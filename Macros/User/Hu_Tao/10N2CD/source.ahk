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


StartTimerResolution()
try {
    Run_HuTao_10N2CD_Strict()
} finally {
    ReleaseAll()
    StopTimerResolution()
}
ExitApp

Run_HuTao_10N2CD_Strict() {
    ; Extracted from Tao 10N2CD.
    ; The source uses the <=60 FPS E startup delay: 450 ms.
    E_Down()
    if (!PreciseSleep(10))
        return
    E_Up()
    if (!PreciseSleep(450))
        return

    while (ShouldContinue()) {
        L_Down()
        if (!PreciseSleep(20))
            return
        L_Up()
        if (!PreciseSleep(175))
            return

        L_Down()
        if (!PreciseSleep(20))
            return
        L_Up()
        if (!PreciseSleep(120))
            return

        L_Down()
        if (!PreciseSleep(275))
            return
        L_Up()
        if (!PreciseSleep(50))
            return

        R_Down()
        if (!PreciseSleep(50))
            return
        R_Up()

        A_Down()
        if (!PreciseSleep(20))
            return
        A_Up()
        if (!PreciseSleep(55))
            return

        D_Down()
        if (!PreciseSleep(20))
            return
        D_Up()
        if (!PreciseSleep(55))
            return

        if (!PreciseSleep(125))
            return
    }
}
