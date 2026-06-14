#Requires AutoHotkey v2.0
#Include ..\lib\MultiSenderLib.ahk
#Include TestHelper.ahk

t := TestRunner("Hotkeys")
tmpHK := A_Temp "\test_hotkeys_" A_TickCount ".ini"

; ── Save and load hotkeys ──────────────────────────────────

hotkeys := Map()
hotkeys["F1"] := "ManualSendAction"
hotkeys["F6"] := "AddFollower"
hotkeys["F2"] := "EmergencyStop"

SaveHotkeysToFile(tmpHK, hotkeys)
loaded := LoadHotkeysFromFile(tmpHK)

t.AssertEqual(loaded.Count, 3, "three hotkeys loaded")
t.AssertEqual(loaded["F1"], "ManualSendAction", "F1 mapping")
t.AssertEqual(loaded["F6"], "AddFollower", "F6 mapping")
t.AssertEqual(loaded["F2"], "EmergencyStop", "F2 mapping")

; ── Load from missing file ─────────────────────────────────

missingHK := A_Temp "\nonexistent_hotkeys_" A_TickCount ".ini"
empty := LoadHotkeysFromFile(missingHK)
t.AssertEqual(empty.Count, 0, "empty map from missing file")

; ── Save empty map ─────────────────────────────────────────

tmpHK2 := A_Temp "\test_hotkeys2_" A_TickCount ".ini"
emptyMap := Map()
SaveHotkeysToFile(tmpHK2, emptyMap)
loaded2 := LoadHotkeysFromFile(tmpHK2)
t.AssertEqual(loaded2.Count, 0, "empty map round-trip")

; ── Cleanup ────────────────────────────────────────────────
CleanupFile(tmpHK)
CleanupFile(tmpHK2)

failures := t.Report()
ExitApp(failures)
