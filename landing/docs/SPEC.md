> 거부된 v1(2026-10-12 15:50). v2 정본은 `docs/v2/`(SPEC·PLAN·DECISIONS). 이 문서의 SPEC §1.4 사실 규칙·§9 에셋 표, 그리고 `docs/v2/DECISIONS.md` §1 표에 적힌 v1 결정만 v2 가 승계한다.

# 아잉체크 랜딩 — 최종 스펙 (SPEC-final)

작성 2026-10-12 · 디자인 디렉터 겸 테크 리드 · **구현자가 보는 유일한 디자인 정본**(병렬 구현 계획은 `PLAN-files.md`)
뼈대: 디자인 안 A 「메뉴바가 페이지다」(심사 합산 1위 254점). 심사 3건의 mustFix 를 전부 반영하고, B·C 의 접목 중 '기억에 남을 하나'를 흐리지 않는 것만 들였다(§0.3).
소재 루트 표기: **`A/` = `/Users/yesung/aing-check-promo/public/assets/`**. 출력 루트 표기: **`P/` = `/Users/yesung/check/landing/public/`**(배포 URL 에서는 `/`). 모든 에셋의 두 경로 전체 목록은 §9.
사실 정본: `design/content-brief.md`(카피·금지 목록), `design/asset-manifest.md`(바이트 실측). 이 문서와 어긋나면 **이 문서가 이긴다**(브리프의 '택1' 후보는 여기서 모두 확정했다).

---

## 0. 한눈에

### 0.1 결정 요약

| 항목 | 결정 |
|---|---|
| 컨셉 | 브라우저 창 = 방문자의 맥 화면. 페이지 맨 위 띠의 오른쪽 끝에 **앱이 실제로 그리는 메뉴바 라벨**이 있고, 거기서 **진짜 팝오버 렌더**가 매달려 내려와 스크롤을 따라온다. 스크롤은 하루다: 출근 전(오프) → 근무 시작(00:00) → 시간이 흐름(01:00) → 한낮(03:45) → 퇴근(06:42 → 오프) |
| 기억에 남을 하나 | **메뉴바 라벨에 매달린 팝오버 스파인.** 라벨이 하루를 사는 동안 팝오버는 섹션마다 앱 레일 버튼을 누른 것처럼 패널을 바꾸고, 시간이 흐르는 구간에서는 라벨 속으로 접힌다. 대담함은 여기와 울트라 한 순간에만 쓴다 |
| 색 규칙 | 페이지는 네이비 무채색. **페이지의 손(누르는 것·포커스·링크)은 라벨 아잉의 라벤더 하나.** 민트(시작)·코랄(종료)·파랑(진행)은 앱 렌더 안에서만 나온다(예외: 렌더 위 핫스팟 호버 링 = 앱 파랑) |
| 글꼴 | 헤드라인 Pretendard ExtraBold(800) 페이지 글자 서브셋 · 본문 시스템 SF(0바이트) · brew 명령 한 줄만 JetBrains Mono |
| 움직임 | 사용자 동작에 대한 응답 + 로드 순간 하나(팝오버가 라벨 밑에서 한 번 내려옴) + 스크롤 scrub 하나(잔디 점등). 나머지 스크롤 효과는 '문턱'에서 상태를 한 번 바꾼다. 섹션 페이드업 없음 |
| 캐릭터 | 앱 사실 그대로 **근무 중일 때만** 화면 오른쪽 아래 구석에 아잉이 산다. 근무 시작(버튼)·자동 시작(스크롤)으로 폴짝 등장, 퇴근하면 꾸벅하고 사라진다. 캐릭터 움직임은 전부 앱 렌더 30fps 영상 |
| 사실 원칙 | 앱 렌더(@3x)만 쓰고 덧그리지 않는다. 렌더가 없는 상태는 보여 주지 않는다. 라벨 숫자도 렌더 이미지(00:00·01:00·03:45·06:42) 교체로만 바꾼다 |
| 다운로드 | 1차 CTA = DMG(`/api/download` → GitHub 최신 릴리스 302). 2026-10-12 실측: v0.3.47 에 `aing-check.dmg` 29,959,634B(= **30.0MB**)와 `aing-check.zip` 28,204,079B(= 28.2MB)가 있고 DMG 직링크가 200 이다 |
| 길이 | 데스크톱 1440×900 기준 **약 10뷰포트(문서 높이 9,000–9,600px, 상한 9,900px)** |
| 무게 | 첫 화면 ≤ 350KB(예상 ≈325KB, LCP = H1 텍스트) · 페이지 전체 ≤ 4.5MB(예상 ≈4.0MB 크롬) |

### 0.2 mustFix 반영표(심사 3건 → 이 문서의 위치)

| mustFix | 반영 |
|---|---|
| DMG 404 전제 삭제, 30.0MB, DMG 기본·zip 은 API 에 DMG 없을 때만, "경고 없이 열려요" 계속 금지, 릴리스 fetch 에 3초 타임아웃 | §4 S11, §6 `RELEASE_FALLBACK`, PLAN `lib/release.ts` |
| 아이폰 '나' 탭 `me` → `me_records`(서울 배지 회피) | §4 S9, §9 |
| `working-medium` 위젯 제거('부산' 2회) → 할 일 위젯 체크 + `today-small` | §4 S9 |
| 라벨 00:01 → 03:45 점프 설명 | §3.3 장면 모델 + §4 S2 시간 경과 박자(렌더만, 01:00 라벨 사용) + 14:05 시각 표식 |
| 스파인 구간 단축·리듬 변주, 같은 구도 3절 초과 금지, 데스크톱 ≈9–10뷰포트 | §4 순서표(S2 접힘, S6 큰 창, S9 폰, S10 타이포만이 사이에 끼움) |
| 메뉴바 띠의 가짜 데스크톱 위험 | 반투명 블러 36px 메뉴바 흉내 폐기 → **불투명 48px 일반 내비** + 오른쪽 끝 실제 라벨과 매달린 팝오버만 유지(§4 S0) |
| 울트라 길이·종료 | 사용자 v4 피드백("울트라는 2초 안팎으로 빠르게")을 따라 **72프레임(2.4초)만 재생**, 아무 입력(클릭·탭·Esc·키·휠·터치 스크롤)으로 즉시 종료(§4 S4, §3.4) |
| 고정 스파인 + fixed 핫스팟의 깨짐 | 조상 transform/filter/contain 금지, `visualViewport` 재계산, 렌더 교체 전 `img.decode()`, 줌 90/110/125% ±2pt 검사, 실패 시 섹션별 sticky 축소판(§10 R3) |
| 코너 아잉이 오른쪽 아래 UI 를 가림, 스파인과 겹침 | 스파인 열림 중 겹치면 스파인 왼쪽으로 이동, `data-companion-avoid` 회피, 숨기기 버튼(§4 공통 C) |
| webm GOP(키프레임 128프레임 간격) | idle 은 `-g 30` 으로 다시 인코딩 + 반응 시작 순간 미리 시크(§9, §3.4) |
| 상태 기계 검증 | 순수 리듀서 + `node --test` 단위 테스트(PLAN) |
| 주 버튼이 흔한 흰 알약 | 라벤더 채움 + 밤색 글자(§2.1) |

### 0.3 접목 — 들인 것 / 버린 것

| 출처 | 아이디어 | 판정 | 이유 |
|---|---|---|---|
| C(+엔지니어 변형) | 히어로 꼬리의 시간 경과(01:00 색종이, 3시간 루비 +3) | **들임** — 라벨은 렌더 `0100`·`0345` 교체만, 숫자 합성 없음 | 점프를 앱 사실로 설명한다. 렌더만 써서 사용자 확인이 필요 없다 |
| C | "팝오버는 헤더 값이 라벨과 같을 때만 보이고 시간이 흐르는 동안 닫힌다" 불변식 | **들임** | 라벨과 렌더가 한 화면에서 어긋나지 않는다. 스파인이 접혔다 펴지며 리듬도 생긴다 |
| C | 하루 시각 표식(14:05 · 17:02) | **들임** — 키커가 아니라 데스크톱 왼쪽 여백(거터)에 매단 타임스탬프 | 정보이고, 시간이 실제로 바뀌는 두 곳에만 |
| C | 처음 오프 → 00:00 이 될 때 라벨 밑 민트 번짐 600ms 1회 | **들임** | 사용자 동작의 결과를 22px 라벨에서 놓치지 않게 |
| C | FAQPage JSON-LD + `#faq-N` 딥링크 | **들임** | 비용 0 |
| B | 라벤더 주 버튼(#C9B8FF + #14102A) | **들임** | 가족 신호를 페이지의 손에 싣고 흰 알약 기본값을 피한다 |
| B | 내비 CTA: 테두리 → 히어로 CTA 가 화면 밖이면 채움 | **들임** | 첫 화면에서 주 버튼 둘이 경쟁하지 않는다 |
| B | 클로징을 17:02 로 닫기(라벨 06:42 → 오프 → [다시 근무 시작] 06:42) | **들임(변형)** — 확대한 실제 라벨 렌더 + 퇴근 뒤 `header_off_1702` 의 진짜 [근무 시작] 핫스팟으로 재시작 | 하루가 장부대로 닫히고 "오늘 총합에서 이어진다"를 렌더로 증명. HTML 코랄 버튼 흉내는 쓰지 않는다 |
| B | 콕 목록의 [집중] 칩 핫스팟(목록 → 1단 → 2단 순환) | **들임** | 캡션 없이 손으로 증명 |
| B | 위젯 할 일 체크(체크 전·후 렌더 교체) | **들임** | '부산' 위젯을 대신하고 사실을 상호작용으로 |
| B | 릴리스 표기(10진 MB, DMG 우선) | **들임** | |
| 엔지니어 | 코너 아잉 회피 + 숨기기 | **들임**(부르기 알약은 버림) | 숨긴 뒤에도 콕을 받으면 잠깐 나타나는 앱 사실로 돌아온다 |
| 엔지니어 | 순수 리듀서 + 단위 테스트, idle 짧은 GOP | **들임** | |
| B | 첫 페인트의 마스코트 아잉(마침표 위) | 버림 | 앱은 근무 중에만 캐릭터를 띄운다(앱에 없는 상태). 대신 **첫 스크롤에서 자동 시작으로 아잉이 반드시 등장**한다(§4 S2) |
| B | Hahmlet 세리프, 커서 시선, 입혀 보기, 동행 비행, 3초 꾹 | 버림 | 앱 글자(SF)와 다른 목소리 / 앱에 없는 트리거 / 모션 체계 과밀 |
| C | 숫자 합성 라벨(아이콘 렌더 + SF 숫자 굴림) | 버림 | 렌더 교체 계단으로 충분하고 '렌더만' 원칙을 지킨다 |
| C | 3D 맥북, 빛 장치, 스크롤 자동 울트라, DMG 클릭 = 근무 시작 | 버림 | 가짜 데스크톱·템플릿 제품샷 / 성능 / 강요된 연출 / 지어낸 의미 |
| A | 36px 반투명 블러 메뉴바 흉내, 메뉴 항목 r5 하이라이트 | 버림 | 가짜 데스크톱 금지선 |
| A | 설정 '공개' 스위치 크롭, 캐릭터 절의 루비 반응 | 버림 / 이동 | 길이 단축·센터 행 위험 / 루비는 시간 경과 박자로 옮김 |
| aingo | 점구름 아잉, 오로라 셰이더, 별밭 순환, 스토어 선택 모달, 모노 대문자 키커, 01/02/03 | 버림 | aingo 의 서명 + 캐릭터 생성 금지 + 템플릿 크롬 |
| 소재 | 소개 영상(`out/v4/aing-check-v4.mp4`) | v1 미포함 | 진짜 UI 가 이미 움직이고, 음원 라이선스 확인 전이다 |

---

## 1. 컨셉과 원칙

### 1.1 한 문단
아잉체크는 화면 맨 위 상단바에 사는 앱이다. 그래서 이 페이지도 상단바에서 시작한다. 내비 띠 오른쪽 끝에는 앱이 실제로 그리는 메뉴바 라벨(시무룩한 아잉 + "오프")이 있고, 그 밑에 진짜 팝오버 렌더가 매달려 있다. 렌더 속 [근무 시작]을 누르면 앱에서 일어나는 일이 그대로 일어난다. 라벨이 00:00 이 되고, 팝오버의 초가 흐르고, "4명 근무중"이 "5명 근무중"이 되고, 화면 오른쪽 아래 구석에 아잉이 폴짝 들어와 "오늘도 화이팅!" 한다. 누르지 않고 스크롤만 해도 앱처럼 "일하는 것 같아서 근무 시작했어요!" 하며 대신 켜진다. 팝오버가 라벨 속으로 접히고 라벨이 01:00 이 되면 아잉이 색종이를 뿌리고, 03:45 가 되면 루비를 받는다. 한낮부터 팝오버는 다시 내려와 섹션마다 앱 레일 버튼을 누른 것처럼 팀 현황·콕·메시지·캐릭터·내 기록 패널로 바뀌고, 섹션마다 한 번의 상호작용이 있다. 쉬는 시간과 아이폰 절에서는 팝오버가 접히고 게임 창과 폰이 자리를 이어받는다. 마지막에 확대된 라벨이 06:42 를 가리키고, [근무 종료]를 누르면 아잉이 꾸벅 인사하고 사라진다. 남는 것은 "메뉴바에, 아잉 하나." 와 다운로드 버튼이다.

### 1.2 기억에 남을 하나 — 규칙
- 라벨·팝오버는 물리적으로 붙어 있다: 팝오버 오른쪽 끝 = 띠 오른쪽 여백 16px(라벨 오른쪽 끝), 팝오버 윗변 = 띠 아랫변 + 6px.
- 라벨 교체는 애니메이션 없이 **즉시**(macOS 메뉴바가 그렇듯). 정밀함이 곧 연출이다.
- 팝오버 패널 교체는 같은 창 안 내용 변화라 위 판 불투명도만 180ms 선형으로 교차, 창 높이는 200ms ease-out 으로 맞춘다.

### 1.3 절제 원칙(구현자가 매번 확인)
1. 페이지 크롬은 네이비 무채색 + 라벤더 손 하나. 민트·코랄·파랑은 렌더 안에서만(핫스팟 호버 링만 예외로 앱 파랑).
2. 움직임은 응답이다. 예외는 셋: 로드 때 팝오버 내려옴 1회, 1.2초 뒤 [근무 시작] 링 맥동 1회, 섹션 진입 때 앱이 실제로 하는 '받는 사건'(자동 시작·콕 받음·메시지 도착·1시간·루비) 각 1회.
3. 캐릭터 동작은 앱 렌더 영상 30fps 그대로. 캐릭터에 CSS 확대·회전·튀기기를 얹지 않는다.
4. 불투명도는 언제나 선형. 이동·크기는 ease-out(들어올 때)/ease-in(나갈 때). 둘을 같은 커브로 깎지 않는다.
5. 장식 없음: 그라디언트 워시·글로우 덩어리·노이즈·별밭·유리 카드·섹션 카드 없음. 그림자는 '창'(팝오버·게임 창·할 일 보드·폰·헤더 카드)에만.
6. 설명 캡션 없음: 규칙·수치 캡션("10분 안에 5분"류)과 "눌러 보세요" 안내 금지. 누를 수 있는 것은 커서·호버 링·포커스 링으로 말한다.
7. 템플릿 크롬 없음: 키커·대문자 라벨·가운뎃점으로 이은 메타 줄·버튼 끝 화살표·순서 아닌 목록의 번호 없음(번호는 설치 단계·팀 참여처럼 진짜 순서에만). 산문 속 나열의 가운뎃점(예: "Apple Silicon·Intel")은 한국어 문장 부호라 허용한다.
8. 한 뷰포트 안에 서로 어긋나는 가상 수치를 함께 보이지 않는다(팀 행 합 vs 리그 총합 → 같은 자리 교체로만, 맥 회고 42:50 vs 폰 회고 40:30 → 다른 절).

### 1.4 사실 규칙(어기면 반려)
- 인물은 v4 가상 세트만: 새벽(나·아잉) / 아잉 데모팀 = 구름빵(해파리)·달토끼(여우)·민트별(아잉)·호두과자(시바) / 다른 팀 = 보리차(다람쥐)·솜사탕(유령)·초코칩(유령). 실사용자 이름·수치 0.
- 렌더를 고치거나 숫자를 덧그리지 않는다(크롭만). 렌더 속 '9월'·'9월 17일'은 데모 날짜로 둔다. HTML 문구에는 달 이름을 쓰지 않는다.
- 쓰지 않는 말: 오픈소스(→ "코드가 공개돼 있어요"), 판돈·베팅·걸고(→ 대결·1:1), 울찌(→ 울트라), 서울·부산·소마·SW마에스트로, 제공자 로고(이름은 글자로만), 전역 단축키, 열품타, "경고 없이 열려요"(DMG 서명·공증·스테이플 확인 전), "확인 메일·이메일 인증", 별점·사용자 수, 캐릭터 수 '일곱'.
- 제품명 **아잉체크**(붙여 씀). 명령·파일명 자리에만 **aing-check**. 처음 한 번만 "아잉체크(aing-check)"(푸터 한 줄). 산문은 '근무 중', 앱 칩 인용만 '근무중'. 버튼 이름 '근무 시작'/'근무 종료'. 팀 열쇠는 '팀 코드'. 공식 이름 '울트라'.
- 쓰지 않는 소재: `A/v4/char/aing/angle_top`, `A/v4/intro/**`, `A/v3/gen/**`, `A/v4/phone3d/**`, `A/v3/mockup/**`, `A/v4/laptop/**`, `A/v4/appstore/screenshot_*`, `A/v4/mac/ui/**/*_goal_done_*`, `*banner_retro*`, 9줄 미니게임 판(`minigame_window_flappy_playing@3x.png`·`_ready`), `A/v4/ios/screens/me_dark@3x.png`, `A/v4/ios/widgets/promo_working-*`, `A/v3/brand/qr-appstore.svg`(지역 코드 `/kr/`), `out/v4/thumbnail*.png`.
- 로봇 그림 없음(렌더 없음). AI 리밋·테트리스·체스 화면 없음(렌더 없음) → 글로만.

### 1.5 aingo 에서 빌린 것 / 달리한 것
| 빌림 | 달리함 |
|---|---|
| 마침표 헤드라인, 쉼표 두 박자(한두 번) | 히어로 장치: 점구름 대신 **앱 렌더 팝오버 + 앱 리액션 영상** |
| H1·첫 CTA 는 SSR 부터 보이게(aingo 의 opacity:0 히어로는 반면교사) | 300vh 스티키 폰 대신 **스파인**(섹션 자체가 내용이라 빈 스크롤 없음) |
| FAQ 아코디언의 조용한 문법 → 네이티브 `<details name>` | 보라 바탕·보라 CTA 대신 **네이비 + 라벤더 손**(아이콘 바탕 #131026 과 aingo #0b0818 은 이미 같은 밤) |
| 라벤더 포커스 링(가족 신호) | IBM Plex 대신 **Pretendard 800 + 시스템 SF**(앱 글자와 페이지 글자를 한 면으로) |
| 성능 규율: 보일 때만 재생, 감속 모션은 정지 한 장, 무거운 것은 load 뒤 idle 에서 | 스토어 선택 모달 대신 **DMG 직링크** + 누른 뒤 설치 안내로 바뀌는 자리(Arc 패턴) |
| iOS Smart App Banner 메타 | 마지막 화면: 별밭 순환 대신 **퇴근 꾸벅 한 번** |

---

## 2. 디자인 토큰

### 2.1 색 (CSS 변수 이름 확정)

| 변수 | 값 | 용도 | 대비(실측) |
|---|---|---|---|
| `--bg-0` | **#12131C** | 페이지 바탕, `theme-color`, 내비 띠 바탕 | — |
| `--bg-1` | #1A1C29 | 설치 절 띠 하나(행동 구역). 경계는 선 없이 바탕 차이로만(수리 단계: #171925 는 bg-0 대비 1.059·ΔL* 3 으로 저휘도 화면에서 사라졌다 → 1.094·ΔL* 4.5) | bg-0 대비 1.094 · ink-3 4.9 |
| `--surface` | #1F2230 | 페이지가 직접 그리는 면: brew 명령 상자, 세그먼트 트랙, FAQ 열린 행 바탕 | — |
| `--surface-2` | #2B2E3D | 선택된 세그먼트 알약, 눌림. 앱 카드색과 같은 값 | — |
| `--line` | rgba(255,255,255,.08) | 헤어라인: 내비 아랫변, FAQ 행 사이, 푸터 윗변 | — |
| `--line-strong` | rgba(255,255,255,.16) | 보조 버튼 테두리, 세그먼트 바깥선 | — |
| `--ink-1` | **#F2F3F7** | 헤드라인·강조 | bg-0 16.7 · surface 14.2 · surface-2 12.1 |
| `--ink-2` | #B4B7C5 | 리드·본문 | bg-0 9.3 · surface 7.9 · surface-2 6.7 |
| `--ink-3` | #868A9C | 메타·법적·시각 표식. **surface-2 위 금지**(3.9) | bg-0 5.4 · bg-1 4.9 · surface 4.6 |
| `--aing` | **#C9B8FF** | 주 버튼 채움, 내비 CTA 테두리·글자, 텍스트 링크, 포커스 링, `::selection` 바탕(30%) | bg-0 10.4 · bg-1 9.5 |
| `--aing-hover` | #D8CCFF | 주 버튼 호버 | — |
| `--on-aing` | #14102A | 라벤더 위 글자 | on aing 10.4 · on hover 12.3 |
| `--hotspot` | #54ABFF | 렌더 위 핫스팟 호버 링(70%), 맥동 링 | 팝오버 바탕 대비 6.5 |
| `--app-mint` | #59E0A1 | 페이지에서 칠하지 않음(참조값). 라벨 첫 시작 번짐 rgba(78,211,149,.35) 한 곳 | — |
| `--app-coral-a` / `--app-coral-b` | #FD9952 / #F76763 | 참조값(렌더 속 [근무 종료]). 페이지에서 쓰지 않음 | — |
| `--scrim-sheet` | rgba(8,9,14,.56) | 폰 모드 할 일 시트 뒤 깔개 하나 | — |

역할: 라벤더 = 아잉 = 페이지의 손. 민트 = 시작·근무 중(렌더). 코랄 = 종료(렌더). 파랑 = 진행·선택(렌더, 핫스팟 링).
주 버튼이 민트가 아닌 이유: 히어로에서 렌더 속 [근무 시작](민트)과 페이지 다운로드 버튼이 나란히 보인다. 둘 다 민트면 무엇이 앱이고 무엇이 페이지인지 흐려진다.

### 2.2 글꼴

| 역할 | 글꼴 | 로딩 |
|---|---|---|
| H1·H2·H3·FAQ 질문·숫자 표식 아닌 헤드라인 전부 | **Pretendard ExtraBold 800** (원본 `/Users/yesung/aing-check-promo/public/fonts/Pretendard-ExtraBold.woff2`, OFL) | 페이지 글자 서브셋 `P/fonts/pretendard-800-sub.woff2`(≈55–70KB), `next/font/local`, `display: 'swap'`, `preload: true`, 변수 `--font-display` |
| 본문·리드·버튼·내비·시각 표식 | 시스템: `-apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", system-ui, "Malgun Gothic", "Noto Sans KR", sans-serif` | 0바이트(앱이 쓰는 SF + Apple SD Gothic Neo) |
| brew 명령 한 줄 | **JetBrains Mono Regular 400** (원본 `/Users/yesung/aing-check-promo/public/fonts/JetBrainsMono-Regular.woff2`, OFL) | ASCII 서브셋 `P/fonts/jbm-400-ascii.woff2`(≈15KB), preload 안 함, 변수 `--font-code` |
| 코너 아잉 몸통 근무 시간 캡슐 | `ui-monospace, "SF Mono", Menlo, monospace` 600 | 0바이트(앱 코드 `.system(.caption, design: .monospaced).weight(.semibold)`) |

- 전역: `word-break: keep-all; overflow-wrap: anywhere;` 헤드라인 `text-wrap: balance`, 본문 `text-wrap: pretty`, 숫자 자리 `font-variant-numeric: tabular-nums`. 헤드라인 굵기 상한 800. 이탤릭·낱말 하나 색/굵기 강조 없음.

### 2.3 타입 스케일(390 → 1440 선형 clamp)

| 토큰(클래스) | 크기 | 행간 | 자간 | 굵기·글꼴 | 쓰는 곳 |
|---|---|---|---|---|---|
| `t-display` | clamp(40px, 6.1vw, 88px) | 1.04 | −0.04em | 800 Pretendard | H1 |
| `t-closing` | clamp(40px, 5.6vw, 80px) | 1.04 | −0.04em | 800 Pretendard | 클로징 H2 |
| `t-h2` | clamp(32px, 4.0vw, 58px) | 1.08 | −0.035em | 800 Pretendard | 섹션 H2 |
| `t-h2-solo` | clamp(56px, 8vw, 112px) | 1.0 | −0.045em | 800 Pretendard | "콕." 하나 |
| `t-h3` | clamp(22px, 2.0vw, 28px) | 1.25 | −0.02em | 800 Pretendard | 섹션 안 두 번째 박자 |
| `t-statement` | clamp(24px, 2.6vw, 36px) | 1.35 | −0.02em | 600 시스템 | 안심 절 큰 문장 |
| `t-lead` | clamp(17px, 1.35vw, 20px) | 1.6 | −0.005em | 400 시스템 | 헤드라인 아래 첫 문단 |
| `t-body` | 17px(phone 16px) | 1.7 | 0 | 400 시스템 | 본문 |
| `t-small` | 14px | 1.55 | 0 | 400 시스템 | 메타·작은 줄 |
| `t-micro` | 13px | 1.5 | 0 | 400 시스템 | 푸터·법적 |
| `t-time` | 13px | 1 | 0.02em | 600 시스템 tabular | 시각 표식 14:05·17:02 |
| `t-nav` | 14px | 1 | 0 | 500 시스템(워드마크 15px 700) | 내비 |
| `t-button` | 16px | 1 | −0.005em | 600 시스템 | 주 버튼(높이 48) |
| `t-button-s` | 14px | 1 | 0 | 600 시스템 | 보조·세그먼트·복사·내비 CTA |
| `t-faq-q` | clamp(18px, 1.6vw, 21px) | 1.4 | −0.015em | 800 Pretendard | FAQ 질문 |
| `t-code` | 15px(phone 13.5px) | 1.5 | 0 | 400 JetBrains Mono | brew 명령 |

글줄: 본문·리드 `max-width: 36em`, 헤드라인 `max-width: 13em`(H1 은 줄바꿈 고정).

### 2.4 간격 · 그리드 · 최대 폭
- 간격 단위 4px: `4 8 12 16 20 24 28 32 40 48 56 64 72 96 112 128`.
- 그리드 12열, 거터 24. 바깥 여백 `--gutter`: **80px(≥1280) / 48px(1024–1279) / 32px(768–1023) / 20px(<768)**. 셸 최대 폭 1440, 글줄은 따로 제한.
- **띠 여백 `--edge` = 16px**: 내비 항목과 스파인(팝오버)·라벨은 화면 가장자리 16px 에 붙는다. 본문 글은 그리드 여백(80px)에 붙는다. 이 어긋남이 의도다(앱은 화면 가장자리에, 글은 지면에).
- 섹션 세로: 스파인 섹션 `min-height: 72svh`, 내용은 세로 가운데, 위아래 패딩 96(desk)/80(tab)/64(phone). 일반 섹션 위아래 패딩 **112(desk) / 96(tab) / 72(phone)**.
- 묶음 간격: 시각 표식 → H2 0(거터에 매달림, phone 은 8), H2 → 리드 20, 리드 → 본문 16, 본문 → 컨트롤 28, 두 번째 박자(H3) 앞 56, 컨트롤 → 인라인 렌더 32.
- 데스크톱 글 열: 왼쪽 그리드 여백에서 시작, 최대 폭 600px(헤드라인 720px). 스파인과 최소 48px 떨어진다(1024 폭에서 글 열 폭 ≈498px).

### 2.5 반지름(물체의 정체가 정한다)
| 물체 | 값 | 변수 |
|---|---|---|
| 라벨 호버·열림 하이라이트(macOS 상태 항목) | 5px | `--r-label` |
| 내비 링크 호버 면 | 8px | `--r-nav` |
| '창'(팝오버, 게임 창, 할 일 보드, 헤더 카드) | 12px | `--r-window` |
| 세그먼트 바깥 / 안쪽 알약 | 10px / 8px | `--r-seg` / `--r-seg-in` |
| brew 명령 상자 | 10px | `--r-code` |
| 버튼(주·보조·내비 CTA) | 999px | `--r-pill` |
| 잔디 툴팁 | 8px | `--r-tip` |
| QR 바탕 타일 | 12px | `--r-window` |
| 핫스팟 링 | 대상 모양: 캡슐 = 높이/2, 레일 버튼 = 15pt×배율, 원 = 50% | — |
| 폰 셸 | 화면 반경 0.155·W, 바깥 = 화면 반경 + 베젤 0.035·W | — |
| FAQ 행·섹션·이미지 아닌 면 | 0 | — |

### 2.6 그림자 · 광원
- 광원은 위(라벨) 하나. 그림자는 아래로만.
- `--shadow-window: 0 0 0 1px rgba(255,255,255,.07), 0 24px 48px -12px rgba(0,0,0,.55), 0 8px 16px -8px rgba(0,0,0,.40);` 첫 겹은 창 바깥 헤어라인(바탕과 렌더 대비 1.1:1 을 가른다). 창에만 쓴다.
- 폰 셸: 바깥 1px rgba(255,255,255,.10) + 안쪽 1px rgba(255,255,255,.06) + `--shadow-window`.
- 버튼·세그먼트·명령 상자·텍스트에는 그림자 없음. 렌더에 구워진 앱 버튼 빛은 그대로.

### 2.7 모션 토큰
| 변수 | 값 | 쓰는 곳 |
|---|---|---|
| `--t-instant` | 0ms | 라벨 교체, 틱 칸 교체, 같은 판 위 숫자만 바뀌는 렌더 교체(근무 시작·찌르기 쿨타임) |
| `--t-quick` | 120ms | 불투명도 들고 남(선형), 버튼 눌림, 같은 창 안 메시지 판 교체 |
| `--t-base` | 180ms | 스파인 패널 교차(선형), 스파인 열림 이동, 세그먼트 알약 이동 |
| `--t-resize` | 200ms | 창 높이 맞춤, 내비 CTA 채움 전환(색, 선형) |
| `--t-overlay` | 220ms | 할 일 보드 열림, 폰 시트 |
| `--t-move` | 240ms | 코너 아잉 자리 이동·회피 |
| `--ease-out` | cubic-bezier(.2,.8,.2,1) | 이동·크기 들어올 때 |
| `--ease-in` | cubic-bezier(.4,0,1,1) | 이동·크기 나갈 때 |
| 불투명도 | linear | 언제나 |
| 캐릭터 | 영상 30fps(phone·`deviceMemory ≤ 4` 의 idle 만 15fps. Save-Data 는 감속 모션처럼 포스터만 — 수리 단계 P-7, PLAN §3.2·코드에 맞춤) | 이징 없음 |
| 말풍선 | 등장: 불투명 0→1 120ms 선형 + scale .96→1 200ms ease-out(origin 왼쪽 아래) / 퇴장: 1→0 160ms 선형 | 지속 시간은 앱 값(§3.5) |

스크롤 규칙: scrub 은 **잔디 점등 하나**. 나머지는 문턱(IntersectionObserver·중앙선 통과)으로 상태를 한 번 바꾸고 전이는 위 토큰으로. 스크롤 하이재킹·스냅·관성 조작 금지.

감속 모션(`prefers-reduced-motion: reduce`): 로드 내려옴·맥동·라벨 번짐 없음, 패널 교체·높이·말풍선은 불투명 120ms 선형만, **캐릭터 영상 요청 0건**(포스터만, 반응은 말풍선만), 울트라는 포스터 + 말풍선 3초(아무 입력으로 닫힘), 잔디는 처음부터 최종 판. 하이드레이션 어긋남 방지: 서버는 감속 여부를 모른다 → `initial` 값을 가르지 말고 전이 시간을 0 으로. CSS 키프레임은 `@media (prefers-reduced-motion: no-preference)` 안에서만 선언.

### 2.8 CSS 변수와 Tailwind v4 연결(`app/globals.css` 그대로)

```css
@import "tailwindcss";

@custom-variant desk (@media (min-width: 1024px) and (min-height: 640px));
@custom-variant tab (@media (min-width: 768px) and ((max-width: 1023.98px) or (max-height: 639.98px)));
@custom-variant phone (@media (max-width: 767.98px));

:root {
  --bg-0:#12131C; --bg-1:#1A1C29; --surface:#1F2230; --surface-2:#2B2E3D;
  --line:rgba(255,255,255,.08); --line-strong:rgba(255,255,255,.16);
  --ink-1:#F2F3F7; --ink-2:#B4B7C5; --ink-3:#868A9C;
  --aing:#C9B8FF; --aing-hover:#D8CCFF; --on-aing:#14102A;
  --hotspot:#54ABFF; --app-mint:#59E0A1; --app-coral-a:#FD9952; --app-coral-b:#F76763;
  --scrim-sheet:rgba(8,9,14,.56);
  --shadow-window:0 0 0 1px rgba(255,255,255,.07),0 24px 48px -12px rgba(0,0,0,.55),0 8px 16px -8px rgba(0,0,0,.40);
  --r-label:5px; --r-nav:8px; --r-window:12px; --r-seg:10px; --r-seg-in:8px; --r-code:10px; --r-pill:999px; --r-tip:8px;
  --t-quick:120ms; --t-base:180ms; --t-resize:200ms; --t-overlay:220ms; --t-move:240ms;
  --ease-out:cubic-bezier(.2,.8,.2,1); --ease-in:cubic-bezier(.4,0,1,1);
  --nav-h:48px; --spine-gap:6px; --edge:16px; --gutter:20px;
  --z-spine:40; --z-nav:50; --z-corner:60; --z-board:70; --z-ultra:90;
}
@media (min-width:768px){ :root{ --gutter:32px; } }
@media (min-width:1024px){ :root{ --gutter:48px; } }
@media (min-width:1280px){ :root{ --gutter:80px; } }

@theme inline {
  --color-bg-0: var(--bg-0); --color-bg-1: var(--bg-1);
  --color-surface: var(--surface); --color-surface-2: var(--surface-2);
  --color-line: var(--line); --color-line-strong: var(--line-strong);
  --color-ink-1: var(--ink-1); --color-ink-2: var(--ink-2); --color-ink-3: var(--ink-3);
  --color-aing: var(--aing); --color-aing-hover: var(--aing-hover); --color-on-aing: var(--on-aing);
  --color-hotspot: var(--hotspot);
  --font-display: var(--font-pretendard), -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", system-ui, sans-serif;
  --font-sans: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", system-ui, "Malgun Gothic", "Noto Sans KR", sans-serif;
  --font-code: var(--font-jbm), ui-monospace, "SF Mono", Menlo, monospace;
  --radius-window: var(--r-window); --radius-pill: var(--r-pill);
}

html { background:var(--bg-0); color:var(--ink-1); color-scheme:dark; font-family:var(--font-sans);
       word-break:keep-all; overflow-wrap:anywhere; -webkit-font-smoothing:antialiased; scroll-padding-top:calc(var(--nav-h) + 24px); }
@media (prefers-reduced-motion: no-preference) { html { scroll-behavior:smooth; } }
:focus-visible { outline:2px solid var(--aing); outline-offset:2px; }
.btn-primary:focus-visible { outline-offset:3px; }
::selection { background:rgba(201,184,255,.30); }
```
`.t-*` 타입 클래스 14개는 §2.3 값 그대로 `@layer components` 에 정의한다(PLAN). JS 판정 상수는 같은 문자열을 `lib/hooks.ts` 의 `MQ_DESK / MQ_TAB / MQ_PHONE` 로 공유한다.

---

## 3. 데모 상태 기계 (모든 섹션이 공유 — 섹션 명세보다 먼저 읽을 것)

페이지 전체에 상태 하나가 흐른다. 라벨·스파인·코너 아잉·인라인 무대는 이 상태를 **그리기만** 한다. 구현: 외부 의존성 없는 순수 리듀서(`lib/demo/reducer.ts`) + `useSyncExternalStore` 스토어(`lib/demo/store.ts`, 타이머·부수효과는 여기에만).

### 3.1 상태
```ts
type Work = 'off' | 'on' | 'ended';
type SectionId = 'hero'|'auto'|'team'|'poke'|'message'|'games'|'character'|'records'|'iphone'|'trust'|'install'|'faq'|'closing';
type Scene = 'am' | 'hour1' | 'noon' | 'evening';           // 파생값(저장하지 않음, §3.3)
type Reaction = 'commute_start'|'commute_end'|'poked'|'message_received'|'milestone'|'ultra_charged';
type BubbleId = 'commute-start'|'autostart'|'poked-mint'|'message-gureum'|'commute-end'|'ruby';

interface DemoState {
  work: Work;
  startedBy: 'button'|'auto'|'jump'|'restart'|null;
  startedAt: number|null;                 // performance.now(), 틱 계산용
  activeSection: SectionId;               // 뷰포트 중앙 띠(-45% / -45%)에 걸린 섹션 또는 focusin 섹션
  activeBeat: string|null;                // 섹션 안 두 번째 박자(예: 'records:tokens')
  autoPassed: 0|1|2;                      // S2 중앙선 표지 두 개 중 지나간 개수
  spine: { userClosed: boolean; rect: {x:number;y:number;w:number;h:number;scale:number}|null };
  labelPopoverOpen: boolean;              // 스파인 없는 섹션에서 라벨을 눌러 연 정지 팝오버
  team: 'members'|'league';
  poke: 'list'|'cooldown';
  focus: 0|1|2;
  message: 'none'|'arrived'|'composing'|'unread'|'read';
  games: 'flappy'|'gomoku'|null;          // null = 모드 기본값(phone 은 gomoku, 그 밖은 flappy)
  grass: 'work'|'token';
  tokens: 'month'|'last';
  phone: 'now'|'messages'|'rankings'|'games'|'me';
  widgetChecked: boolean;
  corner: { hidden: boolean; reaction: {id:Reaction; nonce:number; at:number}|null; bubble: {id:BubbleId; nonce:number}|null; pending: Reaction|null };
  ultra: 'idle'|'waiting'|'playing';
  todoOpen: boolean;
  installHint: boolean;                   // 다운로드를 한 번 눌렀다(sessionStorage 'aing:installHint')
  once: { autostart:boolean; milestone:boolean; ruby:boolean; pokeIn:boolean; ultra:boolean; message:boolean; startGlow:boolean };
  announce: { text:string; nonce:number }|null;
}
```
초기값: work 'off', activeSection 'hero', autoPassed 0, 나머지는 첫 값(team 'members', poke 'list', focus 0, message 'none', games null, grass 'work', tokens 'month', phone 'now'), corner.hidden = sessionStorage 'aing:hidden' === '1'.

### 3.2 이벤트와 전이(리듀서 액션 = 스토어 메서드)

| 메서드 | 조건 | 전이 | 화면 결과 |
|---|---|---|---|
| `pressStart()` 히어로 [근무 시작] 핫스팟 | work=off | work=on, startedBy=button, startedAt=now | 라벨 00:00(+첫 번짐) · 팝오버 popover-on + 틱 · 반응 commute_start + 말풍선 commute-start · 알림 "근무를 시작했어요. 오늘도 화이팅!" |
| `autoStart()` S2 50% 보임 + 700ms, 또는 work=off 로 표지1 통과 | work=off, once.autostart=false | work=on, startedBy=auto | 반응 commute_start + 말풍선 autostart · 알림 "일하는 것 같아서 근무 시작했어요!" |
| `setActiveSection(id)` SectionShell IO·focusin | — | activeSection=id, activeBeat=null. 파생 장면이 hour1/noon/evening 인데 work=off → work=on, startedBy=jump(반응·말풍선 없음, 코너는 120ms 페이드인). work=ended 이고 id≠closing → work=on, startedBy=restart(조용히 되감기). 라벨 팝오버 닫힘 | 라벨·스파인이 장면대로 |
| `setActiveBeat(beat\|null)` Beat IO | — | activeBeat | 스파인 패널 교체 |
| `setAutoPassed(n)` S2 표지 | — | autoPassed=n. 앞으로 지날 때 400ms 머물면: 0→1 은 work=off 면 autoStart 하고 milestone 을 대기열(pending)에, 아니면 once.milestone=false 일 때 반응 milestone. 1→2 는 once.ruby=false 일 때 반응 ultra_charged + 말풍선 ruby | 라벨 01:00 / 03:45 |
| `toggleSpine()` 데스크톱 라벨 클릭(스파인 섹션) | — | spine.userClosed 반전 | 팝오버 접힘/펼침 |
| `toggleLabelPopover()` 라벨 클릭(스파인 없는 섹션) | labelPanel(state)≠null | labelPopoverOpen 반전. 열 때 todoOpen=false(라벨 팝오버와 할 일 보드는 동시에 열리지 않는다 — 스파인 섹션에서 보드가 열린 채 라벨을 누르면 보드를 닫고 스파인을 여는 것과 같은 규칙) | 정지 팝오버 |
| `setSpineRect(r)` Spine 이 게시 | — | spine.rect | 핫스팟 정렬 |
| `setTeam(v)` · `setGames(v)` · `setGrass(v)` · `setTokens(v)` · `setPhone(v)` | — | 해당 값, spine.userClosed=false | 렌더 교체 |
| `cycleFocus()` [집중] 칩 | — | focus 0→1→2→0, userClosed=false | poke-focus-1 / poke-focus-2 / 원래 판 · 알림 "집중 모드 1단"/"집중 모드 2단"/"집중 모드 꺼짐" |
| `pokeIn()` S4 50% + 1200ms | work=on, focus=0, once.pokeIn=false | once.pokeIn=true | 반응 poked + 말풍선 poked-mint(숨김 상태여도 잠깐 나타남) · 알림 "민트별님이 콕 찔렀어요!" |
| `pokeBack()` 민트별 찌르기 핫스팟 | poke=list, focus=0 | poke=cooldown · 1000ms 뒤 `ultraIn()` | 팝오버 poke-cooldown(0ms 교체) |
| `ultraIn()`(스토어 내부 단계 — pokeBack 이 부른다. 오버레이는 `ultraReady()`·`ultraDone()` 으로 알린다) | once.ultra=false | ultra=waiting → 영상 준비되면(최대 2500ms) playing, once.ultra=true | 울트라 오버레이 + "민트별님의 울트라 찌르기!" |
| `ultraDone()` 72프레임 끝·아무 입력 | ultra≠idle | ultra=idle | 오버레이 160ms 선형 퇴장 |
| `msgArrive()` S5 50% + 800ms | message=none | message=arrived | 라벨 03:45 빨간 점 · 팝오버 popover-newmsg · 반응 message_received + 말풍선 message-gureum |
| `msgOpen()` 레일 '콕 / 메시지' 핫스팟·말풍선·왼쪽 버튼 | message=arrived | message=composing, userClosed=false | 팝오버 message-composing · 라벨 점 지움 |
| `msgSend()` [보내기] 핫스팟·왼쪽 버튼 | message=composing | message=unread · 1600ms 뒤 read | message-unread → message-read(1 사라짐) · 알림 "보냈어요" → "구름빵님이 읽었어요" |
| `toggleTodo(force?)` 코너 몸통·S7 버튼 | work=on | todoOpen 반전(S7 버튼은 hidden 이면 hidden=false 로 되돌린 뒤 연다). 열 때 labelPopoverOpen=false(라벨 정지 팝오버를 닫는다 — toggleLabelPopover 와 짝) | 할 일 보드 |
| `toggleWidget()` 위젯 체크 핫스팟 | — | widgetChecked 반전 | 위젯 렌더 교체 |
| `hideCorner()` 코너 숨기기 버튼 | work=on | 반응 commute_end(말풍선 없음) 뒤 hidden=true(sessionStorage) | 코너 사라짐 |
| `pressEnd()` 클로징 [근무 종료] | work=on, activeSection=closing | work=ended | 반응 commute_end + 말풍선 commute-end → 끝나면 코너 언마운트 · 라벨 오프 · 헤더 카드 등장 · 알림 "근무를 마쳤어요. 수고했어!" |
| `restart()` 헤더 카드 [근무 시작] 핫스팟 | work=ended | work=on, startedBy=restart, hidden=false | 라벨 06:42 · 반응 commute_start + 말풍선 commute-start · 헤더 카드 접힘 · 알림 "다시 근무를 시작했어요." |
| `installClicked(placement)` Mac 다운로드 클릭 | — | installHint=true(sessionStorage) | 히어로 메타·설치 블록이 설치 안내로 |
| `reactionDone(nonce)` · `bubbleDone(nonce)` | nonce 일치 | 비움(pending 이 있으면 재생) | — |
| `announce(text)` | — | announce={text,nonce} | LiveAnnouncer 가 읽음 |

반응 큐: 새 반응은 앱처럼 현재 것을 끊고 재생한다. 단 현재 반응이 시작된 지 `TIMING.reactionMinGap`(1200ms) 미만이면 `pending` 하나에 넣었다가(가장 최근 것만) 그 시점에 재생한다. commute_end 는 끊지 않는다. 말풍선은 반응과 따로 산다(milestone 은 말풍선이 없으므로 직전 말풍선이 남는다).

### 3.3 장면 · 라벨 · 패널 매핑(파생 함수, `lib/demo/selectors.ts`)

**장면(scene)** — 스크롤 위치가 하루의 시각이다(양방향). 반응은 앞으로 갈 때 한 번만.
| activeSection | scene |
|---|---|
| hero | am |
| auto | autoPassed 0 → am · 1 → hour1 · 2 → noon |
| team · poke · message · games · character · records · iphone · trust · install · faq | noon |
| closing | evening |

**라벨 키 `labelKey(s)`** → 렌더 이미지(§9 `ui/menubar-*`), 표시 높이 22px(1pt)
| 조건 | 키 | 렌더 |
|---|---|---|
| work=off 또는 ended | `off` | 시무룩 아잉 + "오프"(61.5×22) |
| on · am | `0000` | 웃는 아잉 + 00:00(77.2×22) |
| on · hour1 | `0100` | 01:00 |
| on · noon · message=arrived · activeSection ∈ {message, games} | `0345-newmsg` | 03:45 + 빨간 점(앱이 NSImage 에 구운 배지). 수리 단계: 점 있는 판(popover-newmsg)이 보이는 절에서만 — 다른 절의 스파인 판 레일엔 점이 없어 같은 뷰포트에서 어긋났다(§1.3-8) |
| on · noon | `0345` | 03:45 |
| on · evening | `0642` | 06:42 |
캡슐(코너 아잉 몸통) 글자 = 라벨 키의 HH:MM(off 이면 캡슐 없음).

**스파인 섹션** = hero · team · poke · message · character · records. 나머지 섹션에서는 스파인이 라벨 속으로 접힌다(시간이 흐르거나 다른 창·폰이 자리를 잇는 구간).

**패널 `panelFor(section, beat, s)`** (pt 크기는 §6 `PANELS`)
| section | 조건 | 패널 키 |
|---|---|---|
| hero | off | `popover-off` |
| hero | on · am | `popover-on`(+ 틱 띠 겹침) |
| team | members / league | `popover-working` / `league` |
| poke | focus 1 / focus 2 | `poke-focus-1` / `poke-focus-2` |
| poke | focus 0 · list / cooldown | `poke-list` / `poke-cooldown` |
| message | none / arrived / composing / unread / read | `popover-working` / `popover-newmsg` / `message-composing` / `message-unread` / `message-read` |
| character | — | `character-pick` |
| records | beat≠'records:tokens' / beat='records:tokens' · month / last | `insights` / `token-month` / `token-last` |
| 그 밖 | — | null(스파인 접힘) |

`spineOpen(s, mode)` = mode=desk ∧ section∈스파인 섹션 ∧ ¬userClosed ∧ ¬todoOpen ∧ panelFor≠null. (수리 단계: 할 일 보드가 열린 동안 접힌다 — 보드(코너 왼쪽 위)와 포개지지 않게, macOS 팝오버가 다른 창을 누르면 닫히듯. 보드가 열린 채 라벨을 누르면 보드를 닫고 연다)
**불변식**: 팝오버 렌더 헤더 값과 라벨 값이 같을 때만 팝오버가 보인다(am=00:00, noon=03:45). hour1·evening 에는 맞는 팝오버 렌더가 없으므로 스파인 섹션이 그 장면에 걸리지 않게 장면표를 짰다.

**라벨 정지 팝오버 `labelPanel(s)`**(스파인 없는 섹션에서 라벨 클릭): ended → `popover-off-1702` · noon → `popover-working`(라벨이 `0345-newmsg` 이면 `popover-newmsg`) · am → off/on 판 · hour1 · evening&on → null(라벨 버튼 `aria-disabled="true"`, 커서 기본). 핫스팟 없음, Esc·바깥 클릭·160px 이상 스크롤로 닫힘.

### 3.4 캐릭터 재생 규칙(CharacterStage 공통)
- 층: ① idle 영상(루프) ② 반응 영상(평소 숨김) ③ 몸통 근무 시간 캡슐(HTML) ④ 말풍선. 상자 `overflow: visible`.
- 반응 시작: idle 일시정지 + **즉시 idle 을 `(N mod 432)/30`초로 미리 시크**(숨긴 채) → 반응 영상 0프레임부터 재생, idle 불투명 0. 반응 끝: idle 이 `seeked` 를 마쳤으면(최대 300ms 기다림) idle 보이고 재생, 반응 숨김. N = 반응 프레임 수.
- 반응 → 영상: commute_start=`aing-commute-start`(45) · commute_end=`aing-commute-end`(36, 끝나면 150ms 선형 페이드 후 언마운트) · poked·message_received=`aing-poked`(90) · milestone=`aing-milestone`(72, 상자가 넓다 — 오프셋 §6) · ultra_charged=`aing-ultra-charged`(102, 오프셋 §6).
- 영상 형식 고르기는 `<source>` 순서가 아니라 JS: `isWebKit = (/AppleWebKit/.test(ua) && !/Chrome|Chromium|Edg|OPR|Android/.test(ua)) || /iP(hone|ad|od)/.test(ua)` → `.mov`(HEVC 알파), 아니면 `.webm`(VP9 알파). `error` 면 포스터에 머문다.
- `muted playsinline`, idle 만 loop. 반응 영상은 근접 시 `preload="auto"` 로 받아 0프레임에 멈춰 둔다. 탭 숨김(`visibilitychange`)·울트라 중에는 idle 일시정지. iOS 저전력 autoplay 차단 시 포스터 그대로(재생 버튼 UI 없음).
- phone 모드·`deviceMemory ≤ 4` 이면 idle 은 15fps 판.
- 감속 모션·`navigator.connection.saveData`(`posterOnly`): 영상 src 를 붙이지 않는다. 반응은 말풍선만. (수리 단계 P-7: 문서끼리 어긋났다 — SPEC 은 Save-Data → 15fps, PLAN §3.2·구현은 포스터만. 데이터를 아끼겠다는 사용자 의사에 더 맞고 이미 검증된 경로라 PLAN·구현 쪽으로 맞춘다)

### 3.5 말풍선(앱 원문 · 앱 지속 시간)
| id | 문구 | 렌더(원본) | 지속 |
|---|---|---|---|
| commute-start | 오늘도 화이팅! | `A/v4/mac/ui/bubble/bubble_commute_start@8x.png` | 5000ms |
| autostart | 일하는 것 같아서 근무 시작했어요! | `…/bubble_autostart@8x.png` | 8000ms |
| poked-mint | 민트별님이 콕 찔렀어요! | `…/bubble_poked_mint@8x.png` | 6000ms |
| message-gureum | 구름빵님: 커피 한잔 해요 ☕️ | `…/bubble_message_gureum@8x.png` | 6000ms(누르면 msgOpen) |
| commute-end | 수고했어! | `…/bubble_commute_end@8x.png` | 2000ms |
| ruby | 루비 +3! | `A/v4/char/aing/_ui/bubble_00.png`(캔버스 층, bbox (323,981)–(948,1290)) | 3200ms |
| ultra-mint(오버레이 전용) | 민트별님의 울트라 찌르기! | `…/bubble_ultra_mint@8x.png` | 울트라와 함께 |
| update(설치 절 정지 그림) | 새 업데이트가 있어요! | `…/bubble_update@8x.png` | — |
배치: 말풍선 이미지는 알파 bbox(그림자 포함)로 잘라 낸 것이고, **좌상단 = 캔버스 (323, 981)** 이 앱 배치다(1줄·2줄 말풍선 모두 같은 좌상단, `A/v3/mac/char/_ui/bubble_*.png` 실측).

### 3.6 타이밍 상수(`TIMING`, §6)
autostartDelay 700 · passDwell 400 · pokeInDelay 1200 · ultraAfterPoke 1000 · ultraWaitMax 2500 · ultraFrames 72 · ultraFadeMs 160 · reducedUltraMs 3000 · msgArriveDelay 800 · readAfterSend 1600 · startPulseAt 1200 · reactionMinGap 1200 · copyResetMs 2000 · labelGlowMs 600.

### 3.7 하루 장부(렌더가 이미 이 순서로 맞춰져 있다 — 바꾸지 말 것)
- 10:20 출근 전: 오늘 00:00, 이번 주 19시간 38분(49%), 5명 중 4명 근무중.
- 10:20:00–11 근무 시작 직후: 헤더와 팀 다섯 행의 초가 1초씩(틱 12장, 11초에서 멈춤).
- (시간 경과) 01:00 → 1시간 색종이, 3시간 → 루비 +3.
- 14:05 한낮: 오늘 03:45, 이번 주 23시간 23분(58%), 5명 근무중.
- 17:02 퇴근: 06:42 → 근무종료 06:42, 이번 주 26시간 20분(66%), 3명 근무중.
- 쉬었다 재개하면 0 이 아니라 오늘 총합(06:42)에서 이어진다.

---

## 4. 페이지 구조와 섹션 명세

### 4.0 순서와 리듬(데스크톱 1440×900)

| # | 섹션(id) | 구도 | 스파인 | 높이(목표) |
|---|---|---|---|---|
| S0 | 내비 띠(전역) | 띠 48px | — | — |
| S1 | 히어로 `#top` | 글 왼쪽 + 라벨에 매달린 팝오버 | 열림 | 100svh − 112px |
| S2 | 깜빡해도, 알아서. `#auto` | 글 왼쪽, 오른쪽은 비고 구석에 아잉만 | **접힘**(시간이 흐름) | 76svh |
| S3 | 지금 누가 일하는지, 한 화면에. `#team` | 글 + 팝오버 | 열림 | 72svh |
| S4 | 콕. `#poke` | 거대한 "콕." + 팝오버 | 열림 | 72svh |
| S5 | 하고 싶은 말은, 메시지로. `#message` | 글 + 팝오버 | 열림 | 72svh |
| S6 | 한 판, 쉬어 가기. `#games` | 글 위 + **큰 게임 창** | 접힘 | 내용(≈1.0vp) |
| S7 | 근무하는 동안, 화면 구석에서 함께. `#character` | 글 + 팝오버 + 아잉 옆 할 일 보드 | 열림 | 72svh |
| S8 | 12주 잔디, 지난주 리듬. `#records` | 글 + 확대 잔디 + 팝오버(두 박자) | 열림 | 내용(≈1.1vp) |
| S9 | 이제, 아이폰에서도. `#iphone` | 글 + 폰 + 위젯 | 접힘 | 내용(≈0.95vp) |
| S10 | 화면도, 입력도 보지 않아요. `#trust` | **글자만** | 접힘 | 내용(≈0.7vp) |
| S11 | 지금, 메뉴바에. `#install` | bg-1 띠, Mac / iPhone 두 묶음 | 접힘 | 내용(≈1.0vp) |
| S12 | 자주 묻는 것. `#faq` | 한 열 목록 | 접힘 | 내용(≈0.9vp) |
| S13 | 메뉴바에, 아잉 하나. `#closing` | 확대 라벨 + 퇴근 | 접힘 | 내용(≈0.7vp) |
| S14 | 푸터 | 한 줄 + 링크 | — | ≈0.25vp |

같은 구도(글 + 팝오버)가 이어지는 곳은 S3–S5(셋)와 S7–S8(둘)뿐이다. 그 사이를 S2(접힘)·S6(큰 창)·S9(폰)·S10(글자만)이 끊는다.
와이어 범례: `▓` 실제 렌더 · `[ ]` 버튼 · `( | )` 세그먼트 · `◎` 아잉(코너·인라인 무대) · `⌁` 핫스팟.

---

### S0. 내비 띠 + 메뉴바 라벨 + 스파인(전역 층 `MenubarStage`)

**목적**: 페이지 상단 띠의 오른쪽 끝에 진짜 라벨이 있다는 것을 첫 픽셀부터. 설치 버튼을 늘 손 닿는 곳에.

**카피**
- 건너뛰기 링크(포커스 때만 보임): **본문으로 건너뛰기** → `#main`
- 워드마크: 앱 아이콘 20px + **아잉체크**(`t-nav` 15px 700) → `#top`, `aria-label="아잉체크 처음으로"`
- 링크(desk·tab): **기능** `#team` · **아이폰** `#iphone` · **설치** `#install` · **자주 묻는 것** `#faq` (화면에는 가운뎃점 없이 간격으로만)
- CTA(플랫폼별, §8.4): Mac·그 외 데스크톱 → **Mac용 다운로드**(`/api/download`) / iPhone·iPad → **App Store**(`https://apps.apple.com/app/id6812768622`) / phone 폭의 Mac·그 외 → **설치**(`#install`)

**레이아웃**
```
desk 1440 (높이 48, position: sticky; top: 0; 바탕 --bg-0 불투명, 아랫변 --line 1px)
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│16 ◉ 아잉체크   32  기능  아이폰  설치  자주 묻는 것                (Mac용 다운로드) 12 ▓😟 오프▓ 16│
└──────────────────────────────────────────────────────────────────────────────────────────┬┘
                                                                     팝오버 오른쪽 끝 = 여기 ┘(띠 아래 6px 에 매달림)
phone 390 (높이 48)
┌──────────────────────────────────────────┐
│16 ◉ 아잉체크              ▓😟 오프▓ (설치) 16│
└──────────────────────────────────────────┘
```
- 링크: 높이 32, 좌우 12, `t-nav` `--ink-2`, 호버 `--ink-1` + 바탕 rgba(255,255,255,.06) `--r-nav`. 활성 섹션 링크는 `--ink-1` + `aria-current="true"`.
- CTA: 높이 32, 좌우 16, `t-button-s`, `--r-pill`. **처음엔 테두리**(1px `--aing`, 글자 `--aing`, 투명 바탕). 히어로의 CTA 줄(`[data-hero-cta]`)이 뷰포트를 벗어나면 **채움**(`--aing` 바탕 + `--on-aing` 글자), 색 전환 200ms 선형. 감속 모션이면 즉시.
- 라벨(StatusItem): 이미지 높이 22px(1pt = 1px). 히트 영역 = 띠 높이 48 × (이미지 폭 + 12). 호버 바탕 rgba(255,255,255,.10) `--r-label`, 팝오버가 열려 있으면 rgba(255,255,255,.16) 유지(macOS 상태 항목과 같은 신호). 처음 오프 → 00:00 이 되는 한 번만 라벨 아래 민트 번짐: `box-shadow: 0 6px 18px rgba(78,211,149,.35)` 0→1→0, 600ms.
- phone·tab 의 라벨은 버튼이 아니라 `aria-hidden` 이미지(팝오버는 섹션마다 인라인으로 이미 있다).

**금지**: 애플 로고·시계·와이파이·제어 센터 같은 시스템 항목, 반투명 블러, 메뉴 항목 하이라이트 흉내. 띠에 있는 것은 사이트 항목과 아잉체크 라벨뿐.

**스파인(desk 만)**
- `position: fixed; top: calc(var(--nav-h) + var(--spine-gap)); right: var(--edge); z-index: var(--z-spine)`. 폭 414·s. 배율 `s = min(1, (100svh − 48 − 6 − 16) / 695)` — 가장 큰 패널(695pt) 기준으로 한 번 정해 패널이 바뀌어도 배율이 출렁이지 않는다(900 높이 → 1, 720 높이 → 0.935).
- 창 셸: `--r-window`, `--shadow-window`, `overflow: hidden`, 높이 = 현재 패널 pt × s. 패널이 바뀌면 높이 200ms ease-out, 이미지는 위쪽 정렬로 겹쳐 두고 위 판 불투명도만 180ms 선형(같은 판 위 숫자만 바뀌는 근무 시작·쿨타임 교체는 0ms). 새 판은 `img.decode()` 를 마친 뒤 교차(빈 프레임 금지).
- 열림: 불투명 0→1 120ms 선형 + translateY(−4px)→0 · scale(.985)→1 180ms ease-out, `transform-origin: top right`. 닫힘: 반대, 140ms ease-in. 감속 모션: 불투명 120ms 만.
- 로드 순간(desk, 감속 모션 아님, 처음 활성 섹션이 hero): 팝오버는 SSR 로 DOM 에 있고 CSS 키프레임만으로 150ms 지연 뒤 열림 전이를 한 번 한다(하이드레이션을 기다리지 않음 — LCP 는 H1).
- 사각형(스크린 좌표 + s)을 `demo.setSpineRect` 로 게시한다(ResizeObserver + `visualViewport` resize + 열림/닫힘 끝). **스파인과 PanelSlot 의 조상에 transform·filter·contain·will-change: transform 금지**(fixed 기준이 바뀐다).
- 렌더 이미지는 현재 판과 직전 판만 마운트하고, 다음 섹션의 판은 `new Image()` 로 미리 받아 둔다(§8.2).
- `popover-on` 판 위에는 틱 띠(§4 공통 K)를 겹친다.

**라벨 정지 팝오버(desk, 스파인 없는 섹션)**: 스파인과 같은 셸·같은 자리, `labelPanel(s)` 판 하나, 핫스팟 없음. Esc·바깥 클릭·160px 이상 스크롤로 닫힘.

**접근성**: `<header>` 안 `<nav aria-label="주요">`. 라벨 버튼 `aria-label` = 상태 포함("아잉체크 메뉴바, 오프" / "아잉체크 메뉴바, 근무 중 03:45"), `aria-expanded`, `aria-controls="spine"`. 스파인 `<div id="spine" role="img" aria-label={현재 패널 alt}>`(핫스팟은 섹션 DOM 에 있다).

---

### S1. 히어로 `#top` — 첫 3초

**목적**: 이것이 무엇인지(맥 메뉴바 근무 타이머) + 진짜 앱이 여기서 움직인다는 것 + 다운로드.

**카피(그대로)**
- H1(`t-display`, `<br>` 고정): **출퇴근 기록을,⏎메뉴바 하나로.**
- 리드(`t-lead`, `--ink-2`): 근무 시작을 누르면 팀 전체에 바로 보여요. 일하는 동안엔 아잉이 화면 구석에서 함께해요.
- CTA 줄(`data-hero-cta`, `data-companion-avoid`):
  - Mac·그 외: 주 버튼 **Mac용 다운로드**(`/api/download`) + App Store 공식 배지
  - iPhone·iPad: App Store 배지가 먼저, 다음에 보조 버튼 **Mac 링크 보내기**
- 메타 줄(`t-small`, `--ink-3`):
  - 기본: 무료예요. macOS 14 이상이면 Apple Silicon·Intel 어디서든 돌아가요.
  - 다운로드를 누른 뒤(installHint): 받은 파일을 열고, 아이콘을 Applications 폴더로 끌어다 놓으세요.
  - iPhone·iPad: iOS 18 이상, 무료예요. 근무 시작·종료는 맥에서 해요.
- 텍스트 링크(`t-small`, `--aing`, 밑줄): **터미널이 편하다면 brew로 설치** → `#install` (iPhone·iPad 에서는 숨김)

**레이아웃**
```
desk 1440×900
┌ 내비 48 ───────────────────────────────────────────────────────────────┬───────────────┐
└────────────────────────────────────────────────────────────────────────┤▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│ 팝오버 414×653
 80                                                                     │▓ 근무종료  ⌁[근무 시작]▓│ (x 1010–1424, y 54–707)
   출퇴근 기록을,                         (H1 88px, 윗변 ≈ y 236)        │▓ 이번 주 19시간 38분 ▓│
   메뉴바 하나로.                                                        │▓ 9월 AI 토큰 …       ▓│
                                                                         │▓ 아잉 데모팀 4명 근무중▓│
   근무 시작을 누르면 팀 전체에 바로 보여요.                               │▓ 구름빵 …            ▓│
   일하는 동안엔 아잉이 화면 구석에서 함께해요.                            │▓ …                   ▓│
                                                                         │▓ 동기화됨            ▓│
   [ Mac용 다운로드 ]  [ App Store 배지 ]                                  └───────────────┘
   무료예요. macOS 14 이상이면 …
   터미널이 편하다면 brew로 설치                                                         ◎ ← 근무 시작 뒤에만
 ── 화면 아래 끝에 S2 헤드라인 윗부분이 64px 걸쳐 보인다(스크롤 힌트 불필요) ──             (124.6×150.5, 오른쪽 20·아래 16)

phone 390×844
┌ 내비 48 ─────────────────────────┐
  출퇴근 기록을,          (H1 40px, 윗변 y 72)
  메뉴바 하나로.
  근무 시작을 누르면 …   (리드 17px, 3줄)
  [ Mac용 다운로드 ] [App Store]   (iPhone 이면 배지 먼저 + [Mac 링크 보내기])
  무료예요. …
 ┌▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓┐  ← 인라인 팝오버 폭 min(100vw − 40, 380) = 350 (배율 0.845)
 │▓ 근무종료   ⌁[근무 시작] ▓│     접힘선 위에 헤더와 [근무 시작]이 보인다(≈436px)
◎┘ ← 근무 시작 뒤 인라인 무대 110×133: 무대 오른쪽 아래 = 팝오버 왼쪽 아래 + (90, 20), left ≥ 8
```
- desk: 히어로 높이 `calc(100svh − var(--nav-h) − 64px)`(최소 560px), 글 열은 세로 가운데, H1 윗변이 팝오버 윗변보다 아래.
- 주 버튼: 높이 48, 좌우 24, `t-button`, `--aing` 바탕, `--on-aing` 글자, 호버 `--aing-hover`, 눌림 scale(.98) 100ms. 배지: 높이 48, 사방 여백 12(애플 규칙: 높이 ≥ 40, 여백 = 높이/4), 수정·기울이기·애니메이션 금지. 줄 간격 12.
- tab: 글 위, 인라인 팝오버(폭 380, 왼쪽 정렬) 아래. H1 ≈47px.
- 짧은 phone(390×667): H1 `font-size: min(40px, 10.3cqi)`(히어로 글 상자 `container-type: inline-size`), CTA 줄이 첫 화면 안. 팝오버 헤더는 접힘선 아래로 가도 된다.

**에셋**: `ui/popover-off` · `ui/popover-on` · `ui/popover-tick-strip` · `ui/menubar-off` · `ui/menubar-0000` · `brand/appstore-badge-ko-black.svg` · 코너/인라인 `char/aing-commute-start` + `char/aing-idle` + 포스터 · `ui/bubble-commute-start`.

**상호작용**
| 사용자 | 결과 |
|---|---|
| 렌더 속 [근무 시작](핫스팟 `startButton`) 클릭·탭·Enter·Space | `pressStart()`. 팝오버 popover-off → popover-on 0ms 교체(같은 판 위 상태 변화) + 틱 시작. 렌더 그대로 [근무 시작] 자리가 [근무 종료](코랄)로, "4명 근무중"이 "5명 근무중"으로, 새벽 행에 "근무중" 칩이 붙는다. 라벨 오프 → 00:00 + 민트 번짐. 코너에 아잉 commute_start(폴짝 + 360°, 1.5초), 0.2초에 "오늘도 화이팅!" |
| 근무 중 렌더 속 [근무 종료] | 핫스팟 없음(커서 기본). 종료는 S13 에서만 |
| 주 버튼(Mac) | `/api/download` 로 이동(모달 없음, 302 → DMG 내려받기 시작, 페이지 그대로) + `installClicked('hero')` → 메타 줄이 설치 안내로(120ms 선형 교차) |
| Mac 링크 보내기(iPhone) | `navigator.share({ title: '아잉체크 Mac 앱', url: location.origin + '/#install' })`, 없거나 실패하면 클립보드 복사 + 버튼 글자 **링크를 복사했어요**(2초) + 알림 |
| 텍스트 링크 | `#install` 로 스크롤 |

**모션(첫 3초)**: 0ms SSR 첫 페인트(띠·H1·리드·CTA·팝오버 자리) → 150–330ms 팝오버가 라벨 밑에서 한 번 내려옴(desk, 페이지의 유일한 로드 연출) → 1200ms [근무 시작] 핫스팟 둘레 `--hotspot` 링 한 번 맥동(box-shadow 0 0 0 0 → 0 0 0 10px, 불투명 .7→0, 700ms, 1회). 그다음은 사용자 동작에만. 감속 모션: 내려옴·맥동 없음.

**성능**: LCP = desk 는 H1 텍스트(SSR, 서브셋 글꼴 preload), phone·tab 은 인라인 팝오버(H1 보다 넓다 — 수리 단계 실측). 첫 화면 이미지 = popover-off 39KB(`loading="eager"`, 인라인 active 판에 `fetchpriority="high"`) + 라벨 5KB + 배지 9KB + 아이콘 2KB. load + `requestIdleCallback` 에서 popover-on·틱 띠·commute_start·idle 포스터·말풍선 2장을 받는다. idle 영상은 [근무 시작] 핫스팟 `pointerenter`/`touchstart` 또는 S2 가 600px 안에 들 때부터. 클릭 순간 반응 영상이 없으면 포스터 + 말풍선으로 먼저 보여 주고, 600ms 안에 준비되면 재생, 아니면 건너뛰고 idle 로.

**접근성**: H1 은 실제 `<h1>`(한 문장으로 읽힘). 인라인 팝오버 `alt` 는 §6 `ALT`. 핫스팟 `aria-label="근무 시작"`. 시작 알림 "근무를 시작했어요. 오늘도 화이팅!".

---

### S2. 깜빡해도, 알아서. `#auto` — 자동 시작 · 시간 경과

**목적**: "버튼을 안 눌러도 된다"는 사실과, 일하는 동안 시간이 흐르는 모습. 방문자의 스크롤 자체가 "컴퓨터를 쓰는 중"이라 앱처럼 대신 켜진다. 처음 온 사람도 첫 스크롤에서 아잉을 반드시 만난다.

**카피**
- H2: **깜빡해도, 알아서.**
- 본문(`t-body` `--ink-2`): 컴퓨터를 쓰기 시작하면 아잉이 알리면서 근무를 대신 켜요. 맥을 덮고 떠나면 덮은 시각에 맞춰 정리되고, 잠깐 비운 거라면 돌아왔을 때 그대로 이어져요.
- 두 번째 문단(`--ink-2`): 인터넷이 끊겨도, 누른 순서대로 반영돼요.

**레이아웃**
```
desk (min-height 76svh, 스파인 접힘 — 라벨만 띠에 남는다)
 80
   깜빡해도, 알아서.                                        (오른쪽은 비워 둔다)          ▓라벨 00:00 → 01:00 → 03:45▓ (띠)
   본문 2문장
   두 번째 문단
   ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ 표지1(섹션 높이 38%)                                      ◎ 01:00 색종이
   ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ 표지2(섹션 높이 78%)                                      ◎ 03:45 루비 +3!
phone (min-height 100svh)
   H2 / 본문 / 두 번째 문단
   ◎ 인라인 무대 'inline-lg' 180×217 (왼쪽 정렬) — 자동 시작·색종이·루비가 여기서
```
- 표지 두 개는 보이지 않는 1px 요소(`data-pass="1"`, `"2"`). 뷰포트 세로 중앙선을 위로 지나가면 '지남'.
- 이 절에서는 화면에 렌더 패널이 없다. 라벨(띠)과 구석 아잉, 그리고 몸통 캡슐이 시간을 말한다. 오른쪽이 비는 것이 의도다(앞뒤 절의 밀도와 대비).

**에셋**: `char/aing-commute-start` · `char/aing-milestone`(신규) · `char/aing-ultra-charged` · `ui/bubble-autostart` · `ui/bubble-ruby` · `ui/menubar-0000` · `ui/menubar-0100` · `ui/menubar-0345`.

**상호작용**
- 진입(섹션 50% 보임 + 700ms)에 work=off 면 `autoStart()`: 라벨 00:00, 코너 아잉 commute_start + "일하는 것 같아서 근무 시작했어요!"(8초). work=off 인 채 표지1을 먼저 지나면 그 순간 `autoStart()` 하고, 색종이(milestone)는 반응 큐에 들어가 1.2초 뒤 이어진다.
- 표지1 통과(400ms 머묾) → `setAutoPassed(1)`: 라벨 01:00(즉시). 처음이면 반응 milestone(폴짝폴짝 + 색종이, 2.4초, 말풍선 없음 — 앱의 "오늘 1시간").
- 표지2 통과(400ms 머묾) → `setAutoPassed(2)`: 라벨 03:45(즉시), 캡슐 03:45. 처음이면 반응 ultra_charged(들이쉼 → 번쩍 → 정착, 파란 흡수 스파크) + "루비 +3!"(3.2초) — 앱의 "근무 3시간마다 루비 +3". 수치 캡션은 쓰지 않는다(말풍선은 앱 문구).
- 거꾸로 올라가면 라벨만 03:45 → 01:00 → 00:00 으로 돌아간다. 반응은 다시 나오지 않는다.
- 근무 종료/재시작 데모는 이 절에 없다.

**모션**: 앱 반응뿐. 감속 모션: 말풍선만(색종이·스파크 없음, 포스터 정지).

**성능**: milestone(≈240KB)·ultra-charged(≈295KB)는 S1 이 화면을 반쯤 벗어날 때(이 절 600px 전) 받는다.

**접근성**: 자동 시작은 알림 "일하는 것 같아서 근무 시작했어요!" 한 번. 색종이·루비 반응은 장식(알림 없음) — 내용은 본문이 말한다.

---

### S3. 지금 누가 일하는지, 한 화면에. `#team` — 팀 현황 · 팀 리그

**목적**: 팀이 한 화면에 보인다. 목표는 각자의 약속. 다른 팀과는 리그로.

**카피**
- 시각 표식(`t-time`, `--ink-3`): **14:05**
- H2: **지금 누가 일하는지,⏎한 화면에.**
- 본문: 누르는 순간 팀 전체에 보여요. 팀원마다 지금 근무 시간과 이번 주 진행이 한 줄씩 보이고, 목표는 팀 합계가 아니라 각자의 약속이에요.
- H3: **팀끼리는, 리그로.**
- 본문: 다른 팀과는 1인당 평균으로 나란히 서요. 리그에는 팀 숫자만 오르고 개인 숫자는 오르지 않아요.
- 세그먼트(`aria-label="팀 화면"`): ( **우리 팀** | **팀 리그** )

**레이아웃**
```
desk
14:05 지금 누가 일하는지,                                          │▓ popover-working ▓│ ⇄ │▓ league ▓│
 ↑    한 화면에.                                                   │▓ 03:45 5명 근무중  ▓│
 거터 본문                                                         │▓ 구름빵 04:37 …    ▓│
(x24)  팀끼리는, 리그로.  (H3)                                      │▓ ⌁[팀 현황] 레일   ▓│
      본문                                                         └───────────────────┘
      ( 우리 팀 | 팀 리그 )
phone: 14:05 / H2 / 본문 / H3 / 본문 / (세그먼트) / ▓ 인라인 렌더(교체) ▓
```
- 시각 표식: desk 는 그리드 왼쪽 여백 안(`position: absolute; left: 24px`)에 H2 첫 줄 글자 윗선과 맞춰 매단다. tab·phone 은 H2 위 8px 에 같은 글자로.

**에셋**: `ui/popover-working` · `ui/league` · `ui/menubar-0345`.

**상호작용**
- 진입: 장면 noon(라벨 03:45 즉시, 캡슐 03:45). 스파인이 popover-working 으로 다시 내려온다(앞 절에서 접혀 있었으므로 열림 전이).
- 세그먼트 **팀 리그** 또는 렌더 속 레일 **팀 현황** 핫스팟(`railTeam`, 포커스 불가 — 세그먼트가 키보드 경로) → `setTeam('league')`: 창 높이 653 → 600 으로 줄며 교차. **우리 팀** 또는 리그 판의 레일 핫스팟 → 되돌림.
- 두 판은 같은 자리에서 교체로만 보인다(팀 행 합과 리그 총합이 맞지 않는 가상 수치).

**모션**: 패널 교차 + 높이 맞춤, 세그먼트 알약 180ms ease-out 이동(위치만).

**접근성**: 세그먼트 = `role="radiogroup"`(화살표 키). 렌더 alt §6. 리그 렌더 속 팀 아바타의 작은 센터 배지는 가상 데이터라 그대로 두고, HTML 에는 센터를 어디에도 쓰지 않는다.

---

### S4. 콕. `#poke` — 콕 찌르기 · 울트라 · 집중 모드

**목적**: 이 앱만의 장난. 받아 보는 것이 가장 빨리 이해된다. 페이지에서 가장 큰 움직임(울트라)이 여기 있지만 **방문자가 되찌른 결과로만** 온다.

**카피**
- H2(`t-h2-solo`): **콕.**
- 리드(`t-lead`, `--ink-1`): **찔러 부르기.**
- 본문: 근무 중인 사람을 콕 찌르면 그 사람 캐릭터가 화들짝 놀라며 누가 불렀는지 말풍선으로 알려요.
- H3: **울트라.**
- 본문: 찌르기 버튼을 꾹 누르면 울트라예요. 내 캐릭터가 상대 화면을 잠깐 덮어요.
- 작은 줄(`t-small`, `--ink-2`): 방해받기 싫은 날엔 집중 모드를 켜 두세요. 그동안은 아무도 나를 찌르지 못해요.

**레이아웃**
```
desk
   콕.                        (112px)                         │▓ poke_list          ▓│
   찔러 부르기.                                               │▓ 콕 찌르기 ⌁[집중] ⚡3 ▓│
   본문                                                       │▓ 구름빵 ● 근무중  💬 👉│
   울트라. (H3)                                               │▓ 달토끼 …            ▓│
   본문                                                       │▓ 민트별 … 💬 ⌁[👉]    │
   집중 모드 한 줄                                             │▓ …                   ▓│
                                                              └──────────────────────┘     ◎ "민트별님이 콕 찔렀어요!"
울트라 순간(전 뷰포트, 바탕을 어둡게 하지 않는다)
┌──────────────────────────────────────────────┐
│          ▓ 민트별님의 울트라 찌르기! ▓           │ ← 정사각 윗변 + 56px, 가로 가운데
│     ┌──────────────────────────────┐          │
│     │  아잉(민트별 캐릭터) 2.4초 떨림   │          │ ← 한 변 = 0.98 × min(100vw, 100svh), 정중앙
│     └──────────────────────────────┘          │
└──────────────────────────────────────────────┘
phone: 콕. / 찔러 부르기. / 본문 / 울트라. / 본문 / 집중 한 줄 / ▓ poke_list 인라인(⌁ 집중·민트별) ▓ + ◎ 인라인 무대(렌더 오른쪽 아래에 걸쳐)
```

**에셋**: `ui/poke-list` · `ui/poke-cooldown` · `ui/poke-focus-1` · `ui/poke-focus-2` · `char/aing-poked` · `char/aing-ultra` + `char/aing-ultra-poster` · `ui/bubble-poked-mint` · `ui/bubble-ultra-mint`.

**상호작용(이야기 하나: 찔렸다 → 되찔렀다 → 울트라가 돌아왔다)**
1. 진입(50% + 1200ms) `pokeIn()`: 코너 아잉 poked(도약 + 공중 난리 + 착지, 3.0초) + "민트별님이 콕 찔렀어요!"(6초). 숨김 상태여도 이 반응 동안 잠깐 나타났다가 다시 숨는다(앱 사실). 집중 모드가 켜져 있으면 일어나지 않는다.
2. 렌더 속 **민트별 행 찌르기 버튼**(`pokeMint`, 파랑 원, 히트 44×44) → `pokeBack()`: 팝오버 poke-cooldown(민트별 버튼이 흐려진 앱 쿨타임 판) 0ms 교체.
3. 1000ms 뒤 `ultraIn()`: 민트별이 울트라로 답한다(오버레이 §4 공통 U). 2.4초. 아무 입력으로 즉시 닫힘.
4. 렌더 속 **[집중] 칩**(`focusChip`) → `cycleFocus()`: poke-list → poke-focus-1("집중 모드 1단 — 3시간 동안 콕찌르기를 받지 않아요") → poke-focus-2 → 원래 판(쿨타임이었으면 poke-cooldown). 창 높이 654 ↔ 679 를 200ms 로 맞춘다. 1·2단이면 민트별 찌르기 핫스팟 비활성(`aria-disabled`, 커서 기본) — 렌더 속 안내 줄이 이유를 말한다.
- 다른 행의 찌르기 버튼은 핫스팟이 없다(쿨타임 렌더가 민트별 것뿐). 울트라는 한 번만(once). 렌더 머리의 "3초 꾹 = 울트라"는 앱 글자라 그대로 둔다. 꾹 누르기는 탭과 같은 결과다(보내는 쪽 울트라 렌더가 없으므로).

**모션**: 1·3 은 앱 영상. 2·4 는 렌더 교체. 울트라 퇴장 160ms 선형. 감속 모션: 1 = 말풍선만, 3 = 포스터 + 말풍선 3초.

**성능**: poked(≈296KB)는 이 절 600px 전, 울트라(≈340KB)는 이 절이 뷰포트 1장 거리 안에 들 때.

**접근성**: 핫스팟 `aria-label`: "민트별 콕 찌르기", "집중 모드 바꾸기"(`aria-pressed` 대신 알림으로 단계 낭독). 1·3 은 알림이 말풍선 문구를 읽는다.

---

### S5. 하고 싶은 말은, 메시지로. `#message` — 1:1 메시지

**목적**: 메시지가 오고, 답하고, 읽히는 흐름이 렌더 네 장으로 맞물린다.

**카피**
- H2: **하고 싶은 말은,⏎메시지로.**
- 본문: 근무 중이 아니어도 1:1로 주고받아요. 상대가 읽으면 옆의 1이 사라져요.
- 왼쪽 버튼(보조 캡슐, 상태에 따라 하나만): arrived → **구름빵 대화 열기** / composing → **보내기** / 그 뒤 → 숨김(자리는 유지해 레이아웃이 밀리지 않게 `visibility: hidden`)

**레이아웃**
```
desk
   하고 싶은 말은,                                            │▓ popover-newmsg(레일 점) ▓│
   메시지로.                                                  │   ⌁[콕 / 메시지] → 열기   │
   본문                                                       │▓ composing ⌁[보내기] → unread(1) → read ▓│
   [ 구름빵 대화 열기 ] → [ 보내기 ]                            └──────────────────────────┘
                                                              ◎ "구름빵님: 커피 한잔 해요 ☕️"(누르면 열기) · 라벨 03:45 빨간 점
phone: H2 / 본문 / [버튼] / ▓ 인라인 렌더(교체) ▓ + ◎ 인라인 무대
```

**에셋**: `ui/popover-newmsg` · `ui/message-composing` · `ui/message-unread` · `ui/message-read` · `ui/menubar-0345-newmsg` · `char/aing-poked`(메시지 수신도 같은 동작) · `ui/bubble-message-gureum`.

**상호작용**
1. 진입(50% + 800ms) `msgArrive()`: 라벨에 빨간 점, 팝오버 popover-newmsg, 코너 아잉 message_received + "구름빵님: 커피 한잔 해요 ☕️".
2. 렌더 속 레일 **콕 / 메시지**(`railPokeMsg`), 말풍선, 왼쪽 **구름빵 대화 열기** 중 아무거나 → `msgOpen()`: 팝오버 message-composing(답장 "좋아요! 배포하고 1층에서요 ☕️"가 입력칸에 있는 판), 라벨 점 사라짐.
3. 렌더 속 **[보내기]**(`sendButton`) 또는 왼쪽 **보내기** → `msgSend()`: message-unread(내 말 옆 파란 1) → 1600ms 뒤 message-read(1 사라짐).
- 입력칸에 직접 타이핑하는 기능은 없다(렌더 판이 정해져 있다).

**모션**: 같은 창 안 내용 변화라 120ms 선형 교차 + 높이 572→603 맞춤 200ms. 1 이 사라지는 순간은 렌더 교체 그대로.

**접근성**: `railPokeMsg` 는 포커스 가능(도착 전 popover-working 판에도 같은 자리에 비활성으로 있다 — Tab 이 이 절에 닿아야 도착이 시작된다. arrived 일 때만 활성, `aria-label="콕 / 메시지 열기"`), `sendButton` 포커스 가능(composing 일 때만, `aria-label="보내기"`). 알림: "구름빵님: 커피 한잔 해요" → "보냈어요" → "구름빵님이 읽었어요".

---

### S6. 한 판, 쉬어 가기. `#games` — 미니게임 · 오목 · 체스

**목적**: 쉬는 시간의 재미. 게임은 앱에서 별도 창으로 열린다는 사실을 레이아웃으로(팝오버가 접히고 창이 자리를 잇는다).

**카피**
- H2: **한 판, 쉬어 가기.**
- 본문: 타이밍 바·플래피 아잉·테트리스로 오늘 순위에 도전해요. 오목과 체스는 1:1로 겨루고, 상대가 없으면 AI와 혼자 둬요.
- 세그먼트(`aria-label="게임 화면"`): ( **플래피 아잉** | **1:1 오목** )

**레이아웃**
```
desk (스파인 접힘)
 80
   한 판, 쉬어 가기.
   본문
   ( 플래피 아잉 | 1:1 오목 )
  ┌▓▓▓▓▓▓▓▓▓▓▓▓ 미니게임 창 700×389 (1pt = 1px) ▓▓▓▓▓▓▓▓▓▓▓▓┐ ← '창': --r-window, --shadow-window
  │ 플래피 아잉 캔버스            │ 오늘 순위 8명             │    잘린 캔버스 열(왼쪽 51.1%)만 아래 48px 페이드 → 창 바탕(--render-window) — 수리 단계: 순위표 8행·창 아랫변은 온전히
  └────────────────────────────────────────────────────────┘
   1:1 오목 선택 시: 오목 판 크롭 630×700pt 를 0.8배(504×560)로 같은 자리, 높이 200ms 맞춤
phone: H2 / 본문 / (세그먼트) / ▓ 창 폭 100% ▓ — phone 의 첫 값은 1:1 오목(플래피 창은 폭 350 에서 글자가 읽히지 않는다)
```
- tab: 창 폭 min(100%, 700), 배율 = 폭/700(오목은 폭/630 × 0.9 상한 높이 560).

**에셋**: `ui/minigame`(8줄 판만) · `ui/gomoku-board` · `ui/gomoku-board-sm`(phone). 테트리스·체스 렌더는 없다 → 글로만.

**상호작용**: 세그먼트로 창 판 교체(120ms 선형 교차 + 높이 맞춤). 게임을 실제로 하게 만들지 않는다(앱에 없는 웹 게임이 된다).

**접근성**: 창 alt §6. 세그먼트 radiogroup.

---

### S7. 근무하는 동안, 화면 구석에서 함께. `#character` — 캐릭터 · 루비 · 오늘 할 일

**목적**: 구석의 아잉이 장식이 아니라 기능이라는 것. 누르면 오늘 할 일이 열린다(앱 기본 동작).

**카피**
- H2: **근무하는 동안,⏎화면 구석에서 함께.**
- 본문: 출근하면 폴짝 뛰어오르고, 퇴근하면 꾸벅 인사해요. 고른 캐릭터는 바탕화면·메뉴바·팝오버에서 함께 바뀌어요.
- H3: **일한 만큼, 루비.**
- 본문: 일한 시간만큼 루비가 쌓이고, 상점에서 캐릭터를 골라요.
- H3: **캐릭터를 누르면, 오늘 할 일.**
- 본문: 작은 할 일 목록이 열려요. 못 끝낸 일은 다음 날로 넘어오고, 맥과 아이폰과 위젯이 같은 목록을 써요.
- 버튼(보조 캡슐, `aria-expanded`): **오늘 할 일 열기** / 열려 있으면 **오늘 할 일 닫기**

**레이아웃**
```
desk
   근무하는 동안,                                              │▓ character_pick ▓│ (414×495)
   화면 구석에서 함께.                                          │▓ 아잉✓ 여우 유령  ▓│
   본문                                                        │▓ 해파리 강아지 다람쥐▓│
   일한 만큼, 루비. (H3) / 본문                                  └──────────────────┘
   캐릭터를 누르면, 오늘 할 일. (H3) / 본문                       ┌▓ 할 일 보드 300×400 ▓┐
   [ 오늘 할 일 열기 ]                                           └──────────────────────┘◎ ← 아잉 옆에 열림
phone: H2 / 본문 / H3 / 본문 / H3 / 본문 / [오늘 할 일 열기] / ▓ character_pick 인라인 ▓ / ◎ 인라인 무대 → 누르면 아래 시트
```

**에셋**: `ui/character-pick`(캐릭터 6종이 한꺼번에 보이는 유일한 판 — 페이지에서 한 번만) · `ui/todo-board`.

**상호작용**
- 코너 아잉(몸통만) 클릭 또는 **오늘 할 일 열기** → `toggleTodo()`: 할 일 보드가 아잉 옆에 열린다(§4 공통 T). 버튼을 눌러도 보드는 아잉 옆에 열린다(앱에서 보드는 캐릭터에 붙어 있다 — 버튼은 키보드 경로). 아잉을 숨겨 둔 상태라면 버튼이 아잉을 먼저 되돌린다.
- 캐릭터 바꿔 입기는 만들지 않는다(라벨·팝오버 렌더가 아잉으로 남아 "함께 바뀐다"는 사실과 어긋난다). 로봇은 그림·숫자 모두 없음.

**접근성**: character_pick alt §6. 버튼 `aria-controls="todo-board"`.

---

### S8. 12주 잔디, 지난주 리듬. `#records` — 내 기록 · AI 토큰

**목적**: 혼자 보는 기록이 예쁘게 쌓인다(사용자가 "무조건 살린다"고 한 잔디 점등). 두 번째 박자로 AI 토큰 순위판.

**카피**
- H2: **12주 잔디, 지난주 리듬.**
- 본문: 지난주 어느 요일 몇 시에 일했는지는 격자로, 한 주 요약은 카드 한 장으로 보여 줘요. 최근 12주의 근무와 AI 토큰은 잔디로 쌓여요.
- 두 번째 문단: 이 화면은 내 맥이 내 기록만으로 계산해요. 팀원도 볼 수 없어요.
- 세그먼트(`aria-label="잔디 종류"`): ( **근무** | **AI 토큰** )
- (박자 `records:tokens`) H3: **이번 달 AI 토큰, 전체 순위판.**
- 본문: 이 맥의 Claude Code·Codex 기록에서 숫자만 세어 이번 달 사용량을 보여 줘요. 대화 내용은 읽지 않아요. 순위판에 오를지는 설정에서 내가 정해요.
- 작은 줄(`t-small`, `--ink-2`): 5시간·주간 리밋이 얼마나 찼는지도 메뉴바에서 바로 보이고, 아이폰과 위젯에서도 봐요.

**레이아웃**
```
desk
   12주 잔디, 지난주 리듬.                                      │▓ insights_popover ▓│ (414×695)
   본문 / 두 번째 문단                                          │▓ 지난주 42시간 50분 ▓│
   ( 근무 | AI 토큰 )                                           │▓ 근무 리듬 격자     ▓│
   ┌─────────────────────────────────┐ ← GrassLight 456×258   │▓ 12주 잔디(잘림)    ▓│
   │ 7월   8월      9월               │   (304×172pt × 1.5,     └──────────────────┘
   │ ▢▢▢▢▢▢▢▢▢▢▢▢▢  (칸마다 점등)      │    --r-window, --shadow-window)
   └─────────────────────────────────┘
   ── 박자 records:tokens ──                                     │▓ token_board_month ▓│ (414×682)
   이번 달 AI 토큰, 전체 순위판. (H3)                             │▓ ⌁◀ 9월 AI 토큰 ▷  ▓│
   본문 / 작은 줄                                                │▓ 1 구름빵 …        ▓│
phone: H2 / 본문 / 두 번째 / (세그먼트) / GrassLight 폭 100% / ▓ insights 인라인 ▓ / H3 / 본문 / 작은 줄 / ▓ token 인라인(⌁◀▷) ▓
```

**에셋**: `ui/insights-popover` · `ui/grass-work-empty` · `ui/grass-work-final` · `ui/grass-token-empty` · `ui/grass-token-final` · `data/generated/grass.json` · `ui/token-month` · `ui/token-last`.

**상호작용**
- **점등(페이지의 유일한 scrub)**: 확대판 윗변이 뷰포트 85% 선에 닿으면 p=0, 35% 선에 닿으면 p=1. 켜진 열 수 = ⌊p × 13⌋(주 단위, 7월 → 이번 주). 한 열이 켜지면 그 열의 칸이 월 → 일 순서로 40ms 간격, 칸마다 불투명 0→1 160ms 선형. `future: true` 칸은 켜지지 않는다. 올리면 거꾸로 꺼진다. rAF 한 번, opacity 만.
- 구현: 바탕 = empty 판, 칸마다 `div`(13×7 = 91개)에 final 판을 `background-position` 으로 잘라 얹고 불투명도만 바꾼다(좌표 = grass.json 의 @3x px ÷ 3 × 1.5). **새로 칠하는 색 0** — 칸 색은 final 렌더의 픽셀.
- 호버(포인터 fine): 켜진 칸 위 툴팁 "**월요일, 7시간 20분**"(요일 + `valueText` 그대로. 날짜는 쓰지 않는다 — 소재끼리 날짜가 맞지 않는다). 툴팁은 `--surface-2` 바탕, `--r-tip`, `t-small` `--ink-1`, 칸 위 8px. 터치에서는 툴팁 없음.
- 세그먼트 **AI 토큰** → token 판으로 교체(점등 진행도 유지, 120ms 교차). 스파인 패널(insights)은 그대로.
- 박자 `records:tokens` 가 중앙 띠에 걸리면 스파인이 token-month 로 바뀐다. 렌더 속 **◀**(`tokenPrev`) → token-last, 지난달 판의 **▷**(`tokenNext`) → token-month. 두 핫스팟 모두 포커스 가능(`aria-label` "지난달 순위 보기" / "이번 달 순위 보기"). 이번 달 판의 ▷ 는 렌더에서 흐린 비활성이라 핫스팟이 없다.
- AI 리밋 화면은 렌더가 없다 → 글로만. 제공자 이름은 글자로만, 로고 없음.

**모션**: 점등뿐. 감속 모션: 칸 div 를 만들지 않고 final 이미지 한 장.

**성능**: 잔디 네 장 ≈160KB. 칸 div 는 이 절이 화면 근처일 때만 마운트(IO).

**접근성**: 확대판 `role="img" aria-label="최근 12주 근무 잔디. 지난주 42시간 50분, 목표 40시간 달성"`(토큰 판: "최근 12주 AI 토큰 잔디"). 툴팁 `aria-hidden`.

---

### S9. 이제, 아이폰에서도. `#iphone` — 아이폰 앱 · 위젯

**목적**: 동반 앱. 맥에서 켠 근무가 폰에도 보인다. 설치 경로(App Store).

**카피**
- H2: **이제, 아이폰에서도.**
- 본문: 맥에서 켠 근무가 폰에서도 보여요. 팀 현황·메시지·할 일·순위·게임을 폰에서 보고, 홈 화면 위젯으로도 봐요.
- 작은 줄(`--ink-2`): 근무 시작·종료는 맥에서 해요. 맥 앞에서 일하는 중이면 폰 알림은 울리지 않아요.
- H3: **위젯으로, 한눈에.**
- 본문: 위젯에서 할 일을 체크하면 앱을 열지 않아도 끝나요.
- App Store 배지 + (desk) QR + 작은 줄(`t-small` `--ink-3`): iOS 18 이상, 무료예요.

**레이아웃**
```
desk (스파인 접힘)
   이제, 아이폰에서도.              ┌────────────┐      ┌▓ 할 일 위젯 L ▓┐
   본문                            │ ▓ now     ▓│      │ 300×315       │ ⌁ "주간 회고 초안 쓰기" 줄
   작은 줄                         │ ▓ (다크)  ▓│      └───────────────┘
   위젯으로, 한눈에. (H3)           │ ▓  ⌁탭바  ▓│      ┌▓ S ▓┐ 140×140
   본문                            └────────────┘      └─────┘
   [App Store 배지]  ▣ QR 112      폰 화면 300×652
   iOS 18 이상, 무료예요.
 글 1–5열 · 폰 7–9열 · 위젯 10–12열(기울이지 않음, 위젯은 폰 중간 높이부터)
phone: H2 / 본문 / 작은 줄 / 폰(화면 260, 가운데) / H3 / 본문 / 위젯 L(폭 min(100%, 300)) / 위젯 S / [배지] / 메타. QR 숨김
tab: 2열(글 / 폰 260), 위젯은 글 아래
```
- 폰은 정면 하나(3D·기울기·틸트 없음). 셸은 코드로(§4 공통 P).

**에셋**: `ios/now` · `ios/messages` · `ios/rankings-league` · `ios/games` · `ios/me-records`(**'나' 탭은 me_records** — me 판의 서울 배지 회피) · `ios/widget-todos-large` · `ios/widget-todos-large-checked` · `ios/widget-today-small` · `brand/appstore-badge-ko-black.svg` · `brand/qr-appstore.svg`.

**상호작용**
- 렌더 속 탭바 5개 핫스팟(`phoneTabs`: 지금·메시지·순위·게임·나) → `setPhone()` → 화면 120ms 선형 교차(같은 크기·같은 상태 막대). 선택 탭은 렌더 속 하이라이트가 알려 준다.
- 위젯 L 의 "주간 회고 초안 쓰기" 줄(`widgetRow`, `role="checkbox"`) → `toggleWidget()`: todos-large ↔ todos-large-checked 교차. "남은 4개 → 남은 3개"가 렌더 속에서 바뀐다.
- 스크롤에 묶인 화면 교체(aingo 장치)는 쓰지 않는다 — 누를 수 있는 진짜 탭바가 있다.

**접근성**: 탭 핫스팟은 `role="tablist"`/`role="tab"`/`aria-selected`, 좌우 화살표 이동, 화면 이미지는 `role="tabpanel"` 안 `<img alt>`(§6). 위젯 체크 `aria-checked`, `aria-label="주간 회고 초안 쓰기"`. 배지 `alt="App Store에서 다운로드"`. QR `alt="App Store 아잉체크 페이지로 가는 QR 코드"`.

---

### S10. 화면도, 입력도 보지 않아요. `#trust` — 안심

**목적**: 근무 앱에 대한 첫 의심(감시)을 정면으로. 화면 없이 글자로만 서는 유일한 절.

**카피**
- H2: **화면도, 입력도 보지 않아요.**
- 큰 문장 1(`t-statement`, `--ink-1`): 스크린샷도, 키 입력도, 마우스 움직임도, 앱과 웹 사용 기록도 모으지 않아요.
- 큰 문장 2(`t-statement`, `--ink-1`): 손쉬운 사용·화면 기록·카메라·마이크·위치 권한도 묻지 않아요.
- 본문(`--ink-2`): 자리 비움 판단에는 '마지막으로 만진 시각' 하나만 써요. 무엇을 입력했는지는 담기지 않아요.
- 정직 문장(본문, `--ink-1`): 근무 시각과 기록은 같은 팀 안에서만 보여요. 별명·아바타·지금 근무 중인지는 앱을 쓰는 모두가 봐요.
- 신뢰 줄(`t-small`, `--ink-2`, 줄마다 한 문장, 아이콘·격자·번호 없음, `<ul role="list">`):
  - Apple 공증과 Developer ID 서명을 받은 앱이에요.
  - 외부 SDK 없는 네이티브 앱이에요.
  - 로그인 토큰은 macOS 키체인에 둬요.
  - 코드가 GitHub에 공개돼 있어요. (문장 전체가 링크 → `https://github.com/yehsung/check`)
  - 무엇을 보고 무엇을 보지 않는지 처리방침에 적어 뒀어요. (→ `https://yehsung.github.io/check/privacy`)

**레이아웃**: 왼쪽 정렬, 큰 문장 최대 폭 22em, 신뢰 줄 앞에 48px 여백(장식 선 없음). 오른쪽 절반을 비운다(앞 절들의 밀도와 대비 = 쉼). phone 은 같은 순서, statement 24px.

**에셋·상호작용·모션**: 없음(링크 둘). 0바이트.

---

### S11. 지금, 메뉴바에. `#install` — 설치(bg-1 띠)

**목적**: 바로 설치. DMG 가 주, brew 와 zip 이 보조, 아이폰은 옆에. 누른 뒤에도 막다른 골목이 없게.

**카피**
- H2: **지금, 메뉴바에.**
- Mac 묶음(시각적으로 숨긴 `<h3>Mac</h3>`)
  - 주 버튼: **aing-check.dmg 다운로드**(`/api/download`). 릴리스 API 에 DMG 가 없을 때만 **aing-check.zip 다운로드**(`/api/download?file=zip`)
  - 메타(`t-small` `--ink-2`): **{버전} 버전, {크기}MB. macOS 14 Sonoma 이상, Apple Silicon·Intel 모두 돼요. Apple 공증을 받은 앱이에요.** (기본값 "0.3.47 버전, 30.0MB.")
  - 라벨(`t-small` `--ink-1` 600): **터미널이 편하다면**
  - 명령 상자: `$ brew install yehsung/check/aing-check` + [**복사**] → **복사했어요**
  - 작은 줄: 업데이트는 `brew update && brew upgrade --cask aing-check` 한 줄이고, 끝나면 앱이 다시 켜져요. (수리 단계 2026-10-12: 앱 [명령 복사]·README 현재 문구 — `brew upgrade` 만으로는 탭이 낡았을 때 '이미 최신'으로 끝난다)
  - 텍스트 링크: **GitHub Releases에서 zip으로 받기** → `https://github.com/yehsung/check/releases/latest`
- iPhone 묶음(숨긴 `<h3>iPhone</h3>`): App Store 배지 · (desk) QR 112 · 작은 줄 **iOS 18 이상, 무료예요. 근무 시작·종료는 맥에서 해요.**
- 팀 참여(숨긴 `<h3>팀 참여</h3>`, 진짜 순서라 번호를 쓴다, `<ol>`)
  1. **가입** — 별명·이메일·비밀번호로 가입해요.
  2. **팀 코드** — 팀원에게 받은 팀 코드를 넣으면 들어갈 팀 이름이 미리 떠요. 팀이 없으면 새 팀을 만들고, 생긴 코드를 동료에게 건네요.
  3. **메뉴바** — 그다음부턴 메뉴바에서 근무 시작만 누르면 돼요.
- 업데이트 한 줄: ▓메뉴바 아이콘(점)▓ **새 버전이 나오면 메뉴바 아이콘에 작은 점이 떠요. brew로 설치했다면 지금 업데이트 한 번이면 설치하고 다시 켜지고, DMG로 받았다면 여기서 새 DMG를 받아 덮어쓰면 돼요.** + ▓"새 업데이트가 있어요!" 말풍선 렌더▓ (수리 단계 2026-10-12: 앱 안 [지금 업데이트]는 brew 설치에서만 동작 — README §설치 · docs/team-install.md 방법 B. 이 페이지의 주 경로가 DMG 라 갈라 쓴다)

**다운로드를 누른 뒤(installHint, 같은 자리에서 바뀜 — Arc 패턴)**: 주 버튼과 메타 자리가 세 단계로(진짜 순서, `<ol>`):
1. 받은 파일을 열어요.
2. aing-check 아이콘을 Applications 폴더로 끌어다 놓아요.
3. 실행하면 메뉴바 오른쪽 위에 이게 떠요. ▓`ui/menubar-off` 라벨 렌더(지금 이 페이지 띠에 있는 그것)▓
- 아래 작은 링크: **다운로드가 시작되지 않았다면 다시 받기**(같은 `/api/download`)
- zip 으로 떨어진 경우 1·2: "받은 zip을 열면 aing-check 앱이 나와요." / "앱을 Applications 폴더로 옮겨요."
- DMG 창 스크린샷은 그리지 않는다(실제 화면이 확정되면 그것으로만 교체 가능).
- "경고 없이 열려요" 류 문장은 쓰지 않는다(DMG 서명·공증·스테이플 확인 전).

**레이아웃**
```
desk (bg-1 띠, 위아래 112)
 80
   지금, 메뉴바에.                                                 (H2)
   [ aing-check.dmg 다운로드 ]                        [App Store 배지]
   0.3.47 버전, 30.0MB. macOS 14 Sonoma 이상, …       ▣ QR 112 (흰 타일, --r-window)
                                                      iOS 18 이상, 무료예요. 근무 시작·종료는 맥에서 해요.
   터미널이 편하다면
   ┌──────────────────────────────────────────────┐
   │ $ brew install yehsung/check/aing-check  [복사] │ ← --surface, --r-code, t-code
   └──────────────────────────────────────────────┘
   업데이트는 … 한 줄이고 …
   GitHub Releases에서 zip으로 받기

   1  가입                 2  팀 코드               3  메뉴바          ← 3열, 번호 Pretendard 800 20px --ink-3
      별명·이메일…            팀원에게 받은…           그다음부턴…

   ▓•▓ 새 버전이 나오면 …   ▓새 업데이트가 있어요!▓
 Mac 묶음 1–7열 · iPhone 묶음 9–12열. 묶음을 상자로 감싸지 않는다(정렬과 여백으로만).
phone: H2 / (iPhone 방문자면 iPhone 묶음 먼저 + Mac 묶음 머리에 [Mac 링크 보내기]) / Mac 묶음 / 팀 참여 세로 / 업데이트 줄
```
- 명령 상자는 phone 에서 줄바꿈 허용(`white-space: pre-wrap; overflow-wrap: anywhere` + 각 `/` 뒤 `<wbr>` — 수리 단계: `break-all` 은 'chec|k' 처럼 낱말 가운데서 끊었다), 가로 스크롤 없음.

**에셋**: `ui/menubar-off` · `ui/menubar-icon-dot` · `ui/bubble-update` · 배지 · QR.

**상호작용**
| 사용자 | 결과 |
|---|---|
| 주 버튼 | `/api/download`(또는 `?file=zip`)로 이동 + `installClicked('install')` → 블록이 설치 안내로(높이 200ms, 내용 120ms 교차). 새로고침해도 sessionStorage 로 유지 |
| [복사] | `navigator.clipboard.writeText('brew install yehsung/check/aing-check')` → 버튼 **복사했어요**(2초 뒤 **복사**) + 알림 "복사했어요". 실패하면 명령 글자를 선택 상태로 만들고 작은 줄 "⌘C로 복사하세요" |
| Mac 링크 보내기(iPhone) | S1 과 같은 동작 |
| 배지·QR | App Store 새 탭 |

**접근성**: 명령 상자 `<code>`, 복사 버튼 `aria-label="brew 설치 명령 복사"`. 다운로드 링크의 접근 이름에 형식·크기 포함("aing-check.dmg 다운로드, 30.0MB").

---

### S12. 자주 묻는 것. `#faq`

**목적**: 설치 직전 질문을 정리. 수치는 질문이 물을 때만 여기서.

**카피**: H2 **자주 묻는 것.** 문항(첫 문항만 열린 채, 한 번에 하나):
1. **요금이 있나요?** — 무료예요. 앱 안에서 현금 결제를 받지 않고, 루비는 일하거나 게임해서 모으는 앱 안 재화라 현금으로 사거나 바꿀 수 없어요.
2. **어떤 기기에서 쓰나요?** — 맥은 macOS 14 이상이면 Apple Silicon·Intel 모두 돼요. 아이폰은 iOS 18 이상이에요. 근무 시작·종료는 맥에서 하고, 아이폰에서는 현황·메시지·할 일·게임을 써요.
3. **팀 코드는 어디서 받나요?** — 이미 쓰는 팀원에게 받아요. 팀원 누구나 팀 카드의 열쇠 버튼에서 코드를 보고 복사할 수 있어요. 팀이 없으면 가입할 때 '새 팀 만들기'를 누르면 코드가 바로 생겨요. 공개된 팀 목록은 없어요.
4. **화면이나 키 입력을 보나요?** — 아니요. 스크린샷·키보드 입력·마우스 움직임·앱과 웹 사용 기록을 모으지 않고, 손쉬운 사용·화면 기록·카메라·마이크·위치 권한도 요청하지 않아요. 근무 중에만 '마지막으로 키·클릭·스크롤을 한 시각' 하나를 보내요.
5. **누가 내 근무 시간을 보나요?** — 근무 시작·종료 시각과 근무 기록은 같은 팀 안에서만 보여요. 콕 찌르기 목록·AI 토큰 순위판·미니게임 순위표는 앱을 쓰는 모두가 보는 화면이라 별명·아바타·지금 근무 중인지가 보여요. 토큰과 미니게임은 설정에서 비공개로 바꿀 수 있어요.
6. **데이터는 어디에 저장되나요?** — 근무 기록·팀·프로필 같은 팀 데이터는 서버(Supabase)에, 로그인 토큰은 macOS 로그인 키체인에, 캐릭터 위치 같은 화면 설정은 이 맥에만 있어요. 메시지는 24시간, 콕 기록은 7일이 지나면 서버에서 지워져요.
7. **자동 근무 시작을 끄고 싶어요.** — 설정 → 일반 → '자동 근무 시작' 스위치를 끄면 돼요. 잘못 시작됐을 땐 그냥 근무 종료를 누르면 돼요.
8. **근무 종료를 깜빡하고 퇴근했어요.** — 괜찮아요. 맥이 잠들면 덮은 시각으로, 신호가 끊기면 마지막 신호 시각으로, 오래 아무것도 만지지 않으면 마지막으로 만진 시각으로 근무가 정리돼요. 자리를 비운 시간은 근무로 세지 않아요.
9. **계정을 지우려면요?** — 아이폰 앱에서 나 → 설정 → 계정 삭제로 바로 지울 수 있어요. 맥만 쓴다면 설정 → 제보로 요청해 주세요. 근무 기록·메시지·할 일·캐릭터·루비·순위 기록이 함께 사라지고 되돌릴 수 없어요.
10. **AI 리밋을 보려면 로그인 정보가 밖으로 나가나요?** — 아니요. 이 맥에 이미 있는 각 도구의 로그인 정보로 그 도구의 서버에 사용률만 물어봐요. 로그인 정보는 이 맥을 벗어나지 않고, 아잉체크 서버에는 퍼센트와 초기화 시각 같은 숫자만 올라가며 나만 봐요. 끈 도구는 로그인 정보도 읽지 않아요.
- 센터(서울/부산) 문항은 **미게재**.

**레이아웃**: 한 열, 왼쪽 정렬, 최대 폭 760px(desk 1–8열). H2 아래 40px. 행: 위아래 패딩 22, 행 사이 `--line` 1px(첫 행 위·마지막 행 아래 포함). 질문 `t-faq-q`, 답 `t-body` `--ink-2` 최대 36em, 열린 행 바탕 `--surface`(반지름 0, 좌우로 띠처럼 −16px 확장). 오른쪽 끝 **디스클로저 삼각형**(macOS 목록의 ▸, CSS `::after`, 10px, `--ink-3`)이 열리면 90° 회전 180ms ease-out(`+`→`×` 는 쓰지 않는다).

**구현**: 네이티브 `<details name="faq" id="faq-{n}">` + `<summary>`(1번 `open`). 열림 애니메이션은 `::details-content` + `interpolate-size: allow-keywords` 지원 브라우저에서만(그 외 즉시). `location.hash` 가 `#faq-{n}` 이면(로드·hashchange) 그 문항을 열고 스크롤. 같은 문장으로 `FAQPage` JSON-LD 를 `<script type="application/ld+json">` 에 넣는다.

**접근성**: summary 기본 버튼 역할. 삼각형은 읽히지 않음. 닫힌 답 속 링크는 탭 순서에서 빠진다(네이티브).

---

### S13. 메뉴바에, 아잉 하나. `#closing` — 클로징(17:02 퇴근)

**목적**: 처음(근무 시작)과 끝(근무 종료)을 맞물리고 하루를 장부대로 닫는다. 마지막 다운로드.

**카피**
- 시각 표식: **17:02**
- H2(`t-closing`): **메뉴바에, 아잉 하나.**
- 리드: 맥에 설치하고, 팀 코드를 나눠 주세요.
- 퇴근 전 버튼(보조 캡슐, `--line-strong` 테두리, `--ink-1`): **근무 종료**
- CTA 줄(`data-companion-avoid`): **Mac용 다운로드**(주) · App Store 배지 · (보조 캡슐) **brew 명령 복사** → **복사했어요**

**레이아웃**
```
desk (위아래 128, 왼쪽 정렬 유지)
17:02  메뉴바에, 아잉 하나.            (t-closing 80px)
       맥에 설치하고, 팀 코드를 나눠 주세요.

       ▓😊 06:42▓  (근무 종료)         ← 실제 라벨 렌더를 3배(높이 66px, 231.6×66)로 + 페이지 보조 버튼
       ── 퇴근 뒤 ──
       ▓😟 오프▓                         ← 같은 자리, off 렌더 3배(184.5×66)
       ┌▓ 헤더 카드 header_off_1702 316×107 ▓┐  ← "근무종료 06:42 ⌁[근무 시작] 이번 주 26시간 20분 66%", --r-window, --shadow-window
       └▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓┘

       [ Mac용 다운로드 ]  [App Store]  ( brew 명령 복사 )
                                                                              ◎ "수고했어!" → 꾸벅 → 사라짐
phone: 17:02 / H2 / 리드 / 라벨 3배(폭 ≤ 100%) + ◎ 인라인 무대(라벨 오른쪽) / (근무 종료) / 헤더 카드 폭 min(100%, 316) / CTA 세로
```

**에셋**: `ui/menubar-0642-lg` · `ui/menubar-off-lg` · `ui/header-off-1702` · `char/aing-commute-end`(신규) · `char/aing-commute-start` · `ui/bubble-commute-end` · `ui/bubble-commute-start`.

**상호작용**
- 진입: 장면 evening → 띠 라벨·확대 라벨 06:42, 캡슐 06:42. (work=off 로 건너뛰어 왔으면 조용히 근무 중.)
- **근무 종료** → `pressEnd()`: 버튼 눌림 100ms → 라벨(띠·확대) 오프 즉시 → 코너 아잉 commute_end(앞으로 20° 꾸벅, 1.2초) + "수고했어!"(2초) → 끝나면 150ms 선형으로 사라지고 언마운트 → 헤더 카드가 불투명 120ms + 높이 200ms 로 나타난다. 근무 종료 버튼은 숨는다. 포커스는 헤더 카드의 [근무 시작] 핫스팟으로.
- 헤더 카드 렌더 속 **[근무 시작]**(`restartButton`) → `restart()`: 라벨 **06:42**(앱: 쉬었다 재개해도 오늘 총합에서 이어진다 — 그래서 00:00 이 아니라 06:42 가 사실이다), 코너 아잉 commute_start + "오늘도 화이팅!", 헤더 카드 접힘(불투명 160ms + 높이 200ms), 근무 종료 버튼 복귀.
- 종료 뒤 띠 라벨을 누르면(desk) `popover-off-1702`(근무종료 06:42 · 3명 근무중) 정지 판.
- 종료 상태로 위 섹션으로 올라가면 조용히 근무 중으로 되감긴다(§3.2 setActiveSection).

**모션**: 꾸벅 한 번(반복 없음). 감속 모션: 말풍선 + 즉시 사라짐.

**성능**: commute_end(≈110KB)는 이 절 600px 전.

**접근성**: 확대 라벨 `<img alt="메뉴바 라벨, 근무 중 06:42">`(퇴근 뒤 "메뉴바 라벨, 오프"). 근무 종료 버튼 `aria-describedby` 로 라벨 상태 연결. 헤더 카드 핫스팟 `aria-label="근무 시작"`. 알림 "근무를 마쳤어요. 수고했어!" / "다시 근무를 시작했어요."

---

### S14. 푸터

**카피**
- 한 줄(`t-small` `--ink-2`): 아잉체크(aing-check)는 작은 Mac 팀을 위한 메뉴바 근무 타이머예요.
- 링크(`t-micro` `--ink-2`, 호버 `--ink-1`, 간격 24, 가운뎃점 없음): **지원** `https://yehsung.github.io/check/` · **개인정보 처리방침** `https://yehsung.github.io/check/privacy` · **이용약관** `https://yehsung.github.io/check/terms` · **GitHub** `https://github.com/yehsung/check` · **버그·요청** `https://github.com/yehsung/check/issues` · **글꼴 라이선스** `/licenses`
- 저작권(`t-micro` `--ink-3`): © 2026 아잉체크

**레이아웃**: 위 `--line` 1px, 패딩 48(phone 40)/64. 왼쪽 앱 아이콘 24px + 한 줄, 아래 링크 줄(phone 은 세로 목록), 맨 아래 저작권. 이메일 문의 주소는 넣지 않는다(이슈로 받는다).

**`/licenses` 페이지**: H1 "글꼴 라이선스", Pretendard·JetBrains Mono 의 SIL OFL 1.1 전문(`P/fonts/LICENSE-*.txt` 내용을 그대로), 같은 내비·푸터.

---

### 공통 C. 코너 아잉(전역 층 `AingCorner`, desk·tab)

- **근무 중일 때만 존재**: work=on 이 되면 마운트(button·auto·restart 는 commute_start 로 등장, jump 는 120ms 페이드인), commute_end 가 끝나면 언마운트. phone 모드에서는 그리지 않는다(섹션 인라인 무대가 대신).
- 상자: 영상 HERO 박스(캔버스 [424,544,1308,1580])를 앱 실제 크기로 — **124.6 × 150.5 CSS px**(tab 0.9배). 표시 배율 d = 상자폭/654.
- 자리: 기본 `right: 20px; bottom: 16px`(+ `env(safe-area-inset-*)`), `z-index: var(--z-corner)`. desk 에서 스파인이 열려 있고 `스파인 아랫변 + 24 > 뷰포트높이 − 16 − 150.5` 이면 스파인 왼쪽으로: `right: 16 + 414·s + 24`. 자리 이동은 transform 240ms ease-out. 그래도 겹치면 0.85배.
- 회피: 화면 안의 `[data-companion-avoid]` 요소 사각형과 겹치면 겹친 만큼 + 12px 위로(최대 40vh) 240ms. 스크롤 중 검사는 rAF 120ms 쓰로틀.
- 층(CharacterStage, §3.4): idle · 반응 · 캡슐 · 말풍선.
  - 말풍선 좌상단 = 캔버스 (323,981) → 상자 기준 **(−9.6, 41.6)px**, 크기 = 말풍선 @3x px ÷ 3(= pt, 앱 실제 크기).
  - 캡슐 = 캔버스 (787,1686) 527×239 → **(34.6, 108.8)px, 50.2×22.8px**. HTML(앱 코드 스펙): `font: 600 12px/1 ui-monospace; padding: 3px 8px; color: #fff; background: rgba(0,0,0,.45); border: .5px solid rgba(255,255,255,.2); border-radius: 999px; box-shadow: 0 1px 2px rgba(0,0,0,.35)`, 상자 가운데 정렬. 울트라 중 숨김.
  - 몸통 히트 = 타원 중심 (59.8, 103.2)px, 반지름 48.7×46.0px(`clip-path: ellipse()` 투명 버튼) — 몸 위 클릭만 받는다(앱: 주변 여백은 뒤로 통과). `aria-label="아잉, 오늘 할 일 열기"` → `toggleTodo()`.
  - message-gureum 말풍선은 버튼(`aria-label="구름빵 메시지 열기"`) → `msgOpen()`.
- 숨기기: 상자 왼쪽 위(−4, −4)에 지름 24px 원형 버튼(히트 32px, `--surface-2` 바탕, CSS 가로 막대 하나). desk 는 코너 호버·포커스 때만, tab 은 늘(불투명 .7). `aria-label="아잉 숨기기"` → `hideCorner()`. 부르기 알약은 없다 — S7 버튼·클로징 재시작·받은 콕(잠깐)이 되돌린다.
- 포커스 순서: 문서 끝(LiveAnnouncer 앞).

### 공통 U. 울트라 오버레이(`AingCorner` 소유)
- 앱 사실: 받는 사람 화면을 보낸 사람 캐릭터가 덮고 떤다. 정사각 = 화면 짧은 변의 98%, 정중앙. 민트별은 아잉을 입었으니 덮는 것도 아잉이다.
- `position: fixed; inset: 0; z-index: var(--z-ultra); background: transparent; pointer-events: auto`(화면을 어둡게 하지 않는다). 한 변 S = 0.98 × min(100vw, 100svh). 영상 `char/aing-ultra`(인코딩 박스 [260,48,1680,1476] / 캔버스 2160)을 정사각 안 `left: 260/2160·S; top: 48/2160·S; width: 1680/2160·S; height: 1476/2160·S`. 말풍선 ultra-mint(239×64.3)를 정사각 윗변 + 56px, 가로 가운데(수리 단계: 세로로 긴 화면에서 정사각 위 빈자리가 말풍선 높이 + 16 이상이면 정사각 바로 위 −높이 − 8 — 390 에서 +56 은 눈을 덮었다).
- **72프레임(2.4초) 재생** 뒤 불투명 160ms 선형 퇴장. 클릭·탭·Esc·아무 키·wheel·touchmove 중 하나라도 오면 즉시 퇴장. 코너 아잉(내 캐릭터)은 그대로, idle 일시정지.
- 영상이 준비되지 않았으면 최대 2.5초 기다리고, 그래도 안 되면 포스터 + 말풍선 3초. 감속 모션: 포스터 + 말풍선 3초(이동 없음).
- `role="dialog" aria-modal="false" aria-label="민트별님의 울트라 찌르기"`, 시각적으로 숨긴 닫기 버튼, 포커스를 옮기지 않는다(장난 알림). 알림 "민트별님의 울트라 찌르기!".

### 공통 T. 할 일 보드(`AingCorner` 소유)
- 렌더 `ui/todo-board`(300×400pt, 반투명 창 판). desk·tab: 코너 상자 왼쪽 위에 연다(보드 오른쪽 아래 = 코너 상자 왼쪽 위 + (−8, +40)), 화면 밖이면 위로 붙인다. phone: 아래 시트(폭 `100vw − 32`, 배율 맞춤, 뒤 깔개 `--scrim-sheet`).
- 수리 단계: 렌더가 95% 불투명이라 뒤 UI 가 또렷이 비친다(앱은 비브런시 블러) → 창 상자에 `--bg-0` 불투명 받침. desk 에서 보드가 열린 동안 스파인은 접힌다(§3.3 `spineOpen`) — 900 높이에서 '스파인 아래 보드'(S7 와이어)는 들어가지 않고, 보드를 스파인 왼쪽으로 옮기면 아잉에서 300px 넘게 떨어져 '캐릭터에 붙은 보드' 사실이 약해진다.
- 열림 220ms: 불투명 120ms 선형 + scale .97→1 220ms ease-out(origin 오른쪽 아래, 시트는 translateY). motion `AnimatePresence`. 닫힘: Esc, 바깥 클릭, 렌더 속 × 핫스팟(`todoClose`), 아잉 재클릭, S7 버튼.
- `role="dialog" aria-label="오늘 할 일" id="todo-board"`, 열면 포커스를 닫기 핫스팟으로, 닫으면 연 컨트롤로 복귀. 렌더는 정지 판이라 항목을 체크할 수 없다(체크는 S9 위젯에서만 — 그 렌더가 있다).

### 공통 I. 인라인 무대(phone, `AingStageInline`)
- 같은 층 구조(CharacterStage), 고정하지 않고 섹션 안에 놓인다. 크기: `inline` 110×132.9, `inline-lg` 180×217.4.
- 자리: S1 팝오버 왼쪽 아래 걸침 · S2 본문 아래(inline-lg) · S4·S5 렌더 오른쪽 아래 걸침(무대 오른쪽 = 렌더 오른쪽 − 8, 아래 = 렌더 아래 + 24) · S7 렌더 아래 왼쪽(누르면 할 일 시트) · S13 확대 라벨 오른쪽.
- 활성 섹션의 무대 하나만 영상을 마운트하고 반응을 받는다. 나머지는 아무것도 그리지 않는다. work≠on 이면 없음.

### 공통 K. 틱 띠
- 원본 12장의 바뀌는 열만 잘라 만든 가로 띠 `ui/popover-tick-strip`(180×1010 × 12칸). `popover-on` 판 위 pt (96, 48) 90×505 상자에 `background-position` 으로 1초마다 칸 교체(0ms), 11초에서 멈춤. 탭이 숨으면 멈추고 돌아오면 경과 시간 칸으로(최대 11).

### 공통 P. 폰 셸(코드로 그림)
- 화면 비율 402:874. 화면 모서리 반경 0.155·W, 베젤 0.035·W, 셸 바깥 반경 = 화면 반경 + 베젤, 셸 색 #0a0a0c, 바깥 1px rgba(255,255,255,.10), 안쪽 1px rgba(255,255,255,.06), `--shadow-window`. 측면 버튼 없음.
- 다이내믹 아일랜드는 CSS 로 덮는다: 폭 0.315·W, 높이 0.093·W, 화면 위 0.028·W, 완전 둥근 검정(스틸에 아일랜드가 없다).
- `div.shell > div.screen(overflow: hidden) > img(1% 확대, object-fit: cover) + div.island`.

---

## 5. 컴포넌트 목록(이름·역할 — props·소유권 전체는 PLAN §3–§4)

| 층 | 이름 | 역할 |
|---|---|---|
| 공용 프리미티브 `components/ui/` | `Button` · `DownloadCTA` · `AppStoreBadge` · `QrCode` · `TextLink` · `SectionShell`(+`Beat`) · `Headline` · `TimeMark` · `MacWindowShell` · `RenderImage` · `RenderStack` · `Hotspot` · `PanelSlot` · `Segmented` · `CopyButton` · `CommandBox` · `Bubble` · `TimerCapsule` · `PhoneShell` · `TickStrip` · `CharacterStage` · `AingStageInline` · `LiveAnnouncer` · `VisuallyHidden` · `PlatformScript` | 섹션이 조립에 쓰는 부품. 디자인 토큰·상태 기계·에셋 메타를 숨긴다 |
| 시퀀스 플레이어 `components/SpritePlayer.tsx` | `SpritePlayer`(video·sheet 두 백엔드) | 캐릭터 알파 영상과 틱 띠를 같은 메타 형식으로 재생 |
| 전역 무대 `components/sections/` | `MenubarStage`(S0 + 스파인 + 라벨 정지 팝오버) · `AingCorner`(코너 + 울트라 + 할 일 보드) | 페이지 전체를 가로지르는 '기억에 남을 하나' |
| 섹션 `components/sections/` | `HeroAuto`(S1·S2) · `TeamPoke`(S3·S4) · `MessageGames`(S5·S6) · `CharacterRecords`(S7·S8) · `IphoneTrust`(S9·S10) · `InstallFaq`(S11·S12) · `ClosingFooter`(S13·S14, 이름 붙은 내보내기 `SiteFooter`) | 각자 default export, props 없음 |
| 상태 `lib/demo/` | `reducer` · `store` · `selectors`(scene·labelKey·panelFor·spineOpen·labelPanel) | §3 |
| 서버 `lib/release.ts`, `app/api/*` | `getRelease` · `/api/download`(302) · `/api/release`(JSON) | §8.5 |

---

## 6. 데이터 픽스처 (`landing/data/fixtures.ts` 전문)

모든 숫자는 렌더 속에 있다 — 라이브 데모가 숫자를 계산하는 곳은 없다. 픽스처는 렌더 키·좌표·문구·alt 다. 에셋 경로·픽셀 크기·캐시 버전은 내보내기 스크립트가 만드는 `data/generated/assets.json`(`asset(key)` 로 읽는다)에서 온다.

```ts
// landing/data/fixtures.ts
import assets from './generated/assets.json';
import sequences from './generated/sequences.json';
import bubbles from './generated/bubbles.json';

export type AssetKey = keyof typeof assets;
export const asset = (k: AssetKey) => assets[k] as { src: string; w: number; h: number; bytes: number };
export { sequences, bubbles };

export const PEOPLE = {
  me: { name: '새벽', character: 'aing' },
  team: [
    { name: '구름빵', character: 'jellyfish' }, { name: '달토끼', character: 'fox' },
    { name: '민트별', character: 'aing' }, { name: '호두과자', character: 'shiba' },
  ],
  others: [{ name: '보리차', character: 'squirrel' }, { name: '솜사탕', character: 'ghost' }, { name: '초코칩', character: 'ghost' }],
} as const; // 센터 정보는 넣지 않는다

export const LINKS = {
  download: '/api/download', downloadZip: '/api/download?file=zip',
  dmgLatest: 'https://github.com/yehsung/check/releases/latest/download/aing-check.dmg',
  zipLatest: 'https://github.com/yehsung/check/releases/latest/download/aing-check.zip',
  releases: 'https://github.com/yehsung/check/releases/latest',
  appStore: 'https://apps.apple.com/app/id6812768622', // 지역 코드 넣지 않음(CheckAppLinks.swift:16 과 같음)
  support: 'https://yehsung.github.io/check/', privacy: 'https://yehsung.github.io/check/privacy',
  terms: 'https://yehsung.github.io/check/terms', github: 'https://github.com/yehsung/check',
  issues: 'https://github.com/yehsung/check/issues', licenses: '/licenses',
} as const;
export const APP_STORE_ID = '6812768622';
export const BREW = { install: 'brew install yehsung/check/aing-check', upgrade: 'brew update && brew upgrade --cask aing-check' } as const;

export type LabelKey = 'off' | '0000' | '0100' | '0345' | '0345-newmsg' | '0642';
export const LABELS: Record<LabelKey, { asset: AssetKey; wPt: number; text: string }> = {
  off:           { asset: 'ui/menubar-off',          wPt: 61.5, text: '오프' },
  '0000':        { asset: 'ui/menubar-0000',         wPt: 77.2, text: '근무 중 00:00' },
  '0100':        { asset: 'ui/menubar-0100',         wPt: 77.2, text: '근무 중 01:00' },
  '0345':        { asset: 'ui/menubar-0345',         wPt: 77.2, text: '근무 중 03:45' },
  '0345-newmsg': { asset: 'ui/menubar-0345-newmsg',  wPt: 77.2, text: '근무 중 03:45, 새 메시지' },
  '0642':        { asset: 'ui/menubar-0642',         wPt: 77.2, text: '근무 중 06:42' },
}; // 높이 22pt. 클로징 확대판은 'ui/menubar-0642-lg' · 'ui/menubar-off-lg'(높이 66 CSS px)

export type PanelKey = 'popover-off'|'popover-on'|'popover-working'|'popover-newmsg'|'popover-off-1702'|'league'
  |'poke-list'|'poke-cooldown'|'poke-focus-1'|'poke-focus-2'|'message-composing'|'message-unread'|'message-read'
  |'character-pick'|'insights'|'token-month'|'token-last';
export const PANELS: Record<PanelKey, { asset: AssetKey; w: number; h: number; overlay?: 'tick' }> = {
  'popover-off':       { asset: 'ui/popover-off',       w: 414, h: 653 },
  'popover-on':        { asset: 'ui/popover-on',        w: 414, h: 653, overlay: 'tick' },
  'popover-working':   { asset: 'ui/popover-working',   w: 414, h: 653 },
  'popover-newmsg':    { asset: 'ui/popover-newmsg',    w: 414, h: 653 },
  'popover-off-1702':  { asset: 'ui/popover-off-1702',  w: 414, h: 653 },
  'league':            { asset: 'ui/league',            w: 414, h: 600 },
  'poke-list':         { asset: 'ui/poke-list',         w: 414, h: 654 },
  'poke-cooldown':     { asset: 'ui/poke-cooldown',     w: 414, h: 654 },
  'poke-focus-1':      { asset: 'ui/poke-focus-1',      w: 414, h: 679 },
  'poke-focus-2':      { asset: 'ui/poke-focus-2',      w: 414, h: 679 },
  'message-composing': { asset: 'ui/message-composing', w: 414, h: 572 },
  'message-unread':    { asset: 'ui/message-unread',    w: 414, h: 603 },
  'message-read':      { asset: 'ui/message-read',      w: 414, h: 603 },
  'character-pick':    { asset: 'ui/character-pick',    w: 414, h: 495 },
  'insights':          { asset: 'ui/insights-popover',  w: 414, h: 695 },
  'token-month':       { asset: 'ui/token-month',       w: 414, h: 682 },
  'token-last':        { asset: 'ui/token-last',        w: 414, h: 682 },
};

export type Rect = { x: number; y: number; w: number; h: number }; // 렌더 pt, 왼쪽 위 원점
export type HotspotShape = 'capsule' | 'round' | 'circle';
export const HOTSPOTS = {
  startButton:   { panels: ['popover-off'],                                   x: 222.0, y: 27.0,  w: 93.7, h: 39.7, shape: 'capsule' }, // @3x (666,81)-(947,200)
  railTeam:      { panels: ['popover-working', 'league'],                     x: 337.7, y: 164.3, w: 64.3, h: 46.4, shape: 'round', r: 15 },
  railPokeMsg:   { panels: ['popover-newmsg', 'popover-working'],             x: 337.7, y: 62.3,  w: 64.3, h: 46.4, shape: 'round', r: 15 },
  pokeMint:      { panels: ['poke-list'],                                     x: 274.0, y: 314.0, w: 29.7, h: 29.7, shape: 'circle' }, // @3x (822,942)-(911,1031), 히트 44
  focusChip:     { panels: ['poke-list', 'poke-cooldown', 'poke-focus-1', 'poke-focus-2'], x: 106, y: 141, w: 56, h: 28, shape: 'capsule' }, // @3x (324,434)-(474,495)
  sendButton:    { panels: ['message-composing'],                             x: 268.0, y: 471.0, w: 47.7, h: 23.7, shape: 'capsule' }, // @3x (804,1413)-(947,1484)
  tokenPrev:     { panels: ['token-month'],                                   x: 68.3,  y: 141.0, w: 26.7, h: 26.7, shape: 'circle' },  // @3x (205,423)-(285,503)
  tokenNext:     { panels: ['token-last'],                                    x: 196.7, y: 141.0, w: 26.0, h: 26.7, shape: 'circle' },  // @3x (590,423)-(668,503)
  restartButton: { render: 'ui/header-off-1702', size: [316, 107],            x: 209.5, y: 15.0,  w: 94.5, h: 40.0, shape: 'capsule' }, // @4x (838,60)-(1216,220)
  todoClose:     { render: 'ui/todo-board', size: [300, 400],                 x: 266.0, y: 13.0,  w: 22.0, h: 22.0, shape: 'circle' },
  widgetRow:     { render: 'ios/widget-todos-large', size: [364, 382],        x: 8,     y: 105,   w: 340,  h: 44,   shape: 'capsule', r: 12 },
  phoneTabs: { size: [402, 874], y: 790, h: 60, w: 66, tabs: [
    { id: 'now', cx: 63, label: '지금' }, { id: 'messages', cx: 132, label: '메시지' }, { id: 'rankings', cx: 201, label: '순위' },
    { id: 'games', cx: 269, label: '게임' }, { id: 'me', cx: 338, label: '나' } ] },
  tick: { panel: 'popover-on', x: 96, y: 48, w: 90, h: 505 },
} as const; // 구현 때 링을 켜고 렌더 위에서 ±1pt 눈으로 확인

export type BubbleId = 'commute-start'|'autostart'|'poked-mint'|'message-gureum'|'commute-end'|'ruby'|'ultra-mint'|'update';
export const BUBBLE_TEXT: Record<BubbleId, { text: string; ms: number }> = {
  'commute-start':  { text: '오늘도 화이팅!', ms: 5000 },
  'autostart':      { text: '일하는 것 같아서 근무 시작했어요!', ms: 8000 },
  'poked-mint':     { text: '민트별님이 콕 찔렀어요!', ms: 6000 },
  'message-gureum': { text: '구름빵님: 커피 한잔 해요 ☕️', ms: 6000 },
  'commute-end':    { text: '수고했어!', ms: 2000 },
  'ruby':           { text: '루비 +3!', ms: 3200 },
  'ultra-mint':     { text: '민트별님의 울트라 찌르기!', ms: 0 },
  'update':         { text: '새 업데이트가 있어요!', ms: 0 },
}; // 이미지·크기·배치는 generated/bubbles.json(anchorCanvas [323,981], 캔버스 px = @3x px × 3.5)

export const REACTION_SEQ = {
  commute_start: 'aing-commute-start', commute_end: 'aing-commute-end', poked: 'aing-poked',
  message_received: 'aing-poked', milestone: 'aing-milestone', ultra_charged: 'aing-ultra-charged',
} as const;

export const CORNER = { // HERO 박스 출력 654×790 기준. 표시 배율 d = 상자폭/654
  heroOut: [654, 790], boxCorner: [124.6, 150.5], boxInline: [110, 132.9], boxInlineLg: [180, 217.4],
  bubbleAtOut: [-50.5, 218.5], capsuleAtOut: [181.5, 571], capsuleSizeOut: [263.5, 119.5], capsuleFontAtCorner: 12,
  bodyEllipseOut: { cx: 313.75, cy: 541.75, rx: 255.75, ry: 241.75 },
} as const;

export const PHONE: Record<'now'|'messages'|'rankings'|'games'|'me', { asset: AssetKey; alt: string }> = {
  now:      { asset: 'ios/now',             alt: '아이폰 지금 탭: 맥에서 근무 중 3:45:00, 이번 주 23시간 23분, 오늘 할 일 남은 4개' },
  messages: { asset: 'ios/messages',        alt: '아이폰 메시지 탭: 구름빵 "커피 한잔 해요"' },
  rankings: { asset: 'ios/rankings-league', alt: '아이폰 순위 탭 팀 리그: 2위 아잉 데모팀 평균 34시간 20분' },
  games:    { asset: 'ios/games',           alt: '아이폰 게임 탭: 타이밍 바, 플래피 아잉, 1:1 오목' },
  me:       { asset: 'ios/me-records',      alt: '아이폰 나 탭: 지난주 회고 40시간 30분 목표 달성, 최근 12주 근무와 AI 토큰, 지난주 근무 리듬' },
};

export const ALT: Record<string, string> = {
  'popover-off': '아잉체크 팝오버, 근무 전. 오늘 00:00, 이번 주 19시간 38분, 아잉 데모팀 5명 중 4명 근무중',
  'popover-on': '근무 시작 직후 팝오버. 근무중 00:00, 아잉 데모팀 5명 근무중',
  'popover-working': '팀 현황: 근무중 03:45, 이번 주 23시간 23분. 구름빵 04:37, 달토끼 04:23, 민트별 03:54, 새벽 03:45, 호두과자 04:06',
  'popover-newmsg': '팀 현황, 콕 / 메시지 버튼에 새 메시지 점',
  'popover-off-1702': '근무종료 06:42, 이번 주 26시간 20분, 아잉 데모팀 3명 근무중',
  'league': '팀별 이번 주: 1위 파도 커피단 평균 36시간 40분, 2위 아잉 데모팀 34시간 20분, 3위 종이 공방 18시간 25분',
  'poke-list': '콕 찌르기 목록: 구름빵, 달토끼, 민트별, 보리차, 솜사탕, 초코칩, 호두과자 모두 근무중. 울트라 3개',
  'poke-cooldown': '민트별을 방금 찔러 찌르기 버튼이 잠시 쉬는 중',
  'poke-focus-1': '집중 모드 1단: 3시간 동안 콕찌르기를 받지 않아요',
  'poke-focus-2': '집중 모드 2단: 끌 때까지 콕찌르기를 받지 않아요',
  'message-composing': '구름빵과의 대화. 구름빵 "커피 한잔 해요", 입력칸에 "좋아요! 배포하고 1층에서요"',
  'message-unread': '보낸 메시지 "좋아요! 배포하고 1층에서요" 옆에 안 읽음 1',
  'message-read': '구름빵이 읽어 1이 사라짐',
  'character-pick': '캐릭터 고르기: 아잉 착용 중, 여우, 유령, 해파리, 강아지, 다람쥐',
  'insights': '내 기록: 지난주 42시간 50분 목표 달성, 지난주 근무 리듬, 최근 12주 근무',
  'token-month': '이번 달 AI 토큰 순위: 1위 구름빵 5,014,407,391, 2위 새벽 2,376,382,712',
  'token-last': '지난달 AI 토큰 순위: 1위 구름빵 6,120,554,018, 2위 민트별, 3위 새벽',
  'minigame': '플래피 아잉 진행 중. 오늘 순위 1위 달토끼 41점, 2위 새벽 23점',
  'gomoku-board': '1:1 오목, 새벽(흑) 대 구름빵(백), 내 차례',
  'header-off-1702': '근무종료 06:42, 근무 시작 버튼, 이번 주 26시간 20분 66%',
  'todo-board': '오늘 할 일: 디자인 리뷰 피드백 반영하기, 주간 회고 초안 쓰기(어제), 팀 회의 안건 정리(3일 전), 점심 전에 PR 올리기(완료)',
  'widget-todos-large': '오늘 할 일 위젯: 남은 4개',
  'widget-todos-large-checked': '오늘 할 일 위젯: 주간 회고 초안 쓰기 완료, 남은 3개',
  'widget-today-small': '내 오늘 위젯',
};

export const ANNOUNCE = {
  start: '근무를 시작했어요. 오늘도 화이팅!', auto: '일하는 것 같아서 근무 시작했어요!',
  pokeIn: '민트별님이 콕 찔렀어요!', ultra: '민트별님의 울트라 찌르기!',
  focus1: '집중 모드 1단', focus2: '집중 모드 2단', focus0: '집중 모드 꺼짐',
  msg: '구름빵님: 커피 한잔 해요', sent: '보냈어요', read: '구름빵님이 읽었어요',
  end: '근무를 마쳤어요. 수고했어!', restart: '다시 근무를 시작했어요.',
  copied: '복사했어요', linkCopied: '링크를 복사했어요',
} as const;

export const TIMING = {
  autostartDelay: 700, passDwell: 400, pokeInDelay: 1200, ultraAfterPoke: 1000, ultraWaitMax: 2500,
  ultraFrames: 72, ultraFadeMs: 160, reducedUltraMs: 3000, msgArriveDelay: 800, readAfterSend: 1600,
  startPulseAt: 1200, reactionMinGap: 1200, copyResetMs: 2000, labelGlowMs: 600,
} as const;
```
`RELEASE_FALLBACK`(lib/release.ts): `{ version: '0.3.48', dmg: { name: 'aing-check.dmg', bytes: 29981558, mb: '30.0' }, zip: { name: 'aing-check.zip', bytes: 28268050, mb: '28.3' }, source: 'fallback' }` — 2026-10-12 실측(수리 단계에서 0.3.47 → 0.3.48 갱신). 릴리스마다 갱신한다.

---

## 7. 반응형 — 390 · 768 · 1024 · 1440

모드(CSS 변형과 JS 판정이 같은 문자열): `desk` = 폭 ≥1024 **그리고** 높이 ≥640 · `tab` = 폭 768–1023, 또는 폭 ≥768 이면서 높이 <640 · `phone` = 폭 <768.

| 섹션 | 1440(desk) | 1024(desk) | 768(tab) | 390(phone) |
|---|---|---|---|---|
| S0 띠 | 48, 링크 4 + CTA + 라벨(버튼) | 같음 | 48, 링크 4 + CTA + 라벨(이미지) | 48, 워드마크 + 라벨(이미지) + 플랫폼 CTA |
| 스파인 | 414×653 배율 1, 오른쪽 16 | 배율 1(768 높이에서 들어감), 글 열 48–546 | 없음 → 섹션마다 인라인 창(폭 min(100%, 380), 배율 380/414) | 없음 → 인라인(폭 min(100vw − 40, 380)) |
| 코너 아잉 | 124.6×150.5, 오른쪽 20·아래 16, 스파인과 겹치면 스파인 왼쪽 | 같음 | 고정 0.9배 | 없음 → 섹션 인라인 무대 |
| S1 | 글 왼쪽 + 매달린 팝오버, H1 88 | H1 62 | 글 위 → 인라인 팝오버, H1 ≈47 | H1 40, 접힘선 위에 CTA 와 [근무 시작] |
| S2 | 글만 + 구석 아잉 | 같음 | 글 + 코너 아잉 | 글 + inline-lg 무대 |
| S3 | 시각 표식 거터, 패널 교체 | 같음 | 표식 H2 위, 인라인 창 | 같음 |
| S4 | "콕." 112 | ≈82 | ≈61, 인라인 창 | 56, 인라인 창 + 무대, 울트라 정사각 382 |
| S5 | 패널 교체 + 왼쪽 버튼 | 같음 | 인라인 | 인라인 + 무대(말풍선 누르면 열기) |
| S6 | 창 700(1:1) | 창 700 | 창 폭 100%(≤700) | 창 폭 100%, 첫 값 1:1 오목 |
| S7 | 패널 + 보드는 코너 옆 | 같음 | 인라인 + 보드는 코너 옆 | 인라인 + 보드는 아래 시트 |
| S8 | GrassLight 456 왼쪽 열 + 두 박자 패널 | 456 | 456, 글 아래 | 폭 100%(배율 ≈1.15) |
| S9 | 글 1–5 · 폰 7–9(화면 300) · 위젯 10–12 | 화면 280 | 2열(글 / 폰 260), 위젯 글 아래 | 1열, 폰 260 가운데, QR 숨김 |
| S10 | statement 36 | 32 | 30 | 24 |
| S11 | Mac 1–7 · iPhone 9–12 · 팀 3열 | 같음 | Mac / iPhone 1열, 팀 3열 | 1열, 플랫폼 우선 순서, 팀 세로 |
| S12 | 한 열 760 | 같음 | 전폭 | 전폭 |
| S13 | 왼쪽 정렬, 확대 라벨 66px | 같음 | 같음 | 확대 라벨 폭 ≤100%, 무대 옆 |
| S14 | 한 줄 링크 | 같음 | 두 줄 | 세로 목록 |

가로 스크롤 0(390 에서 `document.documentElement.scrollWidth === 390`). 터치 히트 최소 44×44(핫스팟은 시각 영역보다 넓게, 서로 겹치지 않게).

---

## 8. 성능 · 로딩 · 형식 · 플랫폼 · 메타

### 8.1 예산
| 구간 | 예산 | 예상(크롬 / 사파리) |
|---|---|---|
| 첫 화면 전송 | ≤ 350KB | HTML+CSS ≈40 · JS ≈170(Next 15 + React 19 + 스토어; motion 은 첫 화면에서 로드하지 않음) · Pretendard 서브셋 ≈60 · popover-off 39 · 라벨 5 · 배지 9 · 아이콘 2 = **≈325KB** |
| load 뒤 idle 미리 받기 | ≤ 400KB | popover-on 40 · 틱 띠 89 · commute_start 148/143 · idle 포스터 18 · 말풍선 2장 16 = ≈311KB |
| 페이지 전체 | ≤ 4.5MB(상한 6MB) | 렌더 ≈1.22MB · 영상 ≈2.19MB(idle 760·commute_start 148·commute_end 110·poked 296·milestone 240·ultra_charged 295·ultra 340) · 포스터 54 · 폰·위젯 ≈220 · 글꼴 ≈75 · JS·CSS ≈210 = **≈4.0MB**(사파리 +≈0.15MB) |
| 모바일 LCP | ≤ 2.5s(4G) | desk LCP = H1 텍스트(SSR, 서브셋 글꼴 preload, swap). phone·tab LCP = 히어로 인라인 팝오버 popover-off(145k px² > H1 19.8k px²) → `fetchpriority="high"`(수리 단계) |
| CLS | ≤ 0.05 | 모든 렌더 width/height 명시, 플랫폼 CTA 는 인라인 스크립트로 첫 페인트 전에 결정 |
| 스크롤 중 장기 작업 | 0 | IO 문턱 + rAF 한 개(잔디) + 회피 검사 120ms 쓰로틀 |

### 8.2 로딩 순서
1. 첫 페인트: 띠, H1, 리드, CTA, popover-off(eager), 라벨, 배지, 글꼴 preload 1개.
2. load + `requestIdleCallback`: popover-on, 틱 띠, commute_start, idle 포스터, 말풍선(commute-start·autostart), popover-working.
3. 근무 시작 의도([근무 시작] pointerenter/touchstart) 또는 S2 가 600px 안: idle 영상.
4. 섹션 접근(IO rootMargin 600px): 그 섹션의 렌더·영상. 울트라만 rootMargin 100svh.
5. JetBrains Mono 서브셋(`next/font/local` preload false). 수리 단계 P-5: 크롬은 화면 밖이라도 DOM 에 배치된 글자에 쓰인 웹폰트를 바로 받으므로 '자연 지연'은 일어나지 않는다 — 4.6KB(ASCII)라 첫 화면에서 받는 것을 받아들인다(근접 시 글꼴 갈아 끼우기는 들이지 않음).
6. 이미지는 `loading="lazy"` + 명시 width/height + `decoding="async"`. `next/image` 최적화를 타지 않게 `<img>`(RenderImage)만 쓴다.

### 8.3 형식
- 캐릭터 = 알파 영상 두 벌(VP9 webm / HEVC mov) + 포스터 webp. JS 로 형식 선택(§3.4). 스프라이트 시트는 틱 띠에만.
- 렌더 = webp q80(@3x → @2x), 조각(라벨·말풍선) q90 alphaQuality 100, 잔디는 @3x 원본 크기 q88.
- 글꼴 서브셋: Pretendard 800 은 랜딩 소스(`app/**`, `components/**`, `data/**`)에 나오는 글자 전부(≈55–70KB), JetBrains Mono 는 ASCII(≈15KB).
- 모션 라이브러리 `motion`(framer-motion 12)은 할 일 보드·폰 시트·울트라의 `AnimatePresence` 에만, `LazyMotion` + `domAnimation`, 해당 컴포넌트를 `next/dynamic` 으로.

### 8.4 플랫폼 판별(깜빡임 없이)
- `<head>` 인라인 스크립트(≈250바이트)가 첫 페인트 전에 `document.documentElement.dataset.platform = 'mac' | 'ios' | 'other'`. 규칙: `/iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)` → ios, `/Macintosh|Mac OS X/.test(ua)` → mac, 그 외 other.
- CTA 는 세 벌을 다 SSR 하고 CSS 로 하나만 보인다(`html[data-platform=ios] .cta-mac { display: none }` …). 서버 동적 렌더 없음(정적 + ISR).
- `<meta name="apple-itunes-app" content="app-id=6812768622">` — iOS 사파리 스마트 배너.

### 8.5 릴리스·다운로드
- `getRelease()`: `fetch('https://api.github.com/repos/yehsung/check/releases/latest', { next: { revalidate: 3600 }, signal: AbortSignal.timeout(3000), headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'aing-check-landing' } })` → `tag_name`(v 떼기), `assets[]` 의 `aing-check.dmg`·`aing-check.zip` `size`·`browser_download_url`. 크기 표기는 Finder 와 같은 10진 MB 소수 한 자리(29,959,634B → "30.0"). 실패·타임아웃이면 `RELEASE_FALLBACK`. 환경 변수 `GITHUB_TOKEN` 이 있으면 Authorization 헤더(없어도 동작).
- `/api/download`(GET): `?file=zip` 이면 zip, 아니면 DMG(릴리스에 DMG 가 없으면 zip). 302 → `browser_download_url`(없으면 `releases/latest/download/<파일명>`). `Cache-Control: no-store`.
- `/api/release`(GET): `getRelease()` JSON, `Cache-Control: public, s-maxage=3600, stale-while-revalidate=86400`.

### 8.6 캐시·헤더(`vercel.json`)
- `/assets/(.*)`·`/fonts/(.*)`: `Cache-Control: public, max-age=31536000, immutable`. 파일이 바뀌면 `assets.json` 의 `src` 에 붙는 `?v=<sha1 앞 8자>` 가 바뀐다(이름을 손으로 바꾸지 않는다).
- `/assets/char/(.*)\.mov`: `Content-Type: video/quicktime` 명시. `.webm` 은 `video/webm`.

### 8.7 메타
- `<html lang="ko">`, `<title>아잉체크: 작은 Mac 팀을 위한 메뉴바 근무 타이머</title>`
- description: "근무 시작을 누르면 팀 전체에 바로 보여요. 맥 메뉴바에서 근무 시간을 재고, 아이폰에서도 팀 현황을 봐요."
- `themeColor: '#12131C'`, `metadataBase = SITE_URL`(`lib/site.ts`: `NEXT_PUBLIC_SITE_URL` → `https://${VERCEL_PROJECT_PRODUCTION_URL}` → `http://localhost:3000` — 수리 단계: 환경 변수 없이 배포해도 og:image 가 localhost 를 가리키지 않게). `alternates.canonical` '/' · `openGraph.url` · `openGraph.siteName` '아잉체크'. `/licenses` 는 자기 canonical·og 제목. `app/robots.ts`(전부 허용 + sitemap) · `app/sitemap.ts`(/, /licenses).
- OG/Twitter 이미지: `app/opengraph-image.png` 1200×630 — 히어로(근무 시작 뒤, desk)를 1440×756 뷰포트로 캡처(수리 단계: 클립 = 뷰포트라 코너 아잉과 "오늘도 화이팅!" 말풍선이 프레임 안에 든다). alt "아잉체크 팝오버와 메뉴바 라벨".
- 아이콘: `app/icon.png`(128 팔레트 PNG ≈6KB — 수리 단계 P-9, 예전 256 풀컬러 53KB) · `app/apple-icon.png`(180, `#12131C` 평탄화).
- 외부 분석 SDK 없음.

---

## 9. 에셋 목록 — 원본 절대 경로 → 출력(`/Users/yesung/check/landing/public/assets/…`)

규칙: 원본은 읽기만. 결과물은 커밋한다(HEVC 알파는 macOS videotoolbox 전용이라 Vercel 에서 만들 수 없다). 웹 경로는 `/assets/<출력>` + `?v=<해시>`. 키(`asset()` 인자)는 확장자를 뺀 출력 경로다(예 `ui/popover-off`). 크기·품질·프레임·예상 KB 의 최종 레시피는 PLAN §5.

### 9.1 맥 렌더(@3x → @2x webp)
| 출력 | 원본 |
|---|---|
| `ui/popover-off.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/popover_main_off_1020@3x.png` |
| `ui/popover-on.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/tick/popover_tick_on_00@3x.png` |
| `ui/popover-tick-strip.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/tick/popover_tick_on_00@3x.png` … `popover_tick_on_11@3x.png`(영역 (288,144) 270×1515) |
| `ui/popover-working.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/popover_main_working_1405@3x.png` |
| `ui/popover-newmsg.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/popover_main_working_1405_newmsg@3x.png` |
| `ui/popover-off-1702.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/popover_main_off_1702@3x.png` |
| `ui/league.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/league_week@3x.png` |
| `ui/poke-list.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/poke_list@3x.png` |
| `ui/poke-cooldown.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/poke_cooldown_mint@3x.png` |
| `ui/poke-focus-1.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/poke_focus_stage1@3x.png` |
| `ui/poke-focus-2.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/poke_focus_stage2@3x.png` |
| `ui/message-composing.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/message_thread_gureum_composing@3x.png` |
| `ui/message-unread.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/message_thread_gureum_unread@3x.png` |
| `ui/message-read.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/message_thread_gureum_read@3x.png` |
| `ui/minigame.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/minigame_window_flappy_playing_8rows@3x.png` |
| `ui/gomoku-board.webp` · `ui/gomoku-board-sm.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/gomoku_playing@3x.png`(크롭 x 0–1890, y 0–2100 — 오른쪽 '판돈' 칸 제외) |
| `ui/character-pick.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/character_pick_aing@3x.png` |
| `ui/todo-board.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/todo_board_today_opaque@3x.png` |
| `ui/insights-popover.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/insights_popover@3x.png` |
| `ui/grass-work-empty.webp` · `ui/grass-work-final.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/insights/work_grass_empty@3x.png` · `work_grass_final@3x.png` |
| `ui/grass-token-empty.webp` · `ui/grass-token-final.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/insights/token_grass_empty@3x.png` · `token_grass_final@3x.png` |
| `ui/token-month.webp` · `ui/token-last.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/token_board_month@3x.png` · `token_board_last_month@3x.png` |
| `ui/header-off-1702.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/header/header_off_1702@4x.png` |

### 9.2 메뉴바 라벨·아이콘·말풍선(조각)
| 출력 | 원본 |
|---|---|
| `ui/menubar-off.webp` · `ui/menubar-off-lg.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/menubar/menubar_aing_off_dark_alpha@10x.png` |
| `ui/menubar-0000.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/menubar/menubar_aing_working_0000_dark_alpha@10x.png` |
| `ui/menubar-0100.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/menubar/menubar_aing_working_0100_dark_alpha@10x.png` |
| `ui/menubar-0345.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/menubar/menubar_aing_working_0345_dark_alpha@10x.png` |
| `ui/menubar-0345-newmsg.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/menubar/menubar_aing_working_0345_newmsg_dark_alpha@10x.png` |
| `ui/menubar-0642.webp` · `ui/menubar-0642-lg.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/menubar/menubar_aing_working_0642_dark_alpha@10x.png` |
| `ui/menubar-icon-dot.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/menubar/menubar_aing_icon_working_dot@10x.png` |
| `ui/bubble-commute-start.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/bubble/bubble_commute_start@8x.png` |
| `ui/bubble-autostart.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/bubble/bubble_autostart@8x.png` |
| `ui/bubble-poked-mint.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/bubble/bubble_poked_mint@8x.png` |
| `ui/bubble-message-gureum.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/bubble/bubble_message_gureum@8x.png` |
| `ui/bubble-commute-end.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/bubble/bubble_commute_end@8x.png` |
| `ui/bubble-ultra-mint.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/bubble/bubble_ultra_mint@8x.png` |
| `ui/bubble-update.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/bubble/bubble_update@8x.png` |
| `ui/bubble-ruby.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/char/aing/_ui/bubble_00.png`(캔버스 층 크롭 (323,981)–(948,1290)) |

### 9.3 캐릭터 영상
| 출력 | 원본(프레임 시퀀스) |
|---|---|
| `char/aing-idle.{webm,mov}` · `char/aing-idle-15.{webm,mov}` · `char/aing-idle-poster.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/char/aing/idle_long/%04d.png`(432f) |
| `char/aing-commute-start.{webm,mov}` | `/Users/yesung/aing-check-promo/public/assets/v3/mac/char/aing/commute_start/%04d.png`(45f) |
| `char/aing-commute-end.{webm,mov}` | `/Users/yesung/aing-check-promo/public/assets/v3/mac/char/aing/commute_end/%04d.png`(36f) |
| `char/aing-poked.{webm,mov}` | `/Users/yesung/aing-check-promo/public/assets/v3/mac/char/aing/poked/%04d.png`(90f) |
| `char/aing-milestone.{webm,mov}` | `/Users/yesung/aing-check-promo/public/assets/v3/mac/char/aing/milestone/%04d.png`(72f) |
| `char/aing-ultra-charged.{webm,mov}` | `/Users/yesung/aing-check-promo/public/assets/v4/char/aing/ultra_charged/%04d.png`(102f) |
| `char/aing-ultra.{webm,mov}` · `char/aing-ultra-poster.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/char/aing/ultra_poked/%04d.png`(0000–0071 만, 72f). 수리 단계: 이 한 편만 ×0.75(1260×1108) — 1440×900 Retina 에서 ×0.5 는 1.63배 확대로 물렀다. milestone 은 crf 54(682 → 331KB) |

### 9.4 아이폰·위젯
| 출력 | 원본 |
|---|---|
| `ios/now.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/ios/screens/now_dark@3x.png` |
| `ios/messages.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/ios/screens/messages_dark@3x.png` |
| `ios/rankings-league.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/ios/screens/rankings-league_dark@3x.png` |
| `ios/games.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/ios/screens/games_dark@3x.png` |
| `ios/me-records.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/ios/screens/me_records_dark@3x.png` |
| `ios/widget-todos-large.webp` · `ios/widget-todos-large-checked.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/ios/widgets/promo_todos-large_dark@3x.png` · `promo_todos-large-checked_dark@3x.png` |
| `ios/widget-today-small.webp` | `/Users/yesung/aing-check-promo/public/assets/v4/ios/widgets/promo_today-small_dark@3x.png` |

### 9.5 브랜드·글꼴·앱 아이콘·데이터
| 출력 | 원본 |
|---|---|
| `brand/appstore-badge-ko-black.svg` | `/Users/yesung/aing-check-promo/public/assets/v3/brand/appstore-badge-ko-black.svg`(바이트 그대로) |
| `brand/qr-appstore.svg` | 새로 생성(`https://apps.apple.com/app/id6812768622`) |
| `brand/icon-64.webp` · `brand/icon-256.webp` | `/Users/yesung/check/packaging/appicon/icon-1024.png` |
| `/Users/yesung/check/landing/app/icon.png`(128 팔레트) · `app/apple-icon.png`(180) | `/Users/yesung/check/packaging/appicon/icon-1024.png` |
| `/Users/yesung/check/landing/public/fonts/pretendard-800-sub.woff2` (+ `.txt` 글자 목록) | `/Users/yesung/aing-check-promo/public/fonts/Pretendard-ExtraBold.woff2` |
| `/Users/yesung/check/landing/public/fonts/jbm-400-ascii.woff2` | `/Users/yesung/aing-check-promo/public/fonts/JetBrainsMono-Regular.woff2` |
| `public/fonts/LICENSE-Pretendard.txt` · `LICENSE-JetBrainsMono.txt` | `/Users/yesung/aing-check-promo/public/fonts/LICENSE-*.txt` |
| `/Users/yesung/check/landing/data/generated/grass.json` | `/Users/yesung/aing-check-promo/public/assets/v4/mac/ui/insights/grass_light.json`(필드 추림) |
| `data/generated/assets.json` · `sequences.json` · `bubbles.json` | 내보내기 스크립트가 생성 |

---

## 10. 리스크와 대안 · 자기 비평

### 10.1 리스크와 축소판
| # | 리스크 | 대안 / 축소판 |
|---|---|---|
| R1 | DMG 자체의 서명·공증·스테이플 미확인 | 문구에 "경고 없이 열려요"를 쓰지 않는다. 확인 방법(배포 전, 별도): `hdiutil attach` 뒤 `spctl -a -vv -t open --context context:primary-signature aing-check.dmg`, `xcrun stapler validate aing-check.dmg` |
| R2 | 공개 랜딩 vs 지금의 공동체(가입 폼의 센터 필수 칸, 전체 공개 순위판) | 랜딩은 센터를 어디에도 쓰지 않고 FAQ 문항도 미게재(기본값). openQuestions 1번 |
| R3 | 고정 스파인 + fixed 핫스팟 정렬 깨짐(조상 transform, 줌, 스크롤바 폭) | 조상 transform/filter/contain 금지(통합 검사), `visualViewport` 재계산, 줌 90/110/125% 에서 ±2pt. 실패하면 **섹션별 `position: sticky` 팝오버** 축소판(PanelSlot 의 `inline` 렌더를 desk 에서도 sticky 로 — 상호작용은 전부 산다) |
| R4 | 알파 영상 판별 실패(맥 크롬 HEVC 검은 사각형 등), 파이어폭스 VP9 알파 | JS 판별 + `error` 시 포스터. 최악이면 코너는 포스터 정지 + 말풍선만 |
| R5 | 소재 버전 차이(맥 0.3.38 · 폰 1.0.1 ↔ 현행 0.3.47 · 1.0.5) | 출시 전 히어로 팝오버·콕·메시지 판을 현행 앱과 눈으로 대조(별도 작업). 다르면 다시 렌더 — 덧그리기 금지 |
| R6 | 렌더 속 작은 센터 배지(콕 목록·리그·오목 아바타)와 '9월' 글자 | 가상 데이터라 그대로. HTML 에는 센터·달 이름을 쓰지 않는다. 오목은 판돈 칸이 빠진 크롭 |
| R7 | 페이지 길이 | 상한 9,900px(1440×900). 넘으면 스파인 섹션 min-height 64svh, S6 창 0.86배. 수리 단계: S6 창은 700(1:1)으로 되돌리고 대신 S2 desk min-height 52svh(글 묶음 sticky) — 실측 9,870px. S10·S13 의 desk 위아래 112 복원(+64)은 상한을 넘어 보류 |
| R8 | 서브셋 누락 글자 | `prebuild` 에서 `check-glyphs` 가 소스 글자 ⊄ 서브셋이면 빌드를 멈춘다(`npm run subset` 안내) |
| R9 | 낮은 노트북(1280×720)에서 코너 아잉·스파인 겹침 | §4 공통 C 규칙(스파인 왼쪽 + 0.85배) |
| R10 | 렌더가 없는 최신 기능(AI 리밋·테트리스·체스·로봇·업데이트 배너·DMG 창) | 글로만. 그림을 만들지 않는다 |
| R11 | 울트라가 거슬림 | 되찌른 뒤에만, 한 번만, 2.4초, 아무 입력으로 닫힘, 감속 모션은 포스터 |
| R12 | GitHub API 지연·한도(비인증 60회/시) | ISR 1시간 + 3초 타임아웃 + 폴백 상수 |

### 10.2 '식상한 기본값' 점검(최종)
| 기본값 | 이 문서에서 |
|---|---|
| 글 왼쪽 + 제품 스크린샷 오른쪽 히어로 | 스크린샷이 '놓인 그림'이 아니라 **라벨에 물리적으로 매달린 창**(띠 여백 16px, 띠 아래 6px)이고, 작동하고, 페이지를 따라오고, 시간이 흐르면 라벨 속으로 접힌다 |
| 거의 검정 + 밝은 강조 하나 | 바탕은 팝오버에서 한 단 내린 네이비, 손은 아잉 몸색 라벤더. 앱 상태색은 렌더 안에서만 |
| 흰 알약 주 버튼 | 라벤더 채움 + 밤색 글자 |
| 섹션마다 키커·모노 대문자 라벨 | 없음. 시간이 바뀌는 두 곳에만 거터에 매단 실제 시각(14:05 · 17:02) |
| 가운뎃점 메타 줄 | 문장으로("무료예요. macOS 14 이상이면 …", "0.3.47 버전, 30.0MB.") |
| 작은 데이터 라벨에 모노 | 모노는 brew 명령 한 줄과 앱 코드 스펙인 몸통 캡슐뿐 |
| 버튼 끝 → | 없음. 버튼은 동사 |
| 둥근 카드 + 같은 회색 그림자 | 카드 없음. 그림자는 '창'에만, 반지름은 물체 정체별 |
| 섹션 페이드업·카드 호버 | 없음. 응답 + 로드 순간 하나 + 잔디 scrub 하나 |
| 순서 아닌 목록에 01/02/03 | 번호는 설치 단계·팀 참여에만 |
| 헤드라인 낱말 하나 강조 | 없음. "콕." 한 글자 헤드라인을 크기로만 |
| 그라디언트 워시·오로라·노이즈 | 없음. 바탕 단색 두 단 |
| sticky 제목 + 헤어라인 목록(broadsheet) FAQ | 한 열 목록으로 바꿈 |
| 가운데 정렬 큰 마스코트 클로징 | 왼쪽 정렬, 확대한 실제 라벨과 퇴근 꾸벅 한 번 |
| 스크롤 힌트·"눌러 보세요" | 없음. 다음 절 머리가 접힘선에 걸리고, [근무 시작]은 1.2초 뒤 링 한 번 |

거울 앞에서 하나 더 뺀 것: A 의 "S2 본문 아래 자동 시작 말풍선 정지 그림"과 "설정 공개 스위치 크롭", B 의 "아잉 부르기 알약". 셋 다 없어도 같은 사실이 이미 전달된다.

### 10.3 사용자 결정이 필요한 것(기본값으로 진행)
1. 센터(서울/부산) FAQ 문항 게재 여부 — **기본: 미게재**.
(그 밖의 갈림길 — 울트라 길이, 첫 페인트 마스코트, 내비 모양, 위젯 선택, 저작권 표기 — 은 이 문서에서 결정했다.)
