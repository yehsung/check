#!/usr/bin/env python3
"""수집된 Codex 진단값을 읽어 과다계상의 원인을 지목한다.

전제: v0.2.30 이 `token_usage_device_monthly.codex_diag_*` 를 채우기 시작한 뒤에 돌린다.
앱 빌드+월 당 1회만 올라오므로, 값이 0 뿐이면 아직 그 사람이 업데이트를 안 받았거나
팝오버를 안 연 것이다(codex_diag_build 로 구분된다).

읽는 법 — 네 가설이 남기는 서명이 각각 다르다:

  A. 파일 간 중복 계상        dup_events > 0,  dedup_total << 앱값
     원인 후보: iCloud/Dropbox 충돌 사본(`rollout-… 2.jsonl` 이 glob 에 걸린다),
                백업 복원, 맥 이전 마법사가 세션 디렉터리를 복제.
  B. resume 카운터 이월       carry_files > 0,  carry_total 이 앱값의 상당 비율
     (carry_total 은 **상한** 추정치다 — 직전 세션에서 이미 계상된 몫이 섞여 있다.)
  C. 리셋 후 재계상           drops > 0,  max_delta 가 비정상적으로 큼
  D. 우리 산식이 아니라       final_sum 도 앱값과 비슷하게 큼
     Codex 로그 자체가 큼      → 그 숫자는 Codex 가 보고한 그대로다. 앱 결함이 아니다.

  concentration(top_file/앱값)이 1 에 가까우면 한 파일이 전부를 들고 있다는 뜻이고,
  그 경우 원인은 그 파일 하나에 국한된 사건이다.

사용법:
  CHECK_SUPABASE_SERVICE_ROLE_KEY=... python3 scripts/codex-diag-report.py [YYYY-MM]
"""
import json
import os
import sys
import urllib.request

MONTH = sys.argv[1] if len(sys.argv) > 1 else "2026-08"
URL = os.environ.get("CHECK_SUPABASE_URL", "https://xfnhfjvubetkdnfkfljg.supabase.co")
KEY = os.environ.get("CHECK_SUPABASE_SERVICE_ROLE_KEY")
if not KEY:
    sys.exit("CHECK_SUPABASE_SERVICE_ROLE_KEY 가 필요합니다 (.env.local 참조).")


def get(path):
    req = urllib.request.Request(
        URL + "/rest/v1/" + path,
        headers={"apikey": KEY, "Authorization": "Bearer " + KEY},
    )
    with urllib.request.urlopen(req) as r:
        return json.load(r)


DIAG = ["files_total", "files_month", "events_month", "max_delta", "carry_files",
        "carry_total", "dup_events", "dup_tokens", "final_sum", "dedup_total",
        "drops", "top_file", "build"]
cols = "user_id,device_id,codex_input,total," + ",".join("codex_diag_" + d for d in DIAG)

rows = get("token_usage_device_monthly?month=eq.%s&select=%s&order=codex_input.desc" % (MONTH, cols))
prof = {p["id"]: p for p in get("profiles?select=id,display_name,app_version")}


def name(uid):
    return ((prof.get(uid) or {}).get("display_name") or "?")[:12]


def f(n):
    return format(int(n or 0), ",")


def d(r, k):
    return int(r.get("codex_diag_" + k) or 0)


reported = [r for r in rows if d(r, "build") > 0]
pending = [r for r in rows if d(r, "build") == 0 and int(r.get("codex_input") or 0) > 0]

print("=" * 100)
print("Codex 진단 리포트  ·  %s  ·  보고 %d행 / 미보고(Codex 사용) %d행"
      % (MONTH, len(reported), len(pending)))
print("=" * 100)

if pending:
    print("\n아직 진단이 안 올라온 Codex 사용자 (업데이트 미수신 또는 팝오버 미개봉):")
    for r in sorted(pending, key=lambda r: -int(r["codex_input"] or 0)):
        print("  %-13s codex=%s  앱버전=%s"
              % (name(r["user_id"]), f(r["codex_input"]),
                 (prof.get(r["user_id"]) or {}).get("app_version") or "미보고"))

if not reported:
    print("\n아직 진단 표본이 없습니다. v0.2.30 배포 후 대상자가 팝오버를 한 번 열면 올라옵니다.")
    raise SystemExit(0)

print()
print("%-13s %16s %16s %8s %8s %9s %9s %7s" %
      ("이름", "앱값(codex)", "final_sum", "앱/final", "dup제거", "carry비율", "집중도", "빌드"))
print("-" * 100)
for r in sorted(reported, key=lambda r: -int(r["codex_input"] or 0)):
    app = int(r.get("codex_input") or 0)
    fs = d(r, "final_sum")
    dd = d(r, "dedup_total")
    ct = d(r, "carry_total")
    tf = d(r, "top_file")
    print("%-13s %16s %16s %8s %8s %9s %9s %7d"
          % (name(r["user_id"]), f(app), f(fs),
             ("%.2fx" % (app / fs)) if fs else "-",
             ("%.2fx" % (dd / app)) if app else "-",
             ("%.0f%%" % (100 * ct / app)) if app else "-",
             ("%.0f%%" % (100 * tf / app)) if app else "-",
             d(r, "build")))

print()
print("=" * 100)
print("사람별 판정")
print("=" * 100)
for r in sorted(reported, key=lambda r: -int(r["codex_input"] or 0)):
    app = int(r.get("codex_input") or 0)
    if app == 0:
        continue
    fs, dd, ct = d(r, "final_sum"), d(r, "dedup_total"), d(r, "carry_total")
    verdicts = []
    if d(r, "dup_events") > 0:
        verdicts.append("A 파일간 중복: dup_events=%s, 중복분 %s (%.0f%%) → 제거하면 %s"
                        % (f(d(r, "dup_events")), f(d(r, "dup_tokens")),
                           100 * d(r, "dup_tokens") / app, f(dd)))
    if d(r, "carry_files") > 0:
        verdicts.append("B resume 이월: %s개 파일이 큰 누적치로 시작, 상한 %s (앱값의 %.0f%%)"
                        % (f(d(r, "carry_files")), f(ct), 100 * ct / app))
    if d(r, "drops") > 0:
        verdicts.append("C 리셋 후 재계상: drops=%s, max_delta=%s"
                        % (f(d(r, "drops")), f(d(r, "max_delta"))))
    if fs and app / fs < 1.5 and not verdicts:
        verdicts.append("D 앱 산식 결함 아님: final_sum(%s) 도 비슷하게 크다 — "
                        "Codex 로그가 보고한 숫자 그대로다" % f(fs))
    if not verdicts:
        verdicts.append("네 가설 모두 불발. 파일 %s개 / 이벤트 %s개 / 집중도 %.0f%% 를 보고 다시 세워야 한다."
                        % (f(d(r, "files_month")), f(d(r, "events_month")),
                           100 * d(r, "top_file") / app))
    print("\n%s  (앱값 %s)" % (name(r["user_id"]), f(app)))
    for v in verdicts:
        print("   - " + v)
