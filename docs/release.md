# 배포(release) 운영 가이드 — brew 배포

aing-check 를 팀원에게 배포하는 경로는 두 가지입니다.

1. **brew 배포 (기본)** — 공증된 앱을 GitHub Releases 에 올리고, tap 저장소의 Homebrew Cask 로 설치/업데이트하는 방식. **이 문서가 다루는 내용이며, v0.1.0 부터 라이브입니다.** 최초 `brew install` 한 번 이후로 팀원은 `brew upgrade` 만으로 최신 버전을 받습니다.
2. **zip 직접 전달 (비상용)** — `package-notarized.sh` 산출물 `dist/aing-check.zip` 을 직접 보내는 방법(공증본이라 그대로 열림). brew 를 못 쓰는 환경에서만 쓰면 됩니다. (`package-local.sh` 의 ad-hoc 서명본은 개발 확인용 — 배포에 쓰지 말 것.)

> 이 저장소의 owner 는 `yehsung` 으로 확정되어 있습니다. `release-brew.sh` 는 릴리즈·태그·tap 대상을 `GH_OWNER` 환경변수(또는 `.env.local` 의 `CHECK_GH_OWNER`)로 정하므로, 아래 실행 전에 `GH_OWNER=yehsung` 을 설정하면 됩니다.
>
> Cask 템플릿 `packaging/homebrew/aing-check.rb` 의 `url`/`homepage` 는 `__GH_OWNER__` 자리표시자를 쓰고, `release-brew.sh` 가 `__VERSION__`·`__SHA256__` 과 함께 치환합니다. 공증·brew 배포는 활성 상태입니다 — Developer ID 서명 + 공증 프로파일은 키체인 `check-notary`, 산출 앱은 유니버설(arm64+x86_64)입니다.

## 구성 요소

| 이름 | 역할 |
| --- | --- |
| `yehsung/check` | 앱 소스 저장소 + GitHub Releases (공증된 `aing-check.zip` 이 릴리즈 자산으로 올라감) |
| `yehsung/homebrew-check` | Homebrew **tap** 저장소. `Casks/aing-check.rb` 하나가 들어 있고, 릴리즈마다 version/sha256 이 갱신됨 |
| `packaging/homebrew/aing-check.rb` | Cask **템플릿**(`__VERSION__`, `__SHA256__` 자리표시자). 릴리즈 스크립트가 이 템플릿을 치환해 tap 저장소로 복사 |
| `scripts/release-brew.sh` | 위 전 과정을 한 번에 처리하는 릴리즈 자동화 스크립트 |

`brew tap yehsung/check` 은 GitHub 저장소 `yehsung/homebrew-check` 로 해석됩니다(tap 이름 규칙: `homebrew-` 접두사 생략). Cask 파일명이 `aing-check.rb` 이므로 설치 명령은 `brew install --cask aing-check`(또는 tap 까지 한 번에 `brew install yehsung/check/aing-check`)입니다.

## 최초 1회 세팅

아래는 배포 담당자가 처음 한 번만 하면 됩니다.

1. **gh CLI 로그인**
   ```sh
   brew install gh        # 이미 있으면 생략
   gh auth login          # GitHub 계정으로 로그인 (repo 권한 필요)
   ```
2. **GitHub 저장소 2개 준비**
   ```sh
   # 앱 소스 저장소 (이미 push 되어 있다면 생략)
   gh repo create yehsung/check --public --source=. --remote=origin --push

   # tap 저장소 (../homebrew-check 로 클론)
   gh repo create yehsung/homebrew-check --public --clone
   mv homebrew-check ../homebrew-check   # 저장소 루트 옆(../)에 두는 것이 기본 경로
   ```
   tap 저장소를 `../homebrew-check` 가 아닌 다른 경로에 두려면 `GH_TAP_DIR` 환경변수로 지정하세요.
3. **GH_OWNER 설정 (`yehsung`)** — `release-brew.sh` 가 읽는 값입니다. 매번 export 하기 번거로우면 `.env.local` 에 넣어 둡니다(이 파일은 git 에서 제외됨).
   ```sh
   # 둘 중 하나
   export GH_OWNER=yehsung
   # 또는 .env.local 에 아래 줄 추가
   # CHECK_GH_OWNER=yehsung
   ```

## 릴리즈 1회 순서 (파이프라인)

버전을 올릴 때마다 아래 순서를 따릅니다. 예시 버전은 `0.2.0`.

```sh
# 0) CHANGELOG.md 에 이번 버전 항목을 먼저 쓴다 (없으면 릴리즈가 실패한다)
#    "## 0.2.0" 섹션에 사용자 문장으로 한 줄씩. 이 섹션이 그대로 GitHub 릴리즈 노트가 되고
#    앱의 "새 버전이 나왔어요" 배너에 앞의 4줄까지 표시된다.

# 1) 코드 수정 후 테스트 (반드시 통과 확인)
export CHECK_SUPABASE_ANON_KEY="<Supabase anon key>"   # 또는 .env.local
swift test

# 1-1) 이번 릴리즈에 새 마이그레이션이 있으면 **앱보다 먼저** 적용한다 (아래 "스키마 적용" 참고)
git status --short supabase/migrations   # 이번 diff 에 새 SQL 파일이 있는지
supabase db push                         # 있으면 배포 전에 적용

# 1-2) db push 를 했다면 **반드시** 기존 조회가 아직 살아 있는지 확인한다. 건너뛰지 말 것.
#      표를 더하기만 해도 기존 조회가 깨진다 — PostgREST 는 두 표를 각각 가리키는 FK 를 가진 새 표를
#      다대다 연결 표로 자동 해석해, 이미 있던 임베드에 경로를 하나 더 만들고 PGRST201 로 요청 전체를
#      400 으로 거절한다. 이건 **서버만의 변경이라 앱 버전과 무관**해 구버전 사용자까지 동시에 죽는다.
#      (2026-08-02 v0.2.15 실사고: work_status_devices 가 work_statuses→profiles 임베드를 깨뜨려
#       팀 목록·세션 복구·원격 종료 반영이 전원 다운. 단위 테스트는 원리적으로 못 잡는다 —
#       URLProtocolStub 은 보낸 select 를 해석하지 않고, 스토어 경로는 실패를 syncMessage 로 삼킨다.)
CHECK_E2E=1 CHECK_E2E_SR_KEY_FILE=<apikeys.json> swift test --filter LiveE2E   # s09i 가 임베드를 실제로 검증
#   e2e 키가 없으면 최소한 아래 두 줄이라도 실서버에 쏴 200 인지 확인한다(읽기 전용):
#   curl -s -o /dev/null -w '%{http_code}\n' "$URL/rest/v1/work_statuses?select=user_id,profiles(display_name)&limit=1" \
#        -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN"
#   curl -s -o /dev/null -w '%{http_code}\n' "$URL/rest/v1/memberships?select=team_id,teams(name)&limit=1" \
#        -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN"
#   (e) 울트라 RPC 가 실제로 살아 있고 남은 횟수를 싣는지(근무중이 아니면 not_working 이 정상).
#       404/PGRST202 면 push 가 안 된 것이다.
#   curl -s -X POST "$URL/rest/v1/rpc/ultra_poke_user" -H "apikey: $ANON" \
#        -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"p_to":"<상대uid>"}'
#
# 1-2b) 이번 마이그레이션이 함수를 **drop + create** 했다면, 인자 default 가 살아 있는지 되묻는다.
#       drop 은 인자의 default 를 같이 버리고, PostgREST 는 **보낸 키의 집합으로 함수를 고른다** —
#       그 키를 생략하는 앱 요청이 PGRST202(404) 로 죽는다. 앱은 안 바뀌었는데 화면만 빈다.
#       (2026-09-12 v0.3.13 실사고. 자세한 내용과 대조법은 아래 "스키마 적용" → "함수를 drop+create 할 때".)
#   select p.proname, pg_get_function_arguments(p.oid)   -- identity_arguments 는 default 를 안 보여 준다
#     from pg_proc p where p.pronamespace='public'::regnamespace
#      and p.proname in ('<이번에 바꾼 함수들>') order by 1;
#
# 1-3) **RPC 실행권 유출 점검** (grant 변경 마이그레이션을 push 했거나, 새 RPC 를 추가했으면 반드시).
#      Supabase 는 새 함수의 EXECUTE 를 anon/PUBLIC 에 자동 부여한다 — 앱 RPC 가 auth.uid() 가드 없이
#      로그인 없이 데이터를 반환하면 공개 cask 의 anon 키만으로 전량 유출된다(2026-08-09 token_usage_board 실사고).
#      (A) anon 이 실행 가능한 함수 목록을 뽑아, lookup_team_by_code·is_team_member 등 RLS/미리보기 헬퍼
#          외에 **데이터 RPC 가 끼어 있으면 유출이다**(관리자 SQL — Supabase SQL editor):
#      select p.proname from pg_proc p
#        join aclexplode(coalesce(p.proacl, acldefault('f',p.proowner))) x on true
#        join pg_roles r on r.oid=x.grantee
#        where p.pronamespace='public'::regnamespace and r.rolname='anon' and x.privilege_type='EXECUTE'
#        order by 1;
#      (B) 익명 호출로 직접 확인 — 401/403 이어야 정상(200 에 행이 나오면 유출):
#   curl -s -o /dev/null -w '%{http_code}\n' -X POST "$URL/rest/v1/rpc/token_usage_board" \
#        -H "apikey: $ANON" -H 'Content-Type: application/json' -d '{"p_month":"2026-08"}'
#      (s08b_anonRpcExposureIsLocked e2e 가 (B) 를 자동으로 검증한다.)

# 2) Developer ID 서명 + 공증 + 스테이플된 배포 zip 생성 → dist/aing-check.zip
./scripts/package-notarized.sh

# 3) 태그·릴리즈·Cask 반영을 한 번에 (먼저 dry-run 으로 확인 권장)
./scripts/release-brew.sh 0.2.0 --dry-run
./scripts/release-brew.sh 0.2.0

# 4) 팀원은 최신 버전으로 업그레이드
brew update && brew upgrade --cask aing-check
```

`release-brew.sh` 가 순서대로 하는 일:

1. **사전점검** — gh 로그인, **`CHANGELOG.md` 의 `## <버전>` 패치노트**, `GH_OWNER`(또는 `.env.local` 의 `CHECK_GH_OWNER`), `dist/aing-check.zip` 존재 및 공증 스테이플(`stapler validate`) 확인. 하나라도 어긋나면 안내 메시지와 함께 실패합니다(zip 이 없으면 `package-notarized.sh` 를 먼저 돌리라고 안내). 패치노트 점검은 태그·푸시 같은 부수효과보다 **앞에** 있으므로, 노트를 안 썼으면 아무것도 건드리지 않고 즉시 멈춥니다.
2. **git 태그 + 릴리즈** — `v0.2.0` 태그 생성/푸시 후 `gh release create` 로 릴리즈 생성 + `aing-check.zip` 업로드. 릴리즈 노트 본문은 CHANGELOG 의 해당 섹션 + 설치 안내 한 줄입니다. 이미 있는 태그/릴리즈는 건너뛰거나 자산만 덮어써서 **다시 실행해도 안전(멱등)** 합니다.
3. **Cask 갱신** — zip 의 sha256 을 계산해 `packaging/homebrew/aing-check.rb` 의 version/sha256 을 치환한 뒤 tap 저장소의 `Casks/aing-check.rb` 로 복사·커밋·푸시. 변경이 없으면 커밋을 건너뜁니다.
4. **안내 출력** — 팀원 최초 설치 명령과 업그레이드 명령을 출력합니다.

### dry-run

`--dry-run` 을 붙이면 태그/릴리즈/푸시를 실제로 실행하지 않고 각 단계에서 **무엇을 할지**만 출력합니다(생성될 Cask 내용 미리보기 포함). 사전점검이 어긋나도 종료하지 않고 경고만 남기므로, 흐름 전체를 미리 확인할 때 유용합니다.

```sh
GH_OWNER=yehsung ./scripts/release-brew.sh 0.2.0 --dry-run
```

## 팀원 설치 / 업그레이드

배포 담당자가 릴리즈를 마치면 팀원에게 아래를 안내합니다.

```sh
# 최초 1회
brew tap yehsung/check
brew install --cask aing-check
# (tap + 설치를 한 줄로: brew install yehsung/check/aing-check)

# 이후 업데이트
brew update && brew upgrade --cask aing-check
```

앱은 공증(notarized)되어 있으므로 팀원은 격리 해제(`xattr`)나 `설치하기.command` 없이 바로 실행됩니다. 실행하면 메뉴바에 아이콘이 뜨고, 이후 가입/로그인 절차는 [`docs/team-install.md`](team-install.md) 의 2번 이후와 동일합니다.

Cask 는 업그레이드/삭제 시 실행 중인 앱을 먼저 종료하고(`uninstall quit` — 앱 종료 훅이 근무중이면 퇴근 동기화 후 종료), 설치/업그레이드 완료 후에는 `postflight` 가 앱을 백그라운드로 재실행합니다 — 업그레이드가 앱을 종료만 하고 방치해 근무가 미기록되는 일을 막기 위한 짝입니다.

## 공개 릴리즈의 의미 (사용자 인지 사항)

brew 배포는 앱 소스 저장소와 tap 저장소를 **public** 으로 두는 것을 전제로 합니다(private 저장소는 팀원마다 GitHub 인증 설정이 필요해 배포가 번거로워짐). 즉 **앱 바이너리(공증된 zip)와 Cask 가 인터넷에 공개**됩니다.

이것이 허용되는 이유:

- aing-check 의 실제 관문은 **팀 초대코드**입니다. 앱을 누구나 내려받아 실행해도, 유효한 팀 코드가 없으면 어떤 팀에도 합류할 수 없고 데이터를 볼 수 없습니다(팀 목록은 공개하지 않으며 `코드가 곧 열쇠`).
- Supabase 접근은 RLS 로 보호되며, 번들에 들어가는 값은 **anon/public key** 뿐입니다(공개되어도 무방한 키). service_role 키나 비밀은 배포물에 포함되지 않습니다.

따라서 앱 공개는 **인지된 상태에서 허용한 리스크**입니다. 다만 다음은 유지해야 합니다.

- `.env.local`, service key, Supabase 대시보드 크리덴셜은 절대 커밋하지 않습니다(`.gitignore` 로 `.env.local`, `dist/` 등 제외).
- 초대코드는 팀 owner 만 공유하며, 유출 시 팀 카드에서 재발급(새 팀 생성) 등으로 대응합니다.
- 공개를 원치 않으면 두 저장소를 private 으로 만들 수 있으나, 팀원마다 `brew` 의 GitHub 인증(`HOMEBREW_GITHUB_API_TOKEN` 또는 `gh auth`)이 필요해집니다.

## 서버(Supabase) 운영

앱은 Supabase(Auth + REST)와 동기화합니다. URL: `https://xfnhfjvubetkdnfkfljg.supabase.co`.
anon key 원문은 git 에 커밋하지 않습니다 — 로컬에선 `.env.local` 의 `CHECK_SUPABASE_ANON_KEY` 로 주입합니다.
앱에 `Supabase 키 오류`가 표시되면 주입한 anon key 가 원격에서 거부된 것입니다. Dashboard 의
Project Settings > API 에서 현재 anon/public key 를 다시 가져와 주입하세요.

### 스키마 적용

기존 스키마는 이미 적용되어 정상 동작 중입니다. 다만 **새 마이그레이션 SQL 이 추가된 릴리즈는 앱을 올리기 전에 반드시 적용**해야 합니다(위 파이프라인 1-1 단계). 새 표를 쓰는 앱을 먼저 배포하면 그 표를 쓰는 기능(예: 토큰 사용량 업로드)이 조용히 실패한 채 돌아갑니다 — 앱은 `DB 스키마 필요`를 표시하지만 다음 동기화에서 문구가 갱신되므로 놓치기 쉽습니다. 적용이 늦어도 로컬 원장이 그 달치를 보관하므로 push 직후 값은 스스로 복구됩니다.

```sh
supabase link --project-ref xfnhfjvubetkdnfkfljg
supabase db push
```

> `supabase db push` 는 아직 적용되지 않은 마이그레이션만 올리므로 여러 번 실행해도 안전합니다. 계정이 여러 개면
> `supabase projects list` 로 위 project-ref 가 보이는 계정인지 먼저 확인하세요(다른 계정이면 403 이 납니다).

Dashboard 의 SQL Editor 에서 직접 실행하려면 `supabase/migrations/` 아래 SQL 파일들을
파일명(타임스탬프) 순서대로 실행합니다.

#### 함수를 `drop` + `create` 로 바꿀 때 — **인자 default 까지** 원본과 대조한다

> **반환 컬럼만 맞추고 넘어가지 마세요.** `drop function` + `create function` 은 인자의
> **기본값(`default`)** 을 같이 버립니다. default 만 빠진 함수는 SQL 로 부르면 멀쩡히 돌기 때문에
> 눈으로도 테스트로도 멀쩡해 보이지만, PostgREST 는 **본문에 실려 온 키의 집합으로 함수를 고릅니다** —
> 그 키를 생략하고 부르던 앱 요청이 `PGRST202`(404) 로 죽습니다. 서버만의 변경이라 **앱 버전과 무관**해
> 구버전 사용자까지 같이 죽고, 앱은 한 줄도 안 바뀌었는데 화면만 빕니다.
>
> **2026-09-12 v0.3.13 실사고** — `20260912143000_profile_center.sql` 이 `center` 컬럼을 얹으려고
> `minigame_board` 를 drop+create 하면서 원본의 `p_day date default null`
> (`supabase/migrations/20260908090000_minigame_scores.sql:152`) 에서 **default 만 떨어뜨렸습니다.**
> 앱은 '오늘' 순위를 볼 때 `p_day` 키를 아예 **보내지 않습니다**(`encodeIfPresent` —
> `Sources/check/SupabaseWorkModels.swift` 의 `MiniGameBoardRequest`). 서버에 `minigame_board(p_game)` 에
> 맞는 함수가 없어지자 미니게임 창이 최고기록·오늘 순위까지 **통째로 빈 화면**이 됐습니다(운영자 신고).
> 그 마이그레이션에 붙어 있던 프로브 26개는 **전부 초록이었습니다 — 프로브가 `p_day` 를 넣어서 불렀기
> 때문입니다.** 핫픽스: `supabase/migrations/20260912151142_minigame_board_default_restore.sql`.

> **대조하는 법**: `pg_get_function_identity_arguments` 를 쓰지 마세요 — 이름 그대로 오버로드를 가리는
> **신원**용이라 default 를 **안 보여 줍니다**. `pg_get_function_arguments` 를 써야 default 가 문자열에
> 같이 나옵니다. 바꾸기 **전에** 찍어 두고 바꾼 **뒤에** 같은지 되물으세요(사람 눈보다 정확합니다).
>
> ```sql
> -- 교체 전 / 교체 후 둘 다 돌려 출력을 그대로 비교한다 (관리자 SQL)
> select p.proname, pg_get_function_arguments(p.oid) as args
>   from pg_proc p
>  where p.pronamespace = 'public'::regnamespace
>    and p.proname in ('minigame_board','minigame_yesterday_winner')   -- 이번에 바꾼 함수들
>  order by 1;
> -- 기대: minigame_board | p_game text, p_day date DEFAULT NULL::date
> ```
>
> 마이그레이션 안에서 **기계로** 막는 것이 제일 낫습니다. 위 핫픽스 파일 끝의 `do $$ ... raise exception`
> 처럼, 문자열이 기대값과 다르면 배포가 멈추도록 사후 단언을 답니다.

> **프로브도 같이 고치세요.** 인자를 전부 채워 부르는 프로브는 default 가 사라진 것을 **원리적으로 못
> 봅니다.** default 가 있는 인자는 **빼고** 한 번 더 부르는 줄을 반드시 넣으세요 — 이번 사고에서 26개를
> 전부 통과시킨 것이 바로 이 구멍이었습니다.

> **함수 주석(`comment on function`)도 같이 날아갑니다.** `create or replace` 는 주석을 남기지만
> `drop` + `create` 는 지웁니다. 함수를 갈아 끼울 때는 원본 마이그레이션의 `comment on function` 도
> 같이 옮겨 붙이세요. 지금 무엇이 비었는지는 이렇게 봅니다.
>
> ```sql
> select p.proname, obj_description(p.oid,'pg_proc') is not null as has_comment
>   from pg_proc p where p.pronamespace = 'public'::regnamespace order by 1;
> ```

#### 별명·울트라 스키마에서 **지우면 안 되는 것** (v0.2.16)

> **`grant execute on function public.display_name_key(text) to authenticated;` 를 지우지 마세요.**
> 유니크 인덱스가 `display_name_key(display_name)` 식에 걸려 있어, profiles 에 인덱스 튜플이 새로 생길 때마다
> 이 함수가 **호출자 권한으로** 평가됩니다(PostgreSQL 이 그 자리에서 EXECUTE 를 검사합니다). 회수하면 아바타
> PATCH 가 HOT 갱신에 실패하는 순간에만 403 이 나는 **간헐적** 장애가 됩니다. `normalize_display_name` 도 같습니다.

> **`display_name_key`/`normalize_display_name` 을 고칠 때는 같은 마이그레이션에서
> `reindex index profiles_display_name_key_unique;` 를 함께 돌리세요.** PostgreSQL 은 함수를
> `create or replace` 해도 인덱스를 재구축하지 않아, 인덱스가 옛 정의로 만든 키를 그대로 들고 있게 됩니다
> (중복이 뚫리거나 멀쩡한 이름이 taken 이 됩니다). PG 메이저 업그레이드 후에도 같습니다.

> **`revoke execute on function public.unique_display_name(text, uuid) from anon, authenticated;` 를
> 되돌리지 마세요.** 이 함수는 가입 트리거 전용이고, 권한이 없어도 트리거는 멀쩡히 돕니다 —
> 이 함수를 부르는 `handle_check_auth_user` 가 `security definer` 라 본문 실행 중 유효 사용자가 호출자가
> 아니라 **소유자**이기 때문입니다. "권한이 없어서 가입이 죽나?" 싶어 다시 grant 하면
> `POST /rest/v1/rpc/unique_display_name` 이 열려 **anon 키만으로 전 사용자 별명을 열거**할 수 있습니다
> (응답이 `은호-2` 면 은호가 이미 있다는 뜻이라 존재 확인까지 공짜입니다).
> `revoke all ... from public` 하나로는 못 닫습니다 — Supabase 의 기본권한이 EXECUTE 를 PUBLIC 이 아니라
> 두 역할에 **직접** 붙이기 때문에 역할을 지목해 회수해야 합니다.

> **울트라 하루 한도를 바꾸려면 두 곳입니다** — 서버 `supabase/migrations/20260804030000_ultra_poke.sql` 의
> `ultra_poke_daily_limit constant int := 2` 와 클라 `Sources/check/WorkTimerStorePoke.swift:22` 의
> `WorkTimerStore.ultraPokeDailyLimit`. 둘이 갈리면 "오늘 N번 남음" 안내가 서버 판정과 어긋납니다
> (회귀 방어는 `s09k_ultraPokeRoundTrip` 의 `#expect(limit == 2)` + `ultraRemaining == limit - 1`).

> **롤백 시 주의**: `drop function ultra_poke_user` 한 줄이면 울트라만 죽습니다. 다만 위 두 `grant execute`
> 와 `grant update on public.profiles to service_role` 은 **남겨 두세요** — 지우면 아바타 PATCH 와
> 운영자 수동 조치가 함께 죽습니다.

#### v0.3.13 소속 센터 표시 — **롤백 순서** (★ RPC 가 먼저, 컬럼은 나중)

되돌릴 일이 생기면 **순서가 전부입니다.** 아래 순서로만 하세요.

1. center 를 싣는 **다섯 RPC** 를 center 항이 없는 **직전 정의**로 되돌린다.
2. 가입 트리거 `handle_check_auth_user()` 를 직전 정의로 되돌린다.
3. **그 다음에야** `profiles.center` 컬럼을 뗀다. (급하지 않습니다 — 아래 참고)

> **반대로 하면 화면 넷이 동시에 죽습니다.** 다섯 함수는 본문이 전부 **문자열**이라
> (`pg_proc.prosqlbody` 가 null — 실서버에서 확인함) PostgreSQL 이 `profiles.center` 에 대한 의존성을
> 기록해 두지 않습니다. 그래서 `alter table public.profiles drop column center` 는 **막히지 않고 그냥
> 성공하고**, 그 순간부터 콕 찌르기 목록·AI 토큰 순위판·팀 리그·미니게임 순위가 호출될 때마다
> `42703`(column p.center does not exist) 로 한꺼번에 죽습니다. 서버만의 변경이라 **앱 버전과 무관**해
> 구버전 사용자까지 같이 죽습니다. 트리거(2)를 남겨 둔 채 컬럼을 떼면 더 나쁩니다 — 트리거가 실패하면
> 롤백이 `auth.users` INSERT 까지 되돌려 **가입 자체가 실패합니다.**

> **1·2 만 해도 사용자 화면은 정상입니다.** 네 모델의 `center` 가 전부 Optional 이라
> (`Sources/check/SupabaseWorkModels.swift` 의 `TeamLeaderboardEntry`·`PokeDirectoryEntry` 등) center 항이
> 없는 구버전 RPC 가 내려와도 디코딩이 죽지 않고 **배지만 사라집니다.** 그러니 3 은 서두르지 마세요 —
> 오히려 **컬럼은 남기고 RPC 만 되돌린 상태가 가장 안전한 정지 지점**입니다. 40명의 값이 그대로 남아
> 다시 켤 때 컷오프 백필을 또 하지 않아도 됩니다.

직전 정의는 아래 파일에 있습니다. **손으로 다시 쓰지 말고 그대로 베껴** 새 마이그레이션 한 파일로 묶으세요.

| 함수 | 직전 정의가 있는 파일 |
| --- | --- |
| `app_user_directory()` | `20260903131000_revert_team_poke.sql` |
| `token_usage_board(text)` | `20260912001500_shared_codex_bucket_reconcile.sql` |
| `minigame_board(text, date)` | `20260908090000_minigame_scores.sql` — ★ `p_day date default null`, **default 를 빠뜨리지 말 것** |
| `minigame_yesterday_winner(text)` | `20260908180000_minigame_prize_quorum.sql` (090000 이 아닙니다 — 정족수판이 나중입니다) |
| `team_weekly_leaderboard()` | `20260826010000_work_session_integrity.sql` |
| `handle_check_auth_user()` | `20260804010000_display_name_unique.sql` |

> `token_usage_board` 는 **절대 손으로 다시 쓰지 마세요.** 본문에 계정 우선·fork_safe 게이트·prefer_device·
> 옛 표 병합이 들어 있어, 다시 쓰면 지난 두 주의 사고 수정이 통째로 사라집니다.
>
> 되돌릴 때도 위 **"함수를 drop+create 할 때"** 규약이 그대로 적용됩니다 — `minigame_board` 의
> `p_day` default 와, 두 미니게임 함수의 `comment on function` 을 같이 옮겨 붙이세요.

1·2 가 끝났는지 확인(**0 이어야** 정상):

```sql
select count(*) from pg_proc
 where pronamespace = 'public'::regnamespace
   and proname in ('app_user_directory','token_usage_board','minigame_board',
                   'minigame_yesterday_winner','team_weekly_leaderboard','handle_check_auth_user')
   and prosrc like '%center%';
```

3 단계는 위 count 가 0 인 것을 **눈으로 확인한 뒤에만** 합니다.

```sql
-- ★ 되돌릴 수 없습니다. 40명의 센터 값이 사라집니다.
alter table public.profiles drop constraint if exists profiles_center_valid;
alter table public.profiles drop column if exists center;
```

`revoke select (center) ...` 는 따로 하지 않아도 됩니다 — 컬럼이 사라지면 컬럼 단위 권한도 같이 사라집니다.
(`update (center)` 는 사장님 지시로 이미 회수돼 있습니다 — `20260912161754_center_revoke_user_update.sql`.
컬럼을 남기는 정지 지점을 고르더라도 **이 회수를 되돌리지 마세요.** 센터는 가입 때 한 번 고르는 값이고,
잘못 고른 사람은 운영자가 SQL 로 고칩니다.)

마지막으로 PostgREST 에 스키마를 다시 읽힙니다.

```sql
notify pgrst, 'reload schema';
```

### 무료 플랜 일시정지 → Restore

무료 플랜은 7일 미사용 시 프로젝트가 자동 일시정지되고, 이 상태에서는 앱에 연결 오류가 납니다
(실제로 겪은 상황). 소유 계정으로 [supabase.com/dashboard](https://supabase.com/dashboard)에서 해당
프로젝트의 **Restore** 를 누르면 몇 분 뒤 복원됩니다. 스키마/데이터는 유지되므로 재적용은 불필요합니다.

### 관리자 SQL (선택)

팀 생성/합류는 앱 UI 로 충분하지만, SQL Editor 에서 직접 다룰 수도 있습니다. `weekly_goal_hours` 는
**팀원 1인당 주간 목표**입니다(팀 총합 아님). 참여코드는 `create_team` RPC 로 만들 때만 자동 발급됩니다.

```sql
-- 앱과 동일하게 참여코드까지 자동 발급하며 만들기(로그인 사용자 컨텍스트):
select * from public.create_team('팀이름', 60);

-- 코드를 직접 정하는 저수준 삽입(코드는 팀마다 고유해야 함):
insert into public.teams (name, invite_code, weekly_goal_hours) values ('팀이름', '코드', 60);

-- 기존 팀의 주간 목표시간 변경(다음 새로고침부터 반영):
update public.teams set weekly_goal_hours = 40 where name = '팀이름';
```

## 트러블슈팅

- **`stapler validate` 실패 / 스테이플 없음** — `dist/aing-check.zip` 이 공증 전(예: `package-local.sh` 산출물)일 때 발생합니다. `./scripts/package-notarized.sh` 로 다시 만드세요.
- **`CHANGELOG.md 에 '## <버전>' 섹션이 없거나 비어 있습니다`** — 이번 버전의 변경 내용을 아직 안 적은 것입니다. `CHANGELOG.md` 맨 위에 `## <버전>` 을 만들고 사용자 문장으로 한 줄씩(2~4줄) 적은 뒤 다시 실행하세요. 앱 배너에 그대로 뜨는 문구이므로 내부 구조·파일명 대신 "무엇이 좋아졌는지"를 씁니다.
- **`gh auth status` 실패** — `gh auth login` 을 다시 실행합니다.
- **tap 저장소를 찾을 수 없음** — `../homebrew-check` 에 클론했는지, 아니면 `GH_TAP_DIR` 로 경로를 지정했는지 확인합니다. 저장소가 없으면 스크립트가 `gh repo create ...` 안내를 출력합니다.
- **팀원이 옛 버전을 받음** — `brew update` 로 tap 을 먼저 갱신한 뒤 `brew upgrade --cask aing-check` 를 실행하도록 안내합니다.
