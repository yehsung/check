# 아잉체크 랜딩 v2 — SPEC 후보 B 「아잉이 주인공」

작성 2026-10-12 · 디자이너 B(디자인 디렉터 겸 테크 리드) · 상태: 후보(심사 전). 정본이 되면 `docs/v2/SPEC.md` 로 옮긴다.
읽은 것: `docs/v2/brief.md` 전부 · `docs/content-brief.md` 전부(카피 정본, 줄 번호 = `CB:<줄>`) · `docs/asset-manifest.md` · v1 `docs/SPEC.md` §1.3–1.4·§2·§8·§9 · `docs/PLAN.md`·`DECISIONS.md` · `docs/v2/reference-analysis.md`(= `RA §`) · `docs/v2/teardown.md`(= `TD §`) · 레퍼런스 접촉 시트 0–5 · v1 캡처 `strip1440-0`.
실측(전부 내 전용 폴더 `scratchpad/v2design/designer-B/`): WCAG 대비 `contrast.mjs` → `contrast-final.txt` · 돔·트립틱 목업 `mock/{hero,trip}.html` 을 Playwright 1.60 크로미움으로 촬영(`mock/hero-1440.png`·`hero-1440x789.png`·`trip-1440.png`) · 신규 포스터 6장 인코딩 `posters/make.mjs` · idle 영상 재인코딩 4벌 `enc/*.webm` · Pretendard 가중치별 서브셋 `fonts/ptd-*.woff2` · 앱 아이콘 링 색 표본.
저장소 안에서 고친 파일: 이 문서 하나.

---

## 0. 한눈에

### 0.1 결정 요약

| 항목 | 결정 |
|---|---|
| 컨셉 한 문장 | **앱 아이콘의 보라 링이 지평선만 한 돔이 되고, 그 아래 아잉이 산다.** 페이지는 아잉의 하루다 — 돔 아래 폴짝 도착(히어로) → 일하는 동안의 반응 셋(트립틱) → 앱이 하는 일(기능 행, 렌더 그대로) → 같은 돔 아래 꾸벅 퇴근(아웃트로). |
| 기억에 남을 하나 | 레퍼런스의 "점으로 찍은 지구" 자리에 **진짜 3D 아잉(알파 영상)** 이 서 있는 보라 돔. 처음과 끝 두 번, 같은 자리에서. |
| 색 규칙 | 바탕은 보라 기운 밤 `--bg-0 #0C0A14`, 돔 안은 더 어두운 `#06040C`. 빛은 앱 아이콘 링에서 표본한 `--violet #7E5EFA` 한 가족(깊은 끝 `#3B1E8F` · 밝은 띠 `#DA84FF` · 핵 `#FFC8FF`). 손(버튼·링크·포커스)은 아잉 몸색 `--aing #C9B8FF`. 평평한 보라 면 0, 글로우는 한 화면에 하나. |
| 글꼴 | Pretendard **500**(H1·트립틱 큰 글자·H2·숫자) + **600**(H3·FAQ 질문) 서브셋 두 벌(실측 각 ≈34.5KB). 본문 시스템 SF(0B). brew 명령만 JetBrains Mono ASCII(4,440B). |
| 움직임 | 스크럽 1곳(히어로 돔이 지는 패럴랙스, CSS scroll-driven) · 스티키 1곳(트립틱 — 레퍼런스처럼 세로 스크롤 + 가운데 오브젝트 고정 교체) · 문턱 리빌(기능 행마다 1회, 1.6초) · 자동 루프 2곳(히어로·아웃트로의 아잉 idle 14.4초 진짜 루프). 아잉에 CSS 변형 0. |
| 길이 | 1440×900 에서 **9,660px = 10.7 뷰포트**(§3.0 표). 390×844 에서 ≈ 12,900px. |
| 무게(크롬, 실측 바이트 합산) | 첫 화면 **≈ 299KB**(예산 400) · load 뒤 히어로 아잉 965,268B · 페이지 전체 **≈ 3.13MB**(예산 4.5MB, 여유 1.37MB) · 사파리 ≈ 3.04MB · 폰 크롬 ≈ 2.85MB. 근거 §5. |

### 0.2 사용자 요구 셋을 어디서 어떻게

1. **체험 제거** — 클릭으로 바뀌는 것이 하나도 없다. 아잉의 모든 움직임은 시간(로드 뒤 1회 도착·idle 루프)과 스크롤 위치(트립틱 장 교체·행 리빌·아웃트로 1회)로만 일어나고, 누를 수 있는 것은 brief §5.1 허용 목록(내비·다운로드·App Store·brew 복사·FAQ `<details>`·푸터)뿐이다. §1.3-1·§3 각 절 "금지" 줄.
2. **다크 + 보라 조화** — 보라는 면이 아니라 빛이다: 히어로·아웃트로의 돔 림(앱 아이콘 링 색), 트립틱의 오브젝트 뒤 라디얼, 기능 행의 레일 노드·연결선·타일·점 격자, 설치 띠 윗변의 수평선. 화면마다 보라 빛이 정확히 하나 있다(§3.0 "보라" 열).
3. **레퍼런스 안무** — 돔 히어로(꼭대기 18svh·안쪽으로만 감쇠하는 림 = RA §3.1 단면) → 세로 스크롤 + 고정 오브젝트 교체 트립틱(장 피치 72svh·교체 200+240ms·"꺼진 채 들어와 켜짐" 800ms = RA §4.3) → 가운데 정렬 절 제목 + 눈썹 1개 → 왼쪽 레일 + 노드 기능 행(선 → 타일 팝 → 렌더 → 보조 → 점 격자 → 선 탁해짐, 1.6초 = RA §4.4) → 헤어라인 칸 숫자 격자 → 엔드카드처럼 어두운 아웃트로(RA §4.5).

---

## 1. 컨셉과 원칙

### 1.1 한 문단
아잉체크의 앱 아이콘은 어두운 밤색 사각 안에서 보라 진행 링이 아잉을 감싼 그림이다(아이콘 링 꼭대기 표본 `#7E5EFA`, 바탕 `#121328`). 이 페이지는 그 아이콘을 지평선 크기로 키운 장면에서 시작한다. 레퍼런스의 거대한 돔은 그대로 가져오되, 돔 안의 세계 지도 대신 **앱이 실제로 렌더한 아잉**이 바닥 한가운데 선다. 로드가 끝나면 아잉이 앱에서처럼 폴짝 들어오며 "오늘도 화이팅!" 하고, 그다음부터는 14.4초 진짜 루프로 숨 쉰다. 스크롤을 내리면 돔이 지고, 화면 가운데 고정된 자리에서 아잉이 하루 동안 앱에서 하는 반응 셋 — 1시간 색종이, 콕 찔려 화들짝, 울트라로 화면을 덮기 — 을 큰 글자 「01:00」「콕.」「울트라.」 옆에서 한 번씩 보여 준다. 그 아래 기능 행은 아잉이 물러나고 **앱 렌더가 정확한 크기로** 주인공이 되며, 아잉은 말풍선과 작은 스틸로만 곁에 있다. 마지막에 같은 돔이 작게 다시 떠오르고 아잉이 꾸벅 "수고했어!" 한 뒤 다시 숨 쉰다. 방문자가 하는 일은 읽기·스크롤·다운로드뿐이다.

### 1.2 레퍼런스에서 가져온 것 / 갈라진 것

| 레퍼런스(RA) | B 에서 | 왜 |
|---|---|---|
| 돔: 지름 94% vw, 꼭대기 18% vh, 안쪽 45px 감쇠, 바깥 헤일로 +3 레벨(RA §3.1) | **가져옴**. `--dome-r: min(44vw,70svh)`, 꼭대기 18svh, 안쪽 감쇠 48px, 바깥 그림자 α.16. 1440×900 에서 반지름 630·중심 88svh(= RA 값) | 목업 촬영으로 확인(`mock/hero-1440.png`) |
| 돔 안 점 세계 지도 + 자전 | **갈라짐**: 아잉 알파 영상(idle 14.4초 루프) | 지구본 금지(brief §3). 우리 오브젝트는 아잉 |
| 펄스 → 호 → 알림 카드 4.2초 루프(RA §4.1) | **갈라짐**: 로드 뒤 1회 "폴짝 + 오늘도 화이팅!"(앱 commuteStart 그대로) → idle 루프 | 말풍선마다 앱은 짝 반응을 함께 튼다(`CheckOverlayReactions.swift:941–987`). idle 위에 콕·메시지 말풍선을 돌리면 앱에 없는 상태가 된다 |
| 흰 알약 2개 | 라벨더 채움 「Mac용 다운로드」 + App Store 공식 배지 | brief §3 허용, 배지 수정 금지 |
| 트립틱: 세로 스크롤 + 가운데 오브젝트 고정·교체, 피치 77.5% vh, 다음 장 아래에서 미리보기(RA §5) | **가져옴**(가로 스크럽 대신). 피치 72svh, 다음 큰 글자가 86svh 에서 보임 | 영상이 실제로 그렇게 움직인다. 감속 모션 폴백이 "고정만 풀기"로 끝나고 스크롤 하이재킹이 없다. 가로안은 §3.4.8 부록 |
| 오브젝트 퇴장 8f·등장 10f, 회색 → 보라 점등 | 퇴장 200ms·등장 240ms **불투명도만**, 점등은 오브젝트 뒤 라디얼이 800ms 에 켜짐 | 캐릭터에 축소·회전·필터 금지(v1 §1.3-3) |
| `[ 01 / 03 ]` 고정폭 카운터 | 가져옴, 단 **고정폭 대신 tabular 숫자** | 진짜 순서라 번호 허용. 작은 모노 라벨은 템플릿 신호(§7.1) |
| 눈썹 칩 1개(기능 절 위) | 가져옴: 「Mac 메뉴바 앱 · iPhone 앱」(CB:62) — 페이지 유일 | — |
| 세로 헤어라인 10/50/90% vw, 왼쪽 선 = 스파인 | 가져옴. 왼쪽 선 = **레일**(이름은 `Rail` — `Spine` 금지, TD §0.1-7) | 트립틱부터 숫자 격자까지 한 줄로 이어진다 |
| 행 조립 36–39f(1.2–1.3s), 지갑 행 카운트업 58f | 행마다 1.6s, 메시지 행 "1 사라짐"·AI 행 잔디 12칸 점등이 카운트업 자리(1.9s) | 숫자를 HTML 로 지어내지 않고 렌더 교체·클립만 |
| 목업 안 커서 데모 | 없음 | 커서 합성 금지(brief §3) |
| 로고 띠·"Learn more ›" | 없음 | 파트너 없음, 목적지 없음 |
| 숫자 격자 4×2, 정적 | 가져옴, 제품 사실 8칸(§3.7) | 사용자 수·별점 금지 |
| 엔드카드: 0.6초 페이드, 마크 1.9초 루프 ×2, `#0E0E0E` | 아웃트로: 바탕 `#08060F`, 작은 돔 + 아잉 commute-end 1회 → idle 루프 | 처음과 끝을 맞춘다(CB:280 문법) |

### 1.3 절제 원칙(구현자가 매번 확인)
1. 누르면 바뀌는 렌더·캐릭터는 없다. 아잉은 시간과 스크롤로만 움직이고, 클릭을 받지 않는다(`pointer-events: none`).
2. 아잉 영상·포스터에 `transform`·`filter`·`scale`·`rotate`·튀기기 금지. 바뀌는 것은 불투명도(선형)와 레이아웃 위치뿐이고, 크기는 중단점마다 고정이다.
3. 한 화면에 움직이는 큰 것 하나, 보라 빛 하나. 아잉이 재생 중인 무대는 페이지 전체에서 언제나 하나(`stage-bus`, §3.1).
4. 렌더는 크롭·리사이즈만. 숫자·말을 덧그리지 않는다. HTML 숫자는 렌더에 보이는 사실(「01:00」)이거나 §3.7 출처표의 제품 사실뿐이다.
5. 불투명도는 언제나 선형, 이동은 들어올 때 ease-out·나갈 때 ease-in. 같은 커브로 둘을 깎지 않는다.
6. 기능 본문에 규칙·수치 캡션 금지(CB:55). 카피는 content-brief 문장 그대로, 출처 줄을 이 문서에 적는다.
7. 카드·유리 상자·그라디언트 워시·별밭·노이즈 없음. 그림자는 렌더 창에만, 빛은 §2.2 레시피에만.
8. 감속 모션·Save-Data 면 캐릭터 영상 요청 0건, 정지 한 장 + 말풍선 정지.

---

## 2. 디자인 토큰

### 2.1 색 (변수 이름 확정 · 대비는 `contrast.mjs` WCAG 2.x 실측)

| 변수 | 값 | 용도 |
|---|---|---|
| `--bg-0` | **#0C0A14** | 페이지 바탕, `theme-color`, 내비(스크롤 뒤 α.88) |
| `--bg-dome` | #06040C | 돔 안(레퍼런스처럼 바탕보다 어둡다, RA §6 #5) |
| `--bg-1` | #16132B | 설치 띠 하나. bg-0 대비 **1.09**(v1 교훈: 1.06 이하는 사라진다) |
| `--bg-end` | #08060F | 아웃트로(레퍼런스 엔드카드가 페이지보다 어둡다, RA §0.2-4) |
| `--surface` | #181428 | brew 명령 상자, FAQ 열린 행, 레일 노드(꺼짐) |
| `--surface-2` | #221C38 | 눌림, 코드 복사 버튼 바탕 |
| `--line` | rgba(255,255,255,.07) → bg-0 위 #1D1B24(대비 1.155) | 헤어라인: 격자 10/50/90, 레일, 카드 경계, FAQ 행 |
| `--line-strong` | rgba(255,255,255,.14) → #2E2C35(1.429) | 보조 버튼·칩 테두리 |
| `--ink-1` | **#F4F1FF** | 헤드라인·큰 글자 |
| `--ink-2` | #B8B1D4 | 리드·본문·라벨 |
| `--ink-3` | **#958DB4** | 메타·카운터·법적(brief 출발값 #8A82A8 은 surface-2 위 4.52 로 아슬해 올렸다) |
| `--aing` | **#C9B8FF** | 주 버튼 채움, 링크, 포커스 링, `::selection`(α.30) |
| `--aing-hover` | #D8CCFF | 주 버튼 호버 |
| `--on-aing` | #14102A | 라벤더 위 글자 |
| `--violet` | **#7E5EFA** | 빛의 본색 = 앱 아이콘 링 꼭대기 표본(`icon-1024.png` r272 θ−90°). 레퍼런스 중앙값 #7E33E6·brief #7C4DFF 와 같은 가족 |
| `--violet-deep` | #3B1E8F | 감쇠 끝, 라디얼 바깥 |
| `--violet-bright` | #DA84FF | 림 밝은 띠, 그리는 중인 연결선 |
| `--violet-core` | #FFC8FF | 림 핵(레퍼런스 p99 #FABEFF) |
| `--lilac` | #C584F9 | 타일 그라디언트 윗색(레퍼런스 타일 면 RA §6 #12) |
| `--wire-dim` | rgba(151,133,193,.55) | 정착한 연결선(RA §0.2-9c #9785C1 → #705E92) |

대비 실측(전경 \ 배경):

| | bg-0 #0C0A14 | bg-1 #16132B | surface #181428 | surface-2 #221C38 | bg-dome #06040C | bg-end #08060F |
|---|---|---|---|---|---|---|
| ink-1 #F4F1FF | **17.65** | 16.24 | 16.14 | 14.62 | 18.32 | 18.09 |
| ink-2 #B8B1D4 | **9.61** | 8.84 | 8.79 | 7.96 | 9.97 | 9.85 |
| ink-3 #958DB4 | **6.31** | 5.81 | 5.77 | 5.23 | 6.55 | 6.47 |
| aing #C9B8FF | **11.02** | 10.14 | 10.08 | 9.13 | 11.44 | 11.29 |
| violet-bright #DA84FF(글자로 안 씀) | 8.16 | 7.51 | 7.46 | 6.76 | 8.47 | 8.36 |
| violet #7E5EFA(글자 금지) | 4.08 | 3.75 | 3.73 | 3.38 | 4.23 | 4.18 |

- on-aing #14102A: aing 위 **10.36**, aing-hover 위 12.31. 포커스 링 aing: bg-0 11.02 · surface 10.08.
- 렌더 창 바탕(#1D202B) vs bg-0 = 1.21 → 창 가장자리는 `--shadow-window` 첫 겹 헤어라인이 가른다. App Store 배지(검정) vs bg-0 = 1.07 → 배지 자체의 흰 테두리가 경계(수정 금지라 손대지 않음).
- 앱 색(민트·코랄·앱 파랑)은 렌더 안에서만. 앱 아이콘 링의 파랑 꼬리(#3DA0FF)는 가져오지 않는다 — 페이지 빛은 보라 한 가족.

### 2.2 글로우 레시피(CSS 그대로)

```css
/* ① 돔 — 한 겹 라디얼로 안쪽 감쇠 림을 만든다(목업 촬영 검증). 히어로·아웃트로 공용 */
.dome {
  position: absolute; left: 50%; top: var(--dome-top);
  width: calc(var(--dome-r) * 2); height: calc(var(--dome-r) * 2);
  margin-left: calc(var(--dome-r) * -1);             /* transform 은 스크럽 애니메이션에 남겨 둔다 */
  border-radius: 50%; pointer-events: none;
  background: radial-gradient(circle closest-side,
    var(--bg-dome)        calc(var(--dome-r) - 48px), /* 돔 안 */
    #140C30               calc(var(--dome-r) - 30px), /* 감쇠 시작 */
    #2A1670               calc(var(--dome-r) - 16px),
    #5530C8               calc(var(--dome-r) - 8px),
    var(--violet)         calc(var(--dome-r) - 4px),  /* 밝은 띠 9px 구간 */
    var(--violet-bright)  calc(var(--dome-r) - 1.6px),
    var(--violet-core)    calc(var(--dome-r) - .6px), /* 핵 */
    rgb(255 200 255 / 0)  var(--dome-r));
  box-shadow: 0 0 28px 2px rgb(126 94 250 / .16);     /* 바깥 헤일로는 거의 없다(RA §3.1) */
}
/* ② 돔 바닥 웅덩이 — 아잉 발밑, 돔과 한 빛(따로 세지 않는다) */
.dome-pool { width: calc(var(--aing-w) * 1.6); height: calc(var(--aing-w) * .24);
  background: radial-gradient(closest-side, rgb(126 94 250 / .20), rgb(126 94 250 / 0)); }

/* ③ 트립틱 오브젝트 뒤 라디얼 — "꺼진 채 들어와 켜진다"(opacity 0→1, 800ms linear) */
.stage-glow { width: min(620px, 64svh); aspect-ratio: 1; border-radius: 50%;
  background: radial-gradient(closest-side, rgb(126 94 250 / .34), rgb(59 30 143 / .20) 46%, rgb(12 10 20 / 0) 100%);
  opacity: 0; transition: opacity var(--t-ignite) linear; }
.stage-glow[data-on="true"] { opacity: 1; }

/* ④ 연결선(SVG path, pathLength="1") — 밝게 그리고 탁해진다 */
.wire { fill: none; stroke: var(--violet-bright); stroke-width: 1.5; stroke-linecap: round;
  stroke-dasharray: 1; stroke-dashoffset: 1;
  transition: stroke-dashoffset var(--t-draw) var(--ease-out), stroke var(--t-dim) linear; }
[data-revealed="true"] .wire { stroke-dashoffset: 0; }
[data-settled="true"] .wire { stroke: var(--wire-dim); }

/* ⑤ 아이콘 타일(연결선의 출발점, 앱 아이콘 24px 를 품는다) */
.tile { width: 36px; height: 36px; border-radius: 10px; display: grid; place-items: center;
  background: linear-gradient(145deg, var(--lilac) 0%, var(--violet) 55%, var(--violet-deep) 100%);
  box-shadow: inset 0 0 0 1px rgb(255 255 255 / .22), 0 0 0 1px rgb(126 94 250 / .35), 0 6px 18px -6px rgb(126 94 250 / .55); }

/* ⑥ 레일 노드 — 꺼짐 / 켜짐 */
.node { width: 14px; height: 14px; border-radius: 4px; background: var(--surface-2); box-shadow: inset 0 0 0 1px var(--line-strong);
  transition: background-color var(--t-quick) linear, box-shadow var(--t-quick) linear; }
.node[data-lit="true"] { background: linear-gradient(145deg, var(--violet-bright), var(--violet));
  box-shadow: 0 0 0 3px rgb(126 94 250 / .18), 0 0 14px rgb(126 94 250 / .6); }

/* ⑦ 점 격자(렌더 뒤 작업대) — 64px SVG 타일: 16칸 중 9점, 그중 2점 보라 */
.dotgrid { background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='64' height='64'%3E%3Cg fill='%23fff' fill-opacity='.10'%3E%3Ccircle cx='8' cy='8' r='.9'/%3E%3Ccircle cx='40' cy='8' r='.9'/%3E%3Ccircle cx='24' cy='24' r='.9'/%3E%3Ccircle cx='56' cy='24' r='.9'/%3E%3Ccircle cx='8' cy='40' r='.9'/%3E%3Ccircle cx='40' cy='40' r='.9'/%3E%3Ccircle cx='56' cy='56' r='.9'/%3E%3C/g%3E%3Cg fill='%237E5EFA' fill-opacity='.5'%3E%3Ccircle cx='24' cy='56' r='.9'/%3E%3Ccircle cx='56' cy='8' r='.9'/%3E%3C/g%3E%3C/svg%3E");
  -webkit-mask-image: radial-gradient(ellipse 58% 52% at 55% 50%, #000 35%, transparent 100%);
          mask-image: radial-gradient(ellipse 58% 52% at 55% 50%, #000 35%, transparent 100%);
  opacity: 0; transition: opacity var(--t-grid) linear; }

/* ⑧ 설치 띠 윗변 수평선 — 돔 림을 일직선으로 편 것 */
.horizon { position: absolute; top: 0; left: 10%; right: 10%; height: 1px;
  background: linear-gradient(90deg, transparent, var(--violet) 30%, var(--violet-bright) 50%, var(--violet) 70%, transparent);
  box-shadow: 0 0 18px 1px rgb(126 94 250 / .45); }
```

### 2.3 글꼴

| 역할 | 글꼴 | 파일·로딩 | KB |
|---|---|---|---|
| H1 · 트립틱 큰 글자 · H2 · 숫자 격자 숫자 · 격자 제목 | **Pretendard Medium 500**(OFL, 원본 `/Users/yesung/aing-check-promo/public/fonts/Pretendard-Medium.woff2`) | `public/fonts/pretendard-500-sub.woff2`, `next/font/local` preload **true**, `display: swap`, 변수 `--font-display` | 실측 34,508B(지금 서브셋 글자 496자 기준) → v2 카피 ≈ 520자로 **≈ 36KB** |
| H3(기능 행) · FAQ 질문 | **Pretendard SemiBold 600**(`Pretendard-SemiBold.woff2`) | `pretendard-600-sub.woff2`, preload false(DOM 에 있어 크롬이 첫 화면에서 받는다 — v1 P-5 교훈) | 실측 34,468B → **≈ 36KB** |
| 본문 · 리드 · 버튼 · 내비 · 라벨 · 카운터 | 시스템 `-apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", system-ui, "Malgun Gothic", "Noto Sans KR", sans-serif` | 0B | 0 |
| brew 명령 한 줄 | JetBrains Mono 400 ASCII(지금 파일 유지) | `jbm-400-ascii.woff2` | 4,440B |

- 800 서브셋(`pretendard-800-sub.*`)은 v2 에서 쓰지 않는다 → 삭제(§6.3).
- 전역: `word-break: keep-all; overflow-wrap: anywhere;` 헤드라인 `text-wrap: balance`, 본문 `text-wrap: pretty`, 숫자 자리 `font-variant-numeric: tabular-nums`. 이탤릭·낱말 하나 색 강조 없음. 대문자 라벨 없음.
- 레퍼런스처럼 **큰 것은 가볍게(500), 작은 제목이 오히려 무겁게(600)**(RA §7).

### 2.4 타입 스케일(390 → 1440 선형 clamp, 기울기 = Δpx/1050)

| 클래스 | 크기 | 행간 | 자간 | 글꼴 | 쓰는 곳 | 1440 / 390 |
|---|---|---|---|---|---|---|
| `t-hero` | `min(clamp(40px, 20.7px + 4.95vw, 92px), 10.4svh)` | 1.06 | −0.03em | 500 | H1 | 92 / 40(789 높이 82) |
| `t-figure` | `clamp(44px, 27.7px + 4.19vw, 88px)` | 1.0 | −0.03em | 500 tabular | 트립틱 「01:00」「콕.」「울트라.」 (H1 × 0.96) | 88 / 44 |
| `t-h2` | `clamp(32px, 20.9px + 2.86vw, 62px)` | 1.12 | −0.025em | 500 | 절 제목 H2(H1 × 0.67) | 62 / 32 |
| `t-h3` | `clamp(26px, 20.1px + 1.52vw, 42px)` | 1.22 | −0.02em | 600 | 기능 행 H3(한글은 라틴보다 빽빽해 RA 0.57 대신 0.46) | 42 / 26 |
| `t-num` | `clamp(32px, 24.6px + 1.90vw, 52px)` | 1.0 | −0.02em | 500 tabular | 숫자 격자 숫자(H1 × 0.56) | 52 / 32 |
| `t-grid-title` | `clamp(26px, 21.5px + 1.14vw, 38px)` | 1.25 | −0.02em | 500 | 숫자 격자 제목 | 38 / 26 |
| `t-lead` | `clamp(17px, 16.3px + .19vw, 19px)` | 1.55 | −0.005em | 400 시스템 | 리드·트립틱 캡션 | 19 / 17 |
| `t-body` | 17px(phone 16px) | 1.7 | 0 | 400 시스템 | 본문·트립틱 단락 | |
| `t-label` | 15px | 1.3 | 0 | 500 시스템 | 기능 행 카테고리 라벨(한글) | |
| `t-small` | 14px | 1.55 | 0 | 400 시스템 | 메타·격자 라벨·설치 단계 | |
| `t-micro` | 13px | 1.5 | 0 | 400 시스템 | 푸터·법적·카운터(`[ 01 / 03 ]`, tabular, 자간 .06em) | |
| `t-nav` | 14px | 1 | 0 | 500 시스템(워드마크 15px 700) | 내비 | |
| `t-chip` | 13px | 1 | 0 | 500 시스템 | 눈썹 칩 1개 | |
| `t-button` | 16px | 1 | −0.005em | 600 시스템 | 주 버튼(높이 48) | |
| `t-button-s` | 14px | 1 | 0 | 600 시스템 | 내비 CTA·복사(높이 34) | |
| `t-faq-q` | `clamp(17px, 15.9px + .29vw, 20px)` | 1.4 | −0.01em | 600 | FAQ 질문 | |
| `t-code` | 15px(phone 13.5px) | 1.5 | 0 | JetBrains Mono 400 | brew 명령 | |

글줄: 본문·리드 `max-width: 34em`, H2 `max-width: 15em`, H1 줄바꿈 고정(`<br>`), 트립틱 캡션 `max-width: 300px`.

### 2.5 간격 · 그리드 · 최대 폭
- 간격 단위 4px: `4 8 12 16 20 24 28 32 40 48 56 64 72 96 120`.
- **프레임** `--frame: min(100vw, 1600px)`, 가운데. 세로 헤어라인 3줄 = 프레임의 `--g-l`·50%·`--g-r`: ≥1280 **10% / 50% / 90%**, 1024–1279 **6% / 50% / 94%**, <1024 왼쪽 선만(레일, x = `--gutter` + 4px).
- 칼럼(desk): 글 칼럼 = `--g-l` + 28px ~ 42%(1440 에서 172–605px), 무대 칼럼 = 50% ~ `--g-r`(720–1296px = **576px**). 무대 단위 길이 `--u` = min(1px, 무대폭 / 576) — ≥1280: `min(1px, calc(.4 * min(100vw, 1600px) / 576))`, 1024–1279: `min(1px, calc(.44 * 100vw / 576))`(1024 에서 0.78px, 1440 에서 1px). 길이 ÷ 길이는 CSS 에서 안 되므로 배율 대신 단위 길이를 쓴다.
- 바깥 여백 `--gutter`: ≥1280 = 10% 선과 같음, 1024–1279 = 6%, 768–1023 = 32px, <768 = 20px.
- 섹션 세로: §3.0 표의 높이. 묶음 간격 — 라벨 → H3 12, H3 → 본문 16, 본문 → 보조 12, H2 → 서브 16, 칩 → H2 20.

### 2.6 반지름(물체의 정체가 정한다)
| 물체 | 값 | 변수 |
|---|---|---|
| 렌더 창(팝오버·메시지·순위판·캐릭터 고르기) | 12px | `--r-window` |
| 버튼·내비 CTA·눈썹 칩 | 999px | `--r-pill` |
| 아이콘 타일 36px | 10px | `--r-tile` |
| 레일 노드 14px | 4px | `--r-node` |
| brew 명령 상자 | 10px | `--r-code` |
| 내비 링크 호버 면 | 8px | `--r-nav` |
| 폰 셸 | `phoneShellMetrics()` 그대로 | — |
| 돔 | 50% | — |
| FAQ 행·섹션·격자 칸 | 0 | — |

### 2.7 그림자
- `--shadow-window: 0 0 0 1px rgb(255 255 255 / .07), 0 24px 48px -12px rgb(0 0 0 / .60), 0 8px 16px -8px rgb(0 0 0 / .45);` — 렌더 창과 폰 셸에만. 첫 겹이 창 가장자리를 가른다(렌더 바탕 대비 1.21).
- 말풍선 렌더는 자기 그림자가 구워져 있어 덧붙이지 않는다. 아잉 영상에는 아무것도 붙이지 않는다.
- 빛(§2.2)은 그림자가 아니다. 버튼·칩·텍스트에는 그림자 없음.

### 2.8 모션 토큰
| 변수 | 값 | 쓰는 곳 |
|---|---|---|
| `--t-instant` | 0ms | 메시지 렌더 unread → read 교체(앱처럼 즉시) |
| `--t-quick` | 120ms | 불투명도 들고 남, 버튼, 노드 점등 |
| `--t-swap-out` | 200ms linear | 트립틱 오브젝트 퇴장(불투명도만) |
| `--t-swap-in` | 240ms linear | 트립틱 오브젝트 등장(불투명도만) |
| `--t-ignite` | 800ms linear | 오브젝트 뒤 라디얼 점등 |
| `--t-draw` | 360ms | 연결선 그리기(C1), C2 는 280ms |
| `--t-pop` | 320ms | 타일 팝(scale .6 → 1.08 → 1, `--ease-pop`) |
| `--t-rise` | 320ms | 렌더 등장 translateY 12 → 0(불투명도는 240ms linear 따로) |
| `--t-grid` | 330ms linear | 점 격자 |
| `--t-dim` | 400ms linear | 연결선 탁해짐 |
| `--t-light` | 800ms steps(12) | 잔디 12칸 점등 |
| `--ease-out` | cubic-bezier(.2,.8,.2,1) | 들어올 때 |
| `--ease-in` | cubic-bezier(.4,0,1,1) | 나갈 때 |
| `--ease-pop` | cubic-bezier(.34,1.56,.64,1) | 타일만 |
| 캐릭터 | 영상 30fps(phone·`deviceMemory ≤ 4`·Save-Data 아님 의 idle 은 15fps 판) | 이징 없음 |
| 말풍선 | `Bubble` 그대로: 등장 120ms 선형 + .96→1 200ms ease-out, 퇴장 160ms 선형. 지속 = 앱 값(`BUBBLE_TEXT.ms`) | |

규칙: 스크롤 하이재킹·스냅·관성 조작 금지. 키프레임은 `@media (prefers-reduced-motion: no-preference)` 안에서만 선언. 서버는 감속 여부를 모른다 → `initial` 을 가르지 말고 전이 시간을 0 으로.

### 2.9 반응형 변수와 `globals.css` 골격

```css
@import "tailwindcss";
@custom-variant desk (@media (min-width: 1024px) and (min-height: 640px));
@custom-variant tab (@media (min-width: 768px) and ((max-width: 1023.98px) or (max-height: 639.98px)));
@custom-variant phone (@media (max-width: 767.98px));

:root {
  --bg-0:#0C0A14; --bg-dome:#06040C; --bg-1:#16132B; --bg-end:#08060F; --surface:#181428; --surface-2:#221C38;
  --line:rgb(255 255 255 / .07); --line-strong:rgb(255 255 255 / .14);
  --ink-1:#F4F1FF; --ink-2:#B8B1D4; --ink-3:#958DB4;
  --aing:#C9B8FF; --aing-hover:#D8CCFF; --on-aing:#14102A;
  --violet:#7E5EFA; --violet-deep:#3B1E8F; --violet-bright:#DA84FF; --violet-core:#FFC8FF; --lilac:#C584F9; --wire-dim:rgb(151 133 193 / .55);
  --shadow-window:0 0 0 1px rgb(255 255 255 / .07),0 24px 48px -12px rgb(0 0 0 / .60),0 8px 16px -8px rgb(0 0 0 / .45);
  --r-window:12px; --r-pill:999px; --r-tile:10px; --r-node:4px; --r-code:10px; --r-nav:8px; --r-tip:8px; --r-seg-in:8px;
  --t-quick:120ms; --t-resize:200ms; --t-swap-out:200ms; --t-swap-in:240ms; --t-ignite:800ms; --t-draw:360ms;
  --t-pop:320ms; --t-rise:320ms; --t-grid:330ms; --t-dim:400ms;
  --ease-out:cubic-bezier(.2,.8,.2,1); --ease-in:cubic-bezier(.4,0,1,1); --ease-pop:cubic-bezier(.34,1.56,.64,1);
  --nav-h:56px; --edge:16px; --gutter:20px; --g-l:20px; --g-r:calc(100% - 20px);
  --dome-r:110vw; --dome-top:13svh; --aing-w:clamp(180px, 26svh, 240px);  /* phone 기본 */
  --stage-w:clamp(220px, 62vw, 260px);                                     /* 트립틱 HERO 상자 폭 */
  --z-nav:50; --z-ultra:90;                                                /* --z-ultra = LicensesNav 건너뛰기 링크(TD §8) */
}
@media (min-width:768px){ :root{ --gutter:32px; --g-l:32px; --g-r:calc(100% - 32px); --nav-h:64px;
  --dome-r:min(56vw,64svh); --dome-top:16svh; --aing-w:clamp(200px,26svh,260px); --stage-w:clamp(240px,34svh,300px); } }
@media (min-width:1024px) and (min-height:640px){ :root{ --gutter:6%; --g-l:6%; --g-r:94%;
  --dome-r:min(44vw,70svh); --dome-top:18svh; --aing-w:clamp(200px,29svh,290px); --stage-w:clamp(260px,40svh,380px); } }
@media (min-width:1280px) and (min-height:640px){ :root{ --gutter:10%; --g-l:10%; --g-r:90%; } }
```
`@theme inline` 은 v1 이름을 그대로 유지한다(`--color-ink-1/2/3`·`--color-surface(-2)`·`--color-aing(-hover)`·`--color-on-aing`·`--color-line(-strong)`·`--color-bg-0/1`, TD §8) + `--color-violet`·`--color-bg-end` 추가. `--hotspot`·`--app-*`·`--spine-gap`·`--z-spine/corner/board`·`--t-base/overlay/move`·키프레임 `spine-drop-*`·`hotspot-pulse`·`label-glow` 는 지운다.

---

## 3. 페이지 구조

### 3.0 순서표(1440×900 기준 높이)

| 순서 | id | 구도 | 높이 | px | 리빌 종류 | 보라가 있는 자리 |
|---|---|---|---|---|---|---|
| 내비 | — | 고정 띠, 투명 → 스크롤 8px 뒤 bg-0 α.88 + 아랫선 | 64px(phone 56) | 겹침 | 없음 | CTA 테두리(라벤더) |
| ① 히어로 | `#top` | 가운데 정렬, 돔 안에 글 + 바닥 가운데 아잉 | `max(100svh, 내용)` | 900 | 로드 뒤 아잉 도착 1회(시간) · 돔이 지는 스크럽 | **돔 림** |
| ② 트립틱 | `#moments` | 스티키 무대(아잉) + 세로로 흐르는 카드 3장 | `3×72svh + 20svh` | 2,124 | 장 교체(가운데 띠 44–56% 통과) | **오브젝트 뒤 라디얼** |
| ③ 기능 절 제목 | `#features` | 가운데 정렬, 눈썹 칩 1개 | 44svh | 396 | 없음(정적) | 칩 안 보라 점 |
| ④ 기능 행 ×6 | `#f-timer` `#f-team` `#f-message` `#f-character` `#f-ai` `#f-iphone` | 왼쪽 레일 + 글 / 오른쪽 무대 576px | 6 × 540px | 3,240 | 행마다 1회 조립(1.6s, ③⑤ 1.9s) | **노드·연결선·타일·점 격자** |
| ⑤ 숫자 격자 | `#facts` | 왼쪽 제목 + 오른쪽 4×2 헤어라인 칸 | 540px | 540 | 1회: 레일 끝 노드 점등 + 칸 40ms 간격 페이드 | 레일 끝 노드 |
| ⑥ 설치 | `#install` | bg-1 띠, Mac / iPhone 2칼럼 + 팀 참여 3단계 | 780px | 780 | 없음 | **윗변 수평선** |
| ⑦ FAQ | `#faq` | 한 칼럼 880px, `<details name="faq">` 10개 | ≈ 740px | 740 | 없음(도구) | 열린 행 표식 |
| ⑧ 아웃트로 | `#closing` | bg-end, 작은 돔 + 바닥 가운데 아잉 | 80svh | 720 | 1회 꾸벅(문턱) → idle 루프 | **작은 돔 림** |
| 푸터 | — | `SiteFooter` | 220px | 220 | — | — |
| 합계 | | | | **9,660px = 10.7 뷰포트** | | |

### 3.1 공통: 아잉 무대(`AingStage`) 재생 규율 — B 의 위험을 여기서 묶는다

무대 하나 = 포스터 층(`<img>`) + idle 층(`AlphaVideo` + `sequenceMeta('aing-idle')`, loop) + once 층(`AlphaVideo`, 반응 1회). 무대는 페이지에 **다섯 자리**뿐이다.

| 무대 | once(반응) | 끝난 뒤 | 시작 조건 | 말풍선(앱 원문 · 앱 지속) | 정지 한 장(감속·Save-Data) |
|---|---|---|---|---|---|
| 히어로 | `aing-commute-start` 45f 1.5s | idle(f45 부터) | `afterLoadIdle` && 무대 ≥ 50% 보임 && 아직 안 틀었음 | `commute-start` "오늘도 화이팅!" 5,000ms(반응 시작과 동시) | `aing-rest-poster` + 말풍선 정지 |
| 트립틱 01 | `aing-milestone` 72f 2.4s | idle(f72) | 카드 01 활성 && 무대 ≥ 25% 보임 | 없음(앱 milestone 은 말풍선 없음 `CheckOverlayReactions.swift:964`) | `aing-milestone-poster`(f48, 색종이) |
| 트립틱 02 | `aing-poked` 90f 3.0s | idle(f90) | 카드 02 활성 | `poked-mint` "민트별님이 콕 찔렀어요!" 6,000ms 또는 카드 이탈까지 | rest + 말풍선 정지 |
| 트립틱 03 | `aing-ultra` 72f 2.4s(울트라 캔버스) | 마지막 프레임 유지 | 카드 03 활성 | `ultra-mint` "민트별님의 울트라 찌르기!" 카드 활성 동안 | `aing-ultra-poster`(f40) + 말풍선 정지 |
| 아웃트로 | `aing-commute-end` 36f 1.2s | idle(f36) | 섹션 ≥ 50% 보임(처음 1회) | `commute-end` "수고했어!" 2,000ms | rest + 말풍선 정지 |

**재생 규율(어기면 반려)**
1. `load` 전에는 캐릭터 영상 요청 0건. 히어로도 포스터(17,974B)만 칠하고 영상은 `afterLoadIdle` 뒤에 붙인다.
2. 영상 요청은 그 무대가 가까울 때만: 히어로 = load 뒤 즉시, 트립틱 = `#moments` 가 `rootMargin 100svh` 안, 아웃트로 = `#closing` 이 `rootMargin 100svh` 안. 트립틱 안에서는 **한 장 앞만** 미리 받는다(01 활성 → 02 받기, 02 활성 → 03 받기).
3. 재생은 무대가 ≥ 25% 보일 때만. 25% 밑이면 `pause()`(되감지 않음), 탭이 숨으면(`visibilitychange`) 멈춘다.
4. **동시에 재생하는 무대는 하나**: `lib/stage-bus.ts` 가 보이는 비율이 가장 큰 무대에만 재생권을 준다. 한 무대 안에서도 디코딩은 idle·once 두 층까지.
5. 감속 모션(`MQ_REDUCED`)·Save-Data → 영상 요청 0건, 위 표의 "정지 한 장". `usePosterOnly()` 그대로.
6. phone·`deviceMemory ≤ 4` → idle 은 15fps 판(`aing-idle-15`, `wantsLowFps()` 그대로). 반응 클립은 30fps 하나뿐이다.
7. 같은 idle 파일 하나를 히어로·트립틱·아웃트로가 함께 쓴다(같은 URL·`immutable` 캐시, 크롬은 범위 요청 응답도 HTTP 캐시에 둔다) → 예산에서는 idle 을 **한 번**으로 계상한다. 통합 때 `shoot.mjs` 전송 KB 로 확인하고, 다시 받는다면 트립틱 01·02 를 "마지막 프레임 유지"로 바꾼다(§5.5).
8. 반응이 끝나면 idle 을 `idleResumeFrame(N) = N mod 432` 프레임에 미리 시크해 두었다가 같은 프레임에서 층을 바꾼다(앱 연속성 규칙, `CharacterStage` 103–146행 함수 이식 — TD §3). idle 이 아직 준비되지 않았으면 once 의 마지막 프레임을 그대로 두고 `canplay` 에서 바꾼다.
9. 반응 클립의 첫 프레임(= 앱의 "idle 위상 262" 자세)은 commute-start·commute-end·poked·milestone 이 모두 같다 → **포스터 한 장(`aing-rest-poster`)을 다섯 무대 중 넷이 공유**한다. 실측: 네 시퀀스의 `0000.png` 를 HERO 상자로 잘라 비교하면 픽셀 차 mean 0 · max 0, 같은 레시피로 인코딩한 webp 는 `cmp` 일치. 그래서 포스터 → 반응 첫 프레임 전환에 튐이 없다.
10. 아잉 층에 `transform`·`filter`·`scale` 금지. 무대 교체는 층의 불투명도(선형)만. 클릭 없음(`pointer-events: none`), 영상·포스터 `aria-hidden="true"`, 포스터 `alt=""`.

**기하(HERO 상자 654×790 출력 기준, 표시 배율 d = W/654)**
- HERO 상자: 폭 W, 높이 1.208W. 아잉 몸 = 상자의 x 8.9–87.1%, y 38.0–99.2%(몸 0.782W × 0.739W, body bbox [540,1144,1563,2111] → HERO [424,544,1308,1580]).
- milestone 상자: 772×790 출력 → 폭 1.180W, 왼쪽으로 −58·d(`sequences.json offsetOut`).
- ultra(울트라 캔버스 2160²): 표시 폭 **1.45W**, 높이 ×1108/1260, 무대 가운데에 중심. 정사각 S = 1.45W × 2160/1680, 정사각 윗변 = 상자 윗변 − 48/2160·S.
- 말풍선 앵커 = 상자 (−50.5·d, 218.5·d), 크기 = `bubbles.json canvasPx × 0.5 × d`(`bubbleSize(id, d)` 그대로). 울트라 말풍선은 1:1 pt(239×64), 정사각 윗변 − 높이 − 8 에 가로 가운데(v1 공통 U 규칙).

### 3.2 내비

- **목적**: 다운로드로 가는 길을 늘 한 번에. 아무것도 바뀌지 않는다.
- **카피**: 워드마크 "아잉체크"(CB:326) · 링크 "기능"(→`#features`) · "설치"(→`#install`) · "자주 묻는 것"(→`#faq`) · CTA "Mac용 다운로드"(CB:49).
- **와이어**
```
1440 ┌─────────────────────────────────────────────────────────────────────────────┐ 0
     │ 144 [■24]아잉체크          기능   설치   자주 묻는 것          [Mac용 다운로드]│ 64  ← 링크 묶음 가운데, CTA 오른쪽 끝 = 1296
     └─────────────────────────────────────────────────────────────────────────────┘
390  ┌──────────────────────────────────────┐
     │ 20 [■22]아잉체크                 [설치]│ 56   링크 숨김(푸터에 있다). phone CTA = '설치'(→#install), iOS = App Store(DownloadCTA nav 분기 그대로)
     └──────────────────────────────────────┘
```
- **에셋**: `brand/icon-64.webp`(1,434B, 24px 표시).
- **모션**: 맨 위 투명. 8px 스크롤(맨 위 1px 감시자 IO) 뒤 `background: rgb(12 10 20 / .88)` + 아랫변 `--line`, 120ms 선형. CTA 는 히어로 주 버튼이 보이는 동안 테두리(라벤더 글자), 가려지면 채움(`useHeroCtaVisible` 재사용), `--t-resize` 선형. `backdrop-filter` 는 쓰지 않는다(영상 위 합성 비용).
- **감속**: 전이 0ms.
- **접근성**: 첫 요소 "본문으로 건너뛰기"(`#main`, `--z-ultra`). `<nav aria-label="주 메뉴">`. 포커스 순서 = 건너뛰기 → 워드마크(`/`) → 링크 3 → CTA.
- **금지**: 활성 섹션 하이라이트(v1 상태 기계 잔재), 메뉴바 라벨 흉내, 햄버거 메뉴.

### 3.3 ① 히어로 `#top`

- **목적**: 3초 안에 "맥 메뉴바 근무 타이머, 아잉이 함께한다"를 알리고 다운로드 버튼을 준다. 돔 + 아잉이 페이지의 얼굴.
- **카피**(그대로)
  - H1 「출퇴근 기록을, / 메뉴바 하나로.」 — CB:64(✓v4)
  - 리드 "근무 시작을 누르면 팀 전체에 바로 보여요. 일하는 동안엔 아잉이 화면 구석에서 함께해요." — CB:67
  - 주 버튼 "Mac용 다운로드" → `/api/download` — CB:68 · 메타 "macOS 14 이상 · 무료" — CB:68
  - 보조: App Store 공식 배지 → `https://apps.apple.com/app/id6812768622` — CB:69 · 텍스트 링크 "brew로 설치" → `#install` — CB:69
  - (CB:70 "Apple 공증 · Apple Silicon·Intel" 은 설치 절 메타로 내린다 — 가운뎃점 사슬을 히어로에서 한 개로 줄이려고)
  - 말풍선(렌더) "오늘도 화이팅!" — 앱 원문 `CheckOverlayReactions.swift:956`
- **와이어 1440×900**(목업 촬영 `mock/hero-1440.png` 로 확인한 배치)
```
y    0 ┌───────────────────────────────────────────────────────────────────────────────┐
       │ 내비 64(투명)                                                                  │
   162 │                             .·´¨¨¨¨¨¨¨¨¨¨¨¨¨¨`·.   ← 돔 꼭대기 18svh, 반지름 630  │
       │                       .·´                          `·.   (중심 720,792 = 88svh) │
   234 │                  .´        출퇴근 기록을,               `.  H1 92/97.5 × 2줄      │
       │               .´           메뉴바 하나로.                 `.  폭 ≈ 560          │
   449 │             /      근무 시작을 누르면 팀 전체에 바로 보여요.  \  리드 19/29.5 × 2 │
       │            /       일하는 동안엔 아잉이 화면 구석에서 함께해요. \ 최대 폭 560      │
   532 │           |        [ Mac용 다운로드 160×48 ] [ App Store 배지 48 ] |             │
   592 │           |          macOS 14 이상 · 무료     brew로 설치          |  13px ink-3 │
   652 │          |              ┌오늘도 화이팅!┐ 169×62                    |             │
       │          |             (   아잉 상자 261×315, 몸 204×193   )       |             │
   880 │          |           ░░░░ 웅덩이 418×63 ░░░░                       |             │
   900 └━━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┷━━━━━━━━━━━━━┘ 바닥선 = 트립틱 윗변
```
  - 세로 흐름: 내비 자리 64 → 위 여백 `calc(var(--dome-top) + 8svh − 64px)` → H1 → 20 → 리드 → 24 → 버튼 줄 → 12 → 메타 → **유연 여백(flex 1, 최소 0)** → 아잉 무대(`margin-top: calc(16px - .334 * var(--aing-w))` = 16px − 상자높이 × 0.277 — 상자 위 27.7% 는 말풍선 자리라 글 블록과 겹쳐도 되고, 말풍선 윗변과 메타 사이는 최소 16px) → 아래 여백 20px.
  - 1440×789(맥북 에어 실제 뷰포트)에서: H1 82px, 아잉 W 229(몸 179×169), 말풍선 윗변이 메타 아래 16px — 목업 1차안(`hero-1440x789.png`)에서 말풍선이 메타를 덮은 것을 이 규칙으로 고쳤다. 내용이 넘치면 히어로가 길어진다(`min-height: 100svh`, 고정 높이 아님).
- **와이어 390×844**
```
y   0 ┌──────────────────────────────────────┐
      │ 내비 56                              │
  110 │   .·´¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨¨`·.      │ ← 돔 지름 220vw(858), 꼭대기 13svh, 좌우는 화면 밖
  186 │        출퇴근 기록을,                │ H1 40/44 × 2
      │        메뉴바 하나로.                │
  290 │   근무 시작을 누르면 팀 전체에 바로   │ 리드 16/25.6 × 3, 최대 320
      │   보여요. 일하는 동안엔 아잉이 화면   │
      │   구석에서 함께해요.                 │
  387 │   [      Mac용 다운로드 320×48     ] │ iOS: 배지가 먼저(order -1), Mac 버튼은 'Mac 링크 보내기'
  447 │          [ App Store 배지 40 ]       │
  499 │   macOS 14 이상 · 무료    brew로 설치 │
  636 │           ┌오늘도 화이팅!┐ 142×52     │
      │          (  아잉 219×265  )          │ W = clamp(180px, 26svh, 240px)
  828 └━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┘ 바닥선
```
- **에셋**: `char/aing-rest-poster.webp`(신규, 654×790, **17,974B**, `fetchpriority="high"` + `<link rel="preload" as="image">`) · `char/aing-commute-start.{webm 151,047 / mov 125,839}` · `char/aing-idle.{webm 808,263 / mov 817,960}`(phone `aing-idle-15` 536,078 / 523,861) · `ui/bubble-commute-start.webp`(242×89, 5,958B, 표시 = 423.5·d × 155.8·d) · `brand/appstore-badge-ko-black.svg`(9,260B, 높이 48 / phone 40, 여백 = 높이/4).
- **모션**
  - t = load + idle(≈ 0.2–2s): 무대 ≥ 50% 보이면 commute-start 재생 + 같은 순간 말풍선 등장(120ms 선형 + .96→1 200ms ease-out). 1.5s 에 idle f45 로 층 교체(§3.1-8). 말풍선은 5,000ms 뒤 160ms 선형 퇴장. 그 뒤 idle 14.4s 루프(히어로 자동 루프 = 이것 하나).
  - 로드 전에 히어로를 벗어났으면 도착을 건너뛰고, 돌아오면 idle 만. **도착 마감**: 내비게이션 시작 뒤 2.5s 까지 commute-start 가 `canplay` 가 아니면 도착을 건너뛰고 idle 로 바로 간다(포스터와 같은 자세라 티가 나지 않는다 — 글을 읽는 도중에 뛰어오르는 버벅임 방지, §7.2 R2).
  - **스크럽(돔이 진다)**: `view-timeline: --hero block` + `.dome { animation: dome-set linear both; animation-timeline: --hero; animation-range: exit 0% exit 100% }`, `@keyframes dome-set { to { transform: translateY(14svh); opacity: .45 } }`. 진행도 p = scrollY / 히어로 높이 → translateY = 14svh·p, opacity = 1 − .55p. 글·버튼·아잉은 움직이지 않는다(그냥 스크롤). `@supports not (animation-timeline: view())`(파이어폭스) 면 정적 — JS 폴백 없음.
- **감속 모션**: 영상 요청 0, `aing-rest-poster` + "오늘도 화이팅!" 정지, 돔 스크럽 없음.
- **접근성**: `<h1>` 은 SSR 텍스트(LCP). 아잉·말풍선 `aria-hidden`. 버튼 접근 이름 "Mac용 다운로드, aing-check.dmg 30.0MB"(`ariaLabel`, 크기는 `getRelease()`). 포커스 순서 = Mac용 다운로드 → App Store → brew로 설치. 버튼 높이 48(터치 44 이상).
- **금지**: [근무 시작] 버튼·팝오버·메뉴바 라벨 흉내, 아잉 클릭 반응, 말풍선 순환 루프, 별밭, 지도, 돔 안 그라디언트 워시.

### 3.4 ② 트립틱 `#moments` — 아잉의 반응 셋

- **목적**: "근무하는 동안 아잉이 화면 구석에서 반응한다"를 큰 글자 셋과 진짜 반응 영상 셋으로. 레퍼런스의 "큰 숫자 + 가운데 3D 오브젝트" 자리에 아잉이 선다.
- **카피**(그대로)
  - 절 제목(시각적으로 숨긴 `<h2>`): 「근무하는 동안, 화면 구석에서 함께.」 — CB:128(✓v4)
  - 카드 01: 큰 글자 **「01:00」**(메뉴바 라벨 렌더 `menubar-0100` 에 보이는 값) · 캡션 「버튼 하나, 메뉴바에서.」 — CB:81 · 단락 "메뉴바에서 근무 시작을 누르면 오늘 누적 시간이 흘러요. 잠깐 비운 거라면, 돌아왔을 때 그대로 이어져요." — CB:82 첫 문장 + CB:83 보조 · 렌더 칩: `ui/menubar-0100.webp`(아잉 얼굴 + 01:00) · 오브젝트: milestone(오늘 1시간 색종이 — README §캐릭터 리액션, CB:133)
  - 카드 02: 큰 글자 **「콕.」** · 캡션 「찔러 부르기.」 — CB:114(✓v4) · 단락 "근무 중인 사람을 콕 찌르면 그 사람 캐릭터가 화들짝 놀라며 누가 불렀는지 말풍선으로 알려요." — CB:115 · 오브젝트: poked + "민트별님이 콕 찔렀어요!"
  - 카드 03: 큰 글자 **「울트라.」** · 캡션 「화면을 덮는다.」 — CB:114(✓v4) · 단락 "꾹 누르면 울트라예요. 내 캐릭터가 상대 화면을 잠깐 덮어요." — CB:115 · 오브젝트: ultra(앱: 받는 사람 화면을 보낸 사람 캐릭터가 덮는다 — 민트별 = 아잉 착용) + "민트별님의 울트라 찌르기!"
  - 카운터 `[ 01 / 03 ]` `[ 02 / 03 ]` `[ 03 / 03 ]`(진짜 순서, 현재 번호만 ink-1)
  - 순서는 세기 순(축하 → 콕 → 울트라). 가장 무거운 울트라가 맨 끝이라 받을 시간이 가장 길다.
- **스크럽·스티키 구현**(desk ≥ 1024 && 높이 ≥ 640, 감속 아님)
```
<section id="moments" style="height: calc(3*72svh + 20svh)">      ← 2,124px @900
  <div class="stage" style="position: sticky; top: 0; height: 100svh">  ← 격자선 10/50/90 · 라디얼 · 아잉 무대 · 말풍선
  <div class="cards" style="margin-top: -100svh">                  ← 카드 3장, 각 height: 72svh, 흐름대로 스크롤
```
  - 고정 구간 = 136svh(1,224px). 고정 시작부터 스크롤 s(svh) 일 때 카드 k 윗변 = (k−1)·72 − s. 활성 카드 = 가운데 띠(`IntersectionObserver rootMargin "-44% 0px -44% 0px"`)에 걸린 카드, 둘이면 나중에 들어온 쪽. 02 는 s = 17svh, 03 은 s = 89svh 에서 활성(들어오는 큰 글자가 ≈ 55% vh — RA §4.3 의 45–65%). s = 136 에서 고정이 풀리고 무대는 카드 03 과 함께 위로 빠진다(RA §5.1).
  - 카드 01 은 처음부터 활성이고, 무대가 ≥ 25% 보이는 순간 milestone 재생.
  - 교체: 나가는 층 불투명 1→0 200ms 선형 + 라디얼 1→0 200ms → 들어오는 클립 `canplay`(최대 300ms 기다림, 넘으면 포스터로) → 프레임 0 부터 재생 + 불투명 0→1 240ms 선형 → 라디얼 0→1 800ms 선형("꺼진 채 들어와 켜짐") → 말풍선은 재생과 동시. 위로 되돌아가도 같은 규칙(이전 카드 반응을 처음부터 — 받은 바이트 재사용).
- **와이어 1440×900(카드 02 정착 — 목업 `mock/trip-1440.png` 로 확인)**
```
y  64 ├──────────┬──────────────────────────────┬──────────────────────────────┬──────────┤ 헤더선(내비 아랫변)
      │   144    │172                           │720                           │1296      │ 세로선 10/50/90
  144 │          │ 콕.            t-figure 88   │       ╭─────╮                │          │
      │          │                              │  ┌민트별님이 콕┐  아잉 상자    │          │ 상자 360×435
  252 │          │ 찔러 부르기.    lead 19 ink-2 │  │ 찔렀어요!  │  (body 282×266)│          │ 말풍선 230×120 @ (512,243)
      │          │                              │  └──────────┘ ( ◕ ‿ ◕ )      │          │ 라디얼 Ø576 중심 (720,423)
      │          │                              │              (        )      │          │
  522 │          │                              │                    단락 300px  │ 950 근무 중인 사람을 콕 …│
  594 │          │ [ 02 / 03 ]   micro tabular  │                               │ 17/28.9 × 3 │
  648 ├──────────┼─────── 카드 아랫선 ───────────┼──────────────────────────────┼──────────┤ 72svh
  774 │          │ 울트라.   ← 다음 장 미리보기(86svh)                           │          │
  900 └──────────┴──────────────────────────────┴──────────────────────────────┴──────────┘
```
  - 카드 안 배치(카드 윗변 기준): 큰 글자 윗변 16svh · 캡션 = 큰 글자 + 20px(최대 폭 300) · 01 의 렌더 칩(높이 33 = 22pt × 1.5, 폭 116) = 캡션 + 16px · 카운터 66svh · 단락 왼쪽 = 66%(1440 에서 950), 윗변 58svh, 폭 300 · 카드 아랫선 72svh(10% ~ 90%, 무대 아래로 지나감).
  - 무대: HERO 상자 W = `--stage-w`(1440×900 = 360) · 상자 윗변 = 47svh − 0.69·1.208W(몸 중심 = 47svh) · milestone 425×435 왼쪽 −32 · ultra 522×459 중심 (50%, 47svh), 울트라 말풍선 239×64 @ y 107.
- **와이어 390 / 768 / 감속(스티키 없음, 카드 세로 나열)**
```
390 ┌──────────────────────────────┐
    │ [ 01 / 03 ]                  │ 카운터가 위로(phone)
    │ 01:00            figure 44   │
    │ 버튼 하나, 메뉴바에서.        │ lead 17
    │ [■ 01:00 칩 116×33]          │
    │      (  아잉 상자 242×292  ) │ 카드마다 자기 무대 W = --stage-w(242) · 라디얼 Ø320
    │ 메뉴바에서 근무 시작을 누르면  │ body 16
    │ 오늘 누적 시간이 흘러요. …    │
    ├──────────────────────────────┤ 카드 높이 = 내용(≈ 700)
    │ [ 02 / 03 ]  콕. …            │
```
  - phone·tab: 카드마다 `AingStage` 하나(셋), 무대가 처음 ≥ 60% 보일 때 1회 재생 → 01·02 idle, 03 유지. stage-bus 가 동시 재생을 막는다. 울트라 폭 = 1.25W(phone 302).
- **에셋**: `char/aing-milestone.{webm 331,045 / mov 410,046}` · `char/aing-poked.{webm 328,060 / mov 260,505}` · `char/aing-ultra.{webm 667,105 / mov 604,147}` + `aing-ultra-poster.webp`(34,592) · `ui/bubble-poked-mint.webp`(7,854) · `ui/bubble-ultra-mint.webp`(14,936) · `ui/menubar-0100.webp`(232×66, 3,408) · 감속 전용 `char/aing-milestone-poster.webp`(신규, f48, 26,614). 합계(크롬) **1,387,000B**.
- **감속 모션 폴백**: 스티키 없음, 카드 세로 나열(phone 와이어와 같다), 카드마다 정지 한 장(§3.1 표) + 말풍선 정지, 라디얼은 처음부터 켜짐.
- **키보드·접근성**: 카드 = `<article tabindex="0" aria-labelledby>`(brief §5.1 "트립틱 안 요소에 포커스 가능"), `scroll-margin-top: 16svh` 라 Tab 으로 넘기면 그 카드가 가운데 띠에 들어와 교체가 따라온다. 제목 = `<h3>` 안에 큰 글자(`<span>`)와 캡션(줄바꿈은 CSS). 카운터는 `aria-hidden`(순서는 문서 순서가 말한다). 영상·말풍선 `aria-hidden` — 단락이 같은 내용을 말한다. 포커스 링 = `--aing` 2px.
- **금지**: 클릭·호버로 장 넘기기, 화살표 버튼, 점 페이지네이터, 스냅, 아잉 확대·회전(울트라의 큰 크기는 렌더 자체의 캔버스 — CSS 확대 아님), 울트라 전면 오버레이(v1 공통 U — 페이지를 덮지 않는다), 앱에 없는 말풍선 짝(milestone 에 말풍선 붙이기 등).

#### 3.4.8 부록 — 리드가 가로 스크럽을 고를 경우(대안 명세)
- `section height: calc(100svh + 2 × 85svh)`, 안에 `sticky top:0 height:100svh` 뷰포트, 트랙 `display:flex; width:300vw`, 카드 폭 100vw.
- 매핑: p = (scrollY − sectionTop) / (sectionHeight − 100svh) ∈ [0,1] → 트랙 `translateX(−200vw · p)`. CSS `animation-timeline: view()` + `animation-range: contain 0% contain 100%`, 미지원은 rAF 1개(passive scroll)에서 `--p` 갱신. 아잉 무대는 트랙 밖 가운데에 고정(교체 규칙은 위와 같음, 활성 = round(2p)).
- 키보드: 카드 `tabindex="0"`, 포커스 시 `window.scrollTo({ top: sectionTop + i·85svh })`. 감속·phone·tab: 위 세로 나열 폴백 그대로.
- B 가 세로를 고른 이유: 레퍼런스가 실제로 세로다(RA §0.2-2), 가로는 "스크롤했는데 옆으로 간다"는 하이재킹 감각과 iOS 관성에서 튐이 생기고, 감속 폴백이 레이아웃을 통째로 바꾼다.

### 3.5 ③ 기능 절 제목 `#features`

- **목적**: 아잉의 반응(감정)에서 앱이 하는 일(사실)로 넘어가는 문턱. 페이지 유일의 눈썹 칩.
- **카피**: 칩 "Mac 메뉴바 앱 · iPhone 앱" — CB:62 · H2 「같이 켜는 근무 타이머.」 — CB:66(포지셔닝 문장) · 서브 "일하는 시간을 스스로 재고, 팀이 지금 어디쯤인지 한눈에 보는 앱." — CB:30
- **와이어**
```
1440  y 0 ─── (격자선 10/50/90 계속, 왼쪽 선 = 레일) ───
       120          ( ● Mac 메뉴바 앱 · iPhone 앱 )      칩 높이 30, 13px, 테두리 line-strong, ● = violet 6px
       170              같이 켜는 근무 타이머.             H2 62/69.4, 한 줄(폭 ≈ 640), 가운데
       256    일하는 시간을 스스로 재고, 팀이 지금 어디쯤인지 한눈에 보는 앱.   lead 19 ink-2
       396 ─── 첫 행 시작
390   칩 → H2 32/35.8 두 줄(「같이 켜는 / 근무 타이머.」) → 서브 17 두 줄, 위아래 72
```
- **모션**: 없음(정적 — 트립틱이 막 큰 움직임을 끝냈다). **감속**: 같다. **접근성**: `<h2 id="features-title">`, 칩은 `<p>`(장식 아님, 읽힌다). **금지**: 대문자·영문 칩, 두 번째 칩, 칩 화살표.

### 3.6 ④ 기능 행 ×6 — 레일 + 노드 + 무대 조립

#### 3.6.0 공통 기하·안무
- **레일(`Rail`)**: x = `--g-l`(1440 → 144px), 1px `--line`, `#moments` 윗변에서 `#facts` 끝까지 한 줄(트립틱에서는 왼쪽 격자선과 같은 선). 행이 리빌될 때 이전 노드 → 이 노드 구간에 1px 보라 조각(`linear-gradient(to bottom, rgb(126 94 250 / 0), rgb(126 94 250 / .7))`)이 `scaleY 0 → 1`(origin top) 240ms ease-out 으로 내려오고 그대로 남는다.
- **노드**: 레일 위 14px(§2.2-⑥), 세로 위치 = 카테고리 라벨 줄 가운데. 리빌 때 켜지고 계속 켜져 있다.
- **행 격자(desk)**: 글 칼럼 `--g-l`+28 ~ 42%(라벨 → H3 → 본문 → 보조, 세로 가운데) · 무대 칼럼 50% ~ `--g-r`, 무대 576×500(모든 좌표·크기 = `calc(N * var(--u))` — `transform: scale` 를 쓰지 않는다: 무대 안에 아잉 스틸이 있다). 행 높이 `min-height: 540px`.
- **무대 문법**: 타일 T(0,30, 36px — 앱 아이콘 24px 를 품은 보라 타일) → 연결선 C1(타일 → 주 렌더 R) → R(렌더 창, 배율 0.70 = 414pt → 290px, `--shadow-window`, `--r-window`) → C2(R → 보조 S) → S → 점 격자 G(무대 뒤 전체) → 선 탁해짐.
- **리빌 문턱**: 행의 라벨 줄 윗변이 뷰포트 68% 선을 지나면(`IntersectionObserver rootMargin "0px 0px -32% 0px"`, threshold 0) **한 번** `data-revealed="true"`. 되감기·재생 없음(위로 올라가도 그대로). 시간차는 전부 CSS `transition-delay`(JS 타이머 0).

| t(ms) | 요소 | 속성 | 시간 · 커브 |
|---|---|---|---|
| 0 | 레일 조각 · 노드 | scaleY 0→1 · `data-lit` | 240 ease-out · 120 linear |
| 120 | 타일 T | opacity 0→1 / scale .6→1.08→1 | 120 linear / 320 `--ease-pop` |
| 240 | C1 | stroke-dashoffset 1→0(밝은 `--violet-bright`) | 360 ease-out |
| 480 | R | opacity 0→1 / translateY 12→0 | 240 linear / 320 ease-out |
| 720 | C2 | stroke-dashoffset 1→0 | 280 ease-out |
| 900 | S | 아잉 스틸: opacity 0→1 160 linear(변형 없음) · 말풍선: `Bubble` 전이 · 카드·위젯·라벨: opacity 200 linear + translateY 8→0 240 ease-out | |
| 1060 | G | opacity 0→1 | 330 linear |
| 1200 | C1·C2 | stroke → `--wire-dim` | 400 linear |
| 1600 | 끝(③ 은 1,900 에 렌더 교체, ⑤ 는 1,100–1,900 잔디 점등) | | |

- SSR·JS 없음: 숨김 상태는 `html.js` 일 때만 걸린다(인라인 스크립트가 붙임) → JS 가 죽어도 무대는 다 보인다. 글(라벨·H3·본문)은 처음부터 보이고 움직이지 않는다.
- **phone·tab**: 레일 x = `--gutter` + 4, 글 → 무대 세로 쌓기. 무대 = R(폭 290 고정, 가운데) + S 를 R 의 오른쪽 아래 모서리에 (−16, −24) 겹침. 연결선·타일 없음(레일 조각과 노드만). 리빌 = R 240 linear + rise, S +240ms. 점 격자 없음.
- **감속**: 처음부터 최종 상태(③ 은 read 판, ⑤ 는 final 판), 전이 0.
- **접근성**: 행 = `<article aria-labelledby>`, 라벨 `<p>`, 제목 `<h3>`(t-h3 600). 렌더 `alt` = `ALT[...]`(fixtures 문장 그대로), 아잉 스틸 `alt=""`, 말풍선 `alt` = 앱 문구(예 "말풍선: 일하는 것 같아서 근무 시작했어요!"), 타일·노드·선·격자 `aria-hidden`. 포커스 가능한 요소 없음.
- **금지**: "Learn more ›" 알약, 카드 호버 들림, 렌더 위 핫스팟·커서, 같은 뷰포트에 팀 행 합과 리그 총합 동시 노출(CB:373), 렌더에 필터·틴트, 행마다 다른 레이아웃 실험(문법은 하나).

#### 3.6.1 행별 명세(무대 좌표 = `--u` 1px 기준, (x, y) = 왼쪽 위)

| 행 | 라벨 · H3 · 본문 · 보조(전부 그대로) | R | S | 연결선 |
|---|---|---|---|---|
| ① `#f-timer` | 「근무 타이머」 CB:79 · 「깜빡해도, 알아서.」 CB:81 · "깜빡해도 괜찮아요. 컴퓨터를 쓰기 시작하면 아잉이 알리면서 대신 켜고, 맥을 덮고 떠나면 덮은 시각에 맞춰 정리돼요." CB:82 · "인터넷이 끊겨도, 누른 순서대로 반영돼요." CB:83 | `ui/popover-on` 290×457 @(120,22) — 근무중 00:00, 5명 근무중 | 아잉 스틸 `char/aing-rest-poster`(히어로에서 받은 것, 0B) HERO 상자 W 132 @(424,318) + 말풍선 `autostart` 117×44 @(414,362) | C1 (36,48)→(120,48) · C2 R 오른쪽 (410,110)→(468,110)→(468,362) |
| ② `#f-team` | 「팀」 CB:98 · 「지금 누가 일하는지, 한 화면에.」 CB:100 · "누르는 순간 팀 전체에 보여요. 팀원마다 지금 근무 시간과 이번 주 진행이 한 줄씩 보이고, 목표는 팀 합계가 아니라 각자의 약속이에요." CB:101 · "다른 팀과는 1인당 평균으로 나란히 서요. 리그에는 팀 숫자만 오르고 개인 숫자는 오르지 않아요." CB:102 | `ui/popover-working` 290×457 @(200,41) | 메뉴바 라벨 `ui/menubar-0345` 116×33 @(374,2) — 라벨 아랫변 + 6px = R 윗변(앱처럼 매달림). 이 행만 S 가 R 보다 먼저(480ms), R 은 720ms | C1 (36,48)→(200,48)(R 왼쪽 변) · C2 없음(6px 매달림이 연결) |
| ③ `#f-message` | 「콕 / 메시지」 CB:123(앱 레일 버튼 이름) · 「하고 싶은 말은, 메시지로.」 CB:114 · "할 말은 1:1 메시지로 보내요. 상대가 읽으면 옆의 1이 사라져요. 방해받기 싫은 날엔 집중 모드를 켜 두세요." CB:116 | `ui/message-unread` 290×422 @(120,40) → **1,900ms 에 `ui/message-read` 로 즉시 교체**(같은 크기, "1이 사라짐" — 레퍼런스 카운트업 자리) | 아잉 스틸 `char/still-poked-sm`(poked f60, 착지 자세) W 132 @(424,318) + 말풍선 `message-gureum` 109×44 @(414,362)(앱: 메시지 수신 = poked 동작) | C1 (36,48)→(120,48) · C2 (410,130)→(468,130)→(468,362) |
| ④ `#f-character` | 「캐릭터」 CB:126 · 「일한 만큼, 루비.」 CB:128 · "일한 시간만큼 루비가 쌓이고, 상점에서 캐릭터를 골라요. 고른 캐릭터는 바탕화면·메뉴바·팝오버에서 함께 바뀌어요." CB:130 | `ui/character-pick` 290×347 @(120,60) — 6종이 보이는 유일한 컷(한 번만) | 아잉 스틸 `char/still-ultra-charged`(f54) 124×117 @(427,367)(HERO 상자 W 132 @(424,318) + offsetOut(14,244)·d) + 말풍선 `ruby` 63×31 @(414,362)(앱: 루비 +3! = ultraCharged 짝) | C1 (36,48)→(120,48)→(120,60) · C2 (410,150)→(468,150)→(468,362) |
| ⑤ `#f-ai` | 「AI 사용량」 CB:152 · 「이번 달 AI 토큰, / 전체 순위판.」 CB:154 · "이 맥의 Claude Code·Codex 기록에서 숫자만 세어 이번 달 사용량을 보여 줘요. 대화 내용은 읽지 않아요." CB:155 · "최근 12주의 근무와 AI 토큰은 잔디로 쌓여요." CB:144 | `ui/token-month` 290×477 @(110,12) | 잔디 카드 `ui/grass-token-empty` 위에 `ui/grass-token-final` 겹침, 표시 292×166(@3x × 0.32) @(284,318), `--r-window` 10 + 그림자. **1,100ms 부터 800ms steps(12)** 로 final 의 `clip-path: inset(0 R 0 L)` R 을 줄여 왼쪽 열부터 한 주씩 켠다(열 경계 = `grass.json token.grid` originX·pitch·cols → `lib/grass/grass-geometry.ts`) | C1 (36,48)→(110,48) · C2 (400,260)→(430,260)→(430,318) |
| ⑥ `#f-iphone` | 「iPhone」 CB:180 · 「이제, 아이폰에서도.」 CB:182 · "맥에서 켠 근무가 폰에서도 보여요. 팀 현황·메시지·할 일·순위·게임을 폰에서 보고, 홈 화면 위젯으로도 봐요." CB:183 · "근무 시작·종료는 맥에서 해요." CB:185 | `PhoneShell screenWidth={210}` + `ios/now`(셸 ≈ 225×472) @(120,14), 정면(기울이지 않는다) | 위젯 `ios/widget-todos-large-checked` 218×229(364pt × 0.6) @(352,250) | C1 (36,48)→(120,48) · C2 (345,120)→(400,120)→(400,250) |

와이어(행 ① 1440 — 다른 행은 R·S 만 바뀐다)
```
x   144  172                           605      720                                        1296
y 0 ─┬─────────────────────────────────────────┬──────────────────────────────────────────────┬─
     │                                          │ ░ 점 격자 G(무대 뒤, 가운데 진하고 가장자리 0) ░ │
  70 ■  근무 타이머            t-label 15 ink-2  │[T]────C1────┌─────────────┐                  │
     │  깜빡해도, 알아서.      t-h3 42/51 600    │             │ popover-on  │──C2──┐            │
     │                                          │             │ 290×457     │      │            │
     │  깜빡해도 괜찮아요. 컴퓨터를 쓰기 시작하면  │             │ 근무중 00:00 │ ┌일하는 것 같아서┐│
     │  아잉이 알리면서 대신 켜고, …  body 17/28.9│             │             │ └근무 시작했어요!┘│
     │  인터넷이 끊겨도, 누른 순서대로 반영돼요.   │             │             │   ( 아잉 132 )   │
 540 ┼──────────────────────────────────────────┴─────────────┴─────────────┴──────────────────┴─
```
390(행 ①)
```
 20 ■ 근무 타이머
    │ 깜빡해도, 알아서.         t-h3 26/31.7
    │ 깜빡해도 괜찮아요. …      body 16
    │   ┌──────────────┐
    │   │ popover-on   │ 290×457, 가운데
    │   │              │ ┌일하는 것 같아서┐  ← S 가 R 오른쪽 아래 모서리에 (−16, −24) 겹침
    │   └──────────────┘ (아잉 112)
    ┼ 행 사이 72
```

### 3.7 ⑤ 숫자 격자 `#facts`

- **목적**: 레퍼런스 "In Numbers" 의 리듬을 제품 사실만으로. 사용자 수·별점·순위·토큰 실측 0.
- **카피**: 제목 `<h2>` 「작은 Mac 팀을 위한 메뉴바 근무 타이머.」 — CB:29(README 첫 줄). 칸 = 라벨(위) + 숫자(아래) + 덧말.

| 칸 | 라벨 | 숫자 | 덧말 | 출처 |
|---|---|---|---|---|
| 1 | 요금 | 0원 | — | `docs/terms.md` §1 · App Store 실측 '무료'(CB:17·21) |
| 2 | macOS | 14 | 이상 | `scripts/build-local.sh:14-15` `LSMinimumSystemVersion 14.0`(CB:19) |
| 3 | iOS | 18 | 이상 | App Store 실측 · `CheckAppLinks.swift:21`(CB:17·192) |
| 4 | DMG | 30.0MB | — | `getRelease()` → `formatMB(size)`(실패 시 `RELEASE_FALLBACK` 29,981,558B, brief §1) — 서버에서 렌더, 하드코딩 금지 |
| 5 | 근무·AI 토큰 잔디 | 12주 | — | CHANGELOG 0.2.41·0.3.35(CB:149) |
| 6 | 미니게임 | 3종 | — | CHANGELOG 0.3.38 · `MiniGameEngine.swift:13`(CB:173·391 — 타이밍 바·플래피 아잉·테트리스) |
| 7 | 오목·체스 | 1:1 | — | CHANGELOG 0.3.27·0.3.43(CB:174–175) |
| 8 | 외부 SDK | 0 | — | `Package.swift` 의 `url:` 의존 0건(CB:20) |

  넣지 않은 것: 위젯 수(brief "2종" ↔ CB:191 "넷" 충돌, 렌더는 2종뿐) · 캐릭터 수('일곱' 금지) · 별점·사용자 수 · 메시지 24시간 등 규칙 수치(FAQ 로).
- **와이어**
```
1440 y 0 ──────────── 가로 헤어라인(10%~90%) ────────────────────────────────────────────────
     144 ■ 작은 Mac 팀을     │ 요금        │ macOS       │ iOS         │ DMG          │  칸 4 × 201px(34%~90%)
          위한 메뉴바        │             │             │             │              │  칸 왼쪽 세로 헤어라인 = 칸 높이
          근무 타이머.       │ 0원          │ 14 이상      │ 18 이상      │ 30.0MB       │  t-num 52 / 덧말 t-small ink-3
     (t-grid-title 38/47.5)  ├─────────────┼─────────────┼─────────────┼──────────────┤
                             │ 근무·AI 토큰 │ 미니게임     │ 오목·체스    │ 외부 SDK      │  칸 높이 180, 라벨 t-small ink-2
                             │ 12주         │ 3종          │ 1:1          │ 0             │
     540 ─────────────────────────────────────────────────────────────────────────────────────
390  제목(26/32.5) → 2열 × 4행(칸 163×140), 칸 왼쪽 헤어라인, 레일 끝 노드는 제목 왼쪽
```
- **모션**: 섹션 윗변이 68% 선을 지나면 1회 — 레일 마지막 조각 + 끝 노드 점등(0ms) → 칸 8개 opacity 0→1 200ms linear, 40ms 간격(좌→우, 위→아래). 숫자 카운트업 없음(레퍼런스도 정적, RA §0.2-8). **감속**: 처음부터 보임.
- **접근성**: `<dl>`(칸 = `<div><dt>라벨</dt><dd>숫자 덧말</dd></div>`), `dd` 는 "14 이상"처럼 이어 읽힌다. **금지**: 아이콘 그리기(레퍼런스 칸 아이콘 — 우리에겐 의미 없는 장식), 카운트업, "+" 접미사 과장.

### 3.8 ⑥ 설치 `#install`(bg-1 띠)

- **목적**: 받는 방법 셋을 한 화면에. 플랫폼에 맞는 쪽이 먼저.
- **카피**(그대로): H2 「지금, 메뉴바에.」 CB:224
  - Mac: 칼럼 라벨 "Mac" · 버튼 "Mac용 다운로드" CB:227 · 메타 "macOS 14 Sonoma 이상 · Apple Silicon·Intel · Apple 공증" CB:228 · 단계 ① "받은 파일을 열어요" ② "aing-check 아이콘을 Applications 폴더로 끌어다 놓아요" ③ "실행하면 메뉴바 오른쪽 위에 아이콘이 떠요" CB:229 · 작은 링크 "GitHub Releases에서 zip으로 받기" → `https://github.com/yehsung/check/releases/latest` CB:238
  - 터미널: "터미널이 편하다면" CB:234 · `brew install yehsung/check/aing-check` + [복사] → "복사했어요" CB:235 · "업데이트는 `brew update && brew upgrade --cask aing-check` 한 줄이고, 끝나면 앱이 다시 켜져요." CB:236 + 명령 정정 CB:394
  - iPhone: 칼럼 라벨 "iPhone" · App Store 배지 CB:241 · QR(desk 만) CB:242 · "iOS 18 이상 · 무료" · "근무 시작·종료는 맥에서 해요." CB:243
  - 팀 참여 3단계(진짜 순서라 번호): 1 가입 "별명·이메일·비밀번호로 가입해요." CB:246 · 2 팀 코드 "팀원에게 받은 팀 코드를 넣으면 들어갈 팀 이름이 미리 떠요. 팀이 없으면 새 팀을 만들고, 생긴 코드를 동료에게 건네요." CB:247 · 3 메뉴바 "그다음부턴 메뉴바에서 근무 시작만 누르면 돼요." CB:248
  - "경고 없이 열려요"는 DMG 공증·스테이플 확인 전까지 쓰지 않는다(CB:231·399).
- **와이어**
```
1440 y 0 ════════════ 윗변 수평선(§2.2-⑧, 10%~90%) ════════════════════════════════════
      72                       지금, 메뉴바에.            H2 62, 가운데
     190 │ Mac                              │ iPhone                                   │
         │ [ Mac용 다운로드 ]  48           │ [ App Store 배지 48 ]    ┌QR 112┐         │
         │ macOS 14 Sonoma 이상 · …  small  │ iOS 18 이상 · 무료        └──────┘         │
         │ ① 받은 파일을 열어요             │ 근무 시작·종료는 맥에서 해요.               │
         │ ② aing-check 아이콘을 …          │                                          │
         │ ③ 실행하면 메뉴바 …              │                                          │
         │ 터미널이 편하다면                 │                                          │
         │ ┌$ brew install yehsung/check/aing-check [복사]┐ surface, r10, 높이 48         │
         │ 업데이트는 … 한 줄이고, …   GitHub Releases에서 zip으로 받기              │
     560 ├──────────── 1 가입 ──────────┼──────── 2 팀 코드 ────────┼──── 3 메뉴바 ──────┤ 3칸, 위 헤어라인
         │ 별명·이메일·비밀번호로 …      │ 팀원에게 받은 팀 코드를 … │ 그다음부턴 …        │
     780 ═══════════════════════════════════════════════════════════════════════════════════
390  H2 → (iOS 면 iPhone 칸 먼저) Mac 칸 → 터미널 → iPhone 칸(QR 없음) → 3단계 세로, 칸 사이 헤어라인
```
- **재사용**: `DownloadCTA placement="install" size="l"`(mac·other = `<a href="/api/download">`, ios = 'Mac 링크 보내기'), `CommandBox`·`CopyButton`(알림 → `lib/announce.ts` → `LiveAnnouncer`), `AppStoreBadge height={48} placement="install"`, `QrCode size={112}`(desk 만), `installChoice(release, RELEASE_FALLBACK)`(서버). 플랫폼 판별 = `<head>` 인라인 `PLATFORM_SCRIPT` → `html[data-platform]`, `html[data-platform=ios] .col-iphone { order: -1 }`.
- **모션**: 없음(복사 버튼 문구만 "복사했어요" 2초, `TIMING.copyResetMs`). **감속**: 같다.
- **접근성**: `<h2>`, 칼럼 `<section aria-labelledby>`, 단계 `<ol>`, 다운로드 접근 이름에 형식·크기, 복사 성공은 `role=status`. **금지**: 소속 센터 언급(DECISIONS §8 미게재), 가입 절차 약속(이메일 인증 등), 판매자명 저작권 확정 전 표기.

### 3.9 ⑦ FAQ `#faq`

- **카피**: 제목 「궁금한 것들.」 CB:252 · 10문항 CB:254–273(`data/faq-items.ts` 그대로, 순서 동일). 센터 예비 문항은 미게재.
- **와이어**
```
1440 y 0       궁금한 것들.        H2 62, 가운데
     120 ┌──────────────────────── 880px, 가운데 ────────────────────────┐
         │ 요금이 있나요?                                          ＋   │ summary 높이 58, t-faq-q 20 600
         ├──────────────────────────────────────────────────────────────┤ 행 사이 --line
         │ 어떤 기기에서 쓰나요?                                    ＋   │
         │ … (10행)                                                     │
     ≈700└──────────────────────────────────────────────────────────────┘
390  제목 32 → 목록 전체 폭(좌우 20), summary 54
```
- **도구(허용)**: `<details name="faq">`(한 번에 하나), `FaqHash`(`#faq-n` 딥링크), `faqJsonLd()` JSON-LD. 열린 행: 바탕 `--surface`, 표식 ＋ → × (아이콘만 45° 회전 160ms ease-out), 표식 색 `--violet-bright`. `::details-content` 높이 전이 200ms(지원 브라우저만, v1 `FaqSection.tsx:11–30` 클래스 이식).
- **감속**: 회전·높이 전이 0. **접근성**: `<summary>` 기본 키보드, 질문은 `<h3>` 안 아님(summary 텍스트). **금지**: 아코디언 JS, sticky 제목 + 2칼럼(broadsheet 신호).

### 3.10 ⑧ 아웃트로 `#closing`

- **목적**: 처음과 같은 돔 아래에서 아잉이 퇴근 인사를 하고, 마지막 다운로드 기회를 준다(레퍼런스 엔드카드의 "검정 위 마크 하나").
- **카피**: H2 「메뉴바에, / 아잉 하나.」 — CB:280 · 리드 "맥에 설치하고, 팀 코드를 나눠 주세요." — CB:281 · 버튼 Mac용 다운로드 · App Store 배지 · brew 명령 복사 — CB:282 · 말풍선(렌더) "수고했어!" — `CheckOverlayReactions.swift:963`
- **와이어**
```
1440 y 0 ┌────────────────────── bg-end #08060F ───────────────────────────┐
     126 │                 .·´¨¨¨¨¨¨¨¨¨¨¨¨¨`·.     작은 돔 r = min(30vw,46svh) = 414, 꼭대기 14svh
     216 │             .´     메뉴바에,          `.   H2 62/69.4 × 2, 가운데
         │           /        아잉 하나.            \
     371 │          |   맥에 설치하고, 팀 코드를 나눠 주세요.  |  lead 19
     424 │          | [Mac용 다운로드] [App Store 48] [brew 명령 복사] | 높이 48 · 48 · 40(secondary)
     503 │         |          ┌수고했어!┐ 110×53                |
         │         |        ( 아잉 W 225 상자 225×272 )          |
     720 └━━━━━━━━━┷━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┷━━━━━┘ 바닥선 = 푸터 윗변
390  히어로 phone 와이어와 같은 문법(돔 지름 200vw, 꼭대기 10svh), 버튼 세로 쌓기, 아잉 W clamp(170px,24svh,220px)
```
  - 세로 흐름은 히어로와 같은 규칙(유연 여백 + 말풍선 윗변과 버튼 사이 최소 16px). 섹션 `min-height: 80svh`.
- **에셋**: `char/aing-commute-end.{webm 101,842 / mov 83,484}` · `ui/bubble-commute-end.webp`(4,988) · idle·rest 포스터는 캐시 재사용(0B).
- **모션**: 섹션이 처음 ≥ 50% 보이면 commute-end 1회(1.2s) + 말풍선 2,000ms → idle f36 부터 루프(아웃트로 자동 루프 = 이것 하나, brief §5.2 "꾸벅 1회 → idle"). 돔 스크럽 없음.
- **감속**: rest 포스터 + "수고했어!" 정지.
- **접근성**: `<h2>`, 아잉·말풍선 `aria-hidden`, 버튼 3개 포커스 순서 왼→오. brew 복사 = `CopyButton variant="secondary" label="brew 명령 복사"`, 알림 "복사했어요".
- **금지**: 색종이·하트 같은 장식 애니메이션, 아잉이 사라지는 페이드(앱은 퇴근 뒤 사라지지만, 페이지는 다운로드 버튼 옆에 아잉을 남긴다 — idle 이 이어짐), "근무 종료" 버튼.

### 3.11 푸터
- `SiteFooter` 재사용(TD §1.2). 링크 지원·개인정보 처리방침·이용약관·GitHub·버그·요청(CB:283), 첫 언급 "아잉체크(aing-check)"(CB:328). 바탕 bg-end, 윗변 `--line`. 저작권 표기 문구는 사용자 확인 전까지 v1 그대로(CB:284).

---

## 4. 반응형 — 390 / 768 / 1024 / 1440

| 항목 | 390(phone) | 768(tab) | 1024(desk, 높이 768) | 1440(desk, 높이 900) |
|---|---|---|---|---|
| 내비 | 56 · 워드마크 + CTA(iOS = App Store) | 64 · 링크 3 + CTA | 64 | 64 |
| 세로 격자선 | 레일만(x 24) | 레일만(x 36) | 6 / 50 / 94% | 10 / 50 / 90% |
| 히어로 돔 | 지름 220vw, 꼭대기 13svh, 좌우 화면 밖 | r = min(56vw, 64svh), 16svh | r = min(44vw, 70svh) = 450 | 630 |
| H1 | 40px · 2줄 | 58.7px | 71.4px | 92px(789 높이 82) |
| 히어로 아잉 W | clamp(180, 26svh, 240) = 219 | clamp(200, 26svh, 260) = 260 | clamp(200, 29svh, 290) = 223 | 261 |
| 히어로 버튼 | 세로 쌓기, 폭 320, iOS 는 배지 먼저 | 가로 | 가로 | 가로 |
| 트립틱 | 스티키 없음, 카드 세로 나열, 카드마다 무대 W 242, 울트라 1.25W(302) | 스티키 없음, 카드 2칼럼(무대 왼쪽 W 300 / 글 오른쪽) | 스티키, 무대 W 307, 단락 66% | 스티키, W 360 |
| 기능 행 | 세로 쌓기, R 290 가운데, S 겹침, 선·타일·격자 없음 | 세로 쌓기, R 290 + S, 선 없음 | 2칼럼, `--u` 0.78px | 2칼럼, `--u` 1px |
| 숫자 격자 | 제목 위 → 2열 × 4행 | 제목 위 → 4 × 2 | 제목 왼쪽 → 4 × 2 | 같음 |
| 설치 | 1칼럼(iOS 면 iPhone 먼저), QR 없음, 3단계 세로 | 2칼럼, QR 없음 | 2칼럼 + QR 112 | 같음 |
| FAQ | 좌우 20, summary 54 | 680 가운데 | 880 | 880 |
| 아웃트로 | 돔 200vw · 꼭대기 10svh · 버튼 세로 · 아잉 clamp(170, 24svh, 220) | r = min(48vw, 52svh) | r = min(30vw, 46svh) | 414 |
| 문서 높이(추정) | ≈ 12,900 | ≈ 11,800 | ≈ 9,300 | 9,660 |

- 중단점 문자열은 `lib/hooks.ts` `MQ_DESK / MQ_TAB / MQ_PHONE` 와 같다(낮은 데스크톱 높이 < 640 은 tab 배치).
- 1600 넘는 화면: `--frame` 1600 가운데, 바깥은 bg-0. H1·돔 상한은 clamp 가 막는다.
- 가로 넘침 0(돔·라디얼은 `overflow: clip` 안), 터치 대상 ≥ 44px.

---

## 5. 성능 예산 — 바이트로 증명

예산(brief §5.1): 첫 화면 ≤ 400KB(크롬, Fast 4G) · 전체 ≤ 4.5MB · 모바일 LCP ≤ 2.5s · CLS ≤ 0.05. 아래 바이트는 **실측**(지금 `public/assets` 파일 크기, 신규 포스터는 내 폴더에서 같은 레시피로 인코딩한 값), "≈" 만 추정.

### 5.1 첫 화면(load 까지, 크롬)

| 항목 | 바이트 | 근거 |
|---|---|---|
| HTML(gzip, 전 절 SSR + FAQ JSON-LD) | ≈ 30KB | 추정 |
| CSS | ≈ 14KB | 추정(v1 133줄 + v2 레시피) |
| JS(Next 16 런타임 + React 19 + 클라이언트 섬: SiteNav·AingStage·Moments·RevealOnce·CopyButton·FaqHash) | ≈ 150KB | 추정 — v1 의 스토어·motion 이 빠졌다(TD §7) |
| `pretendard-500-sub.woff2`(preload) | ≈ 36KB | 실측 34,508B(496자) |
| `pretendard-600-sub.woff2` | ≈ 36KB | 실측 34,468B |
| `jbm-400-ascii.woff2` | 4,440 | 실측 |
| `char/aing-rest-poster.webp`(fetchpriority high) | 17,974 | 실측(신규) |
| `brand/icon-64.webp` | 1,434 | 실측 |
| `brand/appstore-badge-ko-black.svg` | 9,260 | 실측 |
| **합계** | **≈ 299KB** | 예산 400KB, 여유 ≈ 100KB |

### 5.2 load 뒤 히어로 아잉(`afterLoadIdle`, 히어로 ≥ 50% 보일 때)

| 항목 | 크롬(webm) | 사파리(mov) | 폰 크롬 |
|---|---|---|---|
| `aing-commute-start` | 151,047 | 125,839 | 151,047 |
| `ui/bubble-commute-start.webp` | 5,958 | 5,958 | 5,958 |
| `aing-idle`(phone: `-15`) | 808,263 | 817,960 | 536,078 |
| **합계** | **965,268** | 949,757 | 693,083 |

Fast 4G(9Mbps ≈ 1.1MB/s)에서 commute-start 0.14s → 재생 1.5s 동안 idle 0.72s 에 도착 → 층 교체에 기다림이 없다. 늦으면 §3.1-8(마지막 프레임 유지 → `canplay`).

### 5.3 근접 로딩 순서
1. 첫 페인트: 내비·H1·리드·버튼·배지·rest 포스터·글꼴(500 preload).
2. load + idle: 히어로 아잉(5.2).
3. `#moments` 가 100svh 안: milestone(331,045) + `menubar-0100`(3,408). 01 활성 → poked(328,060) + 말풍선(7,854). 02 활성 → ultra(667,105) + 포스터(34,592) + 말풍선(14,936). 소계 **1,387,000B**(사파리 1,335,488).
4. 기능 행마다 `rootMargin 600px`: ① 51,136 · ② 45,382 · ③ 91,752 · ④ 48,848 · ⑤ 77,182 · ⑥ 49,700 = **364,000B**(아잉 스틸은 ① rest 재사용 0B, ③ 8,558, ④ 8,620).
5. 설치: QR 3,257(desk). 아웃트로 100svh 안: commute-end 101,842 + 말풍선 4,988 = 106,830(idle 재사용 0B).
6. 이미지는 `RenderImage`(`<img loading="lazy" decoding="async">` + 명시 width/height), `next/image` 금지(DECISIONS §1).

### 5.4 페이지 전체

| | 크롬 desk | 사파리 desk | 폰 크롬 | 감속 모션 |
|---|---|---|---|---|
| 첫 화면 | 299,100 | 299,100 | 299,100 | 299,100 |
| 히어로 아잉 | 965,268 | 949,757 | 693,083 | 5,958(말풍선만) |
| 트립틱 | 1,387,000 | 1,335,488 | 1,387,000 | 26,614 + 34,592 + 22,790(포스터·말풍선) |
| 기능 행 | 364,000 | 364,000 | 364,000 | 364,000 |
| 설치 · 아웃트로 | 110,087 | 91,729 | 106,830 | 4,988 |
| **합계** | **≈ 3.13MB** | ≈ 3.04MB | ≈ 2.85MB | ≈ 0.76MB |

캐릭터 영상이 크롬 desk 전체의 76%(2,387,362B)다. 그래도 예산 4.5MB 에 1.37MB 가 남는다. idle 808KB 한 파일을 무대 셋(히어로·트립틱 01/02 뒤·아웃트로)이 함께 써서 가능한 숫자다(§3.1-7).

### 5.5 예산 지렛대(넘칠 때 — 전부 내 폴더에서 같은 프레임으로 재인코딩한 실측)

| 지렛대 | 실측 | idle 대비 | 판단 |
|---|---|---|---|
| idle crf 46 → 50(654×790·30fps) | 664,036B | −144,227 | 1순위 — 화질 육안 확인 후 |
| idle 상자 ×0.5 → ×0.4(524×632) crf 46 | 688,424B | −119,839 | desk 표시 폭 261 × DPR2 = 522 라 손실 거의 없음 |
| desk 도 15fps(지금 `-15` 파일) | 536,078B | −272,185 | 깜빡임이 덜컥거린다 — 최후 |
| 15fps × 0.4 crf 44 | 474,402B | −333,861 | phone 전용 후보 |
| 몸만 크롭(552×524) crf 46 | 803,339B | −4,924 | **효과 없음** — 투명 여백은 거의 공짜다. 하지 말 것 |
| 트립틱 01·02 끝나면 idle 대신 마지막 프레임 유지 | 0B | — | 바이트는 같고(캐시) 디코딩만 준다 |

### 5.6 LCP · CLS · 장기 작업
- **LCP**: desk = H1 텍스트(SSR, 500 서브셋 preload, `display: swap`, next/font 대체 글꼴 보정) → FCP 와 같음. phone = 히어로 rest 포스터(219×265 상자 > H1 2줄 ≈ 26k px²) → `<link rel=preload as=image fetchpriority=high>` 17,974B. 둘 다 Fast 4G ≈ 1.2s 추정.
- **CLS ≤ 0.05**: 아잉 상자 = `width` + `aspect-ratio: 654/790` 고정, 렌더 전부 width/height 명시, 내비 고정 높이, 플랫폼 CTA 는 `<head>` 인라인 스크립트로 첫 페인트 전 결정, 릴리스 크기 "30.0MB" 는 서버 렌더(ISR 1시간).
- **장기 작업 0**: 히어로 스크럽 = CSS scroll-driven, 트립틱·행 = IntersectionObserver, rAF 루프 없음. 동시 디코딩 영상 ≤ 2(stage-bus).

---

## 6. 컴포넌트 목록과 에셋 레시피

### 6.1 새 컴포넌트(`components/v2/` · 이름에 `Spine` 금지)

| 이름 | 종류 | 역할 | props 초안 |
|---|---|---|---|
| `SiteNav` | client | 투명 → 바탕 전환, CTA 테두리↔채움 | `{ ctaAriaLabel: string }` |
| `Dome` | server | §2.2-① 돔 + 웅덩이 | `{ variant: 'hero' \| 'closing' }` |
| `AingStage` | client | §3.1 무대(포스터·idle·once 층, 재생 규율) | `{ id: 'hero'\|'m01'\|'m02'\|'m03'\|'closing'; width: string; once: 'aing-commute-start'\|'aing-commute-end'\|'aing-poked'\|'aing-milestone'\|'aing-ultra'; after: 'idle'\|'hold'; trigger: 'load-visible'\|'active'\|'first-visible'; active?: boolean; minRatio?: number; bubble?: BubbleKey; still: AssetKey; stillBubble?: boolean; priority?: boolean; prefetch?: boolean; className?: string }` |
| `Hero` | server | 히어로 조립 | `{ release: ReleaseInfo }` |
| `Moments` | client | 트립틱: 활성 카드(IO 띠), 스티키 무대, 감속·폭별 폴백 | `{ cards: MomentSpec[] }` |
| `MomentCard` | server | 카드 마크업 | `MomentSpec = { n: 1\|2\|3; figure: string; caption: string; body: string; chip?: AssetKey; once: …; bubble?: BubbleKey; still: AssetKey }` |
| `Rail` | server | 레일 선 + 노드 + 조각 | `{ from: string; to: string }`(앵커 id) · `Node { lit: boolean }` |
| `FeatureRow` | server | 행 글 + 무대 | `{ id: string; label: string; title: string[]; body: string; aux?: string; stage: RowStageSpec }` |
| `RowStage` | server | 타일·연결선(SVG pathLength=1)·R·S·점 격자 | `RowStageSpec = { primary: { asset: AssetKey; w: number; h: number; at: [number, number]; alt: string; swapTo?: AssetKey } \| { phone: 'ios/now'; screenW: 210; at: [number, number] }; secondary: { kind: 'aing'; still: AssetKey; seq?: SequenceName; boxW: 132; at: [number, number]; bubble: BubbleKey } \| { kind: 'label' \| 'widget'; asset: AssetKey; w: number; h: number; at: [number, number]; alt?: string; first?: boolean } \| { kind: 'grass'; empty: AssetKey; final: AssetKey; w: number; h: number; at: [number, number] }; wires: { c1: [number, number][]; c2?: [number, number][] } }` |
| `RevealOnce` | client | IO 한 번 → `data-revealed` | `{ as?: 'article'\|'section'\|'div'; rootMargin?: string /* "0px 0px -32% 0px" */; children: ReactNode; className?: string }` |
| `FactsGrid` | server | 숫자 격자 | `{ release: ReleaseInfo }` |
| `Install` | server | 설치 띠 | `{ release: ReleaseInfo }` |
| `Faq` | server | 제목 + details + JSON-LD | — |
| `Closing` | server | 작은 돔 + 카피 + 버튼 + 무대 | `{ release: ReleaseInfo }` |

새 `lib`: `lib/stage-bus.ts`(`useStageTurn(id, ref, minRatio): boolean` — 보이는 비율 최대 무대만 true) · `lib/aing-geometry.ts`(`idleResumeFrame(n)`, `stageBox(name, W)`, `bubbleAt(W)`, `ULTRA_K = 1.45` — `CharacterStage` 103–146행 이식) · `lib/announce.ts`(TD §2.4) · 데이터 `data/moments.ts`·`data/features.ts`(카피 = `check-glyphs` 가 보는 `data/`).

### 6.2 재사용(TD §2 서명 기준)과 바꿀 것

| 파일 | 그대로 / 바꿀 것 |
|---|---|
| `AlphaVideo`·`SheetPlayer`·`SpritePlayer` | 그대로. `AingStage` 는 `AlphaVideo`(핸들 `play/pause/seekToFrame`)를 `sequenceMeta()`·`videoVariant(meta, lowFps)`·`preloadSequence()` 와 함께 쓴다 |
| `Bubble` | `onClick`·`ariaLabel` 삭제(TD) · `decorative?: boolean`(기본 true = `aria-hidden`, 행에서는 false → `alt = bubbleText(id)`) 추가 |
| `RenderImage`·`MacWindowShell`(R 의 반지름·그림자)·`PhoneShell` | 그대로 |
| `DownloadCTA` | `Placement` 그대로("nav"·"hero"·"install"·"closing" — v2 자리 이름과 같다), `demo` 제거·`announce`(TD) |
| `CommandBox`·`CopyButton`·`LiveAnnouncer` | `lib/announce.ts` 로(TD) |
| `AppStoreBadge`·`QrCode`·`TextLink`·`VisuallyHidden`·`PlatformScript` | 그대로 |
| `Headline` | `font-extrabold` 고정 삭제, `size: 'hero' \| 'h2' \| 'h3' \| 'grid-title'` → `t-*` 클래스가 굵기까지 정한다 |
| `SiteFooter`·`LicensesNav`·`FaqHash`·`useHeroCtaVisible` | 이동 경로(TD §1.2) 그대로. `data/site-links.ts` `NAV_LINKS` → `#features`·`#install`·`#faq` |
| `data/faq-items.ts`·`data/install-copy.ts` | 그대로(install-copy 의 brew 업데이트 문장만 CB:394 명령으로) |
| `lib/grass/grass-geometry.ts` | `SCRUB_*`·`scrubProgress` 삭제, `token.grid` 열 경계로 `clip-path` 12단 계산 함수 하나 추가 |
| `TimerCapsule`·`motion` 의존성 | 쓰지 않는다 → 삭제 후보(PLAN 결정) |

### 6.3 에셋 레시피(`scripts/build-assets.mjs` 추가 · `subset-fonts.mjs` · 삭제)

**신규 포스터·스틸** — char 묶음에 `POSTERS` 표 추가: 원본 PNG 한 장 → `extract(box)` → `resize(×scale)` → `webp({ quality: 82, alphaQuality: 90 })`(지금 idle 포스터와 같은 옵션). 바이트는 내 폴더에서 이 레시피로 실측.

| 출력 | 원본(`/Users/yesung/aing-check-promo/public/assets/` +) | 프레임 | 상자 [x,y,w,h] | 배율 → 픽셀 | 실측 |
|---|---|---|---|---|---|
| `char/aing-rest-poster.webp` | `v3/mac/char/aing/commute_start/0000.png` | 0(= commute_end 0000, 바이트 동일) | HERO [424,544,1308,1580] | 0.5 → 654×790 | 17,974 |
| `char/aing-milestone-poster.webp` | `v3/mac/char/aing/milestone/0048.png` | 48(색종이 성김 — f42 는 63–74KB) | [308,544,1544,1580] | 0.5 → 772×790 | 26,614 |
| `char/still-poked-sm.webp` | `v3/mac/char/aing/poked/0060.png` | 60(착지, 얼굴이 말풍선 자리 밖 — f16 은 말풍선이 얼굴을 덮는다, `mock/trip-1440.png`) | HERO | 0.25 → 328×396 | 8,558 |
| `char/still-ultra-charged.webp` | `v4/char/aing/ultra_charged/0054.png` | 54 | [452,1032,1228,1160] | 0.25 → 308×290 | 8,620 |

- `sequences.json`: `aing-commute-start`·`aing-commute-end`·`aing-poked`·`aing-milestone` 의 `poster` = `char/aing-rest-poster.webp?v=…`, `posterFrame: 0`. `AssetKey` 에 네 키 추가. 검증 목록(③ webp 픽셀)에 네 줄.
- **선택(지렛대)**: `aing-idle` crf 50 판 — 레시피 줄의 `crf: 46 → 50`(실측 664,036B). 화질 확인 전에는 바꾸지 않는다.

**글꼴** — `subset-fonts.mjs`: 원본을 `Pretendard-Medium.woff2`·`Pretendard-SemiBold.woff2` 두 벌로(같은 글자 집합), 출력 `pretendard-{500,600}-sub.{woff2,txt}`. `check-glyphs.mjs` `SUB_TXT` → 두 파일 모두 검사. `--from-spec` 은 `docs/v2/SPEC.md` §3 을 읽게. `app/layout.tsx`: `localFont` 두 번(500 preload true `--font-display`, 600 preload false `--font-display-strong`), `themeColor: "#0C0A14"`.

**쓰지 않는 에셋(삭제 후보 — 파일·레시피 줄·`AssetKey` 를 함께, TD §6)**: 38파일 1,521,023B — `ui/popover-{off,off-1702,newmsg,tick-strip}` · `ui/poke-{list,cooldown,focus-1,focus-2}` · `ui/message-composing` · `ui/league` · `ui/minigame` · `ui/gomoku-board{,-sm}` · `ui/todo-board` · `ui/insights-popover` · `ui/grass-work-{empty,final}` · `ui/token-last` · `ui/header-off-1702` · `ui/menubar-{off,off-lg,0000,0345-newmsg,0642,0642-lg,icon-dot}` · `ui/bubble-update` · `ios/{messages,games,rankings-league,me-records,widget-todos-large,widget-today-small}` · `char/aing-ultra-charged.{webm,mov}` · `char/aing-idle-poster.webp`(rest 포스터로 대체) · `fonts/pretendard-800-sub.{woff2,txt}`. 쓰는 정적 에셋은 23파일 404,455B + 캐릭터 영상 15파일.
- OG 이미지 `app/opengraph-image.png` 는 통합 때 v2 히어로(1440×756, 아잉 도착 뒤)로 다시 찍는다. alt "보라 돔 아래 서 있는 아잉과 아잉체크 헤드라인".

---

## 7. 자기 비평

### 7.1 식상한 기본값 점검(frontend-design 의 "생성된 페이지가 몰리는 5가지" 기준, 0 = 없음 · 1 = 일부 · 2 = 그대로)

| # | 신호 | 점수 | 이 안에서 |
|---|---|---|---|
| 1 | 크림 바탕 + 고대비 세리프 + 테라코타 | 0 | 해당 없음 |
| 2 | 거의 검정 + 밝은 강조색 하나 | 1 | 브리프가 다크+보라를 못 박았다. 대신 보라를 평면 강조색이 아니라 **앱 아이콘 링에서 표본한 빛 한 가족**(4단 + 라벤더 손)으로 쓰고, 바탕은 그 아이콘 바탕 쪽으로 기운 밤(#0C0A14), 돔 안은 더 어둡게 — 레퍼런스 실측(RA §6)을 따른 깊이다 |
| 3 | 헤어라인·각진 모서리·빽빽한 신문 칼럼 | 1 | 10/50/90 격자선과 숫자 칸 헤어라인이 있다. 다만 선마다 정보(칼럼·레일 순서·칸 소속)가 있고, 반지름은 물체별(12·999·10·4), 칼럼은 성기다. FAQ 는 2칼럼 broadsheet 대신 한 칼럼 |
| 4 | SaaS 카드 키트 | 0 | 카드 0개. 렌더는 앱이 그린 창 그대로, 그림자는 창에만, 그라디언트 워시 없음 |
| 5 | 템플릿 크롬 | 1 | 눈썹 칩 1개(대문자 아님) · 버튼 끝 → 없음 · 카운터를 고정폭 대신 tabular 산세리프로 · 히어로 메타의 가운뎃점 사슬을 하나로 줄였다. 남은 것: 설치 메타 "macOS 14 Sonoma 이상 · Apple Silicon·Intel · Apple 공증"(CB:228 원문) |
| | **합계** | **3 / 10** | |

거울 앞에서 뺀 것: 히어로의 말풍선 순환 루프(앱에 없는 상태), 별밭, 히어로 칩, 기능 행마다 다른 타일 그림, 숫자 칸 아이콘, 쉬는 시간 행(게임 렌더 — 숫자 격자 "3종"·"1:1" 로 남겼다).

### 7.2 사용자가 싫어할 위험 3개와 대안

| # | 위험 | 대안(토큰·바이트까지) |
|---|---|---|
| R1 | **아잉이 너무 자주 나와 유치하다**(히어로 1 · 트립틱 3 · 행 스틸 3 · 아웃트로 1 = 8자리) | 축소 A: 행 ①③④ 의 아잉 스틸을 빼고 말풍선만 렌더 옆에 둔다(−17,178B, 행 문법 그대로). 축소 B: 트립틱 01 을 아잉 대신 확대 메뉴바 라벨(`menubar-0100` 232×66 을 1.5배)로 — 반응 영상은 02·03 둘(−331,045B) |
| R2 | **첫 화면이 잠깐 멈췄다가 아잉이 뛴다 → 버벅임으로 보인다**(느린 망에서 도착이 글 읽는 도중에 온다) | 도착 마감: 내비게이션 시작 뒤 2.5s 안에 commute-start 가 `canplay` 가 아니면 도착을 건너뛰고 idle 로 바로(포스터와 같은 자세라 티가 안 난다). 그래도 싫으면 도착 자체를 빼고 idle 만(−151,047B) |
| R3 | **"여전히 너무 어둡다"**(보라가 선과 테두리에만) | 히어로·아웃트로 바탕을 앱 아이콘 바탕 #121328 로 올린다(bg-0 대비 1.08, ink-3 5.87 · ink-2 8.94 · aing 10.25 — 대비 유지 실측), 돔 안쪽 감쇠를 48 → 72px, 트립틱 라디얼 α .34 → .46. 그래도 평평한 보라 면은 만들지 않는다 |

### 7.3 구현 난이도 상위 3개와 축소판

| # | 어려운 것 | 왜 | 축소판 |
|---|---|---|---|
| D1 | `AingStage` 층 교체(idle 프레임 미리 시크·`canplay` 대기·사파리 HEVC 알파·stage-bus 단일 재생) | 프레임 정확 시크가 브라우저마다 다르고(`SEEK_WAIT_MS 300`), 무대 다섯이 재생권을 나눈다 | 반응 뒤 idle 로 잇지 않고 **마지막 프레임 유지**(모든 반응 클립의 끝 자세 = 쉬는 자세). idle 은 히어로·아웃트로 루프에서만. 이음매 문제 0 |
| D2 | 트립틱 스티키 + 가운데 띠 IO + 교체 타이밍을 iOS 사파리(svh·툴바 접힘)·트랙패드 관성에서 | 띠 경계에서 두 카드가 번갈아 활성이 되는 떨림 | 히스테리시스(새 카드가 띠에 120ms 머물러야 활성). 그래도 떨리면 **모든 폭에서 세로 나열**(phone 배치, 카드마다 무대) — 레퍼런스의 고정 오브젝트만 잃는다 |
| D3 | 행 무대 좌표 × `--u` + SVG 연결선이 1024–1600 모든 폭에서 렌더 모서리에 정확히 닿기 | 좌표가 px 표라 배율·글꼴 차이에 민감 | C2 를 빼고 C1(타일 → R)만, S 는 R 의 모서리 기준 CSS 배치(절대 좌표 없음), 연결선은 SVG 대신 L자 `div`(border-top/left + width 전이) |

### 7.4 사용자 결정이 필요한 것(기본값으로 진행)
1. 트립틱 방향 — **기본: 세로 + 고정 오브젝트(레퍼런스 실측)**. 가로는 §3.4.8.
2. 히어로 도착(commute-start 1회) — **기본: 켬**(R2 마감 규칙 포함).
3. 아웃트로 뒤 아잉 — **기본: idle 루프로 남김**(앱은 퇴근 뒤 사라지지만 brief §5.2 의 "꾸벅 1회 → idle" 을 따른다).
