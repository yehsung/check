#!/bin/bash
# 운영 DB 백업 — roles · schema · data 를 따로 떠서 gzip, SHA256SUMS, 보존 14개.
#
# 왜: 관리 API 백업 조회가 `backups: []`, `pitr_enabled: false` 였다(감사 문서 §6). 조회 가능한 복구본이 없고
#     복원도 검증된 적이 없다. 이 스크립트는 Supabase 공식 이전 절차(roles/schema/data 분리)대로 덤프를 뜬다.
#
# 사용: scripts/ops/backup-db.sh [--keep N] [--no-platform-schema] [--download-storage]
#   --keep N               완료된 백업을 최신 N개만 남긴다(기본 14).
#   --no-platform-schema   auth·storage 스키마 DDL(로컬 복원 훈련용) 덤프를 건너뛴다.
#   --download-storage     Storage 객체도 내려받는다(scripts/ops/storage-download.py). 기본은 목록·용량만.
# 결과: ~/aing-check-backups/<UTC 시각>/ (폴더 700, 파일 600)
#   prod-counts.json        덤프 직전 운영 표별 정확 행 수 + Storage 버킷별 객체 수·용량(식별자 없음)
#   roles.sql.gz            pg_dumpall --roles-only (예약 역할은 CLI 가 주석 처리)
#   schema.sql.gz           public 등 사용자 스키마 DDL (auth·storage·realtime 등 플랫폼 스키마 제외)
#   platform-schema.sql.gz  auth·storage DDL — 새 Supabase 프로젝트 복원엔 쓰지 않는다(플랫폼이 만든다). 로컬 훈련용.
#   data.sql.gz             --data-only --use-copy (auth·storage·cron 등 데이터 포함, 마이그레이션 이력 제외)
#   manifest.json · SHA256SUMS · dump.log
# **개인정보가 들어 있다.** 저장소·작업 폴더 밖(기본 ~/aing-check-backups)에만 두고 절대 커밋하지 마라.
#
# 운영 연결 규칙
# - `supabase db dump --linked` 는 Docker 의 supabase/postgres 이미지 안에서 pg_dump 를 돈다(운영 17.6 과 같은 메이저).
#   Homebrew pg_dump 15 는 17 서버를 못 덤프한다. Docker 데몬이 꺼져 있으면 멈춘다.
# - CLI 의 DB 명령은 임시 로그인 역할을 만든다. 동시에 돌리면 역할 초기화가 경합해 pooler 가 끊긴다(실측) —
#   그래서 명령 하나씩, 잠금 래퍼(CHECK_DB_LOCK)가 있으면 그걸 거친다.
# - 비밀값을 인자로 넘기지 않는다(CLI 가 키체인 토큰으로 임시 역할을 받는다).
set -euo pipefail
umask 077

REPO="${CHECK_REPO:-/Users/yesung/check}"
ROOT="${CHECK_BACKUP_ROOT:-$HOME/aing-check-backups}"
KEEP="${CHECK_BACKUP_KEEP:-14}"
LOCK_WRAP="${CHECK_DB_LOCK:-/Users/yesung/.claude/projects/-Users-yesung-check/stab-1030/bin/with-db-lock.sh}"
PROJECT_REF="xfnhfjvubetkdnfkfljg"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_SCHEMA=1
DOWNLOAD_STORAGE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP="$2"; shift 2;;
    --no-platform-schema) PLATFORM_SCHEMA=0; shift;;
    --download-storage) DOWNLOAD_STORAGE=1; shift;;
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
    *) echo "backup-db: 모르는 인자 $1" >&2; exit 2;;
  esac
done
case "$KEEP" in ''|*[!0-9]*) echo "backup-db: --keep 은 양의 정수" >&2; exit 2;; esac
[ "$KEEP" -ge 1 ] || { echo "backup-db: --keep 은 1 이상" >&2; exit 2; }

now_ms() { /usr/bin/python3 -c 'import time; print(int(time.time()*1000))'; }
log() { printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$WORK/dump.log" >&2; }

# 운영에 붙는 CLI 명령은 한 번에 하나만.
db() {
  if [ -x "$LOCK_WRAP" ]; then "$LOCK_WRAP" "$@"; else (cd "$REPO" && "$@"); fi
}

# ---- 사전 점검: 대상 프로젝트·도구
linked="$(cat "$REPO/supabase/.temp/project-ref" 2>/dev/null || true)"
if [ "$linked" != "$PROJECT_REF" ]; then
  echo "backup-db: $REPO 가 $PROJECT_REF 에 링크되어 있지 않다(현재: ${linked:-없음}). 같은 계정의 다른 프로젝트를 덤프하지 않게 멈춘다." >&2
  exit 3
fi
command -v supabase >/dev/null || { echo "backup-db: supabase CLI 없음" >&2; exit 3; }
if ! docker info >/dev/null 2>&1; then
  echo "backup-db: Docker 데몬이 꺼져 있다 — supabase db dump 는 supabase/postgres 이미지 안에서 pg_dump 를 돈다." >&2
  exit 4
fi

mkdir -p "$ROOT"; chmod 700 "$ROOT"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="$ROOT/.partial-$TS"
FINAL="$ROOT/$TS"
mkdir -m 700 "$WORK"
# 하루 넘은 실패 잔재(.partial-*)는 지운다 — 완료본은 이름이 시각뿐이라 겹치지 않는다.
find "$ROOT" -maxdepth 1 -type d -name '.partial-*' -mtime +1 -exec rm -rf {} + 2>/dev/null || true

T0=$(now_ms)
STEPS=""
step_done() { STEPS="$STEPS$1=$(( $(now_ms) - $2 ));"; }

# ---- 운영 행 수(정확값)·Storage 목록·cron 일정·vault 이름. 복원 훈련의 비교 기준이라 **data 덤프 바로 앞**에서
# 읽는다(사이가 길면 근무 틱·메시지·세션 같은 뜨거운 표가 그만큼 어긋난다). 읽기 전용 한 번.
COUNT_SQL="select json_build_object(
  'taken_at', now(),
  'server_version', current_setting('server_version'),
  'db_bytes', pg_database_size(current_database()),
  'tables', (select coalesce(json_agg(json_build_object('table', s || '.' || t, 'rows', n) order by s, t), '[]'::json) from (
      select n.nspname as s, c.relname as t,
             (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', n.nspname, c.relname), false, true, '')))[1]::text::bigint as n
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where c.relkind in ('r', 'p') and n.nspname in ('public', 'auth', 'storage') and not c.relispartition
        and has_table_privilege(c.oid, 'select')) x),
  -- cron 일정과 vault 비밀 **이름**은 data 덤프에 없다(cron·vault 스키마 제외). 새 프로젝트 복원 때 다시 등록할 목록으로 남긴다.
  'cron_jobs', (case when has_table_privilege('cron.job', 'select') then (select coalesce(json_agg(json_build_object(
      'jobname', j.jobname, 'schedule', j.schedule, 'active', j.active, 'command', j.command) order by j.jobid), '[]'::json) from cron.job j) end),
  'vault_secret_names', (case when has_table_privilege('vault.secrets', 'select') then (select coalesce(json_agg(v.name order by v.name), '[]'::json) from vault.secrets v) end),
  'buckets', (select coalesce(json_agg(json_build_object('bucket', b.id, 'public', b.public, 'objects', x.objects, 'bytes', x.bytes) order by b.id), '[]'::json)
      from storage.buckets b
      left join lateral (select count(*) as objects, coalesce(sum((o.metadata->>'size')::bigint), 0) as bytes
                         from storage.objects o where o.bucket_id = b.id) x on true)
) as snapshot"
prod_counts() {
  local t; t=$(now_ms); log "운영 행 수·Storage 목록"
  db supabase db query --linked -o json "$COUNT_SQL" > "$WORK/prod-counts.raw.json" 2>>"$WORK/dump.log"
  /usr/bin/python3 - "$WORK/prod-counts.raw.json" "$WORK/prod-counts.json" <<'PY'
import json, sys
raw = json.load(open(sys.argv[1]))
def rows_of(x):
    if isinstance(x, list):
        return x
    if isinstance(x, dict):
        for k in ("rows", "result", "data"):
            if isinstance(x.get(k), list):
                return x[k]
    raise SystemExit("prod-counts: 알 수 없는 query 출력 모양")
snap = rows_of(raw)[0]["snapshot"]
if isinstance(snap, str):
    snap = json.loads(snap)
json.dump(snap, open(sys.argv[2], "w"), ensure_ascii=False, indent=1, sort_keys=True)
print("tables=%d rows=%d buckets=%d objects=%d bytes=%d" % (
    len(snap["tables"]), sum(t["rows"] for t in snap["tables"]), len(snap["buckets"]),
    sum(b["objects"] or 0 for b in snap["buckets"]), sum(b["bytes"] or 0 for b in snap["buckets"])), file=sys.stderr)
PY
  rm -f "$WORK/prod-counts.raw.json"
  step_done counts "$t"
}

# ---- 덤프. 순서: roles → schema → (platform) → 행 수 → data. 각 명령은 잠금 아래 하나씩.
dump() {  # dump <이름> <CLI 인자...>
  local name="$1"; shift
  local t; t=$(now_ms)
  log "덤프 $name"
  db supabase db dump --linked "$@" -f "$WORK/$name.sql" >>"$WORK/dump.log" 2>&1
  [ -s "$WORK/$name.sql" ] || { log "덤프 $name 이 비었다"; return 1; }
  gzip -9 "$WORK/$name.sql"
  step_done "$name" "$t"
}
dump roles --role-only
dump schema
if [ "$PLATFORM_SCHEMA" = 1 ]; then dump platform-schema -s auth,storage; fi
prod_counts
dump data --data-only --use-copy

# 행 수 조회와 data 덤프 시작 사이(임시 역할 준비 몇 초)의 쓰기만큼 뜨거운 표는 조금 다를 수 있다 — 훈련이 차이로 보고한다.
if [ "$DOWNLOAD_STORAGE" = 1 ]; then
  t=$(now_ms); log "Storage 객체 내려받기"
  /usr/bin/python3 "$SCRIPT_DIR/storage-download.py" --dest "$WORK/storage" >>"$WORK/dump.log" 2>&1
  step_done storage "$t"
fi

# ---- 체크섬·명세
( cd "$WORK" && shasum -a 256 ./*.gz prod-counts.json > SHA256SUMS )
/usr/bin/python3 - "$WORK" "$TS" "$STEPS" "$(( $(now_ms) - T0 ))" "$REPO" <<'PY'
import json, os, subprocess, sys
work, ts, steps, total_ms, repo = sys.argv[1:6]
def cat(p):
    try:
        return open(p).read().strip()
    except OSError:
        return None
cli = subprocess.run(["supabase", "--version"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.decode().strip()
files = {f: os.path.getsize(os.path.join(work, f)) for f in sorted(os.listdir(work)) if f.endswith(".gz")}
counts = json.load(open(os.path.join(work, "prod-counts.json")))
m = {
    "created_utc": ts, "project_ref": "xfnhfjvubetkdnfkfljg", "supabase_cli": cli,
    "dump_image_pg": cat(os.path.join(repo, "supabase/.temp/postgres-version")),
    "server_version": counts.get("server_version"), "db_bytes": counts.get("db_bytes"),
    "files": files, "step_ms": {k: int(v) for k, v in (s.split("=") for s in steps.split(";") if s)},
    "total_ms": int(total_ms),
    "prod_tables": len(counts["tables"]), "prod_rows": sum(t["rows"] for t in counts["tables"]),
    "storage": counts["buckets"],
    "cron_jobs": None if counts.get("cron_jobs") is None else len(counts["cron_jobs"]),
    "vault_secret_names": counts.get("vault_secret_names"),
}
json.dump(m, open(os.path.join(work, "manifest.json"), "w"), ensure_ascii=False, indent=1)
print(json.dumps({k: m[k] for k in ("created_utc", "files", "step_ms", "total_ms", "prod_tables", "prod_rows",
                                     "cron_jobs", "vault_secret_names")}, ensure_ascii=False))
PY
chmod 600 "$WORK"/*
mv "$WORK" "$FINAL"
WORK="$FINAL"
log "완료 $FINAL"

# ---- 보존: 완료본(이름이 UTC 시각인 폴더)만 세어 최신 KEEP 개를 남긴다.
{ ls -1 "$ROOT" | grep -E '^[0-9]{8}T[0-9]{6}Z$' || true; } | sort -r | tail -n +"$((KEEP + 1))" | while read -r old; do
  log "보존 초과 삭제 $old"
  rm -rf "${ROOT:?}/$old"
done
echo "$FINAL"
