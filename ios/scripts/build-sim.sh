#!/usr/bin/env bash
# 시뮬레이터용 앱을 **엔타이틀먼트를 실어** 빌드한다(dbase-fix). 실서버 e2e(로그인 유지 · 설치 식별자 · 위젯 공유)는 이 빌드로 한다.
#
# 왜: `CODE_SIGNING_ALLOWED=NO` 빌드에는 keychain-access-groups · App Group 엔타이틀먼트가 실리지 않는다. 그 앱에서는 키체인이 전부
# -34018(errSecMissingEntitlement)로 실패해 재실행하면 로그아웃 상태가 되고, App Group 대신 앱 폴더로 접혀 위젯과 나누지 못한다
# (dbase-verify 실측 — 화면에는 아무 표시가 없다). 서명 없는 빌드는 데모 모드(-AingCheckDemo YES) 스크린샷 전용이다.
# 시뮬레이터는 프로비저닝이 필요 없다 — 애드혹(-) 서명이면 링커가 엔타이틀먼트를 바이너리의 __TEXT,__entitlements 에 넣는다.
#
# 사용: ios/scripts/build-sim.sh <derivedDataPath> [Debug|Release]
#   결과: <derivedDataPath>/Build/Products/<구성>-iphonesimulator/AingCheck.app  (끝에 엔타이틀먼트를 확인해 없으면 실패한다)
#   그다음: xcrun simctl install <기기> <앱> && xcrun simctl launch <기기> com.yehsung.aingcheck
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DERIVED="${1:?derivedDataPath 를 주세요}"
CONFIG="${2:-Debug}"

(cd "$ROOT/ios" && xcodegen generate --quiet)

xcodebuild \
  -project "$ROOT/ios/AingCheck.xcodeproj" \
  -scheme AingCheck \
  -configuration "$CONFIG" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= \
  build

APP="$DERIVED/Build/Products/$CONFIG-iphonesimulator/AingCheck.app"
for bin in "$APP/AingCheck" "$APP/PlugIns/AingCheckWidgets.appex/AingCheckWidgets"; do
  ents="$(strings -a "$bin" | grep -c -E 'keychain-access-groups|com\.apple\.security\.application-groups' || true)"
  if [[ "$ents" -lt 2 ]]; then
    echo "error: $(basename "$bin") 에 시뮬레이터 엔타이틀먼트(키체인 그룹 · App Group)가 없다 — 키체인이 -34018 로 실패한다" >&2
    exit 1
  fi
done
echo "OK: $APP (엔타이틀먼트 실림)"
