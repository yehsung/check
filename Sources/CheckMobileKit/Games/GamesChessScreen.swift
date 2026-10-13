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
            .navigationTitle(GamesChessLobbyText.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $stakeTarget) { target in
                GamesChessStakeSheet(store: store, target: target)
            }
            // 규칙 시트의 주인은 화면 루트다(판돈 시트와 같은 관례 — 시트는 루트만 띄운다). 코어 깃발을 쓰는 까닭은
            // 맥과 같다: 메뉴·대국 화면도 같은 깃발로 이 시트를 연다.
            .sheet(isPresented: $chess.isRulesVisible) {
                GamesChessRulesSheet(initialMs: chess.initialMs, incrementMs: chess.incrementMs,
                                     inviteTtlSeconds: GamesChessLobbyText.inviteTtlSecondsFallback)
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
            title: GamesChessLobbyText.acceptEndsRobotTitle,
            message: GamesChessLobbyText.acceptEndsRobotMessage,
            confirmTitle: GamesChessLobbyText.acceptEndsRobotConfirm,
            cancelTitle: GamesChessLobbyText.acceptEndsRobotCancel,
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
                GamesChessMatchView(store: store)
            } else {
                lobby
            }
        case .lobby:
            lobby
        }
    }

    // MARK: - 로비

    private var lobby: some View {
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
                GamesChessAISection(store: store)
                    .padding(.top, MobileTheme.rowSpacing)
                opponents
                // 관전("지금 대결 중" 목록 + 관전 판)과 순위는 **제자리 절**이다(화면 머리말).
                GamesChessWatchSection(store: store)
                GamesChessRankingSection(store: store)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
            .padding(.bottom, MobileTheme.space6)
        }
        .refreshable {
            await chess.refreshLobby()
        }
        // 규칙 책 버튼(오목 로비와 같은 자리). 로비가 **로비 응답 값**으로 시트를 띄우므로 시간 수치가 서버와 같다.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { chess.isRulesVisible = true } label: { Image(systemName: "book") }
                    .accessibilityLabel(GamesChessLobbyText.rulesTitle)
            }
        }
    }

    // MARK: 머리 두 칸 — 내 전적 · 내 루비

    private var summary: some View {
        InsetGroup {
            HStack(spacing: 0) {
                summaryCell(GamesChessLobbyText.recordTitle) {
                    Text(GamesChessLobbyText.record(chess.record))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityLabel("내 체스 전적 \(GamesChessLobbyText.record(chess.record))")
                Rectangle()
                    .fill(MobileTheme.separator)
                    .frame(width: MobileTheme.hairline)
                summaryCell(GamesChessLobbyText.myRubyTitle) {
                    // 공유 미러 먼저(나 탭 상점 구매도 적는다) — `GamesStore.rubyBalance` 와 같은 순서.
                    if let balance = store.rubyBalance {
                        RubyPrice(balance, isShort: false, style: .headline)
                    } else {
                        Text("–").font(.headline).foregroundStyle(MobileTheme.label)
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
        Text(GamesChessLobbyText.subtitle(initialMs: chess.initialMs, incrementMs: chess.incrementMs))
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
        if store.chessEntryBlock == .gomoku {
            InlineNotice(text: GamesChessLobbyText.blockedByGomoku, kind: .warning)
                .padding(.top, MobileTheme.rowSpacing)
        } else if store.hasLiveChessRobotGame {
            // 로봇 판 중에는 [도전]이 막힌다(게이트의 `store.match == nil`). **왜**인지 말하지 않으면
            // 비활성 알약만 보고 "왜 안 눌리지"가 된다 — 폰엔 호버 툴팁이 없다.
            // 받은 신청은 막지 않는다(묻고 수락한다 — `robotConfirm`).
            InlineNotice(text: GamesChessLobbyText.blockedByRobot, kind: .info)
                .padding(.top, MobileTheme.rowSpacing)
        }
    }

    // MARK: 받은 신청 — 서버가 한 번에 하나만 말해 준다

    @ViewBuilder
    private var incoming: some View {
        if let invite = chess.visibleIncoming {
            SectionHeader(GamesChessLobbyText.incomingTitle,
                          trailing: .text(GamesChessLobbyText.inviteTTLHint), padded: true)
            InsetGroup {
                GamesChessInviteCard(store: store, invite: invite,
                                     onNeedsRobotConfirm: { acceptNeedsRobotConfirm = $0 })
            }
        }
    }

    @ViewBuilder
    private var outgoing: some View {
        if let invite = chess.outgoing {
            SectionHeader(GamesChessLobbyText.outgoingTitle, padded: true)
            InsetGroup {
                GamesChessOutgoingRow(store: store, invite: invite)
            }
            Text(GamesChessLobbyText.outgoingCaption)
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
        SectionHeader(GamesChessLobbyText.lobbyTitle,
                      trailing: users.isEmpty ? .none : .text(GamesChessLobbyText.peopleCount(users.count)),
                      padded: true)
        InsetGroup {
            if chess.lobbyLoadFailed {
                GroupRow(divider: users.isEmpty ? .none : .inset(MobileTheme.cardPadding)) {
                    LoadFailureRow(GamesChessLobbyText.usersLoadFailed) { Task { await chess.refreshLobby() } }
                }
            }
            // 빈 목록을 "없다"로 말하는 것은 **한 번 받았고 마지막 조회가 실패하지 않았을 때만**(공용 `MobileLoadKnowledge`).
            if users.isEmpty {
                if !chess.lobbyLoadFailed {
                    GroupRow(divider: .none) {
                        if chess.hasLoadedLobby {
                            Text(GamesChessLobbyText.emptyUsers)
                                .font(.subheadline)
                                .foregroundStyle(MobileTheme.label2)
                        } else {
                            LoadingRow(GamesChessLobbyText.loadingUsers)
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
        Text(GamesChessLobbyText.lobbyCaption)
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
/// ★ 상태 부제가 **옛 버전 배지**를 쥔다: `isCapable == false` 는 "앱 업데이트 필요"다. 서버 `capable` 이
///   nil 로 와도 그 값이 false 이므로(`ChessStore.user(from:)`) **모르는 상대는 불가로 그린다** —
///   신청해서 `target_outdated` 를 받는 것보다 낫다(`ChessWire.swift:118` 의 계약).
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

    private var info: some View {
        VStack(alignment: .leading, spacing: 1) {
            PersonName(user.displayName, center: CenterLabel.serverValue(forDisplay: user.center))
            Text(GamesChessLobbyText.status(for: user))
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var challengeButton: some View {
        if canChallenge {
            AingButton(GamesChessLobbyText.challenge, kind: .tinted, size: .sm) { onChallenge(user) }
                .fixedSize()
                .accessibilityHint("\(user.displayName)님에게 판돈을 골라 신청해요")
        } else {
            AingButton(disabledTitle, kind: .gray, size: .sm) {}
                .disabled(true)
                .fixedSize()
        }
    }

    /// 비활성 버튼의 글자 — **막힌 까닭을 말한다**(상대가 대국 중 · 상대가 옛 버전 · 그 밖). 하나로 뭉치면
    /// "왜 못 누르나"가 사라진다.
    private var disabledTitle: String {
        if user.inMatch { return GamesChessLobbyText.inMatchButton }
        if !user.isCapable { return GamesChessLobbyText.needsUpdateButton }
        return GamesChessLobbyText.challenge
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
                    PersonName(GamesChessLobbyText.incomingTitle(name: invite.peer.displayName),
                               center: CenterLabel.serverValue(forDisplay: invite.peer.center))
                    HStack(spacing: 0) {
                        GamesStakeLine(stake: invite.stake, prefix: GamesChessLobbyText.stakeTitle,
                                       suffix: GamesChessLobbyText.stakeGainSuffix(invite.stake))
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
        AingButton(GamesChessLobbyText.accept, kind: .filled, size: .md, fillsWidth: true) {
            // ★ 로봇 판을 두는 중이면 **여기서 요청을 내지 않는다** — 확인을 거친다(`GamesChessScreen.robotConfirm`).
            guard !store.hasLiveChessRobotGame else { onNeedsRobotConfirm(invite); return }
            Task { await chess.respond(inviteID: invite.id, accept: true) }
        }
        .disabled(!canRespond)
    }

    private var declineButton: some View {
        AingButton(GamesChessLobbyText.decline, kind: .gray, size: .md, fillsWidth: true) {
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
            Text(GamesChessLobbyText.outgoingTitle(name: invite.peer.displayName))
                .font(MobileTheme.rowTitle)
                .foregroundStyle(MobileTheme.label)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                GamesStakeLine(stake: invite.stake, prefix: GamesChessLobbyText.stakeTitle)
                GamesChessRemainingText(store: store, expiresAt: invite.expiresAt, prefix: " · ")
            }
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
        }
        .accessibilityElement(children: .combine)
    }

    private var cancelButton: some View {
        AingButton(GamesChessLobbyText.cancel, kind: .gray, size: .sm) {
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
            Text(prefix + GamesChessLobbyText.remainingPhrase(remaining))
                .monospacedDigit()
                .accessibilityLabel("남은 시간 \(GamesChessLobbyText.remaining(remaining))")
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
            SheetHeader(GamesChessLobbyText.stakeTitle,
                        subtitle: GamesChessLobbyText.stakePromptTitle(name: target.displayName),
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
                                Text(selected.map { GamesChessLobbyText.stakePromptChosen($0.rawValue) }
                                        ?? GamesChessLobbyText.stakePromptCaption)
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
                            Text(GamesChessLobbyText.myRubyTitle)
                                .font(.footnote)
                                .foregroundStyle(MobileTheme.label2)
                            if let balance {
                                RubyPrice(balance, isShort: false, gemSize: 14, style: .footnote)
                            } else {
                                Text("–").font(.footnote).foregroundStyle(MobileTheme.label2)
                            }
                            if ChessStake.allCases.contains(where: { !GamesChessStakeSelection.affordable($0, balance: balance) }) {
                                Text("· " + GamesChessLobbyText.stakeShortfall)
                                    .font(.footnote)
                                    .foregroundStyle(MobileTheme.label2)
                            }
                        }
                        Text(GamesChessLobbyText.stakeCaption)
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
            AingButton(selected.map { GamesChessLobbyText.challengeWithStake($0.rawValue) }
                        ?? GamesChessLobbyText.stakePromptCaption,
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
                Text(GamesChessLobbyText.stakeGain(stake.rawValue))
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
        .accessibilityLabel("판돈 루비 \(stake.rawValue)")
        .accessibilityValue(isSelected ? "선택됨" : (affordable ? "" : GamesChessLobbyText.stakeShortfall))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 문구 (임시 — `ChessPhoneText`(별칭 `GamesChessText`)로 옮길 것)

/// 체스 로비 문구. **임시 자리다**: 정본은 다른 레인의 `ChessPhoneText`(별칭 `GamesChessText`)이고, 그 파일이
/// 이 브랜치에 들어오면 이 열거를 통째로 지우고 호출부를 그 표로 바꾼다(보고의 '문구로 옮길 목록').
/// 이 레인의 워크트리에는 그 파일이 **아직 없어서**(세션 시작 HEAD 포크) 부르면 컴파일되지 않는다 —
/// 그래서 임시로 둔다. 낱말은 맥 `ChessText`(ChessPanel.swift:84)와 같게 맞췄다 —
/// 같은 기능이 두 플랫폼에서 다른 말을 하지 않게.
///
/// ★ **시간 수치를 박은 줄이 하나도 없다**(10-12 에 5분 → 10분으로 늘었고 또 바뀔 수 있다).
///   `subtitle(initialMs:incrementMs:)` 는 로비 응답이 말한 값을 받고, 로비를 읽기 전에는 코어
///   `ChessClock.initialMs`(10분)가 그 자리에 서 있다(`ChessStore.initialMs` 의 기본값).
private enum GamesChessLobbyText {
    static let title = "1:1 체스"
    static let recordTitle = "내 전적"
    static let myRubyTitle = "내 루비"

    /// 머리글 캡션. 시간 수치는 **서버가 말한 값**에서 만든다(맥 `ChessText.subtitle` 과 같은 식).
    static func subtitle(initialMs: Int, incrementMs: Int) -> String {
        let minutes = max(1, initialMs / 60_000)
        let increment = max(0, incrementMs / 1_000)
        return "FIDE 규칙 · 백 선공 · \(minutes)분 + 한 수 \(increment)초"
    }

    static let lobbyTitle = "상대 고르기"
    static let lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    static let emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    static let loadingUsers = "상대 목록을 불러오고 있어요"
    static let usersLoadFailed = "상대 목록을 불러오지 못했어요"
    static let challenge = "도전"
    static let inMatchButton = "대결 중"
    static let needsUpdateButton = "업데이트 필요"
    static func peopleCount(_ count: Int) -> String { "\(count)명" }

    /// 상대 행 상태 부제. 우선순위: 대국 중 > 앱 업데이트 필요 > 근무 중/근무 안 함.
    /// **`isCapable` 이 거짓이면 '앱 업데이트 필요'** 이고, 서버 `capable` 이 nil 이어도 그 값은 거짓이다.
    static func status(for user: ChessUser) -> String {
        if user.inMatch { return "대국 중" }
        if !user.isCapable { return "앱 업데이트 필요" }
        return user.isWorking ? "근무 중" : "근무 안 함"
    }

    static func record(_ record: ChessRecord?) -> String {
        guard let record else { return "0승 0패 0무" }
        return "\(record.wins)승 \(record.losses)패 \(record.draws)무"
    }

    static let stakeTitle = "판돈"
    static let stakePromptCaption = "판돈을 고르세요"
    static func stakePromptTitle(name: String) -> String { "\(name)님에게 신청" }
    static func stakePromptChosen(_ stake: Int) -> String { "판돈 \(stake) · 이기면 +\(stake)" }
    static func challengeWithStake(_ stake: Int) -> String { "\(stake) 걸고 도전하기" }
    static func stakeGain(_ stake: Int) -> String { "이기면 +\(stake)" }
    static func stakeGainSuffix(_ stake: Int) -> String { " · 이기면 +\(stake)" }
    static let stakeShortfall = "루비가 모자라요"
    /// ★ 루비가 **언제** 움직이는지를 말한다 — 신청만 한 상태에서는 0원도 안 움직인다.
    static let stakeCaption = "수락하는 순간 두 사람 모두 걸고, 이기면 판돈만큼 더 받아요"

    static let incomingTitle = "받은 신청"
    static func incomingTitle(name: String) -> String { "\(name)님의 신청" }
    static let inviteTTLHint = "1분 안에 응답하세요"
    static let outgoingTitle = "보낸 신청"
    static func outgoingTitle(name: String) -> String { "\(name)님에게 신청했어요" }
    /// ★ 보낸 신청의 사실: 만료돼도 **잃는 것이 없다**.
    static let outgoingCaption = "신청만 한 상태에서는 루비가 빠지지 않아요 · 1분 뒤 저절로 만료돼요"
    static let accept = "수락"
    static let decline = "거절"
    static let cancel = "취소"

    static let rulesTitle = "체스 규칙"
    /// 신청 TTL(초). ★ **코어가 그 값을 안 드러낸다** — `ChessStore.inviteTTLSeconds` 가 `private` 이라
    /// 로비 응답의 `invite_ttl_seconds` 를 읽을 길이 없다(서버·코어 기본값이 둘 다 60이다).
    /// 코어가 그 칸을 `package` 로 드러내는 날 이 상수를 지우고 그 값을 넘겨라(보고의 후속 목록).
    static let inviteTtlSecondsFallback = 60

    /// 한 사람 한 판 — 오목 판이 흐르는 동안의 안내(양방향 가운데 이쪽).
    /// 옮길 자리: `ChessPhoneText.entryBlock(playing: .gomoku)`.
    static let blockedByGomoku = "오목 대국이 끝나면 체스를 신청할 수 있어요"
    /// 로봇 판 중 — 신청만 막힌다(받은 신청은 묻고 수락한다).
    static let blockedByRobot = "로봇 판을 끝내면 1:1 대결을 신청할 수 있어요"

    /// 로봇 판을 두는 중에 받은 신청을 수락할 때 묻는 네 줄. **두던 판이 사라진다는 사실을 먼저 말한다.**
    static let acceptEndsRobotTitle = "로봇 판을 끝내고 수락할까요?"
    static let acceptEndsRobotMessage = "두던 로봇 판은 저장되지 않아요. 순위·루비와 상관없는 판이라 잃는 루비는 없어요."
    static let acceptEndsRobotConfirm = "끝내고 수락"
    static let acceptEndsRobotCancel = "그냥 두기"

    static func remaining(_ seconds: Double) -> String { "\(Int(max(0, seconds).rounded(.up)))초" }
    static func remainingPhrase(_ seconds: Double) -> String { remaining(seconds) + " 남음" }
}

// ╔══════════════════════════════════════════════════════════════════════════════════════════════╗
// ║ 자리표시 — **통합에서 이 블록을 통째로 지운다.**                                              ║
// ║                                                                                              ║
// ║ 아래 넷은 다른 레인이 자기 파일에 내놓는 이름이다(판 캔버스·대국·순위·관전·로봇 입구).         ║
// ║ 이 레인은 **입구와 로비**만 맡으므로, 그 파일들이 들어올 때까지 컴파일만 되게 빈 뷰로 둔다.     ║
// ║                                                                                              ║
// ║ ★ 일부러 `private` 이 **아니다.** private 로 두면 진짜 뷰가 들어와도 이 파일 안에서는 빈        ║
// ║   자리표시가 계속 이기고(파일 스코프가 먼저다) 화면이 **조용히 죽는다**. internal 로 두면       ║
// ║   진짜 뷰가 들어오는 순간 "invalid redeclaration" 으로 컴파일이 막히므로, 통합이 이 블록을      ║
// ║   지우는 것을 잊을 수 없다. 그 요란한 실패가 이 선택의 목적이다.                               ║
// ║                                                                                              ║
// ║ 서명 가정: 넷 다 `init(store: GamesStore)` — 폰 오목의 절들과 같은 관례                        ║
// ║ (`GamesGomokuRankingSection(store: GamesStore)` · `GamesGomokuWatch(store: GamesStore)`).      ║
// ║ 실제 서명이 다르면 이 블록을 지운 뒤 호출부 네 줄만 고치면 된다.                               ║
// ╚══════════════════════════════════════════════════════════════════════════════════════════════╝

/// 자리표시: 대국·결과 화면.
struct GamesChessMatchView: View {
    let store: GamesStore
    var body: some View { GamesChessPlaceholder(label: "대국 화면") }
}

/// 자리표시: 순위 절(로비 안 제자리).
struct GamesChessRankingSection: View {
    let store: GamesStore
    var body: some View { GamesChessPlaceholder(label: "체스 순위") }
}

/// 자리표시: 관전 절(로비 안 제자리 — "지금 대결 중" 목록과 관전 판).
struct GamesChessWatchSection: View {
    let store: GamesStore
    var body: some View { GamesChessPlaceholder(label: "지금 대결 중") }
}

/// 자리표시: 로봇과 두기 입구.
struct GamesChessAISection: View {
    let store: GamesStore
    var body: some View { GamesChessPlaceholder(label: "로봇과 두기") }
}

/// 자리표시: 규칙 시트. 서명이 셋인 까닭은 **시간 수치를 받아 쓰기** 위해서다 — 로비가 로비 응답 값을 넘긴다
/// (상수를 베끼면 10-12 에 5분 → 10분으로 늘어난 것 같은 변화마다 거짓이 된다).
struct GamesChessRulesSheet: View {
    let initialMs: Int
    let incrementMs: Int
    let inviteTtlSeconds: Int

    var body: some View { GamesChessPlaceholder(label: "체스 규칙") }
}

/// 자리표시 한 칸의 모양 — 비어 있지만 **자리는 보인다**(절이 통째로 사라지면 "로비가 반쪽"으로 읽힌다).
private struct GamesChessPlaceholder: View {
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(label, padded: true)
            InsetGroup {
                GroupRow(divider: .none) {
                    Text("준비 중이에요")
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                }
            }
        }
    }
}
#endif
