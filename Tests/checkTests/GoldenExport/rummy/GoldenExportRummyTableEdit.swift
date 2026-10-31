// 원본: Sources/CheckCore/RummyTableEdit.swift @ 1a5eeca6 (골든 생성기 — 아잉 큐브 판 편집 규칙)
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// 아잉 큐브 판 편집 골든(rummy/table-edit): 남의 작업 판·확정 판을 저마다 그리므로 split · attachment · attachedPoint · insertionIndex · settle · pickRange 가 비트로 같아야 한다.

@Suite("GoldenExport rummy — 판 편집(rummy/table-edit)")
struct GoldenExportRummyTableEdit {
    private typealias T = GoldenRummyText

    private func piecesText(_ pieces: [RummySplitPiece]) -> GoldenJSON {
        .string(pieces.map { "\($0.range.lowerBound)..\($0.range.upperBound)@\(T.point($0.point))" }.joined(separator: " "))
    }

    @Test("rummy/table-edit — split · attachment · attachedPoint · insertionIndex · settle · pickRange")
    func tableEdit() {
        var cases: [GoldenJSON] = []
        var r = GoldenRummyRNG(seed: 0xED17_0000)
        cases.append(["id": "constants", "kind_": "constants", "attachGap": .int(RummyTableEdit.attachGap), "attachRise": .int(RummyTableEdit.attachRise)])

        // split: 7장까지 모든 빼기 조합.
        for count in 0...7 {
            for mask in 0..<(1 << count) {
                let removed = Set((0..<count).filter { mask & (1 << $0) != 0 })
                let point = RummyPoint(x: 100 + count, y: 200)
                cases.append([
                    "id": .string("split-\(count)-\(mask)"), "kind_": "split", "count": .int(count), "mask": .int(mask), "point": .string(T.point(point)),
                    "pieces": piecesText(RummyTableEdit.split(count: count, point: point, removing: removed)),
                ])
            }
        }

        // pickRange: 경계 포함.
        for count in 0...14 {
            for pressed in -1...(count + 1) {
                let range = RummyTableEdit.pickRange(count: count, pressed: pressed)
                cases.append(["id": .string("pick-\(count)-\(pressed < 0 ? "m1" : "\(pressed)")"), "kind_": "pick", "count": .int(count), "pressed": .int(pressed), "lo": .int(range.lowerBound), "hi": .int(range.upperBound)])
            }
        }

        // attachedPoint 표.
        for side in [RummyAttachSide.left, .right] {
            for count in 1...4 {
                let p = RummyTableEdit.attachedPoint(target: RummyPoint(x: 300, y: 120), side: side, blockCount: count)
                cases.append(["id": .string("attached-\(side.rawValue)-\(count)"), "kind_": "attached", "side": .string(side.rawValue), "count": .int(count), "point": .string(T.point(p))])
            }
        }

        // attachment: 무작위 이웃 + 끝 가까운 자리(붙기가 실제로 일어나게) + 볼 쪽 제한.
        func extendAttachment(_ id: String, block: [RummyFace], frame: RummyRect, sets: [[RummyFace]], frames: [RummyRect], sides: [RummyAttachSide]) {
            let hit = RummyTableEdit.attachment(block: block, frame: frame, sets: sets, frames: frames, sides: sides)
            cases.append([
                "id": .string(id), "kind_": "attachment", "block": .string(T.text(block)), "frame": .string(T.rect(frame)),
                "sets": .string(T.sets(sets)), "frames": .string(T.rects(frames)),
                "sides": .string(sides.map(\.rawValue).joined(separator: ",")),
                "hit": hit.map { .string("\($0.set):\($0.side.rawValue)") } ?? .null,
            ])
        }
        for i in 0..<110 {
            let sets = (0..<r.range(1, 5)).map { _ in r.meld() }
            var frames: [RummyRect] = []
            for (index, set) in sets.enumerated() {
                frames.append(RummyTableLayout.frame(at: RummyPoint(x: r.range(0, 800) / 8 * 8, y: (index * 72 + r.range(0, 40))), tiles: set.count))
            }
            let host = r.below(sets.count)
            let chosen = sets[host]
            let numbers = chosen.compactMap(\.number)
            let colors = chosen.compactMap(\.color)
            let onRight = r.flip()
            var extending = [r.face()]
            if r.below(5) != 0 {
                // 이어지는 면을 고른다(런이면 그쪽 끝 다음 숫자, 그룹이면 빠진 색) — 붙기가 실제로 일어나게.
                if Set(numbers).count == 1 {
                    let free = (0..<4).filter { !colors.contains($0) }
                    if !free.isEmpty, let number = numbers.first { extending = [RummyFace(color: r.pick(free), number: number)] }
                } else if let lo = numbers.min(), let hi = numbers.max(), let color = colors.first {
                    let next = onRight ? hi + 1 : lo - 1
                    if (1...13).contains(next) { extending = [RummyFace(color: color, number: next)] }
                }
            } else if r.flip() {
                extending = [r.face(), r.face()]
            }
            let tiles = extending.count
            let near = onRight
                ? RummyPoint(x: frames[host].maxX + r.range(-30, 30), y: frames[host].y + r.range(-34, 34))
                : RummyPoint(x: frames[host].x - tiles * RummyTableLayout.tileWidth + r.range(-30, 30), y: frames[host].y + r.range(-34, 34))
            let sides: [RummyAttachSide] = [[.right, .left], [.right], [.left], [.left, .right]][r.below(4)]
            extendAttachment("attach-\(i)", block: extending, frame: RummyTableLayout.frame(at: near, tiles: tiles), sets: sets, frames: frames, sides: sides)
        }
        // 양쪽 끝이 같은 거리 — 오른끝 먼저(묶음 폭 40 이상이면 안 생기므로 좁은 사각형으로 잰다).
        let narrow = RummyRect(x: 200, y: 100, width: 10, height: 56)
        extendAttachment("attach-tie-sides", block: T.faces("A5"), frame: narrow, sets: [T.faces("J J")], frames: [narrow], sides: [.right, .left])
        extendAttachment("attach-tie-sides-rev", block: T.faces("A5"), frame: narrow, sets: [T.faces("J J")], frames: [narrow], sides: [.left, .right])
        // 두 묶음이 같은 거리 — 번호 앞 먼저.
        let twin = RummyRect(x: 300, y: 100, width: 80, height: 56)
        extendAttachment("attach-tie-sets", block: T.faces("A5"), frame: RummyRect(x: 380, y: 100, width: 40, height: 56), sets: [T.faces("A3 A4"), T.faces("A3 A4")], frames: [twin, twin], sides: [.right, .left])
        // 경계 — 빈 블록 · 빈 대상 · 길이 다른 frames · 간격 24/25 · 세로 28/29.
        let run = T.faces("A2 A3 A4")
        let runFrame = RummyTableLayout.frame(at: RummyPoint(x: 200, y: 200), tiles: 3)
        extendAttachment("attach-empty-block", block: [], frame: runFrame, sets: [run], frames: [runFrame], sides: [.right, .left])
        extendAttachment("attach-empty-target", block: T.faces("A5"), frame: runFrame, sets: [[]], frames: [runFrame], sides: [.right, .left])
        extendAttachment("attach-short-frames", block: T.faces("A5"), frame: runFrame, sets: [run, run], frames: [runFrame], sides: [.right, .left])
        for gap in [-25, -24, 24, 25] {
            for rise in [-29, -28, 28, 29] {
                let frame = RummyTableLayout.frame(at: RummyPoint(x: runFrame.maxX + gap, y: runFrame.y + rise), tiles: 1)
                extendAttachment("attach-edge-\(gap)-\(rise)", block: T.faces("A5"), frame: frame, sets: [run], frames: [runFrame], sides: [.right, .left])
            }
        }

        // insertionIndex: 표(이름 시험과 같은 입력) + 무작위.
        func addInsertion(_ id: String, _ block: [RummyFace], _ meld: [RummyFace], _ preferred: Int) {
            let got = RummyTableEdit.insertionIndex(block, into: meld, preferred: preferred)
            cases.append(["id": .string(id), "kind_": "insertion", "block": .string(T.text(block)), "meld": .string(T.text(meld)), "preferred": .int(preferred), "index": .int(got.index), "fits": .bool(got.fits)])
        }
        let named: [(String, String, Int)] = [
            ("A5", "A6 A7 A8", 3), ("A9", "A6 A7 A8", 0), ("A8", "A6 A7 J", 3), ("A8", "A5 J A7", 0), ("J", "A5 A6 A7", 0), ("J", "A5 A6 A7", 2),
            ("A9 A10", "A6 A7 A8", 0), ("D5", "A5 B5 C5", 0), ("B2", "A6 A7 A8", 1), ("A5", "", 9), ("C5", "A5 B5 D5", 0), ("J", "A5 B5 C5", 0), ("A5", "B5 C5 J", 3),
            // 두 자리가 놓은 자리에서 같은 거리면 오른쪽(동점 끊기).
            ("J", "A5 A6", 1), ("J", "C7 C8", 1), ("J", "A12 A13", 1),
        ]
        for (i, row) in named.enumerated() { addInsertion("insert-n\(i)", T.faces(row.0), T.faces(row.1), row.2) }
        for i in 0..<110 {
            let meld = r.below(4) == 0 ? (0..<r.range(0, 5)).map { _ in r.face() } : r.meld()
            let numbers = meld.compactMap(\.number)
            let colors = meld.compactMap(\.color)
            var block = [r.face()]
            if r.below(4) != 0 {
                // 맞는 자리가 있는 면(런 앞뒤 · 안쪽 빈칸 · 그룹 빠진 색) — 자리 고르기가 실제로 돌게.
                if Set(numbers).count == 1 {
                    let free = (0..<4).filter { !colors.contains($0) }
                    if !free.isEmpty, let number = numbers.first { block = [RummyFace(color: r.pick(free), number: number)] }
                } else if let lo = numbers.min(), let hi = numbers.max(), let color = colors.first {
                    let next = r.pick([hi + 1, lo - 1, hi + 2, lo + 1, lo - 2])
                    if (1...13).contains(next) {
                        block = [RummyFace(color: color, number: next)]
                        if next < 13, r.below(4) == 0 { block.append(RummyFace(color: color, number: next + 1)) }
                    }
                }
            } else if r.flip() {
                block = [r.face(), r.face()]
            }
            addInsertion("insert-r\(i)", block, meld, r.range(-2, meld.count + 2))
        }

        // settle: 늘어난 묶음 앉히기 — 그대로 · 옆으로 · 이웃 비켜 놓기 · 판 밖 · 번호 밖.
        for i in 0..<90 {
            let crowded = i % 6 == 0
            let n = crowded ? r.range(14, 30) : r.range(1, 8)
            var frames: [RummyRect] = []
            for _ in 0..<n {
                let tiles = r.range(1, 7)
                let point = crowded ? RummyTableLayout.firstFree(tiles: tiles, among: frames) : RummyPoint(x: r.range(0, 900) / 8 * 8, y: r.range(0, 584) / 8 * 8)
                frames.append(RummyTableLayout.frame(at: point, tiles: tiles))
            }
            let index = r.below(n + 1) == n ? (r.flip() ? n : -1) : r.below(n)
            let grown = r.range(-1, 4)
            if frames.indices.contains(index) {
                // 곁 묶음으로 일부러 밀어 넣는다(막히게).
                let target = frames[r.below(n)]
                let moved = RummyRect(x: r.flip() ? target.maxX + r.range(-40, 40) : frames[index].x, y: r.flip() ? target.y + r.range(-60, 60) : frames[index].y, width: frames[index].width, height: frames[index].height)
                frames[index] = moved
            }
            let points = RummyTableEdit.settle(frames, index: index, grown: grown)
            cases.append([
                "id": .string("settle-\(i)"), "kind_": "settle", "frames": .string(T.rects(frames)), "index": .int(index), "grown": .int(grown),
                "points": .string(T.points(points)),
            ])
        }

        // 옆으로 밀 때 같은 거리면 왼쪽 먼저 — 가운데 막힘(폭 160 · 막는 묶음 40, 양쪽 116 씩).
        let blocker = RummyRect(x: 460, y: 100, width: 40, height: 56)
        for (i, grown) in [3, 2, 4].enumerated() {
            let frames = [RummyRect(x: 400, y: 100, width: 160, height: 56), blocker]
            let points = RummyTableEdit.settle(frames, index: 0, grown: grown)
            cases.append(["id": .string("settle-tie-\(i)"), "kind_": "settle", "frames": .string(T.rects(frames)), "index": 0, "grown": .int(grown), "points": .string(T.points(points))])
        }

        goldenEmit(GoldenFile(
            golden: "rummy/table-edit",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/RummyTableEdit.swift", "Sources/CheckCore/RummyTableLayout.swift", "Sources/CheckCore/RummyRackLayout.swift", "Sources/CheckCore/RummyRules.swift"],
            spec: [
                "kind_": "constants · split(mask 의 켠 자리를 뺀다 — 'lo..hi@x,y' 왼쪽부터, 공백 구분) · pick(lo..<hi) · attached · attachment(hit 'set:side' 또는 null) · insertion · settle(frames·index·grown → points).",
                "text": "점 'x,y' · 사각형 'x,y,w,h' · 면 목록 공백 구분 · 묶음 목록 'A1 A2|B1'(빈 칸 = 빈 묶음) · 사각형·점 목록 공백 구분 · sides 는 쉼표 구분.",
            ],
            cases: cases
        ))
    }
}
