#!/bin/bash
# check 설치 도우미 — 더블클릭(안 열리면 우클릭→열기)하면 앱을 설치하고 격리 속성을 해제합니다.
set -e
cd "$(dirname "$0")"
if [ ! -d "check.app" ]; then
  echo "check.app 이 이 파일과 같은 폴더에 없습니다. 압축을 풀고 다시 실행해 주세요."
  read -p "엔터를 누르면 닫힙니다."
  exit 1
fi
echo "check.app 을 응용 프로그램 폴더로 복사합니다..."
rm -rf "/Applications/check.app"
cp -R "check.app" "/Applications/"
echo "보안 격리 속성을 해제합니다..."
xattr -dr com.apple.quarantine "/Applications/check.app" 2>/dev/null || true
echo "설치 완료! 앱을 실행합니다."
open "/Applications/check.app"
