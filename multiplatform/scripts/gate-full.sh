#!/usr/bin/env bash
# 전체 게이트(A§4-6, §4-1 출시 기준의 자동 몫). 빠른 게이트 + slow 태그 + Android lint + assembleRelease(.invalid) + 데스크톱 jar,
# 그리고 기기 계측(에뮬레이터)을 더한다. 봉인·카나리아·홈 잔재 판정은 gate-fast.sh 와 같은 코드를 탄다.
#
#   multiplatform/scripts/gate-full.sh
#
# 기기 계측: multiplatform/scripts/emu.sh instrumented(봉인 기본 → 계측 시험 → 끄기, 종료 코드 전달). 세 단계를 차례로 다 돈다:
#   ① androidApp(api36 · :androidApp:connectedDebugAndroidTest — emu.sh 기본값)
#   ② core/rules 골든을 ART 에서(api26 · :core:rules:connectedAndroidDeviceTest) ③ 같은 시험을 api36 에서.
#   ②③ 은 G §8-17 2 (a) 의 API 별 그래핌 잠금(GraphemeArtLocks)의 **값**을 재는 유일한 자리다 — JVM 은 경계 모양만 재고 CI 는 기기를
#   돌지 않는다(6차 c-fold 검증 지적: 손으로 돌리던 단계라 잠금 표를 잘못 적어도 모든 게이트가 초록이었다). NFC · 범위 표 · 날짜 · 자연 정렬도 같이 돈다.
#   포트는 emu.sh 기본(5560 — 통합 자리). 갈래가 자기 포트로 돌리려면 AINGCHECK_GATE_EMU_PORT=<포트>(세 단계 모두 그 포트).
#   한 단계가 빨개도 나머지를 돌고, 처음 빨간 단계의 종료 코드로 끝낸다(단계마다 device[이름]-exit 줄).
#   emu.sh 가 없으면 실패한다 — 조용히 건너뛰지 않는다.
#   일부러 빼려면 AINGCHECK_ALLOW_NO_DEVICE=1. 그때는 **언제나** "기기 계측 빠짐"을 찍는다(이 실행은 기기 몫을 재지 않았다).
# Swift 골든 비교(맥에서만, G §4-1 "Swift 쪽" · contract/README.md §3): scripts/golden-export.sh 비교 모드를 먼저 돈다.
#   맥 전체 스위트(swift test)만으로는 GoldenExport 개수·건너뜀·스위트 밖 시험·영수증 고아를 재지 않는다 — 그 잠금은 이 스크립트에만 있다.
#   golden-export.sh 는 자기 sandbox-exec 봉인을 건다. gate-fast.sh 의 봉인 안에서 부르면 겹 봉인으로 SwiftPM 이 막히므로 봉인 밖 단계에서 부른다.
#   일부러 빼려면 AINGCHECK_ALLOW_NO_SWIFT_GOLDEN=1. 그때는 **언제나** "Swift 골든 비교 빠짐"을 찍는다.
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

if [[ "${AINGCHECK_GATE_INNER:-}" != "1" && "$(uname -s)" == Darwin ]]; then
  if [[ "${AINGCHECK_ALLOW_NO_SWIFT_GOLDEN:-}" == "1" ]]; then
    echo "gate-full: Swift 골든 비교 빠짐(AINGCHECK_ALLOW_NO_SWIFT_GOLDEN=1 — scripts/golden-export.sh 를 부르지 않는다)" >&2
  else
    golden_export="$(cd "$HERE/../.." && pwd)/scripts/golden-export.sh"
    [[ -x "$golden_export" ]] || { echo "gate-full: scripts/golden-export.sh 가 없다(W0-b). 빼려면 AINGCHECK_ALLOW_NO_SWIFT_GOLDEN=1" >&2; exit 2; }
    set +e
    "$golden_export"
    golden_rc=$?
    set -e
    echo "gate-full: golden-export-exit=$golden_rc"
    if [[ $golden_rc -ne 0 ]]; then
      echo "gate-full: Swift 골든 비교 모드가 빨갛다(scripts/golden-export.sh exit $golden_rc) — JVM·기기 몫을 돌리지 않고 멈춘다" >&2
      exit 1
    fi
  fi
fi

# JVM·조립 몫은 gate-fast.sh 가 봉인 아래에서 한다(KIND=full 이면 slow·lint·assembleRelease·jar 를 더한다).
AINGCHECK_GATE_KIND=full "$HERE/gate-fast.sh" "$@"

# 기기 계측(봉인은 emu.sh 가 건다 — A-X7 결과에 따른다). 에뮬레이터 수명은 emu.sh 가 쥔다.
if [[ "$skip_device" -eq 1 ]]; then
  echo "gate-full: 기기 계측 빠짐 — JVM·조립 몫만 초록이다" >&2
  exit 0
fi
port_args=()
if [[ -n "${AINGCHECK_GATE_EMU_PORT:-}" ]]; then
  [[ "$AINGCHECK_GATE_EMU_PORT" =~ ^[0-9]+$ ]] || { echo "gate-full: AINGCHECK_GATE_EMU_PORT 는 숫자다('$AINGCHECK_GATE_EMU_PORT')" >&2; exit 2; }
  port_args=(--port "$AINGCHECK_GATE_EMU_PORT")
fi
device_rc=0
run_device() { # 단계 이름 · emu.sh instrumented 인자…
  local name="$1"; shift
  local rc
  set +e
  "$HERE/emu.sh" instrumented "${port_args[@]+"${port_args[@]}"}" "$@"
  rc=$?
  set -e
  echo "gate-full: device[$name]-exit=$rc"
  if [[ $rc -ne 0 && $device_rc -eq 0 ]]; then device_rc=$rc; fi
}
run_device androidApp-api36
run_device rules-api26 --avd aingcheck-api26 --task :core:rules:connectedAndroidDeviceTest
run_device rules-api36 --avd aingcheck-api36 --task :core:rules:connectedAndroidDeviceTest
echo "gate-full: device-exit=$device_rc"
exit "$device_rc"
