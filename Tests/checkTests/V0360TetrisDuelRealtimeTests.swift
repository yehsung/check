import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.60 — 1:1 테트리스 **초인종 경로**: 링 이름 분기 · 맥 라우팅(WorkTimerStore) · 맥 소유 배선(소스 계약).
// 폰 러너의 '비워 둔 가지'는 CheckMobileKitTests/BaseRealtimeRunnerTests 에서 잰다.
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).

private let trT0 = Date(timeIntervalSince1970: 1_800_000_000)
private let trMe = "00000000-0000-0000-0000-0000000000a1"

private func trSubscribedLink() -> RealtimeLink {
    var link = RealtimeLink(transportAvailable: true)
    _ = link.apply(.signedIn(accessToken: "tok"), now: trT0, jitter: { $0 })
    _ = link.apply(.transport(.joined), now: trT0, jitter: { $0 })
    return link
}

@MainActor
private func trWait(_ resumes: Int = 2_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func trCollapsed(_ source: String) -> String {
    source.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func trCount(_ needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
}

// MARK: - 링: 'tetris' 는 자기 갈래이고 drain 으로 새지 않는다

/// 없으면: 'tetris' 가 '모르는 이름' 과 같은 갈래로 떨어져 **초인종마다 take_pokes 가 한 번씩 더** 나가고
/// (판 중 공격마다 울린다) 소켓은 테트리스 상태를 한 번도 당기지 않는다.
@Test
func theTetrisRingIsItsOwnBranchAndNotATakePokesDrain() {
    #expect(RealtimeLinkConstants.tetrisBroadcastEvent == "tetris",
            "서버 `tetris__ring` 의 realtime.send(…, 'tetris', …) 와 글자가 달라졌다")
    var link = trSubscribedLink()
    #expect(link.apply(.transport(.broadcast(event: "tetris")), now: trT0 + 1, jitter: { $0 }) == [.tetrisSignal])
    // 테트리스 신호도 소켓이 살아 있다는 증거다(좀비 판정 시계를 민다).
    #expect(link.state == .subscribed(since: trT0, lastHeardAt: trT0 + 1))

    // ★ 기준선이 갈린다: 다섯 이름이 다섯 갈래다(모르는 이름은 예전 그대로 drain).
    let unknown = link.apply(.transport(.broadcast(event: "모르는이름")), now: trT0 + 2, jitter: { $0 })
    let chess = link.apply(.transport(.broadcast(event: "chess")), now: trT0 + 3, jitter: { $0 })
    let gomoku = link.apply(.transport(.broadcast(event: "gomoku")), now: trT0 + 4, jitter: { $0 })
    let read = link.apply(.transport(.broadcast(event: "message_read")), now: trT0 + 5, jitter: { $0 })
    #expect(unknown == [.drain] && chess == [.chessSignal] && gomoku == [.gomokuSignal] && read == [.messageReadSignal])
    #expect(Set([[RealtimeEffect.tetrisSignal], unknown, chess, gomoku, read].map { "\($0)" }).count == 5)
    // 문자 그대로만 가른다.
    #expect(link.apply(.transport(.broadcast(event: "TETRIS")), now: trT0 + 6, jitter: { $0 }) == [.drain])

    // 구독 전에는 어떤 이름이든 아무것도 시키지 않는다.
    var connecting = RealtimeLink(transportAvailable: true)
    _ = connecting.apply(.signedIn(accessToken: "tok"), now: trT0, jitter: { $0 })
    #expect(connecting.apply(.transport(.broadcast(event: "tetris")), now: trT0 + 1, jitter: { $0 }) == [])

    // 프레임 해석이 이름을 그대로 넘긴다(서버 페이로드 {v,m,s} + realtime 이 붙이는 id).
    let text = String(decoding: try! JSONSerialization.data(withJSONObject: [
        "topic": "realtime:poke:me", "event": "broadcast",
        "payload": ["event": "tetris", "type": "broadcast",
                    "payload": ["v": 1, "m": "7e7e0000-0000-4000-8000-000000000060", "s": 4, "id": "x"]],
    ]), as: UTF8.self)
    #expect(RealtimeFrame.decode(text: text, channel: "poke:me", joinRef: "1") == .broadcast(event: "tetris"))
}

// MARK: - 맥 라우팅: 테트리스 스토어까지 간다, take_pokes 는 부르지 않는다

/// 없으면: 라우팅 가지가 비어 있어도(또는 drain 으로 새도) 스토어 테스트는 전부 초록이다 — 소켓 신호가 스토어에 닿는지는
/// 이 자리만 잰다. 조인 직후 따라잡기에 테트리스가 빠지면 소켓이 끊겼던 사이의 신청을 창을 열 때까지 모른다.
@MainActor
@Test(.gomokuDefaultsCleanup)
func theTetrisSignalRefetchesTetrisAndNeverConsumesPokes() async {
    let host = "v0360-tr-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host) { rpc, _, _ in
        switch rpc {
        case "tetris_lobby":
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","me":{"incoming":[],"outgoing":null},"users":[],"matches":[]}"#)
        case "chess_lobby":
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","users":[],"matches":[]}"#)
        case "gomoku_inbox":
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","incoming":[],"outgoing":null}"#)
        default:
            return nil
        }
    }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
        session: GomokuStubProtocol.session())
    let transport = FakeRealtimeTransport()
    let store = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0360-tr"), workspaceNotifications: nil,
        realtimeTransport: transport)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: trMe)
    store.startedAt = Date()                      // 소비할 수 있는 맥(그래도 테트리스는 take_pokes 를 안 쓴다)
    store.startRealtimeIfPossible()
    transport.emit(.joined)

    func lobby() -> Int { GomokuStubProtocol.count(host: host, rpc: "tetris_lobby") }
    func pokes() -> Int { GomokuStubProtocol.count(host: host, rpc: "take_pokes") }
    await trWait { lobby() >= 1 }
    #expect(lobby() == 1, "조인 따라잡기가 테트리스를 보지 않았다 — 끊겼던 사이의 신청을 영영 모른다")
    #expect(store.tetris.hasLoadedLobby, "로비 응답이 테트리스 스토어에 닿지 않았다")
    await trWait { store.tetris.syncTask == nil && store.realtime.catchUpTask == nil && store.drainInFlight == nil }
    let afterJoin = pokes()

    // 테트리스 초인종 → 테트리스 재조회 1회, take_pokes 0회.
    transport.emit(.broadcast(event: "tetris"))
    await trWait { lobby() >= 2 }
    #expect(lobby() == 2, "테트리스 초인종이 테트리스 상태를 안 당긴다")
    try? await Task.sleep(for: .milliseconds(100))
    #expect(pokes() == afterJoin, "테트리스 초인종마다 take_pokes 가 한 번씩 더 나간다")

    // ★ 기준선: **모르는 이름**은 예전처럼 take_pokes 로 간다(그래야 위 0 이 뜻을 가진다).
    transport.emit(.broadcast(event: "모르는이름"))
    await trWait { pokes() > afterJoin }
    #expect(pokes() == afterJoin + 1, "모르는 이름이 take_pokes 로 안 간다 — 이 시험의 대조가 죽었다")
    #expect(lobby() == 2)
    store.tetris.reset()
    store.chess.reset()
    store.gomoku.reset()
}

// MARK: - 맥 소유 배선(소스 계약 — 문이 옵셔널이 아니라 '빠져도 초록' 인 자리들)

/// 없으면: 소유자가 `reset()` 을 빠뜨리면 다음 사람이 앞 계정의 판을 보고, 차단 거울을 빠뜨리면 차단한 사람의 신청이
/// 배너에 뜨고, 팝오버 계기를 빠뜨리면 창을 안 연 사람에게 신청이 안 닿는다 — 셋 다 스토어 테스트는 초록이다.
@Test
func theMacOwnerWiresTheTetrisStoreLikeChess() throws {
    let owner = trCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source("WorkTimerStore.swift")))
    #expect(owner.contains("let tetris: TetrisDuelStore"))
    #expect(owner.contains("self.tetris = TetrisDuelStore()"))
    #expect(owner.contains("tetris.attach(host: self)"))
    #expect(trCount("tetris.reset()", in: owner) == 2, "로그아웃·계정 전환 두 길에서 모두 내려야 한다")
    #expect(owner.contains("if tetris.hiddenPeerIDs != blockHiddenPeerIDs { tetris.hiddenPeerIDs = blockHiddenPeerIDs }"))
    #expect(owner.contains("tetris.refreshLobbyIfStale()"), "팝오버 열기 계기에 테트리스가 없다")

    let realtime = trCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source("WorkTimerStoreRealtime.swift")))
    #expect(realtime.contains("case .tetrisSignal: tetris.handleSignal()"),
            "테트리스 신호 가지가 없다 — 초인종마다 take_pokes 가 샌다")
    #expect(realtime.contains("chess.realtimeDidJoin() tetris.realtimeDidJoin()"), "조인 직후 따라잡기에 테트리스가 없다")
    #expect(realtime.contains("if case .didWake = event, !realtime.transportAvailable { tetris.systemDidWake() }"),
            "전송자 없는 맥의 깨어남이 테트리스를 안 본다")

    let link = trCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source("RealtimeLink.swift")))
    // 오목·체스·drain 이 한 문장으로 붙은 기존 계약(V0327)을 지키며 그 **앞**에 선다.
    #expect(link.contains("if event == RealtimeLinkConstants.tetrisBroadcastEvent { return [.tetrisSignal] } "
                          + "if event == RealtimeLinkConstants.gomokuBroadcastEvent { return [.gomokuSignal] }"))
}
