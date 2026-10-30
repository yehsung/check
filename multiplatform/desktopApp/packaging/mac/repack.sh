#!/usr/bin/env bash
# 원본: 없음 — 맥 출시 규약(scripts/release-brew.sh:322-396 산출물 안 build 대조 · package-notarized.sh 가 종료 코드를 삼킨 일)을
# Windows 운영 판 "맥 다시 싸기"로 옮긴다(W6-b2 · xplat-w1/briefs/package.md §5 W6-b2 · 길 (나) 변형 B · D-E31).
#
# 사용
#   repack.sh build --ci DIR --prod-config FILE --out DIR [--identity store|dev] [--arch x64,arm64] [--dry]
#                   [--ci-run ID] [--gradle-project-cache DIR] [--makemsix PATH]
#       DIR = mp-release-windows 실행 산출물(gh run download — AingCheck_<ver>_<arch>.layout.zip · .receipt.json).
#       그 실행의 커밋(영수증 gitSha = HEAD)을 꺼낸 깨끗한 트리에서: 봉인(sandbox-exec, --offline) 아래
#       -Paingcheck.desktop.releaseAssembly=true 로 desktopApp jar 를 다시 빌드(영수증의 buildTime·gitSha 그대로) →
#       CI jar 와 비교해 generated/ProdConfig 계열만 바뀌었을 때만 같은 이름으로 교체 → makemsix pack(x64·arm64) →
#       makemsix unpack(블록맵 검증) → 바꾼 jar 를 뺀 runtime+app 지문 = CI 영수증. --dry 는 장부에 쓰지 않는 리허설.
#       장부(versions.tsv)에 오르는 판은 store 신원(U7 전에는 자리표시라 거부)·.invalid 아닌 운영 host 만.
#   repack.sh jar-diff --ci-jar A --mac-jar B [--expect prod-only|same]   두 jar 의 항목 차이(타임스탬프 무시)
#   repack.sh pack --ci DIR --jar JAR --out DIR [--arch x64,arm64]
#       뒷몫만 리허설: JAR 가 CI jar 와 허용 목록(generated/) 밖 차이가 없을 때 dev 신원 그대로 싸고 풀어 영수증과 대조한다(장부·운영 값 없음).
#   repack.sh publish-sql --build N --min-build M [--notes TEXT]
#       장부의 그 줄로 client_publish_release_v2('windows', …) SQL 한 줄을 찍기만 한다(release-android.sh publish-sql 선례 ·
#       Windows 는 profiles.app_build 를 PATCH 하지 않는다 ★6). 실행은 조정자가 사용자와 함께.
#   repack.sh tools [--src DIR]
#       makemsix 를 microsoft/msix-packaging@25a65f5c 소스에서 makemac.sh -arch arm64 --pack 으로 지어 저장소 밖
#       ~/.aing-check-tools/msix-packaging-25a65f5c/{bin/makemsix,lib/libmsix.dylib} 에 둔다(rpath 를 ../lib 로 고치고 ad-hoc 재서명).
#       sha256 을 찍는다 — repack.py MAKEMSIX_PIN 과 다르면 종료 1(망을 쓰는 유일한 명령 — GitHub 만).
#   repack.sh self-test   가짜 zip 산출물·가짜 Gradle·가짜 makemsix 로 거부·판정·장부·명령줄을 잰다(망·Gradle·makemsix 없음).
#
# 입력(저장소 밖) --prod-config FILE: Java properties, 키는 Gradle 속성 이름 그대로 aingcheck.prod.{supabaseUrl,supabaseAnonKey}.
#   **둘 중 하나라도 없으면 종료 2.** Gradle 에는 환경 변수 ORG_GRADLE_PROJECT_aingcheck.prod.* 로만 넘긴다(argv·로그·장부에 키 0 ★3).
# 종료 코드: 0 초록 · 1 빌드·판정 실패 · 2 입력 거부.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${AINGCHECK_PYTHON:-python3}"
die() { echo "repack: 거부 — $*" >&2; exit 2; }

cmd="${1:-}"
[[ -n "$cmd" ]] || die "명령이 없다(build|pack|jar-diff|publish-sql|tools|self-test)"
shift

case "$cmd" in
  self-test)
    exec "$PY" -I "$HERE/repack_selftest.py" "$@"
    ;;
  build|pack|jar-diff|publish-sql)
    exec "$PY" -I "$HERE/repack.py" "$cmd" "$@"
    ;;
  tools)
    commit=25a65f5c1690930813bcc10cdf1d59fa865f2bb1
    home="$HOME/.aing-check-tools/msix-packaging-${commit:0:8}"
    src="$home/src"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --src) src="${2:?}"; shift 2 ;;
        *) die "tools: 모르는 인자 $1" ;;
      esac
    done
    [[ "$(uname -s)" == Darwin ]] || die "tools 는 맥에서만"
    if [[ ! -d "$src/.git" ]]; then
      git clone -q --filter=blob:none https://github.com/microsoft/msix-packaging.git "$src"
    fi
    git -C "$src" checkout -q "$commit"
    [[ "$(git -C "$src" rev-parse HEAD)" == "$commit" ]] || die "msix-packaging HEAD 가 $commit 이 아니다"
    if [[ ! -x "$src/.vs/bin/makemsix" ]]; then
      (cd "$src" && ./makemac.sh -arch arm64 --pack)
    fi
    mkdir -p "$home/bin" "$home/lib"
    cp "$src/.vs/bin/makemsix" "$home/bin/makemsix"
    cp "$src/.vs/lib/libmsix.dylib" "$home/lib/libmsix.dylib"
    old_rpath="$(otool -l "$home/bin/makemsix" | awk '/LC_RPATH/{f=1} f&&/ path /{print $2; exit}')"
    [[ -n "$old_rpath" ]] && install_name_tool -delete_rpath "$old_rpath" "$home/bin/makemsix"
    install_name_tool -add_rpath "@executable_path/../lib" "$home/bin/makemsix"
    codesign -f -s - "$home/bin/makemsix" >/dev/null 2>&1
    codesign -f -s - "$home/lib/libmsix.dylib" >/dev/null 2>&1
    "$home/bin/makemsix" >/dev/null 2>&1 || true  # 도움말 — 아래 sha 비교가 판정
    exec "$PY" -I -c '
import sys; sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import repack, release_win as rw
home = repack.Path(sys.argv[2])
got = {rel: rw.sha256_file(home / rel) for rel in repack.MAKEMSIX_PIN}
for rel, sha in got.items():
    print(f"{rel}\t{sha}")
sys.exit(0 if got == repack.MAKEMSIX_PIN else 1)
' "$HERE" "$home"
    ;;
  *)
    die "모르는 명령 $cmd(build|pack|jar-diff|publish-sql|tools|self-test)"
    ;;
esac
