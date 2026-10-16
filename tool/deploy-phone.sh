#!/usr/bin/env bash
# Delivery only: build a signed Release app, then install. Never launch or test.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
mkdir -p .tmp .build
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_AQMT4FFHKW.p8"
PHONE_ID=D79FABC7-9CA8-5170-AF1F-58FB541002B6
(cd ios && xcodegen generate)
xcodebuild -project ios/Plenara.xcodeproj -scheme Plenara -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath .build/phone \
  -allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID AQMT4FFHKW \
  -authenticationKeyIssuerID 12ee92f1-bd97-4747-bc50-87c476d9eb9b \
  build > .tmp/phone-build.log 2>&1
APP=.build/phone/Build/Products/Release-iphoneos/Plenara.app
[ -d "$APP" ] || { echo 'Signed app was not produced.' >&2; exit 1; }
codesign --verify --deep --strict "$APP"
du -sh "$APP"
xcrun devicectl --timeout 60 device install app --device "$PHONE_ID" "$APP" \
  --json-output .tmp/phone-install.json > .tmp/phone-install.log 2>&1
printf 'Installed Plenara on Aluminum Monster. The app was not launched.\n'
