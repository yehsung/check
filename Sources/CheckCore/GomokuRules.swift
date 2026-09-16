import Foundation

// 1:1 오목(렌주룰, 15×15, 흑만 금수) 착수 판정 — **순수·결정적·Sendable**.
//
// ── 규범은 이 파일이 아니다 ──
// 판정 정의는 조사 확정본 rules.final.md(D0~D7)와 §4.2 의사코드다. 이 파일은 그것을 **그대로** 옮긴다:
//  · 방향 순서 가로(1,0) → 세로(0,1) → /(1,1) → \(1,-1)
//  · 전환점 순서 +d 먼저, 그다음 −d
//  · 3 판정은 왼쪽부터 단락 평가(any), threes == 2 즉시 반환, 조기 종료
//  · 노드는 judgeBlack **진입마다 1**(루트 포함), nodes > 예산이 되는 순간 초과
// 이 순서가 바뀌면 판정 결과는 같아도 **노드 수**가 달라지고, 그러면 서버(gomoku_judge)와 예산 초과
// 여부가 갈린다 — 앱은 둘 수 있다고 보여 주는데 서버가 거절하는 자리가 생긴다. 코퍼스
// (Tests/checkTests/Fixtures/renju-cases.json)의 nodes 기대값이 그 순서를 못 박는다.
//
// ── 재귀 중 판 상태 (규범 A3) ──
// 재귀는 **조상 가상 돌을 모두 둔 판**에서 내려간다(형제 가지의 돌은 없다). 판을 제자리에서 고치고
// 돌아올 때 되돌린다(defer). 조상 돌을 치우는 구현은 틀릴 뿐 아니라 끝나지도 않는다(K36·D01 실측).
//
// ── 5목 전환점은 무효 (설계자 확정 D-2) ──
// 전환점 q 를 판정한 결과가 win 이면 그 3은 진짜 3이 아니다(RIF THREE 정의 문언, 모든 재귀 깊이).
// 그래서 아래 3 판정은 `== .legal` 만 유효로 센다.

/// 돌 색. 흑 선공.
package nonisolated enum GomokuColor: String, Sendable, Codable, CaseIterable {
    case black, white

    package var opponent: GomokuColor { self == .black ? .white : .black }
}

/// x = 열 A..O(0…14, 왼→오), y = 행 1..15(0…14, 아래→위). 서버 board 인덱스 = y*15 + x.
package nonisolated struct GomokuPoint: Hashable, Sendable {
    package let x: Int
    package let y: Int

    /// 범위 밖이면 nil. 이 타입의 값은 **언제나 판 안**이다 — 판정 함수가 범위를 다시 묻지 않는 근거.
    package init?(x: Int, y: Int) {
        guard (0..<GomokuBoard.size).contains(x), (0..<GomokuBoard.size).contains(y) else { return nil }
        self.x = x
        self.y = y
    }

    /// "H8" 같은 표기. 정규형 `^[A-O]([1-9]|1[0-5])$` **만** 받는다(설계자 확정 D-3).
    /// 소문자·0 채움·공백·전각 숫자는 모두 nil 이다 — 앱과 서버 어느 쪽도 정규화 코드를 두지 않아야
    /// 둘이 갈릴 여지가 없다. 정규식 대신 스칼라를 직접 보는 이유: `$` 는 끝 줄바꿈을 허용하는 엔진이 있다.
    package init?(notation: String) {
        let scalars = Array(notation.unicodeScalars)
        guard scalars.count == 2 || scalars.count == 3 else { return nil }
        let column = scalars[0].value
        guard column >= 0x41, column <= 0x4F else { return nil }            // A…O
        let digits = scalars.dropFirst()
        guard digits.allSatisfy({ $0.value >= 0x30 && $0.value <= 0x39 }) else { return nil }
        guard let first = digits.first, first.value != 0x30 else { return nil }   // 0 채움·"0" 금지
        var row = 0
        for digit in digits { row = row * 10 + Int(digit.value - 0x30) }
        guard (1...GomokuBoard.size).contains(row) else { return nil }
        self.init(x: Int(column - 0x41), y: row - 1)
    }

    package var notation: String {
        let column = Character(UnicodeScalar(UInt8(0x41 + x)))
        return "\(column)\(y + 1)"
    }
}

/// 흑 금수의 종류. rawValue 는 서버 `gomoku_judge` 의 반환 어휘와 **문자 그대로 같다**.
package nonisolated enum GomokuForbiddenReason: String, Sendable {
    case doubleThree = "forbidden-double-three",
         doubleFour = "forbidden-double-four",
         overline = "forbidden-overline",
         budget = "forbidden-budget"
}

extension GomokuForbiddenReason {
    /// 서버 `forbidden{reason}` 의 값을 읽는다. 서버가 판정 어휘 전체('forbidden-double-three')를 싣든
    /// 접두사를 뗀 값('double-three', 'budget')을 싣든 같은 사유로 읽는다 — 어느 쪽으로 오든
    /// "금수라 둘 수 없어요"를 말하지 못하는 경로가 생기면 안 된다. 모르는 값은 nil.
    package nonisolated init?(serverReason: String?) {
        guard let raw = serverReason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return nil }
        let full = raw.hasPrefix("forbidden-") ? raw : "forbidden-\(raw)"
        self.init(rawValue: full.replacingOccurrences(of: "_", with: "-"))
    }
}

package nonisolated enum GomokuJudgement: Equatable, Sendable {
    case legal, win, forbidden(GomokuForbiddenReason), occupied, outOfRange
}

/// 15×15 판. 칸 값은 0 빈칸 / 1 흑 / 2 백.
package nonisolated struct GomokuBoard: Equatable, Sendable {
    package static let size = 15
    package static let cellCount = size * size

    fileprivate var cells: [UInt8]

    package init() {
        cells = Array(repeating: 0, count: Self.cellCount)
    }

    /// 서버 board 문자열(225자, '.', 'b', 'w'). 길이나 문자가 하나라도 어긋나면 nil —
    /// 손상된 판을 "대충 읽어" 그리면 둘 수 없는 자리를 둘 수 있다고 보여 준다.
    package init?(serverString: String) {
        let bytes = Array(serverString.utf8)
        guard bytes.count == Self.cellCount else { return nil }
        var cells = [UInt8](repeating: 0, count: Self.cellCount)
        for (index, byte) in bytes.enumerated() {
            switch byte {
            case UInt8(ascii: "."): cells[index] = 0
            case UInt8(ascii: "b"): cells[index] = 1
            case UInt8(ascii: "w"): cells[index] = 2
            default: return nil
            }
        }
        self.cells = cells
    }

    package var serverString: String {
        String(decoding: cells.map { cell -> UInt8 in
            switch cell {
            case 1: return UInt8(ascii: "b")
            case 2: return UInt8(ascii: "w")
            default: return UInt8(ascii: ".")
            }
        }, as: UTF8.self)
    }

    package subscript(_ point: GomokuPoint) -> GomokuColor? {
        get {
            switch cells[point.y * Self.size + point.x] {
            case 1: return .black
            case 2: return .white
            default: return nil
            }
        }
        set {
            let value: UInt8
            switch newValue {
            case .black?: value = 1
            case .white?: value = 2
            case nil: value = 0
            }
            cells[point.y * Self.size + point.x] = value
        }
    }

    package var stoneCount: Int { cells.reduce(0) { $0 + ($1 == 0 ? 0 : 1) } }
}

package nonisolated enum GomokuRules {
    /// 노드 예산(설계자 확정 D-1). **서버 gomoku_judge 와 같은 상수**여야 한다 — 한쪽만 바꾸면
    /// 앱은 둘 수 있다고 보여 주는 자리를 서버가 거절한다(또는 그 반대).
    package static let nodeBudget = 10_000

    package static func judge(board: GomokuBoard, point: GomokuPoint, color: GomokuColor) -> GomokuJudgement {
        judgeCounting(board: board, point: point, color: color, budget: nodeBudget).judgement
    }

    /// 흑 차례 X 표시용: 빈칸 중 흑에게 금수(예산 초과 포함)인 칸.
    /// `budget` 은 앱에서는 언제나 `nodeBudget` 이다. 인자로 둔 이유는 검증이다 — 실제 국면은 예산의 1/300 도 안 써서,
    /// 예산 초과 칸이 X 로 남는지는 작은 예산을 넣어야만 잴 수 있다.
    package static func forbiddenPoints(
        board: GomokuBoard, budget: Int = GomokuRules.nodeBudget
    ) -> [GomokuPoint: GomokuForbiddenReason] {
        var engine = RenjuEngine(cells: board.cells, budget: budget)
        var result: [GomokuPoint: GomokuForbiddenReason] = [:]
        for y in 0..<GomokuBoard.size {
            for x in 0..<GomokuBoard.size where engine.cells[y * GomokuBoard.size + x] == 0 {
                engine.nodes = 0
                let reason: GomokuForbiddenReason?
                do {
                    switch try engine.judgeBlack(x, y) {
                    case .overline: reason = .overline
                    case .doubleFour: reason = .doubleFour
                    case .doubleThree: reason = .doubleThree
                    case .win, .legal: reason = nil
                    }
                } catch {
                    reason = .budget
                }
                if let reason, let point = GomokuPoint(x: x, y: y) { result[point] = reason }
            }
        }
        return result
    }

    /// 판정 + 노드 수(§4.2 계수). `budget` nil 이면 예산 없음(코퍼스 교차 검증 전용).
    /// 예산을 넘으면 `.forbidden(.budget)` 이고 nodes 는 초과가 확정된 순간의 값이다.
    /// 백은 노드 1(판정 한 번)이다. 이미 돌이 있으면 `.occupied`, nodes 0(입력 오류는 노드를 세지 않는다 — §1.2).
    package static func judgeCounting(
        board: GomokuBoard,
        point: GomokuPoint,
        color: GomokuColor,
        budget: Int?
    ) -> (judgement: GomokuJudgement, nodes: Int) {
        guard board[point] == nil else { return (.occupied, 0) }
        var engine = RenjuEngine(cells: board.cells, budget: budget)
        switch color {
        case .white:
            return (engine.judgeWhite(point.x, point.y), 1)
        case .black:
            do {
                let verdict = try engine.judgeBlack(point.x, point.y)
                return (verdict.judgement, engine.nodes)
            } catch {
                return (.forbidden(.budget), engine.nodes)
            }
        }
    }
}

// MARK: - 엔진 (§4.2 의사코드 그대로)

private nonisolated struct GomokuBudgetExceeded: Error {}

private nonisolated enum BlackVerdict {
    case win, overline, doubleFour, doubleThree, legal

    var judgement: GomokuJudgement {
        switch self {
        case .win: return .win
        case .legal: return .legal
        case .overline: return .forbidden(.overline)
        case .doubleFour: return .forbidden(.doubleFour)
        case .doubleThree: return .forbidden(.doubleThree)
        }
    }
}

private nonisolated struct RenjuEngine {
    static let empty: UInt8 = 0
    static let black: UInt8 = 1
    static let white: UInt8 = 2
    /// 판 밖. 흑의 판정에서 백돌과 똑같이 '막힘'이다(흑도 빈칸도 아님).
    static let off: UInt8 = 3
    /// 규범 순서: 가로, 세로, /, \.
    static let directions: [(Int, Int)] = [(1, 0), (0, 1), (1, 1), (1, -1)]
    static let n = GomokuBoard.size

    var cells: [UInt8]
    var nodes = 0
    let budget: Int?

    init(cells: [UInt8], budget: Int?) {
        self.cells = cells
        self.budget = budget
    }

    @inline(__always)
    func at(_ x: Int, _ y: Int) -> UInt8 {
        guard x >= 0, x < Self.n, y >= 0, y < Self.n else { return Self.off }
        return cells[y * Self.n + x]
    }

    /// D0: (x,y)를 지나는 `color` 연속 수(p 포함, p 는 이미 그 색으로 놓여 있다).
    func run(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int, _ color: UInt8) -> Int {
        var count = 1
        var k = 1
        while at(x + k * dx, y + k * dy) == color { count += 1; k += 1 }
        k = 1
        while at(x - k * dx, y - k * dy) == color { count += 1; k += 1 }
        return count
    }

    /// D3: p 를 포함하는 5칸 창 가운데 '흑 4 + 빈칸 1, 창 바로 바깥 두 칸이 흑 아님'인 창의
    /// 서로 다른 흑돌 집합(p 기준 오프셋 비트 마스크) 개수. 한 줄에서 0·1·2 만 나온다.
    func countFours(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int) -> Int {
        var masks: [Int] = []
        for s in -4...0 {
            var blacks = 0
            var empties = 0
            var mask = 0
            var inside = true
            for k in 0..<5 {
                let offset = s + k
                let value = at(x + offset * dx, y + offset * dy)
                if value == Self.off { inside = false; break }
                if value == Self.black {
                    blacks += 1
                    mask |= 1 << (offset + 4)
                } else if value == Self.empty {
                    empties += 1
                }
            }
            guard inside, blacks == 4, empties == 1 else { continue }
            if at(x + (s - 1) * dx, y + (s - 1) * dy) == Self.black { continue }
            if at(x + (s + 5) * dx, y + (s + 5) * dy) == Self.black { continue }
            if !masks.contains(mask) { masks.append(mask) }
        }
        return masks.count
    }

    /// 열린 4 판정 — d 줄 안에서만 본다(A7).
    func isStraightFour(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int) -> Bool {
        var i = 1
        while at(x + i * dx, y + i * dy) == Self.black { i += 1 }
        var j = 1
        while at(x - j * dx, y - j * dy) == Self.black { j += 1 }
        return i + j - 1 == 4
            && at(x + i * dx, y + i * dy) == Self.empty
            && at(x - j * dx, y - j * dy) == Self.empty
            && at(x + (i + 1) * dx, y + (i + 1) * dy) != Self.black
            && at(x - (j + 1) * dx, y - (j + 1) * dy) != Self.black
    }

    /// D4: 전환점 후보(각 방향 첫 흑 아닌 칸이 빈칸이면 그 칸) 중 두면 p 를 지나는 열린 4가 되는 점.
    /// 순서는 **+d 먼저**(규범).
    mutating func straightFourPoints(_ x: Int, _ y: Int, _ dx: Int, _ dy: Int) -> [(Int, Int)] {
        var points: [(Int, Int)] = []
        for sign in [1, -1] {
            var k = 1
            while at(x + sign * k * dx, y + sign * k * dy) == Self.black { k += 1 }
            let qx = x + sign * k * dx
            let qy = y + sign * k * dy
            guard at(qx, qy) == Self.empty else { continue }
            let index = qy * Self.n + qx
            cells[index] = Self.black
            if isStraightFour(x, y, dx, dy) { points.append((qx, qy)) }
            cells[index] = Self.empty
        }
        return points
    }

    /// D6 흑의 판정. (x,y)는 빈칸이고, 판에는 조상 가상 돌이 모두 있다.
    mutating func judgeBlack(_ x: Int, _ y: Int) throws(GomokuBudgetExceeded) -> BlackVerdict {
        nodes += 1
        if let budget, nodes > budget { throw GomokuBudgetExceeded() }
        let index = y * Self.n + x
        cells[index] = Self.black
        defer { cells[index] = Self.empty }

        let runs = Self.directions.map { run(x, y, $0.0, $0.1, Self.black) }
        if runs.contains(5) { return .win }
        if runs.contains(where: { $0 >= 6 }) { return .overline }

        let fours = Self.directions.map { countFours(x, y, $0.0, $0.1) }
        if fours.reduce(0, +) >= 2 { return .doubleFour }

        var shaped: [[(Int, Int)]] = []
        for (d, direction) in Self.directions.enumerated() where fours[d] == 0 {
            let points = straightFourPoints(x, y, direction.0, direction.1)
            if !points.isEmpty { shaped.append(points) }
        }
        if shaped.count < 2 { return .legal }

        var threes = 0
        for (i, points) in shaped.enumerated() {
            var valid = false
            for (qx, qy) in points where try judgeBlack(qx, qy) == .legal {
                valid = true
                break
            }
            if valid {
                threes += 1
                if threes == 2 { return .doubleThree }
            }
            if threes + (shaped.count - i - 1) < 2 { return .legal }
        }
        return .legal
    }

    /// D7 백의 판정. 금수 없음, 5 이상이면 승리.
    mutating func judgeWhite(_ x: Int, _ y: Int) -> GomokuJudgement {
        let index = y * Self.n + x
        cells[index] = Self.white
        defer { cells[index] = Self.empty }
        for direction in Self.directions where run(x, y, direction.0, direction.1, Self.white) >= 5 {
            return .win
        }
        return .legal
    }
}
