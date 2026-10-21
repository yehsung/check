#!/usr/bin/env bash
# Swift → Kotlin 골든 내보내기(xplat W0-b · C§5.3·§5.4 · A§4-2 · K1). 형식은 contract/README.md.
#
#   scripts/golden-export.sh                        비교 모드 — Swift 가 지금 낸 값이 커밋된 골든과 바이트까지 같아야 0
#   CHECK_GOLDEN_WRITE=1 scripts/golden-export.sh   쓰기 모드 — 골든·_manifest.json·_digests.json 을 다시 쓰고 **언제나 1**
#   scripts/golden-export.sh --skip-build           swift build --build-tests 를 건너뛴다
#
# 하는 일(순서대로, 하나라도 어긋나면 빨강):
#   1. sandbox-exec 로 바깥 IP 연결을 막고(기억 render-tests-hit-production) `swift build --build-tests`.
#      SwiftPM 은 매니페스트를 자기 샌드박스로 컴파일하는데 sandbox-exec 안에서 또 걸면 막힌다 — 그래서 --disable-sandbox.
#   2. 개수 단언(A-X24 — G §8-1 로 '맥 전체 스위트' 소속): `swift test list`(= 전체 스위트 목록)의 GoldenExport 시험 수 L.
#   3. `swift test --filter GoldenExport` 를 영수증 폴더(CHECK_GOLDEN_RUN_DIR)와 함께 돌린다. 돈 수 = L, 건너뜀 0,
#      그리고 L = _manifest.json 에 박힌 exportTests(이름이 바뀌어 필터에서 조용히 빠지는 것을 막는다).
#      xunit 결과의 classname 으로 `GoldenExport…` 스위트 밖에서 돈 시험(파일 이름 때문에 필터에 걸린 자유 함수 등)을 짚는다.
#   4. 영수증으로 _manifest.json 조립 · 고아(영수증 없는 골든 파일) 검사(golden-digest.py assemble).
#   5. 비교 모드: golden-digest.py --check(CI 와 같은 지문) · 저장소에 쓴 것 0(git status 전후 같음).
#      쓰기 모드: golden-digest.py --write, 바뀐 파일 목록을 보이고 1 로 끝낸다(실수로 초록이 되지 않게).
# 실패를 삼키지 않는다(set -euo pipefail · 시험과 푸시는 다른 호출 — 기억 test-grep-chain-masks-failure).
# 종료 코드: 0 비교 모드 초록 · 1 불일치·시험 실패·쓰기 모드 · 2 도구·인자 문제.
#
# 맥 전체 스위트(swift test)만으로는 2·3·4(개수 · 건너뜀 0 · 스위트 밖 시험 · 영수증 고아 · 목록 조립)를 재지 않는다 —
# 이 스크립트를 따로 돌린다: 갈래 완료·병합마다(G §2-5), Android·Windows 출시 전(G §4-1). contract/README.md §3.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SEAL='(version 1)(allow default)(deny network-outbound (remote ip "*:*"))(allow network-outbound (remote ip "localhost:*"))(allow network-outbound (remote unix-socket))'
TOOLS="$ROOT/multiplatform/tools"
FILTER='GoldenExport'

SKIP_BUILD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "golden-export: 모르는 인자 $1" >&2; exit 2 ;;
  esac
  shift
done

case "${CHECK_GOLDEN_WRITE:-}" in
  "") MODE=compare ;;
  1) MODE=write ;;
  *) echo "golden-export: CHECK_GOLDEN_WRITE 는 1 만 받는다(받은 값 '${CHECK_GOLDEN_WRITE}')" >&2; exit 2 ;;
esac
[ "$(uname -s)" = Darwin ] || { echo "golden-export: 맥에서만 돈다(Swift 가 기준 구현이다)" >&2; exit 2; }
command -v python3 >/dev/null || { echo "golden-export: python3 가 없다" >&2; exit 2; }

sealed() { /usr/bin/sandbox-exec -p "$SEAL" "$@"; }

RUN="$(mktemp -d "${TMPDIR:-/tmp}/golden-export.XXXXXX")"
cleanup() { rm -rf "$RUN"; }
trap cleanup EXIT

cd "$ROOT"
status_before="$(git status --porcelain=v1 --untracked-files=all 2>/dev/null | LC_ALL=C sort || true)"

if [ "$SKIP_BUILD" = 0 ]; then
  started=$(date +%s)
  if ! sealed swift build --build-tests --disable-sandbox >"$RUN/build.log" 2>&1; then
    tail -40 "$RUN/build.log" >&2
    echo "golden-export: 빌드 실패" >&2
    exit 1
  fi
  echo "golden-export: 빌드 $(( $(date +%s) - started ))초"
fi

# 2. 전체 스위트 목록에서 GoldenExport 시험 수.
if ! sealed swift test list --skip-build --disable-sandbox >"$RUN/list.txt" 2>"$RUN/list.err"; then
  tail -20 "$RUN/list.err" >&2
  echo "golden-export: swift test list 실패" >&2
  exit 1
fi
listed="$(grep -cE "\.${FILTER}[A-Za-z0-9_]*/" "$RUN/list.txt" || true)"
[ "$listed" -gt 0 ] || { echo "golden-export: 전체 스위트 목록에 ${FILTER} 시험이 하나도 없다" >&2; exit 1; }

# 3. 내보내기 실행(봉인 · 영수증).
started=$(date +%s)
set +e
sealed env CHECK_GOLDEN_RUN_DIR="$RUN" CHECK_GOLDEN_REPO_ROOT="$ROOT" CHECK_GOLDEN_WRITE="${CHECK_GOLDEN_WRITE:-}" \
  swift test --skip-build --disable-sandbox --filter "$FILTER" --xunit-output "$RUN/xunit.xml" >"$RUN/test.log" 2>&1
test_rc=$?
set -e
elapsed=$(( $(date +%s) - started ))

# 첫 줄: 돈 수 · 건너뜀 · 실패. 둘째 줄부터: GoldenExport… 스위트 밖에서 돈 시험(xunit classname 기준, "classname · name").
counts="$(python3 -I - "$RUN/test.log" "$RUN" "$FILTER" <<'PY'
import glob, os, re, sys
import xml.etree.ElementTree as ET
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
# 시험 타깃(맥 · 폰)마다 따로 돌아 요약 줄이 여럿일 수 있다 — 전부 더한다.
m = re.findall(r"Test run with (\d+) tests? in \d+ suites? (passed|failed)", text)
ran = sum(int(n) for n, _ in m) if m else -1
skipped = len(re.findall(r"^\S+ Test .* skipped", text, re.M))
failed = len(re.findall(r"^\S+ Test (?!run with ).* failed after", text, re.M))
print(ran, skipped, failed)
suite = re.compile(r"^[^.]+\." + re.escape(sys.argv[3]) + r"[A-Za-z0-9_]*(\.[A-Za-z0-9_]+)*$")
for path in sorted(glob.glob(os.path.join(sys.argv[2], "xunit*.xml"))):
    try:
        root = ET.parse(path).getroot()
    except Exception:
        continue
    for case in root.iter("testcase"):
        classname = case.get("classname", "")
        if not suite.match(classname):
            print(f"{classname} · {case.get('name', '')}")
PY
)"
read -r ran skipped failed_tests <<<"$(printf '%s\n' "$counts" | head -n 1)"
outside="$(printf '%s\n' "$counts" | tail -n +2)"
pinned="$(python3 -I -c 'import json,sys
try: print(json.load(open(sys.argv[1]))["exportTests"])
except Exception: print(-1)' "$ROOT/contract/golden/_manifest.json")"

echo "golden-export: 모드=$MODE swift-test-exit=$test_rc ${elapsed}초 · 전체 스위트 목록의 ${FILTER} 시험 $listed · 돈 시험 $ran · 건너뜀 $skipped · 실패 $failed_tests · 목록에 박힌 수 $pinned"

problems=0
if [ -n "$outside" ]; then
  echo "golden-export: ${FILTER} 스위트 밖에서 돈 시험이 있다 — 파일·이름이 --filter ${FILTER} 에 걸렸지만 @Suite struct ${FILTER}<…> 의 메서드가 아니다(자유 함수 등). 스위트 메서드로 옮긴다:" >&2
  printf '%s\n' "$outside" | sed 's/^/  - /' >&2
  problems=1
fi
if [ "$ran" != "$listed" ]; then
  echo "golden-export: 돈 시험 수($ran) ≠ 전체 스위트 목록의 ${FILTER} 시험 수($listed) — 목록 정규식은 ${FILTER}<…> 스위트의 메서드만 센다." >&2
  echo "  돈 수가 더 크면: ${FILTER} 파일·이름에 걸렸지만 ${FILTER}<…> 스위트 밖인 시험(자유 함수 등)이 있다(위 목록). 작으면: 목록에 있는 시험이 안 돌았다." >&2
  problems=1
fi
if [ "$skipped" != 0 ]; then echo "golden-export: 건너뛴 ${FILTER} 시험이 있다($skipped) — 건너뛰어서 초록은 게이트가 아니다" >&2; problems=1; fi

# 4. 영수증 → _manifest.json(쓰기 모드는 개수도 새로 박는다).
set +e
python3 -I "$TOOLS/golden-digest.py" assemble --run "$RUN" --mode "$MODE" --export-tests "$listed"
assemble_rc=$?
set -e
[ "$assemble_rc" = 0 ] || problems=1

if [ "$MODE" = write ]; then
  python3 -I "$TOOLS/golden-digest.py" --write
  echo "golden-export: 쓰기 모드 — 바뀐 골든:"
  { git status --porcelain=v1 --untracked-files=all -- contract/golden multiplatform/testkit/src/desktopTest/resources/golden 2>/dev/null || true; } | sed 's/^/  /'
  if [ "$test_rc" != 0 ] && [ "$failed_tests" -gt 0 ]; then
    grep -E "^\S+ Test .* (failed|recorded an issue)" "$RUN/test.log" | grep -v "CHECK_GOLDEN_WRITE=1" | head -20 >&2 || true
  fi
  echo "golden-export: CHECK_GOLDEN_WRITE=1 은 언제나 실패로 끝난다 — git diff 로 이유를 확인하고 비교 모드로 다시 돌린다" >&2
  exit 1
fi

# 5. 비교 모드: 시험 · 지문 · 저장소 쓰기 0.
if [ "$test_rc" != 0 ]; then
  grep -E -A1 "recorded an issue" "$RUN/test.log" | grep -v '^--$' | head -40 >&2 || true
  echo "golden-export: ${FILTER} 시험이 빨갛다(exit $test_rc)" >&2
  problems=1
fi
set +e
python3 -I "$TOOLS/golden-digest.py" --check
digest_rc=$?
set -e
[ "$digest_rc" = 0 ] || problems=1
if [ "$pinned" != "$listed" ]; then
  echo "golden-export: _manifest.json 의 exportTests($pinned) ≠ 지금 ${FILTER} 시험 수($listed) — 시험을 더하거나 뺐으면 CHECK_GOLDEN_WRITE=1 로 목록을 다시 쓴다" >&2
  problems=1
fi
status_after="$(git status --porcelain=v1 --untracked-files=all 2>/dev/null | LC_ALL=C sort || true)"
if [ "$status_before" != "$status_after" ]; then
  echo "golden-export: 비교 모드가 저장소를 바꿨다:" >&2
  diff <(echo "$status_before") <(echo "$status_after") >&2 || true
  problems=1
fi
if [ "$problems" != 0 ]; then exit 1; fi
echo "golden-export: 비교 모드 초록 — ${FILTER} 시험 $listed 개 전부 돌았고 골든·목록·지문이 일치한다"
exit 0
