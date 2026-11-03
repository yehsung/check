import Foundation
import Testing
@testable import check
@testable import CheckCore

// 가려진 대국 창에서도 '내 차례'(테트리스는 '시작') 말풍선이 뜬다 — 오목 · 체스 · 테트리스 (2026-11-03).
//
// 결함: 대국 창을 연 채 다른 앱을 전체 화면으로 쓰거나 다른 스페이스로 가면 `windowOcclusionDidChange(visible: false)` 가
// 폴링을 멈추지만 `isWindowVisible` 은 true 로 남는다. 상대 수가 초인종으로 와 `applyState` 가 내 차례를 세워도
// 말풍선 문(`noteMatchProgress` · `noteMatchStarted` 의 `guard !windowWasVisible`)이 막혀 캐릭터 말풍선이 안 운다 —
// 30초 + 유예 뒤 서버 자동 착수, 세 번 연속이면 abandoned 패로 판돈을 잃는다(테트리스는 시작을 모른 채 준비 30초가 지나간다).
// 맥 오버레이 펌프의 순수 판정(`*AttentionIsCurrent`)도 같은 `guard !isWindowVisible` 이라, 말풍선이 떠도 곧바로 거짓이 되어 걷혔다.
// 아잉 뒤집기(feat/aing-flip de10fd71 V2-01)에서 적대 검증으로 찾았고 같은 틀을 쓰는 세 게임에 남아 있었다.
//
// 갈래마다 셋이 짝이다: (a) 기준선 — 창이 안 보이면 알림이 있다 · (b) 결함 — 창이 보이는데 가려졌으면 알림이 있어야 한다 ·
// (c) 대조 — 창이 보이고 안 가려졌으면 알림이 없다(화면이 이미 말한다). (c) 가 있어야 (b) 의 초록이 "늘 운다" 로 둔갑하지 않는다.
// 시계 잎 뷰 · AI 시계 · 폴링 판정은 이 수리가 건드리지 않는다(`isWindowVisible` 그대로 — 가림 통지가 틀려도 보이는 창의 시계는 돈다).

// MARK: - 하네스

private let otMe = "00000000-0000-0000-0000-0000000000a1"
private let otRival = "00000000-0000-0000-0000-0000000000b2"
private let otGomokuMatch = "0c0c0c0c-2222-3333-4444-555555555555"
private let otTetrisMatch = "7e7e0000-0000-4000-8000-0000000000c1"

/// 체스 픽스처(실서버 응답 원문). 부른 사람은 매니페스트의 A(백)다.
private let otChessFixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/chess-rpc", isDirectory: true)
private let otChessMe = "aa000000-0000-4000-8000-0000000000a1"
private let otChessMatch = "9a7156f6-f055-4590-ba98-f537ead0a600"

private func otJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func otNowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

private func otDecode<T: Decodable>(_ type: T.Type, _ text: String) -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(T.self, from: Data(text.utf8))
}

private func otChessText(_ name: String) -> String {
    try! String(contentsOf: otChessFixtures.appendingPathComponent("\(name).json"), encoding: .utf8)
}

/// 상대 수가 오기 전 창의 모양.
private enum OTWindow: String {
    /// 창을 안 열었거나 닫았다.
    case closed
    /// 창은 열려 있는데 다른 전체 화면 앱 · 다른 스페이스에 가려졌다(가림 통지 visible:false).
    case shownOccluded
    /// 창이 보이고 앞에 있다.
    case shown
}

@MainActor
private func otApply(_ window: OTWindow, visible: (Bool) -> Void, occlusion: (Bool) -> Void) {
    switch window {
    case .closed:
        visible(false)
    case .shownOccluded:
        visible(true)
        occlusion(false)
    case .shown:
        visible(true)
    }
}

@MainActor
private enum OTRetention { static var stores: [WorkTimerStore] = [] }

/// 스텁 호스트 하나 위의 앱 스토어(오목 · 체스 · 테트리스 스토어를 함께 든다 — 장부 defaults 배선까지 실물).
@MainActor
private func otAppStore(_ label: String, userID: String, handler: @escaping GomokuStubProtocol.Handler) -> WorkTimerStore {
    let host = "ot-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: GomokuTestDefaults.make("occluded-turn"), workspaceNotifications: nil)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
    OTRetention.stores.append(store)
    return store
}

@MainActor
private func otWait(_ timeout: TimeInterval = 20, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<Int(timeout * 200) {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
private final class OTTally<Attention> {
    var attentions: [Attention] = []
}

// MARK: 오목 흉내 서버

/// 한 판 오목 서버. 나는 흑 — 처음엔 내가 한 수 두고 상대(백) 차례, `opponentMoves()` 뒤엔 상대가 둬서 내 차례.
private final class OTGomokuServer: @unchecked Sendable {
    private let lock = NSLock()
    private var moveCount = 1
    private var turn = "white"
    private var stones: [(Int, Int, Character)] = [(7, 7, "b")]

    func opponentMoves() {
        lock.lock()
        moveCount = 2
        turn = "black"
        stones = [(7, 7, "b"), (8, 7, "w")]
        lock.unlock()
    }

    func stateText() -> String {
        lock.lock()
        defer { lock.unlock() }
        var cells = Array(repeating: Character("."), count: 225)
        for (x, y, c) in stones { cells[y * 15 + x] = c }
        let now = otNowMs()
        return otJSON([
            "status": "ok",
            "match": [
                "id": otGomokuMatch, "status": "active", "stake": 5,
                "black": otMe, "white": otRival, "challenger": otMe, "opponent": otRival,
                "move_count": moveCount, "turn": turn, "deadline_ms": now + 30_000,
                "result": NSNull(), "end_reason": NSNull(), "winner": NSNull(),
                "invite_expires_ms": now, "board": String(cells)
            ] as [String: Any],
            "moves": [] as [Any],
            "my_color": "black",
            "opponent": ["user_id": otRival, "display_name": "라이벌", "avatar_url": NSNull(), "character": "aing"],
            "ruby_balance": 20,
            "server_now_ms": now
        ])
    }
}

/// 오목 한 판: 진행 중 판(상대 차례)을 들고 → 창을 `window` 로 둔 채 → 상대가 둬서 초인종 → 상태 응답이 내 차례를 세운다.
@MainActor
private func otGomokuOpponentMoves(_ label: String, window: OTWindow) async -> [GomokuAttention] {
    let server = OTGomokuServer()
    let store = otAppStore("g-\(label)", userID: otMe) { rpc, _, _ in
        switch rpc {
        case "gomoku_state": return .init(body: server.stateText())
        case "gomoku_inbox":
            return .init(body: otJSON(["status": "ok", "incoming": [] as [Any], "outgoing": NSNull(),
                                       "active_match_id": otGomokuMatch, "server_now_ms": otNowMs()]))
        case "gomoku_lobby": return .init(body: otJSON(["status": "ok", "users": [] as [Any]]))
        default: return nil
        }
    }
    let gomoku = store.gomoku
    gomoku.pollStepSeconds = 3_600
    gomoku.noteOwnsMatch(otGomokuMatch)          // 이 기기가 연 판(한 판 한 기기 장부)
    let tally = OTTally<GomokuAttention>()
    gomoku.onAttention = { tally.attentions.append($0) }
    gomoku.applyState(otDecode(GomokuStatePayload.self, server.stateText()))
    #expect(gomoku.match?.moveCount == 1 && gomoku.match?.turn == .white, "전제: 상대 차례인 판을 들고 있다")
    #expect(tally.attentions.isEmpty, "전제: 상대 차례에는 말풍선이 없다")

    otApply(window, visible: { gomoku.isWindowVisible = $0 }, occlusion: { gomoku.windowOcclusionDidChange(visible: $0) })
    if window == .shownOccluded {
        #expect(gomoku.isWindowOccluded && gomoku.isWindowVisible, "전제: 가려졌지만 창은 열려 있다")
        #expect(gomoku.pollTask == nil, "전제: 가려진 동안 폴링은 없다 — 초인종만 남는다")
    }

    server.opponentMoves()
    gomoku.handleSignal()                         // 상대가 뒀다는 초인종
    await otWait { gomoku.match?.moveCount == 2 && gomoku.syncTask == nil }
    #expect(gomoku.match?.moveCount == 2 && gomoku.match?.turn == gomoku.match?.myColor, "전제: 초인종이 내 차례를 세웠다")
    let seen = tally.attentions
    gomoku.reset()
    return seen
}

// MARK: 체스

/// 체스 한 판(나는 A · 백): 1수 뒤 상대(흑) 차례 판을 들고 → 창을 `window` 로 둔 채 → 초인종 → 상태 응답이 내 차례(ply 6)를 세운다.
@MainActor
private func otChessOpponentMoves(_ label: String, window: OTWindow) async -> [ChessAttention] {
    let myTurn = otChessText("chess_state__ok_mid_since0")       // ply 6 · 백 차례
    let store = otAppStore("c-\(label)", userID: otChessMe) { rpc, _, _ in
        switch rpc {
        case "chess_state": return .init(body: myTurn)
        default: return nil
        }
    }
    let chess = store.chess
    chess.pollStepSeconds = 3_600
    chess.noteOwnsMatch(otChessMatch)
    let tally = OTTally<ChessAttention>()
    chess.onAttention = { tally.attentions.append($0) }
    chess.applyState(otDecode(ChessStatePayload.self, otChessText("chess_move__ok_white_first")))  // ply 1 · 흑 차례
    #expect(chess.match?.plyCount == 1 && chess.match?.turn == .black && chess.match?.myColor == .white,
            "전제: 상대 차례인 판을 들고 있다")
    #expect(tally.attentions.isEmpty, "전제: 상대 차례에는 말풍선이 없다")

    otApply(window, visible: { chess.isWindowVisible = $0 }, occlusion: { chess.windowOcclusionDidChange(visible: $0) })
    if window == .shownOccluded {
        #expect(chess.isWindowOccluded && chess.isWindowVisible, "전제: 가려졌지만 창은 열려 있다")
        #expect(chess.pollTask == nil, "전제: 가려진 동안 폴링은 없다 — 초인종만 남는다")
    }

    chess.handleSignal()
    await otWait { chess.match?.plyCount == 6 && chess.syncTask == nil }
    #expect(chess.match?.plyCount == 6 && chess.match?.turn == .white, "전제: 초인종이 내 차례를 세웠다")
    let seen = tally.attentions
    chess.reset()
    return seen
}

// MARK: 테트리스

private func otTetrisState() -> [String: Any] {
    let now = otNowMs()
    func player(_ id: String, _ name: String) -> [String: Any] {
        ["id": id, "display_name": name, "avatar_url": NSNull(), "character": NSNull(),
         "ready": false, "seq": 0, "board": NSNull(), "lines": 0, "garbage_sent": 0,
         "garbage_applied": 0, "pending": 0, "last_seen_ms": NSNull(), "topped_out": false]
    }
    return [
        "match_id": otTetrisMatch, "status": "active", "stake": 3, "seed": 4_242,
        "server_now_ms": now, "accepted_at_ms": now - 2_000,
        "start_at_ms": NSNull(), "ready_deadline_ms": now + 28_000, "max_end_ms": NSNull(), "finished_at_ms": NSNull(),
        "me": player(otMe, "나"), "opponent": player(otRival, "라이벌"),
        "result": NSNull(), "winner": NSNull(), "end_reason": NSNull(),
        "ruby_balance": 97, "my_device": "this"
    ]
}

private func otTetrisLobby() -> String {
    otJSON([
        "status": "ok", "server_now_ms": otNowMs(), "stakes": [3, 5, 10],
        "me": ["ruby_balance": 100, "wins": 0, "losses": 0, "draws": 0,
               "active_match_id": otTetrisMatch, "incoming": [] as [Any], "outgoing": NSNull()],
        "users": [] as [Any],
        "matches": [] as [Any],
    ])
}

/// 테트리스: 창을 `window` 로 둔 채(로비를 띄워 둔 채 다른 스페이스로 갔다) → 상대가 수락했다는 초인종 → 로비 → 판 상태가 판을 연다.
@MainActor
private func otTetrisMatchStarts(_ label: String, window: OTWindow) async -> [TetrisDuelAttention] {
    let lobby = otTetrisLobby()
    let state = otJSON(["status": "ok", "state": otTetrisState()])
    let store = otAppStore("t-\(label)", userID: otMe) { rpc, _, _ in
        switch rpc {
        case "tetris_lobby": return .init(body: lobby)
        case "tetris_state": return .init(body: state)
        default: return nil
        }
    }
    let tetris = store.tetris
    tetris.pollStepSeconds = 3_600
    tetris.gameLoopStepSeconds = 3_600
    let tally = OTTally<TetrisDuelAttention>()
    tetris.onAttention = { tally.attentions.append($0) }

    otApply(window, visible: { tetris.isWindowVisible = $0 }, occlusion: { tetris.windowOcclusionDidChange(visible: $0) })
    if window == .shownOccluded {
        #expect(tetris.isWindowOccluded && tetris.isWindowVisible, "전제: 가려졌지만 창은 열려 있다")
        #expect(tetris.pollTask == nil, "전제: 가려진 동안 폴링은 없다 — 초인종만 남는다")
    }

    tetris.handleSignal()
    await otWait { tetris.match?.id == otTetrisMatch && tetris.syncTask == nil }
    #expect(tetris.match?.id == otTetrisMatch && tetris.match?.isFinished == false && !tetris.playingElsewhere,
            "전제: 초인종이 이 기기가 두는 판을 열었다")
    let seen = tally.attentions
    tetris.reset()
    return seen
}

// MARK: 오버레이 순수 판정용 판

private let otGomokuPeer = GomokuUser(id: otRival, displayName: "민수", avatarURL: nil, characterID: "fox",
                                      isWorking: true, isCapable: true, inMatch: true)

private func otGomokuMyTurnMatch() -> GomokuMatchState {
    var board = GomokuBoard()
    if let h8 = GomokuPoint(notation: "H8") { board[h8] = .black }
    if let i9 = GomokuPoint(notation: "I9") { board[i9] = .white }
    return GomokuMatchState(
        id: "match-1", stake: 5, myColor: .black, opponent: otGomokuPeer, board: board,
        lastMove: GomokuPoint(notation: "I9"), moveCount: 2, turn: .black,
        deadline: Date().addingTimeInterval(25), isFinished: false, outcome: nil, endReason: nil,
        rubyDelta: nil, blackPassed: false)
}

private func otChessMyTurnMatch() -> ChessMatchState {
    let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    let peer = ChessUser(id: otRival, displayName: "민수", avatarURL: nil, characterID: "fox",
                         isWorking: true, isCapable: true, inMatch: true)
    return ChessMatchState(
        id: "match-1", stake: 5, myColor: .white, opponent: peer, fen: fen,
        position: ChessPosition(fen: fen), plyCount: 4, turn: .white, lastMove: nil, moves: [],
        clock: .initial, isInCheck: false, legalMoves: [], isFinished: false, outcome: nil,
        endReason: nil, rubyDelta: nil, drawOfferBy: nil, drawOfferedByMe: false)
}

private func otTetrisLiveMatch() -> TetrisDuelMatchState {
    let peer = TetrisDuelUser(id: otRival, displayName: "민수", avatarURL: nil, characterID: "fox",
                              isWorking: true, isCapable: true, inMatch: true)
    return TetrisDuelMatchState(
        id: otTetrisMatch, stake: 5, seed: 7, opponent: peer,
        acceptedAt: nil, readyDeadline: nil, startAt: nil, maxEnd: nil, meReady: false,
        opponentBoard: .empty, isFinished: false, outcome: nil, endReason: nil, rubyDelta: nil, finishedAt: nil)
}

// MARK: - 시험

@MainActor
@Suite("가려진 대국 창에서도 '내 차례' 말풍선 — 오목 · 체스 · 테트리스", .serialized)
struct OccludedTurnAlertTests {

    // MARK: 오목

    @Test("오목 (a) 기준선 — 창이 안 보일 때 상대가 두면 내 차례 말풍선이 한 번 뜬다", .gomokuDefaultsCleanup)
    func gomokuClosedWindowAlerts() async {
        let seen = await otGomokuOpponentMoves("closed", window: .closed)
        #expect(seen.map(\.kind) == [.myTurn], "창이 닫혀 있는데 내 차례 알림이 없다 — 기준선이 죽었다")
        #expect(seen.first?.moveCount == 2 && seen.first?.matchID == otGomokuMatch)
    }

    @Test("오목 (b) 창은 열렸지만 가려졌을 때 상대가 두면 내 차례 말풍선이 뜬다", .gomokuDefaultsCleanup)
    func gomokuOccludedWindowAlerts() async {
        // 없으면: 다른 전체 화면 앱 · 다른 스페이스로 간 사람은 폴링도 멈추고 말풍선 문도 `isWindowVisible` 에 막혀
        // 내 차례를 알 길이 0 이다 — 30초 + 유예 뒤 자동 착수, 세 번이면 판돈 패인데도 초록이다.
        let seen = await otGomokuOpponentMoves("occluded", window: .shownOccluded)
        #expect(seen.map(\.kind) == [.myTurn], "가려진 창인데 내 차례 알림이 없다: \(seen)")
        #expect(seen.first?.moveCount == 2)
    }

    @Test("오목 (c) 대조 — 창이 보이고 안 가려졌으면 말풍선을 안 연다(화면이 이미 말한다)", .gomokuDefaultsCleanup)
    func gomokuShownWindowStaysQuiet() async {
        let seen = await otGomokuOpponentMoves("shown", window: .shown)
        #expect(seen.isEmpty, "보이는 창 위에 말풍선까지 띄웠다: \(seen)")
    }

    // MARK: 체스

    @Test("체스 (a) 기준선 — 창이 안 보일 때 상대가 두면 내 차례 말풍선이 한 번 뜬다", .gomokuDefaultsCleanup)
    func chessClosedWindowAlerts() async {
        let seen = await otChessOpponentMoves("closed", window: .closed)
        #expect(seen.map(\.kind) == [.myTurn], "창이 닫혀 있는데 내 차례 알림이 없다 — 기준선이 죽었다")
        #expect(seen.first?.plyCount == 6 && seen.first?.matchID == otChessMatch)
    }

    @Test("체스 (b) 창은 열렸지만 가려졌을 때 상대가 두면 내 차례 말풍선이 뜬다", .gomokuDefaultsCleanup)
    func chessOccludedWindowAlerts() async {
        // 없으면: 가려진 창의 체스 시계가 말없이 흘러 시간패로 판돈을 잃어도 초록이다.
        let seen = await otChessOpponentMoves("occluded", window: .shownOccluded)
        #expect(seen.map(\.kind) == [.myTurn], "가려진 창인데 내 차례 알림이 없다: \(seen)")
        #expect(seen.first?.plyCount == 6)
    }

    @Test("체스 (c) 대조 — 창이 보이고 안 가려졌으면 말풍선을 안 연다", .gomokuDefaultsCleanup)
    func chessShownWindowStaysQuiet() async {
        let seen = await otChessOpponentMoves("shown", window: .shown)
        #expect(seen.isEmpty, "보이는 창 위에 말풍선까지 띄웠다: \(seen)")
    }

    // MARK: 테트리스(시작 알림 — 실시간 판이라 시작을 놓치면 진다)

    @Test("테트리스 (a) 기준선 — 창이 안 보일 때 판이 열리면 시작 말풍선이 한 번 뜬다", .gomokuDefaultsCleanup)
    func tetrisClosedWindowAlerts() async {
        let seen = await otTetrisMatchStarts("closed", window: .closed)
        #expect(seen.map(\.kind) == [.matchStarted], "창이 닫혀 있는데 시작 알림이 없다 — 기준선이 죽었다")
        #expect(seen.first?.matchID == otTetrisMatch)
    }

    @Test("테트리스 (b) 창은 열렸지만 가려졌을 때 판이 열리면 시작 말풍선이 뜬다", .gomokuDefaultsCleanup)
    func tetrisOccludedWindowAlerts() async {
        // 없으면: 로비 창을 띄워 둔 채 다른 스페이스에 있던 사람이 수락 소식을 못 들어 준비 30초가 지나가도 초록이다.
        let seen = await otTetrisMatchStarts("occluded", window: .shownOccluded)
        #expect(seen.map(\.kind) == [.matchStarted], "가려진 창인데 시작 알림이 없다: \(seen)")
    }

    @Test("테트리스 (c) 대조 — 창이 보이고 안 가려졌으면 말풍선을 안 연다", .gomokuDefaultsCleanup)
    func tetrisShownWindowStaysQuiet() async {
        let seen = await otTetrisMatchStarts("shown", window: .shown)
        #expect(seen.isEmpty, "보이는 창 위에 말풍선까지 띄웠다: \(seen)")
    }

    // MARK: 오버레이 펌프의 순수 판정 — 가려지면 사실, 보이고 안 가려지면 거짓

    @Test("오버레이 오목 — 가려진 창에서 띄운 차례 말풍선은 사실로 남는다")
    func overlayGomokuJudgesOcclusion() {
        let gomoku = GomokuStore()
        gomoku.match = otGomokuMyTurnMatch()
        let attention = GomokuAttention(kind: .myTurn, matchID: "match-1", opponentName: "민수", moveCount: 2)
        #expect(CheckOverlayController.gomokuAttentionIsCurrent(attention, in: gomoku), "기준선: 창이 닫혔으면 사실이다")
        gomoku.isWindowVisible = true
        #expect(!CheckOverlayController.gomokuAttentionIsCurrent(attention, in: gomoku), "대조: 보이는 창이면 거짓이다")
        gomoku.windowOcclusionDidChange(visible: false)
        #expect(CheckOverlayController.gomokuAttentionIsCurrent(attention, in: gomoku),
                "가려진 창인데 차례 알림을 거짓으로 걷는다 — 말풍선이 떠도 곧바로 사라진다")
        gomoku.windowOcclusionDidChange(visible: true)
        #expect(!CheckOverlayController.gomokuAttentionIsCurrent(attention, in: gomoku), "가림이 풀리면 다시 거짓이다")
        gomoku.windowDidHide()
    }

    @Test("오버레이 체스 — 가려진 창에서 띄운 차례 말풍선은 사실로 남는다")
    func overlayChessJudgesOcclusion() {
        let chess = ChessStore()
        chess.match = otChessMyTurnMatch()
        let attention = ChessAttention(kind: .myTurn, matchID: "match-1", opponentName: "민수", plyCount: 4)
        #expect(CheckOverlayController.chessAttentionIsCurrent(attention, in: chess), "기준선: 창이 닫혔으면 사실이다")
        chess.isWindowVisible = true
        #expect(!CheckOverlayController.chessAttentionIsCurrent(attention, in: chess), "대조: 보이는 창이면 거짓이다")
        chess.windowOcclusionDidChange(visible: false)
        #expect(CheckOverlayController.chessAttentionIsCurrent(attention, in: chess),
                "가려진 창인데 차례 알림을 거짓으로 걷는다 — 말풍선이 떠도 곧바로 사라진다")
        chess.windowOcclusionDidChange(visible: true)
        #expect(!CheckOverlayController.chessAttentionIsCurrent(attention, in: chess), "가림이 풀리면 다시 거짓이다")
        chess.windowDidHide()
    }

    @Test("오버레이 테트리스 — 가려진 창에서 띄운 시작 말풍선은 사실로 남는다")
    func overlayTetrisJudgesOcclusion() {
        let tetris = TetrisDuelStore()
        tetris.match = otTetrisLiveMatch()
        let attention = TetrisDuelAttention(kind: .matchStarted, matchID: otTetrisMatch, opponentName: "민수")
        #expect(CheckOverlayController.tetrisAttentionIsCurrent(attention, in: tetris), "기준선: 창이 닫혔으면 사실이다")
        tetris.isWindowVisible = true
        #expect(!CheckOverlayController.tetrisAttentionIsCurrent(attention, in: tetris), "대조: 보이는 창이면 거짓이다")
        tetris.windowOcclusionDidChange(visible: false)
        #expect(CheckOverlayController.tetrisAttentionIsCurrent(attention, in: tetris),
                "가려진 창인데 시작 알림을 거짓으로 걷는다 — 말풍선이 떠도 곧바로 사라진다")
        tetris.windowOcclusionDidChange(visible: true)
        #expect(!CheckOverlayController.tetrisAttentionIsCurrent(attention, in: tetris), "가림이 풀리면 다시 거짓이다")
        tetris.windowDidHide()
    }
}
