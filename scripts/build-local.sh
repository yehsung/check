#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift build -c release >&2

APP_DIR="$ROOT/dist/check.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

rm -rf "$APP_DIR"
mkdir -p "$BIN_DIR" "$RES_DIR"
cp "$ROOT/.build/release/check" "$BIN_DIR/check"

if [[ -n "${CHECK_SUPABASE_ANON_KEY:-}" ]]; then
  CONFIG_PLIST="$RES_DIR/CheckConfig.plist"
  plutil -create xml1 "$CONFIG_PLIST"
  plutil -insert CHECK_SUPABASE_ANON_KEY -string "$CHECK_SUPABASE_ANON_KEY" "$CONFIG_PLIST"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>check</string>
  <key>CFBundleIdentifier</key>
  <string>kingcheck</string>
  <key>CFBundleName</key>
  <string>check</string>
  <key>CFBundleDisplayName</key>
  <string>check</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
