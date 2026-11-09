import Foundation
import Observation

// 1:1 알까기 대결 스토어(SPEC v1.1 §4.2 표면 · §4.3 규약 — 길건너 `CrossyDuelStore` 꼴). 서버 스냅숏이 권위다 — 이 스토어는 판을
// 진행시키지 않고 프레임 루프도 없다. 순위는 AlkkagiOnlineStoreRanking.swift, 관전은 AlkkagiOnlineStoreWatch.swift,
// 사용자 문구는 AlkkagiNoticeText.swift 한 곳.
//
// 규약(§4.3 — 메모리 duel-store-alert-doorbell-rules 다섯 규칙):
//  ① 말풍선 문 = 창이 안 보이거나 가려졌을 때만 `onAttention` · `onInviteArrived`(`attentionDoorIsOpen`)
//  ② `windowDidShow` 는 열린 채 가려진 창의 가림 기록을 지우지 않는다 · `windowDidHide`/`windowDidClose` 가 지운다
//  ③ 도는 조회에 온 부름은 깃발로 합쳐 끝난 뒤 한 바퀴 더(합친 부름이 사람 목록을 원하면 그 바퀴는 전체 로비)
//  ④ 폴링 걸음 조회는 취소 밖 Task `.value`(`outsidePolling`) · 걸음 사이 창 보임 · 가림 · 취소 가드(`pollTick`)
//  ⑤ 조회 엔진은 부른 쪽의 작업이 아니다(독립 Task) — 부른 쪽이 취소돼도 합친 부름까지 끝까지 돈다
// 폴링: 판 중 `pollSeconds`(3초) 박자 그대로 판 상태만 · 판 밖 보낸 신청 5초 · 전체 로비 30초 · 순위 60초 · 메뉴 가벼운 로비 30초 ·
// 관전 2초. 조준 마감 새로고침은 마감 + 판정 유예(VC-23). 판 진행(§4.6 보존 경계 — 배치·조준·굴림 · 시계 오프셋 · revision ·
// 쏘기 action_id · 대화 · 소리)은 0.3.80 그대로다.
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
    /// 새 받은 신청(신청 id 마다 한 번). **말풍선 문**(규칙 ①)이 열렸을 때만 — 보이고 안 가려진 창은 로비 카드가 말한다.
    @ObservationIgnored package var onInviteArrived: (@MainActor (AlkkagiInvite) -> Void)?
    /// 판 시작 · 내 차례 말풍선(창이 안 보이거나 가려졌을 때만 — 규칙 ①).
    @ObservationIgnored package var onAttention: (@MainActor (AlkkagiAttention) -> Void)?
    @ObservationIgnored package var onMatchFinished: (@MainActor () -> Void)?
    @ObservationIgnored package var requestAttention: (@MainActor () -> Void)?

    // MARK: 폴링 상수(SPEC §4.3 — 다수 값. 판 중 걸음은 `pollSeconds` 박자 그대로)

    /// 보낸 신청 확인(`alkkagi_state(outgoing.id)`).
    package nonisolated static let outgoingPollSeconds: TimeInterval = 5
    /// 전체 로비(사람 목록 · 전적 · 지금 대결 중).
    package nonisolated static let lobbyPollSeconds: TimeInterval = 30
    /// 메뉴 팝오버의 가벼운 로비(`p_users` false).
    package nonisolated static let menuLobbyThrottleSeconds: TimeInterval = 30
    /// 순위(주 스위치 `rankingEnabled`).
    package nonisolated static let rankingPollSeconds: TimeInterval = 60
    /// 판 밖 걸음 간격 상한(초) — 5초 · 30초 · 60초 문턱을 이 간격으로 잰다. 판 중 걸음은 `pollSeconds`.
    /// 시험은 크게 재우고 `pollTick(at:)` 을 직접 밟는다.
    @ObservationIgnored package var outsidePollStepSeconds: TimeInterval = 1

    /// 마지막 **전체** 로비 조회 시각(가벼운 로비는 세지 않는다).
    @ObservationIgnored package var lastLobbyRequestAt: Date = .distantPast
    @ObservationIgnored package var lastOutgoingRequestAt: Date = .distantPast
    @ObservationIgnored package var lastMenuLobbyAt: Date = .distantPast
    @ObservationIgnored package var lastRankingRequestAt: Date = .distantPast

    @ObservationIgnored var service: (any AlkkagiServing)?
    /// 루비 미러를 빌리는 곳(약참조 — `attach(host:)` 가 채운다). nil 이면 스토어 값만 바꾼다.
    @ObservationIgnored package internal(set) weak var host: (any GomokuStoreHost)?
    @ObservationIgnored private var rubyServerNowMs: Double?
    @ObservationIgnored var rankingInFlight = false
    @ObservationIgnored var watchMatchID: UUID?
    @ObservationIgnored var watchGeneration = 0
    @ObservationIgnored var watchTask: Task<Void, Never>?
    @ObservationIgnored package private(set) var resetGeneration = 0
    @ObservationIgnored let clock: () -> Date
    @ObservationIgnored private let pollSeconds: Double
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pollToken = 0
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var inviteExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var pendingLobby = false
    @ObservationIgnored private var pendingUsers = false
    @ObservationIgnored private var pendingMatch = false
    /// 보낸 신청 한 건의 상태 조회(5초 걸음 — 엔진 안에서 로비 다음, 판 상태 앞).
    @ObservationIgnored private var pendingOutgoingID: UUID?
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
    /// 이번 응답이 정한 안내(보낸 신청 끝 · 판이 사라짐). 응답 꼬리의 RPC 별 문구가 덮지 않는다.
    @ObservationIgnored private var eventNotice: String?
    /// 이 기기에서 보낸 신청을 새로 세울 때마다 오른다. 그보다 **먼저** 나간 로비 · 확인 응답이 방금 보낸 신청을 지우지 않게(길건너 꼴).
    @ObservationIgnored private var outgoingRevision = 0
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

    /// 말풍선 문(규칙 ①) — 창이 안 보이거나 가려졌다. 보이고 안 가려진 창은 화면이 스스로 말한다.
    package var attentionDoorIsOpen: Bool { !(isWindowVisible && !isWindowOccluded) }

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

    /// 조준 중이고 내 차례인 상태(VC-20 — 내 차례 말풍선은 이 상태로 **들어설 때**만 운다).
    package nonisolated static func isMyAim(_ match: AlkkagiMatch) -> Bool {
        match.phase == .aiming && match.currentPlayer == match.myColor
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
        case .ok:
            // 첫 보낸 신청 확인은 5초 뒤(방금 응답이 그 상태를 실어 왔다).
            lastOutgoingRequestAt = clock()
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

    /// 받은 신청에 응답한다. **떠나지 않은 끝난 판은 응답을 막지 않는다**(RV2-C-1 — 창을 닫은 채 끝난 판은 스토어와 서버 로비에
    /// 남는다. 그 사이 온 신청의 배너 [수락]·[거절]이 서버에 닿지 않고 조용히 사라지면 안 된다 — 다른 1:1 게임도 판 유무를 보지 않는다).
    /// 수락이면 그 끝난 판을 먼저 떠난다(남겨 두면 새 판이 끝난 뒤 서버 로비가 옛 결과를 다시 싣는다). 거절은 결과 카드를 그대로 둔다.
    package func respond(inviteID: String, accept: Bool) async {
        guard !isBusy, isAvailable, availability == .available, state.map({ $0.phase == .finished }) ?? true,
              let id = UUID(uuidString: inviteID),
              incoming.contains(where: { UUID(uuidString: $0.id) == id }) else { return }
        let generation = resetGeneration
        if accept, state?.phase == .finished {
            await leaveFinishedMatch()            // 실패해도 응답은 보낸다 — 새 판 응답이 끝난 판을 갈아 끼운다
            guard generation == resetGeneration, !isBusy else { return }
        }
        guard let invite = incoming.first(where: { UUID(uuidString: $0.id) == id }) else { return }
        guard invite.expiresAtMs > estimatedServerNowMs else {
            await refreshLobby()
            return
        }
        let response = await act(.respond(matchID: id, accept: accept, actionID: UUID()))
        guard generation == resetGeneration, let status = response?.status else { return }
        switch status {
        case .ok, .notFound, .notPending, .expired, .invalid, .forbidden:
            // 받을 수 없게 된 카드는 걷는다(수락 성공은 판이 열리며 나머지 카드도 걷힌다).
            if incoming.contains(where: { UUID(uuidString: $0.id) == id }) {
                incoming.removeAll { UUID(uuidString: $0.id) == id }
                scheduleInviteExpiry()
            }
        default:
            break
        }
    }

    /// 보낸 신청 취소. `not_pending` · `expired` · `stale` 은 수락과 엇갈렸다는 뜻일 수 있다 — 전체 로비를 다시 읽는다(VC-13).
    package func cancelChallenge() async {
        guard !isBusy, let outgoing, let id = UUID(uuidString: outgoing.id) else { return }
        let generation = resetGeneration
        let response = await act(.cancel(matchID: id, actionID: UUID()))
        guard generation == resetGeneration, let status = response?.status else { return }
        switch status {
        case .ok, .notFound, .notPending, .expired:
            if self.outgoing.flatMap({ UUID(uuidString: $0.id) }) == id {
                self.outgoing = nil
                scheduleInviteExpiry()
            }
        default:
            break
        }
        switch status {
        case .notPending, .expired, .stale:
            await refreshLobby()
        default:
            break
        }
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
        clearMatch()
        await refreshLobby()
    }

    /// 창 경로 → 사람 목록까지(`p_users` true).
    package func refreshLobby() async { await synchronize(lobby: true, match: false, users: true) }
    /// 팝오버 · 창 밖 경로 → 가벼운 로비(`p_users` false — 사람 · 전적 · 대결 중을 덮지 않는다).
    package func refreshLightLobby() async { await synchronize(lobby: true, match: false, users: false) }
    package func refreshMatch() async { await synchronize(lobby: false, match: true) }

    /// 메뉴 팝오버 경로 → 가벼운 로비(`p_users` false). 스로틀 30초.
    package func refreshLobbyIfStale() {
        guard service != nil else { return }
        let now = clock()
        guard now.timeIntervalSince(lastMenuLobbyAt) >= Self.menuLobbyThrottleSeconds else { return }
        lastMenuLobbyAt = now
        pendingLobby = true
        startSyncIfNeeded()
    }

    package func handleSignal() { requestSync() }
    package func realtimeDidJoin() { requestSync() }
    package func systemDidWake() { requestSync() }

    package func openWindow(focusMatchID: String? = nil) {
        self.focusMatchID = focusMatchID.flatMap(UUID.init(uuidString:))
        requestSync()
        presentWindow?()
    }

    /// 창이 실제로 보이기 시작했다. **열린 채 가려진 창을 다시 부른 길이면 가림 기록을 그대로 둔다**(규칙 ② — 판 시작의
    /// `presentWindow` 가 가린 창을 '보임'으로 되돌려 말풍선 문을 닫지 않게). 숨었던 창이 처음 뜨면 옛 가림 기록은 지운다.
    package func windowDidShow() {
        let reshownWhileOccluded = isWindowVisible && isWindowOccluded
        if !isWindowVisible { isWindowVisible = true }
        if !reshownWhileOccluded, isWindowOccluded { isWindowOccluded = false }
        guard !isWindowOccluded else { return }
        startPolling()
        scheduleDeadlineRefresh()
        requestSync()
        if rankingEnabled, !hasLiveMatch, clock().timeIntervalSince(lastRankingRequestAt) >= 1 {
            Task { @MainActor [weak self] in await self?.refreshRanking() }
        }
    }

    package func windowDidHide() {
        isWindowVisible = false
        isWindowOccluded = false
        stopPolling()
        scheduleDeadlineRefresh()          // 굴림 중이면 끝에 한 번(RV2-C-3) — 그 밖은 서지 않는다
    }

    package func windowDidClose() {
        windowDidHide()
        stopWatching()
        if state?.phase == .finished {
            let generation = resetGeneration
            Task { @MainActor [weak self] in
                guard let self, generation == self.resetGeneration else { return }
                await self.leaveFinishedMatch()
            }
        }
    }

    /// 창의 가림 상태가 바뀌었다. 폴링을 멈추고 되살린다 — `isWindowVisible` 은 건드리지 않는다.
    package func windowOcclusionDidChange(visible: Bool) {
        isWindowOccluded = !visible
        if visible && isWindowVisible {
            startPolling()
            scheduleDeadlineRefresh()
            requestSync()
        } else {
            stopPolling()
            scheduleDeadlineRefresh()      // 굴림 중이면 끝에 한 번(RV2-C-3)
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
        lastLobbyRequestAt = .distantPast
        lastOutgoingRequestAt = .distantPast
        lastMenuLobbyAt = .distantPast
        lastRankingRequestAt = .distantPast
        pendingLobby = false
        pendingUsers = false
        pendingMatch = false
        pendingOutgoingID = nil
        eventNotice = nil
        outgoingRevision = 0
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
        let outgoingRevision: Int
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
                                     sentAtMs: clock().timeIntervalSince1970 * 1000,
                                     outgoingRevision: outgoingRevision)
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
            eventNotice = nil
            apply(response, for: call, context: context)
            guard context.generation == resetGeneration else { return nil }
            if let eventNotice {
                notice = eventNotice
                self.eventNotice = nil
            } else if case let .set(text) = noticeUpdate(for: call, response: response) {
                notice = text
            }
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
        // 판 · 신청이 서버에서 사라졌다(상대 계정 삭제 cascade 등 — VC-16). 내 판이면 내리고 로비로.
        if response.status == .notFound, let requested = call.parameters.pMatchID {
            dropMatchOrInvite(requested)
        }
        let doorOpen = attentionDoorIsOpen
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
                let fresh = incoming.filter { !isPeerHidden($0.opponent.id) }
                if case .lobby = call {
                    self.incoming = fresh
                } else {
                    // 한 판의 응답(수락 · 거절 · 상태)은 그 신청 하나만 싣는다 — 다른 받은 신청 카드를 지우지 않게 고쳐 넣기만.
                    var merged = self.incoming
                    for invite in fresh {
                        if let index = merged.firstIndex(where: { $0.id.caseInsensitiveCompare(invite.id) == .orderedSame }) {
                            merged[index] = invite
                        } else {
                            merged.insert(invite, at: 0)
                        }
                    }
                    if self.incoming != merged { self.incoming = merged }
                }
                for invite in fresh where seenInviteIDs.insert(invite.id.lowercased()).inserted {
                    // 말풍선 문(규칙 ①) — 보이고 안 가려진 창이면 로비 카드가 말한다.
                    if doorOpen, invite.expiresAtMs > estimatedServerNowMs { onInviteArrived?(invite) }
                    guard context.generation == resetGeneration else { return }
                }
            }
            let predates = context.outgoingRevision < outgoingRevision
            if case .lobby = call {
                if response.status == .ok { noteOutgoing(response.outgoing, from: response, predates: predates) }
            } else if case let .state(requested, _) = call, response.status == .ok,
                      let sent = outgoing, UUID(uuidString: sent.id) == requested {
                // 보낸 신청 확인 걸음(5초) — 대기면 outgoing 이 실려 오고, 끝났으면(거절 · 만료 · 취소) 빠진다.
                noteOutgoing(response.outgoing, from: response, predates: predates)
            } else if response.incoming != nil || response.outgoing != nil {
                if case .challenge = call, response.outgoing != nil { outgoingRevision &+= 1 }
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
        let wasMyAim = old.map(Self.isMyAim) ?? false
        state = next
        focusMatchID = nil
        let key = id.uuidString.lowercased()
        if next.phase == .finished, seenFinishedMatchIDs.insert(key).inserted {
            onMatchFinished?()
            guard context.generation == resetGeneration else { return }
            // 내 판이 끝나는 것을 지켜봤다 — 전적은 로비 응답에만 있으니 한 번 다시 읽고(창이 보이면 사람 목록까지) 순위도.
            if let old, old.phase != .finished { noteOwnMatchFinished() }
        }
        if next.phase != .finished, announcedMatchIDs.insert(key).inserted {
            // 판 id 마다 한 번 — 끝나지 않은 판이 처음 섰다. 서버는 수락 순간 두 사람의 다른 알까기 대기 신청을 전부 닫았다
            // (DF#34) — 로컬 카드 · 보낸 신청도 걷는다. 관전 중이었으면 내린다.
            if !incoming.isEmpty { incoming = [] }
            if outgoing != nil { outgoing = nil }
            scheduleInviteExpiry()
            stopWatching()
            presentWindow?()
            guard context.generation == resetGeneration else { return }
            requestAttention?()
            guard context.generation == resetGeneration else { return }
            // 말풍선 문(규칙 ①) — 창이 안 보였거나 가려졌을 때만.
            if doorOpen {
                let opponent = next.myColor == .black ? next.white : next.black
                onAttention?(AlkkagiAttention(kind: .matchStarted, matchID: next.id, opponentName: opponent.displayName))
                guard context.generation == resetGeneration else { return }
            }
        } else if sameMatch, Self.isMyAim(next), !wasMyAim, doorOpen {
            // 내 차례(VC-20) — 원인과 상관없이(상대 쏘기 끝 · 상대가 시간을 넘김 · 배치 끝 뒤 내가 흑) '조준 · 내 차례'로
            // **들어설 때** 한 번. 이름은 상대가 쏴서 넘어왔을 때만 싣는다(그 밖은 이름 없는 꼴 — §5.8).
            let opponent = next.myColor == .black ? next.white : next.black
            let shooter = next.shot.flatMap { shot in shot.initialStones.first { $0.id == shot.stoneID }?.owner }
            // 서버는 쏘는 순간 shot_count 를 올린 굴림(rolling)을 먼저 낸다 — 그 굴림을 봤으면 수가 같아도 상대가 쏜 것이다(RV2-C-2).
            let byOpponentShot = shooter == next.myColor.opponent
                && (next.shotCount > (old?.shotCount ?? next.shotCount) || old?.phase == .rolling)
            onAttention?(AlkkagiAttention(kind: .myTurn, matchID: next.id,
                                          opponentName: byOpponentShot ? opponent.displayName : ""))
            guard context.generation == resetGeneration else { return }
        }
        scheduleDeadlineRefresh()
    }

    /// 로비 · 보낸 신청 확인 응답의 `outgoing` 을 옮긴다. 들고 있던 보낸 신청이 빠졌고 판으로 이어지지 않았으면 안내 한 줄 —
    /// 만료 전이면 거절(취소 · 상대가 다른 대결을 시작함 포함), 지났으면 응답 없음(§4.4).
    /// `predates` = 이 응답의 요청이 지금 보낸 신청을 세우기 **전에** 나갔다 — 그 응답에 신청이 없는 것은 끝난 것이 아니다.
    private func noteOutgoing(_ fresh: AlkkagiInvite?, from response: AlkkagiResponse, predates: Bool) {
        if predates, fresh == nil { return }
        if let gone = outgoing, fresh.map({ $0.id.caseInsensitiveCompare(gone.id) != .orderedSame }) ?? true {
            let becameMatch = [response.state?.id, state?.id].contains { $0?.caseInsensitiveCompare(gone.id) == .orderedSame }
            if !becameMatch {
                eventNotice = gone.expiresAtMs > estimatedServerNowMs ? AlkkagiNoticeText.inviteDeclined
                                                                      : AlkkagiNoticeText.inviteTimedOut
            }
        }
        if outgoing != fresh { outgoing = fresh }
    }

    /// 그 id 가 내 판이면 판을 내리고 전체 로비를 다시 읽는다(잔액이 상금을 반영 — VC-16). 신청이면 카드를 걷는다.
    private func dropMatchOrInvite(_ id: UUID) {
        if state.flatMap({ UUID(uuidString: $0.id) }) == id {
            clearMatch()
            eventNotice = AlkkagiNoticeText.finishedMatch
            pendingLobby = true
            pendingUsers = true
            startSyncIfNeeded()
        }
        if outgoing.flatMap({ UUID(uuidString: $0.id) }) == id { outgoing = nil }
        if incoming.contains(where: { UUID(uuidString: $0.id) == id }) {
            incoming.removeAll { UUID(uuidString: $0.id) == id }
        }
    }

    /// 판을 내린다(로비로). 끝난 판을 떠날 때 · 판이 사라졌을 때.
    private func clearMatch() {
        matchGeneration &+= 1
        state = nil
        chat = []
        focusMatchID = nil
        deadlineTask?.cancel()
        deadlineTask = nil
    }

    /// 내 판이 끝났다 — 전적은 로비 응답에만 있다. 한 번 다시 읽고(창이 보이면 사람 목록까지) 순위도 다시.
    private func noteOwnMatchFinished() {
        pendingLobby = true
        pendingUsers = pendingUsers || !attentionDoorIsOpen
        startSyncIfNeeded()
        lastRankingRequestAt = .distantPast
        if rankingEnabled {
            Task { @MainActor [weak self] in await self?.refreshRanking() }
        }
    }

    private enum NoticeUpdate { case keep, set(String?) }

    /// 응답 → 안내 줄(문구는 `AlkkagiNoticeText` 한 곳 — RPC 별 표, SPEC §4.4). 배경 조회(로비 · 보낸 신청 확인)의 ok 는
    /// 안내를 지우지 않는다 — 앞선 동작의 안내 · 판이 사라짐 안내가 다음 로비에 지워지지 않게.
    private func noticeUpdate(for call: AlkkagiCall, response: AlkkagiResponse) -> NoticeUpdate {
        let status = response.status
        switch call {
        case .challenge:
            return .set(AlkkagiNoticeText.challenge(status, need: response.need, have: response.have,
                                                    doorOpen: response.doorOpen))
        case .cancel:
            return .set(AlkkagiNoticeText.cancel(status))
        case let .respond(_, accept, _):
            return .set(AlkkagiNoticeText.respond(accept: accept, status, side: response.side, need: response.need,
                                                  have: response.have, doorOpen: response.doorOpen))
        case .resign:
            return .set(AlkkagiNoticeText.resign(status))
        case let .state(requested, _):
            // 내 판이 아닌 id(보낸 신청 확인)는 판 문구를 쓰지 않는다.
            guard state.flatMap({ UUID(uuidString: $0.id) }) == requested || status != .ok else { return .keep }
            if status == .notFound, state == nil, outgoing == nil { return .keep }
            return .set(AlkkagiNoticeText.move(status))
        case .place, .ready, .shoot, .leave, .chatSend, .chatMute:
            return .set(AlkkagiNoticeText.move(status))
        case .lobby, .ranking, .watch, .watchLive:
            return status == .ok ? .keep : .set(AlkkagiNoticeText.common(status))
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

    /// 진행 중인 내 판이 있다(배치 · 조준 · 굴림).
    private var hasLiveMatch: Bool { state.map { $0.phase != .finished } ?? false }

    // MARK: - 폴링(창이 보이고 안 가려졌을 때만 — 규칙 ④)

    /// 폴링 한 걸음의 조회를 **폴링 작업의 취소 밖에서** 돌리고 끝날 때까지 기다린다(규칙 ④ — 창을 닫는 순간의 취소가
    /// 나르던 조회와 그 조회에 합쳐진 초인종 조회까지 죽이지 않게).
    private func outsidePolling(_ body: @escaping @MainActor (AlkkagiOnlineStore) async -> Void) async {
        await Task { @MainActor [weak self] in
            guard let self else { return }
            await body(self)
        }.value
    }

    /// 안전망 한 걸음. **창이 안 보이거나 가려졌으면 아무것도 하지 않는다.** 걸음 사이사이 창 보임 · 가림 · 취소를 다시 본다.
    ///  · 판 중: 걸음마다 판 상태만(박자 그대로 — 3초. 로비 · 순위 조회 0)
    ///  · 판 밖: 보낸 신청이 있으면 5초마다 그 상태 · 전체 로비 30초 · 순위 60초(주 스위치)
    package func pollTick(at now: Date) async {
        guard service != nil, isWindowVisible, !isWindowOccluded, !Task.isCancelled else { return }
        if hasLiveMatch {
            await outsidePolling { await $0.synchronize(lobby: false, match: true) }
            return
        }
        if let sent = outgoing, let id = UUID(uuidString: sent.id),
           now.timeIntervalSince(lastOutgoingRequestAt) >= Self.outgoingPollSeconds {
            lastOutgoingRequestAt = now
            await outsidePolling { await $0.synchronize(lobby: false, match: false, outgoing: id) }
        }
        guard isWindowVisible, !isWindowOccluded, !Task.isCancelled else { return }
        if now.timeIntervalSince(lastLobbyRequestAt) >= Self.lobbyPollSeconds {
            lastLobbyRequestAt = now
            await outsidePolling { await $0.refreshLobby() }
        }
        guard isWindowVisible, !isWindowOccluded, !Task.isCancelled else { return }
        if rankingEnabled, now.timeIntervalSince(lastRankingRequestAt) >= Self.rankingPollSeconds {
            await outsidePolling { await $0.refreshRanking() }
        }
    }

    private func requestSync() {
        guard service != nil else { return }
        pendingLobby = true
        pendingUsers = pendingUsers || (isWindowVisible && !isWindowOccluded)
        pendingMatch = true
        startSyncIfNeeded()
    }

    /// 조회를 직렬 엔진에 싣고 끝날 때까지 기다린다. 엔진은 **부른 쪽의 작업이 아니다**(독립 Task) — 부른 쪽이 취소돼도 조회와
    /// 거기 합쳐진 부름은 끝까지 돈다(규칙 ⑤ 의 뜻 · 길건너 `handOffLobby`). 도는 중에 온 부름은 깃발로 합쳐 끝난 뒤 한 바퀴 더
    /// 돈다(규칙 ③ `lobbyAgain` — 합친 부름 중 하나라도 사람 목록을 원하면 그 바퀴는 전체 로비).
    private func synchronize(lobby: Bool, match: Bool, users: Bool = false, outgoing: UUID? = nil) async {
        guard service != nil else { return }
        pendingLobby = pendingLobby || lobby
        pendingUsers = pendingUsers || users
        pendingMatch = pendingMatch || match
        if let outgoing { pendingOutgoingID = outgoing }
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
                let outgoingID = self.pendingOutgoingID
                self.pendingLobby = false
                self.pendingUsers = false
                self.pendingMatch = false
                self.pendingOutgoingID = nil
                guard lobby || match || outgoingID != nil else { return }
                if lobby {
                    if users { self.lastLobbyRequestAt = self.clock() }
                    _ = await self.perform(.lobby(users: users))
                }
                guard generation == self.resetGeneration, !Task.isCancelled else { return }
                if let outgoingID, self.outgoing.flatMap({ UUID(uuidString: $0.id) }) == outgoingID {
                    self.lastOutgoingRequestAt = self.clock()
                    _ = await self.perform(.state(matchID: outgoingID, sinceChatSeq: 0))
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

    /// 걸음 간격 — 판 중은 `pollSeconds`(3초 박자 그대로), 판 밖은 1초(5초 · 30초 · 60초 문턱을 잰다).
    private var pollStepSeconds: Double {
        hasLiveMatch ? pollSeconds : min(pollSeconds, max(0.001, outsidePollStepSeconds))
    }

    private func startPolling() {
        guard pollTask == nil, service != nil, isWindowVisible, !isWindowOccluded else { return }
        let generation = resetGeneration
        pollToken &+= 1
        let token = pollToken
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let step = self?.pollStepSeconds else { return }
                let seconds = min(step, Double(UInt64.max / 1_000_000_000))
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                guard let self, generation == self.resetGeneration, token == self.pollToken else { return }
                guard self.isWindowVisible, !self.isWindowOccluded else {
                    self.pollTask = nil
                    return
                }
                await self.pollTick(at: self.clock())
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
            // 보낸 신청이 응답 없이 만료됐다(§4.4 — 상대가 응답하지 않았어요).
            self.outgoing = nil
            eventNotice = AlkkagiNoticeText.inviteTimedOut
            notice = AlkkagiNoticeText.inviteTimedOut
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
            self.eventNotice = nil
        }
    }

    private func stopPolling() {
        pollToken &+= 1
        pollTask?.cancel()
        pollTask = nil
        deadlineTask?.cancel()
        deadlineTask = nil
    }

    private var deadlineKey: String? {
        guard let state, let deadline = state.deadlineMs, state.phase != .finished else { return nil }
        return "\(state.id.lowercased()):\(state.revision):\(deadline)"
    }

    /// 마감 맞춤 새로고침 시각. 굴림은 쏘기 재생 끝, **조준은 마감 + 판정 유예**(서버는 유예 전에는 차례를 넘기지 않는다 —
    /// 그 전에 읽으면 같은 판을 또 읽을 뿐이다, VC-23), 배치는 마감 그대로(유예 없음).
    private var refreshDeadlineMs: Double? {
        guard let state else { return nil }
        if state.phase == .rolling, let shot = state.shot {
            return shot.startedAtMs + shot.duration * 1000
        }
        guard let deadline = state.deadlineMs else { return nil }
        if state.phase == .aiming, let grace = state.graceMs, grace.isFinite, grace > 0 {
            return deadline + grace
        }
        return deadline
    }

    /// 굴림 끝 새로고침은 **창이 숨거나 가려져도 한 번** 한다(RV2-C-3). 알까기는 굴림이 끝난 뒤 누군가 서버를 불러야 다음 차례가
    /// 열린다 — 두 창이 모두 숨으면 매분 훑기(0~60초 늦음)까지 차례가 안 열리고, 32초 넘게 늦으면 받는 사람의 놓친 차례가 말풍선
    /// 없이 셈해진다. 조준 · 배치 마감은 그대로 창이 보일 때만(서버 훑기가 옛 마감 기준으로 판정한다).
    private var refreshesWhileHidden: Bool { state?.phase == .rolling }

    private func refreshExpiredDeadline() {
        guard (isWindowVisible && !isWindowOccluded) || refreshesWhileHidden, let key = deadlineKey,
              key != refreshedDeadline else { return }
        refreshedDeadline = key
        requestSync()
    }

    private func scheduleDeadlineRefresh() {
        deadlineTask?.cancel()
        deadlineTask = nil
        guard (isWindowVisible && !isWindowOccluded) || refreshesWhileHidden, let deadline = refreshDeadlineMs,
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
