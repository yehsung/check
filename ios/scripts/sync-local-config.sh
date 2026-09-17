#!/usr/bin/env bash
# .env.local 의 CHECK_SUPABASE_ANON_KEY → ios/Config/Local.xcconfig (gitignore). 키 값은 출력하지 않는다.
#
# 사용: ios/scripts/sync-local-config.sh [.env.local 경로]
#   경로를 안 주면 이 저장소 루트의 .env.local 을 읽는다(워크트리라면 메인 체크아웃의 .env.local 경로를 인자로 준다).
# 맥 scripts/build-local.sh 가 같은 파일에서 같은 키를 읽어 CheckConfig.plist 를 만드는 것과 같은 원천이다.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ENV_FILE="${1:-$ROOT/.env.local}"
OUT="$ROOT/ios/Config/Local.xcconfig"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE 이 없다" >&2
  exit 1
fi

KEY="$(grep -E '^CHECK_SUPABASE_ANON_KEY=' "$ENV_FILE" | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '[:space:]')"
if [[ -z "$KEY" ]]; then
  echo "error: $ENV_FILE 에 CHECK_SUPABASE_ANON_KEY 가 없다" >&2
  exit 1
fi
# xcconfig 는 // 뒤를 주석으로 버린다. anon 키(JWT, base64url)에는 / 가 없지만, 형식이 바뀌면 조용히 잘리지 않게 막는다.
if [[ "$KEY" == *"//"* ]]; then
  echo "error: 키에 // 가 들어 있어 xcconfig 로 옮길 수 없다" >&2
  exit 1
fi

umask 077
printf '// 생성물(ios/scripts/sync-local-config.sh) — 커밋 금지\nCHECK_SUPABASE_ANON_KEY = %s\n' "$KEY" > "$OUT"
echo "ios/Config/Local.xcconfig 를 만들었다(키 길이 ${#KEY})"
