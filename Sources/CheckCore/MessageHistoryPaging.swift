import Foundation

// MARK: - 이전 대화 더 보기 (2026-11-11 — 메시지 30일 보관 · `message_page`)
//
// 대표 결정(#d_IKem7qxZXc5b): "메시지 30일로 늘리기" — 앱에 '이전 대화 더 보기' 추가.
// 서버(서버 안정화 11-11 최종 목록 §1): 옛 함수(`message_history*` · 안 읽음 요약 v1/v2 · 읽음 처리 · 푸시 만료)는 **24시간 그대로**,
// 지우는 기간만 `message_store_days()` = 30. 새 앱만 `message_page(p_peer, p_before_us, p_before_id, p_limit)` 로 30일 안을 쪽으로 넘긴다.
// 문(min_build)은 없다 — 로그인만 본다. 함수가 아직 없는 서버(404 · PGRST202)면 버튼을 숨긴다(스토어 몫).
//
// **전선 이름·키·행 모양은 전부 이 파일 한 곳**에 있다(경로 · 요청 네 키 · 행 열네 칸 · 커서).
//
// ── 이 파일이 지키는 것 ──
//  ① **24시간 머리(head)는 그대로다.** 옛 상수(`historyHours` · `expiry`)를 바꾸지 않고 새 상수만 더한다(폰과 한 벌).
//  ② **지난 쪽(page)은 안 읽음 재료가 아니다.** 지난 쪽 줄은 읽음 경계·점 어디에도 안 들어간다 — 그래서 옮길 때 서버의
//     `unread_for_me` 를 **싣지 않는다**(초기화 인자를 안 넘겨 기본값 nil). 24시간 너머의 받은 말에 unread=true 가 와도
//     메뉴바 점이 켜지지 않는다(24시간 요약이 세지 않는 말에 점이 켜지면 영영 안 꺼진다).
//  ③ **확성기 줄은 버린다**(`is_megaphone`). 확성기는 메시지함 밖이다. 버린 줄도 **커서는 된다** — 확성기만 담긴 쪽에서 멈추지 않게.
//  ④ **커서는 정수 마이크로초 + id 다**(`created_epoch_us` — Int64, 실수로 바꾸지 마라: 2^53 을 넘는 날 경계 줄이 겹치거나 빠진다).
//  ⑤ 디코드는 칸 하나로 죽지 않는다(행마다 칸을 따로 읽고, 깨진 원소는 그 원소만 버린다).
//  ⑥ 본문은 사람이 쓴 문장이다 — `print`/`Logger` 를 붙이지 마라.
//
// ★ 디코더 함정: 서비스 디코더는 `.convertFromSnakeCase` 다. 행 모델의 칸 이름은 **카멜**로 두고 스네이크 원값을 주지 않는다
//   (원값 "created_epoch_us" 를 주면 그 디코더에서 조용히 nil 이 된다). 시험은 같은 디코더로 읽는다(MessageOlderHistoryTests).

// MARK: - 상수 · 문구

extension MessageNoticeText {
    /// 서버가 메시지를 지우기 전까지 두는 날수(서버 `message_store_days()`). 24시간 머리(`historyHours`)와 **다른 값**이다.
    package static let storeDays = 30
    /// "이전 대화 더 보기" 한 번의 요청이 받는 건수(서버 범위 1~100).
    package static let olderPageLimit = 50
    /// 한 번 누를 때 최대 몇 번까지 이어 묻는가. 첫 누름은 커서 없이 최신부터 받으므로 24시간 머리와 겹친 쪽을 건너뛰어야 한다 —
    /// 머리는 최대 `historyLimit` 줄이라 꽉 찬 쪽 `historyLimit / olderPageLimit` 번이 전부 겹칠 수 있고, 그 다음 한 번이 옛 줄에 닿는다.
    package static var olderCatchUpRequests: Int { historyLimit / olderPageLimit + 1 }

    /// 대화 맨 위 줄의 버튼 글자.
    package static let olderButtonTitle = "이전 대화 더 보기"
    /// 받는 중.
    package static let olderLoading = "이전 대화를 불러오는 중…"
    /// 실패(다시 누르면 다시 받는다).
    package static let olderFailed = "이전 대화를 못 불러왔어요 · 다시 시도"
    /// 서버가 "더 없다"고 했다.
    package static let olderEnd = "더 이전 대화가 없어요"

    /// 버튼 툴팁 — 숫자는 상수에서 나온다.
    package static var olderTooltip: String {
        "\(storeDays)일 안의 이전 대화를 불러와요"
    }

    /// 보관 안내(새 서버 — `message_page` 가 한 번이라도 성공한 뒤에만 쓴다). 옛 `expiry`("24시간이 …")는 그대로다.
    package static var storeExpiry: String {
        "\(storeDays)일이 지난 메시지는 사라져요"
    }

    /// 사진만 보낸 줄의 대체 글(서버 `message_photo_fallback_body()` 와 같은 글). 사진 그리기는 다음 판이다 — 지금은 글만 그린다.
    package static let photoFallbackBody = "📷 사진"
}

// MARK: - 전선 모양

/// 다음 쪽 커서: 지금까지 받은 줄 중 **가장 오래된 줄**의 (정수 마이크로초, id). 서버 정렬은 (created_at desc, id desc)다.
package struct MessagePageCursor: Equatable, Sendable {
    /// `created_epoch_us` 그대로(Int64 — 실수로 바꾸지 않는다).
    package let epochMicros: Int64
    package let id: String

    package init(epochMicros: Int64, id: String) {
        self.epochMicros = epochMicros
        self.id = id
    }

    /// 서버 정렬에서 이 줄이 `other` 보다 오래됐는가(같은 µs 는 id 가 작은 쪽이 오래됐다 — 서버 `m.id < p_before_id`).
    /// uuid 의 정렬은 소문자 16진 표기의 사전 순과 같다.
    package func isOlder(than other: MessagePageCursor) -> Bool {
        epochMicros != other.epochMicros ? epochMicros < other.epochMicros : id.lowercased() < other.id.lowercased()
    }
}

/// `message_page` 요청. **네 키를 언제나 싣는다**(커서가 없으면 두 커서 키를 JSON null 로) —
/// PostgREST 는 본문의 키 집합으로 함수를 고른다(V0313 의 교훈).
package struct MessagePageRequest: Encodable, Equatable, Sendable {
    package let pPeer: String
    package let pBeforeUs: Int64?
    package let pBeforeId: String?
    package let pLimit: Int

    package init(peer: String, before: MessagePageCursor?, limit: Int) {
        pPeer = peer
        pBeforeUs = before?.epochMicros
        pBeforeId = before?.id
        pLimit = limit
    }

    /// 키를 이미 스네이크로 적는다(인코더의 스네이크 변환은 대문자 없는 글자를 그대로 지난다).
    package enum CodingKeys: String, CodingKey {
        case pPeer = "p_peer"
        case pBeforeUs = "p_before_us"
        case pBeforeId = "p_before_id"
        case pLimit = "p_limit"
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pPeer, forKey: .pPeer)
        // `encode` 다(encodeIfPresent 가 아니다) — nil 이면 키를 빼지 않고 null 을 싣는다.
        try container.encode(pBeforeUs, forKey: .pBeforeUs)
        try container.encode(pBeforeId, forKey: .pBeforeId)
        try container.encode(pLimit, forKey: .pLimit)
    }
}

/// 응답 한 행(서버 최종 목록 §1의 열네 칸). **칸마다 따로 읽는다**(머리 ⑤).
package struct MessagePageRow: Decodable, Equatable, Sendable {
    package var id: String?
    package var fromUser: String?
    package var toUser: String?
    /// 저장된 본문(옛 앱이 보는 글 — 사진만 보냈으면 '📷 사진').
    package var body: String?
    /// 사진과 같이 보낸 글. 사진만 보냈으면 null.
    package var caption: String?
    package var photoPath: String?
    package var photoWidth: Int?
    package var photoHeight: Int?
    /// 확성기 줄(머리 ③ — 버린다).
    package var isMegaphone: Bool?
    package var isMine: Bool?
    /// 화면 시각(밀리초).
    package var createdEpochMs: Int64?
    /// 다음 쪽 커서(정수 마이크로초 — 머리 ④).
    package var createdEpochUs: Int64?
    /// 내가 보낸 줄만: 상대가 읽었나.
    package var readByPeer: Bool?
    /// 받은 줄만: 내가 안 읽었나. **읽기만 하고 옮기지 않는다**(머리 ②).
    package var unreadForMe: Bool?

    package init(
        id: String? = nil, fromUser: String? = nil, toUser: String? = nil, body: String? = nil, caption: String? = nil,
        photoPath: String? = nil, photoWidth: Int? = nil, photoHeight: Int? = nil, isMegaphone: Bool? = nil, isMine: Bool? = nil,
        createdEpochMs: Int64? = nil, createdEpochUs: Int64? = nil, readByPeer: Bool? = nil, unreadForMe: Bool? = nil
    ) {
        self.id = id
        self.fromUser = fromUser
        self.toUser = toUser
        self.body = body
        self.caption = caption
        self.photoPath = photoPath
        self.photoWidth = photoWidth
        self.photoHeight = photoHeight
        self.isMegaphone = isMegaphone
        self.isMine = isMine
        self.createdEpochMs = createdEpochMs
        self.createdEpochUs = createdEpochUs
        self.readByPeer = readByPeer
        self.unreadForMe = unreadForMe
    }

    /// 카멜 이름만(원값 없음) — 서비스 디코더의 스네이크 변환이 `created_epoch_us` → `createdEpochUs` 로 맞춘다.
    private enum CodingKeys: String, CodingKey {
        case id, fromUser, toUser, body, caption, photoPath, photoWidth, photoHeight, isMegaphone, isMine
        case createdEpochMs, createdEpochUs, readByPeer, unreadForMe
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
        func flag(_ key: CodingKeys) -> Bool? { (try? c.decodeIfPresent(Bool.self, forKey: key)) ?? nil }
        func whole(_ key: CodingKeys) -> Int? { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil }
        /// 정수로만 읽는다(숫자 또는 숫자 글자). 실수 갈래가 없다 — 커서가 실수를 지나면 경계 줄이 겹치거나 빠진다(머리 ④).
        func exact(_ key: CodingKeys) -> Int64? {
            if let number = (try? c.decodeIfPresent(Int64.self, forKey: key)) ?? nil { return number }
            return text(key).flatMap { Int64($0) }
        }
        id = text(.id)
        fromUser = text(.fromUser)
        toUser = text(.toUser)
        body = text(.body)
        caption = text(.caption)
        photoPath = text(.photoPath)
        photoWidth = whole(.photoWidth)
        photoHeight = whole(.photoHeight)
        isMegaphone = flag(.isMegaphone)
        isMine = flag(.isMine)
        createdEpochMs = exact(.createdEpochMs)
        createdEpochUs = exact(.createdEpochUs)
        readByPeer = flag(.readByPeer)
        unreadForMe = flag(.unreadForMe)
    }

    /// 이 줄의 커서(µs · id 둘 다 있을 때만).
    package var cursor: MessagePageCursor? {
        guard let id, !id.isEmpty, let createdEpochUs else { return nil }
        return MessagePageCursor(epochMicros: createdEpochUs, id: id)
    }
}

/// 배열의 원소 하나가 깨져도 그 원소만 nil 로 접는 상자.
package struct MessagePageLossyRow: Decodable, Sendable {
    package let row: MessagePageRow?
    package init(from decoder: Decoder) throws {
        row = try? MessagePageRow(from: decoder)
    }
}

/// 지난 쪽 한 번(옮긴 뒤).
package struct MessagePage: Equatable, Sendable {
    /// 그릴 줄(**오래된 것 → 최신**). 확성기 · 다른 대화 · 보이는 글자 없는 줄은 빠졌고, 받은 쪽 안 읽음 칸은 비어 있다.
    package let entries: [MessageHistoryEntry]
    /// 서버가 준 줄 수(버린 줄 · 깨진 원소 포함) — 쪽 끝 판정의 재료.
    package let rowCount: Int
    /// 서버가 준 줄 중 가장 오래된 줄의 커서(버린 줄도 든다 — 머리 ③). 쓸 만한 줄이 하나도 없으면 nil.
    package let oldestCursor: MessagePageCursor?
    /// 요청 상한.
    package let limit: Int

    package init(entries: [MessageHistoryEntry], rowCount: Int, oldestCursor: MessagePageCursor?, limit: Int) {
        self.entries = entries
        self.rowCount = rowCount
        self.oldestCursor = oldestCursor
        self.limit = limit
    }

    /// 더 이전 쪽이 있는가: 꽉 찬 쪽(받은 줄 수 == 상한)이고 다음 커서를 얻었다. 상한보다 적으면 끝이다(서버 계약).
    package var hasMore: Bool { rowCount >= limit && oldestCursor != nil }
}

// MARK: - 서비스

extension SupabaseWorkService {
    package nonisolated static let messagePagePath = "/rest/v1/rpc/message_page"

    /// 지난 쪽 한 번. **버튼을 눌렀을 때만** 부른다(패널 열기 · 폴링 · 전송 어디에서도 안 부른다).
    /// 함수가 없는 서버(404/PGRST202)는 그대로 던진다 — 버튼을 숨길지는 스토어가 정한다(`isMissingMessageReadFunction`).
    /// 배열이 아닌 답은 디코드 오류로 던진다(스토어는 실패로 그린다).
    ///
    /// - Parameters:
    ///   - peer: 대화 상대. 응답 줄의 두 사람이 나와 이 사람이 아니면 버린다(다른 대화가 섞이지 않게).
    ///   - me: 내 user id. 응답이 `is_mine` 을 안 실으면 보낸이 칸과 비교해 판정한다.
    ///   - before: 다음 쪽 커서. nil 이면 30일 안의 최신부터(첫 누름).
    ///   - peerName · peerAvatarURL: 행이 상대 이름·아바타를 안 싣는다 — 대화 머리가 아는 값을 쓴다.
    package func fetchMessagePage(
        accessToken: String,
        peer: String,
        me: String,
        before: MessagePageCursor?,
        limit: Int = MessageNoticeText.olderPageLimit,
        peerName: String? = nil,
        peerAvatarURL: URL? = nil
    ) async throws -> MessagePage {
        let clamped = min(100, max(1, limit))
        let data = try await send(
            path: Self.messagePagePath,
            method: "POST",
            body: MessagePageRequest(peer: peer, before: before, limit: clamped),
            accessToken: accessToken,
            prefer: nil
        )
        return try messagePage(from: data, peer: peer, me: me, limit: clamped, peerName: peerName, peerAvatarURL: peerAvatarURL)
    }

    /// 응답 바이트 → 지난 쪽. 디코더는 **서비스의 것**(스네이크 변환)이다 — 시험이 같은 바이트를 같은 디코더로 흘린다.
    package func messagePage(
        from data: Data,
        peer: String,
        me: String,
        limit: Int,
        peerName: String? = nil,
        peerAvatarURL: URL? = nil
    ) throws -> MessagePage {
        let rows = try decoder.decode([MessagePageLossyRow].self, from: data).map(\.row)
        var oldest: MessagePageCursor?
        for cursor in rows.compactMap({ $0?.cursor }) where oldest.map({ cursor.isOlder(than: $0) }) ?? true {
            oldest = cursor
        }
        let entries = rows.compactMap { row in
            row.flatMap { messagePageEntry($0, peer: peer, me: me, peerName: peerName, peerAvatarURL: peerAvatarURL) }
        }
        // 서버는 최신부터 준다 — 오래된 것부터로 뒤집는다(같은 µs 의 선후도 서버 순서 그대로 뒤집힌다).
        return MessagePage(entries: entries.reversed(), rowCount: rows.count, oldestCursor: oldest, limit: limit)
    }

    /// 행 → 표시용 한 건. 버리는 줄: id 없음 · 확성기 줄 · 다른 대화 · 내 말인지 모름 · 보이는 글자 없음 · 시각 없음.
    /// 글은 `caption` 이 있으면 그것, 없으면 `body`(사진만 보낸 줄은 '📷 사진')다 — 사진은 다음 판에 그린다.
    /// 받은 쪽 안 읽음(`unread_for_me`)은 **싣지 않는다**(머리 ②). 내가 보낸 말의 읽음(1)은 싣는다.
    package func messagePageEntry(
        _ row: MessagePageRow,
        peer: String,
        me: String,
        peerName: String? = nil,
        peerAvatarURL: URL? = nil
    ) -> MessageHistoryEntry? {
        guard let id = row.id, !id.isEmpty else { return nil }
        if row.isMegaphone == true { return nil }
        let peerKey = peer.lowercased()
        let meKey = me.lowercased()
        let from = row.fromUser.flatMap { $0.isEmpty ? nil : $0.lowercased() }
        let to = row.toUser.flatMap { $0.isEmpty ? nil : $0.lowercased() }
        // 이 대화의 줄인가 — 두 칸이 다 있으면 {나, 상대} 그대로여야 한다.
        if let from, let to, !((from == meKey && to == peerKey) || (from == peerKey && to == meKey)) {
            return nil
        }
        let isMine: Bool
        if let flagged = row.isMine {
            isMine = flagged
        } else if let from, !meKey.isEmpty, from == meKey || from == peerKey {
            isMine = from == meKey
        } else {
            return nil
        }
        let caption = row.caption.flatMap { MessageBody.hasVisibleContent($0) ? $0 : nil }
        let text = caption ?? row.body ?? (row.photoPath == nil ? "" : MessageNoticeText.photoFallbackBody)
        let body = MessageBody.sanitized(text)
        guard MessageBody.hasVisibleContent(body) else { return nil }
        let createdAt: Date
        if let ms = row.createdEpochMs {
            createdAt = Date(timeIntervalSince1970: TimeInterval(ms) / 1_000)
        } else if let us = row.createdEpochUs {
            createdAt = Date(timeIntervalSince1970: TimeInterval(us / 1_000) / 1_000)
        } else {
            return nil
        }
        return MessageHistoryEntry(
            id: id,
            peerUserID: peer,
            peerName: peerName.flatMap { $0.isEmpty ? nil : $0 } ?? "사용자",
            peerAvatarURL: peerAvatarURL,
            body: body,
            createdAt: createdAt,
            isMine: isMine,
            readByPeer: isMine ? row.readByPeer : nil
        )
    }
}

// MARK: - 규칙 (순수)

/// 지난 쪽과 24시간 머리를 잇는 규칙. **다시 정렬하지 않고 잇는다** — 지난 쪽 id 는 머리의 서버 순서표에 없어서
/// `sortedForMessageHistory` 로 함께 세우면 같은 초의 머리 줄 **뒤**로 밀린다(순서표에 없는 id = Int.max).
package enum MessageOlderHistoryRules {
    /// 머리 시각은 초 단위로 반올림된 값이다(옛 함수의 `created_epoch`). 그보다 "새 줄"을 가를 때 이만큼 너그럽게 본다.
    package static let headClockSlack: TimeInterval = 1
    /// 머리 미끄러짐에서 24시간 경계를 이만큼 너그럽게 본다(서버 `now()` 와 맥 시계의 차이). 시계가 늦은 맥에서 경계를 빡빡하게
    /// 재면 정말 미끄러진 줄을 못 옮겨 대화 가운데가 빈다 — 너그러워서 잃는 것은 "곧 사라질 줄"이 몇 분 더 남는 것뿐이다.
    package static let headWindowSlack: TimeInterval = 600

    /// 화면이 그릴 한 줄: 지난 쪽(머리에 있는 id 는 뺀다 — **머리가 이긴다**) + 머리. 다시 정렬하지 않는다.
    /// 머리가 이기는 것은 읽음도 같다(`readFollowingHead` — 지난 쪽의 내 말 "1"이 머리보다 낡지 않게).
    package static func merged(older: [MessageHistoryEntry], head: [MessageHistoryEntry]) -> [MessageHistoryEntry] {
        guard !older.isEmpty else { return head }
        let headIDs = Set(head.map(\.id))
        var seen: Set<String> = []
        let kept = older.filter { !headIDs.contains($0.id) && seen.insert($0.id).inserted }
        return readFollowingHead(older: kept, head: head) + head
    }

    /// 지난 쪽의 내 말 읽음(1)을 머리에 맞춘다. 지난 쪽 줄은 받은 그때의 값을 들고 있고 다시 안 받는다 — 상대가 그 뒤에 읽어도
    /// 머리(다시 받는다)만 1이 지워져, 새 말은 읽었는데 옛 말은 안 읽었다고 그린다.
    /// 머리에 **상대가 읽은 내 말이 하나라도 있으면** 지난 쪽의 내 말은 전부 읽은 것이다: 지난 쪽 줄은 서버 순서에서 머리의 모든 줄보다
    /// 앞이고(머리보다 새 줄은 안 붙인다 — `prepending`), 읽음 경계(`read_until`)는 앞으로만 간다. 그래서 **시각을 비교하지 않는다**
    /// (초 단위 `createdAt` 으로 다시 세지 않는다 — `MessageReadReceiptMark` 주석). false → true 만 바꾼다(모름 nil 은 그대로).
    package static func readFollowingHead(older: [MessageHistoryEntry], head: [MessageHistoryEntry]) -> [MessageHistoryEntry] {
        guard head.contains(where: { $0.isMine && $0.readByPeer == true }),
              older.contains(where: { $0.isMine && $0.readByPeer == false })
        else { return older }
        return older.map { entry in
            guard entry.isMine, entry.readByPeer == false else { return entry }
            var read = entry
            read.readByPeer = true
            return read
        }
    }

    /// 받은 쪽(오래된 것 → 최신)을 기존 지난 쪽 **앞에** 붙인다. 빼는 줄:
    ///  - 머리에 있는 id(머리가 이긴다) · 이미 받은 id(중복 없음).
    ///  - 머리의 가장 새 줄보다 **새** 줄 — 머리를 받은 뒤 도착한 말이다. 앞에 붙이면 순서가 뒤집힌다(다음 머리 조회가 받는다).
    /// 결과는 전부 지난 쪽 모양(`pageEntry` — 받은 쪽 안 읽음 칸 비움)이다 — 넘겨받은 기존 쪽이 어디서 왔든 불변식이 선다.
    package static func prepending(
        _ page: [MessageHistoryEntry],
        to older: [MessageHistoryEntry],
        head: [MessageHistoryEntry]
    ) -> [MessageHistoryEntry] {
        var known = Set(older.map(\.id)).union(head.map(\.id))
        let newestHead = head.map(\.createdAt).max()
        var additions: [MessageHistoryEntry] = []
        for entry in page {
            if let newestHead, entry.createdAt > newestHead.addingTimeInterval(headClockSlack) { continue }
            guard known.insert(entry.id).inserted else { continue }
            additions.append(pageEntry(entry))
        }
        return additions + older.map(pageEntry)
    }

    /// 24시간 머리가 미끄러졌다(대화를 오래 열어 둔 채 이력을 다시 받았다). 앞 머리에 있었는데 새 머리에서 빠진 **그 상대의** 줄
    /// (새 머리의 그 상대 맨 앞보다 오래된 것)을 지난 쪽 끝으로 옮긴다 — 안 옮기면 지난 쪽(또는 커서)과 새 머리 맨 앞 사이의 말이
    /// 두 판 어디에도 없어 대화 가운데가 빈다. **언제 부를지는 스토어가 정한다**(그 상대의 쪽을 한 번이라도 받았을 때만 —
    /// 안 받았으면 다음 누름이 커서 없이 최신부터 받아 그 줄을 되찾는다). `previousHead` 는 **화면이 보던 판**이다(확성기 줄을 뺀 판 —
    /// 날것의 이력을 넘기면 받은 확성기 줄이 24시간을 넘는 순간 지난 쪽으로 옮겨져 메시지 말풍선으로 선다).
    ///
    /// **창 경계로도 자른다.** 미끄러짐은 창이 움직여서만 생긴다: 24시간이 지났거나(`now` − `windowHours`, 시계 차이만큼 너그럽게),
    /// 새 머리가 상한(`headLimit`)까지 차서 그 맨 앞보다 옛 줄이 밀려났다. 그보다 **새** 줄이 빠졌으면 서버가 다른 이유로 뺀 것이다
    /// (상대가 나를 차단 · 숨긴 계정 · 운영자 삭제) — 옮기지 않는다. 그 상대의 줄이 새 머리에 하나도 없을 때(상대 맨 앞이 없다)도
    /// 이 경계가 막는다 — 그때 다 옮기면 서버가 감춘 24시간 대화가 "지난 말"로 남는다.
    package static func carriedAcrossHeadSlide(
        peer: String,
        previousHead: [MessageHistoryEntry],
        nextHead: [MessageHistoryEntry],
        older: [MessageHistoryEntry],
        now: Date,
        windowHours: Int = MessageNoticeText.historyHours,
        headLimit: Int = MessageNoticeText.historyLimit
    ) -> [MessageHistoryEntry] {
        let nextIDs = Set(nextHead.map(\.id))
        let edge = nextHead.first(where: { $0.peerUserID == peer })?.createdAt
        var windowEdge = now.addingTimeInterval(-TimeInterval(windowHours) * 3_600 + headWindowSlack)
        if nextHead.count >= headLimit, let oldest = nextHead.map(\.createdAt).min() {
            windowEdge = max(windowEdge, oldest.addingTimeInterval(headClockSlack))
        }
        var known = Set(older.map(\.id))
        var slid: [MessageHistoryEntry] = []
        for entry in previousHead where entry.peerUserID == peer && !nextIDs.contains(entry.id) {
            if let edge, entry.createdAt > edge { continue }
            if entry.createdAt > windowEdge { continue }
            guard known.insert(entry.id).inserted else { continue }
            slid.append(pageEntry(entry))
        }
        return slid.isEmpty ? older : older + slid
    }

    /// 지난 쪽에 둘 모양: 받은 쪽 안 읽음 칸을 **비운** 사본(초기화 인자를 안 넘겨 기본값 nil — 머리 ②). 나머지는 그대로다.
    package static func pageEntry(_ entry: MessageHistoryEntry) -> MessageHistoryEntry {
        MessageHistoryEntry(
            id: entry.id,
            peerUserID: entry.peerUserID,
            peerName: entry.peerName,
            peerAvatarURL: entry.peerAvatarURL,
            body: entry.body,
            createdAt: entry.createdAt,
            isMine: entry.isMine,
            readByPeer: entry.readByPeer
        )
    }
}
