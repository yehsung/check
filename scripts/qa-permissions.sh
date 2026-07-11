#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT/dist/check.app}"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

test -f "$INFO_PLIST"

if /usr/libexec/PlistBuddy -c "Print :NSCameraUsageDescription" "$INFO_PLIST" >/dev/null 2>&1; then
  echo "unexpected Camera permission"
  exit 1
fi

for key in \
  NSMicrophoneUsageDescription \
  NSLocationWhenInUseUsageDescription \
  NSLocationAlwaysAndWhenInUseUsageDescription \
  NSScreenCaptureUsageDescription \
  NSAppleEventsUsageDescription; do
  if /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" >/dev/null 2>&1; then
    echo "unexpected permission key: $key"
    exit 1
  fi
done

if /usr/libexec/PlistBuddy -c "Print :LSUIElement" "$INFO_PLIST" | grep -q "true"; then
  echo "permissions ok; LSUIElement true; no Accessibility/Screen Recording/Camera/Microphone/Location prompts"
else
  echo "LSUIElement is not true"
  exit 1
fi
