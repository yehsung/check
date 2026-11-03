@testable import CheckCore
import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 아잉 큐브 판 화면의 순수 값(`GamesRummyBoardGeometry.swift`). 폰 뷰는 맥 스위트가 못 보므로 칸 · 보기 · 받침대 · 누르기를 값으로 잰다.
@Suite struct GamesRummyBoardGeometryTests {
    /// 가로 세이프 영역 안 크기: 시스템 '화면 확대' 둘(iPhone 15 확대의 세이프 값은 어림) · 작은 기기 · iPhone 15 · 852×393 · 큰 기기.
    static let screens = [CGSize(width: 568, height: 320), CGSize(width: 605, height: 303), CGSize(width: 667, height: 354), CGSize(width: 734, height: 372), CGSize(width: 852, height: 393), CGSize(width: 932, height: 430)]
    /// iPhone 15 판 칸.
    static let table = CGSize(width: 548, height: 244)

    // MARK: - 칸

    @Test("칸: 네 크기 · 2/3/7줄 받침대에서 칸이 겹치지 않고 화면을 벗어나지 않는다 · 판 칸은 충분하다")
    func cellsNeverOverlap() {
        for size in Self.screens {
            for rows in [2, 3, 7] {
                let layout = GamesRummyMatchLayout(size: size, rackRows: rows)
                let cells = [layout.nav, layout.opponentCard(0), layout.opponentCard(1), layout.opponentCard(2), layout.mySeatCard,
                             layout.table, layout.status, layout.rack,
                             layout.info, layout.tools, layout.submit, layout.draw, layout.undo, layout.sort]
                let screen = CGRect(origin: .zero, size: size)
                for (index, cell) in cells.enumerated() {
                    #expect(screen.contains(cell), "\(size) \(rows)줄: \(index)번 칸이 화면 밖 \(cell)")
                    #expect(cell.width > 0 && cell.height > 0, "\(size): \(index)번 칸이 비었다")
                    for other in cells[(index + 1)...] {
                        let overlap = cell.intersection(other)
                        #expect(overlap.isNull || overlap.height <= 0.5 || overlap.width <= 0.5, "\(size) \(rows)줄: 칸이 겹친다 \(cell) \(other)")
                    }
                }
                #expect(layout.table.height > 190, "\(size) \(rows)줄: 판이 너무 작다 \(layout.table.height)")
            }
        }
    }

    @Test("칸: 받침대 높이는 줄 수로 안 변한다(판이 안 흔들린다) · 왼쪽 90 · 오른쪽 100 · 판 폭은 가운데 전부 · iPhone 15 설계값")
    func rackHeightIsFixed() {
        let size = CGSize(width: 734, height: 372)
        let two = GamesRummyMatchLayout(size: size, rackRows: 2)
        let five = GamesRummyMatchLayout(size: size, rackRows: 5)
        #expect(two.rack == five.rack && two.table == five.table)
        #expect(two.table.minX == 90 && two.table.width == 544 && two.rightColumn.minX == 634 && two.rightColumn.width == 100)
        #expect(two.rack.width == two.table.width && two.rack.maxY == 372)
        #expect(abs(two.rack.height - 109.1) < 0.2)
        #expect(abs(two.table.height - 244.9) < 0.2)
    }

    @Test("오른쪽 열: 여섯 크기에서 버튼 넷이 44pt 아래로 안 내려가고 [완료]가 가장 크다 · 왼쪽 열: 내 자리 카드는 맨 아래 · 상대 3장과 안 겹친다")
    func columns() {
        for size in Self.screens {
            let layout = GamesRummyMatchLayout(size: size)
            let cells = [layout.submit, layout.draw, layout.undo, layout.sort]
            for cell in cells { #expect(cell.height >= GamesRummyMatchLayout.minActionHeight, "\(size): \(cell)") }
            #expect(layout.submit.height > layout.draw.height && layout.draw.height > layout.undo.height && layout.undo.height > layout.sort.height)
            #expect(layout.sort.maxY <= size.height - GamesRummyMatchLayout.columnPadding + 0.001)
            #expect(layout.opponentCard(2).maxY <= layout.mySeatCard.minY)
            #expect(layout.opponentCard(0).height >= 59, "\(size): 카드 글자 세 줄이 안 든다 \(layout.opponentCard(0).height)")
            #expect(layout.isSeatCardCompact == (layout.opponentCard(0).height < GamesRummyMatchLayout.seatCardFullContentHeight), "\(size): 낮은 칸인데 얼굴이 그대로다")
            #expect(layout.leftColumn.contains(layout.mySeatCard) && layout.mySeatCard.maxY > size.height - 10)
        }
    }

    @Test("버튼 하나의 터치 자리: [나가기] · [규칙] · [777] · [789] 가 여섯 크기에서 44×44 이상이고 칸 합이 칸을 안 넘는다")
    func buttonTouchTargets() {
        for size in Self.screens {
            let layout = GamesRummyMatchLayout(size: size)
            #expect(layout.navButton.width >= 44 && layout.navButton.height >= 44, "\(size): \(layout.navButton)")
            #expect(layout.sortButton.width >= 44 && layout.sortButton.height >= 44, "\(size): \(layout.sortButton)")
            #expect(layout.navButton.width * 2 + GamesRummyMatchLayout.navGap <= layout.nav.width + 0.001)
            #expect(layout.sortButton.width * 2 + GamesRummyMatchLayout.sortDividerWidth <= layout.sort.width + 0.001)
            #expect(GamesRummyMatchLayout.navButtonDiameter <= layout.navButton.width, "그림이 터치 자리보다 크다")
        }
        // 넷 다 44pt 가 안 되는 높이에서는 열을 넘지 않는 쪽이 먼저다.
        let tight = GamesRummyMatchLayout(size: CGSize(width: 500, height: 260))
        #expect(tight.sort.maxY <= 260 - GamesRummyMatchLayout.columnPadding + 0.001)
    }

    // MARK: - 보기

    @Test("보기: 기본은 폭 맞춤(iPhone 15 약 0.55 · 타일 약 22×31 · 세로 약 445 단위) · 전체 보기는 높이까지 맞춤 · 상한은 타일 폭 40")
    func defaultViewMatchesTheDesign() {
        let view = GamesRummyViewport(viewport: Self.table)
        #expect(abs(view.scale - 0.548) < 0.001)
        #expect(abs(view.tileSize.width - 21.9) < 0.1)
        #expect(abs(view.tileSize.height - 30.7) < 0.1)
        #expect(abs(view.visibleLogical.width - 1000) < 0.01 && abs(view.visibleLogical.height - 445) < 1)
        #expect(abs(GamesRummyViewport.fitScale(Self.table) - 244.0 / 640.0) < 0.001)
        #expect(GamesRummyViewport.maxScale == 1)
        #expect(!view.isFullView)
    }

    @Test("보기: 기본 보기는 세로로 민다(양끝에서 멈춘다) · 가로는 왼끝 묶음 손잡이 폭만큼만 · 키우면 가로도 민다")
    func panClamps() {
        var view = GamesRummyViewport(viewport: Self.table)
        #expect(view.origin == .zero)
        view.pan(by: CGSize(width: 0, height: 100))
        #expect(view.origin.y == 0, "위쪽 끝을 넘었다")
        view.pan(by: CGSize(width: 0, height: -100))
        #expect(abs(view.origin.y - 100 / view.scale) < 0.001, "손을 위로 끌면 판은 아래를 보여 준다")
        view.pan(by: CGSize(width: 0, height: -100_000))
        #expect(abs(view.visibleLogical.maxY - 640) < 0.001, "아래쪽 끝을 넘었다")
        view.pan(by: CGSize(width: -100, height: 0))
        #expect(abs(view.origin.x) < 0.01, "폭이 꼭 찬 보기가 오른쪽으로 더 갔다")
        view.pan(by: CGSize(width: 100, height: 0))
        #expect(abs(view.origin.x - (-28 / view.scale)) < 0.001, "왼끝 묶음 손잡이가 안 닿는다")

        var zoomed = GamesRummyViewport(viewport: Self.table)
        zoomed.zoom(to: 1, anchor: .zero)
        zoomed.pan(by: CGSize(width: -100_000, height: 0))
        #expect(abs(zoomed.visibleLogical.maxX - 1000) < 0.001, "오른쪽 끝을 넘었다")
        zoomed.pan(by: CGSize(width: 100_000, height: 0))
        #expect(abs(zoomed.origin.x - (-28)) < 0.001)
    }

    @Test("보기: 핀치는 손 아래 논리 점을 그 자리에 두고, 범위 밖 배율은 자른다")
    func zoomKeepsTheAnchor() {
        var view = GamesRummyViewport(viewport: Self.table)
        view.pan(by: CGSize(width: 0, height: -60))
        let anchor = CGPoint(x: 200, y: 100)
        let before = view.transform.toLogical(anchor)
        view.zoom(to: 0.8, anchor: anchor)
        #expect(view.scale == 0.8)
        let after = view.transform.toLogical(anchor)
        #expect(abs(before.x - after.x) < 0.01 && abs(before.y - after.y) < 0.01, "\(before) → \(after)")
        view.zoom(to: 5, anchor: anchor)
        #expect(view.scale == 1)
        view.zoom(to: 0.01, anchor: anchor)
        #expect(view.isFullView)
        #expect(view.origin == .zero, "전체 맞춤에서 오프셋이 남았다")
    }

    @Test("보기: [전체 보기] 토글은 맞춤 ↔ 기본을 오간다 · 전체 보기는 캔버스가 가로 가운데")
    func toggleSwitches() {
        var view = GamesRummyViewport(viewport: Self.table)
        let original = view.scale
        view.toggleFullView()
        #expect(view.isFullView)
        #expect(view.transform.screenOrigin.x > 0 && view.transform.screenOrigin.y == 0)
        #expect(view.scale < original)
        view.toggleFullView()
        #expect(view.scale == original)
    }

    @Test("보기: 칸이 바뀌면 기본 보기는 새 기본으로 · 사람이 고른 배율은 그대로 · 전환 중 세로 칸을 거쳐도 기본 보기가 전체 보기로 안 바뀐다")
    func resizeKeepsChoice() {
        var view = GamesRummyViewport(viewport: Self.table)
        view.resize(to: CGSize(width: 481, height: 238))
        #expect(abs(view.scale - 0.481) < 0.001)
        view.zoom(to: 0.9, anchor: .zero)
        view.resize(to: Self.table)
        #expect(view.scale == 0.9, "사람이 고른 배율이 칸 변화로 바뀌었다")

        var turning = GamesRummyViewport(viewport: Self.table)
        turning.resize(to: CGSize(width: 293, height: 700))
        turning.resize(to: Self.table)
        #expect(!turning.isFullView && abs(turning.scale - 0.548) < 0.001, "세로 칸을 거치니 전체 보기가 됐다")
        var full = GamesRummyViewport(viewport: Self.table)
        full.toggleFullView()
        full.resize(to: CGSize(width: 667, height: 300))
        #expect(full.isFullView, "사람이 고른 전체 보기가 풀렸다")
    }

    @Test("보기: 가장자리 28pt 안에서만 초당 400 단위로 밀고(가로 · 세로), 끝에 닿으면 멈춘다")
    func edgePan() {
        var view = GamesRummyViewport(viewport: Self.table)
        view.zoom(to: 1, anchor: .zero)
        var moved = view.edgePan(pointer: CGPoint(x: 200, y: 100), deltaTime: 0.1)
        #expect(!moved, "가운데에서 밀렸다")
        view.pan(by: CGSize(width: 10_000, height: 0))
        let home = view.origin.x
        moved = view.edgePan(pointer: CGPoint(x: 10, y: 100), deltaTime: 0.1)
        #expect(!moved, "왼쪽 끝인데 움직였다고 한다")
        #expect(view.origin.x == home)
        moved = view.edgePan(pointer: CGPoint(x: 540, y: 100), deltaTime: 0.1)
        #expect(moved)
        #expect(abs(view.origin.x - (home + 40)) < 0.001)
        moved = view.edgePan(pointer: CGPoint(x: 5, y: 100), deltaTime: 0.05)
        #expect(moved)
        #expect(abs(view.origin.x - (home + 20)) < 0.001)
        // 경계값: 정확히 28 은 가장자리가 아니다.
        moved = view.edgePan(pointer: CGPoint(x: 28, y: 100), deltaTime: 0.1)
        #expect(!moved)
        moved = view.edgePan(pointer: CGPoint(x: 548 - 28, y: 100), deltaTime: 0.1)
        #expect(!moved)
    }

    @Test("보기: 화면 밖 묶음을 양쪽으로 세고(일부 보이면 안 센다) 배지를 누르면 가장 가까운 것이 보인다 · 기본 보기에서는 좌우가 없다")
    func offscreenBadges() {
        var view = GamesRummyViewport(viewport: Self.table)
        view.zoom(to: 1, anchor: .zero)
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
        // 기본 보기 · 전체 맞춤이면 좌우 화면 밖이 없다.
        #expect(GamesRummyViewport(viewport: Self.table).offscreenCounts(frames) == (left: 0, right: 0))
        view.zoom(to: 0.01, anchor: .zero)
        #expect(view.offscreenCounts(frames) == (left: 0, right: 0))
    }

    // MARK: - 받침대

    @Test("받침대: frame ↔ slot 왕복(네 크기 · 2·3·5줄 · 반 칸 전부) · 한 줄 16장이 칸 안에 든다")
    func rackRoundTrip() {
        #expect(GamesRummyRackGeometry.halfColumns == RummyRackLayout.halfColumnsPerRow, "폰 폭이 코어(맥) 값과 다르다")
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

    @Test("받침대: 타일 폭 = 가운데 폭 / 16 · 높이 1.39배 · 3줄부터 맥 tileScale 산식(2/줄) · 넓은 기기도 높이 상한을 안 넘는다")
    func rackTileSizes() {
        let rect = GamesRummyMatchLayout(size: CGSize(width: 734, height: 372)).rack
        let base = GamesRummyRackGeometry(size: rect.size)
        #expect(abs(base.tileSize.width - 536.0 / 16) < 0.001)
        #expect(abs(base.tileSize.height / base.tileSize.width - 1.39) < 0.001)
        let three = GamesRummyRackGeometry(size: rect.size, rowCount: 3)
        #expect(abs(three.tileScale - 2.0 / 3) < 0.001)
        #expect(abs(three.tileSize.width - base.tileSize.width * 2 / 3) < 0.05)
        let five = GamesRummyRackGeometry(size: rect.size, rowCount: 5)
        #expect(five.tileScale == 0.4)
        #expect(five.tileSize.width <= base.tileSize.width * 0.4 + 0.001, "칸 안에 담으려면 산식보다 커질 수 없다")
        for size in Self.screens {
            let layout = GamesRummyMatchLayout(size: size)
            #expect(layout.rack.height <= size.height * GamesRummyMatchLayout.rackMaxHeightShare + 0.001)
            // 시스템 '화면 확대'(높이 354 아래)는 칸이 그만큼 좁다 — 맥과 같은 한 줄 16장을 지키는 값이다.
            let smallest: CGFloat = size.height >= 354 ? 29 : 22
            #expect(GamesRummyRackGeometry(size: layout.rack.size).tileSize.width >= smallest, "\(size): 받침대 타일이 너무 작다")
        }
    }

    @Test("받침대: 놓을 자리는 묶음 길이만큼 폭 안으로 자른다")
    func rackSlotClamps() {
        let rack = GamesRummyRackGeometry(size: GamesRummyMatchLayout(size: CGSize(width: 734, height: 372)).rack.size)
        #expect(rack.slot(tileLeft: 9999, centerY: 10, tiles: 3) == RummyRackSlot(row: 0, halfCol: 26))
        #expect(rack.slot(tileLeft: -50, centerY: 1000, tiles: 1) == RummyRackSlot(row: 1, halfCol: 0))
    }

    // MARK: - 누르기 판정

    private func fixture(editable: Bool = true) -> (layout: GamesRummyMatchLayout, rack: GamesRummyRackGeometry,
                                                    rackLayout: RummyRackLayout, view: GamesRummyViewport,
                                                    table: RummyTableLayout) {
        let layout = GamesRummyMatchLayout(size: CGSize(width: 734, height: 372))
        return (layout, GamesRummyRackGeometry(size: layout.rack.size),
                RummyRackLayout.packed([100, 101, 102]),
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

    @Test("누르기: 받침대 타일 · 받침대 빈칸 · 판 타일 · 손잡이 · 빈 펠트 · 양옆 열")
    func hitClasses() {
        let f = fixture()
        let tile = f.rack.frame(RummyRackSlot(row: 0, halfCol: 2))
        #expect(classify(CGPoint(x: f.layout.rack.minX + tile.midX, y: f.layout.rack.minY + tile.midY)) == .rackTile(101))
        #expect(classify(CGPoint(x: f.layout.rack.maxX - 10, y: f.layout.rack.maxY - 2)) == .none, "받침대 빈칸은 무시")
        #expect(classify(screen(CGPoint(x: 100 + 40 + 20, y: 70))) == .boardTile(1))
        // 손잡이: 묶음 왼쪽 바깥 28pt.
        let edge = screen(CGPoint(x: 100, y: 70))
        #expect(classify(CGPoint(x: edge.x - 10, y: edge.y)) == .meldHandle(0))
        #expect(classify(CGPoint(x: edge.x - 27, y: edge.y)) == .meldHandle(0))
        #expect(classify(CGPoint(x: edge.x - 29, y: edge.y)) == .felt, "28pt 밖은 펠트")
        #expect(classify(screen(CGPoint(x: 300, y: 300))) == .felt)
        #expect(classify(CGPoint(x: 40, y: 200)) == .none, "왼쪽 열")
        #expect(classify(CGPoint(x: f.layout.submit.midX, y: f.layout.submit.midY)) == .none, "오른쪽 열")
        #expect(classify(CGPoint(x: f.layout.status.midX, y: f.layout.status.midY)) == .none, "상태 줄")
    }

    @Test("누르기: 캔버스 왼끝(x 0) 묶음의 손잡이는 처음엔 칸 밖이고, 기본 보기에서도 판을 밀면 닿는다")
    func handleOfALeftEdgeMeldIsReachable() {
        let layout = GamesRummyMatchLayout(size: CGSize(width: 734, height: 372))
        let rack = GamesRummyRackGeometry(size: layout.rack.size)
        let table = RummyTableLayout(counts: [3], points: [RummyPoint(x: 0, y: 50)])
        var view = GamesRummyViewport(viewport: layout.table.size)
        func hit(_ point: CGPoint) -> GamesRummyHit {
            GamesRummyHitTester.classify(point: CGPoint(x: point.x + layout.table.minX, y: point.y + layout.table.minY),
                                         layout: layout, rack: rack, rackLayout: RummyRackLayout(),
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
        #expect(classify(CGPoint(x: f.layout.rack.minX + tile.midX, y: f.layout.rack.minY + tile.midY), editable: false) == .rackTile(100))
    }

    @Test("들어 올림: 판 위에서는 손 위 48pt · 받침대 안에서 아래로 갈수록 준다 · 기준점은 뒤집히지 않는다 · 역산이 맞다 · 아랫줄에 놓을 손 자리가 화면 안이다")
    func liftPoint() {
        #expect(GamesRummyGestureRules.liftedPoint(finger: CGPoint(x: 10, y: 100)) == CGPoint(x: 10, y: 52))
        #expect(GamesRummyGestureRules.liftScale == 1.25 && GamesRummyGestureRules.liftDelay == 0.5
                && GamesRummyGestureRules.dragThreshold == 8)
        for size in Self.screens {
            let layout = GamesRummyMatchLayout(size: size)
            let rack = layout.rack
            #expect(layout.fingerLift(atY: rack.minY - 1) == 48 && layout.fingerLift(atY: rack.minY) == 48)
            #expect(abs(layout.fingerLift(atY: rack.maxY) - GamesRummyGestureRules.fingerLiftAtBottom) < 0.001)
            var last = -CGFloat.infinity
            for y in stride(from: CGFloat(0), through: size.height + 30, by: 0.5) {
                let pointer = y - layout.fingerLift(atY: y)
                #expect(pointer > last, "\(size) \(y): 손을 내렸는데 기준점이 올라갔다")
                last = pointer
                let back = layout.finger(forPointer: CGPoint(x: 5, y: pointer))
                #expect(abs(back.y - y) < 0.001, "\(size) \(y): 역산이 \(back.y)")
            }
            // 받침대 아랫줄 가운데에 놓는 손 자리가 세이프 영역 안이다(48pt 그대로면 화면 끝 몇 pt 뿐이다).
            let geometry = GamesRummyRackGeometry(size: rack.size)
            let row = rack.minY + geometry.rowCenter(1)
            #expect(layout.finger(forPointer: CGPoint(x: 5, y: row)).y < size.height, "\(size): 아랫줄 손 자리가 화면 밖")
            #expect(row + 48 > size.height - 8, "기준선: 48pt 그대로면 끝자리다 — 이 값이 없어지면 줄임이 필요 없다")
        }
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
        #expect(target(CGPoint(x: f.layout.rack.minX + tile.midX, y: f.layout.rack.minY + tile.midY)) == .rackSlot(RummyRackSlot(row: 1, halfCol: 6)))
        #expect(target(screen(CGPoint(x: 165, y: 70))) == .meld(0, index: 2))
        #expect(target(screen(CGPoint(x: 300, y: 300))) == .newMeldAt(RummyPoint(x: 280, y: 272)))
        #expect(target(screen(CGPoint(x: 300, y: 300)), myTurn: false) == nil)
        #expect(target(CGPoint(x: 40, y: 10)) == nil, "왼쪽 열엔 못 놓는다")
        #expect(target(CGPoint(x: f.layout.submit.midX, y: f.layout.submit.midY)) == nil, "오른쪽 열엔 못 놓는다")
    }
}

/// 비교를 쓰려고 `offscreenCounts` 튜플을 값으로 맞춘다.
private func == (lhs: (left: Int, right: Int), rhs: (left: Int, right: Int)) -> Bool {
    lhs.left == rhs.left && lhs.right == rhs.right
}
