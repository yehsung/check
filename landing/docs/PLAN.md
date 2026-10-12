> 거부된 v1(2026-10-12 15:50). v2 정본은 `docs/v2/`(SPEC·PLAN·DECISIONS). 이 문서의 SPEC §1.4 사실 규칙·§9 에셋 표, 그리고 `docs/v2/DECISIONS.md` §1 표에 적힌 v1 결정만 v2 가 승계한다.

# 아잉체크 랜딩 — 병렬 구현 계획 (PLAN-files)

작성 2026-10-12 · 짝 문서: `SPEC-final.md`(디자인 정본 — 카피·상태·좌표·토큰은 전부 거기). 이 문서는 **누가 어떤 파일을 만들고, 서로 무엇을 약속하는가**만 정한다.
프로젝트 루트: **`/Users/yesung/check/landing`** (Next.js 15 App Router · TypeScript · Tailwind v4 · motion 12 · sharp devDependency). 저장소의 다른 폴더(Sources·Tests 등에 다른 작업의 미커밋 변경이 있다)는 읽지도 고치지도 않는다.

---

## 0. 단계

| 단계 | 누가 | 무엇 | 끝나는 조건 |
|---|---|---|---|
| 0 스캐폴드 | 에이전트 1명(`scaffold`) | 공용 파일 전부(§2 '공용'), 에셋 내보내기 실행, 글꼴 서브셋, 섹션 9개의 **컴파일되는 스텁**, `docs/` | `npm run typecheck` 0 에러 · `npm run lint` 0 에러 · `npm run test:store` 통과 · `npm run build` 성공 · `public/assets` 에 §5 의 파일 전부 · 스텁 페이지가 dev 에서 섹션 앵커 13개(+푸터)를 그린다(스캐폴드 혼자 쓰는 시점이라 build·dev 허용, 끝나면 프로세스 종료) |
| 1 섹션 | 에이전트 9명 동시(`stage-menubar` · `stage-corner` · `hero` · `team-poke` · `message-games` · `character-records` · `iphone-trust` · `install-faq` · `closing-footer`) | 자기 섹션 파일과 그 하위 폴더만 | 각자 §4 수용 기준 + `npx tsc --noEmit` 0 에러 + `npx eslint <자기 파일들>` 0 에러. **next build·dev 금지** |
| 2 통합 | 에이전트 1명(`integration`) | requests 처리, 공용 파일 수정, build·dev, Playwright 수용 테스트(§7), OG 이미지 캡처, 성능 측정, 잔여 프로세스 정리 | §7 전부 초록 |

예상: 0단계 3–4시간(에셋 영상 인코딩 ≈1–2분 포함), 1단계 2–3시간, 2단계 2시간.

---

## 1. 디렉터리 구조

```
landing/
  package.json  tsconfig.json  next.config.ts  postcss.config.mjs  eslint.config.mjs
  vercel.json  next-env.d.ts  .gitignore  playwright.config.ts
  app/
    layout.tsx               # 글꼴(next/font/local), 메타, PlatformScript, <body>
    globals.css              # SPEC §2.8 토큰 + .t-* 타입 클래스 + 키프레임
    page.tsx                 # 섹션 조립(서버 컴포넌트, revalidate 3600)
    icon.png  apple-icon.png # 내보내기 스크립트 생성
    opengraph-image.png      # 통합 단계에서 캡처(그 전엔 없음)
    licenses/page.tsx        # closing-footer 소유
    api/download/route.ts    # DMG 302
    api/release/route.ts     # 릴리스 JSON
  components/
    SpritePlayer.tsx         # 시퀀스 플레이어(video·sheet)
    sprite/AlphaVideo.tsx  sprite/SheetPlayer.tsx
    ui/                      # 공용 프리미티브(§3.3)
    sections/
      MenubarStage.tsx   menubar-stage/…      # stage-menubar
      AingCorner.tsx     aing-corner/…        # stage-corner
      HeroAuto.tsx       hero-auto/…          # hero
      TeamPoke.tsx       team-poke/…          # team-poke
      MessageGames.tsx   message-games/…      # message-games
      CharacterRecords.tsx character-records/… # character-records
      IphoneTrust.tsx    iphone-trust/…       # iphone-trust
      InstallFaq.tsx     install-faq/…        # install-faq
      ClosingFooter.tsx  closing-footer/…     # closing-footer
  lib/
    demo/reducer.ts  demo/reducer.test.ts  demo/store.ts  demo/selectors.ts
    release.ts  media.ts  platform.ts  hooks.ts
  data/
    fixtures.ts                               # SPEC §6 전문
    generated/assets.json  sequences.json  bubbles.json  grass.json   # 스크립트 생성
  scripts/
    build-assets.mjs  subset-fonts.mjs  check-glyphs.mjs  make-qr.py
  public/
    assets/{ui,char,ios,brand}/…              # 스크립트 생성, 커밋
    fonts/pretendard-800-sub.woff2  pretendard-800-sub.txt  jbm-400-ascii.woff2  LICENSE-*.txt
  docs/
    SPEC.md  PLAN.md                          # 이 두 문서의 사본(스캐폴드가 복사)
    requests/                                 # 섹션 에이전트의 공용 파일 변경 요청
  tests/e2e/                                  # integration 소유
```

---

## 2. 파일 소유권

| 파일 | 소유 | 비고 |
|---|---|---|
| `package.json` · `tsconfig.json` · `next.config.ts` · `postcss.config.mjs` · `eslint.config.mjs` · `vercel.json` · `.gitignore` · `next-env.d.ts` | scaffold | 이후 integration 만 수정 |
| `app/layout.tsx` · `app/globals.css` · `app/page.tsx` · `app/icon.png` · `app/apple-icon.png` | scaffold | page.tsx 의 조립 순서는 §3.10 으로 고정 |
| `app/api/download/route.ts` · `app/api/release/route.ts` · `lib/release.ts` | scaffold | |
| `components/SpritePlayer.tsx` · `components/sprite/*` | scaffold | |
| `components/ui/*`(§3.3 전부) | scaffold | |
| `lib/demo/*` · `lib/media.ts` · `lib/platform.ts` · `lib/hooks.ts` | scaffold | |
| `data/fixtures.ts` · `data/generated/*` | scaffold | generated 는 스크립트 출력 |
| `scripts/*` · `public/assets/**` · `public/fonts/**` | scaffold | |
| `docs/SPEC.md` · `docs/PLAN.md` | scaffold | 사본 |
| `docs/requests/<agent>.md` | 각 섹션 에이전트(자기 파일만) | |
| `components/sections/MenubarStage.tsx` + `components/sections/menubar-stage/**` | stage-menubar | 스텁은 scaffold 가 만들고 넘긴다 |
| `components/sections/AingCorner.tsx` + `aing-corner/**` | stage-corner | |
| `components/sections/HeroAuto.tsx` + `hero-auto/**` | hero | |
| `components/sections/TeamPoke.tsx` + `team-poke/**` | team-poke | |
| `components/sections/MessageGames.tsx` + `message-games/**` | message-games | |
| `components/sections/CharacterRecords.tsx` + `character-records/**` | character-records | |
| `components/sections/IphoneTrust.tsx` + `iphone-trust/**` | iphone-trust | |
| `components/sections/InstallFaq.tsx` + `install-faq/**` | install-faq | |
| `components/sections/ClosingFooter.tsx` + `closing-footer/**` + `app/licenses/page.tsx` | closing-footer | |
| `tests/e2e/**` · `playwright.config.ts` · `app/opengraph-image.png` | integration | |

섹션 에이전트는 다른 섹션 파일을 **import 하지 않는다**(공용 `components/ui`·`lib`·`data` 만). 공용 파일은 1단계 동안 아무도 고치지 않는다.

---

## 3. 공용 API(스캐폴드가 이 서명 그대로 만든다)

### 3.1 상태 스토어 `lib/demo/store.ts` · `reducer.ts` · `selectors.ts`
SPEC §3 이 동작 정본. 서명:
```ts
// reducer.ts — 순수 함수, import 없음(node --experimental-strip-types 로 테스트)
export type Work = 'off'|'on'|'ended';
export type SectionId = 'hero'|'auto'|'team'|'poke'|'message'|'games'|'character'|'records'|'iphone'|'trust'|'install'|'faq'|'closing';
export type Scene = 'am'|'hour1'|'noon'|'evening';
export type Reaction = 'commute_start'|'commute_end'|'poked'|'message_received'|'milestone'|'ultra_charged';
export type BubbleId = 'commute-start'|'autostart'|'poked-mint'|'message-gureum'|'commute-end'|'ruby';
export interface DemoState { /* SPEC §3.1 그대로 */ }
export type DemoEvent =
  | { type:'PRESS_START'; now:number } | { type:'AUTO_START'; now:number }
  | { type:'SET_SECTION'; id:SectionId; now:number } | { type:'SET_BEAT'; beat:string|null }
  | { type:'SET_AUTO_PASSED'; n:0|1|2; now:number }
  | { type:'TOGGLE_SPINE' } | { type:'TOGGLE_LABEL_POPOVER'; open?:boolean } | { type:'SET_SPINE_RECT'; rect:DemoState['spine']['rect'] }
  | { type:'SET_TEAM'; v:'members'|'league' } | { type:'SET_GAMES'; v:'flappy'|'gomoku' } | { type:'SET_GRASS'; v:'work'|'token' }
  | { type:'SET_TOKENS'; v:'month'|'last' } | { type:'SET_PHONE'; v:DemoState['phone'] } | { type:'TOGGLE_WIDGET' }
  | { type:'CYCLE_FOCUS' } | { type:'POKE_IN'; now:number } | { type:'POKE_BACK' }
  | { type:'ULTRA_WAIT' } | { type:'ULTRA_PLAY' } | { type:'ULTRA_DONE' }
  | { type:'MSG_ARRIVE'; now:number } | { type:'MSG_OPEN' } | { type:'MSG_SEND' } | { type:'MSG_READ' }
  | { type:'TOGGLE_TODO'; force?:boolean } | { type:'HIDE_CORNER'; now:number }
  | { type:'PRESS_END'; now:number } | { type:'RESTART'; now:number }
  | { type:'INSTALL_CLICKED' } | { type:'REACTION_DONE'; nonce:number } | { type:'BUBBLE_DONE'; nonce:number }
  | { type:'PLAY_PENDING'; now:number } | { type:'ANNOUNCE'; text:string };
export const initialState: (hidden:boolean, installHint:boolean) => DemoState;
export function reduce(s: DemoState, e: DemoEvent): DemoState;
export function sceneOf(s: DemoState): Scene;

// selectors.ts
export type ViewportMode = 'desk'|'tab'|'phone';
export function labelKey(s: DemoState): LabelKey;              // SPEC §3.3
export function capsuleText(s: DemoState): string|null;        // '00:00'|'01:00'|'03:45'|'06:42'|null
export function panelFor(section: SectionId, beat: string|null, s: DemoState): PanelKey|null;
export function isSpineSection(id: SectionId): boolean;        // hero·team·poke·message·character·records
export function spineOpen(s: DemoState, mode: ViewportMode): boolean;
export function labelPanel(s: DemoState): PanelKey|null;
export function gamesValue(s: DemoState, mode: ViewportMode): 'flappy'|'gomoku'; // s.games ?? (phone ? 'gomoku' : 'flappy')

// store.ts — 'use client'. 타이머·sessionStorage·announce 큐는 여기에만
export function useDemo<T>(selector: (s: DemoState) => T): T;   // useSyncExternalStore
export function getDemo(): DemoState;
export const demo: {
  pressStart(): void; autoStart(): void; setActiveSection(id: SectionId): void; setActiveBeat(beat: string|null): void;
  setAutoPassed(n: 0|1|2): void;                                  // 400ms 머묾 판정은 호출하는 쪽(useCenterLine)
  toggleSpine(): void; toggleLabelPopover(open?: boolean): void; setSpineRect(r: DemoState['spine']['rect']): void;
  setTeam(v: 'members'|'league'): void; setGames(v: 'flappy'|'gomoku'): void; setGrass(v: 'work'|'token'): void;
  setTokens(v: 'month'|'last'): void; setPhone(v: DemoState['phone']): void; toggleWidget(): void;
  cycleFocus(): void; pokeIn(): void; pokeBack(): void;          // pokeBack 은 1000ms 뒤 ultraIn 을 스스로 부른다
  ultraReady(): void; ultraDone(): void;                          // 오버레이가 영상 준비·끝을 알린다(대기 2500ms 초과는 store 가 포스터로 강제)
  msgArrive(): void; msgOpen(): void; msgSend(): void;           // msgSend 는 1600ms 뒤 MSG_READ
  toggleTodo(force?: boolean): void; hideCorner(): void;
  pressEnd(): void; restart(): void; installClicked(placement: 'nav'|'hero'|'install'|'closing'): void;
  reactionDone(nonce: number): void; bubbleDone(nonce: number): void; announce(text: string): void;
};
```
- 진입 지연 타이머(autostart 700 · pokeIn 1200 · msgArrive 800)는 **섹션 쪽 훅 `useEnterTimer(sectionId, ms, action)`**(lib/hooks.ts)이 건다. 섹션이 지연 시간 안에 비활성이 되면 취소.
- `reducer.test.ts`(node:test): 초기값, PRESS_START, AUTO_START once, SET_SECTION 으로 jump/rewind, SET_AUTO_PASSED 반응과 pending, sceneOf 표(SPEC §3.3) 전부, labelKey 6가지, panelFor 표 전부, focus 중 POKE_IN·POKE_BACK 무시, MSG 흐름, PRESS_END→RESTART→06:42, 반응 최소 간격(pending).

### 3.2 훅·유틸 `lib/hooks.ts` · `lib/media.ts` · `lib/platform.ts`
```ts
export const MQ_DESK = '(min-width: 1024px) and (min-height: 640px)';
export const MQ_TAB = '(min-width: 768px) and ((max-width: 1023.98px) or (max-height: 639.98px))';
export const MQ_PHONE = '(max-width: 767.98px)';
export function useViewportMode(): ViewportMode;                 // SSR 기본 'desk'(CSS 가 첫 페인트를 책임진다)
export function useReducedMotion(): boolean;                      // SSR false, 전이 시간에만 쓴다(initial 분기 금지)
export function usePosterOnly(): boolean;                         // reducedMotion || saveData
export function useNearViewport(ref, rootMargin = '600px'): boolean;   // 한 번 true 가 되면 유지
export function useCenterLine(ref, onChange: (passed: boolean) => void, dwellMs = 0): void; // 뷰포트 중앙선 위로 지났는지
export function useEnterTimer(id: SectionId, ms: number, fn: () => void, enabled = true): void;
export function useInViewRatio(ref, ratio: number): boolean;      // 50% 보임 판정 등
// media.ts
export function pickVideoFormat(): 'mov'|'webm';                  // SPEC §3.4 UA 규칙
export function wantsLowFps(): boolean;                           // phone || saveData || deviceMemory ≤ 4
export function preloadImage(src: string): Promise<void>;          // new Image + decode
export function idle(fn: () => void): void;                       // requestIdleCallback 폴백 setTimeout 200
// platform.ts
export type Platform = 'mac'|'ios'|'other';
export const PLATFORM_SCRIPT: string;                              // SPEC §8.4 인라인 스크립트 원문
export function getPlatform(): Platform;                          // <html data-platform> 읽기
```

### 3.3 공용 프리미티브 `components/ui/*`(props 확정)
| 이름 | props | 메모 |
|---|---|---|
| `Button` | `{ variant: 'primary'\|'secondary'\|'ghost'; size?: 'l'\|'m'\|'s'; href?: string; onClick?: () => void; external?: boolean; disabled?: boolean; ariaLabel?: string; className?: string; children }` | primary = 라벤더 채움 h48(l)/h40(m)/h32(s). secondary = `--line-strong` 테두리 + `--ink-1`. 끝 화살표 없음 |
| `DownloadCTA` | `{ placement: 'nav'\|'hero'\|'install'\|'closing'; size: 'l'\|'s'; tone?: 'fill'\|'outline'; label?: string; file?: 'dmg'\|'zip' }` | 세 벌 SSR(`.cta-mac/.cta-ios/.cta-other`). mac·other = `<a href="/api/download">`(onClick `demo.installClicked`) — 단 nav 의 phone 폭에서는 `설치`(`#install`) 링크. ios = nav 에선 App Store 링크, 그 밖에선 `Mac 링크 보내기`(share → 클립보드 폴백) |
| `AppStoreBadge` | `{ height?: 40\|44\|48; placement: string }` | `/assets/brand/appstore-badge-ko-black.svg`, 사방 여백 = 높이/4, `alt="App Store에서 다운로드"`, 새 탭 |
| `QrCode` | `{ size?: number }` | 기본 112, `desk:` 에서만 보임, 흰 타일 |
| `TextLink` | `{ href; external?; children }` | `--aing`, 밑줄 1px 오프셋 3 |
| `SectionShell` | `{ id: SectionId; kind: 'spine'\|'plain'\|'band'; minH?: string; className?; children }` | `<section id aria-labelledby>`, IO(-45%/-45%) + focusin → `demo.setActiveSection` |
| `Beat` | `{ id: string; children }` | 섹션 안 두 번째 박자. 같은 IO 로 걸리면 `setActiveBeat(id)`, 벗어나면 `setActiveBeat(null)` |
| `Headline` | `{ level: 1\|2\|3; size: 'display'\|'closing'\|'h2'\|'h2-solo'\|'h3'; lines: string[]; id?: string }` | `lines` 사이에 `<br>` |
| `TimeMark` | `{ time: '14:05'\|'17:02' }` | desk 는 거터 매달림(부모 relative), tab·phone 은 H2 위 |
| `MacWindowShell` | `{ widthPt: number; heightPt: number; scale: number; className?; children }` | `--r-window`, `--shadow-window`, overflow hidden, 높이 전이 200ms |
| `RenderImage` | `{ asset: AssetKey; widthPt: number; heightPt: number; alt: string; eager?: boolean; className? }` | `<img>` + 명시 크기 + `decoding="async"` |
| `RenderStack` | `{ panels: PanelKey[]; active: PanelKey; scale: number; instant?: boolean; tickStartedAt?: number\|null }` | 위쪽 정렬 겹침, decode 후 위 판 불투명 180ms 선형(instant 면 0), `overlay:'tick'` 이면 TickStrip |
| `Hotspot` | `{ rect: Rect; shape: HotspotShape; radiusPt?: number; scale: number; label: string; onActivate: () => void; focusable?: boolean; disabled?: boolean; pressed?: boolean; role?: 'button'\|'checkbox'\|'tab'; checked?: boolean; selected?: boolean; pulse?: boolean; minHit?: number }` | 투명 `<button>`, 호버 링 `--hotspot` 2px(70%), 포커스 라벤더, 히트 최소 44, `pulse` = 1회 맥동. URL 에 `?hotspots=1` 이면 링을 늘 켠다(좌표 보정용, 개발·통합 전용) |
| `PanelSlot` | `{ section: SectionId; beat?: string\|null; panels: PanelKey[]; hotspots: SlotHotspot[]; inlineWidth?: string; className?; children? }` | §3.4 |
| `Segmented` | `{ options: {id: string; label: string}[]; value: string; onChange: (id: string) => void; ariaLabel: string }` | radiogroup, 화살표 키, 알약 이동 180ms |
| `CopyButton` | `{ text: string; label?: string; done?: string; ariaLabel: string; variant?: 'inline'\|'secondary' }` | 기본 '복사'/'복사했어요', 2초, 실패 시 onFail 콜백 |
| `CommandBox` | `{ command: string; copyAriaLabel: string }` | `$ ` 접두(복사에서 제외), `--surface`, `t-code` |
| `Bubble` | `{ id: BubbleId \| 'ultra-mint' \| 'update'; scale: number; visible: boolean; onClick?: () => void; static?: boolean }` | generated/bubbles.json 의 이미지·크기, 등장/퇴장 전이 |
| `TimerCapsule` | `{ text: string; fontPx: number }` | SPEC 공통 C 스펙 |
| `PhoneShell` | `{ screenWidth: number; children }` | SPEC 공통 P |
| `TickStrip` | `{ startedAt: number\|null; scale: number }` | SpritePlayer(sheet) 래퍼 |
| `CharacterStage` | §3.6 | |
| `AingStageInline` | `{ section: SectionId; size: 'inline'\|'inline-lg'; className?; style? }` | phone 모드 + 활성 섹션 + work=on 일 때만 그린다 |
| `LiveAnnouncer` | — | `aria-live="polite"` 한 곳, store.announce 구독 |
| `VisuallyHidden` | `{ as?: keyof JSX.IntrinsicElements; children }` | |
| `PlatformScript` | — | `<script dangerouslySetInnerHTML={{__html: PLATFORM_SCRIPT}} />` |

### 3.4 PanelSlot(스파인과 섹션을 잇는 계약)
```ts
type SlotHotspot = {
  key: keyof typeof HOTSPOTS;          // 좌표·모양·패널 목록은 fixtures 에서
  label: string; onActivate: () => void;
  focusable?: boolean; disabled?: boolean; pulse?: boolean;
  role?: 'button'|'checkbox'|'tab'; checked?: boolean;
};
```
- **desk**: 아무것도 그리지 않는 대신, `section` 이 활성이고 `spineOpen` 이며 `spine.rect` 가 있을 때 현재 패널(`panelFor(section, beat, s)`)에 속한 핫스팟만 `position: fixed` 로 `left = rect.x + x·rect.scale` 등에 맞춰 그린다(DOM 은 섹션 안 — 탭 순서가 "섹션 글 → 그 섹션 핫스팟"). 비활성이면 `inert`.
- **tab·phone**: `MacWindowShell`(폭 `inlineWidth` 기본 `min(100%, 380px)`, 배율 = 폭/414) 안에 `RenderStack(panels, active=panelFor…)` + 같은 핫스팟을 absolute 로. `children` 은 렌더 위에 겹칠 것(예: 인라인 무대)을 받는다.
- `panels` 는 그 섹션에서 나올 수 있는 판 전부(미리 받기 대상). 스파인(MenubarStage)은 같은 `panelFor` 로 그림을 고른다 — 섹션은 그림을 고르지 않는다.

### 3.5 SpritePlayer 와 시퀀스 메타
```ts
// components/SpritePlayer.tsx ('use client')
export type SequenceName = 'aing-idle'|'aing-commute-start'|'aing-commute-end'|'aing-poked'|'aing-milestone'|'aing-ultra-charged'|'aing-ultra'|'tick';
export interface SpritePlayerHandle { play(): Promise<void>; pause(): void; seekToFrame(n: number): Promise<void>; readonly ready: boolean; }
export interface SpritePlayerProps {
  name: SequenceName;
  play: boolean;                 // true 면 재생(loop 이면 계속), false 면 현재 프레임 정지
  frame?: number;                // sheet 백엔드: 보여 줄 칸(외부 제어). video: 무시
  displayWidth: number;          // CSS px. 높이는 메타 비율
  loop?: boolean;                // 메타 기본값 덮어쓰기
  lowFps?: boolean;              // 메타에 15fps 판이 있으면 그것
  posterOnly?: boolean;          // 감속 모션·Save-Data·오류 → 포스터 <img> 만, 영상 요청 0건
  preload?: 'none'|'metadata'|'auto';
  priority?: boolean;            // 포스터 fetchpriority="high"
  onReady?: () => void; onEnded?: () => void; onError?: () => void;
  className?: string; style?: React.CSSProperties;
}
export const SpritePlayer: React.ForwardRefExoticComponent<SpritePlayerProps & React.RefAttributes<SpritePlayerHandle>>;
export function sequenceMeta(name: SequenceName): SequenceMeta;
export function preloadSequence(name: SequenceName, lowFps?: boolean): Promise<void>;
```
`data/generated/sequences.json` 형식(스크립트가 쓰고 SpritePlayer 가 읽는다):
```json
{
  "version": 1,
  "canvas": { "main": [2100, 2625], "ultra": [2160, 2160] },
  "heroBox": [424, 544, 1308, 1580],
  "sequences": {
    "aing-idle": {
      "kind": "video", "fps": 30, "frames": 432, "loop": true, "canvas": "main",
      "box": [424, 544, 1308, 1580], "scale": 0.5, "size": [654, 790], "offsetOut": [0, 0], "gop": 30,
      "src": { "webm": "/assets/char/aing-idle.webm?v=…", "mov": "/assets/char/aing-idle.mov?v=…" },
      "low": { "fps": 15, "frames": 216, "src": { "webm": "/assets/char/aing-idle-15.webm?v=…", "mov": "/assets/char/aing-idle-15.mov?v=…" } },
      "poster": "/assets/char/aing-idle-poster.webp?v=…", "posterFrame": 0,
      "bytes": { "webm": 0, "mov": 0 }
    },
    "aing-milestone": { "kind": "video", "fps": 30, "frames": 72, "loop": false, "canvas": "main",
      "box": [308, 544, 1544, 1580], "scale": 0.5, "size": [772, 790], "offsetOut": [-58, 0], "src": { "webm": "…", "mov": "…" }, "poster": null },
    "aing-ultra-charged": { "…": "box [452,1032,1228,1160], size [614,580], offsetOut [14,244]" },
    "aing-ultra": { "kind": "video", "fps": 30, "frames": 72, "loop": false, "canvas": "ultra",
      "box": [260, 48, 1680, 1476], "scale": 0.5, "size": [840, 738], "offsetOut": null,
      "src": { "webm": "…", "mov": "…" }, "poster": "/assets/char/aing-ultra-poster.webp?v=…", "posterFrame": 40 },
    "tick": { "kind": "sheet", "fps": 1, "frames": 12, "loop": false, "hold": "last",
      "src": "/assets/ui/popover-tick-strip.webp?v=…", "frameSize": [180, 1010], "cols": 12, "rows": 1, "displayPt": [90, 505] }
  }
}
```
- `offsetOut` = 이 시퀀스 박스 원점 − HERO 박스 원점, × scale(출력 px). CharacterStage 가 반응 층을 `offsetOut × d` 만큼 옮겨 겹친다(d = 표시폭/654).
- video 백엔드: `pickVideoFormat()` 으로 src 하나만 붙인다. `muted playsInline`, `disablePictureInPicture`, `preload` 기본 'metadata'. `seekToFrame(n)` = `currentTime = (n + 0.5)/fps` 후 `seeked` 를 기다리는 Promise(최대 300ms). `error` → `onError` + 포스터.
- sheet 백엔드: `<div>` + `background-image` · `background-size: cols×displayW` · `background-position: -frame×displayW`. 외부 `frame` 으로 제어(TickStrip 이 1초마다 갱신, 감속 모션에서도 동작 — 숫자 교체라 움직임이 아니다).

### 3.6 CharacterStage(코너·인라인 무대 공통)
```ts
// components/ui/CharacterStage.tsx ('use client')
export interface CharacterStageProps {
  width: number;                          // 124.6(코너) · 110 · 180 · (tab 112.1)
  reaction: { id: Reaction; nonce: number } | null;
  bubble: { id: BubbleId; nonce: number } | null;
  capsule: string | null;                 // '00:00' 등. 울트라 중 null
  active: boolean;                        // false 면 idle 일시정지(탭 숨김·울트라·비활성 섹션)
  posterOnly: boolean; lowFps: boolean;
  onReactionEnd: (nonce: number) => void;
  onBubbleEnd: (nonce: number) => void;
  onBodyClick?: () => void; bodyLabel?: string;
  onBubbleClick?: (id: BubbleId) => void;
  entering?: 'commute' | 'fade' | null;   // 첫 마운트 방식
  leaving?: boolean;                      // commute_end 끝나면 150ms 페이드
  className?: string; style?: React.CSSProperties;
}
```
SPEC §3.4 의 층·미리 시크·반응 → 영상 매핑을 그대로 구현한다. 위치 지정(fixed·회피·인라인 자리)은 부모(AingCorner·AingStageInline)의 일이다.

### 3.7 서버: `lib/release.ts` · 라우트
```ts
export type ReleaseAsset = { name: 'aing-check.dmg'|'aing-check.zip'; url: string; bytes: number; mb: string };
export type ReleaseInfo = { version: string; publishedAt: string|null; dmg: ReleaseAsset|null; zip: ReleaseAsset|null; source: 'github'|'fallback' };
export const RELEASE_FALLBACK: ReleaseInfo;     // SPEC §6 아래 값(0.3.47 · 30.0 · 28.2)
export function formatMB(bytes: number): string; // (bytes / 1e6).toFixed(1)
export async function getRelease(): Promise<ReleaseInfo>;  // SPEC §8.5
export function downloadTarget(r: ReleaseInfo, file: 'dmg'|'zip'): string;
```
- `app/api/download/route.ts`: `export async function GET(req)` → `file = searchParams.get('file') === 'zip' ? 'zip' : 'dmg'` → `NextResponse.redirect(downloadTarget(await getRelease(), file), { status: 302, headers: { 'Cache-Control': 'no-store' } })`. 런타임 Node.
- `app/api/release/route.ts`: `export const revalidate = 3600;` JSON + `Cache-Control: public, s-maxage=3600, stale-while-revalidate=86400`.

### 3.8 생성 데이터 형식
- `assets.json`: `{ "<키>": { "src": "/assets/<경로>?v=<sha1 8자>", "w": <px>, "h": <px>, "bytes": <n> } }`. 키 = 출력 경로에서 확장자를 뺀 것(`ui/popover-off`, `ios/now`, `brand/qr-appstore` …). 영상은 sequences.json 에만.
- `bubbles.json`: `{ "anchorCanvas": [323, 981], "canvasPerPx3x": 3.5, "bubbles": { "<id>": { "asset": "ui/bubble-<id>", "px3x": [w, h], "pt": [w/3, h/3], "canvasPx": [w×3.5, h×3.5] } } }`. CharacterStage 는 출력 px = canvasPx × 0.5 로 쓴다.
- `grass.json`: `{ "scale": 3, "work": { "png": {w,h}, "grid": {...}, "cells": [{ "col", "row", "future", "level", "weekday": "월", "valueText", "x", "y", "w", "h" }] }, "token": { … } }` — 원본 `grass_light.json` 의 `cells` 에서 date 는 버리고 요일만 남긴다(칸 좌표는 @3x px, 원본의 grid 와 셀 bbox 그대로).

### 3.9 글꼴(`app/layout.tsx`)
```ts
const pretendard = localFont({ src: '../public/fonts/pretendard-800-sub.woff2', weight: '800', display: 'swap', preload: true, variable: '--font-pretendard', fallback: ['-apple-system', 'BlinkMacSystemFont', 'Apple SD Gothic Neo', 'system-ui'] });
const jbm = localFont({ src: '../public/fonts/jbm-400-ascii.woff2', weight: '400', display: 'swap', preload: false, variable: '--font-jbm' });
```

### 3.10 `app/page.tsx`(고정)
```tsx
import MenubarStage from '@/components/sections/MenubarStage';
import HeroAuto from '@/components/sections/HeroAuto';
import TeamPoke from '@/components/sections/TeamPoke';
import MessageGames from '@/components/sections/MessageGames';
import CharacterRecords from '@/components/sections/CharacterRecords';
import IphoneTrust from '@/components/sections/IphoneTrust';
import InstallFaq from '@/components/sections/InstallFaq';
import ClosingFooter, { SiteFooter } from '@/components/sections/ClosingFooter';
import AingCorner from '@/components/sections/AingCorner';
import { LiveAnnouncer } from '@/components/ui/LiveAnnouncer';
export const revalidate = 3600;
export default function Page() {
  return (<>
    <MenubarStage />
    <main id="main">
      <HeroAuto /><TeamPoke /><MessageGames /><CharacterRecords /><IphoneTrust /><InstallFaq /><ClosingFooter />
    </main>
    <SiteFooter />
    <AingCorner />
    <LiveAnnouncer />
  </>);
}
```
섹션 파일은 서버 컴포넌트(async 가능 — 릴리스가 필요하면 `await getRelease()`)로 두고, 상호작용은 하위 `'use client'` 파일에 둔다. 스텁 9개는 같은 서명으로 `SectionShell` 과 `VisuallyHidden` 제목만 그린다(앵커 13개와 푸터가 처음부터 존재).

---

## 4. 섹션 계약(9개)

공통: default export 이름 = 파일 이름, props 없음. 카피는 SPEC §4 그대로(한 글자도 바꾸지 않는다 — 바꿔야 하면 requests). 섹션 안 HTML 에 금지어(SPEC §1.4) 0. 감속 모션·키보드·390/768/1440 은 모든 섹션의 기본 수용 기준이다.

### 4.1 `stage-menubar` — `components/sections/MenubarStage.tsx`
- **앵커**: 없음(전역 층). `<header>` 를 렌더하고 스파인 `#spine` 을 담는다.
- **쓰는 공용**: `DownloadCTA`(nav) · `RenderStack` · `MacWindowShell` · `TickStrip` · `VisuallyHidden` · `useDemo` · `demo.toggleSpine/toggleLabelPopover/setSpineRect` · selectors(`labelKey`·`panelFor`·`spineOpen`·`labelPanel`) · `useViewportMode` · `useReducedMotion` · `preloadImage`.
- **픽스처·에셋**: `LABELS`, `PANELS`, `ALT`, `brand/icon-64`, `ui/menubar-*`(6), 모든 `ui/popover-*`·패널 판.
- **하위 파일(제안)**: `menubar-stage/NavBar.tsx` · `StatusItem.tsx` · `Spine.tsx` · `LabelPopover.tsx` · `useHeroCtaVisible.ts`.
- **상호작용**: 라벨 교체(0ms) + 첫 시작 민트 번짐 · 라벨 클릭(desk: 스파인 섹션 → toggleSpine, 그 밖 → 라벨 정지 팝오버) · 내비 CTA 테두리 → 채움(히어로 `[data-hero-cta]` IO) · 활성 링크 `aria-current` · 스파인 열림/닫힘/패널 교차/높이 맞춤/로드 내려옴(CSS 키프레임) · 사각형 게시 · 다음 판 미리 받기.
- **수용 기준**
  1. 1440×900 첫 페인트(JS 끄기)에서 띠 48px 와 오른쪽 끝 라벨 "오프", 그 밑에 popover-off 가 오른쪽 16px·띠 아래 6px 에 붙어 보인다(SSR, `desk:` CSS).
  2. 스토어에서 work=on 이면 라벨 이미지가 즉시 `menubar-0000` 으로 바뀌고 첫 1회만 번짐이 보인다.
  3. activeSection 이 auto·games·iphone 이후면 스파인이 140ms 로 접히고, team 이면 popover-working 으로 펼쳐진다. 패널 교체 때 빈 프레임이 없다.
  4. 라벨 클릭으로 접고 펴기, `aria-expanded` 반영. 스파인 없는 섹션에서 라벨 클릭 → 정지 팝오버, Esc 로 닫힘.
  5. 히어로 CTA 가 화면 밖이면 내비 CTA 가 채움, 돌아오면 테두리.
  6. 조상에 transform/filter/contain 없음(스파인 DOM 의 `getComputedStyle` 체인 검사 코드를 개발 모드 경고로 둔다).
  7. phone·tab 에서 라벨은 `aria-hidden` 이미지, 스파인 없음.
- **복잡도**: 높음(2.5–3h).

### 4.2 `stage-corner` — `components/sections/AingCorner.tsx`
- **앵커**: 없음(전역 층). 코너 아잉 + 울트라 오버레이 + 할 일 보드.
- **쓰는 공용**: `CharacterStage` · `SpritePlayer`(울트라) · `Bubble` · `Hotspot`(todoClose) · `RenderImage` · `useDemo` · `demo.reactionDone/bubbleDone/toggleTodo/hideCorner/msgOpen/ultraReady/ultraDone` · `capsuleText` · `useViewportMode` · `usePosterOnly` · `wantsLowFps` · motion(`LazyMotion`, `AnimatePresence`, `next/dynamic` 로 보드·울트라만).
- **픽스처·에셋**: `CORNER`, `REACTION_SEQ`, `BUBBLE_TEXT`, `HOTSPOTS.todoClose`, `TIMING`, `ALT['todo-board']`, `ui/todo-board`, 모든 `char/aing-*`, `ui/bubble-*`.
- **하위 파일(제안)**: `aing-corner/Corner.tsx` · `useCornerPlacement.ts`(스파인 회피 + `[data-companion-avoid]` 회피) · `HideButton.tsx` · `UltraOverlay.tsx` · `TodoBoard.tsx`.
- **상호작용**: SPEC 공통 C·U·T 전부. 등장(commute/fade)·퇴장(commute_end 후 언마운트) · 몸통 클릭 → 보드 · 말풍선(메시지) 클릭 → msgOpen · 숨기기 · 숨김 중 poked 반응만 잠깐 보임 · 자리 이동/회피 240ms · 울트라(72프레임, 아무 입력으로 닫힘, 감속 모션 포스터 3초) · 보드(desk 앵커 / phone 시트, Esc·바깥·×·재클릭).
- **수용 기준**
  1. work=off → 코너 DOM 없음. pressStart → 124.6×150.5 상자가 오른쪽 20·아래 16 에 나타나고 commute_start 영상(크롬 `.webm`, 사파리 `.mov`) 재생 + 말풍선이 상자 기준 (−9.6, 41.6) 에 5초.
  2. 반응이 끝나면 idle 이 이어지고 빈 프레임·이중 캐릭터가 없다(반응 시작 때 idle 을 `(N mod 432)/30` 으로 미리 시크).
  3. 1280×720 에서 스파인이 열려 있으면 코너가 스파인 왼쪽에 있다(겹침 0).
  4. 설치 절 버튼 줄(`data-companion-avoid`)과 겹치면 위로 비켜 선다.
  5. 몸통 타원 밖(상자 모서리) 클릭은 뒤 요소에 통과한다.
  6. 울트라: 정사각 = 0.98 × min(vw, vh) 정중앙, 2.4초 뒤 160ms 퇴장, Esc·클릭·휠·키로 즉시 닫힘. 감속 모션에서 `.webm/.mov` 요청 0건.
  7. 할 일 보드: 열면 포커스가 × 로, Esc 로 닫으면 연 컨트롤로 복귀. phone 에서는 아래 시트.
  8. 숨기기 → 꾸벅 후 사라짐, 새로고침해도 숨김 유지, pokeIn 때 잠깐 나타났다 다시 숨음.
- **복잡도**: 높음(2.5–3h).

### 4.3 `hero` — `components/sections/HeroAuto.tsx`
- **앵커**: `#top`(S1, kind 'spine'), `#auto`(S2, kind 'plain').
- **쓰는 공용**: `SectionShell` · `Headline` · `DownloadCTA`(hero) · `AppStoreBadge` · `TextLink` · `PanelSlot`(hero: panels popover-off·popover-on, hotspot `startButton` pulse) · `AingStageInline`(S1 inline, S2 inline-lg) · `useEnterTimer`(autostart 700) · `useInViewRatio(.5)` · `useCenterLine`(표지 두 개, dwell 400) · `demo.pressStart/autoStart/setAutoPassed`.
- **픽스처·에셋**: `ALT`, `TIMING`, `LINKS`, `ui/popover-off`·`popover-on`·`popover-tick-strip`, 반응 영상 미리 받기(`preloadSequence('aing-commute-start')`, S2 근접 시 milestone·ultra-charged).
- **상호작용**: SPEC S1·S2 표 전부. 히어로 메타 줄 3상태(기본·installHint·iOS). Mac 링크 보내기. 표지 통과 → 라벨 01:00/03:45 + 반응.
- **수용 기준**
  1. 1440×900: H1 두 줄이 SSR 로 보이고(opacity 애니메이션 없음) CTA 줄에 `data-hero-cta`·`data-companion-avoid`, 다음 절 머리가 화면 아래 64px 에 걸친다.
  2. 390×844: H1·리드·CTA 가 접힘선 위, 인라인 팝오버 헤더의 [근무 시작]이 접힘선 위.
  3. [근무 시작] 핫스팟을 Tab 으로 도달해 Enter → 스토어 work=on, 팝오버 판 popover-on(0ms), 틱이 1초마다 바뀌고 11에서 멈춘다.
  4. 1.2초 뒤 맥동 1회(감속 모션이면 없음).
  5. 누르지 않고 S2 로 스크롤하면 700ms 뒤 autostart(말풍선 문구 그대로). 표지1 → 라벨 0100 + milestone, 표지2 → 라벨 0345 + ultra_charged + "루비 +3!". 거꾸로 올리면 라벨만 되돌아가고 반응은 다시 나오지 않는다.
  6. 다운로드 클릭 → 메타 줄이 "받은 파일을 열고, 아이콘을 Applications 폴더로 끌어다 놓으세요."(새로고침 유지). iOS UA 에서는 배지가 먼저, "Mac 링크 보내기".
- **복잡도**: 중상(2.5h).

### 4.4 `team-poke` — `components/sections/TeamPoke.tsx`
- **앵커**: `#team`(S3, spine), `#poke`(S4, spine).
- **쓰는 공용**: `SectionShell` · `Headline` · `TimeMark('14:05')` · `Segmented` · `PanelSlot`(team: popover-working·league / `railTeam` 포커스 불가) · `PanelSlot`(poke: poke-list·poke-cooldown·poke-focus-1·poke-focus-2 / `pokeMint` · `focusChip`) · `AingStageInline`(poke, 렌더 오른쪽 아래) · `useEnterTimer`(pokeIn 1200) · `demo.setTeam/pokeIn/pokeBack/cycleFocus`.
- **에셋**: `ui/popover-working` · `ui/league` · `ui/poke-*`(4) · 울트라 영상은 이 절 근접 시 `preloadSequence('aing-ultra')`(실제 재생은 stage-corner).
- **수용 기준**
  1. #team 진입 시 라벨 0345, 스파인 popover-working. 세그먼트(화살표 키 가능)·레일 핫스팟으로 league ↔ members, 두 판이 동시에 보이지 않는다.
  2. 14:05 표식이 desk 에서 거터(x≈24)에, phone 에서 H2 위.
  3. #poke 진입 1.2초 뒤 poked 반응 + "민트별님이 콕 찔렀어요!"(focus 0 일 때만).
  4. 민트별 찌르기 → poke-cooldown 0ms, 1초 뒤 울트라 시작(스토어 ultra≠idle). 다른 행은 반응 없음.
  5. [집중] 칩 → focus-1 → focus-2 → 원래 판, 창 높이 654↔679 전이, 1·2단에서 찌르기 핫스팟 `aria-disabled`, 알림 문구.
  6. "콕." 은 `t-h2-solo`(1440 에서 112px).
- **복잡도**: 중(2h).

### 4.5 `message-games` — `components/sections/MessageGames.tsx`
- **앵커**: `#message`(S5, spine), `#games`(S6, plain).
- **쓰는 공용**: `SectionShell` · `Headline` · `Button`(secondary) · `PanelSlot`(message: popover-working·popover-newmsg·message-composing·message-unread·message-read / `railPokeMsg`·`sendButton` 포커스 가능) · `AingStageInline`(message) · `useEnterTimer`(msgArrive 800) · `Segmented` · `MacWindowShell` · `RenderImage` · `gamesValue` · `demo.msgArrive/msgOpen/msgSend/setGames`.
- **에셋**: `ui/popover-newmsg` · `ui/message-*`(3) · `ui/minigame` · `ui/gomoku-board` · `ui/gomoku-board-sm`.
- **수용 기준**
  1. #message 진입 0.8초 뒤 라벨 0345-newmsg, 스파인 popover-newmsg, 말풍선.
  2. 왼쪽 버튼이 상태에 따라 "구름빵 대화 열기" → "보내기" → 숨김(자리 유지). 레일·말풍선·버튼 어느 쪽이든 열린다.
  3. 보내기 → unread → 1.6초 뒤 read, 알림 세 문장.
  4. #games 에서 스파인이 접히고 게임 창(desk 700×389 1:1, `--shadow-window`, 아래 24px 페이드)과 세그먼트. 오목 선택 시 504×560 으로 높이 전이. phone 첫 값 오목.
  5. 오목 크롭에 '판돈' 글자가 없다.
- **복잡도**: 중(2h).

### 4.6 `character-records` — `components/sections/CharacterRecords.tsx`
- **앵커**: `#character`(S7, spine), `#records`(S8, spine, 박자 `records:tokens`).
- **쓰는 공용**: `SectionShell` · `Beat` · `Headline` · `Button` · `PanelSlot`(character: character-pick) · `PanelSlot`(records: insights·token-month·token-last / `tokenPrev`·`tokenNext` 포커스 가능) · `AingStageInline`(character) · `Segmented`(grass) · `MacWindowShell` · `useNearViewport` · `useReducedMotion` · `demo.toggleTodo/setGrass/setTokens`.
- **에셋**: `ui/character-pick` · `ui/insights-popover` · `ui/grass-*`(4) · `data/generated/grass.json` · `ui/token-month` · `ui/token-last`.
- **하위 파일(제안)**: `character-records/GrassLight.tsx`(scrub 점등 + 툴팁).
- **수용 기준**
  1. "오늘 할 일 열기" → 스토어 todoOpen=true(보드는 stage-corner 가 그린다), 숨김 상태면 아잉이 먼저 돌아온다. 버튼 `aria-expanded` 연동.
  2. 확대 잔디 456×258(desk): 스크롤 85%→35% 구간에서 켜진 열이 0→13 으로 늘고, 올리면 줄어든다. future 칸은 끝까지 꺼짐. 칸 색은 final 렌더 픽셀(새 색 0).
  3. 호버 툴팁 "월요일, 7시간 20분" 형식(날짜 없음), 터치에서 없음.
  4. 세그먼트 AI 토큰 → token 판, 진행도 유지.
  5. 박자 `records:tokens` 가 중앙에 오면 스파인 token-month, ◀ → token-last, ▷ → token-month(Tab 으로 도달 가능).
  6. 감속 모션: 칸 div 없이 final 한 장.
  7. character-pick 이외에 캐릭터 여러 종을 늘어놓지 않는다. 로봇·'일곱' 없음.
- **복잡도**: 중상(2.5h).

### 4.7 `iphone-trust` — `components/sections/IphoneTrust.tsx`
- **앵커**: `#iphone`(S9, plain), `#trust`(S10, plain).
- **쓰는 공용**: `SectionShell` · `Headline` · `PhoneShell` · `RenderImage` · `Hotspot`(phoneTabs 5개 role tab, widgetRow role checkbox) · `AppStoreBadge` · `QrCode` · `TextLink` · `demo.setPhone/toggleWidget`.
- **에셋**: `ios/now` · `ios/messages` · `ios/rankings-league` · `ios/games` · `ios/me-records` · `ios/widget-todos-large` · `ios/widget-todos-large-checked` · `ios/widget-today-small` · `brand/qr-appstore`.
- **수용 기준**
  1. 폰 셸(정면, 아일랜드 CSS 덮개)이 desk 화면 폭 300, phone 260. 탭 5개 핫스팟이 렌더 탭바 위에 정확히(±2pt), 화살표 키 이동, 화면 120ms 교차, '나' = me-records.
  2. 위젯 L 체크 → checked 판, `aria-checked` 반영, 다시 누르면 되돌림. `working-medium` 위젯 없음.
  3. QR 은 desk 만, 흰 타일, App Store 주소(지역 코드 없음).
  4. #trust: 이미지 0장, 큰 문장 두 줄, 신뢰 줄 5개가 `<ul role="list">`, 링크 둘.
- **복잡도**: 중(2h).

### 4.8 `install-faq` — `components/sections/InstallFaq.tsx`
- **앵커**: `#install`(S11, band), `#faq`(S12, plain) + 문항 `#faq-1` … `#faq-10`.
- **쓰는 공용**: `SectionShell` · `Headline` · `DownloadCTA`(install, 라벨·file 은 릴리스로 결정) · `CommandBox` · `CopyButton` · `AppStoreBadge` · `QrCode` · `TextLink` · `RenderImage` · `Bubble`(update, static) · `VisuallyHidden` · `getRelease`(서버) · `useDemo(s => s.installHint)`.
- **에셋**: `ui/menubar-off` · `ui/menubar-icon-dot` · `ui/bubble-update` · 배지 · QR.
- **하위 파일(제안)**: `install-faq/InstallBlock.tsx`('use client', 안내 상태 전환) · `install-faq/faq-items.ts`(문항 10개 — JSON-LD 와 화면이 같은 출처) · `install-faq/FaqHash.tsx`(해시로 열기).
- **수용 기준**
  1. 릴리스에 DMG 가 있으면 버튼 "aing-check.dmg 다운로드" + 메타 "0.3.47 버전, 30.0MB. …"(API 값), DMG 가 없도록 목(mock)하면 zip 버튼과 `?file=zip`.
  2. 클릭 → 블록이 세 단계 안내로 바뀌고 3단계에 라벨 렌더, "다시 받기" 링크. 새로고침 유지.
  3. 복사 → "복사했어요" 2초, 알림. 클립보드 거부 시 명령 선택 + "⌘C로 복사하세요".
  4. 팀 참여 `<ol>` 3단계, desk 3열.
  5. FAQ 10문항, 첫 문항 열림, 하나 열면 다른 것 닫힘(`name="faq"`), `/#faq-3` 으로 들어오면 3번이 열린 채 스크롤. `FAQPage` JSON-LD 의 질문·답이 화면 문장과 같다. 센터 문항 없음.
  6. 디스클로저 삼각형 회전(감속 모션 즉시), `+` 아이콘 없음.
- **복잡도**: 중(2h).

### 4.9 `closing-footer` — `components/sections/ClosingFooter.tsx`(+ `export function SiteFooter()`) · `app/licenses/page.tsx`
- **앵커**: `#closing`(S13, plain), `<footer>`(S14).
- **쓰는 공용**: `SectionShell` · `Headline(size 'closing')` · `TimeMark('17:02')` · `Button`(secondary) · `RenderImage` · `Hotspot`(restartButton) · `MacWindowShell` · `DownloadCTA`(closing) · `AppStoreBadge` · `CopyButton`(secondary) · `AingStageInline`(closing) · `demo.pressEnd/restart` · `labelKey`.
- **에셋**: `ui/menubar-0642-lg` · `ui/menubar-off-lg` · `ui/header-off-1702` · `brand/icon-64` · `public/fonts/LICENSE-*.txt`(licenses 페이지가 빌드 때 읽음).
- **수용 기준**
  1. #closing 진입 시 띠 라벨과 확대 라벨(66px 높이)이 06:42.
  2. 근무 종료 → 라벨 둘 다 오프, 스토어 work=ended, 헤더 카드가 나타나고 포커스가 그 [근무 시작] 핫스팟으로.
  3. [근무 시작] 핫스팟 → 라벨 06:42(00:00 아님), work=on, 카드 접힘, 근무 종료 버튼 복귀.
  4. CTA 줄 `data-companion-avoid`, brew 명령 복사 동작.
  5. 푸터 링크 6개(지원·처리방침·약관·GitHub·버그·요청·글꼴 라이선스), 가운뎃점 없음, © 2026 아잉체크.
  6. `/licenses` 가 OFL 전문 두 개를 보여 준다.
- **복잡도**: 중하(1.5h).

---

## 5. 에셋 내보내기 레시피(최종) — `scripts/build-assets.mjs`

### 5.1 실행
- 입력 루트 `SRC=/Users/yesung/aing-check-promo/public/assets/`(읽기만) · 앱 아이콘 `/Users/yesung/check/packaging/appicon/icon-1024.png` · 글꼴 `/Users/yesung/aing-check-promo/public/fonts/`.
- 출력 루트 `OUT=/Users/yesung/check/landing/public/assets`, 아이콘은 `landing/app/`, 데이터는 `landing/data/generated/`.
- 도구: Node 22 + `sharp`(devDependency). ffmpeg = `/Users/yesung/aing-check-promo/node_modules/@remotion/compositor-darwin-arm64/ffmpeg`(이 맥에 brew ffmpeg 가 없다 — `DYLD_LIBRARY_PATH` 를 같은 폴더로). 이 판은 libvpx-vp9 · hevc_videotoolbox · crop · scale · trim 만 있고 pad·select·fps 가 없다 → 크롭·짝수 맞춤·프레임 솎기는 sharp 와 JS(짝수 프레임만 임시 폴더에 복사)로 한다.
- 명령: `cd /Users/yesung/check/landing && FFMPEG=/Users/yesung/aing-check-promo/node_modules/@remotion/compositor-darwin-arm64/ffmpeg node scripts/build-assets.mjs [--only=ui,char,ios,brand,data] [--seq=aing-idle,…]`
- 임시 프레임 폴더는 `os.tmpdir()/aing-<name>-*` 에 만들고 끝나면 지운다. 저장소에 임시 파일을 남기지 않는다.
- 끝에 표 출력(파일·KB·합계) + `assets.json`·`sequences.json`·`bubbles.json`·`grass.json` 기록. 각 파일 `?v=` 는 출력 바이트 sha1 앞 8자.
- 검증(스크립트 끝): ① 모든 출력 파일 크기 > 0, ② 영상마다 입력 프레임 수 = 메타 frames, ③ 렌더 webp 의 픽셀 크기 = 표의 값(sharp metadata), ④ 합계가 4.5MB 를 넘으면 경고. 알파가 살아 있는지는 통합 단계에서 브라우저로 본다(축소판 ffmpeg 은 알파 디코드 검증이 안 된다).

### 5.2 공통 규칙
| 종류 | 크기 | 포맷 · 품질 |
|---|---|---|
| 맥 렌더(@3x) | @2x = 원본 폭 × 2/3 (pt × 2) | webp q80, effort 6, smartSubsample |
| 맥 렌더(@4x 헤더) | @2x = 원본 폭 / 2 | webp q85 |
| 잔디(@3x) | 원본 크기 그대로(1.5배 표시라 @3x 가 필요) | webp q88 |
| 라벨(@10x 투명) | 높이 66(nav) / 132(`-lg`) | webp q90, alphaQuality 100 |
| 말풍선(@8x 투명) | 알파>8 bbox 로 자른 뒤 × 3/8(= @3x px) | webp q90, alphaQuality 100 |
| 아이폰(@3x) | 폭 600 | webp q80 |
| 위젯(@3x 투명) | pt × 2(S 340 · L 728) | webp q85, alphaQuality 100 |
| 캐릭터 시퀀스 | 박스 크롭 → × 0.5(박스 w·h 는 4의 배수 → 결과 짝수) | VP9: `-c:v libvpx-vp9 -pix_fmt yuva420p -b:v 0 -crf <n> -row-mt 1 -deadline good -cpu-used 2 -auto-alt-ref 0 -g <gop> -an` / HEVC: `-c:v hevc_videotoolbox -alpha_quality 0.6 -q:v <q> -tag:v hvc1 -pix_fmt bgra -g <gop> -movflags +faststart -an` |
| 포스터 | 같은 박스·크기 1프레임 | webp q82, alphaQuality 90 |

### 5.3 출력 전체 목록(입력 절대 경로 → 출력 → 크기·포맷·품질·프레임 → 예상 KB)
`S/` = `/Users/yesung/aing-check-promo/public/assets/`, `O/` = `/Users/yesung/check/landing/public/assets/`

| # | 입력 | 출력 | 크기 · 포맷 · 품질 · 프레임 | 예상 KB |
|---|---|---|---|---|
| 1 | `S/v4/mac/ui/popover_main_off_1020@3x.png` | `O/ui/popover-off.webp` | 828×1306 · q80 | 39 |
| 2 | `S/v4/mac/ui/tick/popover_tick_on_00@3x.png` | `O/ui/popover-on.webp` | 828×1306 · q80 | 40 |
| 3 | `S/v4/mac/ui/tick/popover_tick_on_{00…11}@3x.png` | `O/ui/popover-tick-strip.webp` | 각 장 영역 (288,144) 270×1515 → 180×1010, 12칸 가로 2160×1010 · q82 · 12프레임 | 89 |
| 4 | `S/v4/mac/ui/popover_main_working_1405@3x.png` | `O/ui/popover-working.webp` | 828×1306 · q80 | 41 |
| 5 | `S/v4/mac/ui/popover_main_working_1405_newmsg@3x.png` | `O/ui/popover-newmsg.webp` | 828×1306 · q80 | 41 |
| 6 | `S/v4/mac/ui/popover_main_off_1702@3x.png` | `O/ui/popover-off-1702.webp` | 828×1306 · q80 | 40 |
| 7 | `S/v4/mac/ui/league_week@3x.png` | `O/ui/league.webp` | 828×1200 · q80 | 49 |
| 8 | `S/v4/mac/ui/poke_list@3x.png` | `O/ui/poke-list.webp` | 828×1308 · q80 | 43 |
| 9 | `S/v4/mac/ui/poke_cooldown_mint@3x.png` | `O/ui/poke-cooldown.webp` | 828×1308 · q80 | 43 |
| 10 | `S/v4/mac/ui/poke_focus_stage1@3x.png` | `O/ui/poke-focus-1.webp` | 828×1358 · q80 | 46 |
| 11 | `S/v4/mac/ui/poke_focus_stage2@3x.png` | `O/ui/poke-focus-2.webp` | 828×1358 · q80 | 46 |
| 12 | `S/v4/mac/ui/message_thread_gureum_composing@3x.png` | `O/ui/message-composing.webp` | 828×1144 · q80 | 35 |
| 13 | `S/v4/mac/ui/message_thread_gureum_unread@3x.png` | `O/ui/message-unread.webp` | 828×1206 · q80 | 36 |
| 14 | `S/v4/mac/ui/message_thread_gureum_read@3x.png` | `O/ui/message-read.webp` | 828×1206 · q80 | 36 |
| 15 | `S/v4/mac/ui/minigame_window_flappy_playing_8rows@3x.png` | `O/ui/minigame.webp` | 1400×779 · q80 | 35 |
| 16 | `S/v4/mac/ui/gomoku_playing@3x.png` 크롭 (0,0,1890,2100) | `O/ui/gomoku-board.webp` | 1260×1400 · q78 | 45 |
| 17 | 같은 크롭 | `O/ui/gomoku-board-sm.webp` | 700×778 · q78 | 18 |
| 18 | `S/v4/mac/ui/character_pick_aing@3x.png` | `O/ui/character-pick.webp` | 828×990 · q80 | 35 |
| 19 | `S/v4/mac/ui/todo_board_today_opaque@3x.png` | `O/ui/todo-board.webp` | 600×800 · q80 alpha 90 | 22 |
| 20 | `S/v4/mac/ui/insights_popover@3x.png` | `O/ui/insights-popover.webp` | 828×1390 · q80 | 48 |
| 21 | `S/v4/mac/ui/insights/work_grass_empty@3x.png` | `O/ui/grass-work-empty.webp` | 912×515 · q88 | 25 |
| 22 | `S/v4/mac/ui/insights/work_grass_final@3x.png` | `O/ui/grass-work-final.webp` | 912×515 · q88 | 45 |
| 23 | `S/v4/mac/ui/insights/token_grass_empty@3x.png` | `O/ui/grass-token-empty.webp` | 912×519 · q88 | 25 |
| 24 | `S/v4/mac/ui/insights/token_grass_final@3x.png` | `O/ui/grass-token-final.webp` | 912×519 · q88 | 45 |
| 25 | `S/v4/mac/ui/token_board_month@3x.png` | `O/ui/token-month.webp` | 828×1364 · q80 | 45 |
| 26 | `S/v4/mac/ui/token_board_last_month@3x.png` | `O/ui/token-last.webp` | 828×1364 · q80 | 45 |
| 27 | `S/v4/mac/ui/header/header_off_1702@4x.png` | `O/ui/header-off-1702.webp` | 632×214 · q85 | 18 |
| 28 | `S/v4/mac/ui/menubar/menubar_aing_off_dark_alpha@10x.png` | `O/ui/menubar-off.webp` · `O/ui/menubar-off-lg.webp` | 높이 66 / 132 · q90 a100 | 3 · 6 |
| 29 | `S/v4/mac/ui/menubar/menubar_aing_working_0000_dark_alpha@10x.png` | `O/ui/menubar-0000.webp` | 높이 66 · q90 a100 | 4 |
| 30 | `S/v4/mac/ui/menubar/menubar_aing_working_0100_dark_alpha@10x.png` | `O/ui/menubar-0100.webp` | 높이 66 | 4 |
| 31 | `S/v4/mac/ui/menubar/menubar_aing_working_0345_dark_alpha@10x.png` | `O/ui/menubar-0345.webp` | 높이 66 | 4 |
| 32 | `S/v4/mac/ui/menubar/menubar_aing_working_0345_newmsg_dark_alpha@10x.png` | `O/ui/menubar-0345-newmsg.webp` | 높이 66 | 4 |
| 33 | `S/v4/mac/ui/menubar/menubar_aing_working_0642_dark_alpha@10x.png` | `O/ui/menubar-0642.webp` · `O/ui/menubar-0642-lg.webp` | 높이 66 / 132 | 4 · 8 |
| 34 | `S/v4/mac/ui/menubar/menubar_aing_icon_working_dot@10x.png` | `O/ui/menubar-icon-dot.webp` | 66×66 · q90 a100 | 3 |
| 35 | `S/v4/mac/ui/bubble/bubble_commute_start@8x.png` | `O/ui/bubble-commute-start.webp` | bbox 크롭 → @3x · q90 a100 | 6 |
| 36 | `S/v4/mac/ui/bubble/bubble_autostart@8x.png` | `O/ui/bubble-autostart.webp` | 같음 | 10 |
| 37 | `S/v4/mac/ui/bubble/bubble_poked_mint@8x.png` | `O/ui/bubble-poked-mint.webp` | 같음 | 8 |
| 38 | `S/v4/mac/ui/bubble/bubble_message_gureum@8x.png` | `O/ui/bubble-message-gureum.webp` | 같음 | 9 |
| 39 | `S/v4/mac/ui/bubble/bubble_commute_end@8x.png` | `O/ui/bubble-commute-end.webp` | 같음 | 5 |
| 40 | `S/v4/mac/ui/bubble/bubble_ultra_mint@8x.png` | `O/ui/bubble-ultra-mint.webp` | 같음(717×193 근처) | 15 |
| 41 | `S/v4/mac/ui/bubble/bubble_update@8x.png` | `O/ui/bubble-update.webp` | 같음 | 7 |
| 42 | `S/v4/char/aing/_ui/bubble_00.png` 크롭 (323,981)–(948,1290) | `O/ui/bubble-ruby.webp` | 캔버스 px ÷ 3.5 = @3x(≈179×89) · q90 a100 | 5 |
| 43 | `S/v4/char/aing/idle_long/0000–0431.png` | `O/char/aing-idle.webm` · `.mov` | 박스 [424,544,1308,1580] → 654×790 · 432f 30fps · VP9 crf46 g30 / HEVC q30 g30 | 760 · 790 |
| 44 | 같은 시퀀스의 짝수 프레임 216장 | `O/char/aing-idle-15.webm` · `.mov` | 654×790 · 15fps · VP9 crf44 g15 / HEVC q40 g15 | 390 · 530 |
| 45 | `S/v4/char/aing/idle_long/0000.png` | `O/char/aing-idle-poster.webp` | 같은 박스 654×790 · q82 a90 | 18 |
| 46 | `S/v3/mac/char/aing/commute_start/0000–0044.png` | `O/char/aing-commute-start.webm` · `.mov` | HERO 박스 654×790 · 45f · crf42 g30 / q35 | 148 · 143 |
| 47 | `S/v3/mac/char/aing/commute_end/0000–0035.png` | `O/char/aing-commute-end.webm` · `.mov` | HERO 박스 · 36f · crf42 / q35 | 110 · 105 |
| 48 | `S/v3/mac/char/aing/poked/0000–0089.png` | `O/char/aing-poked.webm` · `.mov` | HERO 박스 · 90f · crf42 / q35 | 296 · 275 |
| 49 | `S/v3/mac/char/aing/milestone/0000–0071.png` | `O/char/aing-milestone.webm` · `.mov` | 박스 [308,544,1544,1580] → 772×790 · 72f · crf42 / q35 | 240 · 250 |
| 50 | `S/v4/char/aing/ultra_charged/0000–0101.png` | `O/char/aing-ultra-charged.webm` · `.mov` | 박스 [452,1032,1228,1160] → 614×580 · 102f · crf44 / q35 | 295 · 317 |
| 51 | `S/v4/char/aing/ultra_poked/0000–0071.png`(72장만) | `O/char/aing-ultra.webm` · `.mov` | 울트라 캔버스 박스 [260,48,1680,1476] → 840×738 · 72f · crf46 / q30 | 340 · 345 |
| 52 | `S/v4/char/aing/ultra_poked/0040.png` | `O/char/aing-ultra-poster.webp` | 840×738 · q82 a90 | 21 |
| 53 | `S/v4/ios/screens/now_dark@3x.png` | `O/ios/now.webp` | 600×1304 · q80 | 29 |
| 54 | `S/v4/ios/screens/messages_dark@3x.png` | `O/ios/messages.webp` | 600×1304 · q80 | 36 |
| 55 | `S/v4/ios/screens/rankings-league_dark@3x.png` | `O/ios/rankings-league.webp` | 600×1304 · q80 | 34 |
| 56 | `S/v4/ios/screens/games_dark@3x.png` | `O/ios/games.webp` | 600×1304 · q80 | 28 |
| 57 | `S/v4/ios/screens/me_records_dark@3x.png` | `O/ios/me-records.webp` | 600×1304 · q80 | 40 |
| 58 | `S/v4/ios/widgets/promo_todos-large_dark@3x.png` | `O/ios/widget-todos-large.webp` | 728×764 · q85 a100 | 20 |
| 59 | `S/v4/ios/widgets/promo_todos-large-checked_dark@3x.png` | `O/ios/widget-todos-large-checked.webp` | 728×764 · q85 a100 | 20 |
| 60 | `S/v4/ios/widgets/promo_today-small_dark@3x.png` | `O/ios/widget-today-small.webp` | 340×340 · q85 a100 | 9 |
| 61 | `S/v3/brand/appstore-badge-ko-black.svg` | `O/brand/appstore-badge-ko-black.svg` | 바이트 그대로 복사 | 9 |
| 62 | (생성) `https://apps.apple.com/app/id6812768622` | `O/brand/qr-appstore.svg` | `scripts/make-qr.py`(python `qrcode`, `SvgPathImage`, 오류 정정 M, 여백 4모듈, 모듈 #12131C · 바탕 #F2F3F7 타일) | 3 |
| 63 | `/Users/yesung/check/packaging/appicon/icon-1024.png` | `O/brand/icon-64.webp` · `O/brand/icon-256.webp` | 64 · 256 · q90 a100 | 2 · 7 |
| 64 | 같은 아이콘 | `landing/app/icon.png` · `landing/app/apple-icon.png` | 128 팔레트 png(수리 단계) · 180 png(#12131C 평탄화) | 6 · 28 |
| 65 | `/Users/yesung/aing-check-promo/public/fonts/Pretendard-ExtraBold.woff2` | `landing/public/fonts/pretendard-800-sub.woff2` + `pretendard-800-sub.txt` | `scripts/subset-fonts.mjs` → `pyftsubset --text-file=<모은 글자> --flavor=woff2 --layout-features='kern,liga' --no-hinting` | 60 |
| 66 | `/Users/yesung/aing-check-promo/public/fonts/JetBrainsMono-Regular.woff2` | `landing/public/fonts/jbm-400-ascii.woff2` | `--unicodes=U+0020-007E` | 15 |
| 67 | `/Users/yesung/aing-check-promo/public/fonts/LICENSE-Pretendard.txt` · `LICENSE-JetBrainsMono.txt` | `landing/public/fonts/` 같은 이름 | 복사 | 5 |
| 68 | `S/v4/mac/ui/insights/grass_light.json` | `landing/data/generated/grass.json` | §3.8 필드만, date → 요일 | 20 |
| 69 | (생성) | `landing/data/generated/assets.json` · `sequences.json` · `bubbles.json` | §3.5·§3.8 | 10 |

합계(크롬 경로): 렌더·조각 ≈1.22MB · 영상(webm, 30fps 판) ≈2.19MB · 포스터 ≈57KB · 아이폰·위젯 ≈216KB · 브랜드·아이콘 ≈21KB · 글꼴 ≈75KB → **≈3.78MB** + JS·CSS·HTML ≈0.21MB = ≈4.0MB(예산 4.5MB). 사파리(mov) +≈0.15MB.

### 5.4 글꼴 서브셋 · 글자 검사
- `scripts/subset-fonts.mjs`: `app/**`, `components/**`, `data/**`(generated 제외)의 `.ts/.tsx` 에서 문자열·JSX 텍스트의 모든 문자(한글 음절·ASCII·문장 부호·☕️ 제외 이모지)를 모아 `scripts/.glyphs.txt` → `pyftsubset`(`/opt/anaconda3/bin/pyftsubset`, fontTools 4.51 + brotli 확인됨) 실행 → woff2 + 포함 글자 목록 `pretendard-800-sub.txt`. 사람이 카피를 고친 뒤 `npm run subset`.
- `scripts/check-glyphs.mjs`(파이썬 없이 Node 만, Vercel 에서도 돈다): 같은 방식으로 글자를 모아 `pretendard-800-sub.txt` 에 없는 한글 음절이 있으면 목록을 찍고 exit 1. `prebuild` 에 건다.
- 스캐폴드는 SPEC §4 카피 전부를 담은 상태(스텁 + fixtures)에서 첫 서브셋을 만든다. 섹션 에이전트가 카피를 옮겨 적으면 글자 집합은 같다(카피를 바꾸지 않으므로). 통합 단계에서 `npm run subset` 를 한 번 더 돌린다.

---

## 6. 통합 규칙

1. **공용 파일은 1단계 동안 아무도 고치지 않는다.** 섹션 에이전트가 공용 변경이 필요하면 `landing/docs/requests/<agent>.md` 에 (무엇을 · 왜 · 제안 diff) 를 적고, 그동안은 자기 하위 폴더 안에서 임시 우회(로컬 래퍼)를 한다. 통합 에이전트가 모아 처리한다.
2. **섹션 에이전트가 돌리는 명령은 둘뿐**: `cd /Users/yesung/check/landing && npx tsc --noEmit` 와 `npx eslint components/sections/<File>.tsx components/sections/<dir>/`(closing-footer 는 `app/licenses/page.tsx` 포함). **`next build`·`next dev`·`npm run assets`·`npm run subset`·Playwright 금지**(동시 실행 충돌). 명령 출력은 파이프로 걸러 성공처럼 보이게 하지 말고(exit code 를 본다) 전체를 읽는다. 다른 파일에서 나는 tsc 에러는 고치지 말고 requests 에 적는다.
3. **git 상태를 바꾸는 명령 금지**(add·commit·stash·checkout·reset·clean·push). 워크트리를 만들지 않는다 — `landing/` 은 아직 추적되지 않아 워크트리에 존재하지 않는다. 모든 에이전트가 `/Users/yesung/check/landing` 한 곳에서, 서로 다른 파일만 쓴다.
4. 저장소의 `landing/` 밖은 읽지도 쓰지도 않는다(소재·글꼴 원본 읽기는 예외). 임시 파일은 각자 `landing/.scratch/<agent>/`(gitignore) 또는 OS 임시 폴더에만. 같은 이름의 공유 스크래치 파일을 만들지 않는다.
5. 의존성 추가 금지(§8 목록 밖). 필요하면 requests.
6. 카피·좌표·토큰은 SPEC 정본. 렌더 위 핫스팟 좌표는 링을 켜고(개발용 `?hotspots=1` 쿼리 — Hotspot 프리미티브가 지원) 눈으로 맞출 수 있지만 dev 를 직접 띄우지 못하므로, 1단계에서는 fixtures 값을 그대로 쓰고 보정은 통합 단계에서 한다.
7. 통합 에이전트 순서: requests 처리 → `npm run subset` → `npm run typecheck && npm run lint && npm run test:store` → `npm run build` → `npm run start`(포트 3210) 또는 `npm run dev` → Playwright(§7) → OG 캡처(1200×630, desk, 근무 시작 뒤) → 성능(Lighthouse 모바일 1회) → **서버·브라우저 프로세스 종료 확인**(`lsof -i :3210` 비어 있음, 남은 node/chromium 0) → `git status --short landing` 으로 의도하지 않은 파일(덤프·스크린샷·.scratch) 이 없는지 확인(커밋은 하지 않는다).
8. 감속 모션·키보드·대비는 각 섹션의 책임이고, 통합은 검사만 한다.

---

## 7. 수용 테스트(통합 후 Playwright, `tests/e2e/`)

환경: `next start -p 3210`, Chromium(전체) + WebKit(스모크). 클립보드 권한 부여. 콘솔 메시지 수집.

### 7.1 스크린샷(눈으로 확인, `landing/.scratch/integration/shots/`)
- 390×844 · 768×1024 · 1440×900 각각: 첫 화면, 근무 시작 직후, S2 표지2 지난 뒤, #team, #poke(울트라 중 1장), #message(read), #games, #character(보드 열림), #records(점등 중간), #iphone, #trust, #install(안내 상태), #faq, #closing(퇴근 뒤 카드).
- 1280×720 에서 #team 화면: 코너 아잉과 스파인이 겹치지 않음.

### 7.2 상호작용(각 1회, 단언)
1. 히어로 [근무 시작] 핫스팟을 키보드(Tab → Enter)로 → 라벨 `img[src*="menubar-0000"]`, 스파인 `img[src*="popover-on"]`, 코너 요소 존재, 알림 영역 문구 "근무를 시작했어요. 오늘도 화이팅!".
2. 새 컨텍스트에서 누르지 않고 S2 로 스크롤 → 1초 안에 코너 등장 + "일하는 것 같아서 근무 시작했어요!", 표지 통과 뒤 라벨 `menubar-0100` → `menubar-0345`.
3. #team 세그먼트 '팀 리그' → 스파인 `league`, '우리 팀' → `popover-working`.
4. #poke [집중] 칩 3회 → `poke-focus-1` → `poke-focus-2` → `poke-list`. 민트별 찌르기 → `poke-cooldown` → 1.5초 안에 울트라 오버레이 → Escape 로 즉시 사라짐.
5. #message: 0.8초 뒤 라벨 `0345-newmsg` → '구름빵 대화 열기' → `message-composing` → '보내기' → `message-unread` → 2초 안에 `message-read`.
6. #games 세그먼트 '1:1 오목' → `gomoku-board`.
7. #character '오늘 할 일 열기' → `role=dialog[name="오늘 할 일"]` 표시 → Escape → 닫힘 + 포커스 복귀.
8. #records: 확대 잔디를 85% → 35% 로 스크롤하는 동안 불투명 1 칸 수가 단조 증가, 박자 도달 시 스파인 `token-month`, ◀ → `token-last`.
9. #iphone 탭 '나' → `ios/me-records`, 위젯 체크 → `aria-checked="true"`.
10. #install 주 버튼 클릭(다운로드 요청 가로채기) → 안내 3단계 표시, 요청 URL 이 `/api/download`. 복사 → 클립보드 = `brew install yehsung/check/aing-check`, 버튼 "복사했어요".
11. `/#faq-3` 진입 → 3번 `details[open]`, 다른 문항 닫힘. JSON-LD 파싱 결과 질문 10개.
12. #closing '근무 종료' → 라벨 `menubar-off` + 카드 등장 → 카드 [근무 시작] → 라벨 `menubar-0642`.

### 7.3 서버
- `GET /api/download` → 302, `Location` 이 `github.com/yehsung/check/releases/` 의 `aing-check.dmg` 로 끝난다. `GET /api/download?file=zip` → `aing-check.zip`.
- `GET /api/release` → 200 JSON, `version` 문자열, `dmg.mb` = "30.0"(현재 릴리스 기준) 또는 폴백.

### 7.4 품질
- 전 흐름 동안 콘솔 error 0, 처리되지 않은 promise 거부 0, 404 요청 0.
- `prefers-reduced-motion: reduce` 컨텍스트: 흐름 1·4·12 를 다시 — `.webm`/`.mov` 요청 0건, 상태(라벨·패널)는 똑같이 바뀐다, 울트라는 포스터 이미지 + 3초.
- 390 폭 가로 스크롤 0, 1440×900 문서 높이 9,000–9,900px.
- DOM 텍스트에 금지어 0: `오픈소스` `판돈` `베팅` `서울` `부산` `소마` `울찌` `열품타` `경고 없이`.
- 접근성: 모든 `img` 에 alt, 모든 핫스팟·버튼에 접근 이름, 포커스 링 표시(Tab 순회 스크린샷 3장), Lighthouse 접근성 ≥ 95(`npx -y lighthouse` 일회 실행 — 패키지에 추가하지 않는다. 실행이 안 되면 위 항목을 Playwright 로 단언).
- 성능: 모바일 LCP ≤ 2.5s · CLS ≤ 0.05(Playwright + CDP 로 CPU 4배 감속·Fast 4G 를 걸고 `PerformanceObserver` 로 측정, 가능하면 Lighthouse 모바일로 교차 확인), 첫 화면 전송 ≤ 350KB(load 까지 응답 바이트 합), 끝까지 스크롤한 총 전송 ≤ 4.5MB(크롬).
- WebKit: 첫 화면·#poke 스크린샷, 콘솔 error 0(HEVC 알파의 시각 확인은 실제 사파리에서 사람이 — `open -a Safari http://localhost:3210` 한 장, 코너 아잉 바탕이 투명한지).

---

## 8. 의존성 · 스크립트 · 환경

- **dependencies**: `next@15`(15.x 최신) · `react@19` · `react-dom@19` · `motion@12`
- **devDependencies**: `typescript@5` · `@types/node` · `@types/react` · `@types/react-dom` · `tailwindcss@4` · `@tailwindcss/postcss@4` · `eslint@9` · `eslint-config-next@15` · `@eslint/eslintrc` · `sharp` · `@playwright/test`
- **scripts**: `dev: next dev -p 3210` · `build: next build` · `prebuild: node scripts/check-glyphs.mjs` · `start: next start -p 3210` · `lint: eslint .` · `typecheck: tsc --noEmit` · `test:store: node --experimental-strip-types --test lib/demo/reducer.test.ts` · `assets: node scripts/build-assets.mjs` · `subset: node scripts/subset-fonts.mjs` · `qr: python3 scripts/make-qr.py` · `e2e: playwright test`
- `tsconfig`: `strict`, `moduleResolution: bundler`, `resolveJsonModule`, `allowImportingTsExtensions`(테스트가 `./reducer.ts` 를 import), 경로 별칭 `@/*` → `./*`.
- `next.config.ts`: `images: { unoptimized: true }`, `poweredByHeader: false`.
- `.gitignore`: `node_modules` `.next` `.scratch` `test-results` `playwright-report` `scripts/.glyphs.txt`.
- 환경 변수(선택): `NEXT_PUBLIC_SITE_URL`(배포 도메인 — 오늘은 비움), `GITHUB_TOKEN`(API 한도용, 없어도 됨).
- 배포 체크리스트(수리 단계 추가): ① `NEXT_PUBLIC_SITE_URL` 을 배포 도메인으로 넣는다(없으면 `lib/site.ts` 가 `VERCEL_PROJECT_PRODUCTION_URL` → localhost 순으로 폴백 — og:image·canonical·sitemap 이 이 값을 쓴다). ② Vercel 에 `GITHUB_TOKEN`(공유 출구 IP 의 비인증 60회/시 한도 회피). ③ 앱 릴리스마다 `data/fixtures.ts` `RELEASE_FALLBACK`(버전·바이트·MB)을 갱신한다.
- 배포: 오늘은 로컬까지. Vercel 프로젝트 루트 = `landing/`, 빌드는 `next build`(에셋·서브셋은 커밋된 결과를 쓴다).
