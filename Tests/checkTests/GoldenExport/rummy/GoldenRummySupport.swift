// 원본: 없음 — 아잉 큐브 골든 내보내기(rummy/*)가 같이 쓰는 글자 표기·난수(형식 정본: contract/README.md §2).
import CheckGoldenSupport
import Foundation
@testable import CheckCore

// 골든 칸은 들여쓰기 2칸 정규 JSON 이라 배열이 줄마다 벌어진다 — 예산(계약 골든 합계 12 MiB)을 아끼려고 값을 **한 줄 글자**로 싣는다.
// Kotlin 짝: core/rules commonTest …/rummy/RummyGoldenSupport.kt (같은 표기를 같은 함수 이름으로 만든다).
//
//   면 목록 "A1 A2 J"(빈 목록 "") · 묶음 목록 "A1 A2|B1" · 점 "x,y" · 점 목록 "x,y - x,y" · 사각형 "x,y,w,h"(목록은 공백 구분) · 정수 목록 "1,2"
//   받침대 자리 "row,halfCol" · 받침대 한 칸 "id@row,halfCol"
//   놓는 곳 "rack" · "rack:i" · "meld:s" · "meld:s:i" · "new" · "at:x,y" · "slot:r,c"
//   계획 "rack" · "attach:s:left|right" · "insert:s:i" · "new:x,y"
//   미리보기 "nil" 또는 "<계획> landing=-" · "<계획> landing=set|면 목록|사각형|blockStart|valid(0/1)"

/// SplitMix64 + 나머지 잘라 쓰기. Swift `Int.random(using:)`·`shuffled` 는 표준 라이브러리 구현에 기대므로 생성기엔 쓰지 않는다(판이 바뀌면 골든이 흔들린다).
struct GoldenRummyRNG {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< n.
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }

    /// lo ... hi.
    mutating func range(_ lo: Int, _ hi: Int) -> Int { lo + below(hi - lo + 1) }

    mutating func flip() -> Bool { below(2) == 0 }

    mutating func pick<T>(_ items: [T]) -> T { items[below(items.count)] }

    mutating func shuffled<T>(_ items: [T]) -> [T] {
        var out = items
        guard out.count > 1 else { return out }
        for i in stride(from: out.count - 1, to: 0, by: -1) { out.swapAt(i, below(i + 1)) }
        return out
    }

    /// 면 하나(조커 1/16).
    mutating func face() -> RummyFace {
        below(16) == 0 ? .joker : RummyFace(color: below(4), number: range(1, 13))
    }

    /// 맞는 묶음 후보(런 · 그룹, 1/5 조커 한 장).
    mutating func meld() -> [RummyFace] {
        var faces: [RummyFace]
        if flip() {
            let n = range(3, 7)
            let start = range(1, 14 - n)
            let color = below(4)
            faces = (start..<(start + n)).map { RummyFace(color: color, number: $0) }
        } else {
            let n = range(3, 4)
            let number = range(1, 13)
            faces = shuffled([0, 1, 2, 3]).prefix(n).map { RummyFace(color: $0, number: number) }
        }
        if below(5) == 0 { faces[below(faces.count)] = .joker }
        return faces
    }
}

enum GoldenRummyText {
    static func faces(_ text: String) -> [RummyFace] {
        text.split(separator: " ").map { RummyFace(text: String($0))! }
    }

    static func text(_ faces: [RummyFace]) -> String { faces.map(\.text).joined(separator: " ") }

    static func point(_ p: RummyPoint) -> String { "\(p.x),\(p.y)" }

    static func rect(_ r: RummyRect) -> String { "\(r.x),\(r.y),\(r.width),\(r.height)" }

    static func slot(_ s: RummyRackSlot) -> String { "\(s.row),\(s.halfCol)" }

    static func target(_ t: RummyDropTarget) -> String {
        switch t {
        case .rack(let index?): return "rack:\(index)"
        case .rack(nil): return "rack"
        case .meld(let set, let index?): return "meld:\(set):\(index)"
        case .meld(let set, nil): return "meld:\(set)"
        case .newMeld: return "new"
        case .newMeldAt(let p): return "at:\(point(p))"
        case .rackSlot(let s): return "slot:\(slot(s))"
        }
    }

    static func plan(_ p: RummyDropPlan) -> String {
        switch p {
        case .rack: return "rack"
        case .attach(let set, let side): return "attach:\(set):\(side.rawValue)"
        case .insert(let set, let index): return "insert:\(set):\(index)"
        case .newSet(let p): return "new:\(point(p))"
        }
    }

    static func preview(_ p: RummyDropPreview?) -> String {
        guard let p else { return "nil" }
        guard let l = p.landing else { return "\(plan(p.plan)) landing=-" }
        return "\(plan(p.plan)) landing=\(l.set)|\(text(l.faces))|\(rect(l.frame))|\(l.blockStart)|\(l.valid ? 1 : 0)"
    }

    /// 받침대 자리 글자: id 오름차순 "id@r,c".
    static func layout(_ l: RummyRackLayout) -> String {
        l.slots.keys.sorted().map { "\($0)@\(slot(l.slots[$0]!))" }.joined(separator: " ")
    }

    /// 정수 목록 "1,2,3"(빈 목록 "").
    static func ids(_ ids: [Int]) -> String { ids.map(String.init).joined(separator: ",") }

    /// 묶음 목록 "A1 A2|B1"(빈 목록 "").
    static func sets(_ sets: [[RummyFace]]) -> String { sets.map(text).joined(separator: "|") }

    /// 사각형 목록 공백 구분(빈 목록 "").
    static func rects(_ rects: [RummyRect]) -> String { rects.map(rect).joined(separator: " ") }

    /// 점 목록 공백 구분(빈 칸 "-", 빈 목록 "").
    static func points(_ points: [RummyPoint?]) -> String { points.map { $0.map(point) ?? "-" }.joined(separator: " ") }

    /// 편집기가 와이어·화면으로 내놓는 값(판 · 점 · 랙 · 자리 · 판정).
    static func core(_ e: RummyTurnEditor) -> String {
        let melds = e.melds.indices.map { set in
            e.melds[set].map { "\($0.id):\($0.face.text)" }.joined(separator: " ") + "@\(point(e.points[set]))"
        }.joined(separator: " | ")
        let rack = e.rack.map { "\($0.id):\($0.face.text)@\(slot(e.rackLayout.slot(of: $0.id)!))" }.joined(separator: " ")
        return "T \(melds) R \(rack) reason=\(e.reason.rawValue) submit=\(e.canSubmit ? 1 : 0) changed=\(e.isChanged ? 1 : 0)"
            + " layout=\(e.isLayoutChanged ? 1 : 0) init=\(e.initialPoints) played=\(e.playedCount) rows=\(e.rackLayout.rowCount)"
    }

    /// 편집기의 나머지 읽기(랙 묶음 · 첫 등록 합 · 되돌린 자리 · 덩어리 · 집기). 길어서 언제나 지문으로만 싣는다.
    static func extra(_ e: RummyTurnEditor) -> String {
        var out: [String] = []
        out.append("melds=" + e.rackMelds.map { "\(ids($0.tileIDs)):\($0.kind.rawValue):\($0.points)" }.joined(separator: ";"))
        out.append("rackPts=\(e.rackMeldPoints)")
        if let plan = e.initialPlanPoints { out.append("plan=\(plan.table),\(plan.rack)") } else { out.append("plan=-") }
        out.append("restored=" + e.restoredRackEntries.map { "\($0.face.text)@\(slot($0.slot))" }.joined(separator: " "))
        out.append("chunks=" + e.rackLayout.chunks.map(ids).joined(separator: ";"))
        out.append("chains=" + e.rack.map { "\($0.id)>\(ids(e.rackChain(around: $0.id)))" }.joined(separator: ";"))
        out.append("picks=" + e.melds.flatMap { $0 }.map {
            "\($0.id)>\(ids(e.meldChunk(for: $0.id)))/\(ids(e.meldPick(for: $0.id)))/\(ids(e.meldPick(for: $0.id, fromTileToEnd: true)))"
        }.joined(separator: ";"))
        out.append("analysis=" + e.melds.indices.map { i -> String in
            let a = e.analysis(ofMeld: i)
            return "\(a.valid ? 1 : 0):\(a.kind?.rawValue ?? "-"):\(a.points.map(String.init) ?? "-")"
        }.joined(separator: ";"))
        return out.joined(separator: " ")
    }

    /// FNV-1a 64(UTF-8 바이트를 하나씩 — chess/fen 의 ascii 칸과 같은 접기).
    static func fnv(_ text: String) -> String {
        var hasher = GoldenFNV1a64()
        for byte in text.utf8 { hasher.add(UInt64(byte)) }
        return hasher.hex
    }
}
