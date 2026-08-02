param(
    [switch]$RequireNode
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-ExactRelativeFiles {
    Get-ChildItem $Root -Recurse -File -Force |
        Where-Object {
            $_.FullName -notmatch '[\\/](\.git|bin|obj|dist|\.publish-temp|bridge)[\\/]'
        } |
        ForEach-Object {
            [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/')
        }
}

Write-Host "Validating source tree..." -ForegroundColor Cyan

$enginePath = Join-Path $Root 'UMM.Engine.ahk'
$projectPath = Join-Path $Root 'UIHost\UMM.UI.csproj'
$buildInfoPath = Join-Path $Root 'UIHost\ui\build-info.json'
$registryPath = Join-Path $Root 'Macros\registry.ini'
$appJsPath = Join-Path $Root 'UIHost\ui\app.js'
$stylesPath = Join-Path $Root 'UIHost\ui\styles.css'
$licensePath = Join-Path $Root 'LICENSE'
$creditsPath = Join-Path $Root 'docs\MACRO_CREDITS.md'

foreach ($required in @($enginePath, $projectPath, $buildInfoPath, $registryPath, $appJsPath, $stylesPath, $licensePath, $creditsPath)) {
    Assert-True (Test-Path $required -PathType Leaf) "Required source file is missing: $required"
}

$engineText = [System.IO.File]::ReadAllText($enginePath)
$engineMatch = [regex]::Match($engineText, 'global AppVersion := "([^"]+)"')
Assert-True $engineMatch.Success 'Could not read AppVersion from UMM.Engine.ahk.'

$projectXml = [xml][System.IO.File]::ReadAllText($projectPath)
$projectVersion = 'v' + [string]$projectXml.Project.PropertyGroup.Version
$buildInfo = Get-Content $buildInfoPath -Raw | ConvertFrom-Json

Assert-True ($engineMatch.Groups[1].Value -eq $projectVersion) "Engine and C# versions differ."
Assert-True ($buildInfo.version -eq $projectVersion) "build-info.json version differs from the project version."
Assert-True ($null -eq $buildInfo.buildDate -or [string]::IsNullOrWhiteSpace([string]$buildInfo.buildDate)) `
    'Source build-info.json must not contain a local build date. The build script generates it in dist.'

$registryBytes = [System.IO.File]::ReadAllBytes($registryPath)
$hasBom = $registryBytes.Length -ge 3 -and $registryBytes[0] -eq 0xEF -and $registryBytes[1] -eq 0xBB -and $registryBytes[2] -eq 0xBF
Assert-True (-not $hasBom) 'Macros\registry.ini must be UTF-8 without BOM.'

$registryText = [System.IO.File]::ReadAllText($registryPath, [System.Text.Encoding]::UTF8)
$sections = [regex]::Matches($registryText, '(?m)^\[([^\]]+)\]\s*$') | ForEach-Object { $_.Groups[1].Value }
$duplicateSections = $sections | Group-Object | Where-Object Count -gt 1
Assert-True (-not $duplicateSections) ('Duplicate registry sections: ' + (($duplicateSections.Name) -join ', '))

$comboIds = [regex]::Matches($registryText, '(?m)^Id=(.+?)\s*$') | ForEach-Object { $_.Groups[1].Value.Trim().ToLowerInvariant() }
$duplicateIds = $comboIds | Group-Object | Where-Object Count -gt 1
Assert-True (-not $duplicateIds) ('Duplicate registry macro IDs: ' + (($duplicateIds.Name) -join ', '))

$trackedCase = @(Get-ExactRelativeFiles)
$scriptMatches = [regex]::Matches($registryText, '(?m)^Script=(.+?)\s*$')
foreach ($match in $scriptMatches) {
    $relative = $match.Groups[1].Value.Trim().Replace('\', '/')
    Assert-True (-not [string]::IsNullOrWhiteSpace($relative)) 'A registry Script value is empty.'
    Assert-True ($trackedCase -ccontains $relative) "Registry script path is missing or has incorrect letter case: $relative"
}

$timestampedPackages = Get-ChildItem (Join-Path $Root 'Macros\User') -Directory -Recurse -ErrorAction SilentlyContinue |
    Where-Object Name -Match '^user_.*_\d{14}$'
Assert-True (-not $timestampedPackages) ('Timestamped user package folders are not allowed: ' + (($timestampedPackages.FullName) -join ', '))
Assert-True (-not (Test-Path (Join-Path $Root 'docs\REPOSITORY_INVENTORY.md'))) `
    'docs\REPOSITORY_INVENTORY.md is a stale generated inventory and must not be committed.'

$assetFiles = @($trackedCase | Where-Object { $_ -like 'Assets/*' })
$webFiles = @(
    (Join-Path $Root 'UIHost\ui\styles.css')
    (Join-Path $Root 'UIHost\ui\index.html')
    (Join-Path $Root 'UIHost\ui\app.js')
)
foreach ($webFile in $webFiles) {
    $content = [System.IO.File]::ReadAllText($webFile)
    foreach ($match in [regex]::Matches($content, 'https://assets\.umm/([A-Za-z0-9_ ./%-]+)')) {
        $assetRelative = 'Assets/' + [System.Uri]::UnescapeDataString($match.Groups[1].Value)
        if ([string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($assetRelative))) {
            continue
        }
        Assert-True ($assetFiles -ccontains $assetRelative) "Asset URL is missing or has incorrect letter case: $assetRelative"
    }
}

$functionNames = [regex]::Matches($engineText, '(?m)^([A-Za-z_][A-Za-z0-9_]*)\([^\r\n]*\)\s*\{\s*$') |
    ForEach-Object { $_.Groups[1].Value }
$duplicateFunctions = $functionNames | Group-Object | Where-Object Count -gt 1
Assert-True (-not $duplicateFunctions) ('Duplicate AHK functions: ' + (($duplicateFunctions.Name) -join ', '))

$deadEngineHelpers = @('ShouldContinue', 'PreciseSleep', 'WaitUntil', 'Q_Down', 'Q_Up', 'L_Down', 'L_Up', 'R_Down', 'R_Up', 'E_Down', 'E_Up', 'W_Down', 'W_Up', 'Shift_Down', 'Shift_Up', 'A_Down', 'A_Up', 'D_Down', 'D_Up')
foreach ($name in $deadEngineHelpers) {
    Assert-True (-not [regex]::IsMatch($engineText, "(?m)^$([regex]::Escape($name))\(")) `
        "Dead child-runtime helper remains in UMM.Engine.ahk: $name"
}

$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    & $node.Source --check $appJsPath
    if ($LASTEXITCODE -ne 0) {
        throw 'JavaScript syntax validation failed.'
    }
}
elseif ($RequireNode) {
    throw 'Node.js is required for JavaScript validation.'
}
else {
    Write-Warning 'Node.js was not found; JavaScript syntax check was skipped.'
}

Write-Host "Source validation passed." -ForegroundColor Green
Write-Host "Version: $projectVersion"
Write-Host "Registry scripts: $($scriptMatches.Count)"
