#if os(iOS)
import CheckCore
import SwiftUI

// 1:1 알까기 폰 화면(1.0.18 — 맥 0.3.82 와 같은 서버 · 같은 규칙 · 루비 판돈 3/5/10 · 대표 "한 판에 전부" #d_xB6BJcn2nsCq).
// 입구 하나: 내 판이 있으면 판(결과 포함) → 관전 중이면 관전 → 연습 중이면 연습 → 아니면 로비.
// 로비 = 받은 신청 · 보낸 신청 · 상대 고르기 · 지금 대결 중(관전) · 내 전적 · 규칙 · [연습하기] · 순위.
// 상태 · 판정은 전부 코어 `AlkkagiOnlineStore` 다. 이 파일은 그리기와 누름만 한다.
struct GamesAlkkagiScreen: View {
    let store: GamesStore
    @State private var stakeTarget: AlkkagiLobbyUser?
    @State private var practicing = false

    var body: some View {
        let alkkagi = store.alkkagi
        Group {
            if alkkagi.state != nil {
                GamesAlkkagiMatchView(store: store)
            } else if let watch = alkkagi.watched {
                GamesAlkkagiWatchView(store: store, watch: watch)
            } else if practicing {
                GamesAlkkagiPracticeView(onExit: { practicing = false })
            } else {
                lobby
            }
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .navigationTitle(AlkkagiPhoneText.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.alkkagiScreenDidAppear()
            #if DEBUG
            // 데모 `games/alkkagi/practice`: 한 폰 연습 판으로 시작한다(서버 없이 서는 판 — `MobileDemoPhone1018Route`).
            if store.demoPhone1018Route?.opensAlkkagiPractice == true, alkkagi.state == nil { practicing = true }
            #endif
        }
        .onDisappear { store.alkkagiScreenDidDisappear() }
        // 서버 판이 서면 연습은 접는다(판이 이긴다 — 맥 창도 판으로 갈아 끼운다).
        .onChange(of: alkkagi.state?.id) { _, id in if id != nil { practicing = false } }
        .sheet(item: $stakeTarget) { user in
            GamesAlkkagiStakeSheet(store: store, target: user)
        }
    }

    /// 상태 줄의 글(없으면 nil) — 알림 칸이 같은 글이면 알림 칸을 접는다.
    static func availabilityLine(_ availability: AlkkagiAvailability) -> String? {
        switch availability {
        case .available: nil
        case .updateRequired: AlkkagiNoticeText.updateMine
        case .serverMissing: AlkkagiPhoneText.unavailable
        }
    }

    private var lobby: some View {
        let alkkagi = store.alkkagi
        let blockedBy = store.alkkagiEntryBlock
        return ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                Text(AlkkagiPhoneText.lobbyCaption)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                // 문이 닫혔을 때 코어는 같은 글('곧 열려요' · '업데이트')을 알림 칸에도 싣는다 — 아래 상태 줄과 겹치면 한 번만 보인다
                // (11-10 시뮬레이터 캡처에서 두 줄로 겹쳐 보였다).
                if let notice = alkkagi.notice, notice != Self.availabilityLine(alkkagi.availability) {
                    InlineNotice(text: notice, kind: .info)
                }
                if let blockedBy, let line = ChessPhoneText.entryBlockHint(playing: blockedBy.text, blocked: .alkkagi) {
                    InlineNotice(text: line, kind: .info)
                }
                switch alkkagi.availability {
                case .available: EmptyView()
                case .updateRequired: InlineNotice(text: AlkkagiNoticeText.updateMine, kind: .error)
                case .serverMissing: InlineNotice(text: AlkkagiPhoneText.unavailable, kind: .info)
                }
                if !alkkagi.visibleIncomingInvites.isEmpty {
                    SectionHeader(AlkkagiPhoneText.incomingTitle)
                    ForEach(alkkagi.visibleIncomingInvites) { invite in
                        InsetGroup { GamesAlkkagiInviteCard(store: store, invite: invite) }
                    }
                }
                if let outgoing = alkkagi.outgoing {
                    SectionHeader(AlkkagiPhoneText.outgoingTitle)
                    InsetGroup { GamesAlkkagiOutgoingRow(store: store, invite: outgoing) }
                }
                SectionHeader(AlkkagiPhoneText.usersTitle)
                InsetGroup { users(blockedBy: blockedBy) }
                if alkkagi.spectatorFeaturesEnabled {
                    SectionHeader(AlkkagiPhoneText.liveTitle)
                    InsetGroup { liveMatches }
                }
                SectionHeader(AlkkagiPhoneText.recordTitle)
                InsetGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AlkkagiPhoneText.record(alkkagi.record))
                            .font(.headline)
                            .monospacedDigit()
                        Text(AlkkagiPhoneText.rulesTitle)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MobileTheme.label2)
                        ForEach(AlkkagiPhoneText.rulesLines, id: \.self) { line in
                            Text("· " + line)
                                .font(.footnote)
                                .foregroundStyle(MobileTheme.label2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        AingButton(AlkkagiPhoneText.practiceButton, systemImage: "figure.2", kind: .tinted, size: .md, fillsWidth: true) {
                            practicing = true
                        }
                        .padding(.top, 4)
                        .accessibilityHint(Text(AlkkagiPhoneText.practiceHelp))
                        Text(AlkkagiPhoneText.practiceHelp)
                            .font(.caption)
                            .foregroundStyle(MobileTheme.label3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MobileTheme.cardPadding)
                }
                GamesAlkkagiRankingSection(store: store)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.rowSpacing)
        }
        .refreshable { await alkkagi.refreshLobby() }
    }

    @ViewBuilder
    private func users(blockedBy: GamesBusyGame?) -> some View {
        let alkkagi = store.alkkagi
        let users = alkkagi.visibleUsers
        if users.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(alkkagi.lobbyLoadFailed ? AlkkagiPhoneText.usersLoadFailed
                     : (alkkagi.hasLoadedLobby ? AlkkagiPhoneText.emptyUsers : AlkkagiPhoneText.loadingUsers))
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                if alkkagi.lobbyLoadFailed {
                    AingButton(AlkkagiPhoneText.reloadUsers, kind: .tinted, size: .sm) {
                        Task { await alkkagi.refreshLobby() }
                    }
                    .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MobileTheme.cardPadding)
        } else {
            ForEach(Array(users.enumerated()), id: \.element.id) { offset, user in
                let status = AlkkagiPhoneText.userStatus(user)
                let enabled = status.canChallenge && blockedBy == nil && !alkkagi.isBusy && alkkagi.availability == .available
                GroupRow(divider: offset == users.count - 1 ? .none : .inset(MobileTheme.cardPadding + 36 + MobileTheme.space3), minHeight: 56) {
                    PersonAvatar(name: user.displayName, colorSeed: user.id, status: user.isWorking ? .working : nil,
                                 url: user.avatarURL.flatMap(URL.init(string:)), userID: user.id, size: 36,
                                 characterHint: user.characterID)
                    VStack(alignment: .leading, spacing: 1) {
                        PersonName(user.displayName)
                        Text(status.subtitle)
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(user.isCapable ? MobileTheme.label2 : MobileTheme.pending)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 8)
                    AingButton(AlkkagiPhoneText.challenge, kind: enabled ? .tinted : .gray, size: .sm) {
                        stakeTarget = user
                    }
                    .disabled(!enabled)
                    .fixedSize()
                    .accessibilityLabel(Text("\(user.displayName)님에게 \(AlkkagiPhoneText.title) \(AlkkagiPhoneText.challenge)"))
                }
            }
        }
    }

    /// 지금 대결 중(남의 판 — 내가 낀 판은 서버가 뺀다). [관전] 은 내 판이 흐르는 동안 닫힌다(코어 `watch` 도 막는다).
    @ViewBuilder
    private var liveMatches: some View {
        let alkkagi = store.alkkagi
        let matches = alkkagi.liveMatches
        if matches.isEmpty {
            Text(AlkkagiPhoneText.noLive)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MobileTheme.cardPadding)
        } else {
            ForEach(Array(matches.enumerated()), id: \.element.id) { offset, match in
                GroupRow(divider: offset == matches.count - 1 ? .none : .inset(MobileTheme.cardPadding), minHeight: 52) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AlkkagiPhoneText.liveLine(match))
                            .font(MobileTheme.rowTitle)
                            .foregroundStyle(MobileTheme.label)
                            .lineLimit(1)
                        Text(AlkkagiPhoneText.liveDetail(match))
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.label2)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 8)
                    AingButton(AlkkagiPhoneText.watch, systemImage: "eye", kind: .tinted, size: .sm) {
                        alkkagi.watch(matchID: match.id)
                    }
                    .disabled(store.hasLiveAlkkagiMatch)
                    .fixedSize()
                }
            }
        }
    }
}

/// 받은 신청 한 장(수락 · 거절). 수락하면 판이 선다(코어가 `state` 를 세운다).
struct GamesAlkkagiInviteCard: View {
    let store: GamesStore
    let invite: AlkkagiInvite

    var body: some View {
        let alkkagi = store.alkkagi
        let stake = invite.stake
        let canAccept = store.alkkagiEntryBlock == nil && !alkkagi.isBusy && alkkagi.availability == .available
            && (stake.map { need in store.rubyBalance.map { $0 >= need } ?? true } ?? true)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: MobileTheme.space3) {
                PersonAvatar(name: invite.opponent.displayName, colorSeed: invite.opponent.id,
                             url: invite.opponent.avatarURL.flatMap(URL.init(string:)), userID: invite.opponent.id, size: 44,
                             characterHint: invite.opponent.characterID)
                VStack(alignment: .leading, spacing: 1) {
                    PersonName(AlkkagiPhoneText.incomingFrom(invite.opponent.displayName))
                    HStack(spacing: 0) {
                        if let stake {
                            GamesStakeLine(stake: stake, prefix: AlkkagiPhoneText.stakeTitle,
                                           suffix: " · 이기면 +\(DuelFee.winnerNet(stake: stake))")
                        }
                        GamesAlkkagiRemaining(store: alkkagi, expiresAtMs: invite.expiresAtMs)
                    }
                    .font(MobileTheme.rowSubtitle)
                    .foregroundStyle(MobileTheme.label2)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                AingButton(AlkkagiPhoneText.decline, kind: .gray, size: .md, fillsWidth: true) {
                    Task { await alkkagi.respond(inviteID: invite.id, accept: false) }
                }
                .disabled(alkkagi.isBusy)
                AingButton(AlkkagiPhoneText.accept, kind: .filled, size: .md, fillsWidth: true) {
                    Task { await alkkagi.respond(inviteID: invite.id, accept: true) }
                }
                .disabled(!canAccept)
            }
        }
        .padding(MobileTheme.cardPadding)
    }
}

/// 보낸 신청 한 줄(취소).
struct GamesAlkkagiOutgoingRow: View {
    let store: GamesStore
    let invite: AlkkagiInvite

    var body: some View {
        let alkkagi = store.alkkagi
        GroupRow(divider: .none, minHeight: 56) {
            PersonAvatar(name: invite.opponent.displayName, colorSeed: invite.opponent.id,
                         url: invite.opponent.avatarURL.flatMap(URL.init(string:)), userID: invite.opponent.id, size: 36,
                         characterHint: invite.opponent.characterID)
            VStack(alignment: .leading, spacing: 1) {
                Text(AlkkagiPhoneText.outgoingTo(invite.opponent.displayName))
                    .font(MobileTheme.rowTitle)
                    .foregroundStyle(MobileTheme.label)
                HStack(spacing: 0) {
                    if let stake = invite.stake {
                        GamesStakeLine(stake: stake, prefix: AlkkagiPhoneText.stakeTitle)
                    }
                    GamesAlkkagiRemaining(store: alkkagi, expiresAtMs: invite.expiresAtMs)
                }
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            AingButton(AlkkagiPhoneText.cancel, kind: .gray, size: .sm) {
                Task { await alkkagi.cancelChallenge() }
            }
            .disabled(alkkagi.isBusy)
            .fixedSize()
        }
    }
}

/// " · 42초 남음"(서버 보정 시계 · 1초마다).
struct GamesAlkkagiRemaining: View {
    let store: AlkkagiOnlineStore
    let expiresAtMs: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(" · " + AlkkagiPhoneText.remaining(Int(((expiresAtMs - store.estimatedServerNowMs) / 1_000).rounded(.up))))
                .monospacedDigit()
        }
    }
}

/// 판돈 고르기(3 · 5 · 10) → 도전. 잔액이 모자라는 칸은 흐리다(서버도 막는다). 고른 판돈은 코어가 기억한다(`selectedStake`).
struct GamesAlkkagiStakeSheet: View {
    let store: GamesStore
    let target: AlkkagiLobbyUser

    @Environment(\.dismiss) private var dismiss
    @State private var selected: AlkkagiStake?

    var body: some View {
        let balance = store.rubyBalance
        VStack(spacing: 0) {
            SheetHeader(AlkkagiPhoneText.stakeTitle, subtitle: AlkkagiPhoneText.stakePromptTitle(name: target.displayName),
                        onClose: { dismiss() })
            VStack(alignment: .leading, spacing: MobileTheme.space4) {
                HStack(spacing: 10) {
                    ForEach(AlkkagiStake.allCases, id: \.rawValue) { stake in
                        let affordable = balance.map { $0 >= stake.rawValue } ?? true
                        Button { selected = stake } label: {
                            VStack(spacing: 4) {
                                HStack(spacing: 3) {
                                    RubyIcon(size: 16)
                                    Text("\(stake.rawValue)").font(.title3.weight(.bold)).monospacedDigit()
                                }
                                Text("이기면 +\(DuelFee.winnerNet(stake: stake.rawValue))")
                                    .font(.caption)
                                    .foregroundStyle(MobileTheme.label2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .background(RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
                                .fill(selected == stake ? MobileTheme.accentTint : MobileTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
                                .strokeBorder(selected == stake ? MobileTheme.accent : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .disabled(!affordable)
                        .opacity(affordable ? 1 : 0.45)
                        .accessibilityLabel(Text("판돈 \(stake.rawValue)"))
                    }
                }
                if let balance, AlkkagiStake.allCases.contains(where: { balance < $0.rawValue }) {
                    Text(AlkkagiPhoneText.stakeShortfall)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                }
                Spacer(minLength: 0)
            }
            .padding(MobileTheme.sideMargin)
            AingButton(selected.map { AlkkagiPhoneText.challengeWithStake($0.rawValue) } ?? AlkkagiPhoneText.stakePromptCaption,
                       kind: .filled, size: .lg, fillsWidth: true) {
                guard let stake = selected else { return }
                dismiss()
                Task { await store.alkkagi.challenge(opponentID: target.id, stake: stake) }
            }
            .disabled(selected == nil || store.alkkagiEntryBlock != nil || store.alkkagi.isBusy)
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.bottom, MobileTheme.space4)
        }
        .presentationDetents([.medium])
        .onAppear {
            // 지난번 고른 판돈(코어 기억 — 맥 D16)을 미리 고른다. 잔액이 모자라면 비워 둔다.
            let remembered = store.alkkagi.selectedStake
            if balance.map({ $0 >= remembered.rawValue }) ?? true { selected = remembered }
        }
    }
}

/// 순위(승점 = 승 − 패) — 맥과 같은 서버(`alkkagi_ranking`).
struct GamesAlkkagiRankingSection: View {
    let store: GamesStore

    var body: some View {
        let alkkagi = store.alkkagi
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            SectionHeader(AlkkagiPhoneText.rankTitle, trailing: .text(AlkkagiPhoneText.rankHelp))
            InsetGroup {
                if let board = alkkagi.ranking, !board.entries.isEmpty {
                    let entries = Array(board.entries.prefix(20))
                    ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                        GroupRow(divider: offset == entries.count - 1 ? .none : .inset(MobileTheme.cardPadding), minHeight: 48) {
                            Text("\(entry.rank)")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .frame(width: 28)
                            PersonAvatar(name: entry.displayName, colorSeed: entry.id,
                                         url: entry.avatarURL.flatMap(URL.init(string:)), userID: entry.id, size: 28,
                                         characterHint: entry.characterID)
                            PersonName(entry.displayName)
                            Spacer(minLength: 8)
                            Text(AlkkagiPhoneText.points(entry.points))
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(MobileTheme.label2)
                        }
                    }
                } else {
                    Text(alkkagi.rankingUnavailable ? AlkkagiPhoneText.rankSoon
                         : (alkkagi.ranking == nil ? AlkkagiPhoneText.rankLoading : AlkkagiPhoneText.rankEmpty))
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(MobileTheme.cardPadding)
                }
            }
        }
        .task { await alkkagi.refreshRanking() }
    }
}
#endif
