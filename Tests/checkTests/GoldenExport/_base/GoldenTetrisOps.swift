import CheckGoldenSupport
@testable import CheckCore

// 골든 바탕(W0-b · C§5.2 G3 · C-X2): 테트리스 판을 **조종사 없이** 입력 연산 기록만으로 다시 돌리는 도구.
// W1-a(테트리스·미니게임 골든)가 `tetris/scripted-*` 를 만들 때 이 기록기·재생기·접기를 그대로 쓴다.
//
// 연산(한 프레임 안에서 부른 순서대로, 그 뒤 step(dt) 한 번):
//   L+ L-  왼쪽 눌림/뗌      R+ R-  오른쪽 눌림/뗌      SD+ SD-  소프트드롭 눌림/뗌
//   CW CCW 회전               HOLD   홀드                ACT      action()(준비·결과면 판 시작, 진행 중이면 하드드롭)
// 눌림/뗌은 **상태가 바뀔 때만** 적는다(엔진의 setLeftHeld 등은 같은 값이면 아무것도 안 한다 — TetrisGame.swift:760-777).
// 엔진이 스스로 키를 놓는 자리(판 시작·탑아웃·interrupt)는 조종사가 손을 안 대는 단계라 기록이 엔진과 어긋나지 않는다 —
// 어긋나면 재생 해시가 달라지므로 C-X2 시험(GoldenExportReplayW0b)이 그 자리에서 빨개진다.
//
// RLE 글자: "개수:연산들" 을 쉼표로 잇는다. 같은 연산 목록이 이어지는 프레임을 하나로 접는다. 연산이 여럿이면 공백으로 잇는다.
//   예: "4:,1:R+,7:,1:R-,2:,1:CW ACT"  = 빈 프레임 4 · R+ 1 · 빈 7 · R- 1 · 빈 2 · (CW 다음 ACT) 1
// 접기(해시): V0360TetrisSoloGoldenTests.swift 의 goldFoldLight·goldFoldBoard 와 같은 칸·같은 순서(FNV-1a 64).

enum GoldenTetrisOp: String, CaseIterable, Sendable {
    case leftDown = "L+", leftUp = "L-", rightDown = "R+", rightUp = "R-"
    case softDown = "SD+", softUp = "SD-", rotateCW = "CW", rotateCCW = "CCW", hold = "HOLD", act = "ACT"

    func apply(to game: inout TetrisGame) {
        switch self {
        case .leftDown: game.setLeftHeld(true)
        case .leftUp: game.setLeftHeld(false)
        case .rightDown: game.setRightHeld(true)
        case .rightUp: game.setRightHeld(false)
        case .softDown: game.setSoftDropHeld(true)
        case .softUp: game.setSoftDropHeld(false)
        case .rotateCW: game.rotate(clockwise: true)
        case .rotateCCW: game.rotate(clockwise: false)
        case .hold: game.holdCurrentPiece()
        case .act: game.action()
        }
    }
}

enum GoldenTetrisRLE {
    static func encode(_ frames: [[GoldenTetrisOp]]) -> String {
        var entries: [String] = []
        var index = 0
        while index < frames.count {
            var end = index + 1
            while end < frames.count, frames[end] == frames[index] { end += 1 }
            entries.append("\(end - index):" + frames[index].map(\.rawValue).joined(separator: " "))
            index = end
        }
        return entries.joined(separator: ",")
    }

    static func decode(_ text: String) throws -> [[GoldenTetrisOp]] {
        guard !text.isEmpty else { return [] }
        var frames: [[GoldenTetrisOp]] = []
        for entry in text.split(separator: ",", omittingEmptySubsequences: false) {
            guard let colon = entry.firstIndex(of: ":"), let count = Int(entry[..<colon]), count > 0 else {
                throw GoldenJSONError("RLE 항목이 깨졌다: \(entry)")
            }
            let body = entry[entry.index(after: colon)...]
            let ops = try body.split(separator: " ").map { token -> GoldenTetrisOp in
                guard let op = GoldenTetrisOp(rawValue: String(token)) else { throw GoldenJSONError("모르는 연산 \(token)") }
                return op
            }
            frames.append(contentsOf: Array(repeating: ops, count: count))
        }
        return frames
    }
}

/// V0360 의 접기와 같은 칸·같은 순서. 바꾸면 V0360 해시 네 개(C-X2)가 먼저 빨개진다.
enum GoldenTetrisFold {
    static func light(_ g: TetrisGame, into h: inout GoldenFNV1a64) {
        if let a = g.active {
            h.add(a.piece.rawValue); h.add(a.rotation.rawValue); h.add(a.column); h.add(a.row)
        } else {
            h.add(-1)
        }
        h.add(g.next.count)
        for p in g.next { h.add(p.rawValue) }
        h.add(g.heldPiece?.rawValue ?? -1)
        h.add(g.holdUsed)
        h.add(g.score); h.add(g.advance); h.add(g.lines); h.add(g.combo); h.add(g.backToBack)
        switch g.phase {
        case .ready: h.add(0)
        case .running: h.add(1)
        case .lineClear(let left): h.add(2); h.add(left)
        case .are(let left): h.add(3); h.add(left)
        case .over(let hold): h.add(4); h.add(hold)
        case .result: h.add(5)
        }
        h.add(g.elapsed)
        if let c = g.lastClear {
            h.add(c.lines)
            switch c.spin {
            case .none: h.add(0)
            case .mini: h.add(1)
            case .full: h.add(2)
            }
            h.add(c.backToBack); h.add(c.perfectClear); h.add(c.points); h.add(c.at)
        } else {
            h.add(-2)
        }
        h.add(g.level); h.add(g.scoreLevel); h.add(g.isGrounded)
    }

    static func board(_ g: TetrisGame, into h: inout GoldenFNV1a64) {
        for row in g.board {
            for cell in row { h.add(cell?.rawValue ?? -1) }
        }
    }
}

/// 재생 결과. `checkpoints[k]` = (k+1)·checkpointEvery 프레임을 마친 뒤의 해시.
struct GoldenTetrisTrace {
    var hash: UInt64
    var checkpoints: [UInt64]
    var frames: Int
    var game: TetrisGame
}

enum GoldenTetrisReplay {
    /// 시작 판 → 앞 연산(첫 접기 전) → 프레임마다 [연산 → step(dt) → 접기]. 판이 결과 단계에 들면 멈춘다(조종사와 같다).
    static func run(start: TetrisGame, preOps: [GoldenTetrisOp], frames: [[GoldenTetrisOp]], dt: Double,
                    checkpointEvery: Int) -> GoldenTetrisTrace {
        var g = start
        for op in preOps { op.apply(to: &g) }
        var h = GoldenFNV1a64()
        GoldenTetrisFold.board(g, into: &h)
        var checkpoints: [UInt64] = []
        var frame = 0
        for ops in frames {
            frame += 1
            let advanceBefore = g.advance
            for op in ops { op.apply(to: &g) }
            g.step(dt: dt)
            GoldenTetrisFold.light(g, into: &h)
            if g.advance != advanceBefore { GoldenTetrisFold.board(g, into: &h) }
            if frame % checkpointEvery == 0 { checkpoints.append(h.value) }
            if case .result = g.phase { break }
        }
        return GoldenTetrisTrace(hash: h.value, checkpoints: checkpoints, frames: frame, game: g)
    }
}

/// 연산을 적으며 판을 움직인다. 눌림/뗌은 그림자 상태와 다를 때만 적는다.
struct GoldenTetrisRecorder {
    private(set) var game: TetrisGame
    private(set) var frames: [[GoldenTetrisOp]] = []
    private var pending: [GoldenTetrisOp] = []
    private var left = false, right = false, soft = false

    init(_ game: TetrisGame) { self.game = game }

    private mutating func record(_ op: GoldenTetrisOp) {
        pending.append(op)
        op.apply(to: &game)
    }

    mutating func setLeftHeld(_ held: Bool) {
        if held != left { left = held; record(held ? .leftDown : .leftUp) } else { game.setLeftHeld(held) }
    }
    mutating func setRightHeld(_ held: Bool) {
        if held != right { right = held; record(held ? .rightDown : .rightUp) } else { game.setRightHeld(held) }
    }
    mutating func setSoftDropHeld(_ held: Bool) {
        if held != soft { soft = held; record(held ? .softDown : .softUp) } else { game.setSoftDropHeld(held) }
    }
    mutating func rotate(clockwise: Bool) { record(clockwise ? .rotateCW : .rotateCCW) }
    mutating func holdCurrentPiece() { record(.hold) }
    mutating func action() { record(.act) }

    /// 한 프레임을 닫는다: 모인 연산을 기록하고 step(dt).
    mutating func step(dt: Double) {
        frames.append(pending)
        pending = []
        game.step(dt: dt)
    }

    /// 첫 접기 전에 부른 연산(판 시작 ACT 등)을 꺼낸다.
    mutating func takePreOps() -> [GoldenTetrisOp] {
        defer { pending = [] }
        return pending
    }
}

/// V0360 대본 조종사(자리 고르기 · DAS 누름 · 회전 · 홀드 · 소프트드롭 · 중력 굳힘 · 하드드롭)를 **같은 순서로** 옮기되,
/// 판을 직접 만지지 않고 `GoldenTetrisRecorder` 를 거친다. 조종사 자체는 Kotlin 으로 옮기지 않는다(C§5.2 G3).
enum GoldenTetrisPilot {
    struct Result {
        var trace: GoldenTetrisTrace
        var preOps: [GoldenTetrisOp]
        var frames: [[GoldenTetrisOp]]
        var start: TetrisGame
    }

    static func fromNewGame(seed: UInt64, dt: Double, maxFrames: Int, actEvery: Int, checkpointEvery: Int) -> Result {
        var recorder = GoldenTetrisRecorder(TetrisGame(seed: seed))
        let start = recorder.game
        recorder.action()
        let pre = recorder.takePreOps()
        return play(recorder, start: start, preOps: pre, dt: dt, maxFrames: maxFrames, actEvery: actEvery, checkpointEvery: checkpointEvery)
    }

    static func fromAdvance(_ advance: Int, seed: UInt64, dt: Double, maxFrames: Int, actEvery: Int, checkpointEvery: Int) -> Result {
        let start = TetrisGame(seed: seed, board: TetrisGame.emptyBoard(), active: nil,
                               phase: .are(remaining: TetrisGame.areSeconds), advance: advance)
        return play(GoldenTetrisRecorder(start), start: start, preOps: [], dt: dt, maxFrames: maxFrames,
                    actEvery: actEvery, checkpointEvery: checkpointEvery)
    }

    private static func boardCost(_ board: [[TetrisGame.Piece?]]) -> Double {
        var heights = [Int](repeating: 0, count: TetrisGame.columns)
        var holes = 0
        for column in 0..<TetrisGame.columns {
            var covered = false
            for row in 0..<TetrisGame.totalRows {
                if board[row][column] != nil {
                    if !covered { covered = true; heights[column] = TetrisGame.totalRows - row }
                } else if covered {
                    holes += 1
                }
            }
        }
        let bumpiness = zip(heights, heights.dropFirst()).reduce(0) { $0 + abs($1.0 - $1.1) }
        return Double(heights.reduce(0, +)) * 0.51 + Double(holes) * 3.6
            + Double(bumpiness) * 0.18 + Double(heights.max() ?? 0) * 0.5
    }

    private static func bestPlacement(_ game: TetrisGame) -> (turns: Int, column: Int)? {
        guard game.active != nil else { return nil }
        var best: (turns: Int, column: Int)?
        var bestCost = Double.infinity
        for turns in 0..<4 {
            for column in 0..<TetrisGame.columns {
                var probe = game
                for _ in 0..<turns { probe.rotate(clockwise: true) }
                guard let piece = probe.active else { continue }
                let leftmost = piece.cells.map { $0.column }.min() ?? 0
                for _ in 0..<abs(column - leftmost) {
                    if column < leftmost {
                        probe.setLeftHeld(true); probe.setLeftHeld(false)
                    } else {
                        probe.setRightHeld(true); probe.setRightHeld(false)
                    }
                }
                guard probe.active?.cells.map({ $0.column }).min() == column else { continue }
                let before = probe.lines
                probe.action()
                let cost = boardCost(probe.board) - 12 * Double(probe.lines - before)
                if cost < bestCost { bestCost = cost; best = (turns, column) }
            }
        }
        return best
    }

    private static func play(_ initial: GoldenTetrisRecorder, start: TetrisGame, preOps: [GoldenTetrisOp], dt: Double,
                             maxFrames: Int, actEvery: Int, checkpointEvery: Int) -> Result {
        var r = initial
        var h = GoldenFNV1a64()
        var checkpoints: [UInt64] = []
        var pieces = 0
        var plan: (turns: Int, column: Int)?
        var planAdvance = -1
        var planHeld = false
        var mode = 0
        var frame = 0
        GoldenTetrisFold.board(r.game, into: &h)
        while frame < maxFrames {
            frame += 1
            let advanceBefore = r.game.advance
            if case .running = r.game.phase, let active = r.game.active {
                if r.game.advance != planAdvance || r.game.holdUsed != planHeld {
                    if r.game.advance != planAdvance {
                        pieces += 1
                        mode = pieces % 4
                        r.setSoftDropHeld(false)
                    }
                    planAdvance = r.game.advance
                    planHeld = r.game.holdUsed
                    plan = bestPlacement(r.game)
                }
                let leftmost = active.cells.map { $0.column }.min() ?? 0
                let actNow = frame % actEvery == 0
                if mode == 3, !r.game.holdUsed, actNow {
                    r.holdCurrentPiece()
                } else if let p = plan, p.turns > 0, actNow {
                    let before = active.rotation
                    if p.turns == 3 {
                        r.rotate(clockwise: false)
                        plan = (0, p.column)
                    } else {
                        r.rotate(clockwise: true)
                        plan = (p.turns - 1, p.column)
                    }
                    if r.game.active?.rotation == before { plan = (0, p.column) }
                } else if let p = plan, p.turns == 0, leftmost != p.column {
                    if leftmost > p.column {
                        if actNow { r.setRightHeld(false); r.setLeftHeld(true) }
                    } else {
                        if actNow { r.setLeftHeld(false); r.setRightHeld(true) }
                    }
                } else {
                    r.setLeftHeld(false)
                    r.setRightHeld(false)
                    if actNow {
                        switch mode {
                        case 1: r.setSoftDropHeld(true)
                        case 2: break
                        default: r.action()
                        }
                    }
                }
                if let now = r.game.active, let p = plan, p.turns == 0,
                   (now.cells.map { $0.column }.min() ?? 0) == p.column {
                    r.setLeftHeld(false)
                    r.setRightHeld(false)
                }
            }
            r.step(dt: dt)
            GoldenTetrisFold.light(r.game, into: &h)
            if r.game.advance != advanceBefore { GoldenTetrisFold.board(r.game, into: &h) }
            if frame % checkpointEvery == 0 { checkpoints.append(h.value) }
            if case .result = r.game.phase { break }
        }
        return Result(trace: GoldenTetrisTrace(hash: h.value, checkpoints: checkpoints, frames: frame, game: r.game),
                      preOps: preOps, frames: r.frames, start: start)
    }
}
