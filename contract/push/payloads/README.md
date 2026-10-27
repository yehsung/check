# push payload 5종 (언어 무관 정본)

서버 SQL 트리거가 `push_outbox.payload` 에 실제로 적는 JSON 이다. 손으로 쓰지 않았다.

- 만든 방법: 비공개 재생 하네스에서 마이그레이션 체인(기본 128 + xplat 서버 초안 M1~M5)을 재생한 뒤, 다섯 경로를 실제로 탔다.
  - `message`: `messages` 에 한 행 → `push_on_message_insert`
  - `gomoku_invite`: `gomoku_matches` 에 pending 행 → `push_on_gomoku_invite`
  - `chess_invite`: `chess_matches` 에 pending 행 → `push_on_chess_invite`
  - `feedback_reply`: `feedback_reports` 의 답장 칸 갱신 → `push_on_feedback_reply`
  - `work_check`: 3시간 지난 폰 근무 → `phone_work__process`
- 사람·id 는 하네스 전용 고정값(`example.invalid` 계정)이다. 비밀은 없다. `_apns.expiration` 은 만든 순간 기준의 절대 시각이다.
- 형식: `jq -S` 로 키를 정렬했고 끝에 줄바꿈이 있다.
- 쓰는 곳
  - push-send(Edge)의 FCM 번역 골든 시험이 같은 바이트의 사본을 읽는다(`Tests/checkTests/XplatServerMigrationTests.swift` 가 두 벌이 같은지 잰다).
  - Android `NotificationSpec` 순수 함수 시험(W1-g)이 이 다섯 파일을 입력으로 쓴다.
- FCM 메시지 모양(K7): **data 전용** + `android.priority = "high"`. `data` 키는 `type` · 각 id · `title` · `body` · `category` · `thread_id`(전부 문자열). `android.ttl` 은 `_apns.expiration` 까지 남은 초, `android.collapse_key` 는 `_apns.collapse_id`. 채널은 앱이 `type` 으로 고른다.
