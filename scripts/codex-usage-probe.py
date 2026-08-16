#!/usr/bin/env python3
"""Codex 토큰 집계 진단 프로브 — 앱이 왜 그 숫자를 냈는지 현장에서 가른다.

배경: 순위판에서 Codex 사용자 코호트가 Claude 사용자 코호트보다 하루당 중앙값 20배 높게
나오고, 같은 사람이 달마다 50배씩 오르내린다. Claude 쪽 집계는 지상 실측과 0.05% 오차로
일치하므로(대조군), 의심 지점은 Codex 경로 하나로 좁혀져 있다.

이 스크립트는 ~/.codex/sessions 를 읽어 **앱과 똑같은 산식**과 **독립적인 대조 산식**을
나란히 계산한다. 둘이 갈리는 지점이 결함이다.

프라이버시: 대화 본문·프롬프트·파일 경로·파일명을 일절 출력하지 않는다. 나가는 값은
토큰 숫자와 개수뿐이다. 읽는 필드도 payload.type / info.total_token_usage / timestamp 뿐이다.

사용법:  python3 codex-usage-probe.py
"""
import json
import os
import glob
import collections
import datetime
import sys

KST = datetime.timezone(datetime.timedelta(hours=9))
MONTH = os.environ.get("PROBE_MONTH") or datetime.datetime.now(KST).strftime("%Y-%m")

root = os.path.expanduser("~/.codex/sessions")
if not os.path.isdir(root):
    print("~/.codex/sessions 가 없습니다. Codex 를 쓰지 않는 기기입니다.")
    sys.exit(0)

files = sorted(glob.glob(os.path.join(root, "**", "rollout-*.jsonl"), recursive=True))

# ── 앱과 동일한 산식: 파일별로 offset 0 부터, prevCumulative 0 에서 시작해
#    이벤트마다 delta = max(0, cum - prev) 를 그 이벤트의 KST 월에 귀속.
app_month = 0
# ── 대조 산식 A: 파일별 '마지막 누적치'만 더한다(세션당 한 번). 델타 재계상이 있으면 앱값이 이보다 크다.
final_sum_month = 0
# ── 대조 산식 B: 이벤트를 (timestamp, cum) 으로 전역 dedupe 한 뒤 델타 합산.
seen_pairs = collections.defaultdict(int)

n_events = 0
n_files_month = 0
biggest_delta = 0
carried_starts = []          # 첫 이벤트 누적치가 큰 파일 = 카운터 이월(=resume 재계상) 의심
per_file_month = []
skipped_noinfo = 0
drops = 0

for p in files:
    prev = 0
    contrib = 0
    first_cum = None
    last_cum_in_month = 0
    touched = False
    try:
        fh = open(p, errors="ignore")
    except OSError:
        continue
    with fh:
        for line in fh:
            if "token_count" not in line:
                continue
            try:
                o = json.loads(line)
            except Exception:
                continue
            pl = o.get("payload") or {}
            if pl.get("type") != "token_count":
                continue
            info = pl.get("info")
            if not info:
                skipped_noinfo += 1
                continue
            t = info.get("total_token_usage")
            if not t:
                skipped_noinfo += 1
                continue
            ts = o.get("timestamp") or ""
            if len(ts) < 19:
                continue
            try:
                d = datetime.datetime.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S").replace(
                    tzinfo=datetime.timezone.utc).astimezone(KST)
            except Exception:
                continue
            cum = (t.get("input_tokens") or 0) + (t.get("output_tokens") or 0)
            if first_cum is None:
                first_cum = cum
            if cum < prev:
                drops += 1
            delta = max(0, cum - prev)
            prev = cum
            if d.strftime("%Y-%m") == MONTH:
                contrib += delta
                n_events += 1
                touched = True
                last_cum_in_month = cum
                biggest_delta = max(biggest_delta, delta)
                seen_pairs[(ts, cum)] += 1
    if touched:
        n_files_month += 1
        app_month += contrib
        final_sum_month += last_cum_in_month
        per_file_month.append(contrib)
        if first_cum and first_cum > 200_000:
            carried_starts.append(first_cum)


def f(n):
    return format(int(n), ",")


dup_pairs = sum(1 for v in seen_pairs.values() if v > 1)

print("=" * 72)
print("Codex 집계 진단  ·  대상 월 %s" % MONTH)
print("=" * 72)
print("rollout 파일 총 %d개 / 그중 이 달 이벤트가 있는 파일 %d개" % (len(files), n_files_month))
print("이 달 token_count 이벤트 %s개" % f(n_events))
print()
print("[앱 산식]        이 달 합계  %20s" % f(app_month))
print("[대조A 세션최종] 이 달 합계  %20s" % f(final_sum_month))
if final_sum_month:
    print("                 앱/대조A 비율 %19.2fx" % (app_month / final_sum_month))
print()
print("── 이상 신호 ──")
print("  단일 이벤트 최대 델타          %20s" % f(biggest_delta))
print("  누적 감소(리셋) 이벤트          %20d" % drops)
print("  info/total 결손 이벤트          %20d" % skipped_noinfo)
print("  같은 (시각,누적) 쌍이 2회 이상   %20d   <- 0 이 아니면 파일 간 중복 계상" % dup_pairs)
print("  20만 토큰 넘겨 시작한 파일       %20d   <- 0 이 아니면 resume 카운터 이월" % len(carried_starts))
if carried_starts:
    top = sorted(carried_starts, reverse=True)[:5]
    print("     이월 상위: %s" % ", ".join(f(c) for c in top))
    print("     이월분 총합: %s  (전체의 %.1f%%)"
          % (f(sum(carried_starts)), 100.0 * sum(carried_starts) / max(1, app_month)))
if per_file_month:
    per_file_month.sort(reverse=True)
    print()
    print("  파일별 기여 상위 5: %s" % ", ".join(f(x) for x in per_file_month[:5]))
    print("  상위 1개가 전체의 %.1f%%" % (100.0 * per_file_month[0] / max(1, app_month)))
print("=" * 72)
