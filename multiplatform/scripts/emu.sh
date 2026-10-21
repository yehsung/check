#!/bin/bash
# emu.sh — 창 없는 Android 에뮬레이터를 띄우고·찍고·끄는 유일한 입구 (W0-f, A§4-3·A-X7)
#
# 규칙(설계 G §2-2, A§4-3)
#   - 언제나 -no-window -no-audio -no-boot-anim -no-snapshot -read-only. 스냅숏을 저장하지 않는다.
#   - 포트는 갈래마다 고정(5560+2k). 기본값이 없다 — 남의 에뮬레이터와 겹치지 않게 반드시 적는다.
#   - 기본은 망 봉인(sandbox-exec). 봉인 없이 띄우려면 --no-seal 을 적는다.
#   - 끈 뒤에는 자기가 띄운 emulator·qemu 프로세스가 0 이어야 한다. 대기는 PID + kill -0 (pgrep 대기 금지).
#   - adb 서버는 남과 같이 쓴다. adb kill-server 를 부르지 않는다.
#
# 사용
#   emu.sh start   --avd NAME --port N [--seal PROFILE | --no-seal] [--boot-timeout 120] [-- 에뮬레이터 인자…]
#   emu.sh stop    --port N [--timeout 30]
#   emu.sh shot    --port N --out FILE.png
#   emu.sh windows --port N        # 이 포트로 띄운 프로세스의 창 수 + 이름이 qemu/emulator 인 모든 창 수(둘 중 하나라도 0 이 아니면 1)
#   emu.sh procs   --port N        # 이 포트로 띄운 프로세스 중 살아 있는 수(0 이 아니면 종료 코드 1)
#   emu.sh sealcheck --port N      # 손님 안에서 바깥 TCP(1.1.1.1:443)가 실패하고 adb 는 사는지. 둘 다면 0, 아니면 1
#   emu.sh instrumented [--avd aingcheck-api36] [--port 5560] [--seal PROFILE | --no-seal] [--task :androidApp:connectedDebugAndroidTest]
#                                  # gate-full.sh 가 부른다(W0 통합): 띄우기(봉인 기본) → sealcheck·창 0 → 계측 시험(Gradle 도 같은 봉인,
#                                  # --offline --no-daemon, ANDROID_SERIAL 로 이 기기만) → 결과 XML 로 시험 ≥1·건너뜀 0·실패 0 확인
#                                  # → 언제나 끄기·남은 프로세스 0 확인. 종료 코드: Gradle 실패면 그 코드, 아니면 판정 실패 1, 정리 실패 1.
#
# 환경
#   ANDROID_SDK_ROOT / ANDROID_HOME (없으면 ~/Library/Android/sdk)
#   EMU_STATE_DIR (없으면 $TMPDIR/aingcheck-emu) — PID·로그 자리
set -u -o pipefail

SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
EMU_BIN="$SDK/emulator/emulator"
ADB="$SDK/platform-tools/adb"
STATE="${EMU_STATE_DIR:-${TMPDIR:-/tmp}/aingcheck-emu}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_SEAL="$SCRIPT_DIR/seal.sb"

die() { echo "emu.sh: $*" >&2; exit 2; }
log() { echo "emu.sh: $*" >&2; }

cmd="${1:-}"; [ -n "$cmd" ] || die "명령이 없다 (start|stop|shot|windows|procs|sealcheck|instrumented)"; shift

AVD=""; PORT=""; SEAL="$DEFAULT_SEAL"; SEALED=1; BOOT_TIMEOUT=120; STOP_TIMEOUT=30; OUT=""
TASK=":androidApp:connectedDebugAndroidTest"
EXTRA=()
# instrumented 의 기본값(gate-full.sh 가 인자 없이 부른다): api36 AVD · 갈래 포트 5560(5560+2k 의 k=0, W0-f 가 쓴 자리).
if [ "$cmd" = "instrumented" ]; then AVD="aingcheck-api36"; PORT="5560"; BOOT_TIMEOUT=180; fi
while [ $# -gt 0 ]; do
  case "$1" in
    --avd) AVD="${2:?}"; shift 2 ;;
    --port) PORT="${2:?}"; shift 2 ;;
    --seal) SEAL="${2:?}"; SEALED=1; shift 2 ;;
    --no-seal) SEALED=0; shift ;;
    --boot-timeout) BOOT_TIMEOUT="${2:?}"; shift 2 ;;
    --timeout) STOP_TIMEOUT="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --task) TASK="${2:?}"; shift 2 ;;
    --) shift; EXTRA=("$@"); break ;;
    *) die "모르는 인자: $1" ;;
  esac
done

[ -n "$PORT" ] || die "--port 가 필요하다(갈래별 5560+2k)"
case "$PORT" in *[!0-9]*) die "포트는 숫자: $PORT" ;; esac
[ "$PORT" -ge 5554 ] && [ "$PORT" -le 5682 ] && [ $((PORT % 2)) -eq 0 ] || die "포트는 5554..5682 의 짝수: $PORT"

SERIAL="emulator-$PORT"
PIDFILE="$STATE/emu-$PORT.pid"     # 첫 줄: 띄운 PID(sandbox-exec 가 exec 한 emulator), 둘째 줄부터: 자식 PID. 끈 뒤에도 남겨 procs 로 다시 센다
LOGFILE="$STATE/emu-$PORT.log"
mkdir -p "$STATE"

# 이 포트로 띄운 PID 와 그 자손(재귀), 그리고 적어 둔 자식 중 살아 있는 것을 낸다(중복 있음).
tree_pids() {
  [ -f "$PIDFILE" ] || return 0
  local queue p c
  queue=( $(cat "$PIDFILE") )
  while [ ${#queue[@]} -gt 0 ]; do
    p="${queue[0]}"; queue=( "${queue[@]:1}" )
    [ -n "$p" ] || continue
    kill -0 "$p" 2>/dev/null || continue
    echo "$p"
    for c in $(pgrep -P "$p" 2>/dev/null); do queue+=( "$c" ); done
  done
}

alive_count() { tree_pids | sort -u | grep -c . ; }

# CGWindowList 에서 주어진 PID 들이 가진 창 수(화면 밖 포함 전부).
window_count() {
  local pids="$1"
  /usr/bin/osascript -l JavaScript - "$pids" <<'JXA'
ObjC.import("CoreGraphics");
function run(argv) {
  var want = {};
  (argv[0] || "").split(/\s+/).filter(String).forEach(function (p) { want[p] = true; });
  var arr = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll, 0))) || [];
  var own = 0, any = 0;
  arr.forEach(function (w) {
    var owner = String(w.kCGWindowOwnerName || "");
    if (want[String(w.kCGWindowOwnerPID)]) own++;
    if (/qemu-system|^emulator$/i.test(owner)) any++;
  });
  return own + " " + any;
}
JXA
}

case "$cmd" in
start)
  [ -n "$AVD" ] || die "--avd 가 필요하다"
  [ -x "$EMU_BIN" ] || die "에뮬레이터가 없다: $EMU_BIN"
  [ -f "$HOME/.android/avd/$AVD.ini" ] || die "AVD 가 없다: $AVD"
  if [ -f "$PIDFILE" ] && [ "$(alive_count)" -gt 0 ]; then die "포트 $PORT 에 이미 띄운 에뮬레이터가 있다(PID $(head -1 "$PIDFILE"))"; fi
  if "$ADB" devices 2>/dev/null | awk '{print $1}' | grep -qx "$SERIAL"; then die "$SERIAL 를 이미 누가 쓰고 있다 — 다른 포트를 써라"; fi
  "$ADB" start-server >/dev/null 2>&1 || die "adb 서버를 못 띄웠다"

  args=( -avd "$AVD" -port "$PORT" -no-window -no-audio -no-boot-anim -no-snapshot -read-only
         -no-metrics -gpu swiftshader_indirect )
  [ ${#EXTRA[@]} -gt 0 ] && args+=( "${EXTRA[@]}" )
  launcher=()
  if [ "$SEALED" -eq 1 ]; then
    [ -f "$SEAL" ] || die "봉인 프로파일이 없다: $SEAL (--seal 경로 또는 --no-seal)"
    launcher=( /usr/bin/sandbox-exec -f "$SEAL" )
  fi
  : > "$LOGFILE"
  t0=$(date +%s)
  # 새 세션으로 떼어 낸다(부른 셸이 끝나도 산다). PID 는 sandbox-exec → exec → emulator 로 같다.
  /usr/bin/perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec: $!"' -- \
    ${launcher[@]+"${launcher[@]}"} "$EMU_BIN" "${args[@]}" </dev/null >>"$LOGFILE" 2>&1 &
  pid=$!
  echo "$pid" > "$PIDFILE"
  log "띄움 avd=$AVD port=$PORT sealed=$SEALED pid=$pid log=$LOGFILE"

  booted=0
  while :; do
    now=$(date +%s)
    if ! kill -0 "$pid" 2>/dev/null; then
      log "에뮬레이터가 부팅 중에 죽었다 — 로그 끝:"; tail -20 "$LOGFILE" >&2
      "$0" stop --port "$PORT" --timeout 10 >&2   # 남은 자식(netsimd 등)까지 정리
      exit 1
    fi
    # 자식(qemu)을 따로 적어 둔다 — 부모가 먼저 죽어도 끝에서 센다.
    for c in $(pgrep -P "$pid" 2>/dev/null); do grep -qx "$c" "$PIDFILE" || echo "$c" >> "$PIDFILE"; done
    v="$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')"
    if [ "$v" = "1" ]; then booted=1; break; fi
    if [ $((now - t0)) -ge "$BOOT_TIMEOUT" ]; then break; fi
    sleep 2
  done
  t1=$(date +%s)
  if [ "$booted" -ne 1 ]; then
    log "부팅 시한 ${BOOT_TIMEOUT}s 초과 — 끈다"
    "$0" stop --port "$PORT" --timeout 20 >&2
    echo "boot=timeout seconds=$((t1 - t0))"
    exit 1
  fi
  echo "boot=ok seconds=$((t1 - t0)) serial=$SERIAL pid=$pid sealed=$SEALED"
  ;;

stop)
  if [ ! -f "$PIDFILE" ] || [ "$(alive_count)" -eq 0 ]; then echo "stopped alive=0 (띄운 것 없음)"; exit 0; fi
  "$ADB" -s "$SERIAL" emu kill >/dev/null 2>&1 || true
  t0=$(date +%s)
  while [ "$(alive_count)" -gt 0 ] && [ $(( $(date +%s) - t0 )) -lt "$STOP_TIMEOUT" ]; do sleep 1; done
  if [ "$(alive_count)" -gt 0 ]; then
    log "emu kill 뒤에도 살아 있다 — TERM"
    for p in $(tree_pids | sort -u); do kill -TERM "$p" 2>/dev/null; done
    t1=$(date +%s); while [ "$(alive_count)" -gt 0 ] && [ $(( $(date +%s) - t1 )) -lt 10 ]; do sleep 1; done
  fi
  if [ "$(alive_count)" -gt 0 ]; then
    log "TERM 뒤에도 살아 있다 — KILL"
    for p in $(tree_pids | sort -u); do kill -KILL "$p" 2>/dev/null; done
    sleep 1
  fi
  n="$(alive_count)"
  echo "stopped alive=$n seconds=$(( $(date +%s) - t0 ))"
  [ "$n" -eq 0 ]
  ;;

shot)
  [ -n "$OUT" ] || die "--out 이 필요하다"
  "$ADB" -s "$SERIAL" exec-out screencap -p > "$OUT" || die "screencap 실패"
  magic="$(head -c 8 "$OUT" | xxd -p)"
  [ "$magic" = "89504e470d0a1a0a" ] || die "PNG 가 아니다: $OUT (머리 $magic)"
  w=$(/usr/bin/sips -g pixelWidth "$OUT" 2>/dev/null | awk '/pixelWidth/{print $2}')
  h=$(/usr/bin/sips -g pixelHeight "$OUT" 2>/dev/null | awk '/pixelHeight/{print $2}')
  echo "shot=$OUT bytes=$(wc -c < "$OUT" | tr -d ' ') size=${w}x${h}"
  ;;

windows)
  pids="$(tree_pids | sort -u | tr '\n' ' ')"
  read -r own any <<<"$(window_count "$pids")"
  echo "windows_own=$own windows_any_emulator=$any pids=[${pids% }]"
  [ "$own" = "0" ] && [ "$any" = "0" ]
  ;;

sealcheck)
  [ -f "$PIDFILE" ] && [ "$(alive_count)" -gt 0 ] || die "포트 $PORT 에 띄운 에뮬레이터가 없다"
  pong="$("$ADB" -s "$SERIAL" shell echo pong 2>/dev/null | tr -d '\r')"
  # toybox nc: 연결되면 0, 못 하면 1. 시한 5초.
  out="$("$ADB" -s "$SERIAL" shell 'toybox nc -w 5 1.1.1.1 443 </dev/null >/dev/null 2>&1; echo rc=$?' 2>/dev/null | tr -d '\r')"
  echo "adb=${pong:-dead} outbound_tcp_${out}"
  [ "$pong" = "pong" ] && [ "$out" != "rc=0" ] && [ -n "$out" ]
  ;;

procs)
  n="$(alive_count)"
  echo "alive=$n pids=[$(tree_pids | sort -u | tr '\n' ' ' | sed 's/ $//')]"
  [ "$n" -eq 0 ]
  ;;

instrumented)
  MP="$(cd "$SCRIPT_DIR/.." && pwd)"
  case "$TASK" in :*:*) ;; *) die "--task 는 :모듈:작업 꼴이다: $TASK" ;; esac
  module_dir="$(printf '%s' "$TASK" | sed -e 's/^://' -e 's/:[^:]*$//' -e 's#:#/#g')"
  results="$MP/$module_dir/build/outputs/androidTest-results/connected"
  PY="$(command -v python3 || true)"; [ -n "$PY" ] || die "결과 XML 을 읽을 python3 가 없다"
  [ "$SEALED" -eq 0 ] || [ -f "$SEAL" ] || die "봉인 프로파일이 없다: $SEAL"
  started_emu=0
  # 언제나 끈다: 실패·중단에도 이 포트로 띄운 것을 거두고 0 인지 센다(남의 에뮬레이터·adb 서버는 건드리지 않는다).
  finish() {
    local rc=$1 n
    if [ "$started_emu" -eq 1 ]; then
      "$0" stop --port "$PORT" --timeout 30 >&2
      n="$(alive_count)"
      if [ "$n" -ne 0 ]; then log "끈 뒤에도 프로세스 $n 개가 산다"; [ "$rc" -ne 0 ] || rc=1; fi
      echo "instrumented: 정리 alive=$n" >&2
    fi
    exit "$rc"
  }
  trap 'finish 130' INT TERM

  seal_args=(--seal "$SEAL"); [ "$SEALED" -eq 1 ] || seal_args=(--no-seal)
  started_emu=1
  "$0" start --avd "$AVD" --port "$PORT" "${seal_args[@]}" --boot-timeout "$BOOT_TIMEOUT" || { log "에뮬레이터를 못 띄웠다"; finish 1; }
  if [ "$SEALED" -eq 1 ]; then
    "$0" sealcheck --port "$PORT" || { log "봉인 확인 실패 — 손님 안 바깥 연결이 열렸거나 adb 가 죽었다"; finish 1; }
  fi
  "$0" windows --port "$PORT" || { log "에뮬레이터가 창을 가졌다"; finish 1; }

  rm -rf "$results"
  gradle_cmd=( "$MP/gradlew" -p "$MP" --offline --no-daemon "$TASK"
               "-Pandroid.testInstrumentationRunnerArguments.aingcheckSealed=$SEALED" )
  log "계측 시작 task=$TASK serial=$SERIAL sealed=$SEALED"
  t0=$(date +%s)
  if [ "$SEALED" -eq 1 ]; then
    # Gradle·UTP 도 같은 봉인 아래(바깥 IP 거부, localhost — adb 서버 5037·에뮬레이터 콘솔 — 허용).
    /usr/bin/sandbox-exec -f "$SEAL" /usr/bin/env AINGCHECK_NETWORK_SEALED=1 ANDROID_SERIAL="$SERIAL" "${gradle_cmd[@]}"
  else
    ANDROID_SERIAL="$SERIAL" "${gradle_cmd[@]}"
  fi
  grc=$?
  # 시험이 찍은 근거 줄(System.out → logcat)을 남긴다.
  "$ADB" -s "$SERIAL" logcat -d -s System.out:I 2>/dev/null | grep 'AINGCHECK-' | sed 's/^/instrumented: /' >&2 || true
  verdict="$("$PY" -I - "$results" <<'PY'
import os, sys, xml.etree.ElementTree as ET
root = sys.argv[1]
t = sk = f = 0; files = 0
for dirpath, _, names in os.walk(root):
    for n in names:
        if n.startswith("TEST-") and n.endswith(".xml"):
            files += 1
            r = ET.parse(os.path.join(dirpath, n)).getroot()
            for s in ([r] if r.tag == "testsuite" else list(r.iter("testsuite"))):
                t += int(s.get("tests", 0)); sk += int(s.get("skipped", 0))
                f += int(s.get("failures", 0)) + int(s.get("errors", 0))
ok = files >= 1 and t >= 1 and sk == 0 and f == 0
print(("ok" if ok else "bad") + f" files={files} tests={t} skipped={sk} failed={f}")
PY
)"
  echo "instrumented: gradle-exit=$grc elapsed=$(( $(date +%s) - t0 ))s results=[$verdict] avd=$AVD serial=$SERIAL sealed=$SEALED"
  rc=0
  if [ "$grc" -ne 0 ]; then rc=$grc
  elif [ "${verdict%% *}" != "ok" ]; then log "결과가 게이트 조건(시험 ≥1 · 건너뜀 0 · 실패 0)을 못 채웠다: $verdict"; rc=1
  fi
  "$0" windows --port "$PORT" >&2 || { log "시험 뒤 창이 생겼다"; [ "$rc" -ne 0 ] || rc=1; }
  finish "$rc"
  ;;

*) die "모르는 명령: $cmd" ;;
esac
