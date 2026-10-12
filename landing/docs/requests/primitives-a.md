> 거부된 v1 섹션 요청(2026-10-12 15:50 폐기). 기록으로만 남는다 — v2 요청은 `docs/v2/requests/`, 정본은 `docs/v2/`.

# primitives-a: 공용 프리미티브 19개, 계약 메모와 요청

작성: primitives-a, 2026-10-12. 대상 파일은 `components/ui/{Button,DownloadCTA,AppStoreBadge,QrCode,TextLink,SectionShell(+Beat),Headline,TimeMark,MacWindowShell,RenderImage,RenderStack,Hotspot,PanelSlot,Segmented,CopyButton,CommandBox,VisuallyHidden,PlatformScript,LiveAnnouncer}.tsx` 이다.
모든 파일은 named export 와 default export 를 둘 다 낸다. props 는 PLAN §3.3 표 그대로이고, 아래 "선택 props" 는 그 위에 얹은 상위 집합이다(기존 서명을 깨지 않는다).

## 0. core 에 요청: 없음 (확인만)
- `app/globals.css` 의 `.cta-mac/.cta-ios/.cta-other` 규칙은 DownloadCTA 와 뜻이 같다. DownloadCTA 는 같은 판정을 Tailwind 임의 변형(`[html[data-platform=ios]_&]:hidden` 등)으로도 스스로 한다. 그래서 두 쪽이 겹쳐도 충돌하지 않는다. 다만 **이 클래스들에 `display` 를 "보이게" 주는 규칙은 넣지 말 것.** 래퍼가 `display: contents` 여야 한다.
- `hotspot-pulse` 키프레임을 그대로 쓴다. Hotspot 의 맥동 층은 `animation: hotspot-pulse 700ms linear 1 both` 에 인라인 `animation-delay: TIMING.startPulseAt(1200ms)` 를 준다. 불투명도는 건드리지 않는다(키프레임이 box-shadow 알파로 사라진다). 감속 모션이면 키프레임이 없으니 아무 일도 없다.
- 섹션 스텁의 제목 id(`${id}-title`)가 SectionShell 의 기본 `aria-labelledby` 와 같다. 바꿀 것이 없다.
- `<html suppressHydrationWarning>` 은 layout 에 이미 있다(PlatformScript 가 data-platform 을 먼저 단다).

## 1. 서버/클라 경계(섹션 에이전트 필독)
- `'use client'` 가 **없는 것**(서버 섹션에서 바로 써도 된다): Button · TextLink · Headline · TimeMark · MacWindowShell · RenderImage · AppStoreBadge · QrCode · VisuallyHidden · PlatformScript.
  - Button 의 `onClick` 은 클라 파일에서만 넘긴다. 서버 섹션은 `href` 로 쓴다.
- `'use client'` 인 것: DownloadCTA · SectionShell/Beat · RenderStack · Hotspot · PanelSlot · Segmented · CopyButton · CommandBox · LiveAnnouncer.
  - 서버 섹션은 직렬화되는 props 만 넘긴다. `PanelSlot` 의 `hotspots[].onActivate`·`Segmented.onChange`·`Hotspot.onActivate` 는 함수라서 **클라 하위 파일 안에서** 조립한다.
  - 클라 파일에서 함수(`panelSwapMs`)를 export 한다. 이것을 서버 컴포넌트에서 import 하지 말 것(클라 참조가 들어온다). 클라 파일끼리는 괜찮다.

## 2. 컴포넌트별 계약 메모

### SectionShell / Beat
- DOM id 는 SectionId 그대로이고 **`'hero'` 만 `#top`** 이다(SPEC §4.0). `aria-labelledby` 의 기본값은 `${id}-title`(예: `hero-title`, `team-title`)이고, 섹션 제목에 그 id 를 준다. 다르게 하려면 `labelledBy` 를 준다.
- 안쪽에 `relative mx-auto max-w-[1440px] px-[var(--gutter)]` 래퍼가 하나 있다. 선택 props 는 `labelledBy`, `innerClassName` 이다.
- kind 별 값: spine = `min-h-[72svh]`·세로 가운데·위아래 64/80/96 · plain = 72/96/112 · band = plain + `--bg-1`. 히어로·S2 처럼 높이가 다르면 `minH` 로 준다(예 `minH="max(560px, calc(100svh - var(--nav-h) - 64px))"`).
- IO(-45%/-45%)와 focusin 은 **활성 섹션이 바뀔 때만** `setActiveSection` 을 부른다. 섹션 안에서 Tab 을 해도 activeBeat 가 지워지지 않는다.
- Beat 는 중앙 띠에 걸리면 `setActiveBeat(id)` 를 부른다. 이 게시는 한 프레임 뒤로 미룬다(포커스면 마이크로태스크 뒤). 같은 프레임에 섹션이 바뀌면서 박자가 지워지는 경합을 피하려는 것이다. 벗어날 때는, 지금 박자가 자기 것일 때만 `null` 로 되돌린다.
- transform·filter·contain·will-change 를 쓰지 않는다(안쪽 fixed 핫스팟). 섹션 쪽도 SectionShell 과 PanelSlot 사이 조상에 이것들을 넣지 말 것.

### PanelSlot (PLAN §3.4)
- **인라인 창은 SSR 부터 늘 그린다**(`desk:hidden`). 그래서 phone·tab 첫 페인트에 창이 있다. 폭은 `inlineWidth`(기본 `min(100%, 380px)`)다. 폭을 재기 전에는 `aspect-ratio` 로, 잰 뒤에는 px 로 그린다(배율 = 폭/414). 높이는 패널 pt × 배율이고 200ms ease-out 으로 맞춘다.
- desk 에서는 그림을 그리지 않는다. `(활성 섹션 ∧ spineOpen ∧ spine.rect)` 일 때만 현재 패널(`panelFor(section, activeBeat, s)`)의 핫스팟을 `position: fixed` 로 그린다. 좌표는 `left = rect.x + x·rect.scale` 이고 z-index 는 `calc(var(--z-spine) + 1)`, 나머지 경우에는 `inert` 다.
  → **MenubarStage 는 `setSpineRect` 에 창 바깥 상자(뷰포트 좌표, getBoundingClientRect)와 배율 s 를 게시해야 한다.** 핫스팟은 rect.x/y 를 렌더 (0,0) 으로 본다.
- `beat` 를 주면(문자열이든 null 이든) desk 핫스팟은 `activeBeat === beat` 일 때만 나온다. 인라인 판도 그 박자로 고른다. 생략하면 활성 섹션의 activeBeat 를 따른다. 한 섹션에 PanelSlot 을 둘 두는 경우(예: records 본문과 `records:tokens` 박자)에는 각자 `beat` 를 주어야 desk 핫스팟이 겹치지 않는다.
- 선택 props: `eager`(히어로 인라인 판을 `loading="eager"` 로, fetchpriority 는 주지 않는다 — SPEC S1).
- `children` 은 인라인 래퍼(`relative`, 폭 = inlineWidth) 안, 창 뒤에 그린다. 인라인 무대는 이 래퍼를 기준으로 absolute 배치한다. desk 에서는 래퍼째 숨는다.
- 판 교체 시간은 `panelSwapMs(직전, 지금)` 으로 정한다(아래 RenderStack).

### RenderStack
- 부모는 크기가 정해진 positioned 상자여야 한다(MacWindowShell). 이 층 자체는 `absolute inset-0 isolate` 다.
- `panels` 를 전부 마운트한다(lazy 이므로 보일 때만 요청된다). 새 active 판은 `img.decode()` 를 마친 뒤 위로 올라와 불투명 0→1 이 된다. 직전 판은 그동안 밑에서 1 로 버티고, 교차가 끝나면 0 이 된다. 실측: 빈 프레임 없음, 밝기 꺼짐 없음.
- 교차 시간: `instant` 면 0, 아니면 `durationMs ?? 180` 이다. 감속 모션이면 최대 120.
- `export function panelSwapMs(prev, next)` 는 SPEC §2.7·S1·S4·S5 의 규칙이다. popover-off↔on · poke-list↔cooldown · message-unread↔read 는 **0ms**, 메시지 창 안(popover-working·newmsg·message-*)은 **120ms**, 그 밖은 undefined(기본값)다. **MenubarStage 의 스파인도 이 함수를 쓰면 인라인 창과 같은 리듬이 된다.**
- `overlay:'tick'` 판에는 `TickStrip` 을 판 층 안에 바로 넣는다. TickStrip 은 스스로 `(96·s, 48·s)` 에 absolute 로 선다(primitives-b 의 계약).
- 선택 props: `eager`, `durationMs`, `className`.

### Hotspot
- 부모는 positioned 여야 한다. 위치는 rect(pt) × scale(px)다. 반지름은 capsule = 9999px, round = `radiusPt ?? 15` × scale, circle = 50%, 그 밖 = `radiusPt ?? 0` × scale 이다.
- 히트 영역은 `::before` 로 최소 `minHit`(44)px 까지 넓힌다(SPEC §7). **이웃 핫스팟과 44px 안으로 붙어 있으면 넓힌 영역이 겹친다.** 이때는 DOM 뒤쪽이 클릭을 먹는다. fixtures 좌표는 phone 배율에서도 충분히 떨어져 있지만, 새 좌표를 쓰면 확인할 것.
- `disabled` 면 `aria-disabled` 를 달고 활성화를 막는다. 호버 링과 포인터 커서도 없다. Tab 순서에는 남는다. `focusable={false}` 면 tabindex -1 이다. `role="tab"` 이면 `selected` 로 로빙 tabindex(0/-1)를 쓴다. 화살표 키는 tablist 컨테이너(섹션) 몫이다. `role="checkbox"` 면 `aria-checked` 다.
- 호버 링은 `--hotspot` 2px 에 불투명 .7, 120ms 선형이다. 포커스는 전역 `:focus-visible` 라벤더다. `?hotspots=1` 이면 링이 늘 켜진다(useSyncExternalStore 로 읽어 하이드레이션 어긋남이 없다).
- 선택 props: `id`, `className`, `style`, `ref`(React 19 ref prop. 클로징의 "포커스를 [근무 시작] 핫스팟으로"에 쓴다), `pulseDelayMs`(기본 1200), `ariaControls`, `ariaDescribedBy`.

### DownloadCTA
- 세 벌(`.cta-mac`/`.cta-ios`/`.cta-other`)이 모두 SSR 되는 `display: contents` 래퍼다. **flex 줄 안에 바로 놓으면** 안쪽 알약이 바로 flex 항목이 된다.
- mac·other 는 `<a href="/api/download">`(`file="zip"` 이면 `?file=zip`)에 `demo.installClicked(placement)` 를 건다. nav 는 phone 폭에서 `설치`(`#install`)다.
- ios 는 nav 에서는 `App Store`(새 탭), 그 밖에서는 `Mac 링크 보내기`(보조 캡슐)다. `navigator.share({ title: '아잉체크 Mac 앱', url: origin + '/#install' })` 을 부르고, share 가 없거나 실패하면 클립보드에 복사한다. 이어서 '링크를 복사했어요' 2초와 알림이 나온다. 사용자가 공유 시트를 닫으면(AbortError) 아무것도 하지 않는다.
- 선택 props: `ariaLabel`(접근 이름에 형식·크기를 넣는다: "aing-check.dmg 다운로드, 30.0MB" — SPEC S11), `className`(알약에 붙는다. **display 유틸은 넣지 말 것**. 실측으로 Tailwind 출력에서 `.inline-flex` 가 `.hidden` 뒤에 온다).
- 히어로 iOS 순서(배지 먼저)는 섹션이 정한다. 예: 배지 래퍼에 `[html[data-platform=ios]_&]:order-first`.

### AppStoreBadge / QrCode
- 배지의 사방 여백 = 높이/4 이고, `<a>` 의 padding 으로 들어 있다(애플 여백 규칙이 컴포넌트 안에 있다). 글 열 왼쪽 끝에 맞추려면 섹션 쪽에서 음수 margin(48 → `-ml-3`)을 쓴다. src 는 assets.json 의 `brand/appstore-badge-ko-black` 이고, 없으면 `/assets/brand/appstore-badge-ko-black.svg` 를 쓴다.
- QR 은 `hidden desk:block`, 흰 타일, `--r-window`, 안쪽 여백 8 이다. 누르면 App Store 새 탭으로 간다. alt 는 "App Store 아잉체크 페이지로 가는 QR 코드".

### TimeMark
- **부모(relative)의 왼쪽 끝이 그리드 여백(= --gutter)이어야 한다.** 글 열이나 H2 묶음 안에서 H2 바로 앞에 둔다. SectionShell 안쪽 래퍼에 바로 넣으면 안 된다(그 래퍼의 0 은 화면 쪽이다).
  - desk: `left = −gutter/2 − 16px` 이라 x 는 1440 에서 24, 1024–1279 에서 8 이다(실측 1440 → 24.0). 윗변은 H2 글자 크기 × 0.28 − 2px(H2 첫 줄 글자 윗선)다.
  - tab·phone: H2 위 8px 에 정적 흐름으로 놓인다.

### CommandBox / CopyButton
- CommandBox 의 `$ ` 는 `aria-hidden` 에 `user-select: none` 이라 복사와 선택에서 빠진다. 복사가 거부되면 **스스로** 명령 글자를 선택 상태로 만들고 "⌘C로 복사하세요" 작은 줄과 알림을 낸다(섹션이 할 일 없음). phone 에서도 가로 스크롤 없이 `pre-wrap`·`break-all` 로 줄바꿈한다.
- CopyButton 은 성공하면 `done` 문구를 알림으로도 읽고(`demo.announce`), 다시 누르면 2초가 새로 시작한다. 두 문구를 한 칸에 겹쳐 두어 폭이 흔들리지 않는다. 숨은 쪽은 visibility:hidden 이라 접근 이름에서 빠진다. 선택 props: `onFail`, `className`.

### Segmented
- 칸이 같은 폭(`auto-cols-fr`)이라 알약 위치를 재지 않고 CSS 로만 옮긴다(SSR 부터 맞다). 화살표, Home, End 로 고르고 포커스도 옮긴다.

### Button
- 주 l 만 `t-button`, 나머지는 `t-button-s` 다. 눌림 scale(.98) 100ms 는 감속 모션이면 없다. `disabled + href` 면 `<span role="link" aria-disabled>` 다.
- 선택 props: `id`, `type`, `ariaExpanded`, `ariaControls`, `ariaDescribedBy`, `ariaPressed`, `ref`. S7 "오늘 할 일 열기"의 `aria-expanded`/`aria-controls="todo-board"`, S13 근무 종료의 `aria-describedby` 에 쓴다.

### RenderImage / MacWindowShell / Headline / VisuallyHidden
- RenderImage 선택 props: `scale`(기본 1, width/height 속성 = pt × scale), `style`. 키가 없으면 개발 모드 경고와 빈 `<img alt>` 다.
- MacWindowShell 선택 props: `fluid`(폭 100% + aspect-ratio), `style`, `id`, `role`, `ariaLabel`(스파인 `#spine role="img"` 에 쓸 수 있다). 바탕색은 넣지 않는다(렌더 모서리 알파 위로 다른 색이 비치지 않게).
- Headline: `.t-*`, Pretendard 800, `text-wrap: balance`, display 를 뺀 나머지는 `max-width: 13em`. 선택 props: `className`.
- VisuallyHidden 선택 props: `id`(aria-labelledby 대상), `className`.

## 3. 검증한 것(통합 에이전트 참고)
- `npx tsc --noEmit` exit 0 · `npx eslint components/ui` exit 0.
- 브라우저 하네스(Next 밖에서 esbuild 로 묶어 SSR 후 hydrateRoot, Chromium 1.60, 54개 단언 전부 초록). 하네스는 끝나고 지웠다.
  - Mac 1440: CTA 가 mac 판 하나 · desk 핫스팟이 rect + pt 정확(1232, 81) · 비활성 섹션 inert · Tab 순서(내비 CTA → 히어로 CTA → 배지 → 핫스팟) · Enter → pressStart 와 알림 · 다운로드 클릭 → `/api/download` 와 installHint · 세그먼트 화살표 · IO 섹션·박자 게시와 해제 · 복사 2초 · 교차(새 판이 옛 판 위로 0→1, 옛 판은 1 유지 뒤 0) · `::before` 히트 44 · 콘솔 error·하이드레이션 경고 0.
  - iPhone 390: data-platform=ios · 내비 App Store · 히어로 "Mac 링크 보내기"(접근 이름 정확) · 인라인 창 350×552 · 인라인 핫스팟 pt×0.845 · 탭 → popover-on 0ms 와 틱 층 · 팀 교차 180ms · 높이 600pt×배율 · share 폴백 클립보드 · 가로 넘침 0.
  - Windows: `.cta-other` 만 보인다. Mac 390: 내비 `설치`, 복사 거부 시 선택과 ⌘C 안내.
  - 감속 모션: 교차 120ms. 핫스팟 역할·aria·tabindex·반지름이 맞다. disabled 는 활성화도 링도 없다. 스파인을 접으면 desk 핫스팟이 사라지고 inert 가 된다. `?hotspots=1` 이면 링 .7 이고 하이드레이션 경고가 없다.
