#!/usr/bin/env python3
"""운영 안정성 계측 스냅숏 — 장애 때 볼 숫자를 같은 시간축에 쌓는다.

배경(docs/plan/service-stability-audit-2026-10-30.md §3·§4·§8): 2026-10-29 18:54 KST 에 PostgREST
연결 풀 확보 실패(PGRST003), HTTP 504, SQL 시간 초과(57014), cron 시작 시간 초과가 한꺼번에 났다.
436MiB 메모리에서의 스왑·I/O 대기가 유력한 기여 요인인데, 측정은 68초 한 구간뿐이었다.
이 스크립트는 그 숫자들을 5분마다 한 줄씩 남겨 "장애 순간에 스왑·iowait 가 어땠나"를 나중에 답하게 한다.

원칙
- **DB 연결을 쓰지 않는다.** 장애의 직접 경로가 연결 풀 고갈이었으니 계측이 풀을 하나라도 먹으면 안 된다.
  읽는 곳은 Metrics API(Prometheus 텍스트)와 Management API 로그 엔드포인트(ClickHouse SQL) 둘뿐이다.
- 비밀값은 프로세스 안에서만 쓴다: service_role 키는 .env.local 에서, 관리 API 토큰은 Supabase CLI 가 둔
  OS 키체인 항목에서 /usr/bin/security 로 읽는다. 출력·인자·파일 어디에도 남기지 않는다.
  키체인을 못 읽으면 로그 집계만 건너뛰고 그렇다고 줄에 적는다(메트릭은 그대로 남긴다).
- 로그는 **건수만** 센다. 본문·URL·IP 는 가져오지 않는다(개인 식별자).
- 증가율은 기록 시점이 아니라 `--report` 에서 **직전 줄과의 차이**로 낸다. Metrics 응답은 캐시되어
  가까운 요청이 같은 값을 돌려줄 수 있으므로, 카운터 차 0 을 무부하로 읽지 않고 "갱신 없음"으로 표시한다.
  경과 시간도 로컬 시계가 아니라 서버 CPU 카운터 합 / CPU 수로 잰다(감사 문서 §4 의 67.89초 산식과 같다).

사용법
  python3 stability-snapshot.py                 # 한 번 재고 ~/aing-check-ops/snapshots.jsonl 에 한 줄 덧붙임
  python3 stability-snapshot.py --report [시간]  # 최근 N시간(기본 24) 표 요약
  python3 stability-snapshot.py --stdout        # 덧붙이지 않고 줄만 출력(점검용)
  python3 stability-snapshot.py --stdout --log-end 2026-10-29T10:00:00Z --log-minutes 15
                                                # 지난 구간의 로그 건수만 다시 세어 본다(술어 검증용)
주기 실행 예시: scripts/ops/com.aingcheck.stability-snapshot.plist.example (설치는 사용자 결정)
/usr/bin/python3(3.9) 표준 라이브러리만 쓴다 — launchd 의 좁은 PATH 에서도 돈다.
"""
import argparse
import base64
import binascii
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

PROJECT_REF = "xfnhfjvubetkdnfkfljg"
METRICS_URL = "https://%s.supabase.co/customer/v1/privileged/metrics" % PROJECT_REF
LOGS_URL = "https://api.supabase.com/v1/projects/%s/analytics/endpoints/logs" % PROJECT_REF
ENV_FILE = os.environ.get("CHECK_ENV_FILE", "/Users/yesung/check/.env.local")
SERVICE_KEY_NAME = "CHECK_SUPABASE_SERVICE_ROLE_KEY"
KEYCHAIN_SERVICE = "Supabase CLI"
KEYCHAIN_ACCOUNT = os.environ.get("SUPABASE_PROFILE", "supabase")
OUT_DIR = os.path.expanduser("~/aing-check-ops")
OUT_FILE = os.path.join(OUT_DIR, "snapshots.jsonl")
KST = dt.timezone(dt.timedelta(hours=9))
SCHEMA_VERSION = 1

# 로그 집계 술어. PGRST003·57014·504 는 감사 문서 §8 에서 운영 로그로 검증된 모양 그대로다.
# 5xx 는 PostgREST 접근 로그(`"POST /rpc/x HTTP/1.1" 504 -`)의 상태 칸을 본다.
# cron 은 pg_cron 이 남기는 `cron job N job startup timeout` 줄이다(cron.job_run_details 는 DB 라 안 읽는다).
LOG_COUNT_SQL = r"""
select
  count() as total,
  countIf(position(event_message, 'PGRST003') > 0) as pgrst003,
  countIf(event_message = 'canceling statement due to statement timeout') as stmt_timeout_57014,
  countIf(position(event_message, 'HTTP/1.1') > 0 and position(event_message, ' 504 ') > 0) as http_504,
  countIf(match(event_message, 'HTTP/1\\.[01]" 5[0-9][0-9] ')) as http_5xx,
  countIf(position(event_message, 'job startup timeout') > 0) as cron_startup_timeout
from logs
"""
LOG_FIELDS = ("total", "pgrst003", "stmt_timeout_57014", "http_504", "http_5xx", "cron_startup_timeout")
LOG_LAG = dt.timedelta(minutes=1)        # 수집 지연 — 막 들어오는 줄을 놓치지 않게 1분 전까지만 센다
LOG_DEFAULT = dt.timedelta(minutes=5)
LOG_MAX_GAP = dt.timedelta(minutes=60)   # 직전 줄이 이보다 오래면 이어 세지 않고 기본 창으로


def utcnow():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def iso(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def safe_error(e):
    """예외를 상태 코드·종류만으로 줄인다(헤더·본문에 비밀이나 식별자가 섞일 여지를 없앤다)."""
    if isinstance(e, urllib.error.HTTPError):
        return "HTTP %d" % e.code
    if isinstance(e, urllib.error.URLError):
        return "URLError %s" % type(e.reason).__name__
    return type(e).__name__


# ---------------------------------------------------------------- 비밀값(프로세스 안에서만)

def read_service_key():
    try:
        with open(ENV_FILE, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith(SERVICE_KEY_NAME + "="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'") or None
    except OSError:
        return None
    return None


def read_management_token():
    """Supabase CLI 가 OS 키체인에 둔 액세스 토큰. go-keyring 접두어(base64/hex)를 벗긴다."""
    env = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if env:
        return env, None
    try:
        p = subprocess.run(
            ["/usr/bin/security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", KEYCHAIN_ACCOUNT, "-w"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=15)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, "keychain %s" % type(e).__name__
    if p.returncode != 0:
        return None, "keychain rc=%d" % p.returncode
    raw = p.stdout.decode("utf-8", "replace").strip()
    try:
        if raw.startswith("go-keyring-base64:"):
            raw = base64.b64decode(raw[len("go-keyring-base64:"):]).decode()
        elif raw.startswith("go-keyring-encoded:"):
            raw = binascii.unhexlify(raw[len("go-keyring-encoded:"):]).decode()
    except (ValueError, binascii.Error):
        return None, "keychain decode"
    return (raw or None), (None if raw else "keychain empty")


# ---------------------------------------------------------------- Metrics API

_LINE = re.compile(r'^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{([^}]*)\})?\s+(\S+)')
_LABEL = re.compile(r'(\w+)="((?:[^"\\]|\\.)*)"')


def parse_prom(body):
    out = []
    for line in body.splitlines():
        if not line or line[0] == "#":
            continue
        m = _LINE.match(line)
        if not m:
            continue
        try:
            v = float(m.group(4))
        except ValueError:
            continue
        labels = dict(_LABEL.findall(m.group(3) or ""))
        out.append((m.group(1), labels, v))
    return out


def summarize_metrics(body):
    samples = parse_prom(body)

    def one(name, **want):
        for n, lb, v in samples:
            if n == name and all(lb.get(k) == w for k, w in want.items()):
                return v
        return None

    def by_label(name, key):
        d = {}
        for n, lb, v in samples:
            if n == name and key in lb:
                d[lb[key]] = d.get(lb[key], 0.0) + v
        return d

    cpu_modes, cpus = {}, set()
    for n, lb, v in samples:
        if n == "node_cpu_seconds_total":
            cpu_modes[lb.get("mode", "?")] = round(cpu_modes.get(lb.get("mode", "?"), 0.0) + v, 3)
            cpus.add(lb.get("cpu"))
    swap_total, swap_free = one("node_memory_SwapTotal_bytes"), one("node_memory_SwapFree_bytes")
    m = {
        "ok": True,
        # 캐시 판별용 지문. 같은 지문이면 서버가 새로 긁지 않은 응답이다.
        "fingerprint": hashlib.sha256(body.encode()).hexdigest()[:16],
        "mem_total_bytes": one("node_memory_MemTotal_bytes"),
        "mem_available_bytes": one("node_memory_MemAvailable_bytes"),
        "swap_total_bytes": swap_total,
        "swap_used_bytes": (swap_total - swap_free) if (swap_total is not None and swap_free is not None) else None,
        "swap_cached_bytes": one("node_memory_SwapCached_bytes"),
        "pswpin_pages_total": one("node_vmstat_pswpin"),
        "pswpout_pages_total": one("node_vmstat_pswpout"),
        "pgmajfault_total": one("node_vmstat_pgmajfault"),
        "cpu_count": len(cpus) or None,
        "cpu_seconds_total": cpu_modes,
        "disk_io_time_seconds_total": by_label("node_disk_io_time_seconds_total", "device"),
        # 연결 계열. pgrst_db_pool_* 는 PostgREST 자체 풀(전체 max_connections 와 다르다 — 문서 §1).
        "pg_backends": one("pg_stat_database_num_backends"),
        "pg_max_connections": one("max_connections_connection_count"),
        "pg_conn_by_user": by_label("connection_stats_connection_count", "username"),
        "pg_xact_runtime_seconds": one("pg_stat_activity_xact_runtime"),
        "pgrst_pool_max": one("pgrst_db_pool_max"),
        "pgrst_pool_available": one("pgrst_db_pool_available"),
        "pgrst_pool_waiting": one("pgrst_db_pool_waiting"),
        "pgrst_pool_timeouts_total": one("pgrst_db_pool_timeouts_total"),
        "pgbouncer_client_waiting": one("pgbouncer_pools_client_waiting_connections"),
        "gotrue_db_open": sum(by_label("db_sql_connection_open", "state").values()) or one("db_sql_connection_open"),
        "realtime_subscriptions": one("realtime_postgres_changes_total_subscriptions"),
        "metric_lines": len(samples),
    }
    return m


def fetch_metrics():
    key = read_service_key()
    if not key:
        return {"ok": False, "error": "service key not found in env file"}
    req = urllib.request.Request(METRICS_URL)
    req.add_header("Authorization", "Basic " + base64.b64encode(("service_role:" + key).encode()).decode())
    del key
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read().decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001 — 실패 종류만 남긴다
        return {"ok": False, "error": safe_error(e)}
    return summarize_metrics(body)


# ---------------------------------------------------------------- 로그 API(건수만)

def logs_query(sql, start, end, token=None):
    """Management API 로그 엔드포인트. 반환: (rows, error)."""
    if token is None:
        token, err = read_management_token()
        if not token:
            return None, err
    qs = urllib.parse.urlencode({"sql": sql, "iso_timestamp_start": iso(start), "iso_timestamp_end": iso(end)})
    req = urllib.request.Request(LOGS_URL + "?" + qs)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", "application/json")
    del token
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.loads(r.read().decode("utf-8", "replace"))
    except Exception as e:  # noqa: BLE001
        return None, safe_error(e)
    if isinstance(data, dict) and data.get("error"):
        err = data["error"]
        msg = err.get("message") if isinstance(err, dict) else str(err)
        return None, "api: %s" % str(msg)[:160]
    rows = data.get("result") if isinstance(data, dict) else None
    return (rows if isinstance(rows, list) else []), None


def log_window(prev_end, now, minutes=None, end=None):
    """직전 줄의 창 끝부터 이어 센다(빈틈·겹침 없이). 처음이거나 오래 비었으면 기본 5분."""
    if end is not None:
        end = parse_iso(end)
        return end - dt.timedelta(minutes=minutes or 5), end
    end = now - LOG_LAG
    if minutes:
        return end - dt.timedelta(minutes=minutes), end
    if prev_end is not None and dt.timedelta(0) < end - prev_end <= LOG_MAX_GAP:
        return prev_end, end
    return end - LOG_DEFAULT, end


def fetch_log_counts(start, end):
    rows, err = logs_query(LOG_COUNT_SQL, start, end)
    w = {"window_start": iso(start), "window_end": iso(end), "minutes": round((end - start).total_seconds() / 60, 2)}
    if err is not None:
        w.update(ok=False, skipped=err)
        return w
    row = rows[0] if rows else {}
    w["ok"] = True
    for k in LOG_FIELDS:
        try:
            w[k] = int(row.get(k) or 0)
        except (TypeError, ValueError):
            w[k] = None
    return w


# ---------------------------------------------------------------- 기록

def read_rows(path):
    rows = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        rows.append(json.loads(line))
                    except ValueError:
                        pass
    except OSError:
        pass
    return rows


def last_log_end(path):
    for r in reversed(read_rows(path)):
        lg = r.get("logs") or {}
        if lg.get("ok") and lg.get("window_end"):
            return parse_iso(lg["window_end"])
    return None


def take_snapshot(args):
    now = utcnow()
    rec = {"v": SCHEMA_VERSION, "ts": iso(now), "metrics": fetch_metrics()}
    if args.no_logs:
        rec["logs"] = {"ok": False, "skipped": "--no-logs"}
    else:
        prev_end = None if (args.stdout or args.log_end) else last_log_end(args.out)
        start, end = log_window(prev_end, now, args.log_minutes, args.log_end)
        rec["logs"] = fetch_log_counts(start, end)
    line = json.dumps(rec, ensure_ascii=False, sort_keys=True)
    if args.stdout:
        print(line)
    else:
        d = os.path.dirname(args.out)
        os.makedirs(d, mode=0o700, exist_ok=True)
        os.chmod(d, 0o700)
        fd = os.open(args.out, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as f:
            f.write(line + "\n")
        print("snapshot %s metrics=%s logs=%s -> %s" % (
            rec["ts"], "ok" if rec["metrics"].get("ok") else rec["metrics"].get("error"),
            "ok" if rec["logs"].get("ok") else rec["logs"].get("skipped"), args.out))
    return 0 if rec["metrics"].get("ok") else 1


# ---------------------------------------------------------------- 요약

def _f(v, fmt):
    return "-" if v is None else (fmt % v)


def report(path, hours):
    rows = read_rows(path)
    since = utcnow() - dt.timedelta(hours=hours)
    rows = [r for r in rows if r.get("ts") and parse_iso(r["ts"]) >= since]
    rows.sort(key=lambda r: r["ts"])
    if not rows:
        print("최근 %g시간 기록 없음 (%s)" % (hours, path))
        return 0
    hdr = ("시각(KST)", "가용MiB", "스왑MiB", "swpin/s", "swpout/s", "iowait%", "idle%", "구간s",
           "풀대기", "풀TO+", "5xx", "504", "PGRST003", "57014", "cron실패", "로그분")
    print("최근 %g시간 · %d줄 · %s" % (hours, len(rows), path))
    print("스왑 단위는 페이지/초(서버 page size 미확인 — 바이트 환산하지 않는다). 비율은 직전 '갱신된' 줄과의 차이.")
    print("  ".join(hdr))
    base = None          # 직전 갱신 메트릭(같은 지문·카운터 정지면 건너뛴다)
    tot = dict.fromkeys(("http_5xx", "http_504", "pgrst003", "stmt_timeout_57014", "cron_startup_timeout"), 0)
    fresh = swap_active = 0
    worst_iowait = None
    log_gaps = restarts = 0
    pool_to_inc = 0.0
    for r in rows:
        m, lg = r.get("metrics") or {}, r.get("logs") or {}
        cells = [parse_iso(r["ts"]).astimezone(KST).strftime("%m-%d %H:%M")]
        mib = lambda b: None if b is None else b / 1048576.0  # noqa: E731
        cells += [_f(mib(m.get("mem_available_bytes")), "%.0f"), _f(mib(m.get("swap_used_bytes")), "%.0f")]
        rate = [None] * 5
        pool_to = None
        if m.get("ok"):
            cpu = m.get("cpu_seconds_total") or {}
            tot_cpu = sum(cpu.values())
            if base is not None:
                bcpu = base.get("cpu_seconds_total") or {}
                dcpu = tot_cpu - sum(bcpu.values())
                if m.get("fingerprint") == base.get("fingerprint") or dcpu <= 0:
                    rate = ["갱신없음"] + [None] * 4
                else:
                    secs = dcpu / float(m.get("cpu_count") or 1)
                    din = (m.get("pswpin_pages_total") or 0) - (base.get("pswpin_pages_total") or 0)
                    dout = (m.get("pswpout_pages_total") or 0) - (base.get("pswpout_pages_total") or 0)
                    io = 100.0 * (cpu.get("iowait", 0) - bcpu.get("iowait", 0)) / dcpu
                    idle = 100.0 * (cpu.get("idle", 0) - bcpu.get("idle", 0)) / dcpu
                    rate = [din / secs, dout / secs, io, idle, secs]
                    a, b = base.get("pgrst_pool_timeouts_total"), m.get("pgrst_pool_timeouts_total")
                    if a is not None and b is not None:
                        # 카운터는 PostgREST 재시작 때 0 으로 돌아간다 — 음수 차이는 재시작으로 읽는다.
                        pool_to = "재시작" if b < a else "%.0f" % (b - a)
                        if b < a:
                            restarts += 1
                        else:
                            pool_to_inc += b - a
                    fresh += 1
                    swap_active += 1 if (din > 0 or dout > 0) else 0
                    worst_iowait = io if worst_iowait is None else max(worst_iowait, io)
            if rate[0] != "갱신없음":
                base = m
        if rate[0] == "갱신없음":
            cells += ["갱신없음", "", "", "", ""]
        else:
            cells += [_f(rate[0], "%.1f"), _f(rate[1], "%.1f"), _f(rate[2], "%.1f"), _f(rate[3], "%.1f"),
                      _f(rate[4], "%.0f")]
        cells.append(_f(m.get("pgrst_pool_waiting"), "%.0f"))
        cells.append("" if rate[0] == "갱신없음" else (pool_to or "-"))
        if lg.get("ok"):
            for k in ("http_5xx", "http_504", "pgrst003", "stmt_timeout_57014", "cron_startup_timeout"):
                tot[k] += lg.get(k) or 0
                cells.append(str(lg.get(k)))
            cells.append(_f(lg.get("minutes"), "%g"))
        else:
            log_gaps += 1
            cells += ["-"] * 5 + ["건너뜀"]
        print("  ".join(cells))
    print("-- 합계 --")
    print("갱신 구간 %d개 중 스왑 입출력이 0 이 아닌 구간 %d개(%s) · 최악 iowait %s%%" % (
        fresh, swap_active, ("%.0f%%" % (100.0 * swap_active / fresh)) if fresh else "-",
        _f(worst_iowait, "%.1f")))
    print("로그 건수: 5xx %d · 504 %d · PGRST003 %d · 57014 %d · cron 시작 시간 초과 %d (로그 건너뛴 줄 %d)" % (
        tot["http_5xx"], tot["http_504"], tot["pgrst003"], tot["stmt_timeout_57014"], tot["cron_startup_timeout"],
        log_gaps))
    print("PostgREST 풀 시간 초과 카운터(pgrst_db_pool_timeouts_total) 증가 %.0f (재시작 추정 %d회) · 풀 크기 %s" % (
        pool_to_inc, restarts, _f(next((r["metrics"].get("pgrst_pool_max") for r in reversed(rows)
                                       if (r.get("metrics") or {}).get("ok")), None), "%.0f")))
    if fresh and swap_active * 2 > fresh:
        print("판단 기준: 스왑 입출력이 갱신 구간 절반 넘게 0 이 아니다 → compute 증설 검토 1순위(결정은 사용자).")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="aing-check 운영 안정성 계측 스냅숏(DB 연결 없음)")
    ap.add_argument("--report", nargs="?", const=24.0, type=float, metavar="HOURS",
                    help="최근 N시간(기본 24) 요약 표")
    ap.add_argument("--out", default=OUT_FILE, help="JSONL 경로(기본 ~/aing-check-ops/snapshots.jsonl)")
    ap.add_argument("--stdout", action="store_true", help="파일에 덧붙이지 않고 줄만 출력")
    ap.add_argument("--no-logs", action="store_true", help="로그 집계 생략")
    ap.add_argument("--log-minutes", type=float, help="로그 창 길이(분). 기본은 직전 줄의 창 끝부터 이어서")
    ap.add_argument("--log-end", help="로그 창 끝(ISO 8601 UTC). 지난 구간 재집계·술어 검증용")
    args = ap.parse_args(argv)
    args.out = os.path.expanduser(args.out)
    if args.report is not None:
        return report(args.out, args.report)
    return take_snapshot(args)


if __name__ == "__main__":
    sys.exit(main())
