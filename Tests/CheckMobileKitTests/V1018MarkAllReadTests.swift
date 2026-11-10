import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.18 — 메시지 탭 [모두 읽음](대표 결정 2026-11-10 "메시지 전체읽기 버튼 눌러서 읽음처리 해버릴 수 있게 해줘…찌르기조차도…").
// 맥 0.3.81 과 같은 뜻 · 서버 변경 없음: 안 읽은 대화(메시지 ∪ 찌르기)마다 대화를 열 때와 같은 경계로 mark_conversation_read.
@MainActor
@Suite(.serialized) struct V1018MarkAllReadTests {
    typealias Poke = MessagesPokeLogStoreTests.Poke
    static let peerA = MessagesPokeLogStoreTests.peerA
    static let peerB = MessagesPokeLogStoreTests.peerB

    @Test("안 읽은 메시지 A · 안 본 찌르기만 B → 두 사람 각각 한 번 · 경계는 마지막 받은 것 · 두 번 눌러도 두 번 · 다 꺼진다")
    func marksEveryUnreadConversation() async {
        let h = await MessagesHarness.make { server in
            MessagesPokeLogStoreTests.serveConversationRead(server)
            MessagesPokeLogStoreTests.servePokes(
                server,
                messages: [.received("a1", from: Self.peerA, at: 0, unread: true)],
                pokes: [Poke(id: "pb", peer: Self.peerB, epoch: MessagesHarness.base + 5, mine: false, unread: true)]
            )
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        await h.settle()
        #expect(h.store.sortUnreadPeerIDs == [Self.peerA, Self.peerB], "전제: 두 사람이 안 읽음이다")
        h.store.markAllConversationsRead()
        h.store.markAllConversationsRead()
        await h.settle()
        #expect(h.count("mark_conversation_read") == 2, "사람마다 한 번이 아니다: \(h.count("mark_conversation_read"))")
        let bodies = h.bodies("mark_conversation_read").joined(separator: " | ")
        #expect(bodies.contains(#""p_through_message":"a1""#) && bodies.contains(#""p_through_poke":"pb""#), Comment(rawValue: bodies))
        #expect(h.store.sortUnreadPeerIDs.isEmpty, "올린 뒤에도 안 읽음이 남았다: \(h.store.sortUnreadPeerIDs)")
        h.expectNoForbiddenCalls()
    }

    @Test("안 읽은 것이 없으면 요청 0건 · 단추 배선(안 읽음이 있을 때만) — 주석을 걷고 본다")
    func noUnreadNoRequest() async throws {
        let h = await MessagesHarness.make { server in
            MessagesPokeLogStoreTests.serveConversationRead(server)
            MessagesPokeLogStoreTests.servePokes(server, messages: [.received("a1", from: Self.peerA, at: 0, unread: false)], pokes: [])
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        await h.settle()
        h.store.markAllConversationsRead()
        await h.settle()
        #expect(h.count("mark_conversation_read") == 0)
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesTab.swift").filter { !$0.isWhitespace }
        #expect(tab.contains("if!store.sortUnreadPeerIDs.isEmpty{") && tab.contains("store.markAllConversationsRead()"))
    }
}
