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
# 1) 코드 수정 후 테스트 (반드시 통과 확인)
export CHECK_SUPABASE_ANON_KEY="<Supabase anon key>"   # 또는 .env.local
swift test

# 2) Developer ID 서명 + 공증 + 스테이플된 배포 zip 생성 → dist/aing-check.zip
./scripts/package-notarized.sh

# 3) 태그·릴리즈·Cask 반영을 한 번에 (먼저 dry-run 으로 확인 권장)
./scripts/release-brew.sh 0.2.0 --dry-run
./scripts/release-brew.sh 0.2.0

# 4) 팀원은 최신 버전으로 업그레이드
brew update && brew upgrade --cask aing-check
```

`release-brew.sh` 가 순서대로 하는 일:

1. **사전점검** — gh 로그인, `GH_OWNER`(또는 `.env.local` 의 `CHECK_GH_OWNER`), `dist/aing-check.zip` 존재 및 공증 스테이플(`stapler validate`) 확인. 하나라도 어긋나면 안내 메시지와 함께 실패합니다(zip 이 없으면 `package-notarized.sh` 를 먼저 돌리라고 안내).
2. **git 태그 + 릴리즈** — `v0.2.0` 태그 생성/푸시 후 `gh release create` 로 릴리즈 생성 + `aing-check.zip` 업로드. 이미 있는 태그/릴리즈는 건너뛰거나 자산만 덮어써서 **다시 실행해도 안전(멱등)** 합니다.
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

스키마는 이미 적용되어 정상 동작 중입니다. 앱에 `DB 스키마 필요`가 표시되는 경우에만 재적용합니다.

```sh
supabase link --project-ref xfnhfjvubetkdnfkfljg
supabase db push
```

Dashboard 의 SQL Editor 에서 직접 실행하려면 `supabase/migrations/` 아래 SQL 파일들을
파일명(타임스탬프) 순서대로 실행합니다.

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
- **`gh auth status` 실패** — `gh auth login` 을 다시 실행합니다.
- **tap 저장소를 찾을 수 없음** — `../homebrew-check` 에 클론했는지, 아니면 `GH_TAP_DIR` 로 경로를 지정했는지 확인합니다. 저장소가 없으면 스크립트가 `gh repo create ...` 안내를 출력합니다.
- **팀원이 옛 버전을 받음** — `brew update` 로 tap 을 먼저 갱신한 뒤 `brew upgrade --cask aing-check` 를 실행하도록 안내합니다.
