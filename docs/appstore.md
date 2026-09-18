# App Store 제출 자료 초안 — aing-check iOS

작성 2026-09-18 · 기준 커밋 `0fc7a72`(재디자인 B · TestFlight 빌드 3) · SPEC-public-release 작업 D.
**코드 수정 없음.** 아래 모든 항목은 저장소의 실제 코드·문서에서 근거를 찾아 `파일:줄` 로 인용했다. 줄 번호는 기준 커밋 시점이며,
작업 A(계정 삭제 RPC)·B(폰 가입·재설정)·C(앱 안 계정 삭제)가 병합되면 일부가 밀린다 — 그 세 작업이 바꾸는 사실은 각 절에 "작업 B 뒤" 식으로 따로 적었다.
애플 요구 사항은 2026-09-18 에 확인한 공식 문서 기준이고, 확실하지 않은 것은 **확인 필요** 로 표시했다.

---

## 0. 앱 사실 요약 (제출 폼에 그대로 옮길 값)

| 항목 | 값 | 근거 |
| --- | --- | --- |
| 번들 ID | `com.yehsung.aingcheck` | `ios/project.yml:100`, `Sources/CheckMobileShared/CheckMobileIdentifiers.swift:10` |
| 위젯 확장 번들 ID | `com.yehsung.aingcheck.widgets` | `ios/project.yml:181`, `CheckMobileIdentifiers.swift:12` |
| 표시 이름 | `aing-check` | `ios/project.yml:71`, `ios/App/Info.plist`(CFBundleDisplayName) |
| 버전 · 빌드 | `0.1.0` · `3` | `ios/project.yml:30-31`, `Sources/CheckMobileKit/App/MobileAppInfo.swift:5-8` |
| 팀 ID | `MQ2KQK37WD` | `ios/project.yml:23` |
| 지원 기기 · OS | iPhone 전용(`TARGETED_DEVICE_FAMILY: "1"`) · iOS 18.0 이상 · 세로 방향만 | `ios/project.yml:26, 104`, `:15-16, 27`, `:75-76`; `Package.swift:9` |
| 백그라운드 모드 | `remote-notification` 하나 | `ios/project.yml:78-79` |
| 암호화 신고 | `ITSAppUsesNonExemptEncryption: false`(HTTPS 표준 암호화만) | `ios/project.yml:80` |
| URL 스킴 | `aingcheck://`(푸시·위젯 딥링크) | `ios/project.yml:84-87`, `Sources/CheckMobileShared/AingRoute.swift:1-14` |
| 앱 아이콘 | 1024 한 장(`AppIcon-1024.png`) | `ios/App/Assets.xcassets/AppIcon.appiconset/`, `ios/project.yml:106-107` |
| 개발 언어 | 한국어(`developmentLanguage: ko`) — UI 문구 전부 한국어 | `ios/project.yml:18` |
| 외부 SDK | 없음 — 패키지 의존은 저장소 로컬 타깃뿐, `url:` 의존 0건 | `Package.swift:36-64`(dependencies 전부 로컬 이름), `ios/project.yml:42-45`(packages: 로컬 `..` 하나) |
| 앱 내 결제 | 없음(루비는 앱 안 포인트, 현금 구매 불가) | `docs/privacy.md:103`, `README.md`("루비와 상점" 절: "현금으로는 못 삽니다") |
| 배포 채널(현재) | TestFlight — 업데이트 필요 화면이 TestFlight 를 연다 | `Sources/CheckMobileKit/Session/MobileSessionStore.swift:668-671` |

### 0.1 실제 기능 범위 — 탭 다섯 개 (`Sources/CheckMobileKit/`)

루트는 세션 단계로 갈린다: 실행 중 → 업데이트 필요 → 로그인 → 탭 다섯(`App/MobileRootView.swift:7, 52-61, 91-109`).
탭 이름·순서는 `Sources/CheckMobileShared/AingRoute.swift:157-167`(지금 · 메시지 · 순위 · 게임 · 나).

| 탭 | 화면에 있는 것 | 서버에 **쓰는** 것 | 근거 |
| --- | --- | --- | --- |
| 지금 | 내 상태 카드(착용 캐릭터·오늘 타이머·이번 주 막대), 오늘 할 일, 지금 근무 중(우리 팀 경과 / 다른 팀 말 걸기), 주간 목표 편집 시트 | 할 일(`todo_sync`), 팀 주간 목표(`set_team_weekly_goal`). **근무 시작/종료는 없다**(읽기만) | `Now/NowTab.swift:7-9`, `Now/NowStore.swift:15-20`, `Now/NowTodoSupport.swift:10-22` |
| 메시지 | 대화 목록 → 1:1 대화, 새 대화(앱 사용자 전체에서 사람 찾기) | 메시지 보내기(`send_message`, 200자), 읽음 위치(`mark_messages_read`) | `Messages/MessagesTab.swift:5-8`, `Messages/MessagesNewConversationSheet.swift:5`, `Messages/MessagesStore.swift:17-20` |
| 순위 | 팀 리그(이번 주) · AI 토큰(이번 달) · 미니게임(오늘) 세 판 | 없음(전부 읽기) | `Rankings/RankingsTab.swift:5-6`, `Rankings/RankingsStore.swift:20-21`, `Rankings/RankingsText.swift:21-27` |
| 게임 | 미니게임 둘(타이밍 바·플래피 아잉), 1:1 오목(로비·신청·대국·채팅), 오늘 내 순위, 지금 대결 중, 루비 알약 → 상점 | 미니게임 판 시작·점수 제출, 오목 신청·수락·착수·기권·채팅·음소거 | `Games/GamesTab.swift:5-8`, `Games/GamesStore.swift:20-30`, `Games/GamesMiniGameHub.swift:220, 263`, `Sources/CheckCore/SupabaseWorkService.swift:1255-1290` |
| 나 | 무대(착용 캐릭터·이름·팀·센터·루비) → 기록(지난주 회고·12주 근무/AI 토큰 잔디·근무 리듬) → 프로필(사진·별명) · 제보 · 설정(공개 설정·알림·화면 모드·팀 코드·로그아웃·버전) · 상점 · 캐릭터 고르기 | 사진 업로드, 별명, 착용 캐릭터, 캐릭터 구매, 제보, 공개 스위치 둘, 알림 종류별 켬/끔 | `Me/MeTab.swift:6-8`, `Me/MeStore.swift:17-24`, `Me/MeSettingsView.swift:7`, `Me/MeProfileView.swift:6` |
| (홈 위젯) | 지금 근무 중 · 내 오늘 · 할 일 — 세 종류. 앱이 쓴 스냅샷 파일만 그린다 | 할 일 체크 인텐트의 `todo_sync` 한 번뿐 | `Sources/CheckWidgetsKit/AingWidgetModel.swift:11-16`, `Sources/CheckMobileShared/WidgetSnapshot.swift:6`, `Sources/CheckWidgetsKit/WidgetTodoToggle.swift:11` |
| (푸시) | 새 메시지 · 오목 신청(수락 버튼) · 제보 답장 세 종류, 앱 배지 = 안 읽은 메시지 + 받은 오목 신청 | 기기 등록(`register_device`), 알림 종류별 설정(`set_push_prefs`) | `Push/PushPayload.swift:6-10`, `Push/PushCoordinator.swift:14-27`, `Session/MobileDeviceService.swift:116-164` |

폰이 **코드로 못 하는 것**(맥 전용): 근무 시작/종료·근무 시각 쓰기, 자리 비움 신호, AI 토큰 집계 업로드, 콕/울트라 찌르기, 울트라 구매, 집중 모드, 팀 합류/생성.
근거: `Sources/CheckCore/SupabaseWorkServiceMacOnly.swift:1-10`(`#if os(macOS)` 파일 — iOS 에서는 컴파일되지 않는다),
`Sources/CheckMobileKit/Demo/MobileStubURLProtocol.swift:175-187`(금지 RPC 목록 `take_pokes · work_tick · … · join_team · create_team`, 읽기 전용 표 `work_sessions · work_statuses · … · token_usage_*`, 금지 profiles 칸 `app_build · app_version · focus_mode`).
**작업 B 뒤** `join_team · create_team` 은 폰에서도 부른다(SPEC 작업 B-1) — 이 목록과 `docs/privacy.md:102` 를 같이 고쳐야 한다(§7 위험 5).

---

## 1. 스토어 기본 문안 (한국어)

글자 수 한도는 App Store Connect 도움말 기준: 이름 30(최소 2) · 부제 30 · 프로모션 텍스트 170 · 설명 4000 · 키워드 100 · 새로운 기능 4000(첫 버전엔 없음).
출처: <https://developer.apple.com/help/app-store-connect/reference/app-information/> (이름·부제·개인정보 URL "Required for iOS and macOS apps"),
<https://developer.apple.com/help/app-store-connect/reference/platform-version-information/> (설명·키워드·지원 URL·저작권 필수, 프로모션 텍스트·마케팅 URL 선택).
**확인 필요**: 키워드 한도가 100 **자**인지 100 **바이트**인지 — 도움말 요약이 "100 bytes" 로 읽혔다. 한글은 UTF-8 3바이트라 바이트 기준이면 33자 안팎이다. 아래 키워드는 두 경우 모두 대비해 둘을 적었다.

### 1.1 이름 (30자)

`aing-check` (10자)

- 그대로 쓴다. 맥 앱·brew cask·저장소 이름과 같다(`README.md:1`, `docs/release.md`). 표시 이름도 이 값이다(`ios/project.yml:71`).
- 대안 `아잉체크 — aing-check`(15자)는 검색엔 도움되지만 브랜드 표기가 둘로 갈린다. 권장하지 않는다.

### 1.2 부제 (30자)

`팀 근무 현황 · 메시지 · 미니게임` (20자)

- 대안: `우리 팀 지금 누가 일하나` (13자) — 감성적이지만 메시지·게임이 빠진다.

### 1.3 프로모션 텍스트 (170자)

> 맥에서 켠 근무가 폰에서도 보여요. 우리 팀이 지금 누가 일하는지, 이번 주 목표는 얼마나 왔는지 한눈에. 팀원과 1:1 메시지, 1:1 오목 대결, 미니게임 순위까지 — 일한 만큼 모은 루비로 캐릭터를 고르세요. (약 110자)

프로모션 텍스트는 심사 없이 언제든 바꿀 수 있다(App Store Connect 도움말) — 정식 출시 뒤 첫 업데이트 예고에 쓴다.

### 1.4 설명 (4000자)

아래 문안은 약 1,300자. 모든 문장은 코드·`docs/privacy.md`·`README.md` 의 사실만 담았다(과장 금지 — 4.2/2.3 대비).

> **aing-check 는 작은 팀을 위한 근무 타이머의 아이폰 동반 앱입니다.**
> 맥 메뉴바 앱(aing-check for Mac)에서 누른 근무 시작·종료가 팀 전체에 실시간으로 공유되고, 아이폰에서는 그 현황을 언제 어디서나 확인하고 팀원과 이야기할 수 있습니다.
>
> **지금** — 내 오늘 근무 시간과 이번 주 목표 달성률, 우리 팀에서 지금 누가 일하고 있는지, 오늘 할 일을 한 화면에서 봅니다. 할 일은 계정에 저장되어 맥과 아이폰, 홈 화면 위젯에서 같은 목록을 씁니다.
>
> **메시지** — 같은 앱을 쓰는 사람 누구와도 1:1 메시지를 주고받습니다(한 번에 200자). 메시지는 24시간이 지나면 서버에서 자동으로 지워집니다. 새 메시지는 푸시 알림으로 받습니다.
>
> **순위** — 팀 리그(이번 주 1인당 평균 근무시간), AI 도구 토큰 사용량(이번 달), 미니게임(오늘) 세 가지 순위판이 있습니다. 내 사용량·기록을 순위판에 공개할지는 설정에서 직접 고릅니다.
>
> **게임** — 타이밍 바와 플래피 아잉, 두 가지 미니게임의 오늘 순위에 도전하세요. 매일 자정 1·2·3등에게 루비를 드립니다. 팀원과 1:1 오목 대결(렌주룰, 한 수 30초)도 할 수 있고, 대국 중에는 짧은 대화를 나눌 수 있습니다.
>
> **나** — 내 캐릭터와 지난주 회고, 최근 12주 근무 잔디, 요일·시간대별 근무 리듬을 봅니다. 근무하며 모은 루비로 상점에서 캐릭터를 사고 착용할 수 있습니다. 루비는 앱 안 포인트이며 현금으로 사거나 바꿀 수 없습니다.
>
> **위젯** — 지금 근무 중인 사람, 내 오늘 근무, 오늘 할 일 위젯을 홈 화면에 둘 수 있습니다. 할 일은 위젯에서 바로 체크됩니다.
>
> **알아 두세요**
> - 근무 시작·종료는 맥 앱에서 합니다. 아이폰 앱은 기록을 보고, 메시지·게임·할 일을 씁니다.
> - 팀에 들어가려면 팀원에게 받은 팀 코드가 필요하고, 코드가 없으면 새 팀을 만들어 혼자 시작할 수 있습니다.
> - 광고·분석·추적 도구를 쓰지 않고, 앱 안 결제가 없습니다. 카메라·마이크·위치·연락처 권한을 요청하지 않습니다.
> - 계정과 기록은 앱 안(나 → 설정)에서 언제든 삭제할 수 있습니다.
>
> 개인정보 처리방침: (§4 의 URL)

근거(문장별): 근무 시작/종료는 맥만 `docs/privacy.md:99`; 할 일 계정 저장·위젯 `privacy.md:19`, `WidgetTodoToggle.swift:11`; 메시지 200자·24시간 `privacy.md:17`, `SupabaseWorkModels.swift:2094`; 순위 세 판·기간 `RankingsText.swift:21-27`; 공개 스위치 `MeText.swift:412-414`; 미니게임 상품 `GamesText.swift:80-83`; 오목 규칙(렌주룰·30초) 사용자 결정 2026-09-16(메모리 gomoku-pvp-decisions) — **확인 필요: 코어 `GomokuRules.swift` 문구와 대조**; 오목 채팅 `Games/GamesGomokuChat.swift:5`; 기록 화면 `Me/MeTab.swift:6-7`; 루비 현금 불가 `privacy.md:103`; 위젯 3종 `AingWidgetModel.swift:11-16`; 권한 없음 `privacy.md:112-114`; 팀 만들기·계정 삭제는 **작업 B·C 뒤에만 참** — 병합 전 제출이면 두 줄을 뺀다.

### 1.5 키워드 (100자)

문자 기준(54자): `근무,팀,타이머,출퇴근,협업,메시지,오목,미니게임,순위,위젯,할일,루비,캐릭터,소마,SW마에스트로`
바이트 기준 대비(≈71바이트): `근무,팀,타이머,메시지,오목,미니게임,순위,위젯,할일`

- 앱 이름은 키워드에 넣지 않는다(이름은 이미 검색된다). 쉼표 뒤 공백 없이.
- "소마·SW마에스트로" 는 첫 배포 대상이 소마 연수생이라 넣었다(사용자 발언 "우선은 테스트 플라잇으로 소마 내부에서만"). 밖에 열 때는 빼도 된다.

### 1.6 카테고리 후보

| 후보 | 장점 | 단점 |
| --- | --- | --- |
| **주 생산성(Productivity) · 부 소셜 네트워킹(Social Networking)** ← 권장 | 앱의 핵심(근무 현황·할 일)과 두 번째 축(메시지·오목)이 정직하게 드러난다 | 소셜 네트워킹은 1.2(UGC) 지침을 더 꼼꼼히 본다 — 어차피 메시지가 있어 1.2 는 피할 수 없다 |
| 주 생산성 · 부 유틸리티 | 무난 | 메시지·게임이 카테고리에 안 보인다 |
| 주 비즈니스 · 부 생산성 | "팀 근무" 가 들어맞는다 | 미니게임·캐릭터와 어울리지 않아 심사원이 의아해할 수 있다 |
| 주 게임 | — | 핵심이 게임이 아니다. 게임 카테고리는 스크린샷·등급 요구가 다르다. 권장하지 않는다 |

### 1.7 영어 문안 (선택 — 심사원용 최소치)

애플 심사원은 영어로 읽는다. 스토어 페이지는 한국어만 내도 되지만, **심사 노트는 영어를 함께**(§5). 영어 로컬라이제이션을 열면 아래를 쓴다.

- Name: `aing-check` · Subtitle: `Team work status, chat & games`
- Description(초안): "aing-check is the iPhone companion of a small-team work timer for Mac. See who on your team is working right now, your weekly goal progress, and today's to-dos; chat 1:1 with teammates, play quick mini games and 1:1 Gomoku, and spend the rubies you earn on characters. Starting and ending work is done in the Mac app; the phone app reads that record. No ads, no analytics, no in-app purchases."

---

## 2. 개인정보 라벨 (App Privacy)

애플 정의: 데이터 항목 분류·목적·"연결됨(linked to the user)"·"추적(tracking)" 은 <https://developer.apple.com/app-store/app-privacy-details/>.
**추적** = 앱에서 모은 사용자·기기 데이터를 **제3자 데이터**와 결합해 광고 타기팅·측정에 쓰거나 데이터 브로커와 공유하는 것.
이 앱은 그런 일을 하지 않는다(§2.4). 모든 항목의 목적은 **앱 기능(App Functionality)** 하나다 — 분석·광고·개인화 목적 처리가 코드에 없다.

데이터가 가는 곳은 둘뿐이다: **Supabase**(백엔드 — Auth·PostgREST·Storage·Realtime, `Sources/CheckCore/SupabaseWorkService.swift:3-5, 1305`)와 **Apple APNs**(푸시 토큰, `Session/MobileDeviceService.swift:69-70`). 둘 다 서비스 제공자이지 광고 파트너가 아니다.

### 2.1 수집함 · 사용자에게 연결됨 · 추적 아님

| 애플 항목 | 실제로 서버에 가는 것 | 근거(파일:줄) |
| --- | --- | --- |
| 연락처 정보 → **이메일 주소** | 로그인·가입 이메일(계정 식별자). 로그인 뒤 폰의 공용 저장소에도 남아 설정 화면 계정 절에 보인다. 비밀번호는 Auth 요청에만 실리고 저장하지 않는다 | `SupabaseWorkService.swift:57-69`(`/auth/v1/token` 본문 email·password), `:78-93`(`/auth/v1/signup` — 작업 B 뒤 폰도 부른다), `MobileSessionStore.swift:194-209`(이메일 저장), `MeSettingsView.swift:282-293`, `docs/privacy.md:7, 28` |
| 식별자 → **사용자 ID** | Supabase 사용자 uuid(모든 요청의 주체), **별명(display_name — 화면 이름)**. 별명은 같은 앱을 쓰는 모든 사용자에게 보인다 | `MobileSessionStore.swift:634-642`(userID 저장), `AingAppGroup.swift:85-89`, `SupabaseWorkService.swift:869-877`(`set_display_name`), `Me/MeText.swift:289`("팀 목록과 순위판에 보이는 이름"), `privacy.md:8` |
| 식별자 → **기기 ID** | 설치마다 앱이 만든 무작위 UUID(키체인) + **APNs 푸시 토큰** + 플랫폼 `ios`. 기기 이름·모델·IDFA·IDFV 는 담지 않는다 | `AingKeychain.swift:34-41`(`InstallationID`), `MobileDeviceService.swift:63-71`(요청 본문 다섯 칸), `:116-140`(`register_device`), `MobileSessionStore.swift:435-440`, `Push/PushCoordinator.swift:228-231`(토큰 hex), `privacy.md:107`; IDFA/IDFV 미사용은 §2.4 grep |
| 사용자 콘텐츠 → **사진 또는 비디오** | 프로필 사진(선택). 시스템 사진 선택 화면에서 고른 한 장 → 256px JPEG → **공개 버킷**(주소를 아는 사람은 로그인 없이 열람 가능) | `Me/MeProfileView.swift:6, 36`(`PhotosPicker` — 사진 전체 권한 없음), `Me/MeStoreProfile.swift:144-162`, `SupabaseWorkService.swift:294-311`(storage upsert + `profiles.avatar_url`), `privacy.md:25, 64` |
| 사용자 콘텐츠 → **이메일 또는 문자 메시지** | 1:1 메시지 본문(200자)·읽음 위치, 오목 대국 채팅(100자). 메시지는 서버가 24시간 뒤 삭제, 대국 채팅은 둘 다 나가면 삭제 | `SupabaseWorkService.swift:726-745`(`send_message`), `SupabaseWorkModels.swift:2094`(200), `SupabaseWorkServiceMessageReads.swift:59-76`(`mark_messages_read`), `Messages/MessagesStore.swift:19-20`, `SupabaseWorkService.swift:1255-1264`(`gomoku_chat_send`), `SupabaseWorkModels.swift:3565-3567`(100), `:1266-1275`(나가면 삭제), `privacy.md:17-18` |
| 사용자 콘텐츠 → **고객 지원** | 버그·요청 제보 본문(1~1000자)·종류. 앱 버전·iOS 버전 문자열이 자동으로 붙는다(화면에 미리 밝힌다). 본인과 운영자만 본다 | `SupabaseWorkService.swift:1041-1058`(`submit_feedback` 네 인자), `Me/MeStoreFeedback.swift:5, 18-33`, `Me/MeText.swift:350`, `privacy.md:21` |
| 사용자 콘텐츠 → **게임플레이 콘텐츠** | 미니게임 판 시작·점수, 오목 신청·착수·기권·결과, 루비 장부(획득·사용), 캐릭터 구매·착용 | `Games/GamesMiniGameHub.swift:220, 263`, `SupabaseWorkService.swift:524-560`, `:667-708`(`set_character`·`shop_state`·`buy_character`), `:1255-1290`(오목 RPC), `Games/GamesStore.swift:20-30`, `privacy.md:20, 22-24` |
| 사용자 콘텐츠 → **기타 사용자 콘텐츠** | 오늘 할 일(제목·만든/고친/끝낸 시각 — 본인만 조회), 팀 주간 목표(팀원 누구나 편집). **작업 B 뒤**: 팀 이름·팀 코드(팀 만들기·합류) | `Now/NowStore.swift:15-20`, `Now/NowTodoSupport.swift:10-22`, `SupabaseWorkServiceTodoSync.swift:15-17`, `SupabaseWorkService.swift:372-380`(`set_team_weekly_goal`), `privacy.md:19`; 작업 B: `SupabaseWorkServiceMacOnly.swift:453, 469`(`join_team`·`create_team` — 옮겨질 본문) |
| 진단 → **기타 진단 데이터** (판단 필요) | 앱 빌드·버전과 iOS 버전 **문자열** — 기기 등록(최소 빌드 판정·APNs 환경)과 제보에 붙는다. 크래시·성능 수집은 없다 | `MobileDeviceService.swift:67-68`, `MobileAppInfo.swift:5-12, 44`, `Me/MeStoreFeedback.swift:24-25`, `Me/MeText.swift:350`. **확인 필요**: 애플 정의상 '앱 기능' 목적 버전 문자열을 진단으로 신고할지 — 보수적으로 신고 권장 |
| (애플 항목 없음) 설정값 | 알림 종류별 켬/끔, 순위 공개 스위치 둘, 착용 캐릭터, 화면 모드(**로컬만**) | `MobileDeviceService.swift:154-164`(`set_push_prefs`), `Me/MeStoreSettings.swift:117, 145`, `SupabaseWorkService.swift:615-625, 853-863`, `Me/MeText.swift:434-436`(화면 모드는 기기 설정) — 라벨에 별도 항목 없음, "기타 데이터" 로 묶을지 **확인 필요** |

"연결됨" 인 이유: 위 모든 행이 로그인 토큰(사용자 uuid)과 함께 저장된다 — 익명화 처리가 없다. "연결 안 됨" 으로 신고할 항목은 없다.

### 2.2 폰이 **읽기만** 하는 것 (라벨의 '수집' 이 아니라 '표시' — 맥 앱이 올린 값)

| 데이터 | 폰 동작 | 근거 |
| --- | --- | --- |
| 근무 시작/종료 시각·근무 시간·현재 근무 상태 | GET 만. 폰은 쓰지 않는다 | `SupabaseWorkServiceMacOnly.swift:1-10`(`#if os(macOS)`), `MobileStubURLProtocol.swift:182-185`(읽기 전용 표), `Now/NowStore.swift:15`, `Me/MeStoreRecords.swift:6`, `privacy.md:99` |
| 마지막으로 컴퓨터를 만진 시각 | 폰은 올리지 않는다(맥만) | `privacy.md:13, 99`, 금지 RPC `away_sync·work_tick` `MobileStubURLProtocol.swift:178-179` |
| AI 도구 토큰 사용량 숫자 | 순위판·내 잔디로 읽기만 | `Rankings/RankingsStore.swift:20`, `Me/MeStoreRecords.swift:6`, `MobileStubURLProtocol.swift:183-184`, `privacy.md:100` |
| 콕/울트라 찌르기 | 폰에 없음 | `MobileStubURLProtocol.swift:178-179`(`poke_user·ultra_poke_user·take_pokes`), `privacy.md:101` |
| 소속 센터(서울/부산) | 읽기만. 쓰는 길이 일부러 없다 | `SupabaseWorkService.swift:635-654`, `privacy.md:10` |

### 2.3 수집하지 않음 (라벨 "데이터를 수집하지 않음" 으로 둘 항목)

| 애플 항목 | 근거 |
| --- | --- |
| 위치(정밀/대략) · 연락처 · 건강/피트니스 · 재무 정보 · 민감 정보 · 검색/브라우징 기록 · 구매 이력 · 주변 환경 · 신체 | `ios/App/Info.plist` 에 `NS*UsageDescription` 키가 하나도 없다(전체 51줄: APNs 환경·표시 이름·URL 스킴·배경 모드·암호화 신고뿐). `privacy.md:112-114`("알림 권한 하나뿐"). §2.4 grep 에 `CLLocation·AVCaptureDevice·CNContact·NSPhotoLibrary·NSCamera` 0건 |
| 사용 데이터(제품 상호작용·광고 데이터) · 진단(크래시·성능) | 분석·크래시 SDK 없음(§2.4). 앱 안에 이벤트 로깅 코드 없음 — 사용자 글이 있는 파일은 `print`/`Logger` 금지 규약(`Messages/MessagesRules.swift:11`, `Me/MeStoreFeedback.swift:9`) |
| 결제 정보 | 앱 안 결제 없음(§0) |

### 2.4 추적(ATT) 없음의 근거

- `Sources/`·`ios/`·`Package.swift` 전체 grep(`ATTrackingManager|AppTrackingTransparency|AdSupport|StoreKit|Firebase|Analytics|Crashlytics|Sentry|advertisingIdentifier|identifierForVendor|CLLocation|AVCaptureDevice|CNContact|NSPhotoLibrary|NSCamera|WebKit|WKWebView|SafariServices`, 데모 픽스처 제외): **0건**(2026-09-18 실행).
- 외부 패키지 0: `Package.swift:36-64` 의 `dependencies` 는 전부 저장소 안 타깃 이름이고 `url:` 이 없다. `ios/project.yml:42-45` 의 `packages` 는 로컬 `..` 하나.
- `Info.plist` 에 `NSUserTrackingUsageDescription` 없음 → ATT 프롬프트를 띄울 수도 없다.
- 문서 약속: `privacy.md:103`("광고·분석·추적 도구를 쓰지 않고"), `:30-37`(수집하지 않는 것).
- 따라서 라벨의 "추적에 사용되는 데이터" 는 **없음**.

### 2.5 폰 안에만 두는 것 (처리방침 문장용)

- 키체인(service `aingcheck-ios`, 앱·위젯 공용 그룹): access/refresh 토큰, 설치 식별자, 로그아웃 정리 장부 — `AingKeychain.swift:8-19`, `Session/MobileSignOutCleanup.swift:5-11, 32`.
- App Group 공용 suite: userID · 이메일 · APNs 토큰 · 기기 등록 시각/서명 — `AingAppGroup.swift:85-99`.
- App Group 파일: 위젯 스냅샷(내 근무 요약·지금 근무 중인 사람 별명·센터·시작 시각·할 일 앞부분), 계정별 할 일 파일 — `WidgetSnapshot.swift:6-11, 60-127`, `AingAppGroup.swift:74`.
- 로그아웃 시 지우는 것: 토큰·userID·등록 키·위젯 스냅샷 + 서버 `unregister_device → logout?scope=local`; 이메일은 스스로 로그아웃할 때만 지운다; 할 일 파일은 남긴다(미전송 변경 보호) — `MobileSessionStore.swift:235-263, 647-655`, `privacy.md:109`.
- 화면 모드 선택은 기기 설정에만 — `Me/MeText.swift:434-436`.

---

## 3. 연령 등급 설문 예상 답

2025-07 개정 설문(4+ · 9+ · 13+ · 16+ · 18+)이며 2026-01-31 까지 모든 앱이 답해야 했다.
출처: <https://developer.apple.com/help/app-store-connect/reference/age-ratings/>, <https://developer.apple.com/news/?id=ks775ehf>, <https://developer.apple.com/news/upcoming-requirements/?id=07242025a>.
도움말 기준 "User-Generated Content" 와 "Messaging and Chat" 은 4+ 등급에서도 허용되는 기능 항목이고, "Social Media"(피드·재배포·발견)는 13+ 이상이다.
설문 정의는 2026-09-18 에 도움말 페이지 원문으로 확인했다 — **모의 도박과 경연은 이 앱에 그대로 들어맞는다**(아래 표에 원문 인용). 첫 초안은 두 항목을 '카지노류 시뮬레이션'·'실물 상품' 조건으로 잘못 읽어 4+ 를 예상했는데, 그런 조건은 애플 정의에 없다.

| 설문 항목 | 답 | 근거 |
| --- | --- | --- |
| 자녀 보호 기능(Parental Controls) | 없음 | 해당 코드 없음 |
| 연령 확인(Age Assurance) | 없음 | 가입은 이메일·비밀번호·별명·센터·팀 코드만(SPEC 작업 B-2) |
| 무제한 웹 접근 | 아니오 | WebKit·SafariServices 0건(§2.4) |
| **사용자 생성 콘텐츠** | **예** | 1:1 메시지, 오목 채팅, 별명, 프로필 사진, 제보 — §2.1 |
| 소셜 미디어 | 아니오(**확인 필요**) | 피드·재게시·팔로우가 없다. 다만 순위판(별명·아바타)이 앱 사용자 전체에게 보인다(`privacy.md:68-72`) — 심사원이 "발견 수단" 으로 볼 여지가 있으면 13+ |
| **메시지 및 채팅** | **예** | `send_message`, 오목 채팅 |
| 광고 | 아니오 | §2.4 |
| 욕설·공포·약물·성적 내용·폭력 | 없음 | 미니게임 둘(타이밍 바·플래피 아잉)과 오목 — 만화 폭력 없음(`Games/GamesText.swift:107-112` 규칙 한 줄) |
| 의료·웰니스 | 없음 | — |
| 도박(실제) | 아니오 | 애플 정의 "Betting or wagering using real money or in-game currency that **may be exchanged for real money**" → 18+. 결제 없음, 루비는 현금 구매·환금 불가(`privacy.md:103`, `README.md` "현금으로는 못 삽니다") — 환금 불가라는 사실이 피하게 해 주는 것은 **이 항목**이지 아래 모의 도박이 아니다 |
| **모의 도박(Simulated Gambling)** | **예 · 드묾(Infrequent) → 13+** | 애플 정의(원문): "Betting or wagering **without** using real money or in-game currency that can be exchanged for real money" — 환금 불가 재화로 거는 것이 정의 그 자체다. 오목은 수락 순간 두 사람이 루비 판돈 3/5/10 을 내고 이긴 쪽이 두 사람 몫을 받는다(무승부·판 가득이면 각자 돌려받음): 로비 응답 `Demo/Fixtures/games/rpc.gomoku_lobby.json:4-8`(stakes), 서버 `supabase/migrations/20260916120000_gomoku_duel.sql:133`(`stake check (3,5,10)`)·`:1057`(수락 시 차감)·`:640`(승자 `+2*stake`)·`:654`(환불), `GamesText.swift:248` "건 루비는 돌려받아요". 등급: 드묾 13+ · 잦음 18+. 오목은 게임 탭 안 카드 하나이고 앱의 주된 활동(근무 현황)이 아니므로 **드묾**으로 답한다. 심사 노트(§5.2)에 "가상 포인트, 실물 가치 없음, 한 판 3~10 루비" 명시 |
| **경연(Contests)** | **예 · 잦음(Frequent) → 13+** | 애플 정의(원문): "Events that allow users to compete with one another for rankings, rewards, or the achievement of personal goals. May include: skill-based competitions, trivia quizzes, or sport or fitness contests" — 실물 상품·상금 조건이 **없다**. 미니게임은 매일 자정(KST) 그날 1·2·3등에게 루비 20·10·5 를 준다(`GamesText.swift:80-83`, 참여 5명부터 지급 `:81-82, 125-128`, `privacy.md:20`). 매일 여는 순위·보상 행사라 **잦음**. 등급: 드묾 4+ · 잦음 13+ |
| 루트 상자 | 아니오 | 확률 뽑기 없음. 캐릭터는 정가 구매(`Me/MeText.swift:215`) |

예상 결과 등급: **13+** — 모의 도박(드묾)과 경연(잦음) 어느 한쪽만으로도 13+ 가 된다. 두 항목을 '아니오' 로 답해 4+ 로 내면 심사에서 등급 정정·거절 사유가 되므로 그렇게 내지 않는다. 4+ 가 꼭 필요하다면 오목 판돈과 자정 상품을 없애는 결정이 먼저인데(둘 다 사용자 결정 사항 — 2026-09-16 오목 루비 3/5/10, 미니게임 상품), 앱이 성인 연수생 대상이고 별명·사진이 전원에게 보이는 점까지 감안하면 13+ 가 앱 성격과도 맞는다. "최소 연령을 더 높게 설정" 옵션은 따로 필요 없다.

---

## 4. 필요한 URL 셋

애플 요구: 개인정보 처리방침 URL **필수**(iOS), 지원 URL **필수**, 마케팅 URL 선택(§1 출처). 심사 지침 5.1.1(i)은 처리방침 링크를 **스토어 메타데이터와 앱 안 둘 다**에 두라고 한다(<https://developer.apple.com/app-store/review/guidelines/>).

지금 상태: `docs/privacy.md` 는 저장소 안에만 있고(`README.md:175` 에서 링크), 앱 화면에는 처리방침 링크가 없다(`Me/MeSettingsView.swift` 절 구성 `:31-37` 에 없음). 저장소 `yehsung/check` 는 퍼블릭(`git remote`: `https://github.com/yehsung/check.git`).

| 후보 | 처리방침 URL | 장점 | 단점 |
| --- | --- | --- | --- |
| A. 깃허브 파일 링크 | `https://github.com/yehsung/check/blob/main/docs/privacy.md` | 지금 당장 된다. 이력이 커밋으로 남는다 | 깃허브 UI(로그인 버튼·파일 트리)가 함께 보여 '앱 처리방침 페이지' 로 보이지 않는다. 브랜치 이동·파일 이름 변경에 깨진다. 애플이 깃허브 blob 링크를 거절한 사례가 있는지 **확인 필요** |
| **B. GitHub Pages** ← 권장 | `https://yehsung.github.io/check/privacy` (저장소 설정 → Pages → `main` 의 `/docs` 폴더) | 무료·깨끗한 URL·같은 저장소에서 관리. `docs/` 에 `index.md`(지원 페이지) 하나 더 두면 지원 URL 도 해결 | Pages 를 켜면 `docs/` 의 다른 내부 문서(release.md·work-tick.md…)도 페이지가 된다 — 저장소가 이미 퍼블릭이라 새로 새는 것은 없지만 `_config.yml` 로 `exclude` 하는 편이 낫다. 커스텀 도메인 없음 |
| C. 별도 도메인 | `https://aing-check.app/privacy` 등 | 브랜드·장기 안정 | 도메인 비용·DNS·호스팅 관리. 첫 출시엔 과하다 |

권장: **B**. 할 일 — (1) 저장소 Settings → Pages 에서 `main` / `docs` 로 켠다, (2) `docs/index.md` 를 만들어 앱 소개 한 문단 + 지원 연락처(운영자 이메일) + 처리방침 링크를 둔다 → 지원 URL = `https://yehsung.github.io/check/`, 마케팅 URL = 같은 주소(선택), (3) `docs/privacy.md` 를 §7 위험 5 대로 고친 뒤 처리방침 URL = `https://yehsung.github.io/check/privacy`, (4) 앱 나 → 설정에 "개인정보 처리방침" 행(링크)을 더한다(코드 변경 — 이번 작업 범위 밖, 작업 C 와 같은 파일이라 그쪽에 얹는 것이 자연스럽다).
**확인 필요**: Pages 를 켠 뒤 실제 URL 이 위 형태로 뜨는지(저장소 이름이 `check` 라 경로가 `/check/`).

---

## 5. 심사 노트 초안 (App Review Information → Notes)

애플 요구: 로그인이 필요한 앱은 데모 계정을 **만료되지 않는** 비밀번호로 제공(지침 2.1, 플랫폼 버전 정보 도움말 "Sign-in required"). 연락처 이름·이메일·전화(국제 형식) 필수.

### 5.1 데모 계정 준비 (제출 전 운영자 작업)

- 서버에는 **숨김 심사 계정** 장치가 이미 있다: 숨김 사용자·숨김 팀은 일반 사용자와 양방향으로 격리된다(목록·순위·로비·메시지·오목·팀 코드 전부) — `/Users/yesung/check/supabase/migrations/20260917160000_hidden_accounts.sql:1-13`(gitignore 폴더 — 워크트리엔 없음), 만드는 절차는 세션 스크래치 `w2/s7/HIDDEN_ACCOUNTS.md`(저장소 밖 — §7 위험 13).
- 계정은 **둘**(A·B)이어야 메시지·오목을 시연할 수 있다. 실서버 e2e 도 같은 구성을 쓴다: 숨김 팀 이름 "앱 심사 팀", 주간 목표 40시간 — `ios/UITests/AingCheckE2ETests.swift:3, 40-41`.
- A 에게 루비를 넉넉히(절차 문서의 "루비 더 주기") — 오목 판돈·캐릭터 구매 시연용.
- **작업 B 뒤** 심사원이 스스로 가입해 볼 수 있으니, 그 경우 만든 계정은 일반 쪽에 생긴다 — 심사 뒤 정리 절차에 포함.

### 5.2 노트 본문 (영어 — 심사원용) — 자리표시자는 제출 때 채운다

> **What this app is**
> aing-check is the iPhone companion app of "aing-check for Mac", a menu-bar work timer used by small teams. On the phone you can see who on your team is working now, your weekly goal progress, and today's to-dos; send 1:1 messages; play two mini games and 1:1 Gomoku with teammates; and manage your character with in-app points (rubies). **Starting/ending a work session is only possible in the Mac app** — the phone reads that record. All features are tied to a team account, so sign-in is required (5.1.1). No ads, no analytics, no third-party SDKs, no in-app purchases; rubies cannot be bought or cashed out.
>
> **Demo accounts (two, so you can test messaging and Gomoku between them)**
> Account A — email: `<A_EMAIL>` / password: `<A_PASSWORD>`
> Account B — email: `<B_EMAIL>` / password: `<B_PASSWORD>`
> Both belong to the demo team "앱 심사 팀" and are isolated from real users. Passwords do not expire.
>
> **Sign-up without an invite code**
> On the login screen tap "가입하기" (Sign up). Choose "팀 만들기" (Create a team) to start alone with a new team — no invite code needed. Or enter a team code to join an existing team.  *(작업 B 병합 뒤에만 참)*
>
> **Password reset**
> Login screen → "비밀번호를 잊었어요" → a 6-digit code is emailed → enter it → set a new password. Completed inside the app. *(작업 B 뒤)*
>
> **Account deletion**
> "나" (Me) tab → "설정" (Settings) → "계정 삭제" (Delete account) → re-enter password → "영구 삭제". The account and all associated data are deleted on the server; bug reports are kept anonymized. *(작업 C 뒤)*
>
> **Push notifications**
> After first sign-in the app shows an explanation sheet, then the system permission prompt. Notifications are sent for: a new 1:1 message, a Gomoku challenge (with an "Accept" action), and a reply to a bug report. To test: sign in as A on the device, allow notifications, then send A a message from B (second device, or B on the same device after signing out A). Note: a notification is not sent to the phone when the same account is actively working on the Mac app with recent keyboard/mouse input — this does not apply to the demo accounts.
>
> **Gomoku (1:1)**
> Games tab → 1:1 오목 → pick B → challenge (stake 3/5/10 rubies) → B accepts (from the push or the Games tab) → 30 seconds per move. A short chat drawer is available during the match; either player can mute it.
>
> **Screens that will look empty for a solo account**
> "지금 근무 중" and the team league only show data when teammates record work in the Mac app. Demo accounts have seeded records.

### 5.3 노트 한국어 요약 (내부 확인용)

- 데모 계정 둘(A·B, 숨김 팀 "앱 심사 팀") · 비밀번호 무기한.
- 팀 코드 없이 "팀 만들기" 로 혼자 시작 가능(작업 B 뒤) · 비밀번호 재설정 6자리 코드 앱 안 완결(작업 B 뒤) · 계정 삭제는 나 → 설정 → 계정 삭제, 비밀번호 재입력(작업 C 뒤).
- 푸시 세 종류·설명 시트 먼저(`Push/PushCoordinator.swift:14-20`) · 맥에서 근무 중이면 폰 알림 생략(`Push/PushPayload.swift:263` `primerMacNote`, `privacy.md:108`) — 데모엔 해당 없음.
- 근무 시작/종료는 맥 전용이라는 점을 **먼저** 말한다(4.2 오해 방지).

---

## 6. 스크린샷 계획 (촬영은 이번 작업이 아니다)

### 6.1 애플 규격 (2026-09-18 확인, <https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/>)

- 형식 `.jpg/.jpeg/.png`, **알파 채널·투명 불가**, 로컬라이제이션당 1~10장.
- iPhone **6.9"**: `1320 × 2868` · `1290 × 2796` · `1260 × 2736`(세로) — iPhone 16 Pro Max 등. 이 한 벌만 올리면 나머지 크기는 애플이 축소해 쓴다.
- iPhone **6.5"**: `1284 × 2778` · `1242 × 2688` — "Required if app runs on iPhone and screenshots for 6.9" display aren't provided".
- 6.3"(`1179 × 2556` · `1206 × 2622`) 이하는 선택. iPad 는 iPhone 전용 앱이라 불필요("Required if app runs on iPad" 만 필수).
- 지침 2.3.3: 스크린샷은 **앱이 실제로 쓰이는 화면**이어야 하고 타이틀 아트·로그인·스플래시만으로는 안 된다.
- **확인 필요**: 6.9" 행의 필수 표기 — 도움말 표에 6.9" 는 요구 문구가 없고 6.5" 에 "6.9" 가 없을 때 필수" 라고만 적혀 있다. 즉 **6.9" 한 벌이면 충분**하다고 읽힌다.

권장: **6.9" 한 벌(1320 × 2868)** 만 찍는다. iPhone 16 Pro Max 시뮬레이터의 원본 해상도가 정확히 1320 × 2868 이라 `simctl io screenshot` 결과를 그대로 쓸 수 있다. 라이트 6장을 기본으로, 다크는 선택(같은 라우트에 `-AingCheckDemoAppearance dark`).

### 6.2 여섯 장

데모 모드는 **DEBUG 빌드에서만** 컴파일되고 스텁 서버가 지어낸 사람·대화(실사용자 없음)를 돌려주며 시계는 2026-09-17 14:05 KST 에 멈춰 있다 — `Demo/MobileDemo.swift:6-16, 32`. Release 번들에서는 픽스처가 제거된다(`ios/project.yml:126-147`). 데모 계정 이메일도 가짜(`demo@aing-check.invalid`, `MobileDemo.swift:36`)라 화면에 실사용자 정보가 실릴 일이 없다.

| # | 화면 | 데모 라우트(`-AingCheckDemoRoute …`) | 캡션 초안(오버레이 문구) | 근거 |
| --- | --- | --- | --- | --- |
| 1 | 지금 — 내 상태·오늘 할 일·지금 근무 중 | `now` | "우리 팀이 지금 누가 일하는지 한눈에" | `Now/NowTab.swift:7-8`, 픽스처 `Demo/Fixtures/now/_now/` |
| 2 | 메시지 — 대화 화면(읽음 표시) | `messages/d0000000-0000-4000-8000-0000000000c1` | "팀원과 1:1 메시지, 24시간 뒤 사라져요" | 장면 픽스처 `Demo/Fixtures/messages/_messages-d0000000-0000-4000-8000-0000000000c1/rpc.message_history_with_reads.json` |
| 3 | 게임 — 오목 대국(판·차례·대화 서랍) | `games/gomoku/match` | "팀원과 1:1 오목 대결" | `Demo/Fixtures/games/_games-gomoku-match/`, `Games/GamesGomokuChat.swift:5` |
| 4 | 게임 — 허브(미니게임 타일·오목 카드·오늘 내 순위) | `games` | "매일 자정 1·2·3등에게 루비" | `Games/GamesTab.swift:5-8`, `Demo/Fixtures/games/_games/` |
| 5 | 순위 — 팀 리그 | `rankings/league` | "이번 주 팀 리그, 1인당 평균으로" | `Rankings/RankingsText.swift:21-27, 39`, `Demo/Fixtures/rankings/rpc.team_weekly_leaderboard.json` |
| 6 | 나 — 캐릭터 무대·기록 잔디 | `me` | "일한 만큼 모은 루비로 캐릭터를" | `Me/MeTab.swift:6-7`, `Demo/Fixtures/me/_me/` |

예비(7~10장 채울 때): `rankings/minigame`(오늘 순위·어제 1등), `me/shop`(상점), `games/flappy`(플래피 아잉), 알림 설명 시트(`now` + `-AingCheckDemoPushPrimer YES`, `Push/PushCoordinator.swift:108-110`), **작업 B 뒤** 가입 화면(라우트 이름은 작업 B 가 정한다 — `login` 은 로그아웃 장면일 뿐 라우트가 아니다, `Tests/CheckMobileKitTests/BaseRouterTests.swift:35-51`).
피할 것: 설정 화면 아래쪽(이메일 칸) — e2e 도 남기지 않는 화면이다(`ios/UITests/AingCheckE2ETests.swift:16`).

### 6.3 촬영 명령 (simctl 만 — SPEC 공통 규칙 3)

```sh
# 1) DEBUG 시뮬레이터 빌드(엔타이틀먼트 포함) — ios/scripts/build-sim.sh:1-11
DERIVED="$SCRATCH/aing-sim"          # 세션 스크래치 아래
ios/scripts/build-sim.sh "$DERIVED" Debug
APP="$DERIVED/Build/Products/Debug-iphonesimulator/AingCheck.app"

# 2) 기기: 6.9" = iPhone 16 Pro Max (원본 1320×2868). 런타임은 iOS 18 이상.
DEV="iPhone 16 Pro Max"
xcrun simctl boot "$DEV" 2>/dev/null || true
xcrun simctl status_bar "$DEV" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl install "$DEV" "$APP"

# 3) 라우트마다: 종료 → 데모 인자로 실행 → 3초 → 스크린샷
shoot() {  # $1 = 파일 이름, $2 = 라우트, $3 = light|dark
  xcrun simctl terminate "$DEV" com.yehsung.aingcheck 2>/dev/null || true
  xcrun simctl launch "$DEV" com.yehsung.aingcheck -AingCheckDemo YES -AingCheckDemoRoute "$2" -AingCheckDemoAppearance "$3"
  sleep 3
  xcrun simctl io "$DEV" screenshot "$1"
}
shoot 01-now.png        now                                           light
shoot 02-message.png    messages/d0000000-0000-4000-8000-0000000000c1 light
shoot 03-gomoku.png     games/gomoku/match                            light
shoot 04-games.png      games                                         light
shoot 05-league.png     rankings/league                               light
shoot 06-me.png         me                                            light
```

- 실행 인자 규약: `MobileDemo.swift:8, 13, 39-44, 96-102`. 픽스처가 없는 호출은 404 로 조용히 접힌다(`:224-227`) — 콘솔에 `[AingCheckDemo] 픽스처 없음` 이 찍히면 그 화면의 빈 칸이 왜 비었는지 알 수 있다.
- 결과 PNG 는 알파 없음(simctl 기본) — 그래도 업로드 전 `sips -g hasAlpha` 로 확인.
- **확인 필요**: 이 맥에 iPhone 16 Pro Max + iOS 18 이상 시뮬레이터 런타임이 설치돼 있는지(`xcrun simctl list devices available`). 없으면 6.9" 원본 해상도가 같은 다른 기기(17 Pro Max 등)의 해상도를 먼저 확인한다.

---

## 7. 남은 위험 목록과 완화책

| # | 위험 | 지침 | 근거 | 완화 |
| --- | --- | --- | --- | --- |
| 1 | **내부용·동반 앱으로 보임** — 폰은 근무 시작/종료를 못 하고 로그인 첫 화면 문구가 "맥의 aing-check 와 같은 계정으로 로그인해요" 다. 심사원 시점엔 "맥 없이는 쓸모가 적은 앱" 으로 읽힐 수 있다 | 4.2 최소 기능 | `Session/MobileSessionViews.swift:22-24`, `privacy.md:99`, `MacOnly.swift:1-10` | 설명·심사 노트에서 동반 앱임을 먼저 밝히고 폰만으로 되는 것(메시지·오목·미니게임·할 일·위젯)을 앞세운다. 데모 계정에 근무 기록을 심어 화면이 차 있게 한다. 근본 해결(폰에서 근무 시작)은 별도 결정 |
| 2 | **로그인 벽** — 모든 화면이 로그인 뒤에 있다 | 5.1.1(v) | `App/MobileRootView.swift:52-61` | 계정 기반 서비스라 허용 범위. 단 폰 안 가입(작업 B)·앱 안 계정 삭제(작업 C)·데모 계정이 **모두** 있어야 한다. 제출 전 병합 확인 |
| 3 | **사용자 생성 콘텐츠 요건 미충족** — 1:1 메시지·오목 채팅·별명·사진이 있는데, 지침 1.2 가 요구하는 네 가지(부적절 콘텐츠 필터 · **신고 수단** · **사용자 차단** · 공개된 연락처) 중 신고·차단이 앱에 없다. 있는 것은 오목 채팅 음소거(판 단위)와 일반 제보 창뿐 | 1.2 | `Sources/CheckCore/GomokuStore.swift:243-245, 1637`(음소거), `Me/MeFeedbackView.swift`(제보), 코드 전체 grep "차단·신고·block" 0건(2026-09-18) | (a) 최소: 심사 노트에 "제보 창이 신고 통로, 메시지는 24시간 자동 삭제, 서버가 본문 길이·문자 종류를 거른다(`SupabaseWorkService.swift:712-716`)" 를 적고 지원 페이지에 연락처를 둔다. (b) 권장: **사용자 차단**(메시지·오목 신청 거부)과 **메시지 신고** RPC + 나 → 설정 행 — 별도 작업. 거절 확률이 가장 높은 항목 |
| 4 | **연령 설문** — 오목 루비 판돈은 애플 정의상 모의 도박(드묾 13+), 매일 자정 상품은 잦은 경연(13+)에 **그대로 들어맞는다**. '아니오' 로 답해 4+ 로 내면 등급 정정·거절 사유 | 연령 등급 | §3(정의 원문 인용) | §3 대로 둘 다 '예' 로 답하고 **13+** 로 낸다. 심사 노트에 "루비는 현금 구매·환금 불가한 앱 안 포인트" 명시(`privacy.md:103`). 4+ 가 필요하면 판돈·자정 상품 제거가 먼저(사용자 결정) |
| 5 | **처리방침이 폰 현실과 어긋남** — `docs/privacy.md` 는 맥 중심이고 폰 절에 "가입을 받지 않습니다"(`:102`), "계정·기록 삭제는 제보로 요청"(`:118`) 이 적혀 있다. 작업 B·C 뒤엔 거짓이 되고, 지침 5.1.1(i) 은 보존·삭제 정책과 삭제 요청 방법을 요구한다. **그리고 오목이 통째로 빠져 있다** — §2.1 라벨은 오목 대국 채팅(100자)을 '이메일 또는 문자 메시지' 로, 오목 신청·착수·결과·판돈을 '게임플레이 콘텐츠' 로 수집 신고하는데, `privacy.md` 에서 오목은 푸시 문장(`:108` "오목 신청") 한 마디뿐이다(`grep -n -e 오목 -e 판돈 -e 대국 docs/privacy.md` → 1건, 2026-09-18 — 표 안이라 정규식의 세로줄을 쓰지 않았다). 루비 항목(`:23`)의 늘고 주는 사유에도 오목 판돈·상금이 없고, 폰 절 첫 문장(`:95`)의 "같은 규칙" 목록에도 없다. 맥 앱도 0.3.27 부터 오목이 있으니 폰과 무관하게 이미 라벨과 처리방침이 어긋난 상태다 | 5.1.1(i) | `privacy.md:23, 93-118`, §2.1 표의 오목 두 행, `SupabaseWorkService.swift:1255-1285`(채팅·나가기·음소거 RPC), `SupabaseWorkModels.swift:3567`(100자) | 작업 B·C 병합 뒤 폰 절을 고친다: 폰 가입(별명·이메일·비밀번호·센터·팀 코드/팀 만들기), 앱 안 계정 삭제(무엇이 지워지고 제보는 익명화된다 — SPEC 서버 계약 `feedback_reports.user_id set null`), 빈 팀 자동 삭제. **오목 항목은 병합을 기다릴 것 없이 지금 "수집하는 데이터" 에 더한다** — 서버 사실은 `supabase/migrations/20260916120000_gomoku_duel.sql`(표 `:129-157`, 청소 `:1426-1433`, 로비 `:1468-1470`)·`20260916200000_gomoku_chat.sql`(표 `:144-154`, 청소 `:52-58, 116`, 나가기 `:511-514`): (a) **대국 기록** — 신청자·상대·판돈(3/5/10)·상태·판·착수·결과·사유·승자·시각. 두 당사자만 조회하고, 로비에는 앱 사용자 전체에게 별명·아바타·근무 중·**대국 중 여부**(`users[].in_match`)가 보인다. 끝난 판의 착수는 30일 뒤, 거절·취소·만료된 신청은 1일 뒤 서버가 지우며, 끝난 판의 결과 행은 전적(승·무·패)으로 남는다. (b) **대국 채팅** — 본문 100자(또는 빠른 문구 코드)·보낸 사람·시각, 두 당사자만. 둘 다 결과 화면을 닫으면 즉시 삭제, 한쪽이 안 닫아도 끝난 지 1일 뒤 삭제(`gomoku_chat_retention_days`). 판마다 상대 채팅 끄기(음소거)는 판 행에 저장돼 **상대에게 표시된다**. (c) **루비**(`:23`) — "오목 판돈으로 줄고, 이기면 두 사람 몫을 받으며, 무승부면 돌려받는다" 를 늘고 주는 사유에 더한다. (d) 폰 절(`:95`) "같은 규칙" 목록에 오목 추가. 그다음 §4 URL 로 게시하고 앱 설정에 링크 |
| 6 | **업데이트 필요 화면이 TestFlight 를 연다** — 스토어 사용자는 TestFlight 가 없다 | 사용자 경험 | `MobileSessionStore.swift:668-671`(`updateBody` "TestFlight 에서…", `itms-beta://`) | 스토어 빌드에선 App Store 페이지(`itms-apps://apps.apple.com/app/id<APP_ID>`)로 바꾼다 — 앱 ID 는 App Store Connect 에서 앱을 만든 뒤 나온다. 코드 변경(작업 범위 밖) |
| 7 | **"맥 앱에서 가입" 문구 잔존** — 팀 코드 공유 문구, 위젯의 팀 없음 문구, 로그인 머리말 | 4.2 · 일관성 | `Me/MeText.swift:461`("맥 앱에서 가입할 때…"), `Sources/CheckWidgetsKit/AingWidgetModel.swift:22`("맥 앱에서 팀에 참여하면 보여요"), `MobileSessionViews.swift:23` | 작업 B 뒤 세 문구를 폰 가입에 맞춰 고친다(작업 B 는 `MobileSessionViews.swift` 만 고치므로 나머지 둘은 남는다) |
| 8 | **소속 센터(서울/부산) 필수 선택** — 가입 규칙이 소마 두 센터를 전제한다. 밖에 열면 해당 없는 사용자가 생긴다 | 4.2 · 가입 UX | SPEC 작업 B-2("소속 센터 서울/부산, 기본 미선택"), `privacy.md:10` | 정식 출시 전에 "해당 없음" 선택지 또는 센터 단계 생략을 결정해야 한다(값이 없으면 표시가 안 붙는 것은 이미 지원 — `privacy.md:10` "값이 없는 계정에는 아무 표시도 붙지 않습니다"). 사용자 결정 필요 |
| 9 | **혼자 쓸 때 빈 화면** — 팀 만들기로 시작하면 "지금 근무 중" 비고, 팀 리그 "아직 이번 주 근무한 팀이 없어요", 위젯 "맥 앱에서 팀에 참여하면 보여요" | 4.2 | `Rankings/RankingsText.swift:41`, `AingWidgetModel.swift:20-22`, `Games/GamesText.swift:84`("아직 기록이 없어요 — 첫 기록의 주인공이 되세요") | 빈 상태 문구는 이미 다 있다. 심사원은 데모 계정(기록 있음)으로 보게 유도(§5.2 마지막 문단) |
| 10 | **공개 아바타 버킷** — 주소를 알면 로그인 없이 열린다 | 5.1.2 | `privacy.md:64`, `SupabaseWorkService.swift:304`(`/storage/v1/object/public/avatars/`) | 처리방침에 이미 적혀 있다. 라벨 "사진 · 연결됨" 으로 정직하게 신고. 버킷 비공개화는 별도 결정 |
| 11 | **데모 계정 절차가 저장소 밖** — `HIDDEN_ACCOUNTS.md` 가 세션 스크래치에만 있다. 세션이 끝나면 사라진다 | 운영 | `/private/tmp/…/scratchpad/w2/s7/HIDDEN_ACCOUNTS.md` | `docs/ops/` 같은 자리로 옮기되 이메일·비밀번호는 비운 채(문서가 그렇게 설계돼 있다 `:4`) |
| 12 | **심사 시연 계정 격리 마이그레이션 적용 여부** | 2.1 | `supabase/migrations/20260917160000_hidden_accounts.sql`(운영 적용 여부는 이 문서에서 확인 불가) | 제출 전 `is_hidden_user(uuid)` 존재를 운영자가 확인(절차 문서 0단계) |
| 13 | **영어 UI 없음** — 스토어를 한국어만 열면 심사원이 화면을 못 읽는다 | 심사 UX | `ios/project.yml:18` | §5.2 영어 노트에 화면 이름을 한국어 그대로 + 영어 뜻 병기(이미 그렇게 썼다). 영어 로컬라이제이션은 나중 |
| 14 | **Sign in with Apple 요구 오해** — 4.8 은 제3자/소셜 로그인을 쓸 때만 요구한다. 우리는 이메일·비밀번호뿐이라 해당 없음 | 4.8 | `SupabaseWorkService.swift:57-69` | 노트에 굳이 적지 않는다. 심사원이 물으면 위 근거로 답 |
| 15 | **암호화 신고** — `ITSAppUsesNonExemptEncryption: false` 는 HTTPS 표준만 쓸 때 유효 | 수출 규정 | `ios/project.yml:80` | 자체 암호화 코드 없음(외부 SDK 0). 유지 |
| 16 | **스크린샷에 실사용자 노출** — 실서버 계정으로 찍으면 팀원 별명·사진이 실린다 | 5.1.2 | `MobileDemo.swift:32`(픽스처는 지어낸 이름만) | §6 대로 데모 모드로만 찍는다 |
| 17 | **제보 익명화 설명** — 계정 삭제 뒤 제보가 남는다는 사실을 처리방침·삭제 시트 둘 다에 적어야 한다 | 5.1.1(v) 계정 삭제 안내(<https://developer.apple.com/support/offering-account-deletion-in-your-app/>: "법적으로 보관해야 하는 데이터 외 전부 삭제") | SPEC 서버 계약(`feedback_reports.user_id on delete set null`), `privacy.md:21` | 삭제 시트 목록(작업 C-2)에 "제보 글은 익명으로 남아요" 한 줄 — 작업 C 에 전달 |

---

## 8. 제출 체크리스트 (순서)

1. 작업 A·B·C 병합 → 전체 스위트 초록 → `ios/scripts/build-sim.sh` 통과.
2. 위험 5·6·7 코드·문서 수정(별도 작은 작업) → `docs/privacy.md` 개정(가입·계정 삭제·빈 팀 + **오목 대국 기록·채팅·판돈** — 위험 5 의 (a)~(d)) → GitHub Pages 게시(§4) → 앱 설정에 처리방침 링크.
3. 운영: 숨김 심사 계정 A·B 생성(§5.1) · 루비 지급 · 두 계정으로 폰 e2e 한 바퀴(`ios/UITests/AingCheckE2ETests.swift`).
4. 스크린샷 6장(§6) → 알파 없음 확인.
5. App Store Connect: 앱 생성(번들 ID·SKU·기본 언어 ko) → §1 문안 → §2 라벨 → §3 설문 → §4 URL → §5 노트·데모 계정·연락처 → 빌드 선택(`MARKETING_VERSION` 을 `1.0.0` 으로 올릴지 결정 — 지금 `0.1.0`) → 제출.
6. 심사 통과 뒤: 숨김 계정은 두거나 절차 문서의 "정리" 로 삭제.
