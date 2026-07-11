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

# zip에 앱 + 설치 도우미(격리 해제 포함)를 함께 담는다.
STAGE="$ROOT/dist/.stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/check"
cp -R "$APP_PATH" "$STAGE/check/"
cp "$ROOT/scripts/install-helper.command" "$STAGE/check/설치하기.command"
chmod +x "$STAGE/check/설치하기.command"
ditto -c -k --keepParent "$STAGE/check" "$ROOT/dist/check.zip"
rm -rf "$STAGE"

if command -v create-dmg >/dev/null 2>&1; then
  rm -f "$ROOT/dist/check.dmg"
  create-dmg "$APP_PATH" "$ROOT/dist" >/dev/null
fi

echo "$ROOT/dist/check.zip"
