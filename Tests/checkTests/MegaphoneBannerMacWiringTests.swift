import Foundation
import Testing
@testable import check
@testable import CheckCore

// 2026-10-30 — 확성기 배너 맥 배선(계약 docs/plan/megaphone-banner-contract.md C3 · "맥 배너" 실시간 줄 · C2 본인 배너).
//
// 진짜 `WorkTimerStore` + 진짜 `MegaphoneBannerStore` + 스텁 서버(`MessageReadStubProtocol` — 시험마다 고유 호스트)로 잰다.
// 재는 것은 **화면이 읽는 자리**다: 대화 목록·열린 대화(`messageThreads`), 안 읽음 사람·메뉴바 점(`unreadMessagePeerIDs` ·
// `hasUnreadMessages`), 말풍선 큐(`receivedMessages`), 팝오버 도착 줄(`visibleLatestMessage`).
//
// 시험마다 비교 기준선을 둔다 — 같은 서버에서 `megaphone_inbox` 하나만 없는 옛 서버로 바꾸면(필터 꺼짐) 확성기 줄이 지금처럼
// 메시지로 서는 것을 같은 단언 자리에서 보인다("숨긴다"가 늘 참이라 초록인 시험이 아니게).

private typealias Fx = MessageReadFixture

private let mbwMega = "mg-1"        // 확성기 줄 — inbox 가 안다
private let mbwFake = "mg-fake"     // 📢 로 시작하지만 inbox 가 모르는 줄(위조 DM)
private let mbwPlain = "a-1"
private let mbwEpoch = Int(MessageReadFixture.now.timeIntervalSince1970)

private func mbwInboxRow(_ id: String) -> [String: Any] {
    ["message_id": id, "megaphone_id": "mp-" + id, "sender_id": Fx.peerB, "sender_display_name": "확성기님",
     "sender_avatar_url": NSNull(), "body": "라운지에 간식 있어요", "created_epoch": mbwEpoch - 30]
}

/// 서버 모형. 이력: peerA 의 보통 말(읽음 여부는 인자) + peerB 의 확성기 줄(안 읽음). `inboxAvailable == false` 면 inbox · v2 가 없는 옛 서버.
/// 요약: v2 는 확성기 줄을 안 센다(peerA 만), 옛 함수는 센다(peerA · peerB).
private func mbwServer(
    inboxAvailable: Bool,
    plainUnread: Bool = true,
    inboxIDs: [String] = [mbwMega],
    withFakeRow: Bool = false,
    inboxGate: MessageReadStubGate? = nil
) -> MessageReadStubProtocol.Handler {
    { call, _ in
        switch call.rpc {
        case "message_history_with_reads":
            return Fx.historyReply([
                Fx.readsRow(id: mbwPlain, peer: Fx.peerA, isMine: false, body: "밥 먹었어?", epoch: mbwEpoch - 60, unread: plainUnread),
                Fx.readsRow(id: mbwMega, peer: Fx.peerB, isMine: false, body: "📢 라운지에 간식 있어요", epoch: mbwEpoch - 30,
                            unread: true, name: "확성기님")
            ] + (withFakeRow ? [
                Fx.readsRow(id: mbwFake, peer: Fx.peerA, isMine: false, body: "📢 이건 그냥 메시지예요", epoch: mbwEpoch - 10, unread: false)
            ] : []))
        case "megaphone_inbox":
            guard inboxAvailable else { return Fx.missingFunction("megaphone_inbox") }
            return MessageReadStubProtocol.Reply(body: Fx.json(inboxIDs.map(mbwInboxRow)), gate: inboxGate)
        case "message_unread_summary_v2":
            guard inboxAvailable else { return Fx.missingFunction("message_unread_summary_v2") }
            return Fx.summaryReply(plainUnread ? [(Fx.peerA, 1)] : [])
        case "message_unread_summary":
            return Fx.summaryReply(plainUnread ? [(Fx.peerA, 1), (Fx.peerB, 1)] : [(Fx.peerB, 1)])
        case "mark_messages_read":
            return Fx.markReply()
        default:
            return nil
        }
    }
}

@MainActor
private func mbwStore(_ label: String, transport: RealtimeTransport? = nil,
                      _ handler: @escaping MessageReadStubProtocol.Handler) -> (WorkTimerStore, String) {
    let (store, host) = makeMessageReadStore("mbw-" + label, transport: transport, handler: handler)
    // 배너 타이머는 걸기만 하고 안 부른다(5초를 기다리지 않는다 — 이 파일은 배너 표시가 아니라 필터 자리를 잰다).
    store.megaphoneBanner.schedule = { _, _ in }
    store.megaphoneBanner.clock = { Fx.now }
    return (store, host)
}

@MainActor
private func mbwCount(_ host: String, _ rpc: String) -> Int {
    MessageReadStubProtocol.count(host: host, rpc: rpc)
}

@MainActor
private func mbwRow(_ id: String, from peer: String, body: String) -> TakenPokeRow {
    TakenPokeRow(id: id, fromUser: peer, fromDisplayName: "상대", fromAvatarUrl: nil,
                 createdEpoch: mbwEpoch - 1, kind: "message", body: body)
}

/// 배너 목록을 한 번 받아 필터 상태를 정한다(inbox 가 있으면 `.available`, 없으면 `.unavailable`).
@MainActor
private func mbwSettleCapability(_ store: WorkTimerStore) async {
    await store.requestMegaphoneBannerRefresh()?.value
    await messageReadWait { messageReadIdle(store) }
}

// MARK: - 필터 자리

@MainActor
@Suite struct MegaphoneBannerMacWiringTests {
    @Test("대화 목록 · 열린 대화 · 안 읽음 사람 · 메뉴바 점이 확성기 줄을 뺀다 — 옛 서버면 지금처럼 메시지로 선다", .gomokuDefaultsCleanup)
    func listThreadUnreadAndDotDropMegaphoneRow() async {
        for inbox in [true, false] {
            // 보통 말은 읽었다 — 남은 안 읽음은 확성기 줄 하나뿐이라 메뉴바 점이 그 줄 하나로 갈린다.
            let (store, host) = mbwStore("list-\(inbox)", mbwServer(inboxAvailable: inbox, plainUnread: false))
            await mbwSettleCapability(store)
            await store.performLoadMessageHistory()
            await messageReadWait { messageReadIdle(store) }

            // 이력 판 자체는 서버가 답한 그대로다(배너 목록이 늦게 와도 읽는 자리가 다시 거른다).
            #expect(Set(store.messageHistory.map(\.id)) == [mbwPlain, mbwMega], "inbox=\(inbox)")
            let threadPeers = Set(store.messageThreads.map(\.peerUserID))
            if inbox {
                #expect(store.megaphoneBanner.capability == .available)
                #expect(threadPeers == [Fx.peerA], "확성기 보낸 사람이 대화 목록에 섰다")
                #expect(!store.messageThreads.contains { $0.peerUserID == Fx.peerB }, "열린 대화에 확성기 줄이 남았다")
                #expect(store.unreadMessagePeerIDs.isEmpty, "확성기 줄이 안 읽음으로 셌다")
                #expect(store.unreadConversationPeerIDs.isEmpty, "목록 점이 확성기 줄로 켜졌다")
                #expect(!store.hasUnreadMessages, "메뉴바 점이 확성기 줄 하나로 켜졌다")
            } else {
                // 기준선: 같은 이력인데 inbox 가 없는 서버 — 필터가 꺼져 지금처럼 메시지로 보인다.
                #expect(store.megaphoneBanner.capability == .unavailable)
                #expect(threadPeers == [Fx.peerA, Fx.peerB])
                #expect(store.unreadMessagePeerIDs == [Fx.peerB])
                #expect(store.hasUnreadMessages)
            }
            #expect(mbwCount(host, "megaphone_inbox") == 1)
        }
    }

    @Test("옛 요약을 들고 있다가 필터가 켜지면 v2 로 한 번 다시 받는다 — 요약이 더 새로울 때도 점이 확성기 줄을 안 센다", .gomokuDefaultsCleanup)
    func unreadSummarySwitchesToV2WhenFilterTurnsOn() async {
        for inbox in [true, false] {
            let (store, host) = mbwStore("summary-\(inbox)", mbwServer(inboxAvailable: inbox))
            // 로그인 직후 — 배너 목록을 아직 모른다: 옛 함수로 받는다(확성기 줄도 센다).
            await store.performLoadMessageUnreadSummary()
            #expect(mbwCount(host, "message_unread_summary") == 1 && mbwCount(host, "message_unread_summary_v2") == 0)
            #expect(store.unreadMessagePeerIDs == [Fx.peerA, Fx.peerB], "전제: 옛 요약은 확성기 줄도 센다")

            await mbwSettleCapability(store)
            await messageReadWait { messageReadIdle(store) && (!inbox || mbwCount(host, "message_unread_summary_v2") >= 1) }
            if inbox {
                #expect(store.megaphoneBanner.unreadSummaryFunction == "message_unread_summary_v2")
                #expect(mbwCount(host, "message_unread_summary_v2") == 1, "필터가 켜졌는데 요약을 다시 안 받았다")
                #expect(store.unreadMessagePeerIDs == [Fx.peerA], "요약이 확성기 줄을 셌다")
            } else {
                // 기준선: inbox 가 없는 서버 — 필터가 안 켜졌으니 다시 받지 않고, 옛 요약 그대로 둘 다 센다.
                #expect(store.megaphoneBanner.unreadSummaryFunction == "message_unread_summary")
                #expect(mbwCount(host, "message_unread_summary_v2") == 0)
                #expect(store.unreadMessagePeerIDs == [Fx.peerA, Fx.peerB])
            }
        }
    }

    @Test("말풍선 큐 · 팝오버 도착 줄이 확성기 줄을 뺀다 — 옛 서버면 지금처럼 둘 다 선다", .gomokuDefaultsCleanup)
    func bubbleQueueAndReceiptStripDropMegaphoneRow() async {
        for inbox in [true, false] {
            let (store, host) = mbwStore("bubble-\(inbox)", mbwServer(inboxAvailable: inbox))
            await mbwSettleCapability(store)
            store.receiveConsumedMessages(rows: [
                mbwRow(mbwMega, from: Fx.peerB, body: "📢 라운지에 간식 있어요"),
                mbwRow("a-2", from: Fx.peerA, body: "밥?")
            ], now: Fx.now)
            await messageReadWait { messageReadIdle(store) }
            let queued = store.receivedMessages.map(\.id)
            if inbox {
                #expect(queued == ["a-2"], "말풍선 큐에 확성기 줄이 섰다: \(queued)")
                #expect(store.visibleLatestMessage?.id == "a-2")
            } else {
                #expect(queued == [mbwMega, "a-2"])
                #expect(store.visibleLatestMessage?.id == mbwMega)
            }
            // 아는 줄은 다시 묻지 않는다(판정 보류가 아니다).
            #expect(mbwCount(host, "megaphone_inbox") == 1)
        }
    }

    @Test("판정 보류(도착): 📢 줄은 배너 목록을 한 번 받아 본 뒤 거른다 — 목록이 모르는 📢 줄은 메시지로 돌아온다", .gomokuDefaultsCleanup)
    func arrivalHoldsPrefixedRowsUntilOneRefresh() async {
        let gate = MessageReadStubGate()
        let (store, host) = mbwStore("hold-arrival", mbwServer(inboxAvailable: true, inboxGate: gate))
        #expect(store.megaphoneBanner.capability == .unknown, "전제: 배너 목록을 아직 모른다")
        store.receiveConsumedMessages(rows: [
            mbwRow(mbwMega, from: Fx.peerB, body: "📢 라운지에 간식 있어요"),
            mbwRow(mbwFake, from: Fx.peerA, body: "📢 이건 그냥 메시지예요"),
            mbwRow("a-3", from: Fx.peerA, body: "밥?")
        ], now: Fx.now)
        // 보통 말은 곧바로, 📢 두 줄은 붙든다(접두만 보고 숨기지도 띄우지도 않는다).
        #expect(store.receivedMessages.map(\.id) == ["a-3"])
        await messageReadWait { mbwCount(host, "megaphone_inbox") >= 1 }
        gate.open()
        await messageReadWait { store.receivedMessages.contains { $0.id == mbwFake } && messageReadIdle(store) }
        let queued = store.receivedMessages.map(\.id)
        #expect(queued == ["a-3", mbwFake], "목록이 아는 줄은 빠지고 모르는 📢 줄은 돌아와야 한다: \(queued)")
        #expect(mbwCount(host, "megaphone_inbox") == 1, "두 줄을 한 번에 확인하지 않았다")
    }

    @Test("판정 보류(이력): 📢 줄은 목록을 받을 때까지 대화에 안 서고, 받은 뒤 목록이 모르는 줄만 선다", .gomokuDefaultsCleanup)
    func historyHoldsPrefixedRowsUntilOneRefresh() async {
        let gate = MessageReadStubGate()
        let (store, host) = mbwStore("hold-history", mbwServer(inboxAvailable: true, withFakeRow: true, inboxGate: gate))
        await store.performLoadMessageHistory()
        // 이력 응답 자리가 확인을 띄웠다(부르는 자리) — 응답 전에는 📢 두 줄 다 붙든다.
        await messageReadWait { mbwCount(host, "megaphone_inbox") >= 1 }
        #expect(mbwCount(host, "megaphone_inbox") == 1, "이력 응답이 배너 목록 확인을 안 띄웠다")
        #expect(Set(store.visibleMessageHistory.map(\.id)) == [mbwPlain], "판정 전 📢 줄이 대화에 섰다")
        gate.open()
        await messageReadWait { store.visibleMessageHistory.contains { $0.id == mbwFake } && messageReadIdle(store) }
        #expect(Set(store.visibleMessageHistory.map(\.id)) == [mbwPlain, mbwFake])
        #expect(store.messageThreads.first { $0.peerUserID == Fx.peerA }?.messages.map(\.id) == [mbwPlain, mbwFake])
        #expect(!store.messageThreads.contains { $0.peerUserID == Fx.peerB })
    }

    // MARK: - 실시간 · 예비 경로

    @Test("링: 'megaphone' 은 배너 신호로 가르고 drain 으로 보내지 않는다 — 모르는 이름은 여전히 drain", .gomokuDefaultsCleanup)
    func realtimeLinkRoutesMegaphoneEvent() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(RealtimeLinkConstants.megaphoneBroadcastEvent == "megaphone")
        var link = RealtimeLink(transportAvailable: true)
        _ = link.apply(.signedIn(accessToken: "tok"), now: t0, jitter: { $0 })
        _ = link.apply(.transport(.joined), now: t0, jitter: { $0 })
        #expect(link.apply(.transport(.broadcast(event: "megaphone")), now: t0 + 1, jitter: { $0 }) == [.megaphoneSignal])
        #expect(link.apply(.transport(.broadcast(event: "MEGAPHONE")), now: t0 + 2, jitter: { $0 }) == [.drain])
        #expect(link.apply(.transport(.broadcast(event: "ring")), now: t0 + 3, jitter: { $0 }) == [.drain])
        #expect(link.apply(.transport(.broadcast(event: "gomoku")), now: t0 + 4, jitter: { $0 }) == [.gomokuSignal])
    }

    @Test("스토어: 'megaphone' 신호는 배너 목록을 받고 메시지 요약은 안 받는다 — 모르는 이름은 메시지 쪽(drain)으로 간다", .gomokuDefaultsCleanup)
    func realtimeSignalRefreshesBannerOnly() async {
        let transport = FakeRealtimeTransport()
        let (store, host) = mbwStore("realtime", transport: transport, mbwServer(inboxAvailable: true))
        store.startRealtimeIfPossible()
        transport.emit(.joined)
        await messageReadWait { messageReadIdle(store) }
        // 필터를 먼저 켜 둔다 — 켜지는 순간의 요약 재조회(위 시험)가 아래 셈에 섞이지 않게.
        await mbwSettleCapability(store)
        try? await Task.sleep(for: .milliseconds(50))
        await messageReadWait { messageReadIdle(store) }
        func summaries() -> Int { mbwCount(host, "message_unread_summary") + mbwCount(host, "message_unread_summary_v2") }
        let inbox0 = mbwCount(host, "megaphone_inbox")
        let summary0 = summaries()

        transport.emit(.broadcast(event: "megaphone"))
        await messageReadWait { mbwCount(host, "megaphone_inbox") > inbox0 }
        try? await Task.sleep(for: .milliseconds(50))
        await messageReadWait { messageReadIdle(store) }
        #expect(mbwCount(host, "megaphone_inbox") == inbox0 + 1, "배너 신호가 배너 목록을 안 받았다")
        #expect(summaries() == summary0, "배너 신호가 메시지 요약을 받았다(drain 으로 샜다)")
        #expect(mbwCount(host, "take_pokes") == 0, "배너 신호가 take_pokes 를 불렀다")

        // 기준선: 모르는 이름은 배너 목록을 안 받고 메시지 쪽(근무 밖 맥 — 요약 새로고침)으로 간다.
        transport.emit(.broadcast(event: "megaphone_x"))
        await messageReadWait { summaries() > summary0 && messageReadIdle(store) }
        #expect(mbwCount(host, "megaphone_inbox") == inbox0 + 1, "모르는 이름이 배너 목록을 받았다")
        #expect(summaries() == summary0 + 1)
    }

    @Test("예비 경로: 팝오버를 열면 배너 목록을 받되 60초 안에 다시 열면 안 받는다", .gomokuDefaultsCleanup)
    func menuOpenRefreshIsThrottled() async {
        final class Clock: @unchecked Sendable { var now = MessageReadFixture.now }
        let clock = Clock()
        let (store, host) = mbwStore("menu-open", mbwServer(inboxAvailable: true))
        store.clock = { clock.now }
        store.setMenuPresented(true)
        await messageReadWait { mbwCount(host, "megaphone_inbox") >= 1 && messageReadIdle(store) }
        #expect(mbwCount(host, "megaphone_inbox") == 1, "팝오버 열기가 배너 목록을 안 받았다")
        store.setMenuPresented(false)

        clock.now = MessageReadFixture.now.addingTimeInterval(59)
        store.setMenuPresented(true)
        await messageReadWait { messageReadIdle(store) }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(mbwCount(host, "megaphone_inbox") == 1, "60초 안에 다시 받았다")
        store.setMenuPresented(false)

        // 기준선: 60초가 지나면 같은 열기가 다시 받는다(스로틀이 결과를 가른다).
        clock.now = MessageReadFixture.now.addingTimeInterval(61)
        store.setMenuPresented(true)
        await messageReadWait { mbwCount(host, "megaphone_inbox") >= 2 }
        #expect(mbwCount(host, "megaphone_inbox") == 2)
        store.setMenuPresented(false)
    }

    // MARK: - 로그아웃 · 본인 배너

    @Test("로그아웃은 필터 id · 상태 · 스로틀을 비우고, 나가 있던 목록 응답은 다음 계정에 안 닿는다", .gomokuDefaultsCleanup)
    func signOutResetsBannerState() async {
        let gate = MessageReadStubGate()
        let (store, host) = mbwStore("signout", mbwServer(inboxAvailable: true, inboxGate: gate))
        gate.open()
        await mbwSettleCapability(store)
        // 기준선: 로그아웃 전에는 채워져 있다.
        #expect(store.megaphoneBanner.capability == .available)
        #expect(store.megaphoneBanner.knownMessageIDs == [mbwMega])
        #expect(store.megaphoneBannerLastRefreshAt != .distantPast)

        store.clearPersistedSession()
        #expect(store.megaphoneBanner.capability == .unknown)
        #expect(store.megaphoneBanner.knownMessageIDs.isEmpty)
        #expect(store.megaphoneBannerLastRefreshAt == .distantPast)

        // 다음 계정: 앞 계정의 목록 응답이 늦게 와도 필터 id 로 안 들어온다.
        let slow = MessageReadStubGate()
        let (next, nextHost) = mbwStore("signout-next", mbwServer(inboxAvailable: true, inboxGate: slow))
        let inflight = next.requestMegaphoneBannerRefresh()
        await messageReadWait { mbwCount(nextHost, "megaphone_inbox") >= 1 }
        next.clearPersistedSession()
        slow.open()
        await inflight?.value
        #expect(next.megaphoneBanner.knownMessageIDs.isEmpty, "로그아웃 뒤 도착한 응답이 필터 id 를 채웠다")
        #expect(next.megaphoneBanner.capability == .unknown)
        _ = host
    }

    @Test("보내기 성공 뒤 자기 배너를 한 번 띄운다 — 거절이면 안 띄운다", .gomokuDefaultsCleanup)
    func sendSuccessPresentsOwnBanner() async {
        for success in [true, false] {
            let handler: MessageReadStubProtocol.Handler = { call, _ in
                switch call.rpc {
                case "megaphone_info":
                    return MessageReadStubProtocol.Reply(body: #"{"status":"ok","enabled":true,"price":50,"cooldown_seconds":600,"cooldown_remaining_seconds":0,"recipients":12,"max_length":198,"ruby_balance":120}"#)
                case "send_megaphone":
                    return MessageReadStubProtocol.Reply(body: success
                        ? #"{"status":"ok","duplicate":false,"megaphone_id":"mp-own","recipients":12,"price":50,"ruby_balance":70}"#
                        : #"{"status":"insufficient","need":50,"have":10,"ruby_balance":10}"#)
                default: return nil
                }
            }
            let (store, host) = mbwStore("own-\(success)", handler)
            store.displayName = "나야나"
            store.isShopPanelVisible = true
            store.toggleMegaphoneComposer()
            await messageReadWait { store.megaphone.info != nil }
            store.megaphone.setDraft("오늘 3시 라운지에서 간식 나눠요")
            store.megaphone.requestSend()
            #expect(store.megaphone.confirmSend())
            await messageReadWait { !store.megaphone.isSending && mbwCount(host, "send_megaphone") == 1 }
            await messageReadWait { !store.megaphone.infoLoading }
            if success {
                let own = store.megaphoneBanner.current
                #expect(own?.isOwn == true, "보낸 뒤 자기 배너가 안 떴다")
                #expect(own?.body == "오늘 3시 라운지에서 간식 나눠요")
                #expect(own?.megaphoneID == "mp-own")
                #expect(own?.senderName == "나야나")
            } else {
                #expect(store.megaphoneBanner.current == nil, "거절됐는데 자기 배너가 떴다")
            }
        }
    }
}
