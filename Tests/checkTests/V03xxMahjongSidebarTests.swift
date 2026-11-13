import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 마작 — 미니게임 창 사이드바 **여섯째 문**(MJ/SPEC.md §5.8 확정 C — 리버시 카드 답 "C 스크롤로": 줄 42/4 · 창 888×470 ·
// 같이 하기 칸 202pt 그대로, 스크롤 내용만 226 → 272(+꼬리 16), 끝까지 내린 거리 40 → 86).
// 리버시 `V03xxReversiSidebarTests` 틀(산식 · 화면에 올리지 않는 창의 실제 ScrollView)을 여섯 문으로 늘린다.
// 1:1 길건너와 1:1 알까기가 마작 뒤에 붙었다. 여덟 줄 364(+꼬리 16), 끝 거리 178이다.
// 마작 신청은 리버시처럼 그 줄만 최소로 굴린다.
// 화면에 올리지 않는다 — 테두리 없는 창에 붙이기만 한다(orderFront 없음).
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).

@MainActor
private enum MSB {
    static let layout = MiniGameWindowLayout.self
    static var windowHeight: CGFloat { layout.contentSize.height }
    static var duelRowsTop: CGFloat {
        layout.sidebarDuelGroupRect.minY + layout.sidebarGroupTitleHeight + layout.sidebarGroupTitleSpacing
    }
    static var viewportBottom: CGFloat { duelRowsTop + layout.sidebarDuelViewportHeight }
    static var maxScroll: CGFloat { layout.sidebarDuelRowsHeight + layout.sidebarDuelFadeHeight - layout.sidebarDuelViewportHeight }
    /// 여섯째(아잉 마작) 문 초대가 오면 굴러가는 거리 — 그 줄 바닥이 칸 바닥에 닿을 만큼만(`scrollTo(door, anchor: nil)`, 마지막 문이 아니다).
    static var mahjongRevealScroll: CGFloat {
        6 * layout.sidebarRowHeight + 5 * layout.sidebarRowSpacing - layout.sidebarDuelViewportHeight
    }

    static func duelTile(_ index: Int, scrolled: CGFloat = 0) -> CGRect {
        let rowTop = duelRowsTop + CGFloat(index) * (layout.sidebarRowHeight + layout.sidebarRowSpacing) - scrolled
        return CGRect(x: layout.sidebarPadding + 6, y: rowTop + (layout.sidebarRowHeight - layout.sidebarIconSize) / 2,
                      width: layout.sidebarIconSize, height: layout.sidebarIconSize)
    }

    static func sidebar(invites: MiniGameDuelInvites = MiniGameDuelInvites()) -> some View {
        MiniGameSidebar(selected: .flappy, isPlaying: false, isFrozen: false, invites: invites,
                        onSelect: { _ in }, onGomoku: {}, onChess: {}, onTetrisDuel: {}, onRummy: {}, onReversi: {}, onMahjong: {}, onCrossyDuel: {}, onAlkkagi: {},
                        clipsOverflowInsteadOfScroll: false)
            .frame(width: layout.sidebarWidth, height: windowHeight, alignment: .top)
            .background(CheckTheme.background)
    }
}

private enum MSBError: Error { case render }

@MainActor
private func msbSpin(_ seconds: Double = 0.05) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func msbFirstSubview<T: NSView>(of root: NSView, _ type: T.Type) -> T? {
    if let match = root as? T { return match }
    for child in root.subviews {
        if let match = msbFirstSubview(of: child, type) { return match }
    }
    return nil
}

/// 테두리 없는 창에 붙이기만 한다(orderFront 없음 — 사용자 화면에 안 뜨고 클릭을 가로채지 않는다).
@MainActor
private func msbMount(_ view: some View) -> (NSWindow, NSHostingView<AnyView>) {
    let host = NSHostingView(rootView: AnyView(view))
    host.frame = NSRect(x: 0, y: 0, width: MSB.layout.sidebarWidth, height: MSB.windowHeight)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    msbSpin(0.15)
    host.layoutSubtreeIfNeeded()
    return (window, host)
}

@MainActor
private func msbHostBitmap(_ host: NSView) throws -> NSBitmapImageRep {
    host.layoutSubtreeIfNeeded()
    let size = host.bounds.size
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw MSBError.render }
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep
}

@MainActor
private func msbScrolled(_ scrollView: NSScrollView) -> CGFloat {
    let clip = scrollView.contentView
    guard let document = scrollView.documentView else { return 0 }
    return document.isFlipped ? clip.bounds.minY : document.frame.height - clip.bounds.maxY
}

@MainActor
private func msbScroll(_ scrollView: NSScrollView, to distance: CGFloat) {
    guard let document = scrollView.documentView else { return }
    let clip = scrollView.contentView
    let y = document.isFlipped ? distance : max(0, document.frame.height - clip.bounds.height - distance)
    clip.scroll(to: NSPoint(x: 0, y: y))
    scrollView.reflectScrolledClipView(clip)
}

/// 사각형(pt) 안에서 조건을 만족하는 픽셀 수와 그 상자(pt).
private func msbInk(_ bitmap: NSBitmapImageRep, in rect: CGRect, _ predicate: (Int, Int, Int) -> Bool) -> (count: Int, box: CGRect) {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return (0, .null) }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2) - 1)
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2) - 1)
    guard x0 <= x1, y0 <= y1 else { return (0, .null) }
    var count = 0
    var minY = Int.max, maxY = Int.min
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if predicate(Int(data[o]), Int(data[o + 1]), Int(data[o + 2])) {
                count += 1
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard count > 0 else { return (0, .null) }
    return (count, CGRect(x: rect.minX, y: Double(minY) / 2, width: rect.width, height: Double(maxY - minY + 1) / 2))
}

/// 아이콘 잉크 — 바탕(어두운 판)보다 밝은 픽셀(문마다 색이 달라 색 대신 밝기로 센다).
private func msbBright(_ r: Int, _ g: Int, _ b: Int) -> Bool { max(r, g, b) > 140 }
/// 받은 초대 점(`CheckTheme.danger` ≈ (255,115,117)).
private func msbRed(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 200 && r > g + 70 && r > b + 70 }

@MainActor
@Suite(.serialized)
struct V03xxMahjongSidebarTests {
    /// 없으면: 여섯째 문을 더하며 줄·창을 바꾸거나(대표가 고른 C 가 아니다) 칸·꼬리 산식이 어긋나 여섯째 문이 끝까지 내려도 흐림 밑에
    /// 깔린다. 미니게임 창 크기(888×470 · 게임 구역 700×470)는 그대로여야 한다(V0246 값).
    @Test
    func theSixthDoorScrollsInsideTheSameViewport() {
        #expect(MSB.layout.sidebarRowHeight == 42 && MSB.layout.sidebarRowSpacing == 4)
        #expect(MSB.layout.contentSize == CGSize(width: 888, height: 470))
        #expect(MSB.layout.gameAreaSize == CGSize(width: 700, height: 470))
        // 1:1 길건너가 일곱째(CD/SPEC.md §9.5 #18) — 마작은 여섯째 그대로다.
        #expect(MSB.layout.sidebarDuelRows == 8)
        #expect(MiniGameDuelDoor.allCases == [.gomoku, .chess, .tetris, .rummy, .reversi, .mahjong, .crossyDuel, .alkkagi])
        #expect(MiniGameDuelDoor.allCases.firstIndex(of: .mahjong) == 5, "마작이 여섯째 자리가 아니다")
        #expect(MSB.layout.sidebarDuelViewportHeight == 202, "같이 하기 칸은 그대로")
        #expect(MSB.layout.sidebarDuelRowsHeight == 364, "줄 여덟 = 8×42 + 7×4")
        #expect(MSB.layout.sidebarDuelFadeHeight == 16)
        #expect(MSB.maxScroll == 178)
        let sixthRowTop = MSB.duelRowsTop + 5 * (MSB.layout.sidebarRowHeight + MSB.layout.sidebarRowSpacing)
        // 마작 초대는 그 줄 바닥이 칸 바닥에 닿을 만큼만 굴린다(70) — 끝까지 내리면 여섯째 문은 흐림 위에 온전히 선다.
        #expect(MSB.mahjongRevealScroll == 70)
        #expect(sixthRowTop - MSB.mahjongRevealScroll + MSB.layout.sidebarRowHeight == MSB.viewportBottom)
        #expect(sixthRowTop - MSB.maxScroll + MSB.layout.sidebarRowHeight <= MSB.viewportBottom - MSB.layout.sidebarDuelFadeHeight,
                "끝까지 내리면 여섯째 문 바닥이 흐림 위에 선다")
        // ★ 기준선: 일곱 문일 때의 끝 거리(132)와 갈린다.
        #expect(MSB.maxScroll - (MSB.layout.sidebarRowHeight + MSB.layout.sidebarRowSpacing) == 132)
    }

    /// 없으면(결과): 칸 안 실제 ScrollView 의 내용이 여섯 줄 + 꼬리가 아니라 끝까지 내려도 여섯째 문(아잉 마작)이 안 보이거나 흐림 밑에 깔린다.
    @Test
    func theRealScrollViewReachesTheSixthDoorAboveTheFade() throws {
        let (window, host) = msbMount(MSB.sidebar())
        defer { window.contentView = nil; window.close() }
        let scrollView = try #require(msbFirstSubview(of: host, NSScrollView.self), "같이 하기 칸에 스크롤 뷰가 없다")
        let document = try #require(scrollView.documentView)
        #expect(abs(document.frame.height - (364 + 16)) < 0.5, "스크롤 내용이 \(document.frame.height) 다 — 줄 여덟 + 꼬리가 아니다")
        #expect(msbScrolled(scrollView) < 0.5, "초대가 없는데 처음부터 굴러가 있다")
        let top = try msbHostBitmap(host)
        // ★ 기준선: 맨 위에서는 여섯째 문 자리가 칸 바닥 아래(보이지 않음)다.
        #expect(MSB.duelTile(5).minY >= MSB.viewportBottom, "여섯째 문이 맨 위에서 이미 칸 안에 있다 — 스크롤할 까닭이 없다")
        msbScroll(scrollView, to: MSB.maxScroll)
        msbSpin(0.15)
        #expect(abs(msbScrolled(scrollView) - MSB.maxScroll) < 0.5, "끝까지 내렸는데 \(msbScrolled(scrollView)) 만 굴렀다")
        let bottom = try msbHostBitmap(host)
        let sixth = msbInk(bottom, in: MSB.duelTile(5, scrolled: MSB.maxScroll), msbBright)
        #expect(sixth.count > 20, "끝까지 내려도 여섯째 문(아잉 마작) 아이콘이 안 보인다")
        #expect(sixth.box.maxY <= MSB.viewportBottom - MSB.layout.sidebarDuelFadeHeight, "여섯째 문이 흐림 밑에 깔린다")
        let spot = MSB.duelTile(5, scrolled: MSB.maxScroll)
        #expect(msbInk(top, in: spot, msbBright).count != sixth.count, "맨 위 그림과 끝 그림의 여섯째 자리가 갈리지 않는다")
    }

    /// 없으면(결과): 아잉 마작 초대가 와도 여섯째 문은 접힘 아래에 있어 점을 못 본다. 기준선: 맨 위 문(오목) 신청은 굴리지 않는다.
    @Test
    func aMahjongInviteScrollsTheSixthDoorIntoView() throws {
        let (window, host) = msbMount(MSB.sidebar())
        defer { window.contentView = nil; window.close() }
        let scrollView = try #require(msbFirstSubview(of: host, NSScrollView.self))
        func deliver(_ invites: MiniGameDuelInvites) {
            host.rootView = AnyView(MSB.sidebar(invites: invites))
            host.layoutSubtreeIfNeeded()
            msbSpin(0.3)
            host.layoutSubtreeIfNeeded()
        }
        deliver(MiniGameDuelInvites(gomoku: true))
        #expect(msbScrolled(scrollView) < 0.5, "보이는 문의 신청에 칸이 굴렀다(\(msbScrolled(scrollView)))")
        deliver(MiniGameDuelInvites(gomoku: true, mahjong: true))
        // 뒤에 두 문이 있어 끝(178)까지가 아니라 마작 줄이 칸 안에 들어올 만큼(70)만 구른다.
        #expect(abs(msbScrolled(scrollView) - MSB.mahjongRevealScroll) < 0.5,
                "아잉 마작 초대가 왔는데 칸이 여섯째 문까지(70) 안 굴렀다(\(msbScrolled(scrollView)))")
        let lit = try msbHostBitmap(host)
        let sixth = MSB.duelTile(5, scrolled: MSB.mahjongRevealScroll).insetBy(dx: -6, dy: -6)
        let fifth = MSB.duelTile(4, scrolled: MSB.mahjongRevealScroll).insetBy(dx: -6, dy: -6)
        #expect(msbInk(lit, in: sixth, msbRed).count > 20, "아잉 마작 초대가 있는데 여섯째 문에 점이 안 보인다")
        #expect(msbInk(lit, in: fifth, msbRed).count == 0, "아잉 마작 초대 점이 리버시 문에 섰다")
        #expect(MiniGameDuelInvites.scrollTarget(from: nil, to: MiniGameDuelInvites(reversi: true, mahjong: true)) == .mahjong)
    }
}
