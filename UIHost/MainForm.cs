using System.Diagnostics;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace UMM.UI;

public sealed class MainForm : Form
{
    private const int WmNcLButtonDown = 0x00A1;
    private const int HtCaption = 0x0002;

    private const int DefaultClientWidth = 1120;
    private const int DefaultClientHeight = 720;

    private static readonly IReadOnlyDictionary<string, IReadOnlyDictionary<string, int>>
        WebEngineCommandSchema = new Dictionary<string, IReadOnlyDictionary<string, int>>(
            StringComparer.Ordinal)
        {
            ["requestState"] = CommandFields(),
            ["setCharacter"] = CommandFields(("value", 50)),
            ["setCombo"] = CommandFields(("value", 120)),
            ["setAppMode"] = CommandFields(("value", 32)),
            ["setMacroEnabled"] = CommandFields(("value", 8)),
            ["setSoundsEnabled"] = CommandFields(("value", 8)),
            ["setSkipStopMode"] = CommandFields(("value", 16)),
            ["importMacro"] = CommandFields(
                ("character", 50)),
            ["editMacro"] = CommandFields(
                ("comboId", 120),
                ("comboName", 60),
                ("tooltip", 80),
                ("tag", 32)),
            ["deleteMacro"] = CommandFields(("comboId", 120)),
            ["exportMacro"] = CommandFields(("comboId", 120)),
            ["reorderMacros"] = CommandFields(("character", 50), ("comboIds", 16 * 1024)),
            ["setHotkey"] = CommandFields(("target", 32), ("value", 32)),
            ["resetHotkeys"] = CommandFields(),
            ["setAutoLaunchEnabled"] = CommandFields(("value", 8)),
            ["startGame"] = CommandFields(),
            ["clearAutoLaunch"] = CommandFields(),
            ["reloadEngine"] = CommandFields(),
            ["exitEngine"] = CommandFields()
        };

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
    private readonly string _lastUpdateCheckPath;
    private readonly GitHubUpdateService _updateService = new();
    private readonly CancellationTokenSource _lifetimeCancellation = new();
    private UpdateCheckResult? _availableUpdate;
    private bool _webReady;
    private bool _engineConnected;
    private bool _windowPlacementReady;
    private bool _macroRunning;
    private bool _updateOperationInProgress;
    private bool _closingForUpdate;
    private DateTime _lastStateWriteUtc = DateTime.MinValue;
    private DateTime _lastErrorWriteUtc = DateTime.MinValue;

    public MainForm(
        int enginePid,
        string rootDirectory,
        bool enableDevTools,
        EventWaitHandle activationEvent)
    {
        _enginePid = enginePid;
        _rootDirectory = Path.GetFullPath(rootDirectory);
        _enableDevTools = enableDevTools;
        _activationEvent = activationEvent;

        var settingsDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MacroManager");
        Directory.CreateDirectory(settingsDirectory);
        _windowPlacementPath = Path.Combine(settingsDirectory, "window-placement.json");
        _lastUpdateCheckPath = Path.Combine(settingsDirectory, "last-update-check.txt");

        _bridgeDirectory = Path.Combine(_rootDirectory, "bridge");
        _commandsDirectory = Path.Combine(_bridgeDirectory, "commands");
        _stateFile = Path.Combine(_bridgeDirectory, "state.txt");
        _errorFile = Path.Combine(_bridgeDirectory, "error.txt");

        Directory.CreateDirectory(_commandsDirectory);

        Text = "Macro Manager";
        AutoScaleMode = AutoScaleMode.Dpi;
        FormBorderStyle = FormBorderStyle.None;
        MaximizeBox = false;
        MinimizeBox = true;
        SizeGripStyle = SizeGripStyle.Hide;
        ShowIcon = false;
        BackColor = Color.FromArgb(15, 17, 23);

        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(DefaultClientWidth, DefaultClientHeight);
        MinimumSize = new Size(DefaultClientWidth, DefaultClientHeight);
        MaximumSize = new Size(DefaultClientWidth, DefaultClientHeight);
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
            _windowPlacementReady = true;
            _singleInstanceTimer.Start();
            await InitializeWebViewAsync();
        };
        FormClosing += OnFormClosing;

        Log($"UI started. Engine PID argument={_enginePid}; UI HWND={Handle}.");
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == CopyDataMessageReader.WmCopyData)
        {
            var payload = CopyDataMessageReader.Read(message.LParam);
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
                BeginFileBridge();
                PostPreviousUpdateResult();
                if (ShouldRunAutomaticUpdateCheck())
                {
                    _ = CheckForUpdatesAsync(manual: false);
                }
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
            var rawMessage = args.WebMessageAsJson;
            if (string.IsNullOrEmpty(rawMessage) ||
                rawMessage.Length > LineProtocol.MaximumPayloadLength)
            {
                return;
            }

            using var document = JsonDocument.Parse(rawMessage);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !root.TryGetProperty("action", out var actionElement) ||
                actionElement.ValueKind != JsonValueKind.String)
            {
                return;
            }

            var action = actionElement.GetString() ?? string.Empty;
            if (!LineProtocol.TryNormalizeCommandValue(action, 64, out var normalizedAction) ||
                !normalizedAction.Equals(action, StringComparison.Ordinal))
            {
                return;
            }

            action = normalizedAction;
            switch (action)
            {
                case "windowClose":
                    Close();
                    return;
                case "windowMinimize":
                    WindowState = FormWindowState.Minimized;
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
                case "checkForUpdates":
                    _ = CheckForUpdatesAsync(manual: true);
                    return;
                case "installUpdate":
                    _ = InstallAvailableUpdateAsync();
                    return;
            }

            if (!TryBuildWebEngineCommand(root, action, out var values))
            {
                PostToWeb(new Dictionary<string, string>
                {
                    ["type"] = "error",
                    ["message"] = "The interface command was rejected by the input policy."
                });
                return;
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
            Close();
            return;
        }

        _engineConnected = true;
        Log($"Received optional WM_COPYDATA engine message type={type}.");
        PostToWeb(message);
    }

    private static IReadOnlyDictionary<string, int> CommandFields(
        params (string Name, int MaximumLength)[] fields) =>
        fields.ToDictionary(
            field => field.Name,
            field => field.MaximumLength,
            StringComparer.Ordinal);

    private static bool TryBuildWebEngineCommand(
        JsonElement root,
        string action,
        out Dictionary<string, string?> values)
    {
        values = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
        if (!WebEngineCommandSchema.TryGetValue(action, out var allowedFields))
        {
            return false;
        }

        foreach (var property in root.EnumerateObject())
        {
            if (property.NameEquals("action"))
            {
                continue;
            }

            if (!allowedFields.TryGetValue(property.Name, out var maximumLength) ||
                property.Value.ValueKind is JsonValueKind.Object or JsonValueKind.Array or JsonValueKind.Undefined)
            {
                return false;
            }

            var rawValue = property.Value.ValueKind switch
            {
                JsonValueKind.True => "1",
                JsonValueKind.False => "0",
                JsonValueKind.Null => string.Empty,
                JsonValueKind.String => property.Value.GetString() ?? string.Empty,
                _ => property.Value.GetRawText()
            };

            if (!LineProtocol.TryNormalizeCommandValue(rawValue, maximumLength, out var normalizedValue))
            {
                return false;
            }

            if (!values.TryAdd(property.Name, normalizedValue))
            {
                return false;
            }
        }

        return true;
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

        SendEngineCommand("uiReady", reportFailure: false);

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

            return;
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
            _macroRunning = state.TryGetValue("macroRunning", out var macroRunningText) &&
                (macroRunningText.Equals("1", StringComparison.OrdinalIgnoreCase) ||
                 macroRunningText.Equals("true", StringComparison.OrdinalIgnoreCase));
            PostToWeb(state);
        }
        catch (IOException)
        {
            // The engine may be replacing the state file atomically.
        }
        catch (UnauthorizedAccessException)
        {
            Log("The UI cannot read the engine state file.");
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

        if (stream.Length <= 0 || stream.Length > LineProtocol.MaximumPayloadLength)
        {
            return string.Empty;
        }

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
            exception is UnauthorizedAccessException ||
            exception is InvalidDataException)
        {
            Log($"Failed to queue command action={action}: {exception.Message}");

            if (reportFailure)
            {
                PostToWeb(new Dictionary<string, string>
                {
                    ["type"] = "error",
                    ["message"] = "The command could not be delivered to the macro engine."
                });
            }

            return false;
        }
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
                DefaultClientWidth,
                DefaultClientHeight);

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
            var width = DefaultClientWidth;
            var height = DefaultClientHeight;
            var maxX = Math.Max(
                workingArea.Left,
                workingArea.Right - width);
            var maxY = Math.Max(
                workingArea.Top,
                workingArea.Bottom - height);
            var x = Math.Clamp(placement.X, workingArea.Left, maxX);
            var y = Math.Clamp(placement.Y, workingArea.Top, maxY);

            StartPosition = FormStartPosition.Manual;
            Bounds = new Rectangle(x, y, width, height);
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
            var placement = new WindowPlacement
            {
                X = Left,
                Y = Top
            };

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
        _lifetimeCancellation.Cancel();

        if (!_closingForUpdate)
        {
            SendEngineCommand("uiClosed", reportFailure: false);
        }

        _updateService.Dispose();
    }

    private async Task CheckForUpdatesAsync(bool manual)
    {
        if (_updateOperationInProgress)
        {
            if (manual)
            {
                PostUpdateStatus(
                    "busy",
                    "An update operation is already in progress.",
                    manual: true);
            }

            return;
        }

        _updateOperationInProgress = true;
        PostUpdateStatus(
            "checking",
            "Checking GitHub for the latest release…",
            manual);

        try
        {
            var currentVersion = GitHubUpdateService.NormalizeVersion(
                typeof(MainForm).Assembly.GetName().Version ?? new Version(0, 0, 0, 0));

            var result = await _updateService.CheckAsync(
                currentVersion,
                _lifetimeCancellation.Token);

            _availableUpdate = result.Status == UpdateAvailability.Available
                ? result
                : null;

            RecordAutomaticUpdateCheck();

            switch (result.Status)
            {
                case UpdateAvailability.NoRelease:
                    PostUpdateStatus(
                        "noRelease",
                        "No published GitHub release is available yet.",
                        manual,
                        result);
                    break;

                case UpdateAvailability.Current:
                    PostUpdateStatus(
                        "current",
                        $"You are using the latest version ({FormatVersion(result.CurrentVersion)}).",
                        manual,
                        result);
                    break;

                case UpdateAvailability.Available:
                    var canInstall = result.Asset is not null && CanSelfUpdate();
                    var message = result.Asset is null
                        ? $"{result.TagName} is available, but the release has no runtime ZIP asset."
                        : canInstall
                            ? $"{result.TagName} is available and ready to install."
                            : $"{result.TagName} is available. Install it from the Releases page because this is not a packaged runtime build.";

                    PostUpdateStatus(
                        "available",
                        message,
                        manual,
                        result,
                        canInstall);
                    break;
            }
        }
        catch (OperationCanceledException) when (_lifetimeCancellation.IsCancellationRequested)
        {
            // The application is closing.
        }
        catch (HttpRequestException exception)
        {
            PostUpdateStatus(
                "error",
                $"GitHub could not be reached: {exception.Message}",
                manual);
        }
        catch (Exception exception)
        {
            PostUpdateStatus(
                "error",
                $"The update check failed: {exception.Message}",
                manual);
        }
        finally
        {
            _updateOperationInProgress = false;
        }
    }

    private async Task InstallAvailableUpdateAsync()
    {
        if (_availableUpdate is null)
        {
            await CheckForUpdatesAsync(manual: true);
            if (_availableUpdate is null)
            {
                return;
            }
        }

        if (_updateOperationInProgress)
        {
            PostUpdateStatus(
                "busy",
                "An update operation is already in progress.",
                manual: true,
                _availableUpdate);
            return;
        }

        if (!_engineConnected)
        {
            PostUpdateStatus(
                "error",
                "The macro engine must be connected before installing an update.",
                manual: true,
                _availableUpdate);
            return;
        }

        if (_macroRunning)
        {
            PostUpdateStatus(
                "error",
                "Release the macro trigger before installing an update.",
                manual: true,
                _availableUpdate);
            return;
        }

        if (_availableUpdate.Asset is null)
        {
            PostUpdateStatus(
                "error",
                "This release does not contain an installable runtime ZIP.",
                manual: true,
                _availableUpdate);
            return;
        }

        if (!CanSelfUpdate())
        {
            PostUpdateStatus(
                "error",
                "Automatic installation is available only in a packaged runtime build. Open the release page to update this development copy.",
                manual: true,
                _availableUpdate);
            return;
        }

        var confirmation = MessageBox.Show(
            this,
            $"Install {_availableUpdate.TagName}?\n\n" +
            "Macro Manager will close, replace its application files, preserve settings and custom macros, then restart.",
            "Install update",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Information,
            MessageBoxDefaultButton.Button2);

        if (confirmation != DialogResult.Yes)
        {
            return;
        }

        _updateOperationInProgress = true;
        var progress = new Progress<int>(percentage =>
        {
            PostUpdateStatus(
                "downloading",
                $"Downloading {_availableUpdate.TagName}… {percentage}%",
                manual: true,
                _availableUpdate,
                canInstall: true,
                progress: percentage);
        });

        try
        {
            PostUpdateStatus(
                "downloading",
                $"Downloading {_availableUpdate.TagName}…",
                manual: true,
                _availableUpdate,
                canInstall: true,
                progress: 0);

            var prepared = await _updateService.DownloadAndPrepareAsync(
                _availableUpdate,
                _rootDirectory,
                progress,
                _lifetimeCancellation.Token);

            PostUpdateStatus(
                "installing",
                "The update is ready. Macro Manager is closing to install it…",
                manual: true,
                _availableUpdate,
                canInstall: false,
                progress: 100);

            _ = GitHubUpdateService.StartInstaller(
                prepared,
                _rootDirectory,
                _enginePid,
                Environment.ProcessId);

            _closingForUpdate = true;
            SendEngineCommand("exitEngine", reportFailure: false);
            Close();
        }
        catch (OperationCanceledException) when (_lifetimeCancellation.IsCancellationRequested)
        {
            // The application is closing.
        }
        catch (Exception exception)
        {
            PostUpdateStatus(
                "error",
                $"The update could not be installed: {exception.Message}",
                manual: true,
                _availableUpdate);
        }
        finally
        {
            _updateOperationInProgress = false;
        }
    }

    private void PostPreviousUpdateResult()
    {
        var result = GitHubUpdateService.ReadAndDeletePreviousResult();
        if (result is null)
        {
            return;
        }

        var status = result.Status.Equals("success", StringComparison.OrdinalIgnoreCase)
            ? "installed"
            : "error";
        var message = result.Status.Equals("success", StringComparison.OrdinalIgnoreCase)
            ? $"Updated successfully to {result.Version}."
            : $"The previous update failed: {result.Message}";

        PostUpdateStatus(
            status,
            message,
            manual: true,
            releaseUrl: GitHubUpdateService.ReleasesUrl);
    }

    private void PostUpdateStatus(
        string status,
        string message,
        bool manual,
        UpdateCheckResult? release = null,
        bool canInstall = false,
        int progress = -1,
        string? releaseUrl = null)
    {
        var currentVersion = GitHubUpdateService.NormalizeVersion(
            typeof(MainForm).Assembly.GetName().Version ?? new Version(0, 0, 0, 0));

        PostToWeb(new Dictionary<string, string>
        {
            ["type"] = "updateStatus",
            ["status"] = status,
            ["message"] = message,
            ["manual"] = manual ? "1" : "0",
            ["currentVersion"] = FormatVersion(currentVersion),
            ["latestVersion"] = release?.TagName ?? string.Empty,
            ["releaseName"] = release?.ReleaseName ?? string.Empty,
            ["releaseNotes"] = release?.ReleaseNotes ?? string.Empty,
            ["releaseUrl"] = releaseUrl ?? release?.ReleaseUrl ?? GitHubUpdateService.ReleasesUrl,
            ["assetName"] = release?.Asset?.Name ?? string.Empty,
            ["canInstall"] = canInstall ? "1" : "0",
            ["progress"] = progress >= 0 ? progress.ToString() : string.Empty
        });
    }

    private bool ShouldRunAutomaticUpdateCheck()
    {
        try
        {
            if (!File.Exists(_lastUpdateCheckPath))
            {
                return true;
            }

            var lastCheckUtc = File.GetLastWriteTimeUtc(_lastUpdateCheckPath);
            return DateTime.UtcNow - lastCheckUtc >= TimeSpan.FromHours(6);
        }
        catch
        {
            return true;
        }
    }

    private void RecordAutomaticUpdateCheck()
    {
        try
        {
            File.WriteAllText(
                _lastUpdateCheckPath,
                DateTime.UtcNow.ToString("O"),
                new System.Text.UTF8Encoding(false));
        }
        catch
        {
            // Failure to store the throttle timestamp must not block updates.
        }
    }

    private bool CanSelfUpdate() =>
        File.Exists(Path.Combine(_rootDirectory, "UMM.UI.exe")) &&
        File.Exists(Path.Combine(_rootDirectory, "UMM.Engine.ahk")) &&
        Directory.Exists(Path.Combine(_rootDirectory, "ui"));

    private static string FormatVersion(Version version) =>
        $"v{version.Major}.{version.Minor}.{Math.Max(0, version.Build)}";

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
        if (!root.TryGetProperty("url", out var urlElement) ||
            urlElement.ValueKind != JsonValueKind.String)
        {
            return;
        }

        var url = urlElement.GetString();
        if (string.IsNullOrWhiteSpace(url) ||
            !LineProtocol.TryNormalizeCommandValue(url, 2048, out var normalizedUrl) ||
            !normalizedUrl.Equals(url, StringComparison.Ordinal) ||
            !Uri.TryCreate(normalizedUrl, UriKind.Absolute, out var uri) ||
            !uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
            !string.IsNullOrEmpty(uri.UserInfo))
        {
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
        }
        catch (Exception exception) when (
            exception is Win32Exception or InvalidOperationException)
        {
            // A missing/default browser must not terminate the UI host.
        }
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

    private sealed class WindowPlacement
    {
        public int X { get; init; }
        public int Y { get; init; }
    }
}
