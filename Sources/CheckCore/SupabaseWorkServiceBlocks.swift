import Foundation

// MARK: - 차단 · 신고 (앱스토어 심사 지침 1.2 — 사용자 생성 콘텐츠)
//
// 서버 계약(SPEC-block-report 작업 S): `block_user(p_user)` · `unblock_user(p_user)` · `list_blocks()` ·
// `report_content(p_target, p_reason, p_detail, p_message_id, p_block)`. 전부 security definer · authenticated 전용이다.
//
// ── 이 파일이 지키는 것 ──
// ① **응답 모양이 성공을 실패로 만들지 않는다.** 네 RPC 모두 HTTP 2xx 면 성공이고 본문은 읽지 않는다
//    (제보 `submitFeedback` 과 같은 근거 — 스칼라냐 객체냐 하는 한 겹 차이로 성공한 차단이 실패로 보이면
//    사용자는 같은 사람을 또 차단하고, 신고는 24시간 상한만 축낸다). 거절은 서버가 **예외**로 말한다.
// ② **함수가 없는 서버에서 접는 판단은 스토어 몫이다.** 앱이 db push 보다 먼저 나갈 수 있고, 그때 PostgREST 는
//    PGRST202 를 내며 공용 매핑이 `.databaseSchemaMissing` 으로 던진다 — 여기서 삼키지 않고 그대로 올린다
//    (메시지 읽음 RPC 와 같은 규약 · `MessagesStore.isMissingFunction`).
// ③ **신고 본문은 사람이 쓴 문장이다.** 이 파일 어디에도 `print`/`Logger` 를 붙이지 마라(메시지 파일 공통 규약).
// ④ 로그인 토큰은 **옵셔널이 아니다** — anon 으로 부르는 문을 타입 수준에서 닫는다(계정 삭제와 같은 규약).

extension SupabaseWorkService {
    /// 한 사람을 차단한다. 양방향으로 막는 것은 서버다(보내기 · 목록 · 사람 찾기 · 오목 신청).
    /// 자기 자신 차단은 서버가 예외로 거절한다 — 클라도 부르기 전에 한 번 막지만 최종 판정은 서버다.
    package func blockUser(accessToken: String, userID: String) async throws {
        try await sendNoBody(
            path: Self.blockUserPath,
            method: "POST",
            body: BlockUserRequest(pUser: userID),
            accessToken: accessToken,
            prefer: nil
        )
    }

    /// 차단을 푼다(차단 목록의 행에서만).
    package func unblockUser(accessToken: String, userID: String) async throws {
        try await sendNoBody(
            path: Self.unblockUserPath,
            method: "POST",
            body: BlockUserRequest(pUser: userID),
            accessToken: accessToken,
            prefer: nil
        )
    }

    /// 내가 차단한 사람들. 인자 없는 RPC 라 본문은 `{}` 다(PostgREST 는 본문의 키 집합으로 함수를 고른다).
    ///
    /// 행의 칸은 **전부 옵셔널**이다(SPEC §0.4 b) — 서버가 칸 이름을 하나 달리 부르는 날에도 배열 디코드가
    /// 통째로 throw 되어 목록이 사라지지 않게. id 를 못 읽은 행만 버린다(차단 해제를 걸 곳이 없는 행이다).
    package func fetchBlocks(accessToken: String) async throws -> [BlockedUser] {
        let data = try await send(
            path: Self.listBlocksPath,
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([BlockedUserRow].self, from: data)
        // 클로저 인자 이름이 `row` 가 **아닌** 이유는 제보 목록·이력과 같다(소스 계약 테스트가 그 문장을 센다).
        return rows.compactMap { blockRow -> BlockedUser? in
            guard let id = blockRow.userID, !id.isEmpty else { return nil }
            return BlockedUser(
                userID: id,
                // 별명이 없으면(탈퇴·익명화) 이력·제보 목록과 같은 폴백을 쓴다.
                name: blockRow.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "사용자",
                avatarURL: blockRow.avatarUrl.flatMap { URL(string: $0) },
                // epoch 가 정본이고 ISO 문자열은 폴백이다(이력과 같은 근거 — 소수초 파싱 함정). 둘 다 없으면 시각을 말하지 않는다.
                blockedAt: blockRow.createdEpoch.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    ?? blockRow.createdAt.flatMap { parseDate($0) }
            )
        }
    }

    /// 신고 한 건(+ `alsoBlock` 이면 같은 트랜잭션에서 차단까지). 대상은 사람이고, `messageID` 가 있으면 그 사람이 보낸 메시지 한 건이다.
    ///
    /// **다섯 키를 늘 싣는다**(값이 없으면 `null`). 합성 인코더는 nil 인 옵셔널의 키를 아예 빼는데
    /// (`MessageReadMarkRequest` 주석), PostgREST 는 **본문의 키 집합으로 함수를 고르므로** 키가 빠지면
    /// 같은 이름의 다른 서명을 찾다가 PGRST202 로 떨어질 수 있다. 서버 기본값이 있는 인자라도 명시해 보내는 편이
    /// 한 가지 실패를 통째로 없앤다.
    package func reportContent(
        accessToken: String,
        targetUserID: String,
        reason: ContentReportReason,
        detail: String?,
        messageID: String?,
        alsoBlock: Bool
    ) async throws {
        try await sendNoBody(
            path: Self.reportContentPath,
            method: "POST",
            body: ContentReportRequest(
                pTarget: targetUserID,
                pReason: reason.rawValue,
                // 빈 자유 입력은 빈 문자열이 아니라 null 이다(서버 CHECK 는 길이만 본다 — 빈 글이 '적었다'로 남으면 운영자가 헷갈린다).
                pDetail: detail.flatMap { $0.isEmpty ? nil : $0 },
                pMessageID: messageID.flatMap { $0.isEmpty ? nil : $0 },
                pBlock: alsoBlock
            ),
            accessToken: accessToken,
            prefer: nil
        )
    }

    package nonisolated static let blockUserPath = "/rest/v1/rpc/block_user"
    package nonisolated static let unblockUserPath = "/rest/v1/rpc/unblock_user"
    package nonisolated static let listBlocksPath = "/rest/v1/rpc/list_blocks"
    package nonisolated static let reportContentPath = "/rest/v1/rpc/report_content"
}

// MARK: - 전선 모양

/// `block_user(p_user)` · `unblock_user(p_user)` 요청.
package struct BlockUserRequest: Encodable, Equatable, Sendable {
    package let pUser: String

    package init(pUser: String) {
        self.pUser = pUser
    }
}

/// `report_content(...)` 요청. **키를 빼지 않으려고** 인코딩을 손으로 적는다(위 `reportContent` 주석).
package struct ContentReportRequest: Encodable, Equatable, Sendable {
    package let pTarget: String
    package let pReason: String
    package let pDetail: String?
    package let pMessageID: String?
    package let pBlock: Bool

    package init(pTarget: String, pReason: String, pDetail: String?, pMessageID: String?, pBlock: Bool) {
        self.pTarget = pTarget
        self.pReason = pReason
        self.pDetail = pDetail
        self.pMessageID = pMessageID
        self.pBlock = pBlock
    }

    /// 키를 **이미 스네이크로** 적는다. 인코더는 `keyEncodingStrategy = .convertToSnakeCase` 지만 그 변환은
    /// 대문자를 찾아 끊는 것이라 대문자가 없는 이 문자열들은 그대로 지난다 — 카멜(`pMessageID`)로 두면
    /// 변환이 `p_message_i_d` 를 만들어 PostgREST 가 함수를 못 찾는다.
    package enum CodingKeys: String, CodingKey {
        case pTarget = "p_target"
        case pReason = "p_reason"
        case pDetail = "p_detail"
        case pMessageID = "p_message_id"
        case pBlock = "p_block"
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pTarget, forKey: .pTarget)
        try container.encode(pReason, forKey: .pReason)
        // `encode` 다(encodeIfPresent 가 아니다) — nil 이면 키를 빼는 게 아니라 null 을 싣는다.
        try container.encode(pDetail, forKey: .pDetail)
        try container.encode(pMessageID, forKey: .pMessageID)
        try container.encode(pBlock, forKey: .pBlock)
    }
}

/// `list_blocks()` 응답 행. 전부 옵셔널(위 `fetchBlocks` 주석).
///
/// 키는 `.convertFromSnakeCase` 가 이미 카멜로 바꾼 뒤에 매칭되므로 **카멜로 적는다**(`PokeDirectoryRow` 와 같은 함정).
/// `blocked`/`blockedAt` 을 함께 받는 이유: 표의 칸 이름(`blocked`)을 그대로 내보내는 서버와 목록용 이름
/// (`user_id`)을 쓰는 서버 어느 쪽이어도 목록이 서게 하려는 것이다 — 둘 중 먼저 읽힌 값을 쓴다.
package struct BlockedUserRow: Decodable, Equatable, Sendable {
    package let userID: String?
    package let displayName: String?
    package let avatarUrl: String?
    package let createdAt: String?
    package let createdEpoch: Int?

    package enum CodingKeys: String, CodingKey {
        case userId, blocked, id
        case displayName, avatarUrl
        case createdAt, blockedAt, createdEpoch, blockedEpoch
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decodeIfPresent(String.self, forKey: .userId)
            ?? container.decodeIfPresent(String.self, forKey: .blocked)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
            ?? container.decodeIfPresent(String.self, forKey: .blockedAt)
        createdEpoch = try container.decodeIfPresent(Int.self, forKey: .createdEpoch)
            ?? container.decodeIfPresent(Int.self, forKey: .blockedEpoch)
    }

    package init(userID: String?, displayName: String?, avatarUrl: String?, createdAt: String?, createdEpoch: Int?) {
        self.userID = userID
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.createdAt = createdAt
        self.createdEpoch = createdEpoch
    }
}

/// 차단 목록 한 줄(화면용).
package struct BlockedUser: Identifiable, Equatable, Sendable {
    package let userID: String
    package let name: String
    package let avatarURL: URL?
    /// 차단한 시각. 모르면 nil — **지어내지 않는다**(모르면 화면이 시각을 말하지 않는다).
    package let blockedAt: Date?

    package var id: String { userID }

    package init(userID: String, name: String, avatarURL: URL?, blockedAt: Date?) {
        self.userID = userID
        self.name = name
        self.avatarURL = avatarURL
        self.blockedAt = blockedAt
    }
}

/// 신고 사유 넷. **rawValue 가 곧 서버 CHECK 제약의 값**이다 — 여기를 고치면 서버 마이그레이션도 같이 고쳐야 한다.
///
/// 닫힌 집합이라 확장 협상 대상이 아니다(제보 `FeedbackKind` 와 같은 성격). 모르는 값이 서버에서 올 일도 없다 —
/// 이 표를 읽는 것은 보내는 쪽뿐이다.
package enum ContentReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam
    case harassment
    case inappropriate
    case other

    package var id: String { rawValue }

    /// 시트의 행 글자(SPEC 의 사유 4개 그대로).
    package var label: String {
        switch self {
        case .spam: return "스팸"
        case .harassment: return "욕설·괴롭힘"
        case .inappropriate: return "부적절한 내용"
        case .other: return "기타"
        }
    }
}

/// 신고 자유 입력(200자)의 정규화·길이 판정. **`MessageBody` 의 정규화·눈금을 그대로 빌린다** — 상한만 따로 본다
/// (대국 채팅 `GomokuChatBody` 와 같은 구조). 새 trim·새 세는 법을 만들지 않는 것이 요점이다: 서버 CHECK 도
/// `char_length` 로 보므로 두 벌이 갈리면 화면은 "200/200"인데 서버만 거절한다.
package enum ContentReportDetail {
    /// 상한. 단위는 **유니코드 스칼라**(코드포인트)이고 서버 `char_length` 와 같은 눈금이다.
    package static let maxLength = 200

    package static func sanitized(_ raw: String) -> String { MessageBody.sanitized(raw) }

    package static func length(_ raw: String) -> Int { MessageBody.length(raw) }

    /// 자유 입력은 **선택**이다 — 비어 있어도 신고는 나간다. 넘치면 보내지 않는다.
    package static func isWithinLimit(_ raw: String) -> Bool { length(raw) <= maxLength }

    /// 실제로 보낼 값(비었으면 nil — 전선에는 null 이 실린다).
    package static func payload(_ raw: String) -> String? {
        let normalized = sanitized(raw)
        return MessageBody.hasVisibleContent(normalized) ? normalized : nil
    }
}
