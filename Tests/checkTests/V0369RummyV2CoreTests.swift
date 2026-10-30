import Foundation
import Testing
@testable import CheckCore

// 아잉 큐브 2판 코어(설계서 v2 §2 — 레인 K): 판 자유 배치 · 받침대 반 칸 배치 · 묶음째 옮기기 · 와이어 v2 · 스토어 v2.
//
// **픽스처**: `Fixtures/rummy/server/*.json` — 레인 S 가 재생 하네스의 v2 서버(`20261104120000_rummy_v2.sql`)에서 실제 RPC 를
// 불러 뜬 실출력이다(2026-10-30 통합 갈래가 레인 K 의 손 합성 `v2-synth` 를 이것으로 갈아 끼웠다). 값 전수 왕복은
// V0369RummyWireContractTests 가 50장 모두에 대해 잰다 — 여기서는 v2 장면 7장의 뜻을 잰다.
//
// 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가" 다(관례).

private func v2f(_ text: String) -> [RummyFace] {
    text.split(separator: " ").compactMap { RummyFace(text: String($0)) }
}

private func v2p(_ x: Int, _ y: Int) -> RummyPoint { RummyPoint(x: x, y: y) }

private let v2FixtureFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/rummy/server", isDirectory: true)

private func v2Decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: data)
}

private func v2Fixture(_ name: String) throws -> Data {
    try Data(contentsOf: v2FixtureFolder.appendingPathComponent("\(name).json"))
}

/// 모든 묶음 쌍이 여백 밖이고 캔버스 안인가.
private func v2Disjoint(_ layout: RummyTableLayout, indices: [Int]? = nil) -> Bool {
    let frames = layout.frames
    let picked = indices ?? Array(frames.indices)
    for a in picked {
        guard RummyTableLayout.fits(frames[a]) else { return false }
        for b in picked where b > a {
            if RummyTableLayout.overlaps(frames[a], frames[b]) { return false }
        }
    }
    return true
}

private func v2RackID(_ editor: RummyTurnEditor, _ text: String, nth: Int = 0) -> Int {
    editor.rack.filter { $0.face.text == text }[nth].id
}

// MARK: - 판 배치

@Suite("v2 아잉 큐브 코어 — 판 자유 배치(RummyTableLayout)")
struct V0369RummyV2TableLayoutTests {
    @Test("와이어 배치: 범위 밖·모양 틀린 칸만 nil, 배열이 아니면 빈 목록 — 디코드가 throw 하지 않는다 · 인코드는 [x,y]|null")
    func layoutWireIsLenient() throws {
        // 없으면: 서버가 한 칸이라도 이상한 값을 실으면 state 디코드가 통째로 throw 해 창이 죽는 결함이 초록이 된다.
        let raw = #"{"a":[[0,0],[1000,640],[1001,3],[5,-1],[1.5,2],[1,2,3],null,"x",[12,30]],"b":"oops","c":null}"#
        struct Box: Decodable { let a: RummyLayout; let b: RummyLayout; let c: RummyLayout? }
        let box = try JSONDecoder().decode(Box.self, from: Data(raw.utf8))
        #expect(box.a.points == [v2p(0, 0), v2p(1000, 640), nil, nil, nil, nil, nil, nil, v2p(12, 30)])
        #expect(box.b.points.isEmpty)
        #expect(box.c == nil)
        let encoded = String(decoding: try JSONEncoder().encode(RummyLayout([v2p(8, 16), nil])), as: UTF8.self)
        #expect(encoded == "[[8,16],null]")
        // 길이가 묶음 수와 다르면 전부 nil(서버 정리 규칙).
        #expect(RummyTableLayout.sanitize(RummyLayout([v2p(1, 1)]), setCount: 2) == [nil, nil])
        #expect(RummyTableLayout.sanitize(nil, setCount: 1) == [nil])
    }

    @Test("자동 배치: 주어진 점은 그대로, 빈 자리는 행 우선 첫 빈자리 · 겹침 없음 · 캔버스 안 · 8 단위 격자")
    func placeFillsNullsRowMajor() {
        // 없으면: 배치 없는 v1 판(table_layout null)이 전부 (0,0) 에 포개져 그려지는 결함이 초록이 된다.
        let sets = [v2f("A1 A2 A3"), v2f("B5 C5 D5"), v2f("A7 A8 A9 A10")]
        let all = RummyTableLayout(sets: sets, layout: nil)
        #expect(v2Disjoint(all))
        #expect(all.points.allSatisfy { $0.x % RummyTableLayout.grid == 0 && $0.y % RummyTableLayout.grid == 0 })
        // 첫 줄(y=0)에 셋 다 들어간다(긴 것 먼저: 4장 → 3장 둘).
        #expect(all.points.allSatisfy { $0.y == 0 })
        #expect(all.points[2] == v2p(0, 0))
        // 주어진 점은 겹쳐도 그대로 둔다(남이 놓은 자리).
        let given = RummyTableLayout(sets: sets, layout: RummyLayout([v2p(500, 300), v2p(500, 300), nil]))
        #expect(given.points[0] == v2p(500, 300) && given.points[1] == v2p(500, 300))
        #expect(given.points[2] == v2p(0, 0))
        // 주어진 묶음을 피해 간다.
        let blocked = RummyTableLayout(sets: sets, layout: RummyLayout([v2p(0, 0), nil, nil]))
        #expect(v2Disjoint(blocked))
        #expect(blocked.points[0] == v2p(0, 0))
    }

    @Test("자동 배치 결정성: 같은 입력 → 같은 출력, 묶음 순서를 섞어도 각 묶음이 받는 자리는 같다")
    func placeIsDeterministicAndOrderFree() {
        // 없으면: 기기마다(또는 순서가 바뀐 응답마다) 빈 자리 채우기가 달라 남의 판이 사람마다 다르게 보이는 결함이 초록이 된다.
        let sets = [v2f("A1 A2 A3"), v2f("B5 C5 D5"), v2f("C9 C10 C11 C12 C13"), v2f("J D4 D5"), v2f("A11 B11 C11 D11"),
                    v2f("B1 B2 B3"), v2f("D7 D8 D9")]
        let layout = RummyLayout([nil, v2p(400, 120), nil, nil, nil, v2p(40, 400), nil])
        let first = RummyTableLayout.place(sets: sets, layout: layout)
        #expect(first == RummyTableLayout.place(sets: sets, layout: layout))
        let table = RummyTableLayout(counts: sets.map(\.count), points: first)
        #expect(v2Disjoint(table))
        var bySet: [[RummyFace]: RummyPoint] = [:]
        for (set, point) in zip(sets, first) { bySet[set] = point }
        // 여러 순열에서 묶음 → 자리 대응이 같다.
        let permutations: [[Int]] = [[6, 5, 4, 3, 2, 1, 0], [3, 0, 6, 1, 5, 2, 4], [1, 2, 3, 4, 5, 6, 0]]
        for order in permutations {
            let shuffledSets = order.map { sets[$0] }
            let shuffledLayout = RummyLayout(order.map { layout.points[$0] })
            let placed = RummyTableLayout.place(sets: shuffledSets, layout: shuffledLayout)
            for (set, point) in zip(shuffledSets, placed) {
                #expect(bySet[set] == point, "\(set) 자리가 순서에 따라 바뀐다")
            }
        }
    }

    @Test("판이 꽉 차도 자동 배치는 캔버스 밖으로 안 나가고, 많은 묶음도 겹치지 않게 채운다")
    func placeManySets() {
        // 없으면: 묶음이 많은 판에서 자동 배치가 캔버스 밖(화면 밖)으로 밀려나는 결함이 초록이 된다.
        let sets = (0..<30).map { index in v2f("A\(index % 11 + 1) A\(index % 11 + 2) A\(index % 11 + 3)") }
        let table = RummyTableLayout(sets: sets, layout: nil)
        #expect(v2Disjoint(table))
        let crowded = (0..<200).map { _ in v2f("J J A1 A2 A3 A4 A5 A6 A7 A8 A9 A10 A11") }
        let full = RummyTableLayout(sets: crowded, layout: nil)
        #expect(full.frames.allSatisfy(RummyTableLayout.fits))
    }

    @Test("놓기 스냅: 빈 곳이면 그 격자점, 막혔으면 가장 가까운 빈 격자점 · 자기 자신은 장애물에서 뺀다")
    func snapFindsNearestFreeSpot() {
        // 없으면: 묶음을 다른 묶음 위에 놓아 포개지는(또는 엉뚱한 구석으로 튀는) 결함이 초록이 된다.
        let table = RummyTableLayout(counts: [3, 3], points: [v2p(200, 200), v2p(600, 400)])
        #expect(table.snap(v2p(41, 47), tiles: 3) == v2p(40, 48))
        let snapped = table.snap(v2p(210, 210), tiles: 3)
        let frame = RummyTableLayout.frame(at: snapped, tiles: 3)
        #expect(!RummyTableLayout.overlaps(frame, table.frame(of: 0)!))
        #expect(!RummyTableLayout.overlaps(frame, table.frame(of: 1)!))
        // 가장 가깝다: 막힌 묶음(200,200,120×56)을 여백째 피하는 줄은 위 y ≤ 128 · 아래 y ≥ 272 — 아래(Δy 62)가 위(Δy 82)보다 가깝다.
        #expect(snapped == v2p(208, 272))
        // 자기 자신을 옮기면 제자리 근처가 그대로 빈 곳이다.
        #expect(table.snap(v2p(208, 200), tiles: 3, excluding: 0) == v2p(208, 200))
        // 캔버스 밖을 겨냥해도 안으로.
        let edge = table.snap(v2p(990, 630), tiles: 3)
        #expect(RummyTableLayout.fits(RummyTableLayout.frame(at: edge, tiles: 3)))
    }

    @Test("길이 변화: 오른쪽으로 늘어나다 막히면 가장 가까운 빈자리로 · 줄면 그대로")
    func refitGrowsRightThenMoves() {
        // 없으면: 세트에 타일을 붙여 오른쪽 이웃 묶음을 덮는 결함이 초록이 된다.
        let neighbour = RummyTableLayout.frame(at: v2p(200, 0), tiles: 3)
        #expect(RummyTableLayout.refit(v2p(0, 0), tiles: 4, among: [neighbour]) == v2p(0, 0))   // 160+16 ≤ 200
        let moved = RummyTableLayout.refit(v2p(0, 0), tiles: 5, among: [neighbour])            // 200 > 200−16 → 막힘
        #expect(moved != v2p(0, 0))
        #expect(!RummyTableLayout.overlaps(RummyTableLayout.frame(at: moved, tiles: 5), neighbour))
        #expect(RummyTableLayout.refit(v2p(0, 0), tiles: 2, among: [neighbour]) == v2p(0, 0))
        // 오른쪽 캔버스 끝에서 늘어나면 안으로 들어온다.
        let atEdge = RummyTableLayout.refit(v2p(880, 0), tiles: 4, among: [])
        #expect(RummyTableLayout.fits(RummyTableLayout.frame(at: atEdge, tiles: 4)))
    }
}

// MARK: - 받침대 · 편집기

@Suite("v2 아잉 큐브 코어 — 받침대 배치 · 묶음째 옮기기(편집기)")
struct V0369RummyV2EditorTests {
    @Test("isChainable: 런·그룹의 일부(조커 와일드·1장 참) · 8▲8▲ 은 안 이어진다 · 내림차순은 런 아님")
    func chainableFaces() {
        // 없으면: 길게 눌러 집기가 같은 면 두 장(8▲8▲)이나 뒤섞인 타일까지 한 덩어리로 집는 결함이 초록이 된다.
        #expect(RummyRules.isChainable(v2f("A5")))
        #expect(!RummyRules.isChainable([]))
        #expect(RummyRules.isChainable(v2f("A5 A6")))
        #expect(RummyRules.isChainable(v2f("A5 J A7")))
        #expect(RummyRules.isChainable(v2f("A5 B5 J")))
        #expect(!RummyRules.isChainable(v2f("A8 A8")))
        #expect(!RummyRules.isChainable(v2f("A7 A6")))
        #expect(!RummyRules.isChainable(v2f("A5 B6")))
        #expect(!RummyRules.isChainable(v2f("A12 A13 J")))       // 14 는 없다
        #expect(RummyRules.isChainable(v2f("J A12 A13")))
        #expect(!RummyRules.isChainable(v2f("A5 B5 C5 D5 J")))   // 그룹은 4장까지, 런도 아님
    }

    @Test("정렬 777·789: 조합 단위로 끊고 단위 사이 반 칸, 낱장끼리도 반 칸 · 화면 순서는 v1 과 같다")
    func sortGroupsWithHalfGaps() {
        // 없으면: 정렬이 서로 다른 조합까지 한 줄로 쫙 붙여(요구 8) 조합 경계가 안 보이는 결함이 초록이 된다.
        var editor = RummyTurnEditor(table: [], rack: v2f("B8 A7 C9 J A9 B7 A7"), initialDone: true)
        editor.sortRack(.number)
        #expect(editor.rackFaces == v2f("A7 A7 B7 B8 A9 C9 J"))
        let slots = editor.rack.map { editor.rackLayout.slot(of: $0.id)!.halfCol }
        // [A7 A7 B7] _ [B8] _ [A9 C9] _ [J]
        #expect(slots == [0, 2, 4, 7, 10, 12, 15])
        editor.sortRack(.color)
        #expect(editor.rackFaces == v2f("A7 A7 A9 B7 B8 C9 J"))
        let colorSlots = editor.rack.map { editor.rackLayout.slot(of: $0.id)!.halfCol }
        // [A7] _ [A7] _ [A9] _ [B7 B8] _ [C9] _ [J]
        #expect(colorSlots == [0, 3, 6, 9, 11, 14, 17])
        let units = RummyRackLayout.sortUnits(editor.rack, by: .color).map { $0.map(\.face.text) }
        #expect(units == [["A7"], ["A7"], ["A9"], ["B7", "B8"], ["C9"], ["J"]])
    }

    @Test("정렬: 단위가 줄 끝에 안 들어가면 통째로 다음 줄 · 줄이 넘치면 3번째 줄")
    func sortWrapsUnitsToNextRow() {
        // 없으면: 조합 하나가 두 줄로 쪼개져 보이거나 타일이 받침대 밖으로 나가는 결함이 초록이 된다.
        let faces = (1...13).map { "A\($0)" } + (1...13).map { "B\($0)" } + (1...13).map { "C\($0)" }
        var editor = RummyTurnEditor(table: [], rack: v2f(faces.joined(separator: " ")), initialDone: true)
        editor.sortRack(.color)
        for tile in editor.rack {
            let slot = editor.rackLayout.slot(of: tile.id)!
            #expect(slot.halfCol + RummyRackLayout.tileSpan <= RummyRackLayout.halfColumnsPerRow)
            // 색마다 한 줄(13장 = 26 반 칸, 둘째 색은 26+1+26 > 32 → 다음 줄).
            #expect(slot.row == tile.face.color!)
        }
        #expect(editor.rackLayout.rowCount == 3)
    }

    @Test("rackChain: 딱 붙은 이웃만, 조커 가운데 · 반 칸 빈칸·줄 바뀜에서 끊김 · 8▲8▲ 안 이어짐")
    func rackChainRules() {
        // 없으면: 길게 눌러 집기가 반 칸 떨어진 다른 조합이나 다음 줄 타일까지 집는 결함이 초록이 된다.
        var editor = RummyTurnEditor(table: [], rack: v2f("A5 J A7 B9 B9 C3"), initialDone: true)
        // 빈칸 없이: A5 J A7 B9 B9 C3 (반 칸 0,2,4,6,8,10)
        let a5 = v2RackID(editor, "A5"), joker = v2RackID(editor, "J"), a7 = v2RackID(editor, "A7")
        #expect(editor.rackChain(around: joker) == [a5, joker, a7])
        #expect(editor.rackChain(around: a5) == [a5, joker, a7])
        let b9a = v2RackID(editor, "B9"), b9b = v2RackID(editor, "B9", nth: 1)
        #expect(editor.rackChain(around: b9a) == [b9a])          // A7 B9 안 이어짐, B9 B9 안 이어짐
        #expect(editor.rackChain(around: b9b) == [b9b])
        #expect(editor.rackChain(around: 999).isEmpty)
        // 반 칸 띄우면 끊긴다: J(2..4) 뒤 반 칸 띄운 5 에 A7.
        var spaced = RummyTurnEditor(table: [], rack: v2f("A5 J A7"), initialDone: true)
        let s5 = v2RackID(spaced, "A5"), sj = v2RackID(spaced, "J"), s7 = v2RackID(spaced, "A7")
        let moved1 = spaced.moveBlock([s7], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 5)))
        #expect(moved1)
        #expect(spaced.rackLayout.slot(of: s7) == RummyRackSlot(row: 0, halfCol: 5))
        #expect(spaced.rackChain(around: s5) == [s5, sj])
        #expect(spaced.rackChain(around: s7) == [s7])
        // 줄이 바뀌면 끊긴다(다음 줄 첫 자리는 윗줄 끝과 이웃이 아니다).
        let moved2 = spaced.moveBlock([s5, sj], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 28)))
        #expect(moved2)
        let moved3 = spaced.moveBlock([s7], to: .rackSlot(RummyRackSlot(row: 1, halfCol: 0)))
        #expect(moved3)
        #expect(spaced.rackChain(around: sj) == [s5, sj])
        #expect(spaced.rackChain(around: s7) == [s7])
    }

    @Test("moveBlock([x]) ≡ move(x) — 모든 타일 × 모든 놓을 곳(랙 슬롯·세트 슬롯·새 세트·새 자리)")
    func singleBlockEqualsMove() {
        // 없으면: 묶음 옮기기와 한 장 옮기기가 다른 규칙으로 갈라져, 같은 손짓이 한 장일 때와 여럿일 때 결과가 달라지는 결함이 초록이 된다.
        let base = RummyTurnEditor(
            table: [v2f("A1 A2 A3"), v2f("B7 C7 D7")], rack: v2f("A4 B10 C10 D10 J"), initialDone: true)
        var targets: [RummyDropTarget] = [.rack(index: nil), .newMeld, .newMeldAt(v2p(400, 300)),
                                         .rackSlot(RummyRackSlot(row: 1, halfCol: 3)), .meld(5, index: nil)]
        for slot in [nil, 0, 1, 2, 3, 9] as [Int?] {
            targets.append(.rack(index: slot))
            targets.append(.meld(0, index: slot))
            targets.append(.meld(1, index: slot))
        }
        let ids = base.melds.flatMap { $0 }.map(\.id) + base.rack.map(\.id) + [77]
        for id in ids {
            for target in targets {
                var single = base, block = base
                let a = single.move(id, to: target)
                let b = block.moveBlock([id], to: target)
                #expect(a == b && single == block, "tile \(id) → \(target)")
            }
        }
    }

    @Test("moveBlock: 전부 아니면 전무 — 판 출신 섞인 랙행(R-14)·중복·모르는 id·빈 목록·없는 세트는 거절하고 아무것도 안 바꾼다")
    func moveBlockIsAllOrNothing() {
        // 없으면: 판 타일이 섞인 묶음을 랙으로 놓을 때 랙 타일만 넘어가고 판 타일이 남는(반쪽 이동) 결함이 초록이 된다.
        let base = RummyTurnEditor(table: [v2f("A1 A2 A3")], rack: v2f("A4 A5 B9"), initialDone: true)
        var editor = base
        let a4 = v2RackID(editor, "A4"), a5 = v2RackID(editor, "A5")
        let moved4 = editor.moveBlock([a4, a5], to: .meld(0, index: nil))
        #expect(moved4)
        let mixed = editor.meldPick(for: editor.melds[0][1].id, fromTileToEnd: true)
        #expect(mixed.count == 4)
        let before = editor
        #expect(!editor.canMoveBlock(mixed, to: .rack(index: nil)))
        let moved5 = editor.moveBlock(mixed, to: .rack(index: nil))
        #expect(!moved5)
        let moved6 = editor.moveBlock(mixed, to: .rackSlot(RummyRackSlot(row: 1, halfCol: 0)))
        #expect(!moved6)
        let moved7 = editor.moveBlock([a4, a4], to: .newMeld)
        #expect(!moved7)
        let moved8 = editor.moveBlock([a4, 999], to: .newMeld)
        #expect(!moved8)
        let moved9 = editor.moveBlock([], to: .newMeld)
        #expect(!moved9)
        let moved10 = editor.moveBlock([a4], to: .meld(3, index: nil))
        #expect(!moved10)
        #expect(editor == before)
        // 이번 차례에 낸 것만 고르면 랙으로 돌아온다.
        let moved11 = editor.moveBlock([a4, a5], to: .rack(index: nil))
        #expect(moved11)
        #expect(editor.submissionTable == [v2f("A1 A2 A3")])
    }

    @Test("moveBlock: 세트 슬롯은 옮기기 전 화면 기준 — 같은 세트 안에선 앞쪽 집힌 장수만큼 당긴다 · 새 세트는 넘긴 순서")
    func moveBlockSlotsUsePreRemovalIndices() {
        // 없으면: 세트 안에서 묶음을 뒤로 옮길 때 한 칸씩 밀려 엉뚱한 자리에 꽂히는 결함이 초록이 된다.
        var editor = RummyTurnEditor(table: [v2f("A1 A2 A3 A4 A5 A6")], rack: [], initialDone: true)
        let ids = editor.melds[0].map(\.id)
        // [A1 A2] 를 A5 앞(슬롯 4)으로 → A3 A4 A1 A2 A5 A6.
        let moved12 = editor.moveBlock([ids[0], ids[1]], to: .meld(0, index: 4))
        #expect(moved12)
        #expect(editor.submissionTable == [v2f("A3 A4 A1 A2 A5 A6")])
        // 런 쪼개기: A5 부터 끝까지를 새 세트로(⌥ 집기).
        let pick = editor.meldPick(for: ids[4], fromTileToEnd: true)
        #expect(pick == [ids[4], ids[5]])
        let moved13 = editor.moveBlock(pick, to: .newMeldAt(v2p(500, 400)))
        #expect(moved13)
        #expect(editor.submissionTable == [v2f("A3 A4 A1 A2"), v2f("A5 A6")])
        #expect(editor.points[1] == v2p(496, 400))   // 500 은 격자 496·504 의 한가운데 — 같으면 왼쪽
        #expect(v2Disjoint(editor.tableLayout))
        #expect(editor.screenOrder(Set([ids[5], ids[0], 4242]))  == [ids[0], ids[5]])
    }

    @Test("reset: 묶음째 판으로 낸 뒤 되돌리면 받침대 자리·순서·판·배치가 시작 그대로(나간 자리로 돌아온다)")
    func resetRestoresAfterBlockMoves() {
        // 없으면: 묶음 옮기기 뒤 되돌리기가 타일을 엉뚱한 자리(끝)로 돌려 랙 배치가 흐트러지는 결함이 초록이 된다.
        var editor = RummyTurnEditor(table: [v2f("D1 D2 D3")], rack: v2f("A9 A10 A11 B4 C4 J"), initialDone: true)
        editor.sortRack(.color)
        let sorted = editor
        let block = editor.rackChain(around: v2RackID(editor, "A10"))
        #expect(block.count == 3)
        let moved14 = editor.moveBlock(block, to: .newMeldAt(v2p(300, 300)))
        #expect(moved14)
        let moved15 = editor.moveSet(0, to: v2p(600, 500))
        #expect(moved15)
        let moved16 = editor.moveBlock([v2RackID(editor, "J")], to: .meld(1, index: 0))
        #expect(moved16)
        editor.reset()
        #expect(editor == sorted)
        // 다른 랙 타일을 옮긴 뒤엔 그 자리는 유지(지금 자리 유지)하고 나간 것만 돌아온다.
        let b4 = v2RackID(editor, "B4")
        let a9 = v2RackID(editor, "A9")
        let moved17 = editor.moveBlock([a9], to: .newMeld)
        #expect(moved17)
        let moved18 = editor.moveBlock([b4], to: .rackSlot(RummyRackSlot(row: 1, halfCol: 10)))
        #expect(moved18)
        editor.reset()
        #expect(editor.rackLayout.slot(of: b4) == RummyRackSlot(row: 1, halfCol: 10))
        #expect(editor.rackLayout.slot(of: a9) == sorted.rackLayout.slot(of: a9))
        #expect(editor.submissionTable == [v2f("D1 D2 D3")] && editor.points == sorted.points)
    }

    @Test("받침대: 겹침 금지(가장 가까운 빈자리) · 빈칸 허용 · 새 타일은 마지막 빈자리 · 저장 자리로 복원")
    func rackSlotsAndRestore() {
        // 없으면: 타일 두 장이 한 자리에 포개지거나, 다음 차례에 받침대 배치가 처음 순서로 돌아가는 결함이 초록이 된다.
        var editor = RummyTurnEditor(table: [], rack: v2f("A1 A2 A3"), initialDone: true)
        let a1 = v2RackID(editor, "A1"), a3 = v2RackID(editor, "A3")
        let moved19 = editor.moveBlock([a3], to: .rackSlot(RummyRackSlot(row: 1, halfCol: 9)))
        #expect(moved19)
        let moved101 = editor.moveBlock([a1], to: .rackSlot(RummyRackSlot(row: 1, halfCol: 10)))   // a3(9..11) 와 겹침
        #expect(moved101)
        let s1 = editor.rackLayout.slot(of: a1)!, s3 = editor.rackLayout.slot(of: a3)!
        #expect(s1.row == 1 && abs(s1.halfCol - s3.halfCol) >= 2)
        #expect(s1 == RummyRackSlot(row: 1, halfCol: 11))
        #expect(editor.rackFaces == v2f("A2 A3 A1"))
        // 다음 차례: 저장 자리 + 새로 받은 B5 는 마지막 빈자리(화면 순 마지막 타일 바로 뒤).
        let entries = editor.rackEntries
        let next = RummyTurnEditor(table: [], rack: v2f("B5 A1 A2 A3"), initialDone: true, rackEntries: entries)
        #expect(next.rackEntries.prefix(3).map(\.slot) == entries.map(\.slot))
        let b5 = next.rack.first { $0.face.text == "B5" }!
        #expect(next.rackLayout.slot(of: b5.id) == RummyRackSlot(row: 1, halfCol: 13))
        #expect(next.rack.last == b5)
    }

    @Test("판 배치: 시작 배치는 table_layout(빈 자리 자동) · 세트에 붙이면 늘어나다 막히면 옮김 · moveSet 은 내용 무관")
    func editorCarriesTableLayout() {
        // 없으면: 편집기가 배치를 버려 작업 판이 서버 배치와 어긋나거나, 붙인 타일이 이웃 묶음을 덮는 결함이 초록이 된다.
        var editor = RummyTurnEditor(
            table: [v2f("A1 A2 A3"), v2f("B7 C7 D7")], rack: v2f("A4 A5 A6"), initialDone: true,
            tableLayout: RummyLayout([v2p(0, 0), v2p(200, 0)]))
        #expect(editor.points == [v2p(0, 0), v2p(200, 0)])
        #expect(editor.submissionLayout == RummyLayout([v2p(0, 0), v2p(200, 0)]))
        let moved102 = editor.moveBlock([v2RackID(editor, "A4")], to: .meld(0, index: nil))   // 4장 = 160, 160+16 ≤ 200 → 그대로
        #expect(moved102)
        #expect(editor.points[0] == v2p(0, 0))
        let moved103 = editor.moveBlock([v2RackID(editor, "A5")], to: .meld(0, index: nil))   // 5장 = 200 → 막힘
        #expect(moved103)
        #expect(editor.points[0] != v2p(0, 0))
        #expect(v2Disjoint(editor.tableLayout))
        let reason = editor.reason
        let moved20 = editor.moveSet(1, to: v2p(640, 480))
        #expect(moved20)
        #expect(editor.points[1] == v2p(640, 480) && editor.reason == reason)
        let moved21 = editor.moveSet(7, to: v2p(0, 0))
        #expect(!moved21)
        // 내용 그대로 배치만 바꾼 것도 '배치 바뀜'이다(판정은 안 바뀜).
        var layoutOnly = RummyTurnEditor(table: [v2f("A1 A2 A3")], rack: [], initialDone: true)
        #expect(!layoutOnly.isLayoutChanged)
        layoutOnly.moveSet(0, to: v2p(400, 400))
        #expect(layoutOnly.isLayoutChanged && !layoutOnly.isChanged)
    }
}

// MARK: - 와이어 v2 픽스처

@Suite("v2 아잉 큐브 코어 — v2 서버 실출력 디코드")
struct V0369RummyV2WireTests {
    @Test("state_with_layout: table_layout 실값 디코드 · 캔버스를 넘는 칸([999,640])은 안으로 당긴다 · 반응 없음")
    func stateWithLayoutDecodes() throws {
        // 없으면: v2 필드 이름(snake_case)이 어긋나 배치가 조용히 nil 로 접히거나, 서버가 통과시킨 캔버스 밖 칸이 판 밖에 그려진다.
        let response = try v2Decode(RummyActionResponse.self, try v2Fixture("state_with_layout"))
        let state = try #require(response.state)
        #expect(state.table?.count == 2)
        #expect(state.tableLayout?.points == [v2p(10, 20), v2p(999, 640)], "서버 정리 범위(0…1000·0…640) 안이라 둘 다 읽힌다")
        #expect(state.reactions?.isEmpty == true)
        let layout = RummyTableLayout(sets: state.table ?? [], layout: state.tableLayout)
        #expect(layout.points[0] == v2p(10, 20), "들어가는 칸은 받은 자리 그대로")
        #expect(layout.points[1] == v2p(1000 - 3 * 40, 640 - 56), "넘치는 묶음은 오른쪽·아래 끝에 붙는다 — \(layout.points)")
        #expect(v2Disjoint(layout), "당긴 뒤 판 안 · 안 겹침 — \(layout.points)")
        // 같은 입력이면 어느 기기든 같은 답(배치 결정성).
        #expect(RummyTableLayout(sets: state.table ?? [], layout: state.tableLayout).points == layout.points)
    }

    @Test("draft_with_layout · state_forfeit_disconnected · state_with_reactions · react_ok · react_too_fast · heartbeat_ok 디코드")
    func otherScenesDecode() throws {
        // 없으면: too_fast 가 unknown 으로 접히거나 draft.layout · 끊김 기권 · 반응 목록을 못 읽는 결함이 초록이 된다.
        let draft = try #require(try v2Decode(RummyActionResponse.self, try v2Fixture("draft_with_layout")).state)
        #expect(draft.draft?.layout?.points == [v2p(100, 200)])
        #expect(draft.draft?.table?.count == 1)
        #expect(draft.tableLayout == nil, "빈 판의 table_layout 은 null")
        let forfeit = try #require(try v2Decode(RummyActionResponse.self, try v2Fixture("state_forfeit_disconnected")).state)
        #expect(forfeit.lastEvent?.kind == "forfeit" && forfeit.lastEvent?.seatNo == 1)
        #expect(forfeit.seats?.first { $0.seatNo == 1 }?.state == .forfeit)
        #expect(forfeit.status == .active, "셋 중 하나가 끊겨도 판은 이어진다")
        #expect(forfeit.tableLayout?.points.count == forfeit.table?.count)
        let reacted = try #require(try v2Decode(RummyActionResponse.self, try v2Fixture("state_with_reactions")).state)
        let reactions = try #require(reacted.reactions)
        #expect(reactions.count == 12, "최대 12개")
        #expect(reactions.allSatisfy { $0.sticker != nil }, "서버 키 집합 = AingSticker rawValue")
        #expect(zip(reactions, reactions.dropFirst()).allSatisfy { ($0.atMs ?? 0) >= ($1.atMs ?? 0) }, "최신 순")
        #expect(reactions.first?.sticker == .surprised && reactions.first?.seatNo == 2)
        #expect(try v2Decode(RummyActionResponse.self, try v2Fixture("react_ok")).status == .ok)
        #expect(try v2Decode(RummyActionResponse.self, try v2Fixture("react_too_fast")).status == .tooFast)
        let beat = try v2Decode(RummyActionResponse.self, try v2Fixture("heartbeat_ok"))
        #expect(beat.status == .ok && (beat.serverNowMs ?? 0) > 0)
    }

    @Test("요청 본문: p_layout 은 있으면 [[x,y]], 없으면 키가 없다(v1 키 집합) · react 는 p_key · 새 RPC 이름")
    func requestBodies() throws {
        // 없으면: p_layout: null 이 늘 실려 v1 서버에서 함수를 못 찾거나(PGRST202) 배치가 안 실리는 결함이 초록이 된다.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let id = UUID(uuidString: "7E7E0000-0000-4000-8000-000000000068")!
        let plain = try JSONSerialization.jsonObject(
            with: encoder.encode(RummyTableRequest(matchID: id, expectedSeq: 3, table: [v2f("A1 A2 A3")]))) as! [String: Any]
        #expect(Set(plain.keys) == ["p_protocol", "p_match_id", "p_expected_seq", "p_table"])
        let withLayout = try JSONSerialization.jsonObject(
            with: encoder.encode(RummyTableRequest(
                matchID: id, expectedSeq: 3, table: [v2f("A1 A2 A3")], layout: RummyLayout([v2p(8, 16)])))) as! [String: Any]
        #expect(withLayout["p_layout"] as? [[Int]] == [[8, 16]])
        let react = try JSONSerialization.jsonObject(
            with: encoder.encode(RummyReactRequest(matchID: id, key: AingSticker.joy.rawValue))) as! [String: Any]
        #expect(Set(react.keys) == ["p_protocol", "p_match_id", "p_key"] && react["p_key"] as? String == "joy")
        #expect(RummyWire.RPC.v2Added == ["rummy_heartbeat", "rummy_react"])
        #expect(RummyWire.RPC.all == RummyWire.RPC.v1 + RummyWire.RPC.v2Added && RummyWire.RPC.all.count == 14)
    }
}
