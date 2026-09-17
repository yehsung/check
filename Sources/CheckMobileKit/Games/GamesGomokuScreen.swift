#if os(iOS)
import CheckCore
import SwiftUI

/// 1:1 오목 화면(SPEC-ios §3.5) — 코어 `GomokuStore` 의 단계(로비 · 대국 · 결과)를 한 화면에서 갈아 끼운다.
///
/// 수명: 나타나면 `GamesStore.gomokuScreenDidAppear`(로비·인박스·진행 판 + 폴링), 사라지면 `gomokuScreenDidDisappear`.
/// 대국 중 화면 꺼짐 방지는 이 화면이 쓰지 않는다 — 주인은 `GamesStore`(판이 도는 동안은 화면을 떠나도 유지, 끝나면 푼다).
/// 내비 머리(가운데 제목·부제 · 규칙 · 더보기)와 탭 막대 숨김은 **단계 뷰가 제각각** 건다 — 로비는 탭 막대가 보이고, 대국·결과는 숨긴다(시안 B 08·09).
struct GamesGomokuScreen: View {
    let store: GamesStore

    @State private var stakeTarget: GomokuUser?
    @State private var showsResignConfirm = false
    @State private var demoPreview: GomokuPoint?

    private var gomoku: GomokuStore { store.context.gomoku }

    var body: some View {
        @Bindable var gomoku = gomoku
        content
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(GomokuPhoneText.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $gomoku.isRulesVisible) {
                GamesGomokuRulesSheet()
            }
            .sheet(item: $stakeTarget) { target in
                GamesGomokuStakeSheet(store: gomoku, target: target)
            }
            .onAppear {
                store.gomokuScreenDidAppear()
                applyDemoSeed()
            }
            .onDisappear {
                store.gomokuScreenDidDisappear()
            }
            .onChange(of: gomoku.match?.id) { _, _ in
                stakeTarget = nil
                showsResignConfirm = false
            }
    }

    @ViewBuilder
    private var content: some View {
        switch gomoku.phase {
        case .playing:
            if let match = gomoku.match {
                GamesGomokuMatch(store: store, match: match, showsResignConfirm: $showsResignConfirm, demoPreview: demoPreview)
            } else {
                lobby
            }
        case .result:
            if let match = gomoku.match {
                GamesGomokuResult(store: store, match: match)
            } else {
                lobby
            }
        case .lobby:
            lobby
        }
    }

    private var lobby: some View {
        GamesGomokuLobby(store: store, onChallenge: { stakeTarget = $0 })
    }

    private func applyDemoSeed() {
        #if DEBUG
        guard let seed = GamesDemoSeed.current(isDemo: store.context.isDemo) else { return }
        Task { @MainActor in
            switch seed {
            case .rules:
                gomoku.isRulesVisible = true
            case .stake:
                for _ in 0..<40 where gomoku.users.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
                stakeTarget = gomoku.users.first { GomokuPhoneChallengeGate.isEnabled(user: $0, store: gomoku) }
            case .resign:
                for _ in 0..<40 where gomoku.match == nil { try? await Task.sleep(for: .milliseconds(50)) }
                try? await Task.sleep(for: .milliseconds(1100))
                showsResignConfirm = gomoku.match != nil
            case .preview:
                demoPreview = GomokuPoint(notation: "I8")
            case .leave:
                for _ in 0..<60 where gomoku.phase != .result { try? await Task.sleep(for: .milliseconds(50)) }
                try? await Task.sleep(for: .milliseconds(2500))
                gomoku.backToLobby()
            case .playing, .result, .bottom, .visited:
                break
            }
        }
        #endif
    }
}

/// 규칙 책 버튼(세 단계가 같은 자리에 둔다).
struct GamesGomokuRulesButton: View {
    let store: GomokuStore

    var body: some View {
        Button {
            store.isRulesVisible = true
        } label: {
            Image(systemName: "book")
        }
        .accessibilityLabel(GomokuPhoneText.rulesTitle)
    }
}

// MARK: - 로비

/// 로비(시안 B 08): 전적·내 루비 두 칸 · 받은 신청(거절 회색 · 수락 채움 — 채운 버튼은 이것 하나) · 보낸 신청 · 상대 고르기(아바타 점 +
/// 회색 부제 · '도전' 틴트 알약 · 대국 중·업데이트 필요는 회색 비활성) · 지금 대결 중.
struct GamesGomokuLobby: View {
    let store: GamesStore
    let onChallenge: (GomokuUser) -> Void

    private var gomoku: GomokuStore { store.context.gomoku }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summary
                // 규칙 한 줄은 **머리가 아니라 첫 카드 아래**에 둔다 — 접힌 내비 부제는 밑으로 지나가는 파랑 [수락] 버튼 위에 얹혀
                // 4.0:1 까지 떨어졌고, 가장자리를 끊어도 4.4:1 에 머물렀다(w15 검증 medium 5 · 실측). 바탕 위에서는 4.7:1 이다.
                Text(GomokuPhoneText.subtitle)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                    .padding(.top, MobileTheme.space2)
                if let notice = gomoku.notice {
                    InlineNotice(text: notice, kind: .warning)
                        .padding(.top, MobileTheme.rowSpacing)
                }
                invites
                outgoing
                opponents
                liveMatches
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
            .padding(.bottom, MobileTheme.space6)
        }
        .refreshable {
            await gomoku.refreshLobby()
            await gomoku.loadInbox()
        }
        .gamesDemoScrollAnchor(isDemo: store.context.isDemo)
        // 로비 머리는 제목 하나다(부제는 첫 카드 아래로 내렸다 — 위 주석). 제목은 화면이 이미 `navigationTitle` 로 세웠다.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                GamesGomokuRulesButton(store: gomoku)
            }
        }
    }

    // MARK: 머리 두 칸

    private var summary: some View {
        InsetGroup {
            HStack(spacing: 0) {
                summaryCell(GomokuPhoneText.recordTitle) {
                    Text(gomoku.record.map { GomokuPhoneText.record($0) } ?? "–")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityLabel("내 오목 전적 \(GomokuPhoneText.record(gomoku.record))")
                Rectangle()
                    .fill(MobileTheme.separator)
                    .frame(width: MobileTheme.hairline)
                summaryCell(GomokuPhoneText.myRubyTitle) {
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

    // MARK: 받은 신청

    @ViewBuilder
    private var invites: some View {
        // 빈 받은함은 절을 통째로 접는다 — "없어요"는 **받은함을 알 때만**(공용 `MobileLoadKnowledge`)이고, 그때도 할 일이 없는 줄이라 빈칸만 만든다.
        switch MobileLoadKnowledge.placeholder(
            hasRows: !gomoku.incoming.isEmpty, hasLoaded: gomoku.hasLoadedInbox, lastFailed: gomoku.inboxLoadFailed
        ) {
        case .rows:
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
        case .empty:
            EmptyView()
        case .failed:
            SectionHeader(GomokuPhoneText.incomingTitle, padded: true)
            InsetGroup {
                GroupRow(divider: .none) {
                    LoadFailureRow(GomokuPhoneText.incomingLoadFailed) { Task { await gomoku.loadInbox() } }
                }
            }
        case .loading:
            SectionHeader(GomokuPhoneText.incomingTitle, padded: true)
            InsetGroup {
                GroupRow(divider: .none) { LoadingRow(GomokuPhoneText.loadingIncoming) }
            }
        }
    }

    @ViewBuilder
    private var outgoing: some View {
        if let outgoing = gomoku.outgoing {
            SectionHeader(GomokuPhoneText.outgoingTitle, padded: true)
            InsetGroup {
                GamesGomokuOutgoingRow(store: store, invite: outgoing)
            }
        }
    }

    // MARK: 상대 고르기

    @ViewBuilder
    private var opponents: some View {
        let users = gomoku.users
        SectionHeader(GomokuPhoneText.lobbyTitle, trailing: users.isEmpty ? .none : .text(GomokuPhoneText.peopleCount(users.count)), padded: true)
        InsetGroup {
            if gomoku.lobbyLoadFailed {
                GroupRow(divider: users.isEmpty ? .none : .inset(MobileTheme.cardPadding)) {
                    LoadFailureRow(GomokuPhoneText.usersLoadFailed) { Task { await gomoku.refreshLobby() } }
                }
            }
            if users.isEmpty {
                if !gomoku.lobbyLoadFailed {
                    GroupRow(divider: .none) {
                        if gomoku.hasLoadedLobby {
                            Text(GomokuPhoneText.emptyUsers)
                                .font(.subheadline)
                                .foregroundStyle(MobileTheme.label2)
                        } else {
                            LoadingRow(GomokuPhoneText.loadingUsers)
                        }
                    }
                }
            } else {
                ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                    GamesGomokuOpponentRow(store: store, user: user, isLast: index == users.count - 1, onChallenge: onChallenge)
                }
            }
        }
        Text(GomokuPhoneText.lobbyCaption)
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
    }

    // MARK: 지금 대결 중

    @ViewBuilder
    private var liveMatches: some View {
        let lives = gomoku.liveMatches
        switch MobileLoadKnowledge.placeholder(
            hasRows: !lives.isEmpty, hasLoaded: gomoku.hasLoadedLobby, lastFailed: gomoku.lobbyLoadFailed
        ) {
        case .rows:
            SectionHeader(GomokuPhoneText.liveTitle, trailing: .text(GomokuPhoneText.liveCount(lives.count)), padded: true)
            InsetGroup {
                ForEach(Array(lives.enumerated()), id: \.element.id) { index, live in
                    GamesLiveMatchRow(store: store, live: live, isLast: index == lives.count - 1)
                }
            }
        case .empty:
            SectionHeader(GomokuPhoneText.liveTitle, padded: true)
            InsetGroup {
                GroupRow(divider: .none) {
                    Text(GomokuPhoneText.noLiveMatches)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                }
            }
        case .failed:
            // 같은 조회(로비)의 [다시 시도]는 위 상대 고르기 절에 있다 — 여기선 한 줄만.
            SectionHeader(GomokuPhoneText.liveTitle, padded: true)
            InsetGroup {
                GroupRow(divider: .none) { LoadFailureRow(GomokuPhoneText.liveLoadFailed, retry: nil) }
            }
        case .loading:
            EmptyView()
        }
    }
}

/// 상대 한 줄(시안 B 08): 아바타(근무 중 점) · 이름 + 센터 배지 · 회색 부제 · 오른쪽 [도전] 틴트(또는 회색 비활성).
private struct GamesGomokuOpponentRow: View {
    let store: GamesStore
    let user: GomokuUser
    let isLast: Bool
    let onChallenge: (GomokuUser) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var canChallenge: Bool { GomokuPhoneChallengeGate.isEnabled(user: user, store: store.context.gomoku) }

    var body: some View {
        GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding + 36 + MobileTheme.space3), minHeight: 56) {
            // 큰 글자: [도전]을 아래 줄로 — 한 줄에 두면 이름이 글자 하나씩 꺾였다(AX 스크린샷 실측).
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
        PersonAvatar(name: user.displayName, colorSeed: user.id, status: user.presence, url: user.avatarLink, size: 36)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 1) {
            PersonName(user.displayName, center: CenterLabel.serverValue(forDisplay: user.center))
            Text(GomokuPhoneText.opponentStatus(for: user, liveMatches: store.context.gomoku.liveMatches))
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var challengeButton: some View {
        if canChallenge {
            AingButton(GomokuPhoneText.challenge, kind: .tinted, size: .sm) { onChallenge(user) }
                .fixedSize()
                .accessibilityHint("\(user.displayName)님에게 판돈을 골라 신청해요")
        } else {
            AingButton(user.inMatch ? GomokuPhoneText.inMatchButton : GomokuPhoneText.challenge, kind: .gray, size: .sm) {}
                .disabled(true)
                .fixedSize()
        }
    }
}

/// 받은 신청 한 건(시안 B 08): 아바타 44 · "솜사탕님의 신청" + 센터 · 판돈 줄 · [거절 회색] [수락 채움] 반반.
struct GamesGomokuInviteCard: View {
    let store: GamesStore
    let invite: GomokuInvite
    /// 머리가 첫 신청의 남은 초를 말한다 — 두 번째부터는 제 줄에 붙인다.
    var showsCountdown = false
    var isLast = true

    @Environment(\.dynamicTypeSize) private var typeSize

    private var gomoku: GomokuStore { store.context.gomoku }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 큰 글자(접근성 크기): 얼굴 위 · 글 아래 — 옆에 두면 판돈 줄이 "5 · 이기면 / +5"로 꺾였다(AX3 스크린샷 실측).
            let header = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: MobileTheme.space3))
            header {
                PersonAvatar(name: invite.peer.displayName, colorSeed: invite.peer.id, status: invite.peer.presence,
                             url: invite.peer.avatarLink, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    PersonName(GomokuPhoneText.incomingTitle(name: invite.peer.displayName),
                               center: CenterLabel.serverValue(forDisplay: invite.peer.center))
                    HStack(spacing: 0) {
                        GamesStakeLine(stake: invite.stake, suffix: GomokuPhoneText.stakeGainSuffix(invite.stake))
                        if showsCountdown {
                            GamesGomokuRemainingText(store: store, expiresAt: invite.expiresAt, prefix: " · ")
                        }
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
            // 큰 글자(접근성 크기): 위아래로 — 반 폭 둘에 두면 버튼 글자가 낱글자로 꺾일 수 있다.
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 8) { acceptButton; declineButton }
                } else {
                    HStack(spacing: 10) { declineButton; acceptButton }
                }
            }
            .padding(.horizontal, MobileTheme.cardPadding)
            .padding(.bottom, MobileTheme.cardPadding)
            if !isLast {
                Rectangle()
                    .fill(MobileTheme.separator)
                    .frame(height: MobileTheme.hairline)
                    .padding(.leading, MobileTheme.cardPadding)
            }
        }
    }

    private var acceptButton: some View {
        AingButton(GomokuPhoneText.accept, kind: .filled, size: .md, fillsWidth: true) {
            Task { await gomoku.respond(inviteID: invite.id, accept: true) }
        }
        .disabled(gomoku.isBusy)
    }

    private var declineButton: some View {
        AingButton(GomokuPhoneText.decline, kind: .gray, size: .md, fillsWidth: true) {
            Task { await gomoku.respond(inviteID: invite.id, accept: false) }
        }
        .disabled(gomoku.isBusy)
    }
}

/// 보낸 신청 한 줄: 아바타 · "구름빵님에게 신청했어요" · 판돈 · 남은 초 · [취소] 회색 알약.
private struct GamesGomokuOutgoingRow: View {
    let store: GamesStore
    let invite: GomokuInvite

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
        PersonAvatar(name: invite.peer.displayName, colorSeed: invite.peer.id, status: invite.peer.presence,
                     url: invite.peer.avatarLink, size: 36)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(GomokuPhoneText.outgoingTitle(name: invite.peer.displayName))
                .font(MobileTheme.rowTitle)
                .foregroundStyle(MobileTheme.label)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                GamesStakeLine(stake: invite.stake)
                GamesGomokuRemainingText(store: store, expiresAt: invite.expiresAt, prefix: " · ")
            }
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
        }
        .accessibilityElement(children: .combine)
    }

    private var cancelButton: some View {
        AingButton(GomokuPhoneText.cancel, kind: .gray, size: .sm) {
            Task { await store.context.gomoku.cancelChallenge() }
        }
        .disabled(store.context.gomoku.isBusy)
        .fixedSize()
    }
}

// MARK: - 초 단위 잎

/// 신청 만료까지 남은 초("42초 남음") — **잎 뷰**. 시계는 스토어 시계(데모 고정 시계와 같은 눈금).
struct GamesGomokuRemainingText: View {
    let store: GamesStore
    let expiresAt: Date
    var prefix = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = expiresAt.timeIntervalSince(store.context.clock.now())
            Text(prefix + GomokuPhoneText.remainingPhrase(remaining))
                .monospacedDigit()
                .accessibilityLabel("남은 시간 \(GomokuPhoneText.remaining(remaining))")
        }
    }
}
#endif
