;@Ahk2Exe-SetName SHHis
;@Ahk2Exe-SetProductName SHHis
;@Ahk2Exe-SetDescription SHHis
;@Ahk2Exe-SetVersion 0.1.2
;@Ahk2Exe-SetCompanyName ゼルコIST
;@Ahk2Exe-SetOrigFilename SHHis.exe

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

if not A_IsAdmin {
    try {
        Run('*RunAs "' . A_ScriptFullPath . '"')
    }
    ExitApp()
}

global AppName       := "SHHis"
global TaskName      := "SHHisAutoStart"
global IniFile       := A_ScriptDir . "\config.ini"
global CurrentHotkey := IniRead(IniFile, "Settings", "Hotkey", "^!a")
global ShowOSD       := IniRead(IniFile, "Settings", "ShowOSD", 1)

A_IconTip := AppName
SetupTrayMenu()
RegisterHotkey(CurrentHotkey)

; ==============================================================================
; 托盘菜单与快捷键设置界面
; ==============================================================================
SetupTrayMenu() {
    global CurrentHotkey, ShowOSD, TaskName, AppName
    displayHotkey := FormatHotkey(CurrentHotkey)

    A_TrayMenu.Delete()
    A_TrayMenu.Add("当前快捷键: " . displayHotkey, ShowSettingsGui)
    A_TrayMenu.Disable("当前快捷键: " . displayHotkey)
    A_TrayMenu.Add()
    A_TrayMenu.Add("修改快捷键", ShowSettingsGui)

    isAutoStart := (RunWait('schtasks /query /tn "' . TaskName . '"',, "Hide") = 0)
    A_TrayMenu.Add("开机自启动", ToggleAutoStart)
    if isAutoStart
        A_TrayMenu.Check("开机自启动")

    A_TrayMenu.Add("屏幕状态提示", ToggleOSD)
    if ShowOSD
        A_TrayMenu.Check("屏幕状态提示")

    A_TrayMenu.Add()
    A_TrayMenu.Add("退出 " . AppName, (*) => ExitApp())
}

FormatHotkey(hk) {
    if (hk = "")
        return "无"

    hasCtrl := false, hasShift := false, hasAlt := false, hasWin := false
    pos := 1
    len := StrLen(hk)

    while (pos < len) {
        ch := SubStr(hk, pos, 1)
        if (ch = "^")
            hasCtrl := true
        else if (ch = "+")
            hasShift := true
        else if (ch = "!")
            hasAlt := true
        else if (ch = "#")
            hasWin := true
        else if (ch = "<" || ch = ">" || ch = "*" || ch = "~" || ch = "$")
            pos := pos
        else
            break
        pos += 1
    }

    parts := []
    if hasCtrl
        parts.Push("Ctrl")
    if hasShift
        parts.Push("Shift")
    if hasAlt
        parts.Push("Alt")
    if hasWin
        parts.Push("Win")

    mainKey := SubStr(hk, pos)
    if (resolved := GetKeyName(mainKey)) != ""
        mainKey := resolved
    if (StrLen(mainKey) = 1)
        mainKey := StrUpper(mainKey)

    parts.Push(mainKey)

    result := ""
    for idx, val in parts
        result .= (idx > 1 ? "+" : "") . val
    return result
}

RegisterHotkey(key) {
    global CurrentHotkey, IniFile
    if (CurrentHotkey != "") {
        try Hotkey(CurrentHotkey, "Off")
    }
    if (key != "") {
        try {
            Hotkey(key, MuteActiveApp, "On")
            CurrentHotkey := key
            IniWrite(CurrentHotkey, IniFile, "Settings", "Hotkey")
            return true
        }
    }
    return false
}

ShowSettingsGui(*) {
    global AppName, CurrentHotkey
    myGui := Gui("+AlwaysOnTop -MinimizeBox", AppName . " - 快捷键设置")
    myGui.SetFont("s10", "Segoe UI")
    myGui.Add("Text", "xm ym", "请直接在下方输入框中按下你想绑定的快捷键：")
    hkInput := myGui.Add("Hotkey", "xm y+10 w260 vInputHotkey", CurrentHotkey)
    saveBtn := myGui.Add("Button", "xm y+15 w120 Default", "保存并生效")
    saveBtn.OnEvent("Click", (*) => SaveSettings(myGui, hkInput.Value))
    cancelBtn := myGui.Add("Button", "x+20 yp w120", "取消")
    cancelBtn.OnEvent("Click", (*) => myGui.Destroy())
    myGui.Show()
}

SaveSettings(guiObj, newKey) {
    global AppName
    if (newKey = "") {
        MsgBox("快捷键不能为空！", AppName, "Icon! Owner" . guiObj.Hwnd)
        return
    }
    if RegisterHotkey(newKey) {
        SetupTrayMenu()
        guiObj.Destroy()
        MsgBox("快捷键已成功更新为: " . FormatHotkey(newKey), AppName, 64 | 0x40000)
    } else {
        MsgBox("该快捷键已被系统占用或无效，请更换组合。", AppName, "Iconx Owner" . guiObj.Hwnd)
    }
}

ToggleAutoStart(*) {
    global TaskName
    exePath := A_ScriptFullPath
    runWaitResult := RunWait('schtasks /query /tn "' . TaskName . '"',, "Hide")
    if (runWaitResult = 0) {
        RunWait('schtasks /delete /tn "' . TaskName . '" /f',, "Hide")
    } else {
        cmd := 'schtasks /create /tn "' . TaskName . '" /tr "\"' . exePath . '\"" /sc onlogon /rl highest /f'
        RunWait(cmd,, "Hide")
    }
    SetupTrayMenu()
}

ToggleOSD(*) {
    global ShowOSD, IniFile
    ShowOSD := !ShowOSD
    IniWrite(ShowOSD, IniFile, "Settings", "ShowOSD")
    SetupTrayMenu()
}

; ==============================================================================
; 核心功能：切换当前焦点窗口的静音状态
; ==============================================================================
MuteActiveApp(*) {
    global ShowOSD
    try {
        activePID := WinGetPID("A")
        activeProcess := WinGetProcessName("A")
    } catch {
        return
    }

    try {
        deviceEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
        if !deviceEnumerator
            return

        defaultDevice := 0
        ComCall(4, deviceEnumerator, "Int", 0, "Int", 1, "Ptr*", &defaultDevice)
        if !defaultDevice
            return

        sessionManager := 0
        buf_IAudioSessionManager2 := StringToIID("{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}")
        ComCall(3, defaultDevice, "Ptr", buf_IAudioSessionManager2, "UInt", 7, "Ptr", 0, "Ptr*", &sessionManager)
        ObjRelease(defaultDevice)
        if !sessionManager
            return

        sessionEnumerator := 0
        ComCall(5, sessionManager, "Ptr*", &sessionEnumerator)
        ObjRelease(sessionManager)
        if !sessionEnumerator
            return

        count := 0
        ComCall(3, sessionEnumerator, "Int*", &count)

        targetFound := false, newMuteState := -1
        buf_IAudioSessionControl2 := StringToIID("{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}")
        buf_ISimpleAudioVolume    := StringToIID("{87CE5498-68D6-44E5-9215-6DA47EF883D8}")

        Loop count {
            sessionControl := 0
            try {
                ComCall(4, sessionEnumerator, "Int", A_Index - 1, "Ptr*", &sessionControl)
            } catch {
                continue
            }
            if !sessionControl
                continue

            sessionControl2 := 0
            try ComCall(0, sessionControl, "Ptr", buf_IAudioSessionControl2, "Ptr*", &sessionControl2)

            if sessionControl2 {
                pid := 0
                try ComCall(14, sessionControl2, "UInt*", &pid)
                ObjRelease(sessionControl2)

                isMatch := (pid = activePID)
                if !isMatch && pid != 0 {
                    try {
                        if (StrLower(ProcessGetName(pid)) = StrLower(activeProcess))
                            isMatch := true
                    }
                }

                if isMatch {
                    simpleAudioVolume := 0
                    try ComCall(0, sessionControl, "Ptr", buf_ISimpleAudioVolume, "Ptr*", &simpleAudioVolume)

                    if simpleAudioVolume {
                        isMuted := 0
                        try {
                            ComCall(6, simpleAudioVolume, "Int*", &isMuted)
                            if (newMuteState = -1)
                                newMuteState := !isMuted
                            ComCall(5, simpleAudioVolume, "Int", newMuteState, "Ptr", 0)
                            targetFound := true
                        }
                        ObjRelease(simpleAudioVolume)
                    }
                }
            }
            ObjRelease(sessionControl)
        }
        ObjRelease(sessionEnumerator)

        if ShowOSD {
            if targetFound {
                msg := newMuteState ? "🔇 [已静音] " . activeProcess : "🔊 [已恢复] " . activeProcess
                ToolTip(msg)
                SetTimer(() => ToolTip(), -1500)
            } else {
                ToolTip("⚠️ " . activeProcess . " 当前无活跃音频流")
                SetTimer(() => ToolTip(), -1500)
            }
        }
    }
}

StringToIID(guidStr) {
    buf := Buffer(16)
    DllCall("ole32\CLSIDFromString", "WStr", guidStr, "Ptr", buf)
    return buf
}