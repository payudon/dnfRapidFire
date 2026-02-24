#Requires AutoHotkey v2.0
#MaxThreadsPerHotkey 1
#MaxThreadsBuffer 0
ProcessSetPriority "High"
DetectHiddenWindows True ; 必须开启，用于扫描隐藏的输入法窗口

global KeyStatus := Map()
global Config := Map()
global IsEnabled := true

; ====================
;      GUI 设置
; ====================
MainGui := Gui("AlwaysOnTop", "任意多键连发-不影响打字版")
MainGui.OnEvent("Close", (*) => ExitApp())
MainGui.Add("Text", "x10 y15 w40", "按键:")
KeyInput := MainGui.Add("Edit", "x50 y10 w80", "")
MainGui.Add("Text", "x140 y15 w60", "间隔(ms):")
IntervalInput := MainGui.Add("Edit", "x200 y10 w60", "100")
AddBtn := MainGui.Add("Button", "x270 y10 w50", "添加")
AddBtn.OnEvent("Click", AddHotkey)
LV := MainGui.Add("ListView", "x10 y40 w370 h100", ["按键", "间隔(ms)"])
LV.ModifyCol(1, 180), LV.ModifyCol(2, 180)

StatusText := MainGui.Add("Text", "x10 y150 w370 cGreen", "状态：检测中... (F12切换开关)")
MainGui.Show("w390 h180")

SetTimer(GlobalWorker, 10)

; ====================
;      核心逻辑
; ====================

AddHotkey(*) {
    k := KeyInput.Value, i := IntervalInput.Value
    if (k = "" || i = "") {
        return
    }
    try {
        Hotkey("~*$" . k, (*) => (KeyStatus[k] := true), "On")
        Hotkey("~*$" . k . " Up", (*) => (KeyStatus[k] := false), "On")
        Config[k] := {interval: Number(i), lastTick: 0}
        KeyStatus[k] := false
        LV.Add("", k, i)
        KeyInput.Value := ""
    } catch {
        MsgBox("无效键名")
    }
}

; --- 多模态探测函数 ---
IsTyping() {
    ; 1. 检查光标形状：如果在打字，光标通常是 IBeam (工字型)
    ; 这是最简单但也极其有效的判断方案
    if (A_Cursor = "IBeam") {
        return true
    }

    ; 2. 检查系统 GUI 线程信息 (Flags 0x20 = GUI_IMECOMPOSITION)
    ; 这是 Windows 原生的“正在输入”标志位
    stGui := Buffer(72, 0)
    NumPut("UInt", 72, stGui)
    if (DllCall("User32.dll\GetGUIThreadInfo", "UInt", 0, "Ptr", stGui)) {
        flags := NumGet(stGui, 4, "UInt")
        if (flags & 0x20) { ; 0x20 代表正在进行输入法合成
            return true
        }
    }

    ; 3. 检查常见的候选框窗口 (兼容 Win10/11 微软拼音)
    ; 新版微软拼音有时隐藏在 InputHost.exe 中
    if WinExist("ahk_class MSIME_Candidate_Window") || WinExist("ahk_class TSF_Candidate_Window") {
        style := WinGetStyle("ahk_class MSIME_Candidate_Window") || WinGetStyle("ahk_class TSF_Candidate_Window")
        if (style & 0x10000000) { ; 窗口可见
            return true
        }
    }
    
    return false
}

GlobalWorker() {
    if (IsEnabled = false) {
        return
    }

    ; 只要符合打字特征，立即停止连发逻辑
    if (IsTyping()) {
        return
    }

    for key, active in KeyStatus {
        if (active) {
            if (GetKeyState(key, "P") = false) {
                KeyStatus[key] := false
                continue
            }
            conf := Config[key]
            if (A_TickCount - conf.lastTick >= conf.interval) {
                DoPureClick(key)
                conf.lastTick := A_TickCount
            }
        }
    }
}

DoPureClick(key) {
    SendEvent("{Blind}{" . key . " Down}")
    Sleep(5)
    SendEvent("{Blind}{" . key . " Up}")
}

; F12 总开关
F12:: {
    global IsEnabled := !IsEnabled
    if (IsEnabled) {
        StatusText.Text := "状态：运行中 (F12切换)"
        StatusText.Opt("cGreen")
    } else {
        StatusText.Text := "状态：已手动停止"
        StatusText.Opt("cRed")
        for key, value in KeyStatus {
            KeyStatus[key] := false
            SendEvent("{Blind}{" . key . " Up}")
        }
    }
}

^F12::Reload()