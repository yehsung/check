#if os(iOS)
import CheckCore
import SwiftUI

/// 대국 화면(시안 B 09): 탭 막대 숨김 · 가운데 제목 + 판돈 부제 · 규칙 · 더보기(기권) · 상대 카드 · 판(화면 폭 − 24) · 내 카드 ·
/// 아래 반쯤 올라온 대화 서랍(판과 함께 보인다). 두 플레이어 카드는 대칭이다 — 캐릭터 초상 + 돌 배지, 차례인 쪽만 초록 테두리 + 초 링.
struct GamesGomokuMatch: View {
    let store: GamesStore
    let match: GomokuMatchState
    @Binding var showsResignConfirm: Bool
    /// 데모 스크린샷 전용 미리보기 자리(DEBUG 데모에서만 값이 온다).
    var demoPreview: GomokuPoint?

    @State private var preview = GomokuTapPreview()
    @State private var focusedForbidden: GomokuForbiddenReason?
    @State private var forbiddenMemo = GamesGomokuForbiddenMemo()
    /// 이 화면(이 판)이 나타난 시각 — [기권] 누름 가드의 기준.
    @State private var shownAt: Date?
    @State private var chatExpanded = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var gomoku: GomokuStore { store.context.gomoku }

    private var forbidden: [GomokuPoint: GomokuForbiddenReason] {
        let shows = !match.isFinished && match.myColor == .black && match.turn == .black
        return shows ? forbiddenMemo.points(for: match.board) : [:]
    }

    var body: some View {
        GeometryReader { screen in
            matchBody(visible: screen.size)
        }
    }

    private func matchBody(visible: CGSize) -> some View {
        let forbidden = forbidden
        let me = GamesMeIdentity.current(store.context)
        let previewPoint = preview.visiblePoint(match: match, isBusy: gomoku.isBusy, forbidden: forbidden)
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                GamesGomokuPlayerCard(
                    store: store, characterID: match.opponent.characterID, mood: match.opponent.mood,
                    name: match.opponent.displayName, center: match.opponent.center, isMe: false, color: match.myColor.opponent,
                    subtitle: (GomokuPhoneText.playerSubtitle(color: match.myColor.opponent, isWorking: match.opponent.isWorking), MobileTheme.label2),
                    isTurn: match.turn == match.myColor.opponent
                )
                board(side: boardSide(in: visible), forbidden: forbidden)
                GamesGomokuPlayerCard(
                    store: store, characterID: me.characterID, mood: me.mood,
                    name: me.name ?? GomokuPhoneText.me, center: nil, isMe: me.name != nil, color: match.myColor,
                    subtitle: myLine(previewPoint: previewPoint), isTurn: match.turn == match.myColor
                )
                footLines
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space1)
            .padding(.bottom, MobileTheme.space3)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .gamesDemoScrollAnchor(isDemo: store.context.isDemo)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GamesGomokuChatDrawer(store: gomoku, isExpanded: $chatExpanded)
        }
        .hidesTabBar(for: .gomokuMatch)
        .toolbar {
            ToolbarItem(placement: .principal) {
                GamesNavTitle(title: GomokuPhoneText.title) {
                    GamesStakeLine(stake: match.stake, suffix: GomokuPhoneText.stakeGainSuffix(match.stake), gemSize: 13)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                GamesGomokuRulesButton(store: gomoku)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        guard GomokuPhoneResignGuard.acceptsTap(shownAt: shownAt, now: store.context.clock.now()) else { return }
                        showsResignConfirm = true
                    } label: {
                        Label(GomokuPhoneText.resign, systemImage: "flag")
                    }
                    .disabled(match.isFinished || gomoku.isBusy)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel(GomokuPhoneText.moreMenu)
            }
        }
        .onAppear {
            shownAt = store.context.clock.now()
            if let demoPreview {
                _ = preview.tap(demoPreview, match: match, isBusy: gomoku.isBusy, forbidden: forbidden)
            }
        }
        .onChange(of: match.id) { _, _ in
            shownAt = store.context.clock.now()
            preview.clear()
            focusedForbidden = nil
        }
        .onChange(of: match.moveCount) { _, _ in focusedForbidden = nil }
        .onChange(of: demoPreview) { _, point in
            guard let point else { return }
            _ = preview.tap(point, match: match, isBusy: gomoku.isBusy, forbidden: forbidden)
        }
        // 확인은 **불투명 시트**로(`AingConfirmSheet`) — 확인 대화상자는 iOS 26 에서 화면 위쪽 말풍선으로 떠 [계속 두기]가 안 보였고,
        // 알림창은 재질이 나무판 색을 빨아들여 '기권하기' 글자가 1.9:1 이었다(w15 검증 medium 1). 시트는 카드 색을 깔아 대비가 고정된다.
        .sheet(isPresented: $showsResignConfirm) {
            AingConfirmSheet(
                title: GomokuPhoneText.resignConfirm,
                message: GomokuPhoneText.resignConfirmMessage,
                confirmTitle: GomokuPhoneText.resignNow,
                cancelTitle: GomokuPhoneText.keepPlaying,
                onConfirm: {
                    showsResignConfirm = false
                    Task { await gomoku.resign() }
                },
                onCancel: { showsResignConfirm = false }
            )
        }
    }

    // MARK: 판

    /// 판 한 장(가운데 정렬 — 기본 글자에서는 화면 폭 − 24 라 좌우 카드보다 4pt 씩 넓다).
    private func board(side: CGFloat, forbidden: [GomokuPoint: GomokuForbiddenReason]) -> some View {
        GamesGomokuPlayBoard(store: gomoku, match: match, side: side, forbidden: forbidden,
                             preview: $preview, focusedForbidden: $focusedForbidden)
            .frame(width: side, height: side)
            .shadow(color: colorScheme == .dark ? .black.opacity(0.35) : Color(red: 80 / 255, green: 50 / 255, blue: 10 / 255).opacity(0.18),
                    radius: 9, y: 6)
            .frame(maxWidth: .infinity)
    }

    /// 판 한 변. 기본 글자에서는 **화면 폭 최대**(시안 B 09)지만, 글자가 커지면 플레이어 카드 두 장이 훨씬 높아져 판과
    /// '내 차례 · 남은 초' 카드가 한 화면에 들어가지 못했다(w15 검증 medium 6). 그때만 보이는 높이에 맞춰 판을 줄인다 —
    /// 대국에서 가장 중요한 상태(내 차례·남은 초)가 판보다 먼저다.
    private func boardSide(in visible: CGSize) -> CGFloat {
        let full = max(240, visible.width - 24)
        guard visible.height > 0, typeSize >= .xLarge else { return full }
        let fraction: CGFloat = typeSize.isAccessibilitySize ? 0.40 : 0.52
        return max(240, min(full, (visible.height * fraction).rounded()))
    }

    // MARK: 내 카드 부제

    /// 우선순위: 금수 자리를 눌렀다(빨강) > 안내 한 줄(앰버) > 내 차례(초록 · 미리보기 칸) > 상대 차례(회색).
    private func myLine(previewPoint: GomokuPoint?) -> (text: String, tint: Color) {
        if let focusedForbidden { return (GomokuPhoneText.forbiddenStatus(focusedForbidden), MobileTheme.danger) }
        if let notice = gomoku.notice { return (notice, MobileTheme.pending) }
        if match.turn == match.myColor {
            return (GomokuPhoneText.myTurn + " · " + GomokuPhoneText.myTurnHint(preview: previewPoint), MobileTheme.working)
        }
        return (GomokuPhoneText.myWaitingLine(color: match.myColor), MobileTheme.label2)
    }

    /// 판 아래 작은 줄(시안 `.b-turnline`): 흑 패스 · 자동 착수 · 연속 경고 · 서버 시계 안내.
    private var footLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            if match.blackPassed {
                footLine(GomokuPhoneText.blackPassed, tint: MobileTheme.label2)
            }
            if !match.autoPoints.isEmpty {
                footLine(GomokuPhoneText.autoPlacedCount(match.autoPoints.count), tint: MobileTheme.label2)
            }
            if let warning = gomoku.autoStreakWarning {
                footLine(warning, tint: MobileTheme.danger, weight: .semibold)
            }
            Label(GomokuPhoneText.clockRunsInBackground, systemImage: "clock")
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func footLine(_ text: String, tint: Color, weight: Font.Weight = .regular) -> some View {
        Text(text)
            .font(.footnote.weight(weight))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 플레이어 카드

/// 플레이어 한 장(시안 `.b-player` — 맥 60pt 카드 문법): 캐릭터 초상 44 + 돌 배지 · 이름(+ 센터 · '나') · 부제 ·
/// 오른쪽은 차례면 초 링, 아니면 상대의 방금 한 말(말풍선 — 8초 뒤 사라진다). 차례인 카드만 초록 2pt 테두리.
struct GamesGomokuPlayerCard: View {
    let store: GamesStore
    let characterID: String?
    let mood: CharacterMood
    let name: String
    /// 센터 **화면 글자**("서울") — 코어 `GomokuUser.center` 규약.
    let center: String?
    let isMe: Bool
    let color: GomokuColor
    let subtitle: (text: String, tint: Color)
    let isTurn: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous)
        HStack(spacing: MobileTheme.space3) {
            CharacterPortrait(id: characterID, mood: mood, size: 44, badge: .stone(isBlack: color == .black))
            VStack(alignment: .leading, spacing: 1) {
                PersonName(name, center: CenterLabel.serverValue(forDisplay: center), isMe: isMe)
                Text(subtitle.text)
                    .font(MobileTheme.rowSubtitle.weight(subtitle.tint == MobileTheme.label2 ? .regular : .semibold))
                    .foregroundStyle(subtitle.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .layoutPriority(1)
            Spacer(minLength: 4)
            if isTurn {
                GamesGomokuTurnRing(store: store)
                    .frame(width: 44, height: 44)
            } else if !isMe, !typeSize.isAccessibilitySize {
                GamesGomokuSayBubble(store: store)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(shape.fill(MobileTheme.surface))
        .overlay(shape.strokeBorder(isTurn ? MobileTheme.workingDot : Color.clear, lineWidth: 2))
    }
}

/// 상대가 방금 한 말(시안 `.b-saybub`) — 대화 서랍을 보지 않아도 판 위에서 읽힌다. 8초가 지나면 사라진다.
private struct GamesGomokuSayBubble: View {
    let store: GamesStore
    static let holdSeconds: TimeInterval = 8

    var body: some View {
        let gomoku = store.context.gomoku
        if !gomoku.isMuted, let last = gomoku.chat.last(where: { !$0.isMine }) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if store.context.clock.now().timeIntervalSince(last.sentAt) < Self.holdSeconds {
                    Text(last.body)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MobileTheme.bubbleIn))
                        .accessibilityLabel("상대: " + last.body)
                }
            }
            .fixedSize()
        }
    }
}

/// 차례인 사람의 초 링(시안 `.b-ring` 44pt) — **잎 뷰**. 남은 시간은 코어가 서버 마감으로 계산한다(`remainingSeconds(now:)`).
/// 색: 넉넉하면 초록 · 10초 이하 앰버 · 5초 이하 빨강.
struct GamesGomokuTurnRing: View {
    let store: GamesStore

    var body: some View {
        let gomoku = store.context.gomoku
        TimelineView(.animation(minimumInterval: 0.2, paused: !gomoku.isWindowVisible)) { _ in
            let remaining = gomoku.remainingSeconds(now: store.context.clock.now()) ?? 0
            let total = Double(max(1, gomoku.turnSeconds))
            let fraction = min(1, max(0, remaining / total))
            let ring = remaining <= 5 ? MobileTheme.danger : (remaining <= 10 ? MobileTheme.pendingDot : MobileTheme.workingDot)
            let ink = remaining <= 5 ? MobileTheme.danger : (remaining <= 10 ? MobileTheme.pending : MobileTheme.working)
            ZStack {
                Circle().stroke(MobileTheme.fill, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(ring, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(GomokuPhoneText.remaining(remaining))
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .padding(2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GomokuPhoneText.clockAccessibility(remaining))
        }
    }
}

// MARK: - 결과

/// 결과(비평 26): 내 초상 · 결과 제목 · 끝난 이유 · 상대 · 오른쪽 루비 변화(이기면 초록 [보석]+N) · [같은 판돈으로 다시 신청 채움] [로비로 회색]
/// 같은 폭 · 승리선이 그어진 판 · 대화 서랍. 탭 막대는 대국과 같이 숨긴다.
struct GamesGomokuResult: View {
    let store: GamesStore
    let match: GomokuMatchState

    @State private var chatExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    private var gomoku: GomokuStore { store.context.gomoku }

    private var delta: Int {
        if let rubyDelta = match.rubyDelta { return rubyDelta }
        switch match.outcome {
        case .won?: return match.stake
        case .lost?: return -match.stake
        default: return 0
        }
    }

    var body: some View {
        let me = GamesMeIdentity.current(store.context)
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                resultCard(me: me)
                if let notice = gomoku.notice {
                    InlineNotice(text: notice, kind: .warning)
                }
                // 두 버튼은 같은 글자 크기·높이 — 긴 [다시 신청]은 제 폭을 갖고 [로비로]가 남은 폭을 채운다(반반으로 나누면 두 줄로 꺾이고
                // 글자가 줄었다 — 비평 26). 한 줄에 안 들어가면 위아래로.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { lobbyButton; rematchButton(fillsWidth: false).fixedSize() }
                    VStack(spacing: 10) { rematchButton(fillsWidth: true); lobbyButton }
                }
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            GamesGomokuBoardCanvas(board: match.board, geometry: GomokuPhoneBoardGeometry(side: geo.size.width),
                                                   lastMove: match.lastMove, autoPoints: match.autoPoints,
                                                   winLine: match.endReason == .five ? GomokuPhoneWinLine.ends(board: match.board, lastMove: match.lastMove) : nil)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(GomokuPhoneText.boardAccessibility(match, forbiddenCount: 0))
                        }
                    }
                    .shadow(color: colorScheme == .dark ? .black.opacity(0.35) : Color(red: 80 / 255, green: 50 / 255, blue: 10 / 255).opacity(0.18),
                            radius: 9, y: 6)
                    .padding(.horizontal, 12 - MobileTheme.sideMargin)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
            .padding(.bottom, MobileTheme.space4)
        }
        .scrollDismissesKeyboard(.interactively)
        .gamesDemoScrollAnchor(isDemo: store.context.isDemo)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GamesGomokuChatDrawer(store: gomoku, isExpanded: $chatExpanded)
        }
        .hidesTabBar(for: .gomokuMatch)
        .toolbar {
            ToolbarItem(placement: .principal) {
                GamesNavTitle(title: GomokuPhoneText.title) {
                    GamesStakeLine(stake: match.stake, suffix: GomokuPhoneText.stakeGainSuffix(match.stake), gemSize: 13)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                GamesGomokuRulesButton(store: gomoku)
            }
        }
        .sensoryFeedback(match.outcome == .won ? .success : .warning, trigger: match.id)
    }

    private func resultCard(me: GamesMeIdentity) -> some View {
        InsetGroup {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    portrait(me)
                    resultTexts
                    Spacer(minLength: 6)
                    GamesRubyDelta(delta: delta)
                }
                // 큰 글자: 초상·루비 한 줄, 글은 그 아래 — 한 줄에 몰면 "이겼어요!" 가 글자마다 꺾였다(AX 스크린샷 실측).
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) { portrait(me); Spacer(minLength: 6); GamesRubyDelta(delta: delta) }
                    resultTexts
                }
            }
            .padding(MobileTheme.cardPadding)
        }
        .accessibilityElement(children: .combine)
    }

    private func portrait(_ me: GamesMeIdentity) -> some View {
        CharacterPortrait(id: me.characterID, mood: me.mood, size: 60, badge: .stone(isBlack: match.myColor == .black))
    }

    private var resultTexts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(GomokuPhoneText.outcomeTitle(match.outcome))
                .font(MobileTheme.title(.title2))
                .foregroundStyle(MobileTheme.label)
                .fixedSize()
            Text(GomokuPhoneText.endReason(match.endReason, outcome: match.outcome))
                .font(.subheadline)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                PersonAvatar(name: match.opponent.displayName, colorSeed: match.opponent.id, url: match.opponent.avatarLink, size: 20)
                Text(GomokuPhoneText.resultOpponent(match.opponent.displayName))
                    .font(.caption)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rematchButton(fillsWidth: Bool) -> some View {
        AingButton(GomokuPhoneText.rematch, systemImage: "arrow.clockwise", kind: .filled, size: .md, fillsWidth: fillsWidth) {
            Task { await gomoku.rematch() }
        }
        .disabled(gomoku.isBusy || gomoku.outgoing != nil)
    }

    private var lobbyButton: some View {
        AingButton(GomokuPhoneText.backToLobby, kind: .gray, size: .md, fillsWidth: true) { gomoku.backToLobby() }
    }
}

/// 결과 루비 변화 — 이기면 공용 획득 문법(초록 [보석]+N)을 크게, 지면 빨강 −N, 비기면 ±0.
private struct GamesRubyDelta: View {
    let delta: Int

    var body: some View {
        HStack(spacing: 4) {
            RubyIcon(size: 24)
                .opacity(delta < 0 ? 0.5 : 1)
            Text(GomokuPhoneText.rubyDelta(delta))
                .font(MobileTheme.number(.title2, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(delta > 0 ? MobileTheme.working : (delta < 0 ? MobileTheme.danger : MobileTheme.label))
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("루비 \(GomokuPhoneText.rubyDelta(delta))")
    }
}
#endif
