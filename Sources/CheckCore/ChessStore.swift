import Foundation
import Observation
import OSLog

// 1:1 체스 대결 스토어(v0.3.44) — 화면 상태 · 서버 동기화 · 안전망 폴링 · RPC 호출.
//
// 본은 `GomokuStore` 다. **같은 규약을 그대로 베끼고**(아래 ①~⑥) 체스에서 달라지는 자리만 바꿨다 — 오목이
// 피를 흘려 얻은 규약을 체스에서 다시 배우지 않기 위해서다.
//
// ── 베낀 규약 여섯 ──
//  ① **서버가 권위다.** 판(FEN)·차례·시계·결과·루비는 전부 RPC 응답으로만 바뀐다. 낙관적 착수·낙관적 차감은 없다.
//     ★ 체스에서 한 겹 더: **"둘 수 있는 칸"도 서버가 준 `legal_moves` 로만 그린다**(아래 ⑦).
//  ② **시각은 서버 시계로 보정한다.** 차례 시작·신청 만료는 서버 epoch ms 로 오고, 같은 응답의 `server_now_ms`
//     와의 차이로 기기 시계 어긋남을 지운다(`serverClockOffset`).
//  ③ **폴링은 창이 보일 때만 돈다**(무료 플랜 예산). 주기 판정은 `pollTick(at:)` 한 곳이다.
//  ④ **늦게 온 응답은 버린다.** 세대 **셋**을 쓴다: `resetGeneration`(로그아웃·계정 전환은 `host.sessionGeneration`
//     까지 함께 본다) · `watchRuntime.watchGeneration`(관전) · `aiRuntime.generation`(AI 계산).
//  ⑤ **사용자 문구는 `ChessNoticeText` 한 곳에만 있다.** status 이름·서버·동기화 같은 진단 어휘는 화면에 안 싣는다.
//  ⑥ **초 단위 값은 창의 잎 뷰만 읽는다.** `remainingSeconds(_:now:)` 는 잎 뷰 TimelineView 가 `now` 를 넘겨 부르는
//     **순수 계산**이고 이 스토어는 매초 아무것도 대입하지 않는다(팝오버 무효화 계약).
//
// ── 체스에서 바뀐 자리 ──
//  ⑦ **합법 수의 주인이 서버다.** 1:1 판의 하이라이트는 `legal_moves`(내 차례일 때만 온다)를 걸러 그린다 —
//     클라가 `ChessRules.legalMoves` 로 만들어 그리면 "앱은 둘 수 있다는데 서버가 거절한다" 가 생긴다.
//     **AI 판은 정반대다**: 로컬 판이 권위이므로 거기서는 `ChessRules` 가 하이라이트까지 만든다(ChessStoreAI.swift).
//  ⑧ **입력이 2단**이다(말 고르기 → 도착 칸, 승격이면 한 단 더). 그 상태(`selection`·`promotion`)를 **뷰가 아니라
//     스토어가** 든다 — 뷰 `@State` 에 두면 늦게 온 판 갱신과 어긋나 "선택은 e2 인데 판은 이미 다음 수" 가 된다.
//  ⑨ **시계는 클라가 보간한다.** 서버가 준 `white_ms_left`·`black_ms_left`·`turn_started_ms` 로 흘러가는 초를 **계산**하고
//     1초마다 다시 묻지 않는다. 그리고 **서버 응답이 올 때마다 통째로 덮어쓴다** — 클라 시계는 표시용이고
//     권위가 아니다(`ChessServerClock` 머리말).
//  ⑩ **자동 착수 장치가 없다**(B4 — 시간 소진 = 패배). 오목의 `autoPoints`·`autoAbandonStreak`·`.abandoned` 계열
//     다섯 뭉치는 체스에 없고, 대신 `timeout`·`timeout_insufficient` 가 산다.
//  ⑪ **별도 받은함 RPC 가 없다.** 받은·보낸 신청은 로비 `me` 의 두 id 로 알고, 그 id 로 `chess_state` 를 불러
//     상대·판돈·만료를 받는다(pending 판도 참가자에게는 상태를 준다) — `applyState` 가 **한 경로로** 둘을 가른다.

// MARK: - 호스트

/// 체스 스토어가 네트워크·세션·루비 미러를 빌리는 곳.
///
/// 오목(`GomokuStoreHost`)과 **멤버가 같아 그 프로토콜을 그대로 요구한다.** 같은 소유자(맥 `WorkTimerStore`)가
/// 두 게임의 호스트이므로, 멤버를 베껴 적은 두 번째 프로토콜을 두면 소유자가 같은 것을 두 번 적합시켜야 하고
/// 한쪽이 언젠가 빠진다. 체스가 읽을 멤버가 늘어나는 날 갈라라(그때는 갈라야 하는 이유가 생긴 것이다).
package typealias ChessStoreHost = GomokuStoreHost

// MARK: - 화면 값 타입

package nonisolated enum ChessStake: Int, CaseIterable, Sendable { case three = 3, five = 5, ten = 10 }

package nonisolated struct ChessUser: Identifiable, Equatable, Sendable {
    package let id: String                 // user uuid 소문자
    package let displayName: String
    package let avatarURL: String?
    package let characterID: String?
    package let isWorking: Bool
    /// 상대 앱이 체스를 아는 버전인가(서버 `chess_capable`). **모르면 불가**다.
    package let isCapable: Bool
    /// 지금 대국 중인가. 서버는 **오목 판까지** 본다(B8 — 한 사람은 한 판만).
    package let inMatch: Bool
    /// 소속 센터의 **화면 글자**("서울"/"부산"). 서버 어휘 → 글자 변환은 경계 둘(`peerUser`·`user(from:)`)뿐이다.
    /// **기본값이 있는 채로 맨 끝에 둔다** — 멤버와이즈 초기화를 쓰는 테스트가 그대로 컴파일돼야 한다.
    package var center: String? = nil

    package init(id: String, displayName: String, avatarURL: String?, characterID: String?,
                 isWorking: Bool, isCapable: Bool, inMatch: Bool, center: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.characterID = characterID
        self.isWorking = isWorking
        self.isCapable = isCapable
        self.inMatch = inMatch
        self.center = center
    }
}

package nonisolated struct ChessRecord: Equatable, Sendable {
    package let wins: Int
    package let losses: Int
    package let draws: Int

    package init(wins: Int, losses: Int, draws: Int) {
        self.wins = wins
        self.losses = losses
        self.draws = draws
    }
}

package nonisolated struct ChessInvite: Identifiable, Equatable, Sendable {
    package let id: String                 // match id
    package let peer: ChessUser
    package let stake: Int
    /// 기기 시계로 보정된 만료 시각.
    package let expiresAt: Date

    package init(id: String, peer: ChessUser, stake: Int, expiresAt: Date) {
        self.id = id
        self.peer = peer
        self.stake = stake
        self.expiresAt = expiresAt
    }
}

/// 판이 끝난 사유. 서버 `chess_matches.end_reason` CHECK 의 열 글자 그대로다.
///
/// `timeout` 과 `timeoutInsufficient` 가 **갈려 있는 것이 계약이다**: 둘 다 깃발로 끝난 판이지만 앞은 패배,
/// 뒤는 FIDE 6.9 무승부다(상대에게 메이트할 기물이 없다). 하나로 합치면 "무승부 ⟺ 무승부 사유" iff 가 깨진다.
package nonisolated enum ChessEndReason: String, Sendable, CaseIterable {
    case checkmate
    case resign
    case timeout
    case timeoutInsufficient = "timeout_insufficient"
    case stalemate
    case fiftyMove = "fifty_move"
    case threefold
    case insufficientMaterial = "insufficient_material"
    case agreement
    /// 계정 삭제로 둘 수 없게 된 판. **기권과 뜻이 다르다** — 화면이 default 갈래로 떨어뜨리면 남는 사람이
    /// 왜 이겼는지 모른다(서버 주석의 당부).
    case abandoned

    /// 이 사유가 무승부인가. **서버 CHECK 의 여섯과 같은 집합**이다 — 한쪽만 고치면 '외통 무승부' 가 통과한다.
    package var isDraw: Bool {
        switch self {
        case .stalemate, .fiftyMove, .threefold, .insufficientMaterial, .agreement, .timeoutInsufficient:
            return true
        case .checkmate, .resign, .timeout, .abandoned:
            return false
        }
    }
}

/// **내 기준** 결과. `ChessRules.outcome` 이 내는 `ChessOutcome`(외통·사국·50수…)과 **다른 축**이다 —
/// 그쪽은 "판이 어떻게 끝났나" 이고 이쪽은 "나는 이겼나" 다. 이름이 겹치면 한쪽을 다른 쪽에 넣는 사고가 나므로 갈라 둔다.
package nonisolated enum ChessMatchOutcome: Equatable, Sendable { case won, lost, draw }

package nonisolated enum ChessPhase: Equatable, Sendable { case lobby, playing, result }

/// 수 기록 한 줄(화면 기보 · 왕복 검산 재료). `seq` 가 곧 id 다 — 서버가 판마다 1부터 매긴다.
package nonisolated struct ChessMoveRecord: Identifiable, Equatable, Sendable {
    package let seq: Int
    package let color: ChessColor
    package let move: ChessMove
    /// 서버가 만든 SAN. **앱이 다시 만들지 않는다**(두 벌이 갈리면 기보가 두 가지로 보인다) —
    /// 같은 답이 나오는지는 픽스처 계약이 되묻는다.
    package let san: String
    /// 그 수를 둔 **뒤**의 FEN.
    package let fen: String
    /// 그 수를 둔 뒤 **그 사람의** 남은 ms(피셔 가산 포함).
    package let msLeft: Int
    /// 그 수에 쓴 ms.
    package let msSpent: Int

    package var id: Int { seq }

    package init(seq: Int, color: ChessColor, move: ChessMove, san: String, fen: String,
                 msLeft: Int, msSpent: Int) {
        self.seq = seq
        self.color = color
        self.move = move
        self.san = san
        self.fen = fen
        self.msLeft = msLeft
        self.msSpent = msSpent
    }
}

/// 서버가 말한 시계 네 값 + **클라 보간**(5분 + 한 수 3초 가산, A3).
///
/// ★ **이 값은 표시용이고 권위가 아니다.** 서버 응답이 올 때마다 `applyState` 가 네 칸을 통째로 덮어쓴다 —
///   클라가 센 초를 기준선으로 삼아 '서버 값보다 적으면 유지' 같은 보정을 넣으면, 기기가 잠들었다 깨어난 뒤
///   화면 시계가 서버보다 많이 남은 채로 굳고 사용자는 **남았다고 믿는 시간에 깃발이 떨어진다**.
///   깃발 판정도 여기서 하지 않는다(서버가 `chess__clock_charge` 로 한다) — 이 타입은 "몇 초 남았다고 그릴까" 만 안다.
package nonisolated struct ChessServerClock: Equatable, Sendable {
    package var whiteMsLeft: Int
    package var blackMsLeft: Int
    /// 한 수 가산(ms, 3000). 서버 상수를 베끼지 않고 응답에서 받는다.
    package var incrementMs: Int
    /// 차례가 시작된 시각(기기 시계 보정 후). 시계가 흐르지 않으면(끝난 판 · AI 판 일시정지) nil.
    package var turnStartedAt: Date?
    /// 지금 시간이 흐르는 쪽. 끝난 판·멈춘 시계는 nil.
    package var running: ChessColor?

    package init(whiteMsLeft: Int, blackMsLeft: Int, incrementMs: Int,
                 turnStartedAt: Date?, running: ChessColor?) {
        self.whiteMsLeft = whiteMsLeft
        self.blackMsLeft = blackMsLeft
        self.incrementMs = incrementMs
        self.turnStartedAt = turnStartedAt
        self.running = running
    }

    package static let initial = ChessServerClock(
        whiteMsLeft: 300_000, blackMsLeft: 300_000, incrementMs: 3_000, turnStartedAt: nil, running: nil)

    package func msLeft(_ color: ChessColor) -> Int { color == .white ? whiteMsLeft : blackMsLeft }

    /// 보간하지 않은 남은 초 — **음수가 될 수 있다**(깃발이 떨어진 뒤로 얼마나 지났는가). 되묻기 판정이 이것을 쓴다.
    package func rawRemainingSeconds(_ color: ChessColor, now: Date) -> Double {
        let stored = Double(msLeft(color)) / 1000
        guard running == color, let started = turnStartedAt else { return stored }
        return stored - now.timeIntervalSince(started)
    }

    /// 화면에 그릴 남은 초(0 아래로 안 간다). **잎 뷰만 부른다**(규약 ⑥).
    package func remainingSeconds(_ color: ChessColor, now: Date) -> Double {
        max(0, rawRemainingSeconds(color, now: now))
    }

    /// 차례 마감(기기 시계). 시계가 멈춰 있으면 nil. 서버 `deadline_ms` 와 **같은 값**이라 그 키를 읽지 않는다 —
    /// 같은 사실을 두 칸에 들고 있으면 언젠가 둘이 갈린다.
    package var deadline: Date? {
        guard let running, let started = turnStartedAt else { return nil }
        return started.addingTimeInterval(Double(msLeft(running)) / 1000)
    }
}

/// 대국 한 판의 화면 상태.
package nonisolated struct ChessMatchState: Identifiable, Equatable, Sendable {
    package let id: String
    package var stake: Int
    package var myColor: ChessColor
    package var opponent: ChessUser
    /// 서버 `match.fen` 그대로(권위, B5).
    package var fen: String
    /// 그 FEN 을 읽은 국면. **nil 이면 판을 그릴 수 없다**(서버 FEN 이 깐깐한 파서를 통과하지 못했다 — 서버 버그다).
    /// 그래도 판을 내리지 않는 까닭: 끝난 판의 **결과와 루비**는 판을 못 읽어도 사용자가 봐야 한다.
    /// 대신 `legalMoves` 가 비어 선택·착수가 전부 막힌다(읽을 수 없는 판에서 수를 보내지 않는다).
    package var position: ChessPosition?
    package var plyCount: Int
    /// 끝나면 nil. 서버는 끝난 판에도 FEN 에서 파생한 `turn` 을 싣지만 그때는 뜻이 없다.
    package var turn: ChessColor?
    package var lastMove: ChessMove?
    package var moves: [ChessMoveRecord]
    package var clock: ChessServerClock
    /// 차례인 쪽이 체크인가. 끝난 판은 서버가 null 을 주므로 false 다.
    package var isInCheck: Bool
    /// **서버가 준** 합법 수(내 차례일 때만 채워진다). AI 판에서는 로컬 `ChessRules` 가 채운다.
    package var legalMoves: [ChessMove]
    package var isFinished: Bool
    package var outcome: ChessMatchOutcome?
    package var endReason: ChessEndReason?
    /// 이 판으로 내 루비가 변한 양(승 +stake, 패 −stake, 무 0).
    package var rubyDelta: Int?
    /// 무승부를 제안한 사람의 uuid(없으면 nil).
    package var drawOfferBy: String?
    /// 내가 제안했는가(= 상대의 응답을 기다린다).
    package var drawOfferedByMe: Bool
    /// 서버가 말한 **남은 유예 예산**(ms, 판·사람당 1회). 응답에 그 칸이 없으면 nil — `isFlagOverdue` 가 유일한 소비자다.
    package var whiteGraceMs: Int?
    package var blackGraceMs: Int?
    /// 상대가 제안했는가(= 내가 받거나 거절한다).
    package var drawOfferedByOpponent: Bool { drawOfferBy != nil && !drawOfferedByMe }

    /// 지금 내 차례인가(진행 중 + 차례가 내 색).
    package var isMyTurn: Bool { !isFinished && turn == myColor }

    /// 차례쪽 깃발이 떨어지고 **유예까지** 지났는가. 지났으면 조회 한 번이 서버에 신고한다(서버가 정산한다).
    /// 끝난 판은 false — 되묻을 것이 없다.
    ///
    /// ★ 서버 유예는 **판·사람당 1회 예산**이고 `chess_matches.white_grace_ms`/`black_grace_ms` 에서 깎여
    ///   없어진다(duel.sql §4.x `chess__clock_charge` · `chess_grace_ms()` 주석). 깃발 규칙은
    ///   `흐른 시간 − 남은 시간 > 그 사람의 **남은** 예산` 이다. 로비의 전역 `grace_ms`(2,000)는 **판이 시작될 때의
    ///   값**일 뿐이라, 그것만 쓰면 예산을 이미 다 쓴 사람의 판은 서버에서 벌써 끝났는데 앱은 최대 2초를 더
    ///   기다리고 그 사이 "상대 차례 · 0.0" 을 그린다(서버와 클라의 깃발 모형이 갈린다).
    ///   `graceSeconds` 는 **그 두 칸이 없을 때만**(옛 서버 응답) 쓰는 폴백이다.
    package func isFlagOverdue(now: Date, graceSeconds: TimeInterval) -> Bool {
        guard !isFinished, let turn else { return false }
        let budget = graceSecondsLeft(turn) ?? graceSeconds
        // 부등호도 서버와 **같다**(`v_over > v_grace`) — `>=` 로 두면 정확히 같은 순간에 클라만 깃발을 본다.
        return -clock.rawRemainingSeconds(turn, now: now) > budget
    }

    /// 그 사람에게 **남은** 유예 예산(초). 서버가 그 칸을 안 줬으면 nil.
    package func graceSecondsLeft(_ color: ChessColor) -> TimeInterval? {
        guard let ms = color == .white ? whiteGraceMs : blackGraceMs else { return nil }
        return max(0, Double(ms) / 1000)
    }

    package init(id: String, stake: Int, myColor: ChessColor, opponent: ChessUser, fen: String,
                 position: ChessPosition?, plyCount: Int, turn: ChessColor?, lastMove: ChessMove?,
                 moves: [ChessMoveRecord], clock: ChessServerClock, isInCheck: Bool,
                 legalMoves: [ChessMove], isFinished: Bool, outcome: ChessMatchOutcome?,
                 endReason: ChessEndReason?, rubyDelta: Int?, drawOfferBy: String?,
                 drawOfferedByMe: Bool, whiteGraceMs: Int? = nil, blackGraceMs: Int? = nil) {
        self.id = id
        self.stake = stake
        self.myColor = myColor
        self.opponent = opponent
        self.fen = fen
        self.position = position
        self.plyCount = plyCount
        self.turn = turn
        self.lastMove = lastMove
        self.moves = moves
        self.clock = clock
        self.isInCheck = isInCheck
        self.legalMoves = legalMoves
        self.isFinished = isFinished
        self.outcome = outcome
        self.endReason = endReason
        self.rubyDelta = rubyDelta
        self.drawOfferBy = drawOfferBy
        self.drawOfferedByMe = drawOfferedByMe
        self.whiteGraceMs = whiteGraceMs
        self.blackGraceMs = blackGraceMs
    }
}

/// 로비 "지금 대결 중" 한 건(관전 입구). **판 내용이 없다** — 서버가 `fen`·`ply_count` 를 아예 싣지 않는다.
/// a/b 는 uuid 오름차순이고 **색이 아니다**(색은 `chess_watch` 의 black_user/white_user 만 안다).
package nonisolated struct ChessLiveMatch: Identifiable, Equatable, Sendable {
    package let id: String
    package let a: ChessUser
    package let b: ChessUser
    package let stake: ChessStake
    package let startedAt: Date

    package init(id: String, a: ChessUser, b: ChessUser, stake: ChessStake, startedAt: Date) {
        self.id = id
        self.a = a
        self.b = b
        self.stake = stake
        self.startedAt = startedAt
    }
}

// MARK: 입력 2단 (⑧)

/// 고른 말과 그 말이 갈 수 있는 칸. **스토어가 든다**(뷰 `@State` 가 아니다 — 머리말 ⑧).
package nonisolated struct ChessSelection: Equatable, Sendable {
    package let from: ChessSquare
    /// 도착 칸 집합. 1:1 판은 서버 `legal_moves` 를 거른 것이고 AI 판은 로컬 `ChessRules` 의 것이다.
    package let targets: Set<ChessSquare>

    package init(from: ChessSquare, targets: Set<ChessSquare>) {
        self.from = from
        self.targets = targets
    }
}

/// 폰이 8랭크(흑은 1랭크)에 닿아 **네 말 중 하나를 골라야 하는** 단계. 고르기 전에는 수가 나가지 않는다.
/// 상태로 들고 있는 까닭은 선택과 같다 — 뷰에 두면 늦게 온 판 갱신과 어긋난다.
package nonisolated struct ChessPromotionPrompt: Equatable, Sendable {
    package let from: ChessSquare
    package let to: ChessSquare
    /// 고를 수 있는 말(Q R B N — `ChessPieceKind.promotionChoices` 순서 그대로).
    package var choices: [ChessPieceKind] { ChessPieceKind.promotionChoices }

    package init(from: ChessSquare, to: ChessSquare) {
        self.from = from
        self.to = to
    }
}

/// 판을 눌렀는데 수가 안 나간 **이유**. 여기서 갈라 둘로 나간다: 사용자에게 `ChessNoticeText.tapRefusal(_:)`
/// 한 줄, 진단에 `Logger` 한 줄. rawValue 는 **로그 어휘**다(사람 이름·판 내용과 무관한 고정 문자열).
///
/// 오목이 데인 자리를 그대로 피한다: 거절을 뷰·스토어의 `guard` 한 줄씩에 뭉쳐 두면 전부 무음이 되고,
/// 그러면 "눌렀는데 반응이 없다" 의 원인을 가를 값이 아무 데도 없다.
package nonisolated enum ChessTapRefusal: String, CaseIterable, Sendable {
    case notYourTurn = "not-your-turn"
    case busy
    /// 빈 칸을 처음 눌렀다(고를 말이 없다).
    case emptySquare = "empty-square"
    /// 상대 말을 눌렀다(고를 수 없다).
    case notMyPiece = "not-my-piece"
    /// 고른 말이 갈 수 없는 칸이다.
    case illegalTarget = "illegal-target"
    case finished
    case signedOut = "signed-out"
    /// 들고 있는 판이 없다. **말하지 않는다** — 판이 없으면 볼 화면도 없다(로그만).
    case noMatch = "no-match"
    /// 서버가 준 FEN 을 읽을 수 없어 판정할 수 없다(서버 버그 — 사용자에게는 일반 안내).
    case unreadableBoard = "unreadable-board"
}

/// 창이 안 보이는 사람에게 "지금 둘 차례" 를 알리는 한 건. 같은 (판 id, ply) 에는 한 번만 만든다.
package nonisolated struct ChessAttention: Equatable, Sendable {
    package enum Kind: Equatable, Sendable { case matchStarted, myTurn }

    package let kind: Kind
    package let matchID: String
    package let opponentName: String
    package let plyCount: Int

    package init(kind: Kind, matchID: String, opponentName: String, plyCount: Int) {
        self.kind = kind
        self.matchID = matchID
        self.opponentName = opponentName
        self.plyCount = plyCount
    }
}

// MARK: - 문구 표 (사용자 어휘 — 이 표 밖에서 문구를 만들지 마라)

/// 체스 안내 한 줄의 **유일한 출처**. status → 문구 변환이 흩어지면 같은 거절이 화면마다 다른 말을 한다.
/// 진단 어휘(서버·상태·동기화·프로토콜)는 쓰지 않는다 — 사용자가 **할 수 있는 일**을 말한다.
package nonisolated enum ChessNoticeText {
    package static let tryAgain = "잠시 후 다시 시도해 주세요"
    package static let checkConnection = "연결을 확인하고 다시 시도해 주세요"
    package static let updateMine = "앱을 업데이트해야 대결할 수 있어요"
    package static let signInAgain = "다시 로그인해 주세요"
    package static let notYourTurn = "상대 차례예요"
    package static let inviteTimedOut = "상대가 응답하지 않았어요"
    /// 보낸 신청이 만료 전에 사라졌다(거절·취소·상대가 다른 대국을 시작함 — 사용자에게는 모두 같은 뜻이다).
    package static let inviteDeclined = "상대가 신청을 받지 않았어요"
    package static let finishedInvite = "이미 끝난 신청이에요"
    package static let finishedMatch = "이미 끝난 대국이에요"
    /// 고른 말이 갈 수 없는 칸이다.
    package static let cannotMove = "둘 수 없는 자리예요"
    /// 앞 착수·기권이 아직 왕복 중이라 잠긴 동안 또 눌렀다. "기다려라" 가 아니라 **지금 무슨 일이 일어나는지**를 말한다.
    package static let sending = "보내는 중이에요"
    package static let busy = "이미 진행 중인 대국이 있어요"
    package static let targetBusy = "상대가 다른 대국 중이에요"
    /// 서버가 내 수를 거절했다(합법 수가 아니다). 판을 다시 받아 그린다 — 보통 화면이 한 수 뒤처져 있었다.
    package static let illegalMove = "지금은 둘 수 없는 수예요"
    /// 시계 밀림으로 수를 못 받았다(`retry`). **시간패가 아니다** — 다시 누르면 된다.
    package static let moveNotCounted = "다시 한 번 눌러 주세요"

    // 무승부 제안(체스에만 있는 왕복 — 오목에는 대응물이 없다).
    /// 내가 제안했다.
    package static let drawOffered = "무승부를 제안했어요"
    /// 상대가 이미 제안해 둔 상태다(내 제안이 상대 제안을 덮지 않는다).
    package static let drawOfferPending = "상대가 먼저 무승부를 제안했어요"
    /// 내가 상대 제안을 거절했다.
    package static let drawDeclinedByMe = "무승부 제안을 거절했어요"
    /// 받을 제안이 없다(그사이 사라졌다 — 어느 쪽이 한 수 두면 제안은 지워진다).
    package static let drawOfferGone = "무승부 제안이 사라졌어요"

    // 관전.
    /// 볼 수 없는 판(끝난 지 오래됐거나 숨김 격리). 서버는 있다/없다를 가르지 않는다.
    package static let watchGone = "지금은 볼 수 없는 판이에요"
    /// 서버에 체스가 아직 없다(PGRST202 — 배포 중간 창). status 가 아니라 throw 로 오는 실패다.
    package static let unavailable = "체스는 곧 열려요"

    /// 신청 결과. v0.3.44 서버는 근무 조건이 없다(`not_working` 계열을 내지 않는다) — 클라가 근무를 보고
    /// 미리 막는 선게이트를 만들지 마라(오목이 그 선게이트를 지운 자리다).
    package static func challenge(_ status: ChessRPCStatus, need: Int? = nil, have: Int? = nil) -> String {
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

    package static func cancel(_ status: ChessRPCStatus) -> String {
        switch status {
        case .ok: return "신청을 취소했어요"
        case .notFound, .notPending, .expired: return finishedInvite
        default: return common(status)
        }
    }

    /// 수락·거절 결과. **수락 성공은 판이 곧바로 열리므로 말하지 않는다**(nil).
    package static func respond(
        accept: Bool, _ status: ChessRPCStatus, side: String? = nil, need: Int? = nil, have: Int? = nil
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

    /// 착수 결과. **성공과 `stale` 은 말하지 않는다**(nil) — 판이 바뀐 것은 곧바로 다시 불러와 화면이 답한다.
    package static func move(_ status: ChessRPCStatus) -> String? {
        switch status {
        case .ok, .stale: return nil
        case .illegal: return illegalMove
        case .retry: return moveNotCounted
        case .notYourTurn: return notYourTurn
        case .notActive, .notFound: return finishedMatch
        default: return common(status)
        }
    }

    /// 기권 결과. 성공은 결과 화면이 말한다(nil).
    /// 서버는 기권보다 **깃발을 먼저** 신고하므로, 이미 시간을 다 쓴 판은 timeout 으로 닫히고 `not_active` 가 온다.
    package static func resign(_ status: ChessRPCStatus) -> String? {
        switch status {
        case .ok: return nil
        case .notActive, .notFound: return finishedMatch
        default: return common(status)
        }
    }

    /// 무승부 제안 결과.
    package static func offerDraw(_ status: ChessRPCStatus) -> String? {
        switch status {
        case .ok: return drawOffered
        case .offerPending: return drawOfferPending
        case .notActive, .notFound: return finishedMatch
        default: return common(status)
        }
    }

    /// 무승부 응답 결과. **수락 성공은 결과 화면이 말한다**(nil).
    package static func respondDraw(accept: Bool, _ status: ChessRPCStatus) -> String? {
        switch status {
        case .ok: return accept ? nil : drawDeclinedByMe
        case .noOffer: return drawOfferGone
        case .notActive, .notFound: return finishedMatch
        default: return common(status)
        }
    }

    /// 탭 거절 한 줄. nil 이면 **말할 것이 없다**. 나머지는 전부 이미 있는 문구를 **다시 쓴다** —
    /// 같은 사실이 화면마다 다른 말을 하면 그게 곧 다음 조사거리다.
    package static func tapRefusal(_ refusal: ChessTapRefusal) -> String? {
        switch refusal {
        case .notYourTurn: return notYourTurn
        case .busy: return sending
        case .emptySquare: return nil          // 빈 칸을 헛누른 것 — 혼내지 않는다
        case .notMyPiece: return nil           // 상대 말을 눌러 본 것 — 같은 이유로 조용하다
        case .illegalTarget: return cannotMove
        case .finished: return finishedMatch
        case .signedOut: return signInAgain
        case .noMatch: return nil
        case .unreadableBoard: return tryAgain
        }
    }

    private static func common(_ status: ChessRPCStatus) -> String {
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
package final class ChessStore {
    // MARK: 주기 상수

    /// ★ **주기의 하한(= 가장 잦은 주기의 상한)**. 무료 플랜 예산이라 어떤 분기도 이보다 짧게 두지 마라.
    ///
    /// 근거(2026-10-05 산수): 5분+3초 블리츠 한 판은 길어도 약 12분이다. 1초 주기면 대국자 한 사람당
    /// 720회·판당 1,440회이고, 거기에 관전자가 붙으면 2초 주기로 사람당 360회가 더해진다. 0.5초 루프에서
    /// 이보다 짧게 두면 **루프의 매 걸음이 요청**이 되어(= 120회/분) 관전·순위까지 합친 동시 대국 몇 판에
    /// 무료 플랜이 버티지 못한다. 아래 두 상수는 전부 이 하한을 지나 나온다(`statePollSeconds(subscribed:)`).
    package nonisolated static let statePollFloorSeconds: TimeInterval = 1.0

    /// 상대 차례의 상태 조회 주기(초) — 실시간 구독 중. **오목의 3초보다 촘촘하다**(규약 ⑨ 의 사정):
    /// 한 수가 2~3초로 끝나는 블리츠에서 3초 주기는 "상대가 벌써 뒀고 내 시계가 2.5초 흐른" 상태를 평범하게 만든다.
    package nonisolated static let statePollSecondsWhileSubscribed: TimeInterval = 1.5
    /// 같은 조회 — 미구독(킬스위치·재연결 중). 신호가 없으니 하한까지 당긴다.
    package nonisolated static let statePollSecondsUnsubscribed: TimeInterval = 1.0

    /// 지금 쓸 상태 조회 주기. **하한을 지나서만 나온다** — 상수를 잘못 줄여도 여기서 막힌다(주석이 아니라 코드다).
    package nonisolated static func statePollSeconds(subscribed: Bool) -> TimeInterval {
        max(statePollFloorSeconds, subscribed ? statePollSecondsWhileSubscribed : statePollSecondsUnsubscribed)
    }

    /// 보낸 신청이 떠 있을 때 그 판의 상태를 보는 주기(초). 수락이면 같은 id 가 `active` 로 바뀌어 오므로
    /// **조회 하나가 수락·거절·만료를 다 알려 준다**(머리말 ⑪).
    package nonisolated static let outgoingPollSeconds: TimeInterval = 5
    /// 로비 목록 재조회 주기(초).
    package nonisolated static let lobbyPollSeconds: TimeInterval = 30
    /// 팝오버를 열 때 로비를 다시 읽는 **스로틀**(초). 신청 TTL 이 60초이므로 그보다 짧다 —
    /// 팝오버를 연 사람은 배너에서 수락할 수 있어야 하고, 더 잦게 읽으면 팝오버를 여닫는 것만으로 요청이 샌다.
    package nonisolated static let menuLobbyThrottleSeconds: TimeInterval = 30
    /// 관전 중 판 재조회 주기(초).
    package nonisolated static let watchPollSeconds: TimeInterval = 2
    /// 로비를 보고 있는 동안 순위표 재조회 주기(초).
    package nonisolated static let rankingPollSeconds: TimeInterval = 60
    /// 창 열기와 창 표시가 같은 조회를 두 번 쏘지 않게 하는 간격(초).
    package nonisolated static let reloadDedupeSeconds: TimeInterval = 1
    /// 서버 시계 오프셋을 다시 재는 문턱(초). 왕복 지연 몇 ms 마다 갈면 같은 차례의 마감이 응답마다 달라져
    /// 창 루트가 헛되이 다시 그려진다.
    package nonisolated static let serverClockToleranceSeconds: TimeInterval = 0.25
    /// 같은 신청을 다시 읽었을 때 만료가 이만큼 안쪽으로만 다르면 기존 값을 쓴다(초).
    package nonisolated static let inviteExpiryToleranceSeconds: TimeInterval = 1
    /// 깃발이 떨어진 뒤 이만큼 더 기다렸다가 조회로 신고한다(초). 서버 유예(`grace_ms` 2000)와 같은 눈금 —
    /// 서버가 아직 안 끝낼 판을 되묻지 않기 위한 값이다. 서버가 말해 주면 인스턴스의 `graceSeconds` 가 그 값을 든다.
    package nonisolated static let flagGraceSeconds: TimeInterval = 2
    /// throw 실패(5xx·오프라인)가 이만큼 연속되면 관전을 내리고 연결 안내를 남긴다.
    package nonisolated static let watchFailureLimit = 3

    package nonisolated static let logger = Logger(subsystem: "kingcheck", category: "chess")

    /// 네트워크·세션·루비 미러를 빌리는 곳. **약참조다** — 소유자(`WorkTimerStore`)가 이 스토어를 가진다.
    /// nil 이면 미리보기·렌더 테스트용이라 네트워크를 한 건도 내지 않는다.
    @ObservationIgnored package private(set) weak var host: (any ChessStoreHost)?

    package init(host: (any ChessStoreHost)? = nil) {
        self.host = host
    }

    /// 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다.
    package func attach(host: any ChessStoreHost) {
        self.host = host
    }

    // MARK: 화면 상태

    package var phase: ChessPhase = .lobby
    package var users: [ChessUser] = []
    package var record: ChessRecord?
    package var selectedStake: ChessStake = .three
    /// 받은 신청(서버가 한 번에 하나만 말해 준다 — 로비 `me.incoming_match_id`).
    package var incoming: ChessInvite?
    /// 보낸 신청(부분 유니크 인덱스로 한 사람당 하나뿐이다).
    package var outgoing: ChessInvite?
    package var match: ChessMatchState? {
        didSet {
            if let line = Self.matchTransitionLine(from: oldValue, to: match) {
                Self.logger.notice("\(line, privacy: .public)")
            }
            // 판이 바뀌면 입력 2단은 통째로 접는다(⑧ — 앞 판의 선택이 새 판의 칸을 가리키면 그게 사고다).
            if oldValue?.id != match?.id || oldValue?.plyCount != match?.plyCount {
                if selection != nil { selection = nil }
                if promotion != nil { promotion = nil }
            }
            // AI 판은 `match` 가 그 id 를 들고 있는 동안만 산다 — 1:1 판이 열리거나 판이 내려가면 버린다.
            if let game = aiGame, match?.id != game.id { discardAIGame() }
            // 내 판이 섰으면(끝난 판 포함) 관전은 내려간다. 세대를 올려 나가 있던 관전 응답도 함께 버린다.
            if match != nil, spectating != nil {
                spectating = nil
                watchRuntime.bumpWatchGeneration()
            }
        }
    }
    /// 지금 AI 대국(로컬 판이 권위 — ChessStoreAI.swift).
    package internal(set) var aiGame: ChessAIGame?
    /// AI 갈래 장부(선택기·작업·세대). 관찰 대상이 아니다.
    @ObservationIgnored package let aiRuntime = ChessAIRuntime()

    /// 고른 말과 갈 수 있는 칸(⑧).
    package internal(set) var selection: ChessSelection?
    /// 승격 고르기 단계(⑧).
    package internal(set) var promotion: ChessPromotionPrompt?

    // MARK: 애니메이션 — 그림 전용 (v0.3.44)

    /// 지금 판 위에서 **움직이는 중인 수**(없으면 nil). **그림만 읽는다** — 입력·합법성·시계·판정은 이 값을
    /// 한 번도 보지 않으므로, 이 값이 서 있든 nil 이든 `match`·`legalMoves`·`isMyTurn`·시계는 **바이트까지 같다**.
    ///
    /// ★ 여기에 **입력 잠금을 걸지 마라.** 말이 날고 있는 동안에도 `match.position` 과 `legalMoves` 는 이미
    ///   새 것이다(판은 벌써 다음 수의 판이다). 0.2초를 막으면 5분 블리츠에서 빠르게 두는 사람의 수가 씹힌다.
    package private(set) var flight: ChessMoveFlight?
    /// 애니메이션 꼬리표. **늦게 깬 옛 Task 가 새 애니메이션을 지우지 못하게** 하는 유일한 장치다.
    ///
    /// ★ `beginFlight` 는 앞 Task 를 취소하는데 `try? await Task.sleep` 은 취소를 **삼키고 다음 줄로 내려간다**
    ///   (던지지 않는다). 그래서 취소된 Task 도 몸통을 한 번 실행하고, 이 비교가 없으면 그 한 번이 방금 세운
    ///   애니메이션을 지운다 — 빠르게 두는 판에서 두 수째부터 애니메이션이 한 프레임만 보이고 사라진다.
    ///   `Task.isCancelled` 를 **같이 보지 않는 것도 일부러다**: 두 벌을 두면 꼬리표 비교가 아무것도 막지 않는
    ///   죽은 가드가 되어, 지워도 전부 초록이 된다.
    @ObservationIgnored private var flightGeneration = 0
    @ObservationIgnored private var flightTask: Task<Void, Never>?

    package var notice: String?
    package var isBusy = false
    package var isWindowVisible = false
    package var isRulesVisible = false
    /// 서버 응답으로만 갱신(host 에도 반영).
    package var rubyBalance: Int?
    /// 서버가 말한 시작 시간·가산·유예(ms). 화면 캡션("5분 + 3초")이 이 값을 읽는다 — 상수를 베끼지 않는다.
    package var initialMs = 300_000
    package var incrementMs = 3_000
    package var graceMs = 2_000
    package var lobbyLoadFailed = false
    package var hasLoadedLobby = false
    /// 로비 "지금 대결 중" 목록. **서버 순서 그대로**(accepted_at desc) — 다시 정렬하면 스토어·뷰 두 규칙이 갈린다.
    package var liveMatches: [ChessLiveMatch] = []

    // MARK: 관전 · 순위 — 저장 프로퍼티만 여기, 로직은 ChessStoreWatch.swift · ChessStoreRanking.swift

    /// **순위 적재·관전 폴링의 주 스위치. 기본 false.** 이 스토어는 폰도 그대로 쓸 공용 타입이라, 창 표시·pollTick 에
    /// 두 조회를 무조건 얹으면 그리지도 않는 폰이 `chess_ranking` 을 1분마다 당긴다(무료 플랜).
    /// 켜는 곳은 맥 배선뿐이고, 꺼져 있으면 두 조회는 한 번도 나가지 않는다.
    ///
    /// ★ 오목은 이 술어(`canPollSpectatorFeatures`)를 **뒤늦게** 모았고 그 사이 깃발 겸업 사고가 났다 —
    ///   체스는 처음부터 한 술어로 모은다(mapB §7-9 의 당부).
    package var spectatorFeaturesEnabled = false
    package var spectating: ChessSpectateState?
    package var ranking: ChessRankingBoard?
    package var rankingLoadFailed = false
    package var hasLoadedRanking = false
    /// 서버에 `chess_ranking` 이 아직 없다(PGRST202).
    package var rankingUnavailable = false
    /// 서버에 `chess_watch` 가 아직 없다. **관전 입구를 잠그는 신호는 이것뿐이다.**
    /// ★ `rankingUnavailable` 과 **따로** 둔다 — 오목에서 한 깃발이 두 소비자를 겸업하다 한쪽을 좁히는 순간
    ///   [관전] 칩 게이트가 조용히 죽었다(2026-10-01 실측). 게이트와 신호는 짝으로 움직인다.
    package var watchUnavailable = false
    /// 관전·순위 장부(요청 시각·in-flight·세대). 관찰 대상이 아니다.
    @ObservationIgnored package let watchRuntime = ChessWatchRuntime()

    package var isSpectating: Bool { spectating != nil }

    /// 순위·관전 조회가 **지금** 나가도 되는가 — 주 스위치 + 창이 보이고 안 가려짐 + 세션.
    /// 두 폴링 분기가 이 한 술어를 쓴다(창 규칙 ③ 을 각자 다시 적으면 한쪽이 언젠가 빠진다).
    package var canPollSpectatorFeatures: Bool {
        spectatorFeaturesEnabled && isWindowVisible && !isWindowOccluded && host?.session != nil
    }

    // MARK: UI 트랙이 CheckApp 에서 물리는 문

    @ObservationIgnored package var presentWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var dismissWindow: (@MainActor () -> Void)?
    @ObservationIgnored package var onInviteArrived: (@MainActor (ChessInvite) -> Void)?
    @ObservationIgnored package var requestAttention: (@MainActor () -> Void)?
    @ObservationIgnored package var onAttention: (@MainActor (ChessAttention) -> Void)?

    // MARK: 내부 장부 (관찰 대상 아님)

    /// 이 스토어의 '지금'. 테스트가 갈아 끼운다.
    @ObservationIgnored package var clock: () -> Date = { Date() }
    /// 폴링 루프의 한 걸음(초). 주기 판정은 `pollTick` 이 하고 이 값은 그 판정을 얼마나 자주 묻는지다.
    @ObservationIgnored package var pollStepSeconds: TimeInterval = 0.5
    /// 서버 시계 − 기기 시계(초).
    @ObservationIgnored package private(set) var serverClockOffset: TimeInterval = 0
    @ObservationIgnored private var hasServerClockOffset = false
    @ObservationIgnored package private(set) var resetGeneration = 0
    /// 창이 다른 창에 완전히 가려졌거나 다른 Space·잠금 화면에 있다. **폴링만** 이 값을 본다.
    @ObservationIgnored package private(set) var isWindowOccluded = false
    @ObservationIgnored package private(set) var stateInFlightID: String?
    @ObservationIgnored private var pendingStateID: String?
    @ObservationIgnored private var stateInFlight = false
    @ObservationIgnored private var stateAgain = false
    @ObservationIgnored private var lobbyInFlight = false
    /// 마지막으로 "내 차례가 왔다" 를 본 (판 id#ply). 같은 차례에 말풍선이 두 번 뜨지 않게 한다.
    @ObservationIgnored private var attentionKey: String?
    @ObservationIgnored package private(set) var shownResultIDs: Set<String> = []
    /// 서버가 말한 내 진행 중 대국 id.
    @ObservationIgnored package private(set) var activeMatchID: String?
    @ObservationIgnored package private(set) var seenInviteIDs: Set<String> = []
    /// [로비로] 로 접은 끝난 판. 늦게 온 그 판의 상태가 사용자를 결과 화면으로 끌고 가지 않게 한다.
    @ObservationIgnored package private(set) var dismissedMatchIDs: Set<String> = []
    @ObservationIgnored package private(set) var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pollToken = 0
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored package var lastStateRequestAt: Date = .distantPast
    @ObservationIgnored package var lastLobbyRequestAt: Date = .distantPast
    /// 신호 재조회 직렬화(오목 `syncTask` 와 같은 규약 — 도는 중이면 뒤따르는 한 번으로 합친다).
    @ObservationIgnored package private(set) var syncTask: Task<Void, Never>?
    @ObservationIgnored private var syncPendingTrailing = false
    /// 팝오버 열기 계기의 마지막 조회 시각(스로틀).
    @ObservationIgnored package var lastMenuLobbyAt: Date = .distantPast
    @ObservationIgnored package var lastOutgoingRequestAt: Date = .distantPast
    @ObservationIgnored private var inviteTTLSeconds: TimeInterval = 60
    /// 이 기기에서 보낸 신청을 새로 세울 때마다 오른다. 그보다 **먼저** 나간 조회 응답이 방금 보낸 신청을 지우지 않게 한다.
    @ObservationIgnored private var outgoingRevision = 0
    @ObservationIgnored private var lobbyRequestOutgoingRevision = 0
    /// 차단으로 걷어낸 상대(소유자가 채운다). **코어 목록은 서버 답 그대로 두고** 화면이 읽는 파생값만 거른다.
    package var hiddenPeerIDs: Set<String> = []

    /// 로비 상대 목록(화면용).
    package var visibleUsers: [ChessUser] {
        hiddenPeerIDs.isEmpty ? users : users.filter { !hiddenPeerIDs.contains($0.id) }
    }

    /// 받은 신청(화면용 — 차단한 사람이 보낸 것은 뺀다).
    package var visibleIncoming: ChessInvite? {
        guard let invite = incoming, !hiddenPeerIDs.contains(invite.peer.id) else { return nil }
        return invite
    }

    /// 지금 서버가 말해 준 유예(초).
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
                if let focus, focus != self.match?.id {
                    await self.refreshMatch(id: focus)
                } else if let current = self.match, !current.isFinished {
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
        if let current = match, !current.isFinished, !isAIMatch,
           now.timeIntervalSince(lastStateRequestAt) >= Self.reloadDedupeSeconds {
            // 창이 안 보이는 동안 시계는 서버에서 흘렀다 — 올라온 순간 한 번 당겨 보간 기준선을 새로 받는다(⑨).
            Task { [weak self] in await self?.refreshMatch(id: current.id) }
        }
        spectatorWindowDidShow(at: now)
    }

    /// 창이 가려졌다·닫혔다·최소화됐다. 폴링만 멈춘다 — **대국은 계속된다**(시간은 서버에서 흐른다).
    ///
    /// ★ **최소화도 이 문을 지난다.** 그래서 "그만 본다" 는 뜻은 `windowDidClose` 로 갈라 뒀다(바로 아래).
    ///   합치면 최소화만 해도 남의 판 관전이 로비로 떨어진다(오목이 폰에서 잡아 넘겨 준 자리).
    package func windowDidHide() {
        if isWindowVisible { isWindowVisible = false }
        isWindowOccluded = false
        // ★ 안 거두면 0.3초 안에 창을 다시 연 사람에게 **끝나던 수의 토막이 다시 미끄러진다**.
        clearFlight()
        stopPolling()
        pauseAIClock()
        // 끝난 판을 관전한 채 닫았다 = 그 판에서 나간 것이다. **진행 중인 관전은 남긴다**(최소화에서도 오는 통지다).
        // 끝난 판은 재조회가 없어 그대로 두면 한 시간 뒤 창을 열어도 로비 대신 낡은 남의 판이 선다.
        if spectating?.isFinished == true { stopWatching() }
    }

    /// 창을 **정말 닫았다**(빨간 점 · 로그아웃의 프로그램 닫기). 최소화·가려짐은 이 문을 지나지 않는다.
    /// 관전만 내린다(요청은 쏘지 않는다). 체스에는 `chess_leave` 가 없어 내 판에 대고 부를 것이 없다.
    package func windowDidClose() {
        if spectating != nil { stopWatching() }
        clearFlight()
    }

    /// 창의 가림 상태가 바뀌었다. **폴링·AI 시계만** 멈추고 되살린다 — `isWindowVisible` 은 건드리지 않는다
    /// (가림 통지가 틀려도 보이는 창의 시계가 멈추면 안 된다).
    package func windowOcclusionDidChange(visible: Bool) {
        isWindowOccluded = !visible
        if visible {
            resumeAIClockIfVisible()
            startPolling()
        } else {
            // ★ 거두는 자리 일곱 번째다. 가려진 창은 그려지지 않으므로 날던 수는 **보여 줄 사람이 없다** —
            //   그대로 두면 꼬리(최대 0.355초)만큼 60~78Hz 그리기를 가림 뒤에서 계속 요구한다.
            //   `pauseAIClock()` **앞**이어야 한다(`windowDidHide` 와 같은 순서 — 뒤에 두면 그 안에서
            //   `commitAIGame` 이 돌며 방금 거둔 것을 다시 세운다).
            clearFlight()
            pauseAIClock()
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
        guard let result = await perform({ try await $0.chessLobby(accessToken: $1) }) else { return }
        switch result {
        case .success(let response):
            await applyLobby(response)
        case .failure(let error):
            if isSchemaMissing(error) {
                Self.logger.notice("lobby unavailable — chess functions missing on server")
                setNotice(ChessNoticeText.unavailable)
            } else {
                Self.logger.notice("lobby request failed")
            }
            // 빈 목록을 "대결할 사람이 없다" 로 믿게 하지 않는다.
            if !lobbyLoadFailed { lobbyLoadFailed = true }
        }
    }

    package func applyLobby(_ response: ChessLobbyResponse) async {
        guard response.status == .ok else {
            Self.logger.notice("lobby refused status=\(response.status.rawValue, privacy: .public)")
            if response.status == .unsupportedClient { setNotice(ChessNoticeText.updateMine) }
            if !lobbyLoadFailed { lobbyLoadFailed = true }
            return
        }
        noteServerNow(response.serverNowMs)
        if lobbyLoadFailed { lobbyLoadFailed = false }
        if !hasLoadedLobby { hasLoadedLobby = true }
        if let value = response.initialMs, value > 0, initialMs != value { initialMs = value }
        if let value = response.incrementMs, value >= 0, incrementMs != value { incrementMs = value }
        if let value = response.graceMs, value >= 0, graceMs != value { graceMs = value }
        if let ttl = response.inviteTtlSeconds, ttl > 0 { inviteTTLSeconds = TimeInterval(ttl) }
        if let me = response.me {
            applyRuby(me.rubyBalance)
            let fresh = ChessRecord(wins: me.wins ?? 0, losses: me.losses ?? 0, draws: me.draws ?? 0)
            if record != fresh { record = fresh }
            activeMatchID = me.activeMatchId?.lowercased()
        }
        if let rows = response.users {
            let mapped = Self.sortedForLobby(rows.compactMap(Self.user(from:)))
            if users != mapped { users = mapped }
        }
        // **서버 순서 그대로**. 키가 아예 없으면(옛 서버) 들고 있던 목록을 지우지 않는다 — 조회 실패와 같은 규약.
        if let rows = response.matches {
            let live = rows.compactMap(liveMatch(from:))
            if liveMatches != live { liveMatches = live }
        }
        await applyLobbyInvites(response.me)
        if let active = activeMatchID, match?.id != active || match?.isFinished == true {
            await refreshMatch(id: active)
        }
    }

    /// 로비 `me` 의 두 신청 id 를 화면 값으로 옮긴다(머리말 ⑪).
    ///
    /// 서버는 id 만 준다 — 상대·판돈·만료는 그 id 로 `chess_state` 를 한 번 더 불러야 안다. 그래서 **id 가
    /// 새로 생겼을 때만** 조회하고, 들고 있는 신청과 같은 id 면 아무 요청도 내지 않는다(무료 플랜).
    private func applyLobbyInvites(_ me: ChessLobbyMe?) async {
        let incomingID = me?.incomingMatchId?.lowercased()
        let outgoingID = me?.outgoingMatchId?.lowercased()
        // 이 응답은 방금 이 기기가 세운 보낸 신청보다 먼저 나갔다 — 그 신청이 없다고 해도 사실이 아니다.
        let predatesOutgoing = lobbyRequestOutgoingRevision < outgoingRevision
        if let gone = outgoing, outgoingID != gone.id, !predatesOutgoing {
            // 보낸 신청이 로비에서 사라졌다. 판으로 이어졌으면(= 수락) 아래 refreshMatch 가 판을 세우고, 그때는
            // 거절 안내를 하지 않는다 — 진행 중 판이 있으면 서버가 내 다른 신청을 거둔 것이지 상대가 거절한 게 아니다.
            let becameMatch = gone.id == activeMatchID || gone.id == match?.id
            if !becameMatch {
                setNotice(gone.expiresAt > clock() ? ChessNoticeText.inviteDeclined : ChessNoticeText.inviteTimedOut)
            }
            outgoing = nil
            scheduleInviteExpiry()
        }
        if incoming != nil, incomingID != incoming?.id {
            incoming = nil
            scheduleInviteExpiry()
        }
        for id in [incomingID, outgoingID].compactMap({ $0 }) {
            guard id != incoming?.id, id != outgoing?.id, id != match?.id else { continue }
            await refreshMatch(id: id)
        }
    }

    package func refreshMatch() async {
        await refreshMatch(id: match?.id ?? activeMatchID)
    }

    /// 한 판(또는 신청)의 상태를 읽는다. 같은 판을 들고 있으면 `p_since_seq` 로 **새 수만** 받고,
    /// 수 번호가 이어지지 않으면 처음부터 한 번 더 받는다. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다.
    ///
    /// 도는 중에 **다른 판** id 가 들어오면 합치지 않고 기억했다가 지금 판이 끝난 뒤 그 판을 한 번 읽는다 —
    /// 합치면 뒤따르는 반복이 앞 판만 다시 읽어, 막 수락된 판이 다음 계기까지 화면에 안 온다.
    package func refreshMatch(id rawID: String?) async {
        // AI 판 id 는 서버에 없다 — 어느 경로로 와도 **여기서** 막는다(열기·로비·폴링이 전부 이 문을 지난다).
        guard let requested = rawID?.lowercased(), !requested.isEmpty,
              !ChessAIGame.isAIMatchID(requested), host?.session != nil else { return }
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
                let since = (!forceFull && match?.id == id) ? (match?.plyCount ?? 0) : 0
                forceFull = false
                lastStateRequestAt = clock()
                if outgoing?.id == id { lastOutgoingRequestAt = lastStateRequestAt }
                let result = await perform({
                    try await $0.chessState(accessToken: $1, matchID: id, sinceSeq: since)
                })
                guard generation == resetGeneration else { return }
                switch result {
                case .success(let response)?:
                    switch response.status {
                    case .ok:
                        if applyState(response.state, requestedSince: since) == .needsFull, since > 0 {
                            forceFull = true
                            stateAgain = true
                        }
                    case .notFound:
                        dropMatchOrInvite(id)
                    case .unsupportedClient:
                        setNotice(ChessNoticeText.updateMine)
                    default:
                        Self.logger.notice("state refused status=\(response.status.rawValue, privacy: .public)")
                    }
                case .failure(let error)?:
                    if isSchemaMissing(error) { setNotice(ChessNoticeText.unavailable) }
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

    package enum StateApplyOutcome: Equatable { case applied, needsFull, ignored }

    /// 서버 상태 묶음을 화면 상태로 옮긴다. **대국과 신청을 한 경로로 가른다**(머리말 ⑪):
    /// `pending` 은 신청이고 `active`/`finished` 는 판이며 그 밖(declined·cancelled·expired)은 둘 다 아니다.
    ///
    /// 수 기록은 `p_since_seq` 뒤만 오므로 들고 있던 목록에 **이어 붙인다**. 번호가 이어지지 않으면
    /// `.needsFull` 을 돌려 처음부터 다시 받게 한다 — 구멍 난 기보를 그리면 기보가 거짓말을 한다.
    /// 판 자체는 `match.fen` 이 권위라 기보에 구멍이 나도 판은 맞다(그게 FEN 한 칸으로 둔 이유다, B5).
    @discardableResult
    package func applyState(_ payload: ChessStatePayload, requestedSince: Int = 0) -> StateApplyOutcome {
        guard let row = payload.match, let id = row.id?.lowercased(), !id.isEmpty else { return .ignored }
        noteServerNow(payload.serverNowMs)
        applyRuby(payload.rubyBalance)
        let status = row.status ?? ""
        switch status {
        case "pending":
            applyInvite(row, payload: payload, id: id)
            return .applied
        case "active", "finished":
            break
        default:
            // 시작하지 못하고 끝난 신청(declined·cancelled·expired) — 판도 아니고 살아 있는 신청도 아니다.
            dropMatchOrInvite(id, notice: status == "expired" ? ChessNoticeText.inviteTimedOut
                                                              : ChessNoticeText.inviteDeclined)
            return .applied
        }

        let isFinished = status == "finished"
        if isFinished, dismissedMatchIDs.contains(id), match?.id != id { return .ignored }

        let myID = host?.session?.userID.lowercased()
        var myColor = ChessColor(rawValue: payload.myColor ?? "")
        if myColor == nil, let myID {
            if row.black?.lowercased() == myID { myColor = .black } else if row.white?.lowercased() == myID { myColor = .white }
        }
        guard let myColor else { return .ignored }

        let base = match?.id == id ? match : nil
        // 같은 판을 진행 중으로 들고 있는데 **수 번호가 줄어든** 응답은 착수보다 먼저 읽힌 옛 스냅숏이 늦게 온 것이다.
        // 그대로 옮기면 방금 둔 수가 사라지고 시계가 한 수 전으로 되돌아간다. 끝난 응답은 예외다(되돌릴 수 없는 사실).
        if let base, !base.isFinished, !isFinished, let serverPly = row.plyCount, serverPly < base.plyCount {
            return .ignored
        }
        // 같은 판을 이미 끝남으로 들고 있으면 진행 중 응답은 전부 끝나기 전에 읽힌 옛 스냅숏이다.
        if let base, base.isFinished, !isFinished { return .ignored }

        let records = Self.moveRecords(from: payload.moves)
        var merged = base?.moves ?? []
        var applied = base?.plyCount ?? 0
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
        let serverPly = row.plyCount ?? applied
        if serverPly != applied, !rebuild { return .needsFull }

        let fen = row.fen ?? base?.fen ?? ""
        let position = ChessPosition(fen: fen)
        if position == nil {
            // 서버가 자기 FEN 을 파싱해 응답을 만들므로 여기 오면 **서버와 앱의 파서가 갈린 것**이다(서버 버그).
            // 판은 못 그려도 결과·루비는 보여 준다(`position` 머리말) — 수는 전부 막힌다.
            Self.logger.notice("state fen rejected by parser")
        }
        let turn = isFinished ? nil : ChessColor(rawValue: row.turn ?? "")
        let clockValue = ChessServerClock(
            // ★ 서버 값으로 **통째로 덮어쓴다**(⑨). 들고 있던 값과 섞지 마라.
            whiteMsLeft: row.whiteMsLeft ?? base?.clock.whiteMsLeft ?? initialMs,
            blackMsLeft: row.blackMsLeft ?? base?.clock.blackMsLeft ?? initialMs,
            incrementMs: row.incrementMs ?? incrementMs,
            turnStartedAt: isFinished ? nil : deviceDate(serverMs: row.turnStartedMs),
            running: turn)
        let outcome: ChessMatchOutcome?
        switch row.result {
        case "draw": outcome = .draw
        case "white_win": outcome = myColor == .white ? .won : .lost
        case "black_win": outcome = myColor == .black ? .won : .lost
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
        let opponentID = (myColor == .white ? row.black : row.white)?.lowercased()
        let opponent = peerUser(payload.opponent, inMatch: !isFinished)
            ?? base?.opponent
            ?? users.first { $0.id == opponentID }
            ?? ChessUser(id: opponentID ?? "", displayName: "", avatarURL: nil, characterID: nil,
                         isWorking: true, isCapable: true, inMatch: !isFinished)
        // **서버가 준 것만** 쓴다(⑦). 끝난 판·상대 차례는 null 이라 빈 배열이 되고, 그러면 선택·착수가 전부 막힌다.
        let legal = position == nil ? [] : (payload.legalMoves ?? []).compactMap(ChessMove.init(uci:))
        let offerBy = row.drawOfferBy?.lowercased()

        let next = ChessMatchState(
            id: id, stake: stake, myColor: myColor, opponent: opponent, fen: fen, position: position,
            plyCount: serverPly, turn: turn, lastMove: merged.last?.move, moves: merged, clock: clockValue,
            isInCheck: payload.inCheck ?? false, legalMoves: legal, isFinished: isFinished,
            outcome: outcome, endReason: row.endReason.flatMap(ChessEndReason.init(rawValue:)),
            rubyDelta: rubyDelta, drawOfferBy: offerBy,
            drawOfferedByMe: offerBy != nil && offerBy == myID,
            // 유예는 **행마다** 실려 온다(판·사람당 1회 예산에서 깎인 잔량). 깃발 되묻기가 이 값을 읽는다.
            whiteGraceMs: row.whiteGraceMs ?? base?.whiteGraceMs,
            blackGraceMs: row.blackGraceMs ?? base?.blackGraceMs)

        let justFinished = isFinished && base?.isFinished == false
        let previous = match
        let windowWasVisible = isWindowVisible
        // 이 판이 신청이었으면 카드를 걷는다(수락된 쪽·내가 수락한 쪽 모두).
        if incoming?.id == id { incoming = nil }
        if outgoing?.id == id { outgoing = nil }
        if match != next { match = next }
        // 한 수 미끄러진다(1:1 깔때기 — 내 수·상대 수·폴링·실시간이 전부 이 한 자리로 모인다).
        // 이전 판은 `base` 가 아니라 **`previous`** 로 잰다: `base` 는 id 가 같을 때만 서는 값이라
        // "판이 바뀌었다" 를 가릴 수 없고, 그러면 화면 전환이 애니메이션으로 둔갑한다.
        beginFlight(matchID: id, previousMatchID: previous?.id, previousPly: previous?.plyCount,
                    previousPosition: previous?.position, nextPly: serverPly,
                    nextPosition: position, move: next.lastMove)
        let nextPhase: ChessPhase = isFinished ? .result : .playing
        if phase != nextPhase { phase = nextPhase }
        activeMatchID = isFinished ? nil : id
        if isFinished { shownResultIDs.insert(id) }
        if !isFinished {
            // 새 판이 열렸다 — 로비에서 남긴 안내("신청을 보냈어요")는 대국 상태줄을 가린다.
            if previous?.id != id || previous?.isFinished == true { setNotice(nil) }
            noteMatchProgress(previous: previous, next: next, windowWasVisible: windowWasVisible)
        }
        if justFinished {
            // 전적은 로비 응답에만 있다. 끝난 순간 한 번 다시 읽어 결과 화면 뒤 로비가 옛 전적을 보이지 않게 한다.
            Task { [weak self] in await self?.refreshLobby() }
            // 순위도 같은 순간 바뀐다 — 로비 전적만 새로 오고 순위가 옛것이면 머리글이 자기모순 문장을 만든다.
            noteOwnMatchFinishedForRanking()
        }
        return .applied
    }

    // MARK: - 애니메이션 (그림 전용)

    /// 판이 **한 수** 나아갔다 — 그 한 수를 미끄러뜨린다.
    ///
    /// 판을 갈아 치우는 깔때기가 셋이고(1:1 `applyState` · 로봇 `commitAIGame` · 관전 `applyWatch`) **셋 다**
    /// 이 문을 지난다. 하나라도 빠지면 그 길로 온 수만 여전히 순간이동하는데, 사용자에게는 "어떤 때는 되고
    /// 어떤 때는 안 된다" 로 보여 재현 조건을 찾는 데만 한참 걸린다.
    ///
    /// 거절 다섯 — **전부 필요하다**:
    ///  ① 창이 안 보이거나 가려졌다. 안 그러면 보이지도 않는 창 때문에 뷰의 `TimelineView` 가 60fps 로 깨어
    ///     배터리를 먹는다(`paused: flight == nil` 이 배터리 계약이고, 그 계약은 여기서 지켜진다).
    ///  ② 판이 다르다. 판이 바뀐 것은 애니메이션이 아니라 **화면 전환**이다.
    ///  ③ 수 번호가 정확히 1 늘지 않았다. 첫 적재(이전 국면 없음)·잠에서 깬 따라잡기(두 수가 한꺼번에)·
    ///     수가 그대로인 폴링 응답이 전부 여기서 떨어진다. 두 수를 한 장으로 미끄러뜨릴 길은 없고, 폴링마다
    ///     다시 세우면 1.5초 주기로 같은 수가 영원히 미끄러진다.
    ///  ④ 수나 전·후 국면이 없다(서버 FEN 이 파서를 통과하지 못했다 — 판 자체를 못 그리는 상태다).
    ///  ⑤ 파생이 nil 이다(수와 국면이 안 맞는다 · 제자리 수). 그러면 판은 지금처럼 **바로** 바뀐다(안전한 폴백).
    func beginFlight(matchID: String, previousMatchID: String?, previousPly: Int?,
                     previousPosition: ChessPosition?, nextPly: Int,
                     nextPosition: ChessPosition?, move: ChessMove?) {
        guard isWindowVisible, !isWindowOccluded else { return }
        guard let previousMatchID, previousMatchID == matchID else { return }
        guard let previousPly, nextPly == previousPly + 1 else { return }
        guard let move, let before = previousPosition, let after = nextPosition else { return }
        // ★ 꼬리표는 **파생이 성공한 뒤에** 올린다. 먼저 올리면 파생이 nil 인 수 하나가 돌고 있는 애니메이션의
        //   Task 를 꼬리표만으로 무력화해(그 Task 는 옛 세대가 된다) 그 애니메이션이 영영 거둬지지 않는다 —
        //   그러면 `TimelineView` 가 60fps 로 계속 돈다.
        let generation = flightGeneration &+ 1
        guard let made = ChessMoveFlight.make(move: move, before: before, after: after,
                                              matchID: matchID, ply: nextPly,
                                              generation: generation, startedAt: clock())
        else { return }
        flightGeneration = generation
        flight = made
        flightTask?.cancel()
        flightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(made.duration))
            // 꼬리표가 밀렸으면 그사이 다음 수가 왔다 — 그 애니메이션은 **내 것이 아니다**.
            guard let self, self.flightGeneration == generation else { return }
            self.flightTask = nil
            self.flight = nil
        }
    }

    /// 애니메이션을 거둔다(Task 도 끊는다). 거두는 자리 여섯이 이 문을 지난다:
    /// `reset()` · `clearMatch()` · `backToLobby()` · 관전 종료(`stopWatching()`) ·
    /// `windowDidClose()` · `windowDidHide()`.
    ///
    /// Task 가 `duration`(길어도 0.355초) 뒤에 스스로 거두므로 이 문이 끊는 것은 **그 짧은 꼬리**다. 그래도
    /// 자리마다 이유가 있다:
    ///  · `windowDidHide` — 안 거두면 0.3초 안에 창을 다시 연 사람에게 **끝나던 수의 토막이 다시 미끄러진다**
    ///    (값이 남아 있고 `TimelineView` 가 그 순간부터 다시 틱을 받는다).
    ///  · `reset()` — 로그아웃·계정 전환. 다음 사람 화면에서 앞 사람 판의 말이 날아가면 안 된다.
    ///  · 나머지 — 화면이 이미 다른 것을 보여 주는데(로비 접기 · 판 내림 · 관전 종료) 값이 남아 있으면
    ///    뷰가 그만큼 더 60fps 로 깨어 있다.
    func clearFlight() {
        flightTask?.cancel()
        flightTask = nil
        if flight != nil { flight = nil }
    }

    // MARK: - 입력 2단 (⑧)

    /// 고른 말이 그 칸으로 갈 수 있는 합법 수들(승격이면 넷). **들고 있는 `legalMoves` 에서만** 찾는다.
    package func legalMoves(from square: ChessSquare, to target: ChessSquare) -> [ChessMove] {
        (match?.legalMoves ?? []).filter { $0.from == square && $0.to == target }
    }

    /// 그 말이 갈 수 있는 칸 전부.
    package func targets(from square: ChessSquare) -> Set<ChessSquare> {
        Set((match?.legalMoves ?? []).filter { $0.from == square }.map(\.to))
    }

    /// 판을 한 번 누른 결과 — **뷰의 유일한 입구**. 2단(고르기 → 도착)과 승격 단계를 여기서 가른다.
    ///
    /// 거절은 전부 이유를 남긴다(무음 `guard` 금지, `ChessTapRefusal` 머리말). 순서가 계약이다:
    /// 왕복 중 → 판 없음 → 끝난 판 → 읽을 수 없는 판 → 내 차례 아님 → (고른 말이 있으면) 도착 칸 →
    /// 내 말 고르기. 순서를 바꾸면 같은 상황이 다른 문구를 말한다.
    package func tap(_ square: ChessSquare) async {
        guard !isBusy else { refuseTap(.busy, at: square); return }
        guard let current = match else { refuseTap(.noMatch, at: square); return }
        guard !current.isFinished else { refuseTap(.finished, at: square); return }
        guard current.position != nil else { refuseTap(.unreadableBoard, at: square); return }
        guard current.isMyTurn else { refuseTap(.notYourTurn, at: square); return }

        // 승격을 고르는 중이면 판 탭은 그 단계를 취소한다(다른 수를 고르려는 뜻이다).
        if promotion != nil { promotion = nil }

        if let selected = selection, selected.from != square {
            if selected.targets.contains(square) {
                await commit(from: selected.from, to: square)
                return
            }
            // 갈 수 없는 칸이다. 거기에 **내 말**이 있으면 고르기를 옮긴다(체스 UI 의 관례) — 아니면 거절한다.
            if let piece = current.position?[square], piece.color == current.myColor {
                select(square)
                return
            }
            refuseTap(.illegalTarget, at: square)
            return
        }

        if selection?.from == square {
            selection = nil                     // 같은 칸을 다시 누르면 고르기 해제
            return
        }
        guard let piece = current.position?[square] else { refuseTap(.emptySquare, at: square); return }
        guard piece.color == current.myColor else { refuseTap(.notMyPiece, at: square); return }
        select(square)
    }

    /// 승격 창에서 말을 골랐다 — 그 수를 보낸다.
    package func choosePromotion(_ kind: ChessPieceKind) async {
        guard let prompt = promotion else { return }
        promotion = nil
        await send(ChessMove(from: prompt.from, to: prompt.to, promotion: kind))
    }

    /// 승격 창을 닫았다(고르기는 남는다 — 다른 칸을 눌러 보려는 뜻이다).
    package func cancelPromotion() {
        if promotion != nil { promotion = nil }
    }

    /// 고르기를 세운다. 갈 수 있는 칸이 없으면 **세우지 않는다**(움직일 수 없는 말을 고른 채로 두면
    /// 다음 탭이 '갈 수 없는 칸' 으로 거절된다 — 사용자는 말을 고른 적도 없는데 혼난다).
    private func select(_ square: ChessSquare) {
        let targets = targets(from: square)
        guard !targets.isEmpty else {
            selection = nil
            refuseTap(.illegalTarget, at: square)
            return
        }
        selection = ChessSelection(from: square, targets: targets)
    }

    /// 도착 칸이 정해졌다. 승격이면 한 단 더 묻고, 아니면 곧바로 보낸다.
    private func commit(from: ChessSquare, to: ChessSquare) async {
        let candidates = legalMoves(from: from, to: to)
        guard !candidates.isEmpty else { refuseTap(.illegalTarget, at: to); return }
        selection = nil
        if candidates.count > 1 || candidates.contains(where: { $0.promotion != nil }) {
            // 같은 칸으로 가는 합법 수가 여럿 = 승격 네 갈래다(체스에 다른 경우는 없다).
            promotion = ChessPromotionPrompt(from: from, to: to)
            return
        }
        await send(candidates[0])
    }

    /// 한 수를 서버(또는 AI 판)로 보낸다.
    package func send(_ move: ChessMove) async {
        guard !isBusy, let current = match, !current.isFinished else { return }
        // AI 판은 위 거절 가드를 **같이** 지난 뒤 로컬 판에 둔다 — 서버로는 안 나간다(로그인 여부도 안 본다).
        if isAIMatch {
            if let refusal = moveInAIMatch(move) { refuseTap(refusal, at: move.to) }
            return
        }
        guard host?.session != nil else { refuseTap(.signedOut, at: move.to); return }
        let id = current.id
        let expected = current.plyCount
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({
            try await $0.chessMove(accessToken: $1, matchID: id, expectedPly: expected, uci: move.uci)
        }) else { return }
        switch result {
        case .failure(let error):
            setNotice(isSchemaMissing(error) ? ChessNoticeText.unavailable : ChessNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(ChessNoticeText.move(response.status))
            if response.status != .ok {
                Self.logger.notice("move refused status=\(response.status.rawValue, privacy: .public)")
            }
            if response.status == .notFound {
                if match?.id == id { clearMatch() }
                return
            }
            var needsRefresh: Bool
            switch response.status {
            // 내 판단이 서버와 갈렸다 — **언제나** 다시 읽는다.
            case .stale, .notYourTurn, .notActive, .illegal, .retry: needsRefresh = true
            default: needsRefresh = false
            }
            if let state = response.state {
                if applyState(state, requestedSince: expected) == .needsFull { needsRefresh = true }
            } else if response.status == .ok {
                needsRefresh = true             // 상태를 안 실어 준 성공(서버 계약상 없지만 모르는 모양은 되묻는다)
            }
            if needsRefresh { await refreshMatch(id: id) }
        }
    }

    // MARK: - 동작

    package func challenge(userID: String) async {
        guard !isBusy, host?.session != nil else { return }
        let target = userID.lowercased()
        let stake = selectedStake.rawValue
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({
            try await $0.chessChallenge(accessToken: $1, opponentID: target, stake: stake)
        }) else { return }
        switch result {
        case .failure(let error):
            setNotice(isSchemaMissing(error) ? ChessNoticeText.unavailable : ChessNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(ChessNoticeText.challenge(response.status, need: response.need, have: response.have))
            if response.status != .ok {
                Self.logger.notice("challenge refused status=\(response.status.rawValue, privacy: .public)")
            }
            switch response.status {
            case .ok:
                guard let id = response.matchId?.lowercased() else { break }
                let peer = users.first { $0.id == target }
                    ?? ChessUser(id: target, displayName: "", avatarURL: nil, characterID: nil,
                                 isWorking: true, isCapable: true, inMatch: false)
                let expiresAt = deviceDate(serverMs: response.inviteExpiresMs)
                    ?? clock().addingTimeInterval(inviteTTLSeconds)
                outgoingRevision &+= 1
                outgoing = ChessInvite(id: id, peer: peer, stake: stake, expiresAt: expiresAt)
                lastOutgoingRequestAt = clock()
                scheduleInviteExpiry()
            case .alreadyPending, .busy:
                await refreshLobby()
            case .targetBusy, .targetOutdated, .targetFocused:
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
        guard let result = await perform({ try await $0.chessCancel(accessToken: $1, matchID: id) }) else { return }
        switch result {
        case .failure(let error):
            setNotice(isSchemaMissing(error) ? ChessNoticeText.unavailable : ChessNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(ChessNoticeText.cancel(response.status))
            switch response.status {
            case .ok, .notFound, .notPending, .expired:
                if outgoing?.id == id {
                    outgoing = nil
                    scheduleInviteExpiry()
                }
                // not_pending 은 취소보다 수락이 먼저 닿았다는 뜻일 수 있다 — 진행 중 판을 찾아 온다.
                if response.status == .notPending { await refreshLobby() }
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
            try await $0.chessRespond(accessToken: $1, matchID: id, accept: accept)
        }) else { return }
        switch result {
        case .failure(let error):
            setNotice(isSchemaMissing(error) ? ChessNoticeText.unavailable : ChessNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(ChessNoticeText.respond(
                accept: accept, response.status, side: response.side,
                need: response.need, have: response.have))
            if response.status != .ok {
                Self.logger.notice("respond refused status=\(response.status.rawValue, privacy: .public)")
            }
            switch response.status {
            case .ok:
                if incoming?.id == id { incoming = nil }
                guard accept else { break }
                // 수락하는 순간 서버가 두 참가자의 **다른 대기 신청을 전부 거둔다** — 로컬 카드를 그대로 두면
                // 다음 로비에서 '상대가 신청을 받지 않았어요' 가 뜬다.
                if outgoing != nil { outgoing = nil }
                if let state = response.state {
                    applyState(state)
                } else {
                    await refreshMatch(id: id)
                }
                // 판이 열리면 `applyState` 가 창을 띄운다(경로와 무관하게 한 곳에서 알린다).
                if match?.id != id, !isWindowVisible { presentWindow?() }
            case .notFound, .notPending, .expired, .invalid:
                if incoming?.id == id { incoming = nil }
            default:
                break
            }
        }
    }

    package func resign() async {
        if isAIMatch {
            resignAIMatch()
            return
        }
        guard !isBusy, let current = match, !current.isFinished, host?.session != nil else { return }
        let id = current.id
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({ try await $0.chessResign(accessToken: $1, matchID: id) }) else { return }
        switch result {
        case .failure(let error):
            setNotice(isSchemaMissing(error) ? ChessNoticeText.unavailable : ChessNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(ChessNoticeText.resign(response.status))
            if let state = response.state { applyState(state) } else { await refreshMatch(id: id) }
        }
    }

    /// 무승부 제안(체스에만 있는 왕복). AI 판에는 없다 — 상대가 사람이 아니면 합의할 것이 없다.
    package func offerDraw() async {
        guard !isBusy, let current = match, !current.isFinished, !isAIMatch,
              host?.session != nil else { return }
        let id = current.id
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({ try await $0.chessOfferDraw(accessToken: $1, matchID: id) }) else { return }
        switch result {
        case .failure(let error):
            setNotice(isSchemaMissing(error) ? ChessNoticeText.unavailable : ChessNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(ChessNoticeText.offerDraw(response.status))
            if let state = response.state { applyState(state) } else { await refreshMatch(id: id) }
        }
    }

    /// 상대의 무승부 제안에 답한다. 수락이면 서버가 각자에게 판돈을 돌려주고 판을 `agreement` 로 닫는다.
    package func respondDraw(accept: Bool) async {
        guard !isBusy, let current = match, !current.isFinished, !isAIMatch,
              host?.session != nil else { return }
        let id = current.id
        isBusy = true
        setNotice(nil)
        let generation = resetGeneration
        defer { if generation == resetGeneration { isBusy = false } }
        guard let result = await perform({
            try await $0.chessRespondDraw(accessToken: $1, matchID: id, accept: accept)
        }) else { return }
        switch result {
        case .failure(let error):
            setNotice(isSchemaMissing(error) ? ChessNoticeText.unavailable : ChessNoticeText.checkConnection)
        case .success(let response):
            noteServerNow(response.serverNowMs)
            applyRuby(response.rubyBalance)
            setNotice(ChessNoticeText.respondDraw(accept: accept, response.status))
            if let state = response.state { applyState(state) } else { await refreshMatch(id: id) }
        }
    }

    /// 결과 화면 [로비로]. **진행 중인 판에서는 아무것도 안 한다** — 빠져나가는 길은 기권뿐이다.
    package func backToLobby() {
        guard let current = match, current.isFinished else { return }
        dismissedMatchIDs.insert(current.id)
        if isAIMatch {
            match = nil                         // 관찰자가 AI 판을 버린다
        } else {
            match = nil
        }
        if phase != .lobby { phase = .lobby }
        clearFlight()
        setNotice(nil)
        guard host?.session != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshLobby()
            await self.loadRanking()
        }
    }

    // MARK: - 신호 · 계기 (창 밖에서 아는 유일한 길)
    //
    // ★ 폴링은 `isWindowVisible` 을 요구한다(규약 ③). 그래서 체스 창이 닫혀/최소화돼 있으면 체스 요청이
    //   **한 건도** 나가지 않는다. 아래 계기들이 없으면:
    //     (가) 받은 신청은 TTL 60초인데 상대가 창을 열어 두지 않으면 신청이 왔다는 사실을 알 길이 전혀 없고
    //          (서버는 `chess_invite` 푸시를 '맥에서 근무 중' 이면 suppressed 로 적는다 — push_pipeline.sql),
    //          신청자는 "상대가 응답하지 않았어요" 를 본다 → 1:1 신청이 사실상 성립하지 않는다.
    //     (나) 진행 중 판에서 창을 닫으면 "내 차례예요" 가 한 번도 안 와서, 체스는 오목의 자동 착수 장치를
    //          전부 버렸으므로(DECISIONS B4 — 시간 소진 = 패배) 5분 시계가 그대로 흘러 판돈을 잃는다.
    //          창 쪽 주석의 "닫기는 기권이 아니다" 는 알림이 없으면 곧 시간패 보장이다.
    //
    //   계기 하나로 모으는 것은 `refreshLobby()` 다 — 그 한 조회가 받은·보낸 신청 id 와 진행 중 판 id 를
    //   함께 말해 주고, 그 뒤를 `applyLobby` 가 `chess_state` 로 채우며 `onInviteArrived`·`onAttention` 을 연다.

    /// 실시간 'chess' 신호. 직렬화된 재조회 — 도는 중이면 뒤따르는 **한 번**으로 합친다(오목 규약 그대로).
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

    /// 신호 한 번의 조회: 진행 중 1:1 판이 있으면 그 판, 아니면 로비(신청 둘 + 진행 중 판 id).
    /// AI 판은 서버에 없다 — 그동안 온 신호는 로비(신청·수락)로 본다.
    package func syncOnce() async {
        if let current = match, !current.isFinished, !isAIMatch {
            await refreshMatch(id: current.id)
        } else {
            await refreshLobby()
        }
    }

    /// 조인 직후·깨어남의 따라잡기: 로비 한 번(+ 그 응답이 가리키는 판).
    /// **`syncOnce` 가 아니다** — 진행 중 판만 읽으면 그 사이 온 신청을 영영 모른다.
    package func catchUp() async {
        await refreshLobby()
    }

    /// 실시간 조인 성공 직후(`WorkTimerStoreRealtime` 의 `.catchUp`).
    package func realtimeDidJoin() {
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.catchUp() }
    }

    /// 깨어남(뚜껑을 열었다). 소켓이 끊겼던 사이에 온 신청·수를 한 번 따라잡는다.
    package func systemDidWake() {
        guard host?.session != nil else { return }
        Task { [weak self] in await self?.catchUp() }
    }

    /// 팝오버 열림(60초 스로틀). `WorkTimerStore.setMenuPresented(true)` 가 부른다 —
    /// 팝오버 배너·메뉴바 점(`visibleIncoming`)의 신선도가 이 계기와 소켓 신호에 달려 있다.
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

    /// 안전망 한 걸음. **창이 안 보이면 아무것도 하지 않는다**(규약 ③).
    ///  · 진행 중 내 판이 상대 차례거나 깃발+유예가 지났으면 `statePollSeconds` 마다 상태
    ///  · 보낸 신청이 있으면 5초마다 그 판의 상태(수락·거절·만료를 한 조회가 다 말한다)
    ///  · 로비를 보고 있으면 30초마다 목록
    ///  · 관전 2초 / 순위 60초(확장이 주 스위치·가림을 본다)
    ///
    /// **분기 사이사이 `isWindowVisible` 을 다시 본다** — await 중에 창이 내려갈 수 있다.
    package func pollTick(at now: Date) async {
        guard isWindowVisible, !isWindowOccluded, host?.session != nil else { return }
        if let current = match, !current.isFinished, !isAIMatch {
            let waiting = current.turn != current.myColor
            let overdue = current.isFlagOverdue(now: now, graceSeconds: graceSeconds)
            if waiting || overdue {
                let subscribed = host?.realtimeState.isSubscribed ?? false
                if now.timeIntervalSince(lastStateRequestAt) >= Self.statePollSeconds(subscribed: subscribed) {
                    await refreshMatch(id: current.id)
                }
            }
        }
        guard isWindowVisible else { return }
        if let sent = outgoing, now.timeIntervalSince(lastOutgoingRequestAt) >= Self.outgoingPollSeconds {
            await refreshMatch(id: sent.id)
        }
        guard isWindowVisible else { return }
        if phase == .lobby, now.timeIntervalSince(lastLobbyRequestAt) >= Self.lobbyPollSeconds {
            await refreshLobby()
        }
        guard isWindowVisible else { return }
        await pollSpectatorFeatures(at: now)
    }

    // MARK: - 초 단위 값 (잎 뷰 전용 — 규약 ⑥)

    /// 한쪽의 남은 시간(초). 잎 뷰 TimelineView 가 `now` 를 넘겨 부르는 **순수 계산**이고,
    /// 이 스토어는 매초 아무것도 대입하지 않는다. AI 판도 같은 문을 쓴다.
    package func remainingSeconds(_ color: ChessColor, now: Date) -> Double? {
        guard let current = match else { return nil }
        return current.clock.remainingSeconds(color, now: now)
    }

    /// 내 시계 · 상대 시계 둘(화면이 시계를 둘 그린다 — 오목은 하나였다).
    package func remainingSecondsPair(now: Date) -> (mine: Double, opponent: Double)? {
        guard let current = match else { return nil }
        return (current.clock.remainingSeconds(current.myColor, now: now),
                current.clock.remainingSeconds(current.myColor.opponent, now: now))
    }

    // MARK: - 리셋

    /// 로그아웃·계정 전환. 창을 닫고 체스 상태를 전부 비운다 — 남기면 다음 사람이 앞 사람의 판·신청·루비를 본다.
    package func reset() {
        resetGeneration &+= 1
        stopPolling()
        discardAIGame()
        clearFlight()
        expiryTask?.cancel()
        expiryTask = nil
        // 신호 재조회도 끊는다 — 앞 계정의 따라잡기가 다음 사람의 화면에 신청·판을 세우면 안 된다.
        syncTask?.cancel()
        syncTask = nil
        syncPendingTrailing = false
        stateInFlight = false
        stateAgain = false
        lobbyInFlight = false
        stateInFlightID = nil
        pendingStateID = nil
        if phase != .lobby { phase = .lobby }
        if !users.isEmpty { users = [] }
        if record != nil { record = nil }
        if selectedStake != .three { selectedStake = .three }
        if incoming != nil { incoming = nil }
        if outgoing != nil { outgoing = nil }
        if match != nil { match = nil }
        if selection != nil { selection = nil }
        if promotion != nil { promotion = nil }
        if notice != nil { notice = nil }
        if isBusy { isBusy = false }
        if isWindowVisible { isWindowVisible = false }
        if isRulesVisible { isRulesVisible = false }
        if rubyBalance != nil { rubyBalance = nil }
        if !hiddenPeerIDs.isEmpty { hiddenPeerIDs = [] }
        if lobbyLoadFailed { lobbyLoadFailed = false }
        if hasLoadedLobby { hasLoadedLobby = false }
        if !liveMatches.isEmpty { liveMatches = [] }
        if spectating != nil { spectating = nil }
        if ranking != nil { ranking = nil }
        if rankingLoadFailed { rankingLoadFailed = false }
        if hasLoadedRanking { hasLoadedRanking = false }
        if rankingUnavailable { rankingUnavailable = false }
        if watchUnavailable { watchUnavailable = false }
        watchRuntime.clear()
        if initialMs != 300_000 { initialMs = 300_000 }
        if incrementMs != 3_000 { incrementMs = 3_000 }
        if graceMs != 2_000 { graceMs = 2_000 }
        serverClockOffset = 0
        hasServerClockOffset = false
        isWindowOccluded = false
        attentionKey = nil
        shownResultIDs = []
        activeMatchID = nil
        seenInviteIDs = []
        dismissedMatchIDs = []
        outgoingRevision = 0
        lobbyRequestOutgoingRevision = 0
        lastStateRequestAt = .distantPast
        lastLobbyRequestAt = .distantPast
        lastOutgoingRequestAt = .distantPast
        lastMenuLobbyAt = .distantPast
        inviteTTLSeconds = 60
        dismissWindow?()
    }

    // MARK: - 내부

    /// 공용 호출 관용구: 세션 가드 → 두 세대 캡처 → withSessionRetry → 두 세대 대조.
    /// nil = 버린 결과(세션 없음·세대가 밀림·취소). 호출부는 nil 이면 **아무것도 바꾸지 않는다.**
    /// `package` 인 이유: 관전·순위 확장이 같은 관용구로 부른다(확장이 따로 만들면 세대 대조가 두 벌이 된다).
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

    /// 서버에 체스 RPC 가 아직 없다(PGRST202 — 앱이 db push 보다 먼저 나간 창).
    package nonisolated func isSchemaMissing(_ error: any Error) -> Bool {
        (error as? SupabaseWorkServiceError) == .databaseSchemaMissing
    }

    /// 신청 한 건을 세운다(`pending` 상태 응답). 받은 것인지 보낸 것인지는 **내가 challenger 인가**로 가른다.
    private func applyInvite(_ row: ChessMatchRow, payload: ChessStatePayload, id: String) {
        guard let myID = host?.session?.userID.lowercased(),
              let stake = row.stake,
              let expiresAt = deviceDate(serverMs: row.inviteExpiresMs),
              let peer = peerUser(payload.opponent, inMatch: false) else { return }
        let invite = ChessInvite(id: id, peer: peer, stake: stake, expiresAt: expiresAt)
        if row.challenger?.lowercased() == myID {
            outgoing = Self.steadyInvite(invite, previous: outgoing)
        } else {
            let fresh = Self.steadyInvite(invite, previous: incoming)
            if incoming != fresh { incoming = fresh }
            if !seenInviteIDs.contains(id) {
                seenInviteIDs.insert(id)
                onInviteArrived?(fresh)
            }
        }
        if match?.id == id { clearMatch() }
        scheduleInviteExpiry()
    }

    /// 그 id 가 판이었으면 판을 내리고, 신청이었으면 신청 카드를 걷는다(안내가 있으면 한 줄).
    private func dropMatchOrInvite(_ id: String, notice: String? = nil) {
        if match?.id == id { clearMatch() }
        if activeMatchID == id { activeMatchID = nil }
        if incoming?.id == id {
            incoming = nil
            scheduleInviteExpiry()
        }
        if outgoing?.id == id {
            outgoing = nil
            if let notice { setNotice(notice) }
            scheduleInviteExpiry()
        }
    }

    /// 같은 신청을 다시 읽었을 때 만료가 문턱 안쪽으로만 다르면 기존 값을 그대로 쓴다(관찰자를 헛되게 깨우지 않게).
    package nonisolated static func steadyInvite(_ fresh: ChessInvite, previous: ChessInvite?) -> ChessInvite {
        guard let previous, previous.id == fresh.id, previous.stake == fresh.stake, previous.peer == fresh.peer,
              abs(previous.expiresAt.timeIntervalSince(fresh.expiresAt)) < inviteExpiryToleranceSeconds
        else { return fresh }
        return previous
    }

    /// 서버 수 기록 → 화면 값(seq 오름차순). 하나라도 모양이 어긋나면 **그 줄만** 버린다 —
    /// 기보 한 줄이 깨졌다고 판 전체를 버리면 판은 `fen` 으로 멀쩡한데 화면이 통째로 비어 버린다.
    package nonisolated static func moveRecords(from rows: [ChessMoveRow]?) -> [ChessMoveRecord] {
        (rows ?? []).compactMap { row -> ChessMoveRecord? in
            guard let seq = row.seq, seq >= 1,
                  let color = ChessColor(rawValue: row.color ?? ""),
                  let fromIndex = row.from, let from = ChessSquare(index: fromIndex),
                  let toIndex = row.to, let to = ChessSquare(index: toIndex) else { return nil }
            let promotion = row.promo.flatMap { text -> ChessPieceKind? in
                guard let letter = text.first,
                      let kind = ChessPieceKind(fenLetter: letter),
                      ChessPieceKind.promotionChoices.contains(kind) else { return nil }
                return kind
            }
            return ChessMoveRecord(
                seq: seq, color: color,
                move: ChessMove(from: from, to: to, promotion: promotion),
                san: row.san ?? "", fen: row.fen ?? "",
                msLeft: row.msLeft ?? 0, msSpent: row.msSpent ?? 0)
        }
        .sorted { $0.seq < $1.seq }
    }

    /// 안내줄 한 문. `package` 인 이유: 관전 확장이 not_found·준비 중 안내를 여기로 흘린다(순위 실패는 절대 부르지 않는다).
    package func setNotice(_ text: String?) {
        if notice != text { notice = text }
    }

    /// 탭 거절 하나를 **두 곳**에 남긴다: 상태줄 한 줄(`notice`)과 진단 한 줄(`Logger`).
    /// 진단 줄에는 **칸 이름과 사유만** 싣는다(닉네임·판 내용·판 id·토큰은 넣지 않는다 — 로그는 제보에 실려 나간다).
    private func refuseTap(_ refusal: ChessTapRefusal, at square: ChessSquare) {
        if let text = ChessNoticeText.tapRefusal(refusal) { setNotice(text) }
        Self.logger.notice("""
            tap refused reason=\(refusal.rawValue, privacy: .public) \
            square=\(square.notation, privacy: .public) \
            turn=\(self.match?.turn?.rawValue ?? "none", privacy: .public) \
            mine=\(self.match?.myColor.rawValue ?? "none", privacy: .public) \
            busy=\(self.isBusy ? "true" : "false", privacy: .public)
            """)
    }

    /// 판 상태 변화 한 줄(없으면 nil). 수·차례·끝남·판 교체만 본다 — 시계·루비는 이 줄을 만들지 않는다.
    package nonisolated static func matchTransitionLine(
        from old: ChessMatchState?, to new: ChessMatchState?
    ) -> String? {
        func turn(_ m: ChessMatchState?) -> String { m?.turn?.rawValue ?? "none" }
        func ply(_ m: ChessMatchState?) -> String { m.map { String($0.plyCount) } ?? "-" }
        func finished(_ m: ChessMatchState?) -> Bool { m?.isFinished ?? false }
        let sameMatch = old?.id == new?.id
        guard !sameMatch || ply(old) != ply(new) || turn(old) != turn(new)
                || finished(old) != finished(new) else { return nil }
        return "state ply=\(ply(old))→\(ply(new)) turn=\(turn(old))→\(turn(new)) "
            + "finished=\(finished(new)) sameMatch=\(sameMatch)"
    }

    private func applyRuby(_ value: Int?) {
        guard let value else { return }
        if rubyBalance != value { rubyBalance = value }
        if let host, host.rubyBalance != value { host.rubyBalance = value }
    }

    package func clearMatch() {
        if match != nil { match = nil }
        if phase != .lobby { phase = .lobby }
        if selection != nil { selection = nil }
        if promotion != nil { promotion = nil }
        clearFlight()
    }

    /// 판 진행을 사람에게 알린다(진행 중 판을 옮긴 직후).
    ///  · 판이 없거나 끝난 판에서 **진행 중 판으로 처음 넘어가면** 창을 띄우고 주의를 끈다 — 신청자는 상대가
    ///    수락한 순간을 모르면 5분 시계를 흘린다.
    ///  · 창이 안 보이는 동안 차례가 나에게 오면 말풍선 문을 연다. 같은 (판 id, ply) 에는 한 번뿐이다.
    private func noteMatchProgress(previous: ChessMatchState?, next: ChessMatchState, windowWasVisible: Bool) {
        let started = previous == nil || previous?.isFinished == true || previous?.id != next.id
        if started {
            presentWindow?()
            requestAttention?()
        }
        guard next.turn == next.myColor else { return }
        let arrived = started || previous?.turn != next.myColor || previous?.plyCount != next.plyCount
        let key = "\(next.id)#\(next.plyCount)"
        guard arrived, attentionKey != key else { return }
        attentionKey = key
        guard !windowWasVisible else { return }
        onAttention?(ChessAttention(
            kind: started ? .matchStarted : .myTurn, matchID: next.id,
            opponentName: next.opponent.displayName, plyCount: next.plyCount))
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

    /// 가장 이른 만료 시각에 한 번 깨어나 만료된 신청을 걷는다(배너가 시계를 읽지 않게 하는 장치).
    package func scheduleInviteExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        let dates = [incoming?.expiresAt, outgoing?.expiresAt].compactMap { $0 }
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
        if let invite = incoming, invite.expiresAt <= now { incoming = nil }
        if let sent = outgoing, sent.expiresAt <= now {
            outgoing = nil
            setNotice(ChessNoticeText.inviteTimedOut)
        }
        scheduleInviteExpiry()
    }

    /// 사람 행 → ChessUser(상대·관전의 두 사람). 행에 없는 칸은 로비 목록에서 빌린다.
    /// 서버 어휘 → 화면 글자는 **이 함수와 `user(from:)` 두 곳뿐**이다.
    package func peerUser(_ row: ChessUserRow?, inMatch: Bool) -> ChessUser? {
        guard let row, let id = row.userId?.lowercased(), !id.isEmpty else { return nil }
        let known = users.first { $0.id == id }
        return ChessUser(
            id: id,
            displayName: row.displayName ?? known?.displayName ?? "",
            avatarURL: row.avatarUrl ?? known?.avatarURL,
            characterID: row.character ?? known?.characterID,
            isWorking: row.isWorking ?? known?.isWorking ?? true,
            isCapable: row.capable ?? known?.isCapable ?? true,
            inMatch: row.inMatch ?? inMatch,
            center: CenterLabel.display(row.center) ?? known?.center)
    }

    /// 로비 "지금 대결 중" 한 줄 → 화면 값. 하나라도 모르면 **그 카드를 만들지 않는다**.
    package func liveMatch(from row: ChessLobbyMatchRow) -> ChessLiveMatch? {
        guard let id = row.matchId?.lowercased(), !id.isEmpty,
              let a = peerUser(row.a, inMatch: true), let b = peerUser(row.b, inMatch: true),
              // 판돈은 서버 CHECK 가 3·5·10 으로 묶은 값이다. 서버가 그 표를 넓히는 날 이 줄이 먼저 막는다.
              let stake = row.stake.flatMap(ChessStake.init(rawValue:)),
              let startedAt = deviceDate(serverMs: row.startedMs)
        else { return nil }
        return ChessLiveMatch(id: id, a: a, b: b, stake: stake, startedAt: startedAt)
    }

    /// 서버 사람 행 → ChessUser(로비). `capable` 이 nil 이면 **불가**다.
    package nonisolated static func user(from row: ChessUserRow) -> ChessUser? {
        guard let id = row.userId?.lowercased(), !id.isEmpty else { return nil }
        return ChessUser(
            id: id,
            displayName: row.displayName ?? "",
            avatarURL: row.avatarUrl,
            characterID: row.character,
            isWorking: row.isWorking ?? false,
            isCapable: row.capable ?? false,
            inMatch: row.inMatch ?? false,
            center: CenterLabel.display(row.center))
    }

    /// 로비 정렬: 도전할 수 있는 사람 → 근무 중·가능(대국 중) → 근무 중 → 나머지, 그 안은 이름순.
    /// **서버 정렬과 같은 규칙**이라 재정렬이 아니라 되맞춤이다(서버는 working desc → capable desc → 이름 → id).
    package nonisolated static func sortedForLobby(_ users: [ChessUser]) -> [ChessUser] {
        func rank(_ user: ChessUser) -> Int {
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
