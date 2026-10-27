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
