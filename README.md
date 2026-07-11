# check

`check`는 소규모 Mac 팀이 상단바에서 근무 상태와 타이머를 바로 확인하는 메뉴바 전용 유틸리티입니다.

- 앱 이름: `check`
- Bundle ID: `kingcheck`
- 기본 팀 이름: `sudo 박수`
- Supabase URL: `https://xfnhfjvubetkdnfkfljg.supabase.co`

Supabase anon key 원문은 git에 커밋하지 않습니다. 로컬 실행 시 `CHECK_SUPABASE_ANON_KEY` 환경 변수나 git에서 제외된 로컬 설정 파일로 주입합니다.
앱에 `Supabase 키 오류`가 표시되면 현재 주입한 anon key가 원격 프로젝트에서 거부된 것입니다. Supabase Dashboard의 Project Settings > API에서 현재 anon/public key를 다시 가져와 주입해야 합니다.

## 로컬 실행

```sh
export CHECK_SUPABASE_ANON_KEY="<Supabase anon key>"
swift test
./scripts/build-local.sh
open dist/check.app
```

사용하는 환경 변수:

```sh
CHECK_SUPABASE_ANON_KEY="<Supabase anon/public key>"
```

메뉴바 팝오버 가입 화면에서 별명·이메일·비밀번호와 함께 **팀 코드**를 입력합니다. 코드를 넣으면 어떤 팀에 합류하는지 미리보기가 뜨고, `가입`을 누르면 Supabase Auth 계정 생성과 팀 합류가 한 번에 끝납니다. 팀이 아직 없다면 가입 화면에서 **새 팀 만들기**로 전환해 팀 이름과 주간 목표를 입력하면, 계정과 팀이 함께 만들어지고 서버가 참여코드를 자동 발급합니다(다른 사람은 이 코드로 합류). 팀원 목록에는 이메일이 아니라 별명이 표시됩니다. 이미 만든 계정은 `로그인`을 누르면 됩니다.

## 원격 DB 적용

원격 Supabase 프로젝트는 이미 복원되어 정상 동작 중이고, 이 저장소의 스키마도 적용이 끝난 상태입니다. 팀원 상태, 근무 시작/종료, 현재 근무시간, 이번 주 총근무시간이 그대로 동기화됩니다. 앱에 `DB 스키마 필요`가 표시되는 경우에만 아래로 스키마를 다시 적용하면 됩니다.

```sh
supabase link --project-ref xfnhfjvubetkdnfkfljg
supabase db push
```

Supabase Dashboard의 SQL Editor에서 같은 SQL을 실행해도 됩니다: `supabase/migrations/20260701000000_create_check_schema.sql`

### 운영 노트: 프로젝트 일시정지 → Restore

무료 플랜은 7일 동안 사용이 없으면 프로젝트가 자동으로 일시정지(pause)되고, 이 상태에서는 앱에 연결 오류가 나타납니다(이번에 실제로 겪은 상황입니다). 소유 계정으로 [supabase.com/dashboard](https://supabase.com/dashboard)에 접속해 해당 프로젝트의 **Restore** 버튼을 누르면 몇 분 뒤 다시 살아납니다. 복원 후에는 스키마와 데이터가 그대로 유지되므로 재적용은 필요 없습니다.

## 팀 만들기 / 합류 (앱에서)

팀 목록은 더 이상 공개하지 않습니다. **코드가 곧 열쇠**입니다.

- **새 팀 만들기**: 가입 화면에서 `새 팀 만들기`로 전환해 팀 이름과 주간 목표시간(팀원 1인당, 1~168, 기본 60)을 입력하고 가입하면, 계정과 팀이 함께 만들어지고 만든 사람이 owner가 됩니다. 참여코드는 서버가 8자로 자동 발급합니다(헷갈리는 문자 I·L·O·0·1 제외, 기존 팀과 절대 불충돌하도록 UNIQUE 재시도). 만든 직후 공유 안내로 코드가 뜨고, owner는 이후에도 팀 카드에서 코드를 보고 복사할 수 있습니다.
- **코드로 합류**: 가입 화면에 팀 코드를 입력하면 어느 팀인지 미리보기(팀 이름·주간 목표·인원)가 뜨고, `가입` 한 번으로 계정 생성과 합류가 끝납니다. 이미 로그인했는데 소속 팀이 없는 계정은 팀 코드 입력 패널에서 바로 합류할 수 있습니다.
- **코드 입력 규칙**: 대문자화하고 공백·하이픈을 제거해 비교하므로, `x7k2 m9q4` 처럼 넣어도 `X7K2M9Q4` 로 인식합니다.

참고(관리자 SQL): 앱 UI로 충분하지만, 대시보드 SQL Editor에서 직접 팀을 만들 수도 있습니다. 참여코드는 `create_team` RPC로 만들 때만 자동 발급되므로, 직접 넣을 때는 코드도 함께 지정합니다.

```sql
-- 앱과 동일하게 참여코드까지 자동 발급하며 만들기(로그인 사용자 컨텍스트에서 실행):
select * from public.create_team('팀이름', 60);

-- 또는 코드를 직접 정하는 저수준 삽입(코드는 팀마다 고유해야 함):
insert into public.teams (name, invite_code, weekly_goal_hours) values ('팀이름', '코드', 60);

-- 이미 있는 팀의 주간 목표시간 변경(다음 로그인/새로고침부터 게이지에 반영):
update public.teams set weekly_goal_hours = 40 where name = '팀이름';
```

`weekly_goal_hours`는 **팀원 각자의 주간 목표(1인당)** 입니다 — 팀 총합 목표가 아니라 "각자 이번 주 이만큼은 하자"는 약속입니다. 내 팀 카드의 주간 목표 게이지는 **내 주간 누적 ÷ 이 목표**(내 진행률)로 그리고, 팀별 이번 주 화면은 **팀원 평균(총합 ÷ 인원) ÷ 이 목표**로 비교합니다. 값의 출처는 오직 이 컬럼입니다(앱에는 목표 입력 UI가 없습니다). 코드 미리보기는 `lookup_team_by_code(code)` RPC(가입 전 anon 허용, 무차별 대입 완화용 지연 내장)로, 합류는 `join_team(code)` RPC로 처리하며, 두 함수 모두 코드를 정규화해 비교하므로 기존 팀 코드(`SUDOPARK` 등)도 그대로 동작합니다.

## 팀원 배포 패키지 만들기

```sh
./scripts/package-local.sh
```

`package-local.sh`는 `.env.local`의 `CHECK_SUPABASE_ANON_KEY`를 `check.app` 번들 안의 `Contents/Resources/CheckConfig.plist`에 넣고, `build-local.sh`로 앱을 조립·ad-hoc 서명한 뒤 `dist/check.zip`을 만듭니다. 생성된 zip을 팀원에게 전달합니다.

팀은 초대코드로 관리됩니다. 가입 화면에서 팀 코드로 합류하거나 `새 팀 만들기`로 새 팀을 만들 수 있습니다. 가입 시 계정과 팀 합류/생성이 앱에서 함께 처리되므로(DB 트리거는 프로필만 생성), 배포 전에 팀을 미리 만들어 둘 필요가 없습니다.

배포 전 체크리스트:

```sh
./scripts/qa-schema.sh
./scripts/package-local.sh
./scripts/qa-permissions.sh dist/check.app
unzip -t dist/check.zip
```

번들은 ad-hoc(`codesign --sign -`) 서명만 합니다. 사내 배포에는 충분하지만, Gatekeeper 경고 없이 배포하려면 Apple Developer ID 서명과 공증(notarization)이 필요합니다.

### brew 배포 (공증 필요, 선택)

공증까지 마친 앱은 GitHub Releases + Homebrew tap 으로도 배포할 수 있어, 팀원이 `brew tap GH_OWNER/check && brew install --cask check` 로 설치하고 이후 `brew upgrade --cask check` 로 자동 업데이트합니다.
배포 담당자는 `./scripts/package-notarized.sh` 로 공증 zip 을 만든 뒤 `./scripts/release-brew.sh <버전>` 한 번으로 태그·릴리즈·Cask 갱신을 끝냅니다.
최초 세팅(gh 로그인·저장소 2개·`GH_OWNER` 설정), 전체 파이프라인, 공개 릴리즈 리스크는 [`docs/release.md`](docs/release.md) 참고.

## 팀원 설치 (전달받은 zip 기준)

비개발 팀원용 한 장짜리 안내는 [`docs/team-install.md`](docs/team-install.md)에 있습니다. 요약하면 다음과 같습니다.

1. 전달받은 `check.zip`을 더블클릭해 압축을 풉니다. `check` 폴더 안에 `check.app`과 `설치하기.command`가 들어 있습니다.
2. **`설치하기.command` 더블클릭** — 응용 프로그램 폴더 복사 + 격리 해제 + 실행까지 자동으로 처리합니다. 경고로 안 열리면 우클릭(control+클릭) → 열기.
3. 그래도 앱이 **"손상되었기 때문에 열 수 없습니다"** 로 막히면 — ad-hoc 서명(미공증) 앱이 인터넷 경유로 받아져 macOS가 격리한 것이며 실제 손상이 아닙니다. 터미널에서 격리 속성만 제거하면 열립니다:

```sh
xattr -dr com.apple.quarantine /Applications/check.app
```

참고: Apple Developer 계정(연 $99)으로 Developer ID 서명·공증을 하면 이 절차가 완전히 사라집니다. 내부 소규모 배포라 현재는 범위 밖으로 문서화만 해둡니다.

실행하면 메뉴바(상단바)에 아이콘이 뜹니다. 처음이면 별명·이메일·비밀번호와 함께 전달받은 **팀 코드**를 입력하고 `가입`을 누릅니다(팀이 없으면 `새 팀 만들기`로 팀을 만들면서 가입). 이미 만든 계정은 같은 이메일/비밀번호로 `로그인`하면 됩니다.

팝오버 하단에는 아이콘 버튼 3개가 나란히 있습니다: **새로고침**(원형 화살표), **로그아웃**(문에서 나가는 화살표), **앱 종료**(전원 아이콘). 각 아이콘에 마우스를 올리면 한글 툴팁이 떠서 어떤 버튼인지 알 수 있습니다. 로그아웃으로 계정을 해제하고 다른 계정으로 다시 로그인할 수 있으며, 앱 종료로 check를 완전히 끕니다.

## 팀별 이번 주

팀 카드 헤더의 현황 버튼(막대 그래프 아이콘)을 누르면 **팀별 이번 주** 화면이 열립니다. 목표가 1인당이라 팀 규모가 달라도 공정하도록, 이번 주(월요일 KST 기준) **팀원 1인당 평균 근무시간(총합 ÷ 인원)** 이 많은 순으로 보여 줍니다. 각 팀의 평균·1인당 목표 대비 진행률·총시간·인원·근무중 인원이 함께 표시되고 우리 팀 행에는 "우리 팀" 표시가 붙습니다(순위·경쟁 표기는 없습니다). 데이터는 `team_weekly_leaderboard()` RPC(로그인 팀원 전용)로 받아 오며 invite_code 는 노출하지 않습니다.

## 범위

- 포함: 상단바 근무중 표시, 근무 타이머, 팀원 상태, 오늘 근무시간, 팀별 이번 주(주간 총근무시간), Supabase Auth/REST 동기화, RLS 기반 스키마
- 제외: 메인 앱 창, 대시보드, Slack/Calendar/HR/급여 연동, 스크린샷 모니터링, 키보드/마우스 추적, 생산성 점수
