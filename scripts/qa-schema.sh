#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

rg "sudo 박수" supabase/seed.sql >/dev/null
rg "create table if not exists public\\.(teams|memberships|work_statuses|work_sessions)" supabase/migrations >/dev/null
rg "alter table public\\.(teams|profiles|memberships|work_statuses|work_sessions) enable row level security" supabase/migrations >/dev/null
rg "function public\\.is_team_member|security definer" supabase/migrations >/dev/null
rg "function public\\.handle_check_auth_user|on_check_auth_user_created" supabase/migrations >/dev/null
rg "members can upsert their status|members can update their status|members can create their sessions|members can close their sessions" supabase/migrations >/dev/null
rg "work_sessions_one_open_per_user" supabase/migrations >/dev/null

echo "schema ok: team seed, auth user backfill, read/write RLS, and one-open-session uniqueness present"
