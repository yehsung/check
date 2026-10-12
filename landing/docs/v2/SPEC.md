# 아잉체크 랜딩 v2 — 최종 스펙 (SPEC v2)

작성 2026-10-12 · 종합자(디자인 디렉터 겸 테크 리드) · **구현자가 보는 유일한 디자인 정본**. 병렬 구현은 `docs/v2/PLAN.md`, 결정 기록은 `docs/v2/DECISIONS.md`(셋이 어긋나면 DECISIONS > PLAN > SPEC).
뼈대: 후보 **A** 「빛의 돔 + 트립틱 + 스파인 행」(심사 합산 1위 245 = 77+83+85). 심사 3건의 mustFix 를 전부 반영했고(§0.2), B·C 의 접목 중 '기억에 남을 하나'를 흐리지 않는 것만 들였다(§0.3).
표기: **CB:n** = `docs/content-brief.md` n번째 줄(`cat -n`) · **RA** = `docs/v2/reference-analysis.md` · **TD** = `docs/v2/teardown.md` · **A§/B§/C§** = 후보 문서 · **J1/J2/J3** = 심사 문서 · `A/` = `/Users/yesung/aing-check-promo/public/assets/` · `P/` = `/Users/yesung/check/landing/public/`.
실측 근거(세션 한정, 저장소 밖): `/private/tmp/claude-501/-Users-yesung-check/2e0b98fb-2bf2-4358-9866-db6bfc6f2d59/scratchpad/v2design/synth/` — `contrast.mjs`(WCAG 대비), 크롭 시험(`poke-slice`·`token-slice`·`league-slice`·`timer-00-00`·`rest-poster`·`menubar-icon`·`menubar-0000-lg`), 앱 아이콘 링 표본. 후보 A 의 크롭 시험은 `…/v2design/designer-A/probe/`, 대비는 `…/designer-A/contrast.txt`.
사실 정본은 여전히 `docs/content-brief.md`(카피·금지 §9·용어 §10)와 `docs/asset-manifest.md`(소재 실측). **카피는 CB 문장을 그대로 쓴다.** 이 문서가 고른 문장 밖의 새 문장은 §1.4.3 표에 있는 것뿐이다.

**통합(⑤) 반영 메모(2026-10-12)** — DECISIONS D19–D24 로 바뀐 값은 아래 표·코드에 반영했다(§2.2·§2.8·§2.9·§4·§9.1). 본문 표에 옛 값이 남은 곳은 DECISIONS 가 이긴다: R1 아래 페이드 40 → **24**(D19-2) · 콕·토큰·리그 조각 왼쪽 페이드 28 → **16**(D20-3) · 행 바닥 빛 `--w` = 캔버스 안 렌더 합집합 폭(R1 573 · R2 576 · R3 558 · R4 548 · R5 540 — D20-2, `top` 은 표 값 그대로) · 390 내비 CTA = Mac용 다운로드, 테두리 톤 = `--line-strong` + ink-1(D19-3) · 포스터 preload = `page.tsx` 의 react-dom `preload()`(D19-4) · 설치 절 팀 3걸음 = iPhone 열 아래 세로, 절 아래 패딩 96(D21-1) · 기능 행에도 세로 격자 10/50/90(desk, requests/rows-b.md §2) · 첫 화면 예산은 `load` 까지(D24-1).

**수리(⑦) 반영 메모(2026-10-12)** — DECISIONS D25–D28 과 리뷰 4건(`docs/v2/reviews/*.md`)으로 바뀐 값을 아래 표·코드에 반영했다(§2.2·§2.7·§2.9·§5.2·§6.5·§S1·§S2·§S4–§S8). 빛 한 줄 = 흰 머리 5px + 이중 글로우 · 림 핵에서 5px 안쪽 · 두 구간(림 등속 → 착지 ease-out) · 꼬리 시작 불투명 .35 · commute-start 가 재생 가능해진 뒤에만 출발 · 달리는 중 이탈하면 도착 생략(D27-1 · D28) · 목록 모드 카드 무대 빛 = GlowGate(D28-2) · 조용한 절의 빛나는 선 + 10% 스파인 연장 + 하한 0.3%(D27-2) · 조각 잘린 왼쪽 변 직각 + 머리띠 노치(D27-3) · 히어로 아래 `--line` 받침선(D27-4) · iOS 히어로 메타 = 「iOS 18 이상 · 무료」, brew 링크·아웃트로 brew 복사 숨김(D26-2·4) · 설치 절 업데이트 문장 하나(D26-1) · 말풍선 전부 `aria-hidden`(D26-3) · 배지 alt 「App Store에서 다운로드 하기」, 복사 실패 힌트 삭제(D26-5) · 행 렌더는 1,200px 근처에서 마운트(D25-1).

---

## 0. 한눈에

### 0.1 결정 요약

| 항목 | 결정 |
|---|---|
| 컨셉 한 문장 | **앱 아이콘을 페이지로 펼친다.** 아이콘의 보라 타이머 링이 지평선만 한 돔이 되고, 그 아래에서 진짜 앱 렌더와 아잉이 빛을 받아 하나씩 켜진다 |
| 기억에 남을 하나 | **히어로 첫 2초.** 돔 꼭대기의 메뉴바 라벨(00:00)에서 출발한 빛 한 줄이 돔 안쪽을 돌아 내려오고, 그 끝에서 아잉이 폴짝 도착해 "오늘도 화이팅!" 한다(몸에 근무 라벨 00:00). 같은 문법(**빛의 선 → 끝에서 진짜 렌더가 핀다**)이 기능 행 다섯 번에서 되풀이되고, 페이지 끝에서 같은 돔이 작게 돌아와 아잉이 그 아래 쉰다 |
| 색 | 바탕은 보랏빛 밤 `#0C0A14`(brief 값으로 되돌림, J1-A2·J2-A1). 빛은 **앱 아이콘 링 꼭대기 표본 `#7E5EFA`** 가족(B 접목, 실측 `icon-1024.png` (512,240)). 손(버튼·링크·포커스)은 라벤더 `#C9B8FF` 하나. 글로우는 **화면당 하나**(GlowGate, §2.9), 화면별 **보라 면적 예산**을 수용 테스트로 단언(C 접목) |
| 글꼴 | Pretendard **500**(H1·클로징 H2·숫자 격자 제목) · **600**(H2·H3·H4·트립틱 캡션·FAQ 질문) · **300 숫자 전용**(트립틱 큰 숫자·숫자 격자 숫자, C 접목 ≈2.8KB) · 본문 시스템 SF(0B) · brew 명령만 JetBrains Mono ASCII. v1 의 800 은 버린다 |
| 움직임 | **여섯 가지뿐**: ① 히어로 도착 1회(빛 한 줄 → 아잉 폴짝, desk 만 빛) ② 아잉 idle **2회 뒤 그 자리 정지**(히어로·아웃트로) ③ 돔 패럴랙스(CSS scroll-driven, JS 0) ④ 트립틱 고정 오브젝트 교체·점등(문턱, 되감김 허용) ⑤ 기능 행 조립 **1회**(문턱) ⑥ 바닥 빛 GlowGate(띠 안의 한 곳만 켜짐). 호버는 버튼·링크만. 자동 루프 상한 있음, 무한 루프 0 |
| 트립틱 | **세로 스크롤 + 가운데 오브젝트 고정(sticky) 교체** — 레퍼런스가 실제로 하는 동작(RA §0.2-2·§5.1). 가로 스크럽·글 마스크 없음(J1-A3). brief §5.1 의 "가로"와 다른 이유는 DECISIONS D1 |
| 길이 | 1440×900 기준 문서 높이 **9,616px = 10.7 뷰포트**(상한 9,900, 넘칠 때 줄이는 순서 §3.0) |
| 무게 | 첫 화면 **≈310KB**(예산 400) · 전체 **≈1.63MB**(같은 idle 영상 캐시 재사용) / 최악 **2.44MB**(예산 4.5MB) · 폰 최악 ≈1.9MB · desk LCP = H1 텍스트, phone LCP = 아잉 포스터 |
| 레퍼런스와 갈라지는 곳 | 지구본·세계지도 → **아이콘 링 돔 + 진짜 아잉** · 알림 카드 루프 → **도착 1회**(앱에 있는 짝: commute-start + "오늘도 화이팅!" + 근무 라벨) · 3D 오브젝트 → **앱 렌더**(메뉴바 라벨+헤더 카드 / 콕 목록 조각+말풍선 / 보라 AI 토큰 잔디) · 흰 알약 → **라벤더 알약** · 영문 소문자 라벨 → **앱의 한글 이름표** · 아이콘 노드 → **빈 노드가 점등** · 타일 아이콘 → **앱 메뉴바 아이콘·앱 아이콘 렌더** · S 마크 엔드카드 → **작은 돔 아래 아잉** · 로고 띠·Learn more·커서 데모 → 없음 |

### 0.2 mustFix 반영표(심사 → 이 문서의 위치)

**A(뼈대)에 걸린 mustFix 21건 — 전부 반영**

| # | 심사 | mustFix | 반영 |
|---|---|---|---|
| 1 | J1-A1 | 히어로를 '큰 것 하나'로(점 격자·펄스 삭제, 말풍선 하나, 팝오버는 다 넣거나 빼기) | 점 격자·펄스·팝오버 **삭제**. 큰 것 = 돔, 그 안의 물체 = 아잉 하나(말풍선은 아잉 몸 위 앱 배치로 1개, 1회). §S1 |
| 2 | J1-A2 | 바탕을 보랏빛 밤으로, 화면별 보라 하한을 수용 테스트로 | `--bg-0 #0C0A14`(§2.1) · 보라 면적 예산(§2.9) · PLAN §7 T9 |
| 3 | J1-A3 | 트립틱을 세로 + 오브젝트 sticky 로, 가로 마스크 삭제 | §S2 전체(세로 카드 3장 + 고정 무대). DECISIONS D1 |
| 4 | J1-A4 | 히어로 말풍선이 '알림 카드'로 안 읽히게(라벨·아잉 곁), R2 `todo-board` 빼기 | 말풍선은 **아잉 머리 위 앱 배치 그대로**(`CORNER.bubbleAtOut`), R2 의 할 일은 `ios/widget-todos-large`(§S4 R2) |
| 5 | J1-A5 | iOS 'Mac 링크 보내기'(공유 시트) 결정 | **삭제**. iOS 는 App Store 가 주(§1.5, §S6, PLAN `DownloadCTA`) |
| 6 | J2-A1 | "무채에 가깝게" 원칙 삭제 + C 의 보라 면적 예산 | §1.3-2, §2.9 |
| 7 | J2-A2 | 히어로 점 격자 또는 펄스 삭제, 말풍선 3→2 | 둘 다 삭제, 말풍선 1(1회) §S1 |
| 8 | J2-A3 | 히어로 팝오버가 v1 처럼 보이지 않게 | 히어로에서 팝오버 **삭제**. 팝오버 계열 렌더는 트립틱 01 의 헤더 카드 크롭만 §S2 |
| 9 | J2-A4 | 1440×789·1280×720 배치, H1 `svh` 상한, 말풍선이 메타를 덮지 않음 | `t-display` = `min(clamp(…), 10svh)` · 아잉 폭 `clamp(184px, 28svh − 16px, 268px)` · "말풍선 윗변 − 메타 아랫변 ≥ 16px" 규칙과 789·720 와이어 §S1 · PLAN T5 |
| 10 | J2-A5 | 트립틱 교체 히스테리시스, 고정 구간 길이 결정 | 앞으로 `.55`·뒤로 `.62` 두 문턱(`nextActive()` 순수 함수) · 고정 구간 144svh(카드 피치 72svh) §S2 |
| 11 | J2-A6 | 문서 길이 여유와 줄이는 순서 | 9,616px(여유 284px) + 줄이는 순서 §3.0 |
| 12 | J2-A7 | 헤드라인 줄바꿈을 CB ` / ` 위치에 `<br>` 고정 | 모든 헤드라인을 `lines[]` 로 확정(§3 각 절), `Headline` 이 `<br>` 로 낸다 §2.4 |
| 13 | J2-A8 | FAQ 를 숫자 격자와 다른 구도로 | FAQ = **왼쪽 정렬 한 열**(제목 위, 목록 아래). 숫자 격자(왼쪽 제목 + 오른쪽 칸)·설치(가운데 + 두 열)·아웃트로(가운데)와 모두 다르다 — J3-B5 의 "가운데 3연속" 우려도 함께 푼다 §S7 |
| 14 | J2-A9 | 신규 문구를 리드 승인 목록에 | §1.4.3 |
| 15 | J3-A1 | 트립틱 02 의 센터 배지 확대 노출, R4 리그 배지 | **아바타 열을 뺀 크롭** `ui/poke-slice`·`ui/token-slice`·`ui/league-slice`(왼쪽 28px 페이드) + 배지 감사표 §9.6 |
| 16 | J3-A2 | sticky 조상 금지 규칙 + `top === 0` 테스트 | §5.4 · PLAN §6-9 · T17 |
| 17 | J3-A3 | sr-only "하루의 세 장면" → CB 문장 | 신규 문구 삭제. 카드 캡션(「근무 시작.」「찔러 부르기.」「나만 보는 기록.」)을 각 카드의 `<h2>` 로 §S2 |
| 18 | J3-A4 | 아이콘 링 보라 + 아웃트로 작은 돔 북엔드 | `--violet #7E5EFA` §2.1 · 아웃트로 = 히어로와 같은 돔을 작게 + 아잉 §S8 |
| 19 | J3-A5 | 히어로 동시 움직임 줄이기(펄스 삭제 또는 1024 이하 혜성 끔), 상한 유지 | 펄스 삭제 · 빛 한 줄은 **1회**, desk 무대 모드에서만 · idle 2회 상한 §S1 |
| 20 | J3-A6 | `.dome::before` 블렌드 제거 | 돔 = 그라디언트 한 장, 블렌드·의사 요소 없음 §2.8 |
| 21 | J3-A7 | 1440×789·1280×720 히어로 와이어 | §S1 와이어 3벌 |

**접목한 부분(B 히어로·아웃트로, C 보라 예산·숫자 글꼴)에 걸린 mustFix — 해당 항목 반영, 들이지 않은 부분은 해당 없음**

| 심사 | mustFix | 판정 |
|---|---|---|
| J1-B1·J2-B3·J3-B1 | idle 무한 루프 → 횟수 상한 | 반영: `AingClip maxLoops=2`, 끝나면 **그 프레임에서 일시정지**(포스터로 바꾸지 않아 자세가 튀지 않음 — J2-B7·J3 §2 '반응 클립 끝 자세') §S1·§S8 |
| J1-B4·J2-B2 | 히어로에 제품 신호(메뉴바 라벨 또는 헤더 크롭)를 아잉 곁에 | 반영: 돔 꼭대기에 **실제 메뉴바 라벨** `menubar-0000-lg`, 아잉 몸에 **앱 근무 라벨** 00:00(앱 층 렌더 `_ui/timer_00-00`, 근무 중엔 늘 보인다 — `Sources/check/CheckCharacter3DView.swift:1553` `showsTimer`) §S1 |
| J1-B5·J2-B6 | 아웃트로를 앱에 있는 순서로 | 반영: 꾸벅 → idle(앱에 없음) 대신 **idle 만**(아이콘 구성의 브랜드 마크) §S8 |
| J1-B6 | 공유 시트 제거 | 반영(위 #5) |
| J1-B7·J2-B1·J3-B6 | 트립틱 방향을 DECISIONS 에 확정 | 반영: DECISIONS D1(세로) |
| J2-B4 | 폰·Save-Data·느린 망은 포스터, 폰 합계 ≤ 2MB | 반영: phone = 15fps idle, Save-Data·`effectiveType ∈ {slow-2g,2g,3g}` = 포스터만, 폰 최악 ≈1.9MB · T13 §5 |
| J3-B2 | idle 영상 캐시 가정 → 최악 계상 + 두 엔진 단언 | 반영: 히어로·아웃트로가 같은 URL, 최악 2.44MB 로 계상, 크롬·웹킷 전송 ≤ 4.5MB 단언 §5.3·T13 |
| J3-B4 | 한 화면에 같은 팝오버 둘 금지 | 반영: 히어로에 팝오버 없음 |
| J1-B2·J2-B5·J3-B7, J1-B3, J2-B8, J3-B3·B5·B8 | 아잉 스틸·행 구도·쉬는 시간 행·잔디 13단·FAQ·sticky | B 의 행·트립틱은 들이지 않음(A 의 것을 씀). 잔디 13단·쉬는 시간 행·sticky 규칙은 A 쪽에서 이미 충족 |
| J1-C1·J2-C6·J3-C3 | 행 구간 보라 하한 ≥ 1%(대안 (a) 렌더 뒤 약한 빛) | 반영: 행마다 **바닥 빛**(렌더 아래 타원, GlowGate 띠 안일 때만) — 행 하한 1.0% §2.9 |
| J2-C1·J1-C3 | 범용 글리프 타일 금지 | 해당 없음(A 의 실제 앱 아이콘 타일) |
| J1-C4·J2-C5·J3-C1 | 「숫자로.」 금지 | 해당 없음(격자 제목 = CB:29) |
| J2-C3·J3-C2 | 800 헤드라인 금지 | 반영(500/600/300) |
| J2-C4·J3-C5 | 지시선 | 들이지 않음(§0.3) |
| J2-C7 | App Store 배지 여러 곳 | 결정: 히어로·설치·아웃트로 3곳(CB:69·241·282). 매니페스트의 "페이지당 하나"는 원본 규칙 `v3/brand/manifest.json` 의 "영상당 하나"를 옮긴 것이다(DECISIONS D10) |

### 0.3 접목표 — 들인 것 / 버린 것

| 출처 | 아이디어 | 판정 | 이유 |
|---|---|---|---|
| B §2.1 | 빛 기준색 = 앱 아이콘 링 표본 `#7E5EFA`, 바탕 `#0C0A14`, 돔 안 `#06040C`, 엔드 `#08060F` | **들임** | 보라가 '아무 보라'가 아니라 이 앱의 보라가 된다. Sellix 복제 인상을 가장 싸게 푼다(J2·J3 1순위) |
| B §3.3 | 히어로 = 돔 아래 진짜 아잉(commute-start + "오늘도 화이팅!") | **들임(변형)** — A 의 '빛의 선 끝에서 렌더가 핀다'를 **1회** 도착으로 합쳐 기억할 하나로 | 셋 중 가장 아잉체크다운 장면(J1·J2·J3 모두 memorable 최고점). 레퍼런스의 빛줄기 → 카드 안무는 한 번으로 남는다 |
| B §3.3 | 2.5초 도착 마감, `t-hero` 의 `svh` 상한, 1440×789 배치 규칙 | **들임** | 짧은 화면·느린 망 검증(J2-A4·J3-A7) |
| B §3.10 | 아웃트로에 같은 돔을 작게 다시 | **들임** | 처음과 끝의 북엔드. 앱 아이콘(링 + 아잉) 구성이 마지막 그림이 된다 |
| B §2.2-⑧ | 설치 절 윗변 = 돔 림을 편 수평선 | **들임** | 조용한 절의 보라 요소 하나 + 돔 모티프 반복 |
| B §6.3 | `aing-rest-poster`(commute_start 0번 = 모든 반응 0번) | **들임** | 포스터 → 폴짝 이음매 0 |
| B §2.4 | 카운터를 모노 대신 tabular 산세리프 | **들임** | 작은 모노 라벨 템플릿 신호를 줄인다 |
| B §3.3 | 돔 패럴랙스를 CSS `view-timeline` 으로 | **들임** | 스크롤 리스너 0(JS 0), 미지원(파이어폭스)은 정적 |
| B | 세로 sticky 트립틱 | **들임**(J1-A3 mustFix 로) | 레퍼런스 실측과 같은 동작 |
| B | stage-bus(무대 다섯의 동시 재생 관리) | 버림 | 영상 무대가 둘(히어로·아웃트로)뿐이고 동시에 보일 수 없다 |
| B | 기능 행 ×6 의 아잉 스틸·같은 구도, 꾸벅 → idle 아웃트로, 가운데 FAQ | 버림 | J1·J2·J3 mustFix 와 충돌 |
| C §1.3·§5.4 | 화면별 보라 면적 예산 + HSV 캡처 수용 테스트 | **들임**(하한 수치는 §2.9 로 재설정) | "너무 다크하게만이 아니라"를 단언으로 만든다(J2 접목 1순위) |
| C §2.2 | GlowGate | **들임(일반화)** — 히어로·트립틱·행 바닥 빛·아웃트로 각각의 '켜짐 조건' | 절 경계에서 글로우 두 개가 겹치지 않는다 |
| C §2.3·§6.4 | Pretendard 300 숫자 전용 서브셋 | **들임** | 큰 숫자를 가볍게(레퍼런스 Regular 인상), 2.8KB |
| C §2.4 | 헤드라인 ` / ` 위치 `<br>` 고정 | **들임**(J2-A7) | 승인된 두 박자 문법 보장 |
| C | iOS 공유 시트·installHint·할 일 보드 렌더 금지 | **들임** | 허용 목록 밖 도구·v1 체험의 얼굴 |
| C §3.1 | 지시선(큰 숫자 → 렌더 속 같은 숫자) | 버림 | 세로 트립틱에서는 숫자가 스크롤로 움직이고 오브젝트는 고정이라 끝점이 매 프레임 바뀐다(J3 난이도 1위 + 선이 한 화면에 하나 더). "숫자는 렌더에 있다"는 §1.4 규칙과 alt 로 지킨다 |
| C | 지평선 얇은 호, 범용 글리프 타일, 800 헤드라인, 「숫자로.」, 렌더 1× 이하 | 버림 | J1·J2·J3 감점 사유 |
| A(뼈대) | RA 실측 돔 기하·림 단면, 교체 267+333ms·점등, 행 조립 1.3초, 실제 앱 아이콘 타일, 숫자 격자 칸마다 출처, FAQ 열린 행 빛 헤어라인, 잔디 13열 계단 점등, 크롭 레시피 표 | **유지** | 심사 3건이 모두 graft 로 꼽은 A 의 강점 |
| A | 혜성 루프 3슬롯·펄스·점 격자(히어로), 가로 트립틱·마스크, 히어로 팝오버, R2 할 일 보드, sr-only 절 제목 | 버림 | mustFix |
| brief §1(0.3.49) | 설치 절 업데이트 한 줄 — 설치 경로를 가르지 않는 문장 | **들임** | 0.3.49 부터 DMG 설치본도 앱 안 [지금 업데이트]로 스스로 교체된다(brief §1, 커밋 3545607). v1 S11 의 "DMG로 받았다면 … 덮어쓰면 돼요" 는 폐기 |

### 0.4 v1 과의 거리(사용자 원문 세 요구)

| 요구(brief §0) | v1(거부) | v2 |
|---|---|---|
| ① 체험 제거 | 핫스팟·세그먼트·게임 창·할 일 보드·코너 아잉·근무 버튼 흉내 | 클릭하면 바뀌는 것 **0**. 누를 수 있는 것은 §1.5 목록뿐(PLAN T10 이 단언) |
| ② 다크 + 보라 조화 | 네이비 무채 바탕 + 라벤더 버튼 하나, 빛 없음 | 보랏빛 밤 + 아이콘 링 보라 빛(돔·바닥 빛·선·타일·노드·수평선) + 화면별 보라 면적 하한(§2.9) |
| ③ 레퍼런스 안무 | 없음 | 돔 히어로 → 큰 숫자 3장(고정 오브젝트 교체·점등·`[ 01 / 03 ]`) → 눈썹 칩 + 가운데 H2 → 10% 스파인 + 노드 행 조립 → 4×2 숫자 격자 → 검게 가라앉는 엔드 |
| 지저분함 | 한 화면에 움직이는 것 여럿 | 한 화면에 큰 것 하나 · 글로우 하나 · 움직임 하나(§1.3) |

---

## 1. 컨셉과 원칙

### 1.1 한 문단
아잉체크의 앱 아이콘은 보라에서 파랑으로 도는 타이머 링 안에 아잉이 사는 그림이다. 이 페이지는 그 아이콘을 펼친다. 첫 화면은 링의 보라(`#7E5EFA`)로 빛나는 거대한 돔이고, 돔 꼭대기에는 앱이 메뉴바에 실제로 그리는 라벨(아잉 얼굴 + 00:00)이 걸려 있다. 페이지가 열리면 그 라벨에서 빛 한 줄이 출발해 헤드라인을 비켜 돔 안쪽을 돌아 내려오고, 끝에 닿는 순간 아잉이 폴짝 뛰어 도착하며 "오늘도 화이팅!" 한다. 몸에는 근무 라벨 00:00 이 뜬다 — 앱이 근무를 시작할 때 실제로 띄우는 세 가지가 그대로다. 스크롤하면 돔은 천천히 가라앉고, 큰 숫자 세 장(00:00 · 콕. · 12주)이 위로 흘러가는 동안 가운데 오브젝트는 제자리에서 꺼진 채 바뀌어 들어와 보라로 켜진다. 그다음은 왼쪽 10% 선이 스파인이 되어 다섯 기능을 꿰고, 행마다 보라 선이 그려지며 진짜 렌더가 한 번 조립되고 그 아래 빛이 고인다. 제품 사실 여덟 칸, 설치, 질문을 지나면 화면이 한 단 더 검게 가라앉고 처음의 돔이 작게 돌아와 그 아래서 아잉이 숨 쉰다. "메뉴바에, 아잉 하나."

### 1.2 기억에 남을 하나 — 규칙
- **선 → 렌더**: 빛의 선은 언제나 진짜 앱 렌더(아잉·라벨·패널·말풍선·타일)에서 끝난다. 끝나는 곳이 없는 장식 선은 그리지 않는다(헤어라인 격자·수평선·이음매는 '선'이 아니라 '구조'라 예외).
- **도착은 한 번**: 히어로의 빛 한 줄과 아잉 도착은 페이지를 열 때 한 번. 루프하지 않는다.
- **아잉은 두 곳**: 히어로(도착)와 아웃트로(작은 돔 아래). 그 밖의 아잉은 앱 렌더 속(캐릭터 패널·미니게임·폰 화면)에만.
- **링은 하나의 빛**: 돔 림·작은 돔 림·설치 수평선은 같은 그라디언트 가족(`--violet` → `--violet-bright` → `--violet-core`). 다른 보라를 새로 만들지 않는다.

### 1.3 절제 원칙(구현자가 매번 확인)
1. **한 화면에 큰 것 하나, 글로우 하나, 움직임 하나.** 글로우 = 돔 / 트립틱 무대 빛 / 행 바닥 빛 / 아웃트로 돔. 그 밖의 보라는 1–2px 선·작은 점·48px 타일뿐.
2. **바탕은 보랏빛 밤**(`--bg-0 #0C0A14`). 보라는 빛으로만 — 평평한 보라 면은 48px 타일이 최대. "무채에 가깝게"는 이 페이지의 원칙이 아니다(J2-A1).
3. **렌더는 크롭·축소·가장자리 페이드 마스크만.** 필터(회색화 포함)·덧그리기·커서 합성 금지. 연출은 렌더 **밖**(선·링·글로우·그림자·바닥 빛)에서.
4. **움직임은 §0.1 의 여섯 개뿐.** 섹션 페이드업·카드 호버 들림·추가 패럴랙스 금지. 캐릭터에 CSS 확대·회전·튀기기 금지(움직임은 앱 렌더 영상 30fps 그대로).
5. **불투명도는 언제나 선형.** 이동·크기는 등장 ease-out / 퇴장 ease-in. 오버슈트(`--ease-pop`)는 타일 팝에만.
6. **클릭하면 바뀌는 렌더 0.** 허용 인터랙션은 §1.5 뿐.
7. **숫자는 렌더 속 또는 제품 사실만**, 숫자마다 출처(§S5). 한 뷰포트에 어긋나는 가상 수치 금지(v1 §1.3-8: 팀 행 합 ↔ 리그 총합).
8. **한글이 주인공**: 영문 소문자 라벨·대문자 눈썹 없음, 눈썹 칩은 페이지에 하나(§S3).

### 1.4 사실 규칙(어기면 반려 — v1 §1.4 승계 + brief §1 + v2 추가)
- **인물**은 v4 가상 세트만: 새벽(나·아잉) / 아잉 데모팀 = 구름빵(해파리)·달토끼(여우)·민트별(아잉)·호두과자(시바) / 다른 팀 = 보리차(다람쥐)·솜사탕(유령)·초코칩(유령). 실사용자 이름·수치 0.
- **렌더를 고치거나 숫자를 덧그리지 않는다**(크롭·리사이즈·페이드 마스크만). 렌더 속 '9월'은 데모 날짜로 둔다. HTML 문구에는 달 이름을 쓰지 않는다.
- **쓰지 않는 말**: 오픈소스(→ "코드가 공개돼 있어요"), 판돈·베팅·걸고(→ 대결·1:1), 울찌(→ 울트라), 서울·부산·소마·SW마에스트로, 제공자 로고(이름은 글자로만), 전역 단축키, 열품타, "경고 없이 열려요"(DMG 서명·공증·스테이플 확인 전), "확인 메일·이메일 인증", 별점·사용자 수·WAU·유지율, 캐릭터 수 '일곱'.
- **숫자 규칙(brief §1)**: 레퍼런스 "In Numbers" 자리에는 **제품 사실 숫자만**(지표 금지), 칸마다 출처(CB 줄 또는 README).
- **제품명** 아잉체크(붙여 씀). 명령·파일명 자리에만 aing-check. 처음 한 번만 "아잉체크(aing-check)"(푸터 한 줄). 산문은 '근무 중', 앱 칩 인용만 '근무중'. 버튼 이름 '근무 시작'/'근무 종료'. 팀 열쇠는 '팀 코드'. 공식 이름 '울트라'.
- **쓰지 않는 소재**(v1 §1.4 그대로): `A/v4/char/aing/angle_top`, `A/v4/intro/**`, `A/v3/gen/**`, `A/v4/phone3d/**`, `A/v3/mockup/**`, `A/v4/laptop/**`, `A/v4/appstore/screenshot_*`, `A/v4/mac/ui/**/*_goal_done_*`, `*banner_retro*`, 9줄 미니게임 판, `A/v4/ios/screens/me_dark@3x.png`, `A/v4/ios/widgets/promo_working-*`, `A/v3/brand/qr-appstore.svg`(지역 코드 `/kr/`), `out/v4/thumbnail*.png`.
- **없는 것은 그리지 않는다**: 로봇·AI 리밋·테트리스·체스 화면(렌더 없음 → 글로만). 가짜 데스크톱·가짜 노트북·태블릿 프레임·커서 금지.
- **v2 추가**
  - 말풍선 렌더는 **앱의 짝과 함께만**: 아잉 위 "오늘도 화이팅!" = commute-start + 근무 라벨(앱 그대로). 행·트립틱의 말풍선은 아잉 없이 렌더 **곁**(겹치지 않게)에 놓는 페이지 크롬이며 한 화면에 하나, `aria-hidden`, 문구는 `BUBBLE_TEXT` 원문(J3 §2).
  - 센터 배지(서울/부산)가 **확대되어** 보이는 크롭 금지(CB:293). 1pt 이하로 작게 보이는 것은 허용 — 감사표 §9.6.
  - 근무 중인 아잉은 근무 라벨을 단다(앱 `showsTimer`). 아웃트로 아잉은 근무 상태가 아니라 아이콘 구성의 브랜드 마크라 라벨·말풍선이 없다(§S8).

#### 1.4.1 금지어(수용 테스트가 DOM 텍스트 + `alt` + `aria-label` 에서 0건을 단언 — PLAN T4)
`오픈소스` `판돈` `베팅` `걸고` `서울` `부산` `소마` `마에스트로` `울찌` `열품타` `경고 없이` `확인 메일` `이메일 인증` `일곱` `별점` `Learn more` `더보기` `눌러 보세요` `체험` `Mac 링크 보내기` `Gemini`

#### 1.4.2 카피 출처 원칙
헤드라인·본문·버튼·FAQ 는 CB 문장을 글자 그대로. 줄바꿈은 CB 의 ` / ` 위치(없으면 쉼표 뒤, §3 각 절이 `lines[]` 로 확정). 문장 사이 줄바꿈(리드)은 허용.

#### 1.4.3 신규 문구(CB 에 없는 것 — 리드 승인 목록, J2-A9)
| 자리 | 문구 | 근거 |
|---|---|---|
| 숫자 격자 칸 라벨 8개 | 요금 · macOS · iOS · Mac 앱 내려받기 · 근무·AI 토큰 잔디 · 미니게임 · 메시지·오목·체스 · 외부 SDK | CB 사실을 명사 라벨로 줄인 것(A§S5) |
| 숫자 격자 단위 | 원 · 이상 · MB · 주 · 종 · 개 | 같음 |
| 설치 열 라벨 | Mac · iPhone | CB §10 플랫폼 표기 |
| 설치 업데이트 한 줄 | 새 버전이 나오면 메뉴바 아이콘에 작은 점이 떠요. 지금 업데이트 한 번이면 설치하고 다시 켜져요. | 리드 확정 문장(brief §1 '업데이트 사실', 2026-10-12 18:11). CB §5.10 (b) 를 0.3.49 사실에 맞춰 줄인 것 |
| alt 문구 | §6.5 표 | 렌더 내용을 읽은 서술(마케팅 문장 아님) |
| OG alt | §8 | 같음 |

### 1.5 인터랙션 허용 목록(이 밖은 전부 금지)
내비 링크 3 + 내비 CTA · 본문으로 건너뛰기 · 다운로드 링크(`/api/download`, `?file=zip`) · App Store 배지·QR 링크 · "brew로 설치"(→ `#install`) · brew 복사 버튼 · FAQ `<summary>` · 푸터 링크 · `/licenses`. **iOS 공유 시트·버튼 흉내·렌더 위 클릭 대상·세그먼트·호버 툴팁 없음.** 트립틱 카드는 포커스 대상이 아니다(세로 흐름이라 읽기·스크롤만으로 닿는다).

---
## 2. 디자인 토큰

### 2.1 색 — 변수·값·용도(대비는 `synth/contrast.mjs` WCAG 2.x 실측)

| 변수 | 값 | 용도 |
|---|---|---|
| `--bg-0` | **#0C0A14** | 페이지 바탕, `theme-color`, 내비(스크롤 뒤 α .78) |
| `--bg-1` | #16132B | brew 명령 줄 바탕 하나(bg-0 대비 1.09 — v1 교훈: 1.06 이하는 저휘도 화면에서 사라진다) |
| `--surface` | #181428 | 눈썹 칩·명령 상자·노드(꺼짐)·행 주 렌더의 '빈 창' |
| `--surface-2` | #221C38 | 버튼 눌림 |
| `--dome-in` | #06040C | 돔 안(하늘보다 더 검다, RA §6.1-5) |
| `--bg-outro` | #08060F | 아웃트로·푸터(레퍼런스 엔드카드가 페이지보다 한 단 검다, RA §0.2-4). bg-0 → outro 는 160px 그라디언트로 넘긴다 |
| `--line` / `--grid-line` / `--line-strong` | rgba(255,255,255,.08) / .06 / .16 | 헤어라인 / 세로 격자 10·50·90% / 보조 버튼 테두리 |
| `--ink-1` | **#F4F1FF** | 헤드라인·숫자 |
| `--ink-2` | #B8B1D4 | 리드·본문·라벨·단위 |
| `--ink-3` | #958DB4 | 메타·카운터·법적(brief 출발값 #8A82A8 은 surface-2 위가 아슬해 B 값으로) |
| `--aing` / `--aing-hover` / `--on-aing` | **#C9B8FF** / #D8CCFF / #14102A | 주 버튼 채움·텍스트 링크·포커스 링 / 호버 / 라벤더 위 글자 |
| `--violet` | **#7E5EFA** | 빛의 기준색 = 앱 아이콘 링 꼭대기 표본(`packaging/appicon/icon-1024.png` (512,240), 종합자 재측정). 레퍼런스 중앙값 #7E33E6·brief #7C4DFF 와 같은 가족 |
| `--violet-deep` | #3B1E8F | 글로우 바깥 끝·타일 그늘 |
| `--violet-bright` | #DA84FF | 림 밝은 띠·빛 머리 꼬리 |
| `--violet-core` | #FFC8FF | 림 핵·빛 머리(레퍼런스 p99 #FABEFF) |
| `--lilac` | #C584F9 | 타일 윗색(레퍼런스 타일 면 RA §6.1-12) |
| `--wire-draw` / `--wire-rest` | #B9A6FF / #6E5B9A | 연결선: 그릴 때 밝고 정착하면 탁해짐(RA §0.2-9c) |
| `::selection` | rgba(126,94,250,.35) | — |

| 글자 \ 바탕 | bg-0 | bg-1 | surface | surface-2 | dome-in | bg-outro | 렌더 #1D202B |
|---|---|---|---|---|---|---|---|
| ink-1 | 17.65 | 16.24 | 16.14 | 14.62 | 18.32 | 18.09 | 14.59 |
| ink-2 | 9.61 | 8.84 | 8.79 | 7.96 | 9.97 | 9.85 | 7.94 |
| ink-3 | 6.31 | 5.81 | 5.77 | 5.23 | 6.55 | 6.47 | 5.22 |
| aing | 11.02 | 10.14 | 10.08 | 9.13 | 11.44 | 11.29 | 9.11 |
| violet-bright(글자 금지) | 8.16 | 7.51 | 7.46 | 6.76 | 8.47 | 8.36 | 6.74 |
| violet(글자 금지) | 4.55 | 4.19 | 4.16 | 3.77 | 4.72 | 4.67 | 3.76 |
| wire-rest(비글자, ≥3:1) | 3.39 | 3.12 | 3.10 | 2.81 | 3.52 | 3.48 | 2.80 |

on-aing 은 aing 위 10.36 · aing-hover 위 12.31. 면 대비: bg-1/bg-0 1.09 · surface/bg-0 1.09 · outro/bg-0 1.02(그라디언트로 넘김) · 렌더/bg-0 1.21(창 가장자리는 `--shadow-window` 첫 겹 헤어라인이 가른다). 앱 색(민트·코랄·앱 파랑)은 렌더 안에서만. 아이콘 링의 파랑 꼬리(#3DA0FF, 실측 θ 180°)는 가져오지 않는다 — 페이지 빛은 보라 한 가족.

### 2.2 빛 레시피(이름과 뜻 — 코드는 §2.8 에 그대로)

| 이름 | 생김새 | 어디 | 켜짐 조건(GlowGate) |
|---|---|---|---|
| `.dome` | 지름 `--dome-d`, 꼭대기 `--dome-top` 인 원. 안은 `--dome-in`, 림은 RA §3.1 x=349 단면(핵 1.5px → 밝은 띠 9px → 안쪽 감쇠 45px)을 **아이콘 링 가족 색으로 다시 칠한** 한 장의 `radial-gradient`. 블렌드·의사 요소·점 격자 없음(J3-A6) | 히어로(큰 돔) · 아웃트로(`.dome--small`) | 늘 켜짐(구조물). 히어로 돔은 패럴랙스로 가라앉으며 불투명 1 → .35 |
| `.dome-pool` | 아잉 발밑 타원(아잉 폭 × 1.6, 높이 × .24) | 히어로·아웃트로 | 돔과 한 빛(따로 세지 않음) |
| `.obj-glow` + `.obj-pool` | 오브젝트 뒤 라디얼(620px, 중심 α .40 → 60% 지점 .20) + 아래 타원 웅덩이(α .42) — DECISIONS D23-1 | 트립틱 무대 | 무대 진입(`engaged`) + 그 오브젝트가 활성·점등일 때 |
| `.floor-light` | 렌더 아래 타원(캔버스 안 렌더들의 합집합 폭 × 1.3, 높이 160, 중심 α .55 → 55% 지점 .20) — DECISIONS D19-1·D20-2 | 기능 행 5개 | 행 캔버스 중심이 화면 30–70% 띠 안일 때(행 피치 560 > 띠 360 → 한 번에 하나) |
| `.wire` | 1.5px SVG 선, `pathLength=100`, 그릴 때 `--wire-draw` → 정착 `--wire-rest` | 행·트립틱 01 | 조립·점등 때 그려짐(빛이 아니라 선 — GlowGate 대상 아님) |
| `.comet` | 꼬리(그라디언트 1.5px, 시작 불투명 .35) + 머리(흰 5px + 이중 글로우 `drop-shadow(0 0 3px #fff) drop-shadow(0 0 10px --violet-bright)`) — D27-1 · D28-3 | 히어로 1회 | 도착 연출 1회 |
| `.tile` | 48px 둥근 사각, `--lilac → --violet → --violet-deep` 그라디언트 + 안쪽 하이라이트 | R1·R3·R5 | 조립 때 팝 |
| `.node` | 24px 빈 사각 + 속점, 점등하면 보라 | 스파인 | 조립 때(한 번 켜지면 꺼지지 않음) |
| `.horizon` | 1px 선, 가운데가 `--violet-bright`, 바깥 헤일로 18px + 선 알파를 따르는 좁은 빛(`drop-shadow` 2px · 8px — 수리 1바퀴) | 설치 윗변 | 늘 |
| `.seam` | 1px 선(가운데 진한 보라) + 칸 왼쪽 위 24px 2px 틱 8개 + 격자 제목 아래 안심 한 줄 앞 틱 1개. 선·틱 모두 `.horizon` 과 같은 헤일로 + 좁은 빛(D27-2(a)(d)) | 숫자 격자 윗변 | 늘 |
| `.faq-open-line` | 열린 행 위 1px 그라디언트(violet → violet-bright → violet) + `.horizon` 과 같은 헤일로 + 좁은 빛, 열린 행 삼각형은 `--violet-bright`(D27-2(a)(b)) | FAQ | 열린 행 |
| `.spine-ext` | 10% 스파인의 연장: 1px rgba(126,94,250,.35) + 한 단 조용한 좁은 빛. 숫자 격자 · 설치 · FAQ 왼쪽을 지나 아웃트로 위 160px 동안 사라짐(`.spine-ext--end`) — desk 만(D27-2(c)) | 조용한 절 | 늘(구조물 — GlowGate 대상 아님) |
| `.dots` | 64px SVG 점 격자(16칸 중 9점, 그중 2점 보라) + 타원 마스크 | 행 캔버스 뒤 | 조립 끝에 330ms 페이드 |

### 2.3 글꼴

| 역할 | 글꼴 | 파일 · 로딩 | 바이트 |
|---|---|---|---|
| H1 · 클로징 H2 · 숫자 격자 제목 · 워드마크 아님 | Pretendard **Medium 500**(OFL, 원본 `/Users/yesung/aing-check-promo/public/fonts/Pretendard-Medium.woff2`) | `P/fonts/pretendard-500-sub.woff2` · `next/font/local` **preload** · `display:'swap'` · 변수 `--font-ptd-500` → `--font-display` | ≈36,000(B 실측 34,508 @ 496자) |
| H2 · H3 · H4 · 트립틱 캡션 · FAQ 질문 · 워드마크 | Pretendard **SemiBold 600**(`Pretendard-SemiBold.woff2`) | `pretendard-600-sub.woff2` · preload 안 함(DOM 에 있어 크롬이 첫 화면에서 받는다) · `--font-ptd-600` → `--font-heading` | ≈36,000 |
| 트립틱 큰 숫자 · 숫자 격자 숫자 | Pretendard **Light 300 숫자 전용** — `PretendardVariable.woff2` 를 `wght=300` 으로 인스턴스한 뒤 `data/figures.ts` 의 글자 + 숫자·`:`·`.` 만 | `pretendard-300-num.woff2` · preload(작아서 비용 0, 숫자 글꼴 교체 CLS 방지) · `--font-ptd-300n` → `--font-figure` | ≈2,800(C 실측 2.7KB) |
| 본문 · 리드 · 버튼 · 내비 · 라벨 · 카운터 · 단위 | 시스템 `-apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", system-ui, "Malgun Gothic", "Noto Sans KR", sans-serif` | 0 | 0 |
| brew 명령 | JetBrains Mono 400 ASCII(있음) | `jbm-400-ascii.woff2` · `--font-jbm` → `--font-code` | 4,440 |

- v1 `pretendard-800-sub.{woff2,txt}` 는 지운다(DECISIONS D5).
- 500·600 서브셋은 **같은 글자 집합**(소스 전체 스캔 — `scripts/check-glyphs.mjs` 의 수집기 그대로). 300 서브셋은 같은 수집기를 `data/figures.ts` 하나에만 돌린 글자 + `0–9 : .`(§9.5).
- `.t-number`·`.t-facts` 에는 **`FIGURES` 의 문자열과 릴리스 MB(숫자·`.`)만** 넣는다(타입 `FigureString` 으로 강제, §6.4). 단위는 시스템 글꼴 `.t-unit`.
- 전역: `word-break: keep-all; overflow-wrap: anywhere;` 헤드라인 `text-wrap: balance`, 본문 `pretty`, 숫자 `tabular-nums`. 이탤릭·낱말 강조·대문자 라벨 없음.

### 2.4 타입 스케일(390 → 1440 선형, `clamp(a, c + m·vw, b)`)

| 클래스 | 390 → 1440 | 식 | 행간 · 자간 · 굵기 | 쓰는 곳 |
|---|---|---|---|---|
| `t-display` | 40 → 88 | `min(clamp(40px, 22.17px + 4.571vw, 88px), 10svh)` | 1.10 · −.03em · 500 | H1(789 높이에서 78.9, 720 에서 72) |
| `t-number` | 64 → 104 | `clamp(64px, 49.14px + 3.810vw, 104px)` | 1.0 · −.04em · 300 · tnum | 트립틱 숫자 |
| `t-h2` (`t-h2-solo` 별칭) | 32 → 60 | `clamp(32px, 21.6px + 2.667vw, 60px)` | 1.16 · −.03em · 600 | 절 H2 |
| `t-closing` | 36 → 64 | `clamp(36px, 25.6px + 2.667vw, 64px)` | 1.12 · −.03em · 500 | 아웃트로 H2 |
| `t-h3` | 26 → 44 | `clamp(26px, 19.31px + 1.714vw, 44px)` | 1.22 · −.025em · 600 | 기능 행 H3 |
| `t-facts` | 36 → 52 | `clamp(36px, 30.06px + 1.524vw, 52px)` | 1.0 · −.03em · 300 · tnum | 숫자 격자 숫자 |
| `t-facts-title` | 28 → 40 | `clamp(28px, 23.54px + 1.143vw, 40px)` | 1.25 · −.02em · 500 | 숫자 격자 제목 |
| `t-caption` | 20 → 24 | `clamp(20px, 18.51px + .381vw, 24px)` | 1.35 · −.015em · 600 | 트립틱 캡션(`<h2>`) |
| `t-h4` | 18 → 22 | `clamp(18px, 16.51px + .381vw, 22px)` | 1.35 · −.01em · 600 | 행 안 두 번째 박자 |
| `t-faq-q` | 17 → 20 | `clamp(17px, 15.89px + .286vw, 20px)` | 1.4 · −.01em · 600 | FAQ 질문 |
| `t-lead` | 16 → 20 | `clamp(16px, 14.51px + .381vw, 20px)` | 1.6 · 0 · 400 시스템 | 히어로 리드·절 서브·트립틱 부제 |
| `t-body` | 16(phone) / 17 | — | 1.7 · 0 · 400 | 단락 |
| `t-unit` | 16 / 20 | — | 1 · 0 · 500 시스템 · ink-2 | 숫자 격자 단위 |
| `t-kicker` | 14 | — | 1 · 0 · 500 · ink-2 | 행 카테고리 라벨(한글) |
| `t-eyebrow` | 13 | — | 1 · 0 · 500 · ink-1 | 눈썹 칩 1개 |
| `t-counter` | 13 | — | 1 · .06em · 500 · tnum · ink-3(현재 번호 ink-1) | `[ 01 / 03 ]`(모노 아님 — B 접목) |
| `t-small` / `t-micro` / `t-nav` | 14 / 13 / 14 | — | 1.55 / 1.5 / 1 · 400/400/500 | 메타·법적·내비 |
| `t-wordmark` | 16 | — | 1 · 600 | 내비·푸터 워드마크 |
| `t-button` / `t-button-s` | 16 / 14 | — | 1 · 600 | 버튼(48 / 36) |
| `t-code` | 15(phone 13.5) | — | 1.5 · JBM | brew 명령 |

글줄: 단락 `max-width: 34em`, H1 폭 ≤ 640px, 리드 ≤ 576px. **헤드라인 줄바꿈은 `Headline lines[]` 가 `<br>` 로 고정**(C 접목·J2-A7) — 각 절의 `lines` 값이 정본이다. `text-wrap: balance` 는 한 줄 안의 균형에만 쓴다.

### 2.5 간격 · 격자 · 최대 폭
- 간격 4px 단위: `4 8 12 16 20 24 32 40 48 56 64 72 96 120`.
- **세로 격자 = 레퍼런스의 10 / 50 / 90%**(RA §0.2-9a): `--shell: min(100vw, 1600px)`, 선 x = `50% ± .40·shell` 과 `50%`. 왼쪽 선이 기능 절에서 스파인이 된다. 데스크톱 글 시작 = 10% + 32px(1440 에서 **176**) = `--gutter`.
- 기능 행: 글 열 12.5–42%(180–605), 캔버스 열 50–90%(720–1296, **576px 캔버스**, 1024 에서 k = .82).
- 섹션 세로 패딩: 120(desk) / 96(tab) / 72(phone). 묶음: 라벨 → H3 12, H3 → 본문 20, 본문 → H4 32, H4 → 본문 12, H2 → 서브 20.

### 2.6 반지름 · 그림자
| 물체 | 반지름 | 그림자 |
|---|---|---|
| 렌더 창(헤더 카드·패널 조각·게임 창) | `--r-window` 12 | `--shadow-window`, 점등 때 `--ring-lit` 추가 |
| 타일 / 노드 | 12 / 7 | 타일 §2.8, 노드는 점등 때만 |
| 버튼·눈썹 칩 | 999 | 없음 |
| 명령 상자 | 10 | 없음 |
| 폰 셸 | `phoneShellMetrics()` 그대로 | 바깥 1px .10 + 안 1px .06 + `--shadow-window` |
| 말풍선·라벨·근무 라벨 렌더 | 렌더에 구워져 있음 | 렌더 그림자 그대로(덧그리지 않음) |

### 2.7 모션 토큰
| 변수 | 값 | 출처 · 쓰는 곳 |
|---|---|---|
| `--t-quick` | 120ms | 버튼 눌림·불투명 들고 남·말풍선 등장 불투명 |
| `--t-resize` | 200ms | 내비 배경·CTA 채움 전환 |
| `--t-draw` | 200ms | 선 한 토막(RA: 트렁크 ≈6f) |
| `--t-exit` / `--t-enter` | 267 / 333ms | 트립틱 오브젝트 퇴장 8f / 등장 10f(RA §4.3) |
| `--t-pop` | 400ms | 타일 팝 |
| `--t-dots` | 330ms | 점 격자 페이드(≈10f) |
| `--t-dim` | 400ms | 선 탁해짐(12–15f) |
| `--t-fade` | 600ms | 아웃트로 내용 페이드(18f, RA §4.5) |
| `--t-glow` | 800ms | GlowGate 켜고 끄기(선형) |
| `--t-light` | 900ms | 트립틱 오브젝트 점등 |
| `--t-comet` | 1000ms | 히어로 빛 한 줄(RA: 호의 빛 머리 1.3s 를 한 번으로 줄임). 두 구간 — 림 구간(경로 비율 P)은 등속, 착지 구간은 `--ease-out`, 이음매 속도가 같게 림 시간 T₁ = P/(4 − 3P)(1440×900 ≈ 300ms). Web Animations(`HeroStage` · `cometRimTime()`) — DECISIONS D28-3 |
| `--t-first-light` | 1300ms | 트립틱 첫 장 첫 점등(39f) |
| `--ease-out` / `--ease-in` / `--ease-pop` | `cubic-bezier(.2,.8,.2,1)` / `(.4,0,1,1)` / `(.34,1.56,.64,1)` | 등장 / 퇴장 / 타일 팝만 |
| 불투명도 | linear | 언제나 |
| 말풍선(앱 값) | 등장 불투명 0→1 120ms 선형 + scale .96→1 200ms ease-out(원점 왼쪽 아래) / 퇴장 160ms 선형 | v1 `Bubble` 그대로 |
| 캐릭터 | 영상 30fps(phone·`deviceMemory ≤ 4` 의 idle 만 15fps) | 이징 없음 |

**감속 모션(`prefers-reduced-motion: reduce`)**: 빛 한 줄·영상·패럴랙스·교체·조립 전이 **0**. 각 절은 처음부터 **최종 상태**(히어로 = 포스터 + 말풍선 + 근무 라벨, 트립틱 = 세로 목록에 켜진 오브젝트, 행 = 조립 끝). 영상 요청 0건. 글로우의 불투명 페이드(≤ 800ms 선형)만 남긴다(이동이 아니다). CSS 키프레임은 `@media (prefers-reduced-motion: no-preference)` 안에서만 선언. 서버는 감속 여부를 모른다 → 초기 마크업을 가르지 말고 CSS 로 최종 상태를 낸다.

**JS 없음**: `PLATFORM_SCRIPT` 가 `<html>` 에 `js` 클래스를 붙인다. 숨김 초기 상태(조립 전·도착 전)는 전부 `.js` 아래에서만 걸어, JS 가 없으면 모든 절이 최종 상태로 보인다(트립틱도 목록 모드).

### 2.8 `app/globals.css` 그대로

이름 호환(TD §8): `--t-quick --r-pill --t-resize --ease-out --shadow-window --r-window --gutter --z-nav --z-ultra --r-tip --r-seg-in --r-nav --r-code --nav-h --edge --font-display --font-code`, 색 유틸 `text-ink-1/2/3 bg-surface bg-surface-2 text-aing border-aing border-line border-line-strong text-on-aing bg-aing bg-aing-hover bg-bg-0`, 타입 클래스 `t-display t-closing t-h2 t-h2-solo t-h3 t-button t-button-s t-small t-micro t-nav t-code` 는 **이름을 지키고 값만 바꾼다.** 지우는 것: `--hotspot --app-mint --app-coral-a/b --scrim-sheet --render-window --r-label --r-seg --t-base --t-overlay --t-move --spine-gap --z-spine --z-corner --z-board`, 키프레임 `spine-drop-* hotspot-pulse label-glow`, 클래스 `t-statement t-time`.

```css
@import "tailwindcss";

/* ── 반응형 변형: lib/hooks.ts 의 MQ_* 와 같은 문자열 ─────────────────────────── */
@custom-variant desk (@media (min-width: 1024px) and (min-height: 640px));
@custom-variant tab (@media (min-width: 768px) and ((max-width: 1023.98px) or (max-height: 639.98px)));
@custom-variant phone (@media (max-width: 767.98px));
/* 무대 모드 = desk + 감속 아님(트립틱 고정 무대·빛 한 줄·패럴랙스). JS 조건은 .js 로 따로 건다 */
@custom-variant stage (@media (min-width: 1024px) and (min-height: 640px) and (prefers-reduced-motion: no-preference));

:root {
  /* 바탕 — 보랏빛 밤 */
  --bg-0:#0C0A14; --bg-1:#16132B; --surface:#181428; --surface-2:#221C38;
  --dome-in:#06040C; --bg-outro:#08060F;
  --line:rgba(255,255,255,.08); --grid-line:rgba(255,255,255,.06); --line-strong:rgba(255,255,255,.16);
  /* 글자 */
  --ink-1:#F4F1FF; --ink-2:#B8B1D4; --ink-3:#958DB4;
  /* 손 */
  --aing:#C9B8FF; --aing-hover:#D8CCFF; --on-aing:#14102A;
  /* 빛 — 앱 아이콘 링 가족 */
  --violet:#7E5EFA; --violet-deep:#3B1E8F; --violet-bright:#DA84FF; --violet-core:#FFC8FF; --lilac:#C584F9;
  --wire-draw:#B9A6FF; --wire-rest:#6E5B9A;
  /* 물체 */
  --shadow-window:0 0 0 1px rgba(255,255,255,.07),0 28px 56px -18px rgba(0,0,0,.72),0 8px 18px -8px rgba(0,0,0,.5);
  --ring-lit:0 0 0 1px rgba(187,159,255,.28),0 0 40px -6px rgba(126,94,250,.45);
  --r-window:12px; --r-tile:12px; --r-node:7px; --r-pill:999px; --r-code:10px; --r-nav:8px; --r-tip:8px; --r-seg-in:8px;
  /* 움직임 */
  --t-quick:120ms; --t-resize:200ms; --t-draw:200ms; --t-exit:267ms; --t-enter:333ms; --t-pop:400ms;
  --t-dots:330ms; --t-dim:400ms; --t-fade:600ms; --t-glow:800ms; --t-light:900ms; --t-comet:1000ms; --t-first-light:1300ms;
  --ease-out:cubic-bezier(.2,.8,.2,1); --ease-in:cubic-bezier(.4,0,1,1); --ease-pop:cubic-bezier(.34,1.56,.64,1);
  /* 배치 */
  --shell:min(100vw,1600px);
  --nav-h:56px; --edge:16px; --gutter:20px;
  --dome-top:clamp(64px, 9svh, 96px); --dome-d:230vw;
  --aing-w:clamp(180px, 26svh, 240px);
  --z-nav:50; --z-ultra:90;
}
@media (min-width:768px){ :root{ --nav-h:64px; --gutter:32px; --dome-top:clamp(72px, 13svh, 132px); --dome-d:120vw; --aing-w:clamp(184px, 24svh, 240px); } }
@media (min-width:1024px) and (min-height:640px){ :root{
  --gutter:calc((100vw - var(--shell)) / 2 + var(--shell) * .10 + 32px);   /* 1440 → 176 */
  --dome-top:18svh; --dome-d:min(87.5vw, 1300px, 140svh);                  /* 1440×900 → 162 · 1260 */
  --aing-w:clamp(184px, calc(28svh - 16px), 268px);                        /* 900 → 236 · 789 → 205 · 720 → 186 */
} }

@theme inline {
  --color-bg-0:var(--bg-0); --color-bg-1:var(--bg-1); --color-bg-outro:var(--bg-outro);
  --color-surface:var(--surface); --color-surface-2:var(--surface-2);
  --color-line:var(--line); --color-line-strong:var(--line-strong);
  --color-ink-1:var(--ink-1); --color-ink-2:var(--ink-2); --color-ink-3:var(--ink-3);
  --color-aing:var(--aing); --color-aing-hover:var(--aing-hover); --color-on-aing:var(--on-aing);
  --color-violet:var(--violet); --color-violet-bright:var(--violet-bright); --color-violet-deep:var(--violet-deep);
  --font-display:var(--font-ptd-500), -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", system-ui, sans-serif;
  --font-heading:var(--font-ptd-600), -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", system-ui, sans-serif;
  --font-figure:var(--font-ptd-300n), var(--font-ptd-500), -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
  --font-sans:-apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", system-ui, "Malgun Gothic", "Noto Sans KR", sans-serif;
  --font-code:var(--font-jbm), ui-monospace, "SF Mono", Menlo, monospace;
  --radius-window:var(--r-window); --radius-pill:var(--r-pill);
}

html { background:var(--bg-0); color:var(--ink-1); color-scheme:dark; font-family:var(--font-sans);
       word-break:keep-all; overflow-wrap:anywhere; -webkit-font-smoothing:antialiased;
       scroll-padding-top:calc(var(--nav-h) + 24px); }
body { overflow-x:clip; }            /* hidden·auto 금지 — sticky 조상 규칙(§5.4) */
@media (prefers-reduced-motion: no-preference) { html { scroll-behavior:smooth; } }
:focus-visible { outline:2px solid var(--aing); outline-offset:2px; }
.btn-primary:focus-visible { outline-offset:3px; }
::selection { background:rgba(126,94,250,.35); color:var(--ink-1); }

@layer components {
  /* ── 타입 ─────────────────────────────────────────────────────────────── */
  .t-display,.t-closing,.t-facts-title { font-family:var(--font-display); font-weight:500; text-wrap:balance; }
  .t-h2,.t-h2-solo,.t-h3,.t-h4,.t-caption,.t-faq-q,.t-wordmark { font-family:var(--font-heading); font-weight:600; text-wrap:balance; }
  .t-number,.t-facts { font-family:var(--font-figure); font-weight:300; font-variant-numeric:tabular-nums; }
  .t-lead,.t-body,.t-small,.t-micro,.t-nav,.t-button,.t-button-s,.t-kicker,.t-eyebrow,.t-counter,.t-unit { font-family:var(--font-sans); }

  .t-display     { font-size:min(clamp(40px, 22.17px + 4.571vw, 88px), 10svh); line-height:1.1; letter-spacing:-.03em; }
  .t-number      { font-size:clamp(64px, 49.14px + 3.810vw, 104px); line-height:1;    letter-spacing:-.04em; }
  .t-h2,.t-h2-solo { font-size:clamp(32px, 21.6px + 2.667vw, 60px); line-height:1.16; letter-spacing:-.03em; }
  .t-closing     { font-size:clamp(36px, 25.6px + 2.667vw, 64px);   line-height:1.12; letter-spacing:-.03em; }
  .t-h3          { font-size:clamp(26px, 19.31px + 1.714vw, 44px);  line-height:1.22; letter-spacing:-.025em; }
  .t-facts       { font-size:clamp(36px, 30.06px + 1.524vw, 52px);  line-height:1;    letter-spacing:-.03em; }
  .t-facts-title { font-size:clamp(28px, 23.54px + 1.143vw, 40px);  line-height:1.25; letter-spacing:-.02em; }
  .t-caption     { font-size:clamp(20px, 18.51px + .381vw, 24px);   line-height:1.35; letter-spacing:-.015em; }
  .t-h4          { font-size:clamp(18px, 16.51px + .381vw, 22px);   line-height:1.35; letter-spacing:-.01em; }
  .t-faq-q       { font-size:clamp(17px, 15.89px + .286vw, 20px);   line-height:1.4;  letter-spacing:-.01em; }
  .t-lead        { font-size:clamp(16px, 14.51px + .381vw, 20px);   line-height:1.6;  font-weight:400; max-width:34em; text-wrap:pretty; }
  .t-body        { font-size:17px; line-height:1.7;  font-weight:400; max-width:34em; text-wrap:pretty; }
  .t-unit        { font-size:20px; line-height:1;    font-weight:500; color:var(--ink-2); }
  .t-kicker      { font-size:14px; line-height:1;    font-weight:500; color:var(--ink-2); }
  .t-eyebrow     { font-size:13px; line-height:1;    font-weight:500; color:var(--ink-1); }
  .t-counter     { font-size:13px; line-height:1;    font-weight:500; letter-spacing:.06em; font-variant-numeric:tabular-nums; color:var(--ink-3); }
  .t-small       { font-size:14px; line-height:1.55; font-weight:400; }
  .t-micro       { font-size:13px; line-height:1.5;  font-weight:400; }
  .t-nav         { font-size:14px; line-height:1;    font-weight:500; }
  .t-wordmark    { font-size:16px; line-height:1; }
  .t-button      { font-size:16px; line-height:1;    font-weight:600; letter-spacing:-.005em; }
  .t-button-s    { font-size:14px; line-height:1;    font-weight:600; }
  .t-code        { font-family:var(--font-code); font-size:15px; line-height:1.5; font-weight:400; }
  @media (max-width:767.98px) { .t-body{ font-size:16px; } .t-code{ font-size:13.5px; } .t-unit{ font-size:16px; } }

  .sr-only { position:absolute; width:1px; height:1px; padding:0; margin:-1px; overflow:hidden; clip:rect(0,0,0,0); white-space:nowrap; border-width:0; }
  summary.disclosure { list-style:none; cursor:pointer; }
  summary.disclosure::-webkit-details-marker { display:none; }
  .disclosure::after { content:""; display:inline-block; flex:none; width:10px; height:10px; background:var(--ink-3);
    clip-path:polygon(20% 8%, 88% 50%, 20% 92%); transform:rotate(0deg); }
  details[open] > .disclosure::after { transform:rotate(90deg); }

  /* ── 구조: 세로 격자 10/50/90 ─────────────────────────────────────────── */
  .gridlines { position:absolute; inset:0; pointer-events:none; background:
    linear-gradient(var(--grid-line), var(--grid-line)) calc(50% - var(--shell) * .40) 0 / 1px 100% no-repeat,
    linear-gradient(var(--grid-line), var(--grid-line)) 50% 0 / 1px 100% no-repeat,
    linear-gradient(var(--grid-line), var(--grid-line)) calc(50% + var(--shell) * .40) 0 / 1px 100% no-repeat; }
  .gridlines--left { background:linear-gradient(var(--grid-line), var(--grid-line)) calc(50% - var(--shell) * .40) 0 / 1px 100% no-repeat; }

  /* ── 돔: 림 단면(RA §3.1)을 아이콘 링 가족으로. 그라디언트 한 장, 블렌드·의사 요소 없음 ── */
  .dome { position:absolute; left:50%; top:var(--dome-top); width:var(--dome-d); aspect-ratio:1;
    margin-left:calc(var(--dome-d) / -2); border-radius:50%; pointer-events:none;
    background:radial-gradient(circle closest-side,
      var(--dome-in) 0, var(--dome-in) calc(100% - 58px),
      #17123A calc(100% - 46px), #221A58 calc(100% - 36px), #31247F calc(100% - 26px),
      #4733B6 calc(100% - 15px), #6447E2 calc(100% - 11px), #8C6CFF calc(100% - 8px),   /* 2차 띠 */
      #6B4BF0 calc(100% - 7px), var(--violet) calc(100% - 5px), #A27CFF calc(100% - 4px),
      var(--violet-bright) calc(100% - 3px), var(--violet-core) calc(100% - 1.5px),       /* 밝은 띠 → 핵 */
      #1F0A2E calc(100% - .5px), transparent 100%);                                       /* 1px 어두운 선 */
    box-shadow:0 0 120px 8px rgba(126,94,250,.10); }                                     /* 바깥 헤일로는 거의 없다 */
  .dome--small { --dome-d:min(60vw, 92svh, 860px); top:14svh; }
  @media (max-width:767.98px) { .dome--small { --dome-d:200vw; top:10svh; } }
  .dome-pool { position:absolute; left:50%; translate:-50% 0; width:calc(var(--aing-w) * 1.6); height:calc(var(--aing-w) * .24);
    border-radius:50%; pointer-events:none; background:radial-gradient(closest-side, rgba(126,94,250,.24), rgba(126,94,250,0)); }

  /* ── 트립틱 무대 빛 ────────────────────────────────────────────────────── */
  .obj-glow { position:absolute; inset:-140px -180px; pointer-events:none; background:              /* D23-1 */
    radial-gradient(closest-side, rgba(126,94,250,.40), rgba(126,94,250,.20) 60%, transparent),
    radial-gradient(ellipse 52% 18% at 50% 88%, rgba(126,94,250,.42), transparent 70%); }

  /* ── 행 바닥 빛(렌더 아래 타원) ───────────────────────────────────────── */
  .floor-light { position:absolute; left:50%; translate:-50% 0; width:calc(var(--w, 420px) * 1.3); height:160px; border-radius:50%;   /* D19-1·D20-2 */
    pointer-events:none; background:radial-gradient(ellipse closest-side, rgb(126 94 250 / var(--floor-alpha, .55)), rgba(126,94,250,.20) 55%, transparent); }

  /* GlowGate: data-glow="on" 일 때만. 불투명 페이드는 감속 모션에서도 남긴다(이동이 아니다) */
  [data-glow] { opacity:0; transition:opacity var(--t-glow) linear; }
  [data-glow="on"] { opacity:1; }

  /* ── 선 · 타일 · 노드 · 점 격자 ──────────────────────────────────────── */
  .wire { fill:none; stroke:var(--wire-rest); stroke-width:1.5; stroke-linecap:round; stroke-dasharray:100; stroke-dashoffset:0; }
  .tile { width:48px; height:48px; border-radius:var(--r-tile); display:grid; place-items:center;
    background:linear-gradient(150deg, var(--lilac) 0%, var(--violet) 55%, var(--violet-deep) 100%);
    box-shadow:inset 0 1px 0 rgba(255,255,255,.28), inset 0 0 0 1px rgba(255,255,255,.10),
               0 0 0 1px rgba(126,94,250,.35), 0 10px 28px -8px rgba(126,94,250,.6); }
  .node { position:relative; width:24px; height:24px; border-radius:var(--r-node); display:grid; place-items:center;
    background:linear-gradient(150deg, rgba(126,94,250,.35), rgba(59,30,143,.35)); border:1px solid rgba(187,159,255,.55);
    box-shadow:0 0 0 4px rgba(126,94,250,.10), 0 0 16px rgba(126,94,250,.35); }
  .node::after { content:""; width:8px; height:8px; border-radius:2px; background:var(--violet-bright); box-shadow:0 0 8px rgba(218,132,255,.8); }
  .dots { position:absolute; inset:-40px; pointer-events:none;
    background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='64' height='64'%3E%3Cg fill='%23fff' fill-opacity='.10'%3E%3Ccircle cx='8' cy='8' r='.9'/%3E%3Ccircle cx='40' cy='8' r='.9'/%3E%3Ccircle cx='24' cy='24' r='.9'/%3E%3Ccircle cx='56' cy='24' r='.9'/%3E%3Ccircle cx='8' cy='40' r='.9'/%3E%3Ccircle cx='40' cy='40' r='.9'/%3E%3Ccircle cx='56' cy='56' r='.9'/%3E%3C/g%3E%3Cg fill='%237E5EFA' fill-opacity='.5'%3E%3Ccircle cx='24' cy='56' r='.9'/%3E%3Ccircle cx='56' cy='8' r='.9'/%3E%3C/g%3E%3C/svg%3E");
    -webkit-mask-image:radial-gradient(ellipse 58% 52% at 55% 50%, #000 35%, transparent 100%);
            mask-image:radial-gradient(ellipse 58% 52% at 55% 50%, #000 35%, transparent 100%); }

  /* ── 조용한 절의 보라 하나씩 ─────────────────────────────────────────── */
  .horizon { position:absolute; top:0; left:10%; right:10%; height:1px; pointer-events:none;
    background:linear-gradient(90deg, transparent, var(--violet) 30%, var(--violet-bright) 50%, var(--violet) 70%, transparent);
    box-shadow:0 0 18px 1px rgba(126,94,250,.45); }
  .seam { position:absolute; top:0; left:0; right:0; height:1px; pointer-events:none;
    background:linear-gradient(90deg, transparent 10%, rgba(126,94,250,.95) 50%, transparent 90%); }
  .tick { position:absolute; left:-1px; top:0; width:2px; height:24px; background:var(--violet); }
  .faq-open-line { position:absolute; left:0; right:0; top:-1px; height:1px; pointer-events:none;
    background:linear-gradient(90deg, transparent, rgba(218,132,255,.7) 20%, rgba(126,94,250,.5) 60%, transparent); }

  /* ── 히어로 빛 한 줄 ────────────────────────────────────────────────── */
  .comet { position:absolute; inset:0; width:100%; height:100%; overflow:visible; pointer-events:none; }
  .comet-trail { fill:none; stroke:url(#comet-grad); stroke-width:1.5; stroke-linecap:round; stroke-dasharray:100; stroke-dashoffset:100; }
  .comet-head  { fill:none; stroke:var(--violet-core); stroke-width:3; stroke-linecap:round; stroke-dasharray:2 100; stroke-dashoffset:2;
    filter:drop-shadow(0 0 6px var(--violet-bright)); }

  /* ── 트립틱: 무대 모드(desk + 감속 아님 + JS) ↔ 목록 모드(그 밖 전부) ────── */
  .moments-stage { display:none; }
}

/* ── JS 가 있을 때만 거는 '시작 전' 상태(없으면 전부 최종 상태로 보인다) ───────── */
@media (min-width:1024px) and (min-height:640px) and (prefers-reduced-motion: no-preference) {
  .js .moments-stage  { display:block; position:sticky; top:0; height:100svh; overflow:clip; }
  .js .moments-cards  { margin-top:-100svh; position:relative; z-index:1; }
  .js .moments-inline { display:none; }
}
@media (prefers-reduced-motion: no-preference) {
  /* 히어로: data-arrived = 근무 라벨 켬, data-bubble = 말풍선 보임(도착 때 붙고 5s 뒤 떨어진다).
     감속 모션에서는 이 블록이 없으므로 라벨·말풍선이 늘 보인다(= 도착 뒤 정지 상태) */
  .js [data-aing]:not([data-arrived]) .aing-timer { opacity:0; }
  .js [data-aing]:not([data-bubble]) .aing-bubble { opacity:0; scale:.96; transition:opacity 160ms linear; }
  .js [data-aing][data-bubble] .aing-bubble { transform-origin:0 100%; transition:opacity var(--t-quick) linear, scale 200ms var(--ease-out); }
  .comet[data-run] .comet-trail { stroke-dashoffset:0;   transition:stroke-dashoffset var(--t-comet) var(--ease-out); }
  .comet[data-run] .comet-head  { stroke-dashoffset:-98; transition:stroke-dashoffset var(--t-comet) var(--ease-out); }
  .comet[data-done] { opacity:0; transition:opacity 1200ms linear; }

  /* 기능 행 조립 전(§S4 4.1 타임라인 — 각 요소의 --at 지연) */
  .js [data-row]:not([data-on]) .wire     { stroke-dashoffset:100; stroke:var(--wire-draw); }
  .js [data-row]:not([data-on]) .row-item { opacity:0; translate:0 8px; }
  .js [data-row]:not([data-on]) .row-item[data-kind="main"] { opacity:0; translate:none; scale:.96; }
  .js [data-row]:not([data-on]) .row-item[data-kind="main"] > img { opacity:0; }
  .js [data-row]:not([data-on]) .tile     { opacity:0; scale:.6; }
  .js [data-row]:not([data-on]) .dots     { opacity:0; }
  .js [data-row]:not([data-on]) .node     { background:var(--bg-0); border-color:rgba(255,255,255,.14); box-shadow:none; }
  .js [data-row]:not([data-on]) .node::after { width:6px; height:6px; background:rgba(255,255,255,.22); box-shadow:none; }
  .js [data-row]:not([data-on]) .rail-seg { scale:1 0; }
  .js [data-row]:not([data-on]) .swap-to  { opacity:0; }
  .js [data-row][data-on]:not([data-instant]) .wire { transition:stroke-dashoffset var(--t-draw) var(--ease-out) var(--at,0ms), stroke var(--t-dim) linear calc(var(--at,0ms) + 700ms); }
  .js [data-row][data-on]:not([data-instant]) .row-item { transition:opacity 240ms linear var(--at,0ms), translate 240ms var(--ease-out) var(--at,0ms), scale 320ms var(--ease-out) var(--at,0ms); }
  .js [data-row][data-on]:not([data-instant]) .row-item[data-kind="main"] > img { transition:opacity 340ms linear 440ms; }
  .js [data-row][data-on]:not([data-instant]) .tile { transition:opacity 120ms linear 360ms, scale 270ms var(--ease-pop) 360ms; }
  .js [data-row][data-on]:not([data-instant]) .dots { transition:opacity var(--t-dots) linear 900ms; }
  .js [data-row][data-on]:not([data-instant]) .node { transition:background-color 400ms linear, border-color 400ms linear, box-shadow 400ms linear; }
  .js [data-row][data-on]:not([data-instant]) .rail-seg { transition:scale 400ms var(--ease-out); transform-origin:top; }
  .js [data-row][data-on]:not([data-instant]) .swap-to { transition:opacity 180ms linear var(--swap-at,1500ms); }

  /* 돔 패럴랙스(스크럽 1곳) — CSS scroll-driven, 미지원은 정적 */
  @keyframes dome-set { from { translate:0 0; opacity:1; } to { translate:0 14svh; opacity:.35; } }
  @media (min-width:1024px) and (min-height:640px) {
    @supports (animation-timeline: view()) {
      #top { view-timeline:--hero block; }
      #top .dome { animation:dome-set linear both; animation-timeline:--hero; animation-range:exit 0% exit 100%; }
    }
  }
  .disclosure::after { transition:transform 180ms var(--ease-out); }
}

/* 플랫폼별 CTA: 세 벌을 SSR 하고 <html data-platform> 으로 하나만 보인다(층 밖이라 유틸리티 display 를 이긴다) */
html:not([data-platform="ios"]) .cta-ios { display:none; }
html:not([data-platform="other"]) .cta-other { display:none; }
html[data-platform="ios"] .cta-mac, html[data-platform="other"] .cta-mac { display:none; }
html[data-platform="ios"] .order-ios-first { order:-1; }
```
- **통합(⑤)이 globals 에 더한 규칙**(위 블록 밖, 같은 파일): 행 말풍선 앱 문법 예외 `.row-item[data-kind="bubble"]`·접합점 `[data-kind="junction"]`(D19-7) · R5 폰 화면 440ms 내용 페이드(`[data-item="phone"] [data-phone-shell] img`) · FAQ 높이 전이 `details[name="faq"]::details-content`(`@supports (interpolate-size)`, no-preference) · 아웃트로 진입 페이드 `.js [data-outro-stage]:not([data-shown]):not(:focus-within)`(D20-5) · `@property --kw { syntax:"<length>"; inherits:true; initial-value:576px }`(D20-1 — 웹킷 atan2 배율. 초깃값은 D20-1 의 0px 대신 576px = 배율 1 쪽). 기능 행 루트는 `overflow-x:clip`(바닥 빛이 1024 에서 화면 밖으로 나가지 않게, #moments 조상이 아니라 §5.4 와 무관).
- 트립틱 오브젝트의 퇴장·등장·점등은 `components/moments/moments.css`(트립틱 에이전트 소유, CSS 모듈 아님 — `page.tsx` 가 import)에 §S2 값으로 둔다. 이 파일만 globals 밖 CSS 를 허용한다.
- Tailwind 유틸리티는 배치(그리드·간격·정렬)에만. 색·빛·움직임은 위 변수와 클래스로.

### 2.9 보라 면적 예산 · 빛 규칙(v2.1 — brief-v21 §4·§5 가 v2 표를 대체. 수용 테스트 T9 가 단언)

**측정**(C §5.4 알고리즘 그대로): 1440×900 뷰포트 캡처(dsf 1)의 각 픽셀을 HSV 로 바꿔 `H ∈ [245°, 295°]` · `S ≥ .35` · `V ≥ .30` 이면 **보라**(엄격). 라벤더 버튼(#C9B8FF, S .28)은 세지 않는다. v2.1 은 여기에 **보라 기운**(`H ∈ [245°, 295°]` · `S ≥ .15` · `V ≥ .12`)을 더 잰다 — 워시·오로라가 깔려 '어두운 면적'이 줄었는지를 보는 값(bg-0 #0C0A14 는 V .078 이라 세지 않는다). 위치는 DOM 에서 구한다(아래 scrollY 는 1440×900 기댓값이 아니라 정의).

| # | 위치(정의) | 보라 하한 | 보라 상한 | 보라 기운 | 이 화면의 보라 |
|---|---|---|---|---|---|
| V0 | 히어로 — scrollY 0, 도착 + 2.5s | **6%** | 12% | 정보(돔 안은 의도된 검정 — '돔 그대로') | 돔 림·안쪽 감쇠·웅덩이(α .34)·빛 한 줄(사라진 뒤) |
| V1–V6 | 장면 1–6 가운데 — 장면 `<section>` 중심 = 화면 50%, 조립 끝(data-on + 1.5s) 뒤 | **4%** | **15%** | **≥ 25%** | `.scene-wash`(워시 α .10) · `.scene-glow`(반지름 760 · 중심 α .34) · 스파인(.55) · 노드 |
| V7 | 설치 — `#install` 위 = 내비 아래 | **1.5%** | 8% | **≥ 25%** | `.aurora-band`(띠 α .14 + 타원 빛 .24) · `.horizon` · 스파인 연장 |
| V8 | FAQ — `#faq` 위 = 내비 아래 | **1%** | 8% | **≥ 25%** | `.aurora-tail`(꼬리 α .08 + 타원 빛 .26) · 열린 행 빛 헤어라인 · 열린 삼각형 · 스파인 연장 |
| V9 | 아웃트로 — `#outro` 위 = 0 | **5%** | 12% | 정보(작은 돔 안은 검정 — '아웃트로 그대로') | 작은 돔 림 · 웅덩이 |

- 어느 뷰포트도 **15% 초과 금지**(보라 범람). 평평한 보라 면 금지 — 빛은 전부 그라디언트(라디얼·리니어)다. 색 토큰은 v2 그대로(`--violet` 가족).
- 실측(purple, 2026-10-12 23:10, 데브 3000 · 하네스 T9 `out/purple21-final`): V0 6.86% · V1 6.35 · V2 9.10 · V3 11.54 · V4 10.16 · V5 11.55 · V6 10.90 · V7 **4.19%**(기운 59.1%) · V8 **1.97%**(기운 31.4%) · V9 5.09%. 장면 기운 48.5–61.8%. v2 는 V7 0.34% · V8 0.38%(기운 6.9% · 3.8%). 캡처 `.scratch/purple21/{before,after}/` · 나란히 `compare-1440-{install,faq}.png`.
- **장면별 반지름 손잡이**(D19 `--floor-alpha` 와 같은 방식 — 그 장면만, desk 만): 반지름 760 그대로면 렌더가 빛의 심을 덜 가리는 장면에서 워시와 겹친 고리가 상한을 넘었다(메시지 15.3 · 리듬 14.8 · 미니게임 18.0%). 렌더는 보라에 거의 기여하지 않는다(빛·워시를 끄면 장면당 0.03–1.3%). globals 에서 `#f-message` 700 · `#f-rhythm` 720 · `#f-games` 640 — 나머지 760. 중심 α 를 내리는 쪽은 타이머(렌더가 심을 다 가림)를 4% 아래로 떨어뜨려 쓰지 않았다(.30 → 타이머 4.0 · 미니게임 16.7%).
- 띠·꼬리만으로는 엄격 보라에 못 닿는다(α .14 → V .20). 그래서 설치·FAQ 의 빈 오른쪽에 타원 빛 한 점씩을 겹쳤다(brief-v21 §5 의 '보라를 넓게'를 지키는 쪽 — 리드 확인 몫).
- **보라 기운 ≥ 25% 를 '모든 뷰포트'로 적은 brief-v21 §5 와의 차이**: 히어로(실측 13.0%)·아웃트로(9.6%)는 돔 안쪽(#06040C·bg-outro)이 의도된 검정이라 '돔 그대로'와 함께 25% 를 넘을 수 없다 → 이 둘은 정보로 기록(T9 가 값만 남긴다). 리드가 25% 를 고집하면 돔 바깥에 워시를 더하는 쪽을 따로 결정해야 한다.

**빛 규칙**(v2 의 GlowGate·'화면당 글로우 하나'를 대체 — brief-v21 §4 "움직이지 않는 빛은 '지저분함'이 아니다")
| 빛 | 켜짐 | 구현 |
|---|---|---|
| 히어로 돔 | 구조물(늘). 패럴랙스가 나가는 동안 불투명 1 → .35 | `.dome` · `.dome-pool`(α .34) |
| 장면 무대 빛 | **늘 켜짐**, 전이·`data-glow` 없음 | 렌더 영역 가운데 `.scene-glow`(z -1, 반지름 `--glow-r` desk 760 — 장면별 손잡이 메시지 700 · 리듬 720 · 미니게임 640 · tab 560 · phone 380) |
| 장면 워시 | 늘 | 장면 `<section>` 의 배경 `.scene-wash` |
| 스파인 | 늘 — 장면 1 위에서 아웃트로 돔까지 끊김 없이(.55, box-shadow 빛) | `.rail-seg` · `.spine-ext`(설치·FAQ) · `.spine-ext--start`(장면 1 위 15% 흐림) · `.spine-ext--end`(아웃트로 위 160px) |
| 설치 오로라 | 늘 | `.aurora-band`(절 가운데 높이 420) |
| FAQ 꼬리 | 늘 | `.aurora-tail`(절 위 ≤ 520) + `.faq-open-line`(열린 행) |
| 아웃트로 돔 | 구조물(늘) | `.dome--small` |

- **한 화면의 큰 빛 ≤ 2**(T9 가 V0–V9 와 경계에서 단언): 센다 = 히어로 보이는 비율 > .35 · 아웃트로 보이는 비율 > .35 · `.scene-glow`·`.aurora-band`·`.aurora-tail`·`[data-glow="on"]` 가운데 **심 상자**(요소 상자를 가운데 기준 .35 배로 줄인 것 — 장면 빛이면 α ≥ .20 인 원의 바깥 상자)가 화면과 겹치는 것. 장면 피치 760 · 화면 900 이라 장면 경계에서 둘, 장면 가운데서 하나가 정상이다.
- **filter 금지**(빛 선·빛 면): `filter: drop-shadow` 를 빛에 쓰면 WebKit 이 화면 밖 필터 층을 문서 (0,0) 에 28×28 사각으로 그린다(verify-final R1). 좁은 빛은 box-shadow 또는 의사 요소(타원 그라디언트)로. 수용: WebKit 1440 캡처의 (0..40, 0..40) 픽셀이 bg-0 ±6(purple 실측 편차 0, v2 는 20 — 검정 사각).
- v2 의 `.floor-light`(행 바닥 빛)·`[data-glow]` GlowGate·`.obj-glow`(트립틱)·`.seam`·`.tick`(숫자 격자)는 v2.1 에서 쓰는 곳이 없어지면 globals 에서 지운다(purple — scenes 가 import 를 끊은 뒤).

---
## 3. 페이지 구조와 섹션 명세

### 3.0 순서표(1440×900 — v2.1, brief-v21 §1)

| # | id | 구도 | 높이 | 문서 y(어림) | 리빌 | 보라(늘 켜진 빛) |
|---|---|---|---|---|---|---|
| 0 | `nav` | 고정 띠(겹침) | 64 | — | 스크롤 8px 뒤 배경 | 없음 |
| 1 | `#top` | 가운데 · 돔 안 라벨 + H1 + 리드 1문장 + 아잉 | 900(100svh, 넘치면 늘어남) | 0 | 도착 1회 + 패럴랙스 | 돔 림, 빛 한 줄, 웅덩이(α .34) |
| 2 | `#f-timer` | 장면 1 근무 타이머 — 글 왼쪽(12.5–42%) · 통째 렌더 오른쪽(46–94%) | ≈760 | 900 | 조립 1회 | `.scene-wash` · `.scene-glow` · 스파인(.55) · 노드 |
| 3 | `#f-tokens` | 장면 2 AI 토큰·리밋 | ≈760 | 1,660 | 조립 1회 | 같음 |
| 4 | `#f-message` | 장면 3 메시지 | ≈760 | 2,420 | 조립 1회(+ 1.5s 뒤 '1' 사라짐) | 같음 |
| 5 | `#f-rhythm` | 장면 4 근무 리듬·잔디 | ≈760 | 3,180 | 조립 1회 | 같음 |
| 6 | `#f-games` | 장면 5 미니게임 | ≈760 | 3,940 | 조립 1회 | 같음 |
| 7 | `#f-iphone` | 장면 6 아이폰·맥 연동 | ≈760 | 4,700 | 조립 1회 | 같음 |
| 8 | `#install` | 가운데 H2 + Mac / iPhone 두 열 + 업데이트 1줄(압축) | ≈640 | 5,460 | 없음 | `.horizon` · `.aurora-band` · 스파인 연장 |
| 9 | `#faq` | 왼쪽 정렬 한 열 · 5문항 | ≈720(1번 열림) | 6,100 | 없음 | `.aurora-tail` · 열린 행 빛 헤어라인 · 스파인 연장 |
| 10 | `#outro` | 검정 · 작은 돔 + H2 + CTA + 아잉 | 720(80svh) | 6,820 | 진입 페이드 + idle 2회 | 작은 돔 |
| 11 | footer | 링크 줄 | 200 | 7,540 | 없음 | 없음 |
| | | | **≈ 7,740 = 8.6 뷰포트** | | | |

- 삭제(brief-v21 §1): 트립틱 `#moments` · 기능 절 제목 `#features`(칩·H2·서브) · 숫자 격자 `#facts` · 캐릭터/루비 행 · 순위 행(토큰 장면에 합침) · 설치 절의 팀 참여 3걸음·zip 링크(`/api/download?file=zip` 라우트는 유지) · FAQ 6–10번.
- 수용 범위(T5): 1440×900 문서 높이 **7,000–8,400px** · 섹션 id 순서 `top, f-timer, f-tokens, f-message, f-rhythm, f-games, f-iphone, install, faq, outro`. 넘치면 이 순서로 줄인다: ① 장면 패딩 80 → 64(−192) ② FAQ 행 패딩 20 → 16 ③ 설치 위 패딩 96 → 80.
- 리듬: 가운데 장면(1) → 글 왼쪽·렌더 오른쪽 장면 ×6(스파인으로 이어진 한 줄기) → 가운데 + 두 열(8) → 왼쪽 한 열(9) → 가운데 마크(10).
- 아래 S2(트립틱)·S3(기능 절 제목)·S5(숫자 격자) 절과 S4 의 행 표는 v2 기록이다 — v2.1 장면 명세는 brief-v21 §3·§4 가 정본.

---

### S0. 내비

- **목적**: 길 찾기 + 다운로드 하나.
- **카피**: 워드마크 `아잉체크`(`t-wordmark`) · 링크 `기능`(→ `/#features`) · `설치`(→ `/#install`) · `자주 묻는 것`(→ `/#faq`) · CTA `Mac용 다운로드`(CB:68). iOS 는 CTA 가 `App Store`(v1 분기 그대로).
```
1440 ┌──────────────────────────────────────────────────────────────────────────┐ 64
     │176 [icon 24] 아잉체크        기능   설치   자주 묻는 것      (Mac용 다운로드) 1264│
     └──────────────────────────────────────────────────────────────────────────┘
      히어로 위: 투명 · scrollY > 8: bg-0/78% + backdrop-blur 14px + 아래 --line (200ms 선형)
      CTA: 히어로 CTA 가 보이면 테두리(--line-strong · ink-1), 화면 밖이면 라벤더 채움(useHeroCtaVisible)
390  ┌──────────────────────────────────────┐ 56
     │20 [icon 22] 아잉체크      (Mac용 다운로드)│  링크 숨김 · 햄버거 없음
     └──────────────────────────────────────┘
```
- **에셋**: `brand/icon-64.webp`(1,434B, 24px).
- **구현**: `SiteNav`(server) + `NavShell`(client, 스크롤 8px 감지는 **IO 센티널**(문서 맨 위 1px) — 스크롤 리스너 없음).
- **감속**: 배경 전이 0ms. **접근성**: `<header><nav aria-label="주요">`, 맨 앞 `본문으로 건너뛰기`(→ `#main`, `--z-ultra`).
- **금지**: 메뉴바 라벨을 내비에 두기(v1 잔재), 햄버거, 활성 섹션 하이라이트(v1 상태 기계).
- **수용 조건**: scrollY 0 에서 배경 투명(`data-scrolled` 없음) · scrollY 200 에서 `data-scrolled` · 히어로 버튼 줄이 내비 뒤로 사라지면(1440×900 에서 scrollY ≥ 530) 내비 CTA 가 채움(`data-fill`) · 390 에서 링크 3개 `display:none` · Tab 첫 대상 = 건너뛰기 링크.

---

### S1. 히어로 `#top` — 기억에 남을 하나

- **목적**: 3초 안에 "메뉴바 근무 타이머 + 아잉 + 팀"을 보이고 다운로드를 건넨다. 큰 것은 돔 하나, 그 안의 물체는 아잉 하나.
- **카피**(그대로)
  - H1 `lines: ["출퇴근 기록을,", "메뉴바 하나로."]` — CB:64 ✓v4
  - 리드 `lines: ["근무 시작을 누르면 팀 전체에 바로 보여요.", "일하는 동안엔 아잉이 화면 구석에서 함께해요."]` — CB:67(문장 사이 줄바꿈, phone 은 자연 줄바꿈)
  - 주 버튼 **Mac용 다운로드**(CB:68) · App Store 공식 배지(CB:69)
  - 메타(`t-small` ink-3) **macOS 14 이상 · 무료**(CB:68) + 텍스트 링크 **brew로 설치**(CB:69, → `#install`, 누를 자리 45.7px). CB:70 "Apple 공증 · Apple Silicon·Intel" 은 설치 절 메타로 내린다(가운뎃점 사슬 줄이기, J2-A 감점 사유)
  - iOS(`data-platform=ios`): 메타 = **iOS 18 이상 · 무료**(CB:243), "brew로 설치" 링크 없음 — DownloadCTA 와 같은 플랫폼 변형(DECISIONS D26-2)
  - 렌더 속 글자: 메뉴바 라벨 "00:00" · 말풍선 "오늘도 화이팅!"(앱 원문 `CheckOverlayReactions.swift:956`) · 근무 라벨 "00:00"
- **물체(전부 앱 렌더)**

| 물체 | 에셋 | 크기(1440×900) | 배치 |
|---|---|---|---|
| 메뉴바 라벨 | `ui/menubar-0000-lg`(**신규** 463×132, 7,138B) | 높이 `clamp(30px, 4.4svh, 40px)` = 39.6 → 139×39.6(phone `clamp(28px, 3.6svh, 32px)`) | 가운데, 위 = `--dome-top + 14px`(176) — 돔 꼭대기 바로 아래(아이콘 링의 끝점 자리) |
| 아잉 상자 | 포스터 `char/aing-rest-poster`(**신규** 654×790, 17,702B) → `char/aing-commute-start` → `char/aing-idle` | 폭 `--aing-w`(228) × 275 | 가운데, 아래 = 히어로 아래 − 16px |
| 말풍선 | `ui/bubble-commute-start`(4x 로 다시 굽기, §9.3) | 캔버스 847×311.5 × .5 × d = 148×54 (d = 폭/654) | 상자 기준 `CORNER.bubbleAtOut` × d = (−50.5, 218.5)·d — **앱 배치 그대로** |
| 근무 라벨 | `ui/timer-00-00`(**신규** 264×120, 11,982B) | 263.5×119.5 × d = 92×42 | 상자 기준 `CORNER.capsuleAtOut` × d = (181.5, 571)·d |
| 웅덩이 | `.dome-pool` | 폭 × 1.6 × 폭 × .24 | 상자 아래 가운데 |

- **와이어 1440×900**(높이 900)
```
y   0 ┌──────────────────────────────── nav 64(투명) ──────────────────────────────────┐
y 162 │                     ╭──────── 돔 꼭대기(핵 1.5 · 띠 9) ───────╮                      │ 돔 d1260 · 중심 (720,792)
y 176 │              ╭──────╯     [😊 00:00]  139×40  ← 메뉴바 라벨     ╰──────╮              │ 빛 한 줄의 출발점
y 236 │          ╱                  출퇴근 기록을,          t-display 88 × 2줄     ╲          │
      │         │                   메뉴바 하나로.          (폭 ≈ 575, 433–1007)     │         │
y 450 │         │        근무 시작을 누르면 팀 전체에 바로 보여요.     t-lead 20/32 ink-2   │         │
      │         │        일하는 동안엔 아잉이 화면 구석에서 함께해요.                      │         │
y 542 │         │              [ Mac용 다운로드 176×48 ]  [App Store 배지 144×48]          │         │
y 604 │       ◜ │                macOS 14 이상 · 무료    brew로 설치                       │         │
      │     빛 │                                                                         │         │
y 685 │     한 ╰──╮               ⟨오늘도 화이팅!⟩ 148×54                                   │         │
      │     줄    ╰──────────────▶  ◎ 아잉 228×275 (몸에 [00:00] 92×42)                     │         │
y 857 │                          ░░░░░ 웅덩이 365×55 ░░░░░                                   │         │
y 900 └──────────────── 첫 화면 끝 = 히어로 끝(돔은 여기서 잘린다) ─────────────────────────────┘
```
- **와이어 1440×789**(맥북 에어 실제 뷰포트): 돔 위 142 · d 1105 · 라벨 156–191 · H1 78.9 → 211–385 · 리드 405–469 · CTA 497–545 · 메타 559–581 · 아잉 197×238(상자 535–773) · 말풍선 윗변 601 = 메타 아래 + 20 ✓.
- **와이어 1280×720**: 돔 위 130 · 라벨 144–176 · H1 72 → 196–354 · 리드 374–438 · CTA 466–514 · 메타 528–550 · 아잉 184(clamp 하한) → 말풍선 규칙 때문에 상자가 아래로 밀려 **히어로 743px**(아잉 발 23px 가 첫 화면 아래 — 허용, `min-height:100svh` 이고 고정 높이 아님).
- **와이어 390×844**
```
y  0  nav 56
y 76  ╭── 돔 d 230vw(897), 꼭대기 76, 양끝은 화면 밖 = 얕은 지평선 ──╮
y 90      [😊 00:00] 30px
y136      출퇴근 기록을,          t-display 40/44 × 2
          메뉴바 하나로.
y240      근무 시작을 누르면 …  (3줄, t-lead 16/25.6, 폭 ≤ 350)
y341      [   Mac용 다운로드  (폭 100%, ≤ 320)   ]   ← iOS: 이 버튼 없음, 배지가 맨 앞
y401      [ App Store 배지 48 ]   (D22-3 — 모든 뷰포트 48)
y459      macOS 14 이상 · 무료   brew로 설치
y636      ⟨오늘도 화이팅!⟩
          ◎ 아잉 219×265  (빛 한 줄 없음)
y828  └ 히어로 끝
```
- **세로 흐름 규칙**(B §3.3): 내비 자리 → 라벨(`margin-top: calc(var(--dome-top) + 14px)`) → 20 → H1 → 20 → 리드 → 28 → 버튼 줄 → 14 → 메타 → **유연 여백(flex 1, 최소 0)** → 아잉 무대(아래 여백 16). **불변식: 말풍선 윗변 − 메타 아랫변 ≥ 16px**(상자 위 27.7% 는 말풍선 자리라 글 블록과 겹쳐도 되지만 말풍선이 글을 덮으면 안 된다). 못 지키면 히어로가 길어진다.
- **모션 ① 도착(1회)** — 조건: `load` + idle 뒤, 히어로가 50% 이상 보이고, `scrollY < 40`, 감속 아님, Save-Data 아님, **(desk 무대 모드) commute-start 가 재생 가능해짐**(AingClip `onOnceReady` — 빛은 언제나 진짜 렌더에서 끝나야 하므로 반응이 준비되기 전에는 출발하지 않는다, DECISIONS D28-1). 도착 마감: 내비게이션 시작 후 **2.5s** 안에 commute-start 가 재생 가능(`canplay`)하지 않으면 빛 한 줄·폴짝·말풍선을 건너뛰고 근무 라벨만 켠 뒤 idle 로 간다(포스터와 같은 자세라 티가 나지 않는다 — 글을 읽는 도중 뛰어오르지 않게, B 접목).

| t(ms) | 일 | 시간 · 커브 |
|---|---|---|
| 0 | 빛 한 줄 출발: 머리가 **돔 꼭대기(라벨 바로 위)에서 림을 타고** 시계 반대 방향으로 내려가다, 말풍선 높이 − 80px 에서 림을 떠나 말풍선 왼쪽 끝으로 휘어 들어간다. 꼬리는 따라 그려진다(`stroke-dashoffset 100 → 0`). 머리는 흰 5px + 이중 글로우(림 핵과 같은 색이면 안 보인다) | 1000ms 두 구간: 림 등속(≈300ms) → 착지 `--ease-out`, 이음매 속도 일치(§2.7 `--t-comet` · DECISIONS D27-1·D28-3) (desk 무대 모드만) |
| 1000 | **도착**: `aing-commute-start` 재생(45f, 1.5s, 폴짝 + 360°) + 말풍선 등장(120ms 선형 + .96→1 200ms ease-out) + 근무 라벨 즉시(앱처럼) | — |
| 1000–2200 | 빛 한 줄 전체 불투명 1 → 0 | 1200ms 선형 |
| 2500 | idle 로 층 교체: `idleResumeFrame(45, …)` 칸부터(TD §3 순수 함수) | — |
| 6000 | 말풍선 퇴장(앱 지속 5,000ms) | 160ms 선형 |
| 2500–≈30000 | idle **2회** = 반응 뒤 이어지는 첫 바퀴(45칸~끝, ≈12.9s) + 한 바퀴(14.4s) → 그 프레임에서 일시정지(포스터로 바꾸지 않음). 실측 정지 ≈30.0s(review-motion P2-8 — 표를 구현에 맞춤) | — |
  - phone·tab·desk 아닌 경우: 빛 한 줄 없이 t=0 에 도착.
  - 히어로가 35% 미만으로 보이거나 탭이 숨으면 idle 일시정지, 돌아오면 남은 횟수만큼 이어 재생. 처음 도착 전에 히어로를 벗어났으면 도착을 건너뛴다(돌아와도 다시 하지 않음 — 근무 라벨은 켠다). **빛 한 줄이 달리는 중**(도착 전)에 벗어나도 같다 — 빛을 접고 말풍선·반응 없이, 돌아오면 근무 라벨 + idle(DECISIONS D28-4).
  - **빛 한 줄 경로**(순수 함수 `cometPath()`, `components/hero/comet-path.ts`): 돔 원 (cx, cy, r) 과 끝점 E(말풍선 왼쪽 가운데 − 8px)에서 `M cx,cy−r A r,r 0 0 0 Lx,Ly C Lx+…` — L = 림 위 y = E.y − 80 인 왼쪽 점. 원은 돔 바깥 지름에서 **5px 안쪽**(`RIM_CORE_INSET` 5 — 핵이 아니라 바로 안쪽 보라 띠 위, D27-1. 아래 1440×900 예는 설계값 r 630 그대로이고 실제 경로는 r 625). 1440×900: `M 720 162 A 630 630 0 0 0 111 632 C 160 712 380 712 580 712`(길이 ≈1,300px). 단위 테스트: 경로 표본점과 H1·리드·버튼·메타의 **글자 줄 상자** 사이가 12px 이상(1440×900·1440×789·1024×768 의 줄 상자를 고정값으로 넣어서 — 종합자 손계산 여유 23–27px). 통합 T6 은 실제 페이지에서 `Range.getClientRects()` 로 같은 단언을 한다. 림 위를 달리므로 H1 첫 줄 왼쪽 위가 가장 가깝다.
- **모션 ② 돔 패럴랙스(스크럽 1곳)**: CSS `view-timeline`(§2.8) — 돔만 `translate 0 → 14svh` · 불투명 1 → .35, 히어로가 나가는 동안. 글·버튼·아잉은 그냥 스크롤. desk 무대 모드만, 미지원 브라우저는 정적.
- **첫 페인트(SSR)**: 돔·라벨·H1·리드·버튼·메타·포스터가 바로 보인다(불투명 0 시작 금지). 말풍선·근무 라벨은 `.js` 일 때만 도착 전 숨김(§2.8) — JS 가 없으면 최종 상태.
- **감속 모션·Save-Data**: 영상 요청 0, 빛 한 줄 없음, 패럴랙스 없음. 포스터 + 말풍선 + 근무 라벨 정지(= 도착 뒤 상태). 감속 모션에서는 말풍선·근무 라벨을 하이드레이션 전 첫 페인트부터 CSS 배경(`--art`)으로 그린다(미디어쿼리가 맞을 때만 요청 — review-motion P2-6).
- **접근성**: `<section id="top" aria-labelledby="hero-h1">` · H1 하나. 라벨 `alt="메뉴바 라벨, 근무 중 00:00"`. 아잉·말풍선·근무 라벨·빛 한 줄·돔은 `aria-hidden`(같은 사실이 리드에 있다). 버튼 접근 이름 "Mac용 다운로드, aing-check.dmg 30.1MB"(크기는 `getRelease()` — 0.3.49 기준). 포커스: 주 버튼 → 배지 → brew로 설치.
- **금지**: 팝오버·[근무 시작] 버튼 흉내·핫스팟·커서, 아잉 클릭 반응(`pointer-events:none`), 말풍선 순환·두 개 이상, 펄스·점 격자·별밭·지도, 돔 안 그라디언트 워시, 아잉 CSS 변형, 히어로 눈썹 칩.
- **수용 조건**(PLAN T5·T6)
  - 1440×900 · 크롬 · 감속 아님: 로드 후 3.5s 안에 `#top [data-aing][data-arrived][data-bubble]`, `.aing-bubble`·`.aing-timer` 불투명 1(말풍선은 +5s 뒤 0), `.comet[data-run]` 이 있었고 +2.5s 에 `.comet` 불투명 0. 그 뒤 `.comet[data-run]` 이 다시 붙지 않는다(스크롤 왕복 후에도).
  - 같은 조건에서 `video.playbackRate = 16` 로 돌리면 6s 안에 `#top [data-aing][data-stopped]`(2회 상한).
  - 감속 컨텍스트: `.webm`·`.mov` 요청 0, 로드 직후 말풍선·근무 라벨 보임, `.comet` 없음 또는 `display:none`.
  - 390×844: `.comet` 없음, 도착은 일어난다(감속 아닐 때), `scrollWidth === 390`.
  - 1440×789·1280×720: 말풍선 윗변 − 메타 아랫변 ≥ 16, `getComputedStyle(h1).fontSize ≤ 0.1 × innerHeight`.
  - 첫 화면에 `img[src*="popover"]` 0개.
  - 1440×900·1024×768: `.comet-trail` 경로 표본점(`getPointAtLength`)과 H1·리드·버튼 줄·메타의 글자 줄 상자(`Range.getClientRects()`) 사이 ≥ 12px.

---

### S2. 큰 숫자 트립틱 `#moments` — 세로 스크롤 + 고정 오브젝트

- **목적**: 하루의 세 장면을 "큰 숫자 + 렌더 하나"로 각인한다(레퍼런스 100x / 5x / 100% 자리). 숫자는 전부 렌더 안에 있는 글자다.
- **카피**(캡션은 각 카드의 `<h2>` — sr-only 절 제목 없음, J3-A3)

| 장 | 큰 숫자(`t-number`, `aria-hidden`) | `<h2>`(`t-caption`) / 부제(`t-lead` ink-2) | 단락(`t-body` ink-2) | 숫자가 있는 렌더 |
|---|---|---|---|---|
| 01 / 03 | **00:00** | 근무 시작. / 버튼 하나, 메뉴바에서. (CB:81) | 메뉴바에서 근무 시작을 누르면 오늘 누적 시간이 흘러요. 깜빡해도 괜찮아요. 컴퓨터를 쓰기 시작하면 아잉이 알리면서 대신 켜고, 맥을 덮고 떠나면 덮은 시각에 맞춰 정리돼요. (CB:82) | `menubar-0000-lg` "00:00" · 헤더 "근무중 00:00" |
| 02 / 03 | **콕.** | 찔러 부르기. (CB:114) | 근무 중인 사람을 콕 찌르면 그 사람 캐릭터가 화들짝 놀라며 누가 불렀는지 말풍선으로 알려요. 꾹 누르면 울트라예요. 내 캐릭터가 상대 화면을 잠깐 덮어요. (CB:115) | 콕 목록 머리 "콕 찌르기" · 말풍선 "민트별님이 콕 찔렀어요!" |
| 03 / 03 | **12주** | 나만 보는 기록. (CB:143) | 최근 12주의 근무와 AI 토큰은 잔디로 쌓여요. 이 화면은 내 맥이 내 기록만으로 계산해요. 팀원도 볼 수 없어요. (CB:144 둘째 문장 + CB:145) | 잔디 제목 "최근 12주 AI 토큰" |

  카운터 `[ 01 / 03 ]`(`t-counter`, 현재 번호 ink-1) — 진짜 순서라 허용(brief §3).
- **구조**(무대 모드 = desk + 감속 아님 + JS. 그 밖은 같은 DOM 의 **목록 모드**)
```html
<section id="moments" class="relative">                    <!-- 절 제목 없음: 카드마다 h2 -->
  <div class="gridlines gridlines--left" aria-hidden="true"></div>
  <div class="moments-stage">                               <!-- 무대 모드에서만 display:block; sticky; top:0; 100svh -->
    <div class="obj" data-idx="0" data-active data-lit> …오브젝트 1(SSR)… <div class="obj-glow" data-glow></div></div>
    <div class="obj" data-idx="1"> …오브젝트 2(engaged 뒤 마운트)… </div>
    <div class="obj" data-idx="2"> …오브젝트 3(engaged 뒤 마운트)… </div>
  </div>
  <div class="moments-cards">                               <!-- 무대 모드: margin-top:-100svh, 카드 72svh × 3 + 꼬리 28svh -->
    <article class="moment-card" aria-labelledby="m1-h"> 숫자 · h2 · 부제 · 카운터 | 단락 | <div class="moments-inline">오브젝트 1(켜진 최종)</div></article> ×3
  </div>
</section>
```
  - 섹션 높이 = 카드 영역 = 3 × 72svh + 28svh = **244svh**(1440×900 → 2,196). 무대 고정 구간 = 144svh(scrollY 900 → 2,196).
  - 카드 안 배치(1440×900, 카드 위 기준): 숫자 위 16svh(144) · `<h2>` = 숫자 아래 + 20 · 부제 이어서 · 카운터 위 16svh − 32px(숫자 바로 위 — 58svh 면 교체 순간 이전 카드 카운터가 새 숫자 위에 붙어 읽혔다, review-design P2-1) · 단락 x 994–1368(69–95%), 위 40svh. 글 열 오른쪽 끝 ≤ 35%(476), 단락 왼쪽 ≥ 69% → 가운데 무대와 겹치지 않는다.
  - 무대 오브젝트 중심 (50.8% vw, 47svh).
- **활성 카드 · 교체 · 점등**(`lib/moments.ts`, 스크롤 리스너 없이 IO 두 줄)
  - `nextActive(prev, numberTops, vh)` 순수 함수: 다음 카드 숫자 윗변 < **.55·vh** 이면 앞으로, 현재 카드 숫자 윗변 > **.62·vh** 이면 뒤로(히스테리시스 7svh, J2-A5). 1440×900 기댓값: 0→1 at scrollY 1,197 · 1→0 at < 1,134 · 1→2 at 1,845 · 2→1 at < 1,782. 첫 카드 활성(-1→0)은 scrollY 549.
  - `engaged` = 섹션 위가 화면 30% 위로(scrollY ≥ 630) **그리고** 섹션 아래가 70% 아래(scrollY ≤ 2,466). 오브젝트 2·3 의 `<img>` 는 처음 engaged 때 마운트(+ `preloadImage`) — 첫 화면 바이트에서 빠진다.
  - **교체**(RA §4.3): 활성이 바뀌는 순간 나가는 오브젝트 `opacity 1→0`(267ms 선형) + `scale 1→.94, translate 0→∓16px`(267ms ease-in, 앞으로면 위로) / 들어오는 오브젝트 120ms 뒤 `opacity 0→1`(333ms 선형) + `scale .94→1, translate ±16→0`(333ms ease-out). 들어온 직후는 **꺼진 상태**, 450ms 뒤 점등(`--t-light` 900ms 선형). 처음 engaged 때 오브젝트 1 은 `--t-first-light` 1300ms 로 켜진다. 되돌아가면 같은 규칙으로 되감긴다(문턱형 무대라 1회성 규칙의 예외).
  - **꺼짐 = 렌더는 그대로 + 빛·링·선·말풍선 없음.** 필터(회색화) 금지.
- **오브젝트 3개**(1440 기준, 무대 좌표 = 오브젝트 상자 왼쪽 위)

| 장 | 구성 · 표시 크기 | 점등 연출(렌더 밖에서만) |
|---|---|---|
| 1 | `menubar-0000-lg` 231.5×66(3배) 위 → 보라 선 1.5×56 → `ui/header-on-lg`(**신규** 1264×428) 474×160.5(`--r-window`·`--shadow-window`). 전체 474×282 | +333ms 선이 위에서 아래로 그려짐(200ms) → 헤더 카드 `--ring-lit` 0→1(600ms) → 무대 빛 |
| 2 | `ui/poke-slice`(**신규**, 아바타 열을 뺀 콕 목록 조각 762×852 → 표시 1.3pt = 330×369, 왼쪽 16px 페이드 + 머리띠(위 56u)만 왼쪽 31u 완전 투명 노치로 잘린 "…찌르기" 를 가림, 잘린 왼쪽 변은 직각 — D20-3·D27-3) + `ui/bubble-poked-mint` 153×80 을 조각 **오른쪽 바깥** (346, 150)에(민트별 줄 높이, 겹치지 않음). 전체 499×369 | +450ms 말풍선 등장(앱 문법: 120ms 선형 + .96→1) → 무대 빛 |
| 3 | `ui/grass-token-empty` 위에 `ui/grass-token-final` 을 겹쳐 456×259.5(1.5pt) | +450ms 한 주씩 켜짐: `clip-path: inset(0 calc(100% − (9.21% + var(--cols) × 5.92%)) 0 0)`, `--cols` 0→13 을 70ms 계단(910ms). 9.21% = 84/912, 5.92% = 54/912(`grass.json` token.grid originX·pitch, cols 13 실측). 다 켜지면 무대 빛 |

- **와이어 1440×900(무대 고정, 카드 02 머묾 = scrollY 1,548)**
```
 64 ─ (내비) ──────────────────────────────────────────────────────────────────────
    │10% 선
    │144  콕.            ← t-number 104 · 300
    │     찔러 부르기.    ← t-caption 24 · 600 (h2)
    │                     ┌─ poke-slice 330×369 ─────┐ ⟨민트별님이 콕 찔렀어요!⟩      ✦ 무대 빛(하나)
    │                     │ …지르기 (집중) ⚡3 3초 꾹…│
    │                     │ 구름빵 ● 근무중  ▢ ●      │                단락 994–1368 ↓
    │                     │ 민트별 ● 근무중  ▢ ●      │    근무 중인 사람을 콕 찌르면 …
    │  [ 02 / 03 ]        └───────────────────────────┘    … 상대 화면을 잠깐 덮어요.
    │  (아래에서 다음 카드 숫자 머리가 96svh 에 보인다)
```
- **목록 모드**(tab · phone · desk 감속 · JS 없음): 고정·교체 없음. 카드 세 장을 세로로, 오브젝트는 각 카드 안 `moments-inline` 에 **켜진 최종 상태**(선 그려짐·말풍선 보임·잔디 final). 무대 빛은 **GlowGate** — 오브젝트 가운데가 화면 30–70% 띠 안이고 히어로가 .35 미만으로 보일 때만 켜진다(`InlineMoment` 클라 섬, 한 화면에 하나 — DECISIONS D28-2). JS 없음은 켜진 채. desk 감속: 카드 높이 78svh, 왼쪽 글 / 오른쪽 오브젝트 두 열. tab: 두 열. phone: 카운터 → 숫자 64 → 캡션 → 부제 → 오브젝트(라벨 154×44 + 헤더 316×107 / 조각 254×284 + 말풍선 아래 / 잔디 342×195) → 단락, 장 사이 헤어라인.
- **에셋**: `ui/menubar-0000-lg`(히어로 캐시) · `ui/header-on-lg` 18,626 · `ui/poke-slice` 18,438 · `ui/bubble-poked-mint`(4x) ≈10,500 · `ui/grass-token-empty` 9,332 · `ui/grass-token-final` 18,580.
- **접근성**: 카드마다 `<article aria-labelledby>` + `<h2>`. 큰 숫자 `aria-hidden`(캡션·단락이 같은 뜻), 카운터는 `<p>`(읽힘, 대괄호는 `aria-hidden` — "01 / 03"). 렌더 alt 는 두 벌 모두에 둔다 — 모드마다 한 벌만 `display` 되므로 접근성 트리에는 늘 한 벌이다(무대 모드: 무대 이미지 중 **활성 오브젝트만** — 나머지 `.obj` 는 `aria-hidden`, 목록 모드: 인라인 이미지). 빛·선·웅덩이·말풍선은 `aria-hidden`(D26-3). 무대의 오브젝트 2·3 은 engaged 전에는 마운트되지 않지만 같은 사실이 카드 글에 있다. 포커스 대상 없음.
- **금지**: 가로 이동·스크롤 스냅·휠 가로채기, 오브젝트 CSS 필터, 사용자 수·별점, 아바타 배지가 보이는 크롭, 같은 뷰포트에 히어로 아잉 라벨 00:00 과 다른 시각의 렌더(히어로가 30% 이하로 보일 때만 engaged).
- **수용 조건**(PLAN T7)
  - 무대 모드, scrollY 1,548: `.moments-stage.getBoundingClientRect().top === 0`(sticky 동작), `[data-idx="1"][data-active]`, 1.5s 안에 `[data-idx="1"][data-lit]`, 보이는 `[data-glow="on"]` 1개.
  - scrollY 549→1,197→1,845 순으로 내리면 활성 0→1→2, 1,845 → 1,800(−45px) 되돌림에 2 유지(히스테리시스), 1,700 에서 1.
  - scrollY 0 에서 네트워크 로그에 `poke-slice`·`grass-token-*` 요청 0(engaged 전), scrollY 700 이후 요청됨.
  - 감속 컨텍스트: `.moments-stage` `display:none`, 카드 3장에 인라인 오브젝트 보임, 잔디 final 보임, 교체 없음.

---
### S3. 기능 절 제목 `#features`

- **목적**: 큰 장면에서 기능 목록으로 넘어가는 숨 고르기. 무엇인지 한 줄로 정의한다(레퍼런스 절 제목 자리, RA §3.4).
- **카피**: 눈썹 칩 **Mac 메뉴바 앱 · iPhone 앱**(CB:62, 페이지에 하나뿐) · H2 `lines: ["같이 켜는", "근무 타이머."]`(CB:66 ` / ` 위치) · 서브 **일하는 시간을 스스로 재고, 팀이 지금 어디쯤인지 한눈에 보는 앱.**(CB:30)
```
1440 (높이 360, 위 96 · 아래 48)                         390 (≈320)
 │10%          ╭[아잉 16] Mac 메뉴바 앱 · iPhone 앱╮  │90%     ╭[아잉] Mac 메뉴바 앱 · iPhone 앱╮
 │                       같이 켜는                    │          같이 켜는
 │                       근무 타이머.        ← t-h2 60 │          근무 타이머.    (32 × 2)
 │      일하는 시간을 스스로 재고, 팀이 지금 어디쯤인지 한눈에 보는 앱.  ← t-lead ink-2  일하는 시간을 … (2줄)
 ● ← 스파인 머리 점(8px --violet-core) · 여기서 10% 선이 보라 토막(늘 켜짐)으로 R1 노드까지 이어진다
```
- 칩: 높이 30, 좌우 14, `--surface` 바탕, 1px `rgba(126,94,250,.55)` 테두리(보라 하한 V2 의 원천), 안에 `ui/menubar-icon`(**신규** 66×66 → 16px, 1,612B, `alt=""`) + `t-eyebrow`.
- **모션**: 없음. **감속**: 같음. **접근성**: `<h2 id="features-h">`, 칩은 `<p>`.
- **금지**: 칩 두 번째 사용, 대문자 영문, 글로우.
- **수용 조건**: DOM 에 눈썹 칩(`[data-eyebrow]`) 정확히 1개 · H2 `<br>` 1개 · 스파인 머리 점이 화면에 보임(V2).

---

### S4. 기능 행 ×5 — 왼쪽 스파인 + 576 캔버스 조립

- **목적**: 다섯 기능을 "읽은 만큼 켜지는 타임라인"으로 꿰고, 행마다 진짜 렌더가 **한 번** 조립되는 것으로 기능을 보여 준다(설명 캡션 없이). 히어로의 빛 한 줄이 남긴 문법(선 → 렌더)이 여기서 다섯 번 되풀이된다.

#### 4.0 스파인 기하와 점등(이름은 `Rail` — `Spine` 금지, TD §0.1-7)
- 선: x = 10% 선(1440 에서 144), 1px `--line`. **각 행이 자기 토막을 그린다**(행 위 ~ 아래). 기능 절 제목이 머리 점과 첫 토막을 그린다.
- 노드: 24×24(phone 20), 중심 x = 선, 중심 y = 행 라벨(`t-kicker`) 가운데(행 위 + 40 + 7).
- 점등: 행이 조립을 시작하는 순간 노드가 켜지고(400ms 선형) **그 행의 토막**이 보라(`linear-gradient(transparent, rgba(126,94,250,.45))`)로 위에서 아래로 그려진다(`scale 1 0 → 1`, 400ms ease-out). 한 번 켜지면 꺼지지 않는다.
- 라벨: x = 12.5%(180), `t-kicker`. 라벨 → H3 12 · H3 → 본문 20 · 본문 → H4 32 · H4 → 본문 12.
- 문턱: 노드가 화면 위에서 **68svh** 를 지날 때(IO `rootMargin: 0px 0px -32% 0px`), **한 번**. 마운트 때 이미 지나 있으면(해시·뒤로 가기) 전이 없이 완성(`data-on` + `data-instant`).
- 바닥 빛: 캔버스 중심선이 화면 30–70% 띠 안일 때만 `data-glow="on"`(§2.9). 조립(1회)과 별개로 켜지고 꺼진다.

#### 4.1 공통 조립 타임라인(문턱 t=0, ms) — RA §4.4 순서 그대로
| 시각 | 일 | 시간 · 커브 |
|---|---|---|
| 0 | 노드·스파인 토막 점등 | 400 선형 / ease-out |
| 0–200 | 첫 선(트렁크) 그리기 | `--t-draw` ease-out |
| 120–440 | 주 렌더 자리: 빈 창(`--surface` + `--shadow-window`) 불투명 0→1 · scale .96→1 | 320 선형 / ease-out |
| 360–630 | 타일 팝(scale .6→1, 오버슈트) — 타일 있는 행만 | 270 `--ease-pop` |
| 440–780 | 주 렌더 내용이 빈 창 위로 페이드 | 340 선형 |
| 600–800 | 가지 선 그리기 | 200 ease-out |
| 700– | 자식 차례로(100ms 간격): 렌더 = 불투명 240 선형 + translate 8→0 240 ease-out / 말풍선 = 앱 문법(120 선형 + .96→1 200) | — |
| 900–1230 | 점 격자(캔버스 뒤, inset −40, 타원 마스크) 0→1 | `--t-dots` 선형 |
| 900–1300 | 선 `--wire-draw` → `--wire-rest` | `--t-dim` 선형 |
| 합계 | **1,300ms**(레퍼런스 36–39f) · R1 만 +380ms("1"이 사라짐) | |

#### 4.2 행별 명세(캔버스 576 폭 · 좌표 = 캔버스 px (x, y, w, h) · 1440 에서 k=1 · 캔버스 높이 ≤ 480)
렌더 상자끼리 겹치지 않는다(교체 짝 제외 — T8 이 단언). 좌표는 출발값이고, 통합이 1440 캡처를 보고 ±8px 안에서 다듬을 수 있다.

**R1 `#f-message` — 라벨 `콕 / 메시지`**(앱 레일 이름, CB:123)
- H3 `["하고 싶은 말은,", "메시지로."]`(CB:114 ✓v4) · 본문 **할 말은 1:1 메시지로 보내요. 상대가 읽으면 옆의 1이 사라져요. 방해받기 싫은 날엔 집중 모드를 켜 두세요.**(CB:116)

| 요소 | 에셋 · 표시 | 상자 | 등장(ms) |
|---|---|---|---|
| 주 렌더 | `ui/message-unread-panel` → `ui/message-read-panel`(**신규** 954×900, 1.2pt) | (0, 48, 382, 360), 아래 40px 페이드 | 120 자리 · 440 내용 |
| 타일 | `.tile` + `ui/menubar-icon-dot` 32px — 새 메시지면 메뉴바 아이콘에 빨간 점(`CheckApp.swift:31`, CB §5.10) | (504, 0, 48, 48) | 360 |
| 말풍선 | `ui/bubble-message-gureum` "구름빵님: 커피 한잔 해요 ☕️" | (390, 200, 183, 74) | 700 |
| 선 | 트렁크 `M 330 48 V 24 H 504` · 가지 `M 382 160 H 470 V 200` | | 0 · 600 |
| 바닥 빛 | `--w: 382px`, 위 368 | | GlowGate |
| **'숫자 움직임' 하나** | 1,500–1,680ms 에 unread → read 교차(`.swap-to`, 180 선형): 내 말 옆 "1"이 사라진다(레퍼런스 지갑 카운트업 자리, 렌더 교체만) | | 1회 |

**R2 `#f-character` — 라벨 `캐릭터`**(CB:126)
- H3 `["일한 만큼,", "루비."]`(CB:128 ✓v4) · 본문 **일한 시간만큼 루비가 쌓이고, 상점에서 캐릭터를 골라요. 고른 캐릭터는 바탕화면·메뉴바·팝오버에서 함께 바뀌어요.**(CB:130)
- H4 `["캐릭터를 누르면, 오늘 할 일."]`(CB:131 ✓v4) · 본문 **캐릭터를 누르면 작은 할 일 목록이 열려요. 못 끝낸 일은 다음 날로 넘어오고, 맥과 아이폰과 위젯이 같은 목록을 써요.**(CB:131)

| 요소 | 에셋 · 표시 | 상자 | 등장 |
|---|---|---|---|
| 주 렌더 | `ui/character-panel`(**신규**, 캐릭터 6종이 보이는 유일한 컷 — 페이지에서 한 번만) | (0, 70, 360, 340) | 120 · 440 |
| 자식 1 | `ui/bubble-ruby` "루비 +3!" | (400, 40, 119, 59) | 700 |
| 자식 2 | `ios/widget-todos-large`(할 일 위젯 — v1 할 일 보드 렌더 대신, J1-A4) | (376, 150, 200, 210) | 800 |
| 선 | 트렁크 `M 360 240 H 368` · 위 가지 `M 368 240 V 70 H 400` · 아래 가지 `M 368 240 V 255 H 376` | | 0 · 600 |
| 타일 | 없음(리듬: 타일은 R1·R3·R5) | | |
| 바닥 빛 | `--w: 360px`, 위 370 | | |

**R3 `#f-break` — 라벨 `쉬는 시간`**(CB:167)
- H3 `["한 판,", "쉬어 가기."]`(CB:169) · 본문 **타이밍 바·플래피 아잉·테트리스로 오늘 순위에 도전해요. 오목과 체스는 1:1로 겨루고, 상대가 없으면 AI와 혼자 둬요.**(CB:170)

| 요소 | 에셋 · 표시 | 상자 | 등장 |
|---|---|---|---|
| 주 렌더 | `ui/minigame`(1400×779, 8줄 판) .78pt. 빈 창일 때 테두리 `--ring-lit` 0→1(120–600) 후 600–1000 에 꺼짐(레퍼런스 "제목줄이 보라로 차올랐다 꺼짐"의 렌더 밖 번역) | (0, 176, 546, 304) | 120 · 440 |
| 타일 | `.tile` + `ui/menubar-icon-dot`(오목 신청도 같은 점) | (300, 40, 48, 48) | 360 |
| 자식 | `ui/gomoku-board-sm`(판돈 칸이 잘린 판) | (414, 0, 144, 160) | 700 |
| 선 | 트렁크 `M 324 176 V 88` · 가지 `M 348 64 H 414` | | 0 · 600 |
| 바닥 빛 | `--w: 546px`, 위 440 | | |

**R4 `#f-ranking` — 라벨 `순위`**(아이폰 탭 이름, CB:187)
- H3 `["이번 달 AI 토큰,", "전체 순위판."]`(CB:154 ✓v4) · 본문 **이 맥의 Claude Code·Codex 기록에서 숫자만 세어 이번 달 사용량을 보여 줘요. 대화 내용은 읽지 않아요.**(CB:155)
- H4 `["팀끼리는, 리그로."]`(CB:100 ✓v4) · 본문 **다른 팀과는 1인당 평균으로 나란히 서요. 리그에는 팀 숫자만 오르고 개인 숫자는 오르지 않아요.**(CB:102)

| 요소 | 에셋 · 표시 | 상자 | 등장(레퍼런스 구독 행: 카드 둘이 8f 간격) |
|---|---|---|---|
| 카드 1 | `ui/token-slice`(**신규**, 아바타 열을 뺀 이번 달 토큰판, 1pt) 왼쪽 16px 페이드 + 머리띠(위 46px)만 왼쪽 5px 완전 투명 노치로 '◀' 조각을 가림, 잘린 왼쪽 변 직각(D20-3·D27-3) | (0, 60, 236, 335) | 120 |
| 카드 2 | `ui/league-slice`(**신규**, 아바타 열을 뺀 팀별 이번 주 3팀, 1pt) 왼쪽 28px 페이드 | (300, 180, 248, 213) | 387 |
| 선 | 접합점(5px `--violet-core`)이 (288, 30)에 먼저 → `M 288 30 H 118 V 60` · `M 288 30 H 424 V 180` 동시 | | 0–260 |
| 타일 | 없음 | | |
| 바닥 빛 | `--w: 548px`, 위 360(두 카드 아래 하나) | | |
| 사실 주의 | 리그의 우리 팀 총합(171시간 40분)과 팝오버 팀 행 합은 소재끼리 어긋난다(CB §11 ⚠). 이 행과 같은 뷰포트에 팝오버 팀 카드가 없다(R3·R5 사이) | | |

**R5 `#f-iphone` — 라벨 `iPhone`**(CB:180)
- H3 `["이제,", "아이폰에서도."]`(CB:182 ✓v4) · 본문 **맥에서 켠 근무가 폰에서도 보여요. 팀 현황·메시지·할 일·순위·게임을 폰에서 보고, 홈 화면 위젯으로도 봐요.**(CB:183) · 작은 줄(`t-small` ink-3) **근무 시작·종료는 맥에서 해요.**(CB:185)

| 요소 | 에셋 · 표시 | 상자 | 등장 |
|---|---|---|---|
| 주 렌더 | `PhoneShell screenWidth={208}`(셸 ≈222×467) + `ios/now`(다크) | (24, 0, 222, 467) | 120 · 440 |
| 타일 | **앱 아이콘 그대로**(`brand/icon-256` 48px, `.tile` 그림자만 — 레퍼런스의 "보라 그라디언트 앱 아이콘 타일"을 우리 진짜 아이콘으로) | (516, 0, 48, 48) | 360 |
| 자식 | `ios/widget-today-small` | (300, 150, 160, 160) | 700 |
| 선 | 트렁크 `M 246 230 H 300` · 타일 선 `M 246 24 H 516` | | 0 · 600 |
| 바닥 빛 | `--w: 540px`(합집합 — D20-2), 위 **398**(430 이면 타원 아래 절반이 숫자 격자 이음매를 넘었다 — review-design P2-5) | | |

**변주(같은 구도 반복 금지 — B 감점 사유)**: R1 패널 + 타일 + 말풍선 · R2 패널 + 말풍선 + 위젯(타일 없음) · R3 넓은 창 + 타일 + 작은 판 · R4 카드 둘 + 접합점(타일 없음) · R5 폰 + 위젯 + 앱 아이콘 타일.

- **와이어 1440(R1, 행 높이 560)**
```
 │144                          │720(50% 선 = 캔버스 왼쪽)                  │1296(90%)
 │                             │                                 ┌tile┐  │
 ■ 콕 / 메시지  ← 노드 + t-kicker │        ┌─── 트렁크 ──────────────┤ ●  │  │
 │ 하고 싶은 말은,   ← t-h3 44 ×2 │┌─ 메시지 패널 382×360 ─┐       └────┘  │
 │ 메시지로.                     ││ < 구름빵             ├─ 가지 ┐        │
 │ 할 말은 1:1 메시지로 보내요. … ││ … 1 좋아요! 배포하고… │   ⟨구름빵님: 커피 한잔 해요 ☕️⟩
 │ (단락 17/29, 폭 ≤ 425)        │└──────────────────────┘                 │
 │  · · · 점 격자 · · ·  ░░ 바닥 빛 ░░                                        │
```
- **와이어 390(모든 행 공통)**
```
 │20 ■ 콕 / 메시지             ← 스파인 x 20, 노드 20, 글 열 48–370
 │   하고 싶은 말은, / 메시지로.  (t-h3 26)
 │   할 말은 1:1 … (t-body 16)
 │   ┌ 주 렌더 폭 min(100%, 322) ┐   ← 캔버스 대신 세로 묶음
 │   └────────────┬─────────────┘   ░ 바닥 빛 ░
 │                │ 세로 선 24 (트렁크 하나, 타일 숨김)
 │   [자식1 ≤ 150] [자식2 ≤ 150]
```
- **감속 모션**: 처음부터 완성(선 rest 색·점 격자·노드 점등·토막·R1 은 read 판). 전이 0. 바닥 빛은 띠 규칙 그대로(불투명 페이드만).
- **접근성**: 행마다 `<article aria-labelledby="f-…-h">` + `<h3>`, 라벨 `<p>`. 렌더마다 alt(§6.5), 말풍선은 `aria-hidden`(페이지 크롬 — 같은 사실이 패널 alt·본문에 있다, img alt 는 `bubbleText()` 원문 그대로 남음 — DECISIONS D26-3), 타일 아이콘 `alt=""`. 선·점·노드·바닥 빛 `aria-hidden`. 포커스 대상 없음.
- **에셋 합계**: R1 70,794 · R2 56,676 · R3 51,116 · R4 35,796 · R5 45,862 = **260,244B**(행이 화면 1,200px 안에 들어올 때 `<img>` 마운트 — `useNearViewport`, 그 전엔 `<noscript>` 폴백. DECISIONS D25-1).
- **금지**: "Learn more"·더보기, 목업 안 커서·클릭 연출, 되감기, 행마다 같은 구도, 범용 아이콘, 캐릭터 6종 컷 두 번째 노출, 판돈 글자가 보이는 오목 판, 센터 배지가 확대된 크롭, 로봇·체스·테트리스·AI 리밋 그림.
- **수용 조건**(PLAN T8): 각 행에 대해 (1) 노드가 68svh 를 지나기 전 `data-on` 없음 → 지난 뒤 1.5s 안에 `data-on` + `.wire` dashoffset 0 (2) 아래로 지나쳤다가 위로 되돌아와 다시 내려가도 `data-reveal-count="1"` (3) 캔버스 안 렌더 상자 교차 0 (4) R1 은 2s 뒤 `.swap-to` 불투명 1 (5) 캔버스 중심이 화면 50% 에 있을 때 그 행 `.floor-light[data-glow="on"]`, 다른 행은 off (6) 감속 컨텍스트에서 로드 직후 모든 행 최종 상태.

---

### S5. 숫자 격자 `#facts`

- **목적**: 결정에 필요한 사실(요금·요구 사항·크기·범위·안심)을 숫자 여덟 개로. 레퍼런스 In Numbers 자리, 지표 대신 제품 사실(brief §1).
- **카피**: 제목(`t-facts-title`) `lines: ["작은 Mac 팀을 위한", "메뉴바 근무 타이머."]`(CB:29) · 그 아래 안심 한 줄(`t-small` ink-2, 최대 22em, 앞에 2px 보라 틱 하나 — D27-2(d)) **스크린샷·키 입력·마우스 움직임·앱과 웹 사용 기록을 모으지 않아요.**(CB:199 첫 문장 — 안심 섹션을 따로 두지 않는 대신. 정직 문장 CB:201 은 FAQ 5번 답이 같은 사실을 말한다) · 칸 라벨은 §1.4.3 신규 라벨.
- **배치(1440)**: 위 `.seam`(가운데 진한 보라 이음매). 제목 x 176, 1행 높이에 맞춤(RA §3.6). 격자 4열 × 194(36%→90%: x 518–1296) · 2행 × 220. 칸마다 왼쪽 헤어라인(칸 높이만큼) + 위 24px `.tick`(2px 보라), 안쪽 왼쪽 20. 칸 = 라벨 위(`t-small` ink-2) / 숫자 아래(`t-facts` 52 · 300 + `t-unit` 20, 기준선 맞춤). 정적(카운트업 없음 — RA §0.2-8).

| # | 라벨 | 숫자(`FIGURES`) | 단위 | 출처 |
|---|---|---|---|---|
| 1 | 요금 | 0 | 원 | CB:21(무료, 앱 안 현금 결제 없음) · CB:17(App Store 무료) |
| 2 | macOS | 14 | 이상 | CB:19(`LSMinimumSystemVersion 14.0`) |
| 3 | iOS | 18 | 이상 | CB:17 · CB:192 |
| 4 | Mac 앱 내려받기 | 30.1 | MB | 화면 값 = `installChoice(getRelease(), RELEASE_FALLBACK).mb`(서버 렌더, 하드코딩 금지 — DMG 없으면 zip 크기). 기준 v0.3.49 `aing-check.dmg` 30,054,068B = 30.1MB(brief §1, 2026-10-12 18:06 배포) |
| 5 | 근무·AI 토큰 잔디 | 12 | 주 | CB:149 |
| 6 | 미니게임 | 3 | 종 | CB:170 · CB:173(타이밍 바·플래피 아잉·테트리스) |
| 7 | 메시지·오목·체스 | 1:1 | — | CB:116 · CB:170 · CB:174–175 |
| 8 | 외부 SDK | 0 | 개 | CB:20(Package.swift 외부 의존 0건) |

  넣지 않은 것: 위젯 수(brief "2종" ↔ CB:191 "넷" 충돌 — 리드 확인 전 제외), 캐릭터 수(일곱 금지), 24시간·7일·3시간(규칙 수치는 FAQ), 사용자 수·별점.
```
1440 (높이 640)
────────────────────────────── .seam ──────────────────────────────────────────────
 176 작은 Mac 팀을 위한   ▍요금        ▍macOS       ▍iOS         ▍Mac 앱 내려받기
     메뉴바 근무 타이머.   │0원         │14이상       │18이상       │30.1MB         ← 52 + 단위 20
     스크린샷·키 입력·…   ▍근무·AI 토큰 잔디 ▍미니게임  ▍메시지·오목·체스 ▍외부 SDK
     모으지 않아요.        │12주        │3종          │1:1          │0개
390: 제목 → 안심 한 줄 → 2열 × 4행(칸 구분은 위선), 숫자 36
```
- **모션**: 없음. **감속**: 같음. **접근성**: `<h2>` = 제목, 격자 `<dl>`(칸 = `<div><dt>라벨</dt><dd>숫자<span>단위</span></dd></div>`). **금지**: 아이콘, 카운트업, `+` 기호(18+ 가 나이 등급처럼 읽힌다).
- **수용 조건**: `dl > div` 8개, 4번 칸 숫자 = `/api/release` 의 `dmg.mb`(없으면 zip), `.t-facts` 의 글자 ⊂ `pretendard-300-num.txt`(T1 check-glyphs), V6 보라 ≥ 0.02%.

---

### S6. 설치 `#install` — DMG 주 · brew · App Store

> **v2.1(brief-v21 §2 — 아래 v2 명세보다 이긴다)**: H2 + Mac 열(DMG 버튼 · 메타 1줄 · 3단계 · brew 명령+복사) + iPhone 열(배지 · QR · "iOS 18 이상 · 무료") + 업데이트 1줄만. 팀 참여 3걸음·"터미널이 편하다면"·zip 링크·iPhone 둘째 줄 삭제(`/api/download?file=zip` 라우트 유지). 빛 = `.horizon` + `.aurora-band` + 스파인 연장(§2.9). 높이 ≈ 640.

- **목적**: 바로 설치. DMG 가 주, brew·zip 이 보조, 아이폰은 옆 열. 팀에 들어가는 세 걸음과 업데이트 한 줄까지.
- **카피**: H2 `["지금, 메뉴바에."]`(CB:224) · 열 제목 `<h3>` **Mac** / **iPhone**(보이는 `t-kicker`, CB §10 표기)
  - Mac: 주 버튼 **aing-check.dmg 다운로드**(CB:227, DMG 없으면 **aing-check.zip 다운로드**) · 메타 `v{버전} · {크기}MB · ` + **macOS 14 Sonoma 이상 · Apple Silicon·Intel · Apple 공증**(CB:228) · 단계 `<ol>` **받은 파일을 열어요** / **aing-check 아이콘을 Applications 폴더로 끌어다 놓아요** / **실행하면 메뉴바 오른쪽 위에 아이콘이 떠요**(CB:229) — 3번 옆에 `ui/menubar-off`(185×66 → 92.5×33, 2,886B, 실제로 뜨는 라벨) · 라벨 **터미널이 편하다면**(CB:234) · `CommandBox` **brew install yehsung/check/aing-check** + [**복사**] → **복사했어요**(CB:235) · 링크 **GitHub Releases에서 zip으로 받기**(CB:238, 누를 자리 45.7px). (CB:236 brew 업데이트 문장은 뺀다 — 업데이트 문장은 맨 아래 한 줄 하나, DECISIONS D26-1)
  - iPhone: App Store 배지(높이 48) · QR 112(desk 만, `brand/qr-appstore.svg` 3,257B, 지역 코드 없는 판) · **iOS 18 이상 · 무료** · **근무 시작·종료는 맥에서 해요.**(CB:243)
  - 팀 참여 `<ol>`(진짜 순서라 번호): **1 가입** 별명·이메일·비밀번호로 가입해요. / **2 팀 코드** 팀원에게 받은 팀 코드를 넣으면 들어갈 팀 이름이 미리 떠요. 팀이 없으면 새 팀을 만들고, 생긴 코드를 동료에게 건네요. / **3 메뉴바** 그다음부턴 메뉴바에서 근무 시작만 누르면 돼요.(CB:246–248)
  - 업데이트 한 줄(`t-small` ink-2, 앞에 `ui/menubar-icon-dot` 16px `alt=""`): **새 버전이 나오면 메뉴바 아이콘에 작은 점이 떠요. 지금 업데이트 한 번이면 설치하고 다시 켜져요.**(brief §1 리드 확정 문장 — 0.3.49 부터 DMG 설치본도 앱 안에서 스스로 교체되므로 설치 경로를 가르지 않는다. v1 S11 의 DMG 덮어쓰기 문장은 폐기, §1.4.3)
```
1440 (높이 760)
 ─────────────── .horizon(돔 림을 편 선) ───────────────────────────────────────
 │10%                          │50%                           │90%
 │              지금, 메뉴바에.   ← t-h2 60 가운데
 │ Mac                          │ iPhone
 │ [ aing-check.dmg 다운로드 ]   │ [App Store 배지 48]   ▣ QR 112(흰 타일 r12)
 │ v0.3.49 · 30.1MB · macOS 14 Sonoma 이상 · …   │ iOS 18 이상 · 무료
 │ ① 받은 파일을 열어요          │ 근무 시작·종료는 맥에서 해요.
 │ ② … Applications 폴더로 …    │
 │ ③ … 아이콘이 떠요 ▓😟 오프▓   │
 │ 터미널이 편하다면             │
 │ ┌ $ brew install yehsung/check/aing-check  [복사] ┐ ← --bg-1 줄, --r-code, t-code
 │ 업데이트는 … / GitHub Releases에서 zip으로 받기
 │ ─────────────────────────────────────────────────────────── --line
 │ 1 가입 …                │ 2 팀 코드 …              │ 3 메뉴바 …   ← 3열, 번호 t-facts-title 500 ink-3
 │ ▓•▓ 새 버전이 나오면 메뉴바 아이콘에 작은 점이 떠요. …
390: H2 → (data-platform=ios 면 iPhone 묶음 먼저: .order-ios-first) → Mac 묶음 → 팀 3단계 세로 → 업데이트 줄. 명령은 '/' 뒤 <wbr>, 가로 스크롤 0, QR 숨김
```
- **구현 전제**: `DownloadCTA placement="install" size="l" tone="fill" file="dmg"`(iOS 에서도 같은 DMG 링크 — 설치 절은 플랫폼과 무관하게 Mac 안내를 보인다), `/api/download`(302, DMG 기본·`?file=zip`), `installChoice()`·`INSTALL_COPY`(`data/install-copy.ts`), `CommandBox`·`CopyButton`(→ `lib/announce`), `AppStoreBadge height={48}`, `QrCode size={112}`. v1 installHint(누른 뒤 바뀌는 안내)는 **없음** — 단계는 처음부터 정적으로 보인다.
- **모션**: 버튼 호버(색 120ms 선형)·눌림만. **감속**: 같음.
- **접근성**: 다운로드 링크 접근 이름 "aing-check.dmg 다운로드, 30.1MB". 복사 성공은 `LiveAnnouncer` "복사했어요". 복사 버튼 `aria-label="brew 설치 명령 복사"`.
- **금지**: "경고 없이 열려요"(CB:231), "확인 메일" 약속, 센터(서울/부산), DMG 창 그림, 공유 시트.
- **수용 조건**: 주 버튼 `href="/api/download"`(또는 `?file=zip`), 복사 → 클립보드 `brew install yehsung/check/aing-check` + 버튼 글자 "복사했어요"(2s 뒤 "복사"), 390 `scrollWidth === 390`, iOS UA 에서 iPhone 열이 먼저(`getBoundingClientRect().top` 비교), V7 보라 ≥ 0.02%.

---

### S7. FAQ `#faq` — 왼쪽 정렬 한 열

> **v2.1(brief-v21 §2·§5 — 아래 v2 명세보다 이긴다)**: **5문항**(CB §7 의 1–5번 = CB:254–263 순서 그대로, JSON-LD 도 5개, 1번 열림). 빛 = `.aurora-tail`(α .08 + 타원 빛) + 열린 행 빛 헤어라인 + 스파인 연장(§2.9). desk 위아래 패딩 96. 수용(T12): `details[name=faq]` 5 · JSON-LD 질문 5 · `/#faq-3` → 3번만 open.

- **목적**: 설치 직전 질문 정리. 규칙 수치(24시간·7일 등)는 여기서만. 정직 문장(CB:201)의 사실은 5번 답이 맡는다.
- **카피**: H2 `["자주 묻는 것."]`(CB:252 — 내비 링크 이름과 맞춘다) · 10문항 = `data/faq-items.ts`(CB:254–273 그대로, v1 S12 와 같은 문장). 센터 문항 미게재.
- **배치**: 제목 x 176(위), 목록은 그 아래 x 176 부터 **최대 폭 760**(왼쪽 정렬 한 열 — 숫자 격자의 '왼쪽 제목 + 오른쪽 칸', 설치·아웃트로의 '가운데'와 다른 구도). 행 위아래 패딩 20, 행 사이 `--line`, 질문 `t-faq-q`, 답 `t-body` ink-2 최대 40em.
```
1440 (높이 ≈1,040)
 176 자주 묻는 것.                                    (t-h2)
     ─────────────────────────────────────────────────  ← 열린 행 위는 .faq-open-line(빛 한 줄)
     요금이 있나요?                                 ▾
     무료예요. 앱 안에서 현금 결제를 받지 않고, …
     ─────────────────────────────────────────────────
     어떤 기기에서 쓰나요?                           ▸
     … ×10                                   (오른쪽 끝 x 936)
390: 같은 구도, 전폭
```
- `<details name="faq" id="faq-{n}">`(1번 `open`), 높이 전이는 `::details-content` + `interpolate-size` 지원 브라우저만. 디스클로저 ▸ 10px ink-3, 열리면 90° 180ms ease-out · `--violet-bright`(D27-2(b)). `FaqHash`(`#faq-n` 딥링크) · `faqJsonLd()`(`FAQPage`) 그대로.
- **감속**: 회전·높이 전이 0. **접근성**: summary 네이티브, 삼각형 `aria-hidden`. **금지**: sticky 제목, 열린 행 면 칠하기, +/× 아이콘.
- **수용 조건**: `/#faq-3` 진입 → 3번만 `open` · JSON-LD 파싱 결과 질문 10개 · 열린 행 위 `.faq-open-line` 존재 · V8 ≥ 0.02%.

---

### S8. 아웃트로 `#outro` — 작은 돔 아래 아잉(북엔드)

- **목적**: 레퍼런스 엔드카드 자리. 처음의 돔이 작게 돌아오고(앱 아이콘 구성: 링 + 아잉) 마지막 다운로드를 건넨다.
- **카피**: H2(`t-closing`) `lines: ["메뉴바에,", "아잉 하나."]`(CB:280) · 리드 **맥에 설치하고, 팀 코드를 나눠 주세요.**(CB:281) · 버튼 **Mac용 다운로드** · App Store 배지 · **brew 명령 복사** → **복사했어요**(CB:282, iOS 에서는 숨김 — DECISIONS D26-4)
```
1440 (min-height 80svh = 720 · 바탕: 위 160px 동안 bg-0 → bg-outro)
 126              .·´¨¨¨¨¨¨¨¨¨¨¨¨¨¨`·.        작은 돔 d = min(60vw, 92svh, 860) = 828, 꼭대기 14svh
 196          .´        메뉴바에,          `.   t-closing 64 × 2, 가운데
             /          아잉 하나.            \
 359        |   맥에 설치하고, 팀 코드를 나눠 주세요.  |  t-lead
 419        | [Mac용 다운로드] [App Store 48] (brew 명령 복사) |
            |            ◎ 아잉 200×242               |   (상자 위 27.7% 는 비어 있다 — 말풍선 없음)
 704        |         ░░ 웅덩이 ░░                    |
 720  └ 푸터 윗변(--line) ───────────────────────────────┘
390: 돔 d 200vw · 꼭대기 10svh · H2 36 · 버튼 세로 쌓기(폭 100%) · 아잉 clamp(170px, 24svh, 220px)
```
- 세로 흐름은 히어로와 같은 규칙(유연 여백, 아잉은 아래). 아잉 폭 desk `clamp(184px, 24svh − 16px, 220px)`.
- **아잉 = 브랜드 마크**: idle 만(근무 라벨·말풍선 없음). 앱 아이콘이 링 안에 라벨 없는 아잉을 그리는 것과 같은 구성이라 '근무 중 상태' 주장이 아니다. 꾸벅 → idle 은 앱에 없는 상태라 쓰지 않는다(J1-B5·J2-B6).
- **모션(자동 2/2)**: 절이 45% 보이면 1회: 내용 불투명 0→1 `--t-fade` 600ms 선형(레퍼런스 18f 페이드) → `char/aing-idle` 14.4s × **2회**(레퍼런스 마크 루프 ×2) → 그 프레임에서 일시정지. 화면 밖이면 일시정지, 돌아오면 남은 횟수만 재생. 포스터 `char/aing-idle-poster`(idle 0번 = 재생 시작 자세).
- **감속**: 영상 요청 0, 포스터 정지, 페이드 없음.
- **에셋**: `char/aing-idle-poster.webp` 17,748 · `char/aing-idle.{webm 808,263 | mov 817,960}`(히어로와 같은 URL — 캐시되면 0, phone `-15` 판 536,078 / 523,861).
- **접근성**: `<h2>`. 아잉 `aria-hidden`, 포스터 `alt=""`. 버튼 포커스 순서 = 시각 순서. brew 복사 = `CopyButton variant="secondary" label="brew 명령 복사"`.
- **금지**: 다른 캐릭터, 꾸벅 → idle, 아잉 CSS 변형, 영상 컨트롤 UI, 색종이·하트 장식, "근무 종료" 버튼.
- **수용 조건**: 절 45% 진입 후 1s 안에 내용 불투명 1 · 감속에서 영상 요청 0 · `playbackRate=16` 로 `[data-stopped]` · V9 보라 ≥ 2%.

### S9. 푸터
`SiteFooter` 그대로(TD §1.2 이동): 한 줄 **아잉체크(aing-check)는 작은 Mac 팀을 위한 메뉴바 근무 타이머예요.**(v1 S14, CB:29·CB:328) · 링크 지원·개인정보 처리방침·이용약관·GitHub·버그·요청·글꼴 라이선스(CB:283) · © 2026 아잉체크. 위 `--line`, 바탕 `--bg-outro`(아웃트로와 이어짐), 패딩 48/64, 왼쪽 앱 아이콘 24px.
- **수용 조건**: 링크 6개의 `href` 가 SPEC 값과 같음(지원·처리방침·약관·GitHub·이슈·`/licenses`) · DOM 에 "아잉체크(aing-check)" 정확히 1회 · 감속·phone 에서 같은 마크업(링크는 phone 에서 세로 목록) · `/licenses` 200.

---
## 4. 반응형 — 390 / 768 / 1024 / 1440

모드 문자열은 v1 그대로(`desk` = 폭 ≥ 1024 **그리고** 높이 ≥ 640 · `tab` · `phone` < 768, `lib/hooks.ts` `MQ_*` 공유). 추가: `MQ_STAGE` = desk 이면서 `prefers-reduced-motion: no-preference` — 트립틱 무대·빛 한 줄·패럴랙스는 이때만(+ `.js`).

| 절 | 1440 (desk) | 1024×768 (desk) | 768 (tab) | 390 (phone) |
|---|---|---|---|---|
| 내비 | 64 · 링크 3 + CTA(알약 36 · 누를 자리 44 — `::before`) | 같음 | 64 · 링크 3 + CTA | 56 · 워드마크 + CTA(36 · 누를 자리 44) |
| 돔 | d 1260 · 위 162(18svh) | d 896 · 위 138 | d 120vw(922) · 위 13svh | d 230vw(897) · 위 9svh(76), 얕은 지평선 |
| 메뉴바 라벨 | 높이 39.6 | 33.8 | 40 | 30 |
| H1 | 88 | 69 | 57 | 40 |
| 아잉(히어로) | 228 | 199 | 240 | 219 |
| 빛 한 줄 | 있음 | 있음 | 없음 | 없음 |
| 패럴랙스 | 돔 14svh 가라앉음 | 같음 | 없음 | 없음 |
| 트립틱 | 무대 모드(244svh) · 오브젝트 1.5pt | 같음(높이 ≥ 640), 오브젝트 ×.71(D23-3 — ×.85 는 글과 겹침) | **목록 모드**(두 열) | **목록 모드**(한 열) |
| 기능 절 제목 | H2 60 · 2줄 | 48 | 42 | 32 |
| 기능 행 | 글 12.5–42% / 캔버스 50–90%(576, k=1) | 글 12.5–44% / 캔버스 48–94%(471, k=.82, `transform: scale(k)` origin 왼쪽 위 + 높이 보정) | 글 위 · 캔버스 아래(k = min(1, (폭 − 2·gutter − 48)/576)), 스파인 x 32 | 글 위 · 세로 묶음(§S4 390), 스파인 x 20 |
| 숫자 격자 | 제목 왼쪽 + 4×2(1280 이상 — D21-3) | 제목 위 + 4×2(768–1279, 칸 197 — D21-3) | 제목 위 + 4×2 | 제목 위 + 2×4 |
| 설치 | Mac / iPhone 두 열(50% 선) + 팀 3열 | 같음 | 같음 | 한 열 · 플랫폼 우선 · QR 숨김 |
| FAQ | x 176 · 폭 ≤ 760 | 같음 | 전폭 − gutter | 전폭 |
| 아웃트로 | 작은 돔 828 · H2 64 · 아잉 200 | 614 · 52 · 186 | 614 · 48 · 200 | 200vw · 36 · 180 · 버튼 세로 |
| 세로 격자선 | 10/50/90 | 같음 | 없음(스파인만 — D19-5) | 없음(스파인만) |

가로 스크롤 0(390 에서 `scrollWidth === 390` — 돔·작은 돔은 `overflow: clip` 상자 안). 터치 대상 ≥ 44×44. `MQ_STAGE` 가 바뀌는 순간(창 줄이기·감속 켬) 트립틱은 CSS 미디어쿼리만으로 목록 모드가 된다(JS 판단 없음 → 하이드레이션 어긋남 0).

---

## 5. 성능 예산

### 5.1 첫 화면(1440×900, 크롬, `load` 까지 전송 바이트)
| 항목 | 바이트 | 근거 |
|---|---|---|
| HTML + CSS(gzip) | ≈26,000 | 정적 SSR, v1 측정 HTML+CSS 40KB 에서 체험 마크업 제거(A §5.1) |
| JS(gzip) | ≈150,000 | Next 16 런타임 + React 19 ≈145k + 클라 섬(NavShell·HeroStage·MomentsStage·FeatureRow·Outro·FaqHash·CopyButton) ≈8k. `motion` 라이브러리 **제거**, 스크롤 리스너 0(IO + CSS scroll-driven) |
| Pretendard 500 / 600 / 300-num | ≈36,000 / ≈36,000 / ≈2,800 | B 실측 34.5k·34.5k(496자), C 실측 2.7k |
| JetBrains Mono ASCII | 4,440 | 실측 |
| `brand/icon-64` + App Store 배지 | 1,434 + 9,260 | 실측 |
| `ui/menubar-0000-lg`(히어로 라벨) | 7,138 | `synth/` 실측 |
| `char/aing-rest-poster`(preload, phone LCP) | 17,702 | `synth/` 실측 |
| `ui/header-on-lg`(트립틱 오브젝트 1 — 첫 화면 아래 423px 라 브라우저 지연 로딩 문턱 안) | 18,626 | A probe |
| **합계** | **≈309,400** | 예산 400KB. 오브젝트 2·3 은 engaged 때 마운트라 빠진다 |

### 5.2 지연 로딩 순서
1. 첫 페인트: 내비·돔(CSS)·라벨·H1·리드·CTA·메타·포스터(`<link rel="preload" as="image" fetchpriority="high">`)·배지·500·300 글꼴.
2. `load` + idle(`afterLoadIdle`): 히어로 말풍선(4x ≈7,938)·근무 라벨(11,982)·`aing-commute-start`(webm 151,047 / mov 125,839) → 도착 → `aing-idle`(webm 808,263 / mov 817,960 · phone 15fps 536,078 / 523,861). 감속·Save-Data·느린 망(`effectiveType` slow-2g·2g·3g)은 영상 0.
3. 트립틱 engaged: 오브젝트 2·3(56,896).
4. 브라우저 지연 로딩(`<img loading="lazy">`, `RenderImage`): 칩 아이콘(1,612) → 행 렌더(260,244 — 행이 1,200px 안에 들어올 때 마운트, D25-1) → 설치(6,143) → 아웃트로 포스터(17,748).
5. 아웃트로 45% 진입: idle(같은 URL — 캐시되면 0).

### 5.3 전체
| 구간 | 크롬 desk | 비고 |
|---|---|---|
| 첫 화면 | 309,400 | |
| 히어로 load 뒤 | 979,230 | 말풍선 + 근무 라벨 + commute-start + idle |
| 트립틱 2·3 | 56,896 | |
| 칩 + 행 5개 | 261,856 | |
| 설치 | 6,143 | |
| 아웃트로 | 17,748(+ idle 재요청 시 808,263) | 같은 URL |
| **합계** | **≈1,631,000(1.63MB)** · 최악 **≈2,440,000(2.44MB)** | 예산 4.5MB · 사파리(mov) ≈ 같음 · phone ≈1.36MB / 최악 ≈1.90MB · 감속·Save-Data ≈0.65MB |

### 5.4 LCP · CLS · 스크롤 · sticky 조상 규칙
- LCP: desk = **H1 텍스트**(SSR + 500 서브셋 preload + swap). phone = **아잉 포스터**(219×265 > H1 300×88) → preload + `fetchpriority="high"`. 목표 모바일 LCP ≤ 2.5s(Fast 4G · CPU 4×).
- CLS ≤ 0.05: 모든 렌더 `width/height` 명시, 플랫폼 CTA 는 `PLATFORM_SCRIPT` 가 첫 페인트 전 결정, 트립틱 섹션 높이·모드는 CSS 미디어쿼리(JS 전에 결정), 숫자 글꼴 300 preload, 히어로 말풍선·근무 라벨은 자리를 먼저 차지한 채 불투명만 바뀐다.
- 스크롤 중 장기 작업 0: **스크롤 리스너 0개**. 히어로 패럴랙스 = CSS `animation-timeline`, 트립틱·행·GlowGate·내비 = IntersectionObserver. 변형은 `transform`·`translate`·`scale`·`opacity` 만.
- **sticky 조상 규칙(J3-A2)**: `html`·`body`·`main`·`#moments` 와 그 사이 모든 조상에 `overflow: hidden|auto|scroll`·`transform`·`translate`·`scale`·`filter`·`perspective`·`contain: paint|layout|strict|content`·`will-change: transform` 금지. 가로 넘침 방지는 `overflow-x: clip` 만(`body`). 히어로·아웃트로의 `overflow: clip` 은 자기 절 안이라 무해. T17 이 계산된 스타일을 단언하고, T7 이 고정 구간 가운데에서 무대 `top === 0` 을 단언한다.
- 캔버스 셰이더·3D 라이브러리·영상 배경 없음. 글로우는 전부 CSS 그라디언트.

### 5.5 영상 규율
- 영상은 **두 무대**(히어로·아웃트로)뿐, 같은 `idle` URL. 동시에 보일 수 없다(문서 거리 7,800px).
- 로드 전 영상 요청 0. 포스터를 먼저 칠하고 영상은 `afterLoadIdle` 뒤.
- 반응(commute-start) 끝 → `idleResumeFrame()` 칸으로 idle 시작(층 교체, TD §3). idle 2회 뒤 **그 프레임에서 일시정지**(포스터로 바꾸지 않는다 — 자세 튐 0).
- 화면 밖(보이는 비율 < .35)·탭 숨김이면 일시정지, 돌아오면 남은 횟수만.
- 형식은 JS 로 하나만(`pickVideoFormat`: 사파리·iOS = HEVC 알파 `.mov`, 그 밖 VP9 알파 `.webm`), SSR·하이드레이션 중엔 포스터.

---

## 6. 컴포넌트 · 데이터

### 6.1 새 컴포넌트(이름 · 역할 · 소유 — 서명 전문은 PLAN §3)
| 파일 | 종류 | 역할 | 소유 |
|---|---|---|---|
| `components/site/SiteNav.tsx` · `NavShell.tsx` | server · client | 내비, IO 센티널로 `data-scrolled`, `useHeroCtaVisible` 로 CTA 채움 | core |
| `components/ui/Dome.tsx` | server | `.dome`(+ `--small`) + `.dome-pool` | primitives |
| `components/ui/AingClip.tsx` | client | 포스터 → (once) → idle × maxLoops → 정지, 말풍선·근무 라벨 층, 보일 때만 재생 | primitives |
| `components/ui/Wire.tsx` · `Tile.tsx` · `FloorLight.tsx` · `Gridlines.tsx` | server | §2.8 레시피를 감싼 얇은 부품 | primitives |
| `components/features/FeatureRow.tsx` · `RowCanvas.tsx` · `Rail.tsx` | client · server · server | 행 문턱 1회(`data-on`)·GlowGate·캔버스 배치(§S4 4.1 타임라인) — 행 데이터만 받는 엔진 | primitives |
| `components/hero/*` | | 히어로 | hero |
| `components/moments/*` | | 트립틱 | moments |
| `components/features/FeaturesIntro.tsx` · `RowsA.tsx` · `rows-a.data.ts` | | 기능 절 제목 + R1–R3 | rows-a |
| `components/features/RowsB.tsx` · `rows-b.data.ts` | | R4–R5 | rows-b |
| `components/facts/Facts.tsx` · `components/install/Install.tsx` | server | 숫자 격자 · 설치 | facts-install |
| `components/faq/Faq.tsx` · `components/outro/Outro.tsx` | server(+ client 섬) | FAQ · 아웃트로 | faq-outro |
| `lib/moments.ts` | 순수 + 훅 | `nextActive()` · `useActiveCard()` | core |
| `lib/hooks.ts` 추가분 | 훅 | `MQ_STAGE` · `useRevealOnce()` · `useBand()` · `useVisibleRatio()` | core |
| `lib/aing.ts` | 순수 | `idleResumeFrame` · `reactionDurationMs` · `reactionBox`(v1 `CharacterStage.tsx:103–146` 에서 복사) | teardown 이 만들고 primitives 소유 |

### 6.2 재사용 컴포넌트(TD §2 서명 기준 — 바꿀 것)
| 컴포넌트 | 바꿀 것 |
|---|---|
| `DownloadCTA` | **server 컴포넌트로**(`"use client"` 제거). `Placement` = `"nav" \| "hero" \| "install" \| "outro"`. iOS: nav = App Store 알약, hero·outro = **아무것도 그리지 않음**(옆의 배지가 맨 앞으로), install = Mac 과 같은 DMG 링크. `navigator.share`·'Mac 링크 보내기'·`ANNOUNCE.linkCopied`·`demo.installClicked` 삭제 |
| `Headline` | `font-extrabold` 고정 제거(굵기는 `t-*` 가 정함). `HeadlineSize` 에 `caption`·`h4`·`facts-title` 추가. `lines[]` → `<br>` 그대로 |
| `RenderImage` | `fetchPriority?: 'high'`, `fade?: { left?: number; bottom?: number }`(가장자리 마스크 px) 추가 |
| `Bubble` | `onClick`·`ariaLabel`·버튼 분기 삭제. `bubbleText/bubbleSrc/bubbleSize` 유지. 4x 파일로 바뀌어도 `canvasPx` 가 같아 크기 공식 불변 |
| `PhoneShell` · `AppStoreBadge` · `QrCode` · `TextLink` · `VisuallyHidden` · `PlatformScript` · `MacWindowShell` · `Button` | 없음(MacWindowShell 주석의 "조상 transform 금지"만 삭제 — TD §2.2) |
| `CommandBox` · `CopyButton` · `LiveAnnouncer` | TD 필수 수정(`lib/announce`)만 |
| `SpritePlayer` · `AlphaVideo` · `SheetPlayer` | 없음(`AingClip` 이 `SpritePlayer` 를 쓴다) |
| `SiteFooter` · `LicensesNav` · `FaqHash` · `useHeroCtaVisible` | TD §1.2 경로 이동만. `data/site-links.ts` `NAV_LINKS` = `/#features`·`/#install`·`/#faq` |
| `TimerCapsule` | **삭제**(근무 라벨은 렌더 `ui/timer-00-00` 로 — HTML 숫자 합성 금지) |
| `lib/grass/*` | 트립틱이 `GRID`(token: originX 84 · pitch 54 · cols 13) 상수만 쓰면 나머지 삭제(moments 판단) |
| `lib/platform.ts` | `PLATFORM_SCRIPT` 첫머리에 `d.classList.add('js')` 추가(§2.7 'JS 없음') |

### 6.3 `data/fixtures.ts` — 남길 것 / 지울 것 / 더할 것
| 남김 | 지움 | 더함 |
|---|---|---|
| `AssetKey`(기존 전부 — 미사용 키도 남김, DECISIONS D11) · `SequenceName` · `AssetMeta` · `asset()` · `sequences` · `bubbles` | `HOTSPOTS`·`HotspotKey`·`HotspotSpec`·`Rect`·`HotspotShape` | `AssetKey` 에 11개: `ui/header-on-lg` `ui/menubar-0000-lg` `ui/menubar-icon` `ui/poke-slice` `ui/token-slice` `ui/league-slice` `ui/message-unread-panel` `ui/message-read-panel` `ui/character-panel` `ui/timer-00-00` `char/aing-rest-poster` |
| `PEOPLE` · `LINKS` · `APP_STORE_ID` · `BREW`(`upgrade` = `brew update && brew upgrade --cask aing-check`) | `REACTION_SEQ` · `PANELS` · `LABELS` · `PHONE` · v1 `ALT`(키가 v1 상태 이름) | `ALT: Partial<Record<AssetKey, string>>`(§6.5) |
| `BUBBLE_TEXT`(8개 그대로 — `Bubble` 의 Record) · `CORNER`(`heroOut`·`bubbleAtOut`·`capsuleAtOut`·`capsuleSizeOut` — 히어로 배치) | `ANNOUNCE` 의 `copied` 밖 전부(`linkCopied` 포함) · `TIMING` 의 `copyResetMs` 밖 전부 | `HERO`: `{ arrivalDeadlineMs: 2500, idleLoops: 2, cometMs: 1000, bubbleMs: 5000 }` |
| `ReleaseAsset` · `ReleaseInfo` · `RELEASE_FALLBACK` — **0.3.49 로 갱신**: dmg 30,054,068B · "30.1" / zip 28,343,288B · "28.3"(brief §1) | `LabelKey`·`PanelKey` 인라인 타입(쓰는 곳 0) | `MOMENTS_TIMING`: `{ forward: .55, back: .62, exitMs: 267, enterMs: 333, enterDelayMs: 120, lightDelayMs: 450, lightMs: 900, firstLightMs: 1300 }` |
| 인라인 타입 `BubbleId`·`BubbleArtId` | | `ROW_TIMING`: `{ threshold: .68, totalMs: 1300, swapAtMs: 1500, band: [.3, .7] }` |

### 6.4 `data/figures.ts`(core 소유 — 300 숫자 서브셋의 유일한 글자 출처)
```ts
// 트립틱·숫자 격자의 큰 숫자. 이 파일의 문자열 리터럴 + 0–9 : . 만 pretendard-300-num 에 들어간다(scripts/subset-fonts.mjs).
export const FIGURES = {
  start: '00:00', poke: '콕.', records: '12주',                       // 트립틱(렌더 속 글자)
  price: '0', macos: '14', ios: '18', grass: '12', games: '3', duel: '1:1', sdk: '0', // 숫자 격자(제품 사실)
} as const;
export type FigureKey = keyof typeof FIGURES;
/** .t-number·.t-facts 에 넣을 수 있는 값: FIGURES 의 값 또는 릴리스 MB('30.1' 꼴, 숫자와 점뿐). */
export type FigureString = (typeof FIGURES)[FigureKey] | `${number}.${number}`;
```

### 6.5 alt 문구(`ALT` — 렌더를 읽은 서술. HTML 이라 달 이름을 쓰지 않는다)
| 키 | alt |
|---|---|
| `ui/menubar-0000-lg` | 메뉴바 라벨, 근무 중 00:00 |
| `ui/header-on-lg` | 근무 시작 직후 헤더 카드: 근무중 00:00, 이번 주 19시간 38분 / 40시간, 49% |
| `ui/poke-slice` | 콕 찌르기 목록: 구름빵, 달토끼, 민트별, 보리차 모두 근무중, 울트라 3개 |
| `ui/grass-token-final` | 최근 12주 AI 토큰 잔디 |
| `ui/message-unread-panel` / `ui/message-read-panel` | 구름빵과의 1:1 메시지. 보낸 메시지 "좋아요! 배포하고 1층에서요" 옆에 안 읽음 1 / 구름빵이 읽어 1이 사라짐 |
| `ui/character-panel` | 캐릭터 고르기: 아잉 착용 중, 여우, 유령, 해파리, 강아지, 다람쥐 |
| `ui/minigame` | 플래피 아잉 진행 중. 오늘 순위 1위 달토끼 41점, 2위 새벽 23점 |
| `ui/gomoku-board-sm` | 1:1 오목, 새벽(흑) 대 구름빵(백), 내 차례 |
| `ui/token-slice` | 이번 달 AI 토큰 순위: 1위 구름빵, 2위 새벽, 3위 민트별, 4위 달토끼 |
| `ui/league-slice` | 팀별 이번 주: 1위 파도 커피단 평균 36시간 40분, 2위 아잉 데모팀 34시간 20분, 3위 종이 공방 18시간 25분 |
| `ios/now` | 아이폰 지금 탭: 맥에서 근무 중 3:45:00, 이번 주 23시간 23분, 오늘 할 일 남은 4개 |
| `ios/widget-todos-large` · `ios/widget-today-small` | 오늘 할 일 위젯: 남은 4개 · 내 오늘 위젯 |
| `ui/menubar-off` | 메뉴바 라벨, 오프 |
| `brand/appstore-badge-ko-black` | App Store에서 다운로드 하기(배지 글자 그대로 — DECISIONS D26-5) |
| `brand/qr-appstore` | App Store 아잉체크 페이지로 가는 QR 코드(v1 승계 — D26-5) |
| 말풍선 | `bubbleText(id)` 문장 그대로 |
| 장식(`char/*` 포스터·`ui/timer-00-00`·`ui/menubar-icon(-dot)`·타일 속 `brand/icon-256`) | `alt=""` |

---

## 7. 리스크 · 축소판 · 자기 비평

### 7.1 식상한 기본값 점검(0 안전 ~ 2 위험, J2 의 다섯 tell)
| tell | 이 안에서 | 점수 |
|---|---|---|
| 검정 + 형광 1색 | 보라가 아이콘 링 표본 한 가족이고, 돔 림이 레퍼런스 단면을 그대로 옮긴 '물체'라 안개가 아니다. 다만 다크 + 보라 글로우 계열인 것은 사실 | 1 |
| 브로드시트 | 격자 10/50/90 + 헤어라인 칸 + 카운터가 있으나 FAQ 를 한 열로 바꿔 '왼쪽 제목 + 오른쪽 목록' 반복을 끊었다 | 0.5 |
| SaaS 카드 키트 | 카드 그리드 0, 타일 안은 진짜 메뉴바 아이콘·앱 아이콘 | 0.5 |
| 템플릿 크롬 | 칩 1개, 버튼 화살표 없음, 카운터는 tabular 산세리프 | 0.5 |
| 흩어진 마이크로 인터랙션 | 움직임 여섯 가지가 전부 한 문법(선 → 렌더, 빛 → 켜짐) | 0.5 |
| 합계 | | **3.0 / 10** |

### 7.2 사용자가 싫어할 위험 톱3와 바로 갈아 끼울 대안
| 위험 | 왜 | 대안 |
|---|---|---|
| R1 **히어로 도착이 "체험 같다·과하다"** | 첫 2초에 빛·폴짝·말풍선이 한꺼번에 | (a) 빛 한 줄을 빼고 폴짝만(desk 도 phone 과 같게) — `HERO.cometMs = 0` 하나로 (b) 감속 판(정지 한 장)을 기본으로 |
| R2 **"그래도 Sellix 같다"** | 돔·트립틱·스파인·격자를 다 갖췄다 | 이미 아이콘 링 색·아잉·한글 이름표로 갈랐다. 더 필요하면 돔 지름을 140% 로 키워 꼭대기만 보이는 지평선으로(돔 위 = 26svh) — CSS 변수 두 개 |
| R3 **트립틱이 스크롤을 붙잡는 느낌** | 144svh 동안 오브젝트가 멈춰 있다 | 카드 피치 72 → 60svh(고정 구간 120svh, −216px) 또는 무대 모드를 끄고 목록 모드를 desk 기본으로(미디어쿼리 한 줄) |

### 7.3 구현 난이도 상위 3과 축소판
| 순위 | 무엇 | 어려운 점 | 축소판 |
|---|---|---|---|
| 1 | 히어로 도착(빛 경로 계산 + 영상 이음 + 2.5s 마감 + 2회 상한) | 돔·말풍선 상자에서 경로를 매번 계산, 웹킷 HEVC 알파 시크 | 빛 한 줄 없이 폴짝만 · 이음은 `idleResumeFrame` 대신 포스터 → idle 0번(한 프레임 튐 허용) |
| 2 | 트립틱 무대(sticky + IO 두 줄 히스테리시스 + 지연 마운트 + 교체·점등) | 조상 규칙, svh 변화(주소창), 되감기 | 목록 모드를 desk 기본으로 — 같은 DOM, CSS 한 줄 |
| 3 | 행 5개 좌표·타임라인 | 상수가 많고 1024·tab 배율 | 선을 트렁크 하나로, 타임라인 `--at` 을 3단(0/440/700)으로 |

### 7.4 열어 둔 것(리드·사용자 결정 — 기본값으로 진행)
1. 트립틱 방향: 세로(DECISIONS D1). brief 의 가로를 원하면 A §S2 가로판을 부록으로 되살린다(무대 DOM 그대로, 카드만 가로 트랙).
2. 위젯 수(2 ↔ 4) — 숫자 격자에서 뺐다.
3. 신규 문구 §1.4.3(격자 라벨 8·단위·열 라벨). 업데이트 한 줄은 brief §1 리드 확정 문장.
4. WCAG 2.2.2: 루프 상한으로 갈음(멈춤 버튼은 허용 목록 밖, J3 판정).
5. 센터 FAQ 미게재 · 저작권 표기 "© 2026 아잉체크"(v1 그대로).

---

## 8. 메타 · OG

- `<title>` "아잉체크: 작은 Mac 팀을 위한 메뉴바 근무 타이머"(v1 그대로, CB:29) · description "근무 시작을 누르면 팀 전체에 바로 보여요. 맥 메뉴바에서 근무 시간을 재고, 아이폰에서도 팀 현황을 봐요."(v1 그대로) · `themeColor '#0C0A14'` · `itunes.appId` 유지.
- **OG 재촬영(통합 단계)**: 1440×900, **감속 모션 컨텍스트**(도착 뒤 상태가 결정적으로 정지 — 포스터 + 말풍선 + 근무 라벨), 내비 제외. 자르기 상자 = (0, 라벨 위 − 40, 1440, 756) → 1200×630 으로 축소. 들어가는 것: 돔 꼭대기·라벨·H1·리드·CTA·아잉. `app/opengraph-image.png` 덮어쓰기 + `app/opengraph-image.alt.txt` + `lib/site.ts` `OG_IMAGE.alt` = "보라 돔 아래 아잉이 '오늘도 화이팅!' 하고, 돔 꼭대기에 메뉴바 라벨 00:00. 출퇴근 기록을, 메뉴바 하나로."(§1.4.3 alt 범주).
- JSON-LD: `FAQPage`(10문항) 하나. `SoftwareApplication` 은 넣지 않는다(별점·가격 필드 유혹 — §1.4).

---

## 9. 에셋 — 현 파일 → 섹션 → 표시 크기 → 바이트, 그리고 새 레시피

### 9.1 쓰는 기존 파일(`P/assets/…`, 바이트는 디스크 실측)
| 파일 | 섹션 | 표시(1440) | 바이트 |
|---|---|---|---|
| `brand/icon-64.webp` | 내비 · 푸터 | 24 | 1,434 |
| `brand/icon-256.webp` | R5 타일 | 48 | 6,538 |
| `brand/appstore-badge-ko-black.svg` | 히어로 · 설치 · 아웃트로 | 높이 48(모든 뷰포트 — D22-3) | 9,260 |
| `brand/qr-appstore.svg` | 설치(desk) | 112 | 3,257 |
| `ui/bubble-commute-start.webp`(4x 로 다시 굽기) | 히어로 | 148×54 | ≈7,938 |
| `ui/bubble-poked-mint.webp`(4x) | 트립틱 02 | 153×80 | ≈10,546 |
| `ui/bubble-message-gureum.webp`(4x) | R1 | 183×74 | ≈11,898 |
| `ui/bubble-ruby.webp`(4x) | R2 | 119×59 | ≈6,090 |
| `ui/grass-token-empty.webp` · `-final.webp` | 트립틱 03 | 456×259.5 | 9,332 · 18,580 |
| `ui/menubar-icon-dot.webp` | R1 · R3 타일 · 설치 업데이트 줄 | 32 / 16 | 1,832 |
| `ui/menubar-off.webp` | 설치 3단계 | 92.5×33 | 2,886 |
| `ui/minigame.webp` | R3 | 546×304 | 35,538 |
| `ui/gomoku-board-sm.webp` | R3 | 144×160 | 15,578 |
| `ios/now.webp` | R5 | 208 폭 화면 | 30,102 |
| `ios/widget-todos-large.webp` | R2 | 200×210 | 19,920 |
| `ios/widget-today-small.webp` | R5 | 160×160 | 9,222 |
| `char/aing-commute-start.{webm,mov}` | 히어로 | 228×275 | 151,047 / 125,839 |
| `char/aing-idle.{webm,mov}` · `-15` | 히어로 · 아웃트로 | 228 / 200 | 808,263 / 817,960 · 536,078 / 523,861 |
| `char/aing-idle-poster.webp` | 아웃트로 | 200×242 | 17,748 |

### 9.2 새 크롭(`scripts/build-assets.mjs` 에 표 `V2_CROPS` 추가 — 전부 크롭·리사이즈·품질만, 덧그리기 0)
| 출력 `P/assets/…` | 원본(`A/…`) | 크롭 (x, y, w, h) @원본 px | 크기 · 품질 | 바이트(실측) | 근거 |
|---|---|---|---|---|---|
| `ui/header-on-lg.webp` | `v4/mac/ui/header/header_on_1020@4x.png` | 없음 | 1264×428 그대로 · q85 | 18,626 | A probe · 1.5pt 표시를 레티나로 |
| `ui/menubar-0000-lg.webp` | `v4/mac/ui/menubar/menubar_aing_working_0000_dark_alpha@10x.png` | 없음 | 높이 132(463×132) · q90 a100 | 7,138 | 기존 `-lg` 규칙(`LABELS` 표에 한 줄 추가로 충분) |
| `ui/menubar-icon.webp` | `v4/mac/ui/menubar/menubar_aing_icon_working@10x.png` | 없음 | 66×66 · q90 a100 | 1,612 | 칩 16px |
| `ui/poke-slice.webp` | `v4/mac/ui/poke_list@3x.png` | (228, 390, 762, 852) | 그대로 · q80 | 18,438 | **아바타 열(배지) 제외**, 머리 '…찌르기 (집중) ⚡3 3초 꾹 = 울트라' + 4행(구름빵·달토끼·민트별·보리차). 왼쪽 경계가 행 카드를 자르므로 표시 때 28px 페이드 |
| `ui/token-slice.webp` | `v4/mac/ui/token_board_month@3x.png` | (246, 390, 708, 1005) | ×2/3 → 472×670 · q80 | 18,158 | 아바타 열 제외, 머리 + 4행. '◀' 단추 조각은 왼쪽 페이드가 가린다 |
| `ui/league-slice.webp` | `v4/mac/ui/league_week@3x.png` | (216, 540, 744, 640) | ×2/3 → 496×427 · q80 | 17,638 | 아바타 열 제외, 3팀(파도 커피단·아잉 데모팀 '우리 팀'·종이 공방) |
| `ui/message-unread-panel.webp` · `-read-panel` | `v4/mac/ui/message_thread_gureum_{unread,read}@3x.png` | (36, 390, 954, 900) | 그대로 · q80 | 28,576 · 28,486 | A probe. 머리 '구름빵' ~ 14:04 "1 좋아요! …"(대화 머리 아바타에 배지 없음 확인) |
| `ui/character-panel.webp` | `v4/mac/ui/character_pick_aing@3x.png` | (36, 390, 954, 900) | 그대로 · q80 | 30,666 | A probe. '캐릭터' 머리 + 6종 격자 |
| `ui/timer-00-00.webp` | `v3/mac/char/_ui/timer_00-00.png`(캔버스 2100×2625) | (787, 1686, 527, 239) = 알파 bbox 실측 | ×.5 → 264×120 · q90 a100 | 11,982 | 앱 근무 라벨 층(asset-manifest §1 '앱 UI 층'). 상자 좌표 = `CORNER.capsuleAtOut` |
| `char/aing-rest-poster.webp` | `v3/mac/char/aing/commute_start/0000.png` | HERO 박스 (424, 544, 1308, 1580) | ×.5 → 654×790 · q80 a90 | 17,702 | B §6.3 — 모든 반응 시퀀스 0번 프레임과 바이트 동일(J2 표본 10) |

- 표마다 **레시피 + 검증 목록(`expectedOutputs`) + `AssetKey`** 를 함께 고친다(TD §6). 합계 +200,000B.
- 크롭 좌표는 `synth/`·`designer-A/probe/` 에서 실제로 구워 확인했다. assets 에이전트는 굽고 나서 §9.6 배지 감사를 다시 한다.

### 9.3 말풍선 4x 로 다시 굽기(새 키 없음)
- `BUBBLES` 레시피의 배율을 `× 3/8`(@3x) → **`× 1/2`(@4x)** 로, `RUBY` 를 `÷ 3.5` → **`÷ 2.625`** 로. 출력 이름 그대로(`ui/bubble-*.webp`).
- `bubbles.json` 의 **`canvasPx` 는 바뀌지 않아야 한다**(= 알파 bbox × 3/8 × 3.5 — 파일 픽셀이 아니라 bbox 에서 계산). 수용: 다시 굽기 전후 `canvasPx` diff 0 → `Bubble` 표시 크기 불변.
- 바이트: 쓰는 넷 기준 +약 12,000B(A probe 의 `-4x` 실측 7,938·10,546·11,898·6,090).

### 9.4 영상 · 데이터 묶음
- 영상(`SEQS`)은 그대로 — 새로 인코딩하지 않는다. `char/aing-rest-poster` 는 char 묶음에 포스터 레시피로 추가.
- `data/generated/{assets,sequences,bubbles}.json` 은 `npm run assets -- --only=ui,char,data` 로 다시 쓴다(손으로 고치지 않음). `grass.json` 은 그대로.

### 9.5 글꼴 서브셋 레시피(`scripts/subset-fonts.mjs` · `check-glyphs.mjs`)
| 출력 | 원본 | 글자 | 방법 |
|---|---|---|---|
| `pretendard-500-sub.{woff2,txt}` | `Pretendard-Medium.woff2` | **소스 스캔**(`check-glyphs.mjs` 의 `collectSourceGlyphs` — `app·components·data`, `data/generated` 제외, 주석·개발 문구 제외) + ASCII + 문장부호 | `pyftsubset --flavor=woff2 --layout-features=kern,liga --no-hinting`(지금과 같음) |
| `pretendard-600-sub.{woff2,txt}` | `Pretendard-SemiBold.woff2` | 500 과 같은 집합 | 같음 |
| `pretendard-300-num.{woff2,txt}` | `PretendardVariable.woff2` → `fonttools varLib.instancer … wght=300`(임시 폴더) | **같은 수집기를 `data/figures.ts` 하나에만** + `0123456789:.` | `pyftsubset --layout-features=kern,tnum --no-hinting` |
| `jbm-400-ascii.woff2` | 그대로 | U+0020–007E | 그대로 |
- `fonttools` 실행 파일은 `pyftsubset` 와 같은 폴더(`/opt/anaconda3/bin/fonttools`, C 실측). `--from-spec` 모드는 **`docs/v2/SPEC.md` §3 본문 글자 ∪ 소스 스캔**으로(스캐폴드 때 섹션 카피가 아직 없으므로). 통합 단계에서 기본 모드(소스 스캔)로 다시 만든다.
- `check-glyphs.mjs`(`prebuild`): (a) 소스 한글 ⊂ `pretendard-500-sub.txt` **그리고** ⊂ `pretendard-600-sub.txt` (b) `data/figures.ts` 글자 ⊂ `pretendard-300-num.txt`. 하나라도 어긋나면 exit 1. `.txt` 가 없으면 경고 후 exit 0(스캐폴드 전).
- `pretendard-800-sub.{woff2,txt}` 삭제, `FONT_OUTPUTS`(build-assets 검증 목록)·`app/layout.tsx` 에서도 뺀다.

### 9.6 배지 감사(센터 배지 '서울/부산' — CB:293, J3-A1)
| 렌더 | 배지 | 판정 |
|---|---|---|
| `ui/poke-slice` · `ui/token-slice` · `ui/league-slice` | 아바타 열을 잘라 **0개** | 통과(`synth/*.png` 육안) |
| `ui/message-*-panel` | 대화 머리 아바타에 배지 없음 | 통과 |
| `ui/minigame`(.78pt) | 오늘 순위 아바타 7개에 작게(≈8px) | 허용 — 확대가 아니라 축소 표시(CB:293 "크게 보이지 않는 크롭") |
| `ui/character-panel` · `ui/header-on-lg` · `ios/now` · 위젯 · 잔디 | 없음 | 통과 |
assets 에이전트는 새 크롭을 굽고 2× 확대 접촉 시트로 다시 보고, 통합 에이전트는 1440 캡처에서 한 번 더 본다.

### 9.7 v2 에서 안 쓰는 기존 출력(지우지 않음 — DECISIONS D11)
`ui/popover-{off,on,working,newmsg,off-1702,tick-strip}` · `ui/poke-{list,cooldown,focus-1,focus-2}` · `ui/message-{composing,unread,read}` · `ui/league` · `ui/token-{month,last}` · `ui/insights-popover` · `ui/grass-work-*` · `ui/gomoku-board` · `ui/todo-board` · `ui/character-pick` · `ui/header-off-1702` · `ui/menubar-{0000,0100,0345,0345-newmsg,0642,0642-lg,off-lg}` · `ui/bubble-{autostart,commute-end,ultra-mint,update}` · `char/aing-{commute-end,poked,milestone,ultra,ultra-charged}` · `char/aing-ultra-poster` · `ios/{messages,games,rankings-league,me-records,widget-todos-large-checked}`. 페이지가 요청하지 않으므로 무게에 들어가지 않는다. 정리는 후속 작업.
