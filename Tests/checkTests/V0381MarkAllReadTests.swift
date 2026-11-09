import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// 메시지 · 찌르기 [모두 읽음](2026-11-10 대표 결정, 제보 "메세지 전체읽기 만들어주세요"):
// "메시지 전체읽기 버튼 눌러서 읽음처리 해버릴 수 있게 해줘. 지금 찌르기 조차도 다 안읽은메시지로 쌓이다 보니까 안읽었다고 뜨는게 너무 많아.
//  버튼 한번으로 전체 읽음 처리 해버릴 수 있으면 좋을듯"
// 서버 함수는 새로 만들지 않는다 — 대화를 열 때 쓰는 `mark_conversation_read`(메시지 · 찌르기 경계 한 번에)를 안 읽은 대화마다 부른다.

private typealias Fx = MessageReadFixture
private let marEpoch = Int(MessageReadFixture.now.timeIntervalSince1970)

private func marMessageRow(id: String, peer: String, isMine: Bool, epoch: Int, unread: Bool?) -> [String: Any] {
    var row = Fx.readsRow(id: id, peer: peer, isMine: isMine, body: "안녕", epoch: epoch, readByPeer: nil, unread: unread, name: "상대")
    row["kind"] = "message"
    return row
}

private func marPokeRow(id: String, peer: String, isMine: Bool, epoch: Int, unread: Bool?, kind: String = "poke") -> [String: Any] {
    [
        "id": id, "from_user": isMine ? Fx.me : peer, "to_user": isMine ? peer : Fx.me, "body": NSNull(),
        "created_at": "2026-09-21T12:00:00.123456+00:00", "is_mine": isMine, "peer_user_id": peer,
        "peer_display_name": "상대", "peer_avatar_url": NSNull(), "created_epoch": epoch, "read_by_peer": NSNull(),
        "unread": unread.map { $0 as Any } ?? NSNull(), "kind": kind,
    ]
}

private func marConversationMarkReply() -> MessageReadStubProtocol.Reply {
    MessageReadStubProtocol.Reply(body: Fx.json(["status": "ok", "advanced": true, "unread": 0, "poke_advanced": true, "poke_unread": 0]))
}

/// A: 안 읽은 메시지 m1 · 안 읽은 울트라 p1(내가 보낸 p2 는 경계가 아니다) · B: 찌르기만 pb · C: 다 읽음.
private func marRows(read: Bool) -> [[String: Any]] {
    [
        marMessageRow(id: "m0", peer: Fx.peerA, isMine: false, epoch: marEpoch - 120, unread: !read),
        marMessageRow(id: "m1", peer: Fx.peerA, isMine: false, epoch: marEpoch - 60, unread: !read),
        marPokeRow(id: "p1", peer: Fx.peerA, isMine: false, epoch: marEpoch - 30, unread: !read, kind: "ultra"),
        marPokeRow(id: "p2", peer: Fx.peerA, isMine: true, epoch: marEpoch - 10, unread: nil),
        marPokeRow(id: "pb", peer: Fx.peerB, isMine: false, epoch: marEpoch - 5, unread: !read),
    ]
}

@MainActor
@Suite struct V0381MarkAllReadTests {
    @Test("[모두 읽음]: 이력을 새로 받고 안 읽은 대화마다 한 번씩 — A 는 메시지 m1 · 울트라 p1, B 는 찌르기 pb 만 · 점이 곧바로 꺼진다")
    func marksEveryUnreadConversation() async {
        let marked = MarFlag()
        let (store, host) = makeMessageReadStore("v381-all") { call, _ in
            switch call.rpc {
            case "message_history_with_pokes": return Fx.historyReply(marRows(read: marked.isSet))
            case "mark_conversation_read":
                marked.set()
                return marConversationMarkReply()
            case "message_unread_summary": return Fx.summaryReply([])
            default: return nil
            }
        }
        // 전제: 이력을 아직 안 받았다 — [모두 읽음] 이 먼저 받는다.
        #expect(store.unreadConversationPeerIDs.isEmpty && store.messageHistoryReadSnapshot == nil)
        store.markAllConversationsRead()
        store.markAllConversationsRead()                     // 두 번 눌러도 한 차례
        await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "mark_conversation_read") >= 2 && messageReadIdle(store)
            && !store.messageMarkAllReadInFlight }
        let calls = MessageReadStubProtocol.calls(host: host, rpc: "mark_conversation_read").map(\.json)
        #expect(calls.count == 2, "대화 둘에 한 번씩이 아니다: \(calls)")
        #expect(MessageReadStubProtocol.count(host: host, rpc: "mark_messages_read") == 0)
        let byPeer = Dictionary(calls.map { ($0["p_peer"] as? String ?? "", $0) }, uniquingKeysWith: { a, _ in a })
        #expect(byPeer[Fx.peerA]?["p_through_message"] as? String == "m1", "\(byPeer[Fx.peerA] ?? [:])")
        #expect(byPeer[Fx.peerA]?["p_through_poke"] as? String == "p1", "내가 보낸 p2 를 경계로 골랐다")
        #expect(byPeer[Fx.peerB]?["p_through_poke"] as? String == "pb")
        #expect(byPeer[Fx.peerB]?.keys.contains("p_through_message") == false, "찌르기만 있는 B 에 메시지 경계를 실었다")
        #expect(store.unreadConversationPeerIDs.isEmpty, "모두 읽음 뒤에도 점이 남았다: \(store.unreadConversationPeerIDs)")
        #expect(!store.hasUnreadMessages)
    }

    @Test("[모두 읽음] 직접 부르기(받아 둔 이력): 안 읽은 대화 수를 돌려주고 · 안 읽은 게 없으면 아무것도 안 보낸다(기준선)")
    func markFromLoadedCountsConversations() async {
        let (store, host) = makeMessageReadStore("v381-loaded") { call, _ in
            switch call.rpc {
            case "message_history_with_pokes": return Fx.historyReply(marRows(read: false))
            case "mark_conversation_read": return marConversationMarkReply()
            case "message_unread_summary": return Fx.summaryReply([])
            default: return nil
            }
        }
        #expect(store.markAllConversationsReadFromLoaded() == 0, "기준선: 이력이 없는데 무엇을 올렸다")
        await store.performLoadMessageHistory()
        #expect(store.unreadConversationPeerIDs == [Fx.peerA, Fx.peerB], "전제: 안 읽은 대화 둘(\(store.unreadConversationPeerIDs))")
        #expect(store.markAllConversationsReadFromLoaded() == 2)
        #expect(store.unreadConversationPeerIDs.isEmpty, "낙관 읽음이 점을 곧바로 끄지 않았다")
        await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "mark_conversation_read") >= 2 && messageReadIdle(store) }
        #expect(store.markAllConversationsReadFromLoaded() == 0, "이미 올린 대화를 또 올린다")
    }

    @Test("머리 줄: [모두 읽음] 은 안내 글자 자리를 빌리므로 더 좁다(caption2 bold 실측 + 캡슐 여백) · 안 읽은 게 있을 때만 · 배선")
    func titleRowButtonFitsAndIsWired() throws {
        let font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .bold)
        let text = ceil((PokeMarkAllReadButton.title as NSString).size(withAttributes: [.font: font]).width)
        print("[mark-all-read] '\(PokeMarkAllReadButton.title)' \(text)pt + 14")
        #expect(text + 14 <= PokeTitleRowWidthBudget.markAllReadWidth, "단추 실측 \(text + 14)pt 가 예산 \(PokeTitleRowWidthBudget.markAllReadWidth) 을 넘는다")
        #expect(PokeTitleRowWidthBudget.markAllReadWidth <= PokeTitleRowWidthBudget.longestHintWidth,
                "[모두 읽음] 이 안내 글자보다 넓다 — 머리 줄 폭 예산이 깨진다")

        let root = CheckCoreSourceLayout.repoRoot
        let menu = try String(contentsOf: root.appendingPathComponent("Sources/check/CheckMenuView.swift"), encoding: .utf8)
        #expect(menu.contains("onMarkAllRead: { store.markAllConversationsRead() },"), "패널에 [모두 읽음] 이 안 이어졌다")
        #expect(menu.contains("if !unreadMessagePeerIDs.isEmpty || !unreadPokePeerIDs.isEmpty {\n                    PokeMarkAllReadButton(action: onMarkAllRead)"),
                "[모두 읽음] 이 안 읽은 대화가 있을 때만 서지 않는다")
    }
}

private final class MarFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}
