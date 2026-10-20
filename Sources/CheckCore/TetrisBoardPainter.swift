import Foundation
import SwiftUI

// v0.3.60 테트리스 1:1 — **판 그림 한 벌**(맥 대결 창 · 다음 폰 버전이 같이 쓴다). 순수 `GraphicsContext` 함수이고
// 상태·시계·뷰가 없다 — 부르는 쪽이 판(값)과 캔버스 크기를 넘긴다.
//
// ── 왜 솔로 잎 뷰의 그리기를 부르지 않고 여기 한 벌을 더 두는가 ─────────────────────────────────
// 솔로 `TetrisGameView`(맥)와 그 소스 계약은 **건드리지 않는다**(설계서 §4.2). 그 그리기 함수들은 잎 뷰의 private 이라
// 밖에서 부를 문이 없고, 문을 내려면 솔로 파일을 고쳐야 한다. 그래서 **같은 순서·같은 수치**를 여기 옮겨 적었다:
// 하늘 → 후광 → 우물 → 격자 → 버퍼 경계 → 굳은 칸 → 고스트 → 조각 → 홀드·넥스트. 수치(배치·색·불투명도)는 전부
// `TetrisLayout`·`TetrisPalette` 한 표에서 오므로 두 벌이 갈릴 자리는 "그리는 순서" 뿐이다.
// 대결이 더하는 것은 셋이다: ① 방해 줄 칸은 **회색**(`garbageMask` 로만 가른다 — 판 배열에는 `.i` 로 들어 있다),
// ② 우물 왼쪽 거터의 **들어올 방해 줄 미터**, ③ 상대 판을 작게 그리는 `drawMiniBoard`.
//
// ── blur 금지 ─────────────────────────────────────────────────────────────────────────────
// `addFilter`·`drawLayer` 를 쓰지 않는다(솔로와 같은 금지 — 60Hz 에서 캔버스를 흐리면 통합 GPU 에서 프레임이 깨진다).

/// 대결 전용 색. 조각 7색은 `TetrisPalette` 그대로다(솔로와 같은 판이어야 한다).
package enum TetrisDuelPalette {
    /// 방해 줄 칸(무채색 회색). **우물 위 3:1 이상**(무대 5종 × 하늘 위·아래 최악 합성에서 잰다 — 테스트가 되묻는다)이고,
    /// 조각 7색 어느 것과도 채널 최대 차 0.20 이상 벌어진다(조각끼리의 문턱과 같다). 회색이어야 하는 이유: 방해 줄은
    /// "내가 놓은 조각이 아니다" 를 한눈에 말해야 하고, 색이 있으면 그 색의 조각과 섞여 읽힌다.
    package static let garbageRGB = (r: 0.60, g: 0.62, b: 0.68)
    /// 들어올 방해 줄 미터(위험 빨강 — `CheckTheme.danger` 와 같은 값이다. 미터는 "곧 판이 올라온다" 는 경고다).
    package static let meterRGB = (r: 1.0, g: 0.45, b: 0.46)
    /// 상대 미니 판 바닥(불투명). 하늘이 없는 카드 위라 조각 대비의 기준을 이 한 색으로 고정한다.
    package static let miniWellRGB = (r: 0.04, g: 0.05, b: 0.09)

    package static var garbageColor: Color { Color(red: garbageRGB.r, green: garbageRGB.g, blue: garbageRGB.b) }
    package static var meterColor: Color { Color(red: meterRGB.r, green: meterRGB.g, blue: meterRGB.b) }
    package static var miniWellColor: Color { Color(red: miniWellRGB.r, green: miniWellRGB.g, blue: miniWellRGB.b) }
}

/// 상대 미니 판의 배치(셀 9pt — 설계서 "셀 8~9pt"). 순수 상수.
package enum TetrisMiniBoardLayout {
    package static let cell: CGFloat = 9
    /// 판 테두리 안쪽 여백(테두리 선이 칸을 덮지 않게).
    package static let inset: CGFloat = 2
    package static var boardSize: CGSize {
        CGSize(width: cell * CGFloat(TetrisGame.columns) + inset * 2,
               height: cell * CGFloat(TetrisGame.visibleRows) + inset * 2)
    }
}

package enum TetrisBoardPainter {
    /// 미터가 그리는 최대 줄 수(보이는 판 높이). 그 이상 쌓여도 미터는 꽉 찬 채다 — 숫자는 글자층이 말한다.
    package static let meterMaxLines = TetrisGame.visibleRows

    /// 미터의 논리 사각형(거터 = 왼쪽 열과 판 사이 8pt). 높이는 들어올 줄 수 × 셀, **판 바닥에서 위로** 자란다.
    package static func meterRect(pendingLines: Int) -> CGRect {
        let lines = min(max(0, pendingLines), meterMaxLines)
        let height = CGFloat(lines) * TetrisLayout.cell
        return CGRect(x: meterTrackRect.minX, y: TetrisLayout.boardBottomY - height,
                      width: meterTrackRect.width, height: height)
    }

    /// 미터 바탕(빈 미터 자리). 비어 있어도 아주 옅게 그려 "여기에 무언가 차오른다" 를 배울 수 있게 한다.
    package static var meterTrackRect: CGRect {
        // 거터 8pt 의 가운데 5pt(양옆 1.5pt 는 왼쪽 열 상자·우물 테두리와 붙지 않게 비운다).
        CGRect(x: TetrisLayout.boardX - TetrisLayout.gutter + 1.5, y: TetrisLayout.boardTopY,
               width: TetrisLayout.gutter - 3, height: TetrisLayout.boardBottomY - TetrisLayout.boardTopY)
    }

    /// 내 판 한 장(캔버스 전체). 솔로 잎 뷰의 순서·수치 그대로에 방해 줄 회색과 미터를 더한다.
    package static func drawGame(
        _ game: TetrisGame,
        into context: inout GraphicsContext,
        size: CGSize,
        reduceMotion: Bool = false
    ) {
        let t = MiniGameProjection(container: size, logicalSize: TetrisLayout.logicalSize)
        let full = CGRect(origin: .zero, size: size)
        let stage = MiniGameStage.forTetrisAdvance(game.advance)

        // 1) 하늘(캔버스 전체) · 2) 우물 뒤 후광 — 솔로와 같은 근거(능선 없음 · radialGradient 하나).
        MiniGameBackdrop.draw(into: &context, rect: full, stage: stage, scroll: 0,
                              terrain: false, reduceMotion: reduceMotion)
        let well = t.rect(TetrisLayout.wellRect)
        MiniGameEffects.glow(into: &context,
                             in: well.insetBy(dx: -well.width * 0.45, dy: -well.height * 0.12),
                             color: stage.glow, opacity: 0.16)

        // 3) 우물 바닥(조각-배경 대비의 기준값) · 격자 · 버퍼 경계.
        context.fill(Path(roundedRect: well, cornerRadius: 4 * t.scale),
                     with: .color(TetrisPalette.wellColor.opacity(TetrisPalette.wellOpacity)))
        drawGrid(&context, t: t)
        let boundary = t.rect(TetrisLayout.boardX, TetrisLayout.boardTopY, TetrisLayout.boardWidth, 1)
        context.fill(Path(boundary), with: .color(stage.structureEdge.opacity(0.45)))
        context.stroke(Path(roundedRect: well, cornerRadius: 4 * t.scale),
                       with: .color(stage.structureEdge.opacity(0.55)), lineWidth: 1)

        // 4) 굳은 칸. 방해 줄 칸은 **회색·윗변 띠 없음**(내가 놓은 조각과 갈린다). 버퍼행은 0.55.
        let bufferRow = TetrisGame.firstVisibleRow - 1
        for row in bufferRow..<TetrisGame.totalRows {
            for column in 0..<TetrisGame.columns {
                guard let piece = game.board[row][column] else { continue }
                let opacity = row == bufferRow ? 0.55 : 1
                if game.isGarbage(row: row, column: column) {
                    drawCell(&context, t: t, row: row, column: column,
                             color: TetrisDuelPalette.garbageColor, opacity: opacity, highlight: false)
                } else {
                    drawCell(&context, t: t, row: row, column: column,
                             color: TetrisPalette.color(piece), opacity: opacity)
                }
            }
        }

        // 5) 고스트 → 6) 조각(겹치는 자리에서는 실물이 위).
        if let ghost = game.ghost, let active = game.active, ghost.row != active.row {
            for cell in ghost.cells where cell.row >= bufferRow {
                drawCell(&context, t: t, row: cell.row, column: cell.column,
                         color: TetrisPalette.color(ghost.piece),
                         opacity: TetrisPalette.ghostOpacity, highlight: false)
            }
        }
        if let active = game.active {
            for cell in active.cells where cell.row >= bufferRow {
                drawCell(&context, t: t, row: cell.row, column: cell.column,
                         color: TetrisPalette.color(active.piece),
                         opacity: cell.row == bufferRow ? 0.55 : 1)
            }
        }

        // 7) 홀드 · 넥스트 5칸(솔로와 같은 상자).
        drawSlot(&context, t: t, rect: CGRect(x: TetrisLayout.outerMargin, y: TetrisLayout.boxY,
                                              width: TetrisLayout.columnWidth, height: TetrisLayout.boxHeight),
                 piece: game.heldPiece, stage: stage, emphasized: false, spent: game.holdUsed)
        for (index, piece) in game.next.prefix(TetrisGame.nextCount).enumerated() {
            drawSlot(&context, t: t, rect: CGRect(x: TetrisLayout.rightColumnX, y: TetrisLayout.slotY(index),
                                                  width: TetrisLayout.columnWidth, height: TetrisLayout.boxHeight),
                     piece: piece, stage: stage, emphasized: index == 0, spent: false)
        }

        // 8) 들어올 방해 줄 미터(우물 왼쪽 거터).
        drawMeter(&context, t: t, pendingLines: game.pendingGarbageLines)
    }

    /// 미터. 바탕 띠는 언제나, 빨간 막대는 들어올 줄이 있을 때만. 칸 경계마다 1pt 틈을 둬 "몇 줄인가" 가 세어진다.
    package static func drawMeter(_ context: inout GraphicsContext, t: MiniGameProjection, pendingLines: Int) {
        let track = t.rect(meterTrackRect)
        context.fill(Path(roundedRect: track, cornerRadius: 1.5 * t.scale), with: .color(.white.opacity(0.07)))
        let lines = min(max(0, pendingLines), meterMaxLines)
        guard lines > 0 else { return }
        let meter = meterRect(pendingLines: lines)
        for index in 0..<lines {
            let y = meter.maxY - CGFloat(index + 1) * TetrisLayout.cell
            let cell = CGRect(x: meter.minX, y: y, width: meter.width, height: TetrisLayout.cell).insetBy(dx: 0, dy: 0.5)
            context.fill(Path(roundedRect: t.rect(cell), cornerRadius: 1 * t.scale),
                         with: .color(TetrisDuelPalette.meterColor))
        }
    }

    /// 상대 판(20행 × 10칸, 행 0 = 맨 위)을 작게. 바닥은 불투명 한 색이고, 빈 판에도 격자가 보인다.
    package static func drawMiniBoard(_ cells: [[TetrisDuelCell]], into context: inout GraphicsContext, size: CGSize) {
        let cell = TetrisMiniBoardLayout.cell
        let inset = TetrisMiniBoardLayout.inset
        let frame = CGRect(origin: .zero, size: size)
        context.fill(Path(roundedRect: frame, cornerRadius: 4), with: .color(TetrisDuelPalette.miniWellColor))
        let line = GraphicsContext.Shading.color(.white.opacity(0.06))
        for column in 1..<TetrisGame.columns {
            let x = inset + CGFloat(column) * cell
            context.fill(Path(CGRect(x: x, y: inset, width: 0.5, height: cell * CGFloat(TetrisGame.visibleRows))),
                         with: line)
        }
        for row in 1..<TetrisGame.visibleRows {
            let y = inset + CGFloat(row) * cell
            context.fill(Path(CGRect(x: inset, y: y, width: cell * CGFloat(TetrisGame.columns), height: 0.5)),
                         with: line)
        }
        for (rowIndex, row) in cells.prefix(TetrisGame.visibleRows).enumerated() {
            for (columnIndex, value) in row.prefix(TetrisGame.columns).enumerated() {
                let color: Color
                switch value {
                case .empty: continue
                case .piece(let piece): color = TetrisPalette.color(piece)
                case .garbage: color = TetrisDuelPalette.garbageColor
                }
                let rect = CGRect(x: inset + CGFloat(columnIndex) * cell, y: inset + CGFloat(rowIndex) * cell,
                                  width: cell, height: cell).insetBy(dx: 0.5, dy: 0.5)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
        context.stroke(Path(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4),
                       with: .color(.white.opacity(0.16)), lineWidth: 1)
    }

    // MARK: - 조각(솔로 잎 뷰와 같은 수치)

    private static func drawGrid(_ context: inout GraphicsContext, t: MiniGameProjection) {
        let line = GraphicsContext.Shading.color(.white.opacity(0.055))
        for column in 1..<TetrisGame.columns {
            let x = TetrisLayout.boardX + CGFloat(column) * TetrisLayout.cell
            context.fill(Path(t.rect(x, TetrisLayout.bufferY, 1 / t.scale,
                                     TetrisLayout.boardBottomY - TetrisLayout.bufferY)), with: line)
        }
        for row in 1..<TetrisGame.visibleRows {
            let y = TetrisLayout.boardTopY + CGFloat(row) * TetrisLayout.cell
            context.fill(Path(t.rect(TetrisLayout.boardX, y, TetrisLayout.boardWidth, 1 / t.scale)), with: line)
        }
    }

    private static func drawCell(_ context: inout GraphicsContext, t: MiniGameProjection,
                                 row: Int, column: Int, color: Color, opacity: Double, highlight: Bool = true) {
        let logical = TetrisLayout.cellRect(row: row, column: column).insetBy(dx: 0.5, dy: 0.5)
        let rect = t.rect(logical)
        context.fill(Path(roundedRect: rect, cornerRadius: 1.5 * t.scale), with: .color(color.opacity(opacity)))
        guard highlight else { return }
        context.fill(Path(t.rect(logical.minX, logical.minY, logical.width, 2.5)),
                     with: .color(TetrisPalette.cellHighlight.opacity(opacity)))
    }

    private static func drawSlot(_ context: inout GraphicsContext, t: MiniGameProjection, rect: CGRect,
                                 piece: TetrisGame.Piece?, stage: MiniGameStage, emphasized: Bool, spent: Bool) {
        let box = t.rect(rect)
        context.fill(Path(roundedRect: box, cornerRadius: 6 * t.scale), with: .color(.white.opacity(0.05)))
        let border: Color = spent ? CheckTheme.danger.opacity(0.35)
            : (emphasized ? stage.glow.opacity(0.45) : CheckTheme.border)
        context.stroke(Path(roundedRect: box, cornerRadius: 6 * t.scale), with: .color(border), lineWidth: 1)
        guard let piece else { return }
        let cells = TetrisGame.shape(piece, .spawn)
        let minX = cells.map(\.dx).min() ?? 0
        let maxX = cells.map(\.dx).max() ?? 0
        let minY = cells.map(\.dy).min() ?? 0
        let maxY = cells.map(\.dy).max() ?? 0
        let width = CGFloat(maxX - minX + 1) * TetrisLayout.miniCell
        let height = CGFloat(maxY - minY + 1) * TetrisLayout.miniCell
        let originX = rect.midX - width / 2
        let originY = rect.midY - height / 2
        let alpha = spent ? TetrisPalette.spentOpacity : 1
        for cell in cells {
            let logical = CGRect(x: originX + CGFloat(cell.dx - minX) * TetrisLayout.miniCell,
                                 y: originY + CGFloat(cell.dy - minY) * TetrisLayout.miniCell,
                                 width: TetrisLayout.miniCell, height: TetrisLayout.miniCell)
                .insetBy(dx: 0.5, dy: 0.5)
            context.fill(Path(roundedRect: t.rect(logical), cornerRadius: 1.5 * t.scale),
                         with: .color(TetrisPalette.color(piece).opacity(alpha)))
        }
    }
}
