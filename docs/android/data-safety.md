---
# 원본: 없음 — Swift 짝 없음(Play 데이터 보안 설문 답 초안). 답의 정본은 설계 E §9.5, 근거는 서버 마이그레이션 141개(서버 ①~③ 반영본)
published: false
---

# 데이터 보안(Data safety) 설문 답 초안

- **초안이다.** Play Console → 앱 콘텐츠 → 데이터 보안에 옮기기 전에 사용자가 확인한다.
- §2 표의 답(수집 · 필수/선택 · 목적)은 **설계 E §9.5 와 같다**(G §2-3 W6-c ③). 검사기가 이 일치를 잰다.
- 이번에 더한 것은 근거 열뿐이다. 서버 마이그레이션의 표·칸 이름과 Android 코드 자리를 적었다.
- 표의 답을 바꿔야 할 후보는 §3 에 따로 모았다. 고르는 일은 사용자 몫이다.

## 1. 정의와 큰 답

Play 정의(https://support.google.com/googleplay/android-developer/answer/10787469):

- 수집 = 기기 밖으로 보냄
- 공유 = 제3자에게 넘김. 서비스 제공자에게 맡기는 것은 공유가 아니다.
- 앱에 들어간 SDK 가 모으는 것도 신고한다.

데이터가 가는 곳은 둘이다.

- Supabase: 백엔드(Auth · DB · Storage · Realtime)
- Google Firebase: FCM 알림 전송

둘 다 서비스 제공자다. 그래서 **공유는 모든 항목에서 '아니오'** 다.

| 설문 문항 | 초안 답 | 근거 |
|---|---|---|
| 앱이 필수 사용자 데이터 유형을 수집하거나 공유하나요? | 예 | §2 |
| 수집하는 사용자 데이터가 전송 중에 모두 암호화되나요? | 예 | HTTPS·WSS 만. `android:usesCleartextTraffic="false"`(debug 도 같다 — `androidApp/src/main/AndroidManifest.xml`) |
| 사용자가 데이터 삭제를 요청할 방법을 제공하나요? | 예 | 앱 안(나 → 설정 → 계정 삭제) + 웹 `https://aing-check.vercel.app/delete-account`(E §9.6). 웹 주소는 이 설문의 삭제 URL 칸에 적는다 |
| 계정을 만들 수 있나요? · 만드는 방법 | 예 · 이메일과 비밀번호(가입 때 이메일 6자리 코드로 본인 확인) | `core/session/…/signup/SignUpStore.kt`, `core/net/…/RpcCore.kt` 의 `/auth/v1/signup`. 문항 문구는 콘솔에서 확인한다 |
| 계정을 지우지 않고 일부 데이터만 지울 수 있나요?(선택 문항) | **비워 둔다(추천)** | 할 일·상태메시지·사진은 앱에서 지울 수 있다. 하지만 '요청 경로'로 내세울 만큼 일관된 기능은 아니다. 사용자 판단 |
| 데이터를 일시적으로만 처리하나요?(항목별) | 아니오(전 항목) | 전부 서버 표에 저장된다 |

## 2. 항목별 답 (E §9.5 와 같은 답)

- 열 '수집'·'필수/선택'·'목적'은 E §9.5 를 옮겼다.
- '공유'는 §1 대로 전부 '아니오'다.

| Play 항목 | 수집 | 공유 | 필수/선택 | 목적 | 무엇이 가나 · 서버 표·칸(근거) |
|---|---|---|---|---|---|
| 개인 정보 › 이메일 주소 | 예 | 아니오 | 필수 | 계정 관리 · 앱 기능 | 로그인·가입 이메일. Supabase Auth(`auth.users`) + `profiles.email`. 비밀번호는 Auth 요청에만 싣고 앱에 저장하지 않는다 |
| 개인 정보 › 이름 | 예(별명) | 아니오 | 필수 | 앱 기능 | `profiles.display_name`. 같은 앱을 쓰는 모든 사용자에게 보인다(처리방침 '수집하는 데이터'). Play 의 '이름'에 별명이 드는지는 **미확인**이다. 첫 실험: 양식의 항목 설명 확인 |
| 개인 정보 › 사용자 ID | 예 | 아니오 | 필수 | 계정 관리 | Supabase 사용자 uuid(`auth.users.id`). 모든 표의 `user_id` 가 이것이다 |
| 사진 및 동영상 › 사진 | 예 | 아니오 | 선택 | 앱 기능 | 프로필 사진 한 장. 시스템 사진 선택기(`PickVisualMedia` — E §4.5 설계, 화면은 W3-b)로 받는다. `profiles.avatar_url` + Storage `avatars` **공개 버킷**(주소를 알면 로그인 없이 열린다 — 처리방침에 있다) |
| 메시지 › 기타 인앱 메시지 | 예 | 아니오 | 선택 | 앱 기능 | 1:1 메시지 `messages.body`(200자, 24시간 뒤 삭제) · 읽음 위치 `message_reads` · 오목 대국 채팅 `gomoku_chat` · 확성기 `megaphones` · 신고한 메시지 본문 사본 `content_reports.message_body`(400자, 보관) · 알림 발송함 `push_outbox.payload`(24시간 뒤 삭제) |
| 앱 활동 › 앱 상호작용 | 예 | 아니오 | 필수 | 앱 기능 | 폰 근무 중 앱을 앞으로 가져온 시각 `phone_work_sessions.last_touch_at`(근무 확인용, 근무가 끝나면 쓰지 않는다) · 콕 기록을 어디까지 봤는지 `poke_reads.read_until` |
| 앱 활동 › 기타 사용자 제작 콘텐츠 | 예 | 아니오 | 선택 | 앱 기능 | 할 일 `todo_items.title` · 상태메시지 `profiles.status_message`(40자) · 팀 주간 목표(`set_team_weekly_goal`) · 팀 만들기의 팀 이름 `teams.name` · 제보 본문 `feedback_reports.body`(1~1000자) · 신고 사유와 자유 입력 `content_reports.reason`·`detail`(200자) |
| 앱 활동 › 기타 작업 | 예 | 아니오 | 필수 | 앱 기능 | 근무 시작·종료 `work_sessions`·`phone_work_sessions`(서버 시계) · 대결 신청·착수·결과·판돈 `gomoku_matches`·`gomoku_moves`·`chess_matches`·`chess_moves`·`tetris_matches`·`tetris_players` · 관전 `match_watchers` · 미니게임 판 시작과 점수 `minigame_rounds`·`minigame_daily_scores` · 루비 장부 `ruby_ledger` · 상점·뽑기·조각 `character_ownership`·`gacha_log`·`character_shards` · 미션 받기 `daily_mission_progress`·주간 근무 `weekly_work_achieved` · 생일 선물 고르기 `character_gifts.claimed_character` · 차단 `user_blocks` · 착용 캐릭터·공개 스위치 `profiles.character`·`minigame_public` · 알림 종류별 켬/끔 `client_devices.push_prefs` |
| 앱 정보 및 성능 › 기타 앱 성능 데이터 | 예(보수적) | 아니오 | 필수 | 앱 기능 | 앱 빌드·버전 문자열 `client_devices.app_build`·`app_version`(기기 등록 — 기능 가능 판정) · 제보에 붙는 앱 버전과 Android 버전 문자열 `feedback_reports.app_version`·`os_version`(`core/stores/…/me/MeStoreFeedback.kt`). iOS 도 보수적으로 신고했다(`docs/appstore.md` §2.1 '기타 진단 데이터') |
| 기기 또는 기타 ID | 예 | 아니오 | 필수 | 앱 기능 | 설치마다 만든 무작위 UUID `client_devices.installation_id` · FCM 등록 토큰 `client_devices.fcm_token`(android 행만 — `20261101100000_client_platforms_android_windows.sql`) · Firebase 설치 ID(FID). FID 는 Firebase SDK 가 만들어 Google 로 보낸다. 아잉체크 서버에는 저장하지 않는다(https://firebase.google.com/docs/android/play-data-disclosure) |
| 위치·연락처·금융·건강·파일·캘린더·오디오·웹 기록·설치 앱·검색 기록·비정상 종료 로그 | 아니오 | — | — | — | 해당 코드·SDK 없음. Google 쪽 SDK 는 `firebase-messaging` 하나뿐이다(`androidApp/build.gradle.kts`). 분석·크래시 SDK 는 넣지 않는다 |
| 보안: 전송 중 암호화 | 예 | — | — | — | §1 |
| 보안: 삭제 요청 수단 | 예 | — | — | — | §1 |

- **맥이 올린 값은 이 앱의 수집이 아니다**(E §9.5).
  - 토큰 사용량·AI 리밋·자리 비움·기기 이름이 그렇다. Android 앱은 이것들을 **읽기만** 한다.
  - 폰은 `work_tick`·`away_sync`·토큰 업로드를 부르지 못한다. `androidApp` 은 `feature/desktop` 에 의존할 수 없다(G §2-0).
- **광고 ID**: 쓰지 않는다.
  - 병합 매니페스트에서 `com.google.android.gms.permission.AD_ID` 를 지운다(`tools:node="remove"`).
  - CI 가 그 권한이 없음을 단언한다(E §9.5, G §4-1).

## 3. E §9.5 와 다를 수 있는 곳 — 사용자 판단

서버 스키마를 읽다가 E §9.5 표에 없는 수집을 찾았다.

- **답을 바꾸지 않는 것**: 위 근거 열에 이미 넣었다.
  - 관전, 콕 읽음 위치, 생일 선물, 차단, 신고, 팀 이름, 확성기, 알림 설정이 그렇다.
  - 모두 E 의 기존 항목 안에 든다.
- **답을 바꿀 수 있는 것**: 아래 표에 모았다. 표 안 '추천'은 이 갈래의 판단이다.

| # | 찾은 것 | 근거 | 바꾸면 | 추천 |
|---|---|---|---|---|
| 1 | **소속 센터**(서울/부산 둘 중 하나, 가입 때 필수 선택) | `profiles.center`, `SignUpStore.kt`(미선택이면 가입 버튼이 안 눌린다), 처리방침 '수집하는 데이터' 넷째 줄 | '개인 정보 › 기타 정보' 행을 더한다: 수집 예 · 필수 · 앱 기능. 별명·아바타와 함께 같은 앱을 쓰는 모든 사용자에게 보인다 | **더한다.** E §9.9 (a) "보수적으로·사실대로"와 맞다. 처리방침에도 이미 적혀 있다 |
| 2 | **팀 코드** | `teams.invite_code` | 서버가 만든 값이다. 사용자가 입력하는 것은 합류 때뿐이다 | 신고하지 않는다(사용자 데이터가 아니라 팀 식별자) |
| 3 | **'이름' 항목 해석** | 위 표 둘째 줄 | Play 가 '이름'을 실명으로만 정의하면 별명을 '기타 정보'로 옮긴다 | 양식의 항목 설명을 읽고 정한다(E 의 미확인 그대로) |

- #1 을 고르면 §2 표에 행을 더하고, 설계 E §9.5 와 검사기 기대값(`_check/check_listing.py` 의 `E_DATA_SAFETY`)을 **같은 커밋에서** 고친다.
  - 문서만 고치면 검사기가 빨갛다. 의도한 동작이다.

## 4. 처리방침과 대조 (main `4cf98bf` 의 `docs/privacy.md`)

Data safety 답과 처리방침 문장이 어긋나면 Play 가 둘 중 하나를 거짓으로 본다. 그래서 줄마다 맞췄다.

| 처리방침 문장(요지) | 이 초안의 자리 | 일치 |
|---|---|---|
| 이메일 · 표시 이름 · 소속 센터 · 프로필 아바타 | §2 이메일·이름·사진 / §3 #1 센터 | 센터만 §3 결정 대기 |
| 1:1 메시지 24시간 삭제 · 확성기 · 읽음 기록 · 신고 시 본문 사본 | §2 메시지 | 예 |
| 오늘 할 일 · 상태메시지 · 제보 · 신고 | §2 기타 사용자 제작 콘텐츠 | 예 |
| 근무 시작·종료 · 폰 앱을 마지막으로 연 시각(근무 확인) | §2 기타 작업 · 앱 상호작용 | 예 |
| 미니게임 기록 · 루비 · 캐릭터 소유 · 뽑기 기록 · 대국 기록 · 미션 | §2 기타 작업 | 예 |
| 기기 등록(설치 UUID · 플랫폼 · 앱 버전·빌드 · 알림 토큰) | §2 기기 ID · 기타 앱 성능 데이터 | 예 |
| "Firebase 설치 ID 는 저장하지 않습니다" · Firebase 라이브러리가 Google 로 보낸다 | §2 기기 ID(SDK 수집으로 신고) | 예 — 서버 저장이 없어도 SDK 가 보내므로 신고한다 |
| 광고 식별자(AD_ID) 안 씀 · 분석·광고·비정상 종료 보고 도구 없음 | §2 마지막 '아니오' 행 · 광고 ID | 예 |
| 권한은 알림 하나 · 사진은 시스템 사진 선택기 한 장 | §2 사진(선택) | 예 |
| 웹에서도 지울 수 있다(aing-check.vercel.app/delete-account) | §1 삭제 요청 수단 | 예 |

- 처리방침 URL·게시 상태는 [app-content.md](app-content.md) §1 에 있다.
- Data safety 를 고치면 이 표도 같이 고친다.
