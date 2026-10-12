> 거부된 v1 섹션 요청(2026-10-12 15:50 폐기). 기록으로만 남는다 — v2 요청은 `docs/v2/requests/`, 정본은 `docs/v2/`.

# team-poke 요청

작성: team-poke, 2026-10-12. 내 파일은 `components/sections/TeamPoke.tsx`, `components/sections/team-poke/**` 이다. 공용 파일은 고치지 않았다. 아래 1·2 는 지금 내 폴더 안에서 임시로 우회해 두었다. 통합 단계에서 공용 쪽을 고치면 우회 코드를 지운다.

## 1. `data/fixtures.ts` HOTSPOTS 에 '쉬는 민트별' 자리 두 개를 더해 달라 (core 소유)
- **무엇**: 민트별 찌르기 버튼이 비활성인 판의 좌표 두 개를 추가한다.
  ```diff
     pokeMint:      { panels: ['poke-list'],                                     x: 274.0, y: 314.0, w: 29.7, h: 29.7, shape: 'circle' }, // @3x (822,942)-(911,1031), 히트 44
  +  pokeMintRest:  { panels: ['poke-cooldown'],                                 x: 274.0, y: 314.0, w: 29.7, h: 29.7, shape: 'circle' }, // 쿨타임 판의 흐려진 원(같은 자리)
  +  pokeMintFocus: { panels: ['poke-focus-1', 'poke-focus-2'],                  x: 274.0, y: 339.0, w: 29.7, h: 29.7, shape: 'circle' }, // @3x (822,1017)-(911,1106), 집중 안내 한 줄(25pt)만큼 아래
  ```
- **왜**: PLAN §4.4 수용 기준 5 는 "1·2단에서 찌르기 핫스팟 `aria-disabled`" 다. 그런데 `pokeMint.panels` 가 `['poke-list']` 하나뿐이다. 그래서 PanelSlot 은 집중 1·2단과 쿨타임 판에서 그 자리를 아예 그리지 않는다. 비활성 핫스팟이 생기지 않고, 키보드로 민트별을 찌르면 그 버튼이 사라지면서 포커스도 함께 사라진다.
- **좌표 근거**: 원본 `A/v4/mac/ui/poke_focus_stage{1,2}@3x.png`·`poke_cooldown_mint@3x.png` 에서 파란 원(쿨타임은 흐린 원)의 bbox 를 PIL 로 쟀다. 집중 판은 (822,1017)-(911,1106) 이고, pt 로 (274, 339) 29.7×29.7 이다. poke-list 의 pokeMint 보다 정확히 25pt 아래이고, 이는 판 높이 차 679−654 와 같다. 쿨타임 판은 poke-list 와 차이 나는 bbox 가 (822,942)-(912,1032) 하나뿐이라 자리가 같다. [집중] 칩 자리는 네 판 모두 같다(차이 bbox 가 칩 안 글자뿐).
- **지금 우회**: `components/sections/team-poke/spots.ts` 에 `MINT_RESTING`(같은 두 좌표)이 있다. `team-poke/FocusMintSpot.tsx` 는 PanelSlot 과 같은 규칙으로 로컬 층을 하나 더 그린다(desk 는 `spine.rect` 위 fixed, tab·phone 은 PanelSlot children 안 absolute). 그 층에 `disabled` 핫스팟 "민트별 콕 찌르기"가 있다. 키보드로 찔렀을 때는 이 자리가 포커스를 넘겨받는다(`requestMintFocus`).
- **고친 뒤 할 일**: `PokePanel.tsx` 의 `HOTSPOTS` 에 다음 두 항목을 더한다. 그리고 `FocusMintInline`·`FocusMintDesk`·`spots.ts` 의 `MINT_RESTING` 을 지운다.
  ```ts
  { key: 'pokeMintRest',  label: '민트별 콕 찌르기', onActivate: () => {}, disabled: true },
  { key: 'pokeMintFocus', label: '민트별 콕 찌르기', onActivate: () => {}, disabled: true },
  ```
  포커스를 넘기는 일은 3번처럼 PanelSlot 이 맡거나, 같은 key 순서로 `autoFocus` 를 대신할 무엇이 필요하다.

## 2. `components/ui/Segmented.tsx` 칸의 히트를 44px 로 (primitives-a 소유)
- **무엇**: 칸 버튼이 `h-9`(36px)이고 트랙을 포함해도 42px 라서, SPEC §7 의 "터치 히트 최소 44×44"에 모자란다. 모양은 그대로 두고 히트만 넓히자는 제안이다.
  ```diff
  -              "t-button-s relative h-9 whitespace-nowrap rounded-[var(--r-seg-in)] px-4 transition-colors duration-[var(--t-quick)] ease-linear",
  +              "t-button-s relative h-9 whitespace-nowrap rounded-[var(--r-seg-in)] px-4 transition-colors duration-[var(--t-quick)] ease-linear before:absolute before:inset-x-0 before:-inset-y-1 before:content-['']",
  ```
- **지금 우회**: `team-poke/TeamSegment.tsx` 가 `className` 으로 `[&>button]:before:absolute [&>button]:before:inset-x-0 [&>button]:before:-inset-y-1 [&>button]:before:content-['']` 를 넘긴다. 공용이 고쳐지면 `HIT_44` 를 지운다. 다른 섹션(games·records)의 세그먼트도 같은 문제를 안고 있다.

## 3. (제안) PanelSlot: 활성화한 핫스팟이 판 교체로 사라질 때 포커스를 넘길 곳
- **무엇**: 핫스팟 onActivate 때문에 판이 바뀌고 그 핫스팟이 새 판에 없으면 `document.activeElement` 가 body 로 떨어진다(콕 찌르기 → 쿨타임, 메시지 보내기 → unread 등). PanelSlot 이 직전에 포커스를 가진 핫스팟이 사라진 것을 보면, 새 판 핫스팟 중 같은 rect 에 있는 것 또는 첫 핫스팟으로 포커스를 옮기는 방식을 제안한다.
- **왜**: 키보드·스크린 리더 사용자가 같은 자리를 잃지 않게 하려는 것이다. 콕 절은 1번 우회로 해결했다. 메시지 절의 `sendButton` 도 같은 문제를 안고 있다(message-games 몫).
- **지금 우회**: 콕 절만 `FocusMintSpot.tsx` 의 `requestMintFocus`/`takeFocus` 가 처리한다.

## 4. 통합 확인 부탁(내가 dev 를 못 띄워 실행으로 확인하지 못한 것)
- `?hotspots=1` 로 desk·390·768 에서 [집중] 칩, 민트별(목록·쿨타임·집중 1·2단), 레일 [팀 현황] 링이 렌더 위에 ±2pt 로 맞는지 본다.
- phone 390 #poke 에서 인라인 무대(110×132.9)가 창 오른쪽 아래에 걸치는지 본다(오른쪽 −8, 아래 +24). 말풍선이 오른쪽으로 넘치지 않는지도 본다(계산상 243.5–313.9px, 화면 390).
- 1024×768 desk 에서 글 열이 스파인과 48px 떨어지는지 본다(글 열 498px).
