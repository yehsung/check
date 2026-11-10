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
#  5. **그 버전의 기능 문구가 앱 바이너리에 실제로 있다**(1.0.18 — 오목알 스킨 · 오목 AI 난이도 · 1:1 길건너 · 빼빼로 · 개발 아잉이 · 1:1 알까기 · 아잉 마작 · 1.0.17 바닥 한 줄).
#  4.5 **길건너 아잉이 모델이 번들에 있다**(없으면 게임이 보라색 공으로 조용히 접힌다).
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

# ⚠️ **Debug 산출물에 돌리지 마라 — 전부 0회로 나온다.** Debug 에서는 앱 본체(`AingCheck`)가 89KB 짜리 껍데기이고
#   코드가 전부 `AingCheck.debug.dylib`(114MB)에 있다(Xcode 의 Debug Dylib · 프리뷰 지원). 2026-10-30 에 실측했다:
#   세 줄을 재서 전부 0회였다. 0 은 **막는** 쪽이라 거짓 초록은 아니지만, 모르고 돌리면 "기능이 통째로 빠졌다"는
#   틀린 결론으로 시간을 버린다. **Release 아카이브로 돌려라**(기대 횟수도 아카이브로 재서 박는다).
#
# ── 5. 기능 문구 (1.0.18 — 스킨 · AI 난이도 · 1:1 길건너 · 빼빼로 · 개발 아잉이 · 1.0.17 바닥 한 줄) ───
#
# 왜 `strings | grep` 이 아니라 python 바이트인가: `strings` 는 C 로케일의 '출력 가능한 글자' 만 잇는다 — 한글 바이트는
# 그 집합에 없어서 잘려 나가고, `grep -a` 로도 안 잡힌다(저장소 메모 '산출물 검증엔 빌드 시각이 필요하다' 의 그 자리).
# 그래서 UTF-8 바이트를 **그대로 세는** 길 하나만 믿는다.
#
# ★ **UTF-8 15바이트 이하 리터럴은 여기서 잴 수 없다**(2026-10-22 실측 — 이 게이트가 1.0.12 에서 거짓 빨강을 냈다).
# Swift 의 작은 문자열 최적화는 15바이트까지를 `String` 안에 **즉치값으로** 접어 넣는다 — 그러면 최적화 빌드에
# 그 바이트열이 **아예 없다**. 경계는 15/16 에서 깨끗하게 떨어진다(서로 접두사가 아닌 문자열로 재서 확인:
# 6·12·14·15바이트 0회, 16·17바이트 1회). **언어 문제가 아니다** — ASCII `sticker-joy`(11바이트)도 0회다.
# 이모티콘 전선 토큰 `[아잉:기쁨]` 이 정확히 15바이트여서 Release 0회 · Debug 2회가 나왔다.
#
# ⚠️ **경계를 잴 때 서로 포함되는 문자열을 쓰지 마라.** 처음엔 `0123456789abcde`(15)를 `0123456789abcdef`(16)과
#    같이 넣었다가 "15바이트가 살아남았다" 는 **거짓 반례**를 얻었다 — 긴 쪽 하나가 짧은 쪽까지 '있다' 고 말한
#    것이다. 아래 '짧은 낱말을 쓰지 않는 까닭' 과 **같은 함정**인데 그걸 재는 프로브에서 다시 밟았다.
# 그 여섯 토큰은 대신 `Tests/CheckMobileKitTests/V1012StickerMobileTests.swift` 가 **값으로** 못 박는다 —
# 바이트를 세는 것보다 그쪽이 본디 더 강한 검사다. 여기에는 **16바이트 이상**인 문구만 적어라.
#
# 왜 `판돈` · `기권` 같은 **짧은 낱말을 쓰지 않는가**: 바이너리에서 못 찾기 때문이 아니다(2026-10-21 실측 — 6바이트
# `기권` 도 1회 잡힌다). 부분 글자라서 그 낱말을 품은 **모든 리터럴**이 함께 세어지고(`판돈을 고르세요` ·
# `기권하면 판돈을 잃어요` · 규칙 본문 …) 화면이 문장 하나를 늘릴 때마다 수가 흔들린다. 그래서 **문구 표의 리터럴을
# 통째로** 쓴다 — 아래 표의 글자는 전부 폰 문구 표(`GamesRummyText` · `GamesMiniGameText` · `NowText` · `MeText` · `RankingsText`)와 코어 `AvatarRemovalText` 의 값과 한 글자까지 같다.
#
# ★ **1.0.17 — 아홉 줄을 잰다. 기대 횟수는 build 29 아카이브(디바이스 · Release, 2026-11-04 01:17 KST)로 잰 값 — 아홉 줄 모두 1회**(바이트는 2026-11-04 계산).
#   제출판 build 30(맥 0.3.76 main 병합 뒤, 2026-11-04 13:25 KST 아카이브)도 아홉 줄 모두 1회 · 금지 0 으로 같았다.
#   후보는 전부 **1.0.16 소스(e78bb293)에 0회**이고, 지금 소스에서 **다른 리터럴 안에 들어 있지 않다**(주석 · 데모 픽스처 JSON 은 바이너리에 없다)를 확인했다.
#   사람을 골라 신청하거나 로봇과 연습해 보세요              62B  ReversiPhoneText.idleLine — 게임 탭 다섯째 카드 · 로비
#   리버시 규칙 · 흑 선공 · 한 수 30초                      47B  ReversiPhoneText.subtitle — 카드 부제
#   로봇과 연습하기                                        22B  ReversiPhoneText.aiButton — 로봇 연습 입구
#   한 번 더 시간이 지나면 져요                              38B  ReversiPhoneText.autoStreakWarning — 판 화면(자동 착수 두 번째)
#   판만 보여 줘요 · 관전자는 둘 수 없어요                   54B  ReversiPhoneText.watchCaption — 관전 판
#   끝난 판은 3분 동안만 볼 수 있어요                        46B  ReversiPhoneText.watchTailCaption — 관전 판
#   술 한잔 선물 전용                                       24B  DrinkGiftText.lockedCaption(코어) — 상점 · 고르기 이슬 잠긴 칸
#   집중 모드에서는 메시지를 보낼 수 없어요. 맥에서 …        105B MessageNoticeText.senderFocused(코어) — 입력줄 · 목록 위 한 줄(내 집중)
#   2~4명이 숫자 타일로 묶음을 만들어 랙을 먼저 비우는 게임   77B  **1.0.16 바닥 한 줄**(GamesRummyText.subtitle). 병합이 앞 판 기능을 떨어뜨리면 여기서 잡힌다.
#   ⚠️ 1.0.16 의 나머지 열두 줄은 **뺐다.** 이 판을 증명하지 못한다.
#   ⚠️ **넣지 마라 — 판을 증명하지 못하는 후보 일곱**(1.0.17 검토 지적):
#     · 1.0.16 바이너리에 이미 있다: "지금 대결 중인 판이 없어요"(GamesChessText) · "순위를 불러오고 있어요"(GamesTetrisDuelText) ·
#       "보낸 신청의 답을 기다리고 있어요"(GamesTetrisDuelText) — 리버시 화면이 같은 글자를 써도 옛 화면이 이미 싣고 있었다.
#     · 다른 리터럴 안에 그대로 들어 있다(두 번 세어진다): "시간이 지나 자동으로 놓이는 중이에요"(⊂ "상대 시간이 지나 …") ·
#       "로봇과 둔 판은 루비·전적·순위에 남지 않아요"(⊂ 규칙 줄) · "여러 줄이 한 번에"(⊂ 규칙 줄) · "이슬 아잉이"(⊂ DrinkGiftText.body ·
#       CharacterCatalog · MeCharacterCardData 셋에 있다).
#     아래 표 안의 쌍끼리만 포함 관계를 막으므로(아래 python) 표 밖 리터럴과의 겹침은 사람이 거른다.
#
# ★ **1.0.17 에서 이 게이트가 못 재는 것** — 숨기지 말고 적어 둔다:
#   · **메시지 서식 · 골라 복사**: 새 화면 글자가 없다(편집 메뉴는 iOS 것 · [신고]는 앞 판 글자). `V1017ChatMarkdownMobileTests` ·
#     `V1017BubbleSelectionMobileTests` 가 규칙 · 배선을 잰다.
#   · **집중 칩**: "집중"(6B) · "집중 중"(10B)은 15바이트 이하라 못 잰다 — 긴 문장(senderFocused)을 대신 잰다. `V1017FocusRowsMobileTests`.
#   · **이슬 그림**: 번들 PNG 두 장 · 카드 HEIC 다. `BaseComponentTests`(맥 원본과 픽셀) · `IsulAltKitTests`(대체 꾸러미)가 잰다.
#   · **처리방침 개정**: 앱 바이너리가 아니라 GitHub Pages(main 푸시)다. `V1017PrivacyPolicyFactsTests`.
#   게이트에 억지로 짧은 글자를 넣지 마라.
#
# ※ 기대값은 **아카이브(디바이스 · Release)로 재서** 박는다. **시뮬레이터 Release 는
#   같은 글자를 2회로 센다**(구성이 다르다 — 실측) → 기대값은 반드시 아카이브로 재라. 아직 안 쟨 줄은 `None` 으로 두면
#   된다(`None` = "0 이면 막고, 수는 알리기만 한다").
# **0 이면 막고, 기대와 다르면 알리기만 한다.** 화면이 문장을 하나 늘리는 것은 정상이고(수가 오른다), 쓰이지 않는
# 리터럴이 Release 에서 걷히는 것도 정상이다(수가 내린다). 막아야 하는 것은 **그 글자가 아예 없는** 바이너리다 —
# 그건 문구 표가 화면에 안 붙었다는 뜻이고, 글자 없이 나간 기능은 사용자가 쓸 수 없다.
# ── 4.5 자산 존재: 길건너 아잉이 모델 ────────────────────────────────────────────────────────────
# `aing.scn` 이 번들에 없으면 길건너는 **보라색 공**으로 조용히 접힌다(`CrossyPalette.fallbackAing`). 로그 한 줄만
# 남고 빌드는 초록이다. 커밋에서 4.7MB 바이너리가 빠지거나 `.copy` 가 번들에 안 남기면 그대로 출시된다.
# 경로는 2026-10-30 에 실제 산출물에서 확인했다(`.copy("Resources/Art")` 가 폴더째 남긴다).
crossy_model="$APP/check_CheckMobileKit.bundle/Art/aing.scn"
if [[ ! -f "$crossy_model" ]]; then
  report "길건너 아잉이 모델이 번들에 없다 — 게임이 보라색 공으로 접힌다: $crossy_model"
else
  model_size="$(stat -f%z "$crossy_model")"
  if (( model_size < 1000000 )); then
    report "길건너 모델이 너무 작다(${model_size}바이트) — 빈 파일이나 LFS 포인터일 수 있다"
  else
    echo "OK: 길건너 모델 ${model_size}바이트"
  fi
fi

app_bin="${binaries[0]}"
if [[ -f "$app_bin" ]]; then
  feature_report="$(python3 - "$app_bin" <<'PY'
import sys

# 횟수 `None` = **아직 안 쟀다**(아카이브로 확정한다). 0 이면 막고, 수는 알리기만 한다.
want = [
    # 1.0.18 — 맥 기능 이식 판(대표 지시 11-10). build 31 아카이브(디바이스 · Release, 2026-11-10) 실측 다섯 줄 모두 1회.
    ("내 돌은 상대 화면에도 이 스킨으로 보여요", 1),        # 오목알 스킨 절(`OmokSkinPhoneText.note`)
    ("난이도 · AI가 몇 수 앞까지 계산할지", 1),            # 오목 AI 난이도(`GomokuPhoneText.aiDifficultyTitle`)
    ("100점에 먼저 닿으면 이겨요", 1),                    # 1:1 길건너 카드(`CrossyDuelPhoneText.cardSubtitle`)
    ("빼빼로 데이 선물 전용", 1),                          # 빼빼로 잠긴 칸(코어 `PeperoGiftText.lockedCaption` — 폰이 처음 링크한다)
    ("누적 미션 '누적 근무 100시간'을 채우면 받아요", 1),   # 개발 아잉이 얻는 길(코어 `DevAingMission.lockedHint`)
    # 1.0.18 '한 판에 전부'(대표 #d_xB6BJcn2nsCq) — 1:1 알까기 · 아잉 마작. 폰에서 새로 쓴 글자(맥 타깃 글자는 폰 바이너리에 없다). build 32 아카이브 실측 1회.
    ("놓으면 날아가요 · 돌 위로 되돌리면 취소", 1),                        # 1:1 알까기 손짓 안내(`AlkkagiPhoneText.aimRelease`)
    ("리치 마작 4인 대국 · 방을 열어 초대하거나 혼자 연습해요", 1),            # 아잉 마작 카드(`GamesMahjongPhoneText.cardSubtitle`)
    # 1.0.17 — 앞 버전 것을 **한 줄만** 바닥으로 남긴다(기능이 통째로 빠진 바이너리를 막는 그물). build 30 아카이브 실측 1회.
    ("술 한잔 선물 전용", 1),
]
# ⚠️ **길건너의 `MiniGameKind.crossy.howToPlay`("한 칸씩 뛰어 앞으로 · …")를 여기 넣지 마라.**
# 그 글자는 CheckCore 에 있고 **1.0.14 바이너리에 이미 들어 있다**(폰이 `GamesMiniGameText.howToPlay(.crossy)` 를
# 전부터 불렀다 — 1.0.14 게이트 당시의 V0367 시험이 그 자리를 쟀다). 있다고 해도 무엇도 증명하지 못한다.
# 1.0.15 의 증명은 **폰에서 새로 쓴 둘째 줄**("쓸어서 …")이었고, 지금은 앞 판 바닥 한 줄로 남아 있다.

# 서로 포함되는 쌍이 있으면 **긴 쪽 하나가 짧은 쪽까지 "있다"고 말한다**(2026-10-22 에 실제로 데였다).
# 표를 고칠 때마다 여기서 막는다 — 사람이 눈으로 거르지 못한다.
for _i, (_a, _) in enumerate(want):
    for _j, (_b, _) in enumerate(want):
        if _i != _j and _a in _b:
            sys.exit(f"FAIL: 기능 문구가 서로 포함된다 — {_a!r} ⊂ {_b!r} (겹치지 않는 글자로 바꿔라)")

data = open(sys.argv[1], "rb").read()
missing = []
lines = []
for text, expected in want:
    found = data.count(text.encode("utf-8"))
    if expected is None:
        mark = "  ← 기대 미측정(아카이브로 재서 확정한다)"
    else:
        mark = "" if found == expected else "  ← 기대 %d" % expected
    lines.append("  %-36s %d회%s" % (text, found, mark))
    if found == 0:
        missing.append(text)
print("\n".join(lines))
if missing:
    print("MISSING:" + " · ".join(missing))
PY
)"
  echo "1.0.18 기능 문구(스킨 · AI 난이도 · 1:1 길건너 · 빼빼로 · 개발 아잉이 · 1:1 알까기 · 아잉 마작 · 1.0.17 바닥):"
  echo "${feature_report%$'\n'MISSING:*}"
  feature_found="$(printf '%s\n' "${feature_report%$'\n'MISSING:*}" | grep -c '회' || true)"
  if [[ "$feature_report" == *$'\n'MISSING:* ]]; then
    report "1.0.18 기능 문구가 앱 바이너리에 없다: ${feature_report##*$'\n'MISSING:}"
  fi
else
  report "앱 바이너리가 없어 기능 문구를 세지 못했다: $app_bin"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "Release 번들 계약 위반"
  exit 1
fi
echo "OK: 픽스처 0 · 금지 문자열 0 · 금지 심볼 0(뒤에서 도는 알림 액션 흔적 포함) · 1.0.18 기능 문구 ${feature_found:-0}/${feature_found:-0} 전부 있음 · 길건너 모델 있음"
