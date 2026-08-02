#MaxHotkeysPerInterval 9999
#HotkeyInterval 2000
#KeyHistory 0
#NoEnv
DetectHiddenWindows, On
#SingleInstance Force
#Persistent
#InstallMouseHook
#InstallKeybdHook
#UseHook On
#MaxThreadsPerHotkey 1
#MaxThreadsBuffer Off
SendMode Input
SetBatchLines, -1
SetMouseDelay, -1
SetKeyDelay, -1, -1
SetWinDelay, -1
SetControlDelay, -1
SetDefaultMouseSpeed, 0
ListLines, Off
Process, Priority,, AboveNormal
CoordMode, Mouse, Screen
CoordMode, ToolTip, Screen

if (!A_IsAdmin) {
    try {
        Run, *RunAs "%A_ScriptFullPath%"
    } catch e {
        MsgBox, 48, Macro Manager, Administrator permission is required to run this script.
    }
    ExitApp
}

global CurrentCharacter := ""
global CurrentMacro := ""
global CurrentCatalogSchemaVersion := 4
global MacroEnabled := true
global AppMode := "CharacterCombos"
global SkipStopMode := "Release"
global SoundsEnabled := true
global MacroRunning := false
global StopRequested := false

global TriggerKey := ""
global TriggerDownHotkey := ""
global TriggerUpHotkey := ""
global ComboToggleKey := ""
global ComboToggleHotkey := ""
global CharacterToggleKey := ""
global CharacterToggleHotkey := ""
global ModeToggleKey := ""
global ModeToggleHotkey := ""

global ConfigFile := A_ScriptDir . "\settings.ini"
global LState := false
global RState := false
global QState := false
global FState := false
global EState := false
global WState := false
global ShiftState := false
global AState := false
global DState := false
global TimerResolutionOn := false
global PerformanceModeOn := false
global SkipInitialPressed := "|"
global SkipInterruptKeyList := ""

global AssetsDir := ""
global IconDir := ""
global PortraitDir := ""
global SoundDir := ""
global AppVersion := "v1.6.5"
global AutoLaunchExePath := ""
global AutoLaunchEnabled := true
global WebUIHwnd := 0
global WebUIPid := 0
global WebUIExePath := ""
global WebUIConnected := false
global WebUILaunchTick := 0

global WebBridgeDir := ""
global WebBridgeCommandDir := ""
global WebBridgeStateFile := ""
global WebBridgeLastStateTick := 0
global WebBridgeInitialized := false
global WebNoticeSequence := 0

global MacroRootDir := ""
global MacroRegistryFile := ""
global MacroCatalog := []
global MacroById := {}
global CharacterCatalog := {}
global CharacterOrder := []
global ActiveMacroPid := 0

OnExit, CleanupOnExit

ResolveProjectPaths()
MacroCatalog_Initialize()
LoadHotkeySettings()
LoadRuntimeSettings()
if (AutoLaunchEnabled)
    RunAutoLaunchApp()
SetupTrayMenu()
UpdateTrayText()

WebUI_FileBridgeInitialize()
SetTimer, WebUIFileBridgeTick, 200, -20

if (!LaunchWebUI())
    MsgBox, 48, Macro Manager, Unable to open the WebView2 interface.`nMacro Manager will remain available from the tray menu.
return

ToggleCombo:
    SetMode(GetNextCombo(CurrentCharacter, CurrentMacro), true)
return

ToggleAppMode:
    if (AppMode = "CharacterCombos")
        SetAppMode("SkipDialogs", true)
    else
        SetAppMode("CharacterCombos", true)
return

SelectAppModeCharacterCombos:
    SetAppMode("CharacterCombos")
return

SelectAppModeSkipDialogs:
    SetAppMode("SkipDialogs")
return

ToggleCharacter:
    SetCharacter(GetNextCharacter(CurrentCharacter), true)
return

SelectDynamicCharacter:
    SetCharacter(A_ThisMenuItem)
return

SelectDynamicCombo:
    dynamicComboId := MacroCatalog_FindComboIdByMenuLabel(CurrentCharacter, A_ThisMenuItem)
    if (dynamicComboId != "")
        SetMode(dynamicComboId)
return

Trigger_Down:
    if (MacroRunning)
        return

    if (!MacroEnabled) {
        StopRequested := true
        ReleaseAll()
        ShowShortcutTooltip("Macros: OFF", 900)
        return
    }

    StopRequested := false
    MacroRunning := true
    WebUI_SendState()
    PlayFeedbackSound("trigger")
    StartTimerResolution()

    try {
        if (AppMode = "SkipDialogs")
            Run_SkipDialogs()
        else
            RunSelectedMacroProcess()
    } finally {
        StopActiveMacroProcess()
        ReleaseAll()
        StopTimerResolution()
        MacroRunning := false
        StopRequested := false
        WebUI_SendState()
    }
return

Trigger_Up:
    if (AppMode = "SkipDialogs" && SkipStopMode = "AnyKey")
        return
    StopRequested := true
    StopActiveMacroProcess()
return

WebUIFileBridgeTick:
    WebUI_FileBridgeTick()
return


ShowSettingsGui:
    if (!LaunchWebUI())
        MsgBox, 48, Macro Manager, Unable to open the WebView2 interface.
return

ToggleScriptEnabled:
    if (MacroRunning) {
        ShowModeTooltip("Release the trigger first", 1000)
        return
    }

    MacroEnabled := !MacroEnabled
    if (!MacroEnabled) {
        StopRequested := true
        ReleaseAll()
        PlayFeedbackSound("off")
    } else {
        PlayFeedbackSound("on")
    }

    SaveRuntimeSettings()
    SetupTrayMenu()
    SetTrayIconByCharacter()
    UpdateTrayText()
    WebUI_SendState()
    ShowModeTooltip("Macros: " . (MacroEnabled ? "ON" : "OFF"), 1000)
return

ResetAllHotkeys:
    ResetHotkeysToDefault()
return

ReloadScript:
    Reload
return

ExitScript:
    ExitApp
return

TrayNoOp:
return


WebUI_FileBridgeInitialize() {
    global WebBridgeDir, WebBridgeCommandDir, WebBridgeStateFile
    global WebBridgeInitialized, WebBridgeLastStateTick

    WebBridgeDir := A_ScriptDir . "\bridge"
    WebBridgeCommandDir := WebBridgeDir . "\commands"
    WebBridgeStateFile := WebBridgeDir . "\state.txt"

    FileCreateDir, %WebBridgeDir%
    FileCreateDir, %WebBridgeCommandDir%

    ; Remove abandoned temporary files and stale commands from previous runs.
    Loop, Files, %WebBridgeCommandDir%\*.tmp, F
        FileDelete, %A_LoopFileFullPath%

    Loop, Files, %WebBridgeCommandDir%\*.cmd, F
        FileDelete, %A_LoopFileFullPath%

    WebBridgeInitialized := true
    WebBridgeLastStateTick := 0
    WebUI_FileBridgeWriteState()
    return true
}


WebUI_FileBridgeTick() {
    global MacroRunning, WebBridgeInitialized, WebBridgeLastStateTick

    if (!WebBridgeInitialized)
        return

    ; Priority -20 prevents this timer from interrupting normal-priority macro
    ; execution. This guard also avoids disk access while a combo is running.
    if (MacroRunning)
        return

    WebUI_FileBridgeProcessCommands()

    if ((A_TickCount - WebBridgeLastStateTick) >= 1000)
        WebUI_FileBridgeWriteState()
}


WebUI_FileBridgeProcessCommands() {
    global WebBridgeCommandDir
    global WebUIHwnd, WebUIPid, WebUIConnected, WebUILaunchTick

    pattern := WebBridgeCommandDir . "\*.cmd"

    Loop, Files, %pattern%, F
    {
        commandPath := A_LoopFileFullPath
        payload := ""

        try {
            commandFile := FileOpen(commandPath, "r", "UTF-8")
            if IsObject(commandFile) {
                payload := commandFile.Read()
                commandFile.Close()
            }
        } catch e {
            payload := ""
        }

        ; Delete first so a command is never executed twice.
        FileDelete, %commandPath%

        if (payload = "")
            continue

        message := WebUI_ParsePayload(payload)
        action := message.HasKey("action") ? message.action : ""
        if (action = "")
            continue

        if (action = "uiReady") {
            if (message.HasKey("uiPid") && (message.uiPid + 0) > 0)
                WebUIPid := message.uiPid + 0
            if (message.HasKey("hwnd") && (message.hwnd + 0) > 0)
                WebUIHwnd := message.hwnd + 0

            WebUIConnected := true
            WebUILaunchTick := 0
            WebUI_FileBridgeWriteState()
            continue
        }

        if (action = "uiClosed") {
            closedPid := message.HasKey("uiPid") ? (message.uiPid + 0) : 0
            if (!closedPid || closedPid = WebUIPid) {
                WebUIHwnd := 0
                WebUIPid := 0
                WebUIConnected := false
                WebUILaunchTick := 0
            }
            continue
        }

        WebUI_HandleCommand(message)
    }
}


WebUI_FileBridgeWriteState(payload := "") {
    global WebBridgeStateFile, WebBridgeLastStateTick, WebBridgeInitialized
    global MacroEnabled, SoundsEnabled, MacroRunning, AppMode, SkipStopMode
    global CurrentCharacter, CurrentMacro
    global TriggerKey, ComboToggleKey, CharacterToggleKey, ModeToggleKey
    global AutoLaunchExePath, AutoLaunchEnabled, AppVersion

    if (!WebBridgeInitialized || WebBridgeStateFile = "")
        return false

    if (payload = "") {
        enginePid := DllCall("GetCurrentProcessId", "UInt")
        payload := "type=state"
            . "`nconnected=1"
            . "`nenginePid=" . enginePid
            . "`nheartbeat=" . A_TickCount
            . "`nmacroEnabled=" . (MacroEnabled ? 1 : 0)
            . "`nsoundsEnabled=" . (SoundsEnabled ? 1 : 0)
            . "`nmacroRunning=" . (MacroRunning ? 1 : 0)
            . "`nappMode=" . AppMode
            . "`nskipStopMode=" . SkipStopMode
            . "`ncharacter=" . CurrentCharacter
            . "`ncombo=" . CurrentMacro
            . "`ncomboDisplay=" . GetComboDisplay(CurrentMacro)
            . "`ncatalogJson=" . MacroCatalog_ToJson()
            . "`ntriggerKey=" . TriggerKey
            . "`ncomboToggleKey=" . ComboToggleKey
            . "`ncharacterToggleKey=" . CharacterToggleKey
            . "`nmodeToggleKey=" . ModeToggleKey
            . "`nautoLaunchPath=" . AutoLaunchExePath
            . "`nautoLaunchEnabled=" . (AutoLaunchEnabled ? 1 : 0)
            . "`nversion=" . AppVersion
            . "`nisAdmin=" . (A_IsAdmin ? 1 : 0)
    }

    tempPath := WebBridgeStateFile . "." . DllCall("GetCurrentProcessId", "UInt") . ".tmp"
    FileDelete, %tempPath%

    success := false
    try {
        stateFile := FileOpen(tempPath, "w", "UTF-8-RAW")
        if IsObject(stateFile) {
            stateFile.Write(payload)
            stateFile.Close()
            FileMove, %tempPath%, %WebBridgeStateFile%, 1
            success := !ErrorLevel
        }
    } catch e {
        success := false
    }

    if (success)
        WebBridgeLastStateTick := A_TickCount
    else
        FileDelete, %tempPath%

    return success
}


WebUI_FindWindowByPid(processId) {
    if (!processId)
        return 0

    WinGet, windowList, List, ahk_pid %processId%
    Loop, %windowList%
    {
        hwnd := windowList%A_Index%
        if (hwnd && DllCall("IsWindow", "Ptr", hwnd))
            return hwnd
    }

    return 0
}


WebUI_ActivateExisting() {
    global WebUIHwnd, WebUIPid, WebUIConnected, WebUILaunchTick

    if (WebUIHwnd && DllCall("IsWindow", "Ptr", WebUIHwnd)) {
        WinShow, ahk_id %WebUIHwnd%
        WinRestore, ahk_id %WebUIHwnd%
        WinActivate, ahk_id %WebUIHwnd%
        WebUI_SendState()
        return true
    }

    WebUIHwnd := 0

    if (!WebUIPid)
        return false

    Process, Exist, %WebUIPid%
    if (ErrorLevel != WebUIPid) {
        WebUIPid := 0
        WebUIConnected := false
        WebUILaunchTick := 0
        return false
    }

    discoveredHwnd := WebUI_FindWindowByPid(WebUIPid)
    if (discoveredHwnd) {
        WebUIHwnd := discoveredHwnd
        WebUIConnected := true
        WinShow, ahk_id %WebUIHwnd%
        WinRestore, ahk_id %WebUIHwnd%
        WinActivate, ahk_id %WebUIHwnd%
        WebUI_SendState()
        return true
    }

    ; The process exists but its window is not ready yet. During the first
    ; five seconds this is a normal startup race, so never launch a duplicate.
    if (WebUILaunchTick && (A_TickCount - WebUILaunchTick) < 5000)
        return true

    ; A UI process without a window after the startup period is stale.
    WebUIPid := 0
    WebUIConnected := false
    WebUILaunchTick := 0
    return false
}


LaunchWebUI() {
    global WebUIHwnd, WebUIPid, WebUIExePath, WebUILaunchTick

    if (WebUI_ActivateExisting())
        return true

    WebUIExePath := ResolveWebUIExePath()
    if (WebUIExePath = "") {
        TrayTip, Macro Manager, WebView2 UI executable was not found. Build UIHost and place UMM.UI.exe beside this script., 5, 2
        return false
    }

    SplitPath, WebUIExePath, uiExeName, uiExeDir
    enginePid := DllCall("GetCurrentProcessId", "UInt")
    command := """" . WebUIExePath . """ --engine-hwnd " . A_ScriptHwnd
        . " --engine-pid " . enginePid
        . " --root """ . A_ScriptDir . """"

    WebUILaunchTick := A_TickCount
    Run, %command%, %uiExeDir%, UseErrorLevel, WebUIPid
    if (ErrorLevel) {
        WebUIPid := 0
        WebUILaunchTick := 0
        TrayTip, Macro Manager, Failed to start the WebView2 interface., 5, 3
        return false
    }

    return true
}

ResolveWebUIExePath() {
    candidates := []
    candidates.Push(A_ScriptDir . "\UMM.UI.exe")
    candidates.Push(A_ScriptDir . "\UMM.UI\UMM.UI.exe")
    candidates.Push(A_ScriptDir . "\UIHost\bin\Release\net8.0-windows\win-x64\publish\UMM.UI.exe")
    candidates.Push(A_ScriptDir . "\UIHost\bin\Release\net8.0-windows\publish\UMM.UI.exe")

    for index, candidate in candidates {
        if FileExist(candidate)
            return candidate
    }

    return ""
}

WebUI_OnCopyData(wParam, lParam) {
    global WebUIHwnd, WebUIPid, WebUIConnected, WebUILaunchTick

    if (!lParam)
        return false

    cbData := NumGet(lParam + A_PtrSize, 0, "UInt")
    dataPtr := NumGet(lParam + (2 * A_PtrSize), 0, "UPtr")
    if (!dataPtr || cbData < 2)
        return false

    payload := StrGet(dataPtr, (cbData // 2) - 1, "UTF-16")
    message := WebUI_ParsePayload(payload)
    action := message.HasKey("action") ? message.action : ""

    if (action = "uiReady") {
        sender := message.HasKey("hwnd") ? (message.hwnd + 0) : (wParam + 0)
        if (sender) {
            WebUIHwnd := sender
            WebUIConnected := true
            WebUILaunchTick := 0
        }
        if (message.HasKey("uiPid") && (message.uiPid + 0) > 0)
            WebUIPid := message.uiPid + 0
        WebUI_SendState()
        return true
    }

    if (action = "uiClosed") {
        closedPid := message.HasKey("uiPid") ? (message.uiPid + 0) : 0
        if (!closedPid || closedPid = WebUIPid) {
            WebUIHwnd := 0
            WebUIPid := 0
            WebUIConnected := false
            WebUILaunchTick := 0
        }
        return true
    }

    if (wParam)
        WebUIHwnd := wParam

    WebUI_HandleCommand(message)
    return true
}

WebUI_ParsePayload(payload) {
    result := {}

    Loop, Parse, payload, `n, `r
    {
        line := A_LoopField
        equalsPos := InStr(line, "=")
        if (!equalsPos)
            continue

        key := SubStr(line, 1, equalsPos - 1)
        value := SubStr(line, equalsPos + 1)
        result[key] := value
    }

    return result
}

WebUI_HandleCommand(message) {
    global MacroRunning, MacroEnabled, SoundsEnabled, SkipStopMode
    global AutoLaunchExePath, AutoLaunchEnabled, ConfigFile

    action := message.HasKey("action") ? message.action : ""
    value := message.HasKey("value") ? message.value : ""

    if (action = "requestState") {
        WebUI_SendState()
        return
    }

    if (action = "setCharacter") {
        if (MacroRunning) {
            WebUI_SendError("Release the trigger before changing character.")
            return
        }
        SetCharacter(value)
        return
    }

    if (action = "setCombo") {
        if (MacroRunning) {
            WebUI_SendError("Release the trigger before changing combo.")
            return
        }
        SetMode(value)
        return
    }

    if (action = "setAppMode") {
        if (MacroRunning) {
            WebUI_SendError("Release the trigger before changing mode.")
            return
        }
        SetAppMode(value)
        return
    }

    if (action = "setMacroEnabled") {
        desired := WebUI_ToBool(value)
        WebUI_SetMacroEnabled(desired)
        return
    }

    if (action = "setSoundsEnabled") {
        desired := WebUI_ToBool(value)
        if (desired != SoundsEnabled)
            ToggleSoundsEnabled()
        else
            WebUI_SendState()
        return
    }

    if (action = "setSkipStopMode") {
        if (value != "Release" && value != "AnyKey") {
            WebUI_SendError("Invalid skip-dialog behavior.")
            return
        }
        if (SkipStopMode != value) {
            SkipStopMode := value
            SaveRuntimeSettings()
            }
        WebUI_SendState()
        return
    }

    if (action = "importMacro") {
        characterName := message.HasKey("character") ? message.character : ""
        comboName := message.HasKey("comboName") ? message.comboName : ""
        tooltipName := message.HasKey("tooltip") ? message.tooltip : ""
        tagName := message.HasKey("tag") ? message.tag : ""
        MacroCatalog_Import(characterName, comboName, tooltipName, tagName)
        return
    }

    if (action = "deleteMacro") {
        comboId := message.HasKey("comboId") ? message.comboId : value
        MacroCatalog_DeleteImported(comboId)
        return
    }

    if (action = "exportMacro") {
        comboId := message.HasKey("comboId") ? message.comboId : value
        MacroCatalog_Export(comboId)
        return
    }

    if (action = "reorderMacros") {
        if (MacroRunning) {
            WebUI_SendError("Release the trigger before reordering macros.")
            return
        }

        characterName := message.HasKey("character") ? message.character : ""
        orderedComboIds := message.HasKey("comboIds") ? message.comboIds : ""
        MacroCatalog_Reorder(characterName, orderedComboIds)
        return
    }

    if (action = "setHotkey") {
        target := message.HasKey("target") ? message.target : ""
        WebUI_SetHotkey(target, value)
        return
    }

    if (action = "resetHotkeys") {
        if (MacroRunning) {
            WebUI_SendError("Release the trigger before resetting hotkeys.")
            return
        }
        ResetHotkeysToDefault()
        SetupTrayMenu()
        UpdateTrayText()
        WebUI_SendState()
        return
    }

    if (action = "setAutoLaunchPath") {
        if (value = "") {
            ClearAutoLaunchExePath()
            return
        }

        SplitPath, value, fileName, fileDir, fileExt
        StringLower, fileExt, fileExt
        if (!FileExist(value) || fileExt != "exe") {
            WebUI_SendError("Select a valid executable file.")
            return
        }

        AutoLaunchExePath := value
        IniWrite, %AutoLaunchExePath%, %ConfigFile%, Settings, AutoLaunchExe
        WebUI_SendState()
        ShowModeTooltip("Game executable saved", 1000)
        return
    }

    if (action = "setAutoLaunchEnabled") {
        AutoLaunchEnabled := WebUI_ToBool(value)
        IniWrite, % (AutoLaunchEnabled ? 1 : 0), %ConfigFile%, Settings, AutoLaunchEnabled
        WebUI_SendState()
        return
    }

    if (action = "browseAutoLaunch") {
        BrowseForAutoLaunchExe(false)
        return
    }

    if (action = "startGame") {
        RunAutoLaunchApp(true)
        return
    }

    if (action = "clearAutoLaunch") {
        ClearAutoLaunchExePath()
        return
    }

    if (action = "reloadEngine") {
        Reload
        return
    }

    if (action = "exitEngine") {
        ExitApp
        return
    }
}

WebUI_SetMacroEnabled(desired) {
    global MacroRunning, MacroEnabled, StopRequested

    if (MacroRunning) {
        WebUI_SendError("Release the trigger before changing macro state.")
        return false
    }

    desired := desired ? true : false
    if (MacroEnabled = desired) {
        WebUI_SendState()
        return true
    }

    MacroEnabled := desired
    if (!MacroEnabled) {
        StopRequested := true
        ReleaseAll()
        PlayFeedbackSound("off")
    } else {
        PlayFeedbackSound("on")
    }

    SaveRuntimeSettings()
    SetupTrayMenu()
    SetTrayIconByCharacter()
    UpdateTrayText()
    WebUI_SendState()
    ShowModeTooltip("Macros: " . (MacroEnabled ? "ON" : "OFF"), 1000)
    return true
}

WebUI_SetHotkey(target, newKey) {
    global MacroRunning

    if (MacroRunning) {
        WebUI_SendError("Release the trigger before changing hotkeys.")
        return false
    }

    if (!IsAllowedKeyForTarget(newKey, target)) {
        WebUI_SendError("This key is reserved, invalid, or already assigned.")
        return false
    }

    success := false
    if (target = "Trigger")
        success := SetTriggerHotkey(newKey, true)
    else if (target = "ComboToggle")
        success := SetComboToggleHotkey(newKey, true)
    else if (target = "CharacterToggle")
        success := SetCharacterToggleHotkey(newKey, true)
    else if (target = "ModeToggle")
        success := SetModeToggleHotkey(newKey, true)

    if (!success) {
        WebUI_SendError("AutoHotkey could not register that key.")
        return false
    }

    SetupTrayMenu()
    UpdateTrayText()
    WebUI_SendState()
    ShowModeTooltip("Hotkey updated", 900)
    return true
}

WebUI_ToBool(value) {
    StringLower, lowerValue, value
    return (lowerValue = "1" || lowerValue = "true" || lowerValue = "on" || lowerValue = "yes")
}

WebUI_SendState() {
    global WebUIHwnd

    fileResult := WebUI_FileBridgeWriteState()

    messageResult := false
    if (WebUIHwnd && DllCall("IsWindow", "Ptr", WebUIHwnd)) {
        global MacroEnabled, SoundsEnabled, MacroRunning, AppMode, SkipStopMode
        global CurrentCharacter, CurrentMacro
        global TriggerKey, ComboToggleKey, CharacterToggleKey, ModeToggleKey
        global AutoLaunchExePath, AutoLaunchEnabled, AppVersion

        payload := "type=state"
            . "`nconnected=1"
            . "`nmacroEnabled=" . (MacroEnabled ? 1 : 0)
            . "`nsoundsEnabled=" . (SoundsEnabled ? 1 : 0)
            . "`nmacroRunning=" . (MacroRunning ? 1 : 0)
            . "`nappMode=" . AppMode
            . "`nskipStopMode=" . SkipStopMode
            . "`ncharacter=" . CurrentCharacter
            . "`ncombo=" . CurrentMacro
            . "`ncomboDisplay=" . GetComboDisplay(CurrentMacro)
            . "`ncatalogJson=" . MacroCatalog_ToJson()
            . "`ntriggerKey=" . TriggerKey
            . "`ncomboToggleKey=" . ComboToggleKey
            . "`ncharacterToggleKey=" . CharacterToggleKey
            . "`nmodeToggleKey=" . ModeToggleKey
            . "`nautoLaunchPath=" . AutoLaunchExePath
            . "`nautoLaunchEnabled=" . (AutoLaunchEnabled ? 1 : 0)
            . "`nversion=" . AppVersion
            . "`nisAdmin=" . (A_IsAdmin ? 1 : 0)

        messageResult := WebUI_SendMessage(payload)
    }

    return fileResult || messageResult
}

WebUI_SendNotice(message) {
    global WebBridgeDir, WebNoticeSequence

    WebNoticeSequence += 1
    noticeId := A_NowUTC . "-" . A_TickCount . "-" . WebNoticeSequence

    safeMessage := StrReplace(message, "`r", " ")
    safeMessage := StrReplace(safeMessage, "`n", " ")
    payload := "type=notice`nmessage=" . safeMessage
        . "`ncreatedUtc=" . A_NowUTC
        . "`nnoticeId=" . noticeId

    messageFile := WebBridgeDir . "\error.txt"
    tempFile := messageFile . ".tmp"
    FileDelete, %tempFile%
    try {
        output := FileOpen(tempFile, "w", "UTF-8-RAW")
        if IsObject(output) {
            output.Write(payload)
            output.Close()
            FileMove, %tempFile%, %messageFile%, 1
        }
    } catch e {
        FileDelete, %tempFile%
    }
    WebUI_SendMessage(payload)
}

WebUI_SendError(message) {
    global WebBridgeDir

    safeMessage := StrReplace(message, "`r", " ")
    safeMessage := StrReplace(safeMessage, "`n", " ")
    payload := "type=error`nmessage=" . safeMessage

    errorFile := WebBridgeDir . "\error.txt"
    tempFile := errorFile . ".tmp"
    FileDelete, %tempFile%

    try {
        output := FileOpen(tempFile, "w", "UTF-8-RAW")
        if IsObject(output) {
            output.Write(payload)
            output.Close()
            FileMove, %tempFile%, %errorFile%, 1
        }
    } catch e {
        FileDelete, %tempFile%
    }

    WebUI_SendMessage(payload)
}

WebUI_SendMessage(payload) {
    global WebUIHwnd, WebUIConnected

    if (!WebUIHwnd || !DllCall("IsWindow", "Ptr", WebUIHwnd)) {
        WebUIHwnd := 0
        WebUIConnected := false
        return false
    }

    VarSetCapacity(copyData, 3 * A_PtrSize, 0)
    byteCount := (StrLen(payload) + 1) * 2
    NumPut(1, copyData, 0, "UPtr")
    NumPut(byteCount, copyData, A_PtrSize, "UInt")
    NumPut(&payload, copyData, 2 * A_PtrSize, "UPtr")

    senderHwnd := A_ScriptHwnd
    dataAddress := &copyData
    SendMessage, 0x4A, %senderHwnd%, %dataAddress%,, ahk_id %WebUIHwnd%,,,, 1000
    if (ErrorLevel = "FAIL") {
        WebUIHwnd := 0
        WebUIConnected := false
        return false
    }

    WebUIConnected := true
    return true
}


MacroCatalog_Initialize() {
    global MacroRootDir, MacroRegistryFile

    MacroRootDir := A_ScriptDir . "\Macros"
    MacroRegistryFile := MacroRootDir . "\registry.ini"

    if !InStr(FileExist(MacroRootDir), "D")
        FileCreateDir, %MacroRootDir%
    if !InStr(FileExist(MacroRootDir . "\User"), "D")
        FileCreateDir, % MacroRootDir . "\User"

    if (!FileExist(MacroRegistryFile)) {
        MsgBox, 48, Macro Manager, Macro registry was not found:`n%MacroRegistryFile%
        ExitApp
    }

    ; AutoHotkey v1 INI enumeration can ignore the first section when a
    ; UTF-8 BOM appears directly before its opening bracket.
    if (!MacroCatalog_RemoveUtf8Bom()) {
        MsgBox, 48, Macro Manager, The macro registry encoding could not be normalized:`n%MacroRegistryFile%
        ExitApp
    }

    ; Compatibility migrations are schema-gated and normally run once.
    ; Daily startup reads only the dynamic registry after the schema is current.
    if (!MacroCatalog_ApplyMigrations()) {
        MsgBox, 48, Macro Manager, Some legacy macro packages could not be upgraded.`nThey will be retried on the next startup.
    }

    ; Convert registered timestamped import folders and IDs to the stable
    ; package format. Failures remain registered under their previous ID.
    if (!MacroCatalog_NormalizeLegacyImportedPackages())
        MsgBox, 48, Macro Manager, Some older imported macro package names could not be normalized.`nThey will be retried on the next startup.

    ; Recover complete manifest-backed packages that are missing from the
    ; registry. Source-only folders are intentionally ignored.
    MacroCatalog_RegisterOrphanImports()

    if (!MacroCatalog_Load()) {
        MsgBox, 48, Macro Manager, No valid macro packages were found in:`n%MacroRegistryFile%
        ExitApp
    }
}

MacroCatalog_RemoveUtf8Bom() {
    global MacroRegistryFile

    inputFile := FileOpen(MacroRegistryFile, "r")
    if (!IsObject(inputFile))
        return false

    fileLength := inputFile.Length
    if (fileLength < 3) {
        inputFile.Close()
        return true
    }

    firstByte := inputFile.ReadUChar()
    secondByte := inputFile.ReadUChar()
    thirdByte := inputFile.ReadUChar()

    if (firstByte != 0xEF || secondByte != 0xBB || thirdByte != 0xBF) {
        inputFile.Close()
        return true
    }

    remainingLength := fileLength - 3
    VarSetCapacity(fileData, remainingLength, 0)
    bytesRead := 0

    if (remainingLength > 0)
        bytesRead := inputFile.RawRead(fileData, remainingLength)

    inputFile.Close()

    if (remainingLength > 0 && bytesRead != remainingLength)
        return false

    tempPath := MacroRegistryFile . ".nobom." . A_TickCount . ".tmp"
    FileDelete, %tempPath%

    outputFile := FileOpen(tempPath, "w")
    if (!IsObject(outputFile))
        return false

    bytesWritten := 0
    if (remainingLength > 0)
        bytesWritten := outputFile.RawWrite(fileData, remainingLength)

    outputFile.Close()

    if (remainingLength > 0 && bytesWritten != remainingLength) {
        FileDelete, %tempPath%
        return false
    }

    FileMove, %tempPath%, %MacroRegistryFile%, 1
    if (ErrorLevel) {
        FileDelete, %tempPath%
        return false
    }

    return true
}


MacroCatalog_NormalizePackagePath(path) {
    path := StrReplace(path, "/", "\")
    path := RTrim(path, "\")
    StringLower, path, path
    return path
}

MacroCatalog_ReadRunnerMetadata(runnerPath, ByRef executionMode, ByRef detectedTrigger) {
    executionMode := ""
    detectedTrigger := ""

    if (!FileExist(runnerPath))
        return false

    FileRead, runnerText, %runnerPath%
    if (ErrorLevel)
        return false

    if RegExMatch(runnerText, "im)^; Original trigger detected automatically:\s*(.+?)\s*$", triggerMatch) {
        executionMode := "AutoTrigger"
        detectedTrigger := Trim(triggerMatch1)
    } else if InStr(runnerText, "IsFunc(" . Chr(34) . "RunMacro" . Chr(34) . ")") {
        executionMode := "RunMacro"
    } else {
        executionMode := "AutoExecute"
    }

    return true
}

MacroCatalog_ReadPackageManifest(manifestPath) {
    metadata := {}

    if (!FileExist(manifestPath))
        return metadata

    FileRead, manifestText, %manifestPath%
    if (ErrorLevel)
        return metadata

    if (Asc(SubStr(manifestText, 1, 1)) = 0xFEFF)
        manifestText := SubStr(manifestText, 2)

    inMacroSection := false
    Loop, Parse, manifestText, `n, `r
    {
        line := Trim(A_LoopField, " `t")
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue

        if (SubStr(line, 1, 1) = "[" && SubStr(line, 0) = "]") {
            sectionName := Trim(SubStr(line, 2, StrLen(line) - 2))
            StringLower, sectionName, sectionName
            inMacroSection := (sectionName = "macro")
            continue
        }

        if (!inMacroSection)
            continue

        separator := InStr(line, "=")
        if (!separator)
            continue

        keyName := Trim(SubStr(line, 1, separator - 1))
        keyValue := Trim(SubStr(line, separator + 1))
        StringLower, keyName, keyName
        metadata[keyName] := keyValue
    }

    return metadata
}

MacroCatalog_ReadExportMetadata(sourcePath) {
    metadata := {}

    if (!FileExist(sourcePath))
        return metadata

    FileRead, sourceText, %sourcePath%
    if (ErrorLevel)
        return metadata

    if (Asc(SubStr(sourceText, 1, 1)) = 0xFEFF)
        sourceText := SubStr(sourceText, 2)

    foundHeader := false
    Loop, Parse, sourceText, `n, `r
    {
        if (A_Index > 40)
            break

        line := Trim(A_LoopField, " `t")
        if (line = "; Macro Manager export") {
            foundHeader := true
            continue
        }

        if (!foundHeader) {
            if (line != "" && SubStr(line, 1, 1) != ";")
                break
            continue
        }

        if (line = "")
            break
        if (SubStr(line, 1, 1) != ";")
            break

        if (!RegExMatch(line, "i)^;\s*([^:]+):\s*(.*)$", fieldMatch))
            continue

        fieldName := Trim(fieldMatch1)
        fieldValue := Trim(fieldMatch2)
        StringLower, fieldName, fieldName

        if (fieldName = "character")
            metadata["character"] := fieldValue
        else if (fieldName = "macro")
            metadata["name"] := fieldValue
        else if (fieldName = "tooltip")
            metadata["tooltip"] := fieldValue
        else if (fieldName = "tag")
            metadata["tag"] := fieldValue
        else if (fieldName = "execution mode")
            metadata["executionmode"] := fieldValue
        else if (fieldName = "detected trigger")
            metadata["detectedtrigger"] := fieldValue
    }

    return metadata
}

MacroCatalog_WritePackageManifest(manifestPath, comboId, characterName, imageName, comboName, tooltipName, tagName) {
    manifestText := "[Macro]`r`n"
        . "Id=" . comboId . "`r`n"
        . "Character=" . characterName . "`r`n"
        . "Image=" . imageName . "`r`n"
        . "Name=" . comboName . "`r`n"
        . "Tooltip=" . tooltipName . "`r`n"
        . "Tag=" . tagName . "`r`n"
        . "Source=source.ahk`r`n"
        . "ManagedPackage=1`r`n"
        . "PackageFormat=2`r`n"
        . "Version=2`r`n"

    return MacroCatalog_WriteAtomicText(manifestPath, manifestText)
}

MacroCatalog_NormalizeLegacyImportedPackages() {
    global MacroRegistryFile, ConfigFile

    knownIds := {}
    IniRead, sections, %MacroRegistryFile%
    if (sections = "ERROR")
        return true

    Loop, Parse, sections, `n, `r
    {
        section := Trim(A_LoopField)
        if (SubStr(section, 1, 6) != "Combo.")
            continue

        IniRead, knownId, %MacroRegistryFile%, %section%, Id,
        knownId := Trim(knownId)
        if (knownId != "")
            knownIds[knownId] := true
    }

    failedCount := 0
    Loop, Parse, sections, `n, `r
    {
        oldSection := Trim(A_LoopField)
        if (SubStr(oldSection, 1, 6) != "Combo.")
            continue

        IniRead, oldId, %MacroRegistryFile%, %oldSection%, Id,
        IniRead, characterName, %MacroRegistryFile%, %oldSection%, Character,
        IniRead, imageName, %MacroRegistryFile%, %oldSection%, Image,
        IniRead, comboName, %MacroRegistryFile%, %oldSection%, Name,
        IniRead, tooltipName, %MacroRegistryFile%, %oldSection%, Tooltip,
        IniRead, tagName, %MacroRegistryFile%, %oldSection%, Tag,
        IniRead, scriptRelative, %MacroRegistryFile%, %oldSection%, Script,
        IniRead, builtInValue, %MacroRegistryFile%, %oldSection%, BuiltIn, 0
        IniRead, orderValue, %MacroRegistryFile%, %oldSection%, Order, 0
        IniRead, executionMode, %MacroRegistryFile%, %oldSection%, ExecutionMode,
        IniRead, detectedTrigger, %MacroRegistryFile%, %oldSection%, DetectedTrigger,

        oldId := Trim(oldId)
        characterName := Trim(characterName)
        comboName := Trim(comboName)
        scriptRelative := Trim(scriptRelative)

        if (builtInValue != 0 || oldId = "" || characterName = "" || comboName = "" || scriptRelative = "")
            continue

        oldScript := MacroCatalog_ResolvePath(scriptRelative)
        SplitPath, oldScript, , oldPackageDir
        SplitPath, oldPackageDir, oldPackageName, characterDir

        if (SubStr(oldId, 1, 5) != "user_" && SubStr(oldPackageName, 1, 5) != "user_")
            continue

        sourcePath := oldPackageDir . "\source.ahk"
        if (!FileExist(sourcePath)) {
            failedCount += 1
            continue
        }

        newId := ""
        newPackageName := ""
        if (!MacroCatalog_SelectStableIdentity(characterName, comboName, characterDir, oldPackageDir, knownIds, newId, newPackageName)) {
            failedCount += 1
            continue
        }

        newPackageDir := characterDir . "\" . newPackageName
        movedPackage := false

        if (MacroCatalog_NormalizePackagePath(newPackageDir) != MacroCatalog_NormalizePackagePath(oldPackageDir)) {
            FileMoveDir, %oldPackageDir%, %newPackageDir%, 0
            if (ErrorLevel) {
                failedCount += 1
                continue
            }
            movedPackage := true
        } else {
            newPackageDir := oldPackageDir
        }

        newSource := newPackageDir . "\source.ahk"
        newRunner := newPackageDir . "\run.ahk"
        normalizedMode := ""
        normalizedTrigger := ""

        if (!MacroCatalog_CreateImportedRunner(newSource, newRunner, newId, normalizedMode, normalizedTrigger)) {
            if (movedPackage)
                FileMoveDir, %newPackageDir%, %oldPackageDir%, 0
            failedCount += 1
            continue
        }

        if (executionMode = "")
            executionMode := normalizedMode
        if (detectedTrigger = "")
            detectedTrigger := normalizedTrigger

        newSection := "Combo." . newId
        newRelativeScript := SubStr(newRunner, StrLen(A_ScriptDir) + 2)

        IniWrite, %newId%, %MacroRegistryFile%, %newSection%, Id
        IniWrite, %characterName%, %MacroRegistryFile%, %newSection%, Character
        IniWrite, %imageName%, %MacroRegistryFile%, %newSection%, Image
        IniWrite, %comboName%, %MacroRegistryFile%, %newSection%, Name
        IniWrite, %tooltipName%, %MacroRegistryFile%, %newSection%, Tooltip
        IniWrite, %tagName%, %MacroRegistryFile%, %newSection%, Tag
        IniWrite, %newRelativeScript%, %MacroRegistryFile%, %newSection%, Script
        IniWrite, 0, %MacroRegistryFile%, %newSection%, BuiltIn
        IniWrite, %orderValue%, %MacroRegistryFile%, %newSection%, Order
        IniWrite, %executionMode%, %MacroRegistryFile%, %newSection%, ExecutionMode
        IniWrite, %detectedTrigger%, %MacroRegistryFile%, %newSection%, DetectedTrigger

        if (ErrorLevel) {
            IniDelete, %MacroRegistryFile%, %newSection%
            if (movedPackage)
                FileMoveDir, %newPackageDir%, %oldPackageDir%, 0
            failedCount += 1
            continue
        }

        manifestPath := newPackageDir . "\manifest.ini"
        if (!MacroCatalog_WritePackageManifest(manifestPath, newId, characterName, imageName, comboName, tooltipName, tagName)) {
            IniDelete, %MacroRegistryFile%, %newSection%
            if (movedPackage)
                FileMoveDir, %newPackageDir%, %oldPackageDir%, 0
            failedCount += 1
            continue
        }

        IniDelete, %MacroRegistryFile%, %oldSection%
        if (ErrorLevel) {
            IniDelete, %MacroRegistryFile%, %newSection%
            if (movedPackage)
                FileMoveDir, %newPackageDir%, %oldPackageDir%, 0
            oldManifestPath := oldPackageDir . "\manifest.ini"
            MacroCatalog_WritePackageManifest(oldManifestPath, oldId, characterName, imageName, comboName, tooltipName, tagName)
            failedCount += 1
            continue
        }

        IniRead, savedCombo, %ConfigFile%, State, Combo,
        if (savedCombo = oldId)
            IniWrite, %newId%, %ConfigFile%, State, Combo

        IniRead, savedLastCombo, %ConfigFile%, LastCombo, %characterName%,
        if (savedLastCombo = oldId)
            IniWrite, %newId%, %ConfigFile%, LastCombo, %characterName%

        knownIds.Delete(oldId)
        knownIds[newId] := true
    }

    return (failedCount = 0)
}


MacroCatalog_RegisterOrphanImports() {
    global MacroRegistryFile, MacroRootDir

    registeredPackages := {}
    knownIds := {}
    maximumOrder := 0

    IniRead, sections, %MacroRegistryFile%
    if (sections != "ERROR") {
        Loop, Parse, sections, `n, `r
        {
            section := Trim(A_LoopField)
            if (SubStr(section, 1, 6) != "Combo.")
                continue

            IniRead, registeredId, %MacroRegistryFile%, %section%, Id,
            IniRead, registeredCharacter, %MacroRegistryFile%, %section%, Character,
            IniRead, registeredScript, %MacroRegistryFile%, %section%, Script,
            IniRead, registeredOrder, %MacroRegistryFile%, %section%, Order, 0

            registeredId := Trim(registeredId)
            registeredCharacter := Trim(registeredCharacter)
            registeredScript := Trim(registeredScript)

            if (registeredId != "")
                knownIds[registeredId] := true

            if (registeredScript != "") {
                absoluteScript := MacroCatalog_ResolvePath(registeredScript)
                SplitPath, absoluteScript, , registeredDir
                if (registeredDir != "")
                    registeredPackages[MacroCatalog_NormalizePackagePath(registeredDir)] := true
            }

            registeredOrder += 0
            if (registeredOrder > maximumOrder)
                maximumOrder := registeredOrder
        }
    }

    userRoot := MacroRootDir . "\User"
    if !InStr(FileExist(userRoot), "D")
        return 0

    recoveredCount := 0
    characterPattern := userRoot . "\*"

    Loop, Files, %characterPattern%, D
    {
        characterFolder := A_LoopFileName
        characterDir := A_LoopFileFullPath

        if (characterFolder = ".trash" || SubStr(characterFolder, 1, 1) = ".")
            continue

        packagePattern := characterDir . "\*"
        Loop, Files, %packagePattern%, D
        {
            packageDir := A_LoopFileFullPath
            packageKey := MacroCatalog_NormalizePackagePath(packageDir)

            if (registeredPackages.HasKey(packageKey))
                continue

            manifestPath := packageDir . "\manifest.ini"
            sourcePath := packageDir . "\source.ahk"

            ; Never publish a folder just because it contains executable code.
            ; Automatic recovery requires an explicit package manifest.
            if (!FileExist(manifestPath) || !FileExist(sourcePath))
                continue

            manifestMetadata := MacroCatalog_ReadPackageManifest(manifestPath)
            exportMetadata := MacroCatalog_ReadExportMetadata(sourcePath)

            characterName := Trim(manifestMetadata["character"])
            if (!MacroCatalog_IsSafeField(characterName, 50))
                continue
            if (MacroCatalog_Slug(characterName) != characterFolder)
                continue

            comboName := Trim(manifestMetadata["name"])
            if (!MacroCatalog_IsSafeField(comboName, 60))
                comboName := Trim(exportMetadata["name"])
            if (!MacroCatalog_IsSafeField(comboName, 60))
                continue

            tooltipName := Trim(manifestMetadata["tooltip"])
            if (tooltipName = "")
                tooltipName := Trim(exportMetadata["tooltip"])
            if (tooltipName != "" && !MacroCatalog_IsSafeField(tooltipName, 80))
                tooltipName := ""

            tagName := Trim(manifestMetadata["tag"])
            if (!MacroCatalog_IsAllowedTag(tagName))
                tagName := Trim(exportMetadata["tag"])
            if (!MacroCatalog_IsAllowedTag(tagName))
                tagName := ""

            imageName := Trim(manifestMetadata["image"])
            if (!MacroCatalog_IsSafeField(imageName, 80))
                imageName := characterName . ".png"

            comboId := ""
            packageName := ""
            if (!MacroCatalog_SelectStableIdentity(characterName, comboName, characterDir, packageDir, knownIds, comboId, packageName))
                continue

            targetDir := characterDir . "\" . packageName
            if (MacroCatalog_NormalizePackagePath(targetDir) != packageKey) {
                FileMoveDir, %packageDir%, %targetDir%, 0
                if (ErrorLevel)
                    continue

                packageDir := targetDir
                packageKey := MacroCatalog_NormalizePackagePath(packageDir)
                manifestPath := packageDir . "\manifest.ini"
                sourcePath := packageDir . "\source.ahk"
            }

            runnerPath := packageDir . "\run.ahk"
            executionMode := ""
            detectedTrigger := ""

            ; Recreate the runner so generated labels use the stable combo ID.
            if (!MacroCatalog_CreateImportedRunner(sourcePath, runnerPath, comboId, executionMode, detectedTrigger))
                continue

            relativeScript := SubStr(runnerPath, StrLen(A_ScriptDir) + 2)
            maximumOrder += 10
            section := "Combo." . comboId

            IniWrite, %comboId%, %MacroRegistryFile%, %section%, Id
            IniWrite, %characterName%, %MacroRegistryFile%, %section%, Character
            IniWrite, %imageName%, %MacroRegistryFile%, %section%, Image
            IniWrite, %comboName%, %MacroRegistryFile%, %section%, Name
            IniWrite, %tooltipName%, %MacroRegistryFile%, %section%, Tooltip
            IniWrite, %tagName%, %MacroRegistryFile%, %section%, Tag
            IniWrite, %relativeScript%, %MacroRegistryFile%, %section%, Script
            IniWrite, 0, %MacroRegistryFile%, %section%, BuiltIn
            IniWrite, %maximumOrder%, %MacroRegistryFile%, %section%, Order
            IniWrite, %executionMode%, %MacroRegistryFile%, %section%, ExecutionMode
            IniWrite, %detectedTrigger%, %MacroRegistryFile%, %section%, DetectedTrigger

            if (ErrorLevel) {
                IniDelete, %MacroRegistryFile%, %section%
                continue
            }

            if (!MacroCatalog_WritePackageManifest(manifestPath, comboId, characterName, imageName, comboName, tooltipName, tagName)) {
                IniDelete, %MacroRegistryFile%, %section%
                continue
            }

            knownIds[comboId] := true
            registeredPackages[packageKey] := true
            recoveredCount += 1
        }
    }

    return recoveredCount
}

MacroCatalog_ApplyMigrations() {
    global ConfigFile, CurrentCatalogSchemaVersion

    IniRead, savedSchema, %ConfigFile%, System, CatalogSchemaVersion, 0
    if (savedSchema = "ERROR" || savedSchema = "")
        savedSchema := 0
    savedSchema += 0

    if (savedSchema < 1) {
        MacroCatalog_MigrateLegacyBuiltIns()
        if (MacroCatalog_HasLegacyBuiltIns())
            return false

        savedSchema := 1
        IniWrite, %savedSchema%, %ConfigFile%, System, CatalogSchemaVersion
    }

    if (savedSchema < CurrentCatalogSchemaVersion) {
        MacroCatalog_UpgradeImportedRunners()
        if (MacroCatalog_HasOutdatedGeneratedRunners())
            return false

        savedSchema := CurrentCatalogSchemaVersion
        IniWrite, %savedSchema%, %ConfigFile%, System, CatalogSchemaVersion
    }

    return true
}

MacroCatalog_HasLegacyBuiltIns() {
    global MacroRegistryFile

    IniRead, sections, %MacroRegistryFile%
    if (sections = "ERROR")
        return false

    Loop, Parse, sections, `n, `r
    {
        section := Trim(A_LoopField)
        if (SubStr(section, 1, 6) != "Combo.")
            continue

        IniRead, builtInValue, %MacroRegistryFile%, %section%, BuiltIn, 0
        if (builtInValue = 1)
            return true
    }

    return false
}

MacroCatalog_HasOutdatedGeneratedRunners() {
    global MacroRegistryFile

    IniRead, sections, %MacroRegistryFile%
    if (sections = "ERROR")
        return false

    Loop, Parse, sections, `n, `r
    {
        section := Trim(A_LoopField)
        if (SubStr(section, 1, 6) != "Combo.")
            continue

        IniRead, scriptRelative, %MacroRegistryFile%, %section%, Script,
        scriptRelative := Trim(scriptRelative)
        if (scriptRelative = "")
            continue

        runnerPath := MacroCatalog_ResolvePath(scriptRelative)
        SplitPath, runnerPath, runnerName
        StringLower, runnerNameLower, runnerName
        if (runnerNameLower != "run.ahk" || !FileExist(runnerPath))
            continue

        FileRead, runnerText, %runnerPath%
        if (ErrorLevel)
            continue

        if InStr(runnerText, "Macro Manager generated runner v4")
            continue

        if InStr(runnerText, "Macro Manager generated runner v1")
            return true
        if InStr(runnerText, "Macro Manager generated runner v2")
            return true
        if InStr(runnerText, "Macro Manager generated runner v3")
            return true
        if InStr(runnerText, "#Include %A_ScriptDir%\source.ahk")
            return true
    }

    return false
}

MacroCatalog_BuildStandaloneSource(sourcePath, visited := "") {
    if (!FileExist(sourcePath))
        return ""

    if (!IsObject(visited))
        visited := {}

    sourceKey := sourcePath
    StringLower, sourceKey, sourceKey
    if (visited.HasKey(sourceKey))
        return "; Skipped recursive include: " . sourcePath . "`r`n"
    visited[sourceKey] := true

    SplitPath, sourcePath, sourceName, sourceDir
    FileRead, sourceText, %sourcePath%
    if (ErrorLevel)
        return ""

    output := ""
    Loop, Parse, sourceText, `n, `r
    {
        line := A_LoopField

        if RegExMatch(line
            , "i)^\s*#Include(?:Again)?\s+(?:\*i\s+)?%A_ScriptDir%\\(.+?\.ahk)\s*$"
            , includeMatch) {
            includeRelative := includeMatch1
            includePath := sourceDir . "\" . includeRelative

            if FileExist(includePath) {
                includeText := MacroCatalog_BuildStandaloneSource(includePath, visited)
                if (includeText != "") {
                    output .= "`r`n; ===== BEGIN INLINED: "
                        . includeRelative . " =====`r`n"
                    output .= includeText
                    if (SubStr(output, 0) != "`n")
                        output .= "`r`n"
                    output .= "; ===== END INLINED: "
                        . includeRelative . " =====`r`n`r`n"
                    continue
                }
            }
        }

        output .= line . "`r`n"
    }

    return output
}

MacroCatalog_MigrateLegacyBuiltIns() {
    global MacroRegistryFile, MacroRootDir

    IniRead, sections, %MacroRegistryFile%
    if (sections = "ERROR")
        return 0

    converted := 0
    failed := 0

    Loop, Parse, sections, `n, `r
    {
        section := Trim(A_LoopField)
        if (SubStr(section, 1, 6) != "Combo.")
            continue

        IniRead, builtInValue, %MacroRegistryFile%, %section%, BuiltIn, 0
        if (builtInValue != 1)
            continue

        IniRead, comboId, %MacroRegistryFile%, %section%, Id,
        IniRead, characterName, %MacroRegistryFile%, %section%, Character,
        IniRead, scriptRelative, %MacroRegistryFile%, %section%, Script,

        comboId := Trim(comboId)
        characterName := Trim(characterName)
        scriptRelative := Trim(scriptRelative)
        sourcePath := MacroCatalog_ResolvePath(scriptRelative)

        if (comboId = "" || characterName = "" || !FileExist(sourcePath)) {
            failed += 1
            continue
        }

        relativeDir := "Macros\User\" . MacroCatalog_Slug(characterName)
            . "\" . MacroCatalog_Slug(comboId)
        absoluteDir := A_ScriptDir . "\" . relativeDir
        targetSource := absoluteDir . "\source.ahk"

        standaloneSource := MacroCatalog_BuildStandaloneSource(sourcePath)
        if (standaloneSource = "") {
            failed += 1
            continue
        }

        FileCreateDir, %absoluteDir%
        if (ErrorLevel) {
            failed += 1
            continue
        }

        tempSource := targetSource . ".tmp." . A_TickCount
        FileDelete, %tempSource%
        FileAppend, %standaloneSource%, %tempSource%, UTF-8-RAW
        if (ErrorLevel) {
            FileDelete, %tempSource%
            failed += 1
            continue
        }

        FileMove, %tempSource%, %targetSource%, 1
        if (ErrorLevel) {
            FileDelete, %tempSource%
            failed += 1
            continue
        }

        relativeSource := relativeDir . "\source.ahk"
        IniWrite, %relativeSource%, %MacroRegistryFile%, %section%, Script
        IniWrite, 0, %MacroRegistryFile%, %section%, BuiltIn

        if (ErrorLevel) {
            failed += 1
            continue
        }

        converted += 1
    }

    return converted
}

MacroCatalog_Export(comboId) {
    global MacroRunning

    if (MacroRunning) {
        WebUI_SendError("Release the trigger before exporting a macro.")
        return false
    }

    comboId := Trim(comboId)
    combo := MacroCatalog_GetCombo(comboId)
    if (!IsObject(combo)) {
        WebUI_SendError("The selected macro no longer exists.")
        return false
    }

    runPath := MacroCatalog_ResolvePath(combo.script)
    SplitPath, runPath, runName, packageDir
    sourcePath := packageDir . "\source.ahk"
    if (!FileExist(sourcePath))
        sourcePath := runPath

    standaloneSource := MacroCatalog_BuildStandaloneSource(sourcePath)
    if (standaloneSource = "") {
        WebUI_SendError("Unable to read the selected macro source.")
        return false
    }

    defaultName := MacroCatalog_Slug(combo.character . " - " . combo.name) . ".ahk"
    defaultPath := A_Desktop . "\" . defaultName
    FileSelectFile, exportPath, S16, %defaultPath%, Export AutoHotkey macro, AutoHotkey scripts (*.ahk)
    if (ErrorLevel || exportPath = "")
        return false

    SplitPath, exportPath,,, exportExtension
    StringLower, exportExtension, exportExtension
    if (exportExtension != "ahk")
        exportPath .= ".ahk"

    header := "; Macro Manager export`r`n"
        . "; UMM Metadata Version: 1`r`n"
        . "; Character: " . combo.character . "`r`n"
        . "; Macro: " . combo.name . "`r`n"
        . "; Tooltip: " . combo.tooltip . "`r`n"
        . "; Tag: " . combo.tag . "`r`n"
        . "; Execution mode: " . combo.executionMode . "`r`n"
        . "; Detected trigger: " . combo.detectedTrigger . "`r`n"
        . "; Exported: " . A_NowUTC . " UTC`r`n`r`n"

    tempPath := exportPath . ".tmp." . A_TickCount
    FileDelete, %tempPath%
    exportText := header . standaloneSource
    FileAppend, %exportText%, %tempPath%, UTF-8-RAW
    if (ErrorLevel) {
        FileDelete, %tempPath%
        WebUI_SendError("Unable to create the exported AHK file.")
        return false
    }

    FileMove, %tempPath%, %exportPath%, 1
    if (ErrorLevel) {
        FileDelete, %tempPath%
        WebUI_SendError("Unable to save the exported AHK file.")
        return false
    }

    WebUI_SendNotice("Exported " . combo.name . ".")
    return true
}

MacroCatalog_ParseHotkeyLine(line, ByRef triggerName, ByRef inlineBody) {
    triggerName := ""
    inlineBody := ""

    trimmedLine := Trim(line)
    if (trimmedLine = "" || SubStr(trimmedLine, 1, 1) = ";")
        return false

    ; Hotstrings begin with ":" and are not selected as the macro entry point.
    if (SubStr(trimmedLine, 1, 1) = ":")
        return false

    ; Covers common AHK v1 keyboard/mouse/joystick hotkeys, modifiers,
    ; wildcard/pass-through prefixes, and custom combinations such as a & b.
    if !RegExMatch(line, "^\s*([~*$<>#!+^&A-Za-z0-9_ \t]+?)::(.*)$", hotkeyMatch)
        return false

    candidate := Trim(hotkeyMatch1)
    if (candidate = "" || InStr(candidate, ":"))
        return false

    triggerName := candidate
    inlineBody := hotkeyMatch2
    return true
}

MacroCatalog_CanonicalHotkey(triggerName) {
    canonical := Trim(triggerName)
    canonical := RegExReplace(canonical, "i)\s+Up$")
    canonical := RegExReplace(canonical, "^[~*$]+")
    canonical := RegExReplace(canonical, "\s+", " ")
    StringLower, canonical, canonical
    return canonical
}

MacroCatalog_SplitSourceLines(sourceText) {
    lines := []
    Loop, Parse, sourceText, `n, `r
        lines.Push(A_LoopField)
    return lines
}

MacroCatalog_FindPrimaryHotkey(lines, ByRef hotkeyIndex, ByRef triggerName, ByRef inlineBody) {

    hotkeyIndex := 0
    triggerName := ""
    inlineBody := ""

    fallbackIndex := 0
    fallbackTrigger := ""
    fallbackBody := ""

    for lineIndex, line in lines {
        parsedTrigger := ""
        parsedBody := ""
        if (!MacroCatalog_ParseHotkeyLine(line, parsedTrigger, parsedBody))
            continue

        if (!fallbackIndex) {
            fallbackIndex := lineIndex
            fallbackTrigger := parsedTrigger
            fallbackBody := parsedBody
        }

        ; Prefer a key-down hotkey. An Up-only hotkey is used only when no
        ; normal hotkey exists in the file.
        if !RegExMatch(parsedTrigger, "i)\s+Up$") {
            hotkeyIndex := lineIndex
            triggerName := parsedTrigger
            inlineBody := parsedBody
            return true
        }
    }

    if (fallbackIndex) {
        hotkeyIndex := fallbackIndex
        triggerName := fallbackTrigger
        inlineBody := fallbackBody
        return true
    }

    return false
}

MacroCatalog_BraceDelta(line) {
    ; This lightweight depth tracker is used only to avoid treating a return
    ; inside a normal function as the end of the auto-execute section.
    codeLine := line
    commentAt := InStr(codeLine, ";")
    if (commentAt)
        codeLine := SubStr(codeLine, 1, commentAt - 1)

    openCount := StrLen(codeLine) - StrLen(StrReplace(codeLine, "{", ""))
    closeCount := StrLen(codeLine) - StrLen(StrReplace(codeLine, "}", ""))
    return openCount - closeCount
}

MacroCatalog_FindAutoExecuteReturn(lines, hotkeyIndex) {
    depth := 0

    for lineIndex, line in lines {
        if (lineIndex >= hotkeyIndex)
            break

        trimmedLine := Trim(line)
        if (depth = 0 && RegExMatch(trimmedLine, "i)^return(?:\s*;.*)?$"))
            return lineIndex

        depth += MacroCatalog_BraceDelta(line)
        if (depth < 0)
            depth := 0
    }

    return 0
}

MacroCatalog_WriteAtomicText(targetPath, text) {
    tempPath := targetPath . ".tmp." . A_TickCount
    FileDelete, %tempPath%
    FileAppend, %text%, %tempPath%, UTF-8-RAW
    if (ErrorLevel) {
        FileDelete, %tempPath%
        return false
    }

    FileMove, %tempPath%, %targetPath%, 1
    if (ErrorLevel) {
        FileDelete, %tempPath%
        return false
    }

    return true
}

MacroCatalog_RewriteImportedStateCalls(line, shimName) {
    if (!InStr(line, "GetKeyState"))
        return line

    ; Preserve comments. Rewrite function-style GetKeyState(...) calls only.
    commentAt := InStr(line, ";")
    if (commentAt) {
        codePart := SubStr(line, 1, commentAt - 1)
        commentPart := SubStr(line, commentAt)
    } else {
        codePart := line
        commentPart := ""
    }

    codePart := RegExReplace(codePart, "i)\bGetKeyState\s*\(", shimName . "(")
    return codePart . commentPart
}

MacroCatalog_CreateImportedRunner(sourcePath, runnerPath, comboId, ByRef executionMode, ByRef detectedTrigger) {

    executionMode := ""
    detectedTrigger := ""

    FileRead, sourceText, %sourcePath%
    if (ErrorLevel)
        return false

    ; The host uses AutoHotkey v1. A v2 script cannot be safely rewritten or
    ; executed by the same interpreter.
    if RegExMatch(sourceText, "im)^\s*#Requires\s+AutoHotkey\s+v2") {
        executionMode := "UnsupportedV2"
        return false
    }

    lines := MacroCatalog_SplitSourceLines(sourceText)
    hotkeyIndex := 0
    hotkeyName := ""
    hotkeyBody := ""

    if (MacroCatalog_FindPrimaryHotkey(lines, hotkeyIndex, hotkeyName, hotkeyBody)) {

        executionMode := "AutoTrigger"
        detectedTrigger := hotkeyName

        suffix := MacroCatalog_Slug(comboId)
        entryLabel := "__MM_ImportedEntry_" . suffix
        entryUpLabel := "__MM_ImportedEntryUp_" . suffix
        invokeLabel := "__MM_InvokeImported_" . suffix
        stateShimName := "__MM_GetKeyState_" . suffix
        canonicalShimName := "__MM_CanonicalKey_" . suffix
        triggerStateVar := "__MM_OriginalTrigger_" . suffix
        canonicalTrigger := MacroCatalog_CanonicalHotkey(hotkeyName)
        autoReturnIndex := MacroCatalog_FindAutoExecuteReturn(lines, hotkeyIndex)

        output := "; Macro Manager generated runner v4`r`n"
            . "; Original trigger detected automatically: "
            . hotkeyName . "`r`n"
            . "#NoEnv`r`n"
            . "#NoTrayIcon`r`n"
            . "#SingleInstance Force`r`n"
            . "#Persistent`r`n"
            . "SetBatchLines, -1`r`n"
            . "SetWorkingDir, %A_ScriptDir%`r`n"
            . triggerStateVar . " := " . Chr(34) . canonicalTrigger
            . Chr(34) . "`r`n`r`n"

        for lineIndex, line in lines {
            ; A common AHK layout has an explicit top-level return before the
            ; first hotkey. Schedule the automatic invocation immediately
            ; before that return so initialization completes first.
            if (autoReturnIndex && lineIndex = autoReturnIndex)
                output .= "SetTimer, " . invokeLabel . ", -1`r`n"

            parsedTrigger := ""
            parsedBody := ""
            isHotkeyLine := MacroCatalog_ParseHotkeyLine(line, parsedTrigger, parsedBody)

            if (lineIndex = hotkeyIndex) {
                ; When there is no explicit auto-execute return, insert one at
                ; the location where the original hotkey previously ended the
                ; auto-execute section.
                if (!autoReturnIndex) {
                    output .= "SetTimer, " . invokeLabel . ", -1`r`n"
                    output .= "return`r`n`r`n"
                }

                output .= entryLabel . ":`r`n"
                if (Trim(hotkeyBody) != "") {
                    rewrittenHotkeyBody := MacroCatalog_RewriteImportedStateCalls(hotkeyBody, stateShimName)
                    output .= rewrittenHotkeyBody . "`r`n"
                    output .= "return`r`n"
                }
                continue
            }

            ; Neutralize a paired "key Up" declaration for the same original
            ; trigger. Trigger release is controlled by the parent engine,
            ; which terminates the child and calls ReleaseAll().
            if (isHotkeyLine && RegExMatch(parsedTrigger, "i)\s+Up$") && MacroCatalog_CanonicalHotkey(parsedTrigger) = canonicalTrigger) {
                output .= entryUpLabel . ":`r`n"
                if (Trim(parsedBody) != "") {
                    rewrittenUpBody := MacroCatalog_RewriteImportedStateCalls(parsedBody, stateShimName)
                    output .= rewrittenUpBody . "`r`n"
                    output .= "return`r`n"
                }
                continue
            }

            rewrittenLine := MacroCatalog_RewriteImportedStateCalls(line, stateShimName)
            output .= rewrittenLine . "`r`n"
        }

        ; The parent owns Trigger state and terminates this child on release.
        ; Report the original script Trigger as held while this child is alive.
        output .= "`r`n" . canonicalShimName . "(keyName) {`r`n"
            . "    keyName := Trim(keyName)`r`n"
            . "    keyName := RegExReplace(keyName, " . Chr(34) . "i)\s+Up$" . Chr(34) . ")`r`n"
            . "    keyName := RegExReplace(keyName, " . Chr(34) . "^[~*$]+" . Chr(34) . ")`r`n"
            . "    keyName := RegExReplace(keyName, " . Chr(34) . "\s+" . Chr(34) . ", " . Chr(34) . " " . Chr(34) . ")`r`n"
            . "    StringLower, keyName, keyName`r`n"
            . "    return keyName`r`n"
            . "}`r`n`r`n"
            . stateShimName . "(keyName, mode := " . Chr(34) . Chr(34) . ") {`r`n"
            . "    global " . triggerStateVar . "`r`n"
            . "    canonicalKey := " . canonicalShimName . "(keyName)`r`n"
            . "    if (canonicalKey = " . triggerStateVar
            . " && (mode = " . Chr(34) . Chr(34)
            . " || mode = " . Chr(34) . "P" . Chr(34) . "))`r`n"
            . "        return true`r`n"
            . "    return GetKeyState(keyName, mode)`r`n"
            . "}`r`n`r`n"
            . invokeLabel . ":`r`n"
            . "Gosub, " . entryLabel . "`r`n"
            . "return`r`n"

        return MacroCatalog_WriteAtomicText(runnerPath, output)
    }

    if RegExMatch(sourceText, "im)^\s*RunMacro\s*\(") {
        executionMode := "RunMacro"
        output := "; Macro Manager generated runner v4`r`n"
            . "#NoEnv`r`n#NoTrayIcon`r`n#SingleInstance Force`r`n"
            . "SetBatchLines, -1`r`n"
            . "SetWorkingDir, %A_ScriptDir%`r`n"
            . "#Include %A_ScriptDir%\source.ahk`r`n"
            . "if IsFunc(" . Chr(34) . "RunMacro" . Chr(34) . ")`r`n"
            . "    Func(" . Chr(34) . "RunMacro" . Chr(34) . ").Call()`r`n"
            . "ExitApp`r`n"
        return MacroCatalog_WriteAtomicText(runnerPath, output)
    }

    ; No explicit hotkey and no RunMacro(): execute the source's original
    ; auto-execute section as-is when Macro Manager's trigger starts it.
    executionMode := "AutoExecute"
    output := "; Macro Manager generated runner v4`r`n"
        . "#NoEnv`r`n#NoTrayIcon`r`n#SingleInstance Force`r`n"
        . "SetBatchLines, -1`r`n"
        . "SetWorkingDir, %A_ScriptDir%`r`n"
        . "#Include %A_ScriptDir%\source.ahk`r`n"
    return MacroCatalog_WriteAtomicText(runnerPath, output)
}

MacroCatalog_UpgradeImportedRunners() {
    global MacroRegistryFile

    IniRead, sections, %MacroRegistryFile%
    if (sections = "ERROR")
        return 0

    upgraded := 0

    Loop, Parse, sections, `n, `r
    {
        section := Trim(A_LoopField)
        if (SubStr(section, 1, 6) != "Combo.")
            continue

        IniRead, comboId, %MacroRegistryFile%, %section%, Id,
        IniRead, scriptRelative, %MacroRegistryFile%, %section%, Script,
        comboId := Trim(comboId)
        scriptRelative := Trim(scriptRelative)

        if (comboId = "" || scriptRelative = "")
            continue

        runnerPath := MacroCatalog_ResolvePath(scriptRelative)
        SplitPath, runnerPath, runnerName, packageDir
        StringLower, runnerNameLower, runnerName

        if (runnerNameLower != "run.ahk")
            continue

        sourcePath := packageDir . "\source.ahk"
        if (!FileExist(sourcePath) || !FileExist(runnerPath))
            continue

        FileRead, runnerText, %runnerPath%
        if (ErrorLevel)
            continue

        ; Keep current runners unchanged. Rebuild generated v3 runners so
        ; they receive original-trigger state compatibility.
        if InStr(runnerText, "Macro Manager generated runner v4")
            continue

        ; Upgrade old include wrappers and v3 AutoTrigger runners.
        ; Custom user-authored run.ahk files remain untouched.
        isGeneratedWrapper := InStr(runnerText, "#Include %A_ScriptDir%\source.ahk") || InStr(runnerText, "Macro Manager generated runner v3")
        if (!isGeneratedWrapper)
            continue

        executionMode := ""
        detectedTrigger := ""
        if (!MacroCatalog_CreateImportedRunner(sourcePath, runnerPath, comboId, executionMode, detectedTrigger))
            continue

        IniWrite, %executionMode%, %MacroRegistryFile%, %section%, ExecutionMode
        IniWrite, %detectedTrigger%, %MacroRegistryFile%, %section%, DetectedTrigger
        upgraded += 1
    }

    return upgraded
}

MacroCatalog_Load() {
    global MacroRegistryFile, MacroCatalog, MacroById, CharacterCatalog, CharacterOrder

    MacroCatalog := []
    MacroById := {}
    CharacterCatalog := {}
    CharacterOrder := []

    IniRead, sections, %MacroRegistryFile%
    if (sections = "ERROR")
        return false

    Loop, Parse, sections, `n, `r
    {
        section := Trim(A_LoopField)
        if (SubStr(section, 1, 6) != "Combo.")
            continue

        IniRead, comboId, %MacroRegistryFile%, %section%, Id,
        IniRead, characterName, %MacroRegistryFile%, %section%, Character,
        IniRead, imageName, %MacroRegistryFile%, %section%, Image,
        IniRead, comboName, %MacroRegistryFile%, %section%, Name,
        IniRead, tooltipName, %MacroRegistryFile%, %section%, Tooltip,
        IniRead, tagName, %MacroRegistryFile%, %section%, Tag,
        IniRead, scriptPath, %MacroRegistryFile%, %section%, Script,
        IniRead, builtInValue, %MacroRegistryFile%, %section%, BuiltIn, 0
        IniRead, orderValue, %MacroRegistryFile%, %section%, Order, 9999
        IniRead, executionMode, %MacroRegistryFile%, %section%, ExecutionMode,
        IniRead, detectedTrigger, %MacroRegistryFile%, %section%, DetectedTrigger,

        comboId := Trim(comboId)
        characterName := Trim(characterName)
        comboName := Trim(comboName)
        scriptPath := Trim(scriptPath)
        if (comboId = "" || characterName = "" || comboName = "" || scriptPath = "")
            continue
        if (MacroById.HasKey(comboId))
            continue

        absoluteScript := MacroCatalog_ResolvePath(scriptPath)
        if (!FileExist(absoluteScript))
            continue

        ; Repair metadata lost by older project-folder recovery. Registry values
        ; remain authoritative; only an empty Tag inherits portable metadata.
        tagName := Trim(tagName)
        if (tagName = "") {
            SplitPath, absoluteScript, , packageDir
            manifestMetadata := MacroCatalog_ReadPackageManifest(packageDir . "\manifest.ini")
            portableTag := Trim(manifestMetadata["tag"])

            if (!MacroCatalog_IsAllowedTag(portableTag) || portableTag = "") {
                sourcePath := packageDir . "\source.ahk"
                exportMetadata := MacroCatalog_ReadExportMetadata(sourcePath)
                portableTag := Trim(exportMetadata["tag"])
            }

            if (portableTag != "" && MacroCatalog_IsAllowedTag(portableTag)) {
                tagName := portableTag
                IniWrite, %tagName%, %MacroRegistryFile%, %section%, Tag
            }
        }

        if (imageName = "")
            imageName := characterName . ".png"

        combo := {id: comboId
            , character: characterName
            , image: imageName
            , name: comboName
            , tooltip: tooltipName
            , tag: tagName
            , script: scriptPath
            , builtIn: (builtInValue = 1)
            , order: orderValue + 0
            , executionMode: executionMode
            , detectedTrigger: detectedTrigger}

        MacroCatalog.Push(combo)
        MacroById[comboId] := combo

        if (!CharacterCatalog.HasKey(characterName)) {
            character := {name: characterName, image: imageName, combos: []}
            CharacterCatalog[characterName] := character
            CharacterOrder.Push(characterName)
        }
        CharacterCatalog[characterName].combos.Push(combo)
    }

    MacroCatalog_SortCombosByOrder()
    return MacroCatalog.Length() > 0
}

MacroCatalog_SortCombosByOrder() {
    global CharacterCatalog, CharacterOrder

    for characterIndex, characterName in CharacterOrder {
        if (!CharacterCatalog.HasKey(characterName))
            continue

        combos := CharacterCatalog[characterName].combos
        comboCount := combos.Length()
        if (comboCount < 2)
            continue

        comboIndex := 2
        while (comboIndex <= comboCount) {
            currentCombo := combos[comboIndex]
            previousIndex := comboIndex - 1

            while (previousIndex >= 1) {
                previousCombo := combos[previousIndex]
                if (previousCombo.order <= currentCombo.order)
                    break

                combos[previousIndex + 1] := previousCombo
                previousIndex -= 1
            }

            combos[previousIndex + 1] := currentCombo
            comboIndex += 1
        }
    }
}

MacroCatalog_ResolvePath(relativeOrAbsolute) {
    if RegExMatch(relativeOrAbsolute, "i)^[A-Z]:\\|^\\\\")
        return relativeOrAbsolute
    return A_ScriptDir . "\" . relativeOrAbsolute
}

MacroCatalog_GetCombo(comboId) {
    global MacroById
    if (MacroById.HasKey(comboId))
        return MacroById[comboId]
    return ""
}

MacroCatalog_CharacterExists(characterName) {
    global CharacterCatalog
    return CharacterCatalog.HasKey(characterName)
}

MacroCatalog_IsSafeField(value, maximumLength := 80) {
    value := Trim(value)
    if (value = "" || StrLen(value) > maximumLength)
        return false
    if RegExMatch(value, "[\r\n\t=|]")
        return false
    return true
}

MacroCatalog_IsAllowedTag(tagName) {
    return (tagName = "" || tagName = "60 FPS" || tagName = "120 FPS"
        || tagName = "240 FPS" || tagName = "TESTING")
}

MacroCatalog_ComboNameExists(characterName, comboName) {
    global CharacterCatalog
    if (!CharacterCatalog.HasKey(characterName))
        return false
    for index, combo in CharacterCatalog[characterName].combos {
        if (combo.name = comboName)
            return true
    }
    return false
}

MacroCatalog_Slug(value) {
    slug := RegExReplace(value, "[^A-Za-z0-9_-]+", "_")
    slug := Trim(slug, "_")
    if (slug = "")
        slug := "macro"
    return slug
}


MacroCatalog_IdExistsInRegistry(comboId) {
    global MacroRegistryFile

    section := "Combo." . comboId
    missingValue := "__MM_MISSING_ID__"
    IniRead, existingId, %MacroRegistryFile%, %section%, Id, %missingValue%
    return (existingId != missingValue)
}

MacroCatalog_SelectStableIdentity(characterName, comboName, characterDir, currentPackageDir, knownIds, ByRef comboId, ByRef packageName) {

    packageBase := MacroCatalog_Slug(comboName)
    idBase := MacroCatalog_Slug(characterName . "_" . comboName)
    currentKey := MacroCatalog_NormalizePackagePath(currentPackageDir)
    suffix := 1

    Loop, 1000
    {
        suffixText := (suffix = 1) ? "" : "_" . suffix
        candidatePackage := packageBase . suffixText
        candidateId := idBase . suffixText
        candidateDir := characterDir . "\" . candidatePackage
        candidateKey := MacroCatalog_NormalizePackagePath(candidateDir)

        idTaken := (IsObject(knownIds) && knownIds.HasKey(candidateId)) || MacroCatalog_IdExistsInRegistry(candidateId)
        directoryTaken := InStr(FileExist(candidateDir), "D") && candidateKey != currentKey

        if (!idTaken && !directoryTaken) {
            comboId := candidateId
            packageName := candidatePackage
            return true
        }

        suffix += 1
    }

    return false
}

MacroCatalog_GetNextOrder() {
    global MacroRegistryFile

    maximumOrder := 0
    IniRead, sections, %MacroRegistryFile%
    if (sections = "ERROR")
        return 10

    Loop, Parse, sections, `n, `r
    {
        section := Trim(A_LoopField)
        if (SubStr(section, 1, 6) != "Combo.")
            continue

        IniRead, orderValue, %MacroRegistryFile%, %section%, Order, 0
        orderValue += 0
        if (orderValue > maximumOrder)
            maximumOrder := orderValue
    }

    return maximumOrder + 10
}

MacroCatalog_Import(characterName, comboName, tooltipName, tagName) {
    global MacroRegistryFile, MacroRootDir, MacroById, CurrentCharacter, CurrentMacro, MacroRunning

    if (MacroRunning) {
        WebUI_SendError("Release the trigger before importing a macro.")
        return false
    }

    characterName := Trim(characterName)
    comboName := Trim(comboName)
    tooltipName := Trim(tooltipName)
    tagName := Trim(tagName)

    if (!MacroCatalog_IsSafeField(characterName, 50)) {
        WebUI_SendError("Choose a valid character name.")
        return false
    }
    if (!MacroCatalog_IsSafeField(comboName, 60)) {
        WebUI_SendError("Combo name is required and cannot contain tabs, line breaks, =, or |.")
        return false
    }
    if (tooltipName != "" && !MacroCatalog_IsSafeField(tooltipName, 80)) {
        WebUI_SendError("Tooltip cannot contain tabs, line breaks, =, or |.")
        return false
    }
    if (!MacroCatalog_IsAllowedTag(tagName)) {
        WebUI_SendError("Invalid combo tag.")
        return false
    }

    if (!MacroCatalog_CharacterExists(characterName)) {
        WebUI_SendError("The selected character is no longer available.")
        return false
    }

    if (MacroCatalog_ComboNameExists(characterName, comboName)) {
        WebUI_SendError("A combo with that name already exists for this character.")
        return false
    }

    FileSelectFile, sourcePath, 3,, Import AutoHotkey macro, AutoHotkey scripts (*.ahk)
    if (ErrorLevel || sourcePath = "")
        return false

    MsgBox, 52, Import AutoHotkey macro, AutoHotkey files can run programs and access your files.`n`nImport this file only if you trust its source.`n`n%sourcePath%
    IfMsgBox, No
        return false

    ; A Macro Manager export carries portable metadata in comment headers.
    ; Explicit values chosen in the form win; empty fields inherit metadata.
    exportMetadata := MacroCatalog_ReadExportMetadata(sourcePath)

    if (tooltipName = "") {
        exportedTooltip := Trim(exportMetadata["tooltip"])
        if (exportedTooltip != "" && MacroCatalog_IsSafeField(exportedTooltip, 80))
            tooltipName := exportedTooltip
    }

    if (tagName = "") {
        exportedTag := Trim(exportMetadata["tag"])
        if (MacroCatalog_IsAllowedTag(exportedTag))
            tagName := exportedTag
    }

    characterFolder := MacroCatalog_Slug(characterName)
    characterDir := A_ScriptDir . "\Macros\User\" . characterFolder
    FileCreateDir, %characterDir%
    if (ErrorLevel) {
        WebUI_SendError("Unable to create the character macro folder.")
        return false
    }

    comboId := ""
    packageName := ""
    if (!MacroCatalog_SelectStableIdentity(characterName, comboName, characterDir, "", MacroById, comboId, packageName)) {
        WebUI_SendError("Unable to create a stable macro ID.")
        return false
    }

    relativeDir := "Macros\User\" . characterFolder . "\" . packageName
    absoluteDir := A_ScriptDir . "\" . relativeDir
    FileCreateDir, %absoluteDir%
    if (ErrorLevel) {
        WebUI_SendError("Unable to create the imported macro folder.")
        return false
    }

    copiedSource := absoluteDir . "\source.ahk"
    FileCopy, %sourcePath%, %copiedSource%, 1
    if (ErrorLevel) {
        FileRemoveDir, %absoluteDir%, 1
        WebUI_SendError("Unable to copy the selected AHK file.")
        return false
    }

    wrapperPath := absoluteDir . "\run.ahk"
    executionMode := ""
    detectedTrigger := ""

    if (!MacroCatalog_CreateImportedRunner(copiedSource, wrapperPath, comboId, executionMode, detectedTrigger)) {
        FileRemoveDir, %absoluteDir%, 1
        if (executionMode = "UnsupportedV2")
            WebUI_SendError("AutoHotkey v2 files are not supported by this AutoHotkey v1 engine.")
        else
            WebUI_SendError("Unable to analyze and prepare the imported AHK file.")
        return false
    }

    section := "Combo." . comboId
    relativeScript := relativeDir . "\run.ahk"
    IniWrite, %comboId%, %MacroRegistryFile%, %section%, Id
    IniWrite, %characterName%, %MacroRegistryFile%, %section%, Character
    IniWrite, % characterName . ".png", %MacroRegistryFile%, %section%, Image
    IniWrite, %comboName%, %MacroRegistryFile%, %section%, Name
    IniWrite, %tooltipName%, %MacroRegistryFile%, %section%, Tooltip
    IniWrite, %tagName%, %MacroRegistryFile%, %section%, Tag
    IniWrite, %relativeScript%, %MacroRegistryFile%, %section%, Script
    IniWrite, 0, %MacroRegistryFile%, %section%, BuiltIn
    nextOrder := MacroCatalog_GetNextOrder()
    IniWrite, %nextOrder%, %MacroRegistryFile%, %section%, Order
    IniWrite, %executionMode%, %MacroRegistryFile%, %section%, ExecutionMode
    IniWrite, %detectedTrigger%, %MacroRegistryFile%, %section%, DetectedTrigger

    if (ErrorLevel) {
        IniDelete, %MacroRegistryFile%, %section%
        FileRemoveDir, %absoluteDir%, 1
        WebUI_SendError("Unable to register the imported macro.")
        return false
    }

    ; Keep imported folders portable. A manifest makes the registration
    ; explicit and allows safe recovery in another project tree.
    manifestPath := absoluteDir . "\manifest.ini"
    if (!MacroCatalog_WritePackageManifest(manifestPath, comboId, characterName, characterName . ".png", comboName, tooltipName, tagName)) {
        IniDelete, %MacroRegistryFile%, %section%
        FileRemoveDir, %absoluteDir%, 1
        WebUI_SendError("Unable to write the imported macro manifest.")
        return false
    }

    if (!MacroCatalog_Load()) {
        WebUI_SendError("The macro was copied, but the catalog could not be reloaded.")
        return false
    }

    SetCharacter(characterName)
    SetMode(comboId)
    SetupTrayMenu()
    UpdateTrayText()
    WebUI_SendState()

    importNotice := "Imported " . comboName . " for " . characterName . "."
    if (executionMode = "AutoTrigger")
        importNotice .= " Detected trigger " . detectedTrigger
            . " and its GetKeyState checks are now controlled by Macro Manager."
    else if (executionMode = "AutoExecute")
        importNotice .= " Its auto-execute section will run from Macro Manager's trigger."
    else
        importNotice .= " RunMacro() will run from Macro Manager's trigger."

    WebUI_SendNotice(importNotice)
    return true
}

MacroCatalog_Reorder(characterName, orderedComboIds) {
    global MacroRegistryFile, CharacterCatalog, CurrentCharacter, CurrentMacro

    characterName := Trim(characterName)
    if (characterName = "" || !CharacterCatalog.HasKey(characterName)) {
        WebUI_SendError("The selected character is no longer available.")
        return false
    }

    characterCombos := CharacterCatalog[characterName].combos
    expectedCount := characterCombos.Length()
    if (expectedCount < 2)
        return true

    orderedIds := []
    seenIds := {}

    Loop, Parse, orderedComboIds, |
    {
        comboId := Trim(A_LoopField)
        if (comboId = "" || seenIds.HasKey(comboId)) {
            WebUI_SendError("The macro order request is invalid.")
            return false
        }

        combo := MacroCatalog_GetCombo(comboId)
        if (!IsObject(combo) || combo.character != characterName) {
            WebUI_SendError("The macro order does not match the selected character.")
            return false
        }

        seenIds[comboId] := true
        orderedIds.Push(comboId)
    }

    if (orderedIds.Length() != expectedCount) {
        WebUI_SendError("The macro order is incomplete.")
        return false
    }

    for comboIndex, combo in characterCombos {
        if (!seenIds.HasKey(combo.id)) {
            WebUI_SendError("The macro order is incomplete.")
            return false
        }
    }

    oldOrders := {}
    for comboIndex, combo in characterCombos
        oldOrders[combo.id] := combo.order

    writeFailed := false
    for orderIndex, comboId in orderedIds {
        section := "Combo." . comboId
        newOrder := orderIndex * 10
        IniWrite, %newOrder%, %MacroRegistryFile%, %section%, Order
        if (ErrorLevel) {
            writeFailed := true
            break
        }
    }

    if (writeFailed) {
        for comboId, oldOrder in oldOrders {
            section := "Combo." . comboId
            IniWrite, %oldOrder%, %MacroRegistryFile%, %section%, Order
        }

        MacroCatalog_Load()
        WebUI_SendError("Unable to save the new macro order.")
        return false
    }

    if (!MacroCatalog_Load()) {
        for comboId, oldOrder in oldOrders {
            section := "Combo." . comboId
            IniWrite, %oldOrder%, %MacroRegistryFile%, %section%, Order
        }

        MacroCatalog_Load()
        WebUI_SendError("The catalog could not be reloaded after reordering.")
        return false
    }

    if (!IsValidComboForCharacter(CurrentCharacter, CurrentMacro)) {
        CurrentCharacter := characterName
        CurrentMacro := GetDefaultComboForCharacter(characterName)
        SaveRuntimeSettings()
    }

    SetupTrayMenu()
    UpdateTrayText()
    WebUI_SendState()
    return true
}

MacroCatalog_WriteComboSection(combo) {
    global MacroRegistryFile

    if (!IsObject(combo))
        return false

    section := "Combo." . combo.id
    IniWrite, % combo.id, %MacroRegistryFile%, %section%, Id
    IniWrite, % combo.character, %MacroRegistryFile%, %section%, Character
    IniWrite, % combo.image, %MacroRegistryFile%, %section%, Image
    IniWrite, % combo.name, %MacroRegistryFile%, %section%, Name
    IniWrite, % combo.tooltip, %MacroRegistryFile%, %section%, Tooltip
    IniWrite, % combo.tag, %MacroRegistryFile%, %section%, Tag
    IniWrite, % combo.script, %MacroRegistryFile%, %section%, Script
    IniWrite, % (combo.builtIn ? 1 : 0), %MacroRegistryFile%, %section%, BuiltIn
    IniWrite, % combo.order, %MacroRegistryFile%, %section%, Order
    IniWrite, % combo.executionMode, %MacroRegistryFile%, %section%, ExecutionMode
    IniWrite, % combo.detectedTrigger, %MacroRegistryFile%, %section%, DetectedTrigger
    return !ErrorLevel
}

MacroCatalog_IsPathInsideUserRoot(path) {
    userRoot := A_ScriptDir . "\Macros\User"
    path := RTrim(path, "\/")
    userRoot := RTrim(userRoot, "\/")

    if (StrLen(path) <= StrLen(userRoot))
        return false

    expectedPrefix := userRoot . "\"
    return InStr(path, expectedPrefix, false) = 1
}

MacroCatalog_DeleteImported(comboId) {
    global MacroRegistryFile, MacroRootDir, CurrentCharacter, CurrentMacro
    global MacroRunning, StopRequested, ConfigFile, ActiveMacroPid
    global MacroCatalog, CharacterCatalog, CharacterOrder

    comboId := Trim(comboId)
    combo := MacroCatalog_GetCombo(comboId)

    if (!IsObject(combo)) {
        WebUI_SendError("The selected macro no longer exists.")
        return false
    }

    ; A completely empty catalog would remove the character context required
    ; by Add macro. Keep one macro until another has been imported.
    if (MacroCatalog.Length() <= 1) {
        WebUI_SendError("Import another macro before deleting the last remaining macro.")
        return false
    }

    if (combo.builtIn) {
        WebUI_SendError("This legacy macro was not migrated. Restart Macro Manager and try again.")
        return false
    }

    scriptPath := MacroCatalog_ResolvePath(combo.script)
    SplitPath, scriptPath, scriptFileName, macroFolder
    macroFolder := RTrim(macroFolder, "\/")

    if (!MacroCatalog_IsPathInsideUserRoot(macroFolder)) {
        WebUI_SendError("The macro folder is outside Macros\User and was not deleted.")
        return false
    }

    if (MacroRunning) {
        StopRequested := true
        StopActiveMacroProcess()
        ReleaseAll()
    }

    Loop, 20 {
        if (!ActiveMacroPid)
            break
        Process, Exist, %ActiveMacroPid%
        if (ErrorLevel != ActiveMacroPid)
            break
        Sleep, 25
    }

    trashRoot := MacroRootDir . "\User\.trash"
    FileCreateDir, %trashRoot%
    trashFolder := trashRoot . "\" . MacroCatalog_Slug(combo.id)
        . "_" . A_NowUTC . "_" . A_TickCount

    FileMoveDir, %macroFolder%, %trashFolder%, R
    if (ErrorLevel) {
        WebUI_SendError("Unable to remove the macro folder. Close any program using its files and try again.")
        return false
    }

    section := "Combo." . combo.id
    IniDelete, %MacroRegistryFile%, %section%
    if (ErrorLevel) {
        FileMoveDir, %trashFolder%, %macroFolder%, R
        WebUI_SendError("Unable to remove the macro from the registry.")
        return false
    }

    if (!MacroCatalog_Load()) {
        MacroCatalog_WriteComboSection(combo)
        FileMoveDir, %trashFolder%, %macroFolder%, R
        MacroCatalog_Load()
        WebUI_SendError("The catalog could not be reloaded. Nothing was removed.")
        return false
    }

    FileRemoveDir, %trashFolder%, 1
    if (ErrorLevel) {
        MacroCatalog_WriteComboSection(combo)
        FileMoveDir, %trashFolder%, %macroFolder%, R
        MacroCatalog_Load()
        SetupTrayMenu()
        UpdateTrayText()
        WebUI_SendState()
        WebUI_SendError("Unable to delete all macro files. Nothing was removed.")
        return false
    }

    SplitPath, macroFolder,, characterFolder
    FileRemoveDir, %characterFolder%
    FileRemoveDir, %trashRoot%

    deletedWasSelected := (CurrentMacro = combo.id)
    deletedCharacter := combo.character

    IniRead, savedCombo, %ConfigFile%, LastCombo, %deletedCharacter%,
    replacementForDeletedCharacter := GetDefaultComboForCharacter(deletedCharacter)

    if (replacementForDeletedCharacter != "")
        IniWrite, %replacementForDeletedCharacter%, %ConfigFile%, LastCombo, %deletedCharacter%
    else
        IniDelete, %ConfigFile%, LastCombo, %deletedCharacter%

    if (deletedWasSelected || !IsValidComboForCharacter(CurrentCharacter, CurrentMacro)) {
        if (CharacterCatalog.HasKey(deletedCharacter)) {
            CurrentCharacter := deletedCharacter
        } else {
            CurrentCharacter := CharacterOrder.Length() ? CharacterOrder[1] : ""
        }
        CurrentMacro := GetDefaultComboForCharacter(CurrentCharacter)
    }

    SaveRuntimeSettings()
    SetupTrayMenu()
    UpdateTrayText()
    WebUI_SendState()
    WebUI_SendNotice("Deleted " . combo.name . " from " . deletedCharacter . ".")
    return true
}

MacroCatalog_JsonEscape(value) {
    value := StrReplace(value, Chr(92), Chr(92) . Chr(92))
    value := StrReplace(value, Chr(34), Chr(92) . Chr(34))
    value := StrReplace(value, "`r", " ")
    value := StrReplace(value, "`n", " ")
    value := StrReplace(value, "`t", " ")
    return value
}

MacroCatalog_ToJson() {
    global CharacterCatalog, CharacterOrder
    q := Chr(34)
    json := "{"
    firstCharacter := true

    for characterIndex, characterName in CharacterOrder {
        if (!CharacterCatalog.HasKey(characterName))
            continue
        character := CharacterCatalog[characterName]
        if (!firstCharacter)
            json .= ","
        firstCharacter := false

        json .= q . MacroCatalog_JsonEscape(characterName) . q . ":{"
        json .= q . "image" . q . ":" . q . MacroCatalog_JsonEscape(character.image) . q . ","
        json .= q . "combos" . q . ":["

        firstCombo := true
        for comboIndex, combo in character.combos {
            if (!firstCombo)
                json .= ","
            firstCombo := false
            json .= "{" . q . "value" . q . ":" . q . MacroCatalog_JsonEscape(combo.id) . q
            json .= "," . q . "label" . q . ":" . q . MacroCatalog_JsonEscape(combo.name) . q
            json .= "," . q . "tooltip" . q . ":" . q . MacroCatalog_JsonEscape(combo.tooltip) . q
            json .= "," . q . "builtIn" . q . ":" . (combo.builtIn ? "true" : "false")
            if (combo.tag = "TESTING")
                json .= "," . q . "testing" . q . ":true"
            else if InStr(combo.tag, "FPS")
                json .= "," . q . "fps" . q . ":" . q . MacroCatalog_JsonEscape(combo.tag) . q
            json .= "}"
        }
        json .= "]}"
    }
    json .= "}"
    return json
}

RunSelectedMacroProcess() {
    global CurrentMacro, ActiveMacroPid, StopRequested, TriggerKey

    combo := MacroCatalog_GetCombo(CurrentMacro)
    if (!IsObject(combo)) {
        WebUI_SendError("The selected macro is missing from the catalog.")
        return false
    }

    scriptPath := MacroCatalog_ResolvePath(combo.script)
    if (!FileExist(scriptPath)) {
        WebUI_SendError("Macro file not found: " . scriptPath)
        return false
    }

    StopActiveMacroProcess()
    SplitPath, scriptPath, scriptName, scriptDir
    command := Chr(34) . A_AhkPath . Chr(34) . " " . Chr(34) . scriptPath . Chr(34)
        . " " . Chr(34) . TriggerKey . Chr(34)
    Run, %command%, %scriptDir%, UseErrorLevel, childPid
    if (ErrorLevel || !childPid) {
        WebUI_SendError("Unable to start the selected macro process.")
        return false
    }

    ActiveMacroPid := childPid
    Loop {
        Process, Exist, %childPid%
        if (ErrorLevel != childPid)
            break

        if (StopRequested || !GetKeyState(TriggerKey, "P")) {
            Process, Close, %childPid%
            break
        }
        Sleep, 10
    }

    ActiveMacroPid := 0
    return true
}

StopActiveMacroProcess() {
    global ActiveMacroPid
    if (!ActiveMacroPid)
        return

    processId := ActiveMacroPid
    ActiveMacroPid := 0
    Process, Exist, %processId%
    if (ErrorLevel = processId)
        Process, Close, %processId%
}


ResolveProjectPaths() {
    global AssetsDir, IconDir, PortraitDir, SoundDir

    candidates := []
    candidates.Push(A_ScriptDir . "\assets")
    candidates.Push(A_ScriptDir . "\Assets")
    candidates.Push(A_ScriptDir . "\assists")
    candidates.Push(A_ScriptDir . "\..\assets")
    candidates.Push(A_ScriptDir . "\..\Assets")
    candidates.Push(A_ScriptDir . "\..\assists")

    AssetsDir := ""
    for index, candidate in candidates {
        if !InStr(FileExist(candidate), "D")
            continue

        hasIcons := InStr(FileExist(candidate . "\icons"), "D")
        hasPortraits := InStr(FileExist(candidate . "\portraits"), "D")
        hasSounds := InStr(FileExist(candidate . "\sounds"), "D")
        if (hasIcons || hasPortraits || hasSounds) {
            AssetsDir := candidate
            break
        }
    }

    if (AssetsDir = "")
        AssetsDir := A_ScriptDir . "\Assets"

    IconDir := AssetsDir . "\icons"
    PortraitDir := AssetsDir . "\portraits"
    SoundDir := AssetsDir . "\sounds"

    if !InStr(FileExist(AssetsDir), "D")
        FileCreateDir, %AssetsDir%
    if !InStr(FileExist(IconDir), "D")
        FileCreateDir, %IconDir%
    if !InStr(FileExist(PortraitDir), "D")
        FileCreateDir, %PortraitDir%
    if !InStr(FileExist(SoundDir), "D")
        FileCreateDir, %SoundDir%
}


LoadRuntimeSettings() {
    global ConfigFile, CurrentCharacter, CurrentMacro
    global MacroEnabled, AppMode, SkipStopMode, SoundsEnabled, AutoLaunchExePath, AutoLaunchEnabled
    global CharacterOrder

    defaultCharacter := CharacterOrder.Length() ? CharacterOrder[1] : ""
    IniRead, SavedCharacter, %ConfigFile%, State, Character, %defaultCharacter%
    IniRead, SavedCombo, %ConfigFile%, State, Combo,
    IniRead, SavedEnabled, %ConfigFile%, State, Enabled, 1
    IniRead, SavedAppMode, %ConfigFile%, State, AppMode, CharacterCombos
    IniRead, SavedSkipStopMode, %ConfigFile%, Settings, SkipStopMode, Release
    IniRead, SavedSounds, %ConfigFile%, Settings, SoundsEnabled, 1
    IniRead, SavedAutoLaunchExe, %ConfigFile%, Settings, AutoLaunchExe,
    IniRead, SavedAutoLaunchEnabled, %ConfigFile%, Settings, AutoLaunchEnabled, 1

    if (!MacroCatalog_CharacterExists(SavedCharacter))
        SavedCharacter := defaultCharacter

    if (SavedCombo = "Off") {
        SavedCombo := ""
        SavedEnabled := 0
    }

    if (!IsValidComboForCharacter(SavedCharacter, SavedCombo)) {
        IniRead, SavedLastCombo, %ConfigFile%, LastCombo, %SavedCharacter%,
        if (IsValidComboForCharacter(SavedCharacter, SavedLastCombo))
            SavedCombo := SavedLastCombo
        else
            SavedCombo := GetDefaultComboForCharacter(SavedCharacter)
    }

    if (SavedAppMode != "CharacterCombos" && SavedAppMode != "SkipDialogs")
        SavedAppMode := "CharacterCombos"
    if (SavedSkipStopMode != "Release" && SavedSkipStopMode != "AnyKey")
        SavedSkipStopMode := "Release"

    CurrentCharacter := SavedCharacter
    CurrentMacro := SavedCombo
    AppMode := SavedAppMode
    SkipStopMode := SavedSkipStopMode
    MacroEnabled := (SavedEnabled = 1 || SavedEnabled = "true" || SavedEnabled = "ON")
    SoundsEnabled := (SavedSounds = 1 || SavedSounds = "true" || SavedSounds = "ON")
    AutoLaunchExePath := (SavedAutoLaunchExe = "ERROR") ? "" : SavedAutoLaunchExe
    AutoLaunchEnabled := (SavedAutoLaunchEnabled = 1 || SavedAutoLaunchEnabled = "true" || SavedAutoLaunchEnabled = "ON")

}


SaveRuntimeSettings() {
    global ConfigFile, CurrentCharacter, CurrentMacro
    global MacroEnabled, AppMode, SkipStopMode, SoundsEnabled, AutoLaunchExePath, AutoLaunchEnabled

    enabledValue := MacroEnabled ? 1 : 0
    soundsValue := SoundsEnabled ? 1 : 0

    IniWrite, %CurrentCharacter%, %ConfigFile%, State, Character
    IniWrite, %CurrentMacro%, %ConfigFile%, State, Combo
    if (CurrentCharacter != "" && CurrentMacro != "")
        IniWrite, %CurrentMacro%, %ConfigFile%, LastCombo, %CurrentCharacter%
    IniWrite, %enabledValue%, %ConfigFile%, State, Enabled
    IniWrite, %AppMode%, %ConfigFile%, State, AppMode
    IniWrite, %SkipStopMode%, %ConfigFile%, Settings, SkipStopMode
    IniWrite, %soundsValue%, %ConfigFile%, Settings, SoundsEnabled
    IniWrite, %AutoLaunchExePath%, %ConfigFile%, Settings, AutoLaunchExe
    IniWrite, % (AutoLaunchEnabled ? 1 : 0), %ConfigFile%, Settings, AutoLaunchEnabled
}



RunAutoLaunchApp(reportErrors := false) {
    global AutoLaunchExePath

    if (AutoLaunchExePath = "" || !FileExist(AutoLaunchExePath)) {
        if (!reportErrors)
            return false

        MsgBox, 64, Macro Manager, The game path is not configured.`nSelect the game executable now.
        return BrowseForAutoLaunchExe(true)
    }

    SplitPath, AutoLaunchExePath, exeName, exeDir, exeExtension
    StringLower, exeExtension, exeExtension
    if (exeExtension != "exe") {
        if (!reportErrors)
            return false

        MsgBox, 48, Macro Manager, The saved game path is not a valid executable.`nSelect the game executable again.
        return BrowseForAutoLaunchExe(true)
    }

    if (exeName != "") {
        Process, Exist, %exeName%
        if (ErrorLevel) {
            if (reportErrors)
                WebUI_SendError("The selected game is already running.")
            return false
        }
    }

    runTarget := """" . AutoLaunchExePath . """"
    Run, %runTarget%, %exeDir%, UseErrorLevel
    if (ErrorLevel) {
        if (reportErrors)
            WebUI_SendError("Unable to start the selected game.")
        return false
    }

    return true
}

BrowseForAutoLaunchExe(startAfterSelect := false) {
    global AutoLaunchExePath, ConfigFile

    FileSelectFile, selectedExe, 3,, Select the game executable, Executable (*.exe)
    if (ErrorLevel || selectedExe = "")
        return false

    SplitPath, selectedExe, selectedName, selectedDir, selectedExtension
    StringLower, selectedExtension, selectedExtension
    if (!FileExist(selectedExe) || selectedExtension != "exe") {
        WebUI_SendError("Select a valid executable file.")
        return false
    }

    AutoLaunchExePath := selectedExe
    IniWrite, %AutoLaunchExePath%, %ConfigFile%, Settings, AutoLaunchExe
    WebUI_SendState()

    if (startAfterSelect)
        return RunAutoLaunchApp(true)

    return true
}


ClearAutoLaunchExePath() {
    global AutoLaunchExePath, ConfigFile

    AutoLaunchExePath := ""
    IniWrite, %AutoLaunchExePath%, %ConfigFile%, Settings, AutoLaunchExe
    WebUI_SendState()
    ShowModeTooltip("Game executable cleared", 1100)
}

GetShortPathLabel(path) {
    if (path = "")
        return "None"

    SplitPath, path, fileName
    if (fileName = "")
        return path

    return fileName
}

IsValidComboForCharacter(characterName, comboName) {
    combo := MacroCatalog_GetCombo(comboName)
    return IsObject(combo) && combo.character = characterName
}


GetDefaultComboForCharacter(characterName) {
    global CharacterCatalog
    if (!CharacterCatalog.HasKey(characterName))
        return ""
    combos := CharacterCatalog[characterName].combos
    if (combos.Length() < 1)
        return ""
    return combos[1].id
}


GetNextCombo(characterName, comboName) {
    global CharacterCatalog
    if (!CharacterCatalog.HasKey(characterName))
        return ""
    combos := CharacterCatalog[characterName].combos
    count := combos.Length()
    if (count < 1)
        return ""
    for index, combo in combos {
        if (combo.id = comboName) {
            nextIndex := index >= count ? 1 : index + 1
            return combos[nextIndex].id
        }
    }
    return combos[1].id
}

GetNextCharacter(characterName) {
    global CharacterOrder
    count := CharacterOrder.Length()
    if (count < 1)
        return ""
    for index, currentName in CharacterOrder {
        if (currentName = characterName) {
            nextIndex := index >= count ? 1 : index + 1
            return CharacterOrder[nextIndex]
        }
    }
    return CharacterOrder[1]
}


GetComboDisplay(comboName) {
    combo := MacroCatalog_GetCombo(comboName)
    if (!IsObject(combo))
        return comboName
    return combo.name
}


GetComboMenuLabel(comboName) {
    combo := MacroCatalog_GetCombo(comboName)
    if (!IsObject(combo))
        return comboName
    label := combo.name
    if (combo.tag != "")
        label .= " (" . combo.tag . ")"
    return label
}

MacroCatalog_FindComboIdByMenuLabel(characterName, menuLabel) {
    global CharacterCatalog
    if (!CharacterCatalog.HasKey(characterName))
        return ""
    for index, combo in CharacterCatalog[characterName].combos {
        if (GetComboMenuLabel(combo.id) = menuLabel)
            return combo.id
    }
    return ""
}


PlayFeedbackSound(name, boost := false) {
    global SoundDir, SoundsEnabled

    if (!SoundsEnabled)
        return false

    wavPath := SoundDir . "\" . name . ".wav"
    mp3Path := SoundDir . "\" . name . ".mp3"

    if FileExist(wavPath) {
        flags := 0x00020003  ; SND_ASYNC | SND_NODEFAULT | SND_FILENAME
        if (A_IsUnicode)
            return !!DllCall("winmm\PlaySoundW", "WStr", wavPath, "Ptr", 0, "UInt", flags)
        return !!DllCall("winmm\PlaySoundA", "AStr", wavPath, "Ptr", 0, "UInt", flags)
    }

    if FileExist(mp3Path) {
        SoundPlay, %mp3Path%
        return !ErrorLevel
    }

    return false
}



GetSkipIconPath() {
    global IconDir

    skipIcon := IconDir . "\Skip.ico"
    if FileExist(skipIcon)
        return skipIcon

    lowerSkipIcon := IconDir . "\skip.ico"
    if FileExist(lowerSkipIcon)
        return lowerSkipIcon

    return IconDir . "\default.ico"
}


GetCharacterAssetPath(baseDir, characterName, extension) {
    candidates := []
    candidates.Push(characterName)

    compactName := StrReplace(characterName, " ", "")
    if (compactName != "" && compactName != characterName)
        candidates.Push(compactName)

    slugName := MacroCatalog_Slug(characterName)
    if (slugName != "" && slugName != characterName && slugName != compactName)
        candidates.Push(slugName)

    for index, candidateName in candidates {
        candidatePath := baseDir . "\" . candidateName . "." . extension
        if FileExist(candidatePath)
            return candidatePath
    }

    return ""
}


GetCharacterPortraitPath(characterName := "") {
    global PortraitDir, CurrentCharacter

    if (characterName = "")
        characterName := CurrentCharacter

    portraitPath := GetCharacterAssetPath(PortraitDir, characterName, "png")
    if (portraitPath != "")
        return portraitPath

    ; Keep the UI usable when no portrait is supplied.
    return GetCharacterIconPath(characterName)
}


IsIconImagePath(imagePath) {
    SplitPath, imagePath, , , extension
    StringLower, extension, extension
    return (extension = "ico")
}


GetCharacterIconPath(characterName := "") {
    global IconDir, CurrentCharacter

    if (characterName = "")
        characterName := CurrentCharacter

    iconPath := GetCharacterAssetPath(IconDir, characterName, "ico")
    if (iconPath = "")
        iconPath := IconDir . "\default.ico"

    return iconPath
}


SetTrayIconByCharacter() {
    global AppMode

    if (AppMode = "SkipDialogs")
        iconPath := GetSkipIconPath()
    else
        iconPath := GetCharacterIconPath()

    if FileExist(iconPath) {
        Menu, Tray, Icon, %iconPath%
    } else {
        Menu, Tray, Icon
    }
}



LoadHotkeySettings() {
    global ConfigFile
    IniRead, SavedTrigger, %ConfigFile%, Settings, TriggerKey, XButton2
    IniRead, SavedComboToggle, %ConfigFile%, Settings, ComboToggleKey, F10
    IniRead, SavedCharacterToggle, %ConfigFile%, Settings, CharacterToggleKey, F9
    IniRead, SavedModeToggle, %ConfigFile%, Settings, ModeToggleKey, F8

    if (SavedTrigger = "" || SavedTrigger = "ERROR")
        SavedTrigger := "XButton2"
    if (SavedComboToggle = "" || SavedComboToggle = "ERROR")
        SavedComboToggle := "F10"
    if (SavedCharacterToggle = "" || SavedCharacterToggle = "ERROR")
        SavedCharacterToggle := "F9"
    if (SavedModeToggle = "" || SavedModeToggle = "ERROR")
        SavedModeToggle := "F8"

    if (!SetTriggerHotkey(SavedTrigger, false))
        SetTriggerHotkey("XButton2", false)
    if (!SetComboToggleHotkey(SavedComboToggle, false))
        SetComboToggleHotkey("F10", false)
    if (!SetCharacterToggleHotkey(SavedCharacterToggle, false))
        SetCharacterToggleHotkey("F9", false)
    if (!SetModeToggleHotkey(SavedModeToggle, false))
        SetModeToggleHotkey("F8", false)
}

SetupTrayMenu() {
    global CharacterToggleKey, ModeToggleKey, MacroEnabled, CurrentCharacter, AppMode
    global CharacterCatalog, CharacterOrder

    Menu, Tray, NoStandard
    Menu, Tray, DeleteAll

    Menu, AppModeMenu, Add, __init__, SelectAppModeCharacterCombos
    Menu, AppModeMenu, DeleteAll
    Menu, AppModeMenu, Add, Character combos, SelectAppModeCharacterCombos
    Menu, AppModeMenu, Add, Skip dialogs, SelectAppModeSkipDialogs

    Menu, ModeMenu, Add, __init__, SelectDynamicCombo
    Menu, ModeMenu, DeleteAll
    if (CharacterCatalog.HasKey(CurrentCharacter)) {
        for index, combo in CharacterCatalog[CurrentCharacter].combos {
            comboLabel := GetComboMenuLabel(combo.id)
            Menu, ModeMenu, Add, %comboLabel%, SelectDynamicCombo
        }
    }

    Menu, CharacterMenu, Add, __init__, SelectDynamicCharacter
    Menu, CharacterMenu, DeleteAll
    for index, characterName in CharacterOrder
        Menu, CharacterMenu, Add, %characterName%, SelectDynamicCharacter

    statusLabel := "Macros: " . (MacroEnabled ? "ON" : "OFF") . " | " . GetAppModeDisplay()
    Menu, Tray, Add, %statusLabel%, TrayNoOp
    Menu, Tray, Disable, %statusLabel%
    Menu, Tray, Add
    Menu, Tray, Add, Settings, ShowSettingsGui
    Menu, Tray, Default, Settings
    Menu, Tray, Click, 1
    Menu, Tray, Add, Select Mode`t%ModeToggleKey%, :AppModeMenu
    Menu, Tray, Add, Select Character`t%CharacterToggleKey%, :CharacterMenu
    Menu, Tray, Add, Select Combo, :ModeMenu
    Menu, Tray, Add

    if (MacroEnabled)
        Menu, Tray, Add, Turn Macros OFF, ToggleScriptEnabled
    else
        Menu, Tray, Add, Turn Macros ON, ToggleScriptEnabled

    Menu, Tray, Add, Reset Hotkeys, ResetAllHotkeys
    Menu, Tray, Add
    Menu, Tray, Add, Reload, ReloadScript
    Menu, Tray, Add, Exit, ExitScript
    SetTrayIconByCharacter()
}



SetCharacter(characterName, showShortcutFeedback := false) {
    global CurrentCharacter, CurrentMacro, MacroRunning, ConfigFile

    if (MacroRunning) {
        if (showShortcutFeedback)
            ShowShortcutTooltip("Release the trigger before changing character", 1200)
        PlayFeedbackSound("error")
        return false
    }

    if (!MacroCatalog_CharacterExists(characterName))
        return false

    if (CurrentCharacter != "" && IsValidComboForCharacter(CurrentCharacter, CurrentMacro))
        IniWrite, %CurrentMacro%, %ConfigFile%, LastCombo, %CurrentCharacter%

    CurrentCharacter := characterName
    IniRead, savedCombo, %ConfigFile%, LastCombo, %CurrentCharacter%,
    if (IsValidComboForCharacter(CurrentCharacter, savedCombo))
        CurrentMacro := savedCombo
    else
        CurrentMacro := GetDefaultComboForCharacter(CurrentCharacter)

    SaveRuntimeSettings()
    SetupTrayMenu()
    UpdateTrayText()

    PlayFeedbackSound("character")
    WebUI_SendState()
    if (showShortcutFeedback)
        ShowShortcutTooltip("Character: " . CurrentCharacter, 1000)
    return true
}



GetAppModeDisplay() {
    global AppMode
    if (AppMode = "SkipDialogs")
        return "Skip dialogs"
    return "Character combos"
}

GetSkipStopModeDisplay() {
    global SkipStopMode
    if (SkipStopMode = "AnyKey")
        return "Until any key pressed"
    return "Until trigger released"
}

SetAppMode(modeName, showShortcutFeedback := false) {
    global AppMode, MacroRunning

    if (MacroRunning) {
        if (showShortcutFeedback)
            ShowShortcutTooltip("Release the trigger before changing mode", 1200)
        PlayFeedbackSound("error")
        return
    }

    if (modeName != "CharacterCombos" && modeName != "SkipDialogs")
        return

    AppMode := modeName
    SaveRuntimeSettings()
    SetupTrayMenu()
    SetTrayIconByCharacter()
    UpdateTrayText()
    PlayFeedbackSound("character")
    WebUI_SendState()
    if (showShortcutFeedback)
        ShowShortcutTooltip("Mode: " . GetAppModeDisplay(), 1100)
}

ToggleSkipStopMode() {
    global SkipStopMode
    if (SkipStopMode = "Release")
        SkipStopMode := "AnyKey"
    else
        SkipStopMode := "Release"
    SaveRuntimeSettings()
    WebUI_SendState()
    ShowModeTooltip("Skip dialogs: " . GetSkipStopModeDisplay(), 1200)
}

SetMode(modeName, showShortcutFeedback := false) {
    global CurrentMacro, CurrentCharacter, MacroRunning

    if (MacroRunning) {
        if (showShortcutFeedback)
            ShowShortcutTooltip("Release the trigger before changing combo", 1200)
        PlayFeedbackSound("error")
        return false
    }

    if (!IsValidComboForCharacter(CurrentCharacter, modeName))
        return false

    CurrentMacro := modeName
    SaveRuntimeSettings()
    SetupTrayMenu()
    UpdateTrayText()
    PlayFeedbackSound("combo")
    WebUI_SendState()
    if (showShortcutFeedback)
        ShowShortcutTooltip("Combo: " . GetComboDisplay(CurrentMacro))
    return true
}



SetTriggerHotkey(newKey, save := true) {
    global TriggerKey, TriggerDownHotkey, TriggerUpHotkey, ConfigFile

    newKey := Trim(newKey)
    if (!IsAllowedBasicHotkey(newKey))
        return false

    oldDown := TriggerDownHotkey
    oldUp := TriggerUpHotkey
    oldKey := TriggerKey

    if (oldDown != "") {
        Hotkey, %oldDown%, Off
        Hotkey, %oldUp%, Off
    }

    newDown := "$*" . newKey
    newUp := "$*" . newKey . " Up"

    try {
        Hotkey, %newDown%, Trigger_Down, On
        Hotkey, %newUp%, Trigger_Up, On
    } catch e {
        if (oldDown != "") {
            Hotkey, %oldDown%, Trigger_Down, On
            Hotkey, %oldUp%, Trigger_Up, On
        }
        TriggerKey := oldKey
        TriggerDownHotkey := oldDown
        TriggerUpHotkey := oldUp
        return false
    }

    TriggerKey := newKey
    TriggerDownHotkey := newDown
    TriggerUpHotkey := newUp

    if (save)
        IniWrite, %TriggerKey%, %ConfigFile%, Settings, TriggerKey

    return true
}

SetComboToggleHotkey(newKey, save := true) {
    global ComboToggleKey, ComboToggleHotkey, ConfigFile

    newKey := Trim(newKey)
    if (!IsAllowedBasicHotkey(newKey))
        return false

    oldHk := ComboToggleHotkey
    oldKey := ComboToggleKey

    if (oldHk != "")
        Hotkey, %oldHk%, Off

    newHk := "$*" . newKey

    try {
        Hotkey, %newHk%, ToggleCombo, On
    } catch e {
        if (oldHk != "")
            Hotkey, %oldHk%, ToggleCombo, On
        ComboToggleKey := oldKey
        ComboToggleHotkey := oldHk
        return false
    }

    ComboToggleKey := newKey
    ComboToggleHotkey := newHk

    if (save)
        IniWrite, %ComboToggleKey%, %ConfigFile%, Settings, ComboToggleKey

    return true
}

SetCharacterToggleHotkey(newKey, save := true) {
    global CharacterToggleKey, CharacterToggleHotkey, ConfigFile

    newKey := Trim(newKey)
    if (!IsAllowedBasicHotkey(newKey))
        return false

    oldHk := CharacterToggleHotkey
    oldKey := CharacterToggleKey

    if (oldHk != "")
        Hotkey, %oldHk%, Off

    newHk := "$*" . newKey

    try {
        Hotkey, %newHk%, ToggleCharacter, On
    } catch e {
        if (oldHk != "")
            Hotkey, %oldHk%, ToggleCharacter, On
        CharacterToggleKey := oldKey
        CharacterToggleHotkey := oldHk
        return false
    }

    CharacterToggleKey := newKey
    CharacterToggleHotkey := newHk

    if (save)
        IniWrite, %CharacterToggleKey%, %ConfigFile%, Settings, CharacterToggleKey

    return true
}

SetModeToggleHotkey(newKey, save := true) {
    global ModeToggleKey, ModeToggleHotkey, ConfigFile

    newKey := Trim(newKey)
    if (!IsAllowedBasicHotkey(newKey))
        return false

    oldHk := ModeToggleHotkey
    oldKey := ModeToggleKey

    if (oldHk != "")
        Hotkey, %oldHk%, Off

    newHk := "$*" . newKey

    try {
        Hotkey, %newHk%, ToggleAppMode, On
    } catch e {
        if (oldHk != "")
            Hotkey, %oldHk%, ToggleAppMode, On
        ModeToggleKey := oldKey
        ModeToggleHotkey := oldHk
        return false
    }

    ModeToggleKey := newKey
    ModeToggleHotkey := newHk

    if (save)
        IniWrite, %ModeToggleKey%, %ConfigFile%, Settings, ModeToggleKey

    return true
}

IsAllowedBasicHotkey(keyName) {
    keyName := Trim(keyName)
    if (keyName = "")
        return false

    StringLower, lowerKey, keyName
    if (lowerKey = "lbutton" || lowerKey = "rbutton" || lowerKey = "q" || lowerKey = "f" || lowerKey = "e" || lowerKey = "w" || lowerKey = "a" || lowerKey = "d" || lowerKey = "shift" || lowerKey = "lshift" || lowerKey = "rshift" || lowerKey = "wheelup" || lowerKey = "wheeldown" || lowerKey = "wheelleft" || lowerKey = "wheelright")
        return false

    return true
}

IsAllowedKeyForTarget(keyName, target) {
    global TriggerKey, ComboToggleKey, CharacterToggleKey, ModeToggleKey

    if (!IsAllowedBasicHotkey(keyName))
        return false

    StringLower, lowerKey, keyName
    StringLower, lowerTrigger, TriggerKey
    StringLower, lowerCombo, ComboToggleKey
    StringLower, lowerCharacter, CharacterToggleKey
    StringLower, lowerMode, ModeToggleKey

    if (target != "Trigger" && lowerKey = lowerTrigger)
        return false
    if (target != "ComboToggle" && lowerKey = lowerCombo)
        return false
    if (target != "CharacterToggle" && lowerKey = lowerCharacter)
        return false
    if (target != "ModeToggle" && lowerKey = lowerMode)
        return false

    return true
}

DisableAllManagedHotkeys() {
    global TriggerDownHotkey, TriggerUpHotkey
    global ComboToggleHotkey, CharacterToggleHotkey, ModeToggleHotkey

    if (TriggerDownHotkey != "") {
        Hotkey, %TriggerDownHotkey%, Off
        if (TriggerUpHotkey != "")
            Hotkey, %TriggerUpHotkey%, Off
    }

    if (ComboToggleHotkey != "")
        Hotkey, %ComboToggleHotkey%, Off

    if (CharacterToggleHotkey != "")
        Hotkey, %CharacterToggleHotkey%, Off

    if (ModeToggleHotkey != "")
        Hotkey, %ModeToggleHotkey%, Off
}


ResetHotkeysToDefault() {
    global MacroRunning

    if (MacroRunning) {
        ShowModeTooltip("Release the trigger before resetting hotkeys", 1200)
        return
    }

    DisableAllManagedHotkeys()
    SetTriggerHotkey("XButton2", true)
    SetComboToggleHotkey("F10", true)
    SetCharacterToggleHotkey("F9", true)
    SetModeToggleHotkey("F8", true)
    SetupTrayMenu()
    UpdateTrayText()
    ShowModeTooltip("Hotkeys reset to default", 1500)
}

UpdateTrayText() {
    global CurrentCharacter, CurrentMacro, MacroEnabled, AppMode, TriggerKey
    global CharacterCatalog, CharacterOrder

    Menu, AppModeMenu, Uncheck, Character combos
    Menu, AppModeMenu, Uncheck, Skip dialogs
    if (AppMode = "SkipDialogs")
        Menu, AppModeMenu, Check, Skip dialogs
    else
        Menu, AppModeMenu, Check, Character combos

    if (CharacterCatalog.HasKey(CurrentCharacter)) {
        for index, combo in CharacterCatalog[CurrentCharacter].combos {
            comboLabel := GetComboMenuLabel(combo.id)
            Menu, ModeMenu, Uncheck, %comboLabel%
        }
        currentComboLabel := GetComboMenuLabel(CurrentMacro)
        Menu, ModeMenu, Check, %currentComboLabel%
    }

    for index, characterName in CharacterOrder
        Menu, CharacterMenu, Uncheck, %characterName%
    Menu, CharacterMenu, Check, %CurrentCharacter%

    status := MacroEnabled ? "ON" : "OFF"
    trayTip := "Status: " . status . "`nMode: " . GetAppModeDisplay() . "`nTrigger: " . TriggerKey
    if (AppMode = "CharacterCombos")
        trayTip .= "`nCharacter: " . CurrentCharacter . "`nCombo: " . GetComboDisplay(CurrentMacro)
    Menu, Tray, Tip, %trayTip%
    SetTrayIconByCharacter()
}



ToggleSoundsEnabled() {
    global SoundsEnabled, ConfigFile

    if (SoundsEnabled) {
        PlayFeedbackSound("off")
        SoundsEnabled := false
    } else {
        SoundsEnabled := true
        PlayFeedbackSound("on")
    }

    soundsValue := SoundsEnabled ? 1 : 0
    IniWrite, %soundsValue%, %ConfigFile%, Settings, SoundsEnabled
    WebUI_SendState()
    ShowModeTooltip("Sounds: " . (SoundsEnabled ? "ON" : "OFF"), 900)
}

Run_SkipDialogs() {
    local delay

    if (SkipStopMode = "AnyKey")
        InitSkipAnyKeySnapshot()

    while (ShouldContinueSkipDialogs()) {
        F_Tap()
        Random, delay, 20, 200
        if (!WaitSkipDialogsDelay(delay))
            return
    }
}

WaitSkipDialogsDelay(ms) {
    local endTime, remaining, sleepMs
    endTime := QpcMs() + ms

    while (ShouldContinueSkipDialogs()) {
        remaining := endTime - QpcMs()
        if (remaining <= 0)
            return true

        if (remaining > 8) {
            sleepMs := Floor(remaining - 3)
            if (sleepMs > 5)
                sleepMs := 5
            DllCall("Sleep", "UInt", sleepMs)
        } else if (remaining > 1.4) {
            DllCall("Sleep", "UInt", 1)
        } else {
            DllCall("SwitchToThread")
        }
    }

    return false
}


ShouldContinueSkipDialogs() {
    global StopRequested, TriggerKey, SkipStopMode

    if (StopRequested)
        return false

    if (SkipStopMode = "Release")
        return GetKeyState(TriggerKey, "P")

    return !AnyNewPhysicalKeyPressed(TriggerKey)
}

BuildSkipInterruptKeyList() {
    keys := "LButton|RButton|MButton|XButton1|XButton2"
    keys .= "|F1|F2|F3|F4|F5|F6|F7|F8|F9|F10|F11|F12"
    keys .= "|0|1|2|3|4|5|6|7|8|9"
    keys .= "|A|B|C|D|E|F|G|H|I|J|K|L|M|N|O|P|Q|R|S|T|U|V|W|X|Y|Z"
    keys .= "|Space|Tab|CapsLock|Backspace|Enter|Escape|Insert|Delete|Home|End|PgUp|PgDn|Up|Down|Left|Right"
    keys .= "|LShift|RShift|LControl|RControl|LAlt|RAlt|AppsKey"
    keys .= "|Numpad0|Numpad1|Numpad2|Numpad3|Numpad4|Numpad5|Numpad6|Numpad7|Numpad8|Numpad9"
    keys .= "|NumpadDot|NumpadAdd|NumpadSub|NumpadMult|NumpadDiv|NumpadEnter"
    return keys
}

InitSkipAnyKeySnapshot() {
    global SkipInitialPressed, SkipInterruptKeyList

    if (SkipInterruptKeyList = "")
        SkipInterruptKeyList := BuildSkipInterruptKeyList()

    SkipInitialPressed := "|"
    Loop, Parse, SkipInterruptKeyList, |
    {
        if (A_LoopField = "")
            continue
        if (GetKeyState(A_LoopField, "P"))
            SkipInitialPressed .= A_LoopField . "|"
    }
}

AnyNewPhysicalKeyPressed(ignoreKey) {
    global SkipInitialPressed, SkipInterruptKeyList

    if (SkipInterruptKeyList = "")
        SkipInterruptKeyList := BuildSkipInterruptKeyList()

    StringLower, ignoreLower, ignoreKey

    Loop, Parse, SkipInterruptKeyList, |
    {
        key := A_LoopField
        if (key = "")
            continue

        StringLower, keyLower, key
        if (keyLower = ignoreLower)
            continue

        if (GetKeyState(key, "P") && !InStr(SkipInitialPressed, "|" . key . "|"))
            return true
    }
    return false
}

F_Tap() {
    F_Down()
    WaitSkipDialogsDelay(8)
    F_Up()
}

F_Down() {
    global FState
    DllCall("keybd_event", "UChar", 0x46, "UChar", 0x21, "UInt", 0, "UPtr", 0)
    FState := true
}

F_Up() {
    global FState
    DllCall("keybd_event", "UChar", 0x46, "UChar", 0x21, "UInt", 2, "UPtr", 0)
    FState := false
}





















ShouldContinue() {
    global StopRequested, TriggerKey
    return (!StopRequested && GetKeyState(TriggerKey, "P"))
}

QpcMs() {
    static freq := 0
    local counter

    if (!freq)
        DllCall("QueryPerformanceFrequency", "Int64*", freq)

    DllCall("QueryPerformanceCounter", "Int64*", counter)
    return (counter * 1000.0 / freq)
}

PreciseSleep(ms) {
    return WaitUntil(QpcMs() + ms)
}

WaitUntil(targetMs) {
    local remaining, sleepMs

    while (ShouldContinue()) {
        remaining := targetMs - QpcMs()
        if (remaining <= 0)
            return true

        if (remaining > 8) {
            sleepMs := Floor(remaining - 3)
            if (sleepMs > 5)
                sleepMs := 5
            DllCall("Sleep", "UInt", sleepMs)
        } else if (remaining > 1.4) {
            DllCall("Sleep", "UInt", 1)
        } else {
            DllCall("SwitchToThread")
        }
    }

    return false
}


Q_Down() {
    global QState
    DllCall("keybd_event", "UChar", 0x51, "UChar", 0x10, "UInt", 0, "UPtr", 0)
    QState := true
}

Q_Up() {
    global QState
    DllCall("keybd_event", "UChar", 0x51, "UChar", 0x10, "UInt", 2, "UPtr", 0)
    QState := false
}

L_Down() {
    global LState
    DllCall("mouse_event", "UInt", 0x0002, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
    LState := true
}

L_Up() {
    global LState
    DllCall("mouse_event", "UInt", 0x0004, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
    LState := false
}

R_Down() {
    global RState
    DllCall("mouse_event", "UInt", 0x0008, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
    RState := true
}

R_Up() {
    global RState
    DllCall("mouse_event", "UInt", 0x0010, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
    RState := false
}

E_Down() {
    global EState
    DllCall("keybd_event", "UChar", 0x45, "UChar", 0x12, "UInt", 0, "UPtr", 0)
    EState := true
}

E_Up() {
    global EState
    DllCall("keybd_event", "UChar", 0x45, "UChar", 0x12, "UInt", 2, "UPtr", 0)
    EState := false
}

W_Down() {
    global WState
    DllCall("keybd_event", "UChar", 0x57, "UChar", 0x11, "UInt", 0, "UPtr", 0)
    WState := true
}

W_Up() {
    global WState
    DllCall("keybd_event", "UChar", 0x57, "UChar", 0x11, "UInt", 2, "UPtr", 0)
    WState := false
}

Shift_Down() {
    global ShiftState
    DllCall("keybd_event", "UChar", 0x10, "UChar", 0x2A, "UInt", 0, "UPtr", 0)
    ShiftState := true
}

Shift_Up() {
    global ShiftState
    DllCall("keybd_event", "UChar", 0x10, "UChar", 0x2A, "UInt", 2, "UPtr", 0)
    ShiftState := false
}


A_Down() {
    global AState
    DllCall("keybd_event", "UChar", 0x41, "UChar", 0x1E, "UInt", 0, "UPtr", 0)
    AState := true
}

A_Up() {
    global AState
    DllCall("keybd_event", "UChar", 0x41, "UChar", 0x1E, "UInt", 2, "UPtr", 0)
    AState := false
}

D_Down() {
    global DState
    DllCall("keybd_event", "UChar", 0x44, "UChar", 0x20, "UInt", 0, "UPtr", 0)
    DState := true
}

D_Up() {
    global DState
    DllCall("keybd_event", "UChar", 0x44, "UChar", 0x20, "UInt", 2, "UPtr", 0)
    DState := false
}


ReleaseAll() {
    global LState, RState, QState, FState, EState, WState, ShiftState, AState, DState

    DllCall("mouse_event", "UInt", 0x0010, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
    DllCall("mouse_event", "UInt", 0x0004, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
    DllCall("keybd_event", "UChar", 0x51, "UChar", 0x10, "UInt", 2, "UPtr", 0)
    DllCall("keybd_event", "UChar", 0x46, "UChar", 0x21, "UInt", 2, "UPtr", 0)
    DllCall("keybd_event", "UChar", 0x45, "UChar", 0x12, "UInt", 2, "UPtr", 0)
    DllCall("keybd_event", "UChar", 0x57, "UChar", 0x11, "UInt", 2, "UPtr", 0)
    DllCall("keybd_event", "UChar", 0x10, "UChar", 0x2A, "UInt", 2, "UPtr", 0)
    DllCall("keybd_event", "UChar", 0x41, "UChar", 0x1E, "UInt", 2, "UPtr", 0)
    DllCall("keybd_event", "UChar", 0x44, "UChar", 0x20, "UInt", 2, "UPtr", 0)
    Sleep, 5
    DllCall("mouse_event", "UInt", 0x0010, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
    DllCall("mouse_event", "UInt", 0x0004, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
    DllCall("keybd_event", "UChar", 0x51, "UChar", 0x10, "UInt", 2, "UPtr", 0)
    DllCall("keybd_event", "UChar", 0x46, "UChar", 0x21, "UInt", 2, "UPtr", 0)
    DllCall("keybd_event", "UChar", 0x45, "UChar", 0x12, "UInt", 2, "UPtr", 0)
    DllCall("keybd_event", "UChar", 0x57, "UChar", 0x11, "UInt", 2, "UPtr", 0)
    DllCall("keybd_event", "UChar", 0x10, "UChar", 0x2A, "UInt", 2, "UPtr", 0)
    DllCall("keybd_event", "UChar", 0x41, "UChar", 0x1E, "UInt", 2, "UPtr", 0)
    DllCall("keybd_event", "UChar", 0x44, "UChar", 0x20, "UInt", 2, "UPtr", 0)

    LState := false
    RState := false
    QState := false
    FState := false
    EState := false
    WState := false
    ShiftState := false
    AState := false
    DState := false
}

StartTimerResolution() {
    global TimerResolutionOn, PerformanceModeOn

    if (!TimerResolutionOn) {
        DllCall("winmm\timeBeginPeriod", "UInt", 1)
        TimerResolutionOn := true
    }

    if (!PerformanceModeOn) {
        Process, Priority,, High
        PerformanceModeOn := true
    }
}

StopTimerResolution() {
    global TimerResolutionOn, PerformanceModeOn

    if (TimerResolutionOn) {
        DllCall("winmm\timeEndPeriod", "UInt", 1)
        TimerResolutionOn := false
    }

    if (PerformanceModeOn) {
        Process, Priority,, AboveNormal
        PerformanceModeOn := false
    }
}



ShowModeTooltip(text, duration := 1200) {
    ; Interface, tray-menu, and legacy-GUI changes use toast/state feedback.
    ; Cursor tooltips are reserved for actual keyboard/mouse shortcuts.
    return
}


ShowShortcutTooltip(text, duration := 1200) {
    SetTimer, HideTooltip, Off
    MouseGetPos, mx, my
    tx := mx + 18
    ty := my + 18
    ToolTip, %text%, %tx%, %ty%
    timerMs := -1 * duration
    SetTimer, HideTooltip, %timerMs%
}

HideTooltip:
    ToolTip
return

CleanupOnExit:
    StopActiveMacroProcess()
    WebUI_SendMessage("type=engineClosing")
    SaveRuntimeSettings()
    ReleaseAll()
    StopTimerResolution()
ExitApp
