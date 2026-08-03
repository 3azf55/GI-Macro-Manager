#NoEnv
#NoTrayIcon
#SingleInstance Force
SetWorkingDir, %A_ScriptDir%

; ===== BEGIN INLINED: MacroRuntime.ahk =====
#NoEnv
#NoTrayIcon
#SingleInstance Force
#MaxThreadsPerHotkey 1
#MaxThreadsBuffer Off
SendMode Input
SetBatchLines, -1
SetMouseDelay, -1
SetKeyDelay, -1, -1
ListLines, Off
Process, Priority,, High

Global MacroTriggerKey := ""
Global LState := false
Global RState := false
Global QState := false
Global FState := false
Global EState := false
Global WState := false
Global ShiftState := false
Global AState := false
Global DState := false
Global TimerResolutionOn := false
Global PerformanceModeOn := false

if IsObject(A_Args) && A_Args.Length() >= 1
    MacroTriggerKey := A_Args[1]
if (MacroTriggerKey = "")
    MacroTriggerKey := "F7"

ShouldContinue() {
    ; Trigger state is monitored by UMM.Engine.ahk.
    ;
    ; The parent hotkey uses the keyboard/mouse hook and suppresses the
    ; original Trigger event. A separate child process cannot reliably read
    ; that physical state with GetKeyState(), which previously made every
    ; macro stop at its first WaitUntil() call.
    ;
    ; The parent closes this process on Trigger_Up and also calls ReleaseAll(),
    ; so the child should continue until it finishes naturally or is stopped
    ; by the parent.
    return true
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

; ===== END INLINED: MacroRuntime.ahk =====


; ===== BEGIN INLINED: _SkirkHelpers.ahk =====
Skirk_DoClicksAndRCheck(count, preRDelay := 50, postRDelay := 210, clickDelay := 39) {
    local i
    Loop % count - 1 {
        L_Down()
        if (!PreciseSleep(clickDelay - 5))
            return false
        L_Up()
        if (!PreciseSleep(clickDelay + 5))
            return false
    }
    L_Down()
    if (!PreciseSleep(clickDelay))
        return false
    L_Up()
    if (!PreciseSleep(preRDelay))
        return false
    if (!ShouldContinue())
        return false
    R_Down()
    if (!PreciseSleep(20))
        return false
    R_Up()
    return PreciseSleep(postRDelay)
}

Skirk_DoClicksAndQCheck(count, qDelay := 700, clickDelay := 39, preQDelay := 50) {
    Loop % count - 1 {
        L_Down()
        if (!PreciseSleep(clickDelay - 5))
            return false
        L_Up()
        if (!PreciseSleep(clickDelay + 5))
            return false
    }
    L_Down()
    if (!PreciseSleep(clickDelay))
        return false
    L_Up()
    if (!PreciseSleep(preQDelay))
        return false
    if (!ShouldContinue())
        return false
    Q_Down()
    if (!PreciseSleep(20))
        return false
    Q_Up()
    return PreciseSleep(qDelay)
}

Skirk_DoClicksAndWCheck(count, wCount, preWalkDelay := 200, wDelay := 50, clickDelay := 40) {
    local i
    Loop % count - 1 {
        L_Down()
        if (!PreciseSleep(clickDelay - 5))
            return false
        L_Up()
        if (!PreciseSleep(clickDelay + 5))
            return false
    }
    L_Down()
    if (!PreciseSleep(clickDelay))
        return false
    L_Up()
    if (!PreciseSleep(preWalkDelay))
        return false
    if (!ShouldContinue())
        return false
    Loop % wCount {
        W_Down()
        if (!PreciseSleep(wDelay))
            return false
        W_Up()
        if (!PreciseSleep(wDelay))
            return false
    }
    return true
}

Skirk_DoChargedAttackCheck(count, delay := 600, clickDelay := 39) {
    Loop % count - 1 {
        L_Down()
        if (!PreciseSleep(clickDelay - 5))
            return false
        L_Up()
        if (!PreciseSleep(clickDelay + 5))
            return false
    }
    if (!ShouldContinue())
        return false
    L_Down()
    if (!PreciseSleep(300))
        return false
    L_Up()
    return PreciseSleep(delay)
}

Skirk_DoClicksOnly(count, clickDelay := 39) {
    Loop % count {
        L_Down()
        if (!PreciseSleep(clickDelay))
            return false
        L_Up()
        if (!PreciseSleep(clickDelay))
            return false
    }
    return true
}

; ===== END INLINED: _SkirkHelpers.ahk =====


StartTimerResolution()
try {
    Run_Skirk_12N2_4N3_Strict()
} finally {
    ReleaseAll()
    StopTimerResolution()
}
ExitApp

Run_Skirk_12N2_4N3_Strict() {
    local eSleep, wCount, count1, prerd, postrd, postwd, prewd

    eSleep := 280
    E_Down()
    if (!PreciseSleep(10))
        return
    E_Up()
    if (!PreciseSleep(eSleep))
        return

    wCount := 33
    count1 := 17
    prerd := 30
    postrd := 160
    postwd := 10
    prewd := 40

    if (!Skirk_DoClicksAndRCheck(count1, prerd + 5, postrd, 10))
        return
    if (!Skirk_DoClicksAndRCheck(count1, prerd, postrd, 10))
        return
    if (!Skirk_DoClicksAndQCheck(17, 655, 10, 40))
        return
    if (!Skirk_DoClicksAndRCheck(count1, prerd, postrd, 10))
        return
    if (!Skirk_DoClicksAndRCheck(count1, prerd, postrd, 10))
        return
    if (!Skirk_DoClicksAndWCheck(27, wCount, prewd, 10, 10))
        return
    if (!PreciseSleep(postwd))
        return
    if (!Skirk_DoClicksAndRCheck(count1, prerd, postrd, 10))
        return
    if (!Skirk_DoClicksAndRCheck(count1, prerd, postrd, 10))
        return
    if (!Skirk_DoClicksAndWCheck(27, wCount, prewd, 10, 10))
        return
    if (!PreciseSleep(postwd))
        return
    if (!Skirk_DoClicksAndRCheck(count1, prerd, postrd, 10))
        return
    if (!Skirk_DoChargedAttackCheck(17, 580, 10))
        return
    if (!Skirk_DoClicksAndRCheck(count1, prerd, postrd, 10))
        return
    if (!Skirk_DoClicksAndWCheck(27, wCount, prewd, 10, 10))
        return
    if (!PreciseSleep(postwd + 10))
        return
    if (!Skirk_DoClicksAndRCheck(count1, prerd, postrd, 10))
        return
    if (!Skirk_DoClicksAndRCheck(count1, prerd, postrd, 10))
        return
    Skirk_DoClicksOnly(36, 10)
}
