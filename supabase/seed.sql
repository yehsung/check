insert into public.teams (id, name, invite_code) values
  ('10000000-0000-0000-0000-000000000001', 'sudo 박수', 'SUDOPARK')
on conflict (id) do nothing;
