import Foundation
import Observation
import OSLog

// 1:1 길건너 대결 스토어 — 화면 상태 · 서버 동기화 · 판 구동 · 보고 루프 · RPC 호출(SPEC v1.3 §8.3, TetrisDuelStore 규약).
//
// ★ C1 뼈대: **표면(타입 · 프로퍼티 · 메서드 서명)만** 있다. 갈래 U(화면)·T(배선)가 이 이름 그대로 선다.
//   몸통은 안전한 기본값 · 빈 몸통이고(네트워크 0 · 타이머 0 · fatalError 0) C2 이후가 채운다.
//
// 규약(MC:47-78 · 메모리 duel-store-alert-doorbell-rules — C2 가 처음부터 지킨다):
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
    package internal(set) var match: CrossyDuelMatchState?
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

    // MARK: 판 표시 프레임 (관찰 대상 아님 — 로직은 CrossyDuelStoreFrames.swift)

    /// 이 판의 프레임 장부(순수). 이 기기가 두는 판에서만 선다.
    @ObservationIgnored package internal(set) var frameLink: CrossyDuelFrameLink?
    /// 프레임 소켓(판마다 다시 쓰는 한 개). nil 이면 이 기기는 프레임을 못 연다(시험 프로세스 — 대체 길).
    @ObservationIgnored package internal(set) var frameChannel: (any CrossyDuelFrameChannel)?
    /// 프레임 소켓을 만드는 문(시험이 스텁을 끼운다). 받는 값은 리얼타임 킬스위치를 읽을 저장소(`deviceLedger.defaults` 없으면 `.standard`).
    @ObservationIgnored package var makeFrameChannel: @MainActor (UserDefaults) -> (any CrossyDuelFrameChannel)? = { defaults in
        CrossyDuelStore.defaultFrameChannel(defaults: defaults)
    }

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

    // MARK: 수명 · 창

    /// 로그아웃 · 계정 전환. 판·신청·목록을 비운다(C1: 화면 상태만 비운다).
    package func reset() {
        phase = .lobby
        availability = .available
        users = []
        record = nil
        incoming = []
        outgoing = nil
        match = nil
        notice = nil
        isBusy = false
        rubyBalance = nil
        hasLoadedLobby = false
        lobbyLoadFailed = false
        connectionTrouble = false
        playingElsewhere = false
        ranking = nil
        rankingUnavailable = false
        duel = nil
        discardFrames()
    }

    /// 창을 띄운다(받은 신청 · 진행 판에 초점). C1: 창 문만 부른다.
    package func openWindow(focusMatchID: String?) {
        _ = focusMatchID
        presentWindow?()
    }

    package func windowDidShow() {
        isWindowVisible = true
    }

    package func windowDidHide() {
        isWindowVisible = false
    }

    package func windowDidClose() {
        isWindowVisible = false
    }

    package func windowOcclusionDidChange(visible: Bool) {
        isWindowOccluded = !visible
    }

    // MARK: 동기화 (C1 빈 몸통)

    /// 초인종 신호(`.crossyDuelSignal`).
    package func handleSignal() {}

    /// 신호를 합쳐 한 번 동기화한다.
    package func requestSync() {}

    package func realtimeDidJoin() {}

    package func systemDidWake() {}

    /// 팝오버 경로 → 가벼운 로비(`p_users` false, v1.1 CS-4). 메뉴 스로틀 30초.
    package func refreshLobbyIfStale() {}

    /// 창 경로 → 사람 목록까지.
    package func refreshLobby() async {}

    /// 로비 응답을 옮긴다. 가벼운 응답(`users` 빈 배열 · 전적 null)은 `users`·`record` 를 덮지 않는다(v1.1 CS-4).
    package func applyLobby(_ response: CrossyDuelLobbyResponse) async {
        _ = response
    }

    package enum StateApplyOutcome: Equatable { case applied, ignored }

    /// 판 상태를 옮긴다(늦은 응답 버리기 · seq 단조 · 끝난 판 되돌리지 않음). C1: 언제나 `.ignored`.
    @discardableResult
    package func applyState(_ payload: CrossyDuelStatePayload, receivedAt: TimeInterval? = nil) -> StateApplyOutcome {
        _ = (payload, receivedAt)
        return .ignored
    }

    // MARK: 신청 · 응답 · 기권 (C1 빈 몸통)

    package func challenge(userID: String, stake: CrossyDuelStake) async {
        _ = (userID, stake)
    }

    package func cancelChallenge() async {}

    package func respond(inviteID: String, accept: Bool) async {
        _ = (inviteID, accept)
    }

    package func resign() async {}

    /// 결과 화면에서 로비로.
    package func backToLobby() {
        guard phase == .finished || match?.isFinished == true || match == nil else { return }
        match = nil
        duel = nil
        discardFrames()
        phase = .lobby
    }
}
