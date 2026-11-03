import Foundation
import Observation

// 아잉 마작(내부 이름 mahjong) 4인 판 스토어 — 화면 상태 · 서버 동기화 · 안전망 폴링 · RPC 호출 · 연습판.
// 계약 정본은 설계서 mj/SPEC.md §4.5(이 파일들의 표면) · §4.7(장부) · §3.4~3.6(와이어 — MahjongWire.swift).
//
// ── 규약(큐브 머리말 ①~⑯ 을 MCL:73-90 판정대로) ──
//  ① 서버 권위 — 낙관적 그림 없음(버린 패는 응답 뒤 강으로). 연습판은 엔진이 권위다.
//  ② 서버 시계 보정(`serverClockOffset`) — 마감·깨우기는 서버 ms 를 기기 시계로 옮겨 잰다.
//  ③ 창이 탁자를 보일 때만 폴링(로비 30초 · 방 10초 · 판 구독 중 5초 / 미구독 1.5초 · 순위 60초).
//  ④ 늦은 응답 버리기(아래 가드 (a)~(i)) · ⑤ 문구는 `MahjongNoticeText` 한 곳 · ⑥ 초인종 합치기(도는 중 온 신호는 끝난 뒤 정확히 한 번 더)
//  ⑦ 초 단위 값은 잎 뷰만 · ⑧ 2단 입력(리치 무장·치 조합·깡 후보)은 스토어 · ⑬ 반응 · ⑯ 정산을 처음 본 순간 로비 다시 읽기.
//  ⑮(engaged 장부)는 `GameDeviceLedger`(§4.7 — 버그 개선 가지 원문 바이트)로 바꿨다. 창·주의·말풍선·깨우기·방 확인·
//  보조 자동 보내기·`defersMegaphoneBanner`·자리 비움 점/배너는 모두 **이 기기가 연 판**(`ownsMatch`)에서만.
//
// ── 리버시 적대 검증이 고친 결함을 처음부터 피한다(CC-04) ──
//  ⓐ 가림: '창이 말할 수 있다' = `isWindowShowingTable`(보이고 안 가려짐) 하나. 알림·폴링·연습판 멈춤이 모두 이것만 읽는다.
//  ⓑ 폴링 걸음의 조회는 폴링 작업의 취소 밖에서 · ⓒ 걸음 사이 가드 `isWindowShowingTable, !Task.isCancelled`
//  ⓓ `writeRevision` — 쓰기 응답보다 먼저 나간 로비·state 는 잔액·`active_match_id` 를 덮지 않는다(판이 됐다는 판정에는 쓴다)
//  ⓔ 같은 id 를 active·finished 로 든 동안 온 forming·cancelled·expired 응답은 버린다.
//
// ── 칸 나눔(CC-02 — D40) ──
//  `match` 는 **서버 방(forming)·판 전용**, 연습판은 `practice` 칸에만 산다. 화면은 `table` 한 길로 그린다
//  (= showsPractice ? practice?.payload : match). `applyState` 는 `match` 만 만진다(가드 (g)).
//
// ── 갈래 C1(표면 뼈대) ──
//  이 파일들의 이름·서명은 E·B·U·T 갈래가 서는 계약이다. 네트워크 동작의 몸통(폴링·깨우기·요청 마감·쓰기 RPC·알림)은
//  C2, 연습판 몸통은 C3 가 채운다 — 그 자리는 `// C2:` · `// C3:` 로 표시했다.

/// 호스트(네트워크·세션·루비 미러) — 오목 계약을 그대로 빌린다(`CheckCoreShared.swift` 는 안 고친다).
package typealias MahjongStoreHost = GomokuStoreHost

/// 화면 단계. 연습 탁자를 보이는 동안은 `.playing`(연습판이 끝났으면 `.finished`).
package nonisolated enum MahjongPhase: Equatable, Sendable { case lobby, room, playing, finished }

package enum MahjongAvailability: Equatable, Sendable { case available, updateRequired, serverMissing }

package nonisolated enum MahjongStake: Int, CaseIterable, Sendable {
    case three = 3, five = 5, ten = 10
}

/// 보조(aids — UX:426-441). **기기 로컬 설정**(UserDefaults `mahjong.aids` — 시험은 격리 defaults).
/// 루비 판에서도 같다(내 손 + 공개 정보만 쓴다). 자동으로 보내는 것은 **이 기기가 연 판에서만**.
package struct MahjongAids: Equatable, Sendable, Codable {
    /// 쯔모/론 선택지가 오면 바로 보낸다.
    package var autoWin = false
    /// 론 아닌 울기 프롬프트는 바로 패스(국마다 꺼짐).
    package var noCalls = false
    /// 쯔모·론·암깡·가깡·리치 선택지가 없으면 뽑은 패를 버린다(결정 시작 + 0.5~1.0초 뒤 — CC-19).
    package var tsumogiri = false
    /// 두 번 눌러 버리기.
    package var twoClickDiscard = false
    /// 패 귀퉁이 글자.
    package var cornerLabels = true

    package init(
        autoWin: Bool = false, noCalls: Bool = false, tsumogiri: Bool = false, twoClickDiscard: Bool = false,
        cornerLabels: Bool = true
    ) {
        self.autoWin = autoWin
        self.noCalls = noCalls
        self.tsumogiri = tsumogiri
        self.twoClickDiscard = twoClickDiscard
        self.cornerLabels = cornerLabels
    }

    private enum CodingKeys: String, CodingKey { case autoWin, noCalls, tsumogiri, twoClickDiscard, cornerLabels }

    /// 저장된 값에 없는 칸(앞 판에 없던 보조)은 기본값으로 읽는다 — 칸 하나를 더해도 저장값이 통째로 버려지지 않게.
    package init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MahjongAids()
        autoWin = try c.decodeIfPresent(Bool.self, forKey: .autoWin) ?? defaults.autoWin
        noCalls = try c.decodeIfPresent(Bool.self, forKey: .noCalls) ?? defaults.noCalls
        tsumogiri = try c.decodeIfPresent(Bool.self, forKey: .tsumogiri) ?? defaults.tsumogiri
        twoClickDiscard = try c.decodeIfPresent(Bool.self, forKey: .twoClickDiscard) ?? defaults.twoClickDiscard
        cornerLabels = try c.decodeIfPresent(Bool.self, forKey: .cornerLabels) ?? defaults.cornerLabels
    }
}

/// 창 밖 알림 한 건(v1.0 네 갈래 — 덮개 말풍선 하나로 나간다, CC-01·CC-10·CC-22). 모두 `ownsMatch` 판에서만.
/// `key` 가 같으면 다시 띄우지 않는다(판 시작 `판` · 내 차례 `판#국` · 자리 비움 `판#away_since` · 닫기 안내 `판#closed`).
package struct MahjongAttention: Equatable, Sendable {
    package enum Kind: Equatable, Sendable { case matchStarted, myTurn, away, closedWhilePlaying }

    package let kind: Kind
    package let matchID: String
    package let handIndex: Int
    package let key: String
    package let opponentName: String?

    package init(kind: Kind, matchID: String, handIndex: Int, key: String, opponentName: String? = nil) {
        self.kind = kind
        self.matchID = matchID
        self.handIndex = handIndex
        self.key = key
        self.opponentName = opponentName
    }
}

/// 결정 정체성(CC-03 — D42). 이것이 바뀌거나 결정이 없어지는 순간 2단 입력을 모두 접고 비행 잠금을 푼다.
package struct MahjongDecisionKey: Hashable, Sendable {
    package let matchID: String
    package let handIndex: Int
    /// "turn" | "call".
    package let kind: String
    /// turn = decision_seq, call = window_id.
    package let anchor: Int
    package let startedMs: Double

    package init(matchID: String, handIndex: Int, kind: String, anchor: Int, startedMs: Double) {
        self.matchID = matchID
        self.handIndex = handIndex
        self.kind = kind
        self.anchor = anchor
        self.startedMs = startedMs
    }

    /// 판 묶음의 지금 내 결정 키(결정이 없거나 판 id 가 없으면 nil).
    package static func of(_ payload: MahjongStatePayload?) -> MahjongDecisionKey? {
        guard let payload, let match = payload.match, let decision = payload.myDecision else { return nil }
        let hand = match.handIndex ?? 0
        switch decision {
        case .turn(let turn):
            return MahjongDecisionKey(
                matchID: match.id, handIndex: hand, kind: decision.kind, anchor: turn.decisionSeq,
                startedMs: turn.startedMs)
        case .call(let call):
            return MahjongDecisionKey(
                matchID: match.id, handIndex: hand, kind: decision.kind, anchor: call.windowId, startedMs: call.startedMs)
        }
    }
}

/// 연습판(혼자 + 봇 셋 — CC-02 · D40). `match` 와 따로 산다. 엔진·봇 세대·연습 시계·멈춤 여부를 쥔다.
/// C1 은 표면만 — 엔진(`MahjongTableEngine`, 갈래 E) 칸과 봇 세대 진행은 C3 가 더한다.
package struct MahjongPracticeSession: Sendable {
    /// `"ai-"` 로 시작하는 id(`MahjongStatePayload.practiceIDPrefix`).
    package let matchID: String
    package let format: MahjongFormat
    /// '실전처럼 5+20'(꺼짐 = 넉넉히).
    package let timed: Bool
    /// 사람 자리(0~3).
    package let humanSeat: Int
    /// 세대 — 다시 시작·리셋마다 올라 늦은 봇 결정을 버린다.
    package var generation: Int
    /// 엔진 `payload(for: 사람 자리)` — 화면은 `MahjongStore.table` 로 이것을 그린다.
    package var payload: MahjongStatePayload
    /// 창이 탁자를 안 보이거나 방 넷째가 앉아 멈춘 동안 참(봇도 안 둔다).
    package var isPaused: Bool

    // MARK: 연습판 몸통(C3) — 모듈 안에만(엔진은 숨은 정보를 쥔다 — 화면은 `payload` 만 본다)

    /// 판 권위(갈래 E). 패산·남의 손은 이 안에만 있다.
    var engine: MahjongTableEngine?
    /// 지금 사람 결정의 정체성("국#turn#결정번호" | "국#call#창번호") — 바뀌면 시계·안내·2단 입력을 새로 잡는다.
    var humanAnchor: String?
    /// 사람 결정 시계 시작(실전처럼) — 멈췄다 이어 가면 멈춘 만큼 뒤로 민다.
    var humanStartedAt: Date?
    /// 사람 예비(ms) — 국마다 20초, 국 안 회복 없음(MJ-53).
    var bankMs = MahjongClock.bankFullMs
    var bankHandIndex = -1
    /// '넉넉히' 론 아닌 울기 프롬프트가 선 때 · 안내를 띄웠나.
    var callPromptAt: Date?
    var hintShown = false
    /// 지금 울기 창 번호 · 봇 답을 받기 시작하는 때(창 멈춤 0.5~1.0초).
    var windowID: Int?
    var claimReadyAt: Date?
    /// 보조 쯔모기리를 보낼 때.
    var aidDueAt: Date?
    /// 멈춘 때.
    var pausedAt: Date?
    /// 방장 + 서버 방 넷째 착석으로 멈췄다.
    var roomHold = false

    package init(
        matchID: String, format: MahjongFormat, timed: Bool, humanSeat: Int, generation: Int,
        payload: MahjongStatePayload, isPaused: Bool = false
    ) {
        self.matchID = matchID
        self.format = format
        self.timed = timed
        self.humanSeat = humanSeat
        self.generation = generation
        self.payload = payload
        self.isPaused = isPaused
    }
}

/// 연습 중 위 띠 "방 3/4 · 남은 7:12 · [방 보기]"(CC-02).
package struct MahjongRoomBand: Equatable, Sendable {
    package let roomID: String
    package let joined: Int
    package let expiresAt: Date
    /// 넷이 모였다(방장이면 [시작]).
    package let readyToStart: Bool

    package init(roomID: String, joined: Int, expiresAt: Date, readyToStart: Bool) {
        self.roomID = roomID
        self.joined = joined
        self.expiresAt = expiresAt
        self.readyToStart = readyToStart
    }
}

// MARK: - 스토어

/// 칸은 전부 `package internal(set)` — 맥 모듈은 못 쓰고 `@testable` 시험은 쓴다(리버시 CCT B1).
@MainActor
@Observable
package final class MahjongStore {
    /// 네트워크·세션·루비 미러를 빌리는 곳. **약참조다** — 소유자(`WorkTimerStore`)가 이 스토어를 가진다.
    /// nil 이면 미리보기·렌더 시험용이라 네트워크를 한 건도 내지 않는다.
    @ObservationIgnored package private(set) weak var host: (any MahjongStoreHost)?
    /// 기기 시계(시험이 갈아 끼운다).
    @ObservationIgnored package var clock: () -> Date

    package init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
    }

    /// 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다.
    package func attach(host: any MahjongStoreHost) {
        self.host = host
    }

    // MARK: 화면 상태

    package internal(set) var phase: MahjongPhase = .lobby
    package internal(set) var availability: MahjongAvailability = .available
    /// **서버 방(forming)·판 전용** — 연습판은 여기 안 든다(CC-02).
    package internal(set) var match: MahjongStatePayload? {
        didSet { matchDidChange(from: oldValue) }
    }
    /// 연습판 — `match` 와 따로. 엔진 payload 는 이 안에.
    package internal(set) var practice: MahjongPracticeSession?
    /// 화면이 연습 탁자를 고른 상태.
    package internal(set) var showsPractice = false
    package internal(set) var users: [MahjongLobbyUser] = []
    package internal(set) var invites: [MahjongRoom] = []
    package internal(set) var publicRooms: [MahjongRoom] = []
    package internal(set) var record: MahjongRecord?
    package internal(set) var rubyBalance: Int?
    package internal(set) var ranking: MahjongRankingResponse?
    package internal(set) var rankingUnavailable = false
    package internal(set) var notice: String?
    /// 방·차례 동작 비행 중(단추 잠금). 더 새 결정 키의 state 가 오면 즉시 풀린다(CC-06).
    package internal(set) var isWorking = false
    /// 울기 답 비행 중 — `isWorking` 과 따로(패스가 막히지 않게, MCL:126). 같은 규칙으로 풀린다.
    package internal(set) var isAnsweringCall = false
    package internal(set) var riichiArmed = false
    package internal(set) var chiChoicesOpen = false
    package internal(set) var kanChoicesOpen = false
    /// 버림·울기 움직임 순수 값.
    package internal(set) var motion: MahjongMotion?
    package internal(set) var isWindowVisible: Bool = false
    /// ⓐ 창이 보이지만 가려졌다(전체 화면 앱·다른 스페이스).
    package internal(set) var isWindowOccluded: Bool = false

    package var selectedStake: MahjongStake = .three
    package var selectedFormat: MahjongFormat = .tonpuu
    package var selectedPublic = false
    /// 연습판 '실전처럼 5+20'(기본 꺼짐 = 넉넉히).
    package var practiceTimed = false
    /// 보조 — 바뀌면 `aidsDefaults` 에 저장한다.
    package var aids = MahjongAids() {
        didSet { saveAids() }
    }
    /// 숨김·차단 거울(사람 uuid). 맥 배선이 `setHiddenPeers` 로 넣는다.
    package var hiddenPeerIDs: Set<UUID> = []
    package var rankingEnabled: Bool = false

    // MARK: 콜백 · 장부

    /// 이 기기가 연 판 장부(§4.7 — 버그 개선 가지 `GameDeviceLedger` 원문). 앱 배선이 `defaults` 를 넣는다.
    @ObservationIgnored package var deviceLedger = GameDeviceLedger(game: "mahjong", ttlSeconds: 6 * 3_600)
    @ObservationIgnored package var presentWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var dismissWindow: (@MainActor () -> Void)?
    /// 남의 계약과 모양만 맞춘다 — 메뉴바 앱이라 완화책으로 세지 않는다(CC-01 4).
    @ObservationIgnored package var requestAttention: (@MainActor () -> Void)?
    @ObservationIgnored package var onInviteArrived: (@MainActor (MahjongRoom) -> Void)?
    @ObservationIgnored package var onAttention: (@MainActor (MahjongAttention) -> Void)?
    /// 루비 판이 끝난 것을 처음 본 순간 한 번(연습판·무효 판 제외).
    @ObservationIgnored package var onMatchFinished: (@MainActor () -> Void)?
    /// App Nap 붙들기 신호(맥 `MahjongActivityHold` — 큐브 `onHoldingMatchChange` 꼴). 값이 바뀔 때만 부른다(T 배선).
    @ObservationIgnored package var onHoldingActivityChange: (@MainActor (Bool) -> Void)?
    @ObservationIgnored package private(set) var isHoldingActivity = false
    /// 보조 설정을 둘 곳(nil 이면 이 값 안에만 산다 — 시험이 실행기 `.standard` 에 키를 흘리지 않게). 넣는 순간 읽어 온다.
    @ObservationIgnored package var aidsDefaults: UserDefaults? {
        didSet { loadAids() }
    }

    // MARK: 동기화 장부(화면이 안 읽는 칸)

    /// 기기 시계 − 서버 시계(초). 서버 ms 를 기기 Date 로 옮길 때 뺀다(②).
    @ObservationIgnored package internal(set) var serverClockOffset: TimeInterval = 0
    /// ⓓ 쓰기 응답을 적용할 때마다 오른다. 이보다 먼저 나간 로비·state 는 잔액·active_match_id 를 덮지 않는다.
    @ObservationIgnored package internal(set) var writeRevision = 0
    /// 로비가 말한 내 forming 방(내가 앉은 방은 받은 초대 목록에서 뺀다).
    @ObservationIgnored package internal(set) var lobbyRoom: MahjongRoom?
    /// 로비가 말한 내 active 판 id.
    @ObservationIgnored package internal(set) var activeMatchID: String?
    /// (h) 답한 울기 창 — "판#창번호". 답한 창의 `answered == nil` 조회는 프롬프트를 되살리지 않는다(CC-26).
    @ObservationIgnored package internal(set) var answeredWindowIDs: Set<String> = []
    /// 답한 창 → 보낸 답 원문("ron"|"pon"|"minkan"|"chi"|"pass") — (h) 에서 되살릴 답.
    @ObservationIgnored package internal(set) var answeredWindowAnswers: [String: String] = [:]
    /// (a) 접은 판 id — 그 뒤에 온 그 판 응답은 버린다.
    @ObservationIgnored package internal(set) var dismissedMatchIDs: Set<String> = []
    /// 이미 띄운 알림 열쇠(`MahjongAttention.key`).
    @ObservationIgnored package internal(set) var deliveredAttentionKeys: Set<String> = []
    /// 이미 알린 초대 방 id(같은 초대로 말풍선을 두 번 띄우지 않는다).
    @ObservationIgnored package internal(set) var seenInviteIDs: Set<UUID> = []
    @ObservationIgnored package internal(set) var lastLobbyRequestAt: Date = .distantPast
    @ObservationIgnored package internal(set) var lastStateRequestAt: Date = .distantPast
    /// 리셋 세대 — 나가 있던 응답을 버리는 꼬리표.
    @ObservationIgnored package internal(set) var resetGeneration = 0
    /// 폴링 작업(창이 탁자를 보일 때만, ③). C2 가 채운다.
    @ObservationIgnored package internal(set) var pollTask: Task<Void, Never>?
    /// 깨우기 작업(창과 무관 — 장부 판에서만). C2 가 채운다.
    @ObservationIgnored package internal(set) var wakeTask: Task<Void, Never>?
    /// 연습판 장부(봇 결정 주입 · 세대 · 봇/걸음/시계 작업 — C3).
    @ObservationIgnored let practiceRuntime = MahjongPracticeRuntime()

    // MARK: 조회 직렬화 · 합치기 · 요청 표(C2)

    @ObservationIgnored var lobbyInFlight = false
    @ObservationIgnored var lobbyAgain = false
    @ObservationIgnored var stateInFlight = false
    @ObservationIgnored var stateAgain = false
    /// 지금 날고 있는 state 조회의 판 id.
    @ObservationIgnored package internal(set) var stateInFlightID: String?
    /// 도는 중에 온 **다른 판** 조회 — 지금 것이 끝난 뒤 한 번.
    @ObservationIgnored var pendingStateID: String?
    /// 초인종 합치기 작업(⑥) — 도는 중에 온 신호는 끝난 뒤 정확히 한 번 더.
    @ObservationIgnored package internal(set) var syncTask: Task<Void, Never>?
    @ObservationIgnored var syncPendingTrailing = false
    @ObservationIgnored var pollToken = 0
    /// 폴링 루프의 걸음 간격(초). 시험은 크게 두고 `pollTick(at:)` 을 직접 밟는다.
    @ObservationIgnored package var pollStepSeconds: TimeInterval = 0.5
    /// 깨우기·보조 자동 보내기를 실제 타이머로 돌린다(시험은 끄고 `checkWake(at:)` 를 직접 밟는다).
    @ObservationIgnored package var timersEnabled = true
    /// 요청 표(④ (c) 끝 · (d)) — state 를 돌려줄 수 있는 요청을 **보내기 직전에** 하나씩 오른다.
    @ObservationIgnored package internal(set) var requestTicket = 0
    /// 지금 `match` 를 만든 응답의 표.
    @ObservationIgnored package internal(set) var appliedTicket = 0
    @ObservationIgnored var lastMenuLobbyAt: Date = .distantPast
    @ObservationIgnored package internal(set) var lastRankingRequestAt: Date = .distantPast
    /// 내가 joined 인 forming 방을 마지막으로 읽은 때(방 확인 30초 — 창과 무관).
    @ObservationIgnored package internal(set) var lastRoomCheckAt: Date = .distantPast
    /// 깨우기: 마지막으로 쏜 열쇠 · 그 열쇠로 쏜 횟수 · 마지막으로 쏜 때(같은 열쇠 재시도 2회 상한).
    @ObservationIgnored package internal(set) var wakeFiredKey: String?
    @ObservationIgnored package internal(set) var wakeFiredCount = 0
    @ObservationIgnored package internal(set) var wakeFiredAt: Date = .distantPast
    /// 예약해 둔 깨우기 열쇠(같은 깨우기 시각이면 한 번만 예약).
    @ObservationIgnored var wakeScheduledKey: String?
    /// 동작 비행 꼬리표 — 늦게 끝난 옛 요청이 새 요청의 잠금을 풀지 않게.
    @ObservationIgnored var actionToken = 0
    @ObservationIgnored var callToken = 0
    /// 요청 마감 상하한(초 — §4.5 CC-06 `min(8, max(2, …))`). 시험이 줄인다.
    @ObservationIgnored package var requestDeadlineFloor: TimeInterval = 2
    @ObservationIgnored package var requestDeadlineCeiling: TimeInterval = 8
    /// 보조 쯔모기리 지연(결정 시작 + 이 값 초 — CC-19 0.5~1.0 무작위). 시험이 고정한다.
    @ObservationIgnored package var aidJitter: () -> TimeInterval = { Double.random(in: 0.5...1.0) }
    /// 보조가 이미 다룬 결정 키(결정마다 한 번).
    @ObservationIgnored package internal(set) var aidHandledKeys: Set<MahjongDecisionKey> = []
    @ObservationIgnored package internal(set) var aidTask: Task<Void, Never>?
    /// '울지 않음'을 켠 국("판#국") — 국이 바뀌면 꺼진다.
    @ObservationIgnored var noCallsHandKey: String?
    /// 시간 초과 문구를 이미 낸 결정(같은 결정에 두 번 말하지 않는다).
    @ObservationIgnored var timeoutNoticeKeys: Set<String> = []

    // MARK: 계산 속성

    /// ⓐ '창이 말할 수 있다' = 보이고 가려지지 않았다. 알림·폴링·연습판 멈춤이 **모두 이것만** 읽는다(CC-01 · D41).
    package var isWindowShowingTable: Bool { isWindowVisible && !isWindowOccluded }

    /// 그릴 판 — 그리는 길은 하나(연습판도 루비 판도).
    package var table: MahjongStatePayload? { showsPractice ? practice?.payload : match }

    /// 연습 중 위 띠 — 연습 탁자를 보이는 동안 서버 방이 forming 일 때만.
    package var roomBand: MahjongRoomBand? {
        guard showsPractice, let room = match?.match, room.matchStatus == .forming else { return nil }
        let joined = Self.joinedCount(match)
        return MahjongRoomBand(
            roomID: room.id, joined: joined, expiresAt: localDate(serverMs: room.roomExpiresMs) ?? clock(),
            readyToStart: joined >= 4)
    }

    /// 차단 거울만 거른 사람 목록.
    package var visibleUsers: [MahjongLobbyUser] { users.filter { !hiddenPeerIDs.contains($0.id) } }

    /// 차단 거울 + 내가 앉은 방을 뺀 받은 초대.
    package var visibleInvites: [MahjongRoom] {
        let seated = seatedRoomID
        return invites.filter { room in
            if let seated, room.id == seated { return false }
            if let host = room.host?.id.flatMap(UUID.init(uuidString:)), hiddenPeerIDs.contains(host) { return false }
            return true
        }
    }

    /// 받은 초대가 있다 — 메뉴바 점·배너·말풍선·사이드바 점이 모두 이것 하나(§4.6 짝). 장부와 무관(모든 기기).
    package var hasIncomingInvite: Bool { !visibleInvites.isEmpty }

    /// 내 자리가 비움이고 이 기기가 연 판이다 — 메뉴바 점·배너·말풍선 셋이 모두 이것 하나(CC-10).
    package var hasAwaySeatHere: Bool {
        guard let payload = match, let current = payload.match, current.matchStatus == .active else { return false }
        let away = payload.myAway != nil || payload.mySeatRow?.away == true
        return away && ownsMatch(current.id)
    }

    /// 단추는 이것만 그린다(루비 판은 서버, 연습판은 엔진).
    package var myDecision: MahjongDecision? { table?.myDecision }

    package var decisionKey: MahjongDecisionKey? { MahjongDecisionKey.of(table) }

    package var isPractice: Bool { showsPractice && practice != nil }

    /// 서버 방의 방장인가(연습 중에도 `match` 로 잰다).
    package var isHost: Bool {
        guard let me = host?.session?.userID.lowercased(), let room = match else { return false }
        if let hostID = room.match?.host?.id?.lowercased() { return hostID == me }
        return room.members?.contains { $0.isHost == true && $0.user?.id?.lowercased() == me } ?? false
    }

    /// 방장 && forming 방에 넷이 앉았다.
    package var canStart: Bool {
        guard isHost, match?.match?.matchStatus == .forming else { return false }
        return Self.joinedCount(match) == 4
    }

    /// 확성기 배너를 미룬다 — 판을 두는 중(연습판이거나 이 기기가 연 판).
    package var defersMegaphoneBanner: Bool {
        guard phase == .playing else { return false }
        if isPractice { return true }
        guard let id = match?.match?.id else { return false }
        return ownsMatch(id)
    }

    // MARK: 숨김 거울 · 보조 저장

    package func setHiddenPeers(_ ids: Set<UUID>) {
        if hiddenPeerIDs != ids { hiddenPeerIDs = ids }
    }

    /// 보조 저장 키.
    nonisolated static let aidsDefaultsKey = "mahjong.aids"

    private func saveAids() {
        guard let aidsDefaults, let data = try? JSONEncoder().encode(aids) else { return }
        aidsDefaults.set(data, forKey: Self.aidsDefaultsKey)
    }

    private func loadAids() {
        guard let aidsDefaults, let data = aidsDefaults.data(forKey: Self.aidsDefaultsKey),
              let stored = try? JSONDecoder().decode(MahjongAids.self, from: data), stored != aids else { return }
        aids = stored
    }

    // MARK: 장부 도우미(§4.7 — 체스 62ecdf73 과 같은 이름, CC-29)

    /// 이 기기가 이 판(방)을 열었는가. 설계서의 '장부 판'은 모두 이것이다.
    package func ownsMatch(_ matchID: String) -> Bool {
        deviceLedger.owns(matchID, userID: host?.session?.userID, now: clock())
    }

    /// 이 기기가 이 판을 열었다(방 만들기·참가·시작 ok · act·call·back·react 를 보낼 때). 이미 있으면 그대로 둔다.
    func noteOwnsMatch(_ matchID: String) {
        deviceLedger.note(matchID, userID: host?.session?.userID, now: clock())
        syncHoldingActivity()
    }

    /// 이 판의 기록을 지운다(finished·cancelled·expired·접은 판·내가 dropped 된 방).
    func dropOwnership(_ matchID: String) {
        deviceLedger.drop(matchID, userID: host?.session?.userID, now: clock())
        syncHoldingActivity()
    }

    /// App Nap 을 붙들어야 하는가 — **이 기기가 연** 방·판(forming·active)이 있는 동안(SPEC §4.6 #13). 연습판은 빼다:
    /// 창이 탁자를 안 보이면 연습판은 멈추므로 붙들 까닭이 없다. 방은 30초 방 확인 때문에 잡는다.
    package var holdsActivity: Bool {
        guard let header = match?.match, header.matchStatus == .forming || header.matchStatus == .active else { return false }
        return ownsMatch(header.id)
    }

    /// 붙들기 값이 바뀌었으면 한 번 알린다(같은 값 두 번은 조용히).
    func syncHoldingActivity() {
        let holding = holdsActivity
        guard holding != isHoldingActivity else { return }
        isHoldingActivity = holding
        onHoldingActivityChange?(holding)
    }

    // MARK: 창

    /// 창을 연다(메뉴·배너·사이드바). `focusMatchID` 가 있으면 그 판·방을 먼저 읽는다.
    package func openWindow(focusMatchID: String?) {
        presentWindow?()
        guard host?.session != nil else { return }
        let focus = focusMatchID?.lowercased()
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let focus, !focus.hasPrefix(MahjongStatePayload.practiceIDPrefix) {
                await self.refreshMatch(id: focus)
            } else if let current = self.match?.match, !current.matchStatus.isTerminal {
                await self.refreshMatch(id: current.id)
            }
            await self.refreshLobby()
        }
    }

    /// 창이 실제로 보이기 시작했다.
    package func windowDidShow() {
        // 열린 채 가려진 창을 다시 부르는 길(판 시작의 `presentWindow`)이면 가림 기록을 **그대로 둔다**(검증 V3-01 — 오목 · 체스 ·
        // 테트리스 · 뒤집기와 같은 수리, main 6d53d0d2 · 4ae9b489). 창이 정말 앞으로 오면 가림 통지(visible)가 와서 풀고, 못 오면
        // (다른 전체 화면 앱 위로 못 올라옴) 가린 채로 남아야 시작 · 내 차례 말풍선이 산다. 숨겼다 다시 여는 길은 `windowDidHide` 가
        // 이미 지웠으므로 낡은 가림 기록이 폴링을 막지 않는다.
        let reshownWhileOccluded = isWindowVisible && isWindowOccluded
        if !isWindowVisible { isWindowVisible = true }
        if !reshownWhileOccluded, isWindowOccluded { isWindowOccluded = false }
        tableVisibilityDidChange()
    }

    /// 창이 가려졌다·닫혔다·최소화됐다. 폴링·연습판만 멈춘다 — **루비 판은 계속된다**(시간은 서버에서 흐른다).
    package func windowDidHide() {
        if isWindowVisible { isWindowVisible = false }
        if isWindowOccluded { isWindowOccluded = false }
        tableVisibilityDidChange()
    }

    /// 창의 가림 상태가 바뀌었다. `isWindowVisible` 은 건드리지 않는다.
    package func windowOcclusionDidChange(visible: Bool) {
        if isWindowOccluded == visible { isWindowOccluded = !visible }
        tableVisibilityDidChange()
    }

    /// 창을 **정말 닫았다**(`CheckMahjongWindowController.onClosed`). 닫기는 기권이 아니다 — 판은 계속된다.
    /// 사람 닫기 + 이 기기가 연 판이 진행 중이면 닫기 안내 말풍선을 판마다 한 번(CC-22). 프로그램 닫기·연습판은 0.
    package func windowDidClose(byUser: Bool) {
        guard byUser, let current = match?.match, current.matchStatus == .active, ownsMatch(current.id) else { return }
        deliverAttention(MahjongAttention(
            kind: .closedWhilePlaying, matchID: current.id, handIndex: current.handIndex ?? 0,
            key: "\(current.id)#closed"))
    }

    /// '창이 탁자를 보인다'가 바뀐 뒤 — 폴링 켜고 끄기(C2) · 연습판 멈춤(C3).
    func tableVisibilityDidChange() {
        if isWindowShowingTable { startPolling() } else { stopPolling() }
        syncPracticePause()   // 연습판 멈춤/재개(봇 포함)
    }

    /// 알림 한 건을 내보낸다 — 같은 열쇠는 한 번만(장부 확인은 부르는 쪽 몫).
    func deliverAttention(_ attention: MahjongAttention) {
        guard deliveredAttentionKeys.insert(attention.key).inserted else { return }
        onAttention?(attention)
    }

    /// 로그아웃·계정 바뀜. 화면·장부 밖 기록을 모두 비우고 나가 있던 응답을 버린다(장부는 사용자별 키라 둔다).
    package func reset() {
        resetGeneration += 1
        pollTask?.cancel()
        pollTask = nil
        wakeTask?.cancel()
        wakeTask = nil
        syncTask?.cancel()
        syncTask = nil
        syncPendingTrailing = false
        aidTask?.cancel()
        aidTask = nil
        pollToken &+= 1
        lobbyInFlight = false
        lobbyAgain = false
        stateInFlight = false
        stateAgain = false
        stateInFlightID = nil
        pendingStateID = nil
        requestTicket = 0
        appliedTicket = 0
        lastMenuLobbyAt = .distantPast
        lastRankingRequestAt = .distantPast
        lastRoomCheckAt = .distantPast
        wakeFiredKey = nil
        wakeFiredCount = 0
        wakeFiredAt = .distantPast
        wakeScheduledKey = nil
        actionToken &+= 1
        callToken &+= 1
        aidHandledKeys = []
        noCallsHandKey = nil
        timeoutNoticeKeys = []
        discardPracticeGame()   // 봇·걸음·시계 작업까지 거둔다(봇은 취소를 받고 곧바로 돌아온다)
        showsPractice = false
        match = nil
        users = []
        invites = []
        publicRooms = []
        record = nil
        rubyBalance = nil
        ranking = nil
        rankingUnavailable = false
        notice = nil
        isWorking = false
        isAnsweringCall = false
        foldTwoStageInputs()
        motion = nil
        availability = .available
        lobbyRoom = nil
        activeMatchID = nil
        answeredWindowIDs = []
        answeredWindowAnswers = [:]
        dismissedMatchIDs = []
        deliveredAttentionKeys = []
        seenInviteIDs = []
        lastLobbyRequestAt = .distantPast
        lastStateRequestAt = .distantPast
        writeRevision = 0
        serverClockOffset = 0
        recomputePhase()
        syncHoldingActivity()
    }

    // MARK: 공용 도우미

    /// 서버 epoch ms → 기기 Date(②).
    func localDate(serverMs: Double?) -> Date? {
        guard let serverMs else { return nil }
        return Date(timeIntervalSince1970: serverMs / 1_000 + serverClockOffset)
    }

    /// 응답의 `server_now_ms` 로 시계 차를 잡는다.
    func noteServerClock(_ serverNowMs: Double?) {
        guard let serverNowMs else { return }
        serverClockOffset = clock().timeIntervalSince1970 - serverNowMs / 1_000
    }

    /// 내가 앉은 forming 방 id(받은 초대에서 뺀다).
    var seatedRoomID: UUID? {
        if let room = match?.match, room.matchStatus == .forming, let id = UUID(uuidString: room.id) { return id }
        return lobbyRoom?.id
    }

    /// forming 방의 joined 수.
    static func joinedCount(_ payload: MahjongStatePayload?) -> Int {
        payload?.members?.filter { $0.state == "joined" }.count ?? 0
    }

    /// 2단 입력(리치 무장·치 조합·깡 후보)을 모두 접는다 — 결정 키가 바뀌거나 결정이 없어질 때(가드 (f)).
    func foldTwoStageInputs() {
        if riichiArmed { riichiArmed = false }
        if chiChoicesOpen { chiChoicesOpen = false }
        if kanChoicesOpen { kanChoicesOpen = false }
    }

    /// 화면 단계를 칸에서 다시 계산한다.
    func recomputePhase() {
        let next: MahjongPhase
        if showsPractice, let practice {
            next = practice.payload.match?.matchStatus == .finished ? .finished : .playing
        } else {
            switch match?.match?.matchStatus {
            case .forming?: next = .room
            case .active?: next = .playing
            case .finished?: next = .finished
            default: next = .lobby
            }
        }
        if phase != next { phase = next }
    }
}

// MARK: - 공용 관용구 · 폴링 · 초인종(C2)

extension MahjongStore {
    /// 로비 폴링 주기(③ — 창이 탁자를 보일 때만).
    nonisolated static let lobbyPollSeconds: TimeInterval = 30
    /// 방(forming) 폴링 주기.
    nonisolated static let roomPollSeconds: TimeInterval = 10
    /// 판 폴링 주기 — 실시간 구독 중 / 미구독(큐브 15초 그물은 5초 결정에 너무 성기다, MCL:77).
    nonisolated static let statePollSecondsSubscribed: TimeInterval = 5
    nonisolated static let statePollSecondsUnsubscribed: TimeInterval = 1.5
    /// 순위 폴링 주기.
    nonisolated static let rankingPollSeconds: TimeInterval = 60
    /// 방 확인(창과 무관 — 내가 joined 인 forming 방 + 장부, CS-03).
    nonisolated static let roomCheckSeconds: TimeInterval = 30
    /// 팝오버 열림 로비 스로틀(초).
    nonisolated static let menuLobbyThrottleSeconds: TimeInterval = 30
    /// 깨우기 재시도 간격 · 같은 열쇠 재시도 상한(첫 깨우기 뒤 2번 — MCL:142).
    nonisolated static let wakeRetrySeconds: TimeInterval = 1
    nonisolated static let wakeRetryLimit = 2
    /// 결정 주인 깨우기 여유(마감 + 유예 + 100ms).
    nonisolated static let wakeSlackMs: Double = 100
    /// 박자 기기 깨우기 흔들림 상한(ms — 0~150).
    nonisolated static let beatJitterMs: Double = 150
    /// 서버가 유예를 안 실었을 때(§3.6 `grace_ms` 1000).
    nonisolated static let defaultGraceMs: Double = 1_000

    /// 판 폴링 주기(구독 여부만 본다 — 마감 박자는 깨우기 몫).
    nonisolated static func statePollSeconds(subscribed: Bool) -> TimeInterval {
        subscribed ? statePollSecondsSubscribed : statePollSecondsUnsubscribed
    }

    /// 공용 호출 관용구: 세션 가드 → 두 세대 캡처 → withSessionRetry → 두 세대 대조(리버시 `perform` 과 같다).
    /// nil = 버린 결과(세션 없음·세대가 밀림·취소). 호출부는 nil 이면 **아무것도 바꾸지 않는다.**
    func perform<T: Sendable>(
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
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return nil }
            if case .cancelled = host.classifyAuthError(error) { return nil }
            return .failure(error)
        }
    }

    /// 요청 마감(CC-06 — D44): `seconds` 안에 안 끝나면 그 요청 작업을 취소하고 nil. 서버는 이미 처리했을 수 있다 — 다음 state 가 진실이다.
    /// 공용 `DuelRPC.swift`·공용 세션 한도는 안 고친다(URLSession async `data(for:)` 는 작업 취소를 따른다).
    func performWithin(
        _ seconds: TimeInterval,
        _ operation: @escaping @Sendable (SupabaseWorkService, String) async throws -> MahjongActionResponse
    ) async -> Result<MahjongActionResponse, any Error>? {
        let request = Task { @MainActor [weak self] () -> Result<MahjongActionResponse, any Error>? in
            guard let self else { return nil }
            return await self.perform(operation)
        }
        let timer = Task {
            try? await Task.sleep(for: .seconds(max(0, seconds)))
            if !Task.isCancelled { request.cancel() }
        }
        let value = await request.value
        timer.cancel()
        return value
    }

    /// act·call·back 의 요청 마감(초) — `min(천장, max(바닥, 내 deadline_ms − 지금 + grace_ms))`.
    func requestDeadlineSeconds(deadlineMs: Double?) -> TimeInterval {
        let grace = (match?.match?.graceMs).map(Double.init) ?? Self.defaultGraceMs
        guard let deadline = localDate(serverMs: deadlineMs.map { $0 + grace }) else { return requestDeadlineCeiling }
        return min(requestDeadlineCeiling, max(requestDeadlineFloor, deadline.timeIntervalSince(clock())))
    }

    /// 서버에 아잉 마작 RPC 가 아직 없다(PGRST202 — 앱이 db push 보다 먼저 나간 창).
    nonisolated func isSchemaMissing(_ error: any Error) -> Bool {
        (error as? SupabaseWorkServiceError) == .databaseSchemaMissing
    }

    /// 쓰기 동작이 throw 로 실패했다(5xx·오프라인·PGRST202).
    func noteActionFailure(_ error: any Error) {
        if isSchemaMissing(error) { noteServerMissing() } else { setNotice(MahjongNoticeText.checkConnection) }
    }

    /// Availability `.serverMissing` — 서버에 아잉 마작이 아직 없다.
    func noteServerMissing() {
        if availability != .serverMissing { availability = .serverMissing }
        setNotice(MahjongNoticeText.unavailable)
    }

    /// Availability `.updateRequired` — 내 앱이 옛 버전이다.
    func noteUpdateRequired() {
        if availability != .updateRequired { availability = .updateRequired }
        setNotice(MahjongNoticeText.updateRequired)
    }

    /// 안내줄 한 문(⑤).
    func setNotice(_ text: String?) {
        if notice != text { notice = text }
    }

    /// 잔액 한 문 — 호스트 루비 미러도 같이.
    func applyRuby(_ value: Int?) {
        guard let value else { return }
        if rubyBalance != value { rubyBalance = value }
        if let host, host.rubyBalance != value { host.rubyBalance = value }
    }

    /// 요청 표 하나를 뗀다(state 를 돌려줄 수 있는 요청을 **보내기 직전에**).
    func issueTicket() -> Int {
        requestTicket &+= 1
        return requestTicket
    }

    /// 내 사용자 id(소문자) — 호스트가 없으면 nil.
    var myUserID: String? { host?.session?.userID.lowercased() }

    // MARK: 초인종 · 계기

    /// 직렬화된 재조회 — 도는 중이면 뒤따르는 **한 번**으로 합친다(V2-02 · CC-17).
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
                // 루프 **안에서 먼저** 내린다 — 뒤에 내리면 이번 조회가 도는 동안 온 신호를 지운다.
                self.syncPendingTrailing = false
                await self.syncOnce()
            } while self.syncPendingTrailing && generation == self.resetGeneration
            if generation == self.resetGeneration { self.syncTask = nil }
        }
    }

    /// 신호 한 번의 조회: 서버 `match`(방 포함)가 끝나지 않았으면 그 판, 아니면 로비 — **연습 여부와 무관**(CC-02).
    func syncOnce() async {
        if let current = match?.match, !current.matchStatus.isTerminal {
            await refreshMatch(id: current.id)
        } else {
            await refreshLobby()
        }
    }

    // MARK: 폴링(③ — 창이 탁자를 보일 때만)

    func startPolling() {
        guard pollTask == nil, isWindowShowingTable, host?.session != nil else { return }
        pollToken &+= 1
        let token = pollToken
        pollTask = Task { @MainActor [weak self] in
            while true {
                let step = self?.pollStepSeconds ?? 0.5
                try? await Task.sleep(for: .seconds(step))
                guard let self else { return }
                guard !Task.isCancelled, token == self.pollToken, self.isWindowShowingTable else {
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

    /// ⓑ 폴링 걸음의 조회를 **폴링 작업의 취소 밖에서** 돌리고 끝날 때까지 기다린다(리버시 `outsidePolling` 꼴, V2-03).
    /// 창을 닫는 순간의 취소가 그 조회에 합쳐진 초인종 조회까지 죽이지 않게 한다. 남은 걸음은 ⓒ 가드가 막는다(VR-04).
    func outsidePolling(_ body: @escaping @MainActor (MahjongStore) async -> Void) async {
        await Task { @MainActor [weak self] in
            guard let self else { return }
            await body(self)
        }.value
    }
}
