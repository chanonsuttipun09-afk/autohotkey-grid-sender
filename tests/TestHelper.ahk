; ═══════════════════════════════════════════════════════════
; Minimal AHK v2 Test Helper
; ═══════════════════════════════════════════════════════════

class TestRunner {
    __New(suiteName) {
        this.suite := suiteName
        this.passed := 0
        this.failed := 0
        this.errors := []
    }

    AssertEqual(actual, expected, label := "") {
        if (actual == expected) {
            this.passed++
        } else {
            this.failed++
            msg := label != "" ? label : "AssertEqual"
            this.errors.Push(msg ": expected [" expected "] got [" actual "]")
        }
    }

    AssertNotEqual(actual, notExpected, label := "") {
        if (actual != notExpected) {
            this.passed++
        } else {
            this.failed++
            msg := label != "" ? label : "AssertNotEqual"
            this.errors.Push(msg ": should not equal [" notExpected "]")
        }
    }

    AssertTrue(condition, label := "") {
        if (condition) {
            this.passed++
        } else {
            this.failed++
            msg := label != "" ? label : "AssertTrue"
            this.errors.Push(msg ": expected true")
        }
    }

    AssertFalse(condition, label := "") {
        if (!condition) {
            this.passed++
        } else {
            this.failed++
            msg := label != "" ? label : "AssertFalse"
            this.errors.Push(msg ": expected false")
        }
    }

    Report() {
        total := this.passed + this.failed
        FileAppend("[" this.suite "] " total " tests: " this.passed " passed, " this.failed " failed`n", "*")
        for err in this.errors
            FileAppend("  FAIL: " err "`n", "*")
        return this.failed
    }
}

; Clean up temp files created during tests
CleanupFile(path) {
    if FileExist(path)
        FileDelete(path)
}
