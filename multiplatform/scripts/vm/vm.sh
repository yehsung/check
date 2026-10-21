#!/bin/bash
# VMware Fusion Windows 11 Arm VM 하네스(맥에서 실행). 에이전트는 VM 을 이 스크립트로만 다룬다.
# 정본: G §8-6(교차 검증 반영) > A §4-4 > D §15-2. 화면에 창을 띄우지 않는다(nogui), 운영 서버를 부르지 않는다.
#
#   up                      잠금 → nogui 시동 → IP → SSH 확인 → Fusion 창 증가 0 단언. 마지막 줄에 export AINGCHECK_VM_TOKEN=…
#   push [--paths a,b,…]    임시 인덱스 스냅숏(새 파일 포함) → git archive | ssh tar → VM 이 지문을 다시 계산해 대조
#   gradle ARGS…            VM 에서 봉인 카나리아(짝) → gradlew.bat --offline --no-daemon ARGS. 종료 코드를 그대로 돌려준다
#   gui -- CMD ARGS…        schtasks /IT 로 tester 대화형 세션에서 실행(종료 코드 그대로)
#   shot OUT.png            대화형 세션 캡처 → OUT(저장소 밖 경로만)
#   info                    손님 세션·권한 기록
#   revert SNAPSHOT         정지 → 스냅숏 복귀 → 다시 시동(잠금 유지)
#   down                    soft 정지(60초) → 안 되면 hard → vmrun list 에서 빠졌는지·창 증가 0 → 잠금 해제
#   batch PLAN              up → PLAN 의 줄을 차례로 → down(언제나). 첫 실패의 종료 코드로 끝난다
#   snapshot [--paths …] [--out TAR]   (VM 없이) 스냅숏 트리·지문만. 자가 시험·CI 용
#   status | unlock-stale | reap --i-am-coordinator
#
# 환경변수(기본값): AINGCHECK_VMX(~/Virtual Machines.localized/aing-win11-arm.vmwarevm/aing-win11-arm.vmx)
#   AINGCHECK_VMRUN(/Applications/VMware Fusion.app/Contents/Library/vmrun) AINGCHECK_VM_USER(tester)
#   AINGCHECK_VM_KEY(~/.aing-check-secrets/vm/aingcheck_vm_ed25519 — 경로만 ssh 에 넘긴다, 이 스크립트는 읽지 않는다)
#   AINGCHECK_VM_LOCK(/tmp/aingcheck-vm.lock) AINGCHECK_VM_STATE(~/.cache/aingcheck-vm) AINGCHECK_VM_GUEST_ROOT(C:/work/runs)
#   AINGCHECK_SSH(ssh) AINGCHECK_SCP(scp) AINGCHECK_WINPROBE(swift <이 폴더>/cgwindows.swift)
#   AINGCHECK_VM_ARCH(arm64 — x64 면 D-E30 의 x64 JDK 로 gradle) AINGCHECK_VM_GUI_TIMEOUT(600)
# 종료 코드: 명령 자체의 코드(gradle·gui) · 64 사용법 · 69 VM·도구 없음 · 75 잠금을 남이 쥠(기다리지 않는다) · 77 잠금 토큰 불일치
#   78 창이 늘었다 · 79 VM 이 안 꺼졌다 · 142 시한 초과
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VMX="${AINGCHECK_VMX:-$HOME/Virtual Machines.localized/aing-win11-arm.vmwarevm/aing-win11-arm.vmx}"
VMRUN="${AINGCHECK_VMRUN:-/Applications/VMware Fusion.app/Contents/Library/vmrun}"
VM_USER="${AINGCHECK_VM_USER:-tester}"
KEY="${AINGCHECK_VM_KEY:-$HOME/.aing-check-secrets/vm/aingcheck_vm_ed25519}"
LOCK="${AINGCHECK_VM_LOCK:-/tmp/aingcheck-vm.lock}"
STATE="${AINGCHECK_VM_STATE:-$HOME/.cache/aingcheck-vm}"
GUEST_ROOT="${AINGCHECK_VM_GUEST_ROOT:-C:/work/runs}"
SSH_BIN="${AINGCHECK_SSH:-ssh}"
SCP_BIN="${AINGCHECK_SCP:-scp}"
# Sources 는 통째다(W1-e): ui 시험이 Swift 원문(SF 기호 대응·팔레트 대조)과 맥 그림(Sources/check/Resources·CheckMobileKit/Resources/Art — Gradle Sync)을 읽는다. 약 32MB.
DEFAULT_PATHS="multiplatform,contract,Tests/checkTests/Fixtures,Sources"
FUSION_WINDOW_RE='VMware Fusion|vmware-vmx'

log() { printf 'vm.sh: %s\n' "$*" >&2; }
die() { local code=$1; shift; log "$*"; exit "$code"; }

# 시한 실행: perl alarm 으로 exec(백그라운드 & 없이). 시한을 넘기면 142.
run_timeout() {
    local secs=$1; shift
    perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' "$secs" "$@"
}

sha256_hex() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1; else sha256sum | cut -d' ' -f1; fi
}

# ---------- 잠금(mkdir 원자성). 못 잡으면 기다리지 않고 바로 실패한다(A §4-4) ----------
lock_acquire() {
    mkdir -p "$(dirname "$LOCK")"
    if ! mkdir "$LOCK" 2>/dev/null; then
        log "VM 잠금을 다른 작업이 쥐고 있다: $LOCK"
        [ -f "$LOCK/owner" ] && sed 's/^/  /' "$LOCK/owner" >&2
        exit 75
    fi
    local token
    token="$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')"
    printf '%s\n' "$token" >"$LOCK/token"
    {
        printf 'pid=%s\n' "$$"
        printf 'started=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'cwd=%s\n' "$PWD"
        printf 'cmd=%s\n' "${CMDLINE:-}"
    } >"$LOCK/owner"
    AINGCHECK_VM_TOKEN="$token"
    export AINGCHECK_VM_TOKEN
}

lock_require() {
    [ -d "$LOCK" ] || die 77 "잠금이 없다 — 먼저 vm.sh up(또는 batch)"
    local held
    held="$(cat "$LOCK/token" 2>/dev/null || true)"
    [ -n "${AINGCHECK_VM_TOKEN:-}" ] && [ "$held" = "$AINGCHECK_VM_TOKEN" ] || die 77 "잠금 토큰이 맞지 않는다(남의 세션이거나 export 를 안 했다)"
}

lock_release() { rm -rf "$LOCK"; }

state_get() { cat "$LOCK/$1" 2>/dev/null || true; }
state_set() { printf '%s\n' "$2" >"$LOCK/$1"; }

# ---------- vmrun ----------
vmrun() { "$VMRUN" -T fusion "$@"; }

# 손님 자격(-gu/-gp)은 argv 로 비밀번호가 나가므로 기본 금지(§8-1). 하네스 전용 시험 계정(aingvm-*)일 때만 연다.
vmrun_with_guest_creds() {
    [ "${AINGCHECK_VM_ALLOW_GP:-0}" = "1" ] || die 64 "vmrun -gp 는 기본 금지다(SSH 키 + schtasks /IT 를 쓴다). 하네스 전용 계정 실험만 AINGCHECK_VM_ALLOW_GP=1"
    local user="${AINGCHECK_VM_GP_USER:-}"
    [[ "$user" =~ ^aingvm- ]] || die 64 "AINGCHECK_VM_GP_USER 는 하네스 전용 시험 계정(aingvm-*)이어야 한다"
    local svc="${AINGCHECK_VM_GP_KEYCHAIN_SERVICE:-aingcheck-vm-gp}"
    local pass
    pass="$(/usr/bin/security find-generic-password -s "$svc" -a "$user" -w)" || die 69 "키체인 항목 $svc/$user 가 없다"
    log "경고: vmrun -gp 로 손님 비밀번호가 ps 에 보인다(시험 전용 계정)"
    "$VMRUN" -T fusion -gu "$user" -gp "$pass" "$@"
}

vm_listed() { vmrun list 2>/dev/null | grep -Fxq "$VMX"; }
vm_list_count() { vmrun list 2>/dev/null | sed -n '1s/^Total running VMs: *//p'; }

fusion_windows() {
    if [ -n "${AINGCHECK_WINPROBE:-}" ]; then
        # shellcheck disable=SC2086
        $AINGCHECK_WINPROBE --owner-regex "$FUSION_WINDOW_RE" | sed -n 's/.*"count":\([0-9]*\).*/\1/p'
    else
        swift "$HERE/cgwindows.swift" --owner-regex "$FUSION_WINDOW_RE" | sed -n 's/.*"count":\([0-9]*\).*/\1/p'
    fi
}

guest_ip() {
    local ip
    ip="$(run_timeout 180 "$VMRUN" -T fusion getGuestIPAddress "$VMX" -wait 2>/dev/null | tr -d '\r' | tail -1 || true)"
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then printf '%s\n' "$ip"; return 0; fi
    # VMware Tools 가 없으면: vmx 의 MAC 으로 NAT DHCP 임대 파일을 찾는다
    local mac lease="/var/db/vmware/vmnet-dhcpd-vmnet8.leases"
    mac="$(sed -n 's/^ethernet0\.\(generatedAddress\|address\) *= *"\(.*\)"/\2/p' "$VMX" | head -1 | tr 'A-F' 'a-f')"
    if [ -n "$mac" ] && [ -r "$lease" ]; then
        ip="$(awk -v mac="$mac" '/^lease /{ip=$2} tolower($0) ~ "hardware ethernet " mac {last=ip} END{print last}' "$lease")"
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then printf '%s\n' "$ip"; return 0; fi
    fi
    return 1
}

ssh_opts() {
    mkdir -p "$STATE"
    printf '%s\n' -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=8 -o ServerAliveInterval=15 \
        -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$STATE/known_hosts" -o LogLevel=ERROR
}

guest_stdin() {
    local ip opts=()
    ip="$(state_get ip)"
    [ -n "$ip" ] || die 69 "손님 IP 를 모른다(up 을 먼저)"
    while IFS= read -r o; do opts+=("$o"); done < <(ssh_opts)
    "$SSH_BIN" "${opts[@]}" -T "$VM_USER@$ip" "$@"
}

# ssh 는 표준 입력을 읽어 손님에 넘긴다 — batch 의 계획 파일을 삼키지 않게 기본은 /dev/null(러너 예행 run 39598726185 실측).
guest() { guest_stdin "$@" </dev/null; }

# 손님에서 PowerShell 스크립트를 부른다. 인자는 base64 JSON 으로만 넘긴다(인용·주입 방지).
b64_json_args() {
    local json="[" sep="" a
    for a in "$@"; do
        case "$a" in *[$'\001'-$'\037']*) die 64 "인자에 제어 문자가 있다";; esac
        a="${a//\\/\\\\}"
        a="${a//\"/\\\"}"
        json="$json$sep\"$a\""
        sep=","
    done
    printf '%s]' "$json" | base64 | tr -d '\n'
}

guest_ps() {
    local run_dir="$1"; shift
    local script="$run_dir/multiplatform/scripts/vm/winrun.ps1"
    guest "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"${script//\//\\}\" -RunDir \"${run_dir//\//\\}\" $*"
}

wait_ssh() {
    local deadline=$((SECONDS + ${1:-180})) got=""
    while [ $SECONDS -lt $deadline ]; do
        # 손님 기본 셸은 cmd.exe 다 — cmd 를 한 번 더 감싸지 않는다. Win32-OpenSSH 10.x 는 `cmd /c echo ok` 에 `ok"` 를 돌려줬다(run 39596497443).
        got="$(guest "echo ok" 2>/dev/null | tr -d '\r" ' || true)"
        if [ "$got" = "ok" ]; then return 0; fi
        sleep 3
    done
    # 시한이 지나면 마지막 한 번은 오류를 보여 준다(원인 없이 "안 열렸다"만 남지 않게).
    log "마지막 응답: '${got}'"
    guest "echo ok" >&2 || true
    return 1
}

start_vm() {
    local start_args=(start "$VMX" nogui)
    if [ -n "${AINGCHECK_VM_VTPM_KEYCHAIN_SERVICE:-}" ]; then
        # A-X11 빨강 길: Fusion 이 키체인에서 vTPM 비밀번호를 못 읽을 때만. ps 에 보인다는 위험을 알린다.
        local vp
        vp="$(/usr/bin/security find-generic-password -s "$AINGCHECK_VM_VTPM_KEYCHAIN_SERVICE" -w)" || die 69 "vTPM 키체인 항목이 없다"
        log "경고: vmrun -vp 로 VM 암호 비밀번호가 ps 에 보인다(A-X11 대안 길)"
        run_timeout 180 "$VMRUN" -T fusion -vp "$vp" "${start_args[@]}" || return $?
    else
        run_timeout 180 "$VMRUN" -T fusion "${start_args[@]}" || return $?
    fi
}

stop_vm() {
    if vm_listed; then
        run_timeout 60 "$VMRUN" -T fusion stop "$VMX" soft >/dev/null 2>&1 || {
            log "soft 정지 실패 → hard"
            run_timeout 60 "$VMRUN" -T fusion stop "$VMX" hard >/dev/null 2>&1 || true
        }
    fi
    local deadline=$((SECONDS + 30))
    while vm_listed && [ $SECONDS -lt $deadline ]; do sleep 1; done
    ! vm_listed
}

# ---------- 스냅숏(G §8-6, H M-6): 임시 인덱스라 새 파일까지 담고, 실제 인덱스는 건드리지 않는다 ----------
SNAP_TREE="" SNAP_COMMIT="" SNAP_DIGEST="" SNAP_FILES="" SNAP_TAR=""

digest_dir() {
    local dir="$1" list shas
    list="$(mktemp "${TMPDIR:-/tmp}/aingvm-list.XXXXXX")"
    shas="$(mktemp "${TMPDIR:-/tmp}/aingvm-shas.XXXXXX")"
    (cd "$dir" && find . -type f ! -path './.aingcheck-push.json' ! -path './.aingcheck-out/*' -print | sed 's|^\./||' | LC_ALL=C sort) >"$list"
    if grep -q $'\r' "$list"; then rm -f "$list" "$shas"; die 64 "경로에 CR 이 있다"; fi
    (cd "$dir" && git hash-object --no-filters --stdin-paths <"$list") >"$shas"
    SNAP_FILES="$(wc -l <"$list" | tr -d ' ')"
    SNAP_DIGEST="$(paste -d' ' "$shas" "$list" | sha256_hex)"
    rm -f "$list" "$shas"
}

snapshot() {
    local paths_csv="$1" out_tar="$2"
    local top
    top="$(git rev-parse --show-toplevel)" || die 64 "git 저장소 안에서 실행해야 한다"
    local paths=() p
    IFS=',' read -r -a req <<<"$paths_csv"
    for p in "${req[@]}"; do [ -e "$top/$p" ] && paths+=("$p"); done
    [ ${#paths[@]} -gt 0 ] || die 64 "보낼 경로가 하나도 없다: $paths_csv"
    local idx
    idx="$(mktemp "${TMPDIR:-/tmp}/aingvm-index.XXXXXX")"
    rm -f "$idx"
    (
        cd "$top"
        export GIT_INDEX_FILE="$idx"
        git read-tree --empty
        git add -A -- "${paths[@]}"
    )
    SNAP_TREE="$(cd "$top" && GIT_INDEX_FILE="$idx" git write-tree)"
    rm -f "$idx"
    if (cd "$top" && git ls-tree -r "$SNAP_TREE" | awk '$1=="120000"||$1=="160000"{found=1} END{exit !found}'); then
        die 64 "심볼릭 링크·서브모듈은 보내지 않는다(Windows tar 가 다르게 푼다)"
    fi
    SNAP_COMMIT="$(cd "$top" && GIT_AUTHOR_NAME=aingcheck-vm GIT_AUTHOR_EMAIL=vm@aingcheck.invalid \
        GIT_COMMITTER_NAME=aingcheck-vm GIT_COMMITTER_EMAIL=vm@aingcheck.invalid \
        git commit-tree "$SNAP_TREE" -p HEAD -m "aingcheck vm push snapshot")"
    local work
    work="$(mktemp -d "${TMPDIR:-/tmp}/aingvm-snap.XXXXXX")"
    (cd "$top" && git -c core.autocrlf=false archive --format=tar "$SNAP_COMMIT") >"$work/push.tar"
    mkdir "$work/x"
    tar -xf "$work/push.tar" -C "$work/x"
    digest_dir "$work/x"
    printf '{"tree":"%s","commit":"%s","digest":"%s","files":%s,"paths":"%s"}\n' \
        "$SNAP_TREE" "$SNAP_COMMIT" "$SNAP_DIGEST" "$SNAP_FILES" "$(IFS=,; echo "${paths[*]}")" >"$work/.aingcheck-push.json"
    tar -rf "$work/push.tar" -C "$work" .aingcheck-push.json
    rm -rf "$work/x"
    if [ -n "$out_tar" ]; then
        mv "$work/push.tar" "$out_tar"
        SNAP_TAR="$out_tar"
        rm -rf "$work"
    else
        SNAP_TAR="$work/push.tar"
    fi
}

refuse_repo_path() {
    local out="$1" top dir
    dir="$(cd "$(dirname "$out")" 2>/dev/null && pwd)" || die 64 "OUT 의 폴더가 없다: $out"
    top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -z "$top" ] || die 64 "OUT 이 저장소 안이다($top) — 스크래치 경로만 허용한다(기억 agents-leak-files-into-repo)"
}

# ---------- 명령 ----------
cmd_up() {
    [ -x "$VMRUN" ] || die 69 "vmrun 이 없다: $VMRUN (VMware Fusion 미설치 — SETUP-ko.md)"
    [ -f "$VMX" ] || die 69 "VM 이 없다: $VMX (SETUP-ko.md)"
    [ -f "$KEY" ] || die 69 "SSH 키 파일이 없다: $KEY (SETUP-ko.md 의 키 만들기)"
    vm_listed && die 75 "VM 이 이미 켜져 있다 — 다른 세션이 쓰는 중이거나 흘린 것(vm.sh status)"
    lock_acquire
    UP_OK=0
    # up 이 중간에 실패하면 VM 을 끄고 잠금을 푼다(흘림 방지, 기억 agents-leak-load-processes).
    trap 'if [ "${UP_OK:-0}" != 1 ]; then log "up 실패 — 정리"; stop_vm || true; lock_release; fi' EXIT
    local before
    before="$(fusion_windows || echo 0)"
    state_set windows_before "${before:-0}"
    start_vm || die 69 "vmrun start 실패(vTPM 비밀번호를 못 읽었으면 A-X11 대안 길 — SETUP-ko.md)"
    local ip
    ip="$(guest_ip)" || die 69 "손님 IP 를 180초 안에 못 얻었다"
    state_set ip "$ip"
    wait_ssh 180 || die 69 "SSH 가 180초 안에 안 열렸다($VM_USER@$ip)"
    local after
    after="$(fusion_windows || echo 0)"
    [ "${after:-0}" -le "${before:-0}" ] || die 78 "Fusion 창이 늘었다: $before → $after"
    UP_OK=1
    trap - EXIT
    log "up: ip=$ip windows=${before}→$after"
    printf 'export AINGCHECK_VM_TOKEN=%s\n' "$AINGCHECK_VM_TOKEN"
}

cmd_push() {
    lock_require
    local paths="$DEFAULT_PATHS"
    while [ $# -gt 0 ]; do
        case "$1" in
            --paths) paths="$2"; shift 2 ;;
            *) die 64 "push: 모르는 인자 $1" ;;
        esac
    done
    snapshot "$paths" ""
    local run_id run_dir
    run_id="$(date -u +%Y%m%dT%H%M%SZ)-${SNAP_TREE:0:8}"
    run_dir="$GUEST_ROOT/$run_id"
    local win_dir="${run_dir//\//\\}"
    guest_stdin "mkdir $win_dir && tar -xf - -C $win_dir" <"$SNAP_TAR"
    rm -rf "$(dirname "$SNAP_TAR")"
    state_set run_dir "$run_dir"
    state_set tree "$SNAP_TREE"
    log "push: tree=$SNAP_TREE files=$SNAP_FILES → $run_dir"
    guest_ps "$run_dir" -Action verify-tree
}

cmd_gradle() {
    lock_require
    local run_dir
    run_dir="$(state_get run_dir)"
    [ -n "$run_dir" ] || die 64 "push 를 먼저"
    [ $# -gt 0 ] || die 64 "gradle 인자가 없다"
    guest_ps "$run_dir" -Action gradle -Arch "${AINGCHECK_VM_ARCH:-arm64}" -ArgsB64 "$(b64_json_args "$@")"
}

cmd_gui() {
    lock_require
    [ "${1:-}" = "--" ] && shift
    [ $# -gt 0 ] || die 64 "gui -- CMD ARGS…"
    local run_dir
    run_dir="$(state_get run_dir)"
    [ -n "$run_dir" ] || die 64 "push 를 먼저"
    guest_ps "$run_dir" -Action gui -TimeoutSec "${AINGCHECK_VM_GUI_TIMEOUT:-600}" -ArgsB64 "$(b64_json_args "$@")"
}

cmd_shot() {
    lock_require
    local out="${1:-}"
    [ -n "$out" ] || die 64 "shot OUT.png"
    refuse_repo_path "$out"
    local run_dir name
    run_dir="$(state_get run_dir)"
    [ -n "$run_dir" ] || die 64 "push 를 먼저"
    name="shot-$(date -u +%H%M%S).png"
    guest_ps "$run_dir" -Action capture -Out "$name"
    local ip opts=()
    ip="$(state_get ip)"
    while IFS= read -r o; do opts+=("$o"); done < <(ssh_opts)
    "$SCP_BIN" "${opts[@]}" "$VM_USER@$ip:$run_dir/.aingcheck-out/$name" "$out"
}

cmd_info() {
    lock_require
    local run_dir
    run_dir="$(state_get run_dir)"
    [ -n "$run_dir" ] || die 64 "push 를 먼저"
    guest_ps "$run_dir" -Action info
}

cmd_revert() {
    lock_require
    local snap="${1:-}"
    [ -n "$snap" ] || die 64 "revert SNAPSHOT"
    stop_vm || die 79 "revert 전에 VM 이 안 꺼졌다"
    run_timeout 300 "$VMRUN" -T fusion revertToSnapshot "$VMX" "$snap"
    start_vm
    local ip
    ip="$(guest_ip)" || die 69 "revert 뒤 IP 를 못 얻었다"
    state_set ip "$ip"
    rm -f "$LOCK/run_dir"
    wait_ssh 180 || die 69 "revert 뒤 SSH 가 안 열렸다"
}

cmd_down() {
    lock_require
    local code=0
    stop_vm || { log "VM 이 vmrun list 에서 안 빠졌다"; code=79; }
    local before after
    before="$(state_get windows_before)"
    after="$(fusion_windows || echo 0)"
    if [ "${after:-0}" -gt "${before:-0}" ]; then log "Fusion 창이 늘었다: $before → $after"; code=78; fi
    log "down: vmrun list 전체=$(vm_list_count) 우리 VM 실행 중=$(vm_listed && echo 1 || echo 0) 창=${before}→$after"
    lock_release
    return $code
}

batch_exit() {
    local rc=$? d=0
    cmd_down || d=$?
    [ "$rc" -ne 0 ] || rc=$d
    exit "$rc"
}

cmd_batch() {
    local plan="${1:-}"
    [ -f "$plan" ] || die 64 "batch PLAN 파일이 없다"
    # 같은 셸에서 up 을 부른다(명령 치환 안에서는 set -e 가 안 먹는다). 토큰은 lock_acquire 가 export 한다.
    cmd_up >&2
    trap batch_exit EXIT
    local line words n=0
    while IFS= read -r line <&3 || [ -n "$line" ]; do
        line="${line%%#*}"
        [[ "$line" =~ [^[:space:]] ]] || continue
        read -r -a words <<<"$line"
        n=$((n + 1))
        log "batch[$n]: ${words[*]}"
        case "${words[0]}" in
            push | gradle | gui | shot | info | revert) "cmd_${words[0]}" "${words[@]:1}" ;;
            *) die 64 "batch: 허용하지 않는 명령 ${words[0]}" ;;
        esac
    done 3<"$plan"
}

cmd_snapshot() {
    local paths="$DEFAULT_PATHS" out=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --paths) paths="$2"; shift 2 ;;
            --out) out="$2"; shift 2 ;;
            *) die 64 "snapshot: 모르는 인자 $1" ;;
        esac
    done
    snapshot "$paths" "$out"
    printf '{"tree":"%s","commit":"%s","digest":"%s","files":%s,"tar":"%s"}\n' "$SNAP_TREE" "$SNAP_COMMIT" "$SNAP_DIGEST" "$SNAP_FILES" "$SNAP_TAR"
    [ -n "$out" ] || rm -rf "$(dirname "$SNAP_TAR")"
}

cmd_status() {
    if [ -d "$LOCK" ]; then
        printf 'lock: held\n'; sed 's/^/  /' "$LOCK/owner" 2>/dev/null || true
    else
        printf 'lock: free\n'
    fi
    if [ -x "$VMRUN" ]; then
        printf 'vmrun list total: %s\nour vm running: %s\n' "$(vm_list_count)" "$(vm_listed && echo yes || echo no)"
    else
        printf 'vmrun: 없음(%s)\n' "$VMRUN"
    fi
}

cmd_unlock_stale() {
    [ -d "$LOCK" ] || { log "잠금이 없다"; return 0; }
    local pid
    pid="$(sed -n 's/^pid=//p' "$LOCK/owner" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= | grep -q 'vm.sh'; then
        die 75 "잠금 주인(pid $pid, vm.sh)이 살아 있다"
    fi
    if [ -x "$VMRUN" ] && vm_listed; then die 75 "VM 이 켜져 있다 — 쓰는 중일 수 있다(조정자만 reap)"; fi
    lock_release
    log "낡은 잠금을 지웠다"
}

cmd_reap() {
    [ "${1:-}" = "--i-am-coordinator" ] || die 64 "reap 은 조정자만: vm.sh reap --i-am-coordinator"
    stop_vm || die 79 "VM 이 안 꺼졌다"
    lock_release
    log "reap: VM 정지·잠금 해제"
}

main() {
    CMDLINE="$*"
    local cmd="${1:-}"
    [ -n "$cmd" ] || die 64 "usage: vm.sh up|push|gradle|gui|shot|info|revert|down|batch|snapshot|status|unlock-stale|reap"
    shift
    case "$cmd" in
        up) cmd_up "$@" ;;
        push) cmd_push "$@" ;;
        gradle) cmd_gradle "$@" ;;
        gui) cmd_gui "$@" ;;
        shot) cmd_shot "$@" ;;
        info) cmd_info "$@" ;;
        revert) cmd_revert "$@" ;;
        down) cmd_down "$@" ;;
        batch) cmd_batch "$@" ;;
        snapshot) cmd_snapshot "$@" ;;
        status) cmd_status ;;
        unlock-stale) cmd_unlock_stale ;;
        reap) cmd_reap "$@" ;;
        *) die 64 "모르는 명령: $cmd" ;;
    esac
}

main "$@"
