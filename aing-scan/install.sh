#!/bin/sh
# 아잉체크 스캐너 설치 — 맥 아잉체크 → 설정 → [원격 기계 연결]에서 복사한 명령이 이 파일을 받아 돌린다:
#   curl -fsSL '<이 파일 주소>' | sh -s -- <연결코드>
#
# 하는 일: 이 기계에 맞는 스캐너를 받아(검사값 확인) ~/.aing-scan/bin/aing-scan 에 두고, 연결 코드로 계정에 연결한다.
# 연결이 끝나면 스캐너가 10분 예약(맥 LaunchAgent · 리눅스 crontab)을 스스로 건다. 관리자 권한은 쓰지 않는다.
# 끊기: ~/.aing-scan/bin/aing-scan unlink
set -eu

CODE="${1:-${AING_SCAN_CODE:-}}"
BASE="${AING_SCAN_BASE:-https://github.com/yehsung/check/releases/download/aing-scan}"
DIR="$HOME/.aing-scan"
BIN="$DIR/bin/aing-scan"

say() { printf '%s\n' "$*"; }
fail() { say "아잉체크 스캐너: $*" >&2; exit 1; }

[ -n "$CODE" ] || fail "연결 코드가 없습니다. 맥 아잉체크 → 설정 → [원격 기계 연결]에서 명령을 다시 복사해 주세요."

case "$(uname -s)" in
  Darwin) os=macos ;;
  Linux) os=linux ;;
  *) fail "맥과 리눅스만 됩니다(윈도우용은 다음 판에 나와요)." ;;
esac
case "$(uname -m)" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64) arch=x86_64 ;;
  *) fail "지원하지 않는 CPU입니다: $(uname -m)" ;;
esac
# 맥 판은 한 파일(유니버설)이다.
[ "$os" = macos ] && arch=universal
asset="aing-scan-$os-$arch.tar.gz"

command -v curl >/dev/null 2>&1 || fail "curl 이 필요합니다."
command -v tar >/dev/null 2>&1 || fail "tar 가 필요합니다."

tmp="$(mktemp -d "${TMPDIR:-/tmp}/aing-scan.XXXXXX")"
curl -fsSL "$BASE/$asset" -o "$tmp/$asset" || fail "내려받기에 실패했습니다. 인터넷 연결을 확인해 주세요."
curl -fsSL "$BASE/$asset.sha256" -o "$tmp/$asset.sha256" || fail "검사값을 받지 못했습니다."
expected="$(cut -d' ' -f1 < "$tmp/$asset.sha256")"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp/$asset" | cut -d' ' -f1)"
else
  actual="$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)"
fi
[ -n "$expected" ] && [ "$expected" = "$actual" ] || fail "내려받은 파일의 검사값이 맞지 않습니다. 잠시 뒤 다시 해 주세요."

mkdir -p "$DIR/bin"
chmod 700 "$DIR"
tar -xzf "$tmp/$asset" -C "$tmp"
[ -f "$tmp/aing-scan" ] || fail "받은 묶음에 스캐너가 없습니다."
chmod 755 "$tmp/aing-scan"
mv -f "$tmp/aing-scan" "$BIN"
say "스캐너를 설치했습니다: $BIN"

exec "$BIN" link "$CODE"
