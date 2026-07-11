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

메뉴바 팝오버에서 별명, 이메일, 사용할 비밀번호를 입력한 뒤 `가입`을 누르면 Supabase Auth 계정을 만들고 로그인합니다. 팀원 목록에는 이메일이 아니라 가입 시 입력한 별명이 표시됩니다. 이미 만든 계정은 `로그인`을 누르면 됩니다.

## 원격 DB 적용

원격 Supabase 프로젝트는 이미 복원되어 정상 동작 중이고, 이 저장소의 스키마도 적용이 끝난 상태입니다. 팀원 상태, 근무 시작/종료, 현재 근무시간, 이번 주 총근무시간이 그대로 동기화됩니다. 앱에 `DB 스키마 필요`가 표시되는 경우에만 아래로 스키마를 다시 적용하면 됩니다.

```sh
supabase link --project-ref xfnhfjvubetkdnfkfljg
supabase db push
```

Supabase Dashboard의 SQL Editor에서 같은 SQL을 실행해도 됩니다: `supabase/migrations/20260701000000_create_check_schema.sql`

### 운영 노트: 프로젝트 일시정지 → Restore

무료 플랜은 7일 동안 사용이 없으면 프로젝트가 자동으로 일시정지(pause)되고, 이 상태에서는 앱에 연결 오류가 나타납니다(이번에 실제로 겪은 상황입니다). 소유 계정으로 [supabase.com/dashboard](https://supabase.com/dashboard)에 접속해 해당 프로젝트의 **Restore** 버튼을 누르면 몇 분 뒤 다시 살아납니다. 복원 후에는 스키마와 데이터가 그대로 유지되므로 재적용은 필요 없습니다.

## 팀 추가 방법

새 팀은 관리자가 Supabase 대시보드의 SQL Editor(또는 `psql`)에서 아래 한 줄을 실행해 추가합니다.

```sql
insert into public.teams (name, invite_code) values ('팀이름', '코드');
```

- `name`은 가입 화면 팀 목록에 표시되는 이름입니다.
- `invite_code`는 팀마다 고유해야 하는 내부 식별용 코드입니다(`unique` 제약). 가입 화면에는 노출되지 않습니다.

반영 원리: 가입 화면은 `team_directory()` RPC로 `public.teams`를 이름순으로 읽어 목록을 만듭니다. 따라서 위 SQL을 실행하면 앱을 다시 배포하지 않아도 다음 가입 화면 진입부터 새 팀이 선택지로 즉시 노출됩니다. `team_directory()`는 `id`와 `name`만 반환하므로 `invite_code`는 절대 노출되지 않습니다.

## 팀원 배포 패키지 만들기

```sh
./scripts/package-local.sh
```

`package-local.sh`는 `.env.local`의 `CHECK_SUPABASE_ANON_KEY`를 `check.app` 번들 안의 `Contents/Resources/CheckConfig.plist`에 넣고, `build-local.sh`로 앱을 조립·ad-hoc 서명한 뒤 `dist/check.zip`을 만듭니다. 생성된 zip을 팀원에게 전달합니다.

팀은 `sudo 박수` 하나로 고정되어 있습니다. 가입한 사용자는 Supabase Auth 생성 시점에 DB 트리거로 자동 팀원이 되므로, 별도 팀 선택 화면은 없습니다.

배포 전 체크리스트:

```sh
./scripts/qa-schema.sh
./scripts/package-local.sh
./scripts/qa-permissions.sh dist/check.app
unzip -t dist/check.zip
```

번들은 ad-hoc(`codesign --sign -`) 서명만 합니다. 사내 배포에는 충분하지만, Gatekeeper 경고 없이 배포하려면 Apple Developer ID 서명과 공증(notarization)이 필요하며 이는 이 프로젝트 범위 밖입니다.

## 팀원 설치 (전달받은 zip 기준)

비개발 팀원용 한 장짜리 안내는 [`docs/team-install.md`](docs/team-install.md)에 있습니다. 요약하면 다음과 같습니다.

1. 전달받은 `check.zip`을 더블클릭해 압축을 풉니다.
2. 나온 `check.app`을 **응용 프로그램(Applications)** 폴더로 옮깁니다.
3. `check.app`을 더블클릭해 실행을 시도합니다. ad-hoc 서명이라 Gatekeeper가 "확인되지 않은 개발자" 경고로 막는데, 정상입니다. **완료**(또는 취소)로 경고를 닫습니다.
4. **시스템 설정 > 개인정보 보호 및 보안**을 열어 하단의 check 관련 안내에서 **그래도 열기**를 누릅니다. 다시 뜨는 확인 창에서 한 번 더 **열기**를 누르면 이후로는 더블클릭으로 실행됩니다. macOS 15(Sequoia)부터는 미공증 앱의 우클릭 → 열기 우회가 제거되어 이 경로가 기본입니다.
5. macOS 14(Sonoma) 이하라면 `check.app`을 **우클릭(또는 control + 클릭) → 열기 → 다시 열기**로도 첫 실행을 할 수 있습니다.
6. 터미널이 편하다면 격리 속성만 제거해도 됩니다.

```sh
xattr -d com.apple.quarantine /Applications/check.app
```

실행하면 메뉴바(상단바)에 아이콘이 뜹니다. 처음이면 별명, 이메일, 사용할 비밀번호를 입력하고 `가입`을 누릅니다. 이미 만든 계정은 같은 이메일/비밀번호로 `로그인`하면 됩니다.

팝오버 하단에는 아이콘 버튼 3개가 나란히 있습니다: **새로고침**(원형 화살표), **로그아웃**(문에서 나가는 화살표), **앱 종료**(전원 아이콘). 각 아이콘에 마우스를 올리면 한글 툴팁이 떠서 어떤 버튼인지 알 수 있습니다. 로그아웃으로 계정을 해제하고 다른 계정으로 다시 로그인할 수 있으며, 앱 종료로 check를 완전히 끕니다.

## 범위

- 포함: 상단바 근무중 표시, 근무 타이머, 팀원 상태, 오늘 근무시간, Supabase Auth/REST 동기화, RLS 기반 스키마
- 제외: 메인 앱 창, 대시보드, Slack/Calendar/HR/급여 연동, 스크린샷 모니터링, 키보드/마우스 추적, 생산성 점수
