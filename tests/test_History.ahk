#Requires AutoHotkey v2.0
#Include ..\lib\MultiSenderLib.ahk
#Include TestHelper.ahk

t := TestRunner("History")
tmpHist := A_Temp "\test_history_" A_TickCount ".txt"

; ── AddToSendHistory tracks success ────────────────────────

history := []
stats := {count: 0, success: 0, failed: 0}
AddToSendHistory(&history, &stats, tmpHist, 1, "hello", true)

t.AssertEqual(history.Length, 1, "one entry added")
t.AssertEqual(stats.count, 1, "count incremented")
t.AssertEqual(stats.success, 1, "success incremented")
t.AssertEqual(stats.failed, 0, "failed unchanged")
t.AssertTrue(InStr(history[1], "Window:1") > 0, "window index in entry")
t.AssertTrue(InStr(history[1], "hello") > 0, "message in entry")
t.AssertTrue(InStr(history[1], "+") > 0, "success marker")

; ── AddToSendHistory tracks failure ────────────────────────

AddToSendHistory(&history, &stats, tmpHist, 2, "oops", false)
t.AssertEqual(history.Length, 2, "two entries")
t.AssertEqual(stats.count, 2, "count is 2")
t.AssertEqual(stats.success, 1, "success still 1")
t.AssertEqual(stats.failed, 1, "failed incremented")
t.AssertTrue(InStr(history[2], "-") > 0, "failure marker")

; ── History file written ───────────────────────────────────

t.AssertTrue(FileExist(tmpHist), "history file created")
content := FileRead(tmpHist, "UTF-8")
t.AssertTrue(InStr(content, "hello") > 0, "first msg in file")
t.AssertTrue(InStr(content, "oops") > 0, "second msg in file")

; ── ClearSendHistory ───────────────────────────────────────

ClearSendHistory(&history, tmpHist)
t.AssertEqual(history.Length, 0, "history cleared")
t.AssertFalse(FileExist(tmpHist), "history file deleted")

; ── ExportSendHistory ──────────────────────────────────────

exportHistory := ["entry1", "entry2", "entry3"]
exportDir := A_Temp
filepath := ExportSendHistory(exportHistory, exportDir)
t.AssertTrue(FileExist(filepath), "export file created")
exportContent := FileRead(filepath, "UTF-8")
t.AssertTrue(InStr(exportContent, "entry1") > 0, "entry1 exported")
t.AssertTrue(InStr(exportContent, "entry2") > 0, "entry2 exported")
t.AssertTrue(InStr(exportContent, "entry3") > 0, "entry3 exported")

; ── History cap at 1000 ────────────────────────────────────

bigHistory := []
bigStats := {count: 0, success: 0, failed: 0}
tmpHist2 := A_Temp "\test_history2_" A_TickCount ".txt"

Loop 1002 {
    AddToSendHistory(&bigHistory, &bigStats, tmpHist2, 1, "msg" A_Index, true)
}
t.AssertEqual(bigHistory.Length, 1000, "history capped at 1000")
t.AssertEqual(bigStats.count, 1002, "stats count not capped")

; ── Cleanup ────────────────────────────────────────────────
CleanupFile(tmpHist)
CleanupFile(tmpHist2)
CleanupFile(filepath)

failures := t.Report()
ExitApp(failures)
