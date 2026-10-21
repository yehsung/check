#!/bin/bash
# 시험용 가짜 vmrun. 상태 파일 $FAKE_VMRUN_STATE(running|stopped), 호출 기록 $FAKE_VMRUN_LOG.
# 맥 자가 시험(test-vm-sh.sh)과 Windows 러너 예행(mp-windows-spike.yml vm-rehearsal)이 같이 쓴다.
set -u
st="${FAKE_VMRUN_STATE:?FAKE_VMRUN_STATE}"
printf '%s\n' "$*" >>"${FAKE_VMRUN_LOG:-/dev/null}"
[ "${1:-}" = "-T" ] && shift 2
while [ "${1:-}" = "-vp" ] || [ "${1:-}" = "-gu" ] || [ "${1:-}" = "-gp" ]; do shift 2; done
cmd="${1:-}"
shift || true
case "$cmd" in
    list)
        if [ "$(cat "$st" 2>/dev/null)" = running ]; then
            echo "Total running VMs: 1"
            cat "$st.vmx"
        else
            echo "Total running VMs: 0"
        fi
        ;;
    start)
        if [ "${FAKE_VMRUN_START_FAIL:-0}" = 1 ]; then echo "Error: The operation was canceled"; exit 1; fi
        echo running >"$st"
        printf '%s\n' "$1" >"$st.vmx"
        ;;
    stop) echo stopped >"$st" ;;
    getGuestIPAddress)
        if [ "${FAKE_VMRUN_NOIP:-0}" = 1 ]; then echo "Error: The VMware Tools are not running in the virtual machine"; exit 1; fi
        echo "${FAKE_VMRUN_IP:-192.0.2.10}"
        ;;
    revertToSnapshot)
        echo stopped >"$st"
        printf '%s\n' "${2:-}" >"$st.reverted"
        ;;
    *) echo "fake vmrun: 모르는 명령 $cmd" >&2; exit 1 ;;
esac
