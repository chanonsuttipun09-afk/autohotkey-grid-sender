---
name: validating-ahk-scripts
description: How to syntax-check and run AutoHotkey v2 (.ahk) scripts on Linux via Wine. Use whenever editing or creating .ahk files in this repo so changes are verified to compile/run before opening a PR.
---

# Validating AutoHotkey v2 scripts

AutoHotkey is Windows-only and cannot run natively on Linux. Use Wine + the real
AHK v2 interpreter to validate before committing. The environment blueprint installs
Wine, Xvfb, and AutoHotkey v2 (`AutoHotkey64.exe`) and sets `WINEPREFIX`.

Interpreter path: `$WINEPREFIX/drive_c/Program Files/AutoHotkey/v2/AutoHotkey64.exe`

## 1. Syntax check (fast, headless)

```bash
export WINEDEBUG=-all
AHK="$WINEPREFIX/drive_c/Program Files/AutoHotkey/v2/AutoHotkey64.exe"
wine "$AHK" /ErrorStdOut /validate path/to/script.ahk; echo "exit=$?"
```

- exit `0` = no syntax errors. Non-zero (e.g. `2`) = syntax error (details on stderr).
- `/validate` only parses; it does NOT run the script, so runtime errors are not caught here.

## 2. Runtime smoke test (catches startup/GUI/function errors)

Running needs a display; use `xvfb-run` if headless. If the script's auto-execute
builds a GUI and stays in an event loop, a timeout means it started cleanly:

```bash
export WINEDEBUG=-all
AHK="$WINEPREFIX/drive_c/Program Files/AutoHotkey/v2/AutoHotkey64.exe"
timeout 12 xvfb-run -a wine "$AHK" /ErrorStdOut path/to/script.ahk 2>/tmp/run.log
# exit 124 = still running after timeout = started OK; any AHK error is written to /tmp/run.log
```

To exercise functions that only run on user action, make a temp copy, inject calls
to those functions just before the auto-execute `return`, end with
`FileAppend("OK", "result.txt")` and `ExitApp(0)`, then run it and check the result file.

## Gotchas

- `.ahk` files containing Thai (or other non-ASCII) text MUST be saved as **UTF-8 with BOM**,
  otherwise AHK misreads the first line / directives. Verify: first 3 bytes `EF BB BF`.
- Line 1 must be a valid directive, e.g. `#Requires AutoHotkey v2.0` (machine-translated
  files sometimes corrupt this into Thai and fail with "does not contain a recognized action").
- AHK v2 functions only see globals they declare with `global`; reading an undeclared
  global throws at runtime (not caught by `/validate`). Audit each function's `global` list.
- Quick structural pre-check: braces/parens/brackets balanced and no line with an odd
  number of unescaped `"` (AHK escapes a literal quote as `""`).
