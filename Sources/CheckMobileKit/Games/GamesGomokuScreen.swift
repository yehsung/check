#if os(iOS)
import CheckCore
import SwiftUI

/// 1:1 오목 화면(SPEC-ios §3.5) — 코어 `GomokuStore` 의 단계(로비 · 대국 · 결과)를 한 화면에서 갈아 끼운다.
///
/// 수명: 나타나면 `GamesStore.gomokuScreenDidAppear`(로비·인박스·진행 판 + 폴링), 사라지면 `gomokuScreenDidDisappear`.
/// 대국 중 화면 꺼짐 방지는 이 화면이 쓰지 않는다 — 주인은 `GamesStore`(판이 도는 동안은 화면을 떠나도 유지, 끝나면 푼다).
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        gomoku.isRulesVisible = true
                    } label: {
                        Label(GomokuPhoneText.rulesButton, systemImage: "book")
                    }
                    .accessibilityLabel(GomokuPhoneText.rulesTitle)
                }
            }
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
            case .playing, .result, .bottom:
                break
            }
        }
        #endif
    }
}

// MARK: - 로비

/// 로비: 전적·루비 · 안내 · 받은 신청(수락·거절·남은 초) · 보낸 신청(취소) · 상대 고르기 · 지금 대결 중.
struct GamesGomokuLobby: View {
    let store: GamesStore
    let onChallenge: (GomokuUser) -> Void

    private var gomoku: GomokuStore { store.context.gomoku }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                summary
                if let notice = gomoku.notice {
                    InlineNotice(text: notice, kind: .warning)
                }
                invites
                opponents
                liveMatches
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.rowSpacing)
        }
        .refreshable {
            await gomoku.refreshLobby()
            await gomoku.loadInbox()
        }
        .gamesDemoScrollAnchor(isDemo: store.context.isDemo)
    }

    private var summary: some View {
        AingCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { summaryTitle; Spacer(minLength: 8); summaryChips }
                VStack(alignment: .leading, spacing: 10) { summaryTitle; summaryChips }
            }
        }
    }

    private var summaryTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(GomokuPhoneText.title)
                .font(MobileTheme.title(.title3))
                .foregroundStyle(MobileTheme.primaryText)
            Text(GomokuPhoneText.subtitle)
                .font(.caption)
                .foregroundStyle(MobileTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var summaryChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { recordChip; rubyChip }
            VStack(alignment: .leading, spacing: 8) { recordChip; rubyChip }
        }
    }

    private var recordChip: some View {
        Group {
            Label(GomokuPhoneText.record(gomoku.record), systemImage: "flag.checkered")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(MobileTheme.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(MobileTheme.cardElevated))
                .accessibilityLabel("내 오목 전적 \(GomokuPhoneText.record(gomoku.record))")
                .fixedSize()
        }
    }

    private var rubyChip: some View {
        RubyLabel(store.rubyBalance)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(MobileTheme.cardElevated))
            .fixedSize()
    }

    // MARK: 신청

    @ViewBuilder
    private var invites: some View {
        AingCard {
            SectionHeader(GomokuPhoneText.incomingTitle)
            // 빈 받은함을 "없어요"로 말하는 것은 **받은함을 알 때만**(공용 `MobileLoadKnowledge`) — 오프라인에서 "받은 신청이 없어요"가 떴다.
            switch MobileLoadKnowledge.placeholder(
                hasRows: !gomoku.incoming.isEmpty, hasLoaded: gomoku.hasLoadedInbox, lastFailed: gomoku.inboxLoadFailed
            ) {
            case .rows:
                ForEach(gomoku.pendingIncomingInvites) { invite in
                    GamesGomokuInviteCard(store: store, invite: invite)
                }
            case .empty:
                Text(GomokuPhoneText.noIncoming)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.secondaryText)
            case .failed:
                LoadFailureRow(GomokuPhoneText.incomingLoadFailed) { Task { await gomoku.loadInbox() } }
            case .loading:
                LoadingRow(GomokuPhoneText.loadingIncoming)
            }
            if let outgoing = gomoku.outgoing {
                Divider().overlay(MobileTheme.separator)
                GamesGomokuOutgoingRow(store: store, invite: outgoing)
            }
        }
    }

    // MARK: 상대 목록

    private var opponents: some View {
        AingCard {
            SectionHeader(GomokuPhoneText.lobbyTitle)
            Text(GomokuPhoneText.lobbyCaption)
                .font(.caption)
                .foregroundStyle(MobileTheme.secondaryText)
            if gomoku.lobbyLoadFailed {
                LoadFailureRow(GomokuPhoneText.usersLoadFailed) { Task { await gomoku.refreshLobby() } }
            }
            if gomoku.users.isEmpty {
                if !gomoku.lobbyLoadFailed {
                    if gomoku.hasLoadedLobby {
                        Text(GomokuPhoneText.emptyUsers)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.secondaryText)
                    } else {
                        LoadingRow(GomokuPhoneText.loadingUsers)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(gomoku.users) { user in
                        GamesGomokuOpponentRow(store: store, user: user, onChallenge: onChallenge)
                    }
                }
            }
        }
    }

    // MARK: 지금 대결 중

    private var liveMatches: some View {
        AingCard {
            SectionHeader(GomokuPhoneText.liveTitle)
            switch MobileLoadKnowledge.placeholder(
                hasRows: !gomoku.liveMatches.isEmpty, hasLoaded: gomoku.hasLoadedLobby, lastFailed: gomoku.lobbyLoadFailed
            ) {
            case .rows:
                ForEach(gomoku.liveMatches) { live in
                    GamesGomokuLiveMatchRow(store: store, live: live)
                }
            case .empty:
                Text(GomokuPhoneText.noLiveMatches)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.secondaryText)
            case .failed:
                // 같은 조회(로비)의 [다시 시도]는 바로 위 상대 고르기 절에 있다 — 여기선 한 줄만.
                LoadFailureRow(GomokuPhoneText.liveLoadFailed, retry: nil)
            case .loading:
                LoadingRow(GomokuPhoneText.loadingUsers)
            }
        }
    }
}

private struct GamesGomokuOpponentRow: View {
    let store: GamesStore
    let user: GomokuUser
    let onChallenge: (GomokuUser) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var canChallenge: Bool { GomokuPhoneChallengeGate.isEnabled(user: user, store: store.context.gomoku) }

    private var chipTint: Color {
        if user.inMatch { return MobileTheme.pending }
        if !user.isCapable { return MobileTheme.secondaryText }
        return user.isWorking ? MobileTheme.working : MobileTheme.offWork
    }

    var body: some View {
        // 큰 글자: [도전]을 아래 줄로 — 한 줄에 두면 이름이 글자 하나씩 꺾였다(AX 스크린샷 실측).
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) { avatar; info }
                challengeButton(fillsWidth: true)
            }
        } else {
            HStack(spacing: 12) {
                avatar
                info
                Spacer(minLength: 8)
                challengeButton(fillsWidth: false)
            }
        }
    }

    private var avatar: some View {
        AvatarView(name: user.displayName, url: user.avatarURL.flatMap(URL.init(string:)), size: 38)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(user.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MobileTheme.primaryText)
                    .lineLimit(2)
                CenterBadge(CenterLabel.serverValue(forDisplay: user.center))
                    .fixedSize()
            }
            Text(GomokuPhoneText.status(for: user))
                .font(.caption.weight(.bold))
                .foregroundStyle(chipTint)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(chipTint.opacity(0.16)))
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private func challengeButton(fillsWidth: Bool) -> some View {
        Button {
            onChallenge(user)
        } label: {
            Label(GomokuPhoneText.challenge, systemImage: "bolt.fill")
                .font(.subheadline.weight(.bold))
        }
        .buttonStyle(GamesCompactButtonStyle(kind: .filled, fillsWidth: fillsWidth))
        .disabled(!canChallenge)
        .fixedSize(horizontal: !fillsWidth, vertical: true)
        .accessibilityHint("\(user.displayName)님에게 판돈을 골라 신청해요")
    }
}

/// 받은 신청 카드 한 장(수락 · 거절 · 남은 초).
struct GamesGomokuInviteCard: View {
    let store: GamesStore
    let invite: GomokuInvite

    @Environment(\.dynamicTypeSize) private var typeSize

    private var gomoku: GomokuStore { store.context.gomoku }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { inviteAvatar; inviteTexts; Spacer(minLength: 6); countdown }
                VStack(alignment: .leading, spacing: 8) { HStack(spacing: 10) { inviteAvatar; countdown }; inviteTexts }
            }
            // 큰 글자(접근성 크기): 위아래로 — 버튼 글자가 줄을 바꾸게 되어(잘림 대신), 반 폭 둘에 두면 낱글자로 꺾일 수 있다.
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) { acceptButton; declineButton }
            } else {
                HStack(spacing: 8) { acceptButton; declineButton }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MobileTheme.accent.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MobileTheme.accent.opacity(0.45), lineWidth: 1))
    }

    private var acceptButton: some View {
        Button {
            Task { await gomoku.respond(inviteID: invite.id, accept: true) }
        } label: {
            Label(GomokuPhoneText.accept, systemImage: "checkmark")
        }
        .buttonStyle(GamesCompactButtonStyle(kind: .filled, fillsWidth: true))
        .disabled(gomoku.isBusy)
    }

    private var declineButton: some View {
        Button(GomokuPhoneText.decline) {
            Task { await gomoku.respond(inviteID: invite.id, accept: false) }
        }
        .buttonStyle(GamesCompactButtonStyle(kind: .outline, fillsWidth: true))
        .disabled(gomoku.isBusy)
    }

    private var inviteAvatar: some View {
        AvatarView(name: invite.peer.displayName, url: invite.peer.avatarURL.flatMap(URL.init(string:)), size: 36)
    }

    private var inviteTexts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(GomokuPhoneText.incomingTitle(name: invite.peer.displayName))
                .font(.body.weight(.semibold))
                .foregroundStyle(MobileTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                Text(GomokuPhoneText.stakeTitle)
                RubyLabel(invite.stake, style: .caption)
            }
            .font(.caption)
            .foregroundStyle(MobileTheme.secondaryText)
        }
    }

    private var countdown: some View {
        GamesGomokuCountdown(store: store, expiresAt: invite.expiresAt)
    }
}

private struct GamesGomokuOutgoingRow: View {
    let store: GamesStore
    let invite: GomokuInvite

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { title; Spacer(minLength: 4); trailing }
            VStack(alignment: .leading, spacing: 8) { title; trailing }
        }
    }

    private var title: some View {
        HStack(spacing: 8) {
            AvatarView(name: invite.peer.displayName, url: invite.peer.avatarURL.flatMap(URL.init(string:)), size: 26)
            Text(GomokuPhoneText.outgoingTitle(name: invite.peer.displayName))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MobileTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trailing: some View {
        HStack(spacing: 8) {
            RubyLabel(invite.stake, style: .caption)
            GamesGomokuCountdown(store: store, expiresAt: invite.expiresAt)
            Button(GomokuPhoneText.cancel) {
                Task { await store.context.gomoku.cancelChallenge() }
            }
            .buttonStyle(GamesCompactButtonStyle(kind: .outline))
            .disabled(store.context.gomoku.isBusy)
        }
    }
}

private struct GamesGomokuLiveMatchRow: View {
    let store: GamesStore
    let live: GomokuLiveMatch

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { faces; Spacer(minLength: 6); meta }
            VStack(alignment: .leading, spacing: 6) {
                face(live.a)
                Text("vs")
                    .font(.caption)
                    .foregroundStyle(MobileTheme.secondaryText)
                face(live.b)
                meta
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MobileTheme.cardElevated))
        .accessibilityElement(children: .combine)
    }

    private var faces: some View {
        HStack(spacing: 8) {
            face(live.a)
            Text("vs")
                .font(.caption)
                .foregroundStyle(MobileTheme.secondaryText)
            face(live.b)
        }
    }

    private var meta: some View {
        HStack(spacing: 8) {
            RubyLabel(live.stake.rawValue, style: .caption)
            GamesGomokuElapsed(store: store, startedAt: live.startedAt)
        }
        .fixedSize()
    }

    private func face(_ user: GomokuUser) -> some View {
        HStack(spacing: 6) {
            AvatarView(name: user.displayName, url: user.avatarURL.flatMap(URL.init(string:)), size: 24)
            Text(user.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MobileTheme.primaryText)
                .fixedSize()
        }
    }
}

// MARK: - 초 단위 잎

/// 신청 만료까지 남은 초 — **잎 뷰**. 시계는 스토어 시계(데모 고정 시계와 같은 눈금).
struct GamesGomokuCountdown: View {
    let store: GamesStore
    let expiresAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let clock = store.context.clock
            Text(GomokuPhoneText.remaining(expiresAt.timeIntervalSince(clock.now())))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(MobileTheme.pending)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(MobileTheme.pending.opacity(0.14)))
                .fixedSize()
                .accessibilityLabel("남은 시간 \(GomokuPhoneText.remaining(expiresAt.timeIntervalSince(clock.now())))")
        }
    }
}

/// 대결이 시작된 뒤 흐른 시간(m:ss) — 잎 뷰.
struct GamesGomokuElapsed: View {
    let store: GamesStore
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(GomokuPhoneText.elapsed(store.context.clock.now().timeIntervalSince(startedAt)))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(MobileTheme.secondaryText)
        }
    }
}
#endif
