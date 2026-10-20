import Foundation

// 1:1 테트리스 RPC 의 와이어 타입(요청·응답)과 서비스 호출 8개 — `/rest/v1/rpc/tetris_*` (v0.3.60).
// 계약의 정본은 설계서 §2.4·§2.5 이고, 서버 레인이 같은 계약으로 SQL(20261021120000_tetris_duel.sql)을 쓴다.
// **키 이름을 바꾸지 마라** — 디코더가 snake_case → camelCase 로 접으므로 `garbage_sent` 는 `garbageSent` 다.
//
// ── 오목·체스 와이어의 규약을 그대로 베낀다 ──
//  ① **status 만 필수이고 나머지는 전부 Optional 이다.** 비옵셔널 한 칸이면 서버가 키를 늘리기 전·db push 전 창에서
//     디코드가 통째로 throw 해 대결 창이 죽는다. nil 은 "모른다" 다.
//  ② **모르는 status 는 `.unknown` 으로 접는다.** 서버가 어휘를 넓히는 날 디코드 실패로 떨어지면 실패 이유가
//     통째로 사라진다 — 접으면 화면은 일반 실패 문구를 말한다(문구 표는 `TetrisDuelNoticeText` 한 곳).
//  ③ 시각은 전부 epoch **밀리초**이고 `Double` 로 읽는다. 기기 시계 보정은 스토어 몫이다.
//  ④ 요청 본문은 **빈 `{}` 가 아니다** — `p_protocol` 을 언제나 싣는다(PostgREST 는 본문의 키 집합으로 함수를 고른다).
//
// ── 테트리스가 체스와 다른 자리 ──
//  · **상태는 `state` 키에 들어온다(펼치지 않는다).** 체스는 상태를 최상위에 펼치고 `state` 에 한 번 더 실었지만
//    테트리스는 `{status, state}` 한 모양이다. 그래서 응답 타입은 `state` 키를 그대로 읽는다.
//  · **로비가 신청을 통째로 준다.** `me.incoming` 은 배열(`{match_id, from{id,display_name}, stake, expires_at_ms}`),
//    `me.outgoing` 은 하나(`to`) — 체스처럼 id 만 받아 상태를 한 번 더 부르지 않는다.
//  · 사람 행의 id 키가 `user_id` 가 아니라 **`id`** 다(로비 users · 순위 rows · state me/opponent 전부).
//  · 비로그인은 `unauthorized` 가 아니라 **`not_signed_in`** 이다.

/// 테트리스 RPC 프로토콜 버전. 서버 `tetris_protocol()` 이 1 이고, 이보다 **작으면** `unsupported_client` 다.
package nonisolated enum TetrisWire {
    package static let protocolVersion = 1
}

/// 테트리스 RPC 의 status 어휘. **모르는 값은 `.unknown`** 이다(머리말 ②). 집합은 설계서 §2.4 에서 베꼈다.
package nonisolated enum TetrisRPCStatus: String, Equatable, Hashable, Sendable, Decodable {
    case ok
    case notSignedIn = "not_signed_in"
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
    /// 보고 seq 가 서버 저장값 이하이거나 판이 active 가 아니다. **쓰지 않았고** `state` 는 실려 온다 —
    /// 클라가 할 일은 그 상태를 옮기고 seq 를 따라잡는 것 하나다.
    case stale
    case unknown

    package init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TetrisRPCStatus(rawValue: raw) ?? .unknown
    }
}

// MARK: - 요청 본문

/// tetris_lobby / tetris_ranking 본문. { p_protocol }.
package struct TetrisProtocolRequest: Encodable {
    package var pProtocol = TetrisWire.protocolVersion
}

/// tetris_challenge 본문. { p_protocol, p_opponent, p_stake }.
package struct TetrisChallengeRequest: Encodable {
    package var pProtocol = TetrisWire.protocolVersion
    package let pOpponent: String
    package let pStake: Int
}

/// tetris_cancel / tetris_state / tetris_resign 본문. { p_protocol, p_match_id }.
package struct TetrisMatchRequest: Encodable {
    package var pProtocol = TetrisWire.protocolVersion
    package let pMatchId: String
}

/// tetris_respond 본문. { p_protocol, p_match_id, p_accept }.
package struct TetrisRespondRequest: Encodable {
    package var pProtocol = TetrisWire.protocolVersion
    package let pMatchId: String
    package let pAccept: Bool
}

/// tetris_report 본문(1초 하트비트 겸). 값은 전부 **누계**라 한 보고가 사라져도 다음 보고가 같은 사실을 다시 싣는다.
/// `p_seq` 가 서버 저장값 이하면 `stale` 로 버려진다(쓰지 않는다).
package struct TetrisReportRequest: Encodable {
    package var pProtocol = TetrisWire.protocolVersion
    package let pMatchId: String
    package let pSeq: Int
    /// 보이는 판 200글자(`TetrisDuelBoard`).
    package let pBoard: String
    package let pLines: Int
    package let pGarbageSent: Int
    package let pGarbageApplied: Int
    package let pPending: Int
    package let pToppedOut: Bool

    package init(matchID: String, report: TetrisDuelReport) {
        pMatchId = matchID
        pSeq = report.seq
        pBoard = report.board
        pLines = report.lines
        pGarbageSent = report.garbageSent
        pGarbageApplied = report.garbageApplied
        pPending = report.pending
        pToppedOut = report.toppedOut
    }
}

// MARK: - 응답 행

/// 이름 정도만 실린 사람(신청의 `from`·`to` · 로비 matches 의 `a`·`b`).
package struct TetrisPeerRow: Decodable, Equatable, Sendable {
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
/// `target_outdated` 를 받는 것보다 낫다.
package struct TetrisUserRow: Decodable, Equatable, Sendable {
    package var id: String?
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    package var isWorking: Bool?
    /// 오목·체스·테트리스 중 하나라도 진행 중인가(서버 `chess__busy` — 한 사람은 한 판만).
    package var inMatch: Bool?
    package var capable: Bool?
    package var focusMode: Bool?
}

/// 신청 한 건. 받은 것은 `from`, 보낸 것은 `to` 가 실린다.
package struct TetrisInviteRow: Decodable, Equatable, Sendable {
    package var matchId: String?
    package var from: TetrisPeerRow?
    package var to: TetrisPeerRow?
    package var stake: Int?
    package var expiresAtMs: Double?
}

/// 로비 `me`.
package struct TetrisLobbyMe: Decodable, Equatable, Sendable {
    package var rubyBalance: Int?
    package var wins: Int?
    package var losses: Int?
    package var draws: Int?
    package var activeMatchId: String?
    package var incoming: [TetrisInviteRow]?
    package var outgoing: TetrisInviteRow?
}

/// 로비 "지금 대결 중" 한 줄. 판 내용은 없다(관전은 이번 범위가 아니다 — D8). a/b 는 uuid 오름차순이다.
package struct TetrisLobbyMatchRow: Decodable, Equatable, Sendable {
    package var id: String?
    package var a: TetrisPeerRow?
    package var b: TetrisPeerRow?
    package var stake: Int?
    package var startedAtMs: Double?
}

/// tetris_lobby 응답.
package struct TetrisLobbyResponse: Decodable, Equatable, Sendable {
    package let status: TetrisRPCStatus
    package var serverNowMs: Double?
    package var stakes: [Int]?
    package var me: TetrisLobbyMe?
    package var users: [TetrisUserRow]?
    package var matches: [TetrisLobbyMatchRow]?
}

/// 판 상태의 한 사람(`me`·`opponent` 같은 모양). 부르는 사람 기준이다.
package struct TetrisPlayerRow: Decodable, Equatable, Sendable {
    package var id: String?
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    /// 첫 보고(준비)를 냈는가.
    package var ready: Bool?
    /// 서버에 저장된 마지막 보고 번호.
    package var seq: Int?
    /// 보이는 판 200글자(아직 보고가 없으면 null).
    package var board: String?
    package var lines: Int?
    /// 보낸 공격 누계(서버가 단조·상한으로 자른 값).
    package var garbageSent: Int?
    /// 상대 공격 중 받아들였다고 보고한 누계.
    package var garbageApplied: Int?
    package var pending: Int?
    package var lastSeenMs: Double?
    package var toppedOut: Bool?
}

/// 판 상태 묶음(§2.5) — report · state · respond · resign 공통. `me`/`opponent` 는 부르는 사람 기준이다.
package struct TetrisStatePayload: Decodable, Equatable, Sendable {
    package var matchId: String?
    /// 'pending' | 'active' | 'finished' | 'declined' | 'cancelled' | 'expired'.
    package var status: String?
    package var stake: Int?
    /// 수락 때 서버가 뽑은 판 시드(0…2147483647). 두 사람이 같은 값으로 엔진을 만든다 → 조각 순서가 같다.
    package var seed: Int?
    package var serverNowMs: Double?
    package var acceptedAtMs: Double?
    /// null = 아직 둘 다 준비하지 않았다.
    package var startAtMs: Double?
    /// 수락 + 30초. 그때까지 둘 다 준비하지 않으면 서버가 무승부(no_show)로 판돈을 돌려준다.
    package var readyDeadlineMs: Double?
    /// start_at + 480초(판 상한).
    package var maxEndMs: Double?
    package var finishedAtMs: Double?
    package var me: TetrisPlayerRow?
    package var opponent: TetrisPlayerRow?
    /// 'challenger_win' | 'opponent_win' | 'draw' — 내 기준이 아니다. 내 승패는 `winner` 로 가른다.
    package var result: String?
    /// 이긴 사람의 uuid(무승부면 null).
    package var winner: String?
    package var endReason: String?
    package var rubyBalance: Int?
}

/// 쓰기·조회 공용 응답(challenge · cancel · respond · report · state · resign).
/// 상태는 **`state` 키**에 실려 온다(머리말 — 펼치지 않는다).
package struct TetrisActionResponse: Decodable, Equatable, Sendable {
    package let status: TetrisRPCStatus
    package var state: TetrisStatePayload?
    /// respond ok — 수락이면 true, 거절이면 false.
    package var accepted: Bool?
    /// challenge ok / already_pending.
    package var matchId: String?
    package var expiresAtMs: Double?
    /// insufficient — 'me' | 'challenger'(respond 만).
    package var side: String?
    package var need: Int?
    package var have: Int?
    /// invalid — 서버가 받는 판돈 집합.
    package var stakes: [Int]?
    /// not_pending — 그때 판의 status(로그용).
    package var matchStatus: String?
    package var rubyBalance: Int?
    package var serverNowMs: Double?
}

/// 순위표 한 줄. 순위는 **서버가 매긴 값**이고 배열 순서도 서버 것이다(재정렬 금지).
package struct TetrisRankRow: Decodable, Equatable, Sendable {
    package var rank: Int?
    package var id: String?
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    package var wins: Int?
    package var losses: Int?
    package var draws: Int?
    package var points: Int?
}

/// 순위표의 `me`(0판이면 rank null).
package struct TetrisRankingMe: Decodable, Equatable, Sendable {
    package var rank: Int?
    package var wins: Int?
    package var losses: Int?
    package var draws: Int?
    package var points: Int?
}

/// tetris_ranking 응답.
package struct TetrisRankingResponse: Decodable, Equatable, Sendable {
    package let status: TetrisRPCStatus
    package var serverNowMs: Double?
    package var recordSinceMs: Double?
    package var me: TetrisRankingMe?
    package var rows: [TetrisRankRow]?
}

// MARK: - 서비스 호출

/// 테트리스 RPC 8개. 몸통은 공용 `duelRPC`(DuelRPC.swift) 하나다.
/// 교착 재시도는 **쓰기 전부 + 상태 조회**에 켠다(`tetris_state` 는 시간 판정 `tetris__due` 를 돌리고 지갑 잠금을 쥔다).
/// 로비·순위는 읽기 전용이라 끈다.
extension SupabaseWorkService {
    package func tetrisLobby(accessToken: String) async throws -> TetrisLobbyResponse {
        try await duelRPC("tetris_lobby", body: TetrisProtocolRequest(), accessToken: accessToken)
    }

    package func tetrisChallenge(
        accessToken: String, opponentID: String, stake: Int
    ) async throws -> TetrisActionResponse {
        try await duelRPC(
            "tetris_challenge", body: TetrisChallengeRequest(pOpponent: opponentID, pStake: stake),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func tetrisCancel(accessToken: String, matchID: String) async throws -> TetrisActionResponse {
        try await duelRPC(
            "tetris_cancel", body: TetrisMatchRequest(pMatchId: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func tetrisRespond(
        accessToken: String, matchID: String, accept: Bool
    ) async throws -> TetrisActionResponse {
        try await duelRPC(
            "tetris_respond", body: TetrisRespondRequest(pMatchId: matchID, pAccept: accept),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    /// 판 보고(1초 하트비트 겸). 첫 보고가 준비다.
    package func tetrisReport(
        accessToken: String, matchID: String, report: TetrisDuelReport
    ) async throws -> TetrisActionResponse {
        try await duelRPC(
            "tetris_report", body: TetrisReportRequest(matchID: matchID, report: report),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    /// 상태(참가자 전용). 읽기처럼 보이지만 서버가 시간 판정(침묵·상한·준비 마감)을 돌려 판을 닫을 수 있다.
    package func tetrisState(accessToken: String, matchID: String) async throws -> TetrisActionResponse {
        try await duelRPC(
            "tetris_state", body: TetrisMatchRequest(pMatchId: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func tetrisResign(accessToken: String, matchID: String) async throws -> TetrisActionResponse {
        try await duelRPC(
            "tetris_resign", body: TetrisMatchRequest(pMatchId: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func tetrisRanking(accessToken: String) async throws -> TetrisRankingResponse {
        try await duelRPC("tetris_ranking", body: TetrisProtocolRequest(), accessToken: accessToken)
    }
}
