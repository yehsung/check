// GOMOKU-UI-STUB
// ui 트랙 worktree 전용 스텁이다. 통합 때 core 트랙의 GomokuRules.swift 가 이 파일을 **통째로 덮는다**.
//
// 선언(이름·타입·인자 라벨·옵셔널·격리)은 설계서 §6.2 를 글자 그대로 옮겼다. 판정은 렌더·미리보기용 **단순 흉내**다 —
// 렌주 규범(끊어진 3·재귀 거짓 3·노드 예산)을 구현하지 않는다. 뷰는 §6.2 선언만 쓴다.
// ★ 여기에 선언에 없는 공개 API 를 더하지 마라 — 뷰가 그걸 쓰는 순간 통합 때 컴파일이 깨진다.

import Foundation

nonisolated enum GomokuColor: String, Sendable, Codable, CaseIterable { case black, white
    var opponent: GomokuColor { self == .black ? .white : .black } }

/// x = 열 A..O(0…14, 왼→오), y = 행 1..15(0…14, 아래→위). 서버 board 인덱스 = y*15 + x.
nonisolated struct GomokuPoint: Hashable, Sendable {
    let x: Int; let y: Int

    init?(x: Int, y: Int) {
        guard (0..<GomokuBoard.size).contains(x), (0..<GomokuBoard.size).contains(y) else { return nil }
        self.x = x
        self.y = y
    }

    init?(notation: String) {
        guard let first = notation.first,
              let column = GomokuPoint.columnLetters.firstIndex(of: first) else { return nil }
        let digits = notation.dropFirst()
        guard !digits.isEmpty, digits.first != "0",
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let row = Int(digits), (1...GomokuBoard.size).contains(row) else { return nil }
        self.init(x: column, y: row - 1)
    }

    var notation: String { "\(GomokuPoint.columnLetters[x])\(y + 1)" }

    private static let columnLetters = Array("ABCDEFGHIJKLMNO")
}

nonisolated enum GomokuForbiddenReason: String, Sendable {
    case doubleThree = "forbidden-double-three", doubleFour = "forbidden-double-four",
         overline = "forbidden-overline", budget = "forbidden-budget"
}

nonisolated enum GomokuJudgement: Equatable, Sendable { case legal, win, forbidden(GomokuForbiddenReason), occupied, outOfRange }

nonisolated struct GomokuBoard: Equatable, Sendable {
    static let size = 15

    private var cells: [GomokuColor?]

    init() { cells = Array(repeating: nil, count: GomokuBoard.size * GomokuBoard.size) }

    init?(serverString: String) {
        let characters = Array(serverString)
        guard characters.count == GomokuBoard.size * GomokuBoard.size else { return nil }
        var parsed: [GomokuColor?] = []
        parsed.reserveCapacity(characters.count)
        for character in characters {
            switch character {
            case ".": parsed.append(nil)
            case "b": parsed.append(.black)
            case "w": parsed.append(.white)
            default: return nil
            }
        }
        cells = parsed
    }

    var serverString: String {
        String(cells.map { cell -> Character in
            switch cell {
            case nil: return "."
            case .black?: return "b"
            case .white?: return "w"
            }
        })
    }

    subscript(_ point: GomokuPoint) -> GomokuColor? {
        get { cells[point.y * GomokuBoard.size + point.x] }
        set { cells[point.y * GomokuBoard.size + point.x] = newValue }
    }

    var stoneCount: Int { cells.reduce(0) { $0 + ($1 == nil ? 0 : 1) } }
}

nonisolated enum GomokuRules {
    static let nodeBudget = 10_000

    /// 스텁 판정(흉내): 연속 수로 5목·장목, 5칸 창으로 4, 양끝이 열린 연속 3 으로 3 을 센다. 재귀가 없다.
    static func judge(board: GomokuBoard, point: GomokuPoint, color: GomokuColor) -> GomokuJudgement {
        guard board[point] == nil else { return .occupied }
        var placed = board
        placed[point] = color
        let directions = [(1, 0), (0, 1), (1, 1), (1, -1)]
        let runs = directions.map { run(placed, point, $0, color) }
        if color == .white {
            return runs.contains(where: { $0 >= 5 }) ? .win : .legal
        }
        if runs.contains(5) { return .win }
        if runs.contains(where: { $0 >= 6 }) { return .forbidden(.overline) }
        let fours = directions.map { fourCount(placed, point, $0) }
        if fours.reduce(0, +) >= 2 { return .forbidden(.doubleFour) }
        var threes = 0
        for (index, direction) in directions.enumerated() where fours[index] == 0 {
            if isOpenThree(placed, point, direction) { threes += 1 }
        }
        return threes >= 2 ? .forbidden(.doubleThree) : .legal
    }

    /// 흑 차례 X 표시용: 빈칸 중 흑에게 금수(예산 초과 포함)인 칸.
    static func forbiddenPoints(board: GomokuBoard) -> [GomokuPoint: GomokuForbiddenReason] {
        var result: [GomokuPoint: GomokuForbiddenReason] = [:]
        for y in 0..<GomokuBoard.size {
            for x in 0..<GomokuBoard.size {
                guard let point = GomokuPoint(x: x, y: y), board[point] == nil else { continue }
                if case .forbidden(let reason) = judge(board: board, point: point, color: .black) {
                    result[point] = reason
                }
            }
        }
        return result
    }

    // MARK: 스텁 내부 계산(비공개)

    /// -1 판 밖 · 0 빈칸 · 1 흑 · 2 백.
    private static func cell(_ board: GomokuBoard, _ x: Int, _ y: Int) -> Int {
        guard let point = GomokuPoint(x: x, y: y) else { return -1 }
        switch board[point] {
        case nil: return 0
        case .black?: return 1
        case .white?: return 2
        }
    }

    private static func run(_ board: GomokuBoard, _ p: GomokuPoint, _ d: (Int, Int), _ color: GomokuColor) -> Int {
        let target = color == .black ? 1 : 2
        var count = 1
        for sign in [1, -1] {
            var k = 1
            while cell(board, p.x + sign * k * d.0, p.y + sign * k * d.1) == target { count += 1; k += 1 }
        }
        return count
    }

    private static func fourCount(_ board: GomokuBoard, _ p: GomokuPoint, _ d: (Int, Int)) -> Int {
        var shapes = Set<[Int]>()
        for start in -4...0 {
            var blacks: [Int] = []
            var empties = 0
            var offBoard = false
            for k in 0..<5 {
                let offset = start + k
                switch cell(board, p.x + offset * d.0, p.y + offset * d.1) {
                case 1: blacks.append(offset)
                case 0: empties += 1
                case -1: offBoard = true
                default: break
                }
            }
            guard !offBoard, blacks.count == 4, empties == 1 else { continue }
            let before = cell(board, p.x + (start - 1) * d.0, p.y + (start - 1) * d.1)
            let after = cell(board, p.x + (start + 5) * d.0, p.y + (start + 5) * d.1)
            guard before != 1, after != 1 else { continue }
            shapes.insert(blacks)
        }
        return shapes.count
    }

    private static func isOpenThree(_ board: GomokuBoard, _ p: GomokuPoint, _ d: (Int, Int)) -> Bool {
        var forward = 1
        while cell(board, p.x + forward * d.0, p.y + forward * d.1) == 1 { forward += 1 }
        var backward = 1
        while cell(board, p.x - backward * d.0, p.y - backward * d.1) == 1 { backward += 1 }
        guard forward + backward - 1 == 3 else { return false }
        return cell(board, p.x + forward * d.0, p.y + forward * d.1) == 0
            && cell(board, p.x - backward * d.0, p.y - backward * d.1) == 0
            && cell(board, p.x + (forward + 1) * d.0, p.y + (forward + 1) * d.1) != 1
            && cell(board, p.x - (backward + 1) * d.0, p.y - (backward + 1) * d.1) != 1
    }
}
