@testable import CheckCore
import Foundation
import Testing

// 받침대 폭 매개변수화(폰 한 줄 11장 = 반 칸 22). 맥 32 동작 불변 · 폰 22 의 겹침 · 줄 넘김 · 저장-복원 · 폭 밖 항목 재배치를 값으로 잰다.
@Suite struct GamesRummyRackWidthTests {
    private func faces(_ count: Int) -> [RummyFace] {
        // 서로 다른 면이 나오게 네 색 13수를 돈다(같은 면 짝짓기가 시험을 흐리지 않게).
        (0..<count).map { RummyFace(text: "\(["A", "B", "C", "D"][$0 % 4])\($0 % 13 + 1)")! }
    }

    /// 겹침 없음 + 폭 안(반 칸 격자 전 구간).
    private func assertSound(_ layout: RummyRackLayout, sourceLocation: SourceLocation = #_sourceLocation) {
        for (id, slot) in layout.slots {
            #expect(slot.row >= 0 && slot.halfCol >= 0, "음수 자리 \(slot)", sourceLocation: sourceLocation)
            #expect(slot.halfCol + RummyRackLayout.tileSpan <= layout.halfColumns, "폭 밖 \(slot)", sourceLocation: sourceLocation)
            for (other, o) in layout.slots where other > id && o.row == slot.row {
                #expect(abs(o.halfCol - slot.halfCol) >= RummyRackLayout.tileSpan, "겹침 \(slot) \(o)", sourceLocation: sourceLocation)
            }
        }
    }

    @Test("22: 빈칸 없이 놓으면 한 줄 11장 — 22장까지 2줄, 23장에 셋째 줄")
    func packedWrapsAtElevenTiles() {
        let two = RummyRackLayout.packed(Array(0..<22), halfColumns: 22)
        assertSound(two)
        #expect(two.rowCount == 2)
        #expect(two.slot(of: 10) == RummyRackSlot(row: 0, halfCol: 20))
        #expect(two.slot(of: 11) == RummyRackSlot(row: 1, halfCol: 0))
        let three = RummyRackLayout.packed(Array(0..<23), halfColumns: 22)
        assertSound(three)
        #expect(three.rowCount == 3, "23장인데 셋째 줄이 안 열렸다")
        // 기준선: 같은 입력이 맥 폭에서는 2줄이다.
        #expect(RummyRackLayout.packed(Array(0..<23)).rowCount == 2)
    }

    @Test("22: 정렬(조합 단위 + 반 칸 틈)은 틈 때문에 21장 전에도 셋째 줄이 열릴 수 있고, 겹치지 않는다")
    func groupedStaysSound() {
        let units = (0..<7).map { base in Array((base * 3)..<(base * 3 + 3)) }   // 3장 단위 7개 = 21장
        let layout = RummyRackLayout.grouped(units, halfColumns: 22)
        assertSound(layout)
        // 3장(반 칸 6) + 틈 1 → 한 줄에 3단위(20 반 칸)까지 → 7단위는 3줄이다.
        #expect(layout.rowCount == 3)
        #expect(RummyRackLayout.grouped(units).rowCount == 2, "기준선: 맥 폭이면 2줄")
    }

    @Test("22: 끼워 넣기 · 끝자리 · 가장 가까운 빈자리가 전부 폭을 지킨다(무작위 300번)")
    func mutationsKeepTheWidth() {
        var generator = SeededRandom(seed: 17)
        var layout = RummyRackLayout.packed(Array(0..<14), halfColumns: 22)
        for step in 0..<300 {
            let id = Int.random(in: 0..<14, using: &generator)
            let wanted = RummyRackSlot(row: Int.random(in: 0..<4, using: &generator),
                                       halfCol: Int.random(in: 0..<40, using: &generator))
            switch step % 3 {
            case 0: layout.insert([id], at: wanted)
            case 1: layout.set([id], at: layout.nearestFree(to: wanted, excluding: [id]))
            default: layout.set([id], at: layout.endSlot(excluding: [id]))
            }
            assertSound(layout)
            #expect(layout.slots.count == 14, "타일을 잃었다(\(step)번째)")
        }
    }

    @Test("32: 기본값은 그대로다 — 같은 입력의 결과가 명시적 32 와 같고 정렬 줄바꿈도 옛 자리다")
    func thirtyTwoIsUnchanged() {
        #expect(RummyRackLayout().halfColumns == 32)
        #expect(RummyRackLayout.halfColumnsPerRow == 32)
        let ids = Array(0..<20)
        #expect(RummyRackLayout.packed(ids) == RummyRackLayout.packed(ids, halfColumns: 32))
        #expect(RummyRackLayout.packed(ids).slot(of: 15) == RummyRackSlot(row: 0, halfCol: 30))
        #expect(RummyRackLayout.packed(ids).slot(of: 16) == RummyRackSlot(row: 1, halfCol: 0))
        let editor = RummyTurnEditor(table: [], rack: faces(20), initialDone: true)
        #expect(editor.rackLayout.halfColumns == 32)
    }

    @Test("편집기: 폭이 정렬 · 옛 선형 자리 · 되돌리기까지 흐른다")
    func editorCarriesTheWidth() throws {
        var editor = RummyTurnEditor(table: [], rack: faces(16), initialDone: true, rackHalfColumns: 22)
        #expect(editor.rackLayout.halfColumns == 22)
        assertSound(editor.rackLayout)
        editor.sortRack(.number)
        #expect(editor.rackLayout.halfColumns == 22, "정렬이 폭을 맥 값으로 되돌렸다")
        assertSound(editor.rackLayout)
        let first = try #require(editor.rack.first?.id)
        let accepted1 = editor.moveBlock([first], to: .rack(index: 3))
        #expect(accepted1)
        #expect(editor.rackLayout.halfColumns == 22, "옛 선형 자리가 폭을 맥 값으로 되돌렸다")
        assertSound(editor.rackLayout)
        let accepted2 = editor.moveBlock([first], to: .newMeldAt(RummyPoint(x: 100, y: 100)))
        #expect(accepted2)
        editor.reset()
        #expect(editor.rack.count == 16)
        assertSound(editor.rackLayout)
    }

    @Test("저장-복원: 22 에서 저장한 자리는 22 로 그대로 돌아온다")
    func saveAndRestoreOnThePhone() throws {
        var editor = RummyTurnEditor(table: [], rack: faces(14), initialDone: true, rackHalfColumns: 22)
        let id = try #require(editor.rack.first?.id)
        let accepted3 = editor.moveBlock([id], to: .rackSlot(RummyRackSlot(row: 2, halfCol: 7)))
        #expect(accepted3)
        let saved = editor.rackEntries
        let data = try JSONEncoder().encode(saved)
        let restored = RummyTurnEditor(table: [], rack: faces(14), initialDone: true,
                                       rackEntries: try JSONDecoder().decode([RummyRackEntry].self, from: data),
                                       rackHalfColumns: 22)
        #expect(Set(restored.rackEntries) == Set(saved), "저장한 자리와 복원한 자리가 다르다")
    }

    @Test("폭 밖 항목: 맥(32)에서 저장한 자리를 폰(22)이 받으면 타일을 잃지 않고 폭 안으로 다시 앉는다")
    func outOfWidthEntriesAreReseated() {
        let macFaces = faces(16)
        // 맥 한 줄 16장 → 뒤쪽 다섯 장이 반 칸 22 를 넘는다.
        let mac = RummyTurnEditor(table: [], rack: macFaces, initialDone: true, rackHalfColumns: 32)
        #expect(mac.rackEntries.contains { $0.slot.halfCol + RummyRackLayout.tileSpan > 22 }, "전제: 폭 밖 항목이 있어야 재는 뜻이 있다")
        let phone = RummyTurnEditor(table: [], rack: macFaces, initialDone: true, rackEntries: mac.rackEntries,
                                    rackHalfColumns: 22)
        assertSound(phone.rackLayout)
        #expect(phone.rack.count == 16, "폭 밖 타일을 잃었다")
        #expect(phone.rackFaces.sorted { $0.text < $1.text } == macFaces.sorted { $0.text < $1.text })
        // 폭 안에 있던 자리는 그대로다.
        for entry in mac.rackEntries where entry.slot.halfCol + RummyRackLayout.tileSpan <= 22 {
            #expect(phone.rackEntries.contains(entry), "폭 안 자리가 움직였다: \(entry)")
        }
        // 기준선: 맥 폭으로 받으면 전부 제자리다.
        let same = RummyTurnEditor(table: [], rack: macFaces, initialDone: true, rackEntries: mac.rackEntries)
        #expect(Set(same.rackEntries) == Set(mac.rackEntries))
    }
}

/// 재현 가능한 난수(시험이 매번 같은 길을 밟는다).
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
