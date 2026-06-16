#Requires AutoHotkey v2.0
#Include ..\lib\MultiSenderLib.ahk
#Include TestHelper.ahk

t := TestRunner("Config")
tmpConfig := A_Temp "\test_config_" A_TickCount ".ini"

; ── SaveConfig + LoadConfig round-trip ─────────────────────

followers := ["ahk_id 0x1234", "ahk_id 0x5678"]
SaveConfigToFile(tmpConfig, followers, 3000, 5, 100, 2000, "https://hook.example.com", 1, 1, "secret123")

loadedFollowers := []
si := 0
rc := 0
rdMin := 0
rdMax := 0
wURL := ""
wEnabled := 0
pProt := 0
mPwd := ""

LoadConfigFromFile(tmpConfig, &loadedFollowers, &si, &rc, &rdMin, &rdMax, &wURL, &wEnabled, &pProt, &mPwd)

t.AssertEqual(loadedFollowers.Length, 2, "follower count")
t.AssertEqual(loadedFollowers[1], "ahk_id 0x1234", "follower 1")
t.AssertEqual(loadedFollowers[2], "ahk_id 0x5678", "follower 2")
t.AssertEqual(si, 3000, "scheduler interval")
t.AssertEqual(rc, 5, "repeat count")
t.AssertEqual(rdMin, 100, "random delay min")
t.AssertEqual(rdMax, 2000, "random delay max")
t.AssertEqual(wURL, "https://hook.example.com", "webhook URL")
t.AssertEqual(wEnabled, 1, "webhook enabled")
t.AssertEqual(pProt, 1, "password protection")
t.AssertEqual(mPwd, "secret123", "master password")

; ── LoadConfig with missing file ───────────────────────────

missingFile := A_Temp "\nonexistent_" A_TickCount ".ini"
emptyFollowers := []
defSI := 0
defRC := 0
defRDMin := 0
defRDMax := 0
defWURL := ""
defWE := 0
defPP := 0
defMP := ""

LoadConfigFromFile(missingFile, &emptyFollowers, &defSI, &defRC, &defRDMin, &defRDMax, &defWURL, &defWE, &defPP, &defMP)
t.AssertEqual(emptyFollowers.Length, 0, "no followers from missing file")

; ── SaveConfig with empty followers ────────────────────────

tmpConfig2 := A_Temp "\test_config2_" A_TickCount ".ini"
emptyArr := []
SaveConfigToFile(tmpConfig2, emptyArr, 5000, 1, 0, 1000, "", 0, 0, "")

loaded2 := []
si2 := 0
rc2 := 0
rdMin2 := 0
rdMax2 := 0
wURL2 := ""
wE2 := 0
pP2 := 0
mP2 := ""
LoadConfigFromFile(tmpConfig2, &loaded2, &si2, &rc2, &rdMin2, &rdMax2, &wURL2, &wE2, &pP2, &mP2)
t.AssertEqual(loaded2.Length, 0, "empty followers saved/loaded")
t.AssertEqual(si2, 5000, "default scheduler interval")
t.AssertEqual(rc2, 1, "default repeat count")

; ── Cleanup ────────────────────────────────────────────────
CleanupFile(tmpConfig)
CleanupFile(tmpConfig2)

failures := t.Report()
ExitApp(failures)
