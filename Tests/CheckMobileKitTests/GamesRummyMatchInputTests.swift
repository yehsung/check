@testable import CheckCore
import CoreGraphics
import Foundation
import Observation
import Testing
@testable import CheckMobileKit

// 폰 아잉 큐브 판 화면의 **끌기 판정**. 합성 입력이 금지이므로 "손 궤적 → 분류 → 놓을 자리 → 편집기 결과" 를 값으로 잰다.
// 궤적은 실제 화면과 같은 재료(`GamesRummyTouchContext` · `GamesRummyMatchModel`)로 밟고, 결과는 진짜 편집기(`RummyTurnEditor`)에 놓아 본다.
@MainActor
@Suite struct GamesRummyMatchInputTests {
    /// iPhone 15 가로 세이프 영역 안.
    static let size = CGSize(width: 734, height: 372)

    static func faces(_ texts: String...) -> [RummyFace] { texts.compactMap(RummyFace.init(text:)) }

    /// 판 두 묶음(A1~A3 왼쪽 위 · B4~B7 오른쪽 — `farMeldY` 를 키우면 기본 보기의 세로 밖) + 받침대 A4 · C1 C2 C3 · D9.
    static func editor(initialDone: Bool = true, farMeldX: Int = 800, farMeldY: Int = 50) -> RummyTurnEditor {
        RummyTurnEditor(table: [faces("A1", "A2", "A3"), faces("B4", "B5", "B6", "B7")],
                        rack: faces("A4", "C1", "C2", "C3", "D9"),
                        initialDone: initialDone,
                        tableLayout: [RummyPoint(x: 100, y: 50), RummyPoint(x: farMeldX, y: farMeldY)])
    }

    static func context(_ editor: RummyTurnEditor? = GamesRummyMatchInputTests.editor(), isMyTurn: Bool = true,
                        viewport: GamesRummyViewport? = nil, size: CGSize = GamesRummyMatchInputTests.size,
                        rows: Int? = nil) -> GamesRummyTouchContext {
        let layout = GamesRummyMatchLayout(size: size, rackRows: rows ?? editor?.rackLayout.rowCount ?? 2)
        let scene = GamesRummyBoardScene.make(match: nil, editor: editor, isMyTurn: isMyTurn && editor != nil, otherDraft: nil)
        return GamesRummyTouchContext(layout: layout, viewport: viewport, scene: scene, editor: editor,
                                      isMyTurn: isMyTurn && editor != nil, editable: isMyTurn && editor != nil)
    }

    static func id(_ face: String, in editor: RummyTurnEditor) -> Int {
        if let tile = editor.rack.first(where: { $0.face.text == face }) { return tile.id }
        return editor.melds.joined().first { $0.face.text == face }!.id
    }

    /// 받침대 타일 가운데(판 화면 좌표).
    static func rackPoint(_ face: String, _ context: GamesRummyTouchContext) -> CGPoint {
        let slot = context.editor!.rackLayout.slot(of: id(face, in: context.editor!))!
        let frame = context.rack.frame(slot)
        return CGPoint(x: frame.midX + context.layout.rack.minX, y: frame.midY + context.layout.rack.minY)
    }

    static func screen(_ logical: CGPoint, _ context: GamesRummyTouchContext) -> CGPoint {
        let local = context.viewport.transform.toScreen(logical)
        return CGPoint(x: local.x + context.layout.table.minX, y: local.y + context.layout.table.minY)
    }

    /// 손 위 점이 `pointer` 에 오는 손 자리(판 위에서는 48pt).
    static func finger(under pointer: CGPoint) -> CGPoint { GamesRummyMatchLayout(size: size).finger(forPointer: pointer) }

    /// 궤적 한 번: 누르고 → 목적지로 가서 → 뗀다.
    static func trace(_ start: CGPoint, to end: CGPoint, _ context: GamesRummyTouchContext, hold: Bool = false) -> GamesRummyDropAction {
        var machine = GamesRummyTouchMachine()
        machine.down(start, context)
        _ = machine.move(start, context)
        if hold { _ = machine.holdElapsed(context) }
        _ = machine.move(end, context)
        return machine.up(end, context)
    }

    static func apply(_ action: GamesRummyDropAction, to editor: inout RummyTurnEditor) -> Bool {
        switch action {
        case .none, .refused: return false
        case .moveTiles(let ids, let target): return editor.moveBlock(ids, to: target)
        case .moveSet(let index, let point): return editor.moveSet(index, to: point)
        }
    }

    // MARK: - 받침대 → 판

    @Test("받침대 → 판: 묶음 위에 놓으면 그 묶음에 붙고 받침대에서 빠진다(기준점은 손 위 48pt)")
    func rackToMeld() {
        var editor = Self.editor()
        let context = Self.context(editor)
        let a4 = Self.id("A4", in: editor)
        let pointer = Self.screen(CGPoint(x: 100 + 120 - 6, y: 78), context)
        let action = Self.trace(Self.rackPoint("A4", context), to: Self.finger(under: pointer), context)
        #expect(action == .moveTiles([a4], .meld(0, index: 3)))
        let applied = Self.apply(action, to: &editor)
        #expect(applied)
        #expect(editor.melds[0].map(\.face.text) == ["A1", "A2", "A3", "A4"])
        #expect(!editor.rack.contains { $0.id == a4 })
        #expect(editor.canSubmit)
        // 기준선: 손 자리(48pt 아래)로 쟀다면 묶음 위가 아니다 — 들어 올림이 판정에 실제로 들어간다.
        let wrong = Self.trace(Self.rackPoint("A4", context), to: pointer, context)
        #expect(wrong != action, "손 위 48pt 를 안 쓰고 잰다")
    }

    @Test("받침대 → 판: 빈 펠트에 놓으면 새 묶음 · 누른 타일 가운데가 기준이다")
    func rackToFelt() {
        var editor = Self.editor()
        let context = Self.context(editor)
        let d9 = Self.id("D9", in: editor)
        let pointer = Self.screen(CGPoint(x: 300, y: 300), context)
        let action = Self.trace(Self.rackPoint("D9", context), to: Self.finger(under: pointer), context)
        #expect(action == .moveTiles([d9], .newMeldAt(RummyPoint(x: 280, y: 272))))
        let applied = Self.apply(action, to: &editor)
        #expect(applied)
        #expect(editor.melds.count == 3 && editor.melds[2].map(\.id) == [d9])
    }

    @Test("한 장 끌기 문턱: 8pt 까지는 끌기가 아니고 넘으면 한 장이다 · 그냥 떼면 아무 일도 없다")
    func dragThreshold() {
        let context = Self.context()
        let start = Self.rackPoint("C2", context)
        var machine = GamesRummyTouchMachine()
        machine.down(start, context)
        let step1 = machine.move(CGPoint(x: start.x + 8, y: start.y), context)
        #expect(step1 == .none)
        #expect(machine.drag == nil)
        let step2 = machine.move(CGPoint(x: start.x + 8.5, y: start.y), context)
        #expect(step2 == .dragBegan)
        #expect(machine.drag?.ids == [Self.id("C2", in: context.editor!)], "꾹 안 눌렀는데 묶음째 집혔다")
        var tap = GamesRummyTouchMachine()
        tap.down(start, context)
        let step3 = tap.up(start, context)
        #expect(step3 == .none)
        #expect(tap.isIdle)
    }

    @Test("꾹 누르기: 0.5초면 받침대 덩어리째 · 그다음 끌면 묶음이 새 묶음으로 간다 · 움직인 뒤에는 0.5초가 안 먹힌다")
    func holdPicksChain() {
        var editor = Self.editor()
        let context = Self.context(editor)
        let start = Self.rackPoint("C2", context)
        var machine = GamesRummyTouchMachine()
        machine.down(start, context)
        let chain = ["C1", "C2", "C3"].map { Self.id($0, in: editor) }
        let step4 = machine.holdElapsed(context)
        #expect(step4?.ids == chain)
        let step5 = machine.holdElapsed(context)
        #expect(step5 == nil, "두 번 집는다")
        let pointer = Self.screen(CGPoint(x: 300, y: 300), context)
        let step6 = machine.move(Self.finger(under: pointer), context)
        #expect(step6 == .dragBegan)
        #expect(machine.drag?.ids == chain && machine.drag?.grabIndex == 1)
        let action = machine.up(Self.finger(under: pointer), context)
        // 가운데 타일을 잡았으니 묶음 왼쪽은 기준점에서 1.5칸 왼쪽.
        #expect(action == .moveTiles(chain, .newMeldAt(RummyPoint(x: 240, y: 272))))
        let applied = Self.apply(action, to: &editor)
        #expect(applied)
        #expect(editor.melds.last?.map(\.face.text) == ["C1", "C2", "C3"])

        var moved = GamesRummyTouchMachine()
        moved.down(start, context)
        _ = moved.move(CGPoint(x: start.x + 20, y: start.y), context)
        let step7 = moved.holdElapsed(context)
        #expect(step7 == nil, "이미 한 장을 끌기 시작했는데 묶음이 된다")
        #expect(moved.drag?.ids.count == 1)
    }

    // MARK: - 판 → 판 · 판 → 받침대

    @Test("판 → 판: 세로로 밀어 둔 판에서 타일을 다른 묶음으로 옮긴다 · 좌표가 밀린 만큼 맞는다")
    func boardToBoardOnScrolledTable() {
        var editor = Self.editor(farMeldX: 650, farMeldY: 480)
        var view = GamesRummyViewport(viewport: GamesRummyMatchLayout(size: Self.size).table.size)
        view.pan(by: CGSize(width: 0, height: -40))
        let context = Self.context(editor, viewport: view)
        // 밀어 두지 않았다면 아래 묶음(y 480)은 칸 밖이다.
        let table = context.layout.table
        #expect(Self.screen(CGPoint(x: 660, y: 508), Self.context(editor)).y > table.maxY)
        let a3 = Self.id("A3", in: editor)
        let start = Self.screen(CGPoint(x: 100 + 80 + 20, y: 78), context)
        #expect(context.hit(start) == .boardTile(a3))
        let pointer = Self.screen(CGPoint(x: 660, y: 508), context)
        #expect(pointer.y > table.minY && pointer.y < table.maxY, "기준선: 목적지가 칸 안이어야 시험이 뜻이 있다")
        let action = Self.trace(start, to: Self.finger(under: pointer), context)
        #expect(action == .moveTiles([a3], .meld(1, index: 0)))
        let applied = Self.apply(action, to: &editor)
        #expect(applied)
        #expect(editor.melds[0].count == 2 && editor.melds[1].contains { $0.id == a3 })
    }

    @Test("판 → 판: 세로 밖 묶음까지 가장자리 자동 밀기로 간다 — 민 뒤 놓을 자리가 진짜 그 묶음이다")
    func boardToFarMeldWithAutoPan() {
        var editor = Self.editor(farMeldY: 560)
        let context = Self.context(editor)
        let model = GamesRummyMatchModel(tableSize: context.layout.table.size)
        let a3 = Self.id("A3", in: editor)
        let start = Self.screen(CGPoint(x: 100 + 80 + 20, y: 78), context)
        model.touchChanged(start: start, location: start, context: context)
        model.touchChanged(start: start, location: Self.finger(under: CGPoint(x: context.layout.table.midX, y: context.layout.table.maxY - 10)), context: context)
        // 끝까지 민다.
        for _ in 0..<200 { model.edgeTick(deltaTime: 0.016) }
        #expect(abs(model.viewport.visibleLogical.maxY - 640) < 0.01, "자동 밀기가 끝까지 안 갔다")
        // 그 자리에서 묶음 위로 손을 옮겨 놓는다.
        let view = context.with(viewport: model.viewport)
        let over = Self.finger(under: Self.screen(CGPoint(x: 800 + 160 - 6, y: 588), view))
        model.touchChanged(start: start, location: over, context: context)
        let action = model.touchEnded(at: over, context: context)
        #expect(action == .moveTiles([a3], .meld(1, index: 4)))
        let applied = Self.apply(action, to: &editor)
        #expect(applied)
        #expect(editor.melds[1].last?.id == a3 || editor.melds[1].contains { $0.id == a3 })
    }

    @Test("판 → 받침대: 판 출신은 거절(R-14) — 편집기가 그대로고 받침대가 빨개진다 · 내가 이번에 낸 타일은 돌아간다")
    func boardToRackRefused() {
        var editor = Self.editor()
        let context = Self.context(editor)
        let a2 = Self.id("A2", in: editor)
        let start = Self.screen(CGPoint(x: 100 + 40 + 20, y: 78), context)
        let over = CGPoint(x: context.layout.rack.midX, y: context.layout.rack.midY)
        #expect(Self.trace(start, to: Self.finger(under: over), context) == .refused)

        let model = GamesRummyMatchModel(tableSize: context.layout.table.size)
        model.touchChanged(start: start, location: start, context: context)
        model.touchChanged(start: start, location: Self.finger(under: over), context: context)
        #expect(model.hoverRefused)
        #expect(model.rackPreview == nil, "거절인데 받침대가 비켜 선다")
        #expect(model.draggingIDs == [a2])
        let action = model.touchEnded(at: Self.finger(under: over), context: context)
        #expect(action == .refused)
        #expect(model.refusedFlash && model.refuseSerial == 1)
        #expect(!model.hoverRefused && model.draggingIDs.isEmpty && model.drag == nil, "제자리로 안 돌아간다")
        let before = editor
        let applied = Self.apply(action, to: &editor)
        #expect(!applied)
        #expect(editor == before)

        // 이번 차례에 받침대에서 낸 타일은 받침대로 돌아간다(판 출신이 아니다).
        let a4 = Self.id("A4", in: editor)
        let movedEditor = editor.moveBlock([a4], to: .meld(0, index: 3))
        #expect(movedEditor)
        let played = Self.context(editor)
        let back = Self.screen(CGPoint(x: 100 + 120 + 20, y: 78), played)
        #expect(played.hit(back) == .boardTile(a4))
        guard case .moveTiles([a4], .rackSlot) = Self.trace(back, to: Self.finger(under: over), played) else {
            Issue.record("내가 낸 타일이 받침대로 안 돌아간다")
            return
        }
    }

    // MARK: - 묶음 이동

    @Test("손잡이: 묶음 통째 이동 — 잡은 자리만큼 뺀 왼쪽 위 · 받침대 위에 놓으면 아무 일도 없다")
    func handleMovesTheSet() {
        var editor = Self.editor()
        let context = Self.context(editor)
        let scale = context.viewport.scale
        let edge = Self.screen(CGPoint(x: 100, y: 50 + 28), context)
        let start = CGPoint(x: edge.x - 10, y: edge.y)
        #expect(context.hit(start) == .meldHandle(0))
        let finger = CGPoint(x: edge.x + 100, y: edge.y + 200)
        var machine = GamesRummyTouchMachine()
        machine.down(start, context)
        let step8 = machine.move(finger, context)
        #expect(step8 == .dragBegan)
        let drag = machine.drag!
        #expect(drag.kind == .set(0) && abs(drag.grab.x - (-10 / scale)) < 0.01 && abs(drag.grab.y - 28) < 0.01)
        let pointer = GamesRummyGestureRules.liftedPoint(finger: finger)
        let logical = context.viewport.transform.toLogical(context.inTable(pointer))
        let want = RummyPoint(x: Int((logical.x - drag.grab.x).rounded()), y: Int((logical.y - drag.grab.y).rounded()))
        let action = machine.up(finger, context)
        #expect(action == .moveSet(0, want))
        let applied = Self.apply(action, to: &editor)
        #expect(applied)
        #expect(editor.points[0] != RummyPoint(x: 100, y: 50))
        #expect(editor.melds[0].count == 3, "옮기기가 묶음을 바꿨다")

        var outside = GamesRummyTouchMachine()
        outside.down(start, context)
        let overRack = CGPoint(x: 200, y: context.layout.rack.midY + 48)
        _ = outside.move(overRack, context)
        let step9 = outside.up(overRack, context)
        #expect(step9 == .none)
    }

    @Test("꾹 눌러 묶음 전체를 집어 빈 곳에 놓으면 손잡이와 같은 길(`moveSet`)이다 · 끝 타일이면 가까운 끝까지 쪼갠다")
    func holdOnBoardPicksChunk() {
        var editor = Self.editor()
        let context = Self.context(editor)
        let middle = Self.screen(CGPoint(x: 100 + 40 + 20, y: 78), context)
        let pointer = Self.screen(CGPoint(x: 300, y: 300), context)
        let action = Self.trace(middle, to: Self.finger(under: pointer), context, hold: true)
        guard case .moveSet(0, _) = action else {
            Issue.record("묶음 통째가 moveSet 으로 안 갔다: \(action)")
            return
        }
        let applied = Self.apply(action, to: &editor)
        #expect(applied)
        #expect(editor.melds[0].count == 3)

        var machine = GamesRummyTouchMachine()
        let split = Self.context(Self.editor())
        machine.down(Self.screen(CGPoint(x: 100 + 80 + 20, y: 78), split), split)
        // A3(오른쪽 끝) = 그 타일부터 끝까지 = 한 장.
        let step10 = machine.holdElapsed(split)
        #expect(step10?.ids == [Self.id("A3", in: split.editor!)])
    }

    // MARK: - 좌표 왕복

    @Test("좌표 왕복: 밀고 · 키우고 · 전체 보기 어디서나 그린 타일 자리를 누르면 그 타일이다")
    func hitMatchesDrawnFrames() {
        let editor = Self.editor(farMeldY: 300)
        let base = GamesRummyMatchLayout(size: Self.size).table.size
        var panned = GamesRummyViewport(viewport: base)
        panned.pan(by: CGSize(width: 0, height: -20))
        var zoomed = GamesRummyViewport(viewport: base)
        zoomed.zoom(to: 0.95, anchor: CGPoint(x: 200, y: 100))
        zoomed.pan(by: CGSize(width: -40, height: 30))
        var full = GamesRummyViewport(viewport: base)
        full.toggleFullView()
        for view in [GamesRummyViewport(viewport: base), panned, zoomed, full] {
            let context = Self.context(editor, viewport: view)
            for set in context.scene.melds.indices {
                for slot in context.scene.melds[set].tiles.indices {
                    let frame = context.scene.layout.tileFrame(set: set, tile: slot)!
                    let drawn = view.transform.rect(frame)
                    let point = CGPoint(x: drawn.midX + context.layout.table.minX, y: drawn.midY + context.layout.table.minY)
                    guard context.layout.table.insetBy(dx: 1, dy: 1).contains(point) else { continue }
                    #expect(context.hit(point) == .boardTile(context.scene.melds[set].tiles[slot].id!), "\(view.scale) \(set)/\(slot)")
                    let logical = view.transform.toLogical(context.inTable(point))
                    #expect(abs(logical.x - CGFloat(frame.x + 20)) < 0.01 && abs(logical.y - CGFloat(frame.y + 28)) < 0.01)
                }
            }
        }
        // 기준선: 밀린 보기는 처음 보기와 다른 자리에 그린다.
        #expect(panned.transform.toScreen(CGPoint(x: 800, y: 50)) != GamesRummyViewport(viewport: base).transform.toScreen(CGPoint(x: 800, y: 50)))
    }

    @Test("그린 자리 = 재는 자리: 들어 올림 배율을 빼면 집힌 타일 왼쪽 위가 곧 놓을 자리다(타일 · 손잡이) · 배율은 기준점을 중심으로 키운다")
    func floatingFramesMatchTheDrop() {
        let context = Self.context()
        let start = Self.rackPoint("C2", context)
        var machine = GamesRummyTouchMachine()
        machine.down(start, context)
        _ = machine.holdElapsed(context)
        let finger = Self.finger(under: Self.screen(CGPoint(x: 301, y: 305), context))
        _ = machine.move(finger, context)
        let drag = machine.drag!
        let plain = GamesRummyFloatingLayout.frames(drag, tile: context.viewport.tileSize, tableScale: context.viewport.scale, liftScale: 1)
        let logical = context.viewport.transform.toLogical(context.inTable(plain[0].origin))
        guard case .newMeldAt(let point)? = GamesRummyDropPlanner.target(drag, context) else {
            Issue.record("빈 펠트가 아니다")
            return
        }
        #expect(abs(CGFloat(point.x) - logical.x) <= 1 && abs(CGFloat(point.y) - logical.y) <= 1, "\(point) ≠ \(logical)")
        #expect(plain.count == 3 && abs(plain[1].minX - plain[0].maxX) < 0.001)
        // 1.25 배: 잡은 타일 가운데가 기준점에 그대로 있고 들어 올림이 손 위 48pt 다.
        let lifted = GamesRummyFloatingLayout.frames(drag, tile: context.viewport.tileSize, tableScale: context.viewport.scale)
        #expect(abs(lifted[1].midX - finger.x) < 0.001 && abs(lifted[1].midY - (finger.y - 48)) < 0.001)
        #expect(abs(lifted[1].width - context.viewport.tileSize.width * 1.25) < 0.001)

        // 손잡이.
        let edge = Self.screen(CGPoint(x: 100, y: 78), context)
        var handle = GamesRummyTouchMachine()
        handle.down(CGPoint(x: edge.x - 10, y: edge.y), context)
        _ = handle.move(Self.finger(under: Self.screen(CGPoint(x: 300, y: 300), context)), context)
        let set = handle.drag!
        let frames = GamesRummyFloatingLayout.frames(set, tile: context.viewport.tileSize, tableScale: context.viewport.scale, liftScale: 1)
        let origin = context.viewport.transform.toLogical(context.inTable(frames[0].origin))
        guard case .newMeldAt(let setPoint)? = GamesRummyDropPlanner.target(set, context) else {
            Issue.record("손잡이 놓을 자리 없음")
            return
        }
        #expect(abs(CGFloat(setPoint.x) - origin.x) <= 1 && abs(CGFloat(setPoint.y) - origin.y) <= 1)
    }

    // MARK: - 내 차례 아님

    @Test("내 차례가 아니면 받침대 재배치만: 판 타일은 펠트(밀기) · 받침대 타일을 판에 놓아도 아무 일도 없다 · 받침대 안은 옮겨진다")
    func notMyTurnOnlyRearranges() {
        var editor = Self.editor()
        let context = Self.context(editor, isMyTurn: false)
        let noIDs = context.scene.meldTileIDs.allSatisfy { $0.isEmpty }
        #expect(noIDs, "남의 차례 판 타일에 id 가 있다")
        let board = Self.screen(CGPoint(x: 160, y: 78), context)
        #expect(context.hit(board) == .felt)
        let felt = Self.screen(CGPoint(x: 300, y: 300), context)
        #expect(Self.trace(Self.rackPoint("D9", context), to: Self.finger(under: felt), context) == .none)
        let start = Self.rackPoint("D9", context)
        let target = CGPoint(x: context.layout.rack.minX + context.rack.frame(RummyRackSlot(row: 1, halfCol: 12)).midX,
                             y: context.layout.rack.minY + context.rack.rowCenter(1))
        let action = Self.trace(start, to: Self.finger(under: target), context)
        #expect(action == .moveTiles([Self.id("D9", in: editor)], .rackSlot(RummyRackSlot(row: 1, halfCol: 12))))
        let applied = Self.apply(action, to: &editor)
        #expect(applied)
        #expect(editor.rackLayout.slot(of: Self.id("D9", in: editor)) == RummyRackSlot(row: 1, halfCol: 12))
        // 편집기가 없는 자리(기권)는 받침대도 없다.
        let gone = Self.context(nil, isMyTurn: false)
        #expect(gone.hit(board) == .felt)
    }

    // MARK: - 핀치 · 자동 밀기 · 굳히기

    @Test("핀치 중 한 손가락 끌기 금지: 누르던 타일을 거두고 손 뗄 때까지 무시한다 · 끄는 중이면 핀치를 안 받는다")
    func pinchRules() {
        let context = Self.context()
        let start = Self.rackPoint("C2", context)
        var machine = GamesRummyTouchMachine()
        machine.down(start, context)
        let step11 = machine.beginPinch()
        #expect(step11)
        let step12 = machine.move(CGPoint(x: start.x + 50, y: start.y - 200), context)
        #expect(step12 == .none)
        #expect(machine.drag == nil)
        let step13 = machine.up(CGPoint(x: start.x + 50, y: start.y - 200), context)
        #expect(step13 == .none)
        #expect(machine.isIdle)

        var dragging = GamesRummyTouchMachine()
        dragging.down(start, context)
        _ = dragging.move(CGPoint(x: start.x, y: start.y - 100), context)
        let step14 = dragging.beginPinch()
        #expect(!step14)
        #expect(dragging.drag != nil)

        let model = GamesRummyMatchModel(tableSize: context.layout.table.size)
        let before = model.viewport.scale
        model.pinchChanged(magnification: 1.2, anchor: CGPoint(x: 200, y: 300), context: context)
        #expect(model.viewport.scale > before)
        #expect(model.renderScale == before, "핀치 중에 판 층을 다시 그린다")
        model.pinchEnded(touching: false)
        #expect(model.renderScale == model.viewport.scale, "손을 뗐는데 또렷하게 안 그린다")
        #expect(model.machine.isIdle, "핀치 뒤 다음 손이 막힌다")
    }

    @Test("가장자리 자동 밀기: 판 가장자리 28pt 안에서만 민다 · 놓을 자리가 밀린 판을 따라간다 · 받침대 위에서는 안 민다")
    func edgeAutoPan() {
        let context = Self.context()
        let model = GamesRummyMatchModel(tableSize: context.layout.table.size)
        let table = context.layout.table
        let start = Self.rackPoint("D9", context)
        model.touchChanged(start: start, location: start, context: context)
        // 받침대에서 온 끌기는 판 안쪽에 한 번 들어온 뒤에 민다(`V1017RummyLandscapeTests.edgeArming`).
        model.touchChanged(start: start, location: Self.finger(under: CGPoint(x: table.midX, y: table.midY)), context: context)
        model.touchChanged(start: start, location: Self.finger(under: CGPoint(x: table.midX, y: table.maxY - 10)), context: context)
        let first = model.target
        let y = model.viewport.origin.y
        model.edgeTick(deltaTime: 0.1)
        #expect(abs(model.viewport.origin.y - (y + 40)) < 0.001)
        #expect(model.target != first, "밀렸는데 놓을 자리가 그대로다")
        model.touchChanged(start: start, location: Self.finger(under: CGPoint(x: table.midX, y: table.midY)), context: context)
        let still = model.viewport.origin.y
        model.edgeTick(deltaTime: 0.1)
        #expect(model.viewport.origin.y == still, "가운데인데 밀렸다")
        model.touchChanged(start: start, location: Self.finger(under: CGPoint(x: table.midX, y: context.layout.rack.midY)), context: context)
        model.edgeTick(deltaTime: 0.1)
        #expect(model.viewport.origin.y == still, "받침대 위인데 판이 밀렸다")
        model.cancelTouch()
    }

    @Test("굳히기: 누르는 동안·끄는 동안 칸 크기 변화를 미루고 받침대 줄 수를 묶는다 · 떼면 그때 맞춘다 · 판 변화는 배율을 안 바꾼다")
    func freezeWhileHolding() {
        let context = Self.context()
        let model = GamesRummyMatchModel(tableSize: context.layout.table.size)
        let scale = model.viewport.scale
        let start = Self.rackPoint("C2", context)
        model.touchChanged(start: start, location: start, context: context)
        #expect(model.frozenRows == 2)
        model.tableSizeChanged(CGSize(width: 500, height: 240))
        #expect(model.viewport.scale == scale, "누르는 동안 판이 움직였다")
        model.touchChanged(start: start, location: CGPoint(x: start.x, y: start.y - 100), context: context)
        model.tableSizeChanged(CGSize(width: 480, height: 230))
        #expect(model.viewport.scale == scale, "끄는 동안 판이 움직였다")
        model.touchEnded(at: CGPoint(x: start.x, y: start.y - 100), context: context)
        #expect(model.frozenRows == nil)
        #expect(abs(model.viewport.scale - 0.48) < 0.001, "뗀 뒤에 안 맞췄다")
        #expect(model.renderScale == model.viewport.scale)
        // 빈 펠트 밀기는 굳히지 않는다.
        let felt = Self.screen(CGPoint(x: 300, y: 300), context.with(viewport: model.viewport))
        model.touchChanged(start: felt, location: felt, context: context)
        #expect(model.frozenRows == nil)
        model.touchEnded(at: felt, context: context)
    }

    @Test("끊긴 손: 판이 바뀌거나 시스템이 제스처를 거두면 아무것도 안 놓고 접는다 · 다음 손은 새로 분류된다")
    func cancelledTouch() async {
        let context = Self.context()
        let model = GamesRummyMatchModel(tableSize: context.layout.table.size)
        let start = Self.rackPoint("C2", context)
        model.touchChanged(start: start, location: start, context: context)
        model.touchChanged(start: start, location: CGPoint(x: start.x, y: start.y - 100), context: context)
        #expect(model.drag != nil)
        model.cancelTouch()
        #expect(model.drag == nil && model.draggingIDs.isEmpty && model.machine.isIdle)
        #expect(model.touchEnded(at: start, context: context) == .none)

        // 제스처 수명 표시가 꺼졌는데 onEnded 가 안 왔다.
        model.touchChanged(start: start, location: start, context: context)
        model.touchChanged(start: start, location: CGPoint(x: start.x, y: start.y - 100), context: context)
        model.touchVanished()
        #expect(await baseWaitUntil { model.machine.isIdle }, "쥔 채로 남았다")
        #expect(model.drag == nil)
        // 같은 틈에 onEnded 가 먼저 왔고 그 뒤 새 손이 시작됐으면 새 손을 안 건드린다.
        model.touchChanged(start: start, location: start, context: context)
        model.touchVanished()
        model.touchEnded(at: start, context: context)
        model.touchChanged(start: start, location: start, context: context)
        try? await Task.sleep(for: .milliseconds(120))
        #expect(!model.machine.isIdle, "낡은 거둠이 새 손을 죽였다")
        model.cancelTouch()
    }

    // MARK: - 성능의 값

    /// 관찰 변화 횟수를 잰다(뷰가 다시 그려지는 계기 — 렌더 대신 그 계기를 재는 까닭은 맥 스위트가 폰 뷰를 못 보기 때문이다).
    private func fires(_ read: () -> Void, during work: () -> Void) -> Bool {
        final class Flag: @unchecked Sendable { var fired = false }
        let flag = Flag()
        withObservationTracking {
            read()
        } onChange: {
            flag.fired = true
        }
        work()
        return flag.fired
    }

    @Test("끄는 동안 판 층 입력은 안 바뀐다: 손을 1,000번 움직여도 판을 다시 그리는 계기가 0 이다(떠 있는 타일만 다시 그린다)")
    func fingerDoesNotInvalidateTheBoard() {
        let context = Self.context()
        let model = GamesRummyMatchModel(tableSize: context.layout.table.size)
        let start = Self.rackPoint("C2", context)
        model.touchChanged(start: start, location: start, context: context)
        model.touchChanged(start: start, location: CGPoint(x: start.x, y: start.y - 200), context: context)
        let fired = fires({
            _ = model.draggingIDs
            _ = model.lift
            _ = model.movingSet
            _ = model.renderScale
            _ = model.frozenRows
            _ = model.viewport
        }, during: {
            for step in 0..<1_000 {
                let x = 100 + CGFloat(step % 100)
                model.touchChanged(start: start, location: CGPoint(x: x, y: start.y - 200), context: context)
            }
        })
        #expect(!fired, "손 움직임이 판 층을 다시 그린다")
        // 기준선: 떠 있는 타일은 움직인다.
        let moved = fires({ _ = model.drag }, during: {
            model.touchChanged(start: start, location: CGPoint(x: 150, y: start.y - 190), context: context)
        })
        #expect(moved)
        model.cancelTouch()
    }

    @Test("놓을 자리가 그대로면 미리보기를 안 건드린다(묶음 위에서 손이 떨려도)")
    func previewOnlyOnTargetChange() {
        let context = Self.context()
        let model = GamesRummyMatchModel(tableSize: context.layout.table.size)
        let start = Self.rackPoint("A4", context)
        let over = Self.finger(under: Self.screen(CGPoint(x: 100 + 120 - 6, y: 78), context))
        model.touchChanged(start: start, location: start, context: context)
        model.touchChanged(start: start, location: over, context: context)
        #expect(model.boardPreview != nil)
        let fired = fires({
            _ = model.boardPreview
            _ = model.rackPreview
            _ = model.hoverRefused
        }, during: {
            for step in 0..<20 { model.touchChanged(start: start, location: CGPoint(x: over.x + CGFloat(step % 2), y: over.y), context: context) }
        })
        #expect(!fired)
        model.cancelTouch()
    }

    @Test("모든 칸이 값이 다를 때만 쓴다: 빈 펠트 밀기는 판 층 입력을 안 건드리고 보기만 바꾼다")
    func panTouchesOnlyViewport() {
        let context = Self.context()
        let model = GamesRummyMatchModel(tableSize: context.layout.table.size)
        let felt = Self.screen(CGPoint(x: 300, y: 300), context)
        model.touchChanged(start: felt, location: felt, context: context)
        let fired = fires({
            _ = model.draggingIDs
            _ = model.renderScale
            _ = model.drag
        }, during: {
            model.touchChanged(start: felt, location: CGPoint(x: felt.x, y: felt.y - 40), context: context)
        })
        #expect(!fired)
        #expect(model.viewport.origin.y > 0, "밀리지 않았다")
        model.touchEnded(at: felt, context: context)
    }

    // MARK: - 미리보기

    @Test("미리보기: 붙을 끝 = 자석(맞으면 초록) · 빈 곳 = 점선 · 첫 등록 전 판 묶음은 초록을 거둔다 · 남의 차례는 없다")
    func previews() {
        func drag(_ context: GamesRummyTouchContext, _ face: String, to pointer: CGPoint) -> GamesRummyDrag {
            var machine = GamesRummyTouchMachine()
            let start = Self.rackPoint(face, context)
            machine.down(start, context)
            _ = machine.move(Self.finger(under: pointer), context)
            return machine.drag!
        }
        let context = Self.context()
        let onMeld = drag(context, "A4", to: Self.screen(CGPoint(x: 214, y: 78), context))
        let target = GamesRummyDropPlanner.target(onMeld, context)
        let preview = GamesRummyDropPlanner.boardPreview(onMeld, target: target, context)
        #expect(preview?.targetSet == 0 && preview?.completes == true)

        let felt = drag(context, "D9", to: Self.screen(CGPoint(x: 300, y: 300), context))
        guard case .ghost? = GamesRummyDropPlanner.boardPreview(felt, target: GamesRummyDropPlanner.target(felt, context), context) else {
            Issue.record("빈 곳 점선이 없다")
            return
        }

        let before = Self.context(Self.editor(initialDone: false))
        let early = drag(before, "A4", to: Self.screen(CGPoint(x: 214, y: 78), before))
        #expect(GamesRummyDropPlanner.boardPreview(early, target: GamesRummyDropPlanner.target(early, before), before)?.completes == false,
                "첫 등록 전인데 초록")

        let waiting = Self.context(Self.editor(), isMyTurn: false)
        #expect(GamesRummyDropPlanner.boardPreview(felt, target: .newMeldAt(RummyPoint(x: 0, y: 0)), waiting) == nil)
    }

    @Test("받침대 미리보기: 놓을 자리에 사본을 놓아 본다 — 편집기는 그대로 · 놓은 결과와 같다")
    func rackPreviewEqualsDrop() {
        let editor = Self.editor()
        let context = Self.context(editor)
        let d9 = Self.id("D9", in: editor)
        let over = CGPoint(x: context.layout.rack.minX + context.rack.frame(RummyRackSlot(row: 0, halfCol: 2)).midX,
                           y: context.layout.rack.minY + context.rack.rowCenter(0))
        var machine = GamesRummyTouchMachine()
        let start = Self.rackPoint("D9", context)
        machine.down(start, context)
        _ = machine.move(Self.finger(under: over), context)
        let drag = machine.drag!
        let target = GamesRummyDropPlanner.target(drag, context)
        let preview = GamesRummyDropPlanner.rackPreview(drag, target: target, editor: editor)
        #expect(context.editor == editor)
        var after = editor
        let applied = Self.apply(machine.up(Self.finger(under: over), context), to: &after)
        #expect(applied)
        #expect(preview?.layout == after.rackLayout)
        #expect(preview?.ghosts == [after.rackLayout.slot(of: d9)!])
    }

    // MARK: - 칸 · 글자

    @Test("받침대: 끄는 동안 미리보기가 새 줄을 열어도 칸 안에 담긴다(2줄 칸에 3 · 4줄 — 타일이 맥 산식 2/줄로 준다)")
    func previewRowsFitTheCell() {
        let height = GamesRummyMatchLayout(size: Self.size).rack.height
        let width = GamesRummyMatchLayout(size: Self.size).rack.width
        let two = GamesRummyRackGeometry(size: CGSize(width: width, height: height))
        for rows in [3, 4, 6] {
            let rack = GamesRummyRackGeometry(size: CGSize(width: width, height: height), rowCount: rows)
            let frame = rack.frame(RummyRackSlot(row: rows - 1, halfCol: 0))
            #expect(frame.maxY <= height, "\(rows)줄이 칸 밖 \(frame)")
            #expect(rack.tileSize.width <= two.tileSize.width * 2 / CGFloat(rows) + 0.001, "\(rows)줄 타일이 안 줄었다")
            // 줄이 안 겹친다.
            #expect(rack.rowTop(1) >= rack.rowTop(0) + rack.tileSize.height)
        }
        // 2줄은 위아래 여백이 같고 줄 틈이 설계값이다.
        #expect(abs(two.rowTop(1) - two.rowTop(0) - two.tileSize.height - GamesRummyRackGeometry.rowGap) < 0.001)
        #expect(abs(two.rowTop(0) - (height - two.frame(RummyRackSlot(row: 1, halfCol: 0)).maxY)) < 0.001)
    }

    @Test("상태 줄 서열: 서버 문구 > 내 차례 판정 > 기권 > 남의 차례 · 첫 내림 N/30 · 무효 이유 · 완료 가능")
    func statusLine() {
        var editor = Self.editor(initialDone: false)
        #expect(GamesRummyStatusLine.make(notice: "서버 말", isMyTurn: true, editor: editor, turnName: "구름", mySeatState: .playing)
                == GamesRummyStatusLine(text: "서버 말", tone: .notice))
        let progress = GamesRummyStatusLine.make(notice: nil, isMyTurn: true, editor: editor, turnName: nil, mySeatState: .playing)
        #expect(progress.text.contains("0") && progress.text.contains("30") && progress.tone == .plain)
        let movedEditor = editor.moveBlock([Self.id("A4", in: editor)], to: .meld(0, index: 3))
        #expect(movedEditor)
        let touched = GamesRummyStatusLine.make(notice: nil, isMyTurn: true, editor: editor, turnName: nil, mySeatState: .playing)
        #expect(touched.text == RummyNoticeText.reason(.initialTableTouched, initialPoints: nil))
        // 첫 등록 뒤 무효 묶음 — [완료]가 꺼진 이유.
        var broken = Self.editor()
        let movedBroken = broken.moveBlock([Self.id("D9", in: broken)], to: .newMeldAt(RummyPoint(x: 400, y: 400)))
        #expect(movedBroken)
        let why = GamesRummyStatusLine.make(notice: nil, isMyTurn: true, editor: broken, turnName: nil, mySeatState: .playing)
        #expect(why.text == RummyNoticeText.reason(broken.reason, initialPoints: broken.initialPoints) && why.tone == .plain)
        var done = Self.editor()
        let movedDone = done.moveBlock([Self.id("A4", in: done)], to: .meld(0, index: 3))
        #expect(movedDone)
        #expect(GamesRummyStatusLine.make(notice: nil, isMyTurn: true, editor: done, turnName: nil, mySeatState: .playing).tone == .ready)
        #expect(GamesRummyStatusLine.make(notice: nil, isMyTurn: false, editor: nil, turnName: "구름", mySeatState: .forfeit).text == GamesRummyText.spectating)
        #expect(GamesRummyStatusLine.make(notice: nil, isMyTurn: false, editor: done, turnName: "구름", mySeatState: .playing).text == GamesRummyText.turnOf("구름"))
    }

    @Test("자리: 상대 카드는 내 다음 차례부터 · 기권·빠짐·시간 초과·등록 전 표시 · 남의 패는 장수만")
    func seats() throws {
        func seat(_ number: Int, _ state: RummySeatState, streak: Int = 0, initial: Bool = true) -> RummyMatchSeat {
            var seat = try! JSONDecoder().decode(RummyMatchSeat.self, from: Data("{\"userId\":\"\(UUID().uuidString)\"}".utf8))
            seat.seatNo = number
            seat.state = state
            seat.timeoutStreak = streak
            seat.initialDone = initial
            seat.rackCount = 7
            return seat
        }
        var match = try JSONDecoder().decode(RummyMatchState.self, from: Data("{\"id\":\"\(UUID().uuidString)\"}".utf8))
        match.status = .active
        match.seats = [seat(0, .playing), seat(1, .forfeit), seat(2, .playing, streak: 2, initial: false), seat(3, .dropped)]
        match.mySeatNo = 2
        match.turnSeatNo = 3
        #expect(GamesRummySeats.opponents(match).map(\.seatNo) == [3, 0, 1], "내 다음 차례부터가 아니다")
        #expect(GamesRummySeats.mine(match)?.seatNo == 2)
        #expect(!GamesRummySeats.isTurn(match.seats![3], in: match), "빠진 자리에 차례 링이 돈다")
        #expect(GamesRummySeats.tags(match.seats![1]) == [.forfeit] && GamesRummySeats.isGone(match.seats![1]))
        #expect(GamesRummySeats.tags(match.seats![3]) == [.disconnected])
        #expect(GamesRummySeats.tags(match.seats![2]) == [.timeouts(2), .beforeInitial])
        #expect(GamesRummySeats.tags(match.seats![0]).isEmpty)
        #expect(GamesRummySeatTag.timeouts(2).text == "시간 초과 2/3")
        match.turnStartedMs = 1_000
        match.turnDeadlineMs = 61_000
        #expect(GamesRummySeats.turnTotal(match) == 60)
        match.turnDeadlineMs = nil
        #expect(GamesRummySeats.turnTotal(match) == 60)
    }

    @Test("판 장면: 내 차례 = 편집기(이번에 낸 타일 강조 · 무효 표시) · 남의 차례 = 작업 판(새 면만 강조) · 그 밖 = 확정 판")
    func boardScene() throws {
        var editor = Self.editor()
        let movedEditor = editor.moveBlock([Self.id("D9", in: editor)], to: .newMeldAt(RummyPoint(x: 400, y: 400)))
        #expect(movedEditor)
        let mine = GamesRummyBoardScene.make(match: nil, editor: editor, isMyTurn: true, otherDraft: nil)
        #expect(mine.melds.count == 3 && mine.melds[2].invalid && !mine.melds[0].invalid)
        #expect(mine.melds[2].tiles.first?.highlighted == true && mine.melds[0].tiles.first?.highlighted == false)
        #expect(mine.tileCount == 8)

        var match = try JSONDecoder().decode(RummyMatchState.self, from: Data("{\"id\":\"\(UUID().uuidString)\"}".utf8))
        match.table = [Self.faces("A1", "A2", "A3")]
        let draft = [Self.faces("A1", "A2", "A3", "A4")]
        let other = GamesRummyBoardScene.make(match: match, editor: editor, isMyTurn: false, otherDraft: draft)
        #expect(other.melds[0].tiles.map(\.highlighted) == [false, false, false, true])
        let untouchable = other.melds[0].tiles.allSatisfy { $0.id == nil }
        #expect(untouchable, "남의 작업 판이 만져진다")
        let confirmed = GamesRummyBoardScene.make(match: match, editor: editor, isMyTurn: false, otherDraft: nil)
        #expect(confirmed.melds[0].tiles.count == 3 && !confirmed.melds[0].invalid)
    }
}
