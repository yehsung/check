#!/usr/bin/env bash
# 맥 앱스토어(MAS) 판 패키징 — CHECK_MAS 플래그 유니버설 빌드 → AingCheck.app 조립(번들 com.yehsung.aingcheck)
# → 프로파일 삽입 → Apple Distribution 서명(샌드박스 엔타이틀먼트) → productbuild 로 서명된 설치 패키지(.pkg).
# Developer ID 판(kingcheck · build-local.sh · package-notarized.sh · DMG · brew)과는 산출물·빌드 캐시를 나눠 쓰고 서로 건드리지 않는다.
#
# 사용법: ./scripts/package-mas.sh <버전> <build> [--validate]
#   예) ./scripts/package-mas.sh 0.3.52 105 --validate
#   <버전>·<build> 은 **이 커밋으로 낸(낼) Developer ID 릴리스와 같은 값**이다. 서버는 채널을 모르고 build 숫자만 보므로
#   MAS 가 따로 번호를 세면 구버전으로 판정된다(docs/release.md "맥 앱스토어 → build 번호").
#   --validate : 만든 pkg 를 `xcrun altool --validate-app` 으로 애플에 묻는다(읽기 전용 — 올리지 않는다).
#   **업로드는 이 스크립트가 하지 않는다.** 검증이 초록인 걸 본 뒤 docs/release.md 의 업로드 명령을 따로 실행한다
#   (테스트·검증과 업로드는 호출을 나눈다 — 파이프에 묶으면 빨간 채로 나간 적이 있다).
#   stdout 마지막 줄 = pkg 경로. 로그는 전부 stderr.
#
# 산출물(dist/ 는 gitignore): dist/mas/AingCheck.app · dist/mas/AingCheck.pkg · dist/mas/AingCheck.app.dSYM · dist/mas/validate.log
#   빌드 캐시는 .build-mas/ — Developer ID 빌드의 .build/ 와 섞이지 않는다(같은 캐시를 쓰면 플래그가 다른 산출물이 서로를 덮는다).
#
# 필요(저장소 밖 — docs/release.md "맥 앱스토어 → 서명 자산"):
#   · 로그인 키체인의 "Apple Distribution: yesung kim (MQ2KQK37WD)"                         (MAS_APP_IDENTITY)
#   · ~/Library/Keychains/aing-mas.keychain-db 의 "3rd Party Mac Developer Installer: yesung kim (MQ2KQK37WD)"
#       (MAS_INSTALLER_IDENTITY · MAS_INSTALLER_KEYCHAIN). 검색 목록에 없는 전용 키체인이라 productbuild --keychain 으로 지정한다.
#       암호 ~/.aing-check-secrets/mas/keychain-password(600) 는 이 스크립트가 **stdin 으로만** 넘겨 잠금을 푼다 — 출력·argv 에 안 싣는다.
#   · ~/.aing-check-secrets/mas/aingcheck-mac-appstore.provisionprofile (MAC_APP_STORE · MAS_PROFILE)
#   · .env.local(또는 환경)의 CHECK_SUPABASE_ANON_KEY — 없으면 멈춘다. 키 없는 번들은 서명·검증·업로드를 다 통과하고
#       심사관만 로그인을 못 한다(2.1 거절 한 바퀴). service_role 키가 들어 있으면 그것도 멈춘다.
#   · 개인정보 매니페스트 Sources/check/Resources/PrivacyInfo.xcprivacy (MAS_PRIVACY_MANIFEST 로 바꿀 수 있다)
#   · --validate 면 ASC API 키: ASC_API_KEY(기본 JT2GT9FY5N) · ASC_API_ISSUER(.env.local 또는 환경 — 공개 저장소라 여기 적지 않는다)
#       · ~/.appstoreconnect/private_keys/AuthKey_<키>.p8 · ASC_APPLE_ID(기본 6812768622 = 아잉체크 레코드)
#
# 게이트(하나라도 어긋나면 pkg 를 남기지 않고 멈춘다):
#   ① 바이너리가 **방금 만든 것**: 빌드 전에 산출물을 지우고, 빌드 뒤 '빌드 시작 표지보다 새것' + '어떤 소스보다도 새것'.
#      (Xcode 27 산출물 경로 함정 — 0.3.23 에 옛 바이너리가 새 버전 Info.plist 를 달고 나갔다. 경로는 --show-bin-path 로 묻는다)
#   ② CHECK_MAS 갈래가 실제로 컴파일됐다: 자가 업데이트·타사 자격증명·외부 실행 코드의 고유 문자열이 바이너리에 0건.
#      (16바이트 이상만 쓴다 — Swift 는 15바이트 이하 문자열을 코드에 인라인해 바이트 검색으로 원리상 못 찾는다)
#   ③ SDK 스탬프 = 빌드 SDK, minos = LSMinimumSystemVersion, LD 도구 항목 보존, 두 아키텍처(arm64 · x86_64).
#   ④ 프로파일: 앱 ID · 팀 · 플랫폼 OSX · 만료 전 · 배포용(기기 목록 없음) · 서명 인증서가 프로파일에 들어 있다.
#   ⑤ 서명 뒤 엔타이틀먼트가 packaging/mas.entitlements 와 **정확히 같다**(get-task-allow 같은 군더더기 0) ·
#      프로파일이 허락하지 않는 키 0 · 서명자 = Apple Distribution · Identifier = 번들 ID · --verify --deep --strict.
#   ⑥ quarantine 속성 0(2025-02-18 부터 애플 요구) · CheckConfig.plist 에 anon 키.
#   ⑦ pkg 서명자 = Mac Installer Distribution, 펼친 pkg 안의 앱 CDHash = 방금 서명한 앱.
#
# 리허설: Sources 에 `#if … CHECK_MAS` 갈래가 아직 없는 소스(맥 앱스토어 판 앱 코드가 병합되기 전)에서는 ② 를 증명할 수 없어
#   멈춘다. 파이프라인만 미리 돌려 보려면 MAS_REHEARSAL=1 — ② 를 경고로 낮추고 pkg 이름을 AingCheck-rehearsal.pkg 로 바꾼다.
#   **MAS 갈래가 있는 소스에서는 MAS_REHEARSAL 을 거부한다** — 실제 제출본에서 ② 를 끄는 손잡이는 없다.
set -euo pipefail
# pipefail 주의: `cmd | head -n 1` · `| awk '{…; exit}'` · `| grep -q` 처럼 **먼저 끝나는 소비자**를 파이프에 두면 생산자가
# SIGPIPE(141)로 죽고 그 141 이 set -e 로 스크립트를 죽인다(리허설에서 codesign -dvvv | awk exit 가 그랬다). 파일·변수에 받은 뒤 읽는다.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

log() { echo "==> $*" >&2; }
warn() { echo "경고: $*" >&2; }
die() { echo "오류: $*" >&2; exit 1; }

USAGE="사용법: ./scripts/package-mas.sh <버전 x.y.z> <build 정수> [--validate]"
VALIDATE=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    -h|--help) echo "$USAGE"; exit 0 ;;
    --validate) VALIDATE=1 ;;
    -*) die "모르는 옵션: $arg — $USAGE" ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done
[[ ${#POSITIONAL[@]} -eq 2 ]] || die "$USAGE"
VERSION="${POSITIONAL[0]}"
BUILD="${POSITIONAL[1]}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "버전은 x.y.z 여야 한다: [$VERSION]"
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || die "build 는 양의 정수여야 한다: [$BUILD]"

# ---- 고정값 ----------------------------------------------------------------------------------------------------------
BUNDLE_ID="com.yehsung.aingcheck"
TEAM_ID="MQ2KQK37WD"
APP_NAME="AingCheck"            # 파일 이름 · CFBundleName(ASCII — 아래 Info.plist 주석)
DISPLAY_NAME="아잉체크"          # CFBundleDisplayName — App Store 레코드 이름과 같다
CATEGORY="public.app-category.productivity"
ENTITLEMENTS="$ROOT/packaging/mas.entitlements"
SCRATCH="$ROOT/.build-mas"
OUT_DIR="$ROOT/dist/mas"
APP="$OUT_DIR/$APP_NAME.app"
# 이 문자열들이 바이너리에 남아 있으면 CHECK_MAS 갈래가 컴파일되지 않은 것이다(게이트 ②). 전부 16바이트 이상.
FORBIDDEN_STRINGS=(
  "brew upgrade --cask"              # 앱 안 업데이트(brew) — 2.4.5(vii)
  "releases/latest/download"         # DMG 자가 교체 · 직접 받기 링크
  "api.github.com/repos"             # GitHub 릴리스 감시
  "aing-check-update"                # 분리 프로세스 업데이터 스크립트·로그
  "account/usage/read"               # codex app-server 프로브
  "/opt/homebrew/bin/agy"            # 안티그래비티 CLI 실행
)

SECRETS_DIR="${MAS_SECRETS_DIR:-$HOME/.aing-check-secrets/mas}"
APP_IDENTITY="${MAS_APP_IDENTITY:-Apple Distribution: yesung kim (MQ2KQK37WD)}"
INSTALLER_IDENTITY="${MAS_INSTALLER_IDENTITY:-3rd Party Mac Developer Installer: yesung kim (MQ2KQK37WD)}"
INSTALLER_KEYCHAIN="${MAS_INSTALLER_KEYCHAIN:-$HOME/Library/Keychains/aing-mas.keychain-db}"
KEYCHAIN_PASSWORD_FILE="${MAS_KEYCHAIN_PASSWORD_FILE:-$SECRETS_DIR/keychain-password}"
PROFILE="${MAS_PROFILE:-$SECRETS_DIR/aingcheck-mac-appstore.provisionprofile}"
PRIVACY_MANIFEST="${MAS_PRIVACY_MANIFEST:-$ROOT/Sources/check/Resources/PrivacyInfo.xcprivacy}"

# .env.local 에서 **필요한 이름만** 꺼낸다(환경으로 준 값이 이긴다). 통째로 source 하면 그 파일의 다른 값(service_role 키 등)이
# swift build·codesign 같은 자식 프로세스 환경으로 새고, 이름이 겹치면(VERSION · BUILD · ROOT …) 이 스크립트의 값을 덮는다.
env_local() {
  [[ -f "$ROOT/.env.local" ]] || return 0
  # shellcheck disable=SC1091
  ( set +u; source "$ROOT/.env.local" >/dev/null 2>&1; printf '%s' "${!1:-}" )
}
[[ -n "${CHECK_SUPABASE_ANON_KEY:-}" ]] || CHECK_SUPABASE_ANON_KEY="$(env_local CHECK_SUPABASE_ANON_KEY)"
[[ -n "${ASC_API_ISSUER:-}" ]] || ASC_API_ISSUER="$(env_local ASC_API_ISSUER)"
[[ -n "${ASC_API_KEY:-}" ]] || ASC_API_KEY="$(env_local ASC_API_KEY)"
ASC_API_KEY="${ASC_API_KEY:-JT2GT9FY5N}"
ASC_API_ISSUER="${ASC_API_ISSUER:-}"
ASC_APPLE_ID="${ASC_APPLE_ID:-6812768622}"   # 아잉체크 레코드(iOS 와 같은 레코드에 macOS 를 붙인다 — 유니버설 구매)

TMP="$(mktemp -d "${TMPDIR:-/tmp}/aing-mas.XXXXXX")"
ASSEMBLING=0
on_exit() {
  local rc=$?
  rm -rf "$TMP"
  # 조립을 시작한 뒤 실패하면 반쯤 만든 앱·pkg 를 남기지 않는다(옛 산출물 함정 — 남은 것이 '방금 만든 것'으로 오인된다).
  if [[ $rc -ne 0 && "$ASSEMBLING" == 1 ]]; then
    rm -rf "$APP" "$PKG" "$OUT_DIR/$APP_NAME.app.dSYM"
    echo "오류: 실패 — 반쯤 만든 $APP_NAME.app · pkg 를 지웠다" >&2
  fi
  return $rc
}
trap on_exit EXIT

# ---- 0. 사전 점검 (빌드 전에 — 4분 빌드 뒤에 서명 자산이 없다고 죽지 않게) -----------------------------------------------
for tool in swift xcrun vtool codesign productbuild pkgutil plutil security lipo xattr dwarfdump /usr/bin/python3; do
  command -v "$tool" >/dev/null 2>&1 || die "필요한 도구가 없다: $tool"
done
[[ -f "$ENTITLEMENTS" ]] || die "엔타이틀먼트 파일이 없다: $ENTITLEMENTS"
plutil -lint "$ENTITLEMENTS" >/dev/null || die "엔타이틀먼트 plist 가 깨졌다: $ENTITLEMENTS"

# MAS 갈래 유무 → 엄격/리허설.
if grep -rqE '^[[:space:]]*#[[:space:]]*(if|elseif)[^/]*CHECK_MAS' "$ROOT/Sources"; then
  [[ -z "${MAS_REHEARSAL:-}" ]] || die "MAS_REHEARSAL 은 CHECK_MAS 갈래가 없는 소스에서만 쓴다 — 이 소스에는 갈래가 있다(제출본에서 게이트 ② 를 끌 수 없다)"
  REHEARSAL=0
  PKG="$OUT_DIR/$APP_NAME.pkg"
else
  [[ "${MAS_REHEARSAL:-}" == 1 ]] || die "Sources 에 '#if … CHECK_MAS' 갈래가 없다 — 자가 업데이트·타사 자격증명 코드가 그대로 들어간다. 맥 앱스토어 판 앱 코드를 먼저 병합하라(파이프라인 리허설만이면 MAS_REHEARSAL=1)"
  REHEARSAL=1
  PKG="$OUT_DIR/$APP_NAME-rehearsal.pkg"
  warn "리허설 — 이 소스에는 CHECK_MAS 갈래가 없다. 게이트 ② 는 경고로만 돌고 산출물은 $(basename "$PKG") 이다. 이 pkg 는 올리지 마라."
fi

# 버전·build 는 Developer ID 릴리스(build-local.sh)와 한 줄로 센다. 낮으면 서버가 구버전으로 본다.
DEV_VERSION="$(awk '/<key>CFBundleShortVersionString<\/key>/ { getline; gsub(/.*<string>|<\/string>.*/, ""); print; exit }' "$ROOT/scripts/build-local.sh")"
DEV_BUILD="$(awk '/<key>CFBundleVersion<\/key>/ { getline; gsub(/.*<string>|<\/string>.*/, ""); print; exit }' "$ROOT/scripts/build-local.sh")"
if [[ "$DEV_BUILD" =~ ^[0-9]+$ ]]; then
  (( BUILD >= DEV_BUILD )) || die "build $BUILD 이 Developer ID 판 build $DEV_BUILD(scripts/build-local.sh)보다 낮다 — 서버 게이트가 이 판을 구버전으로 본다"
  if [[ "$BUILD" != "$DEV_BUILD" || "$VERSION" != "$DEV_VERSION" ]]; then
    warn "Developer ID 판은 $DEV_VERSION ($DEV_BUILD), 이 MAS 판은 $VERSION ($BUILD) — 같은 커밋이면 같은 값이어야 한다. MAS 만 다시 올리는 경우라면 다음 DMG 릴리스는 $BUILD 위에서 이어 간다."
  fi
else
  warn "scripts/build-local.sh 에서 build 번호를 읽지 못했다([$DEV_BUILD]) — 교차 확인을 건너뛴다"
fi

# anon 키: 있어야 하고, anon 이어야 한다(service_role 을 앱에 실으면 공개 바이너리에서 누구나 관리자다).
[[ -n "${CHECK_SUPABASE_ANON_KEY:-}" ]] || die "CHECK_SUPABASE_ANON_KEY 가 없다 — .env.local 에 넣거나 환경으로 준다(키 없는 번들은 심사관이 로그인하지 못한다)"
KEY_ROLE="$(printf '%s' "$CHECK_SUPABASE_ANON_KEY" | /usr/bin/python3 -I -c '
import base64, json, sys
k = sys.stdin.read().strip()
if any(c.isspace() for c in k): print("whitespace"); sys.exit()
if k.startswith("sb_publishable_"): print("anon"); sys.exit()
if k.startswith("sb_secret_"): print("secret"); sys.exit()
parts = k.split(".")
if len(parts) != 3: print("not-a-jwt"); sys.exit()
try:
    body = parts[1] + "=" * (-len(parts[1]) % 4)
    print(json.loads(base64.urlsafe_b64decode(body)).get("role", "missing"))
except Exception:
    print("undecodable")
')"
[[ "$KEY_ROLE" == "anon" ]] || die "CHECK_SUPABASE_ANON_KEY 가 anon 키가 아니다(role=$KEY_ROLE)"

# 개인정보 매니페스트(맥 앱스토어 판 앱 코드가 만든다).
[[ -f "$PRIVACY_MANIFEST" ]] || die "개인정보 매니페스트가 없다: $PRIVACY_MANIFEST (MAS_PRIVACY_MANIFEST 로 다른 경로를 줄 수 있다)"
plutil -lint "$PRIVACY_MANIFEST" >/dev/null || die "개인정보 매니페스트 plist 가 깨졌다: $PRIVACY_MANIFEST"
plutil -extract NSPrivacyAccessedAPITypes json -o /dev/null "$PRIVACY_MANIFEST" 2>/dev/null \
  || die "개인정보 매니페스트에 NSPrivacyAccessedAPITypes 가 없다: $PRIVACY_MANIFEST"

# 서명 자산.
[[ -f "$PROFILE" ]] || die "프로비저닝 프로파일이 없다: $PROFILE"
[[ -f "$INSTALLER_KEYCHAIN" ]] || die "설치 패키지 서명 키체인이 없다: $INSTALLER_KEYCHAIN"
[[ -f "$KEYCHAIN_PASSWORD_FILE" ]] || die "키체인 암호 파일이 없다: $KEYCHAIN_PASSWORD_FILE"
# 이름이 같은 인증서가 둘이면(갱신 직후) codesign 이 'ambiguous' 로 죽는다 — 해시로 하나를 고른다.
APP_IDENTITY_HASHES="$(security find-identity -v -p codesigning | awk -v want="\"$APP_IDENTITY\"" 'index($0, want) { print $2 }' | sort -u)"
[[ -n "$APP_IDENTITY_HASHES" ]] || die "로그인 키체인에 유효한 '$APP_IDENTITY' 가 없다"
if [[ -n "${MAS_APP_IDENTITY_HASH:-}" ]]; then
  grep -qxF "$MAS_APP_IDENTITY_HASH" <<< "$APP_IDENTITY_HASHES" || die "MAS_APP_IDENTITY_HASH 가 '$APP_IDENTITY' 의 유효한 인증서가 아니다"
  APP_IDENTITY_HASH="$MAS_APP_IDENTITY_HASH"
else
  [[ "$APP_IDENTITY_HASHES" != *$'\n'* ]] \
    || die "'$APP_IDENTITY' 가 여럿이다(유효한 인증서 둘) — 프로파일에 든 쪽의 SHA-1 을 MAS_APP_IDENTITY_HASH 로 준다: $(echo "$APP_IDENTITY_HASHES" | tr '\n' ' ')"
  APP_IDENTITY_HASH="$APP_IDENTITY_HASHES"
fi
INSTALLER_IDENTITIES="$(security find-identity -v "$INSTALLER_KEYCHAIN")"
grep -qF "\"$INSTALLER_IDENTITY\"" <<< "$INSTALLER_IDENTITIES" || die "$INSTALLER_KEYCHAIN 에 유효한 '$INSTALLER_IDENTITY' 가 없다"

# 프로파일 해석(게이트 ④ 앞부분 — 인증서 대조는 서명 뒤).
security cms -D -i "$PROFILE" > "$TMP/profile.plist" 2>/dev/null || die "프로파일을 풀지 못했다: $PROFILE"
/usr/bin/python3 -I - "$TMP/profile.plist" "$ENTITLEMENTS" "$TEAM_ID" "$BUNDLE_ID" <<'PY' || die "프로파일 점검 실패(위)"
import datetime, plistlib, sys
prof_path, ent_path, team, bundle = sys.argv[1:5]
prof = plistlib.load(open(prof_path, "rb"))
ent = plistlib.load(open(ent_path, "rb"))
pe = prof.get("Entitlements", {})
errors = []
want_app_id = f"{team}.{bundle}"
if pe.get("com.apple.application-identifier") != want_app_id:
    errors.append(f"프로파일 앱 ID {pe.get('com.apple.application-identifier')} != {want_app_id}")
if team not in prof.get("TeamIdentifier", []):
    errors.append(f"프로파일 팀 {prof.get('TeamIdentifier')} 에 {team} 없음")
if "OSX" not in prof.get("Platform", []):
    errors.append(f"맥 프로파일이 아니다: Platform={prof.get('Platform')}")
if prof.get("ProvisionedDevices") or prof.get("ProvisionsAllDevices"):
    errors.append("기기 목록이 있는 개발·Developer ID 프로파일이다 — MAC_APP_STORE 배포 프로파일이 필요하다")
now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
exp = prof.get("ExpirationDate")
if exp is None or exp <= now:
    errors.append(f"프로파일 만료: {exp}")
elif (exp - now).days < 30:
    print(f"경고: 프로파일이 {(exp - now).days}일 뒤 만료된다({exp})", file=sys.stderr)
if ent.get("com.apple.application-identifier") != want_app_id:
    errors.append(f"엔타이틀먼트 앱 ID {ent.get('com.apple.application-identifier')} != {want_app_id}")
if ent.get("com.apple.developer.team-identifier") != team:
    errors.append(f"엔타이틀먼트 팀 {ent.get('com.apple.developer.team-identifier')} != {team}")
if ent.get("com.apple.security.app-sandbox") is not True:
    errors.append("엔타이틀먼트에 app-sandbox 가 없다(MAS 필수)")
if "com.apple.security.get-task-allow" in ent:
    errors.append("배포 서명에 get-task-allow 가 있다")
# 샌드박스 키(com.apple.security.*)가 아닌 것은 프로파일이 허락해야 한다.
for k, v in ent.items():
    if k.startswith("com.apple.security."):
        continue
    if k not in pe:
        errors.append(f"프로파일이 허락하지 않는 엔타이틀먼트: {k}")
    elif isinstance(v, str) and isinstance(pe[k], str) and v != pe[k] and not pe[k].endswith("*"):
        errors.append(f"엔타이틀먼트 {k}={v} 가 프로파일 값 {pe[k]} 과 다르다")
for e in errors:
    print("  - " + e, file=sys.stderr)
sys.exit(1 if errors else 0)
PY
log "사전 점검 통과 — $VERSION ($BUILD) · 앱 서명 $APP_IDENTITY · 설치 서명 $INSTALLER_IDENTITY · 프로파일 $(plutil -extract Name raw -o - "$TMP/profile.plist")"

# ---- 1. 빌드 (게이트 ①) ------------------------------------------------------------------------------------------------
# -Xswiftc 는 실행 타깃과 CheckCore 둘 다에 간다(빈 패키지로 확인: 두 모듈·두 아키텍처 모두 #if CHECK_MAS 쪽이 컴파일된다).
SWIFT_ARGS=(-c release --arch arm64 --arch x86_64 --scratch-path "$SCRATCH" -Xswiftc -DCHECK_MAS --product check)
BUILD_PRODUCTS="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"
mkdir -p "$OUT_DIR"
BUILD_MARK="$TMP/build-started"
: > "$BUILD_MARK"
sleep 1   # 표지와 산출물이 같은 초에 찍혀 '새것' 판정이 흐려지지 않게
# 옛 산출물을 먼저 지운다 — 빌드가 실패하거나 아무것도 다시 안 만들면 아래에서 '없다'로 멈춘다(증분 빌드의 exit 0 은
# '다시 만들었다'가 아니다).
rm -f "$BUILD_PRODUCTS/check"
log "빌드: swift build ${SWIFT_ARGS[*]}"
swift build "${SWIFT_ARGS[@]}" >&2
BIN_SRC="$BUILD_PRODUCTS/check"
[[ -f "$BIN_SRC" ]] || die "빌드 산출물이 없다: $BIN_SRC"
[[ -n "$(find "$BIN_SRC" -newer "$BUILD_MARK")" ]] || die "$BIN_SRC 가 이번 빌드보다 오래됐다 — 옛 산출물을 패키징하려 한다"
STALE_SOURCE="$(find "$ROOT/Sources" "$ROOT/Package.swift" -type f -newer "$BIN_SRC" | awk 'NR == 1')"
[[ -z "$STALE_SOURCE" ]] || die "$BIN_SRC 가 소스보다 오래됐다(예: $STALE_SOURCE)"

# ---- 2. 조립 -----------------------------------------------------------------------------------------------------------
ASSEMBLING=1
# 옛 산출물을 먼저 지운다. 제출본 경로(엄격)에서는 리허설 pkg 도 지운다 — 한 폴더에 둘이 있으면 잘못 집는다.
rm -rf "$APP" "$PKG" "$OUT_DIR/$APP_NAME.app.dSYM" "$OUT_DIR/validate.log"
[[ "$REHEARSAL" == 1 ]] || rm -f "$OUT_DIR/$APP_NAME-rehearsal.pkg"
BIN_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"
BIN="$BIN_DIR/check"
mkdir -p "$BIN_DIR" "$RES_DIR"
cp "$BIN_SRC" "$BIN"

# 게이트 ③: SDK 스탬프. Xcode 27 기본 빌드 시스템은 sdk 를 배포 최소(14.0)로 적고, AppKit 은 그 숫자로 옛 호환 동작을 고른다
# (0.3.23 팝오버가 안 줄어 내려앉았다 — build-local.sh 주석). 여기서는 LD 도구 항목까지 보존한다(build-local.sh 는 지운다).
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
ARCHS="$(lipo -archs "$BIN" | tr ' ' '\n' | sort | tr '\n' ' ')"
[[ "$ARCHS" == "arm64 x86_64 " ]] || die "유니버설이 아니다: [$ARCHS]"
MIN_OS="$(vtool -show-build "$BIN" | awk '$1 == "minos" { print $2 }' | sort -u)"
[[ -n "$MIN_OS" && "$MIN_OS" != *$'\n'* ]] || die "minos 를 하나로 읽지 못했다: [$MIN_OS]"
LD_VERSION="$(vtool -show-build "$BIN" | awk '$1 == "tool" && $2 == "LD" { getline; if ($1 == "version") print $2 }' | sort -u)"
[[ "$LD_VERSION" != *$'\n'* ]] || die "슬라이스마다 LD 버전이 다르다: [$LD_VERSION]"
TOOL_ARGS=()
[[ -n "$LD_VERSION" ]] && TOOL_ARGS=(-tool ld "$LD_VERSION")
vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" ${TOOL_ARGS[@]+"${TOOL_ARGS[@]}"} -replace -output "$BIN.stamped" "$BIN" >&2
mv "$BIN.stamped" "$BIN"
SDK_STAMPS="$(vtool -show-build "$BIN" | awk '$1 == "sdk" { print $2 }' | sort -u | tr '\n' ' ')"
MIN_STAMPS="$(vtool -show-build "$BIN" | awk '$1 == "minos" { print $2 }' | sort -u | tr '\n' ' ')"
LD_STAMPS="$(vtool -show-build "$BIN" | awk '$1 == "tool" && $2 == "LD" { getline; print $2 }' | sort -u | tr '\n' ' ')"
[[ "$SDK_STAMPS" == "$SDK_VERSION " && "$MIN_STAMPS" == "$MIN_OS " ]] \
  || die "스탬프가 sdk [${SDK_STAMPS% }] minos [${MIN_STAMPS% }] — 기대 sdk $SDK_VERSION minos $MIN_OS"
[[ -z "$LD_VERSION" || "$LD_STAMPS" == "$LD_VERSION " ]] || die "LD 도구 항목이 사라졌다: [${LD_STAMPS% }] (기대 $LD_VERSION)"
log "스탬프: minos $MIN_OS · sdk $SDK_VERSION · LD ${LD_VERSION:-없음} · $ARCHS"

# 게이트 ②: CHECK_MAS 갈래가 컴파일됐다는 증거.
FOUND=()
for s in "${FORBIDDEN_STRINGS[@]}"; do
  (( ${#s} >= 16 )) || die "금지 문자열은 16바이트 이상이어야 한다(작은 문자열은 코드에 인라인된다): [$s]"
  if LC_ALL=C grep -a -F -q -- "$s" "$BIN"; then FOUND+=("$s"); fi
done
if (( ${#FOUND[@]} > 0 )); then
  if [[ "$REHEARSAL" == 1 ]]; then
    warn "리허설: 금지 문자열 ${#FOUND[@]}개가 바이너리에 있다(MAS 갈래 병합 전이라 예상된 일): ${FOUND[*]}"
  else
    die "CHECK_MAS 판 바이너리에 빠졌어야 할 코드가 있다: ${FOUND[*]}"
  fi
else
  log "금지 문자열 ${#FORBIDDEN_STRINGS[@]}개 — 바이너리에 0건"
fi

# 리소스 번들(Bundle.module · CheckCore 탐색기는 Contents/Resources 아래 **이름**으로 찾는다 — 식별자로 찾지 않는다).
# SwiftBuild 는 번들 식별자를 패키지 폴더 이름(워크트리 이름)으로 적는다 — 'v0351-maspipe.check.resources' 처럼 빌드한 곳마다 다르다.
# 제출본이 빌드 위치에 따라 달라지지 않게 앱 ID 아래로 고정한다.
for TARGET in check CheckCore; do
  SRC_BUNDLE="$BUILD_PRODUCTS/check_$TARGET.bundle"
  [[ -d "$SRC_BUNDLE" ]] || die "리소스 번들이 없다: $SRC_BUNDLE"
  cp -R "$SRC_BUNDLE" "$RES_DIR/"
  plutil -replace CFBundleIdentifier -string "$BUNDLE_ID.resources.$TARGET" "$RES_DIR/check_$TARGET.bundle/Contents/Info.plist"
done

CONFIG_PLIST="$RES_DIR/CheckConfig.plist"
plutil -create xml1 "$CONFIG_PLIST"
plutil -insert CHECK_SUPABASE_ANON_KEY -string "$CHECK_SUPABASE_ANON_KEY" "$CONFIG_PLIST"
cp "$ROOT/packaging/appicon/AppIcon.icns" "$RES_DIR/AppIcon.icns"
cp "$PRIVACY_MANIFEST" "$RES_DIR/PrivacyInfo.xcprivacy"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

# Info.plist — 손으로 쓴 heredoc 대신 plutil 로 키마다 넣는다(값에 XML 특수문자가 와도 깨지지 않는다).
#   · CFBundleName 은 ASCII(AingCheck): 메뉴 막대 앱(LSUIElement)이라 화면에 거의 안 나오고, 도구 호환을 우선한다.
#     사람에게 보이는 이름은 CFBundleDisplayName(아잉체크).
#   · CFBundleDevelopmentRegion 은 Developer ID 판처럼 **넣지 않는다** — 넣으면 시스템 패널 언어·Locale.current 가 판마다 달라진다.
#   · DT* · BuildMachineOSBuild 는 지금 빌드한 툴체인에서 읽는다(지어내지 않는다). 리소스 번들 plist 와 다르면 경고한다.
XCODEBUILD_VERSION="$(xcodebuild -version)"
XCODE_VERSION="$(awk '/^Xcode / { print $2 }' <<< "$XCODEBUILD_VERSION")"
XCODE_BUILD="$(awk '/^Build version / { print $3 }' <<< "$XCODEBUILD_VERSION")"
SDK_BUILD="$(xcrun --sdk macosx --show-sdk-build-version)"
OS_BUILD="$(sw_vers -buildVersion)"
IFS=. read -r XC_MAJOR XC_MINOR XC_PATCH <<< "$XCODE_VERSION"
DT_XCODE="$(printf '%02d%d%d' "$XC_MAJOR" "${XC_MINOR:-0}" "${XC_PATCH:-0}")"
for v in "$XCODE_BUILD" "$SDK_BUILD" "$OS_BUILD" "$SDK_VERSION" "$DT_XCODE"; do
  [[ "$v" =~ ^[A-Za-z0-9.]+$ ]] || die "툴체인 값을 읽지 못했다: [$v]"
done
PLIST="$APP/Contents/Info.plist"
plutil -create xml1 "$PLIST"
pl_str() { plutil -insert "$1" -string "$2" "$PLIST"; }
pl_bool() { plutil -insert "$1" -bool "$2" "$PLIST"; }
pl_str CFBundleExecutable check
pl_str CFBundleIdentifier "$BUNDLE_ID"
pl_str CFBundleName "$APP_NAME"
pl_str CFBundleDisplayName "$DISPLAY_NAME"
pl_str CFBundlePackageType APPL
pl_str CFBundleInfoDictionaryVersion 6.0
plutil -insert CFBundleSupportedPlatforms -json '["MacOSX"]' "$PLIST"
pl_str CFBundleIconFile AppIcon
pl_str CFBundleShortVersionString "$VERSION"
pl_str CFBundleVersion "$BUILD"
pl_str LSMinimumSystemVersion "$MIN_OS"
pl_bool LSUIElement true
pl_str LSApplicationCategoryType "$CATEGORY"
pl_bool ITSAppUsesNonExemptEncryption false
pl_str DTPlatformName macosx
pl_str DTPlatformVersion "$SDK_VERSION"
pl_str DTPlatformBuild "$SDK_BUILD"
pl_str DTSDKName "macosx$SDK_VERSION"
pl_str DTSDKBuild "$SDK_BUILD"
pl_str DTXcode "$DT_XCODE"
pl_str DTXcodeBuild "$XCODE_BUILD"
pl_str DTCompiler com.apple.compilers.llvm.clang.1_0
pl_str BuildMachineOSBuild "$OS_BUILD"
plutil -lint "$PLIST" >/dev/null || die "Info.plist 가 깨졌다"
[[ "$(plutil -extract CFBundleDisplayName raw -o - "$PLIST")" == "$DISPLAY_NAME" ]] || die "CFBundleDisplayName 이 [$DISPLAY_NAME] 로 들어가지 않았다"
RES_PLIST="$RES_DIR/check_check.bundle/Contents/Info.plist"
for k in DTSDKName DTSDKBuild DTXcode DTXcodeBuild BuildMachineOSBuild; do
  a="$(plutil -extract "$k" raw -o - "$PLIST")"
  b="$(plutil -extract "$k" raw -o - "$RES_PLIST" 2>/dev/null || true)"
  [[ -z "$b" || "$a" == "$b" ]] || warn "$k: 앱 $a · 리소스 번들 $b — 리소스 번들이 다른 툴체인에서 만들어진 캐시일 수 있다(rm -rf .build-mas 뒤 다시)"
done

# dSYM(크래시 기호화용 — 올리지는 않는다). UUID 가 바이너리와 같을 때만 남긴다.
if [[ -d "$BUILD_PRODUCTS/check.dSYM" ]]; then
  BIN_UUIDS="$(dwarfdump --uuid "$BIN" | awk '{ print $2 }' | sort | tr '\n' ' ')"
  DSYM_UUIDS="$(dwarfdump --uuid "$BUILD_PRODUCTS/check.dSYM" | awk '{ print $2 }' | sort | tr '\n' ' ')"
  if [[ "$BIN_UUIDS" == "$DSYM_UUIDS" ]]; then
    cp -R "$BUILD_PRODUCTS/check.dSYM" "$OUT_DIR/$APP_NAME.app.dSYM"
  else
    warn "dSYM UUID 가 바이너리와 다르다 — 남기지 않는다"
  fi
fi

# 게이트 ⑥ 앞부분: 확장 속성을 걷고 quarantine 0 을 확인한다.
xattr -cr "$APP"
QUARANTINED="$(xattr -lr "$APP" 2>/dev/null | grep -c 'com.apple.quarantine' || true)"
[[ "$QUARANTINED" == 0 ]] || die "com.apple.quarantine 이 붙은 파일이 $QUARANTINED 개 있다"

# ---- 3. 서명 (안쪽부터, --deep 없이 — 애플 문서가 배포 서명에 --deep 을 금한다) ------------------------------------------
# 타임스탬프는 끈다 — MAS 는 애플이 다시 서명하고, 타임스탬프 서버(네트워크)를 부를 이유가 없다. 하드닝 런타임은 MAS 에 필수는
# 아니지만 Developer ID 판과 같은 런타임 제약으로 돌게 켠다.
for TARGET in check CheckCore; do
  codesign --force --sign "$APP_IDENTITY_HASH" --timestamp=none "$RES_DIR/check_$TARGET.bundle" >&2
done
codesign --force --sign "$APP_IDENTITY_HASH" --entitlements "$ENTITLEMENTS" --options runtime --timestamp=none "$APP" >&2
codesign --verify --deep --strict --verbose=2 "$APP" >&2 || die "서명 검증 실패"

# 게이트 ④ 뒷부분 · ⑤.
codesign -d --entitlements - --xml "$APP" > "$TMP/signed-entitlements.plist" 2>/dev/null || die "서명된 엔타이틀먼트를 읽지 못했다"
codesign -dvv "$APP" > "$TMP/codesign-dvv.txt" 2>&1 || die "codesign -dvv 실패"
codesign -d --extract-certificates="$TMP/cert" "$APP" >/dev/null 2>&1 || die "서명 인증서를 꺼내지 못했다"
/usr/bin/python3 -I - "$TMP/signed-entitlements.plist" "$ENTITLEMENTS" "$TMP/codesign-dvv.txt" "$TMP/cert0" "$TMP/profile.plist" \
  "$BUNDLE_ID" "$TEAM_ID" "$APP_IDENTITY" <<'PY' || die "서명 점검 실패(위)"
import hashlib, plistlib, sys
signed_p, want_p, dvv_p, cert_p, prof_p, bundle, team, identity = sys.argv[1:9]
errors = []
signed = plistlib.load(open(signed_p, "rb"))
want = plistlib.load(open(want_p, "rb"))
if signed != want:
    extra = sorted(set(signed) - set(want)); missing = sorted(set(want) - set(signed))
    diff = sorted(k for k in set(signed) & set(want) if signed[k] != want[k])
    errors.append(f"서명된 엔타이틀먼트가 파일과 다르다 — 군더더기 {extra} · 빠짐 {missing} · 값 다름 {diff}")
fields = {}
authorities = []
for line in open(dvv_p, encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if "=" in line:
        k, v = line.split("=", 1)
        if k == "Authority":
            authorities.append(v)
        else:
            fields.setdefault(k, v)
if fields.get("Identifier") != bundle:
    errors.append(f"서명 Identifier {fields.get('Identifier')} != {bundle}")
if fields.get("TeamIdentifier") != team:
    errors.append(f"서명 TeamIdentifier {fields.get('TeamIdentifier')} != {team}")
if not authorities or authorities[0] != identity:
    errors.append(f"서명자 {authorities[:1]} != {identity}")
leaf = open(cert_p, "rb").read()
prof = plistlib.load(open(prof_p, "rb"))
if leaf not in prof.get("DeveloperCertificates", []):
    errors.append(f"서명 인증서(SHA-1 {hashlib.sha1(leaf).hexdigest().upper()})가 프로파일에 없다 — 프로파일을 이 인증서로 다시 만들어야 한다")
for e in errors:
    print("  - " + e, file=sys.stderr)
sys.exit(1 if errors else 0)
PY
log "서명: $(grep -m1 '^Authority=' "$TMP/codesign-dvv.txt") · 엔타이틀먼트 = packaging/mas.entitlements · 인증서가 프로파일에 있음"

# ---- 4. 설치 패키지 (게이트 ⑦) -------------------------------------------------------------------------------------------
# 암호는 stdin 으로만 넘긴다(argv 는 ps 에 보인다). 전용 키체인은 자동 잠금이 꺼져 있어 다시 잠그지 않는다.
security unlock-keychain "$INSTALLER_KEYCHAIN" < "$KEYCHAIN_PASSWORD_FILE" >/dev/null 2>&1 \
  || die "설치 패키지 키체인을 열지 못했다: $INSTALLER_KEYCHAIN (암호 파일 $KEYCHAIN_PASSWORD_FILE)"
productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" --keychain "$INSTALLER_KEYCHAIN" \
  --timestamp=none "$PKG" >&2 || die "productbuild 실패"
pkgutil --check-signature "$PKG" > "$TMP/pkg-signature.txt" 2>&1 || { cat "$TMP/pkg-signature.txt" >&2; die "pkg 서명 확인 실패"; }
grep -qF "$INSTALLER_IDENTITY" "$TMP/pkg-signature.txt" || { cat "$TMP/pkg-signature.txt" >&2; die "pkg 서명자가 '$INSTALLER_IDENTITY' 가 아니다"; }
pkgutil --expand-full "$PKG" "$TMP/expanded" >/dev/null || die "pkg 를 펼치지 못했다"
EXPANDED_APP="$(find "$TMP/expanded" -maxdepth 4 -type d -name "$APP_NAME.app" | awk 'NR == 1')"
[[ -n "$EXPANDED_APP" ]] || die "pkg 안에 $APP_NAME.app 이 없다"
codesign --verify --deep --strict "$EXPANDED_APP" >&2 || die "pkg 안 앱의 서명이 깨졌다"
codesign -dvvv "$APP" > "$TMP/dvvv-app.txt" 2>&1 || die "codesign -dvvv 실패: $APP"
codesign -dvvv "$EXPANDED_APP" > "$TMP/dvvv-pkg.txt" 2>&1 || die "codesign -dvvv 실패: $EXPANDED_APP"
CDHASH_APP="$(awk -F= '/^CDHash=/ && !seen { print $2; seen = 1 }' "$TMP/dvvv-app.txt")"
CDHASH_PKG="$(awk -F= '/^CDHash=/ && !seen { print $2; seen = 1 }' "$TMP/dvvv-pkg.txt")"
[[ -n "$CDHASH_APP" && "$CDHASH_APP" == "$CDHASH_PKG" ]] || die "pkg 안 앱 CDHash [$CDHASH_PKG] != 서명한 앱 [$CDHASH_APP]"
[[ "$(plutil -extract CFBundleVersion raw -o - "$EXPANDED_APP/Contents/Info.plist")" == "$BUILD" ]] || die "pkg 안 앱 build 가 $BUILD 이 아니다"
QUARANTINED="$(xattr -lr "$EXPANDED_APP" 2>/dev/null | grep -c 'com.apple.quarantine' || true)"
[[ "$QUARANTINED" == 0 ]] || die "pkg 안 앱에 com.apple.quarantine 이 $QUARANTINED 개"
[[ "$(plutil -extract CHECK_SUPABASE_ANON_KEY raw -o - "$EXPANDED_APP/Contents/Resources/CheckConfig.plist")" == "$CHECK_SUPABASE_ANON_KEY" ]] \
  || die "pkg 안 앱 CheckConfig.plist 에 anon 키가 없다"
log "pkg: $PKG ($(du -h "$PKG" | awk '{ print $1 }')) · 서명 $INSTALLER_IDENTITY · 안의 앱 CDHash $CDHASH_PKG"

# ---- 5. 검증 (선택 — 애플에 읽기 전용으로 묻는다, 올리지 않는다) ---------------------------------------------------------
if [[ "$VALIDATE" == 1 ]]; then
  [[ -n "$ASC_API_ISSUER" ]] || die "ASC_API_ISSUER 가 없다 — .env.local 에 넣거나 환경으로 준다(App Store Connect › 사용자와 접근 › 통합 › 키)"
  VALIDATE_LOG="$OUT_DIR/validate.log"
  # --apple-id 로 레코드를 직접 집는다. 번들 ID 로 찾게 두면 레코드에 macOS 플랫폼이 붙기 전에는
  # "Unable to find Apple ID for Bundle ID 'com.yehsung.aingcheck' on platform 'macOS App'" 로 죽는다(2026-10-14 실측).
  log "altool --validate-app (앱 $ASC_APPLE_ID · 키 $ASC_API_KEY)"
  set +e
  xcrun altool --validate-app "$PKG" --apple-id "$ASC_APPLE_ID" --api-key "$ASC_API_KEY" --api-issuer "$ASC_API_ISSUER" \
    > "$VALIDATE_LOG" 2>&1
  VALIDATE_RC=$?
  set -e
  cat "$VALIDATE_LOG" >&2
  [[ "$VALIDATE_RC" == 0 ]] || die "altool --validate-app 실패(rc=$VALIDATE_RC) — 전문: $VALIDATE_LOG"
  # rc 0 만 믿지 않는다(공증 스크립트가 실패를 삼킨 전례) — 성공 문구가 있어야 통과다.
  grep -qE 'VERIFY SUCCEEDED|No errors validating archive' "$VALIDATE_LOG" \
    || die "altool 이 rc 0 인데 성공 문구가 없다 — $VALIDATE_LOG 를 읽고 판정하라"
  log "검증 통과 — 업로드는 docs/release.md \"맥 앱스토어\" 의 명령으로 따로 한다"
fi

echo "$PKG"
