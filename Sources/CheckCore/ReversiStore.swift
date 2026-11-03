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
//     `visibleIncomingInvites` 는 `match?.id` 와 같은 id 를 뺀다(수락 전에 나간 로비 응답이 수락 뒤에 와서 되살리는 것 방지) ·
//     같은 id 를 판으로 든 동안 온 신청 단계 응답(pending·declined·cancelled·expired) 무시 · `writeRevision`(쓰기 응답보다 먼저
//     나간 로비는 잔액·진행 판 id 를 덮지 않는다) · 로비 조회 합치기(`lobbyAgain` — 도는 중에 온 초인종은 끝난 뒤 한 번 더).
//  ⑤ **사용자 문구는 `ReversiNoticeText` 한 곳**(진단 어휘 금지).
//  ⑥ **초 단위 값은 잎 뷰만** 읽는다(`remainingSeconds(now:)` 는 순수 계산 — 스토어는 매초 대입하지 않는다).
//  ⑦ **합법 수는 서버 `legal_moves` 로만**(내 차례일 때만 온다, DEC:26). **AI 판은 로컬 규칙**이 권위다.
//  ⑧ 입력은 한 단(칸 하나)이다 — 체스의 선택 2단이 없다.
//  ⑨ **시계는 서버 응답마다 통째로 덮는다**(마감 하나, 표시값 30초 — 서버 유예 2초 미포함).
//  ⑩ 오목의 **자동 착수 장치**가 있다(30초 넘기면 서버가 합법 수 중 무작위로 둔다 · `myAutoStreak` · 연속 3이면 패 ·
//     자동 패스는 시계·연속 횟수에 안 센다). 체스(⑩ 없음)와 다르다.
//  ⑪ **받은 신청은 로비 `me.incoming` 이 통째로 준다**(테트리스식 — 갈아 끼운다). 보낸 신청만 state 로 따로 본다(③).
//
// 표면(칸·계산 칸·함수 서명)은 C1 이 세웠고 몸통은 C2 가 채웠다 — 표면을 바꾸지 말고 몸통만 고친다.
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
    // MARK: 주기 상수

    /// 상대 차례 상태 조회 주기(초) — 실시간 구독 중 + 마감이 가깝거나(10초 안) 마감을 모를 때. 오목과 같은 눈금이다.
    package nonisolated static let statePollSecondsNearDeadline: TimeInterval = 3
    /// 같은 조회 — 구독 중 + 마감까지 여유가 있을 때. 수는 초인종으로 바로 오고 이 조회는 신호를 놓쳤을 때의 그물이다.
    package nonisolated static let statePollSecondsCalm: TimeInterval = 10
    /// 남은 시간이 이 안으로 들어오면 `statePollSecondsNearDeadline` 로 돌아간다(시간 초과 자동 착수를 빨리 본다).
    package nonisolated static let statePollNearDeadlineSeconds: TimeInterval = 10
    /// 같은 조회 — 미구독(킬스위치·재연결 중). 신호가 없으니 더 촘촘하다.
    package nonisolated static let statePollSecondsUnsubscribed: TimeInterval = 1.5
    /// 보낸 신청이 떠 있을 때 그 판의 상태를 보는 주기(초). **조회 하나가 수락·거절·만료를 다 알려 준다** —
    /// 수락 순간 흑 시계가 돌므로 초인종을 놓친 신청자가 로비 30초 주기로만 알면 첫 수가 자동 착수가 된다.
    package nonisolated static let outgoingPollSeconds: TimeInterval = 5
    /// 로비 목록 재조회 주기(초).
    package nonisolated static let lobbyPollSeconds: TimeInterval = 30
    /// 팝오버를 열 때 로비를 다시 읽는 스로틀(초). 신청 TTL(60초)보다 짧다.
    package nonisolated static let menuLobbyThrottleSeconds: TimeInterval = 30
    /// 관전 중 판 재조회 주기(초).
    package nonisolated static let watchPollSeconds: TimeInterval = 2
    /// 로비를 보고 있는 동안 순위표 재조회 주기(초).
    package nonisolated static let rankingPollSeconds: TimeInterval = 60
    /// 창 열기와 창 표시가 같은 조회를 두 번 쏘지 않게 하는 간격(초).
    package nonisolated static let reloadDedupeSeconds: TimeInterval = 1
    /// 서버 시계 오프셋을 다시 재는 문턱(초).
    package nonisolated static let serverClockToleranceSeconds: TimeInterval = 0.25
    /// 같은 신청을 다시 읽었을 때 만료가 이만큼 안쪽으로만 다르면 기존 값을 쓴다(초).
    package nonisolated static let inviteExpiryToleranceSeconds: TimeInterval = 1
    /// throw 실패(5xx·오프라인)가 이만큼 연속되면 관전을 내리고 연결 안내를 남긴다.
    package nonisolated static let watchFailureLimit = 3

    /// 지금 상대 차례 상태를 물을 주기. 미구독은 언제나 촘촘하고, 구독 중에는 마감이 멀 때만 늦춘다(오목 규칙 그대로).
    package nonisolated static func statePollSeconds(subscribed: Bool, deadline: Date?, now: Date) -> TimeInterval {
        guard subscribed else { return statePollSecondsUnsubscribed }
        guard let deadline, deadline.timeIntervalSince(now) > statePollNearDeadlineSeconds else {
            return statePollSecondsNearDeadline
        }
        return statePollSecondsCalm
    }

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
    package internal(set) var match: ReversiMatchState? {
        didSet {
            if let line = Self.matchTransitionLine(from: oldValue, to: match) {
                Self.logger.notice("\(line, privacy: .public)")
            }
            // 1:1 판이 끝난 것을 **처음 본** 순간 한 번(같은 판을 다시 받아도 또 안 부른다). AI 판은 부르지 않는다.
            if Self.matchJustFinished(from: oldValue, to: match), match?.isAI == false { onMatchFinished?() }
            // AI 판은 `match` 가 그 id 를 들고 있는 동안만 산다 — 1:1 판이 열리거나 판이 내려가면 버린다(1:1 이 이긴다).
            if let game = aiGame, match?.id != game.id { discardAIGame() }
            // 내 판이 섰으면(끝난 판 포함) 관전은 내려간다. 세대를 올려 나가 있던 관전 응답도 함께 버린다.
            if match != nil, spectating != nil {
                spectating = nil
                watchRuntime.bumpWatchGeneration()
            }
            // 판이 내려갔다 — 남의 관전자 수가 로비 화면에 남지 않게 0 으로 돌린다.
            if match == nil, spectatorCount != 0 { spectatorCount = 0 }
            // 다른 판의 뒤집기 그림은 새 판 위에 남기지 않는다.
            if let current = flip, current.matchID != match?.id { clearFlip() }
        }
    }
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
    /// 내 판 관전자 수(관전 중이면 보는 판의 수 — 둘은 동시에 서지 않는다).
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

    // MARK: 내부 장부 (관찰 대상 아님)

    /// 폴링 루프의 한 걸음(초). 주기 판정은 `pollTick` 이 하고 이 값은 그 판정을 얼마나 자주 묻는지다(시험은 재운다).
    @ObservationIgnored package var pollStepSeconds: TimeInterval = 0.5
    /// 서버 시계 − 기기 시계(초).
    @ObservationIgnored package private(set) var serverClockOffset: TimeInterval = 0
    @ObservationIgnored private var hasServerClockOffset = false
    @ObservationIgnored package private(set) var resetGeneration = 0
    /// 창이 다른 창에 완전히 가려졌거나 다른 Space·잠금 화면에 있다. **폴링·AI 시계만** 이 값을 본다.
    @ObservationIgnored package private(set) var isWindowOccluded = false
    @ObservationIgnored package private(set) var stateInFlightID: String?
    @ObservationIgnored private var pendingStateID: String?
    @ObservationIgnored private var stateInFlight = false
    @ObservationIgnored private var stateAgain = false
    @ObservationIgnored private var lobbyInFlight = false
    /// 로비 조회가 도는 중에 또 불렸다 — 끝난 뒤 **한 번 더** 읽는다(큐브 `RummyStoreLobby` 꼴). 앞 조회는 그 뒤에 생긴 신청·수락을
    /// 모르므로, 그 사이 온 초인종을 버리면 받은 신청·수락 소식이 다음 계기(30초 폴링·팝오버)까지 안 선다.
    @ObservationIgnored private var lobbyAgain = false
    /// 마지막으로 "내 차례가 왔다" 를 본 (판 id#move_count). 같은 차례에 말풍선이 두 번 뜨지 않게 한다.
    @ObservationIgnored private var attentionKey: String?
    /// 서버가 말한 내 진행 중 대국 id(로비 `me.active_match_id`).
    @ObservationIgnored package internal(set) var activeMatchID: String?
    @ObservationIgnored package private(set) var seenInviteIDs: Set<String> = []
    /// 이 기기에서 이미 답한 받은 신청(수락·거절·끝남). 답보다 먼저 나간 로비 응답이 늦게 와도 되살리지 않는다.
    @ObservationIgnored package private(set) var answeredInviteIDs: Set<String> = []
    /// [로비로] 로 접은 끝난 판. 늦게 온 그 판의 상태가 사용자를 결과 화면으로 끌고 가지 않게 한다.
    @ObservationIgnored package private(set) var dismissedMatchIDs: Set<String> = []
    @ObservationIgnored package private(set) var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pollToken = 0
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored package var lastStateRequestAt: Date = .distantPast
    @ObservationIgnored package var lastLobbyRequestAt: Date = .distantPast
    @ObservationIgnored package var lastOutgoingRequestAt: Date = .distantPast
    /// 팝오버 열기 계기의 마지막 조회 시각(스로틀).
    @ObservationIgnored package var lastMenuLobbyAt: Date = .distantPast
    /// 신호 재조회 직렬화(도는 중이면 뒤따르는 한 번으로 합친다).
    @ObservationIgnored package private(set) var syncTask: Task<Void, Never>?
    @ObservationIgnored private var syncPendingTrailing = false
    /// 이 기기에서 보낸 신청을 새로 세울 때마다 오른다. 그보다 **먼저** 나간 로비 응답이 방금 보낸 신청을 지우지 않게 한다.
    @ObservationIgnored package private(set) var outgoingRevision = 0
    @ObservationIgnored private var lobbyRequestOutgoingRevision = 0
    /// 쓰기 RPC(신청·취소·응답·착수·기권) 응답을 받을 때마다 오른다. 그보다 **먼저** 나간 로비 응답은 잔액·진행 판 id 를 덮지 않는다 —
    /// 로비는 읽기 전용이라 쓰기 전 스냅숏일 수 있고, 무거워서 쓰기 응답보다 늦게 온다(판돈이 빠진 95 가 100 으로 돌아가는 것 방지).
    @ObservationIgnored package private(set) var writeRevision = 0
    /// 서버가 말한 숫자(로비 응답이 덮는다 — 상수를 베끼지 않는다).
    @ObservationIgnored package private(set) var inviteTTLSeconds: TimeInterval = 60
    @ObservationIgnored package private(set) var turnSeconds = 30
    @ObservationIgnored package private(set) var graceMs = 2_000
    @ObservationIgnored package private(set) var autoAbandonStreak = 3
    /// 지금 서 있는 패스 안내(다음 수가 오면 걷는다 — 그 밖의 안내는 건드리지 않는다).
    @ObservationIgnored private var passNotice: String?
    @ObservationIgnored private var flipToken = 0
    @ObservationIgnored private var flipTask: Task<Void, Never>?
    /// 지금 AI 대국(로컬 판이 권위 — ReversiStoreAI.swift). `match` 가 이 id 를 들고 있는 동안만 산다.
    @ObservationIgnored package internal(set) var aiGame: ReversiAIGame?
    /// AI 갈래 장부(선택기·작업·세대).
    @ObservationIgnored package let aiRuntime = ReversiAIRuntime()
    /// 관전·순위 장부(요청 시각·in-flight·세대).
    @ObservationIgnored package let watchRuntime = ReversiWatchRuntime()

    /// 서버가 말해 준 유예(초).
    package var graceSeconds: TimeInterval { max(0, Double(graceMs) / 1000) }

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
                if let focus, !focus.isEmpty, focus != self.match?.id {
                    await self.refreshMatch(id: focus)
                } else if let current = self.match, !current.isFinished, !current.isAI {
                    await self.refreshMatch(id: current.id)
                }
            }
        }
        presentWindow?()
    }

    /// 창이 실제로 보이기 시작했다. 폴링 시작 · 로비 재조회 · AI 시계 재개.
    package func windowDidShow() {
        if !isWindowVisible { isWindowVisible = true }
        // 막 앞으로 올라온 창이다 — 숨기기 전의 가림 기록이 남아 폴링을 영영 막지 않게 지운다.
        isWindowOccluded = false
        resumeAIClockIfVisible()
        startPolling()
        guard host?.session != nil else { return }
        let now = clock()
        if now.timeIntervalSince(lastLobbyRequestAt) >= Self.reloadDedupeSeconds {
            Task { [weak self] in await self?.refreshLobby() }
        }
        if let current = match, !current.isFinished, !current.isAI,
           now.timeIntervalSince(lastStateRequestAt) >= Self.reloadDedupeSeconds {
            // 창이 안 보이는 동안 시계는 서버에서 흘렀다 — 올라온 순간 한 번 당겨 마감을 새로 받는다(⑨).
            Task { [weak self] in await self?.refreshMatch(id: current.id) }
        }
        spectatorWindowDidShow(at: now)
    }

    /// 창이 가려졌다·닫혔다·최소화됐다. 폴링만 멈춘다 — **1:1 대국은 계속된다**(시간은 서버에서 흐른다).
    /// AI 판은 사람 시계를 멈춘다(기다리는 상대가 없다).
    package func windowDidHide() {
        if isWindowVisible { isWindowVisible = false }
        isWindowOccluded = false
        clearFlip()
        stopPolling()
        pauseAIClock()
        // 끝난 판을 관전한 채 닫았다 = 그 판에서 나간 것이다. 진행 중인 관전은 남긴다(최소화에서도 오는 통지다).
        if spectating?.isFinished == true { stopWatching() }
    }

    /// 창을 **정말 닫았다**. 관전을 내리고 끝난 내 판을 접는다(다음에 창을 열면 로비가 선다).
    /// 진행 중인 판은 건드리지 않는다 — 닫기는 기권이 아니다.
    package func windowDidClose() {
        if spectating != nil { stopWatching() }
        clearFlip()
        foldFinishedMatch()
    }

    /// 창의 가림 상태가 바뀌었다. **폴링·AI 시계만** 멈추고 되살린다 — `isWindowVisible` 은 건드리지 않는다.
    package func windowOcclusionDidChange(visible: Bool) {
        isWindowOccluded = !visible
        if visible {
            resumeAIClockIfVisible()
            startPolling()
        } else {
            clearFlip()
            pauseAIClock()
            stopPolling()
        }
    }

    // MARK: - 조회

    /// 로비를 읽는다. 도는 중에 또 불리면 끝난 뒤 **한 번 더** 읽는다(`lobbyAgain` — `refreshMatch` 의 `stateAgain` 과 같은 꼴).
    /// 합친 한 바퀴에는 진행 판 꼬리(`refreshMatch(active)`)까지 들어간다 — 꼬리가 도는 동안 온 초인종도 뒤따르는 한 번으로 간다.
    package func refreshLobby() async {
        guard host?.session != nil else { return }
        if lobbyInFlight {
            lobbyAgain = true
            return
        }
        lobbyInFlight = true
        let generation = resetGeneration
        defer { if generation == resetGeneration { lobbyInFlight = false } }
        repeat {
            lobbyAgain = false
            lastLobbyRequestAt = clock()
            let revision = outgoingRevision
            let writes = writeRevision
            guard let result = await perform({ try await $0.reversiLobby(accessToken: $1) }) else { return }
            switch result {
            case .success(let response):
                lobbyRequestOutgoingRevision = revision
                applyLobby(response, predatesWrite: writes != writeRevision)
                // 서버가 진행 중이라 말하는 판을 들고 있지 않다(다른 기기에서 수락 · 재시작) — 그 판을 읽어 세운다.
                // 쓰기보다 먼저 나간 응답이라 `activeMatchID` 를 안 덮었어도, 그 순간 판이 서 있었다는 사실은 쓴다(적대 재검증 VR-01).
                if response.status == .ok, let active = activeMatchID ?? response.me?.activeMatchId?.lowercased(),
                   match?.id != active || match?.isFinished == true {
                    await refreshMatch(id: active)
                }
            case .failure(let error):
                if isSchemaMissing(error) {
                    Self.logger.notice("lobby unavailable — reversi functions missing on server")
                    noteServerMissing()
                } else {
                    Self.logger.notice("lobby request failed")
                }
            }
        } while lobbyAgain && generation == resetGeneration
    }

    /// 로비 응답을 화면 상태로 옮긴다(받은 신청은 통째로 갈아 끼운다).
    package func applyLobby(_ response: ReversiLobbyResponse) {
        applyLobby(response, predatesWrite: false)
    }

    /// `predatesWrite` — 이 응답은 그 뒤에 받은 쓰기 응답보다 **먼저** 나갔다(`writeRevision`). 잔액·진행 판 id 는 쓰기 응답이 더 새 사실이라
    /// 덮지 않는다. 나머지(사람·대결 중·신청)는 그대로 옮긴다 — 신청은 `answeredInviteIDs`·`outgoingRevision` 이 따로 지킨다.
    private func applyLobby(_ response: ReversiLobbyResponse, predatesWrite: Bool) {
        guard response.status == .ok else {
            Self.logger.notice("lobby refused status=\(response.status.rawValue, privacy: .public)")
            switch response.status {
            case .unsupportedClient: noteUpdateRequired()
            case .unauthorized: setNotice(ReversiNoticeText.signInAgain)
            default: break
            }
            return
        }
        noteServerNow(response.serverNowMs)
        if availability != .available { availability = .available }
        if let value = response.turnSeconds, value > 0 { turnSeconds = value }
        if let value = response.turnGraceSeconds, value >= 0 { graceMs = value * 1000 }
        if let value = response.inviteTtlSeconds, value > 0 { inviteTTLSeconds = TimeInterval(value) }
        if let value = response.autoAbandonStreak, value > 0 { autoAbandonStreak = value }
        if let me = response.me {
            if !predatesWrite { applyRuby(me.rubyBalance) }
            let fresh = ReversiRecord(wins: me.wins ?? 0, losses: me.losses ?? 0, draws: me.draws ?? 0)
            if record != fresh { record = fresh }
            // ★ 신청을 옮기기 **전에** 적는다 — 보낸 신청이 판으로 이어졌는지(becameMatch)를 이 값으로 가른다.
            if !predatesWrite { activeMatchID = me.activeMatchId?.lowercased() }
        }
        if let rows = response.users {
            let mapped = Self.sortedForLobby(rows.compactMap(Self.user(from:)))
            if users != mapped { users = mapped }
        }
        // **서버 순서 그대로**. 키가 아예 없으면(옛 서버) 들고 있던 목록을 지우지 않는다.
        if let rows = response.matches {
            let live = rows.compactMap(liveMatch(from:))
            if liveMatches != live { liveMatches = live }
        }
        applyLobbyInvites(response.me)
    }

    /// 로비 `me` 의 신청 둘(받은 것 배열 · 보낸 것 하나)을 화면 값으로 옮긴다.
    private func applyLobbyInvites(_ me: ReversiLobbyMe?) {
        // 이 응답이 읽힌 순간 서 있던 진행 판 — `predatesWrite` 라 `activeMatchID` 에 안 옮겼어도 "보낸 신청이 판이 됐다"는 판정엔 쓴다(VR-01).
        let respondedActive = me?.activeMatchId?.lowercased()
        // 받은 신청 — 서버 목록이 권위다(서버가 만료·숨김·차단을 이미 걸렀다). 이 기기가 이미 답한 신청만 뺀다.
        if let rows = me?.incoming {
            var fresh: [ReversiInvite] = []
            for row in rows {
                guard let invite = invite(from: row, peer: row.from),
                      !answeredInviteIDs.contains(invite.id),
                      !fresh.contains(where: { $0.id == invite.id }) else { continue }
                fresh.append(Self.steadyInvite(invite, previous: incoming.first { $0.id == invite.id }))
            }
            if incoming != fresh { incoming = fresh }
            for invite in fresh where !seenInviteIDs.contains(invite.id) && invite.id != match?.id {
                seenInviteIDs.insert(invite.id)
                guard !hiddenPeerIDs.contains(invite.peer.id) else { continue }
                onInviteArrived?(invite)
            }
        } else if me != nil, !incoming.isEmpty {
            incoming = []
        }

        // 보낸 신청.
        let serverOutgoing: ReversiOutgoing? = me?.outgoing.flatMap { row in
            invite(from: row, peer: row.to).map {
                ReversiOutgoing(id: $0.id, peer: $0.peer, stake: $0.stake, expiresAt: $0.expiresAt)
            }
        }
        // 이 응답은 방금 이 기기가 세운 보낸 신청보다 먼저 나갔다 — 그 신청이 없다고 해도 사실이 아니다.
        let predatesOutgoing = lobbyRequestOutgoingRevision < outgoingRevision
        if let gone = outgoing, serverOutgoing?.id != gone.id, !predatesOutgoing {
            // 판으로 이어졌으면(= 수락) 거절 안내를 하지 않는다 — 진행 중 판이 있으면 서버가 내 다른 신청을 거둔 것이다.
            let becameMatch = gone.id == activeMatchID || gone.id == match?.id || gone.id == respondedActive
            if !becameMatch {
                setNotice(gone.expiresAt > clock() ? ReversiNoticeText.inviteDeclined : ReversiNoticeText.inviteTimedOut)
            }
            outgoing = nil
        }
        // 방금 세운 신청보다 먼저 나간 응답은 **다른** 신청으로 덮지 않는다.
        if let serverOutgoing, serverOutgoing.id != match?.id,
           !predatesOutgoing || outgoing == nil || outgoing?.id == serverOutgoing.id {
            let steady = Self.steadyOutgoing(serverOutgoing, previous: outgoing)
            if outgoing != steady { outgoing = steady }
        }
        scheduleInviteExpiry()
    }

    package func refreshMatch() async {
        await refreshMatch(id: match?.id ?? activeMatchID)
    }

    /// 한 판(또는 신청)의 상태를 읽는다. 같은 판을 들고 있으면 `p_since_seq` 로 **새 수만** 받고,
    /// 수 번호가 이어지지 않으면 처음부터 한 번 더 받는다. 도는 중에 또 불리면 뒤따르는 한 번으로 합치고,
    /// **다른 판** id 는 기억했다가 지금 판이 끝난 뒤 한 번 읽는다(합치면 막 수락된 판이 다음 계기까지 안 온다).
    package func refreshMatch(id rawID: String?) async {
        // AI 판 id 는 서버에 없다 — 어느 경로로 와도 **여기서** 막는다(열기·로비·폴링·신호가 전부 이 문을 지난다).
        guard let requested = rawID?.lowercased(), !requested.isEmpty,
              !ReversiAIGame.isAIMatchID(requested), host?.session != nil else { return }
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
            var forceFull = false
            repeat {
                stateAgain = false
                let since = (!forceFull && match?.id == id) ? (match?.moveCount ?? 0) : 0
                forceFull = false
                lastStateRequestAt = clock()
                if outgoing?.id == id { lastOutgoingRequestAt = lastStateRequestAt }
                let result = await perform({
                    try await $0.reversiState(accessToken: $1, matchID: id, sinceSeq: since)
                })
                guard generation == resetGeneration else { return }
                switch result {
                case .success(let response)?:
                    switch response.status {
                    case .ok:
                        if let state = response.state,
                           applyState(state, requestedSince: since) == .needsFull, since > 0 {
                            forceFull = true
                            stateAgain = true
                        }
                    case .notFound:
                        dropMatchOrInvite(id)
                    case .unsupportedClient:
                        noteUpdateRequired()
                    case .unauthorized:
                        setNotice(ReversiNoticeText.signInAgain)
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

    // MARK: 픽스처 문 — U·T 시험은 S 픽스처 원문을 이 두 문으로 넣는다

    package enum StateApplyOutcome: Equatable { case applied, needsFull, ignored }

    /// 서버 state 를 화면 상태로 옮긴다. **대국과 신청을 한 경로로 가른다**: `pending` 은 신청, `active`/`finished` 는 판,
    /// 그 밖(declined·cancelled·expired)은 둘 다 아니다. 관전 모양(내 색 없음)은 무시한다 — 관전은 `applyWatch` 하나다.
    ///
    /// 쓰기 RPC 응답(state 전체)은 `requestedSince: 0` 으로 다시 짓고, 아니면 seq 로 이어 붙이며 틈이 보이면 `.needsFull`.
    /// 판 자체는 서버 64자 문자열이 권위라 기록에 구멍이 나도 판은 맞다 — 구멍 난 기록을 그리지 않을 뿐이다.
    @discardableResult
    package func applyState(_ payload: ReversiStatePayload, requestedSince: Int = 0) -> StateApplyOutcome {
        guard let row = payload.match, let id = row.id?.lowercased(), !id.isEmpty else { return .ignored }
        let status = row.matchStatus
        switch status {
        case .pending, .declined, .cancelled, .expired:
            // ④ 같은 id 를 판(진행·끝남)으로 들고 있거나 접었다 — 신청 단계의 응답은 그 판보다 먼저 읽힌 옛 스냅숏이다
            //    (판은 신청으로 돌아가지 않는다). 판을 지우지도, 잔액을 되돌리지도 않는다 — 잔액은 이 가드를 지난 응답만 옮긴다.
            if match?.id == id || dismissedMatchIDs.contains(id) { return .ignored }
        case .active, .finished, .unknown:
            break
        }
        switch status {
        case .pending:
            noteServerNow(payload.serverNowMs)
            applyRuby(payload.rubyBalance)
            applyInvite(row, payload: payload, id: id)
            return .applied
        case .active, .finished:
            break
        case .declined, .cancelled, .expired:
            noteServerNow(payload.serverNowMs)
            applyRuby(payload.rubyBalance)
            // 시작하지 못하고 끝난 신청 — 판도 아니고 살아 있는 신청도 아니다.
            dropMatchOrInvite(id, notice: status == .expired ? ReversiNoticeText.inviteTimedOut
                                                             : ReversiNoticeText.inviteDeclined)
            return .applied
        case .unknown:
            Self.logger.notice("state with unknown status ignored")
            return .ignored
        }

        let isFinished = status == .finished
        // ④ 접은 끝난 판 — 늦게 온 그 판의 상태가 결과 화면을 되살리지 않는다.
        if isFinished, dismissedMatchIDs.contains(id), match?.id != id { return .ignored }
        // ④ 다른 판을 두는 중인데 끝난 판 응답이 왔다 — 지난 판의 늦은 응답이다(두던 판을 지우지 않는다).
        if isFinished, let current = match, current.id != id, !current.isFinished { return .ignored }

        // 관전 모양(내 색 없음)은 대국 화면으로 옮기지 않는다. 참가자 state 는 active·finished 에서 늘 `my_color` 를 싣는다 —
        // 흑·백 uuid 로 내 색을 지어내지 않는다(내가 낀 판을 관전 응답으로 받아도 대국이 서면 안 된다).
        guard let myColor = payload.myColor else { return .ignored }

        let base = match?.id == id ? match : nil
        let serverCount = row.moveCount
        // ④ 같은 판을 진행 중으로 들고 있는데 **수 번호가 줄어든** 응답은 착수보다 먼저 읽힌 옛 스냅숏이다.
        if let base, !base.isFinished, !isFinished, let serverCount, serverCount < base.moveCount { return .ignored }
        // ④ 같은 판을 이미 끝남으로 들고 있으면 진행 중 응답은 전부 끝나기 전에 읽힌 옛 스냅숏이다.
        if let base, base.isFinished, !isFinished { return .ignored }

        let records = (payload.moves ?? []).filter { $0.seq >= 1 }.sorted { $0.seq < $1.seq }
        var merged = base?.plies ?? []
        var applied = base?.moveCount ?? 0
        let rebuild = base == nil || records.first?.seq == 1 || requestedSince == 0
        if rebuild {
            merged = []
            applied = 0
        }
        for record in records where record.seq > applied {
            if record.seq != applied + 1, !rebuild { return .needsFull }
            merged.append(record)
            applied = record.seq
        }
        let moveCount = serverCount ?? applied
        if moveCount != applied, !rebuild { return .needsFull }

        noteServerNow(payload.serverNowMs)
        applyRuby(payload.rubyBalance)

        let board = row.board ?? base?.board ?? .start
        let turn = isFinished ? nil : row.turn
        let turnStartedAt = deviceDate(serverMs: row.turnStartedMs)
        let deadline = isFinished ? nil
            : (deviceDate(serverMs: row.deadlineMs) ?? turnStartedAt?.addingTimeInterval(TimeInterval(turnSeconds)))
        // **서버가 준 것만** 쓴다(⑦). 상대 차례·끝난 판은 [] 라 착수가 전부 막힌다.
        let legal = (isFinished || turn != myColor) ? []
            : Array(Set((payload.legalMoves ?? []).filter { (0..<64).contains($0) })).sorted()
        let blackID = row.black?.lowercased()
        let whiteID = row.white?.lowercased()
        let opponentID = myColor == .black ? whiteID : blackID
        let opponent = playerUser(payload.opponent, inMatch: !isFinished)
            ?? base?.opponent
            ?? users.first { $0.id == opponentID }
            ?? ReversiUser(id: opponentID ?? "", displayName: "", inMatch: !isFinished)
        let blackUser = playerUser(payload.blackUser, inMatch: !isFinished) ?? base?.blackUser
        let whiteUser = playerUser(payload.whiteUser, inMatch: !isFinished) ?? base?.whiteUser
        let result = row.result
        var winner: ReversiColor? = result?.winner
        if winner == nil, let winnerID = row.winner?.lowercased() {
            winner = winnerID == blackID ? .black : (winnerID == whiteID ? .white : nil)
        }
        let score: ReversiScore? = {
            guard let row = row.score, let black = row.black, let white = row.white, let result else { return nil }
            return ReversiScore(black: black, white: white, result: result)
        }()
        let myStreak = payload.myAutoStreak
            ?? (myColor == .black ? payload.blackAutoStreak : payload.whiteAutoStreak) ?? 0
        let opponentStreak = payload.opponentAutoStreak
            ?? (myColor == .black ? payload.whiteAutoStreak : payload.blackAutoStreak) ?? 0

        let next = ReversiMatchState(
            id: id, isAI: false, status: status, stake: row.stake ?? base?.stake ?? 0, myColor: myColor,
            opponent: opponent, blackUser: blackUser, whiteUser: whiteUser, board: board, moveCount: moveCount,
            turn: turn, turnStartedAt: turnStartedAt, deadline: deadline, legalMoves: legal, plies: merged,
            lastStoneIdx: merged.last(where: { $0.kind == .stone })?.idx,
            autoStones: Set(merged.compactMap { $0.kind == .stone && $0.auto ? $0.idx : nil }),
            counts: row.discs ?? board.counts, score: score, result: isFinished ? result : nil,
            endReason: isFinished ? row.endReason : nil, winner: isFinished ? winner : nil,
            myAutoStreak: myStreak, opponentAutoStreak: opponentStreak,
            autoAbandonStreak: payload.autoAbandonStreak ?? autoAbandonStreak,
            watchers: max(0, payload.watchers ?? 0))

        let justFinished = isFinished && base?.isFinished == false
        let previous = match
        // 말풍선 문은 **보이고 안 가려진** 창만 닫는다 — 열린 채 가려진 창(다른 전체 화면 앱·다른 스페이스)은 화면이 말하지 못하고
        // 폴링도 멈춰 있어, 초인종이 세운 내 차례를 알릴 길이 말풍선뿐이다(30초 자동 착수 · 세 번이면 패). 시계 잎 뷰·AI 시계는 그대로.
        let windowWasVisible = isWindowVisible && !isWindowOccluded
        // 이 판이 신청이었으면 카드를 걷는다(수락된 쪽·내가 수락한 쪽 모두).
        if incoming.contains(where: { $0.id == id }) {
            incoming.removeAll { $0.id == id }
            scheduleInviteExpiry()
        }
        if outgoing?.id == id {
            outgoing = nil
            scheduleInviteExpiry()
        }
        if match != next { match = next }
        // 내 판 관전자 수 — **`match` 대입 뒤**에 세운다(그 didSet 이 판이 바뀌는 길목에서 0 으로 되돌린다).
        if spectatorCount != next.watchers { spectatorCount = next.watchers }
        noteBoardProgress(previous: previous, next: next)
        let nextPhase: ReversiPhase = isFinished ? .result : .playing
        if phase != nextPhase { phase = nextPhase }
        activeMatchID = isFinished ? nil : id
        if !isFinished {
            // 새 판이 열렸다 — 로비에서 남긴 안내("신청을 보냈어요")가 대국 상태줄을 가리지 않게 한다.
            if previous?.id != id || previous?.isFinished == true { setNotice(nil) }
            noteMatchProgress(previous: previous, next: next, windowWasVisible: windowWasVisible)
        }
        if justFinished {
            // 전적은 로비 응답에만 있다. 끝난 순간 한 번 다시 읽어 결과 화면 뒤 로비가 옛 전적을 보이지 않게 한다.
            Task { [weak self] in await self?.refreshLobby() }
            noteOwnMatchFinishedForRanking()
        }
        return .applied
    }

    // MARK: - 동작

    /// `selectedStake` 로 신청한다. 서버는 근무 조건이 없다 — 근무를 보고 미리 막지 않는다.
    package func challenge(userID: String) async {
        guard !isBusy, host?.session != nil else { return }
        let target = userID.lowercased()
        let stake = selectedStake.rawValue
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({
            try await $0.reversiChallenge(accessToken: $1, opponentID: target, stake: stake)
        }) else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            writeRevision &+= 1             // 이 응답보다 먼저 나간 로비는 잔액·진행 판 id 를 덮지 않는다
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            if response.status == .unsupportedClient {
                noteUpdateRequired()
                return
            }
            setNotice(ReversiNoticeText.challenge(response.status, need: response.need, have: response.have))
            if response.status != .ok {
                Self.logger.notice("challenge refused status=\(response.status.rawValue, privacy: .public)")
            }
            switch response.status {
            case .ok:
                guard let id = response.matchId?.lowercased(), !id.isEmpty else { break }
                let peer = users.first { $0.id == target } ?? ReversiUser(id: target, displayName: "")
                let expiresAt = deviceDate(serverMs: response.inviteExpiresMs)
                    ?? clock().addingTimeInterval(inviteTTLSeconds)
                outgoingRevision &+= 1
                outgoing = ReversiOutgoing(id: id, peer: peer, stake: stake, expiresAt: expiresAt)
                lastOutgoingRequestAt = clock()
                scheduleInviteExpiry()
            case .alreadyPending, .busy, .targetBusy, .targetOutdated, .targetFocused:
                // 목록의 칩이 틀렸다는 뜻이다 — 다시 읽어 행을 사실에 맞춘다.
                await refreshLobby()
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
        guard let result = await perform({ try await $0.reversiCancel(accessToken: $1, matchID: id) }) else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            writeRevision &+= 1             // 이 응답보다 먼저 나간 로비는 잔액·진행 판 id 를 덮지 않는다
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            if response.status == .unsupportedClient {
                noteUpdateRequired()
                return
            }
            setNotice(ReversiNoticeText.cancel(response.status))
            switch response.status {
            case .ok, .notFound, .notPending, .expired:
                if outgoing?.id == id {
                    outgoing = nil
                    scheduleInviteExpiry()
                }
                // not_pending 은 취소보다 수락이 먼저 닿았다는 뜻일 수 있다 — 실려 온 판이 진행 중이면 그 판을 세운다.
                if response.status == .notPending {
                    if let state = response.state, state.match?.matchStatus == .active {
                        applyState(state)
                    } else {
                        await refreshLobby()
                    }
                }
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
            try await $0.reversiRespond(accessToken: $1, matchID: id, accept: accept)
        }) else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            writeRevision &+= 1             // 이 응답보다 먼저 나간 로비는 잔액·진행 판 id 를 덮지 않는다
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            if response.status == .unsupportedClient {
                noteUpdateRequired()
                return
            }
            setNotice(ReversiNoticeText.respond(
                accept: accept, response.status, side: response.side, need: response.need, have: response.have))
            if response.status != .ok {
                Self.logger.notice("respond refused status=\(response.status.rawValue, privacy: .public)")
            }
            switch response.status {
            case .ok:
                forgetIncoming(id)
                guard accept, response.accepted != false else { break }
                // 수락하는 순간 서버가 두 참가자의 **다른 대기 신청을 전부 거둔다** — 로컬 카드를 그대로 두면
                // 다음 로비에서 '상대가 신청을 받지 않았어요' 가 뜬다.
                if outgoing != nil {
                    outgoing = nil
                    scheduleInviteExpiry()
                }
                if let state = response.state {
                    applyState(state)
                } else {
                    await refreshMatch(id: id)
                }
                if match?.id != id, !isWindowVisible { presentWindow?() }
            case .notPending:
                forgetIncoming(id)
                // 다른 기기(같은 계정)가 먼저 수락했으면 판이 실려 온다.
                if let state = response.state, state.match?.matchStatus == .active { applyState(state) }
            case .notFound, .expired, .invalid:
                forgetIncoming(id)
            default:
                // busy · target_busy · insufficient — 신청은 아직 살아 있다(나중에 받을 수 있다).
                break
            }
        }
    }

    /// 한 칸에 둔다. 1:1 은 서버, AI 판은 로컬. **`legalTargets` 밖이면 요청 없이 문구만**(합법 수는 서버 목록만, ⑦).
    package func place(_ idx: Int) async {
        guard !isBusy else {
            setNotice(ReversiNoticeText.sending)
            return
        }
        guard let current = match, !current.isFinished else { return }
        guard current.isMyTurn else {
            setNotice(ReversiNoticeText.notYourTurn)
            return
        }
        guard legalTargets.contains(idx) else {
            setNotice(ReversiNoticeText.illegal(Self.localRefusal(board: current.board, color: current.myColor, idx: idx)))
            return
        }
        // AI 판은 위 거절 가드를 **같이** 지난 뒤 로컬 판에 둔다 — 서버로는 안 나간다(로그인 여부도 안 본다).
        if current.isAI {
            placeInAIMatch(idx)
            return
        }
        guard host?.session != nil else {
            setNotice(ReversiNoticeText.signInAgain)
            return
        }
        let id = current.id
        let expected = current.moveCount
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({
            try await $0.reversiMove(accessToken: $1, matchID: id, expectedSeq: expected, idx: idx)
        }) else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            writeRevision &+= 1             // 이 응답보다 먼저 나간 로비는 잔액·진행 판 id 를 덮지 않는다
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            if response.status == .unsupportedClient {
                noteUpdateRequired()
                return
            }
            setNotice(ReversiNoticeText.move(response.status, reason: response.illegalReason))
            if response.status != .ok {
                Self.logger.notice("move refused status=\(response.status.rawValue, privacy: .public)")
            }
            if response.status == .notFound {
                if match?.id == id { clearMatch() }
                return
            }
            // 쓰기 응답의 state 는 수 기록 전체다(§3.4) — 처음부터 다시 짓는다. stale 도 이 한 줄로 맞춘다(문구 없음).
            if let state = response.state {
                if applyState(state, requestedSince: 0) == .needsFull { await refreshMatch(id: id) }
            } else {
                switch response.status {
                case .ok, .stale, .notYourTurn, .notActive, .illegal, .autoPlaced:
                    await refreshMatch(id: id)   // 상태를 안 실어 준 응답(계약상 없지만 모르는 모양은 되묻는다)
                default:
                    break
                }
            }
        }
    }

    package func resign() async {
        if let current = match, current.isAI {
            resignAIMatch()
            return
        }
        guard !isBusy, let current = match, !current.isFinished, host?.session != nil else { return }
        let id = current.id
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({ try await $0.reversiResign(accessToken: $1, matchID: id) }) else { return }
        switch result {
        case .failure(let error):
            noteActionFailure(error)
        case .success(let response):
            writeRevision &+= 1             // 이 응답보다 먼저 나간 로비는 잔액·진행 판 id 를 덮지 않는다
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            if response.status == .unsupportedClient {
                noteUpdateRequired()
                return
            }
            setNotice(ReversiNoticeText.resign(response.status))
            if response.status == .notFound {
                if match?.id == id { clearMatch() }
                return
            }
            if let state = response.state { applyState(state) } else { await refreshMatch(id: id) }
        }
    }

    /// 결과 화면 [로비로]. **진행 중인 판에서는 아무것도 안 한다** — 빠져나가는 길은 기권뿐이다.
    package func backToLobby() {
        let wasAI = match?.isAI == true
        guard foldFinishedMatch() else { return }
        guard !wasAI, host?.session != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshLobby()
            await self.refreshRanking()
        }
    }

    /// 끝난 판을 내리고 화면을 로비로 돌린다. 요청은 쏘지 않는다. 끝난 판을 들고 있지 않으면 false.
    @discardableResult
    private func foldFinishedMatch() -> Bool {
        guard let current = match, current.isFinished else { return false }
        if !current.isAI { dismissedMatchIDs.insert(current.id) }
        match = nil                             // 관찰자가 AI 판을 버린다
        if phase != .lobby { phase = .lobby }
        clearFlip()
        setNotice(nil)
        return true
    }

    /// 지금 차례(내 것이든 상대 것이든)의 남은 초 — 표시값 30초 기준, 서버 유예 미포함. 마감이 없으면 nil.
    /// 잎 뷰가 `now` 를 넘겨 부르는 **순수 계산**이다(⑥).
    package func remainingSeconds(now: Date) -> Double? {
        guard let match, !match.isFinished, let deadline = match.deadline else { return nil }
        return max(0, deadline.timeIntervalSince(now))
    }

    // MARK: - 신호 · 계기 (창 밖에서 아는 유일한 길)

    /// 실시간 초인종(`'reversi'` → `.reversiSignal`). 직렬화된 재조회 — 도는 중이면 뒤따르는 **한 번**으로 합친다.
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

    /// 신호 한 번의 조회: 진행 중 1:1 판이 있으면 그 판, 아니면 로비(받은·보낸 신청 + 진행 중 판 id).
    /// AI 판은 서버에 없다 — 그동안 온 신호는 로비(신청·수락)로 본다.
    package func syncOnce() async {
        if let current = match, !current.isFinished, !current.isAI {
            await refreshMatch(id: current.id)
        } else {
            await refreshLobby()
        }
    }

    /// 조인 직후·깨어남의 따라잡기: 로비 한 번(+ 그 응답이 가리키는 판). 진행 중 판만 읽으면 그 사이 온 신청을 모른다.
    package func catchUp() async {
        await refreshLobby()
    }

    package func realtimeDidJoin() {
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.catchUp() }
    }

    package func systemDidWake() {
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.catchUp() }
    }

    /// 팝오버 열림(30초 스로틀). 메뉴바 점(`visibleIncoming`)의 신선도가 이 계기와 소켓 신호에 달려 있다.
    package func refreshLobbyIfStale() {
        guard host?.session != nil else { return }
        let now = clock()
        guard now.timeIntervalSince(lastMenuLobbyAt) >= Self.menuLobbyThrottleSeconds else { return }
        lastMenuLobbyAt = now
        Task { [weak self] in await self?.refreshLobby() }
    }

    // MARK: - 폴링 (창이 보일 때만)

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

    /// 폴링 한 걸음의 조회를 **폴링 작업의 취소 밖에서** 돌리고 끝날 때까지 기다린다. 창을 닫는(최소화·가림) 순간 `stopPolling` 의
    /// 취소가 날던 조회에 닿으면, 그 조회에 합쳐진 초인종 조회(`stateAgain`·`lobbyAgain`)까지 같이 죽는다 — 창도 폴링도 없는 사람이
    /// 상대 수·수락을 모른 채 30초 자동 착수를 맞는다. 폴링은 멈추고 날던 조회만 끝까지 간다(로그아웃은 세대 가드가 버린다).
    /// 날던 조회가 끝난 뒤 **남은 걸음**은 걸음 사이 가드(창 보임 · 안 가림 · 폴링 작업 안 취소)가 막는다(적대 재검증 VR-04).
    private func outsidePolling(_ body: @escaping @MainActor (ReversiStore) async -> Void) async {
        await Task { @MainActor [weak self] in
            guard let self else { return }
            await body(self)
        }.value
    }

    /// 안전망 한 걸음. **창이 안 보이면 아무것도 하지 않는다**(③).
    ///  · 진행 중 1:1 판이 상대 차례거나 내 마감 + 유예가 지났으면 `statePollSeconds` 마다 상태(서버가 자동 착수를 정산한다)
    ///  · 보낸 신청이 있으면 5초마다 그 판의 상태(수락·거절·만료를 한 조회가 다 말한다)
    ///  · 로비를 보고 있으면 30초마다 목록
    ///  · 관전 2초 / 순위 60초(확장이 주 스위치·가림을 본다)
    /// **분기 사이사이 창 보임 · 가림 · 취소를 다시 본다** — await 중에 창이 내려가거나 가려질 수 있다.
    package func pollTick(at now: Date) async {
        guard isWindowVisible, !isWindowOccluded, host?.session != nil else { return }
        if let current = match, !current.isFinished, !current.isAI {
            let waiting = !current.isMyTurn
            let overdue = current.deadline.map { now >= $0.addingTimeInterval(graceSeconds) } ?? false
            if waiting || overdue {
                let subscribed = host?.realtimeState.isSubscribed ?? false
                let interval = Self.statePollSeconds(subscribed: subscribed, deadline: current.deadline, now: now)
                if now.timeIntervalSince(lastStateRequestAt) >= interval {
                    let id = current.id
                    await outsidePolling { await $0.refreshMatch(id: id) }
                }
            }
        }
        guard isWindowVisible, !isWindowOccluded, !Task.isCancelled else { return }
        if let sent = outgoing, now.timeIntervalSince(lastOutgoingRequestAt) >= Self.outgoingPollSeconds {
            let id = sent.id
            await outsidePolling { await $0.refreshMatch(id: id) }
        }
        guard isWindowVisible, !isWindowOccluded, !Task.isCancelled else { return }
        if phase == .lobby, now.timeIntervalSince(lastLobbyRequestAt) >= Self.lobbyPollSeconds {
            await outsidePolling { await $0.refreshLobby() }
        }
        guard isWindowVisible, !isWindowOccluded, !Task.isCancelled else { return }
        await pollSpectatorFeatures(at: now)
    }

    // MARK: - 리셋

    /// 로그아웃·계정 전환. 세대를 올리고 화면 상태를 처음으로 돌린다 — 남기면 다음 사람이 앞 사람의 판·신청·루비를 본다.
    package func reset() {
        resetGeneration &+= 1
        stopPolling()
        discardAIGame()
        clearFlip()
        expiryTask?.cancel()
        expiryTask = nil
        // 신호 재조회도 끊는다 — 앞 계정의 따라잡기가 다음 사람의 화면에 신청·판을 세우면 안 된다.
        syncTask?.cancel()
        syncTask = nil
        syncPendingTrailing = false
        stateInFlight = false
        stateAgain = false
        lobbyInFlight = false
        lobbyAgain = false
        stateInFlightID = nil
        pendingStateID = nil
        if phase != .lobby { phase = .lobby }
        if availability != .available { availability = .available }
        if !users.isEmpty { users = [] }
        if !liveMatches.isEmpty { liveMatches = [] }
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
        if !hiddenPeerIDs.isEmpty { hiddenPeerIDs = [] }
        if spectating != nil { spectating = nil }
        if ranking != nil { ranking = nil }
        if rankingUnavailable { rankingUnavailable = false }
        if watchUnavailable { watchUnavailable = false }
        if spectatorCountUnavailable { spectatorCountUnavailable = false }
        if spectatorCount != 0 { spectatorCount = 0 }
        watchRuntime.clear()
        serverClockOffset = 0
        hasServerClockOffset = false
        isWindowOccluded = false
        attentionKey = nil
        activeMatchID = nil
        seenInviteIDs = []
        answeredInviteIDs = []
        dismissedMatchIDs = []
        outgoingRevision = 0
        lobbyRequestOutgoingRevision = 0
        writeRevision = 0
        lastStateRequestAt = .distantPast
        lastLobbyRequestAt = .distantPast
        lastOutgoingRequestAt = .distantPast
        lastMenuLobbyAt = .distantPast
        inviteTTLSeconds = 60
        turnSeconds = 30
        graceMs = 2_000
        autoAbandonStreak = 3
        passNotice = nil
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

    /// 서버에 리버시 RPC 가 아직 없다(PGRST202 — 앱이 db push 보다 먼저 나간 창).
    package nonisolated func isSchemaMissing(_ error: any Error) -> Bool {
        (error as? SupabaseWorkServiceError) == .databaseSchemaMissing
    }

    /// 쓰기 동작이 throw 로 실패했다(5xx·오프라인·PGRST202).
    private func noteActionFailure(_ error: any Error) {
        if isSchemaMissing(error) {
            noteServerMissing()
        } else {
            setNotice(ReversiNoticeText.checkConnection)
        }
    }

    /// Availability `.serverMissing` — 서버에 아잉 뒤집기가 아직 없다.
    package func noteServerMissing() {
        if availability != .serverMissing { availability = .serverMissing }
        setNotice(ReversiNoticeText.unavailable)
    }

    /// Availability `.updateRequired` — 내 앱이 옛 버전이다.
    package func noteUpdateRequired() {
        if availability != .updateRequired { availability = .updateRequired }
        setNotice(ReversiNoticeText.updateRequired)
    }

    /// 안내줄 한 문.
    package func setNotice(_ text: String?) {
        if notice != text { notice = text }
        if text != passNotice { passNotice = nil }
    }

    private func applyRuby(_ value: Int?) {
        guard let value else { return }
        if rubyBalance != value { rubyBalance = value }
        if let host, host.rubyBalance != value { host.rubyBalance = value }
    }

    package func clearMatch() {
        if match != nil { match = nil }
        if phase != .lobby { phase = .lobby }
        clearFlip()
    }

    /// 받은 신청 하나를 이 기기에서 답한 것으로 적고 카드를 걷는다.
    private func forgetIncoming(_ id: String) {
        answeredInviteIDs.insert(id)
        if incoming.contains(where: { $0.id == id }) {
            incoming.removeAll { $0.id == id }
            scheduleInviteExpiry()
        }
    }

    /// 신청 한 건을 세운다(`pending` 상태 응답). 받은 것인지 보낸 것인지는 **내가 challenger 인가**로 가른다.
    private func applyInvite(_ row: ReversiMatchRow, payload: ReversiStatePayload, id: String) {
        guard let myID = host?.session?.userID.lowercased(),
              let stake = row.stake,
              let expiresAt = deviceDate(serverMs: row.inviteExpiresMs),
              let peer = playerUser(payload.opponent, inMatch: false) else { return }
        if row.challenger?.lowercased() == myID {
            let fresh = ReversiOutgoing(id: id, peer: peer, stake: stake, expiresAt: expiresAt)
            let steady = Self.steadyOutgoing(fresh, previous: outgoing)
            if outgoing != steady { outgoing = steady }
        } else if !answeredInviteIDs.contains(id) {
            let invite = ReversiInvite(id: id, peer: peer, stake: stake, expiresAt: expiresAt)
            var list = incoming
            if let index = list.firstIndex(where: { $0.id == id }) {
                list[index] = Self.steadyInvite(invite, previous: list[index])
            } else {
                list.insert(invite, at: 0)
            }
            if incoming != list { incoming = list }
            if !seenInviteIDs.contains(id) {
                seenInviteIDs.insert(id)
                if !hiddenPeerIDs.contains(peer.id) { onInviteArrived?(invite) }
            }
        }
        if match?.id == id { clearMatch() }
        scheduleInviteExpiry()
    }

    /// 그 id 가 판이었으면 판을 내리고, 신청이었으면 신청 카드를 걷는다(보낸 신청이면 안내 한 줄).
    private func dropMatchOrInvite(_ id: String, notice: String? = nil) {
        if match?.id == id { clearMatch() }
        if activeMatchID == id { activeMatchID = nil }
        if incoming.contains(where: { $0.id == id }) { incoming.removeAll { $0.id == id } }
        if outgoing?.id == id {
            outgoing = nil
            if let notice { setNotice(notice) }
        }
        scheduleInviteExpiry()
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

    /// 만료된 신청을 `incoming`·`outgoing` 에서 걷는다(관찰을 깨는 대입 — 메뉴바 점이 곧바로 꺼진다).
    package func pruneExpiredInvites(now: Date) {
        let alive = incoming.filter { $0.expiresAt > now }
        if alive.count != incoming.count { incoming = alive }
        if let sent = outgoing, sent.expiresAt <= now {
            outgoing = nil
            setNotice(ReversiNoticeText.inviteTimedOut)
        }
        scheduleInviteExpiry()
    }

    /// 판 진행을 사람에게 알린다(진행 중 판을 옮긴 직후).
    ///  · 판이 없거나 끝난 판에서 **진행 중 판으로 처음 넘어가면** 창을 띄우고 주의를 끈다.
    ///  · 창이 안 보이는 동안 차례가 나에게 오면 말풍선 문을 연다. 같은 (판 id, move_count) 에는 한 번뿐이다.
    private func noteMatchProgress(previous: ReversiMatchState?, next: ReversiMatchState, windowWasVisible: Bool) {
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
        onAttention?(ReversiAttention(
            kind: started ? .matchStarted : .myTurn, matchID: next.id,
            opponentName: next.opponent.displayName, moveCount: next.moveCount))
    }

    /// 판이 나아갔다 — 뒤집기 그림과 패스 안내를 정한다(1:1 `applyState` · AI `commitAIGame` 두 깔때기가 같이 지난다).
    func noteBoardProgress(previous: ReversiMatchState?, next: ReversiMatchState) {
        let sameMatch = previous?.id == next.id
        let advanced = !sameMatch || previous?.moveCount != next.moveCount
        guard advanced else { return }
        // 뒤집기: 창이 보이고 안 가려졌을 때만(보이지 않는 창의 TimelineView 를 깨우지 않는다). 돌 한 수(+ 패스)일 때만 선다.
        if isWindowVisible, !isWindowOccluded,
           let made = ReversiFlipAnimation.make(from: previous, to: next, at: clock()) {
            beginFlip(made)
        } else {
            clearFlip()
        }
        // 패스 안내: 이번에 새로 온 기록에 패스 줄이 있으면 그 사실을 한 줄로(판 화면은 패스를 그리지 않는다).
        guard sameMatch, let previous else { return }
        let fresh = next.plies.filter { $0.seq > previous.moveCount }
        let text: String?
        if !next.isFinished, next.turn == next.myColor,
           fresh.contains(where: { $0.kind == .pass && $0.color == next.myColor.opponent }) {
            text = ReversiNoticeText.opponentPassed(name: next.opponent.displayName)
        } else if !next.isFinished, fresh.contains(where: { $0.kind == .pass && $0.color == next.myColor }) {
            text = ReversiNoticeText.myPass
        } else {
            text = nil
        }
        if let text {
            setNotice(text)
            passNotice = text
        } else if let shown = passNotice, notice == shown {
            setNotice(nil)                      // 지난 패스 안내는 다음 수가 오면 걷는다
        }
    }

    func beginFlip(_ made: ReversiFlipAnimation) {
        flipToken &+= 1
        let token = flipToken
        flipTask?.cancel()
        flip = made
        let duration = made.duration
        flipTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.05))
            guard let self, token == self.flipToken else { return }
            self.flipTask = nil
            if self.flip != nil { self.flip = nil }
        }
    }

    func clearFlip() {
        flipToken &+= 1
        flipTask?.cancel()
        flipTask = nil
        if flip != nil { flip = nil }
    }

    /// `server_now_ms` 로 기기 시계 어긋남을 잰다. 처음 잰 값은 그대로 받고, 그 뒤로는 문턱(250ms) 넘게 벗어날 때만 간다.
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

    /// 로비 신청 행 → 화면 값. 하나라도 모르면 **그 카드를 만들지 않는다**.
    private func invite(from row: ReversiInviteRow, peer peerRow: ReversiPeerRow?) -> ReversiInvite? {
        guard let id = row.matchId?.lowercased(), !id.isEmpty,
              let stake = row.stake,
              let expiresAt = deviceDate(serverMs: row.expiresAtMs),
              let peer = peerUser(peerRow, inMatch: false) else { return nil }
        return ReversiInvite(id: id, peer: peer, stake: stake, expiresAt: expiresAt)
    }

    /// 같은 신청을 다시 읽었을 때 만료가 문턱 안쪽으로만 다르면 기존 값을 그대로 쓴다(관찰자를 헛되게 깨우지 않게).
    package nonisolated static func steadyInvite(_ fresh: ReversiInvite, previous: ReversiInvite?) -> ReversiInvite {
        guard let previous, previous.id == fresh.id, previous.stake == fresh.stake, previous.peer == fresh.peer,
              abs(previous.expiresAt.timeIntervalSince(fresh.expiresAt)) < inviteExpiryToleranceSeconds
        else { return fresh }
        return previous
    }

    package nonisolated static func steadyOutgoing(_ fresh: ReversiOutgoing, previous: ReversiOutgoing?) -> ReversiOutgoing {
        guard let previous, previous.id == fresh.id, previous.stake == fresh.stake, previous.peer == fresh.peer,
              abs(previous.expiresAt.timeIntervalSince(fresh.expiresAt)) < inviteExpiryToleranceSeconds
        else { return fresh }
        return previous
    }

    /// 로컬 거절 문구의 까닭(서버 목록 밖 칸). 규칙상 둘 수 있는 칸이어도 서버가 안 줬으면 "둘 수 없는 칸"이다(⑦).
    package nonisolated static func localRefusal(board: ReversiBoard, color: ReversiColor, idx: Int) -> ReversiIllegalReason {
        guard (0..<64).contains(idx) else { return .outOfRange }
        if board[idx] != nil { return .occupied }
        if ReversiRules.flips(board, color: color, idx: idx).isEmpty { return .noFlip }
        return .outOfRange
    }

    /// state 사람 행(`user_id`) → ReversiUser. 행에 없는 칸은 로비 목록에서 빌린다.
    /// 서버 어휘 → 화면 글자(센터)는 **이 함수 · `peerUser` · `user(from:)` 세 곳뿐**이다.
    package func playerUser(_ row: ReversiPlayerRow?, inMatch: Bool) -> ReversiUser? {
        guard let row, let id = row.userId?.lowercased(), !id.isEmpty else { return nil }
        let known = users.first { $0.id == id }
        return ReversiUser(
            id: id, displayName: row.displayName ?? known?.displayName ?? "",
            avatarURL: row.avatarUrl ?? known?.avatarURL, characterID: row.character ?? known?.characterID,
            center: CenterLabel.display(row.center) ?? known?.center,
            isWorking: known?.isWorking ?? false, isCapable: known?.isCapable ?? true,
            inMatch: inMatch, focusMode: known?.focusMode ?? false)
    }

    /// 로비 PEER 행(`id`) → ReversiUser. 행에 없는 칸은 로비 목록에서 빌린다.
    package func peerUser(_ row: ReversiPeerRow?, inMatch: Bool) -> ReversiUser? {
        guard let row, let id = row.id?.lowercased(), !id.isEmpty else { return nil }
        let known = users.first { $0.id == id }
        return ReversiUser(
            id: id, displayName: row.displayName ?? known?.displayName ?? "",
            avatarURL: row.avatarUrl ?? known?.avatarURL, characterID: row.character ?? known?.characterID,
            center: known?.center, isWorking: known?.isWorking ?? false, isCapable: known?.isCapable ?? true,
            inMatch: inMatch, focusMode: known?.focusMode ?? false)
    }

    /// 로비 "지금 대결 중" 한 줄 → 화면 값. 하나라도 모르면 **그 카드를 만들지 않는다**.
    package func liveMatch(from row: ReversiLobbyMatchRow) -> ReversiLiveMatch? {
        guard let id = row.id?.lowercased(), !id.isEmpty,
              let a = peerUser(row.a, inMatch: true), let b = peerUser(row.b, inMatch: true),
              let stake = row.stake,
              let startedAt = deviceDate(serverMs: row.startedAtMs)
        else { return nil }
        // 안 싣는 서버면 0 — 카드는 그냥 눈 아이콘을 안 그린다(없는 숫자를 지어내지 않는다).
        return ReversiLiveMatch(id: id, a: a, b: b, stake: stake, startedAt: startedAt, watchers: max(0, row.watchers ?? 0))
    }

    /// 로비 사람 행 → ReversiUser. `capable` 이 nil 이면 **불가**다.
    package nonisolated static func user(from row: ReversiLobbyUserRow) -> ReversiUser? {
        guard let id = row.id?.lowercased(), !id.isEmpty else { return nil }
        return ReversiUser(
            id: id, displayName: row.displayName ?? "", avatarURL: row.avatarUrl, characterID: row.character,
            center: CenterLabel.display(row.center), isWorking: row.isWorking ?? false,
            isCapable: row.capable ?? false, inMatch: row.inMatch ?? false, focusMode: row.focusMode ?? false)
    }

    /// 로비 정렬: 신청할 수 있는 사람(근무·가능·한가·집중 아님) → 근무 중·가능 → 근무 중 → 나머지, 그 안은 서버 순서.
    /// **서버 정렬(working desc → capable desc → 이름 → id)과 같은 줄기**라 재정렬이 아니라 되맞춤이다.
    package nonisolated static func sortedForLobby(_ users: [ReversiUser]) -> [ReversiUser] {
        func rank(_ user: ReversiUser) -> Int {
            if user.isWorking && user.isCapable && !user.inMatch && !user.focusMode { return 0 }
            if user.isWorking && user.isCapable { return 1 }
            if user.isWorking { return 2 }
            return 3
        }
        return users.enumerated().sorted { lhs, rhs in
            let (l, r) = (rank(lhs.element), rank(rhs.element))
            if l != r { return l < r }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// 판이 **막 끝났는가** — 새 판이 끝났고, 같은 판의 끝난 모양을 이미 들고 있던 게 아니다(순수 — 시험이 값으로 잰다).
    package nonisolated static func matchJustFinished(from old: ReversiMatchState?, to new: ReversiMatchState?) -> Bool {
        guard let new, new.isFinished else { return false }
        return !(old?.id == new.id && old?.isFinished == true)
    }

    /// 판 상태 변화 한 줄(없으면 nil). 수·차례·끝남·판 교체만 본다 — 시계·루비는 이 줄을 만들지 않는다.
    package nonisolated static func matchTransitionLine(from old: ReversiMatchState?, to new: ReversiMatchState?) -> String? {
        func turn(_ m: ReversiMatchState?) -> String { m?.turn?.rawValue ?? "none" }
        func count(_ m: ReversiMatchState?) -> String { m.map { String($0.moveCount) } ?? "-" }
        func finished(_ m: ReversiMatchState?) -> Bool { m?.isFinished ?? false }
        let sameMatch = old?.id == new?.id
        guard !sameMatch || count(old) != count(new) || turn(old) != turn(new)
                || finished(old) != finished(new) else { return nil }
        return "state moves=\(count(old))→\(count(new)) turn=\(turn(old))→\(turn(new)) "
            + "finished=\(finished(new)) sameMatch=\(sameMatch) ai=\(new?.isAI ?? false)"
    }
}
