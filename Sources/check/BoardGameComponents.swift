import SwiftUI
#if canImport(CheckCore)
import CheckCore
#elseif canImport(AlkkagiCore)
import AlkkagiCore
#endif

/// Shared window and match dimensions, keeping the original Gomoku layout.
enum BoardGameLayout {
    static let contentSize = CGSize(width: 1240, height: 700)
    static let contentPadding: CGFloat = 20
    static let columnSpacing: CGFloat = 20
    static let headerHeight: CGFloat = 40
    static let headerSpacing: CGFloat = 12

    static var innerSize: CGSize {
        CGSize(width: contentSize.width - contentPadding * 2, height: contentSize.height - contentPadding * 2)
    }
    static var bodyHeight: CGFloat { innerSize.height - headerHeight - headerSpacing }
    static var boardSide: CGFloat { bodyHeight }
    static var sideColumnWidth: CGFloat { innerSize.width - columnSpacing - boardSide }

    static let matchSideSpacing: CGFloat = 10
    static let playerCardHeight: CGFloat = 84
    static let portraitSize: CGFloat = 60
    static let nameColumnWidth: CGFloat = 132
    static let clockSize: CGFloat = 54
}

/// The board occupies the left column; all player and chat UI stays in the right column.
@MainActor
struct BoardGameMatchLayout<Board: View, Sidebar: View>: View {
    private let board: Board
    private let sidebar: Sidebar

    init(@ViewBuilder board: () -> Board, @ViewBuilder sidebar: () -> Sidebar) {
        self.board = board()
        self.sidebar = sidebar()
    }

    var body: some View {
        HStack(alignment: .top, spacing: BoardGameLayout.columnSpacing) {
            board
                .frame(width: BoardGameLayout.boardSide, height: BoardGameLayout.boardSide)
            sidebar
                .frame(width: BoardGameLayout.sideColumnWidth, height: BoardGameLayout.bodyHeight, alignment: .top)
                .clipped()
        }
    }
}

/// Games supply their player group, status, chat and actions without sharing game state.
@MainActor
struct BoardGameMatchSidebar<Players: View, Status: View, Chat: View, Actions: View>: View {
    private let players: Players
    private let status: Status
    private let chat: Chat
    private let actions: Actions

    init(@ViewBuilder players: () -> Players, @ViewBuilder status: () -> Status,
         @ViewBuilder chat: () -> Chat, @ViewBuilder actions: () -> Actions) {
        self.players = players()
        self.status = status()
        self.chat = chat()
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BoardGameLayout.matchSideSpacing) {
            players
            status
                .fixedSize(horizontal: false, vertical: true)
            chat
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            actions
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Player identity, speech and clock keep the same reserved columns on every turn.
@MainActor
struct BoardGamePlayerCard<Portrait: View, Message: View, Clock: View>: View {
    let name: String
    let stoneColor: BoardGameStoneColor
    let stoneText: String
    let isTurn: Bool
    let isMe: Bool
    private let portrait: Portrait
    private let message: Message
    private let clock: Clock

    init(name: String, stoneColor: BoardGameStoneColor, stoneText: String, isTurn: Bool, isMe: Bool,
         @ViewBuilder portrait: () -> Portrait, @ViewBuilder message: () -> Message, @ViewBuilder clock: () -> Clock) {
        self.name = name
        self.stoneColor = stoneColor
        self.stoneText = stoneText
        self.isTurn = isTurn
        self.isMe = isMe
        self.portrait = portrait()
        self.message = message()
        self.clock = clock()
    }

    var body: some View {
        HStack(spacing: 12) {
            // The caller frames the portrait and adds its center badge before this shared background.
            portrait
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.callout.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if isMe {
                        Text("나")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CheckTheme.accent)
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(Capsule().fill(CheckTheme.accent.opacity(0.18)))
                    }
                }
                HStack(spacing: 6) {
                    BoardGameStoneDot(color: stoneColor, size: 14)
                    Text(stoneText)
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(width: BoardGameLayout.nameColumnWidth, alignment: .leading)
            message
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            ZStack {
                if isTurn { clock }
            }
            .frame(width: BoardGameLayout.clockSize, height: BoardGameLayout.clockSize)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTurn ? CheckTheme.accent.opacity(0.12) : CheckTheme.panel.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isTurn ? CheckTheme.accent.opacity(0.6) : CheckTheme.border, lineWidth: isTurn ? 1.5 : 1)
        )
    }
}

/// Chat chrome only; game-specific controls, messages and behavior remain with the caller.
@MainActor
struct BoardGameChatCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CheckTheme.panel.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}

// Presentation shared by Gomoku and Alkkagi, including the standalone playground.
enum BoardGameStoneColor {
    case black, white
}

/// Small identity marker; the board stones retain their separate Canvas shading.
@MainActor
struct BoardGameStoneDot: View {
    let color: BoardGameStoneColor
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: color == .black ? [Color(white: 0.45), Color(white: 0.05)] : [Color.white, Color(white: 0.78)],
                center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size))
            .overlay(Circle().stroke(Color.black.opacity(color == .white ? 0.25 : 0), lineWidth: 0.5))
            .frame(width: size, height: size)
    }
}

enum BoardGameDrawing {
    static let woodLight = Color(red: 0.88, green: 0.73, blue: 0.49)
    static let woodDark = Color(red: 0.79, green: 0.62, blue: 0.38)
    static let lineColor = Color(red: 0.30, green: 0.21, blue: 0.12)

    /// Star points are already in Canvas coordinates; game geometry stays with the caller.
    static func drawBoard(_ context: inout GraphicsContext, side: CGFloat, inset: CGFloat, lines: Int, stars: [CGPoint]) {
        let cell = (side - inset * 2) / CGFloat(lines - 1)
        let frame = CGRect(x: 0, y: 0, width: side, height: side)
        context.fill(
            Path(roundedRect: frame, cornerRadius: side * 0.025, style: .continuous),
            with: .linearGradient(Gradient(colors: [woodLight, woodDark]),
                                  startPoint: .zero, endPoint: CGPoint(x: side, y: side))
        )

        var grid = Path()
        let far = inset + CGFloat(lines - 1) * cell
        for i in 0..<lines {
            let offset = inset + CGFloat(i) * cell
            grid.move(to: CGPoint(x: offset, y: inset))
            grid.addLine(to: CGPoint(x: offset, y: far))
            grid.move(to: CGPoint(x: inset, y: offset))
            grid.addLine(to: CGPoint(x: far, y: offset))
        }
        context.stroke(grid, with: .color(lineColor.opacity(0.85)), lineWidth: max(0.8, side / 640))
        context.stroke(
            Path(CGRect(x: inset, y: inset, width: far - inset, height: far - inset)),
            with: .color(lineColor), lineWidth: max(1.2, side / 380)
        )

        for c in stars {
            let r = max(2, cell * 0.1)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(lineColor))
        }
    }

    static func drawStone(_ context: inout GraphicsContext, at c: CGPoint, radius r: CGFloat,
                          color: BoardGameStoneColor, opacity: Double = 1) {
        var layer = context
        layer.opacity = opacity
        let shadow = Path(ellipseIn: CGRect(x: c.x - r + r * 0.06, y: c.y - r + r * 0.14, width: r * 2, height: r * 2))
        layer.fill(shadow, with: .color(.black.opacity(0.25)))
        let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        let highlight = CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4)
        switch color {
        case .black:
            layer.fill(circle, with: .radialGradient(
                Gradient(colors: [Color(white: 0.45), Color(white: 0.05)]),
                center: highlight, startRadius: 0, endRadius: r * 1.5))
        case .white:
            layer.fill(circle, with: .radialGradient(
                Gradient(colors: [Color(white: 1.0), Color(white: 0.80)]),
                center: highlight, startRadius: 0, endRadius: r * 1.6))
            layer.stroke(circle, with: .color(.black.opacity(0.2)), lineWidth: 0.8)
        }
    }
}

/// A clock face only; each game supplies its remaining time and urgency color.
struct BoardGameClockRing: View {
    let remaining: Double
    var duration: Double = 30
    let tint: Color

    var body: some View {
        let fraction = min(1, max(0, remaining / duration))
        let seconds = "\(Int(max(0, remaining).rounded(.up)))초"
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(seconds)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("남은 시간 \(seconds)")
    }
}

struct BoardGameChatBubble: View {
    let text: String
    let isMine: Bool
    let oppositeInset: CGFloat
    let accent: Color
    let primaryText: Color

    init(body: String, isMine: Bool, oppositeInset: CGFloat, accent: Color, primaryText: Color) {
        self.text = body
        self.isMine = isMine
        self.oppositeInset = oppositeInset
        self.accent = accent
        self.primaryText = primaryText
    }

    var body: some View {
        HStack(spacing: 0) {
            if isMine { Spacer(minLength: oppositeInset) }
            Text(text)
                .font(.caption)
                .foregroundStyle(isMine ? Color.white : primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isMine ? accent.opacity(0.85) : Color.white.opacity(0.10))
                )
            if !isMine { Spacer(minLength: oppositeInset) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }
}
