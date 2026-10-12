# 리뷰 ⑥ — 디자인 렌즈(review-design)

작성 2026-10-12 20:45 KST · review-design(읽기 전용 — 코드 0 글자 수정). 기준: DECISIONS D1–D25 > PLAN §0 ⑥ > SPEC §1·§2·§3·§4·§9. 눈: v1 을 거부한 사용자(brief §0 — "체험 기능은 빼라, 지저분하다", "너무 다크하게만이 아니라 다크와 보라의 조화", 레퍼런스 안무).
먼저 읽음: `docs/v2/integration-report.md`, `.scratch/integration/shots/*`(24장). 그다음 데브 3000 에서 직접 캡처(크롬 1440×900 DSF1 + 확대 DSF2 + 짧은 화면·폰·태블릿). 데브 서버는 재시작하지 않았고 3100 은 띄우지 않았다.

캡처 · 스크립트(`landing/.scratch/review-design/`)
- `shots/` — `hero-t400…t6500`(첫 6.5초 9장) · `y0549` · `y0700-boundary` · `y1197` · `y1548` · `y1845` · `y2100-stage-tail` · `features` · `R1`–`R5`(캔버스 중심 = 화면 50%) · `facts` · `install` · `install-mid` · `faq` · `faq-mid` · `outro` · `bottom` + `report.json`(위치·보라·글로우·큰 물체)
- `detail/` — `comet-00…35`(data-run 직후 1.3초 연속 프레임, `../comet-sheet.png` 접촉 시트) · `hero-bottom-seam` · `poke-slice-left` · `r4-slices-left` · `r1-panel-bottom` · `r3-ranking-badges` · `facts-cells` · `install-h2` · `install-top-horizon` · `faq-open-line` · `fold-{1440x789,1280x720,1280x720-reduced,1024x768,768x1024,390x844}` + `detail.json`
- `cap.mjs` · `detail.mjs` · `audit.mjs` · `click2.mjs` · `lines.mjs` — 재수리 뒤 같은 명령으로 다시 잴 수 있다(`node cap.mjs http://localhost:3000 <outdir>`).

---

## 0. 판정 요약

| 축 | 판정 | 근거(실측) |
|---|---|---|
| (a) 기억에 남을 하나(첫 2초) | **빨강(P1)** | 돔·라벨·H1·아잉·도착 말풍선·근무 라벨은 그대로 보이지만, **빛 한 줄이 라벨에서 출발하는 장면이 보이지 않는다** — §1 P1-1 |
| (b) 화면마다 큰 것 하나 · 글로우 하나 · 움직임 하나 | 초록(경계 P2 2건) | 정착 위치 전부 보이는 `[data-glow=on]` ≤ 1. 히어로→트립틱 549–900 · 트립틱 교체 순간에 이웃 요소가 겹친다(P2-1·P2-2) |
| (c) 보라 면적 V0–V9 | 숫자 초록 · **눈 빨강(P1)** | V0 6.58 · V1 3.67 · V2 0.33 · V3 1.95 · V4 1.40 · V5 1.67 · V6 0.19 · V7 0.12 · V8 0.06 · V9 5.05%(통합 T9 와 ±0.01 일치, R2 1.53 · R4 1.76). **숫자 격자 → 설치 → FAQ 세 화면이 연달아 평평한 네이비** — §1 P1-2 |
| (d) 타입 스케일 · lines · 구도 리듬 | 초록 | H1 87.99/500 · H2 60/600 · H3 44/600 · 캡션 24/600 · 숫자 104/300 · 격자 제목 40/500 · 클로징 64/500 = SPEC §2.4. 헤드라인 렌더 줄 수 = `lines` 수(390·768·1024·1440 전부 어긋남 0, `lines.mjs`). 같은 구도 3연속 없음 |
| (e) 렌더 덧그리기 0 · 크롭 가장자리 · 배지 감사 §9.6 | 덧그리기 초록(필터 0 — 호버는 버튼·링크뿐) · **크롭 가장자리 빨강(P1)** · 배지 초록(콕·토큰·리그 조각 0개, 미니게임 축소 배지만 — P2 주의) | §1 P1-4 · P2-7 |
| (f) 1440×789 · 1280×720 · 390 히어로 | 초록(P2 1) | 말풍선 윗변 − 메타 아랫변 = 17 · 17 · 164px(≥ 16) · H1 78.9 / 72 / 40px(≤ .1·vh) · 가로 넘침 0 · 보라 6.50 / 7.25 / 5.93%. 390·768 의 메타–아잉 사이 빈 칸이 크다(P2-6) |
| (g) 레퍼런스에서 가져오지 않을 것 | 초록 | 3D 코인·지구본(점 지도)·태블릿·로고 띠·사용자 수·커서 합성 0. 본문 영문 소문자 낱말은 명령·파일명(brew·aing·check·dmg·install·yehsung·update·upgrade·cask·zip)뿐, 카테고리 라벨은 한글 |
| (h) 체험 요소(클릭하면 바뀌는 렌더) 0 | 초록 | 링크 밖 렌더 23개 가운데 클릭 → `main.innerHTML` 동일(감속 컨텍스트, `click2.mjs`) · 포커스 대상 = 허용 목록(건너뛰기·내비 3·CTA·배지·QR·brew로 설치·복사 2·summary 10·푸터) · role tab/switch/slider 0 |

**개수: P0 0 · P1 4 · P2 7.**

**잘 된 점(3줄)**
- 히어로가 한 장의 그림으로 읽힌다: 아이콘 링 보라의 돔 · 꼭대기 메뉴바 라벨 · 가운데 H1 · 바닥의 아잉 + 앱 짝(말풍선 + 근무 라벨). v1 의 '여럿이 움직이는 화면'은 사라졌고 789·720·390 에서도 말풍선이 메타를 덮지 않는다.
- 보라가 '면'이 아니라 '빛'이다: 돔 림 · 무대 빛 · 행 바닥 빛 · 노드 · 선 · 타일이 한 가족(#7E5EFA)이고, 렌더(잔디의 보라 칸, 아잉 라벤더)가 그 빛과 같은 온도라 다크와 보라의 조화가 히어로·트립틱·행·아웃트로에서 확실히 산다.
- 체험 0 · 렌더 무가공 · 헤드라인 줄바꿈 정확 — 사용자 첫 요구와 사실 규칙은 깨끗하다.

---

## 1. P1 — SPEC 위반 · 눈에 띄는 어색함

### P1-1. 히어로 빛 한 줄의 '출발'이 보이지 않는다 — 기억에 남을 하나가 반쪽

- **파일**: `app/globals.css:173–175`(`.comet-trail`·`.comet-head`) · `app/globals.css:193–194`(전이 `var(--t-comet) var(--ease-out)`) · `components/hero/comet-path.ts:31`(`RIM_CORE_INSET = 1.5`) · `components/hero/HeroStage.tsx:57`
- **재현**: 크롬 1440×900, 감속 아님, scrollY 0, 새로고침. `.comet[data-run]` 이 붙은 순간부터 1.3초를 40ms 간격으로 찍으면(`detail/comet-*.png`, `comet-sheet.png`) — 0ms: 돔 왼쪽 위 림에 점 하나가 거의 안 보임 → **113ms: 머리가 이미 림 왼쪽 아래(113, 626)** → 353ms: 말풍선 자리 앞(≈560, 706) → 353–1000ms: 머리가 거의 서 있음 → 1000ms 도착.
- **기대**(SPEC §0.1·§1.1·§1.2·§S1 모션 ①): "돔 꼭대기의 메뉴바 라벨(00:00)에서 출발한 빛 한 줄이 돔 안쪽을 돌아 내려오고, 그 끝에서 아잉이 도착" — 라벨 → 아잉을 잇는 '선 → 렌더' 문법이 첫 2초에 읽혀야 한다.
- **실제**: 경로(길이 1,305px) 중 림 위 호 828px(63%)를 `cubic-bezier(.2,.8,.2,1)` 로 **약 180ms** 만에 달리고, 그 구간은 머리(3px `--violet-core`)가 **림의 핵(같은 `--violet-core` 1.5px + 밝은 띠) 바로 위**를 달려 배경과 구분되지 않는다. 눈에는 "왼쪽 아래 림에서 선이 튀어나와 말풍선 앞까지 기어가다 650ms 멈춘 뒤 아잉이 뛴다"로 보인다. 라벨과의 연결(출발점)이 사라져, 빛 한 줄이 '장식 선'처럼 읽힌다.
- **고칠 방법**(기하·12px 이격 단언은 유지):
  ```css
  /* globals.css:174 — 머리를 림 위에서도 보이는 흰 구슬로 */
  .comet-head { fill:none; stroke:#fff; stroke-width:5; stroke-linecap:round; stroke-dasharray:2 100; stroke-dashoffset:2;
    filter:drop-shadow(0 0 3px #fff) drop-shadow(0 0 10px var(--violet-bright)); }
  /* globals.css:193–194 — 호 구간에 시간을 준다(림 63% ≈ 600ms). SPEC §S1 의 ease-out 을 지키려면 CSS 기본 ease(.25,.1,.25,1)로라도 */
  .comet[data-run] .comet-trail { stroke-dashoffset:0;   transition:stroke-dashoffset var(--t-comet) linear; }
  .comet[data-run] .comet-head  { stroke-dashoffset:-98; transition:stroke-dashoffset var(--t-comet) linear; }
  ```
  ```ts
  // comet-path.ts:31 — 핵(1.5px)이 아니라 바로 안쪽 보라 띠(#7E5EFA, 100% − 5px) 위를 달리게.
  // 글자 줄 상자와의 최소 이격은 실측 17.7px → 약 14.2px(≥ 12 단언 유지 — comet-path.test.ts 그대로 초록이어야 함)
  export const RIM_CORE_INSET = 5;
  ```
  고친 뒤 `detail.mjs` 로 0–300ms 프레임에서 머리가 라벨 왼쪽 림 위에 보이는지, T6(빛 ↔ 글자 줄 ≥ 12px) 초록인지 확인. 타이밍은 review-motion 렌즈와 겹치므로 같은 수리에서 함께 본다(easing 을 바꾸면 SPEC §S1 표 수정 — 리드 확인).

### P1-2. 숫자 격자 → 설치 → FAQ 세 화면이 연달아 '평평한 네이비'(사용자 요구 ② 의 눈 판정)

- **파일**: `app/globals.css:162–169`(`.horizon`·`.seam`·`.tick`·`.faq-open-line`) · `components/faq/Faq.tsx:19–31` · `components/facts/Facts.tsx:63,74` · `components/install/Install.tsx:61`
- **재현**: 1440×900, R5 를 지나 아래로. `shots/facts.png`(scrollY 6,217) · `install.png`(6,857) · `faq.png`(7,719) · `faq-mid.png`(8,219 이전 구간).
- **기대**(brief §0 ② "너무 다크하게만이 아니라", SPEC §0.4 ② · §1.3-2 "바탕은 보랏빛 밤 + 보라는 빛으로"): 조용한 절이라도 화면마다 보라 빛의 기척이 하나는 눈높이에 있어야 한다. 리뷰 지시: "숫자가 범위 안이라도 눈으로 평평한 네이비 v1 느낌이 나는 화면이 있으면 P1".
- **실제**: V6 0.19% · V7 0.12% · **V8 0.06%**(하한 0.02% 는 통과). 보라 요소가 ① 격자의 `.seam`·`.horizon` 은 절 윗변 1px 이라 측정 위치(절 위 = 내비 아래)에서 **내비 아래 테두리와 겹쳐 사라지고**, ② FAQ 는 열린 행 1px 선 하나뿐이며 그마저 α .7 → .5 로 희미하다(`detail/faq-open-line.png`). 오른쪽 절반(936–1440)이 비어 있는 FAQ 화면은 v1 의 '네이비 바탕 + 글'과 구별되지 않는다. 행 R5(1.67%) 이후 아웃트로(5.05%)까지 약 2,600px(≈2.9 뷰포트)이 보라 없이 이어진다 — 페이지 끝 30% 가 v1 처럼 보인다.
- **고칠 방법**(글로우를 늘리지 않고 '선·구조'만 — SPEC §1.3-1 '그 밖의 보라는 1–2px 선·작은 점' 안):
  ```css
  /* globals.css:165–169 — 이음매·열린 행 선을 설치 수평선과 같은 '빛나는 선' 레시피로(링 가족 §1.2) */
  .seam { …; box-shadow:0 0 18px 1px rgba(126,94,250,.35); }
  .tick { …; box-shadow:0 0 8px rgba(126,94,250,.55); }
  .faq-open-line { …; background:linear-gradient(90deg, transparent, var(--violet) 12%, var(--violet-bright) 35%, var(--violet) 70%, transparent);
    box-shadow:0 0 14px 1px rgba(126,94,250,.40); }
  details[name="faq"][open] > .disclosure::after { background:var(--violet-bright); }
  ```
  ```tsx
  // Faq.tsx:19 · Facts.tsx:57 — 10% 구조선을 조용한 절에도 이어 아웃트로 돔까지 끌고 간다(스파인의 연장, 보라 α .28)
  // globals 에 .gridlines--spine { background:linear-gradient(rgba(126,94,250,.28),rgba(126,94,250,.28)) calc(50% - var(--shell)*.40) 0 / 1px 100% no-repeat; }
  <section id="faq" className="relative …"><div aria-hidden="true" className="gridlines gridlines--spine hidden desk:block" /> …   // tab·phone 은 선 없음(D19-5)
  ```
  목표: 세 위치 모두 보라 ≥ 0.3%(실측)이고 측정 위치에서 내비 테두리 밖에 보라 요소가 하나 이상 보일 것. SPEC §2.9 V6–V8 하한을 0.02% → 0.3% 로 올리는 것은 **리드 결정**(DECISIONS 추가) — 수리는 위 CSS 로 먼저 맞추고 T9 숫자를 보고한다. 조용한 절에 글로우(라디얼)를 새로 두는 안은 권하지 않는다(화면당 하나 원칙은 지켜도 '빛 = 물체' 문법이 흐려진다).

### P1-3. 히어로 → 트립틱 경계에서 돔이 헤어라인 없이 직사각형으로 잘린다

- **파일**: `components/hero/Hero.tsx:29`(`section#top … overflow-clip`) · `app/globals.css:115–124`(`.dome` 안 `--dome-in #06040C`)
- **재현**: 1440×900 에서 scrollY 300–900 사이 아무 곳(`shots/y0549.png` y=351, `detail/hero-bottom-seam.png`). 스크롤할 때마다 모든 사용자가 지나는 자리.
- **기대**(SPEC §S1 와이어 "첫 화면 끝 = 히어로 끝(돔은 여기서 잘린다)" + RA §3.2 "돔은 로고 띠 **윗선**에서 잘린다"): 레퍼런스의 자르기는 헤어라인이 받쳐 '의도된 프레임'으로 읽힌다. 아웃트로 돔도 푸터 윗선(`--line`)에서 잘려 자연스럽다.
- **실제**: 받침선 없이 돔 안(#06040C)과 트립틱 바탕(#0C0A14)이 수평 직선으로 맞닿고, 양쪽 림 끝(가장 밝은 보라)이 같은 높이에서 뚝 끊긴다. 패럴랙스로 돔이 가라앉을수록 더 드러난다. 같은 자리에서 트립틱의 10% 세로선이 시작돼 '어긋난 판'처럼 보인다.
- **고칠 방법**: 아웃트로·레퍼런스와 같은 받침선 한 줄.
  ```tsx
  // Hero.tsx:29
  className="relative flex min-h-svh flex-col items-center overflow-clip border-b border-line"
  ```
  (문서 높이 +1px — T5 9,300–9,900 안.) 더 부드럽게 하려면 돔만 감싼 층(`Dome` 의 바깥 상자)에 `mask-image: linear-gradient(#000 calc(100% - 120px), transparent)` 를 걸 수 있으나 웅덩이도 흐려지므로 받침선을 1순위로 권한다.

### P1-4. 슬라이스 크롭 가장자리 — 토큰판 '◀' 조각 노출 · 첫 글자 잘림 · 잘린 쪽에도 둥근 창 모서리

- **파일**: `components/features/rows-b.data.ts:16,38,40`(`SLICE_FADE = { left: 16 }`) · `components/moments/MomentObject.tsx:80` · `components/features/RowCanvas.tsx:69–80`(`windowStyle` — 페이드가 있어도 `borderRadius: var(--r-window)` 네 모서리) · `components/moments/moments.css:43`(`.moment-slice` 네 모서리 반경) · `components/ui/RenderImage.tsx:31–43`(`fadeMask`)
- **재현**: R4 캔버스 중심 = 화면 50%(scrollY 4,951) → `detail/r4-slices-left.png`(DSF2). 트립틱 02 머묾(scrollY 1,548) → `detail/poke-slice-left.png`.
- **기대**(SPEC §9.2 token-slice "'◀' 단추 조각은 왼쪽 페이드가 가린다" · §1.3-3 "크롭·축소·가장자리 페이드 마스크만" · 리뷰 (e) 크롭 가장자리): 잘린 가장자리는 '화면 밖으로 이어지는' 조각으로 읽혀야 한다.
- **실제**: D20-3 으로 페이드가 28 → 16px 이 되면서 ① 토큰판 머리 왼쪽에 **반원 '◀' 버튼 조각**(≈10px)이 회색 얼룩으로 보이고(SPEC §9.2 와 어긋남), ② 리그 조각의 "각자 목표…"·"파도 커피단"·"종이 공방", 콕 조각 머리의 "…찌르기"가 **첫 획이 잘린 글자**(콕 조각은 "ㅊ르기"로 읽힘)로 남는다, ③ 세 조각 모두 **잘린 왼쪽에도 12px 둥근 모서리 + 안쪽 1px 테두리**가 있어 "왼쪽 내용이 빠진 깨진 창"으로 보인다.
- **고칠 방법**:
  ```ts
  // RowCanvas.tsx:72–78 — 왼쪽 페이드 = 잘린 쪽이므로 그쪽 모서리는 각지게(이어지는 조각으로 읽힘)
  if (mask) return { borderRadius: fade?.left ? "0 var(--r-window) var(--r-window) 0" : "var(--r-window)", background: "var(--surface)",
                     boxShadow: "inset 0 0 0 1px rgba(255,255,255,.07)", ...mask };
  ```
  ```css
  /* moments.css:43 */
  .moment-slice { …; border-radius: 0 var(--r-window) var(--r-window) 0; }
  ```
  ```ts
  // RenderImage.tsx fadeMask — 머리 띠만 왼쪽 페이드를 길게 하는 'notch' 옵션(첫 음절 규칙 D20-3 은 본문 행에 그대로)
  // fade = { left: 16, notch: { w: 44, h: 52 } } → 세 층: [16px 페이드] intersect ([머리 띠 w px 페이드 · top/100% h] add [나머지 불투명 · bottom/100% calc(100% − h)])
  maskImage: `linear-gradient(to right, transparent, #000 16px), linear-gradient(to right, transparent 0 ${w - 16}px, #000 ${w}px), linear-gradient(#000, #000)`,
  maskSize: `100% 100%, 100% ${h}px, 100% calc(100% - ${h}px)`, maskPosition: `0 0, 0 0, 0 100%`, maskRepeat: 'no-repeat',
  maskComposite: 'intersect, add', WebkitMaskComposite: 'source-in, source-over',
  ```
  token-slice 는 `notch: { w: 44, h: 52 }`(◀ 가림), poke-slice 는 `notch: { w: 48, h: 62 }`(머리 "ㅊ" 가림 — 1.3pt 표시 기준). 리그 조각은 각진 모서리만으로 '이어지는 카드'로 읽히는지 1440 DSF2 로 다시 본다. 수리 뒤 배지 감사(§9.6)는 그대로 0.

---

## 2. P2 — 다듬기

### P2-1. 트립틱 교체 순간 이전 카드 카운터가 새 숫자 위에 붙는다 · 머묾에 다음 숫자가 통째로 보인다
- **파일**: `components/moments/moments.css:103–106`(`.js .moment-counter { top: 58svh }`) · `components/moments/Moments.tsx:25`
- **재현**: 1440×900 scrollY 1,197(0→1 문턱) → `shots/y1197.png`: "[ 01 / 03 ]"(y 231)이 "콕."(y 500) 바로 위에 있어 **"[01/03] 콕."** 으로 읽힌다. 1,845 도 "[ 02 / 03 ] 12주". 머묾 1,548(`y1548.png`)에는 다음 카드 "12주" 104px 가 y 800–890 에 통째로 보인다(SPEC §S2 와이어의 "96svh 에 머리만"은 자기 기하 16svh + 72svh = 88svh 와 모순 — 구현은 기하를 따랐다).
- **기대**: 카운터는 진짜 순서 표시(brief §3) — 지금 보이는 숫자의 번호여야 한다. 한 화면 큰 것 하나(§1.3-1).
- **고칠 방법**: 카운터를 숫자 위로 올린다 — `.js .moment-counter { top: calc(16svh - 32px); }`(목록 모드의 grid-area 순서 "counter head obj body" 와도 같아진다). 그러면 문턱 순간 이전 카드 카운터는 화면 밖(−185px)에 있다. 다음 숫자 노출은 카드 피치 72 → 78svh(+162px, SPEC §3.0 ① 행 560 → 520 으로 상쇄) 또는 SPEC 와이어 문구를 88svh 로 고치는 것 중 리드 선택.

### P2-2. 히어로 → 트립틱 이음매(scrollY 549–900)에 '00:00' 네 개 · 빛 두 개
- **파일**: `app/globals.css:226`(`@keyframes dome-set … to { opacity:.35 }`) · `lib/moments.ts`(engaged 문턱 .30)
- **재현**: `shots/y0549.png`·`y0700-boundary.png` — 히어로 아잉(근무 라벨 00:00) + 큰 숫자 00:00 + 무대 라벨 00:00 + 헤더 카드 00:00, 700 에서는 양옆 돔 림(불투명 ≈ .5)과 무대 빛이 함께 보인다(테스트 기준은 히어로 .22 < .35 라 1개로 셈).
- **기대**: §1.3-1 화면당 큰 것 하나·글로우 하나(눈 기준). 사실 충돌은 없음(전부 00:00).
- **고칠 방법**: 돔 패럴랙스 끝 불투명 `.35 → .15`(SPEC §S1 모션 ② 값 — 리드 확인)로 림이 무대 빛보다 먼저 물러나게. 더 필요하면 히어로 근무 라벨이 화면 위 1/4 밖으로 나갈 때(히어로 보이는 비율 < .3) 무대 오브젝트 1 의 SSR 불투명을 .6 으로 시작(engaged 때 1) — 이건 움직임 추가라 review-motion 과 함께 판단.

### P2-3. R1 메시지 패널 아래 24px 페이드가 마지막 말풍선과 '1' 을 덮는다
- **파일**: `scripts/build-assets.mjs:141–142`(crop `top 390 · height 900`) · `components/features/rows-a.data.ts:31`(`fade: { bottom: 24 }`)
- **재현**: R1 중심(scrollY 3,275) → `detail/r1-panel-bottom.png`: "좋아요! 배포하고 1층에서요"가 반쯤 흐려진 채 잘려 있고, R1 의 유일한 숫자 움직임인 "1"(원본 y≈1,232)이 페이드 띠(원본 1,230–1,290) 안에 있다.
- **기대**: §S4 R1 "내 말 옆 '1' 이 사라진다"가 또렷하게(D19-2 의 취지).
- **고칠 방법**: 원본 대화 영역 아래 끝(y 1,305)까지 crop 을 늘려 자연스러운 상자 끝에서 자른다 — `{ left: 36, top: 390, width: 954, height: 922 }`(두 판 모두) → 표시 382×369, `rows-a.data.ts` 주 렌더 상자 `[0, 48, 382, 369]` · `fade` 삭제(또는 bottom 8) · 바닥 빛 `top 368 → 377`. 입력창("메시지를 입력하세요")은 1,330 부터라 들어오지 않는다(원본 확인 `msg-src-bottom.png`).

### P2-4. 설치 절 세로 격자선이 업데이트 줄 바로 위에서 뚝 끊긴다
- **파일**: `components/install/Install.tsx:49,63–64,158–170`
- **재현**: `shots/install-mid.png` y 428 — 10/50/90 세 선이 같은 높이에서 끝나고 그 아래 업데이트 줄은 격자 밖에 걸린다.
- **고칠 방법**: `Gridlines` 는 className 을 받지 않으므로(공용 프리미티브 서명 유지) Install 쪽 래퍼로 아래 96px 를 흐리게 — `Install.tsx:64` 를 `<div aria-hidden="true" className="absolute inset-0 [mask-image:linear-gradient(#000_calc(100%-96px),transparent)]"><Gridlines lines="all" /></div>` 로. 또는 업데이트 줄(`:158–170`)을 TOP 상자 안으로 옮겨 선이 그 아래 패딩까지 내려오게.

### P2-5. R5 바닥 빛이 숫자 격자 이음매(.seam)를 넘어 다음 절로 번진다
- **파일**: `components/features/rows-b.data.ts:72`(`floor: { width: 540, top: 430 }`) · `components/features/FeatureRow.tsx:49`(`overflow-x-clip` — 세로는 열려 있음)
- **재현**: R5 중심(scrollY 5,545) → `shots/R5.png` y 650–800: 타원 아래 절반이 y 736 의 `.seam` 을 가로질러 숫자 격자 위로 내려간다(글로우 위를 보라 선이 관통).
- **고칠 방법**: R5 만 `top 430 → 398`(타원 아래 끝 = 행 아래 끝) 후 V5 ≥ 0.8% 재측정, 모자라면 D20-2 의 행별 `--floor-alpha: .60`.

### P2-6. 390·768 히어로에서 메타와 아잉 사이 빈 칸이 크다
- **파일**: `components/hero/Hero.tsx:75`(유연 여백 `flex-1`) · `:29`(`min-h-svh`)
- **재현**: `detail/fold-390x844.png` 메타 아래 472 → 말풍선 636(164px 빈 어둠, 돔은 위쪽 얕은 호뿐) · `fold-768x1024.png` 520 → 800(≈280px).
- **기대**: §1.3-1 큰 것 하나 — 돔 안 물체(아잉)가 글 블록과 한 덩어리로 읽힐 것(desk 1440×900 은 60px 대).
- **고칠 방법**(리드 판단 — 폰·탭 히어로가 100svh 보다 짧아진다): `<div aria-hidden className="min-h-0 flex-1 phone:max-h-[72px] tab:max-h-[120px]" />` + 절 `desk:min-h-svh phone:min-h-0 tab:min-h-0`. T5 의 390 말풍선 규칙(≥ 16)은 음수 윗여백이 그대로 지킨다.

### P2-7. 미니게임 오늘 순위의 '서울/부산' 배지가 레티나에서 읽힌다(SPEC §9.6 허용 — 리드 판단, 기본 유지)
- **파일**: `components/features/rows-a.data.ts:92`(`ui/minigame` .78pt)
- **재현**: R3 중심(scrollY 4,431) DSF2 → `detail/r3-ranking-badges.png`: 아바타 8개 중 7개 아래 "서울"·"부산" 글자가 또렷하다(1x 에서는 ≈8px).
- **판정**: §9.6 "축소 표시 허용"이고 CB:293 "크게 보이지 않는 크롭"에 맞아 결함은 아니다. 다만 사용자 대부분이 레티나 맥이고 '서울·부산'은 쓰지 않는 말(§1.4)이라, 다른 조각들처럼 순위 목록 아바타 열을 피하는 크롭(게임 판 + 순위 오른쪽 점수 열)을 후속 후보로 남긴다.

---

## 3. 화면별 표(1440×900 · 크롬 · 데브 3000 · 각 위치 1.5s(행 2.6s) 대기 뒤)

| 위치 | scrollY | 보라 %(범위) | 보이는 글로우 | 큰 것 | 움직임 | 판정 |
|---|---|---|---|---|---|---|
| 히어로(도착 + 2.5s) | 0 | 6.58(3–12) | 돔 | 돔 + 아잉 | 도착 1회 → idle | 초록 · 빛 한 줄 P1-1 |
| 히어로→트립틱 | 549 | 1.63 | 돔(히어로 .39) | 히어로 아잉 + 카드 01 | — | P2-2 |
| 이음매 | 700 | 5.19 | 무대(+ 림 눈에 보임) | 같음 | 점등 | P2-2 |
| 트립틱 0→1 문턱 | 1,197 | 3.66 | 무대 | 콕 조각 | 교체 | P2-1 |
| 트립틱 02 머묾(V1) | 1,548 | 3.67(2–8) | 무대 | 콕 조각(+ 다음 숫자) | 점등 | 초록 · P1-4 · P2-1 |
| 트립틱 1→2 문턱 | 1,845 | 2.78 | 무대(점등 중) | 잔디 | 계단 점등 | 초록 |
| 기능 절 제목(V2) | 3,032 | 0.33(.02–3) | 없음 | H2 | — | 초록 |
| R1(V3) | 3,275 | 1.95(.8–6) | R1 바닥 빛 | 메시지 패널 | 조립 · 1 사라짐 | 초록 · P2-3 |
| R2 | 3,836 | 1.53 | R2 | 캐릭터 패널 | 조립 | 초록 |
| R3(V4) | 4,431 | 1.40 | R3 | 미니게임 창 | 조립 · 테두리 점멸 | 초록 · P2-7 |
| R4 | 4,951 | 1.76 | R4 | 카드 둘 | 조립 | P1-4 |
| R5(V5) | 5,545 | 1.67 | R5 | 폰 | 조립 | 초록 · P2-5 |
| 숫자 격자(V6) | 6,217 | 0.19 | 없음 | 4×2 | — | **P1-2** |
| 설치(V7) | 6,857 | 0.12 | 없음 | 두 열 | — | **P1-2** · P2-4 |
| FAQ(V8) | 7,719 | 0.06 | 없음 | 목록 | — | **P1-2** |
| 아웃트로(V9) | 8,901 | 5.05(2–12) | 작은 돔 | 돔 + 아잉 | 페이드 → idle 2회 | 초록 |

짧은 화면 · 폰(도착 뒤 4s): 1440×789 보라 6.50% · 간격 17px · H1 78.9 / 1280×720 7.25% · 17px · 72(아잉 발 23px 접힘 아래 — SPEC 허용) / 1280×720 감속 동일 배치 / 1024×768 8.61% / 768×1024 9.14%(P2-6) / 390×844 5.93% · 164px(P2-6). 가로 넘침 전부 0.
글꼴 실측: 500·600·300n·jbm 로드됨, 800 없음. 콘솔 error 0(이 리뷰의 캡처 실행 기준).

## 4. 범위 밖으로 넘긴 것
- 빛 한 줄 easing·도착 타이밍의 수치 판정 → review-motion(P1-1 의 '보이는가'만 이 렌즈).
- 문장 중복("근무 타이머" 세 번 — 기능 절 제목·격자 제목·푸터) → review-copy.
- WebKit 돔 림 계단(1x)·HEVC 포스터 폴백 → ⑧ 사파리 실기.
