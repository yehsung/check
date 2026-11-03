import Foundation

// 아잉 마작(내부 이름 mahjong) 4인 RPC 의 와이어 타입(요청·응답)과 서비스 호출 13개 — `/rest/v1/rpc/mahjong_*`.
// 계약의 정본은 설계서 mj/SPEC.md §3.4(RPC·status) · §3.5(로비) · §3.6(state) · §4.4(이 파일)이고,
// 서버 갈래가 같은 계약으로 SQL(20261108221000_mahjong_table.sql)을 쓴다.
// **키 이름을 바꾸지 마라** — 디코더가 snake_case → camelCase 로 접으므로 `wake_at_ms` 는 `wakeAtMs` 다.
//
// ── 리버시·큐브 와이어의 규약을 그대로 따른다 ──
//  ① **status 만 필수이고 나머지는 전부 Optional 이다.** 비옵셔널 한 칸이면 서버가 키를 늘리기 전·db push 전 창에서
//     디코드가 통째로 throw 해 판 창이 죽는다. nil 은 "모른다" 다.
//  ② **모르는 status 는 `.unknown` 으로 접는다.** 새 status·응답 키는 프로토콜을 안 올린다(§3.4).
//  ③ 시각은 전부 epoch **밀리초** `Double`. 기기 시계 보정은 스토어 몫이다.
//  ④ 요청 본문은 **빈 `{}` 가 아니다** — `p_protocol` 을 언제나 싣는다(PostgREST 는 본문의 키 집합으로 함수를 고른다).
//  ⑤ 상태가 실리는 응답은 **`{status, state}` 봉투 하나**다. 거절 응답에도 판이 있으면 `state` 가 실린다.
//     쓰기 RPC 응답의 state 는 사건 꼬리 전체(최근 80, p_since 0)다 — 스토어는 `applyState(…, requestedSince: 0)`.
//
// ── 마작에서 정한 자리 ──
//  · 패 한 장은 **물리 패 번호 id(0~135)** 하나 = `MahjongTile`(D4). 종류(0~33)는 이름에 `kind` 가 든 칸만(§1·§8).
//  · **열린 어휘 칸은 모두 원문 `String`**(§4.1 끝 · CC-07 · D43): 판 status · phase · format · end_reason · 사건 kind ·
//    부로 type · hand_draw reason · limit · away reason · window_kind · 역 id. 엔진 타입은 계산 속성(`meld`·`yakuKind`·
//    `matchStatus` …)으로 잇고 모르는 값은 nil 이다 — 규칙 2판의 새 역 id 하나에 옛 맥의 판 화면이 통째로 멎지 않게.
//  · `my_decision` 의 모르는 kind 는 state 전체를 죽이지 않고 nil 로 접는다(`MahjongDecision` 은 규칙 표면 R 이 정의 —
//    감싸기는 이 파일 몫, MahjongRules.swift 머리말).
//  · `MahjongStatePayload` 는 **양방향**(`Codable`)이다 — 서버 디코드와 연습판 엔진(E)의 생성이 같은 타입(§4.2).
//  · 사람 행 id 키: 로비(PEER · users · 방 자리)는 **`id`**, state 의 자리 사람(USER)과 순위는 **`user_id`**.

/// 아잉 마작 RPC 프로토콜과 이름 묶음.
package nonisolated enum MahjongWire {
    /// 서버 `mahjong_protocol()` 이 1 이고, 이보다 **작으면** `unsupported_client` 다.
    package static let protocolVersion = 1

    /// 클라가 부르는 RPC 이름 전부(13). 계약 시험이 판 파일의 `to authenticated` 실행권 함수 집합과 이 목록을 잰다.
    package enum RPC: String, CaseIterable, Sendable {
        case lobby = "mahjong_lobby"
        case create = "mahjong_create"
        case invite = "mahjong_invite"
        case join = "mahjong_join"
        case decline = "mahjong_decline"
        case leave = "mahjong_leave"
        case start = "mahjong_start"
        case state = "mahjong_state"
        case act = "mahjong_act"
        case call = "mahjong_call"
        case back = "mahjong_back"
        case react = "mahjong_react"
        case ranking = "mahjong_ranking"

        package static let all: [String] = allCases.map(\.rawValue)

        /// 교착(40P01) 한 번 재시도 여부(§4.4). 쓰기 전부 + `mahjong_state`(서버가 따라잡기로 판을 바꾼다).
        /// 로비·반응·순위는 끈다 — 실패하면 다음 계기가 다시 읽는다.
        package var retriesDeadlockOnce: Bool {
            switch self {
            case .create, .invite, .join, .decline, .leave, .start, .state, .act, .call, .back: return true
            case .lobby, .react, .ranking: return false
            }
        }
    }
}

/// RPC status 어휘(§3.4 — 서버와 같은 집합, `too_early` 포함). **모르는 값은 `.unknown`** 이다(머리말 ②).
package nonisolated enum MahjongRPCStatus: String, Equatable, Hashable, Sendable, Decodable, CaseIterable {
    case ok
    case unauthorized
    case unsupportedClient = "unsupported_client"
    case invalid
    case blackout
    case targetFocused = "target_focused"
    case targetOutdated = "target_outdated"
    /// **내** 앱이 아잉 마작 문 밖이다(만들기 · 들어가기 · [시작]만 — 서버 `mahjong_capable` 거짓, 되돌리기 '문 닫기' 포함).
    /// 방·판은 안 생긴다. `unsupported_client`(프로토콜 — 가용성 `.updateRequired`)와 달리 안내줄 한 줄만 바꾼다(X1).
    case outdated
    case busy
    case targetBusy = "target_busy"
    case alreadyInRoom = "already_in_room"
    case alreadyInvited = "already_invited"
    case roomFull = "room_full"
    case tooManyInvites = "too_many_invites"
    case roomClosed = "room_closed"
    case notInvited = "not_invited"
    case notHost = "not_host"
    /// joined ≠ 4(DEC:9 — 사람 넷이 다 모여야 시작).
    case notEnoughPlayers = "not_enough_players"
    /// 시작 검사에서 빠진 멤버가 있다(`dropped` · `reasons{uid: unseen|outdated|insufficient}`). 커밋됐고 시작은 안 했다.
    case seatsDropped = "seats_dropped"
    case insufficient
    case notFound = "not_found"
    case notActive = "not_active"
    case notYourTurn = "not_your_turn"
    /// `p_expected_seq < decision_seq` — 지금 결정이 생기기 전의 화면에서 보낸 답. **문구 없이** 실려 온 state 로 맞춘다.
    case stale
    /// 저장된 선택지 밖(`reason` = not_option · not_in_hand). 판은 그대로이고 state 가 실려 온다.
    case illegal
    /// 울기 창이 이미 닫혔다(창 번호가 다르거나 내 선택지 창이 아니다 — 서버가 셋을 가르지 않는다, D12). **문구 없이** 내린다.
    case windowClosed = "window_closed"
    /// 반응 쿨다운 · [돌아왔어요] 쿨다운(`retry_ms`).
    case tooFast = "too_fast"
    /// 리치 중 버림이 `시작 + 멈춤` 전에 왔다(CS-08). 문구 없음 — 보조가 때를 맞춘다.
    case tooEarly = "too_early"
    case unknown

    package init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MahjongRPCStatus(rawValue: raw) ?? .unknown
    }
}

// MARK: - 요청 본문 (키 = 서버 인자 이름 — 인코더가 snake_case 로 편다)

/// mahjong_lobby / mahjong_ranking 본문. { p_protocol }.
package nonisolated struct MahjongProtocolRequest: Encodable, Equatable, Sendable {
    package var pProtocol = MahjongWire.protocolVersion
    package init() {}
}

/// mahjong_create 본문. { p_protocol, p_stake, p_public, p_format }. `p_format` 은 원문 글자("tonpuu"|"hanchan").
package nonisolated struct MahjongCreateRequest: Encodable, Equatable, Sendable {
    package var pProtocol = MahjongWire.protocolVersion
    package let pStake: Int
    package let pPublic: Bool
    package let pFormat: String

    package init(pStake: Int, pPublic: Bool, pFormat: String) {
        self.pStake = pStake
        self.pPublic = pPublic
        self.pFormat = pFormat
    }
}

/// mahjong_join / decline / leave / start / back 본문. { p_protocol, p_match_id }.
package nonisolated struct MahjongMatchRequest: Encodable, Equatable, Sendable {
    package var pProtocol = MahjongWire.protocolVersion
    package let pMatchId: String

    package init(pMatchId: String) {
        self.pMatchId = pMatchId
    }
}

/// mahjong_invite 본문. { p_protocol, p_match_id, p_user_id }.
package nonisolated struct MahjongInviteRequest: Encodable, Equatable, Sendable {
    package var pProtocol = MahjongWire.protocolVersion
    package let pMatchId: String
    package let pUserId: String

    package init(pMatchId: String, pUserId: String) {
        self.pMatchId = pMatchId
        self.pUserId = pUserId
    }
}

/// mahjong_state 본문. { p_protocol, p_match_id, p_since_seq }.
package nonisolated struct MahjongStateRequest: Encodable, Equatable, Sendable {
    package var pProtocol = MahjongWire.protocolVersion
    package let pMatchId: String
    package let pSinceSeq: Int

    package init(pMatchId: String, pSinceSeq: Int) {
        self.pMatchId = pMatchId
        self.pSinceSeq = pSinceSeq
    }
}

/// mahjong_act 본문. { p_protocol, p_match_id, p_expected_seq, p_action, p_tiles }.
/// `p_action` ∈ discard · riichi · tsumo · ankan · kakan · kyuushu. `p_tiles` 는 패 id 배열(쯔모·구종구패는 []) —
/// 서버는 null 인자를 `invalid` 로 받으므로 늘 배열을 싣는다. `p_expected_seq` 는 내 `my_decision.decision_seq`.
package nonisolated struct MahjongActRequest: Encodable, Equatable, Sendable {
    package var pProtocol = MahjongWire.protocolVersion
    package let pMatchId: String
    package let pExpectedSeq: Int
    package let pAction: String
    package let pTiles: [MahjongTile]

    package init(pMatchId: String, pExpectedSeq: Int, pAction: String, pTiles: [MahjongTile] = []) {
        self.pMatchId = pMatchId
        self.pExpectedSeq = pExpectedSeq
        self.pAction = pAction
        self.pTiles = pTiles
    }
}

/// mahjong_call 본문. { p_protocol, p_match_id, p_window_id, p_action, p_tiles }.
/// `p_action` ∈ ron · pon · minkan · chi · pass. `p_tiles` 는 손에서 낼 패 id(론·패스는 []).
package nonisolated struct MahjongCallRequest: Encodable, Equatable, Sendable {
    package var pProtocol = MahjongWire.protocolVersion
    package let pMatchId: String
    package let pWindowId: Int
    package let pAction: String
    package let pTiles: [MahjongTile]

    package init(pMatchId: String, pWindowId: Int, pAction: String, pTiles: [MahjongTile] = []) {
        self.pMatchId = pMatchId
        self.pWindowId = pWindowId
        self.pAction = pAction
        self.pTiles = pTiles
    }
}

/// mahjong_react 본문. { p_protocol, p_match_id, p_key }.
package nonisolated struct MahjongReactRequest: Encodable, Equatable, Sendable {
    package var pProtocol = MahjongWire.protocolVersion
    package let pMatchId: String
    package let pKey: String

    package init(pMatchId: String, pKey: String) {
        self.pMatchId = pMatchId
        self.pKey = pKey
    }
}

// MARK: - 응답 — 로비 (§3.5)

/// 이름 정도만 실린 사람(PEER — 방장 · 방 자리 · forming 멤버). id 키는 **`id`** 다.
package nonisolated struct MahjongPeer: Codable, Equatable, Hashable, Sendable {
    package var id: String?
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
}

/// 방 자리 한 줄 `{user: PEER, state: "invited"|"joined"}`(state 는 원문 글자).
package nonisolated struct MahjongRoomSeat: Codable, Equatable, Hashable, Sendable {
    package var user: MahjongPeer?
    package var state: String?

    package var isJoined: Bool { state == "joined" }
}

/// ROOM(§3.5) — 받은 초대 · 공개 방 · 내 방. id 는 서버 uuid.
package nonisolated struct MahjongRoom: Codable, Equatable, Hashable, Sendable, Identifiable {
    package let id: UUID
    package var host: MahjongPeer?
    package var stake: Int?
    /// 원문 글자("tonpuu"|"hanchan"). 엔진·화면 값은 `formatKind`.
    package var format: String?
    package var isPublic: Bool?
    package var expiresAtMs: Double?
    package var maxSeats: Int?
    package var seats: [MahjongRoomSeat]?

    package var formatKind: MahjongFormat? { format.flatMap(MahjongFormat.init(rawValue:)) }
    /// 앉은(joined) 사람 수.
    package var joinedCount: Int { seats?.filter(\.isJoined).count ?? 0 }
}

/// 로비 `users[]` 한 줄. `capable` 이 nil 이면 **불가**로 읽는다(스토어). `in_match` 는 서버 `lobby__others.busy`.
package nonisolated struct MahjongLobbyUser: Codable, Equatable, Hashable, Sendable, Identifiable {
    package let id: UUID
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    package var isWorking: Bool?
    package var inMatch: Bool?
    /// 서버 `mahjong_capable`.
    package var capable: Bool?
    package var focusMode: Bool?
}

/// 내 전적(`mahjong__record` — 순위표와 같은 함수). `avg_rank` 는 0판이면 null(v1.0.2).
package nonisolated struct MahjongRecord: Codable, Equatable, Hashable, Sendable {
    package var games: Int?
    package var firsts: Int?
    package var seconds: Int?
    package var thirds: Int?
    package var fourths: Int?
    package var avgRank: Double?
}

/// 로비 `me`.
package nonisolated struct MahjongLobbyMe: Codable, Equatable, Sendable {
    package var rubyBalance: Int?
    package var record: MahjongRecord?
    /// 내가 joined 인 forming 방(없으면 null).
    package var room: MahjongRoom?
    /// 내가 앉은 active 판(없으면 null).
    package var activeMatchId: String?
}

/// mahjong_lobby 응답(§3.5). 숫자 상수(판돈·형식·방 TTL·초대 상한·생각 시간)도 서버가 말한다 — 화면은 이 값을 읽는다.
package nonisolated struct MahjongLobbyResponse: Decodable, Equatable, Sendable {
    package let status: MahjongRPCStatus
    package var serverNowMs: Double?
    package var stakes: [Int]?
    /// 원문 글자 목록(["tonpuu","hanchan"]).
    package var formats: [String]?
    package var roomTtlSeconds: Int?
    package var maxInvites: Int?
    package var baseMs: Int?
    package var bankMs: Int?
    package var me: MahjongLobbyMe?
    /// 내가 invited 인 forming 방(만료 전, 최근 순 20).
    package var invites: [MahjongRoom]?
    /// 빈자리 있는 공개 방(최근 순 20).
    package var publicRooms: [MahjongRoom]?
    package var users: [MahjongLobbyUser]?

    package init(
        status: MahjongRPCStatus, serverNowMs: Double? = nil, stakes: [Int]? = nil, formats: [String]? = nil,
        roomTtlSeconds: Int? = nil, maxInvites: Int? = nil, baseMs: Int? = nil, bankMs: Int? = nil,
        me: MahjongLobbyMe? = nil, invites: [MahjongRoom]? = nil, publicRooms: [MahjongRoom]? = nil,
        users: [MahjongLobbyUser]? = nil
    ) {
        self.status = status
        self.serverNowMs = serverNowMs
        self.stakes = stakes
        self.formats = formats
        self.roomTtlSeconds = roomTtlSeconds
        self.maxInvites = maxInvites
        self.baseMs = baseMs
        self.bankMs = bankMs
        self.me = me
        self.invites = invites
        self.publicRooms = publicRooms
        self.users = users
    }
}

// MARK: - 응답 — state (§3.6)

/// 판(방) status(원문 'forming'|'active'|'finished'|'cancelled'|'expired' — §3.1 CHECK). 모르는 값은 `.unknown`.
package nonisolated enum MahjongMatchStatus: String, Equatable, Hashable, Sendable, CaseIterable {
    case forming, active, finished, cancelled, expired, unknown

    package init(wire raw: String?) {
        self = raw.flatMap(MahjongMatchStatus.init(rawValue:)) ?? .unknown
    }

    /// 다시 안 바뀌는 끝 상태(finished·cancelled·expired).
    package var isTerminal: Bool { self == .finished || self == .cancelled || self == .expired }
}

/// state 의 자리 사람(USER — `{user_id, display_name, avatar_url, character, center}`). same_visibility 를 묻지 않는다.
package nonisolated struct MahjongStateUser: Codable, Equatable, Hashable, Sendable {
    package var userId: String?
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    package var center: String?
}

/// forming 방의 멤버 한 줄(`members[]` — 그 밖엔 []).
package nonisolated struct MahjongStateMember: Codable, Equatable, Hashable, Sendable {
    package var user: MahjongPeer?
    /// "invited" | "joined"(원문).
    package var state: String?
    package var isHost: Bool?
}

/// 강의 한 장(DISC). (v1.0) 공개 `auto` 칸은 없다 — 자동 버림 표지는 주인의 `events[].priv.auto` 에만(CC-19).
package nonisolated struct MahjongDiscard: Codable, Equatable, Hashable, Sendable {
    package var tile: MahjongTile
    package var tsumogiri: Bool?
    /// 리치 선언패(옆으로 눕힌다).
    package var riichi: Bool?
    /// 울려 간 패 — 강에 남아 있지만 보이는 장수로는 세지 않는다(부로에서 센다, CC-08).
    package var taken: Bool?
}

/// 부로 원문(MELD). `type` 은 원문 글자 — 엔진 값은 `meld`(모르는 type 이면 nil, CC-07).
package nonisolated struct MahjongWireMeld: Codable, Equatable, Hashable, Sendable {
    package var type: String
    package var tiles: [MahjongTile]
    package var called: MahjongTile?
    package var fromSeat: Int?

    package init(type: String, tiles: [MahjongTile], called: MahjongTile? = nil, fromSeat: Int? = nil) {
        self.type = type
        self.tiles = tiles
        self.called = called
        self.fromSeat = fromSeat
    }

    /// 엔진 값으로 잇는 칸. 모르는 type 은 nil.
    package var meld: MahjongMeld? {
        MahjongMeldType(rawValue: type).map { MahjongMeld(type: $0, tiles: tiles, called: called, fromSeat: fromSeat) }
    }

    /// 엔진 값에서 와이어 원문으로(연습판 엔진이 payload 를 만들 때).
    package init(_ meld: MahjongMeld) {
        self.init(type: meld.type.rawValue, tiles: meld.tiles, called: meld.called, fromSeat: meld.fromSeat)
    }
}

/// 자리 한 줄(SEAT — active·finished 만, seat_no 순 4줄). 남의 손은 `hand_count` 만.
package nonisolated struct MahjongStateSeat: Codable, Equatable, Hashable, Sendable {
    package var seatNo: Int
    /// 계정이 지워진 자리는 null(+ `deleted`).
    package var user: MahjongStateUser?
    /// "E"|"S"|"W"|"N"(원문).
    package var wind: String?
    package var isDealer: Bool?
    package var score: Int?
    package var handCount: Int?
    package var melds: [MahjongWireMeld]?
    package var discards: [MahjongDiscard]?
    package var riichi: Bool?
    package var away: Bool?
    package var deleted: Bool?
    package var finalRank: Int?
    package var finalScore: Int?
    package var payout: Int?
}

/// 판 행(`state.match`). 공개 칸만 — 울기 창의 흔적(창 번호·선택지 수·마감)은 없다(§3.6 누출 표).
package nonisolated struct MahjongStateMatch: Codable, Equatable, Hashable, Sendable {
    /// 서버 uuid · 연습판은 "ai-…".
    package var id: String
    /// 원문 status — 엔진 값은 `matchStatus`.
    package var status: String?
    package var stake: Int?
    /// 원문 "tonpuu"|"hanchan" — 엔진 값은 `formatKind`.
    package var format: String?
    package var isPublic: Bool?
    package var host: MahjongPeer?
    package var seq: Int?
    package var createdMs: Double?
    package var roomExpiresMs: Double?
    package var startedMs: Double?
    package var finishedMs: Double?
    /// 원문 'target_reached'|'max_round'|'tobi'|'agari_yame'|'tenpai_yame'|'limit'|'void'.
    package var endReason: String?
    /// 원문 "room"|"turn"|"wait"|"hand_end"|"finished"(내부 claim·draw_wait 는 둘 다 "wait").
    package var phase: String?
    package var handIndex: Int?
    package var round: Int?
    package var handNo: Int?
    package var honba: Int?
    package var kyotaku: Int?
    package var dealerSeat: Int?
    /// 남입·서입 국.
    package var `extension`: Bool?
    package var wallRemaining: Int?
    package var doraIndicators: [MahjongTile]?
    package var kanCount: Int?
    /// phase turn 일 때만 — 누구 차례인지는 공개.
    package var turnSeat: Int?
    /// 깨우기(공개 시각만 — 멈춤 끝·5초 걸음·상한, §3.7 (d)).
    package var wakeAtMs: Double?
    package var wakeSeat: Int?
    package var backupAtMs: Double?
    package var nextHandMs: Double?
    package var baseMs: Int?
    package var bankFullMs: Int?
    package var graceMs: Int?

    package var matchStatus: MahjongMatchStatus { MahjongMatchStatus(wire: status) }
    package var formatKind: MahjongFormat? { format.flatMap(MahjongFormat.init(rawValue:)) }
    /// 무효 판(루비 환불 — 순위·미션·판 끝 콜백에서 뺀다).
    package var isVoid: Bool { endReason == "void" }
    /// 연습판(기기 안 엔진) id 인가.
    package var isPractice: Bool { id.hasPrefix(MahjongStatePayload.practiceIDPrefix) }
}

/// 내 자리 비움(`my_away` — 나만).
package nonisolated struct MahjongAwayState: Codable, Equatable, Hashable, Sendable {
    /// 원문 "timeouts"|"leave"|"account_deleted".
    package var reason: String?
    package var sinceMs: Double?
    /// [돌아왔어요]가 받아지는 때(나가기 뒤 10초).
    package var backReadyMs: Double?
}

/// 사건의 주인 전용 칸(`priv` — 그 자리 주인에게만). 뽑은 패 id · 자동 버림 표지.
package nonisolated struct MahjongEventPriv: Codable, Equatable, Hashable, Sendable {
    package var auto: Bool?
    package var tile: MahjongTile?
}

/// 공개 사건 한 줄(EVENT). kind 별 칸이 한 객체에 나란히 오므로 **kind 밖 칸은 모두 Optional** 이다.
/// kind 는 원문 글자 — 모르는 kind 는 화면이 건너뛰고 다음 전체 조회(`p_since 0`)로 맞춘다(§4.4).
package nonisolated struct MahjongEvent: Codable, Equatable, Hashable, Sendable {
    package var seq: Int
    /// 원문 deal · draw · discard · call · kan · dora · riichi · win · hand_draw · scores · away · end.
    package var kind: String
    package var seat: Int?
    package var atMs: Double?
    // deal
    package var handIndex: Int?
    package var round: Int?
    package var handNo: Int?
    package var honba: Int?
    package var kyotaku: Int?
    package var dealerSeat: Int?
    package var dora: [MahjongTile]?
    // draw · discard
    package var rinshan: Bool?
    /// draw 는 주인만(남에게 null) · discard 는 버린 패.
    package var tile: MahjongTile?
    package var tsumogiri: Bool?
    package var riichi: Bool?
    /// 주인 전용(뽑은 패 · 자동 버림 표지).
    package var priv: MahjongEventPriv?
    // call · kan
    /// call: chi|pon|minkan · kan: ankan|kakan(원문).
    package var type: String?
    package var tiles: [MahjongTile]?
    package var called: MahjongTile?
    package var fromSeat: Int?
    // dora
    package var indicator: MahjongTile?
    // win
    package var seats: [Int]?
    // hand_draw(reason: exhaustive|kyuushu|suufon|suukaikan|suucha_riichi) · away(reason)
    package var reason: String?
    // scores
    package var deltas: [Int]?
    package var scoresAfter: [Int]?
    // away
    package var on: Bool?
    // end
    package var endReason: String?

    package init(seq: Int, kind: String, seat: Int? = nil, atMs: Double? = nil) {
        self.seq = seq
        self.kind = kind
        self.seat = seat
        self.atMs = atMs
    }

    /// 주인에게 온 '시간이 지나 자동으로 버렸다' 표지(CC-19 — 공개 칸에는 없다).
    package var isAutoDiscard: Bool { kind == "discard" && priv?.auto == true }
}

/// 결과의 역 한 칸 `[id, 판]` 원문. 역 id 는 열린 어휘 — 엔진 값은 `yakuKind`(모르는 역이면 nil · 화면은 "새 역").
package nonisolated struct MahjongWireYaku: Codable, Equatable, Hashable, Sendable {
    package var id: String
    package var han: Int

    package init(id: String, han: Int) {
        self.id = id
        self.han = han
    }

    package init(_ yakuHan: MahjongYakuHan) {
        self.init(id: yakuHan.yaku.rawValue, han: yakuHan.han)
    }

    package var yakuKind: MahjongYaku? { MahjongYaku(rawValue: id) }

    package init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        id = try container.decode(String.self)
        han = try container.decode(Int.self)
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(id)
        try container.encode(han)
    }
}

/// 화료 한 건(`last_hand.wins[]`). `ura_indicators` 는 그 화료자가 리치일 때만.
package nonisolated struct MahjongWinResult: Codable, Equatable, Hashable, Sendable {
    /// 책임 지불(파오) — `{seat, yaku}` 원문.
    package struct Pao: Codable, Equatable, Hashable, Sendable {
        package var seat: Int?
        package var yaku: String?

        package var pao: MahjongPao? {
            guard let seat, let kind = yaku.flatMap(MahjongYaku.init(rawValue:)) else { return nil }
            return MahjongPao(seat: seat, yaku: kind)
        }
    }

    package var seat: Int
    /// 쯔모면 null.
    package var fromSeat: Int?
    package var hand: [MahjongTile]?
    package var melds: [MahjongWireMeld]?
    package var winTile: MahjongTile?
    package var yaku: [MahjongWireYaku]?
    package var yakuman: Int?
    package var han: Int?
    package var fu: Int?
    /// 원문 한도 이름(만관 등 — 열린 어휘).
    package var limit: String?
    package var dora: Int?
    package var aka: Int?
    package var ura: Int?
    package var uraIndicators: [MahjongTile]?
    package var total: Int?
    package var pao: Pao?
}

/// 유국 텐파이 한 줄(`last_hand.tenpai[]`).
package nonisolated struct MahjongTenpaiResult: Codable, Equatable, Hashable, Sendable {
    package var seat: Int
    package var hand: [MahjongTile]?
    package var melds: [MahjongWireMeld]?
}

/// 가장 최근 끝난 국(HAND_RESULT — 다음 국 첫 버림까지 싣는다).
package nonisolated struct MahjongHandResult: Codable, Equatable, Hashable, Sendable {
    package var handIndex: Int
    /// 원문 "win"|"exhaustive"|"abortive".
    package var kind: String
    /// 원문 유국 이유(kyuushu · suufon · suukaikan · suucha_riichi …).
    package var reason: String?
    package var wins: [MahjongWinResult]?
    package var tenpai: [MahjongTenpaiResult]?
    package var nagashi: [Int]?
    package var deltas: [Int]?
    package var scoresAfter: [Int]?
    package var bonusTo: Int?
    package var renchan: Bool?
}

/// 반응 한 줄(큐브 모양 `{seat_no, key, at_ms}`).
package nonisolated struct MahjongReaction: Codable, Equatable, Hashable, Sendable {
    package var seatNo: Int?
    /// 보낸 사람(실응답 `{key, at_ms, seat_no, user_id}` — S2 하네스 픽스처에서 확인, T).
    package var userId: String?
    package var key: String?
    package var atMs: Double?

    package var sticker: AingSticker? { key.flatMap(AingSticker.init(rawValue:)) }
}

/// state 묶음(§3.6) — state 와 쓰기 RPC 응답 공통, 연습판 엔진(E)의 `payload(for:)` 도 이 타입을 낸다.
/// 남의 손·뽑은 패·대기·후리텐·bank·선택지는 **어디에도 없다** — `my_*` 칸만 나의 숨은 정보다.
package nonisolated struct MahjongStatePayload: Codable, Equatable, Sendable {
    /// 연습판 id 머리(`"ai-"` — 서버 uuid 와 겹치지 않는다).
    package static let practiceIDPrefix = "ai-"

    package var match: MahjongStateMatch?
    /// forming 일 때만, 그 밖엔 [].
    package var members: [MahjongStateMember]?
    /// active·finished 만, seat_no 순 4줄.
    package var seats: [MahjongStateSeat]?
    /// 관전 없음 — 멤버는 자리 전엔 null.
    package var mySeat: Int?
    /// id 오름차순, 쯔모패 제외.
    package var myHand: [MahjongTile]?
    package var myDrawn: MahjongTile?
    /// 대기 **종류**(0~33).
    package var myWaits: [Int]?
    /// 원문 "discard"|"temporary"|"riichi".
    package var myFuriten: [String]?
    /// 지금 내 몫 결정. 모르는 kind 는 nil 로 접는다(머리말).
    package var myDecision: MahjongDecision?
    package var myAway: MahjongAwayState?
    /// seq > p_since_seq, seq 순, 최대 80.
    package var events: [MahjongEvent]?
    package var lastHand: MahjongHandResult?
    package var reactions: [MahjongReaction]?
    package var rubyBalance: Int?
    package var serverNowMs: Double?

    package init(
        match: MahjongStateMatch? = nil, members: [MahjongStateMember]? = nil, seats: [MahjongStateSeat]? = nil,
        mySeat: Int? = nil, myHand: [MahjongTile]? = nil, myDrawn: MahjongTile? = nil, myWaits: [Int]? = nil,
        myFuriten: [String]? = nil, myDecision: MahjongDecision? = nil, myAway: MahjongAwayState? = nil,
        events: [MahjongEvent]? = nil, lastHand: MahjongHandResult? = nil, reactions: [MahjongReaction]? = nil,
        rubyBalance: Int? = nil, serverNowMs: Double? = nil
    ) {
        self.match = match
        self.members = members
        self.seats = seats
        self.mySeat = mySeat
        self.myHand = myHand
        self.myDrawn = myDrawn
        self.myWaits = myWaits
        self.myFuriten = myFuriten
        self.myDecision = myDecision
        self.myAway = myAway
        self.events = events
        self.lastHand = lastHand
        self.reactions = reactions
        self.rubyBalance = rubyBalance
        self.serverNowMs = serverNowMs
    }

    private enum CodingKeys: String, CodingKey {
        case match, members, seats, mySeat, myHand, myDrawn, myWaits, myFuriten, myDecision, myAway, events, lastHand
        case reactions, rubyBalance, serverNowMs
    }

    package init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        match = try c.decodeIfPresent(MahjongStateMatch.self, forKey: .match)
        members = try c.decodeIfPresent([MahjongStateMember].self, forKey: .members)
        seats = try c.decodeIfPresent([MahjongStateSeat].self, forKey: .seats)
        mySeat = try c.decodeIfPresent(Int.self, forKey: .mySeat)
        myHand = try c.decodeIfPresent([MahjongTile].self, forKey: .myHand)
        myDrawn = try c.decodeIfPresent(MahjongTile.self, forKey: .myDrawn)
        myWaits = try c.decodeIfPresent([Int].self, forKey: .myWaits)
        myFuriten = try c.decodeIfPresent([String].self, forKey: .myFuriten)
        // 모르는 결정 kind(규칙 2판의 새 결정)는 state 전체를 죽이지 않고 '내 몫 결정 없음'으로 접는다(CC-07).
        myDecision = (try? c.decodeIfPresent(MahjongDecision.self, forKey: .myDecision)) ?? nil
        myAway = try c.decodeIfPresent(MahjongAwayState.self, forKey: .myAway)
        events = try c.decodeIfPresent([MahjongEvent].self, forKey: .events)
        lastHand = try c.decodeIfPresent(MahjongHandResult.self, forKey: .lastHand)
        reactions = try c.decodeIfPresent([MahjongReaction].self, forKey: .reactions)
        rubyBalance = try c.decodeIfPresent(Int.self, forKey: .rubyBalance)
        serverNowMs = try c.decodeIfPresent(Double.self, forKey: .serverNowMs)
    }

    package func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(match, forKey: .match)
        try c.encodeIfPresent(members, forKey: .members)
        try c.encodeIfPresent(seats, forKey: .seats)
        try c.encodeIfPresent(mySeat, forKey: .mySeat)
        try c.encodeIfPresent(myHand, forKey: .myHand)
        try c.encodeIfPresent(myDrawn, forKey: .myDrawn)
        try c.encodeIfPresent(myWaits, forKey: .myWaits)
        try c.encodeIfPresent(myFuriten, forKey: .myFuriten)
        try c.encodeIfPresent(myDecision, forKey: .myDecision)
        try c.encodeIfPresent(myAway, forKey: .myAway)
        try c.encodeIfPresent(events, forKey: .events)
        try c.encodeIfPresent(lastHand, forKey: .lastHand)
        try c.encodeIfPresent(reactions, forKey: .reactions)
        try c.encodeIfPresent(rubyBalance, forKey: .rubyBalance)
        try c.encodeIfPresent(serverNowMs, forKey: .serverNowMs)
    }

    /// 내 자리 줄(자리 전이면 nil).
    package var mySeatRow: MahjongStateSeat? {
        guard let mySeat else { return nil }
        return seats?.first { $0.seatNo == mySeat }
    }

    /// 마지막 사건 seq(사건이 없으면 판 seq).
    package var lastEventSeq: Int? { events?.last?.seq ?? match?.seq }
}

// MARK: - 응답 — 쓰기·조회 공용

/// 쓰기·조회 공용 응답(create · invite · join · decline · leave · start · state · act · call · back · react).
/// 상태는 **`state` 키**에 실려 온다(머리말 ⑤ — 펼치지 않는다).
package nonisolated struct MahjongActionResponse: Decodable, Equatable, Sendable {
    package let status: MahjongRPCStatus
    package var state: MahjongStatePayload?
    /// create ok.
    package var matchId: String?
    /// insufficient.
    package var need: Int?
    package var have: Int?
    /// insufficient 의 주인('me' 등 — 원문).
    package var side: String?
    /// seats_dropped — 빠진 사람 uuid.
    package var dropped: [String]?
    /// seats_dropped — uuid → 'unseen'|'outdated'|'insufficient'(원문).
    package var reasons: [String: String]?
    /// too_fast(back) — 다시 누를 수 있을 때까지 ms.
    package var retryMs: Double?
    /// illegal — 'not_option'|'not_in_hand'(원문).
    package var reason: String?
    /// invalid(create) — 서버가 받는 판돈·형식 집합(§3.4 `invalid{stakes, formats}` — §4.4 목록 밖에 더한 옵셔널 칸).
    package var stakes: [Int]?
    package var formats: [String]?
    package var serverNowMs: Double?

    package init(
        status: MahjongRPCStatus, state: MahjongStatePayload? = nil, matchId: String? = nil, need: Int? = nil,
        have: Int? = nil, side: String? = nil, dropped: [String]? = nil, reasons: [String: String]? = nil,
        retryMs: Double? = nil, reason: String? = nil, stakes: [Int]? = nil, formats: [String]? = nil,
        serverNowMs: Double? = nil
    ) {
        self.status = status
        self.state = state
        self.matchId = matchId
        self.need = need
        self.have = have
        self.side = side
        self.dropped = dropped
        self.reasons = reasons
        self.retryMs = retryMs
        self.reason = reason
        self.stakes = stakes
        self.formats = formats
        self.serverNowMs = serverNowMs
    }
}

// MARK: - 응답 — 순위 (v1.0.2 평균 등수 · 10판 이상)

/// 순위표 한 줄. 순위·배열 순서는 **서버 것**이다(재정렬 금지). 줄 세우기는 반올림 전 avg_rank — 화면은 소수 둘째 자리.
package nonisolated struct MahjongRankRow: Codable, Equatable, Hashable, Sendable {
    package var rank: Int?
    package var userId: String?
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    package var center: String?
    package var games: Int?
    package var firsts: Int?
    package var avgRank: Double?
}

/// 순위 응답의 `me`. 10판 전이면 `rank` 가 null 이고 `games` 는 그대로 — 화면이 "N판 더 하면 순위에 올라요"를 쓴다.
package nonisolated struct MahjongRankingMe: Codable, Equatable, Hashable, Sendable {
    package var rank: Int?
    package var games: Int?
    package var firsts: Int?
    package var seconds: Int?
    package var thirds: Int?
    package var fourths: Int?
    package var avgRank: Double?

    /// 순위에 오르기까지 남은 판 수(이미 올랐거나 모르면 0).
    package var gamesUntilRanked: Int { max(0, MahjongRules.rankingMinGames - (games ?? 0)) }
}

/// mahjong_ranking 응답.
package nonisolated struct MahjongRankingResponse: Decodable, Equatable, Sendable {
    package let status: MahjongRPCStatus
    package var serverNowMs: Double?
    /// 기록 시작 시각(epoch -infinity 면 null).
    package var recordSinceMs: Double?
    package var me: MahjongRankingMe?
    package var rows: [MahjongRankRow]?

    package init(
        status: MahjongRPCStatus, serverNowMs: Double? = nil, recordSinceMs: Double? = nil, me: MahjongRankingMe? = nil,
        rows: [MahjongRankRow]? = nil
    ) {
        self.status = status
        self.serverNowMs = serverNowMs
        self.recordSinceMs = recordSinceMs
        self.me = me
        self.rows = rows
    }
}

// MARK: - 서비스 호출

/// 아잉 마작 RPC 13개. 몸통은 공용 `duelRPC`(DuelRPC.swift) 하나다. 교착 재시도 여부는 `MahjongWire.RPC` 가 정한다.
/// 요청 마감(act·call·back — §4.5 CC-06)은 스토어가 감싼다(공용 파일은 안 고친다).
extension SupabaseWorkService {
    package func mahjongLobby(accessToken: String) async throws -> MahjongLobbyResponse {
        try await mahjongCall(.lobby, body: MahjongProtocolRequest(), accessToken: accessToken)
    }

    package func mahjongCreate(
        accessToken: String, stake: Int, isPublic: Bool, format: String
    ) async throws -> MahjongActionResponse {
        try await mahjongCall(
            .create, body: MahjongCreateRequest(pStake: stake, pPublic: isPublic, pFormat: format), accessToken: accessToken)
    }

    package func mahjongInvite(accessToken: String, matchID: String, userID: String) async throws -> MahjongActionResponse {
        try await mahjongCall(
            .invite, body: MahjongInviteRequest(pMatchId: matchID, pUserId: userID), accessToken: accessToken)
    }

    package func mahjongJoin(accessToken: String, matchID: String) async throws -> MahjongActionResponse {
        try await mahjongCall(.join, body: MahjongMatchRequest(pMatchId: matchID), accessToken: accessToken)
    }

    package func mahjongDecline(accessToken: String, matchID: String) async throws -> MahjongActionResponse {
        try await mahjongCall(.decline, body: MahjongMatchRequest(pMatchId: matchID), accessToken: accessToken)
    }

    /// forming 이면 방에서 나가기(방장이면 방 닫기) · active 면 **자리 비움**(기권 아님, DEC:16).
    package func mahjongLeave(accessToken: String, matchID: String) async throws -> MahjongActionResponse {
        try await mahjongCall(.leave, body: MahjongMatchRequest(pMatchId: matchID), accessToken: accessToken)
    }

    package func mahjongStart(accessToken: String, matchID: String) async throws -> MahjongActionResponse {
        try await mahjongCall(.start, body: MahjongMatchRequest(pMatchId: matchID), accessToken: accessToken)
    }

    /// 상태(자리 주인·멤버 전용). 읽기처럼 보이지만 마감이 지났으면 서버가 따라잡기로 판을 바꾼다.
    package func mahjongState(
        accessToken: String, matchID: String, sinceSeq: Int = 0
    ) async throws -> MahjongActionResponse {
        try await mahjongCall(
            .state, body: MahjongStateRequest(pMatchId: matchID, pSinceSeq: sinceSeq), accessToken: accessToken)
    }

    package func mahjongAct(
        accessToken: String, matchID: String, expectedSeq: Int, action: String, tiles: [MahjongTile]
    ) async throws -> MahjongActionResponse {
        try await mahjongCall(
            .act,
            body: MahjongActRequest(pMatchId: matchID, pExpectedSeq: expectedSeq, pAction: action, pTiles: tiles),
            accessToken: accessToken)
    }

    package func mahjongCallAnswer(
        accessToken: String, matchID: String, windowID: Int, action: String, tiles: [MahjongTile]
    ) async throws -> MahjongActionResponse {
        try await mahjongCall(
            .call, body: MahjongCallRequest(pMatchId: matchID, pWindowId: windowID, pAction: action, pTiles: tiles),
            accessToken: accessToken)
    }

    /// [돌아왔어요] — 자리 비움 풀기.
    package func mahjongBack(accessToken: String, matchID: String) async throws -> MahjongActionResponse {
        try await mahjongCall(.back, body: MahjongMatchRequest(pMatchId: matchID), accessToken: accessToken)
    }

    package func mahjongReact(accessToken: String, matchID: String, key: String) async throws -> MahjongActionResponse {
        try await mahjongCall(.react, body: MahjongReactRequest(pMatchId: matchID, pKey: key), accessToken: accessToken)
    }

    package func mahjongRanking(accessToken: String) async throws -> MahjongRankingResponse {
        try await mahjongCall(.ranking, body: MahjongProtocolRequest(), accessToken: accessToken)
    }

    private func mahjongCall<Body: Encodable, Response: Decodable>(
        _ rpc: MahjongWire.RPC, body: Body, accessToken: String
    ) async throws -> Response {
        try await duelRPC(
            rpc.rawValue, body: body, accessToken: accessToken, retriesDeadlockOnce: rpc.retriesDeadlockOnce)
    }
}
