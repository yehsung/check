import AppKit
import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 판 (2판 §3 — 배치 B "둘러앉은 탁자")
//
// 판 화면 = 위 띠(판돈 · 위쪽 상대 · 더미) / 가운데(왼쪽 상대 · 펠트 판 캔버스 · 오른쪽 상대) / 아래(내 자리 · 받침대 위 2줄 랙 ·
// [완료] [뽑기|넘기기] [되돌리기] [777|789] [판 확대] · 상태 글자). 칸 자리는 전부 `RummyMatchLayout`(순수) 한 곳에서 나온다.
//
// ── 끌기 ──
// 타일마다 `DragGesture(minimumDistance: 0)` 하나로 받고 시간·거리를 스스로 잰다(키 창에서 확실히 도는 길):
//   · 3pt 넘게 움직이면 **한 장** 끌기.
//   · 3pt 안에서 0.5초(`liftDelay` — 0.3.70, 0.35초는 천천히 누르는 사람이 한 장을 집으려다 덩어리째 집었다) 버티면
//     **묶음째 집기** — 받침대 = `editor.rackChain(around:)`(딱 붙은 이어진 덩어리), 판 = `editor.meldChunk(for:)`(누른 타일에서
//     가까운 끝까지 — 오른쪽 절반이면 그 타일부터 끝, 왼쪽 절반이면 처음부터 그 타일, 정확히 가운데면 묶음 전체. ⌥ 없이 쪼개기).
//     들어 올림 · 장수 뱃지 · 햅틱. 그다음 끌면 묶음째.
//   · 묶음 왼쪽 손잡이를 끌면 묶음 통째 위치 이동(`store.moveSet`). 묶음 전체를 집어 빈 곳에 놓아도 같은 길로 간다.
// 놓을 자리는 순수 판정(`RummyDropResolver`)이 정하고, 규칙(놓아도 되는가)은 편집기·서버가 정한다:
//   · 받침대 위 = `.rackSlot`(반 칸 격자, 겹치면 편집기가 가장 가까운 빈자리로) · 묶음 위 = `.meld(m, index:)` ·
//     판 빈 곳 = `.newMeldAt(왼쪽 위)`(편집기가 가장 가까운 빈 격자점으로 스냅).
//   · 판에 있던 타일은 받침대로 안 간다(R-14) — 받침대 빨간 테두리 · 놓으면 제자리.
//   · 내 차례가 아니면 받침대 안 재배치만.
//
// ── 모션 ── (동작 줄이기면 전부 끈다)
//   · 뽑기: `store.lastDraw` 가 바뀌면 새 타일이 [뽑기] 버튼 자리에서 받침대 빈자리로 스프링(0.45초).
//   · 정렬: 정렬 뒤 화면 순서대로 타일마다 25ms 시차로 미끄러진다.
//   · 남의 작업 판·확정 판 변화: 묶음을 면 글자 키로 잡아 제자리에서 부드럽게 옮긴다.
//   · 0.3.70: [판 확대]가 기본이다(놓인 묶음에 맞춰 최대 타일 56pt). 끄는 동안·누르는 동안은 판 변환을 굳힌다 — 놓을 때마다
//     배율이 바뀌어 손 아래 판이 움직이지 않게. 놓으면 새 변환으로 미끄러진다. 창 머리글은 위 띠 빈칸으로 들어왔다.
//   · 3판 놓기: 끄는 동안 편집기 미리보기(`previewDrop`·`previewMoveSet`)로 붙을 끝 자석 · 끼울 자리 캐럿 · 새 묶음 점선을
//     그리고, 놓으면 타일이 손을 놓은 자리에서 들어갈 자리로 미끄러진다(타일 id 로 잡아 나뉨·붙기·끼우기 모두 튀지 않는다).

/// 판 화면 칸 자리(판 화면 좌표, 왼쪽 위 원점). 순수 값 — 그리는 자리·놓는 자리·시험이 같은 산식을 쓴다.
struct RummyMatchLayout: Equatable {
    static let topBandHeight: CGFloat = 46
    static let gap: CGFloat = 8
    static let sideColumnWidth: CGFloat = 150
    static let cornerCardWidth: CGFloat = 230
    static let topSeatWidth: CGFloat = 340
    static let sideCardHeight: CGFloat = 220
    static let submitHeight: CGFloat = 42
    static let buttonHeight: CGFloat = 34
    static let smallButtonHeight: CGFloat = 30
    static let actionSpacing: CGFloat = 8

    let size: CGSize

    static var standard: RummyMatchLayout {
        RummyMatchLayout(size: CGSize(width: RummyWindowLayout.innerWidth, height: RummyWindowLayout.matchBodyHeight))
    }

    var rackHeight: CGFloat { RummyRackGeometry.standHeight }
    var rackWidth: CGFloat { RummyRackGeometry.standWidth }
    var middleY: CGFloat { Self.topBandHeight + Self.gap }
    var bottomY: CGFloat { size.height - rackHeight }
    var middleHeight: CGFloat { bottomY - Self.gap - middleY }

    var potCard: CGRect { CGRect(x: 0, y: 0, width: Self.cornerCardWidth, height: Self.topBandHeight) }
    var poolCard: CGRect {
        CGRect(x: size.width - Self.cornerCardWidth, y: 0, width: Self.cornerCardWidth, height: Self.topBandHeight)
    }
    var topSeat: CGRect {
        CGRect(x: (size.width - Self.topSeatWidth) / 2, y: 0, width: Self.topSeatWidth, height: Self.topBandHeight)
    }
    /// 0.3.70 — 창 머리글이 들어오는 위 띠 빈칸(판돈 카드와 위쪽 상대 사이: 루비 · 반응, 위쪽 상대와 더미 사이: 규칙 · 기권).
    var chromeLeft: CGRect {
        CGRect(x: potCard.maxX + Self.gap, y: 0, width: topSeat.minX - potCard.maxX - Self.gap * 2, height: Self.topBandHeight)
    }
    var chromeRight: CGRect {
        CGRect(x: topSeat.maxX + Self.gap, y: 0, width: poolCard.minX - topSeat.maxX - Self.gap * 2, height: Self.topBandHeight)
    }
    var leftSeat: CGRect { sideCard(x: 0) }
    var rightSeat: CGRect { sideCard(x: size.width - Self.sideColumnWidth) }
    var table: CGRect {
        let x = Self.sideColumnWidth + Self.gap
        return CGRect(x: x, y: middleY, width: size.width - x * 2, height: middleHeight)
    }
    var mySeat: CGRect { CGRect(x: 0, y: bottomY, width: Self.sideColumnWidth, height: rackHeight) }
    var rack: CGRect { CGRect(x: Self.sideColumnWidth + Self.gap, y: bottomY, width: rackWidth, height: rackHeight) }
    var actions: CGRect {
        let x = rack.maxX + Self.gap * 2
        return CGRect(x: x, y: bottomY, width: size.width - x, height: rackHeight)
    }
    /// [뽑기|넘기기] 버튼 — 뽑은 타일이 여기서 튀어나온다.
    var drawButton: CGRect {
        CGRect(x: actions.minX, y: actions.minY + Self.submitHeight + Self.actionSpacing,
               width: (actions.width - Self.actionSpacing) / 2, height: Self.buttonHeight)
    }

    private func sideCard(x: CGFloat) -> CGRect {
        let height = min(Self.sideCardHeight, middleHeight)
        return CGRect(x: x, y: middleY + (middleHeight - height) / 2, width: Self.sideColumnWidth, height: height)
    }
}

/// 상대 자리 배치 — 나 다음 사람부터 왼쪽 → 위 → 오른쪽(둘이면 위, 셋이면 왼·오른). 순수.
struct RummySeatArrangement: Equatable {
    var left: Int?
    var top: Int?
    var right: Int?

    /// `seatNos` = 판의 자리 번호들, `mine` = 내 자리.
    static func arrange(seatNos: [Int], mine: Int?) -> RummySeatArrangement {
        let sorted = seatNos.sorted()
        guard let mine, let at = sorted.firstIndex(of: mine) else {
            let others = sorted
            return place(others)
        }
        let others = Array(sorted[(at + 1)...] + sorted[..<at])
        return place(others)
    }

    private static func place(_ others: [Int]) -> RummySeatArrangement {
        switch others.count {
        case 0: return RummySeatArrangement()
        case 1: return RummySeatArrangement(top: others[0])
        case 2: return RummySeatArrangement(left: others[0], right: others[1])
        default: return RummySeatArrangement(left: others[0], top: others[1], right: others[2])
        }
    }
}

/// 놓을 자리 판정(순수). 재료는 칸 자리·변환·배치와 "내 차례인가" 뿐이다 — 놓아도 되는가는 편집기·서버가 정한다.
enum RummyDropResolver {
    /// 판 묶음 누르기 여유(논리 단위) — 묶음 사이 틈(16)의 반 남짓.
    static let meldSlack = CGSize(width: 10, height: 10)

    /// 타일 묶음(`count` 장, 손에 `grabIndex` 번째)을 `pointer`(판 화면 좌표)에 놓으면.
    /// `skipMeld` = 묶음 하나를 통째로 끄는 중이면 그 묶음(자기 위에 놓기 = 위치 이동으로 본다).
    static func target(pointer: CGPoint, grabIndex: Int, count: Int, layout: RummyMatchLayout,
                       canvas: RummyCanvasTransform, table: RummyTableLayout, rack: RummyRackGeometry,
                       isMyTurn: Bool, skipMeld: Int? = nil) -> RummyDropTarget? {
        if layout.rack.contains(pointer) {
            let local = CGPoint(x: pointer.x - layout.rack.minX, y: pointer.y - layout.rack.minY)
            let left = local.x - (CGFloat(grabIndex) + 0.5) * rack.tileSize.width
            return .rackSlot(rack.slot(tileLeft: left, centerY: local.y, tiles: count))
        }
        guard isMyTurn, layout.table.contains(pointer) else { return nil }
        let logical = canvas.toLogical(CGPoint(x: pointer.x - layout.table.minX, y: pointer.y - layout.table.minY))
        for (index, frame) in table.frames.enumerated() where index != skipMeld {
            let zone = CGRect(x: CGFloat(frame.x), y: CGFloat(frame.y), width: CGFloat(frame.width),
                              height: CGFloat(frame.height)).insetBy(dx: -meldSlack.width, dy: -meldSlack.height)
            guard zone.contains(logical) else { continue }
            var at = 0
            for tile in 0..<table.counts[index] {
                if let f = table.tileFrame(set: index, tile: tile), CGFloat(f.x) + CGFloat(f.width) / 2 < logical.x { at += 1 }
            }
            return .meld(index, index: at)
        }
        let w = CGFloat(RummyTableLayout.tileWidth), h = CGFloat(RummyTableLayout.tileHeight)
        return .newMeldAt(clampedTopLeft(CGPoint(x: logical.x - (CGFloat(grabIndex) + 0.5) * w, y: logical.y - h / 2),
                                         tiles: count))
    }

    /// 손잡이로 묶음을 끌어 `pointer` 에 놓으면 — 판 위면 새 왼쪽 위(잡은 자리 오프셋 `grab` 을 뺀다), 밖이면 nil.
    static func setTarget(pointer: CGPoint, grab: CGPoint, tiles: Int, layout: RummyMatchLayout,
                          canvas: RummyCanvasTransform) -> RummyPoint? {
        guard layout.table.contains(pointer) else { return nil }
        let logical = canvas.toLogical(CGPoint(x: pointer.x - layout.table.minX, y: pointer.y - layout.table.minY))
        return clampedTopLeft(CGPoint(x: logical.x - grab.x, y: logical.y - grab.y), tiles: tiles)
    }

    static func clampedTopLeft(_ p: CGPoint, tiles: Int) -> RummyPoint {
        let maxX = RummyTableLayout.canvasWidth - RummyTableLayout.width(tiles: tiles)
        let maxY = RummyTableLayout.canvasHeight - RummyTableLayout.tileHeight
        return RummyPoint(x: min(max(Int(p.x.rounded()), 0), max(0, maxX)),
                          y: min(max(Int(p.y.rounded()), 0), max(0, maxY)))
    }
}

/// 렌더 시험 주입구: 이 타일을 판 화면 좌표 `point` 로 끌고 있는 장면(`block` = 길게 눌러 묶음째).
/// `point` 가 nil 이면 길게 눌러 **들어 올리기만** 한 장면.
struct RummyPreviewDrag: Equatable {
    let tileID: Int
    let point: CGPoint?
    var block: Bool = false

    init(tileID: Int, point: CGPoint, block: Bool = false) {
        self.tileID = tileID
        self.point = point
        self.block = block
    }

    init(liftedTileID: Int) {
        tileID = liftedTileID
        point = nil
        block = true
    }
}

/// 렌더 시험 주입구: [판 확대] 를 켠 장면.
private struct RummyBoardZoomPreviewKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var rummyBoardZoomPreview: Bool? {
        get { self[RummyBoardZoomPreviewKey.self] }
        set { self[RummyBoardZoomPreviewKey.self] = newValue }
    }
}

/// 판 화면 고정 글자(2판에서 더한 것).
enum RummyMatchText {
    static let zoomIn = "판 확대"
    static let zoomOut = "전체 보기"
    static let pool = "더미에 남은 타일"
    static let initialProgress = "첫 등록"
    static let me = "나"
    static func pot(stake: Int?, seats: Int?) -> String { "판돈 \(stake ?? 0) × \(seats ?? 0)명" }
}

private struct RummyDragState: Equatable {
    enum Kind: Equatable {
        case tiles
        /// 손잡이로 묶음 위치 이동.
        case set(Int)
    }

    var kind: Kind
    var tiles: [RummyTile]
    var grabIndex: Int
    var point: CGPoint
    /// 손잡이 끌기: 잡은 자리 − 묶음 왼쪽 위(논리).
    var grab: CGPoint = .zero

    var ids: [Int] { tiles.map(\.id) }
}

/// 방금 판에 놓은 타일의 출발 자리(논리 왼쪽 위). `landed` 가 켜지면 캔버스가 제자리로 미끄러뜨린다.
private struct RummyArrival: Equatable {
    let serial: Int
    let starts: [Int: CGPoint]
    var landed: Bool
}

private struct RummyPressState: Equatable {
    enum Surface: Equatable { case rack, board }
    let tileID: Int
    let token: Int
    let surface: Surface
    var picked: [Int]?
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
    /// 위 띠 [기권] — 확인 덮개는 창 루트가 띄운다.
    var onForfeit: () -> Void = {}

    /// 길게 눌러 묶음째 집기까지(초).
    static let liftDelay: Double = 0.5

    @State private var drag: RummyDragState?
    @State private var press: RummyPressState?
    @State private var pressSerial = 0
    @State private var refusedFlash = false
    /// [판 확대] — 0.3.70 기본 켬(전체 보기면 판 타일 37pt, 확대면 놓인 묶음에 맞춰 최대 56pt).
    @State private var zoomed = true
    /// 끄는 동안 굳힌 판 변환(놓으면 nil — 새 변환으로 미끄러진다).
    @State private var frozenCanvas: RummyCanvasTransform?
    @State private var stagger: [Int: Double] = [:]
    @State private var flyIn: RummyFlyIn?
    /// 0.3.70 방금 뽑은 타일(3초 빛남).
    @State private var freshDraw: (serial: Int, ids: Set<Int>)?
    /// 0.3.70 내 차례 표시: 테두리 빛 단계 · '내 차례' 배지(차례 정체성으로 한 번만).
    @State private var turnGlowPhase: RummyTurnGlowPhase = .steady
    @State private var turnBadgeShown = false
    @State private var turnCueKey: String?
    @Environment(\.rummyCuePreview) private var cuePreview
    @State private var arrival: RummyArrival?
    @State private var arrivalSerial = 0
    /// 마지막으로 판에 놓은 타일(묶음 상자 모션 키에서 뺀다 — 캔버스 `recentTileIDs`).
    @State private var recentDrop: Set<Int> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rummyBoardZoomPreview) private var zoomPreview

    private var editor: RummyTurnEditor? { scene.editor }
    private var isMyTurn: Bool { scene.isMyTurn && editor != nil }
    private var isZoomed: Bool { zoomPreview ?? zoomed }

    var body: some View {
        GeometryReader { proxy in
            content(RummyMatchLayout(size: proxy.size))
        }
        .coordinateSpace(name: Self.space)
        .onAppear { RummyArt.shared.refreshIfNeeded() }
        // 판이 바뀌면(내 차례 끝 · 남의 확정) 끄는 중이던 타일을 거둔다 — 낡은 id 로 놓지 않게.
        .onChange(of: match.seq) { _, _ in
            drag = nil
            press = nil
            frozenCanvas = nil
            arrival = nil
            recentDrop = []
        }
        .onAppear { cueTurnIfNeeded() }
        .onChange(of: myTurnCueKey) { _, _ in cueTurnIfNeeded() }
        .onChange(of: store.lastDraw?.serial) { _, serial in
            guard let serial, let event = store.lastDraw else { return }
            // 0.3.70: 뽑은 타일은 3초 빛낸다(동작 줄이기면 테두리만 — 날아오기는 없다).
            let ids = Set(event.tiles.map(\.tileID))
            freshDraw = (serial, ids)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if freshDraw?.serial == serial { freshDraw = nil }
            }
            guard !reduceMotion else { return }
            flyIn = RummyFlyIn(serial: serial, tileIDs: Set(event.tiles.map(\.tileID)), landed: false)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                guard flyIn?.serial == serial else { return }
                flyIn?.landed = true
                try? await Task.sleep(for: .milliseconds(900))
                if flyIn?.serial == serial { flyIn = nil }
            }
        }
    }

    // MARK: 내 차례 표시(0.3.70 — 화면 안에서만)

    /// 내 차례 정체성(차례마다 다르다). 내 차례가 아니면 nil.
    private var myTurnCueKey: String? {
        isMyTurn && match.status == .active ? RummyEditorKey(match).text : nil
    }

    /// 내 차례가 새로 왔으면 받침대 테두리를 한 번 크게 빛내고(0.8초 뒤 은은하게) 판 가운데 '내 차례' 배지를 1.3초 띄운다.
    /// 동작 줄이기면 펄스·배지 없이 은은한 테두리만.
    private func cueTurnIfNeeded() {
        guard let key = myTurnCueKey, key != turnCueKey else { return }
        turnCueKey = key
        guard !reduceMotion, !scene.isPreview else {
            turnGlowPhase = .steady
            return
        }
        turnGlowPhase = .pulse
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { turnBadgeShown = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard turnCueKey == key else { return }
            turnGlowPhase = .steady
            try? await Task.sleep(for: .milliseconds(500))
            guard turnCueKey == key else { return }
            withAnimation(.easeIn(duration: 0.25)) { turnBadgeShown = false }
        }
    }

    private var shownTurnGlow: RummyTurnGlowPhase? {
        if let preview = cuePreview { return preview.turnGlow }
        return isMyTurn ? turnGlowPhase : nil
    }

    private var shownTurnBadge: Bool {
        cuePreview?.turnBadge ?? (turnBadgeShown && isMyTurn)
    }

    /// 정렬 버튼의 '선택됨' — 정렬한 뒤 손대지 않은 동안만(스토어 `rackSortMode`).
    private var shownSortMode: RummyRackSort? {
        cuePreview?.sortMode ?? (scene.isPreview ? nil : store.rackSortMode)
    }

    // MARK: 장면 값

    /// 판에 그릴 것(묶음 · 배치 · 편집 가능 여부).
    private var board: (melds: [RummyBoardMeld], layout: RummyTableLayout) {
        if isMyTurn, let editor {
            let layout = editor.tableLayout
            let melds = editor.melds.enumerated().map { index, meld in
                RummyBoardMeld(id: "e\(meld.first?.id ?? -index - 1)",
                               tiles: meld.map { RummyBoardTile(id: $0.id, face: $0.face, highlighted: !editor.isFromTable($0.id)) },
                               frame: layout.frame(of: index) ?? RummyTableLayout.frame(at: RummyPoint(x: 0, y: 0), tiles: meld.count),
                               invalid: !editor.analysis(ofMeld: index).valid)
            }
            return (melds, layout)
        }
        if let draft = scene.otherDraft {
            // 남의 작업 판 — 확정 판에 없던 면(다중집합 차)을 이번 차례에 낸 타일로 칠한다(표시 전용, 판정 아님).
            let layout = RummyTableLayout(sets: draft, layout: match.draft?.layout)
            var confirmed: [RummyFace: Int] = [:]
            for face in (match.table ?? []).joined() { confirmed[face, default: 0] += 1 }
            let keys = RummyBoardMeld.faceKeys(draft)
            let melds = draft.enumerated().map { index, set in
                RummyBoardMeld(id: keys[index], tiles: set.map { face in
                    let left = confirmed[face, default: 0]
                    if left > 0 { confirmed[face] = left - 1 }
                    return RummyBoardTile(id: nil, face: face, highlighted: left == 0)
                }, frame: layout.frame(of: index) ?? RummyTableLayout.frame(at: RummyPoint(x: 0, y: 0), tiles: set.count),
                invalid: !RummyRules.analyze(set).valid)
            }
            return (melds, layout)
        }
        let table = match.table ?? []
        let layout = RummyTableLayout(sets: table, layout: match.tableLayout)
        let keys = RummyBoardMeld.faceKeys(table)
        let melds = table.enumerated().map { index, set in
            RummyBoardMeld(id: keys[index],
                           tiles: RummyRules.displayOrder(set).map { RummyBoardTile(id: nil, face: $0, highlighted: false) },
                           frame: layout.frame(of: index) ?? RummyTableLayout.frame(at: RummyPoint(x: 0, y: 0), tiles: set.count),
                           invalid: false)
        }
        return (melds, layout)
    }

    private func transform(_ L: RummyMatchLayout, layout: RummyTableLayout) -> RummyCanvasTransform {
        if let frozenCanvas { return frozenCanvas }
        return isZoomed ? .zoom(viewport: L.table.size, content: layout.frames) : .fit(viewport: L.table.size)
    }

    /// 끌기·누르기 시작 — 지금 변환을 굳힌다(놓을 때까지 손 아래 판이 안 움직인다).
    private func freeze(_ canvas: RummyCanvasTransform) {
        if frozenCanvas == nil { frozenCanvas = canvas }
    }

    /// 놓은 뒤 — 굳힌 변환을 풀어 새 변환으로 미끄러진다.
    private func thaw() {
        guard frozenCanvas != nil else { return }
        withAnimation(reduceMotion ? nil : RummyTableCanvasView.slide) { frozenCanvas = nil }
    }

    private func rackGeometry(_ L: RummyMatchLayout) -> RummyRackGeometry {
        RummyRackGeometry(height: L.rackHeight, rowCount: editor?.rackLayout.rowCount ?? RummyRackLayout.baseRows)
    }

    private func tile(_ id: Int) -> RummyTile? {
        guard let editor else { return nil }
        return editor.rack.first { $0.id == id } ?? editor.melds.lazy.compactMap { $0.first { $0.id == id } }.first
    }

    /// 묶음 하나를 통째로 집었으면 그 묶음 번호.
    private func wholeMeld(_ ids: [Int]) -> Int? {
        guard let editor else { return nil }
        let set = Set(ids)
        return editor.melds.firstIndex { Set($0.map(\.id)) == set }
    }

    /// 지금 끌고 있는 것(실제 끌기 또는 렌더 주입).
    private var activeDrag: RummyDragState? {
        if let drag { return drag }
        guard let previewDrag, let point = previewDrag.point, let editor, let grabbed = tile(previewDrag.tileID)
        else { return nil }
        let ids = previewDrag.block ? pick(around: grabbed.id, in: editor) : [grabbed.id]
        let tiles = ids.compactMap(tile)
        return RummyDragState(kind: .tiles, tiles: tiles, grabIndex: ids.firstIndex(of: grabbed.id) ?? 0, point: point)
    }

    /// 길게 눌러 들어 올린 묶음(아직 안 끎).
    private var activeLift: (tileID: Int, ids: [Int])? {
        if drag == nil, let press, let picked = press.picked { return (press.tileID, picked) }
        guard drag == nil, let previewDrag, previewDrag.point == nil, let editor else { return nil }
        return (previewDrag.tileID, pick(around: previewDrag.tileID, in: editor))
    }

    /// 길게 눌러 집히는 덩어리 — 받침대는 딱 붙은 이어진 타일, 판은 누른 타일에서 가까운 끝까지(⌥ 없이 쪼개기).
    private func pick(around id: Int, in editor: RummyTurnEditor) -> [Int] {
        editor.rack.contains { $0.id == id } ? editor.rackChain(around: id) : editor.meldChunk(for: id)
    }

    private func resolve(_ drag: RummyDragState, L: RummyMatchLayout, layout: RummyTableLayout,
                         canvas: RummyCanvasTransform) -> RummyDropTarget? {
        switch drag.kind {
        case .set(let index):
            let count = layout.counts.indices.contains(index) ? layout.counts[index] : drag.tiles.count
            return RummyDropResolver.setTarget(pointer: drag.point, grab: drag.grab, tiles: count, layout: L, canvas: canvas)
                .map { .newMeldAt($0) }
        case .tiles:
            return RummyDropResolver.target(pointer: drag.point, grabIndex: drag.grabIndex, count: drag.tiles.count,
                                            layout: L, canvas: canvas, table: layout, rack: rackGeometry(L),
                                            isMyTurn: isMyTurn, skipMeld: wholeMeld(drag.ids))
        }
    }

    /// 판 타일을 받침대 위로 끄는 중 — 놓기 거절 표시.
    private func refused(_ drag: RummyDragState?, target: RummyDropTarget?) -> Bool {
        guard let drag, let target, RummyStore.isRackTarget(target), let editor else { return false }
        return drag.ids.contains(where: editor.isFromTable)
    }

    // MARK: 조립

    @ViewBuilder
    private func content(_ L: RummyMatchLayout) -> some View {
        let model = board
        let canvas = transform(L, layout: model.layout)
        let geometry = rackGeometry(L)
        let dragging = activeDrag
        let target = dragging.flatMap { resolve($0, L: L, layout: model.layout, canvas: canvas) }
        let isRefused = refused(dragging, target: target)
        let lift = activeLift
        let arrangement = RummySeatArrangement.arrange(seatNos: seats.compactMap(\.seatNo), mine: match.mySeatNo)
        ZStack(alignment: .topLeading) {
            RummyPotCard(match: match)
                .frame(width: L.potCard.width, height: L.potCard.height)
                .offset(x: L.potCard.minX, y: L.potCard.minY)
            RummyPoolCard(count: match.poolCount)
                .frame(width: L.poolCard.width, height: L.poolCard.height)
                .offset(x: L.poolCard.minX, y: L.poolCard.minY)
            // 0.3.70: 창 머리글(루비 · 반응 · 규칙 · 기권)이 위 띠 빈칸으로 — 판 칸이 그만큼 높다.
            HStack(spacing: 8) {
                RubyBalanceChip(balance: scene.shownRubyBalance, large: true)
                    .checkTooltip("내 루비")
                RummyReactionButton(store: store)
            }
            .frame(width: L.chromeLeft.width, height: L.chromeLeft.height)
            .offset(x: L.chromeLeft.minX, y: L.chromeLeft.minY)
            HStack(spacing: 8) {
                TetrisDuelActionButton(title: RummyText.rulesButton, icon: "book.fill", style: .outline,
                                       height: 30, action: { store.rulesShown = true })
                if scene.mySeat?.state == .playing {
                    TetrisDuelActionButton(title: RummyText.forfeit, icon: "flag.fill", tint: CheckTheme.danger,
                                           style: .outline, height: 30, action: onForfeit)
                }
            }
            .frame(width: L.chromeRight.width, height: L.chromeRight.height)
            .offset(x: L.chromeRight.minX, y: L.chromeRight.minY)
            if let seat = seat(arrangement.top) {
                RummySeatCard(store: store, scene: scene, match: match, seat: seat, style: .top)
                    .frame(width: L.topSeat.width, height: L.topSeat.height)
                    .rummyReactionAnchor(seatNo: seat.seatNo, edge: .trailing)
                    .offset(x: L.topSeat.minX, y: L.topSeat.minY)
            }
            if let seat = seat(arrangement.left) {
                RummySeatCard(store: store, scene: scene, match: match, seat: seat, style: .side)
                    .frame(width: L.leftSeat.width, height: L.leftSeat.height)
                    .rummyReactionAnchor(seatNo: seat.seatNo, edge: .trailing)
                    .offset(x: L.leftSeat.minX, y: L.leftSeat.minY)
            }
            if let seat = seat(arrangement.right) {
                RummySeatCard(store: store, scene: scene, match: match, seat: seat, style: .side)
                    .frame(width: L.rightSeat.width, height: L.rightSeat.height)
                    .rummyReactionAnchor(seatNo: seat.seatNo, edge: .leading)
                    .offset(x: L.rightSeat.minX, y: L.rightSeat.minY)
            }
            tableArea(L, model: model, canvas: canvas, dragging: dragging, target: target, lift: lift)
                .frame(width: L.table.width, height: L.table.height)
                .offset(x: L.table.minX, y: L.table.minY)
            if shownTurnBadge {
                RummyTurnBadge()
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                    .position(x: L.table.midX, y: L.table.midY)
            }
            if let mine = scene.mySeat {
                RummySeatCard(store: store, scene: scene, match: match, seat: mine, style: .mine)
                    .frame(width: L.mySeat.width, height: L.mySeat.height)
                    .rummyReactionAnchor(seatNo: mine.seatNo, edge: .top)
                    .offset(x: L.mySeat.minX, y: L.mySeat.minY)
            }
            rackArea(L, geometry: geometry, dragging: dragging, target: target, refused: isRefused, lift: lift, canvas: canvas)
                .frame(width: L.rack.width, height: L.rack.height)
                .offset(x: L.rack.minX, y: L.rack.minY)
            actions(L)
                .frame(width: L.actions.width, height: L.actions.height, alignment: .top)
                .offset(x: L.actions.minX, y: L.actions.minY)
            if let dragging {
                floatingBlock(dragging, L: L, canvas: canvas, refused: isRefused)
            }
        }
        .frame(width: L.size.width, height: L.size.height, alignment: .topLeading)
    }

    private var seats: [RummyMatchSeat] {
        (match.seats ?? []).filter { $0.seatNo != nil }.sorted { ($0.seatNo ?? 0) < ($1.seatNo ?? 0) }
    }

    private func seat(_ seatNo: Int?) -> RummyMatchSeat? {
        guard let seatNo else { return nil }
        return seats.first { $0.seatNo == seatNo }
    }

    // MARK: 판

    private func tableArea(_ L: RummyMatchLayout, model: (melds: [RummyBoardMeld], layout: RummyTableLayout),
                           canvas: RummyCanvasTransform, dragging: RummyDragState?, target: RummyDropTarget?,
                           lift: (tileID: Int, ids: [Int])?) -> some View {
        let preview = dragging.flatMap { boardPreview($0, target: target, layout: model.layout) }
        let movingSet: Int? = {
            if case .set(let index)? = dragging?.kind { return index }
            return nil
        }()
        return ZStack(alignment: .bottom) {
            RummyTableCanvasView(
                melds: model.melds, transform: canvas, size: L.table.size, editable: isMyTurn && !scene.isWorking,
                draggingTileIDs: dragging.map { Set($0.ids) } ?? [], liftedTileIDs: Set(lift?.ids ?? []),
                movingSet: movingSet, preview: preview,
                arrivals: arrival.flatMap { $0.landed ? nil : $0.starts } ?? [:], recentTileIDs: recentDrop,
                reduceMotion: reduceMotion,
                onTileDrag: { id, value in tileChanged(id, value, surface: .board, canvas: canvas) },
                onTileDragEnd: { id, value in tileEnded(id, value, L: L) },
                onHandleDrag: { index, value in
                    freeze(canvas)
                    handleChanged(index, value, L: L, canvas: canvas, layout: model.layout)
                },
                onHandleDragEnd: { _, value in tileEnded(-1, value, L: L) })
            HStack(alignment: .bottom, spacing: 8) {
                if let event = RummyText.lastEvent(match.lastEvent, name: scene.name(of: match.lastEvent?.seatNo)) {
                    Text(event)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                }
                Spacer(minLength: 8)
                if !isMyTurn, let name = scene.turnSeat?.displayName {
                    Label(scene.otherDraft != nil ? RummyText.placing(name) : RummyText.turnOf(name),
                          systemImage: scene.otherDraft != nil ? "hand.draw.fill" : "hourglass")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(CheckTheme.panelElevated))
                        .overlay(Capsule().stroke(CheckTheme.accent.opacity(0.5), lineWidth: 1))
                }
            }
            .padding(10)
            .allowsHitTesting(false)
        }
    }

    // MARK: 받침대

    private func rackArea(_ L: RummyMatchLayout, geometry: RummyRackGeometry, dragging: RummyDragState?,
                          target: RummyDropTarget?, refused: Bool, lift: (tileID: Int, ids: [Int])?,
                          canvas: RummyCanvasTransform) -> some View {
        // 0.3.70 끼워 넣기 미리보기: 같은 놓기를 편집기 사본에 해 본 받침대(= 실제). 이웃이 비켜 서고 점선이 놓일 자리.
        let dropped: RummyTurnEditor? = {
            guard !refused, let dragging, case .rackSlot(let wanted)? = target, let editor else { return nil }
            var copy = editor
            return copy.moveBlock(dragging.ids, to: .rackSlot(wanted)) ? copy : nil
        }()
        let ghosts: [RummyRackSlot] = dropped.map { after in dragging?.ids.compactMap { after.rackLayout.slot(of: $0) } ?? [] } ?? []
        let shown = dropped ?? editor
        // 미리보기가 새 줄을 열면 그리는 기하만 그 줄 수로(놓는 판정 기하는 그대로 — 끄는 동안 되먹임이 없게).
        let drawGeometry = dropped.map { RummyRackGeometry(height: L.rackHeight, rowCount: $0.rackLayout.rowCount) } ?? geometry
        let origin = CGPoint(x: L.drawButton.midX - L.rack.minX, y: L.drawButton.midY - L.rack.minY)
        return RummyRackView(
            tiles: editor?.rack ?? [], layout: editor?.rackLayout ?? RummyRackLayout(), geometry: drawGeometry,
            size: L.rack.size, draggingTileIDs: dragging.map { Set($0.ids) } ?? [],
            liftedTileIDs: Set(lift?.ids ?? []), liftBadge: lift.map { ($0.tileID, $0.ids.count) },
            ghostSlots: ghosts, refused: refused || refusedFlash, stagger: stagger, flyIn: flyIn, flyOrigin: origin,
            reduceMotion: reduceMotion,
            onTileDrag: { id, value in tileChanged(id, value, surface: .rack, canvas: canvas) },
            onTileDragEnd: { id, value in tileEnded(id, value, L: L) },
            previewLayout: dropped?.rackLayout,
            freshTileIDs: cuePreview?.freshTileIDs ?? freshDraw?.ids ?? [],
            rackMelds: shown?.rackMelds ?? [],
            planPoints: shown?.initialPlanPoints.map { (table: isMyTurn ? $0.table : 0, rack: $0.rack) },
            turnGlow: shownTurnGlow)
    }

    // MARK: 손에 든 것

    private func floatingBlock(_ drag: RummyDragState, L: RummyMatchLayout, canvas: RummyCanvasTransform,
                               refused: Bool) -> some View {
        let overTable = L.table.contains(drag.point)
        let size = overTable ? RummyTileSize.canvas(scale: canvas.scale) : RummyTileSize.rack
        let n = CGFloat(drag.tiles.count)
        let grab: CGFloat
        if case .set = drag.kind { grab = 0 } else { grab = CGFloat(drag.grabIndex) + 0.5 }
        return HStack(spacing: 1) {
            ForEach(drag.tiles) { tile in
                RummyTileView(face: tile.face, size: size)
            }
        }
        .scaleEffect(1.06)
        .shadow(color: .black.opacity(0.45), radius: 8, y: 6)
        // 아래 스냅 자리 점선이 비쳐 보이게.
        .opacity(0.92)
        .overlay(alignment: .topTrailing) {
            if refused {
                Image(systemName: "nosign")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(RummyTilePalette.color(RummyTilePalette.invalid))
                    .background(Circle().fill(Color.white).padding(-1))
                    .offset(x: 8, y: -8)
            } else if drag.tiles.count > 1 {
                RummyCountBadge(count: drag.tiles.count).offset(x: 9, y: -10)
            }
        }
        .position(x: drag.point.x + (n / 2 - grab) * (size.size.width + 1), y: drag.point.y)
        .allowsHitTesting(false)
    }

    // MARK: 끌기

    private func tileChanged(_ id: Int, _ value: DragGesture.Value, surface: RummyPressState.Surface,
                             canvas: RummyCanvasTransform) {
        guard editor != nil else { return }
        freeze(canvas)
        if drag != nil {
            drag?.point = value.location
            return
        }
        if press?.tileID != id {
            pressSerial += 1
            let token = pressSerial
            press = RummyPressState(tileID: id, token: token, surface: surface, picked: nil)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int(Self.liftDelay * 1000)))
                guard press?.token == token, drag == nil, let editor else { return }
                let ids = surface == .rack ? editor.rackChain(around: id) : editor.meldChunk(for: id)
                guard !ids.isEmpty else { return }
                press?.picked = ids
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
        let moved = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
        guard moved >= 3 else { return }
        let ids = press?.picked ?? [id]
        let tiles = ids.compactMap(tile)
        guard !tiles.isEmpty else { return }
        drag = RummyDragState(kind: .tiles, tiles: tiles, grabIndex: ids.firstIndex(of: id) ?? 0, point: value.location)
        press = nil
    }

    private func handleChanged(_ index: Int, _ value: DragGesture.Value, L: RummyMatchLayout,
                               canvas: RummyCanvasTransform, layout: RummyTableLayout) {
        if drag != nil {
            drag?.point = value.location
            return
        }
        guard isMyTurn, let editor, editor.melds.indices.contains(index), let frame = layout.frame(of: index) else { return }
        let start = canvas.toLogical(CGPoint(x: value.startLocation.x - L.table.minX, y: value.startLocation.y - L.table.minY))
        drag = RummyDragState(kind: .set(index), tiles: editor.melds[index], grabIndex: 0, point: value.location,
                              grab: CGPoint(x: start.x - CGFloat(frame.x), y: start.y - CGFloat(frame.y)))
    }

    private func tileEnded(_ id: Int, _ value: DragGesture.Value, L: RummyMatchLayout) {
        defer {
            drag = nil
            press = nil
            thaw()
        }
        guard var finished = drag, let editor else { return }
        finished.point = value.location
        let model = board
        let canvas = transform(L, layout: model.layout)
        guard let target = resolve(finished, L: L, layout: model.layout, canvas: canvas) else { return }
        switch finished.kind {
        case .set(let index):
            if case .newMeldAt(let point) = target {
                land(finished, L: L, canvas: canvas)
                store.moveSet(index, to: point)
            }
        case .tiles:
            if RummyStore.isRackTarget(target), finished.ids.contains(where: editor.isFromTable) {
                // 판에 있던 타일은 받침대로 안 간다(R-14) — 놓지 않고 받침대를 잠깐 빨갛게.
                refusedFlash = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    refusedFlash = false
                }
                return
            }
            if !RummyStore.isRackTarget(target) { land(finished, L: L, canvas: canvas) }
            if case .newMeldAt(let point) = target, let whole = wholeMeld(finished.ids) {
                store.moveSet(whole, to: point)
            } else {
                store.moveTiles(finished.ids, to: target)
            }
        }
    }

    /// 놓기 미리보기(3판) — 편집기에 "놓으면 어떻게 되는가"를 묻는다(바꾸지 않는다). 놓을 때 부르는 길과 **같은 갈래**:
    /// 손잡이 끌기 · 묶음 통째를 빈 곳에 = `previewMoveSet`, 나머지 = `previewDrop`. 받침대행·거절·남의 차례는 nil.
    private func boardPreview(_ dragging: RummyDragState, target: RummyDropTarget?,
                              layout: RummyTableLayout) -> RummyBoardPreview? {
        guard isMyTurn, let editor, let target, !RummyStore.isRackTarget(target) else { return nil }
        let ids = editor.melds.map { $0.map(\.id) }
        let dragged = Set(dragging.ids)
        func moveSet(_ index: Int, _ point: RummyPoint) -> RummyBoardPreview? {
            guard editor.melds.indices.contains(index) else { return nil }
            return .make(editor.previewMoveSet(index, to: point), blockCount: editor.melds[index].count,
                         meldTileIDs: ids, frames: layout.frames, dragged: dragged)
        }
        switch (dragging.kind, target) {
        case (.set(let index), .newMeldAt(let point)):
            return moveSet(index, point)
        case (.set, _):
            return nil
        case (.tiles, .newMeldAt(let point)) where wholeMeld(dragging.ids) != nil:
            return moveSet(wholeMeld(dragging.ids) ?? 0, point)
        case (.tiles, _):
            let preview = RummyBoardPreview.make(editor.previewDrop(dragging.ids, to: target), blockCount: dragging.ids.count,
                                                 meldTileIDs: ids, frames: layout.frames, dragged: dragged)
            guard !editor.initialDone, let set = preview?.targetSet, editor.melds.indices.contains(set) else { return preview }
            return preview?.beforeInitial(touchesTable: editor.melds[set].contains { editor.isFromTable($0.id) })
        }
    }

    /// 판에 놓는 순간 — 손에 든 타일이 떠 있던 자리(논리 왼쪽 위)를 출발점으로 적어 둔다. 캔버스는 한 장면만 거기 그리고,
    /// 다음 장면부터 편집기가 정한 자리(붙은 끝 · 맞는 정렬 자리 · 새 자리)로 스프링으로 미끄러뜨린다. 동작 줄이기면 바로 제자리.
    private func land(_ drag: RummyDragState, L: RummyMatchLayout, canvas: RummyCanvasTransform) {
        recentDrop = Set(drag.ids)
        guard !reduceMotion, L.table.contains(drag.point) else {
            arrival = nil
            return
        }
        // `floatingBlock` 과 같은 산식: 판 위에선 판 크기 타일 · 1pt 간격 · 1.06 배(가운데 기준).
        let step = CGFloat(RummyTableLayout.tileWidth) * canvas.scale + 1
        let n = CGFloat(drag.tiles.count)
        let grab: CGFloat
        if case .set = drag.kind { grab = 0 } else { grab = CGFloat(drag.grabIndex) + 0.5 }
        let center = drag.point.x + (n / 2 - grab) * step
        var starts: [Int: CGPoint] = [:]
        for (i, tile) in drag.tiles.enumerated() {
            let x = center + (CGFloat(i) + 0.5 - n / 2) * step * 1.06
            let logical = canvas.toLogical(CGPoint(x: x - L.table.minX, y: drag.point.y - L.table.minY))
            starts[tile.id] = CGPoint(x: logical.x - CGFloat(RummyTableLayout.tileWidth) / 2,
                                      y: logical.y - CGFloat(RummyTableLayout.tileHeight) / 2)
        }
        arrivalSerial += 1
        let serial = arrivalSerial
        arrival = RummyArrival(serial: serial, starts: starts, landed: false)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(24))
            guard arrival?.serial == serial else { return }
            arrival?.landed = true
            try? await Task.sleep(for: .milliseconds(900))
            if arrival?.serial == serial { arrival = nil }
        }
    }

    // MARK: 버튼

    private func sort(_ mode: RummyRackSort) {
        guard let editor else { return }
        if !reduceMotion {
            var sorted = editor
            sorted.sortRack(mode)
            stagger = Dictionary(uniqueKeysWithValues: sorted.rackLayout.readingOrder.enumerated().map { ($1, Double($0) * 0.025) })
        }
        store.sortRack(mode)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            stagger = [:]
        }
    }

    private func actions(_ L: RummyMatchLayout) -> some View {
        let busy = scene.isWorking
        let canEdit = isMyTurn && !busy
        let poolEmpty = (match.poolCount ?? 0) == 0
        let status = statusText
        return VStack(spacing: RummyMatchLayout.actionSpacing) {
            TetrisDuelActionButton(title: RummyText.submit, icon: "checkmark", tint: CheckTheme.working,
                                   height: RummyMatchLayout.submitHeight, fullWidth: true,
                                   isEnabled: canEdit && editor?.canSubmit == true,
                                   action: { store.submitTurn() })
                // 0.3.70: 남은 초를 손 가까이 — [완료] 오른쪽 안(10초 이하 주황 · 5초 이하 빨강).
                .overlay(alignment: .trailing) {
                    if isMyTurn {
                        RummySubmitSeconds(remaining: scene.turnRemaining(store), fixedNow: scene.fixedNow)
                            .padding(.trailing, 10)
                    }
                }
            HStack(spacing: RummyMatchLayout.actionSpacing) {
                TetrisDuelActionButton(title: poolEmpty ? RummyText.pass : RummyText.draw,
                                       icon: poolEmpty ? "forward.fill" : "plus.rectangle.on.rectangle",
                                       tint: CheckTheme.pending, style: .outline,
                                       height: RummyMatchLayout.buttonHeight, fullWidth: true,
                                       isEnabled: canEdit, action: { store.drawTile() })
                TetrisDuelActionButton(title: RummyText.undo, icon: "arrow.uturn.backward", style: .outline,
                                       height: RummyMatchLayout.buttonHeight, fullWidth: true,
                                       isEnabled: canEdit && (editor?.isChanged == true || editor?.isLayoutChanged == true),
                                       action: { store.resetTurn() })
                    .checkTooltip("이번 차례에 놓은 것을 처음으로")
            }
            HStack(spacing: RummyMatchLayout.actionSpacing) {
                RummySortSwitch(selected: shownSortMode, enabled: editor != nil, onSort: sort)
                TetrisDuelActionButton(title: isZoomed ? RummyMatchText.zoomOut : RummyMatchText.zoomIn,
                                       icon: isZoomed ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass",
                                       style: .outline, height: RummyMatchLayout.smallButtonHeight, fullWidth: true,
                                       action: { zoomed.toggle() })
                    .checkTooltip("놓인 묶음에 맞춰 판을 크게 봐요")
            }
            Text(status.text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(status.tint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
        }
    }

    /// 상태 글자 — 서버·판정 문구는 스토어 `notice`, 내 차례 글자는 `RummyText.myTurnStatus`(첫 등록 진행 ·
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
}

/// 정렬 두 갈래(777 · 789) 분절 버튼.
private struct RummySortSwitch: View {
    let selected: RummyRackSort?
    let enabled: Bool
    let onSort: (RummyRackSort) -> Void

    var body: some View {
        HStack(spacing: 2) {
            segment(.number, title: RummyText.sortNumber, tip: "같은 숫자끼리 모아요")
            segment(.color, title: RummyText.sortColor, tip: "색별로 이어지게 모아요")
        }
        .padding(2)
        .frame(height: RummyMatchLayout.smallButtonHeight)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().stroke(CheckTheme.border, lineWidth: 1))
        .opacity(enabled ? 1 : 0.45)
    }

    private func segment(_ mode: RummyRackSort, title: String, tip: String) -> some View {
        let on = selected == mode
        return Button(action: { onSort(mode) }) {
            Text(title)
                .font(.callout.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(on ? Color.white : CheckTheme.primaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(on ? CheckTheme.accent.opacity(0.85) : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .checkTooltip(tip)
    }
}

// MARK: - 자리 카드

/// 차례 시간 링 — **잎 뷰**만 시계를 읽는다. `fixedNow` 가 있으면(렌더 시험) 그 시각으로 한 번만 그린다.
struct RummyTurnRing: View {
    let remaining: (Date) -> TimeInterval?
    let total: TimeInterval
    let fixedNow: Date?
    let diameter: CGFloat
    var lineWidth: CGFloat = 4

    var body: some View {
        if let fixedNow {
            ring(at: fixedNow)
        } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in ring(at: context.date) }
        }
    }

    private func ring(at date: Date) -> some View {
        let left = remaining(date) ?? total
        let fraction = min(1, max(0, left / max(total, 1)))
        let tint = left <= 5 ? CheckTheme.danger : (left <= 10 ? CheckTheme.pending : CheckTheme.accent)
        return ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct RummySeatCard: View {
    enum Style { case side, top, mine }

    let store: RummyStore
    let scene: RummyScene
    let match: RummyMatchState
    let seat: RummyMatchSeat
    let style: Style

    private var isTurn: Bool { seat.seatNo == match.turnSeatNo && seat.state == .playing && match.status == .active }
    private var forfeited: Bool { seat.state == .forfeit }
    private var turnTotal: TimeInterval {
        guard let start = match.turnStartedMs, let end = match.turnDeadlineMs, end > start else { return 60 }
        return (end - start) / 1000
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Group {
            switch style {
            case .side: side
            case .top: top
            case .mine: mine
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(isTurn ? CheckTheme.accent.opacity(0.13) : CheckTheme.panel.opacity(0.88)))
        .overlay(shape.stroke(isTurn ? CheckTheme.accent : CheckTheme.border, lineWidth: isTurn ? 2 : 1))
        .opacity(forfeited ? 0.5 : 1)
    }

    private func avatar(_ size: CGFloat) -> some View {
        ZStack {
            if isTurn {
                RummyTurnRing(remaining: scene.turnRemaining(store), total: turnTotal, fixedNow: scene.fixedNow,
                              diameter: size + 10)
            }
            CheckAvatarView(name: seat.displayName ?? "?", userID: seat.userId.uuidString.lowercased(),
                            avatarURL: seat.avatarUrl.flatMap(URL.init(string:)), size: size,
                            characterHint: seat.character)
        }
        .frame(width: size + 10, height: size + 10)
    }

    @ViewBuilder
    private var chips: some View {
        if forfeited {
            RummyChip(text: RummyText.forfeit, tint: CheckTheme.danger)
        } else if seat.initialDone == false {
            RummyChip(text: RummyText.beforeInitial, tint: CheckTheme.pending)
        }
        if let streak = seat.timeoutStreak, streak > 0, !forfeited {
            RummyChip(text: RummyText.timeouts(streak), tint: CheckTheme.danger)
        }
    }

    private var backs: some View {
        HStack(spacing: -6) {
            ForEach(0..<min(4, max(1, seat.rackCount ?? 0)), id: \.self) { _ in RummyTileBack() }
        }
    }

    private var seconds: some View {
        RummyCountdownLeaf(remaining: scene.turnRemaining(store), fixedNow: scene.fixedNow, label: RummyText.seconds)
            .font(.callout.weight(.heavy))
    }

    private var side: some View {
        VStack(spacing: 7) {
            avatar(54)
            Text(seat.displayName ?? "?").font(.callout.weight(.bold)).lineLimit(1)
            HStack(spacing: 8) {
                backs
                Text(RummyText.rackCount(seat.rackCount))
                    .font(.title3.weight(.heavy))
                    .monospacedDigit()
            }
            VStack(spacing: 4) { chips }
            if isTurn { seconds }
        }
        .padding(10)
    }

    private var top: some View {
        HStack(spacing: 10) {
            avatar(30)
            VStack(alignment: .leading, spacing: 2) {
                Text(seat.displayName ?? "?").font(.callout.weight(.bold)).lineLimit(1)
                HStack(spacing: 4) { chips }
            }
            Spacer(minLength: 4)
            backs
            Text(RummyText.rackCount(seat.rackCount)).font(.callout.weight(.heavy)).monospacedDigit()
            if isTurn { seconds }
        }
        .padding(.horizontal, 10)
    }

    private var mine: some View {
        VStack(spacing: 6) {
            avatar(44)
            HStack(spacing: 5) {
                Text(seat.displayName ?? "?").font(.callout.weight(.bold)).lineLimit(1)
                RummyChip(text: RummyMatchText.me, tint: CheckTheme.accent)
            }
            HStack(spacing: 6) {
                Text(RummyText.rackCount(seat.rackCount)).font(.caption.weight(.bold)).monospacedDigit()
                    .foregroundStyle(CheckTheme.secondaryText)
                if isTurn { seconds }
            }
            if seat.initialDone == false, !forfeited {
                initialProgress
            } else {
                HStack(spacing: 4) { chips }
            }
        }
        .padding(8)
    }

    /// 첫 등록 진행(내 차례 편집기 기준 · 30점).
    private var initialProgress: some View {
        let points = scene.editor?.initialPoints ?? 0
        let fraction = min(1, Double(points) / 30)
        return VStack(spacing: 3) {
            HStack {
                Text(RummyMatchText.initialProgress).font(.caption2.weight(.semibold))
                Spacer()
                Text("\(points) / 30").font(.caption2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(points >= 30 ? CheckTheme.working : CheckTheme.primaryText)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(points >= 30 ? CheckTheme.working : CheckTheme.pending)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 4)
    }
}

/// 판돈 카드(위 왼쪽).
private struct RummyPotCard: View {
    let match: RummyMatchState

    var body: some View {
        HStack(spacing: 10) {
            RubyIcon(size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(RummyMatchText.pot(stake: match.stake, seats: match.seatCount))
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
                Text(RummyText.split(seatCount: match.seatCount, stake: match.stake))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CheckTheme.panel.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}

/// 더미 카드(위 오른쪽).
private struct RummyPoolCard: View {
    let count: Int?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    RummyTileBack(size: CGSize(width: 16, height: 22)).offset(x: CGFloat(i) * 3, y: CGFloat(-i) * 2)
                }
            }
            .frame(width: 26, height: 28)
            Text("\(count ?? 0)")
                .font(.title3.weight(.heavy))
                .monospacedDigit()
            Text(RummyMatchText.pool)
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CheckTheme.panel.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}

// MARK: - 결과는 `RummyPanelResult.swift`(2판 — 한 판 더 · 최종 판).
