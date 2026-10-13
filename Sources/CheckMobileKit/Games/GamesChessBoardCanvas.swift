import CheckCore
import SwiftUI

// 폰 체스 판 — 8×8 을 `Canvas` **한 장**으로 그리고, 움직이는 말은 `TimelineView` 가 프레임마다 다시 묻는다.
//
// ## 왜 처음부터 애니메이션인가
// 판을 멈춘 국면 하나로 그리면 **자동으로 순간이동**이다(맥 0.3.43 이 그랬고 사용자가 바로 고쳐 달라고 했다:
// "갑자기 바로바로 순간이동하고 말이 갑자기 바로바로 사라지고 하니까 따라가기가 ux가 너무 별로야").
// 나중에 끼우려면 그리기를 다시 짜야 하므로 **처음 만들 때** 세 겹으로 갈라 둔다.
//
// ## 수학은 여기에 없다
// 시각·이징·칸 셈은 전부 `CheckCore.ChessMoveFlight` 가 끝내 놓는다(플랫폼 분기 0건 — 맥과 **같은 숫자**다).
// 화면 좌표·뒤집기는 `ChessPhoneBoardGeometry` 가 쥔다. 이 파일이 하는 일은 **받은 숫자를 사각형으로 바꿔
// 그리는 것**뿐이고, 말 실루엣은 맥과 한 벌인 `CheckCore.ChessPieceArt` 다.
//
// ## 색 상수가 **렌더 테스트의 감지기**다 (맥 `ChessBoardView` 와 같은 규칙)
// **칸 색과 덮개(마지막 수·선택·체크·도착 점)는 전부 중간 톤**이고 **말만 극단**이다(최대 채널 ≥ 235 또는
// 최소 채널 ≤ 55). 그래서 "칸 가운데에 극단 픽셀이 있는가" 가 곧 "그 자리에 말이 있는가" 다 —
// 덮개 색을 극단으로 바꾸거나 날고 있는 말을 흐리게 그리면 **빈 칸이 말로 세어져** 단언이 조용히 쓸모없어진다.
// 판은 **물건**이라 라이트·다크와 무관하게 같은 색이다(오목 나무판과 같은 규약).

/// 입력을 받지 않는 **순수 그림**. 탭은 감싸는 `GamesChessBoard` 가 받는다.
///
/// 플랫폼 분기가 **없다** — 폰 화면이 쓰는 바로 이 뷰를 맥 스위트가 `ImageRenderer` 로 구워 잉크를 센다
/// (`CheckMobileKit` 의 절반이 `#if os(iOS)` 라 그 안에 두면 그림을 재는 길이 통째로 사라진다).
package struct GamesChessBoardCanvas: View {
    let position: ChessPosition?
    let geometry: ChessPhoneBoardGeometry
    var lastMove: (from: ChessSquare, to: ChessSquare)?
    /// 고른 말의 칸. **관전 판에서는 언제나 nil 이다**(§6 ⑨ — 감싸는 쪽이 끊는다).
    var selected: ChessSquare?
    /// 고른 말이 갈 수 있는 칸들. 관전 판에서는 언제나 빈 집합이다.
    var targets: Set<ChessSquare> = []
    /// 체크를 받은 쪽 왕의 칸(빨간 덮개).
    var checkSquare: ChessSquare?
    var showsCoordinates = true
    /// 지금 미끄러지는 중인 **한 장**. 기본 nil = 멈춘 국면 = **이 값이 생기기 전과 같은 그림**이다.
    var flight: ChessFlightFrame?

    // 칸 — 둘 다 중간 톤(최대 ≤ 204 · 최소 ≥ 71)이다.
    package static let lightSquare = Color(red: 0.80, green: 0.72, blue: 0.60)
    package static let darkSquare = Color(red: 0.44, green: 0.35, blue: 0.28)
    // 말 — **여기만 극단**이다.
    package static let whitePiece = Color(white: 0.96)
    package static let whitePieceEdge = Color(white: 0.10)
    package static let blackPiece = Color(white: 0.10)
    package static let blackPieceEdge = Color(white: 0.90)
    // 덮개 — 전부 중간 톤으로 떨어지는 불투명도를 골랐다(위 ★).
    package static let lastMoveTint = CheckTheme.pending
    package static let lastMoveOpacity: Double = 0.35
    package static let selectedTint = CheckTheme.accent
    package static let selectedOpacity: Double = 0.35
    package static let targetTint = CheckTheme.accent
    package static let targetOpacity: Double = 0.60
    package static let checkTint = CheckTheme.danger
    package static let checkOpacity: Double = 0.45

    package init(position: ChessPosition?,
                 geometry: ChessPhoneBoardGeometry,
                 lastMove: (from: ChessSquare, to: ChessSquare)? = nil,
                 selected: ChessSquare? = nil,
                 targets: Set<ChessSquare> = [],
                 checkSquare: ChessSquare? = nil,
                 showsCoordinates: Bool = true,
                 flight: ChessFlightFrame? = nil) {
        self.position = position
        self.geometry = geometry
        self.lastMove = lastMove
        self.selected = selected
        self.targets = targets
        self.checkSquare = checkSquare
        self.showsCoordinates = showsCoordinates
        self.flight = flight
    }

    package var body: some View {
        Canvas { context, _ in draw(in: &context) }
            .frame(width: geometry.side, height: geometry.side)
    }

    private func draw(in context: inout GraphicsContext) {
        let g = geometry

        // ① 칸 64개
        for index in 0..<64 {
            guard let square = ChessSquare(index: index) else { continue }
            context.fill(Path(g.rect(of: square)),
                         with: .color(square.isLightSquare ? Self.lightSquare : Self.darkSquare))
        }

        // ② 덮개 — 마지막 수 → 선택 → 체크 순(뒤가 위에 온다). 폰에는 호버가 없다.
        if let lastMove {
            for square in [lastMove.from, lastMove.to] {
                context.fill(Path(g.rect(of: square)),
                             with: .color(Self.lastMoveTint.opacity(Self.lastMoveOpacity)))
            }
        }
        if let selected {
            context.fill(Path(g.rect(of: selected)),
                         with: .color(Self.selectedTint.opacity(Self.selectedOpacity)))
        }
        if let checkSquare {
            context.fill(Path(g.rect(of: checkSquare)),
                         with: .color(Self.checkTint.opacity(Self.checkOpacity)))
        }

        // ③ 좌표(가장자리 칸 **안쪽** — 테두리를 두지 않는다)
        if showsCoordinates {
            let size = max(8, g.cell * 0.17)
            for file in 0..<8 {
                let rank = g.orientation == .white ? 0 : 7
                guard let square = ChessSquare(file: file, rank: rank) else { continue }
                let box = g.rect(of: square)
                let letter = String(UnicodeScalar(UInt8(97 + file)))
                context.draw(
                    Text(letter).font(.system(size: size, weight: .bold))
                        .foregroundStyle(square.isLightSquare ? Self.darkSquare : Self.lightSquare),
                    at: CGPoint(x: box.maxX - size * 0.55, y: box.maxY - size * 0.6), anchor: .center)
            }
            for rank in 0..<8 {
                let file = g.orientation == .white ? 0 : 7
                guard let square = ChessSquare(file: file, rank: rank) else { continue }
                let box = g.rect(of: square)
                context.draw(
                    Text("\(rank + 1)").font(.system(size: size, weight: .bold))
                        .foregroundStyle(square.isLightSquare ? Self.darkSquare : Self.lightSquare),
                    at: CGPoint(x: box.minX + size * 0.6, y: box.minY + size * 0.6), anchor: .center)
            }
        }

        // ④ 갈 수 있는 칸 — 빈 칸은 점, 잡는 칸은 고리(점을 말 위에 찍으면 무엇을 잡는지 가린다).
        for target in targets {
            let box = g.rect(of: target)
            if position?[target] != nil {
                let inset = g.cell * 0.07
                context.stroke(Path(ellipseIn: box.insetBy(dx: inset, dy: inset)),
                               with: .color(Self.targetTint.opacity(Self.targetOpacity)),
                               lineWidth: g.cell * 0.09)
            } else {
                let r = g.cell * 0.15
                context.fill(
                    Path(ellipseIn: CGRect(x: box.midX - r, y: box.midY - r, width: r * 2, height: r * 2)),
                    with: .color(Self.targetTint.opacity(Self.targetOpacity)))
            }
        }

        // ⑤ 말 — 세 겹(+끌어 놓은 말 한 겹)으로 **갈라서** 그린다. 한 겹이라도 빠지면 사용자가 말한 증상 셋 중
        //    하나가 그대로 돌아온다.
        guard let position else { return }

        // ⑤a 멈춘 말 — 덮개 위(덮개가 말을 가리면 무엇이 서 있는지 모른다).
        for index in 0..<64 {
            guard let square = ChessSquare(index: index), let piece = position[square] else { continue }
            // ★ 날고 있는 말의 **도착** 칸은 뺀다. `position` 은 이미 수를 둔 뒤의 배치라, 안 빼면 같은 말이
            //   도착 칸과 궤적 위에 **둘로** 보인다(캐슬링이면 셋·넷).
            if flight?.hidden.contains(square) == true { continue }
            // 끌어 놓아 이미 도착해 있는 말은 여기서 건너뛰고 **맨 위**에 그린다(⑤d).
            if square == flight?.landed { continue }
            draw(piece, in: g.rect(of: square), cell: g.cell, into: &context)
        }

        // ⑤b 판에서 빠지는 말 — 멈춘 말 **위**, 날고 있는 말 **아래**.
        //
        // 잡힌 말은 `position` 에 이미 없어서 ⑤a 가 한 번도 그리지 않는다. 그 말이 밀려나는 0.22초가
        // 사용자가 "말이 갑자기 사라진다" 라고 말한 그 자리다 — 여기가 비면 고치려던 증상으로 되돌아간다.
        if let leaving = flight?.leaving {
            let shift = g.offset(fileDelta: leaving.fileOffset, rankDelta: leaving.rankOffset)
            let box = g.scaled(g.rect(of: leaving.square).offsetBy(dx: shift.width, dy: shift.height),
                               by: leaving.scale)
            // ★★ `GraphicsContext` 는 **값**이다 — 불투명도는 **사본**에 걸어야 한다. 원본에 걸면 그 뒤에
            //   그리는 ⑤c(날고 있는 말)까지 같이 흐려져서 **잡는 수마다 잡은 말이 도착하며 투명해진다**
            //   (증상이 잡힌 말에서 잡은 말로 옮겨갈 뿐이다). 맥에서 이 뮤테이션을 넣었을 때 48건이 전부
            //   초록이었다 — 그래서 이 한 장을 재는 시험을 폰에도 뒀다
            //   (`theFadingCapturedPieceDoesNotFadeTheFlyingPieceWithIt`).
            var sub = context
            sub.opacity = leaving.opacity
            draw(leaving.piece, in: box, cell: g.cell, into: &sub)
        }

        // ⑤c 날고 있는 말 — **맨 위**, 배열 순서대로(뒤가 위에 온다 → 캐슬링에서 왕이 룩 위다).
        // 지나가는 칸의 말을 덮으므로 나이트가 말을 **뛰어넘는 것**이 보인다.
        for moving in flight?.moving ?? [] {
            draw(moving.piece, in: g.rect(from: moving.from, to: moving.to, t: moving.t),
                 cell: g.cell, into: &context)
        }

        // ⑤d 끌어 놓아 **이미 도착해 있는** 말 — 잡힌 말(⑤b)과 캐슬링의 룩(⑤c)보다 위.
        // 폰은 아직 끌어서 두지 않으므로(탭 2단) `landed` 는 늘 nil 이지만, 프레임이 그 칸을 실어 보내는 한
        // 여기서 받아야 한다 — 안 받으면 폰에 끌기가 들어오는 날 밀려나는 잡힌 말이 잡은 말 **위에** 얹힌다.
        if let landed = flight?.landed, let piece = position[landed] {
            draw(piece, in: g.rect(of: landed), cell: g.cell, into: &context)
        }
    }

    /// 사각형 하나에 말 하나. 실루엣은 맥과 한 벌(`CheckCore.ChessPieceArt`)이다.
    ///
    /// ★ 색은 **극단 그대로**다. 날고 있는 말을 중간 톤으로 흐리면 "말이 두 칸 사이에 있다" 를 재는 단언이
    ///   통째로 공허해진다 — 날고 있어도 말은 말이다.
    /// ★ `.shadow` 를 쓰지 않는다 — `ImageRenderer` 가 그림자가 있으면 첫 두 장을 다르게 구워 그림 비교가
    ///   호출 순서에 따라 빨개진다.
    private func draw(_ piece: ChessPiece, in box: CGRect, cell: CGFloat,
                      into context: inout GraphicsContext) {
        let path = ChessPieceArt.path(for: piece.kind, in: box)
        context.fill(path, with: .color(piece.color == .white ? Self.whitePiece : Self.blackPiece))
        context.stroke(path,
                       with: .color(piece.color == .white ? Self.whitePieceEdge : Self.blackPieceEdge),
                       lineWidth: max(0.8, cell * 0.035))
    }
}

// MARK: - 프레임 루프 + 탭

/// 대국·관전 화면이 쓰는 판. 공간에 맞춰 크기를 정하고, 애니메이션을 프레임으로 풀고, 탭을 칸으로 바꾼다.
///
/// ★ `onTapSquare` 가 **nil 이면 관전 판**이다(§6 ⑨): 탭·선택·도착 점이 전부 없어야 한다. 관전자는 "내 차례·
///   내 색" 이 없으므로 그 둘에 매인 그림을 **여기서 끊는다** — 부르는 쪽이 매번 빈 값을 넘기기를 믿지 않는다.
/// ★ `whiteAtBottom` 하나가 뒤집기를 쥔다(§6 ①). 내 색이 아래여야 판이 읽히고, 관전자는 백이 아래가 관례다.
package struct GamesChessBoard: View {
    private let position: ChessPosition
    private let flight: ChessMoveFlight?
    private let whiteAtBottom: Bool
    private let selection: ChessSquare?
    private let legalTargets: Set<ChessSquare>
    private let lastMove: (from: ChessSquare, to: ChessSquare)?
    /// 체크를 받은 쪽 왕의 칸(빨간 덮개). **기본값이 없다** — 부르는 자리가 조용히 빠뜨리면 문구는 "체크예요"
    /// 라고 말하는데 판에는 아무 표시가 없다(통합 직후 실제로 그랬다: 캔버스에는 인자가 있고 이 감싸개가
    /// 안 받아서 넷 중 어느 화면도 체크를 못 그렸다). 값은 `GamesChessCheckMark.square(...)` 에서 온다.
    private let checkSquare: ChessSquare?
    private let onTapSquare: ((ChessSquare) -> Void)?

    /// 이 판이 선 화면의 주사율(Hz). 기본값(60)으로 시작해 나타날 때 실제 값을 읽는다 — ProMotion 120 ·
    /// 일반 60(`GamesDisplay.maximumFramesPerSecond`, 미니게임 화면과 같은 문법).
    @State private var refreshHz = MiniGameFrameRate.baselineFPS

    package init(position: ChessPosition,
                 flight: ChessMoveFlight?,
                 whiteAtBottom: Bool,
                 selection: ChessSquare?,
                 legalTargets: Set<ChessSquare>,
                 lastMove: (from: ChessSquare, to: ChessSquare)?,
                 checkSquare: ChessSquare?,
                 onTapSquare: ((ChessSquare) -> Void)?) {
        self.position = position
        self.flight = flight
        self.whiteAtBottom = whiteAtBottom
        self.selection = selection
        self.legalTargets = legalTargets
        self.lastMove = lastMove
        self.checkSquare = checkSquare
        self.onTapSquare = onTapSquare
    }

    /// 입력이 있는 판인가. 없으면 관전이다.
    private var isInteractive: Bool { onTapSquare != nil }

    package var body: some View {
        GeometryReader { proxy in
            let geometry = ChessPhoneBoardGeometry(side: GamesChessBoardMetrics.side(fitting: proxy.size),
                                                   orientation: whiteAtBottom ? .white : .black)
            // ★ `paused: flight == nil` 이 **배터리 계약**이다(`GamesChessFlightLoop.isPaused`) —
            //   애니메이션이 없으면 한 틱도 돌지 않는다. 판은 대국 화면에 늘 떠 있어서, 이게 false 로 굳으면
            //   아무도 수를 안 두는 동안에도 120Hz 로 64칸 + 32말을 다시 그린다.
            TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval(forRefreshRate: refreshHz),
                                    paused: GamesChessFlightLoop.isPaused(flight: flight))) { context in
                board(geometry, frame: flight?.frame(now: context.date))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            #if os(iOS)
            refreshHz = GamesDisplay.maximumFramesPerSecond
            #endif
        }
    }

    private func board(_ geometry: ChessPhoneBoardGeometry, frame: ChessFlightFrame?) -> some View {
        GamesChessBoardCanvas(
            position: position,
            geometry: geometry,
            lastMove: lastMove,
            // 관전 판은 선택·도착 점을 **그리지 않는다**(§6 ⑨).
            selected: isInteractive ? selection : nil,
            targets: isInteractive ? legalTargets : [],
            // ★ 체크는 **관전 판에서도 그린다**(선택·도착 점과 달리 "내 차례·내 색" 에 매이지 않은 판의
            //   사실이다 — 맥 관전도 같은 덮개를 그린다). 여기에 `isInteractive` 를 끼우면 관전자는 왕이
            //   어디서 맞고 있는지 못 본다.
            checkSquare: checkSquare,
            flight: frame
        )
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { value in
            // 판 밖(격자 바깥)은 조용하다 — 거절이 아니라 빈 곳을 누른 것이다. 둘 수 있는가의 판정은
            // 받는 쪽(스토어)에 있다: 뷰가 미리 걸러 조용히 삼키면 "눌렀는데 아무 반응이 없다" 가 된다.
            guard let square = geometry.square(at: value.location) else { return }
            onTapSquare?(square)
        }, isEnabled: isInteractive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.boardAccessibility(position: position, whiteAtBottom: whiteAtBottom))
    }

    /// 판 전체를 읽는 **한 줄**(64칸을 하나씩 읽히면 못 쓴다 — 맥 `ChessText.boardAccessibility` 와 같은 규약).
    /// 화면이 더 많이 아는 글(기보 수·체크)을 말하려면 바깥에서 `.accessibilityLabel` 을 덮어쓰면 된다.
    static func boardAccessibility(position: ChessPosition, whiteAtBottom: Bool) -> String {
        ChessPhoneText.boardAccessibility(position: position, whiteAtBottom: whiteAtBottom)
    }
}
