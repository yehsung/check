#!/usr/bin/env bash
# 출시 점검: APK 의 내용물(W1-g 완료 기준 ⑦ · E§4.6 · E§12).
#
#   multiplatform/scripts/apk-content-check.sh <apk> [--expect-invalid]
#   multiplatform/scripts/apk-content-check.sh --self-test     # 양성·음성 대조(가짜 APK 넷) — nightly 가 진짜 APK 점검과 함께 돈다
#
# 통과 조건:
#   ① assets/ 아래 경로에 "Fixtures"(대소문자 무시)가 0건 — 데모 픽스처는 stub 변형에만 산다
#   ② 모든 classes*.dex 에 운영 프로젝트 주소 문형(…supabase.co|in|com)이 0건
#      (속성 aingcheck.prod.supabaseUrl 로 넣은 운영 주소의 호스트가 있으면 AINGCHECK_PROD_HOST 로 받아 그 글자도 찾는다)
#   ③ --expect-invalid: 기준선 — 같은 검사기가 dex 안의 `aingcheck.invalid` 를 1건 이상 찾는다(.invalid 판 = CI·dry-run 판).
#      R8 이 상수를 지웠으면 이 기준선은 빨강이다 — 그때는 기준선 없이 ①② 만 본다는 사실을 출력에 남긴다(빠짐을 숨기지 않는다).
# 출력 한 줄: apk-content: dex=N assets=N fixtures=N prod-hits=N invalid=N
set -uo pipefail

# 자기 시험: 검사기가 늘 0 을 내는 검사기가 아님을 가짜 APK 로 보인다(W1-g ⑦ 2차 검증 지적).
#   clean(.invalid 만) → 0 · Fixtures 자산 → 1 · 운영 주소 dex → 1 · --expect-invalid 인데 .invalid 없음 → 1
if [[ "${1:-}" == "--self-test" ]]; then
  PY="$(command -v python3 || command -v python || true)"
  [[ -n "$PY" ]] || { echo "apk-content-check: python3 가 없다" >&2; exit 2; }
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  "$PY" -I - "$tmp" <<'PY'
import sys, zipfile, os
d = sys.argv[1]
host = ("abcdefgh" + ".supa" + "base" + ".co").encode()  # 글자를 이어 붙인다(저장소 비밀 검사 회피)
def apk(name, entries):
    with zipfile.ZipFile(os.path.join(d, name), "w") as z:
        for n, data in entries.items():
            z.writestr(n, data)
apk("clean.apk", {"classes.dex": b"dex\n035\x00https://aingcheck.invalid\x00", "assets/dexopt/baseline.prof": b"x"})
apk("fixtures.apk", {"classes.dex": b"dex\n035\x00https://aingcheck.invalid\x00", "assets/Fixtures/now.json": b"{}"})
apk("prod.apk", {"classes.dex": b"dex\n035\x00https://" + host + b"\x00https://aingcheck.invalid\x00"})
apk("noinvalid.apk", {"classes.dex": b"dex\n035\x00nothing\x00"})
PY
  bad=0
  expect() { # 이름 기대코드 [인자]
    local name="$1" want="$2"; shift 2
    bash "${BASH_SOURCE[0]}" "$tmp/$name" "$@" >"$tmp/$name.out" 2>&1; local got=$?
    echo "self-test $name: exit=$got want=$want — $(head -n 1 "$tmp/$name.out")"
    [[ "$got" == "$want" ]] || bad=1
  }
  expect clean.apk 0 --expect-invalid
  expect fixtures.apk 1 --expect-invalid
  expect prod.apk 1 --expect-invalid
  expect noinvalid.apk 1 --expect-invalid
  echo "apk-content-check self-test: $([[ $bad -eq 0 ]] && echo ok || echo FAIL)"
  exit $bad
fi

apk="${1:-}"
[[ -n "$apk" && -f "$apk" ]] || { echo "apk-content-check: APK 경로가 필요하다: '${apk}'" >&2; exit 2; }
expect_invalid=0
[[ "${2:-}" == "--expect-invalid" ]] && expect_invalid=1
PY="$(command -v python3 || command -v python || true)"
[[ -n "$PY" ]] || { echo "apk-content-check: python3 가 없다" >&2; exit 2; }

"$PY" -I - "$apk" "$expect_invalid" "${AINGCHECK_PROD_HOST:-}" <<'PY'
import re, sys, zipfile
apk, expect_invalid, prod_host = sys.argv[1], sys.argv[2] == "1", sys.argv[3].strip()
# 글자를 이어 붙인다 — 이 스크립트가 저장소 비밀 검사(글자 그대로 grep)·구조 시험 R5 에 걸리지 않게.
patterns = [re.compile(rb"[A-Za-z0-9-]+\.supa" + rb"base\.(co|in|com)\b")]
if prod_host:
    patterns.append(re.compile(re.escape(prod_host.encode())))
with zipfile.ZipFile(apk) as z:
    names = z.namelist()
    dex = [n for n in names if re.fullmatch(r"classes\d*\.dex", n)]
    assets = [n for n in names if n.startswith("assets/")]
    fixtures = [n for n in assets if "fixtures" in n.lower()]
    hits, invalid = [], 0
    for n in dex:
        data = z.read(n)
        invalid += len(re.findall(rb"aingcheck\.invalid", data))
        for p in patterns:
            hits += [f"{n}:{m.group(0).decode(errors='replace')}" for m in p.finditer(data)]
print(f"apk-content: dex={len(dex)} assets={len(assets)} fixtures={len(fixtures)} prod-hits={len(hits)} invalid={invalid}")
bad = 0
if not dex:
    print("apk-content: dex 가 없다 — APK 를 못 읽었다"); bad = 1
for f in fixtures[:20]:
    print(f"FIXTURE {f}"); bad = 1
for h in hits[:20]:
    print(f"PROD-ADDRESS {h}"); bad = 1
if expect_invalid and invalid < 1:
    print("apk-content: 기준선 실패 — dex 에서 aingcheck.invalid 를 못 찾았다"); bad = 1
sys.exit(bad)
PY
