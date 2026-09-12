using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

namespace UMM.UI;

internal sealed record FpsMonitorSnapshot(
    bool Enabled,
    bool Available,
    string Status,
    string Message,
    int? CurrentFps);

internal sealed class FpsMonitorService : IDisposable
{
    private const string SessionName = "UMM-FPS";
    private static readonly TimeSpan SampleWindow = TimeSpan.FromMilliseconds(1250);
    private static readonly TimeSpan StaleSampleThreshold = TimeSpan.FromSeconds(2);

    private readonly object _gate = new();
    private readonly object _collectorGate = new();
    private readonly string _presentMonPath;
    private readonly FpsOverlayForm _overlay;
    private readonly CancellationTokenSource _cancellation = new();
    private readonly Task _monitorTask;
    private readonly Dictionary<string, Queue<FrameSample>> _samples = new(StringComparer.OrdinalIgnoreCase);

    private Process? _collector;
    private int _collectorProcessId;
    private int _collectorGeneration;
    private Dictionary<string, int>? _columns;
    private bool _enabled;
    private bool _disposed;
    private string _status = "disabled";
    private string _message = "Enable Show FPS to display the measured frame rate.";
    private string _lastCollectorError = string.Empty;
    private int? _currentFps;
    private DateTime _lastFrameUtc = DateTime.MinValue;

    public FpsMonitorService(string presentMonPath)
    {
        _presentMonPath = Path.GetFullPath(presentMonPath);
        _overlay = new FpsOverlayForm();
        _monitorTask = Task.Run(MonitorAsync);
    }

    public FpsMonitorSnapshot GetSnapshot()
    {
        lock (_gate)
        {
            return new FpsMonitorSnapshot(
                _enabled,
                IsPresentMonAvailable(),
                _status,
                _message,
                _currentFps);
        }
    }

    public bool SetEnabled(bool enabled)
    {
        lock (_gate)
        {
            if (enabled && !IsPresentMonAvailable())
            {
                _enabled = false;
                _status = "unavailable";
                _message = "PresentMon is missing from this build.";
                _currentFps = null;
                RequestOverlayHidden();
                return false;
            }

            _enabled = enabled;
            _status = enabled ? "waiting" : "disabled";
            _message = enabled
                ? "Start the game to measure displayed FPS."
                : "Enable Show FPS to display the measured frame rate.";
            _currentFps = null;
        }

        if (!enabled)
        {
            RequestOverlayHidden();
        }
        return true;
    }

    public void SetTheme(string theme)
    {
        _overlay.SetTheme(theme);
    }

    private async Task MonitorAsync()
    {
        try
        {
            while (!_cancellation.IsCancellationRequested)
            {
                Tick();
                await Task.Delay(250, _cancellation.Token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (_cancellation.IsCancellationRequested)
        {
            // Normal shutdown.
        }
        finally
        {
            StopCollector();
            RequestOverlayHidden();
        }
    }

    private void Tick()
    {
        bool enabled;
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }
            enabled = _enabled;
        }

        if (!enabled)
        {
            StopCollector();
            RequestOverlayHidden();
            return;
        }

        if (!IsPresentMonAvailable())
        {
            StopCollector();
            lock (_gate)
            {
                _enabled = false;
            }
            SetState("unavailable", "PresentMon is missing from this build.", null);
            RequestOverlayHidden();
            return;
        }

        var gameProcessId = FindGameProcessId();
        if (gameProcessId == 0)
        {
            StopCollector();
            SetState("waiting", "Start the game to measure displayed FPS.", null);
            RequestOverlayHidden();
            return;
        }

        if (!CollectorMatches(gameProcessId) && !StartCollector(gameProcessId))
        {
            var failure = GetCollectorFailureMessage();
            SetState("error", failure, null);
            RequestOverlayHidden();
            return;
        }

        var gameWindow = FindGameWindow(gameProcessId);
        int? fps;
        DateTime lastFrameUtc;
        lock (_gate)
        {
            fps = _currentFps;
            lastFrameUtc = _lastFrameUtc;
        }

        if (fps.HasValue && DateTime.UtcNow - lastFrameUtc <= StaleSampleThreshold)
        {
            SetState("active", "Measuring displayed FPS from the game.", fps);
            RequestOverlayPresented(gameWindow, gameProcessId, fps.Value);
            return;
        }

        SetState("connecting", "Waiting for displayed frame data from the game…", null);
        RequestOverlayHidden();
    }

    private bool CollectorMatches(int gameProcessId)
    {
        lock (_collectorGate)
        {
            if (_collector is null || _collectorProcessId != gameProcessId)
            {
                return false;
            }

            try
            {
                return !_collector.HasExited;
            }
            catch (InvalidOperationException)
            {
                return false;
            }
        }
    }

    private bool StartCollector(int gameProcessId)
    {
        StopCollector();

        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = _presentMonPath,
                WorkingDirectory = Path.GetDirectoryName(_presentMonPath) ?? AppContext.BaseDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };
            foreach (var argument in new[]
            {
                "--process_id", gameProcessId.ToString(CultureInfo.InvariantCulture),
                "--output_stdout",
                "--no_console_stats",
                "--exclude_dropped",
                "--no_track_gpu",
                "--no_track_input",
                "--v2_metrics",
                "--terminate_on_proc_exit",
                "--stop_existing_session",
                "--session_name", SessionName
            })
            {
                startInfo.ArgumentList.Add(argument);
            }

            var collector = new Process { StartInfo = startInfo };
            if (!collector.Start())
            {
                collector.Dispose();
                return false;
            }

            int generation;
            lock (_collectorGate)
            {
                _collector = collector;
                _collectorProcessId = gameProcessId;
                generation = ++_collectorGeneration;
            }
            lock (_gate)
            {
                _columns = null;
                _samples.Clear();
                _lastCollectorError = string.Empty;
                _currentFps = null;
                _lastFrameUtc = DateTime.MinValue;
            }

            _ = ReadOutputAsync(collector, generation, _cancellation.Token);
            _ = ReadErrorAsync(collector, generation, _cancellation.Token);
            return true;
        }
        catch (Exception exception) when (
            exception is Win32Exception or InvalidOperationException or IOException or UnauthorizedAccessException)
        {
            lock (_gate)
            {
                _lastCollectorError = exception.Message;
            }
            StopCollector();
            return false;
        }
    }

    private async Task ReadOutputAsync(Process collector, int generation, CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var line = await collector.StandardOutput.ReadLineAsync(cancellationToken).ConfigureAwait(false);
                if (line is null)
                {
                    break;
                }
                ConsumeOutputLine(line, generation);
            }
        }
        catch (Exception exception) when (
            exception is OperationCanceledException or IOException or InvalidOperationException or ObjectDisposedException)
        {
            if (exception is not OperationCanceledException && IsCurrentGeneration(generation))
            {
                lock (_gate)
                {
                    _lastCollectorError = exception.Message;
                }
            }
        }
    }

    private async Task ReadErrorAsync(Process collector, int generation, CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var line = await collector.StandardError.ReadLineAsync(cancellationToken).ConfigureAwait(false);
                if (line is null)
                {
                    break;
                }

                var normalized = line.Trim();
                if (normalized.Length == 0 || !IsCurrentGeneration(generation))
                {
                    continue;
                }
                lock (_gate)
                {
                    _lastCollectorError = normalized.Length <= 240
                        ? normalized
                        : normalized[..240];
                }
            }
        }
        catch (Exception exception) when (
            exception is OperationCanceledException or IOException or InvalidOperationException or ObjectDisposedException)
        {
            if (exception is not OperationCanceledException && IsCurrentGeneration(generation))
            {
                lock (_gate)
                {
                    _lastCollectorError = exception.Message;
                }
            }
        }
    }

    private void ConsumeOutputLine(string line, int generation)
    {
        if (!IsCurrentGeneration(generation) || string.IsNullOrWhiteSpace(line))
        {
            return;
        }

        var fields = SplitCsvLine(line);
        if (fields.Count < 2)
        {
            return;
        }

        lock (_gate)
        {
            if (!IsCurrentGeneration(generation))
            {
                return;
            }

            var processIdIndex = fields.FindIndex(field => field.Equals("ProcessID", StringComparison.OrdinalIgnoreCase));
            var swapChainIndex = fields.FindIndex(field => field.Equals("SwapChainAddress", StringComparison.OrdinalIgnoreCase));
            var displayedTimeIndex = fields.FindIndex(field => field.Equals("DisplayedTime", StringComparison.OrdinalIgnoreCase));
            var frameTimeIndex = fields.FindIndex(field => field.Equals("FrameTime", StringComparison.OrdinalIgnoreCase));
            if (processIdIndex >= 0 && (displayedTimeIndex >= 0 || frameTimeIndex >= 0))
            {
                _columns = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
                {
                    ["ProcessID"] = processIdIndex,
                    ["SwapChainAddress"] = swapChainIndex,
                    ["FrameMetric"] = displayedTimeIndex >= 0 ? displayedTimeIndex : frameTimeIndex
                };
                return;
            }

            if (_columns is null ||
                !_columns.TryGetValue("ProcessID", out processIdIndex) ||
                !_columns.TryGetValue("FrameMetric", out var metricIndex) ||
                processIdIndex >= fields.Count || metricIndex >= fields.Count ||
                !int.TryParse(fields[processIdIndex], NumberStyles.Integer, CultureInfo.InvariantCulture, out var processId) ||
                processId != _collectorProcessId ||
                !double.TryParse(fields[metricIndex], NumberStyles.Float, CultureInfo.InvariantCulture, out var frameDurationMs) ||
                frameDurationMs is <= 0 or > 1000)
            {
                return;
            }

            var swapChain = "default";
            if (_columns.TryGetValue("SwapChainAddress", out swapChainIndex) &&
                swapChainIndex >= 0 && swapChainIndex < fields.Count &&
                !string.IsNullOrWhiteSpace(fields[swapChainIndex]))
            {
                swapChain = fields[swapChainIndex];
            }

            AddFrameSample(swapChain, frameDurationMs);
        }
    }

    private void AddFrameSample(string swapChain, double frameDurationMs)
    {
        var now = DateTime.UtcNow;
        if (!_samples.TryGetValue(swapChain, out var series))
        {
            series = new Queue<FrameSample>();
            _samples[swapChain] = series;
        }
        series.Enqueue(new FrameSample(now, frameDurationMs));

        foreach (var candidate in _samples.Values)
        {
            while (candidate.Count > 0 && now - candidate.Peek().TimestampUtc > SampleWindow)
            {
                candidate.Dequeue();
            }
        }

        var dominantSeries = _samples.Values
            .Where(candidate => candidate.Count >= 3)
            .OrderByDescending(candidate => candidate.Count)
            .FirstOrDefault();
        if (dominantSeries is null)
        {
            return;
        }

        var totalFrameTime = dominantSeries.Sum(sample => sample.DurationMs);
        if (totalFrameTime <= 0)
        {
            return;
        }

        _currentFps = Math.Clamp(
            (int)Math.Round(1000d * dominantSeries.Count / totalFrameTime),
            1,
            9999);
        _lastFrameUtc = now;
    }

    private void StopCollector()
    {
        Process? collector;
        lock (_collectorGate)
        {
            collector = _collector;
            _collector = null;
            _collectorProcessId = 0;
            _collectorGeneration++;
        }

        if (collector is not null)
        {
            try
            {
                if (!collector.HasExited)
                {
                    collector.Kill(entireProcessTree: true);
                }
            }
            catch (Exception exception) when (
                exception is InvalidOperationException or Win32Exception or NotSupportedException)
            {
                // The collector already ended or Windows refused a redundant stop.
            }
            finally
            {
                collector.Dispose();
            }
        }

        lock (_gate)
        {
            _columns = null;
            _samples.Clear();
            _currentFps = null;
            _lastFrameUtc = DateTime.MinValue;
        }
    }

    private bool IsCurrentGeneration(int generation)
    {
        lock (_collectorGate)
        {
            return generation == _collectorGeneration && _collector is not null;
        }
    }

    private string GetCollectorFailureMessage()
    {
        lock (_gate)
        {
            return string.IsNullOrWhiteSpace(_lastCollectorError)
                ? "PresentMon could not start. Run Macro Manager as Administrator."
                : $"PresentMon could not start: {_lastCollectorError}";
        }
    }

    private void SetState(string status, string message, int? currentFps)
    {
        lock (_gate)
        {
            _status = status;
            _message = message;
            _currentFps = currentFps;
        }
    }

    private void RequestOverlayPresented(nint gameWindow, int gameProcessId, int framesPerSecond)
    {
        try
        {
            if (!_overlay.IsDisposed)
            {
                _overlay.BeginInvoke((Action)(() => _overlay.Present(gameWindow, gameProcessId, framesPerSecond)));
            }
        }
        catch (InvalidOperationException)
        {
            // The UI host is closing.
        }
    }

    private void RequestOverlayHidden()
    {
        try
        {
            if (!_overlay.IsDisposed)
            {
                _overlay.BeginInvoke((Action)(() => _overlay.HideOverlay()));
            }
        }
        catch (InvalidOperationException)
        {
            // The UI host is closing.
        }
    }

    private static List<string> SplitCsvLine(string line)
    {
        var fields = new List<string>();
        var field = new StringBuilder();
        var quoted = false;

        for (var index = 0; index < line.Length; index++)
        {
            var character = line[index];
            if (character == '"')
            {
                if (quoted && index + 1 < line.Length && line[index + 1] == '"')
                {
                    field.Append('"');
                    index++;
                }
                else
                {
                    quoted = !quoted;
                }
                continue;
            }

            if (character == ',' && !quoted)
            {
                fields.Add(field.ToString());
                field.Clear();
                continue;
            }
            field.Append(character);
        }
        fields.Add(field.ToString());
        return fields;
    }

    private bool IsPresentMonAvailable()
    {
        try
        {
            return File.Exists(_presentMonPath) && new FileInfo(_presentMonPath).Length > 0;
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or NotSupportedException)
        {
            return false;
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

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }
            _disposed = true;
            _enabled = false;
        }

        _cancellation.Cancel();
        try
        {
            _monitorTask.Wait(TimeSpan.FromSeconds(2));
        }
        catch (AggregateException)
        {
            // Cancellation races are harmless during shutdown.
        }
        StopCollector();
        _overlay.HideOverlay();
        _overlay.Close();
        _overlay.Dispose();
        _cancellation.Dispose();
    }

    private sealed record FrameSample(DateTime TimestampUtc, double DurationMs);
    private delegate bool EnumWindowsCallback(nint window, nint parameter);

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
