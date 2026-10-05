import Foundation
import Testing
@testable import CheckCore

// 체스 수 세기(perft) — **ChessRules 의 합격선**.
//
// 기대값은 이 파일에 없다. `Fixtures/chess-perft.json` 한 곳에 있고, **앞으로 SQL 마이그레이션도 같은 파일을 베낀다**
// (`ChessPerftFixtureSQLContract` 가 둘을 대조한다). 숫자를 Swift 와 SQL 이 각자 적으면 둘이 갈려도 아무도 모른다 —
// 갈린 쪽이 틀렸다는 걸 알려 줄 사람이 없기 때문이다. 그래서 숫자의 집은 하나다.
//
// 픽스처의 두 묶음:
//  · `positions` 여섯 — **공표값**(Chess Programming Wiki). 체스 엔진 세계에서 서로 교차 검증된 알려진 정답이다
//    (초기 배치 · Kiwipete · 폰 끝내기 · 승격/핀 덩어리 · 두 쪽 다 복잡한 중반 둘). 숫자가 어긋나면 **엔진이 틀린 것이다** —
//    기대값은 고치지 마라. 어긋나면 이 파일이 `ChessRules.perftDivide` 를 함께 찍는다: 정답 엔진의 divide 와
//    나란히 놓으면 어느 첫 수에서 갈렸는지 한 줄로 드러나고, 그 수를 둔 국면에서 다시 divide 를 찍어 내려가면
//    틀린 규칙이 나온다. 이게 체스 엔진 디버깅의 표준 방법이고, 이 저장소에서 쓸 수 있는 유일한 방법이다
//    (우리에겐 대조할 다른 구현이 없고, 수 세기가 그 역할을 한다).
//  · `leaves` 셋 — **종국 잎 자리**(우리가 만들었다). 합법 수가 0 인 국면이 섞였을 때 수 세기가 버티는지 본다.
//    SQL 쪽에서 `array_length(빈 배열, 1)` 은 0 이 아니라 **NULL** 이라, 종국 잎이 하나 섞이면 합계가 통째로
//    사라진다. 그 결함은 깊이를 올려야만 우연히 밟히는데(깊이 5 에서 46초) 잎 자리로는 **ms 에 밟힌다**.
//    Swift 쪽에도 같은 모양의 경계가 있다(빈 divide·0 전파) — 그래서 두 구현이 같은 자리를 함께 밟는다.
//
// ── 빠른 것과 깊은 것을 가른 기준 ──
// 이 저장소의 기본 게이트는 **속도**로 가른다(영역으로 가르면 수율이 몰래 깎인다). 그래서 기본 테스트에는
// 여섯 국면의 d1~d3 과 ①③의 d4, 그리고 잎 셋 전부(잎은 다 합쳐 2,500 노드 미만 — ms 에 끝난다)를 둔다.
// 더 깊은 다섯 자리(① d5 · ③ d5 · ② d4 · ⑤ d4 · ⑥ d4 — 합쳐 15,623,917 노드, ③ d5 를 뺀 넷이 14,949,293)는
// `CHESS_PERFT_DEEP=1` 에서만 돈다 — 규칙을 고칠 때 한 번 돌리는 그물이다.
// 실측(2026-10-05, 디버그 빌드 · --no-parallel): 기본 게이트 0.55초 · DEEP 포함 14.6초.

// MARK: - 픽스처

struct ChessPerftCase: Sendable, Decodable {
    let label: String
    let fen: String
    /// counts[0] 이 깊이 1.
    let counts: [Int]
    /// `"checkmate:white"` · `"stalemate"` · nil(안 끝난 국면). 잎 자리에만 있다.
    let outcome: String?
    /// 그 수를 둔 뒤 상대가 둘 수 없는 수들(UCI). divide(깊이 2) 에서 노드 0 으로 나와야 하는 줄이다.
    let terminalChildren: [String]?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case label, fen, counts, outcome, note
        case terminalChildren = "terminal_children"
    }

    /// 픽스처 라벨의 머리글자(①…⑨). 테스트 이름이 가리키는 국면을 **번호로** 집는다 —
    /// 배열 인덱스로 집으면 픽스처에서 줄 순서만 바뀌어도 "① 깊이 4" 가 조용히 다른 국면을 재게 된다.
    var marker: String { label.isEmpty ? "" : String(label.first!) }
}

struct ChessPerftFixture: Sendable, Decodable {
    let positions: [ChessPerftCase]
    let leaves: [ChessPerftCase]

    /// 공표값 여섯 + 잎 셋. SQL 대조도 이 순서로 본다.
    var all: [ChessPerftCase] { positions + leaves }
}

/// 픽스처를 읽는다. 매번 읽는다 — 9개 항목 디코드는 ㎲ 단위고, 전역 캐시를 두면 그 캐시가 또 하나의 상태가 된다.
func chessPerftFixture() throws -> ChessPerftFixture {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/chess-perft.json")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw ChessPerftFixtureError("픽스처가 없다: \(url.path) — 기대값의 집이 하나뿐이라 이게 없으면 잴 것이 없다")
    }
    return try JSONDecoder().decode(ChessPerftFixture.self, from: Data(contentsOf: url))
}

struct ChessPerftFixtureError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// 번호로 국면을 집는다(①…⑨). 없으면 던진다 — 조용히 건너뛰면 그 자리의 테스트가 **아무것도 안 재면서 초록**이 된다.
func chessPerftCase(_ marker: String) throws -> ChessPerftCase {
    let fixture = try chessPerftFixture()
    guard let found = fixture.all.first(where: { $0.marker == marker }) else {
        throw ChessPerftFixtureError("픽스처에 \(marker) 국면이 없다(있는 것: \(fixture.all.map(\.marker).joined(separator: " ")))")
    }
    return found
}

/// 수 세기 한 자리. 어긋나면 판과 divide 를 함께 남긴다 — 성공할 때는 divide 를 **계산하지 않는다**
/// (`#expect` 의 설명문은 미리 계산되므로 거기에 넣으면 초록인 자리에서도 수 세기를 한 번 더 돈다).
func expectChessPerft(_ item: ChessPerftCase, depth: Int) throws {
    let position = try #require(ChessPosition(fen: item.fen), "FEN 을 못 읽었다: \(item.fen)")
    guard depth >= 1, depth <= item.counts.count else {
        throw ChessPerftFixtureError("\(item.label): 픽스처에 깊이 \(depth) 기대값이 없다(있는 깊이 1…\(item.counts.count))")
    }
    let expected = item.counts[depth - 1]
    let actual = ChessRules.perft(position, depth: depth)
    #expect(actual == expected, "\(item.label) 깊이 \(depth)")
    guard actual != expected else { return }
    let divide = ChessRules.perftDivide(position, depth: depth)
        .map { "  \($0.move.uci) \($0.nodes)" }
        .joined(separator: "\n")
    Issue.record("""
        \(item.label) 깊이 \(depth): \(actual) ≠ \(expected) (차 \(actual - expected))
        \(item.fen)
        \(position.asciiBoard)
        divide(깊이 \(depth)) — 정답 엔진의 divide 와 나란히 놓고 갈린 수를 찾아라:
        \(divide)
        """)
}

@Suite("체스 수 세기(perft)")
struct ChessPerftTests {
    @Test("깊이 0 은 국면 자신 하나")
    func depthZeroCountsThePositionItself() {
        #expect(ChessRules.perft(.standard, depth: 0) == 1)
    }

    /// 픽스처가 **무엇을 들고 있는지**부터 못 박는다. 이게 없으면 누군가 픽스처에서 국면 하나를 지워도
    /// 아래 반복 시험들은 남은 것만 돌고 초록이다 — 단언이 조용히 줄어드는 자리다.
    @Test("픽스처 모양 — 공표 국면 ①…⑥ · 잎 ⑦⑧⑨, 깊이별 기대값이 빠짐없이 있다")
    func fixtureShapeIsIntact() throws {
        let fixture = try chessPerftFixture()
        #expect(fixture.positions.map(\.marker) == ["①", "②", "③", "④", "⑤", "⑥"])
        #expect(fixture.leaves.map(\.marker) == ["⑦", "⑧", "⑨"])
        for item in fixture.all {
            #expect(item.counts.count >= 3, "\(item.label): 깊이 3 까지는 있어야 한다")
            #expect(ChessPosition(fen: item.fen) != nil, "\(item.label): FEN 을 못 읽었다 — \(item.fen)")
            #expect(item.counts.allSatisfy { $0 >= 0 }, "\(item.label): 음수 기대값")
        }
        // 공표 여섯은 전부 둘 수가 있는 국면이다(0 이 섞이면 공표값을 베낀 게 아니다).
        #expect(fixture.positions.allSatisfy { $0.counts[0] > 0 })
        // 잎 셋은 **0 짜리 둘 + 0 이 아닌 하나**여야 한다. 셋 다 0 이면 "전부 0" 을 특별 취급해 비껴가는
        // 구현이 통과하고, 0 이 하나도 없으면 NULL 결함을 애초에 못 밟는다.
        #expect(fixture.leaves.filter { $0.counts[0] == 0 }.count == 2)
        #expect(fixture.leaves.filter { $0.counts[0] > 0 }.count == 1)
    }

    @Test("여섯 국면 깊이 1 — 합법 수 개수")
    func depthOneMatchesKnownCounts() throws {
        for item in try chessPerftFixture().positions { try expectChessPerft(item, depth: 1) }
    }

    @Test("여섯 국면 깊이 2")
    func depthTwoMatchesKnownCounts() throws {
        for item in try chessPerftFixture().positions { try expectChessPerft(item, depth: 2) }
    }

    @Test("여섯 국면 깊이 3")
    func depthThreeMatchesKnownCounts() throws {
        for item in try chessPerftFixture().positions { try expectChessPerft(item, depth: 3) }
    }

    @Test("① 초기 배치 깊이 4 — 197,281")
    func startPositionDepthFour() throws {
        try expectChessPerft(try chessPerftCase("①"), depth: 4)
    }

    @Test("③ 폰 끝내기 깊이 4 — 43,238")
    func pawnEndgameDepthFour() throws {
        try expectChessPerft(try chessPerftCase("③"), depth: 4)
    }

    // MARK: - 잎 자리 (종국 국면이 섞인 수 세기)

    /// 없으면 어떤 결함이 초록으로 통과하는가: **합법 수가 0 인 국면에서 수 세기가 0 을 내지 않는 결함.**
    /// Swift 에서는 빈 배열 reduce 가 0 이라 눈에 안 띄지만, 같은 기대값을 베껴 쓰는 SQL 쪽에서는
    /// `array_length(빈 배열, 1)` 이 NULL 이라 합계가 통째로 사라진다. 두 구현이 같은 숫자를 읽으므로,
    /// 이 자리를 Swift 에서 못 박아 두면 SQL 쪽 단언도 같은 자리를 가리킬 수 있다.
    @Test("잎 ⑦⑧ — 외통·스테일메이트는 어느 깊이에서도 0")
    func terminalLeavesCountZeroAtEveryDepth() throws {
        for item in try chessPerftFixture().leaves where item.counts[0] == 0 {
            for depth in 1...item.counts.count { try expectChessPerft(item, depth: depth) }
            let position = try #require(ChessPosition(fen: item.fen), "\(item.label)")
            #expect(ChessRules.legalMoves(in: position).isEmpty, "\(item.label): 둘 수가 있으면 잎이 아니다")
            #expect(ChessRules.perftDivide(position, depth: 2).isEmpty, "\(item.label): divide 가 비어야 한다")
        }
    }

    /// 없으면 어떤 결함이 초록으로 통과하는가: **0 을 특별 취급해 비껴가는 구현.** ⑦⑧ 은 통째로 0 이라
    /// "처음부터 끝까지 0" 으로도 맞힐 수 있지만, ⑨ 는 열일곱 줄 중 **한 줄만** 0 이다 — 그 한 줄이
    /// 합계를 삼키면 128 이 아니라 아무 값도 안 나온다. 사유(외통/스테일메이트)도 함께 잰다:
    /// 숫자만 재면 "어쩌다 0" 과 "종국이라 0" 이 구분되지 않는다.
    @Test("잎 ⑨ — 종국 잎 한 줄이 섞인 깊이 2 가 128, 그 한 줄은 a1a8")
    func leafMixedIntoDepthTwoStillSums() throws {
        let item = try chessPerftCase("⑨")
        for depth in 1...item.counts.count { try expectChessPerft(item, depth: depth) }

        let position = try #require(ChessPosition(fen: item.fen), "\(item.label)")
        let divide = ChessRules.perftDivide(position, depth: 2)
        let terminal = divide.filter { $0.nodes == 0 }.map(\.move.uci).sorted()
        #expect(terminal == (item.terminalChildren ?? []).sorted(), "\(item.label): 노드 0 인 줄")
        #expect(divide.count == item.counts[0], "\(item.label): divide 줄 수 = 깊이 1")
        #expect(divide.reduce(0) { $0 + $1.nodes } == item.counts[1], "\(item.label): divide 합 = 깊이 2")

        // 그 한 줄이 **왜** 0 인지까지 잰다 — 외통이어야 한다(스테일메이트면 다른 국면을 집은 것이다).
        for uci in item.terminalChildren ?? [] {
            let row = try #require(divide.first { $0.move.uci == uci }, "\(uci) 줄이 없다")
            let after = try #require(ChessRules.apply(row.move, to: position), "\(uci) 를 못 뒀다")
            #expect(ChessRules.outcome(position: after) == .checkmate(winner: position.sideToMove),
                    "\(item.label): \(uci) 뒤가 외통이 아니다")
        }
    }

    /// 잎 자리가 **자기가 말하는 종국**인지. 픽스처의 `outcome` 과 엔진 판정을 맞세운다 —
    /// 안 재면 "0 이 나오는 아무 국면"으로 바뀌어도 초록이고, SQL 쪽은 그 FEN 을 그대로 베껴 간다.
    @Test("잎 자리의 종국 사유가 픽스처와 같다")
    func leafOutcomesMatchFixture() throws {
        for item in try chessPerftFixture().leaves {
            let position = try #require(ChessPosition(fen: item.fen), "\(item.label)")
            let actual = ChessRules.outcome(position: position)
            let expected: ChessOutcome?
            switch item.outcome {
            case "checkmate:white": expected = .checkmate(winner: .white)
            case "checkmate:black": expected = .checkmate(winner: .black)
            case "stalemate": expected = .stalemate
            case nil: expected = nil
            case let other?:
                Issue.record("\(item.label): 모르는 outcome 값 \(other) — 픽스처가 말하는 종국 사유를 엔진 판정과 맞세울 수 없다")
                continue
            }
            #expect(actual == expected, "\(item.label): 종국 사유가 픽스처와 다르다(실제 \(String(describing: actual)))")
        }
    }

    // 깊은 자리: 다섯을 합쳐 1,562만 노드(아래 ③ d5 를 뺀 넷이 1,495만)다. 기본 게이트에 두면 게이트가 길어져 아무도 안 돌린다.
    // 넷을 따로 둔 까닭: 하나가 어긋났을 때 **어느 국면**인지 테스트 이름이 바로 말해 주고,
    // 각자의 소요 시간이 그 국면의 처리량(노드/초)이 된다 — 규칙을 고친 뒤 느려졌는지도 같은 자리에서 보인다.
    @Test("깊은 수 세기 ① 초기 배치 d5 — 4,865,609 (CHESS_PERFT_DEEP=1)",
          .enabled(if: ProcessInfo.processInfo.environment["CHESS_PERFT_DEEP"] == "1"))
    func deepStartPositionDepthFive() throws {
        try expectChessPerft(try chessPerftCase("①"), depth: 5)
    }

    @Test("깊은 수 세기 ③ 폰 끝내기 d5 — 674,624 (CHESS_PERFT_DEEP=1)",
          .enabled(if: ProcessInfo.processInfo.environment["CHESS_PERFT_DEEP"] == "1"))
    func deepPawnEndgameDepthFive() throws {
        try expectChessPerft(try chessPerftCase("③"), depth: 5)
    }

    @Test("깊은 수 세기 ② Kiwipete d4 — 4,085,603 (CHESS_PERFT_DEEP=1)",
          .enabled(if: ProcessInfo.processInfo.environment["CHESS_PERFT_DEEP"] == "1"))
    func deepKiwipeteDepthFour() throws {
        try expectChessPerft(try chessPerftCase("②"), depth: 4)
    }

    @Test("깊은 수 세기 ⑤ 승격 직전 d4 — 2,103,487 (CHESS_PERFT_DEEP=1)",
          .enabled(if: ProcessInfo.processInfo.environment["CHESS_PERFT_DEEP"] == "1"))
    func deepPromotionDepthFour() throws {
        try expectChessPerft(try chessPerftCase("⑤"), depth: 4)
    }

    @Test("깊은 수 세기 ⑥ 대칭 중반 d4 — 3,894,594 (CHESS_PERFT_DEEP=1)",
          .enabled(if: ProcessInfo.processInfo.environment["CHESS_PERFT_DEEP"] == "1"))
    func deepMidgameDepthFour() throws {
        try expectChessPerft(try chessPerftCase("⑥"), depth: 4)
    }

    /// 수 세기가 **합법 수 생성과 같은 것**을 세는지. divide 의 합이 한 깊이 위의 수 세기와 같아야 하고,
    /// divide 의 줄 수는 합법 수 개수여야 한다 — 수 세기만 따로 빠른 길을 타다가 생성기와 갈리면 여기서 걸린다.
    /// 잎 자리까지 함께 돈다: 거기서는 "줄 수 0 · 합 0" 이 되어야 한다(빈 합계의 경계).
    @Test("divide 의 합 = 한 깊이 위의 수 세기, 줄 수 = 합법 수 개수")
    func divideAgreesWithLegalMoveGeneration() throws {
        for item in try chessPerftFixture().all {
            let position = try #require(ChessPosition(fen: item.fen))
            let divide = ChessRules.perftDivide(position, depth: 2)
            #expect(divide.count == ChessRules.legalMoves(in: position).count, "\(item.label)")
            #expect(divide.reduce(0) { $0 + $1.nodes } == item.counts[1], "\(item.label)")
        }
    }
}
