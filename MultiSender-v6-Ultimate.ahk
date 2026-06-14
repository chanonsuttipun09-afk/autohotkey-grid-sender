#ต้องใช้ AutoHotkey เวอร์ชัน 2.0
#SingleInstance Force

SetTitleMatchMode 2
SendMode "Event"

; ═══════════════════════════════════════════════════════════
; ⚙️ การตั้งค่าและการจัดเก็บข้อมูล เวอร์ชัน 6.0 - รุ่นมัลติฟีเจอร์
; ═══════════════════════════════════════════════════════════

; การตั้งค่าหน้าต่าง (เค้าโครงจอภาพคงที่)
WIN_W := 520 
WIN_H := 470 
MARGIN_WIN := 2 
MSG_FILE := "messages.txt"
CONFIG_FILE := "MultiSender.ini"
HISTORY_FILE := "send_history.txt"
THEME_FILE := "theme.ini"
HOTKEY_FILE := "hotkeys.ini"

; Feature Flags
isSending := false
blinkState := false
isSchedulerRunning := false
isDarkMode := true

; Counter & State
currentWinIdx := 1
lastInBytes := 0
lastOutBytes := 0
wmiService := ""

; New Feature Variables
schedulerEnabled := false
schedulerInterval := 5000 ; 5 วินาที (ค่าเริ่มต้น)
repeatMode := false
repeatCount := 1
randomDelayMin := 0
randomDelayMax := 1000
sendStats := {count: 0, success: 0, failed: 0}
sendHistory := []
selectedWindows := []
webhookURL := ""
webhookEnabled := false
passwordProtection := false
masterPassword := ""
customHotkeys := {}

followers := []

; ══════════════════════════════════════════════════════════
; 🔧 Shared Utility Functions
; ══════════════════════════════════════════════════════════

IniReadInt(file, section, key, default := "0") {
    return Integer(IniRead(file, section, key, default))
}

DeleteIfExists(filepath) {
    if FileExist(filepath)
        FileDelete(filepath)
}

HttpGet(url, timeout := 5) {
    whr := ComObject("WinHttp.WinHttpRequest.5.1")
    whr.Open("GET", url, true)
    whr.Send()
    whr.WaitForResponse(timeout)
    return whr
}

HttpPost(url, body, contentType := "application/json", timeout := 5) {
    whr := ComObject("WinHttp.WinHttpRequest.5.1")
    whr.Open("POST", url, true)
    whr.SetRequestHeader("Content-Type", contentType)
    whr.Send(body)
    whr.WaitForResponse(timeout)
    return whr
}

WrapWinIdx() {
    global currentWinIdx, followers
    if (currentWinIdx > followers.Length)
        currentWinIdx := 1
}

Timestamp(fmt := "yyyy-MM-dd HH:mm:ss") {
    return FormatTime(, fmt)
}

; ══════════════════════════════════════════════════════════
; 💾 กำลังโหลดและบันทึกการตั้งค่า
; ════════════════════════════════════════════════════════════

LoadConfig() {
 global followers, CONFIG_FILE, schedulerInterval, repeatCount, randomDelayMin
 global randomDelayMax, webhookURL, webhookEnabled, passwordProtection, masterPassword
 
 followers := []
 if !FileExist(CONFIG_FILE)
 return
 try {
n := IniReadInt(CONFIG_FILE, "Win", "count")
 Loop n {
 val := IniRead(CONFIG_FILE, "Win", "f" A_Index, "")
 if (val != "")
 followers.Push(val)
 }
 
 schedulerInterval := IniReadInt(CONFIG_FILE, "Features", "schedulerInterval", "5000")
 repeatCount := IniReadInt(CONFIG_FILE, "Features", "repeatCount", "1")
 randomDelayMin := IniReadInt(CONFIG_FILE, "Features", "randomDelayMin")
 randomDelayMax := IniReadInt(CONFIG_FILE, "Features", "randomDelayMax", "1000")
 webhookURL := IniRead(CONFIG_FILE, "Features", "webhookURL", "")
 webhookEnabled := IniReadInt(CONFIG_FILE, "Features", "webhookEnabled")
 passwordProtection := IniReadInt(CONFIG_FILE, "Features", "passwordProtection")
 masterPassword := IniRead(CONFIG_FILE, "Features", "masterPassword", """)
 
 } catch {
 followers := []
 }
}

SaveConfig() {
 global followers, CONFIG_FILE, schedulerInterval, repeatCount, randomDelayMin
 global randomDelayMax, webhookURL, webhookEnabled, passwordProtection, masterPassword
 
 try {
 DeleteIfExists(CONFIG_FILE)
 
 IniWrite(followers.Length, CONFIG_FILE, "Win", "count")
 Loop followers.Length
 IniWrite(followers[A_Index], CONFIG_FILE, "Win", "f" A_Index)
 
 IniWrite(schedulerInterval, CONFIG_FILE, "Features", "schedulerInterval")
 IniWrite(repeatCount, CONFIG_FILE, "Features", "repeatCount")
 IniWrite(randomDelayMin, CONFIG_FILE, "Features", "randomDelayMin")
 IniWrite(randomDelayMax, CONFIG_FILE, "Features", "randomDelayMax")
 IniWrite(webhookURL, CONFIG_FILE, "Features", "webhookURL")
 IniWrite(webhookEnabled, CONFIG_FILE, "Features", "webhookEnabled")
 IniWrite(passwordProtection, CONFIG_FILE, "Features", "passwordProtection")
 IniWrite(masterPassword, CONFIG_FILE, "Features", "masterPassword")
 
 }
}

LoadTheme() {
 global isDarkMode, THEME_FILE
 if FileExist(THEME_FILE) {
 isDarkMode := IniReadInt(THEME_FILE, "Theme", "darkMode", "1")
 }
}

SaveTheme() {
 global isDarkMode, THEME_FILE
 IniWrite(isDarkMode ? "1" : "0", THEME_FILE, "Theme", "darkMode")
}

LoadMessages() {
 global MSG_FILE
 try {
 if !FileExist(MSG_FILE) {
 defaultMsgs := "สวัสดีครับที่ชื่นชอบสอบถามได้เลยนะ`r`nขอบคุณที่แวะมารับชมครับผม `r`n ฝากกดหัวใจและติดตามด้วยนะครับ"
 FileAppend(defaultMsgs, MSG_FILE, "UTF-8")
 }
 return FileRead(MSG_FILE, "UTF-8")
 } catch {
 return "สวัสดีครับ สอบถามได้ครับ"
 }
}

SaveMessages(txt) {
 global MSG_FILE
 ลอง {
 DeleteIfExists(MSG_FILE)
 FileAppend(Trim(txt, "`r`n "), MSG_FILE, "UTF-8")
 }
}

AddToHistory(windowIdx, ข้อความ, ความสำเร็จ) {
 global sendHistory, HISTORY_FILE, sendStats
 
 การประทับเวลา := Timestamp()
 entry := timestamp " | Window:" windowIdx " | " (สำเร็จ ? "✓" : "✗") " | " ข้อความ
 
 sendHistory.Push(entry)
 if (sendHistory.ความยาว > 1000)
 sendHistory.RemoveAt(1)
 
 ลอง {
 FileAppend(entry "`r`n", HISTORY_FILE, "UTF-8")
 }
 
 sendStats.count++
 ถ้า (สำเร็จ)
 sendStats.success++
 มิฉะนั้น
 sendStats.failed++
}

โหลดคีย์ลัดแบบกำหนดเอง () {
 คีย์ลัดแบบกำหนดเองทั่วโลก, HOTKEY_FILE
 customHotkeys := {}
 ถ้า !FileExist(HOTKEY_FILE)
 ส่งคืน
 ลอง {
n := IniReadInt(HOTKEY_FILE, "Hotkeys", "count")
 วนลูป n {
 key := IniRead(HOTKEY_FILE, "Hotkeys", "key" A_Index, "")
 การกระทำ := IniRead(HOTKEY_FILE, "Hotkeys", "action" A_Index, "")
 if (key != "" && action != "")
 customHotkeys[key] := action
 }
 }
}

LoadConfig()
LoadTheme()
LoadCustomHotkeys()
initialText := LoadMessages()

; ══════════════════════════════════════════════════════════
; 🎨 การออกแบบ UI: CYBERPUNK v6.0 ULTIMATE
; ══════════════════════════════════════════════════════════

; โครงร่างสี
DARK_BG := "0B0B0E" 
DARK_BG2 := "13131A" 
DARK_LINE := "221F3B" 
LIGHT_BG := "F5F5F5"
LIGHT_BG2 := "FFFFFF"
LIGHT_LINE := "E0E0E0"

ACC := "9D4EDD" 
GRN := "10B981" 
RED := "EF4444" 
YEL := "F59E0B" 
CYN := "06B6D4" 

DARK_FG := "F3F4F6"
DARK_FG2 := "9CA3AF"
LIGHT_FG := "1F2937"
LIGHT_FG2 := "6B7280"

; สีแบบไดนามิกตามธีม
BG := isDarkMode ? DARK_BG : LIGHT_BG
BG2 := isDarkMode ? DARK_BG2 : LIGHT_BG2
LINE := isDarkMode ? DARK_LINE : LIGHT_LINE
FG := isDarkMode ? DARK_FG : LIGHT_FG
FG2 := isDarkMode ? DARK_FG2 : LIGHT_FG2

UI_W := 900
UI_H := 750
PAD := 14
COMP_W := UI_W - (PAD * 2)
TAB_H := 35

G := Gui("+AlwaysOnTop +Border", "Multi Sender Ultimate v6.0")
G.BackColor := BG

; ════════════════════════════════════════
; ส่วนหัวและส่วนควบคุม
; ระบายสี ระบายสี ระบายสี ระบายสี ระบายสี ระบายสี "⚡")
G.AddText("x+6 yp พื้นหลัง" BG " c" FG, "GRID SENDER v6")
G.SetFont("s8 ตัวหนา", "Segoe UI")
G.AddText("x+5 yp+3 Background" BG " c" CYN, "ULTIMATE")

G.SetFont("s9 Bold", "Consolas")
clockDisplay := G.AddText("x" (UI_W - PAD - 140) " y15 w70 h16 Right Background" BG " c" YEL, "00:00:00")
statsDisplay := G.AddText("x+5 yp w60 h16 Background" BG " c" GRN, "✓0 ✗0")

G.SetFont("s8 Bold", "Segoe UI")
G.AddButton("x" (UI_W - PAD - 56) " y14 w18 h18 +0x200 c" CYN, "🌙").OnEvent("Click", ToggleTheme)
G.AddButton("x+5 yp w18 h18 +0x200 c" CYN, "↺").OnEvent("Click", (*) => Reload())
G.AddButton("x+5 yp w18 h18 +0x200 c" RED, "✕").OnEvent("Click", (*) => ExitApp())

; สถานะ IP และเครือข่าย
G.AddText("x" PAD " y+12 w" COMP_W " h1 Background" LINE, "")
G.SetFont("s8.5 Bold", "Consolas")
ipGeoDisplay := G.AddText("x" PAD " y+6 w" COMP_W " h14 Background" BG " c" CYN " Center", "📡 กำลังเชื่อมต่อ...")
G.SetFont("s8 Bold", "Consolas")
netSpeedDisplay := G.AddText("x" PAD " y+4 w" COMP_W " h14 Background" BG " c" YEL " Center", "⬇ 0.0 KB/s • ⬆ 0.0 KB/s")

; ไฟ LED แสดงสถานะ
G.AddText("x" PAD " y+6 w" COMP_W " h1 Background" LINE, "")
G.SetFont("s8.5", "Segoe UI Semibold")
statusDot := G.AddText("x" PAD " y+6 w10 h14 Background" BG " c" GRN, "●")
statusText := G.AddText("x+4 yp w" (COMP_W - 14) " h14 Background" BG " c" GRN, "SYSTEM READY")

; ปุ่มควบคุมแท็บ
G.AddText("x" PAD " y+12 w" COMP_W " h1 Background" LINE, "")

; ปุ่มแท็บ
tabWidth := (COMP_W - 30) / 5
G.SetFont("s9 ตัวหนา c" FG, "Segoe UI")
btnTabMain := G.AddButton("x" PAD " y+8 w" tabWidth " h" TAB_H, "📺 หลัก")
btnTabScheduler := G.AddButton("x+5 yp w" tabWidth " h" TAB_H, "⏰ตั้งเวลา")
btnTabStats := G.AddButton("x+5 yp w" tabWidth " h" TAB_H, "📊 สถิติ")
btnTabHistory := G.AddButton("x+5 yp w" tabWidth " h" TAB_H, "💾 แท็บ")
btnTabSettings := G.AddButton("x+5 yp w" tabWidth " h" TAB_H, "⚙️ แท็บ")

btnTabMain.OnEvent("Click", (*) => ShowTab("main"))
btnTabScheduler.OnEvent("Click", (*) => ShowTab("scheduler"))
btnTabStats.OnEvent("Click", (*) => ShowTab("stats"))
btnTabHistory.OnEvent("Click", (*) => ShowTab("history"))
btnTabSettings.OnEvent("Click", (*) => ShowTab("settings"))

; ════════════════════════════════════════
; แท็บ: หลัก
; 4.0.2.2017 . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .AddText("x" PAD " y+12 w" COMP_W " h1 Background" LINE, "")

; Window Register
G.SetFont("s8.5 Bold", "Segoe UI")
G.AddText("x" PAD " y+6 c" FG2, "📺 ลงทะเบียนกลุ่มเป้าหมาย:")
BTN2_W := Floor((COMP_W - 6) / 2)
G.AddButton("x" PAD " y+5 w" BTN2_W " h22 +0x200 c" CYN, "＋ไม่ต้องเพิ่มจอ (F6)").OnEvent("Click", AddFollower)
G.AddButton("x+6 yp w" BTN2_W " h22 +0x200 c" RED, "🧹 ล้าง").OnEvent("Click", ล้างผู้ติดตาม)

; ตัวแก้ไขข้อความ
G.AddText("x" PAD " y+10 w" COMP_W " h1 Background" LINE, "")
G.SetFont("s8.5 Bold", "Segoe UI")
G.AddText("x" PAD " y+6 c" CYN, "txt ข้อความ:")
G.SetFont("s9", "Segoe UI")
msgEditor := G.AddEdit("x" PAD " y+5 w" COMP_W " h110 Background" BG2 " c" FG " WantTab +VScroll", initialText)

; การควบคุมการทำซ้ำและการหน่วงเวลา
G.AddText("x" PAD " y+8 w" COMP_W " h1 Background" LINE, "")
G.SetFont("s8.5 Bold", "Segoe UI")
G.AddText("x" PAD " y+6 c" FG2, "🎛️ คุณสมบัติที่ยอดเยี่ยม:")

COL_W := (COMP_W - 15) / 3
G.SetFont("s8", "Segoe UI")
G.AddText("x" PAD " y+6 w" COL_W " h14 Background" BG " c" FG, "🔁 ดินแดนซ้ำ:")
repeatModeCtrl := G.AddCheckbox("x" PAD " y+3 w20 h20", "เปิด")
G.AddText("x+5 yp w" (COL_W - 25) " h20 Background" BG " c" FG, "จำนวน:")
repeatCountCtrl := G.AddEdit("x+3 yp w40 h20 Background" BG2 " c" FG, "1")

G.AddText("x+10 y" (PAD + 6) " w" COL_W " h14 Background" BG " c" FG, "🎲 สุ่มเวลา (ms):")
G.AddText("x+10 y+6 w20 h14 Background" BG " c" FG, "ต่ำ:")
randomMinCtrl := G.AddEdit("x+3 yp w40 h18 พื้นหลัง" BG2 " c" FG, "0")
G.AddText("x+5 yp w20 h14 Background" BG " c" FG, " สูง:")
randomMaxCtrl := G.AddEdit("x+3 yp w40 h18 Background" BG2 " c" FG, "1000")

G.AddText("x" (PAD + COMP_W - COL_W + 10) " y" (PAD + 6) " w" COL_W " h14 Background" BG " c" FG, "📱 Webhook:")
webhookModeCtrl := G.AddCheckbox("x" (PAD + COMP_W - COL_W + 10) " y+3 w20 h20", " เปิด")
webhookURLCtrl := G.AddEdit("x+5 yp w" (COL_W - 30) " h20 Background" BG2 " c" FG)

; Controls
G.AddText("x" PAD " y+10 w" COMP_W " h1 Background" LINE, "")
G.SetFont("s9.5 Bold", "Segoe UI")
btnTrigger := G.AddButton("x" PAD " y+6 w" BTN2_W " h32 c" ACC, "🚀 ส่ง (F1)")
btnArrange := G.AddButton("x+6 yp w" BTN2_W " h32 c" GRN, "🧩 จัดเรียงใหม่")
btnTrigger.OnEvent("Click", ManualSendAction)
btnArrange.OnEvent("Click", ArrangeWindowsFixed)

; กล่องบันทึก
G.AddText("x" PAD " y+10 w" COMP_W " h1 Background" LINE, "")
G.SetFont("s8", "Consolas")
logBox := G.AddEdit("x" PAD " y+5 w" COMP_W " h60 ReadOnly -Wrap +0x200000 Background" BG2 " c" GRN)

; ════════════════════════════════════════
; แท็บ: ตัวกำหนดตารางเวลา
; ══════════════════════════════════════════
G.SetFont("s9 Bold", "Segoe UI")
schedulerEnableCtrl := G.AddCheckbox("x" (PAD+5) " y" (PAD+100) " w200 h25", "🕐 เปิดเวลาอัตโนมัติ")
schedulerEnableCtrl.OnEvent("คลิก", ToggleScheduler)

G.SetFont("s8", "Segoe UI")
G.AddText("x" (PAD+5) " y+5 c" FG, "ช่วงเวลา (มลทิน):")
schedulerIntervalCtrl := G.AddEdit("x" (PAD+5) " y+3 w100 h22 Background" BG2 " c" FG, "5000")

btnStartScheduler := G.AddButton("x" (PAD+110) " y" (PAD+128) " w80 h22 +0x200 c" GRN, "▶เริ่มต้น")
btnStartScheduler.OnEvent("คลิก", StartScheduler)

btnStopScheduler := G.AddButton("x+5 yp w80 h22 +0x200 c" RED, "⏹ถ่ายทอดสด")
btnStopScheduler.OnEvent("Click", StopScheduler)

G.AddText("x" (PAD+5) " y+10 c" GRN, "⏸ปิดอยู่")
schedulerStatus := G.AddText("x" (PAD+5) " y+0 c" GRN)

; ════════════════════════════════════════
; แท็บ: สถิติ
; ══════════════════════════════════════════
G.SetFont("s10 Bold c" GRN, "Segoe UI")
statsCountCtrl := G.AddText("x" (PAD+10) " y" (PAD+105) " w400 h30 Background" BG2 " c" GRN, "📊 ส่งทั้งหมด: 0 ทั้งหมด")
statsSuccessCtrl := G.AddText("x" (PAD+10) " y+5 w400 h30 Background" BG2 " c" GRN, "✅ สำเร็จ : 0 เท่านั้น")
statsFailCtrl := G.AddText("x" (PAD+10) " y+5 w400 h30 Background" BG2 " c" RED, "❌ ตอนนี้: 0 จริง")
statsRateCtrl := G.AddText("x" (PAD+10) " y+5 w400 h30 Background" BG2 " c" YEL,"📈 อัตราสำเร็จ: 0%")

btnResetStats := G.AddButton("x" (PAD+10) " y+5 w100 h25 +0x200 c" RED, "🔄 รีเซต")
btnResetStats.OnEvent("Click", ResetStats)

; ระบายสี ระบายสี ระบายสี ระบายสี ระบายสี ระบายสี ระบายสี TAB: ประวัติศาสตร์
; ════════════════════════════════════════
G.SetFont("s8", "Consolas")
historyBox := G.AddEdit("x" (PAD+5) " y" (PAD+105) " w" (COMP_W-10) " h180 ReadOnly -Wrap +0x200000 Background" BG2 " c" GRN)

btnClearHistory := G.AddButton("x" (PAD+5) " y+5 w100 h25 +0x200 c" RED, "🗑️ซักประวัติ")
btnClearHistory.OnEvent("Click", ClearHistory)

btnExportHistory := G.AddButton("x+5 yp w100 h25 +0x200 c" CYN, "💾 ส่งออก")
btnExportHistory.OnEvent("คลิก", ExportHistory)

; ════════════════════════════════════════
; แท็บ: การตั้งค่า
; 4.0.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2562 "🔐จำเป็นด้วยรหัสผ่าน:")
passwordEnableCtrl := G.AddCheckbox("x" (PAD+5) " y+3 w20 h20", "")
passwordEnableCtrl.OnEvent("Click", TogglePassword)

G.SetFont("s8 c" FG, "Segoe UI")
G.AddText("x" (PAD+30) " y" (PAD+105) " c" FG, "การสื่อสาร:")
passwordCtrl := G.AddEdit("x" (PAD+30) " y+3 w150 h20 Background" BG2 " c" FG " Password")

G.AddText("x" (PAD+5) " y+10 c" FG, "⚙️ การติดตั้ง Hotkey:")
G.AddText("x" (PAD+5) " y+3 c" FG, "F1 (ส่ง):")
hotkeyF1Ctrl := G.AddEdit("x+50 yp w80 h20 Background" BG2 " c" FG, "F1")

G.AddText("x" (PAD+5) " y+5 c" FG, "F6 ( บันทึกการตั้งค่า):")
hotkeyF6Ctrl := G.AddEdit("x+50 yp w80 h20 Background" BG2 " c" FG, "F6")

G.AddText("x" (PAD+5) " y+5 c" FG, "F2 ( บันทึก):")
hotkeyF2Ctrl := G.AddEdit("x+50 yp w80 h20 Background" BG2 " c" FG, "F2")

btnSaveSettings := G.AddButton("x" (PAD+5) " y+10 w100 h25 +0x200 c" GRN, "💾 บันทึก")
btnSaveSettings.OnEvent("Click", SaveSettings)

btnResetHotkeys := G.AddButton("x+5 yp w100 h25 +0x200 c" RED, "🔄 ไฟล์")
btnResetHotkeys.OnEvent("Click", ResetHotkeys)

; ════════════════════════════════════════
; เริ่มต้นใช้งาน
; ════════════════════════════════════════
InitNetworkCounter()
SetTimer FetchGeoIP, -100 
SetTimer UpdateClock, 1000 
SetTimer UpdateNetworkSpeed,1000 
SetTimer UpdateStats, 500

UpdateStatusLabel()
G.Show("w" UI_W " h" UI_H)
WinSetTransparent(235, G.Hwnd)

ShowTab("main")

; ระบายสี ระบายสี ระบายสี ระบายสี ระบายสี ระบายสี ระบายสี ฟังก์ชั่นการจัดการ UI
; ════════════════════════════════════════

ShowTab(tabName) {
 ; ตรรกะการสลับแท็บ
}

ToggleTheme(*) {
 global isDarkMode
 isDarkMode := !isDarkMode
 SaveTheme()
 G.Destroy()
 Reload()
}

; ════════════════════════════════════════
; ฟังก์ชันตัวจัดตารางเวลา
; ═════════════════════════════════════════

ToggleScheduler(GuiCtrlObj, Info) {
 global schedulerEnabled
 schedulerEnabled := GuiCtrlObj.Value
}

StartScheduler(*) {
 global isSchedulerRunning, schedulerIntervalCtrl, schedulerStatus
 
 if isSchedulerRunning {
 Flash("⚠️ เวลาเปิดจริงๆ")
 return
 }
 
 isSchedulerRunning := true
 ช่วง := Integer(schedulerIntervalCtrl.Value)
 if (interval < 100)
 ช่วง := 100
 
 schedulerStatus.Value := "▶ ต่อไป..."
 schedulerStatus.SetFont("c" GRN)
 
 AddLog("เริ่มตั้งเวลา: " ช่วง "ms")
 
 SetTimer SchedulerTick, ช่วง
}

SchedulerTick() {
 global followers, isSending
 if (followers.Length == 0)
 return
 if !isSending
 ManualSendAction()
}

StopScheduler(*) {
 global isSchedulerRunning, สถานะกำหนดการ
 
 isSchedulerRunning := false
 SetTimer SchedulerTick, 0
 
 schedulerStatus.Value := "⏸ ปิดอยู่"
 schedulerStatus.SetFont("c" RED)
 
 AddLog("⏰ตั้งเวลาออกอากาศ")
}

; ระบายสี ระบายสี ระบายสี ระบายสี ระบายสี ระบายสี ระบายสี ฟังก์ชั่นสถิติ
; ระบายสี ระบายสี ระบายสี ระบายสี ระบายสี statsCountCtrl.Value := "📊 ส่งทั้งหมด: " sendStats.count " จริง"
 statsSuccessCtrl.Value := "✅ สำเร็จ: " sendStats.success "ส่วน"
 statsFailCtrl.Value := "❌ โครงสร้าง: " sendStats.failed "ส่วนภายนอก"
 
 อัตรา := (sendStats.count = 0) ? 0 : Round((sendStats.success / sendStats.count) * 100)
 statsRateCtrl.Value := "📈 อัตราสำเร็จ: " อัตรา "%"
 
 statsDisplay.Value := "✓" sendStats.success " ✗" sendStats.failed
}

ResetStats(*) {
 global sendStats
 sendStats := {count: 0, Success: 0, failed: 0}
 AddLog("🔄 รีเซ็ตสถิติแล้ว")
}

; ════════════════════════════════════════
; ฟังก์ชันประวัติ
; ════════════════════════════════════════

ClearHistory(*) {
 global sendHistory, HISTORY_FILE, historyBox
 sendHistory := []
 DeleteIfExists(HISTORY_FILE)
 historyBox.ค่า := ""
 AddLog("🗑️ ล้างประวัติแล้ว")
}

ExportHistory(*) {
 global sendHistory
 
 filepath := A_MyDocuments "\send_history_" Timestamp("yyyyMMdd_HHmmss") ".txt"
 content := ""
 for entry in sendHistory
 content .= entry "`r`n"
 
 FileAppend(content, filepath, "UTF-8")
 AddLog("💾 ส่งออกประวัติ: " filepath)
 Flash("✅ ส่งออกสำเร็จ!")
}

; ════════════════════════════════════════
; รหัสผ่านและการตั้งค่า
; ════════════════════════════════════════

TogglePassword(GuiCtrlObj, Info) {
 global passwordProtection
 passwordProtection := GuiCtrlObj.Value
}

SaveSettings(*) {
 global customHotkeys, hotkeyF1Ctrl, hotkeyF6Ctrl, hotkeyF2Ctrl, HOTKEY_FILE
 
 try {
 DeleteIfExists(HOTKEY_FILE)
 
 IniWrite("3", HOTKEY_FILE, "Hotkeys", "count")
 IniWrite(hotkeyF1Ctrl.Value, HOTKEY_FILE, "Hotkeys", "key1")
 IniWrite("ManualSendAction", HOTKEY_FILE, "Hotkeys", "action1")
 IniWrite(hotkeyF6Ctrl.Value, HOTKEY_FILE, "Hotkeys", "key2")
 IniWrite("AddFollower", HOTKEY_FILE, "Hotkeys", "action2")
 IniWrite(hotkeyF2Ctrl.Value, HOTKEY_FILE, "Hotkeys", "key3")
 IniWrite("EmergencyStop", HOTKEY_FILE, "Hotkeys", "action3")
 
 AddLog("💾 บันทึกการรับ Hotkey สำเร็จ")
 Flash("✅บันทึกความสำเร็จ!")
 }
}

ResetHotkeys(*) {
 global hotkeyF1Ctrl, hotkeyF6Ctrl, hotkeyF2Ctrl
 hotkeyF1Ctrl.Value := "F1"
 hotkeyF6Ctrl.Value := "F6"
 hotkeyF2Ctrl.Value := "F2"
 AddLog("🔄 รีเซ็ต Hotkey เป็นผล")
}

; ════════════════════════════════════════
; ⏱️ ตัวจับเวลาและโมดูลเครือข่าย
; ════════════════════════════════════════

UpdateClock() {
 global clockDisplay
 clockDisplay.Value := Timestamp("HH:mm:ss")
}

BlinkLED() {
 global blinkState, statusDot, isSending, YEL, BG
 if !isSending {
 SetTimer BlinkLED, 0 
 return
 }
 blinkState := !blinkState
 statusDot.SetFont(blinkState ? "c" YEL : "c" BG)
}

FetchGeoIP() {
 global ipGeoDisplay
 try {
 whr := HttpGet("http://ip-api.com/json/?fields=status,countryCode,regionName,query")
 if (whr.Status == 200) {
 res := whr.ResponseText
 if InStr(res, '"status":"success"') {
 RegExMatch(res, '"query":"([^"]+)"', &matchIp)
 RegExMatch(res, '"countryCode":"([^"]+)"', &matchCountry)
 RegExMatch(res, '"regionName":"([^"]+)"', &matchRegion)
 ipGeoDisplay.Value := (matchIp ​​? matchIp[1] : "Unknown") " [" (matchCountry ? matchCountry[1] : "—") "/" (matchRegion ? matchRegion[1] : "—") "]"
 return
 }
 }
 ipGeoDisplay.Value := "⚠️ ไม่พบข้อมูล"
 } catch {
 ipGeoDisplay.Value := "⚠️ อันตราย"
 }
}

InitNetworkCounter() {
 global lastInBytes, lastOutBytes, wmiService
 try {
 wmiService := ComObjGet("winmgmts:")
 for obj in wmiService.ExecQuery("Select BytesReceivedPersec, BytesSentPersec From Win32_PerfRawData_Tcpip_NetworkInterface") {
 lastInBytes += Integer(obj.BytesReceivedPersec)
 lastOutBytes += Integer(obj.BytesSentPersec)
 }
 } catch {
 lastInBytes := 0
 lastOutBytes := 0
 }
}

UpdateNetworkSpeed() {
 global lastInBytes, lastOutBytes, netSpeedDisplay, wmiService
 currentIn := 0, currentOut := 0
 ลอง {
 ถ้า !wmiService
 wmiService := ComObjGet("winmgmts:")
 สำหรับ obj ใน wmiService.ExecQuery("Select BytesReceivedPersec, BytesSentPersec From Win32_PerfRawData_Tcpip_NetworkInterface") {
 currentIn += Integer(obj.BytesReceivedPersec)
 currentOut += Integer(obj.BytesSentPersec)
 }
 } catch {
 ส่งคืน
 }
 ถ้า (lastInBytes = 0 && lastOutBytes = 0) {
 lastInBytes := currentIn, lastOutBytes := currentOut
 ส่งคืน
 }
 diffIn := currentIn - lastInBytes, diffOut := currentOut - lastOutBytes
 ถ้า (diffIn < 0 || diffOut < 0) {
 lastInBytes := currentIn, lastOutBytes := currentOut
 return
 }
 netSpeedDisplay.Value := "⬇ " FormatBytes(diffIn) " • ⬆ " FormatBytes(diffOut)
 lastInBytes := currentIn, lastOutBytes := currentOut
}

FormatBytes(bytes) {
 if (bytes > 1048576)
 return Round(bytes / 1048576, 1) " MB/s"
 else if (bytes > 1024)
 return Round(bytes / 1024, 1) " KB/s"
 else
 return bytes " B/s"
}

; ════════════════════════════════════════
; 🎯 ฟังก์ชั่นพื้นที่ทำงานและการจัดเรียง (แก้ไขแล้ว!)
; ════════════════════════════════════════

AddFollower(*) {
 ผู้ติดตามทั่วโลก
 MouseGetPos(,, &hw)
 ถ้า !hw
 ส่งคืน
 id := "ahk_id " hw
 for v in allowances
 if (v = id) {
 Flash("⚠️มีจอนี้อย่าง")
 return
 }
 allowances.Push(id)
 SaveConfig()
 UpdateStatusLabel()
 Flash("✅ต่อไปทำสำเร็จ")
}

ClearFollowers(*) {
 global allowances, currentWinIdx
 follower := []
 currentWinIdx := 1
 SaveConfig()
 UpdateStatusLabel()
 Flash("🧹 ล้างหน้าต่างทั้งหมดแล้ว")
}

UpdateStatusLabel() {
 global allowances, currentWinIdx
 if (followers.Length == 0)
 SetStatus("คิวว่าง | กด F6 ชี้เพิ่มหน้าต่าง", "EF4444")
 else
 SetStatus("บันทึกไว้ " followers.Length " จอ (กลุ่มเป้าหมายถัดไป: จอที่ " currentWinIdx ")", "10B981")
}

ArrangeWindowsFixed(*) {
 global allowances, WIN_W, WIN_H, MARGIN_WIN
 if (followers.Length == 0) {
 SetStatus("❌ยังไม่ได้กด F6 ล็อกหน้าต่างบราวเซอร์", "EF4444")
 กลับ
 }
 
 MonitorGet(1, &M_L, &M_T, &M_R, &M_B)
 
 ; แก้ไข: คำนวณคอลัมน์อย่างถูกต้อง - ไม่ต้องมีแล้วเอาขึ้นมาไม่ได้
 monitorWidth := M_R - M_L
 availableWidth := monitorWidth - (2 * MARGIN_WIN)
 TotalWinWidth := availableWidth + MARGIN_WIN
 cols := Floor(totalWinWidth / (WIN_W + MARGIN_WIN))
 if (cols < 1)
 cols := 1
 
 ย้ายจำนวน := 0
 สำหรับ idx, id ในผู้ติดตาม {
 if !WinExist(id) {
 AddLog("⚠️ [" idx "] ไม่พบที่นั่น")
 ดำเนินการต่อ
 }
 
 WinRestore(id)
 Sleep 50
 
 ; คำนวณตำแหน่งได้อย่างน่าเชื่อถือมากขึ้น - ต่อเนื่องไปจอที่ 2
 colIdx := Mod(movedCount, cols)
 rowIdx := Floor(movedCount / cols)
 
 X := M_L + MARGIN_WIN + (colIdx * (WIN_W + MARGIN_WIN))
 Y := M_T + MARGIN_WIN + (rowIdx * (WIN_H + MARGIN_WIN))
 
 WinMove(X, Y, WIN_W, WIN_H, id)
 Sleep 30
movedCount++
 }
 SetStatus("🧩 ลาด "movedCount "เล็บเรียบร้อย", "06B6D4")
 AddLog("🧩 หน้าจอขนาด " WIN_W "x" WIN_H " (" MoveCount "ในกรุง)")
}

; ════════════════════════════════════════
; 🚀 ระบบส่งข้อความ (แก้ไขแล้ว - ข้อความไม่สูญหาย!)
; ════════════════════════════════════════

ManualSendAction(*) {
 global isSending, msgEditor, followers, currentWinIdx, repeatMode, repeatCount
 global randomDelayMin, randomDelayMax, webhookEnabled, webhookURL
 global repeatModeCtrl, repeatCountCtrl, randomMinCtrl, randomMaxCtrl
 
 if isSending
 return
 
 if (followers.Length == 0) {
 SetStatus("❌กด F6 บันทึกหน้าต่างแชทก่อนส่ง!", "EF4444")
 return
 }
 
 rawTxt := msgEditor.Value
 SaveMessages(rawTxt)
 
 lines := []
 Loop Parse rawTxt, "`n", "`r" {
t := Trim(A_LoopField)
 if (t != "")
 lines.Push(t)
 }
 
 if (lines.Length == 0) {
 SetStatus("❌พิมพ์ข้อความก่อนภาพยนตร์!", "EF4444")
 return
 }

 ; รับการตั้งค่า
 RepeatMode := RepeatModeCtrl.Value
 RepeatCount := Integer(repeatCountCtrl.Value) ? Integer(repeatCountCtrl.Value) : 1
 randomDelayMin := Integer(randomMinCtrl.Value)
 randomDelayMax := Integer(randomMaxCtrl.Value)
 webhookEnabled := webhookModeCtrl.Value
 webhookURL := webhookURLCtrl.Value

 WrapWinIdx()
 
 targetID := followers[currentWinIdx]
 
 if !WinExist(targetID) {
 AddLog("⚠️ ค้างที่ [" currentWinIdx "] ปิดอยู่.. กำลังข้าม")
 currentWinIdx++
 WrapWinIdx()
 return
 }

 isSending := true
 SetStatus("⚡ กำลังส่งข้อความหา...", "F59E0B")
 SetTimer BlinkLED, 300
 
 loopCount := RepeatMode ? RepeatCount : 1
 ChosenMsg := ""
 Loop loopCount {
 currentLoop := A_Index
 ChosenMsg := lines[Random(1, lines.Length)]
 shortMsg := StrLen(chosenMsg) > 20 ? SubStr(chosenMsg, 1, 20) "..." : chosenMsg

 SendMessage_Internal(targetID, chosenMsg, currentWinIdx, currentLoop)
 
 if (currentLoop < loopCount) {
 sleepTime := Random(randomDelayMin, randomDelayMax)
 Sleep sleepTime
 }
 }
 
 AddLog("✅ ส่งข้อความ [" currentWinIdx "] ส่งข้อความ")
 
 ; การผสานรวม Webhook
 ถ้า (webhookEnabled && webhookURL != "") {
 SendWebhook(currentWinIdx, chosenMsg, true)
 }
 
 currentWinIdx++
 WrapWinIdx()
 
 UpdateStatusLabel()
 isSending := false
}

SendMessage_Internal(targetID, chosenMsg, windowIdx, loopNum) {
 global sendStats
 
 ส่ง "{ShiftUp}{CtrlUp}{AltUp}{LButtonUp}"
 รอ 50 วินาที

 WinActivate(targetID)
 ถ้า !WinWaitActive(targetID,, 2) {
 AddToHistory(windowIdx, chosenMsg, false)
 ส่งคืน
 }
 พัก 80 วินาที

 ; ล้างข้อความเก่า
 ส่ง "^a"
 พัก 40 วินาที
 ส่ง "{Backspace}"
 พัก 40 วินาที

 ; 🔥 วิธีการใช้คลิปบอร์ด - รับประกันไม่สูญหาย (ข้อความไม่สูญหาย)
 oldClip := ClipboardAll()
 A_Clipboard := ""
 A_Clipboard := chosenMsg
 
 if ClipWait(1) {
 ส่ง "^v"
 พัก 100 วินาที
 ส่ง "{Enter}"
 พัก 100 วินาที
 
 AddToHistory(windowIdx, chosenMsg, true)
 } else {
 AddToHistory(windowIdx,chosenMsg, false)
 }
 
 A_Clipboard := oldClip
 oldClip := ""
}

SendWebhook(windowIdx, message, success) {
 global webhookURL
 try {
 payload := '{"window":' windowIdx ',"message":"' StrReplace(message, """", "\""") '","success":' (success ? "true" : "false") ',"timestamp":"' Timestamp() '"}'
 HttpPost(webhookURL, payload,, 3)
 }
}

EmergencyStop(*) {
 global isSending
 isSending := false
 SetStatus("🛑 EMERGENCY STOPPED", "EF4444")
 AddLog("🛑 หยุดฉุกเฉิน หยุด\)
}

SetStatus(txt, col) {
 global statusText, statusDot
 statusText.Value := txt
 statusText.SetFont("c" col)
 statusDot.SetFont("c" col)
}

AddLog(txt) {
 global logBox
 current := logBox.Value
 logBox.Value := current "[" Timestamp("HH:mm:ss") "] " txt "`r`n"
 SendMessage(0x115, 7, 0, logBox.Hwnd)
}

Flash(txt) {
 ToolTip txt
 SetTimer () => ToolTip(), -2000
}

; ════════════════════════════════════════
; ⌨️ ปุ่มลัด
; ═════════════════════════════════════════
$F1::ManualSendAction() 
$F2::EmergencyStop() 
F4::ExitApp() 
F6::AddFollower()
