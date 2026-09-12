using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace UMM.UI;

internal sealed record GameDllProfile(bool Enabled, string[] Paths)
{
    public static GameDllProfile Empty => new(false, Array.Empty<string>());
}

// DLL management is independent of the selected executable. Windows decides
// load compatibility at launch; list operations never parse DLL PE headers.
internal sealed class GameDllSettingsStore
{
    private readonly string _directory;
    private readonly string _mutexName;
    private string SettingsPath => Path.Combine(_directory, "shared.json");

    public GameDllSettingsStore(string? directory = null)
    {
        _directory = Path.GetFullPath(directory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MacroManager", "game-dlls"));
        var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(_directory.ToUpperInvariant())))[..24];
        _mutexName = $@"Local\MacroManager.GameDllSettings.{key}";
    }

    public static bool IsValidGamePath(string path) =>
        !string.IsNullOrWhiteSpace(path) && Path.IsPathFullyQualified(path) &&
        Path.GetExtension(path).Equals(".exe", StringComparison.OrdinalIgnoreCase) && File.Exists(path);

    public GameDllProfile Get() => WithLock(ReadOrMigrate);

    public void Add(IEnumerable<string> paths)
    {
        var additions = paths.Select(Path.GetFullPath).ToArray();
        foreach (var path in additions) ValidateDllFile(path);
        Change(old => old with {
            Paths = old.Paths.Concat(additions).Distinct(StringComparer.OrdinalIgnoreCase).ToArray()
        });
    }

    public void Remove(string dllPath)
    {
        Change(old => {
            var paths = old.Paths.Where(p => !p.Equals(dllPath, StringComparison.OrdinalIgnoreCase)).ToArray();
            return new(old.Enabled && paths.Length > 0, paths);
        });
    }

    public void SetEnabled(bool enabled)
    {
        Change(profile => {
            if (enabled && profile.Paths.Length == 0)
                throw new InvalidOperationException("Add at least one DLL first.");
            return profile with { Enabled = enabled };
        });
    }

    internal static void ValidateDllFile(string path)
    {
        if (!File.Exists(path) || !Path.GetExtension(path).Equals(".dll", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"DLL not found: {path}");
    }

    private void Change(Func<GameDllProfile, GameDllProfile> change) => WithLock(() => {
        Save(change(ReadOrMigrate()));
        return true;
    });

    private T WithLock<T>(Func<T> operation)
    {
        using var mutex = new Mutex(false, _mutexName);
        var owned = false;
        try
        {
            try { owned = mutex.WaitOne(TimeSpan.FromSeconds(5)); }
            catch (AbandonedMutexException) { owned = true; }
            if (!owned) throw new IOException("DLL settings are busy. Try again.");
            return operation();
        }
        finally { if (owned) mutex.ReleaseMutex(); }
    }

    private GameDllProfile ReadOrMigrate()
    {
        if (File.Exists(SettingsPath)) return ReadProfile(SettingsPath);
        if (!Directory.Exists(_directory)) return GameDllProfile.Empty;
        // Preserve all previous per-game lists, even when no game is selected.
        // Old files remain intact; shared.json makes this a one-time migration.
        var oldFiles = Directory.GetFiles(_directory, "*.json")
            .Where(path => {
                var name = Path.GetFileNameWithoutExtension(path);
                return name.Length == 64 && name.All(Uri.IsHexDigit);
            }).OrderBy(path => path, StringComparer.OrdinalIgnoreCase).ToArray();
        if (oldFiles.Length == 0) return GameDllProfile.Empty;
        var profiles = oldFiles.Select(ReadProfile).ToArray();
        var paths = profiles.SelectMany(profile => profile.Paths).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        // Combining several game-specific lists requires an explicit new opt-in.
        var migrated = new GameDllProfile(profiles.Length == 1 && profiles[0].Enabled && paths.Length > 0, paths);
        Save(migrated);
        return migrated;
    }

    private static GameDllProfile ReadProfile(string path)
    {
        var profile = JsonSerializer.Deserialize<GameDllProfile>(File.ReadAllText(path));
        if (profile is null || profile.Paths is null ||
            profile.Paths.Any(p => string.IsNullOrWhiteSpace(p) || !Path.IsPathFullyQualified(p) ||
                !Path.GetExtension(p).Equals(".dll", StringComparison.OrdinalIgnoreCase)))
            throw new InvalidDataException($"The DLL settings file is invalid: {path}");
        return profile;
    }

    private void Save(GameDllProfile profile)
    {
        Directory.CreateDirectory(_directory);
        var temporary = SettingsPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(profile));
            File.Move(temporary, SettingsPath, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }
}
