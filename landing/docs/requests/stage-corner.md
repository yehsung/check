> 거부된 v1 섹션 요청(2026-10-12 15:50 폐기). 기록으로만 남는다 — v2 요청은 `docs/v2/requests/`, 정본은 `docs/v2/`.

# stage-corner — 요청·통합 메모

작성: stage-corner, 2026-10-12. 대상: `components/sections/AingCorner.tsx` + `components/sections/aing-corner/**`.

## 0. 공용 파일 변경 요청: 없음
CharacterStage · SpritePlayer · Bubble · Hotspot · RenderImage · store · hooks 를 서명 그대로 쓴다. 로컬 우회도 없다.

## 1. install-faq 에 판단 요청(diff 없음 — 그쪽 파일)
- **무엇**: `install-faq/InstallSection.tsx` 의 iPhone 묶음 `<div data-companion-avoid …>` 는 배지·QR·한 줄을 다 담은 큰 상자다(desk 9–12열, 높이 ≈250px).
- **왜**: SPEC 공통 C 규칙("겹친 만큼 + 12px 위로, 최대 40vh, 그래도 겹치면 0.85배")을 그대로 구현했으므로, 큰 상자가 화면 아래를 지나가는 동안 코너가 그 윗변을 따라 최대 40vh 까지 올라가다 0.85배가 된다. SPEC 이 말하는 대상은 "설치 절 버튼 줄"이다.
- **제안**: 속성을 묶음 전체 대신 배지 줄(`AppStoreBadge` 를 감싼 작은 상자)과 brew 명령 줄에만 둔다. 지금 그대로여도 동작은 깨지지 않는다(통합 단계에서 눈으로 보고 결정).

## 2. 통합 에이전트가 알아야 할 동작
- **마운트 조건**: desk·tab 에서 `work==='on' && !hidden`, 또는 숨김 중 `poked` 반응 동안, 또는 `commute_end`(퇴근·숨기기 꾸벅) 동안. 꺼지면 220ms 붙잡아 150ms 페이드 뒤 언마운트. phone 은 그리지 않는다(인라인 무대).
- **자리**: 바깥 상자 `[data-aing-corner]`(fixed, `right: 20px + safe-area`, `bottom: 16px + safe-area`, 변환 없음)를 재고, 안쪽 상자에 `translate3d(dx,dy,0) scale(k)`(오른쪽 아래 기준) 240ms ease-out. 첫 자리를 재기 전 한 프레임은 `visibility:hidden`.
  - 스파인: `spineOpen(s,'desk') && spine.rect` 이고 `rect.y + rect.h + 24 > 코너 윗변` 이면 코너 오른쪽 끝 = `rect.x − 24`(= `right: 16 + 414·s + 24`). rect 는 Spine.tsx 가 게시하는 뷰포트 좌표를 그대로 쓴다.
  - 회피: `[data-companion-avoid]` 중 화면 안 사각형과 겹치면 `코너 아랫변 − 사각형 윗변 + 12` 만큼 위로(최대 40vh, 최대 6번 반복). 그래도 스파인·회피 사각형과 겹치면 0.85배. 스크롤·리사이즈는 rAF + 120ms 쓰로틀(마지막 한 번 보장), 스파인 사각형·활성 섹션·상자 폭이 바뀌면 다음 프레임에 다시 잰다.
  - 순수 계산은 `aing-corner/placement.ts`(import 0). 1280×720 에서 스파인(414×653, 오른쪽 16, 띠 아래 6)이 열려 있으면 코너 오른쪽 끝이 화면 오른쪽에서 454px, 스파인과 겹침 0 — node 로 검산함.
- **숨기기 버튼**: `aria-label="아잉 숨기기"`, 상자 (−4,−4) 의 24px 원, 히트 32px(desk). tab 은 늘 보이고(.7) 터치일 수 있어 투명 `::before` 로 히트 44px(SPEC §7) — SPEC 공통 C 의 "히트 32px" 와 다른 점. desk 는 몸통·말풍선·버튼 위 호버(빈틈은 600ms 붙잡음) 또는 키보드 포커스일 때만 보이고, 안 보일 때는 `pointer-events:none`(뒤 클릭을 가로채지 않는다).
- **할 일 보드** `#todo-board`(role=dialog, 이름 "오늘 할 일"): desk·tab 은 보드 오른쪽 아래 = 코너 왼쪽 위 + (−8, +40), 윗변이 56px(내비 48 + 8)보다 위면 56 에 붙이고 높이가 모자라면 배율을 줄인다. phone 은 아래 시트(폭 100vw − 32, 배율 맞춤, 깔개 `--scrim-sheet`). × 핫스팟 이름은 "닫기". Esc·바깥 누름(`[aria-controls="todo-board"]` 컨트롤은 바깥으로 치지 않는다)·×·아잉 재클릭으로 닫힘.
  - 포커스: 열면 × 로. 연 컨트롤은 스토어가 바뀌는 순간(클릭 처리 안)에 잡는다. 닫을 때 포커스가 보드 안이거나 갈 곳이 없으면 연 컨트롤로, 그것을 모르면(사파리는 클릭해도 버튼에 포커스를 주지 않는다) 화면 안의 코너 몸통 → 인라인 무대 몸통 → S7 버튼 순.
  - 그림 `ui/todo-board` 는 근무가 시작되면 idle 에서 미리 받는다. 창 그림자 반지름은 `--r-window`(12) — 렌더 모서리 실측 ≈13.7pt 라 대각선 차 ≈0.7px.
- **울트라** `[data-ultra-overlay]`(role=dialog, aria-modal=false, 이름 "민트별님의 울트라 찌르기"): waiting 동안은 `visibility:hidden` + 입력 통과(영상만 받는다). canplay → `demo.ultraReady()`. 400ms 안에 준비가 안 되면 숨긴 채 재생을 걸어 받기를 재촉하고(iOS 는 preload 를 무시), 보이기 시작할 때 0프레임으로 되돌린다. 72프레임 끝(onEnded, 보험 3.2초) → 160ms 선형 퇴장. pointerdown·keydown·wheel·touchmove(캡처) → 즉시 숨김. `ultraPoster`·감속 모션·Save-Data·영상 오류 → 포스터 + 말풍선 3초. 감속 모션에서는 `<video>` 를 만들지 않는다(포스터를 받는 대로 ultraReady). 시각적으로 숨긴 "닫기" 버튼, 포커스는 옮기지 않는다.
- **motion**: `TodoBoard.tsx`·`UltraOverlay.tsx` 두 파일에서만, 둘 다 `next/dynamic(ssr:false)`. 보드는 `work!=='off'` 가 된 뒤 마운트(그때 청크 요청), 울트라 청크는 활성 섹션이 poke 가 되면 idle 에서 미리 받는다.

## 3. 브라우저에서 확인할 것(이 단계에선 dev 금지라 실행 확인 못 함)
PLAN §4.2 수용 기준 1–8 전부, 특히: 1280×720 #team 에서 스파인과 겹침 0 · 설치 절에서 위로 비킴 · 상자 모서리 클릭 통과 · 울트라 Esc 즉시 닫힘과 감속 모션 영상 요청 0 · 보드 Esc 후 포커스 복귀 · 숨김 새로고침 유지 · 숨김 중 #poke 진입 시 잠깐 나타났다 사라짐 · 사파리 HEVC 알파.
