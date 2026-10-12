# requests — core(② 스캐폴드)

작성 2026-10-12 · core. 공용 파일 중 core 소유 밖은 고치지 않았다. 아래는 다른 소유자·통합이 볼 것.

## 1. primitives — `components/ui/DownloadCTA.tsx` 의 nav 모양이 SPEC §S0 와 두 군데 다르다

**무엇·왜**
- (a) S0: "CTA: 히어로 CTA 가 보이면 **테두리(`--line-strong` · `ink-1`)**, 화면 밖이면 라벤더 채움". 지금 `tone="outline"` = `border-aing bg-transparent text-aing`(라벤더 테두리·라벤더 글자). `NavShell` 은 `tone={fill ? 'fill' : 'outline'}` 로만 넘긴다(채움 판정은 `header[data-fill]` 로 이미 맞음 — 1440×900 scrollY 545 에서 붙는 것 실측).
- (b) S0 390 와이어: `20 [icon 22] 아잉체크      (Mac용 다운로드)`. 지금 nav 자리는 phone 폭에서 v1 처럼 '설치'(→ `installHref`) 알약을 보인다(390 캡처 실측).

**제안 diff**(둘 중 소유자 판단 — 공용 서명은 그대로)
```diff
 const TONE = {
   fill: "btn-primary border-aing bg-aing text-on-aing hover:border-aing-hover hover:bg-aing-hover",
-  outline: "border-aing bg-transparent text-aing hover:bg-aing/12",
+  outline: "border-line-strong bg-transparent text-ink-1 hover:bg-surface",   // SPEC §S0
 } as const;
 …
     placement === "nav" ? (
-      <>
-        {download("inline-flex phone:hidden")}
-        <a href={installHref} … className={cx(pill, "hidden phone:inline-flex")}>설치</a>
-      </>
+      download("inline-flex")                                                  // SPEC §S0 390 = Mac용 다운로드
     ) : (
```
(b) 를 바꾸면 `installHref` 는 쓰는 곳이 0 이 된다 — `LicensesNav` 가 넘기고 있으니 서명에서 지우지 말고 무시만 하거나 통합이 정리.

**참고(유지 요청)**: `NavShell`(client)이 `DownloadCTA` 를 직접 import 한다(톤이 클라 상태라서). 지금처럼 **동기·훅 없음·`server-only` import 없음**을 유지해 주면 된다(그러면 client 에서 불러도 된다).

## 2. faq-outro — `components/site/LicensesNav.tsx` 건너뛰기 링크가 포커스 때 안 보인다(v1 부터)

**무엇**: `sr-only … focus:not-sr-only focus:fixed …` 조합은 v2 globals 의 `.sr-only`(components 층, `clip:rect(0,0,0,0)`)를 풀지 못한다 — Tailwind 4 의 `not-sr-only` 는 `clip-path` 만 되돌리고 `clip` 은 그대로, 게다가 `padding:0` 으로 `px-4 py-2` 를 이긴다. 첫 페이지 `NavShell` 에서 실측(포커스해도 `clip: rect(0px,0px,0px,0px)`, 높이 14px).
**왜**: SPEC §S0 · PLAN T14 "건너뛰기 링크 포커스 시 보임".
**제안 diff**(NavShell 에 넣은 것과 같은 고침 — 실측 초록):
```diff
-        className="t-button-s sr-only rounded-[var(--r-pill)] bg-surface-2 px-4 py-2 text-ink-1 focus:not-sr-only focus:fixed focus:left-4 focus:top-2 focus:z-[var(--z-ultra)]"
+        className="t-button-s sr-only rounded-[var(--r-pill)] bg-surface-2 px-4 py-2 text-ink-1 focus:not-sr-only focus:fixed focus:left-4 focus:top-2 focus:z-[var(--z-ultra)] focus:px-4 focus:py-2 focus:[clip:auto]"
```
같이 볼 것(선택): 워드마크가 `t-nav text-[15px] font-bold` — v2 는 `.t-wordmark`(16 · 600, 글꼴 `--font-heading`)가 있다(첫 페이지 내비는 `t-wordmark`).

## 3. integration — 포스터 preload 경고(`/licenses` 에서는 계속)

**무엇**: PLAN §3.9 대로 `app/layout.tsx` `<head>` 에 `<link rel="preload" as="image" href={char/aing-rest-poster} fetchPriority="high">` 를 두었다. 크롬·웹킷이 `/` 에서 "preloaded using link preload but not used within a few seconds" **경고**를 낸다 — 자리표시자 히어로가 포스터를 그리지 않아서이고, hero 가 같은 URL 의 `<img>` 를 그리면 `/` 에서는 사라진다. `/licenses` 는 포스터를 쓰지 않으므로 **계속** 경고한다(error 아님 — T3 은 `/` 의 error 만 센다).
**제안**: 통합이 원하면 preload 를 첫 페이지로 좁힌다 — `app/layout.tsx` 에서 `<link>` 를 빼고 `app/page.tsx` 의 `Page()` 맨 앞에서 `import { preload } from 'react-dom'` → `preload(asset('char/aing-rest-poster')!.src, { as: 'image', fetchPriority: 'high' })`(React 19 가 `<head>` 로 올린다). PLAN §3.9·§3.10 모양이 바뀌므로 core 는 하지 않았다.

## 4. 알림 — 계약과 글자가 다른 구현(이유 있음, 서명은 같다)

- `lib/hooks.ts` `useRevealOnce`: IO rootMargin = `100000px 0px -${(1-line)*100}% 0px`(PLAN 은 위 여백 0). 위를 넓혀 두면 빠른 스크롤·해시 이동으로 요소가 문턱 띠를 한 프레임에 건너뛰어 화면 위로 사라져도 '지남'이 잡힌다(위 여백 0 이면 교차가 안 바뀌어 콜백이 없다). 마운트 때 이미 지났으면 첫 콜백에서 `{ on: true, instant: true }`. 크로뮴·웹킷에서 문턱(1440×900, 요소 윗변 612px)·건너뛰기 둘 다 실측.
- `lib/moments.ts` `useActiveCard`: 화면 전체를 루트로 한 IO 는 숫자가 화면 가운데에서 .55 줄을 지나도 교차 비율이 1 그대로라 콜백이 오지 않는다 → **문턱 줄마다 IO 하나**(숫자 윗변 .55·.62 = 루트 (−∞, p·vh], 섹션 윗변 .30, 섹션 아랫변 .70 = 루트 [.70·vh, +∞)), 콜백마다 `getBoundingClientRect` 로 `nextActive`·`isEngaged` 를 다시 계산. thresholds `[0,.25,.5,.75,1]` 는 그대로. 같은 IO 설정을 브라우저(크로뮴·웹킷)에 넣어 SPEC §S2 기댓값을 재 봤다: 548→-1 · 549→0 · 1,196→0 · 1,197→1 · 1,845→2 · 1,800→2 · 1,700→1 · 1,134→1 · 1,133→0 · 0→-1 · engaged 629 ✗/630 ✓/2,466 ✓/2,467 ✗ · 0→1,845 한 번에 2.
- `nextActive` 앞 문턱은 **경계 포함(≤)**, 뒤는 초과(>) — SPEC 기댓값 "scrollY 549 에서 0"(숫자 윗변이 정확히 .55·vh)과 "1→0 at < 1,134" 를 둘 다 만족시키는 유일한 조합. 부동소수 꼬리는 EPS 1e-6 px 로 지웠다.
- 문턱 기본값 `DEFAULT_THRESHOLDS {.55, .62}` 는 `lib/moments.ts` 에 따로 있다(이 파일이 `node --test` 로 읽혀야 해서 `@/`·JSON import 를 하는 `data/fixtures.ts` 를 못 끌어온다). `lib/moments.test.ts` 가 `MOMENTS_TIMING.forward/back` 과 같은지 소스를 읽어 맞춰 본다.
- `useMediaQuery`: SSR·하이드레이션 첫 렌더 false(서버 스냅숏), 하이드레이션 뒤 실제 값. 하이드레이션이 아닌 클라 마운트(나중에 붙는 섬)에서는 첫 렌더부터 실제 값이다(`useSyncExternalStore`).
- `useCenterLine` 삭제(PLAN §3.1 · 사용처 0 — `grep` 확인). `useEnterTimer` 는 이미 없었다.
- SPEC §6.1 표의 `useVisibleRatio()` 는 PLAN §3.1 서명에 없어 만들지 않았다(PLAN 우선 — 보이는 비율은 `useInViewRatio(ref, ratio)`).
- `ALT['ui/message-read-panel']` = "구름빵과의 1:1 메시지. 구름빵이 읽어 1이 사라짐" — SPEC §6.5 의 한 칸("… 안 읽음 1 / 구름빵이 읽어 1이 사라짐")을 앞머리 공유로 나눈 것(새 낱말 없음).
- 내비 워드마크는 링크가 아니다(SPEC §1.5 허용 목록 = 내비 링크 3 + CTA + 건너뛰기).
- 히어로 자리표시자에 `[data-hero-cta]` 표식 하나(1440×900 y≈540)를 두었다 — 자리표시자 단계에서 내비 `data-fill` 을 시험하려고. hero 가 덮어쓸 때 실제 버튼 줄에 `data-hero-cta` 를 달면 된다(PLAN §4.1 그대로).
