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
    $rootFullPath = [System.IO.Path]::GetFullPath($Root)
    $rootPrefix = $rootFullPath.TrimEnd([char[]]"\/") +
        [System.IO.Path]::DirectorySeparatorChar

    Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        Where-Object {
            $_.FullName -notmatch '[\\/](\.git|bin|obj|dist|\.publish-temp|bridge)[\\/]'
        } |
        ForEach-Object {
            $fullPath = [System.IO.Path]::GetFullPath($_.FullName)

            if (-not $fullPath.StartsWith(
                    $rootPrefix,
                    [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Source file is outside project root: $fullPath"
            }

            $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
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
$updateServicePath = Join-Path $Root 'UIHost\UpdateService.cs'
$bridgeProtocolPath = Join-Path $Root 'UIHost\BridgeProtocol.cs'
$macroEditorServicePath = Join-Path $Root 'UIHost\MacroEditorService.cs'
$keyboardRecordingServicePath = Join-Path $Root 'UIHost\KeyboardRecordingService.cs'
$appManifestPath = Join-Path $Root 'UIHost\app.manifest'
$runtimePath = Join-Path $Root 'Macros\Runtime\MacroRuntime.ahk'
$releaseWorkflowPath = Join-Path $Root '.github\workflows\release.yml'
$licensePath = Join-Path $Root 'LICENSE'
$creditsPath = Join-Path $Root 'docs\MACRO_CREDITS.md'
$gameDllSettingsPath = Join-Path $Root 'UIHost\GameDllSettingsStore.cs'
$gameLaunchServicePath = Join-Path $Root 'UIHost\GameLaunchService.cs'
$launcherProgramPath = Join-Path $Root 'UIHost\Program.cs'
$fpsServicePath = Join-Path $Root 'UIHost\FpsUnlockService.cs'
$fpsMonitorServicePath = Join-Path $Root 'UIHost\FpsMonitorService.cs'
$fpsOverlayPath = Join-Path $Root 'UIHost\FpsOverlayForm.cs'
$fpsNativePath = Join-Path $Root 'FpsUnlocker\Native\UnlockerStub\dllmain.cpp'
$fpsProjectPath = Join-Path $Root 'FpsUnlocker\Native\UnlockerStub\UnlockerStub.vcxproj'
$fpsLicensePath = Join-Path $Root 'FpsUnlocker\LICENSE-UPSTREAM.txt'
$fpsBuildScriptPath = Join-Path $Root 'scripts\build-fps-unlocker.ps1'
$stageBuildScriptPath = Join-Path $Root 'scripts\build-and-stage.ps1'
$noticesPath = Join-Path $Root 'THIRD_PARTY_NOTICES.md'
$characterLibraryPath = Join-Path $Root 'Assets\characters.txt'
$presentMonPath = Join-Path $Root 'PresentMon\PresentMon-2.5.1-x64.exe'
$presentMonLicensePath = Join-Path $Root 'PresentMon\LICENSE.txt'
$presentMonNoticesPath = Join-Path $Root 'PresentMon\THIRD_PARTY.txt'
$presentMonReadmePath = Join-Path $Root 'PresentMon\README.md'

foreach ($required in @($gameDllSettingsPath, $gameLaunchServicePath, $launcherProgramPath, $enginePath, $projectPath, $buildInfoPath, $registryPath, $appJsPath, $stylesPath, $indexPath, $mainFormPath, $updateServicePath, $bridgeProtocolPath, $macroEditorServicePath, $keyboardRecordingServicePath, $appManifestPath, $runtimePath, $releaseWorkflowPath, $licensePath, $creditsPath, $fpsServicePath, $fpsMonitorServicePath, $fpsOverlayPath, $fpsNativePath, $fpsProjectPath, $fpsLicensePath, $fpsBuildScriptPath, $stageBuildScriptPath, $noticesPath, $characterLibraryPath, $presentMonPath, $presentMonLicensePath, $presentMonNoticesPath, $presentMonReadmePath)) {
    Assert-True (Test-Path $required -PathType Leaf) "Required source file is missing: $required"
    Assert-True ((Get-Item -LiteralPath $required).Length -gt 0) "Required source file is empty: $required"
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

$configuredCharacters = @{}
foreach ($line in [System.IO.File]::ReadAllLines($characterLibraryPath)) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
        continue
    }
    $parts = $trimmed.Split('|')
    Assert-True ($parts.Count -ge 2) "Invalid Assets\characters.txt entry: $trimmed"
    $name = $parts[0].Trim()
    $portrait = $parts[1].Trim()
    $icon = if ($parts.Count -ge 3) { $parts[2].Trim() } else { '' }
    Assert-True (-not [string]::IsNullOrWhiteSpace($name)) 'A configured character name is empty.'
    Assert-True (-not $configuredCharacters.ContainsKey($name.ToLowerInvariant())) "Duplicate configured character: $name"
    Assert-True (Test-Path (Join-Path $Root "Assets\portraits\$portrait") -PathType Leaf) "Configured portrait is missing: $portrait"
    if (-not [string]::IsNullOrWhiteSpace($icon)) {
        Assert-True (Test-Path (Join-Path $Root "Assets\icons\$icon") -PathType Leaf) "Configured icon is missing: $icon"
    }
    $configuredCharacters[$name.ToLowerInvariant()] = $true
}
Assert-True ($configuredCharacters.Count -gt 0) 'Assets\characters.txt must configure at least one character.'
foreach ($character in $characterCounts.Keys) {
    Assert-True ($configuredCharacters.ContainsKey($character.ToLowerInvariant())) "Registry character is not allowed by Assets\characters.txt: $character"
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
Assert-True ($engineText.Contains('CheckAutoHotkeyV11OnFirstRun()') -and `
            $engineText.Contains('AutoHotkeyV11CheckCompleted') -and `
            $engineText.Contains('https://www.autohotkey.com/download/1.1/') -and `
            $engineText.Contains('if (isAvailable)')) `
    'The engine must silently remember a successful first-run AutoHotkey v1.1 prerequisite check and provide the official download link when missing.'

$runtimeText = [System.IO.File]::ReadAllText($runtimePath)
$macroEditorServiceText = [System.IO.File]::ReadAllText($macroEditorServicePath)
$appJsText = [System.IO.File]::ReadAllText($appJsPath)
$indexText = [System.IO.File]::ReadAllText($indexPath)
$mainFormText = [System.IO.File]::ReadAllText($mainFormPath)
$generatedPerformanceSettings = @(
    '#NoEnv',
    '#NoTrayIcon',
    '#SingleInstance Force',
    '#MaxThreadsPerHotkey 1',
    '#MaxThreadsBuffer Off',
    'SendMode Input',
    'SetBatchLines, -1',
    'SetMouseDelay, -1',
    'SetKeyDelay, -1, -1',
    'SetWinDelay, -1',
    'SetControlDelay, -1',
    'SetDefaultMouseSpeed, 0',
    'ListLines, Off',
    'Process, Priority,, High'
)
foreach ($setting in $generatedPerformanceSettings) {
    Assert-True ($runtimeText.Contains($setting)) "Macro runtime is missing generated performance setting: $setting"
    Assert-True ($macroEditorServiceText.Contains('"' + $setting + '"')) `
        "Visual macro generator is missing performance setting: $setting"
}
$generatedRunnerFiles = Get-ChildItem (Join-Path $Root 'Macros\User') -Recurse -File -Filter 'run.ahk'
foreach ($runnerFile in $generatedRunnerFiles) {
    $runnerText = [System.IO.File]::ReadAllText($runnerFile.FullName)
    Assert-True (-not $runnerText.Contains('Macro Manager generated runner v4')) `
        "Outdated generated runner remains: $($runnerFile.FullName)"
    if (-not $runnerText.Contains('Macro Manager generated runner v5')) {
        continue
    }
    foreach ($setting in $generatedPerformanceSettings) {
        Assert-True ($runnerText.Contains($setting)) `
            "Generated runner is missing performance setting '$setting': $($runnerFile.FullName)"
    }
}
Assert-True ($engineText.Contains('Macro Manager generated runner v5')) `
    'The macro importer must generate the current v5 runner format.'
Assert-True ($engineText.Contains('refreshMacroCatalog')) `
    'The engine must reload the catalog after a visual macro is saved.'
Assert-True ($appJsText.Contains('saveMacroDefinition')) `
    'The visual macro editor save action is missing from app.js.'
Assert-True (([System.IO.File]::ReadAllText($indexPath)).Contains('id="macroEditorTotalDuration"') -and `
            $appJsText.Contains('function calculateMacroDuration(')) `
    'The visual macro editor must show its live total duration.'
Assert-True ($macroEditorServiceText.Contains('CanEditEvents = false') -and `
            $macroEditorServiceText.Contains('Macro Manager visual macro v1') -and `
            $macroEditorServiceText.Contains('Never') -and `
            $macroEditorServiceText.Contains('run the AHK event parser for imported or otherwise unknown code')) `
    'Unknown AHK sources must be restricted to metadata-only editing before event parsing.'
Assert-True ($appJsText.Contains('is-metadata-only') -and `
            $appJsText.Contains('macroEditorDocument.canEditEvents') -and `
            $appJsText.Contains('function macroEventCards(')) `
    'The macro editor must hide event editing for unknown sources and group visual events compactly.'
$keyboardRecordingServiceText = [System.IO.File]::ReadAllText($keyboardRecordingServicePath)
Assert-True ($appJsText.Contains('function resolveMacroEventDrop(') -and `
            $appJsText.Contains('drop.destination.list.splice') -and `
            $appJsText.Contains('data-event-command="duplicate"')) `
    'Visual events must support cross-container drag/drop and duplication.'
Assert-True ($indexText.Contains('id="macroRecorderPanel"') -and `
            $indexText.Contains('id="macroRecorderLastWindow"') -and `
            $indexText.Contains('id="macroRecorderKeys"') -and `
            $keyboardRecordingServiceText.Contains('WhKeyboardLl') -and `
            $keyboardRecordingServiceText.Contains('WhMouseLl') -and `
            $keyboardRecordingServiceText.Contains('RecordingOverlayForm')) `
    'The visual editor must provide global timed input recording, filters, and a floating recording control.'
Assert-True ($keyboardRecordingServiceText.Contains('else if (isDown || isUp)') -and `
            -not $keyboardRecordingServiceText.Contains('IsCurrentProcessForegroundWindow') -and `
            $keyboardRecordingServiceText.Contains('0x10 => "Shift"') -and `
            $keyboardRecordingServiceText.Contains('0xA0 => "Shift", 0xA1 => "Shift"') -and `
            $appJsText.Contains('function sendMacroRecordingSettingsNow()') -and `
            -not $appJsText.Contains('macroRecordingSettingsTimer') -and `
            [regex]::IsMatch($appJsText, "(?s)sendMacroRecordingSettingsNow\(\);\s*post\('startMacroRecording'\);")) `
    'Keyboard recording must work while Macro Manager is foreground, normalize Shift, and flush the selected-key filter before recording starts.'
Assert-True ($appJsText.Contains('target: "Recorder"') -and `
            $engineText.Contains('Recorder: "F7"') -and `
            $engineText.Contains('SetRecorderHotkey(newKey') -and `
            -not $indexText.Contains('id="macroRecorderHotkey"')) `
    'The recorder shortcut must live on Hotkeys and use the shared hotkey conflict policy.'
Assert-True (-not $indexText.Contains('Records keys, mouse buttons, and exact delays.') -and `
            $keyboardRecordingServiceText.Contains('public void Reveal(bool persistent)') -and `
            $keyboardRecordingServiceText.Contains('CreateRoundRectRgn')) `
    'The recorder card copy must stay compact and its rounded overlay must auto-hide when idle.'
Assert-True ($indexText.Contains('id="macroClearAllButton"') -and `
            $appJsText.Contains('function clearAllMacroEditorEvents()') -and `
            $appJsText.Contains("addEventListener('click', clearAllMacroEditorEvents)")) `
    'The visual editor must provide a functional Clear all events action.'
Assert-True ($indexText.Contains('id="toggleMacroDetailsButton"') -and `
            $indexText.Contains('id="macroEditorDetailsToggleLabel"') -and `
            $indexText.Contains('aria-controls="macroEditorDetails"') -and `
            $stylesText.Contains('min-width: 96px;') -and `
            $stylesText.Contains('flex: 0 0 auto;') -and `
            $stylesText.Contains('.macro-editor-details-toggle-icon {') -and `
            $appJsText.Contains('function updateMacroDetailsToggle(collapsed)') -and `
            $appJsText.Contains("shell.classList.toggle('details-collapsed')") -and `
            $appJsText.Contains("setAttribute('aria-pressed', String(collapsed))")) `
    'The visual editor must provide an accessible macro-details collapse control.'
Assert-True ($indexText.Contains('id="macroTriggerCaptureButton"') -and `
            $indexText.Contains('Choose custom hotkey') -and `
            -not $indexText.Contains('Runs this macro directly') -and `
            $macroEditorServiceText.Contains('["MacroTrigger"] = metadata.MacroTrigger') -and `
            $engineText.Contains('MacroSpecificTrigger_Down:') -and `
            $engineText.Contains('macroTriggerCombo.character != CurrentCharacter') -and `
            $engineText.Contains('RunMacroProcessById(macroTriggerComboId, macroTriggerKey)')) `
    'A macro-specific trigger must be editable, persisted, conflict checked, character-scoped, and executed directly.'
Assert-True (-not $engineText.Contains('MacroCatalog_PreserveCharacter(') -and `
            -not $engineText.Contains('Import another macro for this character before deleting its last macro.')) `
    'Deleting a final macro must leave character visibility to the developer-owned catalog.'

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
Assert-True (-not $appJsText.Contains('function fillSelect(')) 'Unused fillSelect() remains in app.js.'
Assert-True ($engineText.Contains('MacroCatalog_Import(characterName)')) `
    'Macro import must derive display metadata after the user selects an AHK file.'
Assert-True ($engineText.Contains('MacroCatalog_Edit(comboId, comboName, tooltipName, tagName)')) `
    'The engine must support editing existing macro metadata.'
Assert-True ($engineText.Contains('MacroCatalog_StripManagedExportHeaders(standaloneSource)') -and `
            $engineText.Contains('!metadata.HasKey("name")') -and `
            $engineText.Contains('!metadata.HasKey("tooltip")') -and `
            $engineText.Contains('!metadata.HasKey("tag")')) `
    'Export must remove stale managed headers and import must keep the first metadata header authoritative.'
Assert-True ($engineText.Contains('MacroCatalog_RewriteOrders(originalRegistryText, orderBySection, updatedRegistryText)') -and `
            $engineText.Contains('RegExMatch(registryLine, "i)^\s*Order\s*=")') -and `
            $engineText.Contains('lines.Push("Order=" . orderBySection[currentSectionKey])')) `
    'Macro reordering must normalize existing Order keys and add missing keys before saving.'
Assert-True ($engineText.Contains('MacroCatalog_ComboIdentityExists(characterName, comboName, tooltipName, tagName') -and `
            $macroEditorServiceText.Contains('HasSameCatalogIdentity(item, metadata.Name, metadata.Description, tag)')) `
    'Macro uniqueness must use name, description, and tags rather than name alone.'
Assert-True ($engineText.Contains('MacroCatalog_FindComboByIdentity(characterName, comboName, tooltipName, tagName') -and `
            $engineText.Contains('existingCombo := MacroCatalog_FindComboByIdentity(characterName, comboName, tooltipName, tagName)') -and `
            $engineText.Contains('MacroCatalog_BeginDuplicateImport(importRequest, existingCombo)') -and `
            $engineText.Contains('MacroCatalog_ResolveImportConflict(requestId, decision, renamedName)') -and `
            $engineText.Contains('MacroCatalog_CompleteImport(importRequest, "replace", existingCombo)') -and `
            $engineText.Contains('existingCombo.tooltip != PendingMacroImport.tooltipName') -and `
            $engineText.Contains('MacroCatalog_NormalizeTag(existingCombo.tag) != MacroCatalog_NormalizeTag(PendingMacroImport.tagName)') -and `
            $engineText.Contains('MacroCatalog_ReplaceImported(existingCombo, sourcePath, characterName, comboName, tooltipName, tagName, macroTrigger)') -and `
            $engineText.Contains('MacroCatalog_RollbackImportReplacement(originalRegistryText, macroFolder, backupFolder)') -and `
            $indexText.Contains('id="importConflictModal"') -and `
            $indexText.Contains('id="renameImportConflictButton"') -and `
            $indexText.Contains('id="replaceImportConflictButton"') -and `
            $appJsText.Contains('post("resolveImportConflict"') -and `
            $mainFormText.Contains('["resolveImportConflict"] = CommandFields(') -and `
            -not $engineText.Contains('MsgBox, 35, Macro already exists') -and `
            -not $engineText.Contains('InputBox, renamedName, Change macro name') -and `
            -not $engineText.Contains('MacroCatalog_FindComboByName(') -and `
            -not $engineText.Contains('MacroCatalog_SelectUniqueName(')) `
    'Only identical name, description, and tag AHK imports may open the in-app rollback-aware replace, rename, or cancel dialog.'
Assert-True (-not $engineText.Contains('MsgBox, 52, Import AutoHotkey macro')) `
    'Macro import must not display the removed confirmation prompt.'
Assert-True (-not [regex]::IsMatch($engineText, '(?m)(?:\breturn\b|:=|\bif\b)[^\n]*\(\n[ \t]+[A-Za-z_]')) `
    'UMM.Engine.ahk contains an expression-style function call split after an opening parenthesis; AutoHotkey v1 may parse the next line as an unrecognized action.'
Assert-True (-not $appJsText.Contains('Select this macro')) `
    'Macro cards without a description must not display placeholder text.'
Assert-True (-not $appJsText.Contains('button.dataset.tooltip')) `
    'Macro cards must not recreate the removed hover tooltip.'
Assert-True ($engineText.Contains('candidates.Push(A_ScriptDir . "\dist\UMM.UI.exe")')) `
    'The source-tree engine must prefer the freshly staged dist UI over a legacy root executable.'
$indexText = [System.IO.File]::ReadAllText($indexPath)
$stylesText = [System.IO.File]::ReadAllText($stylesPath)
$mainFormText = [System.IO.File]::ReadAllText($mainFormPath)
$removedHotkeyFocusSentence = 'Hotkeys are active only while the selected game window ' + 'is focused'
Assert-True (-not $indexText.Contains($removedHotkeyFocusSentence) -and `
            -not $appJsText.Contains($removedHotkeyFocusSentence)) `
    'The removed game-focus Hotkeys sentence must not return.'
Assert-True ($indexText.Contains('id="createMacroButton"') -and `
            $indexText.Contains('id="addMacroButton"')) `
    'The character page must provide separate visual creation and AHK import actions.'
$removedMacroEditorCopy = @(
    'NEW VISUAL MACRO',
    'Use the arrows or drag cards',
    'Only the name, description, and tags will be saved',
    'Edit catalog information without reading or changing',
    'Build the action sequence without editing AHK',
    'A new managed AHK file will be created for this character',
    'Saving replaces the selected macro sequence',
    'Saving replaces the selected visual macro sequence'
)
foreach ($removedCopy in $removedMacroEditorCopy) {
    Assert-True (-not $indexText.Contains($removedCopy) -and -not $appJsText.Contains($removedCopy)) `
        "Removed macro-editor copy returned: $removedCopy"
}
$toolbarStart = $indexText.IndexOf('class="macro-command-bar"', [StringComparison]::Ordinal)
$groupMatches = [regex]::Matches($indexText, 'class="macro-command-group(?:\s+[^\"]*)?"')
$importButtonIndex = $indexText.IndexOf('id="addMacroButton"', [StringComparison]::Ordinal)
$exportButtonIndex = $indexText.IndexOf('id="exportMacroButton"', [StringComparison]::Ordinal)
$createButtonIndex = $indexText.IndexOf('id="createMacroButton"', [StringComparison]::Ordinal)
$editButtonIndex = $indexText.IndexOf('id="editMacroButton"', [StringComparison]::Ordinal)
$deleteButtonIndex = $indexText.IndexOf('id="deleteMacroButton"', [StringComparison]::Ordinal)
$toolbarSpacerIndex = $indexText.IndexOf('class="macro-command-spacer"', [StringComparison]::Ordinal)
$dangerGroupIndex = $indexText.IndexOf('macro-command-danger-group', [StringComparison]::Ordinal)
Assert-True ($toolbarStart -ge 0 -and `
            $groupMatches.Count -eq 3 -and `
            $createButtonIndex -gt $toolbarStart -and `
            $editButtonIndex -gt $createButtonIndex -and `
            $importButtonIndex -gt $editButtonIndex -and `
            $exportButtonIndex -gt $importButtonIndex) `
    'Create/Edit and Import/Export must remain grouped and in their expected order.'
Assert-True ($createButtonIndex -gt $toolbarStart -and `
            $toolbarSpacerIndex -gt $exportButtonIndex -and `
            $dangerGroupIndex -gt $toolbarSpacerIndex -and `
            $deleteButtonIndex -gt $dangerGroupIndex) `
    'Delete must remain isolated at the far end of the macro toolbar.'
Assert-True ($indexText.Contains('M12 4v11') -and $indexText.Contains('M12 15V4')) `
    'Import and export must keep visually distinct inward and outward arrow icons.'
Assert-True (-not $indexText.Contains('<span>Create</span>') -and `
            -not $indexText.Contains('<span>Edit</span>') -and `
            -not $indexText.Contains('<span>Delete</span>') -and `
            -not $indexText.Contains('<span>Import AHK</span>') -and `
            -not $indexText.Contains('<span>Export</span>') -and `
            $indexText.Contains('aria-label="Create macro" title="Create macro"') -and `
            $indexText.Contains('aria-label="Import AHK macro" title="Import AHK macro"')) `
    'The Characters toolbar must remain icon-only while retaining accessible labels and hover hints.'
Assert-True ($stylesText.Contains('width: 36px;') -and `
            $stylesText.Contains('min-width: 36px;') -and `
            $stylesText.Contains('flex-wrap: nowrap;')) `
    'The icon-only Characters toolbar must remain compact and on one row.'
Assert-True ([regex]::Matches($indexText, 'class="macro-command-icon"').Count -eq 5 -and `
            [regex]::Matches($indexText, 'stroke="currentColor"').Count -ge 5 -and `
            $stylesText.Contains('visibility: visible !important;')) `
    'All five macro action icons must be embedded SVG strokes with forced visibility.'
Assert-True (-not $indexText.Contains('id="macroImportModal"')) `
    'The removed macro import metadata form must not return.'
Assert-True ($indexText.Contains('class="sidebar-icon-toggle sound-feedback-toggle"') -and `
            $indexText.Contains('class="sidebar-icon-toggle theme-toggle"') -and `
            -not $indexText.Contains('id="soundLabel"') -and `
            -not $indexText.Contains('id="themeLabel"') -and `
            -not $stylesText.Contains('.sidebar-footer::after {') -and `
            [regex]::IsMatch($stylesText, '(?s)\.sidebar-footer\s*\{[^}]*justify-content:\s*center;') -and `
            [regex]::IsMatch($stylesText, '(?s)\.sidebar-icon-toggle\s*\{[^}]*width:\s*42px;[^}]*height:\s*40px;[^}]*flex:\s*0 0 42px;[^}]*border-radius:\s*14px;') -and `
            $stylesText.Contains('.theme-toggle.is-active {') -and `
            $appJsText.Contains('toggle.classList.toggle("is-active", isDark);')) `
    'Sound and theme must remain separate centered icon-only controls with interface-matched rounded corners and distinct active states.'
Assert-True ($indexText.Contains('id="languageMenuButton"') -and `
            $indexText.Contains('id="languageMenuPopover"') -and `
            $indexText.Contains('<circle cx="12" cy="12" r="9"') -and `
            $indexText.Contains('data-language="en"') -and `
            -not $indexText.Contains('title-language-code')) `
    'The titlebar language control must be a clickable globe with English as its only current option.'
Assert-True (-not $indexText.Contains('data-window-action="minimize"') -and `
            -not $indexText.Contains('data-window-action="maximize"') -and `
            -not $appJsText.Contains("post('windowMinimize')") -and `
            -not $mainFormText.Contains('case "windowMinimize":') -and `
            $mainFormText.Contains('MinimizeBox = false;')) `
    'The titlebar must expose only the close action; maximize remains gesture-only.'
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
Assert-True (-not $indexText.Contains('macroStateButton') -and `
            -not $appJsText.Contains('setMacroEnabled') -and `
            -not $engineText.Contains('MacroEnabled') -and `
            -not $engineText.Contains('ToggleScriptEnabled')) `
    'The removed global macro ON/OFF control must not return in the UI, bridge, engine, or tray.'
Assert-True ($indexText.Contains('data-hotkey-scope="Everywhere"') -and `
            $indexText.Contains('data-hotkey-scope="GameOnly"') -and `
            $engineText.Contains('SetHotkeyScope(scopeName)') -and `
            $engineText.Contains('Settings, HotkeyScope, GameOnly')) `
    'Hotkeys must provide persisted Everywhere and Game only activation scopes.'
Assert-True ($appJsText.IndexOf('target: "Recorder"', [StringComparison]::Ordinal) -gt `
            $appJsText.IndexOf('target: "Trigger"', [StringComparison]::Ordinal) -and `
            $appJsText.IndexOf('target: "ModeToggle"', [StringComparison]::Ordinal) -gt `
            $appJsText.IndexOf('target: "Recorder"', [StringComparison]::Ordinal) -and `
            $appJsText.IndexOf('target: "CharacterToggle"', [StringComparison]::Ordinal) -gt `
            $appJsText.IndexOf('target: "ModeToggle"', [StringComparison]::Ordinal) -and `
            $appJsText.IndexOf('target: "ComboToggle"', [StringComparison]::Ordinal) -gt `
            $appJsText.IndexOf('target: "CharacterToggle"', [StringComparison]::Ordinal) -and `
            $appJsText.IndexOf('target: "Interface"', [StringComparison]::Ordinal) -gt `
            $appJsText.IndexOf('target: "ComboToggle"', [StringComparison]::Ordinal) -and `
            $appJsText.Contains('interfaceKey: "F11"') -and `
            $macroEditorServiceText.Contains('["InterfaceKey"] = "F11"') -and `
            $engineText.Contains('Settings, InterfaceKey, F11') -and `
            $engineText.Contains('Interface: "F11"') -and `
            $engineText.Contains('Hotkey, %newHk%, ShowInterface, On') -and `
            $engineText.Contains('WebUI_PromoteWindow(WebUIHwnd, true)') -and `
            $engineText.Contains('WinSet, AlwaysOnTop, Off, ahk_id %hwnd%')) `
    'The Hotkeys page must keep the configurable F11 Interface shortcut after the gameplay function-key controls.'
Assert-True ($indexText.Contains('data-page-panel="fps"') -and `
            $indexText.Contains('id="fpsTargetSlider"') -and `
            $indexText.Contains('id="fpsShowToggle"') -and `
            $indexText.Contains('id="fpsCurrentValue"') -and `
            $appJsText.Contains('post("setFpsTarget"') -and `
            $appJsText.Contains("post('setFpsUnlockEnabled'") -and `
            $appJsText.Contains("post('setFpsOverlayEnabled'")) `
    'The FPS page must expose the limiter controls and independent Show FPS monitor.'
$mainFormText = [System.IO.File]::ReadAllText($mainFormPath)
Assert-True ($mainFormText.Contains('index.html?launch={uiLaunchToken}')) `
    'WebView2 navigation must use a per-launch cache-busting URL.'
Assert-True ($indexText.Contains('styles.css?v=1.7.7-ui-refresh-12') -and `
            $indexText.Contains('app.js?v=1.7.7-ui-refresh-12')) `
    'The UI stylesheet and script must use the current cache-busting token.'
Assert-True ($appJsText.Contains('https://discord.gg/cm3jkdkWAp') -and `
            -not $appJsText.Contains('https://discord.gg/H8HNhvqqm')) `
    'The interface must use the current Discord community invite.'
Assert-True ($appJsText.Contains('function captureMacroEventLayout()') -and `
            $appJsText.Contains('function animateMacroEventLayout(') -and `
            $stylesText.Contains('transform: translateY(-1px) scale(.98);') -and `
            $stylesText.Contains('.hotkey-action .secondary-button:active:not(:disabled)')) `
    'Combo and hotkey micro-press feedback plus timeline motion must remain enabled.'
Assert-True ($appJsText.Contains('post("setTransientTopMost", { active: true })') -and `
            $appJsText.Contains('post("setTransientTopMost", { active: false })') -and `
            $mainFormText.Contains('case "setTransientTopMost":')) `
    'The hotkey capture surface must remain above other applications only while it is open.'
Assert-True ($appJsText.Contains('post("setMacroRecordingTheme", { theme: selectedTheme })') -and `
            -not $appJsText.Contains('const THEME_STORAGE_KEY') -and `
            $appJsText.Contains('localStorage.removeItem("umm-theme");') -and `
            $appJsText.Contains('const systemThemePreference = window.matchMedia("(prefers-color-scheme: light)");') -and `
            $appJsText.Contains('systemThemePreference.addEventListener("change"') -and `
            $appJsText.Contains('const origin = getThemeTransitionOrigin();') -and `
            $appJsText.Contains('Math.hypot(') -and `
            $appJsText.Contains(') + 24;') -and `
            $appJsText.Contains('transition.ready.then(() => {') -and `
            $appJsText.Contains('pseudoElement: "::view-transition-new(root)"') -and `
            $appJsText.Contains('easing: "linear"') -and `
            $appJsText.Contains('fill: "both"') -and `
            $stylesText.Contains('animation: theme-ripple-expand 460ms linear forwards;') -and `
            $keyboardRecordingServiceText.Contains('public void SetTheme(string theme)') -and `
            $keyboardRecordingServiceText.Contains('DrawRecorderGlyph') -and `
            $keyboardRecordingServiceText.Contains('_animationTimer')) `
    'The interface must follow the live device theme, reveal button-triggered changes radially, and keep the floating recorder synchronized.'
Assert-True ($stylesText.Contains('.fps-limiter-card { width: 100%; max-width: none;') -and `
            $stylesText.Contains('.fps-slider-block {') -and `
            -not $stylesText.Contains('width: min(100%, 720px)')) `
    'The FPS panel must scale across the available maximized window width.'
Assert-True ($mainFormText.Contains('MaximizeBox = true;') -and `
            $mainFormText.Contains('case "windowToggleMaximize":') -and `
            -not $indexText.Contains('data-window-action="maximize"') -and `
            $appJsText.Contains("post(event.detail >= 2 ? 'windowToggleMaximize' : 'windowDrag');") -and `
            $mainFormText.Contains('var reachedTopEdge = dragEnd.Y <= targetScreen.Bounds.Top + 8;') -and `
            $mainFormText.Contains('WindowState = FormWindowState.Maximized;')) `
    'The native application window must hide the maximize button while retaining title-bar double-click and drag-to-top maximize gestures.'
Assert-True ($mainFormText.Contains('case "windowClose":') -and `
            $mainFormText.Contains('HideInterfaceWindow();') -and `
            $mainFormText.Contains('eventArgs.CloseReason == CloseReason.UserClosing') -and `
            $mainFormText.Contains('eventArgs.Cancel = true;') -and `
            $mainFormText.Contains('private const int WmPromoteInterface = 0x8001;') -and `
            $mainFormText.Contains('_interfacePromotionTopMost = true;') -and `
            $mainFormText.Contains('Deactivate += (_, _) => ReleaseInterfacePromotion();') -and `
            $mainFormText.Contains('_ = SetForegroundWindow(Handle);') -and `
            $engineText.Contains('PostMessage, 0x8001, 0, 0,, ahk_id %hwnd%') -and `
            -not $engineText.Contains('Sleep, 60')) `
    'Closing the UI must hide its resident process, and F11 must keep the interface above the game until focus returns to the game.'
Assert-True ($indexText.Contains('id="macroUnsavedModal"') -and `
            $indexText.Contains('id="keepEditingMacroButton"') -and `
            $indexText.Contains('id="discardMacroChangesButton"') -and `
            $stylesText.Contains('.modal-backdrop { position: fixed; inset: 0; display: grid; place-items: center; background: rgba(4,5,9,.72); backdrop-filter: blur(12px); z-index: 200; }') -and `
            $stylesText.Contains('#macroEditorModal { z-index: 210; }') -and `
            $stylesText.Contains('#hotkeyModal { z-index: 240; }') -and `
            $stylesText.Contains('#macroUnsavedModal { z-index: 260; }') -and `
            $stylesText.Contains('.toast-container { position: fixed; right: 24px; bottom: 24px; display: grid; gap: 10px; z-index: 300; }') -and `
            $appJsText.Contains('function macroEditorHasUnsavedChanges()') -and `
            $appJsText.Contains('macroEditorBaseline = macroEditorSnapshot();') -and `
            $appJsText.Contains('function requestMacroEditorExit(afterDiscard = null)') -and `
            $appJsText.Contains('post("windowCloseConfirmed")') -and `
            $mainFormText.Contains('case "windowCloseConfirmed":') -and `
            $mainFormText.Contains('["type"] = "windowCloseRequested"')) `
    'Create and edit sessions must show an in-app warning before discarding unsaved macro changes, including native window-close requests.'
$createDraftText = [regex]::Match(
    $macroEditorServiceText,
    '(?s)public MacroEditorDocument CreateDraft\(string character\).*?(?=public string CreatePreview)').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($createDraftText) -and `
            -not $createDraftText.Contains('FindConfiguredCharacter(') -and `
            -not $createDraftText.Contains('The selected character no longer exists.')) `
    'Opening a new macro draft must not reject a selected character merely because it has no registered macros.'
Assert-True ($macroEditorServiceText.Contains('_characterLibraryPath = Path.Combine(_rootDirectory, "Assets", "characters.txt");') -and `
            $macroEditorServiceText.Contains('var configuredCharacter = FindConfiguredCharacter(character);') -and `
            $macroEditorServiceText.Contains('var image = configuredCharacter.Image;') -and `
            $macroEditorServiceText.Contains('if (fields.Length < 2)') -and `
            $macroEditorServiceText.Contains('fields.Length >= 3 ? fields[2].Trim() : string.Empty') -and `
            $macroEditorServiceText.Contains('StringComparison.OrdinalIgnoreCase') -and `
            -not $macroEditorServiceText.Contains('RegistryContainsCharacter(') -and `
            -not $macroEditorServiceText.Contains('GetRegisteredCharacterImage(')) `
    'Draft creation must allow empty characters, while saving must use the same optional-icon character catalog rules as the AHK engine.'
Assert-True ($stylesText.Contains('.nav-item::before {') -and `
            $stylesText.Contains('.nav-item.active::before {') -and `
            $stylesText.Contains('.nav-item.active.nav-animate::before {') -and `
            $stylesText.Contains('@keyframes nav-active-outline-in') -and `
            $stylesText.Contains('animation: nav-active-outline-in .34s') -and `
            $appJsText.Contains('function restartNavEnclosureAnimation(navItem)') -and `
            $appJsText.Contains('restartNavEnclosureAnimation(nextNavItem);')) `
    'The active Dashboard, Characters, Hotkeys, FPS, Startup, and About enclosure must animate when navigation changes.'
Assert-True ($appJsText.Contains('startGameButton.classList.toggle("hidden", !hasExecutable);') -and `
            $appJsText.Contains('startGameButton.disabled = !hasExecutable;') -and `
            $indexText.Contains('id="startGameButton" class="secondary-button dashboard-start-button hidden"')) `
    'Dashboard Start game must remain hidden until a startup executable path is configured.'
Assert-True ($stylesText.Contains('.macro-editor-fps-field::after {') -and `
            $stylesText.Contains('right: 20px;') -and `
            $stylesText.Contains('border-right: 2px solid var(--muted);') -and `
            $stylesText.Contains('transform: rotate(45deg);')) `
    'The macro editor FPS tag must use an inset, consistently aligned chevron.'
Assert-True ($mainFormText.Contains('applicationDirectory.Equals(rootDirectory') -and `
            $mainFormText.Contains('Updating that mixed layout as if it were a runtime package')) `
    'Self-update installation must be limited to a complete packaged runtime root.'
$updateServiceText = [System.IO.File]::ReadAllText($updateServicePath)
Assert-True ($updateServiceText.Contains('Remove-DirectoryContentsWithRetry') -and `
            $updateServiceText.Contains('$activationMode = "in-place"') -and `
            $updateServiceText.Contains('directory swap was blocked')) `
    'The updater must fall back to an in-place, rollback-protected activation when Windows locks the installation directory.'
Assert-True ($updateServiceText.Contains('Native", "UnlockerStub.dll') -and `
            $updateServiceText.Contains('Native", "PresentMon", "PresentMon-2.5.1-x64.exe') -and `
            $updateServiceText.Contains('Assets", "characters.txt') -and `
            $updateServiceText.Contains('Assets\characters.txt') -and `
            $updateServiceText.Contains('Native\PresentMon\THIRD_PARTY.txt') -and `
            $updateServiceText.Contains('new FileInfo(path).Length == 0') -and `
            $updateServiceText.Contains('function Test-RequiredFile') -and `
            $updateServiceText.Contains('function Test-CurrentRuntimeRoot') -and `
            $updateServiceText.Contains('Test-CurrentRuntimeRoot -Root $installRootFull')) `
    'Automatic updates must allow migration from older runtimes while rejecting missing or empty native components in the new payload.'
Assert-True ($mainFormText.Contains('MinimumSize = new Size(920, 600);') -and `
            -not $mainFormText.Contains('MaximumSize = new Size(DefaultClientWidth, DefaultClientHeight);')) `
    'The native application window must remain usable at its minimum size and allow maximization.'
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
Assert-True ($indexText.Contains('draggable="false"') -and `
            $stylesText.Contains('-webkit-user-drag: none;') -and `
            $stylesText.Contains('pointer-events: none;')) `
    'Character portraits must not expose native selection or dragging.'
Assert-True ([regex]::IsMatch($stylesText, '(?s)\.combo-panel-footer\s*\{[^}]*overflow-x:\s*auto;') -and `
            [regex]::IsMatch($stylesText, '(?s)\.macro-command-bar\s*\{[^}]*width:\s*100%;[^}]*display:\s*inline-flex;[^}]*flex:\s*1\s+0\s+auto;') -and `
            $stylesText.Contains('.macro-command-spacer { min-width: 20px; flex: 1 1 auto; }') -and `
            $stylesText.Contains('.macro-command-danger-group {')) `
    'Character macro actions must fill one row while keeping Delete visually isolated.'
Assert-True ($stylesText.Contains('@media (prefers-reduced-motion: reduce)')) `
    'Interface animations must provide a reduced-motion fallback.'
Assert-True ($stylesText.Contains('aspect-ratio: 1 / 1')) `
    'Character cards must preserve square 256 x 256 portrait proportions.'
Assert-True ($indexText.Contains('id="characterCarouselViewport"') -and `
            $indexText.Contains('id="previousCharactersButton"') -and `
            $indexText.Contains('id="nextCharactersButton"') -and `
            $stylesText.Contains('grid-auto-columns: min(256px, calc((100% - 44px) / 4));') -and `
            $stylesText.Contains('grid-auto-columns: calc((100% - 20px) / 2);') -and `
            $stylesText.Contains('grid-auto-columns: calc(100% - 8px);') -and `
            $appJsText.Contains('function updateCharacterCarousel()') -and `
            $appJsText.Contains('scrollCharacterCarousel(-1)') -and `
            $appJsText.Contains('scrollCharacterCarousel(1)') -and `
            $appJsText.Contains('carousel.classList.toggle("can-scroll-previous", canScrollPrevious);') -and `
            $appJsText.Contains('carousel.classList.toggle("can-scroll-next", canScrollNext);') -and `
            $appJsText.Contains('previous.setAttribute("aria-hidden", String(!canScrollPrevious));') -and `
            $appJsText.Contains('next.setAttribute("aria-hidden", String(!canScrollNext));') -and `
            [regex]::IsMatch($stylesText, '(?s)\.character-carousel-button\s*\{[^}]*position:\s*absolute;[^}]*border-radius:\s*50%;') -and `
            [regex]::Matches($indexText, '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m(?:14\.5|9\.5) 6').Count -eq 2 -and `
            $stylesText.Contains('.character-carousel.can-scroll-previous .character-carousel-button.previous,') -and `
            $stylesText.Contains('.character-carousel.can-scroll-next .character-carousel-button.next') -and `
            $stylesText.Contains('.character-carousel-button:disabled { opacity: 0 !important;') -and `
            $stylesText.Contains('.character-carousel-button.previous { left: 12px; }') -and `
            $stylesText.Contains('.character-carousel-button.next { right: 12px; }')) `
    'Character cards must show four at desktop width and expose only the circular edge control that has hidden cards in its direction.'
Assert-True (-not $indexText.Contains('id="addCharacterButton"') -and `
            -not $indexText.Contains('id="removeCharacterButton"') -and `
            -not $indexText.Contains('id="characterAddModal"') -and `
            -not $indexText.Contains('id="characterRemoveModal"') -and `
            -not $appJsText.Contains('post("addCharacter"') -and `
            -not $appJsText.Contains('post("deleteCharacter"') -and `
            -not $mainFormText.Contains('["addCharacter"]') -and `
            -not $mainFormText.Contains('["deleteCharacter"]') -and `
            -not $engineText.Contains('|addCharacter|') -and `
            -not $engineText.Contains('|deleteCharacter|') -and `
            -not $engineText.Contains('MacroCatalog_SetCharacterEnabled(') -and `
            -not $engineText.Contains('MacroCatalog_RemoveCharacter(') -and `
            -not $engineText.Contains('characterLibraryJson=') -and `
            $engineText.Contains('Assets\characters.txt is the developer-owned source of truth.') -and `
            $engineText.Contains('for libraryIndex, characterName in CharacterLibraryOrder') -and `
            $engineText.Contains('CharacterCatalog[characterName] := {name: characterName, image: libraryCharacter.image, combos: []}')) `
    'Character management must be developer-only, with every valid Assets\characters.txt entry shown automatically and no runtime add/remove surface.'
Assert-True ($engineText.Contains('if (currentComboLabel != "")') -and `
            $engineText.Contains('Menu, ModeMenu, Check, %currentComboLabel%')) `
    'A developer-configured character without macros must not check a blank tray-menu item.'
Assert-True ($stylesText.Contains('padding-block: 8px 14px;') -and `
            $stylesText.Contains('scroll-padding-inline: 4px;') -and `
            $stylesText.Contains('scroll-snap-type: x proximity;') -and `
            [regex]::IsMatch($stylesText, '(?s)\.character-grid\s*\{[^}]*padding:\s*4px;') -and `
            $stylesText.Contains('.character-card:last-child { scroll-snap-align: end; }') -and `
            -not $stylesText.Contains('.character-card.active::after {') -and `
            [regex]::IsMatch($stylesText, '(?s)\.character-card:focus-visible\s*\{[^}]*outline:\s*none;[^}]*border-color:\s*var\(--primary\);[^}]*box-shadow:\s*var\(--card-shadow\);') -and `
            [regex]::IsMatch($stylesText, '(?s)\.character-card\.active\s*\{[^}]*border-color:\s*var\(--primary\);[^}]*box-shadow:\s*0\s+10px\s+28px') -and `
            -not [regex]::IsMatch($stylesText, '(?s)\.character-card(?::focus-visible|\.active)\s*\{[^}]*box-shadow:\s*inset') -and `
            $appJsText.Contains('function ensureSelectedCharacterVisible()') -and `
            $appJsText.Contains('const endClearance = 4;') -and `
            $appJsText.Contains('cardRect.right > viewportRect.right - endClearance') -and `
            $appJsText.Contains("window.addEventListener('resize', () => requestAnimationFrame(() => {") -and `
            $stylesText.Contains('.macro-event-card[data-event-type="delay"] > .macro-event-icon') -and `
            $stylesText.Contains('.macro-event-card[data-event-type="loop"] > .macro-event-icon') -and `
            $stylesText.Contains('.macro-fold-chevron {') -and `
            $appJsText.Contains('aria-expanded="${!folded}"')) `
    'Character hover lift, nested event colors, and the loop fold control must remain visually correct.'
Assert-True ([regex]::IsMatch($stylesText, '(?s)\.dashboard-layout\s*\{[^}]*grid-template-columns:\s*repeat\(12,\s*minmax\(0,\s*1fr\)\)')) `
    'The desktop dashboard must use the balanced twelve-column card layout.'
Assert-True ([regex]::IsMatch($stylesText, '(?s)\.hero-dashboard-top\s*\{[^}]*grid-template-columns:\s*minmax\(128px,\s*150px\)\s+minmax\(0,\s*1fr\)\s+minmax\(250px,\s*286px\)')) `
    'Quick Controls must remain in the upper-right area of the Character Combos card.'
Assert-True ($indexText.Contains('id="quickRecorder"') -and `
            $indexText.Contains('id="quickInterface"') -and `
            $indexText.IndexOf('id="quickRecorder"', [StringComparison]::Ordinal) -gt $indexText.IndexOf('id="quickTrigger"', [StringComparison]::Ordinal) -and `
            $indexText.IndexOf('id="quickMode"', [StringComparison]::Ordinal) -gt $indexText.IndexOf('id="quickRecorder"', [StringComparison]::Ordinal) -and `
            $indexText.IndexOf('id="quickInterface"', [StringComparison]::Ordinal) -gt $indexText.IndexOf('id="quickCombo"', [StringComparison]::Ordinal) -and `
            $appJsText.Contains('$("#quickRecorder").textContent = state.recorderHotkey;') -and `
            $appJsText.Contains('$("#quickInterface").textContent = state.interfaceKey;') -and `
            [regex]::IsMatch($stylesText, '(?s)\.quick-hotkeys\s*\{[^}]*grid-template-columns:\s*repeat\(3,\s*minmax\(0,\s*1fr\)\)')) `
    'Quick Controls must fit all six shortcuts in a three-by-two layout.'
Assert-True ([regex]::IsMatch($stylesText, '(?s)\.hero-settings-grid\s*\{[^}]*grid-template-columns:\s*repeat\(2,\s*minmax\(0,\s*1fr\)\)')) `
    'Application Mode and Skip Dialog Behavior must remain equal-sized controls in the bottom row.'
Assert-True ([regex]::IsMatch($stylesText, '(?s)\.dashboard-layout\s*\{[^}]*align-items:\s*start;')) `
    'Dashboard cards must size to their content instead of stretching to the tallest card in the row.'
$hotkeyHoverRule = [regex]::Match($stylesText, '(?s)\.hotkey-card:hover::before\s*\{([^}]*)\}')
Assert-True ($hotkeyHoverRule.Success -and $hotkeyHoverRule.Groups[1].Value.Contains('transform: translateY(-3px)')) `
    'Hotkey cards must provide the requested visual hover lift through a stationary pseudo-element.'
Assert-True ($stylesText.Contains('.hotkey-card:hover > * { transform: translateY(-3px); }')) `
    'Hotkey-card content must lift with its visual surface.'
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

$fpsServiceText = [System.IO.File]::ReadAllText($fpsServicePath)
$fpsMonitorServiceText = [System.IO.File]::ReadAllText($fpsMonitorServicePath)
$fpsOverlayText = [System.IO.File]::ReadAllText($fpsOverlayPath)
$fpsNativeText = [System.IO.File]::ReadAllText($fpsNativePath)
$fpsProjectText = [System.IO.File]::ReadAllText($fpsProjectPath)
$fpsBuildScriptText = [System.IO.File]::ReadAllText($fpsBuildScriptPath)
$stageBuildScriptText = [System.IO.File]::ReadAllText($stageBuildScriptPath)
$fpsLicenseText = [System.IO.File]::ReadAllText($fpsLicensePath)
$noticesText = [System.IO.File]::ReadAllText($noticesPath)
$fpsGuid = '6B78D5B5-2C60-4A7B-9F52-7F8F8B0E1750'
Assert-True ($fpsServiceText.Contains($fpsGuid) -and $fpsNativeText.Contains($fpsGuid)) `
    'The managed and native FPS components must use the same application-specific shared-memory name.'
Assert-True ($fpsServiceText.Contains('Math.Clamp(target, 10, 420)') -and `
            $fpsNativeText.Contains('std::clamp(static_cast<std::int32_t>(ipc->Framerate), 10, 420)')) `
    'The managed and native FPS limits must both remain 10 through 420.'
Assert-True ($fpsServiceText.Contains('_enabled = settings.Enabled') -and `
            $fpsServiceText.Contains('new FpsSettings { Enabled = _enabled, Target = _target, ShowFps = _showFps }') -and `
            $fpsServiceText.Contains('public bool Enabled { get; set; }') -and `
            $fpsServiceText.Contains('private bool _enabled;')) `
    'The FPS limiter must default to disabled on first launch and persist later user changes.'
Assert-True ($fpsServiceText.Contains('public bool ShowFps { get; set; }') -and `
            $fpsServiceText.Contains('_showFps = settings.ShowFps;') -and `
            $mainFormText.Contains('case "setFpsOverlayEnabled":') -and `
            $mainFormText.Contains('["fpsCurrent"] = monitorSnapshot.CurrentFps?.ToString() ?? string.Empty')) `
    'Show FPS must persist independently and publish live monitor state to the WebView.'
Assert-True ($fpsMonitorServiceText.Contains('PresentMon-2.5.1-x64.exe') -or `
            $mainFormText.Contains('PresentMon-2.5.1-x64.exe')) `
    'The FPS monitor must pin the bundled PresentMon 2.5.1 x64 executable.'
foreach ($argument in @('--process_id', '--output_stdout', '--no_console_stats', '--exclude_dropped', '--v2_metrics', '--terminate_on_proc_exit', '--session_name')) {
    Assert-True ($fpsMonitorServiceText.Contains('"' + $argument + '"')) `
        "PresentMon invocation is missing required argument: $argument"
}
Assert-True ($fpsMonitorServiceText.Contains('DisplayedTime') -and `
            $fpsMonitorServiceText.Contains('SplitCsvLine') -and `
            $fpsMonitorServiceText.Contains('SampleWindow') -and `
            $fpsMonitorServiceText.Contains('_overlay.SetTheme(theme);') -and `
            $mainFormText.Contains('_fpsMonitorService.SetTheme(theme);') -and `
            $fpsOverlayText.Contains('ClientSize = new Size(76, 26);') -and `
            $fpsOverlayText.Contains('Opacity = 0.72;') -and `
            $fpsOverlayText.Contains('_lightTheme = string.Equals(theme, "light", StringComparison.Ordinal);') -and `
            $fpsOverlayText.Contains('WsExNoActivate') -and `
            -not $fpsOverlayText.Contains('WsExTransparent') -and `
            $fpsOverlayText.Contains('protected override void OnMouseMove(MouseEventArgs eventArgs)') -and `
            $fpsOverlayText.Contains('StoreRelativePosition()') -and `
            $fpsOverlayText.Contains('IsGameForeground(gameProcessId)')) `
    'Show FPS must use a tiny, translucent, theme-aware, draggable overlay and parse displayed-frame CSV data.'
Assert-True ((Get-FileHash -LiteralPath $presentMonPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq `
            '9bec3083069f58f911e6a512f4806db51a27bd096103087bc1d05ef54c80a191') `
    'The pinned PresentMon binary hash does not match the reviewed official 2.5.1 x64 build.'
Assert-True (([System.IO.File]::ReadAllText($presentMonLicensePath)).Contains('Copyright (C) 2017-2024 Intel Corporation') -and `
            ([System.IO.File]::ReadAllText($presentMonLicensePath)).Contains('Permission is hereby granted, free of charge') -and `
            ([System.IO.File]::ReadAllText($presentMonNoticesPath)).Contains('PresentMon uses third-party sources') -and `
            ([System.IO.File]::ReadAllText($presentMonReadmePath)).Contains('9bec3083069f58f911e6a512f4806db51a27bd096103087bc1d05ef54c80a191')) `
    'PresentMon license and third-party notice files must remain bundled.'
$projectText = [System.IO.File]::ReadAllText($projectPath)
Assert-True ($projectText.Contains('..\PresentMon\PresentMon-2.5.1-x64.exe') -and `
            $projectText.Contains('Link="Native\PresentMon\LICENSE.txt"') -and `
            $projectText.Contains('Link="Native\PresentMon\THIRD_PARTY.txt"') -and `
            $projectText.Contains('Link="Native\PresentMon\README.md"') -and `
            $stageBuildScriptText.Contains('$FinalPresentMon') -and `
            $stageBuildScriptText.Contains('$FinalPresentMonLicense') -and `
            $stageBuildScriptText.Contains('$FinalPresentMonNotices')) `
    'The project and staging build must package PresentMon and all provenance notices.'
Assert-True ($fpsProjectText.Contains('<PlatformToolset>v143</PlatformToolset>') -and `
            $fpsProjectText.Contains('<RuntimeLibrary>MultiThreaded</RuntimeLibrary>')) `
    'The native FPS component must remain an x64 static-runtime Visual Studio build.'
Assert-True ($fpsNativeText.Contains('#include <winternl.h>') -and `
            $fpsNativeText.Contains('NTSTATUS NTAPI LdrAddRefDll') -and `
            $fpsNativeText.Contains('#pragma comment(lib, "User32.lib")')) `
    'The native FPS component must declare LdrAddRefDll with the Windows SDK NT types and link User32.'
Assert-True ($fpsBuildScriptText.Contains('$env:MSVC_PORTABLE_ROOT') -and `
            $fpsBuildScriptText.Contains('setup_x64.bat') -and `
            $fpsBuildScriptText.Contains('Import-BatchEnvironment') -and `
            $fpsBuildScriptText.Contains('Get-Command cl.exe')) `
    'The native build script must support the portable MSVC x64 environment and direct cl.exe builds.'
Assert-True ($fpsLicenseText.Contains('Copyright (c) 2021-Present 34736384') -and `
            $noticesText.Contains('09eddc6393714900cca0fb55bb83cb490acf09b8') -and `
            $noticesText.Contains('PresentMon') -and `
            $noticesText.Contains('version 2.5.1')) `
    'PowerPaimon and PresentMon copyright, license, and pinned version notices must remain present.'

$releaseWorkflowText = [System.IO.File]::ReadAllText($releaseWorkflowPath)
Assert-True ([regex]::IsMatch($releaseWorkflowText, '(?m)^  notify-discord:\s*$')) `
    'release.yml must define notify-discord as a top-level job.'
Assert-True ($releaseWorkflowText.Contains('.\dist\Native\PresentMon\PresentMon-2.5.1-x64.exe') -and `
            $releaseWorkflowText.Contains('.\dist\Native\PresentMon\LICENSE.txt') -and `
            $releaseWorkflowText.Contains('.\dist\Native\PresentMon\THIRD_PARTY.txt') -and `
            $releaseWorkflowText.Contains('.\dist\Native\PresentMon\README.md') -and `
            $releaseWorkflowText.Contains('.\dist\Assets\characters.txt')) `
    'Release verification must require PresentMon and its legal notices.'

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
