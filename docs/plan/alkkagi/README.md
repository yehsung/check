# 알까기 온라인 대전

오목과 같은 미니게임 입구, 받은 초대 배너와 메뉴바 점, 독립 게임 창을 사용한다.
초대를 수락하면 흑돌부터 각자 30초 안에 5개를 배치하고, 이후 30초씩 번갈아 발사한다.
배치 시간이 끝나면 빈 돌을 자동으로 놓고, 발사 시간이 끝나면 차례를 넘긴다.
돌이 굴러가는 동안 시계는 멈춘다. 창을 닫아도 기권하지 않으며 다시 열면 서버의 판을 받는다.
재화, 내기, 순위와 미션 보상은 추가하지 않는다.

## 로컬에서 두 계정으로 실행

macOS 14 이상과 Swift 6, 이미 실행 중인 Docker가 필요하다. 저장소 루트에서 실행한다.
포트 51051과 51052는 이 테스트가 사용할 수 있는지 먼저 확인한다. 다른 서버를 자동으로 종료하거나
빈 포트로 바꾸지 않는다. 필요하면 시작할 때 `ALKKAGI_TEST_DB_PORT`와 `ALKKAGI_TEST_API_PORT`를 지정한다.

```sh
python3 docs/plan/alkkagi/server/harness/local_stack.py start
python3 docs/plan/alkkagi/server/harness/test_http.py
python3 docs/plan/alkkagi/server/harness/local_stack.py apps
```

마지막 명령이 생성한 `Alkkagi Online A.app`와 `Alkkagi Online B.app`를 각각 연다.
두 앱이 로비를 읽은 뒤 A에서 B에게 도전하고 B에서 수락한다. 서로 다른 인증 사용자로
실제 HTTP API와 PostgreSQL을 사용하므로 돌 배치, 발사, 차례, 시계와 채팅을 두 창에서 확인할 수 있다.
로컬 실행기는 놓친 변경을 0.35초 간격으로 조회한다. Supabase Realtime 연결까지 검증하는 환경은 아니다.
HTTP 테스트는 새 fixture에서 테스트 앱을 열기 전에 실행한다. 이미 진행 중인 시연 판을 초기화하려면
두 앱을 종료한 뒤 `stop`, `start` 순서로 이 로컬 fixture만 다시 만든다.

로컬 fixture는 공개된 테스트 전용 서명 키로 24시간짜리 가짜 JWT를 만든다. 실제 앱 JWT나
키체인을 읽지 않는다. 생성한 설정은 Git에서 제외된 각 앱의 `.build` 내부에만 저장하며,
실제 계정의 토큰을 이 설정에 넣지 않는다. JWT가 만료되면 `apps`를 다시 실행한다.
이 실행기는 loopback 주소만 허용하고, 서버도 loopback에만 바인딩한다.

```sh
./scripts/alkkagi.sh test
python3 docs/plan/alkkagi/server/harness/local_stack.py status
python3 docs/plan/alkkagi/server/harness/local_stack.py stop
```

`stop`은 같은 작업 경로에서 만든 소유 라벨이 있는 컨테이너와 네트워크만 제거한다.
로그인 없는 한 창 로컬 2인 모드는 기존 `./scripts/alkkagi.sh run`으로 계속 실행할 수 있다.

서버 물리와 실제 Swift 엔진을 비교하려면 fixture가 실행 중인 상태에서 다음을 실행한다.
결과와 실행 파일은 Git에서 제외되는 `.build/online` 안에만 만든다.

```sh
swiftc -swift-version 6 -package-name alkkagi-fixtures \
  Sources/CheckCore/AlkkagiGame.swift \
  docs/plan/alkkagi/server/harness/generate-fixtures.swift \
  -o playgrounds/alkkagi/.build/online/generate-physics
playgrounds/alkkagi/.build/online/generate-physics > playgrounds/alkkagi/.build/online/physics-fixtures.json
python3 docs/plan/alkkagi/server/harness/test_physics.py playgrounds/alkkagi/.build/online/physics-fixtures.json
```

## 서버와 클라이언트의 역할

- `AlkkagiOnlineWire`가 RPC와 응답을 정의하고 `AlkkagiOnlineStore`가 초대, 판과 채팅을 관리한다.
  본앱은 기존 `duelRPC`와 세션 갱신 경로를 사용한다. 계정 전환 뒤 늦게 도착한 응답은 폐기한다.
- 서버가 참여자, 현재 차례, 배치 영역, 제한시간과 revision을 검사하고 고정 간격 물리 계산을 수행한다.
  클라이언트는 발사 직전의 상태를 재생해 손맛을 표현한 뒤 서버 상태에 맞춘다.
- 변경 요청은 action UUID로 중복을 제거한다. 돌 배치와 발사는 expected revision도 검사한다.
  서버 시간이 기준이며 클라이언트가 단독으로 차례나 승패를 확정하지 않는다.
- 채팅은 판 revision과 독립된 순번으로 병합한다. 한 메시지는 Unicode codepoint 100자까지이며
  송신 간격은 0.5초다. 알림 끄기는 개인 표시 설정이고 상대 메시지 전송을 차단하지 않는다.
- 본앱은 기존 private `poke:<사용자 UUID>` 채널의 `alkkagi` 이벤트를 받아 상태를 재조회한다.
  알림 payload는 판이나 채팅을 포함하지 않는다. 보이는 창의 3초 조회와 제한시간 종료 시 조회가
  누락된 알림을 복구한다. 가려진 창은 조회를 멈추고 다시 보일 때 따라잡는다.

## RPC 계약

모든 요청은 `p_protocol: 1`을 보낸다. Supabase에서는 `POST /rest/v1/rpc/<이름>`,
로컬 PostgREST에서는 `POST /rpc/<이름>`이다. 인증은 기존 Bearer JWT를 사용한다.

| 이름 | 프로토콜 외 매개변수 | 역할 |
| --- | --- | --- |
| `alkkagi_lobby` | `p_users` | 내 초대와 현재 판, 선택적으로 상대 목록 |
| `alkkagi_challenge` | `p_opponent`, `p_action_id` | 60초 초대 |
| `alkkagi_respond` | `p_match_id`, `p_accept`, `p_action_id` | 수락 또는 거절 |
| `alkkagi_cancel` | `p_match_id`, `p_action_id`, `p_expected_revision?` | 보낸 초대 취소 |
| `alkkagi_state` | `p_match_id`, `p_since_chat_seq` | 판과 이후 채팅 조회 |
| `alkkagi_place` | `p_match_id`, `p_expected_revision`, `p_stone_id`, `p_x`, `p_y`, `p_action_id` | 내 돌 배치 |
| `alkkagi_ready` | `p_match_id`, `p_expected_revision?`, `p_action_id` | 5개 배치 완료 |
| `alkkagi_shoot` | `p_match_id`, `p_expected_revision`, `p_stone_id`, `p_pull_x`, `p_pull_y`, `p_action_id` | 뒤로 당긴 벡터로 발사 |
| `alkkagi_resign` | `p_match_id`, `p_expected_revision?`, `p_action_id` | 기권 |
| `alkkagi_chat_send` | `p_match_id`, `p_body`, `p_action_id` | 대화 보내기 |
| `alkkagi_chat_mute` | `p_match_id`, `p_muted`, `p_action_id` | 개인 알림 설정 |
| `alkkagi_leave` | `p_match_id`, `p_expected_revision?`, `p_action_id` | 종료된 판에서 나가기 |

응답은 `status`, `protocol`, `server_now_ms`와 사용자 정보 `me`를 가진다.
로비는 `incoming`, `outgoing`, 선택적인 `users`를, 진행 중인 판은 `state`를 포함한다.
`state`에는 두 참여자, `my_color`, `revision`, `phase`, `current_player`, `stones`,
`deadline_ms`, `shot_count`, `result`, 최근 `shot`, `chat_seq`, `chat`, `muted`가 있다.
돌 ID 0~4는 흑돌, 5~9는 백돌이며 좌표는 600×600이다.

단계는 `placing_black`, `placing_white`, `aiming`, `rolling`, `finished`다.
`rolling` 중 `deadline_ms`는 발사자의 원래 제한시간이고 남은 시간은 `shot.started_at_ms`에서 고정한다.
굴러가는 결과는 서버 내부에서 보관하며 단계가 `finished`가 되기 전에는 `result`를 공개하지 않는다.
`stale` 응답은 최신 판을 포함하며 오래된 입력을 자동으로 다시 실행하지 않는다.
참여하지 않은 사람에게는 `not_found`를 돌려준다. 알 수 없는 프로토콜과 단계는 클라이언트가 동작을 막는다.
세부 status와 nullable 필드의 기준은 `Sources/CheckCore/AlkkagiOnlineWire.swift`다.

## 운영 반영 전 필요한 작업

**이 디렉터리의 SQL은 운영에 반영되지 않은 제안본이다.** 저장소에 비공개 Supabase 마이그레이션과
현재 공용 대전 중 판정 함수의 본문이 없으므로 기존 함수를 추정해 덮어쓰지 않는다.
앱 JWT만으로 새 테이블이나 RPC를 설치할 수 없다. 서버 소유자가 실제 마이그레이션 체인에 통합해야 한다.

1. 실제 프로젝트의 `profiles`와 `auth.uid()`, `same_visibility(uuid,uuid)`,
   `blocked_between(uuid,uuid)`, `realtime.send(jsonb,text,text,boolean)` 계약을 확인한다.
   제안본은 의존성이 없거나 소유권이 부적합하면 적용을 거부한다.
2. 신뢰하는 비 API 마이그레이션 계정으로 물리 SQL, 대전 SQL 순서로 적용한다.
   두 파일을 하나의 마이그레이션 트랜잭션으로 실행하고 기존 객체 이름과 충돌하지 않는지 확인한다.
   `server/harness/bootstrap.sql`은 가짜 사용자와 테스트 역할을 만드는 로컬 전용 파일이므로 적용하지 않는다.
3. owner 전용 `alk_busy(uuid)`를 기존 `game__busy_users()` 등 공용 대전 중 판정에 통합한다.
   현재 제안본의 중복 대전 제한은 알까기 내부만 보장한다. 다른 게임과의 배타성은 이 통합 전까지 보장하지 않는다.
4. 운영 정리 작업에 종료된 초대 1일, 끝난 판 30일 보관 정책을 통합한다. 진행 중인 판과
   action ID는 시간만으로 삭제하지 않는다. 마지막 채팅 200개와 성공 action 16,384개 제한은 SQL에 있다.
   계정 삭제 시 profiles 외래 키의 cascade가 작동하는지 실제 삭제 경로와 함께 검증한다.
5. 개발 환경에서 실제 두 계정과 기존 private poke 채널의 권한으로 초대, 알림, 재접속을 확인한다.
   그 후 서버를 먼저 배포하고 업데이트된 앱을 배포한다. 프로토콜을 등록한 최근 24시간 내 클라이언트에게만 초대한다.

서버 RPC가 없으면 온라인 화면은 사용할 수 없다고 표시한다. 기존 오목이나 다른 게임의 서버 함수를 대체하지 않는다.
