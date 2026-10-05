import Foundation
import Testing
@testable import CheckCore

// 체스 AI — **고르는 수**를 못 박는다.
//
// 단언의 모양이 이 파일의 전부다: "엔진이 수를 돌려준다"는 아무것도 재지 않는다(불법 수를 두는 엔진도 통과한다).
// 여기서 재는 건 "이 국면에서 **이 수**를 고른다 · 점수가 **이 값**이다 · **이 시간** 안에 돌아온다"다.
//
// ── 기준선은 AI 코드를 타지 않는다 ──
// 메이트 과제의 정답은 `chessForcedMateMoves`(아래)가 `ChessRules` 만으로 전수 탐색해서 낸다. 기대값을 엔진으로
// 만들면 엔진이 틀려도 테스트는 영원히 초록이다. 그래서 ① 전수 탐색이 "이 국면의 메이트 수는 이것뿐"이라고 말하고
// ② 기대 UCI 가 파일에 글자로 박혀 있고(전수 탐색까지 함께 틀리는 길을 막는다) ③ 엔진의 수가 그 집합 안인지 본다.
// 증분 Zobrist 해시도 같은 방식이다 — **전체 재계산**과 나란히 재지 않으면 틀린 해시는 "수가 조금 나빠지는"
// 모습으로만 드러나고 테스트는 초록이다.
//
// ── 한도는 시간이 아니라 깊이로 ──
// 과제 테스트는 `maxDepth` 로 끊는다(시간으로 끊으면 기계가 느린 날 결과가 바뀐다). 1.5초 상한 자체를 재는
// 테스트만 시간으로 돈다.
//
// ── 느린 것은 환경변수 뒤에 ──
// 이 저장소의 기본 게이트는 **속도**로 가른다. 무작위 상대 20전과 1.5초 상한 실측은 `CHESS_AI_SLOW=1` 에서만
// 돈다 — 기본 묶음에 두면 한 번 돌릴 때마다 분 단위를 먹는다. 실측값은 작업 보고에 적었다.

// MARK: - 도우미

private func chessAIPosition(_ fen: String) throws -> ChessPosition {
    try #require(ChessPosition(fen: fen), "FEN 을 못 읽었다: \(fen)")
}

/// 깊이로 못 박은 한도. 시간 예산은 넉넉히 둬서 **깊이가 먼저** 끊는다.
private func chessAILimits(depth: Int, seed: UInt64 = 0xC0FF_EE11,
                           budget: Duration = .seconds(60)) -> ChessAISearchLimits {
    ChessAISearchLimits(timeBudget: budget, maxDepth: depth, tieBreakSeed: seed)
}

/// `position` 에서 **두는 쪽**이 `plies` 반수 안에 상대를 메이트시키는 첫 수 전부(상대가 어떻게 두어도).
/// `ChessRules` 만 쓰는 전수 탐색이다 — 엔진의 기준선이므로 엔진 코드를 한 줄도 부르지 않는다.
private func chessForcedMateMoves(_ position: ChessPosition, plies: Int) -> Set<String> {
    guard plies >= 1 else { return [] }
    var winners = Set<String>()
    for move in ChessRules.legalMoves(in: position) {
        guard let next = ChessRules.apply(move, to: position) else { continue }
        let replies = ChessRules.legalMoves(in: next)
        if replies.isEmpty {
            // 수가 없다 → 체크면 메이트, 아니면 스테일메이트(무승부 — 이긴 게 아니다).
            if ChessRules.isInCheck(next) { winners.insert(move.uci) }
            continue
        }
        guard plies >= 3 else { continue }
        let forced = replies.allSatisfy { reply in
            guard let after = ChessRules.apply(reply, to: next) else { return false }
            return !chessForcedMateMoves(after, plies: plies - 2).isEmpty
        }
        if forced { winners.insert(move.uci) }
    }
    return winners
}

private let chessTestPieceValue: [ChessPieceKind: Int] = [
    .pawn: 100, .knight: 320, .bishop: 330, .rook: 500, .queen: 900, .king: 0
]

/// `color` 시점의 기물 차이(내 값 − 상대 값). 차이로 재야 "내가 뭘 잡았는지"가 함께 들어온다.
private func chessBalance(_ position: ChessPosition, _ color: ChessColor) -> Int {
    position.pieces.reduce(0) { total, item in
        let value = chessTestPieceValue[item.piece.kind] ?? 0
        return item.piece.color == color ? total + value : total - value
    }
}

/// 이 수를 두고 **상대가 가장 아픈 잡기 하나**를 하고 내가 가장 좋은 되잡기를 했을 때의 기물 차이 변화(센티폰).
/// −900 이면 퀸을 공짜로 준 것이고, 0 이상이면 아무것도 넘기지 않았다.
///
/// 말 이름이 아니라 **값의 차이**로 재는 까닭: `d7xc8=Q` 는 폰이 비숍을 잡고 퀸이 되는 좋은 수인데, 그다음
/// `Qxc8` 을 '퀸을 공짜로 줬다'로 읽으면 이기는 수가 패착으로 찍힌다(실제로 찍혔다 — 점수 +506 인 수였다).
private func chessWorstMaterialSwing(_ move: ChessMove, in position: ChessPosition) -> Int {
    let me = position.sideToMove
    let before = chessBalance(position, me)
    guard let after = ChessRules.apply(move, to: position) else { return 0 }
    var worst = chessBalance(after, me)
    for reply in ChessRules.legalMoves(in: after) where after[reply.to] != nil {
        guard let afterReply = ChessRules.apply(reply, to: after) else { continue }
        var best = chessBalance(afterReply, me)
        for recapture in ChessRules.legalMoves(in: afterReply) where recapture.to == reply.to {
            guard let afterRecapture = ChessRules.apply(recapture, to: afterReply) else { continue }
            best = max(best, chessBalance(afterRecapture, me))
        }
        worst = min(worst, best)
    }
    return worst - before
}

/// 이 수로 잡은 말을 상대가 **되잡을 수 없는가**(= 공짜였는가).
private func chessCaptureIsFree(_ move: ChessMove, in position: ChessPosition) -> Bool {
    guard let after = ChessRules.apply(move, to: position) else { return false }
    return !ChessRules.legalMoves(in: after).contains { $0.to == move.to }
}

private func chessSeconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

private func chessAISlowEnabled() -> Bool {
    ProcessInfo.processInfo.environment["CHESS_AI_SLOW"] == "1"
}

struct ChessAIPuzzle: Sendable, CustomStringConvertible {
    let label: String
    let fen: String
    /// 전수 탐색이 찾은 메이트 첫 수 **전부**. 글자로 박아 둔다 — 전수 탐색과 엔진이 함께 틀리는 길을 막는다.
    let mates: Set<String>
    var description: String { label }
}

/// 한 수 메이트(1 반수).
let chessMateInOne: [ChessAIPuzzle] = [
    ChessAIPuzzle(label: "뒷줄 메이트 Ra8#", fen: "6k1/5ppp/8/8/8/8/8/R6K w - - 0 1", mates: ["a1a8"]),
    ChessAIPuzzle(label: "스콜라 메이트 Qxf7#",
                  fen: "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR w KQkq - 4 4",
                  mates: ["f3f7"]),
    ChessAIPuzzle(label: "질식 메이트 Nf7#", fen: "6rk/6pp/8/6N1/8/8/8/5K2 w - - 0 1", mates: ["g5f7"]),
    ChessAIPuzzle(label: "룩+왕 Ra8#", fen: "7k/8/6K1/8/8/8/8/R7 w - - 0 1", mates: ["a1a8"]),
    ChessAIPuzzle(label: "룩+왕 Rh1#", fen: "7k/5K2/8/8/8/8/8/R7 w - - 0 1", mates: ["a1h1"]),
    // 느린 메이트(3 반수)도 열한 가지나 있는 국면이다. 메이트를 거리로 점수화하지 않으면 여기서 느린 쪽을 고른다.
    ChessAIPuzzle(label: "느린 메이트도 많은 Rg8#", fen: "k7/8/1K6/8/8/8/8/6R1 w - - 0 1", mates: ["g1g8"]),
    ChessAIPuzzle(label: "흑이 두는 뒷줄 메이트", fen: "r6k/8/8/8/8/8/5PPP/6K1 b - - 0 1", mates: ["a8a1"]),
    ChessAIPuzzle(label: "흑 퀸 메이트 넷 중 하나", fen: "8/8/8/8/8/1k6/2q5/K7 b - - 0 1",
                  mates: ["c2a2", "c2b2", "c2c1", "c2d1"])
]

/// 두 수 메이트(3 반수).
let chessMateInTwo: [ChessAIPuzzle] = [
    ChessAIPuzzle(label: "퀸+룩 두 수 메이트", fen: "7k/8/8/8/8/8/8/KQR5 w - - 0 1", mates: ["b1b7", "c1c7"]),
    ChessAIPuzzle(label: "흑이 두는 퀸+룩 두 수 메이트", fen: "kqr5/8/8/8/8/8/8/7K b - - 0 1",
                  mates: ["b8b2", "c8c2"]),
    ChessAIPuzzle(label: "Qxf7 두 수 메이트",
                  fen: "2bqkbn1/2pppp2/np2N3/r3P1p1/p2N2B1/5Q2/PPPPKPP1/RNB2r2 w - - 0 1",
                  mates: ["f3f7"]),
    ChessAIPuzzle(label: "룩 희생 두 수 메이트", fen: "r5rk/5p1p/5R2/4Q3/8/8/7P/7K w - - 0 1",
                  mates: ["f6f7"])
]

/// 상대가 **무방비로** 둔 퀸. 잡는 수가 글자로 박혀 있다.
struct ChessFreePiecePuzzle: Sendable, CustomStringConvertible {
    let label: String
    let fen: String
    let capture: String
    var description: String { label }
}

let chessFreeQueenPuzzles: [ChessFreePiecePuzzle] = [
    ChessFreePiecePuzzle(label: "중반 Nxe4",
                         fen: "r1bqk2r/pppp1ppp/2n2n2/2b5/2B1Q3/5N2/PPPP1PPP/RNB1K2R b KQkq - 0 1",
                         capture: "f6e4"),
    ChessFreePiecePuzzle(label: "중반 Nxd4",
                         fen: "r1bqkbnr/pppp1ppp/2n5/8/3QP3/8/PPPP1PPP/RNB1KBNR b KQkq - 0 4",
                         capture: "c6d4"),
    ChessFreePiecePuzzle(label: "끝내기 Bxd5", fen: "4k3/8/8/3q4/4B3/8/8/4K3 w - - 0 1", capture: "e4d5"),
    ChessFreePiecePuzzle(label: "끝내기 Kxd2", fen: "4k3/8/8/8/8/8/3q4/2R1K3 w - - 0 1", capture: "e1d2")
]

/// 1.5초 상한·평균 깊이를 재는 국면(수 세기 테스트가 쓰는 것과 같은 중반·끝내기 덩어리).
let chessAITimingPositions: [String] = [
    "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4",
    "r2q1rk1/ppp2ppp/2np1n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQ1RK1 w - - 8 9",
    "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
    "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
    "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
]

// MARK: - 테스트

@Suite("체스 AI")
struct ChessAIEngineTests {

    // MARK: - 메이트

    @Test("한 수 메이트 — 전수 탐색이 찾은 그 수를 고르고, 점수가 '1 반수 메이트'다", arguments: chessMateInOne)
    func picksMateInOne(_ puzzle: ChessAIPuzzle) throws {
        let position = try chessAIPosition(puzzle.fen)
        #expect(chessForcedMateMoves(position, plies: 1) == puzzle.mates, "\(puzzle.label): 전수 탐색이 다른 말을 한다")
        let decision = try #require(ChessAI.decide(position: position, limits: chessAILimits(depth: 4)))
        #expect(puzzle.mates.contains(decision.move.uci), "\(puzzle.label): 고른 수 \(decision.move.uci)")
        // 거리까지 잰다: 느린 메이트도 있는 국면에서 1 이 아니면 느린 쪽을 골랐다는 뜻이다.
        #expect(decision.mateInPlies == 1, "\(puzzle.label): 점수 \(decision.score)")
    }

    @Test("두 수 메이트 — 전수 탐색이 찾은 그 수를 고르고, 점수가 '3 반수 메이트'다", arguments: chessMateInTwo)
    func picksMateInTwo(_ puzzle: ChessAIPuzzle) throws {
        let position = try chessAIPosition(puzzle.fen)
        #expect(chessForcedMateMoves(position, plies: 1).isEmpty,
                "\(puzzle.label): 한 수 메이트가 있으면 두 수 과제가 아니다")
        #expect(chessForcedMateMoves(position, plies: 3) == puzzle.mates, "\(puzzle.label): 전수 탐색이 다른 말을 한다")
        let decision = try #require(ChessAI.decide(position: position, limits: chessAILimits(depth: 5)))
        #expect(puzzle.mates.contains(decision.move.uci), "\(puzzle.label): 고른 수 \(decision.move.uci)")
        #expect(decision.mateInPlies == 3, "\(puzzle.label): 점수 \(decision.score)")
    }

    @Test("메이트·스테일메이트 국면은 둘 수가 없다 → nil")
    func returnsNilWithoutLegalMoves() throws {
        // 꼬마 메이트(1.f3 e5 2.g4 Qh4#) — 백은 메이트당했다.
        let mated = try chessAIPosition("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")
        #expect(ChessRules.outcome(position: mated) == .checkmate(winner: .black))
        #expect(ChessAI.bestMove(position: mated) == nil)
        let stalemate = try chessAIPosition("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        #expect(ChessRules.outcome(position: stalemate) == .stalemate)
        #expect(ChessAI.bestMove(position: stalemate) == nil)
    }

    // MARK: - 공짜 기물 · 패착

    @Test("무방비로 둔 퀸은 곧바로 잡는다", arguments: chessFreeQueenPuzzles)
    func grabsFreeQueen(_ puzzle: ChessFreePiecePuzzle) throws {
        let position = try chessAIPosition(puzzle.fen)
        let expected = try #require(ChessMove(uci: puzzle.capture))
        // 과제가 진짜 '공짜'인지부터 잰다: 되잡을 수 있으면 공짜가 아니고, 그러면 이 테스트는 뜻이 없다.
        #expect(position[expected.to] == ChessPiece(position.sideToMove.opponent, .queen))
        #expect(chessCaptureIsFree(expected, in: position), "\(puzzle.label): 되잡기가 있다")
        let decision = try #require(ChessAI.decide(position: position, limits: chessAILimits(depth: 4)))
        #expect(decision.move.uci == puzzle.capture, "\(puzzle.label): 고른 수 \(decision.move.uci)")
    }

    @Test("정지 탐색 — 깊이 1 에서도 지켜지는 폰을 퀸으로 잡지 않는다")
    func quiescenceRefusesDefendedPawn() throws {
        // Qxd5 는 '폰 +100' 으로 보이지만 cxd5 로 퀸이 사라진다. 정지 탐색이 없으면 깊이 1 에서 이 수가 최선이다.
        let position = try chessAIPosition("4k3/8/2p5/3p4/8/8/8/3QK3 w - - 0 1")
        let grab = try #require(ChessMove(uci: "d1d5"))
        #expect(ChessRules.legalMoves(in: position).contains(grab))
        #expect(!chessCaptureIsFree(grab, in: position), "d5 가 지켜지지 않으면 이 테스트는 뜻이 없다")
        #expect(chessWorstMaterialSwing(grab, in: position) == -800, "Qxd5 는 퀸−폰 = −800 이다")
        let decision = try #require(ChessAI.decide(position: position, limits: chessAILimits(depth: 1)))
        #expect(decision.move.uci != "d1d5", "깊이 1 에서 퀸을 폰과 바꿨다")
        #expect(chessWorstMaterialSwing(decision.move, in: position) >= 0, "고른 수 \(decision.move.uci)")
        #expect(decision.score > 0, "퀸이 있는 쪽이 유리하다: \(decision.score)")
    }

    @Test("명백한 패착(룩 이상을 공짜로 넘기는 수)은 어느 국면에서도 고르지 않는다")
    func neverHandsOverMaterial() throws {
        for fen in chessAITimingPositions {
            let position = try chessAIPosition(fen)
            let decision = try #require(ChessAI.decide(position: position, limits: chessAILimits(depth: 4)))
            let swing = chessWorstMaterialSwing(decision.move, in: position)
            #expect(swing > -500, "\(fen) → \(decision.move.uci) 가 \(swing) 을 넘겼다")
        }
    }

    // MARK: - 무승부 셈

    @Test("스테일메이트를 이기는 수로 착각하지 않는다")
    func doesNotStalemateAWonPosition() throws {
        // 흑 왕이 이미 꽉 막혀 있다: 백이 아무렇게나 두면 **스테일메이트(무승부)** 다.
        let position = try chessAIPosition("k7/8/1Q6/8/8/8/8/K7 w - - 0 1")
        let stalemating = Set(ChessRules.legalMoves(in: position).filter {
            guard let next = ChessRules.apply($0, to: position) else { return false }
            return ChessRules.outcome(position: next) == .stalemate
        }.map(\.uci))
        #expect(stalemating == ["a1a2", "a1b1", "a1b2", "b6c7"], "과제 국면이 바뀌었다: \(stalemating.sorted())")
        let decision = try #require(ChessAI.decide(position: position, limits: chessAILimits(depth: 5)))
        #expect(!stalemating.contains(decision.move.uci), "스테일메이트로 비겼다: \(decision.move.uci)")
        #expect(decision.score > 300, "퀸이 남은 판을 이긴다고 세야 한다: \(decision.score)")
    }

    @Test("이기는 판을 3회 반복으로 흘려보내지 않는다")
    func avoidsThreefoldWhenWinning() throws {
        // 백은 퀸·룩이 남아 이긴 판이다. Rg1-g2 로 가는 국면이 이미 두 번 나왔다면 그 수는 무승부(0)다.
        let position = try chessAIPosition("7k/8/8/8/8/8/8/K1Q3R1 w - - 0 1")
        let repeating = try #require(ChessMove(uci: "g1g2"))
        let after = try #require(ChessRules.apply(repeating, to: position))
        #expect(ChessRules.outcome(position: after, repetitionCounts: [after.repetitionKey: 3]) == .threefoldRepetition)
        let decision = try #require(ChessAI.decide(position: position,
                                                  repetitionCounts: [after.repetitionKey: 2],
                                                  limits: chessAILimits(depth: 4)))
        #expect(decision.move.uci != "g1g2", "무승부로 걸어 들어갔다")
        #expect(decision.score > 300, "이긴 판이다: \(decision.score)")
    }

    @Test("지는 판에서는 3회 반복(무승부)을 고른다")
    func takesThreefoldWhenLosing() throws {
        // 백은 퀸을 뺏긴 채다. Re1-f1 로 가는 국면이 이미 두 번 나왔으면 그 수만 0 점이고 나머지는 지는 점수다.
        let position = try chessAIPosition("7k/8/8/8/8/3q4/8/K3R3 w - - 0 1")
        let repeating = try #require(ChessMove(uci: "e1e2"))
        let after = try #require(ChessRules.apply(repeating, to: position))
        let decision = try #require(ChessAI.decide(position: position,
                                                   repetitionCounts: [after.repetitionKey: 2],
                                                   limits: chessAILimits(depth: 5)))
        #expect(decision.move.uci == "e1e2", "무승부를 두고 다른 수를 골랐다: \(decision.move.uci) 점수 \(decision.score)")
        #expect(decision.score == 0, "3회 반복은 0 이다: \(decision.score)")
        // 장부가 없으면 같은 국면이 무승부가 아니다 → 지는 점수가 나온다.
        let blind = try #require(ChessAI.decide(position: position, limits: chessAILimits(depth: 5)))
        #expect(blind.score < 0, "퀸을 뺏긴 판이다: \(blind.score)")
    }

    // MARK: - 취소 · 결정성 · 합법성

    @Test("취소 문이 열려 있으면 곧바로 합법 수를 들고 돌아온다")
    func cancellationReturnsImmediately() throws {
        let position = try chessAIPosition(chessAITimingPositions[0])
        let legal = Set(ChessRules.legalMoves(in: position).map(\.uci))
        let clock = ContinuousClock()
        var move: ChessMove?
        let spent = clock.measure {
            move = ChessAI.bestMove(position: position,
                                    limits: ChessAISearchLimits(timeBudget: .seconds(30), maxDepth: 64),
                                    isCancelled: { true })
        }
        let found = try #require(move)
        #expect(legal.contains(found.uci), "취소 뒤에 불법 수를 냈다: \(found.uci)")
        #expect(spent < .milliseconds(200), "취소에 \(spent) 걸렸다")
    }

    @Test("씨앗이 같으면 같은 수 — 씨앗이 없어도 늘 합법 수")
    func seededChoiceIsDeterministic() throws {
        let position = try chessAIPosition(chessAITimingPositions[0])
        let first = try #require(ChessAI.bestMove(position: position, limits: chessAILimits(depth: 4, seed: 99)))
        for _ in 0..<3 {
            let again = try #require(ChessAI.bestMove(position: position, limits: chessAILimits(depth: 4, seed: 99)))
            #expect(again == first, "같은 씨앗·같은 깊이인데 수가 달라졌다")
        }
        let legal = Set(ChessRules.legalMoves(in: position).map(\.uci))
        for _ in 0..<3 {
            let unseeded = try #require(ChessAI.bestMove(
                position: position, limits: ChessAISearchLimits(timeBudget: .milliseconds(80), maxDepth: 3)))
            #expect(legal.contains(unseeded.uci))
        }
    }

    @Test("무작위로 걸어간 40 국면에서 늘 합법 수를 낸다")
    func alwaysReturnsLegalMove() throws {
        var rng = GomokuAISplitMix64(seed: 0x5EED_1234)
        var position = ChessPosition.standard
        var checked = 0
        var plies = 0
        while checked < 40 {
            let legal = ChessRules.legalMoves(in: position)
            if legal.isEmpty || ChessRules.outcome(position: position) != nil || plies >= 120 {
                position = .standard
                plies = 0
                continue
            }
            let decision = try #require(ChessAI.decide(position: position, limits: chessAILimits(depth: 2)))
            #expect(legal.contains(decision.move), "\(position.fen) → \(decision.move.uci)")
            checked += 1
            position = try #require(ChessRules.apply(legal[Int(rng.next() % UInt64(legal.count))], to: position))
            plies += 1
        }
        #expect(checked == 40)
    }

    // MARK: - 증분 해시

    @Test("증분 Zobrist 해시 = 전체 재계산 (승격·캐슬링·앙파상·잡기 전부)")
    func incrementalHashMatchesFullRecompute() throws {
        let lines: [(fen: String, uci: [String])] = [
            // 앙파상 잡기 · 되잡기 · 킹사이드 캐슬링.
            (ChessPosition.standard.fen,
             ["e2e4", "a7a6", "e4e5", "d7d5", "e5d6", "c7d6", "g1f3", "g8f6", "f1c4", "e7e6", "e1g1"]),
            // 나이트 승격 · 흑 킹사이드 캐슬링 · 백 퀸사이드 캐슬링.
            ("4k2r/P7/8/8/8/8/8/R3K3 w Qk - 0 1", ["a7a8n", "e8g8", "e1c1"])
        ]
        for line in lines {
            let position = try chessAIPosition(line.fen)
            let engine = try #require(ChessEngine(position: position))
            let search = ChessAISearch(engine: engine, budget: .seconds(1), isCancelled: { false })
            #expect(search.hash == ChessAISearch.fullHash(search.engine))
            let before = search.hash
            var states: [(undo: ChessUndo, hash: UInt64)] = []
            for uci in line.uci {
                let move = try #require(ChessMove(uci: uci))
                var probe = search.engine
                let candidate = probe.matchingLegalMove(move)
                let raw = try #require(candidate, "\(uci) 가 불법이다")
                states.append(search.makeMove(raw))
                #expect(search.hash == ChessAISearch.fullHash(search.engine),
                        "\(uci) 뒤 증분 해시가 어긋났다: \(search.engine.position.fen)")
            }
            while let state = states.popLast() { search.undoMove(state) }
            #expect(search.hash == before, "되돌린 뒤 해시가 제자리로 안 왔다")
            #expect(search.engine.position.fen == position.fen)
        }
    }

    // MARK: - 느린 것(CHESS_AI_SLOW=1)

    @Test("1.5초 상한 — 다섯 국면에서 벽시계가 상한을 넘지 않는다(평균 깊이 함께 보고)",
          .enabled(if: chessAISlowEnabled()))
    func respectsOneAndAHalfSeconds() throws {
        let budget = Duration.milliseconds(1500)
        var depths: [Int] = []
        var rates: [Int] = []
        for fen in chessAITimingPositions {
            let position = try chessAIPosition(fen)
            let clock = ContinuousClock()
            var decision: ChessAIDecision?
            let spent = clock.measure {
                decision = ChessAI.decide(position: position,
                                          limits: ChessAISearchLimits(timeBudget: budget, maxDepth: 64,
                                                                      tieBreakSeed: 7))
            }
            let found = try #require(decision)
            #expect(spent <= budget, "\(fen): 벽시계 \(spent)")
            #expect(found.depth >= 3, "\(fen): 깊이 \(found.depth)")
            depths.append(found.depth)
            rates.append(Int(Double(found.nodes) / max(chessSeconds(spent), 0.0001)))
            print("[1.5초] \(fen) → \(found.move.uci) 깊이 \(found.depth) 노드 \(found.nodes) \(spent)")
        }
        print("[1.5초] 평균 깊이 \(Double(depths.reduce(0, +)) / Double(depths.count)) · 초당 노드 \(rates)")
    }

    @Test("무작위 합법수 상대 20전 — 전승, 모든 수 합법, 퀸을 공짜로 주지 않는다",
          .enabled(if: chessAISlowEnabled()))
    func beatsRandomOpponentTwentyGames() throws {
        var rng = GomokuAISplitMix64(seed: 0xBEEF_F00D)
        var wins = 0
        for game in 0..<20 {
            let engineColor: ChessColor = game % 2 == 0 ? .white : .black
            var position = ChessPosition.standard
            var ledger = ChessRepetitionLedger()
            ledger.record(position)
            var outcome: ChessOutcome?
            var plies = 0
            while plies < 400 {
                if let done = ChessRules.outcome(position: position, repetitionCounts: ledger.repetitionCounts) {
                    outcome = done
                    break
                }
                let legal = ChessRules.legalMoves(in: position)
                let move: ChessMove
                if position.sideToMove == engineColor {
                    let decision = try #require(ChessAI.decide(position: position,
                                                               repetitionCounts: ledger.repetitionCounts,
                                                               limits: chessAILimits(depth: 4,
                                                                                     seed: UInt64(game) &+ 1)))
                    #expect(legal.contains(decision.move), "\(game)판 \(plies)수: 불법 수 \(decision.move.uci)")
                    // 메이트로 가는 희생은 패착이 아니다 — 그 밖에서는 퀸을 공짜로 주지 않는다.
                    if (decision.mateInPlies ?? -1) <= 0 {
                        let swing = chessWorstMaterialSwing(decision.move, in: position)
                        #expect(swing > -500,
                                "\(game)판 \(plies)수: \(decision.move.uci) 가 \(swing) 을 넘겼다 / \(position.fen)")
                    }
                    move = decision.move
                } else {
                    move = legal[Int(rng.next() % UInt64(legal.count))]
                }
                position = try #require(ChessRules.apply(move, to: position))
                ledger.record(position)
                plies += 1
            }
            #expect(outcome?.winner == engineColor,
                    "\(game)판(\(engineColor.rawValue)): \(String(describing: outcome)) \(plies)수")
            if outcome?.winner == engineColor { wins += 1 }
            print("[20전] \(game)판 \(engineColor.rawValue) → \(String(describing: outcome)) \(plies)수")
        }
        #expect(wins == 20, "전승이 아니다: \(wins)/20")
    }
}
