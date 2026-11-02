import Foundation
import Observation
import OSLog

// 아잉 뒤집기(내부 이름 reversi) 1:1 대결 스토어 — 화면 상태 · 서버 동기화 · 안전망 폴링 · RPC 호출.
// 계약은 설계서 FLIP/SPEC.md §4.4(이 표면) · §4.5(애니메이션·경고) · §5.6(문구)이다. 맥 화면(U)과 통합(T)이
// **이 이름·서명 그대로** 위에 선다 — 바꿔야 하면 설계서부터 고친다.
//
// 본은 `ChessStore` 머리말 ①~⑪ 이고, 리버시에서 달라지는 자리는 이렇다:
//  ① **서버가 권위다.** 판(64자 문자열)·차례·시계·결과·루비는 RPC 응답으로만 바뀐다. 낙관적 착수·낙관적 차감 없음.
//  ② **시각은 서버 시계로 보정한다**(`server_now_ms` 와의 차이).
//  ③ **폴링은 창이 보일 때만** 돈다. 주기 판정은 `pollTick(at:)` 한 곳 — 오목 `statePollSeconds`(구독 10초 · 마감 10초 안 3초
//     · 미구독 1.5초) + **보낸 신청은 5초마다 `reversi_state(outgoing.id)`**(수락 순간 흑 시계가 돈다 — 초인종을 놓치면
//     첫 수가 자동 착수가 되고 연속 횟수가 1 오른다).
//  ④ **늦게 온 응답은 버린다** — 세대(reset·watch·ai) · 같은 판 `move_count` 감소 무시 · 끝난 판 뒤 진행 응답 무시 ·
//     다른 진행 판이 있을 때 끝난 판 무시 · 접은 판 · 같은 판 조회 합치기 · `outgoingRevision` ·
//     `visibleIncomingInvites` 는 `match?.id` 와 같은 id 를 뺀다(수락 전에 나간 로비 응답이 수락 뒤에 와서 되살리는 것 방지).
//  ⑤ **사용자 문구는 `ReversiNoticeText` 한 곳**(진단 어휘 금지).
//  ⑥ **초 단위 값은 잎 뷰만** 읽는다(`remainingSeconds(now:)` 는 순수 계산 — 스토어는 매초 대입하지 않는다).
//  ⑦ **합법 수는 서버 `legal_moves` 로만**(내 차례일 때만 온다, DEC:26). **AI 판은 로컬 규칙**이 권위다.
//  ⑧ 입력은 한 단(칸 하나)이다 — 체스의 선택 2단이 없다.
//  ⑨ **시계는 서버 응답마다 통째로 덮는다**(마감 하나, 표시값 30초 — 서버 유예 2초 미포함).
//  ⑩ 오목의 **자동 착수 장치**가 있다(30초 넘기면 서버가 합법 수 중 무작위로 둔다 · `myAutoStreak` · 연속 3이면 패 ·
//     자동 패스는 시계·연속 횟수에 안 센다). 체스(⑩ 없음)와 다르다.
//  ⑪ **받은 신청은 로비 `me.incoming` 이 통째로 준다**(테트리스식 — 갈아 끼운다). 보낸 신청만 state 로 따로 본다(③).
//
// 이 파일은 **C1 뼈대**다 — 표면(칸·계산 칸·함수 서명)과 값 타입·문구 표가 서 있고, 동작 몸통은 C2 가 같은 파일에서 채운다.
// 칸은 전부 `package internal(set)` — 맥 모듈은 못 쓰고 `@testable` 시험은 쓴다(큐브 `RummyStore` 선례). `private(set)` 은
// `@testable` 로도 안 열려 렌더 시험·점 시험이 상태를 못 심는다.

// MARK: - 호스트

/// 네트워크·세션·루비 미러를 빌리는 곳. 오목·체스와 멤버가 같아 그 프로토콜을 그대로 요구한다
/// (`CheckCoreShared.swift` 는 고치지 않는다).
package typealias ReversiStoreHost = GomokuStoreHost

// MARK: - 화면 값 타입

/// 화면 단계. 관전은 phase 가 아니라 `spectating != nil` 이다.
package nonisolated enum ReversiPhase: Equatable, Sendable { case lobby, playing, result }

/// 이 앱·서버 조합에서 아잉 뒤집기를 쓸 수 있는가. 로비 ok → `.available` · `unsupported_client` → `.updateRequired` ·
/// PGRST202(`.databaseSchemaMissing` — 앱이 db push 보다 먼저 나간 창) → `.serverMissing`.
package nonisolated enum ReversiAvailability: Equatable, Sendable { case available, updateRequired, serverMissing }

/// 판돈(루비). 승자 2× · 수수료 0 · 무승부 각자 환불(DEC:19).
package nonisolated enum ReversiStake: Int, CaseIterable, Sendable { case three = 3, five = 5, ten = 10 }

/// AI 수 선택기. 판과 둘 색을 받아 한 칸(idx)을 돌려준다. nil = 둘 곳 없음 — 호출자가 무작위 대타를 둔다.
/// 테스트가 결정적 가짜로 갈아 끼운다(오목 `GomokuAIMoveChooser` 꼴).
package typealias ReversiAIMoveChooser = @Sendable (ReversiBoard, ReversiColor) async -> Int?

/// 사람 한 명(로비 상대 목록 · 신청 상대 · 판의 두 사람 · 순위 줄 공용).
package nonisolated struct ReversiUser: Identifiable, Equatable, Hashable, Sendable {
    /// user uuid 소문자.
    package let id: String
    package let displayName: String
    package let avatarURL: String?
    package let characterID: String?
    /// 소속 센터의 **화면 글자**. 서버 어휘 → 글자 변환은 스토어 경계에서 한 번만 한다.
    package var center: String?
    package var isWorking: Bool
    /// 상대 앱이 아잉 뒤집기를 아는 버전인가(서버 `reversi_capable`). **모르면 불가**다.
    package var isCapable: Bool
    /// 지금 어떤 1:1 판이든 두는 중인가(서버 `game__busy_users` — 한 사람은 한 판만).
    package var inMatch: Bool
    /// 집중 모드 — 신청할 수 없다(`target_focused`).
    package var focusMode: Bool

    package init(
        id: String, displayName: String, avatarURL: String? = nil, characterID: String? = nil, center: String? = nil,
        isWorking: Bool = false, isCapable: Bool = true, inMatch: Bool = false, focusMode: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.characterID = characterID
        self.center = center
        self.isWorking = isWorking
        self.isCapable = isCapable
        self.inMatch = inMatch
        self.focusMode = focusMode
    }
}

/// 받은 신청 한 건(로비 `me.incoming` 한 줄).
package nonisolated struct ReversiInvite: Identifiable, Equatable, Sendable {
    /// match id 소문자.
    package let id: String
    package let peer: ReversiUser
    package let stake: Int
    /// 기기 시계로 보정한 만료 시각.
    package let expiresAt: Date

    package init(id: String, peer: ReversiUser, stake: Int, expiresAt: Date) {
        self.id = id
        self.peer = peer
        self.stake = stake
        self.expiresAt = expiresAt
    }
}

/// 보낸 신청(한 사람당 하나 — 서버 부분 유니크 인덱스).
package nonisolated struct ReversiOutgoing: Identifiable, Equatable, Sendable {
    /// match id 소문자.
    package let id: String
    package let peer: ReversiUser
    package let stake: Int
    /// 기기 시계로 보정한 만료 시각.
    package let expiresAt: Date

    package init(id: String, peer: ReversiUser, stake: Int, expiresAt: Date) {
        self.id = id
        self.peer = peer
        self.stake = stake
        self.expiresAt = expiresAt
    }
}

/// 로비 "지금 대결 중" 한 줄. **서버 순서 그대로**(최근 순) — 다시 정렬하지 않는다. a/b 는 uuid 오름차순(색이 아니다).
package nonisolated struct ReversiLiveMatch: Identifiable, Equatable, Sendable {
    package let id: String
    package let a: ReversiUser
    package let b: ReversiUser
    package let stake: Int
    package let startedAt: Date
    /// 관전자 수. **`var` 다** — 관전 응답이 이 줄의 숫자만 고쳐 쓴다(let 이면 줄을 통째로 다시 지어야 한다).
    package var watchers: Int

    package init(id: String, a: ReversiUser, b: ReversiUser, stake: Int, startedAt: Date, watchers: Int = 0) {
        self.id = id
        self.a = a
        self.b = b
        self.stake = stake
        self.startedAt = startedAt
        self.watchers = watchers
    }
}

/// 내 전적(로비 `me` 의 wins·losses·draws — 순위표와 같은 서버 함수).
package nonisolated struct ReversiRecord: Equatable, Sendable {
    package let wins: Int
    package let losses: Int
    package let draws: Int

    package init(wins: Int, losses: Int, draws: Int) {
        self.wins = wins
        self.losses = losses
        self.draws = draws
    }
}

/// 내 기준 판 결과.
package nonisolated enum ReversiMatchOutcome: Equatable, Sendable { case won, lost, draw }

/// 창이 안 보이는 사람에게 "판이 섰다 / 지금 둘 차례" 를 알리는 한 건. 같은 (판 id, move_count) 에는 한 번만 만든다.
/// 받는 쪽은 `attention.moveCount == match.moveCount` 로 낡은 "내 차례"를 버린다.
package nonisolated struct ReversiAttention: Equatable, Sendable {
    package enum Kind: Equatable, Sendable { case matchStarted, myTurn }

    package let kind: Kind
    package let matchID: String
    package let opponentName: String
    package let moveCount: Int

    package init(kind: Kind, matchID: String, opponentName: String, moveCount: Int) {
        self.kind = kind
        self.matchID = matchID
        self.opponentName = opponentName
        self.moveCount = moveCount
    }
}

/// 내 판 한 판(1:1 또는 AI). 1:1 은 서버 state 를 옮긴 값이고, AI 판은 `ReversiAIGame` 을 옮긴 값이다(`isAI`).
package nonisolated struct ReversiMatchState: Identifiable, Equatable, Sendable {
    /// match id 소문자. AI 판은 `"ai-"` 머리말(`ReversiAIGame.isAIMatchID`).
    package let id: String
    package var isAI: Bool
    package var status: ReversiMatchStatus
    package var stake: Int
    package var myColor: ReversiColor
    package var opponent: ReversiUser
    package var blackUser: ReversiUser?
    package var whiteUser: ReversiUser?
    /// **판의 권위**(서버 64자 문자열).
    package var board: ReversiBoard
    /// 패스 포함 기록 수 = 마지막 seq. 다음 착수의 `p_expected_seq`.
    package var moveCount: Int
    /// 지금 둘 색. 끝났으면 nil.
    package var turn: ReversiColor?
    package var turnStartedAt: Date?
    /// 지금 차례의 표시 마감(차례 시작 + 30초, 서버 유예 미포함). 끝났거나 AI 차례·멈춘 AI 시계면 nil.
    package var deadline: Date?
    /// 서버 `legal_moves`(내 차례일 때만 온다, 오름차순). AI 판은 로컬 규칙으로 채운다.
    package var legalMoves: [Int]
    /// 수 기록(패스 줄 포함, seq 순).
    package var plies: [ReversiPly]
    /// 마지막 **돌** 수의 칸(패스는 건너뛴다). 빨간 점 자리.
    package var lastStoneIdx: Int?
    /// 시간 초과 자동 착수로 놓인 돌의 칸(회색 점).
    package var autoStones: Set<Int>
    /// 판 위 실제 돌 수(늘).
    package var counts: ReversiCounts
    /// WOF 점수 — 자연 종료만(기권·abandoned 는 nil, V-15).
    package var score: ReversiScore?
    package var result: ReversiResult?
    package var endReason: ReversiEndReason?
    /// 이긴 색. 끝났는데 nil 이면 무승부다.
    package var winner: ReversiColor?
    package var myAutoStreak: Int
    package var opponentAutoStreak: Int
    /// 이 수만큼 연달아 자동 착수되면 패(서버 값, 기본 3).
    package var autoAbandonStreak: Int
    /// 지금 이 판을 보는 사람 수.
    package var watchers: Int

    package var isFinished: Bool { status == .finished }
    package var isMyTurn: Bool { !isFinished && turn == myColor }
    /// 내 기준 결과(끝난 판만).
    package var outcome: ReversiMatchOutcome? {
        guard isFinished, let result else { return nil }
        guard let winner = result.winner else { return .draw }
        return winner == myColor ? .won : .lost
    }

    package init(
        id: String, isAI: Bool = false, status: ReversiMatchStatus = .active, stake: Int, myColor: ReversiColor,
        opponent: ReversiUser, blackUser: ReversiUser? = nil, whiteUser: ReversiUser? = nil,
        board: ReversiBoard = .start, moveCount: Int = 0, turn: ReversiColor? = .black, turnStartedAt: Date? = nil,
        deadline: Date? = nil, legalMoves: [Int] = [], plies: [ReversiPly] = [], lastStoneIdx: Int? = nil,
        autoStones: Set<Int> = [], counts: ReversiCounts? = nil, score: ReversiScore? = nil,
        result: ReversiResult? = nil, endReason: ReversiEndReason? = nil, winner: ReversiColor? = nil,
        myAutoStreak: Int = 0, opponentAutoStreak: Int = 0, autoAbandonStreak: Int = 3, watchers: Int = 0
    ) {
        self.id = id
        self.isAI = isAI
        self.status = status
        self.stake = stake
        self.myColor = myColor
        self.opponent = opponent
        self.blackUser = blackUser
        self.whiteUser = whiteUser
        self.board = board
        self.moveCount = moveCount
        self.turn = turn
        self.turnStartedAt = turnStartedAt
        self.deadline = deadline
        self.legalMoves = legalMoves
        self.plies = plies
        self.lastStoneIdx = lastStoneIdx
        self.autoStones = autoStones
        self.counts = counts ?? board.counts
        self.score = score
        self.result = result
        self.endReason = endReason
        self.winner = winner
        self.myAutoStreak = myAutoStreak
        self.opponentAutoStreak = opponentAutoStreak
        self.autoAbandonStreak = autoAbandonStreak
        self.watchers = watchers
    }
}

// MARK: - 문구 표 (사용자 어휘 — 이 표 밖에서 문구를 만들지 마라, §5.6)

/// 아잉 뒤집기 안내 한 줄의 **유일한 출처**. 게임 이름 글자도 여기 한 곳이다(맥 `ReversiText.gameName` 은 이 값을 받는다).
/// 진단 어휘(서버·상태·동기화·프로토콜)는 쓰지 않는다 — 사용자가 **할 수 있는 일**을 말한다.
/// 공용 거절(busy·target_busy·target_focused·blackout·insufficient·already_pending·expired·not_pending·invalid·unauthorized)은
/// `ChessNoticeText` 의 같은 줄을 글자 그대로 쓰고 게임 이름만 바꾼다.
package nonisolated enum ReversiNoticeText {
    /// 게임 이름(정확히 16바이트 — Release 바이트 검사의 경계, §5.6).
    package static let gameName = "아잉 뒤집기"

    package static let tryAgain = "잠시 후 다시 시도해 주세요"
    package static let checkConnection = "연결을 확인하고 다시 시도해 주세요"
    /// 내 앱이 옛 버전이다(`unsupported_client` · Availability `.updateRequired`).
    package static let updateRequired = "앱을 업데이트해 주세요"
    package static let signInAgain = "다시 로그인해 주세요"
    package static let notYourTurn = "상대 차례예요"
    package static let inviteTimedOut = "상대가 응답하지 않았어요"
    /// 보낸 신청이 만료 전에 사라졌다(거절·취소·상대가 다른 대국을 시작함 — 사용자에게는 모두 같은 뜻이다).
    package static let inviteDeclined = "상대가 신청을 받지 않았어요"
    package static let finishedInvite = "이미 끝난 신청이에요"
    package static let finishedMatch = "이미 끝난 대국이에요"
    /// 앞 착수·기권이 아직 왕복 중이라 잠긴 동안 또 눌렀다.
    package static let sending = "보내는 중이에요"
    package static let busy = "이미 진행 중인 대국이 있어요"
    package static let targetBusy = "상대가 다른 대국 중이에요"
    /// 상대 앱이 리버시 RPC 를 모른다(`target_outdated`).
    package static let targetOutdated = "상대 앱이 \(gameName)를 아직 몰라요"

    // 둘 수 없는 칸(`illegal{reason}` · 로컬 거절 공용).
    package static let occupied = "이미 돌이 있는 칸이에요"
    package static let noFlip = "뒤집을 돌이 없는 칸이에요"
    package static let outOfRange = "둘 수 없는 칸이에요"

    // 시간 초과 · 패스.
    /// 내 차례가 30초를 넘겨 서버가 대신 뒀다(`auto_placed`).
    package static let autoPlaced = "시간이 지나 자동으로 놓였어요"
    /// 내가 둘 곳이 없어 상대에게 넘어갔다.
    package static let myPass = "둘 곳이 없어 차례가 넘어가요"
    /// 상대가 둘 곳이 없어 내 차례가 이어진다.
    package static func opponentPassed(name: String) -> String { "\(name)님이 둘 곳이 없어 내 차례가 이어져요" }

    // 관전 · 배포 창.
    /// 볼 수 없는 판(끝난 지 오래됐거나 숨김 격리). 서버는 있다/없다를 가르지 않는다.
    package static let watchGone = "지금은 볼 수 없는 판이에요"
    /// 서버에 아잉 뒤집기가 아직 없다(PGRST202 — 배포 중간 창).
    package static let unavailable = "\(gameName)는 곧 열려요"

    /// 불법 수 까닭 → 문구.
    package static func illegal(_ reason: ReversiIllegalReason) -> String {
        switch reason {
        case .occupied: return occupied
        case .noFlip: return noFlip
        case .outOfRange: return outOfRange
        }
    }

    /// 신청 결과. 서버는 근무 조건이 없다 — 클라가 근무를 보고 미리 막는 선게이트를 만들지 마라.
    package static func challenge(_ status: ReversiRPCStatus, need: Int? = nil, have: Int? = nil) -> String {
        switch status {
        case .ok: return "신청을 보냈어요"
        case .invalid: return "신청할 수 없는 상대예요"
        case .blackout: return "지금은 조용한 기간이라 신청할 수 없어요"
        case .targetFocused: return "상대가 집중 모드라 신청할 수 없어요"
        case .targetOutdated: return targetOutdated
        case .busy: return busy
        case .targetBusy: return targetBusy
        case .alreadyPending: return "이미 보낸 신청이 있어요"
        case .insufficient: return CheckCoreShared.shortfallNotice(need: need, have: have)
        default: return common(status)
        }
    }

    package static func cancel(_ status: ReversiRPCStatus) -> String {
        switch status {
        case .ok: return "신청을 취소했어요"
        case .notFound, .notPending, .expired: return finishedInvite
        default: return common(status)
        }
    }

    /// 수락·거절 결과. **수락 성공은 판이 곧바로 열리므로 말하지 않는다**(nil).
    package static func respond(
        accept: Bool, _ status: ReversiRPCStatus, side: String? = nil, need: Int? = nil, have: Int? = nil
    ) -> String? {
        switch status {
        case .ok: return accept ? nil : "신청을 거절했어요"
        case .notFound, .notPending: return finishedInvite
        case .expired: return "신청 시간이 지났어요"
        case .invalid: return "받을 수 없는 신청이에요"
        case .busy: return busy
        case .targetBusy: return targetBusy
        case .insufficient:
            if side == "challenger" { return "상대의 루비가 모자라요" }
            return CheckCoreShared.shortfallNotice(need: need, have: have)
        default: return common(status)
        }
    }

    /// 착수 결과. **성공과 `stale` 은 말하지 않는다**(nil) — 실려 온 state 로 화면이 답한다.
    package static func move(_ status: ReversiRPCStatus, reason: ReversiIllegalReason? = nil) -> String? {
        switch status {
        case .ok, .stale: return nil
        case .illegal: return reason.map(illegal) ?? outOfRange
        case .autoPlaced: return autoPlaced
        case .notYourTurn: return notYourTurn
        case .notActive, .notFound: return finishedMatch
        default: return common(status)
        }
    }

    /// 기권 결과. 성공은 결과 화면이 말한다(nil).
    package static func resign(_ status: ReversiRPCStatus) -> String? {
        switch status {
        case .ok: return nil
        case .notActive, .notFound: return finishedMatch
        default: return common(status)
        }
    }

    private static func common(_ status: ReversiRPCStatus) -> String {
        switch status {
        case .unsupportedClient: return updateRequired
        case .unauthorized: return signInAgain
        default: return tryAgain
        }
    }
}

// MARK: - 스토어

@MainActor
@Observable
package final class ReversiStore {
    package nonisolated static let logger = Logger(subsystem: "kingcheck", category: "reversi")

    /// 네트워크·세션·루비 미러를 빌리는 곳. **약참조다** — 소유자(`WorkTimerStore`)가 이 스토어를 가진다.
    /// nil 이면 미리보기·렌더 시험용이라 네트워크를 한 건도 내지 않는다.
    @ObservationIgnored package private(set) weak var host: (any ReversiStoreHost)?
    /// 기기 시계(시험이 갈아 끼운다).
    @ObservationIgnored package var clock: () -> Date

    package init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
    }

    /// 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다.
    package func attach(host: any ReversiStoreHost) {
        self.host = host
    }

    // MARK: 화면 상태 (칸은 전부 `package internal(set)`)

    package internal(set) var phase: ReversiPhase = .lobby
    package internal(set) var availability: ReversiAvailability = .available
    /// 1:1 또는 AI 판(`match.isAI`).
    package internal(set) var match: ReversiMatchState?
    package internal(set) var users: [ReversiUser] = []
    /// 로비 "지금 대결 중" 목록. **서버 순서 그대로**.
    package internal(set) var liveMatches: [ReversiLiveMatch] = []
    /// 받은 신청(서버가 여럿을 준다 — 최신이 앞). 화면은 `visibleIncomingInvites`·`visibleIncoming` 을 읽는다.
    package internal(set) var incoming: [ReversiInvite] = []
    package internal(set) var outgoing: ReversiOutgoing?
    package internal(set) var record: ReversiRecord?
    /// 서버 응답으로만 갱신(host 에도 반영).
    package internal(set) var rubyBalance: Int?
    package internal(set) var notice: String?
    /// 요청 비행 중(버튼 잠금).
    package internal(set) var isBusy = false
    /// 지금 판 위에서 뒤집히는 중인 수(그림 전용 — 입력·판정은 이 값을 보지 않는다).
    package internal(set) var flip: ReversiFlipAnimation?
    package internal(set) var spectating: ReversiSpectating?
    /// 내 판 관전자 수.
    package internal(set) var spectatorCount = 0
    package internal(set) var ranking: ReversiRanking?
    /// 서버에 `reversi_ranking` 이 아직 없다(PGRST202). 아래 둘과 **서로 다른 깃발**이다.
    package internal(set) var rankingUnavailable = false
    /// 서버에 `reversi_watch` 가 없다(관전 잠금은 이 깃발 하나로만).
    package internal(set) var watchUnavailable = false
    /// 서버에 `reversi_watch_live` 가 없어 `reversi_watch` 로 접었다(관전자 수만 못 센다).
    package internal(set) var spectatorCountUnavailable = false
    /// 창이 보이는가. 30초 링 잎(`paused: !store.isWindowVisible`)과 말풍선 "아직 사실인가" 판정이 읽는다.
    package internal(set) var isWindowVisible = false

    package var selectedStake: ReversiStake = .three
    package var isRulesVisible = false
    /// 차단 거울(맥 `blockHiddenPeerIDs` didSet 이 채운다). 소문자 uuid.
    package var hiddenPeerIDs: Set<String> = []
    /// 순위 적재 스위치. 기본 false — 켜는 곳은 맥 배선뿐(폰이 그리지도 않는 순위를 당기지 않게).
    package var rankingEnabled = false
    /// 관전 폴링·관전자 수 스위치. 기본 false — 켜는 곳은 맥 배선뿐.
    package var spectatorFeaturesEnabled = false

    // MARK: 계산 칸

    /// 차단 거울만 거른 상대 목록.
    package var visibleUsers: [ReversiUser] {
        hiddenPeerIDs.isEmpty ? users : users.filter { !hiddenPeerIDs.contains($0.id) }
    }

    /// 차단 거울을 거르고 **지금 내 판과 같은 id 를 뺀** 받은 신청(수락 뒤 늦게 온 옛 로비 응답이 되살리지 못하게).
    /// 말풍선 큐는 이 id 집합으로 거른다. **시계를 읽지 않는다** — 만료는 스토어 타이머가 `incoming` 에서 걷는다
    /// (계산 프로퍼티 안의 시각 비교는 관찰을 깨지 않아 만료된 점이 다음 무관한 갱신까지 남는다).
    package var visibleIncomingInvites: [ReversiInvite] {
        let matchID = match?.id
        guard !hiddenPeerIDs.isEmpty || matchID != nil else { return incoming }
        return incoming.filter { !hiddenPeerIDs.contains($0.peer.id) && $0.id != matchID }
    }

    /// 메뉴바 점·배너·사이드바 점이 읽는 첫 신청.
    package var visibleIncoming: ReversiInvite? { visibleIncomingInvites.first }

    /// 둘 수 있는 칸. 1:1 은 서버 `legal_moves`(내 차례만) · AI 판은 로컬 규칙(사람 차례만).
    package var legalTargets: Set<Int> {
        guard let match, match.isMyTurn else { return [] }
        if match.isAI { return Set(ReversiRules.legalMoves(match.board, color: match.myColor)) }
        return Set(match.legalMoves)
    }

    /// 대국 중이면 확성기 배너를 미룬다.
    package var defersMegaphoneBanner: Bool { phase == .playing }

    // MARK: 문 (맥 배선이 채운다)

    @ObservationIgnored package var presentWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var dismissWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var requestAttention: (@MainActor () -> Void)?
    @ObservationIgnored package var onInviteArrived: (@MainActor (ReversiInvite) -> Void)?
    /// 창이 안 보일 때 판 시작·내 차례(키 id#move_count 로 한 번).
    @ObservationIgnored package var onAttention: (@MainActor (ReversiAttention) -> Void)?
    /// 1:1 판이 끝났다(AI 판 제외) — 미션 새로 고침 꼬리.
    @ObservationIgnored package var onMatchFinished: (@MainActor () -> Void)?

    // MARK: 수명 — C2 가 채운다

    /// 로그아웃·계정 전환. 세대를 올리고 화면 상태를 처음으로 돌린다.
    package func reset() {}

    package func openWindow(focusMatchID: String?) {}
    package func windowDidShow() {}
    package func windowDidHide() {}
    package func windowDidClose() {}
    package func windowOcclusionDidChange(visible: Bool) {}

    // MARK: 계기 — C2 가 채운다

    /// 실시간 초인종(`'reversi'` → `.reversiSignal`).
    package func handleSignal() {}
    package func realtimeDidJoin() {}
    package func systemDidWake() {}
    package func refreshLobbyIfStale() {}

    // MARK: 동작 — C2 가 채운다

    /// `selectedStake` 로 신청한다.
    package func challenge(userID: String) async {}
    package func cancelChallenge() async {}
    package func respond(inviteID: String, accept: Bool) async {}
    /// 1:1 은 서버, AI 판은 로컬. `legalTargets` 밖이면 요청 없이 문구만.
    package func place(_ idx: Int) async {}
    package func resign() async {}
    package func backToLobby() {}

    /// 지금 차례(내 것이든 상대 것이든)의 남은 초 — 표시값 30초 기준, 서버 유예 미포함. 마감이 없으면 nil.
    /// 잎 뷰가 `now` 를 넘겨 부르는 **순수 계산**이다(⑥).
    package func remainingSeconds(now: Date) -> Double? {
        guard let match, !match.isFinished, let deadline = match.deadline else { return nil }
        return max(0, deadline.timeIntervalSince(now))
    }

    // MARK: 픽스처 문 — U·T 시험은 S 픽스처 원문을 이 두 문으로 넣는다

    package enum StateApplyOutcome: Equatable { case applied, needsFull, ignored }

    /// 서버 state 를 화면 상태로 옮긴다. 쓰기 RPC 응답(state 전체)은 `requestedSince: 0` 으로 다시 짓고,
    /// 아니면 seq 로 이어 붙이며 틈이 보이면 `.needsFull`. — C2 가 채운다.
    @discardableResult
    package func applyState(_ payload: ReversiStatePayload, requestedSince: Int = 0) -> StateApplyOutcome {
        .ignored
    }

    /// 로비 응답을 화면 상태로 옮긴다(받은 신청은 통째로 갈아 끼운다). — C2 가 채운다.
    package func applyLobby(_ response: ReversiLobbyResponse) {}
}
