using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace UMM.UI;

internal sealed class KeyboardRecordingService : IDisposable
{
    private const int WhKeyboardLl = 13;
    private const int WhMouseLl = 14;
    private const int WmKeyDown = 0x0100;
    private const int WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104;
    private const int WmSysKeyUp = 0x0105;
    private const int WmLButtonDown = 0x0201;
    private const int WmLButtonUp = 0x0202;
    private const int WmRButtonDown = 0x0204;
    private const int WmRButtonUp = 0x0205;
    private const int WmMButtonDown = 0x0207;
    private const int WmMButtonUp = 0x0208;
    private const int WmMouseWheel = 0x020A;
    private const int WmXButtonDown = 0x020B;
    private const int WmXButtonUp = 0x020C;
    private const uint LlkhfInjected = 0x10;
    private const uint LlmhfInjected = 0x01;
    private const int MaximumTransitions = 2_000;

    private static readonly HashSet<string> SupportedKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        "LButton", "RButton", "MButton", "WheelUp", "WheelDown",
        "Q", "E", "R", "F", "W", "A", "S", "D", "Shift", "Space",
        "1", "2", "3", "4", "5"
    };

    private static readonly HashSet<string> SupportedToggleHotkeys = new(StringComparer.OrdinalIgnoreCase)
    {
        "XButton1", "XButton2", "Space", "Tab", "CapsLock", "Backspace", "Enter",
        "Insert", "Delete", "Home", "End", "PgUp", "PgDn", "Up", "Down", "Left", "Right",
        "LShift", "RShift", "LControl", "RControl", "LAlt", "RAlt", "AppsKey",
        "Numpad0", "Numpad1", "Numpad2", "Numpad3", "Numpad4", "Numpad5", "Numpad6", "Numpad7", "Numpad8", "Numpad9",
        "NumpadDot", "NumpadAdd", "NumpadSub", "NumpadMult", "NumpadDiv", "NumpadEnter"
    };

    static KeyboardRecordingService()
    {
        foreach (var key in Enumerable.Range('A', 26).Select(value => ((char)value).ToString()))
        {
            SupportedToggleHotkeys.Add(key);
        }
        foreach (var key in Enumerable.Range(0, 10).Select(value => value.ToString()))
        {
            SupportedToggleHotkeys.Add(key);
        }
        foreach (var key in Enumerable.Range(1, 24).Select(value => $"F{value}"))
        {
            SupportedToggleHotkeys.Add(key);
        }
    }

    private readonly object _gate = new();
    private readonly string _settingsPath;
    private readonly LowLevelHookProc _keyboardHookProcedure;
    private readonly LowLevelHookProc _mouseHookProcedure;
    private readonly RecordingOverlayForm _overlay;
    private readonly System.Windows.Forms.Timer _snapshotTimer = new();
    private readonly List<RecordedInputTransition> _transitions = [];
    private readonly HashSet<string> _pressedKeys = new(StringComparer.OrdinalIgnoreCase);
    private nint _keyboardHook;
    private nint _mouseHook;
    private long _recordingStartedTimestamp;
    private long _recordingElapsedMs;
    private bool _available;
    private bool _recording;
    private bool _toggleHotkeyDown;
    private bool _capacityTrimmed;
    private bool _snapshotDirty;
    private bool _disposed;
    private string _sessionId = string.Empty;
    private MacroRecordingSettings _settings;

    public KeyboardRecordingService(string settingsDirectory)
    {
        _settingsPath = Path.Combine(settingsDirectory, "macro-recording.json");
        _settings = LoadSettings();
        _keyboardHookProcedure = KeyboardHookCallback;
        _mouseHookProcedure = MouseHookCallback;
        _overlay = new RecordingOverlayForm();
        _overlay.ToggleRequested += (_, _) => Toggle();

        _snapshotTimer.Interval = 200;
        _snapshotTimer.Tick += (_, _) =>
        {
            if (_recording && (_snapshotDirty || _settings.LastWindowEnabled))
            {
                _snapshotDirty = false;
                PublishSnapshot();
            }
        };
    }

    public event EventHandler<MacroRecordingSnapshot>? SnapshotChanged;

    public void SetAvailable(bool available)
    {
        ThrowIfDisposed();
        if (_available == available)
        {
            PublishSnapshot();
            return;
        }

        _available = available;
        if (available)
        {
            try
            {
                InstallHooks();
            }
            catch
            {
                _available = false;
                throw;
            }
            _overlay.SetRecording(_recording, _settings.ToggleHotkey);
            // Opening the macro editor enables the hooks, but must not show
            // the floating recorder badge until recording actually starts.
            if (_recording)
            {
                _overlay.Reveal(persistent: true);
            }
            else
            {
                _overlay.Hide();
            }
            _snapshotTimer.Start();
        }
        else
        {
            Stop();
            _snapshotTimer.Stop();
            _overlay.Hide();
            UninstallHooks();
        }

        PublishSnapshot();
    }

    public void UpdateSettings(MacroRecordingSettings requested)
    {
        ThrowIfDisposed();
        var allowed = (requested.AllowedKeys ?? [])
            .Where(key => SupportedKeys.Contains(key))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        lock (_gate)
        {
            _settings = new MacroRecordingSettings
            {
                LastWindowEnabled = requested.LastWindowEnabled,
                WindowSeconds = Math.Clamp(requested.WindowSeconds, 1, 600),
                ToggleHotkey = _settings.ToggleHotkey,
                AllowedKeys = allowed
            };
        }

        SaveSettings();
        _overlay.SetRecording(_recording, _settings.ToggleHotkey);
        PublishSnapshot();
    }

    public void SetTheme(string theme)
    {
        _overlay.SetTheme(theme);
    }

    public void SetToggleHotkey(string requestedHotkey)
    {
        ThrowIfDisposed();
        var hotkey = NormalizeToggleHotkey(requestedHotkey);
        if (hotkey.Length == 0 || hotkey.Equals(_settings.ToggleHotkey, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        lock (_gate)
        {
            _settings.ToggleHotkey = hotkey;
            _toggleHotkeyDown = false;
        }
        SaveSettings();
        _overlay.SetRecording(_recording, hotkey);
        PublishSnapshot();
    }

    public void Start()
    {
        ThrowIfDisposed();
        if (!_available || _recording)
        {
            PublishSnapshot();
            return;
        }

        lock (_gate)
        {
            _transitions.Clear();
            _pressedKeys.Clear();
            _capacityTrimmed = false;
            _snapshotDirty = false;
            _sessionId = Guid.NewGuid().ToString("N");
            _recordingStartedTimestamp = Stopwatch.GetTimestamp();
            _recordingElapsedMs = 0;
            _recording = true;
        }

        _overlay.SetRecording(true, _settings.ToggleHotkey);
        _overlay.Reveal(persistent: true);
        PublishSnapshot();
    }

    public void Stop()
    {
        if (_disposed || !_recording)
        {
            return;
        }

        lock (_gate)
        {
            _recordingElapsedMs = ElapsedMilliseconds(
                _recordingStartedTimestamp,
                Stopwatch.GetTimestamp());
            foreach (var key in _pressedKeys)
            {
                _transitions.Add(new RecordedInputTransition
                {
                    Key = key,
                    Action = "up",
                    OffsetMs = _recordingElapsedMs
                });
            }
            _recording = false;
            _pressedKeys.Clear();
        }

        _overlay.SetRecording(false, _settings.ToggleHotkey);
        _overlay.Reveal(persistent: false);
        PublishSnapshot();
    }

    public void Toggle()
    {
        if (_recording)
        {
            Stop();
        }
        else
        {
            Start();
        }
    }

    public MacroRecordingSnapshot GetSnapshot()
    {
        lock (_gate)
        {
            var elapsedMilliseconds = _recordingStartedTimestamp == 0
                ? 0L
                : _recording
                    ? ElapsedMilliseconds(_recordingStartedTimestamp, Stopwatch.GetTimestamp())
                    : _recordingElapsedMs;
            var cutoff = _settings.LastWindowEnabled
                ? Math.Max(0L, elapsedMilliseconds - (_settings.WindowSeconds * 1_000L))
                : 0L;
            var activeAtCutoff = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var transition in _transitions.Where(item => item.OffsetMs < cutoff))
            {
                if (transition.Action.Equals("down", StringComparison.OrdinalIgnoreCase))
                {
                    activeAtCutoff.Add(transition.Key);
                }
                else if (transition.Action.Equals("up", StringComparison.OrdinalIgnoreCase))
                {
                    activeAtCutoff.Remove(transition.Key);
                }
            }

            var retained = activeAtCutoff.Select(key => new RecordedInputTransition
            {
                Key = key,
                Action = "down",
                OffsetMs = cutoff
            }).Concat(_transitions.Where(item => item.OffsetMs >= cutoff)).ToList();
            var firstOffset = retained.Count == 0 ? 0L : retained[0].OffsetMs;
            var normalized = retained.Select(item => new RecordedInputTransition
            {
                Key = item.Key,
                Action = item.Action,
                OffsetMs = Math.Max(0L, item.OffsetMs - firstOffset)
            }).ToArray();

            return new MacroRecordingSnapshot
            {
                Available = _available,
                Recording = _recording,
                SessionId = _sessionId,
                ElapsedMs = elapsedMilliseconds,
                CapacityTrimmed = _capacityTrimmed,
                Settings = _settings.Clone(),
                Transitions = normalized
            };
        }
    }

    private void PublishSnapshot()
    {
        if (_disposed)
        {
            return;
        }

        SnapshotChanged?.Invoke(this, GetSnapshot());
    }

    private void RecordTransition(string key, string action)
    {
        lock (_gate)
        {
            if (!_recording || !_settings.AllowedKeys.Contains(key, StringComparer.OrdinalIgnoreCase))
            {
                return;
            }

            if (action.Equals("down", StringComparison.OrdinalIgnoreCase) && !_pressedKeys.Add(key))
            {
                return;
            }
            if (action.Equals("up", StringComparison.OrdinalIgnoreCase) && !_pressedKeys.Remove(key))
            {
                return;
            }

            _transitions.Add(new RecordedInputTransition
            {
                Key = key,
                Action = action,
                OffsetMs = ElapsedMilliseconds(_recordingStartedTimestamp, Stopwatch.GetTimestamp())
            });
            if (_transitions.Count > MaximumTransitions)
            {
                _transitions.RemoveRange(0, _transitions.Count - MaximumTransitions);
                _capacityTrimmed = true;
            }
            _snapshotDirty = true;
        }
    }

    private void RecordWheel(string key)
    {
        lock (_gate)
        {
            if (!_recording || !_settings.AllowedKeys.Contains(key, StringComparer.OrdinalIgnoreCase))
            {
                return;
            }

            _transitions.Add(new RecordedInputTransition
            {
                Key = key,
                Action = "tap",
                OffsetMs = ElapsedMilliseconds(_recordingStartedTimestamp, Stopwatch.GetTimestamp())
            });
            if (_transitions.Count > MaximumTransitions)
            {
                _transitions.RemoveRange(0, _transitions.Count - MaximumTransitions);
                _capacityTrimmed = true;
            }
            _snapshotDirty = true;
        }
    }

    private nint KeyboardHookCallback(int code, nint wParam, nint lParam)
    {
        try
        {
            if (code >= 0 && _available)
            {
                var data = Marshal.PtrToStructure<KbdLlHookStruct>(lParam);
                if ((data.Flags & LlkhfInjected) == 0)
                {
                    var message = unchecked((int)wParam.ToInt64());
                    var isDown = message is WmKeyDown or WmSysKeyDown;
                    var isUp = message is WmKeyUp or WmSysKeyUp;
                    var key = MapVirtualKeyCode(data.VirtualKeyCode, data.Flags);
                    if (!string.IsNullOrEmpty(key))
                    {
                        if (HandleToggleHotkey(key, isDown, isUp))
                        {
                            return (nint)1;
                        }
                        else if ((isDown || isUp) && !IsCurrentProcessForegroundWindow())
                        {
                            RecordTransition(key, isDown ? "down" : "up");
                        }
                    }
                }
            }
        }
        catch (Exception)
        {
            // Native hook callbacks must never leak managed exceptions.
        }

        return CallNextHookEx(_keyboardHook, code, wParam, lParam);
    }

    private nint MouseHookCallback(int code, nint wParam, nint lParam)
    {
        try
        {
            if (code >= 0 && _available)
            {
                var data = Marshal.PtrToStructure<MsLlHookStruct>(lParam);
                if ((data.Flags & LlmhfInjected) == 0)
                {
                    var message = unchecked((int)wParam.ToInt64());
                    if (message is WmXButtonDown or WmXButtonUp)
                    {
                        var xButton = ((data.MouseData >> 16) & 0xFFFF) == 1 ? "XButton1" : "XButton2";
                        if (HandleToggleHotkey(xButton, message == WmXButtonDown, message == WmXButtonUp))
                        {
                            return (nint)1;
                        }
                    }

                    if (!IsPointOverCurrentProcessWindow(data.Point))
                    {
                        switch (message)
                        {
                            case WmLButtonDown: RecordTransition("LButton", "down"); break;
                            case WmLButtonUp: RecordTransition("LButton", "up"); break;
                            case WmRButtonDown: RecordTransition("RButton", "down"); break;
                            case WmRButtonUp: RecordTransition("RButton", "up"); break;
                            case WmMButtonDown: RecordTransition("MButton", "down"); break;
                            case WmMButtonUp: RecordTransition("MButton", "up"); break;
                            case WmMouseWheel:
                                var delta = unchecked((short)((data.MouseData >> 16) & 0xFFFF));
                                if (delta != 0) RecordWheel(delta > 0 ? "WheelUp" : "WheelDown");
                                break;
                        }
                    }
                }
            }
        }
        catch (Exception)
        {
            // Native hook callbacks must never leak managed exceptions.
        }

        return CallNextHookEx(_mouseHook, code, wParam, lParam);
    }

    private bool HandleToggleHotkey(string key, bool isDown, bool isUp)
    {
        if (!key.Equals(_settings.ToggleHotkey, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (isDown && !_toggleHotkeyDown)
        {
            _toggleHotkeyDown = true;
            _overlay.Reveal(persistent: _recording);
            Toggle();
        }
        else if (isUp)
        {
            _toggleHotkeyDown = false;
        }
        return true;
    }

    private static string MapVirtualKeyCode(uint virtualKeyCode, uint flags)
    {
        if (virtualKeyCode == 0x0D && (flags & 0x01) != 0)
        {
            return "NumpadEnter";
        }

        return virtualKeyCode switch
        {
            0x08 => "Backspace",
            0x09 => "Tab",
            0x0D => "Enter",
            0x14 => "CapsLock",
            0x20 => "Space",
            0x21 => "PgUp", 0x22 => "PgDn", 0x23 => "End", 0x24 => "Home",
            0x25 => "Left", 0x26 => "Up", 0x27 => "Right", 0x28 => "Down",
            0x2D => "Insert", 0x2E => "Delete",
            >= 0x30 and <= 0x39 => ((char)virtualKeyCode).ToString(),
            >= 0x41 and <= 0x5A => ((char)virtualKeyCode).ToString(),
            0x5D => "AppsKey",
            >= 0x60 and <= 0x69 => $"Numpad{virtualKeyCode - 0x60}",
            0x6A => "NumpadMult", 0x6B => "NumpadAdd", 0x6D => "NumpadSub",
            0x6E => "NumpadDot", 0x6F => "NumpadDiv",
            >= 0x70 and <= 0x87 => $"F{virtualKeyCode - 0x6F}",
            0xA0 => "LShift", 0xA1 => "RShift",
            0xA2 => "LControl", 0xA3 => "RControl",
            0xA4 => "LAlt", 0xA5 => "RAlt",
            _ => string.Empty
        };
    }

    private static string NormalizeToggleHotkey(string? value) =>
        SupportedToggleHotkeys.FirstOrDefault(key =>
            key.Equals((value ?? string.Empty).Trim(), StringComparison.OrdinalIgnoreCase)) ?? string.Empty;

    private static bool IsPointOverCurrentProcessWindow(Point point)
    {
        var window = WindowFromPoint(point);
        if (window == 0)
        {
            return false;
        }

        GetWindowThreadProcessId(window, out var processId);
        return processId == (uint)Environment.ProcessId;
    }

    private static bool IsCurrentProcessForegroundWindow()
    {
        var window = GetForegroundWindow();
        if (window == 0)
        {
            return false;
        }

        GetWindowThreadProcessId(window, out var processId);
        return processId == (uint)Environment.ProcessId;
    }

    private void InstallHooks()
    {
        if (_keyboardHook != 0 || _mouseHook != 0)
        {
            return;
        }

        using var process = Process.GetCurrentProcess();
        using var module = process.MainModule;
        var moduleHandle = GetModuleHandle(module?.ModuleName);
        _keyboardHook = SetWindowsHookEx(WhKeyboardLl, _keyboardHookProcedure, moduleHandle, 0);
        _mouseHook = SetWindowsHookEx(WhMouseLl, _mouseHookProcedure, moduleHandle, 0);
        if (_keyboardHook == 0 || _mouseHook == 0)
        {
            UninstallHooks();
            throw new InvalidOperationException("Unable to start the global input recorder.");
        }
    }

    private void UninstallHooks()
    {
        if (_keyboardHook != 0)
        {
            UnhookWindowsHookEx(_keyboardHook);
            _keyboardHook = 0;
        }
        if (_mouseHook != 0)
        {
            UnhookWindowsHookEx(_mouseHook);
            _mouseHook = 0;
        }
        _toggleHotkeyDown = false;
    }

    private MacroRecordingSettings LoadSettings()
    {
        try
        {
            if (File.Exists(_settingsPath))
            {
                var parsed = JsonSerializer.Deserialize<MacroRecordingSettings>(File.ReadAllText(_settingsPath));
                if (parsed is not null)
                {
                    var allowed = (parsed.AllowedKeys ?? [])
                        .Where(SupportedKeys.Contains)
                        .Distinct(StringComparer.OrdinalIgnoreCase)
                        .ToArray();
                    return new MacroRecordingSettings
                    {
                        LastWindowEnabled = parsed.LastWindowEnabled,
                        WindowSeconds = Math.Clamp(parsed.WindowSeconds, 1, 600),
                        ToggleHotkey = NormalizeToggleHotkey(parsed.ToggleHotkey) is { Length: > 0 } hotkey
                            ? hotkey
                            : "F7",
                        AllowedKeys = allowed
                    };
                }
            }
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        {
            // Invalid local preferences fall back to safe defaults.
        }

        return new MacroRecordingSettings { ToggleHotkey = "F7", AllowedKeys = SupportedKeys.ToArray() };
    }

    private void SaveSettings()
    {
        try
        {
            var temporaryPath = _settingsPath + ".tmp";
            File.WriteAllText(temporaryPath, JsonSerializer.Serialize(_settings));
            File.Move(temporaryPath, _settingsPath, overwrite: true);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // Recording remains available even when preferences cannot persist.
        }
    }

    private static long ElapsedMilliseconds(long start, long end) =>
        Math.Max(0L, (long)((end - start) * 1_000d / Stopwatch.Frequency));

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        Stop();
        _disposed = true;
        _snapshotTimer.Stop();
        _snapshotTimer.Dispose();
        UninstallHooks();
        _overlay.Close();
        _overlay.Dispose();
    }

    private delegate nint LowLevelHookProc(int code, nint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct KbdLlHookStruct
    {
        public uint VirtualKeyCode;
        public uint ScanCode;
        public uint Flags;
        public uint Time;
        public nuint ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MsLlHookStruct
    {
        public Point Point;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public nuint ExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SetWindowsHookEx(
        int hookId,
        LowLevelHookProc hookProcedure,
        nint moduleHandle,
        uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(nint hookHandle);

    [DllImport("user32.dll")]
    private static extern nint CallNextHookEx(nint hookHandle, int code, nint wParam, nint lParam);

    [DllImport("user32.dll")]
    private static extern nint WindowFromPoint(Point point);

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint windowHandle, out uint processId);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint GetModuleHandle(string? moduleName);
}

internal sealed class MacroRecordingSettings
{
    public bool LastWindowEnabled { get; set; } = true;
    public int WindowSeconds { get; set; } = 30;
    public string ToggleHotkey { get; set; } = "F7";
    public string[] AllowedKeys { get; set; } = [];

    public MacroRecordingSettings Clone() => new()
    {
        LastWindowEnabled = LastWindowEnabled,
        WindowSeconds = WindowSeconds,
        ToggleHotkey = ToggleHotkey,
        AllowedKeys = [.. AllowedKeys]
    };
}

internal sealed class MacroRecordingSnapshot
{
    public bool Available { get; set; }
    public bool Recording { get; set; }
    public string SessionId { get; set; } = string.Empty;
    public long ElapsedMs { get; set; }
    public bool CapacityTrimmed { get; set; }
    public MacroRecordingSettings Settings { get; set; } = new();
    public RecordedInputTransition[] Transitions { get; set; } = [];
}

internal sealed class RecordedInputTransition
{
    public string Key { get; set; } = string.Empty;
    public string Action { get; set; } = string.Empty;
    public long OffsetMs { get; set; }
}

internal sealed class RecordingOverlayForm : Form
{
    private readonly Button _button = new();
    private readonly System.Windows.Forms.Timer _hideTimer = new() { Interval = 2800 };
    private bool _recording;
    private bool _lightTheme;

    public RecordingOverlayForm()
    {
        AutoScaleMode = AutoScaleMode.Dpi;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        ClientSize = new Size(104, 38);
        Padding = new Padding(1);

        _button.Dock = DockStyle.Fill;
        _button.FlatStyle = FlatStyle.Flat;
        _button.FlatAppearance.BorderSize = 0;
        _button.Cursor = Cursors.Hand;
        _button.Font = new Font("Segoe UI Semibold", 8.25f, FontStyle.Bold);
        _button.Margin = Padding.Empty;
        _button.Click += (_, _) => ToggleRequested?.Invoke(this, EventArgs.Empty);
        Controls.Add(_button);

        _hideTimer.Tick += (_, _) =>
        {
            _hideTimer.Stop();
            if (!_recording)
            {
                Hide();
            }
        };
        Shown += (_, _) => PositionOverlay();
        SizeChanged += (_, _) => ApplyRoundedRegion();
        ApplyRoundedRegion();
        ApplyPalette();
    }

    public event EventHandler? ToggleRequested;

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            const int WsExToolWindow = 0x00000080;
            const int WsExNoActivate = 0x08000000;
            var parameters = base.CreateParams;
            parameters.ExStyle |= WsExToolWindow | WsExNoActivate;
            return parameters;
        }
    }

    public void SetRecording(bool recording, string hotkey)
    {
        _recording = recording;
        _button.Text = recording ? "● RECORDING" : $"● REC {hotkey}";
        ApplyPalette();
        _button.AccessibleName = recording ? "Stop macro recording" : "Start macro recording";
        _button.TextAlign = ContentAlignment.MiddleCenter;
        Text = $"Macro recorder ({hotkey})";

        if (recording)
        {
            _hideTimer.Stop();
        }
    }

    public void SetTheme(string theme)
    {
        _lightTheme = string.Equals(theme, "light", StringComparison.Ordinal);
        ApplyPalette();
    }

    private void ApplyPalette()
    {
        if (_recording)
        {
            BackColor = _lightTheme ? Color.FromArgb(52, 170, 116) : Color.FromArgb(91, 226, 161);
            _button.BackColor = _lightTheme ? Color.FromArgb(226, 247, 237) : Color.FromArgb(24, 105, 72);
            _button.ForeColor = _lightTheme ? Color.FromArgb(18, 105, 69) : Color.FromArgb(235, 255, 246);
            _button.FlatAppearance.MouseOverBackColor = _lightTheme ? Color.FromArgb(210, 241, 226) : Color.FromArgb(30, 125, 85);
            _button.FlatAppearance.MouseDownBackColor = _lightTheme ? Color.FromArgb(194, 233, 215) : Color.FromArgb(20, 87, 60);
            return;
        }

        BackColor = _lightTheme ? Color.FromArgb(183, 197, 226) : Color.FromArgb(93, 111, 159);
        _button.BackColor = _lightTheme ? Color.FromArgb(248, 250, 253) : Color.FromArgb(31, 37, 50);
        _button.ForeColor = _lightTheme ? Color.FromArgb(48, 63, 87) : Color.FromArgb(226, 232, 246);
        _button.FlatAppearance.MouseOverBackColor = _lightTheme ? Color.FromArgb(235, 240, 248) : Color.FromArgb(42, 50, 67);
        _button.FlatAppearance.MouseDownBackColor = _lightTheme ? Color.FromArgb(222, 229, 240) : Color.FromArgb(25, 30, 42);
    }

    public void Reveal(bool persistent)
    {
        _hideTimer.Stop();
        PositionOverlay();
        if (!Visible)
        {
            Show();
        }
        BringToFront();
        if (!persistent && !_recording)
        {
            _hideTimer.Start();
        }
    }

    private void PositionOverlay()
    {
        var workingArea = Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(
            Math.Max(workingArea.Left, workingArea.Right - Width - 22),
            workingArea.Top + 72);
    }

    private void ApplyRoundedRegion()
    {
        var regionHandle = CreateRoundRectRgn(0, 0, Width + 1, Height + 1, 18, 18);
        if (regionHandle == 0)
        {
            return;
        }

        var nextRegion = Region.FromHrgn(regionHandle);
        _ = DeleteObject(regionHandle);
        var previousRegion = Region;
        Region = nextRegion;
        previousRegion?.Dispose();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _hideTimer.Dispose();
        }
        base.Dispose(disposing);
    }

    [DllImport("gdi32.dll")]
    private static extern nint CreateRoundRectRgn(int left, int top, int right, int bottom, int width, int height);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteObject(nint handle);
}
