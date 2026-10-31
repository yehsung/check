#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/.env.local" ]]; then
  set -a
  source "$ROOT/.env.local"
  set +a
fi

APP_PATH="$("$ROOT/scripts/build-local.sh" | tail -n 1)"
# 로컬 빌드도 번들 ID 가 kingcheck 이라, 설치된 앱이 떠 있으면 하나만 실행 판정(v0.3.69)이 로컬 빌드를 양보시킨다.
# 인자 영역(-키 값)으로 탈출구를 이 실행에만 켠다 — `defaults write` 로 켜면 설치된 앱의 판정까지 꺼진다.
# 탈출구를 켠 실행은 자기를 check.singleInstance.exemptInstances 에 적어, 나중에 뜬 설치본(brew 재실행 · 로그인)도 이쪽에 양보하지 않는다.
"$APP_PATH/Contents/MacOS/check" -check.allowMultipleInstances YES
