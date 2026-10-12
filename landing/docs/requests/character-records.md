> 거부된 v1 섹션 요청(2026-10-12 15:50 폐기). 기록으로만 남는다 — v2 요청은 `docs/v2/requests/`, 정본은 `docs/v2/`.

# character-records — 요청·계약 메모

작성: character-records, 2026-10-12. 대상: `components/sections/CharacterRecords.tsx` + `components/sections/character-records/**`
(`GrassLight.tsx` · `grass-geometry.ts` · `grass-data.ts` · `TodoButton.tsx` · `TokenPanel.tsx` · `TouchSegmented.tsx`).
공용 파일은 하나도 고치지 않았다. 아래 1·2 는 공용 쪽 수정 제안이고, 그동안은 내 폴더 안 우회로 끝냈다(둘 다 우회가 들어 있다).

## 1. PanelSlot — desk 에서 박자 핫스팟(◀▷)까지 Tab 만으로 가는 길 (primitives-a / integration) · 로컬 우회 있음
- **무엇**: `components/ui/PanelSlot.tsx` 의 desk 분기. `beat` 를 준 슬롯은 `activeBeat !== beat` 이면 fixed 층이 `inert` + `visibility:hidden` 이라
  포커스가 닿지 않는다. 그래서 desk 에서 키보드만 쓰는 사람이 `#records` 의 세그먼트(근무 | AI 토큰)에서 Tab 을 누르면, 박자 `records:tokens` 가
  아직 중앙 띠에 오지 않았을 때 ◀(tokenPrev) 를 건너뛰고 다음 절로 간다. (키보드로 스크롤해 박자를 중앙에 둔 뒤 Tab 하면 닿는다 — DOM 순서상
  세그먼트 다음이 박자 안 핫스팟이다. 스크롤 없이 Tab 만으로 가는 길은 아래 로컬 우회가 메운다.)
- **왜**: 박자 안에는 SPEC 카피상 포커스 가능한 글 요소가 없다(H3·본문·작은 줄뿐). 글 열에 가짜 포커스 대상을 두면 빈 탭 정지가 생기므로, 우회는 핫스팟 자리에 두고 곧바로 진짜 핫스팟으로 넘긴다(아래). 근본 해결은 PanelSlot 쪽이 맞다.
- **제안**: `beat` 가 문자열인 슬롯은 "섹션 활성 ∧ spineOpen ∧ activeBeat≠beat" 동안에도 그 박자 판(`panelFor(section, beat, s)`)의 핫스팟을
  **포커스 가능·보이지 않게**(`opacity:0` + `pointer-events:none`, inert·visibility 없이) 둔다. Tab 이 닿으면 DOM 조상인 `Beat` 의 onFocus 가
  `setActiveBeat(beat)` → 스파인이 그 판으로 바뀌고 핫스팟이 보인다. 대략:
  ```diff
  -  const deskPanel = useDemo((s) =>
  -    mode === "desk" && s.activeSection === section && (beat === undefined || beat === s.activeBeat) && spineOpen(s, mode)
  -      ? panelFor(section, s.activeBeat, s) : null);
  +  const deskPanel = useDemo((s) => {
  +    if (mode !== "desk" || s.activeSection !== section || !spineOpen(s, mode)) return null;
  +    if (beat === undefined || beat === s.activeBeat) return panelFor(section, s.activeBeat, s);
  +    return null;
  +  });
  +  // 박자 밖에서 미리 포커스만 받는 판(보이지 않음)
  +  const peekPanel = useDemo((s) =>
  +    mode === "desk" && typeof beat === "string" && s.activeSection === section && s.activeBeat !== beat && spineOpen(s, mode)
  +      ? panelFor(section, beat, s) : null);
  +  // deskVisible 이 거짓이고 peekPanel 이 있으면: inert 를 빼고, 층 visibility 는 visible, 핫스팟마다 style={{ opacity: 0, pointerEvents: "none" }}
  ```
- **로컬 우회(지금 들어 있음)**: `character-records/TokenPanel.tsx` 의 "desk 키보드 다리". `#records` 활성 ∧ 스파인 열림 ∧ 박자 밖일 때
  스파인 사각형(`spine.rect`) 위 ◀(지난달 판이면 ▷) 자리에 보이지 않는 `<button>`(`[data-token-bridge]` 안, pointer-events 없음, 같은 접근 이름)을 하나 둔다.
  Tab 이 닿으면 조상 `Beat` 의 onFocus → `setActiveBeat('records:tokens')` → 스파인이 토큰 판으로 바뀌고 다리는 사라지며, 다음 프레임에 PanelSlot 의 진짜 핫스팟으로 포커스를 넘긴다.
  위 제안이 PanelSlot 에 들어가면 다리(`bridgeRect` 이하)는 지우면 된다.
- 그 밖에 섹션 쪽 준비: `TokenPanel` 이 PanelSlot 을 `Beat` 안에 두고, ◀/▷ 로 판이 바뀌어 누른 핫스팟이 사라지면 맞은편 핫스팟으로 포커스를 옮긴다.

## 2. Segmented — 터치 히트 44 (primitives-a / integration) · 로컬 우회 있음
- **무엇**: `components/ui/Segmented.tsx` 의 칸 버튼이 `h-9`(36px)라 SPEC §7 "터치 히트 최소 44×44" 에 못 미친다(트랙 전체 42px).
- **우회**: `character-records/TouchSegmented.tsx` 가 `pointer-coarse:[&_[role=radio]]:h-11` 를 className 으로 얹는다(손가락일 때만 44px, 마우스는 그대로).
  Tailwind 출력 확인: `@media (pointer: coarse) { .pointer-coarse\:\[\&_\[role\=radio\]\]\:h-11 [role=radio] { height: calc(var(--spacing) * 11) } }`.
- **제안 diff**(공용에서 고치면 모든 세그먼트(#team·#games·#records)가 같은 높이가 된다 — 그 뒤 내 래퍼는 지우고 `Segmented` 를 바로 쓰면 된다):
  ```diff
  -              "t-button-s relative h-9 whitespace-nowrap rounded-[var(--r-seg-in)] px-4 transition-colors duration-[var(--t-quick)] ease-linear",
  +              "t-button-s relative h-9 pointer-coarse:h-11 whitespace-nowrap rounded-[var(--r-seg-in)] px-4 transition-colors duration-[var(--t-quick)] ease-linear",
  ```

## 3. 통합 테스트(§7.2-7 · 8)용 DOM 손잡이
- 확대 잔디: 바깥 `[data-grass-light]`(윗변 = 점등 기준선을 재는 요소) > `[role=img]` 창 > 판 층 `[data-grass-layer="work"|"token"]`(보이는 판은 `data-active`, opacity 1, z 2).
- 칸: `[data-grass-cell="col,row"]`, 켜진 칸은 `data-on` 속성(불투명 목표 1). 판마다 89개(future 2칸 `12,5`·`12,6` 은 만들지 않는다).
  칸 div 는 판이 화면 위아래 한 화면 안에 들어온 뒤에만 생긴다(IO `rootMargin: 100% 0px`). 감속 모션이면 칸 div 0개, final 판 `<img>` 한 장만 보인다(CSS `motion-reduce:`).
  → "85% → 35% 로 스크롤하는 동안 불투명 1 칸 수가 단조 증가"는 보이는 판 층(`[data-grass-layer][data-active]`) 안의 `[data-grass-cell][data-on]` 수로 세면 된다
  (computed opacity 로 세면 칸마다 160ms 선형 + 40ms 간격 전이 중간값이 섞인다 — 전이 끝을 기다리거나 data-on 을 쓸 것).
- 툴팁: `[data-grass-tip]`(aria-hidden). 마우스·펜 포인터만, 켜진 칸 위에서만 생긴다.
- 박자: `[data-beat="records:tokens"]`. desk 에서 이 상자는 섹션 아래 여백(96px)까지 늘어나 있다(`desk:-mb-24 desk:pb-24`) — 박자를 벗어난 뒤
  다음 절이 활성이 되기 전까지 스파인이 insights 로 잠깐 되돌아가는 틈을 없앴다.
- ◀▷ 접근 이름: "지난달 순위 보기"(token-month 판의 tokenPrev) · "이번 달 순위 보기"(token-last 판의 tokenNext).

## 4. stage-corner 와의 약속(정보)
- S7 버튼은 `demo.toggleTodo(force)` 로 **열기/닫기를 지정**한다. 누르기 시작한 순간(pointerdown, 캡처 단계)의 `todoOpen` 을 기억했다가 그 반대로 보낸다 —
  보드의 '바깥 클릭 닫기'가 같은 누름에서 먼저 닫아도 버튼이 다시 열지 않는다. 키보드(Enter·Space)는 지금 상태 기준.
- 버튼은 `aria-expanded={todoOpen}` · `aria-controls="todo-board"` 다. 보드 쪽은 `id="todo-board"` 와 "Esc 로 닫으면 연 컨트롤로 포커스 복귀"를 지켜 주면 된다
  (버튼으로 열었으면 그 버튼이 연 컨트롤이다. 사파리는 클릭으로 버튼에 포커스를 주지 않으니, 열 때 `document.activeElement` 가 body 일 수 있다).
- 근무 중이 아닐 때(드문 경우) 버튼을 누르면 `#character` 를 먼저 활성으로 만들어(한낮 장면 → 조용히 근무 중) 보드가 열리게 한다.

## 5. SPEC 과 다르게(또는 SPEC 에 없던 것을) 정한 것 — 통합 판단 요청
- **툴팁 테두리**: SPEC S8 툴팁은 `--surface-2` 바탕인데, 잔디 판 그림 바탕이 실측 `#2B2D3D`(≈ surface-2 `#2B2E3D`)라 툴팁 상자가 판에 녹아 글자만 떠 보인다.
  그래서 1px `--line-strong` 테두리를 더했다(그림자 없음). 빼려면 `GrassLight.tsx` 의 `border border-line-strong` 두 낱말만 지우면 된다.
- **창 크기**: 근무 판 그림 비율 그대로 456×257.5(desk). 토큰 판 그림은 912×519 라 위쪽 정렬로 겹치고 아래 2px(바탕 여백)이 잘린다 — 판을 바꿔도 창 높이가 변하지 않아 레이아웃 이동 0.
  창 바탕은 `var(--surface-2)`(판 바탕과 같은 값 — 모서리·교차 중에 다른 색이 비치지 않게).
- **phone 잔디 폭**: SPEC "폭 100%" 에 상한 456px 을 걸었다(390 폭에서는 350px = 100%, 배율 ≈1.15 그대로. 744 폭(iPad mini 세로, phone 모드)에서 @3x 판이 2배 넘게 늘어나 흐려지는 것을 막는다).
- **툴팁 문구**: 요일 + "요일, " + `valueText`. 0칸은 렌더 데이터 그대로 "토요일, 근무 없음" / "토요일, 사용 없음".
- **감속 모션에서도 툴팁**: 모든 칸이 켜진 final 한 장이라 호버 툴팁은 그대로 동작한다(칸 div 없이 좌표로 판정).
