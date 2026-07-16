#!/usr/bin/env bash
# Export the release archive to a signed IPA and upload it to TestFlight — using ONLY an App Store
# Connect API key (no interactive Xcode/Apple login). `xcodebuild -allowProvisioningUpdates` with the
# key creates the iOS Distribution cert + App Store profile on first run; altool uploads with the
# same key. Run AFTER `flutter build ipa --release` (which builds the .xcarchive even when its own
# export step fails on signing).
#
# One-time setup (Luis, in App Store Connect → Users and Access → Integrations → App Store Connect API):
#   generate a key with **Admin** or **App Manager** access, download the .p8 ONCE, note Key ID + Issuer ID.
# Then drop them in tool/.testflight.env (gitignored):
#   ASC_KEY_ID=XXXXXXXXXX
#   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   ASC_KEY_PATH=/absolute/path/to/AuthKey_XXXXXXXXXX.p8
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
ENV_FILE="$ROOT/tool/.testflight.env"
[ -f "$ENV_FILE" ] && set -a && . "$ENV_FILE" && set +a

: "${ASC_KEY_ID:?set ASC_KEY_ID (App Store Connect API key id)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (App Store Connect issuer id)}"
: "${ASC_KEY_PATH:?set ASC_KEY_PATH (path to the AuthKey_*.p8 file)}"
[ -f "$ASC_KEY_PATH" ] || { echo "key file not found: $ASC_KEY_PATH" >&2; exit 1; }

ARCHIVE="$ROOT/app/build/ios/archive/Runner.xcarchive"
[ -d "$ARCHIVE" ] || { echo "no archive — run 'flutter build ipa --release' in app/ first" >&2; exit 1; }
OUT="$ROOT/app/build/ios/ipa"
mkdir -p "$OUT"

# altool also looks for the key here; xcodebuild takes an explicit path.
KEYDIR="$HOME/.appstoreconnect/private_keys"
mkdir -p "$KEYDIR"
cp "$ASC_KEY_PATH" "$KEYDIR/AuthKey_${ASC_KEY_ID}.p8"

echo "== exporting a signed App Store IPA (auto-creates the distribution cert + profile on first run) =="
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$OUT" \
  -exportOptionsPlist "$ROOT/tool/ExportOptions.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

IPA="$(ls -t "$OUT"/*.ipa 2>/dev/null | head -1 || true)"
[ -n "$IPA" ] || { echo "export produced no IPA" >&2; exit 1; }
echo "Exported: $IPA"

echo "== validating =="
xcrun altool --validate-app -f "$IPA" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "== uploading to TestFlight =="
xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "Done — Apple processes it (~5–15 min), then it shows in TestFlight on the phone."
