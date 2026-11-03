import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 뒤집기 — 미니게임 창 사이드바의 다섯째 대결 문(FLIP/SPEC.md §4.6 #18 · §5.8 · §6.3 T 줄).
//
// 같이 하기 묶음이 다섯 줄이 되면 옛 줄(42 · 간격 4)로는 466 > 안쪽 442 라 다섯째 문이 창 밖으로 잘린다. 대표 결정(2026-11-03
// #d_zw7CXHEtevVS "C 스크롤로" — 줄·창 그대로, 같이 하기 칸만 스크롤)대로 줄 42/4 · 창 888×470 을 그대로 두고 **같이 하기 칸(202)만**
// 스크롤한다. 카드에 적어 드린 약점(맥은 스크롤 막대를 숨겨 아래 줄 · 그 신청 점을 놓치기 쉬움)은 바닥 흐림 + 신청이 오면 그 문까지
// 저절로 굴리기로 메운다(`MiniGameSidebarDuelViewport`).
//
// 산식만 재면 다섯째 문이 **실제로 그려지고 닿을 수 있는지** 모른다. ImageRenderer 는 ScrollView 안쪽을 못 그리므로 둘로 나눠 잰다:
//   · 스냅샷(클립 갈래) — 앱 첫 화면과 같은 그림: 문 넷이 칸 안에, 창 바닥 아래로는 잉크 0(옛 줄을 그냥 세운 기준선은 넘친다).
//   · 실제 ScrollView — 화면에 올리지 않는 테두리 없는 창에 붙여(V0331 과 같은 수법 · orderFront 없음) AppKit 이 그린 픽셀로 잰다:
//     칸 높이 · 내용 높이 · 끝까지 내리면 다섯째 문이 흐림 위에 온전히 선다 · 신청이 오면 저절로 굴러간다.

@MainActor
private enum RSB {
    static let layout = MiniGameWindowLayout.self
    static var windowHeight: CGFloat { layout.contentSize.height }
    /// 사이드바 안쪽 바닥(창 높이 − 위아래 여백). 이 아래에 잉크가 있으면 줄이 창 밖으로 넘친 것이다.
    static var innerBottom: CGFloat { windowHeight - layout.contentPadding }
    /// 같이 하기 줄들이 시작하는 y(창 좌표) = 같이 하기 머리 아래.
    static var duelRowsTop: CGFloat {
        layout.sidebarDuelGroupRect.minY + layout.sidebarGroupTitleHeight + layout.sidebarGroupTitleSpacing
    }
    /// 같이 하기 칸 바닥(창 좌표).
    static var viewportBottom: CGFloat { duelRowsTop + layout.sidebarDuelViewportHeight }
    /// 끝까지 내렸을 때의 스크롤 거리 = 줄 + 꼬리 − 칸.
    static var maxScroll: CGFloat { layout.sidebarDuelRowsHeight + layout.sidebarDuelFadeHeight - layout.sidebarDuelViewportHeight }

    /// 줄 높이·간격을 주어진 값으로 두고 같이 하기를 **스크롤 없이** 세운 사이드바의 세로 합(옛 방식 — 기준선 산식).
    static func unscrolledHeight(rowHeight: CGFloat, spacing: CGFloat, duelRows: Int) -> CGFloat {
        func group(_ rows: Int) -> CGFloat {
            layout.sidebarGroupTitleHeight + layout.sidebarGroupTitleSpacing
                + CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * spacing
        }
        return group(MiniGameKind.macCases.count) + layout.sidebarGroupSpacing + group(duelRows)
    }

    /// 같이 하기 i 번째 줄의 아이콘 타일 사각형(창 좌표, pt). `scrolled` 만큼 위로 굴린 자리.
    static func duelTile(_ index: Int, scrolled: CGFloat = 0) -> CGRect {
        let rowTop = duelRowsTop + CGFloat(index) * (layout.sidebarRowHeight + layout.sidebarRowSpacing) - scrolled
        return CGRect(x: layout.sidebarPadding + 6, y: rowTop + (layout.sidebarRowHeight - layout.sidebarIconSize) / 2,
                      width: layout.sidebarIconSize, height: layout.sidebarIconSize)
    }

    static func sidebar(invites: MiniGameDuelInvites = MiniGameDuelInvites(), clips: Bool) -> some View {
        MiniGameSidebar(selected: .flappy, isPlaying: false, isFrozen: false, invites: invites,
                        onSelect: { _ in }, onGomoku: {}, onChess: {}, onTetrisDuel: {}, onRummy: {}, onReversi: {},
                        clipsOverflowInsteadOfScroll: clips)
            .frame(width: layout.sidebarWidth, height: windowHeight, alignment: .top)
            .background(CheckTheme.background)
    }

    /// ★ 기준선 그림: 같은 다섯 문을 옛 방식(스크롤 없이 줄 42/4 로 그냥 세움)으로 같이 하기 줄 자리부터 그린다.
    static func unscrolledDoors() -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: duelRowsTop)
            VStack(spacing: layout.sidebarRowSpacing) {
                MiniGameGomokuEntryButton {}
                MiniGameChessEntryButton {}
                MiniGameTetrisDuelEntryButton {}
                MiniGameRummyEntryButton {}
                MiniGameReversiEntryButton {}
            }
            .padding(.horizontal, layout.sidebarPadding)
        }
        .frame(width: layout.sidebarWidth, height: windowHeight, alignment: .top)
        .background(CheckTheme.fieldFill)
        .background(CheckTheme.background)
    }

    /// 문 하나를 사이드바와 같은 바닥(배경 + fieldFill) 위에 줄 폭으로 단독으로 그린다.
    static func door(_ door: some View) -> some View {
        door.frame(width: layout.sidebarRowWidth)
            .background(CheckTheme.fieldFill)
            .background(CheckTheme.background)
    }
}

private enum RSBError: Error { case render }

@MainActor
private func rsbBitmap(_ view: some View) throws -> NSBitmapImageRep {
    guard let bitmap = CheckRenderSettle.bitmap(view.fixedSize(), scale: 2) else { throw RSBError.render }
    return bitmap
}

private func rsbSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    MiniGameSnapshots.save(bitmap, name: "\(name).png", sub: "reversi")
}

// MARK: - 화면에 올리지 않는 창(실제 ScrollView)

@MainActor
private func rsbSpin(_ seconds: Double = 0.05) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func rsbFirstSubview<T: NSView>(of root: NSView, _ type: T.Type) -> T? {
    if let match = root as? T { return match }
    for child in root.subviews {
        if let match = rsbFirstSubview(of: child, type) { return match }
    }
    return nil
}

/// 테두리 없는 창에 붙이기만 한다(orderFront 없음 — 사용자 화면에 안 뜨고 클릭을 가로채지 않는다). 레이아웃·스크롤·그리기는 이것으로 돈다.
@MainActor
private func rsbMount(_ view: some View, width: CGFloat, height: CGFloat) -> (NSWindow, NSHostingView<AnyView>) {
    let host = NSHostingView(rootView: AnyView(view))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    rsbSpin(0.15)
    host.layoutSubtreeIfNeeded()
    return (window, host)
}

/// AppKit 이 그린 픽셀(2x, 위가 0행). ScrollView 안쪽도 그려진다(ImageRenderer 와 다르다).
/// `cacheDisplay(in:to:)` 로 그린다 — 2x 크기 그림에 `displayIgnoringOpacity` 로 그리면 1x 로 왼쪽 아래 1/4 에만 그려진다(실측).
@MainActor
private func rsbHostBitmap(_ host: NSView) throws -> NSBitmapImageRep {
    host.layoutSubtreeIfNeeded()
    let size = host.bounds.size
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw RSBError.render }
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep
}

/// 위에서부터 굴러간 거리(pt). 문서 뷰가 뒤집혔든 아니든 같은 뜻으로 잰다.
@MainActor
private func rsbScrolled(_ scrollView: NSScrollView) -> CGFloat {
    let clip = scrollView.contentView
    guard let document = scrollView.documentView else { return 0 }
    return document.isFlipped ? clip.bounds.minY : document.frame.height - clip.bounds.maxY
}

@MainActor
private func rsbScroll(_ scrollView: NSScrollView, to distance: CGFloat) {
    guard let document = scrollView.documentView else { return }
    let clip = scrollView.contentView
    let y = document.isFlipped ? distance : max(0, document.frame.height - clip.bounds.height - distance)
    clip.scroll(to: NSPoint(x: 0, y: y))
    scrollView.reflectScrolledClipView(clip)
}

// MARK: - 픽셀

/// 사각형(pt) 안 픽셀 가운데 조건을 만족하는 수와 그 상자(pt).
private func rsbInk(_ bitmap: NSBitmapImageRep, in rect: CGRect,
                    _ predicate: (Int, Int, Int) -> Bool) -> (count: Int, box: CGRect) {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return (0, .null) }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2) - 1)
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2) - 1)
    guard x0 <= x1, y0 <= y1 else { return (0, .null) }
    var count = 0
    var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if predicate(Int(data[o]), Int(data[o + 1]), Int(data[o + 2])) {
                count += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard count > 0 else { return (0, .null) }
    return (count, CGRect(x: Double(minX) / 2, y: Double(minY) / 2,
                          width: Double(maxX - minX + 1) / 2, height: Double(maxY - minY + 1) / 2))
}

/// 대결 문 초록(`CheckTheme.working` ≈ (89,224,161)) — 파랑 accent(84,171,255)는 `g > b + 30` 에서 걸러진다(V0344 와 같은 판정).
private func rsbGreen(_ r: Int, _ g: Int, _ b: Int) -> Bool { g > r + 80 && g > b + 30 && g > 150 }
/// 받은 신청 점(`CheckTheme.danger` ≈ (255,115,117)).
private func rsbRed(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 200 && r > g + 70 && r > b + 70 }

/// 두 그림의 같은 크기 사각형(각자 원점) 사이 가장 큰 채널 차.
private func rsbMaxDifference(_ lhs: NSBitmapImageRep, _ lhsRect: CGRect, _ rhs: NSBitmapImageRep, _ rhsRect: CGRect) -> Int {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData else { return 255 }
    let w = Int(lhsRect.width * 2), h = Int(lhsRect.height * 2)
    let ax = Int(lhsRect.minX * 2), ay = Int(lhsRect.minY * 2), bx = Int(rhsRect.minX * 2), by = Int(rhsRect.minY * 2)
    guard ax >= 0, ay >= 0, bx >= 0, by >= 0, ax + w <= lhs.pixelsWide, ay + h <= lhs.pixelsHigh,
          bx + w <= rhs.pixelsWide, by + h <= rhs.pixelsHigh else { return 255 }
    var worst = 0
    for dy in 0..<h {
        for dx in 0..<w {
            let oa = (ay + dy) * lhs.bytesPerRow + (ax + dx) * lhs.samplesPerPixel
            let ob = (by + dy) * rhs.bytesPerRow + (bx + dx) * rhs.samplesPerPixel
            for channel in 0..<3 { worst = max(worst, abs(Int(a[oa + channel]) - Int(b[ob + channel]))) }
        }
    }
    return worst
}

@MainActor
@Suite(.serialized)
struct V03xxReversiSidebarTests {
    /// 없으면: 다섯째 문을 더하고 줄을 그대로 둔 채 스크롤 칸이 없으면 사이드바가 466 으로 안쪽 442 를 넘어 다섯째 문이 창 밖으로
    /// 잘린다. 줄을 누르거나(옛 임시 D) 창을 키우면(A) 대표가 고른 C 가 아니다.
    @Test
    func theDuelDoorsScrollInsideTheSidebarAtTheOriginalRowSize() {
        // 줄·창 그대로(C): v0.3.69 줄 42 · 간격 4 · 아이콘 30, 창 888×470 · 게임 구역 700×470.
        #expect(RSB.layout.sidebarRowHeight == 42)
        #expect(RSB.layout.sidebarRowSpacing == 4)
        #expect(RSB.layout.sidebarIconSize == 30)
        #expect(RSB.layout.contentSize == CGSize(width: 888, height: 470))
        #expect(RSB.layout.gameAreaSize == CGSize(width: 700, height: 470))
        // 문 수는 문 목록 하나에서 온다.
        #expect(RSB.layout.sidebarDuelRows == 5)
        #expect(MiniGameDuelDoor.allCases == [.gomoku, .chess, .tetris, .rummy, .reversi])

        let inner = RSB.windowHeight - RSB.layout.contentPadding * 2
        #expect(inner == 442 && RSB.layout.sidebarInnerHeight == inner)
        // 같이 하기 칸 = 남은 자리(202), 줄 다섯(226)은 그보다 길어 칸 안에서 스크롤된다.
        #expect(RSB.layout.sidebarDuelViewportHeight == 202)
        #expect(RSB.layout.sidebarDuelRowsHeight == 226)
        #expect(RSB.layout.sidebarDuelScrolls)
        #expect(RSB.layout.sidebarContentHeight == inner, "사이드바 합 \(RSB.layout.sidebarContentHeight) 이 안쪽 높이와 다르다")
        #expect(RSB.viewportBottom == RSB.innerBottom)
        // 칸에는 문 넷이 온전히 서고, 다섯째는 윗머리만 비친다(이어진다는 단서).
        #expect(RSB.duelTile(3).maxY <= RSB.viewportBottom - RSB.layout.sidebarDuelFadeHeight)
        let fifthRowTop = RSB.duelRowsTop + 4 * (RSB.layout.sidebarRowHeight + RSB.layout.sidebarRowSpacing)
        #expect(fifthRowTop < RSB.viewportBottom && fifthRowTop + RSB.layout.sidebarRowHeight > RSB.viewportBottom)
        // 끝까지 내리면(꼬리 = 흐림 높이) 다섯째 문 전체가 흐림 위에 선다.
        #expect(RSB.maxScroll == 40)
        #expect(fifthRowTop - RSB.maxScroll + RSB.layout.sidebarRowHeight == RSB.viewportBottom - RSB.layout.sidebarDuelFadeHeight)
        #expect(RSB.layout.sidebarDuelFadeFloor > 0, "흐림이 바닥을 다 지우면 접힌 문의 신청 점까지 사라진다")

        // ★ 기준선: 같은 줄(42 · 4)로 스크롤 없이 다섯 줄을 세우면 넘친다 — C 를 둔 이유.
        let unscrolled = RSB.unscrolledHeight(rowHeight: 42, spacing: 4, duelRows: 5)
        #expect(unscrolled == 466 && unscrolled > inner)
        // 넷까지는 스크롤 없이 들어갔다(v0.3.69) — 칸이 다섯째부터 생긴다는 경계.
        #expect(RSB.unscrolledHeight(rowHeight: 42, spacing: 4, duelRows: 4) <= inner)
    }

    /// 없으면(결과): 산식은 초록인데 스냅샷(= 앱 첫 화면) 그림에서 문이 창 밖으로 그려지거나 칸 안 아이콘이 비어 있다.
    /// 기준선: 같은 다섯 문을 옛 방식으로 그냥 세우면 창 바닥 아래에 잉크가 생긴다(같은 감지기).
    @Test
    func theSnapshotShowsFourDoorsInsideTheWindowAndNothingBelow() throws {
        let bitmap = try rsbBitmap(RSB.sidebar(clips: true))
        rsbSave(bitmap, "minigame-sidebar-duel-scroll-top")
        #expect(bitmap.pixelsHigh == Int(RSB.windowHeight * 2), "사이드바를 창 높이로 그리지 못했다(\(bitmap.pixelsHigh)px)")
        for index in 0..<4 {
            let ink = rsbInk(bitmap, in: RSB.duelTile(index), rsbGreen)
            print("[사이드바] 같이 하기 \(index + 1)번째 타일 초록 \(ink.count)px · 상자 \(ink.box)")
            #expect(ink.count > 20, "같이 하기 \(index + 1)번째 문의 아이콘이 안 그려진다(초록 \(ink.count)px)")
            #expect(ink.box.maxY <= RSB.viewportBottom, "\(index + 1)번째 문 잉크가 칸 바닥(\(RSB.viewportBottom)) 아래로 내려갔다")
        }
        let strip = CGRect(x: 0, y: RSB.innerBottom, width: RSB.layout.sidebarWidth, height: RSB.layout.contentPadding)
        let below = rsbInk(bitmap, in: strip, rsbGreen).count
        #expect(below == 0, "안쪽 바닥 아래에 문 잉크가 \(below)px 있다 — 줄이 창 밖으로 넘친다")

        // ★ 기준선(결과가 갈린다): 옛 방식으로 그냥 세운 다섯 문은 창 바닥 아래로 넘친다.
        let baseline = try rsbBitmap(RSB.unscrolledDoors())
        rsbSave(baseline, "minigame-sidebar-duel-unscrolled-baseline")
        let baselineBelow = rsbInk(baseline, in: strip, rsbGreen).count
        print("[사이드바] 바닥 아래 초록: 스크롤 칸 \(below)px · 그냥 세운 기준선 \(baselineBelow)px")
        #expect(baselineBelow > 20, "그냥 세운 기준선에서도 바닥 아래가 비었다 — 감지기가 넘침을 못 본다")
    }

    /// 없으면(결과): 칸이 실제 ScrollView 가 아니거나(넘친 문이 그냥 잘려 영영 못 닿는다) 높이가 틀려 다섯째 문을 끝까지 내려도
    /// 흐림 밑에 깔린다. 화면에 올리지 않는 창에서 AppKit 이 그린 픽셀로 잰다.
    @Test
    func theRealScrollViewReachesTheFifthDoorAboveTheFade() throws {
        let (window, host) = rsbMount(RSB.sidebar(clips: false), width: RSB.layout.sidebarWidth, height: RSB.windowHeight)
        defer { window.contentView = nil; window.close() }
        let scrollView = try #require(rsbFirstSubview(of: host, NSScrollView.self), "같이 하기 칸에 스크롤 뷰가 없다")
        let document = try #require(scrollView.documentView)
        print("[사이드바] 칸 \(scrollView.frame.height)pt · 내용 \(document.frame.height)pt · 굴린 거리 \(rsbScrolled(scrollView))")
        #expect(abs(scrollView.frame.height - RSB.layout.sidebarDuelViewportHeight) < 0.5, "칸 높이가 \(scrollView.frame.height) 다")
        #expect(abs(document.frame.height - (RSB.layout.sidebarDuelRowsHeight + RSB.layout.sidebarDuelFadeHeight)) < 0.5,
                "스크롤 내용이 \(document.frame.height) 다 — 줄 다섯 + 꼬리가 아니다")
        #expect(rsbScrolled(scrollView) < 0.5, "신청이 없는데 처음부터 굴러가 있다")

        let top = try rsbHostBitmap(host)
        rsbSave(top, "minigame-sidebar-duel-scroll-live-top")
        for index in 0..<4 {
            #expect(rsbInk(top, in: RSB.duelTile(index), rsbGreen).count > 20, "실제 칸 맨 위에서 \(index + 1)번째 문이 안 보인다")
        }
        let strip = CGRect(x: 0, y: RSB.innerBottom, width: RSB.layout.sidebarWidth, height: RSB.layout.contentPadding)
        #expect(rsbInk(top, in: strip, rsbGreen).count == 0, "실제 칸이 창 바닥 아래로 넘쳐 그린다")

        // 끝까지 내린다 → 다섯째 문이 흐림 위에 온전히, 첫째 문은 칸 위로 사라진다(정말 굴렀다는 증거 — 기준선).
        rsbScroll(scrollView, to: RSB.maxScroll)
        rsbSpin(0.15)
        #expect(abs(rsbScrolled(scrollView) - RSB.maxScroll) < 0.5, "끝까지 내렸는데 \(rsbScrolled(scrollView)) 만 굴렀다")
        let bottom = try rsbHostBitmap(host)
        rsbSave(bottom, "minigame-sidebar-duel-scroll-live-bottom")
        let fifth = rsbInk(bottom, in: RSB.duelTile(4, scrolled: RSB.maxScroll), rsbGreen)
        print("[사이드바] 끝까지 내린 다섯째 타일 초록 \(fifth.count)px · 상자 \(fifth.box)")
        #expect(fifth.count > 20, "끝까지 내려도 다섯째 문(아잉 뒤집기)이 안 보인다")
        #expect(fifth.box.maxY <= RSB.viewportBottom - RSB.layout.sidebarDuelFadeHeight, "다섯째 문이 흐림 밑에 깔린다")
        let firstGone = rsbInk(bottom, in: RSB.duelTile(0, scrolled: RSB.maxScroll), rsbGreen).count
        #expect(firstGone == 0, "끝까지 내렸는데 첫째 문 자리(칸 위)에 초록이 \(firstGone)px — 칸이 위를 자르지 않는다")
        // 같은 자리(끝까지 내렸을 때 다섯째 타일이 서는 곳)가 맨 위 그림에서는 다른 것(큐브 문 아래쪽 · 줄 사이)을 그린다.
        let spot = RSB.duelTile(4, scrolled: RSB.maxScroll)
        let changed = rsbMaxDifference(top, spot, bottom, spot)
        print("[사이드바] 다섯째 자리 맨 위 ↔ 끝 그림 최대 차 \(changed)")
        #expect(changed > 60, "맨 위 그림과 끝 그림의 다섯째 자리가 갈리지 않는다 — 스크롤이 그림을 안 바꾼다(최대 차 \(changed))")
    }

    /// 없으면(결과): 아잉 뒤집기 신청이 와도 다섯째 문은 접힘 아래에 있어 점을 못 본다(대표 카드의 C 약점 그대로).
    /// 기준선: 신청이 맨 위 문(오목)에 오면 굴리지 않는다 — 아무 신청에나 굴러가면 보던 자리를 빼앗는다.
    @Test
    func anInviteOnTheFoldedDoorScrollsItIntoView() throws {
        let (window, host) = rsbMount(RSB.sidebar(clips: false), width: RSB.layout.sidebarWidth, height: RSB.windowHeight)
        defer { window.contentView = nil; window.close() }
        let scrollView = try #require(rsbFirstSubview(of: host, NSScrollView.self))
        func deliver(_ invites: MiniGameDuelInvites) {
            host.rootView = AnyView(RSB.sidebar(invites: invites, clips: false))
            host.layoutSubtreeIfNeeded()
            rsbSpin(0.3)
            host.layoutSubtreeIfNeeded()
        }

        // ★ 기준선: 오목(맨 위) 신청 — 이미 보이므로 안 굴린다.
        deliver(MiniGameDuelInvites(gomoku: true))
        #expect(rsbScrolled(scrollView) < 0.5, "보이는 문의 신청에 칸이 굴렀다(\(rsbScrolled(scrollView)))")

        // 아잉 뒤집기 신청 — 끝까지 굴러 다섯째 문과 점이 흐림 위에 선다.
        deliver(MiniGameDuelInvites(gomoku: true, reversi: true))
        print("[사이드바] 아잉 뒤집기 신청 뒤 굴린 거리 \(rsbScrolled(scrollView))")
        #expect(abs(rsbScrolled(scrollView) - RSB.maxScroll) < 0.5, "아잉 뒤집기 신청이 왔는데 칸이 다섯째 문까지 안 굴렀다")
        let lit = try rsbHostBitmap(host)
        rsbSave(lit, "minigame-sidebar-reversi-invite-dot")
        let fifth = RSB.duelTile(4, scrolled: RSB.maxScroll).insetBy(dx: -6, dy: -6)
        let fourth = RSB.duelTile(3, scrolled: RSB.maxScroll).insetBy(dx: -6, dy: -6)
        let litFifth = rsbInk(lit, in: fifth, rsbRed).count
        print("[사이드바] 다섯째 문 점 \(litFifth)px")
        #expect(litFifth > 20, "아잉 뒤집기 신청이 있는데 다섯째 문에 점이 안 보인다")
        #expect(rsbInk(lit, in: fourth, rsbRed).count == 0, "아잉 뒤집기 신청 점이 큐브 문에 섰다")

        // 창을 처음 열 때 이미 신청이 있으면 열자마자 그 문까지 굴러 있다.
        let (window2, host2) = rsbMount(RSB.sidebar(invites: MiniGameDuelInvites(reversi: true), clips: false),
                                        width: RSB.layout.sidebarWidth, height: RSB.windowHeight)
        defer { window2.contentView = nil; window2.close() }
        let scrollView2 = try #require(rsbFirstSubview(of: host2, NSScrollView.self))
        #expect(abs(rsbScrolled(scrollView2) - RSB.maxScroll) < 0.5, "신청이 있는 채로 열었는데 다섯째 문이 접힘 아래에 있다")
    }

    /// 없으면: 저절로 굴리기가 아무 변화에나(점이 내려갈 때도) 굴러가거나, 새 점이 둘이면 위쪽을 골라 접힌 문을 못 보여 준다.
    @Test
    func theScrollTargetIsTheLowestNewlyLitDoor() {
        let none = MiniGameDuelInvites()
        #expect(MiniGameDuelInvites.scrollTarget(from: nil, to: none) == nil)
        #expect(MiniGameDuelInvites.scrollTarget(from: nil, to: MiniGameDuelInvites(chess: true, reversi: true)) == .reversi)
        #expect(MiniGameDuelInvites.scrollTarget(from: none, to: MiniGameDuelInvites(tetris: true)) == .tetris)
        // 이미 서 있던 점은 다시 굴리지 않는다 — 사람이 위로 올려 둔 칸을 다른 문의 새 점이 아닌 한 끌어내리지 않는다.
        let reversiOnly = MiniGameDuelInvites(reversi: true)
        #expect(MiniGameDuelInvites.scrollTarget(from: reversiOnly, to: reversiOnly) == nil)
        #expect(MiniGameDuelInvites.scrollTarget(from: reversiOnly, to: MiniGameDuelInvites(gomoku: true, reversi: true)) == .gomoku)
        // 점이 내려가면 굴리지 않는다.
        #expect(MiniGameDuelInvites.scrollTarget(from: reversiOnly, to: none) == nil)
        // 문마다 제 칸을 읽는다(첨자가 다른 칸을 읽으면 엉뚱한 문으로 간다).
        for door in MiniGameDuelDoor.allCases {
            var invites = MiniGameDuelInvites()
            switch door {
            case .gomoku: invites.gomoku = true
            case .chess: invites.chess = true
            case .tetris: invites.tetris = true
            case .rummy: invites.rummy = true
            case .reversi: invites.reversi = true
            }
            #expect(MiniGameDuelInvites.scrollTarget(from: none, to: invites) == door)
            #expect(MiniGameDuelDoor.allCases.filter { invites[$0] } == [door])
        }
    }

    /// 없으면(결과): 묶음 안 순서가 섞이거나(문 이름과 아이콘이 다른 자리에 선다) 다섯째 자리에 엉뚱한 문이 그려져도 초록 잉크만
    /// 세는 시험은 초록이다. 자리마다 **그 문을 단독으로 그린 타일**과 맞대고, 이웃 문과는 갈리는지 함께 잰다.
    @Test
    func theFiveDoorsStandInOrderWithReversiLast() throws {
        let panel = V0317ShopTests.stripped(try V0317ShopTests.source("MiniGamePanel.swift"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let order: String = [
            "MiniGameGomokuEntryButton(hasInvite: invites.gomoku) { onGomoku() } ",
            "MiniGameChessEntryButton(hasInvite: invites.chess) { onChess() } ",
            "MiniGameTetrisDuelEntryButton(hasInvite: invites.tetris) { onTetrisDuel() } ",
            "MiniGameRummyEntryButton(hasInvite: invites.rummy) { onRummy() } ",
            "MiniGameReversiEntryButton(hasInvite: invites.reversi) { onReversi() } }",
        ].joined()
        #expect(panel.contains(order), "같이 하기 묶음이 오목 · 체스 · 테트리스 · 큐브 · 아잉 뒤집기 순이 아니다")
        // 줄 순서와 저절로 굴리기의 자리표 순서가 같은 목록이다.
        #expect(panel.contains("case gomoku, chess, tetris, rummy, reversi"), "문 목록 순서가 줄 순서와 다르다")

        let alone = CGRect(x: 6, y: (RSB.layout.sidebarRowHeight - RSB.layout.sidebarIconSize) / 2,
                           width: RSB.layout.sidebarIconSize, height: RSB.layout.sidebarIconSize)
        // 앞 넷: 스냅샷(맨 위 그림)에서 자리마다 단독 문과 맞댄다.
        let sidebar = try rsbBitmap(RSB.sidebar(clips: true))
        let doors: [(String, NSBitmapImageRep)] = [
            ("오목", try rsbBitmap(RSB.door(MiniGameGomokuEntryButton {}))),
            ("체스", try rsbBitmap(RSB.door(MiniGameChessEntryButton {}))),
            ("테트리스", try rsbBitmap(RSB.door(MiniGameTetrisDuelEntryButton {}))),
            ("큐브", try rsbBitmap(RSB.door(MiniGameRummyEntryButton {}))),
        ]
        for (index, door) in doors.enumerated() {
            let same = rsbMaxDifference(sidebar, RSB.duelTile(index), door.1, alone)
            print("[사이드바] \(index + 1)번째 자리 ↔ \(door.0) 문 단독: 최대 차 \(same)")
            #expect(same <= 40, "\(index + 1)번째 자리에 \(door.0) 문이 아닌 것이 그려졌다(최대 차 \(same))")
        }

        // 다섯째: 실제 칸을 끝까지 내린 그림을 같은 수법(AppKit)으로 그린 단독 문과 맞댄다.
        let (window, host) = rsbMount(RSB.sidebar(clips: false), width: RSB.layout.sidebarWidth, height: RSB.windowHeight)
        defer { window.contentView = nil; window.close() }
        let scrollView = try #require(rsbFirstSubview(of: host, NSScrollView.self))
        rsbScroll(scrollView, to: RSB.maxScroll)
        rsbSpin(0.15)
        let bottom = try rsbHostBitmap(host)
        func hostDoor(_ door: some View) throws -> NSBitmapImageRep {
            let (w, h) = rsbMount(RSB.door(door), width: RSB.layout.sidebarRowWidth, height: RSB.layout.sidebarRowHeight)
            defer { w.contentView = nil; w.close() }
            return try rsbHostBitmap(h)
        }
        let reversi = try hostDoor(MiniGameReversiEntryButton {})
        let rummy = try hostDoor(MiniGameRummyEntryButton {})
        let fifth = RSB.duelTile(4, scrolled: RSB.maxScroll)
        let same = rsbMaxDifference(bottom, fifth, reversi, alone)
        print("[사이드바] 다섯째 자리 ↔ 아잉 뒤집기 문 단독: 최대 차 \(same)")
        #expect(same <= 40, "다섯째 자리에 아잉 뒤집기 문이 아닌 것이 그려졌다(최대 차 \(same))")
        // ★ 기준선: 다섯째 자리는 큐브 문 타일과는 **갈린다**(같으면 위 비교가 아무 아이콘이나 받아들이는 것이다).
        let neighbour = rsbMaxDifference(bottom, fifth, rummy, alone)
        #expect(neighbour > 60, "다섯째 자리가 큐브 문과 구별되지 않는다(최대 차 \(neighbour))")
    }
}
