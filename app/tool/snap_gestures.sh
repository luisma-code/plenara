#!/usr/bin/env bash
# Gesture dev-loop: render Plena's gestures headlessly (the REAL plena.dart + glyphs.dart), freeze
# each at 8 points across its sequence, and montage them into contact sheets to judge by eye —
# is it the intended symbol? does it read as fluid/organic and SHED FROM Plena, not disembodied?
#
# Usage (from app/):   tool/snap_gestures.sh [all | heart | wave,candle]   (default: all)
# Output:              .gesture-snaps/frames/<glyph>/NN-of-08.png  +  .gesture-snaps/sheets/*.png
# The snaps are a temp effect of iteration (.gitignored) — regenerate any time.
set -euo pipefail
cd "$(dirname "$0")/.."                       # -> app/
GLYPH="${1:-all}"
OUT=".gesture-snaps"
FLUTTER="../.tools/flutter/bin/flutter.bat"
[ -x "$FLUTTER" ] || FLUTTER="flutter"        # fall back to PATH

rm -rf "$OUT"
PLENA_GLYPH="$GLYPH" PLENA_SNAP_DIR="$OUT/frames" "$FLUTTER" test test/gesture_snap.dart
python tool/gesture_contact_sheet.py "$OUT/frames" "$OUT/sheets"
echo "Review the contact sheets in $OUT/sheets/"
