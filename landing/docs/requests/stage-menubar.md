> 거부된 v1 섹션 요청(2026-10-12 15:50 폐기). 기록으로만 남는다 — v2 요청은 `docs/v2/requests/`, 정본은 `docs/v2/`.

# stage-menubar — 요청·계약 메모

작성: stage-menubar, 2026-10-12. 소유 파일은 `components/sections/MenubarStage.tsx` 와 `components/sections/menubar-stage/**` 이다.
공용 파일을 고치지 않았다. 아래 1은 공용 쪽 개선 요청(지금은 로컬 우회로 동작한다)이다. 2~5는 다른 섹션과 통합 단계가 지킬 계약이다.

## 1. 요청: RenderStack 에 `onSettled` 콜백(선택 prop)을 더해 주세요 (primitives-a / integration)
- **무엇**: `components/ui/RenderStack.tsx` 에 `onSettled?: (top: PanelKey) => void` 를 추가한다. 맨 위 판(`top`)이 바뀐 커밋 직후에 부른다.
- **왜**: 스파인은 접혀 있는 동안 바뀐 판을 0ms 로 갈아 끼운다. 그리고 RenderStack 맨 위가 **실제로 그 판이 된 뒤에** 창을 연다. 그래야 여는 첫 프레임에 옛 판이 비치지 않는다.
  지금은 RenderStack 의 DOM 약속을 읽어서 해결한다(`menubar-stage/Spine.tsx` 의 `useStackTop`). 층마다 `data-panel` 이 있고, 맨 위가 아닌 층에만 `aria-hidden` 이 붙는다는 점을 이용해 MutationObserver 로 본다.
  이 마크업이 바뀌면 300ms 보험 타이머가 대신 창을 연다(그때는 옛 판이 한두 프레임 비칠 수 있다).
- **제안 diff**:
  ```diff
   export interface RenderStackProps {
     …
     className?: string;
  +  onSettled?: (top: PanelKey) => void; // 맨 위 판이 바뀐 커밋 직후
   }
  …
  -export function RenderStack({ panels, active, scale, instant, tickStartedAt = null, eager, durationMs, className }: RenderStackProps) {
  +export function RenderStack({ panels, active, scale, instant, tickStartedAt = null, eager, durationMs, className, onSettled }: RenderStackProps) {
  …
  +  const settled = useEffectEvent((p: PanelKey) => onSettled?.(p));
  +  useEffect(() => { settled(top); }, [top]);
  ```
  이 diff 가 들어오면 `Spine.tsx` 의 `useStackTop` 을 `onSettled={setStackTop}` 로 바꾸면 된다. 동작은 같다.

## 2. 계약: `#spine` 은 `<header>` 의 **형제**다 (integration)
- PLAN §4.1 의 "header 를 렌더하고 #spine 을 담는다"는 **컴포넌트가 둘 다 렌더한다**는 뜻으로 읽었다. `MenubarStage` 는 `<><header/>…<div id="spine"/></>` 조각을 돌려준다.
- 이유: `position: sticky; z-index: 50` 인 헤더는 스택 맥락을 만든다. 스파인을 그 안에 두면 스파인은 실질 z 50 이 된다. 그러면 PanelSlot 의 desk 핫스팟 층(fixed, z = `--z-spine` + 1 = 41)이 스파인 **밑으로** 깔려서 눌리지 않는다.
- `app/page.tsx` 에서 `<MenubarStage />` 를 다른 요소로 감싸지 말 것(특히 transform·filter·contain·isolation 이 있는 요소).

## 3. 계약: 히어로 CTA 줄 `[data-hero-cta]` (hero 에이전트 / integration)
- 내비 CTA 의 테두리 → 채움은 `document.querySelectorAll('[data-hero-cta]')` 를 IntersectionObserver(rootMargin 위 −48px = 내비 띠)로 보고 정한다. 하나라도 보이면 테두리, 모두 화면 밖이면 채움이다.
- 그래서 `data-hero-cta` 는 **상자가 있는 요소**(flex 줄 div 등)에 달아야 한다. `display: contents` 인 요소는 교차하지 않으므로 늘 "안 보임"으로 읽혀 처음부터 채움이 된다. 플랫폼별로 여러 벌이어도 된다(`display: none` 인 벌은 자연히 빠진다).
- 하이드레이션 시점에 줄이 아직 없으면 MutationObserver 로 생길 때까지 기다린다.

## 4. 계약: 스파인 부팅은 `#top`(SectionShell 'hero') 에 기댄다 (integration)
- 스토어의 첫 `activeSection` 은 늘 'hero' 다. 그래서 `/#faq-3` 같은 해시나 스크롤 복원으로 다른 섹션에서 열면, 하이드레이션 직후 한순간 히어로 팝오버가 뜰 수 있다. 이것을 막는 장치가 둘 있다.
  - 첫 페인트(JS 이전): `html:has(:target:not(#top):not(#main)) #spine { visibility: hidden }`. Tailwind 임의 변형이며, 부팅 판정 뒤 클래스를 걷는다. `:has` 가 없는 브라우저(Firefox < 121)에서는 이 규칙이 무시되어 그냥 보인다.
  - 하이드레이션 뒤: `#top` 을 SectionShell 과 같은 중앙 띠(−45%/−45%)로 한 번 잰다. 밖이면 전이 없이 감추고, 스토어가 다른 섹션을 받은 다음부터 스토어를 따른다.
- `#top` 이 없으면 바로 '판정 끝'으로 넘어간다(기능은 살고 위 보호만 빠진다).
- 로드 내려옴(`.anim-spine-drop`)은 SSR 마크업의 클래스(CSS 키프레임)로 돈다. 끝나면(또는 700ms 뒤, 또는 접히면) 클래스를 걷는다. fill 값이 인라인 열림/닫힘 값을 이기지 않게 하려는 것이다.

## 5. 계약: PanelSlot 이 들어가는 섹션은 조상에 transform·filter·contain·container-type·스택 맥락을 두지 말 것 (섹션 에이전트 전원)
- 개발 모드에서 `#spine` 과 모든 `[data-panel-slot-desk]` 의 조상 사슬을 `getComputedStyle` 로 검사한다. 마운트 때, 그리고 섹션이 바뀔 때마다 0ms 와 2초 뒤에 돈다. 아래 경우 `console.warn("[MenubarStage] …")` 을 낸다(같은 문장은 한 번만).
  - fixed 기준을 바꾸는 것: transform · translate · rotate · scale · perspective · filter · backdrop-filter · contain(layout|paint|strict|content) · container-type · content-visibility(auto|hidden) · will-change(transform 류).
  - 핫스팟 층을 스파인 밑으로 깔 수 있는 스택 맥락(PanelSlot 조상만): position fixed/sticky, z-index 가 있는 positioned 요소, opacity < 1, isolation: isolate, mix-blend-mode.
- 히어로 글 상자의 `container-type: inline-size`(SPEC S1, 짧은 phone 의 H1 cqi)는 **PanelSlot 의 조상이 아니어야** 한다.

## 6. 참고(구현 결정)
- 감속 모션: SPEC §2.7·S0 를 따랐다. 열림/닫힘은 불투명 120ms 선형만 남고 이동·크기는 없다. 판 교차는 RenderStack 이 최대 120ms, 창 높이는 MacWindowShell 이 0ms 다. 라벨 번짐과 로드 내려옴은 키프레임이 없어서 일어나지 않는다. 상태 변화는 그대로다.
- 스파인 폭은 CSS `--spine-w = min(414px, (100svh − 48 − 6 − 16) × 414/695)` 로 SSR 부터 맞다. 창 높이는 `calc(var(--spine-w) × 판pt / 414)` 다. 클라는 `#spine` 을 재서 s = 폭/414 를 되읽고, `setSpineRect({ x, y, w, h: 판pt × s, scale: s })` 를 게시한다.
  게시하는 것은 열려 있고 부팅 판정이 끝났을 때뿐이다. 그 밖에는 `null` 이라서 desk 핫스팟이 빈 자리에 뜨지 않는다.
- 라벨 정지 팝오버(스파인 없는 섹션)는 스파인과 같은 `#spine` 요소를 쓰고 판만 `labelPanel(s)` 이다. 핫스팟은 없다(PanelSlot 이 spineOpen 일 때만 그리므로). Esc·바깥 pointerdown·160px 이상 스크롤로 닫힌다. 걸 판이 없으면(hour1·evening) 라벨 버튼이 `aria-disabled` 가 된다.
- 미리 받기(load + idle 뒤): 라벨 6장(≈22KB, 모든 모드)이 먼저다. desk 에서는 섹션이 바뀔 때마다 `menubar-stage/prefetchPlan.ts` 표대로 받는다. 히어로에서는 popover-on·popover-working·틱 띠를 받는다.
- 내비 활성 링크: 기능 = team·poke·message·games·character·records, 아이폰 = iphone, 설치 = install, 자주 묻는 것 = faq. 히어로·S2·안심·클로징은 어느 링크에도 속하지 않는다.
