import Foundation
import Observation

// MARK: - 지난 확성기(📢) — 최근 30일 모아 보기 (2026-11-11 대표 결정 "확성기 지난글 모아보기도 괜찮은듯")
//
// 서버 함수(서버 안정화 팀 최종 목록 §4 · 초안 20261114101000 §9). 전선의 이름·모양은 **이 파일 한 곳**에만 둔다:
//   · `POST /rest/v1/rpc/megaphone_feed` 본문 **정확히** `{"p_before_us": <정수 µs>|null, "p_limit": 30}` — 키 둘을 **언제나** 싣는다
//     (첫 쪽은 `p_before_us: null` · PostgREST 는 키 집합으로 함수를 고른다 — 키가 빠지면 PGRST202).
//   · 응답: 줄 **배열**(봉투 없음 · 문 없음 — 로그인만). 최신이 먼저, 30일 안, `p_limit` 은 1~100. 받은 줄이 `p_limit` 보다 적으면 끝이다.
//   · 줄: megaphone_id · sender_id · sender_display_name(null 없음 — 서버가 '사용자'로 채운다) · sender_avatar_url? ·
//     body(**머리말 '📢 ' 를 서버가 이미 뗐다** — 다시 떼지 않는다) · recipients · is_mine · created_epoch_ms · created_epoch_us.
//   · 다음 쪽 커서: 받은 **마지막(가장 오래된) 줄의 `created_epoch_us`** 를 그대로 `p_before_us` 로. 정수(Int64)로만 든다 — 실수로 바꾸지 않는다.
//   · 차단한 사이 · 숨김 계정 · 운영자가 내린 글은 서버가 뺀다. 줄에는 **메시지 id 가 없다**(신고는 사람 신고로만 — 맥 배선 파일).
//   · 운영자 내리기: `POST /rest/v1/rpc/megaphone_admin_hide` `{"p_id": uuid, "p_hidden": true}` → `{"status":"ok"|"forbidden"|"not_found","hidden":bool}`.
//
// ── 이 파일이 지키는 것 ──
// ① **배너가 아니다.** 줄은 `MegaphoneFeedItem` 이라는 **다른 타입**이다 — 배너 스토어(`MegaphoneBannerStore.offer` · 본 것 기록 100개)에
//    들어갈 길이 타입으로 막힌다. 지난 글이 배너로 다시 뜨거나 본 것 기록을 밀어내는 일이 원리적으로 없다.
// ② **문은 세 갈래**(`isAvailable`): nil 모름 · false 닫힘(함수 없음 404/PGRST202 — 앱이 서버보다 먼저 나간 창) · true 열림(성공 응답).
//    화면은 닫힘(false)일 때만 문('지난 확성기 ›')을 숨긴다. 닫힘은 **영구히 기억하지 않는다** — 다음 자연스러운 진입에서 `rearm()` 으로 다시 모름이 된다.
// ③ **자동 호출이 없다.** 팝오버 열기 · 폴링 틱 · 앱 시작 · 작성기 열기에서는 부르지 않는다. 부르는 곳은 사람이 누른 자리뿐이다:
//    페이지 열기 · [이전 확성기 더 보기] · [다시 시도] · 페이지가 떠 있는 동안의 실시간 'megaphone' 신호 · 운영자 [내리기].
// ④ **세대 가드.** 로그아웃·계정 전환(`reset`) 뒤 도착한 응답은 다음 계정의 목록을 건드리지 않는다. 더 보기 응답은 그 사이 목록 꼬리가
//    바뀌었으면(새로고침이 목록을 갈았다) 버린다 — 엉뚱한 자리에 이어 붙이지 않는다.
// ⑤ 본문은 사람이 쓴 문장이다 — 로그로 흘리지 않는다.

// MARK: 숫자 · 문구(맥·폰 한 벌)

/// 모아 보기의 숫자. 화면 문구의 "30일" 은 이 값을 읽는다(글자로 박지 않는다).
package enum MegaphoneFeedRules {
    /// 서버가 남기는 기간(일 — 서버 `message_store_days()`).
    package static let windowDays = 30
    /// 한 번에 받는 줄 수(`p_limit` — 계약 값).
    package static let pageSize = 30
    /// 접힌 본문의 줄 수(넘치면 그 줄에 [더 보기]).
    package static let collapsedLineLimit = 3
}

package enum MegaphoneFeedText {
    package static let title = "지난 확성기"
    /// 작성기 설명 줄 끝의 문(누르면 페이지로 간다).
    package static var entryLink: String { "\(title) ›" }
    package static var windowNote: String { "최근 \(MegaphoneFeedRules.windowDays)일" }
    package static var empty: String { "최근 \(MegaphoneFeedRules.windowDays)일 동안 울린 확성기가 없어요" }
    package static let loading = "불러오는 중이에요"
    package static let failed = "지난 확성기를 불러오지 못했어요"
    package static let unavailable = "지금은 지난 확성기를 볼 수 없어요"
    package static let loadMore = "이전 확성기 더 보기"
    package static let loadMoreFailed = "더 불러오지 못했어요. 다시 눌러 주세요"
    package static let ownBadge = "내가 보낸"
    package static let expand = "더 보기"
    package static let collapse = "접기"
    /// 운영자 전용 [내리기]와 그 결과 한 줄.
    package static let adminHideAction = "내리기"
    package static let adminHidden = "확성기를 내렸어요"
    package static let adminForbidden = "운영자만 내릴 수 있어요"
    package static let adminHideFailed = "내리지 못했어요. 다시 해 주세요"

    /// 받은 사람 수(작은 글씨 — "46명에게").
    package static func recipients(_ count: Int) -> String { "\(count)명에게" }

    /// 줄의 시각("오늘 14:05" · "어제 09:12" · "11월 3일 18:40"). 메시지 날짜 구분선과 같은 말을 쓴다.
    package static func timeLabel(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        "\(MessageThreadBuilder.dayLabel(date, now: now, calendar: calendar)) \(MessageThreadBuilder.clockText(date, calendar: calendar))"
    }
}

// MARK: 도메인

/// 지난 확성기 한 건(화면이 그리는 값). **`MegaphoneBanner` 와 다른 타입이다**(머리말 ①).
package struct MegaphoneFeedItem: Equatable, Sendable, Identifiable {
    /// 확성기 한 번(`megaphones.id`) — 줄의 정체(중복 지우기 · 운영자 내리기의 `p_id`).
    package var megaphoneID: String
    package var senderID: String?
    package var senderName: String
    package var senderAvatarURL: URL?
    /// 서버가 머리말을 뗀 본문(정규화만 한다 — 다시 떼지 않는다).
    package var body: String
    /// 받은 사람 수(모르면 nil).
    package var recipients: Int?
    package var createdAt: Date
    /// 서버 정수 마이크로초 — 다음 쪽 커서(`p_before_us`). **Int64 그대로** 든다(Double 로 바꾸면 µs 가 뭉개진다).
    package var createdEpochUs: Int64
    /// 내가 보낸 글인가(서버 `is_mine` · 없으면 보낸 사람 id 와 내 id 비교).
    package var isOwn: Bool

    package var id: String { megaphoneID }

    package init(megaphoneID: String, senderID: String?, senderName: String, senderAvatarURL: URL? = nil,
                 body: String, recipients: Int? = nil, createdAt: Date, createdEpochUs: Int64? = nil, isOwn: Bool = false) {
        self.megaphoneID = megaphoneID
        self.senderID = senderID
        self.senderName = senderName
        self.senderAvatarURL = senderAvatarURL
        self.body = body
        self.recipients = recipients
        self.createdAt = createdAt
        self.createdEpochUs = createdEpochUs ?? Int64((createdAt.timeIntervalSince1970 * 1_000_000).rounded())
        self.isOwn = isOwn
    }
}

// MARK: 전선

/// `megaphone_feed(p_before_us, p_limit)` 요청. **키 둘을 언제나 싣는다** — nil 은 키를 빼는 게 아니라 JSON null 이다
/// (`ContentReportRequest` 와 같은 손 인코딩 — 합성 Encodable 은 nil 키를 빼고, 그러면 PostgREST 가 함수를 못 찾는다).
package struct MegaphoneFeedRequest: Encodable, Equatable, Sendable {
    package let pBeforeUs: Int64?
    package let pLimit: Int

    package init(pBeforeUs: Int64?, pLimit: Int = MegaphoneFeedRules.pageSize) {
        self.pBeforeUs = pBeforeUs
        self.pLimit = pLimit
    }

    /// 키를 **이미 스네이크로** 적는다(인코더의 `.convertToSnakeCase` 는 대문자가 없는 문자열을 그대로 지난다).
    package enum CodingKeys: String, CodingKey {
        case pBeforeUs = "p_before_us"
        case pLimit = "p_limit"
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // `encode` 다(encodeIfPresent 가 아니다) — 첫 쪽의 nil 은 null 로 실린다.
        try container.encode(pBeforeUs, forKey: .pBeforeUs)
        try container.encode(pLimit, forKey: .pLimit)
    }
}

/// 응답 한 줄. 전 필드 옵셔널 — 키 하나 빠진 줄은 그 줄만 버린다(지어내지 않는다).
///
/// ★ 프로퍼티 이름은 **카멜이고 원시값이 없다.** 서비스 디코더가 `.convertFromSnakeCase` 라 `sender_id` 는 `senderId` 로 바뀐 뒤 맞춰진다 —
///   여기에 `"sender_id"` 같은 원시값을 달면 그 키는 언제나 nil 이 된다(계약서의 디코더 함정).
package struct MegaphoneFeedRow: Decodable, Equatable, Sendable {
    package var megaphoneId: String?
    package var senderId: String?
    package var senderDisplayName: String?
    package var senderAvatarUrl: String?
    package var body: String?
    package var recipients: Int?
    package var isMine: Bool?
    package var createdEpochMs: Int64?
    package var createdEpochUs: Int64?

    package init(megaphoneId: String? = nil, senderId: String? = nil, senderDisplayName: String? = nil,
                 senderAvatarUrl: String? = nil, body: String? = nil, recipients: Int? = nil, isMine: Bool? = nil,
                 createdEpochMs: Int64? = nil, createdEpochUs: Int64? = nil) {
        self.megaphoneId = megaphoneId
        self.senderId = senderId
        self.senderDisplayName = senderDisplayName
        self.senderAvatarUrl = senderAvatarUrl
        self.body = body
        self.recipients = recipients
        self.isMine = isMine
        self.createdEpochMs = createdEpochMs
        self.createdEpochUs = createdEpochUs
    }

    /// 도메인으로. id · 커서(µs)가 없거나 보이는 본문이 없으면 nil(지어내지 않는다).
    /// `me` 는 지금 계정의 id — 서버가 `is_mine` 을 안 실었을 때 내 글을 가르는 데만 쓴다.
    package func item(me: String?) -> MegaphoneFeedItem? {
        guard let megaphoneID = Self.nonEmpty(megaphoneId), let cursor = createdEpochUs, cursor > 0 else { return nil }
        // 본문은 정규화만 한다 — 머리말은 서버가 이미 뗐다(계약 §2). 다시 떼면 사람이 쓴 '📢' 로 시작하는 글이 잘린다.
        let text = MessageBody.sanitized(body ?? "")
        guard MessageBody.hasVisibleContent(text) else { return nil }
        let millis = createdEpochMs ?? cursor / 1000
        let sender = Self.nonEmpty(senderId)
        let name = (senderDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let own = isMine ?? {
            guard let sender, let me = Self.nonEmpty(me) else { return false }
            return sender.lowercased() == me.lowercased()
        }()
        return MegaphoneFeedItem(
            megaphoneID: megaphoneID,
            senderID: sender,
            senderName: name.isEmpty ? MegaphoneBanner.fallbackSenderName : name,
            senderAvatarURL: Self.nonEmpty(senderAvatarUrl).flatMap { URL(string: $0) },
            body: text,
            recipients: recipients.map { max(0, $0) },
            createdAt: Date(timeIntervalSince1970: TimeInterval(millis) / 1000),
            createdEpochUs: cursor,
            isOwn: own
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// 줄 하나가 깨져도(모양이 틀린 칸) 나머지는 살린다.
private struct MegaphoneFeedLossyRow: Decodable {
    let row: MegaphoneFeedRow?
    init(from decoder: Decoder) throws { row = try? MegaphoneFeedRow(from: decoder) }
}

/// 응답 한 벌(줄 배열).
package struct MegaphoneFeedResponse: Decodable, Equatable, Sendable {
    /// 읽힌 줄(깨진 줄은 빠졌다).
    package var rows: [MegaphoneFeedRow]
    /// 전선에 실려 온 줄 수(깨진 줄 포함) — "받은 줄이 `p_limit` 보다 적으면 끝"을 이 수로 본다
    /// (깨진 줄을 빼고 세면 30줄짜리 쪽이 29줄로 보여 더 보기가 끊긴다).
    package var wireRowCount: Int

    package init(rows: [MegaphoneFeedRow], wireRowCount: Int? = nil) {
        self.rows = rows
        self.wireRowCount = wireRowCount ?? rows.count
    }

    package init(from decoder: Decoder) throws {
        let array = try decoder.singleValueContainer().decode([MegaphoneFeedLossyRow].self)
        self.init(rows: array.compactMap(\.row), wireRowCount: array.count)
    }

    /// 이 쪽 뒤에 더 있는가: 가득 찼는가(전선 줄 수 ≥ 요청한 수).
    package func hasMore(limit: Int) -> Bool {
        limit > 0 && wireRowCount >= limit
    }

    /// 화면 값 한 쪽으로(네트워크 없음). 줄을 도메인으로 바꾸고(읽을 수 없는 줄은 뺀다) 쪽 안 중복을 지운다.
    package func page(limit: Int, me: String?) -> MegaphoneFeedPage {
        var seen: Set<String> = []
        let items = rows.compactMap { $0.item(me: me) }.filter { seen.insert($0.id).inserted }
        return MegaphoneFeedPage(items: items, hasMore: hasMore(limit: limit))
    }
}

/// 한 쪽(도메인). 스토어가 이것만 본다.
package struct MegaphoneFeedPage: Equatable, Sendable {
    /// 최신이 먼저 · 쪽 안 중복 없음.
    package var items: [MegaphoneFeedItem]
    /// 이 쪽 뒤에 더 있다(가득 찬 쪽).
    package var hasMore: Bool

    package init(items: [MegaphoneFeedItem], hasMore: Bool) {
        self.items = items
        self.hasMore = hasMore
    }
}

/// `megaphone_admin_hide(p_id, p_hidden)` 요청. 키 둘을 언제나 싣는다(PostgREST 키 집합 규약).
package struct MegaphoneAdminHideRequest: Encodable, Equatable, Sendable {
    package let pId: String
    package let pHidden: Bool

    package init(pId: String, pHidden: Bool = true) {
        self.pId = pId
        self.pHidden = pHidden
    }

    package enum CodingKeys: String, CodingKey {
        case pId = "p_id"
        case pHidden = "p_hidden"
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pId, forKey: .pId)
        try container.encode(pHidden, forKey: .pHidden)
    }
}

/// `megaphone_admin_hide` 응답 `{"status": ok|forbidden|not_found, "hidden": bool}`.
package struct MegaphoneAdminHideResponse: Decodable, Equatable, Sendable {
    package var status: String?
    package var hidden: Bool?

    package init(status: String?, hidden: Bool? = nil) {
        self.status = status
        self.hidden = hidden
    }

    package enum Outcome: Equatable, Sendable {
        /// 내렸다(또는 이미 없는 글 — 어느 쪽이든 목록에서 뺀다).
        case hidden
        /// 운영자가 아니다(서버 `is_app_admin()` 이 판정).
        case forbidden
        /// 모르는 답.
        case failed
    }

    package var outcome: Outcome {
        switch status {
        case "ok", "not_found": return .hidden
        case "forbidden": return .forbidden
        default: return .failed
        }
    }
}

extension SupabaseWorkService {
    package nonisolated static let megaphoneFeedPath = "/rest/v1/rpc/megaphone_feed"
    package nonisolated static let megaphoneAdminHidePath = "/rest/v1/rpc/megaphone_admin_hide"

    /// 지난 확성기 한 쪽. `beforeUs` 는 이미 보이는 가장 오래된 줄의 `created_epoch_us`(첫 쪽은 nil — null 로 실린다).
    /// `me` 는 지금 계정의 id(서버가 `is_mine` 을 안 실었을 때 내 글을 가르는 데만 쓴다).
    /// 함수가 없는 서버(PGRST202 · 404)는 던진다 — 스토어가 "문 닫힘"으로 접는다.
    package func fetchMegaphoneFeed(accessToken: String, beforeUs: Int64?, limit: Int = MegaphoneFeedRules.pageSize,
                                    me: String?) async throws -> MegaphoneFeedPage {
        let data = try await send(
            path: Self.megaphoneFeedPath,
            method: "POST",
            body: MegaphoneFeedRequest(pBeforeUs: beforeUs, pLimit: limit),
            accessToken: accessToken,
            prefer: nil
        )
        let response = try decoder.decode(MegaphoneFeedResponse.self, from: data)
        return response.page(limit: limit, me: me)
    }

    /// 운영자 [내리기]. 판정은 서버(`is_app_admin()`)가 한다 — 운영자가 아니면 `forbidden`.
    package func megaphoneAdminHide(accessToken: String, megaphoneID: String,
                                    hidden: Bool = true) async throws -> MegaphoneAdminHideResponse {
        let data = try await send(
            path: Self.megaphoneAdminHidePath,
            method: "POST",
            body: MegaphoneAdminHideRequest(pId: megaphoneID, pHidden: hidden),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(MegaphoneAdminHideResponse.self, from: data)
    }
}

// MARK: - 스토어(맥·폰 공용)

/// 페이지의 결과 한 줄(운영자 [내리기]의 결과).
package struct MegaphoneFeedNotice: Equatable, Sendable {
    package let text: String
    package let isError: Bool

    package init(text: String, isError: Bool) {
        self.text = text
        self.isError = isError
    }
}

@MainActor
@Observable
package final class MegaphoneFeedStore {
    /// 네트워크·세션을 빌리는 곳. 약참조 — 소유자가 이 스토어를 쥔다(`MegaphoneStore` 와 같은 규약).
    @ObservationIgnored package private(set) weak var host: (any GomokuStoreHost)?
    /// 한 쪽 크기(시험이 줄인다).
    @ObservationIgnored package var pageSize = MegaphoneFeedRules.pageSize

    /// 받은 줄(최신이 먼저 · 확성기 id 로 중복 없음). **화면은 이것을 그대로 그리지 않는다** — 차단으로 걷어낸 사람은 읽는 자리에서 뺀다.
    package private(set) var items: [MegaphoneFeedItem] = []
    /// 페이지가 열려 있는가(소유자가 연다 · 닫는다). 실시간 신호는 이것이 참일 때만 새로 읽는다.
    package private(set) var isOpen = false
    /// 문(머리말 ②). nil 모름 · false 닫힘 · true 열림.
    package private(set) var isAvailable: Bool?
    /// 첫 쪽을 읽는 중.
    package private(set) var isLoading = false
    /// 다음 쪽을 읽는 중.
    package private(set) var isLoadingMore = false
    /// 첫 쪽을 한 번이라도 받았다(빈 목록 = "없어요"와 "아직 모름"을 가른다).
    package private(set) var hasLoaded = false
    /// 마지막 첫 쪽 읽기가 연결 문제로 실패했다.
    package private(set) var loadFailed = false
    /// 마지막 더 보기가 실패했다.
    package private(set) var loadMoreFailed = false
    /// 더 오래된 줄이 남았다(꼬리 아래 [이전 확성기 더 보기]).
    package private(set) var hasMore = false
    /// 운영자 [내리기]가 날아가는 중인 줄(겹쳐 누르기 잠금).
    package private(set) var hidingID: String?
    /// 결과 한 줄(운영자 [내리기]).
    package private(set) var notice: MegaphoneFeedNotice?

    @ObservationIgnored private var resetGeneration = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var rerunRequested = false

    package init(host: (any GomokuStoreHost)? = nil) {
        self.host = host
    }

    /// 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다(맥 WorkTimerStore — 저장 프로퍼티를 다 채우기 전에는 self 를 넘길 수 없다).
    package func attach(host: any GomokuStoreHost) {
        self.host = host
    }

    // MARK: 화면 사건

    /// 페이지를 연다 — 언제나 첫 쪽을 다시 읽는다(그 사이 새 확성기가 왔을 수 있다). 받아 둔 줄은 읽는 동안 그대로 보인다.
    @discardableResult
    package func open() -> Task<Void, Never>? {
        isOpen = true
        if notice != nil { notice = nil }
        return refresh()
    }

    /// 페이지를 닫는다. 받아 둔 줄은 남긴다(다시 열면 곧바로 보이고 그 위로 새로 읽는다). 결과 한 줄은 걷는다.
    package func close() {
        if isOpen { isOpen = false }
        if notice != nil { notice = nil }
    }

    /// 다음 자연스러운 진입(맥: 작성기 열기)에서 닫힘을 **모름으로** 되돌린다(머리말 ②). 요청은 없다 — 문이 다시 서고,
    /// 누르면 그때 묻는다. 열림·모름이면 아무것도 안 한다.
    package func rearm() {
        if isAvailable == false { isAvailable = nil }
    }

    /// 첫 쪽을 읽어 목록 머리를 갈아 끼운다. 겹친 호출은 하나로 모이되, 진행 중에 들어온 요청은 **한 번 더** 돈다
    /// (그 사이 도착한 확성기를 놓치지 않게 — 배너 스토어의 refresh 와 같은 규약).
    @discardableResult
    package func refresh() -> Task<Void, Never>? {
        if let running = refreshTask {
            rerunRequested = true
            return running
        }
        guard let host, host.session != nil else { return nil }
        // 세대는 **부르는 순간** 붙잡는다 — 요청이 나가기 전에 계정이 바뀌어도 앞 계정의 새로고침이 다음 계정 이름으로 돌지 않게.
        let generation = resetGeneration
        let sessionGeneration = host.sessionGeneration
        isLoading = true
        if loadFailed { loadFailed = false }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.rerunRequested = false
                await self.performRefresh(host: host, generation: generation, sessionGeneration: sessionGeneration)
                guard generation == self.resetGeneration else { return }
            } while self.rerunRequested
            self.refreshTask = nil
            self.isLoading = false
        }
        refreshTask = task
        return task
    }

    /// 꼬리 아래 [이전 확성기 더 보기]. 커서는 지금 목록의 **마지막(가장 오래된) 줄의 µs** 다. 겹쳐 누르면 하나만 나간다.
    @discardableResult
    package func loadMore() -> Task<Void, Never>? {
        guard isAvailable == true, hasMore, !isLoadingMore, let tail = items.last,
              let host, host.session != nil else { return nil }
        let generation = resetGeneration
        let sessionGeneration = host.sessionGeneration
        let service = host.service
        let limit = pageSize
        let me = host.session?.userID
        let cursor = tail.createdEpochUs
        let tailID = tail.megaphoneID
        isLoadingMore = true
        if loadMoreFailed { loadMoreFailed = false }
        return Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let page = try await host.withSessionRetry { session in
                    try await service.fetchMegaphoneFeed(accessToken: session.accessToken, beforeUs: cursor, limit: limit, me: me)
                }
                guard host.sessionGeneration == sessionGeneration, generation == self.resetGeneration else { return }
                self.isLoadingMore = false
                self.applyNextPage(page, tailID: tailID)
            } catch {
                guard host.sessionGeneration == sessionGeneration, generation == self.resetGeneration else { return }
                self.isLoadingMore = false
                if case .cancelled = host.classifyAuthError(error) { return }
                if Self.isMissingFunction(error) {
                    self.shutDoor()
                    return
                }
                self.loadMoreFailed = true
            }
        }
    }

    /// 운영자 [내리기]. 운영자 판정은 서버가 한다(`forbidden`). 겹쳐 누르면 하나만 나간다.
    /// 성공(`ok` · 이미 없는 글 `not_found`)이면 그 줄을 목록에서 뺀다. 반환 Task 는 시험이 기다리는 손잡이다.
    @discardableResult
    package func adminHide(megaphoneID: String) -> Task<Void, Never>? {
        guard hidingID == nil, items.contains(where: { $0.id == megaphoneID }),
              let host, host.session != nil else { return nil }
        let generation = resetGeneration
        let sessionGeneration = host.sessionGeneration
        let service = host.service
        hidingID = megaphoneID
        if notice != nil { notice = nil }
        return Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await host.withSessionRetry { session in
                    try await service.megaphoneAdminHide(accessToken: session.accessToken, megaphoneID: megaphoneID)
                }
                guard host.sessionGeneration == sessionGeneration, generation == self.resetGeneration else { return }
                self.hidingID = nil
                switch response.outcome {
                case .hidden:
                    self.items.removeAll { $0.id == megaphoneID }
                    self.notice = MegaphoneFeedNotice(text: MegaphoneFeedText.adminHidden, isError: false)
                case .forbidden:
                    self.notice = MegaphoneFeedNotice(text: MegaphoneFeedText.adminForbidden, isError: true)
                case .failed:
                    self.notice = MegaphoneFeedNotice(text: MegaphoneFeedText.adminHideFailed, isError: true)
                }
            } catch {
                guard host.sessionGeneration == sessionGeneration, generation == self.resetGeneration else { return }
                self.hidingID = nil
                if case .cancelled = host.classifyAuthError(error) { return }
                self.notice = MegaphoneFeedNotice(text: MegaphoneFeedText.adminHideFailed, isError: true)
            }
        }
    }

    /// 로그아웃·계정 전환. 계정에 묶인 값(목록·문·떠 있는 요청)을 전부 비우고, 나가 있던 응답은 세대로 버린다.
    package func reset() {
        resetGeneration += 1
        refreshTask = nil
        rerunRequested = false
        items = []
        isOpen = false
        isAvailable = nil
        isLoading = false
        isLoadingMore = false
        hasLoaded = false
        loadFailed = false
        loadMoreFailed = false
        hasMore = false
        hidingID = nil
        notice = nil
    }

    // MARK: 내부

    private func performRefresh(host: any GomokuStoreHost, generation: Int, sessionGeneration: Int) async {
        guard host.session != nil, host.sessionGeneration == sessionGeneration, generation == resetGeneration else { return }
        let service = host.service
        let limit = pageSize
        let me = host.session?.userID
        do {
            let page = try await host.withSessionRetry { session in
                try await service.fetchMegaphoneFeed(accessToken: session.accessToken, beforeUs: nil, limit: limit, me: me)
            }
            guard host.sessionGeneration == sessionGeneration, generation == resetGeneration else { return }
            applyFirstPage(page)
        } catch {
            guard host.sessionGeneration == sessionGeneration, generation == resetGeneration else { return }
            if case .cancelled = host.classifyAuthError(error) { return }
            if Self.isMissingFunction(error) {
                shutDoor()
                return
            }
            loadFailed = true
        }
    }

    /// 첫 쪽 반영(네트워크 없음). 새 머리의 가장 오래된 줄이 지금 목록에 있으면 그 아래 꼬리(이미 더 보기로 받은 줄)를 살린다 —
    /// 실시간 새로고침이 사용자가 내려 읽던 자리를 날리지 않게. 없으면(그 사이 한 쪽보다 많이 왔다) 새 머리로 갈아 끼운다.
    package func applyFirstPage(_ page: MegaphoneFeedPage) {
        if isAvailable != true { isAvailable = true }
        let fresh = page.items
        let pageHasMore = page.hasMore && !fresh.isEmpty
        loadFailed = false
        hasLoaded = true
        if let oldest = fresh.last, let index = items.firstIndex(where: { $0.id == oldest.id }) {
            let freshIDs = Set(fresh.map(\.id))
            let tail = items[items.index(after: index)...].filter { !freshIDs.contains($0.id) }
            items = fresh + tail
            if tail.isEmpty { hasMore = pageHasMore }
        } else {
            items = fresh
            hasMore = pageHasMore
        }
    }

    /// 다음 쪽 반영(네트워크 없음). 그 사이 꼬리가 바뀌었으면 버린다(머리말 ④).
    private func applyNextPage(_ page: MegaphoneFeedPage, tailID: String) {
        guard items.last?.megaphoneID == tailID else { return }
        let known = Set(items.map(\.id))
        let added = page.items.filter { !known.contains($0.id) }
        items += added
        // 새 줄이 하나도 없으면 더 없는 것으로 본다 — 같은 커서로 같은 쪽을 끝없이 다시 묻지 않게.
        hasMore = page.hasMore && !added.isEmpty
    }

    /// 문이 닫혔다(함수 없음). 받아 둔 줄은 내린다 — 문이 닫힌 기능의 글을 계속 보여 줄 이유가 없다.
    private func shutDoor() {
        if isAvailable != false { isAvailable = false }
        items = []
        hasMore = false
        loadFailed = false
        loadMoreFailed = false
    }

    private static func isMissingFunction(_ error: Error) -> Bool {
        guard let known = error as? SupabaseWorkServiceError else { return false }
        return BlockReportRules.isMissingFunction(known)
    }
}
