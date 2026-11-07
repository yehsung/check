import Foundation

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
    case challenge(opponentID: UUID, actionID: UUID)
    case cancel(matchID: UUID, actionID: UUID)
    case respond(matchID: UUID, accept: Bool, actionID: UUID)
    case state(matchID: UUID, sinceChatSeq: Int = 0)
    case place(matchID: UUID, expectedRevision: Int, stoneID: Int, position: AlkkagiVector, actionID: UUID)
    case ready(matchID: UUID, expectedRevision: Int, actionID: UUID)
    case shoot(matchID: UUID, expectedRevision: Int, stoneID: Int, pull: AlkkagiVector, actionID: UUID)
    case resign(matchID: UUID, expectedRevision: Int, actionID: UUID)
    case chatSend(matchID: UUID, body: String, actionID: UUID)
    case chatMute(matchID: UUID, muted: Bool, actionID: UUID)
    case leave(matchID: UUID, expectedRevision: Int, actionID: UUID)

    package var rpcName: String {
        switch self {
        case .lobby: "alkkagi_lobby"
        case .challenge: "alkkagi_challenge"
        case .cancel: "alkkagi_cancel"
        case .respond: "alkkagi_respond"
        case .state: "alkkagi_state"
        case .place: "alkkagi_place"
        case .ready: "alkkagi_ready"
        case .shoot: "alkkagi_shoot"
        case .resign: "alkkagi_resign"
        case .chatSend: "alkkagi_chat_send"
        case .chatMute: "alkkagi_chat_mute"
        case .leave: "alkkagi_leave"
        }
    }

    package var parameters: AlkkagiParameters {
        var parameters = AlkkagiParameters()
        switch self {
        case let .lobby(users): parameters.pUsers = users
        case let .challenge(opponentID, actionID):
            parameters.pOpponent = opponentID
            parameters.pActionID = actionID
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
            parameters.pExpectedRevision = revision
            parameters.pStoneID = stoneID
            parameters.pX = position.x
            parameters.pY = position.y
            parameters.pActionID = actionID
        case let .ready(matchID, revision, actionID), let .resign(matchID, revision, actionID),
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
        }
        return parameters
    }
}

package struct AlkkagiParameters: Encodable, Equatable, Sendable {
    package let pProtocol = 1
    package var pUsers: Bool?
    package var pOpponent: UUID?
    package var pMatchID: UUID?
    package var pActionID: UUID?
    package var pExpectedRevision: Int?
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
        case pProtocol = "p_protocol", pUsers = "p_users", pOpponent = "p_opponent"
        case pMatchID = "p_match_id", pActionID = "p_action_id"
        case pExpectedRevision = "p_expected_revision", pAccept = "p_accept"
        case pSinceChatSeq = "p_since_chat_seq", pStoneID = "p_stone_id"
        case pX = "p_x", pY = "p_y", pPullX = "p_pull_x", pPullY = "p_pull_y"
        case pBody = "p_body", pMuted = "p_muted"
    }
}

package enum AlkkagiRPCStatus: String, Codable, Equatable, Sendable {
    case ok, stale, invalid, busy, expired, forbidden
    case notSignedIn = "not_signed_in"
    case unsupportedClient = "unsupported_client"
    case notFound = "not_found"
    case notPending = "not_pending"
    case notActive = "not_active"
    case alreadyPending = "already_pending"
    case targetBusy = "target_busy"
    case muted, rateLimited = "rate_limited", unknown

    package init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

package enum AlkkagiMatchPhase: String, Codable, Equatable, Sendable {
    case placingBlack = "placing_black", placingWhite = "placing_white"
    case aiming, rolling, finished, unknown

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

package struct AlkkagiInvite: Codable, Identifiable, Equatable, Sendable {
    package var id: String
    package var opponent: AlkkagiPeer
    package var expiresAtMs: Double

    package init(id: String, opponent: AlkkagiPeer, expiresAtMs: Double) {
        self.id = id
        self.opponent = opponent
        self.expiresAtMs = expiresAtMs
    }

    private enum CodingKeys: String, CodingKey { case id, opponent, expiresAtMs = "expires_at_ms" }

    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: AlkkagiWireKey.self)
        id = try values.required(String.self, "id")
        opponent = try values.required(AlkkagiPeer.self, "opponent")
        expiresAtMs = try values.required(Double.self, "expires_at_ms")
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

    package init(id: String, revision: Int, phase: AlkkagiMatchPhase,
                 currentPlayer: AlkkagiGame.Player, myColor: AlkkagiGame.Player,
                 black: AlkkagiPeer, white: AlkkagiPeer, stones: [AlkkagiGame.Stone],
                 deadlineMs: Double? = nil, shotCount: Int = 0, result: AlkkagiMatchResult? = nil,
                 finishReason: String? = nil, shot: AlkkagiShot? = nil, chatSeq: Int = 0,
                 chat: [AlkkagiChatMessage] = [], muted: Bool = false) {
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, revision, phase, currentPlayer = "current_player", myColor = "my_color"
        case black, white, stones, deadlineMs = "deadline_ms", shotCount = "shot_count"
        case result, finishReason = "finish_reason", shot, chatSeq = "chat_seq", chat, muted
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
    }

    package var canonicalGame: AlkkagiGame? { canonicalGame(serverNowMs: nil) }

    package func canonicalGame(serverNowMs: Double?) -> AlkkagiGame? {
        guard revision >= 0, chatSeq >= 0, deadlineMs == nil || deadlineMs!.isFinite else { return nil }
        let gamePhase: AlkkagiGame.Phase
        switch phase {
        case .placingBlack:
            guard currentPlayer == .black else { return nil }
            gamePhase = .placing
        case .placingWhite:
            guard currentPlayer == .white else { return nil }
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
        return AlkkagiGame.restore(stones: stones, currentPlayer: currentPlayer, phase: gamePhase,
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

package struct AlkkagiResponse: Codable, Equatable, Sendable {
    package var status: AlkkagiRPCStatus
    package var protocolVersion: Int
    package var serverNowMs: Double
    package var me: AlkkagiPeer?
    package var users: [AlkkagiPeer]?
    package var incoming: [AlkkagiInvite]?
    package var outgoing: AlkkagiInvite?
    package var state: AlkkagiMatch?

    package init(status: AlkkagiRPCStatus, protocolVersion: Int = 1, serverNowMs: Double,
                 me: AlkkagiPeer? = nil, users: [AlkkagiPeer]? = nil,
                 incoming: [AlkkagiInvite]? = nil, outgoing: AlkkagiInvite? = nil,
                 state: AlkkagiMatch? = nil) {
        self.status = status
        self.protocolVersion = protocolVersion
        self.serverNowMs = serverNowMs
        self.me = me
        self.users = users
        self.incoming = incoming
        self.outgoing = outgoing
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case status, protocolVersion = "protocol", serverNowMs = "server_now_ms"
        case me, users, incoming, outgoing, state
    }

    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: AlkkagiWireKey.self)
        status = try values.required(AlkkagiRPCStatus.self, "status")
        protocolVersion = try values.optional(Int.self, "protocol") ?? 1
        serverNowMs = try values.required(Double.self, "server_now_ms")
        me = try values.optional(AlkkagiPeer.self, "me")
        users = try values.optional([AlkkagiPeer].self, "users")
        incoming = try values.optional([AlkkagiInvite].self, "incoming")
        outgoing = try values.optional(AlkkagiInvite.self, "outgoing")
        state = try values.optional(AlkkagiMatch.self, "state")
    }
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
}
