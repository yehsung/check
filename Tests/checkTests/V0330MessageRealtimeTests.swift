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

@MainActor
@Test(.gomokuDefaultsCleanup)
func 비근무_맥에_빚이_있어도_티커와_되맞춤은_요약을_다시_쏘지_않는다() async {
    // m-fix F4: 빚 갚기(resumeDeferredCatchUpIfPossible)의 소비 게이트를 지워도 초록이던 자리(MV15 생존). 게이트가 없으면
    // 비근무 맥이 5초 티커·30초 되맞춤마다 따라잡기 → "소비 불가" 가지 → 요약 RPC 를 쏜다(한 대가 하루 약 1.7만 건).
    let (store, transport, host) = v0330RealtimeStore("tick-debt")
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait { v0330Count(host, "message_unread_summary") >= 1 && messageReadIdle(store) }
    #expect(store.realtime.catchUpDeferred, "전제: 비근무 조인이 빚을 적었다")
    let base = v0330Count(host, "message_unread_summary")

    var now = Date()
    for _ in 0..<5 {
        now = now.addingTimeInterval(5)
        store.realtimeTick(at: now)
        store.reconcileRealtimeWithWorkState()
        await messageReadWait { messageReadIdle(store) }
    }
    try? await Task.sleep(for: .milliseconds(80))
    await messageReadWait { messageReadIdle(store) }
    #expect(v0330Count(host, "message_unread_summary") == base, "비근무 맥의 티커·되맞춤이 요약 RPC 를 반복해서 쐈다")
    #expect(v0330Count(host, "take_pokes") == 0)
    #expect(store.realtime.catchUpDeferred, "갚지도 않은 빚이 지워졌다")
}

// MARK: - m-fix: 근무 중 수신 · 닫힌 팝오버 동안의 신호

@MainActor
@Test(.gomokuDefaultsCleanup)
func 근무_중_drain_으로_받은_메시지는_요약을_다시_받아_안_읽음_점을_켠다() async {
    // m-fix F2 · X1: 근무 중인 맥은 초인종을 take_pokes 로 소비한다. 말풍선으로 본 것은 읽음이 아니므로(M1.8) 서버 기준 안 읽음인데,
    // drain 경로가 요약·이력을 다시 안 받아 메뉴바·레일·목록 점이 꺼진 채였다.
    let epoch = Int(Date().timeIntervalSince1970)
    let (store, transport, host) = v0330RealtimeStore("working-drain-dot") { call, index in
        switch call.rpc {
        case "take_pokes":
            // 조인 따라잡기(0번)는 빈손, 초인종(1번)에 메시지 한 건.
            return index == 0
                ? MessageReadStubProtocol.Reply(body: "[]")
                : MessageReadStubProtocol.Reply(body: MessageReadFixture.json([
                    MessageReadFixture.takenMessageRow(id: "wd-1", from: MessageReadFixture.peerA, epoch: epoch - 5)
                ]))
        case "message_unread_summary":
            // 메시지 도착 전엔 0, 도착 뒤엔 peerA 1건(서버의 사실).
            return MessageReadStubProtocol.count(host: call.url.host ?? "", rpc: "take_pokes") < 2
                ? MessageReadFixture.summaryReply([])
                : MessageReadFixture.summaryReply([(MessageReadFixture.peerA, 1)])
        default: return nil
        }
    }
    store.startedAt = MessageReadFixture.now
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait { v0330Count(host, "take_pokes") >= 1 && messageReadIdle(store) }
    #expect(!store.hasUnreadMessages, "전제: 도착 전엔 점 없음")
    let summaries = v0330Count(host, "message_unread_summary")

    transport.emit(.broadcast(event: "ring"))
    await messageReadWait { v0330Count(host, "take_pokes") >= 2 && messageReadIdle(store) }
    try? await Task.sleep(for: .milliseconds(80))
    await messageReadWait { messageReadIdle(store) }
    #expect(store.receivedMessages.map(\.id) == ["wd-1"], "전제: 말풍선 큐에 들어왔다")
    #expect(v0330Count(host, "message_unread_summary") == summaries + 1, "근무 중 받은 메시지가 요약을 다시 안 받았다")
    #expect(store.hasUnreadMessages, "근무 중 받은 안 읽은 메시지가 메뉴바·레일 점을 켜지 못한다")
    #expect(store.unreadMessagePeerIDs == [MessageReadFixture.peerA])
    // 팝오버가 닫혀 있으니 이력은 안 받는다(볼 사람이 없다).
    #expect(v0330Count(host, "message_history_with_reads") == 0)
    #expect(v0330Count(host, "mark_messages_read") == 0, "말풍선으로 본 것을 읽음으로 올렸다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 근무_중_조인_따라잡기도_요약을_한_번_받는다() async {
    // m-fix(F2 와 같은 틈): 소켓이 끊겨 있던 동안의 메시지·읽음 신호는 재생되지 않는다. 비근무 조인은 요약을 받는데
    // 근무 중 조인은 take_pokes 만 불러, 끊긴 동안 온(5분 넘어 말풍선으로 안 오는) 메시지의 점이 팝오버를 열 때까지 안 떴다.
    let (store, transport, host) = v0330RealtimeStore("working-join-summary")
    store.startedAt = MessageReadFixture.now
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait {
        v0330Count(host, "take_pokes") >= 1 && v0330Count(host, "message_unread_summary") >= 1 && messageReadIdle(store)
    }
    try? await Task.sleep(for: .milliseconds(80))
    await messageReadWait { messageReadIdle(store) }
    #expect(v0330Count(host, "take_pokes") == 1)
    #expect(v0330Count(host, "message_unread_summary") == 1, "근무 중 조인이 요약을 안 받았다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 닫힌_팝오버에서_받은_읽음_신호는_다시_열_때_보이는_대화의_이력을_스로틀과_무관하게_받는다() async {
    // m-fix F1 ⑧: 대화 패널을 띄운 채 팝오버를 닫았다 → 상대가 읽음(message_read) → 60초 안에 다시 연다.
    // 닫힌 동안의 새로고침은 이력을 건너뛰므로(볼 사람이 없다) 다시 열 때 받지 않으면 보낸 말 옆 1 이 남는다.
    let (store, transport, host) = v0330RealtimeStore("read-while-closed") { call, index in
        switch call.rpc {
        case "message_unread_summary": return MessageReadFixture.summaryReply([])
        case "message_history_with_reads":
            // 0·1번(패널 열기·팝오버 열기): 상대가 아직 안 읽음 · 2번부터: 읽음
            return MessageReadFixture.historyReply([
                MessageReadFixture.readsRow(id: "rw-1", peer: MessageReadFixture.peerA, isMine: true, readByPeer: index >= 2)
            ])
        default: return nil
        }
    }
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait { messageReadIdle(store) }
    store.openMessagePanel(peer: MessageReadFixture.peerA)
    store.setMenuPresented(true)
    await messageReadWait { v0330Count(host, "message_history_with_reads") >= 2 && messageReadIdle(store) }
    #expect(store.messageHistory.first?.readByPeer == false, "전제: 상대가 아직 안 읽었다")
    let historiesBeforeClose = v0330Count(host, "message_history_with_reads")

    store.setMenuPresented(false)
    transport.emit(.broadcast(event: "message_read"))
    await messageReadWait { messageReadIdle(store) }
    #expect(v0330Count(host, "message_history_with_reads") == historiesBeforeClose, "닫힌 팝오버에서 이력을 받았다(볼 사람이 없다)")

    store.setMenuPresented(true)   // 얼린 시계 = 60초 스로틀 안
    await messageReadWait { v0330Count(host, "message_history_with_reads") >= historiesBeforeClose + 1 && messageReadIdle(store) }
    try? await Task.sleep(for: .milliseconds(80))
    await messageReadWait { messageReadIdle(store) }
    #expect(v0330Count(host, "message_history_with_reads") == historiesBeforeClose + 1)
    #expect(store.messageHistory.first?.readByPeer == true, "상대가 읽었다는 신호를 받았는데 다시 연 대화에 1 이 남았다")

    // 한 번 받았으면 더는 낡지 않았다 — 같은 스로틀 안에서 다시 열어도 요청 없음.
    store.setMenuPresented(false)
    store.setMenuPresented(true)
    try? await Task.sleep(for: .milliseconds(80))
    await messageReadWait { messageReadIdle(store) }
    #expect(v0330Count(host, "message_history_with_reads") == historiesBeforeClose + 1, "낡음 표시가 안 지워져 열 때마다 이력을 받는다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 닫힌_팝오버에서_온_새_말은_다시_열_때_보이는_대화에_나타나고_읽음으로_올린다() async {
    // m-fix F1 ⑨: 비근무 · 대화 패널을 띄운 채 팝오버를 닫았다 → 그 상대가 새 말(초인종) → 60초 안에 다시 연다.
    // 요약만 받으면 같은 상대에게 점은 켜지는데 열린 대화엔 새 말이 없고 읽음 처리도 0회였다.
    let epoch = Int(Date().timeIntervalSince1970)
    let (store, transport, host) = v0330RealtimeStore("new-while-closed") { call, index in
        // 서버의 사실: 읽음 처리가 한 번 나가면 nw-1 은 읽혔다.
        let marked = MessageReadStubProtocol.count(host: call.url.host ?? "", rpc: "mark_messages_read") > 0
        switch call.rpc {
        case "message_unread_summary":
            return index <= 1 || marked
                ? MessageReadFixture.summaryReply([])
                : MessageReadFixture.summaryReply([(MessageReadFixture.peerA, 1)])
        case "message_history_with_reads":
            var rows = [MessageReadFixture.readsRow(id: "nw-0", peer: MessageReadFixture.peerA, isMine: true, epoch: epoch - 60, readByPeer: true)]
            if index >= 2 {
                rows.append(MessageReadFixture.readsRow(id: "nw-1", peer: MessageReadFixture.peerA, isMine: false, epoch: epoch, unread: !marked))
            }
            return MessageReadFixture.historyReply(rows)
        case "mark_messages_read": return MessageReadFixture.markReply()
        default: return nil
        }
    }
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait { messageReadIdle(store) }
    store.openMessagePanel(peer: MessageReadFixture.peerA)
    store.setMenuPresented(true)
    await messageReadWait { v0330Count(host, "message_history_with_reads") >= 2 && messageReadIdle(store) }

    store.setMenuPresented(false)
    transport.emit(.broadcast(event: "ring"))
    await messageReadWait { v0330Count(host, "message_unread_summary") >= 3 && messageReadIdle(store) }
    #expect(store.hasUnreadMessages, "전제: 닫힌 동안 온 말이 점을 켰다")
    #expect(v0330Count(host, "take_pokes") == 0)

    store.setMenuPresented(true)
    await messageReadWait { v0330Count(host, "mark_messages_read") >= 1 && messageReadIdle(store) }
    #expect(store.messageHistory.map(\.id).contains("nw-1"), "다시 연 대화에 새 말이 안 그려졌다")
    #expect(v0330Count(host, "mark_messages_read") == 1, "보이는 대화의 새 말을 읽음으로 안 올렸다")
    #expect(!store.hasUnreadMessages, "대화 화면에 떠 있는 상대의 점이 켜져 있다")
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
