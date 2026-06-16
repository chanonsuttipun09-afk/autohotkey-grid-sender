#Requires AutoHotkey v2.0
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
  masterPassword := IniRead(CONFIG_FILE, "Features", "masterPassword", "")
  
 } catch as err {
  OutputDebug("⚠️ LoadConfig error: " err.Message)
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
  
 } catch as err {
  AddLog("⚠️ SaveConfig error: " err.Message)
 }
}

LoadTheme() {
 global isDarkMode, THEME_FILE
 if FileExist(THEME_FILE) {
  try {
   isDarkMode := IniReadInt(THEME_FILE, "Theme", "darkMode", "1")
  } catch as err {
   OutputDebug("⚠️ LoadTheme error: " err.Message)
  }
 }
}

SaveTheme() {
 global isDarkMode, THEME_FILE
 try {
  IniWrite(isDarkMode ? "1" : "0", THEME_FILE, "Theme", "darkMode")
 } catch as err {
  AddLog("⚠️ SaveTheme error: " err.Message)
 }
}

LoadMessages() {
 global MSG_FILE
 try {
  if !FileExist(MSG_FILE) {
   defaultMsgs := "สวัสดีครับที่ชื่นชอบสอบถามได้เลยนะ`r`nขอบคุณที่แวะมารับชมครับผม `r`n ฝากกดหัวใจและติดตามด้วยนะครับ"
   FileAppend(defaultMsgs, MSG_FILE, "UTF-8")
  }
  return FileRead(MSG_FILE, "UTF-8")
 } catch as err {
  OutputDebug("⚠️ LoadMessages error: " err.Message)
  return "สวัสดีครับ สอบถามได้ครับ"
 }
}

SaveMessages(txt) {
 global MSG_FILE
 try {
  DeleteIfExists(MSG_FILE)
  FileAppend(Trim(txt, "`r`n "), MSG_FILE, "UTF-8")
 } catch as err {
  AddLog("⚠️ SaveMessages error: " err.Message)
 }
}

AddToHistory(windowIdx, msg, success) {
 global sendHistory, HISTORY_FILE, sendStats
 
 timestamp := Timestamp()
 entry := timestamp " | Window:" windowIdx " | " (success ? "✓" : "✗") " | " msg
 
 sendHistory.Push(entry)
 if (sendHistory.Length > 1000)
  sendHistory.RemoveAt(1)
 
 try {
  FileAppend(entry "`r`n", HISTORY_FILE, "UTF-8")
 } catch as err {
  AddLog("⚠️ History write error: " err.Message)
 }
 
 sendStats.count++
 if (success)
  sendStats.success++
 else
  sendStats.failed++
}

LoadCustomHotkeys() {
 global customHotkeys, HOTKEY_FILE
 customHotkeys := {}
 if !FileExist(HOTKEY_FILE)
  return
 try {
  n := IniReadInt(HOTKEY_FILE, "Hotkeys", "count")
  Loop n {
   key := IniRead(HOTKEY_FILE, "Hotkeys", "key" A_Index, "")
   action := IniRead(HOTKEY_FILE, "Hotkeys", "action" A_Index, "")
   if (key != "" && action != "")
    customHotkeys[key] := action
  }
 } catch as err {
  OutputDebug("⚠️ LoadCustomHotkeys error: " err.Message)
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
; ════════════════════════════════════════
G.SetFont("s11 Bold", "Segoe UI")
G.AddText("x" PAD " y12 Background" BG " c" ACC, "⚡")
G.AddText("x+6 yp Background" BG " c" FG, "GRID SENDER v6")
G.SetFont("s8 Bold", "Segoe UI")
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
G.SetFont("s9 Bold c" FG, "Segoe UI")
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
; ════════════════════════════════════════
G.AddText("x" PAD " y+12 w" COMP_W " h1 Background" LINE, "")

; Window Register
G.SetFont("s8.5 Bold", "Segoe UI")
G.AddText("x" PAD " y+6 c" FG2, "📺 ลงทะเบียนกลุ่มเป้าหมาย:")
BTN2_W := Floor((COMP_W - 6) / 2)
G.AddButton("x" PAD " y+5 w" BTN2_W " h22 +0x200 c" CYN, "＋ไม่ต้องเพิ่มจอ (F6)").OnEvent("Click", AddFollower)
G.AddButton("x+6 yp w" BTN2_W " h22 +0x200 c" RED, "🧹 ล้าง").OnEvent("Click", ClearFollowers)

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
randomMinCtrl := G.AddEdit("x+3 yp w40 h18 Background" BG2 " c" FG, "0")
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
; ════════════════════════════════════════
G.SetFont("s9 Bold", "Segoe UI")
schedulerEnableCtrl := G.AddCheckbox("x" (PAD+5) " y" (PAD+100) " w200 h25", "🕐 เปิดเวลาอัตโนมัติ")
schedulerEnableCtrl.OnEvent("Click", ToggleScheduler)

G.SetFont("s8", "Segoe UI")
G.AddText("x" (PAD+5) " y+5 c" FG, "ช่วงเวลา (ms):")
schedulerIntervalCtrl := G.AddEdit("x" (PAD+5) " y+3 w100 h22 Background" BG2 " c" FG, "5000")

btnStartScheduler := G.AddButton("x" (PAD+110) " y" (PAD+128) " w80 h22 +0x200 c" GRN, "▶เริ่มต้น")
btnStartScheduler.OnEvent("Click", StartScheduler)

btnStopScheduler := G.AddButton("x+5 yp w80 h22 +0x200 c" RED, "⏹หยุด")
btnStopScheduler.OnEvent("Click", StopScheduler)

G.AddText("x" (PAD+5) " y+10 c" GRN, "⏸ปิดอยู่")
schedulerStatus := G.AddText("x" (PAD+5) " y+0 c" GRN)

; ════════════════════════════════════════
; แท็บ: สถิติ
; ════════════════════════════════════════
G.SetFont("s10 Bold c" GRN, "Segoe UI")
statsCountCtrl := G.AddText("x" (PAD+10) " y" (PAD+105) " w400 h30 Background" BG2 " c" GRN, "📊 ส่งทั้งหมด: 0 ทั้งหมด")
statsSuccessCtrl := G.AddText("x" (PAD+10) " y+5 w400 h30 Background" BG2 " c" GRN, "✅ สำเร็จ : 0 เท่านั้น")
statsFailCtrl := G.AddText("x" (PAD+10) " y+5 w400 h30 Background" BG2 " c" RED, "❌ ล้มเหลว: 0")
statsRateCtrl := G.AddText("x" (PAD+10) " y+5 w400 h30 Background" BG2 " c" YEL,"📈 อัตราสำเร็จ: 0%")

btnResetStats := G.AddButton("x" (PAD+10) " y+5 w100 h25 +0x200 c" RED, "🔄 รีเซต")
btnResetStats.OnEvent("Click", ResetStats)

; ════════════════════════════════════════
; แท็บ: ประวัติ
; ════════════════════════════════════════
G.SetFont("s8", "Consolas")
historyBox := G.AddEdit("x" (PAD+5) " y" (PAD+105) " w" (COMP_W-10) " h180 ReadOnly -Wrap +0x200000 Background" BG2 " c" GRN)

btnClearHistory := G.AddButton("x" (PAD+5) " y+5 w100 h25 +0x200 c" RED, "🗑️ล้างประวัติ")
btnClearHistory.OnEvent("Click", ClearHistory)

btnExportHistory := G.AddButton("x+5 yp w100 h25 +0x200 c" CYN, "💾 ส่งออก")
btnExportHistory.OnEvent("Click", ExportHistory)

; ════════════════════════════════════════
; แท็บ: การตั้งค่า
; ════════════════════════════════════════
G.SetFont("s8.5 Bold", "Segoe UI")
G.AddText("x" (PAD+5) " y" (PAD+100) " c" FG2, "🔐 จำเป็นด้วยรหัสผ่าน:")
passwordEnableCtrl := G.AddCheckbox("x" (PAD+5) " y+3 w20 h20", "")
passwordEnableCtrl.OnEvent("Click", TogglePassword)

G.SetFont("s8 c" FG, "Segoe UI")
G.AddText("x" (PAD+30) " y" (PAD+105) " c" FG, "รหัสผ่าน:")
passwordCtrl := G.AddEdit("x" (PAD+30) " y+3 w150 h20 Background" BG2 " c" FG " Password")

G.AddText("x" (PAD+5) " y+10 c" FG, "⚙️ การติดตั้ง Hotkey:")
G.AddText("x" (PAD+5) " y+3 c" FG, "F1 (ส่ง):")
hotkeyF1Ctrl := G.AddEdit("x+50 yp w80 h20 Background" BG2 " c" FG, "F1")

G.AddText("x" (PAD+5) " y+5 c" FG, "F6 (บันทึกการตั้งค่า):")
hotkeyF6Ctrl := G.AddEdit("x+50 yp w80 h20 Background" BG2 " c" FG, "F6")

G.AddText("x" (PAD+5) " y+5 c" FG, "F2 (บันทึก):")
hotkeyF2Ctrl := G.AddEdit("x+50 yp w80 h20 Background" BG2 " c" FG, "F2")

btnSaveSettings := G.AddButton("x" (PAD+5) " y+10 w100 h25 +0x200 c" GRN, "💾 บันทึก")
btnSaveSettings.OnEvent("Click", SaveSettings)

btnResetHotkeys := G.AddButton("x+5 yp w100 h25 +0x200 c" RED, "🔄 รีเซต")
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

; ════════════════════════════════════════
; ฟังก์ชั่นการจัดการ UI
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
; ════════════════════════════════════════

ToggleScheduler(GuiCtrlObj, Info) {
 global schedulerEnabled
 schedulerEnabled := GuiCtrlObj.Value
}

StartScheduler(*) {
 global isSchedulerRunning, schedulerIntervalCtrl, schedulerStatus
 
 if isSchedulerRunning {
  Flash("⚠️ ตัวจัดเวลากำลังทำงานอยู่แล้ว")
  return
 }
 
 isSchedulerRunning := true
 interval := Integer(schedulerIntervalCtrl.Value)
 if (interval < 100)
  interval := 100
 
 schedulerStatus.Value := "▶ กำลังทำงาน..."
 schedulerStatus.SetFont("c" GRN)
 
 AddLog("⏰ เริ่มตั้งเวลา: " interval "ms")
 
 SetTimer SchedulerTick, interval
}

SchedulerTick() {
 global followers, isSending
 if (followers.Length == 0)
  return
 if !isSending
  ManualSendAction()
}

StopScheduler(*) {
 global isSchedulerRunning, schedulerStatus
 
 isSchedulerRunning := false
 SetTimer SchedulerTick, 0
 
 schedulerStatus.Value := "⏸ ปิดอยู่"
 schedulerStatus.SetFont("c" RED)
 
 AddLog("⏰ หยุดตั้งเวลาแล้ว")
}

; ════════════════════════════════════════
; ฟังก์ชั่นสถิติ
; ════════════════════════════════════════

UpdateStats() {
 global sendStats, statsCountCtrl, statsSuccessCtrl, statsFailCtrl, statsRateCtrl, statsDisplay
 statsCountCtrl.Value := "📊 ส่งทั้งหมด: " sendStats.count " ครั้ง"
 statsSuccessCtrl.Value := "✅ สำเร็จ: " sendStats.success " ครั้ง"
 statsFailCtrl.Value := "❌ ล้มเหลว: " sendStats.failed " ครั้ง"
 
 rate := (sendStats.count = 0) ? 0 : Round((sendStats.success / sendStats.count) * 100)
 statsRateCtrl.Value := "📈 อัตราสำเร็จ: " rate "%"
 
 statsDisplay.Value := "✓" sendStats.success " ✗" sendStats.failed
}

ResetStats(*) {
 global sendStats
 sendStats := {count: 0, success: 0, failed: 0}
 AddLog("🔄 รีเซ็ตสถิติแล้ว")
}

; ════════════════════════════════════════
; ฟังก์ชันประวัติ
; ════════════════════════════════════════

ClearHistory(*) {
 global sendHistory, HISTORY_FILE, historyBox
 sendHistory := []
 try {
  DeleteIfExists(HISTORY_FILE)
 } catch as err {
  AddLog("⚠️ ClearHistory error: " err.Message)
 }
 historyBox.Value := ""
 AddLog("🗑️ ล้างประวัติแล้ว")
}

ExportHistory(*) {
 global sendHistory
 
 filepath := A_MyDocuments "\send_history_" Timestamp("yyyyMMdd_HHmmss") ".txt"
 content := ""
 for entry in sendHistory
  content .= entry "`r`n"
 
 try {
  FileAppend(content, filepath, "UTF-8")
  AddLog("💾 ส่งออกประวัติ: " filepath)
  Flash("✅ ส่งออกสำเร็จ!")
 } catch as err {
  AddLog("⚠️ ExportHistory error: " err.Message)
  Flash("❌ ส่งออกล้มเหลว: " err.Message)
 }
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
  
  AddLog("💾 บันทึก Hotkey สำเร็จ")
  Flash("✅ บันทึกสำเร็จ!")
 } catch as err {
  AddLog("⚠️ SaveSettings error: " err.Message)
  Flash("❌ บันทึกล้มเหลว: " err.Message)
 }
}

ResetHotkeys(*) {
 global hotkeyF1Ctrl, hotkeyF6Ctrl, hotkeyF2Ctrl
 hotkeyF1Ctrl.Value := "F1"
 hotkeyF6Ctrl.Value := "F6"
 hotkeyF2Ctrl.Value := "F2"
 AddLog("🔄 รีเซ็ต Hotkey เป็นค่าเริ่มต้น")
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
    ipGeoDisplay.Value := (matchIp ? matchIp[1] : "Unknown") " [" (matchCountry ? matchCountry[1] : "—") "/" (matchRegion ? matchRegion[1] : "—") "]"
    return
   }
  }
  ipGeoDisplay.Value := "⚠️ ไม่พบข้อมูล IP (HTTP " whr.Status ")"
 } catch as err {
  ipGeoDisplay.Value := "⚠️ เครือข่ายผิดพลาด"
  AddLog("⚠️ FetchGeoIP error: " err.Message)
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
 } catch as err {
  OutputDebug("⚠️ InitNetworkCounter error: " err.Message)
  lastInBytes := 0
  lastOutBytes := 0
 }
}

UpdateNetworkSpeed() {
 global lastInBytes, lastOutBytes, netSpeedDisplay, wmiService
 currentIn := 0, currentOut := 0
 try {
  if !wmiService
   wmiService := ComObjGet("winmgmts:")
  for obj in wmiService.ExecQuery("Select BytesReceivedPersec, BytesSentPersec From Win32_PerfRawData_Tcpip_NetworkInterface") {
   currentIn += Integer(obj.BytesReceivedPersec)
   currentOut += Integer(obj.BytesSentPersec)
  }
 } catch as err {
  AddLog("⚠️ UpdateNetworkSpeed error: " err.Message)
  return
 }
 if (lastInBytes = 0 && lastOutBytes = 0) {
  lastInBytes := currentIn, lastOutBytes := currentOut
  return
 }
 diffIn := currentIn - lastInBytes, diffOut := currentOut - lastOutBytes
 if (diffIn < 0 || diffOut < 0) {
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
; 🎯 ฟังก์ชั่นพื้นที่ทำงานและการจัดเรียง
; ════════════════════════════════════════

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
 UpdateStatusLabel()
 Flash("✅ เพิ่มจอสำเร็จ")
}

ClearFollowers(*) {
 global followers, currentWinIdx
 followers := []
 currentWinIdx := 1
 SaveConfig()
 UpdateStatusLabel()
 Flash("🧹 ล้างหน้าต่างทั้งหมดแล้ว")
}

UpdateStatusLabel() {
 global followers, currentWinIdx
 if (followers.Length == 0)
  SetStatus("คิวว่าง | กด F6 ชี้เพิ่มหน้าต่าง", "EF4444")
 else
  SetStatus("บันทึกไว้ " followers.Length " จอ (กลุ่มเป้าหมายถัดไป: จอที่ " currentWinIdx ")", "10B981")
}

ArrangeWindowsFixed(*) {
 global followers, WIN_W, WIN_H, MARGIN_WIN
 if (followers.Length == 0) {
  SetStatus("❌ ยังไม่ได้กด F6 ล็อกหน้าต่าง", "EF4444")
  return
 }
 
 try {
  MonitorGet(1, &M_L, &M_T, &M_R, &M_B)
 } catch as err {
  AddLog("⚠️ MonitorGet error: " err.Message)
  return
 }
 
 monitorWidth := M_R - M_L
 availableWidth := monitorWidth - (2 * MARGIN_WIN)
 totalWinWidth := availableWidth + MARGIN_WIN
 cols := Floor(totalWinWidth / (WIN_W + MARGIN_WIN))
 if (cols < 1)
  cols := 1
 
 movedCount := 0
 for idx, id in followers {
  if !WinExist(id) {
   AddLog("⚠️ [" idx "] หน้าต่างไม่พบ")
   continue
  }
  
  try {
   WinRestore(id)
   Sleep 50
   
   colIdx := Mod(movedCount, cols)
   rowIdx := Floor(movedCount / cols)
   
   X := M_L + MARGIN_WIN + (colIdx * (WIN_W + MARGIN_WIN))
   Y := M_T + MARGIN_WIN + (rowIdx * (WIN_H + MARGIN_WIN))
   
   WinMove(X, Y, WIN_W, WIN_H, id)
   Sleep 30
   movedCount++
  } catch as err {
   AddLog("⚠️ ArrangeWindow [" idx "] error: " err.Message)
  }
 }
 SetStatus("🧩 จัดเรียง " movedCount " จอเรียบร้อย", "06B6D4")
 AddLog("🧩 จัดเรียง " WIN_W "x" WIN_H " (" movedCount " จอ)")
}

; ════════════════════════════════════════
; 🚀 ระบบส่งข้อความ
; ════════════════════════════════════════

ManualSendAction(*) {
 global isSending, msgEditor, followers, currentWinIdx, repeatMode, repeatCount
 global randomDelayMin, randomDelayMax, webhookEnabled, webhookURL
 global repeatModeCtrl, repeatCountCtrl, randomMinCtrl, randomMaxCtrl
 
 if isSending
  return
 
 if (followers.Length == 0) {
  SetStatus("❌ กด F6 บันทึกหน้าต่างแชทก่อนส่ง!", "EF4444")
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
  SetStatus("❌ พิมพ์ข้อความก่อน!", "EF4444")
  return
 }

 ; รับการตั้งค่า
 repeatMode := repeatModeCtrl.Value
 repeatCount := Integer(repeatCountCtrl.Value) ? Integer(repeatCountCtrl.Value) : 1
 randomDelayMin := Integer(randomMinCtrl.Value)
 randomDelayMax := Integer(randomMaxCtrl.Value)
 webhookEnabled := webhookModeCtrl.Value
 webhookURL := webhookURLCtrl.Value

 WrapWinIdx()
 
 targetID := followers[currentWinIdx]
 
 if !WinExist(targetID) {
  AddLog("⚠️ หน้าต่าง [" currentWinIdx "] ปิดอยู่.. กำลังข้าม")
  currentWinIdx++
  WrapWinIdx()
  return
 }

 isSending := true
 SetStatus("⚡ กำลังส่งข้อความ...", "F59E0B")
 SetTimer BlinkLED, 300
 
 chosenMsg := ""
 try {
  loopCount := repeatMode ? repeatCount : 1
  Loop loopCount {
   currentLoop := A_Index
   chosenMsg := lines[Random(1, lines.Length)]
   shortMsg := StrLen(chosenMsg) > 20 ? SubStr(chosenMsg, 1, 20) "..." : chosenMsg

   SendMessage_Internal(targetID, chosenMsg, currentWinIdx, currentLoop)
   
   if (currentLoop < loopCount) {
    sleepTime := Random(randomDelayMin, randomDelayMax)
    Sleep sleepTime
   }
  }
  
  AddLog("✅ ส่งข้อความ [" currentWinIdx "] สำเร็จ")
  
  ; Webhook integration
  if (webhookEnabled && webhookURL != "") {
   SendWebhook(currentWinIdx, chosenMsg, true)
  }
 } catch as err {
  AddLog("⚠️ ManualSendAction error: " err.Message)
  SetStatus("❌ ส่งข้อความล้มเหลว: " err.Message, "EF4444")
 }
 
 currentWinIdx++
 WrapWinIdx()
 
 UpdateStatusLabel()
 isSending := false
}

SendMessage_Internal(targetID, chosenMsg, windowIdx, loopNum) {
 global sendStats
 
 Send "{ShiftUp}{CtrlUp}{AltUp}{LButtonUp}"
 Sleep 50

 WinActivate(targetID)
 if !WinWaitActive(targetID,, 2) {
  AddLog("⚠️ WinWaitActive timeout [" windowIdx "] loop " loopNum)
  AddToHistory(windowIdx, chosenMsg, false)
  sendStats.failed++
  return
 }
 Sleep 80

 ; ล้างข้อความเก่า
 Send "^a"
 Sleep 40
 Send "{Backspace}"
 Sleep 40

 ; วิธีการใช้คลิปบอร์ด
 oldClip := ClipboardAll()
 A_Clipboard := ""
 A_Clipboard := chosenMsg
 
 if ClipWait(1) {
  Send "^v"
  Sleep 100
  Send "{Enter}"
  Sleep 100
  
  AddToHistory(windowIdx, chosenMsg, true)
 } else {
  AddLog("⚠️ ClipWait timeout [" windowIdx "] loop " loopNum)
  AddToHistory(windowIdx, chosenMsg, false)
 }
 
 A_Clipboard := oldClip
 oldClip := ""
}

SendWebhook(windowIdx, message, success) {
 global webhookURL
 try {
  escapedMsg := StrReplace(message, '"', '\"')
  payload := '{"window":' windowIdx ',"message":"' escapedMsg '","success":' (success ? "true" : "false") ',"timestamp":"' Timestamp() '"}'
  whr := HttpPost(webhookURL, payload,, 3)
  
  if (whr.Status != 200) {
   AddLog("⚠️ Webhook HTTP " whr.Status " for window " windowIdx)
  }
 } catch as err {
  AddLog("⚠️ SendWebhook error: " err.Message)
 }
}

EmergencyStop(*) {
 global isSending
 isSending := false
 SetStatus("🛑 EMERGENCY STOPPED", "EF4444")
 AddLog("🛑 หยุดฉุกเฉิน!")
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
; ════════════════════════════════════════
$F1::ManualSendAction() 
$F2::EmergencyStop() 
F4::ExitApp() 
F6::AddFollower()
