import SwiftUI
import CheckCore

// 아잉 뒤집기 — **로비**(상대 목록 · 순위 · 내 전적 · 지금 대결 중 · 받은/보낸 신청)와 가운데 작은 창 둘(판돈 고르기 · AI 색 고르기).
// 계약은 설계서 FLIP/SPEC.md §5.2(세 열 420 | 340 | 400) · §5.8. 틀은 체스 로비(`ChessPanel.swift` 의 같은 이름 부품)를 베꼈다.
// 신청에는 **근무 조건이 없다**(서버가 근무를 안 본다) — 근무 여부는 줄 글자로만 말하고 [도전] 을 잠그지 않는다.

// MARK: - 로비: 상대 목록

struct ReversiOpponentList: View {
    let store: ReversiStore
    let clipsOverflowInsteadOfScroll: Bool
    /// [도전]을 누른 상대를 창 루트로 올린다 — 판돈 창은 **창 가운데**에 서야 해서 행이 직접 못 띄운다.
    let onChallenge: (ReversiUser) -> Void

    /// 신청할 수 있는 사람 먼저, 그다음 대결 중, 그 밖(서버 순서는 그 안에서 유지). 차단한 사람은 빠져 있다(`visibleUsers`).
    private var sortedUsers: [ReversiUser] {
        store.visibleUsers.enumerated().sorted { lhs, rhs in
            let a = Self.rank(lhs.element), b = Self.rank(rhs.element)
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)
    }

    static func rank(_ user: ReversiUser) -> Int {
        if ReversiChallengeGate.isOpen(user) { return user.isWorking ? 0 : 1 }
        if user.inMatch { return 2 }
        return 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(ReversiText.lobbyTitle).font(.headline)
                Spacer()
                Text(ReversiText.lobbyCaption)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            if let blocked = availabilityText {
                Text(blocked)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.visibleUsers.isEmpty {
                Text(ReversiText.emptyUsers)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ReversiScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: ReversiWindowLayout.lobbyUserRowSpacing) {
                        ForEach(sortedUsers) { user in
                            ReversiOpponentRow(user: user, isBusy: store.isBusy,
                                               onChallenge: { onChallenge(user) })
                                .frame(height: ReversiWindowLayout.lobbyUserRowHeight)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chessCard()
    }

    /// 이 앱·서버 조합에서 아잉 뒤집기를 못 쓰는 까닭(쓸 수 있으면 nil).
    private var availabilityText: String? {
        switch store.availability {
        case .available: return nil
        case .updateRequired: return ReversiNoticeText.updateRequired
        case .serverMissing: return ReversiNoticeText.unavailable
        }
    }
}

/// [도전] 을 열지 가르는 규칙(순수). 서버 게이트와 **같은 뜻**의 앞단 잠금일 뿐이다 — 근무 여부는 보지 않는다.
enum ReversiChallengeGate {
    static func isOpen(_ user: ReversiUser) -> Bool {
        user.isCapable && !user.inMatch && !user.focusMode
    }
}

struct ReversiOpponentRow: View {
    let user: ReversiUser
    let isBusy: Bool
    let onChallenge: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CheckAvatarView(name: user.displayName, userID: user.id,
                            avatarURL: user.avatarURL.flatMap(URL.init(string:)), size: 34,
                            center: user.center, characterHint: user.characterID)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let chip = lockChip {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
                    Text(chip).font(.caption2.weight(.bold)).lineLimit(1)
                }
                .foregroundStyle(CheckTheme.secondaryText)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .checkTooltip(ReversiText.challengeLockedHelp)
            }
            ChessActionButton(title: ReversiText.challenge, height: 28, isEnabled: canChallenge, action: onChallenge)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }

    private var canChallenge: Bool { ReversiChallengeGate.isOpen(user) && !isBusy }

    /// 잠긴 까닭(칩). 열려 있으면 nil.
    private var lockChip: String? {
        if !user.isCapable { return ReversiText.needsUpdate }
        if user.inMatch { return ReversiText.inMatch }
        if user.focusMode { return ReversiText.focusMode }
        return nil
    }

    private var statusLine: String {
        if !user.isCapable { return ReversiText.needsUpdate }
        if user.inMatch { return ReversiText.inMatch }
        if user.focusMode { return ReversiText.focusMode }
        return user.isWorking ? ReversiText.working : "—"
    }
}

// MARK: - 로비: 순위 열

struct ReversiRankColumn: View {
    let store: ReversiStore
    let myUserID: String?
    let clipsOverflowInsteadOfScroll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ReversiWindowLayout.rankHeaderSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(ReversiText.rankTitle).font(.headline)
                Spacer(minLength: 4)
                if let since = store.ranking?.recordSince {
                    Text(ReversiText.rankSince(since))
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(height: ReversiWindowLayout.rankHeaderHeight)
            if !store.rankingUnavailable, let board = store.ranking, !board.entries.isEmpty {
                ReversiScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: ReversiWindowLayout.rankRowSpacing) {
                        ForEach(board.entries) { entry in
                            ReversiRankRow(entry: entry, isMe: isMe(entry))
                                .frame(height: ReversiWindowLayout.rankRowHeight)
                        }
                    }
                }
                .frame(height: ReversiWindowLayout.rankListHeight, alignment: .top)
            } else {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chessCard()
    }

    private func isMe(_ entry: ReversiRankEntry) -> Bool {
        guard let myUserID else { return false }
        return entry.user.id.lowercased() == myUserID.lowercased()
    }

    /// `rankingUnavailable`(서버에 순위가 아직 없다) 이면 "곧" — 관전 잠금 깃발과 **다른 깃발**이다.
    private var emptyText: String {
        if store.rankingUnavailable { return ReversiText.rankSoon }
        if store.ranking == nil { return ReversiText.rankLoading }
        return ReversiText.rankEmpty
    }
}

struct ReversiRankRow: View {
    let entry: ReversiRankEntry
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
                            center: entry.user.center, characterHint: entry.user.characterID)
            Text(entry.user.displayName)
                .font(.caption.weight(isMe ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(ReversiText.points(entry.points))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                Text(ReversiText.record(wins: entry.wins, losses: entry.losses, draws: entry.draws))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .monospacedDigit()
            }
            .frame(width: ReversiWindowLayout.rankTrailingWidth, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isMe ? CheckTheme.accent.opacity(0.14) : Color.white.opacity(0.03))
        )
    }
}

// MARK: - 로비: 오른쪽 열

struct ReversiLobbySide: View {
    let store: ReversiStore
    let me: ReversiPlayerFace
    let clipsOverflowInsteadOfScroll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ReversiWindowLayout.lobbySideSpacing) {
            ReversiRecordCard(store: store, me: me)
                .frame(height: ReversiWindowLayout.lobbyRecordHeight)
            liveBox
                .frame(height: ReversiWindowLayout.lobbyLiveHeight)
            // ★ 예산을 **넘기면 잘린다**(부모 열이 `.clipped()` 다) — 예산은 조각의 합이다.
            ReversiLobbyInvitesBox(store: store)
                .frame(maxHeight: ReversiWindowLayout.lobbyInvitesMaxHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var liveBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ReversiText.liveTitle).font(.headline)
            if store.liveMatches.isEmpty {
                Text(ReversiText.noLive)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ReversiScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: 6) {
                        ForEach(store.liveMatches) { live in
                            ReversiLiveRow(
                                live: live,
                                // ★ 스토어 판정(내 user id 가 줄에 있다)을 쓴다 — 로비가 그려질 때 `store.match` 는 늘 nil 이라
                                //   판 id 비교로는 내 판에도 [관전] 이 선다.
                                isMine: store.isMine(live),
                                // ★ 관전 입구의 잠금은 `watchUnavailable` **하나**로만 판정한다(깃발 겸업 금지).
                                canWatch: !store.watchUnavailable,
                                onWatch: { store.startWatching(matchID: live.id) }
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chessCard()
    }
}

/// 로비 오른쪽 열 맨 아래 — 받은 신청 1장 + 보낸 신청 줄 + 안내 줄.
/// 받은 신청은 **`visibleIncoming`** 하나다(차단 거울을 거르고 지금 내 판과 같은 id 를 뺀 첫 신청 — 시계를 읽지 않는다).
struct ReversiLobbyInvitesBox: View {
    let store: ReversiStore

    var body: some View {
        VStack(alignment: .leading, spacing: ReversiWindowLayout.lobbyInvitesSpacing) {
            Text(ReversiText.incomingTitle).font(.headline)
                .frame(height: ReversiWindowLayout.lobbyInvitesTitleHeight)
            if let invite = store.visibleIncoming {
                ReversiInviteCard(store: store, invite: invite)
            } else {
                Text(ReversiText.noIncoming)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            if let outgoing = store.outgoing {
                ReversiOutgoingLine(store: store, outgoing: outgoing)
            }
            if let notice = store.notice {
                ReversiNoticeLine(text: notice)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .chessCard()
    }
}

/// 내 전적 카드(로비 오른쪽 맨 위). 순위 응답과 **같은 출처**를 쓴다(머리글 캡슐과 같은 규칙).
struct ReversiRecordCard: View {
    let store: ReversiStore
    let me: ReversiPlayerFace

    var body: some View {
        HStack(spacing: 10) {
            CharacterPortrait(characterID: me.characterID)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(ReversiText.recordTitle)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                Text(ReversiText.record(store.record))
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            if let mine = ReversiRecordSource.consistentRank(store) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ReversiText.points(mine.points))
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
        .chessCard(padding: 12)
    }
}

struct ReversiLiveRow: View {
    let live: ReversiLiveMatch
    let isMine: Bool
    let canWatch: Bool
    let onWatch: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            CheckAvatarView(name: live.a.displayName, userID: live.a.id,
                            avatarURL: live.a.avatarURL.flatMap(URL.init(string:)), size: 18,
                            characterHint: live.a.characterID)
            Text(live.a.displayName).font(.caption2).lineLimit(1)
            Text("vs").font(.caption2).foregroundStyle(CheckTheme.secondaryText)
            CheckAvatarView(name: live.b.displayName, userID: live.b.id,
                            avatarURL: live.b.avatarURL.flatMap(URL.init(string:)), size: 18,
                            characterHint: live.b.characterID)
            Text(live.b.displayName).font(.caption2).lineLimit(1)
            Spacer(minLength: 4)
            // 관전자 수 — 칩 높이는 [관전] 칩과 **같은 18**(더 크면 카드가 자란다). 0 이면 안 그린다.
            WatcherCountChip(count: live.watchers, height: ReversiWindowLayout.liveWatchChipHeight)
            if isMine {
                Text(ReversiText.myMatch)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(height: ReversiWindowLayout.liveWatchChipHeight)
            } else {
                Button(action: onWatch) {
                    Text(ReversiText.watch)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CheckTheme.accent)
                        .padding(.horizontal, 8)
                        .frame(height: ReversiWindowLayout.liveWatchChipHeight)
                        .background(Capsule().fill(CheckTheme.accent.opacity(0.16)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canWatch)
                .opacity(canWatch ? 1 : 0.4)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
    }
}

struct ReversiInviteCard: View {
    let store: ReversiStore
    let invite: ReversiInvite

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CheckAvatarView(name: invite.peer.displayName, userID: invite.peer.id,
                                avatarURL: invite.peer.avatarURL.flatMap(URL.init(string:)), size: 28,
                                center: invite.peer.center, characterHint: invite.peer.characterID)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ReversiText.incomingLine(name: invite.peer.displayName))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(ReversiText.stakeLine(invite.stake))
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .monospacedDigit()
                }
                Spacer(minLength: 4)
                ChessCountdownText(expiresAt: invite.expiresAt, isLive: store.isWindowVisible)
            }
            HStack(spacing: 8) {
                ChessActionButton(title: ReversiText.accept, height: 30, fullWidth: true, isEnabled: !store.isBusy) {
                    Task { await store.respond(inviteID: invite.id, accept: true) }
                }
                ChessActionButton(title: ReversiText.decline, tint: CheckTheme.offWork, style: .outline,
                                  height: 30, fullWidth: true, isEnabled: !store.isBusy) {
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

struct ReversiOutgoingLine: View {
    let store: ReversiStore
    let outgoing: ReversiOutgoing

    var body: some View {
        HStack(spacing: 8) {
            Text("\(ReversiText.outgoingTitle) · \(outgoing.peer.displayName)")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            ChessCountdownText(expiresAt: outgoing.expiresAt, isLive: store.isWindowVisible)
            Spacer(minLength: 4)
            ChessActionButton(title: ReversiText.cancel, tint: CheckTheme.offWork, style: .outline,
                              height: 26, isEnabled: !store.isBusy) {
                Task { await store.cancelChallenge() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }
}

// MARK: - 판돈 고르기 창

/// 판돈 고르기 창. **고르기와 신청이 갈려 있다** — 판돈 버튼은 고르기만 하고 신청은 [도전하기] 한 곳에서만 나간다.
/// 루비가 모자란 판돈은 흐리게 막는다(서버도 `insufficient` 로 막는다 — 앞단은 친절일 뿐이다).
struct ReversiStakePrompt: View {
    let store: ReversiStore
    let target: ReversiUser
    let initialSelection: ReversiStake?
    let onClose: () -> Void

    @State private var selection: ReversiStake?

    private var chosen: ReversiStake? { selection ?? initialSelection }

    var body: some View {
        ReversiOverlayScrim {
            VStack(spacing: 12) {
                Text(ReversiText.stakePromptTitle(name: target.displayName)).font(.headline)
                Text(chosen.map { ReversiText.stakePromptChosen($0.rawValue) } ?? ReversiText.stakePromptCaption)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(height: 20)
                HStack(spacing: 10) {
                    ForEach(ReversiStake.allCases, id: \.rawValue) { stake in
                        ReversiStakeButton(stake: stake, isSelected: chosen == stake, isEnabled: affordable(stake)) {
                            selection = (chosen == stake) ? nil : stake
                        }
                    }
                }
                if let chosen, !affordable(chosen) {
                    Text(ReversiText.stakeShortfall)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.danger)
                }
                if let chosen, affordable(chosen) {
                    ChessActionButton(title: ReversiText.challengeWithStake(chosen.rawValue), icon: "paperplane.fill",
                                      height: 34, fullWidth: true, isEnabled: !store.isBusy) {
                        store.selectedStake = chosen
                        onClose()
                        Task { await store.challenge(userID: target.id) }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    ChessActionButton(title: ReversiText.cancel, tint: CheckTheme.offWork, style: .outline,
                                      height: 34, fullWidth: true, action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            .frame(width: ReversiWindowLayout.stakePromptWidth)
            .chessCard(padding: 0)
            .overlay(
                Button(action: onClose) { Color.clear.frame(width: 0, height: 0) }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
            )
        }
    }

    private func affordable(_ stake: ReversiStake) -> Bool {
        guard let balance = store.rubyBalance else { return true }
        return balance >= stake.rawValue
    }
}

struct ReversiStakeButton: View {
    let stake: ReversiStake
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                RubyIcon(size: 18)
                Text("\(stake.rawValue)")
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Color.white : CheckTheme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? CheckTheme.accent : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.clear : CheckTheme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

// MARK: - AI 색 고르기 창

/// AI 와 둘 색 고르기 — 흑(먼저) · 백(나중) · 무작위(nil). 고르면 곧바로 판이 열린다(루비·전적 없음).
struct ReversiAIPrompt: View {
    let store: ReversiStore
    let onClose: () -> Void

    var body: some View {
        ReversiOverlayScrim {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CheckTheme.accent)
                    Text(ReversiText.aiPromptTitle).font(.headline)
                }
                Text(ReversiText.aiPromptCaption)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                HStack(spacing: 8) {
                    colorButton(.black, title: ReversiText.aiPlayBlack)
                    colorButton(.white, title: ReversiText.aiPlayWhite)
                    colorButton(nil, title: ReversiText.aiPlayRandom)
                }
                Text(ReversiText.aiInfo)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                ChessActionButton(title: ReversiText.cancel, tint: CheckTheme.offWork, style: .outline,
                                  height: 32, fullWidth: true, action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .frame(width: ReversiWindowLayout.aiPromptWidth)
            .chessCard(padding: 0)
        }
    }

    private func colorButton(_ color: ReversiColor?, title: String) -> some View {
        Button {
            onClose()
            store.startAIMatch(humanColor: color)
        } label: {
            VStack(spacing: 6) {
                if let color {
                    ReversiStoneDot(color: color, size: 24)
                } else {
                    HStack(spacing: -6) {
                        ReversiStoneDot(color: .black, size: 20)
                        ReversiStoneDot(color: .white, size: 20)
                    }
                    .frame(height: 24)
                }
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(CheckTheme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!store.canStartAIMatch)
        .opacity(store.canStartAIMatch ? 1 : 0.45)
    }
}
