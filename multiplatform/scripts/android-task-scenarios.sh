#!/bin/bash
# E-U16 작업·인스턴스 시나리오(G §8-12): 딥링크 → 프로세스 죽음 → 런처 아이콘 순서 뒤 Activity 가 1개이고 복원된 화면이 맨 위인가.
# + 시나리오 4(G §8-13): 알림 [수락](맞는 증표)이 작업 뿌리 → 뒤로 끝남 → 최근 앱에서 다시 띄움 → 증표째 다시 와도 수락은 버린다.
#   최근 앱 카드 누르기는 Pixel 런처(nexuslauncher, API 36 AVD)의 snapshot 노드를 찾아 그 가운데를 누른다.
# 프로세스를 죽이는 일은 계측 시험 안에서 못 한다(계측이 같은 프로세스) — 그래서 adb 로 몬다.
#
#   android-task-scenarios.sh --serial emulator-5562 --apk <debug.apk>
#
# 판정 근거(사람이 다시 볼 수 있게 줄마다 찍는다)
#   - 인스턴스 수: dumpsys activity activities 의 ActivityRecord 중 이 앱 MainActivity
#   - 화면: uiautomator dump 의 글자(자리표시 화면이 라우트 URL 을 보여 준다)
#   - 로그: AingShell 태그(onCreate restored=… / onNewIntent action=…)
# 종료 코드: 전부 통과면 0, 하나라도 실패면 1, 준비 실패면 2.
set -u -o pipefail

SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
ADB="$SDK/platform-tools/adb"
SER=""; APK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --serial) SER="${2:?}"; shift 2 ;;
    --apk) APK="${2:?}"; shift 2 ;;
    *) echo "모르는 인자: $1" >&2; exit 2 ;;
  esac
done
[ -n "$SER" ] && [ -f "$APK" ] || { echo "--serial 과 --apk 가 필요하다" >&2; exit 2; }

PKG=com.yehsung.aingcheck
ACT=$PKG/.android.shell.MainActivity
a() { "$ADB" -s "$SER" "$@"; }

PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1: $2"; PASS=$((PASS+1)); else echo "FAIL $1: got[$2] want[$3]"; FAIL=$((FAIL+1)); fi; }

instances() { a shell dumpsys activity activities | tr -d '\r' | grep -cE "Hist +#[0-9]+: ActivityRecord\{[^}]*$PKG/\.android\.shell\.MainActivity" ; }
tasks() { a shell dumpsys activity activities | tr -d '\r' | grep -E "Hist +#[0-9]+: ActivityRecord\{[^}]*$PKG/" | grep -oE " t[0-9]+" | sort -u | tr -d ' ' | tr '\n' ',' ; }
screen() { a shell uiautomator dump /sdcard/aing-ui.xml >/dev/null 2>&1; a exec-out cat /sdcard/aing-ui.xml 2>/dev/null; }
# 화면에 글자가 나올 때까지(최대 20초).
wait_text() { local t=0; until screen | grep -qF "$1"; do sleep 1; t=$((t+1)); [ $t -ge 20 ] && return 1; done; return 0; }
# 실패하면 무엇이 떠 있었는지 남긴다(갓 부팅한 기기의 시스템 대화상자 등).
shows() {
  if wait_text "$1"; then echo yes; return; fi
  echo "  [진단] focus=$(a shell dumpsys window | tr -d '\r' | grep -m1 mCurrentFocus | sed 's/^ *//') texts=$(screen | grep -oE 'text="[^"]+"' | head -8 | tr '\n' ' ')" >&2
  echo no
}
shell_log() { a logcat -d -s AingShell:I | tr -d '\r' | sed 's/.*AingShell: //' ; }
launcher() { a shell am start -W -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -f 0x10200000 -n "$ACT" >/dev/null; }
# 알림 [수락] 과 같은 명시적 Intent 를 새 작업의 뿌리로 띄운다(인자: 증표).
accept_root() {
  a shell am start -W -n "$ACT" -a com.yehsung.aingcheck.action.OPEN_ROUTE --es com.yehsung.aingcheck.extra.ROUTE "$1" \
    --ez com.yehsung.aingcheck.extra.ACCEPT true --es com.yehsung.aingcheck.extra.PROOF "$2" -f 0x10000000 >/dev/null
  sleep 2
}
# 최근 앱(개요)을 열고 이 앱 카드의 그림 가운데를 누른다 — 시스템이 작업 뿌리 Intent 를 FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY 로 다시 보낸다.
recents_relaunch() {
  a shell input keyevent KEYCODE_APP_SWITCH; sleep 2
  local b x1 y1 x2 y2
  b="$(screen | grep -oE 'id/snapshot"[^>]*content-desc="아잉체크"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -n 1)"
  if [ -z "$b" ]; then
    echo "  [진단] 최근 앱 카드를 못 찾았다: focus=$(a shell dumpsys window | tr -d '\r' | grep -m1 mCurrentFocus | sed 's/^ *//')" >&2
    return 1
  fi
  read -r x1 y1 x2 y2 <<<"$(echo "$b" | tr -c '0-9' ' ')"
  a shell input tap $(( (x1 + x2) / 2 )) $(( (y1 + y2) / 2 ))
  sleep 3
}

die_and_launcher() {
  a shell input keyevent KEYCODE_HOME; sleep 2
  local before after; before=$(a shell pidof $PKG | tr -d '\r')
  a shell am kill $PKG; sleep 1; after=$(a shell pidof $PKG | tr -d '\r')
  local how="am-kill"
  # API 26 의 am kill 은 뒤에 있는 이 프로세스를 죽이지 않을 때가 있다(실측) — 그때는 앱 uid 로 SIGKILL(저메모리 종료와 같은 모양).
  if [ -n "$after" ]; then
    a shell run-as $PKG kill -9 "$after" >/dev/null 2>&1; sleep 1; after=$(a shell pidof $PKG | tr -d '\r'); how="run-as-kill-9"
  fi
  echo "  프로세스 죽음($how): pid before=[$before] after=[$after]"
  check "  am kill 로 프로세스가 죽었다" "$([ -n "$before" ] && [ -z "$after" ] && echo dead || echo alive)" "dead"
  a logcat -c
  launcher
  sleep 2
}

echo "== 준비: 설치 $(basename "$APK") → $SER"
a install -r -t "$APK" >/dev/null || { echo "설치 실패" >&2; exit 2; }
# 갓 부팅한 기기는 시스템 대화상자(시스템 UI 응답 없음 등)가 앞을 가릴 수 있다 — 닫고 홈으로.
a shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1
a shell input keyevent KEYCODE_HOME

echo "== 시나리오 1: 딥링크(VIEW) → 프로세스 죽음 → 런처 아이콘"
a shell am force-stop $PKG; a logcat -c
a shell am start -W -a android.intent.action.VIEW -d "aingcheck://message/abc-123" $PKG >/dev/null
check "딥링크 화면" "$(shows 'aingcheck://message/abc-123')" "yes"
check "딥링크 뒤 인스턴스" "$(instances)" "1"
die_and_launcher
check "런처 뒤 인스턴스(E-U16)" "$(instances)" "1"
check "런처 뒤 작업 수" "$(tasks)" "$(tasks | cut -d, -f1),"
check "런처 뒤 복원된 대화가 맨 위" "$(shows 'aingcheck://message/abc-123')" "yes"
echo "  로그: $(shell_log | tr '\n' '|')"
check "복원된 인스턴스가 런처 Intent 를 onNewIntent 로 받았다" "$(shell_log | grep -c 'onNewIntent restored=false task=[0-9]* action=android.intent.action.MAIN')" "1"
a shell input keyevent KEYCODE_BACK
check "뒤로 → 메시지 목록(탭 스택 그대로)" "$(shows 'aingcheck://messages')" "yes"
check "뒤로 뒤 인스턴스" "$(instances)" "1"

echo "== 시나리오 2: 알림 탭(명시적 OPEN_ROUTE) → 프로세스 죽음 → 런처 아이콘"
a shell am force-stop $PKG; a logcat -c
a shell am start -W -n "$ACT" -a com.yehsung.aingcheck.action.OPEN_ROUTE --es com.yehsung.aingcheck.extra.ROUTE "aingcheck://gomoku/invite/m1" -f 0x10000000 >/dev/null
check "알림 라우트 화면" "$(shows 'aingcheck://gomoku/invite/m1')" "yes"
die_and_launcher
check "런처 뒤 인스턴스" "$(instances)" "1"
check "런처 뒤 오목 신청 화면" "$(shows 'aingcheck://gomoku/invite/m1')" "yes"

echo "== 시나리오 3: 떠 있는 앱에 바깥 딥링크 → 같은 인스턴스(onNewIntent)"
a shell am force-stop $PKG; a logcat -c
launcher
check "런처 첫 화면" "$(shows 'aingcheck://now')" "yes"
a shell am start -W -a android.intent.action.VIEW -d "aingcheck://me/settings" $PKG >/dev/null
check "딥링크 화면" "$(shows 'aingcheck://me/settings')" "yes"
check "인스턴스" "$(instances)" "1"
check "onCreate 한 번" "$(shell_log | grep -c '^onCreate')" "1"

echo "== 시나리오 4: 알림 [수락](맞는 증표) 작업 뿌리 → 뒤로 끝남 → 최근 앱에서 다시 띄움 → 수락 버림·화면만(G §8-13)"
INV="aingcheck://gomoku/invite/h1"
a shell am force-stop $PKG; a logcat -c
# 틀린 증표 수락: 앱이 이 설치의 증표를 처음 만들고(앱 전용 저장소), 수락은 거짓이다.
accept_root "$INV" "$(printf '0%.0s' $(seq 64))"
check "틀린 증표 수락은 거짓" "$(shell_log | grep -c '^route accept=false history=false proof=true')" "1"
proof="$(a shell run-as $PKG cat shared_prefs/aingcheck.xml | tr -d '\r' | grep -oE 'acceptProof">[0-9a-f]{64}<' | grep -oE '[0-9a-f]{64}')"
check "이 설치의 증표(debug run-as)" "${#proof}" "64"
a shell am force-stop $PKG; a logcat -c
accept_root "$INV" "$proof"
check "기준선: 맞는 증표 수락은 참" "$(shell_log | grep -c '^route accept=true history=false proof=true')" "1"
# 뒤로 → 탭 뿌리 → Activity 가 끝난다(작업 뿌리가 런처 Intent 가 아니라 Android 12+ 에서도 끝난다). 작업은 최근 앱에 남는다.
for _ in 1 2 3 4 5; do [ "$(instances)" = "0" ] && break; a shell input keyevent KEYCODE_BACK; sleep 1; done
check "뒤로 뒤 Activity 0(작업은 최근 앱에 남음)" "$(instances)" "0"
a logcat -c
recents_relaunch
check "최근 앱에서 저장 상태 없이 다시 만들어졌다" "$(shell_log | grep -c '^onCreate restored=false .*action=com.yehsung.aingcheck.action.OPEN_ROUTE')" "1"
check "기록 Intent 가 증표째 다시 왔고 수락은 거짓" "$(shell_log | grep -c '^route accept=false history=true proof=true opened=true')" "1"
check "기록 Intent 로 수락이 참이 된 줄" "$(shell_log | grep -c '^route accept=true')" "0"
check "신청 화면은 열렸다" "$(shows "$INV")" "yes"
echo "  로그: $(shell_log | tr '\n' '|')"

a shell am force-stop $PKG
echo "TOTAL pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
