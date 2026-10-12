# requests — rows-b(④ 섹션 · R4 `#f-ranking` · R5 `#f-iphone`)

작성 2026-10-12 · rows-b. 내 파일(`components/features/RowsB.tsx` · `rows-b.data.ts`) 밖은 고치지 않았다. 실측은 데브 3000(크롬 1440×900, dpr 1), 하네스 `landing/.scratch/rows-b/{accept,purple,timeline}.mjs`, 결과 `landing/.scratch/rows-b/report.json`.

---

## 0. (P0 · primitives/통합) 웹킷(사파리)에서 기능 행 다섯 개의 캔버스가 뒤집히고 커진다 — `FeatureRow` 의 `--k`

**무엇**: `components/features/FeatureRow.tsx` `ROOT` 의 `desk:[--k:min(1,tan(atan2(46vw,576px)))]`·`tab:[--k:min(1,tan(atan2(100vw_-_112px,576px)))]` 를 웹킷이 잘못 계산한다. Playwright WebKit 실측(데브 3000, 행 R1·R4·R5 모두 같음):

| 뷰포트 | 크롬 캔버스 `transform` | 웹킷 캔버스 `transform` |
|---|---|---|
| 1440×900 | `matrix(1,0,0,1,…)` | **`matrix(-3.276,0,0,-3.276,…)`** — 180° 뒤집혀 3.3배(캡처 `.scratch/rows-b/r4-1440-webkit.png`·`r5-1440-webkit.png`) |
| 1024×768 | `matrix(.818,…)` | **`matrix(-177.7,…)`** |
| 800×900(tab) | `matrix(1,…)` | **`matrix(-.205,…)`** |

**왜**: 웹킷은 `vw` 처럼 계산 시점에 풀리는 단위가 `atan2()` 안에 있으면 `atan2` 결과(도)를 `tan` 이 라디안으로 읽는다(1440: atan2 = 48.99° → tan(48.99 rad) = −3.28 로 정확히 맞아떨어짐). 글자 상수만 있는 `tan(atan2(662.4px, 576px))` 는 맞게 나온다. `calc()` 로 감싸기·`+ 0deg`·`sin/cos`·`cqw` 는 모두 같은 오답(`.scratch/rows-b/webkit-trig.mjs`). 섹션 쪽(`RowsB`)에서는 article 자신이 `--k` 를 선언하므로 덮을 길이 없어 **로컬 우회 불가**.

**제안 diff**(주입 CSS 로 실페이지 검증 완료 — 웹킷·크롬 모두 1440 = 1 · 1024 = .8178 · tab = 1, 캡처 `.scratch/rows-b/r4-1440-webkit-withfix.png`, 스크립트 `webkit-fix.mjs`):
```diff
 /* app/globals.css — @layer 밖 맨 아래(통합) */
+/* FeatureRow 캔버스 배율: 웹킷은 vw 가 든 tan(atan2()) 를 도/라디안 혼동으로 잘못 낸다(1440 → scale(-3.28)).
+   길이로 등록한 --kw 에 vw 를 담으면 계산값이 px 로 굳은 뒤 atan2 에 들어가 두 엔진이 같아진다 */
+@property --kw { syntax: '<length>'; inherits: true; initial-value: 576px; }
```
```diff
 // components/features/FeatureRow.tsx ROOT
-  "[--k:1] desk:[--k:min(1,tan(atan2(46vw,576px)))] tab:[--k:min(1,tan(atan2(100vw_-_112px,576px)))] " +
+  // tab 은 (폭 − 112)/576 ≥ 656/576 > 1 이라 늘 1 → [--k:1] 그대로. desk 만 --kw(등록된 길이)로 vw 를 px 로 굳힌다
+  "[--k:1] desk:[--kw:46vw] desk:[--k:min(1,tan(atan2(var(--kw),576px)))] " +
```
PLAN T7·T3 의 웹킷 캡처는 행 구간을 보지 않아 이 결함을 못 잡는다 — 통합 수용 때 웹킷 1440 에서 `[data-row-canvas] > div` 의 `transform` 이 `matrix(1, 0, 0, 1, 0, 0)` 인지 한 줄 단언을 더하길 권한다.

---

## 1. (P1 · 리드 결정) 행 보라 하한 1.0%(SPEC §2.9 V3–V5 · DECISIONS D13)는 지금 레시피로 다섯 행 모두 못 넘는다

**무엇**: 행 캔버스 가운데 = 화면 50%(1s+ 대기) 캡처에 SPEC §2.9 HSV 알고리즘(H 245–295 · S ≥ .35 · V ≥ .30)을 그대로 돌린 값. `.floor-light` 중심 α 는 주입 CSS 로만 바꿔 쟀다(파일 수정 없음).

| `.floor-light` 중심 α | R1 f-message | R2 f-character | R3 f-break | **R4 f-ranking** | **R5 f-iphone** |
|---|---|---|---|---|---|
| .34(지금) | 0.525% | 0.423% | 0.400% | 0.533% | 0.179% |
| .40 | 0.632 | 0.442 | 0.429 | 0.690 | 0.207 |
| .46(D13 손잡이 끝) | 0.720 | 0.504 | 0.522 | 0.812 | 0.249 |
| .60(참고) | 0.858 | 0.635 | 0.721 | 1.009 | 0.332 |
| .80(참고) | 0.962 | 0.758 | 0.907 | 1.168 | 0.407 |

**왜**: 바닥 빛 타원(폭 × 1.1 · 높이 120 · `radial-gradient(… α, .12 55%, transparent)`)에서 V ≥ .30 을 넘는 건 α ≥ ≈.25 인 안쪽뿐이라(.34 에서 반지름의 ≈23%) 화면 비율로는 0.1–0.25% 남짓이다. R5 는 SPEC 이 정한 폭(222)이 작아 더 낮다. D13 은 "α 만 .34 → .40 → .46, 다른 곳에 보라를 더하지 않는다"라서 행 파일 안에서 고칠 길이 없다(좌표·폭은 SPEC 고정값 — 행 데이터는 SPEC 표 그대로).

**제안**(셋 중 리드가 고름 — 통합이 SPEC §2.9 표와 T9 단언을 함께 맞춘다):
- (a) **행 하한을 실측에 맞춘다**: V3–V5 하한 1.0% → **0.15%**(상한 6% 그대로). 화면 인상은 캡처 `.scratch/rows-b/r4-1440.png`·`r5-1440.png` 처럼 바닥 빛·노드·선·타일이 보라로 읽힌다(사용자 원문 "다크와 보라의 조화"는 이 정도로 충족된다고 본다 — 판단은 리드).
- (b) 하한을 지키려면 손잡이를 레시피로 넓힌다(D13 개정): 예) `.floor-light` 가운데 정지점 `.12 55%` → `.20 55%` 또는 높이 120 → 160. R5 는 그래도 1% 에 못 미칠 수 있다(위 표 .80 에서도 0.41%).
- (c) V3–V5 를 T9 에서 '참고값'으로 내린다.

---

## 2. (P2 · 통합 판단) 기능 행 구간의 세로 격자 50 · 90% 선을 그리는 주체가 없다

**무엇·왜**: SPEC §4 표 '세로 격자선 1440 = 10/50/90'(RA §0.2-9a: "기능 절·행(10/50/90%)"). 지금 10% 선은 `Rail` 이 행마다 그리지만, 50·90% 선은 `FeatureRow` 엔진에도 섹션 계약(PLAN §4.3·§4.4)에도 없다. R4·R5 만 따로 넣으면 R1–R3 과 어긋나므로 **로컬 우회를 하지 않았다**.

**제안 diff**(통합이 고르면 — 엔진 하나만 고치면 다섯 행이 같아진다):
```diff
 // components/features/FeatureRow.tsx
+import { Gridlines } from "@/components/ui/Gridlines";
 …
     <article … className={ROOT}>
+      <Gridlines />            {/* desk 10·50·90 / tab 10% / phone 없음 — 10% 선은 Rail 토막과 겹친다(같은 x) */}
       <Rail />
```
(겹치는 10% 선이 거슬리면 `Gridlines` 에 `lines="right"`(50·90 만) 변형을 더하는 쪽 — primitives 서명 변경이라 통합 몫.)

---

## 3. (P2 · primitives 요청 1-1 지지) R4 접합점이 8px 올라온다

`.row-item[data-kind="junction"]` 이 일반 `.row-item` 규칙(불투명 0 + `translate 0 8px`)을 받아, 5px 점이 240ms 동안 아래에서 떠오른다. primitives 요청 1-1 의 `.js [data-row]:not([data-on]) .row-item[data-kind="junction"] { translate:none; }` 를 흡수하면 해결된다. 타이밍 자체는 맞다(데이터: 접합점 `at 0` → 두 선 `at 60` 동시, 200ms 그리기로 260 에 끝 — SPEC §S4 R4 '0–260').

---

## 4. (P2 · 리뷰 design/copy 참고) `ui/token-slice`·`ui/league-slice` 의 왼쪽 28px 페이드가 이름 첫 글자를 흐린다

**무엇**: 두 조각 모두 크롭 왼쪽 경계에서 글자가 ≈3 CSS px 안쪽에서 시작한다(`public/assets/ui/{token,league}-slice.webp` 실측). PLAN §4.4 가 정한 `fade.left = 28` 을 그대로 두면 '구름빵'·'새벽'·'Claude' 의 C, '파도 커피단'·'아잉 데모팀'·'종이 공방'의 첫 음절이 흐려진다(확대 캡처 `.scratch/rows-b/zoom-league-fade.png`·`zoom-token-fade.png` — '파'가 '과'처럼 읽힐 만큼 왼쪽 획이 옅다).

**제안**(둘 중 — 나는 계약값 28 을 지켰다):
- (a) SPEC/PLAN 의 R4 페이드를 `left: 28` → `left: 8`(잘린 행 카드 테두리만 녹이고 글자는 살림). 바꾸면 `rows-b.data.ts` 의 `SLICE_FADE` 한 줄과 `.scratch/rows-b/rows-b.test.mjs` 의 기댓값 28 만 고치면 된다.
- (b) assets 가 두 크롭의 x 를 왼쪽으로 넓힌다 — 단 바로 왼쪽이 아바타(배지) 열이라 배지 감사(§9.6)를 다시 해야 한다.

---

## 5. 참고(변경 요청 아님)
- R4 카드 2(`ui/league-slice`)는 `kind: "child"` 로 두었다. 둘째 `main` 으로 두면 globals 의 `.row-item[data-kind="main"] > img` 내용 페이드가 440ms 고정이라 카드 2 자리(387ms)와 거의 같이 떠 '빈 창 → 내용' 두 박자가 무너진다. child 는 387ms 에 불투명 240 + 8px 올라옴(SPEC 4.1 의 자식 문법)이고 페이드 마스크·빈 창 상자는 main 과 같다. phone 폭에서는 첫 main(토큰판)이 주 렌더 줄(≤ 322), 리그는 아래 줄(≤ 150).
- R5 폰 화면은 primitives 요청 1-2 가 흡수되기 전까지 셸과 한 번에 들어온다(앱 문법상 문제 없음).
