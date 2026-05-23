#!/bin/bash
# ============================================================
# demo.sh — Launch the Observer in Chrome with split view
#
# Opens the Observer page in Google Chrome with the ?split flag,
# which automatically loads the IRIS Interop Editor on the left
# half and the terminal log on the right half — all in one window.
#
# Usage:
#   ./scripts/demo.sh
#   ./scripts/demo.sh 22773          # custom port
#   ./scripts/demo.sh 22773 HSCUSTOM # custom port + namespace
# ============================================================

PORT="${1:-22773}"
NS="${2:-USER}"

OBSERVER_URL="http://localhost:${PORT}/agentic/observer/index.html?split&ns=${NS}"

echo "Opening Observer with split view in Chrome..."
echo "  Left:  IRIS for Health Interop Editor (${NS})"
echo "  Right: Observer (behind the scenes)"
echo ""

open -a "Google Chrome" "${OBSERVER_URL}"

echo "Done. Use the chat in the left panel — the right panel shows every step behind the scenes."
echo "Click 'Close Editor' in the topbar to go full-screen Observer."
