import AppKit
import SwiftUI
import CheckCore

// MARK: - 1:1 길건너 로비 (SPEC v1.3 §9.1 — 두 열 [사람·순위 탭 360 | 오른쪽 240])
//
// 왼쪽: 탭(상대 고르기 · 순위). 오른쪽: 내 전적 · 받은/보낸 신청 · 규칙 요약. 관전이 없으므로(Q1) "지금 대결 중" 칸이 없다.
// 스토어의 공개 표면(`visibleUsers` · `visibleIncoming` · `outgoing` · `record` · `ranking` · `challenge` · `respond` ·
// `cancelChallenge` · `refreshLobby`)만 읽고 부른다.

struct CrossyDuelLobbyView: View {
    let store: CrossyDuelStore
    let me: ChessPlayerFace
    let myUserID: String?
    let tab: CrossyDuelLobbyTab
    let clipsOverflowInsteadOfScroll: Bool
    let onSelectTab: (CrossyDuelLobbyTab) -> Void
    let onChallenge: (CrossyDuelUser) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: CrossyDuelWindowLayout.columnSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                CrossyDuelLobbyTabs(selected: tab, onSelect: onSelectTab)
                    .frame(height: CrossyDuelWindowLayout.lobbyTabHeight)
                switch tab {
                case .users:
                    CrossyDuelOpponentList(store: store, clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll,
                                           onChallenge: onChallenge)
                case .ranking:
                    CrossyDuelRankList(store: store, myUserID: myUserID,
                                       clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                }
            }
            .frame(width: CrossyDuelWindowLayout.lobbyListWidth, height: CrossyDuelWindowLayout.bodyHeight,
                   alignment: .top)
            .clipped()
            CrossyDuelLobbySide(store: store, me: me)
                .frame(width: CrossyDuelWindowLayout.lobbySideWidth, height: CrossyDuelWindowLayout.bodyHeight,
                       alignment: .top)
                .clipped()
        }
    }
}

// MARK: - 탭

private struct CrossyDuelLobbyTabs: View {
    let selected: CrossyDuelLobbyTab
    let onSelect: (CrossyDuelLobbyTab) -> Void

    var body: some View {
        HStack(spacing: 6) {
            tab(.users, title: CrossyDuelText.usersTab, icon: "person.2.fill")
            tab(.ranking, title: CrossyDuelText.rankTab, icon: "trophy.fill")
            Spacer(minLength: 4)
        }
    }

    private func tab(_ value: CrossyDuelLobbyTab, title: String, icon: String) -> some View {
        let isOn = selected == value
        return Button { onSelect(value) } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(isOn ? CheckTheme.accent : CheckTheme.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: CrossyDuelWindowLayout.lobbyTabHeight)
                .background(Capsule().fill(isOn ? CheckTheme.accent.opacity(0.20) : Color.white.opacity(0.04)))
                .overlay(Capsule().stroke(isOn ? CheckTheme.accent.opacity(0.55) : CheckTheme.border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - 상대 목록

private struct CrossyDuelOpponentList: View {
    let store: CrossyDuelStore
    let clipsOverflowInsteadOfScroll: Bool
    let onChallenge: (CrossyDuelUser) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(CrossyDuelText.lobbyCaption)
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            if store.visibleUsers.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if store.lobbyLoadFailed {
                    TetrisDuelActionButton(title: CrossyDuelText.reloadUsers, icon: "arrow.clockwise",
                                           style: .outline, height: 30, fullWidth: true) {
                        Task { await store.refreshLobby() }
                    }
                }
            } else {
                CrossyDuelScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: CrossyDuelWindowLayout.lobbyRowSpacing) {
                        // 서버 정렬 그대로(여기서 다시 줄 세우지 않는다).
                        ForEach(store.visibleUsers) { user in
                            CrossyDuelOpponentRow(user: user, isEnabled: canChallenge(user),
                                                  onChallenge: { onChallenge(user) })
                                .frame(height: CrossyDuelWindowLayout.lobbyRowHeight)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .crossyDuelCard()
    }

    /// [신청] — 서버가 어차피 거절할 상대(구버전 · 대결 중 · 집중)만 끈다. **근무 여부는 보지 않는다**(선게이트 금지).
    private func canChallenge(_ user: CrossyDuelUser) -> Bool {
        user.canBeChallenged && !store.isBusy && store.availability == .available && store.outgoing == nil
    }

    private var emptyText: String {
        switch store.availability {
        case .updateRequired: return CrossyDuelNoticeText.updateMine
        case .serverMissing: return CrossyDuelNoticeText.unavailable
        case .available: break
        }
        if store.lobbyLoadFailed { return CrossyDuelText.usersLoadFailed }
        return store.hasLoadedLobby ? CrossyDuelText.emptyUsers : CrossyDuelText.loadingUsers
    }
}

private struct CrossyDuelOpponentRow: View {
    let user: CrossyDuelUser
    let isEnabled: Bool
    let onChallenge: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CheckAvatarView(name: user.displayName, userID: user.id,
                            avatarURL: user.avatarURL.flatMap(URL.init(string:)), size: 32,
                            characterHint: user.characterID)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(user.isCapable ? CheckTheme.secondaryText : CheckTheme.pending)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            TetrisDuelActionButton(title: CrossyDuelText.challenge, height: 28, isEnabled: isEnabled,
                                   action: onChallenge)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }

    /// 상태 글자: 구버전 > 대결 중 > 집중 > 근무 중 > "—".
    private var statusLine: String {
        if !user.isCapable { return CrossyDuelText.needsUpdate }
        if user.inMatch { return CrossyDuelText.inMatch }
        if user.isFocused { return CrossyDuelText.focused }
        return user.isWorking ? CrossyDuelText.working : "—"
    }
}

// MARK: - 순위

private struct CrossyDuelRankList: View {
    let store: CrossyDuelStore
    let myUserID: String?
    let clipsOverflowInsteadOfScroll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(CrossyDuelText.rankHelp)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                Spacer(minLength: 4)
                if let since = store.ranking?.recordSince {
                    Text(CrossyDuelText.rankSince(since))
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            if let board = store.ranking, !board.entries.isEmpty {
                CrossyDuelScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: 5) {
                        ForEach(board.entries) { entry in
                            CrossyDuelRankRow(entry: entry, isMe: entry.user.id == myUserID)
                                .frame(height: 34)
                        }
                    }
                }
            } else {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .crossyDuelCard()
    }

    private var emptyText: String {
        if store.rankingUnavailable { return CrossyDuelText.rankSoon }
        guard store.ranking != nil else { return CrossyDuelText.rankLoading }
        return CrossyDuelText.rankEmpty
    }
}

private struct CrossyDuelRankRow: View {
    let entry: CrossyDuelRankEntry
    let isMe: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(entry.rank)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
                .foregroundStyle(entry.rank <= 3 ? CheckTheme.pending : CheckTheme.secondaryText)
            CheckAvatarView(name: entry.user.displayName, userID: entry.user.id,
                            avatarURL: entry.user.avatarURL.flatMap(URL.init(string:)), size: 22,
                            characterHint: entry.user.characterID)
            Text(entry.user.displayName)
                .font(.caption.weight(isMe ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(CrossyDuelText.points(entry.points))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                Text(CrossyDuelText.record(wins: entry.wins, losses: entry.losses, draws: entry.draws))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .monospacedDigit()
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isMe ? CheckTheme.accent.opacity(0.14) : Color.white.opacity(0.03))
        )
    }
}

// MARK: - 오른쪽 열

private struct CrossyDuelLobbySide: View {
    let store: CrossyDuelStore
    let me: ChessPlayerFace

    var body: some View {
        VStack(alignment: .leading, spacing: CrossyDuelWindowLayout.lobbySideSpacing) {
            recordCard
                .frame(height: CrossyDuelWindowLayout.lobbyRecordHeight)
            // 신청 칸은 **자연 높이**(받은 카드 · 보낸 줄 · 안내), 규칙 요약이 남는 높이를 먹는다.
            CrossyDuelInvitesBox(store: store)
                .fixedSize(horizontal: false, vertical: true)
            howCard
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var recordCard: some View {
        HStack(spacing: 10) {
            CharacterPortrait(characterID: me.characterID)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(CrossyDuelText.recordTitle)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                Text(CrossyDuelText.record(store.record))
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            if let mine = store.ranking?.me, let record = store.record,
               mine.wins == record.wins, mine.losses == record.losses, mine.draws == record.draws {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CrossyDuelText.points(mine.points))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                    if let rank = mine.rank {
                        Text("\(rank)위")
                            .font(.caption2)
                            .foregroundStyle(CheckTheme.secondaryText)
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .crossyDuelCard(padding: 12)
    }

    private var howCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CrossyDuelText.howTitle).font(.headline)
            ForEach(CrossyDuelText.howLines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(CheckTheme.accent.opacity(0.7)).frame(width: 4, height: 4)
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .crossyDuelCard(padding: 12)
    }
}

/// 받은·보낸 신청 칸(팝오버 배너와 같은 사실 — 창 안 자리).
struct CrossyDuelInvitesBox: View {
    let store: CrossyDuelStore

    var body: some View {
        VStack(alignment: .leading, spacing: CrossyDuelWindowLayout.invitesSpacing) {
            HStack(spacing: 6) {
                Text(CrossyDuelText.incomingTitle).font(.headline)
                let more = store.visibleIncomingInvites.count - 1
                if more > 0 {
                    Text(CrossyDuelText.incomingMore(more))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(CheckTheme.secondaryText)
                }
            }
            .frame(height: CrossyDuelWindowLayout.invitesTitleHeight)
            if let invite = store.visibleIncoming {
                CrossyDuelInviteCard(store: store, invite: invite)
            } else {
                Text(CrossyDuelText.noIncoming)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            if let outgoing = store.outgoing {
                CrossyDuelOutgoingLine(store: store, invite: outgoing)
            }
            if let notice = store.notice {
                CrossyDuelNoticeLine(text: notice)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .crossyDuelCard()
    }
}

private struct CrossyDuelInviteCard: View {
    let store: CrossyDuelStore
    let invite: CrossyDuelInvite

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CheckAvatarView(name: invite.peer.displayName, userID: invite.peer.id,
                                avatarURL: invite.peer.avatarURL.flatMap(URL.init(string:)), size: 28,
                                characterHint: invite.peer.characterID)
                VStack(alignment: .leading, spacing: 2) {
                    Text(CrossyDuelText.incomingFrom(invite.peer.displayName))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(CrossyDuelText.stakeLine(invite.stake))
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .monospacedDigit()
                }
                Spacer(minLength: 2)
                TetrisDuelCountdownText(expiresAt: invite.expiresAt, isLive: store.isWindowVisible, now: store.clock)
            }
            HStack(spacing: 8) {
                TetrisDuelActionButton(title: CrossyDuelText.accept, height: 28, fullWidth: true,
                                       isEnabled: !store.isBusy) {
                    Task { await store.respond(inviteID: invite.id, accept: true) }
                }
                TetrisDuelActionButton(title: CrossyDuelText.decline, tint: CheckTheme.offWork, style: .outline,
                                       height: 28, fullWidth: true, isEnabled: !store.isBusy) {
                    Task { await store.respond(inviteID: invite.id, accept: false) }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CheckTheme.accent.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(CheckTheme.accent.opacity(0.4), lineWidth: 1))
    }
}

private struct CrossyDuelOutgoingLine: View {
    let store: CrossyDuelStore
    let invite: CrossyDuelInvite

    var body: some View {
        HStack(spacing: 6) {
            Text("\(CrossyDuelText.outgoingTitle) · \(invite.peer.displayName) · \(invite.stake)")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 2)
            TetrisDuelCountdownText(expiresAt: invite.expiresAt, isLive: store.isWindowVisible, now: store.clock)
            TetrisDuelActionButton(title: CrossyDuelText.cancel, tint: CheckTheme.offWork, style: .outline,
                                   height: 26, isEnabled: !store.isBusy) {
                Task { await store.cancelChallenge() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: CrossyDuelWindowLayout.outgoingLineHeight, alignment: .leading)
    }
}

// MARK: - 판돈 고르기 (가운데 작은 창)

/// 판돈 고르기. **고르기와 신청이 갈려 있다** — 처음엔 아무것도 안 골라져 있고, 골라야 [신청하기] 가 선다(테트리스와 같다).
struct CrossyDuelStakePrompt: View {
    let store: CrossyDuelStore
    let target: CrossyDuelUser
    let initialSelection: CrossyDuelStake?
    let onClose: () -> Void

    @State private var selection: CrossyDuelStake?

    private var chosen: CrossyDuelStake? { selection ?? initialSelection }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            VStack(spacing: 12) {
                Text(CrossyDuelText.stakePromptTitle(name: target.displayName)).font(.headline)
                Text(chosen.map { CrossyDuelText.stakePromptChosen($0.rawValue) } ?? CrossyDuelText.stakePromptCaption)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(height: 20)
                HStack(spacing: 10) {
                    ForEach(CrossyDuelStake.allCases, id: \.rawValue) { stake in
                        stakeButton(stake)
                    }
                }
                if let chosen, !affordable(chosen) {
                    Text(CrossyDuelText.stakeShortfall)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.danger)
                }
                if let chosen, affordable(chosen) {
                    TetrisDuelActionButton(title: CrossyDuelText.challengeWithStake(chosen.rawValue),
                                           icon: "paperplane.fill", height: 34, fullWidth: true,
                                           isEnabled: !store.isBusy) {
                        onClose()
                        Task { await store.challenge(userID: target.id, stake: chosen) }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    TetrisDuelActionButton(title: CrossyDuelText.cancel, tint: CheckTheme.offWork, style: .outline,
                                           height: 34, fullWidth: true, action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            .frame(width: CrossyDuelWindowLayout.stakePromptWidth)
            .crossyDuelCard(padding: 0)
            // Esc 는 고른 뒤에도 언제나 닫는다(위 [취소] 가 사라지는 갈래가 있으므로 한 번 더 건다).
            .overlay(
                Button(action: onClose) { Color.clear.frame(width: 0, height: 0) }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
            )
        }
        .frame(width: CrossyDuelWindowLayout.contentSize.width, height: CrossyDuelWindowLayout.contentSize.height)
    }

    /// 잔액을 모르면 막지 않는다(서버가 판정한다).
    private func affordable(_ stake: CrossyDuelStake) -> Bool {
        guard let balance = store.rubyBalance else { return true }
        return balance >= stake.rawValue
    }

    private func stakeButton(_ stake: CrossyDuelStake) -> some View {
        let isSelected = chosen == stake
        let isEnabled = affordable(stake)
        return Button {
            selection = (chosen == stake) ? nil : stake
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    RubyIcon(size: 14)
                    Text("\(stake.rawValue)").font(.title3.weight(.bold)).monospacedDigit()
                }
                Text("이기면 +\(DuelFee.winnerNet(stake: stake.rawValue))")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? CheckTheme.accent.opacity(0.22) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? CheckTheme.accent : CheckTheme.border, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
