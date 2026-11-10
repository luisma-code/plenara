#!/usr/bin/env bash
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(git rev-parse --show-toplevel)"
SIMULATOR_ID="${PLENARA_SIMULATOR_ID:-BB42F29A-928B-4B9E-BD39-160B70249D4F}"
mkdir -p .tmp .build
xcrun simctl bootstatus "$SIMULATOR_ID" -b > .tmp/simulator-boot.log
(cd ios && xcodegen generate)
xcodebuild -project ios/Plenara.xcodeproj -scheme Plenara -configuration Release \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath .build/simulator \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES build-for-testing > .tmp/native-build.log 2>&1
xcrun simctl install "$SIMULATOR_ID" .build/simulator/Build/Products/Release-iphonesimulator/Plenara.app
# A fresh runner prevents a previous UI test executable from surviving an update.
RUNNER_ID=com.plenara.plenaraApp.UITests.xctrunner
xcrun simctl terminate "$SIMULATOR_ID" "$RUNNER_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$SIMULATOR_ID" "$RUNNER_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_ID" .build/simulator/Build/Products/Release-iphonesimulator/PlenaraUITests-Runner.app
if [ "${PLENARA_CONTACTS_DENIED:-0}" = 1 ]; then
  xcrun simctl privacy "$SIMULATOR_ID" revoke contacts com.plenara.plenaraApp
else
  xcrun simctl privacy "$SIMULATOR_ID" grant contacts com.plenara.plenaraApp
fi
python3 tool/watch-memory.py "$SIMULATOR_ID" &
WATCH_PID=$!
cleanup() { xcrun simctl terminate "$SIMULATOR_ID" "$RUNNER_ID" >/dev/null 2>&1 || true; xcrun simctl terminate "$SIMULATOR_ID" com.plenara.plenaraApp >/dev/null 2>&1 || true; kill "$WATCH_PID" >/dev/null 2>&1 || true; wait "$WATCH_PID" 2>/dev/null || true; }
trap cleanup EXIT
SDK_VERSION=$(xcrun --sdk iphonesimulator --show-sdk-version)
TEST_MANIFEST=".build/simulator/Build/Products/Plenara_iphonesimulator${SDK_VERSION}-$(uname -m).xctestrun"
python3 - "$TEST_MANIFEST" <<'PYCONTEXT'
import hashlib,json,plistlib,sys
from pathlib import Path
manifest=Path(sys.argv[1]); data=plistlib.load(manifest.open('rb')); products=manifest.parent.resolve()
records={}
for name,info in data.items():
    if not isinstance(info,dict) or 'TestHostPath' not in info: continue
    host=Path(info['TestHostPath'].replace('__TESTROOT__',str(products)))
    bundle=Path(info['TestBundlePath'].replace('__TESTHOST__',str(host)))
    assert host.parent==products/'Release-iphonesimulator' and host.is_dir(), 'Unexpected native test product'
    executable=plistlib.load((bundle/'Info.plist').open('rb'))['CFBundleExecutable']
    records[name]={'host':str(host),'bundle':str(bundle),'binarySHA256':hashlib.sha256((bundle/executable).read_bytes()).hexdigest()}
assert set(records)=={'PlenaraTests','PlenaraUITests'}, 'Both current test products must be present'
Path('.tmp/native-test-context.json').write_text(json.dumps({'manifest':str(manifest),'manifestSHA256':hashlib.sha256(manifest.read_bytes()).hexdigest(),'targets':records},indent=2)+'\n')
PYCONTEXT
RESULT=".build/native-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -xctestrun "$TEST_MANIFEST" -configuration Release \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath .build/simulator \
  -parallel-testing-enabled NO -resultBundlePath "$RESULT" CODE_SIGNING_ALLOWED=NO \
  test-without-building "$@" > .tmp/native-tests.log 2>&1
xcrun xcresulttool get test-results summary --path "$RESULT" > .tmp/native-summary.json
python3 - <<'PYRESULT'
import json
summary = json.load(open('.tmp/native-summary.json'))
assert summary['passedTests'] > 0, 'No native tests executed; check test selection and installed runner'
assert summary['failedTests'] == 0 and summary['result'] == 'Passed', 'Native result did not pass'
PYRESULT
kill -0 "$WATCH_PID" 2>/dev/null || { echo 'The simulator memory guard stopped or failed.' >&2; exit 1; }
printf '%s\n' "$RESULT" > .tmp/latest-native-result.txt
printf 'Native Release checks passed. Results: %s\n' "$RESULT"
