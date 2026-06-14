#Requires AutoHotkey v2.0
#Include ..\lib\MultiSenderLib.ahk
#Include TestHelper.ahk

t := TestRunner("Stats")

; ── ResetSendStats ─────────────────────────────────────────

stats := {count: 42, success: 30, failed: 12}
ResetSendStats(&stats)
t.AssertEqual(stats.count, 0, "count reset to 0")
t.AssertEqual(stats.success, 0, "success reset to 0")
t.AssertEqual(stats.failed, 0, "failed reset to 0")

; ── ComputeSuccessRate with zero count ─────────────────────

stats := {count: 0, success: 0, failed: 0}
rate := ComputeSuccessRate(stats)
t.AssertEqual(rate, 0, "rate is 0 when no sends")

; ── ComputeSuccessRate with all success ────────────────────

stats := {count: 10, success: 10, failed: 0}
rate := ComputeSuccessRate(stats)
t.AssertEqual(rate, 100, "100% success rate")

; ── ComputeSuccessRate with partial success ────────────────

stats := {count: 10, success: 7, failed: 3}
rate := ComputeSuccessRate(stats)
t.AssertEqual(rate, 70, "70% success rate")

; ── ComputeSuccessRate with all failures ───────────────────

stats := {count: 5, success: 0, failed: 5}
rate := ComputeSuccessRate(stats)
t.AssertEqual(rate, 0, "0% rate with all failures")

; ── ComputeSuccessRate with 1/3 success ────────────────────

stats := {count: 3, success: 1, failed: 2}
rate := ComputeSuccessRate(stats)
t.AssertEqual(rate, 33, "33% rate (rounded)")

failures := t.Report()
ExitApp(failures)
