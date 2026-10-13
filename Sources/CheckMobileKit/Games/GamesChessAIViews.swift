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
// 문구는 **전부 `ChessPhoneText`**(별칭 `GamesChessText`)에서 온다 — 이 파일에 문장이 없다.
//
// ── ★ 로그인을 보지 않는다 ──
// `ChessStoreAI` 는 서버를 **한 번도 안 탄다**(판 id 머리말 "ai-" 가 서버 경로를 막고, `send` 의 AI 분기는
// `host?.session` 검사 **앞**에 선다). 그래서 입구·화면 어디에도 세션 조건이 없다. 숨기면 그 길이 막힌다 —
// `GamesChessAITests` 가 세션 nil 로 입구·판·수를 전부 되묻는다. 막는 사유 한 줄도 문구 표의
// `robotEntryBlock(signedIn:playing:)` 을 지나는데, 그 함수에 **최악의 값(false)** 을 넣어도 nil 이어야 한다.
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
// 이미 있다(`candidates.count > 1`) — 화면은 `store.promotion` 이 섰을 때만 시트를 띄우고, 닫는 길은
// 시트가 쥔 `store.cancelPromotion()` **하나뿐**이다(따로 빠져나가는 길을 만들지 않는다).
//
// ── ★ 결과 문구는 로봇 판 표를 쓴다 ──
// `ChessPhoneText.robotEndReason` 이다(1인칭 `endReason` 이 아니다) — 그 표는 루비·"상대" 를 말하므로
// 판돈이 없는 로봇 판에 쓰면 **없는 루비 변화**를 말하게 된다. 사유 열 갈래는 문구 표가 다 쥔다.
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
    /// 입구가 막힌 사유 한 줄(열려 있으면 nil). ★ 로그인은 사유가 **아니다** — 문구 표에 **최악의 값**
    /// (`signedIn: false`)을 넣어도 nil 이어야 한다(그 함수가 세션으로 가르면 여기서 빨개진다).
    package let blockReason: String?
    package let board: GamesChessAIBoardInput?
    package let humanColor: ChessColor?
    /// 로봇 쪽 사람 값(이름 "로봇" · 캐릭터 `robot` — 코어 `ChessUser.chessAI`).
    package let opponent: ChessUser?
    /// 승격 고르기 단계. **넷일 때만** 값이 선다(코어가 판정한다 — 화면은 다시 세지 않는다).
    package let promotion: ChessPromotionPrompt?
    package let isRobotThinking: Bool
    package let isInCheck: Bool
    package let plyCount: Int
    /// 둘 차례인 쪽(끝난 판은 nil). ★ **시계의 `running` 이 아니다** — 로봇 판의 로컬 시계는 화면이 안
    /// 보이면 멈추므로(`turnStartedAt = nil`) `running` 으로 차례를 그리면 그때 테두리·안내가 사라진다.
    package let turn: ChessColor?
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
        let canStart = store.canStartAIMatch
        self.canStart = canStart
        // 막히는 길은 하나뿐이다 — 이 스토어가 이미 쥔 체스 판·신청(`canStartAIMatch` 의 다섯 조건 전부).
        blockReason = canStart ? nil : ChessPhoneText.robotEntryBlock(signedIn: false, playing: .chess)
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
            turn = match.turn
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
            turn = nil
            clock = nil
            outcome = nil
            endReason = nil
            canResign = false
            canRestart = false
            matchStake = nil
        }
    }

    /// 판 아래 한 줄. 로봇 차례면 "로봇이 생각 중이에요", 아니면 문구 표의 상태 한 줄(체크 포함).
    package var statusLine: String {
        if isRobotThinking { return ChessPhoneText.robotThinking }
        return ChessPhoneText.statusLine(isMyTurn: board?.isMyTurn == true, isInCheck: isInCheck)
    }

    /// 결과 이유 — **로봇 판 표**다(1인칭 표는 루비·"상대" 를 말한다).
    package var endReasonLine: String {
        ChessPhoneText.robotEndReason(endReason, outcome: outcome)
    }
}

#if os(iOS)

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
                        Text(ChessPhoneText.robotButton)
                            .font(MobileTheme.rowTitle)
                            .foregroundStyle(chrome.canStart ? MobileTheme.label : MobileTheme.label2)
                        Text(chrome.blockReason ?? ChessPhoneText.robotButtonHelp)
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
            .accessibilityHint(ChessPhoneText.robotNoRecord)
        }
        // 판을 통째로 덮어 띄운다 — 탭 막대·로비 위에 서므로 라우팅 표를 건드리지 않는다(다른 레인의 파일이다).
        .fullScreenCover(isPresented: $isScreenPresented) {
            NavigationStack {
                GamesChessAIScreen(store: store)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            GlassCircleButton(systemImage: "xmark", accessibilityLabel: ChessPhoneText.close) {
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
            .navigationTitle(ChessPhoneText.robotButton)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: promotionBinding(chrome)) {
                if let prompt = chrome.promotion {
                    GamesChessPromotionSheet(store: store, prompt: prompt, myColor: chrome.humanColor ?? .white)
                }
            }
        // ★ 창 가시성(`ChessStore.isWindowVisible`)을 **여기서 켜지 않는다** — 배선 레인(로비·입구)의 것이다.
        //   그 깃발은 기본값이 꺼짐이고 `beginFlight` 가 맨 앞에서 그것을 보므로, 배선이 켜 주지 않으면
        //   로봇 수가 **미끄러지지 않는다**(거절이 의도된 동작이라 테스트는 초록이다 — 그래서 시험에서
        //   기준선을 갈라 두 갈래로 쟀다: `GamesChessAIBoardTests` 의 애니메이션 시험).
        //   로컬 시계도 같은 깃발을 본다(보이지 않으면 멈춘다 — 코어 `ChessStoreAI` 머리말).
    }

    /// 승격 시트는 **코어가 단계를 세웠을 때만** 뜬다(도착 칸이 같은 합법 수가 넷 — §6 ⑩).
    /// ★ 닫는 길은 시트가 쥔 `cancelPromotion()` 하나다 — 이 묶음은 그 문을 **다시 지나기만** 한다
    ///   (단계가 이미 접혔으면 아무것도 하지 않는다. 따로 빠져나가는 길을 만들지 않는다).
    private func promotionBinding(_ chrome: GamesChessAIChrome) -> Binding<Bool> {
        Binding(get: { chrome.promotion != nil }, set: { shown in
            if !shown, store.promotion != nil { store.cancelPromotion() }
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
                            Text(ChessPhoneText.robotPromptTitle)
                                .font(MobileTheme.rowTitle)
                                .foregroundStyle(MobileTheme.label)
                            Text(ChessPhoneText.robotPromptCaption)
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
                if let blocked = chrome.blockReason {
                    InlineNotice(text: blocked, kind: .warning)
                }
                if let notice = chrome.notice {
                    InlineNotice(text: notice, kind: .warning)
                }
                // ★ 로그인 없이 둘 수 있다는 사실을 글자로 둔다 — 누가 이 화면을 로그인 뒤로 옮기면
                //   **문구부터** 어긋나 눈에 띈다(문구 레인이 그 까닭으로 둔 줄이다).
                footNote(ChessPhoneText.robotNoSignIn, symbol: "person.crop.circle.badge.checkmark")
                footNote(ChessPhoneText.robotNoRecord, symbol: "cpu")
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
                Text(color == .white ? ChessPhoneText.robotPlayWhite : ChessPhoneText.robotPlayBlack)
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
        .accessibilityHint(ChessPhoneText.robotNoRecord)
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
                title: ChessPhoneText.robotResignConfirmTitle,
                message: ChessPhoneText.robotNoRecord,
                confirmTitle: ChessPhoneText.resignNow,
                cancelTitle: ChessPhoneText.keepPlaying,
                onConfirm: {
                    showsResignConfirm = false
                    Task { await store.resign() }
                },
                onCancel: { showsResignConfirm = false }
            )
        }
    }

    /// 판. **크기를 스스로 정한다**(`GeometryReader` + `aspectRatio(1, .fit)` 가 판 안에 있다) — 공간만 준다.
    /// 뒤집기·궤적·밀림 방향은 `whiteAtBottom` 한 값으로 판 안에서 끝난다(§6 ①·④).
    /// 보이스오버 한 줄만 덮어쓴다 — 판이 모르는 것(기보 수·체크)을 화면은 안다.
    @ViewBuilder
    private func board(_ chrome: GamesChessAIChrome) -> some View {
        if let board = chrome.board {
            GamesChessBoard(
                position: board.position,
                flight: store.flight,
                whiteAtBottom: board.whiteAtBottom,
                selection: board.selection,
                legalTargets: board.legalTargets,
                lastMove: board.lastMove.map { (from: $0.from, to: $0.to) },
                onTapSquare: { square in Task { await store.tap(square) } }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ChessPhoneText.boardAccessibility(
                ply: chrome.plyCount, turn: chrome.turn, inCheck: chrome.isInCheck))
        }
    }

    private func playerCard(_ chrome: GamesChessAIChrome, isMe: Bool) -> some View {
        let human = chrome.humanColor ?? .white
        let color = isMe ? human : human.opponent
        // ★ 차례는 `turn` 으로 읽는다 — 시계의 `running` 은 화면이 안 보이면 nil 이 되어 테두리가 사라진다.
        let isTurn = chrome.turn == color
        let shape = RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous)
        return HStack(spacing: MobileTheme.space3) {
            if isMe {
                GamesChessAIColorDot(color: color, size: 32)
                    .frame(width: 44, height: 44)
            } else {
                CharacterPortrait(id: chrome.opponent?.characterID, mood: .plain, size: 44)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(isMe ? ChessPhoneText.me : (chrome.opponent?.displayName ?? ChessPhoneText.robotName))
                    .font(MobileTheme.rowTitle)
                    .foregroundStyle(MobileTheme.label)
                Text(ChessPhoneText.stoneName(color))
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

    /// 남은 시간. 코어가 쥔 시계(`ChessServerClock`)를 읽기만 한다 — 폰이 세지 않는다(10분 + 한 수 3초는
    /// 서버·코어 상수의 것이고 이 화면에 숫자가 없다). 1초마다만 다시 그린다(판의 60fps 는 판 레인의 것이다).
    private func clockLabel(_ clock: ChessServerClock, color: ChessColor, isTurn: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 1, paused: clock.running == nil)) { _ in
            let remaining = clock.remainingSeconds(color, now: store.clock())
            Text(ChessPhoneText.clock(remaining))
                .font(MobileTheme.roundedNumber(.callout))
                .monospacedDigit()
                .foregroundStyle(remaining <= 10 && isTurn ? MobileTheme.danger : MobileTheme.label)
                .accessibilityLabel(ChessPhoneText.clockAccessibility(remaining))
        }
    }

    private var thinkingMark: some View {
        HStack(spacing: 4) {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
            Text(ChessPhoneText.robotThinkingShort)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(MobileTheme.accent)
        .accessibilityLabel(ChessPhoneText.robotThinking)
    }

    @ViewBuilder
    private func footLines(_ chrome: GamesChessAIChrome) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if chrome.stage == .playing {
                Text(chrome.statusLine)
                    .font(.footnote.weight(chrome.isInCheck ? .semibold : .regular))
                    .foregroundStyle(chrome.isInCheck ? MobileTheme.danger : MobileTheme.label2)
            }
            footNote(ChessPhoneText.robotNoRecord, symbol: "cpu")
            // 1:1 의 "앱을 나가도 차례 시간은 흘러요" 와 **정반대 사실**이다 — 로봇 판 시계는 떠나면 멈춘다.
            footNote(ChessPhoneText.robotClockPauses, symbol: "pause.circle")
            if let notice = chrome.notice {
                InlineNotice(text: notice, kind: .warning)
            }
        }
        .padding(.top, MobileTheme.space1)
    }

    private func footNote(_ text: String, symbol: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(MobileTheme.accent)
        }
        .font(.footnote)
        .foregroundStyle(MobileTheme.label2)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 결과 — 승/패/무 + 끝난 이유(**로봇 판 표**). 루비 줄은 없다(0 원도 움직이지 않았다).
    private func resultCard(_ chrome: GamesChessAIChrome) -> some View {
        InsetGroup {
            GroupRow(divider: .none, minHeight: MobileTheme.rowHeightTwoLine) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ChessPhoneText.outcomeTitle(chrome.outcome))
                        .font(MobileTheme.title(.title3))
                        .foregroundStyle(MobileTheme.label)
                    Text(chrome.endReasonLine)
                        .font(MobileTheme.rowSubtitle)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ChessPhoneText.robotOpponentLine)
                        .font(.caption)
                        .foregroundStyle(MobileTheme.label2)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actions(_ chrome: GamesChessAIChrome) -> some View {
        if chrome.canResign {
            AingButton(ChessPhoneText.resign, kind: .destructive, fillsWidth: true) {
                showsResignConfirm = true
            }
            .padding(.top, MobileTheme.space2)
        }
        if chrome.canRestart {
            VStack(spacing: 10) {
                AingButton(ChessPhoneText.robotRematch, kind: .filled, fillsWidth: true) {
                    store.restartAIMatch()
                }
                AingButton(ChessPhoneText.backToLobby, kind: .gray, fillsWidth: true) {
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
