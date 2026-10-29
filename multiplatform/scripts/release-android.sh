#!/usr/bin/env bash
# 원본: 없음 — Android 출시 파이프라인(W6-a · G §2-3 W6-a 행 · §4-1 · E§9.3·9.7·9.9·§11 · A§6-1). Play 업로드는 하지 않는다(조정자가 콘솔로).
#
# 사용
#   release-android.sh build  --prod-config FILE [--google-services FILE] [--keystore PATH] [--keychain-item NAME] [--key-alias upload]
#                             [--duels on|off] [--out DIR] [--allow-dirty] [--new-upload-key] [--plan-only]
#       운영 판: R8 AAB(bundleRelease) + 같은 번들의 보편 APK(packageReleaseUniversalApk, = bundletool --mode=universal) →
#       판정(verify) → 영수증 JSON → 판 장부(androidApp/release/versions.tsv)에 한 줄. Gradle·서명은 맥에서만(봉인 sandbox-exec 아래 --offline).
#       --plan-only 는 입력 판정·계획까지만 한다(Gradle·서명 없음) — 어느 OS 에서나 돈다(자기 시험이 Linux CI 에서도 이 길을 잰다).
#   release-android.sh dryrun [--duels on|off] [--out DIR] [--allow-dirty] [--plan-only]
#       같은 길을 운영 값 없이(.invalid) · 그 자리에서 만든 버리는 키로. 장부에 적지 않는다. 출시 전 리허설·게이트 몫.
#       Gradle 은 봉인 아래에서만 돈다: 맥은 스스로 sandbox-exec 를 건다. 다른 OS 는 바깥에서 건 봉인(AINGCHECK_NETWORK_SEALED=1)이
#       없으면 거부한다(K12 — 봉인 밖 R8 빌드 금지. gate-full 은 Linux 에서 dryrun 을 'not-run(linux)'로 찍고 건너뛴다).
#   release-android.sh smoke --apk APK --port N [--avd aingcheck-api36] [--expect-firebase INITIALIZE|SKIP_NO_CONFIG]
#                            [--version-code N] [--shot PNG]
#       R8 판을 창 없는 봉인 에뮬레이터(emu.sh)에 깔고 띄워 죽지 않는지·조립 지점 로그를 잰다. 포트는 갈래 자리(기본값 없음).
#       깔린 base.apk 를 기기에서 다시 받아 --apk 와 SHA-256 이 같은지 잰다(installedApk — "이번 빌드"가 깔렸나).
#   release-android.sh publish-sql --receipt RECEIPT.json --min-build N [--notes TEXT]
#       서버 출시 채널(client_publish_release_v2 — 서버 비밀 키 전용 함수)에 넣을 SQL 한 줄을 찍기만 한다. 실행은 사용자 동석으로 조정자가(G §8-9).
#   release-android.sh self-test   # 가짜 입력으로 거부·판정·서명·장부를 잰다(Gradle·에뮬레이터·망·키체인 없음). gate-fast 가 부른다.
#
# 입력(전부 저장소 밖에서 온다 — 저장소·argv·로그에 값을 싣지 않는다)
#   운영 구성   --prod-config FILE: Java properties, 키는 Gradle 속성 이름 그대로 aingcheck.prod.{supabaseUrl,supabaseAnonKey,
#               firebaseAppId,firebaseProjectId,firebaseSenderId,firebaseApiKey}. Firebase 넷은 --google-services FILE(운영 프로젝트의
#               google-services(json) — 패키지 com.yehsung.aingcheck 칸)에서 받아도 된다(둘 다 주면 거부). **여섯 중 하나라도 없으면 거부**(종료 2).
#               Gradle 에는 환경 변수 ORG_GRADLE_PROJECT_aingcheck.prod.* 로 넘긴다(release_tool.py exec-gradle — argv 에 싣지 않는다).
#   업로드 키   G §2-3 W6-a 행: 키 파일은 ~/.aing-check-secrets/android/, 비밀번호는 키체인. **그 자리가 기본이다.**
#               경로: --keystore > AINGCHECK_UPLOAD_KEYSTORE > 기본 ~/.aing-check-secrets/android/upload.p12.
#               비밀번호: --keychain-item NAME > AINGCHECK_UPLOAD_STORE_PASSWORD > 기본 키체인 항목 aingcheck-android-upload
#               (/usr/bin/security find-generic-password -s NAME -w). 항목과 환경 변수를 함께 주면 거부.
#               자리 밖 키 경로·환경 변수 비밀번호는 받되 경고를 찍고 영수증 warnings 에 남긴다(inputs.keyPlace·passwordSource).
#               키 비밀번호가 다르면 AINGCHECK_UPLOAD_KEY_PASSWORD. 별칭 기본 upload.
#               Gradle(androidApp/build.gradle.kts — W6-a 패치 01)은 AINGCHECK_UPLOAD_STORE_{FILE,PASSWORD} · _KEY_{ALIAS,PASSWORD} 를 읽는다.
#   판돈 깃발   --duels on|off(기본 off) → Gradle 속성 aingcheck.release.duelsEnabled → release 의 BuildConfig.DUELS_ENABLED.
#               판돈 e2e 를 통과한 빌드 N 에서만 on(G §8-17 #1). off 판은 내부 트랙에만.
#               **이중 확인**: 커밋된 version.properties 의 androidDuelsFromBuild=N 과 출시 인자가 맞아야 한다 —
#               --duels on 은 그 줄이 있고 versionCode ≥ N 일 때만, --duels off 는 그 줄이 없거나 versionCode < N 일 때만 받는다.
#               (출시 인자 하나로 켜지지 않게 — 켠 사실이 커밋에 남는다.)
#   판 번호     multiplatform/version.properties 의 androidVersionCode(한 곳 — K4). 장부 최댓값보다 커야 한다(단조 증가).
#               빌드 시각(UTC)·커밋 SHA·판 번호·판돈 깃발을 BuildConfig.RELEASE_STAMP 에 싣고, 산출물 dex 에서 다시 읽어 대조한다.
#
# 판정(verify — 하나라도 빨가면 종료 1, 영수증에 근거): aapt2 dump badging(패키지·versionCode·versionName·targetSdk 36·minSdk 26·
#   권한 = androidApp/release/permissions.txt 정확히·AD_ID 0·런처·아이콘) · dex(AAB 와 보편 APK 둘 다: RELEASE_STAMP = 이번 계획 ·
#   DUELS_ENABLED = --duels · BuildIdentity = version.properties · ProdConfig = 운영 구성 — anon·Firebase API 키는 SHA-256 으로 대조,
#   dryrun 은 .invalid·빈 값) · 내용물(비밀 표식 0 · google-services(json)·키 파일 0 · assets Fixtures 0 · 운영 판 dex 의 aingcheck.invalid 0 ·
#   진열장 전용 문자열 0) · R8 mapping(진열장 AingGallery 클래스 0) · 서명(AAB jarsigner · APK apksigner 의 인증서 SHA-256 = 업로드 키) ·
#   scripts/apk-native-check.sh(.so 허용 목록 · 16 KB) · 크기 예산(androidApp/release/budget.properties — AAB·보편 APK·글꼴 바이트).
#   빌드 시각 대조는 G 행의 "aapt2 badging" 대신 dex 도장으로 한다(badging 에는 빌드 시각 칸이 없다 — 매니페스트를 바꾸지 않고
#   같은 산출물에서 읽을 수 있는 자리가 BuildConfig 다). versionCode·versionName 은 badging 으로도 잰다.
#
# 종료 코드: 0 초록 · 1 빌드·판정 실패 · 2 입력 거부.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
MP="$(cd "$HERE/.." && pwd)"
# 자기 시험만 가짜 저장소 뿌리·가짜 security 를 쓴다(release_selftest.py 가 AINGCHECK_RELEASE_SELFTEST=1 로 부른다).
if [[ "${AINGCHECK_RELEASE_SELFTEST:-}" == "1" && -n "${AINGCHECK_RELEASE_MP:-}" ]]; then MP="$AINGCHECK_RELEASE_MP"; fi
SECURITY=/usr/bin/security
if [[ "${AINGCHECK_RELEASE_SELFTEST:-}" == "1" && -n "${AINGCHECK_RELEASE_SECURITY_BIN:-}" ]]; then SECURITY="$AINGCHECK_RELEASE_SECURITY_BIN"; fi
REL="$MP/androidApp/release"
TOOL="$HERE/../androidApp/release/release_tool.py"
LEDGER_REL="multiplatform/androidApp/release/versions.tsv"

die() { echo "release-android: 거부 — $*" >&2; exit 2; }
fail() { echo "release-android: 실패 — $*" >&2; exit 1; }
log() { echo "release-android: $*" >&2; }

PY="$(command -v python3 || true)"
[[ -n "$PY" ]] || die "python3 가 없다"
tool() { "$PY" -I "$TOOL" "$@"; }

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
build_tool() { # 이름 → 가장 높은 build-tools 의 그 도구
  local t
  t="$(ls -d "$SDK"/build-tools/*/"$1" 2>/dev/null | sort -V | tail -n 1)"
  [[ -n "$t" && -x "$t" ]] || return 1
  printf '%s\n' "$t"
}

# AAB(JAR 서명) 서명자: "<인증서 SHA-256> <jarsigner 판정 0|1>". 판정은 'jar verified.' 줄(서명 없는 jar 도 종료 0 이라 종료 코드로 못 가른다).
aab_signer() {
  local f="$1" sha out
  sha="$(keytool -J-Duser.language=en -printcert -rfc -jarfile "$f" 2>/dev/null | tool cert-sha256 2>/dev/null || true)"
  out="$(jarsigner -J-Duser.language=en -verify "$f" 2>&1 || true)"
  # 파이프(printf | grep -q)로 재지 않는다: AGP 가 서명한 AAB 는 출력이 수백 KB(JarInputStream 불일치 목록)라 grep -q 가 둘째 줄에서
  # 먼저 닫으면 printf 가 SIGPIPE(141) → pipefail 이 판정을 1 로 뒤집는다(7차 dryrun 'sign.aab rc=1' 의 원인 — 서명은 정상이었다).
  if grep -qx 'jar verified.' <<<"$out"; then echo "${sha:-none} 0"; else echo "${sha:-none} 1"; fi
}

cmd="${1:-}"
[[ -n "$cmd" ]] || die "명령이 없다(build|dryrun|smoke|publish-sql|self-test)"
shift

case "$cmd" in
  self-test)
    exec "$PY" -I "$TOOL" self-test --script "$SELF"
    ;;
  publish-sql)
    exec "$PY" -I "$TOOL" publish-sql "$@"
    ;;
  aab-signer) # 자기 시험용: AAB 서명자 판정만
    [[ -f "${1:-}" ]] || die "aab-signer: 파일이 없다"
    aab_signer "$1"
    exit 0
    ;;
  build|dryrun|smoke) ;;
  *) die "모르는 명령: $cmd" ;;
esac

# =====================================================================================================================
# smoke — 봉인 에뮬레이터에 R8 판을 깔고 띄운다(emu.sh 가 띄우고 끈다)
# =====================================================================================================================
if [[ "$cmd" == smoke ]]; then
  APK=""; PORT=""; AVD="aingcheck-api36"; EXPECT_FB=""; WANT_VC=""; SHOT=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apk) APK="${2:?}"; shift 2 ;;
      --port) PORT="${2:?}"; shift 2 ;;
      --avd) AVD="${2:?}"; shift 2 ;;
      --expect-firebase) EXPECT_FB="${2:?}"; shift 2 ;;
      --version-code) WANT_VC="${2:?}"; shift 2 ;;
      --shot) SHOT="${2:?}"; shift 2 ;;
      *) die "smoke: 모르는 인자 $1" ;;
    esac
  done
  [[ -f "$APK" ]] || die "smoke: --apk 가 없다"
  [[ "$PORT" =~ ^[0-9]+$ ]] || die "smoke: --port 는 갈래 자리 숫자다(기본값 없음)"
  case "$EXPECT_FB" in ""|INITIALIZE|SKIP_NO_CONFIG) ;; *) die "smoke: --expect-firebase 는 INITIALIZE|SKIP_NO_CONFIG" ;; esac
  ADB="$SDK/platform-tools/adb"; SERIAL="emulator-$PORT"
  EMU="$HERE/emu.sh"
  "$EMU" start --avd "$AVD" --port "$PORT" --boot-timeout 240 >&2 || fail "smoke: 에뮬레이터를 못 띄웠다"
  stop_emu() { "$EMU" stop --port "$PORT" >&2 || true; }
  trap stop_emu EXIT
  sw="$(mktemp -d "${TMPDIR:-/tmp}/aingcheck-smoke.XXXXXX")"
  "$EMU" sealcheck --port "$PORT" > "$sw/seal.txt" 2>&1 || true
  # 이전 판이 남아 있으면 지우고 새로 깐다(같은 판 번호 덮어쓰기·낮은 판 거부에 기대지 않는다).
  "$ADB" -s "$SERIAL" uninstall com.yehsung.aingcheck >/dev/null 2>&1 || true
  "$ADB" -s "$SERIAL" install "$APK" > "$sw/install.txt" 2>&1 || true
  # 깔린 것이 이번 APK 인가: 기기의 base.apk 를 다시 받아 SHA-256 을 견준다(판 번호만으로는 같은 번호의 낡은 판을 못 가른다).
  inst_path="$("$ADB" -s "$SERIAL" shell pm path com.yehsung.aingcheck 2>/dev/null | tr -d '\r' | sed -n 's/^package://p' | grep '/base\.apk$' | head -n 1 || true)"
  { echo "local=$(tool file-sha256 "$APK")"
    if [[ -n "$inst_path" ]] && "$ADB" -s "$SERIAL" pull "$inst_path" "$sw/installed-base.apk" >/dev/null 2>&1; then
      echo "device=$(tool file-sha256 "$sw/installed-base.apk")"
    else
      echo "device=none path=${inst_path:-없음}"
    fi; } > "$sw/apkhash.txt"
  "$ADB" -s "$SERIAL" logcat -c || true
  "$ADB" -s "$SERIAL" shell am start -W -n com.yehsung.aingcheck/.android.shell.MainActivity > "$sw/start.txt" 2>&1 || true
  sleep 6
  "$ADB" -s "$SERIAL" shell pidof com.yehsung.aingcheck > "$sw/pid.txt" 2>/dev/null || true
  "$ADB" -s "$SERIAL" logcat -d -v brief > "$sw/logcat.txt" 2>/dev/null || true
  "$ADB" -s "$SERIAL" shell dumpsys package com.yehsung.aingcheck > "$sw/dumpsys.txt" 2>/dev/null || true
  shot_rc=0
  if [[ -n "$SHOT" ]]; then "$EMU" shot --port "$PORT" --out "$SHOT" >&2 || shot_rc=1; fi
  "$EMU" windows --port "$PORT" > "$sw/windows.txt" 2>&1 || true
  judge=(--dir "$sw" --shot-rc "$shot_rc")
  [[ -n "$EXPECT_FB" ]] && judge+=(--expect-firebase "$EXPECT_FB")
  [[ -n "$WANT_VC" ]] && judge+=(--want-version-code "$WANT_VC")
  set +e
  tool smoke-judge "${judge[@]}"
  bad=$?
  set -e
  rm -rf "$sw"
  "$ADB" -s "$SERIAL" uninstall com.yehsung.aingcheck >/dev/null 2>&1 || true
  trap - EXIT
  stop_emu
  left="$("$EMU" procs --port "$PORT" 2>&1 | tail -n 1 || true)"; log "smoke: 끈 뒤 $left"
  [[ "$left" == alive=0* ]] || bad=1
  echo "release-android: smoke apk=$(basename "$APK") port=$PORT result=$([[ $bad -eq 0 ]] && echo ok || echo FAIL)"
  exit $bad
fi

# =====================================================================================================================
# build · dryrun
# =====================================================================================================================
MODE=prod; [[ "$cmd" == dryrun ]] && MODE=dryrun
PROD_CONFIG=""; GOOGLE_SERVICES=""; KEYSTORE=""; KEYCHAIN_ITEM=""
KEY_ALIAS="${AINGCHECK_UPLOAD_KEY_ALIAS:-upload}"; DUELS=off; OUT=""; PLAN_ONLY=0
pre_flags=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prod-config) PROD_CONFIG="${2:?}"; shift 2 ;;
    --google-services) GOOGLE_SERVICES="${2:?}"; shift 2 ;;
    --keystore) KEYSTORE="${2:?}"; shift 2 ;;
    --keychain-item) KEYCHAIN_ITEM="${2:?}"; shift 2 ;;
    --key-alias) KEY_ALIAS="${2:?}"; shift 2 ;;
    --duels) DUELS="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --allow-dirty) pre_flags+=(--allow-dirty); shift ;;
    --new-upload-key) pre_flags+=(--new-upload-key); shift ;;
    --plan-only) PLAN_ONLY=1; shift ;;
    *) die "모르는 인자: $1" ;;
  esac
done
case "$DUELS" in on|off) ;; *) die "--duels 는 on 또는 off 다('$DUELS')" ;; esac
# OS 가드는 계획 뒤(Gradle·서명 직전)에 있다 — 입력 판정·계획(--plan-only)은 어느 OS 에서나 돌아 자기 시험이 Linux CI 에서도 잰다.
if [[ "$MODE" == prod ]]; then
  [[ -n "$PROD_CONFIG" || -n "$GOOGLE_SERVICES" ]] || die "운영 구성이 없다(--prod-config FILE) — 값 없이 만든 운영 판은 .invalid·FCM 없음으로 나간다"
  for f in "$PROD_CONFIG" "$GOOGLE_SERVICES"; do [[ -z "$f" || -f "$f" ]] || die "운영 구성 파일이 없다: $f"; done
else
  [[ -z "$PROD_CONFIG" && -z "$GOOGLE_SERVICES" ]] || die "dryrun 은 운영 구성을 받지 않는다"
  [[ -z "$KEYCHAIN_ITEM" && -z "$KEYSTORE" ]] || die "dryrun 은 업로드 키를 받지 않는다(그 자리에서 만든 버리는 키로 서명한다)"
  # 셸에 남은 업로드 키 환경 변수는 dryrun 이 쓰지 않는다(버리는 키로 덮는다).
  unset AINGCHECK_UPLOAD_STORE_PASSWORD AINGCHECK_UPLOAD_KEY_PASSWORD AINGCHECK_UPLOAD_KEYSTORE 2>/dev/null || true
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/aingcheck-release.XXXXXX")"
chmod 700 "$work"
cleanup() {
  rm -rf "$work"
  unset AINGCHECK_UPLOAD_STORE_PASSWORD AINGCHECK_UPLOAD_KEY_PASSWORD 2>/dev/null || true
}
trap cleanup EXIT

# ---- 업로드 키(값은 환경 변수로만 — export 는 셸 내장이라 argv 에 실리지 않는다)
if [[ "$MODE" == dryrun ]]; then
  KEYSTORE="$work/dryrun-upload.p12"; KEY_ALIAS=upload
  AINGCHECK_UPLOAD_STORE_PASSWORD="dryrun-$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"
  export AINGCHECK_UPLOAD_STORE_PASSWORD
  keytool -J-Duser.language=en -genkeypair -keystore "$KEYSTORE" -storetype PKCS12 -alias upload -keyalg RSA -keysize 2048 -validity 30 \
    -dname "CN=aingcheck dryrun throwaway" -storepass:env AINGCHECK_UPLOAD_STORE_PASSWORD -keypass:env AINGCHECK_UPLOAD_STORE_PASSWORD >/dev/null 2>&1 \
    || fail "dryrun: 버리는 키를 못 만들었다"
  KEY_PLACE=throwaway; PW_SOURCE=throwaway
else
  # G §2-3 W6-a 행의 자리가 기본: 키 ~/.aing-check-secrets/android/upload.p12 · 비밀번호 키체인 항목 aingcheck-android-upload.
  SECRETS_ANDROID="$HOME/.aing-check-secrets/android"
  KEYSTORE="${KEYSTORE:-${AINGCHECK_UPLOAD_KEYSTORE:-$SECRETS_ANDROID/upload.p12}}"
  [[ -f "$KEYSTORE" ]] || die "업로드 키 파일이 없다: $KEYSTORE(--keystore · AINGCHECK_UPLOAD_KEYSTORE · 기본 자리 ~/.aing-check-secrets/android/upload.p12)"
  if [[ -n "$KEYCHAIN_ITEM" && -n "${AINGCHECK_UPLOAD_STORE_PASSWORD:-}" ]]; then
    die "비밀번호가 두 곳(--keychain-item 과 AINGCHECK_UPLOAD_STORE_PASSWORD)에서 왔다 — 하나만"
  fi
  # 자리 판정(경고만 — 영수증 warnings): 키 파일이 비밀 폴더 밖인가 · 비밀번호가 환경 변수에서 왔나.
  key_dir="$(cd "$(dirname "$KEYSTORE")" && pwd -P)"
  secrets_dir="$(cd "$SECRETS_ANDROID" 2>/dev/null && pwd -P || true)"
  if [[ -n "$secrets_dir" && ( "$key_dir" == "$secrets_dir" || "$key_dir" == "$secrets_dir"/* ) ]]; then KEY_PLACE=secrets-dir; else KEY_PLACE=other; fi
  if [[ -z "$KEYCHAIN_ITEM" && -z "${AINGCHECK_UPLOAD_STORE_PASSWORD:-}" ]]; then KEYCHAIN_ITEM=aingcheck-android-upload; fi
  if [[ -n "$KEYCHAIN_ITEM" ]]; then PW_SOURCE=keychain; else PW_SOURCE=env; fi
  if [[ -n "$KEYCHAIN_ITEM" ]]; then
    pw="$("$SECURITY" find-generic-password -s "$KEYCHAIN_ITEM" -w 2>/dev/null)" || die "키체인 항목 '$KEYCHAIN_ITEM' 을 못 읽었다"
    [[ -n "$pw" ]] || die "키체인 항목 '$KEYCHAIN_ITEM' 이 비었다"
    AINGCHECK_UPLOAD_STORE_PASSWORD="$pw"; unset pw
    export AINGCHECK_UPLOAD_STORE_PASSWORD
  fi
  [[ -n "${AINGCHECK_UPLOAD_STORE_PASSWORD:-}" ]] || die "업로드 키 비밀번호가 없다(--keychain-item NAME 또는 AINGCHECK_UPLOAD_STORE_PASSWORD)"
  export AINGCHECK_UPLOAD_STORE_PASSWORD
fi
export AINGCHECK_UPLOAD_STORE_FILE="$KEYSTORE" AINGCHECK_UPLOAD_KEY_ALIAS="$KEY_ALIAS"
cert_pem="$(keytool -J-Duser.language=en -exportcert -rfc -keystore "$KEYSTORE" -alias "$KEY_ALIAS" -storepass:env AINGCHECK_UPLOAD_STORE_PASSWORD 2>/dev/null)" \
  || die "업로드 키를 못 열었다(비밀번호·별칭 '$KEY_ALIAS' 확인)"
UPLOAD_CERT="$(printf '%s\n' "$cert_pem" | tool cert-sha256)" || die "업로드 키 인증서를 못 읽었다"
log "업로드 키 인증서 SHA-256 $UPLOAD_CERT (별칭 $KEY_ALIAS)"

# ---- 커밋·작업 트리(장부 파일만 더러워도 된다)
GIT_SHA="$(git -C "$MP" rev-parse HEAD 2>/dev/null)" || die "git 저장소가 아니다: $MP"
dirty_lines="$(git -C "$MP" status --porcelain --untracked-files=normal -- . 2>/dev/null | grep -v -F " $LEDGER_REL" | grep -v -F " androidApp/release/versions.tsv" || true)"
GIT_DIRTY=0; [[ -z "$dirty_lines" ]] || GIT_DIRTY=1
BUILD_TIME="$(date -u +%Y%m%dT%H%M%SZ)"

PLAN="$work/plan.json"; VALUES="$work/values.json"
pre_args=(--mode "$MODE" --version-properties "$MP/version.properties" --ledger "$REL/versions.tsv" --duels "$DUELS"
  --build-time "$BUILD_TIME" --git-sha "$GIT_SHA" --git-dirty "$GIT_DIRTY" --upload-cert-sha256 "$UPLOAD_CERT" --out "$PLAN" --values-out "$VALUES"
  --key-place "$KEY_PLACE" --password-source "$PW_SOURCE")
[[ -n "$PROD_CONFIG" ]] && pre_args+=(--prod-config "$PROD_CONFIG")
[[ -n "$GOOGLE_SERVICES" ]] && pre_args+=(--google-services "$GOOGLE_SERVICES")
set +e
tool preflight "${pre_args[@]}" "${pre_flags[@]+"${pre_flags[@]}"}"
rc=$?
set -e
[[ $rc -eq 0 ]] || exit "$rc"
VC="$("$PY" -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["versionCode"])' "$PLAN")"
if [[ "$PLAN_ONLY" -eq 1 ]]; then
  cp "$PLAN" "${OUT:-$work}/plan.json" 2>/dev/null || true
  echo "release-android: plan-only mode=$MODE versionCode=$VC uploadCert=$UPLOAD_CERT dirty=$GIT_DIRTY"
  exit 0
fi

# ---- OS 가드(Gradle·서명 직전). 운영 판은 맥에서만(E§11 — CI 에 서명 비밀을 두지 않는다).
#      Gradle 은 봉인 아래에서만(K12): 맥은 아래에서 sandbox-exec 를 건다. 다른 OS 는 바깥 봉인(AINGCHECK_NETWORK_SEALED=1)이 있어야 한다.
OS_NAME="$(uname -s)"
if [[ "$MODE" == prod && "$OS_NAME" != Darwin ]]; then
  die "운영 판은 이 맥에서만 만든다(E§11 — CI 에 서명 비밀을 두지 않는다). 이 OS($OS_NAME)에서는 --plan-only 까지만"
fi
if [[ "$OS_NAME" != Darwin && "${AINGCHECK_NETWORK_SEALED:-}" != "1" ]]; then
  die "봉인 밖에서 Gradle 을 돌리지 않는다(K12) — 이 OS($OS_NAME)에서는 바깥에서 망을 막고(unshare 등) AINGCHECK_NETWORK_SEALED=1 로 부른다"
fi

OUT="${OUT:-$MP/build/release-android/$MODE-$VC-$BUILD_TIME}"
mkdir -p "$OUT"
cp "$PLAN" "$OUT/plan.json"
# 비교값(비밀 아님 — 운영 주소·Firebase 앱 id 셋)은 판정이 끝나면 지운다. 값 파일 원본은 exec-gradle 이 읽자마자 지운다.
"$PY" -I -c 'import json,sys; d=json.load(open(sys.argv[1])); json.dump({"expect": d["expect"]}, open(sys.argv[2], "w"))' "$VALUES" "$work/expect.json"

# ---- Gradle(봉인 · --offline · 일회용 데몬). 낡은 산출물을 먼저 지워 이번 빌드 것만 판정한다.
AAB_SRC="$MP/androidApp/build/outputs/bundle/release/androidApp-release.aab"
APK_SRC="$MP/androidApp/build/outputs/apk_from_bundle/release/androidApp-release-universal.apk"
MAP_SRC="$MP/androidApp/build/outputs/mapping/release/mapping.txt"
rm -f "$AAB_SRC" "$APK_SRC" "$MAP_SRC"
gradle_cmd=("$MP/gradlew" -p "$MP" --offline --no-daemon :androidApp:bundleRelease :androidApp:packageReleaseUniversalApk)
log "Gradle: bundleRelease + packageReleaseUniversalApk (mode=$MODE duels=$DUELS) → $OUT/gradle.log"
started=$(date +%s)
set +e
if [[ "$OS_NAME" == Darwin ]]; then
  /usr/bin/sandbox-exec -f "$HERE/seal.sb" /usr/bin/env AINGCHECK_NETWORK_SEALED=1 \
    "$PY" -I "$TOOL" exec-gradle --values "$VALUES" -- "${gradle_cmd[@]}" > "$OUT/gradle.log" 2>&1
else
  "$PY" -I "$TOOL" exec-gradle --values "$VALUES" -- "${gradle_cmd[@]}" > "$OUT/gradle.log" 2>&1
fi
grc=$?
set -e
rm -f "$VALUES"
log "Gradle exit=$grc elapsed=$(( $(date +%s) - started ))s"
if [[ $grc -ne 0 ]]; then tail -n 30 "$OUT/gradle.log" >&2; fail "Gradle 빌드가 실패했다(exit $grc)"; fi
[[ -f "$AAB_SRC" && -f "$APK_SRC" ]] || fail "산출물이 없다(AAB·보편 APK)"

BASE="aingcheck-android-$VC-$BUILD_TIME-$MODE"
AAB="$OUT/$BASE.aab"; APK="$OUT/$BASE-universal.apk"
cp "$AAB_SRC" "$AAB"; cp "$APK_SRC" "$APK"
[[ -f "$MAP_SRC" ]] && cp "$MAP_SRC" "$OUT/mapping.txt"

# ---- 도구 판정 → verify
AAPT2="$(build_tool aapt2)" || fail "aapt2 가 없다($SDK/build-tools)"
APKSIGNER="$(build_tool apksigner)" || fail "apksigner 가 없다($SDK/build-tools)"
"$AAPT2" dump badging "$APK" > "$OUT/badging.txt" 2>&1 || fail "aapt2 dump badging 실패"
read -r AAB_CERT AAB_JRC < <(aab_signer "$AAB")
set +e
"$APKSIGNER" verify --print-certs "$APK" > "$OUT/apksigner.txt" 2>&1; ARC=$?
bash "$HERE/apk-native-check.sh" "$APK" > "$OUT/native.txt" 2>&1; NRC=$?
set -e
sed 's/^/  /' "$OUT/native.txt" | tail -n 4 >&2
set +e
tool verify --plan "$PLAN" --values-expect "$work/expect.json" --aab "$AAB" --apk "$APK" --badging "$OUT/badging.txt" \
  --mapping "$OUT/mapping.txt" --permissions "$REL/permissions.txt" --aab-cert-sha256 "$AAB_CERT" --aab-jarsigner-rc "$AAB_JRC" \
  --apksigner-out "$OUT/apksigner.txt" --apksigner-rc "$ARC" --native-rc "$NRC" --budget "$REL/budget.properties" --out "$OUT/receipt.json"
vrc=$?
set -e
[[ $vrc -eq 0 ]] || fail "산출물 판정이 빨갛다 — $OUT/receipt.json"

if [[ "$MODE" == prod ]]; then
  tool ledger-append --receipt "$OUT/receipt.json" --ledger "$REL/versions.tsv"
  log "다음(조정자): Play Console 비공개 테스트 트랙에 $AAB 를 올린다(관리형 게시). 판 장부 변경을 version.properties 다음 판과 함께 커밋한다."
  log "서버 채널(사용자 동석): $SELF publish-sql --receipt $OUT/receipt.json --min-build <N>"
fi
echo "release-android: $MODE ok versionCode=$VC duels=$DUELS aab=$AAB apk=$APK receipt=$OUT/receipt.json"
