import CheckCore
import CoreGraphics
import Foundation

// 폰 아잉 큐브 판 화면의 **순수 값**(설계서 §10 — 판 화면만 가로). `#if os(iOS)` 밖이다 — 폰 뷰는 맥 스위트가 못 보므로 칸 자리 · 보기 · 받침대 · 누르기 판정을 값으로 재는 자리가 여기다.
// 그리는 자리·누르는 자리·놓는 자리가 전부 이 값에서 나온다(맥 `RummyMatchLayout`·`RummyRackGeometry` 와 같은 원칙 · 배치는 폰 가로 화면용으로 다시 짰다).
// 좌표는 전부 판 화면 좌표(세이프 영역 안 왼쪽 위 원점 · `coordinateSpace: .named`)다.

/// 판 화면 칸 자리(가로 화면 · 세이프 영역 안 좌표, 설계서 §10.2) — 왼쪽 열(뒤로 · 규칙 · 자리 카드) | 가운데(판 · 상태 줄 · 받침대) | 오른쪽 열(판돈 · 더미 · 반응 · 전체 보기 · 동작 버튼).
/// **받침대 높이는 줄 수로 안 변한다** — 판 칸이 안 흔들린다(줄이 늘면 타일이 준다). 안드로이드가 아래 상수 이름을 비율로 옮겨 쓴다.
package struct GamesRummyMatchLayout: Equatable, Sendable {
    package static let leftColumnWidth: CGFloat = 86
    package static let rightColumnWidth: CGFloat = 100
    package static let statusHeight: CGFloat = 18
    /// 받침대 높이 상한(화면 높이 비율) — 판 칸이 먼저 살아야 한다.
    package static let rackMaxHeightShare: CGFloat = 0.4
    /// 열 안쪽 여백.
    package static let columnPadding: CGFloat = 4
    /// 오른쪽 열 칸 사이 틈.
    package static let actionGap: CGFloat = 6
    /// 왼쪽 열 [뒤로] · [규칙] 줄 높이.
    package static let navHeight: CGFloat = 44
    /// 오른쪽 열 판돈 · 더미 높이.
    package static let infoHeight: CGFloat = 40
    /// 오른쪽 열 [반응] · [전체 보기] 줄 높이.
    package static let toolsHeight: CGFloat = 44
    /// 왼쪽 열 원형 버튼 지름(열 폭 86 에 둘이 들어간다. 줄 높이 44 가 터치 높이다).
    package static let navButtonDiameter: CGFloat = 38
    /// 상대 카드 최대 수(4인 판). 내 자리까지 네 칸을 늘 같은 높이로 나눈다 — 인원에 따라 카드가 안 늘어난다.
    package static let maxOpponentCards = 3
    package static let seatCardMaxHeight: CGFloat = 76
    package static let seatCardGap: CGFloat = 4
    /// 동작 버튼 넷이 남는 높이를 나누는 비율([완료] · [뽑기|넘기기] · [되돌리기] · [777|789]).
    package static let actionShares: (submit: CGFloat, draw: CGFloat, undo: CGFloat, sort: CGFloat) = (0.34, 0.24, 0.22, 0.20)
    /// 다른 기기 안내 카드의 판 아래 여백 · 어림 높이(배지를 그 위로 올린다).
    package static let elsewhereCardBottom: CGFloat = 6
    package static let elsewhereCardHeight: CGFloat = 60
    /// 동작 버튼 최소 높이(터치).
    package static let minActionHeight: CGFloat = 44

    package let size: CGSize
    package let rackRows: Int

    package init(size: CGSize, rackRows: Int = RummyRackLayout.baseRows) {
        self.size = size
        self.rackRows = max(RummyRackLayout.baseRows, rackRows)
    }

    /// 가로로 선 크기인가. 방향 전환 중에는 세로 크기로 한 프레임 불릴 수 있다 — 그때 칸을 세우지 않는다(`GamesRummyMatch.swift`).
    package static func isLandscape(_ size: CGSize) -> Bool { size.width > size.height }

    // MARK: 가운데

    private var centerWidth: CGFloat { max(0, size.width - Self.leftColumnWidth - Self.rightColumnWidth) }
    package var rackHeight: CGFloat {
        GamesRummyRackGeometry.height(forWidth: centerWidth, maxHeight: size.height * Self.rackMaxHeightShare)
    }
    package var rack: CGRect {
        CGRect(x: Self.leftColumnWidth, y: size.height - rackHeight, width: centerWidth, height: rackHeight)
    }
    package var status: CGRect {
        CGRect(x: Self.leftColumnWidth, y: rack.minY - Self.statusHeight, width: centerWidth, height: Self.statusHeight)
    }
    /// 판 — 가운데의 남는 높이 전부.
    package var table: CGRect {
        CGRect(x: Self.leftColumnWidth, y: 0, width: centerWidth, height: max(0, status.minY))
    }

    // MARK: 왼쪽 열

    package var leftColumn: CGRect { CGRect(x: 0, y: 0, width: Self.leftColumnWidth, height: size.height) }
    package var nav: CGRect {
        CGRect(x: Self.columnPadding, y: 0, width: Self.leftColumnWidth - Self.columnPadding * 2, height: Self.navHeight)
    }

    private var seatCardHeight: CGFloat {
        let slots = CGFloat(Self.maxOpponentCards + 1)
        let room = size.height - nav.maxY - Self.columnPadding - Self.seatCardGap * slots
        return max(0, min(Self.seatCardMaxHeight, room / slots))
    }

    /// 상대 카드 `index` 번째(내 다음 차례부터 위에서 아래로).
    package func opponentCard(_ index: Int) -> CGRect {
        let top = nav.maxY + Self.seatCardGap + CGFloat(max(0, index)) * (seatCardHeight + Self.seatCardGap)
        return CGRect(x: Self.columnPadding, y: top, width: nav.width, height: seatCardHeight)
    }

    /// 내 자리 카드 — 왼쪽 열 맨 아래(몇 명이 앉든 같은 자리).
    package var mySeatCard: CGRect {
        CGRect(x: Self.columnPadding, y: size.height - Self.columnPadding - seatCardHeight, width: nav.width, height: seatCardHeight)
    }

    // MARK: 오른쪽 열

    package var rightColumn: CGRect {
        CGRect(x: size.width - Self.rightColumnWidth, y: 0, width: Self.rightColumnWidth, height: size.height)
    }
    private var rightCellX: CGFloat { rightColumn.minX + Self.columnPadding }
    private var rightCellWidth: CGFloat { Self.rightColumnWidth - Self.columnPadding * 2 }
    package var info: CGRect { CGRect(x: rightCellX, y: Self.columnPadding, width: rightCellWidth, height: Self.infoHeight) }
    package var tools: CGRect { CGRect(x: rightCellX, y: info.maxY + Self.actionGap, width: rightCellWidth, height: Self.toolsHeight) }

    /// 버튼 넷 칸(위에서 아래로). 어떤 높이에서도 합이 열을 안 넘는다.
    private var actionRects: (submit: CGRect, draw: CGRect, undo: CGRect, sort: CGRect) {
        let top = tools.maxY + Self.actionGap
        let room = max(0, size.height - Self.columnPadding - top - Self.actionGap * 3)
        func cell(_ y: CGFloat, _ share: CGFloat) -> CGRect { CGRect(x: rightCellX, y: y, width: rightCellWidth, height: room * share) }
        let submit = cell(top, Self.actionShares.submit)
        let draw = cell(submit.maxY + Self.actionGap, Self.actionShares.draw)
        let undo = cell(draw.maxY + Self.actionGap, Self.actionShares.undo)
        let sort = cell(undo.maxY + Self.actionGap, Self.actionShares.sort)
        return (submit, draw, undo, sort)
    }
    package var submit: CGRect { actionRects.submit }
    package var draw: CGRect { actionRects.draw }
    package var undo: CGRect { actionRects.undo }
    package var sort: CGRect { actionRects.sort }

    // MARK: 들어 올림 — 받침대가 화면 맨 아래다

    /// 손 자리 → 들어 올릴 거리. 판 위에서는 늘 48pt. 받침대 안에서는 아래로 갈수록 준다:
    /// 가로 화면은 받침대 아래에 아무것도 없어서, 48pt 그대로면 아랫줄에 놓을 손 자리가 화면 끝 몇 pt 뿐이다(세로판은 동작 줄이 그 자리를 벌어 줬다).
    /// 손 y 가 커질수록 기준점 y 도 늘 커진다(뒤집히지 않는다).
    package func fingerLift(atY y: CGFloat) -> CGFloat {
        let full = GamesRummyGestureRules.fingerLift, low = GamesRummyGestureRules.fingerLiftAtBottom
        guard y > rack.minY, rack.height > 0 else { return full }
        return full + (low - full) * min(1, (y - rack.minY) / rack.height)
    }

    /// 기준점이 `pointer` 에 오는 손 자리(`fingerLift` 의 역). 궤적을 세우는 데모 · 시험이 쓴다.
    package func finger(forPointer pointer: CGPoint) -> CGPoint {
        let full = GamesRummyGestureRules.fingerLift, low = GamesRummyGestureRules.fingerLiftAtBottom
        guard pointer.y + full > rack.minY, rack.height > 0 else { return CGPoint(x: pointer.x, y: pointer.y + full) }
        let progress = (pointer.y + full - rack.minY) / (rack.height + full - low)
        guard progress < 1 else { return CGPoint(x: pointer.x, y: pointer.y + low) }
        return CGPoint(x: pointer.x, y: rack.minY + progress * rack.height)
    }
}

/// 판 보기(배율 · 오프셋). **배율은 판 변화로 저절로 바뀌지 않는다**(맥 교훈 — 놓을 때마다 판이 움직이면 안 된다). 사람이 움직일 때만 바뀐다.
///
/// 기본 보기는 **폭 맞춤**이다(캔버스 1000 이 칸 폭에 꼭 찬다 — iPhone 15 ≈ 0.55, 타일 ≈ 22×31pt, 세로 약 445/640 단위가 보인다). 나머지 세로는 민다. [전체 보기] = 높이까지 맞춘 배율(약 0.39).
/// 위치는 모든 기기에 같다(서버 `table_layout`) — 폰이 재배치하면 안 된다. 상한 = 타일 폭 40pt(배율 1) · 하한 = 전체 맞춤.
package struct GamesRummyViewport: Equatable, Sendable {
    /// 끌기 중 손이 이 안에 머물면 그 쪽으로 민다.
    package static let edgeZone: CGFloat = 28
    /// 가장자리 자동 밀기(논리 단위/초). 동작 줄이기여도 켠다(끌기 기능이지 꾸밈이 아니다).
    package static let edgePanSpeed: CGFloat = 400
    /// 화면 밖 묶음 배지를 눌러 밀 때 묶음 옆에 둘 여백(논리 단위).
    package static let revealMargin: CGFloat = 24
    /// 타일 폭 상한(pt).
    package static let maxTileWidth: CGFloat = 40

    package private(set) var viewport: CGSize
    package private(set) var scale: CGFloat
    /// 칸 왼쪽 위에 오는 논리 점(캔버스가 칸보다 작은 축은 0 — 가운데로 그린다).
    package private(set) var origin: CGPoint

    private static let canvas = RummyCanvasTransform.canvas

    package init(viewport: CGSize) {
        self.viewport = viewport
        scale = Self.defaultScale(viewport)
        origin = .zero
        clamp()
    }

    // MARK: 배율 값

    /// 전체 맞춤 배율(하한).
    package static func fitScale(_ viewport: CGSize) -> CGFloat {
        let scale = min(viewport.width / canvas.width, viewport.height / canvas.height)
        return max(0.01, min(scale, maxScale))
    }

    /// 타일 폭 40pt(논리 타일 폭 40 × 배율 1).
    package static var maxScale: CGFloat { maxTileWidth / CGFloat(RummyTableLayout.tileWidth) }

    /// 기본 보기 배율(폭 맞춤).
    package static func defaultScale(_ viewport: CGSize) -> CGFloat {
        min(maxScale, max(fitScale(viewport), viewport.width / canvas.width))
    }

    package var fitScale: CGFloat { Self.fitScale(viewport) }
    package var defaultScale: CGFloat { Self.defaultScale(viewport) }
    package var isFullView: Bool { abs(scale - fitScale) < 0.0005 }
    package var tileSize: CGSize {
        CGSize(width: CGFloat(RummyTableLayout.tileWidth) * scale, height: CGFloat(RummyTableLayout.tileHeight) * scale)
    }

    /// 지금 보이는 논리 구간.
    package var visibleLogical: CGRect {
        let width = min(Self.canvas.width, viewport.width / scale), height = min(Self.canvas.height, viewport.height / scale)
        return CGRect(x: origin.x, y: origin.y, width: width, height: height)
    }

    /// 그리는 자리·누르는 자리·놓는 자리가 쓰는 한 변환(칸 좌표 ↔ 논리 좌표).
    package var transform: RummyCanvasTransform {
        let shown = CGSize(width: Self.canvas.width * scale, height: Self.canvas.height * scale)
        return RummyCanvasTransform(
            scale: scale, logicalOrigin: origin,
            screenOrigin: CGPoint(x: max(0, (viewport.width - shown.width) / 2),
                                  y: max(0, (viewport.height - shown.height) / 2)))
    }

    // MARK: 움직이기

    /// 핀치 — 칸 좌표 `anchor` 아래의 논리 점을 그 자리에 두고 배율을 바꾼다. [하한, 상한]으로 자른다.
    package mutating func zoom(to wanted: CGFloat, anchor: CGPoint) {
        let logical = transform.toLogical(anchor)
        scale = min(Self.maxScale, max(fitScale, wanted))
        let shown = CGSize(width: Self.canvas.width * scale, height: Self.canvas.height * scale)
        let screenX = max(0, (viewport.width - shown.width) / 2), screenY = max(0, (viewport.height - shown.height) / 2)
        origin = CGPoint(x: logical.x - (anchor.x - screenX) / scale, y: logical.y - (anchor.y - screenY) / scale)
        clamp()
    }

    /// [전체 보기] 토글 — 맞춤 ↔ 기본.
    package mutating func toggleFullView() {
        scale = isFullView ? defaultScale : fitScale
        clamp()
    }

    /// 빈 펠트 끌기 — 손가락과 같은 쪽으로 판이 움직인다(`translation` pt).
    package mutating func pan(by translation: CGSize) {
        origin.x -= translation.width / scale
        origin.y -= translation.height / scale
        clamp()
    }

    /// 칸 크기가 바뀌었다(기기 방향 · 세이프 영역). 기본·맞춤 보기였으면 새 칸의 기본·맞춤으로, 사람이 고른 배율이면 그대로(범위 안으로만).
    package mutating func resize(to viewport: CGSize) {
        guard viewport != self.viewport else { return }
        // 기본을 먼저 묻는다: 전환 중 세로 칸에서는 기본 = 맞춤이라, 맞춤을 먼저 물으면 기본 보기가 돌아온 뒤 전체 보기가 된다.
        let wasDefault = abs(scale - defaultScale) < 0.0005, wasFull = isFullView
        self.viewport = viewport
        if wasDefault {
            scale = defaultScale
        } else if wasFull {
            scale = fitScale
        } else {
            scale = min(Self.maxScale, max(fitScale, scale))
        }
        clamp()
    }

    /// 끌기 중 가장자리 자동 밀기 한 걸음. `pointer` = 칸 좌표. 가로 · 세로를 따로 민다(기본 보기는 세로로 · 키우면 가로로도 움직인다). 움직였으면 true.
    package mutating func edgePan(pointer: CGPoint, deltaTime: TimeInterval) -> Bool {
        let step = Self.edgePanSpeed * CGFloat(deltaTime)
        let before = origin
        if pointer.x < Self.edgeZone {
            origin.x -= step
        } else if pointer.x > viewport.width - Self.edgeZone {
            origin.x += step
        }
        if pointer.y < Self.edgeZone {
            origin.y -= step
        } else if pointer.y > viewport.height - Self.edgeZone {
            origin.y += step
        }
        guard origin != before else { return false }
        clamp()
        return origin != before
    }

    /// 왼쪽 끝에서 더 밀 수 있는 곳(논리 단위, 음수). 묶음 손잡이는 묶음 **왼쪽 바깥**에 있어서 캔버스 왼끝(x 0)에 놓인 묶음은 그만큼 더 밀어야 닿는다
    /// (맥은 판 여백으로 푼다 — 0.3.70 `zoom` 의 여백 20). 놓을 자리는 캔버스 안으로 잘리니 x 0 묶음은 흔하다. 기본 보기(폭 맞춤)도 이만큼은 민다.
    /// 전체 맞춤은 칸 폭이 남아 캔버스 양옆에 이미 그 자리가 있다.
    private var minOriginX: CGFloat { -GamesRummyGestureRules.handleTouchWidth / scale }

    private mutating func clamp() {
        let visible = CGSize(width: viewport.width / scale, height: viewport.height / scale)
        // 폭 맞춤은 부동소수 오차로 양쪽을 오간다 — 0.5 단위 넘게 남을 때만 '칸이 더 넓다'로 친다.
        origin.x = visible.width > Self.canvas.width + 0.5 ? 0 : min(max(origin.x, minOriginX), max(0, Self.canvas.width - visible.width))
        origin.y = visible.height >= Self.canvas.height ? 0 : min(max(origin.y, 0), Self.canvas.height - visible.height)
    }

    // MARK: 화면 밖 묶음

    /// 왼·오른쪽 화면 밖 묶음 수(남이 새로 낸 묶음을 못 보고 지나가지 않게 하는 배지의 값 — 기본 보기에서는 위·아래가 주로 쓰인다). 일부라도 보이면 세지 않는다.
    package func offscreenCounts(_ frames: [RummyRect]) -> (left: Int, right: Int) {
        let visible = visibleLogical
        var left = 0, right = 0
        for frame in frames {
            if CGFloat(frame.maxX) <= visible.minX {
                left += 1
            } else if CGFloat(frame.x) >= visible.maxX {
                right += 1
            }
        }
        return (left, right)
    }

    /// 위·아래로 가려진 묶음 수(기본 보기는 칸이 캔버스보다 낮아 늘 쓰인다). 가로로 이미 화면 밖인 묶음은 좌우 배지가 센다 — 두 번 세지 않는다.
    package func offscreenVerticalCounts(_ frames: [RummyRect]) -> (up: Int, down: Int) {
        let visible = visibleLogical
        var up = 0, down = 0
        for frame in frames where CGFloat(frame.maxX) > visible.minX && CGFloat(frame.x) < visible.maxX {
            if CGFloat(frame.maxY) <= visible.minY {
                up += 1
            } else if CGFloat(frame.y) >= visible.maxY {
                down += 1
            }
        }
        return (up, down)
    }

    package enum Side: Sendable { case left, right, up, down }

    /// 배지를 눌렀다 — 그 쪽에서 가장 가까운 화면 밖 묶음이 여백을 두고 보이도록 민다. 밀 것이 없으면 그대로.
    package mutating func reveal(_ side: Side, frames: [RummyRect]) {
        let visible = visibleLogical
        switch side {
        case .left:
            guard let nearest = frames.filter({ CGFloat($0.maxX) <= visible.minX }).max(by: { $0.maxX < $1.maxX }) else { return }
            origin.x = CGFloat(nearest.x) - Self.revealMargin
        case .right:
            guard let nearest = frames.filter({ CGFloat($0.x) >= visible.maxX }).min(by: { $0.x < $1.x }) else { return }
            origin.x = CGFloat(nearest.maxX) + Self.revealMargin - visible.width
        case .up:
            guard let nearest = frames.filter({ CGFloat($0.maxY) <= visible.minY }).max(by: { $0.maxY < $1.maxY }) else { return }
            origin.y = CGFloat(nearest.y) - Self.revealMargin
        case .down:
            guard let nearest = frames.filter({ CGFloat($0.y) >= visible.maxY }).min(by: { $0.y < $1.y }) else { return }
            origin.y = CGFloat(nearest.maxY) + Self.revealMargin - visible.height
        }
        clamp()
    }
}

/// 받침대 기하(받침대 칸 왼쪽 위 원점) — **한 줄 16장**(맥과 같은 반 칸 32) · 반 칸 격자. 그리는 자리(`frame`)와 놓는 자리(`slot`)가 한 산식이다.
/// 칸 높이는 줄 수로 안 변한다. 3줄부터는 맥 `tileScale` 산식(2/줄)으로 타일이 줄어 담긴다. 그림 기준선을 쓰는 맥 `RummyRackGeometry` 와 달리 폭이 다른 기기에 맞춰 값으로 잰다.
package struct GamesRummyRackGeometry: Equatable, Sendable, RummyRackDropGeometry {
    /// 받침대 한 줄의 반 칸 수(맥 값 그대로 — 코어 `RummyRackLayout` 하나).
    package static let halfColumns = RummyRackLayout.halfColumnsPerRow
    /// 타일 높이 / 폭. iPhone 15 가운데 칸(548) → 약 33.8×47pt.
    package static let tileAspect: CGFloat = 1.39
    /// 받침대 좌우 최소 여백.
    package static let minSideInset: CGFloat = 4
    /// 위아래 여백 — 아랫줄 선반이 테두리 빛에 묻히지 않을 만큼.
    package static let verticalPadding: CGFloat = 6
    package static let rowGap: CGFloat = 4
    /// 줄 사이 틈의 하한(타일이 위아래로 닿지 않게).
    package static let minRowGap: CGFloat = 2

    package let size: CGSize
    package let rowCount: Int

    package init(size: CGSize, rowCount: Int = RummyRackLayout.baseRows) {
        self.size = size
        self.rowCount = max(RummyRackLayout.baseRows, rowCount)
    }

    private static var perRow: CGFloat { CGFloat(halfColumns / RummyRackLayout.tileSpan) }
    private var perRow: CGFloat { Self.perRow }

    private static func baseTileWidth(forWidth width: CGFloat) -> CGFloat { max(1, width - minSideInset * 2) / perRow }

    /// 칸 높이 — 2줄이 꼭 들어가는 값. 넓은 기기라도 `maxHeight` 를 안 넘는다(그때는 타일이 그만큼 작다).
    package static func height(forWidth width: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let rows = CGFloat(RummyRackLayout.baseRows)
        return min(maxHeight, baseTileWidth(forWidth: width) * tileAspect * rows + rowGap * (rows - 1) + verticalPadding * 2)
    }

    /// 줄이 넘치면 타일을 줄인다(받침대 안 스크롤은 쓰지 않는다 — 맥 `tileScale` 과 같은 산식).
    package var tileScale: CGFloat { rowCount <= RummyRackLayout.baseRows ? 1 : CGFloat(RummyRackLayout.baseRows) / CGFloat(rowCount) }

    /// 칸 안에 담긴다: 폭으로 한 번 · 높이로 한 번 자른다.
    package var tileSize: CGSize {
        let rows = CGFloat(rowCount)
        let heightRoom = max(1, (size.height - Self.verticalPadding * 2 - Self.minRowGap * (rows - 1)) / rows)
        let width = min(Self.baseTileWidth(forWidth: size.width) * tileScale, heightRoom / Self.tileAspect)
        return CGSize(width: width, height: width * Self.tileAspect)
    }

    package var dropTileWidth: CGFloat { tileSize.width }
    package var sideInset: CGFloat { max(Self.minSideInset, (size.width - tileSize.width * perRow) / 2) }
    package var halfPitch: CGFloat { tileSize.width / CGFloat(RummyRackLayout.tileSpan) }

    /// 줄 위쪽. 줄 사이 틈은 남는 높이에서 나오되 `rowGap` 을 안 넘고, 묶음째 칸 세로 가운데에 선다(줄이 넘쳐 타일이 줄어도 틈만 벌어지지 않게).
    package func rowTop(_ row: Int) -> CGFloat {
        let rows = CGFloat(rowCount)
        let gap = rowCount <= 1 ? 0 : min(Self.rowGap, max(0, (size.height - Self.verticalPadding * 2 - tileSize.height * rows) / (rows - 1)))
        let top = max(Self.verticalPadding, (size.height - tileSize.height * rows - gap * (rows - 1)) / 2)
        return top + CGFloat(row) * (tileSize.height + gap)
    }

    package func rowCenter(_ row: Int) -> CGFloat { rowTop(row) + tileSize.height / 2 }

    package func frame(_ slot: RummyRackSlot) -> CGRect {
        CGRect(x: sideInset + CGFloat(slot.halfCol) * halfPitch, y: rowTop(slot.row),
               width: tileSize.width, height: tileSize.height)
    }

    /// 놓을 자리: 맨 왼쪽 타일의 왼쪽 끝 x · 손의 y → 가장 가까운 반 칸과 줄(받침대 안으로 자른다).
    package func slot(tileLeft x: CGFloat, centerY y: CGFloat, tiles: Int) -> RummyRackSlot {
        let maxHalf = max(0, Self.halfColumns - RummyRackLayout.tileSpan * max(1, tiles))
        let half = Int(((x - sideInset) / halfPitch).rounded())
        let row = (0..<rowCount).min { abs(rowCenter($0) - y) < abs(rowCenter($1) - y) } ?? 0
        return RummyRackSlot(row: row, halfCol: min(max(half, 0), maxHalf))
    }

    /// 받침대 타일의 뷰 키 — 면 글자 + 같은 면 순번(id 순). 차례가 바뀌어 편집기가 새 id 를 붙여도 같은 타일이 같은 뷰로 남는다(맥 `motionKeys` 와 같다).
    package static func motionKeys(_ tiles: [RummyTile]) -> [Int: String] {
        var seen: [String: Int] = [:]
        var keys: [Int: String] = [:]
        for tile in tiles.sorted(by: { $0.id < $1.id }) {
            let n = seen[tile.face.text, default: 0]
            seen[tile.face.text] = n + 1
            keys[tile.id] = "\(tile.face.text)#\(n)"
        }
        return keys
    }
}

/// 손이 처음 닿은 자리의 분류. 화면 전체에 제스처 **하나**를 두고 이 판정기로 가른다(타일마다 제스처를 달면 판 타일 100장 이상에서 무겁고 판 밀기와 충돌한다).
package enum GamesRummyHit: Equatable, Sendable {
    case rackTile(Int)
    case boardTile(Int)
    /// 묶음 왼쪽 손잡이(묶음 번호).
    case meldHandle(Int)
    /// 빈 펠트 — 판 밀기.
    case felt
    /// 그 밖 — 무시.
    case none
}

/// 끌기 시간·거리·들어 올림 값(설계서 §4 입력). 놓을 자리 계산의 기준점도 그린 자리와 같다.
package enum GamesRummyGestureRules {
    /// 이만큼 움직이면 **한 장** 끌기.
    package static let dragThreshold: CGFloat = 8
    /// 그 안에서 이만큼 버티면 **묶음째**.
    package static let liftDelay: TimeInterval = 0.5
    /// 집힌 타일은 손 위로 이만큼 — 손가락에 가리지 않게.
    package static let fingerLift: CGFloat = 48
    /// 손이 받침대 아래 끝에 닿았을 때의 들어 올림(`GamesRummyMatchLayout.fingerLift` — 받침대가 화면 맨 아래라 아랫줄에 놓을 손 자리를 벌어 준다).
    package static let fingerLiftAtBottom: CGFloat = 18
    package static let liftScale: CGFloat = 1.25
    /// 묶음 손잡이 터치 폭(타일 왼쪽 바깥).
    package static let handleTouchWidth: CGFloat = 28

    /// 손의 자리 → 그린 자리 · 놓을 자리 계산의 기준점.
    package static func liftedPoint(finger: CGPoint, lift: CGFloat = fingerLift) -> CGPoint { CGPoint(x: finger.x, y: finger.y - lift) }

    /// 그려진 손잡이 막대(묶음 사각형 `shown` 왼쪽 바깥). 그리는 자리(`GamesRummyBoardLayer`)와 재는 자리(`handleGrabRect`)가 이 값 하나를 쓴다.
    package static func handleBar(shown: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: shown.minX - max(9, 13 * scale), y: shown.midY - shown.height * 0.43,
               width: max(8, 10 * scale), height: shown.height * 0.86)
    }

    /// 타일보다 **먼저** 잡히는 손잡이 자리: 그려진 막대 둘레. 붙은 묶음은 틈이 좁아(기본 보기 약 12pt · 전체 보기 약 6pt, 스냅이면 0) 타일을 먼저 재면 막대를 눌러도 앞 묶음 끝 타일이 뽑힌다.
    /// 앞 타일을 다 먹지 않게 둘레는 타일 폭의 ¼(최대 8pt)이고, 자기 첫 타일 쪽으로는 안 넘어간다.
    package static func handleGrabRect(shown: CGRect, scale: CGFloat) -> CGRect {
        let bar = handleBar(shown: shown, scale: scale)
        let margin = min(8, CGFloat(RummyTableLayout.tileWidth) * scale * 0.25)
        let left = bar.minX - margin
        return CGRect(x: left, y: shown.minY, width: max(0, min(bar.maxX + margin, shown.minX) - left), height: shown.height)
    }
}

package enum GamesRummyHitTester {
    /// `point` = 판 화면 좌표. `meldTileIDs` = 묶음별 타일 id(화면 순, 편집기). `editable` = 내 차례라 판 타일을 만질 수 있다 —
    /// 아니면 판은 전부 펠트다(밀어 보기만). 받침대 빈칸은 `.none`(받침대를 밀 일이 없다).
    package static func classify(point: CGPoint, layout: GamesRummyMatchLayout, rack: GamesRummyRackGeometry,
                                 rackLayout: RummyRackLayout, canvas: RummyCanvasTransform, table: RummyTableLayout,
                                 meldTileIDs: [[Int]], editable: Bool) -> GamesRummyHit {
        if layout.rack.contains(point) {
            let local = CGPoint(x: point.x - layout.rack.minX, y: point.y - layout.rack.minY)
            for (id, slot) in rackLayout.slots where rack.frame(slot).contains(local) { return .rackTile(id) }
            return .none
        }
        guard layout.table.contains(point) else { return .none }
        guard editable else { return .felt }
        let local = CGPoint(x: point.x - layout.table.minX, y: point.y - layout.table.minY)
        // ① 그려진 손잡이 막대 둘레 — 타일보다 먼저(붙은 묶음에서도 막대를 누르면 막대가 잡힌다).
        for (set, frame) in table.frames.enumerated() {
            if GamesRummyGestureRules.handleGrabRect(shown: canvas.rect(frame), scale: canvas.scale).contains(local) { return .meldHandle(set) }
        }
        // ② 타일 — 나머지 터치 폭(③)보다 먼저다(옆 묶음의 손잡이 터치 폭이 앞 묶음 타일 위로 겹칠 수 있다).
        for set in table.frames.indices {
            for tile in 0..<table.counts[set] {
                guard let frame = table.tileFrame(set: set, tile: tile),
                      meldTileIDs.indices.contains(set), meldTileIDs[set].indices.contains(tile) else { continue }
                if canvas.rect(frame).contains(local) { return .boardTile(meldTileIDs[set][tile]) }
            }
        }
        // ③ 막대 왼쪽 나머지 터치 폭(묶음과 세로로 겹칠 때만) — 왼쪽이 빈 펠트인 묶음은 여기로 잡기 쉽다.
        for (set, frame) in table.frames.enumerated() {
            let shown = canvas.rect(frame)
            let handle = CGRect(x: shown.minX - GamesRummyGestureRules.handleTouchWidth, y: shown.minY,
                                width: GamesRummyGestureRules.handleTouchWidth, height: shown.height)
            if handle.contains(local) { return .meldHandle(set) }
        }
        return .felt
    }
}
