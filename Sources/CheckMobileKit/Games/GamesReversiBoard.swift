import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 뒤집기 **판**(판 갈래 2/4 — 대표 답 #d_DdwzmxPClGqk). 맥 `ReversiPanelBoard`(Sources/check — 폰 빌드에 안 들어간다)의
// 좌표계·그리는 순서·색을 옮기고, 입력만 폰 문법(한 칸 탭 · 보이스오버 칸 요소)으로 바꿨다.
//
// 지키는 약속(맥과 같다):
//  · **방향 뒤집기가 없다 — 1행이 위, a열이 왼쪽**(`idx = row*8 + col`). 체스처럼 내 색을 아래로 돌리지 않는다.
//  · **둘 수 있는 칸은 판이 계산하지 않는다.** 1:1 은 서버 `legal_moves`, 로봇 판은 로컬 규칙이 이미 코어 `legalTargets` 에 들어 있고
//    판은 그것만 점으로 그린다(코어 머리말 ⑦). 이 파일에 `ReversiRules` 가 나오지 않는다.
//  · **입력은 한 단이다**(코어 ⑧) — 칸 하나를 누르면 곧바로 `place`. 미리보기 단계가 없다(오목의 두 번 누르기와 다르다).
//    거절(내 차례 아님 · 보내는 중 · 이미 돌 · 뒤집을 돌 없음)은 **코어가 문구로 말한다** — 판이 미리 걸러 조용히 삼키지 않는다.
//    조용해도 되는 길은 판 밖 하나뿐이다.
//  · **뒤집기 애니메이션은 코어 값**(`ReversiFlipAnimation`)을 프레임마다 읽기만 한다. 불투명도를 건드리지 않고(이징으로 깎으면
//    밀려나기 전에 사라진다) 가로 비율만 |cos| 로 줄였다 편다. 애니메이션이 없으면 `TimelineView` 가 한 틱도 돌지 않는다(배터리).
//  · 판 그림에 `.shadow` 를 쓰지 않는다 — 돌 그림자는 자체 타원이다(판 바깥 그림자는 감싸는 화면의 몫).
//
// 아래 **판정**(좌표계 · 한 변 · 칸 보이스오버)은 `#if os(iOS)` 밖이다 — 폰 뷰는 맥 스위트가 못 본다.

// MARK: - 판 좌표 (순수)

/// 판 좌표계. 여백이 없다(`cell = side / 8`) — 좌표 글자는 가장자리 칸 **안**에 그린다.
package struct GamesReversiBoardGeometry: Equatable, Sendable {
    package let side: CGFloat

    package init(side: CGFloat) {
        self.side = side.isFinite ? max(0, side) : 0
    }

    package var cell: CGFloat { side / 8 }

    /// 그 칸의 사각형. col 0 = a열(왼쪽), row 0 = 1행(**위**).
    package func rect(idx: Int) -> CGRect {
        CGRect(x: CGFloat(idx % 8) * cell, y: CGFloat(idx / 8) * cell, width: cell, height: cell)
    }

    package func center(idx: Int) -> CGPoint {
        let box = rect(idx: idx)
        return CGPoint(x: box.midX, y: box.midY)
    }

    /// 손가락이 닿은 칸(판 밖이면 nil). **반 칸 관용이 없다** — 칸 안이 아니면 아무 칸도 아니다.
    package func idx(at location: CGPoint) -> Int? {
        guard cell > 0, location.x.isFinite, location.y.isFinite,
              location.x >= 0, location.y >= 0, location.x < side, location.y < side else { return nil }
        let col = min(7, Int(location.x / cell))
        let row = min(7, Int(location.y / cell))
        return row * 8 + col
    }
}

/// 판 한 변. 기본 글자에서는 **열 폭 그대로**(화면 폭 − 좌우 여백)다 — 판이 열보다 넓으면 같은 열의 카드가 전부 오른쪽으로
/// 넘친다(체스 실측 D1). 글자가 커지면 보이는 높이에 맞춰 줄인다: 큰 글자에서 두 카드가 높아져 판과 '내 차례 · 남은 초' 가
/// 한 화면에 안 들어갔다(오목 w15 medium 6 — 대국에서 가장 중요한 상태가 판보다 먼저다). 칸이 정수 pt 가 되게 8 의 배수로 내린다.
package enum GamesReversiBoardLayout {
    /// 판이 이보다 작아지지 않는다(열이 더 좁으면 열 폭).
    package static let minimumSide: CGFloat = 200

    package static func side(visible: CGSize, sideMargin: CGFloat, isLargeText: Bool, isAccessibilitySize: Bool) -> CGFloat {
        let column = max(0, visible.width - sideMargin * 2)
        // 첫 배치에서 `GeometryReader` 가 0 을 주는 한 틱 — 0 으로 그리면 판이 사라졌다 돌아온다. 그 틱은 바닥값으로 선다.
        guard column > 0 else { return minimumSide }
        var side = column
        if isLargeText, visible.height > 0 {
            let fraction: CGFloat = isAccessibilitySize ? 0.40 : 0.52
            side = min(side, (visible.height * fraction).rounded())
        }
        side = max(min(minimumSide, column), side)
        return max(8, (side / 8).rounded(.down) * 8)
    }
}

/// 칸 하나의 보이스오버(칸 이름 · 돌 · 둘 수 있는가). 판정은 코어 값만 읽는다.
package enum GamesReversiBoardCells {
    package static func label(idx: Int, board: ReversiBoard, legalTargets: Set<Int>,
                              lastStoneIdx: Int?, autoStones: Set<Int>) -> String {
        ReversiPhoneText.cellAccessibility(
            idx: idx, stone: board[idx], isLegal: legalTargets.contains(idx),
            isLast: lastStoneIdx == idx, isAuto: autoStones.contains(idx))
    }
}

#if os(iOS)

// MARK: - 판 그림

/// 8×8 판을 Canvas **한 장**으로 그린다. 입력을 받지 않는 순수 그림이다.
/// 그리는 순서(맥 §5.3): ① 초록 칸 + 격자선 + 화점 → ② 좌표 글자 → ③ 둘 수 있는 칸 점 → ④ 돌(뒤집히는 중이면 그 프레임) →
/// ⑤ 자동 착수 회색 점 → ⑥ 마지막 수 빨간 점(돌 위에만).
struct GamesReversiBoardCanvas: View {
    let board: ReversiBoard
    let geometry: GamesReversiBoardGeometry
    var legalTargets: Set<Int> = []
    var lastStoneIdx: Int?
    var autoStones: Set<Int> = []
    /// 지금 뒤집히는 수와 그 프레임 시각. nil = 멈춘 판.
    var flip: ReversiFlipAnimation?
    var flipNow: Date?

    // 색은 맥 판과 같다(두 플랫폼이 같은 판을 그린다). 칸 — 중간 톤 초록 · 돌만 극단.
    static let feltColor = Color(red: 0.32, green: 0.58, blue: 0.42)
    static let lineColor = Color(red: 0.24, green: 0.44, blue: 0.31)
    static let coordinateColor = Color(red: 0.70, green: 0.85, blue: 0.72)
    static let blackStone = Color(white: 0.10)
    static let blackStoneHighlight = Color(white: 0.30)
    static let whiteStone = Color(white: 0.96)
    static let whiteStoneShade = Color(white: 0.86)
    static let stoneRadiusRatio: CGFloat = 0.42
    /// 둘 수 있는 칸 점(반지름 0.15칸). 초록 위에서 읽히는 파랑 — 라이트·다크 같은 판이라 고정색이다.
    static let targetColor = Color(red: 0.36, green: 0.66, blue: 1.0)
    static let targetOpacity: Double = 0.70
    static let targetRadiusRatio: CGFloat = 0.15
    static let autoStoneColor = Color(white: 0.62)
    static let lastMoveColor = Color(red: 0.95, green: 0.30, blue: 0.26)

    var body: some View {
        Canvas { context, _ in draw(in: &context) }
            .frame(width: geometry.side, height: geometry.side)
    }

    private func draw(in context: inout GraphicsContext) {
        let g = geometry
        let side = g.side
        guard side > 0 else { return }
        let frame = CGRect(x: 0, y: 0, width: side, height: side)

        // ① 초록 칸 + 격자선 + 네 화점
        context.fill(Path(roundedRect: frame, cornerRadius: side * GomokuTurnWarning.cornerRatio, style: .continuous),
                     with: .color(Self.feltColor))
        var grid = Path()
        for i in 1..<8 {
            let offset = CGFloat(i) * g.cell
            grid.move(to: CGPoint(x: offset, y: 0))
            grid.addLine(to: CGPoint(x: offset, y: side))
            grid.move(to: CGPoint(x: 0, y: offset))
            grid.addLine(to: CGPoint(x: side, y: offset))
        }
        context.stroke(grid, with: .color(Self.lineColor), lineWidth: max(1, side / 400))
        for (x, y) in [(2, 2), (6, 2), (2, 6), (6, 6)] {
            let r = max(1.5, g.cell * 0.06)
            let c = CGPoint(x: CGFloat(x) * g.cell, y: CGFloat(y) * g.cell)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(Self.lineColor))
        }

        // ② 좌표(가장자리 칸 안쪽). 글자는 1행 칸의 오른쪽 위, 숫자는 a열 칸의 왼쪽 위.
        let size = max(7, g.cell * 0.17)
        for col in 0..<8 {
            let box = g.rect(idx: col)
            let letter = String(UnicodeScalar(UInt8(97 + col)))
            context.draw(Text(letter).font(.system(size: size, weight: .bold)).foregroundStyle(Self.coordinateColor),
                         at: CGPoint(x: box.maxX - size * 0.6, y: box.minY + size * 0.65), anchor: .center)
        }
        for row in 0..<8 {
            let box = g.rect(idx: row * 8)
            context.draw(Text("\(row + 1)").font(.system(size: size, weight: .bold)).foregroundStyle(Self.coordinateColor),
                         at: CGPoint(x: box.minX + size * 0.6, y: box.minY + size * 0.65), anchor: .center)
        }

        // ③ 둘 수 있는 칸 점 — 빈 칸에만.
        for idx in legalTargets where (0..<64).contains(idx) && board[idx] == nil {
            let c = g.center(idx: idx)
            let r = g.cell * Self.targetRadiusRatio
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(Self.targetColor.opacity(Self.targetOpacity)))
        }

        // ④ 돌 — 뒤집히는 중인 칸은 그 프레임의 색·가로 비율로.
        let radius = g.cell * Self.stoneRadiusRatio
        for idx in 0..<64 {
            guard let color = board[idx] else { continue }
            var shown = color
            var xScale: CGFloat = 1
            if let flip, let now = flipNow, let displayed = flip.displayedColor(idx: idx, now: now) {
                shown = displayed
                xScale = CGFloat(flip.xScale(idx: idx, now: now))
            }
            Self.drawStone(&context, at: g.center(idx: idx), radius: radius, color: shown, xScale: xScale)
        }

        // ⑤ 자동 착수 회색 점 — 마지막 수 점보다 먼저, 더 크게(둘이 겹쳐도 둘 다 보인다).
        for idx in autoStones where (0..<64).contains(idx) && board[idx] != nil {
            let c = g.center(idx: idx)
            let r = max(3, g.cell * 0.15)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(Self.autoStoneColor))
        }

        // ⑥ 마지막 수 빨간 점(돌 위에만)
        if let lastStoneIdx, (0..<64).contains(lastStoneIdx), board[lastStoneIdx] != nil {
            let c = g.center(idx: lastStoneIdx)
            let r = max(2.5, g.cell * 0.10)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(Self.lastMoveColor))
        }
    }

    /// 돌 하나. 그림자는 **자체 타원**(`.shadow` 아님). `xScale` 은 뒤집히는 중의 가로 비율 — 불투명도는 바꾸지 않는다.
    static func drawStone(_ context: inout GraphicsContext, at c: CGPoint, radius r: CGFloat,
                          color: ReversiColor, xScale: CGFloat) {
        let k = max(0, min(1, xScale.isNaN ? 1 : xScale))
        let rx = r * k
        guard rx > 0.2 else { return }
        let shadow = Path(ellipseIn: CGRect(x: c.x - rx + r * 0.05, y: c.y - r + r * 0.12, width: rx * 2, height: r * 2))
        context.fill(shadow, with: .color(.black.opacity(0.22)))
        let disc = Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - r, width: rx * 2, height: r * 2))
        switch color {
        case .black:
            context.fill(disc, with: .color(blackStone))
            let gloss = Path(ellipseIn: CGRect(x: c.x - rx * 0.55, y: c.y - r * 0.72, width: rx * 0.7, height: r * 0.45))
            context.fill(gloss, with: .color(blackStoneHighlight.opacity(0.55)))
        case .white:
            context.fill(disc, with: .color(whiteStone))
            let shade = Path(ellipseIn: CGRect(x: c.x - rx * 0.86, y: c.y - r * 0.2, width: rx * 1.72, height: r * 1.12))
            context.fill(shade, with: .color(whiteStoneShade.opacity(0.25)))
            context.stroke(disc, with: .color(.black.opacity(0.25)), lineWidth: max(0.8, r * 0.04))
        }
    }
}

// MARK: - 판 (뒤집기 프레임 · 입력 · 보이스오버)

/// 대국·결과 화면의 판 한 장. `onTap` 이 nil 이면 입력 없는 판(결과)이다.
///
/// ★ 입력(탭·보이스오버 칸)은 `TimelineView` **밖**이다 — 안에 두면 뒤집히는 틱마다 입력 층이 다시 만들어진다(맥 `ReversiPlayBoard` 와 같다).
/// ★ 뒤집기 프레임의 `now` 는 **스토어 시계**다(`store.clock()`) — 애니메이션 시작 시각이 그 시계로 찍혔다. `TimelineView` 는
///   다시 그리게 깨우는 펌프일 뿐이다(폰 체스 잎 뷰와 같은 까닭 — 두 시계를 섞으면 어긋남이 흐른 시간으로 계산된다).
struct GamesReversiBoard: View {
    let store: ReversiStore
    let matchID: String
    let board: ReversiBoard
    let side: CGFloat
    var legalTargets: Set<Int> = []
    var lastStoneIdx: Int?
    var autoStones: Set<Int> = []
    var turn: ReversiColor?
    /// 칸을 눌렀다(판 밖은 부르지 않는다). nil = 입력 없는 판.
    var onTap: ((Int) -> Void)?

    @State private var refreshHz = MiniGameFrameRate.baselineFPS
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    /// 지금 **이 판에서** 뒤집히는 수(값이 판 id 를 들고 있어 다른 판의 애니메이션이 새지 않는다).
    private var flip: ReversiFlipAnimation? {
        guard let flip = store.flip, flip.matchID == matchID else { return nil }
        return flip
    }

    var body: some View {
        let geometry = GamesReversiBoardGeometry(side: side)
        let flip = flip
        TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval(forRefreshRate: refreshHz),
                                paused: flip == nil)) { _ in
            GamesReversiBoardCanvas(board: board, geometry: geometry, legalTargets: legalTargets,
                                    lastStoneIdx: lastStoneIdx, autoStones: autoStones,
                                    flip: flip, flipNow: flip == nil ? nil : store.clock())
        }
        .frame(width: geometry.side, height: geometry.side)
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { value in
            // **조용해도 되는 길은 판 밖 하나뿐이다.** 나머지 거절은 코어 `place` 가 문구로 말한다.
            guard let onTap, let idx = geometry.idx(at: value.location) else { return }
            onTap(idx)
        }, including: onTap == nil ? .subviews : .all)
        .accessibilityElement(children: voiceOver ? .contain : .ignore)
        .accessibilityLabel(ReversiPhoneText.boardAccessibility(counts: board.counts, turn: turn,
                                                                legalCount: legalTargets.count))
        .overlay {
            if voiceOver { cellElements(geometry) }
        }
        .onAppear { refreshHz = GamesDisplay.maximumFramesPerSecond }
    }

    /// 보이스오버: 칸마다 요소("d3, 빈칸, 둘 수 있어요"). 두 번 탭이 곧 착수다(한 단 입력 — 코어 ⑧).
    private func cellElements(_ geometry: GamesReversiBoardGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<64, id: \.self) { idx in
                let element = Color.clear
                    .frame(width: geometry.cell, height: geometry.cell)
                    .position(geometry.center(idx: idx))
                    .accessibilityElement()
                    .accessibilityLabel(GamesReversiBoardCells.label(
                        idx: idx, board: board, legalTargets: legalTargets,
                        lastStoneIdx: lastStoneIdx, autoStones: autoStones))
                if let onTap {
                    element
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onTap(idx) }
                } else {
                    element
                }
            }
        }
        .frame(width: geometry.side, height: geometry.side)
        .allowsHitTesting(false)
    }
}

/// 내 차례 마지막 3초의 판 테두리 빛 — **잎 뷰**. 판정·세기·그림은 코어(`GomokuTurnWarning` 숫자 함수 + `ReversiTurnWarning.watchesMyClock`
/// 짝) 한 곳이고 여기는 스토어 시계로 남은 초를 읽어 넘기기만 한다. 멈춘 TimelineView 는 마지막 그림을 들고 있으므로 켜짐 판정을
/// 본문에서 한 번 더 한다. 탭·보이스오버 칸 요소를 가리지 않는다.
struct GamesReversiBoardTimeWarning: View {
    let store: ReversiStore

    var body: some View {
        let watches = ReversiTurnWarning.watchesMyClock(store.match)
        TimelineView(.animation(minimumInterval: 0.2, paused: !store.isWindowVisible || !watches)) { _ in
            let remaining = ReversiTurnWarning.watchesMyClock(store.match) ? store.remainingSeconds(now: store.clock()) : nil
            if GomokuTurnWarning.isActive(remaining: remaining) {
                let intensity = GomokuTurnWarning.intensity(remaining: remaining)
                Canvas { context, size in
                    GomokuTurnWarning.drawEdgeGlow(into: &context, side: min(size.width, size.height), intensity: intensity)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 돌 하나(판 그림과 같은 칠). `color` 가 nil 이면 반은 흑 · 반은 백(무작위 고르기 · 게임 기호와 같은 뜻).
struct GamesReversiStoneDot: View {
    let color: ReversiColor?
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let radius = min(canvasSize.width, canvasSize.height) / 2 * 0.84
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            if let color {
                GamesReversiBoardCanvas.drawStone(&context, at: center, radius: radius, color: color, xScale: 1)
            } else {
                GamesReversiBoardCanvas.drawStone(&context, at: center, radius: radius, color: .white, xScale: 1)
                var half = Path()
                half.addArc(center: center, radius: radius, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
                half.closeSubpath()
                context.fill(half, with: .color(GamesReversiBoardCanvas.blackStone))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#endif
