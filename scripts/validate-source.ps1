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
$bridgeProtocolPath = Join-Path $Root 'UIHost\BridgeProtocol.cs'
$macroEditorServicePath = Join-Path $Root 'UIHost\MacroEditorService.cs'
$keyboardRecordingServicePath = Join-Path $Root 'UIHost\KeyboardRecordingService.cs'
$appManifestPath = Join-Path $Root 'UIHost\app.manifest'
$runtimePath = Join-Path $Root 'Macros\Runtime\MacroRuntime.ahk'
$releaseWorkflowPath = Join-Path $Root '.github\workflows\release.yml'
$licensePath = Join-Path $Root 'LICENSE'
$creditsPath = Join-Path $Root 'docs\MACRO_CREDITS.md'
$fpsServicePath = Join-Path $Root 'UIHost\FpsUnlockService.cs'
$fpsNativePath = Join-Path $Root 'FpsUnlocker\Native\UnlockerStub\dllmain.cpp'
$fpsProjectPath = Join-Path $Root 'FpsUnlocker\Native\UnlockerStub\UnlockerStub.vcxproj'
$fpsLicensePath = Join-Path $Root 'FpsUnlocker\LICENSE-UPSTREAM.txt'
$fpsBuildScriptPath = Join-Path $Root 'scripts\build-fps-unlocker.ps1'
$noticesPath = Join-Path $Root 'THIRD_PARTY_NOTICES.md'

foreach ($required in @($enginePath, $projectPath, $buildInfoPath, $registryPath, $appJsPath, $stylesPath, $indexPath, $mainFormPath, $bridgeProtocolPath, $macroEditorServicePath, $keyboardRecordingServicePath, $appManifestPath, $runtimePath, $releaseWorkflowPath, $licensePath, $creditsPath, $fpsServicePath, $fpsNativePath, $fpsProjectPath, $fpsLicensePath, $fpsBuildScriptPath, $noticesPath)) {
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
Assert-True ($engineText.Contains('CheckAutoHotkeyV11OnFirstRun()') -and `
            $engineText.Contains('AutoHotkeyV11CheckCompleted') -and `
            $engineText.Contains('https://www.autohotkey.com/download/1.1/') -and `
            $engineText.Contains('if (isAvailable)')) `
    'The engine must silently remember a successful first-run AutoHotkey v1.1 prerequisite check and provide the official download link when missing.'

$runtimeText = [System.IO.File]::ReadAllText($runtimePath)
$macroEditorServiceText = [System.IO.File]::ReadAllText($macroEditorServicePath)
$appJsText = [System.IO.File]::ReadAllText($appJsPath)
$indexText = [System.IO.File]::ReadAllText($indexPath)
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
            -not $appJsText.Contains('window.confirm("Clear all events from this macro?")') -and `
            $appJsText.Contains("collapsed ? 'Expand' : 'Collapse'")) `
    'The visual editor must clear all events immediately and use Expand/Collapse for macro details.'
Assert-True ($indexText.Contains('id="macroTriggerCaptureButton"') -and `
            $indexText.Contains('Choose custom hotkey') -and `
            -not $indexText.Contains('Runs this macro directly') -and `
            $macroEditorServiceText.Contains('["MacroTrigger"] = metadata.MacroTrigger') -and `
            $engineText.Contains('MacroSpecificTrigger_Down:') -and `
            $engineText.Contains('RunMacroProcessById(macroTriggerComboId, macroTriggerKey)')) `
    'A macro-specific trigger must be editable, persisted, conflict checked, and executed directly.'
Assert-True ($engineText.Contains('MacroCatalog_PreserveCharacter(combo.character, combo.image)') -and `
            $engineText.Contains('SubStr(section, 1, 10) = "Character."') -and `
            -not $engineText.Contains('Import another macro for this character before deleting its last macro.')) `
    'Deleting a final macro must preserve its character card.'

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
Assert-True (-not $engineText.Contains('MsgBox, 52, Import AutoHotkey macro')) `
    'Macro import must not display the removed confirmation prompt.'
Assert-True (-not $appJsText.Contains('Select this macro')) `
    'Macro cards without a description must not display placeholder text.'
Assert-True (-not $appJsText.Contains('button.dataset.tooltip')) `
    'Macro cards must not recreate the removed hover tooltip.'
Assert-True ($engineText.Contains('candidates.Push(A_ScriptDir . "\dist\UMM.UI.exe")')) `
    'The source-tree engine must prefer the freshly staged dist UI over a legacy root executable.'
$indexText = [System.IO.File]::ReadAllText($indexPath)
$stylesText = [System.IO.File]::ReadAllText($stylesPath)
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
$groupMatches = [regex]::Matches($indexText, 'class="macro-command-group"')
$importButtonIndex = $indexText.IndexOf('id="addMacroButton"', [StringComparison]::Ordinal)
$exportButtonIndex = $indexText.IndexOf('id="exportMacroButton"', [StringComparison]::Ordinal)
$createButtonIndex = $indexText.IndexOf('id="createMacroButton"', [StringComparison]::Ordinal)
$editButtonIndex = $indexText.IndexOf('id="editMacroButton"', [StringComparison]::Ordinal)
$deleteButtonIndex = $indexText.IndexOf('id="deleteMacroButton"', [StringComparison]::Ordinal)
Assert-True ($toolbarStart -ge 0 -and `
            $groupMatches.Count -eq 2 -and `
            $importButtonIndex -gt $deleteButtonIndex -and `
            $exportButtonIndex -gt $importButtonIndex) `
    'Import and export must remain together and in that order.'
Assert-True ($createButtonIndex -gt $toolbarStart -and `
            $editButtonIndex -gt $createButtonIndex -and `
            $deleteButtonIndex -gt $editButtonIndex) `
    'Create, edit, and delete must remain together and in that order.'
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
Assert-True ($appJsText.IndexOf('target: "Interface"', [StringComparison]::Ordinal) -gt `
            $appJsText.IndexOf('target: "ComboToggle"', [StringComparison]::Ordinal) -and `
            $appJsText.IndexOf('target: "Recorder"', [StringComparison]::Ordinal) -gt `
            $appJsText.IndexOf('target: "Interface"', [StringComparison]::Ordinal) -and `
            $engineText.Contains('Interface: "F11"') -and `
            $engineText.Contains('Hotkey, %newHk%, ShowInterface, On') -and `
            $engineText.Contains('WebUI_PromoteWindow(WebUIHwnd, true)') -and `
            $engineText.Contains('WinSet, AlwaysOnTop, Off, ahk_id %hwnd%')) `
    'The Hotkeys page must keep the configurable F11 Interface shortcut and place Recorder after it.'
Assert-True ($indexText.Contains('data-page-panel="fps"') -and `
            $indexText.Contains('id="fpsTargetSlider"') -and `
            $appJsText.Contains('post("setFpsTarget"') -and `
            $appJsText.Contains("post('setFpsUnlockEnabled'")) `
    'The FPS page must expose the limiter slider and enable commands.'
$mainFormText = [System.IO.File]::ReadAllText($mainFormPath)
Assert-True ($mainFormText.Contains('index.html?launch={uiLaunchToken}')) `
    'WebView2 navigation must use a per-launch cache-busting URL.'
Assert-True ($indexText.Contains('styles.css?v=1.7.6-ui-refresh-1') -and `
            $indexText.Contains('app.js?v=1.7.6-ui-refresh-1')) `
    'The UI stylesheet and script must use the current cache-busting token.'
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
            $keyboardRecordingServiceText.Contains('public void SetTheme(string theme)') -and `
            $keyboardRecordingServiceText.Contains('Color.FromArgb(24, 105, 72)')) `
    'The floating recorder must follow the selected theme and use a green recording state.'
Assert-True ($stylesText.Contains('.fps-limiter-card { width: 100%; max-width: none;') -and `
            $stylesText.Contains('.fps-slider-block {') -and `
            -not $stylesText.Contains('width: min(100%, 720px)')) `
    'The FPS panel must scale across the available maximized window width.'
Assert-True ($mainFormText.Contains('MaximizeBox = true;') -and `
            $mainFormText.Contains('case "windowToggleMaximize":') -and `
            $indexText.Contains('data-window-action="maximize"')) `
    'The native application window must expose maximize and restore controls.'
Assert-True ($mainFormText.Contains('applicationDirectory.Equals(rootDirectory') -and `
            $mainFormText.Contains('Updating that mixed layout as if it were a runtime package')) `
    'Self-update installation must be limited to a complete packaged runtime root.'
$updateServiceText = [System.IO.File]::ReadAllText((Join-Path $Root 'UIHost\UpdateService.cs'))
Assert-True ($updateServiceText.Contains('Remove-DirectoryContentsWithRetry') -and `
            $updateServiceText.Contains('$activationMode = "in-place"') -and `
            $updateServiceText.Contains('directory swap was blocked')) `
    'The updater must fall back to an in-place, rollback-protected activation when Windows locks the installation directory.'
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
            [regex]::IsMatch($stylesText, '(?s)\.macro-command-bar\s*\{[^}]*display:\s*inline-flex;[^}]*flex:\s*0\s+0\s+auto;')) `
    'Character macro actions must remain compact and on one non-wrapping toolbar row.'
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
$fpsNativeText = [System.IO.File]::ReadAllText($fpsNativePath)
$fpsProjectText = [System.IO.File]::ReadAllText($fpsProjectPath)
$fpsLicenseText = [System.IO.File]::ReadAllText($fpsLicensePath)
$noticesText = [System.IO.File]::ReadAllText($noticesPath)
$fpsGuid = '6B78D5B5-2C60-4A7B-9F52-7F8F8B0E1750'
Assert-True ($fpsServiceText.Contains($fpsGuid) -and $fpsNativeText.Contains($fpsGuid)) `
    'The managed and native FPS components must use the same application-specific shared-memory name.'
Assert-True ($fpsServiceText.Contains('Math.Clamp(target, 10, 420)') -and `
            $fpsNativeText.Contains('std::clamp(static_cast<std::int32_t>(ipc->Framerate), 10, 420)')) `
    'The managed and native FPS limits must both remain 10 through 420.'
Assert-True ($fpsServiceText.Contains('_enabled = settings.Enabled') -and `
            $fpsServiceText.Contains('new FpsSettings { Enabled = _enabled, Target = _target }') -and `
            $fpsServiceText.Contains('public bool Enabled { get; set; }') -and `
            $fpsServiceText.Contains('private bool _enabled;')) `
    'The FPS limiter must default to disabled on first launch and persist later user changes.'
Assert-True ($fpsProjectText.Contains('<PlatformToolset>v143</PlatformToolset>') -and `
            $fpsProjectText.Contains('<RuntimeLibrary>MultiThreaded</RuntimeLibrary>')) `
    'The native FPS component must remain an x64 static-runtime Visual Studio build.'
Assert-True ($fpsLicenseText.Contains('Copyright (c) 2021-Present 34736384') -and `
            $noticesText.Contains('09eddc6393714900cca0fb55bb83cb490acf09b8')) `
    'PowerPaimon upstream copyright, license, and pinned commit notice must remain present.'

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
