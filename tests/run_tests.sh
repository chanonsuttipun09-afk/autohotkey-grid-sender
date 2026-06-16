#!/usr/bin/env bash
# Run all AHK unit tests via Wine
set -euo pipefail

export WINEPREFIX="${WINEPREFIX:-$HOME/.wineahk}"
export WINEDEBUG="${WINEDEBUG:--all}"

AHK_EXE="$WINEPREFIX/drive_c/Program Files/AutoHotkey/v2/AutoHotkey64.exe"

if [ ! -f "$AHK_EXE" ]; then
    echo "ERROR: AutoHotkey not found at $AHK_EXE"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUITES=(
    test_FormatBytes.ahk
    test_Config.ahk
    test_Theme.ahk
    test_Messages.ahk
    test_Stats.ahk
    test_History.ahk
    test_Hotkeys.ahk
    test_Webhook.ahk
)

TOTAL=0
FAILED=0

echo "=== MultiSender Unit Tests ==="
for suite in "${SUITES[@]}"; do
    path="$SCRIPT_DIR/$suite"
    if [ ! -f "$path" ]; then
        echo "SKIP: $suite (not found)"
        continue
    fi
    TOTAL=$((TOTAL + 1))
    if xvfb-run -a wine "$AHK_EXE" /ErrorStdOut "$path" 2>&1; then
        :
    else
        FAILED=$((FAILED + 1))
    fi
done

echo "=== $((TOTAL - FAILED))/$TOTAL suites passed ==="
exit $FAILED
