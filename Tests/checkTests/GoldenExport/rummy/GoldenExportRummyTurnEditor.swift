// 원본: Sources/CheckCore/RummyTurnEditor.swift · Tests/checkTests/V0369RummyV3FuzzTests.swift(무작위 동작 생성) @ 1a5eeca6 (골든 생성기 — 아잉 큐브 차례 편집기)
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// 아잉 큐브 편집기 골든(rummy/turn-editor): 동작 열 → 판·랙·배치 스냅숏.
//  · 이름 있는 대본(V0369RummyRulesTests · V0369RummyV3EditTests · V0369RummyV3FuzzTests · V0370RummyRackTests 의 장면) — 단계마다 글자 스냅숏 전부.
//  · 무작위 대본(붐비는 판 · 손으로 흩은 배치 · 첫 등록 전 포함) — 단계마다 지문(한 줄 "동작 ~ 받음 ~ 미리보기 지문 ~ 핵심 지문 ~ 나머지 지문").
// 대본 글자: "block <ids> <놓는 곳>" · "set <번호> <x,y>" · "reset" · "sort number|color" · "afterdrop <ids> <r,c>"(바꾸지 않는다) · "stands <판>;<랙>"(바꾸지 않는다).

private enum TurnStart {
    static func json(table: [[RummyFace]], rack: [RummyFace], initialDone: Bool, layout: RummyLayout?, order: [RummyFace]?, entries: [RummyRackEntry]?) -> [String: GoldenJSON] {
        [
            "table": .string(GoldenRummyText.sets(table)),
            "rack": .string(GoldenRummyText.text(rack)),
            "initialDone": .bool(initialDone),
            "layout": layout.map { .string(GoldenRummyText.points($0.points)) } ?? .null,
            "rackOrder": order.map { .string(GoldenRummyText.text($0)) } ?? .null,
            "rackEntries": entries.map { .string($0.map { "\($0.face.text)@\(GoldenRummyText.slot($0.slot))" }.joined(separator: " ")) } ?? .null,
        ]
    }
}

/// 이름 있는 대본 하나.
private struct TurnScript {
    let id: String
    var editor: RummyTurnEditor
    let start: [String: GoldenJSON]
    var steps: [GoldenJSON] = []

    init(_ id: String, table: [String] = [], at points: [(Int, Int)]? = nil, rack: String = "", initialDone: Bool = true, order: String? = nil, entries: [RummyRackEntry]? = nil) {
        self.id = id
        let sets = table.map(GoldenRummyText.faces)
        let faces = GoldenRummyText.faces(rack)
        let layout = points.map { RummyLayout($0.map { RummyPoint(x: $0.0, y: $0.1) }) }
        let rackOrder = order.map(GoldenRummyText.faces)
        editor = RummyTurnEditor(table: sets, rack: faces, initialDone: initialDone, rackOrder: rackOrder, tableLayout: layout, rackEntries: entries)
        start = TurnStart.json(table: sets, rack: faces, initialDone: initialDone, layout: layout, order: rackOrder, entries: entries)
        record("start", ok: true, preview: "-")
    }

    private mutating func record(_ op: String, ok: Bool, preview: String) {
        steps.append(["op": .string(op), "ok": .bool(ok), "preview": .string(preview), "after": .string(GoldenRummyText.core(editor)), "extra": .string(GoldenRummyText.fnv(GoldenRummyText.extra(editor)))])
    }

    /// 면 글자 → 랙 먼저, 없으면 판(같은 면이 둘이면 앞의 것). "t:A4" 는 판에서만.
    func id(_ text: String) -> Int {
        if text.hasPrefix("t:") { return editor.melds.flatMap { $0 }.first { $0.face.text == String(text.dropFirst(2)) }!.id }
        return (editor.rack + editor.melds.flatMap { $0 }).first { $0.face.text == text }!.id
    }

    mutating func block(_ faces: String, _ target: RummyDropTarget) {
        let ids = faces.split(separator: " ").map { id(String($0)) }
        blockIDs(ids, target)
    }

    mutating func blockIDs(_ ids: [Int], _ target: RummyDropTarget) {
        let preview = GoldenRummyText.preview(editor.previewDrop(ids, to: target))
        let ok = editor.moveBlock(ids, to: target)
        record("block \(GoldenRummyText.ids(ids)) \(GoldenRummyText.target(target))", ok: ok, preview: preview)
    }

    mutating func set(_ index: Int, _ x: Int, _ y: Int) {
        let point = RummyPoint(x: x, y: y)
        let preview = GoldenRummyText.preview(editor.previewMoveSet(index, to: point))
        let ok = editor.moveSet(index, to: point)
        record("set \(index) \(GoldenRummyText.point(point))", ok: ok, preview: preview)
    }

    mutating func reset() {
        editor.reset()
        record("reset", ok: true, preview: "-")
    }

    mutating func sort(_ mode: RummyRackSort) {
        editor.sortRack(mode)
        record("sort \(mode == .number ? "number" : "color")", ok: true, preview: "-")
    }

    mutating func afterDrop(_ faces: String, row: Int, col: Int) {
        let ids = faces.split(separator: " ").map { id(String($0)) }
        let slot = RummyRackSlot(row: row, halfCol: col)
        let layout = editor.rackLayoutAfterDrop(ids, at: slot)
        record("afterdrop \(GoldenRummyText.ids(ids)) \(GoldenRummyText.slot(slot))", ok: layout != nil, preview: layout.map(GoldenRummyText.layout) ?? "nil")
    }

    mutating func stands(_ table: String, _ rack: String) {
        let sets = table.isEmpty ? [] : table.split(separator: "|").map { GoldenRummyText.faces(String($0)) }
        record("stands \(table);\(rack)", ok: editor.standsOn(table: sets, rack: GoldenRummyText.faces(rack)), preview: "-")
    }

    var json: GoldenJSON {
        var out = start
        out["id"] = .string(id)
        out["steps"] = .array(steps)
        return .object(out)
    }
}

@Suite("GoldenExport rummy — 차례 편집기(rummy/turn-editor)")
struct GoldenExportRummyTurnEditor {
    private func named() -> [TurnScript] {
        var all: [TurnScript] = []
        func add(_ script: TurnScript) { all.append(script) }

        // MARK: V0369RummyRulesTests
        var s = TurnScript("rules-init", table: ["A5 A7 J"], rack: "B1 B2")
        add(s)
        s = TurnScript("rules-r14", table: ["A1 A2 A3"], rack: "B10 C10 D10 A4 J")
        s.block("t:A1", .rack(index: nil))
        s.block("t:A1", .rack(index: 0))
        s.block("t:A1", .newMeld)
        s.block("A4", .meld(0, index: nil))
        s.block("A4", .rack(index: 0))
        s.blockIDs([999], .newMeld)
        s.block("A4", .meld(7, index: nil))
        add(s)
        s = TurnScript("rules-empty", table: ["A1 A2 A3"], rack: "B10 C10 D10 A4 J")
        s.block("B10", .newMeld)
        s.block("B10", .rack(index: nil))
        s.block("B10", .newMeld)
        s.block("t:A1", .meld(1, index: nil))
        s.block("t:A2", .meld(1, index: nil))
        s.block("t:A3", .meld(1, index: nil))
        add(s)
        s = TurnScript("rules-slots", table: ["A1 B5 C9 D13"])
        s.block("t:A1", .meld(0, index: 1))
        s.block("t:A1", .meld(0, index: 3))
        s.block("t:A1", .meld(0, index: nil))
        s.block("t:A1", .meld(0, index: 0))
        add(s)
        s = TurnScript("rules-rack-reorder", table: ["A1 A2 A3"], rack: "B10 C10 D10 A4 J")
        s.block("J", .rack(index: 0))
        s.block("B10", .rack(index: 4))
        add(s)
        s = TurnScript("rules-reset", table: ["A1 A2 A3"], rack: "B10 C10 D10 A4 J")
        s.sort(.color)
        s.block("C10", .newMeld)
        s.block("J", .meld(0, index: nil))
        s.block("t:A1", .meld(1, index: 0))
        s.reset()
        add(s)
        s = TurnScript("rules-sort", rack: "C9 J A7 B8 A9 B7 A7", initialDone: false)
        s.sort(.number)
        s.sort(.color)
        s.sort(.number)
        s.sort(.color)
        add(s)
        add(TurnScript("rules-order", rack: "A1 B2 C3 A1 D4", order: "C3 A1 B5 B2 A1"))
        add(TurnScript("rules-order-partial", rack: "A1 B2 C3 D4", order: "D4"))
        s = TurnScript("rules-kbag", table: ["A1 A2 A3 A4 A5 A6"], rack: "B9")
        s.block("t:A4", .newMeld)
        s.block("t:A5", .meld(1, index: nil))
        s.block("t:A6", .meld(1, index: nil))
        s.block("t:A6", .meld(0, index: 0))
        s.block("t:A5", .meld(0, index: 0))
        s.block("t:A4", .meld(0, index: 0))
        s.block("B9", .newMeld)
        s.block("B9", .rack(index: nil))
        add(s)
        s = TurnScript("rules-initial", table: ["A1 A2 A3"], rack: "B10 C10 D10 A4 J", initialDone: false)
        s.block("B10", .newMeld)
        s.block("C10", .meld(1, index: nil))
        s.block("D10", .meld(1, index: nil))
        s.block("A4", .meld(0, index: nil))
        add(s)
        s = TurnScript("rules-under30", rack: "A5 B5 C5", initialDone: false)
        s.block("A5", .newMeld)
        s.block("B5", .meld(0, index: nil))
        s.block("C5", .meld(0, index: nil))
        add(s)

        // MARK: V0369RummyV3EditTests
        s = TurnScript("v3-split-middle", table: ["A1 A2 A3 A4 A5 A6 A7"], at: [(100, 200)])
        s.block("t:A4", .newMeldAt(RummyPoint(x: 600, y: 500)))
        s.block("t:A4", .rack(index: nil))
        s.block("t:A2", .rackSlot(RummyRackSlot(row: 0, halfCol: 0)))
        add(s)
        s = TurnScript("v3-split-ends", table: ["A1 A2 A3 A4 A5 A6 A7"], at: [(100, 200)])
        s.block("t:A7", .newMeldAt(RummyPoint(x: 600, y: 500)))
        s.block("t:A1", .newMeldAt(RummyPoint(x: 600, y: 400)))
        add(s)
        s = TurnScript("v3-split-group", table: ["A5 B5 C5 D5"], at: [(100, 100)])
        s.block("t:B5", .newMeldAt(RummyPoint(x: 600, y: 500)))
        add(s)
        s = TurnScript("v3-split-joker", table: ["A3 J A5 A6 A7 A8 A9"], at: [(40, 300)])
        s.block("t:A6", .newMeldAt(RummyPoint(x: 600, y: 500)))
        add(s)
        s = TurnScript("v3-split-multi", table: ["B1 B2 B3 B4 B5 B6 B7 B8"], at: [(0, 0)])
        s.block("t:B3 t:B6", .newMeldAt(RummyPoint(x: 500, y: 500)))
        add(s)
        s = TurnScript("v3-split-reset", table: ["A1 A2 A3", "A5 A6 A7"], at: [(100, 200), (300, 200)], rack: "A4 B9")
        s.block("A4", .meld(0, index: nil))
        s.set(1, 260, 200)
        s.block("A4", .rack(index: nil))
        s.reset()
        add(s)
        for (name, target) in [("right", RummyPoint(x: 344, y: 228)), ("far", RummyPoint(x: 345, y: 200)), ("far2", RummyPoint(x: 320, y: 229))] {
            s = TurnScript("v3-attach-\(name)", table: ["A2 A3 A4"], at: [(200, 200)], rack: "A1 A5 B9")
            s.block("A5", .newMeldAt(target))
            add(s)
        }
        s = TurnScript("v3-attach-left", table: ["A2 A3 A4"], at: [(200, 200)], rack: "A1 A5 B9")
        s.block("A1", .newMeldAt(RummyPoint(x: 140, y: 190)))
        add(s)
        s = TurnScript("v3-attach-mismatch", table: ["A2 A3 A4"], at: [(200, 200)], rack: "A1 A5 B9")
        s.block("B9", .newMeldAt(RummyPoint(x: 330, y: 200)))
        add(s)
        for (name, x) in [("near-run", 230), ("near-group", 238)] {
            s = TurnScript("v3-closer-\(name)", table: ["A2 A3 A4", "B5 C5 D5"], at: [(100, 200), (290, 200)], rack: "A5")
            s.block("A5", .newMeldAt(RummyPoint(x: x, y: 200)))
            add(s)
        }
        s = TurnScript("v3-hole", table: ["A1 A2 A3 A4 A5 A6 A7"], at: [(100, 200)])
        s.block("t:A4", .newMeldAt(RummyPoint(x: 600, y: 500)))
        s.block("t:A4", .newMeldAt(RummyPoint(x: 220, y: 204)))
        add(s)
        s = TurnScript("v3-moveset", table: ["A1 A2 A3", "A4 A5", "C9 D9 B9"], at: [(100, 200), (500, 400), (600, 100)])
        s.set(1, 235, 205)
        s.set(1, 310, 200)
        s.set(7, 0, 0)
        add(s)
        s = TurnScript("v3-block-attach", table: ["A3 A4 A5"], at: [(400, 300)], rack: "A1 A2 B7")
        s.block("A1 A2", .newMeldAt(RummyPoint(x: 310, y: 296)))
        add(s)
        s = TurnScript("v3-insert-front-back", table: ["A6 A7 A8"], at: [(300, 200)], rack: "A5 A9 B2")
        s.block("A5", .meld(0, index: 3))
        s.block("A9", .meld(0, index: 0))
        s.block("B2", .meld(0, index: 2))
        add(s)
        s = TurnScript("v3-insert-joker", table: ["A6 A7 J"], at: [(300, 200)], rack: "A8")
        s.block("A8", .meld(0, index: 3))
        add(s)
        s = TurnScript("v3-insert-group", table: ["A5 B5 D5"], at: [(300, 200)], rack: "C5")
        s.block("C5", .meld(0, index: 0))
        add(s)
        s = TurnScript("v3-insert-edge", table: ["A6 A7 A8"], at: [(0, 0)], rack: "A5")
        s.block("A5", .meld(0, index: nil))
        add(s)
        s = TurnScript("v3-growth-hole", table: ["A6 J A8"], at: [(200, 200)], rack: "A7")
        s.block("t:J", .newMeldAt(RummyPoint(x: 600, y: 500)))
        s.block("A7", .meld(0, index: nil))
        add(s)
        s = TurnScript("v3-growth-apart", table: ["A1 A2 A3", "A4"], at: [(0, 0), (136, 0)], rack: "A5")
        s.block("A5", .meld(1, index: nil))
        add(s)

        // MARK: V0369RummyV3FuzzTests 의 적대 검증 장면
        s = TurnScript("verify-no-pull", table: ["A1 A2 A3", "A4 A5 A6"], at: [(0, 0), (136, 0)], rack: "A7")
        s.block("A7", .newMeldAt(RummyPoint(x: 260, y: 0)))
        add(s)
        s = TurnScript("verify-onto", table: ["A1 A2 A3", "A4 A5 A6"], at: [(0, 0), (136, 0)], rack: "A7")
        s.block("A7", .meld(1, index: nil))
        add(s)
        s = TurnScript("verify-moveset-once", table: ["A1 A2 A3", "A4 A5 A6", "A7 A8 A9"], at: [(0, 0), (136, 0), (0, 300)], rack: "B1")
        s.set(2, 262, 4)
        add(s)
        s = TurnScript("verify-gap", table: ["A1 A2 A3", "A5 A6 A7"], at: [(100, 200), (260, 200)], rack: "A4")
        s.block("A4", .newMeldAt(RummyPoint(x: 222, y: 204)))
        add(s)
        for done in [false, true] {
            s = TurnScript("initial-\(done ? "done" : "first")", table: ["A1 A2 A3"], at: [(0, 0)], rack: "A4 A5 A6 B9", initialDone: done)
            s.block("A4 A5 A6", .newMeldAt(RummyPoint(x: 126, y: 2)))
            add(s)
        }
        s = TurnScript("initial-tables", table: ["A1 A2 A3", "A4 A5 A6"], at: [(0, 0), (0, 300)], rack: "B4 B5 B6 B7 B8 B9", initialDone: false)
        s.set(1, 124, 0)
        s.block("B4 B5 B6", .newMeldAt(RummyPoint(x: 0, y: 400)))
        s.block("B7 B8 B9", .newMeldAt(RummyPoint(x: 124, y: 400)))
        add(s)
        s = TurnScript("clamp-above-canvas", table: ["A1 A2 A3"], at: [(0, 0)], rack: "B9 C2 D13")
        s.block("B9", .newMeldAt(RummyPoint(x: 600, y: -120)))
        add(s)

        // MARK: V0370RummyRackTests
        func entries(_ rows: [(String, Int, Int)]) -> (String, [RummyRackEntry]) {
            (rows.map(\.0).joined(separator: " "), rows.map { RummyRackEntry(face: RummyFace(text: $0.0)!, slot: RummyRackSlot(row: $0.1, halfCol: $0.2)) })
        }
        func rackScript(_ id: String, _ rows: [(String, Int, Int)], table: [String] = [], initialDone: Bool = true) -> TurnScript {
            let e = entries(rows)
            return TurnScript(id, table: table, rack: e.0, initialDone: initialDone, entries: e.1)
        }
        let base: [(String, Int, Int)] = [("A5", 0, 0), ("A7", 0, 2), ("B1", 0, 4), ("A6", 1, 0)]
        for (name, col) in [("between", 1), ("onto", 2), ("front", 0), ("free", 11)] {
            s = rackScript("rack-\(name)", base)
            s.afterDrop("A6", row: 0, col: col)
            s.block("A6", .rackSlot(RummyRackSlot(row: 0, halfCol: col)))
            add(s)
        }
        s = rackScript("rack-block", [("A5", 0, 0), ("A8", 0, 2), ("A6", 1, 0), ("A7", 1, 2)])
        s.block("A6 A7", .rackSlot(RummyRackSlot(row: 0, halfCol: 1)))
        add(s)
        s = rackScript("rack-push", [("A1", 0, 0), ("A2", 0, 2), ("A3", 0, 4), ("B5", 0, 9), ("C7", 0, 13), ("D1", 1, 0), ("D2", 1, 2)])
        s.block("D1", .rackSlot(RummyRackSlot(row: 0, halfCol: 2)))
        s.block("D2", .rackSlot(RummyRackSlot(row: 0, halfCol: 2)))
        add(s)
        let two: [(String, Int, Int)] = [("A1", 0, 0), ("A2", 0, 2), ("A3", 0, 4), ("B9", 0, 7), ("B10", 0, 9), ("B11", 0, 11), ("A4", 1, 0), ("B8", 1, 4)]
        s = rackScript("rack-chunk-left", two)
        s.block("A4", .rackSlot(RummyRackSlot(row: 0, halfCol: 6)))
        add(s)
        s = rackScript("rack-chunk-right", two)
        s.block("B8", .rackSlot(RummyRackSlot(row: 0, halfCol: 7)))
        add(s)
        var overflow: [(String, Int, Int)] = [("C1", 0, 0), ("C2", 0, 2)]
        for n in 1...13 { overflow.append(("A\(n)", 0, 6 + (n - 1) * 2)) }
        overflow += [("D9", 1, 0), ("B5", 1, 6)]
        s = rackScript("rack-overflow", overflow)
        s.block("B5", .rackSlot(RummyRackSlot(row: 0, halfCol: 10)))
        add(s)
        var full: [(String, Int, Int)] = []
        for i in 0..<16 { full.append(("\(["A", "B"][i / 8])\(i % 8 + 1)", 0, i * 2)) }
        full += [("D9", 1, 0), ("C5", 1, 8)]
        s = rackScript("rack-full-row", full)
        s.block("C5", .rackSlot(RummyRackSlot(row: 0, halfCol: 4)))
        add(s)
        s = rackScript("rack-plan", [("A7", 0, 0), ("A8", 0, 2), ("A9", 0, 4), ("B10", 0, 7), ("C10", 0, 9), ("D10", 0, 11), ("B2", 1, 0)], table: ["C3 C4 C5"], initialDone: false)
        s.block("B10 C10 D10", .newMeldAt(RummyPoint(x: 400, y: 300)))
        s.block("B2", .newMeldAt(RummyPoint(x: 700, y: 500)))
        s.reset()
        s.stands("C3 C4 C5", "A7 A8 A9 B10 C10 D10 B2")
        s.stands("C5 C3 C4", "B2 A7 A8 A9 B10 C10 D10")
        s.stands("C3 C4 C5|A1 A2 A3", "A7 A8 A9 B10 C10 D10 B2")
        s.stands("C3 C4 C5", "A7 A8 A9 B10 C10 D10")
        s.stands("C3 C4 C5", "A7 A8 A9 B10 C10 D10 B3")
        add(s)
        s = rackScript("rack-entries-overlap", [("A1", 0, 0), ("A2", 0, 0), ("A3", 0, 1), ("A4", 5, 40), ("A5", 1, 30)])
        add(s)
        // 저장 자리에 없는 면(뽑은 타일)은 마지막 빈자리로.
        add(TurnScript("rack-entries-new", rack: "B1 A1 A2", entries: [RummyRackEntry(face: RummyFace(text: "A1")!, slot: RummyRackSlot(row: 0, halfCol: 6)), RummyRackEntry(face: RummyFace(text: "D9")!, slot: RummyRackSlot(row: 1, halfCol: 2))]))

        // 줄의 첫 덩어리가 줄 끝을 넘치면 넘친 타일부터(통째로 안 흘린다).
        var firstChunk: [(String, Int, Int)] = []
        for n in 1...13 { firstChunk.append(("A\(n)", 0, 4 + (n - 1) * 2)) }
        firstChunk += [("B1", 0, 30), ("C5", 1, 0)]
        s = rackScript("rack-first-chunk-overflow", firstChunk)
        s.block("C5", .rackSlot(RummyRackSlot(row: 0, halfCol: 6)))
        add(s)

        // 표시 순서로 다시 늘어놓을 때 점 밀기의 동점 끊기(남은 토막 — 무효 묶음 끝을 빼 맞게 된 토막).
        for (name, table, tail) in [("lead", "C4 B4 D4 A4 A9", "t:A9"), ("key", "B4 A4 D4 C4 A9", "t:A9"), ("abs", "C4 D4 A4 B4 A9", "t:A9"), ("joker", "J A5 A6 A9 B9", "t:A9 t:B9")] {
            s = TurnScript("arrange-\(name)", table: [table], at: [(300, 200)])
            s.block(tail, .newMeldAt(RummyPoint(x: 600, y: 500)))
            add(s)
        }
        // 받은 묶음의 점 밀기(자란 묶음이 표시 순서로 바뀐다).
        s = TurnScript("arrange-received", table: ["D4 A4"], at: [(300, 200)], rack: "B4 C4")
        s.block("B4", .meld(0, index: 2))
        s.block("C4", .meld(0, index: 0))
        add(s)
        s = TurnScript("arrange-joker-side", table: ["J A5"], at: [(300, 200)], rack: "A6")
        s.block("A6", .meld(0, index: nil))
        add(s)

        // 붐비는 판: 받은 묶음이 막혀 옆으로 · 이웃 비켜 놓기 · 꽉 찬 판 대체.
        s = TurnScript("settle-side", table: ["A1 A2 A3", "B1 B2 B3"], at: [(0, 0), (136, 0)], rack: "A4")
        s.block("A4", .meld(0, index: nil))
        add(s)
        s = TurnScript("settle-neighbors", table: ["A1 A2 A3", "B1 B2 B3", "C1 C2 C3"], at: [(8, 0), (136, 0), (0, 72)], rack: "A4 A5 A6 A7")
        s.block("A4 A5 A6 A7", .meld(0, index: nil))
        add(s)

        return all
    }

    // MARK: - 무작위 대본(V0369RummyV3FuzzTests 의 생성을 고정 난수로)

    private func extender(of set: [RummyFace], _ r: inout GoldenRummyRNG) -> RummyFace? {
        let numbered = set.compactMap { face -> (Int, Int)? in face.color.flatMap { c in face.number.map { (c, $0) } } }
        guard let first = numbered.first else { return nil }
        if Set(numbered.map(\.1)).count == 1 {
            let used = Set(numbered.map(\.0))
            let free = (0..<4).filter { !used.contains($0) }
            guard !free.isEmpty else { return nil }
            return RummyFace(color: r.pick(free), number: first.1)
        }
        let numbers = numbered.map(\.1)
        let candidates = [numbers.min()! - 1, numbers.max()! + 1, numbers.min()! - 2, numbers.max()! + 2].filter { (1...13).contains($0) }
        guard !candidates.isEmpty else { return nil }
        return RummyFace(color: first.0, number: r.pick(candidates))
    }

    private func near(_ e: RummyTurnEditor, blockCount: Int, _ r: inout GoldenRummyRNG) -> RummyPoint {
        let w = RummyTableLayout.tileWidth
        let frames = e.tableLayout.frames
        let roll = r.below(10)
        if roll < 4, !frames.isEmpty {
            let f = r.pick(frames)
            return RummyPoint(x: f.maxX + r.range(-30, 30), y: f.y + r.range(-34, 34))
        }
        if roll >= 4, roll < 7, !frames.isEmpty {
            let f = r.pick(frames)
            return RummyPoint(x: f.x - blockCount * w + r.range(-30, 30), y: f.y + r.range(-34, 34))
        }
        if roll == 7 { return RummyPoint(x: r.range(-120, 1120), y: r.range(-80, 720)) }
        return RummyPoint(x: r.range(0, 960), y: r.range(0, 584))
    }

    private enum Op {
        case block([Int], RummyDropTarget)
        case set(Int, RummyPoint)
        case reset
        case sort(RummyRackSort)
    }

    /// 랙 타일을 이어지는 묶음의 끝 곁에 놓기 — V0369RummyV3FuzzTests 는 우연에 맡겨 붙기를 몇 번 안 밟는다(지문 대조가 규칙 ②를 재게 일부러 넣는다).
    private func attachOp(_ e: RummyTurnEditor, _ r: inout GoldenRummyRNG) -> Op? {
        guard !e.melds.isEmpty, !e.rack.isEmpty else { return nil }
        let frames = e.tableLayout.frames
        let meldStart = r.below(e.melds.count), rackStart = r.below(e.rack.count)
        let gap = r.range(-24, 24), rise = r.range(-28, 28)
        for m in 0..<e.melds.count {
            let set = (meldStart + m) % e.melds.count
            let faces = e.melds[set].map(\.face)
            for t in 0..<e.rack.count {
                let tile = e.rack[(rackStart + t) % e.rack.count]
                if RummyRules.isChainable(faces + [tile.face]) {
                    return .block([tile.id], .newMeldAt(RummyPoint(x: frames[set].maxX + gap, y: frames[set].y + rise)))
                }
                if RummyRules.isChainable([tile.face] + faces) {
                    return .block([tile.id], .newMeldAt(RummyPoint(x: frames[set].x - RummyTableLayout.tileWidth + gap, y: frames[set].y + rise)))
                }
            }
        }
        return nil
    }

    private func nextOp(_ e: RummyTurnEditor, _ r: inout GoldenRummyRNG) -> Op {
        let roll = r.below(100)
        if roll < 3 { return .reset }
        if roll < 6 { return .sort(r.flip() ? .number : .color) }
        if roll < 18, !e.melds.isEmpty {
            let set = r.below(e.melds.count)
            return .set(set, near(e, blockCount: e.melds[set].count, &r))
        }
        if roll < 36, let directed = attachOp(e, &r) { return directed }
        var ids: [Int] = []
        let tableIDs = e.melds.flatMap { $0 }.map(\.id)
        let pickKind = r.below(7)
        if pickKind == 0, !e.rack.isEmpty {
            ids = e.rackChain(around: r.pick(e.rack).id)
        } else if pickKind == 1, !e.rack.isEmpty {
            let shuffled = r.shuffled(e.rack)
            ids = e.screenOrder(Set(shuffled.prefix(r.range(1, 3)).map(\.id)))
        } else if pickKind == 2, !tableIDs.isEmpty {
            let pressed = r.pick(tableIDs)
            ids = r.flip() ? e.meldChunk(for: pressed) : e.meldPick(for: pressed, fromTileToEnd: r.flip())
        } else if pickKind == 3, !tableIDs.isEmpty, !e.rack.isEmpty {
            ids = e.screenOrder([r.pick(tableIDs), r.pick(e.rack).id])
        } else if pickKind == 4 || pickKind == 5 {
            if !tableIDs.isEmpty { ids = [r.pick(tableIDs)] }
        } else if !e.rack.isEmpty {
            ids = [r.pick(e.rack).id]
        }
        let all = tableIDs + e.rack.map(\.id)
        if ids.isEmpty, !all.isEmpty { ids = [r.pick(all)] }
        let target: RummyDropTarget
        let tk = r.below(20)
        if tk < 6, !e.melds.isEmpty {
            let set = r.below(e.melds.count)
            target = .meld(set, index: r.below(5) == 0 ? nil : r.range(-1, e.melds[set].count + 1))
        } else if tk == 6 {
            target = .meld(e.melds.count, index: 0)  // 없는 묶음 → 거절
        } else if tk == 7 {
            target = .newMeld
        } else if tk >= 8, tk < 15 {
            target = .newMeldAt(near(e, blockCount: ids.count, &r))
        } else if tk == 15 || tk == 16 {
            target = .rackSlot(RummyRackSlot(row: r.range(0, 2), halfCol: r.range(0, 30)))
        } else if tk == 17 {
            target = .rack(index: nil)
        } else {
            target = .rack(index: r.range(-1, e.rack.count + 1))
        }
        return .block(ids, target)
    }

    private func fuzzCase(seed: Int) -> GoldenJSON {
        var r = GoldenRummyRNG(seed: UInt64(seed) &* 0x1000_0001 &+ 7)
        let crowded = r.below(5) == 0
        let table = (0..<(crowded ? r.range(14, 30) : r.range(0, 6))).map { _ in r.meld() }
        var rack = (0..<r.range(2, 10)).map { _ in r.face() }
        for set in table where r.flip() {
            if let face = extender(of: set, &r) { rack.append(face) }
        }
        rack = r.shuffled(rack)
        var layout: RummyLayout?
        if r.below(3) == 0 {
            var points: [RummyPoint] = []
            var obstacles: [RummyRect] = []
            for set in table {
                let want = RummyPoint(x: r.range(0, 900), y: r.range(0, 580))
                let point = RummyTableLayout.snap(want, tiles: set.count, among: obstacles)
                points.append(point)
                obstacles.append(RummyTableLayout.frame(at: point, tiles: set.count))
            }
            layout = RummyLayout(points.map { Optional($0) })
        }
        let initialDone = r.below(4) != 0
        var editor = RummyTurnEditor(table: table, rack: rack, initialDone: initialDone, tableLayout: layout)
        var lines: [GoldenJSON] = []
        func line(_ op: String, _ ok: Bool, _ preview: String, _ e: RummyTurnEditor) -> GoldenJSON {
            .string("\(op) ~ \(ok ? 1 : 0) ~ \(GoldenRummyText.fnv(preview)) ~ \(GoldenRummyText.fnv(GoldenRummyText.core(e))) ~ \(GoldenRummyText.fnv(GoldenRummyText.extra(e)))")
        }
        lines.append(line("start", true, "-", editor))
        for _ in 0..<r.range(1, 16) {
            switch nextOp(editor, &r) {
            case .block(let ids, let target):
                let preview = GoldenRummyText.preview(editor.previewDrop(ids, to: target))
                let ok = editor.moveBlock(ids, to: target)
                lines.append(line("block \(GoldenRummyText.ids(ids)) \(GoldenRummyText.target(target))", ok, preview, editor))
            case .set(let set, let point):
                let preview = GoldenRummyText.preview(editor.previewMoveSet(set, to: point))
                let ok = editor.moveSet(set, to: point)
                lines.append(line("set \(set) \(GoldenRummyText.point(point))", ok, preview, editor))
            case .reset:
                editor.reset()
                lines.append(line("reset", true, "-", editor))
            case .sort(let mode):
                editor.sortRack(mode)
                lines.append(line("sort \(mode == .number ? "number" : "color")", true, "-", editor))
            }
        }
        var out = TurnStart.json(table: table, rack: rack, initialDone: initialDone, layout: layout, order: nil, entries: nil)
        out["id"] = .string("fuzz-\(seed)")
        out["lines"] = .array(lines)
        return .object(out)
    }

    @Test("rummy/turn-editor — 이름 있는 대본(단계마다 스냅숏) + 무작위 대본(단계마다 지문)")
    func turnEditor() {
        var cases = named().map(\.json)
        for seed in 0..<100 { cases.append(fuzzCase(seed: seed)) }
        goldenEmit(GoldenFile(
            golden: "rummy/turn-editor",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/RummyTurnEditor.swift", "Sources/CheckCore/RummyTableEdit.swift", "Sources/CheckCore/RummyTableLayout.swift", "Sources/CheckCore/RummyRackLayout.swift", "Sources/CheckCore/RummyRackMelds.swift", "Sources/CheckCore/RummyRules.swift"],
            spec: [
                "start": "table('|' 구분)·rack·initialDone·layout(공백 구분, 빈 칸 '-')·rackOrder·rackEntries(공백 구분 'face@row,halfCol') 로 RummyTurnEditor 를 만든다.",
                "steps": "이름 있는 대본: op · ok · preview(놓기 전 previewDrop/previewMoveSet 글자, 동작 없으면 '-') · after(core 글자) · extra(나머지 읽기 글자의 FNV-1a 64).",
                "lines": "무작위 대본: '동작 ~ ok(0/1) ~ preview 지문 ~ core 지문 ~ extra 지문'. 지문 = 글자의 UTF-8 바이트를 하나씩 접은 FNV-1a 64.",
                "ops": "block <ids,> <놓는 곳> · set <번호> <x,y> · reset · sort number|color · afterdrop <ids,> <r,c>(바꾸지 않는다, preview 칸 = 받침대 글자 또는 nil) · stands <판 '|' 구분>;<랙>(바꾸지 않는다) · start(첫 줄).",
                "text": "GoldenRummySupport.swift 머리말 · core · extra 정의 그대로. Kotlin 짝은 commonTest …/rummy/RummyGoldenSupport.kt.",
            ],
            cases: cases
        ))
    }
}
