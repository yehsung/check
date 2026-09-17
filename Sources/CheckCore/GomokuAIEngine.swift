import Foundation

// 오목 AI 탐색 엔진 본체. 공개 입구는 GomokuAI.swift 의 `GomokuAI.bestMove` 하나다. 설계: docs/plan/gomoku-ai.md §2.
//
// ── 판 표현 ──
// 15×15 판을 사방 5칸씩 벽(3)으로 두른 25×25 배열에 둔다. 한 칸에서 네 방향으로 ±5칸을 읽어도 경계 검사가 없다.
// 칸 값: 0 빈칸 · 1 흑 · 2 백 · 3 벽. 방향: 가로(+1) · 세로(+25) · /(+26) · \(−24).
//
// ── 줄 모양 표 (증분 평가의 핵심) ──
// 빈칸 p 에 색 c 가 **둔다면** 방향 d 에서 어떤 모양이 되는가를, p 양옆 5칸씩(10칸, 칸마다 빈칸/내 돌/막힘 3가지 = 3^10)
// 으로 미리 계산해 둔다. 착수 하나가 바꾸는 칸은 그 돌을 지나는 네 줄의 ±5칸(최대 40칸)뿐이라, 그 칸들만 다시 찾아본다.
// 모양: 5목 > 열린 4(5목 자리 둘) > 4(5목 자리 하나) > 열린 3(한 수 더 두면 열린 4) > 3 > 열린 2 > 2.
// 흑의 5목은 **정확히 5**(장목은 5목이 아니다) — 렌주 판정(GomokuRules)의 D6 과 같다. ±5칸을 보므로 장목 여부를 안다.
//
// ── 렌주 ──
// 흑 후보의 금수 여부는 `GomokuRenjuProbe`(= GomokuRules 의 판정기 그대로)로 묻는다. 대부분의 칸은 주변 흑돌 수만으로
// "금수일 수 없다"가 확정돼 판정기를 부르지 않는다(아래 `isLegal` 의 걸러내기는 **금수를 합법으로 잘못 보내지 않는 쪽**으로만 줄인다).
// 흑의 위협(5목 자리 · 열린 4 자리)은 그 자리가 흑에게 합법일 때만 위협으로 센다 — 백이 흑의 금수 자리를 노리는 수가 여기서 나온다.
//
// ── 탐색 ──
// 즉결(5목 · 상대 4 막기 · 열린 4) → 내 VCF → 상대 VCF 끊기 → 반복 심화 네가맥스 알파베타(치환표 · 위협 가지치기 · 강제수 연장
// · 잎 VCF). 루트에서는 점수가 **정확히 같은** 최선의 수들을 모아 씨앗 무작위로 하나 고른다.
//
// 프라이버시·동시성: 이 엔진은 판 숫자만 본다. 한 번의 bestMove 호출 안에서만 살고 스레드를 넘나들지 않는다.

nonisolated enum GomokuAIShape {
    static let none: UInt8 = 0
    static let two: UInt8 = 1
    static let openTwo: UInt8 = 2
    static let three: UInt8 = 3
    static let openThree: UInt8 = 4
    static let four: UInt8 = 5
    static let openFour: UInt8 = 6
    static let five: UInt8 = 7
}

/// 네 방향 모양을 합친 칸의 위협 등급.
nonisolated enum GomokuAICategory {
    static let none: UInt8 = 0
    static let weak: UInt8 = 1
    static let building: UInt8 = 2
    static let openThree: UInt8 = 3
    static let four: UInt8 = 4
    static let doubleThree: UInt8 = 5
    static let fourThree: UInt8 = 6
    /// 열린 4 또는 4-4(흑이면 금수일 수 있다 — 합법 확인은 따로).
    static let openFour: UInt8 = 7
    static let five: UInt8 = 8
}

nonisolated enum GomokuAITables {
    static let keyCount = 59_049   // 3^10

    /// 흑(정확히 5) · 백(5 이상) 줄 모양 표.
    static let blackShapes: [UInt8] = buildShapes(exactFive: true)
    static let whiteShapes: [UInt8] = buildShapes(exactFive: false)

    /// 네 방향 모양(각 3비트) → 등급 · 칸 점수.
    static let combos: (categories: [UInt8], values: [Int32]) = buildCombos()

    /// Zobrist 키: [패딩 칸 625 × 색 2] + 백 차례 키. 고정 씨앗이라 실행마다 같다.
    static let zobrist: [UInt64] = {
        var rng = GomokuAISplitMix64(seed: 0x6F6D_6F6B_7541_4921)
        return (0..<(625 * 2 + 1)).map { _ in rng.next() }
    }()

    private static func isFive(_ line: [UInt8], exact: Bool) -> Bool {
        var run = 1
        var j = 4
        while j >= 0, line[j] == 1 { run += 1; j -= 1 }
        j = 6
        while j <= 10, line[j] == 1 { run += 1; j += 1 }
        return exact ? run == 5 : run >= 5
    }

    /// 칸(가운데, 이미 내 돌)을 지나는 한 줄의 모양. 자식(빈칸 하나에 내 돌을 더한 줄)은 내 돌이 하나 더 많아 먼저 계산돼 있다.
    private static func buildShapes(exactFive: Bool) -> [UInt8] {
        var pow3 = [Int](repeating: 1, count: 10)
        for i in 1..<10 { pow3[i] = pow3[i - 1] * 3 }
        var buckets = [[Int]](repeating: [], count: 11)
        for key in 0..<keyCount {
            var k = key
            var ones = 0
            for _ in 0..<10 {
                if k % 3 == 1 { ones += 1 }
                k /= 3
            }
            buckets[ones].append(key)
        }
        var table = [UInt8](repeating: 0, count: keyCount)
        var line = [UInt8](repeating: 0, count: 11)
        for ones in stride(from: 10, through: 0, by: -1) {
            for key in buckets[ones] {
                var k = key
                for i in 0..<10 {
                    line[i < 5 ? i : i + 1] = UInt8(k % 3)
                    k /= 3
                }
                line[5] = 1
                if isFive(line, exact: exactFive) {
                    table[key] = GomokuAIShape.five
                    continue
                }
                // 5목 자리: 가운데를 포함하는 5목은 ±4 안에 있다.
                var winPoints = 0
                for q in 1...9 where q != 5 && line[q] == 0 {
                    line[q] = 1
                    if isFive(line, exact: exactFive) { winPoints += 1 }
                    line[q] = 0
                }
                if winPoints >= 2 { table[key] = GomokuAIShape.openFour; continue }
                if winPoints == 1 { table[key] = GomokuAIShape.four; continue }
                var best = GomokuAIShape.none
                for q in 1...9 where q != 5 && line[q] == 0 {
                    let child = table[key + pow3[q < 5 ? q : q - 1]]
                    switch child {
                    case GomokuAIShape.openFour: best = max(best, GomokuAIShape.openThree)
                    case GomokuAIShape.four: best = max(best, GomokuAIShape.three)
                    case GomokuAIShape.openThree: best = max(best, GomokuAIShape.openTwo)
                    case GomokuAIShape.three: best = max(best, GomokuAIShape.two)
                    default: break
                    }
                }
                table[key] = best
            }
        }
        return table
    }

    private static func buildCombos() -> (categories: [UInt8], values: [Int32]) {
        // 방향 하나의 모양 점수(내가 거기 두면 얻는 잠재력).
        let dirValue: [Int32] = [0, 8, 40, 50, 450, 520, 6_000, 60_000]
        var categories = [UInt8](repeating: 0, count: 4096)
        var values = [Int32](repeating: 0, count: 4096)
        for index in 0..<4096 {
            let shapes = [(index >> 9) & 7, (index >> 6) & 7, (index >> 3) & 7, index & 7]
            var n = [Int](repeating: 0, count: 8)
            var value: Int32 = 0
            for s in shapes {
                n[s] += 1
                value += dirValue[s]
            }
            let category: UInt8
            if n[7] > 0 {
                category = GomokuAICategory.five
            } else if n[6] > 0 || n[5] >= 2 {
                category = GomokuAICategory.openFour
                value += 5_000
            } else if n[5] == 1 && n[4] >= 1 {
                category = GomokuAICategory.fourThree
                value += 4_000
            } else if n[4] >= 2 {
                category = GomokuAICategory.doubleThree
                value += 2_000
            } else if n[5] == 1 {
                category = GomokuAICategory.four
                if n[3] + n[2] >= 1 { value += 150 }
            } else if n[4] == 1 {
                category = GomokuAICategory.openThree
                if n[3] + n[2] >= 1 { value += 300 }
            } else if n[3] + n[2] >= 1 {
                category = GomokuAICategory.building
                if n[3] + n[2] >= 2 { value += 120 }
            } else if n[1] >= 1 {
                category = GomokuAICategory.weak
            } else {
                category = GomokuAICategory.none
            }
            categories[index] = category
            values[index] = value
        }
        return (categories, values)
    }
}

/// 결정적 난수(SplitMix64). 동점 수 고르기와 Zobrist 키에 쓴다.
nonisolated struct GomokuAISplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

nonisolated final class GomokuAIEngine {
    static let width = 25
    static let cellCount = 625
    static let win = 1_000_000
    static let infinity = 10_000_000
    static let maxPly = 96
    static let ttBits = 17

    // 판 상태
    private let cells: UnsafeMutablePointer<UInt8>
    private let shapes: UnsafeMutablePointer<UInt8>       // p*8 + c*4 + d
    private let categories: UnsafeMutablePointer<UInt8>   // p*2 + c
    private let values: UnsafeMutablePointer<Int32>       // p*2 + c
    private let neighbors: UnsafeMutablePointer<UInt8>    // 반경 2 안 돌 수
    private let blackTable: UnsafeMutablePointer<UInt8>
    private let whiteTable: UnsafeMutablePointer<UInt8>
    private let comboCategories: UnsafeMutablePointer<UInt8>
    private let comboValues: UnsafeMutablePointer<Int32>
    private let zobrist: UnsafeMutablePointer<UInt64>
    private var sums: (Int, Int) = (0, 0)
    /// 색별 돌의 중앙 가까움 합(고리 0…7). 줄 모양 점수가 같은 수끼리를 가르는 작은 항 — 한 점 옆 대신 두 칸 떨어진 수를 동점으로 보지 않게.
    private var centrality: (Int, Int) = (0, 0)
    static let centralityWeight = 2
    private(set) var hash: UInt64 = 0
    private(set) var stones = 0
    private var minX = 15, maxX = -1, minY = 15, maxY = -1
    private let boxStack: UnsafeMutablePointer<Int32>     // stones*4
    private var probe: GomokuRenjuProbe
    private var legalCache: [UInt64: Bool] = [:]

    // 탐색 상태
    private let deltas: (Int, Int, Int, Int) = (1, 25, 26, -24)
    private let deadline: ContinuousClock.Instant
    private let started: ContinuousClock.Instant
    private let budget: Duration
    private let isCancelled: @Sendable () -> Bool
    private(set) var aborted = false
    private(set) var nodes = 0
    private let tt: UnsafeMutablePointer<TTEntry>
    private let ttMask: Int
    private let moveBuffer: UnsafeMutablePointer<Int32>   // ply*225
    private let priorityBuffer: UnsafeMutablePointer<Int32>
    /// VCF 실패 기억: 국면(+공격자) → 실패가 확정된 최대 깊이. 예산에 걸려 끊긴 실패는 적지 않는다.
    private var vcfFailures: [UInt64: Int] = [:]
    private var vcfBudget = 0
    private var vcfBudgetHit = false
    /// 탐색이 끝까지 마친 가장 깊은 반복 심화 깊이(측정·보고용).
    private(set) var completedDepth = 0

    struct TTEntry {
        var key: UInt64 = 0
        var score: Int32 = 0
        var depth: Int16 = -1
        var flag: UInt8 = 0
        var move: Int16 = -1
    }

    init(board: GomokuBoard, budget: Duration, isCancelled: @escaping @Sendable () -> Bool) {
        cells = .allocate(capacity: Self.cellCount)
        shapes = .allocate(capacity: Self.cellCount * 8)
        categories = .allocate(capacity: Self.cellCount * 2)
        values = .allocate(capacity: Self.cellCount * 2)
        neighbors = .allocate(capacity: Self.cellCount)
        blackTable = Self.copy(GomokuAITables.blackShapes)
        whiteTable = Self.copy(GomokuAITables.whiteShapes)
        comboCategories = Self.copy(GomokuAITables.combos.categories)
        comboValues = Self.copy(GomokuAITables.combos.values)
        zobrist = Self.copy(GomokuAITables.zobrist)
        boxStack = .allocate(capacity: 226 * 4)
        tt = .allocate(capacity: 1 << Self.ttBits)
        ttMask = (1 << Self.ttBits) - 1
        moveBuffer = .allocate(capacity: Self.maxPly * 225)
        priorityBuffer = .allocate(capacity: Self.maxPly * 225)
        cells.initialize(repeating: 3, count: Self.cellCount)
        shapes.initialize(repeating: 0, count: Self.cellCount * 8)
        categories.initialize(repeating: 0, count: Self.cellCount * 2)
        values.initialize(repeating: 0, count: Self.cellCount * 2)
        neighbors.initialize(repeating: 0, count: Self.cellCount)
        boxStack.initialize(repeating: 0, count: 226 * 4)
        tt.initialize(repeating: TTEntry(), count: 1 << Self.ttBits)
        moveBuffer.initialize(repeating: 0, count: Self.maxPly * 225)
        priorityBuffer.initialize(repeating: 0, count: Self.maxPly * 225)
        probe = GomokuRenjuProbe(board: board)
        self.budget = budget
        self.isCancelled = isCancelled
        started = ContinuousClock.now
        deadline = started.advanced(by: budget)

        for y in 0..<15 {
            for x in 0..<15 { cells[Self.index(x, y)] = 0 }
        }
        for y in 0..<15 {
            for x in 0..<15 {
                guard let point = GomokuPoint(x: x, y: y), let color = board[point] else { continue }
                let p = Self.index(x, y)
                let value: UInt8 = color == .black ? 1 : 2
                cells[p] = value
                hash ^= zobrist[p * 2 + Int(value) - 1]
                stones += 1
                if value == 1 { centrality.0 += Self.ring(x, y) } else { centrality.1 += Self.ring(x, y) }
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for dy in -2...2 {
                    for dx in -2...2 { neighbors[p + dy * Self.width + dx] &+= 1 }
                }
            }
        }
        for y in 0..<15 {
            for x in 0..<15 {
                let p = Self.index(x, y)
                guard cells[p] == 0 else { continue }
                for d in 0..<4 { refreshDirection(p, d) }
                refreshCombo(p)
            }
        }
    }

    deinit {
        cells.deallocate(); shapes.deallocate(); categories.deallocate(); values.deallocate(); neighbors.deallocate()
        blackTable.deallocate(); whiteTable.deallocate(); comboCategories.deallocate(); comboValues.deallocate()
        zobrist.deallocate(); boxStack.deallocate(); tt.deallocate(); moveBuffer.deallocate(); priorityBuffer.deallocate()
    }

    private static func copy<T>(_ array: [T]) -> UnsafeMutablePointer<T> {
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: array.count)
        array.withUnsafeBufferPointer { pointer.initialize(from: $0.baseAddress!, count: array.count) }
        return pointer
    }

    @inline(__always) static func index(_ x: Int, _ y: Int) -> Int { (y + 5) * width + x + 5 }
    /// 중앙(H8)에서 몇 번째 고리 안쪽인가: 7 − 체비셰프 거리.
    @inline(__always) static func ring(_ x: Int, _ y: Int) -> Int { 7 - max(abs(x - 7), abs(y - 7)) }
    @inline(__always) static func coordinates(_ p: Int) -> (x: Int, y: Int) { (p % width - 5, p / width - 5) }

    @inline(__always) private func delta(_ d: Int) -> Int {
        switch d {
        case 0: return deltas.0
        case 1: return deltas.1
        case 2: return deltas.2
        default: return deltas.3
        }
    }

    // MARK: 증분 갱신

    @inline(__always) private func refreshDirection(_ p: Int, _ d: Int) {
        let step = delta(d)
        var blackKey = 0
        var whiteKey = 0
        var multiplier = 1
        var q = p - 5 * step
        for i in 0..<11 {
            if i != 5 {
                switch cells[q] {
                case 1: blackKey += multiplier; whiteKey += 2 * multiplier
                case 2: blackKey += 2 * multiplier; whiteKey += multiplier
                case 3: blackKey += 2 * multiplier; whiteKey += 2 * multiplier
                default: break
                }
                multiplier *= 3
            }
            q += step
        }
        shapes[p * 8 + d] = blackTable[blackKey]
        shapes[p * 8 + 4 + d] = whiteTable[whiteKey]
    }

    @inline(__always) private func refreshCombo(_ p: Int) {
        for c in 0..<2 {
            let base = p * 8 + c * 4
            let combo = Int(shapes[base]) << 9 | Int(shapes[base + 1]) << 6 | Int(shapes[base + 2]) << 3 | Int(shapes[base + 3])
            let newValue = comboValues[combo]
            let delta = Int(newValue) - Int(values[p * 2 + c])
            if c == 0 { sums.0 += delta } else { sums.1 += delta }
            values[p * 2 + c] = newValue
            categories[p * 2 + c] = comboCategories[combo]
        }
    }

    func make(_ p: Int, _ color: Int) {
        let base = stones * 4
        boxStack[base] = Int32(minX); boxStack[base + 1] = Int32(maxX)
        boxStack[base + 2] = Int32(minY); boxStack[base + 3] = Int32(maxY)
        cells[p] = UInt8(color)
        hash ^= zobrist[p * 2 + color - 1]
        let (x, y) = Self.coordinates(p)
        probe.setCell(x: x, y: y, to: color == 1 ? .black : .white)
        stones += 1
        if color == 1 { centrality.0 += Self.ring(x, y) } else { centrality.1 += Self.ring(x, y) }
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        sums.0 -= Int(values[p * 2]); sums.1 -= Int(values[p * 2 + 1])
        values[p * 2] = 0; values[p * 2 + 1] = 0
        categories[p * 2] = 0; categories[p * 2 + 1] = 0
        for dy in -2...2 {
            for dx in -2...2 { neighbors[p + dy * Self.width + dx] &+= 1 }
        }
        for d in 0..<4 {
            let step = delta(d)
            var q = p - 5 * step
            for k in -5...5 {
                if k != 0, cells[q] == 0 {
                    refreshDirection(q, d)
                    refreshCombo(q)
                }
                q += step
            }
        }
    }

    func unmake(_ p: Int) {
        let color = Int(cells[p])
        cells[p] = 0
        hash ^= zobrist[p * 2 + color - 1]
        let (x, y) = Self.coordinates(p)
        probe.setCell(x: x, y: y, to: nil)
        stones -= 1
        if color == 1 { centrality.0 -= Self.ring(x, y) } else { centrality.1 -= Self.ring(x, y) }
        let base = stones * 4
        minX = Int(boxStack[base]); maxX = Int(boxStack[base + 1])
        minY = Int(boxStack[base + 2]); maxY = Int(boxStack[base + 3])
        for dy in -2...2 {
            for dx in -2...2 { neighbors[p + dy * Self.width + dx] &-= 1 }
        }
        for d in 0..<4 { refreshDirection(p, d) }
        refreshCombo(p)
        for d in 0..<4 {
            let step = delta(d)
            var q = p - 5 * step
            for k in -5...5 {
                if k != 0, cells[q] == 0 {
                    refreshDirection(q, d)
                    refreshCombo(q)
                }
                q += step
            }
        }
    }

    // MARK: 조회

    @inline(__always) func category(_ p: Int, _ color: Int) -> UInt8 { categories[p * 2 + color - 1] }
    @inline(__always) func value(_ p: Int, _ color: Int) -> Int { Int(values[p * 2 + color - 1]) }
    @inline(__always) func isEmpty(_ p: Int) -> Bool { cells[p] == 0 }

    /// 이 칸에 두면 어느 방향이든 4(또는 열린 4·5목)가 되는가.
    @inline(__always) func makesFour(_ p: Int, _ color: Int) -> Bool {
        let base = p * 8 + (color - 1) * 4
        return shapes[base] >= GomokuAIShape.four || shapes[base + 1] >= GomokuAIShape.four
            || shapes[base + 2] >= GomokuAIShape.four || shapes[base + 3] >= GomokuAIShape.four
    }

    /// 색 `color` 가 빈칸 p 에 둘 수 있는가. 백은 언제나. 흑은 렌주 판정(5목은 합법, 금수·예산 초과는 불법).
    func isLegal(_ p: Int, _ color: Int) -> Bool {
        guard color == 1 else { return true }
        if categories[p * 2] == GomokuAICategory.five { return true }
        // 걸러내기: 금수(3-3 · 4-4 · 장목)는 적어도 두 방향에 흑이 둘 이상이거나, 한 방향에 셋 이상(한 줄 4-4)이거나,
        // ±5 안에 흑이 다섯 이상(장목)일 때만 생긴다. 그 밖은 판정기를 부를 필요가 없다.
        var directionsWithTwo = 0
        var needsJudge = false
        for d in 0..<4 {
            let step = delta(d)
            var near = 0
            var wide = 0
            for k in 1...5 {
                if cells[p + k * step] == 1 { wide += 1; if k <= 4 { near += 1 } }
                if cells[p - k * step] == 1 { wide += 1; if k <= 4 { near += 1 } }
            }
            if near >= 3 || wide >= 5 { needsJudge = true; break }
            if near >= 2 { directionsWithTwo += 1 }
        }
        if !needsJudge && directionsWithTwo < 2 { return true }
        let key = hash ^ (UInt64(p) &* 0x9E37_79B9_7F4A_7C15)
        if let cached = legalCache[key] { return cached }
        let (x, y) = Self.coordinates(p)
        let legal: Bool
        switch probe.blackJudgement(x: x, y: y) {
        case .legal, .win: legal = true
        default: legal = false
        }
        if legalCache.count > 200_000 { legalCache.removeAll(keepingCapacity: true) }
        legalCache[key] = legal
        return legal
    }

    /// 탐색할 만한 빈칸(돌 반경 2 안). 콜백으로 돌린다.
    @inline(__always) private func forEachCandidate(_ body: (Int) -> Bool) {
        guard stones > 0 else { return }
        let x0 = max(0, minX - 2), x1 = min(14, maxX + 2)
        let y0 = max(0, minY - 2), y1 = min(14, maxY + 2)
        for y in y0...y1 {
            var p = Self.index(x0, y)
            for _ in x0...x1 {
                if cells[p] == 0, neighbors[p] > 0 {
                    if !body(p) { return }
                }
                p += 1
            }
        }
    }

    /// 판 전체 빈칸 중 합법인 첫 칸(돌 반경 밖 포함). 둘 곳이 하나도 없으면 nil.
    func anyLegalCell(_ color: Int) -> Int? {
        for y in 0..<15 {
            for x in 0..<15 {
                let p = Self.index(x, y)
                if cells[p] == 0, isLegal(p, color) { return p }
            }
        }
        return nil
    }

    // MARK: 시간

    @inline(__always) private func tick() {
        nodes += 1
        if nodes & 255 == 0 {
            if ContinuousClock.now >= deadline || isCancelled() { aborted = true }
        }
    }

    func checkAbortNow() -> Bool {
        if !aborted, ContinuousClock.now >= deadline || isCancelled() { aborted = true }
        return aborted
    }

    var elapsedFraction: Double {
        let elapsed = ContinuousClock.now - started
        let total = Double(budget.components.seconds) + Double(budget.components.attoseconds) / 1e18
        let used = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return total > 0 ? used / total : 1
    }

    // MARK: VCF

    /// 공격자가 두면 막 생긴 5목 자리들(착수 m 을 지나는 네 줄에서만 찾는다). 최대 2개까지 센다.
    private func fivePoints(around m: Int, _ color: Int) -> (count: Int, first: Int) {
        var count = 0
        var first = -1
        for d in 0..<4 {
            let step = delta(d)
            var q = m - 4 * step
            for k in -4...4 {
                if k != 0, cells[q] == 0, categories[q * 2 + color - 1] == GomokuAICategory.five, q != first {
                    if first < 0 { first = q }
                    count += 1
                    if count >= 2 { return (count, first) }
                }
                q += step
            }
        }
        return (count, first)
    }

    /// 판 전체에서 색 `color` 의 5목 자리(최대 2개).
    private func globalFivePoints(_ color: Int) -> (count: Int, first: Int) {
        var count = 0
        var first = -1
        forEachCandidate { p in
            if categories[p * 2 + color - 1] == GomokuAICategory.five {
                if first < 0 { first = p }
                count += 1
            }
            return count < 2
        }
        return (count, first)
    }

    /// 공격자 차례에서 4만 연달아 두어 이기는 수순이 있는가. 있으면 첫 수(패딩 인덱스)를 돌려준다.
    /// `lastDefenderMove` 가 있으면 수비자의 5목 자리를 그 수 주변에서만 찾는다(그 전엔 수비자 5목 자리가 없었다).
    func vcfMove(attacker: Int, depth: Int, lastDefenderMove: Int?) -> Int? {
        tick()
        if aborted || vcfBudget <= 0 { vcfBudgetHit = true; return nil }
        vcfBudget -= 1
        let defender = 3 - attacker
        let memoKey = hash ^ (attacker == 2 ? zobrist[625 * 2] : 0) ^ 0x5646_4346_0000_0001
        if let failedDepth = vcfFailures[memoKey], failedDepth >= depth { return nil }

        if lastDefenderMove == nil {
            let own = globalFivePoints(attacker)
            if own.count > 0 { return own.first }
        }
        let defenderFives = lastDefenderMove.map { fivePoints(around: $0, defender) } ?? globalFivePoints(defender)
        if defenderFives.count >= 2 { return nil }

        var candidates: [Int] = []
        if defenderFives.count == 1 {
            let block = defenderFives.first
            guard makesFour(block, attacker), isLegal(block, attacker) else { return nil }
            candidates = [block]
        } else {
            forEachCandidate { p in
                if makesFour(p, attacker) { candidates.append(p) }
                return true
            }
            for p in candidates where categories[p * 2 + attacker - 1] == GomokuAICategory.openFour && isLegal(p, attacker) {
                return p
            }
        }
        guard depth > 0 else { return nil }
        candidates.sort { value($0, attacker) > value($1, attacker) }
        let hitBefore = vcfBudgetHit
        vcfBudgetHit = false
        for m in candidates {
            guard isLegal(m, attacker) else { continue }
            if defenderFives.count == 0, categories[m * 2 + attacker - 1] == GomokuAICategory.openFour { return m }
            make(m, attacker)
            let points = fivePoints(around: m, attacker)
            if points.count >= 2 { unmake(m); vcfBudgetHit = hitBefore || vcfBudgetHit; return m }
            if points.count == 0 { unmake(m); continue }
            let block = points.first
            if defender == 1, !isLegal(block, 1) { unmake(m); vcfBudgetHit = hitBefore || vcfBudgetHit; return m }
            make(block, defender)
            let found = vcfMove(attacker: attacker, depth: depth - 1, lastDefenderMove: block) != nil
            unmake(block)
            unmake(m)
            if found { vcfBudgetHit = hitBefore || vcfBudgetHit; return m }
            if aborted { break }
        }
        if !vcfBudgetHit && !aborted {
            if vcfFailures.count > 300_000 { vcfFailures.removeAll(keepingCapacity: true) }
            vcfFailures[memoKey] = max(depth, vcfFailures[memoKey] ?? -1)
        }
        vcfBudgetHit = hitBefore || vcfBudgetHit
        return nil
    }

    func hasVCF(attacker: Int, depth: Int = 12, budget: Int) -> Bool {
        vcfBudget = budget
        vcfBudgetHit = false
        return vcfMove(attacker: attacker, depth: depth, lastDefenderMove: nil) != nil
    }

    // MARK: 알파베타

    private func evaluate(_ side: Int, ply: Int) -> Int {
        let opponent = 3 - side
        // 잎 VCF: 두는 쪽이 4 로 몰아 이길 수 있으면 이긴 국면으로 본다(작은 예산).
        var hasFour = false
        forEachCandidate { p in
            if makesFour(p, side) { hasFour = true; return false }
            return true
        }
        if hasFour {
            vcfBudget = 120
            vcfBudgetHit = false
            if vcfMove(attacker: side, depth: 8, lastDefenderMove: nil) != nil { return Self.win - (ply + 20) }
        }
        let mine = (side == 1 ? sums.0 : sums.1) + Self.centralityWeight * (side == 1 ? centrality.0 : centrality.1)
        let theirs = (opponent == 1 ? sums.0 : sums.1) + Self.centralityWeight * (opponent == 1 ? centrality.0 : centrality.1)
        return mine - theirs
    }

    @inline(__always) private func toTT(_ score: Int, _ ply: Int) -> Int {
        if score > Self.win - 1000 { return score + ply }
        if score < -(Self.win - 1000) { return score - ply }
        return score
    }

    @inline(__always) private func fromTT(_ score: Int, _ ply: Int) -> Int {
        if score > Self.win - 1000 { return score - ply }
        if score < -(Self.win - 1000) { return score + ply }
        return score
    }

    /// 위협 규칙으로 후보를 모은다. 반환: (후보 수, 강제수인가, 즉결 점수). 즉결 점수가 있으면 후보는 무시한다.
    /// 후보는 moveBuffer[ply*225 ...] 에 우선순위 내림차순으로 들어간다.
    func generate(_ side: Int, ply: Int, depth: Int, limit: Int) -> (count: Int, forced: Bool, immediate: Int?) {
        let opponent = 3 - side
        let so = side - 1
        let oo = opponent - 1
        var oppFiveCount = 0
        var oppFive = -1
        var ownFive = false
        var ownOpenFour: [Int] = []
        var oppOpenFour: [Int] = []
        forEachCandidate { p in
            let mine = categories[p * 2 + so]
            let theirs = categories[p * 2 + oo]
            if mine == GomokuAICategory.five { ownFive = true; return false }
            if theirs == GomokuAICategory.five {
                if oppFive != p { oppFiveCount += 1 }
                if oppFive < 0 { oppFive = p }
            }
            if mine == GomokuAICategory.openFour { ownOpenFour.append(p) }
            if theirs == GomokuAICategory.openFour { oppOpenFour.append(p) }
            return true
        }
        let base = ply * 225
        if ownFive { return (0, false, Self.win - (ply + 1)) }
        if oppFiveCount >= 2 { return (0, false, -(Self.win - (ply + 2))) }
        if oppFiveCount == 1 {
            if side == 1, !isLegal(oppFive, 1) { return (0, false, -(Self.win - (ply + 2))) }
            moveBuffer[base] = Int32(oppFive)
            return (1, true, nil)
        }
        for p in ownOpenFour where isLegal(p, side) { return (0, false, Self.win - (ply + 3)) }

        let threatened = oppOpenFour.contains { isLegal($0, opponent) }
        var count = 0
        let cap = threatened ? 225 : limit
        forEachCandidate { p in
            if threatened {
                let theirs = categories[p * 2 + oo]
                guard makesFour(p, side) || makesFour(p, opponent) || theirs >= GomokuAICategory.doubleThree else { return true }
            }
            let priority = Int32(values[p * 2 + so]) + Int32(values[p * 2 + oo])
            // 상위 cap 개만 우선순위 내림차순으로 유지(삽입 정렬).
            var i = count
            if count < cap {
                count += 1
            } else if priority <= priorityBuffer[base + cap - 1] {
                return true
            } else {
                i = cap - 1
            }
            while i > 0, priorityBuffer[base + i - 1] < priority {
                moveBuffer[base + i] = moveBuffer[base + i - 1]
                priorityBuffer[base + i] = priorityBuffer[base + i - 1]
                i -= 1
            }
            moveBuffer[base + i] = Int32(p)
            priorityBuffer[base + i] = priority
            return true
        }
        return (count, false, nil)
    }

    private func branching(_ depth: Int) -> Int {
        if depth >= 6 { return 7 }
        if depth >= 4 { return 9 }
        if depth >= 2 { return 12 }
        return 16
    }

    func negamax(_ depth: Int, _ alphaIn: Int, _ betaIn: Int, ply: Int, side: Int) -> Int {
        tick()
        if aborted { return 0 }
        if ply >= Self.maxPly - 1 { return evaluate(side, ply: ply) }
        var alpha = alphaIn
        var beta = betaIn
        let key = hash ^ (side == 2 ? zobrist[625 * 2] : 0)
        let slot = Int(truncatingIfNeeded: key) & ttMask
        var ttMove = -1
        if tt[slot].key == key {
            ttMove = Int(tt[slot].move)
            if Int(tt[slot].depth) >= depth {
                let score = fromTT(Int(tt[slot].score), ply)
                switch tt[slot].flag {
                case 1: return score
                case 2: alpha = max(alpha, score)
                case 3: beta = min(beta, score)
                default: break
                }
                if alpha >= beta { return score }
            }
        }

        let generated = generate(side, ply: ply, depth: depth, limit: branching(depth))
        if let immediate = generated.immediate { return immediate }
        if !generated.forced && depth <= 0 { return evaluate(side, ply: ply) }
        let base = ply * 225
        let count = generated.count
        if count == 0 { return evaluate(side, ply: ply) }
        if ttMove >= 0 {
            for i in 0..<count where Int(moveBuffer[base + i]) == ttMove {
                if i > 0 {
                    let moved = moveBuffer[base + i]
                    var j = i
                    while j > 0 { moveBuffer[base + j] = moveBuffer[base + j - 1]; j -= 1 }
                    moveBuffer[base] = moved
                }
                break
            }
        }
        let opponent = 3 - side
        let childDepth = generated.forced ? depth : depth - 1
        var best = -Self.infinity
        var bestMove = -1
        for i in 0..<count {
            let m = Int(moveBuffer[base + i])
            guard isLegal(m, side) else { continue }
            make(m, side)
            let score = -negamax(childDepth, -beta, -alpha, ply: ply + 1, side: opponent)
            unmake(m)
            if aborted { return 0 }
            if score > best {
                best = score
                bestMove = m
                if score > alpha {
                    alpha = score
                    if alpha >= beta { break }
                }
            }
        }
        if bestMove < 0 { return evaluate(side, ply: ply) }
        let flag: UInt8 = best <= alphaIn ? 3 : (best >= betaIn ? 2 : 1)
        if tt[slot].key != key || Int(tt[slot].depth) <= depth {
            tt[slot] = TTEntry(key: key, score: Int32(toTT(best, ply)), depth: Int16(depth), flag: flag, move: Int16(bestMove))
        }
        return best
    }

    // MARK: 루트

    /// 루트 결정. 반환은 패딩 인덱스(nil = 둘 곳 없음).
    func chooseMove(side: Int, maxDepth: Int, rng: inout some RandomNumberGenerator) -> Int? {
        let opponent = 3 - side
        var near: [Int] = []
        forEachCandidate { p in near.append(p); return true }

        // 1) 내 5목.
        let ownFives = near.filter { category($0, side) == GomokuAICategory.five }
        if !ownFives.isEmpty { return ownFives.randomElement(using: &rng) }
        // 2) 상대 5목 자리 막기(둘 이상이면 이미 진 판 — 합법인 하나라도 막는다).
        let opponentFives = near.filter { category($0, opponent) == GomokuAICategory.five }
        if !opponentFives.isEmpty {
            let blocks = opponentFives.filter { isLegal($0, side) }
            if let block = pickBest(blocks, side: side, rng: &rng) { return block }
        }
        // 3) 내 열린 4 · 4-4(합법).
        if opponentFives.isEmpty {
            let openFours = near.filter { category($0, side) == GomokuAICategory.openFour && isLegal($0, side) }
            if !openFours.isEmpty { return openFours.randomElement(using: &rng) }
        }
        let legalNear = near.filter { isLegal($0, side) }
        guard !legalNear.isEmpty else { return anyLegalCell(side) }
        let fallback = pickBest(legalNear, side: side, rng: &rng)
        if checkAbortNow() { return fallback }

        // 4) 내 VCF.
        if opponentFives.isEmpty {
            vcfBudget = 30_000
            vcfBudgetHit = false
            if let move = vcfMove(attacker: side, depth: 16, lastDefenderMove: nil), isLegal(move, side) { return move }
            if checkAbortNow() { return fallback }
        }

        // 5) 상대 VCF 가 있으면 그것을 끊는 수로 좁힌다.
        var rootMoves: [Int] = []
        if opponentFives.isEmpty, hasVCF(attacker: opponent, depth: 16, budget: 20_000) {
            var defenses: [Int] = []
            var pool = legalNear.sorted { value($0, side) + value($0, opponent) > value($1, side) + value($1, opponent) }
            if pool.count > 40 {
                let fours = pool[40...].filter { makesFour($0, side) }
                pool = Array(pool.prefix(40)) + fours
            }
            // 예산에 걸려 "모른다"로 끝난 수는 확인된 방어가 아니다 — 확인된 방어가 하나도 없을 때만 후보로 되살린다.
            var uncertain: [Int] = []
            for m in pool {
                make(m, side)
                let stillLost = hasVCF(attacker: opponent, depth: 16, budget: 4_000)
                let unknown = vcfBudgetHit
                unmake(m)
                if checkAbortNow() { break }
                if !stillLost { if unknown { uncertain.append(m) } else { defenses.append(m) } }
            }
            if defenses.isEmpty { defenses = uncertain }
            if !defenses.isEmpty { rootMoves = defenses }
            if aborted { return defenses.first ?? fallback }
        }

        // 6) 반복 심화.
        if rootMoves.isEmpty {
            let generated = generate(side, ply: 0, depth: maxDepth, limit: 24)
            if let immediate = generated.immediate, immediate > 0 { return fallback }
            for i in 0..<generated.count {
                let m = Int(moveBuffer[i])
                if isLegal(m, side) { rootMoves.append(m) }
            }
            if rootMoves.isEmpty { rootMoves = legalNear }
        } else {
            rootMoves.sort { value($0, side) + value($0, opponent) > value($1, side) + value($1, opponent) }
        }
        if rootMoves.count == 1 { return rootMoves[0] }

        var chosen: [Int] = []
        var scores = [Int](repeating: -Self.infinity, count: rootMoves.count)
        var depth = 1
        while depth <= maxDepth {
            var best = -Self.infinity
            var bests: [Int] = []
            var iterationScores = [Int](repeating: -Self.infinity, count: rootMoves.count)
            for (i, m) in rootMoves.enumerated() {
                make(m, side)
                var score: Int
                if best == -Self.infinity {
                    score = -negamax(depth - 1, -Self.infinity, Self.infinity, ply: 1, side: opponent)
                } else {
                    score = -negamax(depth - 1, -(best + 1), -(best - 1), ply: 1, side: opponent)
                    if !aborted, score > best {
                        score = -negamax(depth - 1, -Self.infinity, -best, ply: 1, side: opponent)
                    }
                }
                unmake(m)
                if aborted { break }
                iterationScores[i] = score
                if score > best {
                    best = score
                    bests = [m]
                } else if score == best {
                    bests.append(m)
                }
            }
            if aborted { break }
            completedDepth = depth
            chosen = bests
            scores = iterationScores
            // 다음 반복은 좋은 수부터.
            let order = rootMoves.indices.sorted { scores[$0] > scores[$1] }
            rootMoves = order.map { rootMoves[$0] }
            scores = order.map { scores[$0] }
            if best > Self.win - 1000 || best < -(Self.win - 1000) { break }
            if elapsedFraction > 0.45 { break }
            depth += 1
        }
        if chosen.isEmpty { return rootMoves.first ?? fallback }
        return chosen.randomElement(using: &rng)
    }

    /// 우선순위(두 색 칸 점수 합) 최고인 칸, 동점이면 무작위.
    private func pickBest(_ moves: [Int], side: Int, rng: inout some RandomNumberGenerator) -> Int? {
        guard !moves.isEmpty else { return nil }
        let opponent = 3 - side
        let top = moves.map { value($0, side) + value($0, opponent) }.max()!
        return moves.filter { value($0, side) + value($0, opponent) == top }.randomElement(using: &rng)
    }
}
