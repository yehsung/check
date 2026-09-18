#!/usr/bin/env bash
# Release 앱 번들 계약 검사(dbase-fix). TestFlight 에 올릴 .app 을 이걸로 먼저 잰다 — 0 이 아니면 올리지 않는다.
#
# 사용: ios/scripts/check-release-app.sh <AingCheck.app 경로>
#   예: xcodebuild -project ios/AingCheck.xcodeproj -scheme AingCheck -configuration Release \
#         -destination 'generic/platform=iOS' -derivedDataPath <dd> CODE_SIGNING_ALLOWED=NO build
#       ios/scripts/check-release-app.sh <dd>/Build/Products/Release-iphoneos/AingCheck.app
#
# 보는 것
#  1. 데모 픽스처 폴더(Fixtures)가 번들 어디에도 없다 — SwiftPM 리소스는 구성과 무관하게 복사되므로 앱 타깃의 Release 빌드 단계가 지운다.
#  2. 앱·위젯 바이너리 strings 에 맥 전용 쓰기 경로·데모 흔적이 0건이다(SPEC-ios §0-2 — 컴파일에서 사라졌다는 증거).
#     읽기 경로(work_status_devices GET · focus_mode 조회 칸)와 실시간 소켓 keepalive(heartbeat · heartbeatAck — 근무 하트비트가 아니다)는
#     폰도 쓰므로 여기서 보지 않는다. 근무 하트비트(맥 heartbeat(…) 메서드)는 아래 심볼 검사와 소스 계약 테스트가 본다.
#  3. nm 심볼에 데모·스텁·맥 전용 메서드 이름이 0건이다.
#
# ★ 2026-09-18: `join_team` · `create_team` · `/auth/v1/signup` 을 금지 목록에서 **뺐다**. 폰이 가입을 받게 됐기 때문이다
#   (앱스토어 정식 출시 준비 — 폰에서 가입을 못 하면 스토어에서 받은 사람은 로그인 벽만 본다). 이 셋은 본인 계정에만 작용하고
#   남의 세션·근무 시간·찌르기를 건드리지 않는다 — 원래 금지의 이유(R1~R4)에 해당하지 않았고, '폰 범위 밖'이라는 범위 결정이었다.
#   나머지 목록은 그대로다: 그것들은 부르는 순간 남의 데이터가 틀어진다.
#  4. 앱을 열지 않고 도는 알림 액션(w10 에서 걷어냄 — MESSAGE 답장 · 읽음, GOMOKU_INVITE 거절)의 식별자 · 답장 실패 안내 알림 ·
#     텍스트 입력 액션 클래스 참조가 0건이다(strings · nm). 이전 Release 바이너리(w4/int)에는 모두 있었다 — 되살아나면 여기서 잡힌다.
set -euo pipefail

APP="${1:?AingCheck.app 경로를 주세요}"
[[ -d "$APP" ]] || { echo "error: $APP 이 없다" >&2; exit 2; }

fail=0
report() { echo "FAIL: $*"; fail=1; }

fixtures="$(find "$APP" -type d -name Fixtures 2>/dev/null || true)"
[[ -z "$fixtures" ]] || report "데모 픽스처 폴더가 번들에 있다: $fixtures"
demo_json="$(find "$APP" -type f \( -name 'rpc.*.json' -o -name 'rest.*.json' -o -name 'auth.*.json' \) 2>/dev/null || true)"
[[ -z "$demo_json" ]] || report "픽스처 모양의 JSON 이 번들에 있다: $demo_json"

STRINGS_PATTERN='take_pokes|work_tick|close_abandoned|ultra_wallet_sync|buy_ultra|poke_user|ultra_poke|away_sync|token_usage_device_monthly|token_usage_monthly|app_build|app_version|AingCheckDemo|demo\.aingcheck|forbidden on phone|MobileStub|MobileDemo|MESSAGE_REPLY|MESSAGE_READ|GOMOKU_DECLINE|aingcheck\.local\.|aingcheck_local'
SYMBOL_PATTERN='MobileDemo|MobileStubURLProtocol|MobileForbiddenCalls|MobileKeychainProbe|takePokes|workTick|WorkTickGate|syncUltraWallet|updateAppVersion|closeAbandonedSessions|upsertStatusDevice|reportDeviceInput|sendUltraPoke|UNTextInputNotificationAction|postLocalNotice'

binaries=("$APP/AingCheck")
for appex in "$APP"/PlugIns/*.appex; do
  [[ -d "$appex" ]] || continue
  name="$(basename "$appex" .appex)"
  binaries+=("$appex/$name")
done

for bin in "${binaries[@]}"; do
  [[ -f "$bin" ]] || { report "바이너리가 없다: $bin"; continue; }
  hits="$(strings -a "$bin" | grep -E "$STRINGS_PATTERN" | sort | uniq -c || true)"
  [[ -z "$hits" ]] || report "$(basename "$bin") strings:"$'\n'"$hits"
  symbols="$(nm "$bin" 2>/dev/null | grep -E "$SYMBOL_PATTERN" | head -5 || true)"
  [[ -z "$symbols" ]] || report "$(basename "$bin") 심볼:"$'\n'"$symbols"
  echo "checked $(basename "$bin") ($(stat -f %z "$bin") bytes)"
done

if [[ "$fail" -ne 0 ]]; then
  echo "Release 번들 계약 위반"
  exit 1
fi
echo "OK: 픽스처 0 · 금지 문자열 0 · 금지 심볼 0(뒤에서 도는 알림 액션 흔적 포함)"
