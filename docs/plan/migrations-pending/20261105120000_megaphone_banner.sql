-- 확성기 배너(2026-10-30 사용자 결정): 메시지함 한 줄 대신 화면 배너 · 앱 전체에 한 번에 하나(5분).
-- 계약: docs/plan/megaphone-banner-contract.md (서버 S1~S6). 전부 덧붙이기 — 옛 앱(맥 · 폰)은 지금처럼 📢 메시지로 받는다.
--
-- ── 왜 ─────────────────────────────────────────────────────────────────────────────────────
--   확성기가 받는 사람마다 평범한 1:1 메시지 한 줄로만 가서 눈에 안 띈다. 새 앱은 그 줄을 메시지함에서 빼고 화면 위 배너로
--   띄운다. 그러려면 (1) 확성기 줄을 믿을 수 있게 알아보는 길(📢 접두는 예약어가 아니다 — 아무나 1:1 로 쓸 수 있다 · 표식은
--   messages.megaphone_id 하나뿐), (2) 그 줄을 빼고 세는 안 읽음 집계, (3) 울림 신호, (4) 앱 전체 5분 창이 필요하다.
--
-- ── 무엇을 바꾸나 ──────────────────────────────────────────────────────────────────────────
--   S1 상수 megaphone_global_cooldown_seconds() = 300 (immutable · PUBLIC 실행권 유지 — 42501 함정).
--   S2 send_megaphone 재정의(정본 + 치환 3곳): 멱등키 → 사람당 창(scope 'self') → 전역 자물쇠 → 앱 전체 창(scope 'global').
--      앱 전체 창은 **같은 쪽 계정**(same_visibility)의 마지막 확성기로 잰다 — 숨김(심사 · 시험) 계정이 실사용자를 막지 않는다.
--      받는 사람마다 poke_ring 다음에 realtime 'megaphone' 신호 {v:1, m:<확성기 id>} — 실패는 삼킨다(루비 · fan-out 은 그대로).
--   S3 megaphone_info 재정의(정본 + 치환 3곳): 기존 키 그대로 + global_cooldown_seconds · global_cooldown_remaining_seconds ·
--      cooldown_scope('self' | 'global' | null). cooldown_remaining_seconds = 둘 중 긴 쪽(옛 앱 작성 화면이 그대로 맞는 시간).
--   S4 새 megaphone_inbox(p_hours default 24): 내가 받은 확성기 줄(최근 24시간 · 차단 제외 · 최신 20개). 벽은 to_user 한 줄.
--   S5 새 message_unread_summary_v2(): 안 읽음 집계(v1 은 그대로) + 확성기 줄 제외. 새 앱 배지가 이것만 센다.
--   S6 push_on_message_insert 재정의(정본 + 치환 1곳): 확성기 줄이면 최상위 megaphone_id 한 키. 나머지 페이로드는 그대로.
--
-- ── 안 바꾸는 것 ───────────────────────────────────────────────────────────────────────────
--   fan-out(messages 줄) · 📢 접두 · poke_ring · 루비 · 장부 · 멱등 · 가격(megaphone_ruby_price 를 계속 부른다) · 받는 사람 집합.
--   1:1 보내기 · 대화 기록 · 안 읽음 집계(v1) · 가격 상수는 **다시 정의하지 않는다**(V0333 관문 · 멱등 시험 · V0354 시험).
--
-- ── 옛 앱 ─────────────────────────────────────────────────────────────────────────────────
--   cooldown 응답의 scope 키를 모르고 "N분 뒤에 다시 보낼 수 있어요"를 말한다(맞는 말). 'megaphone' 신호는 모르는 이벤트라
--   접는다(message_read 선례). 푸시의 최상위 megaphone_id 는 모르는 키라 무시한다(type 'message' · category 'MESSAGE' 그대로).
--
-- ── 잠금 ──────────────────────────────────────────────────────────────────────────────────
--   send_megaphone: ultra_wallet:<uid> → megaphone_global 순서뿐(다른 함수는 megaphone_global 을 쥐지 않는다 — 교착 없음).
--   앱 전체 창은 자물쇠를 쥔 **뒤**의 새 스냅숏으로 읽는다(read committed) — 동시에 온 두 사람 중 하나만 지난다.
--   이 파일: 첫 문장에서 lock_timeout 3초. 함수 정의와 프로브뿐이라 표 잠금은 프로브의 행 잠금(롤백)뿐이다.
--
-- ── 멱등성 ────────────────────────────────────────────────────────────────────────────────
--   §0 은 첫 적용(세 본문 = 정본 md5)이거나 재적용(세 본문 = 이 파일 본문 md5)일 때만 지난다. 섞여 있거나 다른 값이면 누가
--   손댄 것이다 — create or replace 가 그 고침을 조용히 되돌리므로 멈춘다. 새 함수 셋은 create or replace · 같은 grant 재부여 ·
--   임시 객체 drop 후 생성 · 프로브 센티널 롤백. 최상위 begin/commit 없음.
--
-- ── 되돌리기 ───────────────────────────────────────────────────────────────────────────────
--   세 함수를 정본 본문(20261014122000 의 둘 · 20261022070340 의 트리거 함수)으로 다시 create or replace 하고, 새 RPC 둘과
--   상수를 drop 한다(그 순서 — 본문이 상수를 부른다). 새 앱은 megaphone_inbox · v2 가 없으면(PGRST202) 예전 메시지함으로 돌아간다.
--
-- ── 뒤 파일이 이 셋을 다시 정의할 때 ──────────────────────────────────────────────────────────
--   출발점은 이 파일의 본문이다(MegaphoneBannerMigrationTests 가 "정본 + 치환표 = 이 파일 본문" 을 바이트로 되묻는다).
--   지킬 것: 멱등키 → 사람당 → 전역 자물쇠 → 앱 전체 창 순서 · 앱 전체 창이 차감보다 앞 · same_visibility · scope 두 갈래 ·
--   신호의 예외 삼키기 · 가격은 megaphone_ruby_price() · 푸시의 type/category/sticker_push_label/예외 삼키기.
--
-- ── 함정(이 저장소에서 데인 것) ───────────────────────────────────────────────────────────
--   · 서명을 바꾸지 않는다. 새 인자는 전부 DEFAULT. 상수 함수의 PUBLIC 실행권을 회수하지 않는다.
--   · do 블록 · 함수 본문 안 주석에 달러 인용 태그 글자를 적지 않는다. 역할 복귀는 set local role(RESET ROLE 금지).
--   · 프로브는 합성 계정으로 실호출하고 센티널 예외로 통째 롤백한다. 신호 · 초인종 realtime.send 와 푸시 발송함은 표 행이라
--     같이 사라지고, pg_net 요청도 커밋 전에는 나가지 않는다.
-- ══════════════════════════════════════════════════════════════════════════════════════════


-- ── §0 잠금 시한 · 사전 단언(정본 본문 md5) · 직전 기록 ─────────────────────────────────────

do $lk$
begin
  perform set_config('lock_timeout', '3s', true);
end
$lk$;

create or replace function pg_temp.mgb_attrs(p_fn regprocedure)
returns jsonb language sql stable as $tmp$
  select jsonb_build_object('oid', p.oid, 'acl', p.proacl::text, 'vol', p.provolatile, 'secdef', p.prosecdef,
                            'owner', p.proowner, 'lang', p.prolang, 'cfg', p.proconfig::text,
                            'ret', p.prorettype, 'args', pg_get_function_arguments(p.oid), 'strict', p.proisstrict)
    from pg_proc p where p.oid = p_fn
$tmp$;

drop table if exists pg_temp.mgb_before;
create table pg_temp.mgb_before (
  sig       text primary key,
  canon_md5 text not null,
  self_md5  text not null,
  md5       text,
  attrs     jsonb
);
-- canon = 저장소 최신 정의 본문의 md5(운영 본문과 같아야 한다 — 로컬 재생 클러스터에서 체인을 적용해 떴다)
-- self  = 이 파일 §2 · §3 · §6 본문의 md5(재적용 핀). 본문을 고치면 두 자리(여기 · MegaphoneBannerMigrationTests)를 같이 고친다.
insert into pg_temp.mgb_before (sig, canon_md5, self_md5, md5, attrs)
select t.sig, t.canon_md5, t.self_md5, md5(p.prosrc), pg_temp.mgb_attrs(p.oid)
  from (values
    ('public.megaphone_info()',           'aac80255efae548333eb9b2a71f0bb1f', '4b5645fcb482d013e9815180339ed373'),
    ('public.push_on_message_insert()',   'ebbeefee1a3296d78a362fa36bc8e440', '97bc8547dc451a76b4b2e6b4cafd3fb1'),
    ('public.send_megaphone(text,uuid)',  'da0ec946b8cb1cf01acad8ba26dba2b1', '715a5b9778ee02730d9d28805bdd846f')
  ) as t(sig, canon_md5, self_md5)
  left join pg_proc p on p.oid = to_regprocedure(t.sig);

do $pre$
declare
  v_fn    text;
  v_rel   text;
  v_n     int;
  v_first int := 0;
  v_again int := 0;
  r       record;
begin
  -- 본문이 부르는 것(plpgsql 은 만들 때 참조를 확인하지 않는다 — 없으면 첫 호출에서 터진다).
  foreach v_fn in array array[
    'auth.uid()', 'public.megaphone_enabled()', 'public.poke_blackout_active(timestamptz)',
    'public.normalize_message_body(text)', 'public.is_message_body(text)', 'public.message_max_length()',
    'public.megaphone_prefix()', 'public.megaphone_max_length()', 'public.megaphone_ruby_price()',
    'public.megaphone_cooldown_seconds()', 'public.megaphone__recipients(uuid)', 'public.poke_ring(uuid)',
    'public.poke_topic(uuid)', 'realtime.send(jsonb,text,text,boolean)', 'public.same_visibility(uuid,uuid)',
    'public.blocked_between(uuid,uuid)', 'public.push__enqueue(uuid,text,jsonb)', 'public.push_outbox_dispatch(bigint[])',
    'public.sticker_push_label(text)', 'public.message_retention_hours()', 'public.message_unread_summary()']
  loop
    if to_regprocedure(v_fn) is null then
      raise exception '§0 % 가 없다 — 이 파일은 확성기(20261014122000) · 이모티콘 푸시(20261022070340) 위에 얹는다. 배포 중단', v_fn;
    end if;
  end loop;
  foreach v_rel in array array['public.megaphones', 'public.messages', 'public.message_reads', 'public.profiles',
                               'public.ruby_ledger', 'public.push_outbox', 'public.user_blocks']
  loop
    if to_regclass(v_rel) is null then
      raise exception '§0 % 가 없다. 배포 중단', v_rel;
    end if;
  end loop;
  if not exists (select 1 from information_schema.columns c
                  where c.table_schema = 'public' and c.table_name = 'messages' and c.column_name = 'megaphone_id') then
    raise exception '§0 messages.megaphone_id 가 없다 — 확성기 줄을 알아볼 표식이 없다. 배포 중단';
  end if;
  -- 오버로드: 다시 쓰는 셋은 1, 새로 만드는 셋은 0(첫 적용) 또는 이 파일의 서명 하나(재적용).
  foreach v_fn in array array['send_megaphone', 'megaphone_info', 'push_on_message_insert']
  loop
    select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;
    if v_n <> 1 then
      raise exception '§0 % 오버로드가 % 개다(기대 1) — PGRST203. 배포 중단', v_fn, v_n;
    end if;
  end loop;
  for r in select * from (values ('megaphone_global_cooldown_seconds', 'public.megaphone_global_cooldown_seconds()'),
                                 ('megaphone_inbox', 'public.megaphone_inbox(integer)'),
                                 ('message_unread_summary_v2', 'public.message_unread_summary_v2()')) t(name, sig) loop
    select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = r.name;
    if v_n > 1 or (v_n = 1 and to_regprocedure(r.sig) is null) then
      raise exception '§0 % 가 다른 서명으로 이미 있다(% 개) — create or replace 가 오버로드를 만든다. 배포 중단', r.name, v_n;
    end if;
  end loop;
  -- 트리거가 지금도 이 함수를 부른다(아니면 S6 이 헛돈다).
  if not exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.messages'::regclass and not t.tgisinternal
                    and t.tgfoid = 'public.push_on_message_insert()'::regprocedure and t.tgenabled <> 'D') then
    raise exception '§0 messages 에 push_on_message_insert 를 부르는 켜진 트리거가 없다. 배포 중단';
  end if;
  -- 첫 적용이면 셋 다 정본 md5, 재적용이면 셋 다 이 파일 md5. 그 밖(다른 값 · 섞임)은 누가 손댄 것 — 멈춘다.
  for r in select * from pg_temp.mgb_before order by sig collate "C" loop
    if r.md5 is null then
      raise exception '§0 % 가 없다. 배포 중단', r.sig;
    elsif r.md5 = r.canon_md5 then
      v_first := v_first + 1;
    elsif r.md5 = r.self_md5 then
      v_again := v_again + 1;
    else
      raise exception '§0 % 본문 md5 가 정본(%)도 이 파일 결과(%)도 아닌 % 다 — 그 사이 누가 고쳤다. 저장소 최신 정의에서 '
                      '본문을 다시 떠 와라. 배포 중단', r.sig, r.canon_md5, r.self_md5, r.md5;
    end if;
  end loop;
  if not (v_first = 3 or v_again = 3) then
    raise exception '§0 세 함수 중 정본이 % 개 · 이 파일 결과가 % 개로 섞여 있다 — 누가 일부만 고쳤다. 배포 중단', v_first, v_again;
  end if;
  raise notice '§0 사전 단언 통과(%)', case when v_first = 3 then '첫 적용' else '재적용' end;
end
$pre$;


-- ── §1 상수(S1) ──────────────────────────────────────────────────────────────────────────
-- ★ PUBLIC 실행권을 **회수하지 않는다**(immutable 상수를 부르는 definer 함수가 42501 로 죽던 함정). 값은 화면이 그대로 보여 준다.
create or replace function public.megaphone_global_cooldown_seconds()
returns int language sql immutable as $fn$ select 300 $fn$;
comment on function public.megaphone_global_cooldown_seconds() is
  '앱 전체에서 확성기가 한 번 나간 뒤 다음 확성기까지의 초(300 = 5분, 20261105120000). 같은 쪽 계정(same_visibility)의 '
  '마지막 megaphones.created_at 으로 잰다. send_megaphone · megaphone_info 가 이 함수만 본다 — 리터럴을 다시 적지 마라.';


-- ── §2 send_megaphone(S2) — 정본(20261014122000) + 치환 3곳 ─────────────────────────────────
create or replace function public.send_megaphone(p_body text default null, p_request_id uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $send$
declare
  uid       uuid := auth.uid();
  v_req     uuid := coalesce(p_request_id, gen_random_uuid());
  v_max     constant int := public.message_max_length();
  v_usable  constant int := public.megaphone_max_length();
  v_price   constant int := public.megaphone_ruby_price();
  v_cool    constant int := public.megaphone_cooldown_seconds();
  v_gcool   constant int := public.megaphone_global_cooldown_seconds();
  v_today   date := (now() at time zone 'Asia/Seoul')::date;
  v_cleaned text;
  v_full    text;
  v_prev    public.megaphones%rowtype;
  v_last    timestamptz;
  v_glast   timestamptz;
  v_targets uuid[];
  v_n       int;
  v_bal     int;
  v_id      uuid;
  v_rows    int;
  v_target  uuid;
  v_sent    int := 0;
  v_failed  int := 0;
begin
  if uid is null then
    return jsonb_build_object('status', 'unauthorized');
  end if;
  if not public.megaphone_enabled() then
    return jsonb_build_object('status', 'disabled');
  end if;
  -- 발표 주간 차단(send_message 와 같은 검사). 아무것도 안 남기고 초인종도 안 울린다.
  if public.poke_blackout_active() then
    return jsonb_build_object('status', 'blackout');
  end if;

  -- 본문: send_message 와 같은 정규화 · 같은 판정 함수(표 CHECK 가 부르는 것) — 판정은 **표식을 붙인 뒤의 글**로 한다.
  v_cleaned := public.normalize_message_body(p_body);
  if v_cleaned = '' then
    return jsonb_build_object('status', 'empty', 'max_length', v_usable);
  end if;
  v_full := public.megaphone_prefix() || v_cleaned;
  if not public.is_message_body(v_full) then
    -- 길이만이 문제일 때만 too_long(문구 고르기 — send_message 와 같은 순서). 상한은 **쓸 수 있는 길이**(198)로 말한다.
    if char_length(v_full) > v_max and public.is_message_body(left(v_full, v_max)) then
      return jsonb_build_object('status', 'too_long', 'max_length', v_usable);
    end if;
    return jsonb_build_object('status', 'not_text', 'max_length', v_usable);
  end if;

  -- ★ 지갑 자물쇠 — 루비를 깎는 다른 RPC(buy_ultra · buy_character · 오목/체스 판돈)와 **같은 키**다.
  --   이 줄이 멱등키 확인보다 앞이라, 같은 request_id 의 두 요청이 동시에 와도 둘째는 첫째의 커밋을 본다.
  perform pg_advisory_xact_lock(hashtext('ultra_wallet:' || uid::text));

  -- 멱등키: 이미 보낸 요청이면 **처음 결과**를 그대로(아무것도 다시 깎지 않는다).
  select m.* into v_prev from public.megaphones m where m.sender = uid and m.request_id = v_req;
  if found then
    select p.ruby_balance into v_bal from public.profiles p where p.id = uid;
    return jsonb_build_object('status', 'ok', 'duplicate', true, 'megaphone_id', v_prev.id,
                              'recipients', v_prev.recipients, 'price', v_prev.price,
                              'ruby_balance', v_bal, 'body', v_prev.body);
  end if;

  -- 쿨타임: 보낸이당 megaphone_cooldown_seconds() 에 한 번.
  select max(m.created_at) into v_last from public.megaphones m where m.sender = uid;
  if v_last is not null and v_last + make_interval(secs => v_cool) > now() then
    return jsonb_build_object('status', 'cooldown', 'scope', 'self', 'cooldown_seconds', v_cool,
                              'retry_after_seconds',
                              greatest(1, ceil(extract(epoch from (v_last + make_interval(secs => v_cool) - now())))::int));
  end if;

  -- 앱 전체 한 번에 하나(20261105120000): 누가 보내면 그 뒤 megaphone_global_cooldown_seconds() 동안 아무도 못 보낸다.
  --   멱등키 · 사람당 창 **뒤**라 같은 요청 재시도는 자기가 연 창에 안 막히고, 자기 창이면 self 로 답한다.
  --   자물쇠(지갑 다음 · 언제나 이 순서)를 쥔 뒤의 새 스냅숏으로 읽는다 — 동시에 온 두 사람 중 하나만 지난다.
  --   같은 쪽 계정(same_visibility)만 센다 — 숨김(심사 · 시험) 계정의 확성기가 실사용자를 막지 않는다.
  perform pg_advisory_xact_lock(hashtext('megaphone_global'));
  select max(m.created_at) into v_glast
    from public.megaphones m
   where m.created_at > now() - make_interval(secs => v_gcool)
     and public.same_visibility(uid, m.sender);
  if v_glast is not null and v_glast + make_interval(secs => v_gcool) > now() then
    return jsonb_build_object('status', 'cooldown', 'scope', 'global', 'cooldown_seconds', v_gcool,
                              'retry_after_seconds',
                              greatest(1, ceil(extract(epoch from (v_glast + make_interval(secs => v_gcool) - now())))::int));
  end if;

  -- 받는 사람: 미리보기(megaphone_info)와 같은 술어. 0명이면 **깎지 않는다.**
  select coalesce(array_agg(r.id order by r.id), '{}'::uuid[]) into v_targets
    from public.megaphone__recipients(uid) as r(id);
  v_n := coalesce(array_length(v_targets, 1), 0);
  if v_n = 0 then
    return jsonb_build_object('status', 'no_recipients', 'recipients', 0);
  end if;

  select p.ruby_balance into v_bal from public.profiles p where p.id = uid for update;
  if not found then
    return jsonb_build_object('status', 'no_profile');
  end if;
  if v_bal < v_price then
    return jsonb_build_object('status', 'insufficient', 'need', v_price, 'have', v_bal,
                              'ruby_balance', v_bal, 'price', v_price, 'recipients', v_n);
  end if;

  -- 차감과 장부는 **짝**이다(buy_ultra 와 같은 관용구). 장부 detail 에 원장 id 를 적어 둔다.
  v_id := gen_random_uuid();
  update public.profiles set ruby_balance = ruby_balance - v_price
   where id = uid returning ruby_balance into v_bal;
  insert into public.ruby_ledger (user_id, kst_day, reason, delta, balance_after, detail)
  values (uid, v_today, 'spend:megaphone', -v_price, v_bal,
          jsonb_build_object('megaphone_id', v_id, 'recipients', v_n, 'price', v_price));

  insert into public.megaphones (id, sender, body, request_id, recipients, price)
  values (v_id, uid, v_full, v_req, v_n, v_price);

  -- ★ fan-out: 받는 사람마다 평범한 메시지 한 줄(옛 앱이 그대로 받는다). 푸시는 기존 messages 트리거가 행마다 보낸다.
  insert into public.messages (from_user, to_user, body, megaphone_id)
  select uid, t.id, v_full, v_id from unnest(v_targets) as t(id);
  get diagnostics v_rows = row_count;
  if v_rows <> v_n then
    raise exception 'send_megaphone fan-out 이 %행이다(기대 %) — 롤백', v_rows, v_n;
  end if;

  -- 초인종: send_message 와 같은 문(삽입 **뒤** — pending 이 이번 발사를 포함해야 한다). strict=false 라 실패해도 'failed' 만.
  foreach v_target in array v_targets loop
    if public.poke_ring(v_target) = 'sent' then v_sent := v_sent + 1; else v_failed := v_failed + 1; end if;
    -- 배너 신호(20261105120000): 새 앱은 이걸 듣고 megaphone_inbox 를 다시 부른다(payload 는 믿지 않는다). 옛 앱은 접는다.
    --   실패는 삼킨다 — 신호가 루비 차감 · fan-out 을 되돌리면 안 된다(초인종과 같은 결).
    begin
      perform realtime.send(jsonb_build_object('v', 1, 'm', v_id), 'megaphone', public.poke_topic(v_target), true);
    exception when others then
      raise warning 'send_megaphone: 배너 신호를 삼켰다(SQLSTATE %) — 루비 · 메시지는 그대로', sqlstate;
    end;
  end loop;

  return jsonb_build_object('status', 'ok', 'duplicate', false, 'megaphone_id', v_id, 'recipients', v_n,
                            'price', v_price, 'ruby_balance', v_bal, 'body', v_full,
                            'ring_sent', v_sent, 'ring_failed', v_failed);
end;
$send$;

comment on function public.send_megaphone(text, uuid) is
  '확성기(20261014122000 · 배너 20261105120000): 루비 megaphone_ruby_price() 개로 받는 사람(megaphone__recipients) 모두에게 📢 표식을 붙인 1:1 메시지를 한 줄씩 보낸다. '
  '한 트랜잭션: 자물쇠(ultra_wallet:) → 멱등키 → 사람당 창(scope self) → 자물쇠(megaphone_global) → 앱 전체 창(scope global, 같은 쪽 계정) → 받는 사람 → 잔량 → 차감+장부(spend:megaphone) → 원장 → fan-out → 초인종 + megaphone 신호. '
  '응답: ok{megaphone_id, recipients, price, ruby_balance, body, duplicate} · cooldown{scope, cooldown_seconds, retry_after_seconds} · insufficient{need, have} · '
  'no_recipients · empty · not_text · too_long{max_length} · disabled · blackout · no_profile · unauthorized. 같은 p_request_id 는 처음 결과를 duplicate:true 로.';


-- ── §3 megaphone_info(S3) — 정본(20261014122000) + 치환 3곳 ─────────────────────────────────
create or replace function public.megaphone_info()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $info$
declare
  uid      uuid := auth.uid();
  v_last   timestamptz;
  v_remain int := 0;
  v_glast  timestamptz;
  v_gleft  int := 0;
  v_n      int;
  v_bal    int;
begin
  if uid is null then
    return jsonb_build_object('status', 'unauthorized');
  end if;
  select max(m.created_at) into v_last from public.megaphones m where m.sender = uid;
  if v_last is not null then
    v_remain := greatest(0, ceil(extract(epoch from
                  (v_last + make_interval(secs => public.megaphone_cooldown_seconds()) - now())))::int);
  end if;
  -- 앱 전체 창(20261105120000): send_megaphone 과 같은 창 · 같은 쪽 계정의 마지막 확성기.
  select max(m.created_at) into v_glast
    from public.megaphones m
   where m.created_at > now() - make_interval(secs => public.megaphone_global_cooldown_seconds())
     and public.same_visibility(uid, m.sender);
  if v_glast is not null then
    v_gleft := greatest(0, ceil(extract(epoch from
                 (v_glast + make_interval(secs => public.megaphone_global_cooldown_seconds()) - now())))::int);
  end if;
  select count(*)::int into v_n from public.megaphone__recipients(uid);
  select p.ruby_balance into v_bal from public.profiles p where p.id = uid;
  return jsonb_build_object(
    'status', 'ok',
    'enabled', public.megaphone_enabled(),
    'price', public.megaphone_ruby_price(),
    'cooldown_seconds', public.megaphone_cooldown_seconds(),
    -- 옛 앱 작성 화면은 이 한 칸만 본다 — 둘 중 긴 쪽이라야 "N분 뒤에" 가 맞는다.
    'cooldown_remaining_seconds', greatest(v_remain, v_gleft),
    'global_cooldown_seconds', public.megaphone_global_cooldown_seconds(),
    'global_cooldown_remaining_seconds', v_gleft,
    'cooldown_scope', case when v_remain > 0 and v_remain >= v_gleft then 'self'
                           when v_gleft > 0 then 'global' end,
    'recipients', v_n,
    'max_length', public.megaphone_max_length(),
    'ruby_balance', v_bal);
end;
$info$;

comment on function public.megaphone_info() is
  '확성기 작성 화면용(20261014122000 · 배너 20261105120000): {status:ok, enabled, price, cooldown_seconds, cooldown_remaining_seconds, recipients, '
  'max_length, ruby_balance, global_cooldown_seconds, global_cooldown_remaining_seconds, cooldown_scope} · unauthorized. '
  'cooldown_remaining_seconds = max(사람당 남은 초, 앱 전체 남은 초) — 옛 앱이 이 한 칸만 본다. cooldown_scope 는 긴 쪽(self | global | null).';


-- ── §4 megaphone_inbox(S4) — 내가 받은 확성기 줄 ───────────────────────────────────────────
-- 새 앱 메시지함 필터의 유일한 근거(message_id 집합)이자 배너 본문의 출처. 신호 payload 는 믿지 않고 이것을 다시 부른다.
-- profiles 는 함수 안에서 조인한다(PostgREST 임베드 모호성 회피). 본문은 접두를 뗀 글.
create or replace function public.megaphone_inbox(p_hours integer default 24)
returns table(message_id uuid, megaphone_id uuid, sender_id uuid, sender_display_name text, sender_avatar_url text,
              body text, created_at timestamptz, created_epoch bigint)
language sql
stable
security definer
set search_path = public
as $inbox$
  select m.id,
         m.megaphone_id,
         m.from_user,
         coalesce(pr.display_name, '사용자'),
         pr.avatar_url,
         case when left(m.body, char_length(public.megaphone_prefix())) = public.megaphone_prefix()
              then substr(m.body, char_length(public.megaphone_prefix()) + 1)
              else m.body end,
         m.created_at,
         extract(epoch from m.created_at)::bigint
    from public.messages m
    left join public.profiles pr on pr.id = m.from_user
   -- ★ 벽: 내가 받은 줄만. 손대지 마라.
   where m.to_user = auth.uid()
     and m.megaphone_id is not null
     and not public.blocked_between(auth.uid(), m.from_user)
     and m.created_at >= now() - make_interval(hours => least(greatest(coalesce(p_hours, 24), 1), 24))
   order by m.created_at desc, m.id desc
   limit 20
$inbox$;

comment on function public.megaphone_inbox(integer) is
  '내가 받은 확성기 줄(20261105120000): to_user = 나 · megaphone_id 있음 · 차단 아님 · 최근 least(greatest(p_hours,1),24) 시간 · 최신 20개. '
  '{message_id, megaphone_id, sender_id, sender_display_name, sender_avatar_url, body(접두 뗌), created_at, created_epoch}.';
revoke all on function public.megaphone_inbox(integer) from public, anon;
grant execute on function public.megaphone_inbox(integer) to authenticated;


-- ── §5 message_unread_summary_v2(S5) — 안 읽음 집계(v1 · 20260918180000) + 확성기 줄 제외 ─────────
-- v1 은 다시 정의하지 않는다(V0333 관문 · 옛 앱). 새 앱은 확성기 줄을 메시지함에서 빼므로 그 줄은 영영 읽히지 않는다 —
-- v1 을 세면 배지가 꺼지지 않는다. 새 앱 배지(메뉴바 점 · 탭 · 아이콘)는 이것만 센다.
create or replace function public.message_unread_summary_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_uid   uuid := auth.uid();
  v_peers jsonb;
  v_total int;
begin
  if v_uid is null then
    return jsonb_build_object('status', 'unauthorized');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('peer_user_id', s.peer, 'count', s.n, 'last_epoch_ms', s.last_ms)
                            order by s.last_ms desc, s.peer), '[]'::jsonb),
         coalesce(sum(s.n), 0)::int
    into v_peers, v_total
    from (
      select m.from_user as peer,
             count(*)::int as n,
             floor(extract(epoch from max(m.created_at)) * 1000)::bigint as last_ms
        from public.messages m
        left join public.message_reads r on r.reader_id = v_uid and r.peer_id = m.from_user
       -- ★ 벽: 내가 **받은** 행만(to_user = auth.uid()).
       where m.to_user = v_uid
         and m.created_at >= now() - make_interval(hours => public.message_retention_hours())
         -- 차단(20260918180000): 차단한 상대의 안 읽음은 세지 않는다(메뉴바 점·탭 배지가 사라진 대화를 가리키면 안 된다).
         and not public.blocked_between(v_uid, m.from_user)
         -- 확성기 줄(20261105120000): 배너로만 보이고 메시지함에 없다 — 세면 배지가 꺼지지 않는다.
         and m.megaphone_id is null
         and (r.read_until is null or m.created_at > r.read_until)
       group by m.from_user
    ) s;
  return jsonb_build_object('status', 'ok', 'total', v_total, 'peers', v_peers);
end;
$fn$;

comment on function public.message_unread_summary_v2() is
  '안 읽음 집계 v2(20261105120000): v1 과 같은 모양 {status, total, peers[{peer_user_id, count, last_epoch_ms}]} · 확성기 줄(megaphone_id 있음)은 세지 않는다.';
revoke all on function public.message_unread_summary_v2() from public, anon;
grant execute on function public.message_unread_summary_v2() to authenticated;


-- ── §6 push_on_message_insert(S6) — 정본(20261022070340) + 치환 1곳 ──────────────────────────
create or replace function public.push_on_message_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_id bigint;
begin
  begin
    v_id := public.push__enqueue(
      new.to_user,
      'message',
      jsonb_build_object(
        'aps', jsonb_build_object(
                 'alert', jsonb_build_object(
                            'title', coalesce((select pr.display_name from public.profiles pr where pr.id = new.from_user), '사용자'),
                            'body',  public.sticker_push_label(new.body)),
                 'sound', 'default',
                 'category', 'MESSAGE',
                 'thread-id', 'message-' || new.from_user::text),
        'type', 'message',
        'peer_id', new.from_user,
        'message_id', new.id,
        '_apns', jsonb_build_object(
                   'expiration', floor(extract(epoch from new.created_at
                                                 + make_interval(hours => public.message_retention_hours())))::bigint,
                   'collapse_id', null))
      -- 확성기 줄만(20261105120000): 최상위 megaphone_id — 새 폰은 눌러 들어오면 배너로 띄운다. 평범한 1:1 은 키가 없다.
      || case when new.megaphone_id is not null
              then jsonb_build_object('megaphone_id', new.megaphone_id)
              else '{}'::jsonb end);
  exception when others then
    raise warning 'push_on_message_insert: 발송함 적재를 삼켰다(SQLSTATE %) — 메시지는 그대로 저장된다', sqlstate;
    return null;
  end;

  if v_id is not null then
    begin
      perform public.push_outbox_dispatch(array[v_id]);
    exception when others then
      raise warning 'push_on_message_insert: 발송 호출을 삼켰다(SQLSTATE %) — 행은 pending, push-retry 가 다시 보낸다', sqlstate;
    end;
  end if;
  return null;
end
$fn$;

comment on function public.push_on_message_insert() is
  'messages AFTER INSERT → 받는 사람(to_user) 발송함 적재 + 발송 호출. 모든 오류를 삼킨다. 아잉이 이모티콘 본문은 sticker_push_label 로 읽을 수 있게 바꿔 담는다. '
  '확성기 줄이면 최상위 megaphone_id 를 더한다(20261105120000) — type message · category MESSAGE 는 그대로.';


-- ── §7 실행권 ── 다시 쓴 셋은 create or replace 라 ACL 이 그대로다(같은 grant 를 다시 준다 — §8 (2) 가 직전과 대조).
grant execute on function public.send_megaphone(text, uuid) to authenticated;
grant execute on function public.megaphone_info() to authenticated;


-- ── §8 사후 단언 ───────────────────────────────────────────────────────────────────────────
do $assert$
declare
  r        record;
  v_oid    oid;
  v_src    text;
  v_n      int;
  v_wallet int;
  v_dup    int;
  v_self   int;
  v_lock   int;
  v_glob   int;
  v_charge int;
  v_ring   int;
  v_sig    int;
  v_tok    text;
  v_probes int := 0;
begin
  -- (1) 상수: immutable · 값 300 · PUBLIC 실행권 그대로(definer 함수들이 부른다)
  v_oid := to_regprocedure('public.megaphone_global_cooldown_seconds()');
  if v_oid is null or (select p.provolatile from pg_proc p where p.oid = v_oid) <> 'i'
     or public.megaphone_global_cooldown_seconds() is distinct from 300 then
    raise exception '(1) megaphone_global_cooldown_seconds 가 immutable 300 이 아니다. 배포 중단';
  end if;
  if not (has_function_privilege('public', v_oid, 'EXECUTE') and has_function_privilege('anon', v_oid, 'EXECUTE')
          and has_function_privilege('authenticated', v_oid, 'EXECUTE')) then
    raise exception '(1) megaphone_global_cooldown_seconds 의 PUBLIC 실행권이 빠졌다 — 42501 함정. 배포 중단';
  end if;
  v_probes := v_probes + 1;

  -- (2) 다시 쓴 셋: 오버로드 1 · 본문 = 이 파일 결과(재적용 핀) · oid · 실행권 · 속성이 직전과 같다
  for r in select * from pg_temp.mgb_before order by sig collate "C" loop
    v_oid := to_regprocedure(r.sig);
    select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = (select p2.proname from pg_proc p2 where p2.oid = v_oid);
    if v_n <> 1 then
      raise exception '(2) % 오버로드가 % 개다 — PGRST203. 배포 중단', r.sig, v_n;
    end if;
    if (select md5(p.prosrc) from pg_proc p where p.oid = v_oid) is distinct from r.self_md5 then
      raise exception '(2) % 의 본문 md5 가 이 파일 결과(%)가 아니다 — §0 핀과 본문이 어긋났다. 배포 중단', r.sig, r.self_md5;
    end if;
    if pg_temp.mgb_attrs(v_oid) is distinct from r.attrs then
      raise exception '(2) % 의 oid · 실행권 · 속성이 바뀌었다(전 % · 후 %) — 이 파일은 본문만 바꾼다. 배포 중단',
        r.sig, r.attrs, pg_temp.mgb_attrs(v_oid);
    end if;
  end loop;
  v_probes := v_probes + 1;

  -- (3) 새 RPC 둘: definer · search_path=public · 인자 전부 DEFAULT · 오버로드 1 · anon/PUBLIC 실행권 0 · authenticated 는 된다
  for r in select * from (values ('megaphone_inbox', 'public.megaphone_inbox(integer)'),
                                 ('message_unread_summary_v2', 'public.message_unread_summary_v2()')) t(name, sig) loop
    v_oid := to_regprocedure(r.sig);
    if v_oid is null then
      raise exception '(3) % 가 없다. 배포 중단', r.sig;
    end if;
    select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = r.name;
    if v_n <> 1 then
      raise exception '(3) % 오버로드가 % 개다 — PGRST203. 배포 중단', r.name, v_n;
    end if;
    if not (select p.prosecdef and p.proconfig::text = '{search_path=public}' and p.pronargdefaults = p.pronargs
              from pg_proc p where p.oid = v_oid) then
      raise exception '(3) % 가 definer · search_path=public · 인자 전부 DEFAULT 가 아니다. 배포 중단', r.sig;
    end if;
    if has_function_privilege('public', v_oid, 'EXECUTE') or has_function_privilege('anon', v_oid, 'EXECUTE') then
      raise exception '(3) % 를 로그인 없이 부를 수 있다. 배포 중단', r.sig;
    end if;
    if not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
      raise exception '(3) authenticated 가 % 를 못 부른다. 배포 중단', r.sig;
    end if;
  end loop;
  v_probes := v_probes + 1;

  -- (4) send_megaphone 순서: 지갑 자물쇠 → 멱등키 → 사람당(self) → 전역 자물쇠 → 앱 전체 창(global) → 차감, 초인종 → 신호(삼킴)
  select p.prosrc into v_src from pg_proc p where p.oid = 'public.send_megaphone(text,uuid)'::regprocedure;
  v_wallet := strpos(v_src, 'perform pg_advisory_xact_lock(hashtext(''ultra_wallet:'' || uid::text));');
  v_dup    := strpos(v_src, 'select m.* into v_prev from public.megaphones m where m.sender = uid and m.request_id = v_req;');
  v_self   := strpos(v_src, '''status'', ''cooldown'', ''scope'', ''self''');
  v_lock   := strpos(v_src, 'perform pg_advisory_xact_lock(hashtext(''megaphone_global''));');
  v_glob   := strpos(v_src, '''status'', ''cooldown'', ''scope'', ''global''');
  v_charge := strpos(v_src, 'update public.profiles set ruby_balance = ruby_balance - v_price');
  if not (0 < v_wallet and v_wallet < v_dup and v_dup < v_self and v_self < v_lock and v_lock < v_glob and v_glob < v_charge) then
    raise exception '(4) send_megaphone 순서가 지갑(%) → 멱등(%) → 사람당(%) → 전역 자물쇠(%) → 앱 전체(%) → 차감(%) 이 아니다. 배포 중단',
      v_wallet, v_dup, v_self, v_lock, v_glob, v_charge;
  end if;
  if strpos(v_src, 'and public.same_visibility(uid, m.sender)') = 0 or strpos(v_src, 'public.megaphone_ruby_price()') = 0 then
    raise exception '(4) send_megaphone 앱 전체 창에 same_visibility 가 없거나 가격을 megaphone_ruby_price() 로 안 부른다. 배포 중단';
  end if;
  v_ring := strpos(v_src, 'if public.poke_ring(v_target) = ''sent'' then');
  v_sig  := strpos(v_src, 'perform realtime.send(jsonb_build_object(''v'', 1, ''m'', v_id), ''megaphone'', public.poke_topic(v_target), true);');
  if v_ring = 0 or v_sig < v_ring or strpos(substr(v_src, v_sig), 'exception when others then') = 0 then
    raise exception '(4) send_megaphone 의 megaphone 신호가 초인종 뒤에 없거나 예외를 삼키지 않는다. 배포 중단';
  end if;
  v_probes := v_probes + 1;

  -- (5) 나머지 계약 줄: info 의 max · inbox 벽 · v2 제외 · 푸시 키
  select p.prosrc into v_src from pg_proc p where p.oid = 'public.megaphone_info()'::regprocedure;
  if strpos(v_src, '''cooldown_remaining_seconds'', greatest(v_remain, v_gleft)') = 0
     or strpos(v_src, 'public.megaphone_ruby_price()') = 0 then
    raise exception '(5) megaphone_info 가 남은 시간을 둘 중 긴 쪽으로 안 말하거나 가격 함수를 안 부른다. 배포 중단';
  end if;
  select p.prosrc into v_src from pg_proc p where p.oid = 'public.megaphone_inbox(integer)'::regprocedure;
  foreach v_tok in array array['where m.to_user = auth.uid()', 'and m.megaphone_id is not null',
                               'and not public.blocked_between(auth.uid(), m.from_user)', 'limit 20'] loop
    if strpos(v_src, v_tok) = 0 then
      raise exception '(5) megaphone_inbox 에 "%" 가 없다. 배포 중단', v_tok;
    end if;
  end loop;
  select p.prosrc into v_src from pg_proc p where p.oid = 'public.message_unread_summary_v2()'::regprocedure;
  foreach v_tok in array array['where m.to_user = v_uid', 'and not public.blocked_between(v_uid, m.from_user)',
                               'and m.megaphone_id is null'] loop
    if strpos(v_src, v_tok) = 0 then
      raise exception '(5) message_unread_summary_v2 에 "%" 가 없다. 배포 중단', v_tok;
    end if;
  end loop;
  select p.prosrc into v_src from pg_proc p where p.oid = 'public.push_on_message_insert()'::regprocedure;
  foreach v_tok in array array['then jsonb_build_object(''megaphone_id'', new.megaphone_id)', '''type'', ''message'',',
                               '''category'', ''MESSAGE'',', 'public.sticker_push_label(new.body)', 'exception when others then'] loop
    if strpos(v_src, v_tok) = 0 then
      raise exception '(5) push_on_message_insert 에 "%" 가 없다. 배포 중단', v_tok;
    end if;
  end loop;
  v_probes := v_probes + 1;

  raise notice '§8 사후 단언 전부 통과(검사 %건)', v_probes;
end
$assert$;


-- ── §9 흐름 프로브(실호출 — 센티널 예외로 통째 롤백) ────────────────────────────────────────
-- 사용자 흉내 도구(임시 스키마). p_uid 가 null 이면 anon.
create or replace function pg_temp.mgb_as(p_uid uuid)
returns void language plpgsql as $tmp$
begin
  if p_uid is null then
    perform set_config('request.jwt.claims', jsonb_build_object('role', 'anon')::text, true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claim.role', 'anon', true);
    execute 'set local role anon';
    return;
  end if;
  perform set_config('request.jwt.claims',
                     jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aud', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
end $tmp$;

-- 그 사람으로 jsonb 한 값 → 원래 역할로 복귀.
create or replace function pg_temp.mgb_rpc(p_uid uuid, p_sql text)
returns jsonb language plpgsql as $tmp$
declare v_back text := current_user; v jsonb;
begin
  perform pg_temp.mgb_as(p_uid);
  execute p_sql into v;
  execute format('set local role %I', v_back);
  return v;
end $tmp$;

-- 그 사람으로 문장 하나 → SQLSTATE(성공이면 'ok'). 원래 역할로 복귀.
create or replace function pg_temp.mgb_err(p_uid uuid, p_sql text)
returns text language plpgsql as $tmp$
declare v_back text := current_user; v_state text := 'ok';
begin
  begin
    perform pg_temp.mgb_as(p_uid);
    execute p_sql;
  exception when others then
    v_state := sqlstate;
  end;
  execute format('set local role %I', v_back);
  return v_state;
end $tmp$;

-- 그 사람으로 확성기 한 번.
create or replace function pg_temp.mgb_send(p_uid uuid, p_body text, p_req uuid)
returns jsonb language plpgsql as $tmp$
begin
  return pg_temp.mgb_rpc(p_uid, format('select public.send_megaphone(p_body => %L, p_request_id => %L::uuid)', p_body, p_req));
end $tmp$;

-- ★ 이 블록 안 주석에 달러 태그 글자를 적지 마라. 뽑은 값 비교는 is distinct from. 기대 숫자는 전후 델타.
do $probe$
declare
  v_exec_role text := current_user;
  v_expected  constant int := 13;
  probes      int := 0;
  v_synth     boolean := false;
  v_price     constant int := public.megaphone_ruby_price();
  v_cool      constant int := public.megaphone_cooldown_seconds();
  v_gcool     constant int := public.megaphone_global_cooldown_seconds();
  v_pre       constant text := public.megaphone_prefix();
  a uuid; b uuid; c uuid; h1 uuid; h2 uuid;
  ra  uuid := gen_random_uuid();
  v    jsonb;
  v1   jsonb;
  v2   jsonb;
  v1_0 jsonb;
  v2_0 jsonb;
  v_n  int;
  v_k  int;
  a_mid  uuid;
  h_mid  uuid;
  c_msg  uuid;
  b_msg  uuid;
  fake   uuid;
  old_id uuid;
  v_blk  text;
  v_en   text;
begin
  begin
    --------------------------------------------------------------------------------------------
    -- 픽스처: a · b(보내는 실사용자) · c(받는 실사용자 · 폰 하나) · h1 · h2(숨김). 합성 계정이 되면 합성, 아니면 숨김 아닌
    -- 일반 프로필 다섯을 빌린다(빌린 값은 센티널 롤백으로 전부 되돌아간다).
    --------------------------------------------------------------------------------------------
    if has_table_privilege('auth.users', 'INSERT') then
      v_synth := true;
      a := gen_random_uuid(); b := gen_random_uuid(); c := gen_random_uuid(); h1 := gen_random_uuid(); h2 := gen_random_uuid();
      insert into auth.users (id, email, raw_user_meta_data)
        select u.id, 'megaphone-banner-probe-' || u.tag || '-' || u.id || '@example.invalid',
               jsonb_build_object('display_name', 'MGB-' || u.tag || '-' || left(u.id::text, 8))
          from unnest(array[a, b, c, h1, h2], array['a', 'b', 'c', 'h1', 'h2']) as u(id, tag);
      insert into public.profiles (id, email, display_name)
        select u.id, 'megaphone-banner-probe-' || u.tag || '-' || u.id || '@example.invalid',
               'MGB-' || u.tag || '-' || left(u.id::text, 8)
          from unnest(array[a, b, c, h1, h2], array['a', 'b', 'c', 'h1', 'h2']) as u(id, tag)
      on conflict (id) do nothing;
    else
      select s.ids[1], s.ids[2], s.ids[3], s.ids[4], s.ids[5] into a, b, c, h1, h2
        from (select array_agg(q.id order by q.created_at, q.id) as ids
                from (select p.id, p.created_at from public.profiles p
                       where not public.is_hidden_user(p.id)
                       order by p.created_at, p.id limit 5) q) s;
      if h2 is null then
        raise exception '§9 픽스처를 만들 수도 빌릴 수도 없다 — 프로브가 no-op 인 채로 배포되면 안 된다, 배포 중단';
      end if;
    end if;
    update public.profiles set ruby_balance = 100, focus_mode = false, is_hidden = false where id in (a, b, c);
    update public.profiles set ruby_balance = 100, focus_mode = false, is_hidden = true  where id in (h1, h2);
    delete from public.user_blocks where blocker in (a, b, c, h1, h2) or blocked in (a, b, c, h1, h2);
    if public.is_hidden_user(a) or public.is_hidden_user(b) or public.is_hidden_user(c)
       or not public.is_hidden_user(h1) or not public.is_hidden_user(h2) then
      raise exception '§9 픽스처의 숨김 여부가 기대와 다르다';
    end if;
    -- c 의 폰 하나(발송함 행이 생기게). 일하는 중이 아니라 억제되지 않는다.
    insert into public.client_devices (user_id, installation_id, platform, app_build, apns_token, apns_env)
    values (c, gen_random_uuid(), 'ios', 1, repeat('ab', 32), 'sandbox');
    -- 지금 창 안에 있는 확성기(운영의 실제 행 포함)를 창 밖으로 민다 — 이 블록 안에서만(센티널 롤백이 되돌린다).
    update public.megaphones set created_at = created_at - make_interval(secs => greatest(v_cool, v_gcool) + 1)
     where created_at > now() - make_interval(secs => greatest(v_cool, v_gcool) + 1);
    -- 조용한 기간 · 스위치가 막으면 이 블록 안에서만 연다(센티널 롤백이 되돌리고, 끝에서도 원문으로 되돌린다).
    if public.poke_blackout_active() then
      select pg_get_functiondef('public.poke_blackout_active(timestamp with time zone)'::regprocedure) into v_blk;
      execute 'create or replace function public.poke_blackout_active(p_at timestamptz default now()) '
              'returns boolean language sql stable as ''select false''';
    end if;
    if not public.megaphone_enabled() then
      select pg_get_functiondef('public.megaphone_enabled()'::regprocedure) into v_en;
      execute 'create or replace function public.megaphone_enabled() returns boolean language sql immutable as ''select true''';
    end if;

    --------------------------------------------------------------------------------------------
    -- ① 비교 기준선: 아무도 안 보낸 때 a 의 작성 화면 — 남은 시간 0 · scope 없음 · 새 키 · 옛 키 그대로
    --------------------------------------------------------------------------------------------
    v := pg_temp.mgb_rpc(a, 'select public.megaphone_info()');
    if v ->> 'status' is distinct from 'ok' or (v ->> 'cooldown_remaining_seconds')::int is distinct from 0
       or (v ->> 'global_cooldown_remaining_seconds')::int is distinct from 0
       or (v ->> 'global_cooldown_seconds')::int is distinct from v_gcool
       or not (v ? 'cooldown_scope') or jsonb_typeof(v -> 'cooldown_scope') is distinct from 'null'
       or (v ->> 'price')::int is distinct from v_price or (v ->> 'cooldown_seconds')::int is distinct from v_cool
       or not (v ?& array['enabled', 'recipients', 'max_length', 'ruby_balance']) then
      raise exception '① 기준선 작성 화면이 %', v;
    end if;
    -- c 의 안 읽음 기준선(⑪ 이 전후 델타로 잰다 — 빌린 계정이면 이전 줄이 있다).
    v1_0 := pg_temp.mgb_rpc(c, 'select public.message_unread_summary()');
    v2_0 := pg_temp.mgb_rpc(c, 'select public.message_unread_summary_v2()');
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ② h1(숨김)이 먼저 보낸다 → ok(숨김 쪽 받는 사람에게만)
    --------------------------------------------------------------------------------------------
    v := pg_temp.mgb_send(h1, '숨김 쪽 확성기', gen_random_uuid());
    if v ->> 'status' is distinct from 'ok' then
      raise exception '② 숨김 계정 확성기가 %', v;
    end if;
    h_mid := (v ->> 'megaphone_id')::uuid;
    if exists (select 1 from public.messages m where m.megaphone_id = h_mid and m.to_user in (a, b, c)) then
      raise exception '② 숨김 계정 확성기가 실사용자에게 갔다';
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ③ a 가 보낸다 → 숨김 쪽 창에 안 막힌다 · 차감 · 장부 · 원장 · fan-out(접두 · megaphone_id)은 예전 그대로
    --------------------------------------------------------------------------------------------
    select count(*)::int into v_n from public.megaphone__recipients(a);
    v := pg_temp.mgb_send(a, '실사용자 확성기', ra);
    if v ->> 'status' is distinct from 'ok' or (v ->> 'duplicate')::boolean is distinct from false
       or (v ->> 'recipients')::int is distinct from v_n or (v ->> 'price')::int is distinct from v_price then
      raise exception '③ a 의 확성기가 % (기대 ok · recipients % · 숨김 계정 창에 안 막힘)', v, v_n;
    end if;
    a_mid := (v ->> 'megaphone_id')::uuid;
    if (select p.ruby_balance from public.profiles p where p.id = a) is distinct from 100 - v_price
       or (v ->> 'ruby_balance')::int is distinct from 100 - v_price then
      raise exception '③ a 의 루비가 100 - % 가 아니다(%)', v_price, v;
    end if;
    if (select count(*) from public.ruby_ledger l
         where l.user_id = a and l.reason = 'spend:megaphone' and l.delta = -v_price
           and l.detail ->> 'megaphone_id' = a_mid::text) <> 1 then
      raise exception '③ 장부 spend:megaphone 한 줄이 없다';
    end if;
    if (select count(*) from public.megaphones m where m.sender = a) <> 1
       or (select count(*) from public.messages m where m.megaphone_id = a_mid) <> v_n
       or exists (select 1 from public.messages m where m.megaphone_id = a_mid and m.body <> v_pre || '실사용자 확성기')
       or exists (select 1 from public.messages m where m.megaphone_id = a_mid and (m.from_user <> a or m.to_user in (a, h1, h2))) then
      raise exception '③ 원장 · fan-out 이 예전 모양이 아니다';
    end if;
    select m.id into c_msg from public.messages m where m.megaphone_id = a_mid and m.to_user = c;
    select m.id into b_msg from public.messages m where m.megaphone_id = a_mid and m.to_user = b;
    if c_msg is null or b_msg is null then
      raise exception '③ c · b 가 a 의 확성기 줄을 안 받았다';
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ④ 배너 신호: 받는 사람마다 하나 · c 의 초인종 주제 · {v:1, m:<확성기 id>}
    --------------------------------------------------------------------------------------------
    select count(*)::int into v_k from realtime.messages rm
     where rm.inserted_at >= now() - interval '1 minute' and rm.event = 'megaphone' and rm.payload ->> 'm' = a_mid::text;
    if v_k <> v_n or not exists (select 1 from realtime.messages rm
                                  where rm.inserted_at >= now() - interval '1 minute' and rm.event = 'megaphone'
                                    and rm.topic = public.poke_topic(c) and rm.payload ->> 'm' = a_mid::text
                                    and rm.payload ->> 'v' = '1') then
      raise exception '④ megaphone 신호가 %건이다(기대 % · c 주제 포함)', v_k, v_n;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑤ 같은 요청 재시도(멱등 키) → 자기가 연 창에 안 막히고 처음 결과 · 다시 안 깎는다
    --------------------------------------------------------------------------------------------
    v := pg_temp.mgb_send(a, '실사용자 확성기', ra);
    if v ->> 'status' is distinct from 'ok' or (v ->> 'duplicate')::boolean is distinct from true
       or (v ->> 'megaphone_id')::uuid is distinct from a_mid
       or (select p.ruby_balance from public.profiles p where p.id = a) is distinct from 100 - v_price
       or (select count(*) from public.megaphones m where m.sender = a) <> 1 then
      raise exception '⑤ 같은 요청 재시도가 % (기대 duplicate · 같은 id · 안 깎임)', v;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑥ a 의 새 요청 → 사람당 창(scope self · cooldown_seconds = 사람당 초)
    --------------------------------------------------------------------------------------------
    v := pg_temp.mgb_send(a, '또 보낸다', gen_random_uuid());
    if v ->> 'status' is distinct from 'cooldown' or v ->> 'scope' is distinct from 'self'
       or (v ->> 'cooldown_seconds')::int is distinct from v_cool
       or (v ->> 'retry_after_seconds')::int not between 1 and v_cool then
      raise exception '⑥ a 의 두 번째 확성기가 % (기대 cooldown · self)', v;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑦ b(사람당 창 없음) → 앱 전체 창(scope global) · 안 깎이고 원장도 없다
    --------------------------------------------------------------------------------------------
    v := pg_temp.mgb_send(b, '나도 보낸다', gen_random_uuid());
    if v ->> 'status' is distinct from 'cooldown' or v ->> 'scope' is distinct from 'global'
       or (v ->> 'cooldown_seconds')::int is distinct from v_gcool
       or (v ->> 'retry_after_seconds')::int not between 1 and v_gcool
       or (select p.ruby_balance from public.profiles p where p.id = b) is distinct from 100
       or exists (select 1 from public.megaphones m where m.sender = b) then
      raise exception '⑦ b 의 확성기가 % (기대 cooldown · global · 안 깎임)', v;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑧ h2(숨김) → 숨김 쪽 창(h1)에 막힌다 — 같은 쪽끼리는 앱 전체 창이 그대로 선다(같은 쪽 술어가 갈랐다는 기준선)
    --------------------------------------------------------------------------------------------
    v := pg_temp.mgb_send(h2, '숨김 쪽 둘째', gen_random_uuid());
    if v ->> 'status' is distinct from 'cooldown' or v ->> 'scope' is distinct from 'global' then
      raise exception '⑧ h2 의 확성기가 % (기대 cooldown · global)', v;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑨ 작성 화면: b 는 앱 전체 남은 초(scope global), a 는 사람당 남은 초가 더 길다(scope self). 남은 시간 = 둘 중 긴 쪽
    --------------------------------------------------------------------------------------------
    v := pg_temp.mgb_rpc(b, 'select public.megaphone_info()');
    if v ->> 'cooldown_scope' is distinct from 'global'
       or (v ->> 'global_cooldown_remaining_seconds')::int not between 1 and v_gcool
       or (v ->> 'cooldown_remaining_seconds')::int is distinct from (v ->> 'global_cooldown_remaining_seconds')::int then
      raise exception '⑨ b 의 작성 화면이 % (기대 global · 남은 시간 = 앱 전체)', v;
    end if;
    v := pg_temp.mgb_rpc(a, 'select public.megaphone_info()');
    if v ->> 'cooldown_scope' is distinct from 'self'
       or (v ->> 'cooldown_remaining_seconds')::int not between v_gcool + 1 and v_cool
       or (v ->> 'global_cooldown_remaining_seconds')::int not between 1 and v_gcool then
      raise exception '⑨ a 의 작성 화면이 % (기대 self · 남은 시간 = 사람당 > 앱 전체)', v;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑩ megaphone_inbox: c 는 자기 줄만(접두 뗀 본문 · 보낸 사람 이름). 가짜 📢 1:1 · 25시간 전 줄 · 남의 줄 · 차단은 빠진다
    --------------------------------------------------------------------------------------------
    insert into public.messages (from_user, to_user, body) values (b, c, v_pre || '가짜 확성기')
    returning id into fake;
    insert into public.messages (from_user, to_user, body, megaphone_id, created_at)
    values (a, c, v_pre || '옛 확성기', a_mid, now() - interval '25 hours') returning id into old_id;
    v := pg_temp.mgb_rpc(c, 'select coalesce(jsonb_agg(to_jsonb(i)), ''[]''::jsonb) from public.megaphone_inbox(p_hours => 1000) i');
    -- 벽 · 표식 · 시간: 목록의 모든 줄이 c 가 받은 확성기 줄이고, 가짜 · 옛 · b 의 줄은 없다(빌린 계정이면 이전 줄이 더 있을 수 있다).
    if exists (select 1 from jsonb_array_elements(v) e
                where not exists (select 1 from public.messages m
                                   where m.id = (e ->> 'message_id')::uuid and m.to_user = c and m.megaphone_id is not null))
       or exists (select 1 from jsonb_array_elements(v) e where (e ->> 'message_id')::uuid in (fake, old_id, b_msg))
       or (v_synth and jsonb_array_length(v) <> 1) then
      raise exception '⑩ c 의 확성기 목록에 c 의 확성기 줄이 아닌 것이 있다: %', v;
    end if;
    if v -> 0 ->> 'message_id' is distinct from c_msg::text
       or v -> 0 ->> 'megaphone_id' is distinct from a_mid::text or v -> 0 ->> 'sender_id' is distinct from a::text
       or v -> 0 ->> 'body' is distinct from '실사용자 확성기'
       or v -> 0 ->> 'sender_display_name' is distinct from (select coalesce(p.display_name, '사용자') from public.profiles p where p.id = a)
       or (v -> 0 ->> 'created_epoch') is null or not (v -> 0 ? 'sender_avatar_url') or not (v -> 0 ? 'created_at') then
      raise exception '⑩ c 의 확성기 목록이 % (기대 c 의 a 줄 하나 · 가짜 · 옛 · 남의 줄 없음)', v;
    end if;
    insert into public.user_blocks (blocker, blocked) values (c, a);
    v := pg_temp.mgb_rpc(c, 'select coalesce(jsonb_agg(to_jsonb(i)), ''[]''::jsonb) from public.megaphone_inbox() i');
    if exists (select 1 from jsonb_array_elements(v) e where (e ->> 'message_id')::uuid = c_msg) then
      raise exception '⑩ 차단한 사람의 확성기가 목록에 남았다: %', v;
    end if;
    delete from public.user_blocks where blocker = c and blocked = a;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑪ 안 읽음: v1 은 a 의 확성기 줄을 세고 v2 는 안 센다. b 의 가짜 📢 1:1 은 둘 다 센다(표식은 megaphone_id 뿐)
    --------------------------------------------------------------------------------------------
    v1 := pg_temp.mgb_rpc(c, 'select public.message_unread_summary()');
    v2 := pg_temp.mgb_rpc(c, 'select public.message_unread_summary_v2()');
    if v2 ->> 'status' is distinct from 'ok'
       or (v1 ->> 'total')::int - (v1_0 ->> 'total')::int is distinct from 2
       or (v2 ->> 'total')::int - (v2_0 ->> 'total')::int is distinct from 1
       or (v_synth and (not exists (select 1 from jsonb_array_elements(v1 -> 'peers') e where e ->> 'peer_user_id' = a::text)
                        or exists (select 1 from jsonb_array_elements(v2 -> 'peers') e where e ->> 'peer_user_id' = a::text))) then
      raise exception '⑪ 안 읽음이 v1 % → % · v2 % → % (기대 v1 +2 · v2 +1 — 확성기 줄만 v2 가 안 센다)', v1_0, v1, v2_0, v2;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑫ 푸시 발송함: 확성기 줄만 최상위 megaphone_id. type · category · 본문은 예전 그대로
    --------------------------------------------------------------------------------------------
    v := (select o.payload from public.push_outbox o where o.user_id = c and o.payload ->> 'message_id' = c_msg::text);
    if v is null or v ->> 'megaphone_id' is distinct from a_mid::text or v ->> 'type' is distinct from 'message'
       or v -> 'aps' ->> 'category' is distinct from 'MESSAGE'
       or v -> 'aps' -> 'alert' ->> 'body' is distinct from v_pre || '실사용자 확성기' then
      raise exception '⑫ 확성기 줄의 푸시가 % (기대 megaphone_id · type message · category MESSAGE)', v;
    end if;
    v := (select o.payload from public.push_outbox o where o.user_id = c and o.payload ->> 'message_id' = fake::text);
    if v is null or v ? 'megaphone_id' or v ->> 'type' is distinct from 'message' then
      raise exception '⑫ 평범한 1:1(📢 로 시작해도)의 푸시가 % (기대 megaphone_id 키 없음)', v;
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    -- ⑬ 로그인 없이는 새 RPC 둘을 못 부른다(42501) · 로그인하면 된다
    --------------------------------------------------------------------------------------------
    if pg_temp.mgb_err(null, 'select * from public.megaphone_inbox()') <> '42501'
       or pg_temp.mgb_err(null, 'select public.message_unread_summary_v2()') <> '42501'
       or pg_temp.mgb_err(c, 'select * from public.megaphone_inbox()') <> 'ok'
       or pg_temp.mgb_err(c, 'select public.message_unread_summary_v2()') <> 'ok' then
      raise exception '⑬ 새 RPC 실행권이 기대와 다르다';
    end if;
    probes := probes + 1;

    --------------------------------------------------------------------------------------------
    if v_blk is not null then
      execute v_blk;
    end if;
    if v_en is not null then
      execute v_en;
    end if;
    if probes <> v_expected then
      raise exception '§9 프로브 %건만 돌았다(기대 %건) — 검사가 조용히 빠졌다', probes, v_expected;
    end if;
    raise notice '§9 흐름 프로브 %건 통과(합성 계정 % · 롤백)', probes, v_synth;
    raise exception 'MEGAPHONE_BANNER_PROBE_ROLLBACK';
  exception
    when others then
      execute format('set local role %I', v_exec_role);
      if sqlerrm = 'MEGAPHONE_BANNER_PROBE_ROLLBACK' then
        raise notice '§9 롤백 완료 — 확성기 · 메시지 · 장부 · 발송함 · 신호에 흔적이 남지 않았다';
      else
        raise;
      end if;
  end;
end $probe$;

drop function if exists pg_temp.mgb_send(uuid, text, uuid);
drop function if exists pg_temp.mgb_rpc(uuid, text);
drop function if exists pg_temp.mgb_err(uuid, text);
drop function if exists pg_temp.mgb_as(uuid);

notify pgrst, 'reload schema';
