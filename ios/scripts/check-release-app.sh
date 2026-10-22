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
#     ★ 2026-10-19: 이 검사 하나만 믿지 마라. Swift 는 **낱말 치환**으로 망글링해서 `MobileDemoMissionsRoute` 가
#       `0B17DemoMissionsRoute` 로 적힌다 — `MobileDemo` 라는 글자가 심볼에 아예 없다. 그래서 2번(strings · 리플렉션
#       메타데이터)이 데모 격리의 **주된 증거**이고, 3번은 보조다. 치환된 꼴(`<길이>Demo…` · `<길이>Stub…`)도
#       같이 센다 — 길이 숫자가 앞에 붙는 모양이라 평범한 영어 심볼과는 겹치지 않는다.
#
# ★ 2026-09-18: `join_team` · `create_team` · `/auth/v1/signup` 을 금지 목록에서 **뺐다**. 폰이 가입을 받게 됐기 때문이다
#   (앱스토어 정식 출시 준비 — 폰에서 가입을 못 하면 스토어에서 받은 사람은 로그인 벽만 본다). 이 셋은 본인 계정에만 작용하고
#   남의 세션·근무 시간·찌르기를 건드리지 않는다 — 원래 금지의 이유(R1~R4)에 해당하지 않았고, '폰 범위 밖'이라는 범위 결정이었다.
#   나머지 목록은 그대로다: 그것들은 부르는 순간 남의 데이터가 틀어진다.
#  4. 앱을 열지 않고 도는 알림 액션(w10 에서 걷어냄 — MESSAGE 답장 · 읽음, GOMOKU_INVITE 거절)의 식별자 · 답장 실패 안내 알림 ·
#     텍스트 입력 액션 클래스 참조가 0건이다(strings · nm). 이전 Release 바이너리(w4/int)에는 모두 있었다 — 되살아나면 여기서 잡힌다.
#  5. **그 버전의 기능 문구가 앱 바이너리에 실제로 있다**(1.0.12 — 아잉이 이모티콘).
#     ★ 이 표는 **릴리스마다 그 버전 것으로 옮긴다**(맥의 버전 고정 시험과 같은 관행). 안 옮기면
#       게이트가 옛 기능만 재서, 새 기능이 문구 없이 나가도 초록이다. 1~4 가 "없어야 할 것이 없다" 를 재는 데 비해
#     이것은 "있어야 할 것이 있다" 를 잰다. 왜 필요한가: 폰 뷰는 전부 `#if os(iOS)` 안이라 맥 `swift test` 가 한 줄도 보지 못하므로
#     (저장소 메모 '폰 뷰는 맥 스위트가 못 본다') 문구 표(`TetrisPhoneText`)가 **아무 화면에도 안 붙은 채로** 초록일 수 있다.
#     그러면 Swift 가 그 리터럴을 Release 에서 걷어 가고 기능이 글자 없이 나간다 — 이 검사가 그 구멍이다.
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
SYMBOL_PATTERN='MobileDemo|[0-9]Demo[A-Z0-9]|[0-9]Stub[A-Z0-9]|MobileStubURLProtocol|MobileForbiddenCalls|MobileKeychainProbe|takePokes|workTick|WorkTickGate|syncUltraWallet|updateAppVersion|closeAbandonedSessions|upsertStatusDevice|reportDeviceInput|sendUltraPoke|UNTextInputNotificationAction|postLocalNotice'

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

# ── 5. 기능 문구 (1.0.12 — 아잉이 이모티콘 · 1.0.11 바닥 한 줄) ───────────────────────────────────────────────
#
# 왜 `strings | grep` 이 아니라 python 바이트인가: `strings` 는 C 로케일의 '출력 가능한 글자' 만 잇는다 — 한글 바이트는
# 그 집합에 없어서 잘려 나가고, `grep -a` 로도 안 잡힌다(저장소 메모 '산출물 검증엔 빌드 시각이 필요하다' 의 그 자리).
# 그래서 UTF-8 바이트를 **그대로 세는** 길 하나만 믿는다.
#
# 왜 `판돈` · `기권` 같은 **짧은 낱말을 쓰지 않는가**: 바이너리에서 못 찾기 때문이 아니다(2026-10-21 실측 — 6바이트
# `기권` 도 1회 잡힌다). 부분 글자라서 그 낱말을 품은 **모든 리터럴**이 함께 세어지고(`판돈을 고르세요` ·
# `기권하면 판돈을 잃어요` · 규칙 본문 …) 화면이 문장 하나를 늘릴 때마다 수가 흔들린다. 그래서 **문구 표의 리터럴을
# 통째로** 쓴다 — 아래 여섯 줄은 `Sources/CheckMobileKit/Games/GamesTetrisDuelText.swift` 의 값과 글자가 같다.
#
# 기대 수의 근거(= 그 글자를 품은 문구 표의 리터럴 수):
#   1:1 테트리스                      3  (title · rulesTitle "1:1 테트리스 규칙" · cardOpenHint "1:1 테트리스 대결 화면을 열어요")
#   공격형 · 먼저 꼭대기까지 쌓이면 져요   1  (subtitle — cardSubtitle 은 그 값의 별칭이라 리터럴이 늘지 않는다)
#   판돈을 고르세요                     1  (stakePromptCaption)
#   속도 올라가는 중                    1  (speedUp — 2분 뒤 가속, D7)
#   판 중에 앱을 나가면 져요             1  (leaveWarning — 판 위에 늘 보이는 경고, 설계서 P7. 이 줄이 기능의 일부다)
#   기권하면 판돈을 잃어요               1  (resignWarning — 기권 확인)
# **0 이면 막고, 기대와 다르면 알리기만 한다.** 화면이 문장을 하나 늘리는 것은 정상이고(수가 오른다), 쓰이지 않는
# 리터럴이 Release 에서 걷히는 것도 정상이다(수가 내린다). 막아야 하는 것은 **그 글자가 아예 없는** 바이너리다 —
# 그건 문구 표가 화면에 안 붙었다는 뜻이고, 글자 없이 나간 기능은 사용자가 쓸 수 없다.
app_bin="${binaries[0]}"
if [[ -f "$app_bin" ]]; then
  feature_report="$(python3 - "$app_bin" <<'PY'
import sys

want = [
    # 1.0.12 — 아잉이 이모티콘 (`CheckCore/AingSticker.swift` 의 값과 글자가 같다)
    ("아잉이 이모티콘", 2),          # gridTitle + buttonLabel("아잉이 이모티콘 보내기")이 이 글자를 품는다
    ("[아잉:기쁨]", 1),              # 전선 토큰 — 이 글자가 없으면 **보낸 그림이 상대에게 안 간다**
    ("[아잉:놀람]", 1),              # 여섯 중 마지막 — 표가 통째로 실렸는지 양끝으로 본다
    ("보내는 중이에요. 잠시 후 다시 눌러 주세요", 1),  # sendingNowNotice — 조용히 닫지 않는다는 그 줄
    # 1.0.11 — 1:1 테트리스. 앞 버전 것을 **한 줄만** 바닥으로 남긴다(기능이 통째로 빠진 바이너리를 막는 그물).
    ("판 중에 앱을 나가면 져요", 1),
]

data = open(sys.argv[1], "rb").read()
missing = []
lines = []
for text, expected in want:
    found = data.count(text.encode("utf-8"))
    mark = "" if found == expected else "  ← 기대 %d" % expected
    lines.append("  %-36s %d회%s" % (text, found, mark))
    if found == 0:
        missing.append(text)
print("\n".join(lines))
if missing:
    print("MISSING:" + " · ".join(missing))
PY
)"
  echo "1.0.12 기능 문구(아잉이 이모티콘):"
  echo "${feature_report%$'\n'MISSING:*}"
  if [[ "$feature_report" == *$'\n'MISSING:* ]]; then
    report "1.0.12 기능 문구가 앱 바이너리에 없다: ${feature_report##*$'\n'MISSING:}"
  fi
else
  report "앱 바이너리가 없어 기능 문구를 세지 못했다: $app_bin"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "Release 번들 계약 위반"
  exit 1
fi
echo "OK: 픽스처 0 · 금지 문자열 0 · 금지 심볼 0(뒤에서 도는 알림 액션 흔적 포함) · 1.0.12 기능 문구 5/5"
