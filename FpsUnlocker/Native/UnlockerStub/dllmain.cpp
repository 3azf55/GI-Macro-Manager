// FPS unlock implementation adapted from PowerPaimon at commit
// 09eddc6393714900cca0fb55bb83cb490acf09b8 (MIT License).
#include <Windows.h>
#include <winternl.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iterator>
#include <span>
#include <string>
#include <string_view>
#include <vector>

#pragma comment(lib, "ntdll.lib")
#pragma comment(lib, "User32.lib")
extern "C" NTSTATUS NTAPI LdrAddRefDll(ULONG flags, PVOID baseAddress);

namespace
{
    constexpr wchar_t SharedMemoryName[] = L"Global\\6B78D5B5-2C60-4A7B-9F52-7F8F8B0E1750";
    constexpr std::uint8_t FrameratePattern[] = { 0xB9, 0x3C, 0x00, 0x00, 0x00, 0xE8 };

    enum class IpcStatus : std::int32_t
    {
        None = 0,
        Error = 1,
        Ready = 2
    };

    struct alignas(8) IpcData
    {
        volatile std::int32_t Status;
        volatile std::int32_t Framerate;
        volatile std::uint8_t Enabled;
        std::uint8_t Reserved[7];
    };

    static_assert(offsetof(IpcData, Framerate) == 4);
    static_assert(offsetof(IpcData, Enabled) == 8);

    std::int32_t* FramerateAddress = nullptr;

    std::wstring GetModulePath(HMODULE module)
    {
        std::wstring path(MAX_PATH, L'\0');
        for (;;)
        {
            SetLastError(ERROR_SUCCESS);
            const auto length = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
            if (length == 0)
                return {};
            if (length < path.size() - 1 || GetLastError() != ERROR_INSUFFICIENT_BUFFER)
            {
                path.resize(length);
                return path;
            }
            path.resize(path.size() * 2);
        }
    }

    std::vector<std::uint8_t*> FindPattern(std::span<std::uint8_t> bytes)
    {
        std::vector<std::uint8_t*> results;
        if (bytes.size() < std::size(FrameratePattern))
            return results;

        const auto last = bytes.size() - std::size(FrameratePattern);
        for (std::size_t index = 0; index <= last; ++index)
        {
            if (std::memcmp(bytes.data() + index, FrameratePattern, std::size(FrameratePattern)) == 0)
                results.push_back(bytes.data() + index);
        }
        return results;
    }

    bool ResolveFramerateAddress()
    {
        auto* imageBase = reinterpret_cast<std::uint8_t*>(GetModuleHandleW(nullptr));
        if (!imageBase)
            return false;

        const auto* dosHeader = reinterpret_cast<PIMAGE_DOS_HEADER>(imageBase);
        if (dosHeader->e_magic != IMAGE_DOS_SIGNATURE)
            return false;

        const auto* ntHeaders = reinterpret_cast<PIMAGE_NT_HEADERS>(imageBase + dosHeader->e_lfanew);
        if (ntHeaders->Signature != IMAGE_NT_SIGNATURE)
            return false;

        std::span<std::uint8_t> il2cppSection;
        auto* sections = IMAGE_FIRST_SECTION(ntHeaders);
        for (WORD index = 0; index < ntHeaders->FileHeader.NumberOfSections; ++index)
        {
            if (std::memcmp(sections[index].Name, "il2cpp", 6) == 0)
            {
                il2cppSection = { imageBase + sections[index].VirtualAddress, sections[index].Misc.VirtualSize };
                break;
            }
        }

        if (il2cppSection.empty())
            return false;

        for (auto* result : FindPattern(il2cppSection))
        {
            auto* rip = result + 5;
            const auto firstDisplacement = *reinterpret_cast<std::int32_t*>(rip + 1);
            auto* destination = rip + firstDisplacement + 5;
            if (*destination != 0xE9)
                continue;

            while (rip[0] == 0xE8 || rip[0] == 0xE9)
            {
                const auto displacement = *reinterpret_cast<std::int32_t*>(rip + 1);
                rip += displacement + 5;
            }

            const auto displacement = *reinterpret_cast<std::int32_t*>(rip + 2);
            auto* candidate = reinterpret_cast<std::int32_t*>(rip + displacement + 6);

            MEMORY_BASIC_INFORMATION memoryInfo{};
            if (VirtualQuery(candidate, &memoryInfo, sizeof(memoryInfo)) != sizeof(memoryInfo))
                continue;
            if (memoryInfo.State != MEM_COMMIT || (memoryInfo.Protect & 0xFF) != PAGE_READWRITE)
                continue;

            FramerateAddress = candidate;
            return true;
        }

        return false;
    }

    DWORD WINAPI WorkerThread(void* moduleBase)
    {
        const auto processPath = GetModulePath(nullptr);
        if (!processPath.ends_with(L"\\YuanShen.exe") && !processPath.ends_with(L"\\GenshinImpact.exe"))
            return 0;

        const auto mapping = OpenFileMappingW(FILE_MAP_READ | FILE_MAP_WRITE, FALSE, SharedMemoryName);
        if (!mapping)
            return 0;

        auto* ipc = static_cast<IpcData*>(MapViewOfFile(mapping, FILE_MAP_READ | FILE_MAP_WRITE, 0, 0, sizeof(IpcData)));
        if (!ipc)
        {
            CloseHandle(mapping);
            return 0;
        }

        if (!ResolveFramerateAddress())
        {
            InterlockedExchange(reinterpret_cast<volatile LONG*>(&ipc->Status), static_cast<LONG>(IpcStatus::Error));
            UnmapViewOfFile(ipc);
            CloseHandle(mapping);
            return 0;
        }

        // Pin only after setup succeeds so an incompatible build can unload
        // cleanly when the host removes its temporary window hook.
        LdrAddRefDll(1, moduleBase);
        InterlockedExchange(reinterpret_cast<volatile LONG*>(&ipc->Status), static_cast<LONG>(IpcStatus::Ready));
        bool applied = false;
        for (;;)
        {
            if (ipc->Enabled != 0)
            {
                *FramerateAddress = std::clamp(static_cast<std::int32_t>(ipc->Framerate), 10, 420);
                applied = true;
            }
            else if (applied)
            {
                *FramerateAddress = 60;
                applied = false;
            }
            Sleep(62);
        }
    }
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, void*)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        DisableThreadLibraryCalls(instance);
        if (const auto thread = CreateThread(nullptr, 0, WorkerThread, instance, 0, nullptr))
            CloseHandle(thread);
    }
    return TRUE;
}

extern "C" __declspec(dllexport) LRESULT CALLBACK WndProc(int code, WPARAM wParam, LPARAM lParam)
{
    return CallNextHookEx(nullptr, code, wParam, lParam);
}