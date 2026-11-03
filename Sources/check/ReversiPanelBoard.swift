import SwiftUI
import CheckCore

// 아잉 뒤집기 — **판**(좌표계 · 그림 · 입력 · 3초 테두리 경고). 계약은 설계서 FLIP/SPEC.md §5.3.
//
// 이 파일이 지키는 약속:
//   · **방향 뒤집기가 없다 — 1행이 위, a열이 왼쪽**(DEC:12, V-01 `idx = row*8 + col`). 체스처럼 내 색을 아래로 돌리지 않는다.
//   · **둘 수 있는 칸은 내가 계산하지 않는다.** 1:1 판은 서버 `legal_moves`, AI 판은 로컬 규칙이 이미 `store.legalTargets` 에
//     들어 있고 판은 그것만 점으로 그린다(DEC:26 — 스토어 머리말 ⑦).
//   · **렌더 감지기 규칙**: 칸·격자·덮개·점은 전부 **중간 톤**(최대 채널 ≤ 234 · 최소 ≥ 56)이고 **돌만 극단**(가운데 0.96 / 0.10)이다.
//     그래서 "칸 가운데 50% 상자에 최대 ≥ 235 또는 최소 ≤ 55 픽셀이 있는가" 가 곧 "그 칸에 돌이 있는가" 다.
//     짙은 초록(최소 채널 ≤ 55)을 칸 색으로 쓰면 빈 칸이 돌로 세어져 돌 잉크 단언이 조용히 쓸모없어진다.
//   · **판 그림에 `.shadow` 를 쓰지 않는다**(ImageRenderer 가 첫 두 장을 다르게 굽는다) — 돌 그림자는 자체 타원이다.
//   · **뒤집기 애니메이션은 불투명도를 건드리지 않는다.** 가로 비율만 |cos| 로 줄였다 펴고 반에서 색을 바꾼다
//     (`ReversiFlipAnimation` — 순수 값). 돌 색이 늘 극단이라 감지기가 산다.
//   · **초 단위 값은 잎 뷰만 읽는다**(3초 테두리 경고). 판 그림은 매초 다시 그려지지 않는다.

// MARK: - 스냅샷 시계

/// 스냅샷 전용 "지금". 앱은 언제나 nil 이고 잎 뷰들은 `TimelineView` 의 시각을 쓴다. 렌더 시험이 이 값을 넣으면
/// 시계 링·뒤집기 프레임이 그 시각으로 **결정적**으로 그려진다(흐르는 시각을 재면 같은 화면이 매번 다르게 찍힌다).
private struct ReversiPreviewNowKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    var reversiPreviewNow: Date? {
        get { self[ReversiPreviewNowKey.self] }
        set { self[ReversiPreviewNowKey.self] = newValue }
    }
}

// MARK: - 판 좌표

/// 판 그림의 좌표계. 순수 값 — 클릭 위치 ↔ 칸 변환을 결정적으로 잰다.
/// 여백이 없다(`cell = side / 8`) — 608 은 8 로 나누어떨어져 칸이 76pt 정확이고 좌표 글자는 가장자리 칸 **안**에 그린다.
struct ReversiBoardGeometry: Equatable {
    let side: CGFloat

    var cell: CGFloat { side / 8 }

    /// 그 칸의 사각형. col 0 = a열(왼쪽), row 0 = 1행(**위**).
    func rect(col: Int, row: Int) -> CGRect {
        CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
    }

    func rect(idx: Int) -> CGRect { rect(col: idx % 8, row: idx / 8) }

    func center(idx: Int) -> CGPoint {
        let box = rect(idx: idx)
        return CGPoint(x: box.midX, y: box.midY)
    }

    /// 화면 위치가 든 칸(판 밖이면 nil). **반 칸 관용이 없다** — 칸 안이 아니면 아무 칸도 아니다.
    func idx(at location: CGPoint) -> Int? {
        guard location.x.isFinite, location.y.isFinite,
              location.x >= 0, location.y >= 0, location.x < side, location.y < side else { return nil }
        let col = min(7, Int(location.x / cell))
        let row = min(7, Int(location.y / cell))
        return row * 8 + col
    }
}

// MARK: - 판 그림

/// 8×8 판을 Canvas **한 장**으로 그린다. 입력을 받지 않는 순수 그림이다 — 탭·호버는 감싸는 쪽이 한다.
/// 그리는 순서(SPEC §5.3): ① 초록 칸 + 격자선 → ② 덮개(호버) → ③ 좌표 글자 → ④ 합법 수 점 → ⑤ 돌(뒤집히는 중이면 그 프레임) →
/// ⑥ 자동 착수 회색 점 → ⑦ 마지막 수 빨간 점(돌 위에만) → ⑧ 호버 미리보기 반투명 돌(합법 칸에서만) → 예시 표시(규칙 창 전용).
struct ReversiBoardView: View {
    let board: ReversiBoard
    let geometry: ReversiBoardGeometry
    /// 점을 찍을 칸(스토어 `legalTargets` 그대로 — 1:1 은 서버 목록, 내 차례만).
    var legalTargets: Set<Int> = []
    /// 마지막 **돌** 수의 칸(빨간 점). 패스는 돌이 아니다.
    var lastStoneIdx: Int? = nil
    /// 시간이 지나 자동으로 놓인 돌의 칸(회색 점).
    var autoStones: Set<Int> = []
    /// 마우스가 올라간 칸(옅은 덮개 — 입력이 있는 판에서만 온다).
    var hovered: Int? = nil
    /// 호버 미리보기 돌(합법 칸에서만 — 부르는 쪽이 거른다).
    var preview: (idx: Int, color: ReversiColor)? = nil
    /// 지금 뒤집히는 수와 그 프레임 시각. 기본 nil = 멈춘 판 = **이 값이 생기기 전과 같은 그림**이다.
    var flip: ReversiFlipAnimation? = nil
    var flipNow: Date? = nil
    /// 규칙 창 예시 표시: 이번 수에 뒤집힌 칸(고리).
    var flippedMarks: Set<Int> = []
    var showsCoordinates: Bool = true

    // 칸 — 중간 톤(82,148,107). 최소 채널 82 ≥ 56 · 최대 148 ≤ 234.
    static let feltColor = Color(red: 0.32, green: 0.58, blue: 0.42)
    // 격자선 — 중간 톤(61,112,79). 최소 61 ≥ 56(짙게 하면 줄이 돌로 세어진다).
    static let lineColor = Color(red: 0.24, green: 0.44, blue: 0.31)
    // 좌표 글자 — 중간 톤(178,217,184).
    static let coordinateColor = Color(red: 0.70, green: 0.85, blue: 0.72)
    // 돌 — **여기만 극단**이다.
    static let blackStone = Color(white: 0.10)
    static let blackStoneHighlight = Color(white: 0.30)
    static let whiteStone = Color(white: 0.96)
    static let whiteStoneShade = Color(white: 0.86)
    /// 돌 반지름(칸 비율).
    static let stoneRadiusRatio: CGFloat = 0.42
    /// 합법 수 점 — 반지름 0.15칸, accent 0.60(초록 위에서 (83,162,196) — 중간 톤).
    static let targetTint = CheckTheme.accent
    static let targetOpacity: Double = 0.60
    static let targetRadiusRatio: CGFloat = 0.15
    static let hoverOpacity: Double = 0.14
    /// 자동 착수 표시(오목 `autoStoneColor` 와 같은 0.62 회색). 흑돌 위에서는 밝고 백돌 위에서는 어둡다.
    static let autoStoneColor = Color(white: 0.62)
    /// 마지막 수 점(오목과 같은 빨강). 늘 돌 **위에만** 찍는다 — 빈칸에 찍으면 최대 채널 242 라 돌로 세어진다.
    static let lastMoveColor = Color(red: 0.95, green: 0.30, blue: 0.26)
    /// 미리보기 돌 불투명도(초록 위에서 중간 톤으로 떨어지는 값).
    static let previewOpacity: Double = 0.45

    var body: some View {
        Canvas { context, _ in
            draw(in: &context)
        }
        .frame(width: geometry.side, height: geometry.side)
    }

    private func draw(in context: inout GraphicsContext) {
        let g = geometry
        let side = g.side
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

        // ② 덮개(호버)
        if let hovered, (0..<64).contains(hovered) {
            context.fill(Path(g.rect(idx: hovered).insetBy(dx: 1, dy: 1)),
                         with: .color(Color.white.opacity(Self.hoverOpacity)))
        }

        // ③ 좌표(가장자리 칸 안쪽 — 테두리를 두지 않는다). 글자는 1행 칸의 오른쪽 위, 숫자는 a열 칸의 왼쪽 위.
        if showsCoordinates {
            let size = max(8, g.cell * 0.16)
            for col in 0..<8 {
                let box = g.rect(col: col, row: 0)
                let letter = String(UnicodeScalar(UInt8(97 + col)))
                context.draw(
                    Text(letter).font(.system(size: size, weight: .bold)).foregroundStyle(Self.coordinateColor),
                    at: CGPoint(x: box.maxX - size * 0.6, y: box.minY + size * 0.65), anchor: .center)
            }
            for row in 0..<8 {
                let box = g.rect(col: 0, row: row)
                context.draw(
                    Text("\(row + 1)").font(.system(size: size, weight: .bold)).foregroundStyle(Self.coordinateColor),
                    at: CGPoint(x: box.minX + size * 0.6, y: box.minY + size * 0.65), anchor: .center)
            }
        }

        // ④ 합법 수 점 — 빈 칸에만(돌이 있는 칸이 들어오면 무시한다).
        for idx in legalTargets where (0..<64).contains(idx) && board[idx] == nil {
            let c = g.center(idx: idx)
            let r = g.cell * Self.targetRadiusRatio
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(Self.targetTint.opacity(Self.targetOpacity)))
        }

        // ⑤ 돌 — 뒤집히는 중인 칸은 그 프레임의 색·가로 비율로.
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

        // ⑥ 자동 착수 회색 점 — 마지막 수 점보다 **먼저**, 반지름을 더 크게(둘이 겹쳐도 둘 다 보인다).
        for idx in autoStones where (0..<64).contains(idx) && board[idx] != nil {
            let c = g.center(idx: idx)
            let r = max(3, g.cell * 0.15)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(Self.autoStoneColor))
        }

        // ⑦ 마지막 수 빨간 점(돌 위에만)
        if let lastStoneIdx, (0..<64).contains(lastStoneIdx), board[lastStoneIdx] != nil {
            let c = g.center(idx: lastStoneIdx)
            let r = max(2.5, g.cell * 0.10)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(Self.lastMoveColor))
        }

        // ⑧ 호버 미리보기(빈 칸에서만)
        if let preview, (0..<64).contains(preview.idx), board[preview.idx] == nil {
            var layer = context
            layer.opacity = Self.previewOpacity
            Self.drawStone(&layer, at: g.center(idx: preview.idx), radius: radius, color: preview.color, xScale: 1)
        }

        // 예시 표시(규칙 창) — 뒤집힌 돌 둘레의 고리.
        for idx in flippedMarks where (0..<64).contains(idx) {
            let c = g.center(idx: idx)
            let r = radius + max(1.5, g.cell * 0.05)
            context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                           with: .color(CheckTheme.pending), lineWidth: max(1.5, g.cell * 0.07))
        }
    }

    /// 돌 하나. 그림자는 **자체 타원**(`.shadow` 아님). 가운데 색은 극단(흑 0.10 · 백 0.96)이다.
    /// `xScale` 은 뒤집히는 중의 가로 비율 — 불투명도는 바꾸지 않는다.
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

// MARK: - 입력이 있는 판

/// 대국 화면의 판. 탭·호버만 얹고 그림은 `ReversiBoardView` 를 그대로 쓴다(끌기 없음).
///
/// **조용히 삼키는 길은 하나뿐이다 — 판 밖.** 나머지 거절(내 차례 아님 · 보내는 중 · 이미 돌 · 뒤집을 돌 없음 · 끝난 판)은
/// 스토어 `place(_:)` 가 문구로 말한다 — 뭉친 무음 guard 가 오목에서 "눌렀는데 반응 없음" 의 원인이었다.
struct ReversiPlayBoard: View {
    let store: ReversiStore
    let match: ReversiMatchState

    @State private var hovered: Int?
    @Environment(\.reversiPreviewNow) private var previewNow

    private var geometry: ReversiBoardGeometry { ReversiBoardGeometry(side: ReversiWindowLayout.boardSide) }

    private var canPlace: Bool { match.isMyTurn && !store.isBusy }

    /// 지금 **이 판에서** 뒤집히는 수. 값이 `matchID` 를 들고 있으므로 다른 판의 애니메이션이 이 화면으로 새지 않는다.
    private var flip: ReversiFlipAnimation? {
        guard let flip = store.flip, flip.matchID == match.id else { return nil }
        return flip
    }

    var body: some View {
        let g = geometry
        let targets = store.legalTargets
        let preview: (idx: Int, color: ReversiColor)? = {
            guard canPlace, let hovered, targets.contains(hovered) else { return nil }
            return (hovered, match.myColor)
        }()
        // 프레임 상한은 **화면 주사율에서 온다**(1/60 을 박지 않는다 — 비배수 주사율 저더).
        // `paused: flip == nil` 이 배터리 계약이다. 입력(호버·탭·접근성)은 **TimelineView 밖**에 둔다.
        TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval(
            forRefreshRate: MiniGameFrameRateMonitor.shared.refreshHz), paused: flip == nil)) { context in
            ReversiBoardView(
                board: match.board, geometry: g, legalTargets: targets,
                lastStoneIdx: match.lastStoneIdx, autoStones: match.autoStones,
                hovered: canPlace ? hovered : nil, preview: preview,
                flip: flip, flipNow: previewNow ?? context.date)
        }
        // 내 차례 마지막 3초 — 판 안쪽 가장자리가 빨갛게 빛난다. 입력을 받지 않는다.
        .overlay { ReversiBoardTimeWarning(store: store) }
        .overlay(alignment: .topLeading) {
            // 자동으로 놓인 돌마다 투명한 호버 자리 + 설명 툴팁. 같은 사실을 상태 상자가 **글자로도** 말한다.
            ForEach(match.autoStones.sorted(), id: \.self) { idx in
                Color.clear
                    .frame(width: g.cell, height: g.cell)
                    .contentShape(Rectangle())
                    .checkTooltip(ReversiText.autoPlacedStoneHelp)
                    .position(g.center(idx: idx))
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let idx = g.idx(at: location)
                if hovered != idx { hovered = idx }
            case .ended:
                if hovered != nil { hovered = nil }
            }
        }
        .gesture(
            SpatialTapGesture().onEnded { value in
                // **조용해도 되는 길은 이 하나뿐이다** — 판 밖은 거절이 아니라 빈 곳을 누른 것이다.
                guard let idx = g.idx(at: value.location) else { return }
                // 나머지 거절은 스토어 한 곳이 문구로 말한다. 여기서 미리 걸러 조용히 삼키지 않는다.
                Task { await store.place(idx) }
            }
        )
        .onChange(of: match.id) { _, _ in hovered = nil }
        .onChange(of: match.moveCount) { _, _ in hovered = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ReversiText.boardAccessibility(counts: match.counts, turn: match.turn,
                                                           legalCount: targets.count))
    }
}

/// 입력 없는 판(결과·관전). 뒤집기 애니메이션은 판 id 로 거른다 — 결과 화면에서도 마지막 수가 뒤집히는 것이 보여야
/// 왜 끝났는지 안다.
struct ReversiStaticBoard: View {
    let store: ReversiStore
    let matchID: String
    let board: ReversiBoard
    var lastStoneIdx: Int?
    var autoStones: Set<Int> = []
    var turn: ReversiColor?

    @Environment(\.reversiPreviewNow) private var previewNow

    var body: some View {
        let flip = store.flip.flatMap { $0.matchID == matchID ? $0 : nil }
        TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval(
            forRefreshRate: MiniGameFrameRateMonitor.shared.refreshHz), paused: flip == nil)) { context in
            ReversiBoardView(
                board: board, geometry: ReversiBoardGeometry(side: ReversiWindowLayout.boardSide),
                lastStoneIdx: lastStoneIdx, autoStones: autoStones,
                flip: flip, flipNow: previewNow ?? context.date)
        }
        .frame(width: ReversiWindowLayout.boardSide, height: ReversiWindowLayout.boardSide)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ReversiText.boardAccessibility(counts: board.counts, turn: turn, legalCount: 0))
    }
}

/// 내 차례 마지막 3초의 판 테두리 빛 — **잎 뷰**. 판정·세기·그림은 코어(`GomokuTurnWarning` 숫자 함수 +
/// `ReversiTurnWarning.watchesMyClock` 짝) 한 곳이고, 여기는 시계를 읽어 넘기기만 한다.
/// **멈춘 TimelineView 는 마지막 그림을 들고 있으므로** 켜짐 판정을 본문에서 한 번 더 한다.
struct ReversiBoardTimeWarning: View {
    let store: ReversiStore
    @Environment(\.reversiPreviewNow) private var previewNow

    var body: some View {
        let watches = ReversiTurnWarning.watchesMyClock(store.match)
        TimelineView(.animation(minimumInterval: 0.2, paused: !store.isWindowVisible || !watches)) { context in
            let now = previewNow ?? context.date
            let remaining = ReversiTurnWarning.watchesMyClock(store.match) ? store.remainingSeconds(now: now) : nil
            if GomokuTurnWarning.isActive(remaining: remaining) {
                let intensity = GomokuTurnWarning.intensity(remaining: remaining)
                Canvas { canvas, size in
                    GomokuTurnWarning.drawEdgeGlow(into: &canvas, side: min(size.width, size.height), intensity: intensity)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
