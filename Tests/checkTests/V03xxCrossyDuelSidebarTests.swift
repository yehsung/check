import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 1:1 길건너 — 미니게임 창 사이드바 **일곱째 문**(CD/SPEC.md §9.5 #18 · §10.2 T `V03xxCrossyDuelSidebarTests`).
// 같이 하기 칸 202pt 그대로(줄 42/4, 창 888×470), 1:1 알까기가 여덟째로 붙어 줄 364(+꼬리 16), 끝 거리 178이다.
// 길건너 신청은 일곱째 줄까지만 최소로 굴린다. 마지막 알까기 문의 신청 굴림은 V03xxAlkkagiSidebarTests 가 잰다.
// ImageRenderer 는 ScrollView 안을 못 그리므로(MC:91) 굴림은 그림이 아니라 **스크롤 목표 id · 실제 NSScrollView 오프셋 값**으로 재고,
// 점은 테두리 없는 창에 붙인 실제 칸을 cacheDisplay 로 읽는다(orderFront 없음 — 화면에 안 뜨고 클릭을 가로채지 않는다).
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).

@MainActor
private enum CSB {
    static let layout = MiniGameWindowLayout.self
    static var windowHeight: CGFloat { layout.contentSize.height }
    static var duelRowsTop: CGFloat {
        layout.sidebarDuelGroupRect.minY + layout.sidebarGroupTitleHeight + layout.sidebarGroupTitleSpacing
    }
    static var viewportBottom: CGFloat { duelRowsTop + layout.sidebarDuelViewportHeight }
    static var maxScroll: CGFloat { layout.sidebarDuelRowsHeight + layout.sidebarDuelFadeHeight - layout.sidebarDuelViewportHeight }
    /// i 번째 문 줄 바닥이 칸 바닥에 닿을 만큼만 굴린 거리(`scrollTo(door, anchor: nil)` — 마지막 문이 아닐 때).
    static func revealScroll(_ index: Int) -> CGFloat {
        CGFloat(index + 1) * layout.sidebarRowHeight + CGFloat(index) * layout.sidebarRowSpacing - layout.sidebarDuelViewportHeight
    }
    static func duelTile(_ index: Int, scrolled: CGFloat = 0) -> CGRect {
        let rowTop = duelRowsTop + CGFloat(index) * (layout.sidebarRowHeight + layout.sidebarRowSpacing) - scrolled
        return CGRect(x: layout.sidebarPadding + 6, y: rowTop + (layout.sidebarRowHeight - layout.sidebarIconSize) / 2,
                      width: layout.sidebarIconSize, height: layout.sidebarIconSize)
    }
    static func sidebar(invites: MiniGameDuelInvites = MiniGameDuelInvites()) -> some View {
        MiniGameSidebar(selected: .flappy, isPlaying: false, isFrozen: false, invites: invites,
                        onSelect: { _ in }, onGomoku: {}, onChess: {}, onTetrisDuel: {}, onRummy: {}, onReversi: {}, onMahjong: {},
                        onCrossyDuel: {}, onAlkkagi: {}, clipsOverflowInsteadOfScroll: false)
            .frame(width: layout.sidebarWidth, height: windowHeight, alignment: .top)
            .background(CheckTheme.background)
    }
}

private enum CSBError: Error { case render }

@MainActor
private func csbSpin(_ seconds: Double = 0.05) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func csbFirstSubview<T: NSView>(of root: NSView, _ type: T.Type) -> T? {
    if let match = root as? T { return match }
    for child in root.subviews {
        if let match = csbFirstSubview(of: child, type) { return match }
    }
    return nil
}

/// 테두리 없는 창에 붙이기만 한다(orderFront 없음).
@MainActor
private func csbMount(_ view: some View) -> (NSWindow, NSHostingView<AnyView>) {
    let host = NSHostingView(rootView: AnyView(view))
    host.frame = NSRect(x: 0, y: 0, width: CSB.layout.sidebarWidth, height: CSB.windowHeight)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    csbSpin(0.15)
    host.layoutSubtreeIfNeeded()
    return (window, host)
}

@MainActor
private func csbHostBitmap(_ host: NSView) throws -> NSBitmapImageRep {
    host.layoutSubtreeIfNeeded()
    let size = host.bounds.size
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw CSBError.render }
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep
}

@MainActor
private func csbScrolled(_ scrollView: NSScrollView) -> CGFloat {
    let clip = scrollView.contentView
    guard let document = scrollView.documentView else { return 0 }
    return document.isFlipped ? clip.bounds.minY : document.frame.height - clip.bounds.maxY
}

/// 사각형(pt) 안에서 조건을 만족하는 픽셀 수.
private func csbInk(_ bitmap: NSBitmapImageRep, in rect: CGRect, _ predicate: (Int, Int, Int) -> Bool) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2) - 1)
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2) - 1)
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var count = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if predicate(Int(data[o]), Int(data[o + 1]), Int(data[o + 2])) { count += 1 }
        }
    }
    return count
}

/// 받은 신청 점(`CheckTheme.danger` ≈ (255,115,117)).
private func csbRed(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 200 && r > g + 70 && r > b + 70 }

@MainActor
@Suite(.serialized)
struct V03xxCrossyDuelSidebarTests {
    /// 없으면: 일곱째 문을 더하며 줄·창을 바꾸거나(대표가 고른 C 가 아니다) 문 목록 순서와 줄 순서가 갈려 저절로 굴리기가 엉뚱한 문으로
    /// 가거나, 칸·꼬리 산식이 어긋나 일곱째 문이 끝까지 내려도 흐림 밑에 깔린다.
    @Test
    func theSeventhDoorScrollsInsideTheSameViewport() {
        #expect(CSB.layout.sidebarRowHeight == 42 && CSB.layout.sidebarRowSpacing == 4)
        #expect(CSB.layout.contentSize == CGSize(width: 888, height: 470))
        #expect(CSB.layout.gameAreaSize == CGSize(width: 700, height: 470))
        #expect(CSB.layout.sidebarDuelRows == 8)
        #expect(MiniGameDuelDoor.allCases == [.gomoku, .chess, .tetris, .rummy, .reversi, .mahjong, .crossyDuel, .alkkagi])
        #expect(CSB.layout.sidebarDuelViewportHeight == 202, "같이 하기 칸은 그대로")
        #expect(CSB.layout.sidebarDuelRowsHeight == 364, "줄 여덟 = 8×42 + 7×4")
        #expect(CSB.maxScroll == 178)
        let lastRowTop = CSB.duelRowsTop + 7 * (CSB.layout.sidebarRowHeight + CSB.layout.sidebarRowSpacing)
        #expect(lastRowTop - CSB.maxScroll + CSB.layout.sidebarRowHeight == CSB.viewportBottom - CSB.layout.sidebarDuelFadeHeight,
                "끝까지 내리면 여덟째 알까기 문 바닥이 흐림 위에 딱 선다")
        // ★ 기준선: 일곱 문일 때의 끝 거리(132)와 갈린다.
        #expect(CSB.maxScroll - (CSB.layout.sidebarRowHeight + CSB.layout.sidebarRowSpacing) == 132)
    }

    /// 없으면: 1:1 길건너 신청이 와도 칸이 굴러갈 목표가 없거나(첨자가 다른 칸을 읽는다) 위쪽 문으로 굴러 일곱째 문 점을 못 본다.
    @Test
    func theScrollTargetForACrossyDuelInviteIsTheSeventhDoor() {
        let none = MiniGameDuelInvites()
        #expect(MiniGameDuelInvites.scrollTarget(from: nil, to: MiniGameDuelInvites(crossyDuel: true)) == .crossyDuel)
        // 가장 아래 새 점이 이긴다 — 마작·길건너가 함께 서면 길건너.
        #expect(MiniGameDuelInvites.scrollTarget(from: none, to: MiniGameDuelInvites(mahjong: true, crossyDuel: true)) == .crossyDuel)
        // ★ 기준선: 이미 서 있던 길건너 점 위로 마작이 새로 서면 마작이다(새로 선 점만 본다).
        let crossyOnly = MiniGameDuelInvites(crossyDuel: true)
        #expect(MiniGameDuelInvites.scrollTarget(from: crossyOnly, to: MiniGameDuelInvites(mahjong: true, crossyDuel: true)) == .mahjong)
        #expect(MiniGameDuelInvites.scrollTarget(from: crossyOnly, to: crossyOnly) == nil)
        #expect(MiniGameDuelDoor.allCases.filter { crossyOnly[$0] } == [.crossyDuel])
        #expect(!crossyOnly[.alkkagi], "길건너 신청 점이 1:1 알까기 문에도 섰다")
    }

    /// 없으면(결과): 칸 안 실제 ScrollView 의 내용이 일곱 줄 + 꼬리가 아니거나, 1:1 길건너 신청이 와도 일곱째 문이 접힘 아래에 남아 점을
    /// 못 본다. 기준선: 맨 위 문(오목) 신청은 굴리지 않고, 마작 신청은 마작 줄까지만 굴린다(끝까지가 아니다).
    @Test
    func aCrossyDuelInviteScrollsTheSeventhDoorAboveTheFade() throws {
        let (window, host) = csbMount(CSB.sidebar())
        defer { window.contentView = nil; window.close() }
        let scrollView = try #require(csbFirstSubview(of: host, NSScrollView.self), "같이 하기 칸에 스크롤 뷰가 없다")
        let document = try #require(scrollView.documentView)
        #expect(abs(document.frame.height - (364 + 16)) < 0.5, "스크롤 내용이 \(document.frame.height) 다 — 줄 여덟 + 꼬리가 아니다")
        #expect(csbScrolled(scrollView) < 0.5, "신청이 없는데 처음부터 굴러가 있다")
        // ★ 기준선: 맨 위에서는 일곱째 문 자리가 칸 바닥 아래(보이지 않음)다.
        #expect(CSB.duelTile(6).minY >= CSB.viewportBottom, "일곱째 문이 맨 위에서 이미 칸 안에 있다 — 스크롤할 까닭이 없다")
        func deliver(_ invites: MiniGameDuelInvites) {
            host.rootView = AnyView(CSB.sidebar(invites: invites))
            host.layoutSubtreeIfNeeded()
            csbSpin(0.3)
            host.layoutSubtreeIfNeeded()
        }
        deliver(MiniGameDuelInvites(gomoku: true))
        #expect(csbScrolled(scrollView) < 0.5, "보이는 문의 신청에 칸이 굴렀다(\(csbScrolled(scrollView)))")
        deliver(MiniGameDuelInvites(gomoku: true, mahjong: true))
        #expect(abs(csbScrolled(scrollView) - CSB.revealScroll(5)) < 0.5,
                "마작 신청이 마작 줄까지(\(CSB.revealScroll(5)))가 아니라 \(csbScrolled(scrollView)) 굴렀다")
        deliver(MiniGameDuelInvites(gomoku: true, mahjong: true, crossyDuel: true))
        #expect(abs(csbScrolled(scrollView) - CSB.revealScroll(6)) < 0.5,
                "1:1 길건너 신청이 일곱째 줄까지(\(CSB.revealScroll(6))) 굴러가지 않았다(\(csbScrolled(scrollView)))")
        let lit = try csbHostBitmap(host)
        let seventh = CSB.duelTile(6, scrolled: CSB.revealScroll(6)).insetBy(dx: -6, dy: -6)
        let sixth = CSB.duelTile(5, scrolled: CSB.revealScroll(6)).insetBy(dx: -6, dy: -6)
        #expect(seventh.maxY <= CSB.viewportBottom, "일곱째 문 자리가 칸 밖이다")
        let litSeventh = csbInk(lit, in: seventh, csbRed)
        print("[사이드바] 일곱째 문 점 \(litSeventh)px")
        #expect(litSeventh > 20, "1:1 길건너 신청이 있는데 일곱째 문에 점이 안 보인다")
        // 마작 점은 여섯째 문에 그대로 선다(두 점이 섞이지 않는다).
        #expect(csbInk(lit, in: sixth, csbRed) > 20, "마작 초대 점이 여섯째 문에서 사라졌다")
        // ★ 기준선: 길건너 신청을 거두면 일곱째 자리의 점이 사라진다(같은 감지기가 점 유무를 가른다).
        deliver(MiniGameDuelInvites(gomoku: true, mahjong: true))
        let unlit = try csbHostBitmap(host)
        let scrolledNow = csbScrolled(scrollView)
        #expect(csbInk(unlit, in: CSB.duelTile(6, scrolled: scrolledNow).insetBy(dx: -6, dy: -6), csbRed) == 0,
                "신청이 없는데 일곱째 문에 점이 남았다")
    }
}
