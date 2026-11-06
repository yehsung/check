import Foundation

// 1:1 길건너 RPC 의 와이어 타입(요청·응답)과 서비스 호출 8개 — `/rest/v1/rpc/crossy_duel_*`.
// 계약의 정본은 설계서 crossy-duel/SPEC.md v1.3 §6.3~6.5 · §3.4 B5 이고, 서버 갈래 S 가 같은 계약으로 SQL 을 쓴다.
// **키 이름을 바꾸지 마라** — 디코더가 snake_case → camelCase 로 접으므로 `goal_at_ms` 는 `goalAtMs` 다.
//
// ── 테트리스 와이어(TetrisWire.swift)의 규약을 그대로 베낀다 ──
//  ① **status 만 필수이고 나머지는 전부 Optional 이다.** 비옵셔널 한 칸이면 서버가 키를 늘리기 전 창에서 디코드가 통째로
//     throw 해 대결 창이 죽는다. nil 은 "모른다" 다.
//  ② **모르는 status 는 `.unknown` 으로 접는다**(문구 표는 `CrossyDuelNoticeText` 한 곳).
//  ③ 시각은 전부 epoch **밀리초**이고 `Double` 로 읽는다. 기기 시계 보정은 스토어 몫이다.
//  ④ 요청 본문은 빈 `{}` 가 아니다 — `p_protocol` 을 언제나 싣는다(PostgREST 는 본문의 키 집합으로 함수를 고른다).
//  ⑤ 상태는 `{status, state}` 봉투의 `state` 키에 들어온다(펼치지 않는다).
//
// ── 길건너에서 달라진 자리 ──
//  · 로비 `p_users`(v1.1 CS-4): false 면 서버가 `me` 만 채우고 `users` 는 빈 배열 · 전적은 null 이다(가벼운 로비 — 팝오버 경로).
//  · 판 칸이 경주 칸이다(`score`·`deaths`·`goal_at_ms`) · 끝난 판의 굳은 점수 `final{me, opponent}`(내 관점).
//  · `frames` 에 능력 협상 칸이 없다(B5 — 모든 맥이 방송한다). `checkpoint_ms` 가 state 에 온다.

/// 길건너 1:1 RPC 프로토콜 버전과 함수 이름. 서버 `crossy_duel_protocol()` 이 1 이고, 이보다 **작으면** `unsupported_client` 다.
package nonisolated enum CrossyDuelWire {
    package static let protocolVersion = 1

    /// 클라 RPC 이름(SPEC §1 표 — 앞 7개 v0.1, `ranking` 은 Q1).
    package enum RPC {
        package static let lobby = "crossy_duel_lobby"
        package static let challenge = "crossy_duel_challenge"
        package static let cancel = "crossy_duel_cancel"
        package static let respond = "crossy_duel_respond"
        package static let report = "crossy_duel_report"
        package static let state = "crossy_duel_state"
        package static let resign = "crossy_duel_resign"
        package static let ranking = "crossy_duel_ranking"
        package static let all = [lobby, challenge, cancel, respond, report, state, resign, ranking]
    }
}

/// 길건너 1:1 RPC 의 status 어휘(SPEC §6.3 "status 어휘 전체" + `unknown`). **모르는 값은 `.unknown`** 이다(머리말 ②).
package nonisolated enum CrossyDuelRPCStatus: String, Equatable, Hashable, Sendable, Decodable {
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
    /// 보고 seq 가 서버 저장값 이하이거나 판이 active 가 아니다. 쓰지 않았고 `state` 는 실려 온다.
    case stale
    /// 보고·기권이 이 판을 연 기기의 것이 아니다(한 판 한 기기). 서버는 쓰지도 정산하지도 않았다.
    case otherDevice = "other_device"
    case unknown

    package init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CrossyDuelRPCStatus(rawValue: raw) ?? .unknown
    }
}

// MARK: - 요청 본문

/// crossy_duel_ranking 본문. { p_protocol }.
package struct CrossyDuelProtocolRequest: Encodable {
    package var pProtocol = CrossyDuelWire.protocolVersion

    package init() {}
}

/// crossy_duel_lobby 본문. { p_protocol, p_users }(v1.1 CS-4 — false 면 가벼운 로비).
package struct CrossyDuelLobbyRequest: Encodable {
    package var pProtocol = CrossyDuelWire.protocolVersion
    package let pUsers: Bool

    package init(pUsers: Bool) {
        self.pUsers = pUsers
    }
}

/// crossy_duel_challenge 본문. { p_protocol, p_opponent, p_stake }.
package struct CrossyDuelChallengeRequest: Encodable {
    package var pProtocol = CrossyDuelWire.protocolVersion
    package let pOpponent: String
    package let pStake: Int

    package init(pOpponent: String, pStake: Int) {
        self.pOpponent = pOpponent
        self.pStake = pStake
    }
}

/// crossy_duel_cancel / crossy_duel_state / crossy_duel_resign 본문. { p_protocol, p_match_id }.
package struct CrossyDuelMatchRequest: Encodable {
    package var pProtocol = CrossyDuelWire.protocolVersion
    package let pMatchId: String

    package init(pMatchId: String) {
        self.pMatchId = pMatchId
    }
}

/// crossy_duel_respond 본문. { p_protocol, p_match_id, p_accept }.
package struct CrossyDuelRespondRequest: Encodable {
    package var pProtocol = CrossyDuelWire.protocolVersion
    package let pMatchId: String
    package let pAccept: Bool

    package init(pMatchId: String, pAccept: Bool) {
        self.pMatchId = pMatchId
        self.pAccept = pAccept
    }
}

/// crossy_duel_report 본문. { p_protocol, p_match_id, p_seq, p_score, p_deaths }. 값은 전부 **누계**라 한 보고가 사라져도
/// 다음 보고가 같은 사실을 다시 싣는다. `p_seq` 가 서버 저장값 이하면 `stale` 로 버려진다.
package struct CrossyDuelReportRequest: Encodable {
    package var pProtocol = CrossyDuelWire.protocolVersion
    package let pMatchId: String
    package let pSeq: Int
    package let pScore: Int
    package let pDeaths: Int

    package init(matchID: String, report: CrossyDuelReportBody) {
        pMatchId = matchID
        pSeq = report.seq
        pScore = report.score
        pDeaths = report.deaths
    }
}

// MARK: - 응답 행

/// 이름 정도만 실린 사람(신청의 `from`·`to`).
package struct CrossyDuelPeerRow: Decodable, Equatable, Sendable {
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

/// 로비 `users[]` 한 줄. `capable` 이 nil 이면 **불가**로 읽는다(스토어).
package struct CrossyDuelUserRow: Decodable, Equatable, Sendable {
    package var id: String?
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    package var isWorking: Bool?
    /// 어떤 1:1 이든 진행 중인가(서버 `lobby__others` 의 busy).
    package var inMatch: Bool?
    package var capable: Bool?
    package var focusMode: Bool?

    package init(id: String? = nil, displayName: String? = nil, avatarUrl: String? = nil, character: String? = nil,
                 isWorking: Bool? = nil, inMatch: Bool? = nil, capable: Bool? = nil, focusMode: Bool? = nil) {
        self.id = id
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.character = character
        self.isWorking = isWorking
        self.inMatch = inMatch
        self.capable = capable
        self.focusMode = focusMode
    }
}

/// 신청 한 건(SPEC §6.5 INVITE). 받은 것은 `from`, 보낸 것은 `to` 가 실린다.
package struct CrossyDuelInviteRow: Decodable, Equatable, Sendable {
    package var matchId: String?
    package var from: CrossyDuelPeerRow?
    package var to: CrossyDuelPeerRow?
    package var stake: Int?
    package var expiresAtMs: Double?

    package init(matchId: String? = nil, from: CrossyDuelPeerRow? = nil, to: CrossyDuelPeerRow? = nil,
                 stake: Int? = nil, expiresAtMs: Double? = nil) {
        self.matchId = matchId
        self.from = from
        self.to = to
        self.stake = stake
        self.expiresAtMs = expiresAtMs
    }
}

/// 로비 `me`. 전적 셋이 **null 이면 가벼운 로비**다(v1.1 CS-4) — 0 으로 읽어 진짜 전적을 덮지 마라.
package struct CrossyDuelLobbyMe: Decodable, Equatable, Sendable {
    package var rubyBalance: Int?
    package var wins: Int?
    package var losses: Int?
    package var draws: Int?
    package var activeMatchId: String?
    package var incoming: [CrossyDuelInviteRow]?
    package var outgoing: CrossyDuelInviteRow?

    package init(rubyBalance: Int? = nil, wins: Int? = nil, losses: Int? = nil, draws: Int? = nil,
                 activeMatchId: String? = nil, incoming: [CrossyDuelInviteRow]? = nil, outgoing: CrossyDuelInviteRow? = nil) {
        self.rubyBalance = rubyBalance
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.activeMatchId = activeMatchId
        self.incoming = incoming
        self.outgoing = outgoing
    }
}

/// crossy_duel_lobby 응답(SPEC §6.5 LOBBY). 테트리스와 달리 `matches`(관전용)가 없다.
package struct CrossyDuelLobbyResponse: Decodable, Equatable, Sendable {
    package let status: CrossyDuelRPCStatus
    package var serverNowMs: Double?
    package var stakes: [Int]?
    package var goal: Int?
    package var maxDurationSeconds: Int?
    package var me: CrossyDuelLobbyMe?
    package var users: [CrossyDuelUserRow]?

    package init(status: CrossyDuelRPCStatus, serverNowMs: Double? = nil, stakes: [Int]? = nil, goal: Int? = nil,
                 maxDurationSeconds: Int? = nil, me: CrossyDuelLobbyMe? = nil, users: [CrossyDuelUserRow]? = nil) {
        self.status = status
        self.serverNowMs = serverNowMs
        self.stakes = stakes
        self.goal = goal
        self.maxDurationSeconds = maxDurationSeconds
        self.me = me
        self.users = users
    }
}

/// 판 상태의 한 사람(SPEC §6.5 SIDE — `me`·`opponent` 같은 모양, 부르는 사람 기준).
package struct CrossyDuelSideRow: Decodable, Equatable, Sendable {
    package var id: String?
    package var displayName: String?
    package var avatarUrl: String?
    package var character: String?
    /// 첫 보고(준비)를 냈는가.
    package var ready: Bool?
    /// 서버에 저장된 마지막 보고 번호.
    package var seq: Int?
    package var score: Int?
    package var deaths: Int?
    /// 목표 점수에 닿은 서버 시각(승패는 이 기록 순서 — SPEC §5).
    package var goalAtMs: Double?
    package var lastSeenMs: Double?

    package init(id: String? = nil, displayName: String? = nil, avatarUrl: String? = nil, character: String? = nil,
                 ready: Bool? = nil, seq: Int? = nil, score: Int? = nil, deaths: Int? = nil,
                 goalAtMs: Double? = nil, lastSeenMs: Double? = nil) {
        self.id = id
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.character = character
        self.ready = ready
        self.seq = seq
        self.score = score
        self.deaths = deaths
        self.goalAtMs = goalAtMs
        self.lastSeenMs = lastSeenMs
    }
}

/// 끝난 판의 굳은 점수(내 관점, SPEC §6.5 `final`).
package struct CrossyDuelFinalRow: Decodable, Equatable, Sendable {
    package var me: Int?
    package var opponent: Int?

    package init(me: Int? = nil, opponent: Int? = nil) {
        self.me = me
        self.opponent = opponent
    }
}

/// `state.frames` 한 칸(B5). **전 칸 Optional 이고 디코드가 절대 throw 하지 않는다** — 깨진 칸은 "꺼짐"(대체 길)으로 읽는다.
package struct CrossyDuelFramesRow: Decodable, Equatable, Sendable {
    package var on: Bool?
    /// 조인할 토픽(접두사 `realtime:` 없음). **서버가 조립한 글자를 그대로 쓴다.**
    package var topic: String?

    package init(on: Bool? = nil, topic: String? = nil) {
        self.on = on
        self.topic = topic
    }

    private enum CodingKeys: String, CodingKey { case on, topic }

    package init(from decoder: any Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        on = try? container?.decodeIfPresent(Bool.self, forKey: .on)
        topic = try? container?.decodeIfPresent(String.self, forKey: .topic)
    }

    /// 켜졌으면 조인할 토픽, 아니면 nil. `crossy_duel:` 로 시작하지 않는 토픽은 꺼짐으로 읽는다(`poke:` 채널에 싣지 않는다 — B1).
    package var activeTopic: String? {
        guard on == true, let topic, topic.hasPrefix(Self.topicPrefix), topic.count > Self.topicPrefix.count else { return nil }
        return topic
    }

    /// 서버 `'crossy_duel:' || m.id::text` 의 접두사.
    package static let topicPrefix = "crossy_duel:"
}

/// 판 상태 묶음(SPEC §6.5 STATE + B5 `checkpoint_ms`·`frames`) — report · state · respond · resign 공통.
package struct CrossyDuelStatePayload: Decodable, Equatable, Sendable {
    package var matchId: String?
    /// 'pending' | 'active' | 'finished' | 'declined' | 'cancelled' | 'expired'.
    package var status: String?
    package var stake: Int?
    /// 수락 때 서버가 뽑은 판 씨앗(pending 은 null).
    package var seed: Int?
    package var serverNowMs: Double?
    package var acceptedAtMs: Double?
    package var readyDeadlineMs: Double?
    /// null = 아직 둘 다 준비하지 않았다.
    package var startAtMs: Double?
    /// start + 판 행 max_duration_seconds(로컬 3분 얼림 기준).
    package var endAtMs: Double?
    /// end + 2초(서버 시간 끝 판정 시각).
    package var graceEndMs: Double?
    package var finishedAtMs: Double?
    /// 판 행 goal(pending 은 null). 스토어가 기대값(100)과 견준다.
    package var goal: Int?
    /// 판 행 max_duration_seconds(pending 은 null). 스토어가 기대값(180)과 견준다.
    package var maxDurationSeconds: Int?
    package var reportMs: Int?
    package var heartbeatMs: Int?
    package var silenceMs: Int?
    package var countdownMs: Int?
    /// 프레임 확인 중 체크포인트 주기(B5 — 클라는 [2000, 5000] 으로 자른다).
    package var checkpointMs: Int?
    package var me: CrossyDuelSideRow?
    package var opponent: CrossyDuelSideRow?
    /// 'challenger_win' | 'opponent_win' | 'draw' — 내 기준이 아니다. 내 승패는 `winner` 로 가른다.
    package var result: String?
    package var winner: String?
    package var endReason: String?
    /// 끝난 판의 굳은 점수(내 관점).
    package var `final`: CrossyDuelFinalRow?
    /// 'this' | 'other' | nil(모른다 — 장부로 가른다).
    package var myDevice: String?
    package var rubyBalance: Int?
    /// 판 표시 프레임(B5). 진행 중 판 · 서버 스위치 켬 · 내 기기가 'other' 가 아니면 `{on:true, topic:"crossy_duel:<id>"}`.
    package var frames: CrossyDuelFramesRow?

    package init(matchId: String? = nil, status: String? = nil, stake: Int? = nil, seed: Int? = nil,
                 serverNowMs: Double? = nil, acceptedAtMs: Double? = nil, readyDeadlineMs: Double? = nil,
                 startAtMs: Double? = nil, endAtMs: Double? = nil, graceEndMs: Double? = nil,
                 finishedAtMs: Double? = nil, goal: Int? = nil, maxDurationSeconds: Int? = nil,
                 reportMs: Int? = nil, heartbeatMs: Int? = nil, silenceMs: Int? = nil, countdownMs: Int? = nil,
                 checkpointMs: Int? = nil, me: CrossyDuelSideRow? = nil, opponent: CrossyDuelSideRow? = nil,
                 result: String? = nil, winner: String? = nil, endReason: String? = nil,
                 `final`: CrossyDuelFinalRow? = nil, myDevice: String? = nil, rubyBalance: Int? = nil,
                 frames: CrossyDuelFramesRow? = nil) {
        self.matchId = matchId
        self.status = status
        self.stake = stake
        self.seed = seed
        self.serverNowMs = serverNowMs
        self.acceptedAtMs = acceptedAtMs
        self.readyDeadlineMs = readyDeadlineMs
        self.startAtMs = startAtMs
        self.endAtMs = endAtMs
        self.graceEndMs = graceEndMs
        self.finishedAtMs = finishedAtMs
        self.goal = goal
        self.maxDurationSeconds = maxDurationSeconds
        self.reportMs = reportMs
        self.heartbeatMs = heartbeatMs
        self.silenceMs = silenceMs
        self.countdownMs = countdownMs
        self.checkpointMs = checkpointMs
        self.me = me
        self.opponent = opponent
        self.result = result
        self.winner = winner
        self.endReason = endReason
        self.`final` = `final`
        self.myDevice = myDevice
        self.rubyBalance = rubyBalance
        self.frames = frames
    }
}

/// 쓰기·조회 공용 응답(challenge · cancel · respond · report · state · resign). 상태는 **`state` 키**에 실려 온다.
package struct CrossyDuelActionResponse: Decodable, Equatable, Sendable {
    package let status: CrossyDuelRPCStatus
    package var state: CrossyDuelStatePayload?
    /// challenge ok / already_pending.
    package var matchId: String?
    package var expiresAtMs: Double?
    /// insufficient.
    package var need: Int?
    package var have: Int?
    /// insufficient — 'me' | 'challenger'(respond 만).
    package var side: String?
    /// invalid — 서버가 받는 판돈 집합.
    package var stakes: [Int]?
    /// respond ok — 수락이면 true, 거절이면 false.
    package var accepted: Bool?
    /// not_pending — 그때 판의 status(로그용).
    package var matchStatus: String?
    package var serverNowMs: Double?

    package init(status: CrossyDuelRPCStatus, state: CrossyDuelStatePayload? = nil, matchId: String? = nil,
                 expiresAtMs: Double? = nil, need: Int? = nil, have: Int? = nil, side: String? = nil,
                 stakes: [Int]? = nil, accepted: Bool? = nil, matchStatus: String? = nil, serverNowMs: Double? = nil) {
        self.status = status
        self.state = state
        self.matchId = matchId
        self.expiresAtMs = expiresAtMs
        self.need = need
        self.have = have
        self.side = side
        self.stakes = stakes
        self.accepted = accepted
        self.matchStatus = matchStatus
        self.serverNowMs = serverNowMs
    }
}

/// 순위표 한 줄. 순위는 **서버가 매긴 값**이고 배열 순서도 서버 것이다(재정렬 금지).
package struct CrossyDuelRankRow: Decodable, Equatable, Sendable {
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
package struct CrossyDuelRankingMe: Decodable, Equatable, Sendable {
    package var rank: Int?
    package var wins: Int?
    package var losses: Int?
    package var draws: Int?
    package var points: Int?
}

/// crossy_duel_ranking 응답(`tetris_ranking` 모양 그대로 — SPEC §6.3).
package struct CrossyDuelRankingResponse: Decodable, Equatable, Sendable {
    package let status: CrossyDuelRPCStatus
    package var serverNowMs: Double?
    package var recordSinceMs: Double?
    package var me: CrossyDuelRankingMe?
    package var rows: [CrossyDuelRankRow]?
}

// MARK: - 서비스 호출

/// 길건너 1:1 RPC 8개. 몸통은 공용 `duelRPC`(DuelRPC.swift) 하나다.
/// 교착 재시도는 challenge · cancel · respond · resign · state 에 켠다(SPEC §8.2). 로비·순위는 읽기 전용이라 끄고,
/// 보고는 뜨거운 길이라 끈다(실패하면 다음 걸음이 누계를 다시 보낸다).
extension SupabaseWorkService {
    /// - Parameter users: false 면 가벼운 로비(팝오버 경로 — `me` 만, v1.1 CS-4).
    package func crossyDuelLobby(accessToken: String, users: Bool = true) async throws -> CrossyDuelLobbyResponse {
        try await duelRPC(CrossyDuelWire.RPC.lobby, body: CrossyDuelLobbyRequest(pUsers: users), accessToken: accessToken)
    }

    package func crossyDuelChallenge(
        accessToken: String, opponentID: String, stake: Int
    ) async throws -> CrossyDuelActionResponse {
        try await duelRPC(
            CrossyDuelWire.RPC.challenge, body: CrossyDuelChallengeRequest(pOpponent: opponentID, pStake: stake),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func crossyDuelCancel(accessToken: String, matchID: String) async throws -> CrossyDuelActionResponse {
        try await duelRPC(
            CrossyDuelWire.RPC.cancel, body: CrossyDuelMatchRequest(pMatchId: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func crossyDuelRespond(
        accessToken: String, matchID: String, accept: Bool
    ) async throws -> CrossyDuelActionResponse {
        try await duelRPC(
            CrossyDuelWire.RPC.respond, body: CrossyDuelRespondRequest(pMatchId: matchID, pAccept: accept),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    /// 판 보고(첫 보고가 준비다).
    package func crossyDuelReport(
        accessToken: String, matchID: String, report: CrossyDuelReportBody
    ) async throws -> CrossyDuelActionResponse {
        try await duelRPC(
            CrossyDuelWire.RPC.report, body: CrossyDuelReportRequest(matchID: matchID, report: report),
            accessToken: accessToken)
    }

    /// 상태(참가자 전용). 읽기처럼 보이지만 서버가 시간 판정을 돌려 판을 닫을 수 있다.
    package func crossyDuelState(accessToken: String, matchID: String) async throws -> CrossyDuelActionResponse {
        try await duelRPC(
            CrossyDuelWire.RPC.state, body: CrossyDuelMatchRequest(pMatchId: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func crossyDuelResign(accessToken: String, matchID: String) async throws -> CrossyDuelActionResponse {
        try await duelRPC(
            CrossyDuelWire.RPC.resign, body: CrossyDuelMatchRequest(pMatchId: matchID),
            accessToken: accessToken, retriesDeadlockOnce: true)
    }

    package func crossyDuelRanking(accessToken: String) async throws -> CrossyDuelRankingResponse {
        try await duelRPC(CrossyDuelWire.RPC.ranking, body: CrossyDuelProtocolRequest(), accessToken: accessToken)
    }
}
