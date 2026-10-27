// 원본: 없음 — W1-a 골든 내보내기(테트리스·미니게임·길건너)가 같이 쓰는 대본 재생 도구(C§5.2 G3 · contract/README.md §2-4 확장).
import CheckGoldenSupport
import Foundation
@testable import CheckCore

// 대본 골든의 공통 모양(테트리스 A~D 는 _base 의 GoldenTetrisOps 그대로, 나머지는 이 파일의 글자 연산):
//   · ops — "개수:연산들" 을 쉼표로 잇는 RLE(연산 사이는 공백). 한 프레임 = 연산을 적힌 순서대로 → step(dt) 한 번.
//   · checkpoints — 누적 FNV-1a 64 를 checkpointEvery 프레임마다.
//   · frameBytes — 프레임마다 **그 프레임 몫만** 새로 접은 FNV 의 아래 1바이트(16진 2자). 첫 불일치 **프레임 번호**를 짚는 데 쓴다
//     (G §2-3 W1-a ② — ARR 상수를 바꾸면 빨갛고 처음 갈린 프레임을 보고한다). 1/256 확률로 같은 바이트가 나와도 다음 프레임이 잡는다.

/// 글자 연산 RLE. 연산 글자에 `,` `:` 공백이 없어야 한다.
enum GoldenOpsRLE {
    static func encode(_ frames: [[String]]) -> String {
        var entries: [String] = []
        var index = 0
        while index < frames.count {
            var end = index + 1
            while end < frames.count, frames[end] == frames[index] { end += 1 }
            entries.append("\(end - index):" + frames[index].joined(separator: " "))
            index = end
        }
        return entries.joined(separator: ",")
    }

    static func decode(_ text: String) -> [[String]] {
        guard !text.isEmpty else { return [] }
        var frames: [[String]] = []
        for entry in text.split(separator: ",", omittingEmptySubsequences: false) {
            let colon = entry.firstIndex(of: ":")!
            let count = Int(entry[..<colon])!
            let ops = entry[entry.index(after: colon)...].split(separator: " ").map(String.init)
            frames.append(contentsOf: Array(repeating: ops, count: count))
        }
        return frames
    }
}

/// 프레임마다 한 바이트(그 프레임 몫만 접은 FNV 의 아래 8비트) — 첫 불일치 프레임을 짚는다.
struct GoldenFrameBytes {
    private(set) var text = ""
    mutating func append(_ frameHash: UInt64) {
        let byte = UInt8(truncatingIfNeeded: frameHash)
        text += String(format: "%02x", byte)
    }
}

/// 누적 해시와 프레임 해시에 같은 값을 함께 접는다.
struct GoldenDualFold {
    var total = GoldenFNV1a64()
    var frame = GoldenFNV1a64()

    mutating func beginFrame() { frame = GoldenFNV1a64() }
    mutating func add(_ x: UInt64) { total.add(x); frame.add(x) }
    mutating func add(_ x: Int) { total.add(x); frame.add(x) }
    mutating func add(_ x: Double) { total.add(x); frame.add(x) }
    mutating func add(_ x: Bool) { total.add(x); frame.add(x) }
    /// nil 이면 0 하나, 있으면 1 과 값.
    mutating func add(_ x: Double?) {
        if let x { add(true); add(x) } else { add(false) }
    }
    mutating func add(_ x: Int?) {
        if let x { add(true); add(x) } else { add(false) }
    }
}

/// 테트리스 판 전체(40행 × 10칸)를 글자로 — `.` 빈 칸, 조각은 `ijlostz`.
enum GoldenTetrisText {
    static let letters: [Character] = ["i", "j", "l", "o", "s", "t", "z"]

    static func board(_ g: TetrisGame) -> String {
        g.board.map { row in String(row.map { $0.map { letters[$0.rawValue] } ?? "." }) }.joined(separator: "/")
    }

    static func pieces(_ pieces: [TetrisGame.Piece]) -> String {
        String(pieces.map { letters[$0.rawValue] })
    }

    static func phase(_ p: TetrisGame.Phase) -> GoldenJSON {
        switch p {
        case .ready: return ["kind": "ready"]
        case .running: return ["kind": "running"]
        case .lineClear(let left): return ["kind": "lineClear", "remainingBits": .bits(left)]
        case .are(let left): return ["kind": "are", "remainingBits": .bits(left)]
        case .over(let hold): return ["kind": "over", "holdBits": .bits(hold)]
        case .result: return ["kind": "result"]
        }
    }

    /// 끝 상태(사람이 읽을 몫 + Kotlin 이 칸마다 대조할 몫).
    static func final(_ g: TetrisGame, hash: UInt64, frames: Int) -> GoldenJSON {
        [
            "hash": .hex64(hash),
            "frames": .int(frames),
            "score": .int(g.score),
            "advance": .int(g.advance),
            "lines": .int(g.lines),
            "combo": .int(g.combo),
            "backToBack": .int(g.backToBack),
            "level": .int(g.level),
            "next": .string(pieces(g.next)),
            "held": .string(g.heldPiece.map { String(letters[$0.rawValue]) } ?? "-"),
            "phase": phase(g.phase),
            "elapsedBits": .bits(g.elapsed),
            "attackSentTotal": .int(g.attackSentTotal),
            "pendingGarbage": .array(g.pendingGarbage.map { GoldenJSON.int($0) }),
            "levelFloor": .int(g.levelFloor),
            "garbageMask": .array(g.garbageMask.map { GoldenJSON.int(Int($0)) }),
            "board": .string(board(g)),
        ]
    }
}

/// _base `GoldenTetrisFold.light` 와 같은 값 열(두 해시 · 프레임 해시에 함께 싣기 위해 값으로 꺼낸다). 열이 _base 접기와 같은지
/// 스스로 확인한다 — 갈리면 precondition 이 멈춘다.
enum GoldenTetrisLight {
    static func values(_ g: TetrisGame) -> [UInt64] {
        var out: [UInt64] = []
        func a(_ x: Int) { out.append(UInt64(bitPattern: Int64(x))) }
        func d(_ x: Double) { out.append(x.bitPattern) }
        func b(_ x: Bool) { out.append(x ? 1 : 0) }
        if let p = g.active { a(p.piece.rawValue); a(p.rotation.rawValue); a(p.column); a(p.row) } else { a(-1) }
        a(g.next.count)
        for p in g.next { a(p.rawValue) }
        a(g.heldPiece?.rawValue ?? -1)
        b(g.holdUsed)
        a(g.score); a(g.advance); a(g.lines); a(g.combo); a(g.backToBack)
        switch g.phase {
        case .ready: a(0)
        case .running: a(1)
        case .lineClear(let left): a(2); d(left)
        case .are(let left): a(3); d(left)
        case .over(let hold): a(4); d(hold)
        case .result: a(5)
        }
        d(g.elapsed)
        if let c = g.lastClear {
            a(c.lines)
            switch c.spin { case .none: a(0); case .mini: a(1); case .full: a(2) }
            b(c.backToBack); b(c.perfectClear); a(c.points); d(c.at)
        } else {
            a(-2)
        }
        a(g.level); a(g.scoreLevel); b(g.isGrounded)
        var mine = GoldenFNV1a64()
        for v in out { mine.add(v) }
        var check = GoldenFNV1a64()
        GoldenTetrisFold.light(g, into: &check)
        precondition(mine.value == check.value, "GoldenTetrisLight 값 열이 _base GoldenTetrisFold.light 와 갈렸다")
        return out
    }
}

/// 규칙 해시 밖에서 화면·조준이 읽는 파생 값(G §2-3 W1-a 검증 지적 — 옮긴 공개 파생값도 골든에 싣는다):
/// ghost(piece · rotation · column · row, 없으면 −1) · isPlaying · isGameOver · difficultyLevel · pendingGarbageLines.
enum GoldenTetrisDerived {
    static func values(_ g: TetrisGame) -> [Int] {
        var out: [Int] = []
        if let ghost = g.ghost { out += [ghost.piece.rawValue, ghost.rotation.rawValue, ghost.column, ghost.row] } else { out.append(-1) }
        out.append(g.isPlaying ? 1 : 0)
        out.append(g.isGameOver ? 1 : 0)
        out.append(g.difficultyLevel)
        out.append(g.pendingGarbageLines)
        return out
    }

    /// 굳힘 사건 글자: "줄:스핀(none·mini·full):B2B 0/1:퍼펙트 0/1:점수:공격".
    static func event(_ c: TetrisGame.ClearEvent?) -> String {
        guard let c else { return "-" }
        let spin: String
        switch c.spin {
        case .none: spin = "none"
        case .mini: spin = "mini"
        case .full: spin = "full"
        }
        return "\(c.lines):\(spin):\(c.backToBack ? 1 : 0):\(c.perfectClear ? 1 : 0):\(c.points):\(c.attack)"
    }
}

extension GoldenJSON {
    static func intArray(_ values: [Int]) -> GoldenJSON { .array(values.map { .int($0) }) }
    static func bitsArray(_ values: [Double]) -> GoldenJSON { .array(values.map { .bits($0) }) }
    static func boolArray(_ values: [Bool]) -> GoldenJSON { .array(values.map { .bool($0) }) }
}

/// 긴 표는 공백으로 이은 한 글자로 싣는다(정수는 10진, 실수는 비트 16진, 불은 0/1) — 파일이 한 값 한 줄로 부풀지 않게.
enum GoldenCompact {
    static func ints(_ values: [Int]) -> GoldenJSON { .string(values.map(String.init).joined(separator: " ")) }
    static func bits(_ values: [Double]) -> GoldenJSON { .string(values.map(GoldenBits.bits).joined(separator: " ")) }
    static func bools(_ values: [Bool]) -> GoldenJSON { .string(values.map { $0 ? "1" : "0" }.joined()) }
}
