#!/bin/bash
# 원본: 없음 (Swift 짝 없음 — 이식 도구)
# emu.sh — 창 없는 Android 에뮬레이터를 띄우고·찍고·끄는 유일한 입구 (W0-f, A§4-3·A-X7)
#   6차 int-f(조정자 대리, G §8-17 5): 전용 netsim 발견 폴더 · sealcheck 의 netsim Wi-Fi 길 측정 · 창 판정은 자기 PID 나무만(§8-6).
#
# 규칙(설계 G §2-2, A§4-3)
#   - 언제나 -no-window -no-audio -no-boot-anim -no-snapshot. 스냅숏을 저장하지 않는다.
#   - 기본은 -read-only(바뀐 것을 버린다 — 여러 갈래가 같은 AVD 를 동시에 쓴다). 예외는 --writable 하나다:
#     갈래 전용 AVD(avd-clone 으로 만든 것)를 준비할 때만 쓰고, 공용 AVD(aingcheck-api36·aingcheck-api26)와
#     준비가 끝나 보호 표식(.aingcheck-protected)을 단 AVD 에는 거부한다. 판정은 이름 글자가 아니라 에뮬레이터가 열 **폴더**로 한다
#     (맥 APFS 는 대소문자를 안 가려 'AINGCHECK-API36' 이 공용 폴더로 풀린다 · 다른 이름의 .ini 가 path= 로 공용 폴더를 가리킬 수 있다).
#   - 포트는 갈래마다 고정(5560+2k). 기본값이 없다 — 남의 에뮬레이터와 겹치지 않게 반드시 적는다.
#   - 기본은 망 봉인(sandbox-exec). 봉인 없이 띄우려면 --no-seal 을 적는다.
#   - 끈 뒤에는 자기가 띄운 emulator·qemu 프로세스가 0 이어야 한다. 대기는 PID + kill -0 (pgrep 대기 금지).
#   - adb 서버는 남과 같이 쓴다. adb kill-server 를 부르지 않는다.
#
# 사용
#   emu.sh start   --avd NAME --port N [--seal PROFILE | --no-seal] [--boot-timeout 120] [--writable] [-- 에뮬레이터 인자…]
#                                  # --writable: -read-only 를 빼고 띄운다 → 손님 /data 에 바뀐 것이 그 AVD 에 남는다(AVD 준비 전용).
#                                  #   거부(종료 코드 2, 띄우지 않음): 이름이 공용 AVD 와 대소문자 무시로 같다 · .ini 의 path=·path.rel=·NAME.avd
#                                  #   중 하나가 공용 AVD 폴더와 같은 폴더다(-ef) · 그 폴더에 보호 표식이 있다 · 폴더를 못 찾는다.
#                                  #   끌 때(stop) 손님 안에서 sync 를 먼저 부른다(쓰던 것이 디스크 사본에 닿게).
#                                  # 에뮬레이터에는 ANDROID_AVD_HOME 을 이 스크립트가 본 AVD 폴더로 넘긴다(판정한 곳과 여는 곳이 같게).
#                                  # 그래서 '--' 뒤 에뮬레이터 인자로 여는 AVD·자료를 바꾸는 것(-avd·@이름·-datadir·-data·-initdata·-sysdir·
#                                  #   -wipe-data·-writable-system)은 받지 않는다(종료 코드 2).
#   emu.sh avd-clone --from NAME --to NAME
#                                  # 갈래 전용 AVD 를 APFS 사본(맥 cp -c · 그 밖 cp --reflink=auto)으로 만든다 — 공용 AVD 를 쓰기로 띄우지 않으려고.
#                                  #   대상 이름이 이미 있거나(대소문자 무시) 공용 이름이면 거부(종료 코드 2). 실행 중 표식(*.lock·
#                                  #   bootcompleted.ini·emu-launch-params.txt·tmpAdbCmds)과 보호 표식은 옮기지 않는다(사본은 다시 준비할 수 있다).
#   emu.sh avd-protect --avd NAME  # 준비가 끝난 갈래 전용 AVD 폴더에 보호 표식을 단다 → 그 뒤 --writable 거부.
#                                  #   공용 AVD(이름·폴더)에는 쓰지 않는다(종료 코드 2 — 이미 보호된다). 풀 때는 표식 파일을 손으로 지운다.
#   emu.sh avd-prepare-ko --to NAME --port N [--from aingcheck-api36] [--boot-timeout 300]
#                                  # E-U5 한국어 조합 AVD 를 처음부터 만든다(아래 '갈래 전용 AVD' 의 명령열 그대로): avd-clone → 봉인 없이 쓰기로
#                                  #   띄움 → Gboard 에 한국어·두벌식 추가 → 조합이 될 때까지 자료 받기 → 끔 → 봉인·읽기 전용으로 다시 띄워 '안녕'
#                                  #   확인 → avd-protect. 망이 필요하다(Gboard 언어 자료). 계정 로그인 없음. 실패하면 만든 AVD 를 남겨 두고 1.
#   emu.sh self-test               # 가짜 SDK·가짜 HOME 으로 안전장치를 잰다(진짜 에뮬레이터·adb·~/.android 를 건드리지 않는다).
#                                  #   --writable 거부(공용 이름·대소문자·별칭 .ini·보호 표식·ANDROID_AVD_HOME 쪽 별칭) · 기본 -read-only ·
#                                  #   기본 봉인 · stop 의 sync 순서 · avd-clone 거부와 표식 정리 · avd-protect. 실패 사례 수만큼 빨강(종료 코드 1).
#   emu.sh stop    --port N [--timeout 30]
#   emu.sh shot    --port N --out FILE.png
#   emu.sh windows --port N        # 이 포트로 띄운 PID 나무(자손 포함 — qemu·netsimd)가 가진 창 수. 0 이 아니면 1, 살아 있는 자기 PID 가
#                                  #   없으면(빈 판정) 1. 남의 에뮬레이터 창(나무 밖 qemu/emulator 이름)은 windows_foreign_emulator 로 찍기만
#                                  #   한다(G §8-6 · §8-17 5 — 남의 세션이 게이트를 막지 않게).
#   emu.sh procs   --port N        # 이 포트로 띄운 프로세스 중 살아 있는 수(0 이 아니면 종료 코드 1)
#   emu.sh sealcheck --port N      # 봉인 확인(넷 다 맞으면 0, 아니면 1 — 한 줄에 근거를 찍는다):
#                                  #   ① netsim: 전용 발견 폴더의 netsim.ini 가 가리키는 netsimd 가 이 포트 PID 나무 안(own) — 로그엔 netsim 이
#                                  #      붙었는데 자기 것이 아니면 빨강(foreign) ② 길 기다리기(기준선): wlan0(netsim Wi-Fi)이 주소를 받고
#                                  #      손님 → 10.0.2.2:<콘솔 포트>(호스트 루프백)가 붙을 때까지(EMU_NET_TIMEOUT 초, 기본 120) — 부팅 직후엔
#                                  #      lo 밖 주소가 없어 '막힘'이 아무것도 재지 않는다 ③ 바깥 TCP 1.1.1.1:443·8.8.8.8:53 × EMU_PROBE_ROUNDS(기본 3,
#                                  #      EMU_PROBE_GAP 초 간격) + DNS 풀이 1번(dns.google — 'unknown host' 여야) ④ dumpsys connectivity 의 어떤 망도
#                                  #      VALIDATED·PARTIAL_CONNECTIVITY 가 아니다(안드로이드가 망마다 DNS·HTTP 로 잰 '인터넷 됨').
#                                  #   start 는 에뮬레이터에 전용 TMPDIR(<EMU_STATE_DIR>/netsim-<포트>/)을 준다 — 에뮬레이터는 TMPDIR 의 netsim.ini 로
#                                  #   떠 있는 netsimd 를 찾아 붙으므로, 기본 TMPDIR 이면 남의(봉인 안 된) netsimd 의 Wi-Fi 로 바깥이 열린다(int-e 실측).
#   emu.sh instrumented [--avd aingcheck-api36] [--port 5560] [--seal PROFILE | --no-seal] [--task :androidApp:connectedDebugAndroidTest]
#                                  # gate-full.sh 가 부른다(W0 통합): 띄우기(봉인 기본) → sealcheck·창 0 → 계측 시험(Gradle 도 같은 봉인,
#                                  # --offline --no-daemon, ANDROID_SERIAL 로 이 기기만) → 결과 XML 로 시험 ≥1·건너뜀 0·실패 0 확인
#                                  # → 언제나 끄기·남은 프로세스 0 확인. 종료 코드: Gradle 실패면 그 코드, 아니면 판정 실패 1, 정리 실패 1.
#
# 갈래 전용 AVD(W0-f 소유)
#   aingcheck-api36-ko = aingcheck-api36 의 avd-clone + Gboard 두벌식 + 한국어 조합 자료(E-U5 후속, 2026-10-28). 보호 표식을 달았다.
#     IME 재생 시험(W3-a)은 이 AVD 를 봉인·-read-only 로 띄워 쓴다(키 탭 ㅇㅏㄴㄴㅕㅇ·adb input text dkssud → '안녕',
#     setComposingText). 준비 안 된 공용 AVD 는 봉인에서 낱자모 commitText 다. selected_input_method_subtype -1906255757(ko_KR 두벌식).
#     다시 만들기(다른 맥 · 지워졌을 때): emu.sh avd-prepare-ko --to aingcheck-api36-ko --port <갈래 포트>. 하는 일:
#       1. avd-clone --from aingcheck-api36 --to NAME
#       2. start --avd NAME --no-seal --writable(망 필요 · 계정 없음)
#       3. ime set …LatinIME → Gboard 설정(com.google.android.inputmethod.latin/com.google.android.apps.inputmethod.latin.preference.SettingsActivity)
#          에서 uiautomator 로 글자를 찾아 누른다: Languages → Add keyboard → 검색 칸('Search for a language' — 두 번째부터
#          'Search language')에 input text Korean → 한국어 →
#          두벌식(selected 가 true 면 그대로) → Done. 확인: settings get secure enabled_input_methods 에 ;-1906255757 이 있다.
#       4. settings put secure selected_input_method_subtype -1906255757 → (am start -S 로 Gboard 를 다시 띄워) 같은 화면의 검색 칸
#          (EditText)에 adb input text dkssud 를 넣고 칸 글자를 읽어 '안녕' 이 될 때까지 15초 간격 최대 12번(자료를 받는 동안은
#          dkssud·낱자모 — 실측 1~2번째에 '안녕')
#       5. stop(손님 sync 먼저) → 봉인·-read-only 로 다시 띄워 sealcheck → 같은 확인('안녕') → stop → avd-protect --avd NAME
#     다시 준비하려면 보호된 AVD 를 avd-clone 해 새 이름으로 준비한다(사본에는 보호 표식이 없다).
#
# 바깥망 실험(W0-f ⑤ FCM 토큰 · 2026-10-28 · G §8-8 — 개발 Firebase 프로젝트에서만)
#   봉인 게이트와 따로 돈다: start --no-seal(전용 netsim 발견 폴더라 자기 netsimd 의 Wi-Fi 로 나간다) · 기본 -read-only(토큰을 든
#   앱·GMS 자료는 끄면 버려진다) · 갈래 포트. 계정 로그인은 하지 않는다(dumpsys account 의 'Accounts: 0' 을 앞뒤로 본다).
#   API 36 = 공용 aingcheck-api36(Play 이미지). API 35 Play 는 공용 AVD 가 없어 갈래 스크래치에 AVD 를 만들고(aingcheck-api36 의
#   config.ini 에서 image.sysdir.1·target 만 바꾼 사본) ANDROID_AVD_HOME=<스크래치>/avd 로 띄운다(판정·실행이 같은 폴더를 본다).
#   측정기·결과·다시 재는 법은 contract/measurements/w0f-fcm/README.md(조정자 패치). 토큰 원문은 기기 밖으로 내지 않는다.
#
# 환경
#   ANDROID_SDK_ROOT / ANDROID_HOME (없으면 ~/Library/Android/sdk)
#   ANDROID_AVD_HOME (없으면 ~/.android/avd) — 판정·사본·보호가 이 폴더를 보고, 에뮬레이터에도 같은 값을 넘긴다
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

cmd="${1:-}"; [ -n "$cmd" ] || die "명령이 없다 (start|stop|shot|windows|procs|sealcheck|instrumented|avd-clone|avd-protect|avd-prepare-ko|self-test)"; shift

SELF="$SCRIPT_DIR/$(basename "$0")"
AVD_HOME="${ANDROID_AVD_HOME:-$HOME/.android/avd}"
# 공용 AVD: 여러 갈래·게이트가 -read-only 로 동시에 띄운다. 쓰기로 띄우면 모두의 첫 상태가 바뀐다 — --writable 거부.
SHARED_AVDS="aingcheck-api36 aingcheck-api26"
# 보호 표식: 준비가 끝난 갈래 전용 AVD(예: aingcheck-api36-ko) 폴더에 avd-protect 가 단다. 있으면 --writable 거부.
PROTECT_MARK=".aingcheck-protected"

AVD=""; PORT=""; SEAL="$DEFAULT_SEAL"; SEALED=1; BOOT_TIMEOUT=120; STOP_TIMEOUT=30; OUT=""
WRITABLE=0; FROM=""; TO=""
TASK=":androidApp:connectedDebugAndroidTest"
EXTRA=()
# instrumented 의 기본값(gate-full.sh 가 인자 없이 부른다): api36 AVD · 갈래 포트 5560(5560+2k 의 k=0, W0-f 가 쓴 자리).
if [ "$cmd" = "instrumented" ]; then AVD="aingcheck-api36"; PORT="5560"; BOOT_TIMEOUT=180; fi
# avd-prepare-ko 의 기본값: 원본 공용 api36 · 부팅 시한 300초(부하가 높을 때 api36 이 120초를 넘긴 실측).
if [ "$cmd" = "avd-prepare-ko" ]; then FROM="aingcheck-api36"; BOOT_TIMEOUT=300; fi
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
    --writable) WRITABLE=1; shift ;;
    --from) FROM="${2:?}"; shift 2 ;;
    --to) TO="${2:?}"; shift 2 ;;
    --) shift; EXTRA=("$@"); break ;;
    *) die "모르는 인자: $1" ;;
  esac
done

valid_avd_name() { case "$1" in ''|*[!A-Za-z0-9._-]*|.*) return 1 ;; *) return 0 ;; esac; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
is_shared_name() { local a l; l="$(lower "$1")"; for a in $SHARED_AVDS; do [ "$(lower "$a")" = "$l" ] && return 0; done; return 1; }

# AVD 이름 → 에뮬레이터가 열 수 있는 폴더(있는 것만, 한 줄에 하나): <홈>/NAME.ini 의 path=·path.rel=(홈의 부모 기준)·<홈>/NAME.avd.
# 홈을 안 주면 AVD_HOME. 맥 APFS 에서는 NAME 의 대소문자가 달라도 같은 .ini·폴더로 풀린다(에뮬레이터도 그렇게 연다).
avd_dirs() {
  local name="$1" home="${2:-$AVD_HOME}" ini p
  ini="$home/$name.ini"
  if [ -f "$ini" ]; then
    p="$(sed -n 's/^path=//p' "$ini" | head -n 1 | tr -d '\r')"
    [ -n "$p" ] && [ -d "$p" ] && printf '%s\n' "$p"
    p="$(sed -n 's/^path\.rel=//p' "$ini" | head -n 1 | tr -d '\r')"
    [ -n "$p" ] && [ -d "$home/../$p" ] && printf '%s\n' "$home/../$p"
  fi
  [ -d "$home/$name.avd" ] && printf '%s\n' "$home/$name.avd"
  return 0
}

# 공용 AVD 폴더 전부(AVD_HOME 과 기본 ~/.android/avd 양쪽 — ANDROID_AVD_HOME 을 딴 데로 돌려 놓고 별칭으로 가리켜도 잡게).
shared_dirs() {
  local a h
  for h in "$AVD_HOME" "$HOME/.android/avd"; do
    for a in $SHARED_AVDS; do avd_dirs "$a" "$h"; done
  done
}

# NAME 이 공용 AVD 폴더와 같은 폴더(-ef: 같은 장치·inode — 대소문자·심볼릭 링크·별칭 .ini 를 다 거른다)로 풀리면 0.
resolves_to_shared() {
  local d sd
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    while IFS= read -r sd; do
      [ -n "$sd" ] && [ "$d" -ef "$sd" ] && return 0
    done < <(shared_dirs)
  done < <(avd_dirs "$1")
  return 1
}

# --writable 을 막을 까닭(없으면 빈 글자). 이름 글자만 보면 'AINGCHECK-API36'(APFS 대소문자 무시)이나 공용 폴더를 가리키는
# 다른 이름의 .ini 가 빠져나간다(W0-f ③ 검증 반박) — 이름(대소문자 무시)·실제 폴더·보호 표식을 모두 본다.
writable_block_reason() {
  local name="$1" d n=0
  if is_shared_name "$name"; then echo "공용 AVD 이름(대소문자 무시)"; return 0; fi
  if resolves_to_shared "$name"; then echo "공용 AVD 폴더로 풀린다(.ini 의 path=·path.rel= 또는 $name.avd 가 공용 폴더와 같은 폴더)"; return 0; fi
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    n=$((n + 1))
    if [ -e "$d/$PROTECT_MARK" ]; then echo "보호 표식이 있다($d/$PROTECT_MARK — avd-protect 로 단 준비 끝난 AVD)"; return 0; fi
  done < <(avd_dirs "$name")
  [ "$n" -gt 0 ] || echo "AVD 폴더를 못 찾았다($AVD_HOME/$name.ini 의 path=·path.rel=·$name.avd)"
  return 0
}

# 이름이 이미 있는가(.ini·.avd, 대소문자 무시 — 대소문자를 가리는 파일 시스템에서도 같은 이름 둘을 만들지 않는다).
avd_name_taken() {
  local l f b
  l="$(lower "$1")"
  for f in "$AVD_HOME"/*.ini "$AVD_HOME"/*.avd; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"; b="${b%.*}"
    [ "$(lower "$b")" = "$l" ] && return 0
  done
  return 1
}

# 폴더 사본: 맥은 APFS 복제(cp -c), 그 밖은 reflink 가 되면 reflink(GNU cp).
clone_tree() {
  if [ "$(uname -s)" = Darwin ]; then /bin/cp -c -R "$1" "$2"; else cp -R --reflink=auto "$1" "$2"; fi
}

# ---------- self-test: 가짜 SDK·가짜 HOME 으로 안전장치를 잰다 ----------
# 진짜 에뮬레이터·adb·~/.android 를 건드리지 않는다: 하위 실행마다 HOME·ANDROID_SDK_ROOT·ANDROID_HOME·EMU_STATE_DIR 를
# 임시 폴더로 덮고 ANDROID_AVD_HOME 을 지운다(또는 임시 폴더로 준다). 봉인(sandbox-exec)은 겹쳐 걸 수 없어 --no-seal 로 띄우고,
# 기본 봉인은 '봉인 프로파일이 없으면 거부'로 잰다. 끝에 가짜 에뮬레이터 PID 가 하나도 살아 있지 않아야 한다.
self_test() {
  local T A A2 P=5682 bad=0 total=0 rc ci casefold
  T="$(mktemp -d "${TMPDIR:-/tmp}/emu-selftest.XXXXXX")" || die "self-test: 임시 폴더를 못 만들었다"
  A="$T/home/.android/avd"; A2="$T/avd2"
  mkdir -p "$T/sdk/emulator" "$T/sdk/platform-tools" "$A" "$A2" "$T/stub" "$T/state" "$T/copy" "$T/callertmp"
  # 가짜 에뮬레이터: 인자와 받은 ANDROID_AVD_HOME·TMPDIR 을 적고 PID 를 남긴 뒤 잠든다.
  # netsim 흉내: 받은 TMPDIR 에 netsim.ini 가 이미 있었는지(지난 실행 찌꺼기) 적고, 자식 하나(가짜 netsimd)를 띄워
  # 그 PID 로 TMPDIR/netsim.ini 를 쓴다. $STUBDIR/netsim-mode 가 foreign 이면 자기 ini 없이 'netsim 에 붙었다' 는 로그만 낸다
  # (남의 netsimd 에 붙은 꼴).
  cat > "$T/sdk/emulator/emulator" <<'STUB'
#!/bin/bash
printf 'ARGS %s AVD_HOME=%s\n' "$*" "${ANDROID_AVD_HOME:-}" >> "$STUBDIR/emu-args"
printf '%s\n' "${TMPDIR:-}" >> "$STUBDIR/emu-tmpdir"
if [ -n "${TMPDIR:-}" ] && [ -e "${TMPDIR%/}/netsim.ini" ]; then echo stale >> "$STUBDIR/netsim-seen"; else echo clean >> "$STUBDIR/netsim-seen"; fi
/bin/sleep 60 </dev/null >/dev/null 2>&1 &
echo $! > "$STUBDIR/child.pid"
if [ "$(cat "$STUBDIR/netsim-mode" 2>/dev/null)" = foreign ]; then
  echo "INFO         | Successfully initialized netsim WiFi"
elif [ -n "${TMPDIR:-}" ]; then
  printf 'pid=%s\ngrpc.port=1\n' "$(cat "$STUBDIR/child.pid")" > "${TMPDIR%/}/netsim.ini"
fi
echo $$ >> "$STUBDIR/launches"
echo $$ > "$STUBDIR/cur.pid"
exec /bin/sleep 60
STUB
  # 가짜 adb: 부른 것을 적는다. 부팅은 곧바로 끝났다고 답하고, emu kill 은 가짜 에뮬레이터(와 자식)를 끈다.
  # 손님 탐침(sealcheck 의 ': aingcheck-probe-*' 표식)은 $STUBDIR/net 의 장면대로 답한다:
  #   sealed(기본) · leak-tcp · leak-dns · dns-timeout · validated · partial · nonai · wifidown · nowlan · nobase
  cat > "$T/sdk/platform-tools/adb" <<'STUB'
#!/bin/bash
echo "adb $*" >> "$STUBDIR/adb-log"
net="$(cat "$STUBDIR/net" 2>/dev/null || echo sealed)"
nai() { # 인터페이스 · 전송 · 능력 — 실기기 dumpsys connectivity 의 NetworkAgentInfo 줄 꼴
  printf '  NetworkAgentInfo{network{100}  handle{1}  ni{%s CONNECTED extra: } lp{{InterfaceName: %s LinkAddresses: [ 10.0.2.16/24 ] }} nc{[ Transports: %s Capabilities: %s LinkUpBandwidth>=1Kbps]}}\n' "$2" "$1" "$2" "$3"
}
case "$*" in
  devices*) echo "List of devices attached" ;;
  *"getprop sys.boot_completed"*) [ -f "$STUBDIR/cur.pid" ] && echo 1 ;;   # 가짜 에뮬레이터가 돈 뒤에야 '부팅 끝' 
  *"emu kill"*) for f in child.pid cur.pid; do [ -f "$STUBDIR/$f" ] && kill "$(cat "$STUBDIR/$f")" 2>/dev/null; rm -f "$STUBDIR/$f"; done ;;
  *"shell echo pong"*) echo pong ;;
  *aingcheck-probe-wlan-link*) [ "$net" = nowlan ] || echo wlan0 ;;
  *aingcheck-probe-wlan-addr*)
    echo "1: lo    inet 127.0.0.1/8 scope host lo"
    echo "15: eth0    inet 10.0.2.15/24 brd 10.0.2.255 scope global eth0"
    [ "$net" = wifidown ] || echo "16: wlan0    inet 10.0.2.16/24 brd 10.0.2.255 scope global wlan0" ;;
  *aingcheck-probe-base*) [ "$net" = nobase ] && echo rc=1 || echo rc=0 ;;
  *aingcheck-probe-out*)
    if [ "$net" = leak-tcp ]; then echo "tcp 1.1.1.1:443 rc=0"; else echo "tcp 1.1.1.1:443 rc=1"; fi
    echo "tcp 8.8.8.8:53 rc=1" ;;
  *aingcheck-probe-dns*)
    case "$net" in
      leak-dns) echo "dns ping: sendmsg: Operation not permitted PING dns.google (8.8.8.8) 56(84) bytes of data. " ;;   # stderr 줄이 앞에 온 꼴
      dns-timeout) echo "dns " ;;
      *) echo "dns ping: unknown host dns.google" ;;
    esac ;;
  *aingcheck-probe-nai*)
    case "$net" in
      nonai) ;;
      validated) nai wlan0 WIFI 'NOT_METERED&INTERNET&NOT_RESTRICTED&TRUSTED&NOT_VPN&VALIDATED&NOT_ROAMING'; nai eth0 CELLULAR 'INTERNET&NOT_RESTRICTED' ;;
      partial) nai wlan0 WIFI 'INTERNET&PARTIAL_CONNECTIVITY&NOT_VPN'; nai eth0 CELLULAR 'INTERNET&NOT_RESTRICTED' ;;
      *) nai wlan0 WIFI 'NOT_METERED&INTERNET&NOT_RESTRICTED&TRUSTED&NOT_VPN&NOT_ROAMING'; nai eth0 CELLULAR 'INTERNET&NOT_RESTRICTED&TRUSTED' ;;
    esac ;;
esac
exit 0
STUB
  chmod +x "$T/sdk/emulator/emulator" "$T/sdk/platform-tools/adb"
  mk_avd() { # 홈 이름 [path= 폴더]
    local home="$1" name="$2" dir="${3:-$1/$2.avd}"
    mkdir -p "$dir"
    [ -e "$dir/config.ini" ] || printf 'AvdId=%s\n' "$name" > "$dir/config.ini"
    printf 'avd.ini.encoding=UTF-8\npath=%s\npath.rel=avd/%s\ntarget=android-36\n' "$dir" "$(basename "$dir")" > "$home/$name.ini"
  }
  mk_avd "$A" aingcheck-api36; mk_avd "$A" aingcheck-api26
  : > "$A/aingcheck-api36.avd/multiinstance.lock"; : > "$A/aingcheck-api36.avd/bootcompleted.ini"
  : > "$A/aingcheck-api36.avd/emu-launch-params.txt"; mkdir -p "$A/aingcheck-api36.avd/tmpAdbCmds"
  mk_avd "$A" lane-a                                   # 보통 갈래 AVD
  mk_avd "$A" lane-alias "$A/aingcheck-api26.avd"      # 다른 이름의 .ini 가 공용 폴더를 가리킨다
  mk_avd "$A" lane-ko; : > "$A/lane-ko.avd/$PROTECT_MARK"   # 준비가 끝나 보호 표식을 단 AVD
  mk_avd "$A2" only2                                   # ANDROID_AVD_HOME 쪽에만 있는 AVD
  mk_avd "$A2" alias2 "$A/aingcheck-api36.avd"         # ANDROID_AVD_HOME 쪽 별칭이 기본 홈의 공용 폴더를 가리킨다
  cp "$SELF" "$T/copy/emu.sh"                          # 옆에 seal.sb 가 없는 사본(기본 봉인 확인용)

  sub() { # 하위 실행 — 진짜 홈·SDK·AVD 폴더를 못 보게 덮는다. TMPDIR 은 '호출자 것'(에뮬레이터가 물려받으면 안 되는 값)으로.
    env -u ANDROID_AVD_HOME HOME="$T/home" ANDROID_SDK_ROOT="$T/sdk" ANDROID_HOME="$T/sdk" EMU_STATE_DIR="$T/state" STUBDIR="$T/stub" \
      TMPDIR="$T/callertmp/" /bin/bash "$@" >>"$T/out.log" 2>&1
  }
  sub2() { # ANDROID_AVD_HOME 을 둘째 폴더로
    env ANDROID_AVD_HOME="$A2" HOME="$T/home" ANDROID_SDK_ROOT="$T/sdk" ANDROID_HOME="$T/sdk" EMU_STATE_DIR="$T/state" STUBDIR="$T/stub" \
      /bin/bash "$@" >>"$T/out.log" 2>&1
  }
  check() { total=$((total + 1)); if [ "$2" = "$3" ]; then echo "self-test: ok   $1"; else echo "self-test: FAIL $1 — 기대 [$2] 실제 [$3]"; bad=$((bad + 1)); fi; }
  fresh() { rm -f "$T/stub/emu-args" "$T/stub/adb-log"; }
  launched() { # 마지막 start 가 가짜 에뮬레이터를 띄웠나: none | ro | rw
    [ -s "$T/stub/emu-args" ] || { echo none; return; }
    tail -n 1 "$T/stub/emu-args" | grep -q -- ' -read-only' && echo ro || echo rw
  }
  stopit() { sub "$SELF" stop --port "$P" --timeout 5; }
  # 같은 파일 시스템에서 대소문자를 가리는가(맥 APFS 는 안 가린다 → 대문자 이름이 공용 폴더로 풀린다).
  # 가리는 곳에서는 대문자 이름 AVD 를 따로 만들어 이름(대소문자 무시) 판정을 잰다.
  if [ -e "$A/AINGCHECK-API36.ini" ]; then casefold=1; else casefold=0; mk_avd "$A" AINGCHECK-API36; mk_avd "$A" Aingcheck-Api26; fi

  # W: --writable 거부 — 거부면 종료 코드 2 이고 에뮬레이터를 띄우지 않는다.
  for ci in aingcheck-api36 aingcheck-api26 AINGCHECK-API36 Aingcheck-Api26 lane-alias lane-ko; do
    fresh; sub "$SELF" start --avd "$ci" --port "$P" --no-seal --writable; rc=$?
    check "writable 거부 '$ci' 종료 코드" 2 "$rc"; check "writable 거부 '$ci' 안 띄움" none "$(launched)"; stopit
  done
  # W: '--' 뒤 에뮬레이터 인자로 여는 AVD·자료를 바꾸는 길도 막는다(쓰기·읽기 모두).
  for ci in "-avd aingcheck-api36" "@aingcheck-api36" "-datadir $A/aingcheck-api36.avd" "-wipe-data"; do
    fresh; sub "$SELF" start --avd lane-a --port "$P" --no-seal --writable -- $ci; rc=$?
    check "에뮬레이터 인자 거부 '-- $ci' 종료 코드" 2 "$rc"; check "에뮬레이터 인자 거부 '-- $ci' 안 띄움" none "$(launched)"; stopit
  done
  fresh; sub "$SELF" start --avd lane-a --port "$P" --no-seal -- -gpu host; rc=$?
  check "그 밖의 에뮬레이터 인자는 그대로 넘김" "0 1" "$rc $(grep -c -- ' -gpu host' "$T/stub/emu-args" 2>/dev/null)"; stopit
  fresh; sub2 "$SELF" start --avd alias2 --port "$P" --no-seal --writable; rc=$?
  check "writable 거부 ANDROID_AVD_HOME 쪽 별칭 'alias2' 종료 코드" 2 "$rc"; check "writable 거부 'alias2' 안 띄움" none "$(launched)"; stopit
  # W: 보통 갈래 AVD 는 쓰기로 뜬다 → -read-only 없음 · 표식 · stop 은 손님 sync 를 emu kill 보다 먼저.
  fresh; sub "$SELF" start --avd lane-a --port "$P" --no-seal --writable; rc=$?
  check "writable 갈래 AVD 종료 코드" 0 "$rc"; check "writable 갈래 AVD 인자" rw "$(launched)"
  check "writable 표식" 1 "$([ -f "$T/state/emu-$P.writable" ] && echo 1 || echo 0)"
  stopit
  check "writable stop: sync 가 emu kill 보다 먼저" "sync kill" \
    "$(grep -E 'shell sync|emu kill' "$T/stub/adb-log" 2>/dev/null | sed -e 's/.*shell sync.*/sync/' -e 's/.*emu kill.*/kill/' | tr '\n' ' ' | sed 's/ $//')"
  check "writable stop 뒤 표식 지움" 0 "$([ -f "$T/state/emu-$P.writable" ] && echo 1 || echo 0)"
  # R: 기본은 -read-only · 창 없음 · stop 에 sync 없음 · 에뮬레이터에 넘긴 ANDROID_AVD_HOME = 본 폴더.
  for ci in aingcheck-api36 lane-ko; do
    fresh; sub "$SELF" start --avd "$ci" --port "$P" --no-seal; rc=$?
    check "기본 '$ci' 종료 코드" 0 "$rc"; check "기본 '$ci' 인자 -read-only" ro "$(launched)"
    check "기본 '$ci' -no-window" 1 "$(grep -c -- ' -no-window ' "$T/stub/emu-args" 2>/dev/null)"
    check "기본 '$ci' ANDROID_AVD_HOME" "AVD_HOME=$A" "$(tail -n 1 "$T/stub/emu-args" 2>/dev/null | sed 's/.* AVD_HOME=/AVD_HOME=/')"
    stopit; check "기본 '$ci' stop 에 sync 없음" 0 "$(grep -c 'shell sync' "$T/stub/adb-log" 2>/dev/null)"
  done
  fresh; sub2 "$SELF" start --avd only2 --port "$P" --no-seal; rc=$?
  check "ANDROID_AVD_HOME 쪽 AVD 종료 코드" 0 "$rc"
  check "ANDROID_AVD_HOME 을 그대로 넘김" "AVD_HOME=$A2" "$(tail -n 1 "$T/stub/emu-args" 2>/dev/null | sed 's/.* AVD_HOME=/AVD_HOME=/')"
  stopit
  fresh; sub2 "$SELF" start --avd lane-a --port "$P" --no-seal; rc=$?
  check "ANDROID_AVD_HOME 밖(기본 홈)의 AVD 는 없다고 거부" 2 "$rc"; stopit
  # S: 봉인이 기본이다 — 봉인 프로파일이 없는 사본은 --no-seal 없이 띄우지 않는다(2). 없는 --seal 경로도 거부.
  fresh; sub "$T/copy/emu.sh" start --avd lane-a --port "$P"; rc=$?
  check "기본 봉인: 프로파일 없으면 거부" 2 "$rc"; check "기본 봉인: 안 띄움" none "$(launched)"; stopit
  fresh; sub "$SELF" start --avd lane-a --port "$P" --seal "$T/nope.sb"; rc=$?
  check "없는 --seal 거부" 2 "$rc"; stopit
  # C: avd-clone — 실행 중 표식·보호 표식은 옮기지 않고, 원본은 그대로.
  sub "$SELF" avd-clone --from aingcheck-api36 --to clone1; rc=$?
  check "avd-clone 종료 코드" 0 "$rc"
  check "avd-clone path=" 1 "$(grep -cx "path=$A/clone1.avd" "$A/clone1.ini" 2>/dev/null)"
  check "avd-clone 실행 중 표식 안 옮김" 0 "$(ls -A "$A/clone1.avd" 2>/dev/null | grep -c -E '\.lock$|^bootcompleted\.ini$|^tmpAdbCmds$|^emu-launch-params\.txt$')"
  check "avd-clone 원본 표식 그대로" 1 "$(ls -A "$A/aingcheck-api36.avd" | grep -c '^multiinstance\.lock$')"
  sub "$SELF" avd-clone --from lane-ko --to clone2; rc=$?
  check "avd-clone 보호된 원본 종료 코드" 0 "$rc"
  check "avd-clone 보호 표식 안 옮김" 0 "$(ls -A "$A/clone2.avd" 2>/dev/null | grep -c -F "$PROTECT_MARK")"
  check "avd-clone 원본 보호 표식 그대로" 1 "$(ls -A "$A/lane-ko.avd" | grep -c -F "$PROTECT_MARK")"
  fresh; sub "$SELF" start --avd clone2 --port "$P" --no-seal --writable; rc=$?
  check "보호된 AVD 의 사본은 쓰기로 뜬다" "0 rw" "$rc $(launched)"; stopit
  for ci in clone1 CLONE1 aingcheck-api36 AINGCHECK-API26 'bad name' .hid ../x a/b; do
    sub "$SELF" avd-clone --from lane-a --to "$ci"; rc=$?
    check "avd-clone 거부 --to '$ci'" 2 "$rc"
  done
  sub "$SELF" avd-clone --from nosuch --to clone3; check "avd-clone 없는 원본 거부" 2 "$?"
  sub "$SELF" avd-clone --from lane-a --to LANE-A; check "avd-clone 같은 이름(대소문자 무시) 거부" 2 "$?"
  # 공용 AVD 가 없는 AVD 홈에서도 공용 이름으로는 만들지 않는다(어느 홈에서든 그 이름은 공용 AVD 를 뜻한다).
  sub2 "$SELF" avd-clone --from only2 --to AINGCHECK-API36; check "avd-clone 공용 이름 거부(공용이 없는 홈)" 2 "$?"
  check "avd-clone 공용 이름 사본 안 만듦" 0 "$(ls -A "$A2" | grep -ci 'aingcheck-api36')"
  # P: avd-protect — 표식을 달면 --writable 거부, 공용 AVD(이름·별칭)에는 쓰지 않는다.
  sub "$SELF" avd-protect --avd lane-a; rc=$?
  check "avd-protect 종료 코드" 0 "$rc"; check "avd-protect 표식" 1 "$([ -f "$A/lane-a.avd/$PROTECT_MARK" ] && echo 1 || echo 0)"
  fresh; sub "$SELF" start --avd lane-a --port "$P" --no-seal --writable; rc=$?
  check "avd-protect 뒤 writable 거부" "2 none" "$rc $(launched)"; stopit
  for ci in aingcheck-api36 lane-alias nosuch; do
    sub "$SELF" avd-protect --avd "$ci"; rc=$?
    check "avd-protect 거부 '$ci'" 2 "$rc"
  done
  check "공용 폴더에 표식 없음" 0 "$(ls -A "$A/aingcheck-api36.avd" "$A/aingcheck-api26.avd" | grep -c -F "$PROTECT_MARK")"

  # N: 전용 netsim 발견 폴더(G §8-17 5) — 에뮬레이터는 호출자 TMPDIR 이 아니라 <상태>/netsim-<포트>/ 를 받는다(남의 netsim.ini 를
  #    못 보게). 그 폴더는 띄울 때마다 비우고(지난 실행 찌꺼기), 다 내려가면 지운다.
  subo() { # 하위 실행, 표준출력을 $1 파일로(나머지는 out.log). 앞에 붙인 환경 변수는 그대로 물려준다.
    local o="$1"; shift
    env -u ANDROID_AVD_HOME HOME="$T/home" ANDROID_SDK_ROOT="$T/sdk" ANDROID_HOME="$T/sdk" EMU_STATE_DIR="$T/state" STUBDIR="$T/stub" \
      TMPDIR="$T/callertmp/" /bin/bash "$@" >"$o" 2>>"$T/out.log"
  }
  mkdir -p "$T/state/netsim-$P"; printf 'pid=1\n' > "$T/state/netsim-$P/netsim.ini"
  rm -f "$T/stub/netsim-mode" "$T/stub/emu-tmpdir" "$T/stub/netsim-seen"; echo sealed > "$T/stub/net"
  fresh; sub "$SELF" start --avd lane-a --port "$P" --no-seal; rc=$?
  check "netsim: start 종료 코드" 0 "$rc"
  check "netsim: 에뮬레이터 TMPDIR = 전용 폴더(호출자 TMPDIR 아님)" "$T/state/netsim-$P/" "$(tail -n 1 "$T/stub/emu-tmpdir" 2>/dev/null)"
  check "netsim: 띄울 때 찌꺼기 netsim.ini 를 비움" clean "$(tail -n 1 "$T/stub/netsim-seen" 2>/dev/null)"
  # S: sealcheck 판정 — 가짜 adb 가 손님 탐침에 장면대로 답한다(실기기 판정은 gate-full · 결함 심기 실측). 기다림은 짧게.
  sc() { # 장면 → "종료코드 verdict"
    echo "$1" > "$T/stub/net"
    EMU_NET_TIMEOUT=2 EMU_PROBE_GAP=0 subo "$T/sc.out" "$SELF" sealcheck --port "$P"; local r=$?
    echo "$r $(sed -n 's/.* verdict=//p' "$T/sc.out")"
  }
  check "sealcheck 봉인(자기 netsim · Wi-Fi 주소 · 기준선)" "0 sealed" "$(sc sealed)"
  check "sealcheck netsim=own 근거" 1 "$(grep -c "netsim=own:$(cat "$T/stub/child.pid" 2>/dev/null) " "$T/sc.out")"
  check "sealcheck 바깥 TCP 열림" "1 LEAK-OR-UNMEASURED(tcp-open)" "$(sc leak-tcp)"
  check "sealcheck DNS 풀림" "1 LEAK-OR-UNMEASURED(dns-resolved)" "$(sc leak-dns)"
  check "sealcheck DNS 답 없음(잰 것 없음)" "1 LEAK-OR-UNMEASURED(dns-unknown probes=6/7)" "$(sc dns-timeout)"
  check "sealcheck 망 VALIDATED" "1 LEAK-OR-UNMEASURED(validated)" "$(sc validated)"
  check "sealcheck VALIDATED 망 이름" 1 "$(grep -c 'validated=\[wlan0\]' "$T/sc.out")"
  check "sealcheck 망 PARTIAL_CONNECTIVITY" "1 LEAK-OR-UNMEASURED(validated)" "$(sc partial)"
  check "sealcheck 망 목록 없음(판정 비어 있음)" "1 LEAK-OR-UNMEASURED(no-networks)" "$(sc nonai)"
  check "sealcheck Wi-Fi 주소 없음(netsim 길을 못 잼)" "1 LEAK-OR-UNMEASURED(wifi-down)" "$(sc wifidown)"
  check "sealcheck 기준선(손님 → 호스트 루프백) 실패" "1 LEAK-OR-UNMEASURED(baseline)" "$(sc nobase)"
  check "sealcheck wlan0 없는 기기는 Wi-Fi 기다림 없음" "0 sealed" "$(sc nowlan)"
  echo sealed > "$T/stub/net"
  printf 'pid=1\ngrpc.port=1\n' > "$T/state/netsim-$P/netsim.ini"   # 전용 폴더의 ini 가 나무 밖 PID 를 가리킨다
  check "sealcheck netsim.ini 가 남의 PID" "1 LEAK-OR-UNMEASURED(netsim)" "$(sc sealed)"
  EMU_PROBE_ROUNDS=0 subo "$T/sc.out" "$SELF" sealcheck --port "$P"; check "sealcheck 측정 0번 거부" 2 "$?"
  # W2: 창 판정(G §8-6) — 이 포트 PID 나무(자손 포함)의 창만 센다. 가짜 창 목록(EMU_FAKE_WINDOWS)으로 판정 함수를 잰다.
  cur="$(cat "$T/stub/cur.pid" 2>/dev/null)"; kid="$(cat "$T/stub/child.pid" 2>/dev/null)"
  printf '1\tqemu-system-aarch64\n1\temulator\n' > "$T/win-foreign"
  printf '1\tqemu-system-aarch64\n%s\tqemu-system-aarch64-headless\n' "$cur" > "$T/win-own"
  printf '%s\tnetsimd\n' "$kid" > "$T/win-child"
  : > "$T/win-empty"
  wn() { EMU_FAKE_WINDOWS="$1" subo "$T/wn.out" "$SELF" windows --port "$P"; local r=$?
    echo "$r $(sed -n 's/^windows_own=\([^ ]*\) windows_foreign_emulator=\([0-9?]*\).*/own=\1 foreign=\2/p' "$T/wn.out")"; }
  check "windows 남의 에뮬레이터 창만 → 판정 밖" "0 own=0 foreign=2" "$(wn "$T/win-foreign")"
  check "windows 자기 PID 의 창" "1 own=1 foreign=1" "$(wn "$T/win-own")"
  check "windows 자손(가짜 netsimd) 의 창" "1 own=1 foreign=0" "$(wn "$T/win-child")"
  check "windows 창 없음" "0 own=0 foreign=0" "$(wn "$T/win-empty")"
  fresh; EMU_FAKE_WINDOWS="$T/win-empty" sub "$SELF" instrumented --avd lane-a --port "$P" --no-seal; rc=$?
  check "instrumented 는 가짜 창 목록 거부" "2 none" "$rc $(launched)"
  stopit
  check "netsim: 다 내려간 뒤 전용 폴더 지움" 0 "$([ -e "$T/state/netsim-$P" ] && echo 1 || echo 0)"
  check "windows 자기 PID 없음 → 판정 불가" 1 "$(wn "$T/win-empty" | cut -d' ' -f1)"
  # N: 남의 netsimd 에 붙은 꼴(자기 ini 없이 로그만 'netsim WiFi')이면 sealcheck 빨강.
  echo foreign > "$T/stub/netsim-mode"
  fresh; sub "$SELF" start --avd lane-a --port "$P" --no-seal; rc=$?
  check "netsim foreign: start 종료 코드" 0 "$rc"
  check "sealcheck 남의 netsimd 에 붙음" "1 LEAK-OR-UNMEASURED(netsim)" "$(sc sealed)"
  stopit; rm -f "$T/stub/netsim-mode"

  # 끝: 가짜 에뮬레이터가 살아 있지 않아야 한다 — 마지막으로 띄운 것(cur.pid 는 emu kill 이 지운다)과 emu.sh procs 로 센다.
  local alive=0 p
  if [ -f "$T/stub/cur.pid" ]; then
    p="$(cat "$T/stub/cur.pid")"
    if kill -0 "$p" 2>/dev/null && [ "$(ps -o comm= -p "$p" 2>/dev/null | sed 's#.*/##')" = sleep ]; then alive=1; kill -KILL "$p" 2>/dev/null; fi
  fi
  check "남은 가짜 에뮬레이터 0(cur.pid)" 0 "$alive"
  alive=0
  if [ -f "$T/stub/child.pid" ]; then
    p="$(cat "$T/stub/child.pid")"
    if kill -0 "$p" 2>/dev/null && [ "$(ps -o comm= -p "$p" 2>/dev/null | sed 's#.*/##')" = sleep ]; then alive=1; kill -KILL "$p" 2>/dev/null; fi
  fi
  check "남은 가짜 netsimd 0(child.pid)" 0 "$alive"
  sub "$SELF" procs --port "$P"; check "emu.sh procs 0" 0 "$?"
  echo "self-test: 사례 $total · 실패 $bad · 대소문자 무시 파일 시스템=$casefold · 띄운 가짜 에뮬레이터 $(grep -c . "$T/stub/launches" 2>/dev/null || echo 0)"
  if [ "$bad" -ne 0 ]; then echo "self-test: 하위 실행 로그 끝:"; tail -n 30 "$T/out.log"; fi
  rm -rf "$T"
  [ "$bad" -eq 0 ]
}

# 포트가 필요 없는 명령.
if [ "$cmd" = "self-test" ]; then
  self_test
  exit $?
elif [ "$cmd" = "avd-protect" ]; then
  valid_avd_name "$AVD" || die "--avd 가 AVD 이름이 아니다: '$AVD'"
  [ -f "$AVD_HOME/$AVD.ini" ] || die "AVD 가 없다: $AVD"
  if is_shared_name "$AVD" || resolves_to_shared "$AVD"; then
    die "공용 AVD($AVD)는 이름·폴더로 이미 보호된다 — 공용 폴더에 표식을 쓰지 않는다"
  fi
  marked=0; done_dirs=()
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    dup=0; for e in ${done_dirs[@]+"${done_dirs[@]}"}; do [ "$d" -ef "$e" ] && dup=1; done
    [ "$dup" -eq 0 ] || continue
    done_dirs+=("$d")
    printf '%s\n' "보호: emu.sh start --writable 거부 (emu.sh avd-protect, $(date -u +%Y-%m-%dT%H:%M:%SZ)). 풀려면 이 파일을 손으로 지운다." > "$d/$PROTECT_MARK" || die "표식을 못 썼다: $d"
    echo "avd-protect avd=$AVD mark=$d/$PROTECT_MARK"
    marked=$((marked + 1))
  done < <(avd_dirs "$AVD")
  [ "$marked" -gt 0 ] || die "AVD 폴더를 못 찾았다: $AVD"
  exit 0
elif [ "$cmd" = "avd-clone" ]; then
  valid_avd_name "$FROM" || die "--from 이 AVD 이름이 아니다: '$FROM'"
  valid_avd_name "$TO" || die "--to 가 AVD 이름이 아니다(영숫자·._- 만): '$TO'"
  [ "$(lower "$FROM")" != "$(lower "$TO")" ] || die "--from 과 --to 가 같다(대소문자 무시)"
  ! is_shared_name "$TO" || die "--to 가 공용 AVD 이름이다(대소문자 무시): $TO"
  src="$(avd_dirs "$FROM" | head -n 1)"
  [ -f "$AVD_HOME/$FROM.ini" ] && [ -n "$src" ] || die "원본 AVD 가 없다: $FROM"
  ! avd_name_taken "$TO" && [ ! -e "$AVD_HOME/$TO.ini" ] && [ ! -e "$AVD_HOME/$TO.avd" ] \
    || die "대상 AVD 가 이미 있다(대소문자 무시): $TO (지우고 다시 만들려면 손으로 지운다)"
  clone_tree "$src" "$AVD_HOME/$TO.avd" || { rm -rf "$AVD_HOME/$TO.avd"; die "사본 실패: $FROM → $TO"; }
  # 실행 중 표식은 원본의 것이다 — 사본에 남기면 에뮬레이터가 '이미 실행 중'으로 본다.
  # 보호 표식도 옮기지 않는다 — 사본은 다시 준비(--writable)할 수 있어야 한다.
  find "$AVD_HOME/$TO.avd" -maxdepth 1 \( -name '*.lock' -o -name 'bootcompleted.ini' -o -name 'emu-launch-params.txt' -o -name "$PROTECT_MARK" \) -exec rm -f {} +
  rm -rf "$AVD_HOME/$TO.avd/tmpAdbCmds"
  /usr/bin/sed -e "s#^path=.*#path=$AVD_HOME/$TO.avd#" -e "s#^path\.rel=.*#path.rel=avd/$TO.avd#" "$AVD_HOME/$FROM.ini" > "$AVD_HOME/$TO.ini"
  grep -qx "path=$AVD_HOME/$TO.avd" "$AVD_HOME/$TO.ini" || { rm -rf "$AVD_HOME/$TO.avd" "$AVD_HOME/$TO.ini"; die "$TO.ini 의 path 를 못 고쳤다"; }
  echo "avd-clone from=$FROM to=$TO dir=$AVD_HOME/$TO.avd files=$(find "$AVD_HOME/$TO.avd" -type f | wc -l | tr -d ' ')"
  exit 0
fi

[ -n "$PORT" ] || die "--port 가 필요하다(갈래별 5560+2k)"
case "$PORT" in *[!0-9]*) die "포트는 숫자: $PORT" ;; esac
[ "$PORT" -ge 5554 ] && [ "$PORT" -le 5682 ] && [ $((PORT % 2)) -eq 0 ] || die "포트는 5554..5682 의 짝수: $PORT"

SERIAL="emulator-$PORT"
PIDFILE="$STATE/emu-$PORT.pid"     # 첫 줄: 띄운 PID(sandbox-exec 가 exec 한 emulator), 둘째 줄부터: 자식 PID. 끈 뒤에도 남겨 procs 로 다시 센다
WRITABLE_MARK="$STATE/emu-$PORT.writable"   # --writable 로 띄웠다는 표식(stop 이 손님 sync 를 먼저 부른다)
LOGFILE="$STATE/emu-$PORT.log"
# 이 포트 에뮬레이터 전용 netsim 발견 폴더(에뮬레이터의 TMPDIR). 에뮬레이터는 TMPDIR 의 netsim.ini 로 떠 있는 netsimd 를 찾아
# 붙는다 — 기본 TMPDIR 을 물려주면 남이 띄운(봉인 안 된) netsimd 에 localhost 로 붙어 Wi-Fi 로 바깥이 열린다(int-e 실측,
# 'Successfully initialized netsim WiFi' dns:///localhost:52001). 전용 폴더를 주면 에뮬레이터가 자기 netsimd 를 자식으로 띄우고,
# 그 netsimd 는 같은 봉인을 물려받는다(G §8-17 5).
NETSIM_DIR="$STATE/netsim-$PORT"
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

# 창 목록: 한 줄에 "주인PID<탭>주인 이름"(CGWindowList, 화면 밖 포함 전부).
# EMU_FAKE_WINDOWS(자기 시험 전용 — 같은 꼴의 파일 경로)가 있으면 그 파일을 읽는다. instrumented 는 이 변수가 있으면 거부한다.
window_list() {
  if [ -n "${EMU_FAKE_WINDOWS:-}" ]; then cat "$EMU_FAKE_WINDOWS"; return; fi
  /usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import("CoreGraphics");
function run() {
  var arr = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll, 0))) || [];
  return arr.map(function (w) {
    return String(w.kCGWindowOwnerPID) + "\t" + String(w.kCGWindowOwnerName || "").replace(/[\t\n]/g, " ");
  }).join("\n");
}
JXA
}

# 창 판정(G §8-6 · §8-17 5): **이 포트로 띄운 PID 나무(자손 포함)가 가진 창만** 센다 → "own foreign".
# foreign = 나무 밖인데 이름이 qemu/emulator 인 창(남의 에뮬레이터) — 알림으로만 찍고 판정에 넣지 않는다.
window_count() {
  window_list | /usr/bin/awk -F '\t' -v pids="$1" '
    BEGIN { n = split(pids, a, " "); for (i = 1; i <= n; i++) if (a[i] != "") want[a[i]] = 1; own = 0; foreign = 0 }
    NF >= 1 && $1 != "" {
      if ($1 in want) own++
      else if (tolower($2) ~ /qemu-system|^emulator$/) foreign++
    }
    END { print own, foreign }'
}

case "$cmd" in
start)
  [ -n "$AVD" ] || die "--avd 가 필요하다"
  [ -x "$EMU_BIN" ] || die "에뮬레이터가 없다: $EMU_BIN"
  [ -f "$AVD_HOME/$AVD.ini" ] || die "AVD 가 없다: $AVD ($AVD_HOME/$AVD.ini)"
  for x in ${EXTRA[@]+"${EXTRA[@]}"}; do
    case "$x" in
      -avd|@*|-datadir|-data|-initdata|-sysdir|-wipe-data|-writable-system)
        die "에뮬레이터 인자 '$x' 는 받지 않는다 — 여는 AVD·자료는 --avd 와 --writable 로만 정한다(판정을 비켜 가는 길)" ;;
    esac
  done
  if [ "$WRITABLE" -eq 1 ]; then
    why="$(writable_block_reason "$AVD")"
    [ -z "$why" ] || die "--writable 거부: $AVD — $why. 쓰기로는 avd-clone 으로 만든 (보호 표식 없는) 갈래 전용 AVD 만 띄운다"
  fi
  if [ -f "$PIDFILE" ] && [ "$(alive_count)" -gt 0 ]; then die "포트 $PORT 에 이미 띄운 에뮬레이터가 있다(PID $(head -1 "$PIDFILE"))"; fi
  if "$ADB" devices 2>/dev/null | awk '{print $1}' | grep -qx "$SERIAL"; then die "$SERIAL 를 이미 누가 쓰고 있다 — 다른 포트를 써라"; fi
  "$ADB" start-server >/dev/null 2>&1 || die "adb 서버를 못 띄웠다"

  args=( -avd "$AVD" -port "$PORT" -no-window -no-audio -no-boot-anim -no-snapshot
         -no-metrics -gpu swiftshader_indirect )
  if [ "$WRITABLE" -eq 1 ]; then : > "$WRITABLE_MARK"; else args+=( -read-only ); rm -f "$WRITABLE_MARK"; fi
  [ ${#EXTRA[@]} -gt 0 ] && args+=( "${EXTRA[@]}" )
  launcher=()
  if [ "$SEALED" -eq 1 ]; then
    [ -f "$SEAL" ] || die "봉인 프로파일이 없다: $SEAL (--seal 경로 또는 --no-seal)"
    launcher=( /usr/bin/sandbox-exec -f "$SEAL" )
  fi
  : > "$LOGFILE"
  # 전용 netsim 발견 폴더는 띄울 때마다 비운다(지난 실행의 netsim.ini 가 죽은 PID·포트를 가리키지 않게).
  rm -rf "$NETSIM_DIR" && mkdir -p "$NETSIM_DIR" || die "netsim 발견 폴더를 못 만들었다: $NETSIM_DIR"
  # 에뮬레이터가 여는 AVD 폴더 = 위에서 판정한 폴더(ANDROID_AVD_HOME 을 같은 값으로 넘긴다).
  export ANDROID_AVD_HOME="$AVD_HOME"
  t0=$(date +%s)
  # 새 세션으로 떼어 낸다(부른 셸이 끝나도 산다). PID 는 env → sandbox-exec → exec → emulator 로 같다.
  # TMPDIR 은 에뮬레이터(와 그 자식 netsimd)에게만 전용 폴더로 준다 — 남의 netsim.ini 를 못 보게.
  /usr/bin/perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec: $!"' -- \
    /usr/bin/env TMPDIR="$NETSIM_DIR/" ${launcher[@]+"${launcher[@]}"} "$EMU_BIN" "${args[@]}" </dev/null >>"$LOGFILE" 2>&1 &
  pid=$!
  echo "$pid" > "$PIDFILE"
  log "띄움 avd=$AVD port=$PORT sealed=$SEALED writable=$WRITABLE pid=$pid log=$LOGFILE"

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
  echo "boot=ok seconds=$((t1 - t0)) serial=$SERIAL pid=$pid sealed=$SEALED writable=$WRITABLE"
  ;;

stop)
  if [ ! -f "$PIDFILE" ] || [ "$(alive_count)" -eq 0 ]; then rm -f "$WRITABLE_MARK"; echo "stopped alive=0 (띄운 것 없음)"; exit 0; fi
  if [ -f "$WRITABLE_MARK" ]; then
    # 쓰기로 띄운 AVD: 손님 페이지 캐시를 가상 디스크로 내린 뒤 끈다(시한 20초 — 손님이 멎었어도 stop 은 끝난다).
    /usr/bin/perl -e 'alarm shift; exec @ARGV or exit 127' 20 "$ADB" -s "$SERIAL" shell sync >/dev/null 2>&1
    log "writable: 손님 sync rc=$?"
    rm -f "$WRITABLE_MARK"
  fi
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
  [ "$n" -ne 0 ] || rm -rf "$NETSIM_DIR"   # 자기 netsimd 까지 내려갔으면 전용 발견 폴더도 거둔다
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
  src=cgwindowlist; [ -z "${EMU_FAKE_WINDOWS:-}" ] || src=fake
  if [ -z "${pids// /}" ]; then
    # 자기 PID 가 없으면 '창 0' 은 아무것도 재지 않은 것이다(빈 판정) — 초록으로 치지 않는다.
    echo "windows_own=? windows_foreign_emulator=? pids=[] source=$src — 포트 $PORT 로 띄운 살아 있는 프로세스가 없다(판정 불가)"
    exit 1
  fi
  read -r own foreign <<<"$(window_count "$pids")"
  echo "windows_own=$own windows_foreign_emulator=$foreign(판정 밖 — 남의 PID) pids=[${pids% }] source=$src"
  [ "$own" = "0" ]
  ;;

sealcheck)
  # 봉인 확인(G §8-17 5). 부팅 직후의 손님에는 lo 밖 주소가 없다 — 그때 재면 '막힘'은 길이 없어서다(int-e 의 rc=1 이 그랬다).
  # 그래서 (1) 호스트 쪽: 에뮬레이터가 붙은 netsimd 가 자기 PID 나무 안인가, (2) 손님 Wi-Fi(wlan0 = netsim 길)가 주소를 받고
  # 손님 → 10.0.2.2:<콘솔 포트>(호스트 루프백, 봉인이 여는 길)가 붙을 때까지 기다린 뒤(기준선), (3) 바깥 TCP 둘·DNS 풀이를
  # 여러 번 재고, (4) 안드로이드가 '인터넷 됨'(VALIDATED·PARTIAL_CONNECTIVITY)으로 본 망이 없는지 본다. 넷 다 맞아야 0.
  [ -f "$PIDFILE" ] && [ "$(alive_count)" -gt 0 ] || die "포트 $PORT 에 띄운 에뮬레이터가 없다"
  NET_TIMEOUT="${EMU_NET_TIMEOUT:-120}"; ROUNDS="${EMU_PROBE_ROUNDS:-3}"; GAP="${EMU_PROBE_GAP:-5}"
  for v in "$NET_TIMEOUT" "$ROUNDS" "$GAP"; do case "$v" in ''|*[!0-9]*) die "EMU_NET_TIMEOUT·EMU_PROBE_ROUNDS·EMU_PROBE_GAP 는 숫자: '$v'" ;; esac; done
  [ "$ROUNDS" -ge 1 ] || die "EMU_PROBE_ROUNDS 는 1 이상(0 이면 아무것도 재지 않는다)"
  gsh() { "$ADB" -s "$SERIAL" shell "$1" 2>/dev/null | tr -d '\r'; }
  bad=()
  pong="$(gsh 'echo pong')"
  [ "$pong" = "pong" ] || bad+=("adb")
  # (1) netsim 주인: 전용 발견 폴더의 netsim.ini 가 가리키는 netsimd 가 이 포트 PID 나무 안이어야 한다.
  ns_ini="$NETSIM_DIR/netsim.ini"; ns_pid=""
  [ -f "$ns_ini" ] && ns_pid="$(sed -n 's/^pid=//p' "$ns_ini" | head -n 1 | tr -dc '0-9')"
  # (grep -q 를 파이프 끝에 두지 않는다 — pipefail 아래에서 앞 단계가 SIGPIPE 로 끝나 '없음'이 된다.)
  if [ -n "$ns_pid" ] && [ "$(tree_pids | grep -cx "$ns_pid")" -gt 0 ]; then netsim="own:$ns_pid"
  elif [ -f "$ns_ini" ]; then netsim="foreign:ini-pid=${ns_pid:-?}"; bad+=("netsim")   # 전용 폴더의 ini 가 나무 밖(또는 없는) PID
  elif grep -q -E 'netsim|packet streamer' "$LOGFILE" 2>/dev/null; then netsim="foreign:no-own-ini"; bad+=("netsim")   # 로그엔 netsim 이 붙었는데 자기 것이 아니다
  else netsim="none"; fi
  # (2) 길 기다리기: wlan0 이 있으면 IPv4 를 받을 때까지, 그리고 손님 → 호스트 루프백(콘솔)이 붙을 때까지.
  t0=$(date +%s); wifi="absent"; base="down"
  # (셸 사용자는 'ip link show <장치>' 가 netlink 권한으로 막힌다 — 장치 있음은 /sys, 주소는 전체 목록에서 고른다.)
  if [ "$(gsh ': aingcheck-probe-wlan-link; [ -e /sys/class/net/wlan0 ] && echo wlan0')" = "wlan0" ]; then
    wifi="down"
    while :; do
      a="$(gsh ': aingcheck-probe-wlan-addr; ip -4 -o addr 2>/dev/null' | awk '$2 == "wlan0" {for (i=3;i<=NF;i++) if ($i=="inet") {print $(i+1); exit}}')"
      [ -n "$a" ] && { wifi="up:$a"; break; }
      [ $(( $(date +%s) - t0 )) -lt "$NET_TIMEOUT" ] || break
      sleep 2
    done
    case "$wifi" in up:*) ;; *) bad+=("wifi-down") ;; esac
  fi
  while :; do
    r="$(gsh ": aingcheck-probe-base; toybox nc -w 5 10.0.2.2 $PORT </dev/null >/dev/null 2>&1; echo rc=\$?")"
    [ "$r" = "rc=0" ] && { base="connected"; break; }
    [ $(( $(date +%s) - t0 )) -lt "$NET_TIMEOUT" ] || break
    sleep 2
  done
  [ "$base" = "connected" ] || bad+=("baseline")
  # (3) 바깥 TCP(1.1.1.1:443 · 8.8.8.8:53)를 ROUNDS 번(GAP 초 간격), 첫 번째 뒤에 DNS 풀이(손님 기본 망의 DNS) 한 번.
  #     한 번이라도 열리거나 풀리면 샌다. DNS 는 막히면 손님 resolver 가 시한(실측 30초)까지 기다려 'unknown host' 를 낸다 —
  #     60초 안에 답이 없으면 잰 것이 없다(빨강). 기대 측정 수 = ROUNDS×2 + 1.
  tcp_open=0; dns_res=0; dns_odd=0; probes=0
  for ((i = 1; i <= ROUNDS; i++)); do
    out="$(gsh ': aingcheck-probe-out; for t in 1.1.1.1:443 8.8.8.8:53; do toybox nc -w 5 ${t%:*} ${t#*:} </dev/null >/dev/null 2>&1; echo "tcp $t rc=$?"; done')"
    # ping 의 표준출력은 파이프에서 덩어리 버퍼라 stderr 줄(sendmsg 실패 등)이 'PING 이름 (주소)' 보다 먼저 올 수 있다 — 출력 전부를 한 줄로.
    [ "$i" -eq 1 ] && out="$out"$'\n'"$(gsh ': aingcheck-probe-dns; echo "dns $(timeout 60 ping -c 1 -W 3 dns.google 2>&1 | tr "\n" " ")"')"
    while IFS= read -r l; do
      case "$l" in
        "tcp "*" rc=0") tcp_open=$((tcp_open + 1)); probes=$((probes + 1)) ;;
        "tcp "*" rc="[1-9]*) probes=$((probes + 1)) ;;
        "dns "*"PING "*" ("*) dns_res=$((dns_res + 1)); probes=$((probes + 1)) ;;   # 이름이 주소로 풀렸다(먼저 본다)
        "dns "*"unknown host"*) probes=$((probes + 1)) ;;
        "dns "*) dns_odd=$((dns_odd + 1)) ;;
      esac
    done <<<"$out"
    [ "$i" -lt "$ROUNDS" ] && sleep "$GAP"
  done
  [ "$tcp_open" -eq 0 ] || bad+=("tcp-open")
  [ "$dns_res" -eq 0 ] || bad+=("dns-resolved")
  [ "$dns_odd" -eq 0 ] || bad+=("dns-unknown")
  [ "$probes" -eq $((ROUNDS * 2 + 1)) ] || bad+=("probes=$probes/$((ROUNDS * 2 + 1))")
  # (4) 망마다 안드로이드 자체 검사(NetworkMonitor — 망에 묶어 DNS·HTTP 를 잰다)가 '인터넷 됨'으로 본 망.
  nai="$(gsh ': aingcheck-probe-nai; dumpsys connectivity 2>/dev/null | grep "^  NetworkAgentInfo"')"
  nets=0; validated=""
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    nets=$((nets + 1))
    ifc="$(printf '%s' "$l" | sed -n 's/.*InterfaceName: \([A-Za-z0-9_.-]*\).*/\1/p' | head -n 1)"
    # 줄 안의 Capabilities 묶음을 모두 낱말로 쪼개 정확히 맞춘다(NOT_ 꼴 같은 비슷한 이름에 걸리지 않게).
    toks="$(printf '%s\n' "$l" | grep -o 'Capabilities: [A-Z_&]*' | sed 's/^Capabilities: //' | tr '&' '\n')"
    if [ "$(printf '%s\n' "$toks" | grep -cx -E 'VALIDATED|PARTIAL_CONNECTIVITY')" -gt 0 ]; then validated="$validated${validated:+,}${ifc:-?}"; fi
  done <<<"$nai"
  [ "$nets" -ge 1 ] || bad+=("no-networks")
  [ -z "$validated" ] || bad+=("validated")
  echo "adb=${pong:-dead} netsim=$netsim wifi=$wifi host_loopback_via_guest=$base outbound_tcp_open=$tcp_open dns_resolved=$dns_res probes=$probes rounds=$ROUNDS networks=$nets validated=[${validated}] waited=$(( $(date +%s) - t0 ))s verdict=$([ ${#bad[@]} -eq 0 ] && echo sealed || echo "LEAK-OR-UNMEASURED(${bad[*]})")"
  [ ${#bad[@]} -eq 0 ]
  ;;

procs)
  n="$(alive_count)"
  echo "alive=$n pids=[$(tree_pids | sort -u | tr '\n' ' ' | sed 's/ $//')]"
  [ "$n" -eq 0 ]
  ;;

avd-prepare-ko)
  # E-U5 한국어 조합 AVD 를 처음부터 만든다(머리말 '갈래 전용 AVD' 의 1~5). 실패하면 만든 AVD 를 남기고(사람이 볼 수 있게) 1.
  [ -n "$TO" ] || die "--to 가 필요하다(새 AVD 이름)"
  PY="$(command -v python3 || true)"; [ -n "$PY" ] || die "uiautomator 화면을 읽을 python3 가 없다"
  GB_PKG="com.google.android.inputmethod.latin"
  GB_IME="$GB_PKG/com.android.inputmethod.latin.LatinIME"
  GB_SETTINGS="$GB_PKG/com.google.android.apps.inputmethod.latin.preference.SettingsActivity"
  KO_SUBTYPE="-1906255757"   # Gboard 한국어 두벌식(ko_KR)
  sh_adb() { "$ADB" -s "$SERIAL" "$@"; }
  # ui MODE 정규식 [시한초]: uiautomator 덤프에서 글자(text·content-desc)가 맞는 첫 노드를 찾는다.
  #   tap = 가운데를 누름 · wait = 있으면 0 · attr:<이름> = 그 속성 값을 냄 · edit = 첫 EditText 의 글자를 냄(정규식 무시).
  ui() {
    "$PY" -I - "$ADB" "$SERIAL" "$@" <<'UIPY'
import re, subprocess, sys, time
import xml.etree.ElementTree as ET
adb, serial, mode, pat = sys.argv[1:5]
limit = float(sys.argv[5]) if len(sys.argv) > 5 else 20.0
rx = re.compile(pat)
def dump():
    for _ in range(5):
        subprocess.run([adb, "-s", serial, "shell", "uiautomator", "dump", "/data/local/tmp/emu-ui.xml"], capture_output=True, timeout=60)
        raw = subprocess.run([adb, "-s", serial, "exec-out", "cat", "/data/local/tmp/emu-ui.xml"], capture_output=True, timeout=60).stdout.decode("utf-8", "replace")
        if raw.lstrip().startswith("<?xml"):
            return ET.fromstring(raw)
        time.sleep(1)
    return None
t0 = time.time()
while True:
    root = dump()
    hits = []
    if root is not None:
        for n in root.iter("node"):
            if mode == "edit":
                if n.get("class") == "android.widget.EditText":
                    hits.append(n)
            elif rx.search(n.get("text") or "") or rx.search(n.get("content-desc") or ""):
                hits.append(n)
    if hits:
        n = hits[0]
        if mode == "tap":
            x1, y1, x2, y2 = map(int, re.findall(r"\d+", n.get("bounds", "")))
            subprocess.run([adb, "-s", serial, "shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2)], check=True, timeout=60)
            time.sleep(1.5)
        elif mode.startswith("attr:"):
            print(n.get(mode[5:], ""))
        elif mode == "edit":
            print(n.get("text", ""))
        sys.exit(0)
    if time.time() - t0 > limit:
        seen = [] if root is None else [x for x in ((n.get("text") or n.get("content-desc") or "") for n in root.iter("node")) if x][:15]
        print(f"emu.sh: 화면에 /{pat}/ 가 없다({limit:.0f}s, {mode}) — 보이는 글자: {seen}", file=sys.stderr)
        sys.exit(1)
    time.sleep(1)
UIPY
  }
  # Gboard 설정을 열고 Languages 를 누른다. 부팅 직후에는 홈 화면이 뒤늦게 위로 올라와 설정을 덮는다(실측) — 최대 5번 다시 연다.
  # 인자 -S 면 Gboard(IME 프로세스)를 멈췄다 다시 띄운다 — 받은 자료를 새로 읽게.
  open_gb_languages() {
    local i
    for i in 1 2 3 4 5; do
      sh_adb shell am start -W ${1:+"$1"} -n "$GB_SETTINGS" >/dev/null 2>&1
      if ui tap '^Languages$' 20; then return 0; fi
      log "Gboard 설정의 Languages 가 안 보인다($i) — 다시 연다"
      sleep 5
    done
    return 1
  }
  # 지금 띄운 기기에서 Gboard 설정 → Languages → Add keyboard 의 검색 칸(EditText)에 dkssud 를 넣고 칸 글자를 낸다.
  ko_typed() {
    open_gb_languages -S || return 1
    ui tap '^Add keyboard$' 20 && ui tap '^Search (for a )?language$' 20 || return 1
    sh_adb shell input text dkssud || return 1
    sleep 3
    ui edit . 10
  }
  ko_until_composed() { # 시도 수 · 사이 초
    local i got
    for i in $(seq 1 "$1"); do
      got="$(ko_typed 2>/dev/null)"
      log "한국어 조합 시도 $i: '$got'"
      [ "$got" = "안녕" ] && return 0
      sleep "$2"
    done
    return 1
  }
  started=0
  finish_prep() { [ "$started" -eq 1 ] && "$SELF" stop --port "$PORT" --timeout 30 >&2; started=0; }
  trap 'finish_prep; exit 130' INT TERM
  "$SELF" avd-clone --from "$FROM" --to "$TO" || exit $?
  # 1) 봉인 없이·쓰기로: Gboard 에 한국어·두벌식을 더하고 자료를 받는다.
  started=1
  "$SELF" start --avd "$TO" --port "$PORT" --no-seal --writable --boot-timeout "$BOOT_TIMEOUT" || { log "띄우지 못했다(쓰기)"; finish_prep; exit 1; }
  sh_adb shell ime enable "$GB_IME" >/dev/null 2>&1; sh_adb shell ime set "$GB_IME" >/dev/null 2>&1
  open_gb_languages || { log "Gboard 설정을 못 열었다"; finish_prep; exit 1; }
  if ui wait '^한국어$' 3 2>/dev/null; then
    log "Gboard 에 한국어가 이미 있다"
  else
    # 검색 칸 글자는 처음 열 때 'Search for a language', 그 뒤로 'Search language' 다(실측). 늦게 뜰 수 있어 60초 기다리고,
    # 없으면 뒤로 가서 한 번 더.
    picked=0
    for attempt in 1 2; do
      if ui tap '^Add keyboard$' 30 && ui tap '^Search (for a )?language$' 60 && sh_adb shell input text Korean && ui tap '^한국어$' 30; then picked=1; break; fi
      log "한국어 고르기 $attempt 번째 실패 — 뒤로 가서 다시"
      sh_adb shell input keyevent KEYCODE_BACK; sleep 2
    done
    [ "$picked" -eq 1 ] || { log "한국어를 못 골랐다"; finish_prep; exit 1; }
    [ "$(ui 'attr:selected' '^두벌식$')" = "true" ] || ui tap '^두벌식$' || { finish_prep; exit 1; }
    ui tap '^Done$' || { finish_prep; exit 1; }
  fi
  case "$(sh_adb shell settings get secure enabled_input_methods | tr -d '\r')" in
    *";$KO_SUBTYPE"*) log "켜진 IME 에 두벌식($KO_SUBTYPE)이 있다" ;;
    *) log "켜진 IME 에 두벌식($KO_SUBTYPE)이 없다 — Gboard 화면이 바뀌었나"; finish_prep; exit 1 ;;
  esac
  sh_adb shell settings put secure selected_input_method_subtype "$KO_SUBTYPE"
  ko_until_composed 12 15 || { log "쓰기 실행에서 '안녕' 이 안 나왔다(자료를 못 받음 — 망?)"; finish_prep; exit 1; }
  finish_prep
  # 2) 봉인·읽기 전용으로 다시: 받은 자료만으로 조합하는가.
  started=1
  "$SELF" start --avd "$TO" --port "$PORT" --boot-timeout "$BOOT_TIMEOUT" || { log "띄우지 못했다(봉인)"; finish_prep; exit 1; }
  "$SELF" sealcheck --port "$PORT" || { log "봉인 확인 실패"; finish_prep; exit 1; }
  ko_until_composed 3 5 || { log "봉인 실행에서 '안녕' 이 안 나왔다"; finish_prep; exit 1; }
  finish_prep
  # 3) 보호 표식.
  "$SELF" avd-protect --avd "$TO" || exit 1
  echo "avd-prepare-ko avd=$TO from=$FROM subtype=$KO_SUBTYPE sealed-compose=안녕 protected=1"
  ;;

instrumented)
  MP="$(cd "$SCRIPT_DIR/.." && pwd)"
  case "$TASK" in :*:*) ;; *) die "--task 는 :모듈:작업 꼴이다: $TASK" ;; esac
  module_dir="$(printf '%s' "$TASK" | sed -e 's/^://' -e 's/:[^:]*$//' -e 's#:#/#g')"
  results="$MP/$module_dir/build/outputs/androidTest-results/connected"
  PY="$(command -v python3 || true)"; [ -n "$PY" ] || die "결과 XML 을 읽을 python3 가 없다"
  [ "$SEALED" -eq 0 ] || [ -f "$SEAL" ] || die "봉인 프로파일이 없다: $SEAL"
  # 가짜 창 목록은 self-test 전용이다 — 게이트가 그것으로 '창 0' 을 내면 아무것도 재지 않은 것이다.
  [ -z "${EMU_FAKE_WINDOWS:-}" ] || die "EMU_FAKE_WINDOWS 는 self-test 전용이다 — instrumented 는 진짜 창 목록(CGWindowList)으로만 판정한다"
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
