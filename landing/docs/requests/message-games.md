> 거부된 v1 섹션 요청(2026-10-12 15:50 폐기). 기록으로만 남는다 — v2 요청은 `docs/v2/requests/`, 정본은 `docs/v2/`.

# message-games — 요청·통합 메모

작성: message-games, 2026-10-12. 대상: `components/sections/MessageGames.tsx` · `components/sections/message-games/{MessageDemo,GamesDemo}.tsx` · `model.ts`(카피·순수 상태 표) · `sizing.ts`(게임 창 크기 클래스).
공용 파일은 고치지 않았다. 아래 1·2 는 공용 쪽에서 받아 주면 내 로컬 우회를 지울 수 있는 것들이다.

## 1. `components/ui/Segmented.tsx` — 칸 터치 히트 44px (primitives-a / integration)
- **무엇**: 라디오 칸이 `h-9`(36px)라 트랙 전체가 42px, 칸 하나의 히트가 44px 에 못 미친다(SPEC §7 "터치 히트 최소 44×44").
- **왜**: S3 팀·S6 게임·S8 잔디 세그먼트가 모두 같은 프리미티브라 공용에서 한 번 고치는 게 맞다. 시각 높이는 그대로 두고 히트만 넓히면 된다.
- **지금 우회**: `GamesDemo.tsx` 의 `SEGMENT_HIT` 클래스를 Segmented `className` 으로 넘겨 `[role=radio]::before` 를 위아래 4px 넓힌다(시각 변화 0). 공용이 고쳐지면 `SEGMENT_HIT` 상수와 `className={SEGMENT_HIT}` 를 지운다.
- **제안 diff**(Segmented 라디오 버튼 className):
  ```diff
  - "t-button-s relative h-9 whitespace-nowrap rounded-[var(--r-seg-in)] px-4 transition-colors duration-[var(--t-quick)] ease-linear",
  + "t-button-s relative h-9 whitespace-nowrap rounded-[var(--r-seg-in)] px-4 transition-colors duration-[var(--t-quick)] ease-linear " +
  +   "before:absolute before:inset-x-0 before:-inset-y-1 before:content-['']",
  ```

## 2. `components/ui/MacWindowShell.tsx` — CSS 로 정하는 크기 (선택, integration)
- **무엇**: MacWindowShell 은 크기를 인라인 style(`pt × scale` px 또는 fluid aspect-ratio)로만 받는다. S6 게임 창은 모드마다 크기 규칙이 다르고(desk 700×389 · tab 폭/700 · phone 폭 100%, 오목은 0.8배·높이 상한 560), 서버가 모드를 모르므로 **CSS(container query 단위 + `phone:` 변형)** 로 정해야 SSR 첫 페인트·하이드레이션이 맞는다. 인라인 style 은 클래스를 이기므로 그대로는 못 쓴다.
- **지금 우회**: `GamesDemo.tsx` 가 같은 모양(`relative overflow-hidden rounded-[var(--r-window)]` + `box-shadow: var(--shadow-window)`)의 로컬 창 div 를 그리고, 폭·높이를 함께 200ms ease-out 으로 맞춘다(감속 모션이면 크기 전이 없음).
- **제안**: `sizing?: 'style' | 'css'` prop — `'css'` 면 dims 를 인라인으로 넣지 않고 `className` 의 크기를 따르며 전이를 `width, height` 둘 다로. 받아 주면 로컬 div 를 MacWindowShell 로 바꾼다. 받지 않아도 동작에는 문제가 없다.

## 3. 통합 단계에서 확인할 것(내가 dev·build 없이 실행으로 못 본 것)
- **#message**(spine): 진입 0.8초 뒤 `useEnterTimer('message', 800, demo.msgArrive)` → 라벨 `menubar-0345-newmsg`, 스파인 `popover-newmsg`. 왼쪽 버튼은 `[data-message-step]` 안의 하나의 `<button>` 이 none=숨김(자리 유지) → arrived "구름빵 대화 열기" → composing "보내기" → unread/read 숨김(`visibility:hidden`).
  - 숨김 상태는 접근 트리·Tab 순서에서도 빠진다. 키보드로 '열기'를 누르면 같은 버튼이 '보내기'로 바뀌어 포커스가 그대로 남는다. '보내기' 뒤에는 버튼이 숨으므로 포커스가 문서로 돌아간다(알림 영역이 "보냈어요" → "구름빵님이 읽었어요"를 읽는다).
  - 렌더 핫스팟: `railPokeMsg`("콕 / 메시지 열기", arrived 일 때만 활성) · `sendButton`("보내기", composing 일 때만 활성), 둘 다 포커스 가능. fixtures 좌표 그대로 — `?hotspots=1` 로 ±1pt 보정은 통합 몫.
  - phone 인라인 무대: PanelSlot children 으로 `right: 8px; bottom: -24px`(SPEC 공통 I). 390 폭 계산상 composing 판의 `sendButton` 44px 히트 오른쪽 아래 귀퉁이(≈5×3px)가 무대 몸통 타원 히트와 겹친다(무대가 위). 실측에서 눌림이 이상하면 무대를 `bottom: -28px` 정도로 내리면 된다.
- **#games**(plain): 창은 `[data-games-window]` 상자. 크기는 `sizing.ts` 의 클래스(100cqw = 글 열 폭). 계산 검산(node, 12개 뷰포트): desk 700×389 / 오목 504×560, 768 tab 700×389 / 504×560, 390 phone 350×194.5 / 350×388.9, 가로 넘침 0.
  - 고르기 전(`games = null`)에는 보이는 판·창 크기를 CSS 가 정한다(phone 오목, 그 밖 플래피). Segmented 는 JS 값이라 phone 에서 하이드레이션 전 HTML 에는 '플래피 아잉'이 체크돼 있다가 하이드레이션 뒤 '1:1 오목'으로 바뀐다(알약이 한 번 미끄러진다 — `/#games` 직접 진입 때만 보일 수 있음).
  - 아래 24px 페이드는 창을 감싼 상자의 `mask-image` 다. 상자는 `-mx-[var(--gutter)] px-[var(--gutter)]` 로 섹션 안쪽 상자 끝까지 넓혀 옆 그림자를 살린다 — **SectionShell 안쪽 래퍼의 좌우 패딩이 `--gutter` 라는 가정**에 기대므로, 그 패딩이 바뀌면 같이 바꿔야 가로 넘침이 안 생긴다.
  - 오목 판: `<picture>` 의 `<source media="(max-width: 767.98px)">` 로 phone 은 `gomoku-board-sm`, 그 밖은 `gomoku-board`(img src 는 늘 `gomoku-board` — `img[src*="gomoku-board"]` 단언은 둘 다 맞는다). alt 는 `ALT['gomoku-board']`(판돈 글자 없음).
  - R7(문서 길이 초과) 축소판 "S6 창 0.86배"가 필요하면 `sizing.ts` 의 700/504 상수와 클래스 문자열을 함께 바꾼다.
