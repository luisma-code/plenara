#!/usr/bin/env bash
# Plenara local quality gate (Spec 09 §8.4, solo-project path — "steps run as a local pre-push
# script with identical semantics until a hosted runner exists"). Fails on any step.
#
# Usage:  bash tool/precheck.sh
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
# Prefer the vendored Windows toolchain if present; else fall back to PATH (macOS / Linux / CI).
if [ -x "$ROOT/.tools/dart-sdk/bin/dart.exe" ]; then
  DART="$ROOT/.tools/dart-sdk/bin/dart.exe"
  FLUTTER="$ROOT/.tools/flutter/bin/flutter.bat"
else
  DART="dart"
  FLUTTER="flutter"
fi

echo "== [pre] bundled seed assets in sync with v0/data =="
bash "$ROOT/tool/sync_seed.sh" --check

echo "== [1/8] analyze v0 (lib bin test) =="
( cd "$ROOT/v0" && "$DART" analyze lib bin test )

echo "== [2/8] import-lint (dependency-rule layering gate, §8.4 step 5) =="
( cd "$ROOT/v0" && "$DART" bin/import_lint.dart )

echo "== [3/8] v0 tests + coverage gate (incl. the 05a conformance suite) =="
( cd "$ROOT/v0" \
    && "$DART" test --coverage=coverage \
    && "$DART" run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info \
        --report-on=lib --packages=.dart_tool/package_config.json \
    && "$DART" bin/coverage_check.dart )

echo "== [4/9] analyze app (lib test integration_test) =="
( cd "$ROOT/app" && "$FLUTTER" analyze lib test integration_test )

echo "== [5/9] app widget tests =="
( cd "$ROOT/app" && "$FLUTTER" test )

echo "== [6/9] host-OS build (the 'it still builds' floor) =="
case "$(uname -s)" in
  Darwin) TARGET=macos ;;
  MINGW*|MSYS*|CYGWIN*|Windows*) TARGET=windows ;;
  *) TARGET=linux ;;
esac
( cd "$ROOT/app" && "$FLUTTER" build "$TARGET" --debug )

# The real-engine/GPU render smoke — the ONLY coverage of the animated presence + comet-trail
# offscreen buffer (toImageSync) + veilYield corner transition. Headless widget tests build the
# presence with animate:false, so a native raster crash there (the list-reply crash) is invisible to
# them; this runs the actual raster path on the host desktop. (linux has no runner in the matrix.)
if [ "$TARGET" != "linux" ]; then
  echo "== [7/9] integration test (real engine/GPU render smoke) =="
  ( cd "$ROOT/app" && "$FLUTTER" test integration_test -d "$TARGET" )
else
  echo "== [7/9] integration test SKIPPED (no desktop device on $TARGET) =="
fi

echo "== [8/9] secret scan (no BYOK/API keys in tracked files) =="
if git -C "$ROOT" grep -nE "sk-ant-[A-Za-z0-9]{20}" -- . >/dev/null 2>&1; then
  echo "!! SECRET DETECTED in a tracked file — aborting." >&2
  exit 1
fi

echo "== [9/9] conformance ratchet (05a N/60, no decrease) =="
COUNT=$( cd "$ROOT/v0" && "$DART" test test/spec05a_test.dart 2>&1 | grep -oE '\+[0-9]+' | tail -1 | tr -d + )
BASE=$( cat "$ROOT/v0/test/conformance-baseline.txt" )
echo "conformance: $COUNT passing (baseline $BASE)"
if [ "$COUNT" -lt "$BASE" ]; then echo "!! CONFORMANCE REGRESSED ($COUNT < $BASE)" >&2; exit 1; fi
if [ "$COUNT" -gt "$BASE" ]; then echo "note: conformance rose to $COUNT — bump v0/test/conformance-baseline.txt"; fi

echo ""
echo "== ALL GREEN — analyze clean, tests pass, coverage floor met, app builds, no secrets. Safe to push. =="
