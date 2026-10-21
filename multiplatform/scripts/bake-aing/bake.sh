#!/usr/bin/env bash
# 3D 아잉이 굽기 진입점(설계 F §3 · 마스터 계획 W0-d).
#
#   bake.sh                구워서 multiplatform/assets/aing-bake/ 를 다시 쓴다(+ lock.json)
#   bake.sh --check        임시 폴더에 구워 커밋된 lock.json 의 raw · outputs 와 대조한다(저장소는 안 건드린다)
#   bake.sh --out DIR      자산을 DIR 에 쓴다(두 번 굽기 대조용)
#   bake.sh --skip-build   swift build --build-tests 를 건너뛴다
#   bake.sh --keep         작업 폴더(raw · plan · 로그)를 지우지 않는다
#   bake.sh --report FILE  실험 보고(F-3 · 4 · 6 · 9 · 11 · 13 · 알파 손실 · 렌더 굳기)를 FILE 로 복사한다(저장소 밖에 둘 것)
#
# 규칙: 렌더는 sandbox-exec 로 바깥 네트워크를 막고 돈다(기억 render-tests-hit-production). 창을 띄우지 않는다(SCNRenderer 만).
# 끝나면 git status 로 소유 경로(multiplatform/assets/aing-bake/) 밖이 바뀌지 않았는지 잰다(기억 agents-leak-files-into-repo).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
ASSETS_REL="multiplatform/assets/aing-bake"
SEAL='(version 1)(allow default)(deny network-outbound (remote ip "*:*"))'

CHECK=0; OUT=""; SKIP_BUILD=0; KEEP=0; REPORT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --out) OUT="$2"; shift ;;
    --skip-build) SKIP_BUILD=1 ;;
    --keep) KEEP=1 ;;
    --report) REPORT="$2"; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "모르는 인자: $1" >&2; exit 2 ;;
  esac
  shift
done

want="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["cwebp"])' "$HERE/config.json")"
have="$(cwebp -version 2>/dev/null | head -1 || true)"
if [ "$want" != "$have" ]; then
  echo "[bake] cwebp 판이 다르다: 설치 '$have' · config '$want'" >&2
  exit 2
fi
command -v dwebp >/dev/null || { echo "[bake] dwebp 가 없다(무손실 왕복 검사에 쓴다)" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aing-bake.XXXXXX")"
cleanup() { if [ "$KEEP" = 0 ]; then rm -rf "$WORK"; else echo "[bake] 작업 폴더: $WORK"; fi; }
trap cleanup EXIT

status_outside() {
  git -C "$ROOT" status --porcelain=v1 --untracked-files=all | grep -v " $ASSETS_REL/" || true
}
BEFORE="$(status_outside)"

cd "$ROOT"
if [ "$SKIP_BUILD" = 0 ]; then
  sandbox-exec -p "$SEAL" swift build --build-tests >"$WORK/build.log" 2>&1 || { tail -40 "$WORK/build.log"; exit 1; }
fi

started=$(date +%s)
if ! sandbox-exec -p "$SEAL" env CHECK_AING_BAKE_OUT="$WORK/raw" \
     swift test --disable-sandbox --skip-build --no-parallel --filter 'AingBakeSuite/bake' >"$WORK/swift-test.log" 2>&1; then
  tail -40 "$WORK/swift-test.log"
  echo "[bake] 굽기 스위트 실패" >&2
  exit 1
fi
echo "[bake] 렌더 $(( $(date +%s) - started ))초"

if [ "$CHECK" = 1 ]; then
  DEST="$WORK/assets"
elif [ -n "$OUT" ]; then
  DEST="$OUT"
else
  DEST="$ROOT/$ASSETS_REL"
fi
python3 "$HERE/bake.py" finalize --plan "$WORK/raw" --assets "$DEST" --repo "$ROOT"
if [ -n "$REPORT" ]; then cp "$WORK/raw/reports.json" "$REPORT"; echo "[bake] 실험 보고: $REPORT"; fi

set +e
python3 "$HERE/bake.py" sizes --assets "$DEST" --repo "$ROOT"
size_status=$?
set -e

if [ "$CHECK" = 1 ]; then
  python3 "$HERE/bake.py" compare "$DEST/lock.json" "$ROOT/$ASSETS_REL/lock.json" || { echo "[bake] --check: 커밋된 굽기와 다르다" >&2; exit 1; }
fi

AFTER="$(status_outside)"
if [ "$BEFORE" != "$AFTER" ]; then
  echo "[bake] 소유 경로 밖이 바뀌었다:" >&2
  diff <(echo "$BEFORE") <(echo "$AFTER") >&2 || true
  exit 4
fi
echo "[bake] 소유 밖 변경 0"
exit "$size_status"
