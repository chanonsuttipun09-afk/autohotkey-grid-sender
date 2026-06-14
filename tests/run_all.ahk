#Requires AutoHotkey v2.0

; ═══════════════════════════════════════════════════════════
; Test Runner - executes each test suite as a subprocess
; and pipes per-suite stdout back to the caller.
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

shell := ComObject("WScript.Shell")

for suite in suites {
    path := testDir "\" suite
    if !FileExist(path) {
        FileAppend("SKIP: " suite " (not found)`n", "*")
        continue
    }

    try {
        cmd := '"' ahkExe '" /ErrorStdOut "' path '"'
        proc := shell.Exec(cmd)
        proc.StdIn.Close()

        stdout := ""
        while !proc.StdOut.AtEndOfStream
            stdout .= proc.StdOut.ReadLine() "`n"
        stderr := ""
        while !proc.StdErr.AtEndOfStream
            stderr .= proc.StdErr.ReadLine() "`n"

        if (stdout != "")
            FileAppend(stdout, "*")
        if (stderr != "")
            FileAppend(stderr, "*")

        while proc.Status = 0
            Sleep 50
        if (proc.ExitCode != 0)
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
