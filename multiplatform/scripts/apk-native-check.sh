#!/usr/bin/env bash
# 출시 점검: APK 안 네이티브 라이브러리(G §8-12 — "APK lib/ 0" 기준은 버렸다).
#
#   multiplatform/scripts/apk-native-check.sh <apk>
#
# 통과 조건:
#   ① lib/<abi>/*.so 의 파일 이름이 전부 허용 목록(scripts/apk-native-allowlist.txt)에 있다
#   ② zipalign -c -P 16 -v 4 통과(.so 가 16 KB 경계에 압축 없이 놓였다)
#   ③ 모든 .so 의 PT_LOAD 세그먼트 p_align ≥ 0x4000(16 KB 페이지 기기에서 dlopen 이 된다)
# zipalign 은 $ANDROID_HOME(또는 ANDROID_SDK_ROOT, 맥 기본 ~/Library/Android/sdk)/build-tools 의 가장 높은 판을 쓴다.
# ELF 는 파이썬으로 직접 읽는다(NDK·llvm-readelf 에 기대지 않는다).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
apk="${1:-}"
[[ -n "$apk" && -f "$apk" ]] || { echo "apk-native-check: APK 경로가 필요하다: '${apk}'" >&2; exit 2; }
allow="${AINGCHECK_APK_NATIVE_ALLOWLIST:-$HERE/apk-native-allowlist.txt}"
[[ -f "$allow" ]] || { echo "apk-native-check: 허용 목록이 없다: $allow" >&2; exit 2; }

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
zipalign="$(ls -d "$sdk"/build-tools/*/zipalign 2>/dev/null | sort -V | tail -n 1)"
[[ -x "$zipalign" ]] || { echo "apk-native-check: zipalign 이 없다($sdk/build-tools)" >&2; exit 2; }

PY="$(command -v python3 || command -v python || true)"
[[ -n "$PY" ]] || { echo "apk-native-check: python3 가 없다" >&2; exit 2; }

status=0
report="$("$PY" -I - "$apk" "$allow" <<'PY'
import struct, sys, zipfile
apk, allow_path = sys.argv[1], sys.argv[2]
allow = {l.strip() for l in open(allow_path, encoding="utf-8") if l.strip() and not l.strip().startswith("#")}
bad = 0
with zipfile.ZipFile(apk) as z:
    sos = [i for i in z.infolist() if i.filename.startswith("lib/") and i.filename.endswith(".so")]
    names = sorted({i.filename.rsplit("/", 1)[1] for i in sos})
    print(f"so-files={len(sos)} names={names}")
    for n in names:
        if n not in allow:
            print(f"NOT-ALLOWED {n}"); bad += 1
    for i in sos:
        data = z.read(i.filename)
        if data[:4] != b"\x7fELF":
            print(f"NOT-ELF {i.filename}"); bad += 1; continue
        is64 = data[4] == 2
        endian = "<" if data[5] == 1 else ">"
        if is64:
            phoff, = struct.unpack_from(endian + "Q", data, 0x20)
            phentsize, phnum = struct.unpack_from(endian + "HH", data, 0x36)
        else:
            phoff, = struct.unpack_from(endian + "I", data, 0x1C)
            phentsize, phnum = struct.unpack_from(endian + "HH", data, 0x2A)
        aligns = []
        for k in range(phnum):
            off = phoff + k * phentsize
            p_type, = struct.unpack_from(endian + "I", data, off)
            if p_type != 1:  # PT_LOAD
                continue
            p_align, = struct.unpack_from(endian + ("Q" if is64 else "I"), data, off + (0x30 if is64 else 0x1C))
            aligns.append(p_align)
        low = [a for a in aligns if a < 0x4000]
        print(f"{'LOAD-OK ' if aligns and not low else 'LOAD-BAD'} {i.filename} p_align={[hex(a) for a in aligns]}")
        if not aligns or low:
            bad += 1
print(f"bad={bad}")
PY
)"
echo "$report" | sed 's/^/apk-native-check: /'
[[ "$(echo "$report" | tail -n 1)" == "bad=0" ]] || status=1

zout="$("$zipalign" -c -P 16 -v 4 "$apk" 2>&1)"; zrc=$?
echo "apk-native-check: zipalign -c -P 16 -v 4 rc=$zrc · $(echo "$zout" | tail -n 1)"
[[ $zrc -eq 0 ]] || { echo "$zout" | grep -v '(OK' | head -20 | sed 's/^/apk-native-check:   /'; status=1; }

echo "apk-native-check: apk=$(basename "$apk") status=$status"
exit $status
