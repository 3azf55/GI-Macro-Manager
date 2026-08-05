// FPS hook and IPC lifecycle adapted from PowerPaimon at commit
// 09eddc6393714900cca0fb55bb83cb490acf09b8 (MIT License).
using System.ComponentModel;
using System.Diagnostics;
using System.IO.MemoryMappedFiles;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace UMM.UI;

internal sealed record FpsUnlockSnapshot(
    bool Enabled,
    int Target,
    string Status,
    string Message,
    bool Available);

internal sealed class FpsUnlockService : IDisposable
{
    private const string SharedMemoryName = @"Global\6B78D5B5-2C60-4A7B-9F52-7F8F8B0E1750";
    private const int IpcSize = 4096;
    private const int StatusOffset = 0;
    private const int FramerateOffset = 4;
    private const int EnabledOffset = 8;
    private const int HookGetMessage = 3;
    private const uint WmNull = 0;

    private readonly object _gate = new();
    private readonly string _settingsPath;
    private readonly string _stubPath;
    private readonly CancellationTokenSource _cancellation = new();
    private readonly Task _monitorTask;

    private MemoryMappedFile? _sharedMemory;
    private MemoryMappedViewAccessor? _sharedMemoryView;
    private nint _stubModule;
    private nint _windowHook;
    private int _attachedProcessId;
    private DateTime _connectionStartedUtc;
    private bool _retryBlocked;
    private bool _enabled;
    private int _target = 120;
    private string _status = "disabled";
    private string _message = "Enable the limiter, then start the game.";
    private bool _disposed;

    public FpsUnlockService(string settingsDirectory, string stubPath)
    {
        _settingsPath = Path.Combine(settingsDirectory, "fps-settings.json");
        _stubPath = Path.GetFullPath(stubPath);
        LoadSettings();

        if (_enabled && !File.Exists(_stubPath))
        {
            _enabled = false;
            _status = "unavailable";
            _message = "The native FPS component is missing from this build.";
            SaveSettings();
        }
        else if (_enabled)
        {
            _status = "waiting";
            _message = "Start the game to apply the selected frame-rate target.";
        }

        _monitorTask = Task.Run(MonitorAsync);
    }

    public FpsUnlockSnapshot GetSnapshot()
    {
        lock (_gate)
        {
            return new FpsUnlockSnapshot(
                _enabled,
                _target,
                _status,
                _message,
                File.Exists(_stubPath));
        }
    }

    public bool SetEnabled(bool enabled)
    {
        lock (_gate)
        {
            var wasEnabled = _enabled;
            if (enabled && !File.Exists(_stubPath))
            {
                _enabled = false;
                _status = "unavailable";
                _message = "The native FPS component is missing from this build.";
                SaveSettings();
                return false;
            }

            _enabled = enabled;
            if (!enabled)
            {
                WriteIpcSettings();
                CleanupHook();
                _status = "disabled";
                _message = "Enable the limiter, then start the game.";
            }
            else
            {
                if (!wasEnabled)
                {
                    CleanupHook();
                    _retryBlocked = false;
                }
                _status = "waiting";
                _message = "Start the game to apply the selected frame-rate target.";
                WriteIpcSettings();
            }

            SaveSettings();
            return true;
        }
    }

    public void SetTarget(int target)
    {
        lock (_gate)
        {
            _target = Math.Clamp(target, 10, 420);
            WriteIpcSettings();
            if (_status == "active")
            {
                _message = $"The game is limited to {_target} FPS.";
            }
            SaveSettings();
        }
    }

    private async Task MonitorAsync()
    {
        try
        {
            while (!_cancellation.IsCancellationRequested)
            {
                lock (_gate)
                {
                    try
                    {
                        Tick();
                    }
                    catch (Exception exception) when (
                        exception is IOException or UnauthorizedAccessException or InvalidOperationException or Win32Exception)
                    {
                        CleanupHook();
                        _status = "error";
                        _message = "The FPS service encountered a Windows process or IPC error.";
                    }
                }

                await Task.Delay(500, _cancellation.Token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (_cancellation.IsCancellationRequested)
        {
            // Normal shutdown.
        }
    }

    private void Tick()
    {
        if (_disposed)
        {
            return;
        }

        if (!File.Exists(_stubPath))
        {
            if (_enabled)
            {
                _enabled = false;
                SaveSettings();
            }
            _status = "unavailable";
            _message = "The native FPS component is missing from this build.";
            return;
        }

        if (!EnsureSharedMemory())
        {
            _status = "error";
            _message = "Shared memory for the FPS component could not be created.";
            return;
        }

        WriteIpcSettings();
        if (!_enabled)
        {
            _status = "disabled";
            _message = "Enable the limiter, then start the game.";
            return;
        }

        var processId = FindGameProcessId();
        if (processId == 0)
        {
            if (_attachedProcessId != 0)
            {
                CleanupHook();
                _attachedProcessId = 0;
                _retryBlocked = false;
                WriteIpcStatus(0);
            }
            _status = "waiting";
            _message = "Start the game to apply the selected frame-rate target.";
            return;
        }

        if (_attachedProcessId == 0)
        {
            _attachedProcessId = processId;
        }
        else if (_attachedProcessId != processId)
        {
            CleanupHook();
            _attachedProcessId = processId;
            _retryBlocked = false;
            WriteIpcStatus(0);
        }

        var ipcStatus = ReadIpcStatus();
        if (ipcStatus == 2)
        {
            CleanupHook();
            _retryBlocked = false;
            _status = "active";
            _message = $"The game is limited to {_target} FPS.";
            return;
        }

        if (ipcStatus == 1)
        {
            CleanupHook();
            _retryBlocked = true;
            _status = "error";
            _message = "The FPS pattern is incompatible with this game version.";
            return;
        }

        if (_retryBlocked)
        {
            return;
        }

        if (_windowHook != 0)
        {
            if (DateTime.UtcNow - _connectionStartedUtc > TimeSpan.FromSeconds(12))
            {
                CleanupHook();
                _retryBlocked = true;
                _status = "error";
                _message = "The FPS component did not respond. Restart the game and try again.";
            }
            else
            {
                _status = "connecting";
                _message = "Connecting the FPS component to the game…";
            }
            return;
        }

        var gameWindow = FindGameWindow(processId);
        if (gameWindow == 0)
        {
            _status = "waiting";
            _message = "Waiting for the game window to become ready…";
            return;
        }

        if (!StartWindowHook(gameWindow))
        {
            _retryBlocked = true;
            _status = "error";
            _message = "Windows blocked the FPS component from connecting to the game.";
            return;
        }

        _status = "connecting";
        _message = "Connecting the FPS component to the game…";
    }

    private bool EnsureSharedMemory()
    {
        if (_sharedMemoryView is not null)
        {
            return true;
        }

        try
        {
            _sharedMemory = MemoryMappedFile.CreateOrOpen(
                SharedMemoryName,
                IpcSize,
                MemoryMappedFileAccess.ReadWrite);
            _sharedMemoryView = _sharedMemory.CreateViewAccessor(
                0,
                IpcSize,
                MemoryMappedFileAccess.ReadWrite);
            return true;
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or PlatformNotSupportedException)
        {
            _sharedMemoryView?.Dispose();
            _sharedMemory?.Dispose();
            _sharedMemoryView = null;
            _sharedMemory = null;
            return false;
        }
    }

    private void WriteIpcSettings()
    {
        if (!EnsureSharedMemory())
        {
            return;
        }

        try
        {
            _sharedMemoryView!.Write(FramerateOffset, _target);
            _sharedMemoryView.Write(EnabledOffset, _enabled ? (byte)1 : (byte)0);
            _sharedMemoryView.Flush();
        }
        catch (Exception exception) when (exception is ObjectDisposedException or IOException)
        {
            _sharedMemoryView?.Dispose();
            _sharedMemory?.Dispose();
            _sharedMemoryView = null;
            _sharedMemory = null;
        }
    }

    private int ReadIpcStatus()
    {
        try
        {
            return _sharedMemoryView?.ReadInt32(StatusOffset) ?? 0;
        }
        catch (Exception exception) when (exception is ObjectDisposedException or IOException)
        {
            return 0;
        }
    }

    private void WriteIpcStatus(int status)
    {
        try
        {
            _sharedMemoryView?.Write(StatusOffset, status);
            _sharedMemoryView?.Flush();
        }
        catch (Exception exception) when (exception is ObjectDisposedException or IOException)
        {
            _sharedMemoryView = null;
            _sharedMemory = null;
        }
    }

    private bool StartWindowHook(nint gameWindow)
    {
        CleanupHook();

        _stubModule = LoadLibraryW(_stubPath);
        if (_stubModule == 0)
        {
            return false;
        }

        var hookProcedure = GetProcAddress(_stubModule, "WndProc");
        if (hookProcedure == 0)
        {
            CleanupHook();
            return false;
        }

        var threadId = GetWindowThreadProcessId(gameWindow, out _);
        if (threadId == 0)
        {
            CleanupHook();
            return false;
        }

        _windowHook = SetWindowsHookExW(HookGetMessage, hookProcedure, _stubModule, threadId);
        if (_windowHook == 0 || !PostThreadMessageW(threadId, WmNull, 0, 0))
        {
            CleanupHook();
            return false;
        }

        _connectionStartedUtc = DateTime.UtcNow;
        return true;
    }

    private void CleanupHook()
    {
        if (_windowHook != 0)
        {
            UnhookWindowsHookEx(_windowHook);
            _windowHook = 0;
        }

        if (_stubModule != 0)
        {
            FreeLibrary(_stubModule);
            _stubModule = 0;
        }
    }

    private static int FindGameProcessId()
    {
        foreach (var processName in new[] { "GenshinImpact", "YuanShen" })
        {
            foreach (var process in Process.GetProcessesByName(processName))
            {
                using (process)
                {
                    try
                    {
                        if (!process.HasExited)
                        {
                            return process.Id;
                        }
                    }
                    catch (Exception exception) when (exception is InvalidOperationException or Win32Exception)
                    {
                        // The process ended while being inspected.
                    }
                }
            }
        }
        return 0;
    }

    private static nint FindGameWindow(int processId)
    {
        nint fallback = 0;
        nint unityWindow = 0;
        EnumWindows((window, _) =>
        {
            GetWindowThreadProcessId(window, out var windowProcessId);
            if (windowProcessId != processId || !IsWindowVisible(window))
            {
                return true;
            }

            fallback = window;
            var className = new StringBuilder(64);
            if (GetClassNameW(window, className, className.Capacity) > 0 &&
                className.ToString().Equals("UnityWndClass", StringComparison.Ordinal))
            {
                unityWindow = window;
                return false;
            }
            return true;
        }, 0);

        return unityWindow != 0 ? unityWindow : fallback;
    }

    private void LoadSettings()
    {
        try
        {
            if (!File.Exists(_settingsPath))
            {
                return;
            }

            var settings = JsonSerializer.Deserialize<FpsSettings>(File.ReadAllText(_settingsPath));
            if (settings is null)
            {
                return;
            }

            _enabled = settings.Enabled;
            _target = Math.Clamp(settings.Target, 10, 420);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or JsonException)
        {
            _enabled = false;
            _target = 120;
        }
    }

    private void SaveSettings()
    {
        try
        {
            var json = JsonSerializer.Serialize(
                new FpsSettings { Enabled = _enabled, Target = _target },
                new JsonSerializerOptions { WriteIndented = true });
            var temporaryPath = _settingsPath + ".tmp";
            File.WriteAllText(temporaryPath, json, new UTF8Encoding(false));
            File.Move(temporaryPath, _settingsPath, overwrite: true);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // A settings write failure must not terminate the UI host.
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }
            _disposed = true;
            _cancellation.Cancel();
            CleanupHook();
            _sharedMemoryView?.Dispose();
            _sharedMemory?.Dispose();
            _sharedMemoryView = null;
            _sharedMemory = null;
        }

        try
        {
            _monitorTask.Wait(TimeSpan.FromSeconds(1));
        }
        catch (AggregateException)
        {
            // Cancellation races are harmless during shutdown.
        }
        _cancellation.Dispose();
    }

    private sealed class FpsSettings
    {
        public FpsSettings() { }

        public bool Enabled { get; set; }
        public int Target { get; set; } = 120;
    }

    private delegate bool EnumWindowsCallback(nint window, nint parameter);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern nint LoadLibraryW(string fileName);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true, SetLastError = true)]
    private static extern nint GetProcAddress(nint module, string procedureName);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FreeLibrary(nint module);

    [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
    private static extern nint SetWindowsHookExW(int hookId, nint hookProcedure, nint module, uint threadId);

    [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(nint hook);

    [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostThreadMessageW(uint threadId, uint message, nint wParam, nint lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint window, out uint processId);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(EnumWindowsCallback callback, nint parameter);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(nint window);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int GetClassNameW(nint window, StringBuilder className, int maximumCount);
}
