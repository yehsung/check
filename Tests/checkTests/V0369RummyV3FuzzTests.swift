import Foundation
import Testing
@testable import CheckCore
@testable import check

// 아잉 큐브 3판(K3·U3) 적대 검증 — 무작위 편집 시퀀스 퍼즈. 편집기 새 규칙(가운데 빼면 둘로 · 가까이 붙기 · 정렬 삽입)이
// 타일을 잃거나 · 판 출신을 랙으로 보내거나(R-14) · 묶음을 겹치게 두거나 · 손대지 않은 타일을 옮기거나 · 미리보기와 실제가
// 어긋나거나 · 같은 입력에 다른 답을 내는 경우를 찾는다. 시퀀스 수 = 환경 `RUMMY_FUZZ_SEQS`(기본 240 — 빠른 게이트용),
// `RUMMY_FUZZ_OUT` 을 주면 최종 판들을 reference.py 형식(cases.json)으로 써서 판정 짝(클라 `judgeTurn` ↔ reference.py)을 대 본다.

private struct FuzzRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private enum FuzzOp: Hashable {
    case block([Int], RummyDropTarget)
    case set(Int, RummyPoint)
    case reset
    case sort(RummyRackSortKey)
}

private enum RummyRackSortKey: Hashable { case number, color }

private let fuzzColors = ["A", "B", "C", "D"]

private func fz(_ color: String, _ number: Int) -> RummyFace { RummyFace(text: "\(color)\(number)")! }

private func fuzzSet(_ r: inout FuzzRNG) -> [RummyFace] {
    var faces: [RummyFace]
    if Bool.random(using: &r) {
        let n = Int.random(in: 3...7, using: &r)
        let start = Int.random(in: 1...(14 - n), using: &r)
        let color = fuzzColors.randomElement(using: &r)!
        faces = (start..<(start + n)).map { fz(color, $0) }
    } else {
        let n = Int.random(in: 3...4, using: &r)
        let number = Int.random(in: 1...13, using: &r)
        faces = fuzzColors.shuffled(using: &r).prefix(n).map { fz($0, number) }
    }
    if Int.random(in: 0..<5, using: &r) == 0 { faces[Int.random(in: 0..<faces.count, using: &r)] = .joker }
    return faces
}

/// 판 묶음을 잇는 면(런 앞뒤 · 그룹 빠진 색) — 붙기·끼우기가 실제로 일어나게.
private func extender(of set: [RummyFace], _ r: inout FuzzRNG) -> RummyFace? {
    let numbered = set.compactMap { face -> (Int, Int)? in face.color.flatMap { c in face.number.map { (c, $0) } } }
    guard let first = numbered.first else { return nil }
    if Set(numbered.map(\.1)).count == 1 {
        let used = Set(numbered.map(\.0))
        let free = (0..<4).filter { !used.contains($0) }
        guard let color = free.randomElement(using: &r) else { return nil }
        return fz(fuzzColors[color], first.1)
    }
    let numbers = numbered.map(\.1)
    let candidates = [numbers.min()! - 1, numbers.max()! + 1, numbers.min()! - 2, numbers.max()! + 2].filter { (1...13).contains($0) }
    guard let number = candidates.randomElement(using: &r) else { return nil }
    return fz(fuzzColors[first.0], number)
}

private func fuzzFace(_ r: inout FuzzRNG) -> RummyFace {
    Int.random(in: 0..<16, using: &r) == 0 ? .joker : fz(fuzzColors.randomElement(using: &r)!, Int.random(in: 1...13, using: &r))
}

/// 판 위 타일 id → 화면 왼쪽 위.
private func fuzzSpots(_ e: RummyTurnEditor) -> [Int: RummyPoint] {
    var spots: [Int: RummyPoint] = [:]
    for (set, meld) in e.melds.enumerated() {
        for (index, tile) in meld.enumerated() {
            spots[tile.id] = RummyPoint(x: e.points[set].x + index * RummyTableLayout.tileWidth, y: e.points[set].y)
        }
    }
    return spots
}

private func fuzzFrames(_ e: RummyTurnEditor) -> [RummyRect] {
    e.melds.indices.map { RummyTableLayout.frame(at: e.points[$0], tiles: e.melds[$0].count) }
}

private func fuzzClear(_ frames: [RummyRect]) -> Bool {
    for i in frames.indices {
        guard RummyTableLayout.fits(frames[i]) else { return false }
        for j in frames.indices where j > i && RummyTableLayout.overlaps(frames[i], frames[j]) { return false }
    }
    return true
}

private func fuzzNear(_ e: RummyTurnEditor, blockCount: Int, _ r: inout FuzzRNG) -> RummyPoint {
    let w = RummyTableLayout.tileWidth
    let frames = fuzzFrames(e)
    switch Int.random(in: 0..<10, using: &r) {
    case 0..<4 where !frames.isEmpty:
        let f = frames.randomElement(using: &r)!
        return RummyPoint(x: f.maxX + Int.random(in: -30...30, using: &r), y: f.y + Int.random(in: -34...34, using: &r))
    case 4..<7 where !frames.isEmpty:
        let f = frames.randomElement(using: &r)!
        return RummyPoint(x: f.x - blockCount * w + Int.random(in: -30...30, using: &r),
                          y: f.y + Int.random(in: -34...34, using: &r))
    case 7:
        return RummyPoint(x: Int.random(in: -120...1120, using: &r), y: Int.random(in: -80...720, using: &r))
    default:
        return RummyPoint(x: Int.random(in: 0...960, using: &r), y: Int.random(in: 0...584, using: &r))
    }
}

private func fuzzOp(_ e: RummyTurnEditor, _ r: inout FuzzRNG) -> FuzzOp {
    let roll = Int.random(in: 0..<100, using: &r)
    if roll < 3 { return .reset }
    if roll < 6 { return .sort(Bool.random(using: &r) ? .number : .color) }
    if roll < 18, !e.melds.isEmpty {
        let set = Int.random(in: 0..<e.melds.count, using: &r)
        return .set(set, fuzzNear(e, blockCount: e.melds[set].count, &r))
    }
    // 블록 고르기.
    var ids: [Int] = []
    let tableIDs = e.melds.flatMap { $0 }.map(\.id)
    switch Int.random(in: 0..<7, using: &r) {
    case 0 where !e.rack.isEmpty:
        ids = e.rackChain(around: e.rack.randomElement(using: &r)!.id)
    case 1 where !e.rack.isEmpty:
        let pick = Set(e.rack.shuffled(using: &r).prefix(Int.random(in: 1...3, using: &r)).map(\.id))
        ids = e.screenOrder(pick)
    case 2 where !tableIDs.isEmpty:
        ids = e.meldPick(for: tableIDs.randomElement(using: &r)!, fromTileToEnd: Bool.random(using: &r))
    case 3 where !tableIDs.isEmpty && !e.rack.isEmpty:
        ids = e.screenOrder([tableIDs.randomElement(using: &r)!, e.rack.randomElement(using: &r)!.id])
    case 4, 5:
        if let id = tableIDs.randomElement(using: &r) { ids = [id] }
    default:
        if let tile = e.rack.randomElement(using: &r) { ids = [tile.id] }
    }
    if ids.isEmpty, let any = (tableIDs + e.rack.map(\.id)).randomElement(using: &r) { ids = [any] }
    let target: RummyDropTarget
    switch Int.random(in: 0..<20, using: &r) {
    case 0..<6 where !e.melds.isEmpty:
        let set = Int.random(in: 0..<e.melds.count, using: &r)
        let slot: Int? = Int.random(in: 0..<5, using: &r) == 0 ? nil : Int.random(in: -1...(e.melds[set].count + 1), using: &r)
        target = .meld(set, index: slot)
    case 6:
        target = .meld(e.melds.count, index: 0)  // 없는 묶음 → 거절
    case 7:
        target = .newMeld
    case 8..<15:
        target = .newMeldAt(fuzzNear(e, blockCount: ids.count, &r))
    case 15, 16:
        target = .rackSlot(RummyRackSlot(row: Int.random(in: 0...2, using: &r), halfCol: Int.random(in: 0...30, using: &r)))
    case 17:
        target = .rack(index: nil)
    default:
        target = .rack(index: Int.random(in: -1...(e.rack.count + 1), using: &r))
    }
    return .block(ids, target)
}

private func fuzzApply(_ e: inout RummyTurnEditor, _ op: FuzzOp) -> Bool {
    switch op {
    case .block(let ids, let target): return e.moveBlock(ids, to: target)
    case .set(let set, let point): return e.moveSet(set, to: point)
    case .reset: e.reset(); return true
    case .sort(let key): e.sortRack(key == .number ? .number : .color); return true
    }
}

private struct FuzzStart {
    let table: [[RummyFace]]
    let rack: [RummyFace]
    let initialDone: Bool
    let layout: RummyLayout?

    func editor() -> RummyTurnEditor {
        RummyTurnEditor(table: table, rack: rack, initialDone: initialDone, tableLayout: layout)
    }
}

private func fuzzStart(_ r: inout FuzzRNG) -> FuzzStart {
    let table = (0..<Int.random(in: 0...6, using: &r)).map { _ in fuzzSet(&r) }
    var rack = (0..<Int.random(in: 2...10, using: &r)).map { _ in fuzzFace(&r) }
    for set in table where Bool.random(using: &r) {
        if let face = extender(of: set, &r) { rack.append(face) }
    }
    rack.shuffle(using: &r)
    // 배치: 대개 자동 배치(여백 16 으로 한 줄에 붙어 선다 — 붙기 거리 24 안), 가끔 손으로 흩은 배치.
    var layout: RummyLayout?
    if Int.random(in: 0..<3, using: &r) == 0 {
        var points: [RummyPoint] = []
        var obstacles: [RummyRect] = []
        for set in table {
            let want = RummyPoint(x: Int.random(in: 0...900, using: &r), y: Int.random(in: 0...580, using: &r))
            let point = RummyTableLayout.snap(want, tiles: set.count, among: obstacles)
            points.append(point)
            obstacles.append(RummyTableLayout.frame(at: point, tiles: set.count))
        }
        layout = RummyLayout(points.map { Optional($0) })
    }
    return FuzzStart(table: table, rack: rack, initialDone: Int.random(in: 0..<4, using: &r) != 0, layout: layout)
}

private func faceBag(_ faces: [RummyFace]) -> [String: Int] {
    var bag: [String: Int] = [:]
    for face in faces { bag[face.text, default: 0] += 1 }
    return bag
}

/// 한 단계 검사. 실패 문구를 돌려준다(빈 배열 = 통과).
private func fuzzCheck(
    before: RummyTurnEditor, after: RummyTurnEditor, op: FuzzOp, accepted: Bool, preview: RummyDropPreview??,
    start: FuzzStart, startIDs: Set<Int>, tableIDs: Set<Int>, startClear: Bool
) -> [String] {
    var bad: [String] = []
    func checkLanding(_ preview: RummyDropPreview, block: [Int]) {
        guard let landing = preview.landing else {
            if case .rack = preview.plan {} else { bad.append("판행인데 landing 없음") }
            return
        }
        guard after.melds.indices.contains(landing.set) else { bad.append("landing 번호 밖"); return }
        let meld = after.melds[landing.set]
        if landing.faces != meld.map(\.face) { bad.append("landing 면 ≠ 실제") }
        if landing.frame != RummyTableLayout.frame(at: after.points[landing.set], tiles: meld.count) { bad.append("landing 사각형 ≠ 실제") }
        if landing.valid != RummyRules.analyze(meld.map(\.face)).valid { bad.append("landing 유효 ≠ 실제") }
        let ids = meld.map(\.id)
        let start = landing.blockStart
        if start + block.count > ids.count || Array(ids[start..<(start + block.count)]) != block {
            bad.append("블록이 놓은 묶음 안에서 한 덩어리가 아니다")
        }
        if case .attach = preview.plan, !RummyRules.isChainable(meld.map(\.face)) { bad.append("붙였는데 이어질 수 없는 모양") }
    }

    func checkPreview(set: Int) {
        guard let preview else { return }
        if (preview == nil) == accepted { bad.append("묶음 옮기기 미리보기 거절 여부 ≠ 실제") }
        if let preview, accepted, let first = before.melds.indices.contains(set) ? before.melds[set].map(\.id) : nil {
            checkLanding(preview, block: first)
            // 옮긴 묶음·붙은 묶음 말고는 제자리.
            let landed = preview.landing.map { Set(after.melds[$0.set].map(\.id)) } ?? []
            let was = fuzzSpots(before), now = fuzzSpots(after)
            for (id, spot) in was where !landed.contains(id) && now[id] != spot {
                bad.append("묶음 옮기기: 손대지 않은 타일 \(id) 이동"); break
            }
        }
    }

    let allTiles = after.melds.flatMap { $0 } + after.rack
    // 1) 보존: id 집합 · 면 다중집합.
    if Set(allTiles.map(\.id)) != startIDs || allTiles.count != startIDs.count { bad.append("id 보존 깨짐") }
    if faceBag(allTiles.map(\.face)) != faceBag(start.table.flatMap { $0 } + start.rack) { bad.append("면 보존 깨짐") }
    // 2) R-14: 판 출신은 늘 판 위.
    let onTable = Set(after.melds.flatMap { $0 }.map(\.id))
    if !tableIDs.isSubset(of: onTable) { bad.append("판 출신이 랙으로 감(R-14)") }
    // 3) 모양.
    if after.melds.contains(where: \.isEmpty) || after.melds.count != after.points.count { bad.append("빈 묶음/점 길이") }
    if after.rack.map(\.id) != after.rackLayout.readingOrder { bad.append("랙 화면 순서 ≠ 자리") }
    // 4) 겹침 없음(시작 판이 깨끗했으면).
    if startClear, !fuzzClear(fuzzFrames(after)) { bad.append("묶음 겹침/판 밖") }
    // 5) 거절이면 그대로.
    if !accepted, before != after { bad.append("거절했는데 바뀜") }
    // 6) isChanged = !sameTable.
    if after.isChanged == RummyRules.sameTable(after.submissionTable, start.table) { bad.append("isChanged 불일치") }
    guard case .block(let ids, _) = op else {
        if case .set(let set, _) = op {
            checkPreview(set: set)
        }
        return bad
    }
    // 7) R-14 거절.
    if case .block(_, let target) = op, ids.contains(where: tableIDs.contains) {
        switch target {
        case .rack, .rackSlot: if accepted { bad.append("판 출신 랙행을 받아들임") }
        default: break
        }
    }
    // 8) 미리보기 = 실제.
    if let preview {
        if (preview == nil) == accepted { bad.append("미리보기 거절 여부 ≠ 실제") }
        if let preview, accepted { checkLanding(preview, block: ids) }
    }
    // 9) 손대지 않은 타일은 제자리: 블록도 아니고 놓은 묶음에도 없는 판 타일.
    if accepted {
        let landed: Set<Int>
        if let preview, let set = preview?.landing?.set, after.melds.indices.contains(set) {
            landed = Set(after.melds[set].map(\.id))
        } else {
            landed = []
        }
        let was = fuzzSpots(before), now = fuzzSpots(after)
        let moving = Set(ids)
        for (id, spot) in was where !moving.contains(id) && !landed.contains(id) {
            if now[id] != spot { bad.append("손대지 않은 타일 \(id) 이동 \(spot) → \(String(describing: now[id]))"); break }
        }
    }
    return bad
}

private struct FuzzCase: Encodable {
    let id: String
    let initialDone: Bool
    let tableBefore: [[String]]
    let rackBefore: [String]
    let tableAfter: [[String]]
    let valid: Bool
    let reason: String
}

private struct FuzzCorpus: Encodable {
    let meld: [String] = []
    let turn: [FuzzCase]
    let score: [String] = []
}

@Suite("v3 아잉 큐브 편집 — 무작위 시퀀스 퍼즈(보존 · R-14 · 겹침 · 제자리 · 미리보기 · 결정성)")
struct V0369RummyV3FuzzTests {
    @Test("무작위 편집 시퀀스: 모든 단계 불변식 + 같은 시퀀스 다시 돌리면 같은 판 + 되돌리기는 시작 판")
    func randomEditSequences() throws {
        // 없으면: 붙기 연쇄가 곁의 손대지 않은 묶음을 끌어당기거나 · 쪼개기가 타일을 잃거나 · 미리보기가 실제와 다른 결함이 초록이 된다.
        let env = ProcessInfo.processInfo.environment
        let sequences = Int(env["RUMMY_FUZZ_SEQS"] ?? "") ?? 240
        var failures: [String] = []
        var failureCount = 0
        var corpus: [FuzzCase] = []
        var accepted = 0, steps = 0
        for seed in 0..<sequences {
            var r = FuzzRNG(state: UInt64(seed) &* 0x1000_0001 &+ 7)
            let start = fuzzStart(&r)
            let first = start.editor()
            let startIDs = Set((first.melds.flatMap { $0 } + first.rack).map(\.id))
            let tableIDs = Set(first.melds.flatMap { $0 }.map(\.id))
            let startClear = fuzzClear(fuzzFrames(first))
            var editor = first
            var ops: [FuzzOp] = []
            for step in 0..<Int.random(in: 1...16, using: &r) {
                let op = fuzzOp(editor, &r)
                ops.append(op)
                let preview: RummyDropPreview??
                switch op {
                case .block(let ids, let target):
                    let a = editor.previewDrop(ids, to: target)
                    if a != editor.previewDrop(ids, to: target) { failures.append("seed \(seed) step \(step): 미리보기 비결정") }
                    preview = .some(a)
                case .set(let set, let point):
                    preview = .some(editor.previewMoveSet(set, to: point))
                default:
                    preview = nil
                }
                let before = editor
                let ok = fuzzApply(&editor, op)
                steps += 1
                if ok { accepted += 1 }
                let bad = fuzzCheck(before: before, after: editor, op: op, accepted: ok, preview: preview,
                                    start: start, startIDs: startIDs, tableIDs: tableIDs, startClear: startClear)
                if !bad.isEmpty {
                    failureCount += 1
                    if failures.count < 12 {
                        failures.append("seed \(seed) step \(step) op \(op) → \(bad.joined(separator: " · "))\n  before \(before.submissionTable.map { $0.map(\.text) }) @ \(before.points)\n  after  \(editor.submissionTable.map { $0.map(\.text) }) @ \(editor.points)")
                    }
                }
            }
            // 결정성: 같은 시작 · 같은 시퀀스 → 같은 편집기.
            var replay = start.editor()
            for op in ops { _ = fuzzApply(&replay, op) }
            if replay != editor { failureCount += 1; failures.append("seed \(seed): 다시 돌린 결과가 다르다") }
            corpus.append(FuzzCase(
                id: "fuzz-\(seed)", initialDone: start.initialDone,
                tableBefore: start.table.map { $0.map(\.text) }, rackBefore: start.rack.map(\.text),
                tableAfter: editor.submissionTable.map { $0.map(\.text) },
                valid: editor.reason == .ok, reason: editor.reason.rawValue))
            // 되돌리기 = 시작 판 · 시작 배치, 랙 면은 시작 랙.
            var reset = editor
            reset.reset()
            if reset.melds != first.melds || reset.points != first.points || faceBag(reset.rackFaces) != faceBag(start.rack)
                || reset.isChanged || reset.isLayoutChanged {
                failureCount += 1
                failures.append("seed \(seed): 되돌리기가 시작 판이 아니다")
            }
        }
        if let out = env["RUMMY_FUZZ_OUT"] {
            let data = try JSONEncoder().encode(FuzzCorpus(turn: corpus))
            try data.write(to: URL(fileURLWithPath: out))
        }
        print("rummy fuzz: sequences \(sequences) steps \(steps) accepted \(accepted) failures \(failureCount)")
        #expect(failureCount == 0, "\(failures.joined(separator: "\n"))")
        #expect(accepted > steps / 3, "받아들인 단계가 너무 적다 — 퍼즈가 규칙을 못 건드린다")
    }
}

private func vf(_ text: String) -> [RummyFace] { text.split(separator: " ").map { RummyFace(text: String($0))! } }

private func vEditor(_ sets: [String], at points: [RummyPoint], rack: String) -> RummyTurnEditor {
    RummyTurnEditor(table: sets.map(vf), rack: vf(rack), initialDone: true, tableLayout: RummyLayout(points.map { Optional($0) }))
}

private func vTexts(_ e: RummyTurnEditor) -> [String] { e.submissionTable.map { $0.map(\.text).joined(separator: " ") } }

@Suite("v3 아잉 큐브 편집 — 적대 검증에서 찾은 결함(붙기 연쇄 · 자석 자리)")
struct V0369RummyV3VerifyTests {
    @Test("A1-A3 · A4-A6 이 여백 16으로 따로 서 있을 때 A4-A6 오른끝에 A7 을 붙이면 A4-A7 만 — A1-A3 을 끌어와 합치지 않는다")
    func attachDoesNotPullUntouchedNeighbor() {
        // 없으면: 붙은 뒤 합친 묶음의 **대상 쪽 바깥 끝**(손대지 않은 끝)까지 다시 붙기를 봐서, 자동 배치로 16 곁에 서 있던
        // A1-A3 까지 합쳐 A1-A7 이 되고 A4-A6 이 16 왼쪽으로 당겨지는 결함이 초록이 된다(묶음 위에 꽂기 `.meld` 는 안 합친다 — 같은 뜻의 두 놓기가 다른 판).
        let editor = vEditor(["A1 A2 A3", "A4 A5 A6"], at: [RummyPoint(x: 0, y: 0), RummyPoint(x: 136, y: 0)], rack: "A7")
        let a7 = editor.rack[0].id
        var near = editor
        let preview = near.previewDrop([a7], to: .newMeldAt(RummyPoint(x: 260, y: 0)))
        let ok1 = near.moveBlock([a7], to: .newMeldAt(RummyPoint(x: 260, y: 0)))
        #expect(ok1)
        #expect(vTexts(near) == ["A1 A2 A3", "A4 A5 A6 A7"])
        #expect(near.points == [RummyPoint(x: 0, y: 0), RummyPoint(x: 136, y: 0)])
        #expect(preview?.plan == .attach(set: 1, side: .right) && preview?.landing?.set == 1)
        var onto = editor
        let ok2 = onto.moveBlock([a7], to: .meld(1, index: nil))
        #expect(ok2)
        #expect(vTexts(onto) == vTexts(near) && onto.points == near.points, "묶음 위에 놓기와 끝 곁에 놓기가 같은 판")
    }

    @Test("묶음 통째 옮기기도 한 번만 — A7-A9 를 A4-A6 오른끝에 대면 A4-A9, 반대편 A1-A3 은 그대로")
    func moveSetDoesNotCascadeThroughHost() {
        // 없으면: 옮긴 묶음이 대상과 합친 뒤 대상의 반대 끝 곁 묶음까지 합쳐(A1-A9) 손대지 않은 타일이 움직인다.
        var editor = vEditor(["A1 A2 A3", "A4 A5 A6", "A7 A8 A9"],
                             at: [RummyPoint(x: 0, y: 0), RummyPoint(x: 136, y: 0), RummyPoint(x: 0, y: 300)], rack: "B1")
        let ok3 = editor.moveSet(2, to: RummyPoint(x: 262, y: 4))
        #expect(ok3)
        #expect(vTexts(editor) == ["A1 A2 A3", "A4 A5 A6 A7 A8 A9"])
        #expect(editor.points == [RummyPoint(x: 0, y: 0), RummyPoint(x: 136, y: 0)])
    }

    @Test("틈 메우기는 그대로 — 블록의 두 끝이 저마다 한 번씩 붙는다(A1-A3 · A5-A7 사이에 A4)")
    func gapFillStillJoinsBothEnds() {
        // 없으면: 끝마다 한 번만 붙게 고치다 틈 메우기(양쪽 다 붙기)까지 막는 회귀가 초록이 된다.
        var editor = vEditor(["A1 A2 A3", "A5 A6 A7"], at: [RummyPoint(x: 100, y: 200), RummyPoint(x: 260, y: 200)], rack: "A4")
        let ok4 = editor.moveBlock([editor.rack[0].id], to: .newMeldAt(RummyPoint(x: 222, y: 204)))
        #expect(ok4)
        #expect(vTexts(editor) == ["A1 A2 A3 A4 A5 A6 A7"] && editor.points == [RummyPoint(x: 100, y: 200)])
    }

    @Test("자석은 실제 이음 자리에 — 7장 런 가운데(A4)를 빼서 틈에 다시 놓으면 자석 x = A3 오른끝(220), 옮기기 전 묶음 끝(380)이 아니다")
    func magnetSeamOnSplitPiece() {
        // 없으면: 대상이 끌어 온 묶음의 토막일 때 자석이 옮기기 전 묶음 끝(A7 오른끝)에 서서 엉뚱한 곳을 가리키는 결함이 초록이 된다.
        let editor = vEditor(["A1 A2 A3 A4 A5 A6 A7"], at: [RummyPoint(x: 100, y: 200)], rack: "B1")
        let a4 = editor.melds[0][3].id
        let preview = RummyBoardPreview.make(
            editor.previewDrop([a4], to: .newMeldAt(RummyPoint(x: 220, y: 200))), blockCount: 1,
            meldTileIDs: editor.melds.map { $0.map(\.id) }, frames: editor.tableLayout.frames, dragged: [a4])
        #expect(preview?.magnetSeamX == 220)
        // 끝 타일(A7)을 빼서 제자리 곁에 다시 놓기 — 이음 = A6 오른끝(340).
        let a7 = editor.melds[0][6].id
        let back = RummyBoardPreview.make(
            editor.previewDrop([a7], to: .newMeldAt(RummyPoint(x: 346, y: 200))), blockCount: 1,
            meldTileIDs: editor.melds.map { $0.map(\.id) }, frames: editor.tableLayout.frames, dragged: [a7])
        #expect(back?.magnetSeamX == 340)
        // 왼끝(A1)을 빼서 왼쪽 곁에 — 이음 = A2 왼끝(140).
        let a1 = editor.melds[0][0].id
        let left = RummyBoardPreview.make(
            editor.previewDrop([a1], to: .newMeldAt(RummyPoint(x: 96, y: 200))), blockCount: 1,
            meldTileIDs: editor.melds.map { $0.map(\.id) }, frames: editor.tableLayout.frames, dragged: [a1])
        #expect(left?.magnetSeamX == 140)
    }
}

@Suite("v3 아잉 큐브 편집 — 첫 등록 전 자동 붙기(R-12)")
struct V0369RummyV3InitialAttachTests {
    private func editor(_ sets: [String], at points: [RummyPoint], rack: String, initialDone: Bool) -> RummyTurnEditor {
        RummyTurnEditor(table: sets.map(vf), rack: vf(rack), initialDone: initialDone,
                        tableLayout: RummyLayout(points.map { Optional($0) }))
    }

    @Test("첫 등록 전: 판 묶음 A1-A3 오른끝 곁에 내 A4-A6 을 놓아도 안 붙는다(새 묶음) — 붙으면 initial_table_touched 로 막힌다 · 등록 뒤엔 붙는다")
    func newSetDoesNotJoinTableSetBeforeInitial() {
        // 없으면: 첫 등록 전에 곁에 놓은 내 새 묶음이 판 묶음에 저절로 합쳐져 [완료]가 '판 묶음을 건드렸다'로 막히는 결함이 초록이 된다.
        for initialDone in [false, true] {
            var e = editor(["A1 A2 A3"], at: [RummyPoint(x: 0, y: 0)], rack: "A4 A5 A6 B9", initialDone: initialDone)
            let ids = e.rack.prefix(3).map(\.id)
            let preview = e.previewDrop(ids, to: .newMeldAt(RummyPoint(x: 126, y: 2)))
            let ok = e.moveBlock(ids, to: .newMeldAt(RummyPoint(x: 126, y: 2)))
            #expect(ok)
            if initialDone {
                #expect(vTexts(e) == ["A1 A2 A3 A4 A5 A6"])
                #expect(preview?.plan == .attach(set: 0, side: .right))
            } else {
                #expect(vTexts(e) == ["A1 A2 A3", "A4 A5 A6"])
                if case .newSet = preview?.plan {} else { Issue.record("첫 등록 전 미리보기가 붙기다: \(String(describing: preview?.plan))") }
                #expect(e.reason != .initialTableTouched)
                #expect(e.points[1].x >= 120 + RummyTableLayout.clearance, "새 묶음이 판 묶음과 겹친다")
            }
        }
    }

    @Test("첫 등록 전: 판 묶음을 위치만 옮기다 곁의 판 묶음에 대도 안 합친다(isChanged 거짓) · 내 새 묶음끼리는 붙는다")
    func tableSetsDoNotMergeBeforeInitialButOwnSetsDo() {
        // 없으면: 첫 등록 전 판 정리(위치 옮기기)가 판 묶음 둘을 합쳐 낼 수 없는 판이 되는 결함이 초록이 된다.
        var e = editor(["A1 A2 A3", "A4 A5 A6"], at: [RummyPoint(x: 0, y: 0), RummyPoint(x: 0, y: 300)],
                       rack: "B4 B5 B6 B7 B8 B9", initialDone: false)
        let moved = e.moveSet(1, to: RummyPoint(x: 124, y: 0))
        #expect(moved)
        #expect(vTexts(e) == ["A1 A2 A3", "A4 A5 A6"] && !e.isChanged)
        // 내 새 묶음끼리(판 타일 없음)는 첫 등록 전에도 붙는다 → B4-B9 = 39점 → 낼 수 있다.
        let b = e.rack.map(\.id)
        let first = e.moveBlock(Array(b.prefix(3)), to: .newMeldAt(RummyPoint(x: 0, y: 400)))
        let second = e.moveBlock(Array(b.suffix(3)), to: .newMeldAt(RummyPoint(x: 124, y: 400)))
        #expect(first && second)
        #expect(vTexts(e).last == "B4 B5 B6 B7 B8 B9" && e.canSubmit)
    }
}
