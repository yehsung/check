import Foundation

// 1:1 알까기 와이어 — 요청 본문 · 응답 디코딩(SPEC v1.1 §1 · §3.5~3.7 · §4.1). 키 이름은 알까기 v1 것을 지키고 덧붙이기만 한다
// (설계 결정 D3 — `character_id` · `id` · `opponent`). 서명은 v1 순서(p_protocol 맨 뒤, D1) — 바뀌는 서명은 `alkkagi_challenge` 하나.

/// 와이어 상수 · RPC 이름표(SPEC §1 클라 RPC 15).
package nonisolated enum AlkkagiOnlineWire {
    /// 모든 요청의 `p_protocol` 이자 응답이 넘어야 하는 문턱 — 응답 protocol 이 이보다 낮으면 서버가 옛판이다(`.serverMissing`, VC-8).
    package static let protocolVersion = 2

    package enum RPC: String, CaseIterable, Sendable {
        case lobby = "alkkagi_lobby"
        case challenge = "alkkagi_challenge"
        case cancel = "alkkagi_cancel"
        case respond = "alkkagi_respond"
        case state = "alkkagi_state"
        case place = "alkkagi_place"
        case ready = "alkkagi_ready"
        case shoot = "alkkagi_shoot"
        case resign = "alkkagi_resign"
        case leave = "alkkagi_leave"
        case chatSend = "alkkagi_chat_send"
        case chatMute = "alkkagi_chat_mute"
        case ranking = "alkkagi_ranking"
        case watch = "alkkagi_watch"
        case watchLive = "alkkagi_watch_live"

        /// 서버 함수 이름 15개(계약 시험이 초안의 클라 RPC 목록과 견준다).
        package static var all: [String] { allCases.map(\.rawValue) }
    }
}

@MainActor
package protocol AlkkagiServing {
    func call(_ call: AlkkagiCall) async throws -> AlkkagiResponse
}

package enum AlkkagiServiceError: Error, Equatable, Sendable {
    case unavailable, notSignedIn, serverMissing, invalidResponse
}

/// Values are created once per action and reused by session and deadlock retries.
package enum AlkkagiCall: Equatable, Sendable {
    case lobby(users: Bool = true)
    /// `p_stake` 는 3 · 5 · 10(`AlkkagiStake`) — 와이어는 정수 그대로 싣는다(서버가 `invalid{stakes}` 로 가른다).
    case challenge(opponentID: UUID, stake: Int, actionID: UUID)
    case cancel(matchID: UUID, actionID: UUID)
    case respond(matchID: UUID, accept: Bool, actionID: UUID)
    case state(matchID: UUID, sinceChatSeq: Int = 0)
    case place(matchID: UUID, expectedPlacementRevision: Int, stoneID: Int, position: AlkkagiVector, actionID: UUID)
    case ready(matchID: UUID, expectedPlacementRevision: Int, actionID: UUID)
    case shoot(matchID: UUID, expectedRevision: Int, stoneID: Int, pull: AlkkagiVector, actionID: UUID)
    case resign(matchID: UUID, expectedRevision: Int, actionID: UUID)
    case chatSend(matchID: UUID, body: String, actionID: UUID)
    case chatMute(matchID: UUID, muted: Bool, actionID: UUID)
    case leave(matchID: UUID, expectedRevision: Int, actionID: UUID)
    case ranking
    /// 관전(잠금 0 · 진행 0). `watchLive` 는 같은 응답에 관전자 수를 더한다(`match_watch_ping`).
    case watch(matchID: UUID?)
    case watchLive(matchID: UUID?)

    package var rpc: AlkkagiOnlineWire.RPC {
        switch self {
        case .lobby: .lobby
        case .challenge: .challenge
        case .cancel: .cancel
        case .respond: .respond
        case .state: .state
        case .place: .place
        case .ready: .ready
        case .shoot: .shoot
        case .resign: .resign
        case .chatSend: .chatSend
        case .chatMute: .chatMute
        case .leave: .leave
        case .ranking: .ranking
        case .watch: .watch
        case .watchLive: .watchLive
        }
    }

    package var rpcName: String { rpc.rawValue }

    package var parameters: AlkkagiParameters {
        var parameters = AlkkagiParameters()
        switch self {
        case let .lobby(users): parameters.pUsers = users
        case let .challenge(opponentID, stake, actionID):
            parameters.pOpponent = opponentID
            parameters.pActionID = actionID
            parameters.pStake = stake
        case let .cancel(matchID, actionID):
            parameters.pMatchID = matchID
            parameters.pActionID = actionID
        case let .respond(matchID, accept, actionID):
            parameters.pMatchID = matchID
            parameters.pAccept = accept
            parameters.pActionID = actionID
        case let .state(matchID, sinceChatSeq):
            parameters.pMatchID = matchID
            parameters.pSinceChatSeq = sinceChatSeq
        case let .place(matchID, revision, stoneID, position, actionID):
            parameters.pMatchID = matchID
            parameters.pExpectedPlacementRevision = revision
            parameters.pStoneID = stoneID
            parameters.pX = position.x
            parameters.pY = position.y
            parameters.pActionID = actionID
        case let .ready(matchID, revision, actionID):
            parameters.pMatchID = matchID
            parameters.pExpectedPlacementRevision = revision
            parameters.pActionID = actionID
        case let .resign(matchID, revision, actionID),
             let .leave(matchID, revision, actionID):
            parameters.pMatchID = matchID
            parameters.pExpectedRevision = revision
            parameters.pActionID = actionID
        case let .shoot(matchID, revision, stoneID, pull, actionID):
            parameters.pMatchID = matchID
            parameters.pExpectedRevision = revision
            parameters.pStoneID = stoneID
            parameters.pPullX = pull.x
            parameters.pPullY = pull.y
            parameters.pActionID = actionID
        case let .chatSend(matchID, body, actionID):
            parameters.pMatchID = matchID
            parameters.pBody = body
            parameters.pActionID = actionID
        case let .chatMute(matchID, muted, actionID):
            parameters.pMatchID = matchID
            parameters.pMuted = muted
            parameters.pActionID = actionID
        case .ranking:
            break
        case let .watch(matchID), let .watchLive(matchID):
            parameters.pMatchID = matchID
        }
        return parameters
    }
}

package struct AlkkagiParameters: Encodable, Equatable, Sendable {
    package let pProtocol = AlkkagiOnlineWire.protocolVersion
    package var pUsers: Bool?
    package var pOpponent: UUID?
    package var pStake: Int?
    package var pMatchID: UUID?
    package var pActionID: UUID?
    package var pExpectedRevision: Int?
    package var pExpectedPlacementRevision: Int?
    package var pAccept: Bool?
    package var pSinceChatSeq: Int?
    package var pStoneID: Int?
    package var pX: Double?
    package var pY: Double?
    package var pPullX: Double?
    package var pPullY: Double?
    package var pBody: String?
    package var pMuted: Bool?

    private enum CodingKeys: String, CodingKey {
        case pProtocol = "p_protocol", pUsers = "p_users", pOpponent = "p_opponent", pStake = "p_stake"
        case pMatchID = "p_match_id", pActionID = "p_action_id"
        case pExpectedRevision = "p_expected_revision", pAccept = "p_accept"
        case pExpectedPlacementRevision = "p_expected_placement_revision"
        case pSinceChatSeq = "p_since_chat_seq", pStoneID = "p_stone_id"
        case pX = "p_x", pY = "p_y", pPullX = "p_pull_x", pPullY = "p_pull_y"
        case pBody = "p_body", pMuted = "p_muted"
    }
}

/// 서버가 내는 status 어휘(SPEC §3.5 끝). 모르는 값은 `.unknown` 으로 접는다 — status 를 더해도 프로토콜은 안 올린다.
/// `muted` 는 서버가 내지 않아 뺐다(v1.1 §4.1).
package enum AlkkagiRPCStatus: String, Codable, Equatable, Sendable {
    case ok, stale, invalid, busy, expired, forbidden, blackout, insufficient
    case notSignedIn = "not_signed_in"
    case unsupportedClient = "unsupported_client"
    case notFound = "not_found"
    case notPending = "not_pending"
    case notActive = "not_active"
    case alreadyPending = "already_pending"
    case targetBusy = "target_busy"
    case targetFocused = "target_focused"
    case targetOutdated = "target_outdated"
    case rateLimited = "rate_limited", unknown

    package init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

package enum AlkkagiMatchPhase: String, Codable, Equatable, Sendable {
    case placing, aiming, rolling, finished, unknown

    package init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

package enum AlkkagiMatchResult: String, Codable, Equatable, Sendable {
    case black, white, draw, unknown

    package init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

package struct AlkkagiPeer: Codable, Identifiable, Equatable, Sendable {
    package var id: String
    package var displayName: String
    package var avatarURL: String?
    package var characterID: String?
    package var busy: Bool?

    package init(id: String, displayName: String, avatarURL: String? = nil,
                 characterID: String? = nil, busy: Bool? = nil) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.characterID = characterID
        self.busy = busy
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName = "display_name", avatarURL = "avatar_url", characterID = "character_id", busy
    }

    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: AlkkagiWireKey.self)
        id = try values.required(String.self, "id")
        displayName = try values.required(String.self, "display_name")
        avatarURL = try values.optional(String.self, "avatar_url")
        characterID = try values.optional(String.self, "character_id")
        busy = try values.optional(Bool.self, "busy")
    }
}

/// INVITE = v1 + `stake`(SPEC §3.7). v2 신청은 늘 판돈이 있다 — nil 은 v1 옛 신청(적용 때 닫힌다)뿐이다.
package struct AlkkagiInvite: Codable, Identifiable, Equatable, Sendable {
    package var id: String
    package var opponent: AlkkagiPeer
    package var expiresAtMs: Double
    package var stake: Int?

    package init(id: String, opponent: AlkkagiPeer, expiresAtMs: Double, stake: Int? = nil) {
        self.id = id
        self.opponent = opponent
        self.expiresAtMs = expiresAtMs
        self.stake = stake
    }

    private enum CodingKeys: String, CodingKey { case id, opponent, expiresAtMs = "expires_at_ms", stake }

    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: AlkkagiWireKey.self)
        id = try values.required(String.self, "id")
        opponent = try values.required(AlkkagiPeer.self, "opponent")
        expiresAtMs = try values.required(Double.self, "expires_at_ms")
        stake = try values.optional(Int.self, "stake")
    }
}

package struct AlkkagiChatMessage: Codable, Identifiable, Equatable, Sendable {
    package var seq: Int
    package var senderID: String
    package var body: String
    package var sentAtMs: Double
    package var id: Int { seq }

    package init(seq: Int, senderID: String, body: String, sentAtMs: Double) {
        self.seq = seq
        self.senderID = senderID
        self.body = body
        self.sentAtMs = sentAtMs
    }

    private enum CodingKeys: String, CodingKey {
        case seq, senderID = "sender_id", body, sentAtMs = "sent_at_ms"
    }

    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: AlkkagiWireKey.self)
        seq = try values.required(Int.self, "seq")
        senderID = try values.required(String.self, "sender_id")
        body = try values.required(String.self, "body")
        sentAtMs = try values.required(Double.self, "sent_at_ms")
    }
}

package struct AlkkagiShot: Codable, Identifiable, Equatable, Sendable {
    package var id: String
    package var stoneID: Int
    package var pull: AlkkagiVector
    package var startedAtMs: Double
    package var steps: Int
    package var initialStones: [AlkkagiGame.Stone]
    package var duration: Double { Double(max(0, steps)) / 240 }

    package init(id: String, stoneID: Int, pull: AlkkagiVector, startedAtMs: Double,
                 steps: Int, initialStones: [AlkkagiGame.Stone]) {
        self.id = id
        self.stoneID = stoneID
        self.pull = pull
        self.startedAtMs = startedAtMs
        self.steps = steps
        self.initialStones = initialStones
    }

    private enum CodingKeys: String, CodingKey {
        case id, stoneID = "stone_id", pull, startedAtMs = "started_at_ms"
        case steps, initialStones = "initial_stones"
    }

    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: AlkkagiWireKey.self)
        id = try values.required(String.self, "id")
        stoneID = try values.required(Int.self, "stone_id")
        pull = try values.required(AlkkagiVector.self, "pull")
        startedAtMs = try values.required(Double.self, "started_at_ms")
        steps = try values.required(Int.self, "steps")
        initialStones = try values.required([AlkkagiGame.Stone].self, "initial_stones")
    }
}

package struct AlkkagiMatch: Codable, Identifiable, Equatable, Sendable {
    package var id: String
    package var revision: Int
    package var phase: AlkkagiMatchPhase
    package var currentPlayer: AlkkagiGame.Player
    package var myColor: AlkkagiGame.Player
    package var black: AlkkagiPeer
    package var white: AlkkagiPeer
    package var stones: [AlkkagiGame.Stone]
    package var deadlineMs: Double?
    package var shotCount: Int
    package var result: AlkkagiMatchResult?
    package var finishReason: String?
    package var shot: AlkkagiShot?
    package var chatSeq: Int
    package var chat: [AlkkagiChatMessage]
    package var muted: Bool
    package var placementRevision: Int
    package var myReady: Bool
    package var opponentReady: Bool

    // v2 덧붙임(SPEC §3.7 STATE 28키 — 없으면 nil). 옛 판(protocol 1 · 판돈 없음)은 전부 nil 이다.
    /// 판돈(3 · 5 · 10). nil = v1 옛 판.
    package var stake: Int?
    package var acceptedAtMs: Double?
    package var myMissedTurns: Int?
    package var opponentMissedTurns: Int?
    /// 연달아 넘기면 지는 횟수(서버 3).
    package var forfeitAfter: Int?
    /// 정산이 끝났다(`settled_at` 이 섰다).
    package var settled: Bool?
    /// 내 잔액(서버 값 — 스토어 `applyRuby` 한 곳으로 옮긴다, VC-5).
    package var rubyBalance: Int?
    /// 이 판의 관전자 수(`match__watchers` — 대국자는 ping 하지 않는다, VC-6).
    package var watchers: Int?
    /// 조준 마감 판정 유예(ms, 서버 2000). 화면 시계는 30초 그대로 — 마감 맞춤 새로고침만 이만큼 늦춘다(VC-23).
    package var graceMs: Double?

    package init(id: String, revision: Int, phase: AlkkagiMatchPhase,
                 currentPlayer: AlkkagiGame.Player, myColor: AlkkagiGame.Player,
                 black: AlkkagiPeer, white: AlkkagiPeer, stones: [AlkkagiGame.Stone],
                 deadlineMs: Double? = nil, shotCount: Int = 0, result: AlkkagiMatchResult? = nil,
                 finishReason: String? = nil, shot: AlkkagiShot? = nil, chatSeq: Int = 0,
                 chat: [AlkkagiChatMessage] = [], muted: Bool = false,
                 placementRevision: Int = 1, myReady: Bool = false, opponentReady: Bool = false,
                 stake: Int? = nil, acceptedAtMs: Double? = nil, myMissedTurns: Int? = nil,
                 opponentMissedTurns: Int? = nil, forfeitAfter: Int? = nil, settled: Bool? = nil,
                 rubyBalance: Int? = nil, watchers: Int? = nil, graceMs: Double? = nil) {
        self.id = id
        self.revision = revision
        self.phase = phase
        self.currentPlayer = currentPlayer
        self.myColor = myColor
        self.black = black
        self.white = white
        self.stones = stones
        self.deadlineMs = deadlineMs
        self.shotCount = shotCount
        self.result = result
        self.finishReason = finishReason
        self.shot = shot
        self.chatSeq = chatSeq
        self.chat = chat
        self.muted = muted
        self.placementRevision = placementRevision
        self.myReady = myReady
        self.opponentReady = opponentReady
        self.stake = stake
        self.acceptedAtMs = acceptedAtMs
        self.myMissedTurns = myMissedTurns
        self.opponentMissedTurns = opponentMissedTurns
        self.forfeitAfter = forfeitAfter
        self.settled = settled
        self.rubyBalance = rubyBalance
        self.watchers = watchers
        self.graceMs = graceMs
    }

    private enum CodingKeys: String, CodingKey {
        case id, revision, phase, currentPlayer = "current_player", myColor = "my_color"
        case black, white, stones, deadlineMs = "deadline_ms", shotCount = "shot_count"
        case result, finishReason = "finish_reason", shot, chatSeq = "chat_seq", chat, muted
        case placementRevision = "placement_revision", myReady = "my_ready", opponentReady = "opponent_ready"
        case stake, acceptedAtMs = "accepted_at_ms", myMissedTurns = "my_missed_turns"
        case opponentMissedTurns = "opponent_missed_turns", forfeitAfter = "forfeit_after", settled
        case rubyBalance = "ruby_balance", watchers, graceMs = "grace_ms"
    }

    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: AlkkagiWireKey.self)
        id = try values.required(String.self, "id")
        revision = try values.required(Int.self, "revision")
        phase = try values.required(AlkkagiMatchPhase.self, "phase")
        currentPlayer = try values.required(AlkkagiGame.Player.self, "current_player")
        myColor = try values.required(AlkkagiGame.Player.self, "my_color")
        black = try values.required(AlkkagiPeer.self, "black")
        white = try values.required(AlkkagiPeer.self, "white")
        stones = try values.required([AlkkagiGame.Stone].self, "stones")
        deadlineMs = try values.optional(Double.self, "deadline_ms")
        shotCount = try values.required(Int.self, "shot_count")
        result = try values.optional(AlkkagiMatchResult.self, "result")
        finishReason = try values.optional(String.self, "finish_reason")
        shot = try values.optional(AlkkagiShot.self, "shot")
        chatSeq = try values.required(Int.self, "chat_seq")
        chat = try values.required([AlkkagiChatMessage].self, "chat")
        muted = try values.required(Bool.self, "muted")
        if phase == .placing {
            placementRevision = try values.required(Int.self, "placement_revision")
            myReady = try values.required(Bool.self, "my_ready")
            opponentReady = try values.required(Bool.self, "opponent_ready")
        } else {
            placementRevision = try values.optional(Int.self, "placement_revision") ?? 1
            myReady = try values.optional(Bool.self, "my_ready") ?? false
            opponentReady = try values.optional(Bool.self, "opponent_ready") ?? false
        }
        stake = try values.optional(Int.self, "stake")
        acceptedAtMs = try values.optional(Double.self, "accepted_at_ms")
        myMissedTurns = try values.optional(Int.self, "my_missed_turns")
        opponentMissedTurns = try values.optional(Int.self, "opponent_missed_turns")
        forfeitAfter = try values.optional(Int.self, "forfeit_after")
        settled = try values.optional(Bool.self, "settled")
        rubyBalance = try values.optional(Int.self, "ruby_balance")
        watchers = try values.optional(Int.self, "watchers")
        graceMs = try values.optional(Double.self, "grace_ms")
    }

    package var canonicalGame: AlkkagiGame? { canonicalGame(serverNowMs: nil) }

    package func canonicalGame(serverNowMs: Double?) -> AlkkagiGame? {
        guard revision >= 0, chatSeq >= 0, deadlineMs == nil || deadlineMs!.isFinite else { return nil }
        let gamePhase: AlkkagiGame.Phase
        switch phase {
        case .placing:
            guard placementRevision >= 1, stones.count == 5,
                  stones.allSatisfy({ $0.owner == myColor && !$0.isOut }),
                  !myReady || stones.allSatisfy(\.isPlaced),
                  shot == nil, result == nil else { return nil }
            gamePhase = .placing
        case .aiming: gamePhase = .aiming
        case .rolling: gamePhase = .rolling
        case .finished: gamePhase = .finished
        case .unknown: return nil
        }
        let gameResult: AlkkagiGame.Result?
        switch result {
        case .black: gameResult = .winner(.black)
        case .white: gameResult = .winner(.white)
        case .draw: gameResult = .draw
        case .unknown: return nil
        case nil: gameResult = nil
        }
        var remaining = AlkkagiGame.turnDuration
        let referenceMs = phase == .rolling ? shot?.startedAtMs : serverNowMs
        if let referenceMs {
            guard referenceMs.isFinite else { return nil }
            if let deadlineMs { remaining = max(0, min(remaining, (deadlineMs - referenceMs) / 1000)) }
        }
        return AlkkagiGame.restore(stones: stones, currentPlayer: phase == .placing ? myColor : currentPlayer, phase: gamePhase,
                                   placementRemaining: remaining, turnRemaining: remaining,
                                   result: gameResult, shotCount: shotCount)
    }

    /// A separate visual replay. Its clock and result must never replace the server snapshot.
    package var shotReplayGame: AlkkagiGame? {
        guard shotCount > 0, let shot, !shot.id.isEmpty, shot.steps >= 0, shot.startedAtMs.isFinite,
              let shooter = shot.initialStones.first(where: { $0.id == shot.stoneID })?.owner,
              var game = AlkkagiGame.restore(stones: shot.initialStones, currentPlayer: shooter,
                                            phase: .aiming, shotCount: shotCount - 1),
              game.shoot(stoneID: shot.stoneID, pull: shot.pull) else { return nil }
        return game
    }
}

/// 모든 RPC 의 응답 한 모양(봉투 + 덧붙임). 키가 없으면 nil — 가벼운 로비(`users` 빈 배열 · `record` null)를 덮어쓰지 않는 판단은
/// 스토어가 한다(§4.3). 디코딩만 하므로 Encodable 이 아니다(인코딩하는 곳 0 — v2 에서 `Codable` → `Decodable`).
///
/// 한 응답 모양이 갈리는 두 곳:
///  · `state` — STATE(내 판, `my_color` 있음)면 `state`, WATCH(관전, `my_color` 없음)면 `watch` 에 싣는다(SPEC §3.7).
///  · RANKING — 최상위 `rows` 가 있으면 순위 응답이다. 그때 `me` 는 PEER 가 아니라 내 순위 줄이라 `ranking.me` 로 간다.
package struct AlkkagiResponse: Decodable, Equatable, Sendable {
    package var status: AlkkagiRPCStatus
    package var protocolVersion: Int
    package var serverNowMs: Double
    package var me: AlkkagiPeer?
    package var users: [AlkkagiLobbyUser]?
    package var incoming: [AlkkagiInvite]?
    package var outgoing: AlkkagiInvite?
    package var state: AlkkagiMatch?
    // v2 덧붙임(SPEC §3.7 · §4.1)
    package var rubyBalance: Int?
    package var stakes: [Int]?
    /// 문이 열렸거나 내가 capable(VC-8). false 면 '곧 열려요'(`.serverMissing`). protocol 1 응답에는 없다.
    package var doorOpen: Bool?
    /// null = 가벼운 로비(덮지 않는다).
    package var record: AlkkagiRecord?
    package var matches: [AlkkagiLiveMatch]?
    /// `insufficient{need, have, ruby_balance[, side]}` — `side` 는 "me" · "challenger".
    package var need: Int?
    package var have: Int?
    package var side: String?
    /// `already_pending{match_id}`.
    package var matchID: String?
    /// `alkkagi_ranking` 응답(그 밖에는 nil).
    package var ranking: AlkkagiRankingBoard?
    /// `alkkagi_watch` · `alkkagi_watch_live` 의 `state`(WATCH 모양).
    package var watch: AlkkagiWatchState?

    package init(status: AlkkagiRPCStatus, protocolVersion: Int = AlkkagiOnlineWire.protocolVersion, serverNowMs: Double,
                 me: AlkkagiPeer? = nil, users: [AlkkagiLobbyUser]? = nil,
                 incoming: [AlkkagiInvite]? = nil, outgoing: AlkkagiInvite? = nil,
                 state: AlkkagiMatch? = nil, rubyBalance: Int? = nil, stakes: [Int]? = nil,
                 doorOpen: Bool? = nil, record: AlkkagiRecord? = nil, matches: [AlkkagiLiveMatch]? = nil,
                 need: Int? = nil, have: Int? = nil, side: String? = nil, matchID: String? = nil,
                 ranking: AlkkagiRankingBoard? = nil, watch: AlkkagiWatchState? = nil) {
        self.status = status
        self.protocolVersion = protocolVersion
        self.serverNowMs = serverNowMs
        self.me = me
        self.users = users
        self.incoming = incoming
        self.outgoing = outgoing
        self.state = state
        self.rubyBalance = rubyBalance
        self.stakes = stakes
        self.doorOpen = doorOpen
        self.record = record
        self.matches = matches
        self.need = need
        self.have = have
        self.side = side
        self.matchID = matchID
        self.ranking = ranking
        self.watch = watch
    }

    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: AlkkagiWireKey.self)
        status = try values.required(AlkkagiRPCStatus.self, "status")
        protocolVersion = try values.optional(Int.self, "protocol") ?? 1
        serverNowMs = try values.required(Double.self, "server_now_ms")
        if values.has("rows") {
            me = nil
            let mine = try values.optional(AlkkagiMyRank.self, "me")
            let rows = try values.optional([AlkkagiLossy<AlkkagiRankEntry>].self, "rows") ?? []
            let since = try values.optional(Double.self, "record_since_ms")
            ranking = AlkkagiRankingBoard(entries: rows.compactMap(\.value), me: mine,
                                          recordSince: since.flatMap { $0 > 0 && $0.isFinite ? Date(timeIntervalSince1970: $0 / 1000) : nil })
        } else {
            me = try values.optional(AlkkagiPeer.self, "me")
            ranking = nil
        }
        users = try values.optional([AlkkagiLobbyUser].self, "users")
        incoming = try values.optional([AlkkagiInvite].self, "incoming")
        outgoing = try values.optional(AlkkagiInvite.self, "outgoing")
        if values.hasValue("state") {
            let nested = try values.nestedContainer(keyedBy: AlkkagiWireKey.self, forKey: values.wireKey("state"))
            if nested.has("my_color") {
                state = try values.required(AlkkagiMatch.self, "state")
                watch = nil
            } else {
                state = nil
                watch = try values.required(AlkkagiWatchState.self, "state")
            }
        } else {
            state = nil
            watch = nil
        }
        rubyBalance = try values.optional(Int.self, "ruby_balance")
        stakes = try values.optional([Int].self, "stakes")
        doorOpen = try values.optional(Bool.self, "door_open")
        record = try values.optional(AlkkagiRecord.self, "record")
        matches = try values.optional([AlkkagiLiveMatch].self, "matches")
        need = try values.optional(Int.self, "need")
        have = try values.optional(Int.self, "have")
        side = try values.optional(String.self, "side")
        matchID = try values.optional(String.self, "match_id")
    }
}

// MARK: - v2 값 타입의 디코딩(타입 본체는 스토어 · 순위 · 관전 파일에 있다 — 키 도우미가 이 파일 안에만 있어 여기 둔다)

extension AlkkagiLobbyUser: Decodable {
    /// USER = {id, display_name, avatar_url, character_id, is_working, in_match, capable, focus_mode}. `capable` 이 없으면 불가로 읽는다.
    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: AlkkagiWireKey.self)
        self.init(id: try values.required(String.self, "id"),
                  displayName: try values.required(String.self, "display_name"),
                  avatarURL: try values.optional(String.self, "avatar_url"),
                  characterID: try values.optional(String.self, "character_id"),
                  isWorking: try values.optional(Bool.self, "is_working") ?? false,
                  inMatch: try values.optional(Bool.self, "in_match") ?? false,
                  isCapable: try values.optional(Bool.self, "capable") ?? false,
                  isFocused: try values.optional(Bool.self, "focus_mode") ?? false)
    }
}

extension AlkkagiRecord: Decodable {
    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: AlkkagiWireKey.self)
        self.init(wins: try values.optional(Int.self, "wins") ?? 0,
                  losses: try values.optional(Int.self, "losses") ?? 0,
                  draws: try values.optional(Int.self, "draws") ?? 0)
    }
}

extension AlkkagiLiveMatch: Decodable {
    /// LIVE = {id, black: PEER, white: PEER, stake, shot_count, watchers, accepted_at_ms}.
    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: AlkkagiWireKey.self)
        let acceptedMs = try values.optional(Double.self, "accepted_at_ms")
        self.init(id: try values.required(String.self, "id"),
                  black: try values.required(AlkkagiPeer.self, "black"),
                  white: try values.required(AlkkagiPeer.self, "white"),
                  stake: try values.optional(Int.self, "stake"),
                  shotCount: try values.optional(Int.self, "shot_count") ?? 0,
                  watchers: try values.optional(Int.self, "watchers") ?? 0,
                  acceptedAt: acceptedMs.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil })
    }
}

extension AlkkagiRankEntry: Decodable {
    /// RANKING 행 = {rank, id, display_name, avatar_url, character_id, wins, losses, draws, points}. 승점이 없으면 승 − 패.
    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: AlkkagiWireKey.self)
        let wins = try values.optional(Int.self, "wins") ?? 0
        let losses = try values.optional(Int.self, "losses") ?? 0
        self.init(rank: try values.required(Int.self, "rank"),
                  id: try values.required(String.self, "id").lowercased(),
                  displayName: try values.optional(String.self, "display_name") ?? "",
                  avatarURL: try values.optional(String.self, "avatar_url"),
                  characterID: try values.optional(String.self, "character_id"),
                  wins: wins, losses: losses,
                  draws: try values.optional(Int.self, "draws") ?? 0,
                  points: try values.optional(Int.self, "points") ?? (wins - losses))
    }
}

extension AlkkagiMyRank: Decodable {
    /// RANKING `me` = {rank|null, wins, losses, draws, points}.
    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: AlkkagiWireKey.self)
        let wins = try values.optional(Int.self, "wins") ?? 0
        let losses = try values.optional(Int.self, "losses") ?? 0
        self.init(rank: try values.optional(Int.self, "rank"), wins: wins, losses: losses,
                  draws: try values.optional(Int.self, "draws") ?? 0,
                  points: try values.optional(Int.self, "points") ?? (wins - losses))
    }
}

extension AlkkagiWatchState: Decodable {
    /// WATCH(SPEC §3.7) — 둘 다 준비 전이면 `stones` 가 [] 다(숨긴 배치, D10). `watchers` 는 watch_live 만 싣는다.
    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: AlkkagiWireKey.self)
        self.init(id: try values.required(String.self, "id"),
                  revision: try values.required(Int.self, "revision"),
                  phase: try values.required(AlkkagiMatchPhase.self, "phase"),
                  currentPlayer: try values.optional(AlkkagiGame.Player.self, "current_player") ?? .black,
                  black: try values.required(AlkkagiPeer.self, "black"),
                  white: try values.required(AlkkagiPeer.self, "white"),
                  blackReady: try values.optional(Bool.self, "black_ready") ?? false,
                  whiteReady: try values.optional(Bool.self, "white_ready") ?? false,
                  stones: try values.optional([AlkkagiGame.Stone].self, "stones") ?? [],
                  deadlineMs: try values.optional(Double.self, "deadline_ms"),
                  shotCount: try values.optional(Int.self, "shot_count") ?? 0,
                  result: try values.optional(AlkkagiMatchResult.self, "result"),
                  finishReason: try values.optional(String.self, "finish_reason"),
                  shot: try values.optional(AlkkagiShot.self, "shot"),
                  stake: try values.optional(Int.self, "stake"),
                  blackMissedTurns: try values.optional(Int.self, "black_missed_turns") ?? 0,
                  whiteMissedTurns: try values.optional(Int.self, "white_missed_turns") ?? 0,
                  forfeitAfter: try values.optional(Int.self, "forfeit_after") ?? 3,
                  finishedAtMs: try values.optional(Double.self, "finished_at_ms"),
                  watchers: try values.optional(Int.self, "watchers"))
    }
}

/// 한 줄이 깨져도 나머지를 살린다(순위 행 — 길건너 `rankingBoard` 가 id·rank 없는 행을 버리는 것과 같은 뜻).
private struct AlkkagiLossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
}

/// Supports both ordinary JSONDecoder and SupabaseWorkService's convertFromSnakeCase decoder.
private struct AlkkagiWireKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private extension KeyedDecodingContainer where Key == AlkkagiWireKey {
    func wireKey(_ name: String) -> Key {
        let exact = Key(stringValue: name)
        if contains(exact) { return exact }
        let parts = name.split(separator: "_")
        let camel = String(parts.first ?? "") + parts.dropFirst().map { $0.capitalized }.joined()
        return Key(stringValue: camel)
    }

    func required<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try decode(type, forKey: wireKey(name))
    }

    func optional<T: Decodable>(_ type: T.Type, _ name: String) throws -> T? {
        try decodeIfPresent(type, forKey: wireKey(name))
    }

    /// 키가 있는가(값이 null 이어도 참).
    func has(_ name: String) -> Bool { contains(wireKey(name)) }

    /// 키가 있고 값이 null 이 아닌가.
    func hasValue(_ name: String) -> Bool {
        let key = wireKey(name)
        guard contains(key) else { return false }
        return (try? decodeNil(forKey: key)) == false
    }
}
