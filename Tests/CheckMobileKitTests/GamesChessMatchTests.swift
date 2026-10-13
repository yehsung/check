@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1:1 체스 **대국 화면**(`GamesChessMatch.swift`). 폰 뷰는 맥 스위트가 못 보므로(CheckMobileKit 의 절반이
// `#if os(iOS)`) **돈이 갈리는 판정은 뷰 몸통이 아니라 순수 표**(`GamesChessMatchChrome`)에 있고, 이 스위트가 그
// 표의 **결과**를 잰다(모양이 아니라 결과 — 직전 작업에서 기존 24건이 전부 초록인 채로 금지된 상태가 살아 있었다).
//
// 재는 것 다섯:
//  ① `timeout`(패) 과 `timeout_insufficient`(FIDE 6.9 무승부)가 **서로 다른 결과**를 그린다 — 뒤는 무승부이고
//     판돈을 **돌려받는다**고 말한다. 두 사유를 접는 뮤테이션은 빨개져야 한다(열 사유 전부 서로 달라야 한다).
//  ② 깃발+유예 판정이 **행별 잔량**(`white_grace_ms`/`black_grace_ms`)으로 간다 — 로비의 전역 `grace_ms`(2초)를
//     쓰는 뮤테이션은 빨개져야 한다(두 기준선은 **예산 하나만** 다르다).
//  ③ 승격은 **도착 칸이 같은 합법 수가 넷일 때만** 묻는다(코어가 판정한다 — 화면은 그 칸을 읽는다).
//  ④ 시계를 **폰이 세지 않는다** — 시간이 흘러 글자는 바뀌지만 서버가 준 네 칸은 바이트까지 그대로다.
//  ⑤ 동작 줄: 무승부 제안을 받은 판은 [수락]/[거절] 이 서고, 끝난 판에는 [기권]·[무승부 제안]이 없다.

// MARK: - 도우미

private let cmPeer = ChessUser(
    id: "00000000-0000-0000-0000-0000000000cc", displayName: "민수", avatarURL: nil,
    characterID: "fox", isWorking: true, isCapable: true, inMatch: true, center: "seoul")

private let cmStandardFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
private let cmNow = Date(timeIntervalSince1970: 1_791_200_000)

/// 판 한 판. 기본은 **진행 중 · 내(백) 차례 · 멈춘 시계**다(시계·사유는 시험마다 갈아 넣는다).
private func cmMatch(
    stake: Int = 5,
    myColor: ChessColor = .white,
    turn: ChessColor? = .white,
    fen: String = cmStandardFEN,
    readableBoard: Bool = true,
    plyCount: Int = 10,
    moves: [ChessMoveRecord] = [],
    clock: ChessServerClock = .initial,
    isInCheck: Bool = false,
    legalMoves: [ChessMove] = [],
    isFinished: Bool = false,
    outcome: ChessMatchOutcome? = nil,
    endReason: ChessEndReason? = nil,
    rubyDelta: Int? = nil,
    drawOfferBy: String? = nil,
    drawOfferedByMe: Bool = false,
    whiteGraceMs: Int? = nil,
    blackGraceMs: Int? = nil
) -> ChessMatchState {
    ChessMatchState(
        id: "match-chess-1", stake: stake, myColor: myColor, opponent: cmPeer, fen: fen,
        position: readableBoard ? ChessPosition(fen: fen) : nil, plyCount: plyCount,
        turn: isFinished ? nil : turn, lastMove: nil, moves: moves, clock: clock,
        isInCheck: isInCheck, legalMoves: legalMoves, isFinished: isFinished, outcome: outcome,
        endReason: endReason, rubyDelta: rubyDelta, drawOfferBy: drawOfferBy,
        drawOfferedByMe: drawOfferedByMe, whiteGraceMs: whiteGraceMs, blackGraceMs: blackGraceMs)
}

private func cmChrome(_ match: ChessMatchState, promotion: ChessPromotionPrompt? = nil,
                      notice: String? = nil, isBusy: Bool = false,
                      isRobotMatch: Bool = false,
                      initialMs: Int = ChessClock.initialMs) -> GamesChessMatchChrome {
    GamesChessMatchChrome(match: match, promotion: promotion, notice: notice, isBusy: isBusy,
                          isRobotMatch: isRobotMatch, initialMs: initialMs)
}

private func cmSquare(_ notation: String) -> ChessSquare {
    ChessSquare(notation)!
}

@MainActor
private func cmStore(match: ChessMatchState) -> ChessStore {
    let store = ChessStore()
    store.clock = { cmNow }
    store.phase = .playing
    store.match = match
    return store
}

// MARK: - 스위트

@MainActor
@Suite(.serialized) struct GamesChessMatchTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let viewPath = "Sources/CheckMobileKit/Games/GamesChessMatch.swift"

    // MARK: ① FIDE 6.9 — timeout 과 timeout_insufficient

    @Test("★ 깃발 패배와 FIDE 6.9 무승부가 다른 결과를 그린다 — 뒤는 무승부이고 판돈을 돌려받는다")
    func timeoutVersusTimeoutInsufficient() throws {
        // ★ 기준선을 한 축만 갈라 둔다(데모 픽스처 `demo-chess-flagloss` ↔ `demo-chess-flagdraw` 와 같은 짝):
        //   같은 쪽 · 같은 남은 시간(1,000ms) · 같은 경과 · 같은 판돈 · 같은 수 번호이고 **사유와 결과만** 다르다.
        //   입력이 같은 기준선이면 그 시험은 아무것도 증명하지 않는다.
        let frozen = ChessServerClock(whiteMsLeft: 1_000, blackMsLeft: 240_000, incrementMs: 3_000,
                                      turnStartedAt: cmNow.addingTimeInterval(-9), running: nil)
        let lost = cmMatch(plyCount: 40, clock: frozen, isFinished: true, outcome: .lost,
                           endReason: .timeout, rubyDelta: -5)
        let drawn = cmMatch(plyCount: 40, clock: frozen, isFinished: true, outcome: .draw,
                            endReason: .timeoutInsufficient, rubyDelta: 0)
        #expect(lost.clock == drawn.clock && lost.plyCount == drawn.plyCount && lost.stake == drawn.stake,
                "전제: 두 판은 사유·결과 말고 전부 같다")
        let loss = try #require(cmChrome(lost).result)
        let draw = try #require(cmChrome(drawn).result)

        // 제목이 갈린다: 졌다 vs 무승부.
        #expect(loss.title == "졌어요")
        #expect(draw.title == "무승부예요")
        #expect(draw.isDraw && !loss.isDraw)

        // ★ 사유 문장이 **갈린다**. 두 사유를 한 갈래로 접으면 이 줄이 같아져 빨개진다.
        #expect(loss.reason != draw.reason, "깃발 패배와 FIDE 6.9 무승부가 같은 말을 한다 — 돈이 틀린다")
        #expect(loss.reason == "시간이 다 됐어요")
        #expect(draw.reason.contains("무승부"), "무승부인데 무승부라고 말하지 않는다: \(draw.reason)")
        #expect(draw.reason.contains("기물"), "왜 무승부인지(메이트 재료가 없다) 말하지 않는다")

        // 루비: 패배는 판돈만큼 빠지고, 무승부는 **돌려받는다**(서버 `grant:chess:refund:`).
        #expect(loss.rubyDelta == -5 && loss.rubyDeltaText == "−5")
        #expect(draw.rubyDelta == 0 && draw.rubyDeltaText == "±0")
        #expect(loss.rubyNote == nil)
        #expect(draw.rubyNote == "판돈 5 루비를 돌려받았어요", "무승부 ±0 만 그리면 잃은 것으로 읽힌다")
        #expect(loss.showsRubyDelta && draw.showsRubyDelta)
    }

    @Test("★ 사유 열 갈래가 결과마다 서로 다른 문장이다 — 어느 둘을 접어도 빨개진다")
    func everyEndReasonSpeaksForItself() throws {
        #expect(ChessEndReason.allCases.count == 10)
        for outcome in [ChessMatchOutcome.won, .lost, .draw] {
            var seen: [String: ChessEndReason] = [:]
            for reason in ChessEndReason.allCases {
                let match = cmMatch(isFinished: true, outcome: outcome, endReason: reason)
                let result = try #require(cmChrome(match).result)
                #expect(!result.reason.isEmpty, "\(reason) 사유가 빈 줄이다(default 갈래로 접혔다)")
                if let clash = seen[result.reason] {
                    Issue.record("\(outcome) 에서 \(reason) 와 \(clash) 가 같은 문장을 쓴다: \(result.reason)")
                }
                seen[result.reason] = reason
            }
            #expect(seen.count == 10, "\(outcome) 에서 사유 문장이 \(seen.count) 가지뿐이다")
        }
    }

    @Test("무승부 사유 여섯은 환불을 말하고, 승패 사유 넷은 말하지 않는다(서버 CHECK 의 집합과 같다)")
    func drawReasonsSayRefund() throws {
        for reason in ChessEndReason.allCases {
            let outcome: ChessMatchOutcome = reason.isDraw ? .draw : .lost
            let result = try #require(cmChrome(cmMatch(isFinished: true, outcome: outcome,
                                                       endReason: reason)).result)
            if reason.isDraw {
                #expect(result.isDraw, "\(reason) 는 무승부 사유인데 무승부로 그리지 않는다")
                #expect(result.rubyDelta == 0)
                #expect(result.rubyNote == "판돈 5 루비를 돌려받았어요", "\(reason) 가 환불을 말하지 않는다")
            } else {
                #expect(!result.isDraw)
                #expect(result.rubyDelta == -5)
                #expect(result.rubyNote == nil, "\(reason) 가 환불을 말한다")
            }
        }
        #expect(ChessEndReason.allCases.filter(\.isDraw).count == 6)
    }

    @Test("승리는 판돈만큼 는다 · 서버가 말한 루비 변화가 있으면 그것을 쓴다")
    func rubyDeltaPrefersServerValue() throws {
        let won = try #require(cmChrome(cmMatch(isFinished: true, outcome: .won, endReason: .checkmate)).result)
        #expect(won.rubyDelta == 5 && won.rubyDeltaText == "+5")
        #expect(won.reason == ChessPhoneText.endReason(.checkmate, outcome: .won))
        #expect(won.reason == "체크메이트로 이겼어요")
        // 서버가 다른 값을 말하면(환불·보정) 그 값이 이긴다 — 앱이 다시 세지 않는다.
        let patched = try #require(cmChrome(cmMatch(isFinished: true, outcome: .won, endReason: .timeout,
                                                    rubyDelta: 3)).result)
        #expect(patched.rubyDelta == 3 && patched.rubyDeltaText == "+3")
        #expect(patched.reason == "상대 시간이 다 됐어요")
        #expect(patched.reason == ChessPhoneText.endReason(.timeout, outcome: .won))
    }

    @Test("로봇 판 결과는 루비를 안 그리고 기록이 안 남는다고 말한다")
    func robotResultHasNoRuby() throws {
        let result = try #require(cmChrome(cmMatch(isFinished: true, outcome: .won, endReason: .checkmate),
                                           isRobotMatch: true).result)
        #expect(!result.showsRubyDelta, "±0·+5 를 그리면 걸었다가 돌려받은 것처럼 읽힌다")
        #expect(result.rubyNote == ChessPhoneText.robotNoRecord)
        #expect(result.rubyNote == "루비·전적·순위에 들어가지 않아요")
    }

    @Test("★ 로봇 판 사유는 다른 표를 쓴다 — '상대'·루비 어휘가 없고 사람 판과 문장이 갈린다")
    func robotEndReasonsNeverSayOpponentOrRuby() throws {
        var differed = 0
        for reason in ChessEndReason.allCases {
            for outcome in [ChessMatchOutcome.won, .lost, .draw] {
                let match = cmMatch(isFinished: true, outcome: outcome, endReason: reason)
                let robot = try #require(cmChrome(match, isRobotMatch: true).result)
                let human = try #require(cmChrome(match).result)
                #expect(!robot.reason.contains("상대"), "로봇 판이 \(reason) 를 '상대' 로 말한다: \(robot.reason)")
                #expect(!robot.reason.contains("루비"))
                #expect(!robot.reason.isEmpty)
                if robot.reason != human.reason { differed += 1 }
            }
        }
        // 두 표가 **실제로 갈린다**(한쪽을 다른 쪽으로 돌려 놓으면 이 수가 0 이 되어 빨개진다).
        #expect(differed == 3, """
            로봇 표와 사람 표가 갈리는 칸 수가 바뀌었다(기대 3 · 실제 \(differed)).
            갈리는 자리는 **주어가 사람인 셋**이다: 기권·시간패·판 닫힘의 '이김' 칸("상대가…" → "로봇이…").
            0 이면 같은 표를 두 번 쓰는 것이고, 늘었다면 무승부 사유 가운데 하나가 로봇 판에서 다른 말을
            하게 된 것이다 — 어느 쪽이든 읽고 결정할 일이다.
            """)
        // 사람 판은 그 자리에서 '상대' 를 말한다(대조군 — 금지 검사가 공허하지 않다).
        let human = try #require(cmChrome(cmMatch(isFinished: true, outcome: .won, endReason: .resign)).result)
        #expect(human.reason == "상대가 기권했어요")
    }

    @Test("★ 시간 규칙 줄은 서버가 준 값에서 조립된다(10분이 박혀 있지 않다)")
    func clockLineComesFromTheServerValues() {
        let tenMinutes = cmChrome(cmMatch(clock: .initial), initialMs: 600_000)
        #expect(tenMinutes.clockLine == "10분 + 한 수 3초 · 앱을 나가도 차례 시간은 흘러요")
        // 서버가 5분·2초로 되돌아가면 화면도 **따라간다** — 상수를 베꼈으면 10분이 그대로 나온다.
        let fiveMinutes = cmChrome(
            cmMatch(clock: ChessServerClock(whiteMsLeft: 300_000, blackMsLeft: 300_000, incrementMs: 2_000,
                                            turnStartedAt: nil, running: nil)),
            initialMs: 300_000)
        #expect(fiveMinutes.clockLine == "5분 + 한 수 2초 · 앱을 나가도 차례 시간은 흘러요")
        #expect(tenMinutes.clockLine != fiveMinutes.clockLine)
        // 가산은 **이 판의 행**에서 온다(로비 값이 아니다 — 판이 시작된 뒤 로비 상수가 바뀌어도 판은 그대로다).
        let mixed = cmChrome(
            cmMatch(clock: ChessServerClock(whiteMsLeft: 600_000, blackMsLeft: 600_000, incrementMs: 5_000,
                                            turnStartedAt: nil, running: nil)),
            initialMs: 600_000)
        #expect(mixed.clockLine == "10분 + 한 수 5초 · 앱을 나가도 차례 시간은 흘러요")
        // 코어 기본값과도 맞는다(로비를 아직 못 읽었을 때 — 서버가 10분이다).
        #expect(ChessClock.initialMs == 600_000)
        #expect(cmChrome(cmMatch()).clockLine == tenMinutes.clockLine)
    }

    @Test("사유를 모르면 빈칸이 아니라 한 줄이 선다")
    func unknownEndReasonIsNeverBlank() throws {
        let result = try #require(cmChrome(cmMatch(isFinished: true, outcome: nil, endReason: nil)).result)
        #expect(result.reason == ChessPhoneText.unknownEndReason(nil))
        #expect(result.reason == "판이 끝났어요", "사유 자리가 빈칸이다 — 왜 끝났는지 못 묻는다")
        #expect(result.title == "대국이 끝났어요")
        #expect(result.reason != result.title, "제목과 사유가 같은 말이면 한 줄이 공허하다")
    }

    // MARK: ② 유예는 판·사람당 1회 예산

    @Test("★ 깃발+유예 판정은 행별 잔량으로 간다 — 전역 2초를 쓰면 예산 0 인 판을 못 본다")
    func flagOverdueUsesPerRowGraceBudget() throws {
        // 상대(백) 차례 · 남은 1.0초 · 흐른 2.5초 → **초과 1.5초**. 서버 규칙은 `초과 > 남은 예산` 이다.
        let turnStarted = cmNow.addingTimeInterval(-2.5)
        let clock = ChessServerClock(whiteMsLeft: 1_000, blackMsLeft: 300_000, incrementMs: 3_000,
                                     turnStartedAt: turnStarted, running: .white)
        let budgeted = cmMatch(myColor: .black, turn: .white, clock: clock, whiteGraceMs: 2_000)
        let spent = cmMatch(myColor: .black, turn: .white, clock: clock, whiteGraceMs: 0)

        // 전제: 두 판의 시계는 **바이트까지 같고**, 갈림은 예산 하나뿐이다(기준선이 한 축만 다르다).
        #expect(budgeted.clock == spent.clock)
        #expect(abs(budgeted.clock.rawRemainingSeconds(.white, now: cmNow) + 1.5) < 0.001,
                "전제: 초과분이 1.5초다")
        #expect(budgeted.graceSecondsLeft(.white) == 2.0 && spent.graceSecondsLeft(.white) == 0)

        // 전역 유예(로비 `grace_ms` = 2초)를 **폴백으로 같이 넘긴다** — 행별 잔량이 있으면 그것이 이겨야 한다.
        let global: TimeInterval = 2.0
        let waiting = GamesChessMatchChrome.turnLine(match: budgeted, now: cmNow, graceSecondsFallback: global)
        let settling = GamesChessMatchChrome.turnLine(match: spent, now: cmNow, graceSecondsFallback: global)

        #expect(waiting.text == "상대 차례예요" && waiting.tint == .quiet)
        #expect(settling.text == "시간이 다 됐어요 · 결과를 확인하고 있어요",
                "예산을 다 쓴 판을 아직 '상대 차례' 로 그린다 — 전역 2초를 쓰고 있다")
        #expect(settling.tint == .warn)
        #expect(waiting.text != settling.text, "예산만 다른 두 판이 같은 줄을 그린다")

        // 독립 산식으로 서버 규칙을 다시 계산해 같은 답인지 본다(duel.sql `v_over > v_grace`).
        for (label, match) in [("예산 2초", budgeted), ("예산 0", spent)] {
            let over = 2.5 - 1.0
            let serverFlagged = over > Double(match.whiteGraceMs ?? 0)
            let line = GamesChessMatchChrome.turnLine(match: match, now: cmNow, graceSecondsFallback: global)
            #expect((line.text == "시간이 다 됐어요 · 결과를 확인하고 있어요") == serverFlagged,
                    "\(label): 화면 깃발이 서버 규칙과 갈린다")
        }
    }

    @Test("예산이 남은 판도 초과가 예산을 넘으면 결과 확인으로 넘어간다(네트가 늘 false 가 아니다)")
    func flagOverdueStillFiresWhenBudgetIsExceeded() {
        let clock = ChessServerClock(whiteMsLeft: 1_000, blackMsLeft: 300_000, incrementMs: 3_000,
                                     turnStartedAt: cmNow.addingTimeInterval(-3.6), running: .white)
        let match = cmMatch(myColor: .black, turn: .white, clock: clock, whiteGraceMs: 2_000)
        let line = GamesChessMatchChrome.turnLine(match: match, now: cmNow, graceSecondsFallback: 2.0)
        #expect(line.text == "시간이 다 됐어요 · 결과를 확인하고 있어요")
    }

    @Test("서버가 잔량 칸을 안 준 옛 응답만 전역 유예로 떨어진다")
    func legacyResponseFallsBackToGlobalGrace() {
        func line(elapsed: TimeInterval) -> String {
            let clock = ChessServerClock(whiteMsLeft: 1_000, blackMsLeft: 300_000, incrementMs: 3_000,
                                         turnStartedAt: cmNow.addingTimeInterval(-elapsed), running: .white)
            let match = cmMatch(myColor: .black, turn: .white, clock: clock)   // 잔량 nil
            return GamesChessMatchChrome.turnLine(match: match, now: cmNow, graceSecondsFallback: 2.0).text
        }
        #expect(line(elapsed: 2.5) == "상대 차례예요", "초과 1.5초 ≤ 전역 2초")
        #expect(line(elapsed: 3.5) == "시간이 다 됐어요 · 결과를 확인하고 있어요", "초과 2.5초 > 전역 2초")
    }

    @Test("차례 줄 우선순위: 결과 확인 > 로봇 생각 중 > 체크 > 내 차례/상대 차례")
    func turnLinePriority() {
        let running = ChessServerClock(whiteMsLeft: 120_000, blackMsLeft: 120_000, incrementMs: 3_000,
                                       turnStartedAt: cmNow, running: .white)
        let mine = cmMatch(turn: .white, clock: running)
        #expect(GamesChessMatchChrome.turnLine(match: mine, now: cmNow, graceSecondsFallback: 2).text == "내 차례예요")
        #expect(GamesChessMatchChrome.turnLine(match: mine, now: cmNow, graceSecondsFallback: 2).tint == .good)

        let check = cmMatch(turn: .white, clock: running, isInCheck: true)
        let checkLine = GamesChessMatchChrome.turnLine(match: check, now: cmNow, graceSecondsFallback: 2)
        #expect(checkLine.text == "체크! 왕을 피하세요" && checkLine.tint == .bad)

        let theirCheck = cmMatch(myColor: .black, turn: .white, clock: running, isInCheck: true)
        #expect(GamesChessMatchChrome.turnLine(match: theirCheck, now: cmNow, graceSecondsFallback: 2).text
                == "상대가 체크예요")

        let robot = cmMatch(myColor: .white, turn: .black, clock: running)
        #expect(GamesChessMatchChrome.turnLine(match: robot, now: cmNow, graceSecondsFallback: 2,
                                               isRobotThinking: true).text == "로봇이 생각 중이에요")

        // 끝난 판은 결과를 말한다(차례가 없다).
        let done = cmMatch(isFinished: true, outcome: .won, endReason: .checkmate)
        #expect(GamesChessMatchChrome.turnLine(match: done, now: cmNow, graceSecondsFallback: 2).text == "이겼어요")
        // 끝난 판은 깃발을 되묻지 않는다(`isFlagOverdue` 가 false).
        #expect(!done.isFlagOverdue(now: cmNow.addingTimeInterval(86_400), graceSeconds: 2))
    }

    // MARK: ③ 승격은 2단 (코어가 판정한다)

    @Test("★ 도착 칸이 같은 합법 수가 넷이면 승격 시트가 뜨고, 하나면 안 뜬다")
    func promotionSheetOnlyWhenFourCandidates() async throws {
        // 승격 판: a7 폰 하나(도착 칸 a8 로 가는 합법 수가 넷).
        let promoFEN = "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"
        let a7 = cmSquare("a7"), a8 = cmSquare("a8")
        let four = ChessPieceKind.promotionChoices.map { ChessMove(from: a7, to: a8, promotion: $0) }
        #expect(four.count == 4)
        let promoting = cmStore(match: cmMatch(fen: promoFEN, legalMoves: four))
        #expect(!cmChrome(try #require(promoting.match), promotion: promoting.promotion).showsPromotionSheet,
                "누르기 전에는 안 뜬다")

        await promoting.tap(a7)
        #expect(promoting.selection?.from == a7, "전제: 폰이 골라졌다")
        await promoting.tap(a8)

        let prompt = try #require(promoting.promotion, "합법 수가 넷인데 승격을 묻지 않는다")
        #expect(prompt.from == a7 && prompt.to == a8)
        #expect(prompt.choices == [.queen, .rook, .bishop, .knight], "네 말을 묻는다")
        #expect(cmChrome(try #require(promoting.match), promotion: promoting.promotion).showsPromotionSheet)
        #expect(promoting.selection == nil, "승격 단계에서는 고르기가 접힌다")

        // 평수 판: a2 폰의 한 칸 전진 하나뿐 — 묻지 않고 바로 나간다.
        let plainFEN = "4k3/8/8/8/8/8/P7/4K3 w - - 0 1"
        let a2 = cmSquare("a2"), a3 = cmSquare("a3")
        let plain = cmStore(match: cmMatch(fen: plainFEN, legalMoves: [ChessMove(from: a2, to: a3)]))
        await plain.tap(a2)
        await plain.tap(a3)
        #expect(plain.promotion == nil, "합법 수가 하나인데 승격을 묻는다")
        #expect(!cmChrome(try #require(plain.match), promotion: plain.promotion).showsPromotionSheet)
        // 로그인이 없어 수는 못 나갔고, 그 거절은 **안내 한 줄로 보인다**(무음 거절이 아니다).
        #expect(plain.notice == ChessNoticeText.signInAgain)
        let refused = cmChrome(try #require(plain.match), notice: plain.notice)
        #expect(refused.statusLine?.text == ChessNoticeText.signInAgain)
        #expect(refused.statusLine?.tint == .warn)
    }

    @Test("승격 시트를 닫으면 승격 단계가 접힌다(고르기는 남는다)")
    func cancelingPromotionFoldsTheStage() async throws {
        let promoFEN = "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"
        let a7 = cmSquare("a7"), a8 = cmSquare("a8")
        let store = cmStore(match: cmMatch(
            fen: promoFEN, legalMoves: ChessPieceKind.promotionChoices.map { ChessMove(from: a7, to: a8, promotion: $0) }))
        await store.tap(a7)
        await store.tap(a8)
        #expect(store.promotion != nil)
        store.cancelPromotion()
        #expect(store.promotion == nil)
        #expect(!cmChrome(try #require(store.match), promotion: store.promotion).showsPromotionSheet)
    }

    // MARK: ④ 시계는 서버가 쥔다

    @Test("★ 시간이 흘러 시계 글자는 바뀌지만 서버가 준 네 칸은 바이트까지 그대로다(폰이 세지 않는다)")
    func thePhoneNeverCountsTheClock() throws {
        let started = cmNow
        let clock = ChessServerClock(whiteMsLeft: 600_000, blackMsLeft: 480_000, incrementMs: 3_000,
                                     turnStartedAt: started, running: .white)
        let store = cmStore(match: cmMatch(clock: clock))
        let before = try #require(store.match).clock

        var texts: [String] = []
        for step in [0.0, 1.0, 5.0, 61.0, 599.5, 1_000.0] {
            let now = started.addingTimeInterval(step)
            let seconds = try #require(store.remainingSeconds(.white, now: now))
            texts.append(GamesChessMatchChrome.clockFace(seconds: seconds, isTurn: true).text)
            // ★ 한 틱도 값을 건드리지 않았다.
            let current = try #require(store.match).clock
            #expect(current == before, "\(step)초에 폰이 시계 값을 고쳤다")
        }
        let after = try #require(store.match).clock
        #expect(after.whiteMsLeft == 600_000)
        #expect(after.blackMsLeft == 480_000)
        #expect(Set(texts).count == texts.count, "흐르는 시계가 같은 글자를 내놓는다: \(texts)")
        #expect(texts.first == "10:00", "서버가 준 값에서 바로 나온다")
        #expect(texts.last == "0.0", "뚜껑이 0 이다(음수를 그리지 않는다)")

        // 상대 시계는 흐르지 않는다(차례가 아니다) — 둘이 같은 값을 보이면 한쪽이 안 그려진 것이다.
        let theirs = try #require(store.remainingSeconds(.black, now: started.addingTimeInterval(120)))
        #expect(theirs == 480.0)
    }

    @Test("시계 글자·색: 10초 아래는 소수 한 자리 · 30초 이하 앰버 · 10초 이하 빨강 · 내 차례가 아니면 회색")
    func clockFaceFormatAndTint() {
        #expect(GamesChessMatchChrome.clockFace(seconds: 65, isTurn: true).text == "1:05")
        #expect(GamesChessMatchChrome.clockFace(seconds: 9.44, isTurn: true).text == "9.4")
        #expect(GamesChessMatchChrome.clockFace(seconds: 0, isTurn: true).text == "0.0")
        #expect(GamesChessMatchChrome.clockFace(seconds: -3, isTurn: true).text == "0.0")
        #expect(GamesChessMatchChrome.clockFace(seconds: 120, isTurn: true).tint == .good)
        #expect(GamesChessMatchChrome.clockFace(seconds: 30, isTurn: true).tint == .warn)
        #expect(GamesChessMatchChrome.clockFace(seconds: 10, isTurn: true).tint == .bad)
        #expect(GamesChessMatchChrome.clockFace(seconds: 3, isTurn: false).tint == .quiet)
        #expect(GamesChessMatchChrome.clockAccessibility(seconds: 65, color: .white) == "백 남은 시간 1분 5초")
        #expect(GamesChessMatchChrome.clockAccessibility(seconds: 7, color: .black) == "흑 남은 시간 7초")
    }

    // MARK: ⑤ 동작 줄 · 판 방향 · 읽을 수 없는 판

    @Test("무승부 제안을 받은 판은 [수락]/[거절] 이 서고, 내가 제안한 판은 다시 못 누른다")
    func drawOfferActionRow() {
        let incoming = cmChrome(cmMatch(drawOfferBy: cmPeer.id))
        #expect(incoming.actionRow == .answerDrawOffer, "받은 제안에 답할 길이 없으면 무승부를 놓친다")
        #expect(incoming.statusLine?.text == ChessPhoneText.drawOfferedByOpponent)

        let mine = cmChrome(cmMatch(drawOfferBy: "me", drawOfferedByMe: true))
        #expect(mine.actionRow == .playing(canOfferDraw: false, canResign: true))
        #expect(mine.statusLine?.text == ChessPhoneText.drawOfferedByMe)

        let busy = cmChrome(cmMatch(), isBusy: true)
        #expect(busy.actionRow == .playing(canOfferDraw: false, canResign: false), "왕복 중에는 둘 다 잠긴다")

        let robot = cmChrome(cmMatch(), isRobotMatch: true)
        #expect(robot.actionRow == .playing(canOfferDraw: false, canResign: true), "합의할 상대가 없다")
        #expect(!robot.showsStake)

        let plain = cmChrome(cmMatch())
        #expect(plain.actionRow == .playing(canOfferDraw: true, canResign: true))
        #expect(plain.showsStake && plain.stake == 5 && plain.stakeSuffix == " · 이기면 +5")
    }

    @Test("끝난 판에는 기권·무승부 제안이 없고 로봇 판만 [다시 두기]가 있다")
    func finishedActionRow() {
        let pvp = cmChrome(cmMatch(isFinished: true, outcome: .lost, endReason: .resign))
        #expect(pvp.actionRow == .finished(showsPlayAgain: false))
        let robot = cmChrome(cmMatch(isFinished: true, outcome: .won, endReason: .checkmate), isRobotMatch: true)
        #expect(robot.actionRow == .finished(showsPlayAgain: true))
        // 끝난 판이 받은 제안을 들고 있어도(서버가 지우기 전) 동작 줄은 결과다 — 끝난 판에 수락할 것은 없다.
        let stale = cmChrome(cmMatch(isFinished: true, outcome: .draw, endReason: .agreement,
                                     drawOfferBy: cmPeer.id))
        #expect(stale.actionRow == .finished(showsPlayAgain: false))
    }

    @Test("판 방향은 내 색이 아래 · 읽을 수 없는 판은 판만 접고 결과·루비는 보여 준다")
    func boardOrientationAndUnreadableBoard() throws {
        #expect(cmChrome(cmMatch(myColor: .white)).whiteAtBottom)
        #expect(!cmChrome(cmMatch(myColor: .black)).whiteAtBottom)
        #expect(cmChrome(cmMatch()).drawsBoard)
        #expect(cmChrome(cmMatch()).plyLine == "10수 진행")

        let broken = cmChrome(cmMatch(readableBoard: false, isFinished: true, outcome: .draw,
                                      endReason: .timeoutInsufficient))
        #expect(!broken.drawsBoard)
        let result = try #require(broken.result, "판을 못 읽어도 결과와 루비는 봐야 한다")
        #expect(result.isDraw && result.rubyNote == "판돈 5 루비를 돌려받았어요")
    }

    @Test("판 한 변: 기본 글자는 판 레인 값 그대로 · 큰 글자에서만 보이는 높이에 맞춰 줄인다")
    func boardSideShrinksOnlyForLargeText() {
        let screen = CGSize(width: 393, height: 759)
        let lane: CGFloat = 369                       // 판 레인이 준 값(화면 폭 − 24)
        #expect(GamesChessMatchChrome.boardSide(laneDefault: lane, visible: screen,
                                                isLargeText: false, isAccessibilitySize: false) == lane,
                "기본 글자에서 판 레인 값을 건드린다")
        // 키 큰 화면에서는 52% 가 레인 값보다 커서 **아무것도 줄지 않는다**(판을 괜히 깎지 않는다).
        #expect(GamesChessMatchChrome.boardSide(laneDefault: lane, visible: screen,
                                                isLargeText: true, isAccessibilitySize: false) == lane)
        // 낮은 화면(큰 글자로 카드가 높아진 상태)에서는 보이는 높이의 52% 로 줄어든다.
        let short = CGSize(width: 393, height: 600)
        let large = GamesChessMatchChrome.boardSide(laneDefault: lane, visible: short,
                                                    isLargeText: true, isAccessibilitySize: false)
        #expect(large == (600 * 0.52).rounded() && large < lane, "큰 글자에서 판이 화면을 밀어낸다")
        let ax = GamesChessMatchChrome.boardSide(laneDefault: lane, visible: short,
                                                 isLargeText: true, isAccessibilitySize: true)
        #expect(ax == (600 * 0.40).rounded())
        #expect(ax < large, "접근성 글자에서 더 줄어야 카드 둘과 차례 줄이 한 화면에 든다")
        // 아무리 좁아도 240 아래로는 안 간다(판이 뭉개지면 칸을 못 누른다).
        #expect(GamesChessMatchChrome.boardSide(laneDefault: lane, visible: CGSize(width: 393, height: 200),
                                                isLargeText: true, isAccessibilitySize: true) == 240)
        // 높이를 모르면(레이아웃 전) 레인 값을 그대로 쓴다.
        #expect(GamesChessMatchChrome.boardSide(laneDefault: lane, visible: CGSize(width: 393, height: 0),
                                                isLargeText: true, isAccessibilitySize: true) == lane)
    }

    @Test("★ 창 가시성 깃발은 **배선이 켠다** — 화면은 읽기만 한다(안 켜지면 시계·애니메이션이 멈춘 채 초록이다)")
    func theScreenOnlyReadsTheWindowVisibleFlag() throws {
        // 코어 기본값은 **false** 다(`ChessStore.swift` 의 `isWindowVisible`). `beginFlight` 가 맨 앞에서
        // 그 깃발로 막으므로, 배선(로비·입구 레인)이 `windowDidShow()` 를 부르지 않으면 `store.flight` 가
        // 영원히 nil 이고 판은 멈춘 국면만 그린다 — 말이 순간이동하는 것처럼 보인다.
        // 그런데 그 거절은 **의도된 동작**이라 어떤 시험도 빨개지지 않는다. 그래서 여기서 사실만 못 박는다.
        let store = ChessStore()
        #expect(!store.isWindowVisible, "기본값이 바뀌었다 — 잎 뷰의 멈춤 조건을 다시 봐야 한다")
        #expect(store.flight == nil)

        let code = stripComments(try String(contentsOf: Self.root.appendingPathComponent(Self.viewPath),
                                            encoding: .utf8))
        // 화면은 그 깃발을 **읽기만** 한다 — 여기서 켜면 배선 레인 파일과 통합에서 부딪힌다.
        #expect(!code.contains("isWindowVisible ="), "화면이 창 가시성을 직접 켠다(배선 레인 소유다)")
        #expect(code.components(separatedBy: "paused: !store.isWindowVisible").count == 3,
                "잎 뷰 둘이 다 그 깃발로 멈춘다(배터리 계약)")
    }

    @Test("[기권]은 화면이 뜬 직후 1초 동안 안 눌린다(실수로 판돈을 잃는다)")
    func resignTapIsArmedAfterADelay() {
        #expect(GamesChessMatchChrome.resignArmDelay == 1.0)
        #expect(!GamesChessMatchChrome.acceptsResignTap(shownAt: cmNow, now: cmNow))
        #expect(!GamesChessMatchChrome.acceptsResignTap(shownAt: cmNow, now: cmNow.addingTimeInterval(0.9)))
        #expect(GamesChessMatchChrome.acceptsResignTap(shownAt: cmNow, now: cmNow.addingTimeInterval(1.0)))
        #expect(GamesChessMatchChrome.acceptsResignTap(shownAt: nil, now: cmNow))
    }

    // MARK: 소스 계약 (주석을 걷어낸 코드로 본다)

    @Test("화면 소스: 합법 수·시계·낙관적 판·재시도 버튼이 없다 · 초는 잎 뷰만 읽는다")
    func sourceContracts() throws {
        let code = stripComments(try String(contentsOf: Self.root.appendingPathComponent(Self.viewPath),
                                            encoding: .utf8))
        // ④ 합법 수를 클라가 만들지 않는다(1:1 은 서버가 권위 — 코어가 두 길을 한 칸으로 합쳐 뒀다).
        for banned in ["ChessRules", "legalMoves(in:", "ChessAI"] {
            #expect(!code.contains(banned), "화면이 합법 수·수 선택을 스스로 만든다: \(banned)")
        }
        // ① 폰이 시계를 세지 않는다 — 서버가 준 ms 칸을 **이름으로도 부르지 않고**(읽기든 쓰기든 초는
        //    `store.remainingSeconds(_:now:)` 하나로 온다), 제 타이머도 제 시계도 시간 상수도 없다.
        for banned in ["whiteMsLeft", "blackMsLeft", "msLeft", "Timer(", "Timer.publish", "Date()",
                       "ChessClock.initialSeconds", "300_000", "600_000"] {
            #expect(!code.contains(banned), "폰이 시계를 세거나 시간 상수를 베낀다: \(banned)")
        }
        #expect(code.contains("store.remainingSeconds("), "초는 코어의 순수 계산에서 온다")
        #expect(code.components(separatedBy: "TimelineView(.animation").count == 3,
                "초를 읽는 자리는 잎 뷰 둘(시계·차례 줄)뿐이다")
        // ⑥ 수 번호 가드를 두 벌로 두지 않는다(applyState 가 이미 막는다).
        for banned in ["applyState", "plyCount <", "plyCount >"] {
            #expect(!code.contains(banned), "화면이 수 번호를 또 판정한다: \(banned)")
        }
        // ⑦ 착수 재시도 버튼이 없다(같은 `expected_ply` 두 번은 stale 이고 가산은 한 번만 붙는다).
        #expect(!code.contains("store.send("), "화면이 수를 직접 보낸다 — 입구는 탭과 승격 고르기뿐이다")
        #expect(!code.contains("expected_ply"))
        // ⑧ 낙관적 표시가 없다 — 판은 서버가 확인한 국면만 그린다.
        #expect(code.contains("position: match.position ?? .empty"), "판이 서버 국면 말고 다른 것을 그린다")
        // ② 깃발 판정은 코어 함수 하나뿐이다(손 비교 금지).
        #expect(code.contains("isFlagOverdue(now:"), "깃발 판정이 코어 함수를 지나지 않는다")
        #expect(!code.contains("rawRemainingSeconds"), "화면이 깃발을 손으로 비교한다")
        #expect(code.components(separatedBy: "graceSecondsFallback").count >= 2)
        // 탭 막대 숨김은 공용 수단으로만(게임 폴더 계약 — GamesRedesignTests 와 같은 줄).
        #expect(!code.contains("toolbar(.hidden, for: .tabBar)"))
        // 채팅은 없다(오목에만 있다).
        #expect(!code.contains("ChatDrawer"))
    }

    /// 체크는 **판에서 보여야 하는 정보**다. 문구(`turnLine` 의 `inCheck`)로만 말하면 왕이 어디서 맞고 있는지
    /// 모른다. 그림까지 가는 길은 `GamesChessFlightRenderTests` 가 픽셀로 재고, 여기서는 **표의 값**을 잰다.
    ///
    /// ★ 규칙을 돌리지 않는다: 깃발은 서버가 준 `match.isInCheck` 이고 칸은 배치에서 읽는다(§6 ④ · B5).
    @Test("표가 체크 받은 왕의 칸을 집는다 — 체크가 아니면·끝난 판이면·판을 못 읽으면 nil")
    func theChromePicksTheCheckedKingSquare() throws {
        // 데모 픽스처 `demo-chess-incheck` 와 같은 국면(백 왕 e1 · 흑 비숍 f2 가 체크).
        let fen = "r1bqk1nr/pppp1ppp/2n5/4N3/2B1P3/8/PPPP1bPP/RNBQK2R w KQkq - 0 5"
        let checked = cmChrome(cmMatch(turn: .white, fen: fen, isInCheck: true))
        #expect(checked.checkSquare == cmSquare("e1"),
                "체크인데 왕 칸이 안 선다(\(checked.checkSquare?.notation ?? "없음"))")
        // 기준선이 갈린다 — 같으면 위 한 줄은 "아무 칸도 안 세운다" 로도 초록이다.
        #expect(cmChrome(cmMatch(turn: .white, fen: fen, isInCheck: false)).checkSquare == nil,
                "체크가 아닌데 덮개 칸이 선다")
        // 흑이 체크를 받는 국면이면 **흑 왕**이다(차례쪽 왕을 집는다 — 내 색이 아니다).
        // e 열이 열려 있고 백 룩이 e5 에서 e8 을 본다(e6·e7 이 비었다).
        let blackChecked = cmChrome(cmMatch(myColor: .white, turn: .black,
                                            fen: "rnbqkbnr/pppp1ppp/8/4R3/8/8/PPPPPPPP/RNBQKBN1 b Qkq - 0 1",
                                            isInCheck: true))
        #expect(blackChecked.checkSquare == cmSquare("e8"),
                "차례쪽(흑) 왕이 아니라 다른 칸을 집었다(\(blackChecked.checkSquare?.notation ?? "없음"))")
        // 끝난 판에는 없다 — 결과 화면에 빨간 칸이 남으면 아직 두는 중처럼 읽힌다.
        #expect(cmChrome(cmMatch(turn: .white, fen: fen, isInCheck: true, isFinished: true,
                                 outcome: .lost, endReason: .checkmate)).checkSquare == nil,
                "끝난 판에 체크 덮개가 남는다")
        // 판을 못 읽으면 없다(그때는 판 자체를 그리지 않는다 — `drawsBoard`).
        #expect(cmChrome(cmMatch(turn: .white, fen: fen, readableBoard: false, isInCheck: true)).checkSquare == nil,
                "읽을 수 없는 판에 덮개 칸이 선다")
    }

    @Test("공개 이름 하나: GamesChessMatchView(store:) · 자리표시는 private 이라 밖으로 안 샌다")
    func publicSurface() throws {
        let code = stripComments(try String(contentsOf: Self.root.appendingPathComponent(Self.viewPath),
                                            encoding: .utf8))
        #expect(code.contains("struct GamesChessMatchView: View"))
        #expect(code.contains("let store: ChessStore"))
        // ★ 통합이 자리표시 넷(판·한 변·승격 시트·문구 표)을 **지웠다** — 이제 그 이름들은 이웃 레인의 것이고
        //   이 파일에는 **제 벌이 하나도 없어야** 한다. 남으면 같은 모듈에 같은 이름이 둘이 되어 컴파일이 막히고
        //   (프로브로 실측했다 — `private` 이어도 invalid redeclaration 이다), 그 요란한 실패가 이 단언의 짝이다.
        for leftover in ["private struct GamesChessBoard", "private enum GamesChessBoardMetrics",
                         "private struct GamesChessPromotionSheet", "private enum GamesChessText",
                         "enum GamesChessText {"] {
            #expect(!code.contains(leftover), "자리표시 \(leftover) 가 남아 있다 — 이웃 레인의 진짜 부품과 겹친다")
        }
        #expect(code.contains("GamesChessBoard(position: match.position ?? .empty, flight: store.flight,"))
        // 체크 덮개는 **표에서 받는다**. nil 을 박아 두면 문구만 "체크예요" 라고 말하고 판은 가만히 있다
        // (통합 직후 실제로 그랬다 — 캔버스에는 인자가 있는데 감싸개가 안 받았다).
        #expect(code.contains("checkSquare: chrome.checkSquare"), "판에 체크 칸을 넘기지 않는다")
        #expect(code.contains("lastMove: match.lastMove.map { (from: $0.from, to: $0.to) }"),
                "마지막 수를 판 부품의 꼴(칸 둘)로 넘기지 않는다")
        #expect(code.contains("GamesChessBoardMetrics.side(fitting:"))
        #expect(code.contains("GamesChessPromotionSheet(store: store, prompt: prompt, myColor: match.myColor)"))
        // 승격 시트의 계약 둘(쓸어 내려 닫을 수 없다 · 닫는 길은 `cancelPromotion()` 하나뿐)은 **시트 파일**이
        // 쥔다 — 통합 뒤 이 화면은 시트를 띄우기만 한다. 그래서 그 둘을 거기서 잰다.
        //
        // ★ 이 화면의 `isPresented` setter 는 **아무 일도 하지 않아야** 한다: 승격을 고르지 않고 빠져나가는
        //   두 번째 길을 만들면 그 길로 나간 폰은 고르기만 사라진 채 수가 영원히 안 나간다.
        #expect(code.contains("set: { _ in }"), "승격 시트에 두 번째 닫는 길이 생겼다")
        #expect(!code.contains("store.cancelPromotion()"), "닫는 길이 화면에도 있다 — 시트 하나로 모아 둔다")
        let sheets = stripComments(try String(
            contentsOf: Self.root.appendingPathComponent("Sources/CheckMobileKit/Games/GamesChessSheets.swift"),
            encoding: .utf8))
        #expect(sheets.contains("interactiveDismissDisabled()"))
        #expect(sheets.components(separatedBy: "store.cancelPromotion()").count == 2,
                "승격을 고르지 않고 빠져나가는 길이 둘 이상이다")
    }

    // MARK: ⑥ 판이 열을 벌리지 않는다 (D1 — 기본 글자 전용 잘림)

    /// 판 한 변을 **화면이 정하는 대로** 잰다: 여백을 뺀 예산 → 8의 배수 → 큰 글자 축소 → 열 가둠.
    /// 뷰가 하는 셈을 그대로 한 자리에 모은 것이고, 소스 단언이 뷰가 **이 셈을 지난다**는 것을 못 박는다.
    private static func cmBoardSide(screenWidth: CGFloat, screenHeight: CGFloat = 874,
                                    sideMargin: CGFloat = 16,
                                    isLargeText: Bool = false,
                                    isAccessibilitySize: Bool = false) -> CGFloat {
        let visible = CGSize(width: screenWidth, height: screenHeight)
        let budget = GamesChessMatchChrome.boardBudget(visible: visible, sideMargin: sideMargin)
        let lane = GamesChessBoardMetrics.side(fitting: budget)
        return GamesChessMatchChrome.cagedSide(
            GamesChessMatchChrome.boardSide(laneDefault: lane, visible: visible,
                                            isLargeText: isLargeText,
                                            isAccessibilitySize: isAccessibilitySize),
            columnWidth: budget.width)
    }

    @Test("★ 판 + 좌우 여백이 화면 폭 안에 들어온다 — **기본 글자**에서 모든 아이폰 폭(기준선: 화면 폭을 넘기면 전부 넘친다)")
    func theBoardFitsInsideTheColumnAtDefaultTextSize() {
        // 헤드리스 실측으로 잡은 결함이다: 판에 **화면 폭**을 주면 한 변이 그 폭에서 정해지고, 판은
        // `.padding(.horizontal, 16)` **안**에 있으므로 열이 벌어져 결과 카드·사람 카드·시계 칩·기보가
        // 함께 오른쪽으로 잘렸다(402pt 에서 판 오른쪽 모서리가 x=416pt — 화면 밖 14pt).
        //
        // ★ 기준선이 달라야 한다: 아래 `legacy` 는 **여백을 안 뺀** 옛 셈이고 모든 폭에서 넘친다.
        //   그 기준선이 없으면 이 시험은 "식이 식과 같다" 만 말한다.
        let widths: [CGFloat] = [320, 360, 375, 390, 393, 402, 414, 428, 430, 440, 1024]
        for width in widths {
            let side = Self.cmBoardSide(screenWidth: width)
            #expect(side + 32 <= width,
                    "\(width)pt 에서 판(\(side)) + 여백 32 가 화면을 넘는다 — 열의 자식 전부가 잘린다")
            #expect(side.truncatingRemainder(dividingBy: 8) == 0, "\(width)pt 에서 한 변이 8의 배수가 아니다")
            // 기준선(옛 셈) — 여백을 안 빼면 **모든 폭에서** 넘친다는 사실을 같이 못 박는다.
            let legacy = GamesChessBoardMetrics.side(fitting: CGSize(width: width, height: 874))
            if width <= 440 {
                #expect(legacy + 32 > width,
                        "기준선이 안 넘친다 — 이 폭에서는 옛 셈도 멀쩡했다는 뜻이라 기준선을 다시 골라야 한다")
                #expect(side < legacy, "고친 셈이 옛 셈과 같다 — 여백을 빼지 않았다")
            }
        }
    }

    @Test("큰 글자·접근성 글자에서도 열 안이고, 좁은 창은 **열 폭에서 잘린다**(판 레인 바닥값이 열을 벌리지 못한다)")
    func theBoardFitsAtLargeTextAndInNarrowColumns() {
        for width in [CGFloat(320), 390, 402, 440] {
            for (large, a11y) in [(true, false), (true, true)] {
                let side = Self.cmBoardSide(screenWidth: width, isLargeText: large, isAccessibilitySize: a11y)
                #expect(side + 32 <= width, "\(width)pt large=\(large) a11y=\(a11y) 에서 판이 열을 넘는다")
            }
        }
        // 가둠: 열이 판 레인 바닥값(160)보다 좁아도 판은 열을 넘지 않는다.
        #expect(GamesChessMatchChrome.cagedSide(160, columnWidth: 100) == 100)
        #expect(GamesChessMatchChrome.cagedSide(368, columnWidth: 370) == 368, "열보다 좁은 판을 괜히 깎는다")
        // 첫 배치 한 틱(0)에는 자르지 않는다 — 0 으로 자르면 판이 사라진다.
        #expect(GamesChessMatchChrome.cagedSide(368, columnWidth: 0) == 368)
        // 예산 자체도 음수로 내려가지 않는다(0 으로 접힌다).
        #expect(GamesChessMatchChrome.boardBudget(visible: CGSize(width: 10, height: 100), sideMargin: 16).width == 0)
        #expect(GamesChessMatchChrome.boardBudget(visible: CGSize(width: 402, height: 874), sideMargin: 16)
                == CGSize(width: 370, height: 874), "예산이 좌우 여백 둘을 빼지 않는다")
    }

    @Test("화면 소스: 판 레인에 넘기는 값이 **여백을 뺀 예산**이고, 판은 열 폭에 가둬진다")
    func theViewPassesTheMarginSubtractedBudgetToTheBoardLane() throws {
        let code = stripComments(try String(contentsOf: Self.root.appendingPathComponent(Self.viewPath),
                                            encoding: .utf8))
        let flat = code.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        // ★ 뮤테이션 과녁: 여백을 다시 안 빼면(= `side(fitting: visible)`) 여기가 빨개진다.
        #expect(flat.contains("boardBudget(visible: visible, sideMargin: MobileTheme.sideMargin)"),
                "판 예산이 화면 크기에서 열 여백을 빼지 않는다 — 열의 자식 전부가 오른쪽으로 잘린다")
        #expect(flat.contains("GamesChessBoardMetrics.side(fitting: budget)"),
                "판 레인에 예산이 아니라 다른 값을 넘긴다")
        #expect(!flat.contains("GamesChessBoardMetrics.side(fitting: visible)"),
                "판 레인에 **화면 폭**을 그대로 넘긴다(D1 의 정체다)")
        #expect(flat.contains("columnWidth: budget.width)"), "판이 열 폭에 가둬지지 않는다")
        // 열 여백은 한 값에서 온다 — 뷰가 16 을 베껴 적으면 여백이 바뀐 날 판만 옛 값으로 남는다.
        #expect(code.components(separatedBy: "MobileTheme.sideMargin").count == 3,
                "열 여백을 말하는 자리가 둘(열 패딩 · 판 예산)이 아니다")
    }

    // MARK: ⑦ 탭 막대 (D2 — 선언만 있고 호출이 없었다)

    @Test("★ 체스 대국·결과에서 탭 막대가 숨는다 — 그리고 `TabBarPolicy.Screen` 의 **모든 갈래에 호출자가 있다**")
    func everyTabBarPolicyScreenHasACaller() throws {
        // 결함의 정체: `Screen.chessMatch` 가 **주석까지 달려** 선언돼 있었는데 `.hidesTabBar(for: .chessMatch)`
        // 호출이 Sources 전체에 **0건**이었다. 그래서 무승부 제안 화면의 [무승부 수락]·[거절]이, 다른
        // 상태에서는 [기권]·[무승부 제안]이 탭 막대 뒤에 통째로 가렸다(헤드리스 실측 — 제한 시간이 도는
        // 판에서 가장 급한 버튼들이다). 선언을 세는 시험은 그 결함을 못 본다.
        //
        // ① 정책이 **값으로** 답한다(`.hidesTabBar(for:)` 가 이 답을 지나서 숨긴다 — `SheetChrome.swift`).
        #expect(TabBarPolicy.hidesTabBar(on: .chessMatch), "체스 대국 화면이 탭 막대를 숨기지 않는다")
        for screen in TabBarPolicy.Screen.allCases {
            #expect(TabBarPolicy.hidesTabBar(on: screen), "\(screen.rawValue) 가 숨기지 않는다고 답한다")
        }

        // ② 전수: 갈래마다 **뷰 안에 호출자**가 있다(주석을 걷어낸 소스에서 센다 — 본보기 주석이 호출로
        //    세어지면 이 결함이 그대로 초록이 된다).
        let sources = Self.root.appendingPathComponent("Sources")
        var code = ""
        let walker = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in walker where url.pathExtension == "swift" {
            code += stripComments(try String(contentsOf: url, encoding: .utf8))
        }
        #expect(code.contains("package func hidesTabBar(for screen: TabBarPolicy.Screen)"),
                "전제: 공용 수단을 못 읽었다(스캐너가 헛돈다)")
        for screen in TabBarPolicy.Screen.allCases {
            #expect(code.contains(".hidesTabBar(for: .\(screen.rawValue))"),
                    "\(screen.rawValue) 는 선언만 있고 **부르는 화면이 없다** — 그 화면은 탭 막대가 버튼을 가린다")
        }
        // ③ 게임 폴더 계약: 화면이 `toolbar(.hidden, for: .tabBar)` 를 직접 쓰지 않는다(규칙이 한 곳이다).
        let match = stripComments(try String(contentsOf: Self.root.appendingPathComponent(Self.viewPath),
                                             encoding: .utf8))
        #expect(!match.contains("for: .tabBar"), "화면이 탭 막대를 직접 숨긴다 — 공용 수단만 쓴다")
        #expect(match.contains(".hidesTabBar(for: .chessMatch)"), "대국 화면에 숨김 호출이 없다")
    }

    // MARK: ⑧ 데모 스크롤 닻 (D5 — 체스 로비만 없었다)

    @Test("체스 로비에 데모 스크롤 닻이 있다 — 없으면 `bottom` 으로도 순위·관전 절을 띄워 볼 수 없다")
    func theChessLobbyCarriesTheDemoScrollAnchor() throws {
        // 실측 결함: 오목 화면 넷·미니게임은 닻을 달고 있는데 체스 로비만 없었다. 그래서 그 두 절(순위·관전)이
        // **이 작업에서 아무도 눈으로 못 본** 절이 됐다 — 로비 맨 아래라 기본 닻으로는 화면에 들어오지 않는다.
        let anchor = ".gamesDemoScrollAnchor(isDemo: store.context.isDemo)"
        let chess = stripComments(try String(
            contentsOf: Self.root.appendingPathComponent("Sources/CheckMobileKit/Games/GamesChessScreen.swift"),
            encoding: .utf8))
        #expect(chess.contains(anchor), "체스 로비에 데모 스크롤 닻이 없다")
        // 본보기와 **같은 모양**인지(다른 꼴로 적으면 데모 씨앗을 안 지나 아무 일도 안 한다).
        let gomoku = stripComments(try String(
            contentsOf: Self.root.appendingPathComponent("Sources/CheckMobileKit/Games/GamesGomokuScreen.swift"),
            encoding: .utf8))
        #expect(gomoku.contains(anchor), "전제: 본보기(오목 화면)가 바뀌었다 — 모양을 다시 맞춰야 한다")
    }
}
