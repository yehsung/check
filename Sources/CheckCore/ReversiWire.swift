import Foundation

// 아잉 뒤집기(내부 이름 reversi) 1:1 RPC 의 와이어 타입(요청·응답)과 서비스 호출 10개 — `/rest/v1/rpc/reversi_*`.
// 계약의 정본은 설계서 FLIP/SPEC.md §3.4(RPC·status) · §3.5(로비) · §3.6(state) · §4.3(이 파일)이고,
// 서버 갈래가 같은 계약으로 SQL(20261108200000_reversi.sql)을 쓴다.
// **키 이름을 바꾸지 마라** — 디코더가 snake_case → camelCase 로 접으므로 `turn_started_ms` 는 `turnStartedMs` 다.
//
// ── 테트리스·체스 와이어의 규약을 그대로 베낀다 ──
//  ① **status 만 필수이고 나머지는 전부 Optional 이다.** 비옵셔널 한 칸이면 서버가 키를 늘리기 전·db push 전 창에서
//     디코드가 통째로 throw 해 대결 창이 죽는다. nil 은 "모른다" 다.
//  ② **모르는 status 는 `.unknown` 으로 접는다.** 서버가 어휘를 넓혀도(새 status 는 프로토콜을 안 올린다, §3.4)
//     옛 앱은 일반 실패 문구를 말한다(문구 표는 `ReversiNoticeText` 한 곳).
//  ③ 시각은 전부 epoch **밀리초**이고 `Double` 로 읽는다. 기기 시계 보정은 스토어 몫이다.
//  ④ 요청 본문은 **빈 `{}` 가 아니다** — `p_protocol` 을 언제나 싣는다(PostgREST 는 본문의 키 집합으로 함수를 고른다).
//  ⑤ 상태가 실리는 응답은 **`{status, state}` 봉투 하나**다(상태 키를 최상위에 펼치지 않는다, §3.4). 거절 응답에도
//     판이 있으면 `state` 가 실린다. 쓰기 RPC(respond·move·resign)의 state 는 **수 기록 전체**다(p_since = 0).
//
// ── 리버시에서 정한 자리 ──
//  · 칸은 **정수 `idx`(0~63) 하나**로 주고받는다(`idx = row*8 + col`, row 0 = 1행 위). x·y 두 칸은 없다.
//  · 판은 64자 `.bw` 문자열 하나이고 `ReversiBoard` 로 바로 디코드한다(판의 권위). 수 한 줄은 `ReversiPly` 로 읽는다.
//  · 받은 신청은 로비 `me.incoming` 이 통째로 준다(별도 받은함 RPC 없음, §3.5). 보낸 신청은 `me.outgoing` 하나.
//  · 사람 행의 id 키가 둘이다 — 로비(users · 신청의 from/to · matches 의 a/b)는 **`id`**, state 와 순위는 **`user_id`**.
//  · 비로그인은 `unauthorized` 다(오목·체스·큐브와 같은 어휘 — 테트리스의 `not_signed_in` 이 아니다).

/// 아잉 뒤집기 RPC 프로토콜과 이름 묶음.
package nonisolated enum ReversiWire {
    /// 서버 `reversi_protocol()` 이 1 이고, 이보다 **작으면** `unsupported_client` 다.
    package static let protocolVersion = 1

    /// 클라가 부르는 RPC 이름 전부. 계약 시험이 마이그레이션의 `reversi_` 클라 RPC 집합과 이 목록을 잰다.
    package enum RPC: String, CaseIterable, Sendable {
        case lobby = "reversi_lobby"
        case challenge = "reversi_challenge"
        case cancel = "reversi_cancel"
        case respond = "reversi_respond"
        case state = "reversi_state"
        case move = "reversi_move"
        case resign = "reversi_resign"
        case ranking = "reversi_ranking"
        case watch = "reversi_watch"
        case watchLive = "reversi_watch_live"

        package static let all: [String] = allCases.map(\.rawValue)

        /// 교착(40P01) 한 번 재시도 여부(§4.3). 쓰기 전부 + `reversi_state`(서버가 따라잡기로 자동 착수를 정산한다).
        /// 로비·순위·관전 둘은 읽기 전용이라 끈다 — 실패하면 다음 계기가 다시 읽는다.
        package var retriesDeadlockOnce: Bool {
            switch self {
            case .challenge, .cancel, .respond, .state, .move, .resign: return true
            case .lobby, .ranking, .watch, .watchLive: return false
            }
        }
    }
}

/// RPC status 어휘(§3.4 — 서버와 같은 집합). **모르는 값은 `.unknown`** 이다(머리말 ②).
package nonisolated enum ReversiRPCStatus: String, Equatable, Hashable, Sendable, Decodable {
    case ok
    case unauthorized
    case unsupportedClient = "unsupported_client"
    case invalid
    case blackout
    case targetFocused = "target_focused"
    case targetOutdated = "target_outdated"
    case busy
    case targetBusy = "target_busy"
    case alreadyPending = "already_pending"
    case insufficient
    case notFound = "not_found"
    case notPending = "not_pending"
    case expired
    case notActive = "not_active"
    case notYourTurn = "not_your_turn"
    /// 보낸 `p_expected_seq` 가 서버 `move_count` 와 다르다(화면이 낡았다). **문구 없이** 실려 온 state 로 맞춘다.
    /// 판정 순서가 `not_your_turn` 보다 앞이다(§3.4 — 같은 계정 두 기기 동시 착수는 ok 1 · stale 1).
    case stale
    /// 둘 수 없는 칸(`reason` = out_of_range · occupied · no_flip). 판은 그대로이고 state 가 실려 온다.
    case illegal
    /// 착수 직전 서버 따라잡기가 **내 색**을 시간 초과로 대신 뒀다(`auto_placed_count`). 내 수는 쓰지 않았다.
    case autoPlaced = "auto_placed"
    case unknown

    package init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReversiRPCStatus(rawValue: raw) ?? .unknown
    }
}

// MARK: - 요청 본문 (키 = 서버 인자 이름 — 인코더가 snake_case 로 편다)

/// reversi_lobby / reversi_ranking 본문. { p_protocol }.
package nonisolated struct ReversiProtocolRequest: Encodable, Sendable {
    package var pProtocol = ReversiWire.protocolVersion
    package init() {}
}

/// reversi_challenge 본문. { p_protocol, p_opponent, p_stake }.
package nonisolated struct ReversiChallengeRequest: Encodable, Sendable {
    package var pProtocol = ReversiWire.protocolVersion
    package let pOpponent: String
    package let pStake: Int

    package init(pOpponent: String, pStake: Int) {
        self.pOpponent = pOpponent
        self.pStake = pStake
    }
}

/// reversi_cancel / reversi_resign 본문. { p_protocol, p_match_id }.
package nonisolated struct ReversiMatchRequest: Encodable, Sendable {
    package var pProtocol = ReversiWire.protocolVersion
    package let pMatchId: String

    package init(pMatchId: String) {
        self.pMatchId = pMatchId
    }
}

/// reversi_respond 본문. { p_protocol, p_match_id, p_accept }.
package nonisolated struct ReversiRespondRequest: Encodable, Sendable {
    package var pProtocol = ReversiWire.protocolVersion
    package let pMatchId: String
    package let pAccept: Bool

    package init(pMatchId: String, pAccept: Bool) {
        self.pMatchId = pMatchId
        self.pAccept = pAccept
    }
}

/// reversi_state 본문. { p_protocol, p_match_id, p_since_seq } — 수 기록은 `seq > p_since_seq` 만 온다.
package nonisolated struct ReversiStateRequest: Encodable, Sendable {
    package var pProtocol = ReversiWire.protocolVersion
    package let pMatchId: String
    package let pSinceSeq: Int

    package init(pMatchId: String, pSinceSeq: Int) {
        self.pMatchId = pMatchId
        self.pSinceSeq = pSinceSeq
    }
}

/// reversi_move 본문. { p_protocol, p_match_id, p_expected_seq, p_idx }.
/// `p_expected_seq` 는 화면이 본 `move_count`(패스 포함 기록 수)다 — 다르면 `stale`.
package nonisolated struct ReversiMoveRequest: Encodable, Sendable {
    package var pProtocol = ReversiWire.protocolVersion
    package let pMatchId: String
    package let pExpectedSeq: Int
    package let pIdx: Int

    package init(pMatchId: String, pExpectedSeq: Int, pIdx: Int) {
        self.pMatchId = pMatchId
        self.pExpectedSeq = pExpectedSeq
        self.pIdx = pIdx
    }
}

/// reversi_watch / reversi_watch_live 본문. { p_protocol, p_match_id, p_since_seq }.
package nonisolated struct ReversiWatchRequest: Encodable, Sendable {
    package var pProtocol = ReversiWire.protocolVersion
    package let pMatchId: String
    package let pSinceSeq: Int

    package init(pMatchId: String, pSinceSeq: Int) {
        self.pMatchId = pMatchId
        self.pSinceSeq = pSinceSeq
    }
}

// MARK: - 응답 행 — 로비 (§3.5)

/// 이름 정도만 실린 사람(PEER — 신청의 `from`·`to` · 로비 matches 의 `a`·`b`). id 키는 **`id`** 다.
package nonisolated struct ReversiPeerRow: Decodable, Equatable, Sendable {
    package var id: String?
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?

    package init(id: String? = nil, displayName: String? = nil, avatarUrl: String? = nil, character: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.character = character
    }
}

/// 로비 `users[]` 한 줄. `capable` 이 nil 이면 **불가**로 읽는다(스토어) — 모르는 상대에게 신청해
/// `target_outdated` 를 받는 것보다 낫다. `in_match` 는 서버 `lobby__others.busy`(= `game__busy_users`)다.
package nonisolated struct ReversiLobbyUserRow: Decodable, Equatable, Sendable {
    package var id: String?
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    package var center: String?
    package var isWorking: Bool?
    package var inMatch: Bool?
    package var capable: Bool?
    package var focusMode: Bool?
}

/// 신청 한 건. 받은 것은 `from`, 보낸 것은 `to` 가 실린다. 서버는 **만료 전 pending 만** 싣는다(§3.5 — 만료됐는데
/// 아직 expired 로 안 바뀐 행은 거른다). 화면의 만료 걷기는 그래도 스토어 타이머 몫이다.
package nonisolated struct ReversiInviteRow: Decodable, Equatable, Sendable {
    package var matchId: String?
    package var from: ReversiPeerRow?
    package var to: ReversiPeerRow?
    package var stake: Int?
    package var expiresAtMs: Double?
}

/// 로비 `me`.
package nonisolated struct ReversiLobbyMe: Decodable, Equatable, Sendable {
    package var rubyBalance: Int?
    package var wins: Int?
    package var losses: Int?
    package var draws: Int?
    package var activeMatchId: String?
    /// 최근 순 20(신청 뒤 생긴 숨김·차단은 서버가 거른다).
    package var incoming: [ReversiInviteRow]?
    package var outgoing: ReversiInviteRow?
}

/// 로비 "지금 대결 중" 한 줄(active 판, 최근 순 20). a/b 는 **uuid 오름차순**(색이 아니다).
package nonisolated struct ReversiLobbyMatchRow: Decodable, Equatable, Sendable {
    package var id: String?
    package var a: ReversiPeerRow?
    package var b: ReversiPeerRow?
    package var stake: Int?
    /// 관전자 수(`match__watchers`). 없으면 0 으로 읽는다.
    package var watchers: Int?
    package var startedAtMs: Double?
}

/// reversi_lobby 응답(§3.5). 숫자 상수(판돈·차례 초·유예·신청 TTL·자리 비움 연속 수)도 서버가 말한다 —
/// 화면 캡션은 이 값을 읽고 상수를 베끼지 않는다.
package nonisolated struct ReversiLobbyResponse: Decodable, Equatable, Sendable {
    package let status: ReversiRPCStatus
    package var serverNowMs: Double?
    package var stakes: [Int]?
    package var turnSeconds: Int?
    package var turnGraceSeconds: Int?
    package var inviteTtlSeconds: Int?
    package var autoAbandonStreak: Int?
    package var me: ReversiLobbyMe?
    package var users: [ReversiLobbyUserRow]?
    package var matches: [ReversiLobbyMatchRow]?

    package init(
        status: ReversiRPCStatus, serverNowMs: Double? = nil, stakes: [Int]? = nil, turnSeconds: Int? = nil,
        turnGraceSeconds: Int? = nil, inviteTtlSeconds: Int? = nil, autoAbandonStreak: Int? = nil,
        me: ReversiLobbyMe? = nil, users: [ReversiLobbyUserRow]? = nil, matches: [ReversiLobbyMatchRow]? = nil
    ) {
        self.status = status
        self.serverNowMs = serverNowMs
        self.stakes = stakes
        self.turnSeconds = turnSeconds
        self.turnGraceSeconds = turnGraceSeconds
        self.inviteTtlSeconds = inviteTtlSeconds
        self.autoAbandonStreak = autoAbandonStreak
        self.me = me
        self.users = users
        self.matches = matches
    }
}

// MARK: - 응답 행 — state (§3.6, 참가자·관전 공용)

/// state 의 사람 한 칸(USER — `black_user`·`white_user`·`opponent`). id 키는 **`user_id`** 다.
package nonisolated struct ReversiPlayerRow: Decodable, Equatable, Sendable {
    package var userId: String?
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    package var center: String?
}

/// WOF 점수(자연 종료만 — 기권·abandoned 판은 null, V-15). 빈칸은 이긴 쪽에 더해져 합이 늘 64 다.
package nonisolated struct ReversiScoreRow: Decodable, Equatable, Sendable {
    package var black: Int?
    package var white: Int?
}

/// 판 행(`state.match`). 사람 칸(challenger·opponent·black·white·winner)은 **uuid 문자열**이다 —
/// 얼굴은 state 최상위의 `black_user`·`white_user`·`opponent` 가 준다.
package nonisolated struct ReversiMatchRow: Decodable, Equatable, Sendable {
    package var id: String?
    /// 'pending' | 'declined' | 'cancelled' | 'expired' | 'active' | 'finished'.
    package var status: String?
    package var stake: Int?
    package var challenger: String?
    package var opponent: String?
    /// 수락 때 무작위 배정. pending 이면 null.
    package var black: String?
    package var white: String?
    /// 패스 포함 기록 수 = 마지막 seq. `p_expected_seq` 의 눈금.
    package var moveCount: Int?
    /// 끝났거나 pending 이면 null.
    package var turn: ReversiColor?
    package var turnStartedMs: Double?
    /// turn_started + 30초 **표시값**(서버 유예 2초 미포함). active 가 아니면 null.
    package var deadlineMs: Double?
    package var inviteExpiresMs: Double?
    package var startedMs: Double?
    package var finishedMs: Double?
    package var result: ReversiResult?
    package var endReason: ReversiEndReason?
    /// 이긴 사람의 uuid(무승부·진행 중이면 null).
    package var winner: String?
    /// 64자 `.bw` — **판의 권위**.
    package var board: ReversiBoard?
    /// 판 위 실제 돌 수(늘 실린다, V-12).
    package var discs: ReversiCounts?
    /// 자연 종료만.
    package var score: ReversiScoreRow?

    package var matchStatus: ReversiMatchStatus { ReversiMatchStatus(wire: status) }
}

/// state 묶음(§3.6) — state · respond · move · resign · watch · watch_live 공통. 관전 모양이면 참가자 칸
/// (`opponent`·`my_color`·`my_auto_streak`·`opponent_auto_streak`·`ruby_balance`)이 null 이고 `legal_moves` 는 [] 다.
package nonisolated struct ReversiStatePayload: Decodable, Equatable, Sendable {
    package var match: ReversiMatchRow?
    /// `seq > p_since_seq` 인 수만 seq 순(쓰기 RPC 응답은 전체).
    package var moves: [ReversiPly]?
    package var blackUser: ReversiPlayerRow?
    package var whiteUser: ReversiPlayerRow?
    /// 참가자 관점의 상대(관전이면 null).
    package var opponent: ReversiPlayerRow?
    /// 관전·pending 이면 null.
    package var myColor: ReversiColor?
    /// active 이고 **내 차례일 때만** 오름차순. 그 밖은 []. 클라는 이 목록만 하이라이트·입력으로 받는다(DEC:26).
    package var legalMoves: [Int]?
    package var blackAutoStreak: Int?
    package var whiteAutoStreak: Int?
    package var myAutoStreak: Int?
    package var opponentAutoStreak: Int?
    package var autoAbandonStreak: Int?
    package var turnSeconds: Int?
    package var graceMs: Int?
    /// 참가자만.
    package var rubyBalance: Int?
    /// `match__watchers('reversi', id)`. 관전 RPC 는 watch_live 만 채운다(watch 는 0).
    package var watchers: Int?
    package var serverNowMs: Double?

    package init(
        match: ReversiMatchRow? = nil, moves: [ReversiPly]? = nil, blackUser: ReversiPlayerRow? = nil,
        whiteUser: ReversiPlayerRow? = nil, opponent: ReversiPlayerRow? = nil, myColor: ReversiColor? = nil,
        legalMoves: [Int]? = nil, blackAutoStreak: Int? = nil, whiteAutoStreak: Int? = nil, myAutoStreak: Int? = nil,
        opponentAutoStreak: Int? = nil, autoAbandonStreak: Int? = nil, turnSeconds: Int? = nil, graceMs: Int? = nil,
        rubyBalance: Int? = nil, watchers: Int? = nil, serverNowMs: Double? = nil
    ) {
        self.match = match
        self.moves = moves
        self.blackUser = blackUser
        self.whiteUser = whiteUser
        self.opponent = opponent
        self.myColor = myColor
        self.legalMoves = legalMoves
        self.blackAutoStreak = blackAutoStreak
        self.whiteAutoStreak = whiteAutoStreak
        self.myAutoStreak = myAutoStreak
        self.opponentAutoStreak = opponentAutoStreak
        self.autoAbandonStreak = autoAbandonStreak
        self.turnSeconds = turnSeconds
        self.graceMs = graceMs
        self.rubyBalance = rubyBalance
        self.watchers = watchers
        self.serverNowMs = serverNowMs
    }
}

/// 판 행의 status. 와이어 글자는 String 으로 받고 여기서 접는다 — 모르는 값은 `.unknown`.
package nonisolated enum ReversiMatchStatus: String, Equatable, Hashable, Sendable {
    case pending, declined, cancelled, expired, active, finished, unknown

    package init(wire raw: String?) {
        self = raw.flatMap(ReversiMatchStatus.init(rawValue:)) ?? .unknown
    }
}

/// 수 기록 한 줄의 와이어 모양: `{seq, color, kind:"stone"|"pass", idx:0..63|null, flipped:[…], auto, at_ms}`.
/// `at_ms` 는 화면이 쓰지 않아 읽지 않는다. `flipped`·`auto` 가 빠지면 []·거짓으로 읽는다(pass 행의 모양).
extension ReversiPly: Decodable {
    private enum CodingKeys: String, CodingKey { case seq, color, kind, idx, flipped, auto }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            seq: try container.decode(Int.self, forKey: .seq),
            color: try container.decode(ReversiColor.self, forKey: .color),
            kind: try container.decode(Kind.self, forKey: .kind),
            idx: try container.decodeIfPresent(Int.self, forKey: .idx),
            flipped: try container.decodeIfPresent([Int].self, forKey: .flipped) ?? [],
            auto: try container.decodeIfPresent(Bool.self, forKey: .auto) ?? false
        )
    }
}

// MARK: - 응답 — 쓰기·조회 공용

/// 쓰기·조회 공용 응답(challenge · cancel · respond · state · move · resign · watch · watch_live).
/// 상태는 **`state` 키**에 실려 온다(머리말 ⑤ — 펼치지 않는다).
package nonisolated struct ReversiActionResponse: Decodable, Equatable, Sendable {
    package let status: ReversiRPCStatus
    package var state: ReversiStatePayload?
    /// challenge ok / already_pending.
    package var matchId: String?
    /// challenge ok.
    package var inviteExpiresMs: Double?
    package var rubyBalance: Int?
    /// insufficient.
    package var need: Int?
    /// insufficient — 남(신청자)의 잔액이면 null.
    package var have: Int?
    /// insufficient(respond) — 'me' | 'challenger'.
    package var side: String?
    /// illegal — 'out_of_range' | 'occupied' | 'no_flip'. 글자로 받고 `illegalReason` 으로 접는다(모르는 값은 nil).
    package var reason: String?
    /// auto_placed — 이번 따라잡기가 둔 수.
    package var autoPlacedCount: Int?
    /// respond ok — 수락이면 true, 거절이면 false.
    package var accepted: Bool?
    /// invalid(challenge) — 서버가 받는 판돈 집합. (§4.3 목록 밖에 더한 옵셔널 칸 — 서버 `invalid{stakes}`.)
    package var stakes: [Int]?
    package var serverNowMs: Double?

    package var illegalReason: ReversiIllegalReason? { reason.flatMap(ReversiIllegalReason.init(rawValue:)) }

    package init(
        status: ReversiRPCStatus, state: ReversiStatePayload? = nil, matchId: String? = nil,
        inviteExpiresMs: Double? = nil, rubyBalance: Int? = nil, need: Int? = nil, have: Int? = nil,
        side: String? = nil, reason: String? = nil, autoPlacedCount: Int? = nil, accepted: Bool? = nil,
        stakes: [Int]? = nil, serverNowMs: Double? = nil
    ) {
        self.status = status
        self.state = state
        self.matchId = matchId
        self.inviteExpiresMs = inviteExpiresMs
        self.rubyBalance = rubyBalance
        self.need = need
        self.have = have
        self.side = side
        self.reason = reason
        self.autoPlacedCount = autoPlacedCount
        self.accepted = accepted
        self.stakes = stakes
        self.serverNowMs = serverNowMs
    }
}

// MARK: - 응답 — 순위

/// 순위표 한 줄. 순위는 **서버가 매긴 값**이고 배열 순서도 서버 것이다(재정렬 금지). id 키는 `user_id`.
package nonisolated struct ReversiRankRow: Decodable, Equatable, Sendable {
    package var rank: Int?
    package var userId: String?
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    package var center: String?
    package var wins: Int?
    package var losses: Int?
    package var draws: Int?
    /// 승점 = 승 − 패.
    package var points: Int?
}

/// 순위표의 `me`(0판이면 rank null).
package nonisolated struct ReversiRankingMe: Decodable, Equatable, Sendable {
    package var rank: Int?
    package var wins: Int?
    package var losses: Int?
    package var draws: Int?
    package var points: Int?
}

/// reversi_ranking 응답. `record_since_ms` 는 전적 컷이 없으면(-infinity) null 이다.
package nonisolated struct ReversiRankingResponse: Decodable, Equatable, Sendable {
    package let status: ReversiRPCStatus
    package var serverNowMs: Double?
    package var recordSinceMs: Double?
    package var me: ReversiRankingMe?
    package var rows: [ReversiRankRow]?
}

// MARK: - 서비스 호출

/// 아잉 뒤집기 RPC 10개. 몸통은 공용 `duelRPC`(DuelRPC.swift) 하나다. 교착 재시도 여부는 `ReversiWire.RPC` 가 정한다.
extension SupabaseWorkService {
    package func reversiLobby(accessToken: String) async throws -> ReversiLobbyResponse {
        try await reversiCall(.lobby, body: ReversiProtocolRequest(), accessToken: accessToken)
    }

    package func reversiChallenge(
        accessToken: String, opponentID: String, stake: Int
    ) async throws -> ReversiActionResponse {
        try await reversiCall(
            .challenge, body: ReversiChallengeRequest(pOpponent: opponentID, pStake: stake), accessToken: accessToken)
    }

    package func reversiCancel(accessToken: String, matchID: String) async throws -> ReversiActionResponse {
        try await reversiCall(.cancel, body: ReversiMatchRequest(pMatchId: matchID), accessToken: accessToken)
    }

    package func reversiRespond(
        accessToken: String, matchID: String, accept: Bool
    ) async throws -> ReversiActionResponse {
        try await reversiCall(
            .respond, body: ReversiRespondRequest(pMatchId: matchID, pAccept: accept), accessToken: accessToken)
    }

    /// 상태(참가자 전용). 읽기처럼 보이지만 서버가 시간 초과 자동 착수를 따라잡아 판을 바꾸거나 닫을 수 있다.
    package func reversiState(
        accessToken: String, matchID: String, sinceSeq: Int = 0
    ) async throws -> ReversiActionResponse {
        try await reversiCall(
            .state, body: ReversiStateRequest(pMatchId: matchID, pSinceSeq: sinceSeq), accessToken: accessToken)
    }

    package func reversiMove(
        accessToken: String, matchID: String, expectedSeq: Int, idx: Int
    ) async throws -> ReversiActionResponse {
        try await reversiCall(
            .move, body: ReversiMoveRequest(pMatchId: matchID, pExpectedSeq: expectedSeq, pIdx: idx),
            accessToken: accessToken)
    }

    package func reversiResign(accessToken: String, matchID: String) async throws -> ReversiActionResponse {
        try await reversiCall(.resign, body: ReversiMatchRequest(pMatchId: matchID), accessToken: accessToken)
    }

    package func reversiRanking(accessToken: String) async throws -> ReversiRankingResponse {
        try await reversiCall(.ranking, body: ReversiProtocolRequest(), accessToken: accessToken)
    }

    /// 관전(읽기 전용 · 관전자 수 0). `reversi_watch_live` 가 아직 없는 서버로 한 번 접을 때 쓴다.
    package func reversiWatch(
        accessToken: String, matchID: String, sinceSeq: Int = 0
    ) async throws -> ReversiActionResponse {
        try await reversiCall(
            .watch, body: ReversiWatchRequest(pMatchId: matchID, pSinceSeq: sinceSeq), accessToken: accessToken)
    }

    /// 관전 + 생존 신호. **`reversi_state` 를 대신 부르지 마라** — 참가자 게이트에 걸려 관전자는 not_found 만 받는다.
    package func reversiWatchLive(
        accessToken: String, matchID: String, sinceSeq: Int = 0
    ) async throws -> ReversiActionResponse {
        try await reversiCall(
            .watchLive, body: ReversiWatchRequest(pMatchId: matchID, pSinceSeq: sinceSeq), accessToken: accessToken)
    }

    private func reversiCall<Body: Encodable, Response: Decodable>(
        _ rpc: ReversiWire.RPC, body: Body, accessToken: String
    ) async throws -> Response {
        try await duelRPC(
            rpc.rawValue, body: body, accessToken: accessToken, retriesDeadlockOnce: rpc.retriesDeadlockOnce)
    }
}
