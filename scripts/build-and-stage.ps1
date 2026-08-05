$ErrorActionPreference = "Stop"

$PackageRoot = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $PackageRoot "UIHost\UMM.UI.csproj"
$NuGetConfig = Join-Path $PackageRoot "NuGet.Config"
$Assets = Join-Path $PackageRoot "Assets"
$Macros = Join-Path $PackageRoot "Macros"
$Dist = Join-Path $PackageRoot "dist"
$PublishTemp = Join-Path $PackageRoot ".publish-temp"
$Runtime = "win-x64"
$FpsBuildScript = Join-Path $PSScriptRoot "build-fps-unlocker.ps1"

function Invoke-DotNet {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & dotnet @Arguments
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        $commandText = "dotnet " + ($Arguments -join " ")
        throw ("dotnet command failed with exit code {0}: {1}" -f $exitCode, $commandText)
    }
}

function Remove-DirectoryWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [int]$MaximumAttempts = 5
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            if (Test-Path -LiteralPath $Path) {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            }

            return
        }
        catch {
            if ($attempt -eq $MaximumAttempts) {
                throw "Unable to remove '$Path'. Close Macro Manager, AutoHotkey, Explorer, and any terminal using that folder. $($_.Exception.Message)"
            }

            Write-Warning "The folder is in use. Retrying in 2 seconds ($attempt/$MaximumAttempts)..."
            Start-Sleep -Seconds 2
        }
    }
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw ".NET SDK was not found. Install the .NET 8 SDK, then reopen the terminal."
}

if (-not (Test-Path $Project)) {
    throw "Project file was not found: $Project"
}

if (-not (Test-Path $NuGetConfig)) {
    throw "NuGet.Config was not found: $NuGetConfig"
}

# Ensure UnlockerStub.dll is available in FpsUnlocker\Native\ for UMM.UI.csproj validation
$CompiledDll = Join-Path $PackageRoot "FpsUnlocker\Native\UnlockerStub\bin\x64\Release\UnlockerStub.dll"
$TargetDllFolder = Join-Path $PackageRoot "FpsUnlocker\Native"
$TargetDll = Join-Path $TargetDllFolder "UnlockerStub.dll"

New-Item -ItemType Directory -Path $TargetDllFolder -Force | Out-Null

if (Test-Path $CompiledDll) {
    Copy-Item $CompiledDll $TargetDll -Force
} else {
    throw "UnlockerStub.dll missing at $CompiledDll. Please compile it using cl.exe first."
}

# Bypass external build script
# & $FpsBuildScript

if (Test-Path $PublishTemp) {
    Remove-DirectoryWithRetry -Path $PublishTemp
}

New-Item $PublishTemp -ItemType Directory | Out-Null

try {
    Write-Host "Restoring packages from nuget.org..." -ForegroundColor Cyan
    Invoke-DotNet @(
        "restore",
        $Project,
        "--configfile", $NuGetConfig,
        "-r", $Runtime
    )

    Write-Host ""
    Write-Host "Publishing WebView2 host..." -ForegroundColor Cyan
    Invoke-DotNet @(
        "publish",
        $Project,
        "-c", "Release",
        "-r", $Runtime,
        "--self-contained", "false",
        "--no-restore",
        "-o", $PublishTemp
    )

    $UiExe = Join-Path $PublishTemp "UMM.UI.exe"
    if (-not (Test-Path $UiExe)) {
        throw "Publish finished without creating UMM.UI.exe."
    }

    Copy-Item (Join-Path $PackageRoot "UMM.Engine.ahk") $PublishTemp -Force
    Copy-Item (Join-Path $PackageRoot "README.md") $PublishTemp -Force
    Copy-Item (Join-Path $PackageRoot "CHANGELOG.md") $PublishTemp -Force
    Copy-Item (Join-Path $PackageRoot "SECURITY.md") $PublishTemp -Force
    Copy-Item (Join-Path $PackageRoot "LICENSE") $PublishTemp -Force
    Copy-Item (Join-Path $PackageRoot "THIRD_PARTY_NOTICES.md") $PublishTemp -Force

    $FpsNoticeOutput = Join-Path $PublishTemp "FpsUnlocker"
    New-Item $FpsNoticeOutput -ItemType Directory -Force | Out-Null
    Copy-Item (Join-Path $PackageRoot "FpsUnlocker\LICENSE-UPSTREAM.txt") $FpsNoticeOutput -Force

    $NativeOutput = Join-Path $PublishTemp "Native"
    New-Item $NativeOutput -ItemType Directory -Force | Out-Null
    Copy-Item $TargetDll $NativeOutput -Force

    $DocsOutput = Join-Path $PublishTemp "docs"
    New-Item $DocsOutput -ItemType Directory -Force | Out-Null
    Copy-Item (Join-Path $PackageRoot "docs\MACRO_CREDITS.md") $DocsOutput -Force

    $EngineFile = Join-Path $PackageRoot "UMM.Engine.ahk"
    $EngineText = Get-Content $EngineFile -Raw
    $VersionMatch = [regex]::Match($EngineText, 'global AppVersion := "([^"]+)"')
    $BuildVersion = if ($VersionMatch.Success) { $VersionMatch.Groups[1].Value } else { "unknown" }
    $BuildInfo = [ordered]@{
        version = $BuildVersion
        buildDate = (Get-Date -Format "yyyy-MM-dd")
    }
    $BuildInfoPath = Join-Path $PublishTemp "ui\build-info.json"
    $BuildInfoJson = $BuildInfo | ConvertTo-Json
    $Utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($BuildInfoPath, $BuildInfoJson, $Utf8NoBom)

    $BridgeOutput = Join-Path $PublishTemp "bridge"
    New-Item (Join-Path $BridgeOutput "commands") -ItemType Directory -Force | Out-Null

    $AssetsOutput = Join-Path $PublishTemp "Assets"
    if (Test-Path $Assets) {
        Copy-Item $Assets $AssetsOutput -Recurse -Force
    }
    else {
        New-Item $AssetsOutput -ItemType Directory -Force | Out-Null
    }

    if (Test-Path $Macros) {
        Copy-Item $Macros (Join-Path $PublishTemp "Macros") -Recurse -Force
    }
    else {
        throw "Macros folder was not found: $Macros"
    }

    $StagedRegistry = Join-Path $PublishTemp "Macros\registry.ini"
    if (-not (Test-Path $StagedRegistry)) {
        throw "The staged macro registry was not found: $StagedRegistry"
    }

    $RegistryText = [System.IO.File]::ReadAllText(
        $StagedRegistry,
        [System.Text.Encoding]::UTF8)
    $Utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText(
        $StagedRegistry,
        $RegistryText,
        $Utf8NoBom)

    if (Test-Path $Dist) {
        Remove-DirectoryWithRetry -Path $Dist
    }

    Move-Item $PublishTemp $Dist

    $FinalExe = Join-Path $Dist "UMM.UI.exe"
    $FinalEngine = Join-Path $Dist "UMM.Engine.ahk"
    $FinalRegistry = Join-Path $Dist "Macros\registry.ini"
    $FinalUi = Join-Path $Dist "ui\index.html"
    $FinalLicense = Join-Path $Dist "LICENSE"
    $FinalCredits = Join-Path $Dist "docs\MACRO_CREDITS.md"
    $FinalFpsStub = Join-Path $Dist "Native\UnlockerStub.dll"
    $FinalFpsLicense = Join-Path $Dist "FpsUnlocker\LICENSE-UPSTREAM.txt"

    $RequiredOutputs = @(
        $FinalExe,
        $FinalEngine,
        $FinalRegistry,
        $FinalUi,
        $FinalLicense,
        $FinalCredits,
        $FinalFpsStub,
        $FinalFpsLicense
    )

    foreach ($RequiredOutput in $RequiredOutputs) {
        if (-not (Test-Path $RequiredOutput)) {
            throw "The completed dist folder is missing: $RequiredOutput"
        }
    }

    Write-Host ""
    Write-Host "Build completed successfully:" -ForegroundColor Green
    Write-Host $Dist
    Write-Host ""
    Write-Host "Verified output:" -ForegroundColor Green
    Write-Host $FinalExe
    Write-Host ""
    Write-Host ("Version: {0} | Build date: {1}" -f $BuildVersion, $BuildInfo.buildDate)
    Write-Host "Run dist\UMM.Engine.ahk to start Macro Manager."
}
catch {
    if (Test-Path $PublishTemp) {
        Remove-Item $PublishTemp -Recurse -Force
    }

    throw
}