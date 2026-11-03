import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 뒤집기 — 미니게임 창 사이드바의 다섯째 대결 문(FLIP/SPEC.md §4.6 #18 · §5.8 · §6.3 T 줄).
//
// 같이 하기 묶음이 다섯 줄이 되면 옛 줄(42 · 간격 4)로는 466 > 안쪽 442 라 다섯째 문이 창 밖으로 잘린다. 대표가 시안
// (A 창 높이 · B 같이 하기 허브 · C 스크롤)을 고르기 전 **임시 처리 D**(줄 40 · 간격 2 → 434)를 둔다. 대표가 시안을 고르면
// 이 파일의 숫자도 같이 바뀐다 — 출시 전 `grep -rn '임시(대표 시안' Sources Tests` 0건이 게이트다.
//
// 산식만 재면 다섯째 문이 **실제로 그려지는지** 모른다(SwiftUI 는 넘친 줄을 조용히 창 밖에 그린다). 그래서 사이드바를 창 높이(470)로
// 그려 같이 하기 묶음의 아이콘 타일 다섯이 모두 안쪽 바닥(456) 위에 잉크를 갖는지 재고, 옛 줄 높이만큼 밀어 그린 기준선에서는
// 다섯째가 바닥 아래로 잘리는 것을 같은 감지기로 본다(결과가 갈리는 기준선).

@MainActor
private enum RSB {
    static let layout = MiniGameWindowLayout.self
    static var windowHeight: CGFloat { layout.contentSize.height }
    /// 사이드바 안쪽 바닥(창 높이 − 위아래 여백). 이 아래에 잉크가 있으면 줄이 창 밖으로 넘친 것이다.
    static var innerBottom: CGFloat { windowHeight - layout.contentPadding }

    /// 줄 높이·간격을 주어진 값으로 둔 같이 하기 다섯 줄 사이드바의 세로 합(산식은 `sidebarGroupHeight` 와 같다).
    static func contentHeight(rowHeight: CGFloat, spacing: CGFloat, duelRows: Int) -> CGFloat {
        func group(_ rows: Int) -> CGFloat {
            layout.sidebarGroupTitleHeight + layout.sidebarGroupTitleSpacing
                + CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * spacing
        }
        return group(MiniGameKind.macCases.count) + layout.sidebarGroupSpacing + group(duelRows)
    }

    /// 같이 하기 묶음 i 번째 줄의 아이콘 타일 사각형(사이드바 좌표, pt).
    static func duelTile(_ index: Int) -> CGRect {
        let rowsTop = layout.sidebarDuelGroupRect.minY + layout.sidebarGroupTitleHeight + layout.sidebarGroupTitleSpacing
        let rowTop = rowsTop + CGFloat(index) * (layout.sidebarRowHeight + layout.sidebarRowSpacing)
        return CGRect(x: layout.sidebarPadding + 6, y: rowTop + (layout.sidebarRowHeight - layout.sidebarIconSize) / 2,
                      width: layout.sidebarIconSize, height: layout.sidebarIconSize)
    }

    static func sidebar(invites: MiniGameDuelInvites = MiniGameDuelInvites(), topShift: CGFloat = 0) -> some View {
        MiniGameSidebar(selected: .flappy, isPlaying: false, isFrozen: false, invites: invites,
                        onSelect: { _ in }, onGomoku: {}, onChess: {}, onTetrisDuel: {}, onRummy: {}, onReversi: {})
            .padding(.top, topShift)
            .frame(width: layout.sidebarWidth, height: windowHeight, alignment: .top)
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
    /// 없으면: 다섯째 문을 더하고 줄을 그대로 두면 사이드바가 466 으로 안쪽 442 를 넘어 다섯째 문이 창 밖으로 잘린다 —
    /// 산식 시험(V0246)만 고치면 숫자는 초록이어도 그 이유(임시 D)가 어디에도 안 남는다.
    @Test
    func theTemporaryCompressionFitsFiveDuelDoors() {
        // 임시(대표 시안 결정 전) — FLIP/SPEC.md §5.8
        #expect(RSB.layout.sidebarRowHeight == 40)
        #expect(RSB.layout.sidebarRowSpacing == 2)
        #expect(RSB.layout.sidebarDuelRows == 5)
        let inner = RSB.windowHeight - RSB.layout.contentPadding * 2
        #expect(inner == 442)
        #expect(RSB.layout.sidebarContentHeight == 434)
        #expect(RSB.layout.sidebarContentHeight <= inner)
        // 산식이 레이아웃 상수와 같은 값을 낸다(아래 기준선 산식이 헛돌지 않는다는 연결).
        #expect(RSB.contentHeight(rowHeight: 40, spacing: 2, duelRows: 5) == RSB.layout.sidebarContentHeight)
        // ★ 기준선: 옛 줄(42 · 4)로 다섯 줄이면 넘친다 — D 를 둔 이유.
        let old = RSB.contentHeight(rowHeight: 42, spacing: 4, duelRows: 5)
        #expect(old == 466 && old > inner)
        // 다섯째 타일까지 산식상 안쪽 바닥 위에 선다.
        #expect(RSB.duelTile(4).maxY <= RSB.innerBottom)
        // 줄이 눌렸어도 아이콘 타일(30)과 숨 쉴 자리가 남는다(V0246 의 "크게" 하한 40 그대로).
        #expect(RSB.layout.sidebarRowHeight >= 40 && RSB.layout.sidebarRowHeight - RSB.layout.sidebarIconSize >= 10)
    }

    /// 없으면(결과): 산식은 초록인데 다섯째 문이 실제로는 창 밖에 그려지거나(넘침), 아이콘 타일이 비어 있다.
    /// 기준선: 같은 사이드바를 옛 줄 높이로 늘어나는 만큼(466 − 434) 밀어 그리면 다섯째 문 잉크가 안쪽 바닥 아래로 내려간다.
    @Test
    func allFiveDuelTilesInkAboveTheInnerBottomAtWindowHeight() throws {
        let bitmap = try rsbBitmap(RSB.sidebar())
        rsbSave(bitmap, "minigame-sidebar-five-doors")
        #expect(bitmap.pixelsHigh == Int(RSB.windowHeight * 2), "사이드바를 창 높이로 그리지 못했다(\(bitmap.pixelsHigh)px)")
        for index in 0..<5 {
            let tile = RSB.duelTile(index)
            let ink = rsbInk(bitmap, in: tile, rsbGreen)
            print("[사이드바] 같이 하기 \(index + 1)번째 타일 \(tile) 초록 \(ink.count)px · 상자 \(ink.box)")
            #expect(ink.count > 20, "같이 하기 \(index + 1)번째 문의 아이콘이 안 그려진다(초록 \(ink.count)px)")
            #expect(ink.box.maxY <= RSB.innerBottom, "\(index + 1)번째 문 잉크가 안쪽 바닥(\(RSB.innerBottom)) 아래로 내려갔다")
        }
        let strip = CGRect(x: 0, y: RSB.innerBottom, width: RSB.layout.sidebarWidth, height: RSB.layout.contentPadding)
        let below = rsbInk(bitmap, in: strip, rsbGreen).count
        #expect(below == 0, "안쪽 바닥 아래에 문 잉크가 \(below)px 있다 — 줄이 창 밖으로 넘친다")

        // ★ 기준선(결과가 갈린다): 옛 줄(42 · 4)이 더하는 높이만큼 밀어 그린다.
        let overflow = RSB.contentHeight(rowHeight: 42, spacing: 4, duelRows: 5) - RSB.layout.sidebarContentHeight
        #expect(overflow == 32)
        let shifted = try rsbBitmap(RSB.sidebar(topShift: overflow))
        rsbSave(shifted, "minigame-sidebar-five-doors-baseline-42")
        let shiftedBelow = rsbInk(shifted, in: strip, rsbGreen).count
        print("[사이드바] 바닥 아래 초록: 임시 D \(below)px · 옛 줄 기준선 \(shiftedBelow)px")
        #expect(shiftedBelow > 20, "옛 줄 기준선에서도 바닥 아래가 비었다 — 감지기가 넘침을 못 본다")
        // 기준선에서도 넷째까지는 위에 남는다(다섯째만 잘린다 — 무엇이 잘리는지까지 갈린다).
        let fourth = RSB.duelTile(3).offsetBy(dx: 0, dy: overflow)
        #expect(rsbInk(shifted, in: fourth, rsbGreen).box.maxY <= RSB.innerBottom)
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

        let sidebar = try rsbBitmap(RSB.sidebar())
        let doors: [(String, NSBitmapImageRep)] = [
            ("오목", try rsbBitmap(RSB.door(MiniGameGomokuEntryButton {}))),
            ("체스", try rsbBitmap(RSB.door(MiniGameChessEntryButton {}))),
            ("테트리스", try rsbBitmap(RSB.door(MiniGameTetrisDuelEntryButton {}))),
            ("큐브", try rsbBitmap(RSB.door(MiniGameRummyEntryButton {}))),
            ("아잉 뒤집기", try rsbBitmap(RSB.door(MiniGameReversiEntryButton {}))),
        ]
        let alone = CGRect(x: 6, y: (RSB.layout.sidebarRowHeight - RSB.layout.sidebarIconSize) / 2,
                           width: RSB.layout.sidebarIconSize, height: RSB.layout.sidebarIconSize)
        for (index, door) in doors.enumerated() {
            let same = rsbMaxDifference(sidebar, RSB.duelTile(index), door.1, alone)
            print("[사이드바] \(index + 1)번째 자리 ↔ \(door.0) 문 단독: 최대 차 \(same)")
            #expect(same <= 40, "\(index + 1)번째 자리에 \(door.0) 문이 아닌 것이 그려졌다(최대 차 \(same))")
        }
        // ★ 기준선: 다섯째 자리는 큐브 문 타일과는 **갈린다**(같으면 위 비교가 아무 아이콘이나 받아들이는 것이다).
        let neighbour = rsbMaxDifference(sidebar, RSB.duelTile(4), doors[3].1, alone)
        #expect(neighbour > 60, "다섯째 자리가 큐브 문과 구별되지 않는다(최대 차 \(neighbour))")
    }

    /// 없으면(결과): 아잉 뒤집기 신청이 와도 다섯째 문에 점이 안 서거나(점 칸 누락), 엉뚱한 문(큐브)에 선다 — 메뉴바 점을 보고 들어온
    /// 사람이 어느 문을 눌러야 하는지 모른다.
    @Test
    func theInviteDotLightsOnlyTheReversiDoor() throws {
        let lit = try rsbBitmap(RSB.sidebar(invites: MiniGameDuelInvites(reversi: true)))
        let dark = try rsbBitmap(RSB.sidebar())
        rsbSave(lit, "minigame-sidebar-reversi-invite-dot")
        // 점은 타일 오른쪽 위 모서리에 3pt 밀려 선다 — 타일을 사방 6pt 넓혀 본다.
        let fifth = RSB.duelTile(4).insetBy(dx: -6, dy: -6)
        let fourth = RSB.duelTile(3).insetBy(dx: -6, dy: -6)
        let litFifth = rsbInk(lit, in: fifth, rsbRed).count
        let darkFifth = rsbInk(dark, in: fifth, rsbRed).count
        print("[사이드바] 다섯째 문 점: 신청 있음 \(litFifth)px · 없음 \(darkFifth)px")
        #expect(litFifth > 20, "아잉 뒤집기 신청이 있는데 다섯째 문에 점이 안 선다")
        // ★ 기준선: 신청이 없으면 점이 없다(한 값만 바꿨다).
        #expect(darkFifth == 0)
        #expect(rsbInk(lit, in: fourth, rsbRed).count == 0, "아잉 뒤집기 신청 점이 큐브 문에 섰다")
    }
}
