#Requires AutoHotkey v2.0
#Include ..\lib\MultiSenderLib.ahk
#Include TestHelper.ahk

t := TestRunner("Theme")
tmpTheme := A_Temp "\test_theme_" A_TickCount ".ini"

; ── Save dark mode and reload ──────────────────────────────

SaveThemeToFile(tmpTheme, true)
result := LoadThemeFromFile(tmpTheme)
t.AssertEqual(result, 1, "dark mode saved as 1")

; ── Save light mode and reload ─────────────────────────────

SaveThemeToFile(tmpTheme, false)
result := LoadThemeFromFile(tmpTheme)
t.AssertEqual(result, 0, "light mode saved as 0")

; ── Missing file returns default (dark) ────────────────────

missingTheme := A_Temp "\nonexistent_theme_" A_TickCount ".ini"
result := LoadThemeFromFile(missingTheme)
t.AssertEqual(result, 1, "default is dark mode")

; ── Cleanup ────────────────────────────────────────────────
CleanupFile(tmpTheme)

failures := t.Report()
ExitApp(failures)
