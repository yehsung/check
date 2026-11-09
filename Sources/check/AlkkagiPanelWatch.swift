import SwiftUI
import CheckCore

// 1:1 알까기 — **관전 화면**(SPEC v1.1 §5.7 · DF#79). 로비 자리에 선다(다수 4/4 — 뒤집기 `ReversiSpectateSide` 꼴).
// 왼쪽은 판 화면과 **같은 판 그림**(`AlkkagiDrawing` — 입력 없음 · 흑이 아래), 오른쪽 열은 두 사람 카드(차례면 시계 고리) ·
// 상태 카드(관전자 수 칩) · 끝나면 결과 카드(루비 줄 없음 — 관전자는 돈과 무관) · [나가기].
// 숨긴 배치 중엔 서버가 돌을 싣지 않는다(돌 0 — 관전자는 두 사람 배치를 볼 수 없다). 굴림 중엔 판 화면과 같은 shot
// (`initial_stones` · `pull` · `steps`)으로 되살린다. 문장은 3인칭이다 — 내 기준 문장을 남의 판에 쓰면 자기모순이 된다.

struct AlkkagiSpectateView: View {
    let store: AlkkagiOnlineStore
    let watch: AlkkagiWatchState

    var body: some View {
        HStack(alignment: .top, spacing: BoardGameLayout.columnSpacing) {
            AlkkagiSpectateBoard(store: store, watch: watch)
                .frame(width: BoardGameLayout.boardSide, height: BoardGameLayout.boardSide)
            side
                .frame(width: BoardGameLayout.sideColumnWidth, height: BoardGameLayout.bodyHeight, alignment: .top)
                .clipped()
        }
    }

    private var side: some View {
        VStack(alignment: .leading, spacing: BoardGameLayout.matchSideSpacing) {
            playerCard(.black)
            playerCard(.white)
            if watch.isFinished {
                resultCard
            } else {
                statusCard
            }
            AlkkagiStoneCountCard(black: Self.remaining(watch, .black), white: Self.remaining(watch, .white),
                                  shots: watch.shotCount)
            Spacer(minLength: 0)
            ChessActionButton(title: AlkkagiText.leaveWatch, icon: "xmark", tint: CheckTheme.offWork,
                              style: .outline, height: 34, fullWidth: true) {
                store.stopWatching()
            }
            .frame(height: 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 판 위에 남은 돌 수(나간 돌만 뺀다 — 숨긴 배치 중에도 다섯).
    static func remaining(_ watch: AlkkagiWatchState, _ player: AlkkagiGame.Player) -> Int {
        max(0, 5 - watch.stones.filter { $0.owner == player && $0.isOut }.count)
    }

    /// 상태 한 줄(3인칭 — 순수).
    static func headline(_ watch: AlkkagiWatchState) -> String {
        switch watch.phase {
        case .placing: return AlkkagiText.watchPlacing
        case .rolling: return AlkkagiText.watchRolling
        case .aiming: return AlkkagiText.watchTurn(watch.currentPlayer)
        case .finished: return AlkkagiText.watchOutcome(watch.result)
        case .unknown: return AlkkagiText.watchLoading
        }
    }

    private func playerCard(_ player: AlkkagiGame.Player) -> some View {
        let peer = player == .black ? watch.black : watch.white
        let ready = player == .black ? watch.blackReady : watch.whiteReady
        let missed = player == .black ? watch.blackMissedTurns : watch.whiteMissedTurns
        let isPlacing = watch.phase == .placing
        let active = isPlacing ? !ready : (watch.phase == .aiming && watch.currentPlayer == player)
        let detail = isPlacing ? (ready ? "준비 완료" : "배치 중")
            : "\(AlkkagiText.stoneName(player))돌 \(Self.remaining(watch, player))개"
        let message = missed > 0 ? "넘긴 차례 \(missed)/\(watch.forfeitAfter)" : ""
        return BoardGamePlayerCard(name: peer.displayName, stoneColor: player == .black ? .black : .white,
                                   stoneText: detail, isTurn: active, isMe: false) {
            CharacterPortrait(characterID: peer.characterID ?? ReversiPlayerFace.fallbackCharacterID)
                .frame(width: BoardGameLayout.portraitSize, height: BoardGameLayout.portraitSize)
        } message: {
            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckTheme.pending)
                .monospacedDigit()
        } clock: {
            if active, let deadline = watch.deadlineMs {
                AlkkagiWatchClock(store: store, deadlineMs: deadline)
            }
        }
        .frame(height: BoardGameLayout.playerCardHeight)
    }

    private var statusCard: some View {
        HStack(spacing: 10) {
            Text(Self.headline(watch))
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckTheme.accent)
                .lineLimit(2)
            Spacer(minLength: 4)
            if let stake = watch.stake {
                HStack(spacing: 3) {
                    Text(AlkkagiText.stakeTitle).foregroundStyle(CheckTheme.secondaryText)
                    RubyIcon(size: 13)
                    Text("\(stake)").monospacedDigit()
                }
                .font(.caption.weight(.semibold))
            }
            // 나 말고 몇 명이 같이 보고 있는가. 0 이면 안 그린다.
            WatcherCountChip(count: watch.watchers ?? 0, height: 16)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(CheckTheme.panel.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckTheme.border))
    }

    /// 관전 결과 카드 — 결과 카드 꼴에서 루비 줄과 [로비로] 를 뺐다(관전자는 돈과 무관 · 나가기는 아래 단추 하나).
    private var resultCard: some View {
        HStack(spacing: 12) {
            Image(systemName: watch.result == .draw ? "equal.circle.fill" : "trophy.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(watch.result == .draw ? CheckTheme.offWork : CheckTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(AlkkagiText.watchOutcome(watch.result))
                    .font(.title3.weight(.bold))
                Text(AlkkagiText.watchEndReason(watch.endReason, result: watch.result))
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            WatcherCountChip(count: watch.watchers ?? 0, height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chessCard()
    }
}

/// 관전 판 차례 시계 — **잎**(서버 보정 시계는 이 안에서만 읽는다 · 창이 안 보이면 멈춘다).
private struct AlkkagiWatchClock: View {
    let store: AlkkagiOnlineStore
    let deadlineMs: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !store.isWindowVisible)) { _ in
            let remaining = max(0, (deadlineMs - store.estimatedServerNowMs) / 1_000)
            BoardGameClockRing(remaining: remaining, duration: 30,
                               tint: remaining <= 5 ? CheckTheme.danger : (remaining <= 10 ? CheckTheme.pending : CheckTheme.working))
        }
    }
}

/// 관전 판 그림 — 판 화면(`AlkkagiGameView.board`)과 같은 크기 · 같은 그림. 입력이 없다.
private struct AlkkagiSpectateBoard: View {
    let store: AlkkagiOnlineStore
    let watch: AlkkagiWatchState

    private var boardSide: CGFloat { BoardGameLayout.boardSide - 48 }
    private var isRolling: Bool { watch.phase == .rolling && watch.shot != nil }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.25))
                .frame(width: boardSide, height: boardSide + 12).offset(y: -6)
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !(isRolling && store.isWindowVisible))) { _ in
                let stones = Self.stones(watch, serverNowMs: store.estimatedServerNowMs)
                Canvas { context, size in
                    AlkkagiDrawing.board(context: context, size: size)
                    let scale = size.width / AlkkagiGame.boardSize
                    for stone in stones where stone.isPlaced && !stone.isOut {
                        AlkkagiDrawing.stone(stone, context: context, scale: scale, selected: false,
                                             pull: AlkkagiVector(x: 0, y: 0), launch: nil, hits: [], trails: false)
                    }
                }
                .frame(width: boardSide, height: boardSide)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 7)
            }
            .offset(y: -12)
        }
        .frame(width: BoardGameLayout.boardSide, height: BoardGameLayout.boardSide)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityLabel("알까기 바둑판(관전)")
    }

    /// 그릴 돌(순수). 굴림 중이면 shot 을 처음부터 지금까지 되살린 돌, 아니면 서버 돌 그대로.
    static func stones(_ watch: AlkkagiWatchState, serverNowMs: Double) -> [AlkkagiGame.Stone] {
        guard watch.phase == .rolling, let shot = watch.shot, shot.startedAtMs.isFinite,
              let shooter = shot.initialStones.first(where: { $0.id == shot.stoneID })?.owner,
              var game = AlkkagiGame.restore(stones: shot.initialStones, currentPlayer: shooter, phase: .aiming,
                                            shotCount: max(0, watch.shotCount - 1)),
              game.shoot(stoneID: shot.stoneID, pull: shot.pull) else { return watch.stones }
        var left = min(shot.duration, max(0, (serverNowMs - shot.startedAtMs) / 1_000))
        while left > 1e-9 && game.phase == .rolling {
            let slice = min(0.25, left)
            _ = game.advance(dt: slice)
            left -= slice
        }
        return game.stones
    }
}
