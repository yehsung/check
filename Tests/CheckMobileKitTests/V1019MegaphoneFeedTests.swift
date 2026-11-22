@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.19 — 지난 확성기(맥 0.3.86 과 같은 코어 스토어 `MegaphoneFeedStore` · 대표 #d_xygj8oZRFlfH 4번 메시지 묶음).
@MainActor
@Suite("폰 1.0.19 — 지난 확성기", .serialized)
struct V1019MegaphoneFeedTests {
    private static func item(_ id: String, sender: String?, own: Bool = false, recipients: Int? = 46) -> MegaphoneFeedItem {
        MegaphoneFeedItem(megaphoneID: id, senderID: sender, senderName: "보낸이", body: "📢 아닌 본문",
                          recipients: recipients, createdAt: Date(timeIntervalSince1970: 1_800_000_000), isOwn: own)
    }

    @Test("줄 규칙: 남의 글만 신고 · 차단(내 글 · 서버가 is_mine 을 틀려도 내 id · 보낸 사람 모름은 없음) · 시각 · 받은 사람 수")
    func rules() {
        #expect(MessagesMegaphoneFeedRules.actionTarget(for: Self.item("m1", sender: "peer-a"), me: "me")?.peerID == "peer-a")
        #expect(MessagesMegaphoneFeedRules.actionTarget(for: Self.item("m2", sender: "me", own: true), me: "me") == nil)
        #expect(MessagesMegaphoneFeedRules.actionTarget(for: Self.item("m3", sender: "ME"), me: "me") == nil, "서버가 is_mine 을 틀려도 내 글이다")
        #expect(MessagesMegaphoneFeedRules.actionTarget(for: Self.item("m4", sender: nil), me: "me") == nil)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let time = MegaphoneFeedText.timeLabel(now, now: now)
        #expect(MessagesMegaphoneFeedRules.metaText(Self.item("m5", sender: "a"), now: now) == "\(time) · 46명에게")
        #expect(MessagesMegaphoneFeedRules.metaText(Self.item("m6", sender: "a", recipients: nil), now: now) == time)
    }

    @Test("스토어: 열면 첫 쪽(p_before_us null · p_limit 30) · 받은 줄 · 문 열림 · 로그아웃(reset)이 목록과 문을 비운다")
    func storeOpensFirstPage() async {
        let h = await MessagesHarness.make { server in
            server.override("megaphone_feed") { _ in
                .json(#"[{"megaphone_id":"11111111-1111-1111-1111-111111111111","sender_id":"peer-a","sender_display_name":"가나","body":"안녕하세요","recipients":46,"is_mine":false,"created_epoch_ms":1800000000000,"created_epoch_us":1800000000000000}]"#)
            }
        }
        defer { h.tearDown() }
        #expect(h.store.showsMegaphoneFeedEntry, "모르면 문이 선다(누르면 그때 묻는다)")
        await h.store.megaphoneFeed.open()?.value
        await h.settle()
        let bodies = h.bodies("megaphone_feed")
        #expect(bodies.count == 1)
        #expect(bodies.first?.contains("\"p_before_us\":null") == true && bodies.first?.contains("\"p_limit\":30") == true, "\(bodies)")
        #expect(h.store.visibleMegaphoneFeed.map(\.senderName) == ["가나"])
        #expect(h.store.megaphoneFeed.isAvailable == true && h.store.megaphoneFeed.hasLoaded)
        h.store.megaphoneFeed.close()
        h.store.reset()
        #expect(h.store.megaphoneFeed.items.isEmpty && h.store.megaphoneFeed.isAvailable == nil)
        h.expectNoForbiddenCalls()
    }

    @Test("문 닫힘: 서버에 함수가 없으면(404) 작성 시트의 문이 숨고 · 작성기를 다시 열면(rearm) 요청 없이 다시 선다")
    func doorClosedThenRearmed() async {
        let h = await MessagesHarness.make { server in
            server.override("megaphone_feed") { _ in .json(#"{"code":"PGRST202","message":"Could not find the function public.megaphone_feed(p_before_us, p_limit) in the schema cache"}"#, status: 404) }
        }
        defer { h.tearDown() }
        await h.store.megaphoneFeed.open()?.value
        await h.settle()
        #expect(h.store.megaphoneFeed.isAvailable == false && !h.store.showsMegaphoneFeedEntry)
        h.store.megaphoneFeed.close()
        let before = h.count("megaphone_feed")
        h.store.megaphoneFeed.rearm()
        #expect(h.store.showsMegaphoneFeedEntry && h.count("megaphone_feed") == before, "rearm 은 요청 없이 문만 다시 세운다")
    }

    @Test("배선: 작성 시트의 문 · 페이지가 서면 open · 떠나면 close · 작성기 열기에 rearm · 실시간 신호는 열린 페이지만 · 앱이 러너에 잇는다 — 주석을 걷고 본다")
    func wiring() throws {
        let sheet = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesMegaphoneSheet.swift").filter { !$0.isWhitespace }
        #expect(sheet.contains("ifstore.showsMegaphoneFeedEntry{NavigationLink{MessagesMegaphoneFeedView(store:store)}"))
        #expect(sheet.contains(".onAppear{store.megaphoneFeed.rearm()}"))
        let page = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesMegaphoneFeedView.swift").filter { !$0.isWhitespace }
        #expect(page.contains(".onAppear{feed.open()}") && page.contains(".onDisappear{feed.close()}"))
        #expect(page.contains("letitems=store.visibleMegaphoneFeed"), "차단한 사람 글을 거르지 않은 목록을 그린다")
        let runner = try IntegrationContractTests.code("Sources/CheckMobileKit/Realtime/MobileRealtimeRunner.swift").filter { !$0.isWhitespace }
        #expect(runner.contains("ifletfeed=megaphoneFeed,feed.isOpen{feed.refresh()}"))
        let app = try IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileAppModel.swift").filter { !$0.isWhitespace }
        #expect(app.contains("realtime.megaphoneFeed=messages.megaphoneFeed"))
    }
}
