#!/usr/bin/env bash
# aing-check brew 릴리즈 자동화.
#
# 사용법: ./scripts/release-brew.sh <버전> [--dry-run]
#   예:   ./scripts/release-brew.sh 0.2.0
#         ./scripts/release-brew.sh 0.2.0 --dry-run   # 실제 실행 없이 각 단계만 출력
#
# 하는 일:
#   1) 사전점검 — gh 로그인, GH_OWNER, 공증된 dist/aing-check.zip(스테이플 검증)
#   2) git 태그 v<버전> 생성/푸시, GitHub 릴리즈 생성 + zip 자산 업로드
#   3) sha256 계산 → packaging/homebrew/aing-check.rb 치환본을 tap 저장소에 커밋/푸시
#   4) 팀원 설치/업그레이드 명령 출력
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

# ---------------------------------------------------------------------------
# 인자 파싱
# ---------------------------------------------------------------------------
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      echo "사용법: ./scripts/release-brew.sh <버전> [--dry-run]"
      echo "  예:   ./scripts/release-brew.sh 0.2.0"
      exit 0
      ;;
    -*)
      die "알 수 없는 옵션 '$arg' (사용법: ./scripts/release-brew.sh <버전> [--dry-run])"
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
  log "DRY-RUN 모드: 실제 태그/릴리즈/푸시 없이 각 단계만 출력합니다."
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

ZIP="$ROOT/dist/aing-check.zip"
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
fi

# sha256 계산 (zip 이 없으면 dry-run 자리표시자).
if [[ -f "$ZIP" ]]; then
  SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
else
  SHA256="0000000000000000000000000000000000000000000000000000000000000000"
fi
log "sha256: $SHA256"

# ---------------------------------------------------------------------------
# (b) git 태그 + GitHub 릴리즈
# ---------------------------------------------------------------------------
log "git 태그 $TAG 생성/푸시"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  warn "태그 $TAG 이(가) 이미 존재합니다. 태그 생성을 건너뜁니다 (멱등)."
else
  run git tag -a "$TAG" -m "aing-check $VERSION"
fi
run git push origin "$TAG"

log "GitHub 릴리즈 $TAG (자산: aing-check.zip)"
REPO="$GH_OWNER/check"
RELEASE_NOTES="aing-check $VERSION 배포. 설치: brew tap $GH_OWNER/check && brew install --cask aing-check"
if [[ "$DRY_RUN" -eq 0 ]] && gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  warn "릴리즈 $TAG 이(가) 이미 존재합니다. 자산만 덮어씁니다 (멱등)."
  run gh release upload "$TAG" "$ZIP" --repo "$REPO" --clobber
else
  run gh release create "$TAG" "$ZIP" \
    --repo "$REPO" \
    --title "aing-check $VERSION" \
    --notes "$RELEASE_NOTES"
fi

# ---------------------------------------------------------------------------
# (c) Cask 갱신 + tap 저장소 커밋/푸시
# ---------------------------------------------------------------------------
CASK_TEMPLATE="$ROOT/packaging/homebrew/aing-check.rb"
[[ -f "$CASK_TEMPLATE" ]] || die "Cask 템플릿이 없습니다: $CASK_TEMPLATE"

TAP_DIR="${GH_TAP_DIR:-$ROOT/../homebrew-check}"
log "tap 저장소: $TAP_DIR"

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

if [[ ! -d "$TAP_DIR/.git" ]]; then
  warn "tap 저장소를 찾을 수 없습니다: $TAP_DIR"
  cat >&2 <<EOF
  최초 1회 tap 저장소를 준비하세요:
    gh repo create $GH_OWNER/homebrew-check --public --clone
    # 이미 있으면: git clone https://github.com/$GH_OWNER/homebrew-check ../homebrew-check
  경로가 ../homebrew-check 가 아니면 GH_TAP_DIR 환경변수로 지정한 뒤 다시 실행하세요.
EOF
  missing "tap 저장소가 준비되지 않았습니다: $TAP_DIR"
fi

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
      git push
    fi
  )
  log "tap 저장소에 Cask 반영 완료"
fi

# ---------------------------------------------------------------------------
# (d) 팀원 안내 출력
# ---------------------------------------------------------------------------
log "완료: aing-check $VERSION"
{
  echo ""
  echo "팀원 최초 설치:"
  echo "  brew tap $GH_OWNER/check && brew install --cask aing-check"
  echo ""
  echo "이미 설치한 팀원 업그레이드:"
  echo "  brew update && brew upgrade --cask aing-check"
  echo ""
} >&2
