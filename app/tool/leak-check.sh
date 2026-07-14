#!/usr/bin/env bash
# Native memory DIAGNOSTIC for the animated presence — a rough real-app soak. NOT a trusted gate.
#
# Honest status: this soaks the REAL app process (phys_footprint, which includes GPU/IOKit memory
# RSS misses) with the window forced frontmost. It confirms the app reaches steady-state (the fixed
# build plateaus ~35MB growth). BUT mutation-validation FAILED: reintroducing the per-frame gradient
# leak did NOT reliably grow footprint here — the visible-GPU leak only accrues under genuine
# INTERACTIVE compositing (how it was originally hit by hand), which `osascript activate` doesn't
# faithfully reproduce headless. Per the rule "a guard that doesn't go red on mutation isn't
# trusted," this is a smoke/diagnostic, not a gate.
#
# What IS trusted for leaks:
#   • CI gate: app/test/render_resource_test.dart — the Dart Picture/Image leak classes,
#     mutation-validated (removing pic.dispose() turns it red).
#   • CI gate: precheck.sh [4b] — static lint forbidding a per-frame shader in plena.dart paint()
#     (the exact class that shipped; the aura draws the cached sprite instead).
#   • Diagnosis: Xcode Instruments (Allocations) — when something's suspected, it pinpoints the line.
# This script complements those as a quick "does the real app plateau?" check.
#
# Usage:  bash app/tool/leak-check.sh [seconds]   (default 75)
set -euo pipefail
cd "$(dirname "$0")/.."   # -> app/

APP="build/macos/Build/Products/Debug/Plenara.app"
SECS="${1:-75}"
BOUND_MB="${LEAK_BOUND_MB:-120}"   # generous: the observed leak added GB; steady-state noise is tens of MB

[ -d "$APP" ] || { echo "!! build first: flutter build macos --debug"; exit 1; }

phys_mb() { # phys_footprint of a pid, in MB
  footprint "$1" 2>/dev/null \
    | grep -iE 'phys_footprint|Physical footprint' | tail -1 \
    | grep -oE '[0-9]+(\.[0-9]+)?[[:space:]]*[KMG]?B?' | tail -1 \
    | awk '{ v=$1; if ($0 ~ /G/) v*=1024; else if ($0 ~ /K/) v/=1024; printf "%.0f", v }'
}

pkill -f "MacOS/Plenara" 2>/dev/null || true
sleep 1
open "$APP"
osascript -e 'tell application "Plenara" to activate' 2>/dev/null || true  # frontmost → it composites
sleep 4
PID="$(pgrep -f 'MacOS/Plenara' | head -1)"
[ -n "$PID" ] || { echo "!! app did not start"; exit 1; }

echo "== leak-check: soaking PID $PID for ${SECS}s (bound ${BOUND_MB}MB) =="
BEFORE="$(phys_mb "$PID")"
STEP=$(( SECS / 5 )); [ "$STEP" -lt 1 ] && STEP=1
for _ in 1 2 3 4 5; do
  sleep "$STEP"
  osascript -e 'tell application "Plenara" to activate' 2>/dev/null || true
  M="$(phys_mb "$PID")"; echo "   phys_footprint = ${M}MB"
  pgrep -qf 'MacOS/Plenara' || { echo "!! app exited mid-soak"; exit 1; }
done
AFTER="$(phys_mb "$PID")"
kill "$PID" 2>/dev/null || true

GROWTH=$(( AFTER - BEFORE ))
echo "== before=${BEFORE}MB after=${AFTER}MB growth=${GROWTH}MB (bound ${BOUND_MB}MB) =="
if [ "$GROWTH" -ge "$BOUND_MB" ]; then
  echo "!! LEAK: phys_footprint grew ${GROWTH}MB over ${SECS}s of visible animation." >&2
  exit 1
fi
echo "== OK — bounded. =="
