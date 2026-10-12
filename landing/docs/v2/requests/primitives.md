# primitives — 공용 변경 요청 + 인계 메모

작성: primitives, 2026-10-12. ② 스캐폴드의 primitives 몫(PLAN §3.3–§3.5 · SPEC §6.1·§6.2) 완료. 공용 파일 중 **내 소유가 아닌 것**에 대한 요청과, 내 부품을 쓰는 섹션 에이전트가 알아야 할 동작을 적는다.

---

## 1. 요청 — `app/globals.css`(core → 통합이 흡수)

### 1-1. 행 말풍선은 앱 문법으로, 접합점은 올라오지 않게(P2)

- **무엇을**: `.row-item[data-kind="bubble"]` · `[data-kind="junction"]` 의 조립 전/전이 규칙 두 줄씩.
- **왜**: SPEC §S4 4.1 "700– 자식 차례로: 렌더 = 불투명 240 + translate 8→0 / **말풍선 = 앱 문법(120 선형 + .96→1 200)**". 지금 globals 는 `.row-item` 하나라 말풍선도 렌더처럼 8px 올라온다. 접합점(5px 점, R4)이 8px 올라오는 것도 어색하다. 조립 규칙은 @layer 밖(unlayered)이라 Tailwind 유틸리티·클래스로는 덮을 수 없어 primitives 안에서 우회하지 못했다(인라인 스타일은 '조립 전/후' 두 상태를 가를 수 없다).
- **제안 diff**(`@media (prefers-reduced-motion: no-preference)` 블록, 기능 행 규칙 아래):
```css
  /* 말풍선 = 앱 문법(SPEC §S4 4.1) · 접합점은 점이라 올라오지 않는다 */
  .js [data-row]:not([data-on]) .row-item[data-kind="bubble"]   { translate:none; scale:.96; transform-origin:0 100%; }
  .js [data-row]:not([data-on]) .row-item[data-kind="junction"] { translate:none; }
  .js [data-row][data-on]:not([data-instant]) .row-item[data-kind="bubble"] {
    transform-origin:0 100%;
    transition:opacity var(--t-quick) linear var(--at,0ms), scale 200ms var(--ease-out) var(--at,0ms); }
```
  (특이도: 위 셋은 일반 `.row-item` 규칙보다 속성 선택자 하나만큼 높아 순서와 무관하게 이긴다.)

### 1-2. (선택, P2) R5 폰 화면도 440ms 에 내용 페이드

- `PhoneShell` 의 화면 `<img>` 는 `.row-item[data-kind="main"]` 의 **직계 자식이 아니라서** `> img` 규칙(440ms 내용 페이드)이 닿지 않는다. 지금은 폰 셸 전체가 주 렌더 자리처럼(불투명 + scale .96→1) 한 번에 들어온다. 앱 문법상 문제는 없지만 SPEC 4.1 의 '빈 창 → 내용' 두 박자를 폰에도 원하면:
```css
  .js [data-row]:not([data-on]) .row-item[data-item="phone"] [data-phone-shell] img { opacity:0; }
  .js [data-row][data-on]:not([data-instant]) .row-item[data-item="phone"] [data-phone-shell] img { transition:opacity 340ms linear 440ms; }
```

---

## 2. 결정이 필요한 것(통합 · 리드)

| 무엇 | 지금 | 근거 · 대안 |
|---|---|---|
| 내비 CTA 의 phone 폭(비 iOS) | v1 그대로 **'설치'(→ installHref)** 링크 | PLAN §3.4 가 `installHref` 를 계약에 남겼다. SPEC §S0 390 와이어는 "(Mac용 다운로드)"로 그려져 있다. 안드로이드·좁은 창에서 DMG 를 바로 받게 하려면 `DownloadCTA.tsx` 의 nav 분기에서 `phone:hidden`/설치 링크 두 줄을 빼면 된다(통합 판단) |
| `RenderImage eager` | 이제 **loading=eager 만**. `fetchpriority=high` 는 `fetchPriority="high"` 로 따로 | PLAN §3.4 에 `fetchPriority` 가 생겼다. desk LCP 는 H1 글자라 히어로 라벨 등이 포스터 preload 와 우선순위를 다투지 않게 갈랐다 |

---

## 3. 인계 메모(섹션 에이전트용 — 서명은 PLAN §3.4·§3.5 그대로)

### AingClip(`components/ui/AingClip.tsx`) — hero · faq-outro
- 영상은 **load + idle(afterLoadIdle) 뒤에만** 만든다. once(commute-start) 층은 그때 바로 받아 두고, `start` 가 true 이고 재생 가능하면 재생 → `data-arrived`·`data-bubble` + `onArrive()`.
- `start` 는 한 번 true 가 되면 엔진이 래치한다(부모가 false 로 되돌려도 도착·idle 이 되감기지 않는다).
- `deadlineAt`(performance.now() 기준, 히어로 2500)까지 once 가 재생 가능하지 않으면 **start 를 기다리지 않고** once·말풍선을 건너뛴 채 `data-arrived` + `onArrive()` → 곧바로 idle. 히어로는 `onArrive` 가 `start` 전에 오면 빛 한 줄(`.comet[data-run]`)을 시작하지 않으면 된다. once 영상 오류(웹킷 HEVC 실패 등)도 같은 길이다.
- 히어로를 벗어난 뒤에 `start` 를 올려도 된다: once 는 화면 밖에서 한 번 돌고 끝나며(돌아와도 다시 하지 않음), 근무 라벨은 켜진 채, idle 은 `inView` 가 true 일 때만 돈다.
- `inView=false`·탭 숨김 → idle 일시정지, 돌아오면 남은 횟수만. once 는 도중에 멈추지 않는다(1.5s).
- `posterOnly`(감속·Save-Data): 영상 요청 0, 마운트 직후 `data-arrived`·`data-bubble`·`data-stopped`·`data-instant`(해제 없음).
- 루트는 `position:relative; width; aspect-ratio 654/790; pointer-events:none; aria-hidden`. 배치(가운데·아래 여백)는 `className` 으로. 포스터가 `char/aing-rest-poster` 면 eager + fetchpriority high(layout preload 와 같은 URL), 그 밖은 lazy.
- 말풍선·근무 라벨 상자는 `heroLayer()` 를 아잉 상자 % 로 둔다 → SSR 첫 페인트부터 제자리(불투명만 바뀐다). 1440×900(아잉 236px) 실측: 말풍선 153×56 @ 상자(−18, +79) · 근무 라벨 95×43.
- 루트 `data-bubble` 은 boolean, `Bubble` 루트에도 `data-bubble="<id>"` 가 있다(v1 그대로) → 테스트는 `[data-aing][data-bubble]` 처럼 루트로 좁힐 것.

### FeatureRow · RowCanvas · Rail — rows-a · rows-b
- `FeatureRow` 는 client(`"use client"`). 섹션은 server 에서 `<FeatureRow {...R1} />` 로 부른다(데이터는 직렬화 가능한 상수). 타입은 `@/components/features/FeatureRow` 에서 `FeatureRowProps`·`CanvasItem`·`RowCanvasSpec`·`Box` 를 함께 내보낸다.
- 행 루트 `<article id data-row data-on? data-instant? data-reveal-count aria-labelledby="{id}-h">` — H3 id 는 엔진이 `{id}-h` 로 붙인다. 행 최소 높이 desk 560(피치), 라벨·캔버스 윗변 = 행 위 + 40.
- 캔버스 좌표는 576 폭 px. **첫 `main`/`phone` 항목이 주 렌더**(phone 세로 묶음의 첫 줄, 바닥 빛의 왼쪽 끝 기준). 나머지(main 둘째·child·bubble)는 phone 에서 아래 줄 자식(폭 ≤ 150).
- 바닥 빛 가로 위치 = 주 렌더 x 에서 `floor.width` 폭의 가운데(타원은 × 1.1). R1–R5 의 SPEC 값으로 전부 렌더 아래에 맞는다(R5 = 24 + 222/2).
- 창 상자(--surface + --shadow-window + 반경 12)는 불투명 렌더에만 두른다. 알파가 구워진 렌더(`ios/widget-*`·`brand/*`·`ui/menubar-*`·`ui/bubble-*`)는 그대로. `fade` 가 있는 항목은 상자째 마스크(바깥 그림자 대신 안쪽 1px 테두리).
- 타일 팝은 globals 가 360ms 로 고정(데이터의 at 무시). `ringFlash`(R3)는 엔진이 Web Animations 로 120–600 켜짐 → 1000 꺼짐.
- `Rail head` 는 부모(기능 절 `<section>`, position:relative·전폭)의 **아래 48px** 안에 머리 점 + 늘 켜진 토막을 그린다(SPEC §S3 아래 패딩 48).
- 배율 `--k` 는 `tan(atan2(46vw, 576px))`(길이 ÷ 길이 → 수)로 CSS 만으로 낸다(크롬 111+·사파리 15.4+·파이어폭스 108+). 1440 = 1, 1024 = .818.

### Gridlines · Dome · Tile · Wire · FloorLight
- `Gridlines lines="all"` = desk 10·50·90 / tab 왼쪽 하나 / phone 없음, `lines="left"` = desk·tab 왼쪽 / phone 없음(SPEC §4 표). 부모 position:relative.
- `Dome` 은 `.dome`(+`--small`)와 `.dome-pool` 을 형제로 낸다(프래그먼트). 부모(#top·#outro)가 position:relative + `overflow:clip`.

---

## 4. 검증(primitives 자체 — `.scratch/primitives/` 하네스, 측정 3100 은 쓰고 껐다)
landing 사본(심링크 + 내 테스트 페이지) 을 3100 에 띄워 크롬·웹킷으로 실측. 결과 요약:
- AingClip 히어로(1440×900): load 뒤 commute-start 요청 → start 12ms 뒤 도착(`data-arrived`·`data-bubble`) → 1.5s 재생 → idle 이 1.52s(= 45칸) 에서 이어 재생, 말풍선 +5.0s 해제, `playbackRate=16` 로 1.5s 안에 `data-stopped`(마지막 칸에서 정지, 포스터 복귀 없음). 캐시된 재방문도 도착(369ms). phone 은 `aing-idle-15`. 감속 = 영상 요청 0·네 속성 즉시. 마감 0 = once 요청 0·라벨만·idle. 화면 밖 = idle 정지, 돌아오면 이어서. 웹킷 = HEVC 실패 → 포스터·라벨, 콘솔 0.
- AingClip 아웃트로: start 전 영상 0 → 45% 진입 뒤 idle, 벗어나면 정지, 2회 뒤 `data-stopped`.
- FeatureRow(1440): 문턱 전 `data-on` 없음 → 지나자마자 `data-on`, 1.5s 에 `.wire` dashoffset 0, R1 `.swap-to` 2.1s 불투명 1, 캔버스 가운데 50% 에서 그 행만 바닥 빛 on, 왕복 뒤 `data-reveal-count="1"`, 해시 진입 = `data-instant`, 감속 = 처음부터 최종. 상자 교차 0(1440·1024·768·390). 배치: 글 180–605 · 캔버스 720(1440) / 글 128–452 · 캔버스 492, k .818(1024) / 글·캔버스 64(768) / 글·묶음 48–370(390), 가로 넘침 0.
