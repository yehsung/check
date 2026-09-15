import AppKit
import SwiftUI

// MARK: - 1:1 오목 창 화면 (v0.3.27)
//
// `CheckGomokuWindowController` 가 담는 화면이다: 로비(상대 고르기·판돈·신청) → 대국(15×15 판) → 결과, 그리고
// 어느 화면에서든 [규칙] 로 여는 렌주 설명 오버레이. 상태·동작은 전부 `GomokuStore`(§6.3 선언)에 있고 여기는 그리기만 한다.
//
// 이 파일이 지키는 약속:
//   · **Picker/Menu/TextField 를 쓰지 않는다.** ImageRenderer 가 노란 상자(255,204,0)로 그려 렌더 검증이 그 자리에서
//     눈이 먼다. 판돈 선택·수락·기권·판은 전부 Button + Shape/Canvas 다.
//   · **초 단위 값(남은 시간·신청 만료)은 잎 뷰 TimelineView 안에서만 읽는다**(`GomokuTurnClock` · `GomokuCountdownText`).
//     창 루트가 시계를 읽으면 5Hz 로 창 전체가 다시 그려진다. 잎은 창이 안 보이면 멈춘다(`isWindowVisible`).
//   · 툴팁은 `.checkTooltip`, 창 루트에 `.checkTooltipLayer()` 하나. 정보는 툴팁에만 두지 않는다 —
//     금수 이유는 오른쪽 상태줄에도 글자로 뜬다(툴팁은 픽셀을 안 만들어 렌더 검증이 못 본다).
//   · 문구는 사용자 어휘만(`GomokuText`).

// MARK: - 나(플레이어 얼굴)

/// 카드에 그릴 사람 한 명의 얼굴. 스토어(§6.3)는 **상대만** 들고 있어서 나는 앱 배선이 `WorkTimerStore` 에서 읽어 넘긴다.
struct GomokuPlayerFace: Equatable {
    let name: String
    let avatarURL: URL?
    let characterID: String

    /// 캐릭터를 모를 때 쓰는 기본 캐릭터(앱의 첫 캐릭터).
    static let fallbackCharacterID = "aing"
    static let fallback = GomokuPlayerFace(name: "나", avatarURL: nil, characterID: fallbackCharacterID)

    /// 로그인한 나. 이름·아바타는 팀 목록의 내 행에서, 캐릭터는 이 맥에서 고른 캐릭터에서 읽는다.
    @MainActor
    static func me(from store: WorkTimerStore) -> GomokuPlayerFace {
        let myID = store.session?.userID
        let mine = store.teamMembers.first { $0.id == myID }
        let character = CheckCharacter3DScene.selectedCharacter(defaults: .standard).id
        return GomokuPlayerFace(name: mine?.name ?? "나", avatarURL: mine?.avatarURL, characterID: character)
    }

    static func of(_ user: GomokuUser) -> GomokuPlayerFace {
        GomokuPlayerFace(
            name: user.displayName,
            avatarURL: user.avatarURL.flatMap(URL.init(string:)),
            characterID: user.characterID ?? fallbackCharacterID
        )
    }
}

// MARK: - 문구

/// 오목 화면의 사용자 문구(순수 — 값으로 검증한다). 진단 어휘를 쓰지 않는다.
enum GomokuText {
    static let title = "1:1 오목"
    static let subtitle = "렌주룰 · 흑 선공 · 한 수 30초"
    static let rulesButton = "규칙"
    static let rulesTitle = "렌주 규칙"
    static let close = "닫기"

    /// 한 수 제한(초). 서버 `gomoku_turn_seconds()` 와 **짝인 상수**다 — 링이 몇 초에서 가득 차는지만 정한다
    /// (남은 시간 자체는 서버 마감에서 온다).
    static let turnSeconds: Double = 30

    static let lobbyTitle = "상대 고르기"
    static let lobbyCaption = "둘 다 근무 중일 때 신청하고 받을 수 있어요"
    static let emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    static let challenge = "도전"
    static let stakeTitle = "판돈"
    static let stakeCaption = "수락하는 순간 두 사람 모두 걸고, 이긴 사람이 두 배를 가져가요"
    static let incomingTitle = "받은 신청"
    static let outgoingTitle = "보낸 신청"
    static let noIncoming = "받은 신청이 없어요"
    static let accept = "수락"
    static let decline = "거절"
    static let cancel = "취소"

    static let myTurn = "내 차례예요"
    static let opponentTurn = "상대 차례예요"
    static let blackPassed = "흑이 둘 곳이 없어 차례가 백으로 넘어갔어요"
    static let resign = "기권"
    static let resignConfirm = "기권하면 건 루비를 잃어요"
    static let resignNow = "기권하기"
    static let keepPlaying = "계속 두기"

    static let backToLobby = "로비로"
    static let rematch = "같은 판돈으로 다시 신청"

    static func record(_ record: GomokuRecord?) -> String {
        guard let record else { return "전적 —" }
        return "\(record.wins)승 \(record.losses)패 \(record.draws)무"
    }

    static func challengeHelp(stake: Int) -> String { "판돈 \(stake)루비로 대결을 신청해요" }

    /// 상대 행 상태 칩 문구. 우선순위: 대국 중 > 업데이트 필요 > 근무 중/근무 안 함.
    static func status(for user: GomokuUser) -> String {
        if user.inMatch { return "대국 중" }
        if !user.isCapable { return "업데이트 필요" }
        return user.isWorking ? "근무 중" : "근무 안 함"
    }

    static func reasonLabel(_ reason: GomokuForbiddenReason) -> String {
        switch reason {
        case .doubleThree: return "3-3 금수"
        case .doubleFour: return "4-4 금수"
        case .overline: return "장목 금수"
        case .budget: return "판정할 수 없는 자리"
        }
    }

    /// X 위 툴팁.
    static func forbiddenTooltip(_ reason: GomokuForbiddenReason) -> String {
        reason == .budget ? "판정할 수 없는 자리예요" : "\(reasonLabel(reason)) 자리예요"
    }

    /// 상태줄(호버·클릭).
    static func forbiddenStatus(_ reason: GomokuForbiddenReason) -> String {
        reason == .budget ? "판정할 수 없는 자리예요" : "\(reasonLabel(reason))라 둘 수 없어요"
    }

    static func stakeLine(_ stake: Int) -> String { "\(stake) · 이기면 \(stake * 2)" }

    static func stoneName(_ color: GomokuColor) -> String { color == .black ? "흑 · 먼저 둬요" : "백" }

    static func remaining(_ seconds: Double) -> String { "\(Int(max(0, seconds).rounded(.up)))초" }

    static func outcomeTitle(_ outcome: GomokuOutcome?) -> String {
        switch outcome {
        case .won?: return "이겼어요!"
        case .lost?: return "졌어요"
        case .draw?: return "무승부"
        case nil: return "대국이 끝났어요"
        }
    }

    static func endReason(_ reason: GomokuEndReason?, outcome: GomokuOutcome?) -> String {
        switch (reason, outcome) {
        case (.five?, .won?): return "5목을 완성했어요"
        case (.five?, _): return "상대가 5목을 완성했어요"
        case (.timeout?, .won?): return "상대의 시간이 다 됐어요"
        case (.timeout?, _): return "시간이 다 됐어요"
        case (.resign?, .won?): return "상대가 기권했어요"
        case (.resign?, _): return "기권했어요"
        case (.boardFull?, _): return "판이 가득 찼어요 · 건 루비는 돌려받아요"
        case (nil, _): return ""
        }
    }

    /// 루비 변화(+10 / −10 / ±0).
    static func rubyDelta(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "−\(-delta)" }
        return "±0"
    }

    static func inviteTitle(name: String) -> String { "\(name)님이 오목 대결을 신청했어요" }
    static func outgoingTitle(name: String) -> String { "\(name)님에게 신청했어요" }
    static func incomingTitle(name: String) -> String { "\(name)님의 신청" }
    static let inviteBannerSubtitle = "수락하면 대결 창이 열려요"
}

// MARK: - 판 좌표

/// 판(또는 판의 일부) 그림의 좌표계. 순수 값 — 클릭 위치 ↔ 교차점 변환을 결정적으로 잰다.
///
/// 행은 **아래가 1** 이다(렌주 표기 · 서버 인덱스 y). 화면 y 는 위가 0 이라 뒤집는다.
struct GomokuBoardGeometry: Equatable {
    /// 그림 한 변(pt).
    let side: CGFloat
    /// 그리는 줄 수(전체 판 15, 규칙 예시 9).
    var lines: Int = GomokuBoard.size
    /// 가장 왼쪽 열의 x · 가장 아래 행의 y(규칙 예시는 판의 가운데만 잘라 그린다).
    var originX: Int = 0
    var originY: Int = 0
    /// 바깥 여백 비율(좌표 글자와 가장자리 돌이 들어갈 자리).
    var insetRatio: CGFloat = 0.06

    var inset: CGFloat { side * insetRatio }
    var cell: CGFloat { (side - inset * 2) / CGFloat(lines - 1) }

    func contains(_ point: GomokuPoint) -> Bool {
        point.x >= originX && point.x < originX + lines && point.y >= originY && point.y < originY + lines
    }

    func location(of point: GomokuPoint) -> CGPoint {
        CGPoint(
            x: inset + CGFloat(point.x - originX) * cell,
            y: inset + CGFloat(originY + lines - 1 - point.y) * cell
        )
    }

    /// 화면 위치에서 가장 가까운 교차점(반 칸 밖이면 nil).
    func point(at location: CGPoint) -> GomokuPoint? {
        let column = (location.x - inset) / cell
        let row = (location.y - inset) / cell
        let ix = Int(column.rounded())
        let iy = Int(row.rounded())
        guard (0..<lines).contains(ix), (0..<lines).contains(iy),
              abs(column - CGFloat(ix)) <= 0.5, abs(row - CGFloat(iy)) <= 0.5 else { return nil }
        return GomokuPoint(x: originX + ix, y: originY + lines - 1 - iy)
    }

    /// 화점(D4·L4·H8·D12·L12).
    static let starPoints: [GomokuPoint] = [(3, 3), (11, 3), (7, 7), (3, 11), (11, 11)].compactMap {
        GomokuPoint(x: $0.0, y: $0.1)
    }
}

// MARK: - 판 그림

/// 규칙 예시 판에 얹는 표시.
enum GomokuBoardMark: Equatable {
    /// 금수 자리(빨간 X).
    case forbidden
    /// 두면 이기는 자리(반투명 흑 + 초록 고리).
    case win
    /// 둘 수 있는 자리(반투명 흑 + 파란 고리).
    case legal
    /// 설명용 보조 자리(주황 X — 거짓 3 의 전환점).
    case pivot
}

/// 호버 미리보기 돌.
struct GomokuPreviewStone: Equatable {
    let point: GomokuPoint
    let color: GomokuColor
}

/// 15×15 판(또는 그 일부)을 Canvas 한 장으로 그린다. 입력을 받지 않는 순수 그림이다 — 클릭·호버는 감싸는 쪽이 한다.
struct GomokuBoardView: View {
    let board: GomokuBoard
    let geometry: GomokuBoardGeometry
    var lastMove: GomokuPoint? = nil
    var forbidden: [GomokuPoint: GomokuForbiddenReason] = [:]
    var marks: [GomokuPoint: GomokuBoardMark] = [:]
    var preview: GomokuPreviewStone? = nil
    var showsCoordinates: Bool = true

    static let woodLight = Color(red: 0.88, green: 0.73, blue: 0.49)
    static let woodDark = Color(red: 0.79, green: 0.62, blue: 0.38)
    static let lineColor = Color(red: 0.30, green: 0.21, blue: 0.12)
    /// 금수 X 색(렌더 테스트가 이 색을 픽셀로 찾는다).
    static let forbiddenColor = Color(red: 0.87, green: 0.16, blue: 0.18)
    static let lastMoveColor = Color(red: 0.95, green: 0.30, blue: 0.26)

    var body: some View {
        Canvas { context, _ in
            drawBoard(in: &context)
        }
        .frame(width: geometry.side, height: geometry.side)
    }

    private func drawBoard(in context: inout GraphicsContext) {
        let g = geometry
        let side = g.side
        let frame = CGRect(x: 0, y: 0, width: side, height: side)
        context.fill(
            Path(roundedRect: frame, cornerRadius: side * 0.025, style: .continuous),
            with: .linearGradient(Gradient(colors: [Self.woodLight, Self.woodDark]),
                                  startPoint: .zero, endPoint: CGPoint(x: side, y: side))
        )

        // 줄
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
        context.stroke(
            Path(CGRect(x: g.inset, y: g.inset, width: far - g.inset, height: far - g.inset)),
            with: .color(Self.lineColor), lineWidth: max(1.2, side / 380)
        )

        // 화점
        for star in GomokuBoardGeometry.starPoints where g.contains(star) {
            let c = g.location(of: star)
            let r = max(2, g.cell * 0.1)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(Self.lineColor))
        }

        // 좌표(A..O 아래 · 1..15 왼쪽)
        if showsCoordinates {
            let letters = Array("ABCDEFGHIJKLMNO")
            let size = max(8, g.inset * 0.32)
            for i in 0..<g.lines {
                let offset = g.inset + CGFloat(i) * g.cell
                let column = g.originX + i
                if column < letters.count {
                    context.draw(
                        Text(String(letters[column])).font(.system(size: size, weight: .semibold))
                            .foregroundStyle(Self.lineColor.opacity(0.8)),
                        at: CGPoint(x: offset, y: side - g.inset * 0.3), anchor: .center)
                }
                let row = g.originY + g.lines - i
                context.draw(
                    Text("\(row)").font(.system(size: size, weight: .semibold))
                        .foregroundStyle(Self.lineColor.opacity(0.8)),
                    at: CGPoint(x: g.inset * 0.3, y: offset), anchor: .center)
            }
        }

        // 돌
        let radius = g.cell * 0.46
        for y in g.originY..<(g.originY + g.lines) {
            for x in g.originX..<(g.originX + g.lines) {
                guard let point = GomokuPoint(x: x, y: y), let color = board[point] else { continue }
                Self.drawStone(&context, at: g.location(of: point), radius: radius, color: color, opacity: 1)
            }
        }

        // 마지막 수
        if let lastMove, g.contains(lastMove), board[lastMove] != nil {
            let c = g.location(of: lastMove)
            let r = max(2.5, g.cell * 0.13)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(Self.lastMoveColor))
        }

        // 호버 미리보기
        if let preview, g.contains(preview.point), board[preview.point] == nil {
            Self.drawStone(&context, at: g.location(of: preview.point), radius: radius, color: preview.color, opacity: 0.45)
        }

        // 금수 X
        for (point, reason) in forbidden where g.contains(point) && board[point] == nil {
            Self.drawCross(&context, at: g.location(of: point), half: g.cell * 0.22,
                           width: max(2, g.cell * 0.08),
                           color: reason == .budget ? CheckTheme.pending : Self.forbiddenColor)
        }

        // 예시 표시
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
                context.stroke(ring, with: .color(mark == .win ? CheckTheme.working : CheckTheme.accent),
                               lineWidth: max(2, g.cell * 0.1))
            }
        }
    }

    static func drawStone(_ context: inout GraphicsContext, at c: CGPoint, radius r: CGFloat, color: GomokuColor, opacity: Double) {
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

    static func drawCross(_ context: inout GraphicsContext, at c: CGPoint, half: CGFloat, width: CGFloat, color: Color) {
        var cross = Path()
        cross.move(to: CGPoint(x: c.x - half, y: c.y - half))
        cross.addLine(to: CGPoint(x: c.x + half, y: c.y + half))
        cross.move(to: CGPoint(x: c.x + half, y: c.y - half))
        cross.addLine(to: CGPoint(x: c.x - half, y: c.y + half))
        context.stroke(cross, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

/// 흑 차례 X 표시 계산을 판이 바뀔 때만 한다. 호버마다 225칸을 다시 판정하지 않기 위해서다.
@MainActor
final class GomokuForbiddenMemo {
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

// MARK: - 창 루트

struct GomokuPanel: View {
    let store: GomokuStore
    /// 내 얼굴을 읽는 문(앱 배선이 WorkTimerStore 에서 읽는다). 기본은 "나" + 기본 캐릭터.
    var me: @MainActor () -> GomokuPlayerFace = { GomokuPlayerFace.fallback }
    /// 스냅샷 전용: 상대 목록을 ScrollView 대신 클립으로 그린다(ImageRenderer 는 ScrollView 안을 못 그린다). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false

    @State private var hovered: GomokuPoint?
    @State private var confirmResign = false
    @State private var forbiddenMemo = GomokuForbiddenMemo()

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: GomokuWindowLayout.headerSpacing) {
                GomokuHeader(store: store)
                    .frame(height: GomokuWindowLayout.headerHeight)
                content
                    .frame(width: GomokuWindowLayout.innerSize.width, height: GomokuWindowLayout.bodyHeight, alignment: .topLeading)
            }
            .padding(GomokuWindowLayout.contentPadding)
            if store.isRulesVisible {
                GomokuRulesOverlay(onClose: { store.isRulesVisible = false })
            }
        }
        .frame(width: GomokuWindowLayout.contentSize.width, height: GomokuWindowLayout.contentSize.height, alignment: .topLeading)
        .background(CheckTheme.background)
        .foregroundStyle(CheckTheme.primaryText)
        // 툴팁 말풍선 레이어 — 창 루트 하나. 판·목록 클리핑 바깥이다.
        .checkTooltipLayer()
        .onChange(of: store.match?.id) { _, _ in
            confirmResign = false
            hovered = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .playing:
            if let match = store.match { playing(match) } else { lobby }
        case .result:
            if let match = store.match { result(match) } else { lobby }
        case .lobby:
            lobby
        }
    }

    // MARK: 로비

    private var lobby: some View {
        HStack(alignment: .top, spacing: GomokuWindowLayout.columnSpacing) {
            GomokuOpponentList(store: store, clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                .frame(width: GomokuWindowLayout.lobbyListWidth, height: GomokuWindowLayout.bodyHeight, alignment: .top)
            GomokuLobbySide(store: store)
                .frame(width: GomokuWindowLayout.lobbySideWidth, height: GomokuWindowLayout.bodyHeight, alignment: .top)
        }
    }

    // MARK: 대국

    private func playing(_ match: GomokuMatchState) -> some View {
        let showsForbidden = !match.isFinished && match.myColor == .black && match.turn == .black
        let forbidden = showsForbidden ? forbiddenMemo.points(for: match.board) : [:]
        return HStack(alignment: .top, spacing: GomokuWindowLayout.columnSpacing) {
            GomokuPlayBoard(store: store, match: match, forbidden: forbidden, hovered: $hovered)
                .frame(width: GomokuWindowLayout.boardSide, height: GomokuWindowLayout.boardSide)
            GomokuMatchSide(
                store: store, match: match, me: me(),
                hoveredReason: hovered.flatMap { forbidden[$0] },
                confirmResign: $confirmResign
            )
            .frame(width: GomokuWindowLayout.sideColumnWidth, height: GomokuWindowLayout.bodyHeight, alignment: .top)
        }
    }

    // MARK: 결과

    private func result(_ match: GomokuMatchState) -> some View {
        HStack(alignment: .top, spacing: GomokuWindowLayout.columnSpacing) {
            GomokuBoardView(
                board: match.board,
                geometry: GomokuBoardGeometry(side: GomokuWindowLayout.boardSide),
                lastMove: match.lastMove
            )
            GomokuResultCard(store: store, match: match)
                .frame(width: GomokuWindowLayout.sideColumnWidth, height: GomokuWindowLayout.bodyHeight, alignment: .top)
        }
    }
}

// MARK: - 머리글

private struct GomokuHeader: View {
    let store: GomokuStore

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(CheckTheme.accent.opacity(0.18))
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(GomokuText.title)
                    .font(.title3.weight(.bold))
                Text(GomokuText.subtitle)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                Image(systemName: "flag.checkered")
                Text(GomokuText.record(store.record)).monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(CheckTheme.border, lineWidth: 1))
            .checkTooltip("내 오목 전적")
            RubyBalanceChip(balance: store.rubyBalance, large: true)
                .checkTooltip("내 루비")
            GomokuActionButton(title: GomokuText.rulesButton, icon: "book.fill", style: .outline, height: 30) {
                store.isRulesVisible = true
            }
            .checkTooltip("렌주 규칙과 금수 예시를 봐요")
        }
    }
}

// MARK: - 로비: 상대 목록

private struct GomokuOpponentList: View {
    let store: GomokuStore
    let clipsOverflowInsteadOfScroll: Bool

    static let rowHeight: CGFloat = 56
    static let rowSpacing: CGFloat = 6

    /// 근무 중·가능한 사람 먼저(서버 순서는 그 안에서 유지).
    private var sortedUsers: [GomokuUser] {
        store.users.enumerated().sorted { lhs, rhs in
            let a = Self.rank(lhs.element), b = Self.rank(rhs.element)
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)
    }

    static func rank(_ user: GomokuUser) -> Int {
        if user.isCapable && user.isWorking && !user.inMatch { return 0 }
        if user.inMatch { return 1 }
        if user.isCapable { return 2 }
        return 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(GomokuText.lobbyTitle).font(.headline)
                Spacer()
                Text(GomokuText.lobbyCaption)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            if store.users.isEmpty {
                Text(GomokuText.emptyUsers)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if clipsOverflowInsteadOfScroll {
                // minHeight 0 이 핵심이다 — 없으면 이 틀이 행들의 자연 높이를 그대로 보고해 카드가 608pt 본문을 뚫고
                // 창 아래로 자란다(2026-09-16 스냅샷 실측: 사람 10명에서 카드 아래 테두리가 창 밖으로 나갔다).
                rows
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                    .clipped()
            } else {
                ScrollView {
                    rows
                }
                .scrollIndicators(.automatic)
            }
        }
        .gomokuCard()
    }

    private var rows: some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(sortedUsers) { user in
                GomokuOpponentRow(store: store, user: user)
                    .frame(height: Self.rowHeight)
            }
        }
    }
}

private struct GomokuOpponentRow: View {
    let store: GomokuStore
    let user: GomokuUser

    private var canChallenge: Bool {
        user.isWorking && user.isCapable && !user.inMatch && store.outgoing == nil && store.match == nil && !store.isBusy
    }

    private var chipTint: Color {
        if user.inMatch { return CheckTheme.pending }
        if !user.isCapable { return CheckTheme.secondaryText }
        return user.isWorking ? CheckTheme.working : CheckTheme.offWork
    }

    var body: some View {
        HStack(spacing: 12) {
            CheckAvatarView(name: user.displayName, avatarURL: user.avatarURL.flatMap(URL.init(string:)), size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(GomokuText.status(for: user))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(chipTint)
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(Capsule().fill(chipTint.opacity(0.16)))
            }
            Spacer(minLength: 8)
            GomokuActionButton(
                title: GomokuText.challenge, icon: "bolt.fill",
                style: canChallenge ? .filled : .outline, height: 30, isEnabled: canChallenge
            ) {
                Task { await store.challenge(userID: user.id) }
            }
            .checkTooltip(GomokuText.challengeHelp(stake: store.selectedStake.rawValue))
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}

// MARK: - 로비: 판돈 · 신청

private struct GomokuLobbySide: View {
    let store: GomokuStore

    /// 받은 신청 카드는 두 장까지(나머지는 "외 N건"). 오른쪽 열이 608 을 넘지 않게 한다.
    static let maxIncomingCards = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            stakeCard
            VStack(alignment: .leading, spacing: 8) {
                Text(GomokuText.incomingTitle).font(.subheadline.weight(.bold))
                if store.incoming.isEmpty {
                    Text(GomokuText.noIncoming)
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                } else {
                    ForEach(store.incoming.prefix(Self.maxIncomingCards)) { invite in
                        GomokuInviteCard(store: store, invite: invite, isIncoming: true)
                    }
                    if store.incoming.count > Self.maxIncomingCards {
                        Text("외 \(store.incoming.count - Self.maxIncomingCards)건")
                            .font(.caption2)
                            .foregroundStyle(CheckTheme.secondaryText)
                    }
                }
            }
            if let outgoing = store.outgoing {
                VStack(alignment: .leading, spacing: 8) {
                    Text(GomokuText.outgoingTitle).font(.subheadline.weight(.bold))
                    GomokuInviteCard(store: store, invite: outgoing, isIncoming: false)
                }
            }
            Spacer(minLength: 0)
            if let notice = store.notice {
                GomokuNoticeLine(text: notice)
            }
        }
    }

    private var stakeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(GomokuText.stakeTitle).font(.subheadline.weight(.bold))
            HStack(spacing: 8) {
                ForEach(GomokuStake.allCases, id: \.rawValue) { stake in
                    GomokuStakeButton(
                        stake: stake.rawValue,
                        isSelected: store.selectedStake == stake,
                        isEnabled: store.outgoing == nil && !store.isBusy
                    ) {
                        store.selectedStake = stake
                    }
                }
            }
            Text(GomokuText.stakeCaption)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .gomokuCard(padding: 14)
    }
}

private struct GomokuStakeButton: View {
    let stake: Int
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                RubyIcon(size: 18)
                Text("\(stake)")
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Color.white : CheckTheme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? CheckTheme.accent.opacity(0.85) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? CheckTheme.accent : CheckTheme.border, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled || isSelected ? 1 : 0.5)
        .checkTooltip("판돈 \(stake)루비")
    }
}

private struct GomokuInviteCard: View {
    let store: GomokuStore
    let invite: GomokuInvite
    let isIncoming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CheckAvatarView(name: invite.peer.displayName, avatarURL: invite.peer.avatarURL.flatMap(URL.init(string:)), size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isIncoming ? GomokuText.incomingTitle(name: invite.peer.displayName)
                                    : GomokuText.outgoingTitle(name: invite.peer.displayName))
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    HStack(spacing: 4) {
                        Text("판돈")
                        RubyIcon(size: 12)
                        Text("\(invite.stake)").monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                }
                Spacer(minLength: 6)
                GomokuCountdownText(expiresAt: invite.expiresAt, isLive: store.isWindowVisible)
            }
            HStack(spacing: 8) {
                if isIncoming {
                    GomokuActionButton(title: GomokuText.accept, icon: "checkmark", height: 30, fullWidth: true,
                                       isEnabled: !store.isBusy) {
                        Task { await store.respond(inviteID: invite.id, accept: true) }
                    }
                    GomokuActionButton(title: GomokuText.decline, style: .outline, height: 30, fullWidth: true,
                                       isEnabled: !store.isBusy) {
                        Task { await store.respond(inviteID: invite.id, accept: false) }
                    }
                } else {
                    GomokuActionButton(title: GomokuText.cancel, style: .outline, height: 30, fullWidth: true,
                                       isEnabled: !store.isBusy) {
                        Task { await store.cancelChallenge() }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isIncoming ? CheckTheme.accent.opacity(0.12) : CheckTheme.panel.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isIncoming ? CheckTheme.accent.opacity(0.5) : CheckTheme.border, lineWidth: 1)
        )
    }
}

/// 신청 만료까지 남은 초 — **잎 뷰**. 창이 안 보이면 멈춘다.
struct GomokuCountdownText: View {
    let expiresAt: Date
    let isLive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isLive)) { context in
            Text(GomokuText.remaining(expiresAt.timeIntervalSince(context.date)))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.pending)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(CheckTheme.pending.opacity(0.14)))
        }
    }
}

private struct GomokuNoticeLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(CheckTheme.pending)
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CheckTheme.pending.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(CheckTheme.pending.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - 대국: 판

private struct GomokuPlayBoard: View {
    let store: GomokuStore
    let match: GomokuMatchState
    let forbidden: [GomokuPoint: GomokuForbiddenReason]
    @Binding var hovered: GomokuPoint?

    private var geometry: GomokuBoardGeometry { GomokuBoardGeometry(side: GomokuWindowLayout.boardSide) }

    private var canPlace: Bool {
        !match.isFinished && match.turn == match.myColor && !store.isBusy
    }

    private var preview: GomokuPreviewStone? {
        guard canPlace, let hovered, match.board[hovered] == nil, forbidden[hovered] == nil else { return nil }
        return GomokuPreviewStone(point: hovered, color: match.myColor)
    }

    var body: some View {
        let g = geometry
        GomokuBoardView(board: match.board, geometry: g, lastMove: match.lastMove, forbidden: forbidden, preview: preview)
            .overlay(alignment: .topLeading) {
                // 금수 X 마다 투명한 호버 자리 + 이유 툴팁. 이유는 오른쪽 상태줄에도 글자로 뜬다.
                ForEach(forbidden.keys.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }), id: \.self) { point in
                    Color.clear
                        .frame(width: g.cell, height: g.cell)
                        .contentShape(Rectangle())
                        .checkTooltip(GomokuText.forbiddenTooltip(forbidden[point] ?? .doubleThree))
                        .position(g.location(of: point))
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hovered = g.point(at: location)
                case .ended: hovered = nil
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { value in
                    guard let point = g.point(at: value.location) else { return }
                    // 금수 자리는 서버에 보내지 않는다 — 상태줄이 이유를 말하도록 그 자리를 짚어 둔다.
                    if forbidden[point] != nil {
                        hovered = point
                        return
                    }
                    guard canPlace, match.board[point] == nil else { return }
                    Task { await store.place(point) }
                }
            )
    }
}

// MARK: - 대국: 오른쪽 열

private struct GomokuMatchSide: View {
    let store: GomokuStore
    let match: GomokuMatchState
    let me: GomokuPlayerFace
    let hoveredReason: GomokuForbiddenReason?
    @Binding var confirmResign: Bool

    private var statusLine: (text: String, tint: Color) {
        if let hoveredReason { return (GomokuText.forbiddenStatus(hoveredReason), CheckTheme.danger) }
        if let notice = store.notice { return (notice, CheckTheme.pending) }
        if match.turn == match.myColor { return (GomokuText.myTurn, CheckTheme.working) }
        return (GomokuText.opponentTurn, CheckTheme.secondaryText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GomokuPlayerCard(store: store, face: .of(match.opponent), color: match.myColor.opponent,
                             isTurn: match.turn == match.myColor.opponent, isMe: false)
            GomokuPlayerCard(store: store, face: me, color: match.myColor,
                             isTurn: match.turn == match.myColor, isMe: true)

            HStack(spacing: 6) {
                Text(GomokuText.stakeTitle)
                    .foregroundStyle(CheckTheme.secondaryText)
                RubyIcon(size: 16)
                Text(GomokuText.stakeLine(match.stake)).monospacedDigit()
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                Text(statusLine.text)
                    .font(.headline)
                    .foregroundStyle(statusLine.tint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if match.blackPassed {
                    Text(GomokuText.blackPassed)
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(statusLine.tint.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(statusLine.tint.opacity(0.35), lineWidth: 1))

            Spacer(minLength: 0)

            if confirmResign {
                VStack(alignment: .leading, spacing: 8) {
                    Text(GomokuText.resignConfirm)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckTheme.danger)
                    HStack(spacing: 8) {
                        GomokuActionButton(title: GomokuText.resignNow, icon: "flag.fill", tint: CheckTheme.danger,
                                           height: 34, fullWidth: true, isEnabled: !store.isBusy) {
                            confirmResign = false
                            Task { await store.resign() }
                        }
                        GomokuActionButton(title: GomokuText.keepPlaying, style: .outline, height: 34, fullWidth: true) {
                            confirmResign = false
                        }
                    }
                }
            } else {
                GomokuActionButton(title: GomokuText.resign, icon: "flag", tint: CheckTheme.danger, style: .outline,
                                   height: 34, fullWidth: true, isEnabled: !match.isFinished && !store.isBusy) {
                    confirmResign = true
                }
                .checkTooltip("한 번 더 확인한 뒤 기권해요")
            }
        }
    }
}

private struct GomokuPlayerCard: View {
    let store: GomokuStore
    let face: GomokuPlayerFace
    let color: GomokuColor
    let isTurn: Bool
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            CharacterPortrait(characterID: face.characterID)
                .frame(width: 60, height: 60)
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(face.name)
                        .font(.callout.weight(.bold))
                        .lineLimit(1)
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
                    GomokuStoneDot(color: color, size: 14)
                    Text(GomokuText.stoneName(color))
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                }
            }
            Spacer(minLength: 6)
            if isTurn {
                GomokuTurnClock(store: store)
                    .frame(width: 54, height: 54)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct GomokuStoneDot: View {
    let color: GomokuColor
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

/// 차례인 사람의 30초 링 — **잎 뷰**. 남은 시간은 스토어가 서버 마감으로 계산한다(`remainingSeconds(now:)`).
struct GomokuTurnClock: View {
    let store: GomokuStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !store.isWindowVisible)) { context in
            let remaining = store.remainingSeconds(now: context.date) ?? 0
            let fraction = min(1, max(0, remaining / GomokuText.turnSeconds))
            let tint = remaining <= 5 ? CheckTheme.danger : (remaining <= 10 ? CheckTheme.pending : CheckTheme.working)
            ZStack {
                Circle().stroke(Color.white.opacity(0.10), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(GomokuText.remaining(remaining))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            .padding(3)
        }
    }
}

// MARK: - 결과

private struct GomokuResultCard: View {
    let store: GomokuStore
    let match: GomokuMatchState

    private var delta: Int {
        if let rubyDelta = match.rubyDelta { return rubyDelta }
        switch match.outcome {
        case .won?: return match.stake
        case .lost?: return -match.stake
        default: return 0
        }
    }

    private var tint: Color {
        switch match.outcome {
        case .won?: return CheckTheme.working
        case .lost?: return CheckTheme.danger
        default: return CheckTheme.offWork
        }
    }

    private var icon: String {
        switch match.outcome {
        case .won?: return "trophy.fill"
        case .lost?: return "flag.fill"
        default: return "equal.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(tint.opacity(0.16)))
                    .overlay(Circle().stroke(tint.opacity(0.45), lineWidth: 1))
                Text(GomokuText.outcomeTitle(match.outcome))
                    .font(.system(size: 30, weight: .bold))
                Text(GomokuText.endReason(match.endReason, outcome: match.outcome))
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    RubyIcon(size: 26)
                    Text(GomokuText.rubyDelta(delta))
                        .font(.system(size: 26, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(delta > 0 ? CheckTheme.working : (delta < 0 ? CheckTheme.danger : CheckTheme.primaryText))
                }
                .padding(.top, 4)
                Text("상대 · \(match.opponent.displayName)")
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1))

            Spacer(minLength: 0)

            if let notice = store.notice {
                GomokuNoticeLine(text: notice)
            }
            GomokuActionButton(title: GomokuText.rematch, icon: "arrow.clockwise", height: 40, fullWidth: true,
                               isEnabled: !store.isBusy && store.outgoing == nil) {
                Task { await store.rematch() }
            }
            .checkTooltip("같은 상대에게 \(match.stake)루비로 다시 신청해요")
            GomokuActionButton(title: GomokuText.backToLobby, style: .outline, height: 40, fullWidth: true) {
                store.backToLobby()
            }
        }
    }
}

// MARK: - 규칙 보기

/// 규칙 보기의 예시 국면. **좌표는 조사 코퍼스(`cases.final.json`)에서 그대로 옮겼다** — 손으로 만든 모양이 아니라
/// 규범 판정으로 기대값이 확정된 국면이다(`id` 가 코퍼스 케이스 번호). 판정기와 어긋나는지는 테스트가 되묻는다.
struct GomokuRuleExample: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let black: [String]
    let white: [String]
    let point: String
    let expected: GomokuJudgement
    /// 설명용 보조 자리(거짓 3 의 전환점).
    var pivot: String? = nil

    var board: GomokuBoard {
        var board = GomokuBoard()
        for notation in black { if let p = GomokuPoint(notation: notation) { board[p] = .black } }
        for notation in white { if let p = GomokuPoint(notation: notation) { board[p] = .white } }
        return board
    }

    var marks: [GomokuPoint: GomokuBoardMark] {
        var marks: [GomokuPoint: GomokuBoardMark] = [:]
        if let p = GomokuPoint(notation: point) {
            switch expected {
            case .win: marks[p] = .win
            case .forbidden: marks[p] = .forbidden
            default: marks[p] = .legal
            }
        }
        if let pivot, let p = GomokuPoint(notation: pivot) { marks[p] = .pivot }
        return marks
    }

    /// 여섯 예시 모두 H8 을 가운데로 둔 9×9(D..L × 4..12) 안에 들어온다.
    static let cropGeometry = (originX: 3, originY: 3, lines: 9)

    static let all: [GomokuRuleExample] = [
        GomokuRuleExample(
            id: "K01", title: "3-3 금수", detail: "열린 3이 한꺼번에 두 개 생겨요",
            black: ["F8", "G8", "H6", "H7"], white: [], point: "H8",
            expected: .forbidden(.doubleThree)),
        GomokuRuleExample(
            id: "K12", title: "4-4 금수", detail: "막혀 있어도 4가 두 개면 금수예요",
            black: ["E8", "F8", "G8", "H9", "H10", "H11"], white: ["D8", "H12"], point: "H8",
            expected: .forbidden(.doubleFour)),
        GomokuRuleExample(
            id: "K19", title: "장목 금수", detail: "흑은 6개 이상 이을 수 없어요",
            black: ["E8", "F8", "G8", "I8", "J8"], white: [], point: "H8",
            expected: .forbidden(.overline)),
        GomokuRuleExample(
            id: "K24", title: "5목이 먼저", detail: "금수 모양이 함께 생겨도 5목이면 이겨요",
            black: ["D8", "E8", "F8", "G8", "H9", "H10", "I9", "J10"], white: [], point: "H8",
            expected: .win),
        GomokuRuleExample(
            id: "K28", title: "4-3은 괜찮아요", detail: "4 하나 + 3 하나는 둘 수 있어요",
            black: ["E8", "F8", "G8", "H9", "H10"], white: ["D8"], point: "H8",
            expected: .legal),
        GomokuRuleExample(
            id: "K34", title: "거짓 3", detail: "4로 만들 자리(주황)가 장목이라 가로는 3이 아니에요",
            black: ["G8", "J8", "I6", "I7", "I9", "I10", "I11", "H9", "H10"], white: [], point: "H8",
            expected: .legal, pivot: "I8")
    ]

    /// 왼쪽 설명 줄.
    static let ruleLines: [String] = [
        "흑이 먼저 둬요. 가로·세로·대각선으로 5개를 먼저 이으면 이겨요.",
        "흑만 금수가 있어요 — 3-3, 4-4, 장목(6개 이상). 흑 차례엔 금수 자리에 X가 떠요.",
        "흑은 정확히 5개여야 이기고, 백은 5개 이상이면 이겨요.",
        "5목이 되는 수는 금수 모양이 함께 생겨도 흑의 승리예요. 4-3은 금수가 아니에요.",
        "한 수에 30초. 시간이 지나면 차례인 사람이 져요.",
        "흑이 둘 곳이 없으면 차례가 백으로 넘어가고, 판이 가득 차면 무승부예요.",
        "수락하는 순간 두 사람 모두 판돈을 걸고, 이긴 사람이 두 배를 받아요. 무승부면 돌려받아요."
    ]
}

private struct GomokuRulesOverlay: View {
    let onClose: () -> Void

    static let exampleSide: CGFloat = 158

    var body: some View {
        ZStack {
            // 불투명에 가까운 스크림 — 판 위에서 규칙을 읽는 동안 뒤 화면이 비치면 글자가 안 읽힌다.
            Color.black.opacity(0.62)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(GomokuText.rulesTitle, systemImage: "book.fill")
                        .font(.title3.weight(.bold))
                    Spacer()
                    GomokuActionButton(title: GomokuText.close, icon: "xmark", style: .outline, height: 30, action: onClose)
                }
                HStack(alignment: .top, spacing: 26) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(GomokuRuleExample.ruleLines.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(CheckTheme.accent)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(CheckTheme.accent.opacity(0.18)))
                                Text(line)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(width: 300, alignment: .leading)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(Self.exampleSide), spacing: 16), count: 3),
                        alignment: .leading, spacing: 16
                    ) {
                        ForEach(GomokuRuleExample.all) { example in
                            exampleTile(example)
                        }
                    }
                }
            }
            .padding(26)
            .frame(width: 890)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(CheckTheme.panel))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        }
        .frame(width: GomokuWindowLayout.contentSize.width, height: GomokuWindowLayout.contentSize.height)
    }

    private func exampleTile(_ example: GomokuRuleExample) -> some View {
        let crop = GomokuRuleExample.cropGeometry
        return VStack(alignment: .leading, spacing: 6) {
            GomokuBoardView(
                board: example.board,
                geometry: GomokuBoardGeometry(side: Self.exampleSide, lines: crop.lines,
                                              originX: crop.originX, originY: crop.originY, insetRatio: 0.07),
                marks: example.marks,
                showsCoordinates: false
            )
            Text(example.title)
                .font(.callout.weight(.bold))
                .foregroundStyle(example.expected == .win || example.expected == .legal ? CheckTheme.working : CheckTheme.danger)
            Text(example.detail)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 28, alignment: .top)
        }
        .frame(width: Self.exampleSide, alignment: .leading)
    }
}

// MARK: - 팝오버 배너(받은 신청)

/// 팝오버 최상단 배너 — `LongSessionBanner` 와 **같은 모양**(두 줄 + 같은 폭 두 버튼, 높이 28)이다.
/// 높이도 같아야 `CheckMenuView.gomokuInviteBannerHeight` 예산이 맞는다. **초 단위 값을 그리지 않는다** —
/// 이 뷰는 팝오버 트리 안이라 시계를 읽으면 팝오버 전체가 매초 다시 그려진다(V0238 무효화 계약).
struct GomokuInviteBanner: View {
    let invite: GomokuInvite
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(GomokuText.inviteTitle(name: invite.peer.displayName))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 3) {
                        Text("판돈")
                        RubyIcon(size: 11)
                        Text("\(invite.stake) · \(GomokuText.inviteBannerSubtitle)")
                    }
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                }
                Spacer(minLength: 6)
            }
            HStack(spacing: 8) {
                Button(action: onAccept) {
                    Text(GomokuText.accept)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(CheckTheme.accent))
                }
                .buttonStyle(.plain)
                .checkTooltip("수락하고 대결 창을 열어요")
                Button(action: onDecline) {
                    Text(GomokuText.decline)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CheckTheme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(CheckTheme.accent.opacity(0.14))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CheckTheme.accent.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CheckTheme.accent.opacity(0.55), lineWidth: 1)
                )
        )
    }
}

// MARK: - 공용 조각

/// 캡슐 대신 둥근 사각 버튼(채움/외곽선). Menu·Picker 대신 쓰는 유일한 버튼 모양이다.
private struct GomokuActionButton: View {
    enum Style { case filled, outline }

    let title: String
    var icon: String? = nil
    var tint: Color = CheckTheme.accent
    var style: Style = .filled
    var height: CGFloat = 30
    var fullWidth: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: max(10, height * 0.34), weight: .bold))
                }
                Text(title)
                    .font(height >= 38 ? .callout.weight(.bold) : .caption.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(style == .filled ? Color.white : tint)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .fill(style == .filled ? tint : tint.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .stroke(tint.opacity(style == .filled ? 0 : 0.45), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private extension View {
    /// 오목 창 카드 크롬.
    func gomokuCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CheckTheme.panel.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}
