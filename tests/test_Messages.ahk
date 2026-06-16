#Requires AutoHotkey v2.0
#Include ..\lib\MultiSenderLib.ahk
#Include TestHelper.ahk

t := TestRunner("Messages")
tmpMsg := A_Temp "\test_messages_" A_TickCount ".txt"

; ── LoadMessages creates default when file missing ─────────

result := LoadMessagesFromFile(tmpMsg)
t.AssertTrue(StrLen(result) > 0, "default message created")
t.AssertTrue(FileExist(tmpMsg), "file created on first load")

CleanupFile(tmpMsg)

; ── SaveMessages + LoadMessages round-trip ─────────────────

tmpMsg2 := A_Temp "\test_messages2_" A_TickCount ".txt"
SaveMessagesToFile(tmpMsg2, "Line1`r`nLine2`r`nLine3")
content := FileRead(tmpMsg2, "UTF-8")
t.AssertTrue(InStr(content, "Line1") > 0, "line1 saved")
t.AssertTrue(InStr(content, "Line2") > 0, "line2 saved")
t.AssertTrue(InStr(content, "Line3") > 0, "line3 saved")

CleanupFile(tmpMsg2)

; ── SaveMessages trims whitespace ──────────────────────────

tmpMsg3 := A_Temp "\test_messages3_" A_TickCount ".txt"
SaveMessagesToFile(tmpMsg3, "  hello world  `r`n")
content := FileRead(tmpMsg3, "UTF-8")
t.AssertEqual(content, "hello world", "whitespace trimmed")

CleanupFile(tmpMsg3)

; ── ParseMessageLines ──────────────────────────────────────

lines := ParseMessageLines("hello`nworld`n`n  foo  `n")
t.AssertEqual(lines.Length, 3, "three non-empty lines")
t.AssertEqual(lines[1], "hello", "first line")
t.AssertEqual(lines[2], "world", "second line")
t.AssertEqual(lines[3], "foo", "third line trimmed")

; ── ParseMessageLines empty input ──────────────────────────

lines := ParseMessageLines("")
t.AssertEqual(lines.Length, 0, "empty input yields no lines")

lines := ParseMessageLines("`n`n`n")
t.AssertEqual(lines.Length, 0, "only newlines yields no lines")

failures := t.Report()
ExitApp(failures)
