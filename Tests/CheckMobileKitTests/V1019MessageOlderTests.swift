@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.19 — 이전 대화 더 보기(메시지 30일 보관 · `message_page` · 맥 0.3.86 의 폰 짝 · 대표 #d_xygj8oZRFlfH 4번).
@MainActor
@Suite("폰 1.0.19 — 이전 대화 더 보기", .serialized)
struct V1019MessageOlderTests {
    nonisolated static let peer = "peer-a"

    /// `message_page` 줄(최신이 먼저 — 서버 계약).
    nonisolated static func pageRow(_ id: String, mine: Bool, epochSeconds: Int) -> String {
        let from = mine ? MessagesHarness.me : peer
        let to = mine ? peer : MessagesHarness.me
        return #"{"id":"\#(id)","from_user":"\#(from)","to_user":"\#(to)","body":"옛 말 \#(id)","is_megaphone":false,"is_mine":\#(mine),"created_epoch_ms":\#(epochSeconds * 1000),"created_epoch_us":\#(Int64(epochSeconds) * 1_000_000),"read_by_peer":true,"unread_for_me":true}"#
    }

    @Test("누르면 첫 쪽(커서 없이 · 50) · 옛 줄이 머리 앞에 붙고 · 받은 옛 말은 안 읽음이 아니다 · 30일 문장 · 끝이면 '더 없어요' · 대화를 닫으면 비운다")
    func loadsOlderPage() async throws {
        let base = MessagesHarness.base
        let h = await MessagesHarness.make { server in
            server.setRows([.received("head-1", from: Self.peer, at: 10)])
            server.override("message_page") { _ in
                .json("[" + [Self.pageRow("old-2", mine: true, epochSeconds: base - 90_000),
                             Self.pageRow("old-1", mine: false, epochSeconds: base - 100_000)].joined(separator: ",") + "]")
            }
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        await h.settle()
        let token = UUID()
        h.store.conversationDidAppear(peerID: Self.peer, token: token)
        await h.settle()
        #expect(h.count("message_page") == 0, "대화를 열기만 했는데 지난 쪽을 불렀다")
        #expect(h.store.olderRowState(for: Self.peer) == .button)
        #expect(h.store.expiryNotice == MessageNoticeText.expiry, "성공 전에는 24시간 문장")
        let unreadBefore = h.store.badgeCount

        await h.store.performLoadOlderMessages(peerID: Self.peer)
        await h.settle()
        let body = try #require(h.bodies("message_page").first)
        #expect(body.contains("\"p_peer\":\"\(Self.peer)\"") && body.contains("\"p_before_us\":null") && body.contains("\"p_limit\":50"), "\(body)")
        let ids = h.store.conversationMessages(for: Self.peer).map(\.id)
        #expect(ids == ["old-1", "old-2", "head-1"], "\(ids)")
        #expect(h.store.badgeCount == unreadBefore, "지난 쪽의 받은 말이 안 읽음으로 셌다")
        #expect(h.store.expiryNotice == MessageNoticeText.storeExpiry)
        #expect(h.store.olderRowState(for: Self.peer) == .end, "상한(50)보다 적게 왔으면 끝이다")
        #expect(h.store.conversationItems(for: Self.peer).contains { $0.id == "old-1" })

        h.store.conversationDidDisappear(token: token)
        #expect(h.store.olderPages.isEmpty && h.store.olderHasMore.isEmpty, "대화를 닫았는데 지난 쪽이 남았다")
        h.expectNoForbiddenCalls()
    }

    @Test("함수 없는 서버(404 PGRST202): 줄을 숨기고([다시 시도]가 아니다) · 대화를 다시 열면 요청 없이 다시 선다")
    func missingFunctionHidesRow() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("head-1", from: Self.peer, at: 10)])
            server.override("message_page") { _ in
                .json(#"{"code":"PGRST202","message":"Could not find the function public.message_page(p_peer, p_before_us, p_before_id, p_limit) in the schema cache"}"#, status: 404)
            }
        }
        defer { h.tearDown() }
        let token = UUID()
        h.store.conversationDidAppear(peerID: Self.peer, token: token)
        await h.settle()
        await h.store.performLoadOlderMessages(peerID: Self.peer)
        await h.settle()
        #expect(h.store.olderAvailable == false && h.store.olderRowState(for: Self.peer) == nil && !h.store.olderFailed)
        h.store.conversationDidDisappear(token: token)
        let calls = h.count("message_page")
        h.store.conversationDidAppear(peerID: Self.peer, token: UUID())
        #expect(h.store.olderRowState(for: Self.peer) == .button && h.count("message_page") == calls)
    }

    @Test("배선: 대화 화면이 맨 위 줄 · 30일 문장 · 붙인 뒤 제자리 맞추기를 스토어 값으로만 그린다 — 주석을 걷고 본다")
    func wiring() throws {
        let view = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesConversationView.swift").filter { !$0.isWhitespace }
        #expect(view.contains("MessagesExpiryNote(alignment:.center,font:.caption,text:store.expiryNotice)"))
        #expect(view.contains("iflet older=store.olderRowState(for:peerID){MessagesOlderRow(state:older){store.loadOlderMessages(peerID:peerID)}".filter { !$0.isWhitespace }))
        #expect(view.contains(".onChange(of:store.olderScrollAnchor)"))
        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesStore.swift").filter { !$0.isWhitespace }
        #expect(store.contains("messages:conversationMessages(for:peerID)"), "대화 줄이 지난 쪽을 안 잇는다")
        #expect(store.contains("carryOlderMessagesAcrossHeadSlide(previousHead:threads.flatMap(\\.messages),nextHead:sorted)"))
    }
}
