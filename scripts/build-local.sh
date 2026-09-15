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
swift build -c release --arch arm64 --arch x86_64 >&2
# 산출물 경로는 **SwiftPM 이 말해 준 값**을 쓴다. 예전엔 .build/apple/Products/Release 를 적어 두었는데, Xcode 27 의
# 빌드 시스템은 같은 명령의 산출물을 .build/out/Products/Release 에 둔다 — 적어 둔 경로에는 옛 빌드가 그대로 남아 있어
# 0.3.23 패키지에 0.3.22 바이너리와 리소스가 **조용히** 들어갔다(Info.plist 버전은 이 스크립트가 쓰니 0.3.23 으로 보였다,
# 2026-09-15 nm 으로 발견). 경로를 묻고, 아래에서 산출물이 소스보다 새것인지까지 확인한다.
BUILD_PRODUCTS="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
if [[ ! -f "$BUILD_PRODUCTS/check" ]]; then
  echo "error: 빌드 산출물이 없다: $BUILD_PRODUCTS/check" >&2
  exit 1
fi
# 캐시 빌드(소스 변경 없음)는 바이너리를 다시 쓰지 않으므로 '빌드 시작보다 새것'으로는 못 잰다. 대신 **어떤 소스보다도
# 새것**이어야 한다 — 소스 하나라도 산출물보다 새로우면 그 산출물은 이번 소스로 만든 것이 아니다.
STALE_SOURCE="$(find "$ROOT/Sources" "$ROOT/Package.swift" -type f -newer "$BUILD_PRODUCTS/check" | head -n 1)"
if [[ -n "$STALE_SOURCE" ]]; then
  echo "error: $BUILD_PRODUCTS/check 가 소스보다 오래됐다(예: $STALE_SOURCE) — 옛 산출물을 복사하려 한다" >&2
  exit 1
fi

APP_DIR="$ROOT/dist/aing-check.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

rm -rf "$APP_DIR"
mkdir -p "$BIN_DIR" "$RES_DIR"
cp "$BUILD_PRODUCTS/check" "$BIN_DIR/check"

# ★ 링크 SDK 스탬프를 **빌드한 SDK 로 고쳐 적는다.** Xcode 27 의 기본 빌드 시스템은 27.0 SDK 로 컴파일하면서 바이너리의
# LC_BUILD_VERSION 에 sdk 를 배포 최소 버전(14.0)으로 적는다(빈 패키지로도 재현, SDKROOT 로도 안 고쳐진다). AppKit·SwiftUI 는
# 그 숫자로 "옛 SDK 로 만든 앱"이라 판정해 호환 동작으로 돌아가고, 거기서는 MenuBarExtra 창이 콘텐츠가 줄어도 따라 줄지
# 않는다 — 0.3.23 에서 팝오버 위쪽이 비어 보이고 내용이 아래로 내려앉았다(2026-09-15 여러 사용자 신고. 최소 재현 앱의
# 스탬프만 14.0/26.5/27.0 으로 바꿔 14.0 에서만 재현되고 고친 사본은 정상임을 확인).
# `--build-system native` 는 답이 아니다 — `--arch` 를 둘 주면 native 를 줘도 기본 빌드 시스템으로 넘어가 똑같이 14.0 이다.
# 공증·버전·심볼 검사는 이 숫자를 안 보므로 고친 뒤 여기서 다시 잰다. vtool 이 무효화한 서명은 아래 codesign 이 새로 한다.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
MIN_OS="$(vtool -show-build "$BIN_DIR/check" | awk '$1 == "minos" { print $2 }' | sort -u)"
if [[ -z "$MIN_OS" || "$MIN_OS" == *$'\n'* ]]; then
  echo "error: $BIN_DIR/check 의 minos 를 하나로 읽지 못했다: [$MIN_OS]" >&2
  exit 1
fi
vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace -output "$BIN_DIR/check.stamped" "$BIN_DIR/check" >&2
mv "$BIN_DIR/check.stamped" "$BIN_DIR/check"
SDK_STAMPS="$(vtool -show-build "$BIN_DIR/check" | awk '$1 == "sdk" { print $2 }' | sort -u | tr '\n' ' ')"
MIN_STAMPS="$(vtool -show-build "$BIN_DIR/check" | awk '$1 == "minos" { print $2 }' | sort -u | tr '\n' ' ')"
if [[ "$SDK_STAMPS" != "$SDK_VERSION " || "$MIN_STAMPS" != "$MIN_OS " ]]; then
  echo "error: $BIN_DIR/check 스탬프가 sdk [${SDK_STAMPS% }] minos [${MIN_STAMPS% }] 이다 — 기대값 sdk $SDK_VERSION minos $MIN_OS" >&2
  exit 1
fi
lipo -info "$BIN_DIR/check" >&2

# SwiftPM 리소스 번들(캐릭터 이미지)을 앱 번들 Resources로 복사한다.
# Bundle.module 접근자가 Bundle.main.resourceURL 후보를 탐색하므로
# codesign 이전에 Contents/Resources/ 아래에 있어야 한다.
RESOURCE_BUNDLE="$BUILD_PRODUCTS/check_check.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$RES_DIR/"
else
  # 경고로 넘기면 캐릭터 이미지 없는 앱이 공증까지 통과해 나간다 — 멈춘다.
  echo "error: resource bundle not found at $RESOURCE_BUNDLE" >&2
  exit 1
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
  <string>0.3.27</string>
  <key>CFBundleVersion</key>
  <string>79</string>
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
