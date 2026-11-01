import CheckCore
import CoreGraphics
import Foundation

// 폰 아잉 큐브 판 화면의 **순수 값**(설계서 §4). `#if os(iOS)` 밖이다 — 폰 뷰는 맥 스위트가 못 보므로 칸 자리 · 보기 · 받침대 · 누르기 판정을 값으로 재는 자리가 여기다.
// 그리는 자리·누르는 자리·놓는 자리가 전부 이 값에서 나온다(맥 `RummyMatchLayout`·`RummyRackGeometry` 와 같은 원칙 · 배치는 세로용으로 다시 짰다).
// 좌표는 전부 판 화면 좌표(세이프 영역 안 왼쪽 위 원점 · `coordinateSpace: .named`)다.

/// 판 화면 칸 자리 — 위에서 아래로 머리 줄 · 상대 줄 · 판(남는 높이 전부) · 상태 줄 · 받침대 · 동작 줄.
package struct GamesRummyMatchLayout: Equatable, Sendable {
    package static let headerHeight: CGFloat = 44
    package static let opponentsHeight: CGFloat = 56
    package static let statusHeight: CGFloat = 20
    /// 받침대 2줄 · 3줄(넘치면 판이 줄어든다). 4줄부터는 타일이 줄어들고 높이는 3줄 그대로다.
    package static let rackTwoRowsHeight: CGFloat = 118
    package static let rackThreeRowsHeight: CGFloat = 165
    /// 동작 줄 기본 높이(큰 글자에서는 `actionHeight` 로 키운다 — 잘리지 않게).
    package static let actionsHeight: CGFloat = 52

    package let size: CGSize
    package let rackRows: Int
    package let actionHeight: CGFloat

    package init(size: CGSize, rackRows: Int = RummyRackLayout.baseRows, actionHeight: CGFloat = GamesRummyMatchLayout.actionsHeight) {
        self.size = size
        self.rackRows = max(RummyRackLayout.baseRows, rackRows)
        self.actionHeight = max(Self.actionsHeight, actionHeight)
    }

    package var rackHeight: CGFloat { rackRows <= 2 ? Self.rackTwoRowsHeight : Self.rackThreeRowsHeight }

    // MARK: 동작 줄 — 큰 글자

    /// 글자 배율이 이 값을 넘으면 동작 줄을 두 줄로 나눈다([완료] 한 줄 · 나머지 셋 한 줄). 넘지 않는 동안은 글자가 칸에 맞춰 줄어든다.
    package static let twoRowActionsAboveTextScale: CGFloat = 1.3
    /// 버튼 위아래 · 줄 사이 틈.
    package static let actionGap: CGFloat = 6

    package static func actionRowCount(textScale: CGFloat) -> Int { textScale > twoRowActionsAboveTextScale ? 2 : 1 }

    /// 버튼 한 줄 높이(44pt 아래로 안 내려간다 · 글자를 따라 커지되 판을 다 먹지 않게 64 에서 멈춘다).
    package static func actionButtonHeight(textScale: CGFloat) -> CGFloat {
        guard actionRowCount(textScale: textScale) == 2 else { return actionsHeight - actionGap - 2 }
        return min(64, max(44, 40 * textScale))
    }

    /// 글자 배율 → 동작 줄 높이(`init(actionHeight:)` 에 그대로 넘긴다).
    package static func actionHeight(textScale: CGFloat) -> CGFloat {
        guard actionRowCount(textScale: textScale) == 2 else { return actionsHeight }
        return actionButtonHeight(textScale: textScale) * 2 + actionGap * 3
    }

    /// 한 줄 동작 줄의 버튼 폭 넷([완료] · [뽑기|넘기기] · [되돌리기] · [777|789]). 합 + 틈 + 양옆 여백 = 칸 폭이라 어느 폭에서도 안 겹친다.
    package static func actionWidths(total: CGFloat) -> (submit: CGFloat, draw: CGFloat, undo: CGFloat, sort: CGFloat) {
        let room = max(0, total - actionGap * 5)
        return (room * 0.36, room * 0.19, room * 0.21, room * 0.24)
    }

    package var header: CGRect { CGRect(x: 0, y: 0, width: size.width, height: Self.headerHeight) }
    package var opponents: CGRect { CGRect(x: 0, y: header.maxY, width: size.width, height: Self.opponentsHeight) }
    package var actions: CGRect { CGRect(x: 0, y: size.height - actionHeight, width: size.width, height: actionHeight) }
    package var rack: CGRect { CGRect(x: 0, y: actions.minY - rackHeight, width: size.width, height: rackHeight) }
    package var status: CGRect { CGRect(x: 0, y: rack.minY - Self.statusHeight, width: size.width, height: Self.statusHeight) }
    /// 판 — 남는 높이 전부(작은 기기에서 음수가 되지 않는다).
    package var table: CGRect {
        CGRect(x: 0, y: opponents.maxY, width: size.width, height: max(0, status.minY - opponents.maxY))
    }
}

/// 판 보기(배율 · 오프셋). **배율은 판 변화로 저절로 바뀌지 않는다**(맥 교훈 — 놓을 때마다 판이 움직이면 안 된다). 사람이 움직일 때만 바뀐다.
///
/// 기본 보기는 **캔버스 높이를 칸에 맞춘 배율**이다(칸 높이 ≈ 470 → 배율 ≈ 0.73 → 타일 ≈ 29×41pt, 가로 약 530 논리 단위가 보인다). 가로 1000 은 민다.
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
    /// 기본 보기의 타일 폭 하한(pt). 칸이 낮아도(큰 글자 · 작은 기기 · 받침대 3줄) 기본 보기는 맞춤보다 커서 [전체 보기] 토글이 늘 무언가를 바꾼다. 그만큼 세로는 민다.
    package static let minDefaultTileWidth: CGFloat = 24

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

    /// 기본 보기 배율(높이를 맞춘다 · 타일 폭 하한 아래로 안 내려간다).
    package static func defaultScale(_ viewport: CGSize) -> CGFloat {
        let floor = minDefaultTileWidth / CGFloat(RummyTableLayout.tileWidth)
        return min(maxScale, max(fitScale(viewport), viewport.height / canvas.height, floor))
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

    /// 칸 크기가 바뀌었다(받침대 3줄 · 큰 글자). 기본·맞춤 보기였으면 새 칸의 기본·맞춤으로, 사람이 고른 배율이면 그대로(범위 안으로만).
    package mutating func resize(to viewport: CGSize) {
        guard viewport != self.viewport else { return }
        let wasFull = isFullView, wasDefault = abs(scale - defaultScale) < 0.0005
        self.viewport = viewport
        if wasFull {
            scale = fitScale
        } else if wasDefault {
            scale = defaultScale
        } else {
            scale = min(Self.maxScale, max(fitScale, scale))
        }
        clamp()
    }

    /// 끌기 중 가장자리 자동 밀기 한 걸음. `pointer` = 칸 좌표. 가로 · 세로를 따로 민다(세로는 캔버스가 칸보다 클 때만 움직인다 — 확대한 보기 · 낮은 칸). 움직였으면 true.
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
    /// (맥은 판 여백으로 푼다 — 0.3.70 `zoom` 의 여백 20). 놓을 자리는 캔버스 안으로 잘리니 x 0 묶음은 흔하다. 전체 맞춤은 밀 곳이 없다 — 그 보기에선 꾹 눌러 묶음째 옮긴다.
    private var minOriginX: CGFloat { -GamesRummyGestureRules.handleTouchWidth / scale }

    private mutating func clamp() {
        let visible = CGSize(width: viewport.width / scale, height: viewport.height / scale)
        origin.x = visible.width >= Self.canvas.width ? 0 : min(max(origin.x, minOriginX), Self.canvas.width - visible.width)
        origin.y = visible.height >= Self.canvas.height ? 0 : min(max(origin.y, 0), Self.canvas.height - visible.height)
    }

    // MARK: 화면 밖 묶음

    /// 왼·오른쪽 화면 밖 묶음 수(남이 새로 낸 묶음을 못 보고 지나가지 않게 하는 배지의 값). 일부라도 보이면 세지 않는다.
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

    /// 위·아래로 가려진 묶음 수(확대한 보기 · 낮은 칸). 가로로 이미 화면 밖인 묶음은 좌우 배지가 센다 — 두 번 세지 않는다.
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

/// 판 위 조작의 세로 자리(판 칸 아래에서 잰 값). 뷰 밖이라 값으로 잰다.
package enum GamesRummyTableControlsLayout {
    /// 배지 한 칸 높이.
    package static let badgeHeight: CGFloat = 44

    /// [전체 보기] 토글의 아래 여백 — 오른쪽 배지 자리 바로 위. 배지가 있든 없든 같은 값이라 토글이 안 움직인다.
    package static func zoomBottom(badgeLift: CGFloat) -> CGFloat { badgeLift + badgeHeight }
}

/// 받침대 기하(받침대 칸 왼쪽 위 원점) — 한 줄 11장 · 반 칸 격자. 그리는 자리(`frame`)와 놓는 자리(`slot`)가 한 산식이다.
/// 그림 기준선을 쓰는 맥 `RummyRackGeometry` 와 달리 폭이 다른 기기에 맞춰 값으로 잰다.
package struct GamesRummyRackGeometry: Equatable, Sendable, RummyRackDropGeometry {
    /// 폰 받침대 한 줄의 반 칸 수(11장).
    package static let halfColumns = 22
    /// 타일 기준 크기(pt) — 폭이 모자란 기기는 비율대로 줄인다.
    package static let baseTile = CGSize(width: 34, height: 47)
    /// 받침대 좌우 최소 여백.
    package static let minSideInset: CGFloat = 8
    package static let verticalPadding: CGFloat = 8
    package static let rowGap: CGFloat = 8
    /// 줄 사이 틈의 하한(타일이 위아래로 닿지 않게).
    package static let minRowGap: CGFloat = 2

    package let size: CGSize
    package let rowCount: Int

    package init(size: CGSize, rowCount: Int = RummyRackLayout.baseRows) {
        self.size = size
        self.rowCount = max(RummyRackLayout.baseRows, rowCount)
    }

    private var perRow: CGFloat { CGFloat(Self.halfColumns / RummyRackLayout.tileSpan) }

    /// 줄이 3개를 넘으면 타일을 줄인다(받침대 안 스크롤은 쓰지 않는다 — 맥 `tileScale` 과 같은 산식).
    package var tileScale: CGFloat { rowCount <= 3 ? 1 : 3 / CGFloat(rowCount) }

    /// 칸 안에 담긴다: 폭으로 한 번 · 높이로 한 번 자른다(끄는 동안 미리보기가 새 줄을 열면 칸은 그대로라 타일이 줄어 담긴다 — 맥과 같은 선택).
    package var tileSize: CGSize {
        let room = max(1, size.width - Self.minSideInset * 2) / perRow
        let rows = CGFloat(rowCount)
        let heightRoom = max(1, (size.height - Self.verticalPadding * 2 - Self.minRowGap * (rows - 1)) / rows)
        let aspect = Self.baseTile.height / Self.baseTile.width
        let width = min(Self.baseTile.width * tileScale, room, heightRoom / aspect)
        return CGSize(width: width, height: width * aspect)
    }

    package var dropTileWidth: CGFloat { tileSize.width }
    package var sideInset: CGFloat { max(Self.minSideInset, (size.width - tileSize.width * perRow) / 2) }
    package var halfPitch: CGFloat { tileSize.width / CGFloat(RummyRackLayout.tileSpan) }

    /// 줄 위쪽. 줄 사이 틈은 남는 높이에서 나오되 `rowGap` 을 안 넘고, 묶음째 칸 세로 가운데에 선다(좁은 기기는 타일이 작아 틈만 벌어졌다 — 320 실화면).
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
    package static let liftScale: CGFloat = 1.25
    /// 묶음 손잡이 터치 폭(타일 왼쪽 바깥).
    package static let handleTouchWidth: CGFloat = 28

    /// 손의 자리 → 그린 자리 · 놓을 자리 계산의 기준점.
    package static func liftedPoint(finger: CGPoint) -> CGPoint { CGPoint(x: finger.x, y: finger.y - fingerLift) }

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
