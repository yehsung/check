// 원본: Sources/CheckCore/RummyRackLayout.swift · RummyRackMelds.swift @ 1a5eeca6 (골든 생성기 — 아잉 큐브 받침대)
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// 아잉 큐브 받침대 골든(rummy/rack-layout): insert(끼워 넣기 · 흘림) · grouped · packed · sortUnits · chunks · isFree · nearestFree · endSlot · RackMelds.

@Suite("GoldenExport rummy — 받침대(rummy/rack-layout)")
struct GoldenExportRummyRackLayout {
    private typealias T = GoldenRummyText

    /// 겹치지 않는 무작위 받침대(id 0..<count).
    private func randomLayout(_ r: inout GoldenRummyRNG, count: Int) -> RummyRackLayout {
        var layout = RummyRackLayout()
        for id in 0..<count {
            let want = RummyRackSlot(row: r.range(0, 2), halfCol: r.range(0, 30))
            layout.set([id], at: layout.isFree(want) ? want : layout.nearestFree(to: want))
        }
        return layout
    }

    private func entries(_ layout: RummyRackLayout) -> GoldenJSON { .string(T.layout(layout)) }

    @Test("rummy/rack-layout — insert · grouped · packed · sortUnits · chunks · 빈자리 · RackMelds")
    func rackLayout() {
        var cases: [GoldenJSON] = []
        var r = GoldenRummyRNG(seed: 0x4ACC_0000)
        cases.append(["id": "constants", "kind_": "constants", "halfColumnsPerRow": .int(RummyRackLayout.halfColumnsPerRow), "baseRows": .int(RummyRackLayout.baseRows), "tileSpan": .int(RummyRackLayout.tileSpan)])

        // insert: 연속 놓기 — 한 받침대에 여러 번(앞 결과가 다음 입력).
        for i in 0..<36 {
            let count = r.range(2, 30)
            var layout = randomLayout(&r, count: count)
            let seedLayout = T.layout(layout)
            var steps: [GoldenJSON] = []
            for _ in 0..<r.range(1, 5) {
                let start = r.below(count)
                let length = min(r.range(1, 4), count - start)
                let ids = Array(start..<(start + length))
                let wanted = RummyRackSlot(row: r.range(-1, 3), halfCol: r.range(-2, 33))
                layout.insert(ids, at: wanted)
                steps.append(.string("\(T.ids(ids)) \(T.slot(wanted)) => \(T.layout(layout)) rows=\(layout.rowCount) chunks=\(layout.chunks.map(T.ids).joined(separator: ";")) order=\(T.ids(layout.readingOrder))"))
            }
            cases.append(["id": .string("insert-\(i)"), "kind_": "insert", "count": .int(count), "seedLayout": .string(seedLayout), "steps": .array(steps)])
        }

        // 빈자리 찾기(isFree · nearestFree · endSlot · tile(covering:)).
        for i in 0..<70 {
            let count = i % 5 == 0 ? r.range(30, 50) : r.range(0, 25)
            let layout = randomLayout(&r, count: count)
            let slot = RummyRackSlot(row: r.range(-1, 4), halfCol: r.range(-2, 34))
            let tiles = r.range(1, 5)
            let excluding = Set((0..<count).filter { _ in r.below(5) == 0 })
            cases.append([
                "id": .string("free-\(i)"), "kind_": "free", "layout": entries(layout), "slot": .string(T.slot(slot)), "tiles": .int(tiles), "excluding": .string(T.ids(excluding.sorted())),
                "isFree": .bool(layout.isFree(slot, tiles: tiles, excluding: excluding)),
                "nearest": .string(T.slot(layout.nearestFree(to: slot, tiles: tiles, excluding: excluding))),
                "end": .string(T.slot(layout.endSlot(tiles: tiles, excluding: excluding))),
                "covering": layout.tile(covering: slot).map { .int($0) } ?? .null,
                "rows": .int(layout.rowCount), "order": .string(T.ids(layout.readingOrder)), "chunks": .string(layout.chunks.map(T.ids).joined(separator: ";")),
            ])
        }

        // packed · grouped.
        for i in 0..<30 {
            var next = 0
            let units: [[Int]] = (0..<r.range(0, 16)).map { _ in
                let n = r.range(0, 20)
                let ids = Array(next..<(next + n))
                next += n
                return ids
            }
            let gap = r.range(0, 3)
            cases.append([
                "id": .string("group-\(i)"), "kind_": "grouped", "units": .string(units.map(T.ids).joined(separator: ";")), "gap": .int(gap),
                "grouped": entries(.grouped(units, gap: gap)), "groupedDefault": entries(.grouped(units)), "packed": entries(.packed(units.flatMap { $0 })),
            ])
        }

        // sortUnits.
        for i in 0..<36 {
            let tiles = (0..<r.range(0, 22)).map { RummyTile(id: $0, face: r.face()) }
            for (mode, name) in [(RummyRackSort.number, "number"), (.color, "color")] {
                let units = RummyRackLayout.sortUnits(tiles, by: mode)
                cases.append([
                    "id": .string("sort-\(i)-\(name)"), "kind_": "sort", "mode": .string(name), "faces": .string(T.text(tiles.map(\.face))),
                    "units": .string(units.map { unit in unit.map { "\($0.id):\($0.face.text)" }.joined(separator: " ") }.joined(separator: "|")),
                ])
            }
        }

        // RackMelds — 저장 자리로 만든 편집기(이름 시험 표 + 무작위).
        func addMelds(_ id: String, _ rows: [(String, Int, Int)], table: [String] = [], initialDone: Bool = true) {
            let faces = rows.map { RummyFace(text: $0.0)! }
            let saved = rows.map { RummyRackEntry(face: RummyFace(text: $0.0)!, slot: RummyRackSlot(row: $0.1, halfCol: $0.2)) }
            let editor = RummyTurnEditor(table: table.map(T.faces), rack: faces, initialDone: initialDone, rackEntries: saved)
            cases.append([
                "id": .string(id), "kind_": "melds", "entries": .string(rows.map { "\($0.0)@\($0.1),\($0.2)" }.joined(separator: " ")), "table": .string(table.joined(separator: "|")), "initialDone": .bool(initialDone),
                "melds": .string(editor.rackMelds.map { "\(T.ids($0.tileIDs)):\($0.kind.rawValue):\($0.points)" }.joined(separator: ";")),
                "points": .int(editor.rackMeldPoints),
                "plan": editor.initialPlanPoints.map { .string("\($0.table),\($0.rack)") } ?? .null,
                "core": .string(T.core(editor)),
            ])
        }
        addMelds("melds-named", [
            ("A7", 0, 0), ("A8", 0, 2), ("A9", 0, 4), ("B10", 0, 7), ("C10", 0, 9), ("D10", 0, 11), ("B2", 0, 14), ("B4", 0, 16),
            ("J", 0, 19), ("D5", 0, 21), ("D6", 0, 23), ("C1", 1, 0), ("C2", 1, 2), ("C3", 1, 4), ("C9", 1, 6), ("A11", 1, 10), ("A12", 1, 13), ("A13", 1, 15),
        ])
        addMelds("melds-plan", [("A7", 0, 0), ("A8", 0, 2), ("A9", 0, 4), ("B10", 0, 7), ("C10", 0, 9), ("D10", 0, 11), ("B2", 1, 0)], table: ["C3 C4 C5"], initialDone: false)
        addMelds("melds-dup", [("A7", 0, 0), ("A7", 0, 2), ("A7", 0, 4), ("A8", 0, 0), ("A9", 0, 2)])
        let colors = ["A", "B", "C", "D"]
        for i in 0..<30 {
            var rows: [(String, Int, Int)] = []
            var row = 0, col = 0
            for _ in 0..<r.range(3, 7) {
                let run = r.flip()
                let n = r.range(1, 5)
                let color = r.pick(colors)
                let start = r.range(1, 9)
                for k in 0..<n {
                    let text = r.below(8) == 0 ? "J" : (run ? "\(color)\(start + k)" : "\(colors[k % 4])\(start)")
                    rows.append((text, row, col))
                    col += 2
                    if col + 2 > 32 { row += 1; col = 0 }
                }
                col += 1
                if col + 2 > 32 { row += 1; col = 0 }
            }
            addMelds("melds-r\(i)", rows, table: r.flip() ? ["C3 C4 C5"] : [], initialDone: r.flip())
        }

        goldenEmit(GoldenFile(
            golden: "rummy/rack-layout",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/RummyRackLayout.swift", "Sources/CheckCore/RummyRackMelds.swift", "Sources/CheckCore/RummyTurnEditor.swift", "Sources/CheckCore/RummyRules.swift"],
            spec: [
                "kind_": "constants · insert · free · grouped · sort · melds.",
                "insert": "seedLayout 에서 시작해 steps 를 차례로 한다. 한 단계 = '옮길 id들 row,halfCol => 놓은 뒤 자리 rows=.. chunks=.. order=..'.",
                "layout": "받침대 글자 = id 오름차순 'id@row,halfCol' 공백 구분.",
                "melds": "entries 'face@row,halfCol' 로 RummyTurnEditor(rackEntries:) 를 만들어 rackMelds('ids:kind:points' ; 구분) · rackMeldPoints · initialPlanPoints 를 잰다. core 는 편집기 글자(GoldenRummySupport.core).",
            ],
            cases: cases
        ))
    }
}
