@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 **아잉 뒤집기 판 화면 · 로봇 연습**(판 갈래 2/4 · 대표 답 #d_DdwzmxPClGqk). 폰 뷰는 맥 스위트가 못 보므로(`#if os(iOS)`)
// 돈이 갈리는 판정은 뷰 몸통이 아니라 순수 표(`GamesReversiMatchChrome` · `GamesReversiBoardGeometry` · `GamesReversiAIEntry` …)에 있고,
// 이 스위트가 그 표의 **결과**를 잰다. 결과 단언에는 **값 하나만 바꾼 기준선**을 나란히 둔다(같은 입력이면 영원히 초록이다).
//
// 재는 것:
//  ① 루비 3/5/10 — 승 +순이익 · 패 −판돈 · 무 ±0 + 환불 한 줄 · 로봇 판은 루비 없이 '기록 없음'
//  ② 끝난 까닭 여섯 갈래가 서로 다른 문장 · 자리 비움은 그 판의 서버 횟수 · 로봇 판 주어는 '로봇'
//  ③ 점수 줄(흑 : 백 고정 · 빈칸은 이긴 쪽 · 기권은 돌 수만) ④ 동작 줄 ⑤ 패스·안내 줄 ⑥ 자동 착수 줄(3회 패 경고)
//  ⑦ 차례 한 줄(마감 + 서버 유예 뒤 '자동으로 놓이는 중' · 로봇 판 제외) ⑧ 시계 규칙 한 줄(1:1 과 로봇 판이 정반대)
//  ⑨ 링 ⑩ 판 좌표·한 변 ⑪ 보이스오버(칸 이름 · 돌 수) ⑫ 수 기록 칩 ⑬ 로봇 입구·돌 색
//  ⑭ 로봇 판 시계 멈춤(앱을 내렸다 복귀 · 화면을 떠났다 복귀) ⑮ 한 칸 탭 → 요청 한 건 · 뒤집기 그림(화면이 보일 때만)

// MARK: - 도우미

private let rmRival = ReversiUser(id: "a0000000-0000-4000-8000-0000000000b2", displayName: "뒤집기라이벌",
                                  isWorking: true, inMatch: true)
private let rmNow = Date(timeIntervalSince1970: 1_791_200_000)

private func rmMatch(
    id: String = "a0000000-0000-4000-8000-0000000000f1", isAI: Bool = false, finished: Bool = false, stake: Int = 5,
    myColor: ReversiColor = .black, turn: ReversiColor? = .black, deadline: Date? = nil,
    plies: [ReversiPly] = [], autoStones: Set<Int> = [], counts: ReversiCounts? = nil, score: ReversiScore? = nil,
    result: ReversiResult? = nil, endReason: ReversiEndReason? = nil,
    myAutoStreak: Int = 0, opponentAutoStreak: Int = 0, autoAbandonStreak: Int = 3
) -> ReversiMatchState {
    ReversiMatchState(
        id: isAI ? "ai-test" : id, isAI: isAI, status: finished ? .finished : .active, stake: isAI ? 0 : stake,
        myColor: myColor, opponent: isAI ? .reversiAI : rmRival, board: .start, moveCount: plies.count,
        turn: finished ? nil : turn, deadline: deadline, plies: plies, autoStones: autoStones, counts: counts,
        score: score, result: finished ? result : nil, endReason: finished ? endReason : nil,
        myAutoStreak: myAutoStreak, opponentAutoStreak: opponentAutoStreak, autoAbandonStreak: autoAbandonStreak)
}

private func rmChrome(_ match: ReversiMatchState, notice: String? = nil, isBusy: Bool = false,
                      serverTurnSeconds: Int = 30) -> GamesReversiMatchChrome {
    GamesReversiMatchChrome(match: match, notice: notice, isBusy: isBusy, serverTurnSeconds: serverTurnSeconds)
}

private func rmStone(_ seq: Int, _ color: ReversiColor, _ coord: String, flipped: [Int] = [], auto: Bool = false) -> ReversiPly {
    ReversiPly(seq: seq, color: color, kind: .stone, idx: ReversiPoint(coord: coord)!.idx, flipped: flipped, auto: auto)
}

private func rmPass(_ seq: Int, _ color: ReversiColor) -> ReversiPly {
    ReversiPly(seq: seq, color: color, kind: .pass, idx: nil, flipped: [], auto: false)
}

// MARK: - 순수 표

@MainActor
@Suite struct GamesReversiMatchChromeTests {

    @Test("① 루비: 3/5/10 승 +순이익 · 패 −판돈 · 무 ±0 + 환불 한 줄 · 로봇 판은 루비 줄 없이 '기록 없음'(같은 결과 · 판 종류만 다른 기준선)")
    func rubyLines() throws {
        for stake in ReversiStake.allCases.map(\.rawValue) {
            let won = try #require(rmChrome(rmMatch(finished: true, stake: stake, result: .blackWin, endReason: .boardFull)).result)
            #expect(won.rubyDelta == DuelFee.winnerNet(stake: stake) && won.rubyDeltaText == "+\(stake)", "승 \(stake)")
            #expect(won.showsRubyDelta && won.rubyNote == nil && won.tint == .good && !won.isDraw)
            let lost = try #require(rmChrome(rmMatch(finished: true, stake: stake, result: .whiteWin, endReason: .resign)).result)
            #expect(lost.rubyDelta == -stake && lost.rubyDeltaText == "−\(stake)", "패 \(stake)")
            #expect(lost.tint == .bad && lost.rubyNote == nil)
            let draw = try #require(rmChrome(rmMatch(finished: true, stake: stake, result: .draw, endReason: .boardFull)).result)
            #expect(draw.rubyDelta == 0 && draw.rubyDeltaText == "±0" && draw.isDraw)
            #expect(draw.rubyNote == "판돈 \(stake) 루비를 돌려받았어요", "무승부 환불 한 줄이 판돈을 말하지 않는다")
        }
        // 내 색이 백이면 같은 결과(흑 승)가 **패**다 — 결과는 색 기준이고 루비는 내 기준이다.
        let whiteLost = try #require(rmChrome(rmMatch(finished: true, myColor: .white, result: .blackWin, endReason: .boardFull)).result)
        #expect(whiteLost.rubyDelta == -5 && whiteLost.title == "졌어요")
        // 로봇 판: 같은 결과인데 루비가 서지 않는다(±0 을 그리면 걸었다가 돌려받은 것처럼 읽힌다).
        let ai = try #require(rmChrome(rmMatch(isAI: true, finished: true, result: .blackWin, endReason: .boardFull)).result)
        #expect(!ai.showsRubyDelta && ai.rubyDelta == 0 && ai.rubyNote == ReversiPhoneText.aiNoRecord)
        #expect(ai.opponentLine == "상대 · 로봇")
        let aiDraw = try #require(rmChrome(rmMatch(isAI: true, finished: true, result: .draw, endReason: .boardFull)).result)
        #expect(aiDraw.rubyNote == ReversiPhoneText.aiNoRecord, "로봇 판 무승부가 환불을 말한다 — 걸린 루비가 없다")
        let human = try #require(rmChrome(rmMatch(finished: true, result: .blackWin, endReason: .boardFull)).result)
        #expect(human.showsRubyDelta && human.opponentLine == "상대 · 뒤집기라이벌", "기준선이 안 갈린다")
    }

    @Test("② 끝난 까닭: 여섯 갈래 × 승패가 서로 다른 문장 · 자리 비움은 판의 서버 횟수 · 로봇 판 주어는 '로봇'")
    func endReasons() throws {
        func reason(_ end: ReversiEndReason, won: Bool, isAI: Bool = false, streak: Int = 3) throws -> String {
            try #require(rmChrome(rmMatch(isAI: isAI, finished: true, result: won ? .blackWin : .whiteWin,
                                          endReason: end, autoAbandonStreak: streak)).result).reason
        }
        let lines = [
            try reason(.wipeout, won: true), try reason(.wipeout, won: false),
            try reason(.resign, won: true), try reason(.resign, won: false),
            try reason(.abandoned, won: true), try reason(.abandoned, won: false),
            try reason(.boardFull, won: true), try reason(.noMoves, won: true)
        ]
        #expect(Set(lines).count == lines.count, "끝난 까닭 두 갈래가 같은 문장이다: \(lines)")
        #expect(lines.allSatisfy { !$0.isEmpty })
        #expect(try reason(.resign, won: true) == "상대가 기권했어요")
        #expect(try reason(.resign, won: false) == "기권했어요")
        #expect(try reason(.abandoned, won: false) == "시간이 3번 이어서 지나 졌어요")
        // 횟수는 **그 판의 서버 값**이다(상수를 베끼지 않는다) — 값 하나만 바꾼 기준선.
        #expect(try reason(.abandoned, won: false, streak: 4) == "시간이 4번 이어서 지나 졌어요")
        #expect(try reason(.wipeout, won: true, isAI: true) == "로봇 돌을 모두 뒤집었어요")
        #expect(try reason(.wipeout, won: true) == "상대 돌을 모두 뒤집었어요")
        #expect(ReversiPhoneText.endReason(nil, outcome: .won, opponent: "상대", lossStreak: 3) == "")
    }

    @Test("③ 점수 줄: 흑 : 백 고정 · 빈칸이 있으면 판 위 돌 수를 함께 · 기권·자리 비움은 돌 수만")
    func scoreLines() throws {
        let full = rmMatch(finished: true, counts: ReversiCounts(black: 33, white: 31, empty: 0),
                           score: ReversiScore(black: 33, white: 31, result: .blackWin), result: .blackWin, endReason: .boardFull)
        #expect(GamesReversiMatchChrome.scoreLine(full) == "흑 : 백  33 : 31")
        let early = rmMatch(finished: true, counts: ReversiCounts(black: 30, white: 24, empty: 10),
                            score: ReversiScore(black: 40, white: 24, result: .blackWin), result: .blackWin, endReason: .noMoves)
        #expect(GamesReversiMatchChrome.scoreLine(early) == "흑 : 백  40 : 24 (판 위 30 : 24)")
        // 내 색이 백이어도 흑이 먼저다.
        let asWhite = rmMatch(finished: true, myColor: .white, counts: ReversiCounts(black: 30, white: 24, empty: 10),
                              score: ReversiScore(black: 40, white: 24, result: .blackWin), result: .blackWin, endReason: .noMoves)
        #expect(GamesReversiMatchChrome.scoreLine(asWhite) == GamesReversiMatchChrome.scoreLine(early))
        let resigned = rmMatch(finished: true, counts: ReversiCounts(black: 30, white: 24, empty: 10),
                               result: .whiteWin, endReason: .resign)
        #expect(GamesReversiMatchChrome.scoreLine(resigned) == "판 위 흑 30 : 백 24")
        #expect(try #require(rmChrome(early).result).scoreLine == "흑 : 백  40 : 24 (판 위 30 : 24)")
    }

    @Test("④ 동작 줄: 두는 중 [기권](왕복 중이면 잠김) · 끝난 판 [로비로] · 로봇 판만 [같은 색으로 다시 두기]")
    func actionRows() {
        #expect(rmChrome(rmMatch()).actionRow == .playing(canResign: true))
        #expect(rmChrome(rmMatch(), isBusy: true).actionRow == .playing(canResign: false))
        #expect(rmChrome(rmMatch(finished: true, result: .blackWin, endReason: .resign)).actionRow == .finished(showsPlayAgain: false))
        #expect(rmChrome(rmMatch(isAI: true, finished: true, result: .blackWin, endReason: .resign)).actionRow
                == .finished(showsPlayAgain: true))
        // 끝난 판에는 [기권]도 진행 중 줄도 없다.
        let finished = rmChrome(rmMatch(finished: true, result: .whiteWin, endReason: .abandoned, myAutoStreak: 2))
        #expect(finished.detailLine == nil && finished.autoStreakWarning == nil && finished.autoPlacedLine == nil)
        #expect(rmChrome(rmMatch()).resignConfirmTitle == "기권하면 건 루비를 잃어요")
        #expect(rmChrome(rmMatch(isAI: true)).resignConfirmTitle == "기권하면 이 판은 로봇이 이겨요")
        #expect(rmChrome(rmMatch(isAI: true)).resignConfirmMessage == ReversiPhoneText.aiNoRecord)
    }

    @Test("⑤ 둘째 줄: 안내가 먼저 · 없으면 방금 일어난 패스(상대 이름 · 내 패스) · 마지막이 돌이면 없음")
    func detailLines() {
        let opponentPassed = rmMatch(turn: .black, plies: [rmStone(1, .black, "d3"), rmPass(2, .white)])
        #expect(rmChrome(opponentPassed).detailLine == GamesChessMatchLine(
            text: "뒤집기라이벌님이 둘 곳이 없어 내 차례가 이어져요", tint: .quiet))
        let iPassed = rmMatch(turn: .white, plies: [rmStone(1, .black, "d3"), rmPass(2, .black)])
        #expect(rmChrome(iPassed).detailLine?.text == ReversiNoticeText.myPass)
        // 기준선: 마지막 기록이 돌이면 패스 줄이 없다.
        let stone = rmMatch(turn: .white, plies: [rmStone(1, .black, "d3")])
        #expect(rmChrome(stone).detailLine == nil)
        // 안내가 패스보다 먼저다(앰버).
        #expect(rmChrome(opponentPassed, notice: "보내는 중이에요").detailLine == GamesChessMatchLine(text: "보내는 중이에요", tint: .warn))
        // 로봇 판의 패스 주어는 '로봇'.
        let aiPassed = rmMatch(isAI: true, turn: .black, plies: [rmStone(1, .black, "d3"), rmPass(2, .white)])
        #expect(rmChrome(aiPassed).detailLine?.text == "로봇님이 둘 곳이 없어 내 차례가 이어져요")
    }

    @Test("⑥ 자동 착수: 한 번 더 놓치면 지는 순간에만 빨강 줄(서버 횟수 기준) · 회색 점 뜻 한 줄 · 카드 꼬리 '자동 n/3'")
    func autoLines() {
        #expect(rmChrome(rmMatch(myAutoStreak: 2)).autoStreakWarning == "한 번 더 시간이 지나면 져요")
        #expect(rmChrome(rmMatch(myAutoStreak: 1)).autoStreakWarning == nil, "두 번 남았는데 경고한다")
        #expect(rmChrome(rmMatch(myAutoStreak: 2, autoAbandonStreak: 4)).autoStreakWarning == nil, "서버 횟수를 안 본다")
        #expect(rmChrome(rmMatch(myAutoStreak: 3, autoAbandonStreak: 4)).autoStreakWarning != nil)
        #expect(rmChrome(rmMatch(opponentAutoStreak: 2)).autoStreakWarning == nil, "상대 횟수로 나를 경고한다")
        #expect(rmChrome(rmMatch(autoStones: [19, 26])).autoPlacedLine == "시간이 지나 자동으로 놓인 돌 2개 · 회색 점")
        #expect(rmChrome(rmMatch()).autoPlacedLine == nil)
        #expect(GamesReversiMatchChrome.cardSubtitle(color: .black, counts: ReversiCounts(black: 12, white: 9, empty: 43),
                                                     autoStreak: 1, limit: 3) == "흑 · 12개 · 자동 1/3")
        #expect(GamesReversiMatchChrome.cardSubtitle(color: .white, counts: ReversiCounts(black: 12, white: 9, empty: 43),
                                                     autoStreak: 0, limit: 3) == "백 · 9개")
    }

    @Test("⑦ 차례 한 줄: 마감 + 서버 유예가 지나야 '자동으로 놓이는 중'(바로 전은 아직 내 차례) · 로봇 판은 그 갈래가 없다")
    func turnLines() {
        let deadline = rmNow.addingTimeInterval(10)
        let mine = rmMatch(turn: .black, deadline: deadline)
        #expect(GamesReversiMatchChrome.turnLine(match: mine, now: rmNow, graceSeconds: 2, isAIThinking: false)
                == GamesChessMatchLine(text: "내 차례예요", tint: .good))
        #expect(GamesReversiMatchChrome.turnLine(match: mine, now: deadline.addingTimeInterval(1.9), graceSeconds: 2,
                                                 isAIThinking: false).text == "내 차례예요", "유예 안인데 정산 중이라 말한다")
        #expect(GamesReversiMatchChrome.turnLine(match: mine, now: deadline.addingTimeInterval(2), graceSeconds: 2,
                                                 isAIThinking: false) == GamesChessMatchLine(text: ReversiPhoneText.mySettling, tint: .warn))
        let theirs = rmMatch(turn: .white, deadline: deadline)
        #expect(GamesReversiMatchChrome.turnLine(match: theirs, now: rmNow, graceSeconds: 2, isAIThinking: false).text == "상대 차례예요")
        #expect(GamesReversiMatchChrome.turnLine(match: theirs, now: deadline.addingTimeInterval(3), graceSeconds: 2,
                                                 isAIThinking: false).text == ReversiPhoneText.opponentSettling)
        let ai = rmMatch(isAI: true, turn: .black, deadline: deadline)
        #expect(GamesReversiMatchChrome.turnLine(match: ai, now: deadline.addingTimeInterval(5), graceSeconds: 2,
                                                 isAIThinking: false).text == "내 차례예요", "로봇 판에 서버 정산 줄이 선다")
        let thinking = rmMatch(isAI: true, turn: .white)
        #expect(GamesReversiMatchChrome.turnLine(match: thinking, now: rmNow, graceSeconds: 2, isAIThinking: true).text
                == "로봇이 생각 중이에요")
        let done = rmMatch(finished: true, result: .blackWin, endReason: .resign)
        #expect(GamesReversiMatchChrome.turnLine(match: done, now: rmNow, graceSeconds: 2, isAIThinking: false)
                == GamesChessMatchLine(text: "이겼어요", tint: .good))
    }

    @Test("⑧ 시계 규칙 한 줄: 1:1 은 '앱을 나가도 흘러요' + 서버 숫자 · 로봇 판은 '떠나면 멈춰요' + 로컬 30초(서버 숫자를 안 쓴다)")
    func clockLines() {
        let human = rmChrome(rmMatch(autoAbandonStreak: 3), serverTurnSeconds: 20)
        #expect(human.clockLine == "앱을 나가도 차례 시간은 흘러요 · 한 수 20초가 지나면 자동으로 놓이고 3번 이어지면 져요")
        #expect(human.turnSeconds == 20)
        let ai = rmChrome(rmMatch(isAI: true), serverTurnSeconds: 20)
        #expect(ai.clockLine == "화면을 떠나거나 앱을 나가면 내 시계가 멈춰요 · 한 수 30초가 지나면 자동으로 놓이고 3번 이어지면 져요")
        #expect(ai.turnSeconds == Int(ReversiAIGame.turnSeconds))
        #expect(!ai.showsStake && ai.stakeSuffix == nil && ai.opponentName == "로봇")
        #expect(human.showsStake && human.stakeSuffix == " · 이기면 +5" && human.opponentName == "뒤집기라이벌")
        // 별명을 모르는 상대.
        var nameless = rmMatch()
        nameless.opponent = ReversiUser(id: rmRival.id, displayName: "  ")
        #expect(rmChrome(nameless).opponentName == "상대")
    }

    @Test("⑨ 30초 링: 채움은 남은 초 / 한 수 시간(0…1) · 색은 10초 앰버 · 5초 빨강")
    func ring() {
        #expect(GamesReversiMatchChrome.ringFraction(remaining: 15, turnSeconds: 30) == 0.5)
        #expect(GamesReversiMatchChrome.ringFraction(remaining: 45, turnSeconds: 30) == 1)
        #expect(GamesReversiMatchChrome.ringFraction(remaining: -3, turnSeconds: 30) == 0)
        #expect(GamesReversiMatchChrome.ringFraction(remaining: .nan, turnSeconds: 30) == 0)
        #expect(GamesReversiMatchChrome.ringTint(remaining: 10.5) == .good)
        #expect(GamesReversiMatchChrome.ringTint(remaining: 10) == .warn)
        #expect(GamesReversiMatchChrome.ringTint(remaining: 5) == .bad)
        #expect(ReversiPhoneText.remaining(4.2) == "5초" && ReversiPhoneText.clockAccessibility(0) == "남은 시간 0초")
    }
}

@MainActor
@Suite struct GamesReversiBoardTests {

    @Test("⑩ 좌표: 1행이 위 · a열이 왼쪽(방향 뒤집기 없음) · 판 밖은 nil · 64칸 왕복 · 한 변은 열 폭 안 8의 배수 · 큰 글자에서 줄어든다")
    func geometryAndSide() {
        let g = GamesReversiBoardGeometry(side: 320)
        #expect(g.cell == 40)
        #expect(g.idx(at: CGPoint(x: 1, y: 1)) == 0)
        #expect(g.idx(at: CGPoint(x: 319.9, y: 319.9)) == 63)
        #expect(g.idx(at: CGPoint(x: 141, y: 85)) == 19, "d3 은 (열 3, 행 2) — 내 색으로 판을 돌리면 이 칸이 바뀐다")
        #expect(g.idx(at: CGPoint(x: 320, y: 10)) == nil && g.idx(at: CGPoint(x: -0.5, y: 10)) == nil)
        #expect(g.idx(at: CGPoint(x: CGFloat.nan, y: 10)) == nil)
        for idx in 0..<64 { #expect(g.idx(at: g.center(idx: idx)) == idx) }
        #expect(GamesReversiBoardGeometry(side: 0).idx(at: .zero) == nil)

        let phone = CGSize(width: 402, height: 874)
        let plain = GamesReversiBoardLayout.side(visible: phone, sideMargin: 16, isLargeText: false, isAccessibilitySize: false)
        #expect(plain == 368, "기본 글자는 열 폭(370)을 8 의 배수로 내린 값")
        let short = CGSize(width: 402, height: 500)
        #expect(GamesReversiBoardLayout.side(visible: short, sideMargin: 16, isLargeText: false, isAccessibilitySize: false) == 368,
                "기본 글자에서 높이로 줄였다(기준선)")
        #expect(GamesReversiBoardLayout.side(visible: short, sideMargin: 16, isLargeText: true, isAccessibilitySize: false) == 256)
        #expect(GamesReversiBoardLayout.side(visible: short, sideMargin: 16, isLargeText: true, isAccessibilitySize: true) == 200)
        #expect(GamesReversiBoardLayout.side(visible: .zero, sideMargin: 16, isLargeText: false, isAccessibilitySize: false)
                == GamesReversiBoardLayout.minimumSide)
        for width in stride(from: 120, through: 1_000, by: 7) {
            let size = CGSize(width: CGFloat(width), height: 700)
            for large in [false, true] {
                let side = GamesReversiBoardLayout.side(visible: size, sideMargin: 16, isLargeText: large, isAccessibilitySize: large)
                #expect(side <= max(8, CGFloat(width) - 32), "판(\(side))이 열(\(width - 32))보다 넓다 — 같은 열의 카드가 넘친다")
                #expect(side.truncatingRemainder(dividingBy: 8) == 0)
            }
        }
    }

    @Test("⑪ 보이스오버: 칸 이름이 먼저 · 돌 색 · 둘 수 있는 빈칸 · 마지막 수 · 자동 돌 · 판 한 줄에 돌 수 · 차례 · 둘 곳 수")
    func accessibility() {
        let board = ReversiBoard.start
        let legal: Set<Int> = [19, 26, 37, 44]
        #expect(GamesReversiBoardCells.label(idx: 19, board: board, legalTargets: legal, lastStoneIdx: nil, autoStones: [])
                == "d3, 빈칸, 둘 수 있어요")
        #expect(GamesReversiBoardCells.label(idx: 19, board: board, legalTargets: [], lastStoneIdx: nil, autoStones: [])
                == "d3, 빈칸", "둘 수 없는 칸을 둘 수 있다고 읽는다(기준선)")
        #expect(GamesReversiBoardCells.label(idx: 27, board: board, legalTargets: legal, lastStoneIdx: nil, autoStones: [])
                == "d4, 백 돌")
        #expect(GamesReversiBoardCells.label(idx: 28, board: board, legalTargets: legal, lastStoneIdx: 28, autoStones: [28])
                == "e4, 흑 돌, 마지막 수, 자동으로 놓임")
        #expect(GamesReversiBoardCells.label(idx: 0, board: board, legalTargets: legal, lastStoneIdx: nil, autoStones: []) == "a1, 빈칸")
        #expect(GamesReversiBoardCells.label(idx: 63, board: board, legalTargets: legal, lastStoneIdx: nil, autoStones: []) == "h8, 빈칸")
        // 64칸 이름이 전부 다르다(칸을 훑는 사람은 이름으로 찾는다).
        let names = (0..<64).map { ReversiPhoneText.coordinate($0) }
        #expect(Set(names).count == 64)
        #expect(ReversiPhoneText.boardAccessibility(counts: board.counts, turn: .black, legalCount: 4)
                == "아잉 뒤집기 판, 흑 2 · 백 2 · 빈칸 60, 흑 차례, 둘 수 있는 칸 4곳")
        #expect(ReversiPhoneText.boardAccessibility(counts: board.counts, turn: nil, legalCount: 0) == "아잉 뒤집기 판, 흑 2 · 백 2 · 빈칸 60")
    }

    @Test("⑫ 수 기록 칩: 색으로 짝 — 흑이 줄을 열고 백이 닫는다 · 패스도 한 칸 · 중간 합류(백부터)도 1번 · 자동 꼬리")
    func moveChips() {
        let plies = [rmStone(1, .black, "d3"), rmStone(2, .white, "c3", auto: true), rmPass(3, .black),
                     rmStone(4, .white, "c5"), rmStone(5, .black, "f5")]
        let chips = GamesReversiMoveLog.chips(plies.shuffled())
        #expect(chips.map(\.id) == [1, 2, 3, 4, 5], "seq 순이 아니다")
        #expect(chips.map(\.number) == [1, nil, 2, nil, 3])
        #expect(chips.map(\.text) == ["d3", "c3 · 자동", "넘김", "c5", "f5"])
        #expect(chips[2].isPass && chips[1].isAuto && !chips[0].isAuto)
        // 중간 합류: 백부터 오면 그 칩이 줄을 연다 · 백이 연달아 오면(기록 구멍) 줄이 따로 선다.
        let joined = GamesReversiMoveLog.chips([rmStone(7, .white, "c5"), rmStone(8, .white, "c6"), rmStone(9, .black, "f6")])
        #expect(joined.map(\.number) == [1, 2, 3])
        #expect(GamesReversiMoveLog.chips([]).isEmpty)
    }
}

@MainActor
@Suite struct GamesReversiAIEntryTests {

    @Test("⑬ 돌 색: 흑 · 백 · 무작위(무작위는 코어가 고른다 — 화면이 주사위를 굴리지 않는다) · 입구 막힘은 까닭으로 갈린다")
    func colorsAndEntry() async {
        #expect(GamesReversiAIColorChoice.allCases.map(\.humanColor) == [.black, .white, nil])
        #expect(Set(GamesReversiAIColorChoice.allCases.map(\.title)).count == 3)

        let store = ReversiStore(clock: { rmNow })
        store.aiMoveChooser = { _, _ in nil }
        store.aiRuntime.randomIndex = { _ in 1 }
        store.startAIMatch(humanColor: GamesReversiAIColorChoice.random.humanColor)
        #expect(store.match?.myColor == .white, "무작위를 코어에 안 맡겼다")
        await store.resign()
        store.backToLobby()
        store.aiRuntime.randomIndex = { _ in 0 }
        store.startAIMatch(humanColor: GamesReversiAIColorChoice.random.humanColor)
        #expect(store.match?.myColor == .black, "기준선이 안 갈린다")
        await store.resign()
        store.backToLobby()

        // 열려 있다 — 까닭 없음 · 무엇을 하는 곳인지 말한다.
        #expect(GamesReversiAIEntry(store: store).canStart && GamesReversiAIEntry(store: store).block == nil)
        #expect(GamesReversiAIEntry(store: store).caption == ReversiPhoneText.aiButtonHelp)
        // 보낸 신청 → 취소하면 풀린다(판과 다른 말).
        store.outgoing = ReversiOutgoing(id: "o-1", peer: rmRival, stake: 5, expiresAt: rmNow.addingTimeInterval(60))
        #expect(GamesReversiAIEntry(store: store).block == .outgoingInvite)
        #expect(GamesReversiAIEntry(store: store).caption == "보낸 신청을 취소하면 연습할 수 있어요")
        // 판이 섰다(서버가 말한 판 id 만 알아도) → 판이 이긴다.
        store.activeMatchID = "a0000000-0000-4000-8000-0000000000f1"
        #expect(GamesReversiAIEntry(store: store).block == .playing)
        store.outgoing = nil
        store.activeMatchID = nil
        store.isBusy = true
        #expect(GamesReversiAIEntry(store: store).block == .busy)
        store.isBusy = false
        #expect(GamesReversiAIEntry(store: store).block == nil)
        #expect(Set(ReversiPhoneText.AIBlock.allCases.map(ReversiPhoneText.aiBlock)).count == 3)
    }
}

// MARK: - 앱 배선 위에서 (요청 건수 · 시계 값)

@MainActor
@Suite(.serialized) struct GamesReversiMatchFlowTests {
    private let waits = GamesWaitBudget()

    @Test("⑭ 로봇 판 시계: 앱을 내리면 멈추고(남은 초 보존) 돌아오면 이어 간다 · 화면을 떠나도 멈춘다 · 멈춤 없이 같은 시간이 흐른 기준선은 자동 착수")
    func aiClockPausesWithTheScreen() async {
        let harness = ReversiWireHarness(label: "reversi-ai-clock")
        harness.serve()
        await harness.signIn()
        harness.games.reversiScreenDidAppear()
        harness.reversi.startAIMatch(humanColor: .black)
        #expect(harness.reversi.isAIMatch && harness.reversi.match?.isMyTurn == true)
        #expect(harness.reversi.match?.deadline != nil, "화면이 보이는데 사람 시계가 안 돈다")
        harness.clock.advance(10)
        #expect(harness.reversi.remainingSeconds(now: harness.clock.now).map { Int($0.rounded()) } == 20)

        // 앱을 내렸다 — 가림이라 사람 시계가 멈춘다. 60초가 흘러도 자동 착수가 없다.
        harness.games.appDidEnterBackground()
        #expect(harness.reversi.match?.deadline == nil, "앱을 내렸는데 사람 시계가 돈다")
        harness.clock.advance(60)
        harness.reversi.handleAIClock(now: harness.clock.now)
        #expect(harness.reversi.match?.moveCount == 0 && harness.reversi.match?.myAutoStreak == 0, "멈춘 시계로 자동 착수했다")
        harness.games.appDidBecomeActive()
        #expect(harness.reversi.remainingSeconds(now: harness.clock.now).map { Int($0.rounded()) } == 20,
                "돌아왔는데 남은 초가 보존되지 않았다")

        // 화면을 떠났다 — 멈춘다. 돌아오면 이어 간다.
        harness.games.reversiScreenDidDisappear()
        #expect(harness.reversi.match?.deadline == nil, "화면을 떠났는데 사람 시계가 돈다")
        #expect(harness.reversi.isAIMatch, "화면을 떠났더니 진행 중인 연습 판이 사라졌다(닫기는 기권이 아니다)")
        harness.clock.advance(60)
        harness.games.reversiScreenDidAppear()
        #expect(harness.reversi.remainingSeconds(now: harness.clock.now).map { Int($0.rounded()) } == 20)

        // 기준선: 보이는 채로 같은 시간이 흐르면 코어가 대신 둔다(연속 1회).
        harness.clock.advance(21)
        harness.reversi.handleAIClock(now: harness.clock.now)
        #expect(harness.reversi.match?.myAutoStreak == 1 && harness.reversi.notice == ReversiNoticeText.autoPlaced,
                "기준선이 안 갈린다 — 멈춤을 재는 단언이 아무것도 증명하지 않는다")
        await harness.tearDown()
    }

    @Test("⑮ 한 칸 탭: 둘 수 있는 칸은 착수 요청 한 건(기대 수 번호 · 칸) · 못 두는 칸은 0건 + 까닭 · 뒤집기 그림은 화면이 보일 때만(앱을 내린 기준선은 없음)")
    func tapPlacesAndFlips() async throws {
        let outcome = try ReversiRules.play(.start, color: .black, idx: 19).get()
        for visible in [true, false] {
            let harness = ReversiWireHarness(label: "reversi-tap-\(visible)")
            harness.serve()
            await harness.signIn()
            harness.games.reversiScreenDidAppear()
            await harness.loadMatch(owned: true)
            #expect(harness.reversi.legalTargets == [19, 26, 37, 44])
            if !visible { harness.games.appDidEnterBackground() }

            // 못 두는 칸(이미 돌 · 뒤집을 돌 없음)은 요청이 없다 — 판이 조용히 삼키지도 않는다(코어가 까닭을 말한다).
            await harness.reversi.place(27)
            #expect(harness.count("reversi_move") == 0)
            #expect(harness.reversi.notice == ReversiNoticeText.occupied)
            await harness.reversi.place(0)
            #expect(harness.count("reversi_move") == 0 && harness.reversi.notice == ReversiNoticeText.noFlip)

            harness.server.setDefault("reversi_move", json: Self.moveResponse(
                nowMs: harness.nowMs, board: outcome.board.string, flipped: outcome.flipped))
            await harness.reversi.place(19)
            let moves = harness.server.requests("reversi_move")
            #expect(moves.count == 1, "한 번 눌렀는데 \(moves.count)건 나갔다")
            let body = moves.first.flatMap { try? JSONSerialization.jsonObject(with: Data($0.bodyText.utf8)) as? [String: Any] }
            #expect(body?["p_idx"] as? Int == 19 && body?["p_expected_seq"] as? Int == 0)
            #expect(harness.reversi.match?.moveCount == 1 && harness.reversi.match?.board[19] == .black)
            if visible {
                #expect(harness.reversi.flip?.matchID == ReversiWireHarness.matchID, "화면이 보이는데 돌이 순간이동한다")
                #expect(harness.reversi.flip?.placedIdx == 19 && harness.reversi.flip?.flipped == outcome.flipped)
            } else {
                #expect(harness.reversi.flip == nil, "앱을 내렸는데 뒤집기 그림을 깨운다(기준선)")
            }
            await harness.tearDown()
        }
    }

    /// 착수 응답(내가 흑으로 d3 — 다음은 백 차례).
    private static func moveResponse(nowMs: Int, board: String, flipped: [Int]) -> String {
        let me = ReversiWireHarness.userID, rival = ReversiWireHarness.rival
        let match = #"{"id":"\#(ReversiWireHarness.matchID)","status":"active","stake":5,"challenger":"\#(rival)","opponent":"\#(me)","black":"\#(me)","white":"\#(rival)","move_count":1,"turn":"white","turn_started_ms":\#(nowMs),"deadline_ms":\#(nowMs + 30_000),"invite_expires_ms":null,"started_ms":\#(nowMs - 1_000),"finished_ms":null,"result":null,"end_reason":null,"winner":null,"board":"\#(board)","discs":{"black":4,"white":1,"empty":59},"score":null}"#
        let flips = flipped.map(String.init).joined(separator: ",")
        let moves = #"[{"seq":1,"color":"black","kind":"stone","idx":19,"flipped":[\#(flips)],"auto":false,"at_ms":\#(nowMs)}]"#
        return #"{"status":"ok","state":{"match":\#(match),"moves":\#(moves),"black_user":\#(ReversiWireJSON.player(me, "나")),"white_user":\#(ReversiWireJSON.player(rival, "뒤집기라이벌")),"opponent":\#(ReversiWireJSON.player(rival, "뒤집기라이벌")),"my_color":"black","legal_moves":[],"black_auto_streak":0,"white_auto_streak":0,"my_auto_streak":0,"opponent_auto_streak":0,"auto_abandon_streak":3,"turn_seconds":30,"grace_ms":2000,"ruby_balance":95,"watchers":0,"server_now_ms":\#(nowMs)},"ruby_balance":95,"server_now_ms":\#(nowMs)}"#
    }
}
