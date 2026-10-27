#!/usr/bin/env bash
# 빠른 게이트(K12, A§4-6). 시험은 이 스크립트(와 gate-full.sh)로만 돈다.
#
#   multiplatform/scripts/gate-fast.sh            # 봉인 아래 JVM 시험 전부(slow 태그 제외)
#   multiplatform/scripts/gate-fast.sh --warm     # 봉인 밖 의존 예열만(처음 한 번, 네트워크 필요)
#
# 봉인(③층 OS):
#   맥      sandbox-exec -f seal.sb (바깥 IP 연결 거부, localhost 허용)
#   Linux   sudo unshare -n (새 망 이름공간, lo 만 올림) → 원래 사용자로 내려와 실행
#   Windows 바깥에서 건 방화벽 규칙(java.exe 아웃바운드 차단)을 AINGCHECK_EXTERNAL_SEAL=windows-firewall 로 알린다
# 봉인 안에서는 AINGCHECK_NETWORK_SEALED=1 을 주고 --offline --no-daemon 으로 돈다.
# NetworkCanaryTest 가 실제로 돌아 초록이었는지 결과 XML 로 센다(건너뛰었으면 실패).
#
# 실패를 삼키지 않는다: set -euo pipefail, 시험과 푸시는 다른 호출로(기억 test-grep-chain-masks-failure).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MP="$(cd "$HERE/.." && pwd)"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
KIND="${AINGCHECK_GATE_KIND:-fast}"

die() { echo "gate-$KIND: $*" >&2; exit 2; }

os_kind() {
  case "$(uname -s)" in
    Darwin) echo mac ;;
    Linux) echo linux ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) echo unknown ;;
  esac
}
OS="$(os_kind)"

# Windows(git bash)에서도 POSIX gradlew 를 쓴다(MSYS 경로 변환은 gradlew 가 한다).
gradlew() { "$MP/gradlew" "$@"; }

# 결과 XML 을 읽을 파이썬(맥·Linux 는 python3, Windows 러너는 python 일 수 있다).
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then PY="$c"; break; fi
done

# ---------- 예열(봉인 밖) ----------
if [[ "${1:-}" == "--warm" ]]; then
  cd "$MP"
  echo "gate-$KIND: 예열 — 봉인 밖에서 의존을 받는다(이 실행은 게이트가 아니다)"
  warm_tasks=(aingcheckPrefetch)
  if [[ "$OS" != windows ]]; then
    warm_tasks+=(:androidApp:assembleDebug :androidApp:assembleRelease :androidApp:lintDebug)
  fi
  warm_tasks+=(:desktopApp:jar)
  gradlew --no-daemon "${warm_tasks[@]}"
  exit 0
fi

# ---------- 봉인 걸기(바깥 단계) ----------
if [[ "${AINGCHECK_GATE_INNER:-}" != "1" ]]; then
  case "$OS" in
    mac)
      exec /usr/bin/sandbox-exec -f "$HERE/seal.sb" \
        /usr/bin/env AINGCHECK_GATE_INNER=1 AINGCHECK_NETWORK_SEALED=1 /bin/bash "$SELF" "$@"
      ;;
    linux)
      command -v unshare >/dev/null || die "unshare 가 없다"
      # 루트로 새 망 이름공간을 만들고 lo 만 올린 뒤, 원래 사용자로 내려와 같은 스크립트를 다시 부른다.
      # sudo -E 는 HOME 을 루트 것(/root)으로 남긴다(CI 실측) — 원래 HOME·PATH 를 인자로 넘겨 되돌린다.
      exec sudo -n unshare --net -- /bin/sh -c '
        ip link set lo up || exit 3
        user="$1"; path="$2"; home="$3"; jhome="$4"; shift 4
        exec sudo -n -E -u "$user" env PATH="$path" HOME="$home" JAVA_HOME="$jhome" AINGCHECK_GATE_INNER=1 AINGCHECK_NETWORK_SEALED=1 /bin/bash "$@"
      ' sh "$(id -un)" "$PATH" "$HOME" "${JAVA_HOME:-}" "$SELF" "$@"
      ;;
    windows)
      [[ "${AINGCHECK_EXTERNAL_SEAL:-}" == "windows-firewall" ]] \
        || die "Windows 는 방화벽 봉인을 먼저 걸고 AINGCHECK_EXTERNAL_SEAL=windows-firewall 로 부른다"
      export AINGCHECK_GATE_INNER=1 AINGCHECK_NETWORK_SEALED=1
      ;;
    *) die "모르는 OS: $(uname -s)" ;;
  esac
fi

# ---------- 봉인 안(안쪽 단계) ----------
[[ "${AINGCHECK_NETWORK_SEALED:-}" == "1" ]] || die "AINGCHECK_NETWORK_SEALED=1 이 없는 실행은 게이트가 아니다"
cd "$MP"

# 골든 지문(G §8-1: 맥 빠른 게이트·이 게이트에는 golden-digest --check 만 — Swift 비교 모드는 맥 전체 스위트).
# Swift 엔진·골든·작성기·바탕이 _digests.json 과 어긋나거나 생성 시험 이름이 주석에만 남으면
# "맥에서 scripts/golden-export.sh 를 돌려라"로 빨강(C§5.4 ③). Windows 러너에서도 돈다 — golden-digest 는 CRLF 체크아웃
# (골든 지문을 LF 로 접어 센다)과 cp1252 파이프(표준 출력을 UTF-8 로 바꾼다)에 견딘다(W0-b 검증 지적 수정).
[[ -n "$PY" ]] || die "golden-digest 를 돌릴 python3 가 없다"
golden_rc=0
if [[ -f "$MP/tools/golden-digest.py" ]]; then
  "$PY" -I "$MP/tools/golden-digest.py" --check || golden_rc=$?
else
  echo "gate-$KIND: multiplatform/tools/golden-digest.py 가 없다(W0-b 병합 전)" >&2
fi

# emu.sh 안전장치 자기 시험(W0-f ③ 검증 지적 — 저장소 안 회귀 그물이 없었다): 가짜 SDK·가짜 HOME 으로 --writable 거부
# (공용 이름·대소문자·별칭 .ini·보호 표식) · 기본 -read-only · 기본 봉인 · stop 의 sync 순서 · avd-clone · avd-protect 를 잰다.
# 진짜 에뮬레이터·adb·~/.android·망을 쓰지 않는다. emu.sh 는 맥·Linux 도구라 Windows 에서는 돌지 않는다(그 줄을 찍는다).
emu_rc=0
emu_status="not-run(windows)"
if [[ "$OS" != windows ]]; then
  emu_log="$MP/build/gate/emu-self-test.log"
  mkdir -p "$MP/build/gate"
  /bin/bash "$HERE/emu.sh" self-test > "$emu_log" 2>&1 || emu_rc=$?
  emu_status="exit=$emu_rc"
  grep -E '^self-test: (FAIL|사례)' "$emu_log" | sed "s/^/gate-$KIND: emu.sh /" || true
else
  echo "gate-$KIND: emu.sh self-test 안 돎(Windows — emu.sh 는 맥·Linux 도구)"
fi

# 시험 JVM 이 봉인 프로세스의 자손인지(SealAncestryTest). Windows 의 bash PID 는 Windows PID 가 아니라 뺀다.
if [[ "$OS" != windows ]]; then export AINGCHECK_GATE_PID="$$"; fi

if [[ "$OS" == windows ]]; then
  tasks=(aingcheckGateDesktop)
else
  tasks=(aingcheckGateFast)
fi
extra=()
if [[ "$KIND" == full ]]; then
  extra+=(-Paingcheck.includeSlow=true)
  if [[ "$OS" != windows ]]; then
    tasks+=(:androidApp:assembleRelease :androidApp:lintDebug)
  fi
  tasks+=(:desktopApp:jar)
fi

# 홈 잔재 검사 준비(기억 test-residue-fills-preferences): 실행 전 $HOME 꼭대기 이름 목록.
gate_dir="$MP/build/gate"
mkdir -p "$gate_dir"
ls -A "$HOME" | LC_ALL=C sort > "$gate_dir/home-before.txt"
prefs_plist="$HOME/Library/Preferences/com.apple.java.util.prefs.plist"
prefs_before="absent"
if [[ -e "$prefs_plist" ]]; then prefs_before="$(stat -f '%m' "$prefs_plist" 2>/dev/null || echo present)"; fi

started=$(date +%s)
set +e
gradlew --offline --no-daemon --continue "${tasks[@]}" "${extra[@]+"${extra[@]}"}"
rc=$?
set -e
elapsed=$(( $(date +%s) - started ))

# 카나리아가 실제로 돌았는가(건너뜀 = 게이트 아님).
canary_xml="$MP/testkit/build/test-results/desktopTest/TEST-com.yehsung.aingcheck.testkit.seal.NetworkCanaryTest.xml"
[[ -n "$PY" ]] || die "결과 XML 을 읽을 python3 가 없다"
canary_report="$("$PY" -I - "$canary_xml" <<'PY'
import sys, xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception as e:
    print("missing"); sys.exit(0)
suites = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
t = sum(int(s.get("tests", 0)) for s in suites)
sk = sum(int(s.get("skipped", 0)) for s in suites)
f = sum(int(s.get("failures", 0)) + int(s.get("errors", 0)) for s in suites)
print("ran" if t >= 1 and sk == 0 and f == 0 else f"bad tests={t} skipped={sk} failed={f}")
# 근거 줄(카나리아 연결 결과)을 게이트 로그에 남긴다 — CI 로그만으로 봉인을 확인할 수 있게.
for s in suites:
    out = s.find("system-out")
    for line in ((out.text or "") if out is not None else "").splitlines():
        if "AINGCHECK-" in line:
            print(line.strip())
PY
)"
canary_status="$(printf '%s\n' "$canary_report" | head -n 1)"
printf '%s\n' "$canary_report" | tail -n +2 | sed "s/^/gate-$KIND: /"
ancestry_xml="$MP/testkit/build/test-results/desktopTest/TEST-com.yehsung.aingcheck.testkit.seal.SealAncestryTest.xml"
if [[ -f "$ancestry_xml" ]]; then grep -o 'AINGCHECK-ANCESTRY.*' "$ancestry_xml" | head -n 1 | sed -e 's/]]>.*$//' -e "s/^/gate-$KIND: /" || true; fi

# 홈 잔재: 새 꼭대기 항목(빌드 도구 캐시 폴더는 뺀다)과 java.util.prefs plist 변화.
ls -A "$HOME" | LC_ALL=C sort > "$gate_dir/home-after.txt"
new_home="$(LC_ALL=C comm -13 "$gate_dir/home-before.txt" "$gate_dir/home-after.txt" | grep -v -x -E '\.gradle|\.android|\.m2|\.kotlin|\.konan|\.skiko' || true)"
prefs_after="absent"
if [[ -e "$prefs_plist" ]]; then prefs_after="$(stat -f '%m' "$prefs_plist" 2>/dev/null || echo present)"; fi

status=0
echo "gate-$KIND: os=$OS gradle-exit=$rc golden-digest-exit=$golden_rc emu-self-test=$emu_status elapsed=${elapsed}s canary=$canary_status"
if [[ $rc -ne 0 ]]; then status=1; fi
if [[ $golden_rc -ne 0 ]]; then echo "gate-$KIND: golden-digest --check 빨강(exit $golden_rc)" >&2; status=1; fi
if [[ $emu_rc -ne 0 ]]; then echo "gate-$KIND: emu.sh self-test 빨강(exit $emu_rc) — $MP/build/gate/emu-self-test.log" >&2; status=1; fi
if [[ "$canary_status" != "ran" ]]; then echo "gate-$KIND: NetworkCanaryTest 가 초록으로 돌지 않았다($canary_status)" >&2; status=1; fi
if [[ -n "$new_home" ]]; then echo "gate-$KIND: 시험이 \$HOME 에 새 항목을 남겼다: $new_home" >&2; status=1; fi
if [[ "$prefs_before" != "$prefs_after" ]]; then echo "gate-$KIND: java.util.prefs plist 가 바뀌었다($prefs_before → $prefs_after)" >&2; status=1; fi
exit $status
