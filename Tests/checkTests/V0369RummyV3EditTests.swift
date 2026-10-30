import Foundation
import Testing
@testable import CheckCore

// 아잉 큐브 3판(K3) — 판 편집 손맛 규칙(`RummyTableEdit` · `RummyTurnEditor.moveBlock`/`moveSet`/`previewDrop`).
// 사용자 원문(0.3.69 실플레이): "7장 연속으로 있는데 중간꺼 뺐으면 양옆으로 3장씩 이어진 상태 남아있어야지 · 어느정도 가까이
// 배치하면 이어지는것들은 자동으로 붙게 · 붙을 수 있는 조합에 카드 추가할 땐 알맞는 위치로 자동으로".

private func ef(_ text: String) -> [RummyFace] {
    text.split(separator: " ").map { RummyFace(text: String($0))! }
}

private func ep(_ x: Int, _ y: Int) -> RummyPoint { RummyPoint(x: x, y: y) }

private func eEditor(_ sets: [String], at points: [RummyPoint], rack: String = "") -> RummyTurnEditor {
    RummyTurnEditor(table: sets.map(ef), rack: rack.isEmpty ? [] : ef(rack), initialDone: true,
                    tableLayout: RummyLayout(points.map { Optional($0) }))
}

private func eRack(_ editor: RummyTurnEditor, _ text: String) -> Int {
    editor.rack.first { $0.face.text == text }!.id
}

private func eTable(_ editor: RummyTurnEditor, _ text: String) -> Int {
    editor.melds.flatMap { $0 }.first { $0.face.text == text }!.id
}

/// 판 위 타일의 화면 왼쪽 위(묶음 점 + 자리 × 타일폭).
private func eSpot(_ editor: RummyTurnEditor, _ id: Int) -> RummyPoint? {
    for (set, meld) in editor.melds.enumerated() {
        if let index = meld.firstIndex(where: { $0.id == id }) {
            return ep(editor.points[set].x + index * RummyTableLayout.tileWidth, editor.points[set].y)
        }
    }
    return nil
}

private func eTexts(_ editor: RummyTurnEditor) -> [String] {
    editor.submissionTable.map { $0.map(\.text).joined(separator: " ") }
}

@Suite("v3 아잉 큐브 편집 — 가운데 빼면 양쪽 유지(규칙 ①)")
struct V0369RummyV3SplitTests {
    @Test("split 순수 함수: 가운데 → 두 토막(오른 토막 점 = 원래 x + 시작 자리 × 40) · 끝 → 짧아질 뿐 · 왼끝 → 점이 오른쪽 · 전부 → 빈 배열")
    func splitPure() {
        // 없으면: 가운데를 뺀 뒤 오른 토막이 왼쪽으로 당겨져(타일이 튄다) 사용자가 "중간만 분리" 를 못 보는 결함이 초록이 된다.
        let point = ep(100, 200)
        #expect(RummyTableEdit.split(count: 7, point: point, removing: [3]) == [
            RummySplitPiece(range: 0..<3, point: ep(100, 200)), RummySplitPiece(range: 4..<7, point: ep(260, 200)),
        ])
        #expect(RummyTableEdit.split(count: 7, point: point, removing: [6]) == [RummySplitPiece(range: 0..<6, point: point)])
        #expect(RummyTableEdit.split(count: 7, point: point, removing: [0]) == [RummySplitPiece(range: 1..<7, point: ep(140, 200))])
        #expect(RummyTableEdit.split(count: 7, point: point, removing: [1, 4]).map(\.range) == [0..<1, 2..<4, 5..<7])
        #expect(RummyTableEdit.split(count: 3, point: point, removing: [0, 1, 2]).isEmpty)
        #expect(RummyTableEdit.split(count: 3, point: point, removing: []) == [RummySplitPiece(range: 0..<3, point: point)])
    }

    @Test("7장 런 가운데(A4)를 빼면 A1-A3 · A5-A7 둘 다 유효하고 남은 타일 여섯 장은 한 칸도 안 움직인다 · 새 세트는 맨 끝")
    func sevenRunMiddle() throws {
        // 없으면: 가운데를 빼면 나머지 여섯 장이 한 묶음(무효)으로 붙어 남는 0.3.69 결함이 초록이 된다.
        var editor = eEditor(["A1 A2 A3 A4 A5 A6 A7"], at: [ep(100, 200)])
        let before = editor.melds[0].map { ($0.id, eSpot(editor, $0.id)!) }
        let a4 = eTable(editor, "A4")
        let ok1 = editor.moveBlock([a4], to: .newMeldAt(ep(600, 500)))
        #expect(ok1)
        #expect(eTexts(editor) == ["A1 A2 A3", "A5 A6 A7", "A4"])
        #expect(editor.points[0] == ep(100, 200) && editor.points[1] == ep(260, 200))
        #expect(editor.analysis(ofMeld: 0).valid && editor.analysis(ofMeld: 1).valid)
        for (id, spot) in before where id != a4 {
            #expect(eSpot(editor, id) == spot, "타일 \(id) 가 움직였다")
        }
        // 판 출신은 쪼갠 뒤에도 랙으로 못 간다(R-14).
        #expect(!editor.canMoveBlock([a4], to: .rack(index: nil)))
        #expect(editor.previewDrop([eTable(editor, "A2")], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 0))) == nil)
    }

    @Test("끝에서 빼면 짧아질 뿐 — 오른끝은 점 그대로, 왼끝은 점이 한 칸 오른쪽(남은 타일 제자리)")
    func endRemoval() {
        // 없으면: 왼끝을 빼면 남은 묶음이 왼쪽으로 한 칸 당겨져 타일이 튀는 결함이 초록이 된다.
        var editor = eEditor(["A1 A2 A3 A4 A5 A6 A7"], at: [ep(100, 200)])
        let ok2 = editor.moveBlock([eTable(editor, "A7")], to: .newMeldAt(ep(600, 500)))
        #expect(ok2)
        #expect(eTexts(editor) == ["A1 A2 A3 A4 A5 A6", "A7"] && editor.points[0] == ep(100, 200))
        let ok3 = editor.moveBlock([eTable(editor, "A1")], to: .newMeldAt(ep(600, 400)))
        #expect(ok3)
        #expect(eTexts(editor) == ["A2 A3 A4 A5 A6", "A7", "A1"] && editor.points[0] == ep(140, 200))
    }

    @Test("그룹도 같은 규칙 · 조커 섞인 런 가운데를 빼도 조커 쪽 토막이 유효하게 남는다 · 여러 장 빼면 토막 셋")
    func groupJokerAndMulti() {
        // 없으면: 그룹이나 조커 런에서만 규칙이 달라(한 덩어리로 남거나 조커가 엉뚱한 토막으로) 판이 깨지는 결함이 초록이 된다.
        var group = eEditor(["A5 B5 C5 D5"], at: [ep(100, 100)])
        let ok4 = group.moveBlock([eTable(group, "B5")], to: .newMeldAt(ep(600, 500)))
        #expect(ok4)
        #expect(eTexts(group) == ["A5", "C5 D5", "B5"] && group.points[1] == ep(180, 100))

        var joker = eEditor(["A3 J A5 A6 A7 A8 A9"], at: [ep(40, 300)])
        #expect(joker.melds[0].map(\.face.text) == ["A3", "J", "A5", "A6", "A7", "A8", "A9"])
        let ok5 = joker.moveBlock([eTable(joker, "A6")], to: .newMeldAt(ep(600, 500)))
        #expect(ok5)
        #expect(eTexts(joker) == ["A3 J A5", "A7 A8 A9", "A6"])
        #expect(joker.analysis(ofMeld: 0).valid && joker.analysis(ofMeld: 1).valid)
        #expect(joker.points[1] == ep(40 + 4 * 40, 300))

        var multi = eEditor(["B1 B2 B3 B4 B5 B6 B7 B8"], at: [ep(0, 0)])
        let ok6 = multi.moveBlock([eTable(multi, "B3"), eTable(multi, "B6")], to: .newMeldAt(ep(500, 500)))
        #expect(ok6)
        #expect(eTexts(multi) == ["B1 B2", "B4 B5", "B7 B8", "B3 B6"])
        #expect(multi.points.prefix(3) == [ep(0, 0), ep(120, 0), ep(240, 0)])
    }

    @Test("이번 차례에 가운데 낸 랙 타일을 거두면 둘로 남고, 되돌리기는 시작 판·배치 그대로")
    func rackTileOutOfMiddleAndReset() {
        // 없으면: 내 타일을 거둘 때 남은 판 묶음이 한 덩어리로 붙어 남거나, 되돌리기가 쪼갠 판을 못 되돌리는 결함이 초록이 된다.
        let fresh = eEditor(["A1 A2 A3", "A5 A6 A7"], at: [ep(100, 200), ep(300, 200)], rack: "A4 B9")
        var editor = fresh
        let a4 = eRack(editor, "A4")
        let ok7 = editor.moveBlock([a4], to: .meld(0, index: nil))
        #expect(ok7)
        let ok8 = editor.moveSet(1, to: ep(260, 200))   // A1-A4 오른끝(260)에 닿는다 → 합친다
        #expect(ok8)
        #expect(eTexts(editor) == ["A1 A2 A3 A4 A5 A6 A7"] && editor.points == [ep(100, 200)])
        var undone = editor
        undone.reset()
        #expect(undone == fresh)
        let ok9 = editor.moveBlock([a4], to: .rack(index: nil))
        #expect(ok9)
        #expect(eTexts(editor) == ["A1 A2 A3", "A5 A6 A7"] && editor.points == [ep(100, 200), ep(260, 200)])
        #expect(!editor.isChanged && editor.isLayoutChanged)
        editor.reset()
        #expect(editor.melds == fresh.melds && editor.points == fresh.points && editor.rackFaces.count == 2)
    }
}

@Suite("v3 아잉 큐브 편집 — 가까이 놓으면 붙기(규칙 ②)")
struct V0369RummyV3AttachTests {
    @Test("오른끝 · 왼끝에 붙는다(대상 제자리) · 세로 28 까지 · 가로 24 까지 · 안 이어지면 새 묶음")
    func attachRightLeftAndThresholds() {
        // 없으면: 묶음 끝 가까이 놓은 타일이 따로 놀아 손으로 정확히 겨눠야만 붙는 0.3.69 손맛이 초록이 된다.
        #expect(RummyTableEdit.attachGap == 24 && RummyTableEdit.attachRise == 28)
        let base = eEditor(["A2 A3 A4"], at: [ep(200, 200)], rack: "A1 A5 B9")
        var right = base
        #expect(right.previewDrop([eRack(right, "A5")], to: .newMeldAt(ep(344, 228)))?.plan == .attach(set: 0, side: .right))
        let ok10 = right.moveBlock([eRack(right, "A5")], to: .newMeldAt(ep(344, 228)))   // 간격 24 · 세로 28
        #expect(ok10)
        #expect(eTexts(right) == ["A2 A3 A4 A5"] && right.points == [ep(200, 200)])

        var left = base
        let ok11 = left.moveBlock([eRack(left, "A1")], to: .newMeldAt(ep(140, 190)))   // 왼끝 간격 20
        #expect(ok11)
        #expect(eTexts(left) == ["A1 A2 A3 A4"] && left.points == [ep(160, 200)])

        var far = base
        #expect(far.previewDrop([eRack(far, "A5")], to: .newMeldAt(ep(345, 200)))?.plan != .attach(set: 0, side: .right))
        let ok12 = far.moveBlock([eRack(far, "A5")], to: .newMeldAt(ep(320, 229)))   // 세로 29 → 안 붙는다
        #expect(ok12)
        #expect(eTexts(far) == ["A2 A3 A4", "A5"])

        var mismatch = base
        let preview = mismatch.previewDrop([eRack(mismatch, "B9")], to: .newMeldAt(ep(330, 200)))
        let ok13 = mismatch.moveBlock([eRack(mismatch, "B9")], to: .newMeldAt(ep(330, 200)))
        #expect(ok13)
        #expect(eTexts(mismatch) == ["A2 A3 A4", "B9"])
        #expect(preview?.plan == .newSet(mismatch.points[1]) && preview?.landing?.frame == mismatch.tableLayout.frame(of: 1))
        #expect(mismatch.tableLayout.frames[0].maxX + RummyTableLayout.clearance <= mismatch.points[1].x)
    }

    @Test("양쪽 다 되면 더 가까운 쪽 · 구멍을 메우면 양쪽 토막이 다 붙어 하나가 된다")
    func closerSideAndGapFill() {
        // 없으면: 두 묶음 사이에 놓은 타일이 먼 쪽에 붙거나, 구멍을 메워도 세 조각으로 남는 결함이 초록이 된다.
        let base = eEditor(["A2 A3 A4", "B5 C5 D5"], at: [ep(100, 200), ep(290, 200)], rack: "A5")
        var nearRun = base
        let ok14 = nearRun.moveBlock([eRack(nearRun, "A5")], to: .newMeldAt(ep(230, 200)))   // 런 10 · 그룹 20
        #expect(ok14)
        #expect(eTexts(nearRun) == ["A2 A3 A4 A5", "B5 C5 D5"])
        var nearGroup = base
        #expect(nearGroup.previewDrop([eRack(nearGroup, "A5")], to: .newMeldAt(ep(238, 200)))?.plan
                == .attach(set: 1, side: .left))
        let ok15 = nearGroup.moveBlock([eRack(nearGroup, "A5")], to: .newMeldAt(ep(238, 200)))   // 런 18 · 그룹 12
        #expect(ok15)
        #expect(eTexts(nearGroup) == ["A2 A3 A4", "A5 B5 C5 D5"] && nearGroup.points[1] == ep(250, 200))

        // 7장 런 가운데를 뺐다가 그 구멍에 도로 놓으면 다시 한 묶음.
        var hole = eEditor(["A1 A2 A3 A4 A5 A6 A7"], at: [ep(100, 200)])
        let a4 = eTable(hole, "A4")
        let ok16 = hole.moveBlock([a4], to: .newMeldAt(ep(600, 500)))
        #expect(ok16)
        let preview = hole.previewDrop([a4], to: .newMeldAt(ep(220, 204)))
        #expect(preview?.landing?.faces.map(\.text) == ["A1", "A2", "A3", "A4", "A5", "A6", "A7"])
        #expect(preview?.landing?.valid == true && preview?.landing?.blockStart == 3)
        let ok17 = hole.moveBlock([a4], to: .newMeldAt(ep(220, 204)))
        #expect(ok17)
        #expect(eTexts(hole) == ["A1 A2 A3 A4 A5 A6 A7"] && hole.points == [ep(100, 200)])
        #expect(!hole.isChanged)
    }

    @Test("묶음 통째 옮기기(moveSet)도 끝 가까이면 합친다(대상 제자리) · 안 이어지면 위치만 · 덩어리(여러 장)도 붙는다")
    func moveSetAndBlockAttach() {
        // 없으면: 묶음째 끌어 런 끝에 갖다 대도 두 묶음으로 남아 하나씩 다시 옮겨야 하는 결함이 초록이 된다.
        var editor = eEditor(["A1 A2 A3", "A4 A5", "C9 D9 B9"], at: [ep(100, 200), ep(500, 400), ep(600, 100)])
        let preview = editor.previewMoveSet(1, to: ep(235, 205))
        #expect(preview?.plan == .attach(set: 0, side: .right))
        let ok18 = editor.moveSet(1, to: ep(235, 205))
        #expect(ok18)
        #expect(eTexts(editor) == ["A1 A2 A3 A4 A5", "B9 C9 D9"] && editor.points[0] == ep(100, 200))
        #expect(preview?.landing?.frame == editor.tableLayout.frame(of: 0))
        // 그룹 묶음을 런 끝에 대면 안 이어진다 → 위치 이동만(스냅).
        let ok19 = editor.moveSet(1, to: ep(310, 200))
        #expect(ok19)
        #expect(editor.melds.count == 2 && editor.tableLayout.frames[0].maxX + RummyTableLayout.clearance <= editor.points[1].x)

        var block = eEditor(["A3 A4 A5"], at: [ep(400, 300)], rack: "A1 A2 B7")
        let ids = block.rackChain(around: eRack(block, "A1"))
        #expect(ids.count == 2)
        let ok20 = block.moveBlock(ids, to: .newMeldAt(ep(310, 296)))
        #expect(ok20)
        #expect(eTexts(block) == ["A1 A2 A3 A4 A5"] && block.points == [ep(320, 300)])
    }
}

@Suite("v3 아잉 큐브 편집 — 알맞은 자리에 자동 삽입(규칙 ③)")
struct V0369RummyV3InsertTests {
    @Test("insertionIndex 순수 함수: 런 앞·뒤 · 조커 자리 · 그룹 오른끝 · 맞는 자리 없음 = 놓은 자리")
    func insertionPure() {
        // 없으면: 6-7-8 위에 놓은 5 가 놓은 자리(뒤)에 꽂혀 무효 묶음이 되는 0.3.69 손맛이 초록이 된다.
        #expect(RummyTableEdit.insertionIndex(ef("A5"), into: ef("A6 A7 A8"), preferred: 3) == RummyInsertion(index: 0, fits: true))
        #expect(RummyTableEdit.insertionIndex(ef("A9"), into: ef("A6 A7 A8"), preferred: 0) == RummyInsertion(index: 3, fits: true))
        #expect(RummyTableEdit.insertionIndex(ef("A8"), into: ef("A6 A7 J"), preferred: 3).index == 2)    // J 가 9 로 밀린다
        #expect(RummyTableEdit.insertionIndex(ef("A8"), into: ef("A5 J A7"), preferred: 0).index == 3)
        #expect(RummyTableEdit.insertionIndex(ef("J"), into: ef("A5 A6 A7"), preferred: 0).index == 0)    // 둘 다 맞으면 놓은 쪽
        #expect(RummyTableEdit.insertionIndex(ef("J"), into: ef("A5 A6 A7"), preferred: 2).index == 3)
        #expect(RummyTableEdit.insertionIndex(ef("A9 A10"), into: ef("A6 A7 A8"), preferred: 0).index == 3)
        #expect(RummyTableEdit.insertionIndex(ef("D5"), into: ef("A5 B5 C5"), preferred: 0) == RummyInsertion(index: 3, fits: true))
        #expect(RummyTableEdit.insertionIndex(ef("B2"), into: ef("A6 A7 A8"), preferred: 1) == RummyInsertion(index: 1, fits: false))
        #expect(RummyTableEdit.insertionIndex(ef("A5"), into: [], preferred: 9) == RummyInsertion(index: 0, fits: true))
    }

    @Test("편집기: 5 를 6-7-8 뒤에 놓아도 앞에 — 묶음이 왼쪽으로 늘어 기존 타일 제자리 · 9 는 앞에 놓아도 뒤")
    func editorFrontAndBack() throws {
        // 없으면: 앞에 꽂힌 타일이 기존 타일을 오른쪽으로 밀어내 묶음이 들썩이는 결함이 초록이 된다.
        var editor = eEditor(["A6 A7 A8"], at: [ep(300, 200)], rack: "A5 A9 B2")
        let plan = editor.previewDrop([eRack(editor, "A5")], to: .meld(0, index: 3))
        #expect(plan?.plan == .insert(set: 0, index: 0) && plan?.landing?.blockStart == 0 && plan?.landing?.valid == true)
        let ok21 = editor.moveBlock([eRack(editor, "A5")], to: .meld(0, index: 3))
        #expect(ok21)
        #expect(eTexts(editor) == ["A5 A6 A7 A8"] && editor.points == [ep(260, 200)])
        let ok22 = editor.moveBlock([eRack(editor, "A9")], to: .meld(0, index: 0))
        #expect(ok22)
        #expect(eTexts(editor) == ["A5 A6 A7 A8 A9"] && editor.points == [ep(260, 200)])
        // 맞는 자리가 없으면 놓은 자리(무효 표시는 판정 몫).
        let ok23 = editor.moveBlock([eRack(editor, "B2")], to: .meld(0, index: 2))
        #expect(ok23)
        #expect(eTexts(editor) == ["A5 A6 B2 A7 A8 A9"] && !editor.analysis(ofMeld: 0).valid)
    }

    @Test("조커 자리 · 그룹은 표시 순서 자리(색 A→D — 확정 뒤와 같다, 0.3.70) · 판 끝에 막히면 판 안으로")
    func jokerGroupAndEdge() {
        // 없으면: 조커가 메우는 숫자를 무시해 엉뚱한 자리에 꽂히거나, 그룹 오른끝에 꽂혀 확정 뒤 서버 표시 순서(R-09)로 타일이 튀는 결함이 초록이 된다.
        var joker = eEditor(["A6 A7 J"], at: [ep(300, 200)], rack: "A8")
        #expect(joker.melds[0].map(\.face.text) == ["A6", "A7", "J"])
        let ok24 = joker.moveBlock([eRack(joker, "A8")], to: .meld(0, index: 3))
        #expect(ok24)
        #expect(eTexts(joker) == ["A6 A7 A8 J"] && joker.analysis(ofMeld: 0).valid)

        var group = eEditor(["A5 B5 D5"], at: [ep(300, 200)], rack: "C5")
        let ok25 = group.moveBlock([eRack(group, "C5")], to: .meld(0, index: 0))
        #expect(ok25)
        #expect(eTexts(group) == ["A5 B5 C5 D5"] && group.points == [ep(300, 200)] && group.analysis(ofMeld: 0).valid)

        var edge = eEditor(["A6 A7 A8"], at: [ep(0, 0)], rack: "A5")
        let ok26 = edge.moveBlock([eRack(edge, "A5")], to: .meld(0, index: nil))
        #expect(ok26)
        #expect(eTexts(edge) == ["A5 A6 A7 A8"])
        #expect(RummyTableLayout.fits(edge.tableLayout.frames[0]))
    }

    @Test("꽂아서 자란 쪽 끝이 이웃에 닿으면 붙는다(구멍 메우기) · 원래 곁(여백 16)에 있던 이웃과는 안 합친다")
    func insertGrowthAttachesOnlyOnGrownSide() {
        // 없으면: 조커를 빼낸 구멍에 7 을 [6] 위로 놓으면 [6 7] 이 [8] 과 겹쳐 엉뚱한 곳으로 튀거나, 따로 둔 묶음이 곁 런과 멋대로 합쳐진다.
        var hole = eEditor(["A6 J A8"], at: [ep(200, 200)], rack: "A7")
        let ok27 = hole.moveBlock([eTable(hole, "J")], to: .newMeldAt(ep(600, 500)))
        #expect(ok27)
        #expect(eTexts(hole) == ["A6", "A8", "J"])
        let ok28 = hole.moveBlock([eRack(hole, "A7")], to: .meld(0, index: nil))
        #expect(ok28)
        #expect(eTexts(hole) == ["A6 A7 A8", "J"] && hole.points[0] == ep(200, 200))

        var apart = eEditor(["A1 A2 A3", "A4"], at: [ep(0, 0), ep(136, 0)], rack: "A5")
        let ok29 = apart.moveBlock([eRack(apart, "A5")], to: .meld(1, index: nil))
        #expect(ok29)
        #expect(eTexts(apart) == ["A1 A2 A3", "A4 A5"] && apart.points == [ep(0, 0), ep(136, 0)])
    }
}

@Suite("v3 아잉 큐브 편집 — 결정성 · 미리보기 = 실제")
struct V0369RummyV3DeterminismTests {
    @Test("같은 입력 같은 결과 · previewDrop 은 편집기를 안 바꾸고 실제 놓기 결과와 같다 · 거절은 nil")
    func deterministicAndPreviewMatches() {
        // 없으면: 미리보기가 그린 자리와 놓은 뒤 자리가 달라 손이 속거나, 기기마다 다른 판이 그려지는 결함이 초록이 된다.
        let base = eEditor(["A1 A2 A3 A4 A5 A6 A7", "B5 C5 D5", "A9 A10 J"],
                           at: [ep(40, 40), ep(500, 40), ep(300, 300)], rack: "A8 A5 C2 J")
        let tableIDs = base.melds.flatMap { $0 }.map(\.id)
        let rackIDs = base.rack.map(\.id)
        var targets: [RummyDropTarget] = [.newMeld, .rack(index: nil), .rackSlot(RummyRackSlot(row: 1, halfCol: 4)), .meld(9, index: nil)]
        for x in stride(from: 0, through: 960, by: 60) {
            for y in stride(from: 0, through: 580, by: 52) { targets.append(.newMeldAt(ep(x, y))) }
        }
        for set in 0..<3 {
            for slot in [nil, 0, 2, 5] as [Int?] { targets.append(.meld(set, index: slot)) }
        }
        var compared = 0
        for id in tableIDs + rackIDs {
            for target in targets {
                let snapshot = base
                let preview = base.previewDrop([id], to: target)
                #expect(base == snapshot)
                var a = base, b = base
                let movedA = a.moveBlock([id], to: target)
                let movedB = b.moveBlock([id], to: target)
                #expect(movedA == movedB && a == b, "\(id) → \(target)")
                #expect((preview != nil) == movedA, "\(id) → \(target)")
                if let landing = preview?.landing {
                    #expect(a.melds.indices.contains(landing.set))
                    if a.melds.indices.contains(landing.set) {
                        #expect(a.melds[landing.set].map(\.face) == landing.faces)
                        #expect(a.tableLayout.frame(of: landing.set) == landing.frame)
                        #expect(a.melds[landing.set][landing.blockStart].id == id)
                    }
                    compared += 1
                }
                #expect(a.melds.allSatisfy { !$0.isEmpty } && a.points.count == a.melds.count)
                #expect(Set((a.melds.flatMap { $0 } + a.rack).map(\.id)) == Set(tableIDs + rackIDs))
            }
        }
        #expect(compared > 500)
        // 묶음 통째: 미리보기 = 실제.
        for set in 0..<3 {
            for x in stride(from: 0, through: 900, by: 90) {
                let point = ep(x, 44)
                var moved = base
                let preview = base.previewMoveSet(set, to: point)
                let ok30 = moved.moveSet(set, to: point)
                #expect(ok30)
                if let landing = preview?.landing {
                    #expect(moved.tableLayout.frame(of: landing.set) == landing.frame)
                    #expect(moved.melds[landing.set].map(\.face) == landing.faces)
                }
            }
        }
        #expect(base.previewMoveSet(7, to: ep(0, 0)) == nil)
    }
}
