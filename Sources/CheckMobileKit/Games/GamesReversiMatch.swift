import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 뒤집기 **대국·결과 화면**(판 갈래 2/4 — 대표 답 #d_DdwzmxPClGqk "다 넣기 (루비 걸기 포함)").
// 사람끼리 1:1 판과 로봇 연습 판이 **한 화면**이다(코어가 두 판을 같은 `match` 칸에 싣는다 — `match.isAI`). 판 종류별 차이와
// 돈이 갈리는 판정(결과 · 루비 · 무승부 환불 · 동작 줄)은 전부 이 파일 위쪽의 **순수 표**(`GamesReversiMatchChrome`)에 있다 —
// 폰 뷰는 맥 스위트가 못 보지만 그 표는 보인다(`GamesReversiMatchTests`).
//
// 본: 배치는 폰 오목 대국(상대 카드 → 판 → 내 카드 → 판 밑 줄)과 폰 체스(결과 카드가 판 위 · 동작 줄은 스크롤 밖 아래 막대),
// 30초 링 · 3초 테두리 · 자동 착수 줄은 폰 오목 판이 본이다. 맥 `ReversiPanelMatch` 는 문구·순서 참고로만 썼다.
//
// 지키는 계약(코어 머리말 ①~⑪ 중 화면 몫):
//  ① **서버가 권위다.** 판·차례·시계·결과는 코어 `match` 만 그린다 — 낙관적 착수·낙관적 루비가 없다.
//  ⑥ **초 단위 값은 잎 뷰만** 읽는다(30초 링 · 차례 한 줄 · 3초 테두리). 화면 루트는 시계를 읽지 않는다.
//  ⑦ **둘 수 있는 칸은 코어 `legalTargets` 하나**(1:1 은 서버 목록, 로봇 판은 로컬 규칙 — 화면은 어느 쪽인지 모른다).
//  ⑩ 30초가 지나면 서버(로봇 판은 코어)가 대신 두고, 연속 `autoAbandonStreak` 번이면 진다 — 화면은 그 사실을 **글자로** 말한다
//     (카드 '자동 1/3' · 빨강 한 줄 '한 번 더…' · 판 위 회색 점과 그 뜻 한 줄).
//  · 화면 수명(나타남·사라짐·앱 전환)은 `GamesStore` 가 쥔다(배선 갈래 1/4) — 이 화면은 코어 창 문을 부르지 않는다.
//  · 기권은 **불투명 확인 시트**를 지난다(오목·체스가 데인 자리 — 확인 대화상자는 iOS 26 에서 위쪽 말풍선으로 떠 버튼이 가렸다).

// MARK: - 화면 표 (순수 — 돈이 갈리는 판정은 전부 여기)

/// 대국·결과 화면이 그리는 것을 **값으로** 내놓는 표. 뷰는 이 표를 배치만 한다(색은 뜻만 — `GamesChessMatchTint` 를 같이 쓴다).
package struct GamesReversiMatchChrome: Equatable, Sendable {
    /// 아래 동작 줄.
    package enum ActionRow: Equatable, Sendable {
        /// 두는 중 — [기권]. 왕복 중이면 눌리지 않는다.
        case playing(canResign: Bool)
        /// 끝난 판 — [로비로](로봇 판은 [같은 색으로 다시 두기] 가 함께 선다).
        case finished(showsPlayAgain: Bool)
    }

    /// 끝난 판 한 장.
    package struct Result: Equatable, Sendable {
        package let title: String
        package let reason: String
        package let tint: GamesChessMatchTint
        /// 이 판으로 내 루비가 변한 양(승 +순이익 · 패 −판돈 · 무 0).
        package let rubyDelta: Int
        package let rubyDeltaText: String
        /// 로봇 판은 루비를 안 그린다(±0 을 그리면 걸었다가 돌려받은 것처럼 읽힌다 — 맥 `ReversiResultCard` 와 같은 판단).
        package let showsRubyDelta: Bool
        /// 무승부 환불 한 줄 · 로봇 판의 "기록 없음" 한 줄.
        package let rubyNote: String?
        /// 점수 줄(자연 종료는 흑 : 백 점수 · 기권·자리 비움은 판 위 돌 수만).
        package let scoreLine: String
        package let opponentLine: String
        package let isDraw: Bool
    }

    package let isAI: Bool
    package let showsStake: Bool
    package let stake: Int
    package let stakeSuffix: String?
    /// 상대 카드의 이름(로봇 판은 '로봇' · 모르는 상대는 '상대').
    package let opponentName: String
    package let actionRow: ActionRow
    /// 상태 둘째 줄 — 스토어 안내가 먼저, 그다음 **방금 일어난 패스**(판에서 드러나지 않는 사실이다). 끝난 판은 nil.
    package let detailLine: GamesChessMatchLine?
    /// 판 위 회색 점의 뜻(끝난 판·자동 돌 없음이면 nil).
    package let autoPlacedLine: String?
    /// 한 번 더 놓치면 지는 순간의 빨강 한 줄.
    package let autoStreakWarning: String?
    /// 시계 규칙 한 줄(1:1 은 서버 시계 · 로봇 판은 떠나면 멈춘다).
    package let clockLine: String
    /// 30초 링이 가득 찬 값(초). 1:1 은 로비가 말한 값, 로봇 판은 로컬 판의 값.
    package let turnSeconds: Int
    package let resignConfirmTitle: String
    package let resignConfirmMessage: String
    package let result: Result?

    /// - Parameter serverTurnSeconds: 로비가 말한 한 수 시간(코어 `turnSeconds` — 응답이 없으면 30). 로봇 판은 쓰지 않는다.
    package init(match: ReversiMatchState, notice: String?, isBusy: Bool, serverTurnSeconds: Int) {
        let isAI = match.isAI
        self.isAI = isAI
        showsStake = !isAI
        stake = match.stake
        stakeSuffix = isAI ? nil : ReversiPhoneText.stakeGainSuffix(match.stake)
        let name = match.opponent.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        opponentName = isAI ? ReversiPhoneText.aiName : (name.isEmpty ? ReversiPhoneText.opponentFallbackName : name)
        turnSeconds = isAI ? Int(ReversiAIGame.turnSeconds) : max(1, serverTurnSeconds)
        let lossStreak = max(1, match.autoAbandonStreak)
        clockLine = ReversiPhoneText.clockLine(isAI: isAI, turnSeconds: turnSeconds, lossStreak: lossStreak)
        resignConfirmTitle = isAI ? ReversiPhoneText.aiResignConfirmTitle : ReversiPhoneText.resignConfirmTitle
        resignConfirmMessage = isAI ? ReversiPhoneText.aiNoRecord : ReversiPhoneText.resignConfirmMessage

        if match.isFinished {
            actionRow = .finished(showsPlayAgain: isAI)
            detailLine = nil
            autoPlacedLine = nil
            autoStreakWarning = nil
            result = Self.makeResult(match: match, isAI: isAI)
        } else {
            actionRow = .playing(canResign: !isBusy)
            if let notice {
                detailLine = GamesChessMatchLine(text: notice, tint: .warn)
            } else if let pass = Self.passLine(match, opponentName: opponentName) {
                detailLine = GamesChessMatchLine(text: pass, tint: .quiet)
            } else {
                detailLine = nil
            }
            autoPlacedLine = match.autoStones.isEmpty ? nil : ReversiPhoneText.autoPlacedCount(match.autoStones.count)
            autoStreakWarning = ReversiPhoneText.autoStreakWarning(match.myAutoStreak, limit: lossStreak)
            result = nil
        }
    }

    /// 마지막 기록이 패스면 그 사실 한 줄(맥 `ReversiMatchStatusText.passLine` 과 같은 판정). 상대가 넘겨 내 차례가 이어지면 상대 이름으로,
    /// 내가 넘겼으면 "차례가 넘어가요". 스토어의 패스 안내(`notice`)는 다음 수가 오면 걷히므로, 그 뒤에도 판에서 안 보이는 이 사실을 기록에서 읽는다.
    package static func passLine(_ match: ReversiMatchState, opponentName: String) -> String? {
        guard !match.isFinished, let last = match.plies.max(by: { $0.seq < $1.seq }), last.kind == .pass,
              let turn = match.turn else { return nil }
        if last.color != match.myColor, turn == match.myColor { return ReversiNoticeText.opponentPassed(name: opponentName) }
        if last.color == match.myColor, turn != match.myColor { return ReversiNoticeText.myPass }
        return nil
    }

    /// 이 판으로 내 루비가 변한 양. 승자 순이익은 `DuelFee.winnerNet`(서버와 같은 식 — 수수료 0 이라 +판돈) · 패 −판돈 · 무 0.
    package static func rubyDelta(outcome: ReversiMatchOutcome?, stake: Int) -> Int {
        switch outcome {
        case .won?: return DuelFee.winnerNet(stake: stake)
        case .lost?: return -stake
        case .draw?, nil: return 0
        }
    }

    /// 점수 줄. 자연 종료는 WOF 점수(흑 : 백 고정), 기권·자리 비움은 판 위 돌 수만(점수가 없다).
    package static func scoreLine(_ match: ReversiMatchState) -> String {
        switch match.endReason {
        case .resign?, .abandoned?, .unknown?, nil:
            return ReversiPhoneText.boardOnlyLine(match.counts)
        case .wipeout?, .boardFull?, .noMoves?:
            guard let score = match.score ?? ReversiRules.score(match.board) else {
                return ReversiPhoneText.boardOnlyLine(match.counts)
            }
            return ReversiPhoneText.scoreLine(score, counts: match.counts)
        }
    }

    private static func makeResult(match: ReversiMatchState, isAI: Bool) -> Result {
        let outcome = match.outcome
        let delta = isAI ? 0 : rubyDelta(outcome: outcome, stake: match.stake)
        let isDraw = outcome == .draw
        let tint: GamesChessMatchTint = {
            switch outcome {
            case .won?: return .good
            case .lost?: return .bad
            default: return .quiet
            }
        }()
        // 환불 한 줄은 **무승부일 때만**이고 로봇 판에는 없다(걸린 루비가 없다 — 대신 기록이 안 남는다는 한 줄).
        let note: String? = {
            if isAI { return ReversiPhoneText.aiNoRecord }
            if isDraw, match.stake > 0 { return ReversiPhoneText.drawRefund(stake: match.stake) }
            return nil
        }()
        let subject = isAI ? ReversiPhoneText.aiName : ReversiPhoneText.opponentFallbackName
        let name = match.opponent.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(
            title: ReversiPhoneText.outcomeTitle(outcome),
            reason: ReversiPhoneText.endReason(match.endReason, outcome: outcome, opponent: subject,
                                               lossStreak: max(1, match.autoAbandonStreak)),
            tint: tint, rubyDelta: delta, rubyDeltaText: ReversiPhoneText.rubyDelta(delta),
            showsRubyDelta: !isAI, rubyNote: note, scoreLine: scoreLine(match),
            opponentLine: isAI ? ReversiPhoneText.aiOpponentLine
                               : ReversiPhoneText.opponentLine(name.isEmpty ? ReversiPhoneText.opponentFallbackName : name),
            isDraw: isDraw)
    }

    /// 카드 부제 "흑 · 12개 · 자동 1/3".
    package static func cardSubtitle(color: ReversiColor, counts: ReversiCounts, autoStreak: Int, limit: Int) -> String {
        let discs = ReversiPhoneText.discLine(color, count: color == .black ? counts.black : counts.white)
        guard let streak = ReversiPhoneText.autoStreak(autoStreak, limit: max(1, limit)) else { return discs }
        return discs + " · " + streak
    }

    // MARK: 시간을 받는 것 — **잎 뷰 전용**(⑥)

    /// 차례 한 줄. `now` 는 잎 뷰의 스토어 시계다.
    ///
    /// 1:1 판의 마감 + 서버 유예가 지나면 "자동으로 놓이는 중"이라고 말한다 — 폰이 수를 정한 것이 아니라 서버가 정산하는 중이다
    /// (폴링이 그 정산을 부른다 — 코어 `pollTick` 의 overdue 갈래). 로봇 판은 코어 시계 작업이 마감에 곧바로 두므로 이 갈래가 없다.
    package static func turnLine(match: ReversiMatchState, now: Date, graceSeconds: TimeInterval,
                                 isAIThinking: Bool) -> GamesChessMatchLine {
        if match.isFinished {
            let tint: GamesChessMatchTint = match.outcome == .won ? .good : (match.outcome == .lost ? .bad : .quiet)
            return GamesChessMatchLine(text: ReversiPhoneText.outcomeTitle(match.outcome), tint: tint)
        }
        if isAIThinking { return GamesChessMatchLine(text: ReversiPhoneText.aiThinking, tint: .quiet) }
        if !match.isAI, let deadline = match.deadline, now >= deadline.addingTimeInterval(max(0, graceSeconds)) {
            return GamesChessMatchLine(text: match.isMyTurn ? ReversiPhoneText.mySettling : ReversiPhoneText.opponentSettling,
                                       tint: .warn)
        }
        return match.isMyTurn ? GamesChessMatchLine(text: ReversiPhoneText.myTurn, tint: .good)
                              : GamesChessMatchLine(text: ReversiPhoneText.opponentTurn, tint: .quiet)
    }

    /// 30초 링의 채움(0…1) — 남은 초 / 한 수 시간.
    package static func ringFraction(remaining: Double, turnSeconds: Int) -> Double {
        guard remaining.isFinite else { return 0 }
        return min(1, max(0, remaining / Double(max(1, turnSeconds))))
    }

    /// 링 색의 뜻: 넉넉하면 초록 · 10초 이하 앰버 · 5초 이하 빨강(폰 오목 링과 같은 문턱).
    package static func ringTint(remaining: Double) -> GamesChessMatchTint {
        if remaining <= 5 { return .bad }
        if remaining <= 10 { return .warn }
        return .good
    }
}

/// 수 기록 칩 한 줄(가로 스크롤). **색으로** 짝을 짓는다 — 흑이 줄을 열고 백이 그 줄을 닫는다(맥 `ReversiMoveLog` 와 같은 판정).
/// 홀짝으로 자르면 패스·기록 구멍에서 번호가 통째로 밀린다. 줄 번호는 그 줄의 첫 칩에만 붙는다.
package enum GamesReversiMoveLog {
    package struct Chip: Identifiable, Equatable, Sendable {
        package let id: Int
        /// 줄 번호("3.") — 줄의 첫 칩만.
        package let number: Int?
        package let color: ReversiColor
        package let text: String
        package let isPass: Bool
        package let isAuto: Bool
    }

    package static func chips(_ plies: [ReversiPly]) -> [Chip] {
        var chips: [Chip] = []
        var rows = 0
        var openRowHasBlack = false
        for ply in plies.sorted(by: { $0.seq < $1.seq }) {
            let opensRow: Bool
            switch ply.color {
            case .black:
                opensRow = true
                openRowHasBlack = true
            case .white:
                opensRow = !openRowHasBlack
                openRowHasBlack = false
            }
            if opensRow { rows += 1 }
            chips.append(Chip(id: ply.seq, number: opensRow ? rows : nil, color: ply.color,
                              text: ReversiPhoneText.plyText(ply), isPass: ply.kind == .pass, isAuto: ply.auto))
        }
        return chips
    }
}

#if os(iOS)

// MARK: - 대국·결과 화면

/// 아잉 뒤집기 대국·결과 한 화면: (결과 카드) → 상대 카드 → 판 → 내 카드 → 차례·안내 줄 → 수 기록 → 아래 동작 막대.
/// 끝난 판은 **판을 그대로 두고** 위에 결과 카드가 선다(마지막 수가 뒤집히는 것까지 보여야 왜 끝났는지 안다).
struct GamesReversiMatchView: View {
    let store: GamesStore

    /// 이 화면(이 판)이 나타난 시각 — [기권] 누름 가드의 기준(로비 [수락] 두 번 누름의 두 번째가 막 열린 판에 떨어지는 길).
    @State private var shownAt: Date?
    @State private var confirmsResign = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var reversi: ReversiStore { store.reversi }

    var body: some View {
        if let match = reversi.match {
            matchBody(match: match, chrome: GamesReversiMatchChrome(
                match: match, notice: reversi.notice, isBusy: reversi.isBusy, serverTurnSeconds: reversi.turnSeconds))
        }
    }

    private func matchBody(match: ReversiMatchState, chrome: GamesReversiMatchChrome) -> some View {
        let me = GamesMeIdentity.current(store.context)
        return GeometryReader { screen in
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space2) {
                    if let result = chrome.result {
                        GamesReversiResultCard(result: result, me: me, myColor: match.myColor)
                    }
                    GamesReversiPlayerCard(
                        store: reversi, characterID: chrome.isAI ? ReversiUser.reversiAI.characterID : match.opponent.characterID,
                        mood: chrome.isAI ? .plain : (match.opponent.isWorking ? .working : .off),
                        name: chrome.opponentName, center: chrome.isAI ? nil : match.opponent.center, isMe: false,
                        color: match.myColor.opponent,
                        subtitle: GamesReversiMatchChrome.cardSubtitle(
                            color: match.myColor.opponent, counts: match.counts,
                            autoStreak: match.opponentAutoStreak, limit: match.autoAbandonStreak),
                        isTurn: !match.isFinished && match.turn == match.myColor.opponent,
                        isAI: chrome.isAI, turnSeconds: chrome.turnSeconds)
                    board(match: match, visible: screen.size)
                    GamesReversiPlayerCard(
                        store: reversi, characterID: me.characterID, mood: me.mood,
                        name: me.name ?? ReversiPhoneText.me, center: nil, isMe: me.name != nil,
                        color: match.myColor,
                        subtitle: GamesReversiMatchChrome.cardSubtitle(
                            color: match.myColor, counts: match.counts,
                            autoStreak: match.myAutoStreak, limit: match.autoAbandonStreak),
                        isTurn: !match.isFinished && match.turn == match.myColor,
                        isAI: false, turnSeconds: chrome.turnSeconds)
                    statusLines(match: match, chrome: chrome)
                    GamesReversiMoveList(plies: match.plies, counts: match.counts)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space1)
                .padding(.bottom, MobileTheme.space4)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // 동작 줄은 **스크롤 밖**이다(체스 실측 — 큰 글자에서 [기권]이 화면 마지막 픽셀 줄에서 잘렸다). `GeometryReader` 바깥에 달아
        // 판 예산(보이는 높이)에서 막대 높이가 저절로 빠진다.
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar(chrome: chrome) }
        // 탭 막대를 숨긴다 — 몰입 화면 + 자체 동작 줄이고, 한 수 30초라 탭을 잘못 눌러 빠져나가면 자동 착수가 쌓인다.
        .hidesTabBar(for: .reversiMatch)
        .toolbar {
            ToolbarItem(placement: .principal) {
                GamesNavTitle(title: ReversiPhoneText.title) {
                    if chrome.showsStake {
                        GamesStakeLine(stake: chrome.stake, suffix: chrome.stakeSuffix, gemSize: 13)
                    } else {
                        Label(ReversiPhoneText.aiStakeChip, systemImage: "cpu")
                    }
                    // 내 판을 보고 있는 사람 수. 0 이면 서지 않으므로 로봇 판에서도 모양이 그대로다.
                    GamesWatcherBadge(count: reversi.spectatorCount, font: .caption)
                }
            }
        }
        .onAppear { shownAt = reversi.clock() }
        .onChange(of: match.id) { _, _ in
            shownAt = reversi.clock()
            confirmsResign = false
        }
        // 확인을 띄운 채 판이 끝났다(상대 기권 · 자동 착수 3번) — 끝난 판에 '기권하기'가 남지 않게 접는다.
        .onChange(of: match.isFinished) { _, finished in
            if finished { confirmsResign = false }
        }
        .sheet(isPresented: $confirmsResign) {
            AingConfirmSheet(
                title: chrome.resignConfirmTitle,
                message: chrome.resignConfirmMessage,
                confirmTitle: ReversiPhoneText.resignNow,
                cancelTitle: ReversiPhoneText.keepPlaying,
                onConfirm: {
                    confirmsResign = false
                    Task { await reversi.resign() }
                },
                onCancel: { confirmsResign = false })
        }
        .sensoryFeedback(match.outcome == .won ? .success : .warning, trigger: match.isFinished)
    }

    // MARK: 판

    /// 판 한 장. 둘 수 있는 칸은 코어 `legalTargets`(⑦) — 화면은 1:1 인지 로봇 판인지 모른다. 끝난 판은 입력이 없다.
    private func board(match: ReversiMatchState, visible: CGSize) -> some View {
        let side = GamesReversiBoardLayout.side(visible: visible, sideMargin: MobileTheme.sideMargin,
                                                isLargeText: typeSize >= .xLarge,
                                                isAccessibilitySize: typeSize.isAccessibilitySize)
        let interactive = !match.isFinished
        return GamesReversiBoard(
            store: reversi, matchID: match.id, board: match.board, side: side,
            legalTargets: interactive ? reversi.legalTargets : [],
            lastStoneIdx: match.lastStoneIdx, autoStones: match.autoStones,
            turn: match.isFinished ? nil : match.turn,
            onTap: interactive ? { idx in Task { await reversi.place(idx) } } : nil)
            .shadow(color: colorScheme == .dark ? .black.opacity(0.35) : Color.black.opacity(0.16), radius: 9, y: 6)
            // 내 차례 마지막 3초 — 판 안쪽 가장자리가 빨갛게 빛난다. 그림자 **뒤**에 얹는다(앞에 두면 5Hz 틱마다 그림자를 다시 굽는다).
            .overlay { GamesReversiBoardTimeWarning(store: reversi) }
            .sensoryFeedback(.impact(weight: .medium), trigger: match.moveCount)
            .frame(maxWidth: .infinity)
    }

    // MARK: 차례 · 안내 줄

    private func statusLines(match: ReversiMatchState, chrome: GamesReversiMatchChrome) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !match.isFinished {
                GamesReversiTurnLeaf(store: reversi)
            }
            if let line = chrome.detailLine {
                footLine(line.text, tint: GamesChessInk.color(line.tint), weight: .semibold)
            }
            if let line = chrome.autoPlacedLine {
                footLine(line, tint: MobileTheme.label2)
            }
            if let warning = chrome.autoStreakWarning {
                footLine(warning, tint: MobileTheme.danger, weight: .semibold)
            }
            if !match.isFinished {
                Label(chrome.clockLine, systemImage: chrome.isAI ? "pause.circle" : "clock")
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footLine(_ text: String, tint: Color, weight: Font.Weight = .regular) -> some View {
        Text(text)
            .font(.footnote.weight(weight))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 동작 막대

    private func actionBar(chrome: GamesReversiMatchChrome) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(MobileTheme.separator)
                .frame(height: MobileTheme.hairline)
            actionRow(chrome: chrome)
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.vertical, 10)
        }
        .background(MobileTheme.surface)
    }

    @ViewBuilder
    private func actionRow(chrome: GamesReversiMatchChrome) -> some View {
        switch chrome.actionRow {
        case .playing(let canResign):
            AingButton(ReversiPhoneText.resign, systemImage: "flag", kind: .destructive, size: .md,
                       fillsWidth: true, role: .destructive) {
                guard GomokuPhoneResignGuard.acceptsTap(shownAt: shownAt, now: reversi.clock()) else { return }
                confirmsResign = true
            }
            .disabled(!canResign)
        case .finished(let showsPlayAgain):
            // 두 버튼은 같은 글자 크기·높이 — 긴 [다시 두기]가 제 폭을 갖고 [로비로]가 남은 폭을 채운다. 한 줄에 안 들어가면 위아래로.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { lobbyButton; if showsPlayAgain { playAgainButton(fillsWidth: false).fixedSize() } }
                VStack(spacing: 10) { if showsPlayAgain { playAgainButton(fillsWidth: true) }; lobbyButton }
            }
        }
    }

    private var lobbyButton: some View {
        AingButton(ReversiPhoneText.backToLobby, kind: .gray, size: .md, fillsWidth: true) {
            reversi.backToLobby()
        }
    }

    /// 로봇 판의 "다시"는 같은 색의 새 로컬 판이다(맥 [다시 두기]와 같은 문 — 코어 `restartAIMatch`).
    private func playAgainButton(fillsWidth: Bool) -> some View {
        AingButton(ReversiPhoneText.aiRematch, systemImage: "arrow.clockwise", kind: .filled, size: .md,
                   fillsWidth: fillsWidth) {
            reversi.restartAIMatch()
        }
    }
}

// MARK: - 두 사람 카드

/// 플레이어 한 장: 캐릭터 초상(+ 돌 배지) · 이름(+ 센터 · '나') · 돌 수(+ 자동 n/3) · 오른쪽은 차례면 30초 링(로봇 차례면 "생각 중").
/// 차례인 카드만 초록 테두리.
struct GamesReversiPlayerCard: View {
    let store: ReversiStore
    let characterID: String?
    let mood: CharacterMood
    let name: String
    /// 센터 **화면 글자**(코어 `ReversiUser.center` 규약).
    let center: String?
    let isMe: Bool
    let color: ReversiColor
    let subtitle: String
    let isTurn: Bool
    let isAI: Bool
    let turnSeconds: Int

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous)
        HStack(spacing: MobileTheme.space3) {
            CharacterPortrait(id: characterID, mood: mood, size: 44, badge: .stone(isBlack: color == .black))
            VStack(alignment: .leading, spacing: 1) {
                PersonName(name, center: CenterLabel.serverValue(forDisplay: center), isMe: isMe)
                Text(subtitle)
                    .font(MobileTheme.rowSubtitle)
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .layoutPriority(1)
            Spacer(minLength: 4)
            if isTurn {
                // 로봇 차례에는 시계가 없다(마감이 없어 링이 0초로 빨갛게 선다) — "생각 중" 표시가 그 자리에 선다(맥과 같다).
                if isAI {
                    GamesReversiThinkingMark()
                        .frame(width: 44, height: 44)
                } else {
                    GamesReversiTurnRing(store: store, turnSeconds: turnSeconds)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(shape.fill(MobileTheme.surface))
        .overlay(shape.strokeBorder(isTurn ? MobileTheme.workingDot : Color.clear, lineWidth: 2))
    }
}

/// 차례인 사람의 30초 링(44pt) — **잎 뷰**. 남은 시간은 코어가 서버 마감으로 계산한다(`remainingSeconds(now:)`).
/// 로봇 판 사람 시계는 화면이 안 보이면 코어가 멈춘다(마감이 nil 이 되어 링이 비지 않게 — 멈춘 동안은 그리지 않는다).
struct GamesReversiTurnRing: View {
    let store: ReversiStore
    let turnSeconds: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !store.isWindowVisible)) { _ in
            let remaining = store.remainingSeconds(now: store.clock()) ?? Double(turnSeconds)
            let fraction = GamesReversiMatchChrome.ringFraction(remaining: remaining, turnSeconds: turnSeconds)
            let tint = GamesReversiMatchChrome.ringTint(remaining: remaining)
            ZStack {
                Circle().stroke(MobileTheme.fill, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(GamesChessInk.dot(tint), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(ReversiPhoneText.remaining(remaining))
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(GamesChessInk.color(tint))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .padding(2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ReversiPhoneText.clockAccessibility(remaining))
        }
    }
}

/// 로봇 차례에 링 자리(44pt)에 서는 "생각 중" 표시. 말줄임표가 차례로 밝아져 판이 멈춘 것처럼 보이지 않는다
/// (동작 줄이기를 켜면 멈춘 모양). 시계를 읽지 않는다.
struct GamesReversiThinkingMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(MobileTheme.accent.opacity(0.35), lineWidth: 4)
            VStack(spacing: 0) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                Text(ReversiPhoneText.aiThinkingShort)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(MobileTheme.accent)
        }
        .padding(2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ReversiPhoneText.aiThinking)
    }
}

/// 차례 한 줄(내 차례 · 상대 차례 · 생각 중 · 자동으로 놓이는 중). 마감+유예 판정이 시간에 달려 있어 잎 뷰다.
/// `now` 는 **스토어 시계**다 — 마감이 그 시계 축으로 보정돼 있다(`deviceDate(serverMs:)`).
struct GamesReversiTurnLeaf: View {
    let store: ReversiStore

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !store.isWindowVisible)) { _ in
            if let match = store.match {
                let line = GamesReversiMatchChrome.turnLine(match: match, now: store.clock(),
                                                            graceSeconds: store.graceSeconds,
                                                            isAIThinking: store.isAIThinking)
                Text(line.text)
                    .font(MobileTheme.rowTitle)
                    .foregroundStyle(GamesChessInk.color(line.tint))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - 수 기록

/// 수 기록 한 줄(가로 스크롤) + 머리의 돌 수. 세로 스크롤 안에 세로 스크롤을 두면 손가락이 둘 중 하나를 뺏긴다 — 수가 늘어나는 쪽은 가로다.
struct GamesReversiMoveList: View {
    let plies: [ReversiPly]
    let counts: ReversiCounts

    var body: some View {
        let chips = GamesReversiMoveLog.chips(plies)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(ReversiPhoneText.movesTitle)
                    .font(MobileTheme.chip)
                    .foregroundStyle(MobileTheme.label2)
                Spacer(minLength: 4)
                Text(ReversiPhoneText.counts(counts))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.label2)
            }
            if chips.isEmpty {
                Text(ReversiPhoneText.noMoves)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(chips) { chip in
                                moveChip(chip, isLast: chip.id == chips.last?.id)
                                    .id(chip.id)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: chips.last?.id) { _, last in
                        guard let last else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .trailing) }
                    }
                    .onAppear {
                        if let last = chips.last?.id { proxy.scrollTo(last, anchor: .trailing) }
                    }
                }
            }
        }
        .padding(.top, MobileTheme.space1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ReversiPhoneText.movesTitle + ", " + ReversiPhoneText.counts(counts))
    }

    private func moveChip(_ chip: GamesReversiMoveLog.Chip, isLast: Bool) -> some View {
        HStack(spacing: 3) {
            if let number = chip.number {
                Text("\(number).")
                    .font(MobileTheme.chip)
                    .foregroundStyle(MobileTheme.label3Text)
            }
            GamesReversiStoneDot(color: chip.color, size: 11)
            Text(chip.text)
                .font(MobileTheme.number(.footnote, weight: isLast ? .bold : .regular))
                .foregroundStyle(isLast ? MobileTheme.label : MobileTheme.label2)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isLast ? MobileTheme.accentTint : MobileTheme.fill))
    }
}

// MARK: - 결과 카드

/// 승/패/무 · 끝난 까닭 · 점수 줄 · 상대 줄 · 루비 변화(무승부는 ±0 + 환불 한 줄 · 로봇 판은 루비 없이 '기록 없음').
struct GamesReversiResultCard: View {
    let result: GamesReversiMatchChrome.Result
    let me: GamesMeIdentity
    let myColor: ReversiColor

    var body: some View {
        InsetGroup {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    portrait
                    texts
                    Spacer(minLength: 6)
                    if result.showsRubyDelta { rubyDelta }
                }
                // 큰 글자: 초상·루비 한 줄, 글은 그 아래 — 한 줄에 몰면 제목이 글자마다 꺾였다(오목 AX 실측).
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) { portrait; Spacer(minLength: 6); if result.showsRubyDelta { rubyDelta } }
                    texts
                }
            }
            .padding(MobileTheme.cardPadding)
        }
        .accessibilityElement(children: .combine)
    }

    private var portrait: some View {
        CharacterPortrait(id: me.characterID, mood: me.mood, size: 60, badge: .stone(isBlack: myColor == .black))
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(result.title)
                .font(MobileTheme.title(.title2))
                .foregroundStyle(GamesChessInk.color(result.tint))
                .fixedSize()
            Text(result.reason)
                .font(.subheadline)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
            Text(result.scoreLine)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label)
                .fixedSize(horizontal: false, vertical: true)
            Text(result.opponentLine)
                .font(.caption)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
            if let note = result.rubyNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rubyDelta: some View {
        HStack(spacing: 4) {
            RubyIcon(size: 24)
                .opacity(result.rubyDelta < 0 ? 0.5 : 1)
            Text(result.rubyDeltaText)
                .font(MobileTheme.number(.title2, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(result.rubyDelta > 0 ? MobileTheme.working
                                 : (result.rubyDelta < 0 ? MobileTheme.danger : MobileTheme.label))
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ReversiPhoneText.rubyDeltaAccessibility(result.rubyDeltaText))
    }
}

#endif
