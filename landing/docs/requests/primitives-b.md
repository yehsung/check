> 거부된 v1 섹션 요청(2026-10-12 15:50 폐기). 기록으로만 남는다 — v2 요청은 `docs/v2/requests/`, 정본은 `docs/v2/`.

# primitives-b — 요청·공지

다른 에이전트 파일을 고쳐 달라는 요청은 없다. 아래는 PLAN 서명과 다른 점과, 통합·섹션이 알아야 할 계약 메모다.

## 1. `sequenceMeta(name)` 은 `SequenceMeta | null` 을 돌려준다(PLAN §3.5 는 `SequenceMeta`)
- **무엇**: `components/SpritePlayer.tsx` 의 `sequenceMeta` 반환형에 `| null` 이 붙어 있다.
- **왜**: DECISIONS §4 — `sequences.json` 이 스텁(`{}`)이거나 모양이 틀려도 빌드가 깨지면 안 된다. 가짜 메타를 지어내는 대신 null + 개발 모드 경고 1회.
- **쓰는 쪽(stage-corner 의 울트라 배치 등)**: `const m = sequenceMeta('aing-ultra'); if (!m || m.kind !== 'video') …` 처럼 null·kind 를 확인한다. diff 불필요(내 파일 안에서 끝).

## 2. 계약 메모(섹션 에이전트용 — 파일 머리 주석과 같은 내용)
- `TickStrip` 은 스스로 `position:absolute` 로 판 왼쪽 위 기준 `HOTSPOTS.tick`(pt) × scale 에 선다. RenderStack 은 이미 그렇게 쓰고 있다(확인함).
- `CharacterStage`
  - `entering='commute'` = 페이드 없이 바로 보임(포스터 → 반응). commute_start 영상 자체는 `reaction` prop(스토어 `corner.reaction`)이 싣고 온다. `'fade'` = 120ms 선형 페이드인.
  - `leaving` = commute_end 가 돌고 있으면 그것이 끝난 뒤, 아니면 바로 150ms 페이드. commute_end 는 `leaving` 과 무관하게 끝나면 마지막 프레임을 둔 채 페이드 → `onReactionEnd`(부모가 언마운트).
  - 반응 영상이 600ms 안에 준비되지 않으면 건너뛰고 `onReactionEnd` 를 바로 부른다(SPEC S1 성능). posterOnly 면 반응 길이만큼 기다렸다가 부른다.
  - 말풍선 타이머는 무대가 건다: 앱 지속 시간 뒤 160ms 퇴장 → `onBubbleEnd`. 버튼이 되는 말풍선은 `message-gureum`(이름 "구름빵 메시지 열기")뿐.
  - 추가 선택 prop `bodyExpanded?: boolean` → 몸통 버튼에 `aria-expanded` + `aria-controls="todo-board"`.
  - `corner.hidden` 은 보지 않는다(코너의 일). 부모 `style.transition` 은 바깥 상자에만 걸리고, 페이드는 안쪽 상자에서 따로 돈다.
- `Bubble` 크기 = `canvasPx × 0.5 × scale`. 코너 배율(124.6/654)이면 앱 pt 크기. 울트라 말풍선을 239px 폭으로 그리려면 `scale = 239 / (canvasPx[0] × 0.5)`, 또는 `bubbleSize(id, 1)` 로 구해 나눈다. 추가 선택 prop `ariaLabel`·`className`·`style`.
- `AingStageInline` 은 조건이 안 맞으면 `null` — 자리를 비워 둬야 하면(S2·S7·S13 처럼 흐름 안) 섹션이 크기 있는 상자로 감싼다.

## 3. 환경(통합 에이전트용)
- DECISIONS §3 은 Playwright 의 webkit·firefox 가 깔려 있다고 적었지만, 2026-10-12 09:20 기준 `~/Library/Caches/ms-playwright/` 에는 chromium 계열만 있다(`webkit-2287` 없음). 사파리 `.mov`(HEVC 알파) 실재생 검수를 하려면 `npx playwright install webkit` 이 필요하다(사용자 판단).
