import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 1:1 알까기 v2 — 미니게임 창 사이드바 **여덟째 문**(alkkagi/v2 SPEC v1.1 §6 #4 · §7.2 T `V03xxAlkkagiSidebarTests`).
// 같이 하기 칸 202pt 그대로(줄 42/4, 창 888×470), 문 여덟 줄 364(+꼬리 16), 끝 거리 178 — 0.3.80 과 같은 틀이다(길건너 시험이 잰다).
// 바뀐 것: 문 이름 "1:1 알까기" · 아이콘 한 출처(`AlkkagiEntryIcon.resolved`) · 신청 점(이제 알까기도 신청이 온다 — 스토어가 걷은
// `visibleIncoming`). 알까기는 **마지막 문**이라 신청이 오면 꼬리까지(끝 거리) 굴러 흐림 위에 선다.
// ImageRenderer 는 ScrollView 안을 못 그리므로 굴림은 **스크롤 목표 id · 실제 NSScrollView 오프셋 값**으로 재고, 점은 테두리 없는 창에
// 붙인 실제 칸을 cacheDisplay 로 읽는다(orderFront 없음 — 화면에 안 뜨고 클릭을 가로채지 않는다).
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).

@MainActor
private enum ASB {
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

private enum ASBError: Error { case render }

@MainActor
private func asbSpin(_ seconds: Double = 0.05) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func asbFirstSubview<T: NSView>(of root: NSView, _ type: T.Type) -> T? {
    if let match = root as? T { return match }
    for child in root.subviews {
        if let match = asbFirstSubview(of: child, type) { return match }
    }
    return nil
}

/// 테두리 없는 창에 붙이기만 한다(orderFront 없음).
@MainActor
private func asbMount(_ view: some View) -> (NSWindow, NSHostingView<AnyView>) {
    let host = NSHostingView(rootView: AnyView(view))
    host.frame = NSRect(x: 0, y: 0, width: ASB.layout.sidebarWidth, height: ASB.windowHeight)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    asbSpin(0.15)
    host.layoutSubtreeIfNeeded()
    return (window, host)
}

@MainActor
private func asbHostBitmap(_ host: NSView) throws -> NSBitmapImageRep {
    host.layoutSubtreeIfNeeded()
    let size = host.bounds.size
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw ASBError.render }
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep
}

@MainActor
private func asbScrolled(_ scrollView: NSScrollView) -> CGFloat {
    let clip = scrollView.contentView
    guard let document = scrollView.documentView else { return 0 }
    return document.isFlipped ? clip.bounds.minY : document.frame.height - clip.bounds.maxY
}

/// 사각형(pt) 안에서 조건을 만족하는 픽셀 수.
private func asbInk(_ bitmap: NSBitmapImageRep, in rect: CGRect, _ predicate: (Int, Int, Int) -> Bool) -> Int {
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
private func asbRed(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 200 && r > g + 70 && r > b + 70 }

@MainActor
@Suite(.serialized)
struct V03xxAlkkagiSidebarTests {
    /// 없으면: 문 목록 · 줄 순서가 갈려 저절로 굴리기가 엉뚱한 문으로 가거나, 문 이름이 옛 '알까기' 이거나, 아이콘을 글자로 따로 적어
    /// 이 맥에 없는 기호면 문이 빈 칸으로 그려진다(없는 SF Symbol 은 경고 없이 빈 칸).
    @Test
    func theEighthDoorIsTheOneAlkkagiDoorWithAResolvedIcon() throws {
        #expect(MiniGameDuelDoor.allCases == [.gomoku, .chess, .tetris, .rummy, .reversi, .mahjong, .crossyDuel, .alkkagi])
        #expect(MiniGameDuelDoor.allCases.last == .alkkagi && MiniGameDuelDoor.allCases.count == 8)
        #expect(ASB.layout.sidebarDuelRows == 8 && ASB.layout.sidebarDuelRowsHeight == 364 && ASB.maxScroll == 178)
        #expect(MiniGameAlkkagiEntryButton.title == AlkkagiText.gameName && MiniGameAlkkagiEntryButton.title == "1:1 알까기")
        #expect(MiniGameAlkkagiEntryButton.help == AlkkagiText.sidebarHelp)
        // 아이콘: 한 출처 · 이 맥에서 실제로 풀린다 · 뒤집기 기호와 겹치지 않는다(DF#3).
        let icon = AlkkagiEntryIcon.resolved
        #expect(NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil, "없는 SF Symbol: \(icon)")
        #expect(icon == AlkkagiEntryIcon.symbol, "이 맥에서 \(AlkkagiEntryIcon.symbol) 이 안 풀려 대체 기호로 떨어졌다")
        #expect(icon != ReversiEntryIcon.symbol && icon != CrossyDuelEntryIcon.symbol)
        // ★ 기준선: 없는 이름은 정말 nil 이다(위 단언이 갈린다).
        #expect(NSImage(systemSymbolName: "circle.hexagongrid.fill.nope", accessibilityDescription: nil) == nil)
        // 렌더 문 줄 글자에 금지 낱말이 없다(대전 · 초대 · 참가비).
        for banned in ["대전", "초대", "참가비"] {
            #expect(!(MiniGameAlkkagiEntryButton.title + MiniGameAlkkagiEntryButton.help).contains(banned), "\(banned)")
        }
    }

    /// 없으면: 알까기 신청이 와도 칸이 굴러갈 목표가 없거나(첨자가 다른 칸을 읽는다) 위쪽 문으로 굴러 여덟째 문 점을 못 본다.
    @Test
    func theScrollTargetForAnAlkkagiInviteIsTheEighthDoor() {
        let none = MiniGameDuelInvites()
        #expect(MiniGameDuelInvites.scrollTarget(from: nil, to: MiniGameDuelInvites(alkkagi: true)) == .alkkagi)
        // 가장 아래 새 점이 이긴다 — 길건너 · 알까기가 함께 서면 알까기.
        #expect(MiniGameDuelInvites.scrollTarget(from: none, to: MiniGameDuelInvites(crossyDuel: true, alkkagi: true)) == .alkkagi)
        // ★ 기준선: 이미 서 있던 알까기 점 위로 길건너가 새로 서면 길건너다(새로 선 점만 본다).
        let alkkagiOnly = MiniGameDuelInvites(alkkagi: true)
        #expect(MiniGameDuelInvites.scrollTarget(from: alkkagiOnly, to: MiniGameDuelInvites(crossyDuel: true, alkkagi: true)) == .crossyDuel)
        #expect(MiniGameDuelInvites.scrollTarget(from: alkkagiOnly, to: alkkagiOnly) == nil)
        #expect(MiniGameDuelDoor.allCases.filter { alkkagiOnly[$0] } == [.alkkagi])
    }

    /// 없으면(결과): 1:1 알까기 신청이 와도 여덟째 문이 접힘 아래에 남아 점을 못 보거나, 점이 다른 문에 서거나, 신청을 거둬도 점이 남는다.
    /// 기준선: 맨 위 문(오목) 신청은 굴리지 않고, 길건너 신청은 일곱째 줄까지만 굴린다(끝까지가 아니다).
    @Test
    func anAlkkagiInviteScrollsTheEighthDoorAboveTheFade() throws {
        let (window, host) = asbMount(ASB.sidebar())
        defer { window.contentView = nil; window.close() }
        let scrollView = try #require(asbFirstSubview(of: host, NSScrollView.self), "같이 하기 칸에 스크롤 뷰가 없다")
        let document = try #require(scrollView.documentView)
        #expect(abs(document.frame.height - (364 + 16)) < 0.5, "스크롤 내용이 \(document.frame.height) 다 — 줄 여덟 + 꼬리가 아니다")
        #expect(asbScrolled(scrollView) < 0.5, "신청이 없는데 처음부터 굴러가 있다")
        #expect(ASB.duelTile(7).minY >= ASB.viewportBottom, "여덟째 문이 맨 위에서 이미 칸 안에 있다 — 스크롤할 까닭이 없다")
        func deliver(_ invites: MiniGameDuelInvites) {
            host.rootView = AnyView(ASB.sidebar(invites: invites))
            host.layoutSubtreeIfNeeded()
            asbSpin(0.3)
            host.layoutSubtreeIfNeeded()
        }
        deliver(MiniGameDuelInvites(gomoku: true))
        #expect(asbScrolled(scrollView) < 0.5, "보이는 문의 신청에 칸이 굴렀다(\(asbScrolled(scrollView)))")
        deliver(MiniGameDuelInvites(gomoku: true, crossyDuel: true))
        #expect(abs(asbScrolled(scrollView) - ASB.revealScroll(6)) < 0.5,
                "길건너 신청이 일곱째 줄까지(\(ASB.revealScroll(6)))가 아니라 \(asbScrolled(scrollView)) 굴렀다")
        deliver(MiniGameDuelInvites(gomoku: true, crossyDuel: true, alkkagi: true))
        #expect(abs(asbScrolled(scrollView) - ASB.maxScroll) < 0.5,
                "1:1 알까기 신청이 꼬리까지(\(ASB.maxScroll)) 굴러가지 않았다(\(asbScrolled(scrollView)))")
        let lit = try asbHostBitmap(host)
        let eighth = ASB.duelTile(7, scrolled: ASB.maxScroll).insetBy(dx: -6, dy: -6)
        let seventh = ASB.duelTile(6, scrolled: ASB.maxScroll).insetBy(dx: -6, dy: -6)
        #expect(eighth.maxY <= ASB.viewportBottom, "여덟째 문 자리가 칸 밖이다")
        let litEighth = asbInk(lit, in: eighth, asbRed)
        print("[사이드바] 여덟째 문 점 \(litEighth)px")
        #expect(litEighth > 20, "1:1 알까기 신청이 있는데 여덟째 문에 점이 안 보인다")
        #expect(asbInk(lit, in: seventh, asbRed) > 20, "길건너 신청 점이 일곱째 문에서 사라졌다")
        // ★ 기준선: 알까기 신청을 거두면 여덟째 자리의 점이 사라진다(같은 감지기가 점 유무를 가른다).
        deliver(MiniGameDuelInvites(gomoku: true, crossyDuel: true))
        let unlit = try asbHostBitmap(host)
        let scrolledNow = asbScrolled(scrollView)
        #expect(asbInk(unlit, in: ASB.duelTile(7, scrolled: scrolledNow).insetBy(dx: -6, dy: -6), asbRed) == 0,
                "신청이 없는데 여덟째 문에 점이 남았다")
    }
}
