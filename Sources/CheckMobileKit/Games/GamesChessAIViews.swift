import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 "로봇과 두기"(체스 AI) — 가장 작은 레인이지만 **비로그인 사용자의 유일한 체스 길**이다
// (인수인계 §6 ⑫ · §7 "로봇과 두기: 색 고르기(백/흑) → 바로 시작. 판돈 없음, 순위에 안 들어감").
//
// ── 이 파일이 가진 것 둘 ──
//  ① `GamesChessAISection(store:)` — 로비 안 입구(맥 머리글 [로봇과 두기] 와 같은 자리).
//  ② `GamesChessAIScreen(store:)` — 색 고르기 → 판 → 결과.
// 규칙·판·시계·AI·애니메이션은 **전부 코어**다(`ChessStoreAI` · `ChessAIEngine` · `ChessStore.flight`).
// 이 파일은 코어를 한 줄도 고치지 않고, 코어가 이미 세워 둔 값을 화면에 옮기기만 한다.
//
// ── ★ 로그인을 보지 않는다 ──
// `ChessStoreAI` 는 서버를 **한 번도 안 탄다**(판 id 머리말 "ai-" 가 서버 경로를 막고, `send` 의 AI 분기는
// `host?.session` 검사 **앞**에 선다). 그래서 입구·화면 어디에도 세션 조건이 없다. 숨기면 그 길이 막힌다 —
// `GamesChessAITests` 가 세션 nil 로 입구·판·수를 전부 되묻는다.
//
// ── ★ 판 방향은 한 값만 지난다 ──
// 뒤집기는 `GamesChessAIBoardInput.whiteAtBottom` **한 줄**에서 나와 `GamesChessBoard` 로 넘어간다.
// 이 파일에 화면 좌표를 계산하는 자리를 만들면 **흑으로 두는 사람만** 틀어진다(§6 ①). 소스 계약 시험이
// 뷰 구역에 뒤집기 산술이 없는 것을 못 박는다.
//
// ── ★ 합법 수는 스토어가 쥔 한 칸만 읽는다 ──
// 로봇 판은 로컬 `ChessRules` 가, 1:1 은 서버가 `legal_moves` 를 채운다. 맥은 그 두 길을 `match.legalMoves`
// 한 칸으로 합쳐 뒀다(§6 ②) — 화면은 어느 쪽인지 **알려 하지 않는다**. 이 파일은 `ChessRules` 를 부르지 않는다.
//
// ── ★ 승격은 2단 ──
// 도착 칸이 같은 합법 수가 넷이면 승격이고 그때만 네 말을 묻는다. 그 판정은 코어 `commit(from:to:)` 에
// 이미 있다(`candidates.count > 1`) — 화면은 `store.promotion` 이 섰을 때만 시트를 띄운다. 여기서 다시 세지 않는다.
//
// ── ★ 애니메이션은 스토어에 이미 붙어 있다 ──
// 로봇 수는 서버를 안 타므로 즉시 미끄러진다. `ChessStore.flight` 가 `commitAIGame` 깔때기에 붙어 있어
// 화면은 그 값을 `GamesChessBoard` 에 **넘기기만** 한다(스토어를 건드리지 않는다 — §5).

// MARK: - 판정 표 (플랫폼 무관 — 폰 뷰는 맥 스위트가 못 보므로 재는 자리는 전부 여기다)

/// `GamesChessBoard` 한 번을 그리는 데 필요한 값 묶음. **판 인자가 여기서 한 번 만들어진다.**
package struct GamesChessAIBoardInput: Equatable, Sendable {
    package let position: ChessPosition
    /// ★ 이 레인에서 **판 방향을 아는 유일한 값**(§6 ①). 내 색이 아래다 — 흑을 고르면 false.
    package let whiteAtBottom: Bool
    /// 고른 말의 출발 칸.
    package let selection: ChessSquare?
    /// 고른 말이 갈 수 있는 칸. **스토어가 채운 한 칸**(`ChessSelection.targets`)만 읽는다 — 로봇 판은
    /// 로컬 규칙, 1:1 은 서버가 채웠고 화면은 그 차이를 모른다(§6 ②).
    package let legalTargets: Set<ChessSquare>
    package let lastMove: ChessMove?
    /// 지금 사람이 둘 차례인가(탭을 받을 수 있는가).
    package let isMyTurn: Bool

    /// 판을 읽을 수 없으면(서버·FEN 결함) nil — 그때는 판을 그리지 않는다.
    package init?(match: ChessMatchState, selection: ChessSelection?) {
        guard let position = match.position else { return nil }
        self.position = position
        self.whiteAtBottom = match.myColor == .white
        self.selection = selection?.from
        self.legalTargets = selection?.targets ?? []
        self.lastMove = match.lastMove
        self.isMyTurn = match.isMyTurn
    }
}

/// 로봇 판 입구·화면이 읽는 **유일한 판정 표**(오목 `GomokuPhoneMatchChrome` 와 같은 자리).
/// 뷰는 이 표만 읽는다 — 화면이 스스로 판정하는 자리를 두지 않는다.
package struct GamesChessAIChrome: Equatable, Sendable {
    package enum Stage: Equatable, Sendable {
        /// 색 고르기(백/흑) — 로봇 판이 없을 때.
        case colorPick
        case playing
        case result
    }

    /// ★ **로봇 판은 로그인을 보지 않는다**(§6 ⑫). 기본값도 값으로 재라 — 이 세 줄이 이 레인의 계약이고
    ///   `GamesChessAITests` 가 결과로 되묻는다(세션 nil 에서 입구가 열리고 판이 시작되고 수가 들어간다).
    package static let requiresSignIn = false
    /// 판돈 없음 — 걸린 루비가 0 이고 신청·정산 왕복이 아예 없다.
    package static let stake = 0
    /// 순위에 안 들어간다 — 로봇 판은 서버에 없다.
    package static let entersRanking = false

    package let stage: Stage
    /// 입구를 누를 수 있는가(코어 `canStartAIMatch` — 1:1 판·보낸 신청이 떠 있으면 닫힌다).
    package let canStart: Bool
    package let board: GamesChessAIBoardInput?
    package let humanColor: ChessColor?
    /// 로봇 쪽 사람 값(이름 "로봇" · 캐릭터 `robot` — 코어 `ChessUser.chessAI`).
    package let opponent: ChessUser?
    /// 승격 고르기 단계. **넷일 때만** 값이 선다(코어가 판정한다 — 화면은 다시 세지 않는다).
    package let promotion: ChessPromotionPrompt?
    package let isRobotThinking: Bool
    package let isInCheck: Bool
    package let plyCount: Int
    package let clock: ChessServerClock?
    package let outcome: ChessMatchOutcome?
    package let endReason: ChessEndReason?
    package let canResign: Bool
    package let canRestart: Bool
    package let notice: String?
    /// 들고 있는 로봇 판의 판돈. **0 이어야 한다** — 시험이 이 값을 읽는다(없으면 nil).
    package let matchStake: Int?

    @MainActor
    package init(store: ChessStore) {
        // 로봇 판만 본다. 1:1 판이 열려 있으면 그 판은 이 화면의 것이 아니다(코어가 로봇 판을 이미 버렸다).
        let match = store.isAIMatch ? store.match : nil
        canStart = store.canStartAIMatch
        notice = store.notice
        if let match {
            stage = match.isFinished ? .result : .playing
            board = GamesChessAIBoardInput(match: match, selection: store.selection)
            humanColor = match.myColor
            opponent = match.opponent
            promotion = store.promotion
            isRobotThinking = store.isAIThinking
            isInCheck = match.isInCheck
            plyCount = match.plyCount
            clock = match.clock
            outcome = match.outcome
            endReason = match.endReason
            canResign = !match.isFinished
            canRestart = match.isFinished
            matchStake = match.stake
        } else {
            stage = .colorPick
            board = nil
            humanColor = nil
            opponent = nil
            promotion = nil
            isRobotThinking = false
            isInCheck = false
            plyCount = 0
            clock = nil
            outcome = nil
            endReason = nil
            canResign = false
            canRestart = false
            matchStake = nil
        }
    }
}

/// 이 레인의 문구. ★ **전부 `GamesChessText` 로 옮길 목록**이다(그 표가 아직 없어 여기 둔다 —
/// 인수인계 §7 의 짝 맞추기에서 `GamesChessText` 가 서면 이 enum 을 지우고 이름을 그 표의 것으로 바꾼다).
/// 사용자 어휘만 쓴다 — 진단·규격 번호를 싣지 않는다. 겹치는 것은 코어 `ChessNoticeText` 를 그대로 쓴다.
enum GamesChessAIText {
    static let title = "로봇과 두기"
    static let entryHelp = "기기와 한 판 둬요 (루비가 걸리지 않아요)"
    static let colorTitle = "어느 색으로 둘까요"
    static let playWhite = "백(선공)"
    static let playBlack = "흑(후공)"
    static let noRecord = "로봇과 둔 판은 순위·루비에 들어가지 않아요"
    static let thinking = "생각 중"
    static let thinkingShort = "생각 중"
    static let myTurn = "내 차례예요"
    static let inCheck = "체크! 왕을 피하세요"
    static let resign = "기권"
    static let resignConfirm = "기권할까요?"
    static let keepPlaying = "계속 두기"
    static let playAgain = "다시 두기"
    static let quit = "그만두기"
    static let me = "나"
    static let promotionTitle = "승격할 말을 고르세요"
    /// 로봇 판 시계는 **로컬**이다 — 화면을 떠나면 멈춘다(1:1 은 서버에서 흐른다).
    static let clockPauses = "화면을 떠나면 시계가 멈춰요"

    static func color(_ color: ChessColor) -> String { color == .white ? "백" : "흑" }

    static func moveCount(_ ply: Int) -> String { "\(ply)수" }

    static func outcome(_ outcome: ChessMatchOutcome?) -> String {
        switch outcome {
        case .won?: return "이겼어요"
        case .lost?: return "졌어요"
        case .draw?: return "무승부예요"
        case nil: return "대국이 끝났어요"
        }
    }

    /// 끝난 이유. ★ `timeout_insufficient` 는 **FIDE 6.9** 다 — "시간이 다 됐지만 무승부" 를 말해야 한다(§6 ③).
    static func endReason(_ reason: ChessEndReason?) -> String {
        switch reason {
        case .checkmate?: return "외통수"
        case .resign?: return "기권"
        case .timeout?: return "시간이 다 됐어요"
        case .timeoutInsufficient?: return "시간이 다 됐지만 무승부예요"
        case .stalemate?: return "둘 곳이 없어요"
        case .fiftyMove?: return "50수 동안 잡기·폰 이동이 없었어요"
        case .threefold?: return "같은 국면이 세 번 나왔어요"
        case .insufficientMaterial?: return "메이트할 기물이 없어요"
        case .agreement?: return "무승부에 합의했어요"
        case .abandoned?: return "대국이 중단됐어요"
        case nil: return ""
        }
    }

    static func piece(_ kind: ChessPieceKind) -> String {
        switch kind {
        case .queen: return "퀸"
        case .rook: return "룩"
        case .bishop: return "비숍"
        case .knight: return "나이트"
        case .pawn: return "폰"
        case .king: return "킹"
        }
    }

    /// 시계 글자 — `mm:ss`, 10초 아래는 `s.d`(맥 `ChessText.clock` 과 같은 눈금).
    static func clock(_ seconds: Double) -> String {
        let safe = max(0, seconds)
        if safe < 10 { return String(format: "%.1f", safe) }
        let whole = Int(safe.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

#if os(iOS)

// MARK: - ★ 자리표시 — 다른 레인이 내놓으면 이 블록을 **통째로 지운다**
//
// 이름·서명은 지시받은 그대로 두었다(`GamesChessBoard` · `GamesChessBoardMetrics.side(fitting:)` ·
// `GamesChessSheets` 의 승격 고르기). 병합 때 이 블록만 지우면 호출부는 그대로 선다.
//  · 판 자리표시는 **애니메이션을 그리지 않는다**(`flight` 를 받기만 한다) — 세 겹 그리기·TimelineView 는 판 레인의 것이다.
//  · 승격 시트의 **정확한 이름은 추측**이다(`GamesChessSheets.Promotion(store:prompt:)`) — 그 레인의 것으로 바꿔라.

/// 판 한 변(화면에 맞춘 길이).
enum GamesChessBoardMetrics {
    static func side(fitting size: CGSize) -> CGFloat {
        max(0, min(size.width, size.height))
    }
}

/// 판. 자리표시는 칸·말 글자·탭만 있다.
struct GamesChessBoard: View {
    let position: ChessPosition
    let flight: ChessMoveFlight?
    let whiteAtBottom: Bool
    let selection: ChessSquare?
    let legalTargets: Set<ChessSquare>
    let lastMove: ChessMove?
    let onTapSquare: (ChessSquare) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { column in
                        cell(row: row, column: column)
                    }
                }
            }
        }
        .background(MobileTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous))
    }

    @ViewBuilder
    private func cell(row: Int, column: Int) -> some View {
        // 자리표시의 화면 좌표 계산 — 판 레인이 들어오면 이 산술은 사라진다.
        let file = whiteAtBottom ? column : 7 - column
        let rank = whiteAtBottom ? 7 - row : row
        if let square = ChessSquare(file: file, rank: rank) {
            let piece = position[square]
            Button {
                onTapSquare(square)
            } label: {
                Text(piece.map { String($0.kind.fenLetter) } ?? " ")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(piece?.color == .black ? MobileTheme.label : MobileTheme.label3Text)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(background(square))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(square.notation)
        }
    }

    private func background(_ square: ChessSquare) -> Color {
        if selection == square { return MobileTheme.accentTint }
        if legalTargets.contains(square) { return MobileTheme.workingTint }
        if lastMove?.from == square || lastMove?.to == square { return MobileTheme.pendingTint }
        return square.isLightSquare ? MobileTheme.surface2 : MobileTheme.fill
    }
}

/// 체스 시트 모음.
enum GamesChessSheets {
    /// 승격 고르기 — 네 말(Q R B N, `ChessPieceKind.promotionChoices` 순서 그대로).
    struct Promotion: View {
        let store: ChessStore
        let prompt: ChessPromotionPrompt

        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(spacing: 0) {
                SheetHeader(GamesChessAIText.promotionTitle, onClose: { dismiss() })
                HStack(spacing: 10) {
                    ForEach(prompt.choices, id: \.rawValue) { kind in
                        Button {
                            Task { await store.choosePromotion(kind) }
                        } label: {
                            VStack(spacing: 6) {
                                Text(String(kind.fenLetter))
                                    .font(.system(size: 24, weight: .bold, design: .serif))
                                Text(GamesChessAIText.piece(kind))
                                    .font(.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 84)
                            .background(RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
                                .fill(MobileTheme.surface))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                Spacer(minLength: 0)
            }
            .background(MobileTheme.background.ignoresSafeArea())
            .presentationDetents([.height(220)])
        }
    }
}

// MARK: - 입구 (로비 안)

/// 로비 안 [로봇과 두기] 입구. 맥은 로비 머리글에만 세운다(대국 중에 새 판을 열 길을 두지 않는다) — 폰도 로비에만 있다.
///
/// ★ **로그인을 보지 않는다**(§6 ⑫). 비활성은 코어 `canStartAIMatch` 하나로만 갈린다 —
///   1:1 판이 열려 있거나 보낸 신청이 떠 있을 때다(수락되는 순간 1:1 이 로봇 판을 이기므로).
struct GamesChessAISection: View {
    let store: ChessStore

    @State private var isScreenPresented = false

    var body: some View {
        let chrome = GamesChessAIChrome(store: store)
        InsetGroup {
            Button {
                isScreenPresented = true
            } label: {
                GroupRow(divider: .none, minHeight: MobileTheme.rowHeightTwoLine) {
                    CharacterPortrait(id: ChessUser.chessAI.characterID, mood: .plain, size: 36)
                        .opacity(chrome.canStart ? 1 : 0.5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(GamesChessAIText.title)
                            .font(MobileTheme.rowTitle)
                            .foregroundStyle(chrome.canStart ? MobileTheme.label : MobileTheme.label2)
                        Text(GamesChessAIText.entryHelp)
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if chrome.canStart {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MobileTheme.label3)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            .disabled(!chrome.canStart)
            .accessibilityHint(GamesChessAIText.noRecord)
        }
        // 판을 통째로 덮어 띄운다 — 탭 막대·로비 위에 서므로 라우팅 표를 건드리지 않는다(다른 레인의 파일이다).
        .fullScreenCover(isPresented: $isScreenPresented, onDismiss: {
            // 내가 끈 것을 되돌린다: 덮는 동안 멈춰 둔 폴링을 로비에 돌려준다.
            store.windowOcclusionDidChange(visible: true)
        }) {
            NavigationStack {
                GamesChessAIScreen(store: store)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            GlassCircleButton(systemImage: "xmark", accessibilityLabel: SheetChromeText.close) {
                                isScreenPresented = false
                            }
                        }
                    }
            }
        }
    }
}

// MARK: - 화면 (색 고르기 → 판 → 결과)

/// 로봇과 두는 한 판. 색을 고르면 **바로 시작**한다(걸 것이 없어 확인 단계를 두지 않는다 — 맥과 같다).
/// 판돈 줄·순위·기보 열·무승부 제안·대화는 없다(상대가 사람이 아니고 걸린 루비가 없다).
struct GamesChessAIScreen: View {
    let store: ChessStore

    @State private var showsResignConfirm = false

    var body: some View {
        let chrome = GamesChessAIChrome(store: store)
        content(chrome)
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(GamesChessAIText.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: promotionBinding(chrome)) {
                if let prompt = chrome.promotion {
                    GamesChessSheets.Promotion(store: store, prompt: prompt)
                }
            }
            .onAppear {
                // 로컬 시계는 **보이는 동안만** 돈다(기다리는 상대가 없다 — 코어 `ChessStoreAI` 머리말).
                // ★ `windowDidShow()` 를 부르지 않는다 — 그 문은 로비·판 재조회를 쏜다(로봇 판의 일이 아니다).
                store.isWindowVisible = true
                store.windowOcclusionDidChange(visible: true)
            }
            .onDisappear {
                store.windowOcclusionDidChange(visible: false)
            }
    }

    /// 승격 시트는 **코어가 단계를 세웠을 때만** 뜬다(도착 칸이 같은 합법 수가 넷 — §6 ⑩).
    /// 손으로 닫으면 그 단계를 접는다(고르기는 남는다 — 다른 칸을 눌러 보려는 뜻이다).
    private func promotionBinding(_ chrome: GamesChessAIChrome) -> Binding<Bool> {
        Binding(get: { chrome.promotion != nil }, set: { shown in
            if !shown { store.cancelPromotion() }
        })
    }

    @ViewBuilder
    private func content(_ chrome: GamesChessAIChrome) -> some View {
        switch chrome.stage {
        case .colorPick:
            colorPick(chrome)
        case .playing, .result:
            match(chrome)
        }
    }

    // MARK: 색 고르기

    private func colorPick(_ chrome: GamesChessAIChrome) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                InsetGroup {
                    GroupRow(divider: .none, minHeight: MobileTheme.rowHeightTwoLine) {
                        CharacterPortrait(id: ChessUser.chessAI.characterID, mood: .plain, size: 44)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(GamesChessAIText.colorTitle)
                                .font(MobileTheme.rowTitle)
                                .foregroundStyle(MobileTheme.label)
                            Text(GamesChessAIText.noRecord)
                                .font(MobileTheme.rowSubtitle)
                                .foregroundStyle(MobileTheme.label2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
                HStack(spacing: 10) {
                    colorOption(.white, enabled: chrome.canStart)
                    colorOption(.black, enabled: chrome.canStart)
                }
                if !chrome.canStart {
                    InlineNotice(text: ChessNoticeText.busy, kind: .warning)
                }
                if let notice = chrome.notice {
                    InlineNotice(text: notice, kind: .warning)
                }
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
            .padding(.bottom, MobileTheme.space4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func colorOption(_ color: ChessColor, enabled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
        return Button {
            store.startAIMatch(humanColor: color)
        } label: {
            VStack(spacing: 8) {
                GamesChessAIColorDot(color: color, size: 30)
                Text(color == .white ? GamesChessAIText.playWhite : GamesChessAIText.playBlack)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(enabled ? MobileTheme.label : MobileTheme.label2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(shape.fill(MobileTheme.surface))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityHint(GamesChessAIText.noRecord)
    }

    // MARK: 판 · 결과

    private func match(_ chrome: GamesChessAIChrome) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.space2) {
                if chrome.stage == .result {
                    resultCard(chrome)
                }
                playerCard(chrome, isMe: false)
                board(chrome)
                playerCard(chrome, isMe: true)
                footLines(chrome)
                actions(chrome)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space1)
            .padding(.bottom, MobileTheme.space4)
        }
        .scrollBounceBehavior(.basedOnSize)
        // 확인은 **불투명 시트**로(`AingConfirmSheet`) — 알림창·확인 대화상자는 재질이 뒤 색을 빨아들여 글자 대비가
        // 1.9:1 까지 떨어졌다(w15 검증 medium 1 · 오목이 같은 자리에서 데였다).
        .sheet(isPresented: $showsResignConfirm) {
            AingConfirmSheet(
                title: GamesChessAIText.resignConfirm,
                message: GamesChessAIText.noRecord,
                confirmTitle: GamesChessAIText.resign,
                cancelTitle: GamesChessAIText.keepPlaying,
                onConfirm: {
                    showsResignConfirm = false
                    Task { await store.resign() }
                },
                onCancel: { showsResignConfirm = false }
            )
        }
    }

    @ViewBuilder
    private func board(_ chrome: GamesChessAIChrome) -> some View {
        if let board = chrome.board {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { geo in
                        let side = GamesChessBoardMetrics.side(fitting: geo.size)
                        GamesChessBoard(
                            position: board.position,
                            flight: store.flight,
                            whiteAtBottom: board.whiteAtBottom,
                            selection: board.selection,
                            legalTargets: board.legalTargets,
                            lastMove: board.lastMove,
                            onTapSquare: { square in Task { await store.tap(square) } }
                        )
                        .frame(width: side, height: side)
                    }
                }
        }
    }

    private func playerCard(_ chrome: GamesChessAIChrome, isMe: Bool) -> some View {
        let human = chrome.humanColor ?? .white
        let color = isMe ? human : human.opponent
        let isTurn = chrome.clock?.running == color
        let shape = RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous)
        return HStack(spacing: MobileTheme.space3) {
            if isMe {
                GamesChessAIColorDot(color: color, size: 32)
                    .frame(width: 44, height: 44)
            } else {
                CharacterPortrait(id: chrome.opponent?.characterID, mood: .plain, size: 44)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(isMe ? GamesChessAIText.me : (chrome.opponent?.displayName ?? GamesChessAIText.title))
                    .font(MobileTheme.rowTitle)
                    .foregroundStyle(MobileTheme.label)
                Text(GamesChessAIText.color(color))
                    .font(MobileTheme.rowSubtitle)
                    .foregroundStyle(MobileTheme.label2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            if !isMe, chrome.isRobotThinking {
                // 로봇 차례에는 마감이 없다 — 시계 자리에 "생각 중"(맥 상태줄과 같은 말).
                thinkingMark
            } else if let clock = chrome.clock {
                clockLabel(clock, color: color, isTurn: isTurn)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(shape.fill(MobileTheme.surface))
        .overlay(shape.strokeBorder(isTurn ? MobileTheme.workingDot : Color.clear, lineWidth: 2))
    }

    /// 남은 시간. 코어가 쥔 시계(`ChessServerClock`)를 읽기만 한다 — 폰이 세지 않는다.
    /// 1초마다만 다시 그린다(판 애니메이션의 60fps 는 `GamesChessBoard` 의 것이다).
    private func clockLabel(_ clock: ChessServerClock, color: ChessColor, isTurn: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 1, paused: clock.running == nil)) { _ in
            let remaining = clock.remainingSeconds(color, now: store.clock())
            Text(GamesChessAIText.clock(remaining))
                .font(MobileTheme.roundedNumber(.callout))
                .monospacedDigit()
                .foregroundStyle(remaining <= 10 && isTurn ? MobileTheme.danger : MobileTheme.label)
        }
    }

    private var thinkingMark: some View {
        HStack(spacing: 4) {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
            Text(GamesChessAIText.thinkingShort)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(MobileTheme.accent)
        .accessibilityLabel(GamesChessAIText.thinking)
    }

    @ViewBuilder
    private func footLines(_ chrome: GamesChessAIChrome) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if chrome.stage == .playing {
                Text(turnLine(chrome))
                    .font(.footnote.weight(chrome.isInCheck ? .semibold : .regular))
                    .foregroundStyle(chrome.isInCheck ? MobileTheme.danger : MobileTheme.label2)
            }
            Label {
                Text(GamesChessAIText.noRecord)
            } icon: {
                Image(systemName: "cpu").foregroundStyle(MobileTheme.accent)
            }
            .font(.footnote)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
            Text(GamesChessAIText.clockPauses + " · " + GamesChessAIText.moveCount(chrome.plyCount))
                .font(.caption)
                .foregroundStyle(MobileTheme.label2)
            if let notice = chrome.notice {
                InlineNotice(text: notice, kind: .warning)
            }
        }
        .padding(.top, MobileTheme.space1)
    }

    private func turnLine(_ chrome: GamesChessAIChrome) -> String {
        if chrome.isInCheck, chrome.board?.isMyTurn == true { return GamesChessAIText.inCheck }
        if chrome.isRobotThinking { return GamesChessAIText.thinking }
        return chrome.board?.isMyTurn == true ? GamesChessAIText.myTurn : ChessNoticeText.notYourTurn
    }

    /// 결과 — 승/패/무 + 끝난 이유. **루비 변화는 싣지 않는다**(0 원도 움직이지 않았다).
    private func resultCard(_ chrome: GamesChessAIChrome) -> some View {
        InsetGroup {
            GroupRow(divider: .none, minHeight: MobileTheme.rowHeightTwoLine) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(GamesChessAIText.outcome(chrome.outcome))
                        .font(MobileTheme.title(.title3))
                        .foregroundStyle(MobileTheme.label)
                    Text(GamesChessAIText.endReason(chrome.endReason))
                        .font(MobileTheme.rowSubtitle)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actions(_ chrome: GamesChessAIChrome) -> some View {
        if chrome.canResign {
            AingButton(GamesChessAIText.resign, kind: .destructive, fillsWidth: true) {
                showsResignConfirm = true
            }
            .padding(.top, MobileTheme.space2)
        }
        if chrome.canRestart {
            VStack(spacing: 10) {
                AingButton(GamesChessAIText.playAgain, kind: .filled, fillsWidth: true) {
                    store.restartAIMatch()
                }
                AingButton(GamesChessAIText.quit, kind: .gray, fillsWidth: true) {
                    store.backToLobby()
                }
            }
            .padding(.top, MobileTheme.space2)
        }
    }
}

/// 색 점 하나(맥 `ChessColorDot` 과 같은 자리) — 사람·로봇 카드와 색 고르기 타일이 함께 쓴다.
private struct GamesChessAIColorDot: View {
    let color: ChessColor
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color == .white ? Color.white : Color.black)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(MobileTheme.separator, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
#endif
