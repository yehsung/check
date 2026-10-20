import Foundation
import Testing
@testable import CheckCore

// v0.3.60 테트리스 1:1 — **솔로 골든**(엔진을 고치기 전에 박았다).
//
// 대결 확장(방해 줄 대기열·상쇄·삽입·탑아웃 · 따로 도는 방해 줄 난수 · 공격 누계 · 레벨 바닥)은 전부 `TetrisGame` 안에
// 들어간다(`board` 가 private(set) 이라 래퍼로는 줄을 밀어 넣을 수 없다). 그 대가로 솔로 판이 **한 비트라도** 움직이면
// 순위표·서버 시간 하한(`minigame_min_seconds`)이 기대는 엔진이 바뀐 것이다. 기존 테스트들은 규칙을 조각조각 재지만
// "판 전체가 그대로"를 박은 단일 기준은 없었다 — 이 파일이 그 기준이다.
//
// 재는 법: 고정 시드 + 대본 조종사(자리 고르기 · DAS 누름 · 탭 이동 · 회전 양방향 · 홀드 · 소프트드롭 · 중력 굳힘 · 하드드롭)를
// 2의 거듭제곱 dt 로 N프레임 돌려 **매 프레임** 관측 상태를 해시에 접고, 판은 굳을 때마다 접는다. 끝 상태(판·점수·advance·
// 줄·넥스트·단계)는 글자로도 박아 실패 메시지가 무엇이 갈렸는지 말하게 한다.
//
// ⚠️ 여기 박힌 값은 **이 맥(arm64)에서 대결 확장 전 엔진이 낸 값**이다. 중력은 `pow` 를 쓰므로 다른 아키텍처의 libm 에서는
//    마지막 ulp 가 다를 수 있다(추정 — 확인한 적 없다). 이 저장소의 테스트는 이 맥에서만 돈다.
// ⚠️ 값을 고쳐 초록으로 만들지 마라. 솔로 판이 바뀌었다는 뜻이다 — 바꾼 것이 의도라면 서버 하한·순위표 영향부터 따져라.

private typealias GoldPiece = TetrisGame.Piece

/// FNV-1a 64. 프레임마다 관측 상태를 접는다(테스트 전용 · 결정적).
private struct GoldHasher {
    private(set) var value: UInt64 = 0xCBF2_9CE4_8422_2325

    mutating func add(_ x: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            value ^= (x >> UInt64(shift)) & 0xFF
            value &*= 0x0000_0100_0000_01B3
        }
    }

    mutating func add(_ x: Int) { add(UInt64(bitPattern: Int64(x))) }
    mutating func add(_ x: Double) { add(x.bitPattern) }
    mutating func add(_ x: Bool) { add(x ? 1 : 0) }
}

/// 대결 확장 **전부터 있던** 관측 칸만 접는다(새 칸은 일부러 안 본다 — 솔로에서 그대로인지가 관심사다).
private func goldFoldLight(_ g: TetrisGame, into h: inout GoldHasher) {
    if let a = g.active {
        h.add(a.piece.rawValue); h.add(a.rotation.rawValue); h.add(a.column); h.add(a.row)
    } else {
        h.add(-1)
    }
    h.add(g.next.count)
    for p in g.next { h.add(p.rawValue) }
    h.add(g.heldPiece?.rawValue ?? -1)
    h.add(g.holdUsed)
    h.add(g.score); h.add(g.advance); h.add(g.lines); h.add(g.combo); h.add(g.backToBack)
    switch g.phase {
    case .ready: h.add(0)
    case .running: h.add(1)
    case .lineClear(let left): h.add(2); h.add(left)
    case .are(let left): h.add(3); h.add(left)
    case .over(let hold): h.add(4); h.add(hold)
    case .result: h.add(5)
    }
    h.add(g.elapsed)
    if let c = g.lastClear {
        h.add(c.lines)
        switch c.spin {
        case .none: h.add(0)
        case .mini: h.add(1)
        case .full: h.add(2)
        }
        h.add(c.backToBack); h.add(c.perfectClear); h.add(c.points); h.add(c.at)
    } else {
        h.add(-2)
    }
    h.add(g.level); h.add(g.scoreLevel); h.add(g.isGrounded)
}

private func goldFoldBoard(_ g: TetrisGame, into h: inout GoldHasher) {
    for row in g.board {
        for cell in row { h.add(cell?.rawValue ?? -1) }
    }
}

/// 판 전체를 글자로(행 0 = 맨 위). 빈 행은 접어서 "바닥에서 몇 행"만 남긴다.
private func goldBoardText(_ g: TetrisGame) -> String {
    let letters: [GoldPiece: Character] = [.i: "I", .j: "J", .l: "L", .o: "O", .s: "S", .t: "T", .z: "Z"]
    var rows: [String] = []
    for row in g.board {
        rows.append(String(row.map { $0.map { letters[$0]! } ?? "." }))
    }
    while let first = rows.first, first == ".........." { rows.removeFirst() }
    return rows.joined(separator: "/")
}

private func goldPhaseText(_ phase: TetrisGame.Phase) -> String {
    switch phase {
    case .ready: return "ready"
    case .running: return "running"
    case .lineClear: return "lineClear"
    case .are: return "are"
    case .over: return "over"
    case .result: return "result"
    }
}

// MARK: - 대본 조종사

/// 판의 나쁨(낮을수록 좋다) — 시뮬레이션 테스트(GamesMiniGameSimulationTests)와 같은 고전 가중치.
private func goldBoardCost(_ board: [[GoldPiece?]]) -> Double {
    var heights = [Int](repeating: 0, count: TetrisGame.columns)
    var holes = 0
    for column in 0..<TetrisGame.columns {
        var covered = false
        for row in 0..<TetrisGame.totalRows {
            if board[row][column] != nil {
                if !covered { covered = true; heights[column] = TetrisGame.totalRows - row }
            } else if covered {
                holes += 1
            }
        }
    }
    let bumpiness = zip(heights, heights.dropFirst()).reduce(0) { $0 + abs($1.0 - $1.1) }
    return Double(heights.reduce(0, +)) * 0.51 + Double(holes) * 3.6
        + Double(bumpiness) * 0.18 + Double(heights.max() ?? 0) * 0.5
}

/// 복제본에 실제로 떨어뜨려 보고 (시계 회전 수, 왼쪽 끝 열)을 고른다. 규칙만 쓰는 순수 계산이다.
private func goldBestPlacement(_ game: TetrisGame) -> (turns: Int, column: Int)? {
    guard game.active != nil else { return nil }
    var best: (turns: Int, column: Int)?
    var bestCost = Double.infinity
    for turns in 0..<4 {
        for column in 0..<TetrisGame.columns {
            var probe = game
            for _ in 0..<turns { probe.rotate(clockwise: true) }
            guard let piece = probe.active else { continue }
            let leftmost = piece.cells.map { $0.column }.min() ?? 0
            for _ in 0..<abs(column - leftmost) {
                if column < leftmost {
                    probe.setLeftHeld(true); probe.setLeftHeld(false)
                } else {
                    probe.setRightHeld(true); probe.setRightHeld(false)
                }
            }
            guard probe.active?.cells.map({ $0.column }).min() == column else { continue }
            let before = probe.lines
            probe.action()
            let cost = goldBoardCost(probe.board) - 12 * Double(probe.lines - before)
            if cost < bestCost { bestCost = cost; best = (turns, column) }
        }
    }
    return best
}

private struct GoldRun {
    var game: TetrisGame
    var hash: UInt64
    var frames: Int
    var pieces: Int
    var holds: Int
    var softDropPieces: Int
    var gravityLocks: Int
    var maxLevel: Int
}

/// 대본 판 하나. 조각마다 `pieces % 4` 로 마무리를 바꾼다:
/// 0 = 하드드롭 · 1 = 소프트드롭 누른 채 굳힘 · 2 = 손 떼고 중력·락딜레이로 굳힘 · 3 = 홀드 뒤 하드드롭.
/// 조작은 `actEvery` 프레임에 한 번(회전은 세 번 돌 자리를 반시계 한 번으로), 이동은 방향키를 **누른 채**(DAS·ARR) 두고
/// 목표 열에 닿는 프레임에 뗀다 — 판 시계를 읽는 다섯 자리(중력·소프트드롭·락딜레이·리셋 한도·재충전)를 모두 지난다.
private func goldPlay(seed: UInt64, dt: Double, maxFrames: Int, actEvery: Int) -> GoldRun {
    var g = TetrisGame(seed: seed)
    g.action()
    return goldPlay(from: g, dt: dt, maxFrames: maxFrames, actEvery: actEvery)
}

/// 높은 레벨에서 시작하는 판 — 픽스처 init(대결 확장 전부터 있던 모양)으로 advance 를 올려 둔 빈 판의 텀에서 출발한다.
/// 조종사가 바닥 레벨에서 L10 남짓에 죽어도, 20G·락딜레이 보간·리셋 한도 감소·재충전 끄기(L>15)를 여기서 지난다.
private func goldPlayFromAdvance(_ advance: Int, seed: UInt64, dt: Double, maxFrames: Int, actEvery: Int) -> GoldRun {
    let g = TetrisGame(seed: seed, board: TetrisGame.emptyBoard(), active: nil,
                       phase: .are(remaining: TetrisGame.areSeconds), advance: advance)
    return goldPlay(from: g, dt: dt, maxFrames: maxFrames, actEvery: actEvery)
}

private func goldPlay(from start: TetrisGame, dt: Double, maxFrames: Int, actEvery: Int) -> GoldRun {
    var g = start
    var h = GoldHasher()
    var pieces = 0, holds = 0, softDropPieces = 0, gravityLocks = 0, maxLevel = 1
    var plan: (turns: Int, column: Int)?
    var planAdvance = -1
    var planHeld = false
    var mode = 0
    var frame = 0
    goldFoldBoard(g, into: &h)
    while frame < maxFrames {
        frame += 1
        let advanceBefore = g.advance
        if case .running = g.phase, let active = g.active {
            if g.advance != planAdvance || g.holdUsed != planHeld {
                if g.advance != planAdvance {
                    pieces += 1
                    mode = pieces % 4
                    g.setSoftDropHeld(false)
                }
                planAdvance = g.advance
                planHeld = g.holdUsed
                plan = goldBestPlacement(g)
            }
            let leftmost = active.cells.map { $0.column }.min() ?? 0
            let actNow = frame % actEvery == 0
            if mode == 3, !g.holdUsed, actNow {
                g.holdCurrentPiece()
                holds += 1
            } else if let p = plan, p.turns > 0, actNow {
                let before = active.rotation
                if p.turns == 3 {
                    g.rotate(clockwise: false)
                    plan = (0, p.column)
                } else {
                    g.rotate(clockwise: true)
                    plan = (p.turns - 1, p.column)
                }
                if g.active?.rotation == before { plan = (0, p.column) }
            } else if let p = plan, p.turns == 0, leftmost != p.column {
                if leftmost > p.column {
                    if actNow { g.setRightHeld(false); g.setLeftHeld(true) }
                } else {
                    if actNow { g.setLeftHeld(false); g.setRightHeld(true) }
                }
            } else {
                g.setLeftHeld(false)
                g.setRightHeld(false)
                if actNow {
                    switch mode {
                    case 1:
                        g.setSoftDropHeld(true)
                    case 2:
                        break
                    default:
                        g.action()
                    }
                }
            }
            // 이동 중 목표에 닿았으면 그 프레임에 뗀다(ARR 이 지나치지 않게).
            if let now = g.active, let p = plan, p.turns == 0,
               (now.cells.map { $0.column }.min() ?? 0) == p.column {
                g.setLeftHeld(false)
                g.setRightHeld(false)
            }
        }
        g.step(dt: dt)
        goldFoldLight(g, into: &h)
        if g.advance != advanceBefore {
            goldFoldBoard(g, into: &h)
            if mode == 1 { softDropPieces += 1 }
            if mode == 2 { gravityLocks += 1 }
        }
        maxLevel = max(maxLevel, g.level)
        if case .result = g.phase { break }
    }
    return GoldRun(game: g, hash: h.value, frames: frame, pieces: pieces, holds: holds,
                   softDropPieces: softDropPieces, gravityLocks: gravityLocks, maxLevel: maxLevel)
}

/// 7-bag 순서 N장 — 엔진이 쓰는 섞기(`shuffledBag`)를 시드 그대로 이어 붙인 것과, 엔진이 첫 프레임에 내놓은
/// 활성 + 넥스트 여섯 장이 그 앞머리와 같은지를 함께 본다.
private func goldPieceSequence(seed: UInt64, count: Int) -> (bags: String, engineHead: String) {
    let letters: [GoldPiece: Character] = [.i: "I", .j: "J", .l: "L", .o: "O", .s: "S", .t: "T", .z: "Z"]
    var rng = MiniGameRandom(seed: seed)
    var bags = ""
    while bags.count < count {
        for p in TetrisGame.shuffledBag(&rng) { bags.append(letters[p]!) }
    }
    var g = TetrisGame(seed: seed)
    g.action()
    var head = ""
    if let a = g.active { head.append(letters[a.piece]!) }
    for p in g.next { head.append(letters[p]!) }
    return (String(bags.prefix(count)), head)
}

/// 박아 둔 끝 상태 한 벌.
private struct GoldExpected {
    var hash: String
    var score: Int
    var advance: Int
    var lines: Int
    var next: [Int]
    var phase: String
    var held: Int
    var elapsedBits: String
    var board: String
}

private func goldExpect(_ run: GoldRun, _ label: String, _ e: GoldExpected) {
    let g = run.game
    print("[gold] \(label) frames=\(run.frames) pieces=\(run.pieces) holds=\(run.holds) soft=\(run.softDropPieces) gravity=\(run.gravityLocks) maxLevel=\(run.maxLevel) hash=\(String(run.hash, radix: 16))")
    #expect(g.board.count == TetrisGame.totalRows)
    #expect(goldBoardText(g) == e.board, "\(label): 끝 판이 갈렸다 — \(goldBoardText(g))")
    #expect(g.score == e.score, "\(label): 점수 \(g.score) ≠ \(e.score)")
    #expect(g.advance == e.advance, "\(label): advance \(g.advance) ≠ \(e.advance)")
    #expect(g.lines == e.lines, "\(label): 줄 \(g.lines) ≠ \(e.lines)")
    #expect(g.next.map(\.rawValue) == e.next, "\(label): 넥스트 \(g.next.map(\.rawValue)) ≠ \(e.next)")
    #expect(goldPhaseText(g.phase) == e.phase, "\(label): 단계 \(goldPhaseText(g.phase)) ≠ \(e.phase)")
    #expect((g.heldPiece?.rawValue ?? -1) == e.held, "\(label): 홀드 칸이 갈렸다")
    #expect(String(g.elapsed.bitPattern, radix: 16) == e.elapsedBits, "\(label): 판 시계 비트가 갈렸다(\(g.elapsed))")
    // 해시는 매 프레임 관측 칸 + 굳을 때마다 판 전체다 — 끝 상태가 같아도 도중이 갈리면 여기서 빨개진다.
    #expect(String(run.hash, radix: 16) == e.hash, "\(label): 매 프레임 해시가 갈렸다 — 도중 어딘가에서 판이 달라졌다")
}

@Suite("v0.3.60 솔로 골든 — 대결 확장 전 엔진이 낸 판을 비트 단위로 박는다")
struct V0360TetrisSoloGoldenTests {

    @Test("대본 A(1/64초 · 4프레임마다 손) — 끝 상태·매 프레임 해시가 대결 확장 전과 같다")
    func scriptedPlayAtOneSixtyFourth() {
        let run = goldPlay(seed: 20_261_020, dt: 1.0 / 64.0, maxFrames: 64 * 900, actEvery: 4)
        goldExpect(run, "A", GoldExpected(
            hash: "64cdf7c736fca8b9", score: 30279, advance: 196, lines: 46, next: [2, 3, 3, 4, 6], phase: "result", held: 0,
            elapsedBits: "40673cb333333314",
            board: "....Z...../...ZZTI.../...ZTTI.../..JJJTI.../..JJJSI.../..JLLSS.../..JZL.SL../..ZZLLLL../..ZOOOOLS./..JT..TLLS/..ITTTTZZ./..ITOOTSZZ/..IIOO.SS./.SIIIJJJST/.SSII.ZJTT/.TSIIZZZZT/.TTJIZOOZZ/.TTJJJOOLL/.TTTSSJJJL/.LLSSLLLJL/.ZLOOLJJJI"))
        // 대본이 실제로 경로를 다 지났는가(빈 대본이면 골든이 아무것도 못 잡는다).
        #expect(run.holds >= 10 && run.softDropPieces >= 10 && run.gravityLocks >= 10,
                "대본이 홀드 \(run.holds) · 소프트드롭 \(run.softDropPieces) · 중력 굳힘 \(run.gravityLocks) 만 지났다")
        #expect(run.game.lines >= 20, "줄을 \(run.game.lines)줄만 지웠다")
    }

    @Test("대본 B(1/32초 · 2프레임마다 손 · 판이 끝날 때까지) — 끝 상태·매 프레임 해시가 대결 확장 전과 같다")
    func scriptedPlayToTheEnd() {
        let run = goldPlay(seed: 7_777, dt: 1.0 / 32.0, maxFrames: 32 * 3_600, actEvery: 2)
        goldExpect(run, "B", GoldExpected(
            hash: "b8cf191116c89774", score: 35809, advance: 199, lines: 49, next: [1, 0, 2, 3, 6], phase: "result", held: 5,
            elapsedBits: "4065fe333333331b",
            board: "....S...../....SS..../...OOS..../...OOL..../...LLL..../...TLL..../...TTL..../...TSL..../....SS..../..LLLSI.../..LOO.I.../..JOO.I.../..JJJ.IZ../..JJZ.ZZT./..JZZ.ZTTT/..JZZ..LOO/S.IZZ..LOO/SSIZOO.LLT/ISI.OO.JTT/ISI.OO.JST/TTLJZZOO.I/JSSII.TZSI"))
    }

    @Test("대본 C(advance 330 = L16 · 1/64초) — 20G·락딜레이 보간·리셋 한도 감소 구간이 대결 확장 전과 같다")
    func scriptedPlayAtLevelSixteen() {
        let run = goldPlayFromAdvance(330, seed: 330, dt: 1.0 / 64.0, maxFrames: 64 * 900, actEvery: 4)
        goldExpect(run, "C", GoldExpected(
            hash: "d30fb21e622f28c6", score: 11269, advance: 382, lines: 6, next: [6, 0, 4, 6, 1], phase: "result", held: 2,
            elapsedBits: "403e34bf258bf235",
            board: "...J....../...JJJT.../..OOSTTT../..OOSS..../..I.ZS..../..IZZ...../..IZT...../..ITTTOO../.JJTZZOO../.JTTTZZ.../.JSSLLL.../.SSILT..../...I.TT.LL/...I.TZOOL/..TIJZZOOL/.TTTJZ.LLI/.L.JJZOOLI/IL..ZZOOLI/IJTTSLLI.S/OO.ZTJLZJI/OOZJT.ZSSI"))
        #expect(run.maxLevel >= 16, "L16 구간을 못 지났다(\(run.maxLevel))")
    }

    @Test("대본 D(advance 930 = L28 · 1/128초) — 리셋 한도 2·락딜레이 바닥 구간이 대결 확장 전과 같다")
    func scriptedPlayAtLevelTwentyEight() {
        let run = goldPlayFromAdvance(930, seed: 930, dt: 1.0 / 128.0, maxFrames: 128 * 600, actEvery: 8)
        goldExpect(run, "D", GoldExpected(
            hash: "6519e5cdf43bdb8c", score: 0, advance: 950, lines: 0, next: [6, 2, 1, 0, 3], phase: "result", held: 3,
            elapsedBits: "40125e666666665f",
            board: "..I..T..../..I.TT..../..I.ST..../..I.SS..../..JJ.S..../..JLLLL.../..JLL...../...LL...../....Z...../...ZZ...../...ZI...../..T.I.OO../..TTIJOO../..TZIJJJ../..ZZZS..../..ZZZSS.../...Z.LS.../...LLLI.../..T.S.I.../.TTTSSI.../..OOJSI.../..OOJJJ..."))
        // 리셋 한도 2 의 종료 보장: 1열과 10열(양 끝)에 한 칸도 못 닿고 끝난다.
        for row in run.game.board {
            #expect(row[0] == nil && row[TetrisGame.columns - 1] == nil, "L28 에서 벽 열에 닿았다 — 리셋 한도 2 가 안 걸린다")
        }
    }

    @Test("7-bag 순서 — 시드 셋의 첫 조각들이 대결 확장 전과 같다")
    func pieceOrderIsUnchanged() {
        let expected: [(UInt64, String)] = [
            (1, "TZSOIJLJTSLZOILTZOJSISLOTJIZ"),
            (42, "LSZIOJTJSOTIZLISOLTZJZOTJLIS"),
            (20_261_020, "SJLZIOTSZIOLJTZLSIOTJTZSLJOI"),
        ]
        for (seed, bags) in expected {
            let seq = goldPieceSequence(seed: seed, count: 28)
            #expect(seq.bags == bags, "시드 \(seed) 의 7-bag 순서가 갈렸다: \(seq.bags)")
            #expect(seq.engineHead.count == 1 + TetrisGame.nextCount)
            #expect(bags.hasPrefix(seq.engineHead), "시드 \(seed): 엔진 첫 여섯 장(\(seq.engineHead))이 7-bag 앞머리가 아니다")
        }
    }
}
