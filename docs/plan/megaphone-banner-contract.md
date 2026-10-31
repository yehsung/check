# 확성기 배너 계약 — 메시지 한 줄 대신 화면에 크게 (2026-10-30 사용자 결정)

## 결정 (되묻지 말 것)

사용자 원문: "확성기 기능이 임팩트가 너무 없는거 같아. 이건 각자한테 메세지로 가는게 아니라 아예 메인 화면에
확성기 메세지가 팝업처럼 뜨게 마련해줘." AskUserQuestion 으로 고른 것:

| 축 | 결정 |
|---|---|
| 맥 | **화면 위쪽 가운데 큰 배너.** 어떤 앱 위든(전체화면 포함). **5초 뒤 자동으로 올라가고, 마우스를 올리면 멈춘다.** [닫기] 만(2026-10-30 [답장] 제거 · 8초 → 5초) |
| 폰 | 앱을 보고 있으면 어느 탭이든 **위에서 내려오는 배너.** 앱 밖이면 지금처럼 푸시, 눌러 들어오면 배너 |
| 메시지함 | **새 버전은 메시지함에서 빼고 배너로만.** 옛 버전은 업데이트 전까지 지금처럼 📢 메시지로 받는다 |
| 빈도 | **앱 전체에 한 번에 하나** — 누가 보내면 그 뒤 **5분**은 앱 전체에서 아무도 못 보낸다. 작성 화면에 "다음 확성기까지 N분" |
| 그대로 | 30루비 · 사람당 10분 쿨타임 · 받는 사람 집합(숨김·차단·집중 모드 제외) |

## 지금 구조의 사실 (설계를 정한 것)

- `send_megaphone`(정본 `20261014122000_megaphone.sql:308-435`)은 받는 사람마다 `messages` 한 줄(`megaphone_id` 채움,
  본문 앞 `📢 `)을 넣고 `poke_ring` 을 울린다. 받는 쪽은 그것을 **평범한 1:1 메시지**로 본다.
- ★ **`📢 ` 접두는 예약어가 아니다.** `send_message`(`20261101131000`)는 접두를 막지 않는다 → 아무나 `📢 안녕`을
  1:1 로 보낼 수 있다. **접두를 표식으로 믿으면 누구나 공짜로 남의 화면에 배너를 띄운다.** 표식은 `messages.megaphone_id`
  하나뿐이고, 어떤 RPC 도 그 열을 돌려주지 않는다.
- ★ **서버 안 읽음 집계(`message_unread_summary`)가 확성기 줄을 센다.** 새 클라가 줄만 숨기면 그 줄은 영영 읽히지
  않아 **배지가 꺼지지 않는다**(맥 메뉴바 점 · 폰 탭 배지 · 앱 아이콘 배지 전부).
- 실시간 `ring`(`poke_ring`)은 종류·본문·id 를 일부러 싣지 않는다 → 클라가 확성기 울림과 DM 울림을 못 가른다.
- 폰 푸시(`push_on_message_insert`, 정본 `20261022070340`)는 확성기도 `type:"message"` · `category:"MESSAGE"` 로 보낸다.
  확성기 표식이 없다.

## 서버 — 새 파일 하나, 전부 덧붙이기 (옛 클라는 그대로 동작)

파일: `supabase/migrations/20261105120000_megaphone_banner.sql`(운영 마지막 적용분 `20261104120000_rummy_v2` 뒤 — 10-30 18시 기준, 그 앞 `20261103124000_tetris_one_writer` 도 운영.
**적용 직전에 `supabase migration list` 로 번호를 다시 확인**하고, 다른 세션의 대기 파일과 겹치면 뒤로 민다).
운영 적용은 **사용자 동석 승인**.

### S1. 상수
`megaphone_global_cooldown_seconds()` = **300**. 기존 상수 함수와 같은 모양(immutable, PUBLIC execute 유지 — 42501 함정).

### S2. `send_megaphone(p_body, p_request_id)` 재정의 — 정본 본문을 그대로 베끼고 셋만 더한다
1. **전역 쿨타임.** 멱등키 확인(같은 요청 재시도는 자기가 연 전역 창에 안 막혀야 한다) → 사람당 쿨타임 → **전역 잠금
   `pg_advisory_xact_lock(hashtext('megaphone_global'))`** → 전역 확인 순서. 잠금 순서는 언제나 `ultra_wallet:<uid>` → 전역
   (다른 함수는 전역 잠금을 쥐지 않으므로 교착이 없다).
   전역 창은 `max(created_at) from megaphones m where public.same_visibility(uid, m.sender)` — 숨김(심사·시험) 계정이
   실사용자를 막지 않게.
2. **응답.** 둘 다 기존 모양 `{status:'cooldown', cooldown_seconds, retry_after_seconds}` 그대로에 **`scope` 키를 더한다**:
   `'self'`(사람당) · `'global'`(전역). 옛 클라는 `scope` 를 모르고 "N분 뒤에 다시 보낼 수 있어요"를 그대로 말한다(맞는 말이다).
   **사람당 창에 걸렸을 때도 전역 남음을 읽어 긴 쪽 시간·그 scope 로 답한다(같으면 `'global'`)** — 옛 클라가 응답의
   `retry_after_seconds` 로 잠금을 풀기 때문이다(검토 반영 2026-10-30, 프로브 ⑮).
3. **배너 신호.** 각 받는 사람에게 `poke_ring` 다음에 `realtime.send({v:1, m:<megaphone_id>}, 'megaphone', poke_topic(target), true)`.
   예외는 `poke_ring` 과 같은 방식으로 삼킨다(신호 실패가 루비 차감·fan-out 을 롤백하지 않게). 옛 맥·폰은 모르는 이벤트를
   `.drain` 으로 접는다(`message_read` 선례) — 해가 없다.
- fan-out(`messages` 줄) · 접두 · `poke_ring` · 루비·장부·멱등은 **그대로**다. 가격 상수는 계속 `megaphone_ruby_price()` 로 부른다
  (`V0354MegaphonePriceTests` 사후 단언).

### S3. `megaphone_info()` 재정의
기존 키 전부 유지 + `global_cooldown_seconds` · `global_cooldown_remaining_seconds` · `cooldown_scope`(`'self'|'global'|null`,
둘이 같으면 `'global'`).
**`cooldown_remaining_seconds` = max(사람당 남음, 전역 남음)** — 옛 클라 작성 화면이 그대로 맞는 시간을 말한다.

### S4. 새 RPC `megaphone_inbox(p_hours int default 24)`
security definer · `authenticated` 만 · 벽은 `m.to_user = auth.uid()` 하나(손대지 마라).
조건: `m.megaphone_id is not null` · `not blocked_between(uid, m.from_user)` · `m.created_at >= now() - least(greatest(p_hours,1),24) 시간`.
**개수로 자르지 않는다**(24시간 창만 — 전역 5분 창이라 하루 최대 288개. 20개로 자르면 오래된 확성기 줄이 필터에서 빠져
메시지함에 1:1 로 샌다 — 검토 반영 2026-10-30, 프로브 ⑭). 반환은 setof(PostgREST JSON 배열 → `[MegaphoneInboxItem]`):
`message_id, megaphone_id, sender_id, sender_display_name(coalesce '사용자'), sender_avatar_url, body(접두를 뗀 본문), created_at, created_epoch`.
profiles 는 함수 안에서 조인한다(PostgREST 임베드 모호성 회피).

### S5. 새 RPC `message_unread_summary_v2()`
`message_unread_summary` 의 현재 본문(정본 `20260918180000:697-731`) + **`and m.megaphone_id is null`**. 차단 필터 유지.
기존 `message_unread_summary` 는 **재정의하지 않는다**(V0333 관문 함수 · 옛 클라). `_v2(` 이름은 V0333 정규식에 안 걸린다.

### S6. `push_on_message_insert()` 재정의
정본(`20261022070340:42-90`)을 베끼고, `new.megaphone_id is not null` 일 때만 **최상위 `megaphone_id`** 를 더한다.
`type:'message'` · `category:'MESSAGE'` · `thread-id` · `sticker_push_label(new.body)` · 예외 삼키기는 그대로(옛 폰이 의존).
푸시 함수(edge)는 최상위 키를 APNs·FCM 둘 다로 그대로 넘기므로 손대지 않는다.

### 서버 시험 함정 (지키지 않으면 빨갛다)
- `send_message` · `message_history` · `message_unread_summary` 를 **재정의하지 마라**(V0333 관문 · `MessageIdempotencyMigrationTests`).
  V0333 `functionBody` 는 **주석까지** 읽는다 — 주석에 `create … function public.message_unread_summary(` 꼴을 쓰지 마라.
- `megaphone_ruby_price` 를 재정의하지 마라. 주석에 `create or replace function public.message_history_with_pokes(` 를 쓰지 마라(V0365).
- 달러 인용 태그 문자열을 DO 블록 주석에 쓰지 마라. 모든 인자에 DEFAULT.
- 새 시험 파일 `Tests/checkTests/MegaphoneBannerMigrationTests.swift`: 위 S1~S6 의 모양·순서(멱등→사람당→전역 잠금→전역 확인)·
  `scope` 두 갈래·`megaphone` 신호의 예외 삼키기·v2 의 `megaphone_id is null`·푸시 키·벽 한 줄을 단언.

## 코어 (CheckCore — 맥·폰 한 벌)

### C1. 전선
- `MegaphoneInboxItem`(Decodable, 전 필드 옵셔널 규약 + 필수 `messageId`·`megaphoneId`) → 도메인 `MegaphoneBanner`
  `{messageID, megaphoneID, senderID, senderName, senderAvatarURL, body, createdAt}`.
- `MegaphoneInfoResponse` 에 `globalCooldownSeconds` · `globalCooldownRemainingSeconds` · `cooldownScope` (옵셔널).
- `MegaphoneSendResponse` 에 `scope` (옵셔널). `MegaphoneSendOutcome.cooldown` 이 scope 를 든다(`.global` / `.personal` / 모름=personal).
  서버의 `'self'` 는 Swift 의 `.self` 와 겹쳐 `MegaphoneCooldownScope.personal` 로 옮겼다.
- `MegaphoneStore.onSent(body, megaphoneID)` — 전송이 `sent` 로 끝났을 때 소유자(맥 WorkTimerStore · 폰 MessagesStore)가
  `presentOwn` 을 부르는 유일한 문. 실시간 `'megaphone'` 은 `RealtimeEffect.megaphoneSignal` 로 갈린다(맥·폰 러너 모두 `refresh()`).
- `MegaphoneBannerStore.onCapabilityChange` — `capability` 가 바뀔 때마다(첫 판정 · 실시간 · 푸시 · 판정 보류 어느 길이든) 한 번.
  폰 메시지함은 여기서 요약 함수 짝(v1/v2)을 다시 맞춘다(첫 판정이 네트워크로 실패한 뒤 배지 고착 — 2026-10-30 안드로이드 검증에서 발견).
- `MegaphoneBannerStore.holdsAutoDismiss` / `autoDismissHoldChanged()` — **보이스오버가 켜져 있으면 저절로 닫지 않는다**([닫기] 동작으로만).
  본문 최대 198자는 5초 안에 다 못 듣고, 누르기·호버 멈춤은 보이스오버 조작이 아니다(2026-10-31 모바일 세션 지적). 맥 `NSWorkspace.isVoiceOverEnabled`(KVO) ·
  폰 `UIAccessibility.isVoiceOverRunning`(`voiceOverStatusDidChangeNotification`). 미룸에서 돌아와 다시 뜨는 배너도 같은 `startTimer` 를 지난다.

### C2. `MegaphoneBannerStore`(@Observable, `GomokuStoreHost` 를 빌린다 — 기존 `MegaphoneStore` 와 같은 결)
- `knownMessageIDs: Set<String>` — **메시지함 필터의 유일한 근거.** `megaphone_inbox` 가 성공했을 때만 채운다.
- `capability: .unknown | .available | .unavailable` — `megaphone_inbox` 가 PGRST202/404 면 `.unavailable` →
  **필터를 끄고 지금처럼 메시지로 보인다**(서버가 아직 안 올라간 창 — 클라 먼저 내도 잃는 것이 없다).
- `refresh()` — `megaphone_inbox` 를 부르고 `knownMessageIDs` 를 갱신, 새로 본 항목을 `pending` 큐에 넣는다.
- 표시 규칙:
  - **신선도 10분**(`MegaphoneBannerRules.freshness = 600`) — `createdAt` 이 10분보다 오래된 항목은 큐에 넣지 않는다
    (켜 둔 사이 놓친 것은 보여 주되 묵은 것은 안 띄운다). **푸시를 눌러 들어온 항목은 24시간 안이면 신선도 무시.**
  - **본 것 기록**: 계정별 최근 100개 `megaphoneID` 를 기본값 저장소에 — 재실행·두 기기 간에도 같은 항목을 두 번 안 띄운다
    (기기 간 공유는 안 한다 — 맥에서 본 것이 폰에 또 뜨는 것은 허용).
  - **한 번에 하나**, 표시 시간 **5초**(`displaySeconds` — 2026-10-30 8초에서 줄임), 다음 항목은 닫힘 0.4초 뒤.
  - **미룸**: 호스트가 `isBannerDeferred == true` 를 말하는 동안(실시간 대결 판 · 미니게임 판 · 폰 시트 위) 큐를 붙든다.
    풀리면 신선도 안의 것만 띄운다.
  - 보낸 사람 본인에게도 **보낸 직후 자기 배너를 한 번** 띄운다(전송 응답의 본문으로 — "이렇게 떴어요"). 서버 fan-out 에는
    본인이 없으므로 중복이 아니다.
- 로그아웃 `reset()` 이 큐·ID·기록 캐시를 비운다(계정별 키라 다음 계정에 새지 않는다).
- 타이머는 주입 가능하게(`clock`, `schedule(after:)`) — 시험이 5초를 기다리지 않는다.

### C3. 메시지함 필터 — 한 술어, 모든 자리
`MegaphoneBannerStore.hides(messageID:) -> Bool` = `capability == .available && knownMessageIDs.contains(id)`.
- 이 술어로 **대화 목록 · 열린 대화 · 안 읽음 사람/수 · 메뉴바 점 · 폰 탭 배지 · 앱 아이콘 배지 · 맥 캐릭터 말풍선 · 팝오버 도착 줄**이
  전부 같은 줄을 뺀다(차단 숨김을 빼는 자리와 같은 자리에 붙인다 — 맥 `unreadMessagePeerIDs`·`receiveConsumedMessages`·
  `performLoadMessageHistory`, 폰 `visibleHistory`).
- 안 읽음 요약은 `capability == .available` 이면 **`message_unread_summary_v2`**, 아니면 기존 함수. v2 가 PGRST202 면 v1 로 내려가고
  **필터도 끈다**(둘은 한 마이그레이션에 같이 온다 — 반쪽 상태에서 숨기기만 하면 배지가 고착된다).
- ★ **경합**: 울림(`ring`) → `take_pokes`/히스토리가 `megaphone` 신호 → `megaphone_inbox` 보다 먼저 올 수 있다. 그래서 본문이
  `📢 ` 로 시작하는데 ID 를 아직 모르는 줄은 **판정 보류** — `refresh()` 를 한 번 기다린 뒤 거른다. 접두는 "확인해 볼 이유"일 뿐
  표식이 아니다(접두만 보고 숨기거나 배너로 띄우지 않는다). 확인 실패(네트워크)면 메시지로 보인다(잃는 쪽보다 낫다).

### C4. 작성 화면 문구 (`MegaphoneText` — 맥·폰 공유)
- 전역 쿨타임: **"다음 확성기까지 N분"**(올림). 사람당: 기존 "N분 뒤에 다시 보낼 수 있어요" 유지. 둘 다면 더 긴 쪽, 같으면 전역 문구.
- 받는 사람 줄: "지금 보내면 N명에게 가요" → **"지금 보내면 N명의 화면에 떠요"**. 확인 문구·가격 줄은 그대로.
- 상점 카드 설명(맥 `CheckShopPanel` · 폰 시트 머리)은 "앱 사용자 모두의 화면 위에 크게 떠요" 결로 고친다(정확한 위치는 레인이 찾는다).
- 사용자 문구 금지어: 서버·RPC·토큰·테스트·전역·scope·쿨타임(→ "N분 뒤"로 말한다).

## 맥 배너 (Sources/check)

- 패널: `CheckMousePanel` 하위 `MegaphoneBannerPanel` — `[.borderless, .nonactivatingPanel]`, `hidesOnDeactivate = false`,
  `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, 레벨은 캐릭터 패널(`.floating`)보다 한 칸 위,
  **`canBecomeKey = false`**(키 입력을 훔치지 않는다 — 대결 중 키보드), `sharingType = .none`(화면 공유에 안 비친다).
  시험 실행에서는 `CheckPanelVisibility` 알파 0 + 화면 밖 주차(케이크 선물 창 패턴).
- 자리: **마우스가 있는 화면**의 `visibleFrame` 위쪽 가운데, 메뉴바 아래 12pt. 폭 `min(화면폭 − 48, 520)`, 높이는 내용대로.
- 내용: 📢 · 보낸 사람 아바타(없으면 기본 아잉) · 닉네임 · 본문(최대 198자, 17pt semibold, 최대 4줄) · [닫기].
  루트에 `.checkTooltipLayer()`.
- 동작: 위에서 0.25초 미끄러져 내려온다(동작 줄이기면 페이드만). **5초 뒤** 0.2초 올라가며 사라진다. 마우스를 올리면 타이머가 멈추고,
  떠나면 남은 시간과 3초 중 긴 쪽으로 다시 센다(`NSTrackingArea` — 키 아닌 패널에서도 동작하는 캐릭터 패널 방식).
- ~~[답장]~~: 2026-10-30 사용자 결정으로 뺐다("닫기 버튼만 냅두고. 5초 지나면 자동으로 다시 올라가게"). 말풍선이 없어 루트 `.checkTooltipLayer()` 도 걷었다.
  확성기 줄이 숨겨져 대화가 비어 있어도 제목이 나오도록 닉네임·아바타를 함께 넘긴다.
- **미룸(`isBannerDeferred`)**: 오목·체스·테트리스 대결이 `playing`/`countdown`, 미니게임 판 진행 중. 아잉 큐브(rummy)는 main 에 없다 —
  '게임 추가' 세션이 자기 판 상태를 이 집계에 한 줄 더하게 알린다.
- 실시간: `RealtimeLink` 의 이벤트 분기에 `megaphone` → `banner.refresh()`(V0327 소스 계약 — 분기·`.drain` 기본이 한 문장 안에).
  예비 경로: 팝오버 열 때·근무 틱 때 60초 스로틀 `refresh()`.

## 폰 배너 (Sources/CheckMobileKit)

- 자리: `MobileRootView` 의 `TabView` 에 `.overlay(alignment: .top)`. **세이프에어리어 아래**(상태바·다이내믹 아일랜드를 덮지 않는다),
  배경만 `ignoresSafeArea`. 탭바 위·아래와 무관하게 위쪽에 붙는다. 좌우 여백 `MobileTheme.sideMargin`.
- 모양: `GlassBackground` 둥근 카드(`NowUndoToast` 의 재료) · 아바타 · 닉네임 · 📢 · 본문 최대 4줄 · [닫기].
  **위로 쓸면 닫힌다.** 카드 밖 터치는 그대로 아래로 지나간다(카드만 hit-test — 게임 캔버스 제스처를 먹지 않는다).
- 동작: 위에서 내려온다(동작 줄이기면 페이드). **5초** 뒤 자동으로 올라간다. 누르고 있는 동안은 멈춘다.
- ~~[답장]~~: 2026-10-30 뺐다(맥과 같은 결정).
- **미룸(`isBannerDeferred`)**: 시트·풀스크린 커버가 떠 있을 때(오버레이가 그 밑에 깔려 안 보인다), `model.games.isAnyMatchScreenVisible`,
  미니게임 판 진행 중(폰은 판 도중 다른 화면으로 가면 `endRound()` 가 점수를 확정한다 — 배너는 판을 끊지 않는다).
- 푸시:
  - **앱이 앞에 있을 때** 확성기 푸시(`megaphone_id` 키)는 시스템 배너를 **숨기고**(`.hidden`) 앱 배너로 — 알림의 제목·본문으로
    바로 띄우고 `refresh()` 로 맞춘다.
  - **푸시를 눌러 들어오면** 대화로 가지 않고 그 항목을 배너로(신선도 무시, 24시간 안). 냉시동은 기존 `waitForSessionSettled` 뒤.
  - `PushPayload` 는 `megaphone_id` 를 **옵셔널로** 읽는다 — 새 `PushKind` 를 만들지 않는다(완전 열거 switch·카테고리 시험이 깨진다).
- 실시간: `MobileRealtimeRunner` 의 이벤트 분기에 `megaphone` → `banner.refresh()`.
- 데모: `Demo/Fixtures/messages/rpc.megaphone_inbox.json` · `rpc.message_unread_summary_v2.json` 추가, 히스토리 픽스처에 확성기 줄 하나
  (같은 id 가 inbox 에도 있어 필터가 보인다). `rpc.megaphone_info.json` 에 전역 키.

## 옛 클라·다른 플랫폼

- 맥 0.3.68 이하·폰 1.0.15 이하·안드로이드·윈도우: 서버 fan-out 이 그대로라 **지금처럼 📢 메시지로 받는다.** 작성 화면은
  `cooldown_remaining_seconds` 로 전역 대기도 맞게 말한다. 모르는 `megaphone` 실시간 이벤트는 `.drain` 으로 접힌다.
- 안드로이드('check 개발')·윈도우('윈도우 개발') 세션에 이 계약을 알린다 — 그쪽도 같은 RPC 로 배너를 붙일 수 있다.

## 그물 — 시험

- 코어: 필터 술어(가능/불가/모름 세 갈래) · 신선도 10분 · 푸시 진입 신선도 무시 · 본 것 기록(재실행·계정 분리) · 한 번에 하나 · 5초 ·
  미룸이 풀리면 신선한 것만 · 접두만 있고 ID 모르는 줄은 refresh 뒤 판정 · inbox 404 → 필터 끔 · v2 404 → v1 + 필터 끔 · 본인 배너 · reset.
- 맥: 패널 속성(키 불가·전 스페이스·전체화면 보조·공유 제외·시험 알파 0) · 위치(마우스 화면 위 가운데) · 호버 멈춤 · [닫기] 만 ·
  메시지함/점/말풍선이 확성기 줄을 빼는 자리 · 실시간 분기 · 작성 문구.
- 폰: 필터가 `visibleHistory` 한 자리에서 배지까지 · 푸시 앞/뒤 분기 · 미룸 · 데모 픽스처 디코드 · **`ios/scripts/build-sim.sh` 초록**(폰 뷰는
  맥 스위트가 컴파일하지 않는다).
- ★ 단언은 부르는 자리를 재라 — "상수가 있다"는 "화면이 그렇게 된다"의 증거가 아니다.
