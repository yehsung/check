#!/bin/bash
# 시험용 가짜 창 탐침: $FAKE_WINDOWS 파일의 숫자를 창 수로 낸다(없으면 0).
n="$(cat "${FAKE_WINDOWS:-/nonexistent}" 2>/dev/null || echo 0)"
printf '{"count":%s,"byOwner":{}}\n' "$n"
