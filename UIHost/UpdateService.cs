using System.Diagnostics;
using System.IO.Compression;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace UMM.UI;

internal sealed class GitHubUpdateService : IDisposable
{
    public const string RepositoryOwner = "3azf55";
    public const string RepositoryName = "GI-Macro-Manager";
    public const string RepositoryUrl = "https://github.com/3azf55/GI-Macro-Manager";
    public const string ReleasesUrl = RepositoryUrl + "/releases";

    private const string LatestReleaseApiUrl =
        "https://api.github.com/repos/3azf55/GI-Macro-Manager/releases/latest";

    private const long MaximumDownloadBytes = 250L * 1024L * 1024L;
    private const long MaximumExtractedBytes = 600L * 1024L * 1024L;
    private const int MaximumExtractedFiles = 5000;

    private readonly HttpClient _httpClient;

    public GitHubUpdateService()
    {
        _httpClient = new HttpClient(new HttpClientHandler
        {
            AllowAutoRedirect = true,
            AutomaticDecompression = DecompressionMethods.All
        })
        {
            Timeout = TimeSpan.FromMinutes(10)
        };

        _httpClient.DefaultRequestHeaders.UserAgent.Add(
            new ProductInfoHeaderValue("GI-Macro-Manager", "1.0"));
        _httpClient.DefaultRequestHeaders.Accept.Add(
            new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        _httpClient.DefaultRequestHeaders.Add("X-GitHub-Api-Version", "2026-03-10");
    }

    public async Task<UpdateCheckResult> CheckAsync(
        Version currentVersion,
        CancellationToken cancellationToken)
    {
        using var response = await _httpClient.GetAsync(
            LatestReleaseApiUrl,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);

        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            return UpdateCheckResult.NoRelease(
                NormalizeVersion(currentVersion),
                ReleasesUrl);
        }

        response.EnsureSuccessStatusCode();

        await using var responseStream = await response.Content.ReadAsStreamAsync(cancellationToken);
        var release = await JsonSerializer.DeserializeAsync<GitHubRelease>(
            responseStream,
            cancellationToken: cancellationToken);

        if (release is null || string.IsNullOrWhiteSpace(release.TagName))
        {
            throw new InvalidDataException("GitHub returned an invalid release response.");
        }

        var latestVersion = ParseReleaseVersion(release.TagName);
        var normalizedCurrent = NormalizeVersion(currentVersion);

        if (latestVersion <= normalizedCurrent)
        {
            return UpdateCheckResult.Current(
                normalizedCurrent,
                latestVersion,
                release.TagName,
                release.HtmlUrl ?? ReleasesUrl);
        }

        var asset = SelectReleaseAsset(release.Assets, release.TagName);
        return UpdateCheckResult.Available(
            normalizedCurrent,
            latestVersion,
            release.TagName,
            release.Name ?? release.TagName,
            release.Body ?? string.Empty,
            release.HtmlUrl ?? ReleasesUrl,
            asset);
    }

    public async Task<PreparedUpdate> DownloadAndPrepareAsync(
        UpdateCheckResult update,
        string installRoot,
        IProgress<int>? progress,
        CancellationToken cancellationToken)
    {
        if (update.Status != UpdateAvailability.Available || update.Asset is null)
        {
            throw new InvalidOperationException("The selected release does not contain an installable ZIP asset.");
        }

        if (update.Asset.Size <= 0 || update.Asset.Size > MaximumDownloadBytes)
        {
            throw new InvalidDataException("The release asset size is invalid or exceeds the update limit.");
        }

        var updateRoot = Path.Combine(
            Path.GetTempPath(),
            "GI-Macro-Manager",
            "updates",
            SanitizeFileName(update.TagName) + "-" + Guid.NewGuid().ToString("N"));
        var downloadPath = Path.Combine(updateRoot, "package.zip");
        var extractRoot = Path.Combine(updateRoot, "payload");

        Directory.CreateDirectory(updateRoot);
        Directory.CreateDirectory(extractRoot);

        try
        {
            await DownloadFileAsync(
                update.Asset,
                downloadPath,
                progress,
                cancellationToken);

            VerifyDigestIfAvailable(downloadPath, update.Asset.Digest);
            SafeExtractZip(downloadPath, extractRoot);

            var payloadRoot = FindPayloadRoot(extractRoot);
            ValidatePayload(payloadRoot);
            MergeInstalledRegistry(installRoot, payloadRoot);

            var scriptPath = WriteUpdaterScript();
            return new PreparedUpdate(
                scriptPath,
                payloadRoot,
                updateRoot,
                update.TagName);
        }
        catch
        {
            TryDeleteDirectory(updateRoot);
            throw;
        }
    }

    public static Process StartInstaller(
        PreparedUpdate prepared,
        string installRoot,
        int enginePid,
        int uiPid)
    {
        var resultPath = GetUpdateResultPath();

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = installRoot
        };

        startInfo.ArgumentList.Add("-NoLogo");
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-NonInteractive");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(prepared.ScriptPath);
        startInfo.ArgumentList.Add("-InstallRoot");
        startInfo.ArgumentList.Add(installRoot);
        startInfo.ArgumentList.Add("-PayloadRoot");
        startInfo.ArgumentList.Add(prepared.PayloadRoot);
        startInfo.ArgumentList.Add("-EnginePid");
        startInfo.ArgumentList.Add(enginePid.ToString());
        startInfo.ArgumentList.Add("-UiPid");
        startInfo.ArgumentList.Add(uiPid.ToString());
        startInfo.ArgumentList.Add("-UpdateRoot");
        startInfo.ArgumentList.Add(prepared.UpdateRoot);
        startInfo.ArgumentList.Add("-ResultPath");
        startInfo.ArgumentList.Add(resultPath);
        startInfo.ArgumentList.Add("-TargetVersion");
        startInfo.ArgumentList.Add(prepared.TargetVersion);

        return Process.Start(startInfo)
            ?? throw new InvalidOperationException("The update installer could not be started.");
    }

    public static UpdateResult? ReadAndDeletePreviousResult()
    {
        var resultPath = GetUpdateResultPath();
        if (!File.Exists(resultPath))
        {
            return null;
        }

        try
        {
            var json = File.ReadAllText(resultPath, Encoding.UTF8);
            return JsonSerializer.Deserialize<UpdateResult>(
                json,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch
        {
            return null;
        }
        finally
        {
            try
            {
                File.Delete(resultPath);
            }
            catch
            {
                // A stale result is harmless and can be retried next time.
            }
        }
    }

    public void Dispose() => _httpClient.Dispose();

    public static Version NormalizeVersion(Version version) => new(
        Math.Max(0, version.Major),
        Math.Max(0, version.Minor),
        Math.Max(0, version.Build),
        Math.Max(0, version.Revision));

    private static Version ParseReleaseVersion(string tagName)
    {
        var value = tagName.Trim();
        if (value.StartsWith('v') || value.StartsWith('V'))
        {
            value = value[1..];
        }

        var suffixIndex = value.IndexOfAny(new[] { '-', '+' });
        if (suffixIndex >= 0)
        {
            value = value[..suffixIndex];
        }

        if (!Version.TryParse(value, out var parsed))
        {
            throw new InvalidDataException($"The release tag '{tagName}' is not a supported version.");
        }

        return NormalizeVersion(parsed);
    }

    private static ReleaseAsset? SelectReleaseAsset(
        IReadOnlyList<GitHubAsset>? assets,
        string tagName)
    {
        if (assets is null)
        {
            return null;
        }

        var normalizedTag = tagName.Trim();
        var expectedName = $"GI-Macro-Manager-{normalizedTag}-win-x64.zip";

        var candidates = assets
            .Where(asset =>
                asset.State.Equals("uploaded", StringComparison.OrdinalIgnoreCase) &&
                asset.Name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase) &&
                Uri.TryCreate(asset.BrowserDownloadUrl, UriKind.Absolute, out var uri) &&
                uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
            .Select(asset => new
            {
                Asset = asset,
                Score = ScoreAsset(asset.Name, expectedName)
            })
            .OrderByDescending(candidate => candidate.Score)
            .ThenBy(candidate => candidate.Asset.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (candidates.Count == 0)
        {
            return null;
        }

        var selected = candidates[0].Asset;
        return new ReleaseAsset(
            selected.Name,
            selected.BrowserDownloadUrl,
            selected.Size,
            selected.Digest ?? string.Empty);
    }

    private static int ScoreAsset(string name, string expectedName)
    {
        if (name.Equals(expectedName, StringComparison.OrdinalIgnoreCase))
        {
            return 1000;
        }

        var score = 0;
        if (name.Contains("GI-Macro-Manager", StringComparison.OrdinalIgnoreCase)) score += 100;
        if (name.Contains("win-x64", StringComparison.OrdinalIgnoreCase)) score += 80;
        if (name.Contains("runtime", StringComparison.OrdinalIgnoreCase)) score += 30;
        if (name.Contains("source", StringComparison.OrdinalIgnoreCase)) score -= 200;
        return score;
    }

    private async Task DownloadFileAsync(
        ReleaseAsset asset,
        string destinationPath,
        IProgress<int>? progress,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, asset.DownloadUrl);
        using var response = await _httpClient.SendAsync(
            request,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);
        response.EnsureSuccessStatusCode();

        var contentLength = response.Content.Headers.ContentLength ?? asset.Size;
        if (contentLength <= 0 || contentLength > MaximumDownloadBytes)
        {
            throw new InvalidDataException("The downloaded update has an invalid size.");
        }

        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using var destination = new FileStream(
            destinationPath,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None,
            1024 * 128,
            FileOptions.Asynchronous | FileOptions.SequentialScan);

        var buffer = new byte[1024 * 128];
        long totalRead = 0;
        var lastProgress = -1;

        while (true)
        {
            var read = await source.ReadAsync(buffer.AsMemory(), cancellationToken);
            if (read == 0)
            {
                break;
            }

            totalRead += read;
            if (totalRead > MaximumDownloadBytes)
            {
                throw new InvalidDataException("The downloaded update exceeds the size limit.");
            }

            await destination.WriteAsync(buffer.AsMemory(0, read), cancellationToken);

            var currentProgress = (int)Math.Clamp(totalRead * 100L / contentLength, 0, 100);
            if (currentProgress != lastProgress)
            {
                lastProgress = currentProgress;
                progress?.Report(currentProgress);
            }
        }

        if (asset.Size > 0 && totalRead != asset.Size)
        {
            throw new InvalidDataException("The downloaded update size does not match the GitHub asset.");
        }

        progress?.Report(100);
    }

    private static void VerifyDigestIfAvailable(string path, string digest)
    {
        if (string.IsNullOrWhiteSpace(digest))
        {
            return;
        }

        const string prefix = "sha256:";
        if (!digest.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var expected = digest[prefix.Length..].Trim();
        using var stream = File.OpenRead(path);
        var actual = Convert.ToHexString(SHA256.HashData(stream));

        if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("The downloaded update failed SHA-256 verification.");
        }
    }

    private static void SafeExtractZip(string zipPath, string destinationRoot)
    {
        var fullDestination = Path.GetFullPath(destinationRoot)
            .TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        long extractedBytes = 0;
        var extractedFiles = 0;

        using var archive = ZipFile.OpenRead(zipPath);
        foreach (var entry in archive.Entries)
        {
            var relativePath = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
            var destinationPath = Path.GetFullPath(Path.Combine(destinationRoot, relativePath));

            if (!destinationPath.StartsWith(fullDestination, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("The update archive contains an unsafe path.");
            }

            if (string.IsNullOrEmpty(entry.Name))
            {
                Directory.CreateDirectory(destinationPath);
                continue;
            }

            extractedFiles++;
            extractedBytes += entry.Length;
            if (extractedFiles > MaximumExtractedFiles || extractedBytes > MaximumExtractedBytes)
            {
                throw new InvalidDataException("The update archive exceeds the extraction limit.");
            }

            var parentDirectory = Path.GetDirectoryName(destinationPath);
            if (!string.IsNullOrEmpty(parentDirectory))
            {
                Directory.CreateDirectory(parentDirectory);
            }

            entry.ExtractToFile(destinationPath, overwrite: true);
        }
    }

    private static string FindPayloadRoot(string extractRoot)
    {
        var candidates = Directory
            .EnumerateFiles(extractRoot, "UMM.Engine.ahk", SearchOption.AllDirectories)
            .Select(Path.GetDirectoryName)
            .Where(directory => !string.IsNullOrWhiteSpace(directory))
            .Cast<string>()
            .Where(directory =>
                File.Exists(Path.Combine(directory, "UMM.UI.exe")) &&
                File.Exists(Path.Combine(directory, "ui", "index.html")) &&
                File.Exists(Path.Combine(directory, "Macros", "registry.ini")))
            .OrderBy(directory => directory.Count(character =>
                character == Path.DirectorySeparatorChar ||
                character == Path.AltDirectorySeparatorChar))
            .ToList();

        return candidates.Count switch
        {
            0 => throw new InvalidDataException(
                "The release ZIP is not a complete Macro Manager runtime package."),
            _ => candidates[0]
        };
    }

    private static void ValidatePayload(string payloadRoot)
    {
        var requiredFiles = new[]
        {
            Path.Combine(payloadRoot, "UMM.Engine.ahk"),
            Path.Combine(payloadRoot, "UMM.UI.exe"),
            Path.Combine(payloadRoot, "ui", "index.html"),
            Path.Combine(payloadRoot, "ui", "app.js"),
            Path.Combine(payloadRoot, "Macros", "registry.ini")
        };

        var missing = requiredFiles.FirstOrDefault(path => !File.Exists(path));
        if (missing is not null)
        {
            throw new InvalidDataException(
                $"The release package is missing '{Path.GetFileName(missing)}'.");
        }
    }

    private static void MergeInstalledRegistry(string installRoot, string payloadRoot)
    {
        var installedPath = Path.Combine(installRoot, "Macros", "registry.ini");
        var updatePath = Path.Combine(payloadRoot, "Macros", "registry.ini");

        if (!File.Exists(installedPath) || !File.Exists(updatePath))
        {
            return;
        }

        var installed = IniDocument.Load(installedPath);
        var update = IniDocument.Load(updatePath);

        foreach (var installedSection in installed.Sections)
        {
            var updateSection = update.FindSection(installedSection.Name);
            if (updateSection is null)
            {
                update.Sections.Add(installedSection.Clone());
                continue;
            }

            if (installedSection.Name.StartsWith("Combo.", StringComparison.OrdinalIgnoreCase) &&
                installedSection.Values.TryGetValue("Order", out var installedOrder))
            {
                updateSection.Values["Order"] = installedOrder;
            }
        }

        update.Save(updatePath);
    }

    private static string WriteUpdaterScript()
    {
        var scriptPath = Path.Combine(
            Path.GetTempPath(),
            "GI-Macro-Manager-apply-" + Guid.NewGuid().ToString("N") + ".ps1");

        const string script = """
param(
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [Parameter(Mandatory = $true)][string]$PayloadRoot,
    [int]$EnginePid = 0,
    [int]$UiPid = 0,
    [Parameter(Mandatory = $true)][string]$UpdateRoot,
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [Parameter(Mandatory = $true)][string]$TargetVersion
)

$ErrorActionPreference = "Stop"

function Wait-ForApplicationExit {
    param([int]$ProcessId)

    if ($ProcessId -le 0) {
        return
    }

    try {
        Wait-Process -Id $ProcessId -Timeout 35 -ErrorAction SilentlyContinue
    }
    catch {
    }

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -ne $process) {
        Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $ProcessId -Timeout 10 -ErrorAction SilentlyContinue
    }
}

function Copy-WithRetry {
	param(
		[string]$Source,
		[string]$Destination
	)

	$item = Get-Item -LiteralPath $Source -Force
	if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
		throw "Update data must not contain symbolic links or junctions: $Source"
	}

	if ($item.PSIsContainer) {
		New-Item -Path $Destination -ItemType Directory -Force | Out-Null
		Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
			Copy-WithRetry -Source $_.FullName -Destination (Join-Path $Destination $_.Name)
		}
		return
	}

	for ($attempt = 1; $attempt -le 12; $attempt++) {
		try {
			Copy-Item -LiteralPath $Source -Destination $Destination -Force
			return
        }
        catch {
            if ($attempt -eq 12) {
                throw
            }

            Start-Sleep -Milliseconds 750
        }
    }
}

function Copy-DirectoryContents {
	param(
		[string]$Source,
		[string]$Destination
	)

	New-Item -Path $Destination -ItemType Directory -Force | Out-Null
	Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
		Copy-WithRetry -Source $_.FullName -Destination (Join-Path $Destination $_.Name)
	}
}

function Remove-DirectoryContentsWithRetry {
	param([string]$Root)

	if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
		return
	}

	foreach ($item in @(Get-ChildItem -LiteralPath $Root -Force)) {
		for ($attempt = 1; $attempt -le 20; $attempt++) {
			try {
				Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
				break
			}
			catch {
				if ($attempt -eq 20) {
					throw
				}

				Start-Sleep -Milliseconds 500
			}
		}
	}
}

function Test-RuntimeRoot {
    param([string]$Root)

    return (
        (Test-Path -LiteralPath (Join-Path $Root "UMM.Engine.ahk") -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Root "UMM.UI.exe") -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Root "ui\index.html") -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Root "Macros\registry.ini") -PathType Leaf)
    )
}

function Write-UpdateResult {
    param(
        [string]$Status,
        [string]$Message
    )

    $resultDirectory = Split-Path -Parent $ResultPath
    New-Item $resultDirectory -ItemType Directory -Force | Out-Null

    $result = [ordered]@{
        status = $Status
        version = $TargetVersion
        message = $Message
    }

    $json = $result | ConvertTo-Json -Compress
    $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($ResultPath, $json, $utf8)
}

$stageRoot = $null
$rollbackRoot = $null
$activationComplete = $false
$activationMode = "none"
$installRootFull = $null
$restartSucceeded = $false
try {
    $directorySeparators = [char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $installRootFull = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd($directorySeparators)
    $payloadRootFull = [System.IO.Path]::GetFullPath($PayloadRoot).TrimEnd($directorySeparators)
    $installDriveRoot = [System.IO.Path]::GetPathRoot($installRootFull).TrimEnd($directorySeparators)
    $installParent = Split-Path -Parent $installRootFull
    $installName = Split-Path -Leaf $installRootFull

    if ([string]::IsNullOrWhiteSpace($installName) -or
        $installRootFull -eq $installDriveRoot -or
        -not (Test-Path -LiteralPath $installParent -PathType Container)) {
        throw "The installation root is unsafe for an update transaction."
    }

    if (-not (Test-RuntimeRoot -Root $installRootFull)) {
        throw "The current installation is not a complete runtime package."
    }

    if (-not (Test-RuntimeRoot -Root $payloadRootFull)) {
        throw "The prepared update payload is incomplete."
    }

    Wait-ForApplicationExit -ProcessId $UiPid
    Wait-ForApplicationExit -ProcessId $EnginePid
    Start-Sleep -Milliseconds 500

    $transactionId = [Guid]::NewGuid().ToString("N")
    $stageRoot = Join-Path $installParent ("." + $installName + ".update." + $transactionId)
    $rollbackRoot = Join-Path $installParent ("." + $installName + ".rollback." + $transactionId)

    if ((Test-Path -LiteralPath $stageRoot) -or (Test-Path -LiteralPath $rollbackRoot)) {
        throw "The update transaction paths already exist."
    }

    New-Item -Path $stageRoot -ItemType Directory | Out-Null

    $preservedNames = @(
        "settings.ini",
        "bridge",
        "UMM.UI.connection.log"
    )

    # Build a clean candidate beside the live installation. Preserve only
    # local settings/bridge data and installed user macro folders, then overlay
    # the release payload so removed application files do not survive forever.
	foreach ($preservedName in $preservedNames) {
		$preservedPath = Join-Path $installRootFull $preservedName
		if (Test-Path -LiteralPath $preservedPath) {
			Copy-WithRetry -Source $preservedPath -Destination (Join-Path $stageRoot $preservedName)
		}
	}

    $installedUserMacros = Join-Path $installRootFull "Macros\User"
    if (Test-Path -LiteralPath $installedUserMacros -PathType Container) {
        $stageUserMacros = Join-Path $stageRoot "Macros\User"
        New-Item -Path $stageUserMacros -ItemType Directory -Force | Out-Null
		Get-ChildItem -LiteralPath $installedUserMacros -Force |
			Where-Object { $_.Name -ne ".trash" } |
			ForEach-Object {
				Copy-WithRetry -Source $_.FullName -Destination (Join-Path $stageUserMacros $_.Name)
			}
    }

    Get-ChildItem -LiteralPath $payloadRootFull -Force | ForEach-Object {
        if ($preservedNames -contains $_.Name) {
            return
        }

		Copy-WithRetry -Source $_.FullName -Destination (Join-Path $stageRoot $_.Name)
	}

    if (-not (Test-RuntimeRoot -Root $stageRoot)) {
        throw "The staged installation failed runtime validation."
    }

    $backupRoot = Join-Path $env:LOCALAPPDATA (
        "MacroManager\UpdateBackups\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item $backupRoot -ItemType Directory -Force | Out-Null

    $settingsPath = Join-Path $installRootFull "settings.ini"
    if (Test-Path $settingsPath) {
        Copy-Item $settingsPath $backupRoot -Force
    }

    $registryPath = Join-Path $installRootFull "Macros\registry.ini"
    if (Test-Path $registryPath) {
        $registryBackup = Join-Path $backupRoot "registry.ini"
        Copy-Item $registryPath $registryBackup -Force
    }

    # Prefer a same-volume directory swap because it is atomic. Windows can
    # reject a root-directory rename when Explorer, a terminal, or another
    # harmless process has that directory open. In that case, keep the root
    # directory and replace only its contents from the already validated stage.
    Set-Location -LiteralPath $installParent
    try {
        Move-Item -LiteralPath $installRootFull -Destination $rollbackRoot -ErrorAction Stop
        $activationMode = "swap"
    }
    catch {
        $directorySwapError = $_.Exception.Message
        Copy-WithRetry -Source $installRootFull -Destination $rollbackRoot
        $activationMode = "in-place"
    }

    if ($activationMode -eq "swap") {
      try {
        Move-Item -LiteralPath $stageRoot -Destination $installRootFull
        $activationComplete = $true
        $stageRoot = $null
      }
      catch {
          Move-Item -LiteralPath $rollbackRoot -Destination $installRootFull
          $rollbackRoot = $null
          throw
      }
    }
    else {
        Remove-DirectoryContentsWithRetry -Root $installRootFull
        Copy-DirectoryContents -Source $stageRoot -Destination $installRootFull

        if (-not (Test-RuntimeRoot -Root $installRootFull)) {
            throw "The in-place update fallback failed runtime validation after directory swap was blocked: $directorySwapError"
        }

        $activationComplete = $true
    }

    Write-UpdateResult -Status "success" -Message "Macro Manager was updated successfully."
}
catch {
    $updateErrorMessage = $_.Exception.Message
    if (-not $activationComplete -and $null -ne $rollbackRoot -and (Test-Path -LiteralPath $rollbackRoot)) {
        try {
            if ($activationMode -eq "in-place") {
                New-Item -Path $installRootFull -ItemType Directory -Force | Out-Null
                Remove-DirectoryContentsWithRetry -Root $installRootFull
                Copy-DirectoryContents -Source $rollbackRoot -Destination $installRootFull
            }
            elseif (-not (Test-Path -LiteralPath $installRootFull)) {
                Move-Item -LiteralPath $rollbackRoot -Destination $installRootFull
                $rollbackRoot = $null
            }
        }
        catch {
            $updateErrorMessage += " Rollback also failed: " + $_.Exception.Message
        }
    }

    Write-UpdateResult -Status "error" -Message $updateErrorMessage
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($installRootFull)) {
        $enginePathAfterUpdate = Join-Path $installRootFull "UMM.Engine.ahk"
        if (Test-Path -LiteralPath $enginePathAfterUpdate -PathType Leaf) {
            try {
                Start-Process -FilePath $enginePathAfterUpdate -WorkingDirectory $installRootFull
                $restartSucceeded = $true
            }
            catch {
                Write-UpdateResult -Status "error" -Message (
                    "The update was applied, but Macro Manager could not restart: " + $_.Exception.Message)
            }
        }
    }

    if ($activationComplete -and $restartSucceeded -and $null -ne $rollbackRoot -and (Test-Path -LiteralPath $rollbackRoot)) {
        Remove-Item -LiteralPath $rollbackRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $stageRoot -and (Test-Path -LiteralPath $stageRoot)) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 2
    try {
        $temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $updateRootFull = [System.IO.Path]::GetFullPath($UpdateRoot)
        if ($updateRootFull.StartsWith($temporaryRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $updateRootFull -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
    }
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
""";

        File.WriteAllText(scriptPath, script, new UTF8Encoding(false));
        return scriptPath;
    }

    private static string GetUpdateResultPath()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MacroManager");
        Directory.CreateDirectory(directory);
        return Path.Combine(directory, "last-update.json");
    }

    private static string SanitizeFileName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars();
        return new string(value.Select(character =>
            invalid.Contains(character) ? '_' : character).ToArray());
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch
        {
            // Temporary update files can be cleaned by the operating system.
        }
    }

    private sealed class GitHubRelease
    {
        [JsonPropertyName("tag_name")]
        public string TagName { get; init; } = string.Empty;

        [JsonPropertyName("name")]
        public string? Name { get; init; }

        [JsonPropertyName("body")]
        public string? Body { get; init; }

        [JsonPropertyName("html_url")]
        public string? HtmlUrl { get; init; }

        [JsonPropertyName("assets")]
        public List<GitHubAsset>? Assets { get; init; }
    }

    private sealed class GitHubAsset
    {
        [JsonPropertyName("name")]
        public string Name { get; init; } = string.Empty;

        [JsonPropertyName("browser_download_url")]
        public string BrowserDownloadUrl { get; init; } = string.Empty;

        [JsonPropertyName("size")]
        public long Size { get; init; }

        [JsonPropertyName("digest")]
        public string? Digest { get; init; }

        [JsonPropertyName("state")]
        public string State { get; init; } = string.Empty;
    }

    private sealed class IniDocument
    {
        public List<string> Preamble { get; } = [];
        public List<IniSection> Sections { get; } = [];

        public static IniDocument Load(string path)
        {
            var document = new IniDocument();
            IniSection? currentSection = null;

            foreach (var rawLine in File.ReadAllLines(path, Encoding.UTF8))
            {
                var line = rawLine.Trim();
                if (line.StartsWith('[') && line.EndsWith(']') && line.Length > 2)
                {
                    currentSection = new IniSection(line[1..^1].Trim());
                    document.Sections.Add(currentSection);
                    continue;
                }

                if (currentSection is null)
                {
                    document.Preamble.Add(rawLine);
                    continue;
                }

                if (line.Length == 0 || line.StartsWith(';') || line.StartsWith('#'))
                {
                    currentSection.ExtraLines.Add(rawLine);
                    continue;
                }

                var separator = rawLine.IndexOf('=');
                if (separator <= 0)
                {
                    currentSection.ExtraLines.Add(rawLine);
                    continue;
                }

                var key = rawLine[..separator].Trim();
                var value = rawLine[(separator + 1)..].Trim();
                currentSection.Values[key] = value;
            }

            return document;
        }

        public IniSection? FindSection(string name) => Sections.FirstOrDefault(section =>
            section.Name.Equals(name, StringComparison.OrdinalIgnoreCase));

        public void Save(string path)
        {
            var builder = new StringBuilder();
            foreach (var line in Preamble)
            {
                builder.AppendLine(line);
            }

            if (Preamble.Count > 0 && Preamble[^1].Length > 0)
            {
                builder.AppendLine();
            }

            for (var index = 0; index < Sections.Count; index++)
            {
                var section = Sections[index];
                builder.Append('[').Append(section.Name).AppendLine("]");
                foreach (var pair in section.Values)
                {
                    builder.Append(pair.Key).Append('=').AppendLine(pair.Value);
                }

                foreach (var line in section.ExtraLines)
                {
                    builder.AppendLine(line);
                }

                if (index < Sections.Count - 1)
                {
                    builder.AppendLine();
                }
            }

            File.WriteAllText(path, builder.ToString(), new UTF8Encoding(false));
        }
    }

    private sealed class IniSection(string name)
    {
        public string Name { get; } = name;
        public Dictionary<string, string> Values { get; } =
            new(StringComparer.OrdinalIgnoreCase);
        public List<string> ExtraLines { get; } = [];

        public IniSection Clone()
        {
            var clone = new IniSection(Name);
            foreach (var pair in Values)
            {
                clone.Values[pair.Key] = pair.Value;
            }

            clone.ExtraLines.AddRange(ExtraLines);
            return clone;
        }
    }
}

internal enum UpdateAvailability
{
    NoRelease,
    Current,
    Available
}

internal sealed record ReleaseAsset(
    string Name,
    string DownloadUrl,
    long Size,
    string Digest);

internal sealed record UpdateCheckResult(
    UpdateAvailability Status,
    Version CurrentVersion,
    Version LatestVersion,
    string TagName,
    string ReleaseName,
    string ReleaseNotes,
    string ReleaseUrl,
    ReleaseAsset? Asset)
{
    public static UpdateCheckResult NoRelease(Version currentVersion, string releaseUrl) => new(
        UpdateAvailability.NoRelease,
        currentVersion,
        currentVersion,
        string.Empty,
        string.Empty,
        string.Empty,
        releaseUrl,
        null);

    public static UpdateCheckResult Current(
        Version currentVersion,
        Version latestVersion,
        string tagName,
        string releaseUrl) => new(
            UpdateAvailability.Current,
            currentVersion,
            latestVersion,
            tagName,
            tagName,
            string.Empty,
            releaseUrl,
            null);

    public static UpdateCheckResult Available(
        Version currentVersion,
        Version latestVersion,
        string tagName,
        string releaseName,
        string releaseNotes,
        string releaseUrl,
        ReleaseAsset? asset) => new(
            UpdateAvailability.Available,
            currentVersion,
            latestVersion,
            tagName,
            releaseName,
            releaseNotes,
            releaseUrl,
            asset);
}

internal sealed record PreparedUpdate(
    string ScriptPath,
    string PayloadRoot,
    string UpdateRoot,
    string TargetVersion);

internal sealed record UpdateResult(
    string Status,
    string Version,
    string Message);
