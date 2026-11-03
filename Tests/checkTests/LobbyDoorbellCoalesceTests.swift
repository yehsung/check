import Foundation
import Testing
@testable import check
@testable import CheckCore

// 결함 ② — 로비를 읽는 도중에 온 초인종을 버린다(오목 · 체스 · 테트리스) + 같은 갈래(폴링 취소가 합쳐진 조회를 죽인다).
//
// 아잉 뒤집기 적대 검증(V2-02 · V2-03 · VR-04)이 찾은 결함이 같은 틀을 쓰는 세 게임에 그대로 남아 있었다.
//  (b) `refreshLobby` 가 `guard !lobbyInFlight else { return }` 라, 로비가 도는 중에 온 '새 신청'·'수락' 초인종의 조회가
//      그냥 빠진다. 앞 조회는 그 뒤에 생긴 신청·수락을 모르므로 받은 신청 카드·메뉴바 점·말풍선이 다음 계기(30초 폴링·팝오버)까지
//      안 서고 60초 기한이 지날 수 있다. 큐브(`RummyStoreLobby.lobbyAgain`)는 이미 고쳐져 있었다.
//  (c) 폴링 걸음의 조회가 폴링 작업 **안에서** 돌아, 창을 닫거나 가리는 순간 `stopPolling` 의 취소가 그 조회에 합쳐진 초인종
//      조회(lobbyAgain · inboxAgain · stateAgain)까지 같이 죽인다 — 창을 닫은 신청자는 수락을 몰라 흑이면 첫 수가 자동 착수된다.
//  (d) (c) 를 고치면 날던 조회가 끝까지 가므로, 그 뒤 **남은 걸음**이 가려진 창에서 로비를 새로 내면 안 된다.
//
// 오목은 초인종이 로비가 아니라 **받은함**(`loadInbox` — 이미 `inboxAgain` 으로 합친다)으로 간다. 그래서 오목의 (b) 는
// 초인종이 아닌 다른 계기(판 끝 전적 재조회 · [로비로] · 관전 나가기 · 창 열기)가 겹친 로비이고, (c) 는 보낸 신청 5초 받은함이다.
//
// 하네스: `GomokuStubProtocol`(호스트별 스텁) + `WorkTimerStore` 호스트(실제 `classifyAuthError` — 취소는 nil 로 접힌다).
// 기준선이 짝으로 붙는다(같은 입력에서 겹침·창 닫힘만 다르다).

// MARK: - 하네스

private let ldMe = "00000000-0000-0000-0000-0000000000a1"
private let ldRival = "00000000-0000-0000-0000-0000000000b2"
private let ldGomokuMatch = "1d1d1d1d-2222-3333-4444-555555555555"
private let ldTetrisMatch = "7e7e0000-0000-4000-8000-0000000000d2"

private func ldJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func ldNowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

@MainActor
private enum LDRetention {
    /// 스토어는 호스트를 **약참조**로 든다(제품 계약). 버리면 host 가 nil 이 되어 요청이 한 건도 안 나간다.
    static var owners: [WorkTimerStore] = []
}

@MainActor
private func ldOwner(_ label: String, me: String, handler: @escaping GomokuStubProtocol.Handler) -> (WorkTimerStore, String) {
    let host = "ld-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let owner = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: GomokuTestDefaults.make("ld-lobby-again"), workspaceNotifications: nil)
    owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    LDRetention.owners.append(owner)
    return (owner, host)
}

/// 상한은 재개 횟수다(5ms 한 번 = 한 차례 — 전체 스위트에서 메인 액터가 붐벼도 스토어의 Task 가 차례를 받는다).
@MainActor
private func ldWait(_ resumes: Int = 2_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func ldCount(_ host: String, _ rpc: String) -> Int { GomokuStubProtocol.count(host: host, rpc: rpc) }

/// rpc 이름 → (같은 rpc 의 n 번째 호출 → 본문). 늦춤은 그 rpc 의 모든 호출에 건다. 응답은 **요청이 도착한 순간** 정해진다.
private func ldHandler(_ bodies: [String: @Sendable (Int) -> String], delays: [String: TimeInterval] = [:])
    -> GomokuStubProtocol.Handler {
    { rpc, _, index in
        guard let make = bodies[rpc] else { return nil }
        return GomokuStubProtocol.Reply(body: make(index), delay: delays[rpc] ?? 0)
    }
}

/// 창이 어떻게 내려가는가 — 닫기(최소화·빨간 점) · 가림(다른 전체 화면 앱·다른 스페이스) · 그대로(기준선).
private enum LDWindowExit: CaseIterable {
    case stays, hidden, occluded
}

// MARK: 체스(실서버 픽스처 원문)

private let ldChessFixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/chess-rpc", isDirectory: true)
private let ldChessA = "aa000000-0000-4000-8000-0000000000a1"
private let ldChessB = "bb000000-0000-4000-8000-0000000000b2"
private let ldChessMatch = "9a7156f6-f055-4590-ba98-f537ead0a600"

private func ldChessJSON(_ name: String) throws -> [String: Any] {
    let data = try Data(contentsOf: ldChessFixtures.appendingPathComponent("\(name).json"))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func ldChessText(_ name: String) throws -> String {
    try String(contentsOf: ldChessFixtures.appendingPathComponent("\(name).json"), encoding: .utf8)
}

/// 받은 신청이 **생기기 전** 의 B 로비(= `chess_lobby__ok_pending_in` 에서 incoming_match_id 만 null).
private func ldChessLobbyBeforeInvite() throws -> String {
    var top = try ldChessJSON("chess_lobby__ok_pending_in")
    var me = try #require(top["me"] as? [String: Any])
    me["incoming_match_id"] = NSNull()
    top["me"] = me
    return ldJSON(top)
}

/// pending 상태(신청) — 실제 봉투의 키 그대로 status·흑백·시계만 서버가 pending 에 싣는 모양으로(`V0343ChessStoreTests` ⑬ 과 같은 꼴).
/// `base` 를 부른 사람의 시점이다: their_turn 은 B(받는 쪽), my_turn 은 A(신청자).
private func ldChessPending(_ base: String) throws -> String {
    var pending = try ldChessJSON(base)
    var row = try #require(pending["match"] as? [String: Any])
    row["status"] = "pending"
    for key in ["white", "black", "turn", "white_ms_left", "black_ms_left", "turn_started_ms", "deadline_ms", "started_ms"] {
        row[key] = NSNull()
    }
    row["invite_expires_ms"] = (try #require(pending["server_now_ms"] as? Double)) + 60_000
    pending["match"] = row
    pending["my_color"] = NSNull()
    pending["legal_moves"] = NSNull()
    pending["in_check"] = NSNull()
    pending.removeValue(forKey: "state")
    return ldJSON(pending)
}

@MainActor
private func ldChess(_ label: String, me: String, handler: @escaping GomokuStubProtocol.Handler)
    -> (ChessStore, String, LDArrivals) {
    let (owner, host) = ldOwner(label, me: me, handler: handler)
    let chess = ChessStore(host: owner)
    chess.pollStepSeconds = 3_600
    let arrivals = LDArrivals()
    chess.onInviteArrived = { arrivals.ids.append($0.id) }
    return (chess, host, arrivals)
}

@MainActor
private final class LDArrivals {
    var ids: [String] = []
}

// MARK: 테트리스(서버 jsonb 모양 — `V0360TetrisDuelStoreTests.tdLobby` 와 같은 키)

private func ldTetrisLobby(incoming: [[String: Any]] = [], outgoing: [String: Any]? = nil) -> String {
    ldJSON([
        "status": "ok", "server_now_ms": ldNowMs(), "stakes": [3, 5, 10],
        "me": ["ruby_balance": 100, "wins": 2, "losses": 1, "draws": 0,
               "active_match_id": NSNull(), "incoming": incoming, "outgoing": outgoing.map { $0 as Any } ?? NSNull()],
        "users": [["id": ldRival, "display_name": "라이벌", "avatar_url": NSNull(), "character": "jelly",
                   "is_working": true, "in_match": false, "capable": true, "focus_mode": false]],
        "matches": [] as [Any],
    ])
}

private func ldTetrisInvite(peerKey: String) -> [String: Any] {
    ["match_id": ldTetrisMatch, peerKey: ["id": ldRival, "display_name": "라이벌"], "stake": 3,
     "expires_at_ms": ldNowMs() + 60_000]
}

/// 보낸 신청의 pending 상태(§2.5 키). 들고 있는 보낸 신청과 같은 id 라 아무것도 바꾸지 않는다(로비 재조회도 없다).
private func ldTetrisPendingState() -> String {
    let now = ldNowMs()
    func player(_ id: String, _ name: String) -> [String: Any] {
        ["id": id, "display_name": name, "avatar_url": NSNull(), "character": NSNull(), "ready": false, "seq": 0,
         "board": NSNull(), "lines": 0, "garbage_sent": 0, "garbage_applied": 0, "pending": 0,
         "last_seen_ms": NSNull(), "topped_out": false]
    }
    return ldJSON(["status": "ok", "state": [
        "match_id": ldTetrisMatch, "status": "pending", "stake": 3, "seed": NSNull(), "server_now_ms": now,
        "accepted_at_ms": NSNull(), "start_at_ms": NSNull(), "ready_deadline_ms": NSNull(), "max_end_ms": NSNull(),
        "finished_at_ms": NSNull(), "me": player(ldMe, "나"), "opponent": player(ldRival, "라이벌"),
        "result": NSNull(), "winner": NSNull(), "end_reason": NSNull(), "ruby_balance": 100,
    ] as [String: Any]])
}

@MainActor
private func ldTetris(_ label: String, handler: @escaping GomokuStubProtocol.Handler)
    -> (TetrisDuelStore, String, LDArrivals) {
    let (owner, host) = ldOwner(label, me: ldMe, handler: handler)
    let tetris = TetrisDuelStore(host: owner)
    tetris.pollStepSeconds = 3_600
    tetris.gameLoopStepSeconds = 3_600
    let arrivals = LDArrivals()
    tetris.onInviteArrived = { arrivals.ids.append($0.id) }
    return (tetris, host, arrivals)
}

// MARK: 오목(흉내 서버 — 나는 신청자 흑)

/// 신청 → 수락을 흉내 낸다. 상태(status)는 테스트가 바꾸고, 응답은 요청이 도착한 순간의 상태로 정해진다.
private final class LDGomokuServer: @unchecked Sendable {
    private let lock = NSLock()
    private var status = "pending"

    func accept() {
        lock.lock()
        status = "active"
        lock.unlock()
    }

    private var current: String {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    func inbox() -> String {
        let now = ldNowMs()
        var body: [String: Any] = ["status": "ok", "server_now_ms": now, "ruby_balance": 20, "incoming": [] as [Any]]
        if current == "pending" {
            body["outgoing"] = [
                "match_id": ldGomokuMatch, "stake": 5, "invite_expires_ms": now + 50_000,
                "challenger": ["user_id": ldMe, "display_name": "나"],
                "opponent": ["user_id": ldRival, "display_name": "라이벌"],
            ] as [String: Any]
        } else {
            body["outgoing"] = NSNull()
            body["active_match_id"] = ldGomokuMatch
        }
        return ldJSON(body)
    }

    func state() -> String {
        let now = ldNowMs()
        return ldJSON([
            "status": "ok",
            "match": [
                "id": ldGomokuMatch, "status": current, "stake": 5, "black": ldMe, "white": ldRival,
                "challenger": ldMe, "opponent": ldRival, "move_count": 0, "turn": "black",
                "deadline_ms": now + 30_000, "result": NSNull(), "end_reason": NSNull(), "winner": NSNull(),
                "invite_expires_ms": now + 50_000,
            ] as [String: Any],
            "moves": [] as [Any], "my_color": "black",
            "opponent": ["user_id": ldRival, "display_name": "라이벌", "avatar_url": NSNull(), "character": "aing"],
            "ruby_balance": 15, "server_now_ms": now,
        ])
    }

    static func challenge() -> String {
        let now = ldNowMs()
        return ldJSON(["status": "ok", "match_id": ldGomokuMatch, "invite_expires_ms": now + 50_000,
                       "ruby_balance": 20, "server_now_ms": now])
    }
}

private func ldGomokuLobby(wins: Int) -> String {
    ldJSON(["status": "ok", "server_now_ms": ldNowMs(), "users": [] as [Any],
            "me": ["wins": wins, "losses": 0, "draws": 0, "ruby_balance": 20, "active_match_id": NSNull()]])
}

@MainActor
private final class LDGomokuTally {
    var attentions: [GomokuAttention] = []
    var arrived: [String] = []
}

@MainActor
private func ldGomoku(_ label: String, handler: @escaping GomokuStubProtocol.Handler)
    -> (GomokuStore, String, LDGomokuTally) {
    let (owner, host) = ldOwner(label, me: ldMe, handler: handler)
    let gomoku = owner.gomoku
    gomoku.pollStepSeconds = 3_600
    let tally = LDGomokuTally()
    gomoku.presentWindow = {}
    gomoku.requestAttention = {}
    gomoku.onAttention = { tally.attentions.append($0) }
    gomoku.onInviteArrived = { tally.arrived.append($0.id) }
    return (gomoku, host, tally)
}

// MARK: - 시험

@Suite("결함 ② — 로비를 읽는 중에 온 초인종 합치기 · 폴링 취소 밖 조회 · 가려진 창의 남은 걸음(오목·체스·테트리스)")
@MainActor
struct LobbyDoorbellCoalesceTests {

    // MARK: 체스

    @Test(.gomokuDefaultsCleanup)
    func 체스_도는_로비_중에_온_초인종도_받은_신청을_세운다() async throws {
        let pendingIn = try ldChessText("chess_lobby__ok_pending_in")
        let before = try ldChessLobbyBeforeInvite()
        let pending = try ldChessPending("chess_state__ok_initial_their_turn")   // B 시점(받는 쪽)

        // (a) 기준선: 로비가 안 돌 때 초인종 → 로비 한 번 → 받은 신청 · 말풍선.
        let (base, baseHost, baseArrived) = ldChess("c-base", me: ldChessB, handler: ldHandler(
            ["chess_lobby": { _ in pendingIn }, "chess_state": { _ in pending }]))
        base.handleSignal()
        await ldWait { base.incoming != nil }
        #expect(ldCount(baseHost, "chess_lobby") == 1)
        #expect(base.incoming?.id == ldChessMatch)
        #expect(baseArrived.ids == [ldChessMatch])

        // (b) 결함 갈래: 신청이 생기기 **전에** 읽힌 로비가 날고 있는 동안(팝오버 열기 · 재접속 따라잡기와 겹침) 초인종이 온다.
        let (store, host, arrived) = ldChess("c-drop", me: ldChessB, handler: ldHandler(
            ["chess_lobby": { $0 == 0 ? before : pendingIn }, "chess_state": { _ in pending }],
            delays: ["chess_lobby": 0.4]))
        let first = Task { await store.refreshLobby() }
        await ldWait { ldCount(host, "chess_lobby") == 1 }
        try #require(ldCount(host, "chess_lobby") == 1, "준비: 첫 로비가 날고 있다")
        store.handleSignal()                     // 상대가 막 신청했다는 초인종
        await first.value
        await ldWait(600) { store.incoming != nil }
        #expect(ldCount(host, "chess_lobby") == 2, "초인종이 로비 조회를 한 번도 못 냈다(도는 로비에 삼켜졌다)")
        #expect(store.incoming?.id == ldChessMatch, "받은 신청이 화면·메뉴바 점에 안 섰다")
        #expect(arrived.ids == [ldChessMatch], "말풍선(onInviteArrived)이 안 울렸다")
    }

    @Test(.gomokuDefaultsCleanup, arguments: [LDWindowExit.hidden, LDWindowExit.occluded])
    fileprivate func 체스_폴링_로비에_합쳐진_초인종은_창이_내려가도_나간다(_ exit: LDWindowExit) async throws {
        let pendingIn = try ldChessText("chess_lobby__ok_pending_in")
        let before = try ldChessLobbyBeforeInvite()
        let pending = try ldChessPending("chess_state__ok_initial_their_turn")
        let (store, host, arrived) = ldChess("c-poll-\(exit)", me: ldChessB, handler: ldHandler(
            ["chess_lobby": { $0 == 0 ? before : pendingIn }, "chess_state": { _ in pending }],
            delays: ["chess_lobby": 0.4]))
        store.isWindowVisible = true
        store.pollStepSeconds = 0.02
        store.startPolling()
        await ldWait { ldCount(host, "chess_lobby") == 1 }
        try #require(ldCount(host, "chess_lobby") == 1, "준비: 폴링 걸음의 로비가 날고 있다")
        store.handleSignal()                     // 도는 로비에 합쳐진다
        await ldWait { store.syncTask == nil }
        switch exit {
        case .hidden: store.windowDidHide()      // stopPolling → pollTask.cancel()
        case .occluded: store.windowOcclusionDidChange(visible: false)
        case .stays: break
        }
        #expect(store.pollTask == nil, "창이 내려가면 폴링 작업은 멈춘다")
        await ldWait(600) { store.incoming != nil }
        #expect(ldCount(host, "chess_lobby") == 2, "합쳐진 초인종 조회가 폴링 취소와 함께 죽었다(\(exit))")
        #expect(store.incoming?.id == ldChessMatch, "창을 내린 사람에게 받은 신청이 안 섰다(\(exit))")
        #expect(arrived.ids == [ldChessMatch], "말풍선이 안 울렸다 — 창도 폴링도 없는 사람이 60초 기한을 넘긴다(\(exit))")
    }

    @Test(.gomokuDefaultsCleanup)
    func 체스_가려진_뒤_남은_폴링_걸음이_로비를_새로_내지_않는다() async throws {
        let pending = try ldChessPending("chess_state__ok_initial_my_turn")      // A 시점(신청자)
        let lobby = try ldChessText("chess_lobby__ok_empty")
        let challenge = ldJSON(["status": "ok", "match_id": ldChessMatch, "ruby_balance": 100,
                                "server_now_ms": ldNowMs(), "invite_expires_ms": ldNowMs() + 60_000])
        func make(_ label: String) async throws -> (ChessStore, String) {
            let (store, host, _) = ldChess(label, me: ldChessA, handler: ldHandler(
                ["chess_state": { _ in pending }, "chess_lobby": { _ in lobby }, "chess_challenge": { _ in challenge }],
                delays: ["chess_state": 0.5]))
            await store.challenge(userID: ldChessB)
            try #require(store.outgoing?.id == ldChessMatch && store.phase == .lobby, "준비: 로비 · 보낸 신청 하나")
            store.isWindowVisible = true
            store.lastOutgoingRequestAt = .distantPast
            store.lastLobbyRequestAt = .distantPast
            store.pollStepSeconds = 0.02
            store.startPolling()
            await ldWait { ldCount(host, "chess_state") == 1 }
            try #require(ldCount(host, "chess_state") == 1, "준비: 폴링이 보낸 신청 조회를 냈다")
            return (store, host)
        }

        // 기준선: 보낸 신청 조회(0.5초)가 나는 중 창을 **내린다** → 남은 걸음(로비)은 안 나간다.
        let (base, baseHost) = try await make("c-occl-base")
        base.windowDidHide()
        await ldWait(300) { false }
        #expect(ldCount(baseHost, "chess_lobby") == 0, "기준선: 창을 내린 뒤 남은 걸음이 로비를 불렀다")

        // 같은 순간 창이 **가려진다** → 폴링 작업은 멈췄으니 남은 걸음도 로비를 새로 내면 안 된다.
        let (store, host) = try await make("c-occl")
        store.windowOcclusionDidChange(visible: false)
        #expect(store.pollTask == nil)
        await ldWait(300) { ldCount(host, "chess_lobby") > 0 }
        #expect(ldCount(host, "chess_lobby") == 0, "가려진 창에서 취소된 폴링 걸음이 로비 요청을 새로 냈다")
    }

    // MARK: 테트리스

    @Test(.gomokuDefaultsCleanup)
    func 테트리스_도는_로비_중에_온_초인종도_받은_신청을_세운다() async throws {
        // (a) 기준선.
        let (base, baseHost, baseArrived) = ldTetris("t-base", handler: ldHandler(
            ["tetris_lobby": { _ in ldTetrisLobby(incoming: [ldTetrisInvite(peerKey: "from")]) }]))
        base.handleSignal()
        await ldWait { !base.incoming.isEmpty }
        #expect(ldCount(baseHost, "tetris_lobby") == 1)
        #expect(base.incoming.map(\.id) == [ldTetrisMatch])
        #expect(baseArrived.ids == [ldTetrisMatch])

        // (b) 결함 갈래: 신청 없는 로비가 0.4초 늦게 오는 동안 초인종.
        let (store, host, arrived) = ldTetris("t-drop", handler: ldHandler(
            ["tetris_lobby": { $0 == 0 ? ldTetrisLobby() : ldTetrisLobby(incoming: [ldTetrisInvite(peerKey: "from")]) }],
            delays: ["tetris_lobby": 0.4]))
        let first = Task { await store.refreshLobby() }
        await ldWait { ldCount(host, "tetris_lobby") == 1 }
        try #require(ldCount(host, "tetris_lobby") == 1, "준비: 첫 로비가 날고 있다")
        store.handleSignal()
        await first.value
        await ldWait(600) { !store.incoming.isEmpty }
        #expect(ldCount(host, "tetris_lobby") == 2, "초인종이 로비 조회를 한 번도 못 냈다(도는 로비에 삼켜졌다)")
        #expect(store.incoming.map(\.id) == [ldTetrisMatch], "받은 신청이 화면·메뉴바 점에 안 섰다")
        #expect(arrived.ids == [ldTetrisMatch], "말풍선(onInviteArrived)이 안 울렸다")
    }

    @Test(.gomokuDefaultsCleanup, arguments: [LDWindowExit.hidden, LDWindowExit.occluded])
    fileprivate func 테트리스_폴링_로비에_합쳐진_초인종은_창이_내려가도_나간다(_ exit: LDWindowExit) async throws {
        let (store, host, arrived) = ldTetris("t-poll-\(exit)", handler: ldHandler(
            ["tetris_lobby": { $0 == 0 ? ldTetrisLobby() : ldTetrisLobby(incoming: [ldTetrisInvite(peerKey: "from")]) }],
            delays: ["tetris_lobby": 0.4]))
        store.isWindowVisible = true
        store.pollStepSeconds = 0.02
        store.startPolling()
        await ldWait { ldCount(host, "tetris_lobby") == 1 }
        try #require(ldCount(host, "tetris_lobby") == 1, "준비: 폴링 걸음의 로비가 날고 있다")
        store.handleSignal()
        await ldWait { store.syncTask == nil }
        switch exit {
        case .hidden: store.windowDidHide()
        case .occluded: store.windowOcclusionDidChange(visible: false)
        case .stays: break
        }
        #expect(store.pollTask == nil, "창이 내려가면 폴링 작업은 멈춘다")
        await ldWait(600) { !store.incoming.isEmpty }
        #expect(ldCount(host, "tetris_lobby") == 2, "합쳐진 초인종 조회가 폴링 취소와 함께 죽었다(\(exit))")
        #expect(store.incoming.map(\.id) == [ldTetrisMatch], "창을 내린 사람에게 받은 신청이 안 섰다(\(exit))")
        #expect(arrived.ids == [ldTetrisMatch], "말풍선이 안 울렸다(\(exit))")
    }

    @Test(.gomokuDefaultsCleanup)
    func 테트리스_가려진_뒤_남은_폴링_걸음이_로비를_새로_내지_않는다() async throws {
        let sentLobby = ldTetrisLobby(outgoing: ldTetrisInvite(peerKey: "to"))
        func make(_ label: String) async throws -> (TetrisDuelStore, String) {
            let (store, host, _) = ldTetris(label, handler: ldHandler(
                ["tetris_state": { _ in ldTetrisPendingState() }, "tetris_lobby": { _ in sentLobby }],
                delays: ["tetris_state": 0.5]))
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            await store.applyLobby(try decoder.decode(TetrisLobbyResponse.self, from: Data(sentLobby.utf8)))
            try #require(store.outgoing?.id == ldTetrisMatch && store.phase == .lobby, "준비: 로비 · 보낸 신청 하나")
            store.isWindowVisible = true
            store.lastOutgoingRequestAt = .distantPast
            store.lastLobbyRequestAt = .distantPast
            store.pollStepSeconds = 0.02
            store.startPolling()
            await ldWait { ldCount(host, "tetris_state") == 1 }
            try #require(ldCount(host, "tetris_state") == 1, "준비: 폴링이 보낸 신청 조회를 냈다")
            return (store, host)
        }

        let (base, baseHost) = try await make("t-occl-base")
        base.windowDidHide()
        await ldWait(300) { false }
        #expect(ldCount(baseHost, "tetris_lobby") == 0, "기준선: 창을 내린 뒤 남은 걸음이 로비를 불렀다")

        let (store, host) = try await make("t-occl")
        store.windowOcclusionDidChange(visible: false)
        #expect(store.pollTask == nil)
        await ldWait(300) { ldCount(host, "tetris_lobby") > 0 }
        #expect(ldCount(host, "tetris_lobby") == 0, "가려진 창에서 취소된 폴링 걸음이 로비 요청을 새로 냈다")
    }

    // MARK: 오목

    @Test(.gomokuDefaultsCleanup)
    func 오목_초인종은_받은함으로_가서_도는_로비에_안_삼켜진다() async throws {
        // 오목은 초인종이 로비가 아니라 받은함으로 간다(이미 `inboxAgain` 으로 합친다) — 고치기 전에도 초록이어야 하는 확인 항목.
        let incoming = ldJSON(["status": "ok", "server_now_ms": ldNowMs(), "ruby_balance": 20, "outgoing": NSNull(),
                               "incoming": [["match_id": ldGomokuMatch, "stake": 5, "invite_expires_ms": ldNowMs() + 50_000,
                                             "challenger": ["user_id": ldRival, "display_name": "라이벌"],
                                             "opponent": ["user_id": ldMe, "display_name": "나"]]]])
        let (store, host, tally) = ldGomoku("g-signal", handler: ldHandler(
            ["gomoku_lobby": { _ in ldGomokuLobby(wins: 0) }, "gomoku_inbox": { _ in incoming }],
            delays: ["gomoku_lobby": 0.4]))
        let first = Task { await store.refreshLobby() }
        await ldWait { ldCount(host, "gomoku_lobby") == 1 }
        store.handleSignal()
        await ldWait(600) { !store.incoming.isEmpty }
        await first.value
        #expect(ldCount(host, "gomoku_inbox") == 1)
        #expect(store.incoming.map(\.id) == [ldGomokuMatch])
        #expect(tally.arrived == [ldGomokuMatch])
    }

    @Test(.gomokuDefaultsCleanup)
    func 오목_도는_로비_중_겹친_로비_계기는_뒤따르는_한_번으로_간다() async throws {
        // 겹친 계기: 판이 끝난 순간 전적 재조회 · [로비로] · 관전 나가기 · 창 열기. 두 번째 응답만 새 전적(1승)을 안다.
        func make(_ label: String) -> (GomokuStore, String) {
            let (store, host, _) = ldGomoku(label, handler: ldHandler(
                ["gomoku_lobby": { ldGomokuLobby(wins: $0 == 0 ? 0 : 1) }], delays: ["gomoku_lobby": 0.4]))
            return (store, host)
        }
        // (a) 기준선: 겹치지 않으면 두 번 읽고 새 전적이 선다.
        let (base, baseHost) = make("g-lobby-base")
        await base.refreshLobby()
        await base.refreshLobby()
        #expect(ldCount(baseHost, "gomoku_lobby") == 2)
        #expect(base.record?.wins == 1)

        // (b) 겹치면: 앞 조회가 도는 중에 온 계기가 빠져, 전적·대결 중 목록·진행 판 id 가 다음 30초 폴링까지 옛것이다.
        let (store, host) = make("g-lobby-drop")
        let first = Task { await store.refreshLobby() }
        await ldWait { ldCount(host, "gomoku_lobby") == 1 }
        try #require(ldCount(host, "gomoku_lobby") == 1, "준비: 첫 로비가 날고 있다")
        await store.refreshLobby()
        await first.value
        await ldWait(600) { store.record?.wins == 1 }
        #expect(ldCount(host, "gomoku_lobby") == 2, "겹친 로비 계기가 조회를 한 번도 못 냈다")
        #expect(store.record?.wins == 1, "판이 끝난 뒤의 전적이 안 섰다")
    }

    @Test(.gomokuDefaultsCleanup, arguments: LDWindowExit.allCases)
    fileprivate func 오목_보낸_신청_폴링에_합쳐진_수락_초인종은_창이_내려가도_판을_연다(_ exit: LDWindowExit) async throws {
        // 신청자(흑)가 보낸 신청 5초 받은함 폴링이 나는 중에 수락 초인종이 와서 합쳐지고, 그 순간 창을 내린다.
        // 기준선(.stays)은 고치기 전에도 초록이다 — `inboxAgain` 은 있었다. 창을 내리면 폴링 취소가 합쳐진 조회까지 죽였다.
        let server = LDGomokuServer()
        let (store, host, tally) = ldGomoku("g-poll-\(exit)", handler: ldHandler(
            ["gomoku_inbox": { _ in server.inbox() }, "gomoku_state": { _ in server.state() },
             "gomoku_challenge": { _ in LDGomokuServer.challenge() }, "gomoku_lobby": { _ in ldGomokuLobby(wins: 0) }],
            delays: ["gomoku_inbox": 0.4]))
        await store.challenge(userID: ldRival)
        try #require(store.outgoing?.id == ldGomokuMatch, "준비: 보낸 신청 하나")
        store.isWindowVisible = true
        store.lastInboxRequestAt = .distantPast
        store.lastLobbyRequestAt = Date()        // 로비 걸음은 이 시험 밖
        store.pollStepSeconds = 0.02
        store.startPolling()
        await ldWait { ldCount(host, "gomoku_inbox") == 1 }
        try #require(ldCount(host, "gomoku_inbox") == 1, "준비: 폴링 걸음의 받은함이 날고 있다")
        server.accept()                          // 상대가 수락했다(서버)
        store.handleSignal()                     // 수락 초인종 — 도는 받은함에 합쳐진다
        await ldWait { store.syncTask == nil }
        switch exit {
        case .hidden: store.windowDidHide()
        case .occluded: store.windowOcclusionDidChange(visible: false)
        case .stays: break
        }
        await ldWait(800) { store.match?.id == ldGomokuMatch }
        #expect(ldCount(host, "gomoku_inbox") == 2, "합쳐진 수락 초인종의 받은함이 안 나갔다(\(exit))")
        #expect(store.match?.id == ldGomokuMatch, "수락된 판이 안 열렸다 — 흑이면 30초 뒤 첫 수가 자동 착수된다(\(exit))")
        if exit == .hidden {
            #expect(tally.attentions.map(\.kind) == [.matchStarted], "창을 닫은 신청자에게 판 시작 말풍선이 안 떴다")
        }
        store.stopPolling()
    }

    @Test(.gomokuDefaultsCleanup)
    func 오목_가려진_뒤_남은_폴링_걸음이_로비를_새로_내지_않는다() async throws {
        let server = LDGomokuServer()
        func make(_ label: String) async throws -> (GomokuStore, String) {
            let (store, host, _) = ldGomoku(label, handler: ldHandler(
                ["gomoku_inbox": { _ in server.inbox() }, "gomoku_challenge": { _ in LDGomokuServer.challenge() },
                 "gomoku_lobby": { _ in ldGomokuLobby(wins: 0) }],
                delays: ["gomoku_inbox": 0.5]))
            await store.challenge(userID: ldRival)
            try #require(store.outgoing?.id == ldGomokuMatch && store.phase == .lobby, "준비: 로비 · 보낸 신청 하나")
            store.isWindowVisible = true
            store.lastInboxRequestAt = .distantPast
            store.lastLobbyRequestAt = .distantPast
            store.pollStepSeconds = 0.02
            store.startPolling()
            await ldWait { ldCount(host, "gomoku_inbox") == 1 }
            try #require(ldCount(host, "gomoku_inbox") == 1, "준비: 폴링이 보낸 신청 받은함을 냈다")
            return (store, host)
        }

        let (base, baseHost) = try await make("g-occl-base")
        base.windowDidHide()
        await ldWait(300) { false }
        #expect(ldCount(baseHost, "gomoku_lobby") == 0, "기준선: 창을 내린 뒤 남은 걸음이 로비를 불렀다")

        let (store, host) = try await make("g-occl")
        store.windowOcclusionDidChange(visible: false)
        #expect(store.pollTask == nil)
        await ldWait(300) { ldCount(host, "gomoku_lobby") > 0 }
        #expect(ldCount(host, "gomoku_lobby") == 0, "가려진 창에서 취소된 폴링 걸음이 로비 요청을 새로 냈다")
    }

    // MARK: 로그아웃은 합치기 깃발도 비운다

    @Test(.gomokuDefaultsCleanup)
    func 로그아웃이_도는_로비의_뒤따르는_한_번을_다음_사람에게_넘기지_않는다() async throws {
        // 세 스토어 모두: 로비가 도는 중 초인종(합침) → reset → 앞 조회의 응답은 세대로 버리고, 뒤따르는 한 번도 나가지 않는다.
        let pendingIn = try ldChessText("chess_lobby__ok_pending_in")
        let (chess, chessHost, _) = ldChess("c-reset", me: ldChessB, handler: ldHandler(
            ["chess_lobby": { _ in pendingIn }], delays: ["chess_lobby": 0.4]))
        let chessFirst = Task { await chess.refreshLobby() }
        await ldWait { ldCount(chessHost, "chess_lobby") == 1 }
        chess.handleSignal()
        await ldWait { chess.syncTask == nil }
        chess.reset()
        await chessFirst.value
        await ldWait(200) { ldCount(chessHost, "chess_lobby") > 1 }
        #expect(ldCount(chessHost, "chess_lobby") == 1, "로그아웃 뒤에 앞 사람의 뒤따르는 로비가 나갔다")
        #expect(chess.incoming == nil)

        let (tetris, tetrisHost, _) = ldTetris("t-reset", handler: ldHandler(
            ["tetris_lobby": { _ in ldTetrisLobby(incoming: [ldTetrisInvite(peerKey: "from")]) }],
            delays: ["tetris_lobby": 0.4]))
        let tetrisFirst = Task { await tetris.refreshLobby() }
        await ldWait { ldCount(tetrisHost, "tetris_lobby") == 1 }
        tetris.handleSignal()
        await ldWait { tetris.syncTask == nil }
        tetris.reset()
        await tetrisFirst.value
        await ldWait(200) { ldCount(tetrisHost, "tetris_lobby") > 1 }
        #expect(ldCount(tetrisHost, "tetris_lobby") == 1, "로그아웃 뒤에 앞 사람의 뒤따르는 로비가 나갔다")
        #expect(tetris.incoming.isEmpty)
    }
}
