import SwiftUI
import CheckCore

// 1:1 알까기 — **로비**(상대 고르기 · 순위 · 내 전적 · 지금 대결 중 · 받은/보낸 신청)와 가운데 작은 창 둘(판돈 고르기 · 규칙).
// 계약은 SPEC v1.1 §5.3 · §5.4. 틀과 치수는 뒤집기 로비(`ReversiPanelLobby.swift` 의 같은 자리 부품)를 옮기고 이름만 바꿨다
// (세 열 420 | 340 | 400 — `ReversiWindowLayout` 로비 상수 그대로, 창은 같은 1240×700).
// 신청에는 **근무 조건이 없다**(서버가 근무를 안 본다) — 근무 여부는 줄 글자로만 말하고 [도전] 을 잠그지 않는다.
// Picker/Menu/TextField 를 쓰지 않는다(ImageRenderer 가 못 그린다) — 고르기는 Button + Shape. 정보는 글자로 말한다.
// 줄 순서는 스토어 한 곳(`visibleUsers` = 차단 거울 뺀 뒤 `sortedForLobby`)이 정한다 — 화면은 다시 줄 세우지 않는다.

// MARK: - 로비: 상대 목록

struct AlkkagiOpponentList: View {
    let store: AlkkagiOnlineStore
    let clipsOverflowInsteadOfScroll: Bool
    /// [도전]을 누른 상대를 창 루트로 올린다 — 판돈 창은 **창 가운데**에 서야 해서 행이 직접 못 띄운다.
    let onChallenge: (AlkkagiLobbyUser) -> Void

    /// 빈 상태 다섯 갈래(DF#12) — 사람 줄 대신 서는 한 줄. nil 이면 줄을 그린다.
    /// `.serverMissing`(문 닫힘 포함)이면 사람 줄 대신 '곧 열려요'다 — 문이 닫힌 동안 모든 줄이 `capable` 거짓이라 줄마다
    /// '앱 업데이트 필요'로 잘못 보이는 것을 막는다(VC-8).
    enum EmptyState: Equatable {
        case soon, update, failed, loading, none

        var text: String {
            switch self {
            case .soon: return AlkkagiNoticeText.unavailable
            case .update: return AlkkagiNoticeText.updateMine
            case .failed: return AlkkagiText.usersLoadFailed
            case .loading: return AlkkagiText.loadingUsers
            case .none: return AlkkagiText.emptyUsers
            }
        }
    }

    @MainActor
    static func emptyState(_ store: AlkkagiOnlineStore) -> EmptyState? {
        switch store.availability {
        case .serverMissing: return .soon
        case .updateRequired: return .update
        case .available: break
        }
        guard store.visibleUsers.isEmpty else { return nil }
        if store.lobbyLoadFailed { return .failed }
        if !store.hasLoadedLobby { return .loading }
        return EmptyState.none
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(AlkkagiText.lobbyTitle).font(.headline)
                Spacer()
                Text(AlkkagiText.lobbyCaption)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            if let empty = Self.emptyState(store) {
                VStack(spacing: 12) {
                    Text(empty.text)
                        .font(.callout)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .multilineTextAlignment(.center)
                    if empty == .failed {
                        ChessActionButton(title: AlkkagiText.reloadUsers, icon: "arrow.clockwise", style: .outline,
                                          height: 30, isEnabled: !store.isBusy) {
                            Task { await store.refreshLobby() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ReversiScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: ReversiWindowLayout.lobbyUserRowSpacing) {
                        ForEach(store.visibleUsers) { user in
                            AlkkagiOpponentRow(user: user, canChallenge: Self.canChallenge(user, store: store),
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

    /// [도전] 을 여는 규칙(순수 — §5.3): 상대가 받을 수 있고(`canBeChallenged`) · 내가 바쁘지 않고 · 이 기기가 대결할 수 있다.
    /// 서버 게이트와 같은 뜻의 앞단 잠금일 뿐이다 — 근무 여부는 보지 않는다.
    @MainActor
    static func canChallenge(_ user: AlkkagiLobbyUser, store: AlkkagiOnlineStore) -> Bool {
        user.canBeChallenged && !store.isBusy && store.availability == .available
    }
}

struct AlkkagiOpponentRow: View {
    let user: AlkkagiLobbyUser
    let canChallenge: Bool
    let onChallenge: () -> Void

    /// 상태 한 줄(순수 — §5.3): 앱 업데이트 필요(주황) > 대결 중 > 집중 모드 > 근무 중 > "—".
    static func statusLine(_ user: AlkkagiLobbyUser) -> String {
        if !user.isCapable { return AlkkagiText.needsUpdate }
        if user.inMatch { return AlkkagiText.inMatch }
        if user.isFocused { return AlkkagiText.focusMode }
        return user.isWorking ? AlkkagiText.working : AlkkagiText.idle
    }

    var body: some View {
        HStack(spacing: 12) {
            CheckAvatarView(name: user.displayName, userID: user.id,
                            avatarURL: user.avatarURL.flatMap(URL.init(string:)), size: 34,
                            characterHint: user.characterID)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(Self.statusLine(user))
                    .font(.caption2)
                    .foregroundStyle(user.isCapable ? CheckTheme.secondaryText : CheckTheme.pending)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ChessActionButton(title: AlkkagiText.challenge, height: 28, isEnabled: canChallenge, action: onChallenge)
                .accessibilityLabel("\(user.displayName)님에게 \(AlkkagiText.gameName) \(AlkkagiText.challenge)")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}

// MARK: - 로비: 순위 열

struct AlkkagiRankColumn: View {
    let store: AlkkagiOnlineStore
    let clipsOverflowInsteadOfScroll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ReversiWindowLayout.rankHeaderSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(AlkkagiText.rankTitle).font(.headline)
                Spacer(minLength: 4)
                Text(AlkkagiText.rankHelp)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(height: ReversiWindowLayout.rankHeaderHeight)
            if Self.emptyText(store) == nil, let board = store.ranking {
                ReversiScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: ReversiWindowLayout.rankRowSpacing) {
                        ForEach(board.entries) { entry in
                            AlkkagiRankRow(entry: entry, isMe: isMe(entry))
                                .frame(height: ReversiWindowLayout.rankRowHeight)
                        }
                    }
                }
                .frame(height: ReversiWindowLayout.rankListHeight, alignment: .top)
            } else {
                Text(Self.emptyText(store) ?? AlkkagiText.rankEmpty)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chessCard()
    }

    private func isMe(_ entry: AlkkagiRankEntry) -> Bool {
        guard let myID = store.me?.id else { return false }
        return entry.id.lowercased() == myID.lowercased()
    }

    /// 순위 대신 서는 한 줄(줄을 그릴 수 있으면 nil): 곧 열려요(서버 옛판 · 순위 함수 없음) > 불러오는 중 > 없음.
    @MainActor
    static func emptyText(_ store: AlkkagiOnlineStore) -> String? {
        if store.rankingUnavailable || store.availability == .serverMissing { return AlkkagiText.rankSoon }
        guard let board = store.ranking else { return AlkkagiText.rankLoading }
        return board.entries.isEmpty ? AlkkagiText.rankEmpty : nil
    }
}

struct AlkkagiRankRow: View {
    let entry: AlkkagiRankEntry
    let isMe: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(entry.rank)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
                .foregroundStyle(entry.rank <= 3 ? CheckTheme.pending : CheckTheme.secondaryText)
            CheckAvatarView(name: entry.displayName, userID: entry.id,
                            avatarURL: entry.avatarURL.flatMap(URL.init(string:)), size: 22,
                            characterHint: entry.characterID)
            Text(entry.displayName)
                .font(.caption.weight(isMe ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(AlkkagiText.points(entry.points))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                Text(AlkkagiText.record(wins: entry.wins, losses: entry.losses, draws: entry.draws))
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

// MARK: - 전적 글자 한 출처

/// 전적 글자 — **한 출처**. 순위 응답의 `me` 가 로비 전적과 같을 때만 순위·승점을 함께 쓴다
/// (두 출처를 섞으면 "8승 3패 · 승점 +4" 같은 자기모순 문장이 뜬다 — 뒤집기 `ReversiRecordSource` · §4.5).
enum AlkkagiRecordSource {
    @MainActor
    static func consistentRank(_ store: AlkkagiOnlineStore) -> AlkkagiMyRank? {
        guard let mine = store.ranking?.me else { return nil }
        guard let record = store.record else { return mine }
        return mine.matches(record) ? mine : nil
    }

    /// 머리 캡슐 "N승 N패 N무 · N위 · 승점 +N".
    @MainActor
    static func headerLine(_ store: AlkkagiOnlineStore) -> String {
        guard let mine = consistentRank(store) else { return AlkkagiText.record(store.record) }
        let record = AlkkagiText.record(wins: mine.wins, losses: mine.losses, draws: mine.draws)
        guard let rank = mine.rank else { return "\(record) · \(AlkkagiText.points(mine.points))" }
        return "\(record) · \(AlkkagiText.myRank(rank: rank, points: mine.points))"
    }
}

// MARK: - 로비: 오른쪽 열

struct AlkkagiLobbySide: View {
    let store: AlkkagiOnlineStore
    let clipsOverflowInsteadOfScroll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ReversiWindowLayout.lobbySideSpacing) {
            AlkkagiRecordCard(store: store)
                .frame(height: ReversiWindowLayout.lobbyRecordHeight)
            liveBox
                .frame(height: ReversiWindowLayout.lobbyLiveHeight)
            // ★ 예산을 **넘기면 잘린다**(부모 열이 `.clipped()` 다) — 예산은 조각의 합이다(뒤집기 상수).
            AlkkagiInvitesBox(store: store)
                .frame(maxHeight: ReversiWindowLayout.lobbyInvitesMaxHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var liveBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AlkkagiText.liveTitle).font(.headline)
            if store.liveMatches.isEmpty {
                Text(AlkkagiText.noLive)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ReversiScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: 6) {
                        ForEach(store.liveMatches) { live in
                            // 내가 낀 판은 서버가 뺀다(§3.7) — 줄마다 [관전] 이 선다. 관전 스위치가 꺼지면 [관전] 을 숨긴다.
                            AlkkagiLiveRow(live: live, canWatch: store.spectatorFeaturesEnabled,
                                           onWatch: { store.watch(matchID: live.id) })
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chessCard()
    }
}

/// 내 전적 카드(로비 오른쪽 맨 위). 순위 응답과 **같은 출처**를 쓴다(머리글 캡슐과 같은 규칙).
struct AlkkagiRecordCard: View {
    let store: AlkkagiOnlineStore

    var body: some View {
        HStack(spacing: 10) {
            CharacterPortrait(characterID: store.me?.characterID ?? ReversiPlayerFace.fallbackCharacterID)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(AlkkagiText.recordTitle)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                Text(AlkkagiText.record(store.record))
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            if let mine = AlkkagiRecordSource.consistentRank(store) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(AlkkagiText.points(mine.points))
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

/// 지금 대결 중 한 줄 — 두 사람(흑 vs 백) · 판돈 · 관전자 수 칩 · [관전].
struct AlkkagiLiveRow: View {
    let live: AlkkagiLiveMatch
    let canWatch: Bool
    let onWatch: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            CheckAvatarView(name: live.black.displayName, userID: live.black.id,
                            avatarURL: live.black.avatarURL.flatMap(URL.init(string:)), size: 18,
                            characterHint: live.black.characterID)
            Text(live.black.displayName).font(.caption2).lineLimit(1)
            Text("vs").font(.caption2).foregroundStyle(CheckTheme.secondaryText)
            CheckAvatarView(name: live.white.displayName, userID: live.white.id,
                            avatarURL: live.white.avatarURL.flatMap(URL.init(string:)), size: 18,
                            characterHint: live.white.characterID)
            Text(live.white.displayName).font(.caption2).lineLimit(1)
            Spacer(minLength: 4)
            if let stake = live.stake {
                HStack(spacing: 2) {
                    RubyIcon(size: 11)
                    Text("\(stake)").font(.caption2.weight(.bold)).monospacedDigit()
                }
                .foregroundStyle(CheckTheme.secondaryText)
            }
            // 관전자 수 — 칩 높이는 [관전] 칩과 **같은 18**(더 크면 카드가 자란다). 0 이면 안 그린다.
            WatcherCountChip(count: live.watchers, height: ReversiWindowLayout.liveWatchChipHeight)
            if canWatch {
                Button(action: onWatch) {
                    Text(AlkkagiText.watch)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CheckTheme.accent)
                        .padding(.horizontal, 8)
                        .frame(height: ReversiWindowLayout.liveWatchChipHeight)
                        .background(Capsule().fill(CheckTheme.accent.opacity(0.16)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
    }
}

/// 로비 오른쪽 열 맨 아래 — 받은 신청 1장(+ 제목 옆 '외 N건') · 보낸 신청 줄 · 안내 줄.
/// 받은 신청은 **`visibleIncoming`** 하나다(차단 거울을 거르고 지금 내 판과 같은 id 를 뺀 첫 신청 — 시계를 읽지 않는다).
struct AlkkagiInvitesBox: View {
    let store: AlkkagiOnlineStore

    var body: some View {
        VStack(alignment: .leading, spacing: ReversiWindowLayout.lobbyInvitesSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(AlkkagiText.incomingTitle).font(.headline)
                let more = store.visibleIncomingInvites.count - 1
                if more > 0 {
                    Text(AlkkagiText.incomingMore(more))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckTheme.secondaryText)
                }
            }
            .frame(height: ReversiWindowLayout.lobbyInvitesTitleHeight)
            if let invite = store.visibleIncoming {
                AlkkagiInviteCard(store: store, invite: invite)
            } else {
                Text(AlkkagiText.noIncoming)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            if let outgoing = store.outgoing {
                AlkkagiOutgoingLine(store: store, outgoing: outgoing)
            }
            if let notice = store.notice {
                ReversiNoticeLine(text: notice)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .chessCard()
    }
}

/// 받은 신청 카드 — 아바타 28 · "{이름}님의 신청" · "N · 이기면 +N" · 남은 초 · [수락][거절].
struct AlkkagiInviteCard: View {
    let store: AlkkagiOnlineStore
    let invite: AlkkagiInvite

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CheckAvatarView(name: invite.opponent.displayName, userID: invite.opponent.id,
                                avatarURL: invite.opponent.avatarURL.flatMap(URL.init(string:)), size: 28,
                                characterHint: invite.opponent.characterID)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AlkkagiText.incomingLine(name: invite.opponent.displayName))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        RubyIcon(size: 11)
                        Text(AlkkagiText.stakeLine(invite.stake))
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                }
                Spacer(minLength: 4)
                AlkkagiServerCountdown(store: store, expiresAtMs: invite.expiresAtMs)
            }
            HStack(spacing: 8) {
                ChessActionButton(title: AlkkagiText.accept, height: 30, fullWidth: true, isEnabled: canRespond) {
                    Task { await store.respond(inviteID: invite.id, accept: true) }
                }
                ChessActionButton(title: AlkkagiText.decline, tint: CheckTheme.offWork, style: .outline,
                                  height: 30, fullWidth: true, isEnabled: canRespond) {
                    Task { await store.respond(inviteID: invite.id, accept: false) }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CheckTheme.accent.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(CheckTheme.accent.opacity(0.4), lineWidth: 1))
    }

    private var canRespond: Bool { !store.isBusy && store.availability == .available }
}

/// 보낸 신청 한 줄 — "보낸 신청 · 이름 · N" · 남은 초 · [취소].
struct AlkkagiOutgoingLine: View {
    let store: AlkkagiOnlineStore
    let outgoing: AlkkagiInvite

    var body: some View {
        HStack(spacing: 8) {
            Text(AlkkagiText.outgoingLine(name: outgoing.opponent.displayName, stake: outgoing.stake))
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            AlkkagiServerCountdown(store: store, expiresAtMs: outgoing.expiresAtMs)
            Spacer(minLength: 4)
            ChessActionButton(title: AlkkagiText.cancel, tint: CheckTheme.offWork, style: .outline,
                              height: 26, isEnabled: !store.isBusy) {
                Task { await store.cancelChallenge() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }
}

/// 신청 남은 초 — **잎**(서버 보정 시계는 이 안에서만 읽는다 · 창이 안 보이면 멈춘다).
struct AlkkagiServerCountdown: View {
    let store: AlkkagiOnlineStore
    let expiresAtMs: Double

    var body: some View {
        TetrisDuelCountdownText(
            expiresAt: Date(timeIntervalSince1970: expiresAtMs / 1_000),
            isLive: store.isWindowVisible,
            now: { Date(timeIntervalSince1970: store.estimatedServerNowMs / 1_000) }
        )
    }
}

// MARK: - 판돈 고르기 창

/// 판돈 고르기 창(= `ReversiStakePrompt` 340pt — §5.4). **고르기와 신청이 갈려 있다** — 판돈 버튼은 고르기만 하고 신청은
/// [N 걸고 도전하기] 한 곳에서만 나간다. 고른 값은 `store.selectedStake` 에 기억한다(D16). 루비가 모자란 판돈은 흐리게(0.45)
/// "루비가 모자라요" — 잔액을 모르면 막지 않는다(서버도 `insufficient` 로 막는다 — 앞단은 친절일 뿐이다).
struct AlkkagiStakePrompt: View {
    let store: AlkkagiOnlineStore
    let target: AlkkagiLobbyUser
    let onClose: () -> Void

    @State private var selection: AlkkagiStake?

    private var chosen: AlkkagiStake { selection ?? store.selectedStake }

    var body: some View {
        ZStack {
            // 막 클릭 닫힘 — 바깥 바닥을 누르면 닫힌다.
            CheckTheme.panelElevated.opacity(0.93)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            VStack(spacing: 12) {
                Text(AlkkagiText.stakePromptTitle(name: target.displayName)).font(.headline)
                Text(AlkkagiText.stakePromptCaption)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(height: 20)
                HStack(spacing: 10) {
                    ForEach(AlkkagiStake.allCases, id: \.rawValue) { stake in
                        stakeButton(stake)
                    }
                }
                Text(Self.affordable(chosen, balance: store.rubyBalance)
                     ? AlkkagiText.stakePromptChosen(chosen.rawValue) : AlkkagiText.stakeShortfall)
                    .font(.caption2)
                    .foregroundStyle(Self.affordable(chosen, balance: store.rubyBalance)
                                     ? CheckTheme.secondaryText : CheckTheme.danger)
                    .monospacedDigit()
                HStack(spacing: 8) {
                    ChessActionButton(title: AlkkagiText.cancel, tint: CheckTheme.offWork, style: .outline,
                                      height: 34, fullWidth: true, action: onClose)
                        .keyboardShortcut(.cancelAction)
                    ChessActionButton(title: AlkkagiText.challengeWithStake(chosen.rawValue), icon: "paperplane.fill",
                                      height: 34, fullWidth: true,
                                      isEnabled: !store.isBusy && Self.affordable(chosen, balance: store.rubyBalance)) {
                        let stake = chosen
                        store.selectedStake = stake
                        onClose()
                        Task { await store.challenge(opponentID: target.id, stake: stake) }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: ReversiWindowLayout.stakePromptWidth)
            .chessCard(padding: 0)
        }
        .frame(width: ReversiWindowLayout.contentSize.width, height: ReversiWindowLayout.contentSize.height)
    }

    /// 잔액 ≥ 판돈. 잔액을 모르면(nil) 막지 않는다.
    static func affordable(_ stake: AlkkagiStake, balance: Int?) -> Bool {
        guard let balance else { return true }
        return balance >= stake.rawValue
    }

    private func stakeButton(_ stake: AlkkagiStake) -> some View {
        let isSelected = chosen == stake
        let enabled = Self.affordable(stake, balance: store.rubyBalance)
        return Button {
            selection = stake
        } label: {
            VStack(spacing: 2) {
                RubyIcon(size: 18)
                Text("\(stake.rawValue)")
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
                Text("이기면 +\(DuelFee.winnerNet(stake: stake.rawValue))")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : CheckTheme.secondaryText)
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Color.white : CheckTheme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
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
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel("판돈 루비 \(stake.rawValue)")
    }
}

// MARK: - 규칙 창

/// 규칙 보기(머리 [규칙] — §5.4). 다섯 줄은 `AlkkagiText.rulesLines`(시험이 번호로 집는다). 툴팁만으로 설명하지 않는다.
struct AlkkagiRulesPrompt: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            CheckTheme.panelElevated.opacity(0.93)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(AlkkagiText.rulesTitle, systemImage: "book.fill")
                        .font(.title3.weight(.bold))
                    Spacer()
                    ChessActionButton(title: AlkkagiText.close, icon: "xmark", style: .outline, height: 30,
                                      action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(AlkkagiText.rulesLines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(CheckTheme.accent)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(CheckTheme.accent.opacity(0.18)))
                            Text(line)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(26)
            .frame(width: 560)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(CheckTheme.panel))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
        }
        .frame(width: ReversiWindowLayout.contentSize.width, height: ReversiWindowLayout.contentSize.height)
    }
}
