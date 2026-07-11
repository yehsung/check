#!/usr/bin/env bash
# Developer ID 서명 + 공증 + 스테이플 패키징.
# 선행 조건:
#   1) 키체인에 "Developer ID Application" 인증서 존재 (Xcode > Accounts > Manage Certificates)
#   2) xcrun notarytool store-credentials check-notary --apple-id <애플ID> --team-id <팀ID> --password <앱암호> 1회 실행
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "${CHECK_SUPABASE_ANON_KEY:-}" && -f "$ROOT/.env.local" ]]; then
  set -a; source "$ROOT/.env.local"; set +a
fi

IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')"
if [[ -z "$IDENTITY" ]]; then
  echo "Developer ID Application 인증서가 없습니다. Xcode > Settings > Accounts > Manage Certificates에서 발급하세요." >&2
  exit 1
fi
echo "서명 인증서: $IDENTITY" >&2

APP_PATH="$("$ROOT/scripts/build-local.sh" | tail -n 1)"

# ad-hoc 서명을 Developer ID + hardened runtime으로 교체 (공증 필수 조건)
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP_PATH" >&2
codesign --verify --deep --strict "$APP_PATH" >&2

# 공증 제출용 zip → 제출 --wait → 앱에 스테이플
NOTARIZE_ZIP="$ROOT/dist/check-notarize.zip"
rm -f "$NOTARIZE_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
echo "공증 제출 중 (보통 2~10분)..." >&2
xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile check-notary --wait >&2
xcrun stapler staple "$APP_PATH" >&2
rm -f "$NOTARIZE_ZIP"
spctl --assess --type execute -v "$APP_PATH" >&2 || true

# 배포 zip (공증된 앱은 도우미 불필요하지만, 구버전 macOS 대비 동봉 유지)
STAGE="$ROOT/dist/.stage"
rm -rf "$STAGE" "$ROOT/dist/check.zip"
mkdir -p "$STAGE/check"
cp -R "$APP_PATH" "$STAGE/check/"
ditto -c -k --keepParent "$STAGE/check" "$ROOT/dist/check.zip"
rm -rf "$STAGE"
echo "$ROOT/dist/check.zip"
