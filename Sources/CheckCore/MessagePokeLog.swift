import Foundation

// MARK: - 대화창 찌르기 기록 (v0.3.65)
//
// 사용자 결정(2026-10-23, 원문): "사람들이 서로 찌르거나 울트라 찌르기 한거 메세지창에 기록으로 남게끔 해줘. 물론 이것도 24시간 뒤에
// 기록 사라지는건 동일하고." · "안 본 찌르기도 '안 읽음'으로 친다" — 그 사람이 나를 찌른 것(일반·울트라)은 내가 그 대화를 열어 보기
// 전까지 안 읽음이다.
//
// 이 파일은 **순수**다(전선 모양 · 디코드 · 안 읽음/경계 규칙 · 대화 줄 끼워 넣기). 맥 스토어가 부르고, 폰이 다음 판에 같은 것을 쓴다.
//
// ── 서버 계약(마이그레이션 `20261023200000_message_poke_log.sql` 머리말 — 그 글을 정본으로 디코더를 맞췄다) ──
//  · 조회: `message_history_with_pokes(p_hours, p_limit)` — `message_history_with_reads` 의 12칸·행 그대로 + **찌르기 행**,
//    끝에 종류 칸 `kind`('message'|'poke'|'ultra'). 찌르기 행은 body·read_by_peer null, `unread` 는 받은 찌르기에만 값.
//    순서는 메시지·찌르기를 **섞어** created_at asc, id asc(마이크로초).
//  · 읽음: `mark_conversation_read(p_peer, p_through_message, p_through_poke)` — 세 인자 모두 DEFAULT, **null 인 갈래는 안 움직인다**.
//    → `{status, advanced, unread, poke_advanced, poke_unread}`. 메시지 갈래는 서버가 `mark_messages_read` 를 그대로 부른다(읽음 신호 포함).
//    옛 `mark_messages_read`·`message_history_with_reads` 는 한 글자도 안 바뀌었다(옛 맥·폰이 쓴다).
//
// ── 이 파일이 지키는 것 ──
//  ① **디코드는 칸 하나로 통째로 죽지 않는다.** 행마다 칸을 따로 읽고(`try?`), 행 하나가 객체가 아니어도 그 행만 버린다.
//     종류 칸이 없으면 메시지로 읽는다(그러면 본문 없는 찌르기 행은 메시지 옮김에서 저절로 빠진다 — 기록이 없을 뿐 대화는 산다).
//     모르는 종류는 버린다(미래에 생길 종류를 메시지 말풍선으로 그리면 빈 말풍선이 된다).
//  ② **메시지 규칙과 섞지 않는다.** 찌르기는 `messageHistory` 에 들어가지 않는다 — 메시지 읽음 경계(`p_through`)·메뉴바 점·말풍선 필터가
//     찌르기 id 를 메시지로 오인하는 길을 타입으로 닫는다.
//  ③ 시각 비교는 **서버 판정**을 따른다. 안 읽음은 서버 플래그, 경계는 찌르기 id, 같은 초의 선후는 서버 시각(마이크로초)이다.

/// 대화 기록에 끼는 찌르기 종류(서버 `kind`).
package enum MessagePokeLogKind: String, Equatable, Sendable {
    case poke
    case ultra

    /// 서버 종류 글자 → 찌르기 줄. `'message'`·nil·모르는 값은 nil(찌르기 줄이 아니다).
    /// `'normal'` 은 pokes 표의 원래 글자다 — 서버가 표의 글자를 그대로 실어도 일반 찌르기로 읽는다.
    package init?(serverKind: String?) {
        switch serverKind?.trimmingCharacters(in: .whitespaces) {
        case "poke", "normal": self = .poke
        case "ultra": self = .ultra
        default: return nil
        }
    }
}

/// 대화 기록의 찌르기 한 건(표시용). 말풍선이 아니다 — 답장·읽음 표시 대상이 아니다.
package struct MessagePokeLogEntry: Identifiable, Equatable, Sendable {
    /// 서버 pokes 행 id.
    package let id: String
    /// 대화 상대(내가 찔렀으면 찔린 사람, 받았으면 찌른 사람).
    package let peerUserID: String
    package let peerName: String
    package let peerAvatarURL: URL?
    package let createdAt: Date
    /// true = 내가 찔렀다.
    package let isMine: Bool
    package let kind: MessagePokeLogKind
    /// **받은 찌르기에만** 값이 있다: 서버 기준 내가 아직 그 대화를 안 열어 봤으면 true. 보낸 것은 nil.
    package var isUnread: Bool?

    package init(
        id: String, peerUserID: String, peerName: String, peerAvatarURL: URL? = nil,
        createdAt: Date, isMine: Bool, kind: MessagePokeLogKind, isUnread: Bool? = nil
    ) {
        self.id = id
        self.peerUserID = peerUserID
        self.peerName = peerName
        self.peerAvatarURL = peerAvatarURL
        self.createdAt = createdAt
        self.isMine = isMine
        self.kind = kind
        self.isUnread = isUnread
    }
}

// MARK: - 전선 모양

/// `message_history_with_pokes` 응답 행. **모든 칸이 옵셔널이고 칸마다 따로 읽는다**(머리 ①) —
/// 합성 디코더는 칸 하나의 타입이 틀려도 배열 전체를 throw 한다(MessageHistoryRow 가 적어 둔 그 사고).
package struct MessageHistoryWithPokesRow: Decodable, Equatable, Sendable {
    package var id: String?
    package var fromUser: String?
    package var toUser: String?
    package var body: String?
    package var createdAt: String?
    package var isMine: Bool?
    package var peerUserId: String?
    package var peerDisplayName: String?
    package var peerAvatarUrl: String?
    package var createdEpoch: Int?
    package var readByPeer: Bool?
    package var unread: Bool?
    /// 'message' | 'poke' | 'ultra'. 없으면 메시지로 읽는다.
    package var kind: String?

    package init(
        id: String? = nil, fromUser: String? = nil, toUser: String? = nil, body: String? = nil, createdAt: String? = nil,
        isMine: Bool? = nil, peerUserId: String? = nil, peerDisplayName: String? = nil, peerAvatarUrl: String? = nil,
        createdEpoch: Int? = nil, readByPeer: Bool? = nil, unread: Bool? = nil, kind: String? = nil
    ) {
        self.id = id
        self.fromUser = fromUser
        self.toUser = toUser
        self.body = body
        self.createdAt = createdAt
        self.isMine = isMine
        self.peerUserId = peerUserId
        self.peerDisplayName = peerDisplayName
        self.peerAvatarUrl = peerAvatarUrl
        self.createdEpoch = createdEpoch
        self.readByPeer = readByPeer
        self.unread = unread
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id, fromUser, toUser, body, createdAt, isMine, peerUserId, peerDisplayName, peerAvatarUrl
        case createdEpoch, readByPeer, unread, kind
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
        func flag(_ key: CodingKeys) -> Bool? { (try? c.decodeIfPresent(Bool.self, forKey: key)) ?? nil }
        id = text(.id)
        fromUser = text(.fromUser)
        toUser = text(.toUser)
        body = text(.body)
        createdAt = text(.createdAt)
        isMine = flag(.isMine)
        peerUserId = text(.peerUserId)
        peerDisplayName = text(.peerDisplayName)
        peerAvatarUrl = text(.peerAvatarUrl)
        // bigint 는 정수로 오지만 직렬화가 소수·문자열로 바뀌는 날에도 행을 버리지 않는다.
        if let whole = (try? c.decodeIfPresent(Int.self, forKey: .createdEpoch)) ?? nil {
            createdEpoch = whole
        } else if let real = (try? c.decodeIfPresent(Double.self, forKey: .createdEpoch)) ?? nil, real.isFinite {
            createdEpoch = Int(real.rounded())
        } else {
            createdEpoch = text(.createdEpoch).flatMap { Int($0) }
        }
        readByPeer = flag(.readByPeer)
        unread = flag(.unread)
        kind = text(.kind)
    }
}

/// 배열의 원소 하나가 깨져도(객체가 아님 등) 그 원소만 nil 로 접는 디코드 상자.
package struct MessagePokeLossyRow: Decodable, Sendable {
    package let row: MessageHistoryWithPokesRow?
    package init(from decoder: Decoder) throws {
        row = try? MessageHistoryWithPokesRow(from: decoder)
    }
}

/// 새 조회 한 번의 결과(옮긴 뒤). 두 배열 모두 **서버 순서 그대로**다.
package struct MessageHistoryWithPokes: Sendable {
    package let messages: [MessageHistoryEntry]
    package let pokes: [MessagePokeLogEntry]
    /// 행 id → 서버 시각 순위(0부터). 메시지와 찌르기가 **같은 초**일 때의 선후다(`created_epoch` 은 초 단위라 모른다).
    /// 서버 시각(`created_at`, 마이크로초)을 먼저 보고, 없으면 epoch, 같으면 응답 자리 순이다.
    package let chronology: [String: Int]

    package init(messages: [MessageHistoryEntry], pokes: [MessagePokeLogEntry], chronology: [String: Int]) {
        self.messages = messages
        self.pokes = pokes
        self.chronology = chronology
    }
}

/// 이력 조회 한 번의 결과(맥 스토어가 받는 모양). `pokes == nil` 이면 **서버가 찌르기 기록을 모른다**(옛 조회로 접었다).
package struct MessageConversationLoad: Sendable {
    package let history: MessageHistoryLoad
    package let pokes: [MessagePokeLogEntry]?
    package let chronology: [String: Int]

    package init(history: MessageHistoryLoad, pokes: [MessagePokeLogEntry]?, chronology: [String: Int] = [:]) {
        self.history = history
        self.pokes = pokes
        self.chronology = chronology
    }
}

/// `mark_conversation_read(p_peer, p_through_message, p_through_poke)` 요청. nil 인 칸은 **키 자체를 싣지 않는다**(합성 인코더의
/// encodeIfPresent) — 서버 기본값 null 과 같은 뜻이고(그 갈래는 안 움직인다), PostgREST 는 두 키 집합 모두 같은 함수로 고른다.
package struct MessageConversationReadMarkRequest: Encodable, Equatable, Sendable {
    package let pPeer: String
    package let pThroughMessage: String?
    package let pThroughPoke: String?

    package init(pPeer: String, pThroughMessage: String?, pThroughPoke: String?) {
        self.pPeer = pPeer
        self.pThroughMessage = pThroughMessage
        self.pThroughPoke = pThroughPoke
    }
}

/// `mark_conversation_read` 응답. `{"status":"ok","advanced":bool,"unread":int,"poke_advanced":bool,"poke_unread":int}` ·
/// unauthorized · invalid. 칸은 전부 옵셔널이다(키 하나로 디코드가 죽으면 성공한 읽음이 실패로 정산된다).
package struct MessageConversationReadMarkResponse: Decodable, Equatable, Sendable {
    package let status: String?
    package let advanced: Bool?
    package let unread: Int?
    package let pokeAdvanced: Bool?
    package let pokeUnread: Int?

    package var isOK: Bool { status == "ok" }
}

// MARK: - 서비스

extension SupabaseWorkService {
    package nonisolated static let messageHistoryWithPokesPath = "/rest/v1/rpc/message_history_with_pokes"

    /// 메시지 + 찌르기 기록 한 번(조회 박자당 왕복 1회 — `message_history_with_reads` 를 **대신** 부른다).
    /// 함수가 없는 서버는 404/PGRST202 를 던진다 — 폴백 판단은 스토어 몫이다(`fetchMessageHistoryWithReads` 와 같은 규약).
    package func fetchMessageHistoryWithPokes(
        accessToken: String,
        hours: Int,
        limit: Int
    ) async throws -> MessageHistoryWithPokes {
        let data = try await send(
            path: Self.messageHistoryWithPokesPath,
            method: "POST",
            body: MessageHistoryRequest(pHours: min(24, max(1, hours)), pLimit: min(500, max(1, limit))),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([MessagePokeLossyRow].self, from: data).compactMap(\.row)
        return messageHistoryWithPokes(fromRows: rows)
    }

    /// 행 → 메시지 · 찌르기(순수 — 테스트가 같은 행을 바로 흘린다). 메시지 옮김은 `messageHistoryEntry(fromReadsRow:)` **그대로**다.
    package func messageHistoryWithPokes(fromRows rows: [MessageHistoryWithPokesRow]) -> MessageHistoryWithPokes {
        var messages: [MessageHistoryEntry] = []
        var pokes: [MessagePokeLogEntry] = []
        var stamps: [(id: String, micros: Int64?, index: Int)] = []
        for (index, row) in rows.enumerated() {
            let kind = row.kind?.trimmingCharacters(in: .whitespaces)
            if kind == nil || kind == "message" {
                let readsRow = MessageHistoryReadsRow(
                    id: row.id, fromUser: row.fromUser, toUser: row.toUser, body: row.body, createdAt: row.createdAt,
                    isMine: row.isMine, peerUserId: row.peerUserId, peerDisplayName: row.peerDisplayName,
                    peerAvatarUrl: row.peerAvatarUrl, createdEpoch: row.createdEpoch, readByPeer: row.readByPeer, unread: row.unread
                )
                guard let entry = messageHistoryEntry(fromReadsRow: readsRow) else { continue }
                messages.append(entry)
                stamps.append((entry.id, Self.serverMicros(row, parse: parseDate), index))
            } else if let pokeKind = MessagePokeLogKind(serverKind: kind), let entry = pokeLogEntry(from: row, kind: pokeKind) {
                pokes.append(entry)
                stamps.append((entry.id, Self.serverMicros(row, parse: parseDate), index))
            }
            // 모르는 종류는 버린다(머리 ①).
        }
        let ranked = stamps.sorted { lhs, rhs in
            switch (lhs.micros, rhs.micros) {
            case let (l?, r?) where l != r: return l < r
            default: return lhs.index < rhs.index
            }
        }
        var chronology: [String: Int] = [:]
        for (rank, stamp) in ranked.enumerated() where chronology[stamp.id] == nil { chronology[stamp.id] = rank }
        return MessageHistoryWithPokes(messages: messages, pokes: pokes, chronology: chronology)
    }

    /// 찌르기 행 → 기록 한 건. 상대 · id · 시각이 없으면 버린다(어느 대화에 끼울지 모른다).
    private func pokeLogEntry(from row: MessageHistoryWithPokesRow, kind: MessagePokeLogKind) -> MessagePokeLogEntry? {
        guard let id = row.id, !id.isEmpty, let peer = row.peerUserId, !peer.isEmpty,
              let createdAt = row.createdEpoch.map({ Date(timeIntervalSince1970: TimeInterval($0)) })
                ?? row.createdAt.flatMap({ parseDate($0) })
        else { return nil }
        let isMine = row.isMine ?? false
        return MessagePokeLogEntry(
            id: id,
            peerUserID: peer,
            peerName: row.peerDisplayName.flatMap { $0.isEmpty ? nil : $0 } ?? "사용자",
            peerAvatarURL: row.peerAvatarUrl.flatMap { URL(string: $0) },
            createdAt: createdAt,
            isMine: isMine,
            kind: kind,
            // 받은 찌르기에만 싣는다(메시지의 `isUnread` 와 같은 규약 — 서버가 반대쪽에 값을 실어도 버린다).
            isUnread: isMine ? nil : row.unread
        )
    }

    /// 행의 서버 시각(마이크로초 epoch). `created_at` 이 정본이고, 못 읽으면 `created_epoch`(초)로 접는다.
    private static func serverMicros(_ row: MessageHistoryWithPokesRow, parse: (String) -> Date?) -> Int64? {
        if let text = row.createdAt, let micros = MessagePokeLogRules.microsecondsSinceEpoch(text, wholeSeconds: parse) {
            return micros
        }
        return row.createdEpoch.map { Int64($0) * 1_000_000 }
    }

    package nonisolated static let markConversationReadPath = "/rest/v1/rpc/mark_conversation_read"

    /// 대화를 읽음으로 올린다 — 메시지 경계 + **찌르기 경계**(v0.3.65). nil 인 경계는 싣지 않는다(서버가 그 갈래를 안 움직인다).
    /// 함수가 없는 서버는 404/PGRST202 를 던진다 — 폴백(메시지만 옛 함수로)은 스토어 몫이다.
    package func markConversationRead(
        accessToken: String,
        peerUserID: String,
        throughMessageID: String?,
        throughPokeID: String?
    ) async throws -> MessageConversationReadMarkResponse {
        let data = try await send(
            path: Self.markConversationReadPath,
            method: "POST",
            body: MessageConversationReadMarkRequest(
                pPeer: peerUserID, pThroughMessage: throughMessageID, pThroughPoke: throughPokeID
            ),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(MessageConversationReadMarkResponse.self, from: data)
    }
}

// MARK: - 규칙 (순수)

package enum MessagePokeLogRules {
    /// `"2026-10-23T01:02:03.123456+00:00"` → 마이크로초 epoch. 소수부는 **직접** 읽는다(ISO 포매터는 밀리초에서 자른다 —
    /// 같은 밀리초 안의 메시지·찌르기는 그 포매터로 못 가른다). 초 부분은 주입한 파서(서비스의 `parseDate`)가 읽는다.
    package static func microsecondsSinceEpoch(_ text: String, wholeSeconds: (String) -> Date?) -> Int64? {
        guard let tee = text.firstIndex(of: "T") else { return nil }
        var base = text
        var fraction = ""
        if let dot = text[tee...].firstIndex(of: ".") {
            let afterDot = text.index(after: dot)
            let digitsEnd = text[afterDot...].firstIndex(where: { !$0.isASCII || !$0.isNumber }) ?? text.endIndex
            fraction = String(text[afterDot..<digitsEnd])
            base = String(text[..<dot]) + String(text[digitsEnd...])
        }
        guard let date = wholeSeconds(base) else { return nil }
        let padded = (fraction + "000000").prefix(6)
        let micros = Int64(padded) ?? 0
        return Int64(date.timeIntervalSince1970.rounded()) * 1_000_000 + micros
    }

    /// 선후 판정의 순서표: 서버 순서 + **서버 순서가 모르는 id**(take_pokes 로 받아 바로 넣은 찌르기)를 그 뒤에 기록 자리 순으로.
    /// `MessageUnreadRules.effectiveOrder` 와 같은 규칙이다(그쪽은 메시지 타입을 받아 여기서 따로 둔다).
    package static func effectiveOrder(log: [MessagePokeLogEntry], serverOrder: [String: Int]) -> [String: Int] {
        guard log.contains(where: { serverOrder[$0.id] == nil }) else { return serverOrder }
        var order = serverOrder
        var next = (serverOrder.values.max() ?? -1) + 1
        for entry in log where order[entry.id] == nil {
            order[entry.id] = next
            next += 1
        }
        return order
    }

    /// 받은 찌르기가 낙관 읽음 경계 **안쪽**(경계 자신 포함)인가. 경계·그 찌르기를 순서표에서 못 찾으면 덮이지 않았다.
    package static func isCovered(_ entry: MessagePokeLogEntry, by record: MessageOptimisticRead, order: [String: Int]) -> Bool {
        if entry.id == record.throughID { return true }
        guard let through = order[record.throughID], let index = order[entry.id] else { return false }
        return index <= through
    }

    /// 안 본 찌르기가 있는 상대들. 서버 플래그(`isUnread == true`)에서 **그 스냅샷이 모르는 낙관 읽음**을 뺀다
    /// (`MessageUnreadRules.unreadPeerIDs` 의 이력 갈래와 같은 규칙 — 찌르기에는 요약 RPC 가 없다).
    package static func unreadPeerIDs(
        log: [MessagePokeLogEntry],
        snapshot: MessageHistoryReadSnapshot,
        optimistic: [String: MessageOptimisticRead]
    ) -> Set<String> {
        let order = effectiveOrder(log: log, serverOrder: snapshot.serverOrder)
        var peers: Set<String> = []
        for entry in log where !entry.isMine && entry.isUnread == true {
            if let record = optimistic[entry.peerUserID], !record.isKnown(bySnapshotSerial: snapshot.serial),
               isCovered(entry, by: record, order: order) {
                continue
            }
            peers.insert(entry.peerUserID)
        }
        return peers
    }

    /// 찌르기 읽음 경계 = 그 대화의 **마지막 받은 찌르기 id**(서버 순서 기준 — 화면에 보인 마지막 것). 올릴 것이 없으면 nil.
    ///  · 서버 기준 안 본 받은 찌르기가 없으면 nil.
    ///  · 같은 경계로 이미 올렸거나 올리는 중이면 nil — 실패로 정산된 기록만 다시 올린다(`MessageUnreadRules.markTarget` 과 같다).
    package static func markTarget(
        peer: String,
        log: [MessagePokeLogEntry],
        snapshot: MessageHistoryReadSnapshot,
        optimistic: MessageOptimisticRead?
    ) -> String? {
        let received = log.enumerated().filter { $0.element.peerUserID == peer && !$0.element.isMine }
        guard received.contains(where: { $0.element.isUnread == true }) else { return nil }
        let order = effectiveOrder(log: log, serverOrder: snapshot.serverOrder)
        guard let last = received.max(by: { lhs, rhs in
            let l = order[lhs.element.id] ?? -1
            let r = order[rhs.element.id] ?? -1
            return l != r ? l < r : lhs.offset < rhs.offset
        })?.element else { return nil }
        if let optimistic, optimistic.throughID == last.id, !optimistic.failed { return nil }
        return last.id
    }

    /// 기록을 표시 순서로(오래된 것 → 최신): 초 → 서버 시각 순위 → 도착 순서 → id.
    package static func sorted(
        _ log: [MessagePokeLogEntry],
        chronology: [String: Int],
        arrivalOrder: [String: Int] = [:]
    ) -> [MessagePokeLogEntry] {
        log.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            let l = chronology[lhs.id] ?? Int.max
            let r = chronology[rhs.id] ?? Int.max
            if l != r { return l < r }
            let la = arrivalOrder[lhs.id] ?? -1
            let ra = arrivalOrder[rhs.id] ?? -1
            if la != ra { return la < ra }
            return lhs.id < rhs.id
        }
    }
}

// MARK: - 대화 줄 (메시지 사이에 찌르기 끼워 넣기)

/// 대화 화면 한 줄(v0.3.65). `MessageTimelineItem` 에 찌르기 줄을 더한 모양이다 — 그 열거형은 폰 화면이 망라 switch 로 읽어서
/// 케이스를 더하면 폰이 깨진다(이 판은 폰을 안 고친다). 찌르기가 없으면 `MessageThreadBuilder.timeline` 과 **줄 단위로 같다**.
package enum MessageConversationLine: Identifiable, Equatable {
    case day(key: String, label: String)
    case bubble(MessageHistoryEntry)
    case poke(MessagePokeLogEntry)

    package var id: String {
        switch self {
        case .day(let key, _): return "day-\(key)"
        case .bubble(let entry): return entry.id
        case .poke(let entry): return "poke-\(entry.id)"
        }
    }

    /// 스크롤 따라가기의 "마지막 줄이 내 것인가".
    package var isMine: Bool {
        switch self {
        case .day: return false
        case .bubble(let entry): return entry.isMine
        case .poke(let entry): return entry.isMine
        }
    }
}

package enum MessageConversationTimeline {
    /// 시간순 메시지(이미 대화 순서) 사이에 시간순 찌르기를 **끼워 넣고** 날짜 구분선을 세운다.
    ///
    /// 메시지끼리 · 찌르기끼리의 순서는 **건드리지 않는다**(안정 병합) — 메시지 순서는 이미 같은 초 동률까지 깨진 대화 순서다.
    /// 병합이 정하는 것은 둘 사이의 끼움 자리뿐이다: 초가 다르면 초, 같은 초면 서버 시각 순위(`chronology`), 순위를 모르는 쪽
    /// (서버가 아직 모르는 즉시 삽입분)은 아는 쪽 **뒤**, 둘 다 모르면 메시지가 먼저다(결정성).
    package static func lines(
        messages: [MessageHistoryEntry],
        pokes: [MessagePokeLogEntry],
        chronology: [String: Int] = [:],
        now: Date,
        calendar: Calendar = .current
    ) -> [MessageConversationLine] {
        var merged: [MessageConversationLine] = []
        merged.reserveCapacity(messages.count + pokes.count)
        var m = 0
        var p = 0
        while m < messages.count || p < pokes.count {
            if p < pokes.count, m >= messages.count || pokeGoesFirst(pokes[p], before: messages[m], chronology: chronology) {
                merged.append(.poke(pokes[p]))
                p += 1
            } else {
                merged.append(.bubble(messages[m]))
                m += 1
            }
        }
        var lines: [MessageConversationLine] = []
        var lastKey: String?
        for line in merged {
            let date: Date
            switch line {
            case .bubble(let entry): date = entry.createdAt
            case .poke(let entry): date = entry.createdAt
            case .day: continue
            }
            let key = MessageThreadBuilder.dayKey(date, calendar: calendar)
            if key != lastKey {
                lines.append(.day(key: key, label: MessageThreadBuilder.dayLabel(date, now: now, calendar: calendar)))
                lastKey = key
            }
            lines.append(line)
        }
        return lines
    }

    private static func pokeGoesFirst(
        _ poke: MessagePokeLogEntry, before message: MessageHistoryEntry, chronology: [String: Int]
    ) -> Bool {
        if poke.createdAt != message.createdAt { return poke.createdAt < message.createdAt }
        switch (chronology[poke.id], chronology[message.id]) {
        case let (p?, m?): return p < m
        case (.some, nil): return true
        default: return false
        }
    }
}

// MARK: - 문구

/// 찌르기 줄의 글자(v0.3.65). 말투는 캐릭터 말풍선("○○님이 콕 찔렀어요!")을 따르고, 시각은 말풍선 옆 시각과 **같은 눈금**
/// (`MessageThreadBuilder.clockText` — 24시간제, 대화 안에서 두 시계가 다른 모양이면 같은 시각을 다르게 읽는다)이다.
package enum MessagePokeLogText {
    /// 아이콘 — 레일 [콕] 손가락과 울트라 번개를 그대로 쓴다.
    package static func symbol(_ kind: MessagePokeLogKind) -> String {
        switch kind {
        case .poke: return "hand.point.right.fill"
        case .ultra: return "bolt.fill"
        }
    }

    /// 주어("○○님이" / "내가"). 이름이 길면 이 부분만 줄인다(시각은 언제나 보인다).
    package static func subject(for entry: MessagePokeLogEntry) -> String {
        entry.isMine ? "내가" : "\(entry.peerName)님이"
    }

    /// 술어 + 시각("콕 찔렀어요 · 15:12").
    package static func predicate(for entry: MessagePokeLogEntry, calendar: Calendar = .current) -> String {
        let verb = entry.kind == .ultra ? "울트라 찔렀어요" : "콕 찔렀어요"
        return "\(verb) · \(MessageThreadBuilder.clockText(entry.createdAt, calendar: calendar))"
    }

    /// 한 줄 전체(보이스오버 · 시험).
    package static func line(for entry: MessagePokeLogEntry, calendar: Calendar = .current) -> String {
        "\(subject(for: entry)) \(predicate(for: entry, calendar: calendar))"
    }
}
