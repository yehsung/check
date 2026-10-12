# v2 철거·재사용 감정서 — `landing/` 전수 조사

작성 2026-10-12 KST · 철거·재사용 감정가(설계 워크플로) · 기준 `docs/v2/brief.md` §0·§4·§5.1 · 소재·카피 정본은 `docs/{asset-manifest,content-brief}.md`
상태: **설계 문서다. 저장소에서는 아무것도 지우지 않았다.** 판정은 스크래치 사본에서 실제로 지우고 `tsc`·`eslint`·`check-glyphs`·`next build` 를 돌려 검증했다(§4).

---

## 0. 결론

| 판정 | 파일 | 줄 | 바이트 |
|---|---|---|---|
| 삭제 | **70** | 7,433 | 334,040 |
| 유지(그대로) | 40 = 코드 22 · 생성 JSON 4 · 스크립트 4 · 앱 아이콘 2 · 설정 8 | | |
| 유지·이동 | 9 | 538 | 25,873 |
| 수정(제자리) | 13 = teardown 때 필수 9 · v2 스캐폴드 때 4 (+ 통합 때 OG 그림 2) | | |
| 신규 | 1 `lib/announce.ts` | 26 | 883 |

소스(app·components·lib·data 의 ts/tsx/css): **112개 · 10,704줄 · 469,761B → 43개 · 3,238줄 · 131,823B(−72%)**.

### 0.1 brief §4 와 달라진 판단
1. **`LiveAnnouncer` 는 삭제가 아니라 수정.** brew 복사·Mac 링크 보내기(허용 목록의 도구)가 알림을 여기로 보낸다. 스토어 의존만 `lib/announce.ts`(26줄)로 바꾼다. 지우면 복사 성공이 화면 읽기에 안 읽힌다.
2. **`RenderStack` 삭제 확정.** 본업이 판 교차(패널 교체)이고 `TickStrip` 을 import 한다. 정지 렌더는 `RenderImage`, 늦은 마운트는 `lib/media.afterLoadIdle` 로 충분.
3. **`CharacterStage` 삭제 확정**(§3). 쓸 만한 순수 함수 3개와 기하만 새 컴포넌트로 옮긴다. `TimerCapsule` 은 의존 0 이라 후보로 남김.
4. **brief 에 없던 삭제:** `SectionShell`(+`Beat`, 본업이 `activeSection` 갱신) · `TimeMark`(v1 하루 서사 14:05·17:02) · `closing-footer/Reveal`(열림/닫힘 토글).
5. **brief 에 없던 재사용(이동):** `FaqHash`(FAQ 딥링크 — `<details>` 도구) · `useHeroCtaVisible`(내비 CTA 테두리↔채움, 의존 0) · `grass-data`/`grass-geometry`(grass.json 의 유일한 소비자, 렌더 픽셀로 잔디를 한 번 켜는 리빌 재료 — 후보).
6. **`docs/.{assets,contracts,core,primitives-a,primitives-b}-done` 5개는 반드시 지운다.** v2 스캐폴드가 같은 표식 방식을 쓰면 `.contracts-done` 이 이미 있어 기다리지 않고 tsc 를 돌린다.
7. **이름 충돌 주의:** v2 기능 행의 왼쪽 세로 선을 `Spine` 이라 부르지 말 것. v1 잔재(`Spine.tsx`·`#spine`·`--z-spine`·`anim-spine-drop`) grep 과 섞인다. `Rail`/`Timeline` 권장.
8. **`motion` 의존성은 철거 뒤 사용처 0**(TodoBoard·UltraOverlay 만 썼다). 지울지 v2 스크럽에 쓸지는 PLAN 이 정한다.
9. **`landing/` 은 통째로 git 미추적**(`?? landing/`)이라 삭제를 git 으로 되돌릴 수 없다. 유일한 백업 `.scratch/landing-v1-2026-10-12.tgz`(8.26MB · 269항목, 삭제 70개 전부 들어 있음을 확인)도 gitignore 안에 있다.
10. **철거만 따로 반영하지 말 것.** 철거 직후 `/` 는 푸터만 남은 빈 페이지다. 사용자가 3000 을 열 수 있으니 v2 스캐폴드와 한 묶음으로 진행.

---

## 1. 전수 목록과 판정

### 1.1 삭제 — 70개 (체험·상태 기계·핫스팟·패널 교체·코너 아잉·스파인)

| 폴더 | 파일 | 개수 · 줄 / 바이트 | 이유 |
|---|---|---|---|
| `lib/demo/` | reducer · reducer.test · store · selectors · types | 5 · 1,301 / 61,231 | 상태 기계 본체와 테스트 |
| `components/sections/*.tsx` | AingCorner · CharacterRecords · ClosingFooter · HeroAuto · InstallFaq · IphoneTrust · MenubarStage · MessageGames · TeamPoke | 9 · 468 / 26,097 | v1 섹션 진입점. v2 는 새로 쓴다 |
| `menubar-stage/` | Spine · StatusItem · spineDisplay · useSpineBoot · fixedAncestors · prefetchPlan · loadIdle · geometry · navModel · NavLinks · NavCta | 11 · 762 / 36,625 | 팝오버 스파인, 라벨 상태, 활성 섹션 내비 |
| `aing-corner/` | AingCornerClient · Corner · HideButton · TodoBoard · UltraOverlay · placement · useCornerPlacement · useViewportSize | 8 · 1,102 / 44,438 | 코너 아잉·할 일 보드·울트라 오버레이 |
| `hero-auto/` | AutoProbe · HeroMeta · HeroPopover · copy · geometry · preload | 6 · 352 / 14,842 | 근무 시작 버튼 흉내, 자동 시작 탐침. 카피 정본은 content-brief |
| `team-poke/` | NearPreload · PokePanel · TeamPanel · TeamSegment | 4 · 163 / 6,764 | 세그먼트, 찌르기 체험 |
| `message-games/` | GamesDemo · MessageDemo · model · sizing | 4 · 353 / 17,783 | 메시지 보내기, 게임 창 교체 |
| `character-records/` | GrassLight · TodoButton · TokenPanel | 3 · 349 / 14,085 | 되감기 스크럽 + 호버 툴팁 + 세그먼트, 토큰 이전/다음 |
| `iphone-trust/` | PhoneTabs · TodoWidget · copy · geometry · layout | 5 · 354 / 17,090 | 폰 탭 바꾸기, 위젯 체크 핫스팟 |
| `install-faq/` | InstallBlock · InstallSection · FaqSection | 3 · 315 / 16,364 | installHint 상태, SectionShell 결합(FAQ 마크업 조각은 §2.8) |
| `closing-footer/` | ClosingDay · ClosingCta · Reveal | 3 · 323 / 14,545 | 근무 종료·다시 시작 버튼, 코너 회피 |
| `components/ui/` | CharacterStage 468 · PanelSlot 293 · RenderStack 189 · SectionShell 150 · Hotspot 141 · TickStrip 112 · Segmented 103 · AingStageInline 97 · TimeMark 38 | 9 · 1,591 / 64,176 | 위 표의 공용 부품 |

### 1.2 유지·이동 — 9개 (경로는 제안, v2 PLAN 이 덮어쓸 수 있다)

| 지금 | 제안 경로 | 줄 | 이유 · 같이 고칠 것 |
|---|---|---|---|
| `sections/closing-footer/SiteFooter.tsx` | `components/site/SiteFooter.tsx` | 57 | 푸터 6링크·저작권. `./links` → `@/data/site-links` |
| `sections/closing-footer/LicensesNav.tsx` | `components/site/LicensesNav.tsx` | 58 | /licenses 내비. 같은 import. 모양은 v2 내비와 맞출 때 |
| `sections/closing-footer/links.ts` | `data/site-links.ts` | 22 | `FOOTER_LINKS`·`NAV_LINKS`. NAV_LINKS 앵커(`/#team`·`/#iphone`)는 v2 앵커로 |
| `sections/install-faq/faq-items.ts` | `data/faq-items.ts` | 63 | FAQ 10문항 + `faqJsonLd()` |
| `sections/install-faq/install-copy.ts` | `data/install-copy.ts` | 66 | 설치 절 문장 + `installChoice(release, fallback)`. `stepsDmg` 등 installHint 문장은 v2 가 고른다 |
| `sections/install-faq/FaqHash.tsx` | `components/site/FaqHash.tsx` | 60 | `#faq-n` 으로 들어오면 그 `<details>` 를 열고 스크롤 |
| `sections/menubar-stage/useHeroCtaVisible.ts` | `components/site/useHeroCtaVisible.ts` | 49 | `[data-hero-cta]` 가 내비 아래로 보이는지(IO + MutationObserver) |
| `sections/character-records/grass-data.ts` | `lib/grass/grass-data.ts` | 81 | grass.json 검증 읽기. **후보** — v2 가 안 쓰면 삭제 |
| `sections/character-records/grass-geometry.ts` | `lib/grass/grass-geometry.ts` | 82 | `cellClip`·`cellDelayMs`·`litColumns`. **후보**. `SCRUB_*` 는 되감기용 — 1회 리빌로 바꿔 쓴다 |

카피를 `data/` 로 옮기는 이유: `scripts/check-glyphs.mjs:26` 의 `SCAN_DIRS` 가 `app·components·data` 뿐이다. `lib/` 에 한글 카피를 두면 글자 검사가 못 본다.

### 1.3 수정 — 제자리 13개

| 파일 | 줄 | 끊을 것 · 바꿀 것 | 시점 |
|---|---|---|---|
| `app/page.tsx` | 22 | v1 섹션 9개 + AingCorner import → 스텁(§4.3) | teardown 필수 |
| `app/licenses/page.tsx` | 109 | `sections/closing-footer/*` → `components/site/*` | 필수 |
| `data/fixtures.ts` | 208→177 | `lib/demo/types` 타입 import → 인라인, 상태 기계 상수 정리(§2.9) | 필수 |
| `lib/hooks.ts` | 175→159 | `useDemo`·`SectionId` → `ViewportMode` 인라인, `useEnterTimer` 삭제 | 필수 |
| `components/ui/Bubble.tsx` | 205 | `BubbleArtId` 를 fixtures 에서. `onClick`·`ariaLabel`(버튼 분기)는 v2 에서 삭제 권장 | 필수 |
| `components/ui/CopyButton.tsx` | 78 | `demo.announce` → `announce` | 필수 |
| `components/ui/CommandBox.tsx` | 61 | 같음 | 필수 |
| `components/ui/DownloadCTA.tsx` | 154 | `demo.installClicked(placement)` 삭제 + `announce` | 필수 |
| `components/ui/LiveAnnouncer.tsx` | 17 | `useDemo(s => s.announce)` → `useAnnouncement()` | 필수 |
| `app/globals.css` | 133 | v1 토큰 값·스파인/핫스팟/라벨 키프레임(:107–130)·z 토큰 정리. 이름 호환은 §8 | v2 스캐폴드 |
| `app/layout.tsx` | 74 | `themeColor:"#12131C"`(:53) → v2 `--bg-0`, 글꼴 가중치(800 한 벌뿐) | v2 스캐폴드 |
| `package.json` | 34 | `test:store`(:12) 삭제 | teardown 과 함께 |
| `README.md` | 35 | `test:store`(:11) · 정본 경로(:14–19) · "Pretendard 800"(:27) | teardown 과 함께 |

통합 때 교체: `app/opengraph-image.png`(220,329B, v1 히어로 캡처) · `app/opengraph-image.alt.txt` · `lib/site.ts:13` `OG_IMAGE.alt`("아잉체크 팝오버와 메뉴바 라벨").

### 1.4 유지 — 그대로 40개
- 서버·라우트: `app/api/download/route.ts`(12) · `app/api/release/route.ts`(11) · `app/robots.ts`(10) · `app/sitemap.ts`(10) · `lib/release.ts`(69) · `lib/site.ts`(13)
- 플랫폼·미디어: `lib/platform.ts`(18) · `lib/media.ts`(71) · `components/ui/PlatformScript.tsx`(10)
- 캐릭터 영상: `components/SpritePlayer.tsx`(330) · `components/sprite/AlphaVideo.tsx`(258) · `components/sprite/SheetPlayer.tsx`(130 — 쓰는 시퀀스는 `tick` 하나뿐이지만 SpritePlayer 가 import 한다)
- 프리미티브: `Button`(129) · `AppStoreBadge`(44) · `QrCode`(43) · `RenderImage`(43) · `MacWindowShell`(55) · `PhoneShell`(88) · `Headline`(49) · `TextLink`(30) · `VisuallyHidden`(22) · `TimerCapsule`(52, 후보)
- 생성물: `data/generated/{assets 350, sequences 276, bubbles 129, grass 2,219}.json` — 전부 `scripts/build-assets.mjs` 의 data 묶음(:471–539)이 디스크 결과물에서 다시 쓴다. 손으로 고치지 않는다.
- 스크립트: `build-assets.mjs`(674) · `subset-fonts.mjs`(131) · `check-glyphs.mjs`(175) · `make-qr.py`(118) — 조건부 수정은 §6
- 앱 아이콘: `app/icon.png` · `app/apple-icon.png`(build-assets brand 묶음 출력)
- 설정: `next.config.ts` · `vercel.json` · `eslint.config.mjs` · `tsconfig.json` · `next-env.d.ts` · `AGENTS.md` · `.gitignore` · `package-lock.json`

### 1.5 `docs/`
| 파일 | 판정 |
|---|---|
| `content-brief.md` · `asset-manifest.md` | 정본 유지 |
| `SPEC.md` · `PLAN.md` · `DECISIONS.md` | 맨 위에 한 줄: "거부된 v1(2026-10-12 15:50). v2 정본은 `docs/v2/`. SPEC §1.4 사실 규칙·§9 에셋 표, DECISIONS §1–3 은 v2 가 승계" |
| `requests/*.md`(12) | 각 파일 머리에 "거부된 v1 섹션 요청" |
| `export-assets.probe.mjs` | v1 설계 초안(`scripts/build-assets.mjs` 가 대체). 남기되 머리에 "v1 초안". eslint 대상이고 지금 초록 |
| `.{assets,contracts,core,primitives-a,primitives-b}-done` | **삭제**(빈 파일, gitignore — §0.1-6) |

---

## 2. 유지·수정 파일의 현재 서명 (재사용 판단용)

### 2.1 CTA·도구
```ts
// Button.tsx — 'use client' 없음(서버는 href, 클라는 onClick). 끝 화살표 없음.
type ButtonVariant = "primary" | "secondary" | "ghost";   // primary = bg-aing / secondary = border-line-strong
type ButtonSize = "l" | "m" | "s";                        // h-12 / h-10 / h-8
interface ButtonProps { variant: ButtonVariant; size?: ButtonSize; href?: string; onClick?: () => void; external?: boolean;
  disabled?: boolean; ariaLabel?: string; className?: string; children: ReactNode; id?: string; type?: "button" | "submit";
  ariaExpanded?: boolean; ariaControls?: string; ariaDescribedBy?: string; ariaPressed?: boolean; ref?: Ref<HTMLElement> }

// DownloadCTA.tsx — 세 벌(.cta-mac/.cta-ios/.cta-other) SSR, <html data-platform> 으로 하나만 보임.
//   mac·other → <a href="/api/download">, ios → nav 면 App Store, 그 밖엔 'Mac 링크 보내기'(share → 클립보드).
type Placement = "nav" | "hero" | "install" | "closing";  // 내보내지 않음. nav 분기와 data-cta 에만 쓰인다 → v2 자리 이름으로 넓힐 것
interface DownloadCTAProps { placement: Placement; size: "l" | "s"; tone?: "fill" | "outline"; label?: string;  // 기본 "Mac용 다운로드"
  file?: "dmg" | "zip"; ariaLabel?: string; className?: string; installHref?: string /* 기본 "#install" */ }

interface CommandBoxProps { command: string; copyAriaLabel: string; className?: string }   // '$ ' 접두 제외, '/' 뒤 <wbr>, 실패 시 선택 + "⌘C로 복사하세요"
interface CopyButtonProps { text: string; label?: string /* "복사" */; done?: string /* ANNOUNCE.copied */; ariaLabel: string;
  variant?: "inline" | "secondary"; onFail?: () => void; className?: string }
interface AppStoreBadgeProps { height?: 40 | 44 | 48 /* 48 */; placement: string; className?: string }  // hero·nav 면 eager, 여백 = height/4
interface QrCodeProps { size?: number /* 112 */; className?: string }   // desk 에서만 보임(hidden desk:block)
interface TextLinkProps { href: string; external?: boolean; children: ReactNode; className?: string }
```

### 2.2 렌더·셸·글자
```ts
interface RenderImageProps { asset: AssetKey; widthPt: number; heightPt: number; alt: string; eager?: boolean; className?: string;
  scale?: number /* 1 */; style?: CSSProperties; id?: string }        // <img> + 명시 크기 + decoding async, 키 없으면 dev 경고
interface MacWindowShellProps { widthPt: number; heightPt: number; scale: number; className?: string; children?: ReactNode;
  fluid?: boolean; style?: CSSProperties; id?: string; role?: string; ariaLabel?: string }  // --r-window·--shadow-window, height 전이
// ※ 주석의 "transform·filter 금지"는 v1 fixed 핫스팟 때문이었다 — v2 에는 핫스팟이 없으니 조상에 transform 리빌을 써도 된다.
interface PhoneShellProps { screenWidth: number; children?: ReactNode; className?: string; style?: CSSProperties }
export const PHONE_SCREEN_RATIO = 874 / 402;  export function phoneShellMetrics(W: number): { screenW; screenH; bezel; screenRadius; shellRadius; shellW; shellH; island }
type HeadlineSize = "display" | "closing" | "h2" | "h2-solo" | "h3";  // → .t-display … 클래스(globals.css), font-extrabold 고정
interface HeadlineProps { level: 1 | 2 | 3; size: HeadlineSize; lines: string[]; id?: string; className?: string }
interface VisuallyHiddenProps { as?: keyof JSX.IntrinsicElements; children: ReactNode; id?: string; className?: string }
interface TimerCapsuleProps { text: string; fontPx: number; className?: string; style?: CSSProperties }  // + capsulePadding(fontPx)
export function PlatformScript(): JSX.Element   // <head> 인라인 스크립트
export function LiveAnnouncer(): JSX.Element    // role=status aria-live=polite, nonce 를 key 로
```

### 2.3 말풍선 `Bubble.tsx`
```ts
export type BubbleKey = BubbleArtId;  // 'commute-start'|'autostart'|'poked-mint'|'message-gureum'|'commute-end'|'ruby'|'ultra-mint'|'update'
interface BubbleProps { id: BubbleKey; scale: number; visible: boolean; onClick?: () => void /* v2 삭제 */; static?: boolean;
  ariaLabel?: string /* v2 삭제 */; className?: string; style?: CSSProperties }
export function bubbleText(id): string; bubbleMs(id): number; bubbleSrc(id): string | null;
export function bubbleSizeFrom(file: unknown, id: string, scale: number): { w; h } | null;  bubbleSize(id, scale)
// 크기 = bubbles.json canvasPx × 0.5 × scale. 등장 120ms 선형 + scale .96→1 200ms ease-out, 퇴장 160ms. static 이면 전이 없음.
```

### 2.4 신규 `lib/announce.ts` (사본에서 검증한 그대로)
```ts
export type Announcement = { text: string; nonce: number } | null;
export function announce(text: string): void;      // 서버에선 무시, 같은 문장도 nonce 로 다시 읽힘
export function useAnnouncement(): Announcement;   // useSyncExternalStore, 서버 스냅숏 null
```

### 2.5 캐릭터 영상
```ts
// AlphaVideo.tsx — 형식은 JS(pickVideoFormat)로 하나만, SSR·하이드레이션 중엔 포스터, posterOnly 면 <video> 없음
interface AlphaVideoProps { sources: { webm?: string; mov?: string }; poster: string | null; fps: number; frames: number;
  width: number; height: number; play: boolean; loop: boolean; posterOnly: boolean; preload: "none" | "metadata" | "auto";
  priority?: boolean; onReady?(); onEnded?(); onError?(); className?: string; style?: CSSProperties }
interface AlphaVideoHandle { play(): Promise<void>; pause(): void; seekToFrame(n: number): Promise<void>; readonly ready: boolean }
export const SEEK_WAIT_MS = 300;  export function frameTime(n, fps, frames): number
// SheetPlayer.tsx — background-position 으로 칸 고르기
interface SheetPlayerProps { src; cols; rows; frames; fps; frameSize: readonly [number, number]; displayWidth: number;
  frame?: number; play: boolean; loop: boolean; onReady?(); onEnded?(); className?; style? }   export function sheetPosition(...)
// SpritePlayer.tsx — sequences.json 메타로 video/sheet 를 고른다. 화면 밖 일시정지는 하지 않는다(play 는 부르는 쪽이 IO 로).
interface SpritePlayerProps { name: SequenceName; play: boolean; frame?: number; displayWidth: number; loop?: boolean;
  lowFps?: boolean; posterOnly?: boolean; preload?: "none" | "metadata" | "auto" /* 'metadata' */; priority?: boolean;
  onReady?(); onEnded?(); onError?(); className?: string; style?: CSSProperties }
export function sequenceMeta(name): SequenceMeta | null; parseSequenceMeta(raw); videoVariant(meta, lowFps);
export function sequenceDisplayHeight(meta, w): number; preloadSequence(name, lowFps?): Promise<void>  // 사파리 .mov 는 미리 받지 않음
```

### 2.6 `lib/*`
```ts
// release.ts(서버 전용) — GitHub latest, 3초 타임아웃, 1시간 revalidate, 실패면 RELEASE_FALLBACK
export function formatMB(bytes: number): string; getRelease(): Promise<ReleaseInfo>; downloadTarget(r: ReleaseInfo, file: "dmg" | "zip"): string
// site.ts: SITE_URL(NEXT_PUBLIC_SITE_URL → VERCEL_PROJECT_PRODUCTION_URL → localhost:3000) · SITE_NAME · OG_IMAGE
// platform.ts: type Platform = 'mac'|'ios'|'other' · PLATFORM_SCRIPT(≈250B, 해시 첫 로드 smooth 끄기 포함) · getPlatform()
// media.ts: pickVideoFormat() · wantsLowFps() · preloadImage(src) · idle(fn) · afterLoadIdle(fn): () => void
// hooks.ts(수정 뒤): MQ_DESK·MQ_TAB·MQ_PHONE·MQ_REDUCED · type ViewportMode = 'desk'|'tab'|'phone' · viewportModeNow() · saveDataNow()
//   useViewportMode() · useReducedMotion() · useSaveData() · usePosterOnly()
//   useNearViewport(ref, rootMargin='600px')  ← 한 번 true 면 그대로: v2 '1회 리빌' 문턱에 맞다
//   useCenterLine(ref, onChange, dwellMs) · useInViewRatio(ref, ratio)  ← 양방향(되감긴다): v2 리빌에 쓰면 첫 true 만 받을 것
//   삭제: useEnterTimer(id: SectionId, …)
```

### 2.7 앱 셸·라우트
- `app/layout.tsx`: `metadata`(TITLE·DESCRIPTION, openGraph·twitter `images:[OG_IMAGE]`, `itunes.appId`) · `viewport{themeColor,colorScheme:"dark"}` · `localFont` 두 벌(`pretendard-800-sub.woff2` → `--font-pretendard` preload, `jbm-400-ascii.woff2` → `--font-jbm`) · `<html lang="ko" data-scroll-behavior="smooth" suppressHydrationWarning>` + `<head><PlatformScript/>`.
- `app/api/download/route.ts`: `GET` → 302 `downloadTarget(getRelease(), file)`, `?file=zip`, `no-store`, runtime nodejs. `app/api/release/route.ts`: `revalidate=3600`, JSON + `s-maxage=3600, swr=86400`.
- `app/licenses/page.tsx`: `public/fonts/LICENSE-*.txt` 를 빌드 때 읽어 `toBlocks()` 로 문단화, 정적 프리렌더. `LicensesNav` + `Headline` + `SiteFooter current="licenses"`.
- `scripts/*`: build-assets(소재 `/Users/yesung/aing-check-promo/public/assets/` → `public/assets/**`·앱 아이콘·`data/generated/*.json`) · subset-fonts(Pretendard ExtraBold 서브셋 + JBM ASCII + 라이선스) · check-glyphs(`prebuild`, 소스 한글 ⊄ 서브셋이면 exit 1) · make-qr.py(App Store QR SVG).

### 2.8 섹션에서 건질 조각(파일은 지움)
- `install-faq/FaqSection.tsx:11–30` `DETAILS`·`OPEN_BAND` 클래스(::details-content 높이 전이, 열린 행 띠)와 `:34·54` JSON-LD 주입 두 줄 — v2 FAQ 가 그대로 가져갈 만하다.
- `InstallFaq.tsx:10–11` `getRelease()` → `installChoice(release, RELEASE_FALLBACK)` 서버 패턴.

### 2.9 `data/fixtures.ts` — 남길 것 / 지울 것
| 남김(정적 데이터) | 지움(상태 기계) |
|---|---|
| `AssetKey` · `SequenceName` · `AssetMeta` · `asset()` · `sequences` · `bubbles` | `HOTSPOTS`(:97–115) · `HotspotKey` · `HotspotSpec` · `Rect`·`HotspotShape` 재내보내기 |
| `PEOPLE`(가상 인물 세트) · `LINKS` · `APP_STORE_ID` · `BREW` | `REACTION_SEQ`(:133–136) — 반응 큐 전용 |
| `LABELS`(라벨 pt 폭·alt) · `PANELS`(렌더 pt 크기 — `overlay:'tick'` 필드만 삭제) | `ANNOUNCE` 의 start·auto·pokeIn·ultra·focus*·msg·sent·read·end·restart → `copied`·`linkCopied` 만 |
| `BUBBLE_TEXT` · `CORNER`(아잉 박스·말풍선 앵커 기하) · `PHONE` · `ALT` | `TIMING` 의 13개 → `copyResetMs` 만 |
| `ReleaseAsset` · `ReleaseInfo` · `RELEASE_FALLBACK`(0.3.48 · 30.0MB) | |
| 신규 인라인 타입: `LabelKey` · `PanelKey` · `BubbleId` · `BubbleArtId`(v1 reducer.ts:13–23 에서 그대로) | |

---

## 3. `CharacterStage` 의 상태 기계 결합부

| 층 | 무엇이 묶였나 | v2 |
|---|---|---|
| import | `Reaction`·`BubbleId` 타입(`lib/demo/types`), `CORNER`·`REACTION_SEQ`(fixtures) | 타입뿐이라 쉽게 떼지만 아래가 본체다 |
| 프로토콜 | `reaction`/`bubble` = `{id, nonce}`(스토어가 올리는 단조 nonce) → 끝나면 `onReactionEnd`/`onBubbleEnd` 로 스토어 큐를 비움. `doneUpTo`·`fadeNonce`·`leaving`: commute_end 가 끝나면 150ms 페이드 → 부모(Corner) 언마운트 | 상태 기계 그 자체 — 삭제 |
| 상호작용 | `onBodyClick`·`bodyExpanded`(aria-controls="todo-board")·`onBubbleClick`(message-gureum → 메시지 열기) | 금지 목록 |
| 캡슐 | `capsule = capsuleText(state)` | 고정 문자열이면 `TimerCapsule` 직접 |
| **건질 것** | idle(loop) + 반응(1회) 두 층, 반응 끝에 idle 을 `(N mod 432)/30`초로 미리 시크해 이음매 없이 잇기 → 순수 함수 `idleResumeFrame()`·`reactionBox()`·`reactionDurationMs()`(103–146행), 탭 숨김 일시정지(visibilitychange), HERO 박스 기하(654×790, d = width/654, 말풍선 `CORNER.bubbleAtOut`) | 새 컴포넌트로 복사 |

새 컴포넌트 제안(구속력 없음, ≈80줄):
```ts
// components/ui/AingClip.tsx — 보일 때만 재생, 클릭 없음, 감속 모션이면 포스터 한 장
interface AingClipProps {
  width: number;             // 높이 = width × 790/654
  once?: SequenceName;       // 'aing-commute-end' 등 — inView 가 처음 true 일 때 한 번, 끝나면 idle 로(idleResumeFrame)
  inView: boolean;           // 부모가 useNearViewport 로
  posterOnly: boolean;       // usePosterOnly()
  bubble?: BubbleKey;        // <Bubble static visible> 를 CORNER.bubbleAtOut 자리에
  capsule?: string;          // <TimerCapsule>
  className?: string;
}
```

---

## 4. 의존 그래프와 삭제 시뮬레이션

### 4.1 삭제 대상을 import 하는 유지 파일(전수, 정규식 import 해석 스크립트로)
| 유지 파일 | 끊을 import | 고칠 줄 |
|---|---|---|
| `app/page.tsx` | sections 9개 | 통째로 스텁(§4.3) |
| `app/licenses/page.tsx:6–7` | `sections/closing-footer/{LicensesNav,SiteFooter}` | `@/components/site/*` |
| `data/fixtures.ts:6,8` | `lib/demo/types` | 타입 인라인 + §2.9 |
| `lib/hooks.ts:5–8,140–152` | `lib/demo/store`·`types` | `ViewportMode` 인라인, `useEnterTimer` 삭제 |
| `components/ui/Bubble.tsx:11–12` | `lib/demo/types` | `type BubbleArtId` 를 fixtures import 에 합침 |
| `CopyButton.tsx:5,55` · `CommandBox.tsx:4,34` · `DownloadCTA.tsx:5,71,74,135` | `lib/demo/store` | `import { announce } from "@/lib/announce"`, DownloadCTA 는 `onDownload` 줄과 `onClick={onDownload}` 삭제 |
| `LiveAnnouncer.tsx:3,9` | `lib/demo/store` | `useAnnouncement()` |
| `components/site/{SiteFooter,LicensesNav}.tsx` | `./links`(이동으로 끊김) | `@/data/site-links` |

나머지 유지 파일(SpritePlayer·AlphaVideo·SheetPlayer·Button·AppStoreBadge·QrCode·RenderImage·MacWindowShell·PhoneShell·Headline·TextLink·VisuallyHidden·PlatformScript·TimerCapsule·lib/{release,site,platform,media}·app/api/*·robots·sitemap·layout)는 삭제 대상을 import 하지 않는다.

### 4.2 사본 시뮬레이션 결과(rsync 사본 + node_modules 심링크, 자기 전용 폴더, 끝나고 지움)
| 단계 | tsc --noEmit | eslint . | 그 밖 |
|---|---|---|---|
| 기준선(손대기 전) | 0 | 0 | |
| A. 이동 9(복사) + 삭제 70 만 | **27 에러 / 11 파일**(TS2307 23 · TS7006 4) | — | 에러 파일 = §4.1 표 그대로 |
| B. A + 수정 9 + `lib/announce.ts` | **0** | **0(경고 0)** | `check-glyphs` OK(소스 34파일 · 한글 315자 ⊂ 서브셋 495자) · `next build` 성공(라우트 10개: / · /licenses · /api/download · /api/release · 아이콘·OG·robots·sitemap) |

`next build` 는 사본에서만 `next.config.ts` 에 `turbopack.root:"/"` 를 넣어 돌렸다(심링크 node_modules 가 사본 밖이라 Turbopack 이 거부). 실제 트리는 바꿀 필요 없다.

### 4.3 스텁 `app/page.tsx`(B 단계에서 쓴 그대로)
```tsx
import { SiteFooter } from '@/components/site/SiteFooter';
import { LiveAnnouncer } from '@/components/ui/LiveAnnouncer';

// v2 스캐폴드 전 자리표시자(teardown 단계). 섹션은 docs/v2/PLAN.md 대로 다시 쓴다.
export const revalidate = 3600;
export default function Page() {
  return (<>
    <main id="main" />
    <SiteFooter />
    <LiveAnnouncer />
  </>);
}
```

---

## 5. 삭제 순서 — 데브 서버(3000)가 켜진 채로

원칙: **새 파일 → import 재작성 → 일괄 삭제.** Turbopack 은 `/` 에서 도달하는 모듈만 컴파일하므로, P2 가 끝나면 v1 체험 코드는 그래프 밖이고 P3 의 삭제가 열린 탭을 깨지 않는다. P2 와 P3 사이에는 tsc 를 돌리지 않는다(아직 남은 v1 파일이 지운 `HOTSPOTS` 를 찾는다).

```sh
cd /Users/yesung/check/landing
# P0 백업 확인 — landing/ 은 git 미추적, 되돌릴 길은 이 tgz 뿐(gitignore 안이라 밖에 사본 하나 권장)
tar -tzf .scratch/landing-v1-2026-10-12.tgz | wc -l          # 269
rm docs/.assets-done docs/.contracts-done docs/.core-done docs/.primitives-a-done docs/.primitives-b-done

# P1 새 파일(아직 아무도 import 하지 않는다 → 데브 그래프 영향 0). mv 가 아니라 cp.
mkdir -p components/site lib/grass
cp components/sections/closing-footer/{SiteFooter,LicensesNav}.tsx components/sections/install-faq/FaqHash.tsx \
   components/sections/menubar-stage/useHeroCtaVisible.ts components/site/
cp components/sections/closing-footer/links.ts data/site-links.ts
cp components/sections/install-faq/{faq-items,install-copy}.ts data/
cp components/sections/character-records/grass-{data,geometry}.ts lib/grass/
#    + lib/announce.ts 작성(§2.4)

# P2 import 지점 재작성 — Edit/Write 또는 `cat > 파일`. sed -i·perl -i 금지(§9-2)
#    app/page.tsx(§4.3) · app/licenses/page.tsx · components/site/{SiteFooter,LicensesNav}.tsx · data/fixtures.ts · lib/hooks.ts
#    components/ui/{Bubble,CopyButton,CommandBox,DownloadCTA,LiveAnnouncer}.tsx

# P3 일괄 삭제(70개 + 이동 원본 9개 = components/sections 65 + lib/demo 5 + ui 9)
rm -r components/sections lib/demo
rm components/ui/{AingStageInline,CharacterStage,Hotspot,PanelSlot,RenderStack,SectionShell,Segmented,TickStrip,TimeMark}.tsx

# P4 검증 — exit code 로 판정(| grep·| tail 로 가리지 않는다)
npx tsc --noEmit && npx eslint . && node scripts/check-glyphs.mjs
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3000/            # 200
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3000/licenses    # 200

# P5 package.json:12 test:store 줄 삭제 · README(§6) · docs v1 머리표(§1.5)
```

데브 서버를 신경 쓰지 않아도 되면 P1–P3 을 한 번에 해도 된다(B 단계가 그 경우다).

---

## 6. 설정·스크립트에서 같이 바꿀 줄

| 파일 | 줄 | 변경 |
|---|---|---|
| `package.json` | 12 | `"test:store": "node --experimental-strip-types --test lib/demo/reducer.test.ts"` 삭제. 나머지 scripts 그대로. `motion`(18)은 사용처 0 — PLAN 결정 |
| `README.md` | 11 | `npm run typecheck && npm run lint && npm run test:store` → `npm run typecheck && npm run lint` |
| `README.md` | 14–19 | 정본 → `docs/v2/{SPEC,PLAN,DECISIONS}.md`, v1 세 문서는 "거부된 v1 기록" |
| `README.md` | 27 | "Pretendard 800 서브셋" → v2 가중치대로 |
| `tsconfig.json` | — | 바꿀 것 없음. `allowImportingTsExtensions`(14)는 reducer.test.ts 의 `'./reducer.ts'` 때문이었다 — 무해, v2 node 테스트가 쓰면 필요 |
| `eslint.config.mjs` · `next.config.ts` · `vercel.json` · `AGENTS.md` | — | 그대로 |
| `.gitignore` | 49–50 | `docs/.*-done` 그대로(표식 방식 재사용 가능). 표식 파일 5개만 지운다 |
| `scripts/subset-fonts.mjs` | 61–63 | `--from-spec` 이 `docs/SPEC.md` §4·§6 을 읽는다 → v2 스캐폴드가 이 모드를 쓰면 `docs/v2/SPEC.md` 와 v2 절 번호로 |
| `scripts/subset-fonts.mjs` | 82, 93–98 | 가중치를 늘리면 원본 목록·출력 파일 추가(가중치당 ≈35KB) |
| `scripts/check-glyphs.mjs` | 25–26 | `SUB_TXT` 가 `pretendard-800-sub.txt` 하나만 본다. 가중치별 서브셋이면 각각 검사. `SCAN_DIRS` 에 `lib` 없음(§1.2) |
| `scripts/build-assets.mjs` | 75·86·90·92·103·137–144·164·283–299·507·547–559 | 에셋을 빼려면 **레시피 줄 + 검증 목록 + `AssetKey` 를 함께**. 파일만 지우면 다음 `npm run assets` 가 되살리거나 "출력 없음"으로 exit 1 |

---

## 7. 줄어드는 바이트와 더는 안 쓸 에셋 후보

- 소스: 파일 삭제 −334,040B(7,433줄) + 수정 −3,898B(`announce` +883 포함) = **−337,938B**. 남는 소스 131,823B.
- 클라이언트 JS 의 대부분이 상태 기계·스파인·코너였다(v1 첫 화면 310KB · 전체 4.2MB, 2026-10-12 13:30 실측). v2 예산(첫 화면 ≤ 400KB)은 이 철거로 여유가 생긴다 — 실측은 v2 통합 때.
- `public/assets/`: 74파일 · 7,673,597B. **지우지 않는다** — 최종 목록은 v2 SPEC §에셋 표가 정한다. 아래는 후보.

**A 후보 — 체험 상태 전용(v2 에 자리가 거의 없음), 243,798B**
| 파일 | 바이트 | 왜 | build-assets 줄 |
|---|---|---|---|
| `ui/popover-tick-strip.webp` (+ sequences.json `tick`) | 91,398 | 틱 띠 스프라이트(TickStrip) | 299·507·547 |
| `ui/poke-cooldown.webp` | 43,786 | 찌른 '뒤' 쿨타임 판 | 75 |
| `ui/token-last.webp` | 43,688 | 토큰 이전/다음 토글의 다른 판 | 86 |
| `ios/widget-todos-large-checked.webp` | 19,598 | 위젯 체크 토글 결과 | 164 |
| `ui/gomoku-board-sm.webp` | 15,578 | phone 게임 창 변형 | 283·549 |
| `ui/grass-{work,token}-empty.webp` | 18,170 | 점등 바탕 — `lib/grass` 를 안 쓰면 | 90·92 |
| `ui/header-off-1702.webp` | 8,172 | 다시 시작 핫스팟 카드 | 288·549 |
| `ui/menubar-0100.webp` | 3,408 | 하루 서사 01:00 | 103 |

**B 후보 — v2 디자인이 행 리빌 오브젝트로 쓰면 남김, 3,197,942B(브라우저는 webm/mov 중 하나만 받는다)**
| 파일 | 바이트 | 메모 |
|---|---|---|
| `char/aing-ultra.{webm,mov}` + `aing-ultra-poster.webp` + `ui/bubble-ultra-mint.webp` | 1,320,780 | 울트라 전면 오버레이. 기능은 포스터 한 장으로도 보인다 |
| `char/aing-milestone.{webm,mov}` | 741,091 | 색종이 반응 |
| `char/aing-poked.{webm,mov}` | 588,565 | 콕 찌르기 행의 1회 리빌로 쓸 수 있다 |
| `char/aing-ultra-charged.{webm,mov}` | 547,506 | 울트라 충전 반응 |

확실히 남김: `aing-idle`(+15fps 판)·`commute-start`·`commute-end`·포스터 · 팝오버 렌더 전부 · 말풍선(콕·메시지·루비 — 레퍼런스의 "알림 카드" 자리) · iOS 화면·위젯 · brand.

---

## 8. v2 `globals.css` 가 지켜야 할 이름(유지 컴포넌트 호환, 사본에서 grep 실측)

값은 v2 토큰으로 바꾸되 **이름**을 바꾸면 아래 파일을 같이 고쳐야 한다.
- CSS 변수: `--t-quick`(8) `--r-pill`(5) `--t-resize`(4) `--ease-out`(3) `--shadow-window`(2) `--r-window`(2) `--gutter`(2) · 1회씩 `--z-nav` `--z-ultra`(LicensesNav 건너뛰기 링크) `--r-tip` `--r-seg-in` `--r-nav` `--r-code` `--nav-h` `--edge` `--font-display` `--font-code`.
- 색 유틸리티(`@theme inline` 의 `--color-*`): `text-ink-1`(14) `text-ink-2`(6) `bg-surface`(5) `text-aing`·`border-line-strong`·`border-line`·`border-aing`(3) `text-on-aing`·`text-ink-3`·`bg-surface-2`·`bg-aing/12`·`bg-aing-hover`·`bg-aing`(2) `text-aing-hover`·`border-aing-hover`·`bg-bg-0`(1).
- 타입 클래스: `t-button-s`(7) `t-small`(4) `t-button`·`t-code`(3) `t-display`·`t-h3`·`t-micro`·`t-nav`(2) `t-closing`·`t-h2`·`t-h2-solo`(Headline `SIZE_CLASS` :18–24). Headline 은 `font-extrabold` 고정 — 큰 숫자를 가볍게 쓰려면 Headline 밖에서.
- 변형: `desk:`(10) `phone:`(9) `tab:`(5) → `@custom-variant` 3줄(:5–7) 유지. `lib/hooks.ts` MQ_* 와 같은 문자열.
- 전역 클래스: `btn-primary`(포커스 오프셋 :45) · `cta-mac/ios/other`(:101–104) · `sr-only`(:83–86) · `disclosure`(FAQ ▸ :89–96, 회전 전이 :132).
- 철거 뒤 사용처 0(지워도 됨): `--hotspot` `--app-mint` `--app-coral-a/b` `--scrim-sheet` `--render-window` `--r-label` `--r-seg` `--t-base` `--t-overlay` `--t-move` `--spine-gap` `--z-spine` `--z-corner` `--z-board` · 키프레임 `spine-drop-*`·`hotspot-pulse`·`label-glow`. `--bg-1`·`--ease-in` 은 지금 0 이지만 v2 brief·FAQ 가 쓸 수 있다.

---

## 9. 데브 서버가 켜진 채 삭제·재작성할 때의 함정

1. **Turbopack "HMR hash mismatch" 무한 새로고침** — 대량 삭제·재작성 직후 잘 난다. 서버를 끄고 `rm -rf .next/dev` 뒤 `npm run dev`(포트 3000). 출처: 메모리 `landing-page-project`. 재기동은 리드·사용자 몫(설계 단계는 pid 14129/14130 을 건드리지 않는다).
2. **`sed -i`(그리고 `perl -i`)는 파일을 새 inode 로 바꿔치기한다** → dev 가 그 파일 변경을 놓친다. Edit/Write 도구나 `cat > 파일`(같은 inode 에 덮어쓰기)로. 출처: 같은 메모.
3. **삭제보다 import 끊기가 먼저**(§5 P2 → P3). 거꾸로 하면 열린 탭이 "Module not found" 오버레이를 띄우고, 그 상태의 HMR 이 1번으로 번진다.
4. `.next/dev/types/validator.ts`·`.next/types/*` 는 라우트 파일만 본다(tsconfig include :30–31). 컴포넌트 삭제와 무관. 라우트를 옮기거나 지우면 dev 가 다시 쓸 때까지 tsc 가 옛 경로를 찾는다.
5. `tsconfig.tsbuildinfo`(incremental)는 지울 필요 없다(사본에서 그대로 0 에러).
6. 브라우저 sessionStorage `aing:hidden`·`aing:installHint` 는 v1 이 남긴 값 — 읽는 코드가 사라져 무해. 확인 탭은 강력 새로고침.
7. 삭제는 `rm`(미추적이라 `git rm` 대상이 아니고 git 명령은 금지). `git status --short landing` 은 늘 `?? landing/` 한 줄이라 안쪽 잔재(덤프·스크린샷)는 `ls -R` 로 따로 본다. 데브 로그 `.scratch/dev.log`, 검수 하네스는 DECISIONS §3(playwright 1.60, `landing/` 밖).
