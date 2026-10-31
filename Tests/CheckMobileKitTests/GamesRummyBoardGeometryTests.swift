@testable import CheckCore
import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 아잉 큐브 판 화면의 순수 값(`GamesRummyBoardGeometry.swift`). 폰 뷰는 맥 스위트가 못 보므로 칸 · 보기 · 받침대 · 누르기를 값으로 잰다.
@Suite struct GamesRummyBoardGeometryTests {
    /// 세이프 영역 안 크기: SE 1세대급 · 기준 393 · 큰 폰.
    static let screens = [CGSize(width: 320, height: 548), CGSize(width: 393, height: 759), CGSize(width: 430, height: 830)]

    // MARK: - 칸

    @Test("칸: 세 폭 · 2/3/4줄 받침대 · 큰 글자에서 칸이 겹치지 않고 화면을 벗어나지 않는다")
    func cellsNeverOverlap() {
        for size in Self.screens {
            for rows in [2, 3, 4, 7] {
                for action in [GamesRummyMatchLayout.actionsHeight, 84] {
                    let layout = GamesRummyMatchLayout(size: size, rackRows: rows, actionHeight: action)
                    let cells = [layout.header, layout.opponents, layout.table, layout.status, layout.rack, layout.actions]
                    let screen = CGRect(origin: .zero, size: size)
                    for (index, cell) in cells.enumerated() {
                        #expect(screen.contains(cell), "\(size) \(rows)줄: \(index)번 칸이 화면 밖 \(cell)")
                        for other in cells[(index + 1)...] {
                            #expect(cell.intersection(other).height <= 0.5, "\(size) \(rows)줄: 칸이 겹친다 \(cell) \(other)")
                        }
                    }
                    #expect(layout.table.height > 100, "\(size) \(rows)줄: 판이 너무 작다 \(layout.table.height)")
                    #expect(layout.actions.height >= action, "큰 글자에서 동작 줄이 잘린다")
                }
            }
        }
    }

    @Test("칸: 받침대는 2줄 118 · 3줄부터 165(판이 그만큼 줄어든다) · 기준 화면의 판 높이는 설계값 약 470")
    func rackGrowsAndTableShrinks() {
        let size = CGSize(width: 393, height: 759)
        let two = GamesRummyMatchLayout(size: size, rackRows: 2)
        let three = GamesRummyMatchLayout(size: size, rackRows: 3)
        let five = GamesRummyMatchLayout(size: size, rackRows: 5)
        #expect(two.rack.height == 118 && three.rack.height == 165 && five.rack.height == 165)
        #expect(abs(two.table.height - 469) < 1)
        #expect(two.table.height - three.table.height == 47)
    }

    // MARK: - 보기

    @Test("보기: 기본은 높이 맞춤(기준 약 0.73 · 타일 약 29×41 · 가로 약 530 단위) · 하한은 전체 맞춤 · 상한은 타일 폭 40")
    func defaultViewMatchesTheDesign() {
        let viewport = CGSize(width: 393, height: 469)
        let view = GamesRummyViewport(viewport: viewport)
        #expect(abs(view.scale - 469.0 / 640.0) < 0.001)
        #expect(abs(view.tileSize.width - 29.3) < 0.2)
        #expect(abs(view.tileSize.height - 41) < 0.3)
        #expect(abs(view.visibleLogical.width - 536) < 2)
        #expect(abs(GamesRummyViewport.fitScale(viewport) - 0.393) < 0.001)
        #expect(GamesRummyViewport.maxScale == 1)
        #expect(!view.isFullView)
    }

    @Test("보기: 밀기는 양끝에서 멈춘다(왼쪽은 손잡이 터치 폭 28pt 만큼 더 · 오른쪽은 캔버스 끝 · 손과 같은 쪽으로 움직인다)")
    func panClamps() {
        var view = GamesRummyViewport(viewport: CGSize(width: 393, height: 469))
        #expect(view.origin.x == 0, "처음 보기는 캔버스 왼끝이다")
        view.pan(by: CGSize(width: 100, height: 0))
        let home = -28 / view.scale
        #expect(abs(view.origin.x - home) < 0.001, "왼쪽 끝을 넘었다: \(view.origin.x)")
        view.pan(by: CGSize(width: -100, height: 0))
        #expect(abs(view.origin.x - (home + 100 / view.scale)) < 0.001, "손을 왼쪽으로 끌면 판은 오른쪽을 보여 준다")
        view.pan(by: CGSize(width: -100_000, height: 0))
        #expect(abs(view.visibleLogical.maxX - 1000) < 0.001, "오른쪽 끝을 넘었다")
        // 높이가 다 보이는 기본 보기는 세로로 안 민다.
        view.pan(by: CGSize(width: 0, height: -50))
        #expect(view.origin.y == 0)
    }

    @Test("보기: 핀치는 손 아래 논리 점을 그 자리에 두고, 범위 밖 배율은 자른다")
    func zoomKeepsTheAnchor() {
        var view = GamesRummyViewport(viewport: CGSize(width: 393, height: 469))
        view.pan(by: CGSize(width: -200, height: 0))
        let anchor = CGPoint(x: 200, y: 200)
        let before = view.transform.toLogical(anchor)
        view.zoom(to: 0.95, anchor: anchor)
        #expect(view.scale == 0.95)
        let after = view.transform.toLogical(anchor)
        #expect(abs(before.x - after.x) < 0.01 && abs(before.y - after.y) < 0.01, "\(before) → \(after)")
        view.zoom(to: 5, anchor: anchor)
        #expect(view.scale == 1)
        view.zoom(to: 0.01, anchor: anchor)
        #expect(view.isFullView)
        #expect(view.origin == .zero, "전체 맞춤에서 오프셋이 남았다")
    }

    @Test("보기: [전체 보기] 토글은 맞춤 ↔ 기본을 오간다")
    func toggleSwitches() {
        var view = GamesRummyViewport(viewport: CGSize(width: 393, height: 469))
        let original = view.scale
        view.toggleFullView()
        #expect(view.isFullView)
        // 전체 맞춤이면 캔버스가 세로 가운데에 선다.
        #expect(view.transform.screenOrigin.y > 0 && view.transform.screenOrigin.x == 0)
        view.toggleFullView()
        #expect(view.scale == original)
    }

    @Test("보기: 칸이 줄면 기본 보기는 새 기본으로, 사람이 고른 배율은 그대로다")
    func resizeKeepsChoice() {
        var view = GamesRummyViewport(viewport: CGSize(width: 393, height: 469))
        view.resize(to: CGSize(width: 393, height: 422))
        #expect(abs(view.scale - 422.0 / 640.0) < 0.001)
        view.zoom(to: 0.9, anchor: .zero)
        view.resize(to: CGSize(width: 393, height: 469))
        #expect(view.scale == 0.9, "사람이 고른 배율이 칸 변화로 바뀌었다")
    }

    @Test("보기: 가장자리 28pt 안에서만 초당 400 단위로 밀고, 끝에 닿으면 멈춘다")
    func edgePan() {
        var view = GamesRummyViewport(viewport: CGSize(width: 393, height: 469))
        var moved = view.edgePan(pointerX: 200, deltaTime: 0.1)
        #expect(!moved, "가운데에서 밀렸다")
        view.pan(by: CGSize(width: 10_000, height: 0))
        let home = view.origin.x
        moved = view.edgePan(pointerX: 10, deltaTime: 0.1)
        #expect(!moved, "왼쪽 끝인데 움직였다고 한다")
        #expect(view.origin.x == home)
        moved = view.edgePan(pointerX: 380, deltaTime: 0.1)
        #expect(moved)
        #expect(abs(view.origin.x - (home + 40)) < 0.001)
        moved = view.edgePan(pointerX: 5, deltaTime: 0.05)
        #expect(moved)
        #expect(abs(view.origin.x - (home + 20)) < 0.001)
        // 경계값: 정확히 28 은 가장자리가 아니다.
        moved = view.edgePan(pointerX: 28, deltaTime: 0.1)
        #expect(!moved)
        moved = view.edgePan(pointerX: 393 - 28, deltaTime: 0.1)
        #expect(!moved)
    }

    @Test("보기: 화면 밖 묶음을 양쪽으로 세고(일부 보이면 안 센다) 배지를 누르면 가장 가까운 것이 보인다")
    func offscreenBadges() {
        var view = GamesRummyViewport(viewport: CGSize(width: 393, height: 469))
        let frames = [
            RummyRect(x: 10, y: 10, width: 120, height: 56),
            RummyRect(x: 500, y: 10, width: 120, height: 56),   // 경계에 걸침 — 일부 보인다.
            RummyRect(x: 620, y: 100, width: 120, height: 56),
            RummyRect(x: 860, y: 100, width: 120, height: 56),
        ]
        #expect(view.offscreenCounts(frames) == (left: 0, right: 2))
        view.reveal(.right, frames: frames)
        #expect(view.visibleLogical.contains(CGRect(x: 620, y: 100, width: 120, height: 56)), "눌렀는데 묶음이 안 보인다")
        #expect(abs(view.visibleLogical.maxX - (740 + GamesRummyViewport.revealMargin)) < 0.001)
        let moved = view.offscreenCounts(frames)
        #expect(moved.right == 1)
        #expect(moved.left == 1, "밀고 나면 왼쪽 첫 묶음이 왼쪽 화면 밖이다")
        let before = view.origin
        view.reveal(.right, frames: [])
        #expect(view.origin == before, "밀 것이 없는데 움직였다")
        view.reveal(.left, frames: frames)
        #expect(view.origin.x == 10 - GamesRummyViewport.revealMargin, "왼끝 묶음도 여백을 두고 보여야 손잡이가 닿는다")
        // 전체 맞춤이면 화면 밖이 없다.
        view.toggleFullView()
        #expect(view.offscreenCounts(frames) == (left: 0, right: 0))
    }

    // MARK: - 받침대

    @Test("받침대: frame ↔ slot 왕복(세 폭 · 2·3·5줄 · 반 칸 전부) · 한 줄 11장이 칸 안에 든다")
    func rackRoundTrip() {
        for size in Self.screens {
            for rows in [2, 3, 5] {
                let rect = GamesRummyMatchLayout(size: size, rackRows: rows).rack
                let rack = GamesRummyRackGeometry(size: rect.size, rowCount: rows)
                for row in 0..<rows {
                    for half in 0...(GamesRummyRackGeometry.halfColumns - RummyRackLayout.tileSpan) {
                        let slot = RummyRackSlot(row: row, halfCol: half)
                        let frame = rack.frame(slot)
                        #expect(CGRect(origin: .zero, size: rect.size).insetBy(dx: -0.5, dy: -0.5).contains(frame),
                                "\(size) \(rows)줄 \(slot): 칸 밖 \(frame)")
                        #expect(rack.slot(tileLeft: frame.minX, centerY: frame.midY, tiles: 1) == slot, "\(size) \(rows)줄 왕복 실패 \(slot)")
                    }
                }
            }
        }
    }

    @Test("받침대: 기준 폭 타일은 34×47 · 좁은 기기는 비율대로 줄고 · 4줄부터는 맥 tileScale 산식(3/줄)")
    func rackTileSizes() {
        let base = GamesRummyRackGeometry(size: CGSize(width: 393, height: 118))
        #expect(base.tileSize == CGSize(width: 34, height: 47))
        let narrow = GamesRummyRackGeometry(size: CGSize(width: 320, height: 118))
        #expect(abs(narrow.tileSize.width - 304.0 / 11) < 0.001)
        #expect(abs(narrow.tileSize.width / narrow.tileSize.height - 34.0 / 47) < 0.001)
        let five = GamesRummyRackGeometry(size: CGSize(width: 393, height: 165), rowCount: 5)
        #expect(five.tileScale == 0.6)
        #expect(abs(five.tileSize.width - 34 * 0.6) < 0.001)
    }

    @Test("받침대: 놓을 자리는 묶음 길이만큼 폭 안으로 자른다")
    func rackSlotClamps() {
        let rack = GamesRummyRackGeometry(size: CGSize(width: 393, height: 118))
        #expect(rack.slot(tileLeft: 9999, centerY: 10, tiles: 3) == RummyRackSlot(row: 0, halfCol: 16))
        #expect(rack.slot(tileLeft: -50, centerY: 1000, tiles: 1) == RummyRackSlot(row: 1, halfCol: 0))
    }

    // MARK: - 누르기 판정

    private func fixture(editable: Bool = true) -> (layout: GamesRummyMatchLayout, rack: GamesRummyRackGeometry,
                                                    rackLayout: RummyRackLayout, view: GamesRummyViewport,
                                                    table: RummyTableLayout) {
        let layout = GamesRummyMatchLayout(size: CGSize(width: 393, height: 759))
        return (layout, GamesRummyRackGeometry(size: layout.rack.size),
                RummyRackLayout.packed([100, 101, 102], halfColumns: 22),
                GamesRummyViewport(viewport: layout.table.size),
                RummyTableLayout(counts: [3, 3], points: [RummyPoint(x: 100, y: 50), RummyPoint(x: 800, y: 50)]))
    }

    private func classify(_ point: CGPoint, editable: Bool = true) -> GamesRummyHit {
        let f = fixture()
        return GamesRummyHitTester.classify(point: point, layout: f.layout, rack: f.rack, rackLayout: f.rackLayout,
                                            canvas: f.view.transform, table: f.table,
                                            meldTileIDs: [[0, 1, 2], [3, 4, 5]], editable: editable)
    }

    /// 판 논리 좌표 → 판 화면 좌표.
    private func screen(_ logical: CGPoint) -> CGPoint {
        let f = fixture()
        let p = f.view.transform.toScreen(logical)
        return CGPoint(x: p.x + f.layout.table.minX, y: p.y + f.layout.table.minY)
    }

    @Test("누르기: 받침대 타일 · 받침대 빈칸 · 판 타일 · 손잡이 · 빈 펠트 · 그 밖")
    func hitClasses() {
        let f = fixture()
        let tile = f.rack.frame(RummyRackSlot(row: 0, halfCol: 2))
        #expect(classify(CGPoint(x: tile.midX, y: f.layout.rack.minY + tile.midY)) == .rackTile(101))
        #expect(classify(CGPoint(x: 380, y: f.layout.rack.maxY - 2)) == .none, "받침대 빈칸은 무시")
        #expect(classify(screen(CGPoint(x: 100 + 40 + 20, y: 70))) == .boardTile(1))
        // 손잡이: 묶음 왼쪽 바깥 28pt.
        let edge = screen(CGPoint(x: 100, y: 70))
        #expect(classify(CGPoint(x: edge.x - 10, y: edge.y)) == .meldHandle(0))
        #expect(classify(CGPoint(x: edge.x - 27, y: edge.y)) == .meldHandle(0))
        #expect(classify(CGPoint(x: edge.x - 29, y: edge.y)) == .felt, "28pt 밖은 펠트")
        #expect(classify(screen(CGPoint(x: 300, y: 400))) == .felt)
        #expect(classify(CGPoint(x: 100, y: 10)) == .none, "머리 줄")
        #expect(classify(CGPoint(x: 100, y: f.layout.actions.midY)) == .none, "동작 줄")
    }

    @Test("누르기: 캔버스 왼끝(x 0) 묶음의 손잡이는 처음엔 칸 밖이고, 판을 밀면 닿는다")
    func handleOfALeftEdgeMeldIsReachable() {
        let layout = GamesRummyMatchLayout(size: CGSize(width: 393, height: 759))
        let rack = GamesRummyRackGeometry(size: layout.rack.size)
        let table = RummyTableLayout(counts: [3], points: [RummyPoint(x: 0, y: 50)])
        var view = GamesRummyViewport(viewport: layout.table.size)
        func hit(_ point: CGPoint) -> GamesRummyHit {
            GamesRummyHitTester.classify(point: CGPoint(x: point.x + layout.table.minX, y: point.y + layout.table.minY),
                                         layout: layout, rack: rack, rackLayout: RummyRackLayout(halfColumns: 22),
                                         canvas: view.transform, table: table, meldTileIDs: [[0, 1, 2]], editable: true)
        }
        let y = view.transform.toScreen(CGPoint(x: 0, y: 70)).y
        // 기준선: 처음 보기에는 묶음이 칸 왼끝에 붙어 손잡이 자리가 없다.
        #expect(hit(CGPoint(x: 1, y: y)) == .boardTile(0))
        view.pan(by: CGSize(width: 100, height: 0))
        let meldLeft = view.transform.toScreen(CGPoint(x: 0, y: 70)).x
        #expect(abs(meldLeft - 28) < 0.001, "손잡이 폭만큼 안 밀린다: \(meldLeft)")
        #expect(hit(CGPoint(x: 14, y: y)) == .meldHandle(0), "왼끝 묶음의 손잡이가 안 닿는다")
        #expect(hit(CGPoint(x: 30, y: y)) == .boardTile(0))
    }

    @Test("누르기: 내 차례가 아니면 판은 전부 펠트다(밀어 보기만) · 받침대는 그대로 잡힌다")
    func notEditable() {
        let f = fixture()
        #expect(classify(screen(CGPoint(x: 160, y: 70)), editable: false) == .felt)
        let tile = f.rack.frame(RummyRackSlot(row: 0, halfCol: 0))
        #expect(classify(CGPoint(x: tile.midX, y: f.layout.rack.minY + tile.midY), editable: false) == .rackTile(100))
    }

    @Test("들어 올림: 그린 자리와 재는 자리가 같다(손 위 48pt)")
    func liftPoint() {
        #expect(GamesRummyGestureRules.liftedPoint(finger: CGPoint(x: 10, y: 100)) == CGPoint(x: 10, y: 52))
        #expect(GamesRummyGestureRules.liftScale == 1.25 && GamesRummyGestureRules.liftDelay == 0.5
                && GamesRummyGestureRules.dragThreshold == 8)
    }

    // MARK: - 놓을 자리(코어 판정기 + 폰 칸)

    @Test("놓기: 받침대 위 = 자리 · 묶음 위 = 끼울 번호 · 빈 펠트 = 새 묶음 · 내 차례 아니면 받침대만")
    func dropTargets() {
        let f = fixture()
        func target(_ point: CGPoint, myTurn: Bool = true, grab: Int = 0, count: Int = 1) -> RummyDropTarget? {
            RummyDropResolver.target(pointer: point, grabIndex: grab, count: count, rackRect: f.layout.rack,
                                     tableRect: f.layout.table, canvas: f.view.transform, table: f.table,
                                     rack: f.rack, isMyTurn: myTurn)
        }
        let tile = f.rack.frame(RummyRackSlot(row: 1, halfCol: 6))
        #expect(target(CGPoint(x: tile.midX, y: f.layout.rack.minY + tile.midY)) == .rackSlot(RummyRackSlot(row: 1, halfCol: 6)))
        #expect(target(screen(CGPoint(x: 165, y: 70))) == .meld(0, index: 2))
        #expect(target(screen(CGPoint(x: 300, y: 300))) == .newMeldAt(RummyPoint(x: 280, y: 272)))
        #expect(target(screen(CGPoint(x: 300, y: 300)), myTurn: false) == nil)
        #expect(target(CGPoint(x: 10, y: 10)) == nil, "머리 줄엔 못 놓는다")
    }
}

/// 비교를 쓰려고 `offscreenCounts` 튜플을 값으로 맞춘다.
private func == (lhs: (left: Int, right: Int), rhs: (left: Int, right: Int)) -> Bool {
    lhs.left == rhs.left && lhs.right == rhs.right
}
