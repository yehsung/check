import Foundation
import Testing
@testable import check

// v0.3.27 — 실시간 'gomoku' 신호 라우팅.
//
// 채널은 여전히 poke:<uid> 하나이고 라이브 전송자도 CheckApp 한 곳이다(RealtimeLinkTests 가 그대로 지킨다).
// 바뀐 것은 링의 브로드캐스트 가지 하나다: 이벤트 이름이 'gomoku' 면 `.gomokuSignal`(오목 재조회),
// 그 밖(‘ring’·빈 이름·모르는 이름)은 예전 그대로 `.drain`(take_pokes).

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let me = "00000000-0000-0000-0000-0000000000a1"
private let matchID = "11111111-2222-3333-4444-555555555555"

private func subscribed() -> RealtimeLink {
    var link = RealtimeLink(transportAvailable: true)
    _ = link.apply(.signedIn(accessToken: "tok"), now: t0, jitter: { $0 })
    _ = link.apply(.transport(.joined), now: t0, jitter: { $0 })
    return link
}

private func jsonText(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

@MainActor
private func makeRealtimeGomokuStore(
    _ label: String,
    handler: @escaping GomokuStubProtocol.Handler
) -> (WorkTimerStore, FakeRealtimeTransport, String) {
    let host = "v0327-rt-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: GomokuStubProtocol.session()
    )
    let transport = FakeRealtimeTransport()
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0327-rt"),
        workspaceNotifications: nil,
        realtimeTransport: transport
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    return (store, transport, host)
}

@MainActor
private func realtimeWait(_ timeout: TimeInterval = 60, _ condition: @MainActor () -> Bool) async {
    // 상한은 벽시계가 아니라 **재개 횟수**다(5ms 한 번 = 한 차례). 전체 스위트에서는 렌더 테스트가 메인 액터를 수십 초씩 쥐어
    // 벽시계 상한이 스토어의 Task 가 차례를 받기도 전에 끝났다(0.3.27 전체 실행: 690초 지점에서 20초 대기 실패, 격리 3/3 초록).
    // V0325TooltipTests.waitUntil 과 같은 해법 — 재개마다 메인 액터 차례를 거치므로 스토어의 Task 도 같은 줄에서 순서를 받는다.
    for _ in 0..<Int(timeout * 200) {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func inboxReply(delay: TimeInterval = 0) -> GomokuStubProtocol.Reply {
    GomokuStubProtocol.Reply(body: #"{"status":"ok","incoming":[],"outgoing":null}"#, delay: delay)
}

// MARK: - 순수 링

@Test(.gomokuDefaultsCleanup)
func 오목_브로드캐스트만_gomokuSignal_이고_나머지는_전부_drain_이다() {
    #expect(RealtimeLinkConstants.gomokuBroadcastEvent == "gomoku")

    var link = subscribed()
    #expect(link.apply(.transport(.broadcast(event: "gomoku")), now: t0 + 1, jitter: { $0 }) == [.gomokuSignal])
    // 오목 신호도 소켓이 살아 있다는 증거다(좀비 판정 시계를 민다).
    #expect(link.state == .subscribed(since: t0, lastHeardAt: t0 + 1))
    #expect(link.apply(.transport(.broadcast(event: "ring")), now: t0 + 2, jitter: { $0 }) == [.drain])
    #expect(link.apply(.transport(.broadcast(event: "")), now: t0 + 3, jitter: { $0 }) == [.drain])
    // 문자 그대로만 가른다 — 대소문자가 다르면 오목이 아니다(모르는 이름은 예전처럼 drain).
    #expect(link.apply(.transport(.broadcast(event: "GOMOKU")), now: t0 + 4, jitter: { $0 }) == [.drain])

    // 구독 전에는 어떤 이름이든 아무것도 시키지 않는다.
    var connecting = RealtimeLink(transportAvailable: true)
    _ = connecting.apply(.signedIn(accessToken: "tok"), now: t0, jitter: { $0 })
    #expect(connecting.apply(.transport(.broadcast(event: "gomoku")), now: t0 + 1, jitter: { $0 }) == [])
    var disabled = RealtimeLink(transportAvailable: false)
    #expect(disabled.apply(.transport(.broadcast(event: "gomoku")), now: t0, jitter: { $0 }) == [])
}

@Test(.gomokuDefaultsCleanup)
func 프레임_해석은_오목_이벤트_이름을_그대로_넘긴다() {
    let text = jsonText([
        "topic": "realtime:poke:me",
        "event": "broadcast",
        "payload": ["event": "gomoku", "type": "broadcast", "payload": ["v": 1, "m": matchID, "s": 7]]
    ])
    #expect(RealtimeFrame.decode(text: text, channel: "poke:me", joinRef: "1") == .broadcast(event: "gomoku"))
}

// MARK: - 스토어 배선 (Fake 전송자 — 소켓 0개)

@MainActor
@Test(.gomokuDefaultsCleanup)
func 조인_따라잡기는_인박스를_한_번_보고_오목_신호는_take_pokes_를_부르지_않는다() async {
    let (store, transport, host) = makeRealtimeGomokuStore("wiring") { rpc, _, _ in
        rpc == "gomoku_inbox" ? inboxReply() : nil
    }
    func inbox() -> Int { GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") }
    func pokes() -> Int { GomokuStubProtocol.count(host: host, rpc: "take_pokes") }
    store.startedAt = Date()
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await realtimeWait { inbox() >= 1 && pokes() >= 1 }
    await realtimeWait { store.realtime.catchUpTask == nil && store.drainInFlight == nil }
    try? await Task.sleep(for: .milliseconds(100))
    #expect(inbox() == 1, "조인 직후 오목 인박스 따라잡기는 정확히 한 번")
    let pokesAfterJoin = pokes()
    #expect(pokesAfterJoin == 1)

    transport.emit(.broadcast(event: "gomoku"))
    await realtimeWait { inbox() == 2 }
    await realtimeWait { store.gomoku.syncTask == nil }
    #expect(inbox() == 2)
    #expect(pokes() == pokesAfterJoin, "오목 신호가 take_pokes 를 쐈다(원자 소비 RPC 를 수마다 한 번씩 더 쏘게 된다)")

    transport.emit(.broadcast(event: "ring"))
    await realtimeWait { pokes() == pokesAfterJoin + 1 }
    await realtimeWait { store.drainInFlight == nil }
    #expect(pokes() == pokesAfterJoin + 1, "찌르기 초인종은 예전 그대로 drain 이다")
    #expect(inbox() == 2, "찌르기 초인종이 오목 조회를 불렀다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 대국_중_신호는_인박스가_아니라_그_판의_새_수를_읽는다() async {
    let (store, transport, host) = makeRealtimeGomokuStore("in-match") { rpc, _, _ in
        guard rpc == "gomoku_state" else { return rpc == "gomoku_inbox" ? inboxReply() : nil }
        return GomokuStubProtocol.Reply(body: jsonText([
            "status": "ok",
            "match": ["id": matchID, "status": "active", "stake": 5, "black": me,
                      "white": "00000000-0000-0000-0000-0000000000b2", "move_count": 2, "turn": "black"],
            "moves": [["seq": 2, "color": "white", "x": 8, "y": 7]],
            "my_color": "black"
        ]))
    }
    store.gomoku.applyState(GomokuStatePayload(
        match: GomokuMatchRow(id: matchID, status: "active", stake: 5, black: me,
                              white: "00000000-0000-0000-0000-0000000000b2", moveCount: 1, turn: "white"),
        moves: [GomokuMoveRow(seq: 1, color: "black", kind: "stone", x: 7, y: 7)],
        myColor: "black"
    ))
    #expect(store.gomoku.match?.moveCount == 1)
    store.startedAt = Date()
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await realtimeWait { store.realtime.catchUpTask == nil }
    await realtimeWait { store.gomoku.match?.moveCount == 2 }
    let inboxBefore = GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox")
    let statesBefore = GomokuStubProtocol.count(host: host, rpc: "gomoku_state")

    transport.emit(.broadcast(event: "gomoku"))
    await realtimeWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == statesBefore + 1 }
    await realtimeWait { store.gomoku.syncTask == nil }

    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == statesBefore + 1)
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") == inboxBefore)
    let since = GomokuStubProtocol.calls(host: host, rpc: "gomoku_state").last?.json["p_since_seq"] as? Int
    #expect(since == 2, "들고 있는 판 뒤의 수만 묻는다")
    #expect(store.gomoku.match?.board[GomokuPoint(x: 8, y: 7)!] == .white)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 조회_중에_몰려온_신호는_뒤따르는_한_번으로_합친다() async {
    let (store, _, host) = makeRealtimeGomokuStore("coalesce") { rpc, _, _ in
        rpc == "gomoku_inbox" ? inboxReply(delay: 0.3) : nil
    }
    let gomoku = store.gomoku
    gomoku.handleSignal()
    await realtimeWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") == 1 }
    gomoku.handleSignal()
    gomoku.handleSignal()
    gomoku.handleSignal()
    await realtimeWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") >= 2 }
    await realtimeWait { gomoku.syncTask == nil }
    try? await Task.sleep(for: .milliseconds(400))
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") == 2,
            "인플라이트 중 신호 셋은 트레일링 한 번이어야 한다(버리면 유실, 셋 다 쏘면 낭비)")
}

/// 전송자 없는 스토어(킬스위치로 리얼타임을 끈 맥과 같은 모양).
@MainActor
private func makeKillSwitchGomokuStore(
    _ label: String,
    handler: @escaping GomokuStubProtocol.Handler
) -> (WorkTimerStore, String) {
    let host = "v0327-ks-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: GomokuStubProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0327-ks"),
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    return (store, host)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 전송자가_없는_맥은_깨어나면_근무_중인_주인일_때만_오목을_다시_본다() async {
    let (store, host) = makeKillSwitchGomokuStore("wake") { rpc, _, _ in
        rpc == "gomoku_inbox" ? inboxReply() : nil
    }
    func inbox() -> Int { GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") }
    #expect(store.realtime.transportAvailable == false)

    // 비근무: 신청이 올 수 없는 맥이다.
    store.realtimeApply(.didWake, at: t0)
    try? await Task.sleep(for: .milliseconds(150))
    #expect(inbox() == 0)

    // 흡수 세션(주인은 다른 맥).
    store.startedAt = Date()
    store.adoptedRemoteSession = true
    store.realtimeApply(.didWake, at: t0)
    try? await Task.sleep(for: .milliseconds(150))
    #expect(inbox() == 0)

    // 근무 중인 주인 맥 — 조인이 없으니 깨어남이 직접 한 번 본다.
    store.adoptedRemoteSession = false
    store.realtimeApply(.didWake, at: t0)
    await realtimeWait { inbox() == 1 }
    #expect(inbox() == 1)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 전송자가_있는_맥은_깨어남이_아니라_재조인_따라잡기가_오목을_본다() async {
    // 깨움 결합 게이트 계약(V0238ClockTests): 조인 뒤에 본문 밖 요청이 더 나가면 안 된다.
    // 그래서 `.didWake` 는 직접 조회하지 않고, 재조인이 성공한 `.catchUp` 이 한 번 본다.
    let (store, transport, host) = makeRealtimeGomokuStore("wake-online") { rpc, _, _ in
        rpc == "gomoku_inbox" ? inboxReply() : nil
    }
    func inbox() -> Int { GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") }
    store.startedAt = Date()
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await realtimeWait { inbox() == 1 }
    await realtimeWait { store.realtime.catchUpTask == nil && store.drainInFlight == nil }

    store.realtimeApply(.willSleep, at: t0)
    store.realtimeApply(.didWake, at: t0.addingTimeInterval(60))
    if case .connecting = store.realtimeState {} else {
        Issue.record("깨어났는데 재조인이 시작되지 않았다: \(store.realtimeState)")
    }
    try? await Task.sleep(for: .milliseconds(200))
    #expect(inbox() == 1, "전송자가 있는데 깨어남이 조인 전에 직접 조회했다")

    transport.emit(.joined)
    await realtimeWait { inbox() == 2 }
    #expect(inbox() == 2, "재조인 따라잡기가 오목을 보지 않았다")
}

@Test(.gomokuDefaultsCleanup)
func 오목_라우팅_배선은_소스에_그대로_있다() throws {
    let realtime = gomokuCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source("WorkTimerStoreRealtime.swift")))
    #expect(realtime.contains("case .gomokuSignal: gomoku.handleSignal()"))
    #expect(realtime.contains("case .catchUp: startCatchUp() gomoku.realtimeDidJoin()"))
    #expect(realtime.contains(
        "if case .didWake = event, realtimeMayConsumePokes, !realtime.transportAvailable { gomoku.systemDidWake() }"))
    // `.drain` 가지는 근무 게이트 뒤에 그대로다(오목이 그 게이트를 풀지 않았다).
    #expect(realtime.contains("case .drain: guard realtimeMayConsumePokes else { continue } requestDrain()"))

    let link = gomokuCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source("RealtimeLink.swift")))
    #expect(link.contains("if event == RealtimeLinkConstants.gomokuBroadcastEvent { return [.gomokuSignal] } return [.drain]"))
    // 채널은 여전히 하나다.
    #expect(link.contains("static func pokeChannel(userID: String) -> String { \"poke:\\(userID)\" }"))
}
