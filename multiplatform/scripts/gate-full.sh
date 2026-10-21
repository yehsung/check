#!/usr/bin/env bash
# 전체 게이트(A§4-6, §4-1 출시 기준의 자동 몫). 빠른 게이트 + slow 태그 + Android lint + assembleRelease(.invalid) + 데스크톱 jar,
# 그리고 기기 계측(에뮬레이터)을 더한다. 봉인·카나리아·홈 잔재 판정은 gate-fast.sh 와 같은 코드를 탄다.
#
#   multiplatform/scripts/gate-full.sh
#
# 기기 계측: multiplatform/scripts/emu.sh instrumented(api36 AVD · 포트 5560 · 봉인 기본 → 계측 시험 → 끄기, 종료 코드 전달).
#   emu.sh 가 없으면 실패한다 — 조용히 건너뛰지 않는다.
#   일부러 빼려면 AINGCHECK_ALLOW_NO_DEVICE=1. 그때는 **언제나** "기기 계측 빠짐"을 찍는다(이 실행은 기기 몫을 재지 않았다).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

skip_device=0
if [[ "${AINGCHECK_GATE_INNER:-}" != "1" ]]; then
  if [[ "${AINGCHECK_ALLOW_NO_DEVICE:-}" == "1" ]]; then
    skip_device=1
    if [[ -x "$HERE/emu.sh" ]]; then
      echo "gate-full: 기기 계측 빠짐(AINGCHECK_ALLOW_NO_DEVICE=1 — emu.sh instrumented 를 부르지 않는다)" >&2
    else
      echo "gate-full: 기기 계측 빠짐(emu.sh 없음, AINGCHECK_ALLOW_NO_DEVICE=1)" >&2
    fi
  elif [[ ! -x "$HERE/emu.sh" ]]; then
    echo "gate-full: multiplatform/scripts/emu.sh 가 없다(W0-f). 기기 계측 없이 돌리려면 AINGCHECK_ALLOW_NO_DEVICE=1" >&2
    exit 2
  fi
fi

# JVM·조립 몫은 gate-fast.sh 가 봉인 아래에서 한다(KIND=full 이면 slow·lint·assembleRelease·jar 를 더한다).
AINGCHECK_GATE_KIND=full "$HERE/gate-fast.sh" "$@"

# 기기 계측(봉인은 emu.sh 가 건다 — A-X7 결과에 따른다). 에뮬레이터 수명은 emu.sh 가 쥔다.
if [[ "$skip_device" -eq 1 ]]; then
  echo "gate-full: 기기 계측 빠짐 — JVM·조립 몫만 초록이다" >&2
  exit 0
fi
set +e
"$HERE/emu.sh" instrumented
device_rc=$?
set -e
echo "gate-full: device-exit=$device_rc"
exit "$device_rc"
