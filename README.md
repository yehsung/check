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

앱에 `DB 스키마 필요`가 표시되면 원격 Supabase에 테이블이 아직 만들어지지 않은 상태입니다. 이 저장소의 migration을 원격 프로젝트에 적용해야 팀원 상태, 근무 시작/종료, 현재 근무시간, 이번 주 총근무시간이 동기화됩니다.

```sh
supabase link --project-ref xfnhfjvubetkdnfkfljg
supabase db push
```

현재 로컬 Supabase CLI 로그인 계정에서는 이 프로젝트가 목록에 없어 제가 직접 push하지는 못했습니다. Supabase Dashboard에서 같은 SQL을 실행해도 됩니다: `supabase/migrations/20260701000000_create_check_schema.sql`

## 팀원 설치 패키지

```sh
./scripts/package-local.sh
```

`package-local.sh`는 `.env.local`의 `CHECK_SUPABASE_ANON_KEY`를 `check.app` 번들 안의 `Contents/Resources/CheckConfig.plist`에 넣고 `dist/check.zip`을 만듭니다. 생성된 zip을 팀원에게 전달하면 압축 해제 후 `check.app`을 실행할 수 있습니다.

팀은 `sudo 박수` 하나로 고정되어 있습니다. 가입한 사용자는 Supabase Auth 생성 시점에 DB 트리거로 자동 팀원이 되므로, 별도 팀 선택 화면은 없습니다.

팀원 배포 전 체크리스트:

```sh
./scripts/qa-schema.sh
./scripts/package-local.sh
./scripts/qa-permissions.sh dist/check.app
unzip -t dist/check.zip
```

팀원이 처음 실행하면 별명, 이메일, 사용할 비밀번호를 입력하고 `가입`을 누르면 됩니다. 이미 만든 계정은 같은 이메일/비밀번호로 `로그인`하면 됩니다.

## 범위

- 포함: 상단바 근무중 표시, 근무 타이머, 팀원 상태, 오늘 근무시간, Supabase Auth/REST 동기화, RLS 기반 스키마
- 제외: 메인 앱 창, 대시보드, Slack/Calendar/HR/급여 연동, 스크린샷 모니터링, 키보드/마우스 추적, 생산성 점수
