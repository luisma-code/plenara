#!/usr/bin/env bash
# Plenara local quality gate (Spec 09 §8.4, solo-project path — "steps run as a local pre-push
# script with identical semantics until a hosted runner exists"). Fails on any step.
#
# Usage:  bash tool/precheck.sh
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
DART="$ROOT/.tools/dart-sdk/bin/dart.exe"
FLUTTER="$ROOT/.tools/flutter/bin/flutter.bat"

echo "== [1/6] analyze v0 (lib bin test) =="
( cd "$ROOT/v0" && "$DART" analyze lib bin test )

echo "== [2/6] v0 tests + coverage gate (incl. the 05a conformance suite) =="
( cd "$ROOT/v0" \
    && "$DART" test --coverage=coverage \
    && "$DART" run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info \
        --report-on=lib --packages=.dart_tool/package_config.json \
    && "$DART" bin/coverage_check.dart )

echo "== [3/6] analyze app (lib test) =="
( cd "$ROOT/app" && "$FLUTTER" analyze lib test )

echo "== [4/6] app widget tests =="
( cd "$ROOT/app" && "$FLUTTER" test )

echo "== [5/6] windows build (the 'it still builds' floor) =="
( cd "$ROOT/app" && "$FLUTTER" build windows --debug )

echo "== [6/6] secret scan (no BYOK/API keys in tracked files) =="
if git -C "$ROOT" grep -nE "sk-ant-[A-Za-z0-9]{20}" -- . >/dev/null 2>&1; then
  echo "!! SECRET DETECTED in a tracked file — aborting." >&2
  exit 1
fi

echo ""
echo "== ALL GREEN — analyze clean, tests pass, coverage floor met, app builds, no secrets. Safe to push. =="
