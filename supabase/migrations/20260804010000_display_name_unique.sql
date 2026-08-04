-- 별명 유일성: 정규화/키 함수 + 부분 유니크 인덱스 + 가입 트리거 충돌 내성.
-- 인덱스와 트리거 수정은 **반드시 한 배포 단위**다. 인덱스만 먼저 들어가면 동명이 발생 시 두 번째 가입의
-- profiles INSERT 가 실패하고 그 롤백이 auth.users INSERT 까지 되돌려 새 사람이 앱에 못 들어온다.
-- 멱등성: create or replace / create unique index if not exists / do 블록.
--
-- PostgREST 임베드 안전성(결정 (o)) — 이 파일은 **표도 FK 도 만들지 않는다**. 만드는 것은 함수 4개와
-- profiles.display_name **식**에 걸리는 부분 유니크 인덱스 1개뿐이다. PostgREST 의 관계 그래프는
-- 오직 외래키 제약으로만 만들어지므로, FK 집합이 그대로면 앱이 쓰는 임베드 두 개
--   work_statuses?select=…,profiles(…)  /  memberships?select=team_id,role,teams(…)
-- 의 경로 수는 산술적으로 변하지 않는다(각각 여전히 1개). 2026-08-02 전원 다운은 FK **두 개**짜리 새 표가
-- 다대다 연결표로 오해받아 경로가 2개가 된 사고였다 — 식 인덱스는 to-one/to-many 판정에 개입하지 않는다.

-- 1) 저장값 정규화. NFC 합성 → 보이지 않는 서식문자 제거 → 제어문자 제거 → 연속 공백 1칸 → 앞뒤 trim.
--    NFC 로 합성하지 않으면 자모 분리(NFD)로 들어온 "한글"이 눈에는 같은데 코드포인트가 3배라
--    길이 판정이 클라(Swift)와 갈린다.
--    U+200D(ZWJ)와 U+FE0F(VS16)는 **저장값에서는 일부러 남긴다** — 이모지 결합·표현에 쓰이는 정당한
--    문자라, 지우면 "👨‍👩‍👧" 가 세 조각으로 흩어지고 "❤️" 가 흑백 "❤" 로 바뀐다.
--    그래서 지우는 목록이 **둘로 갈린다**: 여기(저장값)는 '보여야 하는 것'을 남기고, 아래
--    display_name_key 는 '보이지 않는 것'을 남김없이 지운다. 사칭 차단은 전적으로 그 키가 맡는다.
--    이 대칭이 깨져 키 쪽 목록이 더 좁아지면 화면에서 원본과 구별되지 않는 이름이 통과한다 —
--    그러니 여기에 문자를 더하거나 뺄 때는 반드시 아래 목록도 같이 봐라.
--    보이지 않는 문자 목록을 정규식 문자 클래스가 아니라 translate() + U&'' 로 쓰는 이유:
--    이 줄이 리터럴이면 편집기·포매터가 보이지 않는 문자를 정리하는 순간 규칙이 소리 없이 바뀐다.
--    그렇다고 정규식 브래킷 안의 \u 이스케이프에 기대면, 만에 하나 그 이스케이프가 해석되지 않을 때
--    '[​]' 가 문자 집합 {\,u,2,0,b} 로 읽혀 **이름에서 숫자와 알파벳을 조용히 지운다**(eunho2 → enho).
--    U&'' 는 표준 SQL 문자열 이스케이프라 잘못되면 마이그레이션이 **문법 오류로 크게 실패**한다 —
--    조용한 데이터 훼손보다 시끄러운 실패가 낫다. translate 는 세 번째 인자가 짧으면 그 문자들을 삭제한다.
create or replace function public.normalize_display_name(p_name text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select btrim(
           regexp_replace(
             regexp_replace(
               translate(
                 normalize(coalesce(p_name, ''), NFC),
                 U&'\00ad\200b\200c\200e\200f\202a\202b\202c\202d\202e\2060\2061\2062\2063\2064\feff',
                 ''),
               '[[:cntrl:]]', '', 'g'),
             '[[:space:]]+', ' ', 'g'));
$$;

-- 2) 유일성 키. **인덱스와 RPC 가 이 함수 하나만 쓰므로 둘이 갈릴 수 없다.**
--    갈리면 최악이다 — 인덱스는 통과하는데 RPC 가 거부하거나(사용자는 영원히 못 바꾼다),
--    RPC 는 통과시키는데 인덱스가 23505 를 던진다(같은 이름 둘이 서로 다른 이유로 실패한다).
--    공백을 '줄이는' 게 아니라 '지우는' 이유: 줄이기만 하면 "eun ho" 로 "eunho" 를 그대로 흉내 낼 수 있다.
--    저장값에 남겨 둔 '보이지 않는' 문자들은 여기서 전부 지운다 — 화면에서 원본과 구별되지 않는 이름은
--    같은 이름으로 취급해야 사칭이 막힌다. 목록은 다음 일곱이고, ZWJ 를 뺀 여섯은 로컬 PostgreSQL 에서
--    실제로 뚫렸다(다른 사람이 `은호` 를 점유한 상태에서 `은호`+그 글자가 {"status":"ok"} 를 받아 냈다):
--      U+200D ZWJ            "eun<ZWJ>ho" 가 화면에서 "eunho" 와 똑같다(이것만 처음부터 막고 있었다)
--      U+1160 한글 중성 채움  폭 0. NFKC 가 U+3164(한글 채움)·U+FFA0(반각 채움)를 여기로 접으므로
--                            이 한 글자가 그 셋을 함께 막는다
--      U+3164 한글 채움      NFKC 이전 형태까지 방어한다(접기 단계가 바뀌어도 구멍이 안 생기게)
--      U+115F 한글 초성 채움  분해 규칙이 없어 NFKC 를 그대로 통과한다
--      U+2800 점자 빈칸      Symbol 이라 [[:space:]] 도 [[:cntrl:]] 도 못 잡는데 눈에는 공백이다
--      U+FE0F VS16          이모지 표현 선택자. 아무 글자 뒤에 붙여도 보이지 않는다
--      U+180E 몽골 모음 구분자 Cf 인데 NFKC 가 지우지 않는다
--    한 글자라도 빠지면 `은호`+그 글자가 새 계정으로 통과해 팀 목록에서 진짜 은호와 구별되지 않는다.
--    replace 를 겹치지 않고 translate 를 쓰는 이유: 목록이 한 줄에 다 보여야 무엇이 빠졌는지 눈에 띈다.
--    NFKC 는 전각/반각(ＡＢＣ ↔ ABC)까지 접어 준다.
--    이 함수는 7)의 인덱스 **식**에 쓰이므로 immutable 이어야 한다 — translate/normalize/lower/
--    regexp_replace 는 모두 immutable 이라 목록을 늘려도 그 성질은 그대로다.
--    **본문을 고쳤으면 8)의 reindex 를 반드시 같이 돌려라.** 안 그러면 인덱스는 옛 키로,
--    RPC 는 새 키로 판정하는 갈림 상태가 된다(이 설계가 가장 경계하는 상태다).
create or replace function public.display_name_key(p_name text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select lower(
           regexp_replace(
             translate(
               normalize(public.normalize_display_name(p_name), NFKC),
               U&'\115f\1160\180e\200d\2800\3164\fe0f', ''),
             '[[:space:]]', '', 'g'));
$$;

-- 이 두 함수의 EXECUTE 를 authenticated 에게 **반드시 준다.** 없으면 아바타 변경이 프로덕션에서 죽는다:
-- 7)의 유니크 인덱스는 profiles 에 새 인덱스 튜플을 만들 때마다 display_name_key 를 평가하는데,
-- 그 평가는 **호출자 권한으로** 일어나고 PostgreSQL 은 함수 EXECUTE 를 그 자리에서 검사한다
-- (execExpr.c 의 ExecInitFunc). 즉 authenticated 의 `PATCH /rest/v1/profiles {"avatar_url":…}` 가
-- HOT 갱신에 실패하는 순간(페이지가 꽉 찼을 때) "permission denied for function display_name_key" 로
-- 떨어진다 — 페이지 상태에 좌우되는 **간헐적** 실패라 재현도 어렵다.
-- 공개 비용은 POST /rest/v1/rpc/display_name_key 엔드포인트 하나뿐이고, 둘 다 입력만으로 결정되는
-- 순수 텍스트 함수라 새는 정보가 없다. service_role 도 같은 이유로 명시한다(admin 이 profiles 를 PATCH 한다).
revoke all on function public.normalize_display_name(text) from public;
revoke all on function public.display_name_key(text) from public;
grant execute on function public.normalize_display_name(text) to authenticated, service_role;
grant execute on function public.display_name_key(text) to authenticated, service_role;

-- 3) 가입이 유일성 때문에 죽지 않게 한다. **이 조각이 없으면 새 사람의 가입 자체가 실패한다** —
--    eunho@a.com 과 eunho@b.com 은 둘 다 split_part(email,'@',1)=eunho 다.
--    p_self 는 지금 쓰고 있는 그 사람의 id. 이 인자가 없으면 자기 이름을 자기가 점유한 것으로 보고
--    on conflict/재실행 경로에서 멀쩡한 사람을 '이름-2' 로 개명한다.
create or replace function public.unique_display_name(p_base text, p_self uuid default null)
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  base text := public.normalize_display_name(coalesce(nullif(btrim(p_base), ''), '팀원'));
  candidate text := base;
  n int := 2;
begin
  while exists (
    select 1 from public.profiles p
     where (p_self is null or p.id <> p_self)
       and public.display_name_key(p.display_name) = public.display_name_key(candidate)
  ) loop
    candidate := base || '-' || n::text;
    n := n + 1;
    if n > 50 then
      candidate := base || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 4);
      exit;
    end if;
  end loop;
  return candidate;
end;
$$;
-- 트리거 전용 함수라 앱이 부를 이유가 없다. 그런데 `revoke ... from public` **하나로는 못 닫는다**:
-- Supabase 는 public 스키마에 `alter default privileges ... grant all on functions to anon,
-- authenticated` 를 걸어 두므로 새 함수의 EXECUTE 가 PUBLIC 이 아니라 두 역할에게 **직접** 붙는다.
-- PUBLIC 에서만 회수하면 그 직접 grant 가 남고 PostgREST 가
--   POST /rest/v1/rpc/unique_display_name  {"p_base":"은호","p_self":null}
-- 을 열어 준다 — anon 키만으로 "이 이름이 비었는가"를 무한히 물어 전 사용자 별명을 훑을 수 있고,
-- 응답이 '은호-2' 면 은호가 이미 있다는 뜻이라 존재 확인까지 공짜로 된다. 그래서 명시적으로 지운다.
-- 지워도 **가입 트리거는 멀쩡히 돈다**: 이 함수를 부르는 handle_check_auth_user 가 security definer 라
-- 본문 실행 중 유효 사용자가 호출자가 아니라 그 함수의 **소유자**이고(PostgreSQL 은 중첩 호출의 EXECUTE 를
-- 그 시점의 GetUserId() 로 검사한다), 두 함수는 이 파일이 같은 역할로 만들어 소유자가 같으며
-- 소유자 자신의 권한은 revoke 로 지워지지 않는다.
-- 반대로 normalize_display_name/display_name_key 는 여기서 EXECUTE 를 지우면 **인덱스가 죽는다**
-- (바로 위 문단대로 인덱스 식은 호출자 권한으로 평가된다). 트리거 전용 함수만 골라 지우는 이유다.
revoke all on function public.unique_display_name(text, uuid) from public;
revoke execute on function public.unique_display_name(text, uuid) from anon, authenticated;

-- 4) 가입 트리거 재정의.
--    **원본은 20260711160000_invite_code_join.sql:189-207 이다. 20260701000000:72-103 은 죽은 원본이다.**
--    그 옛 본문에는 하드코딩 팀('10000000-0000-0000-0000-000000000001', 'sudo 박수') insert 와 자동
--    membership/work_status insert 가 들어 있고, 20260712090000 이 그 팀을 지운 뒤 20260711160000 이
--    트리거에서 그 로직을 걷어냈다. 옛 본문을 복사해 create or replace 하면 신규 가입자 전원이 참여한 적
--    없는 팀에 자동 소속돼 서로의 근무 현황·프로필을 읽게 된다. 그래서 여기서도 profiles upsert 하나만 둔다.
--    트리거 바인딩(on_check_auth_user_created)은 함수 본문만 갈아 끼우므로 재생성하지 않는다.
create or replace function public.handle_check_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  base text := coalesce(new.raw_user_meta_data ->> 'display_name',
                        split_part(coalesce(new.email, '팀원'), '@', 1));
  candidate text := public.unique_display_name(base, new.id);
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, coalesce(new.email, ''), candidate)
  on conflict (id) do update set
    email = excluded.email,
    display_name = excluded.display_name;
  return new;
exception when unique_violation then
  -- 같은 이름으로 두 사람이 **같은 순간에** 가입하면 unique_display_name 의 사전 조회는 둘 다 통과한다
  -- (아직 어느 쪽도 커밋되지 않았으니 서로가 안 보인다). 여기서 잡지 않으면 진 쪽의 profiles INSERT 가
  -- 23505 로 죽고, 그 롤백이 auth.users INSERT 까지 되돌려 **가입 자체가 실패한다**.
  -- 유일성보다 "새 사람이 앱에 들어올 수 있다"가 우선이므로 무작위 접미어로 반드시 성공시킨다.
  insert into public.profiles (id, email, display_name)
  values (new.id, coalesce(new.email, ''),
          candidate || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 4))
  on conflict (id) do update set
    email = excluded.email,
    display_name = excluded.display_name;
  return new;
end;
$$;

-- 5) 자가 치유 백필. 중복이 남아 있으면 사람 손을 기다리지 말고 결정적으로 접미어를 붙인다(created_at 늦은 쪽).
--    이게 없으면 신규 환경 db reset 이 20260701000000:114-122 백필이 만든 동명 때문에 통째로 멈춘다.
with d as (
  select id,
         row_number() over (
           partition by public.display_name_key(display_name)
           order by created_at, id) rn
    from public.profiles
   where public.display_name_key(display_name) <> ''
)
update public.profiles p
   set display_name = p.display_name || '-' || d.rn::text
  from d
 where d.id = p.id and d.rn > 1;

-- 6) 최종 안전망. 여기서 걸리면 위 백필이 만든 접미어끼리 또 충돌했다는 뜻이라 사람이 봐야 한다.
--    raw 23505 대신 어떤 키가 겹치는지를 보여 주고 멈춘다.
do $$
declare dup text;
begin
  select string_agg(k, ', ') into dup from (
    select public.display_name_key(display_name) k
      from public.profiles
     where public.display_name_key(display_name) <> ''
     group by 1 having count(*) > 1) d;
  if dup is not null then
    raise exception '별명 중복이 남아 있어 유일 인덱스를 걸 수 없습니다: %', dup;
  end if;
end $$;

-- 7) 최종 방어선. RPC 의 사전 조회만으로는 같은 이름을 든 동시 요청 둘이 **둘 다** 통과한다 —
--    경쟁 조건을 실제로 끝내는 것은 이 인덱스뿐이고, RPC 는 그 23505 를 'taken' 으로 번역할 뿐이다.
--    부분 인덱스인 이유: 키가 빈 문자열이 되는 병리적 옛 행(공백만 있는 이름)이 서로 충돌해
--    마이그레이션을 죽이지 않게. 새 빈 이름은 RPC 가 애초에 거절하므로 생기지 않는다.
--    주의: display_name_key/normalize_display_name 을 나중에 create or replace 로 고치면 이 인덱스는
--    옛 정의로 만들어진 값을 그대로 들고 있다(PostgreSQL 은 재구축하지 않는다). 그래서 8)이 있다.
--    PG 메이저 업그레이드 뒤에도 같다(lower/normalize 가 유니코드 테이블에 기댄다).
create unique index if not exists profiles_display_name_key_unique
  on public.profiles (public.display_name_key(display_name))
  where public.display_name_key(display_name) <> '';

-- 8) 키 함수를 고쳤을 때의 필수 후처리. `create or replace function` 은 인덱스를 재구축하지 않는다.
--    이 파일의 옛 판이 이미 적용된 DB(로컬·스테이징)라면 2)의 목록을 늘려도 인덱스 안의 값은
--    **옛 정의로 계산된 키** 그대로다. 그러면 인덱스와 RPC 가 서로 다른 규칙으로 판정한다:
--    `은호`+U+3164 를 RPC 는 taken 이라 하는데 인덱스는 통과시키고(사칭이 그대로 뚫린다),
--    반대 방향에서는 멀쩡한 이름이 raw 23505 로 죽는다. 2)의 주석이 경계하는 바로 그 갈림이다.
--    실측(로컬 PostgreSQL 15): 낡은 인덱스를 둔 채 같은 count 질의를 돌리면 순차 스캔은 2, 인덱스
--    스캔은 1 을 냈다 — 조회 계획에 따라 답이 갈리므로 "중복이 없다"는 확인조차 믿을 수 없어진다.
--    **순서가 중요하다** — 5)·6)이 새 키로 중복을 먼저 정리·검증한 뒤라야 이 재구축이 23505 없이 끝난다.
--    reindex 를 앞에 두면 백필이 손볼 기회도 없이 사람이 읽을 수 없는 오류로 배포가 멈춘다.
--    concurrently 를 안 쓰는 이유: 마이그레이션은 한 트랜잭션 안이고 concurrently 는 거기서 못 돈다.
--    7)이 인덱스 존재를 보장하므로 이 줄은 몇 번을 다시 돌려도 안전하다(26행짜리 재구축이라 값도 싸다).
reindex index profiles_display_name_key_unique;
