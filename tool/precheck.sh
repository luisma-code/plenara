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

echo "== [4/8] analyze app (lib test) =="
( cd "$ROOT/app" && "$FLUTTER" analyze lib test )

echo "== [5/8] app widget tests =="
( cd "$ROOT/app" && "$FLUTTER" test )

echo "== [6/8] host-OS build (the 'it still builds' floor) =="
case "$(uname -s)" in
  Darwin) TARGET=macos ;;
  MINGW*|MSYS*|CYGWIN*|Windows*) TARGET=windows ;;
  *) TARGET=linux ;;
esac
( cd "$ROOT/app" && "$FLUTTER" build "$TARGET" --debug )

echo "== [7/8] secret scan (no BYOK/API keys in tracked files) =="
if git -C "$ROOT" grep -nE "sk-ant-[A-Za-z0-9]{20}" -- . >/dev/null 2>&1; then
  echo "!! SECRET DETECTED in a tracked file — aborting." >&2
  exit 1
fi

echo "== [8/8] conformance ratchet (05a N/60, no decrease) =="
COUNT=$( cd "$ROOT/v0" && "$DART" test test/spec05a_test.dart 2>&1 | grep -oE '\+[0-9]+' | tail -1 | tr -d + )
BASE=$( cat "$ROOT/v0/test/conformance-baseline.txt" )
echo "conformance: $COUNT passing (baseline $BASE)"
if [ "$COUNT" -lt "$BASE" ]; then echo "!! CONFORMANCE REGRESSED ($COUNT < $BASE)" >&2; exit 1; fi
if [ "$COUNT" -gt "$BASE" ]; then echo "note: conformance rose to $COUNT — bump v0/test/conformance-baseline.txt"; fi

echo ""
echo "== ALL GREEN — analyze clean, tests pass, coverage floor met, app builds, no secrets. Safe to push. =="
