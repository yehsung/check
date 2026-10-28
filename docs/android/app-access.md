---
# 원본: 없음 — Swift 짝 없음(Play 앱 액세스·영어 심사 지시문 초안). 바탕 docs/appstore.md §5 @ 3bd04bd(iOS 심사 노트) — 낡은 문장은 §3 목록대로 걸렀다
published: false
---

# 앱 액세스 · 영어 심사 지시문 초안

- **초안이다.** Play Console → 앱 콘텐츠 → 앱 액세스에 옮기기 전에 사용자가 확인한다.
- **자격증명은 이 문서에 없다.** 공개 저장소다.
  - 데모 계정의 이메일·비밀번호는 사용자의 비밀 보관소에만 있다. 콘솔 입력칸에 직접 넣는다.
  - 이 문서·저장소·로그·스크린샷·보고서에는 적지 않는다(iOS 1.0.11 결정과 같다 — `docs/appstore.md` §5.3).

## 1. Play 요건과 이 앱의 답

요건 원문(https://support.google.com/googleplay/android-developer/answer/15748846):

- 심사용 계정은 "accessible at all times, reusable, and valid regardless of user location" 이어야 한다.
- 지시문은 영어로 쓴다.
- 2단계 인증이 있으면 우회할 수 있는 자격을 준다.
- 계정이 만료되면 "the app may be rejected".

| 항목 | 초안 답 | 근거 |
|---|---|---|
| 앱 액세스 | **앱의 모든 기능 또는 일부 기능이 제한됨**(로그인 필요) | 다섯 탭 전부가 로그인 뒤에 있다 |
| 안내 1 이름 | `Demo account A` | — |
| 안내 1 사용자 이름 · 비밀번호 | `<콘솔에만 입력>` · `<콘솔에만 입력>` | **iOS 숨김 심사 계정 A 를 재사용**한다(E §9.7) |
| 안내 1 기타 정보 | §2.1 짧은 지시문(영어). 입력칸이 길게 받으면 §2.2 긴 지시문 | 입력칸 글자 한도는 **미확인**이다. 콘솔에서 확인한다 |
| 안내 2 이름 | `Demo account B (second device — 1:1 messages and matches)` | 메시지·대결은 상대가 있어야 보인다 |
| 안내 2 사용자 이름 · 비밀번호 | `<콘솔에만 입력>` · `<콘솔에만 입력>` | iOS 숨김 심사 계정 B |
| 안내 2 기타 정보 | `Use together with Demo account A on a second device to try 1:1 messages and a 1:1 match. The two demo accounts see only each other.` | — |
| 2단계 인증 | 없음 | 로그인은 이메일·비밀번호 한 번이다(`/auth/v1/token`). 이메일 6자리 코드는 가입·재설정 때만 쓴다 |
| 만료 | 없음 | 숨김 계정은 지우지 않는 한 남는다. iOS 쪽에서 비밀번호를 바꾸면 Play 칸도 같이 고친다 |

**제출 전에 확인할 것**

- **숨김 계정 격리**
  - 숨김 사용자·숨김 팀은 일반 사용자와 양방향으로 격리된다(`20260917160000_hidden_accounts.sql`).
  - 심사 대결·메시지에 실제 사용자가 끌려들지 않는다.
- **대결 시연에는 서버 ⑤ 가 먼저다**
  - 서버의 `gomoku_android_min_build` 등 Android 상수는 처음에 닿을 수 없는 값(2147483647)이다(`20261101110000_device_capable_platforms.sql`).
  - 그래서 대결이 켜진 빌드 N 으로 서버 ⑤ 를 마치기 전에는, Android 기기가 대결 상대로 잡히지 않는다(G §8-17 #1).
  - 대결 문단(§2.2 'Rubies, 1:1 matches…')은 서버 ⑤ 뒤 빌드에만 넣는다.
- **미션은 숨김 계정에서 판정되지 않는다**
  - 누적 미션은 `achievements_settle` 이 숨김 사용자를 바로 돌려보낸다(`20261019120000_achievements.sql`).
  - 일일 미션은 상태 함수가 `profiles.is_hidden` 이면 달성으로 세지 않는다(`20261023130000_daily_missions.sql` 의 `achieved` 계산).
  - 그래서 심사원에게는 [받기] 버튼이 보이지 않는다. Play 는 애플 2.3.1(a) 같은 "새 기능 시연" 요구가 없어 막히지 않는다고 본다(E §9.7 판단).
  - 살아 있는 [받기]를 보이려면 제출 직전 운영에 달성 행을 넣어야 한다. **운영 쓰기라 사용자 동석**이다. 받으면 소진되므로 재심사 때 다시 넣는다(기억 `appstore-metadata-inherits`).
  - `phone_login` 이 Android 기기도 세게 된 것(서버 ① M2)은 숨김 계정에는 상관이 없다.

## 2. 영어 심사 지시문

### 2.1 짧은 지시문 (안내 1 '기타 정보' 칸 — 500자 안)

<!-- field: review_notes_short · 최대 500자 -->
```text
Sign in with this demo account (email and password, no second factor, never expires). It belongs to an isolated demo team: it sees no real users and real users never see it. Tabs: 지금 Now, 메시지 Messages, 순위 Rankings, 게임 Games, 나 Me. Rubies are in-app points earned by working and playing; they cannot be bought, cashed out or sent to others. Delete account: 나 Me > 설정 Settings > 계정 삭제, or https://aing-check.vercel.app/delete-account
```

### 2.2 긴 지시문 (입력칸이 받으면 2.1 대신)

<!-- field: review_notes_long · 최대 4000자 -->
```text
What this app is
아잉체크 (aing-check) is the Android app of a work timer for small teams. A work session can be started and ended from this app's 지금 (Now) tab or from the Mac menu bar app; either way the whole team sees it in real time. On the phone you can also see who on your team is working now, your weekly goal progress and today's to-dos; send 1:1 messages (with six app-provided stickers); play three single-player mini games; play 1:1 Gomoku, Chess or Tetris against another user; and manage a character with in-app points (rubies). Every feature belongs to a team account, so sign-in is required. The app has no ads, no analytics or crash-reporting SDK and no in-app purchases.

Demo accounts
Use the credentials entered in this form. Both demo accounts belong to an isolated demo team: they never see real users, and real users never see them. The passwords do not expire and sign-in has no second factor. To try 1:1 messages or a 1:1 match, sign in as Demo account A on one device and as Demo account B on a second device; the two demo accounts see only each other. Each device only needs to have opened this version once after signing in.

Notifications
After the first sign-in the app explains notifications, then Android 13 and later show the system permission prompt. This is the only permission the app asks for. Notifications are sent for a new 1:1 message, a Gomoku or Chess challenge, a reply to a bug report, and a work check when a work session started on the phone has not been confirmed for a while.

Rubies, 1:1 matches and the character draw
Rubies are earned only by working and by playing mini games. They cannot be bought with money, cashed out, or sent to another user. In 게임 (Games), open 1:1 Gomoku, Chess or Tetris, pick the other demo account, choose a stake of 3, 5 or 10 rubies and send a challenge. When it is accepted both players put in the stake; the winner receives both stakes and a draw returns them. This is declared as simulated gambling in the content rating questionnaire. In 나 (Me), the shop has a character draw that costs rubies only and gives a cosmetic character; its odds are shown in the app right on the draw card (확률 보기, "Show odds").

Reporting and blocking (user-generated content)
In a 1:1 conversation, tap ··· in the top right for 신고하기 (Report) and 차단하기 (Block); long-press a received message to report only that message. The Gomoku match chat drawer has the same ··· menu. Blocked people are listed under 나 (Me) → 설정 (Settings) → 차단한 사람 (Blocked people), where a block can be lifted. Reports are reviewed within 24 hours.

Account deletion
In the app: 나 (Me) → 설정 (Settings) → 계정 삭제 (Delete account), then re-enter the password. On the web, without the app: https://aing-check.vercel.app/delete-account

What may look empty on the demo accounts
Mission progress is not evaluated for isolated demo accounts, so the 미션 (Missions) screen usually lists its rows without a 받기 (Claim) button. "지금 근무 중" (Working now) and the team league show data only while teammates record work.
```

- 대결이 꺼진 빌드(내부 트랙 — 원래 심사 대상이 아니다)에 지시문을 붙여야 하면 두 군데를 뺀다.
  - 'Rubies, 1:1 matches…' 문단의 대결 문장들
  - 'What this app is' 의 "play 1:1 Gomoku, Chess or Tetris against another user"

## 3. 옮기지 않은 낡은 문장 (iOS 심사 노트 → Android)

iOS 노트(`docs/appstore.md` §5.2)는 판마다 덧붙여 와서 지금 Android 에 맞지 않는 문장이 섞여 있다. 아래 목록은 검사기가 §2 의 두 지시문에서 **0건**인지 잰다(대소문자 무시).

| 금지 문구 | 왜 낡았나 |
|---|---|
| `only possible in the Mac app` · `only in the Mac app` · `done in the Mac app` | 폰 근무 시작·종료는 iOS 1.0.7 부터 된다(`docs/appstore.md` §5.2 ★). Android 도 첫 판부터 된다 |
| `two mini games` · `two quick mini games` | 미니게임은 셋이다(타이밍 바·플래피 아잉·테트리스) |
| `iPhone` · `APNs` · `App Store` · `TestFlight` | 플랫폼이 다르다. Android 알림은 FCM 이다 |
| `Guideline` | 애플 심사 지침 번호(1.2 · 2.3.1 …)다. Play 정책 이름이 아니다 |
| `New in 1.` | iOS 판별 변경 블록(1.0.9~1.0.13)이다. Android 첫 판에는 '새 기능' 블록이 없다 |
| `phone_login` · `already achieved` · `turns achieved` | 숨김 데모 계정은 미션 판정을 받지 않는다(§1). iOS 1.0.13 노트의 "한 판 하면 일일 미션이 달성된다"는 숨김 계정에서는 사실이 아니다 |
| `<A_EMAIL>` · `<B_EMAIL>` · `<A_PASSWORD>` · `<B_PASSWORD>` | 자격증명을 문서 안에서 치환하던 옛 틀이다. Play 는 자격증명 칸이 따로 있다 |
| `fee` (낱말) | 대결 수수료는 2026-10-22 에 없어졌다(`20261023132000_duel_fee_off.sql`) |
| `Crossy` · `길건너` · `all-time` | Android 첫 판에 넣지 않는다(G §8-18 #7) |

- 그 밖에 **확률 숫자는 지시문에도 넣지 않는다.** iOS 1.0.10 노트는 확률표를 통째로 적었다. 서버가 바꾸면 거짓이 된다.
  - 지시문은 "앱 안 [확률 보기]에서 보인다"까지만 말한다.

## 4. 한국어 요약 (내부 확인용)

- 데모 계정은 iOS 숨김 심사 계정 A·B 를 재사용한다. 안내 두 세트, 자격증명은 콘솔에만 넣는다.
- 로그인은 비밀번호 한 번이다. 2단계 인증이 없고 만료도 없다.
- 지시문이 다루는 것: 앱 소개, 데모 계정 격리, 알림(권한 하나), 루비·대결·뽑기(모의 도박 신고 사실 포함), 신고·차단, 계정 삭제(앱·웹), 빈 화면 안내.
- 대결 시연은 서버 ⑤ 뒤에만 된다. 미션 [받기]는 숨김 계정이라 안 보인다.
