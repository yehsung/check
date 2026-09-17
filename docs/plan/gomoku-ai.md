# 오목 AI 대국 설계 (2026-09-17)

상대가 없어도 둘 수 있게 **기기 안 AI 와 1:1 오목**을 더한다. 서버는 건드리지 않는다.

## 0. 사용자 결정 (되묻지 않는다)

| 항목 | 결정 |
|---|---|
| 루비 | **걸지 않는다** |
| 기록 | **순위·전적·기록 자체를 남기지 않는다** (서버·로컬 모두) |
| 시간 | 사람 차례 **한 수 30초**, 넘기면 **빈칸 무작위 자동 착수**(1:1 대국과 같은 규칙) |
| 난이도 | **단일** — 일부러 실수하지 않고 **항상 최선의 수** |
| 공개 엔진 | Rapfi 등은 GPL-3.0 이라 쓰지 않는다 — **Swift 로 직접 작성** |

설계자 결정(이의 있으면 뒤집는다): 흑/백은 사람이 고른다 · 연속 3회 자동 착수면 사람 패(1:1 과 같음) ·
창이 안 보이면 사람 시계를 멈춘다(기다리는 상대가 없다) · 점수가 **완전히 같은** 최선의 수끼리는 무작위로 고른다
(세기는 같고 매판 같은 기보가 되풀이되지 않는다) · 채팅 없음 · 앱을 끄면 판은 사라진다.

## 1. 규칙 (서버 1:1 과 한 벌)

- 렌주룰 15×15, 흑 선공, 흑만 3-3·4-4·장목 금지. 판정은 `GomokuRules.judge` **그대로**(두 벌 만들지 않는다).
- 5목이면 승(흑은 정확히 5, 백은 5 이상). 판이 가득 차면 무승부.
- 흑이 둘 곳이 하나도 없으면(남은 칸이 전부 금수) **자동 패스**.
- 사람 시계 30초가 0 이 되면 사람 돌을 빈칸 중 **균등 무작위**로 놓는다. 흑이면 금수를 뺀 칸에서(서버 `gomoku__pick_cell` 과 같은 규칙).
  자동 착수도 정상 수다(5목이면 이김). **연속 3회**(`GomokuStore.autoPlaceLossStreak`) 자동 착수면 사람 패 — `endReason = .abandoned`.
  사람이 직접 한 수 두면 연속 횟수 0.
- AI 차례엔 시계가 없다. 생각 시간 상한 1.5초, 화면에는 최소 0.6초 "생각 중"을 보여 준 뒤 둔다(즉답이 어색하다).
- 기권 가능(1:1 과 같은 확인·`GomokuResignGuard`).

## 2. 엔진 — `Sources/CheckCore/GomokuAI.swift` (에이전트 A 소유)

계약(main 에 스텁으로 먼저 들어가 있다 — **서명을 바꾸지 마라**):

```swift
package nonisolated struct GomokuAISearchLimits: Sendable {
    package var timeBudget: Duration      // 기본 1.5초
    package var maxDepth: Int             // 기본 넉넉히(시간이 먼저 끊는다). 테스트는 깊이로 결정적으로 돌린다.
    package var tieBreakSeed: UInt64?     // nil = 시스템 무작위. 테스트는 고정.
}
package nonisolated enum GomokuAI {
    /// toMove 가 둘 최선의 수. 둘 곳이 없으면(흑 전부 금수·판 가득) nil.
    /// isCancelled 가 true 가 되면 지금까지 찾은 최선(없으면 첫 합법 수)을 곧바로 돌려준다.
    package static func bestMove(board: GomokuBoard, toMove: GomokuColor,
                                 limits: GomokuAISearchLimits = .init(),
                                 isCancelled: @Sendable () -> Bool = { false }) -> GomokuPoint?
}
```

방식(고전 오목 엔진 — 신경망 없음):
1. **즉결 판단**(탐색 전): ① 내가 5목 → 둔다 ② 상대 4(5목 한 칸 전) → 막는다(막을 곳이 흑 금수면 그 4는 못 막는 4다)
   ③ 내 VCF(연속 4로 이기는 수순) → 첫 수 ④ 상대 VCF → 그것을 끊는 수 후보로 좁힌다 ⑤ 상대 열린 3 → 막는 수 + 내 4 로 후보를 좁힌다.
2. **탐색**: 반복 심화 네가맥스 알파베타 + 치환표(Zobrist) + 수 정렬(위협 점수·킬러). 후보는 기존 돌 반경 2 안 빈칸.
3. **평가**: 네 방향 줄 모양 점수(5·열린4·막힌4·열린3·막힌3·열린2…), 두 색 모두, 착수마다 증분 갱신.
4. **렌주**: 흑 후보는 `GomokuRules.judge` 가 legal/win 인 칸만(국면 해시로 캐시). 백은 흑의 금수 자리를 "흑이 못 막는 칸"으로 본다.
5. 빈 판에서 흑이면 천원(H8).
6. 판 내부 배열이 필요하면 `GomokuRules.swift` **끝에** package 도우미를 더해도 된다 — 기존 판정 코드·순서·노드 계수는 한 글자도 바꾸지 않는다
   (`Fixtures/renju-cases.json` 91개가 노드 수까지 못 박는다).

검증(`Tests/checkTests/V0332GomokuAIEngineTests.swift` + `Fixtures/gomoku-ai-puzzles.json`) — **깊이 제한·고정 시드로 결정적**:
- 한 수 승(흑·백) · 유일한 4 막기 · 열린 4 만들기 · 열린 3 막기 · VCF 승(내 수 ≤5) · 상대 VCF 막기 · 흑 금수로만 막을 수 있는 백 4 = 백 승 인식 · 빈 판 흑 H8.
- 흑 AI 는 절대 금수에 안 둔다: 무작위 중반 국면 200개에서 `judge ∈ {legal, win}`.
- 무작위 상대와 자가 대국 흑·백 각 10판 전승, 모든 수 합법. AI 대 AI 한 판이 합법적으로 끝난다.
- 취소: isCancelled 가 곧 true 면 200ms 안에 합법 수를 돌려준다.
- 시간: 중반 국면 5개에서 `timeBudget` + 0.5초 안에 돌아온다(디버그 빌드 기준 느슨한 상한). 릴리스 빌드 한 수 시간·도달 깊이는 스크래치 하네스로 재서 보고만.
- iOS: `xcodebuild -scheme CheckCore -destination 'generic/platform=iOS Simulator' build` 초록.

## 3. 로컬 대국 상태 — `Sources/CheckCore/GomokuAIGame.swift` (에이전트 B 소유)

순수 값 타입(시계·무작위 주입). 1장의 규칙을 전부 여기서 판정한다.
- `id = "ai-<uuid>"`, `humanColor`, 판·수 목록(자동 여부 포함)·차례·마지막 수·`autoPoints`·사람 연속 자동 횟수·끝남/결과/끝난 사유.
- `humanPlace(point, now)` → 거절 사유는 `GomokuTapRefusal`(notYourTurn/occupied/finished/forbidden+사유) 그대로.
- `applyAIMove(point?)`(nil = 흑 자동 패스) · `autoPlaceHuman(now, rng)` · `resign()` · `pause(now)`/`resume(now)`(남은 초 보존).
- `matchState() -> GomokuMatchState`: 상대 = `GomokuUser.gomokuAI`(id "ai", 이름 "AI"), stake 0, rubyDelta 0 — **기존 화면이 그대로 읽는 모양**.

## 4. 스토어 연결 — `Sources/CheckCore/GomokuStoreAI.swift` + `GomokuStore.swift` 작은 삽입 (에이전트 B)

- 저장 프로퍼티 1줄(`aiGame`)만 본문에, 나머지는 확장 파일에. `isAIMatch` = `aiGame != nil && match?.id == aiGame.id`.
- `startAIMatch(humanColor:)`: 로비에서만, 진행 중인 1:1 판이 없을 때. `match`·`phase = .playing` 을 세우고 AI 가 흑이면 바로 AI 차례를 시작.
- `place` / `resign` / `backToLobby` 는 **맨 앞에서** AI 판이면 로컬 경로로 가고 서버로 절대 안 나간다. 거절 문구·진단 줄은 기존 표(`GomokuNoticeText`) 재사용.
- AI 수는 `Task.detached` 에서 `GomokuAI.bestMove` — 판이 바뀌거나 기권·로비·로그아웃이면 취소하고 결과를 버린다(세대 번호).
  테스트가 엔진을 갈아 끼울 수 있게 선택기 주입점을 둔다(`aiMoveChooser`).
- 사람 시계: 로컬 작업이 마감에 깨어 `autoPlaceHuman`. 창 숨김·가림(`windowDidHide` / `windowOcclusionDidChange(false)`)이면 멈추고 다시 보이면 이어 간다.
- **서버와 섞이지 않게**: `refreshMatch`·폴링·실시간 따라잡기·`activeMatchID` 에 "ai-" id 가 절대 안 실린다. AI 판 중에도 받은 신청 배너는 뜨고,
  수락(`respond(accept: true)`)이나 상대가 내 신청을 받아 1:1 판이 시작되면 **AI 판을 조용히 버리고** 1:1 이 이긴다. 로그아웃(`reset`)이면 버린다.
- 주의(되돌리지 말 것): `applyState` 의 "끝난 판에 늦은 진행 중 응답 무시"(6ca184c)는 1:1 전용이다 — AI 판은 이 경로를 안 탄다.

## 5. 화면 — `Sources/check/GomokuPanel.swift` (에이전트 B)

- 로비 오른쪽 열 맨 아래 **AI 카드**: 제목 "AI와 두기", 설명 "루비·전적 없이 연습해요", 버튼 [흑으로 두기(선공)] [백으로 두기]. 1:1 판이 진행 중이면 흐림.
  위 칸("지금 대결 중")이 늘어나는 칸이라 높이 예산 안에서 줄어든다 — 기존 배치 시험처럼 창 밖으로 안 넘치는지 잰다.
- 대국: 두 열 그대로. 상대 카드는 AI(캐릭터 대신 `cpu` 기호, 말풍선 없음, 시계 대신 "생각 중" 표시). 채팅 카드 자리엔
  안내 카드("AI 대국은 루비·전적·순위에 남지 않아요"). 상태줄: AI 차례면 "AI가 생각 중이에요". [기권] 그대로.
- 결과: 결과 카드에서 루비 줄을 뺀다. 버튼 [다시 두기](같은 색) · [로비로]. 채팅 카드 자리엔 같은 안내 카드.
- 문구는 기존 문구 표(`GomokuText` / `GomokuNoticeText`)에만 더한다.

검증(`Tests/checkTests/V0332GomokuAIMatchTests.swift`):
- 대국 상태 규칙 전부(5목·가득 참·흑 패스·금수 거절·자동 착수 흑은 금수 제외·연속 3회 패·직접 두면 0·기권·일시정지 남은 초 보존).
- 스토어: AI 판 동안 서비스(가짜 호스트)로 **요청 0건**, 늦게 끝난 AI 수는 기권·로비 뒤 버려짐, 1:1 수락이 AI 판을 이김, 로그아웃이 지움.
- 화면: 로비(AI 카드)·AI 대국·AI 결과 스냅샷이 창 예산 안(기존 V0330 배치 시험 방식), 기존 1:1 화면 스냅샷 바이트 불변.
- 기존 오목 묶음(V0327·V0328·V0330·V0331) 초록, iOS CheckCore 빌드 초록.
- **폰이 같은 GomokuStore 를 쓴다**(Sources/CheckMobileKit/Games): `swift test --filter CheckMobileKitTests`(약 286개, 특히
  GamesStoreScenarioTests·GamesStoreHardeningTests) 초록 — AI 판이 아닐 때 앞머리 분기가 기존 동작을 한 줄도 안 바꾼다는 증거.
- 새 코어 파일은 맥 전용 API(AppKit·NSWorkspace 등) 금지, 선언은 `package`, 테스트가 소스를 읽으면 `CheckCoreSourceLayout`.

## 6. 진행

1. main: 이 문서 + `GomokuAI.swift` 계약 스텁(가장 가까운 합법 수를 두는 임시 몸통).
2. 병렬 에이전트 2개(격리 워크트리, 시작 시 `git merge --ff-only main`): A 엔진 / B 대국·스토어·화면. 파일 소유권이 겹치지 않는다(A 는 GomokuRules 끝 추가만).
3. 통합: main 에 병합 → 메인 저장소에서 전체 스위트 → 실제 앱으로 AI 한 판(창 하네스) → 배포(다른 세션과 버전 조율).
