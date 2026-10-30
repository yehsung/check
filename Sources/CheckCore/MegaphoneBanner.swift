import Foundation

// MARK: - 확성기 배너 — 메시지 한 줄 대신 화면 위에 크게 (2026-10-30 사용자 결정 · 계약 docs/plan/megaphone-banner-contract.md C1)
//
// 서버는 지금처럼 받는 사람마다 `messages` 한 줄(`megaphone_id` 채움, 본문 앞 `📢 `)을 넣는다 — 옛 앱은 그대로 메시지로 받는다.
// 새 앱은 `megaphone_inbox(p_hours)` 가 돌려준 줄만 배너로 띄우고, 그 `message_id` 들만 메시지함에서 뺀다.
//
// ★ `📢 ` 접두는 표식이 아니다 — `send_message` 는 접두를 막지 않는다(아무나 `📢 안녕` 을 1:1 로 보낼 수 있다).
//   표식은 서버의 `messages.megaphone_id` 하나뿐이고, 클라가 그것을 아는 길은 `megaphone_inbox` 하나뿐이다.
//   그래서 이 파일의 어떤 판정도 본문 접두만 보고 숨기거나 띄우지 않는다(접두는 "확인해 볼 이유"일 뿐 — 스토어의 needsVerification).

/// 화면에 뜨는 확성기 한 건(도메인). 맥 배너 패널 · 폰 위 배너가 같은 값을 그린다.
package struct MegaphoneBanner: Equatable, Sendable, Identifiable {
    /// 내 메시지함의 그 줄(`messages.id`). 푸시로만 알고 아직 `megaphone_inbox` 로 맞추기 전이거나 내가 보낸 배너면 nil.
    package var messageID: String?
    /// 확성기 한 번(`megaphones.id`) — 배너의 정체(같은 확성기는 한 번만 뜬다). 내가 보낸 배너를 응답 id 없이 띄우면 `local-` 로 시작하는 자리값.
    package var megaphoneID: String
    /// 보낸 사람(답장 상대). 푸시로만 알고 아직 못 맞췄으면 nil.
    package var senderID: String?
    package var senderName: String
    package var senderAvatarURL: URL?
    /// 접두(`📢 `)를 뗀 본문.
    package var body: String
    package var createdAt: Date
    /// 내가 보낸 직후 띄우는 "이렇게 떴어요" 배너인가(답장 버튼이 없다).
    package var isOwn: Bool

    package var id: String { megaphoneID }

    /// [답장] 을 보일 수 있는가 — 상대를 알고, 내가 보낸 것이 아닐 때.
    package var canReply: Bool { !isOwn && !(senderID ?? "").isEmpty }

    package init(messageID: String?, megaphoneID: String, senderID: String?, senderName: String, senderAvatarURL: URL?,
                 body: String, createdAt: Date, isOwn: Bool = false) {
        self.messageID = messageID
        self.megaphoneID = megaphoneID
        self.senderID = senderID
        self.senderName = senderName
        self.senderAvatarURL = senderAvatarURL
        self.body = body
        self.createdAt = createdAt
        self.isOwn = isOwn
    }

    /// 사람 이름이 비었을 때(서버 coalesce 와 같은 말).
    package static let fallbackSenderName = "사용자"

    /// 화면에 그릴 본문: 정규화 후 앞의 `📢` 표식(뒤 공백 포함)을 한 번 뗀다. 보이는 글자가 없으면 nil.
    /// 푸시 알림 본문·내가 쓴 글·inbox 본문(서버가 이미 뗐다) 어느 것을 넣어도 같은 모양이 나온다.
    package static func displayBody(_ raw: String) -> String? {
        var text = MessageBody.sanitized(raw)
        if hasMegaphonePrefix(text) {
            text = String(text.drop(while: { $0.isWhitespace }).dropFirst(MegaphoneText.icon.count))
            text = MessageBody.sanitized(text)
        }
        return MessageBody.hasVisibleContent(text) ? text : nil
    }

    /// 본문이 `📢` 로 시작하는가(앞 공백은 건너뛴다). **표식이 아니다** — 확인해 볼 이유일 뿐(파일 머리 ★).
    package static func hasMegaphonePrefix(_ body: String) -> Bool {
        body.drop(while: { $0.isWhitespace }).hasPrefix(MegaphoneText.icon)
    }

    /// 같은 확성기의 더 나은 정보(inbox 가 푸시 자리값을 맞출 때)를 얹는다. 새 쪽에 값이 있으면 새 쪽이 이긴다.
    /// 내가 보낸 배너인가(`isOwn`)는 처음 값을 지킨다.
    package func merged(with newer: MegaphoneBanner) -> MegaphoneBanner {
        MegaphoneBanner(
            messageID: newer.messageID ?? messageID,
            megaphoneID: megaphoneID,
            senderID: newer.senderID ?? senderID,
            senderName: newer.senderName.isEmpty ? senderName : newer.senderName,
            senderAvatarURL: newer.senderAvatarURL ?? senderAvatarURL,
            body: newer.body.isEmpty ? body : newer.body,
            createdAt: newer.createdAt,
            isOwn: isOwn
        )
    }
}

/// 배너 표시 규칙의 숫자(계약 C2). 화면·스토어·시험이 이 값 하나를 본다.
package enum MegaphoneBannerRules {
    /// 신선도 — `createdAt` 이 이보다 오래된 것은 띄우지 않는다(켜 둔 사이 놓친 것은 보여 주되 묵은 것은 안 띄운다).
    package static let freshness: TimeInterval = 600
    /// 푸시를 눌러 들어온 항목은 이 안이면 신선도를 무시한다(24시간 — 서버 inbox 창과 같다).
    package static let pushWindow: TimeInterval = 24 * 3_600
    /// 한 장이 떠 있는 시간.
    package static let displaySeconds: TimeInterval = 8
    /// 닫힌 뒤 다음 장까지 쉬는 시간.
    package static let gap: TimeInterval = 0.4
    /// 멈췄다(호버·누르고 있기) 풀리면 남은 시간과 이것 중 긴 쪽으로 다시 센다.
    package static let resumeMinimum: TimeInterval = 3
    /// 본 것 기록 — 계정별 최근 이만큼의 `megaphoneID`.
    package static let seenLimit = 100
    /// `megaphone_inbox(p_hours)` 에 넘기는 창(서버가 1~24 로 자른다).
    package static let inboxHours = 24

    /// 본 것 기록의 기본값 저장소 키(계정별 — 다음 계정에 새지 않는다).
    package static func seenKey(userID: String) -> String { "megaphoneBanner.seen.\(userID)" }

    /// 지금 띄워도 되는가. 푸시로 들어온 것(`fromPush`)은 24시간, 나머지는 10분. 미래 시각(시계 어긋남)은 신선하다.
    package static func isPresentable(createdAt: Date, now: Date, fromPush: Bool) -> Bool {
        now.timeIntervalSince(createdAt) <= (fromPush ? pushWindow : freshness)
    }
}

// MARK: - 전선

/// `megaphone_inbox` 응답 한 줄. 필수는 두 id 뿐이고 나머지는 옵셔널(메시지 파일 공통 규약 — 키 하나 빠진 서버에서 통째로 죽지 않게).
/// 보낸 사람 키는 `sender_id` 가 정본이고, 서버가 `from_user` 로 내려도 받는다.
package struct MegaphoneInboxItem: Decodable, Equatable, Sendable {
    package let messageId: String
    package let megaphoneId: String
    package var senderId: String?
    package var senderDisplayName: String?
    package var senderAvatarUrl: String?
    package var body: String?
    package var createdAt: String?
    /// 초(정본). 밀리초로 와도 받는다(1e11 이 넘으면 밀리초로 본다 — 초로는 서기 5138년이다).
    package var createdEpoch: Double?

    package init(messageId: String, megaphoneId: String, senderId: String? = nil, senderDisplayName: String? = nil,
                 senderAvatarUrl: String? = nil, body: String? = nil, createdAt: String? = nil, createdEpoch: Double? = nil) {
        self.messageId = messageId
        self.megaphoneId = megaphoneId
        self.senderId = senderId
        self.senderDisplayName = senderDisplayName
        self.senderAvatarUrl = senderAvatarUrl
        self.body = body
        self.createdAt = createdAt
        self.createdEpoch = createdEpoch
    }

    private enum CodingKeys: String, CodingKey {
        case messageId, megaphoneId, senderId, fromUser, senderDisplayName, senderAvatarUrl, body, createdAt, createdEpoch
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messageId = try c.decode(String.self, forKey: .messageId)
        megaphoneId = try c.decode(String.self, forKey: .megaphoneId)
        senderId = try c.decodeIfPresent(String.self, forKey: .senderId)
            ?? c.decodeIfPresent(String.self, forKey: .fromUser)
        senderDisplayName = try c.decodeIfPresent(String.self, forKey: .senderDisplayName)
        senderAvatarUrl = try c.decodeIfPresent(String.self, forKey: .senderAvatarUrl)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        createdEpoch = try c.decodeIfPresent(Double.self, forKey: .createdEpoch)
    }

    /// 도메인으로. id 가 비었거나 · 보이는 본문이 없거나 · 시각을 모르면 nil(지어내지 않는다).
    package func banner(parsingDate parse: (String) -> Date?) -> MegaphoneBanner? {
        guard !messageId.isEmpty, !megaphoneId.isEmpty, let text = MegaphoneBanner.displayBody(body ?? "") else { return nil }
        let epochDate = createdEpoch.map { Date(timeIntervalSince1970: $0 > 1e11 ? $0 / 1000 : $0) }
        guard let created = epochDate ?? createdAt.flatMap(parse) else { return nil }
        let name = (senderDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return MegaphoneBanner(
            messageID: messageId,
            megaphoneID: megaphoneId,
            senderID: senderId.flatMap { $0.isEmpty ? nil : $0 },
            senderName: name.isEmpty ? MegaphoneBanner.fallbackSenderName : name,
            senderAvatarURL: senderAvatarUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) },
            body: text,
            createdAt: created
        )
    }
}

/// 줄 하나가 깨져도(필수 id 없음) 나머지는 살린다.
private struct MegaphoneInboxLossyItem: Decodable {
    let item: MegaphoneInboxItem?
    init(from decoder: Decoder) throws { item = try? MegaphoneInboxItem(from: decoder) }
}

/// `megaphone_inbox(p_hours)` 요청. 키를 언제나 싣는다(PostgREST 는 키 집합으로 함수를 고른다).
package struct MegaphoneInboxRequest: Encodable, Equatable, Sendable {
    package let pHours: Int
    package init(pHours: Int) { self.pHours = pHours }
}

extension SupabaseWorkService {
    package nonisolated static let megaphoneInboxPath = "/rest/v1/rpc/megaphone_inbox"

    /// 내게 온 확성기(최근 `hours` 시간 · 최신 20개 · 차단 상대 제외 — 서버가 거른다)를 배너 도메인으로.
    /// 함수가 없는 서버(PGRST202 · 404)는 던진다 — 스토어가 "필터 끔"으로 접는다.
    package func fetchMegaphoneInbox(accessToken: String, hours: Int = MegaphoneBannerRules.inboxHours) async throws -> [MegaphoneBanner] {
        let data = try await send(
            path: Self.megaphoneInboxPath,
            method: "POST",
            body: MegaphoneInboxRequest(pHours: hours),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([MegaphoneInboxLossyItem].self, from: data)
        return rows.compactMap { row in row.item?.banner(parsingDate: { parseDate($0) }) }
    }

    /// 안 읽음 요약을 **이름으로 고른 함수**에서 받는다(`message_unread_summary` · `message_unread_summary_v2`).
    /// 어느 것을 부를지는 `MegaphoneBannerStore.unreadSummaryFunction` 이 정한다. 둘 다 인자 없는 RPC 라 본문은 `{}` 다.
    package func fetchMessageUnreadSummary(accessToken: String, function: String) async throws -> MessageUnreadSummaryResponse {
        let data = try await send(
            path: "/rest/v1/rpc/\(function)",
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(MessageUnreadSummaryResponse.self, from: data)
    }
}
