; Macro Manager generated runner v4
; Original trigger detected automatically: *$j
#NoEnv
#NoTrayIcon
#SingleInstance Force
#Persistent
SetBatchLines, -1
SetWorkingDir, %A_ScriptDir%
__MM_OriginalTrigger_Skirk_9N2_2N5_N3 := "j"

; Macro Manager export
; Character: Skirk
; Macro: 9N2 2N5 N3
; Tooltip: 
; Tag: 60 FPS
; Execution mode: AutoTrigger
; Detected trigger: *$j
; Exported: 20260802015436 UTC

#NoEnv
#SingleInstance Force
#MaxHotkeysPerInterval 9999
#InstallKeybdHook
#InstallMouseHook
SetBatchLines, -1
SendMode Input
SetWorkingDir %A_ScriptDir%
Process, Priority, , H

; ==============================================================================
; Standalone extraction: Skirk 9N2 2N5 N3
; Source mode: SkirkMacroEnabled = 1 (60 FPS / C0)
; Trigger: hold J. Releasing J aborts immediately and releases held inputs.
; Auto-repeat is latched: one complete combo maximum per physical J press.
;
; Exact logical order:
; E -> 2N2D -> N2Q -> 2N2D -> N5D -> N2D -> N2C
;   -> 2N2D -> N5D -> N3
;
; Exact group durations while J remains held:
; E startup = 10 + 300 = 310 ms                 [300 chosen over 280]
; N2D      = 9*(14 down + 24 gap) + 19 down
;            + 50 pre-D + 20 D + 210 post-D = 641 ms
; N2Q      = 9*(15 down + 25 gap) + 20 down
;            + 50 pre-Q + 20 Q + 655 post-Q = 1105 ms
; N5D      = 45*(15 down + 25 gap) + 20 down
;            + 310 pre-D + 20 D + 210 post-D = 2360 ms
; N2C      = 9*(15 down + 25 gap)
;            + 300 charged hold + 575 post-C = 1235 ms
; N3       = 20*(20 down + 20 gap) = 800 ms
;
; Total nominal duration:
; 310 + 7*641 + 1105 + 2*2360 + 1235 + 800 = 12657 ms
;
; Input totals:
; Left-button presses = 202 (202 downs + 202 ups)
; Shift presses      = 9, each held for 20 ms
; Q presses          = 1, held for 20 ms
; E presses          = 1 logical press, held for 10 ms
;                      (sent through both mechanisms used in the source)
;
; Cumulative group timeline (start -> end, in ms):
; E       0 -> 310
; N2D-1 310 -> 951       N2D-2 951 -> 1592
; N2Q  1592 -> 2697      N2D-3 2697 -> 3338
; N2D-4 3338 -> 3979     N5D-1 3979 -> 6339
; N2D-5 6339 -> 6980     N2C   6980 -> 8215
; N2D-6 8215 -> 8856     N2D-7 8856 -> 9497
; N5D-2 9497 -> 11857    N3   11857 -> 12657
; ==============================================================================

global TriggerKey := "j"
global MacroRunning := false
global TriggerLatched := false
global AbortRequested := false

DllCall("winmm\timeBeginPeriod", "UInt", 1)
OnExit, CleanupTimer
SetTimer, __MM_InvokeImported_Skirk_9N2_2N5_N3, -1
return

; Keep the original game's window restriction.
#IfWinActive ahk_exe GenshinImpact.exe

__MM_ImportedEntry_Skirk_9N2_2N5_N3:
    ; Ignore keyboard auto-repeat and extra down events until physical release.
    if (TriggerLatched)
        return

    TriggerLatched := true
    if (MacroRunning)
        return

    MacroRunning := true
    AbortRequested := false

    try
    {
        RunSkirk9N2Combo()
    }
    finally
    {
        ReleaseAllInputs()
        MacroRunning := false
        if !__MM_GetKeyState_Skirk_9N2_2N5_N3(TriggerKey, "P")
            TriggerLatched := false
    }
return

__MM_ImportedEntryUp_Skirk_9N2_2N5_N3:
    AbortRequested := true
    TriggerLatched := false
    ReleaseAllInputs()
return

#IfWinActive

RunSkirk9N2Combo()
{
    ; Original source sends E by both keybd_event and SendInput.
    HardwareEDown()
    SendInput {e down}
    if !PreciseSleepHeld(10)
        return false

    HardwareEUp()
    SendInput {e up}

    ; Source chose: fps <= 60 ? 300 : 280.
    ; Requested choice: always use 300.
    if !PreciseSleepHeld(300)
        return false

    ; 1) N2D
    if !DoClicksAndDodgeHeld(10, 50, 210, 19)
        return false

    ; 2) N2D
    if !DoClicksAndDodgeHeld(10, 50, 210, 19)
        return false

    ; 3) N2Q
    if !DoClicksAndQHeld(10, 655, 20, 50)
        return false

    ; 4) N2D
    if !DoClicksAndDodgeHeld(10, 50, 210, 19)
        return false

    ; 5) N2D
    if !DoClicksAndDodgeHeld(10, 50, 210, 19)
        return false

    ; 6) N5D
    if !DoClicksAndDodgeHeld(46, 310, 210, 20)
        return false

    ; 7) N2D
    if !DoClicksAndDodgeHeld(10, 50, 210, 19)
        return false

    ; 8) N2C
    if !DoChargedAttackHeld(10, 575, 20)
        return false

    ; 9) N2D
    if !DoClicksAndDodgeHeld(10, 50, 210, 19)
        return false

    ; 10) N2D
    if !DoClicksAndDodgeHeld(10, 50, 210, 19)
        return false

    ; 11) N5D
    if !DoClicksAndDodgeHeld(46, 310, 210, 20)
        return false

    ; 12) N3 final
    return DoClicksOnlyHeld(20, 20)
}

; Reproduces source helper DoClicksAndCheck:
; - First count-1 mouse pulses: (clickDelay-5) down, (clickDelay+5) gap.
; - Last pulse: clickDelay down.
; - Wait preDodgeDelay, press Shift for 20 ms, wait postDodgeDelay.
DoClicksAndDodgeHeld(count, preDodgeDelay := 50, postDodgeDelay := 210, clickDelay := 39)
{
    Loop % count - 1
    {
        HardwareClickDown()
        if !PreciseSleepHeld(clickDelay - 5)
            return false

        HardwareClickUp()
        if !PreciseSleepHeld(clickDelay + 5)
            return false
    }

    HardwareClickDown()
    if !PreciseSleepHeld(clickDelay)
        return false
    HardwareClickUp()

    if !PreciseSleepHeld(preDodgeDelay)
        return false

    SendInput {Shift down}
    if !PreciseSleepHeld(20)
        return false
    SendInput {Shift up}

    return PreciseSleepHeld(postDodgeDelay)
}

; Reproduces source helper DoClicksAndQCheck.
DoClicksAndQHeld(count, qDelay := 700, clickDelay := 39, preQDelay := 50)
{
    Loop % count - 1
    {
        HardwareClickDown()
        if !PreciseSleepHeld(clickDelay - 5)
            return false

        HardwareClickUp()
        if !PreciseSleepHeld(clickDelay + 5)
            return false
    }

    HardwareClickDown()
    if !PreciseSleepHeld(clickDelay)
        return false
    HardwareClickUp()

    if !PreciseSleepHeld(preQDelay)
        return false

    SendInput {q down}
    if !PreciseSleepHeld(20)
        return false
    SendInput {q up}

    return PreciseSleepHeld(qDelay)
}

; Reproduces source helper DoChargedAttackCheck.
DoChargedAttackHeld(count, postChargeDelay := 600, clickDelay := 39)
{
    Loop % count - 1
    {
        HardwareClickDown()
        if !PreciseSleepHeld(clickDelay - 5)
            return false

        HardwareClickUp()
        if !PreciseSleepHeld(clickDelay + 5)
            return false
    }

    HardwareClickDown()
    if !PreciseSleepHeld(300)
        return false
    HardwareClickUp()

    return PreciseSleepHeld(postChargeDelay)
}

; Reproduces source helper DoClicksOnly.
DoClicksOnlyHeld(count, clickDelay := 39)
{
    Loop % count
    {
        HardwareClickDown()
        if !PreciseSleepHeld(clickDelay)
            return false

        HardwareClickUp()
        if !PreciseSleepHeld(clickDelay)
            return false
    }
    return true
}

; High-resolution wait that preserves the requested delay while continuously
; watching the physical J state. It returns false as soon as J is released.
PreciseSleepHeld(delayMs)
{
    global TriggerKey, AbortRequested
    static freq := 0

    if (!freq)
        DllCall("QueryPerformanceFrequency", "Int64*", freq)

    if (AbortRequested || !__MM_GetKeyState_Skirk_9N2_2N5_N3(TriggerKey, "P"))
        return false

    DllCall("QueryPerformanceCounter", "Int64*", start)
    target := delayMs * freq / 1000

    Loop
    {
        if (AbortRequested || !__MM_GetKeyState_Skirk_9N2_2N5_N3(TriggerKey, "P"))
            return false

        DllCall("QueryPerformanceCounter", "Int64*", now)
        remaining := (target - (now - start)) * 1000 / freq

        if (remaining <= 1.2)
            break

        if (remaining > 10)
            DllCall("Sleep", "UInt", 5)
        else
            DllCall("Sleep", "UInt", 1)
    }

    Loop
    {
        if (AbortRequested || !__MM_GetKeyState_Skirk_9N2_2N5_N3(TriggerKey, "P"))
            return false

        DllCall("QueryPerformanceCounter", "Int64*", now)
        if ((now - start) >= target)
            break
        DllCall("Sleep", "UInt", 0)
    }

    return true
}

ReleaseAllInputs()
{
    ; Release through both mechanisms used by the extracted source.
    HardwareClickUp()
    HardwareEUp()
    HardwareQUp()
    HardwareShiftUp()
    SendInput {LButton up}{e up}{q up}{Shift up}
}

HardwareClickDown()
{
    DllCall("mouse_event", "UInt", 0x0002)
}

HardwareClickUp()
{
    DllCall("mouse_event", "UInt", 0x0004)
}

HardwareEDown()
{
    DllCall("keybd_event", "UChar", 0x45, "UChar", 0, "UInt", 0, "Ptr", 0)
}

HardwareEUp()
{
    DllCall("keybd_event", "UChar", 0x45, "UChar", 0, "UInt", 2, "Ptr", 0)
}

HardwareQUp()
{
    DllCall("keybd_event", "UChar", 0x51, "UChar", 0, "UInt", 2, "Ptr", 0)
}

HardwareShiftUp()
{
    DllCall("keybd_event", "UChar", 0x10, "UChar", 0, "UInt", 2, "Ptr", 0)
}

CleanupTimer:
    ReleaseAllInputs()
    DllCall("winmm\timeEndPeriod", "UInt", 1)
    ExitApp
return



__MM_CanonicalKey_Skirk_9N2_2N5_N3(keyName) {
    keyName := Trim(keyName)
    keyName := RegExReplace(keyName, "i)\s+Up$")
    keyName := RegExReplace(keyName, "^[~*$]+")
    keyName := RegExReplace(keyName, "\s+", " ")
    StringLower, keyName, keyName
    return keyName
}

__MM_GetKeyState_Skirk_9N2_2N5_N3(keyName, mode := "") {
    global __MM_OriginalTrigger_Skirk_9N2_2N5_N3
    canonicalKey := __MM_CanonicalKey_Skirk_9N2_2N5_N3(keyName)
    if (canonicalKey = __MM_OriginalTrigger_Skirk_9N2_2N5_N3 && (mode = "" || mode = "P"))
        return true
    return GetKeyState(keyName, mode)
}

__MM_InvokeImported_Skirk_9N2_2N5_N3:
Gosub, __MM_ImportedEntry_Skirk_9N2_2N5_N3
return
