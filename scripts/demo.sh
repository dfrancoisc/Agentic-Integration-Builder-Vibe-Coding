#!/bin/bash
# ============================================================
# demo.sh — Launch IRIS Interop Editor + Observer side by side
#
# Opens two Safari windows positioned as a split view:
#   Left  = IRIS for Health Interop Editor (USER namespace)
#   Right = Observer terminal (behind-the-scenes live feed)
#
# Usage:
#   ./scripts/demo.sh
#   ./scripts/demo.sh 22773          # custom port
#   ./scripts/demo.sh 22773 HSCUSTOM # custom port + namespace
#
# First run: macOS will prompt to allow Terminal (or iTerm)
# to control Safari. Click "OK" to enable split-view positioning.
# If denied, both pages still open — just arrange manually.
# ============================================================

PORT="${1:-22773}"
NS="${2:-USER}"

EDITOR_URL="http://localhost:${PORT}/ui/interop/interop-editor/index.html?%24NAMESPACE=${NS}"
OBSERVER_URL="http://localhost:${PORT}/agentic/observer/index.html"

echo "Opening demo split view..."
echo "  Left:  IRIS for Health Interop Editor (${NS})"
echo "  Right: Observer (behind the scenes)"
echo ""

# Step 1: Open both URLs in Safari (always works, no permissions needed)
open -a Safari "${EDITOR_URL}"
sleep 1
open -a Safari "${OBSERVER_URL}"
sleep 1

# Step 2: Try to position windows side by side (needs Automation permission)
# Get screen resolution from system_profiler
SCREEN_W=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -m1 "Resolution:" | sed 's/.*: //' | awk '{print $1}')
SCREEN_H=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -m1 "Resolution:" | sed 's/.*: //' | awk '{print $3}')
if [ -z "$SCREEN_W" ] || [ "$SCREEN_W" = "0" ]; then
    SCREEN_W=2560; SCREEN_H=1440
fi

MENU_BAR=25
HALF_W=$(( SCREEN_W / 2 ))

osascript 2>/dev/null <<APPLESCRIPT
tell application "Safari"
    activate
    -- Find the Editor and Observer windows by URL
    set editorWin to missing value
    set observerWin to missing value
    repeat with w in windows
        try
            set tabUrl to URL of current tab of w
            if tabUrl contains "interop-editor" then
                set editorWin to w
            else if tabUrl contains "observer" then
                set observerWin to w
            end if
        end try
    end repeat

    -- Position: Editor on left, Observer on right
    if editorWin is not missing value then
        set bounds of editorWin to {0, ${MENU_BAR}, ${HALF_W}, ${SCREEN_H}}
    end if
    if observerWin is not missing value then
        set bounds of observerWin to {${HALF_W}, ${MENU_BAR}, ${SCREEN_W}, ${SCREEN_H}}
    end if

    -- Bring editor to front
    if editorWin is not missing value then
        set index of editorWin to 1
    end if
end tell
APPLESCRIPT

if [ $? -ne 0 ]; then
    echo "Note: Could not auto-position windows."
    echo "Grant Automation permission in System Settings > Privacy & Security > Automation"
    echo "to allow $(basename "$TERM_PROGRAM" 2>/dev/null || echo "Terminal") to control Safari."
    echo ""
    echo "Both pages are open — arrange them side by side manually."
else
    echo "Split view ready."
fi
echo "Interact with the chat on the left. The right shows every step behind the scenes."
