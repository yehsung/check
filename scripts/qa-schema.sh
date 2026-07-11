#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ripgrep가 있으면 rg로, 없으면 grep -E로 동일한 패턴을 검사한다.
# 두 경우 모두 매치가 없으면 exit 1이 되어 set -e로 스크립트가 실패한다.
if command -v rg >/dev/null 2>&1; then
  match() { rg "$1" "$2" >/dev/null; }
else
  match() { grep -Erq "$1" "$2"; }
fi

match "sudo 박수" supabase/seed.sql
match "create table if not exists public\\.(teams|memberships|work_statuses|work_sessions)" supabase/migrations
match "alter table public\\.(teams|profiles|memberships|work_statuses|work_sessions) enable row level security" supabase/migrations
match "function public\\.is_team_member|security definer" supabase/migrations
match "function public\\.handle_check_auth_user|on_check_auth_user_created" supabase/migrations
match "members can upsert their status|members can update their status|members can create their sessions|members can close their sessions" supabase/migrations
match "work_sessions_one_open_per_user" supabase/migrations

echo "schema ok: team seed, auth user backfill, read/write RLS, and one-open-session uniqueness present"
