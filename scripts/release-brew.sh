#!/usr/bin/env bash
# aing-check brew 릴리즈 자동화.
#
# 사용법: ./scripts/release-brew.sh <버전> [--dry-run] [--server-only]
#   예:   ./scripts/release-brew.sh 0.2.0
#         ./scripts/release-brew.sh 0.2.0 --dry-run       # 실제 실행 없이 각 단계만 출력
#         ./scripts/release-brew.sh 0.2.0 --server-only   # 태그·릴리즈·Cask 커밋 없이 서버 릴리스 알림만 (재)게시
#
# 하는 일:
#   1) 사전점검 — gh 로그인, CHANGELOG.md 의 이번 버전 패치노트(서버 노트 규칙 포함), GH_OWNER,
#      공증된 dist/aing-check.zip(스테이플 검증 · 내부 버전 · 내부 build), tap 저장소, 서버의 현재 릴리스(build 역행 차단).
#      전부 부수효과보다 앞이다 — 하나라도 어긋나면 아무것도 건드리지 않고 멈춘다.
#   2) git 태그 v<버전> 생성/푸시, GitHub 릴리즈 생성 + zip 자산 업로드
#   3) sha256 계산 → packaging/homebrew/aing-check.rb 치환본을 tap 저장소에 커밋
#   4) tap 원격 게이트 — 원격보다 앞서 있으면 푸시하고, fetch 로 원격 Cask 를 되읽어 이번 version/sha256 인지 확인
#   5) 서버 릴리스 알림 게시(app_publish_release) — 실행 중인 앱이 몇 분 안에 새 버전을 안다.
#      반드시 4 뒤다: brew 가 아직 옛 cask 인데 앱이 "업데이트" 를 띄우면 [지금 업데이트] 가 아무것도 못 받는다.
#   6) 팀원 설치/업그레이드 명령 출력
#
# --server-only 는 1 → 4 → 5 만 한다(2·3 의 태그·릴리즈·Cask 커밋은 건너뜀). 게시가 실패했을 때 게시만 다시 하거나,
# 이미 brew 로 나간 현재 릴리스를 서버에 처음 심을 때 쓴다.
#
# 최초 1회 세팅과 전체 파이프라인은 docs/release.md 를 참고하세요.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ---------------------------------------------------------------------------
# 로그 / 유틸
# ---------------------------------------------------------------------------
log()  { echo "==> $*" >&2; }
warn() { echo "경고: $*" >&2; }
die()  { echo "오류: $*" >&2; exit 1; }

DRY_RUN=0
SERVER_ONLY=0
USAGE="사용법: ./scripts/release-brew.sh <버전> [--dry-run] [--server-only]"

# dry-run 에서는 경고 후 계속 진행하고, 실제 실행에서는 안내 후 종료한다.
missing() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    warn "$1 (dry-run 이므로 계속 진행합니다)"
  else
    die "$1"
  fi
}

# 부수효과가 있는 명령 실행기. dry-run 이면 실행하지 않고 출력만 한다.
run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] $*" >&2
    return 0
  fi
  "$@"
}

# 서버 응답(JSON) 해석과 노트 글자 수 세기에 쓴다. 시스템 python3 을 먼저 고른다 — PATH 앞의 conda 등은 맥마다 다르다.
PYTHON3="/usr/bin/python3"
[[ -x "$PYTHON3" ]] || PYTHON3="$(command -v python3 || true)"

# SQL 문자열 리터럴로 가둔다 — 작은따옴표는 두 번 쓴다. standard_conforming_strings(기본 on)라 역슬래시는 글자 그대로다.
# 따옴표를 변수 q 로 넣는 이유: macOS 기본 /bin/bash 3.2 는 "${s//\'/\'\'}" 의 치환 결과에 역슬래시를 남긴다
# (it's → it\'\'s, 실측) — 그대로 SQL 에 들어가면 서버에 저장되는 노트 글자가 바뀐다.
sql_quote() {
  local q="'"
  printf "'%s'" "${1//$q/$q$q}"
}

# CHANGELOG 섹션 → 서버에 게시할 노트 줄(한 줄에 하나). "- "/"* " 로 시작하는 항목 줄만 접두사를 떼고 앞뒤 공백을 걷는다 —
# 앱의 GitHub 본문 파서(CheckUpdateCheck.parseNotes)가 고르는 줄과 같다. 섹션 산문·빈 항목은 버린다.
changelog_bullets() {
  printf '%s\n' "$1" \
    | sed -n -e 's/^[[:space:]]*[-*] //p' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d'
}

# 노트 줄들 → array['…','…']::text[]. 항목이 없으면 array[]::text[] (서버 계약상 빈 배열은 허용).
notes_sql_array() {
  local out="" line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    out="${out:+$out,}$(sql_quote "$line")"
  done <<< "$1"
  printf 'array[%s]::text[]' "$out"
}

# 서버 계약(app_release_invalid)과 같은 노트 규칙을 부수효과 전에 건다: 항목 8개 이하, 항목마다 1..200자.
# 글자 수는 python 으로 센다 — 셸·awk 의 길이는 로케일에 따라 한글을 바이트로 세 3배로 부푼다.
# 통과하면 조용히 0, 어긋나면 이유 한 줄을 찍고 1.
notes_violation() {
  printf '%s' "$1" | "$PYTHON3" -c '
import sys
def fail(msg):
    sys.stdout.buffer.write(msg.encode("utf-8") + b"\n")
    sys.exit(1)
items = [l.strip(" ") for l in sys.stdin.buffer.read().decode("utf-8").split("\n") if l.strip(" ")]
if len(items) > 8:
    fail("항목이 %d줄입니다(서버는 8줄까지 받습니다)" % len(items))
for item in items:
    if len(item) > 200:
        fail("%d자인 항목이 있습니다(서버는 200자까지 받습니다): %s…" % (len(item), item[:20]))
'
}

# `supabase db query -o json` 표준출력에서 첫 행 r(jsonb)의 필드 하나를 찍는다(null·없음은 빈 줄).
# r 이 객체로 오든 JSON 문자열로 오든 받는다 — 링크드(Management API) 경로와 직접 접속 경로의 표현이 같다는 보장이 없다.
# JSON 앞에 잡음 줄이 섞여도 첫 JSON 값부터 읽는다. 해석이 안 되면 1.
release_json_field() {
  "$PYTHON3" -c '
import json, sys
field = sys.argv[1]
raw = sys.stdin.buffer.read().decode("utf-8", "replace")
doc, decoder = None, json.JSONDecoder()
for i, ch in enumerate(raw):
    if ch in "[{":
        try:
            doc = decoder.raw_decode(raw, i)[0]
            break
        except ValueError:
            continue
rows = doc if isinstance(doc, list) else [doc]
row = rows[0] if rows and isinstance(rows[0], dict) else {}
r = row.get("r")
if isinstance(r, str):
    try:
        r = json.loads(r)
    except ValueError:
        sys.exit(1)
if not isinstance(r, dict):
    sys.exit(1)
value = r.get(field)
sys.stdout.buffer.write(("" if value is None else str(value)).encode("utf-8") + b"\n")
' "$1"
}

# Cask 본문에서 stanza 값 하나를 꺼낸다 — `version "0.3.19"` → 0.3.19. 주석 줄은 첫 칸이 # 라 걸리지 않는다.
cask_value() {
  awk -v key="$1" '$1 == key { gsub(/"/, "", $2); print $2; exit }' <<< "$2"
}

# 링크된 프로젝트에 SQL 을 보낸다(인자 = SQL 문자열, 또는 -f <파일>). 인증은 CLI 가 키체인으로 한다 —
# 키를 명령행에 싣지 않고 .env.local 도 읽지 않는다. 표준출력은 JSON 만 받고(업데이트 안내 같은 잡음은 stderr),
# 오류 본문은 stderr 로 그대로 흘려 운영자가 원인을 보게 한다.
supabase_query() {
  supabase db query --linked --agent=no -o json "$@"
}

# supabase 조회가 실패했을 때의 안내. 원인은 대개 셋 중 하나다.
server_query_help() {
  cat >&2 <<EOF
  서버 조회(supabase db query --linked)가 실패했습니다. 대개 셋 중 하나입니다:
    1) 릴리스 알림 마이그레이션(app_release · app_latest_release · app_publish_release)이 아직 적용되지 않았다
       → docs/release.md "스키마 적용" 대로 먼저 적용하세요(PGRST202 · function does not exist).
    2) supabase CLI 가 다른 계정으로 로그인돼 있다(403) → 'supabase projects list' 에 xfnhfjvubetkdnfkfljg 가 보이는지 확인하고,
       안 보이면 'supabase login' 으로 소유 계정에 다시 로그인하세요.
    3) 이 체크아웃이 프로젝트에 link 되지 않았다 → 'supabase link --project-ref xfnhfjvubetkdnfkfljg'
EOF
}

# ---------------------------------------------------------------------------
# 인자 파싱
# ---------------------------------------------------------------------------
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --server-only) SERVER_ONLY=1 ;;
    -h|--help)
      echo "$USAGE"
      echo "  예:   ./scripts/release-brew.sh 0.2.0"
      echo "        ./scripts/release-brew.sh 0.2.0 --dry-run       # 실제 실행 없이 각 단계만 출력"
      echo "        ./scripts/release-brew.sh 0.2.0 --server-only   # 서버 릴리스 알림만 (재)게시 — 실패한 게시 재시도 · 현재 릴리스 시드"
      exit 0
      ;;
    -*)
      die "알 수 없는 옵션 '$arg' ($USAGE)"
      ;;
    *)
      if [[ -n "$VERSION" ]]; then
        die "버전 인자가 중복됩니다 ('$VERSION' 와 '$arg')."
      fi
      VERSION="$arg"
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  die "버전을 지정해야 합니다. 예: ./scripts/release-brew.sh 0.2.0"
fi

# 편의상 앞의 v 는 떼어낸다 (v0.2.0 -> 0.2.0).
VERSION="${VERSION#v}"

VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*$'
if [[ ! "$VERSION" =~ $VERSION_RE ]]; then
  die "버전 형식이 올바르지 않습니다: '$VERSION' (예: 0.2.0)"
fi

TAG="v$VERSION"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY-RUN 모드: 실제 태그/릴리즈/푸시/서버 게시 없이 각 단계만 출력합니다(tap 원격 fetch·읽기만은 실제로 합니다)."
fi
if [[ "$SERVER_ONLY" -eq 1 ]]; then
  log "SERVER-ONLY 모드: 태그·GitHub 릴리즈·Cask 커밋은 건너뛰고 사전점검 → tap 원격 게이트 → 서버 게시만 합니다."
fi
log "릴리즈 버전: $VERSION (태그 $TAG)"

# ---------------------------------------------------------------------------
# GH_OWNER 확정 (환경변수 우선, 없으면 .env.local 의 CHECK_GH_OWNER)
# ---------------------------------------------------------------------------
if [[ -z "${GH_OWNER:-}" && -f "$ROOT/.env.local" ]]; then
  ENV_OWNER_LINE="$(grep -E '^CHECK_GH_OWNER=' "$ROOT/.env.local" | tail -n 1 || true)"
  if [[ -n "$ENV_OWNER_LINE" ]]; then
    GH_OWNER="${ENV_OWNER_LINE#CHECK_GH_OWNER=}"
    # 감싸는 따옴표 제거
    GH_OWNER="${GH_OWNER%\"}"; GH_OWNER="${GH_OWNER#\"}"
    GH_OWNER="${GH_OWNER%\'}"; GH_OWNER="${GH_OWNER#\'}"
  fi
fi

if [[ -z "${GH_OWNER:-}" ]]; then
  missing "GH_OWNER 가 설정되지 않았습니다. 'export GH_OWNER=<GitHub 사용자/조직>' 또는 .env.local 에 CHECK_GH_OWNER=<...> 를 추가하세요."
  # dry-run 에서 흐름을 계속 보여주기 위한 자리표시자.
  GH_OWNER="GH_OWNER"
fi
log "GH_OWNER: $GH_OWNER"

# ---------------------------------------------------------------------------
# 사전점검
# ---------------------------------------------------------------------------
log "사전점검: gh CLI 로그인"
if ! command -v gh >/dev/null 2>&1; then
  missing "gh CLI 가 설치되어 있지 않습니다. 'brew install gh' 후 'gh auth login' 을 실행하세요."
elif ! gh auth status >/dev/null 2>&1; then
  missing "gh CLI 에 로그인되어 있지 않습니다. 'gh auth login' 을 먼저 실행하세요."
fi

if [[ -z "$PYTHON3" ]]; then
  missing "python3 을 찾을 수 없습니다(노트 글자 수 확인 · 서버 응답 해석에 필요). 'xcode-select --install' 로 명령행 도구를 설치하세요."
fi

# 패치노트: CHANGELOG.md 의 "## <버전>" 섹션이 곧 릴리스 노트이자 앱 업데이트 배너 문구다.
# 이 게이트를 사전점검 맨 앞에 두는 이유: 노트가 비어 있으면 태그/푸시 같은 되돌리기 번거로운 부수효과가
# 일어나기 전에 즉시 멈추기 위해서다(빈 패치노트 배포를 구조적으로 차단).
CHANGELOG="$ROOT/CHANGELOG.md"
log "사전점검: CHANGELOG.md 의 $VERSION 패치노트"

# "## <버전>" 다음 줄부터 다음 "## " 직전까지. 빈 줄은 지워 앞뒤 공백을 정리한다(항목은 한 줄씩이라 무손실).
extract_changelog_section() {
  awk -v header="## $1" '
    $0 == header { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
  ' "$CHANGELOG" | sed -e '/^[[:space:]]*$/d'
}

RELEASE_NOTES=""
if [[ ! -f "$CHANGELOG" ]]; then
  missing "$CHANGELOG 이 없습니다. 이번 버전의 변경 내용을 '## $VERSION' 섹션으로 먼저 적으세요."
else
  CHANGELOG_SECTION="$(extract_changelog_section "$VERSION")"
  if [[ -z "$CHANGELOG_SECTION" ]]; then
    missing "CHANGELOG.md 에 '## $VERSION' 섹션이 없거나 비어 있습니다. 이 섹션이 그대로 릴리스 노트가 되고 앱의 새 버전 배너에 뜨므로, 빈 패치노트로는 배포하지 않습니다 — 이번 버전에서 무엇이 바뀌었는지 사용자 문장으로 먼저 적으세요."
  else
    log "패치노트 확인됨:"
    printf '%s\n' "$CHANGELOG_SECTION" | sed 's/^/    | /' >&2
    RELEASE_NOTES="$CHANGELOG_SECTION"
  fi
fi

# 서버 알림 노트 — 설치 안내 줄을 붙이기 전의 섹션에서 항목 줄만 뽑는다((b) 가 RELEASE_NOTES 뒤에 안내 줄을 덧붙인다).
# 서버 계약 위반은 여기서 미리 막는다: 안 그러면 태그·릴리즈·tap 이 다 나간 뒤 맨 끝 게시에서야 app_release_invalid 로 멈춘다.
SERVER_NOTES="$(changelog_bullets "$RELEASE_NOTES")"
NOTES_COUNT="$(printf '%s' "$SERVER_NOTES" | grep -c . || true)"
if [[ -n "$RELEASE_NOTES" ]]; then
  if [[ "$NOTES_COUNT" -eq 0 ]]; then
    warn "'## $VERSION' 섹션에 '- ' 로 시작하는 항목 줄이 없습니다 — 앱 배너와 서버 알림에는 노트 없이 뜹니다."
  elif [[ -n "$PYTHON3" ]]; then
    if NOTES_PROBLEM="$(notes_violation "$SERVER_NOTES")"; then
      log "서버 알림 노트 ${NOTES_COUNT}줄 확인됨 (8줄 이하 · 한 줄 200자 이하)"
    else
      missing "CHANGELOG.md '## $VERSION' 의 항목이 서버 알림 규칙(8줄 이하 · 한 줄 200자 이하)에 어긋납니다 — $NOTES_PROBLEM. 서버가 app_release_invalid 로 거절하므로 태그를 만들기 전에 고치세요."
    fi
  fi
fi

ZIP="$ROOT/dist/aing-check.zip"
# dry-run 에서 zip 이 없거나 build 가 이상할 때 흐름을 계속 보여 주기 위한 자리표시자(서버는 0 을 거절한다).
BUILD="0"
log "사전점검: 공증된 배포 zip — $ZIP"
if [[ ! -f "$ZIP" ]]; then
  missing "$ZIP 이 없습니다. 먼저 './scripts/package-notarized.sh' 로 공증된 배포 zip 을 만드세요."
else
  # zip 안 aing-check/aing-check.app 의 공증 스테이플을 검증한다.
  STAPLE_TMP="$(mktemp -d)"
  STAPLE_OK=0
  if unzip -q "$ZIP" -d "$STAPLE_TMP" >/dev/null 2>&1 && [[ -d "$STAPLE_TMP/aing-check/aing-check.app" ]]; then
    if xcrun stapler validate "$STAPLE_TMP/aing-check/aing-check.app" >/dev/null 2>&1; then
      STAPLE_OK=1
    fi
  fi
  rm -rf "$STAPLE_TMP"
  if [[ "$STAPLE_OK" -eq 1 ]]; then
    log "공증 스테이플 확인됨 (aing-check/aing-check.app)"
  else
    missing "aing-check.app 의 공증 스테이플 검증에 실패했습니다. './scripts/package-notarized.sh' 로 공증/스테이플된 zip 을 다시 만드세요."
  fi

  # zip 내부 앱 버전 == 릴리스 버전 게이트. v0.2.3 사고(패키징이 키체인 잠금으로 실패했는데 파이프가 exit 를
  # 삼켜, 낡은 0.2.2 zip 이 그대로 태깅됨) 재발 방지 — 스테이플이 유효해도 버전이 다르면 낡은 산출물이다.
  ZIP_VERSION="$(unzip -p "$ZIP" "aing-check/aing-check.app/Contents/Info.plist" 2>/dev/null \
    | plutil -extract CFBundleShortVersionString raw - 2>/dev/null || true)"
  if [[ "$ZIP_VERSION" == "$VERSION" ]]; then
    log "zip 내부 앱 버전 확인됨 ($ZIP_VERSION)"
  else
    missing "zip 내부 앱 버전($ZIP_VERSION)이 릴리스 버전($VERSION)과 다릅니다 — 낡은 산출물입니다. './scripts/package-notarized.sh' 를 다시 실행하세요."
  fi

  # zip 내부 build(CFBundleVersion). 서버 릴리스 알림은 버전 문자열이 아니라 이 정수로 비교한다 — 버전 축은
  # "0.3.01"=="0.3.1" 같은 함정이 있었다. 위 버전 게이트와 같은 방식으로, 스테이플을 검증한 바로 그 zip 에서 읽는다.
  ZIP_BUILD="$(unzip -p "$ZIP" "aing-check/aing-check.app/Contents/Info.plist" 2>/dev/null \
    | plutil -extract CFBundleVersion raw - 2>/dev/null || true)"
  BUILD_RE='^[1-9][0-9]{0,6}$'
  if [[ "$ZIP_BUILD" =~ $BUILD_RE ]] && (( ZIP_BUILD <= 1000000 )); then
    BUILD="$ZIP_BUILD"
    log "zip 내부 build 확인됨 ($BUILD)"
  else
    missing "zip 내부 build(CFBundleVersion '$ZIP_BUILD')가 1..1000000 의 정수가 아닙니다 — 서버 릴리스 알림은 build 로 비교하므로 게시할 수 없습니다. './scripts/package-notarized.sh' 를 다시 실행하세요."
  fi
fi

# sha256 계산 (zip 이 없으면 dry-run 자리표시자).
if [[ -f "$ZIP" ]]; then
  SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
else
  SHA256="0000000000000000000000000000000000000000000000000000000000000000"
fi
log "sha256: $SHA256"

# 사전점검: tap 저장소. 예전엔 이 확인이 GitHub 릴리즈가 이미 공개된 뒤에 있어, tap 이 없으면 릴리즈만 나간 채 멈췄다.
CASK_TEMPLATE="$ROOT/packaging/homebrew/aing-check.rb"
[[ -f "$CASK_TEMPLATE" ]] || die "Cask 템플릿이 없습니다: $CASK_TEMPLATE"

TAP_DIR="${GH_TAP_DIR:-$ROOT/../homebrew-check}"
log "사전점검: tap 저장소 — $TAP_DIR"

if [[ ! -d "$TAP_DIR/.git" ]]; then
  warn "tap 저장소를 찾을 수 없습니다: $TAP_DIR"
  cat >&2 <<EOF
  최초 1회 tap 저장소를 준비하세요:
    gh repo create $GH_OWNER/homebrew-check --public --clone
    # 이미 있으면: git clone https://github.com/$GH_OWNER/homebrew-check ../homebrew-check
  경로가 ../homebrew-check 가 아니면 GH_TAP_DIR 환경변수로 지정한 뒤 다시 실행하세요.
EOF
  missing "tap 저장소가 준비되지 않았습니다: $TAP_DIR"
elif ! git -C "$TAP_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  missing "tap 저장소의 현재 브랜치에 upstream 이 없습니다 — 원격 게이트가 읽을 곳이 없습니다. 'git -C \"$TAP_DIR\" branch --set-upstream-to=origin/main' 으로 연결하세요."
elif [[ "$SERVER_ONLY" -eq 0 ]]; then
  # 전체 흐름은 이 로컬 브랜치 위에 새 Cask 를 커밋해 푸시한다. 로컬이 원격보다 뒤처져 있으면 그 푸시는 거절되는데,
  # 그 시점엔 이미 태그·GitHub 릴리즈가 공개된 뒤다 — 그래서 부수효과 전에 fetch 로 되읽어 막는다(읽기 전용).
  if ! git -C "$TAP_DIR" fetch origin; then
    missing "tap 원격 fetch 에 실패했습니다 — 네트워크나 GitHub 인증을 확인하세요."
  else
    TAP_BEHIND="$(git -C "$TAP_DIR" rev-list --count 'HEAD..@{u}')"
    if (( TAP_BEHIND > 0 )); then
      missing "tap 저장소가 원격보다 ${TAP_BEHIND}커밋 뒤처져 있습니다 — 이대로 커밋하면 푸시가 거절됩니다. 'git -C \"$TAP_DIR\" pull --ff-only' 로 맞춘 뒤 다시 실행하세요."
    fi
  fi
fi

# 사전점검: 서버 릴리스 알림. 서버 게시는 파이프라인 맨 끝이라, 여기서 미리 안 막으면 태그·릴리즈·tap 이 다 나간 뒤에야
# 실패한다. 서버 계약: version 은 숫자.숫자(최대 4마디, 접미사 없음), build 는 이미 게시된 build 보다 뒤로 갈 수 없다.
SERVER_VERSION_RE='^[0-9]+(\.[0-9]+){1,3}$'
if [[ ! "$VERSION" =~ $SERVER_VERSION_RE ]]; then
  missing "버전 '$VERSION' 은 서버 릴리스 알림 형식(숫자.숫자.숫자, 접미사 없음)이 아닙니다 — 서버가 app_release_invalid 로 거절하므로 게시할 수 없습니다."
fi

LATEST_SQL="select public.app_latest_release() as r"
NOTES_SQL="$(notes_sql_array "$SERVER_NOTES")"
PUBLISH_SQL="select public.app_publish_release($(sql_quote "$VERSION"), $BUILD, $NOTES_SQL) as r;"
# 운영자 강제 게시(롤백)용 — 스크립트는 절대 이 SQL 을 실행하지 않는다. 역행이 막혔을 때 안내로만 찍는다.
FORCE_SQL="select public.app_publish_release($(sql_quote "$VERSION"), $BUILD, $NOTES_SQL, true) as r;"

log "사전점검: 서버 릴리스 알림 (app_latest_release, 읽기 전용)"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  [dry-run] 서버 사전점검을 건너뜁니다 — dry-run 은 supabase 를 부르지 않습니다. 실제 실행은 아래를 읽기 전용으로 조회해 서버 build 가 $BUILD 이하인지 확인합니다:" >&2
  echo "    supabase db query --linked --agent=no -o json \"$LATEST_SQL\"" >&2
else
  command -v supabase >/dev/null 2>&1 \
    || die "supabase CLI 가 없습니다. 'brew install supabase/tap/supabase' 후 'supabase login' · 'supabase link --project-ref xfnhfjvubetkdnfkfljg' 를 실행하세요."
  if ! SERVER_LATEST_JSON="$(supabase_query "$LATEST_SQL")"; then
    server_query_help
    die "서버의 현재 릴리스를 읽지 못했습니다 — 아무것도 건드리지 않고 멈춥니다."
  fi
  if ! SERVER_BUILD="$(release_json_field build <<< "$SERVER_LATEST_JSON")" \
    || ! SERVER_VERSION="$(release_json_field version <<< "$SERVER_LATEST_JSON")"; then
    die "app_latest_release() 응답을 해석하지 못했습니다: $SERVER_LATEST_JSON"
  fi
  if [[ -z "$SERVER_BUILD" ]]; then
    log "서버에 게시된 릴리스가 아직 없습니다 — 이번이 첫 게시입니다."
  elif [[ ! "$SERVER_BUILD" =~ ^[0-9]+$ ]]; then
    die "서버 build 값이 정수가 아닙니다: '$SERVER_BUILD'"
  elif (( SERVER_BUILD > BUILD )) || { (( SERVER_BUILD == BUILD )) && [[ "$SERVER_VERSION" != "$VERSION" ]]; }; then
    cat >&2 <<EOF
  서버 릴리스 알림은 build 가 뒤로 가지 않습니다(app_release_regression). 대개 낡은 zip 이거나 버전을 잘못 고른 것입니다 —
  dist/aing-check.zip 을 이번 버전으로 다시 만들었는지, 릴리스할 버전이 맞는지 먼저 확인하세요.
  정말로 되돌리는 것(롤백)이라면 이 스크립트가 아니라 운영자가 직접 강제 게시합니다(마지막 인자 true).
  Supabase SQL Editor 에서 실행하거나, 파일로 저장해 'supabase db query --linked --agent=no -f <파일>' 로 실행하세요:
    $FORCE_SQL
  되돌리기 전후 주의사항: docs/release.md "서버 릴리스 알림" → "되돌리기".
EOF
    die "서버 릴리스 알림이 이미 build $SERVER_BUILD ($SERVER_VERSION) 입니다 — 이번 zip(build $BUILD, $VERSION)을 게시하면 역행이라 아무것도 건드리지 않고 멈춥니다."
  elif (( SERVER_BUILD == BUILD )); then
    log "서버에 이미 같은 릴리스가 게시돼 있습니다(build $BUILD) — 게시 단계는 unchanged 또는 refreshed(노트만 갱신)로 끝납니다."
  else
    log "서버 릴리스 알림: build $SERVER_BUILD ($SERVER_VERSION) → $BUILD ($VERSION) 로 올립니다."
  fi
fi

# ---------------------------------------------------------------------------
# (b) git 태그 + GitHub 릴리즈
# ---------------------------------------------------------------------------
if [[ "$SERVER_ONLY" -eq 1 ]]; then
  log "--server-only: git 태그 · GitHub 릴리즈 · Cask 커밋을 건너뜁니다."
else
  log "git 태그 $TAG 생성/푸시"
  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    warn "태그 $TAG 이(가) 이미 존재합니다. 태그 생성을 건너뜁니다 (멱등)."
  else
    run git tag -a "$TAG" -m "aing-check $VERSION"
  fi
  run git push origin "$TAG"

  log "GitHub 릴리즈 $TAG (자산: aing-check.zip)"
  REPO="$GH_OWNER/check"
  # 본문 = CHANGELOG 섹션(위 사전점검에서 확보) + 설치 안내 한 줄. 안내 줄은 "- " 로 시작하지 않으므로
  # 앱의 노트 파서가 항목으로 오해하지 않는다(배너에는 패치노트만 뜬다).
  RELEASE_NOTES="$RELEASE_NOTES

설치: brew tap $GH_OWNER/check && brew install --cask aing-check"
  if [[ "$DRY_RUN" -eq 0 ]] && gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    warn "릴리즈 $TAG 이(가) 이미 존재합니다. 자산만 덮어씁니다 (멱등)."
    run gh release upload "$TAG" "$ZIP" --repo "$REPO" --clobber
  else
    run gh release create "$TAG" "$ZIP" \
      --repo "$REPO" \
      --title "aing-check $VERSION" \
      --notes "$RELEASE_NOTES"
  fi
fi

# ---------------------------------------------------------------------------
# (c) Cask 갱신 + tap 저장소 커밋 (푸시는 (d) 가 맡는다)
# ---------------------------------------------------------------------------
# 템플릿의 자리표시자를 치환해 지정 파일로 출력한다.
generate_cask() {
  sed -e "s|__VERSION__|$VERSION|g" -e "s|__SHA256__|$SHA256|g" -e "s|__GH_OWNER__|$GH_OWNER|g" "$CASK_TEMPLATE" > "$1"
}

# dry-run 미리보기.
preview_cask() {
  local tmp; tmp="$(mktemp)"
  generate_cask "$tmp"
  echo "  [dry-run] 생성될 Cask 내용 (-> $TAP_DIR/Casks/aing-check.rb):" >&2
  sed 's/^/    | /' "$tmp" >&2
  rm -f "$tmp"
}

if [[ "$SERVER_ONLY" -eq 0 ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    preview_cask
  elif [[ -d "$TAP_DIR/.git" ]]; then
    CASK_DIR="$TAP_DIR/Casks"
    mkdir -p "$CASK_DIR"
    generate_cask "$CASK_DIR/aing-check.rb"
    (
      cd "$TAP_DIR"
      git add "Casks/aing-check.rb"
      if git diff --cached --quiet; then
        warn "Cask 에 변경 사항이 없습니다. 커밋을 건너뜁니다 (멱등)."
      else
        git commit -m "aing-check $VERSION"
      fi
    )
    log "tap 저장소에 Cask 커밋 반영 완료"
  fi
fi

# ---------------------------------------------------------------------------
# (d) tap 푸시 + 원격 게이트 — 서버 게시보다 반드시 앞선다
# ---------------------------------------------------------------------------
# 앱은 서버 알림을 받는 즉시 "업데이트" 를 띄우고 [지금 업데이트] 가 brew upgrade 를 부른다. tap 원격이 아직 옛 cask 면
# 그 업그레이드는 아무것도 못 받는다 — 그래서 로컬 커밋이 아니라 원격을 fetch 로 되읽어 version/sha256 을 확인한다.
#
# 푸시를 커밋 블록에서 떼어 여기서 "앞서 있으면 푸시" 로 하는 이유: 예전엔 커밋과 푸시가 한 묶음이라, 커밋은 됐는데
# 푸시가 실패한 뒤 다시 실행하면 스테이징할 변경이 없어 커밋·푸시를 둘 다 건너뛰고도 성공 로그를 찍었다(푸시 영영 누락).
#
# 통과면 0(TAP_GATE_SOURCE 에 판정 기준), 실패면 TAP_GATE_ERROR 에 이유를 담고 1. elif 조건 안에서 불리므로
# set -e 가 꺼져 있다 — 실패할 수 있는 명령은 전부 직접 검사한다.
TAP_GATE_ERROR=""
TAP_GATE_SOURCE=""
check_tap_remote() {
  local upstream ahead behind cask got_version got_sha
  if ! upstream="$(git -C "$TAP_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
    TAP_GATE_ERROR="tap 저장소의 현재 브랜치에 upstream 이 없습니다. 'git -C \"$TAP_DIR\" branch --set-upstream-to=origin/main' 으로 연결하세요"
    return 1
  fi
  if ! ahead="$(git -C "$TAP_DIR" rev-list --count '@{u}..HEAD')"; then
    TAP_GATE_ERROR="tap 저장소의 앞섬 여부를 읽지 못했습니다"
    return 1
  fi

  if (( ahead > 0 )); then
    # 공개 tap 에 엉뚱한 커밋을 올리지 않도록, 푸시할 HEAD 의 Cask 가 이번 릴리스인지 먼저 본다
    # (--server-only 에서 지난 실행과 무관한 커밋이 남아 있을 수 있다).
    cask="$(git -C "$TAP_DIR" show 'HEAD:Casks/aing-check.rb' 2>/dev/null || true)"
    got_version="$(cask_value version "$cask")"; got_sha="$(cask_value sha256 "$cask")"
    if [[ "$got_version" != "$VERSION" || "$got_sha" != "$SHA256" ]]; then
      TAP_GATE_ERROR="tap 로컬이 $upstream 보다 ${ahead}커밋 앞서 있는데 HEAD 의 Cask 가 이번 릴리스가 아닙니다(version '${got_version:-없음}', sha256 '${got_sha:-없음}') — 푸시하지 않습니다. 'git -C \"$TAP_DIR\" log --oneline @{u}..HEAD' 로 확인하세요"
      return 1
    fi
    log "tap 로컬이 $upstream 보다 ${ahead}커밋 앞서 있습니다 — 푸시합니다"
    if ! run git -C "$TAP_DIR" push; then
      TAP_GATE_ERROR="tap 푸시에 실패했습니다 — 원격과 갈라졌을 수 있습니다. 'git -C \"$TAP_DIR\" status' 로 확인하세요"
      return 1
    fi
  fi

  log "tap 원격 되읽기: git -C $TAP_DIR fetch origin (읽기 전용)"
  if ! git -C "$TAP_DIR" fetch origin; then
    TAP_GATE_ERROR="tap 원격 fetch 에 실패했습니다 — 네트워크나 GitHub 인증을 확인하세요"
    return 1
  fi

  if (( ahead > 0 )) && [[ "$DRY_RUN" -eq 1 ]]; then
    # dry-run 은 푸시를 안 했으니 원격은 아직 옛것이다. 푸시가 성공하면 원격이 가질 로컬 HEAD 로 판정하되,
    # 원격이 갈라져 있으면 그 푸시는 거절되므로 그것만은 원격 기준으로 가려낸다.
    if ! behind="$(git -C "$TAP_DIR" rev-list --count 'HEAD..@{u}')" || (( behind > 0 )); then
      TAP_GATE_ERROR="tap 로컬과 원격이 갈라져 있습니다(원격에만 ${behind:-?}커밋) — 푸시가 거절됩니다. 'git -C \"$TAP_DIR\" pull --rebase' 로 정리하세요"
      return 1
    fi
    TAP_GATE_SOURCE="로컬 HEAD (dry-run: 푸시하면 원격이 가질 커밋)"
    cask="$(git -C "$TAP_DIR" show 'HEAD:Casks/aing-check.rb' 2>/dev/null || true)"
  else
    TAP_GATE_SOURCE="$upstream"
    cask="$(git -C "$TAP_DIR" show '@{u}:Casks/aing-check.rb' 2>/dev/null || true)"
  fi
  got_version="$(cask_value version "$cask")"; got_sha="$(cask_value sha256 "$cask")"
  if [[ "$got_version" != "$VERSION" || "$got_sha" != "$SHA256" ]]; then
    TAP_GATE_ERROR="tap 원격($TAP_GATE_SOURCE)의 Casks/aing-check.rb 가 이번 릴리스가 아닙니다 — version '${got_version:-없음}' (기대 $VERSION), sha256 '${got_sha:-없음}' (기대 $SHA256)"
    return 1
  fi
  return 0
}

log "tap 원격 게이트: Casks/aing-check.rb 가 version $VERSION · sha256 $SHA256 인지"
if [[ ! -d "$TAP_DIR/.git" ]]; then
  # 실제 실행이면 사전점검에서 이미 멈췄다 — 여기 오는 건 dry-run 뿐이다.
  warn "tap 저장소가 없어 원격 게이트를 건너뜁니다 (dry-run — 실제 실행이면 여기서 멈춥니다)."
elif check_tap_remote; then
  log "원격 게이트 통과 — 기준: $TAP_GATE_SOURCE"
elif [[ "$DRY_RUN" -eq 1 && "$SERVER_ONLY" -eq 0 ]]; then
  # 전체 흐름의 dry-run 은 Cask 커밋을 미리보기만 했으니 원격이 옛 버전인 게 정상이다.
  warn "$TAP_GATE_ERROR (dry-run 은 Cask 를 커밋·푸시하지 않아 여기서 어긋나는 게 정상일 수 있습니다 — 실제 실행에서는 여기서 멈춥니다)"
else
  die "$TAP_GATE_ERROR. brew 가 아직 이번 버전을 주지 않으므로 서버 릴리스 알림을 게시하지 않습니다."
fi

# ---------------------------------------------------------------------------
# (e) 서버 릴리스 알림 게시 — 실행 중인 앱이 몇 분 안에 새 버전을 안다
# ---------------------------------------------------------------------------
log "서버 릴리스 알림 게시: $VERSION (build $BUILD, 노트 ${NOTES_COUNT}줄)"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  [dry-run] 임시 파일에 아래 SQL 을 써서 'supabase db query --linked --agent=no -o json -f <파일>' 로 실행하고, app_latest_release() 를 되읽어 build 가 $BUILD 인지 확인합니다:" >&2
  printf '%s\n' "$PUBLISH_SQL" | sed 's/^/    | /' >&2
else
  # 저장소 밖 임시 파일로 보낸다 — 노트가 명령행 인자(프로세스 목록)에 실리지 않고, 셸 인용과도 엮이지 않는다.
  PUBLISH_SQL_FILE="$(mktemp "${TMPDIR:-/tmp}/aing-check-release.XXXXXX")"
  printf '%s\n' "$PUBLISH_SQL" > "$PUBLISH_SQL_FILE"
  if ! PUBLISH_JSON="$(supabase_query -f "$PUBLISH_SQL_FILE")"; then
    rm -f "$PUBLISH_SQL_FILE"
    server_query_help
    die "서버 게시(app_publish_release)가 실패했습니다. brew 쪽(태그·릴리즈·tap)은 이미 끝났으니, 원인을 고친 뒤 게시만 다시 하세요: ./scripts/release-brew.sh $VERSION --server-only"
  fi
  rm -f "$PUBLISH_SQL_FILE"
  PUBLISH_STATUS="$(release_json_field status <<< "$PUBLISH_JSON" || true)"
  case "$PUBLISH_STATUS" in
    published|unchanged|refreshed) ;;
    *) warn "게시 응답의 status 를 해석하지 못했습니다('$PUBLISH_STATUS') — 되읽기로 판정합니다: $PUBLISH_JSON" ;;
  esac

  # 되읽기 — 게시 응답이 아니라 앱이 실제로 읽는 app_latest_release() 로 확인한다.
  if ! LATEST_JSON="$(supabase_query "$LATEST_SQL")"; then
    server_query_help
    die "게시 뒤 되읽기에 실패했습니다 — 게시가 반영됐는지 모릅니다. 확인 후 필요하면: ./scripts/release-brew.sh $VERSION --server-only"
  fi
  LATEST_BUILD="$(release_json_field build <<< "$LATEST_JSON" || true)"
  LATEST_VERSION="$(release_json_field version <<< "$LATEST_JSON" || true)"
  if [[ "$LATEST_BUILD" != "$BUILD" || "$LATEST_VERSION" != "$VERSION" ]]; then
    die "되읽은 서버 릴리스가 build '$LATEST_BUILD' ($LATEST_VERSION) 입니다 — 기대 build $BUILD ($VERSION). 누가 동시에 게시했는지 확인하세요: $LATEST_JSON"
  fi
  log "서버 게시 완료: status=$PUBLISH_STATUS — app_latest_release() = $LATEST_VERSION (build $LATEST_BUILD)"
fi

# ---------------------------------------------------------------------------
# (f) 팀원 안내 출력
# ---------------------------------------------------------------------------
if [[ "$SERVER_ONLY" -eq 1 ]]; then
  log "완료: aing-check $VERSION (build $BUILD) 서버 릴리스 알림 (--server-only)"
else
  log "완료: aing-check $VERSION (build $BUILD)"
fi
{
  echo ""
  echo "실행 중인 앱(build 72 이상)은 5분 안에 서버 알림으로 새 버전을 압니다. build 71 이하는 하루 1회 GitHub 확인에 기댑니다."
  if [[ "$SERVER_ONLY" -eq 0 ]]; then
    echo ""
    echo "팀원 최초 설치:"
    echo "  brew tap $GH_OWNER/check && brew install --cask aing-check"
    echo ""
    echo "이미 설치한 팀원 업그레이드:"
    echo "  brew update && brew upgrade --cask aing-check"
  fi
  echo ""
} >&2
