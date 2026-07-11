create extension if not exists "pgcrypto";

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.memberships (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (team_id, user_id)
);

create table if not exists public.work_statuses (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('working', 'off_work')),
  active_session_id uuid null,
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (team_id, user_id)
);

create table if not exists public.work_sessions (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  ended_at timestamptz null,
  duration_seconds integer null check (duration_seconds is null or duration_seconds >= 0)
);

create unique index if not exists work_sessions_one_open_per_user
  on public.work_sessions(user_id)
  where ended_at is null;

alter table public.teams enable row level security;
alter table public.profiles enable row level security;
alter table public.memberships enable row level security;
alter table public.work_statuses enable row level security;
alter table public.work_sessions enable row level security;

create or replace function public.is_team_member(check_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.memberships
    where memberships.team_id = check_team_id
      and memberships.user_id = auth.uid()
  );
$$;

revoke all on function public.is_team_member(uuid) from public;
grant execute on function public.is_team_member(uuid) to authenticated;

create or replace function public.handle_check_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.teams (id, name, invite_code)
  values ('10000000-0000-0000-0000-000000000001', 'sudo 박수', 'SUDOPARK')
  on conflict (id) do nothing;

  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(coalesce(new.email, '팀원'), '@', 1))
  )
  on conflict (id) do update set
    email = excluded.email,
    display_name = excluded.display_name;

  insert into public.memberships (team_id, user_id, role)
  values ('10000000-0000-0000-0000-000000000001', new.id, 'member')
  on conflict (team_id, user_id) do nothing;

  insert into public.work_statuses (team_id, user_id, status, active_session_id)
  values ('10000000-0000-0000-0000-000000000001', new.id, 'off_work', null)
  on conflict (team_id, user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_check_auth_user_created on auth.users;
create trigger on_check_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_check_auth_user();

insert into public.teams (id, name, invite_code)
values ('10000000-0000-0000-0000-000000000001', 'sudo 박수', 'SUDOPARK')
on conflict (id) do nothing;

insert into public.profiles (id, email, display_name)
select
  users.id,
  coalesce(users.email, ''),
  coalesce(users.raw_user_meta_data ->> 'display_name', split_part(coalesce(users.email, '팀원'), '@', 1))
from auth.users
on conflict (id) do update set
  email = excluded.email,
  display_name = excluded.display_name;

insert into public.memberships (team_id, user_id, role)
select '10000000-0000-0000-0000-000000000001', users.id, 'member'
from auth.users
on conflict (team_id, user_id) do nothing;

insert into public.work_statuses (team_id, user_id, status, active_session_id)
select '10000000-0000-0000-0000-000000000001', users.id, 'off_work', null
from auth.users
on conflict (team_id, user_id) do nothing;

create policy "members can read their teams"
  on public.teams for select
  using (public.is_team_member(teams.id));

create policy "members can read memberships"
  on public.memberships for select
  using (public.is_team_member(memberships.team_id));

create policy "users can read team profiles"
  on public.profiles for select
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.memberships target
      where target.user_id = profiles.id
        and public.is_team_member(target.team_id)
    )
  );

create policy "members can read team statuses"
  on public.work_statuses for select
  using (public.is_team_member(work_statuses.team_id));

create policy "members can upsert their status"
  on public.work_statuses for insert
  with check (
    user_id = auth.uid()
    and public.is_team_member(work_statuses.team_id)
  );

create policy "members can update their status"
  on public.work_statuses for update
  using (
    user_id = auth.uid()
    and public.is_team_member(work_statuses.team_id)
  )
  with check (user_id = auth.uid());

create policy "members can read team sessions"
  on public.work_sessions for select
  using (public.is_team_member(work_sessions.team_id));

create policy "members can create their sessions"
  on public.work_sessions for insert
  with check (
    user_id = auth.uid()
    and public.is_team_member(work_sessions.team_id)
  );

create policy "members can close their sessions"
  on public.work_sessions for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
