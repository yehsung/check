#if os(iOS)
import CheckCore
import SwiftUI

// 1:1 길건너 폰 화면(1.0.18 — 맥 0.3.78 과 같은 서버 · 같은 규칙 · 루비 판돈 3/5/10 · 대표 #d_t103CxfPGinB "셋 다 루비 그대로").
// 로비(받은 신청 · 보낸 신청 · 상대 고르기 · 내 전적 · 규칙 · 순위) → 판(준비 · 카운트다운 · 달리기) → 결과. 관전은 없다(SPEC Q1).
// 상태 · 판정은 전부 코어 `CrossyDuelStore` 다. 이 파일은 그리기와 손짓만 한다.
struct GamesCrossyDuelScreen: View {
    let store: GamesStore
    @State private var stakeTarget: CrossyDuelUser?

    var body: some View {
        let duel = store.crossyDuel
        Group {
            switch duel.phase {
            case .lobby:
                lobby
            case .ready, .countdown, .playing, .finished:
                GamesCrossyDuelMatchView(store: store)
            }
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .navigationTitle(CrossyDuelPhoneText.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.crossyDuelScreenDidAppear() }
        .onDisappear { store.crossyDuelScreenDidDisappear() }
        .sheet(item: $stakeTarget) { user in
            GamesCrossyDuelStakeSheet(store: store, target: user)
        }
    }

    private var lobby: some View {
        let duel = store.crossyDuel
        let blockedBy = store.crossyDuelEntryBlock
        return ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                Text(CrossyDuelPhoneText.lobbyCaption)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                if let notice = duel.notice {
                    InlineNotice(text: notice, kind: .info)
                }
                if let blockedBy, let line = ChessPhoneText.entryBlockHint(playing: blockedBy.text, blocked: .crossyDuel) {
                    InlineNotice(text: line, kind: .info)
                }
                if duel.availability != .available {
                    InlineNotice(text: duel.availability == .updateRequired ? CrossyDuelPhoneText.needsUpdate : CrossyDuelNoticeText.checkConnection,
                                 kind: .error)
                }
                if !duel.visibleIncomingInvites.isEmpty {
                    SectionHeader(CrossyDuelPhoneText.incomingTitle)
                    ForEach(duel.visibleIncomingInvites) { invite in
                        InsetGroup { GamesCrossyDuelInviteCard(store: store, invite: invite) }
                    }
                }
                if let outgoing = duel.outgoing {
                    SectionHeader(CrossyDuelPhoneText.outgoingTitle)
                    InsetGroup { GamesCrossyDuelOutgoingRow(store: store, invite: outgoing) }
                }
                SectionHeader(CrossyDuelPhoneText.usersTitle)
                InsetGroup { users(blockedBy: blockedBy) }
                SectionHeader(CrossyDuelPhoneText.recordTitle)
                InsetGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(CrossyDuelPhoneText.record(duel.record))
                            .font(.headline)
                            .monospacedDigit()
                        Text(CrossyDuelPhoneText.howTitle)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MobileTheme.label2)
                        ForEach(CrossyDuelPhoneText.howLines, id: \.self) { line in
                            Text("· " + line)
                                .font(.footnote)
                                .foregroundStyle(MobileTheme.label2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MobileTheme.cardPadding)
                }
                GamesCrossyDuelRankingSection(store: store)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.rowSpacing)
        }
        .refreshable { await duel.refreshLobby() }
    }

    @ViewBuilder
    private func users(blockedBy: GamesBusyGame?) -> some View {
        let duel = store.crossyDuel
        let users = duel.visibleUsers
        if users.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(duel.lobbyLoadFailed ? CrossyDuelPhoneText.usersLoadFailed
                     : (duel.hasLoadedLobby ? CrossyDuelPhoneText.emptyUsers : CrossyDuelPhoneText.loadingUsers))
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                if duel.lobbyLoadFailed {
                    AingButton(CrossyDuelPhoneText.reloadUsers, kind: .tinted, size: .sm) {
                        Task { await duel.refreshLobby() }
                    }
                    .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MobileTheme.cardPadding)
        } else {
            ForEach(Array(users.enumerated()), id: \.element.id) { offset, user in
                let status = CrossyDuelPhoneText.userStatus(user)
                let enabled = status.canChallenge && blockedBy == nil && duel.outgoing == nil && !duel.isBusy
                    && duel.availability == .available
                GroupRow(divider: offset == users.count - 1 ? .none : .inset(MobileTheme.cardPadding + 36 + MobileTheme.space3), minHeight: 56) {
                    PersonAvatar(name: user.displayName, colorSeed: user.id, status: user.isWorking ? .working : nil,
                                 url: user.avatarURL.flatMap(URL.init(string:)), userID: user.id, size: 36,
                                 characterHint: user.characterID)
                    VStack(alignment: .leading, spacing: 1) {
                        PersonName(user.displayName)
                        Text(status.subtitle)
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.label2)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 8)
                    AingButton(CrossyDuelPhoneText.challenge, kind: enabled ? .tinted : .gray, size: .sm) {
                        stakeTarget = user
                    }
                    .disabled(!enabled)
                    .fixedSize()
                }
            }
        }
    }
}

/// 받은 신청 한 장(수락 · 거절). 수락하면 판으로 넘어간다(코어가 `phase` 를 바꾼다).
struct GamesCrossyDuelInviteCard: View {
    let store: GamesStore
    let invite: CrossyDuelInvite

    var body: some View {
        let duel = store.crossyDuel
        let canAccept = store.crossyDuelEntryBlock == nil && !duel.isBusy
            && (store.rubyBalance.map { $0 >= invite.stake } ?? true)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: MobileTheme.space3) {
                PersonAvatar(name: invite.peer.displayName, colorSeed: invite.peer.id,
                             url: invite.peer.avatarURL.flatMap(URL.init(string:)), userID: invite.peer.id, size: 44,
                             characterHint: invite.peer.characterID)
                VStack(alignment: .leading, spacing: 1) {
                    PersonName(CrossyDuelPhoneText.incomingFrom(invite.peer.displayName))
                    HStack(spacing: 0) {
                        GamesStakeLine(stake: invite.stake, prefix: CrossyDuelPhoneText.stakeTitle,
                                       suffix: " · 이기면 +\(DuelFee.winnerNet(stake: invite.stake))")
                        GamesCrossyDuelRemaining(store: duel, expiresAt: invite.expiresAt)
                    }
                    .font(MobileTheme.rowSubtitle)
                    .foregroundStyle(MobileTheme.label2)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                AingButton(CrossyDuelPhoneText.decline, kind: .gray, size: .md, fillsWidth: true) {
                    Task { await duel.respond(inviteID: invite.id, accept: false) }
                }
                .disabled(duel.isBusy)
                AingButton(CrossyDuelPhoneText.accept, kind: .filled, size: .md, fillsWidth: true) {
                    Task { await duel.respond(inviteID: invite.id, accept: true) }
                }
                .disabled(!canAccept)
            }
        }
        .padding(MobileTheme.cardPadding)
    }
}

/// 보낸 신청 한 줄(취소).
struct GamesCrossyDuelOutgoingRow: View {
    let store: GamesStore
    let invite: CrossyDuelInvite

    var body: some View {
        let duel = store.crossyDuel
        GroupRow(divider: .none, minHeight: 56) {
            PersonAvatar(name: invite.peer.displayName, colorSeed: invite.peer.id,
                         url: invite.peer.avatarURL.flatMap(URL.init(string:)), userID: invite.peer.id, size: 36,
                         characterHint: invite.peer.characterID)
            VStack(alignment: .leading, spacing: 1) {
                Text(CrossyDuelPhoneText.outgoingTo(invite.peer.displayName))
                    .font(MobileTheme.rowTitle)
                    .foregroundStyle(MobileTheme.label)
                HStack(spacing: 0) {
                    GamesStakeLine(stake: invite.stake, prefix: CrossyDuelPhoneText.stakeTitle)
                    GamesCrossyDuelRemaining(store: duel, expiresAt: invite.expiresAt)
                }
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            AingButton(CrossyDuelPhoneText.cancel, kind: .gray, size: .sm) {
                Task { await duel.cancelChallenge() }
            }
            .disabled(duel.isBusy)
            .fixedSize()
        }
    }
}

/// " · 42초 남음"(1초마다).
struct GamesCrossyDuelRemaining: View {
    let store: CrossyDuelStore
    let expiresAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(" · " + CrossyDuelPhoneText.remaining(Int(expiresAt.timeIntervalSince(store.clock()).rounded(.up))))
                .monospacedDigit()
        }
    }
}

/// 판돈 고르기(3 · 5 · 10) → 신청. 잔액이 모자라는 칸은 흐리다(서버도 막는다).
struct GamesCrossyDuelStakeSheet: View {
    let store: GamesStore
    let target: CrossyDuelUser

    @Environment(\.dismiss) private var dismiss
    @State private var selected: CrossyDuelStake?

    var body: some View {
        let balance = store.rubyBalance
        VStack(spacing: 0) {
            SheetHeader(CrossyDuelPhoneText.stakeTitle, subtitle: CrossyDuelPhoneText.stakePromptTitle(name: target.displayName),
                        onClose: { dismiss() })
            VStack(alignment: .leading, spacing: MobileTheme.space4) {
                HStack(spacing: 10) {
                    ForEach(CrossyDuelStake.allCases, id: \.rawValue) { stake in
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
                if let balance, CrossyDuelStake.allCases.contains(where: { balance < $0.rawValue }) {
                    Text(CrossyDuelPhoneText.stakeShortfall)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                }
                Spacer(minLength: 0)
            }
            .padding(MobileTheme.sideMargin)
            AingButton(selected.map { CrossyDuelPhoneText.challengeWithStake($0.rawValue) } ?? CrossyDuelPhoneText.stakePromptCaption,
                       kind: .filled, size: .lg, fillsWidth: true) {
                guard let stake = selected else { return }
                dismiss()
                Task { await store.crossyDuel.challenge(userID: target.id, stake: stake) }
            }
            .disabled(selected == nil || store.crossyDuelEntryBlock != nil || store.crossyDuel.isBusy)
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.bottom, MobileTheme.space4)
        }
        .presentationDetents([.medium])
    }
}

/// 순위(승점 = 승 − 패) — 맥과 같은 서버(`crossy_duel_ranking`).
struct GamesCrossyDuelRankingSection: View {
    let store: GamesStore

    var body: some View {
        let duel = store.crossyDuel
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            SectionHeader(CrossyDuelPhoneText.rankTitle, trailing: .text(CrossyDuelPhoneText.rankHelp))
            InsetGroup {
                if let board = duel.ranking, !board.entries.isEmpty {
                    ForEach(Array(board.entries.prefix(20).enumerated()), id: \.element.id) { offset, entry in
                        GroupRow(divider: offset == min(board.entries.count, 20) - 1 ? .none : .inset(MobileTheme.cardPadding), minHeight: 48) {
                            Text("\(entry.rank)")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .frame(width: 28)
                            PersonAvatar(name: entry.user.displayName, colorSeed: entry.user.id,
                                         url: entry.user.avatarURL.flatMap(URL.init(string:)), userID: entry.user.id, size: 28,
                                         characterHint: entry.user.characterID)
                            PersonName(entry.user.displayName)
                            Spacer(minLength: 8)
                            Text(CrossyDuelPhoneText.points(entry.points))
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(MobileTheme.label2)
                        }
                    }
                } else {
                    Text(duel.ranking == nil ? CrossyDuelPhoneText.rankLoading : CrossyDuelPhoneText.rankEmpty)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(MobileTheme.cardPadding)
                }
            }
        }
        .task { await duel.refreshRanking() }
    }
}
#endif
