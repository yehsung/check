import Foundation
import Testing
@testable import check
@testable import CheckCore

// 결함 ①의 남은 길 — 판이 시작될 때 스토어가 `presentWindow`(창 앞으로)를 부르면 앱 배선은 **동기로**
// `CheckGomokuWindowController.show()` → `notifyVisibility(true)` → `store.windowDidShow()` 를 지난다.
// 고치기 전 `windowDidShow` 는 가림 기록을 무조건 지웠다. 이미 열린 채 가려진 창(다른 전체 화면 앱 · 다른 스페이스)이
// 정말 앞으로 오면 그건 맞지만, 못 오면(협조적 활성화 거절 등) 가림 상태가 그대로라 가림 통지가 다시 오지 않는다 →
// 스토어는 "보이고 안 가려졌다"고 믿어 ① 시작 말풍선을 오버레이가 띄우기 전에 버리고 ② 그 판의 다음 '내 차례' 말풍선도 막힌다.
// 고친 뒤: 열린 채 가려진 창을 다시 부르는 `windowDidShow` 는 가림 기록을 그대로 둔다(창이 정말 앞으로 오면 가림 통지
// visible 이 와서 푼다). 숨겼다가 다시 여는 길은 `windowDidHide` 가 이미 지웠으므로 그대로다.
// 적대 검증 프로브(C1VerifyProbeTests, 복제본)를 옮겼다.

private let opMe = "00000000-0000-0000-0000-0000000000a1"
private let opRival = "00000000-0000-0000-0000-0000000000b2"
private let opGomokuMatch = "0c0c0c0c-2222-3333-4444-5555555555ab"
private let opTetrisMatch = "7e7e0000-0000-4000-8000-0000000000d2"

private func opJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func opNowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

@MainActor
private enum OPRetention { static var stores: [WorkTimerStore] = [] }

@MainActor
private func opAppStore(_ host: String, handler: @escaping GomokuStubProtocol.Handler) -> WorkTimerStore {
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: GomokuTestDefaults.make("occluded-present"), workspaceNotifications: nil)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: opMe)
    OPRetention.stores.append(store)
    return store
}

@MainActor
private func opWait(_ timeout: TimeInterval = 20, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<Int(timeout * 200) {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
private final class OPTally<A> { var items: [A] = [] }

/// 신청자(나 · 흑) 오목 서버. 처음엔 막 시작한 판(내 차례), `advance()` 뒤엔 흑 · 백 한 수씩 — 다시 내 차례.
private final class OPGomokuServer: @unchecked Sendable {
    private let lock = NSLock()
    private var phase = 0
    func advance() { lock.lock(); phase = 1; lock.unlock() }
    func stateText() -> String {
        lock.lock(); let p = phase; lock.unlock()
        var cells = Array(repeating: Character("."), count: 225)
        let moveCount: Int
        if p == 0 {
            moveCount = 0
        } else {
            cells[7 * 15 + 7] = "b"; cells[7 * 15 + 8] = "w"
            moveCount = 2
        }
        let now = opNowMs()
        return opJSON([
            "status": "ok",
            "match": [
                "id": opGomokuMatch, "status": "active", "stake": 5,
                "black": opMe, "white": opRival, "challenger": opMe, "opponent": opRival,
                "move_count": moveCount, "turn": "black", "deadline_ms": now + 30_000,
                "result": NSNull(), "end_reason": NSNull(), "winner": NSNull(),
                "invite_expires_ms": now, "board": String(cells)
            ] as [String: Any],
            "moves": [] as [Any],
            "my_color": "black",
            "opponent": ["user_id": opRival, "display_name": "라이벌", "avatar_url": NSNull(), "character": "aing"],
            "ruby_balance": 20,
            "server_now_ms": now
        ])
    }
}

@MainActor
@Suite("가려진 창에서 판이 시작될 때 — 창 띄우기가 가림 기록을 지우지 않는다(오목 · 체스 · 테트리스 · 아잉 뒤집기)", .serialized)
struct OccludedPresentWindowTests {

    /// 신청자: 로비 창을 연 채 다른 전체 화면 앱에 있다 → 수락 초인종 → 판 시작. 앱처럼 presentWindow 가 windowDidShow 를
    /// 부르고, 창은 여전히 가려져 있다(가림 통지 없음). 시작 말풍선이 오버레이 판정을 지나고, 다음 차례 말풍선도 뜬다.
    @Test("오목 신청자 · 가린 채 판 시작 — 시작 말풍선이 살아남고 다음 차례 말풍선도 뜬다", .gomokuDefaultsCleanup)
    func gomokuStartWhileOccluded() async {
        let server = OPGomokuServer()
        let host = "op-g-\(UUID().uuidString.prefix(8))".lowercased()
        let store = opAppStore(host) { rpc, _, _ in
            switch rpc {
            case "gomoku_state": return .init(body: server.stateText())
            case "gomoku_inbox":
                return .init(body: opJSON(["status": "ok", "incoming": [] as [Any], "outgoing": NSNull(),
                                           "active_match_id": opGomokuMatch, "server_now_ms": opNowMs()]))
            case "gomoku_lobby": return .init(body: opJSON(["status": "ok", "users": [] as [Any]]))
            default: return nil
            }
        }
        let gomoku = store.gomoku
        gomoku.pollStepSeconds = 3_600
        gomoku.noteOwnsMatch(opGomokuMatch)
        let tally = OPTally<GomokuAttention>()
        var presents = 0
        gomoku.presentWindow = { presents += 1; gomoku.windowDidShow() }   // 앱 배선의 동기 효과
        gomoku.onAttention = { tally.items.append($0) }
        gomoku.isWindowVisible = true
        gomoku.windowOcclusionDidChange(visible: false)
        #expect(gomoku.isWindowOccluded)

        gomoku.handleSignal()
        await opWait { gomoku.match?.id == opGomokuMatch && gomoku.syncTask == nil }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(presents == 1, "전제: 판 시작이 창을 띄웠다")
        #expect(tally.items.map(\.kind) == [.matchStarted], "스토어는 시작 말풍선을 낸다: \(tally.items)")
        #expect(gomoku.isWindowOccluded, "창 띄우기가 가림 기록을 지웠다 — 창이 못 왔으면 말풍선이 다 막힌다")
        if let first = tally.items.first {
            #expect(CheckOverlayController.gomokuAttentionIsCurrent(first, in: gomoku),
                    "오버레이가 시작 말풍선을 띄우기 전에 버린다")
        }

        server.advance()
        gomoku.handleSignal()
        await opWait { gomoku.match?.moveCount == 2 && gomoku.syncTask == nil }
        #expect(gomoku.match?.moveCount == 2 && gomoku.match?.turn == .black, "전제: 다시 내 차례")
        #expect(tally.items.map(\.kind) == [.matchStarted, .myTurn],
                "창이 여전히 가려졌는데 다음 차례 말풍선이 막혔다: \(tally.items.map(\.kind))")

        // 창이 정말 앞으로 왔다(가림 통지 visible) — 그때는 풀린다.
        gomoku.windowOcclusionDidChange(visible: true)
        #expect(!gomoku.isWindowOccluded)
        if let last = tally.items.last {
            #expect(!CheckOverlayController.gomokuAttentionIsCurrent(last, in: gomoku), "보이는 창이면 말풍선은 거짓이다")
        }
        gomoku.reset()
    }

    /// 테트리스: 가린 채 판 시작 + 앱 presentWindow. 시작 말풍선이 오버레이 판정을 지난다.
    @Test("테트리스 · 가린 채 판 시작 — 시작 말풍선이 오버레이에서 살아남는다", .gomokuDefaultsCleanup)
    func tetrisStartWhileOccluded() async {
        let now = opNowMs()
        func player(_ id: String, _ name: String) -> [String: Any] {
            ["id": id, "display_name": name, "avatar_url": NSNull(), "character": NSNull(),
             "ready": false, "seq": 0, "board": NSNull(), "lines": 0, "garbage_sent": 0,
             "garbage_applied": 0, "pending": 0, "last_seen_ms": NSNull(), "topped_out": false]
        }
        let stateObj: [String: Any] = [
            "match_id": opTetrisMatch, "status": "active", "stake": 3, "seed": 4_242,
            "server_now_ms": now, "accepted_at_ms": now - 2_000,
            "start_at_ms": NSNull(), "ready_deadline_ms": now + 28_000, "max_end_ms": NSNull(), "finished_at_ms": NSNull(),
            "me": player(opMe, "나"), "opponent": player(opRival, "라이벌"),
            "result": NSNull(), "winner": NSNull(), "end_reason": NSNull(),
            "ruby_balance": 97, "my_device": "this"
        ]
        let state = opJSON(["status": "ok", "state": stateObj])
        let lobby = opJSON([
            "status": "ok", "server_now_ms": now, "stakes": [3, 5, 10],
            "me": ["ruby_balance": 100, "wins": 0, "losses": 0, "draws": 0,
                   "active_match_id": opTetrisMatch, "incoming": [] as [Any], "outgoing": NSNull()],
            "users": [] as [Any], "matches": [] as [Any],
        ])
        let host = "op-t-\(UUID().uuidString.prefix(8))".lowercased()
        let store = opAppStore(host) { rpc, _, _ in
            switch rpc {
            case "tetris_lobby": return .init(body: lobby)
            case "tetris_state": return .init(body: state)
            case "tetris_report": return .init(body: state)
            default: return nil
            }
        }
        let tetris = store.tetris
        tetris.pollStepSeconds = 3_600
        tetris.gameLoopStepSeconds = 3_600
        let tally = OPTally<TetrisDuelAttention>()
        tetris.onAttention = { tally.items.append($0) }
        tetris.presentWindow = { tetris.windowDidShow() }
        tetris.isWindowVisible = true
        tetris.windowOcclusionDidChange(visible: false)

        tetris.handleSignal()
        await opWait { tetris.match?.id == opTetrisMatch && tetris.syncTask == nil }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(tetris.match?.id == opTetrisMatch && !tetris.playingElsewhere, "전제: 이 기기가 두는 판이 열렸다")
        #expect(tally.items.map(\.kind) == [.matchStarted], "전제: 스토어는 시작 말풍선을 낸다")
        #expect(tetris.isWindowOccluded, "창 띄우기가 가림 기록을 지웠다")
        if let first = tally.items.first {
            #expect(CheckOverlayController.tetrisAttentionIsCurrent(first, in: tetris),
                    "오버레이가 시작 말풍선을 띄우기 전에 버린다")
        }
        tetris.reset()
    }

    /// 체스: 같은 문(windowDidShow)의 단위 판정 — 열린 채 가려진 창을 다시 부르면 가림을 지키고, 오버레이 말풍선이 사실로 남는다.
    @Test("체스 · 열린 채 가려진 창을 다시 띄우면 가림 기록을 지킨다 · 가림 통지 visible 이 푼다")
    func chessShowKeepsOcclusion() {
        let chess = ChessStore()
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let peer = ChessUser(id: opRival, displayName: "민수", avatarURL: nil, characterID: "fox",
                             isWorking: true, isCapable: true, inMatch: true)
        chess.match = ChessMatchState(
            id: "match-1", stake: 5, myColor: .white, opponent: peer, fen: fen,
            position: ChessPosition(fen: fen), plyCount: 0, turn: .white, lastMove: nil, moves: [],
            clock: .initial, isInCheck: false, legalMoves: [], isFinished: false, outcome: nil,
            endReason: nil, rubyDelta: nil, drawOfferBy: nil, drawOfferedByMe: false)
        let attention = ChessAttention(kind: .matchStarted, matchID: "match-1", opponentName: "민수", plyCount: 0)
        chess.isWindowVisible = true
        chess.windowOcclusionDidChange(visible: false)
        chess.windowDidShow()                         // presentWindow 의 동기 효과
        #expect(chess.isWindowOccluded, "창 띄우기가 가림 기록을 지웠다")
        #expect(CheckOverlayController.chessAttentionIsCurrent(attention, in: chess), "오버레이가 시작 말풍선을 버린다")
        chess.windowOcclusionDidChange(visible: true)
        #expect(!chess.isWindowOccluded)
        #expect(!CheckOverlayController.chessAttentionIsCurrent(attention, in: chess))
        chess.windowDidHide()
    }

    /// 아잉 뒤집기: 같은 문(windowDidShow)의 단위 판정 — 0.3.74 통합에서 같은 결함을 찾아 같은 수리를 넣었다(한 수 30초라 더 아프다).
    @Test("아잉 뒤집기 · 열린 채 가려진 창을 다시 띄우면 가림 기록을 지킨다 · 가림 통지 visible 이 푼다")
    func reversiShowKeepsOcclusion() {
        let reversi = ReversiStore()
        let rival = ReversiUser(id: opRival, displayName: "민수", characterID: "fox", isWorking: true)
        reversi.match = ReversiMatchState(id: "match-r", stake: 5, myColor: .black, opponent: rival, moveCount: 0, turn: .black)
        let attention = ReversiAttention(kind: .matchStarted, matchID: "match-r", opponentName: "민수", moveCount: 0)
        reversi.isWindowVisible = true
        reversi.windowOcclusionDidChange(visible: false)
        reversi.windowDidShow()                       // presentWindow 의 동기 효과
        #expect(reversi.isWindowOccluded, "창 띄우기가 가림 기록을 지웠다")
        #expect(CheckOverlayController.reversiAttentionIsCurrent(attention, in: reversi), "오버레이가 시작 말풍선을 버린다")
        reversi.windowOcclusionDidChange(visible: true)
        #expect(!reversi.isWindowOccluded)
        #expect(!CheckOverlayController.reversiAttentionIsCurrent(attention, in: reversi))
        reversi.windowDidHide()

        // 대조: 숨겼다 다시 연 창은 가림이 아니다.
        reversi.windowOcclusionDidChange(visible: false)
        reversi.windowDidHide()
        reversi.windowDidShow()
        #expect(reversi.isWindowVisible && !reversi.isWindowOccluded)
        reversi.windowDidHide()
    }

    /// 대조: 숨겼다가 다시 여는 길은 그대로다 — windowDidHide 가 가림을 지우고, windowDidShow 뒤 가림이 아니다(폴링이 돈다).
    @Test("대조 · 숨겼다 다시 연 창은 가림이 아니다(오목 · 체스 · 테트리스)")
    func hiddenThenShownIsNotOccluded() {
        let gomoku = GomokuStore()
        gomoku.isWindowVisible = true
        gomoku.windowOcclusionDidChange(visible: false)
        gomoku.windowDidHide()
        gomoku.windowDidShow()
        #expect(gomoku.isWindowVisible && !gomoku.isWindowOccluded)
        gomoku.windowDidHide()

        let chess = ChessStore()
        chess.isWindowVisible = true
        chess.windowOcclusionDidChange(visible: false)
        chess.windowDidHide()
        chess.windowDidShow()
        #expect(chess.isWindowVisible && !chess.isWindowOccluded)
        chess.windowDidHide()

        let tetris = TetrisDuelStore()
        tetris.isWindowVisible = true
        tetris.windowOcclusionDidChange(visible: false)
        tetris.windowDidHide()
        tetris.windowDidShow()
        #expect(tetris.isWindowVisible && !tetris.isWindowOccluded)
        tetris.windowDidHide()

        // 처음 여는 창(가림 기록 없음)도 그대로.
        let fresh = GomokuStore()
        fresh.windowDidShow()
        #expect(fresh.isWindowVisible && !fresh.isWindowOccluded)
        fresh.windowDidHide()
    }
}
