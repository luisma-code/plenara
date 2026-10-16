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
if [ "${PLENARA_CONTACTS_DENIED:-0}" = 1 ]; then
  xcrun simctl privacy "$SIMULATOR_ID" revoke contacts com.plenara.plenaraApp
else
  xcrun simctl privacy "$SIMULATOR_ID" grant contacts com.plenara.plenaraApp
fi
python3 tool/watch-memory.py "$SIMULATOR_ID" &
WATCH_PID=$!
cleanup() { xcrun simctl terminate "$SIMULATOR_ID" com.plenara.plenaraApp >/dev/null 2>&1 || true; kill "$WATCH_PID" >/dev/null 2>&1 || true; wait "$WATCH_PID" 2>/dev/null || true; }
trap cleanup EXIT
RESULT=".build/native-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project ios/Plenara.xcodeproj -scheme Plenara -configuration Release \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath .build/simulator \
  -parallel-testing-enabled NO -resultBundlePath "$RESULT" CODE_SIGNING_ALLOWED=NO \
  test-without-building "$@" > .tmp/native-tests.log 2>&1
kill -0 "$WATCH_PID" 2>/dev/null || { echo 'The simulator memory guard stopped or failed.' >&2; exit 1; }
printf '%s\n' "$RESULT" > .tmp/latest-native-result.txt
printf 'Native Release checks passed. Results: %s\n' "$RESULT"
