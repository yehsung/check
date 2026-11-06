import Foundation
import Observation
import OSLog

// 1:1 길건너 대결 스토어 — 화면 상태 · 서버 동기화 · 판 구동 · 보고 루프 · RPC 호출(SPEC v1.3 §8.3, TetrisDuelStore 규약).
//
// 표면(타입 · 프로퍼티 · 메서드 서명)은 C1 그대로다 — 갈래 U(화면)·T(배선)가 이 이름 그대로 선다(바꾸지 말고 덧붙이기만).
// 본은 `TetrisDuelStore` 다: 서버가 권위 · 서버 시계 보정 · 판 밖 폴링은 창이 보이고 안 가려졌을 때만 · 늦은 응답 버리기(두 세대 +
// 판 세대 + seq) · 신호 합치기 · 한 판 한 기기(서버 `my_device` → 없으면 장부). 판 갈래는 CrossyDuelStoreGame.swift,
// 프레임은 CrossyDuelStoreFrames.swift, 순위는 CrossyDuelStoreRanking.swift.
//
// 규약(MC:47-78 · 메모리 duel-store-alert-doorbell-rules — 다섯 규칙 처음부터):
//  · 말풍선 문 = `isWindowVisible && !isWindowOccluded` · `windowDidShow` 는 가림 기록을 안 지움 · `lobbyAgain` 합치기 ·
//    폴링 걸음은 `outsidePolling` + 걸음 사이 가드 · 취소로 접힌 조회는 `handOffLobby`.
//  · 판 시계 = 단조 시계(`uptime`, v1.1 CC-1). 벽시계(`clock`)는 로비 스로틀 · 장부 · 서버 시각 환산에만.
//  · 사용자 문구는 `CrossyDuelNoticeText` 한 곳에만.

// MARK: - 호스트

/// 네트워크·세션·루비 미러를 빌리는 곳 — 오목·체스·테트리스와 같은 프로토콜(CC/CheckCoreShared.swift 는 안 고친다, MC#24).
package typealias CrossyDuelStoreHost = GomokuStoreHost

// MARK: - 화면 값 타입

/// 화면 흐름. **신청(보냄·받음)은 phase 가 아니라** `.lobby` 위의 `outgoing`·`incoming` 이다.
package nonisolated enum CrossyDuelPhase: Equatable, Sendable { case lobby, ready, countdown, playing, finished }

/// 흐름과 따로 서는 상태 — 이 기기가 지금 대결을 할 수 있는가.
package nonisolated enum CrossyDuelAvailability: Equatable, Sendable { case available, updateRequired, serverMissing }

package nonisolated enum CrossyDuelStake: Int, CaseIterable, Sendable { case three = 3, five = 5, ten = 10 }

/// 판이 끝난 사유(서버 `end_reason` 글자). 모르는 글자는 `.unknown`.
package nonisolated enum CrossyDuelEndReason: String, Sendable {
    case goal, timeCap = "time_cap", resign, disconnect, noShow = "no_show", abandoned, void, unknown   // void = v1.1(CS-2)
}

/// **내 기준** 결과.
package nonisolated enum CrossyDuelOutcome: Equatable, Sendable { case win, loss, draw }

/// 로비 상대 한 사람.
package nonisolated struct CrossyDuelUser: Identifiable, Equatable, Sendable {
    package let id: String
    package let displayName: String
    package let avatarURL: String?
    package let characterID: String?
    package let isWorking: Bool
    /// 서버 `capable` — 상대 앱이 1:1 길건너를 안다. nil 은 불가로 읽는다.
    package let isCapable: Bool
    package let inMatch: Bool
    package let isFocused: Bool

    package init(id: String, displayName: String, avatarURL: String? = nil, characterID: String? = nil,
                 isWorking: Bool = false, isCapable: Bool = true, inMatch: Bool = false, isFocused: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.characterID = characterID
        self.isWorking = isWorking
        self.isCapable = isCapable
        self.inMatch = inMatch
        self.isFocused = isFocused
    }

    package var canBeChallenged: Bool { isCapable && !inMatch && !isFocused }
}

/// 내 전적(가벼운 로비는 덮지 않는다 — v1.1 CS-4).
package nonisolated struct CrossyDuelRecord: Equatable, Sendable {
    package let wins: Int
    package let losses: Int
    package let draws: Int

    package init(wins: Int, losses: Int, draws: Int) {
        self.wins = wins
        self.losses = losses
        self.draws = draws
    }
}

/// 신청 한 건(받은 것 · 보낸 것 같은 모양).
package nonisolated struct CrossyDuelInvite: Identifiable, Equatable, Sendable {
    /// match id.
    package let id: String
    package let peer: CrossyDuelUser
    package let stake: Int
    /// 기기 시계로 보정한 만료 시각.
    package let expiresAt: Date

    package init(id: String, peer: CrossyDuelUser, stake: Int, expiresAt: Date) {
        self.id = id
        self.peer = peer
        self.stake = stake
        self.expiresAt = expiresAt
    }
}

/// 바깥(앱)에 알릴 일 — 지금은 판 시작 하나.
package nonisolated struct CrossyDuelAttention: Equatable, Sendable {
    package enum Kind: Equatable, Sendable { case matchStarted }

    package let kind: Kind
    package let matchID: String
    package let opponentName: String

    package init(kind: Kind, matchID: String, opponentName: String) {
        self.kind = kind
        self.matchID = matchID
        self.opponentName = opponentName
    }
}

/// 내 판 상태(서버 응답으로만 바뀐다). 시각은 기기 시계로 보정한 `Date`.
package nonisolated struct CrossyDuelMatchState: Identifiable, Equatable, Sendable {
    package let id: String
    package var stake: Int
    package var seed: Int?
    package var opponent: CrossyDuelUser
    package var acceptedAt: Date?
    package var readyDeadline: Date?
    package var startAt: Date?
    package var endAt: Date?
    package var graceEndAt: Date?
    package var meReady: Bool
    package var opponentReady: Bool
    /// 서버가 아는 내 점수(내 막대는 로컬 엔진 점수 — 이 값은 재개·`restore` 기준).
    package var myServerScore: Int
    package var opponentScore: Int
    package var opponentDeaths: Int
    package var opponentLastSeenAt: Date?
    /// 잘라 둔 보고 간격(ms — [1000, 5000]).
    package var reportMs: Int
    /// 잘라 둔 하트비트 간격(ms — [reportMs, 5000]).
    package var heartbeatMs: Int
    package var isFinished: Bool
    package var outcome: CrossyDuelOutcome?
    package var endReason: CrossyDuelEndReason?
    /// 끝난 판의 굳은 점수(내 관점).
    package var finalMyScore: Int?
    package var finalOpponentScore: Int?
    /// 내 루비 증감(이기면 `DuelFee.winnerNet(stake:)`).
    package var rubyDelta: Int?
    package var finishedAt: Date?

    package init(id: String, stake: Int, seed: Int? = nil, opponent: CrossyDuelUser,
                 acceptedAt: Date? = nil, readyDeadline: Date? = nil, startAt: Date? = nil, endAt: Date? = nil,
                 graceEndAt: Date? = nil, meReady: Bool = false, opponentReady: Bool = false,
                 myServerScore: Int = 0, opponentScore: Int = 0, opponentDeaths: Int = 0,
                 opponentLastSeenAt: Date? = nil, reportMs: Int = 2000, heartbeatMs: Int = 3000,
                 isFinished: Bool = false, outcome: CrossyDuelOutcome? = nil, endReason: CrossyDuelEndReason? = nil,
                 finalMyScore: Int? = nil, finalOpponentScore: Int? = nil, rubyDelta: Int? = nil,
                 finishedAt: Date? = nil) {
        self.id = id
        self.stake = stake
        self.seed = seed
        self.opponent = opponent
        self.acceptedAt = acceptedAt
        self.readyDeadline = readyDeadline
        self.startAt = startAt
        self.endAt = endAt
        self.graceEndAt = graceEndAt
        self.meReady = meReady
        self.opponentReady = opponentReady
        self.myServerScore = myServerScore
        self.opponentScore = opponentScore
        self.opponentDeaths = opponentDeaths
        self.opponentLastSeenAt = opponentLastSeenAt
        self.reportMs = reportMs
        self.heartbeatMs = heartbeatMs
        self.isFinished = isFinished
        self.outcome = outcome
        self.endReason = endReason
        self.finalMyScore = finalMyScore
        self.finalOpponentScore = finalOpponentScore
        self.rubyDelta = rubyDelta
        self.finishedAt = finishedAt
    }
}

/// U 가 TimelineView 틱마다 읽는 값 하나(`raceSnapshot(at:)`).
package struct CrossyDuelRaceSnapshot: Equatable, Sendable {
    package var myScore: Int
    package var opponentScore: Int
    package var goal: Int
    package var myDeaths: Int
    package var opponentDeaths: Int
    /// 카운트다운 남은 초(카운트다운이 아니면 nil).
    package var countdown: TimeInterval?
    /// 판 남은 초(시작 전이면 nil).
    package var remaining: TimeInterval?
    /// 부활까지 남은 초(죽어 있지 않으면 nil).
    package var respawnIn: TimeInterval?
    /// 부활 보호 중.
    package var shielded: Bool
    /// 3분 얼림 · 100 도달 · 끝난 판 — 입력이 먹지 않는다.
    package var frozen: Bool
    /// 얼었고 서버 결과를 기다린다.
    package var waitingForResult: Bool
    /// 상대 last_seen 이 8초 넘음(v1.1 CC-19 · 프레임이 켜져 있으면 프레임 수신 시각과 max — §8.4).
    package var opponentQuiet: Bool

    package init(myScore: Int, opponentScore: Int, goal: Int, myDeaths: Int, opponentDeaths: Int,
                 countdown: TimeInterval? = nil, remaining: TimeInterval? = nil, respawnIn: TimeInterval? = nil,
                 shielded: Bool = false, frozen: Bool = false, waitingForResult: Bool = false,
                 opponentQuiet: Bool = false) {
        self.myScore = myScore
        self.opponentScore = opponentScore
        self.goal = goal
        self.myDeaths = myDeaths
        self.opponentDeaths = opponentDeaths
        self.countdown = countdown
        self.remaining = remaining
        self.respawnIn = respawnIn
        self.shielded = shielded
        self.frozen = frozen
        self.waitingForResult = waitingForResult
        self.opponentQuiet = opponentQuiet
    }
}

// MARK: - 스토어

@MainActor
@Observable
package final class CrossyDuelStore {
    // MARK: 주기 상수(테트리스 상수, CC/TetrisDuelStore.swift:450-475)

    /// 보낸 신청이 떠 있을 때 `crossy_duel_state(outgoing.id)` 주기(초).
    package nonisolated static let outgoingPollSeconds: TimeInterval = 5
    package nonisolated static let lobbyPollSeconds: TimeInterval = 30
    package nonisolated static let menuLobbyThrottleSeconds: TimeInterval = 30
    package nonisolated static let rankingPollSeconds: TimeInterval = 60
    /// 상대 침묵 표시 문턱(초, v1.1 CC-19).
    package nonisolated static let opponentQuietSeconds: TimeInterval = 8
    /// 판 루프 한 걸음(초).
    package nonisolated static let gameLoopSeconds: TimeInterval = 0.05
    /// 창 열기와 창 표시가 같은 조회를 두 번 쏘지 않게 하는 간격(초).
    package nonisolated static let reloadDedupeSeconds: TimeInterval = 1
    /// 서버 시계 오프셋을 다시 재는 문턱(초).
    package nonisolated static let serverClockToleranceSeconds: TimeInterval = 0.25
    /// 같은 신청을 다시 읽었을 때 만료가 이만큼 안쪽으로만 다르면 기존 값을 쓴다(초).
    package nonisolated static let inviteExpiryToleranceSeconds: TimeInterval = 1
    /// 보고가 이만큼 연달아 실패하면 `connectionTrouble` 을 세운다(화면: "연결 확인 중"). 55P03 은 세지 않는다(§3.1 CC-21).
    package nonisolated static let reportFailureLimit = 2

    package nonisolated static let logger = Logger(subsystem: "kingcheck", category: "crossy-duel")

    /// 네트워크·세션·루비 미러를 빌리는 곳(약참조). nil 이면 미리보기·렌더 시험용이라 네트워크를 한 건도 내지 않는다.
    @ObservationIgnored package private(set) weak var host: (any CrossyDuelStoreHost)?
    /// 벽시계(로비 스로틀 · 장부 · 서버 시각 환산). 시험이 갈아 끼운다.
    @ObservationIgnored package var clock: () -> Date
    /// **단조 시계**(초). 판 시계 · 보고 간격 · `raceSnapshot` 기본값(v1.1 CC-1).
    @ObservationIgnored package var uptime: () -> TimeInterval

    package init(host: (any CrossyDuelStoreHost)? = nil, clock: @escaping () -> Date = Date.init,
                 uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.host = host
        self.clock = clock
        self.uptime = uptime
    }

    /// 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다.
    package func attach(host: any CrossyDuelStoreHost) {
        self.host = host
    }

    // MARK: 화면 상태

    package internal(set) var phase: CrossyDuelPhase = .lobby
    package internal(set) var availability: CrossyDuelAvailability = .available
    package internal(set) var users: [CrossyDuelUser] = []
    package internal(set) var record: CrossyDuelRecord?
    /// 받은 신청(최신이 앞). 화면은 `visibleIncomingInvites`·`visibleIncoming` 을 읽는다.
    package internal(set) var incoming: [CrossyDuelInvite] = []
    package internal(set) var outgoing: CrossyDuelInvite?
    package internal(set) var match: CrossyDuelMatchState? {
        didSet {
            if let line = Self.matchTransitionLine(from: oldValue, to: match) {
                Self.logger.notice("\(line, privacy: .public)")
            }
            if Self.matchJustFinished(from: oldValue, to: match) { onMatchFinished?() }
        }
    }
    package internal(set) var notice: String?
    package internal(set) var isBusy = false
    package internal(set) var isWindowVisible = false
    /// 창이 완전히 가려졌다(판은 계속 흐른다 — 폴링과 말풍선 문만 본다).
    package internal(set) var isWindowOccluded = false
    package internal(set) var rubyBalance: Int?
    package internal(set) var hasLoadedLobby = false
    package internal(set) var lobbyLoadFailed = false
    /// 보고가 연달아 실패하는 중(판 화면의 "연결 확인 중").
    package internal(set) var connectionTrouble = false
    /// 진행 중인 내 판을 같은 계정의 다른 기기가 두고 있다(화면은 `CrossyDuelNoticeText.otherDevice`).
    package internal(set) var playingElsewhere = false
    package internal(set) var ranking: CrossyDuelRankingBoard?
    /// 서버에 `crossy_duel_ranking` 이 아직 없다(PGRST202).
    package internal(set) var rankingUnavailable = false

    /// **순위 적재의 주 스위치. 기본 false.** 켜는 곳은 맥 배선 한 줄(T).
    package var rankingEnabled = false
    package var selectedStake: CrossyDuelStake = .three
    /// 차단으로 걷어낸 상대(소유자가 채운다).
    package var hiddenPeerIDs: Set<String> = []

    /// 로비 상대 목록(화면용).
    package var visibleUsers: [CrossyDuelUser] {
        hiddenPeerIDs.isEmpty ? users : users.filter { !hiddenPeerIDs.contains($0.id) }
    }

    /// 받은 신청 전부(화면용) — 차단 거울 + 지금 내 판과 같은 id 는 뺀다(MC:77).
    package var visibleIncomingInvites: [CrossyDuelInvite] {
        let matchID = match?.id
        return incoming.filter { !hiddenPeerIDs.contains($0.peer.id) && $0.id != matchID }
    }

    /// 배너·메뉴바 점이 읽는 받은 신청 하나(가장 최근). **시계를 읽지 않는다** — 만료는 스토어 타이머가 걷는다.
    package var visibleIncoming: CrossyDuelInvite? { visibleIncomingInvites.first }

    /// 확성기 배너를 미룬다(카운트다운 · 판 중).
    package var defersMegaphoneBanner: Bool { phase == .countdown || phase == .playing }

    /// App Nap 붙들기(카운트다운 · 판 중이고 이 기기가 연 판).
    package var holdsActivity: Bool { (phase == .countdown || phase == .playing) && !playingElsewhere }

    // MARK: 판 (관찰 대상 아님)

    /// 내 판 구동기. **관찰 대상이 아니다** — 뷰는 `TimelineView` 안에서 `raceSnapshot(at:)` 으로 읽는다.
    @ObservationIgnored package internal(set) var duel: CrossyDuelSession?
    /// '이 기기가 연 판' 장부(앱 배선이 `defaults` 를 넣는다).
    @ObservationIgnored package var deviceLedger = GameDeviceLedger(game: "crossy_duel", ttlSeconds: 3600)
    /// `duel` 이 어느 판의 것인가.
    @ObservationIgnored package internal(set) var duelMatchID: String?
    /// 판 구동기를 갈아 끼울 때마다 오른다 — 앞 판에 나간 보고의 응답이 새 판을 건드리지 못하게 한다.
    @ObservationIgnored package internal(set) var duelGeneration = 0
    @ObservationIgnored package internal(set) var gameLoopTask: Task<Void, Never>?
    @ObservationIgnored var gameLoopToken = 0
    /// 판 루프의 한 걸음(초). 창과 무관하게 돈다. 시험은 3,600 으로 재우고 `tick(now:)` 을 직접 부른다.
    @ObservationIgnored package var gameLoopStepSeconds: TimeInterval = CrossyDuelStore.gameLoopSeconds
    /// 지금 나가 있는 보고(마지막 것). 시험이 `await reportTask?.value` 로 기다린다.
    @ObservationIgnored package internal(set) var reportTask: Task<Void, Never>?
    @ObservationIgnored package internal(set) var reportInFlight = false
    /// 나가 있는 보고의 종류(멎어서 버릴 때 결승 보고면 다시 낸다).
    @ObservationIgnored package internal(set) var reportInFlightKind: CrossyDuelSession.ReportKind?
    /// 나가 있는 보고를 낸 단조 시각(멎음 판정).
    @ObservationIgnored package internal(set) var reportSentAt: TimeInterval?
    /// 보고를 낼 때마다 오른다 — 버렸거나 앞지른(goal·cap) 보고의 늦은 답이 그 뒤에 낸 보고의 자리를 건드리지 못하게 한다.
    @ObservationIgnored package internal(set) var reportTicket = 0
    @ObservationIgnored package internal(set) var reportFailureStreak = 0
    /// 서버가 말한 내 seq·상대 seq 의 최댓값(같은 판의 옛 스냅숏을 버리는 기준).
    @ObservationIgnored package internal(set) var heldMySeq = 0
    @ObservationIgnored package internal(set) var heldOpponentSeq = 0
    /// 상대 침묵 재료(v1.1 CC-19): 응답의 `server_now_ms − opponent.last_seen_ms`(초)와 그 응답을 받은 단조 시각.
    /// 서버 시각끼리 빼므로 기기 시계 어긋남과 무관하다.
    @ObservationIgnored package internal(set) var opponentSilenceAtReceipt: TimeInterval?
    @ObservationIgnored package internal(set) var opponentSilenceReceivedAt: TimeInterval?
    /// 서버가 `other_device` 로 돌려보내 **물러난** 판(서버가 다시 'this' 라 해도 두지 않는다).
    @ObservationIgnored package internal(set) var yieldedMatchIDs: Set<String> = []
    /// 마지막으로 알린 `holdsActivity`(바뀔 때만 `onHoldingActivityChange`).
    @ObservationIgnored var lastHoldingActivity = false

    // MARK: 판 표시 프레임 (관찰 대상 아님 — 로직은 CrossyDuelStoreFrames.swift)

    /// 이 판의 프레임 장부(순수). 이 기기가 두는 판에서만 선다.
    @ObservationIgnored package internal(set) var frameLink: CrossyDuelFrameLink?
    /// `frameLink` 가 어느 판의 것인가(구동기와 수명을 같이한다).
    @ObservationIgnored package internal(set) var frameLinkMatchID: String?
    /// 프레임 소켓(판마다 다시 쓰는 한 개). nil 이면 이 기기는 프레임을 못 연다(시험 프로세스 — 대체 길).
    @ObservationIgnored package internal(set) var frameChannel: (any CrossyDuelFrameChannel)?
    @ObservationIgnored var frameChannelResolved = false
    /// 프레임 소켓을 만드는 문(시험이 스텁을 끼운다). 받는 값은 리얼타임 킬스위치를 읽을 저장소(`deviceLedger.defaults` 없으면 `.standard`).
    @ObservationIgnored package var makeFrameChannel: @MainActor (UserDefaults) -> (any CrossyDuelFrameChannel)? = { defaults in
        CrossyDuelStore.defaultFrameChannel(defaults: defaults)
    }
    /// 재시도 지터(full jitter). 시험은 `{ $0 }` 로 결정적으로 만든다.
    @ObservationIgnored package var frameJitter: (Double) -> Double = { ceiling in
        ceiling <= 0 ? 0 : Double.random(in: 0...ceiling)
    }
    /// 프레임 소켓에 connect 를 시켰고 아직 disconnect 를 안 시켰다(닫기 누락 = 연결 누수 — 이 깃발이 닫기의 기준이다).
    @ObservationIgnored package internal(set) var frameSocketOpen = false
    @ObservationIgnored package internal(set) var frameSocketTopic: String?
    @ObservationIgnored package internal(set) var frameSocketToken: String?
    @ObservationIgnored var frameConnectTicket = 0
    @ObservationIgnored var loggedFramesConfirmed: Bool?

    // MARK: 내부 장부 (관찰 대상 아님)

    /// 판 밖 폴링 루프의 한 걸음(초). 시험은 3,600 으로 재우고 `pollTick(at:)` 을 직접 밟는다.
    @ObservationIgnored package var pollStepSeconds: TimeInterval = 0.5
    @ObservationIgnored package private(set) var serverClockOffset: TimeInterval = 0
    @ObservationIgnored private var hasServerClockOffset = false
    /// 루비 잔액을 마지막으로 옮긴 응답의 `server_now_ms`(늦은 응답 가드 §8.3 — 검토 RV-C-2). 이보다 옛 응답의 잔액은 버린다.
    @ObservationIgnored private var rubyServerNowMs: Double?
    @ObservationIgnored package private(set) var resetGeneration = 0
    @ObservationIgnored package private(set) var stateInFlightID: String?
    @ObservationIgnored private var pendingStateID: String?
    @ObservationIgnored var stateInFlight = false
    @ObservationIgnored private var stateAgain = false
    @ObservationIgnored private var lobbyInFlight = false
    /// 로비 조회가 도는 중에 또 불렸다 — 끝난 뒤 **한 번 더** 읽는다(합친 부름이 사람 목록을 원했으면 전체로).
    @ObservationIgnored private var lobbyAgain = false
    @ObservationIgnored private var lobbyAgainWantsUsers = false
    @ObservationIgnored var rankingInFlight = false
    /// 서버가 말한 내 진행 중 대결 id.
    @ObservationIgnored package private(set) var activeMatchID: String?
    @ObservationIgnored package private(set) var seenInviteIDs: Set<String> = []
    /// "대결이 시작됐어요" 를 이미 알린 판 id.
    @ObservationIgnored private var announcedMatchIDs: Set<String> = []
    /// [로비로] 로 접은 끝난 판. 늦게 온 그 판의 상태가 사용자를 결과 화면으로 끌고 가지 않게 한다.
    @ObservationIgnored package private(set) var dismissedMatchIDs: Set<String> = []
    @ObservationIgnored package private(set) var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pollToken = 0
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored package var lastStateRequestAt: Date = .distantPast
    @ObservationIgnored package var lastLobbyRequestAt: Date = .distantPast
    @ObservationIgnored package var lastOutgoingRequestAt: Date = .distantPast
    @ObservationIgnored package var lastMenuLobbyAt: Date = .distantPast
    @ObservationIgnored package var lastRankingRequestAt: Date = .distantPast
    /// 신호 재조회 직렬화(도는 중이면 뒤따르는 한 번으로 합친다).
    @ObservationIgnored package private(set) var syncTask: Task<Void, Never>?
    @ObservationIgnored private var syncPendingTrailing = false
    /// 신청 만료(초) — 응답이 만료를 안 실어 준 드문 경우의 기본값.
    @ObservationIgnored package private(set) var inviteTTLSeconds: TimeInterval = 60
    /// 이 기기에서 보낸 신청을 새로 세울 때마다 오른다. 그보다 **먼저** 나간 로비 응답이 방금 보낸 신청을 지우지 않게 한다.
    @ObservationIgnored private var outgoingRevision = 0
    @ObservationIgnored private var lobbyRequestOutgoingRevision = 0

    // MARK: UI · 앱 배선 문

    @ObservationIgnored package var presentWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var dismissWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var requestAttention: (@MainActor () -> Void)?
    @ObservationIgnored package var onInviteArrived: (@MainActor (CrossyDuelInvite) -> Void)?
    /// `.matchStarted` 만.
    @ObservationIgnored package var onAttention: (@MainActor (CrossyDuelAttention) -> Void)?
    /// 내 판이 끝난 것을 처음 본 순간 한 번(미션 꼬리 — T).
    @ObservationIgnored package var onMatchFinished: (@MainActor () -> Void)?
    /// `holdsActivity` 가 바뀔 때(refreshPhase 끝 `syncHoldingActivity` — v1.1 CC-10).
    @ObservationIgnored package var onHoldingActivityChange: (@MainActor (Bool) -> Void)?

    // MARK: - 창

    /// 창을 띄우고 로비(사람 목록까지)·판을 읽는다. `focusMatchID` 는 배너·말풍선에서 온 경로의 대상이다.
    package func openWindow(focusMatchID: String?) {
        if host?.session != nil {
            let focus = focusMatchID?.lowercased()
            // 곧 이어질 windowDidShow 가 같은 조회를 또 쏘지 않도록 **동기로** 먼저 적는다.
            lastLobbyRequestAt = clock()
            Task { [weak self] in
                guard let self else { return }
                await self.refreshLobby()
                if let focus, focus != self.match?.id, !self.incoming.contains(where: { $0.id == focus }) {
                    await self.refreshMatch(id: focus)
                }
            }
        }
        presentWindow?()
    }

    /// 창이 실제로 보이기 시작했다. 폴링 시작 · 로비 재조회 · **준비 보고의 문이 열린다**.
    package func windowDidShow() {
        // 열린 채 가려진 창을 다시 부르는 길(판 시작의 `presentWindow`)이면 가림 기록을 **그대로 둔다**(규칙 ② — 오목·테트리스 수리).
        let reshownWhileOccluded = isWindowVisible && isWindowOccluded
        if !isWindowVisible { isWindowVisible = true }
        if !reshownWhileOccluded, isWindowOccluded { isWindowOccluded = false }
        startPolling()
        // 준비를 기다리던 판이면 지금 곧바로 낸다(다음 판 루프 걸음을 기다리지 않는다).
        if duel != nil { tick() }
        guard host?.session != nil else { return }
        let now = clock()
        if now.timeIntervalSince(lastLobbyRequestAt) >= Self.reloadDedupeSeconds {
            Task { [weak self] in await self?.refreshLobby() }
        }
        if rankingEnabled, phase == .lobby,
           now.timeIntervalSince(lastRankingRequestAt) >= Self.reloadDedupeSeconds {
            Task { [weak self] in await self?.refreshRanking() }
        }
    }

    /// 창이 숨었다·최소화됐다. 폴링만 멈춘다 — **판은 계속 흐른다**.
    package func windowDidHide() {
        if isWindowVisible { isWindowVisible = false }
        if isWindowOccluded { isWindowOccluded = false }
        stopPolling()
    }

    /// 창을 **정말 닫았다**. **닫기는 기권이 아니다** — 진행 중 판은 그대로 흐른다. 끝난 판은 여기서 접는다.
    package func windowDidClose() {
        if isWindowVisible { isWindowVisible = false }
        if isWindowOccluded { isWindowOccluded = false }
        stopPolling()
        foldFinishedMatch()
    }

    /// 창의 가림 상태가 바뀌었다. 폴링을 멈추고 되살린다 — `isWindowVisible` 은 건드리지 않는다.
    package func windowOcclusionDidChange(visible: Bool) {
        if isWindowOccluded != !visible { isWindowOccluded = !visible }
        if visible { startPolling() } else { stopPolling() }
    }

    // MARK: - 조회

    /// 창 경로 → 사람 목록까지(`p_users` true).
    package func refreshLobby() async {
        await loadLobby(users: true)
    }

    /// 팝오버 · 창 밖 신호 경로 → 가벼운 로비(`p_users` false — `me` 만, v1.1 CS-4).
    package func refreshLightLobby() async {
        await loadLobby(users: false)
    }

    /// 로비를 읽는다. 도는 중에 또 불리면 끝난 뒤 **한 번 더** 읽는다(`lobbyAgain` — 규칙 ③). 합친 부름 중 하나라도 사람 목록을
    /// 원했으면 그 한 바퀴는 전체 로비다. 나르던 작업이 취소돼 조회가 접히면 합쳐진 부름은 취소 밖으로 넘긴다(`handOffLobby` — 규칙 ⑤).
    package func loadLobby(users wantsUsers: Bool) async {
        guard host?.session != nil else { return }
        if lobbyInFlight {
            lobbyAgain = true
            if wantsUsers { lobbyAgainWantsUsers = true }
            return
        }
        lobbyInFlight = true
        let generation = resetGeneration
        let sessionGeneration = host?.sessionGeneration
        var handOff = false
        var handOffUsers = false
        defer { if handOff { handOffLobby(users: handOffUsers, generation: generation, sessionGeneration: sessionGeneration) } }
        defer { if generation == resetGeneration { lobbyInFlight = false } }
        var owed = false
        var users = wantsUsers
        repeat {
            // 루프 **안에서 먼저** 내린다 — 이번 조회가 도는 동안 온 초인종을 지우지 않게.
            if owed { users = lobbyAgainWantsUsers }
            lobbyAgain = false
            lobbyAgainWantsUsers = false
            if users { lastLobbyRequestAt = clock() }
            lobbyRequestOutgoingRevision = outgoingRevision
            let full = users
            guard let result = await perform({ try await $0.crossyDuelLobby(accessToken: $1, users: full) }) else {
                handOff = Task.isCancelled && (owed || lobbyAgain)
                handOffUsers = lobbyAgainWantsUsers || (!owed && full)
                return
            }
            switch result {
            case .success(let response):
                await applyLobby(response)
            case .failure(let error):
                if isSchemaMissing(error) {
                    Self.logger.notice("lobby unavailable — crossy duel functions missing on server")
                    noteServerMissing()
                } else {
                    Self.logger.notice("lobby request failed")
                }
                if !lobbyLoadFailed { lobbyLoadFailed = true }
            }
            owed = true
        } while lobbyAgain && generation == resetGeneration
    }

    /// 로비를 나르던 작업 자체가 취소돼 조회가 접혔는데 합쳐진 부름이 남았다 — 그 한 번을 **취소 밖** Task 로 낸다(규칙 ⑤).
    private func handOffLobby(users: Bool, generation: Int, sessionGeneration: Int?) {
        Task { @MainActor [weak self] in
            guard let self, generation == self.resetGeneration, self.host?.sessionGeneration == sessionGeneration,
                  !self.lobbyInFlight else { return }
            await self.loadLobby(users: users)
        }
    }

    /// 로비 응답을 옮긴다. **가벼운 응답**(전적 셋이 null — 서버가 `p_users` false 로 읽은 것)은 `users`·`record` 를 덮지 않는다
    /// (v1.1 CS-4 — null·빈 값으로 진짜 목록·전적을 지우는 결함 자리). 잔액·신청·진행 판 id 는 둘 다 반영한다.
    package func applyLobby(_ response: CrossyDuelLobbyResponse) async {
        guard response.status == .ok else {
            Self.logger.notice("lobby refused status=\(response.status.rawValue, privacy: .public)")
            switch response.status {
            case .unsupportedClient: noteUpdateRequired()
            case .notSignedIn: setNotice(CrossyDuelNoticeText.signInAgain)
            default: break
            }
            if !lobbyLoadFailed { lobbyLoadFailed = true }
            return
        }
        noteServerNow(response.serverNowMs)
        if availability != .available { availability = .available }
        if lobbyLoadFailed { lobbyLoadFailed = false }
        let light = Self.isLightLobby(response)
        if !light {
            if !hasLoadedLobby { hasLoadedLobby = true }
            if let rows = response.users {
                let mapped = Self.sortedForLobby(rows.compactMap(Self.user(from:)))
                if users != mapped { users = mapped }
            }
        }
        if let me = response.me {
            applyRuby(me.rubyBalance, serverNowMs: response.serverNowMs)
            if !light {
                let fresh = CrossyDuelRecord(wins: me.wins ?? 0, losses: me.losses ?? 0, draws: me.draws ?? 0)
                if record != fresh { record = fresh }
            }
            // ★ 신청을 옮기기 **전에** 적는다 — 보낸 신청이 판으로 이어졌는지(becameMatch)를 이 값으로 가른다.
            activeMatchID = me.activeMatchId?.lowercased()
        }
        applyLobbyInvites(response.me)
        if let active = activeMatchID, match?.id != active || match?.isFinished == true {
            await refreshMatch(id: active)
        }
    }

    /// 가벼운 로비 응답인가 — 전적 셋이 모두 null(서버는 가벼운 로비에서만 null 을 준다 — 0 이 아니다).
    package nonisolated static func isLightLobby(_ response: CrossyDuelLobbyResponse) -> Bool {
        guard let me = response.me else { return response.users?.isEmpty ?? true }
        return me.wins == nil && me.losses == nil && me.draws == nil
    }

    /// 로비 `me` 의 신청 둘(받은 것 배열 · 보낸 것 하나)을 화면 값으로 옮긴다.
    private func applyLobbyInvites(_ me: CrossyDuelLobbyMe?) {
        if let rows = me?.incoming {
            var fresh: [CrossyDuelInvite] = []
            for row in rows {
                guard let invite = invite(from: row, peer: row.from) else { continue }
                // 지금 내 판으로 이어진 신청은 되살리지 않는다(늦은 로비 — MC:77).
                if invite.id == match?.id { continue }
                fresh.append(Self.steadyInvite(invite, previous: incoming.first { $0.id == invite.id }))
            }
            if incoming != fresh { incoming = fresh }
            for invite in fresh where !seenInviteIDs.contains(invite.id) {
                seenInviteIDs.insert(invite.id)
                guard !hiddenPeerIDs.contains(invite.peer.id) else { continue }
                onInviteArrived?(invite)
            }
        } else if me != nil, !incoming.isEmpty {
            incoming = []
        }

        let serverOutgoing = me?.outgoing.flatMap { invite(from: $0, peer: $0.to) }
        let predatesOutgoing = lobbyRequestOutgoingRevision < outgoingRevision
        if let gone = outgoing, serverOutgoing?.id != gone.id, !predatesOutgoing {
            let becameMatch = gone.id == activeMatchID || gone.id == match?.id
            if !becameMatch {
                setNotice(gone.expiresAt > clock() ? CrossyDuelNoticeText.inviteDeclined
                                                   : CrossyDuelNoticeText.inviteTimedOut)
            }
            outgoing = nil
        }
        if let serverOutgoing, serverOutgoing.id != match?.id,
           !predatesOutgoing || outgoing == nil || outgoing?.id == serverOutgoing.id {
            let steady = Self.steadyInvite(serverOutgoing, previous: outgoing)
            if outgoing != steady { outgoing = steady }
        }
        scheduleInviteExpiry()
    }

    package func refreshMatch() async {
        await refreshMatch(id: match?.id ?? activeMatchID)
    }

    /// 한 판(또는 신청)의 상태를 읽는다. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다. 다른 판 id 는 기억했다가 그다음에 읽는다.
    package func refreshMatch(id rawID: String?) async {
        guard let requested = rawID?.lowercased(), !requested.isEmpty, host?.session != nil else { return }
        if stateInFlight {
            if requested == stateInFlightID { stateAgain = true } else { pendingStateID = requested }
            return
        }
        stateInFlight = true
        let generation = resetGeneration
        var nextID: String? = requested
        while let id = nextID {
            nextID = nil
            stateInFlightID = id
            repeat {
                stateAgain = false
                lastStateRequestAt = clock()
                if outgoing?.id == id { lastOutgoingRequestAt = lastStateRequestAt }
                let result = await perform({ try await $0.crossyDuelState(accessToken: $1, matchID: id) })
                guard generation == resetGeneration else { return }
                switch result {
                case .success(let response)?:
                    noteServerNow(response.serverNowMs)
                    switch response.status {
                    case .ok:
                        if let state = response.state { applyState(state, receivedAt: uptime()) }
                    case .notFound:
                        dropMatchOrInvite(id)
                    case .unsupportedClient:
                        noteUpdateRequired()
                    default:
                        Self.logger.notice("state refused status=\(response.status.rawValue, privacy: .public)")
                    }
                case .failure(let error)?:
                    if isSchemaMissing(error) { noteServerMissing() }
                case nil:
                    break
                }
            } while stateAgain
            if let pending = pendingStateID {
                pendingStateID = nil
                nextID = pending
            }
        }
        stateInFlightID = nil
        stateInFlight = false
    }

    package enum StateApplyOutcome: Equatable { case applied, ignored }

    /// 판 상태를 옮긴다 — **판과 신청을 한 경로로 가르는 유일한 깔때기**(보고 · 상태 조회 · 수락 · 기권 응답이 전부 여기로 온다).
    ///
    /// 늦은 응답 가드(§8.3): [로비로] 로 접은 끝난 판 · 이미 끝남으로 든 판의 진행 중 응답 · 다른 진행 판을 들고 있을 때의 남의 판 ·
    /// 같은 판의 내 seq·상대 seq 감소 스냅숏(끝난 응답은 예외 — 되돌릴 수 없는 사실) · 모르는 status.
    /// 판정·루비는 **서버 값만** 옮긴다(프레임은 이 함수를 지나지 않는다 — B0).
    /// - Parameter receivedAt: 이 응답을 **받은** 단조 시각(판 시작을 단조 시계로 옮기는 기준). nil 이면 지금.
    @discardableResult
    package func applyState(_ payload: CrossyDuelStatePayload, receivedAt: TimeInterval? = nil) -> StateApplyOutcome {
        guard let id = payload.matchId?.lowercased(), !id.isEmpty else { return .ignored }
        let received = receivedAt ?? uptime()
        noteServerNow(payload.serverNowMs)
        applyRuby(payload.rubyBalance, serverNowMs: payload.serverNowMs)
        let status = payload.status ?? ""
        switch status {
        case "pending":
            if match?.id == id { return .ignored }
            if !incoming.contains(where: { $0.id == id }) && outgoing?.id != id {
                Task { [weak self] in await self?.refreshLightLobby() }
            }
            return .applied
        case "active", "finished":
            break
        case "declined", "cancelled", "expired":
            dropMatchOrInvite(id, notice: status == "expired" ? CrossyDuelNoticeText.inviteTimedOut
                                                              : CrossyDuelNoticeText.inviteDeclined)
            return .applied
        default:
            Self.logger.notice("state ignored — unknown status=\(status, privacy: .public)")
            return .ignored
        }

        let isFinished = status == "finished"
        if isFinished, dismissedMatchIDs.contains(id), match?.id != id { return .ignored }
        if let current = match, current.id != id, !current.isFinished { return .ignored }
        let base = match?.id == id ? match : nil
        if let base, base.isFinished, !isFinished { return .ignored }
        // 규칙 값 두 출처 금지(§8.1 CC-17): 진행 중 판의 goal·상한이 이 앱의 엔진과 다르면 두지 않는다.
        if !isFinished, !Self.rulesMatch(goal: payload.goal, maxDurationSeconds: payload.maxDurationSeconds) {
            Self.logger.notice("state ignored — rules differ goal=\(payload.goal ?? -1) max=\(payload.maxDurationSeconds ?? -1)")
            noteUpdateRequired()
            return .ignored
        }
        let mySeq = payload.me?.seq ?? 0
        let opponentSeq = payload.opponent?.seq ?? 0
        if base != nil, !isFinished, mySeq < heldMySeq || opponentSeq < heldOpponentSeq { return .ignored }
        if base == nil {
            heldMySeq = 0
            heldOpponentSeq = 0
            opponentSilenceAtReceipt = nil
            opponentSilenceReceivedAt = nil
        }
        heldMySeq = max(heldMySeq, mySeq)
        heldOpponentSeq = max(heldOpponentSeq, opponentSeq)
        if let now = payload.serverNowMs, let seen = payload.opponent?.lastSeenMs, now.isFinite, seen.isFinite {
            opponentSilenceAtReceipt = max(0, (now - seen) / 1000)
            opponentSilenceReceivedAt = received
        }

        let myID = host?.session?.userID.lowercased()
        let opponentRow = payload.opponent
        let opponentID = opponentRow?.id?.lowercased() ?? base?.opponent.id ?? ""
        let opponent = peerUser(id: opponentRow?.id, displayName: opponentRow?.displayName,
                                avatarURL: opponentRow?.avatarUrl, character: opponentRow?.character, inMatch: !isFinished)
            ?? base?.opponent
            ?? CrossyDuelUser(id: opponentID, displayName: "", inMatch: !isFinished)
        let outcome = isFinished ? Self.outcome(result: payload.result, winner: payload.winner, myID: myID) : nil
        let stake = payload.stake ?? base?.stake ?? 0
        let rubyDelta = outcome.map { result -> Int in
            switch result {
            case .win: return DuelFee.winnerNet(stake: stake)
            case .loss: return -stake
            case .draw: return 0
            }
        }
        let intervals = CrossyDuelSession.clampedIntervals(reportMs: payload.reportMs, heartbeatMs: payload.heartbeatMs)
        let next = CrossyDuelMatchState(
            id: id, stake: stake, seed: payload.seed ?? base?.seed, opponent: opponent,
            acceptedAt: deviceDate(serverMs: payload.acceptedAtMs) ?? base?.acceptedAt,
            readyDeadline: deviceDate(serverMs: payload.readyDeadlineMs) ?? base?.readyDeadline,
            // 시작 시각은 한 번 정해지면 사라지지 않는다(옛 응답의 null 이 지우지 못하게).
            startAt: deviceDate(serverMs: payload.startAtMs) ?? base?.startAt,
            endAt: deviceDate(serverMs: payload.endAtMs) ?? base?.endAt,
            graceEndAt: deviceDate(serverMs: payload.graceEndMs) ?? base?.graceEndAt,
            meReady: (payload.me?.ready ?? false) || (base?.meReady ?? false),
            opponentReady: (payload.opponent?.ready ?? false) || (base?.opponentReady ?? false),
            myServerScore: max(payload.me?.score ?? 0, isFinished ? 0 : (base?.myServerScore ?? 0)),
            opponentScore: isFinished ? (payload.opponent?.score ?? base?.opponentScore ?? 0)
                                      : max(payload.opponent?.score ?? 0, base?.opponentScore ?? 0),
            opponentDeaths: max(payload.opponent?.deaths ?? 0, isFinished ? 0 : (base?.opponentDeaths ?? 0)),
            opponentLastSeenAt: deviceDate(serverMs: payload.opponent?.lastSeenMs) ?? base?.opponentLastSeenAt,
            reportMs: intervals.reportMs, heartbeatMs: intervals.heartbeatMs,
            isFinished: isFinished, outcome: outcome,
            endReason: payload.endReason.map { CrossyDuelEndReason(rawValue: $0) ?? .unknown },
            finalMyScore: isFinished ? payload.final?.me : nil,
            finalOpponentScore: isFinished ? payload.final?.opponent : nil,
            rubyDelta: rubyDelta,
            finishedAt: deviceDate(serverMs: payload.finishedAtMs) ?? base?.finishedAt)

        // 한 판 한 기기: 서버 `my_device` 가 권위, 없으면 장부. 끝난 판의 기록은 걷는다.
        if isFinished {
            dropOwnership(id)
        } else {
            switch payload.myDevice {
            case "this" where !yieldedMatchIDs.contains(id): noteOwnsMatch(id)
            case "other": dropOwnership(id)
            default: break
            }
        }
        let plays = !isFinished && playsMatch(id, serverSays: payload.myDevice)
        let wasElsewhere = playingElsewhere
        let elsewhere = !isFinished && !plays

        if isFinished {
            if duelMatchID == id {
                duel?.freeze()
                // ★ 끝난 판 가지에서 **바로** 프레임 소켓을 닫는다(닫기 누락 = 연결 누수). 장부는 남긴다.
                finishFrames()
            } else {
                discardDuel()
            }
            stopGameLoop()
        } else if plays {
            prepareDuel(matchID: id, payload: payload)
            if duelMatchID == id {
                if let startMs = payload.startAtMs, let serverNow = payload.serverNowMs {
                    duel?.syncStart(startAtMs: startMs, serverNowMs: serverNow, localNow: received)
                }
                duel?.adoptServerSeq(mySeq)
                // ok/stale 응답의 me.score 가 로컬 엔진보다 크면 그 줄로 다시 세운다(CC-22).
                if let score = payload.me?.score, duel?.catchUp(serverScore: score, serverDeaths: payload.me?.deaths ?? 0) == true {
                    Self.logger.notice("duel caught up to server score=\(score)")
                }
                noteServerFrames(payload.frames, reportMs: intervals.reportMs, checkpointMs: payload.checkpointMs,
                                 matchID: id, opponentID: opponentID, at: received)
                startGameLoop()
            }
        } else {
            discardDuel()
        }
        if playingElsewhere != elsewhere { playingElsewhere = elsewhere }

        let justFinished = isFinished && base?.isFinished == false
        let previous = match
        // 말풍선 문은 **보이고 안 가려진** 창만 닫는다(규칙 ①).
        let windowWasVisible = isWindowVisible && !isWindowOccluded
        if !isFinished, previous?.id != id || previous?.isFinished == true {
            // 판이 서는 순간 서버(respond)는 두 사람의 다른 길건너 대기 신청을 전부 닫았다 — 받는 쪽은 respond 가 걷지만 보낸 쪽
            // 기기(5초 조회 · 초인종이 판을 데려온 쪽)에는 닫힌 받은 신청이 남아 메뉴바 점 · 배너가 선다(검토 RV-C-4). 판 중엔 새 신청이
            // 올 수 없다(상대가 대국 중이면 서버가 target_busy).
            if !incoming.isEmpty { incoming = [] }
        } else if incoming.contains(where: { $0.id == id }) {
            incoming.removeAll { $0.id == id }
        }
        if outgoing?.id == id { outgoing = nil }
        if match != next { match = next }
        activeMatchID = isFinished ? nil : id
        refreshPhase()
        if elsewhere {
            setNotice(CrossyDuelNoticeText.otherDevice)
        } else {
            if wasElsewhere, notice == CrossyDuelNoticeText.otherDevice { setNotice(nil) }
            if !isFinished, previous?.id != id || previous?.isFinished == true || wasElsewhere {
                setNotice(nil)
                noteMatchStarted(next, windowWasVisible: windowWasVisible)
            }
        }
        if justFinished {
            // 전적은 로비 응답에만 있다. 끝난 순간 한 번 다시 읽는다(창이 보이면 사람 목록까지).
            Task { [weak self] in
                guard let self else { return }
                await self.loadLobby(users: self.isWindowVisible)
            }
            noteOwnMatchFinishedForRanking()
        }
        return .applied
    }

    /// state 의 규칙 값이 이 앱의 엔진 기대값(100 · 180)과 같은가. 키가 없으면(옛 응답) 같다고 본다.
    package nonisolated static func rulesMatch(goal: Int?, maxDurationSeconds: Int?) -> Bool {
        (goal ?? CrossyDuelSession.expectedGoal) == CrossyDuelSession.expectedGoal
            && (maxDurationSeconds ?? CrossyDuelSession.expectedMaxDurationSeconds)
                == CrossyDuelSession.expectedMaxDurationSeconds
    }

    /// 서버 `result`·`winner` → 내 기준 결과(무승부 사유 — no_show · void · 같은 점수 — 는 result 'draw').
    package nonisolated static func outcome(result: String?, winner: String?, myID: String?) -> CrossyDuelOutcome? {
        if result == "draw" { return .draw }
        guard let winner = winner?.lowercased(), !winner.isEmpty else { return nil }
        guard let myID else { return nil }
        return winner == myID ? .win : .loss
    }

    // MARK: - 동작

    /// 신청. 판돈은 고른 값을 그대로 받는다.
    package func challenge(userID: String, stake: CrossyDuelStake) async {
        guard !isBusy, host?.session != nil else { return }
        let target = userID.lowercased()
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({
            try await $0.crossyDuelChallenge(accessToken: $1, opponentID: target, stake: stake.rawValue)
        }) else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            setNotice(CrossyDuelNoticeText.challenge(response.status, need: response.need, have: response.have))
            if response.status != .ok {
                Self.logger.notice("challenge refused status=\(response.status.rawValue, privacy: .public)")
            }
            switch response.status {
            case .ok:
                guard let id = response.matchId?.lowercased() else { break }
                noteOwnsMatch(id)
                let peer = users.first { $0.id == target } ?? CrossyDuelUser(id: target, displayName: "")
                let expiresAt = deviceDate(serverMs: response.expiresAtMs) ?? clock().addingTimeInterval(inviteTTLSeconds)
                outgoingRevision &+= 1
                outgoing = CrossyDuelInvite(id: id, peer: peer, stake: stake.rawValue, expiresAt: expiresAt)
                lastOutgoingRequestAt = clock()
                scheduleInviteExpiry()
            case .unsupportedClient:
                noteUpdateRequired()
            case .alreadyPending, .busy, .targetBusy, .targetOutdated, .targetFocused:
                await refreshLobby()            // 목록의 칩이 틀렸다는 뜻 — 다시 읽어 행을 사실에 맞춘다
            default:
                break
            }
        }
    }

    package func cancelChallenge() async {
        guard !isBusy, let invite = outgoing, host?.session != nil else { return }
        let id = invite.id
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({ try await $0.crossyDuelCancel(accessToken: $1, matchID: id) }) else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            setNotice(CrossyDuelNoticeText.cancel(response.status))
            switch response.status {
            case .ok, .notFound, .notPending, .expired:
                if outgoing?.id == id {
                    outgoing = nil
                    scheduleInviteExpiry()
                }
                // not_pending 은 취소보다 수락이 먼저 닿았다는 뜻일 수 있다 — 진행 중 판을 찾아 온다.
                if response.status == .notPending { await refreshLobby() }
            case .unsupportedClient:
                noteUpdateRequired()
            default:
                break
            }
        }
    }

    package func respond(inviteID: String, accept: Bool) async {
        guard !isBusy, host?.session != nil else { return }
        let id = inviteID.lowercased()
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({
            try await $0.crossyDuelRespond(accessToken: $1, matchID: id, accept: accept)
        }) else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            let receivedAt = uptime()
            noteServerNow(response.serverNowMs)
            setNotice(CrossyDuelNoticeText.respond(
                accept: accept, response.status, side: response.side, need: response.need, have: response.have))
            if response.status != .ok {
                Self.logger.notice("respond refused status=\(response.status.rawValue, privacy: .public)")
            }
            switch response.status {
            case .ok:
                incoming.removeAll { $0.id == id }
                guard accept, response.accepted != false else {
                    scheduleInviteExpiry()
                    break
                }
                // 이 기기가 수락했다 — 이 기기가 둔다. 상태를 옮기기 **전에** 적는다.
                noteOwnsMatch(id)
                // 수락하는 순간 서버가 두 사람의 다른 길건너 대기 신청을 전부 닫는다 — 로컬 카드도 함께 걷는다.
                if !incoming.isEmpty { incoming = [] }
                if outgoing != nil { outgoing = nil }
                scheduleInviteExpiry()
                if let state = response.state {
                    applyState(state, receivedAt: receivedAt)
                } else {
                    await refreshMatch(id: id)
                }
                if match?.id != id, !isWindowVisible { presentWindow?() }
            case .notFound, .notPending, .expired, .invalid:
                incoming.removeAll { $0.id == id }
                scheduleInviteExpiry()
            case .unsupportedClient:
                noteUpdateRequired()
            default:
                break
            }
        }
    }

    /// 기권(확인은 화면이 받는다). 카운트다운·준비 중에도 된다.
    package func resign() async {
        guard !isBusy, let current = match, !current.isFinished, host?.session != nil else { return }
        let id = current.id
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({ try await $0.crossyDuelResign(accessToken: $1, matchID: id) }) else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            let receivedAt = uptime()
            noteServerNow(response.serverNowMs)
            setNotice(CrossyDuelNoticeText.resign(response.status))
            if response.status == .unsupportedClient { noteUpdateRequired() }
            if response.status == .otherDevice { yieldMatchToOtherDevice(id) }
            if let state = response.state { applyState(state, receivedAt: receivedAt) } else { await refreshMatch(id: id) }
        }
    }

    /// 결과 화면 [로비로]. **진행 중인 판에서는 아무것도 안 한다** — 빠져나가는 길은 기권뿐이다.
    package func backToLobby() {
        guard foldFinishedMatch(), host?.session != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshLobby()
            await self.refreshRanking()
        }
    }

    /// 끝난 판을 내리고 화면을 로비로 돌린다. 끝난 판을 들고 있지 않으면 false.
    @discardableResult
    private func foldFinishedMatch() -> Bool {
        guard let current = match, current.isFinished else { return false }
        dismissedMatchIDs.insert(current.id)
        clearMatch()
        setNotice(nil)
        return true
    }

    // MARK: - 신호 · 계기 (창 밖에서 아는 길)

    /// 초인종 신호(`.crossyDuelSignal`). 직렬화된 재조회 — 도는 중이면 뒤따르는 **한 번**으로 합친다.
    package func handleSignal() {
        requestSync()
    }

    /// 신호를 합쳐 한 번 동기화한다.
    package func requestSync() {
        guard host?.session != nil else { return }
        guard syncTask == nil else {
            syncPendingTrailing = true
            return
        }
        let generation = resetGeneration
        syncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.syncPendingTrailing = false
                await self.syncOnce()
            } while self.syncPendingTrailing && generation == self.resetGeneration
            if generation == self.resetGeneration { self.syncTask = nil }
        }
    }

    /// 신호 한 번의 조회: 진행 중 판이 있으면 그 판의 상태, 아니면 로비(창이 보이면 사람 목록까지 · 아니면 가벼운 로비 — CS-4).
    package func syncOnce() async {
        if let current = match, !current.isFinished {
            await refreshMatch(id: current.id)
        } else {
            await loadLobby(users: isWindowVisible)
        }
    }

    package func realtimeDidJoin() {
        guard host?.session != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.loadLobby(users: self.isWindowVisible)
        }
    }

    package func systemDidWake() {
        guard host?.session != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.loadLobby(users: self.isWindowVisible)
        }
    }

    /// 팝오버 경로 → 가벼운 로비(`p_users` false, v1.1 CS-4). 메뉴 스로틀 30초.
    package func refreshLobbyIfStale() {
        guard host?.session != nil else { return }
        let now = clock()
        guard now.timeIntervalSince(lastMenuLobbyAt) >= Self.menuLobbyThrottleSeconds else { return }
        lastMenuLobbyAt = now
        Task { [weak self] in await self?.refreshLightLobby() }
    }

    // MARK: - 폴링 (창이 보이고 안 가려졌을 때만 · 판 밖)

    package func startPolling() {
        guard pollTask == nil, isWindowVisible, !isWindowOccluded else { return }
        pollToken &+= 1
        let token = pollToken
        pollTask = Task { @MainActor [weak self] in
            while true {
                let step = self?.pollStepSeconds ?? 0.5
                try? await Task.sleep(for: .seconds(step))
                guard let self else { return }
                guard !Task.isCancelled, token == self.pollToken, self.isWindowVisible, !self.isWindowOccluded else {
                    if token == self.pollToken { self.pollTask = nil }
                    return
                }
                await self.pollTick(at: self.clock())
            }
        }
    }

    package func stopPolling() {
        pollToken &+= 1
        pollTask?.cancel()
        pollTask = nil
    }

    /// 폴링 한 걸음의 조회를 **폴링 작업의 취소 밖에서** 돌리고 끝날 때까지 기다린다(규칙 ④ — 창을 닫는 순간의 취소가 합쳐진
    /// 초인종 조회까지 죽이지 않게).
    private func outsidePolling(_ body: @escaping @MainActor (CrossyDuelStore) async -> Void) async {
        await Task { @MainActor [weak self] in
            guard let self else { return }
            await body(self)
        }.value
    }

    /// 안전망 한 걸음. **창이 안 보이거나 가려졌으면 아무것도 하지 않는다.** 걸음 사이사이 창 보임 · 가림 · 취소를 다시 본다(규칙 ④).
    ///  · 보낸 신청이 있으면 5초마다 그 판의 상태 · 로비를 보고 있으면 30초마다 목록 · 순위 60초(주 스위치)
    /// **판 중에는 조회하지 않는다** — 보고 응답이 판 상태를 가져온다.
    package func pollTick(at now: Date) async {
        guard isWindowVisible, !isWindowOccluded, host?.session != nil else { return }
        if let sent = outgoing, now.timeIntervalSince(lastOutgoingRequestAt) >= Self.outgoingPollSeconds {
            let id = sent.id
            await outsidePolling { await $0.refreshMatch(id: id) }
        }
        guard isWindowVisible, !isWindowOccluded, !Task.isCancelled else { return }
        if phase == .lobby, now.timeIntervalSince(lastLobbyRequestAt) >= Self.lobbyPollSeconds {
            await outsidePolling { await $0.refreshLobby() }
        }
        guard isWindowVisible, !isWindowOccluded, !Task.isCancelled else { return }
        if rankingEnabled, phase == .lobby, now.timeIntervalSince(lastRankingRequestAt) >= Self.rankingPollSeconds {
            await refreshRanking()
        }
    }

    // MARK: - 리셋

    /// 로그아웃 · 계정 전환. 판·신청·목록을 비운다. **배선 값**(`rankingEnabled` · 시계 · 주기 · UI 문)은 건드리지 않는다.
    package func reset() {
        resetGeneration &+= 1
        stopPolling()
        discardDuel()
        expiryTask?.cancel()
        expiryTask = nil
        syncTask?.cancel()
        syncTask = nil
        syncPendingTrailing = false
        stateInFlight = false
        stateAgain = false
        lobbyInFlight = false
        lobbyAgain = false
        lobbyAgainWantsUsers = false
        rankingInFlight = false
        stateInFlightID = nil
        pendingStateID = nil
        if phase != .lobby { phase = .lobby }
        if availability != .available { availability = .available }
        if !users.isEmpty { users = [] }
        if record != nil { record = nil }
        if !incoming.isEmpty { incoming = [] }
        if outgoing != nil { outgoing = nil }
        if match != nil { match = nil }
        if notice != nil { notice = nil }
        if isBusy { isBusy = false }
        if isWindowVisible { isWindowVisible = false }
        if isWindowOccluded { isWindowOccluded = false }
        if rubyBalance != nil { rubyBalance = nil }
        if !hiddenPeerIDs.isEmpty { hiddenPeerIDs = [] }
        if lobbyLoadFailed { lobbyLoadFailed = false }
        if hasLoadedLobby { hasLoadedLobby = false }
        if connectionTrouble { connectionTrouble = false }
        if playingElsewhere { playingElsewhere = false }
        if ranking != nil { ranking = nil }
        if rankingUnavailable { rankingUnavailable = false }
        yieldedMatchIDs = []
        heldMySeq = 0
        heldOpponentSeq = 0
        opponentSilenceAtReceipt = nil
        opponentSilenceReceivedAt = nil
        serverClockOffset = 0
        hasServerClockOffset = false
        rubyServerNowMs = nil
        activeMatchID = nil
        seenInviteIDs = []
        announcedMatchIDs = []
        dismissedMatchIDs = []
        outgoingRevision = 0
        lobbyRequestOutgoingRevision = 0
        lastStateRequestAt = .distantPast
        lastLobbyRequestAt = .distantPast
        lastOutgoingRequestAt = .distantPast
        lastMenuLobbyAt = .distantPast
        lastRankingRequestAt = .distantPast
        inviteTTLSeconds = 60
        syncHoldingActivity()
        dismissWindow?()
    }

    // MARK: - 내부

    /// 공용 호출 관용구: 세션 가드 → 두 세대 캡처 → withSessionRetry → 두 세대 대조.
    /// nil = 버린 결과(세션 없음·세대가 밀림·취소). 호출부는 nil 이면 **아무것도 바꾸지 않는다.**
    package func perform<T: Sendable>(
        _ operation: @escaping @Sendable (SupabaseWorkService, String) async throws -> T
    ) async -> Result<T, any Error>? {
        guard let host, host.session != nil else { return nil }
        let sessionGeneration = host.sessionGeneration
        let generation = resetGeneration
        let service = host.service
        do {
            let value = try await host.withSessionRetry { session in
                try await operation(service, session.accessToken)
            }
            guard host.sessionGeneration == sessionGeneration, generation == resetGeneration else { return nil }
            return .success(value)
        } catch {
            guard host.sessionGeneration == sessionGeneration, generation == resetGeneration else { return nil }
            if case .cancelled = host.classifyAuthError(error) { return nil }
            return .failure(error)
        }
    }

    /// 서버에 길건너 RPC 가 아직 없다(PGRST202).
    package nonisolated func isSchemaMissing(_ error: any Error) -> Bool {
        (error as? SupabaseWorkServiceError) == .databaseSchemaMissing
    }

    private func noteActionFailure(_ error: any Error) {
        if isSchemaMissing(error) {
            noteServerMissing()
        } else {
            setNotice(CrossyDuelNoticeText.checkConnection)
        }
    }

    func noteServerMissing() {
        if availability != .serverMissing { availability = .serverMissing }
        setNotice(CrossyDuelNoticeText.unavailable)
    }

    func noteUpdateRequired() {
        if availability != .updateRequired { availability = .updateRequired }
        setNotice(CrossyDuelNoticeText.updateMine)
    }

    /// 로비 신청 행 → 화면 값. 하나라도 모르면 **그 카드를 만들지 않는다**.
    private func invite(from row: CrossyDuelInviteRow, peer peerRow: CrossyDuelPeerRow?) -> CrossyDuelInvite? {
        guard let id = row.matchId?.lowercased(), !id.isEmpty,
              let stake = row.stake,
              let expiresAt = deviceDate(serverMs: row.expiresAtMs),
              let peer = peerUser(id: peerRow?.id, displayName: peerRow?.displayName,
                                  avatarURL: peerRow?.avatarUrl, character: peerRow?.character, inMatch: false)
        else { return nil }
        return CrossyDuelInvite(id: id, peer: peer, stake: stake, expiresAt: expiresAt)
    }

    /// 그 id 가 판이었으면 판을 내리고, 신청이었으면 신청 카드를 걷는다(안내가 있으면 한 줄 — 보낸 신청만).
    private func dropMatchOrInvite(_ id: String, notice: String? = nil) {
        dropOwnership(id)
        if match?.id == id { clearMatch() }
        if activeMatchID == id { activeMatchID = nil }
        if incoming.contains(where: { $0.id == id }) {
            incoming.removeAll { $0.id == id }
            scheduleInviteExpiry()
        }
        if outgoing?.id == id {
            outgoing = nil
            if let notice { setNotice(notice) }
            scheduleInviteExpiry()
        }
    }

    package nonisolated static func steadyInvite(_ fresh: CrossyDuelInvite, previous: CrossyDuelInvite?) -> CrossyDuelInvite {
        guard let previous, previous.id == fresh.id, previous.stake == fresh.stake, previous.peer == fresh.peer,
              abs(previous.expiresAt.timeIntervalSince(fresh.expiresAt)) < inviteExpiryToleranceSeconds
        else { return fresh }
        return previous
    }

    /// 안내줄 한 문.
    package func setNotice(_ text: String?) {
        if notice != text { notice = text }
    }

    package nonisolated static func matchJustFinished(from old: CrossyDuelMatchState?, to new: CrossyDuelMatchState?) -> Bool {
        guard let new, new.isFinished else { return false }
        return !(old?.id == new.id && old?.isFinished == true)
    }

    package nonisolated static func matchTransitionLine(
        from old: CrossyDuelMatchState?, to new: CrossyDuelMatchState?
    ) -> String? {
        func finished(_ m: CrossyDuelMatchState?) -> Bool { m?.isFinished ?? false }
        func started(_ m: CrossyDuelMatchState?) -> Bool { m?.startAt != nil }
        func ready(_ m: CrossyDuelMatchState?) -> Bool { m?.meReady ?? false }
        let sameMatch = old?.id == new?.id
        guard !sameMatch || finished(old) != finished(new) || started(old) != started(new)
                || ready(old) != ready(new) else { return nil }
        return "state ready=\(ready(new)) started=\(started(new)) finished=\(finished(new)) "
            + "reason=\(new?.endReason?.rawValue ?? "none") sameMatch=\(sameMatch)"
    }

    /// 서버 잔액을 스토어 · 앱 미러로 옮긴다. 늦은 응답 가드(§8.3, 검토 RV-C-2): 이미 옮긴 잔액보다 **먼저** 서버가 만든 응답
    /// (정산 뒤 닿은 옛 상태 — 판 값은 `.ignored` 인 그 응답 · 옛 로비)의 잔액은 버린다(105 를 95 로 되감지 않게).
    /// 서버 시각이 없는 응답은 예전처럼 옮긴다.
    func applyRuby(_ value: Int?, serverNowMs: Double?) {
        guard let value else { return }
        if let at = serverNowMs, at.isFinite, at > 0 {
            if let last = rubyServerNowMs, at < last { return }
            rubyServerNowMs = at
        }
        if rubyBalance != value { rubyBalance = value }
        if let host, host.rubyBalance != value { host.rubyBalance = value }
    }

    /// 판을 내린다(판 구동기 · 판 루프 · 보고 · 프레임까지).
    package func clearMatch() {
        if match != nil { match = nil }
        if playingElsewhere { playingElsewhere = false }
        discardDuel()
        refreshPhase()
    }

    /// 진행 중 판으로 **처음** 넘어갔다 — 창을 띄우고 주의를 끈다. 창이 안 보였거나 가려졌으면 말풍선 문도 연다(판 id 마다 한 번).
    private func noteMatchStarted(_ next: CrossyDuelMatchState, windowWasVisible: Bool) {
        guard !announcedMatchIDs.contains(next.id) else { return }
        announcedMatchIDs.insert(next.id)
        presentWindow?()
        requestAttention?()
        guard !windowWasVisible else { return }
        onAttention?(CrossyDuelAttention(kind: .matchStarted, matchID: next.id, opponentName: next.opponent.displayName))
    }

    /// `server_now_ms` 로 기기 시계 어긋남을 잰다. 처음 잰 값은 그대로, 그 뒤로는 문턱(250ms) 넘게 벗어날 때만.
    package func noteServerNow(_ milliseconds: Double?) {
        guard let milliseconds, milliseconds > 0 else { return }
        let measured = milliseconds / 1000 - clock().timeIntervalSince1970
        guard !hasServerClockOffset || abs(measured - serverClockOffset) >= Self.serverClockToleranceSeconds
        else { return }
        serverClockOffset = measured
        hasServerClockOffset = true
    }

    /// 서버 epoch 밀리초 → 기기 시계의 같은 순간.
    package func deviceDate(serverMs milliseconds: Double?) -> Date? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000 - serverClockOffset)
    }

    /// 가장 이른 만료 시각에 한 번 깨어나 만료된 신청을 걷는다(배너가 시계를 읽지 않게 하는 장치).
    package func scheduleInviteExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        let dates = incoming.map(\.expiresAt) + [outgoing?.expiresAt].compactMap { $0 }
        guard let earliest = dates.min() else { return }
        let delay = max(0, earliest.timeIntervalSince(clock())) + 0.25
        let generation = resetGeneration
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, generation == self.resetGeneration else { return }
            self.expiryTask = nil
            self.pruneExpiredInvites(now: self.clock())
        }
    }

    package func pruneExpiredInvites(now: Date) {
        if incoming.contains(where: { $0.expiresAt <= now }) { incoming.removeAll { $0.expiresAt <= now } }
        if let sent = outgoing, sent.expiresAt <= now {
            outgoing = nil
            setNotice(CrossyDuelNoticeText.inviteTimedOut)
        }
        scheduleInviteExpiry()
    }

    /// 사람 조각 → 화면 값. 행에 없는 칸은 로비 목록에서 빌린다.
    package func peerUser(id rawID: String?, displayName: String?, avatarURL: String?, character: String?,
                          inMatch: Bool) -> CrossyDuelUser? {
        guard let id = rawID?.lowercased(), !id.isEmpty else { return nil }
        let known = users.first { $0.id == id }
        return CrossyDuelUser(
            id: id,
            displayName: displayName ?? known?.displayName ?? "",
            avatarURL: avatarURL ?? known?.avatarURL,
            characterID: character ?? known?.characterID,
            isWorking: known?.isWorking ?? false,
            isCapable: known?.isCapable ?? true,
            inMatch: inMatch,
            isFocused: known?.isFocused ?? false)
    }

    /// 서버 사람 행 → 화면 값(로비). `capable` 이 nil 이면 **불가**다.
    package nonisolated static func user(from row: CrossyDuelUserRow) -> CrossyDuelUser? {
        guard let id = row.id?.lowercased(), !id.isEmpty else { return nil }
        return CrossyDuelUser(
            id: id,
            displayName: row.displayName ?? "",
            avatarURL: row.avatarUrl,
            characterID: row.character,
            isWorking: row.isWorking ?? false,
            isCapable: row.capable ?? false,
            inMatch: row.inMatch ?? false,
            isFocused: row.focusMode ?? false)
    }

    /// 로비 정렬: 서버 정렬과 같은 규칙(working desc → capable desc → 이름 → 원래 순서)의 되맞춤.
    package nonisolated static func sortedForLobby(_ users: [CrossyDuelUser]) -> [CrossyDuelUser] {
        func rank(_ user: CrossyDuelUser) -> Int {
            if user.isWorking && user.isCapable && !user.inMatch { return 0 }
            if user.isWorking && user.isCapable { return 1 }
            if user.isWorking { return 2 }
            return 3
        }
        return users.enumerated().sorted { lhs, rhs in
            let (l, r) = (rank(lhs.element), rank(rhs.element))
            if l != r { return l < r }
            let order = lhs.element.displayName.localizedStandardCompare(rhs.element.displayName)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}
