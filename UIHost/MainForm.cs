using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace UMM.UI;

public sealed class MainForm : Form
{
    private const int WmNcLButtonDown = 0x00A1;
    private const int HtCaption = 0x0002;

    private const int FixedClientWidth = 1120;
    private const int FixedClientHeight = 720;

    private readonly WebView2 _webView = new();
    private readonly string _rootDirectory;
    private readonly bool _enableDevTools;
    private readonly int _enginePid;
    private readonly string _bridgeDirectory;
    private readonly string _commandsDirectory;
    private readonly string _stateFile;
    private readonly string _errorFile;
    private readonly System.Windows.Forms.Timer _bridgeTimer = new();
    private readonly System.Windows.Forms.Timer _singleInstanceTimer = new();
    private readonly EventWaitHandle _activationEvent;
    private readonly System.Windows.Forms.Timer _windowPlacementTimer = new();
    private readonly string _windowPlacementPath;
    private nint _engineHwnd;
    private bool _webReady;
    private bool _engineConnected;
    private bool _windowPlacementReady;
    private DateTime _lastStateWriteUtc = DateTime.MinValue;
    private DateTime _lastErrorWriteUtc = DateTime.MinValue;

    public MainForm(
        nint engineHwnd,
        int enginePid,
        string rootDirectory,
        bool enableDevTools,
        EventWaitHandle activationEvent)
    {
        _engineHwnd = engineHwnd;
        _enginePid = enginePid;
        _rootDirectory = rootDirectory;
        _enableDevTools = enableDevTools;
        _activationEvent = activationEvent;

        var settingsDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MacroManager");
        Directory.CreateDirectory(settingsDirectory);
        _windowPlacementPath = Path.Combine(settingsDirectory, "window-placement.json");

        _bridgeDirectory = Path.Combine(_rootDirectory, "bridge");
        _commandsDirectory = Path.Combine(_bridgeDirectory, "commands");
        _stateFile = Path.Combine(_bridgeDirectory, "state.txt");
        _errorFile = Path.Combine(_bridgeDirectory, "error.txt");

        Directory.CreateDirectory(_commandsDirectory);

        Text = "Macro Manager";
        AutoScaleMode = AutoScaleMode.Dpi;
        FormBorderStyle = FormBorderStyle.None;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowIcon = false;
        BackColor = Color.FromArgb(15, 17, 23);

        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(FixedClientWidth, FixedClientHeight);
        RestoreWindowPlacement();

        // The AutoHotkey engine owns the only notification-area icon.
        // Closing this form exits only the WebView2 host; the engine remains
        // available from its original tray icon and can launch the UI again.
        _webView.Dock = DockStyle.Fill;
        _webView.DefaultBackgroundColor = Color.FromArgb(15, 17, 23);
        Controls.Add(_webView);

        _bridgeTimer.Interval = 200;
        _bridgeTimer.Tick += (_, _) => PollFileBridge();

        _windowPlacementTimer.Interval = 450;
        _windowPlacementTimer.Tick += (_, _) =>
        {
            _windowPlacementTimer.Stop();
            SaveWindowPlacement();
        };

        Move += (_, _) => ScheduleWindowPlacementSave();

        _singleInstanceTimer.Interval = 160;
        _singleInstanceTimer.Tick += (_, _) =>
        {
            if (_activationEvent.WaitOne(0))
            {
                ActivateExistingInstance();
            }
        };

        Shown += async (_, _) =>
        {
            ClientSize = new Size(FixedClientWidth, FixedClientHeight);
            _windowPlacementReady = true;
            _singleInstanceTimer.Start();
            await InitializeWebViewAsync();
        };
        FormClosing += OnFormClosing;

        Log($"UI started. Engine HWND argument={_engineHwnd}; Engine PID argument={_enginePid}; UI HWND={Handle}.");
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == CopyDataMessenger.WmCopyData)
        {
            var payload = CopyDataMessenger.Read(message.LParam);
            if (!string.IsNullOrWhiteSpace(payload))
            {
                BeginInvoke(new Action(() => HandleEnginePayload(payload)));
            }

            message.Result = (nint)1;
            return;
        }

        base.WndProc(ref message);
    }

    private async Task InitializeWebViewAsync()
    {
        try
        {
            var userDataDirectory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "UltimateMacroManager",
                "WebView2");

            var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: userDataDirectory);
            await _webView.EnsureCoreWebView2Async(environment);

            var core = _webView.CoreWebView2;
            core.Settings.IsWebMessageEnabled = true;
            core.Settings.AreDefaultContextMenusEnabled = _enableDevTools;
            core.Settings.AreDevToolsEnabled = _enableDevTools;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.IsZoomControlEnabled = false;

            var uiDirectory = Path.Combine(AppContext.BaseDirectory, "ui");
            if (!Directory.Exists(uiDirectory))
            {
                throw new DirectoryNotFoundException($"UI folder was not found: {uiDirectory}");
            }

            core.SetVirtualHostNameToFolderMapping(
                "app.umm",
                uiDirectory,
                CoreWebView2HostResourceAccessKind.DenyCors);

            var assetsDirectory = Path.Combine(_rootDirectory, "Assets");
            Directory.CreateDirectory(assetsDirectory);
            core.SetVirtualHostNameToFolderMapping(
                "assets.umm",
                assetsDirectory,
                CoreWebView2HostResourceAccessKind.Allow);

            core.WebMessageReceived += OnWebMessageReceived;
            core.NavigationCompleted += (_, args) =>
            {
                if (!args.IsSuccess)
                {
                    MessageBox.Show(
                        $"The interface could not be loaded: {args.WebErrorStatus}",
                        "Macro Manager",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    return;
                }

                _webReady = true;
                PostToWeb(new Dictionary<string, string>
                {
                    ["type"] = "connection",
                    ["connected"] = "0",
                    ["status"] = "connecting"
                });
                BeginFileBridge();
            };

            core.Navigate("https://app.umm/index.html");
        }
        catch (WebView2RuntimeNotFoundException)
        {
            MessageBox.Show(
                "Microsoft Edge WebView2 Runtime is not installed. Install the Evergreen WebView2 Runtime, then start the program again.",
                "WebView2 Runtime required",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            Close();
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                exception.Message,
                "Unable to start the interface",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            Close();
        }
    }

    private void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs args)
    {
        if (!args.Source.StartsWith("https://app.umm/", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        try
        {
            using var document = JsonDocument.Parse(args.WebMessageAsJson);
            var root = document.RootElement;
            if (!root.TryGetProperty("action", out var actionElement))
            {
                return;
            }

            var action = actionElement.GetString() ?? string.Empty;
            switch (action)
            {
                case "windowClose":
                            Close();
                    return;
                case "windowDrag":
                    BeginWindowDrag();
                    return;
                case "browseAutoLaunch":
                    BrowseForExecutable();
                    return;
                case "openExternal":
                    OpenExternal(root);
                    return;
            }

            var values = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
            foreach (var property in root.EnumerateObject())
            {
                values[property.Name] = property.Value.ValueKind switch
                {
                    JsonValueKind.True => "1",
                    JsonValueKind.False => "0",
                    JsonValueKind.Null => string.Empty,
                    _ => property.Value.ToString()
                };
            }

            SendEngineCommand(action, values);
        }
        catch (JsonException)
        {
            PostToWeb(new Dictionary<string, string>
            {
                ["type"] = "error",
                ["message"] = "The interface sent an invalid command."
            });
        }
    }

    private void HandleEnginePayload(string payload)
    {
        var message = LineProtocol.Parse(payload);
        if (!message.TryGetValue("type", out var type))
        {
            return;
        }

        if (type.Equals("engineClosing", StringComparison.OrdinalIgnoreCase))
        {
            _engineConnected = false;
            _engineHwnd = 0;
            Close();
            return;
        }

        _engineConnected = true;
        Log($"Received optional WM_COPYDATA engine message type={type}; engine HWND={_engineHwnd}.");
        PostToWeb(message);
    }

    private void PostToWeb(IReadOnlyDictionary<string, string> message)
    {
        if (!_webReady || _webView.CoreWebView2 is null)
        {
            return;
        }

        var json = JsonSerializer.Serialize(message);
        _webView.CoreWebView2.PostWebMessageAsJson(json);
    }

    private void BeginFileBridge()
    {
        _engineConnected = false;
        _lastStateWriteUtc = DateTime.MinValue;

        // Do not replay the last success/error event merely because the
        // WebView host was reopened. New writes after this point are still
        // detected normally by ReadErrorIfChanged().
        _lastErrorWriteUtc = File.Exists(_errorFile)
            ? File.GetLastWriteTimeUtc(_errorFile)
            : DateTime.MinValue;

        PostConnectionStatus("connecting");
        SendEngineCommand("uiReady", reportFailure: false);
        SendEngineCommand("requestState", reportFailure: false);

        PollFileBridge();
        _bridgeTimer.Start();
    }

    private void PollFileBridge()
    {
        if (!_webReady)
        {
            return;
        }

        var processAlive = IsEngineProcessAlive();

        ReadStateIfChanged();
        ReadErrorIfChanged();

        if (!processAlive)
        {
            if (_engineConnected)
            {
                _engineConnected = false;
            }

            PostConnectionStatus("disconnected");
            return;
        }

        if (!_engineConnected)
        {
            PostConnectionStatus(File.Exists(_stateFile) ? "connecting" : "connecting");
        }
    }

    private void ReadStateIfChanged()
    {
        try
        {
            if (!File.Exists(_stateFile))
            {
                return;
            }

            var writeUtc = File.GetLastWriteTimeUtc(_stateFile);
            if (writeUtc <= _lastStateWriteUtc)
            {
                return;
            }

            var payload = ReadSharedTextFile(_stateFile);
            if (string.IsNullOrWhiteSpace(payload))
            {
                return;
            }

            var state = LineProtocol.Parse(payload);
            if (!state.TryGetValue("type", out var type) ||
                !type.Equals("state", StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            if (state.TryGetValue("enginePid", out var statePidText) &&
                int.TryParse(statePidText, out var statePid) &&
                _enginePid > 0 &&
                statePid != _enginePid)
            {
                return;
            }

            _lastStateWriteUtc = writeUtc;
            _engineConnected = true;
            state["connected"] = "1";
            PostToWeb(state);
        }
        catch (IOException)
        {
            // The engine may be replacing the state file atomically.
        }
        catch (UnauthorizedAccessException)
        {
            PostConnectionStatus("failed");
        }
    }

    private void ReadErrorIfChanged()
    {
        try
        {
            if (!File.Exists(_errorFile))
            {
                return;
            }

            var writeUtc = File.GetLastWriteTimeUtc(_errorFile);
            if (writeUtc <= _lastErrorWriteUtc)
            {
                return;
            }

            var payload = ReadSharedTextFile(_errorFile);
            if (string.IsNullOrWhiteSpace(payload))
            {
                return;
            }

            _lastErrorWriteUtc = writeUtc;
            var message = LineProtocol.Parse(payload);
            PostToWeb(message);
        }
        catch (IOException)
        {
            // Retry on the next timer tick.
        }
    }

    private static string ReadSharedTextFile(string path)
    {
        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete);

        using var reader = new StreamReader(stream, new System.Text.UTF8Encoding(false), true);
        return reader.ReadToEnd();
    }

    private bool IsEngineProcessAlive()
    {
        if (_enginePid <= 0)
        {
            return false;
        }

        try
        {
            using var process = Process.GetProcessById(_enginePid);
            return !process.HasExited;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    private bool SendEngineCommand(
        string action,
        IReadOnlyDictionary<string, string?>? extraValues = null,
        bool reportFailure = true)
    {
        var values = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase)
        {
            ["action"] = action,
            ["uiPid"] = Environment.ProcessId.ToString(),
            ["hwnd"] = Handle.ToInt64().ToString()
        };

        if (extraValues is not null)
        {
            foreach (var pair in extraValues)
            {
                if (!pair.Key.Equals("action", StringComparison.OrdinalIgnoreCase))
                {
                    values[pair.Key] = pair.Value;
                }
            }
        }

        try
        {
            Directory.CreateDirectory(_commandsDirectory);

            var id = $"{DateTime.UtcNow:yyyyMMddHHmmssfffffff}-{Guid.NewGuid():N}";
            var tempPath = Path.Combine(_commandsDirectory, id + ".tmp");
            var commandPath = Path.Combine(_commandsDirectory, id + ".cmd");
            var payload = LineProtocol.Serialize(values);

            File.WriteAllText(tempPath, payload, new System.Text.UTF8Encoding(false));
            File.Move(tempPath, commandPath);

            Log($"Queued file command action={action}; file={Path.GetFileName(commandPath)}.");
            return true;
        }
        catch (Exception exception) when (
            exception is IOException ||
            exception is UnauthorizedAccessException)
        {
            Log($"Failed to queue command action={action}: {exception.Message}");

            if (reportFailure)
            {
                PostConnectionStatus("failed");
            }

            return false;
        }
    }

    private void PostConnectionStatus(string status)
    {
        PostToWeb(new Dictionary<string, string>
        {
            ["type"] = "connection",
            ["connected"] = _engineConnected ? "1" : "0",
            ["status"] = _engineConnected ? "connected" : status
        });
    }

    private void Log(string message)
    {
        try
        {
            var logPath = Path.Combine(_rootDirectory, "UMM.UI.connection.log");
            File.AppendAllText(
                logPath,
                $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} | {message}{Environment.NewLine}");
        }
        catch
        {
            // Diagnostics must never prevent the UI from starting.
        }
    }

    private void ScheduleWindowPlacementSave()
    {
        if (!_windowPlacementReady || WindowState != FormWindowState.Normal)
        {
            return;
        }

        _windowPlacementTimer.Stop();
        _windowPlacementTimer.Start();
    }

    private void RestoreWindowPlacement()
    {
        try
        {
            if (!File.Exists(_windowPlacementPath))
            {
                return;
            }

            var json = File.ReadAllText(_windowPlacementPath);
            var placement = JsonSerializer.Deserialize<WindowPlacement>(json);
            if (placement is null)
            {
                return;
            }

            var requestedBounds = new Rectangle(
                placement.X,
                placement.Y,
                FixedClientWidth,
                FixedClientHeight);

            var targetScreen = Screen.AllScreens
                .OrderByDescending(screen =>
                {
                    var intersection = Rectangle.Intersect(
                        screen.WorkingArea,
                        requestedBounds);
                    return intersection.Width * intersection.Height;
                })
                .FirstOrDefault();

            if (targetScreen is null)
            {
                return;
            }

            var workingArea = targetScreen.WorkingArea;
            var maxX = Math.Max(
                workingArea.Left,
                workingArea.Right - FixedClientWidth);
            var maxY = Math.Max(
                workingArea.Top,
                workingArea.Bottom - FixedClientHeight);
            var x = Math.Clamp(placement.X, workingArea.Left, maxX);
            var y = Math.Clamp(placement.Y, workingArea.Top, maxY);

            StartPosition = FormStartPosition.Manual;
            Location = new Point(x, y);
        }
        catch (Exception exception) when (
            exception is IOException ||
            exception is UnauthorizedAccessException ||
            exception is JsonException)
        {
            Log($"Could not restore window placement: {exception.Message}");
        }
    }

    private void SaveWindowPlacement()
    {
        if (!_windowPlacementReady)
        {
            return;
        }

        try
        {
            var bounds = WindowState == FormWindowState.Normal ? Bounds : RestoreBounds;

            var placement = new WindowPlacement(
                bounds.X,
                bounds.Y);

            var json = JsonSerializer.Serialize(
                placement,
                new JsonSerializerOptions { WriteIndented = true });

            var temporaryPath = _windowPlacementPath + ".tmp";
            File.WriteAllText(temporaryPath, json);
            File.Move(temporaryPath, _windowPlacementPath, overwrite: true);
        }
        catch (Exception exception) when (
            exception is IOException ||
            exception is UnauthorizedAccessException)
        {
            Log($"Could not save window placement: {exception.Message}");
        }
    }

    private void ActivateExistingInstance()
    {
        if (IsDisposed || Disposing)
        {
            return;
        }

        if (WindowState == FormWindowState.Minimized)
        {
            WindowState = FormWindowState.Normal;
        }

        Show();
        ShowInTaskbar = true;
        BringToFront();
        Activate();
        Focus();
    }

    private void OnFormClosing(object? sender, FormClosingEventArgs eventArgs)
    {
        _windowPlacementTimer.Stop();
        SaveWindowPlacement();
        _singleInstanceTimer.Stop();
        _bridgeTimer.Stop();
        SendEngineCommand("uiClosed", reportFailure: false);
    }

    private void BrowseForExecutable()
    {
        using var dialog = new OpenFileDialog
        {
            Title = "Select the game executable",
            Filter = "Executable files (*.exe)|*.exe",
            CheckFileExists = true,
            Multiselect = false,
            RestoreDirectory = true
        };

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            SendEngineCommand("setAutoLaunchPath", new Dictionary<string, string?>
            {
                ["value"] = dialog.FileName
            });
        }
    }

    private static void OpenExternal(JsonElement root)
    {
        if (!root.TryGetProperty("url", out var urlElement))
        {
            return;
        }

        var url = urlElement.GetString();
        if (string.IsNullOrWhiteSpace(url) ||
            (!url.StartsWith("https://", StringComparison.OrdinalIgnoreCase) &&
             !url.StartsWith("http://", StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
    }


    private void BeginWindowDrag()
    {
        ReleaseCapture();
        _ = SendMessage(Handle, WmNcLButtonDown, (nint)HtCaption, 0);
    }

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    private static extern nint SendMessage(nint windowHandle, int message, nint wParam, nint lParam);

    private sealed record WindowPlacement(int X, int Y);
}
