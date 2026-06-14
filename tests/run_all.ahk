#Requires AutoHotkey v2.0

; ═══════════════════════════════════════════════════════════
; Test Runner - executes each test suite as a subprocess
; ═══════════════════════════════════════════════════════════

testDir := A_ScriptDir
ahkExe := A_AhkPath

suites := [
    "test_FormatBytes.ahk",
    "test_Config.ahk",
    "test_Theme.ahk",
    "test_Messages.ahk",
    "test_Stats.ahk",
    "test_History.ahk",
    "test_Hotkeys.ahk",
    "test_Webhook.ahk"
]

totalFailed := 0
FileAppend("═══ MultiSender Test Suite ═══`n", "*")

for suite in suites {
    path := testDir "\" suite
    if !FileExist(path) {
        FileAppend("SKIP: " suite " (not found)`n", "*")
        continue
    }

    try {
        cmd := '"' ahkExe '" /ErrorStdOut "' path '"'
        result := RunWait(cmd,, "Hide")
        if (result != 0)
            totalFailed++
    } catch as e {
        FileAppend("ERROR running " suite ": " e.Message "`n", "*")
        totalFailed++
    }
}

FileAppend("═══ Done ═══`n", "*")
if (totalFailed > 0)
    FileAppend("RESULT: " totalFailed " suite(s) had failures`n", "*")
else
    FileAppend("RESULT: All suites passed`n", "*")

ExitApp(totalFailed)
