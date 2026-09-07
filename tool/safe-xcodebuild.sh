#!/usr/bin/env bash
# Keep ambient model/voice-provider credentials out of Xcode's verbose scheme
# environment dump. App Store Connect credentials remain available when a
# release command explicitly passes them as xcodebuild arguments.
set -euo pipefail

SENSITIVE_BUILD_VARS=(
  ANTHROPIC_API_KEY
  CARTESIA_API_KEY
  ELEVENLABS_API_KEY
  PLENARA_DATA
  PLENARA_FREE
)
unset "${SENSITIVE_BUILD_VARS[@]}" || true

if [ "${1:-}" = "--check-environment" ]; then
  remaining="$(/usr/bin/env | /usr/bin/cut -d= -f1 | \
    /usr/bin/grep -E '^(ANTHROPIC|CARTESIA|ELEVENLABS)_API_KEY$' || true)"
  if [ -n "$remaining" ]; then
    echo "unsafe xcodebuild environment: provider API key variable remains set" >&2
    exit 1
  fi
  echo "xcodebuild environment clean"
  exit 0
fi

exec /usr/bin/xcrun xcodebuild -quiet "$@"
