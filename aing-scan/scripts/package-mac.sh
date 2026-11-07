#!/bin/bash
# 맥 판 스캐너 묶음: 유니버설(arm64+x86_64) 릴리스 빌드 → (선택) Developer ID 서명 + 공증 → aing-scan-macos-universal.tar.gz + .sha256
#
# 쓰는 법: aing-scan/scripts/package-mac.sh <출력폴더>
#   AING_SCAN_ANON_KEY  공개 anon 키(환경 변수로만 — 인자·출력 금지). 없으면 키 없는 개발판이 된다.
#   SIGN=1              서명·공증까지(CODESIGN_IDENTITY 없으면 키체인의 첫 Developer ID Application). 공증 프로파일 check-notary.
#
# 저장소 파일은 바꾸지 않는다 — 패키지를 임시 사본으로 복사해 그 사본의 BuildConfig 에 키를 넣고 빌드한다.
# 임시 사본은 지우지 않는다(출력폴더 아래 work-<시각>).
set -euo pipefail

OUT="${1:?출력 폴더를 주세요}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"          # aing-scan/
REPO="$(cd "$HERE/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$OUT/work-$STAMP"
mkdir -p "$WORK"

# 사본: 공유 파일 링크(../Sources/CheckCore)가 그대로 풀리도록 저장소 구조째(aing-scan + Sources/CheckCore) 복사한다.
mkdir -p "$WORK/repo/Sources"
cp -R "$REPO/Sources/CheckCore" "$WORK/repo/Sources/CheckCore"
rsync -a --exclude .build --exclude .swiftpm "$HERE/" "$WORK/repo/aing-scan/"

if [ -n "${AING_SCAN_ANON_KEY:-}" ]; then
  # 키를 사본의 상수에 넣는다(파이썬이 환경 변수에서 읽는다 — 셸 인자로 넘기지 않는다).
  python3 - "$WORK/repo/aing-scan/Sources/aing-scan/BuildConfig.swift" <<'PY'
import os, sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
key = os.environ["AING_SCAN_ANON_KEY"].strip()
assert key and '"' not in key and "\\" not in key
old = "static let embeddedAnonKey: String? = nil"
assert t.count(old) == 1
open(p, "w", encoding="utf-8").write(t.replace(old, 'static let embeddedAnonKey: String? = "' + key + '"'))
PY
  echo "키: 넣음"
else
  echo "키: 없음(개발판)"
fi

cd "$WORK/repo/aing-scan"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/aing-scan"
lipo -info "$BIN"
mkdir -p "$WORK/stage"
cp "$BIN" "$WORK/stage/aing-scan"

if [ "${SIGN:-0}" = "1" ]; then
  IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' | head -n 1)}"
  [ -n "$IDENTITY" ] || { echo "Developer ID Application 인증서가 없습니다" >&2; exit 1; }
  codesign --force --options runtime --timestamp --identifier io.aingcheck.scan --sign "$IDENTITY" "$WORK/stage/aing-scan"
  codesign --verify --strict "$WORK/stage/aing-scan"
  ditto -c -k "$WORK/stage/aing-scan" "$WORK/notarize.zip"
  xcrun notarytool submit "$WORK/notarize.zip" --keychain-profile check-notary --wait
fi

cd "$WORK/stage"
tar -czf "$OUT/aing-scan-macos-universal.tar.gz" aing-scan
cd "$OUT"
shasum -a 256 aing-scan-macos-universal.tar.gz > aing-scan-macos-universal.tar.gz.sha256
ls -l "$OUT"/aing-scan-macos-universal.tar.gz*
