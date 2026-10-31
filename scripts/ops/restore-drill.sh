#!/bin/bash
# 복원 훈련 — backup-db.sh 가 뜬 백업을 로컬 PostgreSQL 17 클러스터(127.0.0.1:55445)에 되살리고
# 표별 행 수(덤프 직전 운영값과 비교) · 읽기 RPC · 쓰기 한 건 · 단계별 소요 시간을 잰다.
#
# 왜: "백업이 있다"와 "복원된다"는 다르다(감사 문서 §6·§7 병행 항목). 복원 소요와 실패 항목을 실측해 둔다.
#
# 사용: scripts/ops/restore-drill.sh [백업 폴더]     (기본: ~/aing-check-backups 의 가장 최근 완료본)
# 환경: DRILL_PORT(55445) · DRILL_PGBIN(/opt/homebrew/opt/postgresql@17/bin) · KEEP_CLUSTER=1(끝나도 켜 둠)
# 결과: <백업 폴더>/drill-<UTC 시각>/ 에 단계 로그(개인정보가 섞일 수 있음 — 백업과 같이 보존·삭제)와
#       summary.json(표 이름·건수·소요·가린 오류 문구만). 같은 요약을 표준 출력으로도 낸다.
#
# 대상은 **맨 PostgreSQL 17** 이다(Supabase 이미지 아님). 그래서 일부러 드러나는 차이:
#   - Supabase 전용 확장(pg_cron · pg_net · supabase_vault 등)이 없다 → schema 단계 오류로 기록된다.
#   - 예약 역할(anon · authenticated · service_role · supabase_auth_admin …)은 roles 덤프에 없다 → 여기서 만든다.
#   - auth · storage 스키마는 platform-schema 덤프로 세운다(새 Supabase 프로젝트로의 실제 복원에선 플랫폼이 만든다).
# 안전장치: libpq 환경변수(PG*)를 전부 지우고 127.0.0.1:$DRILL_PORT 로 고정한다 — 운영으로 가는 경로가 없다.
set -uo pipefail
umask 077

ROOT="${CHECK_BACKUP_ROOT:-$HOME/aing-check-backups}"
PGBIN="${DRILL_PGBIN:-/opt/homebrew/opt/postgresql@17/bin}"
PORT="${DRILL_PORT:-55445}"
DRILL_DIR="$ROOT/.drill"
PGDATA_DIR="$DRILL_DIR/pgdata"

BK="${1:-}"
if [ -z "$BK" ]; then
  BK="$(ls -1d "$ROOT"/[0-9]*T[0-9]*Z 2>/dev/null | sort | tail -1)"
fi
[ -n "$BK" ] && [ -f "$BK/SHA256SUMS" ] || { echo "restore-drill: 완료된 백업 폴더가 없다(${BK:-$ROOT})" >&2; exit 2; }
BK="$(cd "$BK" && pwd)"

for _v in $(env | sed -n 's/^\(PG[A-Z_]*\)=.*/\1/p'); do unset "$_v"; done
export PGHOST=127.0.0.1 PGPORT="$PORT" PGDATABASE=postgres PGUSER=supabase_admin PGCONNECT_TIMEOUT=5 PGSSLMODE=disable
export PGCLIENTENCODING=UTF8 LC_ALL=C LANG=C

"$PGBIN/postgres" --version 2>/dev/null | grep -q ' 17\.' || {
  echo "restore-drill: $PGBIN 에 PostgreSQL 17 이 없다 — 운영(17.6) 덤프는 brew install postgresql@17 가 필요하다." >&2; exit 3; }

OUT="$BK/drill-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -m 700 -p "$OUT" "$DRILL_DIR"; chmod 700 "$DRILL_DIR"
now_ms() { /usr/bin/python3 -c 'import time; print(int(time.time()*1000))'; }
PSQL=("$PGBIN/psql" -X -q)
TIMES=""
mark() { TIMES="$TIMES$1=$(( $(now_ms) - $2 ));"; }

# ---- 체크섬
( cd "$BK" && shasum -a 256 -c --quiet SHA256SUMS ) >"$OUT/checksum.log" 2>&1 || {
  echo "restore-drill: 체크섬 불일치 — $OUT/checksum.log" >&2; exit 4; }

# ---- 클러스터
running() { [ -f "$PGDATA_DIR/postmaster.pid" ] && "$PGBIN/pg_ctl" -D "$PGDATA_DIR" status >/dev/null 2>&1; }
stop_cluster() {
  if running; then "$PGBIN/pg_ctl" -D "$PGDATA_DIR" stop -m fast -w >/dev/null 2>&1; fi
  # 복원본에는 개인정보가 있다 — 켜 두라는 말이 없으면 데이터 폴더째 지운다.
  if [ "${KEEP_CLUSTER:-0}" != 1 ]; then rm -rf "$PGDATA_DIR"; fi
}
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 && ! running; then
  echo "restore-drill: 127.0.0.1:$PORT 를 다른 프로세스가 쓴다 — DRILL_PORT 로 바꿔라." >&2; exit 5
fi
running && "$PGBIN/pg_ctl" -D "$PGDATA_DIR" stop -m fast -w >/dev/null
case "$PGDATA_DIR" in "$ROOT"/.drill/pgdata) rm -rf "$PGDATA_DIR";; *) echo "이상한 PGDATA $PGDATA_DIR" >&2; exit 6;; esac
trap stop_cluster EXIT

T_ALL=$(now_ms); t=$T_ALL
"$PGBIN/initdb" -D "$PGDATA_DIR" -U supabase_admin --auth=trust -E UTF8 --locale=C >"$OUT/initdb.log" 2>&1 \
  || { echo "restore-drill: initdb 실패 — $OUT/initdb.log" >&2; exit 7; }
"$PGBIN/pg_ctl" -D "$PGDATA_DIR" -l "$OUT/server.log" -w start \
  -o "-p $PORT -c listen_addresses=127.0.0.1 -c unix_socket_directories='' -c timezone=UTC -c lc_messages=C" >/dev/null \
  || { echo "restore-drill: 서버 시작 실패 — $OUT/server.log" >&2; exit 7; }

# Supabase 가 미리 만들어 두는 역할·스키마. roles 덤프는 이들을 주석 처리한다(예약 역할).
"${PSQL[@]}" -v ON_ERROR_STOP=1 >"$OUT/bootstrap.log" 2>&1 <<'SQL' || { echo "restore-drill: bootstrap 실패" >&2; exit 8; }
create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;
create role authenticator login noinherit;
grant anon, authenticated, service_role to authenticator;
create role postgres login createrole createdb bypassrls;
grant anon, authenticated, service_role to postgres;
create role supabase_auth_admin login createrole noinherit;
create role supabase_storage_admin login createrole noinherit;
create role supabase_realtime_admin nologin noinherit;
create role supabase_replication_admin login replication;
create role supabase_read_only_user login bypassrls;
create role dashboard_user nologin createrole createdb replication;
create role pgbouncer login;
grant authenticator to supabase_storage_admin;
create schema extensions authorization postgres;
grant usage on schema extensions to anon, authenticated, service_role;
grant all on schema public to postgres, anon, authenticated, service_role;
-- Realtime 은 Supabase 플랫폼 서비스라 덤프에 없다. send_message·poke_ring 이 realtime.send(브로드캐스트)를 부르고
-- realtime.messages 를 읽으므로, 쓰기 확인이 그 줄에서 끊기지 않게 같은 모양의 표와 함수만 둔다(배달은 없다).
create schema realtime;
create table realtime.messages(
  topic text not null, extension text not null default 'broadcast', payload jsonb, event text,
  private boolean default false, updated_at timestamp not null default now(),
  inserted_at timestamp not null default now(), id uuid not null default gen_random_uuid());
create function realtime.send(payload jsonb, event text, topic text, private boolean default true)
  returns void language sql as $$
  insert into realtime.messages(payload, event, topic, private, extension) values (payload, event, topic, private, 'broadcast') $$;
grant usage on schema realtime to postgres, anon, authenticated, service_role;
grant all on realtime.messages to postgres, authenticated, service_role;
grant execute on function realtime.send(jsonb, text, text, boolean) to postgres, anon, authenticated, service_role;
SQL
mark init "$t"

phase() {  # phase <이름> <덤프 파일> — 오류가 나도 끝까지(어떤 문장이 안 들어가는지가 훈련의 결과다)
  local t; t=$(now_ms)
  gzcat "$2" | "${PSQL[@]}" -v ON_ERROR_STOP=0 >"$OUT/$1.log" 2>&1
  mark "$1" "$t"
}
phase roles "$BK/roles.sql.gz"
[ -f "$BK/platform-schema.sql.gz" ] && phase platform "$BK/platform-schema.sql.gz"
phase schema "$BK/schema.sql.gz"
# auth.users 위 트리거(on_check_auth_user_created → public.handle_check_auth_user)는 platform 덤프에 있는데
# 대상 함수는 schema 덤프에 있다. platform 을 먼저 세우니 트리거만 public 뒤에 한 번 더 건다(CREATE OR REPLACE 라 멱등).
if [ -f "$BK/platform-schema.sql.gz" ]; then
  t=$(now_ms)
  gzcat "$BK/platform-schema.sql.gz" | grep -E '^CREATE OR REPLACE TRIGGER ' \
    | "${PSQL[@]}" -v ON_ERROR_STOP=0 >"$OUT/platform_triggers.log" 2>&1
  mark platform_triggers "$t"
fi

# ---- 데이터: COPY 블록을 표 하나씩 따로 넣는다. 대상 표가 없거나 열이 다르면 넣지 않고 건너뜀으로 센다
# (COPY 머리가 실패하면 psql 이 뒤따르는 데이터 줄을 SQL 로 읽어 버린다 — 행 내용이 문장으로 실행될 수 있다).
t=$(now_ms)
/usr/bin/python3 - "$BK/data.sql.gz" "$OUT" "$PGBIN/psql" <<'PY'
import gzip, json, re, subprocess, sys
src, out, psql = sys.argv[1:4]
base = [psql, "-X", "-q", "-v", "ON_ERROR_STOP=1"]
cols = {}
q = ("select table_schema || '.' || table_name, string_agg(column_name, ',' order by ordinal_position) "
     "from information_schema.columns where table_schema not in ('pg_catalog', 'information_schema') group by 1")
for line in subprocess.run(base + ["-At", "-F", "\t", "-c", q], stdout=subprocess.PIPE, check=True).stdout.decode().splitlines():
    k, v = line.split("\t", 1)
    cols[k] = set(v.split(","))
COPY = re.compile(r'^COPY "((?:[^"]|"")+)"\."((?:[^"]|"")+)" \((.*)\) FROM stdin;$')
def redact(msg):
    # 값이 오류 문구에 섞여 나온다(invalid input syntax …: "값") — 따옴표 안을 모두 가린다.
    return re.sub(r"'[^']*'", "'…'", re.sub(r'"[^"]*"', '"…"', msg))[:160]
header, rest, results = [], [], []
seen_copy = False
with gzip.open(src, "rt", encoding="utf-8", newline="\n") as f:
    it = iter(f)
    for line in it:
        m = COPY.match(line.rstrip("\n"))
        if not m:
            if line.startswith("--") or not line.strip():
                continue
            (rest if seen_copy else header).append(line)
            continue
        seen_copy = True
        schema, table = m.group(1).replace('""', '"'), m.group(2).replace('""', '"')
        want = [c.strip().strip('"') for c in m.group(3).split(",")]
        block = [line]
        for d in it:
            block.append(d)
            if d == "\\.\n":
                break
        rows = len(block) - 2
        key = schema + "." + table
        r = {"table": key, "rows": rows}
        if key not in cols:
            r["result"] = "skipped: no target table"
        elif not set(want) <= cols[key]:
            r["result"] = "skipped: column mismatch (%d missing)" % len(set(want) - cols[key])
        else:
            p = subprocess.run(base, input=("".join(header) + "SET session_replication_role = replica;\n" + "".join(block)).encode(),
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if p.returncode == 0:
                r["result"] = "loaded"
            else:
                err = [l for l in p.stderr.decode("utf-8", "replace").splitlines() if "ERROR:" in l]
                r["result"] = "failed"
                r["error"] = redact(err[0].split("ERROR:", 1)[1].strip()) if err else "rc=%d" % p.returncode
        results.append(r)
# 남은 문장(시퀀스 setval · RESET 등)
p = subprocess.run(base[:-1] + ["ON_ERROR_STOP=0"], input=("".join(header) + "".join(rest)).encode(),
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
tail_errors = [redact(l.split("ERROR:", 1)[1].strip()) for l in p.stderr.decode("utf-8", "replace").splitlines() if "ERROR:" in l]
json.dump({"tables": results, "trailing_statements": len(rest), "trailing_errors": tail_errors},
          open(out + "/data.json", "w"), ensure_ascii=False, indent=1)
PY
mark data "$t"
mark restore_total "$T_ALL"

# ---- 확인: 행 수 비교 · 읽기 RPC · 쓰기 한 건
t=$(now_ms)
/usr/bin/python3 - "$BK/prod-counts.json" "$OUT" "$PGBIN/psql" <<'PY'
import json, subprocess, sys
prod_path, out, psql = sys.argv[1:4]
base = [psql, "-X", "-q", "-At", "-F", "\t"]
prod = json.load(open(prod_path))
names = [t["table"] for t in prod["tables"]]
vals = ",".join("('%s')" % n.replace("'", "''") for n in names)
q = ("select x.n, case when to_regclass(x.n) is null then null else "
     "(xpath('/row/c/text()', query_to_xml('select count(*) as c from ' || x.n::regclass::text, false, true, '')))[1]::text::bigint end "
     "from (values %s) x(n)") % vals
restored = {}
for line in subprocess.run(base + ["-c", q], stdout=subprocess.PIPE, check=True).stdout.decode().splitlines():
    n, c = line.split("\t")
    restored[n] = int(c) if c else None
cmp_rows = [{"table": t["table"], "prod": t["rows"], "restored": restored.get(t["table"])} for t in prod["tables"]]
probe = r"""
\set ON_ERROR_STOP 0
select from_user as sender, to_user as receiver from public.messages order by created_at desc limit 1 \gset
select 'messages_before', count(*) from public.messages;
begin;
select set_config('request.jwt.claims', json_build_object('sub', :'receiver', 'role', 'authenticated')::text, true) is not null as _ \gset
select set_config('request.jwt.claim.sub', :'receiver', true) is not null as _ \gset
set local role authenticated;
select 'rpc_read message_unread_summary', jsonb_typeof(public.message_unread_summary());
select 'rpc_read token_usage_board', count(*) from public.token_usage_board(to_char(now() at time zone 'Asia/Seoul', 'YYYY-MM'));
commit;
begin;
select set_config('request.jwt.claims', json_build_object('sub', :'sender', 'role', 'authenticated')::text, true) is not null as _ \gset
select set_config('request.jwt.claim.sub', :'sender', true) is not null as _ \gset
set local role authenticated;
select 'write send_message', public.send_message(:'receiver'::uuid, 'restore-drill write probe') ->> 'status';
commit;
select 'messages_after', count(*) from public.messages;
"""
p = subprocess.run(base, input=probe.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
open(out + "/probe.log", "wb").write(p.stdout + b"\n--stderr--\n" + p.stderr)
checks = {}
for line in p.stdout.decode().splitlines():
    if "\t" in line:
        k, v = line.split("\t", 1)
        checks[k] = v
errs = [l.split("ERROR:", 1)[1].strip()[:160] for l in p.stderr.decode("utf-8", "replace").splitlines() if "ERROR:" in l]
json.dump({"rows": cmp_rows, "checks": checks, "probe_errors": errs}, open(out + "/verify.json", "w"), ensure_ascii=False, indent=1)
PY
mark verify "$t"

# ---- 요약(표 이름 · 건수 · 소요 · 가린 오류만)
/usr/bin/python3 - "$OUT" "$TIMES" "$BK" <<'PY'
import collections, json, os, re, sys
out, times, bk = sys.argv[1:4]
ms = {k: int(v) for k, v in (s.split("=") for s in times.split(";") if s)}
def phase_errors(name):
    p = os.path.join(out, name + ".log")
    if not os.path.exists(p):
        return None
    c = collections.Counter()
    for l in open(p, encoding="utf-8", errors="replace"):
        if "ERROR:" in l:
            c[re.sub(r"\d+", "N", l.split("ERROR:", 1)[1].strip())[:140]] += 1
    return {"errors": sum(c.values()), "top": c.most_common(12)}
data = json.load(open(os.path.join(out, "data.json")))
ver = json.load(open(os.path.join(out, "verify.json")))
res = collections.Counter(t["result"].split(":")[0] for t in data["tables"])
eq = [r for r in ver["rows"] if r["restored"] == r["prod"]]
diff = [r for r in ver["rows"] if r["restored"] is not None and r["restored"] != r["prod"]]
missing = [r["table"] for r in ver["rows"] if r["restored"] is None]
s = {
    "backup": os.path.basename(bk), "drill": os.path.basename(out), "ms": ms,
    "phases": {n: phase_errors(n) for n in ("roles", "platform", "schema", "platform_triggers")},
    "data": {"blocks": dict(res), "rows_loaded": sum(t["rows"] for t in data["tables"] if t["result"] == "loaded"),
             "not_loaded": [t for t in data["tables"] if t["result"] != "loaded"],
             "trailing_errors": data["trailing_errors"][:10]},
    "row_compare": {"tables": len(ver["rows"]), "equal": len(eq), "differ": diff, "missing": missing},
    "checks": ver["checks"], "probe_errors": ver["probe_errors"],
}
json.dump(s, open(os.path.join(out, "summary.json"), "w"), ensure_ascii=False, indent=1)
print(json.dumps(s, ensure_ascii=False, indent=1))
PY
echo "restore-drill: 로그 $OUT (개인정보가 섞일 수 있음 — 밖으로 옮기지 마라)" >&2
