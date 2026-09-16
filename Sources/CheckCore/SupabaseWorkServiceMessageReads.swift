import Foundation

// MARK: - 메시지 읽음 (v0.3.30) — 서버 계약 SPEC-wave1 §1.1
//
// 새 RPC 셋(`message_history_with_reads` · `message_unread_summary` · `mark_messages_read`)의 전선 모양과 옮김이 여기 산다.
// 기존 `message_history` 호출(SupabaseWorkService.fetchMessageHistory)은 **그대로 둔다** — 새 함수가 없는 서버(앱이 db push
// 보다 먼저 나간 창·옛 서버)에서 스토어가 그쪽으로 접는다(WorkTimerStoreMessages.performLoadMessageHistory).
//
// ── 이 파일이 지키는 것 ──
// ① **응답 디코드 필드는 전부 옵셔널이다**(SPEC §0.4 b). 키 하나가 빠진 서버에서 배열 디코드가 통째로 throw 되면
//    이력이 조용히 사라진다(MessageHistoryRow 가 이미 적어 둔 사고).
// ② **읽음 판정은 서버가 한다.** `read_by_peer`/`unread` 는 서버 timestamptz(마이크로초)로 비교한 결과다 — 클라가
//    `created_epoch`(초 단위)로 다시 비교하면 같은 초 안의 메시지들이 서로 뒤바뀐다. 그래서 이 파일에는 시각 비교가 없다.
// ③ **본문은 사람이 쓴 문장이다.** 이 파일에 `print`/`Logger` 를 붙이지 마라(메시지 파일 공통 규약).

extension SupabaseWorkService {
    /// 읽음 칸이 붙은 이력. `message_history(p_hours, p_limit)` 와 같은 요청 본문을 싣는다(같은 서명 규약).
    ///
    /// 함수가 없는 서버에서는 PostgREST 가 PGRST202 를 내고, 공용 매핑이 `.databaseSchemaMissing` 으로 던진다 —
    /// 여기서 접지 않고 그대로 던지는 이유는 **폴백 판단이 스토어의 몫**이기 때문이다(옛 이력으로 다시 부를지,
    /// 읽음 기능을 "모름"으로 둘지를 한 자리에서 정해야 두 판단이 갈리지 않는다).
    ///
    /// 반환 순서는 **서버 순서 그대로**다(created_at asc, id asc — 마이크로초까지). 스토어가 이 순서를 받아 적어 둔다:
    /// 같은 초 안의 선후를 아는 것은 이 순서뿐이고, "마지막으로 받은 메시지"를 고르는 판정이 그것을 쓴다.
    package func fetchMessageHistoryWithReads(
        accessToken: String,
        hours: Int,
        limit: Int
    ) async throws -> [MessageHistoryEntry] {
        let data = try await send(
            path: Self.messageHistoryWithReadsPath,
            method: "POST",
            // 인자 범위는 옛 이력과 같은 눈금으로 접는다(서버도 message_history 에 위임해 같은 값으로 접는다).
            body: MessageHistoryRequest(
                pHours: min(24, max(1, hours)),
                pLimit: min(500, max(1, limit))
            ),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([MessageHistoryReadsRow].self, from: data)
        return rows.compactMap { readsRow in messageHistoryEntry(fromReadsRow: readsRow) }
    }

    /// 안 읽은 메시지 요약. 인자 없는 RPC 라 본문은 `{}` 다(PostgREST 는 본문의 키 집합으로 함수를 고른다).
    package func fetchMessageUnreadSummary(accessToken: String) async throws -> MessageUnreadSummaryResponse {
        let data = try await send(
            path: Self.messageUnreadSummaryPath,
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(MessageUnreadSummaryResponse.self, from: data)
    }

    /// 읽음 경계를 올린다. `p_through` 는 **내가 화면에서 본 마지막 받은 메시지 id** 다 — 비우면 서버가 그 대화의
    /// 최신까지 올리는데, 그러면 이력을 받은 뒤 도착해 아직 화면에 안 그려진 말까지 "읽음"이 된다.
    package func markMessagesRead(
        accessToken: String,
        peerUserID: String,
        throughMessageID: String?
    ) async throws -> MessageReadMarkResponse {
        let data = try await send(
            path: Self.markMessagesReadPath,
            method: "POST",
            body: MessageReadMarkRequest(pPeer: peerUserID, pThrough: throughMessageID),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(MessageReadMarkResponse.self, from: data)
    }

    package nonisolated static let messageHistoryWithReadsPath = "/rest/v1/rpc/message_history_with_reads"
    package nonisolated static let messageUnreadSummaryPath = "/rest/v1/rpc/message_unread_summary"
    package nonisolated static let markMessagesReadPath = "/rest/v1/rpc/mark_messages_read"

    /// with_reads 행 → 표시용 한 건.
    ///
    /// ★ 옮김 규칙은 `fetchMessageHistory` 의 클로저와 **같다**(본문 정규화 · 상대 없음 버림 · epoch 우선 · 이름 폴백 ·
    ///   is_mine 서버 판정). 그 함수는 이 작업이 고칠 수 없는 파일에 있어 공용 함수로 뽑지 못했다 — 두 벌이 갈리는 날을
    ///   V0330MessageReadServiceTests 가 같은 행을 두 경로에 흘려 결과를 비교해 잡는다.
    /// 읽음 칸은 **그 칸이 뜻을 갖는 쪽에만** 싣는다: read_by_peer 는 내가 보낸 것, unread 는 받은 것. 서버가 반대쪽에
    /// 값을 실어 보내도 여기서 버린다 — 화면이 받은 말풍선 옆에 1을 그리는 경로를 타입 수준에서 닫는다.
    package func messageHistoryEntry(fromReadsRow readsRow: MessageHistoryReadsRow) -> MessageHistoryEntry? {
        guard let id = readsRow.id, !id.isEmpty else { return nil }
        let body = MessageBody.sanitized(readsRow.body ?? "")
        guard MessageBody.hasVisibleContent(body) else { return nil }
        guard let peer = readsRow.peerUserId, !peer.isEmpty else { return nil }
        guard let createdAt = readsRow.createdEpoch.map({ Date(timeIntervalSince1970: TimeInterval($0)) })
            ?? readsRow.createdAt.flatMap({ parseDate($0) })
        else { return nil }
        let isMine = readsRow.isMine ?? false
        return MessageHistoryEntry(
            id: id,
            peerUserID: peer,
            peerName: readsRow.peerDisplayName.flatMap { $0.isEmpty ? nil : $0 } ?? "사용자",
            peerAvatarURL: readsRow.peerAvatarUrl.flatMap { URL(string: $0) },
            body: body,
            createdAt: createdAt,
            isMine: isMine,
            readByPeer: isMine ? readsRow.readByPeer : nil,
            isUnread: isMine ? nil : readsRow.unread
        )
    }
}

// MARK: - 전선 모양

/// `message_history_with_reads` 응답 행. `message_history` 의 열 전부 + 끝의 두 칸.
package struct MessageHistoryReadsRow: Decodable, Equatable, Sendable {
    package let id: String?
    package let fromUser: String?
    package let toUser: String?
    package let body: String?
    package let createdAt: String?
    package let isMine: Bool?
    package let peerUserId: String?
    package let peerDisplayName: String?
    package let peerAvatarUrl: String?
    package let createdEpoch: Int?
    /// 내가 보낸 행에만 값(상대가 읽었는가). 받은 행은 null.
    package let readByPeer: Bool?
    /// 받은 행에만 값(내가 아직 안 읽었는가). 보낸 행은 null.
    package let unread: Bool?
}

/// `mark_messages_read(p_peer, p_through)` 요청. p_through 가 nil 이면 **키 자체를 싣지 않는다**(합성 인코더의
/// encodeIfPresent) — 서버 기본값 null 과 같은 뜻이고, PostgREST 는 두 키 집합 모두 같은 함수로 고른다.
package struct MessageReadMarkRequest: Encodable, Equatable, Sendable {
    package let pPeer: String
    package let pThrough: String?
}

/// `mark_messages_read` 응답. `{"status":"ok","advanced":bool,"unread":int}` · unauthorized · invalid.
package struct MessageReadMarkResponse: Decodable, Equatable, Sendable {
    package let status: String?
    package let advanced: Bool?
    package let unread: Int?

    package var isOK: Bool { status == "ok" }
}

/// `message_unread_summary()` 응답.
package struct MessageUnreadSummaryResponse: Decodable, Equatable, Sendable {
    package struct Peer: Decodable, Equatable, Sendable {
        package let peerUserId: String?
        package let count: Int?
        /// 정수로 오지만 JSON 숫자면 무엇이든 받는다(서버가 bigint 를 소수로 직렬화하는 날에도 디코드가 죽지 않게).
        package let lastEpochMs: Double?
    }

    package let status: String?
    package let total: Int?
    package let peers: [Peer]?

    /// 화면이 쓸 요약. `ok` 가 아니면(미로그인 등) nil = **스냅샷이 없다**(빈 요약이 아니다 — "안 읽은 것 0"이라고
    /// 말하면 거짓이 될 수 있다).
    package var summary: MessageUnreadSummary? {
        guard status == "ok" else { return nil }
        let rows: [MessageUnreadPeer] = (peers ?? []).compactMap { peer in
            guard let id = peer.peerUserId, !id.isEmpty, let count = peer.count, count > 0 else { return nil }
            return MessageUnreadPeer(
                peerUserID: id,
                count: count,
                lastMessageAt: peer.lastEpochMs.map { Date(timeIntervalSince1970: $0 / 1000) }
            )
        }
        return MessageUnreadSummary(total: max(0, total ?? rows.reduce(0) { $0 + $1.count }), peers: rows)
    }
}

/// 안 읽은 메시지 요약(서버 판정). 순서는 서버가 준 그대로(last_epoch_ms 내림차순)다.
package struct MessageUnreadSummary: Equatable, Sendable {
    package let total: Int
    package let peers: [MessageUnreadPeer]

    package var unreadPeerIDs: Set<String> { Set(peers.map(\.peerUserID)) }
}

package struct MessageUnreadPeer: Equatable, Sendable {
    package let peerUserID: String
    package let count: Int
    /// 그 상대에게서 받은 안 읽은 메시지 중 가장 최근 것의 시각. **표시용이다** — 읽음 판정에 쓰지 않는다(머리 주석 ②).
    package let lastMessageAt: Date?
}
