# 아잉체크 랜딩 v2 — 병렬 구현 계획 (PLAN v2)

작성 2026-10-12 · 종합자 · 짝 문서: `docs/v2/SPEC.md`(디자인 정본 — 카피·좌표·토큰·수용 조건은 전부 거기), `docs/v2/DECISIONS.md`(어긋나면 이긴다). 이 문서는 **누가 어떤 파일을 만들고, 서로 무엇을 약속하고, 무엇으로 끝났다고 판정하는가**만 정한다.
프로젝트 루트: **`/Users/yesung/check/landing`**(Next 16.4.0 · React 19.3.0 · Tailwind 4.3 `@tailwindcss/turbopack` · TypeScript 5 · sharp). `landing/` 은 git 미추적이다(`?? landing/`). 저장소의 다른 폴더(`Sources/`·`Tests/` 등 다른 작업의 미커밋 변경)는 **읽지도 고치지도 않는다**(사실 확인이 필요한 에이전트도 SPEC 이 인용한 줄 번호만 믿는다).
v1 계획(`docs/PLAN.md`)과 같은 방식(계약 먼저 → 병렬 → 통합 → 리뷰 → 수리 → 독립 재검증)이고, 달라진 점은 §0 의 ①철거·⑥리뷰·⑧재검증 단계와 §7 의 수용 테스트 대상(클릭 대신 **스크롤 위치별 상태·리빌 1회성·감속 정지·보라 예산**)이다.

---

## 0. 단계

| 단계 | 누가(동시 인원) | 무엇 | 끝나는 조건(표식) | 예상 |
|---|---|---|---|---|
| ① 철거 | `teardown` 1명 | TD §5 P0–P5 그대로 + `lib/aing.ts` 보존 + `TimerCapsule` 삭제 + `motion` 제거 + v1 문서 머리표 | `npx tsc --noEmit`·`npx eslint .`·`node scripts/check-glyphs.mjs` exit 0 · `curl` `/`·`/licenses` 200 · `docs/v2/.teardown-done` | 40분 |
| ② 스캐폴드 | `core` · `assets` · `primitives` **3명 동시** | core: 계약 서명 **15분 안에** → `docs/v2/.contracts-done`, 그다음 토큰·globals·layout·내비·page 뼈대·섹션 자리표시자·lib 훅. assets: 새 크롭·말풍선 4x·포스터·근무 라벨·서브셋 3벌·generated json. primitives: Dome·AingClip·Wire·Tile·FloorLight·Gridlines·FeatureRow 엔진·재사용 부품 수정 | `.core-done` · `.fonts-done`(assets, 글꼴 먼저) · `.assets-done` · `.primitives-done` | 2–3시간 |
| ③ 검증 | `verify` 1명 | tsc · eslint · test:unit · check-glyphs · `next build` · dev 3000 에서 200 · 자리표시자 페이지 스크린샷(390/1440) · 콘솔 0 | `docs/v2/.verify-done` + 보고 | 30분 |
| ④ 섹션 | **6명 동시**: `hero` · `moments` · `rows-a` · `rows-b` · `facts-install` · `faq-outro` | 자기 파일만(§2). 명령은 `npx tsc --noEmit` + `npx eslint <자기 파일>` + 자기 순수 함수 `node --test` 뿐. 데브 서버는 **공유·읽기 전용**(스크린샷 가능, 재시작 금지) | 각자 §4 수용 조건 + tsc·eslint 0 + `docs/v2/.<agent>-done` | 2–3시간 |
| ⑤ 통합 | `integration` 1명 | requests 흡수 → `page.tsx` 조립 → 서브셋 소스 모드 재생성 → build → §7 수용 테스트 전부 → 예산 측정(prod 임시 서버) → OG 재촬영 → 리드 보고용 캡처 세트 | §7 전부 초록 + `docs/v2/.integration-done` + `docs/v2/integration-report.md` | 2–3시간 |
| ⑥ 리뷰 | **4명 동시**(읽기 전용): `review-design` · `review-motion` · `review-copy` · `review-perf-a11y` | 렌즈별로 SPEC 대조 + 실측. 코드는 고치지 않는다 | `docs/v2/reviews/<lens>.md`(결함마다 심각도 P0–P2 · 파일:줄 · 재현 · 고칠 방법) | 1시간 |
| ⑦ 수리 | `repair` 1명 | 리뷰 P0 → P1 → P2 순. P2 는 시간이 남을 때만. 고친 뒤 §7 다시 | 리뷰 P0·P1 0건 + §7 초록 + `docs/v2/.repair-done` | 1–2시간 |
| ⑧ 독립 재검증 | `reverify` 1명(①–⑦ 에 참여하지 않은 에이전트) | 깨끗한 상태에서 §7 전부를 처음부터 + 사파리 실기 HEVC 알파 확인 + 잔여 프로세스·파일 점검 | `docs/v2/verify-final.md`(초록/빨강 표 + 캡처 경로) | 1시간 |

- **표식 파일은 `docs/v2/` 아래 빈 파일**(`.gitignore` 의 `docs/.*-done` 패턴은 v2 하위 폴더도 덮지 않으므로 통합이 끝나면 지운다). v1 표식 `docs/.{assets,contracts,core,primitives-a,primitives-b}-done` 은 ① 에서 지운다(TD §0.1-6).
- 기다리기: `while [ ! -f docs/v2/.contracts-done ]; do sleep 20; done`(최대 40분, 넘으면 보고하고 멈춘다). 기다리는 동안 자기 파일 초안은 써도 되지만 `tsc` 는 돌리지 않는다.
- 모든 단계의 공통 규칙은 §10(에이전트 머리말).

### 0.1 단계별 세부

**① 철거(`teardown`)** — TD §5 의 P0–P5 를 순서대로. 더할 것:
1. P1(새 파일) 에 **`lib/aing.ts`** 를 만든다: `components/ui/CharacterStage.tsx:121–146`(JSDoc 포함) 의 `idleResumeFrame()`·`reactionBox()` 를 **그대로 복사**(순수 함수, import 0) + `lib/aing.test.ts`(`idleResumeFrame(45, 432, 30, 30, 432) === 45`, `(45, 432, 30, 15, 216) === 22`, `reactionBox(null, [654,790], .5)` 등 4건). P3 에서 원본이 지워지므로 반드시 P3 전에.
2. P3 삭제 목록에 `components/ui/TimerCapsule.tsx` 추가(사용처 0 — 근무 라벨은 렌더로, SPEC §6.2).
3. P5 에서 `package.json` 의 `test:store` 삭제 + **`npm uninstall motion`**(사용처 0 을 `grep -rn "from \"motion\|from 'motion" app components lib` 로 먼저 확인). `test:unit` 은 core 가 넣는다.
4. `data/fixtures.ts` 는 TD §2.9 까지만(HOTSPOTS·REACTION_SEQ·ANNOUNCE/TIMING 정리). v2 추가는 core 몫.
5. `README.md`·v1 `docs/{SPEC,PLAN,DECISIONS}.md`·`docs/requests/*.md` 머리표(TD §1.5) — README 의 정본 경로는 `docs/v2/{SPEC,PLAN,DECISIONS}.md`.
6. 끝나면 `/` 는 푸터만 남은 빈 페이지다(TD §0.1-10). **곧바로 ② 가 시작돼야 한다** — 오케스트레이터는 ① 과 ② 를 한 묶음으로 띄운다.

**② 스캐폴드** — §2 소유권대로 세 명이 동시에.
- `core` 순서: (a) 계약(≤15분): `data/fixtures.ts`(SPEC §6.3 전부 — 새 `AssetKey` 11개·`ALT`·`HERO`·`MOMENTS_TIMING`·`ROW_TIMING`, `PANELS`·`LABELS`·`PHONE`·v1 `ALT` 삭제, `RELEASE_FALLBACK` 을 0.3.49 값으로 — DECISIONS D18), `data/figures.ts`(SPEC §6.4 전문), `lib/hooks.ts` 추가 서명, `lib/moments.ts` 서명(본문은 임시여도 됨), `lib/platform.ts`(`js` 클래스) → `touch docs/v2/.contracts-done`. (b) `app/globals.css`(SPEC §2.8 **글자 그대로**), `components/site/{SiteNav,NavShell}.tsx`, `data/site-links.ts` NAV_LINKS, 섹션 자리표시자 9개(§6-2), `app/page.tsx`(§3.10 모양, 자리표시자 import), `lib/moments.ts`·훅 본구현 + `lib/moments.test.ts`, `package.json` `test:unit`. (c) **`.fonts-done` 이 생긴 뒤에만** `app/layout.tsx` 를 새 글꼴 3벌로 바꾼다(없는 파일을 가리키면 데브 서버가 깨진다) → `touch docs/v2/.core-done`.
- `assets` 순서: (a) `scripts/subset-fonts.mjs`·`check-glyphs.mjs` 를 SPEC §9.5 대로 고치고 `node scripts/subset-fonts.mjs --from-spec` → `public/fonts/pretendard-{500,600}-sub.*`·`pretendard-300-num.*` → `touch docs/v2/.fonts-done`(목표 30분). (b) `scripts/build-assets.mjs` 에 SPEC §9.2·§9.3 레시피 → `node scripts/build-assets.mjs --only=ui,data`(영상 재인코딩 없음 — 포스터·근무 라벨도 ui 묶음에서 굽는다) → 바이트 표·배지 감사 접촉 시트(`landing/.scratch/assets/badges.png`) → `touch docs/v2/.assets-done`.
- `primitives`: `.contracts-done` 을 기다린 뒤 §3 서명대로. `lib/aing.ts` 에 `heroLayer()`·`shouldStop()` 추가 + 테스트.
- 스캐폴드 단계의 `next build` 는 **verify 만**. core·assets·primitives 는 `npx tsc --noEmit`·`npx eslint <자기 파일>`·자기 스크립트 실행까지.

**③ 검증(`verify`)** — 세 표식이 모두 생긴 뒤. 명령은 하나씩 exit code 로(§10-6):
```sh
cd /Users/yesung/check/landing
npm run typecheck ; echo "tsc=$?"
npm run lint ; echo "lint=$?"
npm run test:unit ; echo "unit=$?"
node scripts/check-glyphs.mjs ; echo "glyphs=$?"
npm run build ; echo "build=$?"          # Next 16: build 는 .next/, dev 는 .next/dev — 데브 서버와 동시에 돌아도 된다
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3000/          # 200
node $H/shoot.mjs http://localhost:3000 $H/out/verify --widths 390,1440   # H = …/scratchpad/tools (v1 하네스)
```
실패하면 고치지 말고 원인 파일·소유자를 적어 오케스트레이터에 돌려준다(소유자가 고친다).

**④ 섹션** — §4 계약대로. 공용 API 를 바꾸고 싶으면 `docs/v2/requests/<agent>.md` 에 (무엇을 · 왜 · 제안 diff) 를 적고 **자기 폴더 안 로컬 우회**로 진행한다(통합이 흡수).

**⑤ 통합(`integration`)** — 순서: requests 처리(공용 파일 수정 권한은 통합에만) → `page.tsx` 최종 조립 → `npm run subset`(소스 모드) → §③ 명령 전부 → 데브 3000 에서 §7 의 동작 테스트 → `npm run build && npx next start -p 3100`(백그라운드, **측정 끝나면 kill**, `lsof -i :3100` 비어 있음 확인) 으로 T13 예산 → OG 재촬영(SPEC §8) → 캡처 세트(§7.3) → `integration-report.md` → 잔여 프로세스·파일 점검(§6-8).

**⑥ 리뷰** — 렌즈별 체크리스트(각자 SPEC 해당 절과 §7 결과를 읽고 데브 3000·prod 3100 캡처로 확인. 3100 이 필요하면 리뷰어가 띄우고 끈다 — 동시에 둘 이상 띄우지 않게 `review-perf-a11y` 만):
| 렌즈 | 본다 |
|---|---|
| design | 기억에 남을 하나(첫 2초)가 SPEC §1.2 대로인가 · 한 화면 큰 것 하나 / 글로우 하나 · 보라 예산 · 타입 스케일·줄바꿈 `lines` · 구도 리듬 · 렌더 덧그리기 0 · 배지 감사 · 1440×789 |
| motion | 도착 타임라인·2.5s 마감·idle 2회 정지(자세 튐 없음) · 패럴랙스 · 트립틱 sticky·히스테리시스·교체 267/333·점등 · 행 1.3초·1회성·되감김 없음 · GlowGate 경계 · 감속 모션 전 구간 |
| copy | 모든 문장 = CB 줄(표본 30 이상) · 금지어 · 신규 문구는 §1.4.3 뿐 · 줄바꿈 · alt 문구 · 숫자 출처 |
| perf-a11y | 첫 화면 KB·전체 MB·LCP·CLS(prod) · 영상 요청 규율 · 헤딩·랜드마크·alt·포커스·Tab 순서·대비 · 가로 넘침 · sticky 조상 · 콘솔 |

**⑦ 수리 · ⑧ 재검증** — §6 규칙 그대로. 재검증자는 코드를 고치지 않고 판정만 한다(빨강이면 오케스트레이터가 ⑦ 로 되돌린다).

---

## 1. 디렉터리 구조(최종)

```
landing/
  package.json  tsconfig.json  next.config.ts  eslint.config.mjs  vercel.json  next-env.d.ts  AGENTS.md  .gitignore
  app/
    layout.tsx                 # core — 글꼴 3+1, 메타, PlatformScript, themeColor #0C0A14
    globals.css                # core — SPEC §2.8 그대로
    page.tsx                   # core(자리표시자) → integration(최종)
    icon.png  apple-icon.png   # assets(그대로)
    opengraph-image.png  opengraph-image.alt.txt   # integration(재촬영)
    licenses/page.tsx          # faq-outro(teardown 이 import 만 고침)
    robots.ts  sitemap.ts  api/download/route.ts  api/release/route.ts   # 그대로
  components/
    SpritePlayer.tsx  sprite/AlphaVideo.tsx  sprite/SheetPlayer.tsx       # 그대로(AingClip 이 씀)
    site/
      SiteNav.tsx  NavShell.tsx  useHeroCtaVisible.ts                     # core
      SiteFooter.tsx  LicensesNav.tsx  FaqHash.tsx                        # faq-outro
    ui/
      Button.tsx AppStoreBadge.tsx QrCode.tsx TextLink.tsx VisuallyHidden.tsx PlatformScript.tsx
      MacWindowShell.tsx PhoneShell.tsx CommandBox.tsx CopyButton.tsx LiveAnnouncer.tsx       # primitives(필요한 수정만)
      DownloadCTA.tsx Headline.tsx RenderImage.tsx Bubble.tsx                                  # primitives(수정)
      Dome.tsx AingClip.tsx Wire.tsx Tile.tsx FloorLight.tsx Gridlines.tsx                     # primitives(신규)
    features/
      FeatureRow.tsx  RowCanvas.tsx  Rail.tsx                             # primitives(엔진)
      FeaturesIntro.tsx  RowsA.tsx  rows-a.data.ts                        # rows-a
      RowsB.tsx  rows-b.data.ts                                           # rows-b
    hero/      Hero.tsx  HeroStage.tsx  comet-path.ts  comet-path.test.ts  copy.ts            # hero
    moments/   Moments.tsx  MomentsStage.tsx  MomentObject.tsx  GrassReveal.tsx  moments.css  copy.ts   # moments
    facts/     Facts.tsx                                                  # facts-install
    install/   Install.tsx                                                # facts-install
    faq/       Faq.tsx                                                    # faq-outro
    outro/     Outro.tsx  OutroStage.tsx                                  # faq-outro
  lib/
    hooks.ts  moments.ts  moments.test.ts  platform.ts                    # core
    aing.ts  aing.test.ts                                                 # teardown 생성 → primitives
    announce.ts                                                           # teardown(그대로)
    release.ts  site.ts  media.ts                                         # 그대로(site.ts OG alt 만 integration)
    grass/grass-data.ts  grass/grass-geometry.ts                          # moments(쓰지 않으면 삭제)
  data/
    fixtures.ts  figures.ts  site-links.ts                                # core
    install-copy.ts                                                       # facts-install
    faq-items.ts                                                          # faq-outro
    generated/assets.json  sequences.json  bubbles.json  grass.json       # assets(스크립트가 씀)
  scripts/  build-assets.mjs  subset-fonts.mjs  check-glyphs.mjs  make-qr.py   # assets
  public/
    assets/{ui,char,ios,brand}/…                                          # assets
    fonts/pretendard-500-sub.{woff2,txt}  pretendard-600-sub.{woff2,txt}  pretendard-300-num.{woff2,txt}
          jbm-400-ascii.woff2  LICENSE-*.txt                              # assets
  docs/
    content-brief.md  asset-manifest.md  SPEC.md PLAN.md DECISIONS.md(v1, 머리표)  requests/(v1)
    v2/ brief.md reference-analysis.md teardown.md candidates/ judging/
        SPEC.md PLAN.md DECISIONS.md  requests/<agent>.md  reviews/<lens>.md
        integration-report.md  verify-final.md  .<단계>-done
  .scratch/<agent>/                                                       # gitignore — 각자 전용
```
삭제(① 이후 존재하지 않음): `components/sections/**` · `lib/demo/**` · `components/ui/{AingStageInline,CharacterStage,Hotspot,PanelSlot,RenderStack,SectionShell,Segmented,TickStrip,TimeMark,TimerCapsule}.tsx` · `public/fonts/pretendard-800-sub.*`(assets 가 ② 에서).

---

## 2. 파일 소유권(쓰기 가능한 경로 — 겹침 0)

| 에이전트 | 쓸 수 있는 파일 | 읽기만 |
|---|---|---|
| `teardown` | TD §5 의 이동·삭제·수정 대상 전부 + `lib/aing.ts`·`lib/aing.test.ts`·`lib/announce.ts` 생성 · `package.json`(test:store·motion) · `README.md` · v1 `docs/*.md` 머리 한 줄 · `docs/requests/*.md` 머리 한 줄 · v1 표식 삭제 | — |
| `core` | `app/{globals.css,layout.tsx,page.tsx}` · `components/site/{SiteNav,NavShell,useHeroCtaVisible}.*` · `lib/{hooks,moments,moments.test,platform}.ts` · `data/{fixtures,figures,site-links}.ts` · 섹션 자리표시자 9개(② 에서만 — ④ 에서 소유가 섹션으로 넘어간다) · `package.json` scripts(`test:unit`) · `tsconfig.json`·`eslint.config.mjs`·`next.config.ts`(필요할 때만 최소) | 전부 |
| `assets` | `scripts/**` · `public/assets/**` · `public/fonts/**` · `data/generated/*.json` · `app/{icon,apple-icon}.png` · `vercel.json` · `landing/.scratch/assets/` | 전부 |
| `primitives` | `components/ui/**`(위 표 §1) · `components/features/{FeatureRow,RowCanvas,Rail}.tsx` · `lib/aing.ts`·`lib/aing.test.ts` | 전부 |
| `hero` | `components/hero/**` | 전부 |
| `moments` | `components/moments/**` · `lib/grass/**` | 전부 |
| `rows-a` | `components/features/{FeaturesIntro,RowsA}.tsx` · `components/features/rows-a.data.ts` | 전부 |
| `rows-b` | `components/features/RowsB.tsx` · `components/features/rows-b.data.ts` | 전부 |
| `facts-install` | `components/{facts,install}/**` · `data/install-copy.ts` | 전부 |
| `faq-outro` | `components/{faq,outro}/**` · `components/site/{SiteFooter,LicensesNav,FaqHash}.tsx` · `data/faq-items.ts` · `app/licenses/page.tsx` | 전부 |
| `integration` | 위 전부(공용 파일 수정은 requests 를 근거로) · `app/opengraph-image.{png,alt.txt}` · `lib/site.ts`(OG alt) · `docs/v2/integration-report.md` | — |
| `review-*` | `docs/v2/reviews/<lens>.md` 하나 | 전부 |
| `repair` | 리뷰가 가리킨 파일(소유권 무시, 통합과 같은 권한) | — |
| `reverify` | `docs/v2/verify-final.md` 하나 | 전부 |
- 모든 에이전트: `docs/v2/requests/<agent>.md`(자기 이름) · `docs/v2/.<agent>-done` · `landing/.scratch/<agent>/`.
- **섹션 에이전트가 자기 섹션의 자리표시자 파일을 받는다**: 예) core 가 ② 에서 만든 `components/hero/Hero.tsx` 는 ④ 에서 `hero` 가 덮어쓴다(같은 export 이름·props 유지 — §3.10).

---

## 3. 공용 API(스캐폴드가 이 서명 그대로 만든다)

### 3.1 `lib/hooks.ts`(core — 기존 유지 + 추가)
```ts
export const MQ_DESK = '(min-width: 1024px) and (min-height: 640px)';
export const MQ_TAB = '(min-width: 768px) and ((max-width: 1023.98px) or (max-height: 639.98px))';
export const MQ_PHONE = '(max-width: 767.98px)';
export const MQ_REDUCED = '(prefers-reduced-motion: reduce)';
export const MQ_STAGE = '(min-width: 1024px) and (min-height: 640px) and (prefers-reduced-motion: no-preference)'; // 신규
export type ViewportMode = 'desk' | 'tab' | 'phone';
export function viewportModeNow(): ViewportMode;
export function saveDataNow(): boolean;           // 수정: saveData || effectiveType ∈ {'slow-2g','2g','3g'}
export function useViewportMode(): ViewportMode;
export function useReducedMotion(): boolean;
export function useSaveData(): boolean;
export function usePosterOnly(): boolean;         // reduced || saveData
export function useMediaQuery(query: string): boolean;   // 신규. SSR·첫 렌더 false
export function useNearViewport(ref: RefObject<Element | null>, rootMargin?: string): boolean; // 한 번 true 면 유지
export function useInViewRatio(ref: RefObject<Element | null>, ratio: number): boolean;        // 양방향(그대로)
/** 신규 — 문턱 1회. 요소 윗변이 화면 위에서 line·innerHeight 를 지나면 on(이후 고정).
 *  마운트 때 이미 지나 있으면 { on: true, instant: true }. IO rootMargin = `0px 0px -${(1-line)*100}% 0px`. */
export function useRevealOnce(ref: RefObject<Element | null>, line?: number /* .68 */): { on: boolean; instant: boolean };
/** 신규 — GlowGate. 요소(보통 높이 0 표식)가 화면 [band[0], band[1]] 비율 띠 안이면 true(양방향).
 *  IO rootMargin = `-${band[0]*100}% 0px -${(1-band[1])*100}% 0px`. */
export function useBand(ref: RefObject<Element | null>, band?: readonly [number, number] /* [.3, .7] */): boolean;
// 삭제: useEnterTimer, useCenterLine(쓰는 곳 0 — 통합이 확인 후)
```

### 3.2 `lib/moments.ts`(core)
```ts
export type MomentsThresholds = { forward: number; back: number };   // 기본 MOMENTS_TIMING { .55, .62 }
/** 순수. numberTops[i] = i번 카드 큰 숫자의 화면 기준 윗변(px). prev = -1 이면 아직 활성 없음.
 *  앞으로: numberTops[prev+1] < forward·vh 인 동안 한 칸씩 / 뒤로: numberTops[prev] > back·vh 인 동안 한 칸씩(최소 -1). */
export function nextActive(prev: number, numberTops: readonly number[], vh: number, t?: MomentsThresholds): number;
/** 순수. 섹션 상자로 engaged 판정: top ≤ .30·vh && bottom ≥ .70·vh */
export function isEngaged(sectionTop: number, sectionBottom: number, vh: number): boolean;
/** 훅. enabled=false(목록 모드)면 { active: -1, engaged: false } 고정. 스크롤 리스너 없이
 *  IO(카드 숫자 3개 + 섹션, thresholds [0,.25,.5,.75,1]) 콜백에서 getBoundingClientRect 를 읽어 위 두 순수 함수로 갱신. */
export function useActiveCard(
  sectionRef: RefObject<HTMLElement | null>,
  numberRefs: readonly RefObject<HTMLElement | null>[],
  enabled: boolean,
): { active: number; engaged: boolean };
```
`lib/moments.test.ts` 필수 사례(1440×900, SPEC §S2 기댓값): scrollY 549·1,197·1,845 에서 0·1·2, 1,845→1,800 에서 2 유지, 1,700 에서 1, 0 에서 -1 · `isEngaged` 630/2,466 경계.

### 3.3 `lib/aing.ts`(teardown 생성 → primitives 소유)
```ts
export function idleResumeFrame(n: number, idleFrames: number, idleFps: number, variantFps: number, variantFrames: number): number; // v1 그대로
export function reactionBox(offsetOut: readonly [number, number] | null, sizeOut: readonly [number, number], d: number):
  { left: number; top: number; width: number; height: number };                                                                // v1 그대로
export type Rect = { left: number; top: number; width: number; height: number };
/** 히어로 아잉 상자 폭 w(CSS px) → 말풍선·근무 라벨 상자. d = w/654, CORNER.bubbleAtOut·capsuleAtOut·capsuleSizeOut, 말풍선 크기 = bubbleSize(id, d). */
export function heroLayer(w: number, bubbleCanvasPx: readonly [number, number]): { bubble: Rect; timer: Rect };
export function shouldStop(loopsDone: number, maxLoops: number): boolean;   // loopsDone >= maxLoops
```

### 3.4 공용 프리미티브 `components/ui/*`(primitives — props 확정)
```ts
// Dome.tsx (server) — aria-hidden. SPEC §2.8 .dome / .dome--small / .dome-pool
export interface DomeProps { variant: 'hero' | 'small'; pool?: { bottom: number | string }; className?: string }

// AingClip.tsx (client) — 클릭 없음(pointer-events:none), 루트에 data-aing · data-arrived · data-bubble · data-stopped · data-instant
export interface AingClipProps {
  width: string;                                  // CSS 길이, 예: 'var(--aing-w)'. 높이 = 폭 × 790/654
  poster: 'char/aing-rest-poster' | 'char/aing-idle-poster';
  once?: 'aing-commute-start';                    // start 때 한 번 재생할 반응(없으면 곧바로 idle)
  start: boolean;                                 // 부모의 '이제' 신호(히어로: 빛 한 줄 끝 / 아웃트로: 45% 진입). false→true 한 번만 의미
  maxLoops?: number;                              // 기본 HERO.idleLoops = 2 → 끝나면 그 프레임에서 pause(포스터로 바꾸지 않음)
  inView: boolean;                                // 보이는 비율 ≥ .35 — false 면 pause, true 면 남은 횟수만 이어서
  posterOnly: boolean;                            // usePosterOnly() — true 면 영상 요청 0, data-arrived·data-bubble 즉시 붙이고 해제하지 않음(= 감속 판 정지 상태)
  bubble?: 'commute-start';                       // once 시작과 같은 순간 data-bubble, BUBBLE_TEXT ms(5,000) 뒤 해제
  timer?: boolean;                                // 근무 라벨(ui/timer-00-00) — once 시작 순간 data-arrived(이후 유지)
  deadlineAt?: number;                            // performance.now() 기준 마감. 그때까지 once 가 canplay 가 아니면 once·bubble 건너뛰고 data-arrived 만
  onArrive?(): void;
  onOnceReady?(): void;                           // 수리 ⑦(DECISIONS D28-1): once 가 재생 가능해진 순간 한 번 — 히어로 빛 한 줄의 출발 신호
  onStop?(): void;
  className?: string;
}
// 내부: SpritePlayer(once) + SpritePlayer(idle, loop=false 로 두고 ended 마다 loopsDone++ → shouldStop 이면 멈춤),
//       once 끝 → idle 을 idleResumeFrame(45, …) 칸으로 seek 후 층 교체(TD §3). visibilitychange 일시정지.
//       층: .aing-bubble(Bubble static) · .aing-timer(<img ui/timer-00-00>) — 상자는 heroLayer(w).

// Wire.tsx (server) — <path class="wire" pathLength="100" style={{'--at': at+'ms'}} d={d} />. 부모 <svg> 는 RowCanvas 가 만든다
export interface WireProps { d: string; at?: number }
// Tile.tsx (server)
export interface TileProps { icon: AssetKey; bare?: boolean /* 앱 아이콘 그대로(그림자만) */; at?: number }
// FloorLight.tsx (client 아님 — data-glow 값은 부모가 준다)
export interface FloorLightProps { width: number; top: number; on: boolean }   // <div class="floor-light" data-glow={on?'on':'off'} aria-hidden>
// Gridlines.tsx (server)
export interface GridlinesProps { lines?: 'all' | 'left' }

// 재사용 수정
type Placement = 'nav' | 'hero' | 'install' | 'outro';
export interface DownloadCTAProps { placement: Placement; size: 'l' | 's'; tone?: 'fill' | 'outline'; label?: string;
  file?: 'dmg' | 'zip'; ariaLabel?: string; className?: string; installHref?: string }       // server 컴포넌트, iOS 규칙 SPEC §6.2
type HeadlineSize = 'display' | 'closing' | 'h2' | 'h2-solo' | 'h3' | 'h4' | 'caption' | 'facts-title';
export interface HeadlineProps { level: 1 | 2 | 3 | 4; size: HeadlineSize; lines: readonly string[]; id?: string; className?: string } // lines → <br>
export interface RenderImageProps { asset: AssetKey; widthPt: number; heightPt: number; alt: string; eager?: boolean; className?: string;
  scale?: number; style?: CSSProperties; id?: string; fetchPriority?: 'high'; fade?: Fade }   // fade = mask-image 가장자리 px
type Fade = { left?: number; bottom?: number; notch?: { solid: number; height: number } };   // 수리 ⑦(D27-3): notch = 머리띠(위 height px)만 왼쪽 solid px 완전 투명 + left px 페이드
export interface BubbleProps { id: BubbleKey; scale: number; visible: boolean; static?: boolean; className?: string; style?: CSSProperties } // onClick·ariaLabel 삭제
```

### 3.5 기능 행 엔진 `components/features/*`(primitives)
```ts
export type Box = readonly [x: number, y: number, w: number, h: number];   // 캔버스 px(576 기준)
export type CanvasItem =
  | { kind: 'main'; asset: AssetKey; alt: string; box: Box; at: number; fade?: { left?: number; bottom?: number };
      swapTo?: { asset: AssetKey; alt: string; at: number }; ringFlash?: boolean }
  | { kind: 'child'; asset: AssetKey; alt: string; box: Box; at: number; fade?: { left?: number } }
  | { kind: 'bubble'; bubble: BubbleKey; box: Box; at: number }
  | { kind: 'phone'; screen: AssetKey; alt: string; box: Box; screenWidth: number; at: number }
  | { kind: 'junction'; point: readonly [number, number]; at: number };
export interface RowCanvasSpec {
  height: number;                                   // ≤ 480
  items: readonly CanvasItem[];
  wires: readonly { d: string; at: number }[];
  tile?: { box: readonly [number, number]; icon: AssetKey; bare?: boolean };
  floor: { width: number; top: number };
}
export interface FeatureRowProps {
  id: `f-${string}`;
  kicker: string;                                   // 한글 라벨(SPEC §S4)
  title: readonly string[];                         // H3 lines
  body: string;
  sub?: { title: readonly string[]; body: string }; // H4 + 본문
  note?: string;                                    // t-small ink-3
  canvas: RowCanvasSpec;
}
export function FeatureRow(p: FeatureRowProps): JSX.Element;
// 수리 ⑦(D25-1): RowCanvas 에 mount(= useNearViewport(root, '1200px')) — false 면 렌더 <img> 는 <noscript> 폴백만(첫 화면 예산)
// client. 루트 <article id data-row data-on? data-instant? data-reveal-count> — useRevealOnce(nodeRef, ROW_TIMING.threshold)
//   한 번 on 이면 data-reveal-count="1" 로 고정(되감기 없음). 바닥 빛은 useBand(markerRef) → FloorLight on.
//   phone 은 캔버스 대신 세로 묶음(SPEC §S4 390), tab 은 scale k. Rail(토막+노드)을 자기 왼쪽에 그린다.
export function Rail(p: { head?: boolean }): JSX.Element;   // server. head = 기능 절 제목의 머리 점 + 첫 토막(늘 켜짐)
```

### 3.6 데이터 `data/*`(core)
- `fixtures.ts`: SPEC §6.3 표 그대로. `AssetKey` 는 손으로 적은 유니언(v1 DECISIONS §4 승계), 새 키 11개 포함.
- `figures.ts`: SPEC §6.4 전문. **`.t-number`·`.t-facts` 에 넣는 문자열은 이 타입만**(`FigureString`).
- `site-links.ts`: `FOOTER_LINKS`(그대로) · `NAV_LINKS = [{ href:'/#features', label:'기능' }, { href:'/#install', label:'설치' }, { href:'/#faq', label:'자주 묻는 것' }]`.

### 3.7 서버 · 라우트(그대로)
`lib/release.ts`: `getRelease(): Promise<ReleaseInfo>`(3초 타임아웃·1시간 revalidate·실패 시 `RELEASE_FALLBACK`) · `formatMB` · `downloadTarget`. `data/install-copy.ts`: `installChoice(release, fallback)` → `{ file: 'dmg'|'zip'; label; mb; version }`.

### 3.8 생성 데이터
`data/generated/assets.json`(키 = AssetKey, `{src,w,h,bytes}`) · `sequences.json`(그대로) · `bubbles.json`(`canvasPx` 불변 — SPEC §9.3) · `grass.json`(그대로). 읽는 쪽은 `as Record<string, …>` 로 느슨하게, 키가 없으면 개발 모드 경고 + 명시 크기의 빈 `<img alt>`(v1 DECISIONS §4).

### 3.9 글꼴(`app/layout.tsx`, core)
```ts
const ptd500 = localFont({ src: '../public/fonts/pretendard-500-sub.woff2', weight: '500', display: 'swap', preload: true,  variable: '--font-ptd-500',
  fallback: ['-apple-system', 'BlinkMacSystemFont', 'Apple SD Gothic Neo', 'system-ui'] });
const ptd600 = localFont({ src: '../public/fonts/pretendard-600-sub.woff2', weight: '600', display: 'swap', preload: false, variable: '--font-ptd-600', fallback: [...] });
const ptd300n = localFont({ src: '../public/fonts/pretendard-300-num.woff2', weight: '300', display: 'swap', preload: true, variable: '--font-ptd-300n' });
const jbm = localFont({ src: '../public/fonts/jbm-400-ascii.woff2', weight: '400', display: 'swap', preload: false, variable: '--font-jbm' });
export const viewport: Viewport = { themeColor: '#0C0A14', colorScheme: 'dark' };
// <html lang="ko" className={`${ptd500.variable} ${ptd600.variable} ${ptd300n.variable} ${jbm.variable}`} data-scroll-behavior="smooth" suppressHydrationWarning>
// <head><PlatformScript/> + <link rel="preload" as="image" href={asset('char/aing-rest-poster').src} fetchPriority="high"/></head>
```

### 3.10 `app/page.tsx`(core 자리표시자 → integration 최종 — 모양 고정)
```tsx
import { getRelease } from '@/lib/release';
import { SiteNav } from '@/components/site/SiteNav';
import { Hero } from '@/components/hero/Hero';
import { Moments } from '@/components/moments/Moments';
import { FeaturesIntro } from '@/components/features/FeaturesIntro';
import { RowsA } from '@/components/features/RowsA';
import { RowsB } from '@/components/features/RowsB';
import { Facts } from '@/components/facts/Facts';
import { Install } from '@/components/install/Install';
import { Faq } from '@/components/faq/Faq';
import { Outro } from '@/components/outro/Outro';
import { SiteFooter } from '@/components/site/SiteFooter';
import { LiveAnnouncer } from '@/components/ui/LiveAnnouncer';

export const revalidate = 3600;
export default async function Page() {
  const release = await getRelease();
  return (<>
    <SiteNav />
    <main id="main">
      <Hero release={release} />
      <Moments />
      <FeaturesIntro />
      <RowsA />
      <RowsB />
      <Facts release={release} />
      <Install release={release} />
      <Faq />
      <Outro />
    </main>
    <SiteFooter />
    <LiveAnnouncer />
  </>);
}
```
섹션 export 서명(자리표시자도 같게): `Hero({ release }: { release: ReleaseInfo })` · `Moments()` · `FeaturesIntro()` · `RowsA()` · `RowsB()` · `Facts({ release })` · `Install({ release })` · `Faq()` · `Outro()` — 전부 named export, server 컴포넌트(안에서 client 섬을 쓴다).

---
## 4. 섹션 계약(④ 단계 6명)

공통: 카피·좌표·수용 조건은 SPEC 해당 절이 정본. 섹션 파일은 server 컴포넌트로 시작해 움직이는 부분만 client 섬으로 쪼갠다. 색·빛·움직임은 globals 의 변수·클래스로(새 색 금지), 배치만 Tailwind. 명령은 `npx tsc --noEmit` + `npx eslint <자기 파일들>` + (있으면) `node --experimental-strip-types --test <자기 테스트>` 뿐. 데브 서버 3000 은 보기만(아래 §9).

### 4.1 `hero` — `components/hero/**` · SPEC §S1
- **입력**: `{ release: ReleaseInfo }`(버튼 접근 이름의 크기).
- **쓴다**: `Dome variant="hero"` · `RenderImage`(라벨 `ui/menubar-0000-lg`) · `Headline level={1} size="display"` · `DownloadCTA placement="hero"` · `AppStoreBadge height={48}` · `AingClip`(poster `char/aing-rest-poster`, once `aing-commute-start`, bubble `commute-start`, timer, `deadlineAt = 2500`(내비게이션 시작 기준)) · `useInViewRatio(.5)`·`(.35)` · `useMediaQuery(MQ_STAGE)` · `usePosterOnly()` · `afterLoadIdle`.
- **만든다**: `Hero.tsx`(server: 섹션·돔·라벨·글·버튼·메타 + `<HeroStage/>`) · `HeroStage.tsx`(client: 빛 한 줄 SVG + AingClip 오케스트레이션 — 조건이 맞으면 `.comet[data-run]` → 1000ms 뒤 `start=true`, `.comet[data-done]`) · `comet-path.ts`(순수 `cometPath(dome: {cx,cy,r}, end: {x,y}, leaveDy = 80): string`) · `comet-path.test.ts`(1440×900·1440×789·1024×768 의 글자 줄 상자를 고정값으로 넣고, 경로 표본 200점이 그 상자들과 12px 이상 떨어짐 · 시작점 = 돔 꼭대기 · 끝점 = 말풍선 왼쪽 가운데 − 8) · `copy.ts`(SPEC 문장).
- **`<section id="top" data-hero-cta-scope>`**, 버튼 줄에 `data-hero-cta`(내비 `useHeroCtaVisible` 이 본다), H1 `id="hero-h1"`.
- **수용**: SPEC §S1 수용 조건 전부(T5·T6 이 단언). 스스로는 tsc·eslint·`comet-path.test.ts` + 데브 3000 캡처 1440×900·1440×789·390 각 1장(`landing/.scratch/hero/`).
- **금지**: SPEC §S1 금지 목록. 스크롤 리스너. `transform` 을 `#top` 바깥 조상에 거는 것(sticky 규칙).

### 4.2 `moments` — `components/moments/**` · `lib/grass/**` · SPEC §S2
- **입력**: 없음.
- **쓴다**: `useActiveCard()`·`isEngaged()`(core) · `useMediaQuery(MQ_STAGE)` · `RenderImage` · `Bubble static` · `Gridlines lines="left"` · `preloadImage`(lib/media) · `FIGURES.start/poke/records` · `MOMENTS_TIMING`.
- **만든다**: `Moments.tsx`(server: 섹션 + 카드 3장(SSR, 인라인 오브젝트 포함) + `<MomentsStage/>` + `import './moments.css'`) · `MomentsStage.tsx`(client: 무대 래퍼 — 무대 모드일 때만 오브젝트 2·3 마운트, `data-active`·`data-lit`·`data-glow` 갱신, 숫자 ref 는 카드에서 `data-moment-number` 로 찾는다) · `MomentObject.tsx`(오브젝트 1·2·3 — `lit` prop 으로 선·링·말풍선) · `GrassReveal.tsx`(`--cols` 0→13 을 70ms 계단, `instant` 면 13) · `moments.css`(교체·점등·카드 배치 — 이 섹션 전용 전역 CSS, 클래스 접두 `.moments-`·`.moment-`·`.obj`) · `copy.ts`.
- **무대 오브젝트와 인라인 오브젝트는 같은 `MomentObject` 를 두 번 렌더**(인라인은 `lit` 고정). 무대 모드 판정은 CSS 가 하고(SPEC §2.8 `.js .moments-stage`), JS 는 `MQ_STAGE` 가 참일 때만 IO 를 건다.
- **수용**: SPEC §S2 수용 조건(T7). 스스로: tsc·eslint + 데브 3000 에서 scrollY 549·1,197·1,548·1,845 캡처 4장 + 감속 1장.
- **금지**: 가로 이동, 스크롤 스냅, 휠 가로채기, 렌더 필터, `#moments` 나 조상에 overflow·transform·contain(§5.4).

### 4.3 `rows-a` — 기능 절 제목 + R1–R3 · SPEC §S3·§S4
- **만든다**: `FeaturesIntro.tsx`(server: `<section id="features">` 칩 + H2 + 서브 + `<Rail head/>`) · `RowsA.tsx`(server: `FeatureRow` 3개) · `rows-a.data.ts`(R1·R2·R3 의 `FeatureRowProps` — SPEC §S4 4.2 표를 그대로 옮긴 상수, 카피 포함).
- **쓴다**: `FeatureRow`·`Rail`(primitives) · `ROW_TIMING` · `ALT`.
- **수용**: SPEC §S3·§S4 수용 조건(T8 의 R1–R3) · 캔버스 렌더 상자 교차 0(데이터만으로 검사하는 작은 스크립트를 `.scratch/rows-a/` 에서 돌려도 됨).
- **금지**: `FeatureRow` 를 우회한 자체 리빌, 행마다 같은 구도.

### 4.4 `rows-b` — R4–R5 · SPEC §S4
- **만든다**: `RowsB.tsx` · `rows-b.data.ts`. R5 의 폰은 `CanvasItem kind:'phone'`(PhoneShell `screenWidth=208`), 타일은 `{ icon: 'brand/icon-256', bare: true }`.
- **수용**: T8 의 R4–R5 · R4 의 두 조각에 `fade.left = 28`.
- **금지**: 센터 배지가 보이는 원본 패널(`ui/league`·`ui/token-month`) 사용.

### 4.5 `facts-install` — `components/{facts,install}/**` · `data/install-copy.ts` · SPEC §S5·§S6
- **입력**: 둘 다 `{ release: ReleaseInfo }`.
- **만든다**: `Facts.tsx`(server, `<dl>` 8칸 — 숫자는 `FIGURES` + `installChoice(release, RELEASE_FALLBACK).mb`, 단위 `.t-unit`, `.seam`·`.tick`) · `Install.tsx`(server, `.horizon`, Mac/iPhone 두 열, 팀 3단계, 업데이트 한 줄 — `DownloadCTA placement="install"`·`CommandBox`·`AppStoreBadge`·`QrCode`) · `data/install-copy.ts` 정리(installHint 문장 삭제, SPEC §S6 문장으로).
- **수용**: SPEC §S5·§S6 수용 조건(T5·T11·T15) · `.t-facts` 에 들어가는 문자열이 `FigureString` 타입으로 컴파일됨.
- **금지**: 숫자 하드코딩(30.1), 카운트업, 아이콘, "경고 없이", 공유 시트.

### 4.6 `faq-outro` — `components/{faq,outro}/**` · `components/site/{SiteFooter,LicensesNav,FaqHash}.tsx` · `data/faq-items.ts` · `app/licenses/page.tsx` · SPEC §S7·§S8·§S9
- **만든다**: `Faq.tsx`(server — `<details name="faq">` 10개, 1번 open, `.faq-open-line`, `FaqHash`, JSON-LD) · `Outro.tsx`(server — `Dome variant="small"`, H2·리드·CTA 줄(`DownloadCTA placement="outro"`·배지·`CopyButton variant="secondary" label="brew 명령 복사"`), `<OutroStage/>`) · `OutroStage.tsx`(client — 45% 진입 1회 `data-shown` 으로 내용 페이드, `AingClip` poster `char/aing-idle-poster`, once 없음, maxLoops 2) · 푸터·라이선스 내비를 v2 토큰에 맞춤(구조 그대로).
- **수용**: SPEC §S7·§S8·§S9 수용 조건(T6 의 아웃트로 부분·T12) · `/licenses` 200.
- **금지**: 꾸벅(commute-end)·말풍선·근무 라벨을 아웃트로에, FAQ sticky, 센터 문항.

---

## 5. 에셋 레시피(② `assets`) — 값은 SPEC §9 가 정본

### 5.1 실행
```sh
cd /Users/yesung/check/landing
node scripts/subset-fonts.mjs --from-spec                 # ② 초반: docs/v2/SPEC.md §3 글자 ∪ 소스 스캔 → 500·600·300-num
touch docs/v2/.fonts-done
node scripts/build-assets.mjs --only=ui,data              # 새 크롭·말풍선 4x·포스터·근무 라벨 + generated json (영상 재인코딩 없음)
node scripts/check-glyphs.mjs ; echo "glyphs=$?"
```
⑤ 통합은 `npm run subset`(소스 모드)로 다시 만든다.

### 5.2 `build-assets.mjs` 에 더할 것(모양)
```js
// ─── v2 크롭(SPEC §9.2) — 크롭·리사이즈·품질만 ─────────────────────────────────
// [출력, 원본(SRC 기준), extract | null, resize {width|height} | null, webp 옵션, 기대 [w,h]]
const V2_CROPS = [
  ["ui/header-on-lg.webp",          "v4/mac/ui/header/header_on_1020@4x.png", null, null, { quality: 85, alphaQuality: 90 }, [1264, 428]],
  ["ui/poke-slice.webp",            "v4/mac/ui/poke_list@3x.png", { left: 228, top: 390, width: 762, height: 852 }, null, R80, [762, 852]],
  ["ui/token-slice.webp",           "v4/mac/ui/token_board_month@3x.png", { left: 246, top: 390, width: 708, height: 1005 }, { width: 472 }, R80, [472, 670]],
  ["ui/league-slice.webp",          "v4/mac/ui/league_week@3x.png", { left: 216, top: 540, width: 744, height: 640 }, { width: 496 }, R80, [496, 427]],
  ["ui/message-unread-panel.webp",  "v4/mac/ui/message_thread_gureum_unread@3x.png", { left: 36, top: 390, width: 954, height: 900 }, null, R80, [954, 900]],
  ["ui/message-read-panel.webp",    "v4/mac/ui/message_thread_gureum_read@3x.png",   { left: 36, top: 390, width: 954, height: 900 }, null, R80, [954, 900]],
  ["ui/character-panel.webp",       "v4/mac/ui/character_pick_aing@3x.png",          { left: 36, top: 390, width: 954, height: 900 }, null, R80, [954, 900]],
  ["ui/timer-00-00.webp",           "v3/mac/char/_ui/timer_00-00.png", { left: 787, top: 1686, width: 527, height: 239 }, { width: 264 }, { quality: 90, alphaQuality: 100 }, [264, 120]],
  ["char/aing-rest-poster.webp",    "v3/mac/char/aing/commute_start/0000.png", { left: 424, top: 544, width: 1308, height: 1580 }, { width: 654 }, { quality: 80, alphaQuality: 90, smartSubsample: true }, [654, 790]],
  ["ui/menubar-icon.webp",          "v4/mac/ui/menubar/menubar_aing_icon_working@10x.png", null, { width: 66 }, LABEL, [66, 66]],
];
// LABELS 표에 한 줄: [29, "ui/menubar-0000-lg.webp", "menubar/menubar_aing_working_0000_dark_alpha@10x.png", 132]
// BUBBLES: w3 = bbox.width * 3/8 → w4 = Math.round(bbox.width / 2) (출력 이름 그대로) · RUBY: ÷ 3.5 → ÷ 2.625
//   buildData 의 bubbles.json: canvasPx 는 bbox × 3/8 × 3.5 로 계속 계산(파일 픽셀이 아니라 bbox 에서) → 값 불변
// FONT_OUTPUTS: pretendard-800-sub.* → pretendard-500-sub.{woff2,txt} · pretendard-600-sub.{woff2,txt} · pretendard-300-num.{woff2,txt}
// expectedOutputs(): V2_CROPS·새 LABELS 줄 추가 — 레시피 + 검증 목록 + AssetKey(core) 를 함께(TD §6)
```
`buildUI()` 끝에 `await pool(V2_CROPS, 4, …)` 한 줄. `char/aing-rest-poster` 도 여기서 굽는다(영상 묶음을 돌리지 않으려고).

### 5.3 확인(assets 의 완료 조건)
1. SPEC §9.2 의 바이트 ±10% 안(크게 다르면 품질 값을 확인하고 보고).
2. `data/generated/assets.json` 에 새 키 11개가 있고 `w·h` 가 기대값.
3. `bubbles.json` 의 `canvasPx` 가 다시 굽기 전과 같다(diff 를 보고에 붙인다).
4. 배지 감사: 새 크롭 6개(poke·token·league·message ×2·character)를 2× 확대 접촉 시트로(`.scratch/assets/badges.png`) — '서울'·'부산' 글자 0.
5. `check-glyphs.mjs` exit 0, `public/fonts` 에 800 서브셋 없음.

---

## 6. 통합 규칙

1. **공용 파일은 ④ 동안 아무도 고치지 않는다.** 섹션 에이전트가 공용 변경이 필요하면 `docs/v2/requests/<agent>.md` 에 (무엇을 · 왜 · 제안 diff)를 적고 자기 폴더 안에서 우회한다. 통합이 모아 처리한다. 공용 = `app/{globals.css,layout.tsx,page.tsx}`·`components/ui/**`·`components/features/{FeatureRow,RowCanvas,Rail}.tsx`·`lib/**`·`data/{fixtures,figures,site-links}.ts`·`scripts/**`.
2. **페이지는 매 단계 컴파일된다**: core 가 ② 에서 섹션 자리표시자 9개(각 `id`·`min-height`·named export·props 가 §3.10 과 같음)를 먼저 두고 `page.tsx` 가 그것을 import 한다. 섹션 에이전트는 자기 자리표시자를 **덮어쓴다**(이름·props 유지). 자리표시자 모양:
   ```tsx
   // components/moments/Moments.tsx — 자리표시자(core). moments 에이전트가 덮어쓴다.
   export function Moments() { return <section id="moments" style={{ minHeight: '244svh' }} aria-label="트립틱 자리" />; }
   ```
3. 섹션 에이전트가 돌리는 명령: `npx tsc --noEmit` · `npx eslint <자기 파일들>` · 자기 테스트. **`next build`·`npm run assets`·`npm run subset`·데브 서버 재시작·포트 열기 금지.** 다른 파일의 tsc 에러는 고치지 말고 requests 에 적는다.
4. **git 상태를 바꾸는 명령 금지**(add·commit·stash·checkout·reset·clean·push·branch·rm). 워크트리 금지(`landing/` 은 미추적이라 워크트리에 없다). 커밋·배포는 사용자 몫.
5. `landing/` 밖은 읽기만(소재 `/Users/yesung/aing-check-promo/public/**`, 앱 아이콘 `packaging/appicon/icon-1024.png`). 저장소 `Sources/`·`Tests/` 는 열지 않는다.
6. 의존성 추가 금지(§8). 필요하면 requests → 통합이 DECISIONS 에 적고 결정.
7. **편집은 Edit/Write 도구 또는 `cat > 파일`**. `sed -i`·`perl -i` 금지(새 inode → 데브 서버가 변경을 놓친다, §9).
8. 통합의 마지막 점검: 서버·브라우저 프로세스 종료(`lsof -i :3100` 비어 있음, 남은 `chromium`·`node`(데브 제외)·`ffmpeg` 0) · `ls -R landing | grep -v node_modules` 로 의도하지 않은 파일(덤프·스크린샷·`.scratch` 밖 임시) 0 · 표식 `docs/v2/.*-done` 삭제 · 커밋하지 않는다.
9. **sticky 조상 규칙**: `html`·`body`·`main`·`#moments` 와 그 사이 모든 조상에 `overflow: hidden|auto|scroll`·`transform`·`translate`·`scale`·`filter`·`perspective`·`contain: paint|layout|strict|content`·`will-change: transform` 금지(SPEC §5.4). 가로 넘침은 `body { overflow-x: clip }` 하나로.
10. 감속 모션·키보드·대비·alt 는 각 섹션의 책임이고, 통합은 검사만 한다.
11. 카피를 고쳐야 하면(CB 와 다름·금지어) 섹션 파일이 아니라 SPEC 의 CB 줄을 기준으로 고치고, SPEC 밖 문장은 넣지 않는다(SPEC §1.4.3 승인 목록만).

---

## 7. 수용 테스트(⑤ 통합 · ⑧ 재검증)

### 7.1 환경
- 하네스: **저장소 밖** `/private/tmp/claude-501/-Users-yesung-check/2e0b98fb-2bf2-4358-9866-db6bfc6f2d59/scratchpad/v2accept/`(통합이 만들고 재검증이 그대로 다시 돌린다). `lib.mjs` 에서 `const pw = createRequire('/Users/yesung/Aingo/node_modules/')('playwright')`(1.60, chromium·webkit·firefox 설치됨). `@playwright/test`·`tests/e2e/`·`playwright.config.ts` 는 만들지 않는다(DECISIONS 승계).
- 서버: **동작·모양 테스트 = 데브 3000**(T3–T12·T14–T17). **예산 테스트 = prod**: `npm run build && npx next start -p 3100`(백그라운드, 끝나면 kill) 에서 T13 과 T3·T4·T9 를 한 번 더.
- 엔진: Chromium 전체. WebKit = T3·T6(감속)·T7(sticky)·T13(전송 바이트)·T17.
- 컨텍스트: 기본 · `reducedMotion: 'reduce'` · iOS(`userAgent` iPhone + `hasTouch`) · 클립보드 권한(T11).
- 스크롤은 `window.scrollTo(0, y)` 뒤 `await page.waitForTimeout(…)`(IO 콜백·전이 대기). 위치는 DOM 에서 구한다(SPEC 의 scrollY 는 1440×900 기댓값 — ±24px 허용).
- 판정은 exit code. 결과는 `v2accept/out/report.json` + 캡처.

### 7.2 테스트 목록
| # | 무엇 | 단언 |
|---|---|---|
| T1 | 빌드 건강 | `npm run typecheck`·`lint`·`test:unit`·`node scripts/check-glyphs.mjs`·`npm run build` 각각 exit 0 |
| T2 | 서버 | `GET /api/download` 302, `Location` 이 `aing-check.dmg` 로 끝남 · `?file=zip` → `aing-check.zip` · `GET /api/release` 200 JSON, `version` 문자열, `dmg.mb` = "30.1"(0.3.49) 또는 그 뒤 릴리스 값 · 폴백이면 `RELEASE_FALLBACK` 과 같음 |
| T3 | 깨끗함 | 390·768·1440 각각 맨 아래까지 스크롤하는 동안 콘솔 error 0 · pageerror 0 · 실패 요청 0 · 404 0 · 모든 `img` `naturalWidth > 0`(스크롤 뒤) |
| T4 | 금지어 | `document.body.innerText` + 모든 `alt`·`aria-label`·`title` + `<meta name=description>` + JSON-LD 에서 SPEC §1.4.1 목록 0건 |
| T5 | 모양 | `scrollWidth === innerWidth`(390·768·1440) · 1440×900 문서 높이 9,300–9,900 · 섹션 id 순서 = `top, moments, features, f-message, f-character, f-break, f-ranking, f-iphone, facts, install, faq, outro` · `[data-eyebrow]` 1개 · 페이지 전체 `img[src*="popover"]` 0 · 1440×789·1280×720(감속) 말풍선 윗변 − 메타 아랫변 ≥ 16 · H1 `fontSize ≤ .1 × innerHeight` · 헤드라인 `<br>` 수 = SPEC `lines` 수 − 1(H1·H2·H3) |
| T6 | 히어로·아웃트로 | SPEC §S1·§S8 수용 조건 전부(도착 3.5s · `.comet` 1회 · `playbackRate=16` 로 `[data-stopped]` · 감속 영상 요청 0 · 390 에 `.comet` 없음 · 아웃트로 45% 진입 후 내용 불투명 1 · 아웃트로 `.aing-bubble`·`.aing-timer` 0개) |
| T7 | 트립틱 | SPEC §S2 수용 조건 전부(무대 `top === 0` · 활성 0→1→2 · 히스테리시스 · 점등 1.5s · engaged 전 오브젝트 2·3 요청 0 · 감속 목록 모드) · WebKit 에서 `top === 0` |
| T8 | 기능 행 | 행마다: 문턱 전 `data-on` 없음 → 지난 뒤 1.5s 안에 `data-on`, `.wire` 의 `stroke-dashoffset` 계산값 0 · 위·아래 왕복 뒤 `data-reveal-count="1"` · 캔버스 렌더 상자 교차 0 · R1 2s 뒤 `.swap-to` 불투명 1 · 캔버스 중심 50% 에서 그 행만 `.floor-light[data-glow="on"]` · 감속에서 로드 직후 전부 최종(`data-instant` 또는 dashoffset 0) · `#f-character` 에 `img[src*="todo-board"]` 0 |
| T9 | 빛 | SPEC §2.9 의 V0–V9 보라 면적이 범위 안(HSV 알고리즘, 1440×900, 각 위치 1s 대기 뒤 캡처) · 같은 위치 + 경계 6곳(히어로→트립틱 scrollY 600·660, 행 경계 3곳, FAQ→아웃트로)에서 화면과 겹치는 `[data-glow="on"]` ≤ 1(히어로 보이는 비율 > .35 면 1로 센다) |
| T10 | 체험 0 | Tab 을 끝까지 눌러 모은 포커스 대상이 전부 허용 목록(건너뛰기·내비 링크·CTA·배지·QR·"brew로 설치"·복사 버튼·`summary`·푸터 링크) · `button` 요소 = 복사 버튼 2개뿐 · `[role=tab],[role=tablist],[role=switch],[role=slider]` 0 · 감속 컨텍스트에서 `main img` 마다 가운데 클릭 → `main.innerHTML` 해시 불변 · `.next/static` 청크에 `navigator.share` 0 · `cursor: pointer` 인 요소가 허용 목록 밖에 0 |
| T11 | 복사 | 설치·아웃트로 복사 → 클립보드 `brew install yehsung/check/aing-check` · 버튼 "복사했어요" → 2.2s 뒤 "복사"(아웃트로는 "brew 명령 복사") · `[role=status]` 에 "복사했어요" |
| T12 | FAQ | `/#faq-3` → 3번만 `open` · `details[name=faq]` 10개 · JSON-LD `FAQPage` 질문 10개 · 열린 행 `.faq-open-line` |
| T13 | 예산(prod 3100) | 1440×900 크롬, 스크롤 없이 `load` + 1s 까지 응답 바이트 합 **≤ 400KB** · 맨 아래까지 스크롤(아웃트로 idle 시작 + 3s) 총 전송 **≤ 4.5MB**(크롬·웹킷 각각) · 390 크롬 총 전송 **≤ 2.2MB** · CDP 스로틀(지연 60ms·다운 9Mbps·업 1.5Mbps·CPU 4×)에서 390 LCP **≤ 2.5s**, CLS **≤ 0.05**(`PerformanceObserver`) · 로드 전(`load` 이전) 영상 요청 0 |
| T14 | 접근성 | `html[lang=ko]` · `h1` 1개 · 각 `section` 에 `h2`(트립틱은 카드마다) · 모든 `img` 에 `alt` 속성(장식은 `""` — SPEC §6.5 목록과 일치) · 건너뛰기 링크 포커스 시 보임 · 포커스 링 캡처 3장(내비 CTA·복사·summary) · `t-small` ink-3 글자 대비 ≥ 4.5(계산값) |
| T15 | iOS | iOS 컨텍스트: 히어로·아웃트로에 Mac 다운로드 버튼 안 보임, 배지가 버튼 줄 첫째 · 내비 CTA = App Store 링크 · 설치 절 iPhone 열이 Mac 열보다 위 |
| T16 | OG·메타 | `app/opengraph-image.png` 1200×630 · `.alt.txt` = `lib/site.ts` `OG_IMAGE.alt` · `<meta name=theme-color content=#0C0A14>` · `<title>` = SPEC §8 |
| T17 | sticky 조상 | `html`·`body`·`main`·`#moments` 의 계산 스타일: `overflow-y ∈ {visible, clip}`, `overflow-x ∈ {visible, clip}`, `transform/translate/scale/filter/perspective = none`, `contain` 에 paint·layout·strict·content 없음, `will-change` 에 transform 없음 |

### 7.3 리드 보고용 캡처 세트(⑤ 가 `landing/.scratch/integration/shots/` 에 — gitignore)
1440×900: 첫 화면 t=0 · t=1.2s(빛 한 줄 중간) · t=3s(도착 뒤) · 트립틱 01·02·03 머묾 · 기능 절 제목 · R1–R5 각 조립 끝 · 숫자 격자 · 설치 · FAQ · 아웃트로 · 전체 페이지 한 장. 1440×789 첫 화면 · 1280×720 첫 화면. 390×844 첫 화면 + 전체. 감속 1440 전체. WebKit 1440 첫 화면. `integration-report.md` 에 경로·§7 결과표·예산 실측·남은 결정(SPEC §7.4)을 적는다 — 오케스트레이터가 이것으로 사용자에게 보여 줄 페이지를 만든다.

---

## 8. 의존성 · 스크립트 · 환경

- **dependencies**: `next@16.4.0` · `react@19.3.0` · `react-dom@19.3.0`. **`motion` 은 ① 에서 제거**(사용처 0).
- **devDependencies**(그대로): `@tailwindcss/turbopack@^4` · `tailwindcss@^4` · `typescript@^5` · `@types/{node,react,react-dom}` · `eslint@^9` · `eslint-config-next@16.4.0` · `sharp@^0.35`.
- **새 패키지 0**(DECISIONS D6). Playwright 는 `createRequire('/Users/yesung/Aingo/node_modules/')` 로 저장소 밖에서.
- **scripts**: `dev: next dev`(3000) · `prebuild: node scripts/check-glyphs.mjs` · `build: next build` · `start: next start`(측정 때만 `-p 3100`) · `lint: eslint .` · `typecheck: tsc --noEmit` · **`test:unit: node --experimental-strip-types --test "lib/**/*.test.ts" "components/**/*.test.ts"`**(신규) · `assets` · `subset` · `qr`. `test:store` 삭제.
- `tsconfig`: 그대로(`allowImportingTsExtensions` 는 테스트가 `./x.ts` 를 import 하므로 유지).
- `next.config.ts`: 그대로(`images.unoptimized`, `cacheComponents` 꺼짐 — 고전 ISR, `export const revalidate = 3600`). **이 Next 는 학습 데이터와 다르다** — 코드를 쓰기 전에 `node_modules/next/dist/docs/01-app/02-guides/upgrading/version-16.md` 와 자기 영역 문서를 읽는다(AGENTS.md).
- 외부 도구: `pyftsubset`·`fonttools` = `/opt/anaconda3/bin/`(C 실측) · ffmpeg 는 이번엔 쓰지 않는다(영상 재인코딩 없음).
- 환경 변수(선택, 배포 때): `NEXT_PUBLIC_SITE_URL` · `GITHUB_TOKEN`. 앱 릴리스마다 `RELEASE_FALLBACK` 갱신.

---

## 9. 데브 서버 운영(포트 3000)

1. **3000 은 하나뿐이고 계속 떠 있다**(설계 시점 pid 14129/14130 — 사용자가 결과를 이 주소로 본다). 섹션·리뷰 에이전트는 **보기만**: `curl`·Playwright 캡처 가능, 재시작·종료 금지.
2. 재시작은 **통합(또는 수리) 에이전트만**, 아래 경우에만: Turbopack "HMR hash mismatch" 무한 새로고침 · 모듈 그래프가 꼬여 저장해도 반영되지 않음. 절차: 서버 종료 → `rm -rf .next/dev` → `npm run dev > .scratch/dev.log 2>&1` 을 **백그라운드 실행 도구로**(명령 안에 `&` 를 또 붙이지 않는다 — 런처만 끝나고 서버가 죽는다) → `curl` 200 확인 → 보고에 적는다.
3. **편집은 Edit/Write 또는 `cat >`**. `sed -i`·`perl -i` 는 새 inode 로 바꿔치기해 데브 서버가 변경을 놓친다.
4. **import 끊기 → 삭제** 순서(TD §5). 거꾸로 하면 열린 탭이 "Module not found" 오버레이를 띄우고 HMR 이 2번으로 번진다.
5. `next build` 는 `.next/`, 데브는 `.next/dev` 라 동시에 돌아도 된다(Next 16). 그래도 ④ 단계에서는 build 금지(§6-3).
6. 측정용 prod 서버는 `-p 3100` 하나만, 쓰고 바로 끈다(`lsof -i :3100` 비어 있음 확인).

---

## 10. 에이전트 머리말(모든 에이전트 프롬프트 맨 앞에 붙인다)

1. 읽는 순서: `docs/v2/DECISIONS.md` → `docs/v2/PLAN.md`(§0 자기 단계·§2 자기 파일·§3 서명·§4 자기 계약) → `docs/v2/SPEC.md`(§1 원칙·§2 토큰·자기 절·§9 에셋). 카피는 SPEC 이 고른 CB 문장 그대로.
2. 혼자 끝낸다: Agent·서브에이전트·스킬(`/code-review` 포함)·Workflow 호출 금지(위임하면 손자 에이전트가 생긴다).
3. 쓰기는 §2 의 자기 경로만. 공용 변경은 `docs/v2/requests/<agent>.md`.
4. git 상태를 바꾸는 명령 금지. `landing/` 밖은 읽기만. 저장소 `Sources/`·`Tests/` 는 열지 않는다.
5. 임시 파일은 `landing/.scratch/<agent>/` 에만(다른 에이전트와 같은 이름의 공유 파일 금지). 끝나면 비운다.
6. 명령 결과는 exit code 로 판정한다. `| grep`·`| tail` 로 실패를 가리지 않는다. 테스트와 다음 명령을 `&&` 로 잇지 말고 따로 실행해 결과를 읽는다.
7. 띄운 프로세스(브라우저·node·서버)는 끝내고 나간다. 데브 서버 3000 은 §9 규칙대로만.
8. 보고는 짧게: 만든·고친 파일 경로, 수용 조건별 초록/빨강, 남은 문제와 requests 경로. 완료 표식 `touch docs/v2/.<agent>-done`.
