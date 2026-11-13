#if os(iOS)
import CheckCore
import SwiftUI

// 1:1 알까기 판 · 연습 · 관전 화면(폰 1.0.18). 맥 `AlkkagiGameView` 의 오른쪽 열(상대 카드 · 내 카드 · 상태 카드 · 돌 수 · [기권] ·
// 결과 카드)을 폰 세로로 옮겼다: (결과) → 상대 줄 → 판 → 내 줄 → 상태 줄(+ 숨겨 놓기 줄) → 아래 동작 막대.
// 스크롤이 없다 — 판 위 끌기가 스크롤과 다투지 않게. 판은 남은 높이에 맞춰 정사각형으로 줄어든다.

/// 서버 판(내 판 · 같은 계정 맥이 두는 판 포함).
struct GamesAlkkagiMatchView: View {
    let store: GamesStore
    @State private var model = GamesAlkkagiBoardModel()
    @State private var confirmingResign = false

    var body: some View {
        let alkkagi = store.alkkagi
        if let state = alkkagi.state {
            let me = GamesMeIdentity.current(store.context)
            let myPeer = state.myColor == .black ? state.black : state.white
            let opponent = state.myColor == .black ? state.white : state.black
            VStack(spacing: MobileTheme.space2) {
                if state.phase == .finished {
                    GamesAlkkagiResultCard(outcome: alkkagi.outcome, reason: alkkagi.endReason, rubyDelta: alkkagi.rubyDelta)
                }
                GamesAlkkagiPlayerRow(name: opponent.displayName, userID: opponent.id, avatarURL: opponent.avatarURL,
                                      characterID: opponent.characterID, color: state.myColor.opponent,
                                      detail: detail(for: state.myColor.opponent, state: state, missed: state.opponentMissedTurns),
                                      clock: isTurn(state.myColor.opponent, state: state) ? alkkagi : nil)
                GamesAlkkagiBoardView(model: model, placingPlayer: state.phase == .placing ? state.myColor : nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(-1)
                GamesAlkkagiPlayerRow(name: me.name ?? myPeer.displayName, userID: myPeer.id, avatarURL: myPeer.avatarURL,
                                      characterID: me.characterID ?? myPeer.characterID, color: state.myColor,
                                      detail: detail(for: state.myColor, state: state, missed: state.myMissedTurns),
                                      clock: isTurn(state.myColor, state: state) ? alkkagi : nil)
                statusLine(alkkagi: alkkagi, state: state)
                if state.phase == .placing {
                    GamesAlkkagiPlacementBar(model: model, ready: state.myReady)
                }
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space1)
            .padding(.bottom, MobileTheme.space2)
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar(alkkagi: alkkagi, state: state) }
            .hidesTabBar(for: .alkkagiMatch)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    GamesNavTitle(title: AlkkagiPhoneText.title) {
                        if let stake = state.stake {
                            GamesStakeLine(stake: stake, suffix: " · 이기면 +\(DuelFee.winnerNet(stake: stake))", gemSize: 13)
                        }
                        GamesWatcherBadge(count: alkkagi.spectatorFeaturesEnabled ? alkkagi.spectatorCount : 0, font: .caption)
                    }
                }
            }
            .onAppear { model.attachOnline(alkkagi) }
            .confirmationDialog(AlkkagiPhoneText.resignWarning(stake: state.stake), isPresented: $confirmingResign,
                                titleVisibility: .visible) {
                Button(AlkkagiPhoneText.confirmResign, role: .destructive) { Task { await alkkagi.resign() } }
                Button(AlkkagiPhoneText.keepPlaying, role: .cancel) {}
            }
        }
    }

    private func isTurn(_ player: AlkkagiGame.Player, state: AlkkagiMatch) -> Bool {
        switch state.phase {
        case .placing: return player == state.myColor ? !state.myReady : !state.opponentReady
        case .aiming: return state.currentPlayer == player
        case .rolling, .finished, .unknown: return false
        }
    }

    private func detail(for player: AlkkagiGame.Player, state: AlkkagiMatch, missed: Int?) -> String {
        var parts: [String]
        if state.phase == .placing {
            let ready = player == state.myColor ? state.myReady : state.opponentReady
            parts = [AlkkagiPhoneText.stoneTitle(player), ready ? AlkkagiPhoneText.readyDone : "숨겨 놓는 중"]
        } else {
            parts = [AlkkagiPhoneText.stoneTitle(player), AlkkagiPhoneText.stonesLeft(model.game.remaining(player))]
        }
        if let missed, missed > 0 { parts.append(AlkkagiPhoneText.missedLine(missed, of: state.forfeitAfter ?? 3)) }
        return parts.joined(separator: " · ")
    }

    /// 상태 한 줄: 안내 > 놓친 차례 경고(주황) > 차례 안내(내 차례면 초록) · 조준 중이면 힘.
    private func statusLine(alkkagi: AlkkagiOnlineStore, state: AlkkagiMatch) -> some View {
        let headline: (String, Color) = {
            if let notice = alkkagi.notice { return (notice, MobileTheme.pending) }
            if let warning = alkkagi.missedTurnWarning,
               let text = AlkkagiNoticeText.missedTurn(mine: warning.mine, forfeitAfter: warning.forfeitAfter) {
                return (text, MobileTheme.pending)
            }
            if let notice = model.notice { return (notice, MobileTheme.pending) }
            if alkkagi.isMyTurn, state.phase != .finished { return (model.status, MobileTheme.working) }
            return (model.status, MobileTheme.label2)
        }()
        return HStack(spacing: 8) {
            Text(headline.0)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(headline.1)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if model.selectedID != nil {
                Text(AlkkagiPhoneText.power(model.power))
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.accent)
            }
        }
        .frame(minHeight: 22)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actionBar(alkkagi: AlkkagiOnlineStore, state: AlkkagiMatch) -> some View {
        HStack(spacing: 10) {
            if state.phase == .finished {
                AingButton(AlkkagiPhoneText.backToLobby, kind: .filled, size: .lg, fillsWidth: true) { alkkagi.backToLobby() }
            } else {
                Text(AlkkagiPhoneText.leaveKeepsMatch)
                    .font(.caption)
                    .foregroundStyle(MobileTheme.label3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                AingButton(AlkkagiPhoneText.resign, systemImage: "flag", kind: .destructive, size: .sm) { confirmingResign = true }
                    .disabled(alkkagi.isBusy)
                    .fixedSize()
            }
        }
        .padding(.horizontal, MobileTheme.sideMargin)
        .padding(.vertical, MobileTheme.space2)
        .background(.bar)
    }
}

/// 연습 판 — 한 폰에서 둘이 번갈아(맥 [연습하기] — 루비 · 전적 · 서버 0). 놓기도 번갈아(흑 → 백), 쏘기는 흑부터.
struct GamesAlkkagiPracticeView: View {
    let onExit: () -> Void
    @State private var model = GamesAlkkagiBoardModel()

    var body: some View {
        let game = model.game
        VStack(spacing: MobileTheme.space2) {
            // 부제('연습 판 · 루비·전적에 남지 않아요')는 머리 제목 아래 한 번만 둔다(11-10 캡처에서 두 번 보였다).
            practiceRow(.white, game: game)
            GamesAlkkagiBoardView(model: model, placingPlayer: game.phase == .placing ? game.currentPlayer : nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(-1)
            practiceRow(.black, game: game)
            HStack(spacing: 8) {
                Text(model.notice ?? model.status)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(model.notice == nil ? MobileTheme.label2 : MobileTheme.pending)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if model.selectedID != nil {
                    Text(AlkkagiPhoneText.power(model.power))
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.accent)
                }
            }
            .frame(minHeight: 22)
            if game.phase == .placing {
                GamesAlkkagiPlacementBar(model: model, ready: false)
            }
        }
        .padding(.horizontal, MobileTheme.sideMargin)
        .padding(.top, MobileTheme.space1)
        .padding(.bottom, MobileTheme.space2)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                AingButton(AlkkagiPhoneText.backToLobby, kind: .gray, size: .md, fillsWidth: true) { onExit() }
                AingButton(AlkkagiPhoneText.practiceRestart, systemImage: "arrow.counterclockwise",
                           kind: game.phase == .finished ? .filled : .tinted, size: .md, fillsWidth: true) {
                    model.restartPractice()
                }
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.space2)
            .background(.bar)
        }
        .hidesTabBar(for: .alkkagiMatch)
        .toolbar {
            ToolbarItem(placement: .principal) {
                GamesNavTitle(title: AlkkagiPhoneText.practiceTitle) {
                    Text(AlkkagiPhoneText.practiceSubtitle).font(.caption)
                }
            }
        }
    }

    private func practiceRow(_ player: AlkkagiGame.Player, game: AlkkagiGame) -> some View {
        let active: Bool = switch game.phase {
        case .placing, .aiming: game.currentPlayer == player
        case .rolling, .finished: false
        }
        return HStack(spacing: 10) {
            GamesAlkkagiStoneMark(player: player).frame(width: 26, height: 26)
            Text(AlkkagiPhoneText.stoneTitle(player))
                .font(.subheadline.weight(.semibold))
            Text(AlkkagiPhoneText.stonesLeft(game.remaining(player)))
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .monospacedDigit()
            Spacer(minLength: 4)
            if active {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    GamesAlkkagiClockText(remaining: model.remainingSeconds)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(active ? MobileTheme.accentTint : MobileTheme.surface))
        .accessibilityElement(children: .combine)
    }
}

/// 관전 — 판 그림(입력 없음) · 두 사람 줄(차례면 시계) · 상태 줄 · 끝나면 결과(3인칭 · 루비 없음) · [나가기].
struct GamesAlkkagiWatchView: View {
    let store: GamesStore
    let watch: AlkkagiWatchState

    var body: some View {
        let alkkagi = store.alkkagi
        VStack(spacing: MobileTheme.space2) {
            if watch.isFinished {
                VStack(spacing: 4) {
                    Text(AlkkagiPhoneText.watchOutcome(watch.result))
                        .font(.title3.weight(.bold))
                    let reason = AlkkagiPhoneText.watchEndReason(watch.endReason, result: watch.result)
                    if !reason.isEmpty {
                        Text(reason).font(.footnote).foregroundStyle(MobileTheme.label2).multilineTextAlignment(.center)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MobileTheme.surface))
                .accessibilityElement(children: .combine)
            }
            watchRow(.white, alkkagi: alkkagi)
            GamesAlkkagiWatchBoard(store: alkkagi, watch: watch)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(-1)
            watchRow(.black, alkkagi: alkkagi)
            HStack(spacing: 8) {
                Text(AlkkagiPhoneText.watchHeadline(watch))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileTheme.accent)
                Spacer(minLength: 4)
                if let stake = watch.stake {
                    GamesStakeLine(stake: stake, prefix: AlkkagiPhoneText.stakeTitle, gemSize: 13)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                }
                GamesWatcherBadge(count: watch.watchers ?? 0, font: .footnote)
            }
            .frame(minHeight: 22)
        }
        .padding(.horizontal, MobileTheme.sideMargin)
        .padding(.top, MobileTheme.space1)
        .padding(.bottom, MobileTheme.space2)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AingButton(AlkkagiPhoneText.leaveWatch, systemImage: "xmark", kind: .gray, size: .md, fillsWidth: true) {
                alkkagi.stopWatching()
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.space2)
            .background(.bar)
        }
    }

    private func watchRow(_ player: AlkkagiGame.Player, alkkagi: AlkkagiOnlineStore) -> some View {
        let peer = player == .black ? watch.black : watch.white
        let ready = player == .black ? watch.blackReady : watch.whiteReady
        let missed = player == .black ? watch.blackMissedTurns : watch.whiteMissedTurns
        let active = watch.phase == .placing ? !ready : (watch.phase == .aiming && watch.currentPlayer == player)
        var parts = [AlkkagiPhoneText.stoneTitle(player)]
        parts.append(watch.phase == .placing ? (ready ? AlkkagiPhoneText.readyDone : "숨겨 놓는 중")
                     : AlkkagiPhoneText.stonesLeft(AlkkagiPhoneText.remaining(watch.stones, player)))
        if missed > 0 { parts.append(AlkkagiPhoneText.missedLine(missed, of: watch.forfeitAfter)) }
        return GamesAlkkagiPlayerRow(name: peer.displayName, userID: peer.id, avatarURL: peer.avatarURL, characterID: peer.characterID,
                                     color: player, detail: parts.joined(separator: " · "),
                                     clock: nil, deadlineMs: active ? watch.deadlineMs : nil, watchStore: alkkagi)
    }
}

// MARK: - 조각

/// 한 사람 줄(아바타 · 이름 · 돌 색 · 남은 돌 · 넘긴 차례 · 차례면 남은 초).
struct GamesAlkkagiPlayerRow: View {
    let name: String
    let userID: String
    let avatarURL: String?
    let characterID: String?
    let color: AlkkagiGame.Player
    let detail: String
    /// 내 판에서 이 사람 차례면 스토어(남은 초를 읽는다).
    var clock: AlkkagiOnlineStore?
    /// 관전 판에서 이 사람 차례면 마감(서버 ms).
    var deadlineMs: Double? = nil
    var watchStore: AlkkagiOnlineStore? = nil

    var body: some View {
        let active = clock != nil || deadlineMs != nil
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                PersonAvatar(name: name, colorSeed: userID, url: avatarURL.flatMap(URL.init(string:)), userID: userID, size: 32,
                             characterHint: characterID)
                GamesAlkkagiStoneMark(player: color).frame(width: 13, height: 13).offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(AlkkagiPhoneText.displayName(name))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(MobileTheme.label2)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let clock {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    GamesAlkkagiClockText(remaining: clock.remainingSeconds)
                }
            } else if let deadlineMs, let watchStore {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    GamesAlkkagiClockText(remaining: max(0, (deadlineMs - watchStore.estimatedServerNowMs) / 1_000))
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(active ? MobileTheme.accentTint : MobileTheme.surface))
        .accessibilityElement(children: .combine)
    }
}

/// 남은 초(10초 이하 주황 · 5초 이하 빨강 — 맥 `clockTint` 와 같은 문턱).
struct GamesAlkkagiClockText: View {
    let remaining: Double

    var body: some View {
        let tint = remaining <= 5 ? MobileTheme.danger : (remaining <= 10 ? MobileTheme.pending : MobileTheme.working)
        Text("\(Int(max(0, remaining).rounded(.up)))초")
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(tint)
    }
}

/// 숨겨 놓기 줄: 내 돌 다섯(누르면 그 돌을 놓을 차례로) · [배치 완료 (n/5)] / [준비 완료] · 안내 한 줄.
struct GamesAlkkagiPlacementBar: View {
    let model: GamesAlkkagiBoardModel
    let ready: Bool

    var body: some View {
        let game = model.game
        let mine = game.stones.filter { $0.owner == game.currentPlayer }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(mine) { stone in
                    Button { model.placementID = stone.id } label: {
                        GamesAlkkagiStoneMark(player: stone.owner)
                            .frame(width: 26, height: 26)
                            .opacity(stone.isPlaced ? 0.4 : 1)
                            .padding(3)
                            .overlay(Circle().stroke(model.placementID == stone.id ? MobileTheme.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canInteract)
                    .accessibilityLabel(Text("\(AlkkagiPhoneText.stoneTitle(stone.owner)) \(stone.id % 5 + 1)번 돌 선택"))
                }
                Spacer(minLength: 4)
                AingButton(ready ? AlkkagiPhoneText.readyDone : AlkkagiPhoneText.placementDone(game.placedCount(game.currentPlayer)),
                           kind: .filled, size: .sm) {
                    model.confirmPlacement()
                }
                .disabled(ready || game.placedCount(game.currentPlayer) < 5 || !model.canInteract)
                .fixedSize()
            }
            Text(model.isOnline ? AlkkagiPhoneText.placingHelpOnline : AlkkagiPhoneText.placingHelpPractice)
                .font(.caption2)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 흑 · 백 돌 표식(오목 돌과 같은 그림).
struct GamesAlkkagiStoneMark: View {
    let player: AlkkagiGame.Player

    var body: some View {
        Canvas { context, size in
            var layer = context
            let r = min(size.width, size.height) / 2 * 0.92
            GamesGomokuBoardCanvas.drawStone(&layer, at: CGPoint(x: size.width / 2, y: size.height / 2), radius: r,
                                             color: player == .black ? .black : .white, opacity: 1)
        }
        .accessibilityHidden(true)
    }
}

/// 결과 카드(내 기준 — 맥 `AlkkagiResultCard` 와 같은 내용).
struct GamesAlkkagiResultCard: View {
    let outcome: AlkkagiOutcome?
    let reason: AlkkagiEndReason?
    let rubyDelta: Int?

    var body: some View {
        let tint: Color = outcome == .win ? MobileTheme.working : (outcome == .loss ? MobileTheme.danger : MobileTheme.label2)
        let reasonText = AlkkagiNoticeText.endReason(reason, outcome: outcome)
        HStack(spacing: 12) {
            Image(systemName: outcome == .draw ? "equal.circle.fill" : (outcome == .win ? "trophy.fill" : "flag.fill"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(AlkkagiPhoneText.outcomeTitle(outcome))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tint)
                if !reasonText.isEmpty {
                    Text(reasonText)
                        .font(.caption)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if let rubyDelta {
                HStack(spacing: 3) {
                    RubyIcon(size: 15)
                    Text(AlkkagiPhoneText.rubyLine(rubyDelta))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(rubyDelta > 0 ? MobileTheme.working : (rubyDelta < 0 ? MobileTheme.danger : MobileTheme.label2))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MobileTheme.surface))
        .accessibilityElement(children: .combine)
    }
}
#endif
