import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 판·결과 (설계서 §5)
//
// 판 = 위 자리 띠(얼굴 · 이름 · 랙 장수 · '등록 전' · 차례 링과 남은 초 · 더미 · 판돈/분배) / 가운데 판(세트를 줄바꿈 흐름으로 ·
// 무효 세트 빨간 테두리 · 이번 차례 낸 타일 노란 링 · 남의 차례면 그 사람 작업 판과 'OO님이 놓는 중') / 아래 내 랙 2줄
// (넘치면 가로 스크롤) + [되돌리기] [777] [789] [뽑기|넘기기] [완료] · 상태 줄.
//
// ── 끌기 ──
// 체스 판처럼 `DragGesture` 하나로 받는다(키 창에서 확실히 도는 길 — `.draggable` 은 끌기 세션이 앱 밖 페이스트보드를
// 거쳐 놓을 자리 판정이 늦고, 놓기 거절 표시를 그릴 틈이 없다). 좌표는 판 화면 전체의 이름 붙은 좌표계 하나
// (`RummyMatchView.space`)에서 재고, 놓을 자리는 **순수 기하**(`RummyBoardGeometry`·`RummyRackGeometry`·`RummyDropResolver`)가
// 정한다 — 그리는 자리와 놓는 자리가 한 산식에서 나온다(시험이 그 산식을 되묻는다).
//   · 놓을 자리: 세트 위(타일 사이 = 끼울 자리) · 빈 곳(새 세트) · 랙(끼울 자리). 세트 사이 틈은 가까운 세트의 끝으로 간다.
//   · 판에 있던 타일은 랙으로 안 간다 — 랙 위에서 빨간 테두리(놓기 거절 표시), 놓으면 제자리. 판단은 `editor.isFromTable`.
//   · 내 차례가 아니면 랙 안 재배치만(판 타일은 집히지 않고, 랙 타일은 랙에만 놓인다).
//   · 끼울 자리 번호(`index`)는 **끌던 타일을 뺀 배열 기준**이다(그 자리에 놓인 뒤의 위치).

// MARK: - 순수 기하

/// 판(작업 판) 기하 — 세트를 왼쪽 위부터 줄바꿈 흐름으로 놓는다. 좌표는 판 **내용** 좌표(여백 안쪽 원점).
struct RummyBoardGeometry: Equatable {
    static var tile: CGSize { RummyTileSize.table.size }
    static let tileGap: CGFloat = 2
    static let meldPadding: CGFloat = 5
    static let meldSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 10
    static var meldHeight: CGFloat { tile.height + meldPadding * 2 }

    let counts: [Int]
    let width: CGFloat
    let meldFrames: [CGRect]
    /// 새 세트 자리(끌 때 점선으로 보이는 빈 세트) — 마지막 세트 뒤.
    let newMeldFrame: CGRect

    static func meldWidth(_ count: Int) -> CGFloat {
        meldPadding * 2 + CGFloat(count) * tile.width + CGFloat(max(0, count - 1)) * tileGap
    }

    init(counts: [Int], width: CGFloat) {
        self.counts = counts
        self.width = width
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0
        func place(_ w: CGFloat) -> CGRect {
            if x > 0, x + w > width {
                x = 0
                y += Self.meldHeight + Self.rowSpacing
            }
            let rect = CGRect(x: x, y: y, width: w, height: Self.meldHeight)
            x += w + Self.meldSpacing
            return rect
        }
        for count in counts { frames.append(place(Self.meldWidth(max(1, count)))) }
        meldFrames = frames
        newMeldFrame = place(Self.meldWidth(2))
    }

    /// 세트를 다 담는 높이(새 세트 자리 포함).
    var contentHeight: CGFloat { newMeldFrame.maxY }

    func tileFrame(meld: Int, index: Int) -> CGRect {
        let origin = meldFrames[meld].origin
        return CGRect(x: origin.x + Self.meldPadding + CGFloat(index) * (Self.tile.width + Self.tileGap),
                      y: origin.y + Self.meldPadding, width: Self.tile.width, height: Self.tile.height)
    }

    /// 판 내용 좌표 `p` 에 놓으면 어느 세트의 몇 번째인가. 세트 틀을 틈의 절반만큼 넓혀 잰다(세트 사이 틈 = 가까운 세트).
    /// 끌던 타일이 같은 세트에 있으면 그 타일을 빼고 센다. nil = 세트 밖(빈 곳 → 새 세트).
    func hit(_ p: CGPoint, excluding: (meld: Int, index: Int)? = nil) -> (meld: Int, index: Int)? {
        for (meld, frame) in meldFrames.enumerated() {
            let zone = frame.insetBy(dx: -Self.meldSpacing / 2, dy: -Self.rowSpacing / 2)
            guard zone.contains(p) else { continue }
            var index = 0
            for i in 0..<counts[meld] {
                if let excluding, excluding.meld == meld, excluding.index == i { continue }
                if tileFrame(meld: meld, index: i).midX < p.x { index += 1 }
            }
            return (meld, index)
        }
        return nil
    }
}

/// 랙 기하 — 두 줄, 첫 줄을 먼저 채운다. 보이는 폭에 안 들면 한 줄 칸 수를 늘려 가로로 넘친다(스크롤).
struct RummyRackGeometry: Equatable {
    static var tile: CGSize { RummyTileSize.rack.size }
    static let gap: CGFloat = 4
    static let rowSpacing: CGFloat = 6
    static let rows = 2
    static var pitch: CGFloat { tile.width + gap }

    let count: Int
    /// 한 줄 칸 수.
    let perRow: Int

    /// 보이는 폭에 드는 한 줄 칸 수.
    static func capacity(viewportWidth: CGFloat) -> Int {
        max(1, Int((viewportWidth + gap) / pitch))
    }

    init(count: Int, viewportWidth: CGFloat) {
        self.count = count
        perRow = max(Self.capacity(viewportWidth: viewportWidth), (count + Self.rows - 1) / Self.rows)
    }

    var contentWidth: CGFloat { CGFloat(perRow) * Self.pitch - Self.gap }
    var contentHeight: CGFloat { CGFloat(Self.rows) * Self.tile.height + CGFloat(Self.rows - 1) * Self.rowSpacing }

    func frame(_ index: Int) -> CGRect {
        let row = index / perRow, column = index % perRow
        return CGRect(x: CGFloat(column) * Self.pitch, y: CGFloat(row) * (Self.tile.height + Self.rowSpacing),
                      width: Self.tile.width, height: Self.tile.height)
    }

    /// 랙 내용 좌표 `p` 에 놓으면 몇 번째에 끼우는가(끌던 랙 타일 `excluding` 을 뺀 배열 기준, 0...남은 장수).
    func insertionIndex(at p: CGPoint, excluding: Int? = nil) -> Int {
        let row = p.y < Self.tile.height + Self.rowSpacing / 2 ? 0 : 1
        var column = 0
        for c in 0..<perRow where CGFloat(c) * Self.pitch + Self.tile.width / 2 < p.x { column = c + 1 }
        var raw = row * perRow + min(column, perRow)
        if let excluding, excluding < raw { raw -= 1 }
        let remaining = count - (excluding == nil ? 0 : 1)
        return max(0, min(raw, remaining))
    }
}

/// 끌던 타일이 어디서 왔나.
enum RummyDragSource: Equatable {
    case rack(index: Int)
    case meld(Int, index: Int)
}

/// 판 화면 좌표계에서 본 칸 자리. 판·랙은 레이아웃 상수로 고정이고, 스크롤만 내용 원점을 옮긴다.
struct RummyMatchZones: Equatable {
    var boardViewport: CGRect
    var boardContentOrigin: CGPoint
    var rackViewport: CGRect
    var rackContentOrigin: CGPoint

    /// 스크롤 0 일 때의 자리 — 레이아웃 상수에서만 나온다.
    static var standard: RummyMatchZones {
        let L = RummyWindowLayout.self
        let board = CGRect(x: 0, y: L.seatBarHeight + L.sectionSpacing, width: L.innerWidth, height: L.boardHeight)
        let rackY = board.maxY + L.sectionSpacing + L.statusLineHeight + L.statusSpacing + L.rackCardPadding
        let rack = CGRect(x: L.rackCardPadding, y: rackY, width: L.rackViewportWidth, height: L.rackAreaHeight)
        return RummyMatchZones(
            boardViewport: board,
            boardContentOrigin: CGPoint(x: board.minX + L.boardPadding, y: board.minY + L.boardPadding),
            rackViewport: rack, rackContentOrigin: rack.origin)
    }
}

/// 놓을 자리 판정(순수). 판단 재료는 기하와 "내 차례인가" 뿐이다 — 규칙(놓아도 되는가)은 편집기·서버가 정한다.
enum RummyDropResolver {
    static func target(at point: CGPoint, zones: RummyMatchZones, board: RummyBoardGeometry, rack: RummyRackGeometry,
                       source: RummyDragSource, isMyTurn: Bool) -> RummyDropTarget? {
        if zones.rackViewport.contains(point) {
            let local = CGPoint(x: point.x - zones.rackContentOrigin.x, y: point.y - zones.rackContentOrigin.y)
            var excluding: Int?
            if case .rack(let index) = source { excluding = index }
            return .rack(index: rack.insertionIndex(at: local, excluding: excluding))
        }
        // 내 차례가 아니면 랙 안 재배치만.
        guard isMyTurn else { return nil }
        guard zones.boardViewport.contains(point) else { return nil }
        let local = CGPoint(x: point.x - zones.boardContentOrigin.x, y: point.y - zones.boardContentOrigin.y)
        var excluding: (meld: Int, index: Int)?
        if case .meld(let meld, let index) = source { excluding = (meld, index) }
        if let hit = board.hit(local, excluding: excluding) {
            return .meld(hit.meld, index: hit.index)
        }
        return .newMeld
    }
}

/// 렌더 시험 주입구: 이 타일을 판 화면 좌표 `point` 로 끌고 있는 장면.
struct RummyPreviewDrag: Equatable {
    let tileID: Int
    let point: CGPoint
}

private struct RummyDragState: Equatable {
    let tile: RummyTile
    let source: RummyDragSource
    var point: CGPoint
}

/// 판 위에 그릴 타일 한 장(내 차례 = 편집기 타일 id, 남의 차례 = id 없음).
private struct RummyBoardTile: Hashable {
    let id: Int?
    let face: RummyFace
    let highlighted: Bool
}

private struct RummyContentOriginKey: PreferenceKey {
    static let defaultValue: [String: CGPoint] = [:]
    static func reduce(value: inout [String: CGPoint], nextValue: () -> [String: CGPoint]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private extension View {
    /// 스크롤 내용의 원점을 판 화면 좌표계로 알린다(스크롤 오프셋 = 이 원점의 이동).
    func reportsContentOrigin(_ key: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: RummyContentOriginKey.self,
                                   value: [key: proxy.frame(in: .named(RummyMatchView.space)).origin])
        })
    }
}

// MARK: - 판 화면

struct RummyMatchView: View {
    static let space = "rummy.match"

    let store: RummyStore
    let scene: RummyScene
    let match: RummyMatchState
    let me: ChessPlayerFace
    let clipsOverflowInsteadOfScroll: Bool
    let previewDrag: RummyPreviewDrag?

    @State private var drag: RummyDragState?
    @State private var scrolledOrigins: [String: CGPoint] = [:]
    @State private var refusedFlash = false

    private var editor: RummyTurnEditor? { scene.editor }
    private var isMyTurn: Bool { scene.isMyTurn && editor != nil }

    private var zones: RummyMatchZones {
        var zones = RummyMatchZones.standard
        if let origin = scrolledOrigins["board"] {
            zones.boardContentOrigin = CGPoint(x: origin.x, y: origin.y)
        }
        if let origin = scrolledOrigins["rack"] { zones.rackContentOrigin = origin }
        return zones
    }

    /// 판에 그릴 세트들.
    private var boardMelds: [[RummyBoardTile]] {
        if isMyTurn, let editor {
            return editor.melds.map { meld in
                meld.map { RummyBoardTile(id: $0.id, face: $0.face, highlighted: !editor.isFromTable($0.id)) }
            }
        }
        if let draft = scene.otherDraft {
            // 남의 작업 판 — 확정 판에 없던 면(다중집합 차)을 이번 차례에 낸 타일로 칠한다(표시 전용, 판정 아님).
            var confirmed: [RummyFace: Int] = [:]
            for face in (match.table ?? []).joined() { confirmed[face, default: 0] += 1 }
            return draft.map { meld in
                meld.map { face in
                    let left = confirmed[face, default: 0]
                    if left > 0 { confirmed[face] = left - 1 }
                    return RummyBoardTile(id: nil, face: face, highlighted: left == 0)
                }
            }
        }
        return (match.table ?? []).map { meld in
            RummyRules.displayOrder(meld).map { RummyBoardTile(id: nil, face: $0, highlighted: false) }
        }
    }

    /// 세트별 무효 여부 — 내 차례는 편집기, 남의 작업 판은 `RummyRules.analyze`, 확정 판은 서버가 이미 받았다.
    private var invalidMelds: [Bool] {
        if isMyTurn, let editor {
            return editor.melds.indices.map { !editor.analysis(ofMeld: $0).valid }
        }
        if let draft = scene.otherDraft {
            return draft.map { !RummyRules.analyze($0).valid }
        }
        return Array(repeating: false, count: match.table?.count ?? 0)
    }

    private var rackTiles: [RummyTile] { editor?.rack ?? [] }

    private var boardGeometry: RummyBoardGeometry {
        RummyBoardGeometry(counts: boardMelds.map(\.count), width: RummyWindowLayout.boardContentWidth)
    }

    private var rackGeometry: RummyRackGeometry {
        RummyRackGeometry(count: rackTiles.count, viewportWidth: RummyWindowLayout.rackViewportWidth)
    }

    /// 지금 끌고 있는 것(실제 끌기 또는 렌더 주입).
    private var activeDrag: RummyDragState? {
        if let drag { return drag }
        guard let previewDrag, let editor else { return nil }
        if let index = editor.rack.firstIndex(where: { $0.id == previewDrag.tileID }) {
            return RummyDragState(tile: editor.rack[index], source: .rack(index: index), point: previewDrag.point)
        }
        for (m, meld) in editor.melds.enumerated() {
            if let index = meld.firstIndex(where: { $0.id == previewDrag.tileID }) {
                return RummyDragState(tile: meld[index], source: .meld(m, index: index), point: previewDrag.point)
            }
        }
        return nil
    }

    private var hoverTarget: RummyDropTarget? {
        guard let drag = activeDrag else { return nil }
        return RummyDropResolver.target(at: drag.point, zones: zones, board: boardGeometry, rack: rackGeometry,
                                        source: drag.source, isMyTurn: isMyTurn)
    }

    /// 판 타일을 랙 위로 끄는 중 — 놓기 거절 표시.
    private var hoverRefused: Bool {
        guard let drag = activeDrag, case .rack? = hoverTarget, let editor else { return false }
        return editor.isFromTable(drag.tile.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RummyWindowLayout.sectionSpacing) {
            RummySeatBar(store: store, scene: scene, match: match)
                .frame(width: RummyWindowLayout.innerWidth, height: RummyWindowLayout.seatBarHeight)
            board
                .frame(width: RummyWindowLayout.innerWidth, height: RummyWindowLayout.boardHeight)
            VStack(alignment: .leading, spacing: RummyWindowLayout.statusSpacing) {
                statusLine
                    .frame(height: RummyWindowLayout.statusLineHeight)
                rackCard
                    .frame(width: RummyWindowLayout.innerWidth, height: RummyWindowLayout.rackCardHeight)
            }
            .frame(height: RummyWindowLayout.bottomHeight)
        }
        .frame(width: RummyWindowLayout.innerWidth, height: RummyWindowLayout.bodyHeight, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
        .overlay(alignment: .topLeading) {
            if let drag = activeDrag {
                RummyTileView(face: drag.tile.face, size: .rack)
                    .scaleEffect(1.08)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 4)
                    .overlay(alignment: .topTrailing) {
                        if hoverRefused {
                            Image(systemName: "nosign")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(RummyTilePalette.color(RummyTilePalette.invalid))
                                .background(Circle().fill(Color.white).padding(-1))
                                .offset(x: 6, y: -6)
                        }
                    }
                    .position(drag.point)
                    .allowsHitTesting(false)
            }
        }
        .onPreferenceChange(RummyContentOriginKey.self) { origins in
            // 클립 갈래(렌더)는 스크롤이 없다 — 표준 자리 그대로.
            guard !clipsOverflowInsteadOfScroll, scrolledOrigins != origins else { return }
            scrolledOrigins = origins
        }
        // 판이 바뀌면(내 차례 끝 · 남의 확정) 끄는 중이던 타일을 거둔다 — 낡은 id 로 놓지 않게.
        .onChange(of: match.seq) { _, _ in drag = nil }
    }

    // MARK: 판

    private var board: some View {
        let geometry = boardGeometry
        let melds = boardMelds
        let invalid = invalidMelds
        let target = hoverTarget
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.13, green: 0.14, blue: 0.20).opacity(0.92))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CheckTheme.border, lineWidth: 1)
            RummyScrollBox(clips: clipsOverflowInsteadOfScroll) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(melds.enumerated()), id: \.offset) { m, meld in
                        meldChip(meld, index: m, invalid: invalid.indices.contains(m) && invalid[m],
                                 targeted: { if case .meld(m, _)? = target { return true }; return false }())
                            .frame(width: geometry.meldFrames[m].width, height: geometry.meldFrames[m].height)
                            .position(x: geometry.meldFrames[m].midX, y: geometry.meldFrames[m].midY)
                    }
                    if isMyTurn, activeDrag != nil {
                        newMeldGhost(targeted: target == .newMeld)
                            .frame(width: geometry.newMeldFrame.width, height: geometry.newMeldFrame.height)
                            .position(x: geometry.newMeldFrame.midX, y: geometry.newMeldFrame.midY)
                    }
                }
                .frame(width: RummyWindowLayout.boardContentWidth,
                       height: max(geometry.contentHeight, RummyWindowLayout.boardHeight - RummyWindowLayout.boardPadding * 2),
                       alignment: .topLeading)
                .reportsContentOrigin("board")
            }
            .padding(RummyWindowLayout.boardPadding)
            if !isMyTurn, let name = scene.turnSeat?.displayName {
                Label(scene.otherDraft != nil ? RummyText.placing(name) : RummyText.turnOf(name),
                      systemImage: scene.otherDraft != nil ? "hand.draw.fill" : "hourglass")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(CheckTheme.panelElevated))
                    .overlay(Capsule().stroke(CheckTheme.accent.opacity(0.5), lineWidth: 1))
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }

    private func meldChip(_ meld: [RummyBoardTile], index: Int, invalid: Bool, targeted: Bool) -> some View {
        let invalidColor = RummyTilePalette.color(RummyTilePalette.invalid)
        return HStack(spacing: RummyBoardGeometry.tileGap) {
            ForEach(Array(meld.enumerated()), id: \.offset) { i, tile in
                let view = RummyTileView(face: tile.face, size: .table, highlighted: tile.highlighted,
                                         dimmed: tile.id != nil && activeDrag?.tile.id == tile.id)
                if let id = tile.id, isMyTurn, let editorTile = editor?.melds[safe: index]?[safe: i], editorTile.id == id {
                    view.gesture(dragGesture(editorTile, source: .meld(index, index: i)))
                } else {
                    view
                }
            }
        }
        .padding(RummyBoardGeometry.meldPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(invalid ? invalidColor.opacity(0.14) : Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(invalid ? invalidColor : (targeted ? CheckTheme.accent : Color.white.opacity(0.10)),
                    lineWidth: invalid || targeted ? 2 : 1))
    }

    private func newMeldGhost(targeted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, dash: [5, 4]))
            .foregroundStyle(targeted ? CheckTheme.accent : CheckTheme.secondaryText.opacity(0.6))
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CheckTheme.accent.opacity(targeted ? 0.14 : 0.04)))
            .overlay(Text(RummyText.newMeld).font(.caption2.weight(.bold))
                .foregroundStyle(targeted ? CheckTheme.accent : CheckTheme.secondaryText))
    }

    // MARK: 상태 줄

    private var statusLine: some View {
        let status = statusText
        return HStack(spacing: 8) {
            Image(systemName: scene.notice != nil ? "exclamationmark.circle.fill" : "info.circle")
            Text(status.text).lineLimit(1)
            Spacer(minLength: 12)
            if let event = RummyText.lastEvent(match.lastEvent, name: scene.name(of: match.lastEvent?.seatNo)) {
                Text(event).lineLimit(1).foregroundStyle(CheckTheme.secondaryText)
            }
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(status.tint)
        .padding(.horizontal, 4)
    }

    /// 상태 줄 글자 — 서버·판정 문구는 스토어 `notice`, 내 차례 글자는 `RummyText.myTurnStatus`(첫 등록 진행 ·
    /// [완료]가 꺼진 이유), 색은 `editor.canSubmit`.
    private var statusText: (text: String, tint: Color) {
        if let notice = scene.notice { return (notice, CheckTheme.pending) }
        if isMyTurn, let editor {
            let tint = editor.canSubmit ? CheckTheme.working : CheckTheme.primaryText
            return (RummyText.myTurnStatus(editor), tint)
        }
        if let name = scene.turnSeat?.displayName { return (RummyText.turnOf(name), CheckTheme.secondaryText) }
        return ("", CheckTheme.secondaryText)
    }

    // MARK: 랙 + 버튼

    private var rackCard: some View {
        let geometry = rackGeometry
        let target = hoverTarget
        let refused = hoverRefused || refusedFlash
        let rackTargeted: Bool = { if case .rack? = target { return true }; return false }()
        return HStack(alignment: .top, spacing: RummyWindowLayout.columnSpacing) {
            RummyScrollBox(axis: .horizontal, clips: clipsOverflowInsteadOfScroll) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(rackTiles.enumerated()), id: \.element.id) { i, tile in
                        let frame = geometry.frame(i)
                        RummyTileView(face: tile.face, size: .rack, dimmed: activeDrag?.tile.id == tile.id)
                            .gesture(dragGesture(tile, source: .rack(index: i)))
                            .position(x: frame.midX, y: frame.midY)
                    }
                    if !refused, case .rack(let index?)? = target {
                        rackCaret(at: index, geometry: geometry)
                    }
                }
                .frame(width: geometry.contentWidth, height: geometry.contentHeight, alignment: .topLeading)
                .reportsContentOrigin("rack")
            }
            .frame(width: RummyWindowLayout.rackViewportWidth, height: RummyWindowLayout.rackAreaHeight)
            .padding(RummyWindowLayout.rackCardPadding)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.24, green: 0.21, blue: 0.33).opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(refused ? RummyTilePalette.color(RummyTilePalette.invalid)
                        : (rackTargeted ? CheckTheme.accent : CheckTheme.border),
                        lineWidth: refused || rackTargeted ? 2 : 1))
            actions
                .frame(width: RummyWindowLayout.actionColumnWidth, height: RummyWindowLayout.rackCardHeight)
        }
    }

    /// 랙의 끼울 자리 표시(세로 막대).
    private func rackCaret(at index: Int, geometry: RummyRackGeometry) -> some View {
        let row = min(index / geometry.perRow, RummyRackGeometry.rows - 1)
        let column = index - row * geometry.perRow
        let x = CGFloat(column) * RummyRackGeometry.pitch - RummyRackGeometry.gap / 2
        let y = CGFloat(row) * (RummyRackGeometry.tile.height + RummyRackGeometry.rowSpacing)
        return Capsule()
            .fill(CheckTheme.accent)
            .frame(width: 3, height: RummyRackGeometry.tile.height)
            .position(x: max(1.5, x), y: y + RummyRackGeometry.tile.height / 2)
    }

    private var actions: some View {
        let busy = scene.isWorking
        let canEdit = isMyTurn && !busy
        let poolEmpty = (match.poolCount ?? 0) == 0
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                TetrisDuelActionButton(title: RummyText.undo, icon: "arrow.uturn.backward", style: .outline,
                                       height: RummyWindowLayout.actionButtonHeight, fullWidth: true,
                                       isEnabled: canEdit && editor?.isChanged == true,
                                       action: { store.resetTurn() })
                    .checkTooltip("이번 차례에 놓은 것을 처음으로")
                TetrisDuelActionButton(title: RummyText.sortNumber, style: .outline,
                                       height: RummyWindowLayout.actionButtonHeight,
                                       isEnabled: editor != nil, action: { store.sortRack(.number) })
                    .checkTooltip("같은 숫자끼리 모아요")
                TetrisDuelActionButton(title: RummyText.sortColor, style: .outline,
                                       height: RummyWindowLayout.actionButtonHeight,
                                       isEnabled: editor != nil, action: { store.sortRack(.color) })
                    .checkTooltip("색별로 이어지게 모아요")
            }
            HStack(spacing: 8) {
                TetrisDuelActionButton(title: poolEmpty ? RummyText.pass : RummyText.draw,
                                       icon: poolEmpty ? "forward.fill" : "plus.rectangle.on.rectangle",
                                       tint: CheckTheme.pending, style: .outline,
                                       height: RummyWindowLayout.actionButtonHeight, fullWidth: true,
                                       isEnabled: canEdit, action: { store.drawTile() })
                TetrisDuelActionButton(title: RummyText.submit, icon: "checkmark", tint: CheckTheme.working,
                                       height: RummyWindowLayout.actionButtonHeight, fullWidth: true,
                                       isEnabled: canEdit && editor?.canSubmit == true,
                                       action: { store.submitTurn() })
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, RummyWindowLayout.rackCardPadding)
    }

    // MARK: 끌기

    private func dragGesture(_ tile: RummyTile, source: RummyDragSource) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag?.tile.id == tile.id {
                    drag?.point = value.location
                } else {
                    drag = RummyDragState(tile: tile, source: source, point: value.location)
                }
            }
            .onEnded { value in
                finishDrag(tile, source: source, at: value.location)
            }
    }

    private func finishDrag(_ tile: RummyTile, source: RummyDragSource, at point: CGPoint) {
        drag = nil
        guard let target = RummyDropResolver.target(at: point, zones: zones, board: boardGeometry, rack: rackGeometry,
                                                    source: source, isMyTurn: isMyTurn)
        else { return }
        if case .rack = target, editor?.isFromTable(tile.id) == true {
            // 판에 있던 타일은 랙으로 안 간다(R-14) — 놓지 않고 랙을 잠깐 빨갛게.
            refusedFlash = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                refusedFlash = false
            }
            return
        }
        store.moveTile(tile.id, to: target)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - 자리 띠

private struct RummySeatBar: View {
    let store: RummyStore
    let scene: RummyScene
    let match: RummyMatchState

    private var seats: [RummyMatchSeat] {
        (match.seats ?? []).filter { $0.seatNo != nil }.sorted { ($0.seatNo ?? 0) < ($1.seatNo ?? 0) }
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(seats) { seat in
                RummySeatCard(store: store, scene: scene, seat: seat,
                              isTurn: seat.seatNo == match.turnSeatNo && seat.state == .playing,
                              isMe: seat.seatNo == match.mySeatNo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(RummyText.pool(match.poolCount), systemImage: "square.stack.3d.up.fill")
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
                HStack(spacing: 4) {
                    RubyIcon(size: 11)
                    Text(RummyText.stake(match.stake)).monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                Text(RummyText.split(seatCount: match.seatCount, stake: match.stake))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(width: 176, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CheckTheme.panel.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
        }
    }
}

private struct RummySeatCard: View {
    let store: RummyStore
    let scene: RummyScene
    let seat: RummyMatchSeat
    let isTurn: Bool
    let isMe: Bool

    var body: some View {
        let forfeited = seat.state == .forfeit
        HStack(spacing: 10) {
            CheckAvatarView(name: seat.displayName ?? "?", userID: seat.userId.uuidString.lowercased(),
                            avatarURL: seat.avatarUrl.flatMap(URL.init(string:)), size: 38,
                            characterHint: seat.character)
                .padding(3)
                .overlay(Circle().stroke(isTurn ? CheckTheme.accent : Color.clear, lineWidth: 3))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(seat.displayName ?? "?").font(.callout.weight(.bold)).lineLimit(1)
                    if isMe { RummyChip(text: "나", tint: CheckTheme.accent) }
                }
                HStack(spacing: 5) {
                    Label(RummyText.rackCount(seat.rackCount), systemImage: "rectangle.portrait.fill")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(CheckTheme.secondaryText)
                    if forfeited {
                        RummyChip(text: RummyText.forfeit, tint: CheckTheme.danger)
                    } else if seat.initialDone == false {
                        RummyChip(text: RummyText.beforeInitial, tint: CheckTheme.pending)
                    }
                    if let streak = seat.timeoutStreak, streak > 0, !forfeited {
                        RummyChip(text: RummyText.timeouts(streak), tint: CheckTheme.danger)
                    }
                }
            }
            Spacer(minLength: 4)
            if isTurn {
                RummyCountdownLeaf(remaining: scene.turnRemaining(store), fixedNow: scene.fixedNow,
                                   label: RummyText.seconds)
                    .font(.title3.weight(.heavy))
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isTurn ? CheckTheme.accent.opacity(0.14) : CheckTheme.panel.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(isTurn ? CheckTheme.accent : CheckTheme.border, lineWidth: isTurn ? 2 : 1))
        .opacity(forfeited ? 0.5 : 1)
    }
}

// MARK: - 결과

struct RummyResultView: View {
    let store: RummyStore
    let scene: RummyScene
    let match: RummyMatchState

    /// 판에 앉았던 자리(끝까지 한 자리 · 기권) — 서버 등수 순.
    private var rows: [RummyMatchSeat] {
        (match.seats ?? []).filter { $0.state == .done || $0.state == .forfeit || $0.finalRank != nil }
            .sorted { ($0.finalRank ?? 99, $0.seatNo ?? 9) < ($1.finalRank ?? 99, $1.seatNo ?? 9) }
    }

    private var winnerName: String? {
        rows.first { $0.isWinner == true }?.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RummyWindowLayout.resultRowSpacing) {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill").font(.title2).foregroundStyle(CheckTheme.pending)
                VStack(alignment: .leading, spacing: 2) {
                    Text("결과").font(.title3.weight(.bold))
                    Text(RummyText.endReason(match.endReason, winner: winnerName))
                        .font(.callout)
                        .foregroundStyle(CheckTheme.secondaryText)
                }
                Spacer()
                TetrisDuelActionButton(title: RummyText.toLobby, icon: "arrow.left", height: 38,
                                       action: { store.dismissResult() })
            }
            .frame(height: 48)
            ForEach(rows) { seat in
                RummyResultRow(seat: seat, stake: match.stake ?? 0, isMe: seat.seatNo == match.mySeatNo)
                    .frame(height: RummyWindowLayout.resultRowHeight)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tetrisDuelCard(padding: 18)
    }
}

private struct RummyResultRow: View {
    let seat: RummyMatchSeat
    let stake: Int
    let isMe: Bool

    static let maxTiles = 16

    var body: some View {
        let net = (seat.payout ?? 0) - stake
        let rack = seat.finalRack ?? []
        HStack(spacing: 16) {
            Text(RummyText.rank(seat.finalRank))
                .font(.title2.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(seat.finalRank == 1 ? CheckTheme.pending : CheckTheme.primaryText)
                .frame(width: 64, alignment: .leading)
            CheckAvatarView(name: seat.displayName ?? "?", userID: seat.userId.uuidString.lowercased(),
                            avatarURL: seat.avatarUrl.flatMap(URL.init(string:)), size: 44,
                            characterHint: seat.character)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(seat.displayName ?? "?").font(.callout.weight(.bold)).lineLimit(1)
                    if seat.isWinner == true { Image(systemName: "crown.fill").foregroundStyle(CheckTheme.pending) }
                    if isMe { RummyChip(text: "나", tint: CheckTheme.accent) }
                    if seat.state == .forfeit { RummyChip(text: RummyText.forfeit, tint: CheckTheme.danger) }
                }
                Text(RummyText.score(seat.finalScore))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            .frame(width: 190, alignment: .leading)
            HStack(spacing: 5) {
                RubyIcon(size: 16)
                Text(RummyText.net(net))
                    .font(.title3.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(net > 0 ? CheckTheme.working : (net < 0 ? CheckTheme.danger : CheckTheme.primaryText))
            }
            .frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(RummyText.remainingTiles).font(.caption2).foregroundStyle(CheckTheme.secondaryText)
                HStack(spacing: 2) {
                    ForEach(Array(rack.prefix(Self.maxTiles).enumerated()), id: \.offset) { _, face in
                        RummyTileView(face: face, size: .table)
                    }
                    if rack.count > Self.maxTiles {
                        Text("+\(rack.count - Self.maxTiles)").font(.caption.weight(.bold))
                    }
                    if rack.isEmpty {
                        Text("—").font(.callout).foregroundStyle(CheckTheme.secondaryText)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(seat.isWinner == true ? CheckTheme.pending.opacity(0.10) : Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(isMe ? CheckTheme.accent.opacity(0.6) : CheckTheme.border, lineWidth: isMe ? 2 : 1))
    }
}
