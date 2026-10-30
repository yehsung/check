import Foundation

// 아잉 큐브(rummy) RPC 의 와이어 타입(요청·응답)과 서비스 호출 12개 — `/rest/v1/rpc/rummy_*`.
// 계약의 정본은 설계서 §3.4·§3.5·§3.7 이고, 서버 갈래(S)가 같은 계약으로 SQL(20261103120000_rummy.sql)을 쓴다.
// **키 이름을 바꾸지 마라** — 디코더가 snake_case → camelCase 로 접으므로 `public_rooms` 는 `publicRooms` 다.
//
// ── 테트리스 와이어(TetrisWire.swift)의 규약을 그대로 베낀다 ──
//  ① **status 와 행의 id 만 필수이고 나머지는 전부 Optional 이다.** 비옵셔널 한 칸이면 서버가 키를 늘리기 전·db push 전
//     창에서 디코드가 통째로 throw 해 창이 죽는다. nil 은 "모른다" 다.
//     (테트리스와 달리 id 를 필수로 둔 이유: 스토어가 와이어 모델을 화면에 **그대로** 내준다(§4.3 `lobby`·`match`·
//     `incomingInvites`) — 화면의 ForEach·[참가]·[초대] 가 id 를 바로 쓴다. 서버는 기본 키에서 싣으므로 빠질 일이 없다.)
//  ② **모르는 status·상태 글자는 `.unknown` 으로 접는다**(`RummyRPCStatus` · `RummyMatchStatus` · `RummySeatState` ·
//     `RummyEndReason` · 판정 이유 `RummyTurnReason`). 문구 표는 스토어의 `RummyNoticeText` 한 곳.
//  ③ 시각은 전부 epoch **밀리초**이고 `Double` 로 읽는다. 기기 시계 보정은 스토어 몫이다.
//  ④ 요청 본문은 **빈 `{}` 가 아니다** — `p_protocol` 을 언제나 싣는다(PostgREST 는 본문의 키 집합으로 함수를 고른다).
//  ⑤ 면은 문자열(`"A7"`·`"J"`)이고 `RummyFace` 로 디코드한다(`[RummyFace]` · `[[RummyFace]]`). 타일 정수 id 는 없다.
//
// ── 테트리스와 같은 자리 ──
//  · 상태는 `{status, state}` 봉투의 **`state` 키**에 들어온다(펼치지 않는다).
//  · 사람 행의 id 키는 `id` 다(로비 users · 순위 rows · 방장 host). 자리 행만 `user_id` 다(§3.5 ROOM.seats · §3.7 seats).
//
// ── 테트리스와 다른 자리 ──
//  · 비로그인은 `not_signed_in` 이 아니라 **`unauthorized`** 다(§3.4 공통 머리).
//  · 요청 본문의 uuid 는 **소문자 문자열**로 싣는다(서비스 함수가 `UUID` 를 받아 접는다).

/// 아잉 큐브 RPC 프로토콜 버전과 이름. 서버 `rummy_protocol()` 이 1 이고, 이보다 **작으면** `unsupported_client` 다.
package enum RummyWire {
    package static let protocolVersion = 1

    /// RPC 이름(§3.4). 서버 함수 이름 그대로다 — 바꾸지 마라.
    package enum RPC {
        package static let lobby = "rummy_lobby"
        package static let create = "rummy_create"
        package static let invite = "rummy_invite"
        package static let join = "rummy_join"
        package static let decline = "rummy_decline"
        package static let leave = "rummy_leave"
        package static let start = "rummy_start"
        package static let state = "rummy_state"
        package static let draft = "rummy_draft"
        package static let play = "rummy_play"
        package static let draw = "rummy_draw"
        package static let ranking = "rummy_ranking"

        package static let all: [String] = [
            lobby, create, invite, join, decline, leave, start, state, draft, play, draw, ranking,
        ]

        // ── v2(설계서 v2 §1.2·§1.3, 마이그레이션 `20261104120000_rummy_v2.sql`) ──
        /// 하트비트(자리 있는 사람만). → `{status, server_now_ms}`.
        package static let heartbeat = "rummy_heartbeat"
        /// 이모티콘 반응. → `ok` · `invalid` · `too_fast` · `not_found`.
        package static let react = "rummy_react"
        /// v2 에서 새로 생긴 RPC. `all` 은 v1 마이그레이션 계약 시험이 대는 12개라 아직 넣지 않았다 —
        /// v2 마이그레이션이 합류하면(통합 갈래) `all` 로 합치고 계약 시험의 마이그레이션 이름을 늘린다.
        package static let v2Added: [String] = [heartbeat, react]
        package static let allV2: [String] = all + v2Added
    }
}

/// 아잉 큐브 RPC 의 status 어휘(§3.4). **모르는 값은 `.unknown`** 이다(머리말 ②).
package enum RummyRPCStatus: String, Equatable, Hashable, Sendable, Codable {
    case ok
    case unauthorized
    case unsupportedClient = "unsupported_client"
    case invalid
    case busy
    case alreadyInRoom = "already_in_room"
    case insufficient
    case notHost = "not_host"
    case blackout
    case targetFocused = "target_focused"
    case targetOutdated = "target_outdated"
    case targetBusy = "target_busy"
    case roomFull = "room_full"
    case tooManyInvites = "too_many_invites"
    case alreadyInvited = "already_invited"
    case roomClosed = "room_closed"
    case notInvited = "not_invited"
    case notEnoughPlayers = "not_enough_players"
    /// 시작 검사에서 빠진 자리가 있다(`dropped:[uuid]`). 커밋됐고 시작은 안 했다.
    case seatsDropped = "seats_dropped"
    case notFound = "not_found"
    case notYourTurn = "not_your_turn"
    /// `p_expected_seq ≠ seq`. 쓰지 않았고 `state` 가 실려 온다 — 클라는 그 상태로 맞추면 된다.
    case stale
    case malformed
    /// v2 `rummy_react` 쿨다운(같은 사람 2초).
    case tooFast = "too_fast"
    /// play 판정 거절(`reason` · `state`). 벌칙 없음.
    case rejected
    case notActive = "not_active"
    case unknown

    package init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RummyRPCStatus(rawValue: raw) ?? .unknown
    }
}

/// 판(방) status(§3.1). 모르는 값은 `.unknown`.
package enum RummyMatchStatus: String, Equatable, Hashable, Sendable, Codable {
    case forming, active, finished, cancelled, expired, unknown

    package init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RummyMatchStatus(rawValue: raw) ?? .unknown
    }
}

/// 자리 state(§3.1). 모르는 값은 `.unknown`.
package enum RummySeatState: String, Equatable, Hashable, Sendable, Codable {
    case invited, joined, declined, left, dropped, playing, forfeit, done, unknown

    package init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RummySeatState(rawValue: raw) ?? .unknown
    }
}

/// 끝난 이유(§3.1 `end_reason`). 모르는 값은 `.unknown`.
package enum RummyEndReason: String, Equatable, Hashable, Sendable, Codable {
    case rackEmpty = "rack_empty"
    case blocked
    case lastStanding = "last_standing"
    case unknown

    package init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RummyEndReason(rawValue: raw) ?? .unknown
    }
}

// MARK: - 요청 본문(키 = 서버 인자 이름. 인코더가 camelCase → snake_case 로 편다)

/// rummy_lobby / rummy_ranking 본문. { p_protocol }.
package struct RummyProtocolRequest: Encodable, Equatable, Sendable {
    package var pProtocol = RummyWire.protocolVersion

    package init() {}
}

/// rummy_create 본문. { p_protocol, p_stake, p_public }.
package struct RummyCreateRequest: Encodable, Equatable, Sendable {
    package var pProtocol = RummyWire.protocolVersion
    package let pStake: Int
    package let pPublic: Bool

    package init(stake: Int, isPublic: Bool) {
        pStake = stake
        pPublic = isPublic
    }
}

/// rummy_invite 본문. { p_protocol, p_match_id, p_user }.
package struct RummyInviteRequest: Encodable, Equatable, Sendable {
    package var pProtocol = RummyWire.protocolVersion
    package let pMatchId: String
    package let pUser: String

    package init(matchID: UUID, userID: UUID) {
        pMatchId = matchID.uuidString.lowercased()
        pUser = userID.uuidString.lowercased()
    }
}

/// rummy_join / rummy_decline / rummy_leave / rummy_start / rummy_state 본문. { p_protocol, p_match_id }.
package struct RummyMatchRequest: Encodable, Equatable, Sendable {
    package var pProtocol = RummyWire.protocolVersion
    package let pMatchId: String

    package init(matchID: UUID) {
        pMatchId = matchID.uuidString.lowercased()
    }
}

/// rummy_draw 본문. { p_protocol, p_match_id, p_expected_seq }.
package struct RummySeqRequest: Encodable, Equatable, Sendable {
    package var pProtocol = RummyWire.protocolVersion
    package let pMatchId: String
    package let pExpectedSeq: Int

    package init(matchID: UUID, expectedSeq: Int) {
        pMatchId = matchID.uuidString.lowercased()
        pExpectedSeq = expectedSeq
    }
}

/// rummy_draft / rummy_play 본문. { p_protocol, p_match_id, p_expected_seq, p_table[, p_layout] }. `p_table` 은 면 문자열 배열의 배열.
/// v2: `p_layout` = 묶음마다 `[x, y]`(`RummyLayout`). nil 이면 **키를 싣지 않는다**(서버 `default null` — v1 본문과 같은 키 집합).
package struct RummyTableRequest: Encodable, Equatable, Sendable {
    package var pProtocol = RummyWire.protocolVersion
    package let pMatchId: String
    package let pExpectedSeq: Int
    package let pTable: [[RummyFace]]
    package let pLayout: RummyLayout?

    package init(matchID: UUID, expectedSeq: Int, table: [[RummyFace]], layout: RummyLayout? = nil) {
        pMatchId = matchID.uuidString.lowercased()
        pExpectedSeq = expectedSeq
        pTable = table
        pLayout = layout
    }
}

/// v2 rummy_react 본문. { p_protocol, p_match_id, p_key }. `p_key` = `AingSticker.rawValue`.
package struct RummyReactRequest: Encodable, Equatable, Sendable {
    package var pProtocol = RummyWire.protocolVersion
    package let pMatchId: String
    package let pKey: String

    package init(matchID: UUID, key: String) {
        pMatchId = matchID.uuidString.lowercased()
        pKey = key
    }
}

// MARK: - 로비(§3.5)

/// 이름 정도만 실린 사람(ROOM.host).
package struct RummyPeer: Codable, Equatable, Hashable, Sendable, Identifiable {
    package let id: UUID
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
}

/// ROOM.seats 한 칸. 초대받은 자리는 `seat_no` 가 null 이다.
package struct RummyRoomSeat: Codable, Equatable, Hashable, Sendable, Identifiable {
    package let userId: UUID
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    /// 'joined' | 'invited'.
    package var state: RummySeatState?
    package var seatNo: Int?

    package var id: UUID { userId }
}

/// §3.5 ROOM — 받은 초대 · 공개 방 · 내 방이 같은 모양이다.
package struct RummyRoom: Codable, Equatable, Hashable, Sendable, Identifiable {
    package let id: UUID
    package var host: RummyPeer?
    package var stake: Int?
    package var isPublic: Bool?
    package var expiresAtMs: Double?
    package var maxSeats: Int?
    package var seats: [RummyRoomSeat]?
}

/// 로비 `users[]` 한 줄. `capable` 이 nil 이면 **불가**로 읽는다(테트리스와 같다).
package struct RummyLobbyUser: Codable, Equatable, Hashable, Sendable, Identifiable {
    package let id: UUID
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    package var isWorking: Bool?
    /// 오목·체스·테트리스·아잉 큐브 중 하나라도 진행 중(서버 `chess__busy`).
    package var inMatch: Bool?
    /// 서버 `rummy_capable`.
    package var capable: Bool?
    package var focusMode: Bool?
}

/// 로비 `me`.
package struct RummyLobbyMe: Codable, Equatable, Sendable {
    package var rubyBalance: Int?
    package var games: Int?
    package var wins: Int?
    /// 내가 joined 인 forming 방(없으면 null).
    package var room: RummyRoom?
    /// 내가 playing 인 active 판.
    package var activeMatchId: UUID?
}

/// rummy_lobby 응답.
package struct RummyLobby: Codable, Equatable, Sendable {
    package let status: RummyRPCStatus
    package var serverNowMs: Double?
    package var stakes: [Int]?
    package var turnSeconds: Int?
    package var roomTtlSeconds: Int?
    package var me: RummyLobbyMe?
    /// 내가 invited 인 forming 방(만료 전), 최근 순 20.
    package var invites: [RummyRoom]?
    /// 빈자리 있는 공개 방, 최근 순 20.
    package var publicRooms: [RummyRoom]?
    package var users: [RummyLobbyUser]?
}

// MARK: - 판 상태(§3.7)

/// state.seats 한 칸. `final_*`·`final_rack` 은 finished 에서만 차고 그 전엔 null.
package struct RummyMatchSeat: Codable, Equatable, Hashable, Sendable, Identifiable {
    package var seatNo: Int?
    package let userId: UUID
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    package var state: RummySeatState?
    package var rackCount: Int?
    package var initialDone: Bool?
    package var timeoutStreak: Int?
    package var forfeitOrder: Int?
    package var finalRank: Int?
    package var finalScore: Int?
    package var payout: Int?
    package var isWinner: Bool?
    package var finalRack: [RummyFace]?

    package var id: UUID { userId }
}

/// 이번 차례 작업 판(공개).
package struct RummyDraft: Codable, Equatable, Hashable, Sendable {
    package var table: [[RummyFace]]?
    /// v2: 작업 판 배치(`[[x,y]|null]`, 묶음 수와 길이가 다르면 전부 null 로 읽는다 — `RummyTableLayout.sanitize`).
    package var layout: RummyLayout?
    package var draftSeq: Int?
    package var atMs: Double?
}

/// v2 `state.reactions[]` 한 칸(최근 10초, 최신 순, 최대 12). `key` 는 글자 그대로 — `sticker` 가 모르는 키면 nil(버린다).
package struct RummyReaction: Codable, Equatable, Hashable, Sendable {
    package var seatNo: Int?
    package var key: String?
    package var atMs: Double?

    package var sticker: AingSticker? { key.flatMap(AingSticker.init(rawValue:)) }
}

/// 마지막 확정 사건. `kind` = 'start' | 'play' | 'draw' | 'pass' | 'timeout_play' | 'timeout_penalty' | 'timeout_draw' |
/// 'forfeit' | 'finish'(서버 moves.kind 그대로 — 글자로 둔다).
package struct RummyLastEvent: Codable, Equatable, Hashable, Sendable {
    package var kind: String?
    package var seatNo: Int?
    package var count: Int?
    package var atMs: Double?
}

/// §3.7 state. forming 방도 같은 모양(table 빈 배열, 랙 null). **남의 랙·pool 내용은 실리지 않는다.**
package struct RummyMatchState: Codable, Equatable, Sendable, Identifiable {
    package let id: UUID
    package var status: RummyMatchStatus?
    package var hostId: UUID?
    package var stake: Int?
    package var isPublic: Bool?
    package var seatCount: Int?
    package var maxSeats: Int?
    package var serverNowMs: Double?
    package var seq: Int?
    /// forming 일 때만.
    package var expiresAtMs: Double?
    package var seats: [RummyMatchSeat]?
    package var mySeatNo: Int?
    /// 내가 playing 일 때만 내 랙.
    package var myRack: [RummyFace]?
    package var myInitialDone: Bool?
    package var table: [[RummyFace]]?
    /// v2: 확정 판 배치(`[[x,y]|null]|null`). 빈 자리는 `RummyTableLayout.place` 가 모든 기기에서 같게 채운다.
    package var tableLayout: RummyLayout?
    package var poolCount: Int?
    package var turnSeatNo: Int?
    package var turnStartedMs: Double?
    package var turnDeadlineMs: Double?
    /// 마감 뒤 유예(2000).
    package var graceMs: Double?
    package var draft: RummyDraft?
    package var consecutivePasses: Int?
    package var lastEvent: RummyLastEvent?
    package var endReason: RummyEndReason?
    package var finishedAtMs: Double?
    /// v2: 최근 10초 이모티콘 반응(최신 순, 최대 12).
    package var reactions: [RummyReaction]?
}

/// 쓰기·조회 공용 응답(create · invite · join · decline · leave · start · state · draft · play · draw).
/// 상태는 **`state` 키**에 실려 온다. 거절 응답에도 가능하면 `state` 가 실린다(§3.4 끝).
package struct RummyActionResponse: Codable, Equatable, Sendable {
    package let status: RummyRPCStatus
    package var state: RummyMatchState?
    /// create ok.
    package var matchId: UUID?
    /// draft ok.
    package var draftSeq: Int?
    /// play rejected — R-16 판정 이유.
    package var reason: RummyTurnReason?
    /// start seats_dropped — 빠진 사람들.
    package var dropped: [UUID]?
    /// insufficient — 'me'.
    package var side: String?
    package var need: Int?
    package var have: Int?
    /// invalid — 서버가 받는 판돈 집합.
    package var stakes: [Int]?
    package var rubyBalance: Int?
    package var serverNowMs: Double?
}

// MARK: - 순위

/// 순위표 한 줄. 순위·배열 순서 모두 **서버 것**이다(재정렬 금지).
package struct RummyRankRow: Codable, Equatable, Hashable, Sendable, Identifiable {
    package let id: UUID
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    package var games: Int?
    package var wins: Int?
    package var rank: Int?
}

/// 순위표의 `me`(0판이면 rank null).
package struct RummyRankingMe: Codable, Equatable, Sendable {
    package var games: Int?
    package var wins: Int?
    package var rank: Int?
}

/// rummy_ranking 응답.
package struct RummyRanking: Codable, Equatable, Sendable {
    package let status: RummyRPCStatus
    package var serverNowMs: Double?
    package var rows: [RummyRankRow]?
    package var me: RummyRankingMe?
}

// MARK: - 서비스 호출

/// 아잉 큐브 RPC 12개. 몸통은 공용 `duelRPC`(DuelRPC.swift) 하나다.
/// 교착 재시도는 **쓰기 전부 + 상태 조회**에 켠다(`rummy_state` 는 `rummy__catchup` 으로 시간 판정을 돌리고 지갑 잠금을 쥔다).
/// 로비·순위는 끈다(로비의 만료 방 정리는 실패해도 다음 계기가 다시 한다).
extension SupabaseWorkService {
    package func rummyLobby(accessToken: String) async throws -> RummyLobby {
        try await duelRPC(RummyWire.RPC.lobby, body: RummyProtocolRequest(), accessToken: accessToken)
    }

    package func rummyCreate(accessToken: String, stake: Int, isPublic: Bool) async throws -> RummyActionResponse {
        try await duelRPC(
            RummyWire.RPC.create, body: RummyCreateRequest(stake: stake, isPublic: isPublic),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func rummyInvite(accessToken: String, matchID: UUID, userID: UUID) async throws -> RummyActionResponse {
        try await duelRPC(
            RummyWire.RPC.invite, body: RummyInviteRequest(matchID: matchID, userID: userID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func rummyJoin(accessToken: String, matchID: UUID) async throws -> RummyActionResponse {
        try await duelRPC(
            RummyWire.RPC.join, body: RummyMatchRequest(matchID: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func rummyDecline(accessToken: String, matchID: UUID) async throws -> RummyActionResponse {
        try await duelRPC(
            RummyWire.RPC.decline, body: RummyMatchRequest(matchID: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    /// forming 이면 방 나가기(방장이면 방 닫기), active 면 기권.
    package func rummyLeave(accessToken: String, matchID: UUID) async throws -> RummyActionResponse {
        try await duelRPC(
            RummyWire.RPC.leave, body: RummyMatchRequest(matchID: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func rummyStart(accessToken: String, matchID: UUID) async throws -> RummyActionResponse {
        try await duelRPC(
            RummyWire.RPC.start, body: RummyMatchRequest(matchID: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    /// 상태(자리 있는 사람 전용). 읽기처럼 보이지만 서버가 시간 판정(`rummy__catchup`)을 돌려 판을 바꿀 수 있다.
    package func rummyState(accessToken: String, matchID: UUID) async throws -> RummyActionResponse {
        try await duelRPC(
            RummyWire.RPC.state, body: RummyMatchRequest(matchID: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    /// 작업 상태 전송(R-19). 차례인 사람만. v2: `layout` 을 주면 `p_layout` 으로 싣는다.
    package func rummyDraft(
        accessToken: String, matchID: UUID, expectedSeq: Int, table: [[RummyFace]], layout: RummyLayout? = nil
    ) async throws -> RummyActionResponse {
        try await duelRPC(
            RummyWire.RPC.draft,
            body: RummyTableRequest(matchID: matchID, expectedSeq: expectedSeq, table: table, layout: layout),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    /// 확정 내기(R-16 판정). 거절이면 `rejected{reason, state}`. v2: `layout` 을 주면 `p_layout` 으로 싣는다.
    package func rummyPlay(
        accessToken: String, matchID: UUID, expectedSeq: Int, table: [[RummyFace]], layout: RummyLayout? = nil
    ) async throws -> RummyActionResponse {
        try await duelRPC(
            RummyWire.RPC.play,
            body: RummyTableRequest(matchID: matchID, expectedSeq: expectedSeq, table: table, layout: layout),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    /// v2 하트비트(`rummy_seats.last_seen_at` 갱신). 자리 없는 사람은 `not_found`.
    package func rummyHeartbeat(accessToken: String, matchID: UUID) async throws -> RummyActionResponse {
        try await duelRPC(
            RummyWire.RPC.heartbeat, body: RummyMatchRequest(matchID: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    /// v2 이모티콘 반응. `key` = `AingSticker.rawValue`.
    package func rummyReact(accessToken: String, matchID: UUID, key: String) async throws -> RummyActionResponse {
        try await duelRPC(
            RummyWire.RPC.react, body: RummyReactRequest(matchID: matchID, key: key),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    /// 뽑기(더미가 비었으면 패스).
    package func rummyDraw(accessToken: String, matchID: UUID, expectedSeq: Int) async throws -> RummyActionResponse {
        try await duelRPC(
            RummyWire.RPC.draw, body: RummySeqRequest(matchID: matchID, expectedSeq: expectedSeq),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func rummyRanking(accessToken: String) async throws -> RummyRanking {
        try await duelRPC(RummyWire.RPC.ranking, body: RummyProtocolRequest(), accessToken: accessToken)
    }
}
