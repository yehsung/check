import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// MARK: - v0.2.44: 잔디 호버 말풍선(근무·AI 토큰 잔디 셀에 즉시 뜨는 날짜·값 카드)
//
// 배경: 셀마다 `.help("9월 3일 · 4시간 12분")` 을 달아 두었지만 사용자 체감은 "간헐적으로만 뜨고 가독성이 없다"였다 —
// 시스템 툴팁은 1초 뒤에 뜨고 미세 이동에 사라지며 작은 회색 글씨다. 그래서 격자 전체의 호버 좌표로 셀을 풀어 자체 말풍선을
// 즉시 그린다. 이 파일이 지키는 것:
//  (1) 좌표 → 셀 순수 규칙(틈은 앞 셀에 귀속, 라벨·월 라벨·밖은 nil)
//  (2) 말풍선 배치 순수 규칙(월·화는 아래, 나머지는 위, 가로 클램프)
//  (3) 날짜 문구 "9월 3일 (목)" 와 종전 툴팁 형식 불변
//  (4) 렌더: 호버된 셀 위(또는 아래)에 어두운 카드 + 밝은 글씨 픽셀이 실제로 생긴다
//  (5) 소스 계약: 셀에 `.help(` 가 없고 격자에 onContinuousHover·accessibilityLabel 이 있다, 히트맵은 무관

private let cellPitch = ContributionGridView.cellSize + ContributionGridView.cellGap
private let gridOriginX = ContributionGridView.labelWidth + ContributionGridView.cellGap
private let gridOriginY = ContributionGridView.monthLabelHeight + ContributionGridView.cellGap

private func kstDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var c = DateComponents(); c.year = y; c.month = m; c.day = d
    return TeamWeeklyGoal.kstCalendar.date(from: c)!
}

// MARK: - (1) 좌표 → 셀

@Test
func hoverPointResolvesToTheCellUnderItAndGapsBelongToThePrecedingCell() {
    let weeks = 13
    // 첫 셀: 좌상단 · 중앙 · 오른쪽/아래 틈(gap) 안 → (0,0). 틈이 앞 셀에 귀속돼야 칸 사이를 지날 때 말풍선이 깜빡이지 않는다.
    #expect(ContributionGridView.cell(at: CGPoint(x: gridOriginX, y: gridOriginY), weeks: weeks) == .init(week: 0, weekday: 0))
    #expect(ContributionGridView.cell(at: CGPoint(x: gridOriginX + 8, y: gridOriginY + 8), weeks: weeks) == .init(week: 0, weekday: 0))
    #expect(ContributionGridView.cell(at: CGPoint(x: gridOriginX + ContributionGridView.cellSize + 1, y: gridOriginY + 8), weeks: weeks)
            == .init(week: 0, weekday: 0))
    #expect(ContributionGridView.cell(at: CGPoint(x: gridOriginX + 8, y: gridOriginY + ContributionGridView.cellSize + 1), weeks: weeks)
            == .init(week: 0, weekday: 0))
    // 두 번째 열의 첫 픽셀 → (1,0).
    #expect(ContributionGridView.cell(at: CGPoint(x: gridOriginX + cellPitch, y: gridOriginY), weeks: weeks) == .init(week: 1, weekday: 0))
    // 마지막 셀의 우하단 → (weeks−1, 6).
    let lastX = gridOriginX + CGFloat(weeks - 1) * cellPitch + ContributionGridView.cellSize - 0.5
    let lastY = gridOriginY + 6 * cellPitch + ContributionGridView.cellSize - 0.5
    #expect(ContributionGridView.cell(at: CGPoint(x: lastX, y: lastY), weeks: weeks) == .init(week: weeks - 1, weekday: 6))
    // 요일 라벨 영역 · 월 라벨 행 · 격자 오른쪽 밖 · 아래 밖 · 음수 → nil.
    #expect(ContributionGridView.cell(at: CGPoint(x: 5, y: gridOriginY + 8), weeks: weeks) == nil)
    #expect(ContributionGridView.cell(at: CGPoint(x: gridOriginX + 8, y: 3), weeks: weeks) == nil)
    #expect(ContributionGridView.cell(at: CGPoint(x: gridOriginX + CGFloat(weeks) * cellPitch + 1, y: gridOriginY + 8), weeks: weeks) == nil)
    #expect(ContributionGridView.cell(at: CGPoint(x: gridOriginX + 8, y: gridOriginY + 7 * cellPitch + 1), weeks: weeks) == nil)
    #expect(ContributionGridView.cell(at: CGPoint(x: -1, y: -1), weeks: weeks) == nil)
    #expect(ContributionGridView.cell(at: CGPoint(x: gridOriginX + 8, y: gridOriginY + 8), weeks: 0) == nil)
}

// MARK: - (2) 말풍선 배치

@Test
func bubbleSitsAboveTheCellExceptOnTheTopTwoRowsAndStaysInsideTheGrid() {
    let weeks = 13
    let size = CGSize(width: 120, height: 44)
    let totalWidth = gridOriginX + CGFloat(weeks) * ContributionGridView.cellSize + CGFloat(weeks - 1) * ContributionGridView.cellGap

    // 월·화(0·1)는 아래, 수~일(2~6)은 위.
    for weekday in 0...1 {
        let a = ContributionGridView.bubbleAnchor(week: 5, weekday: weekday, weeks: weeks, bubbleSize: size)
        #expect(a.above == false)
        let cellBottom = gridOriginY + CGFloat(weekday) * cellPitch + ContributionGridView.cellSize
        #expect(a.origin.y == cellBottom + ContributionGridView.bubbleGap)
    }
    for weekday in 2...6 {
        let a = ContributionGridView.bubbleAnchor(week: 5, weekday: weekday, weeks: weeks, bubbleSize: size)
        #expect(a.above == true)
        let cellTop = gridOriginY + CGFloat(weekday) * cellPitch
        #expect(a.origin.y == cellTop - ContributionGridView.bubbleGap - size.height)
    }
    // 중앙 열은 셀 중심 정렬.
    let mid = ContributionGridView.bubbleAnchor(week: 6, weekday: 4, weeks: weeks, bubbleSize: size)
    let midCenter = gridOriginX + 6 * cellPitch + ContributionGridView.cellSize / 2
    #expect(mid.origin.x == midCenter - size.width / 2)
    // 첫 열은 왼쪽 클램프, 마지막 열은 오른쪽 클램프.
    let first = ContributionGridView.bubbleAnchor(week: 0, weekday: 4, weeks: weeks, bubbleSize: size)
    #expect(first.origin.x == 0)
    let last = ContributionGridView.bubbleAnchor(week: weeks - 1, weekday: 4, weeks: weeks, bubbleSize: size)
    #expect(last.origin.x + size.width == totalWidth)
    // 말풍선이 격자보다 넓으면 0 에 붙인다(음수로 튀지 않는다).
    let huge = ContributionGridView.bubbleAnchor(week: 6, weekday: 4, weeks: weeks, bubbleSize: CGSize(width: 1_000, height: 44))
    #expect(huge.origin.x == 0)
}

// MARK: - (3) 날짜 문구 · 종전 툴팁 불변

@Test
func bubbleDateTextCarriesTheWeekdayAndTheOldTooltipFormatIsUntouched() {
    let weekStart = kstDate(2026, 8, 31)   // 월요일
    #expect(ContributionGridView.dateText(weekStart: weekStart, week: 0, weekday: 3) == "9월 3일 (목)")
    #expect(ContributionGridView.dateText(weekStart: weekStart, week: 0, weekday: 0) == "8월 31일 (월)")
    #expect(ContributionGridView.dateText(weekStart: weekStart, week: 1, weekday: 6) == "9월 13일 (일)")
    // 종전 툴팁(접근성 문구로 계속 쓴다)은 형식 그대로.
    #expect(ContributionGridView.tooltipText(weekStart: weekStart, week: 0, weekday: 3, valueText: "12,345,678 토큰") == "9월 3일 · 12,345,678 토큰")
}

// MARK: - (4) 렌더

private enum HoverRenderError: Error { case failed }

@MainActor
private func renderBitmap(_ view: some View, width: CGFloat = 292) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
        throw HoverRenderError.failed
    }
    return bitmap
}

private func savePNG(_ bitmap: NSBitmapImageRep, _ name: String) {
    let dir = "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad/agent-f"
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
}

/// 영역 안에서 predicate(r,g,b,a) 를 만족하는 픽셀 수. 좌표는 **pt**(스케일 2 라 픽셀은 ×2).
private func count(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>,
                   where predicate: (Int, Int, Int, Int) -> Bool) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 4 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(x.lowerBound * 2)), x1 = min(bitmap.pixelsWide - 1, Int(x.upperBound * 2))
    let y0 = max(0, Int(y.lowerBound * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(y.upperBound * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var n = 0
    for py in y0...y1 {
        for px in x0...x1 {
            let o = py * bpr + px * spp
            if predicate(Int(data[o]), Int(data[o + 1]), Int(data[o + 2]), Int(data[o + 3])) { n += 1 }
        }
    }
    return n
}

/// 말풍선 바탕(panelElevated ≈ (54,56,74), 불투명) — 격자 칸(accent 파랑)·라벨(반투명 회색)과 겹치지 않는 서명.
private func isCardPixel(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool {
    a >= 250 && abs(r - 54) <= 12 && abs(g - 56) <= 12 && abs(b - 74) <= 12
}
/// 말풍선 글씨(primaryText = 흰색 0.94, 카드 위라 불투명). 라벨 글씨는 투명 바탕 위 반투명이라 a < 250.
private func isInkPixel(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool {
    a >= 250 && min(r, min(g, b)) >= 215
}

@MainActor
private func hoverGrid(initialHovered: ContributionGridView.Cell?) -> ContributionGridView {
    let weeks = 13
    let full = Array(repeating: Array(repeating: WorkDailyGrid.fullDaySeconds, count: 7), count: weeks)
    return ContributionGridView(
        weeks: weeks, values: full, weekStart: kstDate(2026, 6, 8), isFuture: { _, _ in false },
        denominator: WorkDailyGrid.fullDaySeconds, valueText: WorkDailyGrid.tooltipValueText, initialHovered: initialHovered
    )
}

@MainActor
@Test
func hoveredCellDrawsAReadableBubbleAboveItAndTopRowsGetItBelow() throws {
    let weeks = 13
    let totalWidth = gridOriginX + CGFloat(weeks) * ContributionGridView.cellSize + CGFloat(weeks - 1) * ContributionGridView.cellGap
    let plain = try renderBitmap(hoverGrid(initialHovered: nil))
    let above = try renderBitmap(hoverGrid(initialHovered: .init(week: 5, weekday: 4)))
    let below = try renderBitmap(hoverGrid(initialHovered: .init(week: 5, weekday: 0)))
    savePNG(above, "hover-above.png")
    savePNG(below, "hover-below.png")

    // (5,4) 금요일: 셀 위쪽 띠에 카드와 글씨가 생긴다. 호버가 없으면 그 띠엔 둘 다 없다(칸은 파랑, 라벨은 반투명).
    let cellTop = gridOriginY + 4 * cellPitch
    let aboveBand = (cellTop - ContributionGridView.bubbleGap - 60)...(cellTop - ContributionGridView.bubbleGap)
    #expect(count(above, x: 0...totalWidth, y: aboveBand, where: isCardPixel) > 200)
    #expect(count(above, x: 0...totalWidth, y: aboveBand, where: isInkPixel) > 30)
    #expect(count(plain, x: 0...totalWidth, y: aboveBand, where: isCardPixel) == 0)
    #expect(count(plain, x: 0...totalWidth, y: aboveBand, where: isInkPixel) == 0)
    // 말풍선은 레이아웃에 참여하지 않는다 — 그림 크기가 같다.
    #expect(above.pixelsHigh == plain.pixelsHigh && above.pixelsWide == plain.pixelsWide)

    // (5,0) 월요일: 위에 두면 월 라벨·섹션 제목을 덮으므로 셀 아래쪽 띠에 생긴다. 위쪽 띠(월 라벨 행)엔 카드가 없다.
    let cellBottom = gridOriginY + ContributionGridView.cellSize
    let belowBand = (cellBottom + ContributionGridView.bubbleGap)...(cellBottom + ContributionGridView.bubbleGap + 60)
    #expect(count(below, x: 0...totalWidth, y: belowBand, where: isCardPixel) > 200)
    #expect(count(below, x: 0...totalWidth, y: belowBand, where: isInkPixel) > 30)
    #expect(count(below, x: 0...totalWidth, y: 0...(gridOriginY - 1), where: isCardPixel) == 0)
}

@MainActor
@Test
func bubbleViewRendersTwoLinesOnADarkCard() throws {
    let bitmap = try renderBitmap(ContributionCellBubble(title: "9월 3일 (목)", value: "12,345,678 토큰"), width: 200)
    let w = CGFloat(bitmap.pixelsWide) / 2, h = CGFloat(bitmap.pixelsHigh) / 2
    #expect(count(bitmap, x: 0...w, y: 0...h, where: isCardPixel) > 500)
    #expect(count(bitmap, x: 0...w, y: 0...h, where: isInkPixel) > 100)
    // 두 줄이라 한 줄 카드보다 높다(값 줄 13pt + 날짜 줄 11pt + 여백).
    #expect(h >= 36 && h <= 60)
}

// MARK: - (5) 소스 계약

@Test
func gridUsesItsOwnHoverBubbleInsteadOfSystemTooltips() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let text = try String(contentsOf: root.appendingPathComponent("Sources/check/CheckComponents.swift"), encoding: .utf8)
    let stripped = text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            guard let slash = line.range(of: "//") else { return String(line) }
            return String(line[line.startIndex..<slash.lowerBound])
        }
        .joined(separator: "\n")
    let gridStart = try #require(stripped.range(of: "struct ContributionGridView"))
    let gridEnd = try #require(stripped.range(of: "\nstruct ContributionCellBubble"))
    let grid = String(stripped[gridStart.lowerBound..<gridEnd.lowerBound])
    #expect(!grid.contains(".help("), "셀의 시스템 툴팁이 남아 있으면 자체 말풍선 1초 뒤에 회색 툴팁이 또 뜬다")
    #expect(grid.contains("onContinuousHover"))
    #expect(grid.contains("accessibilityLabel"))
    #expect(grid.contains("allowsHitTesting(false)"))
    // 히트맵은 이 변경과 무관하다 — 호버 코드가 스며들지 않았다.
    let heatmapStart = try #require(stripped.range(of: "struct WorkRhythmHeatmapGrid"))
    let heatmap = String(stripped[heatmapStart.lowerBound..<gridStart.lowerBound])
    #expect(!heatmap.contains("onContinuousHover"))
    #expect(!heatmap.contains("ContributionCellBubble"))
}
