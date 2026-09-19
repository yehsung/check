@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 AI 오목(1.0.1 — SPEC w20 갈래 B §6). 규칙·판·서버 차단은 코어(맥 0.3.32 와 한 벌, V0332 가 지킨다) — 여기서 지키는 것은
// 폰이 더한 것뿐이다:
//  ① 입구 → 색 선택 → 대국 시작(로비에서만 · 1:1 판·보낸 신청이 있으면 닫힘)
//  ② 사람이 두면 AI 가 답한다 — 엔진은 메인 스레드 밖에서 돌고, 도는 동안 메인 액터가 멈추지 않는다
//  ③ AI 판은 서버에 한 번도 닿지 않는다(두는 동안 요청 0건 · 수명 사건을 지나도 대국 RPC · AI 판 id 0건)
//  ④ 화면을 떠나거나 background 로 가면 탐색을 취소하고(덜 생각한 수는 버린다) 돌아오면 다시 생각한다
//  ⑤ 결과 뒤 [같은 색으로 다시 두기]
//  ⑥ 사람 대국 화면의 기존 동작은 한 걸음도 안 바뀐다(화면 표 글자 · 선택기 무호출 · 서버 착수 · 화면 꺼짐 방지)
// 스토어 시험은 **결정적 가짜 엔진**(`GamesAIEngineProbe`)을 폰 선택기에 끼운다 — 선택기(취소·재시도·메인 밖)는 진짜로 돈다.

// MARK: - 도우미

private func pt(_ notation: String) -> GomokuPoint { GomokuPoint(notation: notation)! }

/// 서버로 나가면 안 되는 대국 RPC(맥 V0332 와 같은 목록).
private let matchRPCs: Set<String> = [
    "gomoku_state", "gomoku_move", "gomoku_resign", "gomoku_leave", "gomoku_chat_send", "gomoku_chat_mute",
    "gomoku_challenge", "gomoku_respond", "gomoku_cancel"
]

/// 천원에서 가장 가까운 합법 수(행 → 열 순서로 동점 해소 — 맥 V0332 `nearestChooser` 와 같은 규칙).
private func nearest(_ board: GomokuBoard, _ color: GomokuColor) -> GomokuPoint? {
    let center = GomokuBoard.size / 2
    return GomokuAIGame.legalPoints(on: board, color: color).min { a, b in
        let da = abs(a.x - center) + abs(a.y - center), db = abs(b.x - center) + abs(b.y - center)
        return da != db ? da < db : (a.y, a.x) < (b.y, b.x)
    }
}

/// 결정적 가짜 엔진의 조종판(엔진은 분리된 작업에서 불리므로 잠금으로 지킨다).
final class GamesAIEngineProbe: @unchecked Sendable {
    enum Mode: Sendable {
        /// 천원에서 가까운 합법 수를 곧바로.
        case nearest
        /// 1열 가장자리(A1·A3·…)의 빈칸 — 막지 않는 상대(5목 결과를 빨리 세운다).
        case edge
        /// 취소 문이 열릴 때까지 돈다. 취소되면 **덜 생각한 수**(A1)를 낸다 — 그 돌이 판에 놓이면 버리지 않은 것이다.
        case spinUntilCancelled
    }

    private let lock = NSLock()
    private var mode: Mode
    private var entered = 0
    private var cancelled = 0
    private var returned = 0
    private var onMain = 0

    init(_ mode: Mode) { self.mode = mode }

    func set(_ mode: Mode) { lock.withLock { self.mode = mode } }
    var enteredCount: Int { lock.withLock { entered } }
    var cancelledCount: Int { lock.withLock { cancelled } }
    var returnedCount: Int { lock.withLock { returned } }
    /// 메인 스레드에서 불린 횟수(0 이어야 한다).
    var mainThreadCalls: Int { lock.withLock { onMain } }

    private var current: Mode { lock.withLock { mode } }

    var engine: GamesGomokuAIThinker.Engine {
        { [self] board, color, _, isCancelled in
            lock.withLock {
                entered += 1
                if Thread.isMainThread { onMain += 1 }
            }
            defer { lock.withLock { returned += 1 } }
            while true {
                switch current {
                case .nearest:
                    return nearest(board, color)
                case .edge:
                    let edges = ["A1", "A3", "A5", "A7", "A9", "A11", "A13", "A15", "C1", "C15"].map(pt)
                    return edges.first { board[$0] == nil }
                case .spinUntilCancelled:
                    if isCancelled() {
                        lock.withLock { cancelled += 1 }
                        return pt("A1")
                    }
                    usleep(1_000)
                }
            }
        }
    }
}

/// 로그인 → 오목 화면 표시(로비·받은함 도착)까지 세운 하네스 + 가짜 엔진. AI 최소 표시 0 · 대리 착수 첫 칸.
@MainActor
private func aiHarness(_ label: String, mode: GamesAIEngineProbe.Mode?) async -> (GamesHarness, GamesAIEngineProbe) {
    let harness = GamesHarness(label: label)
    let nowMs = harness.serverNowMs
    harness.server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs))
    harness.server.setDefault("gomoku_lobby", json: GamesGomokuJSON.lobby(nowMs: nowMs))
    await harness.signIn()
    let probe = GamesAIEngineProbe(mode ?? .nearest)
    if mode != nil { harness.games.aiThinker.engine = probe.engine }
    harness.gomoku.aiRuntime.minimumThinkSeconds = 0
    harness.gomoku.aiRuntime.randomIndex = { _ in 0 }
    harness.games.gomokuScreenDidAppear()
    _ = await baseWaitUntil { harness.gomoku.hasLoadedLobby && harness.gomoku.hasLoadedInbox }
    return (harness, probe)
}

/// 사람 차례가 오면 후보 중 첫 빈 합법 칸을 둔다(화면이 누르는 문 그대로 — `GomokuStore.place`).
@MainActor
private func placeWhenHumanTurn(_ gomoku: GomokuStore, _ candidates: [String]) async -> GomokuPoint? {
    guard await baseWaitUntil({ gomoku.isAIMatch && gomoku.match?.turn == gomoku.match?.myColor && gomoku.match?.isFinished == false }),
          let match = gomoku.match,
          let point = candidates.map(pt).first(where: { point in
              switch GomokuRules.judge(board: match.board, point: point, color: match.myColor) {
              case .legal, .win: return true
              default: return false
              }
          })
    else { return nil }
    await gomoku.place(point)
    return point
}

/// 메인 액터에서 도는 깃발(작업이 실제로 돌았는지 본다).
@MainActor
private final class GamesMainFlag {
    var raised = false
}

// MARK: - 시험

@MainActor
@Suite(.serialized) struct GamesAIMatchTests {

    // MARK: ① 입구 → 색 선택 → 대국 시작

    @Test("입구 → 색 선택 → 대국 시작: 로비에서 열리고 고른 색으로 선다 · AI 가 흑이면 곧바로 둔다 · 1:1 신청이 떠 있으면 입구가 닫힌다")
    func entryPickColorStart() async throws {
        let (harness, probe) = await aiHarness("ai-entry", mode: .nearest)
        let gomoku = harness.gomoku
        #expect(harness.games.aiThinker.isAllowed, "오목 화면이 보이고 active 인데 AI 가 생각할 수 없다")

        // 보낸 신청이 떠 있으면 닫힌다(수락되는 순간 1:1 이 AI 판을 이긴다) — 입구 카드·시트 두 칸이 같은 값을 읽는다.
        let peer = GomokuUser(id: "p-1", displayName: "구름빵", avatarURL: nil, characterID: nil, isWorking: true, isCapable: true, inMatch: false)
        gomoku.outgoing = GomokuInvite(id: "m-out", peer: peer, stake: 3, expiresAt: harness.clock.now.addingTimeInterval(50))
        #expect(!gomoku.canStartAIMatch)
        gomoku.startAIMatch(humanColor: .black)
        #expect(!gomoku.isAIMatch && gomoku.phase == .lobby, "보낸 신청이 떠 있는데 AI 판이 섰다")
        gomoku.outgoing = nil
        #expect(gomoku.phase == .lobby && gomoku.canStartAIMatch, "로비인데 AI 입구가 닫혀 있다")

        // 돌 색 시트의 [백 · 나중에 둬요] 가 부르는 문.
        gomoku.startAIMatch(humanColor: .white)
        let match = try #require(gomoku.match)
        #expect(gomoku.isAIMatch && gomoku.phase == .playing)
        #expect(match.myColor == .white && match.opponent.isGomokuAI && match.stake == 0)
        #expect(GomokuAIGame.isAIMatchID(match.id))
        #expect(GomokuPhoneMatchChrome(match: match).isAI)
        #expect(await baseWaitUntil { gomoku.match?.moveCount == 1 }, "AI 흑이 먼저 두지 않았다")
        #expect(gomoku.match?.board[pt("H8")] == .black && gomoku.match?.turn == .white)
        #expect(probe.enteredCount == 1 && harness.games.aiThinker.searchesStarted == 1)
        #expect(!gomoku.canStartAIMatch, "대국 중에 새 AI 판을 열 수 있다(입구는 로비에만)")
        await harness.tearDown()
    }

    @Test("소스 계약: 입구는 로비 카드 하나 · 시트가 고른 색으로 시작 · 두 칸 모두 코어 가드를 읽는다 · 재디자인 B 토큰만")
    func entrySourceContract() throws {
        let screen = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuScreen.swift")
        #expect(screen.contains("GamesGomokuAIEntryCard(store: gomoku, onPlay: onPlayAI)"), "로비에 AI 입구가 없다")
        #expect(screen.contains("GamesGomokuAIColorSheet(store: gomoku)"), "돌 색 시트를 띄우지 않는다")
        let entries = try IntegrationContractTests.files(containing: ["GamesGomokuAIEntryCard("], under: "Sources/CheckMobileKit")
        #expect(entries == ["Sources/CheckMobileKit/Games/GamesGomokuScreen.swift"], "AI 입구가 로비 밖에도 섰다: \(entries)")

        let views = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuAIViews.swift")
        #expect(views.contains("store.startAIMatch(humanColor: color)"), "색을 골라도 코어 문으로 시작하지 않는다")
        #expect(views.components(separatedBy: "store.canStartAIMatch").count - 1 == 2, "입구 카드·색 칸이 코어 가드를 읽지 않는다")
        #expect(views.contains("GomokuPhoneText.aiPlayBlack") && views.contains("GomokuPhoneText.aiPlayWhite"), "맥과 같은 두 선택지가 아니다")
        #expect(views.contains("SheetHeader(GomokuPhoneText.aiPromptTitle"), "시트 머리가 공용 SheetHeader 가 아니다")
        #expect(views.contains("InsetGroup {") && views.contains("GroupRow("), "입구 카드가 공용 그룹 부품이 아니다")
        #expect(!views.contains("Color("), "재디자인 B 토큰(MobileTheme) 밖의 색 리터럴")
        #expect(views.contains("typeSize.isAccessibilitySize"), "큰 글자에서 두 칸이 세로로 서지 않는다")
        #expect(views.contains("accessibilityReduceMotion"), "'생각 중' 움직임이 동작 줄이기를 모른다")

        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesStore.swift")
        #expect(store.contains("context.gomoku.aiMoveChooser = aiThinker.chooser"), "폰 선택기를 코어에 끼우지 않는다")
    }

    // MARK: ② 사람이 두면 AI 가 답한다(메인 밖)

    @Test("사람이 두면 AI 가 답한다 — 엔진은 메인 스레드 밖에서 돌고, 도는 동안 메인 액터 일이 멈추지 않는다")
    func humanMoveGetsAnAnswerOffMain() async throws {
        let (harness, probe) = await aiHarness("ai-answer", mode: .spinUntilCancelled)
        let gomoku = harness.gomoku
        gomoku.startAIMatch(humanColor: .black)
        #expect(gomoku.match?.turn == .black && !gomoku.isAIThinking)
        await gomoku.place(pt("H8"))
        #expect(gomoku.match?.moveCount == 1 && gomoku.isAIThinking)
        #expect(await baseWaitUntil { probe.enteredCount == 1 })

        // 엔진이 아직 돌고 있다(돌려준 적 없다) — 그 사이 메인 액터에 줄 선 일이 돈다.
        let flag = GamesMainFlag()
        Task { @MainActor in flag.raised = true }
        #expect(await baseWaitUntil { flag.raised }, "엔진이 도는 동안 메인 액터가 막혔다")
        gomoku.isRulesVisible = true
        gomoku.isRulesVisible = false
        #expect(probe.returnedCount == 0, "대조: 엔진이 이미 끝나 있었다(막힘을 못 본다)")
        #expect(harness.games.aiThinker.isSearching)

        probe.set(.nearest)
        #expect(await baseWaitUntil { gomoku.match?.moveCount == 2 }, "AI 가 답하지 않았다")
        let match = try #require(gomoku.match)
        #expect(match.turn == .black && !gomoku.isAIThinking && match.deadline != nil, "답한 뒤 사람 시계가 서지 않았다")
        #expect(match.lastMove.map { match.board[$0] } == .white)
        #expect(match.board[pt("A1")] == nil)
        #expect(probe.mainThreadCalls == 0, "엔진이 메인 스레드에서 돌았다")
        #expect(!harness.games.aiThinker.isSearching && harness.games.aiThinker.searchesStarted == 1)

        // 한 수 더 — 매 AI 차례에 한 번씩.
        _ = await placeWhenHumanTurn(gomoku, ["I9", "G9", "J7"])
        #expect(await baseWaitUntil { gomoku.match?.moveCount == 4 })
        #expect(probe.enteredCount == 2 && probe.mainThreadCalls == 0)
        await harness.tearDown()
    }

    @Test("진짜 엔진(폰 한도)이 폰 선택기를 지나 둔다 — 유일한 막는 자리 · 메인 밖 · 시간 한도 안")
    func realEngineThroughPhoneThinker() async throws {
        #expect(GamesGomokuAIThinker.phoneLimits.timeBudget == GomokuAISearchLimits().timeBudget, "폰 한도가 맥 기본값과 갈렸다(바꿨다면 주석 근거도)")
        #expect(GamesGomokuAIThinker.phoneLimits.timeBudget == .milliseconds(1500))
        let (harness, _) = await aiHarness("ai-real", mode: nil)
        let gomoku = harness.gomoku
        #expect(harness.games.aiThinker.limits.timeBudget == GamesGomokuAIThinker.phoneLimits.timeBudget)
        // 흑 G8·H8·I8(F8 은 백이 막음)에 사람이 J8 을 두면 K8 이 유일한 막는 자리다(맥 V0332 통합 시험과 같은 판).
        var board = GomokuBoard()
        for notation in ["G8", "H8", "I8"] { board[pt(notation)] = .black }
        for notation in ["F8", "D3"] { board[pt(notation)] = .white }
        let game = GomokuAIGame(humanColor: .black, board: board, turn: .black, now: harness.clock.now)
        gomoku.aiGame = game
        gomoku.match = game.matchState()
        gomoku.phase = .playing

        let started = ContinuousClock.now
        await gomoku.place(pt("J8"))
        #expect(gomoku.isAIThinking)
        #expect(await baseWaitUntil { gomoku.match?.moveCount == 7 }, "진짜 엔진이 폰 선택기로 두지 않았다")
        let elapsed = ContinuousClock.now - started
        let match = try #require(gomoku.match)
        #expect(match.board[pt("K8")] == .white, "유일한 막는 자리(K8)를 두지 않았다: \(match.lastMove?.notation ?? "-")")
        // 엔진은 시간으로 끊긴다 — 포화한 스위트에서도 한도의 몇 배를 넘지 않는다(한가할 때 ≤ 약 1.5초).
        #expect(elapsed < .seconds(10), "한 수에 \(elapsed) — 시간 한도가 안 걸린다")
        #expect(harness.games.aiThinker.searchesStarted == 1)
        await harness.tearDown()
    }

    // MARK: ③ 서버 0건

    @Test("AI 판은 서버에 한 번도 닿지 않는다 — 두기·AI 답·기권·다시 두기 동안 요청 0건 · 수명 사건을 지나도 대국 RPC·AI 판 id 0건")
    func aiMatchNeverTouchesServer() async throws {
        let (harness, _) = await aiHarness("ai-offline", mode: .nearest)
        let gomoku = harness.gomoku
        await harness.barrier()
        // 로비 표시가 띄운 조회(로비·받은함)가 다 닿은 뒤를 기준으로 센다.
        let before = harness.server.requests.count
        var aiIDs: Set<String> = []

        gomoku.startAIMatch(humanColor: .black)
        aiIDs.insert(try #require(gomoku.match?.id))
        for _ in 0..<3 { _ = await placeWhenHumanTurn(gomoku, ["H8", "I9", "G9", "J7", "G7"]) }
        #expect(await baseWaitUntil { gomoku.match?.moveCount == 6 })
        await gomoku.resign()
        #expect(gomoku.phase == .result && gomoku.match?.outcome == .lost && gomoku.match?.endReason == .resign)
        gomoku.restartAIMatch()
        aiIDs.insert(try #require(gomoku.match?.id))
        _ = await placeWhenHumanTurn(gomoku, ["H8"])
        #expect(await baseWaitUntil { gomoku.match?.moveCount == 2 })
        await harness.barrier()
        let during = Array(harness.server.requests.dropFirst(before))
        #expect(during.isEmpty, "AI 판을 두는 동안 서버 요청이 나갔다: \(during.map(GamesStubServer.key))")

        // 수명 사건: background → active(따라잡기) · 화면 떠남 → 돌아옴(로비·받은함 재조회) · 끝난 판에서 화면 떠남(1:1 이면 '나가기') · 로비로.
        harness.model.sceneDidEnterBackground()
        harness.model.sceneDidBecomeActive()
        harness.games.gomokuScreenDidDisappear()
        harness.games.gomokuScreenDidAppear()
        #expect(gomoku.isAIMatch, "수명 사건이 AI 판을 버렸다")
        await gomoku.resign()
        harness.games.gomokuScreenDidDisappear()
        harness.games.gomokuScreenDidAppear()
        #expect(gomoku.phase == .result && gomoku.isAIMatch)
        gomoku.backToLobby()
        #expect(gomoku.phase == .lobby && gomoku.aiGame == nil && gomoku.match == nil)
        await harness.barrier()
        await baseYield(turns: 8)
        await harness.barrier()

        let all = harness.server.requests
        let matchCalls = all.filter { matchRPCs.contains(GamesStubServer.key($0)) }
        #expect(matchCalls.isEmpty, "대국 RPC 가 나갔다: \(matchCalls.map(GamesStubServer.key))")
        let leaked = all.filter { request in
            aiIDs.contains { id in request.bodyText.contains(id) || request.path.contains(id) || request.query.contains(id) }
                || (request.rpcName?.hasPrefix("gomoku_") == true && request.bodyText.contains("\"\(GomokuAIGame.idPrefix)"))
        }
        #expect(leaked.isEmpty, "AI 판 id 가 요청에 실렸다: \(leaked.map(GamesStubServer.key))")
        #expect(gomoku.activeMatchID == nil, "AI 판 id 가 서버 진행 중 판 장부에 들어갔다")
        // 대조: 수명 사건의 로비·받은함 조회는 평소처럼 나갔다(요청 기록이 살아 있다).
        #expect(!harness.server.requests("gomoku_inbox").isEmpty && !harness.server.requests("gomoku_lobby").isEmpty)
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    // MARK: ④ 떠나면 탐색 취소

    @Test("화면을 떠나면 탐색을 취소하고(덜 생각한 수는 버린다) 돌아오면 처음부터 다시 생각한다 · background 도 같다")
    func leavingCancelsTheSearch() async throws {
        let (harness, probe) = await aiHarness("ai-leave", mode: .spinUntilCancelled)
        let gomoku = harness.gomoku
        let thinker = harness.games.aiThinker
        gomoku.startAIMatch(humanColor: .black)
        await gomoku.place(pt("H8"))
        #expect(await baseWaitUntil { probe.enteredCount == 1 })

        // 뒤로 — 오목 화면이 사라졌다.
        harness.games.gomokuScreenDidDisappear()
        #expect(!thinker.isAllowed)
        #expect(await baseWaitUntil { probe.cancelledCount == 1 && probe.returnedCount == 1 }, "화면을 떠났는데 탐색이 계속 돈다")
        #expect(await baseWaitUntil { thinker.waitingCount == 1 }, "끊긴 선택기가 돌아올 때를 기다리지 않는다")
        #expect(thinker.searchesInterrupted == 1 && !thinker.isSearching)
        await harness.barrier()
        await baseYield(turns: 8)
        #expect(gomoku.match?.moveCount == 1, "끊긴 탐색의 수가 판에 놓였다")
        #expect(gomoku.match?.board[pt("A1")] == nil, "덜 생각한 수(A1)가 판에 놓였다")
        #expect(gomoku.isAIThinking, "떠난 사이 AI 차례가 사라졌다")

        // 돌아오면 처음부터 다시.
        harness.games.gomokuScreenDidAppear()
        #expect(await baseWaitUntil { probe.enteredCount == 2 }, "돌아왔는데 다시 생각하지 않는다")
        #expect(thinker.waitingCount == 0)

        // 앱이 background 로 — 같은 규칙.
        harness.model.sceneDidEnterBackground()
        #expect(await baseWaitUntil { probe.cancelledCount == 2 }, "background 인데 탐색이 계속 돈다")
        #expect(await baseWaitUntil { thinker.waitingCount == 1 })
        harness.model.sceneDidBecomeActive()
        #expect(await baseWaitUntil { probe.enteredCount == 3 })

        probe.set(.nearest)
        #expect(await baseWaitUntil { gomoku.match?.moveCount == 2 }, "돌아온 뒤 AI 가 답하지 않았다")
        #expect(gomoku.match?.board[pt("A1")] == nil)
        #expect(gomoku.match?.turn == .black && gomoku.match?.deadline != nil)
        #expect(thinker.searchesStarted == 3 && thinker.searchesInterrupted == 2)
        #expect(probe.mainThreadCalls == 0)
        await harness.tearDown()
    }

    @Test("끊긴 뒤 판이 바뀌면(기권) 돌아와도 다시 생각하지 않는다 · 로그아웃은 붙잡힌 선택기를 풀고 대리 수를 두지 않는다")
    func staleSearchIsNotRestarted() async throws {
        let (harness, probe) = await aiHarness("ai-stale", mode: .spinUntilCancelled)
        let gomoku = harness.gomoku
        let thinker = harness.games.aiThinker
        gomoku.startAIMatch(humanColor: .black)
        await gomoku.place(pt("H8"))
        #expect(await baseWaitUntil { probe.enteredCount == 1 })
        harness.games.gomokuScreenDidDisappear()
        #expect(await baseWaitUntil { thinker.waitingCount == 1 })

        // 떠난 채로 기권(결과) → 돌아옴: 붙잡힌 호출은 풀리지만 엔진을 다시 띄우지 않는다. 코어도 대리 수를 두지 않는다.
        await gomoku.resign()
        harness.games.gomokuScreenDidAppear()
        #expect(await baseWaitUntil { thinker.waitingCount == 0 })
        await harness.barrier()
        await baseYield(turns: 8)
        #expect(probe.enteredCount == 1, "기권한 판을 다시 생각했다")
        #expect(gomoku.match?.isFinished == true && gomoku.match?.board.stoneCount == 1, "끝난 판에 AI 수가 놓였다")

        // 새 판(AI 흑) → 생각 중에 떠남 → 로그아웃: 코어가 작업을 취소하면 붙잡힌 호출이 곧바로 풀린다.
        gomoku.restartAIMatch()
        gomoku.backToLobby()   // 진행 중이면 아무것도 안 한다(대조)
        #expect(gomoku.isAIMatch)
        await gomoku.resign()
        gomoku.backToLobby()
        gomoku.startAIMatch(humanColor: .white)
        #expect(await baseWaitUntil { probe.enteredCount == 2 })
        harness.games.gomokuScreenDidDisappear()
        #expect(await baseWaitUntil { thinker.waitingCount == 1 })
        await harness.model.session.signOut()
        #expect(await baseWaitUntil { thinker.waitingCount == 0 }, "로그아웃했는데 선택기가 붙잡혀 있다")
        #expect(gomoku.aiGame == nil && gomoku.match == nil)
        #expect(!thinker.isAllowed)
        await baseYield(turns: 8)
        #expect(probe.enteredCount == 2)
        await harness.tearDown()
    }

    // MARK: ⑤ 결과 뒤 다시 두기

    @Test("결과 뒤 [같은 색으로 다시 두기]: 같은 색의 새 로컬 판 — 5목 승 · 루비 줄·서랍 없음 · 서버 신청 없음 · 로비로 가면 입구가 다시 열린다")
    func rematchAfterResult() async throws {
        let (harness, _) = await aiHarness("ai-rematch", mode: .edge)
        let gomoku = harness.gomoku
        gomoku.startAIMatch(humanColor: .black)
        for notation in ["H8", "I8", "J8", "K8", "L8"] { _ = await placeWhenHumanTurn(gomoku, [notation]) }
        #expect(await baseWaitUntil { gomoku.phase == .result })
        let finished = try #require(gomoku.match)
        #expect(finished.outcome == .won && finished.endReason == .five)
        let chrome = GomokuPhoneMatchChrome(match: finished)
        #expect(chrome.isAI && !chrome.showsStake && !chrome.showsChatDrawer)
        #expect(chrome.endReason(finished.endReason, outcome: finished.outcome) == "5목을 완성했어요")
        #expect(chrome.opponentLine(name: finished.opponent.displayName) == "상대 · AI")
        #expect(chrome.rematchTitle == "같은 색으로 다시 두기")

        // 결과 화면 [같은 색으로 다시 두기] 가 부르는 문.
        gomoku.restartAIMatch()
        let next = try #require(gomoku.match)
        #expect(gomoku.phase == .playing && gomoku.isAIMatch)
        #expect(next.id != finished.id && next.myColor == .black && next.moveCount == 0 && next.turn == .black)
        await harness.barrier()
        #expect(harness.server.requests("gomoku_challenge").isEmpty, "AI 판의 다시 두기가 서버 신청이 됐다")

        await gomoku.resign()
        gomoku.backToLobby()
        #expect(gomoku.phase == .lobby && gomoku.aiGame == nil && gomoku.canStartAIMatch)
        await harness.tearDown()
    }

    @Test("소스 계약: 결과·대국 화면이 AI 판에서 판돈 줄·서랍을 세우지 않고, [다시 두기]는 코어 restartAIMatch · '생각 중'은 초 링 자리")
    func matchSourceContract() throws {
        let match = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuMatch.swift")
        #expect(match.components(separatedBy: "if chrome.showsChatDrawer {").count - 1 == 2, "대국·결과 두 서랍이 판 종류를 보지 않는다")
        #expect(match.components(separatedBy: "GamesAIMatchLine()").count - 1 == 2, "대국·결과 내비 부제가 판 종류를 보지 않는다")
        #expect(match.components(separatedBy: "if chrome.showsStake { GamesRubyDelta(delta: delta) }").count - 1 == 2, "AI 결과에 루비 변화가 선다")
        #expect(match.contains("gomoku.restartAIMatch()"), "AI 결과의 다시 두기가 코어 문이 아니다")
        #expect(match.contains("GamesGomokuAIThinkingMark()"), "AI 차례에 '생각 중' 표시가 없다")
        #expect(match.contains("isAI: chrome.isAI"), "상대 카드가 AI 를 모른다(캐릭터·말풍선·초 링이 선다)")
        #expect(match.contains("Label(chrome.clockLine"), "AI 판에서 '앱을 나가도 차례 시간은 흘러요'가 선다")
        #expect(match.contains("title: chrome.resignConfirmTitle"), "AI 판 기권 확인이 '건 루비를 잃어요'라고 말한다")
    }

    // MARK: ⑥ 사람 판은 그대로

    @Test("사람 판 화면 표는 그대로다 — 판돈·서랍·기권 문구·시계 줄·다시 신청·상대 부제·결과 이유가 w15 글자 그대로")
    func humanChromeIsUnchanged() {
        let human = GomokuPhoneMatchChrome(isAI: false)
        #expect(human.showsStake && human.showsChatDrawer)
        #expect(human.resignConfirmTitle == "기권하면 건 루비를 잃어요")
        #expect(human.resignConfirmMessage == "지금 기권하면 이 판은 상대가 이겨요.")
        #expect(human.clockLine == "앱을 나가도 차례 시간은 흘러요")
        #expect(human.rematchTitle == "같은 판돈으로 다시 신청")
        #expect(human.waitingLine(myColor: .black) == "흑 · 상대 차례예요")
        #expect(human.opponentSubtitle(color: .white, isWorking: true) == "백 · 근무 중")
        #expect(human.opponentSubtitle(color: .black, isWorking: false) == "흑 · 근무 안 함")
        #expect(human.endReason(.timeout, outcome: .won) == "상대의 시간이 다 됐어요")
        #expect(human.endReason(.boardFull, outcome: .draw) == "판이 가득 찼어요 · 건 루비는 돌려받아요")
        #expect(human.endReason(.five, outcome: .lost) == "상대가 5목을 완성했어요")
        #expect(human.opponentLine(name: "구름빵") == "상대 · 구름빵")

        // 판 종류는 코어 서버 차단과 **같은 판정**(id 머리말) — 서버 판 id(uuid)는 사람 판이다.
        let server = GomokuAIGame(id: "3f2a8c1e-0000-4000-8000-000000000001", humanColor: .black, now: MobileClock.demoInstant).matchState()
        #expect(!GomokuPhoneMatchChrome(match: server).isAI)
        let ai = GomokuPhoneMatchChrome(match: GomokuAIGame(humanColor: .black, now: MobileClock.demoInstant).matchState())
        #expect(ai.isAI && !ai.showsStake && !ai.showsChatDrawer)
        #expect(ai.resignConfirmTitle == "기권하면 이 판은 AI가 이겨요" && ai.resignConfirmMessage == "루비·전적·순위에 남지 않아요")
        #expect(ai.clockLine == GomokuPhoneText.aiClockPauses && ai.clockLine != human.clockLine)
        #expect(ai.waitingLine(myColor: .black) == "흑 · AI가 생각 중이에요")
        #expect(ai.opponentSubtitle(color: .white, isWorking: true) == "백")
        #expect(ai.endReason(.boardFull, outcome: .draw) == "판이 가득 찼어요", "AI 판 결과가 루비를 말한다")
    }

    @Test("사람 판 동작은 한 걸음도 안 바뀐다 — 선택기 무호출 · 착수는 서버로 · 화면을 떠나도 화면 꺼짐 방지 유지(AI 판은 떠나면 푼다)")
    func humanMatchBehaviorIsUnchanged() async throws {
        let (harness, probe) = await aiHarness("ai-human", mode: .nearest)
        let gomoku = harness.gomoku
        let nowMs = harness.serverNowMs
        let matchID = "m-human-1"
        harness.server.setDefault("gomoku_move") { _ in
            .json(#"{"status":"ok","state":\#(GamesGomokuJSON.state(nowMs: nowMs, matchID: matchID, turn: "white", moves: [("black", "H8")]))}"#)
        }
        harness.server.setDefault("gomoku_state") { _ in
            .json(GamesGomokuJSON.state(nowMs: nowMs, matchID: matchID, turn: "white", moves: [("black", "H8")]))
        }
        let opening = try JSONDecoder.gamesSnake.decode(GomokuStateResponse.self, from: Data(
            GamesGomokuJSON.state(nowMs: nowMs, matchID: matchID, moves: []).utf8))
        gomoku.applyState(opening.state)
        #expect(gomoku.phase == .playing && !gomoku.isAIMatch && gomoku.match?.turn == .black)
        #expect(!GomokuPhoneMatchChrome(match: try #require(gomoku.match)).isAI)

        await gomoku.place(pt("H8"))
        #expect(await baseWaitUntil { harness.server.requests("gomoku_move").count == 1 }, "사람 판 착수가 서버로 가지 않았다")
        #expect(await baseWaitUntil { gomoku.match?.turn == .white })
        await harness.barrier()
        await baseYield(turns: 8)
        #expect(probe.enteredCount == 0 && harness.games.aiThinker.searchesStarted == 0, "사람 판에서 AI 선택기가 불렸다")
        #expect(!gomoku.isAIThinking && gomoku.match?.moveCount == 1)

        // 화면 꺼짐 방지: 사람 판은 화면을 떠나도 판이 도는 동안 유지(w15 규칙 그대로).
        #expect(harness.games.wantsIdleTimerDisabled)
        harness.games.gomokuScreenDidDisappear()
        #expect(harness.games.wantsIdleTimerDisabled, "사람 판인데 화면을 떠나니 화면 꺼짐 방지가 풀렸다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("AI 판의 화면 꺼짐 방지는 오목 화면이 보일 때만 — 떠나면 풀고(시계도 AI 도 멈춘다) 돌아오면 다시 · 끝나면 푼다")
    func aiIdleTimerFollowsTheScreen() async {
        let (harness, _) = await aiHarness("ai-idle", mode: .nearest)
        let gomoku = harness.gomoku
        gomoku.startAIMatch(humanColor: .black)
        #expect(harness.games.wantsIdleTimerDisabled)
        harness.games.gomokuScreenDidDisappear()
        #expect(!harness.games.wantsIdleTimerDisabled, "AI 판인데 화면 밖에서 화면 꺼짐 방지를 쥐고 있다")
        #expect(gomoku.match?.deadline == nil, "떠났는데 사람 시계가 돈다")
        harness.games.gomokuScreenDidAppear()
        #expect(harness.games.wantsIdleTimerDisabled)
        #expect(gomoku.match?.deadline != nil, "돌아왔는데 사람 시계가 멈춰 있다")
        await gomoku.resign()
        #expect(!harness.games.wantsIdleTimerDisabled)
        await harness.tearDown()
    }

    // MARK: 데모 라우트

    @Test("데모 라우트 games/gomoku/ai…: 딥링크가 아니라 데모 표기 · 오목 로비로 열리고 · 결과·생각 중 장면을 세운다 · 대국 RPC 0")
    func demoRouteBuildsAIScenes() async {
        #expect(MobileDemoGomokuAI.scene(route: "games/gomoku/ai") == .playing(.black))
        #expect(MobileDemoGomokuAI.scene(route: "games/gomoku/ai/white") == .playing(.white))
        #expect(MobileDemoGomokuAI.scene(route: "games/gomoku/ai/thinking") == .thinking)
        #expect(MobileDemoGomokuAI.scene(route: "games/gomoku/ai/result") == .result)
        #expect(MobileDemoGomokuAI.scene(route: "games/gomoku/ai/pick") == .pick)
        #expect(MobileDemoGomokuAI.scene(route: "games/gomoku/ai/nope") == nil)
        #expect(MobileDemoGomokuAI.scene(route: "games/gomoku/lobby") == nil)
        #expect(MobileDemoGomokuAI.scene(isDemo: false, arguments: ["-AingCheckDemo", "YES", "-AingCheckDemoRoute", "games/gomoku/ai"]) == nil)
        #expect(MobileDemoGomokuAI.scene(isDemo: true, arguments: ["-AingCheckDemo", "YES", "-AingCheckDemoRoute", "games/gomoku/ai/result"]) == .result)
        #expect(AingRoute(path: "games/gomoku/ai") == nil, "데모 표기가 딥링크 모양에 들어갔다")

        let index = MobileDemoFixtures.load()
        for route in ["games/gomoku/ai/result", "games/gomoku/ai/thinking"] {
            let host = BaseStub.makeHost("games-ai-demo")
            let scenario = route.replacingOccurrences(of: "/", with: "-").lowercased()
            MobileStubURLProtocol.register(host: host) { request in index.response(for: request, scenario: scenario) }
            let storage = BaseStub.makeStorage()
            let vault = InMemoryTokenVault()
            vault.write(MobileDemo.accessToken, key: AingKeychain.accessTokenKey)
            vault.write("demo-refresh-token", key: AingKeychain.refreshTokenKey)
            storage.defaults.set(MobileDemo.userID, forKey: AingSharedKeys.userID)
            let model = MobileAppModel(environment: MobileEnvironment(
                service: BaseStub.makeService(host: host), vault: vault, storage: storage, appInfo: BaseStub.appInfo,
                clock: .fixed(MobileClock.demoInstant), installationID: MobileDemo.installationID,
                realtimeTransport: nil, runsTimers: false, reloadWidgetTimelines: {}, demoRoute: route))
            model.session.clientReleaseTimeoutSeconds = 0
            model.start()
            #expect(await baseWaitUntil { model.session.isSignedIn }, "\(route)")
            model.sceneDidBecomeActive()
            #expect(await baseWaitUntil { model.router.lastOpenedRoute == .gomokuLobby }, "\(route): 오목 로비로 열리지 않았다")
            model.gomoku.aiRuntime.minimumThinkSeconds = 0
            // 진짜 엔진이 두는 앞 수는 시험에서 짧게(장면은 한도의 씨앗만 바꾼다).
            model.games.aiThinker.limits = GomokuAISearchLimits(timeBudget: .milliseconds(80), maxDepth: 64)
            model.games.gomokuScreenDidAppear()
            let scene = MobileDemoGomokuAI.scene(route: route)!
            await MobileDemoGomokuAI.play(scene, games: model.games)
            switch scene {
            case .result:
                #expect(model.gomoku.phase == .result, "\(route): 결과가 안 섰다")
                #expect(model.gomoku.match?.outcome == .won && model.gomoku.match?.endReason == .five)
                #expect(model.gomoku.isAIMatch)
            default:
                #expect(await baseWaitUntil { model.gomoku.isAIThinking && model.games.aiThinker.isSearching }, "\(route): 생각 중에 멈추지 않았다")
                #expect(model.gomoku.match.map { $0.moveCount >= 5 } == true, "\(route): 대본 수가 안 놓였다")
                model.games.gomokuScreenDidDisappear()   // 대역 엔진은 취소 문을 보고 나간다
                #expect(await baseWaitUntil { !model.games.aiThinker.isSearching })
            }
            await baseBarrier(model.context.service)
            let requests = baseRequests(host: host)
            #expect(MobileForbiddenCalls.violations(in: requests).isEmpty, "\(route)")
            #expect(requests.filter { matchRPCs.contains($0.rpcName ?? "") }.isEmpty, "\(route): 대국 RPC 가 나갔다")
            model.gomoku.reset()
            model.sceneDidEnterBackground()
            BaseStub.tearDown(host: host, storage: storage)
        }
    }
}

// 허브 오목 카드: 두던 AI 판이 사람의 1:1 신청을 가리지 않는다(2026-09-20 검증 low — 루비가 걸린 신청을 놓친다).
@Test("허브 카드: AI 판은 받은 신청을 가리지 않고, 사람 대국은 늘 먼저다")
func hubCardAIMatchDoesNotHideIncoming() {
    #expect(!GamesText.hubShowsActiveMatch(active: true, isAIMatch: true, incoming: 1), "AI 판이 받은 신청을 가렸다")
    #expect(GamesText.hubShowsActiveMatch(active: true, isAIMatch: true, incoming: 0), "받은 신청이 없으면 두던 AI 판을 말한다")
    #expect(GamesText.hubShowsActiveMatch(active: true, isAIMatch: false, incoming: 3), "사람 대국은 신청보다 먼저다(차례 시간이 흐른다)")
    #expect(!GamesText.hubShowsActiveMatch(active: false, isAIMatch: false, incoming: 2))
    let line = GamesText.gomokuLine(
        incoming: 1, hasActiveMatch: GamesText.hubShowsActiveMatch(active: true, isAIMatch: true, incoming: 1), hasOutgoing: false)
    #expect(line == "받은 신청 1건")
}
