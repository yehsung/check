import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// MARK: - 확성기 배너 · 폰 배선(계약 docs/plan/megaphone-banner-contract.md — 폰)
//
// 배너 뷰는 다음 갈래 몫이다. 여기서는 **배선**만 잰다 — 앱 모델이 배너 스토어 하나를 만들어 메시지함 필터(`visibleHistory`)·
// 안 읽음 요약(v1/v2)·푸시(앞/뒤 · 눌러 들어옴)·실시간(`megaphone`)·전송 뒤 내 배너·로그아웃이 그 하나를 보는가.
// 시험마다 같은 줄을 **다른 기준선**(배너 RPC 없음 · 표식 없음 · 다른 신호 이름)과 나란히 둔다 — 결과를 가르는 것이 배선임을 보이려고.

@MainActor
@Suite(.serialized) struct MegaphoneBannerPhoneTests {
    nonisolated static let peerA = "p-friend"
    nonisolated static let peerMega = "p-mega"

    nonisolated static func inbox(_ items: [(message: String, megaphone: String, sender: String, body: String, offset: Int)]) -> String {
        "[" + items.map { item in
            #"{"message_id":"\#(item.message)","megaphone_id":"\#(item.megaphone)","sender_id":"\#(item.sender)","#
                + #""sender_display_name":"확성기님","sender_avatar_url":null,"body":"\#(item.body)","#
                + #""created_at":null,"created_epoch":\#(MessagesHarness.base + item.offset)}"#
        }.joined(separator: ",") + "]"
    }

    /// 배너 첫 판정(probe)과 그 뒤 요약·이력이 끝날 때까지.
    static func settleBanner(_ h: MessagesHarness) async {
        _ = await baseWaitUntil { h.model.megaphoneBanner.capability != .unknown || h.model.megaphoneBanner.lastRefreshFailed }
        await h.settle()
        await h.barrier()
        await h.settle()
    }

    static func megaphonePushJSON(megaphoneID: String?, peer: String = peerMega) -> Data {
        var text = #"{"aps":{"alert":{"title":"확성기님","body":"📢 다 같이 오목!"},"category":"MESSAGE"},"type":"message","peer_id":"\#(peer)""#
        if let megaphoneID { text += #","megaphone_id":"\#(megaphoneID)""# }
        return Data((text + "}").utf8)
    }

    // MARK: 필터 — visibleHistory 한 자리에서 배지까지

    @Test("필터: inbox 가 말한 줄은 visibleHistory 에서 빠지고 대화·안 읽음·탭 배지·앱 아이콘 배지가 따라온다 · 요약은 첫 판정을 기다려 v2")
    func filterReachesBadges() async {
        let h = await MessagesHarness.make { server in
            server.setRows([
                .received("n1", from: Self.peerA, at: 10),
                .received("m1", from: Self.peerMega, body: "📢 다 같이 오목!", at: 20),
            ])
            server.setSummary(MessagesStubServer.summary([(Self.peerA, 1), (Self.peerMega, 1)]))
            server.override("megaphone_inbox") { _ in .json(Self.inbox([("m1", "mg1", Self.peerMega, "다 같이 오목!", 20)])) }
            server.override("message_unread_summary_v2") { _ in .json(MessagesStubServer.summary([(Self.peerA, 1)])) }
        }
        defer { h.tearDown() }
        await Self.settleBanner(h)
        let banner = h.model.megaphoneBanner
        #expect(h.model.links.megaphoneBanner === banner, "링크가 앱 모델의 배너 스토어를 안 가리킨다")
        #expect(banner.capability == .available)
        #expect(banner.knownMessageIDs == ["m1"])
        #expect(h.count("message_unread_summary") == 0, "첫 요약이 배너 판정을 안 기다리고 옛 함수로 나갔다")
        #expect(h.count("message_unread_summary_v2") >= 1)
        #expect(h.store.badgeCount == 1, "요약(v2) 기준 탭 배지: \(h.store.badgeCount)")

        h.store.requestActivityRefresh(includeHistory: true)
        await h.settle()
        #expect(h.store.history.contains { $0.id == "m1" }, "원본 이력에는 있어야 한다(거르는 곳은 visibleHistory 하나)")
        #expect(!h.store.visibleHistory.contains { $0.id == "m1" })
        #expect(h.store.threads.map(\.peerUserID) == [Self.peerA], "대화 목록에 확성기 보낸 사람이 남았다")
        #expect(h.store.unreadPeerIDs == [Self.peerA])
        #expect(h.store.badgeCount == 1)
        #expect(h.model.badges.messages == 1)
        #expect(h.model.badges.appBadgeTotal == 1, "앱 아이콘 배지가 확성기 줄을 센다")
        h.expectNoForbiddenCalls()
    }

    @Test("기준선: 서버에 배너 RPC 가 없으면(.unavailable) 지금처럼 — 📢 줄이 메시지로 보이고 옛 요약 · 배지 2")
    func unavailableKeepsMessages() async {
        let h = await MessagesHarness.make { server in
            server.setRows([
                .received("n1", from: Self.peerA, at: 10),
                .received("m1", from: Self.peerMega, body: "📢 다 같이 오목!", at: 20),
            ])
            server.setSummary(MessagesStubServer.summary([(Self.peerA, 1), (Self.peerMega, 1)]))
        }
        defer { h.tearDown() }
        await Self.settleBanner(h)
        h.store.requestActivityRefresh(includeHistory: true)
        await h.settle()
        #expect(h.model.megaphoneBanner.capability == .unavailable)
        #expect(h.count("message_unread_summary_v2") == 0)
        #expect(h.count("message_unread_summary") >= 1)
        #expect(h.store.visibleHistory.contains { $0.id == "m1" })
        #expect(Set(h.store.threads.map(\.peerUserID)) == [Self.peerA, Self.peerMega])
        #expect(h.store.badgeCount == 2)
        #expect(h.model.badges.appBadgeTotal == 2)
    }

    @Test("v2 요약이 없는 서버: 옛 요약으로 내려가고 필터도 꺼진다(줄만 숨기면 배지가 고착)")
    func missingV2TurnsFilterOff() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("m1", from: Self.peerMega, body: "📢 다 같이 오목!", at: 20)])
            server.setSummary(MessagesStubServer.summary([(Self.peerMega, 1)]))
            server.override("megaphone_inbox") { _ in .json(Self.inbox([("m1", "mg1", Self.peerMega, "다 같이 오목!", 20)])) }
        }
        defer { h.tearDown() }
        await Self.settleBanner(h)
        h.store.requestActivityRefresh(includeHistory: true)
        await h.settle()
        #expect(h.count("message_unread_summary_v2") >= 1)
        #expect(h.count("message_unread_summary") >= 1, "v2 실패 뒤 옛 함수로 안 내려갔다")
        #expect(h.model.megaphoneBanner.capability == .unavailable)
        #expect(h.store.visibleHistory.contains { $0.id == "m1" }, "필터가 안 꺼져 옛 요약이 세는 줄을 숨겼다")
        #expect(h.store.badgeCount == 1)
    }

    @Test("경합: 📢 로 시작하는데 id 를 모르는 받은 줄은 refresh 한 번 뒤 판정 — inbox 에 있으면 숨김, 없으면(위조) 메시지")
    func prefixRowsWaitForOneRefresh() async {
        let inboxText = BaseLockedBox<String>("[]")
        let h = await MessagesHarness.make { server in
            server.setRows([.received("f1", from: Self.peerA, body: "📢 장난이에요", at: 10)])
            server.setSummary(MessagesStubServer.summary([(Self.peerA, 1)]))
            server.override("megaphone_inbox") { _ in .json(inboxText.get()) }
            server.override("message_unread_summary_v2") { _ in .json(MessagesStubServer.summary([(Self.peerA, 1)])) }
        }
        defer { h.tearDown() }
        await Self.settleBanner(h)
        let banner = h.model.megaphoneBanner
        #expect(banner.capability == .available)
        let probeCalls = h.count("megaphone_inbox")
        h.store.requestActivityRefresh(includeHistory: true)
        await h.settle()
        #expect(await baseWaitUntil { h.store.visibleHistory.contains { $0.id == "f1" } }, "접두만 있는 위조 DM 이 refresh 뒤에도 안 보인다")
        #expect(h.count("megaphone_inbox") == probeCalls + 1, "판정 보류 줄이 refresh 를 한 번 거치지 않았다")
        #expect(!banner.hides(messageID: "f1"))

        // 울림·이력이 배너 신호보다 먼저 온 진짜 확성기 줄.
        inboxText.mutate { $0 = Self.inbox([("m2", "mg2", Self.peerMega, "진짜 확성기", 30)]) }
        h.server.appendRow(.received("m2", from: Self.peerMega, body: "📢 진짜 확성기", at: 30))
        let before = h.count("megaphone_inbox")
        h.store.requestActivityRefresh(includeHistory: true)
        await h.settle()
        #expect(await baseWaitUntil { banner.knownMessageIDs.contains("m2") })
        await h.barrier()
        #expect(h.count("megaphone_inbox") == before + 1)
        #expect(banner.hides(messageID: "m2"))
        #expect(!h.store.visibleHistory.contains { $0.id == "m2" })
        #expect(h.store.visibleHistory.contains { $0.id == "f1" }, "같은 접두의 위조 줄까지 숨겼다")
    }

    // MARK: 푸시

    @Test("PushPayload: megaphone_id 는 옵셔널 키 — 새 종류 없음 · 옛 라우트 그대로 · 모양이 틀리면 없는 것으로 · 메시지 밖에서는 안 읽는다")
    func payloadOptionalKey() throws {
        let marked = try #require(PushPayload(json: Self.megaphonePushJSON(megaphoneID: "D0000000-0000-4000-8000-0000000000E2")))
        #expect(marked.megaphoneID == "d0000000-0000-4000-8000-0000000000e2")
        #expect(marked.kind == .message)
        #expect(marked.route == .message(peerID: Self.peerMega), "옛 라우트가 바뀌었다(옛 폰과 같은 뜻이어야 한다)")
        let plain = try #require(PushPayload(json: Self.megaphonePushJSON(megaphoneID: nil)))
        #expect(plain.megaphoneID == nil)
        #expect(plain == PushPayload(content: .message(peerID: Self.peerMega)))
        #expect(marked != plain)
        let broken = try #require(PushPayload(json: Self.megaphonePushJSON(megaphoneID: "bad id!")))
        #expect(broken.megaphoneID == nil, "모양이 틀린 키가 살아남았다")
        let invite = try #require(PushPayload(json: Data(#"{"type":"gomoku_invite","match_id":"m-1","megaphone_id":"mg"}"#.utf8)))
        #expect(invite.megaphoneID == nil)
        #expect(PushPayload(content: .gomokuInvite(matchID: "m-1"), megaphoneID: "mg").megaphoneID == nil)
        #expect(Set(PushKind.allCases.map(\.rawValue)) == ["message", "gomoku_invite", "feedback_reply", "work_check"], "새 PushKind 를 만들었다")

        let object = try #require(try JSONSerialization.jsonObject(with: Self.megaphonePushJSON(megaphoneID: "mg")) as? [String: Any])
        #expect(PushAlert(userInfo: object) == PushAlert(title: "확성기님", body: "📢 다 같이 오목!"))
        #expect(PushAlert(userInfo: ["aps": ["alert": "본문만"]]) == PushAlert(title: nil, body: "본문만"))
        #expect(PushAlert(userInfo: ["type": "message"]) == nil)
        #expect(PushAlert(title: "  ", body: "\n").body == nil)
    }

    @Test("앱이 앞: 확성기 푸시는 시스템 배너를 숨기고 앱 배너(알림 제목·본문) + refresh · 기준선: 표식 없는 메시지 푸시는 시스템 배너")
    func foregroundPushBecomesBanner() async throws {
        let h = await MessagesHarness.make { server in
            server.override("megaphone_inbox") { _ in .json("[]") }
            server.override("message_unread_summary_v2") { _ in .json(MessagesStubServer.summary([])) }
        }
        defer { h.tearDown() }
        await Self.settleBanner(h)
        let banner = h.model.megaphoneBanner
        #expect(banner.current == nil)

        let plain = try #require(PushPayload(json: Self.megaphonePushJSON(megaphoneID: nil)))
        let alert = PushAlert(title: "확성기님", body: "📢 다 같이 오목!")
        #expect(h.model.push.presentation(for: plain, alert: alert) == .banner)
        #expect(banner.current == nil, "표식 없는 메시지 푸시가 앱 배너를 띄웠다(접두는 표식이 아니다)")
        await h.settle()

        let before = h.count("megaphone_inbox")
        let marked = try #require(PushPayload(json: Self.megaphonePushJSON(megaphoneID: "mg9")))
        #expect(h.model.push.presentation(for: marked, alert: alert) == .hidden)
        let shown = try #require(banner.current)
        #expect(shown.megaphoneID == "mg9")
        #expect(shown.body == "다 같이 오목!")
        #expect(shown.senderName == "확성기님")
        #expect(shown.senderID == Self.peerMega)
        #expect(await baseWaitUntil { h.count("megaphone_inbox") == before + 1 }, "앱 배너를 띄운 뒤 inbox 로 맞추지 않았다")
        await h.settle()
    }

    @Test("앱이 뒤: 확성기 푸시도 지금처럼 시스템 배너(앱 배너 없음)")
    func backgroundPushStaysSystem() async throws {
        let h = await MessagesHarness.make { server in
            server.override("megaphone_inbox") { _ in .json("[]") }
        }
        defer { h.tearDown() }
        await Self.settleBanner(h)
        h.model.sceneDidEnterBackground()
        let marked = try #require(PushPayload(json: Self.megaphonePushJSON(megaphoneID: "mg9")))
        #expect(h.model.push.presentation(for: marked, alert: PushAlert(title: "확성기님", body: "📢 다 같이 오목!")) == .banner)
        #expect(h.model.megaphoneBanner.current == nil)
    }

    @Test("눌러 들어옴: 확성기는 대화로 가지 않고 배너로 · 기준선: 표식 없는 메시지는 그 대화를 연다")
    func tappedPushOpensBannerNotThread() async throws {
        let h = await MessagesHarness.make { server in
            server.override("megaphone_inbox") { _ in .json("[]") }
            server.override("message_unread_summary_v2") { _ in .json(MessagesStubServer.summary([])) }
        }
        defer { h.tearDown() }
        await Self.settleBanner(h)
        let alert = PushAlert(title: "확성기님", body: "📢 다 같이 오목!")
        let tabBefore = h.model.router.selectedTab
        #expect(tabBefore != .messages)

        let marked = try #require(PushPayload(json: Self.megaphonePushJSON(megaphoneID: "mg7")))
        await h.model.push.handleResponse(marked, action: .open, alert: alert)
        #expect(h.model.megaphoneBanner.current?.megaphoneID == "mg7")
        #expect(h.model.router.selectedTab == tabBefore, "확성기 푸시가 메시지 탭으로 갔다")
        #expect(h.model.router.consumePendingRoute(for: .messages) == nil, "확성기 푸시가 대화를 열었다")
        await h.settle()

        let plain = try #require(PushPayload(json: Self.megaphonePushJSON(megaphoneID: nil)))
        await h.model.push.handleResponse(plain, action: .open, alert: alert)
        #expect(h.model.router.selectedTab == .messages)
        #expect(h.model.router.consumePendingRoute(for: .messages) == .message(peerID: Self.peerMega))
        await h.settle()
    }

    // MARK: 실시간

    @Test("실시간: 'megaphone' 신호 → 배너 refresh(메시지 조회는 안 깨운다) · 기준선: 'ring' 은 메시지 요약")
    func realtimeMegaphoneRefreshesBanner() async {
        let h = await MessagesHarness.make { server in
            server.override("megaphone_inbox") { _ in .json("[]") }
            server.override("message_unread_summary_v2") { _ in .json(MessagesStubServer.summary([])) }
        }
        defer { h.tearDown() }
        await Self.settleBanner(h)
        #expect(h.model.realtime.megaphoneBanner === h.model.megaphoneBanner, "러너에 배너 스토어가 안 붙었다")
        h.transport.emit(.joined)
        h.model.realtime.flushCoalescedSignals()
        await h.settle()
        let summaries = h.count("message_unread_summary_v2")
        let inbox = h.count("megaphone_inbox")

        h.transport.emit(.broadcast(event: "megaphone"))
        h.model.realtime.flushCoalescedSignals()
        #expect(await baseWaitUntil { h.count("megaphone_inbox") == inbox + 1 })
        await h.settle()
        #expect(h.count("message_unread_summary_v2") == summaries, "확성기 신호가 메시지 조회(drain)까지 깨웠다")

        h.transport.emit(.broadcast(event: "ring"))
        h.model.realtime.flushCoalescedSignals()
        #expect(await baseWaitUntil { h.count("message_unread_summary_v2") > summaries })
        await h.settle()
        #expect(h.count("megaphone_inbox") == inbox + 1, "'ring' 이 배너를 다시 읽었다")
    }

    // MARK: 전송 뒤 내 배너

    @Test("보낸 직후 내 화면에 배너 한 번(isOwn) · 기준선: 루비 부족 응답이면 안 뜬다")
    func ownBannerAfterSend() async {
        let status = BaseLockedBox<String>(#"{"status":"insufficient","need":50,"have":10}"#)
        let h = await MessagesHarness.make { server in
            server.override("megaphone_info") { _ in .json(MessagesMegaphoneTests.info(recipients: 9, ruby: 130)) }
            server.override("send_megaphone") { _ in .json(status.get()) }
            server.override("megaphone_inbox") { _ in .json("[]") }
        }
        defer { h.tearDown() }
        await Self.settleBanner(h)
        let mega = h.store.megaphone
        let banner = h.model.megaphoneBanner
        mega.open()
        _ = await baseWaitUntil { mega.info != nil }

        mega.setDraft("오늘 3시 라운지에서 간식 나눠요")
        mega.requestSend()
        #expect(mega.confirmSend())
        _ = await baseWaitUntil { !mega.isSending }
        await h.barrier()
        await baseYield()
        #expect(mega.noticeIsError)
        #expect(banner.current == nil, "보내지 못했는데 내 배너가 떴다")

        status.mutate { $0 = #"{"status":"ok","duplicate":false,"megaphone_id":"mg-own","recipients":9,"price":50,"ruby_balance":80}"# }
        mega.requestSend()
        #expect(mega.confirmSend())
        #expect(await baseWaitUntil { banner.current != nil }, "보낸 뒤 내 배너가 안 떴다")
        #expect(banner.current?.isOwn == true)
        #expect(banner.current?.body == "오늘 3시 라운지에서 간식 나눠요")
        #expect(banner.current?.megaphoneID == "mg-own", "서버가 준 확성기 id 가 아니라 임시 id 로 떴다")
        _ = await baseWaitUntil { !mega.infoLoading }
        await h.settle()
    }

    // MARK: 데모 픽스처 · 로그아웃

    @Test("데모 픽스처: inbox · v2 요약 · 히스토리의 확성기 줄(같은 id) · 정보의 대기 키가 실제로 읽힌다")
    func demoFixturesDecode() async {
        let demo = await MessagesDemoFixtureTests.make(route: "messages")
        defer { demo.tearDown() }
        let banner = demo.model.megaphoneBanner
        _ = await baseWaitUntil { banner.capability != .unknown }
        let megaRow = "d0000000-0000-4000-8000-00000000ee01"
        #expect(banner.capability == .available)
        #expect(banner.knownMessageIDs == [megaRow], "rpc.megaphone_inbox.json 이 안 읽혔다")
        #expect(banner.current?.megaphoneID == "d0000000-0000-4000-8000-0000000000e2", "데모 시계 기준 신선한 확성기가 안 떴다")
        demo.store.listDidAppear()
        await demo.settle()
        #expect(demo.store.history.contains { $0.id == megaRow }, "히스토리 픽스처에 확성기 줄이 없다")
        #expect(!demo.store.visibleHistory.contains { $0.id == megaRow })
        #expect(!demo.store.threads.contains { $0.peerUserID == "d0000000-0000-4000-8000-0000000000b8" })
        #expect(demo.store.badgeCount == 3)
        let names = demo.requests.compactMap(\.rpcName)
        #expect(names.contains("message_unread_summary_v2"))
        #expect(!names.contains("message_unread_summary"), "v2 픽스처가 있는데 옛 요약을 불렀다")

        let mega = demo.store.megaphone
        mega.open()
        _ = await baseWaitUntil { mega.info != nil }
        #expect(mega.info?.globalCooldownSeconds == 300, "rpc.megaphone_info.json 의 전역 키가 안 읽혔다")
        mega.close()
    }

    @Test("로그아웃: 배너 스토어의 판정·id·떠 있는 배너를 비운다 · 기준선: 로그아웃 전에는 채워져 있다")
    func signOutResetsBanner() async {
        let h = await MessagesHarness.make { server in
            server.override("megaphone_inbox") { _ in .json(Self.inbox([("m1", "mg1", Self.peerMega, "다 같이 오목!", 400)])) }
            server.override("message_unread_summary_v2") { _ in .json(MessagesStubServer.summary([])) }
        }
        defer { h.tearDown() }
        await Self.settleBanner(h)
        let banner = h.model.megaphoneBanner
        #expect(banner.capability == .available)
        #expect(!banner.knownMessageIDs.isEmpty)
        #expect(banner.current?.megaphoneID == "mg1")
        await h.model.session.signOut()
        #expect(banner.capability == .unknown)
        #expect(banner.knownMessageIDs.isEmpty)
        #expect(banner.current == nil)
        #expect(banner.queue.isEmpty)
    }

    // MARK: 소스 계약(iOS 전용 어댑터는 맥 스위트가 컴파일하지 않는다 — 주석을 걷고 잰다)

    @Test("소스 계약: 알림 어댑터가 알림 제목·본문을 표시 판정과 눌러 들어옴 둘 다로 넘긴다")
    func adapterPassesAlert() throws {
        let adapter = try IntegrationContractTests.code("Sources/CheckMobileKit/Push/PushNotificationCenterAdapter.swift")
        #expect(adapter.components(separatedBy: "PushAlert(title: content.title, body: content.body)").count - 1 == 2)
        #expect(adapter.contains("presentation(for: payload, alert: PushAlert(title: content.title, body: content.body))"))
        #expect(adapter.contains("model.push.handleResponse(payload, action: action, alert: alert)"))
        #expect(adapter.contains("model?.push.presentation(for: payload, alert: alert)"))
    }
}
