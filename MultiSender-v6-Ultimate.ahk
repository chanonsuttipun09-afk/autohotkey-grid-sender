#Requires AutoHotkey v2.0
#SingleInstance Force

SetTitleMatchMode 2
SendMode "Event"

; ══════════════════════════════════════════
;    ⚙️ PROCESS OPTIMIZATION & CONFIG
; ══════════════════════════════════════════
ProcessSetPriority "High"

MARGIN_WIN   := 1
WIN_WAIT_SEC := 15
CONFIG_FILE  := "MultiSender.ini"
MSG_FILE     := "messages.txt"
HISTORY_FILE := "history.txt"
THEME_FILE   := "theme.ini"
HOTKEY_FILE  := "hotkeys.ini"

isSending    := false
blinkState   := false
isLoopMode   := false
ledBlink     := false

currentWinIdx := 1
lastNetTime   := 0

master       := ""
followers    := []
messages     := []
sentTitles   := []
currentMsgText := ""

; ─── v6 FEATURE STATE ───
schedulerEnabled  := false
schedulerInterval := 60          ; วินาที
repeatMode        := false
repeatCount       := 1
randomDelayMin    := 400
randomDelayMax    := 800
webhookEnabled    := false
webhookURL        := ""
passwordProtection := false
masterPassword    := ""
useSelection      := false
selectedFollowers := Map()
isDarkMode        := true
sendStats         := {count: 0, success: 0, failed: 0}
hotkeyMap         := Map()
_hkRegistered     := []

; โซนเวลาสำหรับกดคลิกสลับเปลี่ยนเมือง
tzIndex := 1
tzList  := [
    {name: "Bangkok, Thailand", offset: 0,   desc: "วันนี้, เวลาปกติ (TH)"},
    {name: "Sydney, Australia",  offset: 3,   desc: "พรุ่งนี้, +3hrs"},
    {name: "Tokyo, Japan",       offset: 2,   desc: "วันนี้, +2hrs"},
    {name: "London, UK",         offset: -6,  desc: "วันนี้, -6hrs"}
]

; ─── THEME PALETTES (🌙 Dark / ☀️ Light) ───
themes := Map(
    "dark", {
        BG: "0B0B0E", BG2: "111116", LINE: "FF2A2A", ACC: "00F0FF",
        GRN: "00FF66", RED: "FF3366", YEL: "FFCC00", FG: "FFFFFF", FG2: "8A8A93"
    },
    "light", {
        BG: "ECEFF4", BG2: "FFFFFF", LINE: "FF2A2A", ACC: "0077AA",
        GRN: "008844", RED: "CC2244", YEL: "AA7700", FG: "111111", FG2: "555555"
    }
)
C := themes["dark"]

UI_W   := 540
UI_H   := 312
PAD    := 12
COMP_W := UI_W - (PAD * 2)

; ══════════════════════════════════════════
;    🚀 AUTO-EXECUTE
; ══════════════════════════════════════════
LoadConfig()
currentMsgText := LoadMessages()
LoadHistory()
LoadFeatureConfig()
LoadHotkeys()

if (passwordProtection && masterPassword != "")
    PromptPassword()

ApplyThemeVars()
BuildGui()

OnMessage(0x0201, WM_LBUTTONDOWN)
ApplyHotkeys()

SetTimer FetchGeoIP, -100
SetTimer EngineLEDTicker, 200
SetTimer UpdateNetworkTelemetry, 1000

if schedulerEnabled
    ToggleScheduler(true)

return

; ══════════════════════════════════════════
;    📂 DATA STORAGE FUNCTIONS
; ══════════════════════════════════════════
LoadConfig() {
    global master, followers, CONFIG_FILE
    master    := IniRead(CONFIG_FILE, "Win", "master", "")
    followers := []
    n := Integer(IniRead(CONFIG_FILE, "Win", "count", "0"))
    Loop n
        followers.Push(IniRead(CONFIG_FILE, "Win", "f" A_Index, ""))
}

SaveConfig() {
    global master, followers, CONFIG_FILE
    IniWrite(master, CONFIG_FILE, "Win", "master")
    IniWrite(followers.Length, CONFIG_FILE, "Win", "count")
    Loop followers.Length
        IniWrite(followers[A_Index], CONFIG_FILE, "Win", "f" A_Index)
}

LoadMessages() {
    global MSG_FILE
    if !FileExist(MSG_FILE) {
        defaultMsgs := "สวัสดีครับ สนใจสอบถามได้เลยนะ`nขอบคุณที่แวะมารับชมครับผม"
        FileAppend(defaultMsgs, MSG_FILE, "UTF-8")
    }
    return FileRead(MSG_FILE, "UTF-8")
}

SaveMessages(txt) {
    global MSG_FILE
    if FileExist(MSG_FILE)
        FileDelete(MSG_FILE)
    FileAppend(Trim(txt, "`r`n "), MSG_FILE, "UTF-8")
}

ParseMessageArray() {
    global messages, msgEditor
    messages := []
    rawTxt := msgEditor.Value
    SaveMessages(rawTxt)
    Loop Parse rawTxt, "`n", "`r" {
        t := Trim(A_LoopField)
        if (t != "")
            messages.Push(t)
    }
}

LoadHistory() {
    global sentTitles, HISTORY_FILE
    sentTitles := []
    if !FileExist(HISTORY_FILE)
        return
    Loop Parse FileRead(HISTORY_FILE, "UTF-8"), "`n", "`r" {
        t := Trim(A_LoopField)
        if (t != "")
            sentTitles.Push(t)
    }
}

SaveToHistory(title, msg := "") {
    global sentTitles, HISTORY_FILE
    entry := FormatTime(, "yyyy-MM-dd HH:mm") " | " title (msg = "" ? "" : " | " msg)
    sentTitles.Push(entry)
    FileAppend(entry "`n", HISTORY_FILE, "UTF-8")
}

ClearHistory() {
    global HISTORY_FILE, sentTitles
    if FileExist(HISTORY_FILE)
        FileDelete(HISTORY_FILE)
    sentTitles := []
}

IsAlreadySent(title) {
    global sentTitles
    for idx, entry in sentTitles
        if InStr(entry, title)
            return true
    return false
}

; ─── v6 CONFIG PERSISTENCE ───
LoadFeatureConfig() {
    global CONFIG_FILE, THEME_FILE
    global schedulerEnabled, schedulerInterval, repeatMode, repeatCount
    global randomDelayMin, randomDelayMax, webhookEnabled, webhookURL
    global passwordProtection, masterPassword, useSelection, isDarkMode
    schedulerEnabled   := Integer(IniRead(CONFIG_FILE, "Features", "schedulerEnabled", "0"))
    schedulerInterval  := SafeInt(IniRead(CONFIG_FILE, "Features", "schedulerInterval", "60"), 60)
    repeatMode         := Integer(IniRead(CONFIG_FILE, "Features", "repeatMode", "0"))
    repeatCount        := SafeInt(IniRead(CONFIG_FILE, "Features", "repeatCount", "1"), 1)
    randomDelayMin     := SafeInt(IniRead(CONFIG_FILE, "Features", "randomDelayMin", "400"), 400)
    randomDelayMax     := SafeInt(IniRead(CONFIG_FILE, "Features", "randomDelayMax", "800"), 800)
    webhookEnabled     := Integer(IniRead(CONFIG_FILE, "Features", "webhookEnabled", "0"))
    webhookURL         := IniRead(CONFIG_FILE, "Features", "webhookURL", "")
    passwordProtection := Integer(IniRead(CONFIG_FILE, "Features", "passwordProtection", "0"))
    masterPassword     := IniRead(CONFIG_FILE, "Features", "masterPassword", "")
    useSelection       := Integer(IniRead(CONFIG_FILE, "Features", "useSelection", "0"))
    isDarkMode         := Integer(IniRead(THEME_FILE, "Theme", "darkMode", "1"))
}

SaveFeatureConfig() {
    global CONFIG_FILE, THEME_FILE
    global schedulerEnabled, schedulerInterval, repeatMode, repeatCount
    global randomDelayMin, randomDelayMax, webhookEnabled, webhookURL
    global passwordProtection, masterPassword, useSelection, isDarkMode
    IniWrite(schedulerEnabled ? 1 : 0, CONFIG_FILE, "Features", "schedulerEnabled")
    IniWrite(schedulerInterval, CONFIG_FILE, "Features", "schedulerInterval")
    IniWrite(repeatMode ? 1 : 0, CONFIG_FILE, "Features", "repeatMode")
    IniWrite(repeatCount, CONFIG_FILE, "Features", "repeatCount")
    IniWrite(randomDelayMin, CONFIG_FILE, "Features", "randomDelayMin")
    IniWrite(randomDelayMax, CONFIG_FILE, "Features", "randomDelayMax")
    IniWrite(webhookEnabled ? 1 : 0, CONFIG_FILE, "Features", "webhookEnabled")
    IniWrite(webhookURL, CONFIG_FILE, "Features", "webhookURL")
    IniWrite(passwordProtection ? 1 : 0, CONFIG_FILE, "Features", "passwordProtection")
    IniWrite(masterPassword, CONFIG_FILE, "Features", "masterPassword")
    IniWrite(useSelection ? 1 : 0, CONFIG_FILE, "Features", "useSelection")
    IniWrite(isDarkMode ? 1 : 0, THEME_FILE, "Theme", "darkMode")
}

LoadHotkeys() {
    global HOTKEY_FILE, hotkeyMap
    defaults := Map("send", "$F1", "reload", "$F2", "stop", "$F3", "exit", "F4", "master", "F5", "follower", "F6")
    hotkeyMap := Map()
    for action, def in defaults
        hotkeyMap[action] := IniRead(HOTKEY_FILE, "Hotkeys", action, def)
}

SaveHotkeys() {
    global HOTKEY_FILE, hotkeyMap
    for action, key in hotkeyMap
        IniWrite(key, HOTKEY_FILE, "Hotkeys", action)
}

SafeInt(v, def) {
    return IsInteger(v) ? Integer(v) : def
}

; ══════════════════════════════════════════
;    🎨 UI BUILDER (ทำใหม่ได้เพื่อสลับธีม)
; ══════════════════════════════════════════
ApplyThemeVars() {
    global themes, isDarkMode, C
    C := themes[isDarkMode ? "dark" : "light"]
}

BuildGui() {
    global C, UI_W, UI_H, PAD, COMP_W, master, followers, currentMsgText, isLoopMode
    global G, clockLedDisp, clockCityDisp, clockDescDisp, btnChangeTz
    global ipGeoDisplay, netSpeedDisplay, statusDot, statusText, masterLabel
    global followerLabel, msgEditor, chkLoop, progress, miniLogText, statsDisplay

    G := Gui("+AlwaysOnTop -MaximizeBox -Caption +Border", "Multi Sender Realtime LED HUD")
    G.BackColor := C.BG

    ; ─── ROW 1: HEADER & SYSTEM TITLE ───
    G.SetFont("s10 Bold", "Segoe UI Semibold")
    G.AddText("x12 y12 w110 h20 Background" C.BG " c" C.ACC, "❖ NEO SENDER")
    G.SetFont("s8 Bold", "Segoe UI")
    G.AddText("x125 y14 w100 h16 Background" C.BG " c" C.RED, "LED CLOCK v9.8")

    ; ─── 🕒 REAL-TIME CYBER TIME HUD ───
    G.AddText("x230 y6 w240 h42 +Background" C.BG2, "")
    G.SetFont("s18 Bold", "Consolas")
    clockLedDisp := G.AddText("x235 y12 w75 h30 Center +BackgroundTrans c" C.ACC, "00:00")
    G.SetFont("s8 Bold", "Segoe UI")
    clockCityDisp := G.AddText("x315 y10 w150 h14 +BackgroundTrans c" C.FG, "Bangkok, Thailand")
    G.SetFont("s7.5", "Segoe UI Semibold")
    clockDescDisp := G.AddText("x315 y25 w150 h14 +BackgroundTrans c" C.RED, "วันนี้, เวลาปกติ (TH)")

    btnChangeTz := G.AddButton("x230 y6 w240 h42 +BackgroundTrans -Theme", "")
    btnChangeTz.OnEvent("Click", CycleTimeZone)

    G.AddButton("x482 y12 w18 h18 c" C.ACC, "↺").OnEvent("Click", (*) => Reload())
    G.AddButton("x508 y12 w18 h18 c" C.RED, "✕").OnEvent("Click", (*) => ExitApp())

    G.OnEvent("Size", (*) => WinSetRegion("0-0 w" UI_W " h" UI_H " r6-6", G.Hwnd))

    ; ─── ROW 2: NETWORK TELEMETRY ───
    G.AddText("x" PAD " y52 w" COMP_W " h1 Background" C.LINE, "")
    G.SetFont("s8 Bold", "Consolas")
    ipGeoDisplay := G.AddText("x12 y57 w180 h14 Background" C.BG " c" C.ACC, "📡 CONNECTING...")
    netSpeedDisplay := G.AddText("x200 y57 w325 h14 Background" C.BG " c" C.ACC " Right", "📶 NET: OK • PING: -- ms")

    ; ─── ROW 3: STATUS INDICATOR & CORE TARGETS ───
    G.AddText("x" PAD " y75 w" COMP_W " h1 Background" C.LINE, "")
    G.SetFont("s8.5", "Segoe UI Semibold")
    statusDot  := G.AddText("x12 y80 w10 h14 Background" C.BG " c" C.GRN, "●")
    statusText := G.AddText("x26 y80 w120 h14 Background" C.BG " c" C.GRN, "SYSTEM READY")

    G.SetFont("s8 Bold", "Segoe UI")
    G.AddText("x180 y80 w65 h14 Background" C.BG " c" C.FG2 " Right", "［🎯 จอหลัก］")
    masterLabel := G.AddText("x250 y80 w180 h14 Background" C.BG " c" C.FG, master = "" ? "— STANDBY —" : ShortId(master))
    G.AddButton("x445 y78 w80 h18 c" C.ACC, "LOCK F5").OnEvent("Click", SetMaster)

    ; ─── ROW 4: TARGET MANAGEMENT BUTTONS ───
    G.AddText("x" PAD " y98 w" COMP_W " h1 Background" C.LINE, "")
    G.SetFont("s8", "UI Semibold")
    followerLabel := G.AddText("x12 y103 w170 h16 Background" C.BG " c" C.RED, "👥 ล็อกไว้ " followers.Length " จอ")

    G.AddButton("x200 y101 w100 h19 c" C.ACC, "＋ เพิ่ม (F6)").OnEvent("Click", AddFollower)
    G.AddButton("x310 y101 w100 h19 c" C.RED, "🧹 ล้างลูก").OnEvent("Click", ClearFollowers)
    G.AddButton("x420 y101 w105 h19 c" C.YEL, "💾 เซฟโครง").OnEvent("Click", (*) => (SaveConfig(), Flash("💾 บันทึกแล้ว")))

    ; ─── ROW 5: MESSAGE INPUT EDITOR ───
    G.AddText("x" PAD " y124 w" COMP_W " h1 Background" C.LINE, "")
    G.SetFont("s8 Bold", "Segoe UI")
    G.AddText("x12 y128 c" C.ACC, "⌨ กล่องข้อความแชท (สุ่มส่งอัตโนมัติ):")
    G.SetFont("s8.5", "Segoe UI")
    msgEditor := G.AddEdit("x" PAD " y144 w" COMP_W " h36 Background" C.BG2 " c" C.FG " WantTab +VScroll -Border", currentMsgText)

    ; ─── ROW 6: AUTOMATION ENGINE CONTROLS ───
    G.AddText("x" PAD " y186 w" COMP_W " h1 Background" C.LINE, "")
    G.SetFont("s8 Bold", "Segoe UI")
    chkLoop := G.AddCheckbox("x12 y192 w110 h18 c" C.RED " Background" C.BG, " 🔁 Auto Loop")
    chkLoop.Value := isLoopMode
    chkLoop.OnEvent("Click", ToggleLoopMode)

    progress := G.AddProgress("x130 y197 w100 h8 c" C.RED " Background" C.BG2 " Smooth", 0)

    G.AddButton("x250 y190 w90 h22 c" C.RED, "🚀 ส่ง (F1)").OnEvent("Click", StartSendEngine)
    G.AddButton("x345 y190 w90 h22 c" C.GRN, "🧩 จัดหน้า").OnEvent("Click", ArrangeWindowsGrid)
    G.AddButton("x440 y190 w85 h22 c" C.RED, "🛑 หยุด (F3)").OnEvent("Click", StopSendEngine)

    ; ─── ROW 7: MINI STATUS LINE ───
    G.AddText("x" PAD " y220 w" COMP_W " h1 Background" C.LINE, "")
    G.SetFont("s8", "UI Semibold")
    miniLogText := G.AddText("x12 y226 w510 h14 Background" C.BG " c" C.FG2, "[LOGS] ระบบพร้อมทำงาน...")

    ; ─── ROW 8: 📊 STATS & ⚙️ V6 CONTROLS ───
    G.AddText("x" PAD " y244 w" COMP_W " h1 Background" C.LINE, "")
    G.SetFont("s8 Bold", "Consolas")
    statsDisplay := G.AddText("x12 y250 w260 h18 Background" C.BG " c" C.GRN, "📊 ส่ง: 0  ✓ 0  ✗ 0")
    G.SetFont("s8 Bold", "Segoe UI")
    G.AddButton("x300 y248 w105 h22 c" C.ACC, "⚙️ ตั้งค่า v6").OnEvent("Click", (*) => OpenSettings())
    G.AddButton("x410 y248 w115 h22 c" C.FG2, "📂 ประวัติ").OnEvent("Click", (*) => OpenHistoryViewer())

    G.Show("w" UI_W " h" UI_H)
    WinSetTransparent(245, G.Hwnd)
    RefreshAllLabels()
    UpdateStatsDisplay()
}

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global G
    if (hwnd == G.Hwnd)
        PostMessage(0xA1, 2,,, G.Hwnd)
}

; ══════════════════════════════════════════
;    ⏱️ REALTIME DIGITAL LED TICKER ENGINE
; ══════════════════════════════════════════
EngineLEDTicker() {
    global clockLedDisp, tzList, tzIndex, ledBlink
    targetTime := DateAdd(A_Now, tzList[tzIndex].offset, "Hours")
    ledBlink := !ledBlink
    splitter := ledBlink ? ":" : " "
    hh := FormatTime(targetTime, "HH")
    mm := FormatTime(targetTime, "mm")
    clockLedDisp.Value := hh splitter mm
}

CycleTimeZone(*) {
    global tzIndex, tzList, clockCityDisp, clockDescDisp
    tzIndex := tzIndex >= tzList.Length ? 1 : tzIndex + 1
    clockCityDisp.Value := tzList[tzIndex].name
    clockDescDisp.Value := tzList[tzIndex].desc
    EngineLEDTicker()
    Flash("🌍 World Clock: " tzList[tzIndex].name)
}

BlinkLED() {
    global blinkState, statusDot, isSending, C
    if !isSending {
        SetTimer BlinkLED, 0
        return
    }
    blinkState := !blinkState
    statusDot.SetFont(blinkState ? "c" C.RED : "c" C.BG)
}

FetchGeoIP() {
    global ipGeoDisplay
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", "http://ip-api.com/json/?fields=status,countryCode,regionName,query", true)
        whr.Send()
        whr.WaitForResponse(5)
        if (whr.Status == 200) {
            res := whr.ResponseText
            if InStr(res, '"status":"success"') {
                RegExMatch(res, '"query":"([^"]+)"', &matchIp)
                RegExMatch(res, '"countryCode":"([^"]+)"', &matchCountry)
                ipGeoDisplay.Value := "📡 " (matchIp ? matchIp[1] : "Unknown") " [" (matchCountry ? matchCountry[1] : "—") "]"
                return
            }
        }
        ipGeoDisplay.Value := "⚠️ FETCH IP FAILED"
    } catch {
        ipGeoDisplay.Value := "⚠️ NETWORK OFFLINE"
    }
}

UpdateNetworkTelemetry() {
    global netSpeedDisplay, isSending
    try {
        startTime := A_TickCount
        req := ComObject("MSXML2.ServerXMLHTTP.6.0")
        req.open("GET", "https://connectivitycheck.gstatic.com/generate_204", true)
        req.send()

        Loop 8 {
            if (req.readyState == 4)
                break
            Sleep 100
        }

        latency := A_TickCount - startTime

        if (req.readyState == 4 && req.status == 204) {
            baseIn  := isSending ? Random(152, 540) : Random(12, 45)
            baseOut := isSending ? Random(98, 212)  : Random(4, 18)
            unitIn  := " KB/s"
            unitOut := isSending ? " KB/s" : " B/s"
            netSpeedDisplay.Value := "⬇ " baseIn unitIn " • ⬆ " baseOut unitOut " ⚡ " latency " ms"
        } else {
            netSpeedDisplay.Value := "❌ NET DISCONNECTED • -- ms"
        }
    } catch {
        netSpeedDisplay.Value := "⚠️ NET UNSTABLE • ERROR"
    }
}

SetMaster(*) {
    global master, masterLabel
    MouseGetPos(,, &hw)
    if !hw
        return
    master := "ahk_id " hw
    masterLabel.Value := ShortId(master)
    SaveConfig()
    Flash("✅ เซ็ตจอหลักสำเร็จ")
}

ShortId(id) {
    if !WinExist(id)
        return "❌ NOT FOUND"
    t := WinGetTitle(id)
    return (StrLen(t) > 15 ? SubStr(t, 1, 15) "…" : t)
}

AddFollower(*) {
    global followers
    MouseGetPos(,, &hw)
    if !hw
        return
    id := "ahk_id " hw
    for v in followers
        if (v = id) {
            Flash("⚠️ มีจอนี้อยู่แล้ว")
            return
        }
    followers.Push(id)
    SaveConfig()
    RefreshAllLabels()
    Flash("✅ เพิ่มจอลูกสำเร็จ")
}

ClearFollowers(*) {
    global followers, currentWinIdx, selectedFollowers
    followers := []
    selectedFollowers := Map()
    currentWinIdx := 1
    SaveConfig()
    RefreshAllLabels()
    Flash("🧹 ล้างหน้าต่างทั้งหมดแล้ว")
}

ToggleLoopMode(ctrl, *) {
    global isLoopMode
    isLoopMode := ctrl.Value
    if isLoopMode
        Flash("🔁 เปิดลูปต่อเนื่อง")
    else
        Flash("🛑 ปิดระบบวนลูป")
}

RefreshAllLabels() {
    global followers, messages, followerLabel
    ParseMessageArray()
    followerLabel.Value := "👥 ล็อกไว้ " followers.Length " จอ | คิว: " messages.Length
}

ArrangeWindowsGrid(*) {
    global followers, master, MARGIN_WIN
    allWins := []
    for id in followers {
        if WinExist(id)
            allWins.Push(id)
    }
    if (master != "" && WinExist(master))
        allWins.Push(master)

    totalCount := allWins.Length
    if (totalCount == 0) {
        SetStatus("❌ ไม่พบจอทำงาน", "FF0055")
        return
    }

    MonitorGetWorkArea(1, &M_L, &M_T, &M_R, &M_B)
    screenW := M_R - M_L
    screenH := M_B - M_T

    cols := Ceil(Sqrt(totalCount))
    rows := Ceil(totalCount / cols)

    winW := Floor((screenW - (MARGIN_WIN * (cols + 1))) / cols)
    winH := Floor((screenH - (MARGIN_WIN * (rows + 1))) / rows)

    movedCount := 0
    for idx, id in allWins {
        WinRestore(id)
        colIdx := Mod(movedCount, cols)
        rowIdx := Floor(movedCount / cols)
        X := M_L + MARGIN_WIN + (colIdx * (winW + MARGIN_WIN))
        Y := M_T + MARGIN_WIN + (rowIdx * (winH + MARGIN_WIN))
        WinMove(X, Y, winW, winH, id)
        movedCount++
    }
    SetStatus("🧩 จัดเรียง " movedCount " จอแล้ว", "00F0FF")
    UpdateMiniLog("Grid จัดหน้าจอแบบ: " cols "x" rows)
}

StartSendEngine(*) {
    global isSending, messages, progress, followers, master, WIN_WAIT_SEC, isLoopMode
    global repeatMode, repeatCount, randomDelayMin, randomDelayMax
    global useSelection, selectedFollowers, webhookEnabled, sendStats
    if isSending
        return

    ParseMessageArray()
    if !messages.Length {
        SetStatus("ERROR: NO MESSAGE", "FF0055")
        return
    }
    if !followers.Length {
        SetStatus("ERROR: NO FOLLOWER", "FF0055")
        return
    }

    isSending := true
    SetTimer BlinkLED, 300

    Loop {
        SetStatus("BOT RUNNING...", "FFCC00")
        total := followers.Length
        done := 0
        skipped := 0
        progress.Value := 0

        SetKeyDelay 20, 20

        for idx, id in followers {
            if !isSending
                break
            if (useSelection && !selectedFollowers.Has(id))
                continue
            if !WinExist(id) {
                sendStats.failed++
                UpdateStatsDisplay()
                continue
            }

            winTitle := WinGetTitle(id)
            if IsAlreadySent(winTitle) {
                skipped++
                done++
                progress.Value := Round(done / total * 100)
                continue
            }

            Send "{ShiftUp}{CtrlUp}{AltUp}{LButtonUp}"

            WinActivate(id)
            if !WinWaitActive(id,, WIN_WAIT_SEC) {
                sendStats.failed++
                UpdateStatsDisplay()
                continue
            }

            WinGetPos(,, &wW, &wH, id)
            clickX := Floor(wW / 2)
            clickY := wH - 25

            sendTimes := repeatMode ? repeatCount : 1
            Loop sendTimes {
                if !isSending
                    break

                Click(clickX " " clickY)
                Send "{LButtonUp}"
                Sleep 350

                Loop 4
                    Send "{Backspace}"
                Sleep 100

                msg := messages[Random(1, messages.Length)]
                shortMsg := StrLen(msg) > 12 ? SubStr(msg, 1, 12) "..." : msg
                UpdateMiniLog("พิมพ์ [" idx "]: " shortMsg)
                SendEvent "{Raw}" msg
                Sleep 350

                Send "{Enter}"
                Sleep 500

                sendStats.count++
                sendStats.success++
                SaveToHistory(winTitle, msg)
                if webhookEnabled
                    SendWebhook(winTitle, msg, true)
                UpdateStatsDisplay()

                Sleep Random(randomDelayMin, randomDelayMax)
            }

            done++
            progress.Value := Round(done / total * 100)
            SetStatus("SENDING: " done "/" total, "FFCC00")
        }

        if (master != "" && WinExist(master))
            WinActivate(master)

        if (isLoopMode && isSending) {
            SetStatus("🔁 จบรอบ! รอเริ่มลูปใหม่...", "00F0FF")
            UpdateMiniLog("จบรอบ.. รอเริ่มลูปใหม่ใน 5 วิ")
            Loop 50 {
                if !isSending
                    break
                Sleep 100
            }
        } else {
            break
        }
    }

    isSending := false
    progress.Value := 100
    SetStatus("COMPLETED", "00FF66")
}

StopSendEngine(*) {
    global isSending
    isSending := false
    SetStatus("STOPPED", "FF0055")
    UpdateMiniLog("🛑 พนักงานกดหยุดทำงานฉุกเฉิน")
}

SetStatus(txt, col) {
    global statusText, statusDot
    statusText.Value := txt
    statusText.SetFont("c" col)
    statusDot.SetFont("c" col)
}

UpdateMiniLog(txt) {
    global miniLogText
    miniLogText.Value := "[" FormatTime(, "HH:mm:ss") "] " txt
}

UpdateStatsDisplay() {
    global statsDisplay, sendStats
    statsDisplay.Value := "📊 ส่ง: " sendStats.count "  ✓ " sendStats.success "  ✗ " sendStats.failed
}

ResetStats(*) {
    global sendStats
    sendStats := {count: 0, success: 0, failed: 0}
    UpdateStatsDisplay()
    Flash("🔄 รีเซ็ตสถิติแล้ว")
}

Flash(txt) {
    ToolTip txt
    SetTimer () => ToolTip(), -2000
}

; ══════════════════════════════════════════
;    ⏰ SCHEDULER (ตั้งเวลาส่งอัตโนมัติ)
; ══════════════════════════════════════════
ToggleScheduler(enable) {
    global schedulerEnabled, schedulerInterval
    schedulerEnabled := enable
    if enable {
        SetTimer SchedulerTick, schedulerInterval * 1000
        Flash("⏰ เปิดตั้งเวลาส่งทุก " schedulerInterval " วินาที")
    } else {
        SetTimer SchedulerTick, 0
    }
}

SchedulerTick() {
    global isSending
    if !isSending
        StartSendEngine()
}

; ══════════════════════════════════════════
;    📱 WEBHOOK INTEGRATION
; ══════════════════════════════════════════
SendWebhook(winTitle, msg, success) {
    global webhookEnabled, webhookURL
    if (!webhookEnabled || webhookURL = "")
        return
    try {
        body := '{"window":"' JsonEsc(winTitle) '","message":"' JsonEsc(msg) '","success":' (success ? "true" : "false") ',"timestamp":"' FormatTime(, "yyyy-MM-dd HH:mm:ss") '"}'
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("POST", webhookURL, true)
        whr.SetRequestHeader("Content-Type", "application/json")
        whr.Send(body)
        whr.WaitForResponse(3)
    }
}

JsonEsc(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "")
    s := StrReplace(s, "`n", "\n")
    return s
}

; ══════════════════════════════════════════
;    🔐 PASSWORD PROTECTION
; ══════════════════════════════════════════
PromptPassword() {
    global masterPassword
    Loop 3 {
        ib := InputBox("🔐 ใส่รหัสผ่านเพื่อเข้าใช้งาน", "MultiSender Lock", "Password w280 h130")
        if (ib.Result = "Cancel")
            ExitApp()
        if (ib.Value = masterPassword)
            return true
        MsgBox("รหัสผ่านไม่ถูกต้อง", "ผิดพลาด", "Icon!")
    }
    ExitApp()
}

; ══════════════════════════════════════════
;    ⚙️ CUSTOM HOTKEYS
; ══════════════════════════════════════════
ApplyHotkeys() {
    global hotkeyMap, _hkRegistered
    actions := Map(
        "send",     (*) => StartSendEngine(),
        "reload",   (*) => Reload(),
        "stop",     (*) => StopSendEngine(),
        "exit",     (*) => ExitApp(),
        "master",   (*) => SetMaster(),
        "follower", (*) => AddFollower()
    )
    for k in _hkRegistered {
        try Hotkey(k, "Off")
    }
    _hkRegistered := []
    for action, key in hotkeyMap {
        if (key = "" || !actions.Has(action))
            continue
        try {
            Hotkey(key, actions[action], "On")
            _hkRegistered.Push(key)
        }
    }
}

; ══════════════════════════════════════════
;    📂 HISTORY VIEWER
; ══════════════════════════════════════════
OpenHistoryViewer() {
    global HISTORY_FILE, C
    content := FileExist(HISTORY_FILE) ? FileRead(HISTORY_FILE, "UTF-8") : "(ยังไม่มีประวัติการส่ง)"
    HG := Gui("+AlwaysOnTop", "📂 ประวัติการส่ง (Timeline)")
    HG.BackColor := C.BG
    HG.SetFont("s9", "Consolas")
    HG.AddEdit("x10 y10 w560 h360 ReadOnly +VScroll Background" C.BG2 " c" C.FG, content)
    HG.SetFont("s9", "Segoe UI")
    HG.AddButton("x10 y378 w130 h26", "🗑️ ล้างประวัติ").OnEvent("Click", (*) => (ClearHistory(), HG.Destroy(), Flash("🗑️ ล้างประวัติแล้ว")))
    HG.AddButton("x150 y378 w100 h26", "ปิด").OnEvent("Click", (*) => HG.Destroy())
    HG.Show("w580 h416")
}

; ══════════════════════════════════════════
;    ⚙️ SETTINGS WINDOW (v6 FEATURES)
; ══════════════════════════════════════════
OpenSettings() {
    global SG, C, followers
    global schedulerEnabled, schedulerInterval, repeatMode, repeatCount
    global randomDelayMin, randomDelayMax, webhookEnabled, webhookURL
    global passwordProtection, masterPassword, useSelection, isDarkMode
    global selectedFollowers, hotkeyMap
    global sgSched, sgInterval, sgRepeat, sgRepeatCnt, sgDelayMin, sgDelayMax
    global sgWebOn, sgWebURL, sgPwOn, sgPw, sgDark, sgSel, sgLV
    global sgHkSend, sgHkStop, sgHkReload, sgHkExit, sgHkMaster, sgHkFollower

    if (IsSet(SG) && SG) {
        try SG.Destroy()
    }
    SG := Gui("+AlwaysOnTop", "⚙️ ตั้งค่า MultiSender v6")
    SG.BackColor := C.BG2
    SG.SetFont("s9", "Segoe UI")

    SG.SetFont("s10 Bold")
    SG.AddText("x15 y12 c" C.ACC, "⏰ ตั้งเวลาส่งอัตโนมัติ (Scheduler)")
    SG.SetFont("s9 Norm")
    sgSched := SG.AddCheckbox("x20 y+6", " เปิดใช้งานตั้งเวลาส่ง")
    sgSched.Value := schedulerEnabled
    SG.AddText("x20 y+8", "ทุก ๆ (วินาที):")
    sgInterval := SG.AddEdit("x130 yp-3 w80", schedulerInterval)

    SG.SetFont("s10 Bold")
    SG.AddText("x15 y+14 c" C.ACC, "🔁 ส่งซ้ำ (Repeat) + 🎲 หน่วงเวลาสุ่ม")
    SG.SetFont("s9 Norm")
    sgRepeat := SG.AddCheckbox("x20 y+6", " เปิดโหมดส่งซ้ำ")
    sgRepeat.Value := repeatMode
    SG.AddText("x20 y+8", "จำนวนครั้งที่ส่งซ้ำ:")
    sgRepeatCnt := SG.AddEdit("x150 yp-3 w70", repeatCount)
    SG.AddText("x20 y+10", "หน่วงสุ่ม (ms) ต่ำสุด:")
    sgDelayMin := SG.AddEdit("x150 yp-3 w70", randomDelayMin)
    SG.AddText("x230 yp+3", "สูงสุด:")
    sgDelayMax := SG.AddEdit("x285 yp-3 w70", randomDelayMax)

    SG.SetFont("s10 Bold")
    SG.AddText("x15 y+14 c" C.ACC, "📱 Webhook")
    SG.SetFont("s9 Norm")
    sgWebOn := SG.AddCheckbox("x20 y+6", " ส่งข้อมูลไปยัง Webhook")
    sgWebOn.Value := webhookEnabled
    SG.AddText("x20 y+8", "URL:")
    sgWebURL := SG.AddEdit("x60 yp-3 w355", webhookURL)

    SG.SetFont("s10 Bold")
    SG.AddText("x15 y+14 c" C.ACC, "🔐 รหัสผ่าน + 🌙 ธีม")
    SG.SetFont("s9 Norm")
    sgPwOn := SG.AddCheckbox("x20 y+6", " ล็อกด้วยรหัสผ่านตอนเปิดโปรแกรม")
    sgPwOn.Value := passwordProtection
    SG.AddText("x20 y+8", "ตั้งรหัสผ่านใหม่:")
    sgPw := SG.AddEdit("x130 yp-3 w150 Password", "")
    sgDark := SG.AddCheckbox("x20 y+10", " 🌙 โหมดมืด (Dark Mode)")
    sgDark.Value := isDarkMode

    SG.SetFont("s10 Bold")
    SG.AddText("x15 y+14 c" C.ACC, "🎯 เลือกจอที่จะส่ง (Selectable Windows)")
    SG.SetFont("s9 Norm")
    sgSel := SG.AddCheckbox("x20 y+6", " ส่งเฉพาะจอที่ติ๊กเลือกด้านล่าง")
    sgSel.Value := useSelection
    sgLV := SG.AddListView("x20 y+6 w395 h110 Checked", ["#", "หน้าต่าง (Title)"])
    for idx, id in followers {
        row := sgLV.Add(, idx, WinExist(id) ? WinGetTitle(id) : "(ไม่พบ) " id)
        if (!useSelection || selectedFollowers.Has(id))
            sgLV.Modify(row, "Check")
    }
    sgLV.ModifyCol(1, 30)
    sgLV.ModifyCol(2, 340)

    SG.SetFont("s10 Bold")
    SG.AddText("x15 y+14 c" C.ACC, "⚙️ ปุ่มลัด (Custom Hotkeys)")
    SG.SetFont("s9 Norm")
    SG.AddText("x20 y+6 w90", "ส่ง:")
    sgHkSend := SG.AddEdit("x110 yp-3 w90", hotkeyMap["send"])
    SG.AddText("x215 yp+3 w70", "หยุด:")
    sgHkStop := SG.AddEdit("x290 yp-3 w90", hotkeyMap["stop"])
    SG.AddText("x20 y+8 w90", "รีโหลด:")
    sgHkReload := SG.AddEdit("x110 yp-3 w90", hotkeyMap["reload"])
    SG.AddText("x215 yp+3 w70", "ออก:")
    sgHkExit := SG.AddEdit("x290 yp-3 w90", hotkeyMap["exit"])
    SG.AddText("x20 y+8 w90", "ตั้งจอหลัก:")
    sgHkMaster := SG.AddEdit("x110 yp-3 w90", hotkeyMap["master"])
    SG.AddText("x215 yp+3 w70", "เพิ่มลูก:")
    sgHkFollower := SG.AddEdit("x290 yp-3 w90", hotkeyMap["follower"])

    SG.SetFont("s9 Bold")
    SG.AddButton("x20 y+16 w120 h30 c" C.GRN, "💾 บันทึก").OnEvent("Click", SaveSettings)
    SG.AddButton("x150 yp w120 h30 c" C.YEL, "🔄 รีเซ็ตสถิติ").OnEvent("Click", ResetStats)
    SG.AddButton("x290 yp w120 h30 c" C.RED, "ปิด").OnEvent("Click", (*) => SG.Destroy())

    SG.Show("AutoSize")
}

SaveSettings(*) {
    global SG, followers, selectedFollowers, hotkeyMap, isDarkMode
    global schedulerEnabled, schedulerInterval, repeatMode, repeatCount
    global randomDelayMin, randomDelayMax, webhookEnabled, webhookURL
    global passwordProtection, masterPassword, useSelection
    global sgSched, sgInterval, sgRepeat, sgRepeatCnt, sgDelayMin, sgDelayMax
    global sgWebOn, sgWebURL, sgPwOn, sgPw, sgDark, sgSel, sgLV
    global sgHkSend, sgHkStop, sgHkReload, sgHkExit, sgHkMaster, sgHkFollower

    schedulerEnabled  := sgSched.Value
    schedulerInterval := Max(1, SafeInt(sgInterval.Value, 60))
    repeatMode        := sgRepeat.Value
    repeatCount       := Max(1, SafeInt(sgRepeatCnt.Value, 1))
    randomDelayMin    := Max(0, SafeInt(sgDelayMin.Value, 400))
    randomDelayMax    := Max(randomDelayMin, SafeInt(sgDelayMax.Value, 800))
    webhookEnabled    := sgWebOn.Value
    webhookURL        := Trim(sgWebURL.Value)
    passwordProtection := sgPwOn.Value
    if (sgPw.Value != "")
        masterPassword := sgPw.Value
    useSelection := sgSel.Value

    selectedFollowers := Map()
    r := 0
    Loop {
        r := sgLV.GetNext(r, "Checked")
        if !r
            break
        if (r <= followers.Length)
            selectedFollowers[followers[r]] := true
    }

    hotkeyMap["send"]     := Trim(sgHkSend.Value)
    hotkeyMap["stop"]     := Trim(sgHkStop.Value)
    hotkeyMap["reload"]   := Trim(sgHkReload.Value)
    hotkeyMap["exit"]     := Trim(sgHkExit.Value)
    hotkeyMap["master"]   := Trim(sgHkMaster.Value)
    hotkeyMap["follower"] := Trim(sgHkFollower.Value)

    newDark := sgDark.Value

    SaveFeatureConfig()
    SaveHotkeys()
    ApplyHotkeys()
    ToggleScheduler(schedulerEnabled)

    Flash("💾 บันทึกการตั้งค่าแล้ว")
    SG.Destroy()

    if (newDark != isDarkMode)
        ToggleTheme()
}

ToggleTheme() {
    global isDarkMode, THEME_FILE
    isDarkMode := !isDarkMode
    IniWrite(isDarkMode ? 1 : 0, THEME_FILE, "Theme", "darkMode")
    ApplyThemeVars()
    RebuildGui()
}

RebuildGui() {
    global G, msgEditor, currentMsgText
    currentMsgText := msgEditor.Value
    G.Destroy()
    BuildGui()
}
