using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace UMM.UI;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();

        var options = CommandLineOptions.Parse(args);
        var instanceKey = BuildInstanceKey(options);
        var mutexName = $@"Local\MacroManager.UI.{instanceKey}";
        var activationEventName = $@"Local\MacroManager.UI.Activate.{instanceKey}";

        using var instanceMutex = new Mutex(
            initiallyOwned: true,
            name: mutexName,
            createdNew: out var isFirstInstance);

        if (!isFirstInstance)
        {
            SignalExistingInstance(activationEventName);
            return;
        }

        using var activationEvent = new EventWaitHandle(
            initialState: false,
            mode: EventResetMode.AutoReset,
            name: activationEventName);

        Application.Run(
            new MainForm(
                options.EngineHwnd,
                options.EnginePid,
                options.RootDirectory,
                options.EnableDevTools,
                activationEvent));
    }

    private static string BuildInstanceKey(CommandLineOptions options)
    {
        var identity = options.EnginePid > 0
            ? $"engine:{options.EnginePid}"
            : $"root:{Path.GetFullPath(options.RootDirectory).TrimEnd(Path.DirectorySeparatorChar).ToUpperInvariant()}";

        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(identity));
        return Convert.ToHexString(hash)[..24];
    }

    private static void SignalExistingInstance(string activationEventName)
    {
        try
        {
            using var activationEvent = EventWaitHandle.OpenExisting(activationEventName);
            activationEvent.Set();
        }
        catch (WaitHandleCannotBeOpenedException)
        {
            // The first instance may still be creating its activation event.
        }
        catch (UnauthorizedAccessException)
        {
            // Different integrity levels cannot share the activation event.
        }
    }
}

internal sealed record CommandLineOptions(IntPtr EngineHwnd, int EnginePid, string RootDirectory, bool EnableDevTools)
{
    public static CommandLineOptions Parse(string[] args)
    {
        nint engineHwnd = 0;
        var enginePid = 0;
        var rootDirectory = AppContext.BaseDirectory;
        var enableDevTools = false;

        for (var index = 0; index < args.Length; index++)
        {
            var arg = args[index];
            if (arg.Equals("--engine-hwnd", StringComparison.OrdinalIgnoreCase) && index + 1 < args.Length)
            {
                if (long.TryParse(args[++index], NumberStyles.Integer, CultureInfo.InvariantCulture, out var rawHwnd))
                {
                    engineHwnd = (nint)rawHwnd;
                }
            }
            else if (arg.Equals("--engine-pid", StringComparison.OrdinalIgnoreCase) && index + 1 < args.Length)
            {
                _ = int.TryParse(args[++index], NumberStyles.Integer, CultureInfo.InvariantCulture, out enginePid);
            }
            else if (arg.Equals("--root", StringComparison.OrdinalIgnoreCase) && index + 1 < args.Length)
            {
                rootDirectory = Path.GetFullPath(args[++index]);
            }
            else if (arg.Equals("--devtools", StringComparison.OrdinalIgnoreCase))
            {
                enableDevTools = true;
            }
        }

        return new CommandLineOptions(engineHwnd, enginePid, rootDirectory, enableDevTools);
    }
}
