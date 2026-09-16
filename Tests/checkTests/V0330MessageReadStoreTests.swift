import Foundation
import Testing
@testable import check

// v0.3.30 — 메시지 읽음의 **스토어 계약**(스텁 기반).
//
//  · 이력은 `message_history_with_reads` 로 받고, 없는 서버(404/PGRST202)면 `message_history` 로 접고 읽음은 "모름".
//  · 읽음 처리 조건 표: 팝오버 · 대화 패널 · 그 상대 · 서버 기준 안 읽음 — 하나라도 빠지면 호출 0.
//  · 낙관 읽음은 점을 곧바로 끄고, 실패해도 되돌리지 않되 다음 새로고침에서 서버가 이긴다.
//  · 다른 기기에서 읽으면(요약 total 0) 점이 꺼진다.
//  · 근무 시작 drain 으로 들어온 메시지 중 이미 읽은 것은 말풍선으로 안 뜬다.
//  · 로그아웃 뒤 늦게 온 응답은 다음 계정에 안 들어간다(세대 가드).
//  · 로그아웃은 `scope=local` 이다(A5).

private typealias Fx = MessageReadFixture

@MainActor
private func v0330Rpc(_ host: String, _ rpc: String) -> Int {
    MessageReadStubProtocol.count(host: host, rpc: rpc)
}

/// 대화가 팝오버에 보이는 상태로 세운다(판정 조건 넷 중 셋). 상대는 peerA.
@MainActor
private func v0330OpenConversation(_ store: WorkTimerStore, peer: String = Fx.peerA) {
    store.isMenuPresented = true
    store.isMessagePanelVisible = true
    store.selectedMessagePeerID = peer
}

// MARK: - 이력: with_reads · 옛 서버 폴백

@MainActor
@Test(.gomokuDefaultsCleanup)
func 읽음_칸이_붙은_이력을_받으면_읽음_기능이_켜지고_플래그가_제자리에_실린다() async {
    let (store, host) = makeMessageReadStore("with-reads") { call, _ in
        guard call.rpc == "message_history_with_reads" else { return nil }
        return Fx.historyReply([
            Fx.readsRow(id: "s1", peer: Fx.peerA, isMine: true, readByPeer: false),
            Fx.readsRow(id: "s2", peer: Fx.peerA, isMine: true, readByPeer: true),
            // 서버가 반대쪽 칸에 값을 실어 보내도 버린다(받은 말풍선에 1 이 그려질 경로를 닫는다).
            Fx.readsRow(id: "r1", peer: Fx.peerA, isMine: false, readByPeer: true, unread: true),
            Fx.readsRow(id: "r2", peer: Fx.peerB, isMine: false, unread: false)
        ])
    }
    await store.performLoadMessageHistory()

    #expect(store.messageReadReceiptsAvailable)
    #expect(store.messageHistoryReadSnapshot != nil)
    let byID = Dictionary(uniqueKeysWithValues: store.messageHistory.map { ($0.id, $0) })
    #expect(byID["s1"]?.readByPeer == false && byID["s1"]?.isUnread == nil)
    #expect(byID["s2"]?.readByPeer == true)
    #expect(byID["r1"]?.readByPeer == nil, "받은 메시지에 read_by_peer 가 새어 들어왔다")
    #expect(byID["r1"]?.isUnread == true)
    #expect(byID["r2"]?.isUnread == false)
    #expect(v0330Rpc(host, "message_history") == 0, "새 함수가 있는데 옛 이력까지 불렀다")
    // 요청은 24시간 창을 싣는다(보관 24시간 — 서버 상한과 같은 값).
    #expect(MessageReadStubProtocol.calls(host: host, rpc: "message_history_with_reads").first?.json["p_hours"] as? Int == 24)
    #expect(WorkTimerStore.messageHistoryHours == 24)
    #expect(store.unreadMessagePeerIDs == [Fx.peerA])
    #expect(store.hasUnreadMessages)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 새_함수가_없는_서버는_옛_이력으로_접고_읽음은_모름이다() async {
    let (store, host) = makeMessageReadStore("fallback") { call, _ in
        switch call.rpc {
        case "message_history_with_reads": return Fx.missingFunction("message_history_with_reads")
        case "message_history":
            return MessageReadStubProtocol.Reply(body: Fx.json([
                ["id": "old1", "from_user": Fx.peerA, "to_user": Fx.me, "body": "옛 서버", "is_mine": false,
                 "peer_user_id": Fx.peerA, "peer_display_name": "상대", "created_epoch": 1_789_999_000]
            ]))
        default: return nil
        }
    }
    // 앞서 읽음을 아는 서버였다가(스냅샷 있음) 옛 서버로 되돌아간 경우까지 함께 본다.
    store.messageReadReceiptsAvailable = true
    store.messageHistoryReadSnapshot = MessageHistoryReadSnapshot(serial: 0, serverOrder: [:])

    await store.performLoadMessageHistory()

    #expect(v0330Rpc(host, "message_history_with_reads") == 1)
    #expect(v0330Rpc(host, "message_history") == 1, "없는 서버에서 옛 이력으로 접지 않았다")
    #expect(store.messageHistory.map(\.id) == ["old1"])
    #expect(!store.messageReadReceiptsAvailable, "읽음을 모르는 서버인데 1 을 그릴 수 있다고 말한다")
    #expect(store.messageHistoryReadSnapshot == nil)
    #expect(store.messageHistory.first?.isUnread == nil)
    #expect(!store.messageHistoryFailed)
    // 옛 서버의 안 읽음 점은 옛 규칙(도장 시각)이다.
    #expect(store.unreadMessagePeerIDs == [Fx.peerA])
    store.messageReadStamps[Fx.peerA] = Fx.now
    #expect(store.unreadMessagePeerIDs.isEmpty)

    // 읽음을 모르는 서버에서는 대화를 열어도 읽음 처리 호출이 없다.
    v0330OpenConversation(store)
    store.evaluateMessageReadMarking()
    try? await Task.sleep(for: .milliseconds(60))
    #expect(v0330Rpc(host, "mark_messages_read") == 0)
}

@Test
func 함수_없음_판정은_404와_스키마_부재만이다() {
    #expect(WorkTimerStore.isMissingMessageReadFunction(.databaseSchemaMissing))
    #expect(WorkTimerStore.isMissingMessageReadFunction(.invalidResponse(404)))
    // 일시 장애·권한은 "함수 없음"이 아니다 — 접으면 장애 한 번에 읽음 표시가 꺼진다.
    #expect(!WorkTimerStore.isMissingMessageReadFunction(.invalidResponse(500)))
    #expect(!WorkTimerStore.isMissingMessageReadFunction(.sessionExpired))
    #expect(!WorkTimerStore.isMissingMessageReadFunction(.invalidResponse(403)))
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 일시_장애는_옛_이력으로_접지_않고_실패로_남는다() async {
    let (store, host) = makeMessageReadStore("transient") { call, _ in
        call.rpc == "message_history_with_reads"
            ? MessageReadStubProtocol.Reply(status: 500, body: #"{"message":"boom"}"#) : nil
    }
    await store.performLoadMessageHistory()
    #expect(v0330Rpc(host, "message_history") == 0)
    #expect(store.messageHistoryFailed)
}

// MARK: - 읽음 처리 조건 표

@MainActor
@Test(.gomokuDefaultsCleanup, arguments: [
    // (팝오버, 패널, 고른 상대, 서버 안 읽음, 기대 호출 수)
    (true, true, Fx.peerA, true, 1),
    (false, true, Fx.peerA, true, 0),     // 팝오버 닫힘
    (true, false, Fx.peerA, true, 0),     // 패널 안 보임
    (true, true, Fx.peerB, true, 0),      // 다른 상대를 보고 있다
    (true, true, Fx.peerA, false, 0)      // 서버 기준 이미 읽음
])
func 읽음_처리는_팝오버_패널_상대_안읽음이_모두_맞을_때만_부른다(
    menu: Bool, panel: Bool, selected: String, unread: Bool, expected: Int
) async {
    let (store, host) = makeMessageReadStore("mark-table") { call, _ in
        switch call.rpc {
        case "message_history_with_reads":
            return Fx.historyReply([
                Fx.readsRow(id: "a1", peer: Fx.peerA, isMine: false, unread: unread),
                Fx.readsRow(id: "b1", peer: Fx.peerB, isMine: false, unread: false)
            ])
        case "mark_messages_read": return Fx.markReply()
        case "message_unread_summary": return Fx.summaryReply([])
        default: return nil
        }
    }
    store.isMenuPresented = menu
    store.isMessagePanelVisible = panel
    store.selectedMessagePeerID = selected
    await store.performLoadMessageHistory()
    await messageReadWait { messageReadIdle(store) }
    try? await Task.sleep(for: .milliseconds(60))
    await messageReadWait { messageReadIdle(store) }

    #expect(v0330Rpc(host, "mark_messages_read") == expected)
    if expected == 1 {
        let body = MessageReadStubProtocol.calls(host: host, rpc: "mark_messages_read").first?.json
        #expect(body?["p_peer"] as? String == Fx.peerA)
        #expect(body?["p_through"] as? String == "a1", "경계가 그 대화의 마지막 받은 메시지 id 가 아니다")
    }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 같은_초_안의_메시지는_서버_순서로_마지막을_고른다() async {
    // created_epoch 은 초 단위다. 같은 초 안의 세 메시지를 서버는 created_at(마이크로초) 순서로 준다 — id 사전순과 **반대로**.
    // 클라가 화면 정렬(초 → id)로 "마지막"을 고르면 "c" 를 경계로 올리고, 서버는 "a" 까지 안 읽음으로 남겨 점이 영영 안 꺼진다.
    let (store, host) = makeMessageReadStore("same-second") { call, _ in
        switch call.rpc {
        case "message_history_with_reads":
            return Fx.historyReply([
                Fx.readsRow(id: "c", peer: Fx.peerA, isMine: false, unread: true),
                Fx.readsRow(id: "b", peer: Fx.peerA, isMine: false, unread: true),
                Fx.readsRow(id: "a", peer: Fx.peerA, isMine: false, unread: true)
            ])
        case "mark_messages_read": return Fx.markReply()
        default: return nil
        }
    }
    v0330OpenConversation(store)
    await store.performLoadMessageHistory()
    await messageReadWait { v0330Rpc(host, "mark_messages_read") >= 1 && messageReadIdle(store) }
    #expect(MessageReadStubProtocol.calls(host: host, rpc: "mark_messages_read").first?.json["p_through"] as? String == "a")
    // 화면 정렬도 같은 초의 동률을 서버 순서로 깬다(m-fix F7) — id 사전순이면 "a" 가 맨 위에 그려진다.
    #expect(store.messageHistory.map(\.id) == ["c", "b", "a"], "같은 초 안의 말풍선이 서버 순서가 아니다")
    #expect(store.selectedMessageThread?.messages.map(\.id) == ["c", "b", "a"])
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 낙관_읽음은_응답_전에_점을_끄고_새_메시지가_오면_다시_올린다() async {
    let (store, host) = makeMessageReadStore("optimistic") { call, index in
        switch call.rpc {
        case "message_history_with_reads":
            var rows = [Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: false, unread: true)]
            if index >= 1 { rows.append(Fx.readsRow(id: "m2", peer: Fx.peerA, isMine: false, unread: true)) }
            return Fx.historyReply(rows)
        // 응답을 늦춘다 — 날아가는 동안 점이 이미 꺼져 있어야 한다.
        case "mark_messages_read": return Fx.markReply(delay: 0.4)
        case "message_unread_summary": return Fx.summaryReply([])
        default: return nil
        }
    }
    v0330OpenConversation(store)
    await store.performLoadMessageHistory()
    // 점은 **응답 전에**(요청이 전선에 오르기 전부터) 이미 꺼져 있다.
    #expect(store.unreadMessagePeerIDs.isEmpty, "읽음을 보냈는데 응답 전까지 점이 켜져 있다")
    #expect(!store.hasUnreadMessages)
    #expect(store.messageOptimisticReads[Fx.peerA]?.throughID == "m1")
    #expect(store.messageReadRuntime.markInFlight.contains(Fx.peerA))
    await messageReadWait { v0330Rpc(host, "mark_messages_read") == 1 }
    #expect(v0330Rpc(host, "mark_messages_read") == 1)

    // 날아가는 중(응답 0.4초)에 같은 경계로 다시 판정해도 호출이 겹치지 않는다.
    store.evaluateMessageReadMarking()
    try? await Task.sleep(for: .milliseconds(50))
    #expect(v0330Rpc(host, "mark_messages_read") == 1)

    // 그 상태에서 새 메시지가 도착(이력 재조회)하면 새 경계로 다시 올린다 — 날아가는 것이 끝난 뒤에.
    await store.performLoadMessageHistory()
    await messageReadWait { v0330Rpc(host, "mark_messages_read") >= 2 && messageReadIdle(store) }
    let throughs = MessageReadStubProtocol.calls(host: host, rpc: "mark_messages_read").compactMap { $0.json["p_through"] as? String }
    #expect(Array(throughs.prefix(2)) == ["m1", "m2"])
    #expect(store.messageOptimisticReads[Fx.peerA]?.throughID == "m2")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 읽음_처리_성공_뒤에_요약을_다시_받고_서버_판정으로_넘어간다() async {
    let (store, host) = makeMessageReadStore("after-success") { call, index in
        switch call.rpc {
        case "message_history_with_reads":
            return Fx.historyReply([Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: false, unread: index == 0)])
        case "mark_messages_read": return Fx.markReply()
        case "message_unread_summary": return Fx.summaryReply([])
        default: return nil
        }
    }
    v0330OpenConversation(store)
    await store.performLoadMessageHistory()
    await messageReadWait { v0330Rpc(host, "message_unread_summary") >= 1 && messageReadIdle(store) }
    #expect(v0330Rpc(host, "message_unread_summary") == 1, "읽음 처리 성공 뒤에 요약을 다시 안 받았다")
    #expect(v0330Rpc(host, "message_history_with_reads") == 2, "패널이 보이는데 이력을 다시 안 받았다")
    #expect(store.messageOptimisticReads[Fx.peerA]?.settledSerial != nil)
    #expect(store.messageOptimisticReads[Fx.peerA]?.failed == false)
    #expect(store.unreadMessagePeerIDs.isEmpty)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 읽음_처리가_실패해도_낙관_표시는_남고_다음_새로고침에서_서버가_이긴다() async {
    let (store, host) = makeMessageReadStore("mark-fails") { call, _ in
        switch call.rpc {
        case "message_history_with_reads":
            return Fx.historyReply([Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: false, unread: true)])
        case "mark_messages_read": return MessageReadStubProtocol.Reply(status: 500, body: #"{"message":"boom"}"#)
        case "message_unread_summary": return Fx.summaryReply([(Fx.peerA, 1)])
        default: return nil
        }
    }
    v0330OpenConversation(store)
    await store.performLoadMessageHistory()
    await messageReadWait { messageReadIdle(store) }
    #expect(v0330Rpc(host, "mark_messages_read") == 1)
    #expect(store.messageOptimisticReads[Fx.peerA]?.failed == true)
    #expect(store.unreadMessagePeerIDs.isEmpty, "실패했다고 낙관 표시를 되돌렸다")
    #expect(v0330Rpc(host, "message_unread_summary") == 0, "실패했는데 성공 뒤 새로고침을 돌렸다")

    // 다음 새로고침(정산 뒤에 띄운 요약)이 사실을 말한다. 패널을 닫아 재시도가 끼지 않게 한다.
    store.isMessagePanelVisible = false
    await store.performLoadMessageUnreadSummary()
    #expect(store.unreadMessagePeerIDs == [Fx.peerA], "실패한 읽음이 서버 판정을 영영 가린다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 다른_기기에서_읽으면_요약이_점을_끈다() async {
    let (store, _) = makeMessageReadStore("other-device") { call, _ in
        switch call.rpc {
        case "message_history_with_reads":
            return Fx.historyReply([Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: false, unread: true)])
        case "message_unread_summary": return Fx.summaryReply([])     // 폰에서 읽었다: total 0
        default: return nil
        }
    }
    await store.performLoadMessageHistory()
    #expect(store.unreadMessagePeerIDs == [Fx.peerA])
    #expect(store.hasUnreadMessages)

    await store.performLoadMessageUnreadSummary()
    #expect(store.messageUnreadSummary?.summary.total == 0)
    #expect(store.unreadMessagePeerIDs.isEmpty, "다른 기기에서 읽었는데 맥의 점이 남았다")
    #expect(!store.hasUnreadMessages)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 늦게_온_옛_요약과_옛_이력은_새_판정을_덮지_않는다() async {
    // 도착 순서를 **문으로 정한다**(m-fix F6). 벽시계 지연(0.3초)이던 때는 전체 스위트 부하에서 뒤에 띄운 요청이 전선에
    // 오르기도 전에 옛 응답이 풀려, 일련번호 가드를 지워도 초록이었다(MV24·MV25 생존 — 단독 실행에서만 빨강).
    let gate = MessageReadStubGate()
    let (store, host) = makeMessageReadStore("stale-responses") { call, index in
        switch call.rpc {
        case "message_unread_summary":
            // 첫 요청은 문에 붙잡혀 "안 읽음 있음", 둘째는 곧바로 "없음".
            return index == 0 ? Fx.summaryReply([(Fx.peerA, 2)], gate: gate) : Fx.summaryReply([])
        case "message_history_with_reads":
            return index == 0
                ? Fx.historyReply([Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: true, readByPeer: false)], gate: gate)
                : Fx.historyReply([Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: true, readByPeer: true)])
        default: return nil
        }
    }
    // 먼저 띄운 조회 둘(붙잡힘) → 나중에 띄운 조회 둘(곧바로). 요청 순서가 서버 상태의 순서다.
    let firstSummary = Task { @MainActor in await store.performLoadMessageUnreadSummary() }
    let firstHistory = Task { @MainActor in await store.performLoadMessageHistory() }
    await messageReadWait {
        v0330Rpc(host, "message_unread_summary") == 1 && v0330Rpc(host, "message_history_with_reads") == 1
    }
    await store.performLoadMessageUnreadSummary()
    await store.performLoadMessageHistory()
    // 전제: 나중에 띄운 두 응답이 먼저 반영됐다.
    #expect(store.messageUnreadSummary?.summary.total == 0)
    #expect(store.messageHistory.first?.readByPeer == true)
    // 이제서야 옛 응답 둘이 도착한다.
    gate.open()
    await firstSummary.value
    await firstHistory.value

    #expect(store.messageUnreadSummary?.summary.total == 0, "늦게 온 옛 요약이 새 요약을 덮었다")
    #expect(store.messageHistory.first?.readByPeer == true, "늦게 온 옛 이력이 읽음 1 을 되살렸다")
    #expect(store.unreadMessagePeerIDs.isEmpty)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 다른_기기에서_읽혀_요약이_0_이라_말한_메시지는_근무_시작_drain_말풍선으로_안_뜬다() async {
    // m-fix F3: 이력(안 읽음)을 받은 **뒤에** 띄운 요약이 "그 상대 0건"이라 말하면 점은 꺼진다. 같은 메시지가 근무 시작
    // drain 으로 들어왔을 때 이력 스냅샷만 보면 말풍선으로 튀어나온다 — 점은 꺼졌는데 알림은 뜨는 어긋남.
    let nowEpoch = Int(Date().timeIntervalSince1970)
    let (store, host) = makeMessageReadStore("drain-after-other-device") { call, index in
        switch call.rpc {
        case "message_history_with_reads":
            return Fx.historyReply([
                Fx.readsRow(id: "od-1", peer: Fx.peerA, isMine: false, epoch: nowEpoch - 20, unread: true),
                Fx.readsRow(id: "od-2", peer: Fx.peerB, isMine: false, epoch: nowEpoch - 10, unread: true)
            ])
        case "message_unread_summary":
            // 이력보다 나중에 띄운 요약: peerA 는 폰에서 읽었고(0건) peerB 는 아직 1건.
            return Fx.summaryReply([(Fx.peerB, 1)])
        case "take_pokes":
            return MessageReadStubProtocol.Reply(body: Fx.json([
                Fx.takenMessageRow(id: "od-1", from: Fx.peerA, epoch: nowEpoch - 20),
                Fx.takenMessageRow(id: "od-2", from: Fx.peerB, epoch: nowEpoch - 10)
            ]))
        default: return nil
        }
    }
    await store.performLoadMessageHistory()
    await store.performLoadMessageUnreadSummary()
    #expect(store.unreadMessagePeerIDs == [Fx.peerB], "전제: 요약이 더 나중이라 peerA 의 점은 꺼졌다")

    store.startedAt = Date()
    _ = await store.drainReceivedPokes()
    await messageReadWait { messageReadIdle(store) }
    #expect(v0330Rpc(host, "take_pokes") == 1)
    #expect(store.receivedMessages.map(\.id) == ["od-2"],
            "점이 꺼진(다른 기기에서 읽은) 메시지가 말풍선으로 떴다: \(store.receivedMessages.map(\.id))")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 계정을_바꾸면_앞_계정의_요약은_점으로_남지_않고_새_계정의_요약이_반영된다() async {
    // m-fix F5: 기존 세대 가드 테스트는 **늦게 온** 응답만 본다. 이미 반영된 요약(일련번호 3)을 로그아웃이 안 지우면
    // 다음 계정에 앞 사람의 점이 남고, 새 장부의 요약(일련번호 1)은 "더 낡았다"로 버려져 그 점을 영영 못 끈다(MV32 생존).
    let (store, host) = makeMessageReadStore("account-switch") { call, index in
        guard call.rpc == "message_unread_summary" else { return nil }
        return index < 3 ? Fx.summaryReply([(Fx.peerA, 2)]) : Fx.summaryReply([])
    }
    for _ in 0..<3 { await store.performLoadMessageUnreadSummary() }
    #expect(store.hasUnreadMessages, "전제: 앞 계정에 안 읽음이 있다")
    #expect((store.messageUnreadSummary?.serial ?? 0) >= 3)

    store.signOut()
    store.session = SupabaseSession(accessToken: "access-token-2", refreshToken: nil, userID: Fx.peerB)
    #expect(store.messageUnreadSummary == nil, "로그아웃이 앞 계정의 요약을 지우지 않았다")
    #expect(!store.hasUnreadMessages, "앞 계정의 안 읽음 점이 다음 계정에 남았다")

    await store.performLoadMessageUnreadSummary()
    #expect(v0330Rpc(host, "message_unread_summary") == 4)
    #expect(store.messageUnreadSummary?.summary.total == 0, "새 계정의 요약이 앞 계정의 일련번호에 막혀 반영되지 않았다")
    #expect(!store.hasUnreadMessages)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 안_읽음_점이_켜져_있으면_60초_안에_다시_열어도_요약을_다시_받는다() async {
    // X1-F1(다른 기기에서 읽음): 서버의 'message_read' 는 **보낸 사람** 채널로만 간다 — 읽은 사람의 맥에는 신호가 없다.
    // 점이 켜진 채 60초 스로틀에 걸리면 사용자가 점을 보고 팝오버를 열어도 점이 그대로다. 점이 켜져 있을 때는 짧은 스로틀이다.
    final class Clock: @unchecked Sendable { var now = MessageReadFixture.now }
    let clock = Clock()
    let (store, host) = makeMessageReadStore("reopen-with-dot") { call, index in
        switch call.rpc {
        case "message_unread_summary":
            return index == 0 ? Fx.summaryReply([(Fx.peerA, 1)]) : Fx.summaryReply([])
        case "message_history_with_reads":
            return Fx.historyReply([Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: false, unread: index == 0)])
        default: return nil
        }
    }
    store.clock = { clock.now }
    store.setMenuPresented(true)
    await messageReadWait { v0330Rpc(host, "message_history_with_reads") >= 1 && messageReadIdle(store) }
    #expect(store.hasUnreadMessages, "전제: peerA 안 읽음")

    // 폰에서 읽었다 — 이 맥엔 신호 없음. 30초 뒤 팝오버를 다시 연다.
    store.setMenuPresented(false)
    clock.now = clock.now.addingTimeInterval(30)
    store.setMenuPresented(true)
    await messageReadWait { v0330Rpc(host, "message_unread_summary") >= 2 && messageReadIdle(store) }
    #expect(v0330Rpc(host, "message_unread_summary") == 2, "점이 켜져 있는데 60초 스로틀로 요약을 안 물었다")
    #expect(!store.hasUnreadMessages, "폰에서 읽었는데 맥의 점이 남았다")

    // 점이 꺼진 뒤에는 원래 스로틀(60초)이다 — 30초 뒤 다시 열어도 요청 없음.
    store.setMenuPresented(false)
    clock.now = clock.now.addingTimeInterval(30)
    store.setMenuPresented(true)
    try? await Task.sleep(for: .milliseconds(120))
    await messageReadWait { messageReadIdle(store) }
    #expect(v0330Rpc(host, "message_unread_summary") == 2, "점이 꺼졌는데 스로틀을 건너뛰었다")
    store.tickerTask?.cancel()
}

// MARK: - 팝오버 열기 · 겹치지 않는 새로고침

@MainActor
@Test(.gomokuDefaultsCleanup)
func 팝오버를_열면_요약과_이력을_60초에_한_번_받고_오목_인박스도_본다() async {
    final class Clock: @unchecked Sendable { var now = MessageReadFixture.now }
    let clock = Clock()
    let (store, host) = makeMessageReadStore("menu-open") { call, _ in
        switch call.rpc {
        // 안 읽음이 **없는** 서버다(m-fix) — 점이 켜져 있으면 짧은 스로틀을 쓰므로(아래 `안_읽음_점이_켜져_있으면_…`) 이 테스트는
        // 점이 꺼진 맥의 60초 눈금만 잰다. 같은 새로고침 안에서는 이력이 요약보다 나중에 띄워진다 — 두 응답이 같은 사실을 말하게 한다.
        case "message_unread_summary": return Fx.summaryReply([])
        case "message_history_with_reads": return Fx.historyReply([Fx.readsRow(id: "b1", peer: Fx.peerB, isMine: false, unread: false)])
        case "gomoku_inbox": return MessageReadStubProtocol.Reply(body: #"{"status":"ok","incoming":[],"outgoing":null}"#)
        default: return nil
        }
    }
    store.clock = { clock.now }
    store.gomoku.clock = { clock.now }
    store.isMenuPresented = false

    store.setMenuPresented(true)
    await messageReadWait {
        v0330Rpc(host, "message_history_with_reads") >= 1 && v0330Rpc(host, "gomoku_inbox") >= 1 && messageReadIdle(store)
    }
    #expect(v0330Rpc(host, "message_unread_summary") == 1)
    #expect(v0330Rpc(host, "message_history_with_reads") == 1, "대화 패널이 안 보여도 팝오버 열기는 이력을 받는다(안 읽음 계산용)")
    #expect(v0330Rpc(host, "gomoku_inbox") == 1, "팝오버 열기가 오목 받은 신청을 안 봤다")
    #expect(store.messageReadReceiptsAvailable)
    #expect(!store.hasUnreadMessages)

    // 30초 뒤 다시 열면 스로틀.
    store.setMenuPresented(false)
    clock.now = clock.now.addingTimeInterval(30)
    store.setMenuPresented(true)
    try? await Task.sleep(for: .milliseconds(120))
    await messageReadWait { messageReadIdle(store) }
    #expect(v0330Rpc(host, "message_unread_summary") == 1)
    #expect(v0330Rpc(host, "message_history_with_reads") == 1)
    #expect(v0330Rpc(host, "gomoku_inbox") == 1)

    // 61초가 지나면 다시.
    store.setMenuPresented(false)
    clock.now = clock.now.addingTimeInterval(31)
    store.setMenuPresented(true)
    await messageReadWait { v0330Rpc(host, "message_unread_summary") >= 2 && v0330Rpc(host, "gomoku_inbox") >= 2 && messageReadIdle(store) }
    #expect(v0330Rpc(host, "message_unread_summary") == 2)
    #expect(v0330Rpc(host, "message_history_with_reads") == 2)
    #expect(v0330Rpc(host, "gomoku_inbox") == 2)
    store.tickerTask?.cancel()
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 메시지_활동_새로고침은_겹치지_않고_뒤따르는_한_번으로_합친다() async {
    let (store, host) = makeMessageReadStore("coalesce") { call, _ in
        call.rpc == "message_unread_summary" ? Fx.summaryReply([], delay: 0.3) : nil
    }
    let first = store.requestMessageActivityRefresh()
    await messageReadWait { v0330Rpc(host, "message_unread_summary") == 1 }
    let second = store.requestMessageActivityRefresh()
    store.requestMessageActivityRefresh()
    store.requestMessageActivityRefresh()
    #expect(first != nil && second == first, "진행 중인데 새 Task 를 만들었다")
    await first?.value
    await messageReadWait { messageReadIdle(store) }
    try? await Task.sleep(for: .milliseconds(400))
    #expect(v0330Rpc(host, "message_unread_summary") == 2, "진행 중 요청 셋은 뒤따르는 한 번이어야 한다(버리면 유실, 셋 다 쏘면 낭비)")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 점이_켜져_있어도_짧은_스로틀_안의_재오픈은_요청하지_않는다() async {
    final class Clock: @unchecked Sendable { var now = MessageReadFixture.now }
    let clock = Clock()
    let (store, host) = makeMessageReadStore("reopen-with-dot-burst") { call, _ in
        switch call.rpc {
        case "message_unread_summary": return Fx.summaryReply([(Fx.peerA, 1)])
        case "message_history_with_reads":
            return Fx.historyReply([Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: false, unread: true)])
        default: return nil
        }
    }
    store.clock = { clock.now }
    store.setMenuPresented(true)
    await messageReadWait { v0330Rpc(host, "message_history_with_reads") >= 1 && messageReadIdle(store) }
    #expect(store.hasUnreadMessages)
    // 연타(짧은 스로틀의 절반 뒤)는 요청을 내지 않는다. 시계는 앞으로만 민다 — "상한 − 1초"로 밀면 상한이 0 으로
    // 무너진 날 시계가 뒤로 가서 요청이 안 나가고 초록이 된다(m-fix 변이 MF15 에서 실측).
    store.setMenuPresented(false)
    clock.now = clock.now.addingTimeInterval(WorkTimerStore.messageMenuRefreshUnreadThrottleSeconds / 2)
    store.setMenuPresented(true)
    try? await Task.sleep(for: .milliseconds(120))
    await messageReadWait { messageReadIdle(store) }
    #expect(v0330Rpc(host, "message_unread_summary") == 1, "점이 켜진 팝오버 연타마다 요약을 쐈다")
    #expect(WorkTimerStore.messageMenuRefreshUnreadThrottleSeconds > 0)
    #expect(WorkTimerStore.messageMenuRefreshUnreadThrottleSeconds < WorkTimerStore.messageMenuRefreshThrottleSeconds)
    store.tickerTask?.cancel()
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 읽음을_모르는_옛_서버의_도장_점에는_짧은_스로틀을_주지_않는다() async {
    // 옛 서버(db push 전 창)의 점은 도장 규칙이라 앱을 켤 때마다 켜져 있다. 짧은 스로틀을 주면 여닫이마다 404 폴백까지 세 건이
    // 붙는데, 다시 물어도 꺼질 점이 아니다 — 짧은 스로틀은 서버가 판정한 점에만 준다.
    final class Clock: @unchecked Sendable { var now = MessageReadFixture.now }
    let clock = Clock()
    let (store, host) = makeMessageReadStore("legacy-dot-throttle") { call, _ in
        switch call.rpc {
        case "message_history_with_reads", "message_unread_summary": return Fx.missingFunction(call.rpc)
        case "message_history":
            return MessageReadStubProtocol.Reply(body: Fx.json([
                ["id": "old1", "from_user": Fx.peerA, "to_user": Fx.me, "body": "옛 서버", "is_mine": false,
                 "peer_user_id": Fx.peerA, "peer_display_name": "상대", "created_epoch": 1_789_999_000]
            ]))
        default: return nil
        }
    }
    store.clock = { clock.now }
    store.setMenuPresented(true)
    await messageReadWait { v0330Rpc(host, "message_history") >= 1 && messageReadIdle(store) }
    #expect(store.hasUnreadMessages, "전제: 옛 규칙(도장 없음)으로 점이 켜져 있다")
    #expect(store.messageUnreadSummary == nil && store.messageHistoryReadSnapshot == nil)

    store.setMenuPresented(false)
    clock.now = clock.now.addingTimeInterval(30)
    store.setMenuPresented(true)
    try? await Task.sleep(for: .milliseconds(120))
    await messageReadWait { messageReadIdle(store) }
    #expect(v0330Rpc(host, "message_unread_summary") == 1, "옛 서버의 도장 점에 짧은 스로틀을 줬다")
    #expect(v0330Rpc(host, "message_history") == 1)
    store.tickerTask?.cancel()
}

// MARK: - 캐릭터 말풍선은 읽음이 아니다 · 근무 시작 drain 필터

@MainActor
@Test(.gomokuDefaultsCleanup)
func 말풍선을_띄우고_넘겨도_읽음_처리는_나가지_않는다() async {
    let (store, host) = makeMessageReadStore("bubble-not-read") { call, _ in
        switch call.rpc {
        case "message_history_with_reads":
            return Fx.historyReply([Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: false, unread: true)])
        case "mark_messages_read": return Fx.markReply()
        default: return nil
        }
    }
    await store.performLoadMessageHistory()
    store.isMenuPresented = true      // 팝오버는 떠 있지만 대화 패널은 아니다
    store.enqueueReceivedMessages([
        ReceivedMessage(id: "m1", fromName: "상대", body: "안녕", createdAt: Fx.now, fromUserID: Fx.peerA)
    ])
    store.consumeCurrentMessage()
    #expect(store.lastShownMessage?.id == "m1")
    await messageReadWait { messageReadIdle(store) }
    try? await Task.sleep(for: .milliseconds(60))
    #expect(v0330Rpc(host, "mark_messages_read") == 0, "말풍선으로 본 것을 읽음으로 올렸다")
    #expect(store.unreadMessagePeerIDs == [Fx.peerA])

    // 말풍선을 눌러 대화가 열리면 그때 읽음이다.
    store.openMessagePanel(peer: Fx.peerA, from: .overlay)
    await messageReadWait { v0330Rpc(host, "mark_messages_read") >= 1 && messageReadIdle(store) }
    #expect(v0330Rpc(host, "mark_messages_read") >= 1)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 근무_시작_drain_은_이미_읽은_메시지를_말풍선으로_띄우지_않는다() async {
    let nowEpoch = Int(Date().timeIntervalSince1970)
    let (store, host) = makeMessageReadStore("drain-filter") { call, _ in
        switch call.rpc {
        case "take_pokes":
            return MessageReadStubProtocol.Reply(body: Fx.json([
                Fx.takenMessageRow(id: "read-on-phone", from: Fx.peerA, epoch: nowEpoch - 30),
                Fx.takenMessageRow(id: "read-optimistic", from: Fx.peerB, epoch: nowEpoch - 20),
                Fx.takenMessageRow(id: "fresh", from: Fx.peerB, epoch: nowEpoch - 10),
                Fx.takenMessageRow(id: "too-old", from: Fx.peerB, epoch: nowEpoch - 400)
            ]))
        default: return nil
        }
    }
    // 이력(서버 순서): peerA 의 것은 서버 기준 읽음, peerB 의 두 개 중 앞의 것까지 낙관 읽음.
    store.messageHistory = [
        MessageHistoryEntry(id: "read-on-phone", peerUserID: Fx.peerA, peerName: "A", peerAvatarURL: nil, body: "1",
                            createdAt: Fx.now, isMine: false, isUnread: false),
        MessageHistoryEntry(id: "read-optimistic", peerUserID: Fx.peerB, peerName: "B", peerAvatarURL: nil, body: "2",
                            createdAt: Fx.now, isMine: false, isUnread: true),
        MessageHistoryEntry(id: "fresh", peerUserID: Fx.peerB, peerName: "B", peerAvatarURL: nil, body: "3",
                            createdAt: Fx.now, isMine: false, isUnread: true)
    ]
    store.messageHistoryReadSnapshot = MessageHistoryReadSnapshot(
        serial: 1, serverOrder: ["read-on-phone": 0, "read-optimistic": 1, "fresh": 2]
    )
    store.messageOptimisticReads[Fx.peerB] = MessageOptimisticRead(throughID: "read-optimistic", recordedSerial: 2)

    store.startedAt = Date()
    _ = await store.drainReceivedPokes()
    #expect(v0330Rpc(host, "take_pokes") == 1)
    #expect(store.receivedMessages.map(\.id) == ["fresh"],
            "읽은 메시지가 말풍선 큐에 올랐다(또는 5분 넘은 것이 되살아났다): \(store.receivedMessages.map(\.id))")
}

// MARK: - 세대 가드 · 로그아웃

@MainActor
@Test(.gomokuDefaultsCleanup)
func 로그아웃_뒤_늦게_온_요약_이력_읽음_응답은_다음_계정에_안_들어간다() async {
    let (store, host) = makeMessageReadStore("generation") { call, _ in
        switch call.rpc {
        case "message_unread_summary": return Fx.summaryReply([(Fx.peerA, 3)], delay: 0.3)
        case "message_history_with_reads":
            return Fx.historyReply([Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: false, unread: true)], delay: 0.3)
        case "mark_messages_read": return Fx.markReply(delay: 0.3)
        default: return nil
        }
    }
    // 앞 계정: 읽음 처리까지 날아가게 만든다.
    store.messageHistory = [MessageHistoryEntry(id: "m1", peerUserID: Fx.peerA, peerName: "A", peerAvatarURL: nil,
                                                body: "x", createdAt: Fx.now, isMine: false, isUnread: true)]
    store.messageHistoryReadSnapshot = MessageHistoryReadSnapshot(serial: 1, serverOrder: ["m1": 0])
    v0330OpenConversation(store)
    store.evaluateMessageReadMarking()
    let refresh = store.requestMessageActivityRefresh(includeHistory: true)
    await messageReadWait {
        v0330Rpc(host, "message_unread_summary") == 1 && v0330Rpc(host, "mark_messages_read") == 1
    }

    // 계정 전환.
    store.clearPersistedSession()
    store.session = SupabaseSession(accessToken: "next-token", refreshToken: nil, userID: Fx.peerB)
    #expect(store.messageOptimisticReads.isEmpty)
    #expect(store.messageUnreadSummary == nil)
    #expect(!store.messageReadReceiptsAvailable)

    await refresh?.value
    try? await Task.sleep(for: .milliseconds(500))
    #expect(store.messageUnreadSummary == nil, "앞 계정의 요약이 새 계정에 들어갔다")
    #expect(store.messageHistory.isEmpty, "앞 계정의 대화가 새 계정에 들어갔다")
    #expect(store.messageOptimisticReads.isEmpty, "앞 계정의 읽음 정산이 새 계정 장부에 들어갔다")
    #expect(!store.hasUnreadMessages)
    // 새 계정의 새로고침은 막히지 않는다(앞 계정의 왕복이 "도는 중"으로 남아 있지 않다).
    #expect(store.messageReadRuntime.activityTask == nil)
    #expect(store.messageReadRuntime.markInFlight.isEmpty)
}

@Test
func 로그아웃은_scope_local_로_보낸다() async throws {
    let host = "v0330-logout-\(UUID().uuidString.prefix(8))".lowercased()
    MessageReadStubProtocol.register(host: host) { _, _ in MessageReadStubProtocol.Reply(status: 204, body: "") }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: MessageReadStubProtocol.session()
    )
    await service.signOut(accessToken: "access-token")
    let call = try #require(MessageReadStubProtocol.calls(host: host).first)
    #expect(call.path == "/auth/v1/logout")
    #expect(call.method == "POST")
    let items = URLComponents(url: call.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(items == [URLQueryItem(name: "scope", value: "local")],
            "로그아웃이 scope=local 이 아니다 — 기본 global 이면 같은 계정의 폰·다른 맥 세션까지 끊긴다")
}
