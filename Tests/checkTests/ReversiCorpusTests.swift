import Foundation
import Testing
@testable import CheckCore

// 아잉 뒤집기 실전 기보 재생 — cases.json `wthor_sample` 200판(공개 대회 기보 WTH_2015~2024 에서 고른 표본)과 가장 짧은 판.
//
// 손 사례(hand 48)는 규칙 조항을 하나씩 찌르고, 이 시험은 **판 하나를 처음부터 끝까지** 둔다: 자동 패스가 일어나는 자리(passes_before),
// 마지막 판, 실제 돌 수, WOF 점수(빈칸은 이긴 쪽), 결과, 끝 사유. 기보 파일에 적힌 흑 점수(official_black_score)와도 맞세운다 —
// 사람이 실제로 둔 판이라 우리 규칙이 어느 한 수라도 불법으로 막거나, 패스를 한 수 늦게·빨리 하면 그 판은 끝까지 못 간다.
// 표본은 무작위 123 + 패스 많은 판 · 무승부 · no_moves · 백 승 · 전멸 각 15 + 짧은 판 2 다(picked_for).

@Suite("아잉 뒤집기 기보 재생 — wthor_sample 200 · 가장 짧은 판")
struct ReversiCorpusTests {
    struct Replay {
        var board = ReversiBoard.start
        var turn: ReversiColor? = .black
        var passesBefore: [Int] = []
        var played = 0
    }

    /// 수 목록을 시작 판부터 둔다(둘 곳 없는 쪽은 자동 패스). 불법이거나 끝난 뒤에 수가 남으면 던진다.
    static func replay(_ moves: [Int], label: String) throws -> Replay {
        var state = Replay()
        for (k, idx) in moves.enumerated() {
            guard let color = state.turn else {
                throw ReversiFixtureError("\(label): \(k) 번째 수(\(idx)) 전에 판이 끝났다")
            }
            switch ReversiRules.play(state.board, color: color, idx: idx) {
            case .failure(let reason):
                throw ReversiFixtureError("\(label): \(k) 번째 수 \(ReversiPoint(idx: idx)?.coord ?? "\(idx)") (\(color)) 가 불법 — \(reason.rawValue)\n\(state.board.string)")
            case .success(let outcome):
                state.board = outcome.board
                state.turn = outcome.next
                state.played += 1
                // passes_before = k+1: 다음 수(k+1 번째)를 두기 직전에 자동 패스가 있었다.
                if outcome.passed { state.passesBefore.append(k + 1) }
            }
        }
        return state
    }

    // 없으면: 표본에서 패스·무승부·전멸·no_moves 판이 빠져도(코퍼스를 다시 뽑다 실수) 아래 재생은 판 가득 판만 돌고 초록이다.
    @Test("표본 모양 — 200판, 끝 사유 셋 · 무승부 · 패스 있는 판이 다 들어 있다")
    func sampleCoversEveryEnding() throws {
        let games = try ReversiCorpusFile.load().wthorSample
        #expect(games.count == 200)
        #expect(Set(games.map(\.id)).count == 200)
        #expect(Set(games.map(\.end)) == ["board_full", "no_moves", "wipeout"])
        #expect(games.contains { $0.result == "draw" })
        #expect(games.contains { $0.result == "black_win" } && games.contains { $0.result == "white_win" })
        #expect(games.filter { !$0.passesBefore.isEmpty }.count >= 15)
    }

    // 없으면: 자동 패스 시점(V-09)·끝 판정(V-10)·WOF 점수(V-11)가 손 사례 밖의 실전 판에서 갈려도 모른다.
    @Test("기보 200판 재생 — 수 수 · 패스 자리 · 마지막 판 · 돌 수 · WOF 점수 · 결과 · 끝 사유 · 기보 흑 점수")
    func wthorSampleReplays() throws {
        let games = try ReversiCorpusFile.load().wthorSample
        var replayed = 0
        for game in games {
            let label = "\(game.id)(\(game.pickedFor))"
            let moves = try ReversiCorpusFile.indices(game.moves, label)
            let state = try Self.replay(moves, label: label)
            #expect(moves.count == game.plies, "\(label) 수 수")
            #expect(state.turn == nil, "\(label): 기보가 끝났는데 판이 안 끝났다")
            #expect(state.passesBefore == game.passesBefore, "\(label) 패스 자리")
            #expect(state.board.string == game.finalBoard, "\(label) 마지막 판")
            #expect(state.board.counts == ReversiCounts(black: game.discs.black, white: game.discs.white, empty: game.discs.empty), "\(label) 돌 수")
            let score = ReversiRules.score(state.board)
            #expect(score.map { ReversiCorpus.Pair(black: $0.black, white: $0.white) } == game.score, "\(label) WOF 점수")
            #expect(score?.result.rawValue == game.result, "\(label) 결과")
            #expect(ReversiRules.endKind(state.board)?.rawValue == game.end, "\(label) 끝 사유")
            #expect(score?.black == game.officialBlackScore, "\(label): 기보 파일의 흑 점수와 다르다")
            replayed += 1
        }
        #expect(replayed == 200)
    }

    // 없으면: 판 가득 전에 전멸로 끝나는 판(9수)이 "끝난 뒤 수가 남음"·"전멸 대신 no_moves" 로 갈려도 기보 표본만으로는 드물게만 밟힌다.
    @Test("가장 짧은 판 9수 — 전멸 13:0 → 64:0 흑 승")
    func shortestGameReplays() throws {
        let shortest = try ReversiCorpusFile.load().perft.shortestGame
        let moves = try ReversiCorpusFile.indices(shortest.moves, "shortest_game")
        #expect(moves.count == 9)
        let state = try Self.replay(moves, label: "shortest_game")
        #expect(state.turn == nil)
        #expect(state.board.string == shortest.finalBoard)
        #expect(state.board.counts == ReversiCounts(black: shortest.discs.black, white: shortest.discs.white, empty: shortest.discs.empty))
        let score = try #require(ReversiRules.score(state.board))
        #expect(ReversiCorpus.Pair(black: score.black, white: score.white) == shortest.score)
        #expect(score.result.rawValue == shortest.result)
        #expect(ReversiRules.endKind(state.board)?.rawValue == shortest.end)
        // 기준선: 마지막 수 하나를 빼면 판은 아직 안 끝났다 — "끝"이 수 수와 상관없이 늘 참인 구현을 가른다.
        let before = try Self.replay(Array(moves.dropLast()), label: "shortest_game −1")
        #expect(before.turn != nil)
        #expect(ReversiRules.endKind(before.board) == nil)
    }
}
