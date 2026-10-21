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
      exec sudo -n unshare --net -- /bin/sh -c '
        ip link set lo up || exit 3
        user="$1"; path="$2"; shift 2
        exec sudo -n -E -u "$user" env PATH="$path" AINGCHECK_GATE_INNER=1 AINGCHECK_NETWORK_SEALED=1 /bin/bash "$@"
      ' sh "$(id -un)" "$PATH" "$SELF" "$@"
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
canary_status="$("$PY" -I - "$canary_xml" <<'PY'
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
PY
)"

# 홈 잔재: 새 꼭대기 항목(빌드 도구 캐시 폴더는 뺀다)과 java.util.prefs plist 변화.
ls -A "$HOME" | LC_ALL=C sort > "$gate_dir/home-after.txt"
new_home="$(LC_ALL=C comm -13 "$gate_dir/home-before.txt" "$gate_dir/home-after.txt" | grep -v -x -E '\.gradle|\.android|\.m2|\.kotlin|\.konan|\.skiko' || true)"
prefs_after="absent"
if [[ -e "$prefs_plist" ]]; then prefs_after="$(stat -f '%m' "$prefs_plist" 2>/dev/null || echo present)"; fi

status=0
echo "gate-$KIND: os=$OS gradle-exit=$rc elapsed=${elapsed}s canary=$canary_status"
if [[ $rc -ne 0 ]]; then status=1; fi
if [[ "$canary_status" != "ran" ]]; then echo "gate-$KIND: NetworkCanaryTest 가 초록으로 돌지 않았다($canary_status)" >&2; status=1; fi
if [[ -n "$new_home" ]]; then echo "gate-$KIND: 시험이 \$HOME 에 새 항목을 남겼다: $new_home" >&2; status=1; fi
if [[ "$prefs_before" != "$prefs_after" ]]; then echo "gate-$KIND: java.util.prefs plist 가 바뀌었다($prefs_before → $prefs_after)" >&2; status=1; fi
exit $status
