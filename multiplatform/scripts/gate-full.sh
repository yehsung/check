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

# 출시 판(R8) 점검(§4-1 "릴리스(R8) 스모크" · W6-a 패치 03): 운영 값 없는 dryrun. 출시 스크립트가 R8 AAB + 같은 번들의 보편 APK 를
# 만들고(sandbox-exec 봉인 · --offline · 그 자리에서 만든 버리는 키) 산출물 판정(badging 패키지·판 번호·targetSdk·권한 = 허용 목록 ·
# AD_ID 0 · AAB·APK dex 의 빌드 도장·판돈 깃발·.invalid 기준선 · 비밀 표식·키 파일·Fixtures 0 · 서명 지문 · .so 허용 목록·16 KB ·
# 진열장 클래스·문자열 0 · 크기 예산)을 한다.
# 런처 아이콘 판정(badging.icon)도 넘기지 않는다 — 8b 에서 적응형 아이콘이 들어와 --allow-no-icon 을 없앴다.
# 맥에서만 돈다: 봉인(sandbox-exec)을 거는 곳이 맥이다. Linux(mp-nightly gate-full-linux)는 이 단계 밖이 봉인 밖이라 R8 빌드를 하지 않고
# **언제나** 'release-dryrun=not-run(linux)'를 찍는다(K12 — 봉인 밖 Gradle 금지. 출시 판은 맥 몫, E§11).
MP_DIR="$(cd "$HERE/.." && pwd)"
rel_out="$MP_DIR/build/gate/release-dryrun"
rel_rc=0
rel_ran=0
if [[ "$(uname -s)" == Darwin ]]; then
  rel_ran=1
  rm -rf "$rel_out"
  mkdir -p "$MP_DIR/build/gate"
  # 판돈 깃발은 커밋된 version.properties 를 따른다(androidDuelsFromBuild=N 이 있고 androidVersionCode ≥ N 이면 on, 아니면 off) —
  # 출시될 판과 같은 변종을 R8 로 굽는다. 출시 도구의 이중 확인은 커밋 값과 어긋난 인자를 거부하므로(8c: 그 줄이 들어오자
  # 인자 없는 dryrun 이 '거부'로 빨갛게 됐다) 여기서 고정값을 쓰지 않는다. 값이 이상하면 off 를 넘겨 출시 도구가 그 이유로 거부하게 둔다.
  rel_duels="$(python3 -I - "$MP_DIR/version.properties" <<'PY' 2>/dev/null || echo off
import sys
vp = {}
for line in open(sys.argv[1], encoding="utf-8"):
    s = line.strip()
    if s and not s.startswith(("#", "!")) and "=" in s:
        k, v = s.split("=", 1)
        vp[k.strip()] = v.strip()
try:
    on = "androidDuelsFromBuild" in vp and int(vp["androidVersionCode"]) >= int(vp["androidDuelsFromBuild"])
except ValueError:
    on = False
print("on" if on else "off")
PY
)"
  set +e
  "$HERE/release-android.sh" dryrun --duels "$rel_duels" --allow-dirty --out "$rel_out" > "$MP_DIR/build/gate/release-dryrun.log" 2>&1
  rel_rc=$?
  set -e
  echo "gate-full: release-dryrun duels=$rel_duels(커밋된 version.properties 를 따름)"
  grep -E '^release-android: (FAIL|거부|verify checks=|dryrun ok)' "$MP_DIR/build/gate/release-dryrun.log" | sed 's/^/gate-full: /' || true
  echo "gate-full: release-dryrun-exit=$rel_rc · log=$MP_DIR/build/gate/release-dryrun.log"
else
  echo "gate-full: release-dryrun=not-run($(uname -s) — 출시 R8 판·스모크는 맥 몫: 이 OS 에서는 봉인 밖 R8 빌드를 하지 않는다)"
fi

# 기기 계측(봉인은 emu.sh 가 건다 — A-X7 결과에 따른다). 에뮬레이터 수명은 emu.sh 가 쥔다.
if [[ "$skip_device" -eq 1 ]]; then
  echo "gate-full: 기기 계측 빠짐 — JVM·조립·출시 판정 몫만 잰다(R8 판 기기 스모크도 빠짐)" >&2
  exit "$rel_rc"
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
# R8 판 기기 스모크(W6-a 패치 03): 위 dryrun 의 보편 APK 를 봉인 에뮬레이터에 깔고 띄운다 — 6초 뒤 살아 있음 · FATAL 0 ·
# 조립 지점 로그(variant=RELEASE firebase=SKIP_NO_CONFIG) · 셸 onCreate · 깔린 versionCode = 영수증의 판 번호 ·
# 깔린 base.apk 의 SHA-256 = 이번 dryrun APK(installedApk — 판 번호가 늘 같은 dryrun 에서 "이번 빌드"를 가르는 것은 이것이다). 포트는 위 단계와 같다.
if [[ $rel_ran -eq 0 ]]; then
  smoke_rc=0
  echo "gate-full: device[release-smoke]=not-run($(uname -s) — 출시 dryrun 이 돌지 않았다)"
elif [[ $rel_rc -eq 0 ]]; then
  rel_apk="$(ls "$rel_out"/*-universal.apk 2>/dev/null | head -n 1)"
  rel_vc="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["versionCode"])' "$rel_out/receipt.json" 2>/dev/null || true)"
  set +e
  if [[ -n "$rel_apk" && "$rel_vc" =~ ^[0-9]+$ ]]; then
    "$HERE/release-android.sh" smoke --apk "$rel_apk" --port "${AINGCHECK_GATE_EMU_PORT:-5560}" --expect-firebase SKIP_NO_CONFIG --version-code "$rel_vc"
    smoke_rc=$?
  else
    echo "gate-full: R8 판 기기 스모크 못 함 — dryrun 산출물·영수증이 없다(apk='$rel_apk' versionCode='$rel_vc')" >&2
    smoke_rc=1
  fi
  set -e
else
  smoke_rc=1
  echo "gate-full: R8 판 기기 스모크 못 함 — dryrun 이 빨갛다(exit $rel_rc)" >&2
fi
echo "gate-full: device[release-smoke]-exit=$smoke_rc"
if [[ $smoke_rc -ne 0 && $device_rc -eq 0 ]]; then device_rc=$smoke_rc; fi
# 시험 dex 운영 주소 0(§4-1): 계측이 만든 debug APK 와 시험 APK 의 dex 에 운영 프로젝트 주소 문형이 없고 assets Fixtures 가 없다.
for test_apk in "$MP_DIR/androidApp/build/outputs/apk/debug/androidApp-debug.apk" \
                "$MP_DIR/androidApp/build/outputs/apk/androidTest/debug/androidApp-debug-androidTest.apk"; do
  if [[ ! -f "$test_apk" ]]; then
    echo "gate-full: 시험 APK 가 없다(계측이 만들지 않았다): $test_apk" >&2
    if [[ $device_rc -eq 0 ]]; then device_rc=1; fi
    continue
  fi
  set +e
  bash "$HERE/apk-content-check.sh" "$test_apk" | sed 's/^/gate-full: /'
  tc_rc=${PIPESTATUS[0]}
  set -e
  echo "gate-full: test-dex[$(basename "$test_apk")]-exit=$tc_rc"
  if [[ $tc_rc -ne 0 && $device_rc -eq 0 ]]; then device_rc=$tc_rc; fi
done
if [[ $rel_rc -ne 0 && $device_rc -eq 0 ]]; then device_rc=$rel_rc; fi
echo "gate-full: device-exit=$device_rc"
exit "$device_rc"
