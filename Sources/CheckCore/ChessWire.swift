import Foundation

// 1:1 체스 RPC 의 와이어 타입(요청·응답)과 서비스 호출 11개 — `/rest/v1/rpc/chess_*`.
//
// ── 오목 와이어의 규약을 그대로 베낀다 ──
//  ① **status 만 필수이고 나머지는 전부 Optional 이다.** 비옵셔널 한 칸이면 키를 늘리기 전 서버·db push 전 창에서
//     디코드가 통째로 throw 해 대국 창이 죽는다. nil 은 "모른다" 다.
//  ② **모르는 status 는 `.unknown` 으로 접는다.** 서버가 어휘를 넓히는 날 디코드 실패로 떨어지면 실패 이유가
//     통째로 사라진다 — 접으면 화면은 일반 실패 문구를 말한다(문구 표는 `ChessNoticeText` 한 곳).
//  ③ 시각은 전부 epoch **밀리초**이고 `Double` 로 읽는다(정수로 두면 서버가 소수를 싣는 날 응답 전체가 throw 한다).
//     기기 시계 보정은 스토어 몫이다.
//
// ── 체스가 오목과 다른 자리 셋(마이그레이션 20261005160000 실측) ──
//  · **별도 받은함 RPC 가 없다.** 오목의 `gomoku_inbox` 에 해당하는 것이 `chess_lobby` 의 `me.incoming_match_id`·
//    `outgoing_match_id` 두 칸이다. 그래서 신청의 상대·판돈·만료는 그 id 로 `chess_state` 를 한 번 더 불러서 안다
//    (pending 판도 참가자에게는 상태를 준다 — `chess__state` 는 status 를 가리지 않는다).
//  · **상태 봉투가 최상위에 펼쳐지고 `state` 키에 한 번 더 들어온다.** 그래서 쓰기·조회 어느 응답이든 최상위
//    디코더로 payload 를 읽으면 된다(오목 `GomokuActionResponse` 가 두 모양을 가르던 분기가 체스에는 필요 없다).
//  · **판은 FEN 한 칸**이다(DECISIONS B5). 225자 판 문자열이 아니라 `match.fen` 이 권위이고, `moves[]` 의
//    `from`·`to` 는 **칸 번호**(rank*8+file — `ChessSquare.index` 와 같은 눈금, 실측으로 확인했다)다.

/// 체스 RPC 프로토콜 버전. 서버 `chess_protocol()` 이 1 이고, 이보다 **작으면** `unsupported_client` 다(B10).
///
/// 오목처럼 "한 숫자로 두 게이트"를 지나는 사정이 아직 없으므로 서버 값과 같은 1 이다. 올리는 날은 서버가
/// 게이트를 올리는 날이고, 그 전에 올리면 **모든 체스 RPC 가 조용히 그대로 통과한다**(1 < 1 이 거짓) —
/// 즉 이 숫자를 미리 올려도 안전하지만 아무 뜻도 없다.
package nonisolated enum ChessWire {
    package static let protocolVersion = 1
}

/// 체스 RPC 의 status 어휘. **모르는 값은 `.unknown`** 이다(머리말 ②).
/// 집합은 마이그레이션의 `comment on function public.chess_*` 열한 줄에서 베꼈다.
package nonisolated enum ChessRPCStatus: String, Equatable, Hashable, Sendable, Decodable {
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
    /// 내가 들고 있는 `ply_count` 가 서버와 다르다. **체스는 이것이 `not_your_turn` 보다 먼저다**(서버 주석 §5.4) —
    /// 차례가 FEN 에서 파생하므로 수 번호가 어긋나면 차례 판단도 믿을 수 없다. 클라가 할 일은 상태 재조회 하나다.
    case stale
    case notYourTurn = "not_your_turn"
    /// 합법 수가 아니다. 서버는 이때 **판을 전혀 건드리지 않는다**(ply·시계·차례 시작 시각 불변).
    case illegal
    /// 도착 시각이 차례 시작보다 앞이다(시계 밀림·재시도). **시간패가 아니고 수도 받지 않았다** — 다시 재야 한다.
    case retry
    /// 상대가 이미 무승부를 제안해 둔 상태에서 내가 제안했다(덮지 않는다 — 덮으면 상대 제안이 조용히 사라진다).
    case offerPending = "offer_pending"
    /// 무승부 응답인데 상대의 제안이 없다.
    case noOffer = "no_offer"
    case unknown

    package init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChessRPCStatus(rawValue: raw) ?? .unknown
    }
}

// MARK: - 요청 본문

/// chess_lobby / chess_ranking 본문. { p_protocol }.
/// **빈 객체가 아니다** — PostgREST 는 본문의 키 집합으로 함수를 고른다(오목이 데인 자리).
package struct ChessProtocolRequest: Encodable {
    package var pProtocol = ChessWire.protocolVersion
}

/// chess_challenge 본문. { p_protocol, p_opponent, p_stake }.
package struct ChessChallengeRequest: Encodable {
    package var pProtocol = ChessWire.protocolVersion
    package let pOpponent: String
    package let pStake: Int
}

/// chess_cancel / chess_resign / chess_offer_draw 본문. { p_protocol, p_match_id }.
package struct ChessMatchRequest: Encodable {
    package var pProtocol = ChessWire.protocolVersion
    package let pMatchId: String
}

/// chess_respond / chess_respond_draw 본문. { p_protocol, p_match_id, p_accept }.
package struct ChessRespondRequest: Encodable {
    package var pProtocol = ChessWire.protocolVersion
    package let pMatchId: String
    package let pAccept: Bool
}

/// chess_move 본문. { p_protocol, p_match_id, p_expected_ply, p_uci }.
/// `p_expected_ply` 는 **내가 본 `ply_count`** 다 — 다르면 서버가 stale 로 돌려보낸다(낙관적 동시성 토큰).
package struct ChessMoveRequest: Encodable {
    package var pProtocol = ChessWire.protocolVersion
    package let pMatchId: String
    package let pExpectedPly: Int
    /// `e2e4` · 승격은 소문자 한 글자(`e7e8q`). 만드는 자리는 `ChessMove.uci` 하나다.
    package let pUci: String
}

/// chess_state / chess_watch 본문. { p_protocol, p_match_id, p_since_seq }.
/// `p_since_seq` 는 서버 default(0)가 있지만 **언제나 싣는다**(키 집합이 함수를 고른다).
package struct ChessSinceRequest: Encodable {
    package var pProtocol = ChessWire.protocolVersion
    package let pMatchId: String
    package let pSinceSeq: Int
}

// MARK: - 응답 행

/// 사람 한 명. 로비 `users[]` 에만 is_working·capable·in_match 가 실리고, 상대·관전의 두 사람에는 앞 다섯만 있다.
/// `capable` 이 nil 이면 **불가**로 읽는다(스토어) — 모르는 상대에게 신청해 `target_outdated` 를 받는 것보다 낫다.
package struct ChessUserRow: Decodable, Equatable, Sendable {
    package var userId: String?
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    /// 서버 어휘('seoul'|'busan'|null). 화면 글자로 바꾸는 자리는 `ChessStore` 의 경계 둘(`peerUser`·`user(from:)`)뿐이다.
    package var center: String?
    package var isWorking: Bool?
    package var capable: Bool?
    package var inMatch: Bool?
}

/// 로비 `me` — 오목에는 없는 `incoming_match_id` 가 있다(이 파일에는 받은함 RPC 가 없다, 머리말).
package struct ChessLobbyMe: Decodable, Equatable, Sendable {
    package var rubyBalance: Int?
    package var wins: Int?
    package var losses: Int?
    package var draws: Int?
    package var activeMatchId: String?
    package var outgoingMatchId: String?
    package var incomingMatchId: String?
}

/// 로비 "지금 대결 중" 한 줄(관전 입구).
/// **판 내용이 없다** — `fen`·`ply_count` 를 서버가 아예 싣지 않는다(§10 이 소스로, 픽스처 계약이 결과로 막는다).
/// a/b 순서는 서버가 uuid 오름차순으로 고정하므로 조회마다 좌우가 흔들리지 않는다 — **색이 아니다.**
package struct ChessLobbyMatchRow: Decodable, Equatable, Sendable {
    package var matchId: String?
    package var a: ChessUserRow?
    package var b: ChessUserRow?
    package var stake: Int?
    package var startedMs: Double?
}

/// chess_lobby 응답.
package struct ChessLobbyResponse: Decodable, Equatable, Sendable {
    package let status: ChessRPCStatus
    package var serverNowMs: Double?
    package var stakes: [Int]?
    /// 한 사람에게 주는 시작 시간(ms, 300000 = 5분). 서버 상수를 앱이 베끼지 않기 위한 칸이다.
    package var initialMs: Int?
    package var incrementMs: Int?
    /// 서버가 차례쪽에 더해 주는 네트워크 유예(ms, 2000). 깃발 판정은 서버가 하고 앱은 **되묻는 시점**에만 쓴다.
    package var graceMs: Int?
    package var inviteTtlSeconds: Int?
    package var me: ChessLobbyMe?
    package var rubyBalance: Int?
    package var users: [ChessUserRow]?
    package var matches: [ChessLobbyMatchRow]?
}

/// 대국 한 판의 서버 행. 판의 권위는 **`fen` 한 칸**이다(B5).
package struct ChessMatchRow: Decodable, Equatable, Sendable {
    package var id: String?
    /// 'pending' | 'active' | 'finished' | 'declined' | 'cancelled' | 'expired'.
    package var status: String?
    package var stake: Int?
    package var white: String?
    package var black: String?
    package var challenger: String?
    package var opponent: String?
    package var plyCount: Int?
    package var fen: String?
    /// FEN 에서 파생된 차례('white'|'black'). 끝난 판에도 실려 오지만 그때는 뜻이 없다(스토어가 nil 로 접는다).
    package var turn: String?
    package var whiteMsLeft: Int?
    package var blackMsLeft: Int?
    package var whiteGraceMs: Int?
    package var blackGraceMs: Int?
    package var incrementMs: Int?
    /// 표시용 마감(차례 시작 + 차례쪽 남은 ms). 유예를 안 더한 값이고 active 가 아니면 null.
    package var deadlineMs: Double?
    package var turnStartedMs: Double?
    /// 무승부를 제안한 사람의 uuid(없으면 null). 어느 쪽이 한 수 두면 사라진다.
    package var drawOfferBy: String?
    package var result: String?
    package var endReason: String?
    package var winner: String?
    package var inviteExpiresMs: Double?
    package var startedMs: Double?
    package var finishedMs: Double?
}

/// 수 기록 한 줄. `from`·`to` 는 **칸 번호**(rank*8+file), `promo` 는 소문자 한 글자(`q`) 또는 null.
/// `ms_left` 는 그 수를 둔 뒤 **그 사람의** 남은 시간(가산 포함), `ms_spent` 는 그 수에 쓴 시간이다.
package struct ChessMoveRow: Decodable, Equatable, Sendable {
    package var seq: Int?
    package var color: String?
    package var from: Int?
    package var to: Int?
    package var promo: String?
    package var san: String?
    package var fen: String?
    package var msLeft: Int?
    package var msSpent: Int?
}

/// 참가자 시점의 대국 상태 묶음. chess_state 는 이것을 **최상위에 펼치고 `state` 키에 한 번 더** 싣고,
/// 쓰기 RPC 도 같은 모양이다 — 그래서 어느 응답이든 최상위 디코더 하나로 읽는다(머리말).
package struct ChessStatePayload: Decodable, Equatable, Sendable {
    package var match: ChessMatchRow?
    /// `p_since_seq` 이후만, seq 오름차순.
    package var moves: [ChessMoveRow]?
    package var myColor: String?
    package var opponent: ChessUserRow?
    package var rubyBalance: Int?
    /// 차례인 쪽이 체크인가. **진행 중이 아니면 null** 이다(끝난 판은 묻지 않는다).
    package var inCheck: Bool?
    /// **내 차례일 때만** 실린다(UCI 사전순). 그 밖에는 null — 상대 차례·끝난 판·관전이 전부 null 이다.
    /// 화면의 "둘 수 있는 칸"은 이 배열이 권위다(서버가 판정 주인이다).
    package var legalMoves: [String]?
    package var serverNowMs: Double?
}

/// chess_state 응답.
package struct ChessStateResponse: Decodable, Equatable, Sendable {
    package let status: ChessRPCStatus
    package var state: ChessStatePayload

    private enum CodingKeys: String, CodingKey { case status }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(ChessRPCStatus.self, forKey: .status)
        state = try ChessStatePayload(from: decoder)
    }
}

/// 쓰기 RPC 공용 응답(challenge · cancel · respond · move · resign · offer_draw · respond_draw).
///
/// 상태를 싣는 갈래는 payload 가 최상위에 펼쳐져 있으므로 **`match` 가 있을 때만** payload 를 세운다 —
/// 안 그러면 `chess_challenge__ok` 처럼 판이 없는 응답에 "키가 다 nil 인 payload" 가 서고,
/// 부르는 쪽이 `if let state` 로 가른 분기가 둘 다 참이 된다(상태가 없는데 있다고 말하는 모양).
package struct ChessActionResponse: Decodable, Equatable, Sendable {
    package let status: ChessRPCStatus
    package var state: ChessStatePayload?
    /// respond / respond_draw ok — 수락이면 true, 거절이면 false.
    package var accepted: Bool?
    /// move ok — 방금 둔 수의 SAN(화면 기보가 쓴다).
    package var san: String?
    /// move ok — 'checkmate:white' · 'stalemate' · 'threefold_repetition' … 또는 null(계속).
    /// **판정의 주인은 서버다**. 앱은 `ChessRules.outcome` 으로 같은 답이 나오는지 계약 테스트에서만 되묻는다.
    package var outcome: String?
    /// move ok — 이 수로 만든 국면이 이 판에서 몇 번째인가(3 이면 삼중 반복).
    package var repetition: Int?
    /// illegal — 서버가 거절한 그 UCI(에코).
    package var uci: String?
    /// retry — 'clock_skew'.
    package var reason: String?
    /// challenge ok / already_pending.
    package var matchId: String?
    package var inviteExpiresMs: Double?
    /// insufficient — 'me' | 'challenger'(respond 만).
    package var side: String?
    package var need: Int?
    package var have: Int?
    /// invalid — 받는 판돈 집합(서버가 알려 준다 — 앱 상수와 갈리는 날 진실은 거절한 쪽에 있다).
    package var stakes: [Int]?
    /// not_pending — 그때 판의 status(로그용. 화면 문구는 이 값을 쓰지 않는다).
    package var matchStatus: String?
    package var rubyBalance: Int?
    package var serverNowMs: Double?

    private enum CodingKeys: String, CodingKey {
        case status, state, accepted, san, outcome, repetition, uci, reason, matchId, inviteExpiresMs,
             side, need, have, stakes, matchStatus, rubyBalance, serverNowMs, match
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(ChessRPCStatus.self, forKey: .status)
        // 최상위에 `match` 가 있을 때만 상태로 읽는다(위 머리말). `state` 키가 따로 와도 같은 객체라 최상위로 읽는다.
        state = container.contains(.match) ? try ChessStatePayload(from: decoder) : nil
        accepted = try container.decodeIfPresent(Bool.self, forKey: .accepted)
        san = try container.decodeIfPresent(String.self, forKey: .san)
        outcome = try container.decodeIfPresent(String.self, forKey: .outcome)
        repetition = try container.decodeIfPresent(Int.self, forKey: .repetition)
        uci = try container.decodeIfPresent(String.self, forKey: .uci)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        matchId = try container.decodeIfPresent(String.self, forKey: .matchId)
        inviteExpiresMs = try container.decodeIfPresent(Double.self, forKey: .inviteExpiresMs)
        side = try container.decodeIfPresent(String.self, forKey: .side)
        need = try container.decodeIfPresent(Int.self, forKey: .need)
        have = try container.decodeIfPresent(Int.self, forKey: .have)
        stakes = try container.decodeIfPresent([Int].self, forKey: .stakes)
        matchStatus = try container.decodeIfPresent(String.self, forKey: .matchStatus)
        rubyBalance = try container.decodeIfPresent(Int.self, forKey: .rubyBalance)
        serverNowMs = try container.decodeIfPresent(Double.self, forKey: .serverNowMs)
    }
}

/// 순위표 한 줄. 순위는 **서버가 매긴 값**(rank() — 동률은 같은 숫자)이고 배열 순서도 서버 것이다(재정렬 금지).
package struct ChessRankRow: Decodable, Equatable, Sendable {
    package var rank: Int?
    package var userId: String?
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    package var center: String?
    package var wins: Int?
    package var losses: Int?
    package var draws: Int?
    /// 승점 = 승 − 패. 서버가 계산해 싣는다.
    package var points: Int?
}

/// 순위표의 `me`. `rank` 는 **0판이면 null**(순위 밖) — 전적은 그래도 온다(0,0,0).
package struct ChessRankingMe: Decodable, Equatable, Sendable {
    package var rank: Int?
    package var wins: Int?
    package var losses: Int?
    package var draws: Int?
    package var points: Int?
}

/// chess_ranking 응답. `record_since_ms` 는 전적 컷이고 `-infinity` 면 null 이다.
package struct ChessRankingResponse: Decodable, Equatable, Sendable {
    package let status: ChessRPCStatus
    package var serverNowMs: Double?
    package var recordSinceMs: Double?
    package var me: ChessRankingMe?
    package var rows: [ChessRankRow]?
}

/// chess_watch 응답.
///
/// **관전은 판만이다.** `my_color`·`legal_moves`·`ruby_balance`·`opponent`·`state` 중복 봉투가 **없다** —
/// 서버가 안 싣는 것이 1차 방어이고, 앱이 안 읽는 것이 2차다. 이 응답을 참가자 적용 경로(`applyState`)로
/// 절대 넣지 않는다(my_color 가 없어 조용히 무시되거나, 대국 화면이 서 버린다).
///
/// 흑·백은 **`black_user`/`white_user` 로만** 확정한다 — 로비 카드의 a/b 는 uuid 순서라 색을 말하지 않는다.
package struct ChessWatchResponse: Decodable, Equatable, Sendable {
    package let status: ChessRPCStatus
    package var serverNowMs: Double?
    package var match: ChessMatchRow?
    package var moves: [ChessMoveRow]?
    package var inCheck: Bool?
    package var blackUser: ChessUserRow?
    package var whiteUser: ChessUserRow?
}

// MARK: - 서비스 호출

/// 체스 RPC 11개. **판정은 전부 서버 몫이다** — 합법 수·차례·시간·잔액·숨김·차단을 서버가 한 트랜잭션에서 본다.
/// 앱의 `ChessRules` 는 AI 판의 권위이고 1:1 판에서는 **그리는 재료**일 뿐이다(서버 `legal_moves` 가 권위).
extension SupabaseWorkService {
    package func chessLobby(accessToken: String) async throws -> ChessLobbyResponse {
        try await chessRPC("chess_lobby", body: ChessProtocolRequest(), accessToken: accessToken)
    }

    package func chessChallenge(
        accessToken: String, opponentID: String, stake: Int
    ) async throws -> ChessActionResponse {
        try await chessRPC(
            "chess_challenge", body: ChessChallengeRequest(pOpponent: opponentID, pStake: stake),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func chessCancel(accessToken: String, matchID: String) async throws -> ChessActionResponse {
        try await chessRPC(
            "chess_cancel", body: ChessMatchRequest(pMatchId: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func chessRespond(
        accessToken: String, matchID: String, accept: Bool
    ) async throws -> ChessActionResponse {
        try await chessRPC(
            "chess_respond", body: ChessRespondRequest(pMatchId: matchID, pAccept: accept),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    /// 착수. `expectedPly` 는 내가 본 `ply_count` 다 — 어긋나면 서버가 stale 로 돌려보낸다.
    package func chessMove(
        accessToken: String, matchID: String, expectedPly: Int, uci: String
    ) async throws -> ChessActionResponse {
        try await chessRPC(
            "chess_move",
            body: ChessMoveRequest(pMatchId: matchID, pExpectedPly: expectedPly, pUci: uci),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func chessResign(accessToken: String, matchID: String) async throws -> ChessActionResponse {
        try await chessRPC(
            "chess_resign", body: ChessMatchRequest(pMatchId: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func chessOfferDraw(accessToken: String, matchID: String) async throws -> ChessActionResponse {
        try await chessRPC(
            "chess_offer_draw", body: ChessMatchRequest(pMatchId: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func chessRespondDraw(
        accessToken: String, matchID: String, accept: Bool
    ) async throws -> ChessActionResponse {
        try await chessRPC(
            "chess_respond_draw", body: ChessRespondRequest(pMatchId: matchID, pAccept: accept),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    /// 상태(참가자 전용). **읽기처럼 보이지만 서버가 깃발을 신고한다**(volatile) — 그래서 상대가 창을 닫고
    /// 사라져도 내가 보고 있는 동안 판이 끝난다. 그 사정 때문에 교착 재시도를 **켠다**(쓰기와 같은 겹).
    package func chessState(
        accessToken: String, matchID: String, sinceSeq: Int
    ) async throws -> ChessStateResponse {
        try await chessRPC(
            "chess_state", body: ChessSinceRequest(pMatchId: matchID, pSinceSeq: sinceSeq),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    /// 순위표. 서버가 **읽기 전용**이라 교착 재시도가 없다 — 실패하면 다음 계기(창 열기·주기)가 다시 읽는다.
    package func chessRanking(accessToken: String) async throws -> ChessRankingResponse {
        try await chessRPC("chess_ranking", body: ChessProtocolRequest(), accessToken: accessToken)
    }

    /// 관전. 읽기 전용이고 **`chess_state` 를 대신 부르지 마라** — 참가자 게이트에 걸려 관전자는 not_found 만 받는다.
    package func chessWatch(
        accessToken: String, matchID: String, sinceSeq: Int
    ) async throws -> ChessWatchResponse {
        try await chessRPC(
            "chess_watch", body: ChessSinceRequest(pMatchId: matchID, pSinceSeq: sinceSeq),
            accessToken: accessToken)
    }

    /// 오목 `gomokuRPC` 와 **같은 몸통**이다(헤더 구성·교착 재시도 규약). 따로 있는 까닭은 하나뿐이다:
    /// 그 함수가 `SupabaseWorkService.swift` 안의 `private` 라 이 파일에서 부를 수 없다. 규약이 갈리면
    /// 한쪽만 교착을 재시도하거나 한쪽만 헤더가 빠지므로, 고칠 일이 생기면 **두 곳을 같이** 고쳐라.
    ///
    /// `retriesDeadlockOnce` — 교착으로 죽은 트랜잭션은 Postgres 가 통째로 되돌리므로(수·차감·원장·초인종 전부 0)
    /// 재시도는 첫 시도와 같은 요청이고, 그사이 판이 바뀌었으면 서버 가드가 멱등하게 거절한다(stale·not_pending·
    /// not_active·already_pending). 교착은 상금 cron 의 등수 순 지갑 잠금과 대국의 uuid 순 잠금이 엇갈릴 때 난다.
    private func chessRPC<Body: Encodable, Response: Decodable>(
        _ name: String, body: Body, accessToken: String, retriesDeadlockOnce: Bool = false
    ) async throws -> Response {
        guard let anonKey else { throw SupabaseWorkServiceError.missingAnonKey }
        var request = URLRequest(url: try url(path: "/rest/v1/rpc/\(name)", queryItems: []))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        var attempt = 0
        while true {
            attempt += 1
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            if 200..<300 ~= statusCode {
                return try decoder.decode(Response.self, from: data)
            }
            if retriesDeadlockOnce, attempt == 1,
               postgrestErrorCode(in: data) == SupabaseWorkService.gomokuDeadlockCode {
                continue
            }
            throw serviceError(statusCode: statusCode, data: data)
        }
    }
}
