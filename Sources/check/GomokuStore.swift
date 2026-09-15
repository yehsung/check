import Foundation
import Observation
import OSLog

// 1:1 오목 대결 스토어(v0.3.27) — 화면 상태 · 서버 동기화 · 안전망 폴링 · RPC 호출.
//
// ── 이 파일이 지키는 규칙 ──
//  ① **서버가 권위다.** 대국 판·차례·마감·결과·루비는 전부 RPC 응답으로만 바뀐다. 낙관적 착수·낙관적 차감은 없다
//     — 두 곳에서 바꾸면 실패한 수가 화면에서만 놓이고, 실패한 수락이 화면에서만 루비를 뺀다.
//  ② **시각은 서버 시계로 보정한다.** 마감·신청 만료는 서버 epoch 밀리초로 오고, 같은 응답의 server_now_ms 와의
//     차이로 기기 시계 어긋남을 지운다(`serverClockOffset`). 기기 시계가 5초 빠른 맥이 "25초 남음"을 보면 안 된다.
//  ③ **폴링은 창이 보일 때만 돈다**(무료 플랜 예산). 창이 안 보이면 받은 신청은 팝오버 열기(60초 스로틀)·실시간
//     'gomoku' 신호·조인 직후 따라잡기·근무 시작·깨어남에서만 본다.
//  ④ **늦게 온 응답은 버린다.** 로그아웃·계정 전환(host.sessionGeneration)과 이 스토어의 reset(resetGeneration)
//     두 세대를 모두 대조한다 — 하나만 보면 로그아웃 직후 도착한 앞 계정의 판이 새 계정 화면에 뜬다.
//  ⑤ **사용자 문구는 GomokuNoticeText 한 곳에만 있다.** status 이름·서버·동기화 같은 진단 어휘는 화면에 싣지 않는다.
//  ⑥ **초 단위 값은 창의 잎 뷰만 읽는다.** remainingSeconds(now:) 는 잎 뷰 TimelineView 가 now 를 넘겨 부르는
//     순수 계산이고, 이 스토어는 매초 아무것도 대입하지 않는다(팝오버 V0238 무효화 계약).

// MARK: - 화면 값 타입 (설계서 §6.3 선언 그대로 — ui 트랙이 이 선언만 믿고 짠다)

nonisolated enum GomokuStake: Int, CaseIterable, Sendable { case three = 3, five = 5, ten = 10 }

nonisolated struct GomokuUser: Identifiable, Equatable, Sendable {
    let id: String                 // user uuid 소문자 문자열
    let displayName: String
    let avatarURL: String?
    let characterID: String?
    let isWorking: Bool
    let isCapable: Bool            // 상대 앱이 오목을 아는 버전
    let inMatch: Bool
}

nonisolated struct GomokuRecord: Equatable, Sendable { let wins: Int; let losses: Int; let draws: Int }

nonisolated struct GomokuInvite: Identifiable, Equatable, Sendable {
    let id: String                 // match id
    let peer: GomokuUser           // 받은 신청이면 신청자, 보낸 신청이면 상대
    let stake: Int
    let expiresAt: Date            // 기기 시계로 보정된 시각
}

nonisolated enum GomokuEndReason: String, Sendable { case five, timeout, resign, boardFull = "board_full" }

nonisolated enum GomokuOutcome: Equatable, Sendable { case won, lost, draw }

nonisolated struct GomokuMatchState: Identifiable, Equatable, Sendable {
    let id: String
    var stake: Int
    var myColor: GomokuColor
    var opponent: GomokuUser
    var board: GomokuBoard
    var lastMove: GomokuPoint?
    var moveCount: Int
    var turn: GomokuColor?         // 끝나면 nil
    var deadline: Date?            // 차례 마감(기기 시계로 보정), 끝나면 nil
    var isFinished: Bool
    var outcome: GomokuOutcome?
    var endReason: GomokuEndReason?
    var rubyDelta: Int?            // 이 판으로 내 루비가 변한 양(승 +stake, 패 -stake, 무 0)
    var blackPassed: Bool          // 직전에 흑 자동 패스가 있었다
}

nonisolated enum GomokuPhase: Equatable, Sendable { case lobby, playing, result }

/// 창이 안 보이는 사람에게 "지금 둘 차례"를 알리는 한 건(캐릭터 말풍선으로 간다 — CheckApp 배선).
/// 같은 (판 id, move_count) 에는 한 번만 만든다.
nonisolated struct GomokuAttention: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// 판이 막 시작됐고 내가 먼저 둔다(흑).
        case matchStarted
        /// 상대가 뒀고 이제 내 차례다.
        case myTurn
    }

    let kind: Kind
    let matchID: String
    let opponentName: String
    /// 이 알림을 만든 순간의 기록 수. 말풍선을 띄우기 직전 판이 이미 넘어갔는지 대조한다.
    let moveCount: Int
}

// MARK: - 문구 표 (사용자 어휘 — 이 표 밖에서 문구를 만들지 마라)

/// 오목 안내 한 줄의 **유일한 출처**. status → 문구 변환이 여러 곳에 흩어지면 같은 거절이 화면마다 다른 말을 한다.
/// 진단 어휘(서버·상태·동기화·토큰 등)는 쓰지 않는다 — 사용자가 할 수 있는 일을 말한다.
nonisolated enum GomokuNoticeText {
    static let tryAgain = "잠시 후 다시 시도해 주세요"
    static let checkConnection = "연결을 확인하고 다시 시도해 주세요"
    static let updateMine = "앱을 업데이트해야 대결할 수 있어요"
    static let signInAgain = "다시 로그인해 주세요"
    static let notYourTurn = "상대 차례예요"
    static let inviteTimedOut = "상대가 응답하지 않았어요"
    /// 보낸 신청이 만료 전에 사라졌다(거절·취소·상대가 다른 대국을 시작함 — 사용자에게는 모두 같은 뜻이다).
    static let inviteDeclined = "상대가 신청을 받지 않았어요"
    /// 착수·기권을 눌렀는데 그 전에 시간이 넘어 판이 이미 끝났다.
    static let timedOut = "시간이 지나 대국이 끝났어요"
    static let finishedInvite = "이미 끝난 신청이에요"
    static let finishedMatch = "이미 끝난 대국이에요"
    static let cannotPlace = "둘 수 없는 자리예요"
    static let busy = "이미 진행 중인 대국이 있어요"
    static let targetBusy = "상대가 다른 대국 중이에요"

    /// 금수 사유별 문구. 상태줄과 호버 이유가 같은 말을 한다.
    static func forbidden(_ reason: GomokuForbiddenReason) -> String {
        switch reason {
        case .doubleThree: return "3-3 금수라 둘 수 없어요"
        case .doubleFour: return "4-4 금수라 둘 수 없어요"
        case .overline: return "장목 금수라 둘 수 없어요"
        case .budget: return "판정할 수 없는 자리예요"
        }
    }

    /// 신청(gomoku_challenge) 결과.
    static func challenge(_ status: GomokuRPCStatus, need: Int? = nil, have: Int? = nil) -> String {
        switch status {
        case .ok: return "신청을 보냈어요"
        case .invalid: return "신청할 수 없는 상대예요"
        case .blackout: return "지금은 조용한 기간이라 신청할 수 없어요"
        case .notWorking: return "근무 중일 때만 신청할 수 있어요"
        case .targetNotWorking: return "상대가 근무 중이 아니에요"
        case .targetFocused: return "상대가 집중 모드라 신청할 수 없어요"
        case .targetOutdated: return "상대가 앱을 업데이트해야 해요"
        case .busy: return busy
        case .targetBusy: return targetBusy
        case .alreadyPending: return "이미 보낸 신청이 있어요"
        case .insufficient: return WorkTimerStore.shortfallNotice(need: need, have: have)
        default: return common(status)
        }
    }

    /// 신청 취소(gomoku_cancel) 결과.
    static func cancel(_ status: GomokuRPCStatus) -> String {
        switch status {
        case .ok: return "신청을 취소했어요"
        case .notFound, .notPending, .expired: return finishedInvite
        default: return common(status)
        }
    }

    /// 수락·거절(gomoku_respond) 결과. 수락 성공은 판이 곧바로 열리므로 말하지 않는다(nil).
    static func respond(
        accept: Bool, _ status: GomokuRPCStatus, side: String? = nil, need: Int? = nil, have: Int? = nil
    ) -> String? {
        switch status {
        case .ok: return accept ? nil : "신청을 거절했어요"
        case .notFound, .notPending: return finishedInvite
        case .expired: return "신청 시간이 지났어요"
        case .notWorking: return "근무 중일 때만 수락할 수 있어요"
        case .targetNotWorking: return "상대가 근무를 끝냈어요"
        case .busy: return busy
        case .targetBusy: return targetBusy
        case .insufficient:
            if side == "challenger" { return "상대의 루비가 모자라요" }
            return WorkTimerStore.shortfallNotice(need: need, have: have)
        default: return common(status)
        }
    }

    /// 착수(gomoku_move) 결과. 성공·판이 바뀐 경우(stale — 곧바로 다시 불러온다)는 말하지 않는다(nil).
    static func move(_ status: GomokuRPCStatus, reason: String? = nil) -> String? {
        switch status {
        case .ok, .stale: return nil
        case .forbidden:
            return GomokuForbiddenReason(serverReason: reason).map(forbidden) ?? cannotPlace
        case .timeout: return timedOut
        case .notYourTurn: return notYourTurn
        case .notActive, .notFound: return finishedMatch
        case .invalid: return cannotPlace
        default: return common(status)
        }
    }

    /// 기권(gomoku_resign) 결과. 성공은 결과 화면이 말한다(nil).
    /// 서버는 기권보다 시간 초과를 먼저 정산해 `timeout` + 끝난 판을 돌려준다 — 착수와 같은 말을 한다.
    static func resign(_ status: GomokuRPCStatus) -> String? {
        switch status {
        case .ok: return nil
        case .timeout: return timedOut
        case .notActive, .notFound: return finishedMatch
        default: return common(status)
        }
    }

    private static func common(_ status: GomokuRPCStatus) -> String {
        switch status {
        case .unsupportedClient: return updateMine
        case .unauthorized: return signInAgain
        default: return tryAgain
        }
    }
}

// MARK: - 스토어

@MainActor
@Observable
final class GomokuStore {
    /// 상대 차례의 대국 상태 안전망 조회 주기(초) — 실시간 구독 중.
    nonisolated static let statePollSecondsWhileSubscribed: TimeInterval = 3
    /// 같은 조회 — 미구독(킬스위치·재연결 중). 신호가 없으니 더 촘촘하다.
    nonisolated static let statePollSecondsUnsubscribed: TimeInterval = 1.5
    /// 내 대기 신청이 있을 때 받은 쪽의 응답을 보는 주기(초).
    nonisolated static let outgoingInboxPollSeconds: TimeInterval = 5
    /// 로비 목록 재조회 주기(초). 창을 열 때 한 번 + 로비를 보고 있는 동안 이 주기.
    nonisolated static let lobbyPollSeconds: TimeInterval = 30
    /// 팝오버를 열 때 받은 신청을 보는 스로틀(초). 팀 메타 재조회와 같은 눈금이다.
    nonisolated static let menuInboxThrottleSeconds: TimeInterval = 60
    /// 서버가 턴 제한에 더하는 네트워크 유예(초). 서버 `gomoku_turn_grace_seconds()` 와 같은 값 — 표시 마감이 이만큼
    /// 지나도 결과가 안 왔으면 내 차례여도 한 번 물어본다(서버는 누가 부르든 시간 초과를 먼저 정산한다).
    nonisolated static let turnGraceSeconds: TimeInterval = 2
    /// 창 열기(openWindow)와 창 표시(windowDidShow)가 같은 조회를 두 번 쏘지 않게 하는 간격(초).
    nonisolated static let reloadDedupeSeconds: TimeInterval = 1
    /// 서버 시계 오프셋을 다시 재는 문턱(초). 응답마다 왕복 지연이 몇 ms 씩 달라지는데, 그때마다 오프셋을 갈면
    /// 같은 신청의 만료·같은 차례의 마감이 응답마다 다른 값이 되어 팝오버·창 루트가 헛되이 다시 그려진다.
    nonisolated static let serverClockToleranceSeconds: TimeInterval = 0.25
    /// 같은 신청(id·판돈·상대가 같음)을 다시 읽었을 때 만료 시각이 이만큼 안쪽으로만 다르면 기존 값을 쓴다(초).
    nonisolated static let inviteExpiryToleranceSeconds: TimeInterval = 1
    /// 같은 차례(기록 수·차례가 같음)를 다시 읽었을 때 마감이 이만큼 안쪽으로만 다르면 기존 값을 쓴다(초).
    nonisolated static let deadlineToleranceSeconds: TimeInterval = 0.5

    nonisolated static let logger = Logger(subsystem: "kingcheck", category: "gomoku")

    /// 네트워크·세션·루비 미러를 빌리는 곳. **약참조다** — WorkTimerStore 가 이 스토어를 소유한다.
    /// nil 이면 미리보기·렌더 테스트용이라 네트워크를 한 건도 내지 않는다.
    @ObservationIgnored private(set) weak var host: WorkTimerStore?

    init(host: WorkTimerStore? = nil) {
        self.host = host
    }

    /// 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다(저장 프로퍼티를 다 채우기 전에는 self 를 넘길 수 없다).
    func attach(host: WorkTimerStore) {
        self.host = host
    }

    // MARK: 화면 상태 — 전부 internal set(렌더 테스트가 직접 채운다)

    var phase: GomokuPhase = .lobby
    var users: [GomokuUser] = []
    var record: GomokuRecord?
    var selectedStake: GomokuStake = .three
    var incoming: [GomokuInvite] = []
    var outgoing: GomokuInvite?
    var match: GomokuMatchState?
    /// 사용자 어휘 안내 한 줄.
    var notice: String?
    var isBusy = false
    var isWindowVisible = false
    var isRulesVisible = false
    /// 서버 응답으로만 갱신(host 에도 반영).
    var rubyBalance: Int?
    /// 한 수 제한(초). 서버 로비 응답이 말해 주면 그 값, 아니면 설계값 30.
    var turnSeconds = 30
    /// 마지막 상대 목록 조회가 실패했다. 빈 목록을 "상대가 없다"로 보여 주지 않기 위한 값이다.
    var lobbyLoadFailed = false
    /// 이번 로그인에서 상대 목록을 한 번이라도 받았다.
    var hasLoadedLobby = false

    /// 팝오버 배너·말풍선이 쓰는 대표 신청(만료 안 된 받은 신청 중 가장 오래된 것).
    /// **시계를 읽지 않는다** — 만료된 신청은 스토어가 만료 시각에 `incoming` 에서 걷어낸다(pruneExpiredInvites).
    /// 여기서 Date() 를 읽으면 배너 body 가 시각 판정을 하게 되어 팝오버 전체가 시계에 묶인다.
    var bannerInvite: GomokuInvite? {
        incoming.reduce(nil) { best, invite in
            guard let best else { return invite }
            return invite.expiresAt < best.expiresAt ? invite : best
        }
    }

    // MARK: UI 트랙이 CheckApp 에서 물리는 문

    /// 창 띄우기(컨트롤러 show).
    @ObservationIgnored var presentWindow: (@MainActor () -> Void)?
    /// 새 받은 신청(처음 본 id 한 번).
    @ObservationIgnored var onInviteArrived: (@MainActor (GomokuInvite) -> Void)?
    /// 창 닫기(컨트롤러 close). reset() 이 부른다 — 로그아웃한 뒤 앞 계정의 판이 떠 있으면 안 된다.
    @ObservationIgnored var dismissWindow: (@MainActor () -> Void)?
    /// 판이 막 시작됐다 — 앱이 앞에 없으면 사용자의 주의를 끈다(CheckApp 이 NSApp.requestUserAttention 으로 잇는다).
    @ObservationIgnored var requestAttention: (@MainActor () -> Void)?
    /// 창이 안 보이는 동안 차례가 나에게 왔다(같은 판 id·기록 수에 한 번). CheckApp 이 캐릭터 말풍선으로 잇는다.
    @ObservationIgnored var onAttention: (@MainActor (GomokuAttention) -> Void)?

    // MARK: 내부 장부 (관찰 대상 아님)

    /// 이 스토어의 '지금'. 테스트가 갈아 끼운다.
    @ObservationIgnored var clock: () -> Date = { Date() }
    /// 폴링 루프의 한 걸음(초). 주기 판정은 pollTick 이 하고, 이 값은 그 판정을 얼마나 자주 묻는지다.
    @ObservationIgnored var pollStepSeconds: TimeInterval = 0.5
    /// 서버 시계 − 기기 시계(초). server_now_ms 가 올 때마다 갱신한다.
    @ObservationIgnored private(set) var serverClockOffset: TimeInterval = 0
    /// 오프셋을 한 번이라도 쟀는가(처음 잰 값은 문턱과 무관하게 받는다).
    @ObservationIgnored private var hasServerClockOffset = false
    @ObservationIgnored private(set) var resetGeneration = 0
    /// 창이 다른 창에 완전히 가려졌거나 다른 Space·잠금 화면에 있다(창 컨트롤러의 가림 통지).
    /// **폴링만** 이 값을 본다 — 시계 잎 뷰·말풍선 판정은 `isWindowVisible` 그대로다(가림 통지가 틀려도 보이는 창의 시계는 돈다).
    @ObservationIgnored private(set) var isWindowOccluded = false
    /// 지금 조회 중인 판 id 와, 그 사이 다른 판으로 들어온 조회 요청(마지막 것 하나).
    @ObservationIgnored private(set) var stateInFlightID: String?
    @ObservationIgnored private var pendingStateID: String?
    /// 마지막으로 "내 차례가 왔다"를 본 (판 id#기록 수). 같은 차례에 말풍선이 두 번 뜨지 않게 한다.
    @ObservationIgnored private var attentionKey: String?
    /// 결과 화면을 한 번이라도 세운 끝난 판(받은함 last_finished 로 같은 결과를 다시 세우지 않는다).
    @ObservationIgnored private(set) var shownResultIDs: Set<String> = []
    /// 보낸 신청을 이 기기에서 새로 세울 때마다 오른다. 그보다 **먼저** 나간 받은함 응답이 방금 보낸 신청을 지우지 않게 한다.
    @ObservationIgnored private var outgoingRevision = 0
    @ObservationIgnored private var inboxRequestOutgoingRevision = 0
    /// 서버가 말한 내 진행 중 대국 id(로비·인박스·상태 응답).
    @ObservationIgnored private(set) var activeMatchID: String?
    /// onInviteArrived 를 이미 부른 받은 신청 id.
    @ObservationIgnored private(set) var seenInviteIDs: Set<String> = []
    /// [로비로] 로 접은 끝난 판. 늦게 온 그 판의 상태 응답이 사용자를 결과 화면으로 끌고 가지 않게 한다.
    @ObservationIgnored private(set) var dismissedMatchIDs: Set<String> = []
    @ObservationIgnored private(set) var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pollToken = 0
    @ObservationIgnored private(set) var syncTask: Task<Void, Never>?
    @ObservationIgnored private var syncPendingTrailing = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var stateInFlight = false
    @ObservationIgnored private var stateAgain = false
    @ObservationIgnored private var inboxInFlight = false
    @ObservationIgnored private var inboxAgain = false
    @ObservationIgnored private var lobbyInFlight = false
    @ObservationIgnored var lastStateRequestAt: Date = .distantPast
    @ObservationIgnored var lastInboxRequestAt: Date = .distantPast
    @ObservationIgnored var lastLobbyRequestAt: Date = .distantPast
    @ObservationIgnored private var lastMenuInboxAt: Date = .distantPast
    @ObservationIgnored private var inviteTTLSeconds: TimeInterval = 60
    @ObservationIgnored private var lastOpponent: GomokuUser?
    @ObservationIgnored private var lastStake: Int?

    // MARK: - 창

    /// 상태 로드 시작 + presentWindow?().
    ///
    /// `focusMatchID` 는 말풍선·배너에서 온 경로의 대상이다. 받은 신청이면 로비의 받은 신청 카드가 그것을 보여 주고,
    /// 대국이면 그 판을 불러온다.
    func openWindow(focusMatchID: String?) {
        if host?.session != nil {
            let focus = focusMatchID?.lowercased()
            // 곧 이어질 windowDidShow 가 같은 조회를 또 쏘지 않도록 **동기로** 먼저 적는다(Task 는 아직 안 돌았다).
            let now = clock()
            lastLobbyRequestAt = now
            lastInboxRequestAt = now
            Task { [weak self] in await self?.refreshLobby() }
            Task { [weak self] in
                guard let self else { return }
                await self.loadInbox()
                if let focus, focus != self.match?.id, !self.incoming.contains(where: { $0.id == focus }) {
                    await self.refreshMatch(id: focus)
                } else if let current = self.match, !current.isFinished {
                    await self.refreshMatch(id: current.id)
                }
            }
        }
        presentWindow?()
    }

    /// 창이 실제로 보이기 시작했다(컨트롤러가 부른다). 폴링 시작·로비/인박스 재조회.
    func windowDidShow() {
        if !isWindowVisible { isWindowVisible = true }
        // 막 앞으로 올라온 창이다. 숨기기 전의 가림 기록이 남아 폴링을 영영 막지 않게 지운다(가려지면 통지가 다시 온다).
        isWindowOccluded = false
        startPolling()
        guard host?.session != nil else { return }
        let now = clock()
        if now.timeIntervalSince(lastLobbyRequestAt) >= Self.reloadDedupeSeconds {
            Task { [weak self] in await self?.refreshLobby() }
        }
        if now.timeIntervalSince(lastInboxRequestAt) >= Self.reloadDedupeSeconds {
            Task { [weak self] in await self?.loadInbox() }
        }
    }

    /// 창이 가려졌다·닫혔다. 폴링만 멈춘다 — **대국은 계속된다**(시간은 서버에서 흐른다).
    func windowDidHide() {
        if isWindowVisible { isWindowVisible = false }
        isWindowOccluded = false
        stopPolling()
    }

    /// 창의 가림 상태가 바뀌었다(다른 창 뒤·다른 Space·잠금 화면). **폴링만** 멈추고 되살린다.
    /// `isWindowVisible` 은 건드리지 않는다 — 가림 통지가 틀려도 보이는 창의 시계가 멈추면 안 된다.
    /// 실시간 신호(handleSignal)는 이 값과 무관하게 계속 받는다.
    func windowOcclusionDidChange(visible: Bool) {
        isWindowOccluded = !visible
        if visible {
            startPolling()
        } else {
            stopPolling()
        }
    }

    // MARK: - 조회

    func refreshLobby() async {
        guard host?.session != nil, !lobbyInFlight else { return }
        lobbyInFlight = true
        let generation = resetGeneration
        defer { if generation == resetGeneration { lobbyInFlight = false } }
        lastLobbyRequestAt = clock()
        guard let result = await perform({ try await $0.gomokuLobby(accessToken: $1) }) else { return }
        switch result {
        case .success(let response):
            applyLobby(response)
        case .failure:
            Self.logger.notice("lobby request failed")
            // 빈 목록을 "대결할 사람이 없다"로 믿게 하지 않는다 — 화면이 연결 안내와 [다시 불러오기]를 그린다.
            if !lobbyLoadFailed { lobbyLoadFailed = true }
        }
    }

    func applyLobby(_ response: GomokuLobbyResponse) {
        guard response.status == .ok else {
            Self.logger.notice("lobby refused status=\(response.status.rawValue, privacy: .public)")
            if response.status == .unsupportedClient { setNotice(GomokuNoticeText.updateMine) }
            return
        }
        noteServerNow(response.serverNowMs)
        if lobbyLoadFailed { lobbyLoadFailed = false }
        if !hasLoadedLobby { hasLoadedLobby = true }
        if let seconds = response.turnSeconds, seconds > 0, turnSeconds != seconds { turnSeconds = seconds }
        if let ttl = response.inviteTtlSeconds, ttl > 0 { inviteTTLSeconds = TimeInterval(ttl) }
        if let me = response.me {
            applyRuby(me.rubyBalance)
            let newRecord = GomokuRecord(wins: me.wins ?? 0, losses: me.losses ?? 0, draws: me.draws ?? 0)
            if record != newRecord { record = newRecord }
            activeMatchID = me.activeMatchId?.lowercased()
        }
        if let rows = response.users {
            let mapped = Self.sortedForLobby(rows.compactMap(Self.user(from:)))
            if users != mapped { users = mapped }
        }
        if let active = activeMatchID, match?.id != active {
            Task { [weak self] in await self?.refreshMatch(id: active) }
        }
    }

    /// 받은·보낸 신청과 진행 중 대국 id 를 읽는다. 도는 중에 또 불리면 **뒤따르는 한 번으로 합친다** —
    /// 버리면 조회가 나간 뒤 도착한 신호(신청·수락)가 다음 계기까지 화면에 안 온다.
    func loadInbox() async {
        guard host?.session != nil else { return }
        if inboxInFlight {
            inboxAgain = true
            return
        }
        inboxInFlight = true
        let generation = resetGeneration
        repeat {
            inboxAgain = false
            lastInboxRequestAt = clock()
            inboxRequestOutgoingRevision = outgoingRevision
            let result = await perform({ try await $0.gomokuInbox(accessToken: $1) })
            guard generation == resetGeneration else { return }
            switch result {
            case .success(let response)?:
                await applyInbox(response)
                guard generation == resetGeneration else { return }
            case .failure?:
                Self.logger.notice("inbox request failed")
            case nil:
                break
            }
        } while inboxAgain
        inboxInFlight = false
    }

    func applyInbox(_ response: GomokuInboxResponse) async {
        guard response.status == .ok else {
            Self.logger.notice("inbox refused status=\(response.status.rawValue, privacy: .public)")
            if response.status == .unsupportedClient { setNotice(GomokuNoticeText.updateMine) }
            return
        }
        noteServerNow(response.serverNowMs)
        applyRuby(response.rubyBalance)
        let now = clock()
        let previousIncoming = incoming
        let received = (response.incoming ?? [])
            .compactMap { row in invite(from: row, peerRow: row.challenger, fallbackPeer: nil) }
            .filter { $0.expiresAt > now }
            .map { fresh in Self.steadyInvite(fresh, previous: previousIncoming.first { $0.id == fresh.id }) }
        if incoming != received { incoming = received }
        let previousOutgoing = outgoing
        let active = response.activeMatchId?.lowercased()
        // 이 응답은 방금 이 기기가 세운 보낸 신청보다 먼저 나갔다 — 그 신청이 없다고 해도 사실이 아니다.
        let predatesOutgoing = inboxRequestOutgoingRevision < outgoingRevision
        var sent = response.outgoing
            .flatMap { row in
                invite(from: row, peerRow: row.opponent,
                       fallbackPeer: outgoing?.id == row.matchId?.lowercased() ? outgoing?.peer : nil)
            }
            .flatMap { $0.expiresAt > now ? $0 : nil }
            .map { fresh in Self.steadyInvite(fresh, previous: previousOutgoing) }
        if sent == nil, predatesOutgoing { sent = previousOutgoing }
        if outgoing != sent { outgoing = sent }
        // 진행 중 대국이 있으면 거절 안내를 하지 않는다 — 내가 다른 신청을 수락해 서버가 보낸 신청을 거둔 것이지 상대가 거절한 게 아니다
        // (수락 전에 나간 받은함이 옛 보낸 신청을 되살렸다가 다음 받은함에서 사라지는 경로 포함).
        let inMatch = active != nil || match.map { !$0.isFinished } == true
        if let gone = previousOutgoing, sent?.id != gone.id, gone.id != active, !predatesOutgoing, !inMatch {
            // 보낸 신청이 받은함에서 사라졌고 판으로 이어지지도 않았다 = 거절·취소(상대가 다른 대국을 시작해 서버가
            // 거둔 경우 포함). 만료 시각이 지났으면 만료 안내와 같은 말을 한다(두 안내가 겹치지 않게).
            setNotice(gone.expiresAt > now ? GomokuNoticeText.inviteDeclined : GomokuNoticeText.inviteTimedOut)
        }
        announceNewInvites()
        scheduleInviteExpiry()

        activeMatchID = active
        if let active {
            if match?.id != active || match?.isFinished == true {
                await refreshMatch(id: active)
            }
        } else if let current = match, !current.isFinished {
            // 로컬은 진행 중인데 서버엔 진행 중 대국이 없다 = 그 사이 끝났다. 결과를 받아 온다.
            await refreshMatch(id: current.id)
        } else if match == nil, phase == .lobby,
                  let finished = response.lastFinished?.matchId?.lowercased(), !finished.isEmpty,
                  !dismissedMatchIDs.contains(finished), !shownResultIDs.contains(finished) {
            // 앱을 다시 켜는 사이 끝난 판(최근 10분)의 결과를 한 번 세운다. 창이 안 보이면 다음에 열 때 보인다.
            shownResultIDs.insert(finished)
            await refreshMatch(id: finished)
        }
    }

    /// 같은 신청을 다시 읽었을 때 만료가 문턱 안쪽으로만 다르면 기존 값을 그대로 쓴다(관찰자를 깨우지 않게).
    nonisolated static func steadyInvite(_ fresh: GomokuInvite, previous: GomokuInvite?) -> GomokuInvite {
        guard let previous, previous.id == fresh.id, previous.stake == fresh.stake, previous.peer == fresh.peer,
              abs(previous.expiresAt.timeIntervalSince(fresh.expiresAt)) < inviteExpiryToleranceSeconds
        else { return fresh }
        return previous
    }

    /// 지금 대국(없으면 서버가 말한 진행 중 대국)을 다시 읽는다.
    func refreshMatch() async {
        await refreshMatch(id: match?.id ?? activeMatchID)
    }

    /// 한 판의 상태를 읽는다. 같은 판을 들고 있으면 `since_seq` 로 **새 수만** 받고, 기록이 이어지지 않으면
    /// 처음부터 한 번 더 받는다. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다(loadInbox 와 같은 이유).
    ///
    /// 도는 중에 **다른 판** id 가 들어오면 합치지 않고 기억했다가 지금 판이 끝난 뒤 그 판을 한 번 읽는다 —
    /// 합치면 뒤따르는 반복이 앞 판만 다시 읽어, 막 수락된 판이 다음 계기까지 화면에 안 온다.
    func refreshMatch(id rawID: String?) async {
        guard let requested = rawID?.lowercased(), !requested.isEmpty, host?.session != nil else { return }
        if stateInFlight {
            if requested == stateInFlightID {
                stateAgain = true
            } else {
                pendingStateID = requested
            }
            return
        }
        stateInFlight = true
        let generation = resetGeneration
        var nextID: String? = requested
        while let id = nextID {
            nextID = nil
            stateInFlightID = id
            var forceFull = false
            repeat {
                stateAgain = false
                let since = (!forceFull && match?.id == id) ? (match?.moveCount ?? 0) : 0
                lastStateRequestAt = clock()
                let result = await perform({ try await $0.gomokuState(accessToken: $1, matchID: id, sinceSeq: since) })
                guard generation == resetGeneration else { return }
                forceFull = false
                guard case .success(let response)? = result else { continue }
                switch response.status {
                case .ok:
                    if applyState(response.state, requestedSince: since) == .needsFull, since > 0 {
                        forceFull = true
                        stateAgain = true
                    }
                case .notFound:
                    if match?.id == id { clearMatch() }
                    if activeMatchID == id { activeMatchID = nil }
                case .unsupportedClient:
                    setNotice(GomokuNoticeText.updateMine)
                default:
                    Self.logger.notice("state refused status=\(response.status.rawValue, privacy: .public)")
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

    enum StateApplyOutcome: Equatable { case applied, needsFull, ignored }

    /// 서버 상태 묶음을 화면 상태로 옮긴다.
    ///
    /// 판은 수 기록에서 다시 쌓는다(서버가 board 문자열을 실어 주면 그것이 권위다). 기록이 이어지지 않으면
    /// (`seq` 가 비었거나 서버 move_count 와 안 맞으면) `.needsFull` 을 돌려 처음부터 다시 받게 한다 —
    /// 구멍 난 판을 그리면 이미 돌이 있는 자리를 비어 있다고 보여 준다. 처음부터 받은 응답(`requestedSince == 0`)도
    /// 안 맞으면 그 판은 있는 그대로 반영한다(차례·결과는 서버 행이 말하므로 결과 화면이 막히지 않는다).
    @discardableResult
    func applyState(
        _ payload: GomokuStatePayload, requestedSince: Int = 0, blackPassedHint: Bool? = nil
    ) -> StateApplyOutcome {
        guard let row = payload.match, let id = row.id?.lowercased(), !id.isEmpty else { return .ignored }
        noteServerNow(payload.serverNowMs)
        applyRuby(payload.rubyBalance)
        let status = row.status ?? ""
        guard status == "active" || status == "finished" else {
            // 아직 시작 전(pending)이거나 시작하지 못하고 끝난 신청(declined·cancelled·expired)이다 — 판이 아니다.
            if match?.id == id { clearMatch() }
            if activeMatchID == id { activeMatchID = nil }
            return .applied
        }
        let isFinished = status == "finished"
        if isFinished, dismissedMatchIDs.contains(id), match?.id != id { return .ignored }

        let myID = host?.session?.userID.lowercased()
        var myColor = GomokuColor(rawValue: payload.myColor ?? "")
        if myColor == nil, let myID {
            if row.black?.lowercased() == myID { myColor = .black }
            else if row.white?.lowercased() == myID { myColor = .white }
        }
        guard let myColor else { return .ignored }

        let base = match?.id == id ? match : nil
        // 같은 판을 진행 중으로 들고 있는데 기록 수가 **줄어든** 응답은 착수보다 먼저 읽힌 옛 스냅숏이 늦게 온 것이다
        // (조회 → 착수 → 착수 응답 → 조회 응답 순서). 그대로 옮기면 방금 둔 돌이 사라지고 차례·마감이 한 수 전으로 돌아간다.
        // 판을 끝낸 응답은 예외다 — 끝남은 되돌릴 수 없는 사실이라 순서와 무관하게 받는다.
        if let base, !base.isFinished, !isFinished, let serverCount = row.moveCount, serverCount < base.moveCount {
            return .ignored
        }
        let tolerateGaps = requestedSince == 0
        let records: [(seq: Int, color: GomokuColor, point: GomokuPoint?)] = (payload.moves ?? [])
            .compactMap { move in
                guard let seq = move.seq, let color = GomokuColor(rawValue: move.color ?? "") else { return nil }
                if move.kind == "pass" || move.x == nil || move.y == nil { return (seq, color, nil) }
                guard let point = GomokuPoint(x: move.x ?? -1, y: move.y ?? -1) else { return nil }
                return (seq, color, point)
            }
            .sorted { $0.seq < $1.seq }

        var board: GomokuBoard
        var lastMove: GomokuPoint?
        var appliedCount: Int
        var lastRecordIsBlackPass: Bool?
        let rebuild = base == nil || records.first?.seq == 1
        if rebuild {
            board = GomokuBoard()
            lastMove = nil
            appliedCount = 0
        } else {
            board = base?.board ?? GomokuBoard()
            lastMove = base?.lastMove
            appliedCount = base?.moveCount ?? 0
        }
        for record in records where record.seq > appliedCount {
            if record.seq != appliedCount + 1, !tolerateGaps { return .needsFull }
            if let point = record.point {
                board[point] = record.color
                lastMove = point
                lastRecordIsBlackPass = false
            } else {
                lastRecordIsBlackPass = record.color == .black
            }
            appliedCount = record.seq
        }
        if let serverBoard = row.board.flatMap(GomokuBoard.init(serverString:)) {
            board = serverBoard
            if let serverCount = row.moveCount { appliedCount = serverCount }
        } else if let serverCount = row.moveCount, serverCount != appliedCount {
            if !tolerateGaps { return .needsFull }
            appliedCount = serverCount
        }

        let blackPassed: Bool
        if blackPassedHint == true {
            blackPassed = true
        } else if let lastRecordIsBlackPass {
            blackPassed = lastRecordIsBlackPass
        } else {
            blackPassed = base?.blackPassed ?? false
        }

        let turn = isFinished ? nil : GomokuColor(rawValue: row.turn ?? "")
        var deadline = isFinished ? nil : deviceDate(serverMs: row.deadlineMs)
        if let base, let kept = base.deadline, let fresh = deadline, base.moveCount == appliedCount, base.turn == turn,
           abs(fresh.timeIntervalSince(kept)) < Self.deadlineToleranceSeconds {
            // 같은 차례를 다시 읽었다 — 보정 오차만큼 다른 마감으로 갈면 창 루트가 조회마다 다시 그려진다.
            deadline = kept
        }
        let outcome: GomokuOutcome?
        switch row.result {
        case "draw": outcome = .draw
        case "black_win": outcome = myColor == .black ? .won : .lost
        case "white_win": outcome = myColor == .white ? .won : .lost
        default: outcome = nil
        }
        let stake = row.stake ?? base?.stake ?? 0
        let rubyDelta = outcome.map { result -> Int in
            switch result {
            case .won: return stake
            case .lost: return -stake
            case .draw: return 0
            }
        }
        let opponentID = (myColor == .black ? row.white : row.black)?.lowercased()
        let opponent = peerUser(payload.opponent, working: true, capable: true, inMatch: !isFinished)
            ?? base?.opponent
            ?? users.first { $0.id == opponentID }
            ?? GomokuUser(id: opponentID ?? "", displayName: "", avatarURL: nil, characterID: nil,
                          isWorking: true, isCapable: true, inMatch: !isFinished)

        let next = GomokuMatchState(
            id: id, stake: stake, myColor: myColor, opponent: opponent, board: board, lastMove: lastMove,
            moveCount: appliedCount, turn: turn, deadline: deadline, isFinished: isFinished, outcome: outcome,
            endReason: row.endReason.flatMap(GomokuEndReason.init(rawValue:)), rubyDelta: rubyDelta,
            blackPassed: blackPassed
        )
        let justFinished = isFinished && base?.isFinished == false
        let previous = match
        let windowWasVisible = isWindowVisible
        if match != next { match = next }
        let nextPhase: GomokuPhase = isFinished ? .result : .playing
        if phase != nextPhase { phase = nextPhase }
        activeMatchID = isFinished ? nil : id
        if !isFinished {
            // 내 신청이 수락됐거나 내가 수락한 판이다 — 대기 카드를 걷는다.
            if outgoing?.id == id { outgoing = nil }
            if incoming.contains(where: { $0.id == id }) { incoming.removeAll { $0.id == id } }
        } else {
            shownResultIDs.insert(id)
        }
        lastOpponent = opponent
        lastStake = stake
        if !isFinished {
            noteMatchProgress(previous: previous, next: next, windowWasVisible: windowWasVisible)
        }
        if justFinished {
            // 전적은 로비 응답에만 있다. 판이 끝난 순간 한 번 다시 읽어 결과 화면 뒤 로비가 옛 전적을 보이지 않게 한다.
            Task { [weak self] in await self?.refreshLobby() }
        }
        return .applied
    }

    // MARK: - 동작

    func challenge(userID: String) async {
        await challenge(userID: userID, peerHint: nil)
    }

    private func challenge(userID: String, peerHint: GomokuUser?) async {
        guard !isBusy, host?.session != nil else { return }
        let target = userID.lowercased()
        let stake = selectedStake.rawValue
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({
            try await $0.gomokuChallenge(accessToken: $1, opponentID: target, stake: stake)
        }) else { return }
        switch result {
        case .failure:
            setNotice(GomokuNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(GomokuNoticeText.challenge(response.status, need: response.need, have: response.have))
            if response.status != .ok {
                Self.logger.notice("challenge refused status=\(response.status.rawValue, privacy: .public)")
            }
            switch response.status {
            case .ok:
                guard let id = response.matchId?.lowercased() else { break }
                let peer = users.first { $0.id == target }
                    ?? peerHint
                    ?? GomokuUser(id: target, displayName: "", avatarURL: nil, characterID: nil,
                                  isWorking: true, isCapable: true, inMatch: false)
                let expiresAt = deviceDate(serverMs: response.inviteExpiresMs)
                    ?? clock().addingTimeInterval(inviteTTLSeconds)
                outgoingRevision &+= 1
                outgoing = GomokuInvite(id: id, peer: peer, stake: stake, expiresAt: expiresAt)
                scheduleInviteExpiry()
            case .alreadyPending, .busy:
                await loadInbox()
            case .targetNotWorking, .targetBusy, .targetOutdated:
                // 목록의 칩이 틀렸다는 뜻이다 — 다시 읽어 행을 사실에 맞춘다.
                await refreshLobby()
            default:
                break
            }
        }
    }

    func cancelChallenge() async {
        guard !isBusy, let invite = outgoing, host?.session != nil else { return }
        let id = invite.id
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({ try await $0.gomokuCancel(accessToken: $1, matchID: id) }) else { return }
        switch result {
        case .failure:
            setNotice(GomokuNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(GomokuNoticeText.cancel(response.status))
            switch response.status {
            case .ok, .notFound, .notPending, .expired:
                if outgoing?.id == id {
                    outgoing = nil
                    scheduleInviteExpiry()
                }
                // not_pending 은 취소보다 수락이 먼저 닿았다는 뜻일 수 있다 — 진행 중 판을 찾아 온다.
                if response.status == .notPending { await loadInbox() }
            default:
                break
            }
        }
    }

    func respond(inviteID: String, accept: Bool) async {
        guard !isBusy, host?.session != nil else { return }
        let id = inviteID.lowercased()
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({
            try await $0.gomokuRespond(accessToken: $1, matchID: id, accept: accept)
        }) else { return }
        switch result {
        case .failure:
            setNotice(GomokuNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(GomokuNoticeText.respond(
                accept: accept, response.status, side: response.side, need: response.need, have: response.have))
            if response.status != .ok {
                Self.logger.notice("respond refused status=\(response.status.rawValue, privacy: .public)")
            }
            switch response.status {
            case .ok:
                removeIncoming(id)
                guard accept else { break }
                // 수락하는 순간 서버가 두 참가자의 **다른 대기 신청을 전부 취소한다**(보낸 것·받은 것). 로컬 카드를 그대로 두면
                // 다음 받은함에서 '상대가 신청을 받지 않았어요'가 뜨고, 남은 보낸 신청 카드는 60초 뒤 '응답하지 않았어요'를 띄운다.
                if outgoing != nil { outgoing = nil }
                if !incoming.isEmpty { incoming = [] }
                if let state = response.state {
                    applyState(state)
                } else {
                    await refreshMatch(id: id)
                }
                // 판이 열리면 applyState 가 창을 띄운다(판 시작은 경로와 무관하게 한 곳에서 알린다).
                // 판을 못 받아 온 경우에만 여기서 창을 띄워 받은 신청이 어떻게 됐는지 보게 한다.
                if match?.id != id, !isWindowVisible { presentWindow?() }
            case .notFound, .notPending, .expired:
                removeIncoming(id)
            default:
                break
            }
        }
    }

    func place(_ point: GomokuPoint) async {
        guard !isBusy, let current = match, !current.isFinished else { return }
        guard current.turn == current.myColor else {
            setNotice(GomokuNoticeText.notYourTurn)
            return
        }
        guard current.board[point] == nil else { return }
        // 흑 금수는 서버에 보내기 전에 막는다(헛왕복 절감). 판정은 서버 gomoku_judge 와 같은 규범·같은 예산이다.
        if current.myColor == .black,
           case .forbidden(let reason) = GomokuRules.judge(board: current.board, point: point, color: .black) {
            setNotice(GomokuNoticeText.forbidden(reason))
            return
        }
        guard host?.session != nil else { return }
        let id = current.id
        let expected = current.moveCount
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({
            try await $0.gomokuMove(accessToken: $1, matchID: id, expectedSeq: expected, x: point.x, y: point.y)
        }) else { return }
        switch result {
        case .failure:
            setNotice(GomokuNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(GomokuNoticeText.move(response.status, reason: response.reason))
            if response.status != .ok {
                Self.logger.notice("move refused status=\(response.status.rawValue, privacy: .public)")
            }
            if response.status == .notFound {
                if match?.id == id { clearMatch() }
                return
            }
            // 판이 바뀌었거나(stale) 내 판단이 서버와 갈린 경우는 **언제나** 다시 읽는다.
            var needsRefresh: Bool
            switch response.status {
            case .stale, .notYourTurn, .notActive, .invalid: needsRefresh = true
            default: needsRefresh = false
            }
            if let state = response.state {
                if applyState(state, requestedSince: expected, blackPassedHint: response.blackPassed) == .needsFull {
                    needsRefresh = true
                }
            } else if response.status == .ok || response.status == .timeout {
                needsRefresh = true
            }
            if needsRefresh { await refreshMatch(id: id) }
        }
    }

    func resign() async {
        guard !isBusy, let current = match, !current.isFinished, host?.session != nil else { return }
        let id = current.id
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({ try await $0.gomokuResign(accessToken: $1, matchID: id) }) else { return }
        switch result {
        case .failure:
            setNotice(GomokuNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(GomokuNoticeText.resign(response.status))
            if let state = response.state { applyState(state) }
            if response.status != .ok || response.state == nil { await refreshMatch(id: id) }
        }
    }

    /// 결과 화면에서 로비로. **진행 중인 판에서는 아무것도 하지 않는다**(빠져나가는 길은 기권뿐이다).
    func backToLobby() {
        if let current = match {
            guard current.isFinished else { return }
            dismissedMatchIDs.insert(current.id)
            lastOpponent = current.opponent
            lastStake = current.stake
            match = nil
        }
        if phase != .lobby { phase = .lobby }
        setNotice(nil)
        guard host?.session != nil else { return }
        Task { [weak self] in
            await self?.refreshLobby()
            await self?.loadInbox()
        }
    }

    /// 같은 상대·같은 판돈으로 다시 신청.
    func rematch() async {
        if let current = match, !current.isFinished { return }
        guard let opponent = match?.opponent ?? lastOpponent else { return }
        if let stake = GomokuStake(rawValue: match?.stake ?? lastStake ?? selectedStake.rawValue),
           selectedStake != stake {
            selectedStake = stake
        }
        if let current = match {
            dismissedMatchIDs.insert(current.id)
            match = nil
        }
        if phase != .lobby { phase = .lobby }
        await challenge(userID: opponent.id, peerHint: opponent)
    }

    // MARK: - 신호 · 계기

    /// 실시간 'gomoku' 신호. 직렬화된 재조회 — 도는 중이면 뒤따르는 한 번으로 합친다.
    func handleSignal() {
        requestSync()
    }

    func requestSync() {
        guard host?.session != nil else { return }
        guard syncTask == nil else {
            syncPendingTrailing = true
            return
        }
        let generation = resetGeneration
        syncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                // 루프 **안에서 먼저** 내린다. 뒤에 내리면 이번 조회가 도는 동안 도착한 신호를 지운다(requestDrain 과 같은 규약).
                self.syncPendingTrailing = false
                await self.syncOnce()
            } while self.syncPendingTrailing && generation == self.resetGeneration
            if generation == self.resetGeneration { self.syncTask = nil }
        }
    }

    /// 신호 한 번의 조회: 진행 중 판이 있으면 그 판(since_seq), 아니면 인박스.
    func syncOnce() async {
        if let current = match, !current.isFinished {
            await refreshMatch(id: current.id)
        } else {
            await loadInbox()
        }
    }

    /// 조인 직후·깨어남의 따라잡기: 인박스 한 번 + 진행 중 판이면 그 판의 놓친 수.
    func catchUp() async {
        await loadInbox()
        if let current = match, !current.isFinished {
            await refreshMatch(id: current.id)
        }
    }

    /// 실시간 조인 성공 직후(WorkTimerStoreRealtime 의 `.catchUp`).
    func realtimeDidJoin() {
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.catchUp() }
    }

    /// 깨어남(결합 게이트가 열린 뒤).
    func systemDidWake() {
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.catchUp() }
    }

    /// 근무 시작. 신청은 근무 중인 사람에게만 오므로 이 순간 한 번 본다.
    func workDidStart() {
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.loadInbox() }
    }

    /// 팝오버 열림. 60초 스로틀.
    func menuDidOpen() {
        guard host?.session != nil else { return }
        let now = clock()
        guard now.timeIntervalSince(lastMenuInboxAt) >= Self.menuInboxThrottleSeconds else { return }
        lastMenuInboxAt = now
        Task { [weak self] in await self?.loadInbox() }
    }

    // MARK: - 폴링 (창이 보일 때만)

    func startPolling() {
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

    func stopPolling() {
        pollToken &+= 1
        pollTask?.cancel()
        pollTask = nil
    }

    /// 안전망 한 걸음. **창이 안 보이면 아무것도 하지 않는다.**
    ///  · 진행 중 판이 상대 차례면(또는 표시 마감 + 유예가 지났으면) 구독 중 3초 / 미구독 1.5초마다 상태.
    ///  · 내 대기 신청이 있으면 5초마다 인박스(수락·거절·만료를 본다).
    ///  · 로비를 보고 있으면 30초마다 목록.
    func pollTick(at now: Date) async {
        guard isWindowVisible, !isWindowOccluded, host?.session != nil else { return }
        if let current = match, !current.isFinished {
            let waiting = current.turn != current.myColor
            let overdue = current.deadline.map { now.timeIntervalSince($0) > Self.turnGraceSeconds } ?? false
            if waiting || overdue {
                let subscribed = host?.realtimeState.isSubscribed ?? false
                let interval = subscribed ? Self.statePollSecondsWhileSubscribed : Self.statePollSecondsUnsubscribed
                if now.timeIntervalSince(lastStateRequestAt) >= interval {
                    await refreshMatch(id: current.id)
                }
            }
        }
        guard isWindowVisible else { return }
        if outgoing != nil, now.timeIntervalSince(lastInboxRequestAt) >= Self.outgoingInboxPollSeconds {
            await loadInbox()
        }
        guard isWindowVisible else { return }
        if phase == .lobby, now.timeIntervalSince(lastLobbyRequestAt) >= Self.lobbyPollSeconds {
            await refreshLobby()
        }
    }

    // MARK: - 초 단위 값 (잎 뷰 전용)

    /// 대국 창의 남은 시간(초, 0 이상). 잎 뷰 TimelineView 가 now 를 넘겨 부른다.
    func remainingSeconds(now: Date) -> Double? {
        guard let current = match, !current.isFinished, let deadline = current.deadline else { return nil }
        return max(0, deadline.timeIntervalSince(now))
    }

    // MARK: - 리셋

    /// 로그아웃·계정 전환. 창을 닫고 오목 상태를 전부 비운다 — 남기면 다음 사람이 앞 사람의 판·신청·루비를 본다.
    func reset() {
        resetGeneration &+= 1
        stopPolling()
        syncTask?.cancel()
        syncTask = nil
        syncPendingTrailing = false
        expiryTask?.cancel()
        expiryTask = nil
        stateInFlight = false
        stateAgain = false
        inboxInFlight = false
        inboxAgain = false
        lobbyInFlight = false
        if phase != .lobby { phase = .lobby }
        if !users.isEmpty { users = [] }
        if record != nil { record = nil }
        if selectedStake != .three { selectedStake = .three }
        if !incoming.isEmpty { incoming = [] }
        if outgoing != nil { outgoing = nil }
        if match != nil { match = nil }
        if notice != nil { notice = nil }
        if isBusy { isBusy = false }
        if isWindowVisible { isWindowVisible = false }
        if isRulesVisible { isRulesVisible = false }
        if rubyBalance != nil { rubyBalance = nil }
        if turnSeconds != 30 { turnSeconds = 30 }
        if lobbyLoadFailed { lobbyLoadFailed = false }
        if hasLoadedLobby { hasLoadedLobby = false }
        serverClockOffset = 0
        hasServerClockOffset = false
        isWindowOccluded = false
        stateInFlightID = nil
        pendingStateID = nil
        attentionKey = nil
        shownResultIDs = []
        outgoingRevision = 0
        inboxRequestOutgoingRevision = 0
        activeMatchID = nil
        seenInviteIDs = []
        dismissedMatchIDs = []
        lastStateRequestAt = .distantPast
        lastInboxRequestAt = .distantPast
        lastLobbyRequestAt = .distantPast
        lastMenuInboxAt = .distantPast
        inviteTTLSeconds = 60
        lastOpponent = nil
        lastStake = nil
        dismissWindow?()
    }

    // MARK: - 내부

    /// 공용 호출 관용구: 세션 가드 → 두 세대 캡처 → withSessionRetry → 두 세대 대조.
    /// nil = 버린 결과(세션 없음·세대가 밀림·취소). 호출부는 nil 이면 **아무것도 바꾸지 않는다.**
    private func perform<T: Sendable>(
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

    private func setNotice(_ text: String?) {
        if notice != text { notice = text }
    }

    private func applyRuby(_ value: Int?) {
        guard let value else { return }
        if rubyBalance != value { rubyBalance = value }
        if let host, host.rubyBalance != value { host.rubyBalance = value }
    }

    private func clearMatch() {
        if match != nil { match = nil }
        if phase != .lobby { phase = .lobby }
    }

    private func removeIncoming(_ id: String) {
        if incoming.contains(where: { $0.id == id }) { incoming.removeAll { $0.id == id } }
    }

    /// 판 진행을 사람에게 알린다(applyState 가 진행 중 판을 옮긴 직후).
    ///  · 판이 없거나 끝난 판에서 **진행 중 판으로 처음 넘어가면** 창을 띄우고 주의를 끈다 — 신청자는 상대가 수락한
    ///    순간을 모르면 흑 30초를 흘려 판돈을 잃는다. 내가 수락해 연 판도 같은 문을 지난다(경로마다 따로 두지 않는다).
    ///  · 창이 안 보이는 동안 차례가 나에게 오면 말풍선 문(onAttention)을 연다. 같은 (판 id, 기록 수)에는 한 번뿐이다.
    private func noteMatchProgress(previous: GomokuMatchState?, next: GomokuMatchState, windowWasVisible: Bool) {
        let started = previous == nil || previous?.isFinished == true || previous?.id != next.id
        if started {
            presentWindow?()
            requestAttention?()
        }
        guard next.turn == next.myColor else { return }
        let arrived = started || previous?.turn != next.myColor || previous?.moveCount != next.moveCount
        let key = "\(next.id)#\(next.moveCount)"
        guard arrived, attentionKey != key else { return }
        attentionKey = key
        guard !windowWasVisible else { return }
        onAttention?(GomokuAttention(
            kind: started ? .matchStarted : .myTurn, matchID: next.id,
            opponentName: next.opponent.displayName, moveCount: next.moveCount))
    }

    /// server_now_ms 로 기기 시계 어긋남을 잰다. 처음 잰 값은 그대로 받고, 그 뒤로는 문턱(250ms) 넘게 벗어날 때만 간다 —
    /// 왕복 지연 몇 ms 마다 오프셋을 갈면 같은 신청·같은 마감이 응답마다 다른 값이 된다.
    func noteServerNow(_ milliseconds: Double?) {
        guard let milliseconds, milliseconds > 0 else { return }
        let measured = milliseconds / 1000 - clock().timeIntervalSince1970
        guard !hasServerClockOffset || abs(measured - serverClockOffset) >= Self.serverClockToleranceSeconds else { return }
        serverClockOffset = measured
        hasServerClockOffset = true
    }

    /// 서버 epoch 밀리초 → 기기 시계의 같은 순간.
    func deviceDate(serverMs milliseconds: Double?) -> Date? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000 - serverClockOffset)
    }

    private func invite(from row: GomokuInviteRow, peerRow: GomokuUserRow?, fallbackPeer: GomokuUser?) -> GomokuInvite? {
        guard let id = row.matchId?.lowercased(), !id.isEmpty, let stake = row.stake,
              let expiresAt = deviceDate(serverMs: row.inviteExpiresMs),
              let peer = peerUser(peerRow, working: true, capable: true, inMatch: false) ?? fallbackPeer
        else { return nil }
        return GomokuInvite(id: id, peer: peer, stake: stake, expiresAt: expiresAt)
    }

    /// 사람 행 → GomokuUser. 행에 없는 칸(근무·가능·대국 중)은 로비 목록에서 빌리고, 거기에도 없으면 문맥 기본값이다.
    private func peerUser(_ row: GomokuUserRow?, working: Bool, capable: Bool, inMatch: Bool) -> GomokuUser? {
        guard let row, let id = row.userId?.lowercased(), !id.isEmpty else { return nil }
        let known = users.first { $0.id == id }
        return GomokuUser(
            id: id,
            displayName: row.displayName ?? known?.displayName ?? "",
            avatarURL: row.avatarUrl ?? known?.avatarURL,
            characterID: row.character ?? known?.characterID,
            isWorking: row.isWorking ?? known?.isWorking ?? working,
            isCapable: row.capable ?? known?.isCapable ?? capable,
            inMatch: row.inMatch ?? inMatch
        )
    }

    private func announceNewInvites() {
        for invite in incoming.sorted(by: { $0.expiresAt < $1.expiresAt }) where !seenInviteIDs.contains(invite.id) {
            seenInviteIDs.insert(invite.id)
            onInviteArrived?(invite)
        }
    }

    /// 가장 이른 만료 시각에 한 번 깨어나 만료된 신청을 걷는다(배너가 시계를 읽지 않게 하는 장치).
    func scheduleInviteExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        let dates = incoming.map(\.expiresAt) + (outgoing.map { [$0.expiresAt] } ?? [])
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

    func pruneExpiredInvites(now: Date) {
        let alive = incoming.filter { $0.expiresAt > now }
        if alive != incoming { incoming = alive }
        if let sent = outgoing, sent.expiresAt <= now {
            outgoing = nil
            setNotice(GomokuNoticeText.inviteTimedOut)
        }
        scheduleInviteExpiry()
    }

    /// 서버 사람 행 → GomokuUser(로비). `capable` 이 nil 이면 **불가**다.
    nonisolated static func user(from row: GomokuUserRow) -> GomokuUser? {
        guard let id = row.userId?.lowercased(), !id.isEmpty else { return nil }
        return GomokuUser(
            id: id,
            displayName: row.displayName ?? "",
            avatarURL: row.avatarUrl,
            characterID: row.character,
            isWorking: row.isWorking ?? false,
            isCapable: row.capable ?? false,
            inMatch: row.inMatch ?? false
        )
    }

    /// 로비 정렬: 도전할 수 있는 사람(근무 중·가능·대국 아님) → 근무 중·가능(대국 중) → 근무 중 → 나머지, 그 안은 이름순.
    nonisolated static func sortedForLobby(_ users: [GomokuUser]) -> [GomokuUser] {
        func rank(_ user: GomokuUser) -> Int {
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
