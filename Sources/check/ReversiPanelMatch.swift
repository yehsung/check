import SwiftUI
import CheckCore

// 아잉 뒤집기 — **대국 오른쪽 열 · 결과 카드 · 관전 오른쪽 열**. 계약은 설계서 FLIP/SPEC.md §5.4 · §5.5 · §5.8.
//
// 선수 카드는 **오목 카드 틀**이다(한 수 30초 규칙이 같다): 차례일 때만 30초 링(`GomokuClockRing` 그대로 — 링은
// `GomokuText.turnSeconds = 30` 만 읽는다), AI 차례면 "생각 중". 각 카드에 **현재 돌 수**가 선다.
// 정보는 **글자로** 말한다 — 패스·자동 착수·연속 경고는 상태 상자 글자, 판 위 회색 점의 뜻도 글자로 한 번 더.

// MARK: - 대국 오른쪽 열

struct ReversiMatchSide: View {
    let store: ReversiStore
    let match: ReversiMatchState
    let me: ReversiPlayerFace
    @Binding var confirmResign: Bool
    /// 스냅샷 전용 확인 상태. 앱은 false.
    let showsConfirmPreview: Bool
    let clipsOverflowInsteadOfScroll: Bool

    /// 이 화면(이 판)이 나타난 시각 — [기권] 누름 판정의 기준(`GomokuResignGuard`).
    @State private var shownAt: Date?

    private var showsConfirm: Bool { confirmResign || showsConfirmPreview }

    var body: some View {
        VStack(alignment: .leading, spacing: ReversiWindowLayout.matchSideSpacing) {
            // 위가 **상대**, 아래가 **나**다.
            ReversiPlayerCard(store: store, face: opponentFace, color: match.myColor.opponent,
                              discs: discs(match.myColor.opponent),
                              autoStreak: match.opponentAutoStreak, autoLimit: match.autoAbandonStreak,
                              isTurn: !match.isFinished && match.turn == match.myColor.opponent,
                              isMe: false, isAI: match.isAI)
                .frame(height: ReversiWindowLayout.playerCardHeight)
            ReversiPlayerCard(store: store, face: me, color: match.myColor, discs: discs(match.myColor),
                              autoStreak: match.myAutoStreak, autoLimit: match.autoAbandonStreak,
                              isTurn: !match.isFinished && match.turn == match.myColor, isMe: true, isAI: false)
                .frame(height: ReversiWindowLayout.playerCardHeight)
            HStack(spacing: ReversiWindowLayout.matchSideSpacing) {
                Group {
                    if match.isAI { ReversiAIStakeChip() } else { ChessStakeChip(stake: match.stake) }
                }
                .frame(width: ReversiWindowLayout.stakeChipWidth)
                ReversiStatusBox(store: store, match: match)
            }
            .frame(minHeight: ReversiWindowLayout.stakeStatusMinHeight)
            ReversiMoveListCard(plies: match.plies, counts: match.counts,
                                clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            actionRow
                .frame(height: ReversiWindowLayout.actionRowHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { shownAt = GomokuResignGuard.clock() }
        .onChange(of: match.id) { _, _ in
            shownAt = GomokuResignGuard.clock()
            confirmResign = false
        }
        .onChange(of: store.isWindowVisible) { _, visible in
            if visible { shownAt = GomokuResignGuard.clock() }
        }
        // 확인이 아무 선택 없이 오래 서 있으면 스스로 접는다(다음 누름 하나가 곧 기권이 되지 않게).
        .task(id: confirmResign) {
            guard confirmResign else { return }
            try? await Task.sleep(for: .seconds(GomokuResignGuard.confirmTimeout))
            guard !Task.isCancelled else { return }
            confirmResign = false
        }
    }

    private var opponentFace: ReversiPlayerFace {
        guard match.isAI else { return .of(match.opponent) }
        return ReversiPlayerFace(name: ReversiText.aiOpponentName, avatarURL: nil,
                                 characterID: ReversiPlayerFace.fallbackCharacterID)
    }

    private func discs(_ color: ReversiColor) -> Int {
        color == .black ? match.counts.black : match.counts.white
    }

    @ViewBuilder
    private var actionRow: some View {
        if match.isFinished {
            ChessActionButton(title: ReversiText.backToLobby, icon: "chevron.left", style: .outline,
                              height: ReversiWindowLayout.actionRowHeight, fullWidth: true) {
                store.backToLobby()
            }
        } else if showsConfirm {
            HStack(spacing: 8) {
                ChessActionButton(title: ReversiText.confirmResign, icon: "flag.fill", tint: CheckTheme.danger,
                                  height: ReversiWindowLayout.actionRowHeight, fullWidth: true,
                                  isEnabled: !store.isBusy) {
                    confirmResign = false
                    Task { await store.resign() }
                }
                // 스페이스·↩ 로 눌리지 않는다 — 키보드 탐색이 켜진 맥에서 다른 키가 기권이 되면 안 된다.
                .focusable(false)
                ChessActionButton(title: ReversiText.keepPlaying, tint: CheckTheme.offWork, style: .outline,
                                  height: ReversiWindowLayout.actionRowHeight, fullWidth: true) {
                    confirmResign = false
                }
            }
        } else {
            ChessActionButton(title: ReversiText.resign, icon: "flag", tint: CheckTheme.danger, style: .outline,
                              height: ReversiWindowLayout.actionRowHeight, fullWidth: true,
                              isEnabled: !store.isBusy) {
                // 화면이 막 나타난 직후의 누름(로비 [수락] 더블클릭의 두 번째 누름)은 이 화면을 보고 누른 것이 아니다.
                guard GomokuResignGuard.acceptsTap(shownAt: shownAt, now: GomokuResignGuard.clock()) else { return }
                confirmResign = true
            }
            .focusable(false)
            .checkTooltip(ReversiText.resignHelp)
        }
    }
}

/// 상태 상자가 그리는 글자(순수 — 뷰에서 떼어 두어야 시험이 "사용자가 읽는 글자" 를 값으로 되묻는다).
enum ReversiMatchStatusText {
    static func headline(_ match: ReversiMatchState, isAIThinking: Bool) -> String {
        if match.isFinished { return ReversiText.outcomeTitle(match.outcome) }
        if isAIThinking { return ReversiText.aiThinking }
        return match.isMyTurn ? ReversiText.myTurn : ReversiText.opponentTurn
    }

    /// 둘째 줄. 끝난 판은 까닭, 아니면 스토어 안내가 먼저, 그다음 **방금 일어난 패스**(판에서 드러나지 않는 사실이다).
    static func detail(_ match: ReversiMatchState, notice: String?, opponentName: String) -> String? {
        if match.isFinished { return ReversiText.endReason(match.endReason, outcome: match.outcome) }
        if let notice { return notice }
        return passLine(match, opponentName: opponentName)
    }

    /// 마지막 기록이 패스면 그 사실 한 줄. 상대가 넘겨 내 차례가 이어지면 상대 이름으로, 내가 넘겼으면 "차례가 넘어가요".
    static func passLine(_ match: ReversiMatchState, opponentName: String) -> String? {
        guard !match.isFinished, let last = match.plies.max(by: { $0.seq < $1.seq }), last.kind == .pass,
              let turn = match.turn else { return nil }
        if last.color != match.myColor, turn == match.myColor {
            return ReversiNoticeText.opponentPassed(name: opponentName)
        }
        if last.color == match.myColor, turn != match.myColor {
            return ReversiNoticeText.myPass
        }
        return nil
    }
}

/// 상태 상자(판돈 칩 오른쪽). 지금 무슨 일이 일어나는지 **글자로** 말한다.
struct ReversiStatusBox: View {
    let store: ReversiStore
    let match: ReversiMatchState

    private var opponentName: String { match.isAI ? ReversiText.aiOpponentName : match.opponent.displayName }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(ReversiMatchStatusText.headline(match, isAIThinking: store.isAIThinking))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Spacer(minLength: 4)
                // 내 판을 보고 있는 사람 수. 0 이면 아무것도 안 그린다(애니메이션 없음).
                WatcherCountChip(count: store.spectatorCount, height: 16)
            }
            if let detail = ReversiMatchStatusText.detail(match, notice: store.notice, opponentName: opponentName) {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !match.isFinished, !match.autoStones.isEmpty {
                Text(ReversiText.autoPlacedCount(match.autoStones.count))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            if !match.isFinished,
               let warning = ReversiText.autoStreakWarning(match.myAutoStreak, limit: match.autoAbandonStreak) {
                Text(warning)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckTheme.danger)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: ReversiWindowLayout.stakeStatusMinHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        if match.isFinished {
            switch match.outcome {
            case .won?: return CheckTheme.working
            case .lost?: return CheckTheme.danger
            default: return CheckTheme.offWork
            }
        }
        return match.isMyTurn ? CheckTheme.working : CheckTheme.secondaryText
    }
}

/// AI 판의 판돈 칩 자리 — 걸린 루비가 없다는 것을 같은 모양의 칩으로 말한다.
struct ReversiAIStakeChip: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu").foregroundStyle(CheckTheme.accent)
            Text(ReversiText.aiStakeChip)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: ReversiWindowLayout.stakeStatusMinHeight)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}

// MARK: - 선수 카드

/// 두 사람 카드 한 장(오목 카드 틀). 가로 자리는 언제나 같다: 초상 | 이름·돌(고정 폭) | 남는 폭 | 링 자리(고정 폭, 차례가 아니면 빈다).
struct ReversiPlayerCard: View {
    let store: ReversiStore
    let face: ReversiPlayerFace
    let color: ReversiColor
    /// 판 위 이 색의 돌 수.
    let discs: Int
    let autoStreak: Int
    let autoLimit: Int
    let isTurn: Bool
    let isMe: Bool
    let isAI: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isAI {
                    ReversiAIPortrait()
                } else {
                    CharacterPortrait(characterID: face.characterID)
                }
            }
            .frame(width: ReversiWindowLayout.portraitSide, height: ReversiWindowLayout.portraitSide)
            .overlay(alignment: .bottomTrailing) {
                if let center = face.center {
                    CenterCornerBadge(label: center, avatarSize: ReversiWindowLayout.portraitSide)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(face.name)
                        .font(.callout.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if isMe {
                        Text("나")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CheckTheme.accent)
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(Capsule().fill(CheckTheme.accent.opacity(0.18)))
                    }
                }
                HStack(spacing: 6) {
                    ReversiStoneDot(color: color, size: 14)
                    Text(ReversiText.discLine(color, count: discs))
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                    if let streak = ReversiText.autoStreak(autoStreak, limit: autoLimit) {
                        Text(streak)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CheckTheme.pending)
                            .monospacedDigit()
                    }
                }
            }
            .frame(width: ReversiWindowLayout.nameColumnWidth, alignment: .leading)
            Spacer(minLength: 4)
            ZStack {
                if isTurn {
                    // AI 차례에는 시계가 없다(마감이 없어 링이 0초로 빨갛게 선다) — "생각 중" 표시가 그 자리에 선다.
                    if isAI { ReversiAIThinkingMark() } else { ReversiTurnClock(store: store) }
                }
            }
            .frame(width: ReversiWindowLayout.clockSide, height: ReversiWindowLayout.clockSide)
        }
        .padding(.horizontal, ReversiWindowLayout.cardInsetX)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTurn ? CheckTheme.accent.opacity(0.12) : CheckTheme.panel.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isTurn ? CheckTheme.accent.opacity(0.6) : CheckTheme.border, lineWidth: isTurn ? 1.5 : 1)
        )
    }
}

/// 차례인 사람의 30초 링 — **잎 뷰**. 남은 시간은 스토어가 서버 마감으로 계산한다(`remainingSeconds(now:)`).
/// 창이 안 보이면 멈춘다(`paused: !store.isWindowVisible`).
struct ReversiTurnClock: View {
    let store: ReversiStore
    @Environment(\.reversiPreviewNow) private var previewNow

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !store.isWindowVisible)) { context in
            let remaining = store.remainingSeconds(now: previewNow ?? context.date) ?? 0
            GomokuClockRing(remaining: remaining)
        }
    }
}

/// 관전 링 — 마감 시각을 직접 센다(관전 중 `store.match` 는 nil 이라 스토어 링은 못 쓴다). 0초는 패배가 아니라
/// 자동 착수 **대기**라 주황(`overdueTint`)으로 선다.
struct ReversiDeadlineRing: View {
    let deadline: Date
    let isLive: Bool
    @Environment(\.reversiPreviewNow) private var previewNow

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !isLive)) { context in
            GomokuClockRing(remaining: max(0, deadline.timeIntervalSince(previewNow ?? context.date)),
                            overdueTint: CheckTheme.pending)
        }
    }
}

/// AI 상대 카드의 초상(캐릭터 자리).
struct ReversiAIPortrait: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(CheckTheme.accent.opacity(0.16))
            .overlay(
                Image(systemName: "cpu")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(CheckTheme.accent)
            )
    }
}

/// AI 차례에 링 자리에 서는 표시. 시계를 읽지 않는다(AI 차례엔 마감이 없다).
struct ReversiAIThinkingMark: View {
    var body: some View {
        ZStack {
            Circle().stroke(CheckTheme.accent.opacity(0.35), lineWidth: 5)
            VStack(spacing: 1) {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold))
                Text(ReversiText.aiThinkingShort).font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(CheckTheme.accent)
        }
        .padding(3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ReversiText.aiThinking)
    }
}

// MARK: - 돌 수 · 수 기록

/// 수 기록 한 줄(번호 · 흑 수 · 백 수). **순수 값** — 짝 짓기를 뷰에서 하면 시험이 못 잰다.
struct ReversiMoveRow: Identifiable, Equatable {
    let number: Int
    var black: ReversiPly?
    var white: ReversiPly?

    var id: Int { number }
}

enum ReversiMoveLog {
    /// 수 기록을 화면 줄로 짝 짓는다. **색으로** 짝을 짓는다 — 홀짝으로 자르면 기록 구멍·관전 중간 합류에서 흑·백 칸이
    /// 통째로 밀린다. 흑이 줄을 열고 백이 그 줄을 닫는다. 패스도 한 수(그 색 칸에 "넘김")다.
    static func rows(_ plies: [ReversiPly]) -> [ReversiMoveRow] {
        var rows: [ReversiMoveRow] = []
        for ply in plies.sorted(by: { $0.seq < $1.seq }) {
            switch ply.color {
            case .black:
                rows.append(ReversiMoveRow(number: rows.count + 1, black: ply, white: nil))
            case .white:
                if var last = rows.last, last.white == nil, last.black != nil {
                    last.white = ply
                    rows[rows.count - 1] = last
                } else {
                    rows.append(ReversiMoveRow(number: rows.count + 1, black: nil, white: ply))
                }
            }
        }
        return rows
    }
}

/// 돌 수·수 기록 카드. 제목 줄에 **돌 수**("흑 N · 백 N · 빈칸 N")가 서고 아래가 수 목록이다(SPEC §5.2 의 322 자리).
struct ReversiMoveListCard: View {
    let plies: [ReversiPly]
    let counts: ReversiCounts
    let clipsOverflowInsteadOfScroll: Bool

    var body: some View {
        let lastSeq = plies.map(\.seq).max()
        VStack(alignment: .leading, spacing: ReversiWindowLayout.moveHeaderSpacing) {
            HStack(alignment: .center, spacing: 6) {
                Text(ReversiText.movesTitle).font(.headline)
                Spacer(minLength: 4)
                ReversiStoneDot(color: .black, size: 11)
                ReversiStoneDot(color: .white, size: 11)
                Text(ReversiText.counts(counts))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(height: ReversiWindowLayout.moveHeaderHeight)
            if plies.isEmpty {
                Text(ReversiText.noMoves)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ReversiScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: ReversiWindowLayout.moveRowSpacing) {
                        ForEach(ReversiMoveLog.rows(plies)) { row in
                            ReversiMoveLine(row: row, highlightSeq: lastSeq)
                                .frame(height: ReversiWindowLayout.moveRowHeight)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chessCard()
    }
}

struct ReversiMoveLine: View {
    let row: ReversiMoveRow
    let highlightSeq: Int?

    var body: some View {
        HStack(spacing: 8) {
            Text("\(row.number).")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(width: ReversiWindowLayout.moveNumberWidth, alignment: .trailing)
            cell(row.black)
            cell(row.white)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cell(_ ply: ReversiPly?) -> some View {
        let isLast = ply != nil && ply?.seq == highlightSeq
        let isPass = ply?.kind == .pass
        Text(ply.map(ReversiText.plyText) ?? "")
            .font(.caption.weight(isLast ? .bold : .regular))
            .foregroundStyle(isLast ? CheckTheme.accent
                             : (isPass || ply?.auto == true ? CheckTheme.secondaryText : CheckTheme.primaryText))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(width: ReversiWindowLayout.moveCellWidth, height: ReversiWindowLayout.moveRowHeight,
                   alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isLast ? CheckTheme.accent.opacity(0.16) : Color.clear)
            )
    }
}

// MARK: - 결과 카드

/// 결과 카드(체스 `ChessResultCard` 틀). 승·패·무 아이콘 + 까닭 + 점수 줄 + 루비 줄(순수익). 무승부는 루비 0 · 환불.
/// AI 판은 루비 줄을 빼고 [다시 두기] 를 둔다.
struct ReversiResultCard: View {
    let store: ReversiStore
    let match: ReversiMatchState

    private var tint: Color {
        switch match.outcome {
        case .won?: return CheckTheme.working
        case .lost?: return CheckTheme.danger
        default: return CheckTheme.offWork
        }
    }

    private var icon: String {
        switch match.outcome {
        case .won?: return "trophy.fill"
        case .lost?: return "xmark.circle.fill"
        default: return "equal.circle.fill"
        }
    }

    /// 점수 줄. 자연 종료는 WOF 점수(흑 : 백 고정), 기권·자리 비움은 판 위 돌 수만(V-15).
    static func scoreText(_ match: ReversiMatchState) -> String {
        switch match.endReason {
        case .resign?, .abandoned?, .unknown?, nil:
            return ReversiText.boardOnlyLine(match.counts)
        case .wipeout?, .boardFull?, .noMoves?:
            guard let score = match.score ?? ReversiRules.score(match.board) else {
                return ReversiText.boardOnlyLine(match.counts)
            }
            return "\(ReversiText.scoreLabel)  \(ReversiText.scoreLine(score, counts: match.counts))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ReversiText.outcomeTitle(match.outcome))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(tint)
                    Text(ReversiText.endReason(match.endReason, outcome: match.outcome))
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if !match.isAI {
                    HStack(spacing: 4) {
                        RubyIcon(size: 18)
                        Text(ReversiText.rubyLine(outcome: match.outcome, stake: match.stake))
                            .font(match.outcome == .draw ? .callout.weight(.bold) : .title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(rubyTint)
                            .lineLimit(1)
                    }
                }
            }
            HStack(spacing: 8) {
                ReversiStoneDot(color: .black, size: 12)
                ReversiStoneDot(color: .white, size: 12)
                Text(Self.scoreText(match))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if match.isAI {
                Text(ReversiText.aiInfo)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            HStack(spacing: 8) {
                if match.isAI {
                    ChessActionButton(title: ReversiText.playAgain, icon: "arrow.clockwise", height: 32,
                                      fullWidth: true) { store.restartAIMatch() }
                }
                ChessActionButton(title: ReversiText.backToLobby, icon: "chevron.left", style: .outline,
                                  height: 32, fullWidth: true) { store.backToLobby() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chessCard()
    }

    private var rubyTint: Color {
        switch match.outcome {
        case .won?: return CheckTheme.working
        case .lost?: return CheckTheme.danger
        default: return CheckTheme.secondaryText
        }
    }
}

// MARK: - 관전 오른쪽 열

struct ReversiSpectateSide: View {
    let store: ReversiStore
    let watch: ReversiSpectating
    let clipsOverflowInsteadOfScroll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ReversiWindowLayout.matchSideSpacing) {
            // 색은 **서버 응답으로만** 확정한다(로비 카드의 a/b 는 uuid 순서이고 색이 아니다).
            ReversiWatchPlayerCard(store: store, user: watch.blackUser, color: .black, discs: watch.counts.black,
                                   autoStreak: watch.blackAutoStreak,
                                   isTurn: !watch.isFinished && watch.turn == .black, deadline: watch.deadline)
                .frame(height: ReversiWindowLayout.playerCardHeight)
            ReversiWatchPlayerCard(store: store, user: watch.whiteUser, color: .white, discs: watch.counts.white,
                                   autoStreak: watch.whiteAutoStreak,
                                   isTurn: !watch.isFinished && watch.turn == .white, deadline: watch.deadline)
                .frame(height: ReversiWindowLayout.playerCardHeight)
            HStack(spacing: ReversiWindowLayout.matchSideSpacing) {
                // 관전자는 이겨도 한 푼도 못 얻는다 — 판돈 숫자만(`showsReward: false`).
                ChessStakeChip(stake: watch.stake, showsReward: false)
                ReversiWatchStatusBox(store: store, watch: watch)
            }
            .frame(minHeight: ReversiWindowLayout.stakeStatusMinHeight)
            ReversiMoveListCard(plies: watch.plies, counts: watch.counts,
                                clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            ChessActionButton(title: ReversiText.leaveWatch, icon: "xmark", tint: CheckTheme.offWork,
                              style: .outline, height: ReversiWindowLayout.spectateLeaveHeight, fullWidth: true) {
                store.leaveWatch()
            }
            .frame(height: ReversiWindowLayout.spectateLeaveHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ReversiWatchPlayerCard: View {
    let store: ReversiStore
    let user: ReversiUser?
    let color: ReversiColor
    let discs: Int
    let autoStreak: Int
    let isTurn: Bool
    let deadline: Date?

    var body: some View {
        HStack(spacing: 12) {
            CharacterPortrait(characterID: user?.characterID ?? ReversiPlayerFace.fallbackCharacterID)
                .frame(width: ReversiWindowLayout.portraitSide, height: ReversiWindowLayout.portraitSide)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 6) {
                Text(user?.displayName ?? "—")
                    .font(.callout.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    ReversiStoneDot(color: color, size: 14)
                    Text(ReversiText.discLine(color, count: discs))
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .monospacedDigit()
                    if let streak = ReversiText.autoStreak(autoStreak, limit: ReversiAIGame.autoLossStreak) {
                        Text(streak)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CheckTheme.pending)
                            .monospacedDigit()
                    }
                }
            }
            .frame(width: ReversiWindowLayout.nameColumnWidth, alignment: .leading)
            Spacer(minLength: 4)
            ZStack {
                if isTurn, let deadline {
                    ReversiDeadlineRing(deadline: deadline, isLive: store.isWindowVisible)
                }
            }
            .frame(width: ReversiWindowLayout.clockSide, height: ReversiWindowLayout.clockSide)
        }
        .padding(.horizontal, ReversiWindowLayout.cardInsetX)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTurn ? CheckTheme.accent.opacity(0.12) : CheckTheme.panel.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isTurn ? CheckTheme.accent.opacity(0.6) : CheckTheme.border, lineWidth: isTurn ? 1.5 : 1)
        )
    }
}

/// 관전 상태 상자가 그리는 **두 줄**(순수 값). 3인칭이다 — 내 기준 문장을 남의 판에 쓰면 자기모순이 된다.
enum ReversiWatchStatusText {
    static func headline(_ watch: ReversiSpectating) -> String {
        if watch.isFinished {
            guard let winner = watch.winner else { return "무승부로 끝났어요" }
            return "\(ReversiText.stoneName(winner)) 승리"
        }
        // 색이 서기 전(첫 응답 전)에는 차례를 말하지 않는다.
        guard watch.blackUser != nil, watch.whiteUser != nil else { return ReversiText.watchLoading }
        guard let turn = watch.turn else { return ReversiText.watchLoading }
        return "\(ReversiText.stoneName(turn)) 차례"
    }

    static func detail(_ watch: ReversiSpectating, notice: String?) -> String {
        if watch.isFinished { return ReversiText.watchEndReason(watch.endReason, winner: watch.winner) }
        if let notice { return notice }
        return ReversiText.watchPaused
    }
}

struct ReversiWatchStatusBox: View {
    let store: ReversiStore
    let watch: ReversiSpectating

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(ReversiWatchStatusText.headline(watch))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(watch.isFinished ? CheckTheme.offWork : CheckTheme.accent)
                    .lineLimit(1)
                Spacer(minLength: 4)
                // 나 말고 몇 명이 같이 보고 있는가. 0 이면 안 그린다.
                WatcherCountChip(count: store.spectatorCount, height: 16)
            }
            Text(ReversiWatchStatusText.detail(watch, notice: store.notice))
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: ReversiWindowLayout.stakeStatusMinHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}
