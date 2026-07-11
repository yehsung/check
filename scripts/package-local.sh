#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/.env.local" ]]; then
  set -a
  source "$ROOT/.env.local"
  set +a
fi

if [[ -z "${CHECK_SUPABASE_ANON_KEY:-}" ]]; then
  echo "CHECK_SUPABASE_ANON_KEY is required. Add it to .env.local before packaging." >&2
  exit 1
fi

APP_PATH="$("$ROOT/scripts/build-local.sh" | tail -n 1)"
mkdir -p "$ROOT/dist"
rm -f "$ROOT/dist/check.zip"
ditto -c -k --keepParent "$APP_PATH" "$ROOT/dist/check.zip"

if command -v create-dmg >/dev/null 2>&1; then
  rm -f "$ROOT/dist/check.dmg"
  create-dmg "$APP_PATH" "$ROOT/dist" >/dev/null
fi

echo "$ROOT/dist/check.zip"
