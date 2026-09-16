import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.30 — 새 RPC 셋의 **전선 모양**(요청 본문 · 응답 옮김). SPEC-wave1 §1.1 의 JSON 을 글자 그대로 쓴다.
//
// with_reads 행 옮김은 옛 `fetchMessageHistory` 의 규칙을 **두 벌로** 들고 있다(그 함수는 이 작업이 고칠 수 없는 파일에 있다).
// 두 벌이 갈리는 날을 여기서 잡는다: 같은 행을 두 경로에 흘려 읽음 칸을 뺀 결과가 같은지 본다.

@MainActor
private func serviceFor(_ label: String, handler: @escaping MessageReadStubProtocol.Handler) -> (SupabaseWorkService, String) {
    let host = "v0330-svc-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    MessageReadStubProtocol.register(host: host, handler: handler)
    return (SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: MessageReadStubProtocol.session()
    ), host)
}

private func stripReads(_ entry: MessageHistoryEntry) -> MessageHistoryEntry {
    var copy = entry
    copy.readByPeer = nil
    copy.isUnread = nil
    return copy
}

@MainActor
@Test
func with_reads_행_옮김은_옛_이력_옮김과_읽음_칸_말고는_같다() async throws {
    // 옛 이력이 버리는 행(본문 공백·상대 없음·시각 없음)과 폴백(이름 없음·ISO 시각)을 한 응답에 섞는다.
    let rows: [[String: Any]] = [
        ["id": "k1", "from_user": "u1", "to_user": "me", "body": "  안녕  ", "created_at": "2026-09-21T12:00:00.5Z",
         "is_mine": false, "peer_user_id": "u1", "peer_display_name": "", "peer_avatar_url": "https://example.com/a.png",
         "created_epoch": 1_790_000_000, "read_by_peer": NSNull(), "unread": true],
        ["id": "k2", "from_user": "me", "to_user": "u1", "body": "보냄", "created_at": "2026-09-21T12:00:01.25Z",
         "is_mine": true, "peer_user_id": "u1", "peer_display_name": "영식", "peer_avatar_url": NSNull(),
         "created_epoch": NSNull(), "read_by_peer": true, "unread": NSNull()],
        ["id": "drop-blank", "body": "   ", "is_mine": false, "peer_user_id": "u1", "created_epoch": 1_790_000_000],
        ["id": "drop-peer", "body": "x", "is_mine": false, "created_epoch": 1_790_000_000],
        ["id": "drop-time", "body": "x", "is_mine": false, "peer_user_id": "u1"]
    ]
    let body = MessageReadFixture.json(rows)
    let (service, host) = serviceFor("parity") { call, _ in
        switch call.rpc {
        case "message_history_with_reads", "message_history": return MessageReadStubProtocol.Reply(body: body)
        default: return nil
        }
    }
    let withReads = try await service.fetchMessageHistoryWithReads(accessToken: "t", hours: 24, limit: 200)
    let legacy = try await service.fetchMessageHistory(accessToken: "t", hours: 24, limit: 200)

    #expect(withReads.map(\.id) == ["k1", "k2"])
    #expect(withReads.map(stripReads) == legacy, "with_reads 옮김이 옛 이력 옮김과 갈렸다(두 벌 규칙의 드리프트)")
    #expect(withReads[0].isUnread == true && withReads[0].readByPeer == nil)
    #expect(withReads[1].readByPeer == true && withReads[1].isUnread == nil)
    // 요청 본문은 옛 이력과 같은 키·같은 접기다.
    let sent = MessageReadStubProtocol.calls(host: host, rpc: "message_history_with_reads").first?.json
    #expect(sent?["p_hours"] as? Int == 24)
    #expect(sent?["p_limit"] as? Int == 200)
    #expect(Set(sent?.keys.map { $0 } ?? []) == ["p_hours", "p_limit"])
}

@MainActor
@Test
func with_reads_는_키가_빠진_행에도_배열_디코드가_죽지_않는다() async throws {
    let (service, _) = serviceFor("optional") { call, _ in
        call.rpc == "message_history_with_reads"
            ? MessageReadStubProtocol.Reply(body: #"[{"id":"x","body":"a","peer_user_id":"u1","created_epoch":1}, {"body":"no id"}]"#)
            : nil
    }
    let entries = try await service.fetchMessageHistoryWithReads(accessToken: "t", hours: 24, limit: 200)
    #expect(entries.map(\.id) == ["x"])
    #expect(entries.first?.isMine == false, "is_mine 이 없으면 받은 것으로 본다(왼쪽 정렬이 안전한 쪽)")
    #expect(entries.first?.isUnread == nil)
}

@MainActor
@Test
func 읽음_처리_요청은_p_peer_와_p_through_를_싣고_응답을_옮긴다() async throws {
    let (service, host) = serviceFor("mark") { call, _ in
        call.rpc == "mark_messages_read"
            ? MessageReadStubProtocol.Reply(body: #"{"status":"ok","advanced":true,"unread":2}"#) : nil
    }
    let response = try await service.markMessagesRead(accessToken: "t", peerUserID: "u1", throughMessageID: "m9")
    #expect(response == MessageReadMarkResponse(status: "ok", advanced: true, unread: 2))
    #expect(response.isOK)
    let sent = try #require(MessageReadStubProtocol.calls(host: host, rpc: "mark_messages_read").first?.json)
    #expect(sent["p_peer"] as? String == "u1")
    #expect(sent["p_through"] as? String == "m9")
    #expect(Set(sent.keys) == ["p_peer", "p_through"])

    // 경계를 비우면 키 자체가 없다(서버 기본값 null 과 같은 뜻 — PostgREST 는 두 키 집합을 같은 함수로 고른다).
    _ = try await service.markMessagesRead(accessToken: "t", peerUserID: "u1", throughMessageID: nil)
    let second = try #require(MessageReadStubProtocol.calls(host: host, rpc: "mark_messages_read").last?.json)
    #expect(Set(second.keys) == ["p_peer"])

    // invalid·unauthorized 는 ok 가 아니다.
    let (service2, _) = serviceFor("mark-invalid") { _, _ in MessageReadStubProtocol.Reply(body: #"{"status":"invalid"}"#) }
    #expect(try await service2.markMessagesRead(accessToken: "t", peerUserID: "me", throughMessageID: nil).isOK == false)
}

@MainActor
@Test
func 요약_요청은_빈_본문이고_없는_서버는_스키마_부재로_던진다() async throws {
    let (service, host) = serviceFor("summary") { call, index in
        guard call.rpc == "message_unread_summary" else { return nil }
        return index == 0
            ? MessageReadFixture.summaryReply([("u1", 2)])
            : MessageReadFixture.missingFunction("message_unread_summary")
    }
    let response = try await service.fetchMessageUnreadSummary(accessToken: "t")
    #expect(response.summary?.unreadPeerIDs == ["u1"])
    #expect(MessageReadStubProtocol.calls(host: host, rpc: "message_unread_summary").first?.body == "{}")

    do {
        _ = try await service.fetchMessageUnreadSummary(accessToken: "t")
        Issue.record("없는 함수인데 던지지 않았다")
    } catch let error as SupabaseWorkServiceError {
        #expect(error == .databaseSchemaMissing)
        #expect(WorkTimerStore.isMissingMessageReadFunction(error))
    }
}
