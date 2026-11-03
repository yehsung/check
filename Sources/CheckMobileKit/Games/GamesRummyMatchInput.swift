import CheckCore
import CoreGraphics
import Foundation

// 폰 아잉 큐브 판 화면의 **입력 판정**(설계서 §4 입력). `#if os(iOS)` 밖이다 — 폰 뷰는 맥 스위트가 못 보고 합성 입력도 금지라,
// 끌기가 맞는지는 "손 궤적 → 분류 → 놓을 자리 → 편집기 결과" 를 값으로 재는 것이 유일한 그물이다(`GamesRummyMatchInputTests`).
//
// 화면 전체에 제스처 **하나**(`GamesRummyMatch.swift` 의 입력 층)가 손의 자리만 여기로 넘긴다. 타일마다 제스처를 달지 않는다 —
// 판 타일 100장 이상에서 무겁고 판 밀기와 충돌한다.
//   · `GamesRummyTouchMachine` — 손 하나의 일생(누름 → 8pt 넘게 움직이면 한 장 · 8pt 안에서 0.5초면 묶음째 · 손잡이 · 빈 펠트 밀기).
//   · `GamesRummyDropPlanner` — 놓을 자리 · 미리보기 · 놓은 결과. 맥 `RummyMatchView.resolve`·`boardPreview`·`tileEnded` 와 **같은 갈래**다. 판정은 코어 `RummyDropResolver`·편집기가 한다.
//   · `GamesRummyFloatingLayout` — 집힌 타일의 자리. **그린 자리와 재는 자리가 같다**: 손 위 점(`GamesRummyDrag.pointer` — 판 위에서 48pt)이 놓기 기준이고 그림도 그 점에 선다.

// MARK: - 판에 그릴 값

/// 판에 그릴 것(묶음 · 배치) — 맥 `RummyMatchView.board` 와 같은 세 갈래: 내 차례 = 편집기, 남의 차례 = 그 사람 작업 판, 그 밖 = 확정 판.
package struct GamesRummyBoardScene: Equatable, Sendable {
    package let melds: [RummyBoardMeld]
    package let layout: RummyTableLayout

    package init(melds: [RummyBoardMeld], layout: RummyTableLayout) {
        self.melds = melds
        self.layout = layout
    }

    package static let empty = GamesRummyBoardScene(melds: [], layout: .empty)

    package var meldTileIDs: [[Int]] { melds.map { $0.tiles.compactMap(\.id) } }
    package var tileCount: Int { melds.reduce(0) { $0 + $1.tiles.count } }

    package static func make(match: RummyMatchState?, editor: RummyTurnEditor?, isMyTurn: Bool,
                             otherDraft: [[RummyFace]]?) -> GamesRummyBoardScene {
        func fallback(_ count: Int) -> RummyRect { RummyTableLayout.frame(at: RummyPoint(x: 0, y: 0), tiles: count) }
        if isMyTurn, let editor {
            let layout = editor.tableLayout
            let melds = editor.melds.enumerated().map { index, meld in
                RummyBoardMeld(id: "e\(meld.first?.id ?? -index - 1)",
                               tiles: meld.map { RummyBoardTile(id: $0.id, face: $0.face, highlighted: !editor.isFromTable($0.id)) },
                               frame: layout.frame(of: index) ?? fallback(meld.count),
                               invalid: !editor.analysis(ofMeld: index).valid)
            }
            return GamesRummyBoardScene(melds: melds, layout: layout)
        }
        if let draft = otherDraft {
            // 남의 작업 판 — 확정 판에 없던 면(다중집합 차)을 이번 차례에 낸 타일로 칠한다(표시 전용, 판정 아님).
            let layout = RummyTableLayout(sets: draft, layout: match?.draft?.layout)
            var confirmed: [RummyFace: Int] = [:]
            for face in (match?.table ?? []).joined() { confirmed[face, default: 0] += 1 }
            let keys = RummyBoardMeld.faceKeys(draft)
            let melds = draft.enumerated().map { index, set in
                RummyBoardMeld(id: keys[index], tiles: set.map { face in
                    let left = confirmed[face, default: 0]
                    if left > 0 { confirmed[face] = left - 1 }
                    return RummyBoardTile(id: nil, face: face, highlighted: left == 0)
                }, frame: layout.frame(of: index) ?? fallback(set.count), invalid: !RummyRules.analyze(set).valid)
            }
            return GamesRummyBoardScene(melds: melds, layout: layout)
        }
        let table = match?.table ?? []
        let layout = RummyTableLayout(sets: table, layout: match?.tableLayout)
        let keys = RummyBoardMeld.faceKeys(table)
        let melds = table.enumerated().map { index, set in
            RummyBoardMeld(id: keys[index],
                           tiles: RummyRules.displayOrder(set).map { RummyBoardTile(id: nil, face: $0, highlighted: false) },
                           frame: layout.frame(of: index) ?? fallback(set.count), invalid: false)
        }
        return GamesRummyBoardScene(melds: melds, layout: layout)
    }
}

// MARK: - 손에 든 것

package struct GamesRummyDrag: Equatable, Sendable {
    package enum Kind: Equatable, Sendable {
        case tiles
        /// 손잡이로 묶음 위치 이동.
        case set(Int)
    }

    package enum Surface: Equatable, Sendable { case rack, board }

    package var kind: Kind
    package var tiles: [RummyTile]
    package var grabIndex: Int
    package var finger: CGPoint
    /// 손잡이 끌기: 잡은 자리 − 묶음 왼쪽 위(논리).
    package var grab: CGPoint = .zero
    package var surface: Surface
    /// 손 자리에서 나온 들어 올림(`GamesRummyMatchLayout.fingerLift`).
    package var lift: CGFloat = GamesRummyGestureRules.fingerLift

    package var ids: [Int] { tiles.map(\.id) }
    /// 그린 자리 = 재는 자리. 판 위에서 손 위 48pt.
    package var pointer: CGPoint { GamesRummyGestureRules.liftedPoint(finger: finger, lift: lift) }

    /// 손이 옮겨 갔다.
    package mutating func move(to point: CGPoint, in layout: GamesRummyMatchLayout) {
        finger = point
        lift = layout.fingerLift(atY: point.y)
    }
}

/// 꾹 눌러 들어 올린 것(아직 안 끎).
package struct GamesRummyLift: Equatable, Sendable {
    package let tileID: Int
    package let ids: [Int]
    package let surface: GamesRummyDrag.Surface
}

/// 받침대 위로 끄는 동안의 미리보기 — 같은 놓기를 편집기 사본에 해 본 받침대(= 실제). 이웃이 비켜 서고 점선이 놓일 자리다.
package struct GamesRummyRackPreview: Equatable, Sendable {
    package let layout: RummyRackLayout
    package let ghosts: [RummyRackSlot]
    /// 놓은 뒤 받침대에서 그대로 맞는 덩어리(밑줄 띠).
    package let melds: [RummyRackMeld]
}

/// 놓은 결과 — 화면이 스토어로 옮긴다.
package enum GamesRummyDropAction: Equatable, Sendable {
    case none
    case moveTiles([Int], RummyDropTarget)
    case moveSet(Int, RummyPoint)
    /// 판 출신을 받침대에 놓았다(R-14) — 놓지 않고 받침대를 잠깐 빨갛게.
    case refused
}

/// 판단 재료 한 벌. 화면이 본문에서 한 번 만들어 제스처에 넘기고, 보기(`viewport`)만 모델이 사건마다 채운다 — 본문이 보기를 읽으면 밀 때마다 화면 전체가 다시 그려진다.
package struct GamesRummyTouchContext: Equatable, Sendable {
    package var layout: GamesRummyMatchLayout
    package var rack: GamesRummyRackGeometry
    package var viewport: GamesRummyViewport
    package var scene: GamesRummyBoardScene
    package var editor: RummyTurnEditor?
    /// 내 차례이고 편집기가 있다(놓을 자리 판정 — 아니면 받침대 재배치만).
    package var isMyTurn: Bool
    /// 판 타일을 만질 수 있다(내 차례 · 요청 비행 중 아님).
    package var editable: Bool
    /// 이 값을 만든 차례. 손을 쥔 사이 차례가 바뀌었는지 가른다(`GamesRummyMatchModel.boardChanged`).
    package var turnKey: RummyEditorKey?

    package init(layout: GamesRummyMatchLayout, viewport: GamesRummyViewport? = nil, scene: GamesRummyBoardScene,
                 editor: RummyTurnEditor?, isMyTurn: Bool, editable: Bool, turnKey: RummyEditorKey? = nil) {
        self.layout = layout
        rack = GamesRummyRackGeometry(size: layout.rack.size, rowCount: layout.rackRows)
        self.viewport = viewport ?? GamesRummyViewport(viewport: layout.table.size)
        self.scene = scene
        self.editor = editor
        self.isMyTurn = isMyTurn
        self.editable = editable
        self.turnKey = turnKey
    }

    package var rackLayout: RummyRackLayout { editor?.rackLayout ?? RummyRackLayout() }

    package func hit(_ point: CGPoint) -> GamesRummyHit {
        GamesRummyHitTester.classify(point: point, layout: layout, rack: rack, rackLayout: rackLayout,
                                     canvas: viewport.transform, table: scene.layout,
                                     meldTileIDs: scene.meldTileIDs, editable: editable && editor != nil)
    }

    /// 모델이 사건마다 지금 보기를 채운다.
    package func with(viewport: GamesRummyViewport) -> GamesRummyTouchContext {
        var context = self
        context.viewport = viewport
        return context
    }

    package func tile(_ id: Int) -> RummyTile? {
        guard let editor else { return nil }
        return editor.rack.first { $0.id == id } ?? editor.melds.lazy.compactMap { $0.first { $0.id == id } }.first
    }

    /// 칸 좌표로 옮긴 판 안의 점.
    package func inTable(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - layout.table.minX, y: point.y - layout.table.minY)
    }
}

// MARK: - 손 하나의 일생

/// 손이 닿아서 떨어질 때까지의 상태. 시간은 밖에서 민다(`holdElapsed` — 시험이 0.5초를 기다리지 않게).
package struct GamesRummyTouchMachine: Equatable, Sendable {
    package enum Phase: Equatable, Sendable {
        case idle
        /// 타일을 누르는 중. `picked` = 0.5초를 버텨 들어 올린 묶음.
        case pressing(tileID: Int, surface: GamesRummyDrag.Surface, start: CGPoint, picked: [Int]?)
        case handle(set: Int, start: CGPoint)
        case panning(last: CGPoint)
        case dragging(GamesRummyDrag)
        /// 그 밖에서 시작했거나 핀치로 넘어갔다 — 손을 뗄 때까지 무시한다.
        case ignoring
    }

    package enum Effect: Equatable, Sendable {
        case none
        case pan(CGSize)
        case dragBegan
        case dragMoved
    }

    package private(set) var phase: Phase = .idle

    package init() {}

    package var isIdle: Bool { phase == .idle }

    /// 판·받침대를 쥐고 있다(판 변환·받침대 줄 수를 굳힐 때).
    package var holdsBoard: Bool {
        switch phase {
        case .pressing, .handle, .dragging: return true
        case .idle, .panning, .ignoring: return false
        }
    }

    package var drag: GamesRummyDrag? {
        if case .dragging(let drag) = phase { return drag }
        return nil
    }

    package mutating func down(_ point: CGPoint, _ context: GamesRummyTouchContext) {
        switch context.hit(point) {
        case .rackTile(let id):
            phase = .pressing(tileID: id, surface: .rack, start: point, picked: nil)
        case .boardTile(let id):
            phase = .pressing(tileID: id, surface: .board, start: point, picked: nil)
        case .meldHandle(let set):
            phase = .handle(set: set, start: point)
        case .felt:
            phase = .panning(last: point)
        case .none:
            phase = .ignoring
        }
    }

    package mutating func move(_ point: CGPoint, _ context: GamesRummyTouchContext) -> Effect {
        switch phase {
        case .idle, .ignoring:
            return .none
        case .panning(let last):
            phase = .panning(last: point)
            let delta = CGSize(width: point.x - last.x, height: point.y - last.y)
            return delta == .zero ? .none : .pan(delta)
        case .pressing(let id, let surface, let start, let picked):
            guard Self.distance(point, start) > GamesRummyGestureRules.dragThreshold else { return .none }
            let ids = picked ?? [id]
            let tiles = ids.compactMap(context.tile)
            guard !tiles.isEmpty else {
                phase = .ignoring
                return .none
            }
            phase = .dragging(GamesRummyDrag(kind: .tiles, tiles: tiles, grabIndex: ids.firstIndex(of: id) ?? 0,
                                             finger: point, surface: surface, lift: context.layout.fingerLift(atY: point.y)))
            return .dragBegan
        case .handle(let set, let start):
            guard Self.distance(point, start) > GamesRummyGestureRules.dragThreshold else { return .none }
            guard let editor = context.editor, editor.melds.indices.contains(set),
                  let frame = context.scene.layout.frame(of: set) else {
                phase = .ignoring
                return .none
            }
            let logical = context.viewport.transform.toLogical(context.inTable(start))
            phase = .dragging(GamesRummyDrag(kind: .set(set), tiles: editor.melds[set], grabIndex: 0, finger: point,
                                             grab: CGPoint(x: logical.x - CGFloat(frame.x), y: logical.y - CGFloat(frame.y)),
                                             surface: .board, lift: context.layout.fingerLift(atY: point.y)))
            return .dragBegan
        case .dragging(var drag):
            drag.move(to: point, in: context.layout)
            phase = .dragging(drag)
            return .dragMoved
        }
    }

    /// 0.5초가 지났다. 아직 8pt 안에서 누르고 있으면 묶음째 집는다(받침대 = 이어진 덩어리 · 판 = 가까운 끝까지). 집었으면 그 값.
    package mutating func holdElapsed(_ context: GamesRummyTouchContext) -> GamesRummyLift? {
        guard case .pressing(let id, let surface, let start, nil) = phase, let editor = context.editor else { return nil }
        let ids = surface == .rack ? editor.rackChain(around: id) : editor.meldChunk(for: id)
        guard !ids.isEmpty else { return nil }
        phase = .pressing(tileID: id, surface: surface, start: start, picked: ids)
        return GamesRummyLift(tileID: id, ids: ids, surface: surface)
    }

    /// 손을 뗐다 — 놓은 결과.
    package mutating func up(_ point: CGPoint, _ context: GamesRummyTouchContext) -> GamesRummyDropAction {
        defer { phase = .idle }
        guard case .dragging(var drag) = phase else { return .none }
        drag.move(to: point, in: context.layout)
        return GamesRummyDropPlanner.action(drag, target: GamesRummyDropPlanner.target(drag, context), editor: context.editor)
    }

    package mutating func cancel() {
        phase = .idle
    }

    /// 쥔 것이 이 편집기에 그대로 있는가(같은 차례 안에서 판이 바뀌었을 때 묻는다). `was` = 쥘 때의 편집기 — 손잡이는 묶음 번호만 들고 있어 그 번호의 내용을 견준다.
    package func holdSurvives(in editor: RummyTurnEditor?, was old: RummyTurnEditor?) -> Bool {
        guard let editor else { return false }
        let alive: (Int) -> Bool = { id in
            editor.rack.contains { $0.id == id } || editor.melds.contains { $0.contains { $0.id == id } }
        }
        func sameMeld(_ index: Int, _ ids: [Int]?) -> Bool {
            guard let ids, editor.melds.indices.contains(index) else { return false }
            return editor.melds[index].map(\.id) == ids
        }
        switch phase {
        case .idle, .panning, .ignoring:
            return true
        case .pressing(let id, _, _, let picked):
            return (picked ?? [id]).allSatisfy(alive)
        case .handle(let set, _):
            return sameMeld(set, old.flatMap { $0.melds.indices.contains(set) ? $0.melds[set].map(\.id) : nil })
        case .dragging(let drag):
            if case .set(let index) = drag.kind { return sameMeld(index, drag.ids) }
            return drag.ids.allSatisfy(alive)
        }
    }

    /// 손에 든 것을 거둔다 — **손은 아직 닿아 있다**. 쉬는 상태로 두면 다음 `onChanged` 가 처음 누른 자리(`startLocation`)를 새 판에서 다시 분류해 도약이나 엉뚱한 타일 집기가 난다.
    /// 손을 뗄 때까지 무시한다(`up` · 수명 표시가 쉬는 상태로 되돌린다).
    package mutating func abandon() {
        phase = .ignoring
    }

    /// 핀치가 시작됐다. 끌던 타일이 있으면 핀치를 안 받는다(거짓). 아니면 누르기·밀기를 거두고 손을 뗄 때까지 무시한다 — 핀치 중 한 손가락 끌기 금지.
    package mutating func beginPinch() -> Bool {
        if case .dragging = phase { return false }
        phase = .ignoring
        return true
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}

// MARK: - 놓기

package enum GamesRummyDropPlanner {
    /// 묶음 하나를 통째로 집었으면 그 묶음 번호.
    package static func wholeMeld(_ ids: [Int], editor: RummyTurnEditor?) -> Int? {
        guard let editor else { return nil }
        let set = Set(ids)
        return editor.melds.firstIndex { Set($0.map(\.id)) == set }
    }

    /// 지금 놓으면 어디로 가는가. 받침대 위 = 자리 · 묶음 위 = 끼울 번호 · 빈 펠트 = 새 묶음 · 그 밖 = nil.
    package static func target(_ drag: GamesRummyDrag, _ context: GamesRummyTouchContext) -> RummyDropTarget? {
        switch drag.kind {
        case .set(let index):
            let counts = context.scene.layout.counts
            let count = counts.indices.contains(index) ? counts[index] : drag.tiles.count
            return RummyDropResolver.setTarget(pointer: drag.pointer, grab: drag.grab, tiles: count,
                                               tableRect: context.layout.table, canvas: context.viewport.transform)
                .map { .newMeldAt($0) }
        case .tiles:
            return RummyDropResolver.target(pointer: drag.pointer, grabIndex: drag.grabIndex, count: drag.tiles.count,
                                            rackRect: context.layout.rack, tableRect: context.layout.table,
                                            canvas: context.viewport.transform, table: context.scene.layout,
                                            rack: context.rack, isMyTurn: context.isMyTurn,
                                            skipMeld: wholeMeld(drag.ids, editor: context.editor))
        }
    }

    /// 판 타일을 받침대 위로 끄는 중 — 놓기 거절 표시(R-14).
    package static func refused(_ drag: GamesRummyDrag, target: RummyDropTarget?, editor: RummyTurnEditor?) -> Bool {
        guard let target, RummyStore.isRackTarget(target), let editor else { return false }
        return drag.ids.contains(where: editor.isFromTable)
    }

    /// 놓은 결과(맥 `tileEnded` 와 같은 갈래).
    package static func action(_ drag: GamesRummyDrag, target: RummyDropTarget?, editor: RummyTurnEditor?) -> GamesRummyDropAction {
        guard let target, editor != nil else { return .none }
        switch drag.kind {
        case .set(let index):
            if case .newMeldAt(let point) = target { return .moveSet(index, point) }
            return .none
        case .tiles:
            if refused(drag, target: target, editor: editor) { return .refused }
            if case .newMeldAt(let point) = target, let whole = wholeMeld(drag.ids, editor: editor) {
                return .moveSet(whole, point)
            }
            return .moveTiles(drag.ids, target)
        }
    }

    /// 놓기 미리보기 — 편집기에 "놓으면 어떻게 되는가"를 묻는다(바꾸지 않는다). 놓을 때 부르는 길과 **같은 갈래**:
    /// 손잡이 끌기 · 묶음 통째를 빈 곳에 = `previewMoveSet`, 나머지 = `previewDrop`. 받침대행·거절·남의 차례는 nil.
    package static func boardPreview(_ drag: GamesRummyDrag, target: RummyDropTarget?, _ context: GamesRummyTouchContext) -> RummyBoardPreview? {
        guard context.isMyTurn, let editor = context.editor, let target, !RummyStore.isRackTarget(target) else { return nil }
        let ids = editor.melds.map { $0.map(\.id) }
        let frames = context.scene.layout.frames
        let dragged = Set(drag.ids)
        func moveSet(_ index: Int, _ point: RummyPoint) -> RummyBoardPreview? {
            guard editor.melds.indices.contains(index) else { return nil }
            return .make(editor.previewMoveSet(index, to: point), blockCount: editor.melds[index].count,
                         meldTileIDs: ids, frames: frames, dragged: dragged)
        }
        switch (drag.kind, target) {
        case (.set(let index), .newMeldAt(let point)):
            return moveSet(index, point)
        case (.set, _):
            return nil
        case (.tiles, .newMeldAt(let point)) where wholeMeld(drag.ids, editor: editor) != nil:
            return moveSet(wholeMeld(drag.ids, editor: editor) ?? 0, point)
        case (.tiles, _):
            let preview = RummyBoardPreview.make(editor.previewDrop(drag.ids, to: target), blockCount: drag.ids.count,
                                                 meldTileIDs: ids, frames: frames, dragged: dragged)
            guard !editor.initialDone, let set = preview?.targetSet, editor.melds.indices.contains(set) else { return preview }
            return preview?.beforeInitial(touchesTable: editor.melds[set].contains { editor.isFromTable($0.id) })
        }
    }

    /// 받침대 미리보기(거절이면 nil). 같은 놓기를 사본에 해 본다 — 되먹임이 없게 놓는 판정 기하는 그대로 둔다.
    package static func rackPreview(_ drag: GamesRummyDrag, target: RummyDropTarget?, editor: RummyTurnEditor?) -> GamesRummyRackPreview? {
        guard case .rackSlot(let wanted)? = target, !refused(drag, target: target, editor: editor), var copy = editor,
              copy.moveBlock(drag.ids, to: .rackSlot(wanted)) else { return nil }
        return GamesRummyRackPreview(layout: copy.rackLayout, ghosts: drag.ids.compactMap { copy.rackLayout.slot(of: $0) },
                                     melds: copy.rackMelds)
    }
}

// MARK: - 집힌 타일 자리

package enum GamesRummyFloatingLayout {
    /// 그릴 타일 크기(들어 올림 배율 전): 손잡이 끌기는 판 크기, 나머지는 판 위면 판 크기 · 그 밖이면 받침대 크기.
    package static func tileSize(_ drag: GamesRummyDrag, _ context: GamesRummyTouchContext) -> CGSize {
        if case .set = drag.kind { return context.viewport.tileSize }
        return context.layout.table.contains(drag.pointer) ? context.viewport.tileSize : context.rack.tileSize
    }

    /// 손에 든 타일들의 화면 자리(판 화면 좌표). **기준점 `drag.pointer` 를 중심으로 키운다** — `liftScale` 을 1 로 두면 그 왼쪽 위가 곧 놓을 자리다.
    package static func frames(_ drag: GamesRummyDrag, tile: CGSize, tableScale: CGFloat,
                               liftScale: CGFloat = GamesRummyGestureRules.liftScale) -> [CGRect] {
        let width = tile.width * liftScale, height = tile.height * liftScale
        let origin: CGPoint
        switch drag.kind {
        case .tiles:
            origin = CGPoint(x: drag.pointer.x - (CGFloat(drag.grabIndex) + 0.5) * width, y: drag.pointer.y - height / 2)
        case .set:
            origin = CGPoint(x: drag.pointer.x - drag.grab.x * tableScale * liftScale,
                             y: drag.pointer.y - drag.grab.y * tableScale * liftScale)
        }
        return drag.tiles.indices.map { index in
            CGRect(x: origin.x + CGFloat(index) * width, y: origin.y, width: width, height: height)
        }
    }
}

// MARK: - 자리 · 상태 줄

/// 자리 하나에 붙는 표시. **서버가 말한 것만** — 남의 패는 장수뿐이다(추측 표시 금지).
package enum GamesRummySeatTag: Equatable, Sendable {
    case forfeit
    /// 판이 시작될 때 90초 넘게 안 보여 빠진 자리(`dropped`) · 나간 자리(`left`). 판 중 끊김 기권은 서버 state 에 사유가 안 실려 `forfeit` 으로 보인다.
    case disconnected
    case beforeInitial
    case timeouts(Int)

    package var text: String {
        switch self {
        case .forfeit: return GamesRummyText.forfeitTag
        case .disconnected: return GamesRummyText.disconnectedTag
        case .beforeInitial: return GamesRummyText.beforeInitial
        case .timeouts(let streak): return GamesRummyText.timeouts(streak)
        }
    }
}

package enum GamesRummySeats {
    /// 상대 카드 — 내 다음 차례부터. 자리 번호 없는 사람(초대만 받은 사람)은 판에 없다.
    package static func opponents(_ match: RummyMatchState) -> [RummyMatchSeat] {
        let seats = (match.seats ?? []).filter { $0.seatNo != nil }
        let order = RummySeatArrangement.arrange(seatNos: seats.compactMap(\.seatNo), mine: match.mySeatNo).turnOrder
        return order.compactMap { number in seats.first { $0.seatNo == number } }
    }

    package static func mine(_ match: RummyMatchState) -> RummyMatchSeat? {
        guard let mine = match.mySeatNo else { return nil }
        return match.seats?.first { $0.seatNo == mine }
    }

    package static func turnSeat(_ match: RummyMatchState) -> RummyMatchSeat? {
        guard let turn = match.turnSeatNo else { return nil }
        return match.seats?.first { $0.seatNo == turn }
    }

    package static func isTurn(_ seat: RummyMatchSeat, in match: RummyMatchState) -> Bool {
        seat.seatNo == match.turnSeatNo && seat.state == .playing && match.status == .active
    }

    package static func isGone(_ seat: RummyMatchSeat) -> Bool {
        seat.state == .forfeit || seat.state == .dropped || seat.state == .left
    }

    package static func tags(_ seat: RummyMatchSeat) -> [GamesRummySeatTag] {
        switch seat.state {
        case .forfeit: return [.forfeit]
        case .dropped, .left: return [.disconnected]
        default: break
        }
        var tags: [GamesRummySeatTag] = []
        if let streak = seat.timeoutStreak, streak > 0 { tags.append(.timeouts(streak)) }
        if seat.initialDone == false { tags.append(.beforeInitial) }
        return tags
    }

    /// 이번 차례 전체 시간(초).
    package static func turnTotal(_ match: RummyMatchState) -> TimeInterval {
        guard let start = match.turnStartedMs, let end = match.turnDeadlineMs, end > start else { return 60 }
        return (end - start) / 1000
    }
}

/// 상태 줄 한 줄 — 서버·판정 문구는 스토어 `notice`, 내 차례 글자는 `myTurnStatus`(첫 등록 진행 · [완료]가 꺼진 이유). 맥 `statusText` 와 같은 서열.
package struct GamesRummyStatusLine: Equatable, Sendable {
    package enum Tone: Equatable, Sendable { case notice, ready, plain, quiet }

    package let text: String
    package let tone: Tone
    /// 내 시간 초과 연속 횟수(내 자리가 playing 일 때만). 상태 글자와 따로 위험 색으로 늘 보인다 — 다음 초과면 기권인데 글자 서열에 밀려 안 보이면 안 된다.
    package var warning: String? = nil

    /// `engaged` = 이 기기가 손댄 판(앱을 내리면 기권될 수 있는 기기). 남의 차례 줄은 상태 줄 꼬리(`GamesRummyStatusTail`)가 이미 '누구 차례'를 말하므로, 이 기기엔 90초 규칙을 말한다(체스·테트리스 판의 상시 안내와 같은 자리).
    package static func make(notice: String?, isMyTurn: Bool, editor: RummyTurnEditor?, turnName: String?,
                             mySeatState: RummySeatState?, myTimeoutStreak: Int? = nil, engaged: Bool = false) -> GamesRummyStatusLine {
        var line = base(notice: notice, isMyTurn: isMyTurn, editor: editor, turnName: turnName, mySeatState: mySeatState, engaged: engaged)
        if mySeatState == .playing, let streak = myTimeoutStreak, streak > 0 { line.warning = GamesRummyText.timeouts(streak) }
        return line
    }

    private static func base(notice: String?, isMyTurn: Bool, editor: RummyTurnEditor?, turnName: String?,
                             mySeatState: RummySeatState?, engaged: Bool) -> GamesRummyStatusLine {
        if let notice { return GamesRummyStatusLine(text: notice, tone: .notice) }
        if isMyTurn, let editor {
            return GamesRummyStatusLine(text: GamesRummyText.myTurnStatus(editor), tone: editor.canSubmit ? .ready : .plain)
        }
        if mySeatState == .forfeit { return GamesRummyStatusLine(text: GamesRummyText.spectating, tone: .quiet) }
        if engaged, mySeatState == .playing { return GamesRummyStatusLine(text: GamesRummyText.backgroundWarning, tone: .quiet) }
        if let turnName { return GamesRummyStatusLine(text: GamesRummyText.turnOf(turnName), tone: .quiet) }
        return GamesRummyStatusLine(text: "", tone: .quiet)
    }
}

/// 상태 줄 오른쪽 작은 글자 — 직전 사건 · 남의 차례(작업 중이면 '놓는 중'). 판 위에 띄우면 낮은 칸에서 타일을 가린다.
package struct GamesRummyStatusTail: Equatable, Sendable {
    package let lastEvent: String?
    /// 상태 글자가 이미 같은 말이면 비운다.
    package let turn: String?
    package let isPlacing: Bool

    package static func make(match: RummyMatchState, isMyTurn: Bool, hasOtherDraft: Bool, line: GamesRummyStatusLine) -> GamesRummyStatusTail {
        let last = match.lastEvent.flatMap { event in
            GamesRummyText.lastEvent(event, name: match.seats?.first { $0.seatNo == event.seatNo }?.displayName)
        }
        var turn: String?
        if !isMyTurn, let name = GamesRummySeats.turnSeat(match)?.displayName {
            let text = hasOtherDraft ? GamesRummyText.placing(name) : GamesRummyText.turnOf(name)
            if text != line.text { turn = text }
        }
        return GamesRummyStatusTail(lastEvent: last, turn: turn, isPlacing: hasOtherDraft)
    }
}
