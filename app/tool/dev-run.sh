#!/usr/bin/env bash
# Local macOS dev build + STABLE code-signing + launch.
#
# WHY: macOS drops a TCC grant (Microphone / Speech Recognition) whenever the app's signature
# changes — and a plain `flutter build macos` signs AD-HOC, producing a new signature every build.
# So each rebuild would make you re-grant mic access. This script re-signs the freshly-built app with
# a stable self-signed identity ("Plenara Dev"), whose designated requirement is constant across
# rebuilds (bundle id + cert leaf), so the permission sticks.
#
# CI-SAFE: the re-sign only happens if the "Plenara Dev" identity exists on this machine. On CI /
# any other machine it's a no-op — the app just stays ad-hoc. Nothing here is required to build.
#
# ONE-TIME SETUP (already done on Luis's Mac): a self-signed codesigning cert "Plenara Dev" lives in
# ~/Library/Keychains/plenara-signing.keychain-db (password: plenara), added to the keychain search
# list. That keychain locks on reboot; this script unlocks it automatically.
#
# Usage:  bash app/tool/dev-run.sh   [--no-open]
set -euo pipefail
cd "$(dirname "$0")/.."   # -> app/

KEYCHAIN="$HOME/Library/Keychains/plenara-signing.keychain-db"
IDENTITY="Plenara Dev"
APP="build/macos/Build/Products/Debug/Plenara.app"

flutter build macos --debug

if [ -f "$KEYCHAIN" ]; then
  security unlock-keychain -p plenara "$KEYCHAIN" 2>/dev/null || true
fi
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY" \
   || security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  echo "==> Re-signing with '$IDENTITY' (stable identity → mic/Speech permission persists)…"
  codesign --force --deep --sign "$IDENTITY" "$APP"
  codesign -dvv "$APP" 2>&1 | grep -i "Authority=$IDENTITY" >/dev/null \
    && echo "    ok: $(codesign -d -r- "$APP" 2>&1 | grep designated)"
else
  echo "==> note: '$IDENTITY' identity not found — app stays ad-hoc (mic permission resets on rebuild)."
fi

if [ "${1:-}" != "--no-open" ]; then
  echo "==> Launching Plenara…"
  open "$APP"
fi
