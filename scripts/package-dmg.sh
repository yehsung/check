#!/usr/bin/env bash
# 공증·스테이플된 .app → 서명·공증·스테이플된 배포 DMG.
# 열면 짙은 남색 창에 앱과 Applications 바로가기가 나란히 있고, 앱을 끌어다 놓으면 설치가 끝난다.
#
# 사용법: ./scripts/package-dmg.sh <스테이플된 .app> [출력 .dmg]
#   기본 출력 dist/aing-check.dmg, 볼륨 이름 aing-check. package-notarized.sh 가 zip 을 만든 뒤 부른다.
#   stdout 마지막 줄 = dmg 경로. 로그는 전부 stderr.
#
# 순서: 입력 앱 검사(서명·스테이플·버전) → dmgbuild(배경·아이콘 배치·볼륨 아이콘) → codesign → notarytool --wait
#       → stapler staple → 검증 → 출력 경로로 옮김.
# 검증은 하나라도 어긋나면 멈추고 DMG 를 남기지 않는다. `|| true` 로 삼키지 않는다 — 이 저장소엔 공증 실패를 삼켜
# 낡은 산출물이 나갈 뻔한 사고가 있었다(v0.2.39). 같은 이유로 시작할 때 옛 출력 DMG 를 먼저 지운다.
#   - DMG: stapler validate · spctl -t open(Notarized Developer ID) · hdiutil verify
#   - 읽기 전용 마운트: 안의 앱 codesign --deep --strict · stapler validate · spctl -t execute ·
#     버전/build/CDHash 가 입력 앱과 같은지 · Applications 링크 · 배경/창 설정/볼륨 아이콘 파일
#
# 필요: Developer ID Application 인증서(CODESIGN_IDENTITY 로 지정 가능), 공증 프로파일 check-notary
#       (package-notarized.sh 주석 참고 — 키체인을 명시해야 보인다), /usr/bin/python3.
#       dmgbuild 는 .build/dmgbuild-venv 에 처음 한 번 설치한다(PyPI 접속 필요).
# 창 배치·배경: packaging/dmg/settings.py · background.html(바꾸면 node packaging/dmg/render-background.mjs).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo "==> $*" >&2; }
die() { echo "오류: $*" >&2; exit 1; }

USAGE="사용법: ./scripts/package-dmg.sh <스테이플된 .app> [출력 .dmg]"
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "$USAGE"
  exit 0
fi
[[ $# -ge 1 && $# -le 2 ]] || die "$USAGE"

[[ -d "$1" ]] || die "앱이 없습니다: $1"
APP="$(cd "$1" && pwd)"
APP_NAME="$(basename "$APP")"
[[ "$APP_NAME" == *.app ]] || die "앱 번들(.app)을 넘기세요: $APP"

OUT="${2:-$ROOT/dist/aing-check.dmg}"
[[ "$OUT" == *.dmg ]] || die "출력 파일은 .dmg 로 끝나야 합니다: $OUT"
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

VOLNAME="aing-check"
DMG_DIR="$ROOT/packaging/dmg"
SETTINGS="$DMG_DIR/settings.py"
VOLUME_ICON="$ROOT/packaging/appicon/AppIcon.icns"
VENV="$ROOT/.build/dmgbuild-venv"
DMGBUILD_VERSION="1.6.5"
NOTARY_PROFILE="${NOTARY_PROFILE:-check-notary}"
NOTARY_KEYCHAIN="${NOTARY_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

# 작업 중인 DMG 는 임시 폴더에 출력과 같은 이름으로 만든다(공증 기록에도 이 이름이 남는다).
# 검증을 전부 통과해야 출력 경로로 옮긴다.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/aing-check-dmg.XXXXXX")"
TMP_DMG="$WORK/$(basename "$OUT")"
MNT=""  # 마운트돼 있을 때만 값이 있다

cleanup() {
  if [[ -n "$MNT" ]]; then
    hdiutil detach "$MNT" -force >/dev/null 2>&1 || echo "경고: 마운트 해제 실패 — 'hdiutil detach \"$MNT\" -force' 로 직접 푸세요." >&2
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# 옛 출력부터 지운다 — 어느 단계에서 멈추든 낡은 DMG 가 그 자리에 남아 릴리스에 붙지 않게.
rm -f "$OUT"

# Info.plist 값 하나. 없으면 빈 줄.
plist_value() {
  plutil -extract "$2" raw "$1/Contents/Info.plist" 2>/dev/null || true
}

cdhash() {
  codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p' | head -n 1
}

png_size() {
  sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null | awk '/pixelWidth/ {w = $2} /pixelHeight/ {h = $2} END {print w "x" h}'
}

# notarytool --output-format json 출력에서 필드 하나. 여러 객체가 섞여 있으면 마지막 객체를 본다.
notary_field() {
  /usr/bin/python3 -c '
import json, sys
raw = open(sys.argv[1], encoding="utf-8", errors="replace").read()
dec, i, last = json.JSONDecoder(), 0, {}
while True:
    i = raw.find("{", i)
    if i < 0:
        break
    try:
        obj, end = dec.raw_decode(raw, i)
    except ValueError:
        i += 1
        continue
    if isinstance(obj, dict):
        last = obj
    i = end
print(last.get(sys.argv[2]) or "")
' "$1" "$2"
}

# ---------------------------------------------------------------------------
# 1) 입력 앱 — 스테이플까지 끝난 앱만 받는다
# ---------------------------------------------------------------------------
log "입력 앱: $APP"
[[ -f "$APP/Contents/Info.plist" ]] || die "Info.plist 가 없습니다: $APP/Contents/Info.plist"
APP_VERSION="$(plist_value "$APP" CFBundleShortVersionString)"
APP_BUILD="$(plist_value "$APP" CFBundleVersion)"
[[ -n "$APP_VERSION" && -n "$APP_BUILD" ]] || die "입력 앱의 버전/build 를 읽지 못했습니다(CFBundleShortVersionString '$APP_VERSION', CFBundleVersion '$APP_BUILD')."
codesign --verify --deep --strict "$APP" >&2 || die "입력 앱의 서명 검증에 실패했습니다: $APP"
xcrun stapler validate "$APP" >&2 \
  || die "입력 앱에 공증 스테이플이 없습니다 — ./scripts/package-notarized.sh 가 만든(스테이플된) 앱을 넘기세요: $APP"
APP_CDHASH="$(cdhash "$APP")"
[[ -n "$APP_CDHASH" ]] || die "입력 앱의 CDHash 를 읽지 못했습니다: $APP"
log "aing-check $APP_VERSION (build $APP_BUILD), CDHash $APP_CDHASH"

# ---------------------------------------------------------------------------
# 2) 재료 — 설정·배경(1x 는 settings.py 의 배경 크기, 2x 는 정확히 두 배)·볼륨 아이콘
# ---------------------------------------------------------------------------
for f in "$SETTINGS" "$DMG_DIR/background.png" "$DMG_DIR/background@2x.png" "$VOLUME_ICON"; do
  [[ -f "$f" ]] || die "DMG 재료가 없습니다: $f"
done
BG_SIZE="$(sed -n 's/^BACKGROUND_W, BACKGROUND_H = \([0-9][0-9]*\), \([0-9][0-9]*\).*/\1x\2/p' "$SETTINGS")"
[[ -n "$BG_SIZE" ]] || die "settings.py 에서 'BACKGROUND_W, BACKGROUND_H = <가로>, <세로>' 줄을 찾지 못했습니다."
BG1="$(png_size "$DMG_DIR/background.png")"
BG2="$(png_size "$DMG_DIR/background@2x.png")"
[[ "$BG1" == "$BG_SIZE" ]] || die "background.png 가 $BG1 입니다 — settings.py 의 배경 크기 $BG_SIZE 와 같아야 합니다(node packaging/dmg/render-background.mjs)."
[[ "$BG2" == "$(( ${BG_SIZE%x*} * 2 ))x$(( ${BG_SIZE#*x} * 2 ))" ]] \
  || die "background@2x.png 가 $BG2 입니다 — 정확히 두 배여야 합니다(node packaging/dmg/render-background.mjs)."

IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' | head -n 1)"
fi
[[ -n "$IDENTITY" ]] || die "Developer ID Application 인증서가 없습니다. Xcode > Settings > Accounts > Manage Certificates 에서 발급하세요."
log "서명 인증서: $IDENTITY"

# ---------------------------------------------------------------------------
# 3) dmgbuild — .build/dmgbuild-venv 에 고정 버전으로
# ---------------------------------------------------------------------------
DMGBUILD_HAVE=""
if [[ -x "$VENV/bin/python" ]]; then
  DMGBUILD_HAVE="$("$VENV/bin/python" -c 'import importlib.metadata as m; print(m.version("dmgbuild"))' 2>/dev/null || true)"
fi
if [[ "$DMGBUILD_HAVE" != "$DMGBUILD_VERSION" || ! -x "$VENV/bin/dmgbuild" ]]; then
  log "dmgbuild $DMGBUILD_VERSION 설치 → $VENV (처음 한 번, PyPI 접속 필요)"
  [[ -x /usr/bin/python3 ]] || die "/usr/bin/python3 이 없습니다 — 'xcode-select --install' 로 명령행 도구를 설치하세요."
  rm -rf "$VENV"
  /usr/bin/python3 -m venv "$VENV" >&2 || die "venv 를 만들지 못했습니다: $VENV"
  if ! "$VENV/bin/pip" install --disable-pip-version-check --quiet "dmgbuild==$DMGBUILD_VERSION" >&2; then
    rm -rf "$VENV"
    die "dmgbuild 설치에 실패했습니다. 네트워크(https://pypi.org)에 연결돼 있는지 확인하고 다시 실행하세요. 당장 DMG 없이 릴리스해야 하면: SKIP_DMG=1 ./scripts/release-brew.sh <버전>"
  fi
fi

log "DMG 만들기 (dmgbuild $DMGBUILD_VERSION, 볼륨 '$VOLNAME')"
"$VENV/bin/dmgbuild" -s "$SETTINGS" \
  -D app="$APP" -D dmg_dir="$DMG_DIR" -D volume_icon="$VOLUME_ICON" \
  "$VOLNAME" "$TMP_DMG" >&2
[[ -f "$TMP_DMG" ]] || die "dmgbuild 가 DMG 를 만들지 않았습니다: $TMP_DMG"

# ---------------------------------------------------------------------------
# 4) 서명 → 공증 → 스테이플
# ---------------------------------------------------------------------------
codesign --force --timestamp --sign "$IDENTITY" "$TMP_DMG" >&2
codesign --verify --strict --verbose=2 "$TMP_DMG" >&2

log "DMG 공증 제출 중 (보통 2~10분)..."
NOTARY_OUT="$WORK/notary.json"
NOTARY_RC=0
xcrun notarytool submit "$TMP_DMG" --keychain-profile "$NOTARY_PROFILE" --keychain "$NOTARY_KEYCHAIN" \
  --wait --output-format json > "$NOTARY_OUT" || NOTARY_RC=$?
cat "$NOTARY_OUT" >&2
echo >&2
SUBMISSION_ID="$(notary_field "$NOTARY_OUT" id)"
NOTARY_STATUS="$(notary_field "$NOTARY_OUT" status)"
# 종료코드와 상태를 **둘 다** 본다 — 종료코드만 믿다가 실패를 놓친 적이 있다.
if [[ "$NOTARY_RC" -ne 0 || "$NOTARY_STATUS" != "Accepted" ]]; then
  if [[ -n "$SUBMISSION_ID" ]]; then
    log "공증 로그 ($SUBMISSION_ID):"
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" --keychain "$NOTARY_KEYCHAIN" >&2 \
      || echo "경고: 공증 로그를 받지 못했습니다." >&2
  fi
  die "DMG 공증 실패 — 종료코드 $NOTARY_RC, 상태 '${NOTARY_STATUS:-없음}', submission '${SUBMISSION_ID:-없음}'. 'No Keychain password item found' 가 보이면 화면 잠금/프로파일 문제다(package-notarized.sh 주석의 복구 명령)."
fi
log "공증 통과: submission $SUBMISSION_ID ($NOTARY_STATUS)"

xcrun stapler staple "$TMP_DMG" >&2

# ---------------------------------------------------------------------------
# 5) 검증 — 전부 실패 시 종료
# ---------------------------------------------------------------------------
log "검증: DMG 스테이플"
xcrun stapler validate "$TMP_DMG" >&2

log "검증: Gatekeeper (DMG 열기)"
SPCTL_DMG="$(spctl -a -t open --context context:primary-signature -v "$TMP_DMG" 2>&1)" \
  || { echo "$SPCTL_DMG" >&2; die "spctl 이 DMG 를 거절했습니다."; }
echo "$SPCTL_DMG" >&2
grep -q "source=Notarized Developer ID" <<< "$SPCTL_DMG" || die "DMG 의 spctl 출처가 'Notarized Developer ID' 가 아닙니다."

log "검증: hdiutil verify"
hdiutil verify "$TMP_DMG" >&2

log "검증: 읽기 전용으로 마운트해 안을 본다"
MNT_DIR="$WORK/mnt"
mkdir -p "$MNT_DIR"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$MNT_DIR" "$TMP_DMG" >&2
MNT="$MNT_DIR"
INNER="$MNT/$APP_NAME"
[[ -d "$INNER" ]] || die "DMG 안에 $APP_NAME 이 없습니다."
codesign --verify --deep --strict --verbose=2 "$INNER" >&2
xcrun stapler validate "$INNER" >&2
SPCTL_APP="$(spctl --assess --type execute -v "$INNER" 2>&1)" \
  || { echo "$SPCTL_APP" >&2; die "spctl 이 DMG 안의 앱을 거절했습니다."; }
echo "$SPCTL_APP" >&2
grep -q "source=Notarized Developer ID" <<< "$SPCTL_APP" || die "DMG 안 앱의 spctl 출처가 'Notarized Developer ID' 가 아닙니다."

INNER_VERSION="$(plist_value "$INNER" CFBundleShortVersionString)"
INNER_BUILD="$(plist_value "$INNER" CFBundleVersion)"
[[ "$INNER_VERSION" == "$APP_VERSION" && "$INNER_BUILD" == "$APP_BUILD" ]] \
  || die "DMG 안 앱이 $INNER_VERSION (build $INNER_BUILD) 입니다 — 입력 앱 $APP_VERSION (build $APP_BUILD) 과 다릅니다."
INNER_CDHASH="$(cdhash "$INNER")"
[[ "$INNER_CDHASH" == "$APP_CDHASH" ]] || die "DMG 안 앱의 CDHash($INNER_CDHASH)가 입력 앱($APP_CDHASH)과 다릅니다."
log "DMG 안 앱: $INNER_VERSION (build $INNER_BUILD), CDHash 일치"

[[ -L "$MNT/Applications" && "$(readlink "$MNT/Applications")" == "/Applications" ]] \
  || die "DMG 안에 /Applications 를 가리키는 'Applications' 링크가 없습니다."
for f in .background.tiff .DS_Store .VolumeIcon.icns; do
  [[ -f "$MNT/$f" ]] || die "DMG 안에 $f 가 없습니다 — 창 배경/배치/볼륨 아이콘이 빠졌습니다."
done
log "Applications 링크 · 배경 · 창 설정 · 볼륨 아이콘 확인됨"

hdiutil detach "$MNT" >&2 || hdiutil detach "$MNT" -force >&2 || die "마운트 해제 실패: $MNT"
MNT=""

# ---------------------------------------------------------------------------
# 6) 출력
# ---------------------------------------------------------------------------
mv -f "$TMP_DMG" "$OUT"
log "완료: $OUT — $(stat -f %z "$OUT") bytes, sha256 $(shasum -a 256 "$OUT" | awk '{print $1}') (aing-check $APP_VERSION, build $APP_BUILD)"
echo "$OUT"
