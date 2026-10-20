import Foundation
import Observation
import OSLog

// 1:1 테트리스 대결 스토어(v0.3.60) — 화면 상태 · 서버 동기화 · 판 구동 · 보고 루프 · RPC 호출. 맥·폰 공용(코어).
//
// 본은 `ChessStore` 다. **같은 규약을 그대로 베끼고**(아래 ①~⑥) 테트리스에서 달라지는 자리만 바꿨다.
//
// ── 베낀 규약 ──
//  ① **서버가 권위다.** 판 상태(시작 시각·상대 판·공격 누계)·결과·루비는 RPC 응답으로만 바뀐다. 낙관적 차감은 없다.
//  ② **시각은 서버 시계로 보정한다**(`noteServerNow` · `deviceDate`). 단 판 시계는 벽시계가 아니라 **단조 시계**다(⑦).
//  ③ **판 밖 폴링은 창이 보일 때만 돈다**(보낸 신청 5초 · 로비 30초 — 체스와 같다). 판 중에는 보고 루프가 그 일을 한다.
//  ④ **늦게 온 응답은 버린다.** 세대 두 개(`resetGeneration` + `host.sessionGeneration`)가 로그아웃·계정 전환 뒤의 응답을,
//     판 세대(`duelGeneration`)가 판이 바뀐 뒤의 보고 응답을, 서버 seq(나·상대)가 같은 판의 옛 스냅숏을 버린다.
//  ⑤ **사용자 문구는 `TetrisDuelNoticeText` 한 곳에만 있다.**
//  ⑥ **신호는 합친다**(`requestSync` — 도는 중 온 신호는 뒤따르는 한 번).
//
// ── 테트리스에서 새로 생긴 자리 ──
//  ⑦ **판은 스토어가 든다**(`duel` — `TetrisDuelSession`). 뷰 `@State` 에 두면 창이 가려지거나 최소화될 때 판이 멈춘다.
//     설계 D10: 판 시간은 화면 프레임이 아니라 **단조 시계**(`uptime`)로 흐르고, 스토어의 판 루프(`gameLoopStepSeconds`)가
//     창과 무관하게 `advance(to:)` 를 부른다. 창이 보이면 뷰의 프레임 루프가 `tick()` 을 더 자주 부를 뿐이다(같은 시각이면 멱등).
//     `duel` 은 **관찰 대상이 아니다** — 프레임마다 바뀌는 값이라 관찰하면 그 값을 읽는 모든 뷰가 매 걸음 무효화된다.
//     뷰는 `TimelineView` 안에서 읽고, 조각이 굳을 때만 바뀌는 숫자는 관찰 가능한 `myStats` 로 따로 낸다.
//  ⑧ **보고 루프**(설계 §4.1). 1초 하트비트 · 공격 누계 증가와 탑아웃은 곧바로(최소 간격 0.25초) · 한 번에 하나만 나간다.
//     응답의 상대 `garbage_sent` 에서 **아직 반영 안 한 차분만** `receiveGarbage` 하고 그 누계를 `garbage_applied` 로 보고한다
//     (`TetrisDuelSession.absorbOpponentAttack` — 누계 차분이라 겹치거나 순서가 뒤집힌 응답에도 멱등).
//  ⑨ **준비 = 첫 보고**. 창이 화면에 떠 있을 때만 낸다(`isWindowVisible`) — 맥이 잠들었거나 창을 못 띄운 사람은 준비하지
//     않고, 서버가 30초 뒤 무승부(no_show)로 판돈을 돌려준다(D4). 한 번 준비한 뒤로는 창을 숨겨도 판이 흐른다(D10).

// MARK: - 호스트

/// 테트리스 스토어가 네트워크·세션·루비 미러를 빌리는 곳 — 오목·체스와 **같은 프로토콜**이다(같은 소유자가 세 게임의 호스트).
package typealias TetrisDuelStoreHost = GomokuStoreHost

// MARK: - 화면 값 타입

package nonisolated enum TetrisDuelStake: Int, CaseIterable, Sendable { case three = 3, five = 5, ten = 10 }

package nonisolated struct TetrisDuelUser: Identifiable, Equatable, Sendable {
    package let id: String                 // user uuid 소문자
    package let displayName: String
    package let avatarURL: String?
    package let characterID: String?
    package let isWorking: Bool
    /// 상대 앱이 테트리스 대결을 아는 버전인가(서버 `tetris_capable`). **모르면 불가**다.
    package let isCapable: Bool
    /// 오목·체스·테트리스 중 하나라도 진행 중인가(서버가 세 게임을 함께 본다 — 한 사람은 한 판만).
    package let inMatch: Bool
    /// 집중 모드(서버가 `target_focused` 로 신청을 막는다).
    package let isFocused: Bool

    package init(id: String, displayName: String, avatarURL: String?, characterID: String?,
                 isWorking: Bool, isCapable: Bool, inMatch: Bool, isFocused: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.characterID = characterID
        self.isWorking = isWorking
        self.isCapable = isCapable
        self.inMatch = inMatch
        self.isFocused = isFocused
    }

    /// [신청] 을 켤 수 있는가 — 서버가 어차피 거절할 상대(구버전 · 대결 중 · 집중)만 끈다.
    /// **근무 여부는 보지 않는다**(D1 — 오목·체스처럼 근무 조건이 없다. 클라 근무 선게이트를 만들지 마라).
    package var canBeChallenged: Bool { isCapable && !inMatch && !isFocused }
}

package nonisolated struct TetrisDuelRecord: Equatable, Sendable {
    package let wins: Int
    package let losses: Int
    package let draws: Int

    package init(wins: Int, losses: Int, draws: Int) {
        self.wins = wins
        self.losses = losses
        self.draws = draws
    }
}

package nonisolated struct TetrisDuelInvite: Identifiable, Equatable, Sendable {
    package let id: String                 // match id
    package let peer: TetrisDuelUser
    package let stake: Int
    /// 기기 시계로 보정된 만료 시각.
    package let expiresAt: Date

    package init(id: String, peer: TetrisDuelUser, stake: Int, expiresAt: Date) {
        self.id = id
        self.peer = peer
        self.stake = stake
        self.expiresAt = expiresAt
    }
}

/// 판이 끝난 사유. 서버 `tetris_matches.end_reason` CHECK 의 여섯 글자 그대로다(결과 문구는 전수 switch).
package nonisolated enum TetrisDuelEndReason: String, Sendable, CaseIterable {
    /// 꼭대기까지 쌓였다(진 사람이 스스로 신고한 탑아웃 — 서버가 믿는 몇 안 되는 주장, D9).
    case topout
    case resign
    /// 보고가 15초 끊겼다(서버 시계로 잰 침묵). 둘 다 끊기면 무승부다.
    case disconnect
    /// 판 상한 480초 — 무승부·환불.
    case timeCap = "time_cap"
    /// 수락 뒤 30초 안에 둘 다 준비하지 않았다 — 무승부·환불(전적에서 빠진다).
    case noShow = "no_show"
    /// 계정 삭제로 떠난 사람의 패.
    case abandoned

    /// 이 사유는 **언제나** 무승부인가(서버 CHECK). `disconnect` 는 둘 다 가능하므로 여기 없다.
    package var isAlwaysDraw: Bool {
        switch self {
        case .timeCap, .noShow: return true
        case .topout, .resign, .disconnect, .abandoned: return false
        }
    }
}

/// **내 기준** 결과.
package nonisolated enum TetrisDuelOutcome: Equatable, Sendable { case won, lost, draw }

/// 화면 흐름. **신청(보냄·받음)은 phase 가 아니라** `.lobby` 위의 `outgoing`·`incoming` 이다(체스와 같다).
///  · `.ready`     — 수락됐고 서버가 아직 판 시작을 안 정했다(둘 다 준비 전). 내 준비 보고가 나가는 단계다.
///  · `.countdown` — 서버가 `start_at`(둘째 준비 + 3초)을 정했고 아직 그 시각 전이다.
///  · `.playing`   — 판 시계가 0을 넘었다.
///  · `.finished`  — 서버가 판을 닫았다(결과 화면).
package nonisolated enum TetrisDuelPhase: Equatable, Sendable { case lobby, ready, countdown, playing, finished }

/// 흐름과 **따로** 서는 상태 — 이 기기가 지금 대결을 할 수 있는가.
package nonisolated enum TetrisDuelAvailability: Equatable, Sendable {
    case available
    /// 서버가 `unsupported_client` 를 냈다(이 앱의 프로토콜이 낮다 — 같은 계정의 옛 두 번째 기기 겹).
    case updateRequired
    /// 서버에 테트리스 RPC 가 아직 없다(PGRST202 — 앱이 db push 보다 먼저 나간 창).
    case serverMissing
}

/// 상대 판 스냅숏(보고가 올 때만 바뀐다 — 하트비트마다 오르는 seq·last_seen 은 **여기 없다**, 관찰자가 매초 깨지 않게).
package nonisolated struct TetrisDuelOpponentBoard: Equatable, Sendable {
    /// 20행 × 10칸(행 0 = 보이는 판 맨 위). 아직 보고가 없으면 전부 빈 칸이다.
    package let cells: [[TetrisDuelCell]]
    /// 판을 한 번이라도 받았는가(빈 판과 "아직 모름" 을 가른다).
    package let hasBoard: Bool
    package let lines: Int
    /// 상대가 보낸 공격 누계(서버가 상한으로 자른 값).
    package let attackSent: Int
    /// 상대 판에 아직 안 들어간 대기 방해 줄.
    package let pending: Int
    package let toppedOut: Bool
    package let ready: Bool

    package init(cells: [[TetrisDuelCell]], hasBoard: Bool, lines: Int, attackSent: Int, pending: Int,
                 toppedOut: Bool, ready: Bool) {
        self.cells = cells
        self.hasBoard = hasBoard
        self.lines = lines
        self.attackSent = attackSent
        self.pending = pending
        self.toppedOut = toppedOut
        self.ready = ready
    }

    package static let emptyCells: [[TetrisDuelCell]] =
        Array(repeating: Array(repeating: .empty, count: TetrisGame.columns), count: TetrisGame.visibleRows)

    package static let empty = TetrisDuelOpponentBoard(
        cells: emptyCells, hasBoard: false, lines: 0, attackSent: 0, pending: 0, toppedOut: false, ready: false)
}

/// 대결 한 판의 화면 상태(서버 응답이 바꾸는 값만).
package nonisolated struct TetrisDuelMatchState: Identifiable, Equatable, Sendable {
    package let id: String
    package var stake: Int
    /// 서버 시드. 진행 중 판이면 언제나 있다(수락 때 뽑는다).
    package var seed: Int?
    package var opponent: TetrisDuelUser
    package var acceptedAt: Date?
    /// 준비 마감(수락 + 30초). 화면의 "상대를 기다리는 중 n초" 가 읽는다.
    package var readyDeadline: Date?
    /// 판 시작(기기 시계 보정 — **표시용**). 판 시계는 단조 시계로 따로 잰다(`duel.startAt`).
    package var startAt: Date?
    /// 판 상한(start_at + 480초).
    package var maxEnd: Date?
    /// 서버가 내 준비를 받았는가.
    package var meReady: Bool
    package var opponentBoard: TetrisDuelOpponentBoard
    package var isFinished: Bool
    package var outcome: TetrisDuelOutcome?
    package var endReason: TetrisDuelEndReason?
    /// 이 판으로 내 루비가 변한 양(승 +(stake−수수료) · `DuelFee.winnerNet`, 패 −stake, 무 0).
    package var rubyDelta: Int?
    package var finishedAt: Date?

    package init(id: String, stake: Int, seed: Int?, opponent: TetrisDuelUser, acceptedAt: Date?,
                 readyDeadline: Date?, startAt: Date?, maxEnd: Date?, meReady: Bool,
                 opponentBoard: TetrisDuelOpponentBoard, isFinished: Bool, outcome: TetrisDuelOutcome?,
                 endReason: TetrisDuelEndReason?, rubyDelta: Int?, finishedAt: Date?) {
        self.id = id
        self.stake = stake
        self.seed = seed
        self.opponent = opponent
        self.acceptedAt = acceptedAt
        self.readyDeadline = readyDeadline
        self.startAt = startAt
        self.maxEnd = maxEnd
        self.meReady = meReady
        self.opponentBoard = opponentBoard
        self.isFinished = isFinished
        self.outcome = outcome
        self.endReason = endReason
        self.rubyDelta = rubyDelta
        self.finishedAt = finishedAt
    }
}

/// 내 판의 숫자들(조각이 굳을 때만 바뀐다 — 관찰 가능). 판 칸·떨어지는 조각은 `duel.game` 을 직접 읽는다.
package nonisolated struct TetrisDuelMyStats: Equatable, Sendable {
    package let lines: Int
    /// 보낸 공격 누계(상쇄 뒤).
    package let attackSent: Int
    /// 들어올 방해 줄(대기열 합 — 우물 왼쪽 미터).
    package let pendingGarbage: Int
    /// 가속 바닥(1 이면 아직 가속 전 — "속도 올라가는 중" 은 `> 1`).
    package let levelFloor: Int
    package let toppedOut: Bool

    package init(lines: Int, attackSent: Int, pendingGarbage: Int, levelFloor: Int, toppedOut: Bool) {
        self.lines = lines
        self.attackSent = attackSent
        self.pendingGarbage = pendingGarbage
        self.levelFloor = levelFloor
        self.toppedOut = toppedOut
    }
}

/// 로비 "지금 대결 중" 한 건. a/b 는 uuid 오름차순이다.
package nonisolated struct TetrisDuelLiveMatch: Identifiable, Equatable, Sendable {
    package let id: String
    package let a: TetrisDuelUser
    package let b: TetrisDuelUser
    package let stake: TetrisDuelStake
    package let startedAt: Date

    package init(id: String, a: TetrisDuelUser, b: TetrisDuelUser, stake: TetrisDuelStake, startedAt: Date) {
        self.id = id
        self.a = a
        self.b = b
        self.stake = stake
        self.startedAt = startedAt
    }
}

/// 창이 안 보이는 사람에게 "대결이 시작됐어요" 를 알리는 한 건(판 id 마다 한 번).
/// 차례가 없는 게임이라 체스의 `myTurn` 대응물은 없다.
package nonisolated struct TetrisDuelAttention: Equatable, Sendable {
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

// MARK: 순위

package nonisolated struct TetrisDuelRankEntry: Identifiable, Equatable, Sendable {
    package let id: String
    /// 서버가 매긴 순위(동률은 같은 숫자 — rank()).
    package let rank: Int
    package let user: TetrisDuelUser
    package let wins: Int
    package let losses: Int
    package let draws: Int
    /// 승점 = 승 − 패(서버 값).
    package let points: Int

    package init(id: String, rank: Int, user: TetrisDuelUser, wins: Int, losses: Int, draws: Int, points: Int) {
        self.id = id
        self.rank = rank
        self.user = user
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.points = points
    }
}

package nonisolated struct TetrisDuelMyRank: Equatable, Sendable {
    /// 0판이면 nil(순위 밖).
    package let rank: Int?
    package let wins: Int
    package let losses: Int
    package let draws: Int
    package let points: Int

    package init(rank: Int?, wins: Int, losses: Int, draws: Int, points: Int) {
        self.rank = rank
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.points = points
    }
}

/// 순위표. **`entries` 는 서버 순서 그대로**(재정렬 금지).
package nonisolated struct TetrisDuelRankingBoard: Equatable, Sendable {
    package let entries: [TetrisDuelRankEntry]
    package let me: TetrisDuelMyRank?
    package let recordSince: Date?

    package init(entries: [TetrisDuelRankEntry], me: TetrisDuelMyRank?, recordSince: Date?) {
        self.entries = entries
        self.me = me
        self.recordSince = recordSince
    }
}

// MARK: - 문구 표 (사용자 어휘 — 이 표 밖에서 문구를 만들지 마라)

/// 테트리스 대결 안내 한 줄의 **유일한 출처**. 진단 어휘(서버·상태·동기화)는 쓰지 않는다.
package nonisolated enum TetrisDuelNoticeText {
    package static let tryAgain = "잠시 후 다시 시도해 주세요"
    package static let checkConnection = "연결을 확인하고 다시 시도해 주세요"
    package static let updateMine = "앱을 업데이트해야 대결할 수 있어요"
    package static let signInAgain = "다시 로그인해 주세요"
    package static let inviteTimedOut = "상대가 응답하지 않았어요"
    /// 보낸 신청이 만료 전에 사라졌다(거절·취소·상대가 다른 대결을 시작함 — 사용자에게는 모두 같은 뜻이다).
    package static let inviteDeclined = "상대가 신청을 받지 않았어요"
    package static let finishedInvite = "이미 끝난 신청이에요"
    package static let finishedMatch = "이미 끝난 대결이에요"
    package static let busy = "이미 진행 중인 대결이 있어요"
    package static let targetBusy = "상대가 다른 대결 중이에요"
    /// 서버에 테트리스 대결이 아직 없다(PGRST202 — 배포 중간 창).
    package static let unavailable = "1:1 테트리스는 곧 열려요"

    /// 신청 결과. 근무 조건은 없다(D1) — 클라가 근무를 보고 미리 막는 선게이트를 만들지 마라.
    package static func challenge(_ status: TetrisRPCStatus, need: Int? = nil, have: Int? = nil) -> String {
        switch status {
        case .ok: return "신청을 보냈어요"
        case .invalid: return "신청할 수 없는 상대예요"
        case .blackout: return "지금은 조용한 기간이라 신청할 수 없어요"
        case .targetFocused: return "상대가 집중 모드라 신청할 수 없어요"
        case .targetOutdated: return "상대가 앱을 업데이트해야 해요"
        case .busy: return busy
        case .targetBusy: return targetBusy
        case .alreadyPending: return "이미 보낸 신청이 있어요"
        case .insufficient: return CheckCoreShared.shortfallNotice(need: need, have: have)
        default: return common(status)
        }
    }

    package static func cancel(_ status: TetrisRPCStatus) -> String {
        switch status {
        case .ok: return "신청을 취소했어요"
        case .notFound, .notPending, .expired: return finishedInvite
        default: return common(status)
        }
    }

    /// 수락·거절 결과. **수락 성공은 판이 곧바로 열리므로 말하지 않는다**(nil).
    package static func respond(
        accept: Bool, _ status: TetrisRPCStatus, side: String? = nil, need: Int? = nil, have: Int? = nil
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

    /// 기권 결과. 성공은 결과 화면이 말한다(nil). 시간 판정이 먼저라 이미 끝났어야 할 판은 `not_active` 가 온다.
    package static func resign(_ status: TetrisRPCStatus) -> String? {
        switch status {
        case .ok: return nil
        case .notActive, .notFound: return finishedMatch
        default: return common(status)
        }
    }

    /// 결과 카드의 사유 한 줄(**내 기준** — 승자면 주어가 "상대"). 사유를 모르면 빈 문자열.
    package static func endReason(_ reason: TetrisDuelEndReason?, outcome: TetrisDuelOutcome?) -> String {
        guard let reason else { return "" }
        switch reason {
        case .topout: return outcome == .won ? "상대가 꼭대기까지 쌓였어요" : "꼭대기까지 쌓였어요"
        case .resign: return outcome == .won ? "상대가 기권했어요" : "기권했어요"
        case .disconnect:
            switch outcome {
            case .won: return "상대 연결이 끊겼어요"
            case .lost: return "연결이 끊겼어요"
            case .draw, nil: return "둘 다 연결이 끊겼어요"
            }
        case .timeCap: return "시간 초과 — 판돈을 돌려받았어요"
        case .noShow: return "대결이 시작되지 않아 판돈을 돌려받았어요"
        case .abandoned: return outcome == .won ? "상대가 더 할 수 없게 됐어요" : "대결을 떠났어요"
        }
    }

    package static func common(_ status: TetrisRPCStatus) -> String {
        switch status {
        case .unsupportedClient: return updateMine
        case .notSignedIn: return signInAgain
        default: return tryAgain
        }
    }
}

// MARK: - 스토어

@MainActor
@Observable
package final class TetrisDuelStore {
    // MARK: 주기 상수

    /// 보낸 신청이 떠 있을 때 그 판의 상태를 보는 주기(초) — 체스와 같다. 조회 하나가 수락·거절·만료를 다 말한다.
    package nonisolated static let outgoingPollSeconds: TimeInterval = 5
    /// 로비 목록 재조회 주기(초).
    package nonisolated static let lobbyPollSeconds: TimeInterval = 30
    /// 팝오버를 열 때 로비를 다시 읽는 스로틀(초). 신청 TTL(60초)보다 짧다.
    package nonisolated static let menuLobbyThrottleSeconds: TimeInterval = 30
    /// 로비를 보고 있는 동안 순위표 재조회 주기(초).
    package nonisolated static let rankingPollSeconds: TimeInterval = 60
    /// 창 열기와 창 표시가 같은 조회를 두 번 쏘지 않게 하는 간격(초).
    package nonisolated static let reloadDedupeSeconds: TimeInterval = 1
    /// 서버 시계 오프셋을 다시 재는 문턱(초).
    package nonisolated static let serverClockToleranceSeconds: TimeInterval = 0.25
    /// 같은 신청을 다시 읽었을 때 만료가 이만큼 안쪽으로만 다르면 기존 값을 쓴다(초).
    package nonisolated static let inviteExpiryToleranceSeconds: TimeInterval = 1
    /// 보고가 이만큼 연달아 실패하면 `connectionTrouble` 을 세운다(화면: "연결 확인 중").
    package nonisolated static let reportFailureLimit = 2

    package nonisolated static let logger = Logger(subsystem: "kingcheck", category: "tetris-duel")

    /// 네트워크·세션·루비 미러를 빌리는 곳(약참조). nil 이면 미리보기·렌더 테스트용이라 네트워크를 한 건도 내지 않는다.
    @ObservationIgnored package private(set) weak var host: (any TetrisDuelStoreHost)?

    package init(host: (any TetrisDuelStoreHost)? = nil) {
        self.host = host
    }

    /// 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다.
    package func attach(host: any TetrisDuelStoreHost) {
        self.host = host
    }

    // MARK: 화면 상태

    package var phase: TetrisDuelPhase = .lobby
    package var availability: TetrisDuelAvailability = .available
    package var users: [TetrisDuelUser] = []
    package var record: TetrisDuelRecord?
    /// 받은 신청(서버가 여럿을 준다 — 최신이 앞). 화면은 `visibleIncomingInvites`·`visibleIncoming` 을 읽는다.
    package var incoming: [TetrisDuelInvite] = []
    /// 보낸 신청(부분 유니크 인덱스로 한 사람당 하나뿐이다).
    package var outgoing: TetrisDuelInvite?
    package var match: TetrisDuelMatchState? {
        didSet {
            if let line = Self.matchTransitionLine(from: oldValue, to: match) {
                Self.logger.notice("\(line, privacy: .public)")
            }
        }
    }
    /// 내 판의 숫자들(조각이 굳을 때만 바뀐다). 판이 없으면 nil.
    package var myStats: TetrisDuelMyStats?
    package var notice: String?
    package var isBusy = false
    package var isWindowVisible = false
    /// 서버 응답으로만 갱신(host 에도 반영).
    package var rubyBalance: Int?
    package var lobbyLoadFailed = false
    package var hasLoadedLobby = false
    /// 로비 "지금 대결 중" 목록(서버 순서 그대로).
    package var liveMatches: [TetrisDuelLiveMatch] = []
    /// 보고가 연달아 실패하는 중(판 화면의 "연결 확인 중"). 다음 성공이 내린다.
    package var connectionTrouble = false

    // 순위(로직은 TetrisDuelStoreGame.swift 의 순위 절).
    /// **순위 적재의 주 스위치. 기본 false.** 공용 스토어라 그리지도 않는 기기(폰 1.0.11 전)가 순위를 당기지 않게 한다.
    package var rankingEnabled = false
    package var ranking: TetrisDuelRankingBoard?
    package var rankingLoadFailed = false
    package var hasLoadedRanking = false
    /// 서버에 `tetris_ranking` 이 아직 없다(PGRST202).
    package var rankingUnavailable = false

    /// 차단으로 걷어낸 상대(소유자가 채운다). 코어 목록은 서버 답 그대로 두고 화면이 읽는 파생값만 거른다.
    package var hiddenPeerIDs: Set<String> = []

    /// 로비 상대 목록(화면용).
    package var visibleUsers: [TetrisDuelUser] {
        hiddenPeerIDs.isEmpty ? users : users.filter { !hiddenPeerIDs.contains($0.id) }
    }

    /// 받은 신청 전부(화면용 — 차단한 사람이 보낸 것은 뺀다).
    package var visibleIncomingInvites: [TetrisDuelInvite] {
        hiddenPeerIDs.isEmpty ? incoming : incoming.filter { !hiddenPeerIDs.contains($0.peer.id) }
    }

    /// 배너·메뉴바 점이 읽는 받은 신청 하나(가장 최근). **스토어가 만료를 걷은 값만** 읽는다 — 시각과 비교하지 마라.
    package var visibleIncoming: TetrisDuelInvite? { visibleIncomingInvites.first }

    // MARK: UI 트랙이 앱에서 물리는 문

    @ObservationIgnored package var presentWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var dismissWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var onInviteArrived: (@MainActor (TetrisDuelInvite) -> Void)?
    @ObservationIgnored package var requestAttention: (@MainActor () -> Void)?
    @ObservationIgnored package var onAttention: (@MainActor (TetrisDuelAttention) -> Void)?

    // MARK: 판 (관찰 대상 아님 — 머리말 ⑦)

    /// 내 판 구동기. **관찰 대상이 아니다** — 뷰는 `TimelineView` 안에서 읽는다. 입력은 이 스토어의 입력 문으로만 넣는다.
    @ObservationIgnored package internal(set) var duel: TetrisDuelSession?
    /// `duel` 이 어느 판의 것인가.
    @ObservationIgnored package internal(set) var duelMatchID: String?
    /// 판 구동기를 갈아 끼울 때마다 오른다 — 앞 판에 나간 보고의 응답이 새 판을 건드리지 못하게 한다.
    @ObservationIgnored package internal(set) var duelGeneration = 0
    @ObservationIgnored package internal(set) var gameLoopTask: Task<Void, Never>?
    @ObservationIgnored var gameLoopToken = 0
    /// 지금 나가 있는 보고(한 번에 하나). 테스트가 `await reportTask?.value` 로 기다린다.
    @ObservationIgnored package internal(set) var reportTask: Task<Void, Never>?
    @ObservationIgnored package internal(set) var reportInFlight = false
    @ObservationIgnored package internal(set) var reportFailureStreak = 0
    /// 서버가 말한 내 seq·상대 seq 의 최댓값(같은 판의 옛 스냅숏을 버리는 기준 — 머리말 ④).
    @ObservationIgnored package internal(set) var heldMySeq = 0
    @ObservationIgnored package internal(set) var heldOpponentSeq = 0
    /// 서버가 말한 상대 공격 누계의 최댓값. 판 시작 전에 온 공격은 시작 뒤 `tick` 이 이 값으로 다시 넣는다.
    @ObservationIgnored package internal(set) var opponentAttackTotal = 0
    /// 상대의 마지막 보고 시각(기기 시계 보정). "상대 연결 확인 중" 표시 재료.
    @ObservationIgnored package internal(set) var opponentLastSeenAt: Date?

    // MARK: 내부 장부 (관찰 대상 아님)

    /// 이 스토어의 벽시계 '지금'(서버 시각 보정·신청 만료). 테스트가 갈아 끼운다.
    @ObservationIgnored package var clock: () -> Date = { Date() }
    /// **단조 시계**(초). 판 시계·보고 간격은 이것만 쓴다 — 사용자가 시계를 돌려도 판이 건너뛰거나 멈추지 않는다.
    @ObservationIgnored package var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// 판 밖 폴링 루프의 한 걸음(초).
    @ObservationIgnored package var pollStepSeconds: TimeInterval = 0.5
    /// 판 루프의 한 걸음(초). 창과 무관하게 돈다(D10). 테스트는 3,600 으로 재우고 `tick(now:)` 을 직접 부른다.
    @ObservationIgnored package var gameLoopStepSeconds: TimeInterval = 0.05
    @ObservationIgnored package private(set) var serverClockOffset: TimeInterval = 0
    @ObservationIgnored private var hasServerClockOffset = false
    @ObservationIgnored package private(set) var resetGeneration = 0
    /// 창이 완전히 가려졌다. **폴링만** 이 값을 본다(판은 계속 흐른다).
    @ObservationIgnored package private(set) var isWindowOccluded = false
    @ObservationIgnored package private(set) var stateInFlightID: String?
    @ObservationIgnored private var pendingStateID: String?
    @ObservationIgnored private var stateInFlight = false
    @ObservationIgnored private var stateAgain = false
    @ObservationIgnored private var lobbyInFlight = false
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
    /// 신청 만료(초) — 응답이 만료를 안 실어 준 드문 경우의 기본값(서버 `tetris_invite_ttl_seconds()`).
    @ObservationIgnored package private(set) var inviteTTLSeconds: TimeInterval = 60
    /// 이 기기에서 보낸 신청을 새로 세울 때마다 오른다. 그보다 **먼저** 나간 로비 응답이 방금 보낸 신청을 지우지 않게 한다.
    @ObservationIgnored private var outgoingRevision = 0
    @ObservationIgnored private var lobbyRequestOutgoingRevision = 0

    // MARK: - 창

    /// 창을 띄우고 로비·판을 읽는다. `focusMatchID` 는 배너·말풍선에서 온 경로의 대상이다.
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

    /// 창이 실제로 보이기 시작했다. 폴링 시작 · 로비 재조회 · **준비 보고의 문이 열린다**(머리말 ⑨).
    package func windowDidShow() {
        if !isWindowVisible { isWindowVisible = true }
        isWindowOccluded = false
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
            Task { [weak self] in await self?.loadRanking() }
        }
    }

    /// 창이 숨었다·최소화됐다. 폴링만 멈춘다 — **판은 계속 흐른다**(D10). 눌린 키는 놓는다(숨은 창은 keyUp 을 못 받는다).
    package func windowDidHide() {
        if isWindowVisible { isWindowVisible = false }
        isWindowOccluded = false
        releaseAllKeys()
        stopPolling()
    }

    /// 창을 **정말 닫았다**(빨간 점 · 로그아웃의 프로그램 닫기). **닫기는 기권이 아니다** — 진행 중 판은 그대로 흐르고
    /// 다시 열면 이어진다. 끝난 판은 여기서 접는다(다음에 창을 열면 결과가 아니라 로비가 선다 — 체스 0.3.50 과 같다).
    package func windowDidClose() {
        releaseAllKeys()
        foldFinishedMatch()
    }

    /// 창의 가림 상태가 바뀌었다. **폴링만** 멈추고 되살린다 — `isWindowVisible` 은 건드리지 않는다.
    package func windowOcclusionDidChange(visible: Bool) {
        isWindowOccluded = !visible
        if visible {
            startPolling()
        } else {
            releaseAllKeys()
            stopPolling()
        }
    }

    // MARK: - 조회

    package func refreshLobby() async {
        guard host?.session != nil, !lobbyInFlight else { return }
        lobbyInFlight = true
        let generation = resetGeneration
        defer { if generation == resetGeneration { lobbyInFlight = false } }
        lastLobbyRequestAt = clock()
        lobbyRequestOutgoingRevision = outgoingRevision
        guard let result = await perform({ try await $0.tetrisLobby(accessToken: $1) }) else { return }
        switch result {
        case .success(let response):
            await applyLobby(response)
        case .failure(let error):
            if isSchemaMissing(error) {
                Self.logger.notice("lobby unavailable — tetris functions missing on server")
                noteServerMissing()
            } else {
                Self.logger.notice("lobby request failed")
            }
            // 빈 목록을 "대결할 사람이 없다" 로 믿게 하지 않는다.
            if !lobbyLoadFailed { lobbyLoadFailed = true }
        }
    }

    package func applyLobby(_ response: TetrisLobbyResponse) async {
        guard response.status == .ok else {
            Self.logger.notice("lobby refused status=\(response.status.rawValue, privacy: .public)")
            switch response.status {
            case .unsupportedClient: noteUpdateRequired()
            case .notSignedIn: setNotice(TetrisDuelNoticeText.signInAgain)
            default: break
            }
            if !lobbyLoadFailed { lobbyLoadFailed = true }
            return
        }
        noteServerNow(response.serverNowMs)
        if availability != .available { availability = .available }
        if lobbyLoadFailed { lobbyLoadFailed = false }
        if !hasLoadedLobby { hasLoadedLobby = true }
        if let rows = response.users {
            let mapped = Self.sortedForLobby(rows.compactMap(Self.user(from:)))
            if users != mapped { users = mapped }
        }
        if let me = response.me {
            applyRuby(me.rubyBalance)
            let fresh = TetrisDuelRecord(wins: me.wins ?? 0, losses: me.losses ?? 0, draws: me.draws ?? 0)
            if record != fresh { record = fresh }
            // ★ 신청을 옮기기 **전에** 적는다 — 보낸 신청이 판으로 이어졌는지(becameMatch)를 이 값으로 가른다.
            activeMatchID = me.activeMatchId?.lowercased()
        }
        // **서버 순서 그대로**. 키가 아예 없으면(옛 서버) 들고 있던 목록을 지우지 않는다.
        if let rows = response.matches {
            let live = rows.compactMap(liveMatch(from:))
            if liveMatches != live { liveMatches = live }
        }
        applyLobbyInvites(response.me)
        if let active = activeMatchID, match?.id != active || match?.isFinished == true {
            await refreshMatch(id: active)
        }
    }

    /// 로비 `me` 의 신청 둘(받은 것 배열 · 보낸 것 하나)을 화면 값으로 옮긴다.
    private func applyLobbyInvites(_ me: TetrisLobbyMe?) {
        // 받은 신청 — 서버 목록이 권위다(서버가 만료·숨김·차단을 이미 걸렀다).
        if let rows = me?.incoming {
            var fresh: [TetrisDuelInvite] = []
            for row in rows {
                guard let invite = invite(from: row, peer: row.from) else { continue }
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

        // 보낸 신청.
        let serverOutgoing = me?.outgoing.flatMap { invite(from: $0, peer: $0.to) }
        // 이 응답은 방금 이 기기가 세운 보낸 신청보다 먼저 나갔다 — 그 신청이 없다고 해도 사실이 아니다.
        let predatesOutgoing = lobbyRequestOutgoingRevision < outgoingRevision
        if let gone = outgoing, serverOutgoing?.id != gone.id, !predatesOutgoing {
            // 판으로 이어졌으면(= 수락) 거절 안내를 하지 않는다 — 진행 중 판이 있으면 서버가 내 다른 신청을 거둔 것이다.
            let becameMatch = gone.id == activeMatchID || gone.id == match?.id
            if !becameMatch {
                setNotice(gone.expiresAt > clock() ? TetrisDuelNoticeText.inviteDeclined
                                                   : TetrisDuelNoticeText.inviteTimedOut)
            }
            outgoing = nil
        }
        // 방금 세운 신청보다 먼저 나간 응답은 **다른** 신청으로 덮지 않는다(그 응답의 보낸 신청은 이미 지나간 것이다).
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

    /// 한 판(또는 신청)의 상태를 읽는다. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다.
    /// 도는 중에 **다른 판** id 가 들어오면 기억했다가 지금 것을 끝낸 뒤 그 판을 한 번 읽는다(막 수락된 판을 놓치지 않게).
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
                let result = await perform({ try await $0.tetrisState(accessToken: $1, matchID: id) })
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

    /// 서버 상태 묶음을 화면 상태로 옮긴다 — **판과 신청을 한 경로로 가르는 유일한 깔때기**다
    /// (보고 응답 · 상태 조회 · 수락 · 기권이 전부 여기로 온다).
    ///
    /// - Parameter receivedAt: 이 응답을 **받은** 단조 시각(판 시작 시각을 단조 시계로 옮기는 기준). nil 이면 지금.
    ///
    /// 늦은 응답 가드 넷(머리말 ④):
    ///  (a) [로비로] 로 접은 끝난 판의 상태는 무시한다.
    ///  (b) 이미 끝남으로 든 판에 진행 중 응답이 오면 무시한다(끝나기 전에 읽힌 옛 스냅숏).
    ///  (c) 같은 판을 진행 중으로 들고 있는데 **내 seq 나 상대 seq 가 들고 있는 값보다 작으면** 옛 스냅숏이다 —
    ///      옮기면 상대 판이 한 박자 전으로 되돌아간다. (끝난 응답은 예외 — 되돌릴 수 없는 사실이다.)
    ///  (d) 모르는 status 는 아무것도 바꾸지 않는다(서버가 어휘를 넓히는 날 진행 중 판을 내려 버리지 않게).
    @discardableResult
    package func applyState(_ payload: TetrisStatePayload, receivedAt: TimeInterval? = nil) -> StateApplyOutcome {
        guard let id = payload.matchId?.lowercased(), !id.isEmpty else { return .ignored }
        noteServerNow(payload.serverNowMs)
        applyRuby(payload.rubyBalance)
        let status = payload.status ?? ""
        switch status {
        case "pending":
            // 신청은 로비가 통째로 준다(상대·판돈·만료). 상태로는 카드를 세우지 않는다 — 들고 있지 않은 신청이면 로비를 다시 읽는다.
            if match?.id == id { return .ignored }       // 진행 중으로 든 판의 옛 스냅숏
            if !incoming.contains(where: { $0.id == id }) && outgoing?.id != id {
                Task { [weak self] in await self?.refreshLobby() }
            }
            return .applied
        case "active", "finished":
            break
        case "declined", "cancelled", "expired":
            dropMatchOrInvite(id, notice: status == "expired" ? TetrisDuelNoticeText.inviteTimedOut
                                                              : TetrisDuelNoticeText.inviteDeclined)
            return .applied
        default:
            Self.logger.notice("state ignored — unknown status=\(status, privacy: .public)")
            return .ignored
        }

        let isFinished = status == "finished"
        if isFinished, dismissedMatchIDs.contains(id), match?.id != id { return .ignored }
        // 다른 판을 **진행 중으로** 들고 있으면 이 응답은 지나간 판의 늦은 것이다(한 사람은 한 판만 — 서버 게이트).
        // 받으면 살아 있는 판 구동기가 버려지고 화면이 옛 판으로 넘어간다(오목이 같은 자리를 막는다).
        if let current = match, current.id != id, !current.isFinished { return .ignored }
        let base = match?.id == id ? match : nil
        if let base, base.isFinished, !isFinished { return .ignored }
        let mySeq = payload.me?.seq ?? 0
        let opponentSeq = payload.opponent?.seq ?? 0
        if base != nil, !isFinished, mySeq < heldMySeq || opponentSeq < heldOpponentSeq {
            return .ignored
        }
        if base == nil {
            // 다른 판으로 넘어간다 — 앞 판의 장부를 비운다.
            heldMySeq = 0
            heldOpponentSeq = 0
            opponentAttackTotal = 0
            opponentLastSeenAt = nil
        }
        heldMySeq = max(heldMySeq, mySeq)
        heldOpponentSeq = max(heldOpponentSeq, opponentSeq)
        opponentAttackTotal = max(opponentAttackTotal, payload.opponent?.garbageSent ?? 0)
        if let seen = deviceDate(serverMs: payload.opponent?.lastSeenMs) { opponentLastSeenAt = seen }

        let myID = host?.session?.userID.lowercased()
        let opponentRow = payload.opponent
        let opponentID = opponentRow?.id?.lowercased() ?? base?.opponent.id ?? ""
        let opponent = peerUser(id: opponentRow?.id, displayName: opponentRow?.displayName,
                                avatarURL: opponentRow?.avatarUrl, character: opponentRow?.character,
                                inMatch: !isFinished)
            ?? base?.opponent
            ?? TetrisDuelUser(id: opponentID, displayName: "", avatarURL: nil, characterID: nil,
                              isWorking: false, isCapable: true, inMatch: !isFinished)
        let winner = payload.winner?.lowercased()
        let outcome: TetrisDuelOutcome?
        if !isFinished {
            outcome = nil
        } else if payload.result == "draw" {
            outcome = .draw
        } else if let winner, let myID, winner == myID {
            outcome = .won
        } else if let winner, !winner.isEmpty {
            outcome = .lost
        } else {
            outcome = nil
        }
        let stake = payload.stake ?? base?.stake ?? 0
        let rubyDelta = outcome.map { result -> Int in
            switch result {
            // 승자 순이익 = 판돈 − 수수료(서버 `duel_fee` 와 같은 식). 무승부 환불엔 수수료가 없다.
            case .won: return DuelFee.winnerNet(stake: stake)
            case .lost: return -stake
            case .draw: return 0
            }
        }
        let next = TetrisDuelMatchState(
            id: id, stake: stake, seed: payload.seed ?? base?.seed, opponent: opponent,
            acceptedAt: deviceDate(serverMs: payload.acceptedAtMs) ?? base?.acceptedAt,
            readyDeadline: deviceDate(serverMs: payload.readyDeadlineMs) ?? base?.readyDeadline,
            // 시작 시각은 한 번 정해지면 사라지지 않는다(옛 응답의 null 이 지우지 못하게).
            startAt: deviceDate(serverMs: payload.startAtMs) ?? base?.startAt,
            maxEnd: deviceDate(serverMs: payload.maxEndMs) ?? base?.maxEnd,
            meReady: (payload.me?.ready ?? false) || (base?.meReady ?? false),
            opponentBoard: Self.opponentBoard(from: opponentRow, previous: base?.opponentBoard),
            isFinished: isFinished, outcome: outcome,
            endReason: payload.endReason.flatMap(TetrisDuelEndReason.init(rawValue:)),
            rubyDelta: rubyDelta,
            finishedAt: deviceDate(serverMs: payload.finishedAtMs) ?? base?.finishedAt)

        // 판 구동기.
        if isFinished {
            if duelMatchID == id {
                duel?.finish()
            } else {
                discardDuel()
            }
            stopGameLoop()
        } else {
            prepareDuel(matchID: id, seed: next.seed, startingSeq: mySeq)
            if duelMatchID == id {
                if let startMs = payload.startAtMs, let serverNow = payload.serverNowMs {
                    duel?.syncStart(startAtMs: startMs, serverNowMs: serverNow, localNow: receivedAt ?? uptime())
                }
                duel?.adoptServerSeq(mySeq)
                duel?.absorbOpponentAttack(total: opponentAttackTotal)
                startGameLoop()
            }
        }

        let justFinished = isFinished && base?.isFinished == false
        let previous = match
        let windowWasVisible = isWindowVisible
        // 이 판이 신청이었으면 카드를 걷는다(수락된 쪽·내가 수락한 쪽 모두).
        if incoming.contains(where: { $0.id == id }) { incoming.removeAll { $0.id == id } }
        if outgoing?.id == id { outgoing = nil }
        if match != next { match = next }
        activeMatchID = isFinished ? nil : id
        refreshPhase()
        syncStats()
        if !isFinished, previous?.id != id || previous?.isFinished == true {
            // 새 판이 열렸다 — 로비에서 남긴 안내("신청을 보냈어요")는 판 상태줄을 가린다.
            setNotice(nil)
            noteMatchStarted(next, windowWasVisible: windowWasVisible)
        }
        if justFinished {
            // 전적은 로비 응답에만 있다. 끝난 순간 한 번 다시 읽어 결과 뒤 로비가 옛 전적을 보이지 않게 한다.
            Task { [weak self] in await self?.refreshLobby() }
            noteOwnMatchFinishedForRanking()
        }
        return .applied
    }

    // MARK: - 동작

    /// 신청. 판돈은 **고른 값을 그대로** 받는다 — 판돈 창은 처음에 아무것도 안 고른 채로 열린다(체스와 같다).
    package func challenge(userID: String, stake: TetrisDuelStake) async {
        guard !isBusy, host?.session != nil else { return }
        let target = userID.lowercased()
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({
            try await $0.tetrisChallenge(accessToken: $1, opponentID: target, stake: stake.rawValue)
        }) else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(TetrisDuelNoticeText.challenge(response.status, need: response.need, have: response.have))
            if response.status != .ok {
                Self.logger.notice("challenge refused status=\(response.status.rawValue, privacy: .public)")
            }
            switch response.status {
            case .ok:
                guard let id = response.matchId?.lowercased() else { break }
                let peer = users.first { $0.id == target }
                    ?? TetrisDuelUser(id: target, displayName: "", avatarURL: nil, characterID: nil,
                                      isWorking: false, isCapable: true, inMatch: false)
                let expiresAt = deviceDate(serverMs: response.expiresAtMs)
                    ?? clock().addingTimeInterval(inviteTTLSeconds)
                outgoingRevision &+= 1
                outgoing = TetrisDuelInvite(id: id, peer: peer, stake: stake.rawValue, expiresAt: expiresAt)
                lastOutgoingRequestAt = clock()
                scheduleInviteExpiry()
            case .unsupportedClient:
                noteUpdateRequired()
            case .alreadyPending, .busy, .targetBusy, .targetOutdated, .targetFocused:
                await refreshLobby()            // 목록의 칩이 틀렸다는 뜻이다 — 다시 읽어 행을 사실에 맞춘다
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
        guard let result = await perform({ try await $0.tetrisCancel(accessToken: $1, matchID: id) }) else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(TetrisDuelNoticeText.cancel(response.status))
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
            try await $0.tetrisRespond(accessToken: $1, matchID: id, accept: accept)
        }) else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            let receivedAt = uptime()
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(TetrisDuelNoticeText.respond(
                accept: accept, response.status, side: response.side, need: response.need, have: response.have))
            if response.status != .ok {
                Self.logger.notice("respond refused status=\(response.status.rawValue, privacy: .public)")
            }
            switch response.status {
            case .ok:
                incoming.removeAll { $0.id == id }
                guard accept else { break }
                // 수락하는 순간 서버가 두 사람의 **다른 테트리스 대기 신청을 전부** 닫는다 — 로컬 카드도 함께 걷는다.
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

    /// 기권(확인은 화면이 받는다). 카운트다운·준비 중에도 된다. 서버가 상대 승 `resign` 으로 정산한다.
    package func resign() async {
        guard !isBusy, let current = match, !current.isFinished, host?.session != nil else { return }
        let id = current.id
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({ try await $0.tetrisResign(accessToken: $1, matchID: id) }) else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            let receivedAt = uptime()
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(TetrisDuelNoticeText.resign(response.status))
            if response.status == .unsupportedClient { noteUpdateRequired() }
            if let state = response.state { applyState(state, receivedAt: receivedAt) } else { await refreshMatch(id: id) }
        }
    }

    /// 결과 화면 [로비로]. **진행 중인 판에서는 아무것도 안 한다** — 빠져나가는 길은 기권뿐이다.
    package func backToLobby() {
        guard foldFinishedMatch(), host?.session != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshLobby()
            await self.loadRanking()
        }
    }

    /// 끝난 판을 내리고 화면을 로비로 돌린다. 끝난 판을 들고 있지 않으면 false — 아무것도 안 바꾼다.
    @discardableResult
    private func foldFinishedMatch() -> Bool {
        guard let current = match, current.isFinished else { return false }
        dismissedMatchIDs.insert(current.id)
        clearMatch()
        setNotice(nil)
        return true
    }

    // MARK: - 신호 · 계기 (창 밖에서 아는 길)

    /// 실시간 'tetris' 초인종. 직렬화된 재조회 — 도는 중이면 뒤따르는 **한 번**으로 합친다.
    package func handleSignal() {
        requestSync()
    }

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
                // 루프 **안에서 먼저** 내린다. 뒤에 내리면 이번 조회가 도는 동안 도착한 신호를 지운다.
                self.syncPendingTrailing = false
                await self.syncOnce()
            } while self.syncPendingTrailing && generation == self.resetGeneration
            if generation == self.resetGeneration { self.syncTask = nil }
        }
    }

    /// 신호 한 번의 조회: 진행 중 판이 있으면 그 판의 상태(상대 공격·시작 시각·정산), 아니면 로비(신청 · 진행 중 판 id).
    package func syncOnce() async {
        if let current = match, !current.isFinished {
            await refreshMatch(id: current.id)
        } else {
            await refreshLobby()
        }
    }

    /// 조인 직후·깨어남의 따라잡기: 로비 한 번(+ 그 응답이 가리키는 판). 진행 중 판만 읽으면 그 사이 온 신청을 모른다.
    package func catchUp() async {
        await refreshLobby()
    }

    /// 실시간 조인 성공 직후(맥 `WorkTimerStoreRealtime` 의 `.catchUp`).
    package func realtimeDidJoin() {
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.catchUp() }
    }

    /// 깨어남(뚜껑을 열었다). 소켓이 끊겼던 사이에 온 신청을 한 번 따라잡는다.
    package func systemDidWake() {
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.catchUp() }
    }

    /// 팝오버 열림(30초 스로틀). 배너·메뉴바 점(`visibleIncoming`)의 신선도가 이 계기와 소켓 신호에 달려 있다.
    package func refreshLobbyIfStale() {
        guard host?.session != nil else { return }
        let now = clock()
        guard now.timeIntervalSince(lastMenuLobbyAt) >= Self.menuLobbyThrottleSeconds else { return }
        lastMenuLobbyAt = now
        Task { [weak self] in await self?.refreshLobby() }
    }

    // MARK: - 폴링 (창이 보일 때만 · 판 밖)

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

    /// 안전망 한 걸음. **창이 안 보이면 아무것도 하지 않는다.**
    ///  · 보낸 신청이 있으면 5초마다 그 판의 상태(수락·거절·만료를 한 조회가 다 말한다)
    ///  · 로비를 보고 있으면 30초마다 목록 · 순위는 60초(주 스위치)
    /// **판 중에는 조회하지 않는다** — 1초 보고가 상대 판과 판 상태를 함께 받아 온다(같은 일을 두 번 하지 않는다).
    package func pollTick(at now: Date) async {
        guard isWindowVisible, !isWindowOccluded, host?.session != nil else { return }
        if let sent = outgoing, now.timeIntervalSince(lastOutgoingRequestAt) >= Self.outgoingPollSeconds {
            await refreshMatch(id: sent.id)
        }
        guard isWindowVisible else { return }
        if phase == .lobby, now.timeIntervalSince(lastLobbyRequestAt) >= Self.lobbyPollSeconds {
            await refreshLobby()
        }
        guard isWindowVisible else { return }
        if rankingEnabled, phase == .lobby, now.timeIntervalSince(lastRankingRequestAt) >= Self.rankingPollSeconds {
            await loadRanking()
        }
    }

    // MARK: - 리셋

    /// 로그아웃·계정 전환. 창을 닫고 상태를 전부 비운다 — 남기면 다음 사람이 앞 사람의 판·신청·루비를 본다.
    /// **배선 값**(`rankingEnabled` · 시계 · 주기 · UI 문)은 건드리지 않는다.
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
        if myStats != nil { myStats = nil }
        if notice != nil { notice = nil }
        if isBusy { isBusy = false }
        if isWindowVisible { isWindowVisible = false }
        if rubyBalance != nil { rubyBalance = nil }
        if !hiddenPeerIDs.isEmpty { hiddenPeerIDs = [] }
        if lobbyLoadFailed { lobbyLoadFailed = false }
        if hasLoadedLobby { hasLoadedLobby = false }
        if !liveMatches.isEmpty { liveMatches = [] }
        if connectionTrouble { connectionTrouble = false }
        if ranking != nil { ranking = nil }
        if rankingLoadFailed { rankingLoadFailed = false }
        if hasLoadedRanking { hasLoadedRanking = false }
        if rankingUnavailable { rankingUnavailable = false }
        serverClockOffset = 0
        hasServerClockOffset = false
        isWindowOccluded = false
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

    /// 서버에 테트리스 RPC 가 아직 없다(PGRST202).
    package nonisolated func isSchemaMissing(_ error: any Error) -> Bool {
        (error as? SupabaseWorkServiceError) == .databaseSchemaMissing
    }

    /// 쓰기 동작이 throw 로 실패했다(5xx·오프라인·PGRST202).
    private func noteActionFailure(_ error: any Error) {
        if isSchemaMissing(error) {
            noteServerMissing()
        } else {
            setNotice(TetrisDuelNoticeText.checkConnection)
        }
    }

    func noteServerMissing() {
        if availability != .serverMissing { availability = .serverMissing }
        setNotice(TetrisDuelNoticeText.unavailable)
    }

    func noteUpdateRequired() {
        if availability != .updateRequired { availability = .updateRequired }
        setNotice(TetrisDuelNoticeText.updateMine)
    }

    /// 로비 신청 행 → 화면 값. 하나라도 모르면 **그 카드를 만들지 않는다**.
    private func invite(from row: TetrisInviteRow, peer peerRow: TetrisPeerRow?) -> TetrisDuelInvite? {
        guard let id = row.matchId?.lowercased(), !id.isEmpty,
              let stake = row.stake,
              let expiresAt = deviceDate(serverMs: row.expiresAtMs),
              let peer = peerUser(id: peerRow?.id, displayName: peerRow?.displayName,
                                  avatarURL: peerRow?.avatarUrl, character: peerRow?.character, inMatch: false)
        else { return nil }
        return TetrisDuelInvite(id: id, peer: peer, stake: stake, expiresAt: expiresAt)
    }

    /// 그 id 가 판이었으면 판을 내리고, 신청이었으면 신청 카드를 걷는다(안내가 있으면 한 줄 — 보낸 신청만).
    private func dropMatchOrInvite(_ id: String, notice: String? = nil) {
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

    /// 같은 신청을 다시 읽었을 때 만료가 문턱 안쪽으로만 다르면 기존 값을 그대로 쓴다(관찰자를 헛되게 깨우지 않게).
    package nonisolated static func steadyInvite(_ fresh: TetrisDuelInvite, previous: TetrisDuelInvite?) -> TetrisDuelInvite {
        guard let previous, previous.id == fresh.id, previous.stake == fresh.stake, previous.peer == fresh.peer,
              abs(previous.expiresAt.timeIntervalSince(fresh.expiresAt)) < inviteExpiryToleranceSeconds
        else { return fresh }
        return previous
    }

    /// 상대 행 → 판 스냅숏. 글자판이 깨졌으면 **들고 있던 판을 그대로** 둔다(깨진 판을 그리지 않는다).
    package nonisolated static func opponentBoard(
        from row: TetrisPlayerRow?, previous: TetrisDuelOpponentBoard?
    ) -> TetrisDuelOpponentBoard {
        let decoded = row?.board.flatMap(TetrisDuelBoard.decode)
        return TetrisDuelOpponentBoard(
            cells: decoded ?? previous?.cells ?? TetrisDuelOpponentBoard.emptyCells,
            hasBoard: decoded != nil || previous?.hasBoard == true,
            lines: row?.lines ?? previous?.lines ?? 0,
            attackSent: max(row?.garbageSent ?? 0, previous?.attackSent ?? 0),
            pending: row?.pending ?? previous?.pending ?? 0,
            toppedOut: (row?.toppedOut ?? false) || (previous?.toppedOut ?? false),
            ready: (row?.ready ?? false) || (previous?.ready ?? false))
    }

    /// 안내줄 한 문.
    package func setNotice(_ text: String?) {
        if notice != text { notice = text }
    }

    /// 판 상태 변화 한 줄(없으면 nil). 판 교체·끝남·시작 시각·준비만 본다 — 상대 판·루비는 이 줄을 만들지 않는다.
    package nonisolated static func matchTransitionLine(
        from old: TetrisDuelMatchState?, to new: TetrisDuelMatchState?
    ) -> String? {
        func finished(_ m: TetrisDuelMatchState?) -> Bool { m?.isFinished ?? false }
        func started(_ m: TetrisDuelMatchState?) -> Bool { m?.startAt != nil }
        func ready(_ m: TetrisDuelMatchState?) -> Bool { m?.meReady ?? false }
        let sameMatch = old?.id == new?.id
        guard !sameMatch || finished(old) != finished(new) || started(old) != started(new)
                || ready(old) != ready(new) else { return nil }
        return "state ready=\(ready(new)) started=\(started(new)) finished=\(finished(new)) "
            + "reason=\(new?.endReason?.rawValue ?? "none") sameMatch=\(sameMatch)"
    }

    func applyRuby(_ value: Int?) {
        guard let value else { return }
        if rubyBalance != value { rubyBalance = value }
        if let host, host.rubyBalance != value { host.rubyBalance = value }
    }

    /// 판을 내린다(판 구동기·판 루프·보고까지).
    package func clearMatch() {
        if match != nil { match = nil }
        discardDuel()
        refreshPhase()
        syncStats()
    }

    /// 진행 중 판으로 **처음** 넘어갔다 — 창을 띄우고 주의를 끈다. 창이 안 보였으면 말풍선 문도 연다(판 id 마다 한 번).
    private func noteMatchStarted(_ next: TetrisDuelMatchState, windowWasVisible: Bool) {
        guard !announcedMatchIDs.contains(next.id) else { return }
        announcedMatchIDs.insert(next.id)
        presentWindow?()
        requestAttention?()
        guard !windowWasVisible else { return }
        onAttention?(TetrisDuelAttention(kind: .matchStarted, matchID: next.id,
                                         opponentName: next.opponent.displayName))
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
            setNotice(TetrisDuelNoticeText.inviteTimedOut)
        }
        scheduleInviteExpiry()
    }

    /// 사람 조각 → 화면 값. 행에 없는 칸은 로비 목록에서 빌린다.
    package func peerUser(id rawID: String?, displayName: String?, avatarURL: String?, character: String?,
                          inMatch: Bool) -> TetrisDuelUser? {
        guard let id = rawID?.lowercased(), !id.isEmpty else { return nil }
        let known = users.first { $0.id == id }
        return TetrisDuelUser(
            id: id,
            displayName: displayName ?? known?.displayName ?? "",
            avatarURL: avatarURL ?? known?.avatarURL,
            characterID: character ?? known?.characterID,
            isWorking: known?.isWorking ?? false,
            isCapable: known?.isCapable ?? true,
            inMatch: inMatch,
            isFocused: known?.isFocused ?? false)
    }

    /// 로비 "지금 대결 중" 한 줄 → 화면 값. 하나라도 모르면 **그 카드를 만들지 않는다**.
    package func liveMatch(from row: TetrisLobbyMatchRow) -> TetrisDuelLiveMatch? {
        guard let id = row.id?.lowercased(), !id.isEmpty,
              let a = peerUser(id: row.a?.id, displayName: row.a?.displayName, avatarURL: row.a?.avatarUrl,
                               character: row.a?.character, inMatch: true),
              let b = peerUser(id: row.b?.id, displayName: row.b?.displayName, avatarURL: row.b?.avatarUrl,
                               character: row.b?.character, inMatch: true),
              // 판돈은 서버 CHECK 가 3·5·10 으로 묶은 값이다. 서버가 그 표를 넓히는 날 이 줄이 먼저 막는다.
              let stake = row.stake.flatMap(TetrisDuelStake.init(rawValue:)),
              let startedAt = deviceDate(serverMs: row.startedAtMs)
        else { return nil }
        return TetrisDuelLiveMatch(id: id, a: a, b: b, stake: stake, startedAt: startedAt)
    }

    /// 서버 사람 행 → 화면 값(로비). `capable` 이 nil 이면 **불가**다.
    package nonisolated static func user(from row: TetrisUserRow) -> TetrisDuelUser? {
        guard let id = row.id?.lowercased(), !id.isEmpty else { return nil }
        return TetrisDuelUser(
            id: id,
            displayName: row.displayName ?? "",
            avatarURL: row.avatarUrl,
            characterID: row.character,
            isWorking: row.isWorking ?? false,
            isCapable: row.capable ?? false,
            inMatch: row.inMatch ?? false,
            isFocused: row.focusMode ?? false)
    }

    /// 로비 정렬: 도전할 수 있는 근무자 → 근무 중·가능(대결 중) → 근무 중 → 나머지, 그 안은 이름순.
    /// **서버 정렬과 같은 규칙**이라 재정렬이 아니라 되맞춤이다(서버는 working desc → capable desc → 이름 → id).
    package nonisolated static func sortedForLobby(_ users: [TetrisDuelUser]) -> [TetrisDuelUser] {
        func rank(_ user: TetrisDuelUser) -> Int {
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
