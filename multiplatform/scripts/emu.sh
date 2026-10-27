#!/bin/bash
# 원본: 없음 (Swift 짝 없음 — 이식 도구)
# emu.sh — 창 없는 Android 에뮬레이터를 띄우고·찍고·끄는 유일한 입구 (W0-f, A§4-3·A-X7)
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
#   emu.sh windows --port N        # 이 포트로 띄운 프로세스의 창 수 + 이름이 qemu/emulator 인 모든 창 수(둘 중 하나라도 0 이 아니면 1)
#   emu.sh procs   --port N        # 이 포트로 띄운 프로세스 중 살아 있는 수(0 이 아니면 종료 코드 1)
#   emu.sh sealcheck --port N      # 손님 안에서 바깥 TCP(1.1.1.1:443)가 실패하고 adb 는 사는지. 둘 다면 0, 아니면 1
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
  mkdir -p "$T/sdk/emulator" "$T/sdk/platform-tools" "$A" "$A2" "$T/stub" "$T/state" "$T/copy"
  # 가짜 에뮬레이터: 인자와 받은 ANDROID_AVD_HOME 을 적고 PID 를 남긴 뒤 잠든다.
  cat > "$T/sdk/emulator/emulator" <<'STUB'
#!/bin/bash
printf 'ARGS %s AVD_HOME=%s\n' "$*" "${ANDROID_AVD_HOME:-}" >> "$STUBDIR/emu-args"
echo $$ >> "$STUBDIR/launches"
echo $$ > "$STUBDIR/cur.pid"
exec /bin/sleep 60
STUB
  # 가짜 adb: 부른 것을 적는다. 부팅은 곧바로 끝났다고 답하고, emu kill 은 가짜 에뮬레이터를 끈다.
  cat > "$T/sdk/platform-tools/adb" <<'STUB'
#!/bin/bash
echo "adb $*" >> "$STUBDIR/adb-log"
case "$*" in
  devices*) echo "List of devices attached" ;;
  *"getprop sys.boot_completed"*) [ -f "$STUBDIR/cur.pid" ] && echo 1 ;;   # 가짜 에뮬레이터가 돈 뒤에야 '부팅 끝' 
  *"emu kill"*) [ -f "$STUBDIR/cur.pid" ] && kill "$(cat "$STUBDIR/cur.pid")" 2>/dev/null; rm -f "$STUBDIR/cur.pid" ;;
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

  sub() { # 하위 실행 — 진짜 홈·SDK·AVD 폴더를 못 보게 덮는다
    env -u ANDROID_AVD_HOME HOME="$T/home" ANDROID_SDK_ROOT="$T/sdk" ANDROID_HOME="$T/sdk" EMU_STATE_DIR="$T/state" STUBDIR="$T/stub" \
      /bin/bash "$@" >>"$T/out.log" 2>&1
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

  # 끝: 가짜 에뮬레이터가 살아 있지 않아야 한다 — 마지막으로 띄운 것(cur.pid 는 emu kill 이 지운다)과 emu.sh procs 로 센다.
  local alive=0 p
  if [ -f "$T/stub/cur.pid" ]; then
    p="$(cat "$T/stub/cur.pid")"
    if kill -0 "$p" 2>/dev/null && [ "$(ps -o comm= -p "$p" 2>/dev/null | sed 's#.*/##')" = sleep ]; then alive=1; kill -KILL "$p" 2>/dev/null; fi
  fi
  check "남은 가짜 에뮬레이터 0(cur.pid)" 0 "$alive"
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
  # 에뮬레이터가 여는 AVD 폴더 = 위에서 판정한 폴더(ANDROID_AVD_HOME 을 같은 값으로 넘긴다).
  export ANDROID_AVD_HOME="$AVD_HOME"
  t0=$(date +%s)
  # 새 세션으로 떼어 낸다(부른 셸이 끝나도 산다). PID 는 sandbox-exec → exec → emulator 로 같다.
  /usr/bin/perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "exec: $!"' -- \
    ${launcher[@]+"${launcher[@]}"} "$EMU_BIN" "${args[@]}" </dev/null >>"$LOGFILE" 2>&1 &
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
  # 지금 띄운 기기에서 Gboard 설정 → Languages → Add keyboard 의 검색 칸(EditText)에 dkssud 를 넣고 칸 글자를 낸다.
  # am start -S 가 Gboard(IME)도 다시 띄운다 — 받은 자료를 새로 읽게.
  ko_typed() {
    sh_adb shell am start -W -S -n "$GB_SETTINGS" >/dev/null 2>&1 || return 1
    ui tap '^Languages$' 30 && ui tap '^Add keyboard$' 20 && ui tap '^Search (for a )?language$' 20 || return 1
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
  sh_adb shell am start -W -n "$GB_SETTINGS" >/dev/null 2>&1
  ui tap '^Languages$' 30 || { finish_prep; exit 1; }
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
