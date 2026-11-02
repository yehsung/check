import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 뒤집기 **화면** 렌더 — 로비 · 내 차례(합법 수 점) · 상대 차례 · 패스 안내 · 뒤집기 직후 · 결과(승·패·무·abandoned) ·
// 규칙 창 · 관전 · AI 색 고르기 · AI 판(설계서 FLIP/SPEC.md §5 · §6.3 U 줄).
//
// 전부 ImageRenderer(scale 2)로 `CheckRenderSettle` 이 굳힌 뒤 재고, `CHECK_SNAPSHOT_DIR/reversi/` 에 PNG 를 남긴다
// (사람이 직접 열어 본다 — 디자인 작업에서 초록 시험은 아무것도 증명하지 않는다).
//
// ★ **"노란 상자 0" 을 감지기로 쓰지 않는다**(Menu·기본 Picker 는 아무것도 안 그린다). 화면은 **잉크**로 잰다.
// ★ **판은 "돌 잉크" 로 잰다.** `ReversiBoardView` 는 칸·격자·점을 중간 톤으로, **돌만 극단**으로 그린다. 그래서
//   "칸 가운데 50% 상자에 극단 픽셀이 있는가" 가 곧 "그 칸에 돌이 섰는가" 이고, 돌 잉크 칸 수 = 판의 돌 수여야 한다.
// ★ **합법 수 점은 서버 목록만 그린다**(DEC:26). 진짜 판에서는 서버 목록과 로컬 규칙이 늘 같아 이 규칙을 못 잰다 —
//   그래서 시작 판 흑 차례에 서버가 `[19]` 만 준 **어긋난 기준선**을 그려 점 덩어리 1 대 4 로 가른다(CCT I7).
// 상태는 `package internal(set)` 칸에 직접 심는다(C1 뼈대의 `applyState`/`applyLobby` 몸통은 갈래 C 가 채우는 중이다).
// 스토어에 host 를 물리지 않아 네트워크는 한 건도 안 나간다. 시각은 `previewNow` 로 고정한다(30초 링 · 뒤집기 프레임).

@MainActor
@Suite(.serialized)
struct V03xxReversiPanelRenderTests {
    // MARK: ① 로비

    /// 없으면: 로비 세 열이 크롬(카드 테두리·제목)만 그리고 내용(사람·순위·대결 중·신청)이 비어도 초록이다.
    @Test
    func theLobbyDrawsInkInAllThreeColumns() throws {
        let full = try rvBitmap(rvPanel(rvLobbyStore()))
        let bare = try rvBitmap(rvPanel(rvLobbyStore(populated: false)))
        rvSave(full, "lobby")
        rvSave(bare, "lobby-empty")

        let size = ReversiWindowLayout.contentSize
        #expect(full.pixelsWide == Int(size.width) * 2 && full.pixelsHigh == Int(size.height) * 2,
                "로비가 \(full.pixelsWide)×\(full.pixelsHigh)px 다 — 고정 창을 넘치거나 모자란다")
        for (label, rect, minimum) in [("상대 목록", rvLobbyUsersColumn, 4_000),
                                       ("순위", rvLobbyRankColumn, 4_000),
                                       ("오른쪽(전적·대결·신청)", rvLobbySideColumn, 2_000)] {
            let withContent = rvInk(full, rect: rect)
            let withoutContent = rvInk(bare, rect: rect)
            print("[로비] \(label): 잉크 \(withContent)px (빈 가게 \(withoutContent)px)")
            #expect(withContent > withoutContent + minimum,
                    "\(label) 열이 내용을 안 그린다(잉크 \(withContent) vs 빈 가게 \(withoutContent))")
        }

        // 판돈 창(가운데 작은 창)도 그린다 — 사람이 보는 PNG.
        let stake = try rvBitmap(rvPanel(rvLobbyStore(), previewStakeTarget: rvMinsu, previewStakeSelection: .five))
        rvSave(stake, "lobby-stake-prompt")
        #expect(rvMaxChannelDifference(stake, full, rect: rvCenterRect) > 60, "판돈 창이 안 그려졌다")
    }

    // MARK: ② 내 차례 — 합법 수 점은 서버 목록만

    /// ★ 없으면: 판이 `ReversiRules.legalMoves` 로 점을 그려도(DEC:26 위반) 초록이다 — 진짜 판에서는 두 목록이 늘 같다.
    @Test
    func myTurnDotsFollowTheServerListNotTheRules() throws {
        let four = try rvBitmap(rvPanel(rvPlayingStore(legalMoves: [19, 26, 37, 44])))
        let one = try rvBitmap(rvPanel(rvPlayingStore(legalMoves: [19])))
        rvSave(four, "my-turn")
        rvSave(one, "my-turn-server-one-dot")

        let fourBlobs = rvDotBlobs(four), oneBlobs = rvDotBlobs(one)
        print("[내 차례] 점 덩어리: 서버 4칸 → \(fourBlobs.count) · 서버 1칸 → \(oneBlobs.count)")
        #expect(fourBlobs.count == 4, "서버가 준 합법 수 넷인데 점 \(fourBlobs.count)개")
        #expect(oneBlobs.count == 1, "서버가 [19] 만 줬는데 점 \(oneBlobs.count)개 — 판이 로컬 규칙으로 점을 그린다")
        // 그 한 점은 **d3(19) 칸** 안에 있다.
        let d3 = rvCellRect(19)
        #expect(oneBlobs.allSatisfy { d3.contains($0) }, "점이 d3 가 아닌 자리에 찍혔다: \(oneBlobs)")
        // 돌 잉크 = 판의 돌 수(시작 판 4개 — 백 d4·e5, 흑 e4·d5).
        for bitmap in [four, one] {
            let stones = rvStoneCells(bitmap)
            #expect(stones.white == [27, 36], "백 칸 \(stones.white)")
            #expect(stones.black == [28, 35], "흑 칸 \(stones.black)")
        }
    }

    /// 없으면: 상대 차례에도 점을 그려도 초록이다(서버는 내 차례에만 목록을 준다 — 스토어도 내 차례에만 연다).
    @Test
    func opponentTurnDrawsNoDots() throws {
        let theirs = try rvBitmap(rvPanel(rvPlayingStore(turn: .white, legalMoves: [19, 26, 37, 44])))
        rvSave(theirs, "their-turn")
        #expect(rvDotBlobs(theirs).isEmpty, "상대 차례인데 점이 찍혔다")
        #expect(rvStoneCells(theirs).count == 4)
        // 상태 상자 글자(값).
        let match = try #require(rvPlayingStore(turn: .white).match)
        #expect(ReversiMatchStatusText.headline(match, isAIThinking: false) == ReversiText.opponentTurn)
        let mine = try #require(rvPlayingStore().match)
        #expect(ReversiMatchStatusText.headline(mine, isAIThinking: false) == ReversiText.myTurn)
    }

    // MARK: ③ 돌 잉크 = 판의 돌 수

    /// ★ 없으면: 칸 색을 짙은 초록(최소 채널 ≤ 55)으로 바꿔 빈 칸이 돌로 세어지거나, 돌이 한 칸 밀려 그려져도 다른 시험은 초록이다.
    @Test
    func stoneInkMatchesTheBoardCellByCell() throws {
        // 시작 판에서 늘 가장 작은 합법 수를 두며(패스는 기록) 여러 장면을 만든다 — 결과가 다른 판 여럿이 같은 산식을 지난다.
        let game = rvGreedyGame(plies: 40)
        for cut in [6, 17, 31, game.plies.count] {
            let prefix = rvGreedyGame(plies: cut)
            let board = prefix.board
            let store = rvPlayingStore(board: board, turn: prefix.next ?? .black, legalMoves: [],
                                       plies: prefix.plies, lastStone: prefix.plies.last(where: { $0.kind == .stone })?.idx)
            let bitmap = try rvBitmap(rvPanel(store))
            if cut == 17 { rvSave(bitmap, "midgame") }
            let stones = rvStoneCells(bitmap)
            let expectedBlack = Set((0..<64).filter { board[$0] == .black })
            let expectedWhite = Set((0..<64).filter { board[$0] == .white })
            #expect(stones.black == expectedBlack, "[\(cut)수] 흑 칸이 판과 다르다: 그림 \(stones.black.sorted()) · 판 \(expectedBlack.sorted())")
            #expect(stones.white == expectedWhite, "[\(cut)수] 백 칸이 판과 다르다")
            #expect(stones.count == board.counts.black + board.counts.white)
            // SPEC §5.3 의 감지기(최대 ≥ 235 **또는** 최소 ≤ 55)로 세도 같다 — 칸·격자·점이 중간 톤이라는 규칙을 그림으로 잰다
            // (짙은 초록 칸이면 빈 칸이 전부 돌로 세어진다).
            let loose = Set((0..<64).filter {
                rvCount(bitmap, rect: rvCellProbe($0, origin: rvBodyOrigin, side: ReversiWindowLayout.boardSide),
                        where: rvIsExtremeStone) >= 40
            })
            #expect(loose == expectedBlack.union(expectedWhite), "[\(cut)수] 느슨한 감지기가 빈 칸을 돌로 센다: \(loose.subtracting(expectedBlack.union(expectedWhite)).sorted())")
        }
        // 판 색 상수 — 중간 톤(최소 채널 ≥ 56 · 최대 ≤ 234). 합법 수 점은 칸 위에 얹힌 합성색으로 잰다.
        for (label, color) in [("칸", ReversiBoardView.feltColor), ("격자", ReversiBoardView.lineColor),
                               ("좌표", ReversiBoardView.coordinateColor)] {
            let rgb = rvRGB(color)
            #expect(rgb.min() ?? 0 >= 56 && rgb.max() ?? 255 <= 234, "\(label) 색 \(rgb) 이 중간 톤이 아니다")
        }
        let felt = rvRGB(ReversiBoardView.feltColor), accent = rvRGB(ReversiBoardView.targetTint)
        let alpha = ReversiBoardView.targetOpacity
        let dot = zip(accent, felt).map { Int((Double($0) * alpha + Double($1) * (1 - alpha)).rounded()) }
        #expect(dot.min() ?? 0 >= 56 && dot.max() ?? 255 <= 234, "합법 수 점 합성색 \(dot) 이 중간 톤이 아니다")
        // 돌 색은 극단이다(감지기가 돌을 세는 근거).
        #expect(rvRGB(ReversiBoardView.blackStone).max() ?? 255 <= 55)
        #expect(rvRGB(ReversiBoardView.whiteStone).min() ?? 0 >= 235)
        // 기준선: 64칸이 다 찬 판(결과 화면)은 64 — 앞의 장면들과 갈린다.
        let full = try #require(ReversiBoard(string: rvF02After))
        let bitmap = try rvBitmap(rvPanel(rvFinishedStore(board: full, myColor: .black, result: .draw, reason: .boardFull)))
        #expect(rvStoneCells(bitmap).count == 64)
    }

    // MARK: ④ 패스 안내

    /// 없으면: 상대가 둘 곳이 없어 내 차례가 이어진 사실이 판에서 드러나지 않는데(돌이 안 바뀐다) 글자로도 안 말해도 초록이다.
    @Test
    func aPassIsSpokenInWords() throws {
        let passed = rvPassStore(lastIsPass: true)
        let plain = rvPassStore(lastIsPass: false)
        let match = try #require(passed.match)
        #expect(ReversiMatchStatusText.detail(match, notice: nil, opponentName: "민수")
                == ReversiNoticeText.opponentPassed(name: "민수"))
        #expect(ReversiMatchStatusText.detail(try #require(plain.match), notice: nil, opponentName: "민수") == nil)
        // 스토어 안내가 있으면 그것이 먼저다.
        #expect(ReversiMatchStatusText.detail(match, notice: ReversiNoticeText.autoPlaced, opponentName: "민수")
                == ReversiNoticeText.autoPlaced)
        // 내가 넘겼고 상대 차례면 "차례가 넘어가요".
        var mine = match
        mine.plies = [ReversiPly(seq: 1, color: .white, kind: .pass, idx: nil, flipped: [], auto: false)]
        mine.turn = .black
        #expect(ReversiMatchStatusText.passLine(mine, opponentName: "민수") == ReversiNoticeText.myPass)

        let withPass = try rvBitmap(rvPanel(passed))
        let without = try rvBitmap(rvPanel(plain))
        rvSave(withPass, "pass-notice")
        #expect(rvMaxChannelDifference(withPass, without, rect: rvStatusBoxRect) > 60, "패스 안내가 상태 상자에 안 그려졌다")
        // 수 목록의 "넘김" 줄도 그려진다(목록 칸이 다르다).
        #expect(rvMaxChannelDifference(withPass, without, rect: rvMoveListRect) > 60, "수 목록에 넘김 줄이 없다")
    }

    // MARK: ⑤ 뒤집기 직후

    /// ★ 없으면: 뒤집기 애니메이션이 불투명도를 깎아(이징) 돌이 사라지거나, 반을 지나기 전에 색을 바꾸거나, 다른 판의 애니메이션이
    /// 이 판으로 새도 초록이다.
    @Test
    func theFlipKeepsStonesExtremeAndSwapsColourAtHalfway() throws {
        // 시작 판에서 흑 d3(19) → d4(27) 가 뒤집힌다.
        let outcome = try #require(try? ReversiRules.play(.start, color: .black, idx: 19).get())
        #expect(outcome.flipped == [27])
        let started = rvNow
        func frame(_ offset: TimeInterval, matchID: String = "m-1") throws -> NSBitmapImageRep {
            let store = rvPlayingStore(board: outcome.board, turn: .white, legalMoves: [],
                                       plies: [ReversiPly(seq: 1, color: .black, kind: .stone, idx: 19, flipped: [27], auto: false)],
                                       lastStone: 19)
            store.flip = ReversiFlipAnimation(matchID: matchID, startedAt: started, placedIdx: 19, color: .black, flipped: [27])
            return try rvBitmap(rvPanel(store, now: started.addingTimeInterval(offset)))
        }
        let early = try frame(0.05)
        let beforeHalf = try frame(0.10)
        let afterHalf = try frame(0.25)
        let done = try frame(1.0)
        let stranger = try frame(0.05, matchID: "other-match")
        rvSave(early, "flip-early")
        rvSave(beforeHalf, "flip-before-half")
        rvSave(afterHalf, "flip-after-half")
        rvSave(done, "flip-done")

        for (label, bitmap) in [("직후", early), ("반 전", beforeHalf), ("반 뒤", afterHalf), ("끝", done)] {
            let stones = rvStoneCells(bitmap)
            #expect(stones.count == 5, "[\(label)] 뒤집히는 중에 돌 잉크가 \(stones.count)칸 — 불투명도·크기가 돌을 지웠다")
        }
        #expect(rvStoneCells(early).white.contains(27), "반을 지나기 전인데 d4 가 이미 흑이다")
        #expect(rvStoneCells(beforeHalf).white.contains(27))
        #expect(rvStoneCells(afterHalf).black.contains(27), "반을 지났는데 d4 가 아직 백이다")
        #expect(rvStoneCells(done).black.contains(27))
        // 기준선이 갈린다: 다른 판의 애니메이션은 이 판에 안 샌다 — 같은 시각인데 d4 는 판 그대로 흑.
        #expect(rvStoneCells(stranger).black.contains(27), "다른 판 id 의 애니메이션이 이 판을 뒤집었다")
        // 반 전에는 가로가 줄어든다(같은 칸의 잉크 폭이 끝 장면보다 좁다).
        #expect(rvStoneWidth(beforeHalf, idx: 27) < rvStoneWidth(done, idx: 27) - 10,
                "뒤집히는 돌의 가로 폭이 안 줄었다(반 전 \(rvStoneWidth(beforeHalf, idx: 27))px · 끝 \(rvStoneWidth(done, idx: 27))px)")
    }

    // MARK: ⑥ 결과

    /// 없으면: 결과 카드가 무승부에서 루비를 잃은 것처럼 말하거나, 기권·자리 비움 판에 WOF 점수를 지어내도 초록이다.
    @Test
    func resultCardsSayOutcomeReasonScoreAndRuby() throws {
        // 값: 루비 순수익 · 점수 줄(흑 : 백 고정).
        #expect(ReversiText.rubyLine(outcome: .won, stake: 5) == "+5")
        #expect(ReversiText.rubyLine(outcome: .lost, stake: 5) == "−5")
        #expect(ReversiText.rubyLine(outcome: .draw, stake: 5) == "0 · 판돈을 돌려받았어요")
        #expect(ReversiText.scoreLine(ReversiScore(black: 44, white: 20, result: .blackWin),
                                      counts: ReversiCounts(black: 40, white: 20, empty: 4)) == "44 : 20 (판 위 40 : 20)")
        #expect(ReversiText.scoreLine(ReversiScore(black: 50, white: 14, result: .blackWin),
                                      counts: ReversiCounts(black: 50, white: 14, empty: 0)) == "50 : 14")

        // ① 승 — 둘 다 둘 곳이 없어 끝(빈칸 60 은 이긴 흑 몫 → 63 : 1). 나는 흑.
        let e05 = try #require(ReversiBoard(string: rvE05))
        let won = rvFinishedStore(board: e05, myColor: .black, result: .blackWin, reason: .noMoves)
        // ② 패 — 내 돌(백)이 모두 뒤집혔다(B01 결과 판).
        let b01 = try #require(ReversiBoard(string: rvB01After))
        let lost = rvFinishedStore(board: b01, myColor: .white, result: .blackWin, reason: .wipeout)
        // ③ 무 — 판 가득 32 : 32, 판돈 환불.
        let f02 = try #require(ReversiBoard(string: rvF02After))
        let draw = rvFinishedStore(board: f02, myColor: .black, result: .draw, reason: .boardFull)
        // ④ abandoned — 상대가 자리 비움 3번(나 백 승). WOF 점수 없음.
        let mid = rvGreedyGame(plies: 20).board
        // ★ 점수 칸이 실려 와도(서버·스토어가 잘못 채워도) 자리 비움 판은 점수 줄을 쓰지 않는다 — 기준선이 갈리는 입력.
        let abandoned = rvFinishedStore(board: mid, myColor: .white, result: .whiteWin, reason: .abandoned,
                                        serverScore: ReversiScore(black: 20, white: 44, result: .whiteWin))

        let wonMatch = try #require(won.match)
        #expect(wonMatch.outcome == .won)
        #expect(ReversiResultCard.scoreText(wonMatch) == "흑 : 백  63 : 1 (판 위 3 : 1)")
        #expect(ReversiText.endReason(wonMatch.endReason, outcome: wonMatch.outcome) == "둘 다 둘 곳이 없어요")
        let lostMatch = try #require(lost.match)
        #expect(lostMatch.outcome == .lost)
        #expect(ReversiText.endReason(lostMatch.endReason, outcome: .lost) == "내 돌이 모두 뒤집혔어요")
        #expect(ReversiResultCard.scoreText(lostMatch) == "흑 : 백  64 : 0 (판 위 17 : 0)")
        let drawMatch = try #require(draw.match)
        #expect(drawMatch.outcome == .draw)
        #expect(ReversiResultCard.scoreText(drawMatch) == "흑 : 백  32 : 32")
        let abandonedMatch = try #require(abandoned.match)
        #expect(abandonedMatch.outcome == .won)
        #expect(ReversiText.endReason(abandonedMatch.endReason, outcome: .won) == "자리 비움 3번으로 끝났어요")
        #expect(ReversiResultCard.scoreText(abandonedMatch) == ReversiText.boardOnlyLine(mid.counts),
                "자리 비움 판에 WOF 점수를 지어냈다(V-15)")

        var bitmaps: [String: NSBitmapImageRep] = [:]
        for (name, store) in [("result-won", won), ("result-lost", lost), ("result-draw", draw),
                              ("result-abandoned", abandoned)] {
            let bitmap = try rvBitmap(rvPanel(store))
            rvSave(bitmap, name)
            bitmaps[name] = bitmap
            let board = try #require(store.match?.board)
            #expect(rvStoneCells(bitmap).count == board.counts.black + board.counts.white, "[\(name)] 돌 잉크가 판과 다르다")
            #expect(rvInk(bitmap, rect: rvResultCardRect) > 3_000, "[\(name)] 결과 카드가 비었다")
        }
        // 기준선이 갈린다: 승 카드와 패 카드는 같은 자리에 다른 글자·색을 그린다.
        let wonBitmap = try #require(bitmaps["result-won"]), lostBitmap = try #require(bitmaps["result-lost"])
        #expect(rvMaxChannelDifference(wonBitmap, lostBitmap, rect: rvResultCardRect) > 60)
        // 승 카드의 루비 줄은 초록(working) 글자다 — 패 카드에는 그 초록이 없다.
        #expect(rvGreen(wonBitmap, rect: rvResultCardRect) > rvGreen(lostBitmap, rect: rvResultCardRect) + 100)
    }

    // MARK: ⑦ 규칙 창

    /// 없으면: 규칙 줄이 빠지거나(8번 "리버시와 같은 규칙이에요") 예시 판이 규칙과 어긋나게 손으로 그려져도 초록이다.
    @Test
    func theRulesOverlayCarriesEightLinesAndFourExamples() throws {
        let lines = ReversiRulesOverlayLines.all
        try #require(lines.count == 8, "규칙 줄이 \(lines.count)개다(SPEC §5.7 은 여덟 줄)")
        #expect(lines[0].hasPrefix("흑이 먼저 둬요"))
        #expect(lines[4].contains("남은 빈칸은 이긴 쪽 점수에 더해요") && lines[4].contains("32 : 32"))
        #expect(lines[5].contains("30초") && lines[5].contains("3번"))
        #expect(lines[6].contains("무승부면") && lines[6].contains("돌려받아요"))
        #expect(lines[7].hasPrefix("리버시와 같은 규칙이에요"))

        let examples = ReversiRuleExample.all
        try #require(examples.map(\.id) == ["start", "lines", "pass", "end"])
        #expect(examples[0].dots == [19, 26, 37, 44])
        #expect(examples[1].flipped == [19, 20, 26, 27, 36, 45], "B02 의 세 방향 뒤집기와 다르다")
        #expect(examples[1].lastStone == 18)
        #expect(examples[2].dots == [2], "넘김 예시: 백의 둘 곳은 c1 하나다")
        #expect(ReversiRules.legalMoves(examples[2].board, color: .black).isEmpty, "넘김 예시에서 흑이 둘 곳이 있다")
        #expect(examples[3].detail.contains("63 : 1"))

        let store = rvLobbyStore()
        store.isRulesVisible = true
        let rules = try rvBitmap(rvPanel(store))
        let lobby = try rvBitmap(rvPanel(rvLobbyStore()))
        rvSave(rules, "rules")
        #expect(rvMaxChannelDifference(rules, lobby, rect: rvCenterRect) > 60, "규칙 창이 안 그려졌다")
        // 예시 판 한 장 한 장: 돌 잉크 = 그 판의 돌 수 · 점 덩어리 = 그 장면의 둘 곳 수(규칙 창이 그리는 바로 그 판 뷰).
        let side = ReversiWindowLayout.rulesExampleSide
        for example in examples {
            let tile = try rvBitmap(ReversiBoardView(
                board: example.board, geometry: ReversiBoardGeometry(side: side), legalTargets: example.dots,
                lastStoneIdx: example.lastStone, flippedMarks: example.flipped, showsCoordinates: false))
            let stones = rvStoneCells(tile, origin: .zero, side: side)
            #expect(stones.count == example.board.counts.black + example.board.counts.white,
                    "[\(example.id)] 예시 판 돌 잉크 \(stones.count) — 판 \(example.board.counts)")
            #expect(stones.black == Set((0..<64).filter { example.board[$0] == .black }), "[\(example.id)] 흑 칸이 다르다")
            let dots = rvDotBlobs(tile, rect: CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 1, dy: 1),
                                  minimumSize: 20)
            #expect(dots.count == example.dots.count, "[\(example.id)] 점 \(dots.count)개 · 둘 곳 \(example.dots.count)곳")
        }
    }

    // MARK: ⑧ 관전

    /// 없으면: 관전 판이 서버가 말한 색을 안 기다리고 로비 카드(a/b — 색 아님)로 색 배지를 지어내도, 관전 판의 돌이 안 그려져도 초록이다.
    @Test
    func spectateDrawsTheBoardAndBothSides() throws {
        let game = rvGreedyGame(plies: 23)
        let loaded = rvLobbyStore()
        loaded.spectating = ReversiSpectating(
            id: "live-1", faces: [rvMinsu, rvJunho], stake: 5, blackUser: rvJunho, whiteUser: rvMinsu,
            board: game.board, moveCount: game.plies.count, appliedSeq: game.plies.count, plies: game.plies,
            lastStoneIdx: game.plies.last(where: { $0.kind == .stone })?.idx, turn: game.next,
            turnStartedAt: rvNow.addingTimeInterval(-12), deadline: rvNow.addingTimeInterval(18),
            startedAt: rvNow.addingTimeInterval(-300), watchers: 3)
        loaded.spectatorCount = 3
        let seed = rvLobbyStore()
        seed.spectating = ReversiSpectating(id: "live-1", faces: [rvMinsu, rvJunho], stake: 5)

        let watch = try #require(loaded.spectating)
        let waiting = try #require(seed.spectating)
        #expect(ReversiWatchStatusText.headline(watch) == "\(ReversiText.stoneName(try #require(game.next))) 차례")
        #expect(ReversiWatchStatusText.headline(waiting) == ReversiText.watchLoading, "색이 서기 전에 차례를 말했다")

        let bitmap = try rvBitmap(rvPanel(loaded))
        let empty = try rvBitmap(rvPanel(seed))
        rvSave(bitmap, "spectate")
        rvSave(empty, "spectate-loading")
        #expect(rvStoneCells(bitmap).count == game.board.counts.black + game.board.counts.white)
        #expect(rvDotBlobs(bitmap).isEmpty, "관전 판에 둘 수 있는 칸 점이 찍혔다 — 관전자는 둘 수 없다")
        #expect(rvMaxChannelDifference(bitmap, empty, rect: rvMatchSideColumn) > 60)
        // 12줄이 넘는 수 목록도 카드 높이를 밀지 않는다 — 상태 상자와 수 기록 카드 사이 간격이 짧은 기록의 장면과 같다
        // (스냅샷 클립 갈래가 내용 높이를 부모로 흘리면 간격이 눌려 앱과 다른 그림이 된다).
        #expect(ReversiMoveLog.rows(game.plies).count > ReversiWindowLayout.moveVisibleRows)
        let short = rvGreedyGame(plies: 6)
        let shortStore = rvLobbyStore()
        var shortWatch = watch
        shortWatch.board = short.board
        shortWatch.plies = short.plies
        shortWatch.counts = short.board.counts
        shortStore.spectating = shortWatch
        shortStore.spectatorCount = 3
        let shortBitmap = try rvBitmap(rvPanel(shortStore))
        let gap = CGRect(x: rvMatchSideColumn.minX, y: rvStatusBoxRect.maxY + 4,
                         width: rvMatchSideColumn.width, height: 4)
        #expect(rvMaxChannelDifference(bitmap, shortBitmap, rect: gap) <= 8,
                "긴 수 기록이 카드를 밀어 올렸다 — 상태 상자와 수 기록 카드 사이 간격이 짧은 기록과 다르다")

        // 끝난 관전은 3인칭이다(내 기준 "기권했어요" 가 아니다).
        var finished = watch
        finished.isFinished = true
        finished.winner = .white
        finished.endReason = .resign
        #expect(ReversiWatchStatusText.headline(finished) == "백 승리")
        #expect(ReversiWatchStatusText.detail(finished, notice: nil) == "흑이 기권했어요")
    }

    // MARK: ⑨ AI

    /// 없으면: AI 색 고르기 창이 안 그려지거나(Menu 로 바꾸면 픽셀 0), AI 판이 서버 목록(빈 배열)을 따라 점을 안 그려도 초록이다.
    @Test
    func theAIPromptAndTheAIMatchDraw() throws {
        let prompt = try rvBitmap(rvPanel(rvLobbyStore(populated: false), previewAIPrompt: true))
        let lobby = try rvBitmap(rvPanel(rvLobbyStore(populated: false)))
        rvSave(prompt, "ai-color")
        #expect(rvMaxChannelDifference(prompt, lobby, rect: rvCenterRect) > 60, "AI 색 고르기 창이 안 그려졌다")

        // AI 판 — 사람(흑) 차례: 점은 **로컬 규칙**에서 온다(서버 목록이 비어 있어도 넷).
        let human = rvPlayingStore(legalMoves: [], isAI: true)
        let humanTurn = try rvBitmap(rvPanel(human))
        rvSave(humanTurn, "ai-match-my-turn")
        #expect(rvDotBlobs(humanTurn).count == 4, "AI 판인데 로컬 규칙 점이 안 그려졌다")
        // 기준선: 같은 판·같은 빈 서버 목록의 1:1 판은 점이 없다.
        let duel = try rvBitmap(rvPanel(rvPlayingStore(legalMoves: [])))
        #expect(rvDotBlobs(duel).isEmpty)

        // AI 차례 — "생각 중".
        let thinking = rvPlayingStore(turn: .white, legalMoves: [], isAI: true)
        #expect(thinking.isAIThinking)
        let thinkingBitmap = try rvBitmap(rvPanel(thinking))
        rvSave(thinkingBitmap, "ai-match-thinking")
        #expect(ReversiMatchStatusText.headline(try #require(thinking.match), isAIThinking: true) == ReversiText.aiThinking)
    }
}

// MARK: - 픽스처

private let rvNow = Date(timeIntervalSince1970: 1_793_660_908)

private func rvUser(_ name: String, _ suffix: Int, working: Bool = true, capable: Bool = true, inMatch: Bool = false,
                    focus: Bool = false, character: String? = "shiba") -> ReversiUser {
    ReversiUser(id: "00000000-0000-0000-0000-\(String(format: "%012d", suffix))", displayName: name,
                characterID: character, isWorking: working, isCapable: capable, inMatch: inMatch, focusMode: focus)
}

private let rvMinsu = rvUser("민수", 11, character: "fox")
private let rvJunho = rvUser("준호", 12, character: "squirrel")
private let rvMe = ReversiPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba",
                                     userID: "00000000-0000-0000-0000-000000000013")

private func rvUsers() -> [ReversiUser] {
    [
        rvUser("지영", 14, working: false),
        rvMinsu,
        rvUser("태화", 15, inMatch: true),
        rvUser("옛버전사용자", 16, capable: false),
        rvJunho,
        rvUser("서연", 17, focus: true, character: "ghost"),
        rvUser("하늘", 18, working: false),
        rvUser("가장긴별명열두글자입니다", 19)
    ]
}

/// 코퍼스 판(research/cases.json — 64자 '.bw').
private let rvE05 = "bbb" + String(repeating: ".", count: 53) + "w......."
private let rvB01After = "..................b.b.b....bbb....bbbbb....bbb....b.b.b........."
private let rvF02After = "bbbbbbbbbbbbbbbbbbbbbbbbbbbwwwwwwwwwwwwwwwwwwwwwwwwwwwbbwwwwwbbb"

@MainActor
private func rvLobbyStore(populated: Bool = true) -> ReversiStore {
    let store = ReversiStore(clock: { rvNow })
    store.rubyBalance = 42
    store.record = ReversiRecord(wins: 7, losses: 3, draws: 1)
    guard populated else { return store }
    store.users = rvUsers()
    store.liveMatches = [
        ReversiLiveMatch(id: "live-1", a: rvMinsu, b: rvJunho, stake: 5, startedAt: rvNow.addingTimeInterval(-300),
                         watchers: 2),
        ReversiLiveMatch(id: "live-2", a: rvUser("서연", 17), b: rvUser("바다", 20), stake: 10,
                         startedAt: rvNow.addingTimeInterval(-120)),
        ReversiLiveMatch(id: "live-3", a: rvUser("산", 21), b: rvUser("하늘", 18), stake: 3,
                         startedAt: rvNow.addingTimeInterval(-60))
    ]
    store.incoming = [ReversiInvite(id: "in-1", peer: rvMinsu, stake: 5, expiresAt: Date().addingTimeInterval(48))]
    store.outgoing = ReversiOutgoing(id: "out-1", peer: rvJunho, stake: 10, expiresAt: Date().addingTimeInterval(31))
    store.ranking = ReversiRanking(
        entries: (rvUsers() + [rvUser("영식", 13)]).enumerated().map { index, user in
            ReversiRankEntry(id: user.id, rank: index + 1, user: user, wins: 12 - index, losses: index, draws: 1,
                             points: 12 - index * 2)
        },
        me: ReversiMyRank(rank: 4, wins: 7, losses: 3, draws: 1, points: 4),
        recordSince: Date(timeIntervalSince1970: 1_780_000_000))
    return store
}

/// 대국 중 가게. 기본은 시작 판 · 나 흑 · 흑 차례 · 서버 합법 수 넷 · 마감 21초 남음(30초 링 · `previewNow` 기준).
@MainActor
private func rvPlayingStore(
    board: ReversiBoard = .start, myColor: ReversiColor = .black, turn: ReversiColor = .black,
    legalMoves: [Int] = [19, 26, 37, 44], plies: [ReversiPly] = [], lastStone: Int? = nil,
    isAI: Bool = false
) -> ReversiStore {
    let store = ReversiStore(clock: { rvNow })
    store.phase = .playing
    store.rubyBalance = 32
    store.record = ReversiRecord(wins: 7, losses: 3, draws: 1)
    let humanTurn = turn == myColor
    store.match = ReversiMatchState(
        id: isAI ? "ai-render-1" : "m-1", isAI: isAI, stake: isAI ? 0 : 5, myColor: myColor, opponent: rvMinsu,
        blackUser: myColor == .black ? nil : rvMinsu, whiteUser: myColor == .white ? nil : rvMinsu,
        board: board, moveCount: plies.count, turn: turn, turnStartedAt: rvNow.addingTimeInterval(-9),
        deadline: (isAI && !humanTurn) ? nil : rvNow.addingTimeInterval(21),
        legalMoves: humanTurn ? legalMoves : (isAI ? [] : legalMoves), plies: plies, lastStoneIdx: lastStone)
    return store
}

/// 패스 장면: 나 백 · 상대(민수, 흑)가 둘 곳이 없어 넘겼고 다시 내 차례(코퍼스 E02 판).
@MainActor
private func rvPassStore(lastIsPass: Bool) -> ReversiStore {
    var plies = [
        ReversiPly(seq: 1, color: .black, kind: .stone, idx: 1, flipped: [], auto: false),
        ReversiPly(seq: 2, color: .white, kind: .stone, idx: 0, flipped: [], auto: true)
    ]
    if lastIsPass { plies.append(ReversiPly(seq: 3, color: .black, kind: .pass, idx: nil, flipped: [], auto: false)) }
    let store = rvPlayingStore(board: ReversiBoard(string: "wb" + String(repeating: ".", count: 62)) ?? .start,
                               myColor: .white, turn: .white, legalMoves: [2], plies: plies, lastStone: 0)
    store.match?.autoStones = [0]
    store.match?.myAutoStreak = 1
    return store
}

/// 끝난 판 가게(결과 화면).
@MainActor
private func rvFinishedStore(board: ReversiBoard, myColor: ReversiColor, result: ReversiResult,
                             reason: ReversiEndReason, serverScore: ReversiScore? = nil) -> ReversiStore {
    let store = ReversiStore(clock: { rvNow })
    store.phase = .result
    store.rubyBalance = 47
    // WOF 점수는 자연 종료에만 있다(기권·자리 비움은 nil, V-15).
    let natural = reason == .wipeout || reason == .boardFull || reason == .noMoves
    let resolvedScore: ReversiScore? = serverScore ?? (natural ? ReversiRules.score(board) : nil)
    let game = rvGreedyGame(plies: 12)
    store.match = ReversiMatchState(
        id: "m-done", status: .finished, stake: 5, myColor: myColor, opponent: rvMinsu, board: board,
        moveCount: game.plies.count, turn: nil, plies: game.plies, lastStoneIdx: nil, score: resolvedScore,
        result: result, endReason: reason, winner: result.winner)
    return store
}

/// 시작 판에서 늘 가장 작은 합법 수를 둔다(패스는 기록). 결정적 장면 생성기.
private func rvGreedyGame(plies count: Int) -> (board: ReversiBoard, plies: [ReversiPly], next: ReversiColor?) {
    var board = ReversiBoard.start
    var color: ReversiColor? = .black
    var plies: [ReversiPly] = []
    while plies.count < count, let mover = color {
        guard let idx = ReversiRules.legalMoves(board, color: mover).first,
              case .success(let outcome) = ReversiRules.play(board, color: mover, idx: idx) else { break }
        plies.append(ReversiPly(seq: plies.count + 1, color: mover, kind: .stone, idx: idx,
                                flipped: outcome.flipped, auto: false))
        if outcome.passed {
            plies.append(ReversiPly(seq: plies.count + 1, color: mover.opponent, kind: .pass, idx: nil,
                                    flipped: [], auto: false))
        }
        board = outcome.board
        color = outcome.next
    }
    return (board, plies, color)
}

@MainActor
private func rvPanel(_ store: ReversiStore, now: Date = rvNow, previewStakeTarget: ReversiUser? = nil,
                     previewStakeSelection: ReversiStake? = nil, previewAIPrompt: Bool = false) -> some View {
    ReversiPanel(store: store, me: { rvMe }, clipsOverflowInsteadOfScroll: true,
                 previewStakeTarget: previewStakeTarget, previewStakeSelection: previewStakeSelection,
                 previewAIPrompt: previewAIPrompt, previewNow: now)
}

// MARK: - 창 좌표(레이아웃 상수에서만 뽑는다)

private var rvBodyOrigin: CGPoint {
    CGPoint(x: ReversiWindowLayout.contentPadding,
            y: ReversiWindowLayout.contentPadding + ReversiWindowLayout.headerHeight + ReversiWindowLayout.headerSpacing)
}

private var rvBoardRect: CGRect {
    CGRect(origin: rvBodyOrigin, size: CGSize(width: ReversiWindowLayout.boardSide, height: ReversiWindowLayout.boardSide))
}

private var rvMatchSideColumn: CGRect {
    CGRect(x: rvBodyOrigin.x + ReversiWindowLayout.boardSide + ReversiWindowLayout.columnSpacing, y: rvBodyOrigin.y,
           width: ReversiWindowLayout.sideColumnWidth, height: ReversiWindowLayout.bodyHeight)
}

/// 상태 상자(판돈 칩 오른쪽, 카드 둘 아래).
private var rvStatusBoxRect: CGRect {
    let column = rvMatchSideColumn
    let top = column.minY + (ReversiWindowLayout.playerCardHeight + ReversiWindowLayout.matchSideSpacing) * 2
    let left = column.minX + ReversiWindowLayout.stakeChipWidth + ReversiWindowLayout.matchSideSpacing
    return CGRect(x: left, y: top, width: column.maxX - left, height: ReversiWindowLayout.stakeStatusMinHeight)
}

/// 돌 수·수 기록 카드의 목록 자리(제목 줄 아래).
private var rvMoveListRect: CGRect {
    let column = rvMatchSideColumn
    let top = rvStatusBoxRect.maxY + ReversiWindowLayout.matchSideSpacing + ReversiWindowLayout.cardPadding
        + ReversiWindowLayout.moveHeaderHeight + ReversiWindowLayout.moveHeaderSpacing
    return CGRect(x: column.minX, y: top, width: column.width, height: ReversiWindowLayout.moveListInnerHeight)
}

/// 결과 화면 오른쪽 열 위쪽(결과 카드 자리).
private var rvResultCardRect: CGRect {
    let column = rvMatchSideColumn
    return CGRect(x: column.minX, y: column.minY, width: column.width, height: 150)
}

private var rvLobbyUsersColumn: CGRect {
    CGRect(x: rvBodyOrigin.x, y: rvBodyOrigin.y, width: ReversiWindowLayout.lobbyUsersWidth,
           height: ReversiWindowLayout.bodyHeight)
}

private var rvLobbyRankColumn: CGRect {
    CGRect(x: rvLobbyUsersColumn.maxX + ReversiWindowLayout.columnSpacing, y: rvBodyOrigin.y,
           width: ReversiWindowLayout.lobbyRankWidth, height: ReversiWindowLayout.bodyHeight)
}

private var rvLobbySideColumn: CGRect {
    CGRect(x: rvLobbyRankColumn.maxX + ReversiWindowLayout.columnSpacing, y: rvBodyOrigin.y,
           width: ReversiWindowLayout.lobbySideWidth, height: ReversiWindowLayout.bodyHeight)
}

/// 창 가운데(가운데 작은 창 자리).
private var rvCenterRect: CGRect {
    let size = ReversiWindowLayout.contentSize
    return CGRect(x: size.width / 2 - 170, y: size.height / 2 - 120, width: 340, height: 240)
}

/// 그 칸의 창 좌표 사각형(기본은 대국 판 — 규칙 창 예시 판은 원점·한 변을 넘긴다).
private func rvCellRect(_ idx: Int, origin: CGPoint = rvBodyOrigin,
                        side: CGFloat = ReversiWindowLayout.boardSide) -> CGRect {
    ReversiBoardGeometry(side: side).rect(idx: idx).offsetBy(dx: origin.x, dy: origin.y)
}

/// 칸 가운데 50% 상자(돌 잉크를 세는 자리 — 격자선·좌표 글자를 뺀다).
private func rvCellProbe(_ idx: Int, origin: CGPoint, side: CGFloat) -> CGRect {
    let box = rvCellRect(idx, origin: origin, side: side)
    return box.insetBy(dx: box.width * 0.25, dy: box.height * 0.25)
}

// MARK: - 감지기

private struct RVStones {
    var black: Set<Int> = []
    var white: Set<Int> = []
    var count: Int { black.count + white.count }
    var isEmpty: Bool { count == 0 }
}

private func rvIsExtremeStone(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    max(r, max(g, b)) >= 235 || min(r, min(g, b)) <= 55
}

/// 칸마다 가운데 상자에 **극단 픽셀**이 40개 이상이면 돌 — 아주 어두우면(최대 ≤ 55) 흑, 아주 밝으면(최소 ≥ 235) 백.
private func rvStoneCells(_ bitmap: NSBitmapImageRep, origin: CGPoint = rvBodyOrigin,
                          side: CGFloat = ReversiWindowLayout.boardSide) -> RVStones {
    var stones = RVStones()
    for idx in 0..<64 {
        let probe = rvCellProbe(idx, origin: origin, side: side)
        let dark = rvCount(bitmap, rect: probe) { r, g, b in max(r, max(g, b)) <= 55 }
        let light = rvCount(bitmap, rect: probe) { r, g, b in min(r, min(g, b)) >= 235 }
        if dark >= 40 && dark >= light { stones.black.insert(idx) }
        else if light >= 40 { stones.white.insert(idx) }
    }
    return stones
}

/// 그 칸 가운데 줄(가로)에서 극단 픽셀이 이어진 폭(px). 뒤집히는 돌의 가로 비율을 잰다.
private func rvStoneWidth(_ bitmap: NSBitmapImageRep, idx: Int) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let box = rvCellRect(idx)
    let y = Int(box.midY * 2)
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var width = 0
    for x in Int(box.minX * 2)..<Int(box.maxX * 2) {
        let o = y * bpr + x * spp
        if rvIsExtremeStone(Int(data[o]), Int(data[o + 1]), Int(data[o + 2])) { width += 1 }
    }
    return width
}

/// 판 안 **합법 수 점** 덩어리(연결 성분)의 중심들(창 좌표 pt). 점 색은 accent 0.60 이 초록 위에 얹힌 (83,162,196) 근처 —
/// 파랑이 초록보다 20 이상 높은 픽셀이다(칸 초록 · 돌 · 좌표 글자 · 빨간 점은 어느 것도 이 조건에 안 든다).
private func rvDotBlobs(_ bitmap: NSBitmapImageRep, rect: CGRect = rvBoardRect.insetBy(dx: 4, dy: 4),
                        minimumSize: Int = 60) -> [CGPoint] {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return [] }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = Int(rect.minX * 2), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = Int(rect.minY * 2), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    let w = x1 - x0 + 1, h = y1 - y0 + 1
    var mask = [Bool](repeating: false, count: w * h)
    for y in 0..<h {
        for x in 0..<w {
            let o = (y + y0) * bpr + (x + x0) * spp
            let r = Int(data[o]), g = Int(data[o + 1]), b = Int(data[o + 2])
            mask[y * w + x] = b >= 170 && b >= g + 20 && r <= 140
        }
    }
    var seen = [Bool](repeating: false, count: w * h)
    var centers: [CGPoint] = []
    for start in 0..<(w * h) where mask[start] && !seen[start] {
        var stack = [start]
        seen[start] = true
        var size = 0, sumX = 0, sumY = 0
        while let p = stack.popLast() {
            size += 1
            let px = p % w, py = p / w
            sumX += px; sumY += py
            for (nx, ny) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)]
            where nx >= 0 && ny >= 0 && nx < w && ny < h {
                let n = ny * w + nx
                if mask[n] && !seen[n] { seen[n] = true; stack.append(n) }
            }
        }
        if size >= minimumSize {
            centers.append(CGPoint(x: (CGFloat(sumX) / CGFloat(size) + CGFloat(x0)) / 2,
                                   y: (CGFloat(sumY) / CGFloat(size) + CGFloat(y0)) / 2))
        }
    }
    return centers
}

/// 사각형(pt) 안의 **잉크** 픽셀 수 — 유채색(채널 폭 ≥ 40)이거나 밝은 글자(최대 ≥ 150).
private func rvInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    rvCount(bitmap, rect: rect) { r, g, b in
        let high = max(r, max(g, b)), low = min(r, min(g, b))
        return (high - low) >= 40 || high >= 150
    }
}

/// 사각형(pt) 안 초록 잉크(`CheckTheme.working` 글자) 픽셀 수. accent(파랑)는 `g > b + 30` 으로 뺀다.
private func rvGreen(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    rvCount(bitmap, rect: rect) { r, g, b in g > r + 80 && g > b + 30 && g > 150 }
}

private func rvCount(_ bitmap: NSBitmapImageRep, rect: CGRect, where predicate: (Int, Int, Int) -> Bool) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var hits = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if predicate(Int(data[o]), Int(data[o + 1]), Int(data[o + 2])) { hits += 1 }
        }
    }
    return hits
}

/// 사각형(pt) 안에서 두 비트맵의 채널 최대 차(0 이면 한 바이트도 다르지 않다).
private func rvMaxChannelDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> Int {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData,
          lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return 255 }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(lhs.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(lhs.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 255 }
    var worst = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let offset = y * bpr + x * spp
            for channel in 0..<min(3, spp) {
                worst = max(worst, abs(Int(a[offset + channel]) - Int(b[offset + channel])))
            }
        }
    }
    return worst
}

/// SwiftUI 색 → sRGB 0~255 세 채널.
private func rvRGB(_ color: Color) -> [Int] {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return [0, 0, 0] }
    return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int(($0 * 255).rounded()) }
}

private enum RVRenderError: Error { case failed }

/// 굳힌 비트맵(scale 2). 같은 내용의 첫 두 장이 다르게 구워지는 ImageRenderer 버릇을 `CheckRenderSettle` 이 걷어낸다.
@MainActor
private func rvBitmap(_ view: some View) throws -> NSBitmapImageRep {
    guard let bitmap = CheckRenderSettle.bitmap(view.fixedSize(), scale: 2) else { throw RVRenderError.failed }
    return bitmap
}

private func rvSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    MiniGameSnapshots.save(bitmap, name: "\(name).png", sub: "reversi")
}
