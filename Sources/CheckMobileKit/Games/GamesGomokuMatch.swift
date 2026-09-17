#if os(iOS)
import CheckCore
import SwiftUI

/// 대국 화면: 상대 줄 · 판(폭에 맞춤) · 나 줄 · 상태줄 · 판돈 · 채팅 · 기권.
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

    private var gomoku: GomokuStore { store.context.gomoku }

    private var forbidden: [GomokuPoint: GomokuForbiddenReason] {
        let shows = !match.isFinished && match.myColor == .black && match.turn == .black
        return shows ? forbiddenMemo.points(for: match.board) : [:]
    }

    var body: some View {
        let forbidden = forbidden
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                GamesGomokuPlayerStrip(store: store, name: match.opponent.displayName, avatarURL: match.opponent.avatarURL,
                                  center: match.opponent.center, color: match.myColor.opponent,
                                  isTurn: match.turn == match.myColor.opponent, isMe: false)
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            GamesGomokuPlayBoard(store: gomoku, match: match, side: geo.size.width, forbidden: forbidden,
                                            preview: $preview, focusedForbidden: $focusedForbidden)
                        }
                    }
                GamesGomokuPlayerStrip(store: store, name: GomokuPhoneText.me, avatarURL: nil, center: nil,
                                  color: match.myColor, isTurn: match.turn == match.myColor, isMe: true)
                statusBox
                stakeLine
                GamesGomokuChatCard(store: gomoku)
                resignButton
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.rowSpacing)
        }
        .scrollDismissesKeyboard(.interactively)
        .gamesDemoScrollAnchor(isDemo: store.context.isDemo)
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
        // 확인은 알림창으로 — iOS 26 의 확인 대화상자는 화면 위쪽 말풍선으로 떠 [계속 두기]가 안 보였다(데모 스크린샷 실측).
        .alert(GomokuPhoneText.resignConfirm, isPresented: $showsResignConfirm) {
            Button(GomokuPhoneText.resignNow, role: .destructive) {
                Task { await gomoku.resign() }
            }
            Button(GomokuPhoneText.keepPlaying, role: .cancel) {}
        }
    }

    // MARK: 상태줄

    private var statusLine: (text: String, tint: Color) {
        if let focusedForbidden { return (GomokuPhoneText.forbiddenStatus(focusedForbidden), MobileTheme.danger) }
        if let notice = gomoku.notice { return (notice, MobileTheme.pending) }
        if match.turn == match.myColor { return (GomokuPhoneText.myTurn, MobileTheme.working) }
        return (GomokuPhoneText.opponentTurn, MobileTheme.secondaryText)
    }

    private var statusBox: some View {
        let line = statusLine
        return VStack(alignment: .leading, spacing: 4) {
            Text(line.text)
                .font(.headline)
                .foregroundStyle(line.tint)
                .fixedSize(horizontal: false, vertical: true)
            if match.turn == match.myColor, gomoku.notice == nil, focusedForbidden == nil {
                Text(GomokuPhoneText.placeHint)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if match.blackPassed {
                Text(GomokuPhoneText.blackPassed)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !match.autoPoints.isEmpty {
                Text(GomokuPhoneText.autoPlacedCount(match.autoPoints.count))
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let warning = gomoku.autoStreakWarning {
                Text(warning)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(MobileTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(line.tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(line.tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var stakeLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(GomokuPhoneText.stakeTitle)
                    .foregroundStyle(MobileTheme.secondaryText)
                Image(systemName: "diamond.fill")
                    .foregroundStyle(MobileTheme.ruby)
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(GomokuPhoneText.stakeLine(match.stake))
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.primaryText)
            }
            .font(.subheadline.weight(.semibold))
            Label(GomokuPhoneText.clockRunsInBackground, systemImage: "clock")
                .font(.footnote)
                .foregroundStyle(MobileTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var resignButton: some View {
        Button {
            guard GomokuPhoneResignGuard.acceptsTap(shownAt: shownAt, now: store.context.clock.now()) else { return }
            showsResignConfirm = true
        } label: {
            Label(GomokuPhoneText.resign, systemImage: "flag")
        }
        .buttonStyle(GamesCompactButtonStyle(kind: .destructive, fillsWidth: true))
        .disabled(match.isFinished || gomoku.isBusy)
        .accessibilityHint(GomokuPhoneText.resignConfirm)
    }
}

// MARK: - 사람 줄

/// 두 사람 줄: 얼굴 · 이름(+나) · 센터 · 돌 · (차례면) 30초 링. 나 줄은 루비도.
struct GamesGomokuPlayerStrip: View {
    let store: GamesStore
    let name: String
    let avatarURL: String?
    let center: String?
    let color: GomokuColor
    let isTurn: Bool
    let isMe: Bool

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(name: name, url: avatarURL.flatMap(URL.init(string:)), size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.body.weight(.bold))
                        .foregroundStyle(MobileTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if !isMe { CenterBadge(CenterLabel.serverValue(forDisplay: center)) }
                    if isMe {
                        RubyLabel(store.rubyBalance, style: .footnote)
                    }
                }
                HStack(spacing: 6) {
                    GamesGomokuStoneDot(color: color, size: 14)
                    Text(GomokuPhoneText.stoneName(color))
                        .font(.caption)
                        .foregroundStyle(MobileTheme.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 6)
            if isTurn {
                GamesGomokuTurnRing(store: store)
                    .frame(width: 48, height: 48)
            } else {
                Color.clear.frame(width: 48, height: 48)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: MobileTheme.cardRadius, style: .continuous)
                .fill(isTurn ? MobileTheme.accent.opacity(0.12) : MobileTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MobileTheme.cardRadius, style: .continuous)
                .stroke(isTurn ? MobileTheme.accent.opacity(0.6) : MobileTheme.separator, lineWidth: isTurn ? 1.5 : 1)
        )
    }
}

struct GamesGomokuStoneDot: View {
    let color: GomokuColor
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: color == .black ? [Color(white: 0.45), Color(white: 0.05)] : [Color.white, Color(white: 0.78)],
                center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size))
            .overlay(Circle().stroke(Color.black.opacity(color == .white ? 0.35 : 0), lineWidth: 0.5))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 차례인 사람의 30초 링 — **잎 뷰**. 남은 시간은 코어가 서버 마감으로 계산한다(`remainingSeconds(now:)`).
struct GamesGomokuTurnRing: View {
    let store: GamesStore

    var body: some View {
        let gomoku = store.context.gomoku
        TimelineView(.animation(minimumInterval: 0.2, paused: !gomoku.isWindowVisible)) { _ in
            let remaining = gomoku.remainingSeconds(now: store.context.clock.now()) ?? 0
            let total = Double(max(1, gomoku.turnSeconds))
            let fraction = min(1, max(0, remaining / total))
            let tint = remaining <= 5 ? MobileTheme.danger : (remaining <= 10 ? MobileTheme.pending : MobileTheme.working)
            ZStack {
                Circle().stroke(MobileTheme.track, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(GomokuPhoneText.remaining(remaining))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.7)
            }
            .padding(3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GomokuPhoneText.clockAccessibility(remaining))
        }
    }
}

// MARK: - 결과

struct GamesGomokuResult: View {
    let store: GamesStore
    let match: GomokuMatchState

    @Environment(\.dynamicTypeSize) private var typeSize

    private var gomoku: GomokuStore { store.context.gomoku }

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
        case .won?: return MobileTheme.working
        case .lost?: return MobileTheme.danger
        default: return MobileTheme.offWork
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
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                resultCard
                if let notice = gomoku.notice {
                    InlineNotice(text: notice, kind: .warning)
                }
                // 기본 글자에서만 한 줄 — 커지면 위아래로(가로 둘로 나누면 "같은 판돈으로 다…" 로 잘렸다, XXL 스크린샷 실측).
                if typeSize <= .large {
                    HStack(spacing: 10) { rematchButton; lobbyButton }
                } else {
                    VStack(spacing: 10) { rematchButton; lobbyButton }
                }
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            GamesGomokuBoardCanvas(board: match.board, geometry: GomokuPhoneBoardGeometry(side: geo.size.width),
                                              lastMove: match.lastMove, autoPoints: match.autoPoints)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(GomokuPhoneText.boardAccessibility(match, forbiddenCount: 0))
                        }
                    }
                GamesGomokuChatCard(store: gomoku)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.rowSpacing)
        }
        .scrollDismissesKeyboard(.interactively)
        .gamesDemoScrollAnchor(isDemo: store.context.isDemo)
        .sensoryFeedback(match.outcome == .won ? .success : .warning, trigger: match.id)
    }

    private var resultCard: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) { resultIcon; resultTexts; Spacer(minLength: 6); rubyDeltaLabel }
            // 큰 글자: 아이콘·루비 한 줄, 글은 그 아래 — 한 줄에 몰면 "이겼어요!" 가 글자마다 꺾였다(AX 스크린샷 실측).
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) { resultIcon; Spacer(minLength: 6); rubyDeltaLabel }
                resultTexts
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var resultIcon: some View {
        Image(systemName: icon)
            .font(.title.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 60, height: 60)
            .background(Circle().fill(tint.opacity(0.16)))
            .overlay(Circle().stroke(tint.opacity(0.45), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var resultTexts: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(GomokuPhoneText.outcomeTitle(match.outcome))
                    .font(MobileTheme.title(.title2))
                    .foregroundStyle(MobileTheme.primaryText)
                    .fixedSize()
                Text(GomokuPhoneText.endReason(match.endReason, outcome: match.outcome))
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    AvatarView(name: match.opponent.displayName, url: match.opponent.avatarURL.flatMap(URL.init(string:)), size: 22)
                    Text("상대 · \(match.opponent.displayName)")
                        .font(.caption)
                        .foregroundStyle(MobileTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
    }

    private var rubyDeltaLabel: some View {
            HStack(spacing: 4) {
                Image(systemName: "diamond.fill")
                    .foregroundStyle(MobileTheme.ruby)
                    .accessibilityHidden(true)
                Text(GomokuPhoneText.rubyDelta(delta))
                    .font(MobileTheme.number(.title2, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(delta > 0 ? MobileTheme.working : (delta < 0 ? MobileTheme.danger : MobileTheme.primaryText))
            }
            .fixedSize()
            .accessibilityLabel("루비 \(GomokuPhoneText.rubyDelta(delta))")
    }

    private var rematchButton: some View {
        Button {
            Task { await gomoku.rematch() }
        } label: {
            Label(GomokuPhoneText.rematch, systemImage: "arrow.clockwise")
        }
        .buttonStyle(GamesCompactButtonStyle(kind: .filled, fillsWidth: true))
        .disabled(gomoku.isBusy || gomoku.outgoing != nil)
    }

    private var lobbyButton: some View {
        Button(GomokuPhoneText.backToLobby) { gomoku.backToLobby() }
            .buttonStyle(GamesCompactButtonStyle(kind: .outline, fillsWidth: true))
    }
}
#endif
