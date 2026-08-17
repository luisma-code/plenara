#!/usr/bin/env bash
# Plenara local quality gate (Spec 09 §8.4, solo-project path — "steps run as a local pre-push
# script with identical semantics until a hosted runner exists"). Fails on any step.
#
# Usage:  bash tool/precheck.sh
set -euo pipefail

# The quality gate is hermetic. In particular, never let a developer's live BYOK key reach a test
# matcher: an assertion failure prints its unexpected actual value. Config precedence itself is
# covered with an injected environment map in config_test.dart.
unset ANTHROPIC_API_KEY PLENARA_DATA PLENARA_FREE || true

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

echo "== [1/12] analyze v0 (lib bin test) =="
( cd "$ROOT/v0" && "$DART" analyze lib bin test )

echo "== [2/12] import-lint (dependency-rule layering gate, §8.4 step 5) =="
( cd "$ROOT/v0" && "$DART" bin/import_lint.dart )

echo "== [3/12] v0 tests + coverage gate (incl. the 05a conformance suite) =="
( cd "$ROOT/v0" \
    && "$DART" test --coverage=coverage \
    && "$DART" run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info \
        --report-on=lib --packages=.dart_tool/package_config.json \
    && "$DART" bin/coverage_check.dart )

# Resolve Flutter packages exactly once. Offline-first makes an already-provisioned
# development/CI machine independent of pub.dev availability; a fresh machine falls
# back to the network. Every later Flutter command uses --no-pub so the gate has one
# dependency boundary rather than five intermittent network points.
echo "== [app-deps] resolve Flutter packages once (offline cache, then network fallback) =="
( cd "$ROOT/app" && "$FLUTTER" pub get --offline ) || \
  ( cd "$ROOT/app" && "$FLUTTER" pub get )

echo "== [4/12] analyze app (lib test integration_test tool) =="
( cd "$ROOT/app" && "$FLUTTER" analyze --no-pub lib test integration_test tool )

# Render leak guard: the presence paint() runs ~60fps forever, so a per-frame native SHADER there
# (a ui.Gradient created every frame, never disposed) leaks GPU memory unboundedly while visible —
# the exact class that shipped once. dart:ui Shaders aren't leak-tracker-visible and can't be safely
# disposed from a CustomPainter, so the rule is: NO shader creation in paint() (cache it, or draw
# without one — the aura uses the cached sprite). This static check enforces it (comments excluded;
# the one-time sprite gradient in _makeSprite is outside paint() and correctly ignored). The Dart
# Picture/Image leak class is gated dynamically by app/test/render_resource_test.dart.
echo "== [5/12] render guard: no per-frame shader in plena.dart paint() =="
if awk '/void paint\(Canvas/,/^  }/' "$ROOT/app/lib/plena.dart" | grep -vE '^[[:space:]]*//' \
     | grep -qE 'ui\.Gradient|ui\.Shader|\.createShader\('; then
  echo "!! A shader is created inside plena.dart paint() — that's the per-frame GPU-leak class." >&2
  echo "   Cache it outside the hot path, or draw without a shader (see the aura's sprite approach)." >&2
  exit 1
fi

echo "== [6/12] visual verifier unit tests (including RGBA composition calibration) =="
python3 -m unittest "$ROOT/app/tool/test_gesture_contact_sheet.py"

echo "== [7/12] app widget tests =="
( cd "$ROOT/app" && "$FLUTTER" test --no-pub )

echo "== [8/12] external channel reachability (diagnostics + internal tools fail closed) =="
( cd "$ROOT/app" && "$FLUTTER" test --no-pub \
    --dart-define=PLENARA_CHANNEL=external test/external_channel_test.dart )

echo "== [9/12] host-OS build (the 'it still builds' floor) =="
case "$(uname -s)" in
  Darwin) TARGET=macos ;;
  MINGW*|MSYS*|CYGWIN*|Windows*) TARGET=windows ;;
  *) TARGET=linux ;;
esac
( cd "$ROOT/app" && "$FLUTTER" build "$TARGET" --debug --no-pub )

# The real-engine/GPU render smoke — the ONLY coverage of the animated presence + comet-trail
# offscreen buffer (toImageSync) + veilYield corner transition. Headless widget tests build the
# presence with animate:false, so a native raster crash there (the list-reply crash) is invisible to
# them; this runs the actual raster path on the host desktop. (linux has no runner in the matrix.)
if [ "$TARGET" != "linux" ]; then
  echo "== [10/12] integration test (real engine/GPU render smoke) =="
  ( cd "$ROOT/app" && "$FLUTTER" test --no-pub integration_test/render_test.dart -d "$TARGET" )
else
  echo "== [10/12] integration test SKIPPED (no desktop device on $TARGET) =="
fi

echo "== [11/12] secret scan (no BYOK/API keys in tracked files) =="
if git -C "$ROOT" grep -nE "sk-ant-[A-Za-z0-9]{20}" -- . >/dev/null 2>&1; then
  echo "!! SECRET DETECTED in a tracked file — aborting." >&2
  exit 1
fi

echo "== [12/12] conformance ratchet (05a N/60, no decrease) =="
( cd "$ROOT/v0" && "$DART" run bin/conformance_count.dart )

echo ""
echo "== ALL GREEN — analyze clean, tests pass, coverage floor met, app builds, no secrets. Safe to push. =="
