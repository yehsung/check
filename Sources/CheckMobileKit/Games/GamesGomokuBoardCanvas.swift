#if os(iOS)
import CheckCore
import SwiftUI

/// 15×15 판(또는 일부) 그림 — 맥 `GomokuBoardView`(Sources/check/GomokuPanel.swift)와 같은 그림·색이다. 입력은 받지 않는다.
/// 나무판 색은 라이트·다크와 무관하게 같다(판은 물건이다).
struct GamesGomokuBoardCanvas: View {
    let board: GomokuBoard
    let geometry: GomokuPhoneBoardGeometry
    var lastMove: GomokuPoint?
    var forbidden: [GomokuPoint: GomokuForbiddenReason] = [:]
    var autoPoints: Set<GomokuPoint> = []
    var marks: [GomokuPoint: GomokuPhoneRuleExample.Mark] = [:]
    var preview: (point: GomokuPoint, color: GomokuColor)?
    var showsCoordinates = true
    /// 끝난 판의 승리선 양 끝(`GomokuPhoneWinLine`) — 돌 위로 굵은 선을 긋는다.
    var winLine: (from: GomokuPoint, to: GomokuPoint)?

    static let woodLight = Color(red: 0.88, green: 0.73, blue: 0.49)
    static let woodDark = Color(red: 0.79, green: 0.62, blue: 0.38)
    static let lineColor = Color(red: 0.30, green: 0.21, blue: 0.12)
    static let forbiddenColor = Color(red: 0.87, green: 0.16, blue: 0.18)
    static let lastMoveColor = Color(red: 0.95, green: 0.30, blue: 0.26)
    static let autoStoneColor = Color(white: 0.62)
    /// 미리보기 돌을 두르는 고리(폰 전용 — 호버가 없어 "지금 고른 칸"이 더 또렷해야 한다).
    static let previewRing = Color(red: 0.10, green: 0.45, blue: 0.95)
    /// 승리선(판은 물건이라 외관과 무관하게 같은 색 — 마지막 수 점과 같은 붉은 계열로 "여기서 끝났다"를 잇는다).
    static let winLineColor = Color(red: 0.95, green: 0.30, blue: 0.26)

    var body: some View {
        Canvas { context, _ in draw(&context) }
            .frame(width: geometry.side, height: geometry.side)
    }

    private func draw(_ context: inout GraphicsContext) {
        let g = geometry
        let side = g.side
        context.fill(
            Path(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerRadius: side * 0.025, style: .continuous),
            with: .linearGradient(Gradient(colors: [Self.woodLight, Self.woodDark]), startPoint: .zero, endPoint: CGPoint(x: side, y: side))
        )
        var grid = Path()
        let far = g.inset + CGFloat(g.lines - 1) * g.cell
        for i in 0..<g.lines {
            let offset = g.inset + CGFloat(i) * g.cell
            grid.move(to: CGPoint(x: offset, y: g.inset))
            grid.addLine(to: CGPoint(x: offset, y: far))
            grid.move(to: CGPoint(x: g.inset, y: offset))
            grid.addLine(to: CGPoint(x: far, y: offset))
        }
        context.stroke(grid, with: .color(Self.lineColor.opacity(0.85)), lineWidth: max(0.8, side / 640))
        context.stroke(Path(CGRect(x: g.inset, y: g.inset, width: far - g.inset, height: far - g.inset)),
                       with: .color(Self.lineColor), lineWidth: max(1.2, side / 380))
        for star in GomokuPhoneBoardGeometry.starPoints where g.contains(star) {
            let c = g.location(of: star)
            let r = max(2, g.cell * 0.1)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Self.lineColor))
        }
        if showsCoordinates {
            let letters = Array("ABCDEFGHIJKLMNO")
            // 좌표 글자: 비평 "판 좌표 숫자가 작다" — 여백(6%) 안에서 가장 크게(369pt 판에서 약 9.7pt).
            let size = max(8, g.inset * 0.44)
            for i in 0..<g.lines {
                let offset = g.inset + CGFloat(i) * g.cell
                let column = g.originX + i
                if column < letters.count {
                    context.draw(Text(String(letters[column])).font(.system(size: size, weight: .semibold))
                        .foregroundStyle(Self.lineColor.opacity(0.8)),
                                 at: CGPoint(x: offset, y: side - g.inset * 0.38), anchor: .center)
                }
                let row = g.originY + g.lines - i
                context.draw(Text("\(row)").font(.system(size: size, weight: .semibold))
                    .foregroundStyle(Self.lineColor.opacity(0.8)),
                             at: CGPoint(x: g.inset * 0.4, y: offset), anchor: .center)
            }
        }
        let radius = g.cell * 0.46
        for y in g.originY..<(g.originY + g.lines) {
            for x in g.originX..<(g.originX + g.lines) {
                guard let point = GomokuPoint(x: x, y: y), let color = board[point] else { continue }
                Self.drawStone(&context, at: g.location(of: point), radius: radius, color: color, opacity: 1)
            }
        }
        for point in autoPoints where g.contains(point) && board[point] != nil {
            let c = g.location(of: point)
            let r = max(3, g.cell * 0.17)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Self.autoStoneColor))
        }
        if let lastMove, g.contains(lastMove), board[lastMove] != nil {
            let c = g.location(of: lastMove)
            let r = max(2.5, g.cell * 0.13)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Self.lastMoveColor))
        }
        if let winLine, g.contains(winLine.from), g.contains(winLine.to) {
            let a = g.location(of: winLine.from)
            let b = g.location(of: winLine.to)
            var line = Path()
            line.move(to: a)
            line.addLine(to: b)
            context.stroke(line, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: max(4, g.cell * 0.24), lineCap: .round))
            context.stroke(line, with: .color(Self.winLineColor), style: StrokeStyle(lineWidth: max(2.5, g.cell * 0.16), lineCap: .round))
        }
        if let preview, g.contains(preview.point), board[preview.point] == nil {
            let c = g.location(of: preview.point)
            Self.drawStone(&context, at: c, radius: radius, color: preview.color, opacity: 0.55)
            let ring = Path(ellipseIn: CGRect(x: c.x - radius - 2, y: c.y - radius - 2, width: (radius + 2) * 2, height: (radius + 2) * 2))
            context.stroke(ring, with: .color(Self.previewRing), style: StrokeStyle(lineWidth: max(1.5, g.cell * 0.09), dash: [3, 2]))
        }
        for (point, reason) in forbidden where g.contains(point) && board[point] == nil {
            Self.drawCross(&context, at: g.location(of: point), half: g.cell * 0.22, width: max(2, g.cell * 0.08),
                           color: reason == .budget ? CheckTheme.pending : Self.forbiddenColor)
        }
        for (point, mark) in marks where g.contains(point) {
            let c = g.location(of: point)
            switch mark {
            case .forbidden:
                Self.drawCross(&context, at: c, half: g.cell * 0.26, width: max(2, g.cell * 0.1), color: Self.forbiddenColor)
            case .pivot:
                Self.drawCross(&context, at: c, half: g.cell * 0.2, width: max(1.6, g.cell * 0.08), color: CheckTheme.pending)
            case .win, .legal:
                Self.drawStone(&context, at: c, radius: radius, color: .black, opacity: 0.5)
                let ring = Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
                context.stroke(ring, with: .color(mark == .win ? CheckTheme.working : CheckTheme.accent), lineWidth: max(2, g.cell * 0.1))
            }
        }
    }

    static func drawStone(_ context: inout GraphicsContext, at c: CGPoint, radius r: CGFloat, color: GomokuColor, opacity: Double) {
        var layer = context
        layer.opacity = opacity
        layer.fill(Path(ellipseIn: CGRect(x: c.x - r + r * 0.06, y: c.y - r + r * 0.14, width: r * 2, height: r * 2)),
                   with: .color(.black.opacity(0.25)))
        let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        let highlight = CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4)
        switch color {
        case .black:
            layer.fill(circle, with: .radialGradient(Gradient(colors: [Color(white: 0.45), Color(white: 0.05)]),
                                                     center: highlight, startRadius: 0, endRadius: r * 1.5))
        case .white:
            layer.fill(circle, with: .radialGradient(Gradient(colors: [Color(white: 1.0), Color(white: 0.80)]),
                                                     center: highlight, startRadius: 0, endRadius: r * 1.6))
            layer.stroke(circle, with: .color(.black.opacity(0.2)), lineWidth: 0.8)
        }
    }

    static func drawCross(_ context: inout GraphicsContext, at c: CGPoint, half: CGFloat, width: CGFloat, color: Color) {
        var cross = Path()
        cross.move(to: CGPoint(x: c.x - half, y: c.y - half))
        cross.addLine(to: CGPoint(x: c.x + half, y: c.y + half))
        cross.move(to: CGPoint(x: c.x + half, y: c.y - half))
        cross.addLine(to: CGPoint(x: c.x - half, y: c.y + half))
        context.stroke(cross, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

/// 흑 차례 금수 표시 계산을 판이 바뀔 때만 한다(맥 `GomokuForbiddenMemo`).
@MainActor
final class GamesGomokuForbiddenMemo {
    private var board: GomokuBoard?
    private var cached: [GomokuPoint: GomokuForbiddenReason] = [:]

    func points(for board: GomokuBoard) -> [GomokuPoint: GomokuForbiddenReason] {
        if self.board != board {
            cached = GomokuRules.forbiddenPoints(board: board)
            self.board = board
        }
        return cached
    }
}

/// 대국 판(탭 입력): **첫 탭은 미리보기 돌, 같은 칸을 다시 누르면 착수, 다른 칸은 미리보기 이동**.
/// 둘 수 없는 탭은 스토어 `place` 에 넘겨 거절 이유 한 줄을 남긴다(뷰가 조용히 삼키지 않는다 — 맥과 같은 규약).
struct GamesGomokuPlayBoard: View {
    let store: GomokuStore
    let match: GomokuMatchState
    let side: CGFloat
    let forbidden: [GomokuPoint: GomokuForbiddenReason]
    @Binding var preview: GomokuTapPreview
    /// 금수 자리를 눌렀다 — 상태줄이 그 이유를 1순위로 말한다.
    @Binding var focusedForbidden: GomokuForbiddenReason?

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        let geometry = GomokuPhoneBoardGeometry(side: side)
        let previewPoint = preview.visiblePoint(match: match, isBusy: store.isBusy, forbidden: forbidden)
        GamesGomokuBoardCanvas(
            board: match.board, geometry: geometry, lastMove: match.lastMove, forbidden: forbidden,
            autoPoints: match.autoPoints, preview: previewPoint.map { ($0, match.myColor) }
        )
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { value in
            handleTap(geometry.point(at: value.location))
        })
        .sensoryFeedback(.impact(weight: .medium), trigger: match.moveCount)
        .sensoryFeedback(.selection, trigger: previewPoint)
        .accessibilityElement(children: voiceOver ? .contain : .ignore)
        .accessibilityLabel(GomokuPhoneText.boardAccessibility(match, forbiddenCount: forbidden.count))
        .overlay {
            if voiceOver { cellElements(geometry: geometry, previewPoint: previewPoint) }
        }
    }

    private func handleTap(_ point: GomokuPoint?) {
        let outcome = preview.tap(point, match: match, isBusy: store.isBusy, forbidden: forbidden)
        switch outcome {
        case .none:
            return
        case .preview:
            focusedForbidden = nil
        case .place(let target):
            focusedForbidden = nil
            let seen = GomokuSeenTurn(match)
            Task { await store.place(target, seen: seen) }
        case .refuse(let target):
            focusedForbidden = forbidden[target]
            let seen = GomokuSeenTurn(match)
            Task { await store.place(target, seen: seen) }
        }
    }

    /// 보이스오버: 칸마다 요소("H8, 비어 있음"). 두 번 탭이 곧 미리보기 → 한 번 더 두 번 탭이 착수다.
    private func cellElements(geometry: GomokuPhoneBoardGeometry, previewPoint: GomokuPoint?) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<GomokuBoard.cellCount, id: \.self) { index in
                let point = GomokuPoint(x: index % GomokuBoard.size, y: index / GomokuBoard.size)!
                let center = geometry.location(of: point)
                Color.clear
                    .frame(width: geometry.cell, height: geometry.cell)
                    .position(center)
                    .accessibilityElement()
                    .accessibilityLabel(GomokuPhoneText.cellAccessibility(
                        point, stone: match.board[point], isLastMove: match.lastMove == point,
                        isAuto: match.autoPoints.contains(point), forbidden: forbidden[point], isPreview: previewPoint == point))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { handleTap(point) }
            }
        }
        .frame(width: geometry.side, height: geometry.side)
        .allowsHitTesting(false)
    }
}
#endif
