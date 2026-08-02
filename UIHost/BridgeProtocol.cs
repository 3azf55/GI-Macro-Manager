using System.Runtime.InteropServices;
using System.Text;

namespace UMM.UI;

internal static class LineProtocol
{
    public static Dictionary<string, string> Parse(string payload)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var rawLine in payload.Split('\n'))
        {
            var line = rawLine.TrimEnd('\r');
            var separator = line.IndexOf('=');
            if (separator <= 0)
            {
                continue;
            }

            result[line[..separator]] = line[(separator + 1)..];
        }

        return result;
    }

    public static string Serialize(IEnumerable<KeyValuePair<string, string?>> values)
    {
        return string.Join("\n", values.Select(pair =>
            $"{Sanitize(pair.Key)}={Sanitize(pair.Value ?? string.Empty)}"));
    }

    private static string Sanitize(string value) => value.Replace("\r", " ").Replace("\n", " ");
}

internal static class CopyDataMessenger
{
    public const int WmCopyData = 0x004A;

    [StructLayout(LayoutKind.Sequential)]
    private struct CopyDataStruct
    {
        public nint DataId;
        public int ByteCount;
        public nint DataPointer;
    }

    [Flags]
    private enum SendMessageTimeoutFlags : uint
    {
        AbortIfHung = 0x0002,
        Block = 0x0001
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint SendMessageTimeout(
        nint windowHandle,
        uint message,
        nint wParam,
        ref CopyDataStruct lParam,
        SendMessageTimeoutFlags flags,
        uint timeoutMilliseconds,
        out nint result);

    [DllImport("user32.dll")]
    internal static extern bool IsWindow(nint windowHandle);

    public static bool Send(nint targetHwnd, nint senderHwnd, string payload)
    {
        if (targetHwnd == 0 || !IsWindow(targetHwnd))
        {
            return false;
        }

        var bytes = Encoding.Unicode.GetBytes(payload + '\0');
        var dataPointer = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, dataPointer, bytes.Length);
            var copyData = new CopyDataStruct
            {
                DataId = 1,
                ByteCount = bytes.Length,
                DataPointer = dataPointer
            };

            var sendResult = SendMessageTimeout(
                targetHwnd,
                WmCopyData,
                senderHwnd,
                ref copyData,
                SendMessageTimeoutFlags.AbortIfHung | SendMessageTimeoutFlags.Block,
                1500,
                out _);

            return sendResult != 0;
        }
        finally
        {
            Marshal.FreeHGlobal(dataPointer);
        }
    }

    public static string Read(nint lParam)
    {
        if (lParam == 0)
        {
            return string.Empty;
        }

        var copyData = Marshal.PtrToStructure<CopyDataStruct>(lParam);
        if (copyData.DataPointer == 0 || copyData.ByteCount <= 1)
        {
            return string.Empty;
        }

        var characterCount = Math.Max(0, copyData.ByteCount / 2 - 1);
        return Marshal.PtrToStringUni(copyData.DataPointer, characterCount) ?? string.Empty;
    }
}


internal static class EngineWindowLocator
{
    private delegate bool EnumWindowsCallback(nint hwnd, nint lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsCallback callback, nint lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint hwnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(nint hwnd, StringBuilder className, int maxCount);

    public static nint FindAutoHotkeyMainWindow(int processId)
    {
        if (processId <= 0)
        {
            return 0;
        }

        nint match = 0;

        EnumWindows((hwnd, unusedParameter) =>
        {
            GetWindowThreadProcessId(hwnd, out var windowProcessId);
            if (windowProcessId != (uint)processId)
            {
                return true;
            }

            var className = new StringBuilder(128);
            GetClassName(hwnd, className, className.Capacity);
            if (className.ToString().Equals("AutoHotkey", StringComparison.OrdinalIgnoreCase))
            {
                match = hwnd;
                return false;
            }

            return true;
        }, nint.Zero);

        return match;
    }
}
