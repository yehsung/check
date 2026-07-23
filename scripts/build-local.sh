#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 단독 실행 시에도 anon key가 번들에 주입되도록 .env.local을 읽는다 (package-local.sh와 동일 패턴).
if [[ -z "${CHECK_SUPABASE_ANON_KEY:-}" && -f "$ROOT/.env.local" ]]; then
  set -a
  source "$ROOT/.env.local"
  set +a
fi

# 유니버설(arm64+x86_64) 빌드 — 인텔 맥 팀원도 실행 가능해야 한다.
# --arch 를 두 개 주면 산출물이 .build/apple/Products/Release/ 로 들어간다(단일 arch 경로와 다름).
swift build -c release --arch arm64 --arch x86_64 >&2
BUILD_PRODUCTS="$ROOT/.build/apple/Products/Release"

APP_DIR="$ROOT/dist/aing-check.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

rm -rf "$APP_DIR"
mkdir -p "$BIN_DIR" "$RES_DIR"
cp "$BUILD_PRODUCTS/check" "$BIN_DIR/check"
lipo -info "$BIN_DIR/check" >&2

# SwiftPM 리소스 번들(캐릭터 이미지)을 앱 번들 Resources로 복사한다.
# Bundle.module 접근자가 Bundle.main.resourceURL 후보를 탐색하므로
# codesign 이전에 Contents/Resources/ 아래에 있어야 한다.
RESOURCE_BUNDLE="$BUILD_PRODUCTS/check_check.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$RES_DIR/"
else
  echo "warning: resource bundle not found at $RESOURCE_BUNDLE" >&2
fi

if [[ -n "${CHECK_SUPABASE_ANON_KEY:-}" ]]; then
  CONFIG_PLIST="$RES_DIR/CheckConfig.plist"
  plutil -create xml1 "$CONFIG_PLIST"
  plutil -insert CHECK_SUPABASE_ANON_KEY -string "$CHECK_SUPABASE_ANON_KEY" "$CONFIG_PLIST"
fi

# 앱 아이콘 (원본: packaging/appicon/icon-1024.png → iconutil 산출물 커밋본)
cp "$ROOT/packaging/appicon/AppIcon.icns" "$RES_DIR/AppIcon.icns"

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
  <string>aing-check</string>
  <key>CFBundleDisplayName</key>
  <string>aing-check</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.3</string>
  <key>CFBundleVersion</key>
  <string>12</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

# Apple Silicon에서 미서명 번들은 실행이 막히거나 Gatekeeper 경험이 나빠지므로
# ad-hoc 서명(--sign -)을 남긴다. Developer ID 서명/공증은 범위 밖(README 참고).
codesign --force --deep --sign - "$APP_DIR" >&2
codesign --verify --deep --strict "$APP_DIR" >&2

echo "$APP_DIR"
