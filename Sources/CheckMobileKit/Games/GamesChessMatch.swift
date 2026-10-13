import CheckCore
import Foundation
#if os(iOS)
import CheckMobileShared
import SwiftUI
#endif

// 폰 1:1 체스 **대국 화면**(맥 `ChessPanel`의 대국·결과 절 · 폰 오목 `GamesGomokuMatch` 문법).
// 돈이 갈리는 화면이라, 판정이 들어가는 자리는 **전부 이 파일 위쪽의 순수 표**(`GamesChessMatchChrome`)에 둔다 —
// 폰 뷰는 맥 스위트가 못 보지만(CheckMobileKit 의 절반이 `#if os(iOS)`) 그 표는 보이기 때문이다.
//
// 지키는 계약(맥에서 실제로 데인 자리들 — 인수인계 §6):
//  ① **시계는 서버가 쥔다**(`white_ms_left`/`black_ms_left` + 한 수 가산). 폰은 한 번도 세지 않는다 —
//     이 파일에 `whiteMsLeft`·`blackMsLeft` 로 가는 **대입이 한 줄도 없고**, 초를 읽는 자리는 잎 뷰의
//     TimelineView 뿐이다(`store.remainingSeconds(_:now:)` 는 순수 계산이다). **시간 상수도 베끼지 않는다**:
//     지금 서버는 10분 + 한 수 3초지만 2026-10-12 에 5분에서 늘어난 값이라(`20261012120000_chess_clock_10min`),
//     총시간은 로비가 말한 `store.initialMs`, 가산은 이 판의 행에서 온 `match.clock.incrementMs` 에서 읽는다.
//  ② **유예는 판·사람당 1회 예산**이다. 로비의 전역 `grace_ms`(2,000)는 판이 시작될 때의 값일 뿐이고 실제
//     판정은 행마다 오는 잔량(`white_grace_ms`/`black_grace_ms`)으로 한다. 그 판정은
//     `ChessMatchState.isFlagOverdue(now:graceSeconds:)` **하나뿐**이고(부등호도 서버와 같다 — `>`)
//     이 파일은 손으로 비교하지 않는다. 전역 값을 쓰면 예산을 다 쓴 사람의 판이 서버에서 벌써 끝났는데
//     화면은 최대 2초를 더 "상대 차례 · 0.0" 으로 그린다.
//  ③ **FIDE 6.9**: 깃발이 떨어졌는데 남은 쪽에 메이트 재료가 없으면 **무승부**다(2배 승리가 아니다).
//     서버가 판정해 사유를 `timeout`(패) 과 `timeout_insufficient`(무) 로 **갈라** 보낸다 — 폰은 다시 계산하지
//     않고 **문구만** 그 경우를 말한다. 두 문구가 섞이면 돈이 틀린다(그래서 결과 표가 `default:` 를 안 쓴다).
//  ④ **합법 수를 클라가 만들지 않는다.** 1:1 은 서버가 준 `payload.legal_moves` 만, 로봇 판만 로컬 규칙이고,
//     그 둘은 코어가 `match.legalMoves` 한 칸으로 합쳐 뒀다 — 화면은 어느 쪽인지 모른다. 이 파일에
//     `ChessRules` 가 **한 번도 안 나온다**.
//  ⑤ **승격은 2단**이다. 도착 칸이 같은 합법 수가 넷이면 승격이고 그때만 네 말을 묻는다 — 그 판정은
//     코어 `commit(from:to:)` 가 하고(`ChessStore.promotion`), 화면은 그 칸이 서 있는지만 본다.
//  ⑥ **수 번호가 줄어든 응답**은 `applyState` 가 이미 버린다 — 화면이 따로 막지 않는다(두 벌이면 한 벌은 죽은 가드다).
//  ⑦ **`expected_ply` 를 같은 값으로 두 번 보내면 두 번째는 `stale` 이고 가산은 한 번만** 붙는다. 그래서 이
//     화면에는 **착수 재시도 버튼이 없다**(`store.send(` 를 부르는 자리도 없다 — 입구는 탭과 승격 고르기뿐).
//  ⑧ **낙관적 표시가 없다.** 판은 `match.position`(서버가 확인한 국면)만 그린다. 내 수는 응답이 와야
//     미끄러진다(0.1~0.3초). ★ 사용자 결정이 필요한 자리다 — 넣으면 서버가 확인하지 않은 판을 보여 준다.
//  ⑨ 계정 삭제가 진행 중 판을 `abandoned` 로 닫고 **서버가 상대에게 환불한다** — 화면은 경고하지 않고 사유만 말한다.
//
// 채팅은 없다(오목에만 있다). 관전·로비·순위는 다른 화면이다.

// MARK: - 문구 (★ 자리표시 — 문구 레인의 `GamesChessText`(= `ChessPhoneText` 별칭)가 들어오면 **이 표를 지운다**)
//
// 이름을 약속된 `GamesChessText` 그대로 둔 까닭: 같은 모듈에 같은 이름이 둘이면 Swift 는 `private` 이라도
// **invalid redeclaration 으로 막는다**(이 저장소에서 프로브로 실측했다). 그래서 머지 때 이 표를 안 지우면
// 컴파일이 멈춘다 — 조용히 옛 문구가 쓰이는 길이 없다. 호출부는 한 줄도 안 바뀐다.

/// 이 화면이 쓰는 사용자 어휘. 안내 한 줄(거절·실패)은 **코어 `ChessNoticeText`** 를 그대로 쓴다 —
/// 같은 사실이 화면마다 다른 말을 하면 그게 다음 조사거리다.
/// 맥 정본은 `Sources/check/ChessPanel.swift` 의 `ChessText` 이고, 아래는 같은 뜻이면 **같은 문장**이다.
private enum GamesChessText {
    static let title = "1:1 체스"
    static let stakeTitle = "판돈"
    static func stakeGainSuffix(_ stake: Int) -> String { " · 이기면 +\(stake)" }
    /// 로봇 판의 판돈 자리(맥 "AI 대국 · 기록 없음" 과 같은 뜻).
    static let robotStakeChip = "로봇과 두기 · 기록 없음"
    static let robotNoRecord = "로봇과 둔 판은 순위·루비에 들어가지 않아요"

    static let myTurn = "내 차례예요"
    static let opponentTurn = "상대 차례예요"
    static let inCheck = "체크! 왕을 피하세요"
    static let opponentInCheck = "상대가 체크예요"
    static let robotThinking = "로봇이 생각 중이에요"
    /// 깃발이 떨어지고 **유예 예산까지** 지났다 — 서버가 정산하는 중이다(폰이 판정한 것이 아니다).
    static let flagSettling = "시간이 다 됐어요 · 결과를 확인하고 있어요"
    /// 서버 FEN 을 읽지 못해 판을 그릴 수 없다(서버 쪽 문제 — 결과·루비는 그대로 보여 준다).
    static let unreadableBoard = "판을 그릴 수 없어요 · 결과는 그대로 보여요"
    /// 폰에서 처음 쓰는 문장: 맥과 달리 앱을 내려도 판은 서버에서 계속 흐른다.
    static let clockKeepsRunning = "앱을 닫아도 시계는 계속 흘러요"
    /// 시간 규칙 한 마디. ★ **숫자를 박지 않는다** — 서버가 준 값에서 조립한다(10-12 에 5분 → 10분이 됐다).
    static func clockPhrase(initialMs: Int, incrementMs: Int) -> String {
        let minutes = max(1, initialMs / 60_000)
        let increment = max(0, incrementMs / 1_000)
        return "\(minutes)분 + 한 수 \(increment)초"
    }

    static func plyLine(_ ply: Int) -> String { "\(ply)수 진행" }

    static let resign = "기권"
    static let resignNow = "기권하기"
    static let keepPlaying = "계속 두기"
    static let resignConfirmTitle = "기권할까요?"
    static func resignConfirmMessage(stake: Int) -> String { "판돈 \(stake) 루비를 상대가 가져가요" }
    static let robotResignConfirmMessage = "로봇 판이라 루비는 걸리지 않아요"
    static let offerDraw = "무승부 제안"
    static let drawOfferedByMe = ChessNoticeText.drawOffered
    static let drawOfferedByOpponent = ChessNoticeText.drawOfferPending
    static let acceptDraw = "무승부 수락"
    static let declineDraw = "거절"
    static let backToLobby = "로비로"
    static let playAgain = "다시 두기"

    static let movesTitle = "기보"
    static let noMoves = "아직 둔 수가 없어요"
    static let promotionTitle = "승격할 말을 고르세요"

    static func stoneName(_ color: ChessColor) -> String { color == .white ? "백" : "흑" }
    static let me = "나"

    // 결과.
    static func outcomeTitle(_ outcome: ChessMatchOutcome?) -> String {
        switch outcome {
        case .won?: return "이겼어요"
        case .lost?: return "졌어요"
        case .draw?: return "무승부예요"
        case nil: return "대국이 끝났어요"
        }
    }

    /// 사유를 모를 때(서버가 새 값을 보냈다 · 응답에 없다). **빈칸으로 두지 않는다** — 결과 카드에 이유 줄이
    /// 사라지면 사용자는 왜 끝났는지 못 묻는다.
    static let unknownEndReason = "대국이 끝났어요"

    /// 끝난 이유(**내 기준** — 주어가 '상대'다). `ChessEndReason` 열 갈래를 **빠짐없이** 말한다:
    /// `default:` 를 두지 않는 것이 계약이다 — 접으면 `abandoned`(상대 계정 삭제)가 "대국이 끝났어요" 가 되어
    /// 남는 사람이 왜 이겼는지 모르고, `timeout_insufficient` 가 패배 문장을 입는다. 사유가 늘면 컴파일이 막는다.
    static func endReason(_ reason: ChessEndReason?, outcome: ChessMatchOutcome?) -> String {
        guard let reason else { return unknownEndReason }
        switch reason {
        case .checkmate: return outcome == .won ? "체크메이트" : "체크메이트를 당했어요"
        case .resign: return outcome == .won ? "상대가 기권했어요" : "기권했어요"
        case .timeout: return outcome == .won ? "상대 시간이 다 됐어요" : "시간이 다 됐어요"
        // ★ FIDE 6.9 — 깃발은 떨어졌지만 남은 쪽에 메이트 재료가 없어 **무승부**다. 위 `timeout`(패) 과
        //   **다른 문장이어야 한다**: 섞이면 환불받은 사람이 졌다고 읽는다.
        case .timeoutInsufficient: return "시간이 다 됐지만 메이트할 기물이 없어요 · 무승부예요"
        case .stalemate: return "스테일메이트"
        case .fiftyMove: return "50수 규칙"
        case .threefold: return "같은 국면 3회 반복"
        case .insufficientMaterial: return "메이트할 기물이 없어요"
        case .agreement: return "무승부에 합의했어요"
        case .abandoned: return "상대가 더 둘 수 없게 됐어요"
        }
    }

    /// 로봇 판의 끝난 이유 — **루비 어휘도, '상대' 도 쓰지 않는다**(걸린 루비가 없고, 상대는 사람이 아니다).
    /// 사람 판 표를 그대로 쓰면 "상대가 기권했어요" 가 되어 로봇이 사람처럼 읽힌다.
    static func robotEndReason(_ reason: ChessEndReason?, outcome: ChessMatchOutcome?) -> String {
        guard let reason else { return unknownEndReason }
        switch reason {
        case .checkmate: return outcome == .won ? "체크메이트" : "체크메이트를 당했어요"
        case .resign: return outcome == .won ? "로봇이 기권했어요" : "기권했어요"
        case .timeout: return outcome == .won ? "로봇의 시간이 다 됐어요" : "시간이 다 됐어요"
        case .timeoutInsufficient: return "시간이 다 됐지만 메이트할 기물이 없어요 · 무승부예요"
        case .stalemate: return "스테일메이트"
        case .fiftyMove: return "50수 규칙"
        case .threefold: return "같은 국면 3회 반복"
        case .insufficientMaterial: return "메이트할 기물이 없어요"
        case .agreement: return "무승부로 끝났어요"
        case .abandoned: return "판이 닫혔어요"
        }
    }

    static func rubyDelta(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "−\(-delta)" }
        return "±0"
    }

    /// 무승부는 **양쪽이 판돈을 돌려받는다**(서버 `grant:chess:refund:`). ±0 만 그리면 "걸었다가 그대로"
    /// 인지 "잃었는지" 를 사용자가 못 가른다 — 돈이 갈리는 자리라 한 줄로 말한다.
    static func drawRefund(stake: Int) -> String { "판돈 \(stake) 루비를 돌려받았어요" }

    /// 시계 글자 — `m:ss`, 10초 아래는 소수 한 자리(마지막 10초는 1초 단위로 안 읽힌다). 맥과 같은 산식이다.
    static func clock(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        if clamped < 10 { return String(format: "%.1f", clamped) }
        let whole = Int(clamped.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    static func clockAccessibility(_ seconds: Double, color: ChessColor) -> String {
        let whole = Int(max(0, seconds).rounded())
        let side = stoneName(color)
        if whole >= 60 { return "\(side) 남은 시간 \(whole / 60)분 \(whole % 60)초" }
        return "\(side) 남은 시간 \(whole)초"
    }

    static func boardAccessibility(ply: Int, turn: ChessColor?, inCheck: Bool) -> String {
        var text = "체스판, \(ply)수 진행"
        if let turn { text += ", \(stoneName(turn)) 차례" }
        if inCheck { text += ", 체크" }
        return text
    }
}

// MARK: - 색의 뜻

/// 화면 표가 말하는 색. `MobileTheme` 은 iOS 전용이라 이 표에 `Color` 를 둘 수 없다(둬도 맥 스위트가 못 본다) —
/// **뜻만** 두고 뷰가 토큰으로 옮긴다.
package enum GamesChessMatchTint: Equatable, Sendable {
    /// 초록 — 내 차례 · 이김.
    case good
    /// 빨강 — 체크 · 짐 · 기권.
    case bad
    /// 앰버 — 안내 · 결과를 확인하는 중.
    case warn
    /// 회색 — 상대 차례 · 무승부 · 보조.
    case quiet
}

/// 글자 한 줄 + 그 뜻(색).
package struct GamesChessMatchLine: Equatable, Sendable {
    package let text: String
    package let tint: GamesChessMatchTint

    package init(text: String, tint: GamesChessMatchTint) {
        self.text = text
        self.tint = tint
    }
}

// MARK: - 화면 표 (순수 — 돈이 갈리는 판정은 전부 여기)

/// 대국 화면이 그리는 것을 **값으로** 내놓는 표. 뷰는 이 표를 배치만 한다.
///
/// 폰 뷰는 맥 스위트가 못 보므로(인수인계 §6-11) 결과·사유·루비·버튼 줄처럼 **틀리면 돈이 갈리는 판정**은
/// 뷰 몸통이 아니라 이 표에 있어야 한다. `Tests/CheckMobileKitTests/GamesChessMatchTests.swift` 가 이 표를 잰다.
package struct GamesChessMatchChrome: Equatable, Sendable {
    /// 아래 동작 줄 — 네 모양 중 하나다.
    package enum ActionRow: Equatable, Sendable {
        /// 두는 중. `canOfferDraw` 가 false 면 [무승부 제안]이 눌리지 않는다(이미 제안했거나 왕복 중).
        case playing(canOfferDraw: Bool, canResign: Bool)
        /// 상대가 무승부를 제안했다 — [수락] [거절].
        case answerDrawOffer
        /// 끝난 판 — [로비로](로봇 판은 [다시 두기] 가 앞에 붙는다).
        case finished(showsPlayAgain: Bool)
    }

    /// 끝난 판 한 장.
    package struct Result: Equatable, Sendable {
        /// 이겼어요 / 졌어요 / 무승부예요.
        package let title: String
        /// 끝난 이유. ★ `timeout`(패) 과 `timeout_insufficient`(FIDE 6.9 무승부)가 **다른 문장**이다.
        package let reason: String
        package let tint: GamesChessMatchTint
        /// 이 판으로 내 루비가 변한 양. 서버가 말한 값이 있으면 그것이고, 없으면 승패에서 센다.
        package let rubyDelta: Int
        package let rubyDeltaText: String
        /// 로봇 판은 루비를 안 그린다(±0 을 그리면 걸었다가 돌려받은 것처럼 읽힌다 — 맥과 같은 판단).
        package let showsRubyDelta: Bool
        /// 무승부 환불 한 줄 · 로봇 판의 "기록 없음" 한 줄. 없으면 nil.
        package let rubyNote: String?
        package let isDraw: Bool
    }

    package let isRobotMatch: Bool
    package let showsStake: Bool
    package let stake: Int
    /// 판돈 자리 부제(로봇 판은 "기록 없음").
    package let stakeSuffix: String?
    package let actionRow: ActionRow
    /// 승격 시트가 떠 있는가. **코어가 2단을 판정한다**(도착 칸이 같은 합법 수가 넷) — 여기서 다시 세지 않는다.
    package let showsPromotionSheet: Bool
    /// 판 밑 안내 한 줄(무승부 제안 상태 · 거절 안내 · 읽을 수 없는 판). 시간과 무관한 것만 온다.
    package let statusLine: GamesChessMatchLine?
    /// 판을 그릴 수 있는가(서버 FEN 을 읽었는가).
    package let drawsBoard: Bool
    /// 내 색이 아래인가. 체스는 **내 색이 아래**여야 읽힌다(관전은 백이 아래 — 다른 화면이다).
    package let whiteAtBottom: Bool
    package let plyLine: String
    /// 시간 규칙 + 폰에서 처음 쓰는 사실("앱을 닫아도 시계는 계속 흘러요"). ★ 숫자는 **서버가 준 값**에서
    /// 조립한다(총시간은 로비 `initialMs`, 가산은 행의 `increment_ms`) — 10-12 에 5분이 10분으로 늘었다.
    package let clockLine: String
    package let result: Result?

    /// [기권]을 화면이 뜬 직후에는 받지 않는다(실수로 판돈을 잃는다 — 오목 `GomokuPhoneResignGuard` 와 같은 1초).
    package static let resignArmDelay: TimeInterval = 1.0

    package static func acceptsResignTap(shownAt: Date?, now: Date) -> Bool {
        guard let shownAt else { return true }
        return now.timeIntervalSince(shownAt) >= resignArmDelay
    }

    /// - Parameter initialMs: 서버가 말한 **한 사람 총시간**(로비 `initial_ms` — 아직 로비를 못 읽었으면
    ///   코어 기본값 `ChessClock.initialMs`). 가산은 이 판의 행에서 온 `match.clock.incrementMs` 를 쓴다.
    package init(match: ChessMatchState, promotion: ChessPromotionPrompt?, notice: String?,
                 isBusy: Bool, isRobotMatch: Bool, initialMs: Int) {
        self.isRobotMatch = isRobotMatch
        showsStake = !isRobotMatch
        stake = match.stake
        stakeSuffix = isRobotMatch ? nil : GamesChessText.stakeGainSuffix(match.stake)
        showsPromotionSheet = promotion != nil
        drawsBoard = match.position != nil
        whiteAtBottom = match.myColor == .white
        plyLine = GamesChessText.plyLine(match.plyCount)
        clockLine = GamesChessText.clockPhrase(initialMs: initialMs, incrementMs: match.clock.incrementMs)
            + " · " + GamesChessText.clockKeepsRunning

        if match.isFinished {
            actionRow = .finished(showsPlayAgain: isRobotMatch)
        } else if match.drawOfferedByOpponent {
            actionRow = .answerDrawOffer
        } else {
            // 로봇 판에는 무승부 제안이 없다(합의할 상대가 없다 — 서버 왕복이 아예 안 나간다).
            actionRow = .playing(canOfferDraw: !isRobotMatch && !isBusy && !match.drawOfferedByMe,
                                 canResign: !isBusy)
        }

        if let notice {
            statusLine = GamesChessMatchLine(text: notice, tint: .warn)
        } else if !match.isFinished, match.drawOfferedByOpponent {
            statusLine = GamesChessMatchLine(text: GamesChessText.drawOfferedByOpponent, tint: .warn)
        } else if !match.isFinished, match.drawOfferedByMe {
            statusLine = GamesChessMatchLine(text: GamesChessText.drawOfferedByMe, tint: .quiet)
        } else if match.position == nil {
            statusLine = GamesChessMatchLine(text: GamesChessText.unreadableBoard, tint: .warn)
        } else {
            statusLine = nil
        }

        result = match.isFinished ? Self.makeResult(match: match, isRobotMatch: isRobotMatch) : nil
    }

    private static func makeResult(match: ChessMatchState, isRobotMatch: Bool) -> Result {
        let delta: Int = {
            if let given = match.rubyDelta { return given }
            switch match.outcome {
            case .won?: return match.stake
            case .lost?: return -match.stake
            default: return 0
            }
        }()
        let isDraw = match.outcome == .draw
        let tint: GamesChessMatchTint = {
            switch match.outcome {
            case .won?: return .good
            case .lost?: return .bad
            default: return .quiet
            }
        }()
        // 환불 한 줄은 **무승부일 때만**이고 로봇 판에는 없다(걸린 루비가 없다).
        let note: String? = {
            if isRobotMatch { return GamesChessText.robotNoRecord }
            if isDraw, match.stake > 0 { return GamesChessText.drawRefund(stake: match.stake) }
            return nil
        }()
        // 로봇 판은 **다른 표**를 쓴다(루비·'상대' 어휘가 없다 — 문구 레인의 `robotEndReason`).
        let reason = isRobotMatch ? GamesChessText.robotEndReason(match.endReason, outcome: match.outcome)
                                  : GamesChessText.endReason(match.endReason, outcome: match.outcome)
        return Result(title: GamesChessText.outcomeTitle(match.outcome),
                      reason: reason,
                      tint: tint, rubyDelta: delta,
                      rubyDeltaText: GamesChessText.rubyDelta(delta),
                      showsRubyDelta: !isRobotMatch, rubyNote: note, isDraw: isDraw)
    }

    // MARK: 시간을 받는 둘 — **잎 뷰 전용**(규약 ⑥)

    /// 차례 한 줄. `now` 를 받는 자리는 잎 뷰의 TimelineView 안이다.
    ///
    /// ★ 깃발 판정은 `ChessMatchState.isFlagOverdue(now:graceSeconds:)` **하나뿐**이다. 그 함수가 그 사람의
    ///   **남은 유예 예산**(`white_grace_ms`/`black_grace_ms`)을 먼저 쓰고, 부등호도 서버와 같다(`>`).
    ///   `graceSecondsFallback`(= 로비의 전역 `grace_ms`)은 서버가 그 칸을 **안 줬을 때만**(옛 응답) 쓰이는
    ///   폴백이다. 여기서 손으로 비교하거나 전역 값을 직접 쓰면, 예산을 다 쓴 사람의 판은 서버에서 벌써 끝났는데
    ///   화면이 최대 2초를 더 "상대 차례 · 0.0" 으로 그린다.
    package static func turnLine(match: ChessMatchState, now: Date, graceSecondsFallback: TimeInterval,
                                 isRobotThinking: Bool = false) -> GamesChessMatchLine {
        if match.isFinished {
            return GamesChessMatchLine(text: GamesChessText.outcomeTitle(match.outcome),
                                       tint: match.outcome == .won ? .good : (match.outcome == .lost ? .bad : .quiet))
        }
        if match.isFlagOverdue(now: now, graceSeconds: graceSecondsFallback) {
            return GamesChessMatchLine(text: GamesChessText.flagSettling, tint: .warn)
        }
        if isRobotThinking {
            return GamesChessMatchLine(text: GamesChessText.robotThinking, tint: .quiet)
        }
        if match.isInCheck {
            return GamesChessMatchLine(text: match.isMyTurn ? GamesChessText.inCheck
                                                            : GamesChessText.opponentInCheck, tint: .bad)
        }
        return match.isMyTurn ? GamesChessMatchLine(text: GamesChessText.myTurn, tint: .good)
                              : GamesChessMatchLine(text: GamesChessText.opponentTurn, tint: .quiet)
    }

    /// 시계 한 칸의 글자·뜻. **값을 세지 않는다** — 서버가 준 네 칸에서 파생한 초를 글자로만 옮긴다.
    package static func clockFace(seconds: Double, isTurn: Bool) -> GamesChessMatchLine {
        let tint: GamesChessMatchTint
        if !isTurn {
            tint = .quiet
        } else if seconds <= 10 {
            tint = .bad
        } else if seconds <= 30 {
            tint = .warn
        } else {
            tint = .good
        }
        return GamesChessMatchLine(text: GamesChessText.clock(seconds), tint: tint)
    }

    package static func clockAccessibility(seconds: Double, color: ChessColor) -> String {
        GamesChessText.clockAccessibility(seconds, color: color)
    }

    // MARK: 판에 줄 한 변

    /// 판 레인이 정한 한 변(`GamesChessBoardMetrics.side(fitting:)`)을 **글자가 커질 때만** 줄인다.
    ///
    /// 오목에서 데인 자리다(w15 검증 medium 6): 큰 글자에서는 플레이어 카드 두 장이 훨씬 높아져 판과
    /// '내 차례 · 남은 시간' 이 한 화면에 들어가지 못했다. 대국에서 가장 중요한 상태(차례·시계)가 판보다
    /// 먼저다. 기본 글자에서는 **판 레인 값을 한 픽셀도 건드리지 않는다**.
    package static func boardSide(laneDefault: CGFloat, visible: CGSize,
                                  isLargeText: Bool, isAccessibilitySize: Bool) -> CGFloat {
        guard isLargeText, visible.height > 0 else { return laneDefault }
        let fraction: CGFloat = isAccessibilitySize ? 0.40 : 0.52
        return max(240, min(laneDefault, (visible.height * fraction).rounded()))
    }
}

#if os(iOS)

// MARK: - 대국 화면

/// 1:1 체스 대국·결과 한 화면(시안 B 09 오목 대국 문법): 상대 카드 → 판 → 내 카드 → 기보 → 동작 줄.
/// 끝난 판은 **판을 그대로 두고** 위에 결과 카드가 선다(마지막 수가 보인다 — 인수인계 §7).
///
/// `me` 는 게임 탭이 아는 내 얼굴·이름이다. 안 주면 기본 얼굴로 접힌다(로봇 판·비로그인도 둘 수 있다 — §6-12).
struct GamesChessMatchView: View {
    let store: ChessStore
    var me: GamesMeIdentity?

    /// 이 화면(이 판)이 나타난 시각 — [기권] 누름 가드의 기준.
    @State private var shownAt: Date?
    @State private var confirmsResign = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let match = store.match {
            matchBody(match: match, chrome: chrome(match))
        }
    }

    private func chrome(_ match: ChessMatchState) -> GamesChessMatchChrome {
        GamesChessMatchChrome(match: match, promotion: store.promotion, notice: store.notice,
                              isBusy: store.isBusy, isRobotMatch: store.isAIMatch,
                              initialMs: store.initialMs)
    }

    private func matchBody(match: ChessMatchState, chrome: GamesChessMatchChrome) -> some View {
        GeometryReader { screen in
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space2) {
                    if let result = chrome.result {
                        GamesChessResultCard(result: result, me: me, myColor: match.myColor)
                    }
                    GamesChessPlayerCard(
                        store: store, name: match.opponent.displayName, center: match.opponent.center,
                        characterID: match.opponent.characterID,
                        mood: match.opponent.isWorking ? .working : .off,
                        isMe: false, isRobot: chrome.isRobotMatch, color: match.myColor.opponent,
                        isTurn: !match.isFinished && match.turn == match.myColor.opponent)
                    board(match: match, chrome: chrome, visible: screen.size)
                    GamesChessPlayerCard(
                        store: store, name: me?.name ?? GamesChessText.me, center: nil,
                        characterID: me?.characterID, mood: me?.mood ?? .plain,
                        isMe: me?.name != nil, isRobot: false, color: match.myColor,
                        isTurn: !match.isFinished && match.turn == match.myColor)
                    GamesChessTurnLeaf(store: store)
                    if let line = chrome.statusLine {
                        footLine(line, weight: .semibold)
                    }
                    GamesChessMoveList(moves: match.moves)
                    footLine(GamesChessMatchLine(text: chrome.plyLine, tint: .quiet))
                    Label(chrome.clockLine, systemImage: "clock")
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                    actionRow(match: match, chrome: chrome)
                        .padding(.top, MobileTheme.space1)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space1)
                .padding(.bottom, MobileTheme.space4)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                GamesNavTitle(title: GamesChessText.title) {
                    if chrome.showsStake {
                        GamesStakeLine(stake: chrome.stake, prefix: GamesChessText.stakeTitle,
                                       suffix: chrome.stakeSuffix, gemSize: 13)
                    } else {
                        Label(GamesChessText.robotStakeChip, systemImage: "cpu")
                    }
                }
            }
        }
        .onAppear { shownAt = store.clock() }
        .onChange(of: match.id) { _, _ in
            shownAt = store.clock()
            confirmsResign = false
        }
        // 승격 시트: 떠 있는 조건은 **코어의 승격 단계**(`store.promotion`)다 — 화면이 2단을 다시 세지 않는다.
        //
        // ★ **닫는 길을 여기서 만들지 않는다.** 시트가 `interactiveDismissDisabled` 이고 그 안의 닫는 길 둘이
        //   모두 `store.cancelPromotion()` 을 지난다(문구·시트 레인 확정). 그래서 이 묶음의 setter 는 **아무
        //   일도 하지 않는다** — 승격을 고르지 않고 빠져나가는 두 번째 길을 만들면 그 길로 나간 폰은
        //   고르기만 사라진 채 수가 영원히 안 나간다.
        .sheet(isPresented: Binding(get: { chrome.showsPromotionSheet }, set: { _ in })) {
            if let prompt = store.promotion {
                GamesChessPromotionSheet(store: store, prompt: prompt, myColor: match.myColor)
            }
        }
        // 확인은 **불투명 시트**로(오목이 데인 자리 — 확인 대화상자는 iOS 26 에서 위쪽 말풍선으로 떠
        // [계속 두기]가 안 보였고, 알림창은 재질이 색을 빨아들여 대비가 1.9:1 이었다).
        .sheet(isPresented: $confirmsResign) {
            AingConfirmSheet(
                title: GamesChessText.resignConfirmTitle,
                message: chrome.isRobotMatch ? GamesChessText.robotResignConfirmMessage
                                             : GamesChessText.resignConfirmMessage(stake: chrome.stake),
                confirmTitle: GamesChessText.resignNow,
                cancelTitle: GamesChessText.keepPlaying,
                onConfirm: {
                    confirmsResign = false
                    Task { await store.resign() }
                },
                onCancel: { confirmsResign = false })
        }
        .sensoryFeedback(match.outcome == .won ? .success : .warning, trigger: match.isFinished)
    }

    // MARK: 판

    /// 판 한 장. ★ `position` 은 **서버가 확인한 국면**이고, 갈 수 있는 칸은 코어가 합쳐 둔 `match.legalMoves`
    /// 에서 온 `store.selection` 이다 — 이 화면은 합법 수를 만들지 않고 낙관적으로 고치지도 않는다.
    ///
    /// 판은 **스스로 크기를 정한다**(판 레인: `GeometryReader` + `aspectRatio(1, .fit)`) — 여기서 하는 일은
    /// 네모난 공간을 주는 것뿐이고, 그 한 변만 글자 크기에 따라 줄인다(오목에서 받은 교훈: 큰 글자에서
    /// 카드 둘이 높아져 판과 '내 차례' 가 한 화면에 안 들어갔다).
    /// 접근성은 판이 내는 최소 한 줄을 **바깥에서 덮는다**(여기가 수·차례·체크를 더 안다 — 판 레인의 당부).
    ///
    /// ★ 말이 미끄러지는 애니메이션(`store.flight`)은 **배선이 `windowDidShow()` 를 부른 뒤에만** 온다 —
    ///   코어 `beginFlight` 가 창 가시성으로 막는다. 이 화면은 그 깃발을 켜지 않는다(배선 레인 소유).
    @ViewBuilder
    private func board(match: ChessMatchState, chrome: GamesChessMatchChrome, visible: CGSize) -> some View {
        if chrome.drawsBoard {
            let side = GamesChessMatchChrome.boardSide(
                laneDefault: GamesChessBoardMetrics.side(fitting: visible), visible: visible,
                isLargeText: typeSize >= .xLarge, isAccessibilitySize: typeSize.isAccessibilitySize)
            GamesChessBoard(position: match.position, flight: store.flight,
                            whiteAtBottom: chrome.whiteAtBottom, selection: store.selection?.from,
                            legalTargets: store.selection?.targets ?? [], lastMove: match.lastMove,
                            onTapSquare: { square in Task { await store.tap(square) } })
                .frame(width: side, height: side)
                .shadow(color: colorScheme == .dark ? .black.opacity(0.35)
                                                    : Color(red: 80 / 255, green: 50 / 255, blue: 10 / 255).opacity(0.18),
                        radius: 9, y: 6)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(GamesChessText.boardAccessibility(
                    ply: match.plyCount, turn: match.turn, inCheck: match.isInCheck))
        }
    }

    // MARK: 동작 줄

    @ViewBuilder
    private func actionRow(match: ChessMatchState, chrome: GamesChessMatchChrome) -> some View {
        switch chrome.actionRow {
        case .finished(let showsPlayAgain):
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { lobbyButton; if showsPlayAgain { playAgainButton(fillsWidth: false).fixedSize() } }
                VStack(spacing: 10) { if showsPlayAgain { playAgainButton(fillsWidth: true) }; lobbyButton }
            }
        case .answerDrawOffer:
            HStack(spacing: 10) {
                AingButton(GamesChessText.acceptDraw, kind: .filled, size: .md, fillsWidth: true) {
                    Task { await store.respondDraw(accept: true) }
                }
                .disabled(store.isBusy)
                AingButton(GamesChessText.declineDraw, kind: .gray, size: .md, fillsWidth: true) {
                    Task { await store.respondDraw(accept: false) }
                }
                .disabled(store.isBusy)
            }
        case .playing(let canOfferDraw, let canResign):
            HStack(spacing: 10) {
                AingButton(GamesChessText.resign, systemImage: "flag", kind: .destructive, size: .md,
                           fillsWidth: true, role: .destructive) {
                    guard GamesChessMatchChrome.acceptsResignTap(shownAt: shownAt, now: store.clock()) else { return }
                    confirmsResign = true
                }
                .disabled(!canResign)
                if !chrome.isRobotMatch {
                    AingButton(match.drawOfferedByMe ? GamesChessText.drawOfferedByMe
                                                     : GamesChessText.offerDraw,
                               systemImage: "equal.circle", kind: .gray, size: .md, fillsWidth: true) {
                        Task { await store.offerDraw() }
                    }
                    .disabled(!canOfferDraw)
                }
            }
        }
    }

    private var lobbyButton: some View {
        AingButton(GamesChessText.backToLobby, kind: .gray, size: .md, fillsWidth: true) {
            store.backToLobby()
        }
    }

    private func playAgainButton(fillsWidth: Bool) -> some View {
        AingButton(GamesChessText.playAgain, systemImage: "arrow.clockwise", kind: .filled, size: .md,
                   fillsWidth: fillsWidth) {
            store.restartAIMatch()
        }
    }

    private func footLine(_ line: GamesChessMatchLine, weight: Font.Weight = .regular) -> some View {
        Text(line.text)
            .font(.footnote.weight(weight))
            .foregroundStyle(GamesChessInk.color(line.tint))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 색 옮김

/// 표의 **뜻**을 폰 토큰으로 옮기는 한 자리(뷰에 색 리터럴을 적지 않는다 — 토큰 규칙).
enum GamesChessInk {
    static func color(_ tint: GamesChessMatchTint) -> Color {
        switch tint {
        case .good: return MobileTheme.working
        case .bad: return MobileTheme.danger
        case .warn: return MobileTheme.pending
        case .quiet: return MobileTheme.label2
        }
    }

    static func dot(_ tint: GamesChessMatchTint) -> Color {
        switch tint {
        case .good: return MobileTheme.workingDot
        case .bad: return MobileTheme.danger
        case .warn: return MobileTheme.pendingDot
        case .quiet: return MobileTheme.offWorkDot
        }
    }
}

// MARK: - 두 사람 카드

/// 플레이어 한 장: 얼굴 · 이름(+ 센터 · '나') · 색 점 + 색 이름 · **자기 시계**. 차례인 카드만 초록 테두리.
/// 시계가 **둘** 있는 것이 오목과 가장 다른 점이다 — 둘이 같은 값을 보이면 한쪽이 안 그려진 것이다.
struct GamesChessPlayerCard: View {
    let store: ChessStore
    let name: String
    let center: String?
    let characterID: String?
    let mood: CharacterMood
    let isMe: Bool
    let isRobot: Bool
    let color: ChessColor
    let isTurn: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous)
        HStack(spacing: MobileTheme.space3) {
            CharacterPortrait(id: characterID, mood: mood, size: 44,
                              badge: .stone(isBlack: color == .black))
            VStack(alignment: .leading, spacing: 1) {
                PersonName(name, center: CenterLabel.serverValue(forDisplay: center), isMe: isMe)
                HStack(spacing: 5) {
                    Circle()
                        .fill(color == .white ? Color.white : Color.black)
                        .overlay(Circle().strokeBorder(MobileTheme.label3, lineWidth: 1))
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(GamesChessText.stoneName(color))
                        .font(MobileTheme.rowSubtitle)
                        .foregroundStyle(MobileTheme.label2)
                    if isRobot {
                        Image(systemName: "cpu")
                            .font(.caption2)
                            .foregroundStyle(MobileTheme.accent)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .layoutPriority(1)
            Spacer(minLength: 4)
            GamesChessClockLeaf(store: store, color: color, isTurn: isTurn)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(shape.fill(MobileTheme.surface))
        .overlay(shape.strokeBorder(isTurn ? MobileTheme.workingDot : Color.clear, lineWidth: 2))
    }
}

// MARK: - 잎 뷰 둘 (시간을 읽는 **유일한** 자리 — 규약 ⑥)

/// 한쪽 시계. ★ **폰이 세지 않는다**: 서버가 준 네 칸(`white_ms_left`·`black_ms_left`·가산·차례 시작 시각)에서
/// 파생한 초를 글자로 옮길 뿐이고, 이 뷰는 어떤 값도 증감시키지 않는다. 화면이 안 보이면 한 틱도 돌지 않는다.
struct GamesChessClockLeaf: View {
    let store: ChessStore
    let color: ChessColor
    let isTurn: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !store.isWindowVisible || !isTurn)) { context in
            let remaining = store.remainingSeconds(color, now: context.date) ?? 0
            let face = GamesChessMatchChrome.clockFace(seconds: remaining, isTurn: isTurn)
            Text(face.text)
                .font(MobileTheme.number(.title3, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(GamesChessInk.color(face.tint))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isTurn ? MobileTheme.fill : MobileTheme.fill2))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(GamesChessMatchChrome.clockAccessibility(seconds: remaining, color: color))
        }
    }
}

/// 차례 한 줄(내 차례 · 체크 · 결과 확인 중). 깃발+유예 판정이 시간에 달려 있어 잎 뷰다.
struct GamesChessTurnLeaf: View {
    let store: ChessStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !store.isWindowVisible)) { context in
            if let match = store.match {
                let line = GamesChessMatchChrome.turnLine(
                    match: match, now: context.date, graceSecondsFallback: store.graceSeconds,
                    isRobotThinking: store.isAIThinking)
                Text(line.text)
                    .font(MobileTheme.rowTitle)
                    .foregroundStyle(GamesChessInk.color(line.tint))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - 기보

/// 기보 한 줄(가로 스크롤). 세로 스크롤 안에 세로 스크롤을 두면 손가락이 둘 중 하나를 뺏긴다 —
/// 수가 늘어나는 쪽은 가로다. SAN 은 **서버가 만든 것**을 그대로 쓴다(앱이 다시 만들면 두 벌이 갈린다).
struct GamesChessMoveList: View {
    let moves: [ChessMoveRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(GamesChessText.movesTitle)
                .font(MobileTheme.chip)
                .foregroundStyle(MobileTheme.label2)
            if moves.isEmpty {
                Text(GamesChessText.noMoves)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(moves) { record in
                                moveChip(record)
                                    .id(record.seq)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: moves.last?.seq) { _, last in
                        guard let last else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .trailing) }
                    }
                    .onAppear {
                        if let last = moves.last?.seq { proxy.scrollTo(last, anchor: .trailing) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(GamesChessText.movesTitle)
    }

    private func moveChip(_ record: ChessMoveRecord) -> some View {
        let isLast = record.seq == moves.last?.seq
        return HStack(spacing: 3) {
            if record.color == .white {
                Text("\((record.seq + 1) / 2).")
                    .font(MobileTheme.chip)
                    .foregroundStyle(MobileTheme.label3Text)
            }
            Text(record.san)
                .font(MobileTheme.number(.footnote, weight: isLast ? .bold : .regular))
                .foregroundStyle(isLast ? MobileTheme.label : MobileTheme.label2)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isLast ? MobileTheme.accentTint : MobileTheme.fill))
    }
}

// MARK: - 결과 카드

/// 승/패/무 · 끝난 이유 · 루비 변화. 판은 **그대로 아래 남는다**(마지막 수가 보인다).
struct GamesChessResultCard: View {
    let result: GamesChessMatchChrome.Result
    let me: GamesMeIdentity?
    let myColor: ChessColor

    var body: some View {
        InsetGroup {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    portrait
                    texts
                    Spacer(minLength: 6)
                    if result.showsRubyDelta { rubyDelta }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) { portrait; Spacer(minLength: 6); if result.showsRubyDelta { rubyDelta } }
                    texts
                }
            }
            .padding(MobileTheme.cardPadding)
        }
        .accessibilityElement(children: .combine)
    }

    private var portrait: some View {
        CharacterPortrait(id: me?.characterID, mood: me?.mood ?? .plain, size: 60,
                          badge: .stone(isBlack: myColor == .black))
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(result.title)
                .font(MobileTheme.title(.title2))
                .foregroundStyle(GamesChessInk.color(result.tint))
                .fixedSize()
            Text(result.reason)
                .font(.subheadline)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
            if let note = result.rubyNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rubyDelta: some View {
        HStack(spacing: 4) {
            RubyIcon(size: 24)
                .opacity(result.rubyDelta < 0 ? 0.5 : 1)
            Text(result.rubyDeltaText)
                .font(MobileTheme.number(.title2, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(result.rubyDelta > 0 ? MobileTheme.working
                                 : (result.rubyDelta < 0 ? MobileTheme.danger : MobileTheme.label))
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("루비 \(result.rubyDeltaText)")
    }
}

// MARK: - ★ 자리표시 — 다른 레인이 내놓으면 **이 절을 통째로 지운다**
//
// 약속된 이름·서명 그대로 비워 뒀다(`private` 이라 레인 파일이 들어와도 내 파일 밖으로 새지 않는다).
// 지울 때 호출부는 한 줄도 안 바뀐다.
//  · `GamesChessBoard(position:flight:whiteAtBottom:selection:legalTargets:lastMove:onTapSquare:)` — 판 레인
//    (세 겹 Canvas + `TimelineView(.animation(…, paused: flight == nil))` · 인수인계 §5)
//  · `GamesChessBoardMetrics.side(fitting:)` — 판 한 변
//  · `GamesChessPromotionSheet(store:prompt:myColor:)` — 승격 고르기 시트(문구·시트 레인 확정 서명).
//    말 그림은 공용 `ChessPieceArt` 가 올라오는 중이라 여기서는 FEN 글자로 세워 뒀다.

private struct GamesChessBoard: View {
    let position: ChessPosition?
    let flight: ChessMoveFlight?
    let whiteAtBottom: Bool
    let selection: ChessSquare?
    let legalTargets: Set<ChessSquare>
    let lastMove: ChessMove?
    let onTapSquare: (ChessSquare) -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(MobileTheme.fill)
    }
}

private enum GamesChessBoardMetrics {
    static func side(fitting size: CGSize) -> CGFloat {
        max(240, min(size.width - 24, size.height * 0.52).rounded())
    }
}

/// ★ 자리표시. 진짜 시트는 **닫는 길 둘이 모두** `store.cancelPromotion()` 을 지나고
/// `interactiveDismissDisabled` 라 손가락으로 쓸어 내릴 수 없다 — 그 둘이 이 시트의 계약이다.
private struct GamesChessPromotionSheet: View {
    let store: ChessStore
    let prompt: ChessPromotionPrompt
    let myColor: ChessColor

    var body: some View {
        VStack(spacing: MobileTheme.space3) {
            Text(GamesChessText.promotionTitle)
                .font(.headline)
                .foregroundStyle(MobileTheme.label)
            HStack(spacing: MobileTheme.space3) {
                ForEach(prompt.choices, id: \.rawValue) { kind in
                    Button {
                        Task { await store.choosePromotion(kind) }
                    } label: {
                        Text(String(ChessPiece(myColor, kind).fenCharacter))
                            .font(.title)
                            .frame(width: 56, height: 56)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(MobileTheme.fill))
                    }
                    .accessibilityLabel(kind.rawValue)
                }
            }
            AingButton(GamesChessText.keepPlaying, kind: .gray, fillsWidth: true) {
                store.cancelPromotion()
            }
        }
        .padding(MobileTheme.cardPadding)
        .presentationDetents([.height(220)])
        .interactiveDismissDisabled()
    }
}

#endif
