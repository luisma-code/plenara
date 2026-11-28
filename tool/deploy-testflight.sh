#!/usr/bin/env bash
# Explicit TestFlight upload. Does not launch or install on a physical phone.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source tool/require-storage.sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_AQMT4FFHKW.p8"
mkdir -p .tmp/testflight .build/testflight-candidate
# A prior upload receipt must not appear to describe the current run.
rm -f .tmp/testflight/archive.log .tmp/testflight/export.log .tmp/testflight/validate.log .tmp/testflight/upload.log .tmp/testflight/package.json
python3 tool/testflight.py status
(cd ios && xcodegen generate)
xcodebuild -project ios/Plenara.xcodeproj -scheme Plenara -configuration Release \
  -destination 'generic/platform=iOS' -archivePath .build/testflight-candidate/Plenara.xcarchive \
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
xcodebuild -exportArchive -archivePath .build/testflight-candidate/Plenara.xcarchive \
  -exportPath .build/testflight-candidate/export -exportOptionsPlist .tmp/testflight/ExportOptions.plist \
  -allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID AQMT4FFHKW \
  -authenticationKeyIssuerID 12ee92f1-bd97-4747-bc50-87c476d9eb9b \
  > .tmp/testflight/export.log 2>&1
SDK_VERSION=$(xcrun --sdk iphoneos --show-sdk-version)
python3 - "$SDK_VERSION" .build/testflight-candidate/export/Plenara.ipa > .tmp/testflight/package.json <<'PYSDK'
import hashlib, json, plistlib, re, shutil, subprocess, sys, tempfile
from pathlib import Path
from zipfile import ZipFile
sdk, ipa = sys.argv[1:]
with ZipFile(ipa) as package:
    prefix = 'Payload/Plenara.app/'
    info = plistlib.loads(package.read(prefix + 'Info.plist'))
    if info['DTSDKName'] != 'iphoneos' + sdk:
        raise SystemExit('SDK mismatch: exported package does not use the selected iPhone SDK.')
    with tempfile.TemporaryDirectory(prefix='iphone-sdk-', dir='.tmp') as scratch:
        binary = Path(scratch) / 'Plenara'
        with package.open(prefix + info['CFBundleExecutable']) as src, binary.open('wb') as dst:
            shutil.copyfileobj(src, dst, 1024 * 1024)
        commands = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(binary)], text=True)
        binary_sdks = re.findall(r'^\s*sdk\s+(\S+)', commands, re.M)
        platforms = re.findall(r'^\s*platform\s+(\S+)', commands, re.M)
        if not binary_sdks or not platforms or any(value != sdk for value in binary_sdks) or any(value != 'IOS' for value in platforms):
            raise SystemExit('SDK mismatch: executable load commands do not match the selected iPhone SDK.')
receipt = {key: info.get(key) for key in ['CFBundleVersion', 'CFBundleShortVersionString', 'CFBundleIdentifier', 'DTSDKName', 'DTXcodeBuild', 'MinimumOSVersion', 'UIDeviceFamily']}
digest = hashlib.sha256()
with open(ipa, 'rb') as src:
    for chunk in iter(lambda: src.read(1024 * 1024), b''):
        digest.update(chunk)
receipt.update({'binarySDKs': binary_sdks, 'ipaSHA256': digest.hexdigest()})
print(json.dumps(receipt, indent=2))
PYSDK
xcrun altool --validate-app --type ios -f .build/testflight-candidate/export/Plenara.ipa \
  --apiKey AQMT4FFHKW --apiIssuer 12ee92f1-bd97-4747-bc50-87c476d9eb9b \
  > .tmp/testflight/validate.log 2>&1
# Apple accepted the candidate package. Replace the previous local usable build.
if [ -e .build/testflight-replaced ]; then echo 'A previous build replacement needs inspection.' >&2; exit 1; fi
if [ -d .build/testflight ]; then mv .build/testflight .build/testflight-replaced; fi
mv .build/testflight-candidate .build/testflight
rm -rf .build/testflight-replaced
xcrun altool --upload-app --type ios -f .build/testflight/export/Plenara.ipa \
  --apiKey AQMT4FFHKW --apiIssuer 12ee92f1-bd97-4747-bc50-87c476d9eb9b \
  > .tmp/testflight/upload.log 2>&1
BUILD_NUMBER=$(python3 - <<'PYBUILD'
import plistlib
p = '.build/testflight/Plenara.xcarchive/Products/Applications/Plenara.app/Info.plist'
print(plistlib.load(open(p, 'rb'))['CFBundleVersion'])
PYBUILD
)
python3 tool/testflight.py release "$BUILD_NUMBER"
