-- 프로필 아바타 백엔드: avatar_url 컬럼, profiles UPDATE 정책, avatars 스토리지 버킷/RLS
-- 멱등성: if not exists / on conflict / drop policy if exists 후 create 로 재실행 안전.

alter table public.profiles add column if not exists avatar_url text;

-- 본인 프로필만 수정 가능 (avatar_url 갱신용). 현재 profiles UPDATE 정책이 없어 신규 추가.
drop policy if exists "users can update own profile" on public.profiles;
create policy "users can update own profile"
  on public.profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- 공개 아바타 버킷.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- 본인 파일명(auth.uid() || '.jpg')에 한해 authenticated insert/update/delete.
drop policy if exists "avatar owner can upload" on storage.objects;
create policy "avatar owner can upload"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and name = auth.uid()::text || '.jpg'
  );

drop policy if exists "avatar owner can update" on storage.objects;
create policy "avatar owner can update"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and name = auth.uid()::text || '.jpg'
  )
  with check (
    bucket_id = 'avatars'
    and name = auth.uid()::text || '.jpg'
  );

drop policy if exists "avatar owner can delete" on storage.objects;
create policy "avatar owner can delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and name = auth.uid()::text || '.jpg'
  );

-- 공개 버킷이라 읽기는 public URL로 충분하지만 authenticated select 정책도 추가.
drop policy if exists "authenticated can read avatars" on storage.objects;
create policy "authenticated can read avatars"
  on storage.objects for select to authenticated
  using (bucket_id = 'avatars');
