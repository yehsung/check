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
"$APP_PATH/Contents/MacOS/check"
