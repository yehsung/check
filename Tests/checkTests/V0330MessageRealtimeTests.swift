import Foundation
import Testing
@testable import check

// v0.3.30 — 근무 밖 메시지 수신: 소켓 기준(로그인) · 소비 분기(take_pokes vs 요약) · 'message_read' 가지 · 근무 시작 따라잡기.
//
// 서버가 send_message·오목 신청의 근무 조건을 지웠다(SPEC-wave1 §1.1·§1.3). 서버만 풀면 맥이 못 듣는다 —
// 소켓이 근무 중에만 붙고(v0.2.34) take_pokes 도 근무 중에만 나갔기 때문이다. 이 파일이 그 수신판 두 겹을 잰다:
//  ① 소켓은 로그인이면 붙는다(비근무·흡수 세션 포함).
//  ② 초인종은 소비할 수 있는 맥만 take_pokes 로, 나머지는 **요약 조회**로 간다(집 맥이 회사 맥의 찌르기를 훔치지 않게).
//  ③ 'message_read' 는 이름으로 갈라 take_pokes 로 보내지 않는다. 모르는 이름은 예전처럼 drain 이다.
//  ④ 소비할 수 없던 동안 진 빚은 소비할 수 있게 되는 순간 **정확히 한 번** 갚는다.

private let v0330T0 = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
private func v0330RealtimeStore(
    _ label: String,
    handler: @escaping MessageReadStubProtocol.Handler = { call, _ in
        call.rpc == "message_unread_summary" ? MessageReadFixture.summaryReply([]) : nil
    }
) -> (WorkTimerStore, FakeRealtimeTransport, String) {
    let transport = FakeRealtimeTransport()
    let (store, host) = makeMessageReadStore(label, transport: transport, handler: handler)
    return (store, transport, host)
}

@MainActor
private func v0330Count(_ host: String, _ rpc: String) -> Int {
    MessageReadStubProtocol.count(host: host, rpc: rpc)
}

// MARK: - 순수 링

@Test
func 읽음_신호는_이름으로_갈라_drain_으로_보내지_않는다() {
    #expect(RealtimeLinkConstants.messageReadBroadcastEvent == "message_read")
    var link = RealtimeLink(transportAvailable: true)
    _ = link.apply(.signedIn(accessToken: "tok"), now: v0330T0, jitter: { $0 })
    _ = link.apply(.transport(.joined), now: v0330T0, jitter: { $0 })

    #expect(link.apply(.transport(.broadcast(event: "message_read")), now: v0330T0 + 1, jitter: { $0 }) == [.messageReadSignal])
    // 읽음 신호도 소켓이 살아 있다는 증거다(좀비 판정 시계를 민다).
    #expect(link.state == .subscribed(since: v0330T0, lastHeardAt: v0330T0 + 1))
    // 문자 그대로만 가른다. 모르는 이름·대소문자 다른 이름·빈 이름은 **예전 그대로 drain** 이다 — 모르는 이름을 버리면
    // 서버가 이벤트 이름을 바꾸는 날 찌르기가 조용히 끊긴다.
    #expect(link.apply(.transport(.broadcast(event: "MESSAGE_READ")), now: v0330T0 + 2, jitter: { $0 }) == [.drain])
    #expect(link.apply(.transport(.broadcast(event: "ring")), now: v0330T0 + 3, jitter: { $0 }) == [.drain])
    #expect(link.apply(.transport(.broadcast(event: "future_event")), now: v0330T0 + 4, jitter: { $0 }) == [.drain])
    #expect(link.apply(.transport(.broadcast(event: "gomoku")), now: v0330T0 + 5, jitter: { $0 }) == [.gomokuSignal])

    // 구독 전에는 어떤 이름이든 아무것도 시키지 않는다.
    var connecting = RealtimeLink(transportAvailable: true)
    _ = connecting.apply(.signedIn(accessToken: "tok"), now: v0330T0, jitter: { $0 })
    #expect(connecting.apply(.transport(.broadcast(event: "message_read")), now: v0330T0 + 1, jitter: { $0 }) == [])
}

// MARK: - ① 소켓 기준 = 로그인

@MainActor
@Test(.gomokuDefaultsCleanup)
func 비근무_로그인_맥도_소켓을_붙인다() async {
    let (store, transport, _) = v0330RealtimeStore("connect")
    #expect(store.startedAt == nil)

    store.startRealtimeIfPossible()
    #expect(transport.commands.filter { $0.hasPrefix("connect(") }.count == 1, "비근무 로그인 맥이 소켓을 안 열었다")
    if case .connecting = store.realtimeState {} else {
        Issue.record("비근무 로그인 맥의 링이 출발하지 않았다: \(store.realtimeState)")
    }
    // 같은 진입점을 또 불러도(로그인 활성화·근무 시작이 겹친다) 다시 조인하지 않는다.
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    store.startRealtimeIfPossible()
    #expect(transport.commands.filter { $0.hasPrefix("connect(") }.count == 1)
    await messageReadWait { messageReadIdle(store) }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 로그인_지점이_소켓을_붙이고_요약을_한_번_받는다() async {
    let (store, transport, host) = v0330RealtimeStore("login")
    store.refreshLoopSliceSeconds = 30
    defer {
        store.refreshTask?.cancel()
        store.pokePollTask?.cancel()
    }

    store.startStatusRefreshLoop()
    #expect(transport.commands.filter { $0.hasPrefix("connect(") }.count == 1, "로그인 지점이 소켓을 붙이지 않았다")
    await messageReadWait { v0330Count(host, "message_unread_summary") >= 1 && messageReadIdle(store) }
    #expect(v0330Count(host, "message_unread_summary") == 1, "로그인 직후 요약을 안 받았다 — 근무 밖에 쌓인 메시지 점이 팝오버 전엔 안 뜬다")
    #expect(v0330Count(host, "take_pokes") == 0)
}

// MARK: - ② 소비 분기

@MainActor
@Test(.gomokuDefaultsCleanup)
func 비근무_맥의_초인종은_take_pokes_없이_요약만_받는다() async {
    let (store, transport, host) = v0330RealtimeStore("idle-ring")
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait { messageReadIdle(store) && v0330Count(host, "message_unread_summary") >= 1 }
    // 조인 직후 따라잡기(소비 불가) = 요약 1회, take_pokes 0회.
    #expect(v0330Count(host, "take_pokes") == 0)
    #expect(v0330Count(host, "message_unread_summary") == 1)

    transport.emit(.broadcast(event: "ring"))
    await messageReadWait { v0330Count(host, "message_unread_summary") >= 2 && messageReadIdle(store) }
    try? await Task.sleep(for: .milliseconds(80))
    #expect(v0330Count(host, "take_pokes") == 0, "비근무 맥이 초인종에 take_pokes 를 쐈다 — 회사 맥의 말풍선을 훔친다")
    #expect(v0330Count(host, "message_unread_summary") == 2, "비근무 맥의 초인종이 요약을 정확히 한 번 부르지 않았다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 근무_중_맥의_초인종은_예전_그대로_take_pokes_한_번이다() async {
    let (store, transport, host) = v0330RealtimeStore("working-ring")
    store.startedAt = MessageReadFixture.now
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait { v0330Count(host, "take_pokes") >= 1 && messageReadIdle(store) }
    let afterJoin = v0330Count(host, "take_pokes")
    let summariesAfterJoin = v0330Count(host, "message_unread_summary")
    #expect(afterJoin == 1)

    transport.emit(.broadcast(event: "ring"))
    await messageReadWait { v0330Count(host, "take_pokes") >= afterJoin + 1 && messageReadIdle(store) }
    try? await Task.sleep(for: .milliseconds(80))
    #expect(v0330Count(host, "take_pokes") == afterJoin + 1)
    #expect(v0330Count(host, "message_unread_summary") == summariesAfterJoin, "근무 중 초인종이 요약까지 불렀다(요청만 는다)")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 모르는_이벤트_이름은_예전처럼_drain_이다() async {
    let (store, transport, host) = v0330RealtimeStore("unknown-event")
    store.startedAt = MessageReadFixture.now
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait { v0330Count(host, "take_pokes") >= 1 && messageReadIdle(store) }
    let before = v0330Count(host, "take_pokes")

    transport.emit(.broadcast(event: "something_new"))
    await messageReadWait { v0330Count(host, "take_pokes") >= before + 1 && messageReadIdle(store) }
    #expect(v0330Count(host, "take_pokes") == before + 1, "모르는 이름을 버렸다 — 서버가 이름을 바꾸는 날 찌르기가 끊긴다")
}

// MARK: - ③ 읽음 신호

@MainActor
@Test(.gomokuDefaultsCleanup)
func 읽음_신호는_take_pokes_없이_요약과_보이는_대화의_이력을_다시_받는다() async {
    let (store, transport, host) = v0330RealtimeStore("message-read") { call, _ in
        switch call.rpc {
        case "message_unread_summary": return MessageReadFixture.summaryReply([])
        case "message_history_with_reads":
            return MessageReadFixture.historyReply([
                MessageReadFixture.readsRow(id: "m1", peer: MessageReadFixture.peerA, isMine: true, readByPeer: false)
            ])
        default: return nil
        }
    }
    store.startedAt = MessageReadFixture.now          // 근무 중이어도 읽음 신호는 take_pokes 가 아니다
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait { v0330Count(host, "take_pokes") >= 1 && messageReadIdle(store) }
    let pokes = v0330Count(host, "take_pokes")
    let summaries = v0330Count(host, "message_unread_summary")
    let histories = v0330Count(host, "message_history_with_reads")

    // 대화 패널이 팝오버에 보이는 상태.
    store.isMenuPresented = true
    store.isMessagePanelVisible = true
    transport.emit(.broadcast(event: "message_read"))
    await messageReadWait {
        v0330Count(host, "message_history_with_reads") >= histories + 1 && messageReadIdle(store)
    }
    try? await Task.sleep(for: .milliseconds(80))
    #expect(v0330Count(host, "take_pokes") == pokes, "읽음 신호가 take_pokes 를 쐈다")
    #expect(v0330Count(host, "message_unread_summary") == summaries + 1)
    #expect(v0330Count(host, "message_history_with_reads") == histories + 1)
    #expect(store.messageHistory.first?.readByPeer == false)

    // 패널이 안 보이면 요약만 — 볼 사람 없는 이력은 받지 않는다(무료 플랜).
    store.isMessagePanelVisible = false
    transport.emit(.broadcast(event: "message_read"))
    await messageReadWait { v0330Count(host, "message_unread_summary") >= summaries + 2 && messageReadIdle(store) }
    try? await Task.sleep(for: .milliseconds(80))
    #expect(v0330Count(host, "message_history_with_reads") == histories + 1)
    #expect(v0330Count(host, "take_pokes") == pokes)
}

// MARK: - ④ 근무 시작 전이

@MainActor
@Test(.gomokuDefaultsCleanup)
func 근무를_시작하는_순간_drain_따라잡기는_정확히_한_번이다() async {
    let (store, transport, host) = v0330RealtimeStore("work-start")
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    // 비근무 동안 초인종이 두 번 울렸다 — 빚은 적히지만 take_pokes 는 0.
    transport.emit(.broadcast(event: "ring"))
    transport.emit(.broadcast(event: "ring"))
    await messageReadWait { messageReadIdle(store) }
    #expect(v0330Count(host, "take_pokes") == 0)
    #expect(store.realtime.catchUpDeferred)

    store.start(now: MessageReadFixture.now)
    await messageReadWait { v0330Count(host, "take_pokes") >= 1 && messageReadIdle(store) }
    // 5초 티커와 30초 되맞춤이 같은 빚을 또 갚지 않는다.
    store.realtimeTick(at: store.realtime.diagnostics.recent.last.map { $0.at + 1 } ?? Date())
    store.reconcileRealtimeWithWorkState()
    await messageReadWait { messageReadIdle(store) }
    try? await Task.sleep(for: .milliseconds(100))
    #expect(v0330Count(host, "take_pokes") == 1, "근무 시작 한 번에 take_pokes 가 \(v0330Count(host, "take_pokes"))번 나갔다")
    #expect(!store.realtime.catchUpDeferred)
    #expect(transport.commands.filter { $0.hasPrefix("connect(") }.count == 1, "근무 시작이 붙어 있는 소켓을 다시 열었다")
    store.syncTask?.cancel()
    store.tickerTask?.cancel()
}

// MARK: - 소스 계약 (주석을 걷어낸 뒤)

@Test
func 소켓_출발에는_근무_게이트가_없고_소비_분기는_그대로다() throws {
    let realtime = gomokuCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source("WorkTimerStoreRealtime.swift")))
    let start = try #require(gomokuBody(of: "func startRealtimeIfPossible()", in: realtime))
    #expect(!start.contains("realtimeMayConsumePokes"), "소켓 출발이 다시 근무에 묶였다 — 근무 밖 메시지가 안 들린다")
    #expect(!start.contains("startedAt"))
    #expect(start.contains("guard realtime.link.state == .idle(.signedOut) else { return }"))
    // 읽음 신호 가지는 take_pokes 문을 지나지 않는다.
    #expect(realtime.contains("case .messageReadSignal: requestMessageActivityRefresh()"))
    // take_pokes 로 가는 문은 여전히 하나다.
    #expect(realtime.contains("var realtimeMayConsumePokes: Bool { startedAt != nil && !adoptedRemoteSession }"))

    let store = gomokuCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source("WorkTimerStore.swift")))
    let stop = try #require(gomokuBody(of: "func stop(now: Date = Date())", in: store))
    #expect(!stop.contains("realtimeApply("), "근무 종료가 다시 링을 건드린다")
}
