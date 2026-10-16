#!/usr/bin/env bash
# Explicit TestFlight upload. Does not launch or install on a physical phone.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_AQMT4FFHKW.p8"
mkdir -p .tmp/testflight .build/testflight
python3 tool/testflight.py status
(cd ios && xcodegen generate)
xcodebuild -project ios/Plenara.xcodeproj -scheme Plenara -configuration Release \
  -destination 'generic/platform=iOS' -archivePath .build/testflight/Plenara.xcarchive \
  -derivedDataPath .build/testflight-derived -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" -authenticationKeyID AQMT4FFHKW \
  -authenticationKeyIssuerID 12ee92f1-bd97-4747-bc50-87c476d9eb9b \
  archive > .tmp/testflight/archive.log 2>&1
python3 - <<'PY'
import plistlib
plistlib.dump({'method':'app-store-connect','destination':'export','teamID':'7V63BZ39HU',
              'signingStyle':'automatic','manageAppVersionAndBuildNumber':False,
              'uploadSymbols':True},open('.tmp/testflight/ExportOptions.plist','wb'))
PY
xcodebuild -exportArchive -archivePath .build/testflight/Plenara.xcarchive \
  -exportPath .build/testflight/export -exportOptionsPlist .tmp/testflight/ExportOptions.plist \
  -allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID AQMT4FFHKW \
  -authenticationKeyIssuerID 12ee92f1-bd97-4747-bc50-87c476d9eb9b \
  > .tmp/testflight/export.log 2>&1
xcrun altool --validate-app --type ios -f .build/testflight/export/Plenara.ipa \
  --apiKey AQMT4FFHKW --apiIssuer 12ee92f1-bd97-4747-bc50-87c476d9eb9b \
  > .tmp/testflight/validate.log 2>&1
xcrun altool --upload-app --type ios -f .build/testflight/export/Plenara.ipa \
  --apiKey AQMT4FFHKW --apiIssuer 12ee92f1-bd97-4747-bc50-87c476d9eb9b \
  > .tmp/testflight/upload.log 2>&1
printf 'Uploaded. Check processing with python3 tool/testflight.py status BUILD.\n'
printf 'When VALID, distribute with python3 tool/testflight.py distribute BUILD.\n'
