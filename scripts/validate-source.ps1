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
$indexPath = Join-Path $Root 'UIHost\ui\index.html'
$mainFormPath = Join-Path $Root 'UIHost\MainForm.cs'
$bridgeProtocolPath = Join-Path $Root 'UIHost\BridgeProtocol.cs'
$appManifestPath = Join-Path $Root 'UIHost\app.manifest'
$runtimePath = Join-Path $Root 'Macros\Runtime\MacroRuntime.ahk'
$releaseWorkflowPath = Join-Path $Root '.github\workflows\release.yml'
$licensePath = Join-Path $Root 'LICENSE'
$creditsPath = Join-Path $Root 'docs\MACRO_CREDITS.md'

foreach ($required in @($enginePath, $projectPath, $buildInfoPath, $registryPath, $appJsPath, $stylesPath, $indexPath, $mainFormPath, $bridgeProtocolPath, $appManifestPath, $runtimePath, $releaseWorkflowPath, $licensePath, $creditsPath)) {
    Assert-True (Test-Path $required -PathType Leaf) "Required source file is missing: $required"
}

$engineText = [System.IO.File]::ReadAllText($enginePath) -replace "`r`n?", "`n"
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

$allowedTagValues = @('60 FPS', '120 FPS', '240 FPS', 'TESTING')
function Test-MacroTags {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    $tags = @($Value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($tags.Count -eq 0 -or @($tags | Select-Object -Unique).Count -ne $tags.Count) {
        return $false
    }
    if (@($tags | Where-Object { $allowedTagValues -cnotcontains $_ }).Count -gt 0) {
        return $false
    }

    return @($tags | Where-Object { $_ -like '* FPS' }).Count -le 1
}
$comboSections = [regex]::Matches(
    $registryText,
    '(?ms)^\[Combo\.([^\]]+)\]\s*\r?\n(.*?)(?=^\[|\z)')
$characterCounts = @{}

foreach ($comboSection in $comboSections) {
    $values = @{}
    foreach ($valueMatch in [regex]::Matches($comboSection.Groups[2].Value, '(?m)^([^=\r\n]+)=(.*)$')) {
        $values[$valueMatch.Groups[1].Value.Trim()] = $valueMatch.Groups[2].Value.Trim()
    }

    foreach ($requiredKey in @('Id', 'Character', 'Name', 'Tag', 'Script', 'Order')) {
        Assert-True ($values.ContainsKey($requiredKey)) "Registry section $($comboSection.Groups[1].Value) is missing $requiredKey."
    }

    Assert-True (Test-MacroTags $values.Tag) "Unsupported macro tags '$($values.Tag)' in $($values.Id)."
    $characterCounts[$values.Character] = 1 + [int]($characterCounts[$values.Character])

    $relativeScript = $values.Script.Replace('/', '\')
    $packageDirectory = Split-Path -Parent (Join-Path $Root $relativeScript)
    $manifestPath = Join-Path $packageDirectory 'manifest.ini'
    Assert-True (Test-Path $manifestPath -PathType Leaf) "Managed macro $($values.Id) is missing manifest.ini."

    $manifestText = [System.IO.File]::ReadAllText($manifestPath)
    $manifestMatch = [regex]::Match($manifestText, '(?ms)^\[Macro\]\s*\r?\n(.*?)(?=^\[|\z)')
    Assert-True $manifestMatch.Success "Macro manifest has no [Macro] section: $manifestPath"

    $manifestValues = @{}
    foreach ($valueMatch in [regex]::Matches($manifestMatch.Groups[1].Value, '(?m)^([^=\r\n]+)=(.*)$')) {
        $manifestValues[$valueMatch.Groups[1].Value.Trim()] = $valueMatch.Groups[2].Value.Trim()
    }

    Assert-True ($manifestValues.Id -ceq $values.Id) "Manifest ID differs from the registry for $($values.Id)."
    Assert-True ($manifestValues.Character -ceq $values.Character) "Manifest character differs for $($values.Id)."
    Assert-True ($manifestValues.Name -ceq $values.Name) "Manifest name differs for $($values.Id)."
    Assert-True ($manifestValues.Tag -ceq $values.Tag) "Manifest tag differs for $($values.Id)."
    Assert-True ($manifestValues.ManagedPackage -eq '1') "ManagedPackage=1 is required for $($values.Id)."
    Assert-True ($manifestValues.PackageFormat -eq '2') "PackageFormat=2 is required for $($values.Id)."
}

Assert-True ($comboSections.Count -eq $scriptMatches.Count) 'Every registered script must belong to one complete Combo section.'
foreach ($character in $characterCounts.Keys) {
    Assert-True ($characterCounts[$character] -ge 1) "Character $character has no registered macro."
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
$deadEngineHelpers += @('WebUI_OnCopyData', 'MacroCatalog_ReadRunnerMetadata', 'ToggleSkipStopMode', 'GetCharacterPortraitPath', 'GetShortPathLabel', 'IsIconImagePath')
foreach ($name in $deadEngineHelpers) {
    Assert-True (-not [regex]::IsMatch($engineText, "(?m)^$([regex]::Escape($name))\(")) `
        "Dead child-runtime helper remains in UMM.Engine.ahk: $name"
}

$childAhkText = Get-ChildItem (Join-Path $Root 'Macros') -Recurse -File -Filter '*.ahk' |
    ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }
Assert-True (-not [regex]::IsMatch(($childAhkText -join "`n"), '(?i)\*RunAs|\bA_IsAdmin\b')) `
    'Bundled macro sources must inherit the engine token and must not self-elevate independently.'
Assert-True ([regex]::IsMatch($engineText, '(?m)^if \(!A_IsAdmin\) \{$')) `
    'UMM.Engine.ahk must enforce the Administrator startup policy.'
Assert-True ($engineText.Contains('DllCall("GetCommandLine", "Str")') -and $engineText.Contains('/restart')) `
    'The Administrator relaunch must use a /restart command-line guard.'
Assert-True ([regex]::Matches($engineText, '(?i)\*RunAs').Count -eq 2) `
    'The engine must define exactly the compiled and interpreted guarded elevation commands.'

$appManifestText = [System.IO.File]::ReadAllText($appManifestPath)
Assert-True ([regex]::IsMatch($appManifestText, 'requestedExecutionLevel\s+level="asInvoker"\s+uiAccess="false"')) `
    'UIHost must run asInvoker with uiAccess disabled.'
$csharpText = Get-ChildItem (Join-Path $Root 'UIHost') -Recurse -File -Filter '*.cs' |
    Where-Object { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' } |
    ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }
Assert-True (-not [regex]::IsMatch(($csharpText -join "`n"), '(?i)\bVerb\s*=\s*"runas"')) `
    'C# source must not request Administrator elevation.'

$runtimeText = ([System.IO.File]::ReadAllText($runtimePath) -replace "`r`n?", "`n").Trim()
$inlinedSources = Get-ChildItem (Join-Path $Root 'Macros\User') -Recurse -File -Filter 'source.ahk' |
    Where-Object { [System.IO.File]::ReadAllText($_.FullName).Contains('; ===== BEGIN INLINED: MacroRuntime.ahk =====') }
foreach ($source in $inlinedSources) {
    $sourceText = [System.IO.File]::ReadAllText($source.FullName)
    $inlineMatch = [regex]::Match(
        $sourceText,
        '(?s); ===== BEGIN INLINED: MacroRuntime\.ahk =====\s*\r?\n(.*?)\r?\n; ===== END INLINED: MacroRuntime\.ahk =====')
    Assert-True $inlineMatch.Success "Could not read the inlined runtime in $($source.FullName)."
    $inlineText = ($inlineMatch.Groups[1].Value -replace "`r`n?", "`n").Trim()
    Assert-True ($inlineText -ceq $runtimeText) "The inlined MacroRuntime.ahk copy is stale: $($source.FullName)"
}

$bridgeProtocolText = [System.IO.File]::ReadAllText($bridgeProtocolPath)
Assert-True (-not $bridgeProtocolText.Contains('EngineWindowLocator')) 'Unused EngineWindowLocator remains in BridgeProtocol.cs.'
Assert-True (-not $bridgeProtocolText.Contains('public static bool Send(')) 'Unused WM_COPYDATA sender remains in BridgeProtocol.cs.'
$appJsText = [System.IO.File]::ReadAllText($appJsPath)
Assert-True (-not $appJsText.Contains('function fillSelect(')) 'Unused fillSelect() remains in app.js.'
Assert-True ($engineText.Contains('MacroCatalog_Import(characterName)')) `
    'Macro import must derive display metadata after the user selects an AHK file.'
Assert-True ($engineText.Contains('MacroCatalog_Edit(comboId, comboName, tooltipName, tagName)')) `
    'The engine must support editing existing macro metadata.'
Assert-True (-not $engineText.Contains('MsgBox, 52, Import AutoHotkey macro')) `
    'Macro import must not display the removed confirmation prompt.'
Assert-True (-not $appJsText.Contains('Select this macro')) `
    'Macro cards without a description must not display placeholder text.'
Assert-True (-not $appJsText.Contains('button.dataset.tooltip')) `
    'Macro cards must not recreate the removed hover tooltip.'
$indexText = [System.IO.File]::ReadAllText($indexPath)
Assert-True ($indexText.Contains('<span>Import macro</span>')) `
    'The character page must label the import action as Import macro.'
Assert-True (-not $indexText.Contains('id="macroImportModal"')) `
    'The removed macro import metadata form must not return.'
Assert-True ($indexText.Contains('class="sidebar-icon-toggle sound-feedback-toggle"') -and `
            $indexText.Contains('class="sidebar-icon-toggle theme-toggle"')) `
    'Sound feedback and color theme must remain compact icon controls in the sidebar.'
Assert-True (-not $indexText.Contains('class="surface-card sound-card"') -and `
            -not $indexText.Contains('class="surface-card mode-card"')) `
    'Sound feedback and Application Mode must not return as standalone Dashboard cards.'
Assert-True ([regex]::IsMatch($indexText, 'class="[^"]*\bhero-mode-setting\b[^"]*"')) `
    'Application Mode must remain inside the selected Character Combos card.'
Assert-True ($indexText.Contains('class="hero-dashboard-content"') -and `
            $indexText.Contains('class="hero-dashboard-top"') -and `
            $indexText.Contains('class="quick-card"') -and `
            $indexText.Contains('class="hero-setting-card skip-card"')) `
    'Quick Controls and Skip Dialog Behavior must remain embedded in the Character Combos card.'
Assert-True (-not $indexText.Contains('data-window-action="maximize"')) `
    'The fixed application window must not display a maximize control.'
$mainFormText = [System.IO.File]::ReadAllText($mainFormPath)
Assert-True ($mainFormText.Contains('MaximizeBox = false;')) `
    'The native application window must keep maximize disabled.'
Assert-True ($mainFormText.Contains('MinimumSize = new Size(DefaultClientWidth, DefaultClientHeight);') -and `
            $mainFormText.Contains('MaximumSize = new Size(DefaultClientWidth, DefaultClientHeight);')) `
    'The native application window must keep one fixed size.'
Assert-True (-not $mainFormText.Contains('windowMaximize') -and `
            -not $mainFormText.Contains('HitTestResizeBorder')) `
    'Window maximize and resize-border handling must remain removed.'
Assert-True ($engineText.Contains('WebUI_IsSafeProtocolValue(value, maximumLength)')) `
    'The AHK bridge must validate protocol values without the legacy control-character regex.'
Assert-True (-not $engineText.Contains('InStr(payload, Chr(0))')) `
    'AHK v1 must not search decoded text for Chr(0), because it behaves as an empty-string needle and rejects valid commands.'
Assert-True ($engineText.Contains('commandFile.RawRead(rawPayload, byteCount)')) `
    'Bridge command files must be checked as raw bytes before UTF-8 decoding.'
Assert-True ($engineText.Contains('NumGet(rawPayload, A_Index - 1, "UChar") = 0')) `
    'Bridge command files must reject embedded NUL bytes during raw-byte validation.'
Assert-True ($engineText.Contains('errorId := A_NowUTC')) `
    'Engine errors must include a stable ID for duplicate-delivery suppression.'
Assert-True ($engineText.Contains('"INVALID_BRIDGE_PAYLOAD"')) `
    'Malformed bridge payloads must use a non-retriable protocol error code.'
Assert-True ($appJsText.Contains('function requestState()')) `
    'The UI must throttle state synchronization requests.'
Assert-True ($appJsText.Contains('function navigateToPage(pageName)')) `
    'The UI must animate navigation through the section-navigation helper.'
Assert-True ($appJsText.Contains('function maybeShowUpdatePrompt(message)')) `
    'The UI must present automatic update availability with update and reminder actions.'
$stylesText = [System.IO.File]::ReadAllText($stylesPath)
Assert-True ($stylesText.Contains('@media (prefers-reduced-motion: reduce)')) `
    'Interface animations must provide a reduced-motion fallback.'
Assert-True ($stylesText.Contains('aspect-ratio: 1 / 1')) `
    'Character cards must preserve square 256 x 256 portrait proportions.'
Assert-True ([regex]::IsMatch($stylesText, '(?s)\.character-grid\s*\{[^}]*grid-template-columns:\s*repeat\(4,\s*minmax\(0,\s*1fr\)\)')) `
    'The desktop character grid must keep four cards in each row.'
Assert-True ([regex]::IsMatch($stylesText, '(?s)\.dashboard-layout\s*\{[^}]*grid-template-columns:\s*repeat\(12,\s*minmax\(0,\s*1fr\)\)')) `
    'The desktop dashboard must use the balanced twelve-column card layout.'
Assert-True ([regex]::IsMatch($stylesText, '(?s)\.hero-dashboard-top\s*\{[^}]*grid-template-columns:\s*minmax\(128px,\s*150px\)\s+minmax\(0,\s*1fr\)\s+minmax\(174px,\s*190px\)')) `
    'Quick Controls must remain in the upper-right area of the Character Combos card.'
Assert-True ([regex]::IsMatch($stylesText, '(?s)\.quick-card\s*\{[^}]*width:\s*100%;[^}]*aspect-ratio:\s*1\s*/\s*1')) `
    'Quick Controls must remain a compact square inside the Character Combos card.'
Assert-True ([regex]::IsMatch($stylesText, '(?s)\.hero-settings-grid\s*\{[^}]*grid-template-columns:\s*repeat\(2,\s*minmax\(0,\s*1fr\)\)')) `
    'Application Mode and Skip Dialog Behavior must remain equal-sized controls in the bottom row.'
Assert-True ([regex]::IsMatch($stylesText, '(?s)\.dashboard-layout\s*\{[^}]*align-items:\s*start;')) `
    'Dashboard cards must size to their content instead of stretching to the tallest card in the row.'
$hotkeyHoverRule = [regex]::Match($stylesText, '(?s)\.hotkey-card:hover\s*\{([^}]*)\}')
Assert-True $hotkeyHoverRule.Success 'The Hotkeys page must define a hover treatment for its cards.'
Assert-True (-not $hotkeyHoverRule.Groups[1].Value.Contains('transform:')) `
    'Hotkey-card hover must not move the card, because crossing its transformed boundary causes repeated hover jitter.'
Assert-True ($appJsText.Contains('function ensureHotkeyCards()') -and `
            $appJsText.Contains('if (grid.dataset.initialized === "1") return;')) `
    'Hotkey cards must keep stable DOM nodes instead of being recreated during every state update.'
Assert-True (-not $stylesText.Contains('.combo-option[data-tooltip]')) `
    'Macro-card hover tooltip styles must remain removed.'
$rawStatePostCount = [regex]::Matches($appJsText, 'post\(["'']requestState["'']\)').Count
Assert-True ($rawStatePostCount -eq 1) `
    'All state requests must pass through the single throttled requestState() helper.'
Assert-True (-not (Test-Path (Join-Path $Root '.github\workflows\discord-release.yml'))) `
    'Discord notification must remain in release.yml so GITHUB_TOKEN publishing can trigger it.'

$releaseWorkflowText = [System.IO.File]::ReadAllText($releaseWorkflowPath)
Assert-True ([regex]::IsMatch($releaseWorkflowText, '(?m)^  notify-discord:\s*$')) `
    'release.yml must define notify-discord as a top-level job.'

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
