#!/usr/bin/env python3
"""이월 정정 후, 순위판이 옛 원장의 부풀린 값을 계속 쓰는 것을 끊는다.

■ 왜 필요한가

순위판 RPC(`token_usage_board`)는 기기별 합산과 옛 원장(`token_usage_monthly`) 행 중
**큰 쪽**을 쓴다. v0.2.31 의 이월 정정으로 기기값은 내려가지만, 앱은 옛 표를 덮기 전에
현재 값을 읽어 **자기 값이 더 작으면 쓰지 않는다**(v0.2.10 맥의 값을 보호하려고 넣은 게이트).
그래서 옛 행은 부풀린 값 그대로 남고, '큰 쪽' 규칙에서 계속 이긴다 — 정정이 화면에 안 나타난다.

■ 언제 돌려야 하는가 (중요)

**그 사용자가 정정값을 이미 올린 뒤에만** 지워야 한다. 너무 일찍 지우면 순위판이
'업그레이드 전 기기값'(여전히 부풀린 값)으로 떨어질 뿐이고, 아무것도 나아지지 않는다.

판정 기준은 `codex_diag_build`다. v0.2.31 = build 40 이므로, 그 사용자의 **모든** 기기 행이
`codex_diag_build >= 40` 이면 정정값을 올린 것이 확정된다. 하나라도 미달이면 건너뛴다.

■ 무엇을 하는가

대상 월에 대해, 위 조건을 만족하는 사용자의 옛 원장 행만 지운다. 기기 행은 건드리지 않는다
(그게 정정된 진짜 값이다). 기본은 **모의 실행**이라 아무것도 지우지 않는다.

사용법:
  CHECK_SUPABASE_SERVICE_ROLE_KEY=... python3 scripts/legacy-ledger-cleanup.py 2026-08
  CHECK_SUPABASE_SERVICE_ROLE_KEY=... python3 scripts/legacy-ledger-cleanup.py 2026-08 --apply
"""
import json
import os
import sys
import urllib.request
import urllib.parse

MIN_BUILD = 40  # v0.2.31 — 이월 정정이 처음 들어간 빌드

args = [a for a in sys.argv[1:] if not a.startswith("--")]
APPLY = "--apply" in sys.argv
MONTH = args[0] if args else "2026-08"

URL = os.environ.get("CHECK_SUPABASE_URL", "https://xfnhfjvubetkdnfkfljg.supabase.co")
KEY = os.environ.get("CHECK_SUPABASE_SERVICE_ROLE_KEY")
if not KEY:
    sys.exit("CHECK_SUPABASE_SERVICE_ROLE_KEY 가 필요합니다 (.env.local 참조).")

HDR = {"apikey": KEY, "Authorization": "Bearer " + KEY}


def req(method, path, body=None, extra=None):
    h = dict(HDR)
    if extra:
        h.update(extra)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    r = urllib.request.Request(URL + "/rest/v1/" + path, data=data, headers=h, method=method)
    with urllib.request.urlopen(r) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else []


def f(n):
    return format(int(n or 0), ",")


devices = req("GET", "token_usage_device_monthly?month=eq.%s&select=user_id,device_id,total,codex_input,codex_diag_build,codex_diag_legacy_total" % MONTH)
legacy = req("GET", "token_usage_monthly?month=eq.%s&select=user_id,total,codex_input,updated_at" % MONTH)
prof = {p["id"]: p for p in req("GET", "profiles?select=id,display_name")}


def name(uid):
    return ((prof.get(uid) or {}).get("display_name") or "?")[:12]


by_user = {}
for d in devices:
    by_user.setdefault(d["user_id"], []).append(d)

legacy_by = {l["user_id"]: l for l in legacy}

print("=" * 96)
print("옛 원장 정리  ·  %s  ·  %s" % (MONTH, "실제 적용" if APPLY else "모의 실행 (아무것도 지우지 않음)"))
print("=" * 96)
print("%-13s %18s %18s %10s %s" % ("이름", "옛 원장", "기기 합산", "최소빌드", "판정"))
print("-" * 96)

targets = []
for uid, rows in sorted(by_user.items(), key=lambda kv: -sum(int(r["total"]) for r in kv[1])):
    lg = legacy_by.get(uid)
    if not lg:
        continue
    dev_total = sum(int(r["total"]) for r in rows)
    lg_total = int(lg["total"])
    builds = [int(r.get("codex_diag_build") or 0) for r in rows]
    min_build = min(builds) if builds else 0

    if min_build < MIN_BUILD:
        verdict = "건너뜀 — 아직 정정값 미보고"
    elif lg_total <= dev_total:
        verdict = "불필요 — 기기 합산이 이미 이김"
    else:
        verdict = "삭제 대상 (%s 만큼 부풀어 있음)" % f(lg_total - dev_total)
        targets.append((uid, lg_total, dev_total))

    print("%-13s %18s %18s %10d %s" % (name(uid), f(lg_total), f(dev_total), min_build, verdict))

print()
if not targets:
    print("삭제 대상 없음. 대상자가 v0.2.31 로 업그레이드하고 팝오버를 한 번 열면 다시 돌려라.")
    raise SystemExit(0)

print("삭제 대상 %d명, 순위판에서 걷힐 총 과다계상 %s"
      % (len(targets), f(sum(l - d for _, l, d in targets))))

if not APPLY:
    print()
    print("모의 실행이다. 실제로 지우려면 --apply 를 붙여라.")
    raise SystemExit(0)

print()
for uid, lg_total, dev_total in targets:
    q = "token_usage_monthly?user_id=eq.%s&month=eq.%s" % (urllib.parse.quote(uid), MONTH)
    req("DELETE", q, extra={"Prefer": "return=minimal"})
    print("  삭제됨: %-13s  옛값 %s → 기기 합산 %s" % (name(uid), f(lg_total), f(dev_total)))

print()
print("완료. 순위판을 다시 조회해 값이 내려갔는지 확인해라.")
