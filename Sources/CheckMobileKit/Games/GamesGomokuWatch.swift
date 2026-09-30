#if os(iOS)
import CheckCore
import SwiftUI

/// 관전 화면(0.3.41) — 남의 진행 중인 판을 **읽기 전용**으로 본다. `phase == .lobby && spectating != nil` 이면
/// 로비 **대신** 이 화면이 선다(새 라우트가 아니다 — 자식 라우트를 push 하면 `GamesGomokuScreen.onDisappear` →
/// `windowDidHide()` 로 스토어 폴링이 죽어 값이 갱신되지 않는다).
///
/// 위에서부터: 받은 신청(있을 때만) · 안내 한 줄 · 흑 카드 · 판 · 백 카드 · 상태 상자 · 판돈·수·경과, 아래 막대에 [나가기].
/// 대국 화면(`GamesGomokuMatch`)과 같은 문법이지만 **입력이 하나도 없다**:
/// - 판은 순수 그림(`GamesGomokuBoardCanvas`)이다 — 탭 제스처·미리보기 돌·금수 표시가 없다.
///   `GamesGomokuPlayBoard` 는 `match.myColor`·탭에 묶여 있어 쓰지 않는다.
/// - 차례 링은 `watch.deadline` 을 **직접** 센다 — 스토어 `remainingSeconds` 는 내 판만 알고, 관전 중 `match` 는 nil 이라
///   그 값을 쓰면 링이 0초로 빨갛게 선다.
/// - 채팅·관전자 수는 그리지 않는다(서버 응답에 그 키 자체가 없다).
/// - 끝난 판을 다시 조회하지 않는다 — 폴링은 스토어가 멈추고(`isFinished`) 결과는 [나가기] 전까지 이 값에 남는다.
///   3분이 지나면 서버가 `not_found` 를 주므로 **화면이 들고 있는 것이 결과의 유일한 출처**다.
struct GamesGomokuWatch: View {
    let store: GamesStore
    let watch: GomokuSpectateState

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var gomoku: GomokuStore { store.context.gomoku }

    var body: some View {
        GeometryReader { screen in
            watchBody(visible: screen.size)
        }
    }

    private func watchBody(visible: CGSize) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.space2) {
                invites
                if let notice = gomoku.notice {
                    InlineNotice(text: notice, kind: .warning)
                }
                players(boardSide: boardSide(in: visible))
                GamesGomokuWatchStatusBox(store: store, watch: watch)
                info
                caption
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
            .padding(.bottom, MobileTheme.space3)
        }
        .scrollBounceBehavior(.basedOnSize)
        .gamesDemoScrollAnchor(isDemo: store.context.isDemo)
        .safeAreaInset(edge: .bottom, spacing: 0) { leaveBar }
        // 로비와 같은 머리(제목은 화면 루트가 `navigationTitle` 로 세웠다 · 탭 막대는 그대로 보인다 — 관전은 로비 자리다).
        // 규칙 책은 남긴다(규칙을 모르는 채로 남의 판을 보는 자리다). [AI와 두기]는 로비 본문의 카드라 여기엔 없다 —
        // 맥도 관전 중에는 그 버튼을 숨긴다(AI 판이 서면 관전이 내려가 보던 판을 잃는다).
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                GamesGomokuRulesButton(store: gomoku)
            }
        }
    }

    // MARK: 받은 신청 (관전 중에도 닿아야 한다)

    /// 관전 화면이 로비를 통째로 덮으므로, 여기 없으면 받은 신청의 60초를 거둘 길이 없다. 로비의 `.rows` 갈래와 **같은 부품**이다
    /// (`GamesGomokuInviteCard` — 수락·거절 문이 두 벌이 되지 않는다). 받은 신청이 없으면 아무것도 그리지 않는다:
    /// "없어요"는 할 일이 없는 줄이고, 관전 화면에서는 판이 밀려날 뿐이다.
    ///
    /// 개수 상한은 두지 않는다(맥 오른쪽 열은 세로 예산이 못 박혀 2장까지였다) — 폰은 스크롤이라 전부 그려도 거둘 길이 남는다.
    /// 보낸 신청 [취소]는 여기 없다 — 그 행(`GamesGomokuOutgoingRow`)은 로비 파일 안에 private 이고, 취소 문을 한 벌 더
    /// 만드는 것보다 늘 보이는 [나가기]로 로비에 돌아가는 길이 낫다.
    @ViewBuilder
    private var invites: some View {
        let pending = gomoku.pendingIncomingInvites
        if let first = pending.first {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                SectionHeader(GomokuPhoneText.incomingTitle,
                              trailing: .text(GomokuPhoneText.remainingPhrase(first.expiresAt.timeIntervalSince(store.context.clock.now()))),
                              padded: true)
            }
            InsetGroup {
                ForEach(Array(pending.enumerated()), id: \.element.id) { index, invite in
                    GamesGomokuInviteCard(store: store, invite: invite, showsCountdown: index > 0, isLast: index == pending.count - 1)
                }
            }
        }
    }

    // MARK: 두 사람 · 판

    /// 흑 카드 · 판 · 백 카드. **색을 모르는 동안에는 자리만 지킨다**(아래 `playerRow`).
    @ViewBuilder
    private func players(boardSide side: CGFloat) -> some View {
        if watch.hasServerState || !watch.faces.isEmpty {
            playerRow(.black, index: 0)
            board(side: side)
            playerRow(.white, index: 1)
        } else {
            // 씨앗도 응답도 없다(로비 30초 사이 목록에서 빠진 판을 눌렀다) — 두 사람을 하나도 모르니 빈 카드 두 장 대신
            // 한 줄 로딩이다(빈 카드는 "사람이 없는 판"으로 읽힌다).
            InsetGroup {
                GroupRow(divider: .none) { LoadingRow(GomokuPhoneText.watchLoading) }
            }
            board(side: side)
        }
    }

    /// 카드 한 자리. **흑·백을 추측하지 않는다**: `faces` 의 a/b 는 uuid 순서라 색이 아니므로, 서버가 `black`/`white` 를 말하기
    /// 전(`hasServerState == false`)에는 그 자리 얼굴만 그리고 **돌 배지도 차례 표시도 달지 않는다**. 안 그러면 절반의 판이 뒤집힌다.
    private func playerRow(_ color: GomokuColor, index: Int) -> some View {
        let known = watch.hasServerState
        let user: GomokuUser?
        let subtitle: String?
        if known {
            user = color == .black ? watch.black : watch.white
            subtitle = user.map { GomokuPhoneText.playerSubtitle(color: color, isWorking: $0.isWorking) }
        } else {
            // 이 자리와 색의 관계를 아직 모른다 — `faces` 의 얼굴만 빌려 그리고 "불러오고 있어요"를 첫 자리에 한 번 둔다.
            user = watch.faces.indices.contains(index) ? watch.faces[index] : nil
            subtitle = index == 0 ? GomokuPhoneText.watchLoading : nil
        }
        return GamesGomokuWatchPlayerRow(
            store: store,
            user: user,
            color: known ? color : nil,
            isTurn: known && !watch.isFinished && watch.turn == color,
            deadline: watch.deadline,
            subtitle: subtitle
        )
    }

    /// 판 한 장(가운데 정렬 · 그림자는 대국·결과 화면과 같은 줄). 입력이 없으므로 `forbidden: [:]` · `preview: nil` 이고
    /// 탭 제스처를 달지 않는다. 끝난 판이 5목이면 승리선을 긋는다(결과 화면과 같은 판정 — `GomokuPhoneWinLine`).
    private func board(side: CGFloat) -> some View {
        GamesGomokuBoardCanvas(
            board: watch.board,
            geometry: GomokuPhoneBoardGeometry(side: side),
            lastMove: watch.lastMove,
            forbidden: [:],
            autoPoints: watch.autoPoints,
            preview: nil,
            winLine: watch.isFinished && watch.endReason == .five
                ? GomokuPhoneWinLine.ends(board: watch.board, lastMove: watch.lastMove)
                : nil
        )
        .frame(width: side, height: side)
        .shadow(color: colorScheme == .dark ? .black.opacity(0.35) : Color(red: 80 / 255, green: 50 / 255, blue: 10 / 255).opacity(0.18),
                radius: 9, y: 6)
        .frame(maxWidth: .infinity)
        // 보이스오버: 판 전체가 한 요소다(돌 수 · 마지막 수 · 누구 차례) — 칸마다 요소를 두는 것은 두는 사람의 판뿐이다.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GomokuPhoneText.watchBoardAccessibility(watch))
    }

    /// 판 한 변 — 대국 화면 `boardSide(in:)` 과 **같은 식**이다(그 함수는 그 파일 안에 private 이다): 기본 글자에서는 화면 폭 최대지만,
    /// 글자가 커지면 카드 두 장이 훨씬 높아져 판과 상태 상자가 한 화면에 들어가지 못한다. 관전에서 가장 중요한 상태(누구 차례 ·
    /// 남은 초 · 끝났는가)가 판보다 먼저다.
    private func boardSide(in visible: CGSize) -> CGFloat {
        let full = max(240, visible.width - 24)
        guard visible.height > 0, typeSize >= .xLarge else { return full }
        let fraction: CGFloat = typeSize.isAccessibilitySize ? 0.40 : 0.52
        return max(240, min(full, (visible.height * fraction).rounded()))
    }

    // MARK: 판돈 · 수 · 경과

    /// 판돈 | N수 · 경과 한 줄. 판돈은 씨앗이 없으면 첫 응답 전까지 모른다("판돈 —").
    private var info: some View {
        InsetGroup {
            GroupRow(divider: .none) {
                if typeSize.isAccessibilitySize {
                    // 큰 글자: 판돈 줄과 수·경과가 한 줄에 몰리면 "이기면 / +5"로 꺾인다(신청 카드에서 실측된 같은 결).
                    VStack(alignment: .leading, spacing: 4) { stakeLine; GamesGomokuWatchMoveLine(store: store, watch: watch) }
                } else {
                    stakeLine
                    Spacer(minLength: MobileTheme.space2)
                    GamesGomokuWatchMoveLine(store: store, watch: watch)
                }
            }
        }
    }

    @ViewBuilder
    private var stakeLine: some View {
        if let stake = watch.stake {
            GamesStakeLine(stake: stake, suffix: GomokuPhoneText.stakeGainSuffix(stake))
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
        } else {
            Text(GomokuPhoneText.watchStakeUnknown)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
        }
    }

    /// 카드 밑 작은 줄(로비 캡션과 같은 자리): 채팅이 없다는 사실 · 판 위 회색 점이 뜻하는 것을 **글자로도**
    /// (폰에는 호버 자리가 없어 점만으로는 아무도 모른다).
    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(GomokuPhoneText.watchNoChat)
                .fixedSize(horizontal: false, vertical: true)
            if !watch.autoPoints.isEmpty {
                Text(GomokuPhoneText.autoPlacedCount(watch.autoPoints.count))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(MobileTheme.rowSubtitle)
        .foregroundStyle(MobileTheme.label2)
        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
        .padding(.top, MobileTheme.space1)
        .accessibilityElement(children: .combine)
    }

    // MARK: [나가기]

    /// [나가기]는 **늘 보이는 아래 막대**에 둔다 — 판이 화면을 채우면 스크롤 끝의 버튼은 "거둘 길"이 못 된다.
    /// `leaveWatch()` 는 관전을 내리고 로비·받은함·순위를 다시 읽는다(`stopWatching()` 을 부르면 낡은 목록의 로비로 돌아오고,
    /// 관전 중 막아 둔 받은함의 끝난 내 판 결과도 서지 않는다). 채운 버튼은 화면당 하나라 여기는 틴트다 —
    /// 받은 신청 카드의 [수락]이 그 하나다.
    private var leaveBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(MobileTheme.separator)
                .frame(height: MobileTheme.hairline)
            AingButton(GomokuPhoneText.leaveWatch, systemImage: "arrow.uturn.backward", kind: .tinted, size: .md, fillsWidth: true) {
                gomoku.leaveWatch()
            }
            .accessibilityHint(GomokuPhoneText.leaveWatchHint)
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, 10)
        }
        .background(MobileTheme.surface)
    }
}

// MARK: - 플레이어 카드

/// 관전 플레이어 한 장 — 대국 카드(`GamesGomokuPlayerCard`)와 같은 모양이지만 **마감을 직접 받는다**.
/// 그 카드를 재사용하면 차례 링이 스토어 `remainingSeconds`(내 판 전용)를 읽어 0초에 빨갛게 선다.
///
/// - `color`: 서버가 말한 돌 색. **nil 이면 색을 모른다**(첫 응답 전 — `faces` 는 uuid 순서다): 돌 배지도 초록 테두리도 없다.
/// - `user`: nil 이면 그 자리 사람조차 모른다(씨앗 없는 판) — 이름 자리에 "—".
private struct GamesGomokuWatchPlayerRow: View {
    let store: GamesStore
    let user: GomokuUser?
    let color: GomokuColor?
    let isTurn: Bool
    /// 진행 중인 판의 차례 마감. 지난 값이 올 수 있다 — 그 판정은 링(`GamesGomokuWatchClock`)이 한다.
    let deadline: Date?
    let subtitle: String?

    /// 돌 배지는 **색을 알 때만**(함정 1) — 모르는 동안 아무 색이나 달면 절반의 판이 뒤집힌다.
    private var badge: CharacterPortrait.Badge {
        guard let color else { return .none }
        return .stone(isBlack: color == .black)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous)
        HStack(spacing: MobileTheme.space3) {
            CharacterPortrait(id: user?.characterID, mood: user?.mood ?? .plain, size: 44, badge: badge)
            VStack(alignment: .leading, spacing: 1) {
                PersonName(user?.displayName ?? "—", center: CenterLabel.serverValue(forDisplay: user?.center))
                if let subtitle {
                    Text(subtitle)
                        .font(MobileTheme.rowSubtitle)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .layoutPriority(1)
            Spacer(minLength: 4)
            if isTurn, let deadline {
                GamesGomokuWatchClock(store: store, deadline: deadline)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(shape.fill(MobileTheme.surface))
        // 차례인 카드만 초록 테두리(대국 화면과 같다). 마감이 지나도 초록이다 — 차례는 여전히 그 사람 것이고,
        // "곧 자동으로 놓여요"는 링과 상태 상자가 대기색으로 말한다.
        .overlay(shape.strokeBorder(isTurn ? MobileTheme.workingDot : Color.clear, lineWidth: 2))
    }
}

// MARK: - 잎 뷰(시계를 읽는 자리)

/// 관전 차례 링 — **잎 뷰**. 마감 시각을 직접 받아 스토어 시계로 센다(데모 고정 시계와 같은 눈금).
/// 그림은 대국 링(`GamesGomokuTurnRing`)과 같고 **0초 색만 다르다**: 마감이 지난 남의 판은 자동 착수 **대기**지 패배가 아닌데,
/// 빨간 0초는 색만으로 "졌다"로 읽혔다(맥 2026-09-30 반증). 그래서 0초는 대기색(pending)이다.
private struct GamesGomokuWatchClock: View {
    let store: GamesStore
    let deadline: Date

    var body: some View {
        // 1초 눈금 — 관전은 남의 시계라 0.2초로 돌릴 이유가 없다(로비 "지금 대결 중" 줄과 같은 관용구).
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = max(0, deadline.timeIntervalSince(store.context.clock.now()))
            let total = Double(max(1, store.context.gomoku.turnSeconds))
            let fraction = min(1, max(0, remaining / total))
            let ring = remaining <= 0 ? MobileTheme.pendingDot
                : (remaining <= 5 ? MobileTheme.danger : (remaining <= 10 ? MobileTheme.pendingDot : MobileTheme.workingDot))
            let ink = remaining <= 0 ? MobileTheme.pending
                : (remaining <= 5 ? MobileTheme.danger : (remaining <= 10 ? MobileTheme.pending : MobileTheme.working))
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

/// 상태 상자 — **잎 뷰**. 문구·색을 `GomokuPhoneWatchStatus` 가 시각으로 고른다.
/// 시각이 문구를 바꾸는 것은 **마감이 있는 진행 중 판**뿐이라, 끝난 판·첫 응답 전에는 시계를 아예 달지 않는다
/// (끝난 판은 폴링도 이미 멈춰 있다 — 1초마다 다시 그릴 이유가 없다).
private struct GamesGomokuWatchStatusBox: View {
    let store: GamesStore
    let watch: GomokuSpectateState

    var body: some View {
        if !watch.isFinished, watch.deadline != nil {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                box(now: store.context.clock.now())
            }
        } else {
            box(now: store.context.clock.now())
        }
    }

    private func box(now: Date) -> some View {
        let kind = GomokuPhoneWatchStatus.kind(for: watch, now: now)
        let tint = Self.tint(kind)
        // 글자는 `label` 이고 뜻은 기호·바탕이 낸다(공용 `InlineNotice` 와 같은 문법) — 틴트 위 틴트 글자는 대비가 떨어진다.
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: Self.symbol(kind))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(GomokuPhoneWatchStatus.text(for: watch, now: now))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let warning = GomokuPhoneWatchStatus.streakWarning(for: watch, lossStreak: store.context.gomoku.autoAbandonStreak) {
                Text(warning)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous).fill(tint.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }

    /// 진행 중은 초록(대국의 "내 차례"와 같은 결) · 마감 지남은 앰버(대기 — **빨강 금지**) · 끝은 청회색 · 모름은 회색.
    private static func tint(_ kind: GomokuPhoneWatchStatus.Kind) -> Color {
        switch kind {
        case .loading: return MobileTheme.label2
        case .turn: return MobileTheme.working
        case .overdue: return MobileTheme.pending
        case .ended: return MobileTheme.offWork
        }
    }

    private static func symbol(_ kind: GomokuPhoneWatchStatus.Kind) -> String {
        switch kind {
        case .loading: return "hourglass"
        case .turn: return "eye"
        case .overdue: return "clock.badge.exclamationmark"
        case .ended: return "flag.checkered"
        }
    }
}

/// "12수 · 1분 35초째" — **잎 뷰**. 끝난 판은 경과를 세지 않는다(끝난 뒤 흐르는 시간은 아무 뜻도 없다).
private struct GamesGomokuWatchMoveLine: View {
    let store: GamesStore
    let watch: GomokuSpectateState

    var body: some View {
        if let startedAt = watch.startedAt, !watch.isFinished {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                line(GomokuPhoneText.watchMoves(watch.moveCount) + " · "
                    + GomokuPhoneText.elapsedPhrase(store.context.clock.now().timeIntervalSince(startedAt)))
            }
        } else {
            line(GomokuPhoneText.watchMoves(watch.moveCount))
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(MobileTheme.rowSubtitle)
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
