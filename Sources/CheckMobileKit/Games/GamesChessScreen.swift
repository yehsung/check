#if os(iOS)
import CheckCore
import SwiftUI

/// 1:1 체스 화면 — 코어 `ChessStore` 의 단계(로비 · 대국 · 결과)를 한 화면에서 갈아 끼운다.
/// 본은 폰 오목(`GamesGomokuScreen`)이고, 체스에서 달라지는 자리만 바꿨다.
///
/// 수명: 나타나면 `GamesStore.chessScreenDidAppear`(로비·진행 판 + 폴링), 사라지면 `chessScreenDidDisappear`
/// (관전을 먼저 내리고 창을 내린다 — 그 순서가 계약이다). 대국 중 화면 꺼짐 방지는 이 화면이 쓰지 않는다 —
/// 주인은 `GamesStore` 하나다(판이 도는 동안은 화면을 떠나도 유지한다).
///
/// ★ **순위·관전은 로비 안 절(section)이다 — 새 화면으로 밀지 마라.** 스토어가 `phase == .lobby` 를 요구하고
///   (`ChessStoreWatch.shouldPollWatch` · `startWatching` 의 `guard phase == .lobby`), 자식 라우트를 push 하면
///   이 화면의 `onDisappear` → `windowDidHide()` 로 **폴링이 죽어** 판이 갱신되지 않는다. 오목에서 실증된 자리다.
///
/// ★ **로그인을 보지 않는다.** 로봇 판(`ChessStoreAI`)은 서버를 한 번도 안 타므로 비로그인 사용자도 둔다
///   (인수인계 §6-12). 이 화면을 로그인 뒤로 숨기면 그 길이 막힌다 — 1:1 절들만 제 안에서 "로그인하세요"로 접힌다.
struct GamesChessScreen: View {
    let store: GamesStore

    /// [도전] → 판돈 시트의 대상.
    @State private var stakeTarget: ChessUser?
    /// 로봇 판을 두는 중에 누른 [수락] — 확인을 거쳐야 보낸다(아래 `robotConfirm` 주석).
    @State private var acceptNeedsRobotConfirm: ChessInvite?

    private var chess: ChessStore { store.chess }

    var body: some View {
        @Bindable var chess = chess
        content
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(ChessPhoneText.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $stakeTarget) { target in
                GamesChessStakeSheet(store: store, target: target)
            }
            // 규칙 시트의 주인은 화면 루트다(판돈 시트와 같은 관례 — 시트는 루트만 띄운다). 코어 깃발을 쓰는 까닭은
            // 맥과 같다: 메뉴·대국 화면도 같은 깃발로 이 시트를 연다.
            .sheet(isPresented: $chess.isRulesVisible) {
                // ★ TTL 은 **로비 응답이 말한 값**이다(코어 `inviteTTLSeconds` — 응답에 없으면 60으로 선다).
                //   상수를 베껴 넘기면 서버가 TTL 을 바꾼 날 규칙 시트만 옛 숫자를 말한다.
                GamesChessRulesSheet(initialMs: chess.initialMs, incrementMs: chess.incrementMs,
                                     inviteTtlSeconds: Int(chess.inviteTTLSeconds))
            }
            .sheet(item: $acceptNeedsRobotConfirm) { invite in
                robotConfirm(for: invite)
            }
            .onAppear { store.chessScreenDidAppear() }
            .onDisappear { store.chessScreenDidDisappear() }
            .onChange(of: chess.match?.id) { _, _ in
                stakeTarget = nil
                acceptNeedsRobotConfirm = nil
            }
    }

    /// 로봇 판을 두는 중에 1:1 신청을 수락하려 한다 — **먼저 묻는다.**
    ///
    /// ★ 안 물으면 두던 로봇 판이 **문구도 확인도 없이 사라진다**: 서버 `chess__busy` 는 로봇 판을 볼 수 없고
    ///   (서버에 행이 없다) 코어 `respond` 에도 가드가 없어 1:1 판이 그대로 서며, 그 순간 `match` 관찰자가
    ///   로봇 판을 버린다(`discardAIGame`). 걸린 루비가 0이라 **손실은 없고**, 잃는 것은 두던 판뿐이다 —
    ///   그래서 막지 않고 **묻는다**(막으면 60초 TTL 안에 진짜 대결을 놓친다).
    ///   확인 뒤에는 코어가 알아서 로봇 판을 버린다 — 이 화면이 따로 정리하지 않는다.
    private func robotConfirm(for invite: ChessInvite) -> some View {
        AingConfirmSheet(
            title: ChessPhoneText.acceptEndsRobotTitle,
            message: ChessPhoneText.acceptEndsRobotMessage,
            confirmTitle: ChessPhoneText.acceptEndsRobotConfirm,
            cancelTitle: ChessPhoneText.acceptEndsRobotCancel,
            onConfirm: {
                acceptNeedsRobotConfirm = nil
                Task { await chess.respond(inviteID: invite.id, accept: true) }
            },
            onCancel: { acceptNeedsRobotConfirm = nil }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch chess.phase {
        case .playing, .result:
            // 대국·결과는 한 화면이 맡는다(다른 레인 — `GamesChessMatchView`). 판이 없으면 로비가 선다:
            // 늦게 온 응답이 단계만 올려 놓고 판을 못 세운 틈이고, 오목도 같은 대체 갈래를 둔다.
            if chess.match != nil {
                GamesChessMatchView(store: chess, me: GamesMeIdentity.current(store.context))
            } else {
                lobby
            }
        case .lobby:
            lobby
        }
    }

    // MARK: - 로비

    /// 데모 스크린샷 전용 닻 id — 관전 절을 화면 위로 올릴 자리(`gamesDemoChessWatchAnchor`).
    /// 값이 **절에 붙은 `.id` 와 같은 한 곳에서** 와야 한다(글자를 두 번 적으면 한쪽만 고쳐져 조용히 안 움직인다).
    static let watchSectionAnchorID = "chess-watch-section"

    private var lobby: some View {
        ScrollViewReader { proxy in
            lobbyScroll(proxy: proxy)
        }
    }

    private func lobbyScroll(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summary
                caption
                notice
                blockedByOtherGame
                incoming
                outgoing
                // 로봇과 두기 — 사람 목록 바로 위, 시간이 흐르는 것(받은·보낸 신청)보다 아래.
                // 판돈도 순위도 없고 **로그인을 보지 않는다**(화면 머리말).
                GamesChessAISection(store: chess)
                    .padding(.top, MobileTheme.rowSpacing)
                opponents
                // 관전("지금 대결 중" 목록 + 관전 판)과 순위는 **제자리 절**이다(화면 머리말).
                // `.id` 는 데모 닻이 올릴 자리다(운영에서는 아무도 그 id 를 부르지 않는다).
                GamesChessWatchSection(store: chess)
                    .id(Self.watchSectionAnchorID)
                GamesChessRankingSection(store: chess)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
            .padding(.bottom, MobileTheme.space6)
        }
        .refreshable {
            await chess.refreshLobby()
        }
        // 데모 스크린샷(`-AingCheckGamesDemo bottom`)에서 맨 아래부터 보여 준다 — 오목 화면 넷·미니게임과
        // 같은 모양. ★ 체스 로비만 이 줄이 없어서 **순위·관전 절을 아무도 눈으로 못 봤다**(실측 D5):
        // 그 두 절은 로비 맨 아래라 기본 닻으로는 화면에 한 번도 들어오지 않는다.
        .gamesDemoScrollAnchor(isDemo: store.context.isDemo)
        // 데모 전용 닻 둘. ★ **게임 탭이 아니라 여기**다: 둘 다 "관전 중인가"를 보는데, 그 값을
        // `navigationDestination` 클로저에서 읽으면 관전이 서는 순간 목적지가 다시 세워져 체스 화면이
        // 헐리고(`chessScreenDidDisappear` → `stopWatching()`) 관전이 영영 안 섰다(실측).
        // ① 라우트 꼬리가 순위·관전이면 맨 아래 절에서 시작하되, **관전이 선 뒤에는 그 닻을 놓는다**.
        // ★ `#if DEBUG` 는 **인자가 DEBUG 전용 값**이라 있다(출시 게이트 — `Demo/MobileDemoChessRoute.swift` 머리).
        //   Release 에서 잃는 것은 없다: 그 구성에서 `demoChessRoute` 는 영원히 nil 이고 nil 이면 닻이 없다.
        #if DEBUG
        .gamesDemoChessSectionAnchor(store.demoChessRoute?.section, isWatching: chess.spectating != nil)
        #endif
        // ② 그리고 관전 절을 화면 위로 올린다 — 닻 하나로는 둘 다 못 한다(바닥 닻이 순위 절을 붙잡는 동안
        //    판은 접힘 위로 밀려 올라갔다 · 실측 A).
        .gamesDemoChessWatchAnchor(isDemo: store.context.isDemo, watchID: chess.spectating?.id,
                                   proxy: proxy, id: Self.watchSectionAnchorID)
        // 규칙 책 버튼(오목 로비와 같은 자리). 로비가 **로비 응답 값**으로 시트를 띄우므로 시간 수치가 서버와 같다.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { chess.isRulesVisible = true } label: { Image(systemName: "book") }
                    .accessibilityLabel(ChessPhoneText.rulesTitle)
            }
        }
    }

    // MARK: 머리 두 칸 — 내 전적 · 내 루비

    private var summary: some View {
        InsetGroup {
            HStack(spacing: 0) {
                summaryCell(ChessPhoneText.recordTitle) {
                    Text(ChessPhoneText.record(chess.record))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityLabel(ChessPhoneText.myRecordAccessibility(chess.record))
                Rectangle()
                    .fill(MobileTheme.separator)
                    .frame(width: MobileTheme.hairline)
                summaryCell(ChessPhoneText.myRubyTitle) {
                    // 공유 미러 먼저(나 탭 상점 구매도 적는다) — `GamesStore.rubyBalance` 와 같은 순서.
                    if let balance = store.rubyBalance {
                        RubyPrice(balance, isShort: false, style: .headline)
                    } else {
                        Text(ChessPhoneText.unknownNumber).font(.headline).foregroundStyle(MobileTheme.label)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryCell(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
            value()
        }
        .padding(.horizontal, MobileTheme.cardPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// 규칙 한 줄 — **시간 수치는 서버가 말한 값**에서 만든다(상수를 베끼지 않는다. 로비 응답이 오면 그 값으로 덮인다).
    private var caption: some View {
        Text(ChessPhoneText.subtitle(initialMs: chess.initialMs, incrementMs: chess.incrementMs))
            .font(.footnote)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
    }

    @ViewBuilder
    private var notice: some View {
        if let text = chess.notice {
            InlineNotice(text: text, kind: .warning)
                .padding(.top, MobileTheme.rowSpacing)
        }
    }

    /// 한 사람 한 판(B8) — 오목 판이 흐르는 동안은 체스를 신청·수락할 수 없다. 버튼만 흐려 두면 **왜**인지
    /// 알 길이 없어(폰엔 호버 툴팁이 없다) 절 위에 까닭을 한 줄로 세운다. 판정은 `GamesStore.chessEntryBlock`.
    @ViewBuilder
    private var blockedByOtherGame: some View {
        if let playing = store.chessEntryBlock {
            // 판정·문구가 **한 함수**에 있다(`entryBlockNotice(playing:blocked:)`) — 화면이 사유를 지어내지 않는다.
            // ★ **두 줄**이다: 제목(`busyTitle`)만 그리면 왜 막혔는지만 알고 **언제 풀리는지**를 모른다.
            //   둘째 줄(`busyHint`)이 "오목 판이 끝나면 체스를 신청할 수 있어요" 를 말한다 — 게임 탭 카드들이
            //   칩 + 보조 줄로 그리는 것과 같은 짝이고, 조립은 문구 표가 쥔다(뷰에서 이으면 맥 스위트가 못 본다).
            // ★ `.gomoku` 를 박아 두지 **않는다**: 1.0.11 부터 체스를 막는 판이 오목·테트리스 둘이다
            //   (박아 두면 테트리스 대결 중에 이 안내가 통째로 사라진다 — 버튼만 흐려지고 까닭이 없어진다).
            InlineNotice(text: ChessPhoneText.entryBlockNotice(playing: playing, blocked: .chess) ?? "", kind: .warning)
                .padding(.top, MobileTheme.rowSpacing)
        } else if store.hasLiveChessRobotGame {
            // 로봇 판 중에는 [도전]이 막힌다(게이트의 `store.match == nil`). **왜**인지 말하지 않으면
            // 비활성 알약만 보고 "왜 안 눌리지"가 된다 — 폰엔 호버 툴팁이 없다.
            // 받은 신청은 막지 않는다(묻고 수락한다 — `robotConfirm`).
            InlineNotice(text: ChessPhoneText.blockedByRobot, kind: .info)
                .padding(.top, MobileTheme.rowSpacing)
        }
    }

    // MARK: 받은 신청 — 서버가 한 번에 하나만 말해 준다

    @ViewBuilder
    private var incoming: some View {
        if let invite = chess.visibleIncoming {
            SectionHeader(ChessPhoneText.incomingTitle,
                          trailing: .text(ChessPhoneText.inviteTtlHint(ttlSeconds: Int(chess.inviteTTLSeconds))),
                          padded: true)
            InsetGroup {
                GamesChessInviteCard(store: store, invite: invite,
                                     onNeedsRobotConfirm: { acceptNeedsRobotConfirm = $0 })
            }
        }
    }

    @ViewBuilder
    private var outgoing: some View {
        if let invite = chess.outgoing {
            SectionHeader(ChessPhoneText.outgoingTitle, padded: true)
            InsetGroup {
                GamesChessOutgoingRow(store: store, invite: invite)
            }
            Text(ChessPhoneText.stakeNotHeldYet(ttlSeconds: Int(chess.inviteTTLSeconds)))
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
        }
    }

    // MARK: 상대 고르기 — 근무 중 먼저 · 대국 중 배지 · 옛 버전 배지

    @ViewBuilder
    private var opponents: some View {
        let users = store.chessLobbyUsers
        SectionHeader(ChessPhoneText.lobbyTitle,
                      trailing: users.isEmpty ? .none : .text(ChessPhoneText.peopleCount(users.count)),
                      padded: true)
        InsetGroup {
            if chess.lobbyLoadFailed {
                GroupRow(divider: users.isEmpty ? .none : .inset(MobileTheme.cardPadding)) {
                    LoadFailureRow(ChessPhoneText.usersLoadFailed) { Task { await chess.refreshLobby() } }
                }
            }
            // 빈 목록을 "없다"로 말하는 것은 **한 번 받았고 마지막 조회가 실패하지 않았을 때만**(공용 `MobileLoadKnowledge`).
            if users.isEmpty {
                if !chess.lobbyLoadFailed {
                    GroupRow(divider: .none) {
                        if chess.hasLoadedLobby {
                            Text(ChessPhoneText.emptyUsers)
                                .font(.subheadline)
                                .foregroundStyle(MobileTheme.label2)
                        } else {
                            LoadingRow(ChessPhoneText.loadingUsers)
                        }
                    }
                }
            } else {
                ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                    GamesChessOpponentRow(store: store, user: user, isLast: index == users.count - 1,
                                          onChallenge: { stakeTarget = $0 })
                }
            }
        }
        Text(ChessPhoneText.lobbyCaption)
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
    }
}

// MARK: - 상대 한 줄

/// 상대 한 줄(폰 오목 `GamesGomokuOpponentRow` 와 같은 모양): 아바타(근무 중 점) · 이름 + 센터 · 상태 부제 ·
/// 오른쪽 [도전] 틴트(또는 회색 비활성).
///
/// ★ **옛 버전 배지는 버튼이 쥔다**("업데이트 필요"), 부제는 **근무 축**을 쥔다. 두 자리가 각자 고르던
///   때는 한 줄이 "앱 업데이트가 필요해요" 를 두 번 말하고 초록 점이 켜진 사람의 "근무 중" 이 사라졌다
///   (헤드리스 실측 D4). 그래서 고르는 자리를 `ChessPhoneText.opponentRow(for:)` 하나로 모았다.
///   서버 `capable` 이 nil 로 와도 그 값이 false 이므로(`ChessStore.user(from:)`) **모르는 상대는 불가로
///   그린다** — 신청해서 `target_outdated` 를 받는 것보다 낫다(`ChessWire.swift:118` 의 계약).
private struct GamesChessOpponentRow: View {
    let store: GamesStore
    let user: ChessUser
    let isLast: Bool
    let onChallenge: (ChessUser) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var canChallenge: Bool {
        GamesChessChallengeGate.isEnabled(user: user, store: store.chess, blockedBy: store.chessEntryBlock)
    }

    var body: some View {
        GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding + 36 + MobileTheme.space3), minHeight: 56) {
            // 큰 글자: [도전]을 아래 줄로 — 한 줄에 두면 이름이 글자 하나씩 꺾인다(오목에서 실측).
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: MobileTheme.space3) { avatar; info }
                    challengeButton
                }
            } else {
                avatar
                info
                Spacer(minLength: 8)
                challengeButton
            }
        }
    }

    private var avatar: some View {
        PersonAvatar(name: user.displayName, colorSeed: user.id,
                     status: user.isWorking ? .working : nil,
                     url: user.avatarURL.flatMap(URL.init(string:)), userID: user.id, size: 36,
                     characterHint: user.characterID)
    }

    /// 부제와 버튼 글자를 **문구 표가 한 번에** 고른다 — 자리마다 따로 고르면 한 줄에 같은 문장이 두 번
    /// 나오고(실측 D4) 근무 축이 덮인다.
    private var lines: ChessPhoneText.OpponentRow { ChessPhoneText.opponentRow(for: user) }

    private var info: some View {
        VStack(alignment: .leading, spacing: 1) {
            PersonName(user.displayName, center: CenterLabel.serverValue(forDisplay: user.center))
            Text(lines.subtitle)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var challengeButton: some View {
        if canChallenge {
            AingButton(ChessPhoneText.challenge, kind: .tinted, size: .sm) { onChallenge(user) }
                .fixedSize()
                .accessibilityHint(ChessPhoneText.challengeHint(name: user.displayName))
        } else {
            // 막힌 까닭은 **버튼**이 말하고(짧게), 근무 축은 부제가 말한다 — 둘을 한 자리에서 고른 것이
            // `ChessPhoneText.opponentRow(for:)` 다. 여기서 다시 고르면 같은 문장이 두 번 나온다.
            AingButton(lines.buttonTitle, kind: .gray, size: .sm) {}
                .disabled(true)
                .fixedSize()
        }
    }
}

// MARK: - 받은 신청 · 보낸 신청

/// 받은 신청 한 건: 아바타 44 · "솜사탕님의 신청" + 센터 · 판돈 줄 + 남은 초 · [거절 회색] [수락 채움].
///
/// ★ 수락이 **루비가 실제로 빠지는 순간**이다(신청만 한 상태에서는 0원도 안 움직인다 — 아래 `GamesChessStakeSheet`).
private struct GamesChessInviteCard: View {
    let store: GamesStore
    let invite: ChessInvite
    /// 로봇 판을 두는 중이면 수락을 **바로 보내지 않고** 화면 루트에 확인을 넘긴다(두던 판이 말없이 사라지지 않게).
    let onNeedsRobotConfirm: (ChessInvite) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var chess: ChessStore { store.chess }

    /// 오목 판이 흐르는 동안은 체스 수락도 막는다(한 사람 한 판 — 양방향).
    /// **로봇 판은 여기서 막지 않는다** — 막으면 60초 TTL 안에 진짜 대결을 놓친다. 대신 확인을 거친다.
    private var canRespond: Bool { !chess.isBusy && store.chessEntryBlock == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let header = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: MobileTheme.space3))
            header {
                PersonAvatar(name: invite.peer.displayName, colorSeed: invite.peer.id,
                             status: invite.peer.isWorking ? .working : nil,
                             url: invite.peer.avatarURL.flatMap(URL.init(string:)), userID: invite.peer.id, size: 44,
                             characterHint: invite.peer.characterID)
                VStack(alignment: .leading, spacing: 1) {
                    PersonName(ChessPhoneText.incomingTitle(name: invite.peer.displayName),
                               center: CenterLabel.serverValue(forDisplay: invite.peer.center))
                    HStack(spacing: 0) {
                        GamesStakeLine(stake: invite.stake, prefix: ChessPhoneText.stakeTitle,
                                       suffix: ChessPhoneText.stakeGainSuffix(invite.stake))
                        GamesChessRemainingText(store: store, expiresAt: invite.expiresAt, prefix: " · ")
                    }
                    .font(MobileTheme.rowSubtitle)
                    .foregroundStyle(MobileTheme.label2)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MobileTheme.cardPadding)
            .padding(.top, 14)
            .padding(.bottom, 10)
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 8) { acceptButton; declineButton }
                } else {
                    HStack(spacing: 10) { declineButton; acceptButton }
                }
            }
            .padding(.horizontal, MobileTheme.cardPadding)
            .padding(.bottom, MobileTheme.cardPadding)
        }
    }

    private var acceptButton: some View {
        AingButton(ChessPhoneText.accept, kind: .filled, size: .md, fillsWidth: true) {
            // ★ 로봇 판을 두는 중이면 **여기서 요청을 내지 않는다** — 확인을 거친다(`GamesChessScreen.robotConfirm`).
            guard !store.hasLiveChessRobotGame else { onNeedsRobotConfirm(invite); return }
            Task { await chess.respond(inviteID: invite.id, accept: true) }
        }
        .disabled(!canRespond)
    }

    private var declineButton: some View {
        AingButton(ChessPhoneText.decline, kind: .gray, size: .md, fillsWidth: true) {
            Task { await chess.respond(inviteID: invite.id, accept: false) }
        }
        .disabled(chess.isBusy)
    }
}

/// 보낸 신청 한 줄: 아바타 · "구름빵님에게 신청했어요" · 판돈 · 남은 초 · [취소] 회색 알약.
private struct GamesChessOutgoingRow: View {
    let store: GamesStore
    let invite: ChessInvite

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GroupRow(divider: .none, minHeight: 56) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: MobileTheme.space3) { avatar; texts }
                    cancelButton
                }
            } else {
                avatar
                texts
                Spacer(minLength: 8)
                cancelButton
            }
        }
    }

    private var avatar: some View {
        PersonAvatar(name: invite.peer.displayName, colorSeed: invite.peer.id,
                     status: invite.peer.isWorking ? .working : nil,
                     url: invite.peer.avatarURL.flatMap(URL.init(string:)), userID: invite.peer.id, size: 36,
                     characterHint: invite.peer.characterID)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(ChessPhoneText.outgoingTitle(name: invite.peer.displayName))
                .font(MobileTheme.rowTitle)
                .foregroundStyle(MobileTheme.label)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                GamesStakeLine(stake: invite.stake, prefix: ChessPhoneText.stakeTitle)
                GamesChessRemainingText(store: store, expiresAt: invite.expiresAt, prefix: " · ")
            }
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
        }
        .accessibilityElement(children: .combine)
    }

    private var cancelButton: some View {
        AingButton(ChessPhoneText.cancel, kind: .gray, size: .sm) {
            Task { await store.chess.cancelChallenge() }
        }
        .disabled(store.chess.isBusy)
        .fixedSize()
    }
}

// MARK: - 초 단위 잎

/// 신청 만료까지 남은 초("42초 남음") — **잎 뷰**(규약 ⑥: 초 단위 값은 잎만 읽는다. 스토어는 매초 아무것도 대입하지 않는다).
/// 시계는 스토어 시계(데모 고정 시계와 같은 눈금).
private struct GamesChessRemainingText: View {
    let store: GamesStore
    let expiresAt: Date
    var prefix = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = expiresAt.timeIntervalSince(store.context.clock.now())
            Text(prefix + ChessPhoneText.remainingPhrase(remaining))
                .monospacedDigit()
                .accessibilityLabel(ChessPhoneText.remainingAccessibility(remaining))
        }
    }
}

// MARK: - 판돈 시트

/// 판돈 시트(맥 `ChessStakePrompt` 흐름 · 폰 오목 `GamesGomokuStakeSheet` 와 같은 모양): **아무것도 안 골라진 채**
/// 열리고, 판돈은 고르기만(다시 누르면 해제), 신청은 맨 아래 채운 버튼 하나.
///
/// ★ 캡션이 **거짓말을 하지 않는 것**이 이 시트의 계약이다: 신청만 한 상태에서는 **0원도 안 움직이고**,
///   양쪽에서 빠지는 것은 **수락하는 순간**이다. 신청은 60초 뒤 만료되고 그때도 루비 이동이 없다.
///   "신청하면 빠져요"로 적으면 사용자가 취소를 못 해 손해를 본다고 믿는다(실제로는 잃는 것이 없다).
private struct GamesChessStakeSheet: View {
    let store: GamesStore
    let target: ChessUser

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: ChessStake?

    private var chess: ChessStore { store.chess }
    /// 공유 미러 먼저 — `GamesStore.rubyBalance` 와 같은 순서.
    private var balance: Int? { store.rubyBalance }

    /// 지금 신청을 **낼 수 있는 판돈**(못 내면 nil). 판정은 `GamesChessStakeSend` 한 곳이다 —
    /// 요청이 나가는 마지막 문이라 맥 스위트가 값으로 재야 한다(그쪽 머리말).
    private var sendable: ChessStake? {
        GamesChessStakeSend.sendable(selected, store: chess, balance: balance, blockedBy: store.chessEntryBlock)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(ChessPhoneText.stakeTitle,
                        subtitle: ChessPhoneText.stakePromptTitle(name: target.displayName),
                        onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space4) {
                    InsetGroup {
                        GroupRow(divider: .none, minHeight: 64) {
                            PersonAvatar(name: target.displayName, colorSeed: target.id,
                                         status: target.isWorking ? .working : nil,
                                         url: target.avatarURL.flatMap(URL.init(string:)), userID: target.id, size: 44,
                                         characterHint: target.characterID)
                            VStack(alignment: .leading, spacing: 1) {
                                PersonName(target.displayName, center: CenterLabel.serverValue(forDisplay: target.center))
                                Text(selected.map { ChessPhoneText.stakePromptChosen($0.rawValue) }
                                        ?? ChessPhoneText.stakePromptCaption)
                                    .font(MobileTheme.rowSubtitle)
                                    .monospacedDigit()
                                    .foregroundStyle(selected == nil ? MobileTheme.label2 : MobileTheme.accent)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    // 큰 글자에서는 세로로 — 가로 셋에 "10" 이 줄바꿈되어 "1/0" 으로 읽혔다(오목 AX 실측).
                    Group {
                        if typeSize.isAccessibilitySize {
                            VStack(spacing: 10) {
                                ForEach(ChessStake.allCases, id: \.rawValue) { stake in stakeOption(stake) }
                            }
                        } else {
                            HStack(spacing: 10) {
                                ForEach(ChessStake.allCases, id: \.rawValue) { stake in stakeOption(stake) }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(ChessPhoneText.myRubyTitle)
                                .font(.footnote)
                                .foregroundStyle(MobileTheme.label2)
                            if let balance {
                                RubyPrice(balance, isShort: false, gemSize: 14, style: .footnote)
                            } else {
                                Text(ChessPhoneText.unknownNumber).font(.footnote).foregroundStyle(MobileTheme.label2)
                            }
                            if ChessStake.allCases.contains(where: { !GamesChessStakeSelection.affordable($0, balance: balance) }) {
                                Text(ChessPhoneText.bulletPrefix + ChessPhoneText.stakeShortfall)
                                    .font(.footnote)
                                    .foregroundStyle(MobileTheme.label2)
                            }
                        }
                        Text(ChessPhoneText.stakeCaption)
                            .font(.footnote)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
                .padding(.bottom, MobileTheme.space4)
            }
            AingButton(selected.map { ChessPhoneText.challengeWithStake($0.rawValue) }
                        ?? ChessPhoneText.stakePromptCaption,
                       kind: .filled, size: .lg, fillsWidth: true) {
                guard let stake = sendable else { return }
                // 고른 값을 스토어에 적고(결과 화면의 [다시 신청]이 쓴다) 신청은 여기 한 곳에서만 나간다.
                chess.selectedStake = stake
                dismiss()
                Task { await chess.challenge(userID: target.id) }
            }
            .disabled(sendable == nil)
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.bottom, MobileTheme.space3)
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    /// 판돈 칸 하나 — **고르기만** 한다(선택 = 파랑 틴트 + 파랑 테두리 + 체크). 모자라면 흐린 가격 + 비활성,
    /// **잔액을 모르면 막지 않는다**.
    private func stakeOption(_ stake: ChessStake) -> some View {
        let isSelected = selected == stake
        let affordable = GamesChessStakeSelection.affordable(stake, balance: balance)
        let enabled = affordable && !chess.isBusy
        let shape = RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selected = GamesChessStakeSelection.toggled(current: selected, tapped: stake)
            }
        } label: {
            VStack(spacing: 2) {
                RubyPrice(stake.rawValue, isShort: !affordable, gemSize: 20, style: .title3)
                Text(ChessPhoneText.stakeGain(stake.rawValue))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(affordable ? MobileTheme.label2 : MobileTheme.label3Text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(shape.fill(isSelected ? MobileTheme.accentTint : MobileTheme.surface))
            .overlay(shape.strokeBorder(isSelected ? MobileTheme.accent : Color.clear, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MobileTheme.accent)
                        .padding(7)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(ChessPhoneText.stakeOptionAccessibility(stake.rawValue))
        .accessibilityValue(isSelected ? ChessPhoneText.selected : (affordable ? "" : ChessPhoneText.stakeShortfall))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
