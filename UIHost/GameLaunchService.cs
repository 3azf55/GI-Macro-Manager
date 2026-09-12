// Game launch / LoadLibraryW sequence adapted from PowerPaimon, MIT License,
// commit 09eddc6393714900cca0fb55bb83cb490acf09b8.
// See THIRD_PARTY_NOTICES.md and FpsUnlocker/LICENSE-UPSTREAM.txt.
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Reflection.PortableExecutable;
using System.Security.Cryptography;
using System.Text;

namespace UMM.UI;

internal static class GameLaunchService
{
    public static void Launch(string gamePath)
    {
        if (!GameDllSettingsStore.IsValidGamePath(gamePath))
            throw new InvalidOperationException("Select an existing game executable in Startup first.");
        gamePath = Path.GetFullPath(gamePath);
        var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(gamePath.ToUpperInvariant())))[..24];
        using var launchMutex = new Mutex(true, $@"Local\MacroManager.GameLaunch.{key}", out var owner);
        if (!owner) throw new InvalidOperationException("This game is already being launched.");
        try
        {
            foreach (var candidate in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(gamePath)))
            {
                using (candidate)
                {
                    // Match the engine's existing duplicate-game protection.
                    if (!candidate.HasExited)
                        throw new InvalidOperationException("The selected game is already running. Close it before applying DLL changes.");
                }
            }
            var profile = new GameDllSettingsStore().Get();
            var paths = profile.Enabled ? profile.Paths : Array.Empty<string>();
            // Complete preflight before creating the game process.
            foreach (var path in paths) GameDllSettingsStore.ValidateDllFile(path);
            if (paths.Length == 0)
            {
                using var game = Process.Start(new ProcessStartInfo(gamePath) {
                    WorkingDirectory = Path.GetDirectoryName(gamePath)!, UseShellExecute = true
                });
                if (game is null) throw new InvalidOperationException("Windows could not start the selected game.");
                return;
            }
            if (RuntimeInformation.ProcessArchitecture != Architecture.X64)
                throw new InvalidOperationException("Build and run the x64 UI host to load game DLLs.");

            // The remote loader address is resolved by this x64 host. Check
            // only the target executable's architecture, never DLL metadata.
            using (var gameStream = File.OpenRead(gamePath))
            using (var gameImage = new PEReader(gameStream))
            {
                if (gameImage.PEHeaders.CoffHeader.Machine != Machine.Amd64)
                    throw new InvalidOperationException("Additional DLL loading requires an x64 game executable.");
            }

            var startup = new StartupInfo { Size = Marshal.SizeOf<StartupInfo>() };
            if (!CreateProcessW(gamePath, new StringBuilder($"\"{gamePath}\""), 0, 0, false, 0, 0,
                    Path.GetDirectoryName(gamePath)!, ref startup, out var processInfo))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Windows could not start the selected game.");
            try
            {
                using var process = Process.GetProcessById((int)processInfo.ProcessId);
                var remoteLoader = ResolveRemoteLoader(process);
                foreach (var path in paths)
                    LoadDll(process, processInfo.Process, remoteLoader, path);
            }
            catch (Exception exception)
            {
                // Do not silently report success or terminate a running game.
                throw new InvalidOperationException(
                    "The game started, but additional DLL loading failed. " + exception.Message +
                    " Close the game before retrying; any DLLs already loaded remain active.", exception);
            }
            finally
            {
                CloseHandle(processInfo.Thread);
                CloseHandle(processInfo.Process);
            }
        }
        finally { launchMutex.ReleaseMutex(); }
    }

    private static nint ResolveRemoteLoader(Process process)
    {
        var kernel = GetModuleHandleW("kernel32.dll");
        var loader = GetProcAddress(kernel, "LoadLibraryW");
        if (loader == 0 || !GetModuleHandleExW(0x6, loader, out var owner))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not resolve the Windows DLL loader.");
        var moduleName = new StringBuilder(32768);
        if (GetModuleFileNameW(owner, moduleName, moduleName.Capacity) == 0)
            throw new Win32Exception(Marshal.GetLastWin32Error());
        var fileName = Path.GetFileName(moduleName.ToString());
        var offset = loader.ToInt64() - owner.ToInt64();
        // Windows can forward LoadLibraryW to another system module. Resolve
        // the owning module and remote base instead of assuming identical ASLR.
        var stopwatch = Stopwatch.StartNew();
        do
        {
            if (process.HasExited) throw new InvalidOperationException("The game exited during startup.");
            try
            {
                process.Refresh();
                foreach (ProcessModule module in process.Modules)
                    if (module.ModuleName.Equals(fileName, StringComparison.OrdinalIgnoreCase))
                        return new nint(module.BaseAddress.ToInt64() + offset);
            }
            catch (Win32Exception) when (stopwatch.ElapsedMilliseconds < 5000) { }
            Thread.Sleep(50);
        } while (stopwatch.ElapsedMilliseconds < 5000);
        throw new InvalidOperationException("The Windows DLL loader was not available in the game process.");
    }

    private static void LoadDll(Process process, nint handle, nint loader, string path)
    {
        var bytes = Encoding.Unicode.GetBytes(path + "\0");
        var memory = VirtualAllocEx(handle, 0, (nuint)bytes.Length, 0x3000, 0x04);
        if (memory == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), $"Could not allocate the DLL path: {path}");
        nint thread = 0;
        var canFree = true;
        try
        {
            if (!WriteProcessMemory(handle, memory, bytes, (nuint)bytes.Length, out var written) || written != (nuint)bytes.Length)
                throw new Win32Exception(Marshal.GetLastWin32Error(), $"Could not write the DLL path: {path}");
            thread = CreateRemoteThread(handle, 0, 0, loader, memory, 0, out _);
            if (thread == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), $"Could not start the DLL loader: {path}");
            // A timeout must not free memory while the remote loader still uses
            // it. That one path buffer is then reclaimed when the game exits.
            canFree = false;
            var wait = WaitForSingleObject(thread, 15000);
            if (wait != 0) throw new InvalidOperationException($"DLL loading timed out or could not be monitored: {path}");
            canFree = true;
            // GetExitCodeThread truncates HMODULE on x64. Verify the full module
            // path in the process instead, so an unrelated DLL is not success.
            process.Refresh();
            foreach (ProcessModule module in process.Modules)
                if (Path.GetFullPath(module.FileName).Equals(Path.GetFullPath(path), StringComparison.OrdinalIgnoreCase))
                    return;
            throw new InvalidOperationException($"Windows did not load {path}. Check its dependencies and compatibility.");
        }
        finally
        {
            if (thread != 0) CloseHandle(thread);
            if (canFree) VirtualFreeEx(handle, memory, 0, 0x8000);
        }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo
    {
        public int Size;
        public nint Reserved, Desktop, Title;
        public uint X, Y, XSize, YSize, XCountChars, YCountChars, FillAttribute, Flags;
        public ushort ShowWindow, ReservedSize;
        public nint Reserved2, StdInput, StdOutput, StdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInformation
    {
        public nint Process, Thread;
        public uint ProcessId, ThreadId;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreateProcessW(string application, StringBuilder commandLine, nint processAttributes,
        nint threadAttributes, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint flags, nint environment,
        string directory, ref StartupInfo startup, out ProcessInformation information);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern nint GetModuleHandleW(string module);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true, ExactSpelling = true)]
    private static extern nint GetProcAddress(nint module, string name);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetModuleHandleExW(uint flags, nint address, out nint module);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, ExactSpelling = true)]
    private static extern uint GetModuleFileNameW(nint module, StringBuilder path, int size);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern nint VirtualAllocEx(nint process, nint address, nuint size, uint allocation, uint protection);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool WriteProcessMemory(nint process, nint address, byte[] data, nuint size, out nuint written);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern nint CreateRemoteThread(nint process, nint attributes, nuint stackSize, nint start,
        nint parameter, uint flags, out uint threadId);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(nint handle, uint milliseconds);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool VirtualFreeEx(nint process, nint address, nuint size, uint freeType);
    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(nint handle);
}
