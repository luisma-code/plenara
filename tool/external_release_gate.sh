#!/usr/bin/env bash
# Build and inspect the actual external AOT artifact. This is deliberately
# separate from the faster development precheck: no external build is promoted
# without this gate and its generated revision-bound manifest.
set -euo pipefail

unset ANTHROPIC_API_KEY PLENARA_DATA PLENARA_FREE || true
ROOT="$(git rev-parse --show-toplevel)"
ALLOW_DIRTY=()
if [ "${1:-}" = "--allow-dirty" ]; then
  ALLOW_DIRTY=(--allow-dirty)
fi
REVISION="$(git -C "$ROOT" rev-parse HEAD)"

scan_forbidden() {
  local target="$1"
  local quiet="${2:-}"
  local found=0
  local pattern
  for pattern in \
    PLENARA_INTERNAL_RAW_CONTENT_CANARY \
    'Share raw diagnostics' \
    'Dev harness' \
    'Tune Plena' \
    'WARNING: contains conversation text'; do
    if rg -aF -q "$pattern" "$target"; then
      if [ "$quiet" != "quiet" ]; then
        echo "!! external artifact contains internal-only marker: $pattern" >&2
      fi
      found=1
    fi
  done
  return "$found"
}

echo "== calibrate binary scanner with a known internal-content marker =="
CALIBRATION_DIR="$(mktemp -d)"
trap 'rm -rf "$CALIBRATION_DIR"' EXIT
printf '%s\n' 'PLENARA_INTERNAL_RAW_CONTENT_CANARY' > \
  "$CALIBRATION_DIR/known-bad.bin"
if scan_forbidden "$CALIBRATION_DIR/known-bad.bin" quiet; then
  echo '!! binary scanner accepted its known-bad calibration input' >&2
  exit 1
fi

echo "== external policy, accessibility/device matrix, and release assets =="
( cd "$ROOT/app" && flutter pub get --offline ) || \
  ( cd "$ROOT/app" && flutter pub get )
( cd "$ROOT/app" && flutter test --no-pub \
    --dart-define=PLENARA_CHANNEL=external test/external_channel_test.dart )
( cd "$ROOT/app" && flutter test --no-pub \
    test/device_accessibility_matrix_test.dart test/app_icon_test.dart )
plutil -lint "$ROOT/app/ios/Runner/PrivacyInfo.xcprivacy" \
  "$ROOT/app/macos/Runner/PrivacyInfo.xcprivacy"
jq -e '
  (.productName | length > 0) and
  (.subtitle | length > 0 and length <= 30) and
  (.description | length > 0) and
  (.privacyPolicyUrl | startswith("https://")) and
  (.supportUrl | startswith("https://")) and
  (.reviewNotes | length > 0)
' "$ROOT/releases/app-store-metadata.json" >/dev/null
test -s "$ROOT/PRIVACY.md"

echo "== external release AOT build =="
( cd "$ROOT/app" && flutter build macos --release --no-pub \
    --dart-define=PLENARA_CHANNEL=external \
    --dart-define=PLENARA_REVISION="$REVISION" )
BUNDLE="$ROOT/app/build/macos/Build/Products/Release/Plenara.app"
AOT="$BUNDLE/Contents/Frameworks/App.framework/Versions/A/App"
PRIVACY="$BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy"
test -f "$AOT"
test -f "$PRIVACY"
plutil -lint "$PRIVACY"

echo "== compiled reachability: no content diagnostics or dev surfaces =="
scan_forbidden "$AOT"
rg -aF -q 'Diagnostics capture and raw export are disabled in this external build.' "$AOT"

echo "== unsigned iOS external release compile (local only; never installed or launched) =="
( cd "$ROOT/app" && flutter build ios --release --no-codesign --no-pub \
    --dart-define=PLENARA_CHANNEL=external \
    --dart-define=PLENARA_REVISION="$REVISION" )
IOS_BUNDLE="$ROOT/app/build/ios/iphoneos/Runner.app"
IOS_AOT="$IOS_BUNDLE/Frameworks/App.framework/App"
IOS_PRIVACY="$IOS_BUNDLE/PrivacyInfo.xcprivacy"
test -f "$IOS_AOT"
test -f "$IOS_PRIVACY"
plutil -lint "$IOS_PRIVACY"
scan_forbidden "$IOS_AOT"
rg -aF -q 'Diagnostics capture and raw export are disabled in this external build.' "$IOS_AOT"

echo "== tracked secret and release-placeholder scan =="
if git -C "$ROOT" grep -nE 'sk-ant-[A-Za-z0-9]{20}' -- . >/dev/null 2>&1; then
  echo '!! secret-shaped value in tracked files' >&2
  exit 1
fi
if rg -n -i 'A new Flutter project|flutter_logo' \
  "$ROOT/app/lib" "$ROOT/app/ios/Runner" "$ROOT/app/macos/Runner"; then
  echo '!! Flutter placeholder content remains in production surfaces' >&2
  exit 1
fi

echo "== revision-bound release manifest =="
MANIFEST="$ROOT/app/build/release/release-manifest.json"
MANIFEST_ARGS=(
  --artifact "$IOS_AOT"
  --output "$MANIFEST"
  --channel external
)
if [ "${#ALLOW_DIRTY[@]}" -gt 0 ]; then
  MANIFEST_ARGS+=("${ALLOW_DIRTY[@]}")
fi
dart "$ROOT/tool/generate_release_manifest.dart" "${MANIFEST_ARGS[@]}"
jq -e '
  all(.migrations[]?[]?; test("^[0-9]+→[0-9]+$"))
' "$MANIFEST" >/dev/null
echo "== EXTERNAL RELEASE GATE GREEN =="
echo "Manifest: $MANIFEST"
