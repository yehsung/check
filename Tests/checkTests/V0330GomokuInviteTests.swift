import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.30 — 오목 신청의 근무 조건 삭제(스토어 쪽).
//
//  · `pendingIncomingInvites` 는 만료되지 않은 받은 신청이고, 만료 시각이 지나면 **타이머로** 빠진다(관찰 갱신은 시간 흐름만으로
//    일어나지 않는다 — 메뉴바 점이 켜진 채 남으면 안 된다).
//  · `refreshInboxIfStale()` 은 60초 스로틀이고 `setMenuPresented(true)` 가 부른다.
//  · 'gomoku' 신호는 근무 여부와 무관하게 받은 신청을 새로 받는다(비근무 맥도 소켓이 붙어 있다).

private typealias GFx = MessageReadFixture

private func v0330InboxReply(expiresInMs: Double, serverNowMs: Double, id: String = "11111111-2222-3333-4444-555555555555")
    -> MessageReadStubProtocol.Reply {
    MessageReadStubProtocol.Reply(body: GFx.json([
        "status": "ok",
        "server_now_ms": serverNowMs,
        "incoming": [[
            "match_id": id, "stake": 5, "invite_expires_ms": serverNowMs + expiresInMs,
            "challenger": ["user_id": GFx.peerA, "display_name": "도전자", "avatar_url": NSNull(), "character": "aing"]
        ]],
        "outgoing": NSNull()
    ]))
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 받은_신청은_만료_시각이_지나면_타이머로_목록에서_빠진다() async {
    // 실제 시계를 쓴다 — 만료 타이머는 Task.sleep 이고, 그 잠을 깨우는 것이 이 테스트가 재려는 바로 그것이다.
    let serverNow = Date().timeIntervalSince1970 * 1000
    let (store, _) = makeMessageReadStore("invite-expiry") { call, _ in
        call.rpc == "gomoku_inbox" ? v0330InboxReply(expiresInMs: 400, serverNowMs: serverNow) : nil
    }
    let gomoku = store.gomoku
    gomoku.clock = { Date() }

    await gomoku.loadInbox()
    #expect(gomoku.pendingIncomingInvites.map(\.id) == ["11111111-2222-3333-4444-555555555555"])
    #expect(gomoku.pendingIncomingInvites.first?.stake == 5)

    // 아무도 다시 조회하지 않는다 — 시간만 흐른다.
    await messageReadWait(10) { gomoku.pendingIncomingInvites.isEmpty }
    #expect(gomoku.pendingIncomingInvites.isEmpty, "만료된 신청이 목록에 남았다 — 메뉴바 점·배너가 켜진 채로 굳는다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 받은_신청은_만료가_이른_것부터다() {
    let gomoku = GomokuStore()
    let peer = GomokuUser(id: GFx.peerA, displayName: "A", avatarURL: nil, characterID: nil,
                          isWorking: false, isCapable: true, inMatch: false)
    gomoku.incoming = [
        GomokuInvite(id: "late", peer: peer, stake: 3, expiresAt: GFx.now.addingTimeInterval(50)),
        GomokuInvite(id: "early", peer: peer, stake: 3, expiresAt: GFx.now.addingTimeInterval(10))
    ]
    #expect(gomoku.pendingIncomingInvites.map(\.id) == ["early", "late"])
    #expect(gomoku.bannerInvite?.id == "early")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 받은함_새로고침은_60초_스로틀이고_세션이_없으면_안_낸다() async {
    final class Clock: @unchecked Sendable { var now = GFx.now }
    let clock = Clock()
    let (store, host) = makeMessageReadStore("inbox-throttle") { call, _ in
        call.rpc == "gomoku_inbox" ? MessageReadStubProtocol.Reply(body: #"{"status":"ok","incoming":[]}"#) : nil
    }
    let gomoku = store.gomoku
    gomoku.clock = { clock.now }
    func inbox() -> Int { MessageReadStubProtocol.count(host: host, rpc: "gomoku_inbox") }

    gomoku.refreshInboxIfStale()
    await messageReadWait { inbox() == 1 }
    clock.now = clock.now.addingTimeInterval(59)
    gomoku.refreshInboxIfStale()
    try? await Task.sleep(for: .milliseconds(120))
    #expect(inbox() == 1)
    clock.now = clock.now.addingTimeInterval(1)
    gomoku.refreshInboxIfStale()
    await messageReadWait { inbox() == 2 }
    #expect(inbox() == 2)

    let bare = GomokuStore()
    bare.refreshInboxIfStale()
    #expect(bare.syncTask == nil)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 비근무_맥도_오목_신호를_받으면_받은_신청을_새로_받는다() async {
    let serverNow = Date().timeIntervalSince1970 * 1000
    let transport = FakeRealtimeTransport()
    let (store, host) = makeMessageReadStore("gomoku-signal-idle", transport: transport) { call, _ in
        switch call.rpc {
        case "gomoku_inbox": return v0330InboxReply(expiresInMs: 60_000, serverNowMs: serverNow)
        case "message_unread_summary": return GFx.summaryReply([])
        default: return nil
        }
    }
    store.gomoku.clock = { Date() }
    #expect(store.startedAt == nil)
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "gomoku_inbox") >= 1 && messageReadIdle(store) }
    let before = MessageReadStubProtocol.count(host: host, rpc: "gomoku_inbox")

    transport.emit(.broadcast(event: "gomoku"))
    await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "gomoku_inbox") >= before + 1 }
    await messageReadWait { store.gomoku.syncTask == nil }
    #expect(MessageReadStubProtocol.count(host: host, rpc: "gomoku_inbox") == before + 1, "비근무 맥이 오목 신호를 무시했다")
    #expect(store.gomoku.pendingIncomingInvites.count == 1)
    #expect(MessageReadStubProtocol.count(host: host, rpc: "take_pokes") == 0)
}

@Test
func 팝오버_열기는_오목_받은함_신선도를_부르고_신청_경로에_근무_선게이트가_없다() throws {
    let store = gomokuCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source("WorkTimerStore.swift")))
    let menu = try #require(gomokuBody(of: "func setMenuPresented(", in: store))
    #expect(menu.contains("gomoku.refreshInboxIfStale()"))
    #expect(menu.contains("refreshMessageActivityOnMenuOpen()"))

    let gomoku = gomokuCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source("GomokuStore.swift")))
    for signature in ["private func challenge(userID: String, peerHint: GomokuUser?) async",
                      "func respond(inviteID: String, accept: Bool) async",
                      "func handleSignal()", "func requestSync()", "func refreshInboxIfStale()", "func realtimeDidJoin()",
                      "func systemDidWake()"] {
        let body = try #require(gomokuBody(of: signature, in: gomoku), "\(signature) 를 못 찾았다")
        #expect(!body.contains("startedAt"), "\(signature) 에 근무 선게이트가 있다")
        // `isWorking:` 라벨(모르는 상대의 기본값을 만드는 자리)은 판정이 아니다 — 읽는 자리(`.isWorking`)만 막는다.
        #expect(!body.contains(".isWorking"), "\(signature) 가 근무 여부를 본다")
        #expect(!body.contains("realtimeMayConsumePokes"), "\(signature) 가 소비 게이트를 본다")
    }
}
