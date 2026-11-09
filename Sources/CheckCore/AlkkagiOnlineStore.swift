import Foundation
import Observation

// 1:1 알까기 대결 스토어(SPEC v1.1 §4.2 표면 · §4.3 규약 — 길건너 `CrossyDuelStore` 꼴). 서버 스냅숏이 권위다 — 이 스토어는 판을
// 진행시키지 않고 프레임 루프도 없다. 순위는 AlkkagiOnlineStoreRanking.swift, 관전은 AlkkagiOnlineStoreWatch.swift,
// 사용자 문구는 AlkkagiNoticeText.swift 한 곳.
//
// C1 뼈대(갈래 U·T 가 이 이름 그대로 선다 — 바꾸지 말고 덧붙이기만): 표면 · 와이어 · 문구 함수가 섰다. 몸통은 안전한 기본값이고
// 다섯 규칙(말풍선 문 · 가림 기록 · lobbyAgain · outsidePolling · handOffLobby) · 폴링 상수 · 판이 사라짐(VC-16) · 내 차례
// 말풍선(VC-20) · 보낸 신청 끝 안내는 C 다음 걸음이다. 판 진행(§4.6 보존 경계 — 배치·조준·굴림 · 시계 오프셋 · revision ·
// 쏘기 action_id · 대화 · 소리)은 손대지 않았다.
//
// 렌더·시험 입구: 칸은 전부 `package internal(set)` — 맥 모듈은 못 쓰고 `@testable import CheckCore` 시험은 바로 심는다
// (뒤집기 `ReversiStore` 선례). 와이어 원문으로 세우려면 `init(service:)` 에 스텁 `AlkkagiServing` 을 물리고
// `refreshLobby()` · `refreshMatch()` · `refreshRanking()` · `watch(matchID:)` 를 부른다(host 가 없으니 네트워크 0).

// MARK: - 화면 값 타입

/// 이 기기가 지금 대결을 할 수 있는가(흐름과 따로). `serverMissing` = '곧 열려요'(서버 옛판 · PGRST202 · 문 닫힘 — VC-8).
package nonisolated enum AlkkagiAvailability: Equatable, Sendable { case available, updateRequired, serverMissing }

package nonisolated enum AlkkagiStake: Int, CaseIterable, Sendable { case three = 3, five = 5, ten = 10 }

/// 판이 끝난 사유(서버 `finish_reason` 글자). 모르는 글자(`rollback` 포함)는 `.unknown`.
package nonisolated enum AlkkagiEndReason: String, Sendable {
    case ringOut = "ring_out", timeout, resign, abandoned, void, unknown
}

/// **내 기준** 결과.
package nonisolated enum AlkkagiOutcome: Equatable, Sendable { case win, loss, draw }

/// 로비 상대 한 사람(USER — `lobby__others` 집합).
package nonisolated struct AlkkagiLobbyUser: Identifiable, Equatable, Sendable {
    package let id: String
    package let displayName: String
    package let avatarURL: String?
    package let characterID: String?
    package let isWorking: Bool
    package let inMatch: Bool
    /// 서버 `capable` — 상대 앱이 1:1 알까기 v2 를 안다(문이 닫힌 동안은 모두 거짓 — 화면은 '곧 열려요' 갈래로 덮는다).
    package let isCapable: Bool
    package let isFocused: Bool

    package init(id: String, displayName: String, avatarURL: String? = nil, characterID: String? = nil,
                 isWorking: Bool = false, inMatch: Bool = false, isCapable: Bool = true, isFocused: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.characterID = characterID
        self.isWorking = isWorking
        self.inMatch = inMatch
        self.isCapable = isCapable
        self.isFocused = isFocused
    }

    /// [도전] 이 설 수 있는 사람. 보낸 신청이 있어도 켜고 서버 `already_pending` 에 맡긴다(DF#23).
    package var canBeChallenged: Bool { isCapable && !inMatch && !isFocused }
}

/// 내 전적(가벼운 로비는 덮지 않는다 — `record` null).
package nonisolated struct AlkkagiRecord: Equatable, Sendable {
    package let wins: Int
    package let losses: Int
    package let draws: Int

    package init(wins: Int, losses: Int, draws: Int) {
        self.wins = wins
        self.losses = losses
        self.draws = draws
    }

    /// 승점 = 승 − 패.
    package var points: Int { wins - losses }
}

/// 로비 "지금 대결 중" 한 판(LIVE).
package nonisolated struct AlkkagiLiveMatch: Identifiable, Equatable, Sendable {
    package let id: String
    package let black: AlkkagiPeer
    package let white: AlkkagiPeer
    package let stake: Int?
    package let shotCount: Int
    package let watchers: Int
    package let acceptedAt: Date?

    package init(id: String, black: AlkkagiPeer, white: AlkkagiPeer, stake: Int? = nil, shotCount: Int = 0,
                 watchers: Int = 0, acceptedAt: Date? = nil) {
        self.id = id
        self.black = black
        self.white = white
        self.stake = stake
        self.shotCount = shotCount
        self.watchers = watchers
        self.acceptedAt = acceptedAt
    }
}

/// 바깥(앱)에 알릴 일 — 판 시작 · 내 차례(VC-20).
package nonisolated struct AlkkagiAttention: Equatable, Sendable {
    package enum Kind: Equatable, Sendable { case matchStarted, myTurn }

    package let kind: Kind
    package let matchID: String
    /// 상대 이름. 내 차례가 상대 쏘기로 넘어온 때만 채운다 — 그 밖(시간 넘김 · 배치 끝)은 빈 글자(이름 없는 꼴, §5.8).
    package let opponentName: String

    package init(kind: Kind, matchID: String, opponentName: String) {
        self.kind = kind
        self.matchID = matchID
        self.opponentName = opponentName
    }
}

// MARK: - 스토어

/// Server snapshots are authoritative. This store never advances the game or runs a frame loop.
@Observable @MainActor
package final class AlkkagiOnlineStore {
    package internal(set) var users: [AlkkagiLobbyUser] = []
    package internal(set) var incoming: [AlkkagiInvite] = []
    package internal(set) var outgoing: AlkkagiInvite?
    package internal(set) var me: AlkkagiPeer?
    /// 내 판(SPEC 표의 `match` — 같은 값, 아래 `match`). 바뀌면 관전자 수 칩 값도 따라간다.
    package internal(set) var state: AlkkagiMatch? {
        didSet {
            let count = state?.watchers ?? 0
            if spectatorCount != count { spectatorCount = count }
        }
    }
    package private(set) var chat: [AlkkagiChatMessage] = []
    package internal(set) var notice: String?
    package internal(set) var isBusy = false
    package private(set) var isLoading = false
    package private(set) var isSendingChat = false
    package internal(set) var isWindowVisible = false
    package internal(set) var isWindowOccluded = false

    // MARK: v2 화면 상태(SPEC §4.2)

    /// `isAvailable`(Bool) 대신 — 업데이트 · 곧 열려요를 가른다. 판 진행 문(`canAct`)은 이 값을 보지 않는다(진행 판은 문이 닫혀도 끝까지).
    package internal(set) var availability: AlkkagiAvailability = .available
    package internal(set) var record: AlkkagiRecord?
    /// 서버 응답으로만 갱신(`applyRuby` — host 에도 반영).
    package internal(set) var rubyBalance: Int?
    /// 로비 "지금 대결 중"(서버 순서 그대로 · 내가 낀 판은 서버가 뺀다).
    package internal(set) var liveMatches: [AlkkagiLiveMatch] = []
    package internal(set) var hasLoadedLobby = false
    package internal(set) var lobbyLoadFailed = false
    package internal(set) var ranking: AlkkagiRankingBoard?
    /// 서버에 `alkkagi_ranking` 이 아직 없다(PGRST202).
    package internal(set) var rankingUnavailable = false
    /// 지금 보고 있는 남의 판(관전). nil = 관전 아님.
    package internal(set) var watched: AlkkagiWatchState?
    /// 내 판 관전자 수(STATE `watchers`) — 판이 없으면 0(VC-6). `state` 를 심으면 따라 바뀐다.
    package internal(set) var spectatorCount = 0

    /// 순위 적재 스위치. 기본 false — 켜는 곳은 맥 배선(T). 순위를 그리지 않는 조립(시험)이 순위를 당기지 않게.
    package var rankingEnabled = false
    /// 관전 폴링 스위치. 기본 false — 켜는 곳은 맥 배선(T).
    package var spectatorFeaturesEnabled = false
    /// 고른 판돈 기억(뒤집기 꼴 — 설계 결정 D16).
    package var selectedStake: AlkkagiStake = .three

    package var hiddenPeerIDs: Set<String> = [] {
        didSet {
            guard hiddenPeerIDs != oldValue else { return }
            users = users.filter { !isPeerHidden($0.id) }
            incoming = incoming.filter { !isPeerHidden($0.opponent.id) }
            if let outgoing, isPeerHidden(outgoing.opponent.id) { self.outgoing = nil }
            scheduleInviteExpiry()
            if isAvailable { requestSync() }
        }
    }

    @ObservationIgnored package var presentWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var dismissWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var onInviteArrived: (@MainActor (AlkkagiInvite) -> Void)?
    /// 판 시작 · 내 차례 말풍선(창이 안 보이거나 가려졌을 때만 — 규칙 ①). C1 뼈대: 판 시작만 부른다(내 차례는 C 다음 걸음).
    @ObservationIgnored package var onAttention: (@MainActor (AlkkagiAttention) -> Void)?
    @ObservationIgnored package var onMatchFinished: (@MainActor () -> Void)?
    @ObservationIgnored package var requestAttention: (@MainActor () -> Void)?

    @ObservationIgnored var service: (any AlkkagiServing)?
    /// 루비 미러를 빌리는 곳(약참조 — `attach(host:)` 가 채운다). nil 이면 스토어 값만 바꾼다.
    @ObservationIgnored package internal(set) weak var host: (any GomokuStoreHost)?
    @ObservationIgnored private var rubyServerNowMs: Double?
    @ObservationIgnored var rankingInFlight = false
    @ObservationIgnored var watchMatchID: UUID?
    @ObservationIgnored var watchGeneration = 0
    @ObservationIgnored var watchTask: Task<Void, Never>?
    @ObservationIgnored package private(set) var resetGeneration = 0
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let pollSeconds: Double
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var inviteExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var lastLobbyRefresh: Date?
    @ObservationIgnored private var lastUsersRefresh: Date?
    @ObservationIgnored private var pendingLobby = false
    @ObservationIgnored private var pendingUsers = false
    @ObservationIgnored private var pendingMatch = false
    @ObservationIgnored private var focusMatchID: UUID?
    @ObservationIgnored private var matchGeneration = 0
    @ObservationIgnored private var muteGeneration = 0
    @ObservationIgnored private var requestSequence = 0
    @ObservationIgnored private var lobbySequence = 0
    @ObservationIgnored private var clockSequence = 0
    @ObservationIgnored private var seenInviteIDs: Set<String> = []
    @ObservationIgnored private var seenFinishedMatchIDs: Set<String> = []
    @ObservationIgnored private var dismissedMatchIDs: Set<String> = []
    @ObservationIgnored private var refreshedDeadline: String?
    @ObservationIgnored private var announcedMatchIDs: Set<String> = []
    private var serverClockOffsetMs: Double?
    /// 서버와 맞물렸다(첫 성공 응답 뒤 참 · 낡은 응답 뒤 거짓). 판 진행 문 — 화면 상태는 `availability`.
    private var isAvailable = false
    /// PGRST202(서버에 함수가 없다). 판 진행 문 — 화면 상태는 `availability`.
    private var serverMissing = false

    package init(service: (any AlkkagiServing)? = nil, clock: @escaping () -> Date = Date.init,
                 pollSeconds: Double = 3) {
        self.service = service
        self.clock = clock
        self.pollSeconds = pollSeconds.isFinite && pollSeconds > 0 ? pollSeconds : 3
    }

    deinit {
        syncTask?.cancel()
        pollTask?.cancel()
        deadlineTask?.cancel()
        inviteExpiryTask?.cancel()
        watchTask?.cancel()
    }

    // MARK: 계산 칸(SPEC §4.2)

    /// SPEC 표의 이름 — `state` 와 같은 값(판 화면 코드가 `state` 로 읽어 두 이름을 둔다).
    package var match: AlkkagiMatch? { state }

    /// 차단 거울을 뺀 뒤 로비 순서(`sortedForLobby`)로 줄 세운 상대 목록.
    package var visibleUsers: [AlkkagiLobbyUser] {
        Self.sortedForLobby(hiddenPeerIDs.isEmpty ? users : users.filter { !isPeerHidden($0.id) })
    }

    /// 차단 거울을 거르고 **지금 내 판과 같은 id 를 뺀** 받은 신청(수락 뒤 늦게 온 옛 로비 응답이 되살리지 못하게).
    /// **시계를 읽지 않는다** — 만료는 스토어 타이머가 `incoming` 에서 걷는다.
    package var visibleIncomingInvites: [AlkkagiInvite] {
        let matchID = state?.id
        return incoming.filter { invite in
            !isPeerHidden(invite.opponent.id)
                && matchID.map { invite.id.caseInsensitiveCompare($0) != .orderedSame } ?? true
        }
    }

    /// 배너 · 메뉴바 점 · 사이드바 점이 읽는 받은 신청 하나(가장 최근).
    package var visibleIncoming: AlkkagiInvite? { visibleIncomingInvites.first }

    /// 확성기 배너를 미룬다(진행 판 — 배치 · 조준 · 굴림).
    package var defersMegaphoneBanner: Bool {
        switch state?.phase {
        case .placing, .aiming, .rolling: true
        case .finished, .unknown, nil: false
        }
    }

    /// 끝난 내 판의 결과(내 기준). 끝나지 않았으면 nil.
    package var outcome: AlkkagiOutcome? {
        guard let state, state.phase == .finished, let result = state.result else { return nil }
        switch result {
        case .draw: return .draw
        case .black: return state.myColor == .black ? .win : .loss
        case .white: return state.myColor == .white ? .win : .loss
        case .unknown: return nil
        }
    }

    /// 끝난 사유(서버 글자 → 열거). 끝나지 않았으면 nil.
    package var endReason: AlkkagiEndReason? {
        guard let state, state.phase == .finished else { return nil }
        return state.finishReason.map { AlkkagiEndReason(rawValue: $0) ?? .unknown }
    }

    /// 내 루비 증감: 승 `DuelFee.winnerNet(stake:)` · 패 −판돈 · 무(무효 포함) 0 · 옛 판(판돈 nil) nil.
    package var rubyDelta: Int? {
        guard let stake = state?.stake, let outcome else { return nil }
        switch outcome {
        case .win: return DuelFee.winnerNet(stake: stake)
        case .loss: return -stake
        case .draw: return 0
        }
    }

    /// 놓친 차례 경고 값(내가 1번 이상 놓쳤고 판이 진행 중일 때). 문구는 `AlkkagiNoticeText.missedTurn`.
    package var missedTurnWarning: (mine: Int, forfeitAfter: Int)? {
        guard let state, state.phase != .finished, let mine = state.myMissedTurns, mine >= 1 else { return nil }
        return (mine, state.forfeitAfter ?? 3)
    }

    /// 로비 순서(순수): (가능 ∧ 근무) 0 · 가능 1 · 대결 중 2 · 그 밖 3, 같으면 이름(`localizedStandardCompare`) · id.
    /// 가능 = `canBeChallenged`(뒤집기 CK/ReversiPanelLobby.swift:16-28 순서를 스토어 한 곳으로).
    package nonisolated static func sortedForLobby(_ users: [AlkkagiLobbyUser]) -> [AlkkagiLobbyUser] {
        func rank(_ user: AlkkagiLobbyUser) -> Int {
            if user.canBeChallenged { return user.isWorking ? 0 : 1 }
            return user.inMatch ? 2 : 3
        }
        return users.sorted { lhs, rhs in
            let a = rank(lhs), b = rank(rhs)
            if a != b { return a < b }
            let byName = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if byName != .orderedSame { return byName == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    package var estimatedServerNowMs: Double {
        let now = clock().timeIntervalSince1970 * 1000 + (serverClockOffsetMs ?? 0)
        return now.isFinite ? now : 0
    }

    package var remainingSeconds: Double {
        guard let state, let deadline = state.deadlineMs,
              state.phase != .finished, deadline.isFinite else { return 0 }
        if state.phase == .rolling {
            guard let shot = state.shot, shot.startedAtMs.isFinite else { return 0 }
            return max(0, (deadline - shot.startedAtMs) / 1000)
        }
        return max(0, (deadline - estimatedServerNowMs) / 1000)
    }

    package var isMyTurn: Bool {
        guard let state else { return false }
        switch state.phase {
        case .placing: return !state.myReady
        case .aiming: return state.currentPlayer == state.myColor
        case .rolling, .finished, .unknown: return false
        }
    }

    package var canPlace: Bool {
        canAct && isMyTurn && state?.phase == .placing
    }

    package var canShoot: Bool {
        canAct && isMyTurn && state?.phase == .aiming
    }

    private var canAct: Bool {
        guard service != nil, isAvailable, !serverMissing, !isBusy,
              serverClockOffsetMs != nil, let state, let deadline = state.deadlineMs else { return false }
        return deadline > estimatedServerNowMs
    }

    /// 판돈을 걸고 신청한다(`challenge(opponentID:)` 를 바꿈). 고른 판돈은 `selectedStake` 에 기억한다(D16).
    /// 보낸 신청이 있어도 막지 않는다 — 서버 `already_pending` 에 맡긴다(DF#23). 근무 조건은 없다.
    /// `already_pending · busy · target_busy · target_outdated · target_focused` 면 곧바로 전체 로비를 다시 읽는다(§4.3).
    package func challenge(opponentID: String, stake: AlkkagiStake) async {
        if selectedStake != stake { selectedStake = stake }
        guard !isBusy, isAvailable, availability == .available, state == nil,
              !isPeerHidden(opponentID),
              let opponent = UUID(uuidString: opponentID),
              opponent != me.flatMap({ UUID(uuidString: $0.id) }),
              users.first(where: { UUID(uuidString: $0.id) == opponent })?.canBeChallenged != false else { return }
        let generation = resetGeneration
        let response = await act(.challenge(opponentID: opponent, stake: stake.rawValue, actionID: UUID()))
        guard generation == resetGeneration, let status = response?.status else { return }
        switch status {
        case .alreadyPending, .busy, .targetBusy, .targetOutdated, .targetFocused:
            await refreshLobby()
        default:
            break
        }
    }

    /// 끝난 판을 떠나 로비로(결과 카드 [로비로]). `leaveFinishedMatch` 를 부르고 로비 · 순위를 다시 읽는다.
    package func backToLobby() {
        let generation = resetGeneration
        Task { @MainActor [weak self] in
            guard let self, generation == self.resetGeneration else { return }
            if self.state?.phase == .finished {
                await self.leaveFinishedMatch()        // 성공하면 로비를 다시 읽는다
            } else if self.state == nil {
                await self.refreshLobby()
            }
            guard generation == self.resetGeneration else { return }
            await self.refreshRanking()
        }
    }

    /// 서버 잔액을 스토어 · 앱 미러(`host.rubyBalance` — 메뉴 · 상점 · 뽑기 칩)로 옮긴다. 늦은 응답 가드(VC-5 — 길건너 RV-C-2):
    /// 이미 옮긴 잔액보다 **먼저** 서버가 만든 응답의 잔액은 버린다(정산 뒤 늦게 닿은 옛 로비가 105 를 95 로 되감지 않게).
    /// 서버 시각이 없는 응답은 그대로 옮긴다.
    func applyRuby(_ value: Int?, serverNowMs: Double?) {
        guard let value else { return }
        if let at = serverNowMs, at.isFinite, at > 0 {
            if let last = rubyServerNowMs, at < last { return }
            rubyServerNowMs = at
        }
        if rubyBalance != value { rubyBalance = value }
        if let host, host.rubyBalance != value { host.rubyBalance = value }
    }

    package func respond(inviteID: String, accept: Bool) async {
        guard !isBusy, isAvailable, availability == .available, state == nil, let id = UUID(uuidString: inviteID),
              let invite = incoming.first(where: { UUID(uuidString: $0.id) == id }) else { return }
        guard invite.expiresAtMs > estimatedServerNowMs else {
            await refreshLobby()
            return
        }
        let generation = resetGeneration
        let response = await act(.respond(matchID: id, accept: accept, actionID: UUID()))
        if generation == resetGeneration, response?.status == .ok {
            incoming.removeAll { UUID(uuidString: $0.id) == id }
        }
    }

    package func cancelChallenge() async {
        guard !isBusy, let outgoing, let id = UUID(uuidString: outgoing.id) else { return }
        let generation = resetGeneration
        let response = await act(.cancel(matchID: id, actionID: UUID()))
        if generation == resetGeneration, response?.status == .ok,
           self.outgoing.flatMap({ UUID(uuidString: $0.id) }) == id { self.outgoing = nil }
    }

    package func place(stoneID: Int, at position: AlkkagiVector) async {
        guard canPlace, let state, let id = UUID(uuidString: state.id),
              state.canonicalGame?.canPlace(stoneID: stoneID, at: position) == true else { return }
        await act(.place(matchID: id, expectedPlacementRevision: state.placementRevision, stoneID: stoneID,
                         position: position, actionID: UUID()))
    }

    package func confirmPlacement() async {
        guard canPlace, let state, let id = UUID(uuidString: state.id) else { return }
        let ownStones = state.stones.filter { $0.owner == state.myColor }
        guard ownStones.count == 5, ownStones.allSatisfy({ $0.isPlaced && !$0.isOut }) else { return }
        await act(.ready(matchID: id, expectedPlacementRevision: state.placementRevision, actionID: UUID()))
    }

    package func shoot(stoneID: Int, pull: AlkkagiVector, actionID: UUID? = nil) async {
        guard canShoot, let state, let id = UUID(uuidString: state.id),
              var game = state.canonicalGame, game.shoot(stoneID: stoneID, pull: pull) else { return }
        await act(.shoot(matchID: id, expectedRevision: state.revision, stoneID: stoneID,
                         pull: pull, actionID: actionID ?? UUID()))
    }

    package func resign() async {
        guard !isBusy, let state, state.phase != .finished,
              let id = UUID(uuidString: state.id) else { return }
        await act(.resign(matchID: id, expectedRevision: state.revision, actionID: UUID()))
    }

    package func sendChat(body: String) async {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSendingChat, isAvailable, let state, !state.muted,
              let id = UUID(uuidString: state.id) else { return }
        guard !body.isEmpty, body.unicodeScalars.count <= 100 else {
            notice = "대화는 100자까지 보낼 수 있어요."
            return
        }
        let generation = resetGeneration
        isSendingChat = true
        defer { if generation == resetGeneration { isSendingChat = false } }
        _ = await perform(.chatSend(matchID: id, body: body, actionID: UUID()))
    }

    package func setMuted(_ muted: Bool) async {
        guard !isBusy, let state, state.muted != muted,
              let id = UUID(uuidString: state.id) else { return }
        muteGeneration &+= 1
        let generation = resetGeneration
        let response = await act(.chatMute(matchID: id, muted: muted, actionID: UUID()))
        if generation == resetGeneration, response?.status == .ok,
           self.state.flatMap({ UUID(uuidString: $0.id) }) == id { self.state?.muted = muted }
    }

    package func leaveFinishedMatch() async {
        guard !isBusy, let state, state.phase == .finished,
              let id = UUID(uuidString: state.id) else { return }
        let generation = resetGeneration
        let response = await act(.leave(matchID: id, expectedRevision: state.revision, actionID: UUID()))
        guard generation == resetGeneration, response?.status == .ok,
              self.state.flatMap({ UUID(uuidString: $0.id) }) == id else { return }
        dismissedMatchIDs.insert(id.uuidString.lowercased())
        matchGeneration &+= 1
        self.state = nil
        chat = []
        focusMatchID = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        await refreshLobby()
    }

    package func refreshLobby() async { await synchronize(lobby: true, match: false, users: true) }
    package func refreshMatch() async { await synchronize(lobby: false, match: true) }

    package func refreshLobbyIfStale() {
        guard lastLobbyRefresh.map({ clock().timeIntervalSince($0) >= 60 }) ?? true else { return }
        requestSync()
    }

    package func handleSignal() { requestSync() }
    package func realtimeDidJoin() { requestSync() }
    package func systemDidWake() { requestSync() }

    package func openWindow(focusMatchID: String? = nil) {
        self.focusMatchID = focusMatchID.flatMap(UUID.init(uuidString:))
        requestSync()
        presentWindow?()
    }

    package func windowDidShow() {
        isWindowVisible = true
        if !isWindowOccluded {
            startPolling()
            scheduleDeadlineRefresh()
            requestSync()
        }
    }

    package func windowDidHide() {
        isWindowVisible = false
        isWindowOccluded = false
        stopPolling()
    }

    package func windowDidClose() {
        windowDidHide()
        if state?.phase == .finished {
            let generation = resetGeneration
            Task { @MainActor [weak self] in
                guard let self, generation == self.resetGeneration else { return }
                await self.leaveFinishedMatch()
            }
        }
    }

    package func windowOcclusionDidChange(visible: Bool) {
        isWindowOccluded = !visible
        if visible && isWindowVisible {
            startPolling()
            scheduleDeadlineRefresh()
            requestSync()
        } else {
            stopPolling()
        }
    }

    /// Clears account state but deliberately retains the injected service/weak-host adapter.
    package func reset() {
        resetGeneration &+= 1
        matchGeneration &+= 1
        muteGeneration &+= 1
        syncTask?.cancel()
        syncTask = nil
        stopPolling()
        inviteExpiryTask?.cancel()
        inviteExpiryTask = nil
        lastLobbyRefresh = nil
        lastUsersRefresh = nil
        pendingLobby = false
        pendingUsers = false
        pendingMatch = false
        focusMatchID = nil
        users = []
        incoming = []
        outgoing = nil
        me = nil
        state = nil
        chat = []
        notice = nil
        isBusy = false
        isLoading = false
        isSendingChat = false
        serverMissing = false
        isAvailable = false
        availability = .available
        record = nil
        rubyBalance = nil
        rubyServerNowMs = nil
        liveMatches = []
        hasLoadedLobby = false
        lobbyLoadFailed = false
        ranking = nil
        rankingUnavailable = false
        rankingInFlight = false
        stopWatching()
        selectedStake = .three
        announcedMatchIDs = []
        hiddenPeerIDs = []
        isWindowVisible = false
        isWindowOccluded = false
        serverClockOffsetMs = nil
        seenInviteIDs = []
        seenFinishedMatchIDs = []
        dismissedMatchIDs = []
        refreshedDeadline = nil
        requestSequence = 0
        lobbySequence = 0
        clockSequence = 0
        dismissWindow?()
    }

    private struct RequestContext {
        let generation: Int
        let matchGeneration: Int
        let muteGeneration: Int
        let sequence: Int
        let sentAtMs: Double
    }

    @discardableResult
    private func act(_ call: AlkkagiCall) async -> AlkkagiResponse? {
        guard !isBusy, service != nil else { return nil }
        let generation = resetGeneration
        isBusy = true
        notice = nil
        defer { if generation == resetGeneration { isBusy = false } }
        return await perform(call)
    }

    private func perform(_ call: AlkkagiCall) async -> AlkkagiResponse? {
        guard let service else { return nil }
        requestSequence &+= 1
        let context = RequestContext(generation: resetGeneration, matchGeneration: matchGeneration,
                                     muteGeneration: muteGeneration, sequence: requestSequence,
                                     sentAtMs: clock().timeIntervalSince1970 * 1000)
        do {
            let response = try await service.call(call)
            guard context.generation == resetGeneration, !Task.isCancelled else { return nil }
            // 응답 protocol 이 요청보다 낮으면 서버가 옛판이다(0.3.81 이 v1 서버를 만남) — '곧 열려요'(VC-8 ①).
            guard response.protocolVersion >= AlkkagiOnlineWire.protocolVersion, response.serverNowMs.isFinite else {
                isAvailable = false
                availability = .serverMissing
                notice = AlkkagiNoticeText.unavailable
                noteLobbyFailed(call)
                return nil
            }
            if context.sequence >= clockSequence {
                let receivedAtMs = clock().timeIntervalSince1970 * 1000
                let midpoint = context.sentAtMs / 2 + receivedAtMs / 2
                let offset = response.serverNowMs - midpoint
                if midpoint.isFinite, offset.isFinite {
                    serverClockOffsetMs = offset
                    clockSequence = context.sequence
                }
            }
            if response.status == .notSignedIn {
                reset()
                return nil
            }
            guard response.status != .unsupportedClient, response.status != .unknown else {
                // 문이 닫혔으면(door_open false) 내 앱 탓이 아니다 — '곧 열려요'(VC-8 ④). 그 밖은 업데이트(⑤).
                isAvailable = false
                availability = response.doorOpen == false ? .serverMissing : .updateRequired
                notice = availability == .serverMissing ? AlkkagiNoticeText.unavailable : AlkkagiNoticeText.updateMine
                noteLobbyFailed(call)
                return nil
            }
            if let state = response.state, state.canonicalGame == nil {
                isAvailable = false
                notice = AlkkagiNoticeText.tryAgain
                return nil
            }
            serverMissing = false
            isAvailable = true
            if case .lobby = call, response.status == .ok {
                // ok LOBBY 만 문 상태를 바꾼다(③ · ⑥). 남의 구버전(target_outdated)은 내 availability 를 안 바꾼다(DF#29).
                availability = response.doorOpen == false ? .serverMissing : .available
            }
            applyRuby(response.rubyBalance ?? response.state?.rubyBalance, serverNowMs: response.serverNowMs)
            apply(response, for: call, context: context)
            guard context.generation == resetGeneration else { return nil }
            notice = noticeText(for: call, response: response)
            return response
        } catch {
            guard context.generation == resetGeneration, !Task.isCancelled,
                  !(error is CancellationError) else { return nil }
            switch error as? AlkkagiServiceError {
            case .serverMissing:
                // PGRST202 — 새 서명이 아직 없다(VC-8 ②).
                serverMissing = true
                isAvailable = false
                availability = .serverMissing
                notice = AlkkagiNoticeText.unavailable
            case .notSignedIn:
                reset()
                return nil
            case .unavailable:
                isAvailable = false
                notice = AlkkagiNoticeText.signInAgain
            default:
                notice = AlkkagiNoticeText.checkConnection
            }
            noteLobbyFailed(call)
            return nil
        }
    }

    private func apply(_ response: AlkkagiResponse, for call: AlkkagiCall, context: RequestContext) {
        if context.sequence >= lobbySequence {
            if let me = response.me { self.me = me }
            // 가벼운 로비(`p_users` 거짓 — users [] · record null · matches [])는 사람 · 전적 · 대결 중을 **덮지 않는다**(§4.3).
            if case .lobby(true) = call, response.status == .ok {
                if let users = response.users { self.users = users.filter { !isPeerHidden($0.id) } }
                if let record = response.record, self.record != record { self.record = record }
                if let matches = response.matches, liveMatches != matches { liveMatches = matches }
                if !hasLoadedLobby { hasLoadedLobby = true }
                if lobbyLoadFailed { lobbyLoadFailed = false }
            }
            if let incoming = response.incoming {
                self.incoming = incoming.filter { !isPeerHidden($0.opponent.id) }
                for invite in self.incoming where seenInviteIDs.insert(invite.id.lowercased()).inserted {
                    if invite.expiresAtMs > estimatedServerNowMs { onInviteArrived?(invite) }
                    guard context.generation == resetGeneration else { return }
                }
            }
            if case let .lobby(users) = call {
                outgoing = response.outgoing
                lastLobbyRefresh = clock()
                if users { lastUsersRefresh = clock() }
            } else if response.incoming != nil || response.outgoing != nil {
                outgoing = response.outgoing
            }
            lobbySequence = context.sequence
            if let outgoing, isPeerHidden(outgoing.opponent.id) { self.outgoing = nil }
            scheduleInviteExpiry()
        }
        guard var next = response.state, let id = UUID(uuidString: next.id),
              !dismissedMatchIDs.contains(id.uuidString.lowercased()),
              next.canonicalGame != nil else { return }
        if let requestedID = call.parameters.pMatchID, requestedID != id { return }
        if let me {
            let ownID = next.myColor == .black ? next.black.id : next.white.id
            guard let ownID = UUID(uuidString: ownID), let meID = UUID(uuidString: me.id),
                  ownID == meID else { return }
        }
        let sameMatch = state.flatMap { UUID(uuidString: $0.id) } == id
        guard sameMatch || context.matchGeneration == matchGeneration else { return }
        let old = sameMatch ? state : nil
        var messages = Dictionary(chat.filter { _ in sameMatch }.map { ($0.seq, $0) }, uniquingKeysWith: { first, _ in first })
        for message in next.chat where message.seq > 0 && message.seq <= next.chatSeq
            && message.sentAtMs.isFinite && message.body.unicodeScalars.count <= 100 {
            if messages[message.seq] == nil { messages[message.seq] = message }
        }
        chat = messages.values.sorted { $0.seq < $1.seq }
        if let old, old.revision > next.revision { next = old }
        next.chatSeq = max(next.chatSeq, response.state?.chatSeq ?? 0, old?.chatSeq ?? 0)
        next.chat = chat
        if context.muteGeneration != muteGeneration, let old { next.muted = old.muted }
        if !sameMatch { matchGeneration &+= 1 }
        state = next
        focusMatchID = nil
        if next.phase == .finished, seenFinishedMatchIDs.insert(id.uuidString.lowercased()).inserted {
            onMatchFinished?()
            guard context.generation == resetGeneration else { return }
        }
        if !sameMatch, !(isWindowVisible && !isWindowOccluded) {
            presentWindow?()
            guard context.generation == resetGeneration else { return }
            requestAttention?()
            guard context.generation == resetGeneration else { return }
            // 판 id 마다 한 번 — 끝나지 않은 판이 처음 섰다(창이 안 보였거나 가려졌을 때만, 규칙 ①).
            if next.phase != .finished, announcedMatchIDs.insert(id.uuidString.lowercased()).inserted {
                let opponent = next.myColor == .black ? next.white : next.black
                onAttention?(AlkkagiAttention(kind: .matchStarted, matchID: next.id, opponentName: opponent.displayName))
                guard context.generation == resetGeneration else { return }
            }
        }
        scheduleDeadlineRefresh()
    }

    /// 응답 → 안내 줄(문구는 `AlkkagiNoticeText` 한 곳 — RPC 별 표, SPEC §4.4).
    private func noticeText(for call: AlkkagiCall, response: AlkkagiResponse) -> String? {
        let status = response.status
        switch call {
        case .challenge:
            return AlkkagiNoticeText.challenge(status, need: response.need, have: response.have, doorOpen: response.doorOpen)
        case .cancel:
            return AlkkagiNoticeText.cancel(status)
        case let .respond(_, accept, _):
            return AlkkagiNoticeText.respond(accept: accept, status, side: response.side, need: response.need,
                                             have: response.have, doorOpen: response.doorOpen)
        case .resign:
            return AlkkagiNoticeText.resign(status)
        case .state, .place, .ready, .shoot, .leave, .chatSend, .chatMute:
            return AlkkagiNoticeText.move(status)
        case .lobby, .ranking, .watch, .watchLive:
            return status == .ok ? nil : AlkkagiNoticeText.common(status)
        }
    }

    /// 전체 로비(`p_users` 참)가 실패했다 — 사람 목록 갈래의 [다시 불러오기].
    private func noteLobbyFailed(_ call: AlkkagiCall) {
        guard case .lobby(true) = call, !lobbyLoadFailed else { return }
        lobbyLoadFailed = true
    }

    private func isPeerHidden(_ id: String) -> Bool {
        hiddenPeerIDs.contains { $0.caseInsensitiveCompare(id) == .orderedSame }
    }

    /// 창이 보이는 동안의 걸음(check 통합 — 외부 기여 PR #9 를 받으며). 진행 중인 판이 있으면 **판 상태만** 읽는다 —
    /// 로비(사람 목록)를 걸음마다 부르면 판마다 서버에 사람 목록 조회가 3초에 하나씩 쌓인다. 판이 없거나 끝났으면 로비를 읽되
    /// 사람 목록은 30초에 한 번이다(받은 · 보낸 초대는 가벼운 로비가 걸음마다 싣는다). 신호 · 창 열기 · 깨어남은 `requestSync` 그대로.
    private func pollStep() {
        guard service != nil else { return }
        if let state, state.phase != .finished {
            pendingMatch = true
        } else {
            pendingLobby = true
            pendingUsers = pendingUsers || (lastUsersRefresh.map { clock().timeIntervalSince($0) >= 30 } ?? true)
            pendingMatch = true
        }
        startSyncIfNeeded()
    }

    private func requestSync() {
        guard service != nil else { return }
        pendingLobby = true
        pendingUsers = pendingUsers || (isWindowVisible && !isWindowOccluded)
        pendingMatch = true
        startSyncIfNeeded()
    }

    private func synchronize(lobby: Bool, match: Bool, users: Bool = false) async {
        guard service != nil else { return }
        pendingLobby = pendingLobby || lobby
        pendingUsers = pendingUsers || users
        pendingMatch = pendingMatch || match
        startSyncIfNeeded()
        await syncTask?.value
    }

    private func startSyncIfNeeded() {
        guard syncTask == nil else { return }
        let generation = resetGeneration
        syncTask = Task { @MainActor [weak self] in
            guard let self, generation == self.resetGeneration else { return }
            self.isLoading = true
            defer {
                if generation == self.resetGeneration {
                    self.isLoading = false
                    self.syncTask = nil
                }
            }
            while generation == self.resetGeneration, !Task.isCancelled {
                let lobby = self.pendingLobby
                let users = self.pendingUsers
                let match = self.pendingMatch
                self.pendingLobby = false
                self.pendingUsers = false
                self.pendingMatch = false
                guard lobby || match else { return }
                if lobby {
                    _ = await self.perform(.lobby(users: users))
                }
                guard generation == self.resetGeneration, !Task.isCancelled else { return }
                let focus = self.focusMatchID
                let isInvite = focus.map { id in
                    self.incoming.contains { UUID(uuidString: $0.id) == id }
                        || self.outgoing.flatMap { UUID(uuidString: $0.id) } == id
                } ?? false
                let id = isInvite ? self.state.flatMap { UUID(uuidString: $0.id) }
                    : focus ?? self.state.flatMap { UUID(uuidString: $0.id) }
                if match, let id {
                    let since = self.state.flatMap { UUID(uuidString: $0.id) } == id ? self.state?.chatSeq ?? 0 : 0
                    _ = await self.perform(.state(matchID: id, sinceChatSeq: since))
                }
            }
        }
    }

    private func startPolling() {
        guard pollTask == nil, service != nil, isWindowVisible, !isWindowOccluded else { return }
        let generation = resetGeneration
        let seconds = min(pollSeconds, Double(UInt64.max / 1_000_000_000))
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                guard let self, generation == self.resetGeneration,
                      self.isWindowVisible, !self.isWindowOccluded else { return }
                self.pollStep()
            }
        }
    }

    // Invitation badges also expire while the game window is closed, without polling.
    private func scheduleInviteExpiry() {
        inviteExpiryTask?.cancel()
        inviteExpiryTask = nil
        let now = estimatedServerNowMs
        incoming.removeAll { !$0.expiresAtMs.isFinite || $0.expiresAtMs <= now }
        if let outgoing, !outgoing.expiresAtMs.isFinite || outgoing.expiresAtMs <= now {
            self.outgoing = nil
        }
        let deadlines = incoming.map(\.expiresAtMs) + [outgoing?.expiresAtMs].compactMap { $0 }
        guard let deadline = deadlines.min() else { return }
        let seconds = max(0, (deadline - now) / 1000)
        guard seconds.isFinite, seconds < Double(UInt64.max / 1_000_000_000) else { return }
        let generation = resetGeneration
        inviteExpiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, !Task.isCancelled, generation == self.resetGeneration else { return }
            self.scheduleInviteExpiry()
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        deadlineTask?.cancel()
        deadlineTask = nil
    }

    private var deadlineKey: String? {
        guard let state, let deadline = state.deadlineMs, state.phase != .finished else { return nil }
        return "\(state.id.lowercased()):\(state.revision):\(deadline)"
    }

    private var refreshDeadlineMs: Double? {
        guard let state else { return nil }
        if state.phase == .rolling, let shot = state.shot {
            return shot.startedAtMs + shot.duration * 1000
        }
        return state.deadlineMs
    }

    private func refreshExpiredDeadline() {
        guard isWindowVisible, !isWindowOccluded, let key = deadlineKey,
              key != refreshedDeadline else { return }
        refreshedDeadline = key
        requestSync()
    }

    private func scheduleDeadlineRefresh() {
        deadlineTask?.cancel()
        deadlineTask = nil
        guard isWindowVisible, !isWindowOccluded, let deadline = refreshDeadlineMs,
              deadline.isFinite, let key = deadlineKey, key != refreshedDeadline else { return }
        let seconds = max(0, (deadline - estimatedServerNowMs) / 1000)
        guard seconds.isFinite, seconds < Double(UInt64.max / 1_000_000_000) else { return }
        let generation = resetGeneration
        deadlineTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, !Task.isCancelled, generation == self.resetGeneration,
                  self.deadlineKey == key else { return }
            self.refreshExpiredDeadline()
        }
    }
}
