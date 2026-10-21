#!/bin/bash
# vm.sh 자가 시험(맥, VM 없이). 가짜 vmrun·ssh·창 탐침으로 잠금·스냅숏·종료 코드 전달·정리를 결과로 잰다.
# 사용: /bin/bash tests/test-vm-sh.sh   (macOS 기본 bash 3.2 로 돌려야 한다 — vm.sh 가 그 bash 로 돈다)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM="$HERE/../vm.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/aingvm-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s — %s\n' "$1" "$2"; }

# 시험 저장소: 추적 파일 + 무시 파일 + (나중에) 추적 안 되는 새 파일
R="$T/repo"
mkdir -p "$R/multiplatform/sub" "$R/multiplatform/build" "$R/other"
(
    cd "$R"
    git init -q
    git config user.email t@example.invalid
    git config user.name t
    printf 'build/\n' >multiplatform/.gitignore
    printf 'tracked\n' >multiplatform/sub/a.txt
    printf 'outside\n' >other/o.txt
    git add -A
    git commit -qm init
)
printf 'ignored\n' >"$R/multiplatform/build/ignored.bin"

reset_env() {
    rm -rf "$T/lock" "$T/state" "$T/guest" "$T/vmstate"*
    mkdir -p "$T/vm" "$T/guest"
    printf 'ethernet0.generatedAddress = "00:0c:29:aa:bb:cc"\n' >"$T/vm/test.vmx"
    printf 'not a key\n' >"$T/key"
    echo 0 >"$T/windows"
    : >"$T/vmrun.log"
    : >"$T/ssh.log"
    export AINGCHECK_VMX="$T/vm/test.vmx" AINGCHECK_VMRUN="$HERE/fake-vmrun.sh" AINGCHECK_VM_KEY="$T/key"
    export AINGCHECK_VM_LOCK="$T/lock" AINGCHECK_VM_STATE="$T/state" AINGCHECK_SSH="$HERE/fake-ssh.sh" AINGCHECK_SCP=false
    export AINGCHECK_WINPROBE="$HERE/fake-winprobe.sh" FAKE_WINDOWS="$T/windows"
    export FAKE_VMRUN_STATE="$T/vmstate" FAKE_VMRUN_LOG="$T/vmrun.log" FAKE_GUEST="$T/guest" FAKE_SSH_LOG="$T/ssh.log"
    export FAKE_GUEST_ARGS="$T/guest-args"
    unset AINGCHECK_VM_TOKEN FAKE_TAMPER FAKE_GRADLE_EXIT FAKE_VMRUN_NOIP FAKE_VMRUN_START_FAIL AINGCHECK_VM_ALLOW_GP 2>/dev/null || true
}

vm() { (cd "$R" && /bin/bash "$VM" "$@" </dev/null); }
up_token() { vm up 2>"$T/up.err" | sed -n 's/^export AINGCHECK_VM_TOKEN=//p'; }

# 1. 잠금: 두 번째 up 은 기다리지 않고 75
reset_env
tok="$(up_token)"
if [ -n "$tok" ] && [ -d "$T/lock" ] && [ "$(cat "$T/vmstate")" = running ]; then ok "up 이 잠금·토큰·시동을 만든다"; else bad "up" "token=$tok $(cat "$T/up.err")"; fi
start=$SECONDS
vm up >/dev/null 2>&1
rc=$?
if [ $rc -eq 75 ] && [ $((SECONDS - start)) -le 3 ]; then ok "두 번째 up 은 바로 75"; else bad "잠금 경합" "rc=$rc"; fi

# 1b. VM 이 꺼져 있어도 남의 잠금이 있으면 up 은 75(잠금 자체가 막는다)
(
    reset_env
    mkdir -p "$T/lock"
    printf 'pid=1\n' >"$T/lock/owner"
    vm up >/dev/null 2>&1
    rc=$?
    if [ $rc -eq 75 ] && [ "$(cat "$T/vmstate" 2>/dev/null)" != running ]; then echo PASS; else echo "FAIL rc=$rc"; fi
) >"$T/case1b"
if grep -q '^PASS' "$T/case1b"; then ok "남의 잠금이 있으면 VM 이 꺼져 있어도 75, 시동 안 함"; else bad "잠금 단독" "$(cat "$T/case1b")"; fi
reset_env
tok="$(up_token)"

# 2. 토큰 없이 push → 77
vm push >/dev/null 2>&1
rc=$?
[ $rc -eq 77 ] && ok "토큰 없는 push 는 77" || bad "토큰 검사" "rc=$rc"

# 3. push: 새 파일 포함 · 무시 파일 제외 · 실제 인덱스 불변 · 지문 대조(다른 구현)
printf 'new untracked\n' >"$R/multiplatform/sub/new.kt"
before_index="$(cd "$R" && git ls-files --stage | shasum)"
out="$(AINGCHECK_VM_TOKEN="$tok" vm push --paths multiplatform 2>"$T/push.err")"
rc=$?
run="$(find "$T/guest/work/runs" -mindepth 1 -maxdepth 1 -type d | head -1)"
if [ $rc -eq 0 ] && [ -f "$run/multiplatform/sub/new.kt" ] && [ ! -e "$run/multiplatform/build/ignored.bin" ] && [ ! -e "$run/other/o.txt" ] && printf '%s' "$out" | grep -q '"match": *true'; then
    ok "push 가 새 파일을 담고 무시·범위 밖 파일을 뺀다, 손님 지문 일치"
else
    bad "push" "rc=$rc out=$out err=$(cat "$T/push.err")"
fi
after_index="$(cd "$R" && git ls-files --stage | shasum)"
[ "$before_index" = "$after_index" ] && (cd "$R" && git status --porcelain | grep -q '^?? multiplatform/sub/new.kt') && ok "실제 인덱스는 그대로(new.kt 는 여전히 미추적)" || bad "인덱스 오염" "$(cd "$R" && git status --porcelain)"

# 4. gradle: 종료 코드·인자 그대로
out="$(AINGCHECK_VM_TOKEN="$tok" FAKE_GRADLE_EXIT=37 vm gradle :x:test --tests 'A B' 'q"uote\back' 2>/dev/null)"
rc=$?
args="$(cat "$T/guest-args" 2>/dev/null)"
if [ $rc -eq 37 ] && [ "$args" = '[":x:test","--tests","A B","q\"uote\\back"]' ]; then ok "gradle 종료 코드 37 과 인자가 그대로 간다"; else bad "gradle 전달" "rc=$rc args=$args"; fi
grep -q -- '-Arch "*arm64' "$T/guest-args.remote" && ok "기본 손님 아키텍처는 arm64" || bad "arch" "$(cat "$T/guest-args.remote")"

# 5. down: 정지·잠금 해제, 창이 늘면 78
echo 1 >"$T/windows"
AINGCHECK_VM_TOKEN="$tok" vm down >/dev/null 2>&1
rc=$?
if [ $rc -eq 78 ] && [ ! -d "$T/lock" ] && [ "$(cat "$T/vmstate")" = stopped ]; then ok "down 은 끄고 잠금을 풀고, 창이 늘었으면 78"; else bad "down" "rc=$rc"; fi

# 6. 변조 감지: 손님에서 한 바이트가 바뀌면 push 가 1
reset_env
tok="$(up_token)"
AINGCHECK_VM_TOKEN="$tok" FAKE_TAMPER=1 vm push --paths multiplatform >/dev/null 2>&1
rc=$?
[ $rc -eq 1 ] && ok "손님 쪽 변조를 지문이 잡는다" || bad "변조" "rc=$rc"
AINGCHECK_VM_TOKEN="$tok" vm down >/dev/null 2>&1

# 7. batch: 중간 실패의 코드로 끝나고 언제나 down
reset_env
printf 'push --paths multiplatform\n# 주석\n\ngradle :fail\ninfo\n' >"$T/plan"
FAKE_GRADLE_EXIT=5 vm batch "$T/plan" >/dev/null 2>"$T/batch.err"
rc=$?
if [ $rc -eq 5 ] && [ ! -d "$T/lock" ] && [ "$(cat "$T/vmstate")" = stopped ] && ! grep -q 'Action info' "$T/ssh.log"; then
    ok "batch 는 첫 실패 코드(5)로 끝나고 down 한다, 뒤 줄은 안 돈다"
else
    bad "batch" "rc=$rc $(tail -3 "$T/batch.err")"
fi
printf 'push --paths multiplatform\nrm -rf /\n' >"$T/plan2"
reset_env
vm batch "$T/plan2" >/dev/null 2>&1
rc=$?
[ $rc -eq 64 ] && [ ! -d "$T/lock" ] && ok "batch 는 허용 목록 밖 명령을 거절(64)하고 정리한다" || bad "batch 허용 목록" "rc=$rc"

# 8. up 중간 실패 정리: IP 를 못 얻으면 69, VM 꺼짐, 잠금 없음
reset_env
FAKE_VMRUN_NOIP=1 vm up >/dev/null 2>&1
rc=$?
if [ $rc -eq 69 ] && [ ! -d "$T/lock" ] && [ "$(cat "$T/vmstate")" = stopped ]; then ok "up 이 실패하면 VM 을 끄고 잠금을 푼다"; else bad "up 정리" "rc=$rc lock=$([ -d "$T/lock" ] && echo yes)"; fi

# 9. VM·도구 없음 → 69(잠금을 만들지 않는다)
reset_env
AINGCHECK_VMRUN="$T/nope" vm up >/dev/null 2>&1
rc=$?
[ $rc -eq 69 ] && [ ! -d "$T/lock" ] && ok "vmrun 이 없으면 69, 잠금 없음" || bad "vmrun 없음" "rc=$rc"

# 10. shot OUT 이 저장소 안이면 64
reset_env
tok="$(up_token)"
AINGCHECK_VM_TOKEN="$tok" vm push --paths multiplatform >/dev/null 2>&1
AINGCHECK_VM_TOKEN="$tok" vm shot "$R/multiplatform/x.png" >/dev/null 2>&1
rc=$?
[ $rc -eq 64 ] && ok "shot 은 저장소 안 경로를 거절(64)" || bad "shot 경로" "rc=$rc"
AINGCHECK_VM_TOKEN="$tok" vm down >/dev/null 2>&1

# 11. unlock-stale: VM 이 켜져 있으면 거절, 꺼져 있고 주인이 죽었으면 지운다
reset_env
tok="$(up_token)"
vm unlock-stale >/dev/null 2>&1
rc=$?
[ $rc -eq 75 ] && [ -d "$T/lock" ] && ok "unlock-stale 은 VM 이 켜져 있으면 75" || bad "unlock-stale 켜짐" "rc=$rc"
echo stopped >"$T/vmstate"
vm unlock-stale >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] && [ ! -d "$T/lock" ] && ok "unlock-stale 은 꺼진 VM 의 낡은 잠금을 지운다" || bad "unlock-stale 꺼짐" "rc=$rc"

# 12. vmrun -gp 는 보호 함수 안에서만(주석을 걷고 본다)
stripped="$(sed -e 's/[[:space:]]#.*$//' -e 's/^#.*$//' "$VM")"
gp_lines="$(printf '%s\n' "$stripped" | grep -n -- '-gp' || true)"
fn_start="$(printf '%s\n' "$stripped" | grep -n '^vmrun_with_guest_creds()' | cut -d: -f1)"
fn_end="$(printf '%s\n' "$stripped" | awk -v s="$fn_start" 'NR>s && /^}/ {print NR; exit}')"
outside=0
while IFS=: read -r n _; do
    [ -z "$n" ] && continue
    if [ "$n" -lt "$fn_start" ] || [ "$n" -gt "$fn_end" ]; then outside=$((outside + 1)); fi
done <<<"$gp_lines"
if [ -n "$fn_start" ] && [ -n "$gp_lines" ] && [ $outside -eq 0 ]; then ok "vmrun -gp 는 보호 함수 안에만 있다"; else bad "-gp 위치" "outside=$outside"; fi
reset_env
sed '$d' "$VM" >"$T/vmlib.sh"
out="$(cd "$R" && /bin/bash -c "source '$T/vmlib.sh'; vmrun_with_guest_creds list" 2>&1)"
rc=$?
[ $rc -eq 64 ] && ok "-gp 경로는 기본 거절(64)" || bad "-gp 기본 거절" "rc=$rc $out"

# 13. 스냅숏 지문이 손님 쪽 다른 구현과 같은 값(앞 3 에서 일치) + 같은 입력이면 같은 트리
reset_env
a="$(vm snapshot --paths multiplatform 2>/dev/null | sed -n 's/.*"tree":"\([0-9a-f]*\)".*/\1/p')"
b="$(vm snapshot --paths multiplatform 2>/dev/null | sed -n 's/.*"tree":"\([0-9a-f]*\)".*/\1/p')"
printf 'changed\n' >>"$R/multiplatform/sub/new.kt"
c="$(vm snapshot --paths multiplatform 2>/dev/null | sed -n 's/.*"tree":"\([0-9a-f]*\)".*/\1/p')"
[ -n "$a" ] && [ "$a" = "$b" ] && [ "$a" != "$c" ] && ok "스냅숏 트리: 같은 입력 같음, 새 파일 수정은 다름" || bad "스냅숏 결정성" "$a $b $c"

# 14. .ps1 은 UTF-8 BOM 으로 시작한다 — Windows PowerShell 5.1 은 BOM 없는 UTF-8 을 ANSI(CP949·1252)로 읽어
#     한글 주석·문자열에서 구문 오류가 난다(러너 run 39591985078 에서 실측). VM 은 5.1 로 돈다.
nobom=0
for f in "$HERE"/../*.ps1 "$HERE"/../../../spikes/windows/ci/*.ps1 "$HERE"/../../../spikes/windows/msix/*.ps1; do
    [ -f "$f" ] || continue
    [ "$(head -c 3 "$f" | od -An -tx1 | tr -d ' \n')" = "efbbbf" ] || { nobom=$((nobom + 1)); printf '  BOM 없음: %s\n' "$f"; }
done
[ $nobom -eq 0 ] && ok "모든 .ps1 이 UTF-8 BOM 으로 시작한다" || bad "BOM" "$nobom 개"

printf '\n%d 통과 · %d 실패\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
