# 유리 프리미티브 API (v3 · 1단계 산출물)

2단계(기능 무대 · 설치/brew · FAQ/아웃트로/푸터)는 이 문서만 보고 쓴다. 정본 설계는 `docs/v3/brief.md`(§3 토큰 · §5 움직임 · §8 문구).
바탕 오로라(`AuroraField`)와 굴절 필터 자리(`GlassDefs`)는 `app/layout.tsx` 가 이미 마운트했다 — **다시 두지 말 것.**

가져오기는 파일 경로로(배럴 `@/components/glass` 도 있지만 서버 컴포넌트에서는 파일 경로가 안전하다).

---

## 1. `Glass` — 유리 판 (서버·클라 어디서나)
`import { Glass, glassClass } from '@/components/glass/Glass'`

| prop | 값 | 기본 |
|---|---|---|
| `level` | `'thin'`(칩·알약·메뉴바) · `'regular'`(터미널·FAQ 판·세그먼트·설치 카드) · `'thick'`(기능 무대 베젤) | `'regular'` |
| `as` | `'div' 'section' 'article' 'aside' 'header' 'footer' 'nav' 'figure' 'ul' 'ol' 'li' 'span' 'details' 'pre'` | `'div'` |
| `radius` | 숫자(px) 또는 CSS 길이 — 단계 기본 thin 999 · regular 22 · thick 30 | — |
| `tint` | 글 많은 판의 대비 보험(짙은 바닥색 .38 — 터미널에 권장) | `false` |
| `specular` | 포인터 스페큘러(pointer:fine · 감속 아님일 때만 움직임) | `false` |
| `refract` | 가장자리 굴절. `true` 또는 `{ band, scale, aberration, rimBlur }` | `false` |
| 그 밖 | `className` `style` `id` `aria-*` `ref` 등 HTML 속성 그대로 | |

```tsx
<Glass level="regular" tint className="p-6 desk:p-8">…터미널…</Glass>
<Glass as="section" level="thick" specular className="p-4">…무대…</Glass>
<div className={glassClass('regular')}>이미 있는 요소에 클래스만</div>
```

## 2. `GlassButton` — 유리 버튼 (서버·클라)
`import { GlassButton, glassButtonClass } from '@/components/glass/GlassButton'`
- `variant`: `'primary'`(보라 빛 — 한 화면에 하나) · `'glass'`(투명 유리, 보조) · `'ghost'`(글자만). `size`: `'l'` 52 · `'m'` 44 · `'s'` 32(누를 자리 44 보장).
- `href` 있으면 `<a>`(+`external`), 없으면 `<button onClick>`. `ariaLabel` `dataCta` `id` 등.
```tsx
<GlassButton href="/api/download" variant="primary" size="l" ariaLabel={`aing-check.dmg 다운로드, ${mb}MB`}>aing-check.dmg 다운로드</GlassButton>  {/* mb = getRelease() */}
<GlassButton href="#install" variant="glass" size="m">설치 방법 보기</GlassButton>
<a className={glassButtonClass('glass', 's')} href="/licenses">글꼴 라이선스</a>
```
다운로드 버튼은 플랫폼 분기가 든 `@/components/ui/DownloadCTA`(`placement` `size` `tone="fill"|"outline"` `label` `ariaLabel`)를 그대로 써도 된다 — 이미 유리로 입혔다.
QR 흰 타일: `@/components/ui/QrCode`(`size` · `href` · `src` · `alt` — 기본 = App Store QR 새 탭. 바깥 주소만 새 탭, `/#android` 같은 사이트 경로는 같은 탭 · desk 전용 — brief §12, 2026-10-30).

## 3. `CommandPill` · `BrewPill` — 명령 알약 + 진짜 복사 (client)
`import { CommandPill, BrewPill } from '@/components/glass/CommandPill'`
- thin 유리, JetBrains Mono, `$` 프롬프트(복사·선택 제외), 오른쪽 [복사] 칩 → `복사했어요`(2초) + 페이지 라이브 영역 알림(`LiveAnnouncer`, page.tsx 에 이미 있음).
- 좁은 폭에서는 `/` 뒤 · `&& ` 뒤에서만 줄바꿈 — 390 가로 넘침 0. 두 줄이면 26px 둥근 판.
- 명령 문자열 정본은 `BREW`(`@/data/fixtures` — `install` · `upgrade`). 하드코딩 금지.
```tsx
<BrewPill />                                  {/* brew install yehsung/check/aing-check · 접근 이름 'brew 설치 명령 복사' */}
<BrewPill size="l" className="w-full" />      {/* 넓은 자리(글자 15.5px) */}
<CommandPill command={BREW.upgrade} copyAriaLabel="brew 업데이트 명령 복사" />
```
알약 없이 버튼만: `import { CopyButton } from '@/components/glass/CopyButton'` — `text` `ariaLabel`(보이는 '복사' 포함) `label` `done` `variant="chip"|"glass"|"primary"` `icon` `dataCta`(측정용 `data-cta`, 2026-10-30).
설치 선택 창(유리 팝오버 — 다운로드 버튼이 연다)은 프리미티브가 아니라 `@/components/install/InstallChooser`(DownloadCTA 가 hero·outro·nav ≥768 에서 쓴다 — brief §11). 판은 `<Glass level="thick" specular>` + 짙은 틴트, body 포털 · z 메뉴바 창 60 / 히어로·아웃트로 창 49(메뉴바 아래). 자리 계산은 순수 함수 `computePlacement`(`components/install/chooser-logic.ts`).
iOS 에서 숨기려면 부르는 쪽 className 에 `[html[data-platform=ios]_&]:hidden`.

## 4. `LocalLight` — 절마다 유리 뒤 국소 빛 (서버·클라)
`import { LocalLight } from '@/components/glass/LocalLight'`
- `tone` `'violet'`(기본) · `'orchid'` · `'indigo'` · `'rose'`(아주 작게, 페이지 전체에서 한두 곳) · `'ice'` / `x` `y`(중심, 기본 50%) / `size`(지름 px 또는 CSS 길이, 기본 900) / `aspect`(세로/가로, 기본 .7) / `strength`(중심 α, 기본 .32).
- **부모는 `relative isolate`**(빛이 z -1 로 절 안에 머문다), 빛이 가장자리 밖으로 크면 부모에 `overflow-clip`.
```tsx
<section id="install" className="relative isolate overflow-clip">
  <LocalLight tone="violet" x="62%" y="45%" size="min(1200px, 120vw)" />
  <LocalLight tone="indigo" x="15%" y="85%" size={800} strength={0.24} />
```

## 5. 훅 (클라이언트 컴포넌트 안에서 직접 걸 때)
- `usePointerSpecular(ref, enabled?)` — `@/components/glass/usePointerSpecular`. 요소에 `--mx` `--my`(px) `--spec`(0|1) 를 단다. `.glass` 의 ::before(테두리 캐치라이트)·::after(면 광택)가 읽는다.
- `useRefraction(ref, { level?, band?, scale?, aberration?, rimBlur?, entrance?, enabled? })` — `@/components/glass/useRefraction`. 데스크톱 Chromium 에서만 켜진다(`canRefract()`), 나머지는 아무것도 안 함 = blur 폴백.
```tsx
const ref = useRef<HTMLDivElement>(null);
useRefraction(ref, { level: 'regular', band: 14, scale: 36 });   // 세그먼트 물방울
return <div ref={ref} className={glassClass('regular')} style={{ '--g-r': '999px' } as CSSProperties} />;
```

## 6. CSS 토큰·클래스 (app/globals.css)
- 색: `--bg` `--bg-deep` `--light-violet|orchid|indigo|rose` `--ice` `--ink-1|2|3` `--focus` · 알파용 `--violet-rgb` 등(`rgb(var(--violet-rgb) / .3)`).
  Tailwind: `bg-bg` `bg-bg-deep` `text-ink-1|2|3` `text-focus` `text-light-violet` …(v2 이름은 3단계에서 걷어냈다 — `border-line` 만 /licenses 용으로 남음).
- 글자: `.t-display`(히어로 H1) · `.t-h2`(설치·FAQ·아웃트로 H2 = clamp(32, 3.6vw, 52)) · `.t-h2-feature`(기능 제목 = clamp(28, 2.6vw, 40)) · `.t-h3` · `.t-lead`/`.t-body`(17–19px · ink-2 기본) · `.t-small` 14 · `.t-code`(모노) · `.t-tabular`. 제목은 `Headline`(lines → `<br>`)으로.
- 유리: `.glass .glass--thin|regular|thick` (+ `.glass-tint`) · 버튼 `.gbtn .gbtn--primary|glass|ghost|chip .gbtn--l|m|s` · 알약 `.cmd-pill`.
  2차(2026-10-22) 겉모습: 채움은 거의 투명(흰 α thin .06 · regular .045 · thick .05 → 아래로 옅게) — 재질감은 **림**이 만든다
  (위 가장자리·왼위 모서리 호의 흰 하이라이트 1.25px(thick 1.5px), 오른아래 얼음빛 반사, 안쪽 가장자리 어두운 띠 = 두께).
  그래서 **유리 판 뒤에는 늘 빛이 있어야 한다**(`LocalLight` 1–2개 — 판 가장자리에 걸치면 굴절·흐림이 보인다). 글 많은 판은 `tint`.
  `primary` 버튼 = 보라 틴트 유리(반투명 채움 + 위 광택 + 아래 안쪽 빛 + 림), `primary`·`glass` 버튼은 포인터 스페큘러가 자동(props 그대로).
- 움직임: `--ease-out` · `--ease-spring`(linear() 스프링, 미지원은 cubic-bezier). 감속 모션이면 전부 정지가 기본(버튼 눌림 포함).
- 포커스 링: 전역 `:focus-visible` = 2px `--focus`, 오프셋 3 — 덮어쓰지 말 것.

## 7. 하지 말 것
- **굴절은 한 화면에 동시에 보이는 판 셋까지**: 메뉴바(켜짐) · 히어로 팝오버(켜짐) · 기능 세그먼트 물방울(2단계). 무대·터미널·FAQ·카드에는 `refract` 를 켜지 말 것(blur 만).
- `.glass` 요소에 `::before`/`::after` 를 따로 쓰지 말 것(유리가 쓴다 — z 3 으로 내용 위에 깔린다). 내용이 판 끝까지 차면 padding ≥ 1px.
- **절(section)에 `relative isolate overflow-clip` 을 꼭 줄 것** — 빼면 `LocalLight` 가 옆 절로 번지고 가로 넘침이 생긴다
  (2026-10-22 실측: `#features` 가 overflow visible 이라 빛이 히어로 가운데로 번지고 scrollWidth 1540 @1440).
- 유리 판의 **조상에 `opacity < 1` · `filter` · `mask` · `clip-path` · `mix-blend-mode` 를 두지 말 것** — 그 조상이 backdrop root 가 되어 유리 뒤가 비어 보인다. 페이드는 유리 요소 자신에 건다. `transform` 은 괜찮다.
- 큰 요소에 `filter: blur()`·`drop-shadow()` 금지(WebKit 이 화면 밖 필터 층을 (0,0) 에 그린 전력) — 빛은 방사 그라디언트(`LocalLight`)로.
- 유리 안에 유리를 겹치면 안쪽 판은 바깥 판의 채움만 흐린다(브라우저 규칙) — 겹침은 버튼·칩 정도만.
- 렌더(앱 화면 이미지)를 유리 베젤에 넣을 때 크롭·마스크 금지. 모서리 둥글림은 렌더 바깥 여백에만 닿게(≤ 16px).
- `AuroraField` · `GlassDefs` 를 다시 마운트하지 말 것. 절마다 `LocalLight` 1–2개면 충분하다.
- 문구는 `docs/v3/brief.md §8` 글자 그대로. 새 한글이 생기면 `npm run subset`.
- **`*.module.css` 를 쓰지 말 것** — 이 프로젝트는 next.config 의 turbopack `'*.css'` 규칙(`@tailwindcss/turbopack`, `as: '*.css'`) 때문에 `*.module.css` 도 전역 CSS 로 컴파일된다(클래스 이름이 지역화되지 않는다). 절 전용 CSS 는 평범한 `.css` 에 절 접두 클래스로.

## 8. 확인할 때 알아 둘 것(실측 2026-10-22)
- Playwright 헤드리스 WebKit 은 `backdrop-filter` 를 아예 안 그린다(평범한 blur 도) — WebKit 캡처는 '흐림 없는 최악의 경우'다. 실제 Safari 는 blur 폴백이 그려진다.
- 헤드리스 Chromium 은 **DPR 2 에서 스크롤된 fixed 요소의 backdrop 을 어긋나게 잡는다**(빈 페이지에서도 재현) — 유리 캡처는 DPR 1 로.
- WebKit 은 `CSS.supports('backdrop-filter','url(#a)')` 가 true 인데 그리지는 못한다 — 굴절 감지는 `canRefract()`(navigator.userAgentData)만 쓴다.
