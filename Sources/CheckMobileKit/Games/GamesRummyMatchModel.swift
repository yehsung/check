import CheckCore
import CoreGraphics
import Foundation
import Observation

/// 판 화면의 손 상태 한 곳. 화면 전체 제스처 하나가 사건을 여기로 넘기고, 뷰는 **자기가 쓰는 값만** 읽는다 — 그래서 손이 움직여도 판이 다시 그려지지 않는다:
///   · 손가락 자리(`drag`)는 떠 있는 타일 잎 뷰만 읽는다(사건마다 바뀐다).
///   · 놓을 자리에서 나온 값(`target`·`boardPreview`·`rackPreview`·`hoverRefused`)은 **자리가 바뀔 때만** 쓴다(타일 하나를 끄는 동안 대부분 그대로다).
///   · 판 층의 입력(`draggingIDs`·`lift`·`movingSet`·`renderScale`)은 끌기가 시작·끝날 때만 바뀐다.
/// `@Observable` 은 값이 같아도 쓰면 알리므로 전부 값이 다를 때만 쓴다.
///
/// 판 변환을 굳힌다: 누르는 동안·끄는 동안 칸 크기 변화를 미루고(`pendingTableSize`) 받침대 줄 수를 묶는다(`frozenRows`). 손 아래 판이 움직이면 안 된다(맥 교훈). 가장자리 자동 밀기만 예외다 — 사람이 민 것이다.
/// 놓은 뒤에도 같다: 차례 안에서는 줄 수가 줄지 않는다(`rackRows`) — 셋째 줄 마지막 타일을 놓는 순간 칸이 늘어 배율이 바뀌면 방금 놓은 타일째 판이 움직인다.
@MainActor
@Observable
package final class GamesRummyMatchModel {
    package private(set) var viewport: GamesRummyViewport
    /// 판 층을 그린 배율. 핀치 중에는 그대로 두고 층을 통째로 키운다(100장을 프레임마다 다시 그리지 않게) — 손을 떼면 그 배율로 또렷하게 다시 그린다.
    package private(set) var renderScale: CGFloat
    package private(set) var drag: GamesRummyDrag?
    package private(set) var draggingIDs: Set<Int> = []
    package private(set) var lift: GamesRummyLift?
    package private(set) var movingSet: Int?
    package private(set) var target: RummyDropTarget?
    package private(set) var boardPreview: RummyBoardPreview?
    package private(set) var rackPreview: GamesRummyRackPreview?
    package private(set) var hoverRefused = false
    /// 놓기를 거절했다 — 받침대 빨간 표시(0.6초).
    package private(set) var refusedFlash = false
    package private(set) var frozenRows: Int?
    /// 햅틱 계기(묶음째 집음 · 거절).
    package private(set) var liftSerial = 0
    package private(set) var refuseSerial = 0

    @ObservationIgnored package private(set) var machine = GamesRummyTouchMachine()
    @ObservationIgnored package private(set) var pendingTableSize: CGSize?
    @ObservationIgnored private var pinchBase: CGFloat?
    @ObservationIgnored private var context: GamesRummyTouchContext?
    @ObservationIgnored private var touchToken = 0
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private var edgeTask: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    /// 방금 손으로 놓은 타일 — 옛 자리에서 날아오지 않게 판 변화 모션의 짝짓기에서 뺀다(맥 `recentDrop` 과 같다).
    @ObservationIgnored package private(set) var recentDropIDs: Set<Int> = []
    /// 그 타일을 손이 놓은 자리(논리 좌표) — 들어갈 자리가 다르면 여기서 미끄러진다(맥 `land`).
    @ObservationIgnored package private(set) var recentDropOrigins: [Int: CGPoint] = [:]
    /// 이번 차례에 판 칸을 정한 받침대 줄 수.
    @ObservationIgnored private var heldRows: (turnKey: String?, rows: Int)?

    package init(tableSize: CGSize = CGSize(width: 393, height: 469)) {
        let view = GamesRummyViewport(viewport: tableSize)
        viewport = view
        renderScale = view.scale
    }

    private func withViewport(_ base: GamesRummyTouchContext) -> GamesRummyTouchContext {
        base.with(viewport: viewport)
    }

    // MARK: 손

    /// 제스처의 `onChanged`. 손이 새로 닿았으면(기계가 쉬는 중) 시작 자리로 분류한다.
    package func touchChanged(start: CGPoint, location: CGPoint, context base: GamesRummyTouchContext,
                              holdDelay: TimeInterval = GamesRummyGestureRules.liftDelay) {
        let context = withViewport(base)
        self.context = context
        if machine.isIdle {
            touchToken += 1
            recentDropIDs = []
            recentDropOrigins = [:]
            machine.down(start, context)
            if machine.holdsBoard { frozenRows = base.layout.rackRows }
            if case .pressing = machine.phase { startHoldTimer(holdDelay) }
        }
        switch machine.move(location, context) {
        case .none:
            break
        case .pan(let delta):
            viewport.pan(by: delta)
        case .dragBegan:
            holdTask?.cancel()
            lift = nil
            let drag = machine.drag
            draggingIDs = Set(drag?.ids ?? [])
            if case .set(let index)? = drag?.kind { movingSet = index }
            startEdgeLoop()
            refresh(context)
        case .dragMoved:
            refresh(context)
        }
    }

    /// 제스처의 `onEnded`. 결과는 화면이 `apply` 로 스토어에 옮긴다.
    @discardableResult
    package func touchEnded(at location: CGPoint, context base: GamesRummyTouchContext) -> GamesRummyDropAction {
        let context = withViewport(base)
        var released = machine.drag
        released?.finger = location
        let action = machine.up(location, context)
        switch action {
        case .moveTiles(let ids, _):
            recentDropIDs = Set(ids)
            recentDropOrigins = released.map { Self.dropOrigins($0, context) } ?? [:]
        case .moveSet(let index, _):
            recentDropIDs = Set(base.scene.meldTileIDs.indices.contains(index) ? base.scene.meldTileIDs[index] : [])
            recentDropOrigins = released.map { Self.dropOrigins($0, context) } ?? [:]
        case .none, .refused:
            break
        }
        tearDown()
        if action == .refused { flashRefused() }
        return action
    }

    /// 손을 놓은 자리(타일 왼쪽 위, 논리 좌표). 떠 있는 타일과 같은 기준점에서 나온다. 받침대 위에서 놓았으면 값은 있어도 판에 그 타일이 없어 쓰이지 않는다.
    private static func dropOrigins(_ drag: GamesRummyDrag, _ context: GamesRummyTouchContext) -> [Int: CGPoint] {
        let frames = GamesRummyFloatingLayout.frames(drag, tile: context.viewport.tileSize, tableScale: context.viewport.scale, liftScale: 1)
        return Dictionary(zip(drag.ids, frames.map { context.viewport.transform.toLogical(context.inTable($0.origin)) })) { first, _ in first }
    }

    /// 시스템이 제스처를 거뒀다(손이 사라졌다) — 아무것도 안 놓고 접는다. 함께 사라진 핀치도 푼다: 취소된 `MagnifyGesture` 는 `onEnded` 를 안 부른다.
    package func cancelTouch() {
        machine.cancel()
        tearDown()
        endPinch()
    }

    /// 판이 바뀌었다(seq 상승). **손은 아직 닿아 있을 수 있다.**
    /// · 판 밀기는 그대로 둔다(타일을 쥔 게 아니다).
    /// · 같은 차례이고 쥔 타일이 편집기에 그대로면 둔다 — 남이 기권해 seq 만 오른 경우다. 꾹 눌러 집은 묶음이 풀리면 안 된다.
    /// · 차례가 바뀌었거나 쥔 id · 묶음이 사라졌으면 낡았다(새 차례는 id 를 다시 매긴다) — 거두고 손을 뗄 때까지 무시한다(`abandon`). 쉬는 상태로 두면 다음 사건이 처음 누른 자리를 새 판에서 다시 집는다.
    package func boardChanged(editor: RummyTurnEditor?, turnKey: RummyEditorKey?) {
        guard machine.holdsBoard else { return }
        if turnKey == context?.turnKey, machine.holdSurvives(in: editor, was: context?.editor) { return }
        machine.abandon()
        tearDown()
    }

    /// 판 칸을 정할 받침대 줄 수. 손이 닿은 동안은 `frozenRows`, 그 밖에는 **차례 안에서 줄지 않는다** — 줄이 줄면 칸이 늘어 기본 배율이 저절로 바뀐다(판 위 타일이 최대 약 40pt 움직인다). 차례가 바뀌면 그때 맞춘다.
    /// 본문이 부른다. 관찰 밖 값이라 다시 그리기를 부르지 않는다.
    package func rackRows(editorRows: Int, turnKey: String?) -> Int {
        if let frozenRows { return frozenRows }
        let rows = heldRows.map { $0.turnKey == turnKey ? max($0.rows, editorRows) : editorRows } ?? editorRows
        heldRows = (turnKey, rows)
        return rows
    }

    /// 손이 판을 쥐고 있다 — 동작 줄을 끈다. 다른 손가락의 [되돌리기]·[777|789] 는 seq 를 안 올려서, 그대로 두면 쥔 묶음 번호가 낡은 채 다른 묶음이 옮겨진다.
    package var locksActions: Bool { frozenRows != nil }

    /// 제스처 수명 표시가 꺼졌다. `onEnded` 가 같은 틈에 먼저 돌 수 있어 조금 뒤 같은 손일 때만 거둔다(끝나지 않은 손이 타일을 쥔 채 · 핀치가 열린 채 남지 않게).
    package func touchVanished() {
        let token = touchToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, self.touchToken == token, !self.machine.isIdle || self.pinchBase != nil else { return }
            self.cancelTouch()
        }
    }

    private func tearDown() {
        holdTask?.cancel()
        holdTask = nil
        edgeTask?.cancel()
        edgeTask = nil
        if drag != nil { drag = nil }
        if !draggingIDs.isEmpty { draggingIDs = [] }
        if lift != nil { lift = nil }
        if movingSet != nil { movingSet = nil }
        if target != nil { target = nil }
        if boardPreview != nil { boardPreview = nil }
        if rackPreview != nil { rackPreview = nil }
        if hoverRefused { hoverRefused = false }
        if frozenRows != nil { frozenRows = nil }
        if let size = pendingTableSize {
            pendingTableSize = nil
            tableSizeChanged(size)
        }
    }

    /// 손가락이나 보기가 움직인 뒤 파생 값을 맞춘다. 놓을 자리가 그대로면 미리보기를 다시 묻지 않는다.
    private func refresh(_ base: GamesRummyTouchContext) {
        guard let moved = machine.drag else { return }
        drag = moved
        let context = withViewport(base)
        let next = GamesRummyDropPlanner.target(moved, context)
        guard next != target else { return }
        target = next
        let preview = GamesRummyDropPlanner.boardPreview(moved, target: next, context)
        if preview != boardPreview { boardPreview = preview }
        let rack = GamesRummyDropPlanner.rackPreview(moved, target: next, editor: context.editor)
        if rack != rackPreview { rackPreview = rack }
        let refused = GamesRummyDropPlanner.refused(moved, target: next, editor: context.editor)
        if refused != hoverRefused { hoverRefused = refused }
    }

    // MARK: 0.5초 · 가장자리

    private func startHoldTimer(_ delay: TimeInterval) {
        holdTask?.cancel()
        let token = touchToken
        holdTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.touchToken == token else { return }
            self.holdElapsed()
        }
    }

    /// 0.5초가 지났다(시험이 직접 밟는다).
    package func holdElapsed() {
        guard let context, let picked = machine.holdElapsed(withViewport(context)) else { return }
        lift = picked
        liftSerial += 1
    }

    private func startEdgeLoop() {
        edgeTask?.cancel()
        edgeTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled, let self else { return }
                self.edgeTick(deltaTime: 0.016)
            }
        }
    }

    /// 끄는 중 기준점이 판 가장자리 28pt 안이면 민다(동작 줄이기여도 켠다 — 꾸밈이 아니라 끌기 기능이다). 보기가 바뀌었으니 놓을 자리를 다시 묻는다.
    package func edgeTick(deltaTime: TimeInterval) {
        guard let context, let moved = machine.drag, context.layout.table.contains(moved.pointer) else { return }
        if viewport.edgePan(pointer: context.inTable(moved.pointer), deltaTime: deltaTime) { refresh(context) }
    }

    // MARK: 보기

    package func tableSizeChanged(_ size: CGSize) {
        guard !machine.holdsBoard else {
            pendingTableSize = size
            return
        }
        guard size != viewport.viewport, size.width > 0, size.height > 0 else { return }
        viewport.resize(to: size)
        if renderScale != viewport.scale { renderScale = viewport.scale }
    }

    package func toggleFullView() {
        guard !machine.holdsBoard else { return }
        viewport.toggleFullView()
        renderScale = viewport.scale
    }

    package func reveal(_ side: GamesRummyViewport.Side, frames: [RummyRect]) {
        viewport.reveal(side, frames: frames)
    }

    package func pinchChanged(magnification: CGFloat, anchor: CGPoint, context base: GamesRummyTouchContext) {
        pinch(magnification: magnification, tableAnchor: base.inTable(anchor))
    }

    /// 핀치 — 기준점은 판 칸 좌표다(결과의 읽기 전용 판은 판 화면 칸 자리를 안 쓴다).
    package func pinch(magnification: CGFloat, tableAnchor: CGPoint) {
        if pinchBase == nil {
            guard machine.beginPinch() else { return }
            tearDown()
            pinchBase = viewport.scale
        }
        guard let pinchBase else { return }
        viewport.zoom(to: pinchBase * magnification, anchor: tableAnchor)
    }

    /// 읽기 전용 판(결과의 [최종 판]) 밀기 — 타일을 집지 않으니 손 기계를 안 거친다. 핀치 중에는 안 민다.
    package func readOnlyPan(by delta: CGSize) {
        guard pinchBase == nil, delta != .zero else { return }
        viewport.pan(by: delta)
    }

    /// 핀치 끝. `touching` = 아직 손이 닿아 있다(떼면 기계가 쉰다 — 드래그가 시작조차 못 했으면 여기서 푼다).
    package func pinchEnded(touching: Bool) {
        guard pinchBase != nil else { return }
        endPinch()
        if !touching { machine.cancel() }
    }

    /// 열린 핀치를 닫고 흐린 배율을 또렷하게 맞춘다. 안 닫으면 다음 핀치가 낡은 기준에서 튀고 읽기 전용 밀기가 죽는다.
    private func endPinch() {
        pinchBase = nil
        if renderScale != viewport.scale { renderScale = viewport.scale }
    }

    // MARK: 거절

    private func flashRefused() {
        refuseSerial += 1
        refusedFlash = true
        flashTask?.cancel()
        flashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.refusedFlash = false
        }
    }

    // MARK: 스토어로

    package static func apply(_ action: GamesRummyDropAction, to store: RummyStore) {
        switch action {
        case .none, .refused:
            break
        case .moveTiles(let ids, let target):
            store.moveTiles(ids, to: target)
        case .moveSet(let index, let point):
            store.moveSet(index, to: point)
        }
    }
}

#if DEBUG
extension GamesRummyMatchModel {
    /// 데모 장면 전용: 손 궤적을 **실제 사건 길로** 밟아 끌기 도중 모습을 세운다(합성 입력 금지 — 렌더만, 손을 떼지 않는다). Release 에 없다.
    package func playDemo(_ touch: MobileDemoRummyRoute.DemoTouch, context base: GamesRummyTouchContext) {
        let context = withViewport(base)
        guard let editor = context.editor else { return }
        func rackTile(_ face: String) -> CGPoint? {
            guard let tile = editor.rack.first(where: { $0.face.text == face }),
                  let slot = editor.rackLayout.slot(of: tile.id) else { return nil }
            let frame = context.rack.frame(slot)
            return CGPoint(x: frame.midX + context.layout.rack.minX, y: frame.midY + context.layout.rack.minY)
        }
        func screen(logical: CGPoint) -> CGPoint {
            let local = context.viewport.transform.toScreen(logical)
            return CGPoint(x: local.x + context.layout.table.minX, y: local.y + context.layout.table.minY)
        }
        /// 손 위 48pt 점이 `pointer` 에 오는 손 자리.
        func finger(under pointer: CGPoint) -> CGPoint { CGPoint(x: pointer.x, y: pointer.y + GamesRummyGestureRules.fingerLift) }
        func press(_ start: CGPoint) { touchChanged(start: start, location: start, context: base, holdDelay: 3_600) }
        func travel(_ start: CGPoint, to location: CGPoint) { touchChanged(start: start, location: location, context: base) }
        switch touch {
        case .lift(let face):
            guard let start = rackTile(face) else { return }
            press(start)
            holdElapsed()
        case .rackToMeld(let face, let meld):
            guard let start = rackTile(face), let frame = context.scene.layout.frame(of: meld) else { return }
            press(start)
            travel(start, to: finger(under: screen(logical: CGPoint(x: CGFloat(frame.maxX) - 6, y: CGFloat(frame.y) + 28))))
        case .rackToFelt(let face, let x, let y):
            guard let start = rackTile(face) else { return }
            press(start)
            travel(start, to: finger(under: screen(logical: CGPoint(x: x, y: y))))
        case .chainToFelt(let face, let x, let y):
            guard let start = rackTile(face) else { return }
            press(start)
            holdElapsed()
            travel(start, to: finger(under: screen(logical: CGPoint(x: x, y: y))))
        case .boardToRack(let face):
            guard let (set, index) = editor.melds.enumerated().lazy.compactMap({ set, meld in
                meld.firstIndex { $0.face.text == face }.map { (set, $0) }
            }).first, let frame = context.scene.layout.tileFrame(set: set, tile: index) else { return }
            let start = screen(logical: CGPoint(x: CGFloat(frame.x) + 20, y: CGFloat(frame.y) + 28))
            press(start)
            travel(start, to: finger(under: CGPoint(x: context.layout.rack.midX, y: context.layout.rack.midY)))
        case .handle(let set, let x, let y):
            guard let frame = context.scene.layout.frame(of: set) else { return }
            let start = screen(logical: CGPoint(x: frame.x, y: frame.y + 28))
            let handle = CGPoint(x: start.x - 10, y: start.y)
            press(handle)
            travel(handle, to: finger(under: screen(logical: CGPoint(x: x, y: y))))
        }
    }
}
#endif
