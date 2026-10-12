# 리뷰 — 모션 렌즈(review-motion)

작성 2026-10-12 KST · review-motion(읽기 전용 — 코드 변경 0). 기준: DECISIONS D1–D25 > PLAN §0·§3·§7 > SPEC §1.2·§1.3·§2.7–§2.9·§S1·§S2·§S4·§S8·§5.
측정: 데브 3000(재시작 0회), Chromium(Playwright 1.60) 직접 계측 + CDP 스크린캐스트 + 실제 영상 프레임 비교. WebKit 은 히어로 1건만(HEVC 알파 디코드 불가 환경 — 포스터 폴백 정상).
스크립트·로그·캡처: `/Users/yesung/check/landing/.scratch/review-motion/`(파일 목록은 맨 아래 §5).

**집계: P0 0 · P1 4 · P2 4**

잘 된 점(3줄)
- 히어로 도착이 표대로 돈다: 빛 1,004ms → 반응 1.50s → idle 45칸부터(실제 프레임 비교: 반응 끝 ↔ idle 45칸 차 2.4 ≈ 자연 한 칸 1.6–1.7, 가장 닮은 idle 칸도 45) → 말풍선 정확히 5,000ms → 30.0s 에 마지막 칸(14.4s)에서 정지, 포스터로 안 바뀜. D22-1 수정 뒤 층 교체 틈 0(포스터↔반응 19ms·반응↔idle 35ms 겹침).
- 트립틱: 고정 구간 900–2,196 전부 `top === 0`, 문턱 앞 1,198/1,846 · 뒤 1,778/1,130(SPEC 1,197/1,845 · <1,782/<1,134), 교체 퇴장 277ms·등장 120ms 뒤 ~460ms 에 끝, 점등 455ms, 빛 +120ms 지연 후 800ms 선형, 되감김 대칭(아래로 퇴장·위에서 등장), 첫 점등 1,300ms, 잔디 70ms×13.
- 행 5개 모두 문턱 직후 ≤40ms 에 `data-on` → 1.26s 조립 끝 · 왕복 뒤 `data-reveal-count="1"`·재진입 즉시 최종 · 오버슈트는 타일만(scale 최대 1.039) · 감속/JS 없음 전 구간 최종 상태·영상 요청 0 · 앱 스크롤 리스너 0 · 아웃트로 45% 진입 600ms 선형 1회·idle 2바퀴 뒤 정지.

---

## 1. 결함

### P1-1 빛 한 줄이 commute-start 준비 여부를 보지 않고 출발한다 — 마감(2.5s)에 걸리면 빛만 달리고 아무것도 도착하지 않는다
- **파일:줄**: `components/hero/HeroStage.tsx:92`(출발 조건 `loadIdle && in50 && atTop`) · `components/ui/AingClip.tsx:264–278`(마감 판정은 AingClip 만 함)
- **재현**: Chromium 1440×900 · scrollY 0 · 캐시 끔 · `page.route(/\.(webm|mov)/)` 로 영상만 지연. `node .scratch/review-motion/deadline.mjs delay:4000`(또는 `delay:2300`, `delay:1500`).
- **기대**(SPEC §S1 모션 ①): "2.5s 안에 commute-start 가 재생 가능하지 않으면 **빛 한 줄·폴짝·말풍선을 건너뛰고** 근무 라벨만 켠 뒤 idle". 빛 한 줄은 언제나 진짜 렌더에서 끝난다(SPEC §1.2 '선 → 렌더').
- **실제**(`deadline-delay_4000/contact-0.25s.png`, `log.json`):
  - 지연 4,000ms: `data-run` 572 → 빛이 말풍선 자리까지 다 달림(1,574) → 1.2s 동안 흐려짐 → 2,502 에 근무 라벨만 뿅. 폴짝·말풍선 없음. **빛이 '약속'만 하고 끝난다.**
  - 지연 2,300ms: 같은 모양(빛 306–1,310, 라벨 2,504).
  - 지연 1,500ms: 빛 끝 1,339 → **480ms 동안 아무 일 없음** → 1,818 에 폴짝(빛이 거의 다 사라진 뒤).
  - WebKit(HEVC 실패): 빛이 491 에 출발해 534 에 접힘 — 43ms 번쩍(`webkit/webkit.json`).
- **고칠 방법**(빛은 반응이 재생 가능해진 뒤에만 출발 — 마감 전에 준비 안 되면 빛도 없음):
  ```diff
  // components/ui/AingClip.tsx — props 에 추가(PLAN §3.4 서명 보강, 수리가 PLAN 에 한 줄 적는다)
  +  /** once 가 재생 가능(canplay)해진 순간 한 번 */
  +  onOnceReady?(): void;
  ...
  +  const onceReadyCalled = useRef(false);
  +  useEffect(() => {
  +    if (!onceReady || onceReadyCalled.current) return;
  +    onceReadyCalled.current = true;
  +    onOnceReady?.();
  +  }, [onceReady, onOnceReady]);

  // components/hero/HeroStage.tsx
  +  const [onceOk, setOnceOk] = useState(false);
  ...
  -    else if (loadIdle && in50 && atTop) setBegun(stageMode ? 'comet' : 'direct');
  +    else if (loadIdle && in50 && atTop && (!stageMode || onceOk)) setBegun(stageMode ? 'comet' : 'direct');
  ...
         <AingClip
  +          onOnceReady={() => setOnceOk(true)}
  ```
  마감(`deadlinePassed`)이 먼저 오면 기존 `setSkip(true)` 길로 빛 없이 라벨만 — SPEC 그대로. 준비가 2.4s 에 끝나면 빛 2.4 → 도착 3.4s(T6 '로드 후 3.5s' 안). WebKit 43ms 번쩍도 같이 사라진다. 확인: `deadline.mjs delay:4000` 에서 `data-run` 0건, `delay:1500` 에서 빛 끝 = 도착(±20ms).

### P1-2 목록 모드(폰·탭·감속 데스크·JS 없음)의 트립틱 무대 빛이 '늘 켜짐'이라 한 화면에 글로우 2–3개
- **파일:줄**: `components/moments/Moments.tsx:36`(`glow="static"`) · `components/moments/MomentObject.tsx:45`(속성 없는 `.obj-glow`) · `app/globals.css:132`(`.obj-glow` inset −140px −180px — 오브젝트 위아래로 140px 씩 번짐)
- **재현**: `node .scratch/review-motion/glow.mjs 390 844` · `glow.mjs 768 1024` · `glow.mjs 1440 900 --reduced`(각 위치 1s 대기, 유효 불투명 > .05 인 글로우가 화면과 겹치는 수). 캡처 `shots/glow-768x1024-y1350.png`(셋), `shots/glow-390x844-y1200.png`(둘), `shots/glow-1440x900-reduced-y2000.png`(둘).
- **기대**(SPEC §1.3-1 "한 화면에 글로우 하나", §2.9 GlowGate, §S2 목록 모드 "카드당 하나라 '화면당 하나'를 지킨다"): 화면과 겹치는 글로우 ≤ 1.
- **실제**: 무대 모드(1440×900·1280×720·1024×768)는 113·79·81 위치 모두 ≤ 1(초록). 목록 모드는 빨강 —
  - 390×844: 135 위치 중 17곳 > 1(scrollY 300–2,300 거의 전 구간: 이웃 카드 빛 둘, 히어로 돔 + 카드 1 빛).
  - 768×1024: 86 위치 중 17곳 > 1, **최대 3개**(scrollY 1,050–1,500) + 600–660 에서 히어로 돔까지 4개.
  - 1440×900 감속: 114 위치 중 19곳 > 1.
  - T9 는 1440×900 무대 모드만 재서 통합이 놓쳤다.
- **고칠 방법**: 인라인 빛에도 행 바닥 빛과 같은 GlowGate(오브젝트 가운데가 화면 30–70% 띠 안일 때만).
  ```tsx
  // components/moments/InlineMoment.tsx(신규, client)
  'use client';
  import { useRef } from 'react';
  import { useBand } from '@/lib/hooks';
  import { MomentObject } from './MomentObject';
  export function InlineMoment({ n }: { n: 1 | 2 | 3 }) {
    const ref = useRef<HTMLSpanElement>(null);
    const on = useBand(ref, [0.3, 0.7]);                 // display:none(무대 모드)이면 교차가 없어 늘 off
    return (<>
      <MomentObject n={n} lit instant glow={on ? 'on' : 'off'} />
      <span ref={ref} aria-hidden="true" className="pointer-events-none absolute left-0 top-1/2 h-px w-px" />
    </>);
  }
  ```
  ```diff
  // components/moments/Moments.tsx:36
  -              <MomentObject n={OBJECT_N[i]} lit instant glow="static" />
  +              <InlineMoment n={OBJECT_N[i]} />
  /* components/moments/moments.css — JS 없음은 최종 상태 유지(겹침은 JS 없음에서만 허용) */
  + html:not(.js) .moments-inline .obj-glow[data-glow] { opacity: 1; }
  ```
  카드 피치(폰 ≈700–900px, 탭 ≈460px, 감속 데스크 78svh=702px)가 띠 높이(폰 338 · 탭 410 · 데스크 360px)보다 커서 동시에 둘은 불가능. 감속에서도 불투명 800ms 페이드만(허용). 고친 뒤 위 세 명령 > 1 이 0건인지, 그리고 T9 에 390·768·감속 1440 을 추가.

### P1-3 빛 한 줄의 '라벨에서 출발해 림을 타고'가 보이지 않는다 — 경로 63% 가 첫 180ms 에 지나가고, 머리는 림의 핵과 같은 색으로 그 위를 달린다
- **파일:줄**: `app/globals.css:193–194`(1000ms 한 번의 `--ease-out`) · `components/hero/comet-path.ts:31`(`RIM_CORE_INSET = 1.5` — 머리가 핵 위) · `app/globals.css:174`(머리 `stroke: var(--violet-core)` = 림 핵 색) · `components/hero/HeroStage.tsx:184`(꼬리 그라디언트 0번 정지점 불투명 0 — 림 구간 꼬리는 안 보임)
- **재현**: Chromium 1440×900 · scrollY 0 · `node .scratch/review-motion/comet.mjs` → `comet/comet-100ms.png`(run+0…1300ms, 100ms 간격).
- **기대**(SPEC §0.1·§1.1·§S1 표 t=0): "머리가 **돔 꼭대기(라벨 바로 위)에서 림을 타고** 시계 반대 방향으로 내려가다 … 말풍선 왼쪽 끝으로 휘어 들어간다" — 페이지의 '기억에 남을 하나'.
- **실제**: 경로 1,305px 중 림 원호 ≈819px(63%). `cubic-bezier(.2,.8,.2,1)` 에서 진행 .63 은 시간 ≈.18 → **림 구간 180ms**, 남은 37%(착지 곡선)에 820ms. 캡처에서 run+100ms 에 림 위 희미한 점 하나, run+300ms 에 이미 왼쪽 림을 떠나 바닥 곡선 위 — 화면에는 "왼쪽 림에서 선 하나가 자라 말풍선 쪽으로 느려지며 기어간다"로 읽힌다. 라벨 출발은 판독 불가(머리 #FFC8FF 가 같은 #FFC8FF 핵 위, 꼬리는 림 구간에서 투명).
- **고칠 방법**(움직임 규칙 안에서 — 리드 확인 필요: SPEC §S1 표 '1000ms ease-out' 문구를 바꾼다):
  1. 시간 분배: 림 구간은 등속, 착지 곡선만 ease-out, 이음매 속도 일치. P = 림 길이/전체, 착지 시작 속도 = ease-out 기울기 4 → 림 시간 비 T₁ = P/(4 − 3P)(1440×900: P .63 → T₁ .30 = 300ms). `measureComet` 이 `rimFrac = r·θ / path.getTotalLength()` 를 함께 돌려주고, CSS 전이 대신 WAAPI 로:
     ```ts
     const P = c.rimFrac, T1 = P / (4 - 3 * P), E = 'cubic-bezier(.2,.8,.2,1)';
     trail.animate([{ strokeDashoffset: 100 }, { strokeDashoffset: 100 - 100 * P, offset: T1, easing: E }, { strokeDashoffset: 0 }],
                   { duration: HERO.cometMs, fill: 'forwards' });
     head.animate([{ strokeDashoffset: 2 }, { strokeDashoffset: 2 - 100 * P, offset: T1, easing: E }, { strokeDashoffset: -98 }],
                  { duration: HERO.cometMs, fill: 'forwards' });
     ```
     (WAAPI 키프레임 easing 은 그 키프레임에서 다음까지 — 첫 구간은 기본 linear.) 더 또렷하게 하려면 `--t-comet` 1000 → 1300(RA 의 '호의 빛 머리 1.3s')로 림 390ms.
  2. 머리를 림 핵과 구분: `.comet-head { stroke:#fff; stroke-width:4; filter:drop-shadow(0 0 6px var(--violet-core)) drop-shadow(0 0 14px var(--violet-bright)); }`. 경로를 안쪽으로 옮기는 안(`RIM_CORE_INSET` 1.5 → ≤5)은 H1 첫 줄 왼쪽 위와의 간격(실측 17.7–19px, D22-2)이 12px 아래로 떨어지지 않는 범위에서만 — `comet-path.test.ts` 와 T6 기하 단언을 다시 돌린다.
  3. 꼬리 0번 정지점 `stopOpacity: 0` → `.35`(림 구간 꼬리가 출발점에서부터 보이게).
  확인: `comet.mjs` 로 run+100·200ms 캡처에서 머리가 림 위 라벨 근처 → 림 중간에 또렷이 보이는지.

### P1-4 빛 한 줄이 달리는 중(도착 전)에 히어로를 벗어나도 도착이 화면 밖에서 그대로 재생된다
- **파일:줄**: `components/hero/HeroStage.tsx:89–95`(건너뜀 판정은 `begun === null` 일 때만) · `:148–155`(1000ms 타이머가 무조건 `setStartSig(true)`)
- **재현**: Chromium 1440×900 · 로드 → `data-run` + 300ms 에 scrollY 1,200 → 4s 뒤 0 으로. `node .scratch/review-motion/leave.mjs`(갈래 B).
- **기대**(SPEC §S1): "처음 도착 전에 히어로를 벗어났으면 도착을 건너뛴다(돌아와도 다시 하지 않음 — 근무 라벨은 켠다)".
- **실제**(`leave/leave.json` B): 562ms 에 벗어났는데 1,241 에 `data-arrived`+`data-bubble`, 반응 1,241–2,742 를 화면 밖에서 재생. 돌아온 6,104 에 말풍선이 아직 떠 있다가(불투명 1) 6,241 에 사라짐 — 도착은 못 봤는데 남은 말풍선만 본다. (갈래 A: 로드 전에 벗어남 → 빛·반응 요청 0, 돌아오면 라벨+idle — 초록. 갈래 C: scrollY 300 → 2.5s 에 라벨만 — 초록.)
- **고칠 방법**(P1-1 과 같은 파일, 4줄):
  ```diff
     if (begun === 'comet' && early && !done) setDone(true);
  +  // 빛이 달리는 중(도착 전)에 히어로를 벗어나면 도착을 건너뛴다(SPEC §S1) — 빛은 접고, 돌아오면 라벨 + idle
  +  if (begun === 'comet' && !startSig && !skip && seen35 && !in35) { setSkip(true); setDone(true); }
  ...
     useEffect(() => {
  -    if (!run) return;
  +    if (!run || skip) return;
  ...
  -          start={startSig || (skip && in35)}
  +          start={(startSig && !skip) || (skip && in35)}
  ```
  (`skip` 이면 `once`·`bubble` 이 undefined 로 바뀌어 AingClip 은 시작 신호 때 0번 칸 idle + 근무 라벨로 간다.) 확인: `leave.mjs` B 에서 `data-bubble` 0건, 복귀 후 `data-arrived` 만.

### P2-5 히어로 말풍선 퇴장 첫 프레임에 scale 이 .96 으로 '툭' 줄어든다
- **파일:줄**: `app/globals.css:191`(`:not([data-bubble])` 규칙이 `scale:.96` 을 걸면서 전이는 opacity 만)
- **재현**: 1440×900 · 로드 후 ≈6.2s(말풍선 해제 순간) rAF 표본. `comet.mjs` 의 `exit` — `[0ms, opacity 1, scale .96] → [172ms, 0, .96]`.
- **기대**(SPEC §2.7 말풍선 앱 값): 퇴장 = 불투명 160ms 선형만.
- **실제**: 불투명 1 인 채로 148→142px 즉시 축소(원점 왼쪽 아래 — 오른쪽 위 모서리가 ≈6px 튐) 후 페이드.
- **고칠 방법**: 축소는 다 사라진 뒤에.
  ```diff
  - .js [data-aing]:not([data-bubble]) .aing-bubble { opacity:0; scale:.96; transition:opacity 160ms linear; }
  + .js [data-aing]:not([data-bubble]) .aing-bubble { opacity:0; scale:.96; transition:opacity 160ms linear, scale 0s linear 160ms; }
  ```

### P2-6 감속 모션에서 히어로 말풍선·근무 라벨이 첫 페인트에 없고 하이드레이션 뒤에 '뿅' 나타난다
- **파일:줄**: `components/ui/AingClip.tsx:231–239`(posterOnly 도 rAF 뒤 `layersOn`) · `:438–449`(SSR 은 `<noscript>` 안 — JS 켜진 브라우저는 그리지 않음)
- **재현**: Chromium 1440×900 · `reducedMotion:'reduce'` · 캐시 끔. `node .scratch/review-motion/reduced-paint.mjs` → CPU 1×: FCP 444 · 말풍선 568(+124ms) / CPU 4×: FCP 208 · 말풍선 647(+439ms)(`reduced/paint.json`, 데브 기준).
- **기대**(SPEC §2.7 · §S1): 감속 = "각 절은 처음부터 최종 상태(히어로 = 포스터 + 말풍선 + 근무 라벨)".
- **실제**: 첫 화면 예산 때문에 통합이 렌더 파일을 load+idle 뒤로 미뤘고(보고 §3), 감속도 하이드레이션 뒤에야 `<img>` 를 붙인다 — 움직임을 끈 사람에게 0.1–0.4s 뒤 두 물체가 튀어나온다. 수용 단언("로드 직후 보임")은 통과.
- **고칠 방법**(예산은 그대로): 감속일 때만 CSS 배경으로 첫 페인트에 받기 — 미디어쿼리가 맞을 때만 배경 이미지를 요청하므로 기본 컨텍스트 바이트는 0.
  ```tsx
  // AingClip: 상자에 URL 을 변수로(SSR)
  <span className="aing-timer" style={{ ..., ['--art' as string]: `url(${timerMeta?.src})` }}>…</span>
  <div className="aing-bubble" style={{ ..., ['--art' as string]: `url(${bubbleSrc(bubble)})` }}>…</div>
  ```
  ```css
  /* globals — 감속에서는 배경이 최종 그림, img 층은 숨김(중복 그리기 방지) */
  @media (prefers-reduced-motion: reduce) {
    .aing-timer, .aing-bubble { background: var(--art) center / 100% 100% no-repeat; }
    .aing-timer > img, .aing-bubble > * { visibility: hidden; }
  }
  ```

### P2-7 행 가지 선의 '탁해짐'이 1.72s 에 끝난다(SPEC 900–1300) · 주 렌더 빈 창 불투명이 240ms(SPEC 320)
- **파일:줄**: `app/globals.css:208`(`stroke var(--t-dim) linear calc(var(--at) + 700ms)` — 600ms 가지면 1,300–1,700) · `:209`(`.row-item` opacity 240ms 를 주 렌더에도)
- **재현**: Chromium 1440×900, 행마다 새 페이지에서 노드를 68svh 아래 → 위로 넘기고 rAF 표본. `node .scratch/review-motion/rows2.mjs` → wireRestAt R1 1,721 · R2 1,744 · R3 1,725 · R5 1,717ms(R4 는 가지가 60ms 라 1,196).
- **기대**(SPEC §S4 4.1): 900–1300 선 `--wire-draw → --wire-rest`, 합계 1,300ms(R1 만 +380). 120–440 빈 창 불투명 320 선형.
- **실제**: 조립 자체는 1.26s 에 끝나는데 가지 선 색만 0.4s 더 바뀐다(눈에 덜 띄는 차이). 빈 창 불투명 120–360.
- **고칠 방법**:
  ```diff
  - ….wire { transition:stroke-dashoffset var(--t-draw) var(--ease-out) var(--at,0ms), stroke var(--t-dim) linear calc(var(--at,0ms) + 700ms); }
  + ….wire { transition:stroke-dashoffset var(--t-draw) var(--ease-out) var(--at,0ms), stroke var(--t-dim) linear max(900ms, calc(var(--at,0ms) + 200ms)); }
  + .js [data-row][data-on]:not([data-instant]) .row-item[data-kind="main"] { transition:opacity 320ms linear var(--at,0ms), scale 320ms var(--ease-out) var(--at,0ms); }
  ```

### P2-8 idle '2회'의 첫 바퀴가 45칸부터라 12.9s — 정지가 30.0s(SPEC 31.3s)
- **파일:줄**: `components/ui/AingClip.tsx:333–336`(`onIdleEnded` 가 이어 재생한 첫 바퀴도 1회로 셈)
- **재현**: 1440×900 실시간 34s 기록 `node .scratch/review-motion/hero.mjs 1440 900 --long` → idle ended 15,616(12.9s) · 30,014, `data-stopped` 30,018(`hero-1440x900/long.json`).
- **기대**(SPEC §S1 표): 2,500–31,300 "idle 14.4s × 2회".
- **실제**: 1.3s 일찍 멈춘다(자세 튐 없음 — 마지막 칸에서 정지, 34s/35.5s 캡처 동일).
- **고칠 방법**(싼 쪽): SPEC 표를 "반응 뒤 이어지는 첫 바퀴(45칸~끝) + 한 바퀴 → 정지(≈30.0s)"로 고친다. 코드로 맞추려면 이어 재생한 바퀴를 세지 않고 두 번째 끝(`ended`)이 아니라 세 번째 바퀴가 45칸에 닿을 때 `pause()`(rVFC 로 칸 감시) — 복잡도에 비해 이득이 작다.

---

## 2. 요청 항목별 판정(초록/빨강)

| 항목 | 판정 | 실측 |
|---|---|---|
| 히어로 도착 타임라인(빛 1.0s → 도착 → 말풍선 5s → idle 2회 → 그 프레임 정지) | 초록 | load 117 · run 218 · 도착 1,222(+1,004) · 반응 1,223–2,725 · idle 45칸부터 2,727 · 말풍선 해제 6,224(+5,002) · 정지 30,018 @14.4s, 포스터 불투명 0(`hero-1440x900/`) |
| 자세 튐(포스터↔영상 이음, 0.5s 캡처 + 실제 프레임) | 초록 | `contact-0.5s.png` · 프레임 차(알파 가중 RGB): 포스터↔반응0 1.43 · 반응끝↔idle45 2.40 · idle끝↔idle0 2.18 · idle포스터↔idle0 1.55 / 자연 한 칸 0.9–1.7(`seam/seam.json`, `pair-*.png`) · 빈 프레임 0(아잉 상자 밝은 화소 0.44–0.49 유지) · 390 은 15fps 22칸(1.5s)부터 |
| 2.5s 마감(영상만 늦춤) | **빨강** | P1-1 — 라벨만 켜지는 건 맞지만 빛이 먼저 다 달린다 |
| 처음 도착 전 이탈 → 도착 생략 | **빨강(부분)** | 로드 전 이탈·scrollY 300 은 초록, 빛 도중 이탈은 P1-4 |
| 돔 패럴랙스 | 초록 | 1440×900: scrollY 0/450/900 → translate 0/69.8/126px(=14svh) · 불투명 1/.64/.35, 선형·양방향, H1·아잉은 그냥 스크롤 · 1280×720 은 히어로 743 에서 끝 · 768·감속 `animation:none`(`parallax/parallax.json`) |
| 트립틱 sticky `top===0` | 초록 | scrollY 900·1,200·1,548·2,000·2,196 → 0, 850 → 50, 2,250 → −54 |
| 히스테리시스 .55/.62 | 초록 | 6px 걸음: 앞 0→1 1,198 · 1→2 1,846 / 뒤 2→1 1,778 · 1→0 1,130 · engaged 634/2,470(뒤 2,462/626) |
| 교체 267/333 | 초록 | 나감: 불투명 선형 1→0 277ms · scale 1→.94 · translate 0→−16 ease-in / 들어옴: 125ms 시작 → ~460 끝, .94→1 · +16→0 ease-out |
| 점등 450 + | 초록 | `data-lit` 455 · 말풍선 120ms · 무대 빛 +120 지연 후 800ms 선형(~1,390 에 1) · 오브젝트 3 은 잔디 910ms 뒤 빛 · 첫 점등 1,300ms |
| 되감김 | 초록 | 2→1·1→0: 나가는 것 아래로(+16), 들어오는 것 위에서(−16→0), 다시 점등 |
| 행 5개 조립 1.3s | 초록 | 모든 렌더·선·점 격자 최종 1,256–1,279ms(가지 선 색만 ~1.72s — P2-7) |
| 1회성(왕복 뒤 count 1) | 초록 | 5행 모두 "1", 재진입 시 전이 없이 최종 |
| R1 swap 1500ms | 초록 | `.swap-to` 불투명 1 at 1,705–1,711ms(1,500 + 180) |
| R3 ring flash | 초록 | 최대 .989 @625ms, 1,000ms 에 0 |
| GlowGate 경계 6곳 ≤ 1 | 초록(무대) / **빨강(목록)** | 1440×900·1280×720·1024×768 전 구간(+경계 600·660·행 경계·FAQ→아웃트로) > 1 0건 / 390·768·감속 1440 은 P1-2 |
| 감속 모션 전 구간 | 초록 | 1440·390: 영상 요청 0 · 돌던 애니메이션 = 바닥 빛 불투명 전이뿐 · 히어로 `data-instant`·말풍선/라벨 1 · 트립틱 목록·잔디 13·선 0px · 행 전부 최종(R1 read 판) · 아웃트로 진입 전부터 1 · `scroll-behavior:auto`(첫 페인트 '뿅'은 P2-6) |
| JS 없음 | 초록 | 1440·390: `.js` 없음 · 히어로 말풍선·라벨 `<noscript>` 그림 로드 · 빛 0 · 트립틱 목록 · 행 최종 · 아웃트로 1(패럴랙스는 순수 CSS 라 JS 없이도 돈다 — 무해) |
| 아웃트로 45% 진입 페이드 1회 · idle 2회 정지 | 초록 | 40% 불투명 0 → 47% 에서 0→1 ≈620ms 선형 → 왕복 뒤 즉시 1 · idle 0칸부터 2바퀴(14.4s×2, rate16 도 동일) → 14.4s 칸 정지, 포스터 0 · 포스터=idle 0칸이라 이음 차 1.55 |
| 스크롤 리스너 0 | 초록 | 코드 grep `addEventListener('scroll'`/`onScroll` 0 · CDP: window·html·body 0, document 의 캡처 scroll 1개는 React 루트 위임 리스너(react-dom, 핸들러 없음) · `nextjs-portal`(데브 오버레이 전용) 외 요소 0(`listeners/listeners.json`) |
| 불투명 선형 · 이동 ease-out/in · 오버슈트는 타일만 | 초록(예외 1) | 트립틱·행·히어로·아웃트로 표본 전부 선형 불투명, 행 주 렌더 scale 최대 1.0, 타일 1.039 · 예외: 말풍선 퇴장 scale 스냅(P2-5) |
| (추가) 빛 한 줄 판독성 | **빨강** | P1-3 |

---

## 3. 수리(⑦)에 넘기는 메모
- P1-1·P1-4 는 `HeroStage.tsx` 한 파일(+ AingClip 콜백 1개)이라 함께 고치는 게 싸다. 고친 뒤 T6(도착 3.5s·`data-run` 1회·`playbackRate 16` 정지)과 `deadline.mjs delay:4000|1500`·`leave.mjs` 를 다시 돌린다.
- P1-2 는 T9 가 1440 무대 모드만 재서 생긴 구멍 — 하네스 T9 에 390×844·768×1024·감속 1440 의 '경계 + 트립틱 구간' 위치를 더한다(`glow.mjs` 의 셈법: `.obj-glow`·`.floor-light` 중 유효 불투명 > .05 + 히어로 > .35 + 아웃트로 돔).
- P1-3 은 SPEC §S1 표의 '1000ms ease-out' 을 바꾸는 일이라 리드 확인 후. 코드 변경은 HeroStage 의 data-run 전이를 WAAPI 두 구간으로.
- D25-1(행 렌더 `<img>` 를 1,200px 근처에서 마운트)을 반영할 때: 문턱(68svh) 전에 이미지가 디코드되지 않으면 440–780ms 내용 페이드가 빈 창 위에서 끝나고 그림이 나중에 '뿅' 나온다 — 행의 `data-on` 을 주 렌더 `img.decode()` 뒤로 미루거나(문턱 지난 뒤 최대 300ms) 마운트 거리를 넉넉히(1,200px 이상) 유지할 것.

## 4. 범위 밖으로 본 것(판정에 넣지 않음)
- 갈래 C(로드 전 scrollY 300)에서 쓰지 않을 commute-start(151KB)를 받는다 — 바이트는 perf 렌즈 몫.
- 웹킷 영상 미재생은 환경 한계(D25-4, 사파리 실기는 사용자 몫).

## 5. 산출물(모두 `/Users/yesung/check/landing/.scratch/review-motion/`)
- 스크립트: `lib.mjs` · `hero.mjs` · `seam.mjs` · `deadline.mjs` · `leave.mjs` · `parallax.mjs` · `moments.mjs` · `rows2.mjs`(`rows.mjs` 는 행 사이 오염된 첫 판) · `glow.mjs` · `shots.mjs` · `reduced.mjs` · `reduced-paint.mjs` · `outro.mjs` · `listeners.mjs` · `comet.mjs` · `webkit.mjs`
- 타임라인 로그: `hero-1440x900/{log,long}.json` · `hero-390x844/log.json` · `deadline-*/log.json` · `leave/leave.json` · `parallax/parallax.json` · `moments/moments.json` · `rows/rows.json` · `glow/glow-*.json` · `reduced/{reduced,paint}.json` · `outro/outro.json` · `listeners/listeners.json` · `comet/comet.json` · `seam/seam.json` · `webkit/webkit.json`
- 캡처: `hero-1440x900/contact-0.5s.png`·`t*.png`·`full-*.png`·`stop-34s.png` · `deadline-*/contact-0.25s.png` · `comet/comet-100ms.png` · `seam/pair-*.png` · `shots/glow-*.png` · `reduced/*-fold.png`·`nojs-*-full.png` · `outro/outro-end-rate*.png` · `leave/{B-back,C-4.5s}.png` · `webkit/webkit-4s.png`
