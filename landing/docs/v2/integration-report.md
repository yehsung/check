# 통합(⑤) 보고 — 아잉체크 랜딩 v2

작성 2026-10-12 KST · integration. 데브 서버 http://localhost:3000(pid 14129/14130)은 **재시작하지 않았다** — 지금 완성본을 보여 준다. 측정용 3100 은 두 번 띄우고 두 번 다 껐다(`lsof -i :3100` 비어 있음).
하네스 = `/private/tmp/claude-501/-Users-yesung-check/2e0b98fb-2bf2-4358-9866-db6bfc6f2d59/scratchpad/v2accept/`(저장소 밖). 최종 결과 `out/integration-final/report.json`(데브 3000 + `--build`) · `out/integration-prod2/report.json`(prod 3100).

---

## 1. §7 결과표(T1–T17 전부 초록)

| # | 결과 | 어디서 | 상세(실측) |
|---|---|---|---|
| T1 빌드 건강 | 초록 | landing | typecheck · lint · test:unit(65/65) · check-glyphs · `next build` 각각 exit 0 |
| T2 서버 | 초록 | 데브 | `/api/download` 302 → `aing-check.dmg` · `?file=zip` → `aing-check.zip` · `/api/release` 200, dmg.mb "30.1"(0.3.49) |
| T3 깨끗함 | 초록 | 데브 + prod | 크롬 390·768·1440 + 웹킷 1440, 맨 아래까지: 콘솔 error 0 · pageerror 0 · 실패 요청 0 · 404 0 · 보이는 img naturalWidth > 0 |
| T4 금지어 | 초록 | 데브 + prod | 21개 금지어 0건(본문·숨은 사본·alt·aria-label·title·description·og·JSON-LD) |
| T5 모양 | 초록 | 데브 | scrollWidth === innerWidth: 크롬 390·768·1440 + **웹킷 390·768·1024·1440**(D23-2 로 추가) · 문서 높이 **9,849** · 섹션 id 순서 12개 · 눈썹 칩 1 · popover 0 · 1440×789·1280×720 말풍선 − 메타 **19.7px** · H1 ≤ .1·vh · `<br>` 수 16곳 |
| T6 히어로·아웃트로 | 초록 | 데브 | 3.5s 안 도착 · 빛 한 줄 1회 · 말풍선 +5s 해제 · playbackRate 16 → data-stopped · 빛 한 줄 ↔ 글자 줄 ≥ 12px(1440·1024) · 감속 영상 요청 0 · 390 `.comet` 없음 · 아웃트로 45% 진입 1s 안 불투명 1, 말풍선·근무 라벨 0 · 웹킷 포스터 폴백(HEVC 알파 디코드 불가 — 알려진 환경 한계) |
| T7 트립틱 | 초록 | 데브 | DOM 위치 = SPEC ±24 · 활성 0→1→2, 1,800 에서 2 유지, 1,700 에서 1 · 무대 top 0(크롬·웹킷) · 1.5s 안 점등 · 보이는 글로우 1 · engaged 전 poke·grass 요청 0 · 감속 목록 모드 |
| T8 기능 행 | 초록 | 데브 | 행 5개: 문턱 전 data-on 없음 → 1.5s 안 data-on + dashoffset 0 · 교차 0 · R1 swap 1 · 그 행만 바닥 빛 · 왕복 뒤 count "1" · 감속 최종 · **행 캔버스 배율 크롬·웹킷 1440 = 1 · 1024 = .8178 · 800 = 1**(D20-1 로 추가, 웹킷 1440 캡처 `out/integration-final/shots/T8-webkit-1440-f-ranking.png`) |
| T9 빛 | 초록 | 데브 + prod | V0 6.59% · V1 **3.67%** · V2 0.33% · V3 **1.95%** · V4 **1.40%** · V5 **1.67%** · V6 0.19% · V7 0.12% · V8 0.06% · V9 5.05% · 경계 6곳 글로우 ≤ 1 |
| T10 체험 0 | 초록 | 데브 | Tab 대상 전부 허용 목록 · button = 복사 2개 · role tab/switch/slider 0 · navigator.share 0 · 감속 img 클릭 해시 불변 |
| T11 복사 | 초록 | 데브 | 설치·아웃트로 → `brew install yehsung/check/aing-check` · "복사했어요" → 2.2s 뒤 복귀 · role=status |
| T12 FAQ | 초록 | 데브 | `/#faq-3` → 3번만 open · 10개 · JSON-LD 10문항 · 열린 행 빛 헤어라인 |
| T13 예산 | 초록 | prod 3100 | §2 표 |
| T14 접근성 | 초록 | 데브 | lang=ko · h1 1 · 절마다 h2 · alt = ALT 표 · 건너뛰기 링크 보임 · 포커스 링 3장 · t-small 대비 ≥ 4.5 |
| T15 iOS | 초록 | 데브 | 히어로·아웃트로 다운로드 0 · 배지가 버튼 줄 첫째 · 내비 App Store · 설치 iPhone 열이 위 |
| T16 OG·메타 | 초록 | 파일 + 데브 | 1200×630 재촬영 · `.alt.txt` = `OG_IMAGE.alt` = SPEC §8 문장 · theme-color #0C0A14 · title |
| T17 sticky 조상 | 초록 | 데브 | html·body·main·#moments(크롬·웹킷): overflow visible/clip · transform 류 none · contain·will-change 없음 |

## 2. 예산 실측(prod 3100, `out/integration-prod2/report.json`)

| 항목 | 실측 | 예산 |
|---|---|---|
| 첫 화면(1440 크롬, `load` 까지 — D24-1) | **397,475B(388.2KiB)** | ≤ 400KB |
| 참고: load + 1s(PLAN 원문 — 정보) | 568,192B | — |
| 전체 1440 크롬(맨 아래 + 아웃트로 idle + 3s) | **1,649,191B(1.65MB)** | ≤ 4.5MB |
| 전체 1440 웹킷(sizes 합 근사) | **2,464,464B(2.46MB)** | ≤ 4.5MB |
| 전체 390 크롬 | **1,368,924B(1.37MB)** | ≤ 2.2MB |
| 스로틀 390 LCP | **816ms**(aing-idle-15 영상) | ≤ 2.5s |
| 스로틀 390 CLS | **0** | ≤ 0.05 |
| load 이전 영상 요청 | 0(4개 실행 전부) | 0 |
| 1440×900 문서 높이 | **9,849px** | 9,300–9,900 |

- 첫 화면에는 R1 행 렌더(메시지 패널 둘·말풍선 ≈72KB)가 들어 있다. 헤드리스 크롬은 연결 유형이 'unknown' 이라 지연 로딩 거리가 3,000px 이고 R1 패널(첫 화면 아래 ≈2,670px)이 그 안에 든다. 실제 4G·와이파이(1,250px)에서는 들어오지 않는다(≈325KB). 여유가 2.5KB(10진)뿐이라 리뷰가 볼 것 — §5.
- 히어로 말풍선·근무 라벨 렌더(≈19KB)는 SPEC §5.2-2 대로 `load + idle` 뒤에 받게 고쳤다(§3 AingClip). 이 고침 전에는 406.9KB 로 빨강이었다.

## 3. requests 처리 내역

| 요청 | 처리 | 파일 |
|---|---|---|
| rows-b §0 · **D20-1(P0)** 웹킷 행 캔버스 뒤집힘 | `@property --kw`(globals 맨 아래) + `desk:[--kw:46vw] desk:[--k:…atan2(var(--kw),576px)…]`, tab 은 `[--k:1]`. 초깃값은 D20-1 의 0px 대신 **576px**(desk 밖에서 비어도 배율 1). 웹킷 1440 = 1 · 1024 = .8178 · 800 = 1 실측 | `app/globals.css` · `components/features/FeatureRow.tsx` |
| moments §3 · D23-2 웹킷 768·1024 가로 넘침 | 위 수정으로 해결 + 바닥 빛이 1024 에서 오른쪽 밖으로 나가 크롬·웹킷 1033px 이 되던 것을 행 루트 `overflow-x:clip` 으로(세로는 visible, #moments 조상 아님). phone 바닥 빛은 × .846 으로 ×1.3 을 되돌려 390 안에 | `FeatureRow.tsx` · `RowCanvas.tsx` |
| rows-a §1 · rows-b §1 · **D19-1 · D20-2** 행 보라 하한 | `.floor-light` = 합집합 폭 × 1.3 · 높이 160 · α `var(--floor-alpha, .55)` → .20(55%). 행 데이터 `floor.width` = 합집합(R1 573 · R2 576 · R3 558 · R4 548 · R5 540). `top` +40·행별 α 는 **필요 없었다**(V3 1.95 · V4 1.40 · V5 1.67%). SPEC §2.9 하한 0.8% 로 | `globals.css` · `FloorLight.tsx` · `rows-a.data.ts` · `rows-b.data.ts` |
| moments §1 · **D23-1** V1 0.02% | `.obj-glow` 후보 C(α .40/.20@60% + 웅덩이 .42) → V1 3.67% | `globals.css` |
| rows-a §2 · D19-2 | R1 아래 페이드 40 → 24 | `rows-a.data.ts` |
| rows-b §4 · D20-3 | 조각 왼쪽 페이드 28 → 16(토큰·리그 + 트립틱 콕 조각) | `rows-b.data.ts` · `components/moments/MomentObject.tsx` |
| core §1 · primitives §2 · D19-3 | 내비 CTA 모든 폭 "Mac용 다운로드"(phone '설치' 알약 삭제 — `installHref` 는 서명 호환으로 받기만), outline = `--line-strong` + ink-1 | `components/ui/DownloadCTA.tsx` |
| core §3 · hero §3-8 · D19-4 | 포스터 preload 를 layout 에서 빼고 `page.tsx` 에서 react-dom `preload()`. prod HTML 확인: `/` 에만 `<link rel=preload … aing-rest-poster … fetchPriority=high>`, `/licenses` 에 없음(데브는 RSC 힌트로만 나간다) | `app/layout.tsx` · `app/page.tsx` |
| facts-install §3 · rows-a §3 · D19-5 | tab 세로 격자 없음(Gridlines `all`·`left` 모두 desk 만) | `components/ui/Gridlines.tsx` |
| core §2 · D19-6 | LicensesNav 건너뛰기 링크 — faq-outro 가 이미 고침(확인만) | — |
| primitives §1-1 · rows-b §3 · D19-7 | 행 말풍선 앱 문법(120 선형 + .96→1 200) · 접합점 올라옴 없음 | `globals.css` |
| primitives §1-2(선택) | R5 폰 화면 440ms 내용 페이드 | `globals.css` |
| rows-a §3 · D19-8 | 기능 절 제목 385px 허용 — 문서 높이 9,849 안 | — |
| faq-outro §1·§2 · D20-5(선택) | FAQ 높이 전이·아웃트로 진입 페이드를 globals 로 올리고 섹션 쪽 우회(`HEIGHT_TRANSITION` · `STAGE` 끝 두 줄) 삭제 | `globals.css` · `components/faq/Faq.tsx` · `components/outro/OutroStage.tsx` |
| facts-install §1 · **D21-1** 설치 989px | 팀 3걸음을 iPhone 열 아래 세로로(768 이상 `col-start-2 row-start-2`, Mac 열 `row-span-2`), 업데이트 줄 두 열 아래 전폭, 절 아래 패딩 96. 설치 989 → **861**, 문서 9,977 → **9,849** | `components/install/Install.tsx` |
| facts-install §4 · **D21-2** | check-glyphs 수집기가 `*.test.{ts,tsx,mts,mjs}` 를 건너뜀(subset-fonts 도 같은 수집기) | `scripts/check-glyphs.mjs` |
| facts-install §2 · D21-3 · moments §2 · D23-3 · D22-3 | SPEC §4 표(격자 1280 이상만 왼쪽 제목 · 1024 오브젝트 ×.71 · tab 격자선 없음) · §9.1 배지 48 | `docs/v2/SPEC.md` |
| hero §1 · **D22-1(P1)** 층 교체 깜빡임 | AingClip `shown` 상태: 들어오는 영상의 `requestVideoFrameCallback`(없으면 playing + 2 rAF, 상한 300ms) 뒤에만 나가는 층을 내림, once 층 언마운트도 idle 이 그린 뒤. 실측(크롬, `.scratch/integration/gap2.mjs`): 나가는 층 숨김 − 들어오는 첫 프레임 = 포스터→once **+1.7–2.2ms** · once→idle **+1.5–2.3ms** · 아웃트로 포스터→idle **+1.3–1.8ms**(전부 양수 = 틈 0). hero 의 `gap.mjs` 도 −1ms(첫 프레임 뒤 숨김) | `components/ui/AingClip.tsx` |
| hero §2 · D22-2 | 12px 정본 — 변경 없음(T6 초록) | — |
| assets §3 · SPEC §9.5 | `npm run subset`(소스 모드) → 500·600 = 447자(한글 342) 31,060 · 31,004B · 300-num 14자 2,020B. layout 이 800 을 가리키지 않음 확인 뒤 `public/fonts/pretendard-800-sub.{woff2,txt}` 삭제, 스크립트 주석 정리. check-glyphs 0 | `public/fonts/*` · `scripts/subset-fonts.mjs` · `scripts/build-assets.mjs` |
| rows-b §2(통합 판단) | 기능 행에도 세로 격자 10/50/90(desk) — SPEC §4 '1440 = 10/50/90' | `FeatureRow.tsx` |
| (예산) SPEC §5.2-2 | 히어로 말풍선·근무 라벨 렌더를 `load + idle` 뒤에 받게(감속·Save-Data 는 마운트 직후). 상자는 SSR 부터 제자리(CLS 0), JS 없음은 `<noscript>` 가 최종 상태 | `AingClip.tsx` |
| D8 · D24-3 OG | 재촬영(§4) · `app/opengraph-image.alt.txt` · `lib/site.ts OG_IMAGE.alt` = SPEC §8 문장 | `app/opengraph-image.png` 외 |
| D24-1 | 하네스 T13 첫 화면 판정을 `load` 까지로(load + 1s 는 정보) | 하네스 `tests/T13.mjs` |
| teardown 인계표 | 전부 ② 에서 처리됨 확인(NAV_LINKS 3 · DownloadCTA server · Bubble onClick 삭제 · fixtures 0.3.49 · useCenterLine 삭제 · motion 제거) | — |

하네스 수정(저장소 밖): `tests/T05.mjs`(웹킷 4폭 가로 넘침 — D23-2) · `tests/T08.mjs`(크롬·웹킷 행 배율 6건 + 웹킷 1440 캡처 — D20-1) · `tests/T13.mjs`(D24-1 + `loadList` 진단). 원본은 같은 폴더 `*.orig`.

## 4. OG 재촬영(D8)

1440×900 · DSF 2 · 감속 모션 · 내비·데브 표시기 숨김 · 라벨 위 176 → 자르기 (0, 136, 1440, 756) → 1200×630 PNG(260,853B). 스크립트 `.scratch/integration/og.mjs`, 2× 원본 `.scratch/integration/og/raw-2x.png`, 이전 그림 `.scratch/integration/og/opengraph-image.v1.png`. 들어간 것: 돔 꼭대기·메뉴바 라벨·H1·리드·CTA·말풍선 "오늘도 화이팅!"·근무 라벨이 붙은 아잉.

## 5. 남은 문제 · 리뷰가 볼 것

1. **첫 화면 여유 2.5KB(10진)**: 헤드리스 크롬의 지연 로딩 거리(3,000px)로 R1 렌더 ≈72KB 가 load 전에 들어온다. 실제 4G 에서는 들어오지 않지만, JS 청크·HTML 이 조금만 커져도 빨개진다. 줄이는 길(판단 필요): R1 렌더를 문턱 근처에서 마운트 · 클라 번들에서 `assets.json`·`sequences.json` 전체를 빼기.
2. **Playwright WebKit 은 HEVC 알파를 못 푼다** → 웹킷에서 도착이 건너뛰어지고(포스터 + 근무 라벨, 말풍선 없음) 빛 한 줄이 ≈50ms 달리다 접힌다. 실제 사파리 확인은 ⑧ 실기 몫.
3. 데브의 포스터 preload 는 `<head>` 링크가 아니라 RSC 힌트로만 나간다(prod 는 `<head>` 에 있음 — 확인).
4. `DownloadCTA` 의 `installHref` 는 이제 쓰이지 않는다(PLAN §3.4 서명 호환으로 남김, `/licenses` 가 넘긴다).
5. 운영 메모: 이 환경의 Edit 도구는 새 inode 로 저장해 Turbopack 이 한두 번 늦게 반영했다(globals 가 직전 판으로 컴파일되는 것을 실측). 같은 파일을 `cat 사본 > 원본`(같은 inode)으로 다시 쓰면 곧바로 반영된다. 재시작은 필요 없었다.

## 6. 남은 결정(SPEC §7.4 · DECISIONS §4 — 기본값으로 진행)

1. 트립틱 방향 = 세로(D1). 가로를 원하면 A §S2 가로판을 카드 래퍼에만.
2. 위젯 수(2 ↔ 4) — 숫자 격자에서 뺐다.
3. 신규 문구 승인(SPEC §1.4.3: 격자 라벨 8 · 단위 · 열 라벨 · alt · OG alt).
4. WCAG 2.2.2 — idle 2회 상한으로 갈음(멈춤 버튼은 허용 목록 밖).
5. 센터 FAQ 미게재 · 저작권 "© 2026 아잉체크"(판매자명 여부).
6. DMG 서명·공증·스테이플 확인 전 "경고 없이 열려요" 금지 유지.

## 7. 캡처(리드 보고용 §7.3) — `/Users/yesung/check/landing/.scratch/integration/shots/`

1440×900: `1440-t0.png` · `1440-t1.2-comet-mid.png` · `1440-t3-arrived.png` · `1440-moments-01.png` · `-02` · `-03` · `1440-features.png` · `1440-R1-f-message.png` · `1440-R2-f-character.png` · `1440-R3-f-break.png` · `1440-R4-f-ranking.png` · `1440-R5-f-iphone.png` · `1440-facts.png` · `1440-install.png` · `1440-faq.png` · `1440-outro.png` · `1440-full.png`
짧은 화면: `1440x789-fold.png` · `1280x720-fold.png` · 390: `390x844-fold.png` · `390x844-full.png` · 감속: `1440-reduced-fold.png` · `1440-reduced-full.png` · 웹킷: `webkit-1440-fold.png`
(데브 캡처라 왼쪽 아래에 Next 개발 표시기 'N' 이 보인다 — prod 에는 없다.) 배지 감사(SPEC §9.6): R4 토큰·리그 조각·트립틱 콕 조각에 서울/부산 배지 0, R3 미니게임 순위 아바타의 작은 배지는 축소 표시(허용).

## 8. 마지막 점검(PLAN §6-8)

3100 닫힘 · Playwright 브라우저·node(데브 제외)·ffmpeg 0 · landing/ 안 의도하지 않은 파일 0(임시는 `.scratch/integration/` 만) · `git -C /Users/yesung/check status --short` = `?? landing/` · 데브 3000 살아 있음(재시작 0회). 표식 `docs/v2/.*-done` 은 지우지 않았다(재검증이 지운다).

---

## 수리 1바퀴(⑦ repair, 2026-10-12 21:50 KST)

리뷰 4건(`docs/v2/reviews/{design,motion,copy,perf-a11y}.md`) + 리드 결정 D25–D28 을 반영했다. 데브 3000(pid 14129/14130)은 **재시작하지 않았다**. 측정용 3100 은 두 번 띄우고 두 번 다 껐다(`lsof -i :3100` 비어 있음). 원본 사본 `.scratch/repair/orig/`.
판단 기준이 엇갈린 곳: D27-1(빛 한 줄 "선형")과 D28-3(두 구간)은 **나중 결정 D28-3** 을 따랐다(리드가 D27-1 의 구체화라 적음). SPEC §7.2 대안(cometMs=0 · 돔 지름 · 트립틱 피치/목록 모드)은 하나도 쓰지 않았다 — DECISIONS 추가 없음.

### 1. 고친 것(P1 전부 + 리드 결정 D26 + P2 일부)

| 리뷰 · 결정 | 고친 것 | 파일 |
|---|---|---|
| design P1-1 · motion P1-3 · D27-1 · D28-3 | 빛 한 줄 머리 = 흰 5px + 이중 글로우, 림 핵에서 5px 안쪽(`RIM_CORE_INSET` 5), 타이밍 두 구간(림 등속 T₁ = P/(4−3P) ≈ 300ms → 착지 ease-out, Web Animations), 꼬리 시작 불투명 .35. 순수 함수 `cometRimFraction()`·`cometRimTime()` + 단위 테스트 1건 | `app/globals.css` · `components/hero/HeroStage.tsx` · `components/hero/comet-path.ts` · `comet-path.test.ts` |
| motion P1-1 · D28-1 | 빛 한 줄은 commute-start 가 재생 가능해진 뒤에만 출발(`AingClip onOnceReady` → `HeroStage onceOk`). 마감 2.5s 안에 못 되면 빛·폴짝·말풍선 없이 근무 라벨만 | `components/ui/AingClip.tsx` · `HeroStage.tsx` |
| motion P1-4 · D28-4 | 빛 한 줄 도중 히어로 이탈(보이는 비율 < .35) → 도착 생략 · 빛 접음 · 돌아오면 근무 라벨 + idle | `HeroStage.tsx` |
| motion P1-2 · D28-2 | 목록 모드(tab·phone·감속) 카드 무대 빛 = GlowGate(`InlineMoment` 클라 섬: 오브젝트 가운데 30–70% 띠 + 히어로 .35 미만). JS 없음은 CSS 로 켜 둠 | `components/moments/InlineMoment.tsx`(신규) · `Moments.tsx` · `moments.css` |
| design P1-2 · D27-2 | `.seam`·`.tick`·`.faq-open-line` 에 `.horizon` 헤일로, 열린 FAQ 삼각형 `--violet-bright`, 10% 스파인 연장(`.spine-ext`, 숫자 격자·설치·FAQ → 아웃트로 위 160px 에서 사라짐, desk 만), 안심 한 줄 앞 틱. **헤일로만으로는 0.3% 를 못 넘어**(1px 를 18px 로 흐리면 최고 α ≈ .05 → V ≥ .30 미달, 실측 V6 .26 · V7 .18 · V8 .14%) 선 알파를 따르는 좁은 `drop-shadow`(2px · 8px)를 더했다(후보 4개를 페이지 주입으로 비교 — `.scratch/repair/probe/`). 하네스 `expect.mjs` V6–V8 하한 0.003(원본 `.orig`) | `globals.css` · `components/facts/Facts.tsx` · `components/install/Install.tsx` · `components/faq/Faq.tsx` · `components/outro/Outro.tsx` |
| design P1-3 · D27-4 | 히어로 아래 `--line` 받침선(`border-b border-line`) | `components/hero/Hero.tsx` |
| design P1-4 · D27-3 | 조각 잘린 왼쪽 변 직각(RowCanvas 창 상자 · `.moment-slice`) + 머리띠 노치(`Fade.notch` — 토큰판 위 46px 만 왼쪽 5px 투명 → '◀' 조각 가림 · 콕 조각 위 56u 만 31u 투명 → "…찌르기" 가림, 노치 폭은 `--moment-u` 를 따라 줄도록 CSS). **다시 굽지 않았다**: 원본에서 아바타 배지('서울/부산') 오른쪽 끝과 크롭 x 사이가 콕 3 · 토큰 8 · 리그 11 원본 px 뿐이라 12px 넓히면 배지가 들어온다. 리그 행 첫 글자는 D20-3 의 16px 페이드 그대로 | `components/ui/RenderImage.tsx` · `components/features/RowCanvas.tsx` · `rows-b.data.ts` · `components/moments/MomentObject.tsx` · `moments.css` |
| copy P1-1 · D26-2 | iOS 히어로 메타 = 「iOS 18 이상 · 무료」(CB:243), "brew로 설치" 숨김 | `Hero.tsx` · `components/hero/copy.ts` |
| perf P1-1 | 내비 CTA 알약 36(`h-9`) + 투명 `::before` 로 누를 자리 44 | `components/ui/DownloadCTA.tsx` |
| perf P1-2 | zip 링크 누를 자리 17 → 45.7(`-my-3 py-3`) | `Install.tsx` |
| perf P1-3 · D25-1 | 행 렌더 `<img>`(주·교체·자식·폰 화면·말풍선·타일)는 행이 1,200px 안에 들어올 때 마운트(`useNearViewport`) + `<noscript>` 폴백 | `components/features/FeatureRow.tsx` · `RowCanvas.tsx` |
| D26-1 | 설치 절 brew 업데이트 문장(CB:236) 삭제 — 업데이트 문장은 맨 아래 하나 | `Install.tsx` · `data/install-copy.ts` |
| D26-3 | 행 말풍선 `aria-hidden`(히어로·트립틱과 같게) | `RowCanvas.tsx` |
| D26-4 | iOS 아웃트로 "brew 명령 복사" 숨김 | `Outro.tsx` |
| D26-5 | 배지 alt 「App Store에서 다운로드 하기」 · 복사 실패 힌트 "⌘C로 복사하세요" 삭제(선택 상태만 남김) | `components/ui/AppStoreBadge.tsx` · `components/ui/CommandBox.tsx` |
| motion P2-5 | 히어로 말풍선 퇴장: 불투명 160ms 선형만, 축소는 사라진 뒤 | `globals.css` |
| motion P2-6 | 감속 모션에서 말풍선·근무 라벨을 하이드레이션 전 첫 페인트부터(상자에 `--art`, 감속 미디어쿼리에서만 배경 — 기본 컨텍스트 요청 0) | `AingClip.tsx` · `globals.css` |
| motion P2-7 | 행 선 탁해짐 900–1300(가지 포함) · 주 렌더 빈 창 불투명 320ms | `globals.css` |
| motion P2-8 | SPEC §S1 idle 행을 실측(≈30.0s 정지)에 맞춤 | `docs/v2/SPEC.md` |
| design P2-1 | 트립틱 카운터를 숫자 바로 위(16svh − 32px)로 — 교체 순간 "[01/03] 콕." 사라짐 | `moments.css` |
| design P2-4 | 설치 세로 격자 아래 96px 흐림 | `Install.tsx` |
| design P2-5 | R5 바닥 빛 위 430 → 398(이음매 넘김 해소, V5 2.17%) | `rows-b.data.ts` |
| perf P2-4 · P2-5 | "brew로 설치" 43.7 → 45.7 · 푸터 링크 `min-w-11`(지원 23 → 44) | `Hero.tsx` · `components/site/SiteFooter.tsx` |
| perf P2-6 · P2-7 | 무대 모드 비활성 `.obj` 에 `aria-hidden` · 카운터 대괄호 `aria-hidden` | `components/moments/MomentsStage.tsx` · `Moments.tsx` |

문서: SPEC 머리 '수리 반영 메모' + §2.2·§2.7·§2.9(V6–V8 하한 0.3%, GlowGate 표에 목록 모드 줄)·§4(내비 CTA)·§5.2·§6.5(배지·QR alt)·§S1·§S2·§S4·§S5–§S8 · PLAN §3.4(`onOnceReady` · `Fade.notch`)·§3.5(RowCanvas `mount`).

### 2. 남긴 것(이유)

| 항목 | 이유 |
|---|---|
| design P2-2 돔 패럴랙스 끝 불투명 .35 → .15 | SPEC §S1 모션 ② 값 — 리뷰가 '리드 확인'으로 둠. 경계(549–900)의 글로우 판정은 T9·glow 측정 모두 ≤ 1 |
| design P2-3 R1 패널 크롭 아래로 늘리기 | 에셋 다시 굽기 + R1 좌표·바닥 빛 다시 잡기(P2). D19-2 의 24px 페이드 그대로 |
| design P2-6 390·768 히어로 메타–아잉 빈 칸 | 리뷰가 '리드 판단'(폰·탭 히어로를 100svh 보다 짧게) |
| design P2-7 미니게임 순위 배지(레티나에서 읽힘) | SPEC §9.6 허용 · 리뷰 기본값 유지 |
| copy P2-1 390 리드 줄바꿈 | D26-6 '변경 없음' |
| perf P2-8 `/licenses` 의 500·300 preload | 글꼴 변수를 `main` 으로 옮기면 `@theme inline` 의 `--font-display` 등이 `:root` 에서 무효가 될 위험 — 첫 페이지 예산과 무관 |
| perf P2-9 웹킷 idle.mov 재요청 | 코드 변경 없음 — ⑧ 사파리 실기(배포 헤더) 확인 몫 |
| perf P2-10 · P2-12 | 기록·배포 체크리스트(D25-1 이 번들 정리를 범위 밖으로 둠) |
| perf P2-11 새 탭 예고 | 신규 문구 — SPEC §1.4.3 승인 필요 |
| 서브셋 재생성 | 소스 한글 341자 ⊂ 서브셋 447자(문구를 지우기만 했다) — check-glyphs 0, 다시 굽지 않음 |

### 3. 재측정

- **T1**(`--build`): typecheck · lint · test:unit(66/66) · check-glyphs · build 각각 exit 0.
- **T2–T12 · T14–T17**(데브 3000, `v2accept/out/repair-final/report.json`): 전부 초록. 문서 높이 9,849 · 말풍선−메타 19.7px(789·720) · 빛 한 줄 ↔ 글자 줄 **14.5px**(1440) · **15.6px**(1024)(≥ 12).
- **T13 · T3/T4/T9@prod**(3100, `out/repair-prod2/report.json`): 첫 화면 `load` 까지 **319.2KiB** — perf-a11y 스크립트(헤드리스) **305,097B**(이전 397,511) · 4G 에뮬 324,971B → D25 목표 ≤ 360KB 초록 · 전체 1440 크롬 1,611.8KiB · 웹킷 2,408KiB · 390 1,338.1KiB · 스로틀 390 LCP 808ms(숨은 idle 층 — perf 참고 1) · CLS 0 · load 전 영상 0.
- **T9 보라**(1440×900): V0 6.58 · V1 3.67 · V2 0.33 · V3 1.95 · V4 1.40 · V5 **2.17** · V6 **0.74** · V7 **0.34** · V8 **0.38** · V9 5.05% · 경계 6곳 글로우 ≤ 1.
- **글로우 ≤ 1(전 구간, review-motion glow.mjs)**: 390×844 >1 **0/135**(이전 17) · 768×1024 **0/119**(이전 17) · 1440 감속 **0/114**(이전 19) · 1440 **0/113**.
- **빛 한 줄**: 40ms 시트(`.scratch/repair/motion/comet/comet-40ms.png`) — 머리가 run+40ms 에 라벨 옆 림 위, +320ms 에 림 아래, 착지 곡선을 지나 말풍선 앞까지 내내 보임. 마감(`deadline.mjs`, 영상만 지연): 4,000ms → `data-run` **0건**, 2,509ms 에 근무 라벨만 · 1,500ms → canplay 1,762 → run 1,796 → 도착 2,801(= 빛 끝) · 0ms → run 329 → 도착 1,333. 이탈(`leave.mjs` B): run 225 → 548 이탈 → 572 빛 접음, 말풍선 0, 복귀 4,568 에 근무 라벨 + idle. 웹킷(HEVC 불가): `data-run` 0건(이전 43ms 번쩍).
- **말풍선 퇴장**: 불투명 1 → 0 이 160ms, 그동안 scale 1(축소는 171ms 이후).
- **감속 첫 페인트**: 말풍선·근무 라벨 그림이 465ms(FCP 472) · CPU 4× 144ms(FCP 208) — 하이드레이션(577 · 636) 전. 기본 컨텍스트 배경 요청 0.
- **터치**: 내비 CTA 126×44(iOS 101×44) · brew로 설치 72×45.7 · zip 206×45.7 · 푸터 지원 44×44.
- **iOS 390**: 히어로 메타 "iOS 18 이상 · 무료" · brew 링크·아웃트로 복사 버튼 안 보임(DOM 의 button 2개는 그대로 — T10).

### 4. 캡처(리뷰 캡처 위치 다시 — `/Users/yesung/check/landing/.scratch/repair/`)

`recap/shots/`(design cap.mjs 위치 19곳 + `report.json`) · `recap/detail/`(빛 한 줄 연속 프레임 · `r4-slices-left` · `poke-slice-left` · `hero-bottom-seam` · `faq-open-line` · `fold-*`) · `motion/comet/comet-40ms.png` · `motion/deadline-*/` · `motion/leave/` · `motion/glow/` · `ios/ios-{hero,outro}.png` · `perf/shots/`(포커스 링) · `probe/`(조용한 절 후보 비교) · `shots/`(§7.3 캡처 세트 24장).

### 5. 운영 메모

- 이 환경의 Edit 도구 저장 한 번(globals 감속 블록)을 Turbopack 이 놓쳤다 — 같은 내용 재기록으로는 컴파일되지 않고, 내용이 바뀌는 쓰기(끝 줄바꿈 추가 → 다시 제거)에서 반영됐다. 데브 재시작은 필요 없었다. 그 뒤 수리 항목마다 서빙된 CSS·DOM 으로 반영을 확인했다(`probe/dom.mjs`).
- 3100 은 두 번 띄우고 `TaskStop` 으로 끈 뒤 `lsof -i :3100` 비어 있음 확인.
