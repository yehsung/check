import Foundation
import Testing
@testable import check
@testable import CheckCore

// 한 계정 여러 기기 — 1:1 판 창은 **판을 연 기기에서만** 저절로 열린다(2026-11-03).
//
// 제보 원문: "아니 이거 오목이나 미니게임 화면이 맥미니에도 동시에 열리는데 맥미니 꺼는 안 꺼져요".
// 원인: 1:1 판의 초인종(`gomoku__ring` · `chess__ring`)은 그 사람의 **모든 기기**로 간다. 받은 기기마다
// 받은함/로비 → 판 상태를 읽고 `noteMatchProgress` 가 "진행 중 판으로 처음 넘어갔다"로 보아 창 · 주의 · 말풍선을 불렀다.
// 맥북에서 신청한 판이 놀던 맥미니에서도 열리고, 그 창은 사람이 맥미니로 가서 닫기 전까지 남았다.
//
// 이 파일은 **두 스토어(같은 사람 · 다른 기기)** 를 한 흉내 서버 위에 세우고 창 띄우기 · 주의 · 말풍선 횟수를 잰다.
// 기준선이 짝으로 붙는다 — 판을 연 기기 A 는 예전처럼 창이 뜬다(가드 앞에서 통째로 멈춘 가짜 초록과 구별하려고).
// 테트리스(서버 my_device)는 `V0369TetrisOneWriterStoreTests`, 아잉 큐브(engaged 장부)는 `V0369RummyStoreTests` 가 잰다.

private let odMe = "00000000-0000-0000-0000-0000000000a1"
private let odRival = "00000000-0000-0000-0000-0000000000b2"
private let odMatch = "0d0d0d0d-2222-3333-4444-555555555555"

private func odJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func odNowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

/// 두 기기가 같이 보는 오목 흉내 서버(한 판). `status` 가 pending 이면 신청, active 면 판이다.
/// 스텁 응답기는 URL 로딩 스레드에서 부르므로 잠금으로 지킨다(테트리스 `TDServer` 와 같은 꼴).
private final class ODGomokuServer: @unchecked Sendable {
    private let lock = NSLock()
    var status = "pending"
    var moveCount = 0
    var turn = "black"
    /// 이 사람이 신청자인가(흑) — 아니면 받은 쪽(백).
    var meChallenged = true
    var stones: [(Int, Int, Character)] = []

    var myColor: String { meChallenged ? "black" : "white" }

    func board() -> String {
        var cells = Array(repeating: Character("."), count: 225)
        for (x, y, c) in stones { cells[y * 15 + x] = c }
        return String(cells)
    }

    func state() -> [String: Any] {
        let now = odNowMs()
        return [
            "status": "ok",
            "match": [
                "id": odMatch, "status": status, "stake": 5,
                "black": meChallenged ? odMe : odRival, "white": meChallenged ? odRival : odMe,
                "challenger": meChallenged ? odMe : odRival, "opponent": meChallenged ? odRival : odMe,
                "move_count": moveCount, "turn": status == "active" ? turn : NSNull(),
                "deadline_ms": now + 30_000, "result": NSNull(), "end_reason": NSNull(), "winner": NSNull(),
                "invite_expires_ms": now + 50_000, "board": board()
            ] as [String: Any],
            "moves": [] as [Any],
            "my_color": myColor,
            "opponent": ["user_id": odRival, "display_name": "라이벌", "avatar_url": NSNull(), "character": "aing"],
            "ruby_balance": 20,
            "server_now_ms": now
        ]
    }

    func inbox() -> [String: Any] {
        let now = odNowMs()
        let row: [String: Any] = [
            "match_id": odMatch, "stake": 5, "invite_expires_ms": now + 50_000,
            "challenger": ["user_id": meChallenged ? odMe : odRival, "display_name": meChallenged ? "나" : "라이벌"],
            "opponent": ["user_id": meChallenged ? odRival : odMe, "display_name": meChallenged ? "라이벌" : "나"]
        ]
        var body: [String: Any] = ["status": "ok", "server_now_ms": now, "ruby_balance": 20]
        if status == "pending" {
            body["incoming"] = meChallenged ? [] : [row]
            body["outgoing"] = meChallenged ? row : NSNull()
        } else {
            body["incoming"] = [] as [Any]
            body["outgoing"] = NSNull()
            body["active_match_id"] = odMatch
        }
        return body
    }

    func edit(_ change: (ODGomokuServer) -> Void) {
        lock.lock()
        change(self)
        lock.unlock()
    }

    func handler() -> GomokuStubProtocol.Handler {
        { [self] rpc, _, _ in
            lock.lock()
            defer { lock.unlock() }
            return reply(rpc)
        }
    }

    private func reply(_ rpc: String) -> GomokuStubProtocol.Reply? {
        switch rpc {
        case "gomoku_inbox": return .init(body: odJSON(inbox()))
        case "gomoku_state": return .init(body: odJSON(state()))
        case "gomoku_lobby": return .init(body: odJSON(["status": "ok", "users": [] as [Any]]))
        case "gomoku_challenge":
            let now = odNowMs()
            return .init(body: odJSON(["status": "ok", "match_id": odMatch, "invite_expires_ms": now + 50_000,
                                       "ruby_balance": 20, "server_now_ms": now]))
        case "gomoku_respond":
            status = "active"
            return .init(body: odJSON(["status": "ok", "state": state(), "ruby_balance": 15,
                                       "server_now_ms": odNowMs()]))
        case "gomoku_move":
            return .init(body: odJSON(["status": "ok", "state": state(), "server_now_ms": odNowMs()]))
        default: return nil
        }
    }
}

@MainActor
private enum ODRetention { static var stores: [WorkTimerStore] = [] }

@MainActor
private final class ODTally {
    var presents = 0
    var attentionRequests = 0
    var attentions: [GomokuAttention] = []
}

/// 같은 사람(`odMe`)의 **기기 하나**. 기기마다 자기 스텁 호스트 · 자기 defaults(= 다른 맥)를 갖는다.
@MainActor
private func odGomokuDevice(_ label: String, server: ODGomokuServer, defaults: UserDefaults? = nil)
    -> (store: WorkTimerStore, gomoku: GomokuStore, tally: ODTally, host: String) {
    let host = "od-g-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: server.handler())
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: defaults ?? GomokuTestDefaults.make("od-gomoku"), workspaceNotifications: nil)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: odMe)
    ODRetention.stores.append(store)
    let gomoku = store.gomoku
    let tally = ODTally()
    gomoku.presentWindow = { tally.presents += 1 }
    gomoku.requestAttention = { tally.attentionRequests += 1 }
    gomoku.onAttention = { tally.attentions.append($0) }
    return (store, gomoku, tally, host)
}

@MainActor
private func odWait(_ timeout: TimeInterval = 20, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<Int(timeout * 200) {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 초인종 한 번이 끝까지 돈다(받은함 → 진행 중 판 상태).
@MainActor
private func odRing(_ gomoku: GomokuStore) async {
    gomoku.handleSignal()
    await odWait { gomoku.syncTask == nil }
}

// MARK: - 체스

/// 체스 픽스처(실서버 응답 원문 — `V0343ChessStoreTests` 와 같은 폴더). 부른 사람은 매니페스트의 A(`odChessMe`)다.
private let odChessFixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/chess-rpc", isDirectory: true)
private let odChessMe = "aa000000-0000-4000-8000-0000000000a1"
private let odChessRival = "bb000000-0000-4000-8000-0000000000b2"
private let odChessMatch = "9a7156f6-f055-4590-ba98-f537ead0a600"

private func odChessText(_ name: String) -> String {
    try! String(contentsOf: odChessFixtures.appendingPathComponent("\(name).json"), encoding: .utf8)
}

@MainActor
private final class ODChessTally {
    var presents = 0
    var attentionRequests = 0
    var attentions: [ChessAttention] = []
}

/// 같은 사람(A)의 체스 기기 하나. 로비는 진행 중 판을 말하고(수락 뒤), 상태는 A 의 첫 차례다.
@MainActor
private func odChessDevice(_ label: String) -> (chess: ChessStore, tally: ODChessTally) {
    let host = "od-c-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    let lobby = odChessText("chess_lobby__ok_in_match")
    let state = odChessText("chess_state__ok_initial_my_turn")
    GomokuStubProtocol.register(host: host) { rpc, _, _ in
        switch rpc {
        case "chess_lobby": return .init(body: lobby)
        case "chess_state": return .init(body: state)
        case "chess_challenge":
            return .init(body: #"{"status":"ok","match_id":"\#(odChessMatch)","ruby_balance":95,"#
                         + #""server_now_ms":1791182748623,"invite_expires_ms":1791182808623}"#)
        default: return nil
        }
    }
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let owner = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: GomokuTestDefaults.make("od-chess"), workspaceNotifications: nil)
    owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: odChessMe)
    ODRetention.stores.append(owner)
    let chess = ChessStore(host: owner)
    chess.pollStepSeconds = 3_600
    let tally = ODChessTally()
    chess.presentWindow = { tally.presents += 1 }
    chess.requestAttention = { tally.attentionRequests += 1 }
    chess.onAttention = { tally.attentions.append($0) }
    return (chess, tally)
}

@MainActor
private func odRing(_ chess: ChessStore) async {
    chess.handleSignal()
    await odWait { chess.syncTask == nil }
}

// MARK: - 오목

@MainActor
@Suite("한 계정 여러 기기 — 1:1 창은 판을 연 기기에서만 저절로 열린다", .serialized)
struct GameWindowOneDeviceTests {

    @Test("오목 ① 신청한 기기 A 만 창·주의·말풍선을 받는다 — 같은 계정의 맥미니 B 는 판을 알되 창을 안 띄운다",
          .gomokuDefaultsCleanup)
    func gomokuChallengerOnlyOpensOnTheChallengingDevice() async {
        // 없으면(0.3.27~0.3.73): 수락 초인종을 받은 신청자의 **모든 맥**이 창을 띄우고 주의를 끈다 — 2026-11-03 제보.
        let server = ODGomokuServer()
        let a = odGomokuDevice("ch-a", server: server)
        let b = odGomokuDevice("ch-b", server: server)

        await a.gomoku.challenge(userID: odRival)
        #expect(a.gomoku.outgoing?.id == odMatch, "전제: A 가 신청을 보냈다")
        await odRing(b.gomoku)                        // B 도 받은함에서 보낸 신청을 본다(계정 단위)
        #expect(b.gomoku.outgoing?.id == odMatch, "전제: B 도 같은 계정의 보낸 신청을 안다")

        server.edit { $0.status = "active" }          // 상대가 수락했다 — 신청자의 모든 기기에 초인종
        await odRing(a.gomoku)
        await odRing(b.gomoku)

        #expect(a.gomoku.phase == .playing && a.gomoku.match?.id == odMatch)
        #expect(a.tally.presents == 1, "신청한 A 가 창을 안 띄웠다(\(a.tally.presents)회) — 흑 30초를 흘린다")
        #expect(a.tally.attentionRequests == 1)
        #expect(a.tally.attentions.map(\.kind) == [.matchStarted])

        #expect(b.gomoku.match?.id == odMatch && b.gomoku.phase == .playing,
                "B 는 판을 알아야 한다 — 사람이 B 에서 창을 직접 열면 판이 보여야 한다")
        #expect(b.tally.presents == 0, "신청하지 않은 B 가 창을 \(b.tally.presents)번 띄웠다")
        #expect(b.tally.attentionRequests == 0, "B 가 주의를 끌었다")
        #expect(b.tally.attentions.isEmpty, "B 에 말풍선이 떴다: \(b.tally.attentions)")
        a.gomoku.reset()
        b.gomoku.reset()
    }

    @Test("오목 ② 수락한 기기 A 만 창을 띄운다 — 초인종·상태만 받은 B 는 창·주의·말풍선이 0 이다",
          .gomokuDefaultsCleanup)
    func gomokuAcceptOnlyOpensOnTheAcceptingDevice() async {
        let server = ODGomokuServer()
        server.edit { $0.meChallenged = false }
        let a = odGomokuDevice("ac-a", server: server)
        let b = odGomokuDevice("ac-b", server: server)
        await odRing(a.gomoku)
        await odRing(b.gomoku)
        #expect(a.gomoku.incoming.map(\.id) == [odMatch] && b.gomoku.incoming.map(\.id) == [odMatch],
                "전제: 받은 신청은 두 기기 다 안다")

        await a.gomoku.respond(inviteID: odMatch, accept: true)
        await odRing(b.gomoku)                        // 수락으로 판이 섰다 — 서버는 두 사람의 모든 기기를 울린다

        #expect(a.gomoku.phase == .playing)
        #expect(a.tally.presents == 1, "수락한 A 가 창을 안 띄웠다(\(a.tally.presents)회)")
        #expect(b.gomoku.match?.id == odMatch)
        #expect(b.tally.presents == 0 && b.tally.attentionRequests == 0 && b.tally.attentions.isEmpty,
                "수락하지 않은 B 가 창 \(b.tally.presents) · 주의 \(b.tally.attentionRequests) · 말풍선 \(b.tally.attentions.count)")
        a.gomoku.reset()
        b.gomoku.reset()
    }

    @Test("오목 ③ 판 중 '내 차례' 말풍선도 판을 연 기기에서만 — B 는 상대가 둘 때마다 울려도 조용하다",
          .gomokuDefaultsCleanup)
    func gomokuTurnBubblesStayOnTheOwningDevice() async {
        let server = ODGomokuServer()
        server.edit { $0.meChallenged = false }       // 나는 백 — 상대(흑)가 먼저 둔다
        let a = odGomokuDevice("turn-a", server: server)
        let b = odGomokuDevice("turn-b", server: server)
        await odRing(a.gomoku)
        await a.gomoku.respond(inviteID: odMatch, accept: true)
        await odRing(b.gomoku)
        let aBefore = a.tally.attentions.count

        // 상대가 뒀다 → 내 차례. 두 기기 다 창이 안 보인다.
        server.edit {
            $0.moveCount = 1
            $0.turn = "white"
            $0.stones = [(7, 7, "B")]
        }
        await odRing(a.gomoku)
        await odRing(b.gomoku)

        #expect(a.gomoku.match?.moveCount == 1 && b.gomoku.match?.moveCount == 1, "전제: 두 기기 다 상대 수를 읽었다")
        #expect(a.tally.attentions.count == aBefore + 1 && a.tally.attentions.last?.kind == .myTurn,
                "판을 연 A 에 내 차례 말풍선이 안 떴다 — 기준선이 죽었다")
        #expect(b.tally.attentions.isEmpty, "B 에 내 차례 말풍선이 떴다: \(b.tally.attentions)")
        #expect(b.tally.presents == 0 && b.tally.attentionRequests == 0)
        a.gomoku.reset()
        b.gomoku.reset()
    }

    @Test("오목 ④ 장부는 앱 defaults 에 산다 — 판 중에 다시 켠 A 는 자기 판의 창을 띄우고, 다른 맥(다른 defaults)은 여전히 조용하다",
          .gomokuDefaultsCleanup)
    func gomokuLedgerSurvivesARestartOnTheOwningDevice() async {
        // 없으면: 장부가 프로세스 안에만 살아 판 중에 앱을 다시 켠 A 가 자기 판을 못 알아본다 — 창이 안 떠 흑 30초를 흘린다.
        let server = ODGomokuServer()
        let defaultsA = GomokuTestDefaults.make("od-restart-a")
        let a = odGomokuDevice("rs-a", server: server, defaults: defaultsA)
        await a.gomoku.challenge(userID: odRival)
        #expect(a.gomoku.ownsMatch(odMatch))
        #expect(defaultsA.dictionary(forKey: a.gomoku.deviceLedger.key(userID: odMe))?.keys.contains(odMatch) == true,
                "장부가 앱 defaults 에 안 떨어졌다(WorkTimerStore 배선)")
        a.gomoku.reset()

        server.edit { $0.status = "active" }
        // 같은 맥에서 앱을 다시 켰다 = 같은 defaults 의 새 스토어. 다른 맥 = 다른 defaults.
        let restarted = odGomokuDevice("rs-a2", server: server, defaults: defaultsA)
        let other = odGomokuDevice("rs-b", server: server)
        await odRing(restarted.gomoku)
        await odRing(other.gomoku)
        #expect(restarted.tally.presents == 1, "다시 켠 A 가 자기 판의 창을 안 띄웠다(\(restarted.tally.presents)회)")
        #expect(other.tally.presents == 0, "다른 맥이 창을 띄웠다 — 위 1 이 장부 덕인지 가리지 못한다")
        restarted.gomoku.reset()
        other.gomoku.reset()
    }

    @Test("오목 ⑤ B 로 옮겨 와 직접 두면 B 도 연 기기가 된다 — 그 뒤 내 차례 말풍선이 B 에서도 뜬다 · 끝나면 장부에서 걷힌다",
          .gomokuDefaultsCleanup)
    func gomokuPlacingOnAnotherDeviceAdoptsTheMatch() async {
        // 막는 것은 **저절로** 열리는 것뿐이다 — 사람이 B 에서 창을 열고 두면 B 가 그 판을 알린다.
        let server = ODGomokuServer()
        let a = odGomokuDevice("mv-a", server: server)
        let b = odGomokuDevice("mv-b", server: server)
        await a.gomoku.challenge(userID: odRival)
        server.edit { $0.status = "active" }           // 나는 흑, 내 차례
        await odRing(b.gomoku)
        #expect(b.tally.presents == 0 && !b.gomoku.ownsMatch(odMatch))

        // 사람이 B 에서 창을 열고 둔다.
        b.gomoku.isWindowVisible = true
        server.edit {
            $0.moveCount = 1
            $0.turn = "white"
            $0.stones = [(7, 7, "B")]
        }
        await b.gomoku.place(GomokuPoint(x: 7, y: 7)!)
        #expect(b.gomoku.ownsMatch(odMatch), "B 에서 둔 수가 장부에 안 올랐다")
        #expect(GomokuStubProtocol.count(host: b.host, rpc: "gomoku_move") == 1, "전제: B 의 수가 서버로 갔다")

        // 창을 닫았는데 상대가 뒀다 → 내 차례 말풍선이 B 에서 뜬다.
        b.gomoku.isWindowVisible = false
        server.edit {
            $0.moveCount = 2
            $0.turn = "black"
            $0.stones = [(7, 7, "B"), (8, 8, "W")]
        }
        await odRing(b.gomoku)
        #expect(b.tally.attentions.map(\.kind) == [.myTurn], "B 로 옮겨 온 사람에게 내 차례가 안 왔다: \(b.tally.attentions)")
        #expect(b.tally.presents == 0, "판 시작은 지나갔다 — 창을 다시 띄우면 안 된다")

        // 판이 끝났다 → 장부에서 걷힌다.
        server.edit { $0.status = "finished" }
        await b.gomoku.refreshMatch(id: odMatch)
        #expect(b.gomoku.match?.isFinished == true && !b.gomoku.ownsMatch(odMatch), "끝난 판이 장부에 남았다")
        a.gomoku.reset()
        b.gomoku.reset()
    }

    @Test("체스 ① 신청한 기기 A 만 창·주의·말풍선을 받는다 — 같은 계정의 B 는 판을 알되 창을 안 띄운다",
          .gomokuDefaultsCleanup)
    func chessChallengerOnlyOpensOnTheChallengingDevice() async {
        // 없으면(0.3.44~0.3.73): 수락 초인종을 받은 신청자의 모든 맥이 체스 창을 띄우고 주의를 끈다.
        let a = odChessDevice("ch-a")
        let b = odChessDevice("ch-b")
        await a.chess.challenge(userID: odChessRival)
        #expect(a.chess.outgoing?.id == odChessMatch, "전제: A 가 신청을 보냈다")

        await odRing(a.chess)                         // 상대가 수락했다 — 로비가 진행 중 판을 말한다
        await odRing(b.chess)

        #expect(a.chess.match?.id == odChessMatch)
        #expect(a.tally.presents == 1, "신청한 A 가 창을 안 띄웠다(\(a.tally.presents)회) — 시계를 흘린다")
        #expect(a.tally.attentionRequests == 1)
        #expect(a.tally.attentions.map(\.kind) == [.matchStarted])
        #expect(b.chess.match?.id == odChessMatch, "B 는 판을 알아야 한다 — 창을 직접 열면 판이 보여야 한다")
        #expect(b.tally.presents == 0 && b.tally.attentionRequests == 0 && b.tally.attentions.isEmpty,
                "신청하지 않은 B 가 창 \(b.tally.presents) · 주의 \(b.tally.attentionRequests) · 말풍선 \(b.tally.attentions.count)")
        a.chess.reset()
        b.chess.reset()
    }
}
