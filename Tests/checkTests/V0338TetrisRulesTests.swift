import Foundation
import Testing
@testable import CheckCore

// v0.3.38 테트리스 규칙 엔진 — SRS 킥표 전수 · 프레임 독립성 · 레벨/중력표 · 접지 리셋 바닥 2 의 종료 보장 ·
// 점수(줄소거·T스핀·B2B·콤보·퍼펙트클리어) · 7-bag · 홀드 · 탑아웃 · 접지 총량 상한.
//
// 이 파일이 지키는 것은 **확정 스펙의 숫자**다. 곡선 상수가 한 곳(TetrisGame)에 모여 있는 이유가 여기 있다 —
// 구현 후 실기로 파라미터를 되맞출 때 이 표들이 "무엇이 바뀌었는가"를 말해 준다.

private typealias Piece = TetrisGame.Piece
private typealias Rotation = TetrisGame.Rotation
private typealias ActivePiece = TetrisGame.ActivePiece

// MARK: - 도우미

/// 조각을 스폰 자리에 둔 픽스처.
private func game(board: [[Piece?]], piece: Piece, rotation: Rotation = .spawn,
                  column: Int = TetrisGame.spawnColumn, row: Int = TetrisGame.spawnRow,
                  advance: Int = 0, combo: Int = -1, backToBack: Int = -1,
                  score: Int = 0, seed: UInt64 = 11) -> TetrisGame {
    TetrisGame(seed: seed, board: board,
               active: ActivePiece(piece: piece, rotation: rotation, column: column, row: row),
               score: score, advance: advance, combo: combo, backToBack: backToBack)
}

/// 텀(ARE·줄소거)을 지나 다음 조각이 뜰 때까지.
private func advanceToNextPiece(_ game: inout TetrisGame, limit: Int = 200) {
    var guardCount = 0
    while guardCount < limit {
        switch game.phase {
        case .are, .lineClear:
            game.step(dt: TetrisGame.maxStep)
        default:
            return
        }
        guardCount += 1
    }
}

/// `.running` 이 끝날 때까지 흘린다(조각이 굳거나 판이 끝날 때까지).
private func runUntilPieceLocks(_ game: inout TetrisGame, dt: TimeInterval = 1.0 / 120.0, limit: Int = 20_000) {
    var guardCount = 0
    while guardCount < limit {
        guard case .running = game.phase else { return }
        game.step(dt: dt)
        guardCount += 1
    }
}

/// 굳은 칸이 있는 열들.
private func occupiedColumns(_ game: TetrisGame) -> Set<Int> {
    var columns: Set<Int> = []
    for row in 0..<TetrisGame.totalRows {
        for column in 0..<TetrisGame.columns where game.board[row][column] != nil {
            columns.insert(column)
        }
    }
    return columns
}

// MARK: - (1) SRS 킥표 전수 — 8전이 × 5오프셋 × 2표

// 널리 알려진 SRS 표(tetris.wiki "SRS" 의 Wall Kick Data)를 **여기 한 벌 더** 적어 둔다.
// 구현이 이 표를 import 하지 않고 손으로 다시 적은 것이 요점이다 — 한 벌뿐이면 옮겨 적기 실수를 아무도 못 잡는다.
private let jlstzKicks: [String: [(Int, Int)]] = [
    "0R": [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
    "R0": [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
    "R2": [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
    "2R": [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
    "2L": [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
    "L2": [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
    "L0": [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
    "0L": [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)]
]

private let iKicks: [String: [(Int, Int)]] = [
    "0R": [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
    "R0": [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
    "R2": [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
    "2R": [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
    "2L": [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
    "L2": [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
    "L0": [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
    "0L": [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)]
]

private let transitions: [(String, Rotation, Rotation)] = [
    ("0R", .spawn, .right), ("R0", .right, .spawn),
    ("R2", .right, .flip), ("2R", .flip, .right),
    ("2L", .flip, .left), ("L2", .left, .flip),
    ("L0", .left, .spawn), ("0L", .spawn, .left)
]

@Test("SRS 킥표 전수 — J/L/S/T/Z 공통표 8전이 × 5오프셋")
func srsCommonKickTableMatchesTheStandardEntryByEntry() {
    for piece in [Piece.j, .l, .s, .t, .z] {
        for (key, from, to) in transitions {
            let actual = TetrisGame.kicks(piece: piece, from: from, to: to)
            let expected = jlstzKicks[key]!
            #expect(actual.count == 5, "\(piece) \(key) 오프셋이 \(actual.count)개다")
            for index in 0..<min(actual.count, expected.count) {
                #expect(actual[index].dx == expected[index].0 && actual[index].dy == expected[index].1,
                        "\(piece) \(key) \(index + 1)번 오프셋: (\(actual[index].dx),\(actual[index].dy)) ≠ (\(expected[index].0),\(expected[index].1))")
            }
        }
    }
}

@Test("SRS 킥표 전수 — I 전용표 8전이 × 5오프셋")
func srsIKickTableMatchesTheStandardEntryByEntry() {
    for (key, from, to) in transitions {
        let actual = TetrisGame.kicks(piece: .i, from: from, to: to)
        let expected = iKicks[key]!
        #expect(actual.count == 5, "I \(key) 오프셋이 \(actual.count)개다")
        for index in 0..<min(actual.count, expected.count) {
            #expect(actual[index].dx == expected[index].0 && actual[index].dy == expected[index].1,
                    "I \(key) \(index + 1)번 오프셋: (\(actual[index].dx),\(actual[index].dy)) ≠ (\(expected[index].0),\(expected[index].1))")
        }
    }
}

@Test("O 는 킥을 보지 않고, 모든 회전 상태의 모양이 같다")
func theOPieceNeverKicksBecauseItsShapeDoesNotChange() {
    for (key, from, to) in transitions {
        let kicks = TetrisGame.kicks(piece: .o, from: from, to: to)
        #expect(kicks.count == 1 && kicks[0].dx == 0 && kicks[0].dy == 0, "O \(key) 가 킥표를 본다")
    }
    let spawn = TetrisGame.shape(.o, .spawn).map { [$0.dx, $0.dy] }
    for rotation in Rotation.allCases {
        #expect(TetrisGame.shape(.o, rotation).map { [$0.dx, $0.dy] } == spawn)
    }
}

@Test("회전은 킥표를 차례로 보고, 다섯 자리가 전부 막혀 있으면 **일어나지 않는다**")
func aRotationThatFitsNowhereIsRejectedOutright() {
    // 바닥 두 줄의 1~4열만 빈 복도. 가로 I 하나가 겨우 들어가고, 세로로는 어느 킥 자리에도 못 선다.
    var board = TetrisGame.emptyBoard()
    for row in 0..<TetrisGame.totalRows {
        for column in 0..<TetrisGame.columns { board[row][column] = .i }
    }
    for row in [38, 39] {
        for column in 0...3 { board[row][column] = nil }
    }
    var g = game(board: board, piece: .i, rotation: .spawn, column: 0, row: 37)
    #expect(g.fits(g.active!), "픽스처 I 가 복도에 안 들어간다 — 전제가 깨졌다")
    let before = g
    g.rotate(clockwise: true)
    #expect(g == before, "막힌 자리로 회전이 들어갔다 — 회전이 킥표 판정을 건너뛴다")
    g.rotate(clockwise: false)
    #expect(g == before, "막힌 자리로 반시계 회전이 들어갔다")
}

@Test("월킥 — 바닥에 붙은 T 는 세 번째 오프셋(-1,+1)으로 한 칸 올라가며 돈다")
func aFloorKickLiftsThePieceByTheThirdOffset() {
    // 빈 판 바닥에 놓인 T(스폰 상태). 시계 회전은 제자리(0,0)·(-1,0) 에서 바닥을 뚫으므로 세 번째 (-1,+1) 로 성공한다.
    var g = game(board: TetrisGame.emptyBoard(), piece: .t, rotation: .spawn, column: 4, row: 38)
    #expect(g.fits(g.active!) && g.isGrounded, "픽스처 T 가 바닥에 안 붙었다")
    g.rotate(clockwise: true)
    #expect(g.active?.rotation == .right, "회전이 아예 안 됐다")
    #expect(g.active?.column == 3 && g.active?.row == 37,
            "킥이 (-1,+1) 이 아니다 — 지금 자리는 (\(g.active?.column ?? -1), \(g.active?.row ?? -1))")
}

@Test("모든 조각의 모든 회전 상태는 정확히 네 칸이고 상자 안에 있다")
func everyRotationStateHasFourCellsInsideItsBox() {
    for piece in Piece.allCases {
        let box = piece == .i ? 4 : 3
        for rotation in Rotation.allCases {
            let cells = TetrisGame.shape(piece, rotation)
            #expect(cells.count == 4, "\(piece) \(rotation) 칸이 \(cells.count)개")
            #expect(Set(cells.map { [$0.dx, $0.dy] }).count == 4, "\(piece) \(rotation) 에 겹친 칸이 있다")
            for cell in cells {
                #expect(cell.dx >= 0 && cell.dx < box && cell.dy >= 0 && cell.dy < box,
                        "\(piece) \(rotation) 칸 (\(cell.dx),\(cell.dy)) 이 \(box)×\(box) 상자 밖이다")
            }
        }
    }
}

// MARK: - (2) 프레임 독립성

/// 같은 판을 같은 총 시간만큼, 프레임 수만 달리해서 돌린다.
///
/// 십진 분할(10·100)을 안 쓰는 이유: 1/320 은 이진 분수가 아니라 100프레임의 총합이 1/32 와 **정확히 같지 않다**.
/// 그러면 이 테스트가 재는 것이 '프레임 독립성'이 아니라 '부동소수점 오차 내성'이 된다.
/// 2의 거듭제곱(1/32 · 1/128 · 1/1024)은 부분합까지 정확히 같아서 프레임 수만 순수하게 달라진다.
/// 세 dt 모두 `maxStep`(1/20) 이하다 — 그보다 크면 클램프가 먼저 걸려 총 시간 자체가 달라진다.
private func playFrames(seed: UInt64, frames: Int, dt: TimeInterval,
                        softDrop: Bool, left: Bool) -> TetrisGame {
    var game = TetrisGame(seed: seed)
    game.action()
    if softDrop { game.setSoftDropHeld(true) }
    if left { game.setLeftHeld(true) }
    for _ in 0..<frames { game.step(dt: dt) }
    return game
}

private func expectSamePlay(_ a: TetrisGame, _ b: TetrisGame, _ label: String) {
    #expect(a.board == b.board, "\(label): 최종 판이 다르다")
    #expect(a.score == b.score, "\(label): 점수 \(a.score) ≠ \(b.score)")
    #expect(a.advance == b.advance, "\(label): advance \(a.advance) ≠ \(b.advance)")
    #expect(a.lines == b.lines, "\(label): 지운 줄 \(a.lines) ≠ \(b.lines)")
    #expect(a.active == b.active, "\(label): 떨어지는 조각이 다르다")
    #expect(a.phase == b.phase, "\(label): 단계가 다르다")
}

@Test("프레임 독립성 — 중력·소프트드롭만: 같은 총 dt 를 128 / 512 / 4096 프레임으로 나눠도 같은 판")
func gravityAndSoftDropProduceTheSameBoardAtAnyFrameRate() {
    let a = playFrames(seed: 42, frames: 128, dt: 1.0 / 32.0, softDrop: true, left: false)
    let b = playFrames(seed: 42, frames: 512, dt: 1.0 / 128.0, softDrop: true, left: false)
    let c = playFrames(seed: 42, frames: 4096, dt: 1.0 / 1024.0, softDrop: true, left: false)
    // 기준선이 비어 있으면 이 비교는 아무것도 못 잡는다 — 4초 동안 조각이 실제로 여러 개 굳었는지 먼저 본다.
    #expect(a.advance >= 3, "4초에 굳은 조각이 \(a.advance)개뿐이다 — 시나리오가 아무 일도 안 한다")
    expectSamePlay(a, b, "128 vs 512")
    expectSamePlay(a, c, "128 vs 4096")
}

@Test("프레임 독립성 — DAS/ARR 가로 이동: 프레임 수를 32배로 늘려도 같은 판")
func horizontalAutoRepeatProducesTheSameBoardAtAnyFrameRate() {
    let a = playFrames(seed: 7, frames: 128, dt: 1.0 / 32.0, softDrop: false, left: true)
    let b = playFrames(seed: 7, frames: 512, dt: 1.0 / 128.0, softDrop: false, left: true)
    let c = playFrames(seed: 7, frames: 4096, dt: 1.0 / 1024.0, softDrop: false, left: true)
    #expect(a.active?.column == 0 || occupiedColumns(a).contains(0),
            "4초 동안 왼쪽으로 한 번도 안 갔다 — DAS/ARR 가 안 돈다")
    expectSamePlay(a, b, "128 vs 512")
    expectSamePlay(a, c, "128 vs 4096")
}

@Test("프레임 독립성 — 가로·소프트드롭 동시: 프레임 수를 32배로 늘려도 같은 판")
func combinedInputsProduceTheSameBoardAtAnyFrameRate() {
    let a = playFrames(seed: 99, frames: 128, dt: 1.0 / 32.0, softDrop: true, left: true)
    let b = playFrames(seed: 99, frames: 512, dt: 1.0 / 128.0, softDrop: true, left: true)
    let c = playFrames(seed: 99, frames: 4096, dt: 1.0 / 1024.0, softDrop: true, left: true)
    #expect(a.advance >= 3, "4초에 굳은 조각이 \(a.advance)개뿐이다")
    expectSamePlay(a, b, "128 vs 512")
    expectSamePlay(a, c, "128 vs 4096")
}

@Test("dt 클램프 — 한 프레임에 maxStep 을 넘겨도 그만큼만 흐른다")
func oneHugeFrameOnlyAdvancesByMaxStep() {
    var game = TetrisGame(seed: 5)
    game.action()
    game.step(dt: 5.0)
    #expect(abs(game.elapsed - TetrisGame.maxStep) < 1e-12,
            "5초를 한 번에 밀었다(elapsed \(game.elapsed))")
    #expect(TetrisGame.maxStep == 1.0 / 20.0)
    // **24Hz·30Hz 화면을 덮어야 한다.** 클램프가 화면 프레임 간격보다 작으면 매 프레임 시간을 버려
    // 판이 실시간보다 느리게 돌고, 느린 시계는 이 게임에서 곧 이득이다(하드웨어가 순위를 가른다).
    #expect(TetrisGame.maxStep > 1.0 / 24.0, "24Hz 화면의 프레임 간격(0.0417초)을 못 덮는다")
    #expect(TetrisGame.maxStep > 1.0 / 30.0, "30Hz 화면의 간격과 같거나 작다 — 지터 한 번에 판이 느려진다")
}

// MARK: - (3) 레벨 · 중력 · 락다운 표

@Test("레벨 축 — advance 경계가 확정표와 같다")
func theLevelAxisIsAdvanceNotLines() {
    // 진입 advance: L1=0 · L2=20 · L15=280(20G) · L16=330 · L28=930 · L30=1030.
    #expect(TetrisGame.level(forAdvance: 0) == 1)
    #expect(TetrisGame.level(forAdvance: 19) == 1)
    #expect(TetrisGame.level(forAdvance: 20) == 2)
    #expect(TetrisGame.level(forAdvance: 279) == 14)
    #expect(TetrisGame.level(forAdvance: 280) == 15)
    #expect(TetrisGame.level(forAdvance: 329) == 15)
    #expect(TetrisGame.level(forAdvance: 330) == 16)
    #expect(TetrisGame.level(forAdvance: 930) == 28)
    #expect(TetrisGame.level(forAdvance: 1030) == 30)
    // 점수 배수만 30 에서 멈춘다 — 난이도 함수는 자르지 않은 레벨을 본다.
    #expect(TetrisGame.level(forAdvance: 5000) == 109)
    #expect(TetrisGame.scoreLevel(forLevel: 109) == 30)
    #expect(TetrisGame.scoreLevel(forLevel: 29) == 29)

    // 진행 표시는 '줄 수'가 아니라 advance 를 봐야 한다 — 레벨 축이 advance 라 줄만 봐서는 다음 상승을 못 읽는다.
    func remaining(_ advance: Int) -> Int {
        game(board: TetrisGame.emptyBoard(), piece: .o, advance: advance).advanceToNextLevel
    }
    #expect(remaining(0) == 20)
    #expect(remaining(19) == 1)
    #expect(remaining(279) == 1, "L14 에서 L15(20G) 까지 한 칸이어야 한다")
    #expect(remaining(280) == 50)
    #expect(remaining(329) == 1)
}

@Test("중력표 — L=1·5·10·15·20·28·30·200 이 확정표와 같다")
func theGravityTableMatchesTheSpec() {
    let expected: [(Int, Double)] = [
        (1, 0.355197), (5, 0.093882), (10, 0.011439), (15, 0.000824),
        (20, 0.000824), (28, 0.000824), (30, 0.000824), (200, 0.000824)
    ]
    for (level, seconds) in expected {
        let actual = TetrisGame.gravitySeconds(forLevel: level)
        #expect(abs(actual - seconds) < 5e-7, "L\(level) 중력 \(actual) ≠ \(seconds)")
    }
    // 20G 는 L15 에서 처음 닿고 그 뒤로 더 빨라지지 않는다(E 가 19 에서 멈춘다).
    let twentyG = 1.0 / (20.0 * 60.0)
    #expect(TetrisGame.gravitySeconds(forLevel: 14) > twentyG, "L14 가 이미 20G 다")
    #expect(TetrisGame.gravitySeconds(forLevel: 15) < twentyG, "L15 가 20G 에 못 닿는다")
    #expect(TetrisGame.gravitySeconds(forLevel: 200) == TetrisGame.gravitySeconds(forLevel: 15))
    #expect(TetrisGame.gravityStage(forLevel: 1) == 5, "시작 중력 단계가 E5 가 아니다")
    #expect(TetrisGame.gravityStage(forLevel: 15) == 19)
    #expect(TetrisGame.gravityStage(forLevel: 200) == 19)
    // 소프트드롭은 표준대로 중력의 20배.
    #expect(abs(TetrisGame.softDropSeconds(forLevel: 1) * 20 - TetrisGame.gravitySeconds(forLevel: 1)) < 1e-15)
}

@Test("중력 지수 클램프 — 상한이 없으면 낙하 간격이 음수가 된다(레벨 116)")
func theGravityExponentIsClampedSoTheIntervalNeverGoesNegative() {
    // 밑 0.8 − 0.007(E−1) 은 E = 115.29 에서 0 을 지난다. 클램프가 없으면 E116 에서 음수(조각이 위로 솟는다).
    #expect(TetrisGame.gravitySeconds(forStage: 116) > 0, "E116 에서 낙하 간격이 0 이하다")
    #expect(TetrisGame.gravitySeconds(forStage: 116) == TetrisGame.gravitySeconds(forStage: 20),
            "E116 이 E20 으로 안 잘린다")
    #expect(TetrisGame.gravitySeconds(forStage: 1000) == TetrisGame.gravitySeconds(forStage: 20))
    // 클램프가 안 걸린 식이 실제로 음수라는 것 — 기준선이 다르다는 확인이다.
    let unclamped = pow(0.8 - 0.007 * 115.0, 115.0)
    #expect(unclamped < 0, "클램프 없는 식이 E116 에서 음수가 아니다 — 이 테스트의 전제가 깨졌다")
}

@Test("락딜레이·리셋 한도 램프가 확정표와 같다")
func theLockDownRampMatchesTheSpec() {
    let expected: [(Int, Double, Int)] = [
        (1, 0.500, 15), (15, 0.500, 15), (16, 0.477, 14), (18, 0.432, 12),
        (20, 0.387, 10), (22, 0.341, 8), (24, 0.296, 6), (26, 0.251, 4),
        (28, 0.205, 2), (30, 0.160, 2), (40, 0.160, 2)
    ]
    for (level, delay, resets) in expected {
        #expect(abs(TetrisGame.lockDelaySeconds(forLevel: level) - delay) < 5e-4,
                "L\(level) 락딜레이 \(TetrisGame.lockDelaySeconds(forLevel: level)) ≠ \(delay)")
        #expect(TetrisGame.lockResetLimit(forLevel: level) == resets,
                "L\(level) 리셋 한도 \(TetrisGame.lockResetLimit(forLevel: level)) ≠ \(resets)")
    }
    // 재충전은 L>15 에서 꺼진다 — 거친 판에서 접지 예산이 2~3배로 부푸는 것을 막는 자리다.
    #expect(TetrisGame.lockResetRefreshes(forLevel: 15))
    #expect(!TetrisGame.lockResetRefreshes(forLevel: 16))
    // ★ 필수 상수: 빼면 늘어뜨리기 상계가 24.7분 → 71분이 된다.
    #expect(TetrisGame.maxGroundedSeconds == 1.00)
    #expect(TetrisGame.areSeconds == 0.100 && TetrisGame.lineClearSeconds == 0.500)
    #expect(TetrisGame.dasSeconds == 0.167 && TetrisGame.arrSeconds == 0.033)
}

// MARK: - (4) 접지 리셋 바닥 2 — 종료 보장

/// 1·10열이 빈 평평한 더미. advance 930 = 레벨 28(리셋 한도 2 · 20G).
private let level28Stack = [
    ".########.",
    ".########.",
    ".########.",
    ".########.",
    ".########.",
    ".########."
]

@Test("리셋 바닥 2 — 스폰에서 왼벽에 못 닿는다(7조각 전부)")
func atResetFloorTwoNoPieceCanReachTheLeftWall() {
    for piece in Piece.allCases {
        var g = game(board: TetrisGame.boardFixture(bottomRows: level28Stack), piece: piece, advance: 930)
        #expect(TetrisGame.lockResetLimit(forLevel: g.level) == 2, "\(piece): 레벨 \(g.level) 의 리셋 한도가 2 가 아니다")
        g.setLeftHeld(true)
        runUntilPieceLocks(&g)
        #expect(!occupiedColumns(g).contains(0),
                "\(piece): 왼쪽 끝 열에 닿았다 — 리셋 바닥 2 의 종료 보장이 깨졌다")
        // 스폰 점유열 최소값 3(1-indexed 4) − 리셋 2 = 1 이 이론적 한계다.
        for row in 0..<TetrisGame.totalRows {
            #expect(g.board[row][0] == nil, "\(piece): 1열 \(row)행이 찼다")
        }
    }
}

@Test("리셋 바닥 2 — 스폰에서 오른벽에 못 닿는다(7조각 전부)")
func atResetFloorTwoNoPieceCanReachTheRightWall() {
    for piece in Piece.allCases {
        var g = game(board: TetrisGame.boardFixture(bottomRows: level28Stack), piece: piece, advance: 930)
        g.setRightHeld(true)
        runUntilPieceLocks(&g)
        #expect(!occupiedColumns(g).contains(TetrisGame.columns - 1),
                "\(piece): 오른쪽 끝 열에 닿았다 — 리셋 바닥 2 의 종료 보장이 깨졌다")
    }
}

@Test("리셋 바닥 2 — 회전을 섞어도 벽에 못 닿는다(회전도 리셋 하나를 쓴다)")
func rotationsAlsoSpendTheResetBudgetSoWallsStayOutOfReach() {
    for piece in Piece.allCases {
        var g = game(board: TetrisGame.boardFixture(bottomRows: level28Stack), piece: piece, advance: 930)
        g.step(dt: TetrisGame.maxStep)       // 20G — 여기서 이미 더미 위에 얹힌다
        g.rotate(clockwise: false)
        g.setLeftHeld(true)
        runUntilPieceLocks(&g)
        #expect(!occupiedColumns(g).contains(0), "\(piece): 회전 + 왼쪽으로 1열에 닿았다")
        #expect(!occupiedColumns(g).contains(TetrisGame.columns - 1), "\(piece): 회전 + 왼쪽으로 10열에 닿았다")
    }
}

@Test("리셋 바닥 2 — **스폰을 실제로 지나도** 벽에 못 닿는다(눌린 방향키가 공짜 칸을 주지 않는다)")
func heldDirectionAcrossASpawnGivesNoFreeCell() {
    // ★ 왜 이 테스트가 따로 있나(2026-09-23, 적대 검증이 찾은 구멍):
    //   위 세 테스트는 픽스처가 `ActivePiece` 를 **직접 꽂고**, `runUntilPieceLocks` 가 첫 고정에서 되돌아온다.
    //   그래서 `spawn()` 이 측정 경로에 **한 번도 오지 않았다.** 스폰 순간에 붙는 이득(IMS — 눌려 있는
    //   방향키로 공짜 한 칸)을 구현에 심어도 94건이 전부 초록이었다. 여기는 방향키를 **누른 채 스폰을 태운다.**
    for piece in Piece.allCases {
        var g = game(board: TetrisGame.boardFixture(bottomRows: level28Stack), piece: piece, advance: 930)
        #expect(TetrisGame.lockResetLimit(forLevel: g.level) == 2)
        g.setLeftHeld(true)                 // 누른 채로 둔다 — 첫 조각이 굳고 다음 조각이 뜰 때까지
        runUntilPieceLocks(&g)
        advanceToNextPiece(&g)              // ← 여기서 spawn() 이 실제로 돈다
        var isRunning = false
        if case .running = g.phase { isRunning = true }
        #expect(isRunning, "\(piece): 스폰을 못 지났다 — 이 테스트의 전제가 없어졌다")
        runUntilPieceLocks(&g)
        #expect(!occupiedColumns(g).contains(0),
                "\(piece): 스폰을 지나자 왼쪽 끝에 닿았다 — 눌린 방향키가 리셋 예산을 안 쓰고 한 칸을 줬다")
    }
}

@Test("리셋 바닥 2 — **텀 동안 누른 회전**이 스폰 순간 공짜로 적용되지 않는다(입력 선행 금지)")
func rotationPressedDuringTheGapIsNotBankedIntoTheSpawn() {
    // 사용자 확정: 스폰 전 입력 버퍼링(IRS/IHS)을 넣지 않는다. 넣으면 조각마다 회전 하나가 리셋 예산 밖에서
    // 공짜가 되어 리셋 바닥 2 가 사실상 3~4 가 되고, 20G 후반의 종료 보장이 무너진다.
    for piece in Piece.allCases {
        var g = game(board: TetrisGame.boardFixture(bottomRows: level28Stack), piece: piece, advance: 930)
        runUntilPieceLocks(&g)
        var inGap = false
        if case .are = g.phase { inGap = true }
        if case .lineClear = g.phase { inGap = true }
        #expect(inGap, "\(piece): 텀이 없다 — 이 테스트의 전제가 없어졌다")
        g.rotate(clockwise: true)           // 텀 동안 누른다 — 버퍼에 쌓이면 안 된다
        g.rotate(clockwise: true)
        advanceToNextPiece(&g)
        #expect(g.active?.rotation == .spawn,
                "\(piece): 텀 동안 누른 회전이 스폰에 실렸다 — 입력 선행(IRS)이 들어갔다")
        g.setLeftHeld(true)
        runUntilPieceLocks(&g)
        #expect(!occupiedColumns(g).contains(0), "\(piece): 선행 회전 + 왼쪽으로 1열에 닿았다")
    }
}

@Test("리셋 바닥 2 의 산술 근거 — 스폰 점유열에서 양 끝까지 3칸·4칸이 필요하다")
func theResetFloorIsSmallerThanTheDistanceToEitherWall() {
    var minimum = TetrisGame.columns
    var maximum = 0
    for piece in Piece.allCases {
        for cell in TetrisGame.shape(piece, .spawn) {
            minimum = min(minimum, TetrisGame.spawnColumn + cell.dx)
            maximum = max(maximum, TetrisGame.spawnColumn + cell.dx)
        }
    }
    // J/L/S/T/Z = 4~6열 · I = 4~7열 · O = 5~6열(1-indexed) → 합쳐서 4~7열.
    #expect(minimum == 3 && maximum == 6, "스폰 점유열이 \(minimum + 1)~\(maximum + 1)열(1-indexed)이다")
    let floor = TetrisGame.lockResetLimit(forLevel: 28)
    #expect(minimum - floor > 0, "왼벽까지 \(minimum)칸인데 리셋이 \(floor) 이라 닿는다")
    #expect(maximum + floor < TetrisGame.columns - 1, "오른벽까지 \(TetrisGame.columns - 1 - maximum)칸인데 리셋이 \(floor) 이라 닿는다")
}

// MARK: - (9) 접지 총량 상한

/// 바닥이 평평하고(1~9열) 10열만 빈 더미 — 어떤 배치로도 줄이 안 지워진다.
private let flatFloor = ["#########.", "#########."]

@Test("maxGroundedSeconds 가 접지 시간을 실제로 자른다(락딜레이 재충전보다 먼저 온다)")
func theGroundedBudgetCutsTheStallShorterThanTheLockDelayChain() {
    // L1: 락딜레이 0.5 · 리셋 한도 15. 0.453 과 0.906 에 한 칸씩 움직이면 마지막 창이 1.406 까지 이어진다 —
    // 접지 총량 1.00 이 그보다 먼저 굳힌다.
    var g = game(board: TetrisGame.boardFixture(bottomRows: flatFloor), piece: .t, column: 3, row: 36)
    #expect(g.isGrounded, "픽스처가 접지 상태가 아니다 — 이 테스트의 전제가 깨졌다")
    let dt = 1.0 / 256.0
    for index in 0..<400 {
        guard case .running = g.phase else { break }
        if index == 116 { g.setLeftHeld(true); g.setLeftHeld(false) }
        if index == 232 { g.setRightHeld(true); g.setRightHeld(false) }
        g.step(dt: dt)
    }
    let lockedAt = g.lastClear?.at ?? -1
    #expect(abs(lockedAt - TetrisGame.maxGroundedSeconds) < 1e-9,
            "접지 \(lockedAt)초에 굳었다 — 상한 1.00초가 안 걸렸다(상한 없으면 1.406초)")
}

@Test("접지 예산은 조각이 아니라 한 번의 배치에 붙는다 — 홀드로 갈아타도 이어진다")
func theGroundedBudgetSurvivesAHoldSwap() {
    // L15(advance 280)에서 잰다: 20G 라 갈아탄 조각이 0.015초 만에 바닥에 닿아 '공중에 뜬 시간'이 잡음으로 안 섞인다.
    // 락딜레이는 아직 0.50, 리셋 한도는 15 다.
    var g = game(board: TetrisGame.boardFixture(bottomRows: flatFloor), piece: .t, column: 3, row: 36,
                 advance: 280)
    #expect(g.isGrounded && g.level == 15, "픽스처 전제가 깨졌다(접지 \(g.isGrounded) · 레벨 \(g.level))")
    let dt = 1.0 / 256.0
    // 0.398초에 한 번 흔들어 락딜레이를 되감고(0.50 짜리 창이 0.898 까지 늘어난다), 0.75초에 홀드로 갈아탄다.
    for index in 0..<192 {
        if index == 102 { g.setLeftHeld(true); g.setLeftHeld(false) }
        g.step(dt: dt)
    }
    #expect(g.lastClear == nil, "홀드 전에 굳었다 — 전제가 깨졌다")
    g.holdCurrentPiece()
    for _ in 0..<1000 {
        guard case .running = g.phase else { break }
        g.step(dt: dt)
    }
    let lockedAt = g.lastClear?.at ?? -1
    // 예산이 이어지면 남은 0.25초 뒤(≈1.015초)에 굳는다. 새로 주어지면 락딜레이 0.50초를 다 써 ≈1.265초다.
    #expect(lockedAt > 0.9 && lockedAt < 1.10,
            "홀드 뒤 \(lockedAt)초에 굳었다 — 예산이 새로 주어졌다(늘어뜨리기 상계가 두 배가 된다)")
}

// MARK: - (5) 점수 — 줄소거 · T스핀 · B2B · 콤보 · 퍼펙트클리어

/// 10열만 빈 `rows` 줄짜리 벽. 세로 I 를 10열에 떨어뜨리면 정확히 `rows` 줄이 지워진다.
///
/// 맨 위 `#.........` 는 **지워지지 않는 부스러기 한 줄**이다. 없으면 4줄 소거가 곧 판을 비워
/// 퍼펙트 클리어 보너스(2000×L)가 얹히고, 그러면 이 표가 재려던 '줄소거 점수'가 안 갈린다.
private func wellBoard(rows: Int) -> [[Piece?]] {
    TetrisGame.boardFixture(bottomRows: ["#........."] + Array(repeating: "#########.", count: rows))
}

/// 10열에 세로 I 를 세워 둔 판.
private func verticalIAtLastColumn(rows: Int, advance: Int = 0,
                                   combo: Int = -1, backToBack: Int = -1, score: Int = 0) -> TetrisGame {
    game(board: wellBoard(rows: rows), piece: .i, rotation: .right,
         column: TetrisGame.columns - 3, row: TetrisGame.spawnRow,
         advance: advance, combo: combo, backToBack: backToBack, score: score)
}

@Test("줄소거 점수 — 1·2·3·4줄이 표준표와 같다")
func lineClearScoringMatchesTheStandardTable() {
    let expected: [(Int, Int)] = [(1, 100), (2, 300), (3, 500), (4, 800)]
    for (rows, points) in expected {
        var g = verticalIAtLastColumn(rows: rows)
        g.action()                      // 하드드롭 → 고정
        #expect(g.lastClear?.lines == rows, "\(rows)줄을 지우려 했는데 \(g.lastClear?.lines ?? -1)줄이 지워졌다")
        #expect(g.lastClear?.points == points, "\(rows)줄 점수 \(g.lastClear?.points ?? -1) ≠ \(points)")
        #expect(g.lines == rows)
        // 난이도 시계: 고정 1 + 지운 줄.
        #expect(g.advance == 1 + rows, "advance \(g.advance) ≠ \(1 + rows)")
    }
}

@Test("점수는 레벨 배수를 탄다(점수 배수 레벨은 min(level, 30))")
func clearScoresAreMultipliedByTheCappedLevel() {
    var g = verticalIAtLastColumn(rows: 4, advance: 930)     // L28
    g.action()
    #expect(g.lastClear?.points == 800 * 28, "L28 테트리스 \(g.lastClear?.points ?? -1) ≠ \(800 * 28)")

    var capped = verticalIAtLastColumn(rows: 4, advance: 5000)   // L109 → 점수 배수는 30
    #expect(capped.level == 109 && capped.scoreLevel == 30)
    capped.action()
    #expect(capped.lastClear?.points == 800 * 30, "배수 상한 30 이 안 걸렸다")
}

@Test("B2B — 연속된 어려운 소거에만 ×1.5 가 붙고, 평범한 소거가 사슬을 끊는다")
func backToBackMultipliesOnlyTheSecondAndLaterDifficultClears() {
    // 첫 테트리스: 사슬 시작이라 배수 없음.
    var first = verticalIAtLastColumn(rows: 4)
    first.action()
    #expect(first.lastClear?.backToBack == false)
    #expect(first.lastClear?.points == 800)
    #expect(first.backToBack == 0, "첫 어려운 소거 뒤 사슬이 \(first.backToBack)")

    // 사슬이 이어진 테트리스: 800 × 1.5 = 1200.
    var chained = verticalIAtLastColumn(rows: 4, backToBack: 0)
    chained.action()
    #expect(chained.lastClear?.backToBack == true)
    #expect(chained.lastClear?.points == 1200, "B2B 테트리스 \(chained.lastClear?.points ?? -1) ≠ 1200")
    #expect(chained.backToBack == 1)

    // 평범한 소거(1줄)는 사슬을 끊는다.
    var broken = verticalIAtLastColumn(rows: 1, backToBack: 3)
    broken.action()
    #expect(broken.lastClear?.backToBack == false)
    #expect(broken.lastClear?.points == 100, "평범한 소거에 B2B 가 붙었다")
    #expect(broken.backToBack == -1, "평범한 소거가 사슬을 안 끊었다")

    // 줄을 안 지우는 배치는 사슬을 건드리지 않는다.
    var idle = game(board: TetrisGame.boardFixture(bottomRows: flatFloor), piece: .o, backToBack: 2)
    idle.action()
    #expect(idle.lastClear?.lines == 0)
    #expect(idle.backToBack == 2, "소거 없는 배치가 B2B 사슬을 건드렸다")
}

@Test("콤보 — 50 × 콤보수 × 레벨이 더해지고, 소거 없는 배치가 −1 로 되돌린다")
func comboAddsFiftyPerChainStepAndResetsOnAnEmptyPlacement() {
    // 첫 소거는 콤보수 0 이라 보너스가 없다.
    var first = verticalIAtLastColumn(rows: 1)
    first.action()
    #expect(first.combo == 0)
    #expect(first.lastClear?.points == 100, "첫 소거에 콤보 점수가 붙었다")

    // 사슬 3 에서 한 줄 더 지우면 콤보수 4 → 100 + 50×4 = 300.
    var chained = verticalIAtLastColumn(rows: 1, combo: 3)
    chained.action()
    #expect(chained.combo == 4)
    #expect(chained.lastClear?.points == 100 + 50 * 4, "콤보 점수 \(chained.lastClear?.points ?? -1) ≠ 300")

    // 레벨 배수를 탄다.
    var levelled = verticalIAtLastColumn(rows: 1, advance: 930, combo: 3)   // L28
    levelled.action()
    #expect(levelled.lastClear?.points == (100 + 50 * 4) * 28)

    // 소거 없는 배치는 −1 로.
    var idle = game(board: TetrisGame.boardFixture(bottomRows: flatFloor), piece: .o, combo: 5)
    idle.action()
    #expect(idle.combo == -1, "소거 없는 배치가 콤보를 \(idle.combo) 로 뒀다")
}

@Test("퍼펙트 클리어 — 판을 통째로 비우면 보너스가 행동 점수에 더해진다")
func aPerfectClearAddsItsBonusOnTopOfTheActionScore() {
    // 38·39행의 1~8열만 차 있는 판. 9·10열에 O 를 떨어뜨리면 두 줄이 지워지고 판이 완전히 빈다.
    var g = game(board: TetrisGame.boardFixture(bottomRows: ["########..", "########.."]),
                 piece: .o, column: 7)
    g.action()
    #expect(g.lastClear?.lines == 2)
    #expect(g.lastClear?.perfectClear == true, "판이 안 비었다")
    // 더블 300 + 퍼펙트클리어 더블 1200 = 1500 (레벨 1).
    #expect(g.lastClear?.points == 1500, "퍼펙트 클리어 점수 \(g.lastClear?.points ?? -1) ≠ 1500")
    #expect(g.board.allSatisfy { $0.allSatisfy { $0 == nil } })

    // 판이 안 비면 보너스가 없다(기준선이 다르다는 확인).
    var partial = verticalIAtLastColumn(rows: 2)
    partial.action()
    #expect(partial.lastClear?.perfectClear == false)
    #expect(partial.lastClear?.points == 300)
}

@Test("T-스핀 — 3코너 규칙으로 완전 T-스핀 더블이 잡힌다")
func aThreeCornerTSpinDoubleScoresTwelveHundred() {
    // 36행 4열의 처마 + 37행 4~6열 슬롯 + 38행 5열 구멍.
    var g = game(board: TetrisGame.boardFixture(bottomRows: [
        "...#......",
        "###...####",
        "####.#####",
        "#########."
    ]), piece: .t, rotation: .right, column: 3, row: 36)
    #expect(g.fits(g.active!), "픽스처 T 가 판에 안 들어간다")
    g.rotate(clockwise: true)                   // R → 2 (아래를 가리킨다)
    #expect(g.active?.rotation == .flip, "회전이 실패했다")
    g.action()                                   // 0칸 하드드롭 — 회전 표시를 지우지 않는다
    #expect(g.lastClear?.spin == .full, "T-스핀 판정이 \(String(describing: g.lastClear?.spin))")
    #expect(g.lastClear?.lines == 2)
    #expect(g.lastClear?.points == 1200, "T-스핀 더블 \(g.lastClear?.points ?? -1) ≠ 1200")

    // 마지막 행동이 회전이 아니면 T-스핀이 아니다 — 같은 자리에서 옆으로 한 번 밀었다 되돌리면 점수가 달라진다.
    var moved = game(board: TetrisGame.boardFixture(bottomRows: [
        "...#......",
        "###...####",
        "####.#####",
        "#########."
    ]), piece: .t, rotation: .flip, column: 3, row: 36)
    moved.action()
    #expect(moved.lastClear?.spin == TetrisGame.Spin.none, "회전 없이도 T-스핀이 붙었다")
    #expect(moved.lastClear?.points == 300, "회전 없는 더블 \(moved.lastClear?.points ?? -1) ≠ 300")
}

@Test("점수표 순수 함수 — T-스핀·미니·퍼펙트클리어 표가 표준 그대로다")
func thePureScoringTablesMatchTheStandard() {
    #expect(TetrisGame.actionPoints(lines: 1) == 100)
    #expect(TetrisGame.actionPoints(lines: 2) == 300)
    #expect(TetrisGame.actionPoints(lines: 3) == 500)
    #expect(TetrisGame.actionPoints(lines: 4) == 800)
    #expect(TetrisGame.actionPoints(lines: 0, spin: .full) == 400)
    #expect(TetrisGame.actionPoints(lines: 1, spin: .full) == 800)
    #expect(TetrisGame.actionPoints(lines: 2, spin: .full) == 1200)
    #expect(TetrisGame.actionPoints(lines: 3, spin: .full) == 1600)
    #expect(TetrisGame.actionPoints(lines: 0, spin: .mini) == 100)
    #expect(TetrisGame.actionPoints(lines: 1, spin: .mini) == 200)
    #expect(TetrisGame.actionPoints(lines: 2, spin: .mini) == 400)
    #expect(TetrisGame.perfectClearPoints(lines: 1, backToBackTetris: false) == 800)
    #expect(TetrisGame.perfectClearPoints(lines: 2, backToBackTetris: false) == 1200)
    #expect(TetrisGame.perfectClearPoints(lines: 3, backToBackTetris: false) == 1800)
    #expect(TetrisGame.perfectClearPoints(lines: 4, backToBackTetris: false) == 2000)
    #expect(TetrisGame.perfectClearPoints(lines: 4, backToBackTetris: true) == 3200)
    // 어려운 소거 = 테트리스 + 모든 T-스핀 줄소거.
    #expect(TetrisGame.isDifficult(lines: 4, spin: TetrisGame.Spin.none))
    #expect(TetrisGame.isDifficult(lines: 1, spin: .full))
    #expect(TetrisGame.isDifficult(lines: 1, spin: .mini))
    #expect(!TetrisGame.isDifficult(lines: 3, spin: TetrisGame.Spin.none))
    #expect(!TetrisGame.isDifficult(lines: 0, spin: .full), "줄을 안 지운 T-스핀은 사슬을 잇지 않는다")
    // B2B ×1.5 는 콤보·퍼펙트클리어에 곱하지 않는다.
    let withB2B = TetrisGame.placementPoints(lines: 4, spin: TetrisGame.Spin.none, scoreLevel: 2,
                                             backToBack: true, combo: 3, perfectClear: true)
    #expect(withB2B == (800 * 2) * 3 / 2 + 3200 * 2 + 50 * 3 * 2,
            "B2B 가 콤보·퍼펙트클리어까지 곱했다(\(withB2B))")
}

@Test("소프트드롭 1점/칸 · 하드드롭 2점/칸 (레벨 배수 없음)")
func dropPointsAreFlatPerCell() {
    // 하드드롭: 빈 판에서 세로 I 를 떨어뜨린다.
    var hard = game(board: TetrisGame.emptyBoard(), piece: .i, rotation: .right,
                    column: TetrisGame.spawnColumn, row: TetrisGame.spawnRow, advance: 930)
    let before = hard.active!
    let ghostRow = hard.ghost!.row
    hard.action()
    #expect(hard.score == 2 * (ghostRow - before.row), "하드드롭 점수 \(hard.score) ≠ \(2 * (ghostRow - before.row))")

    // 소프트드롭: 한 칸 내려갈 때마다 1점. 레벨이 높아도 칸당 1점이다.
    var soft = game(board: TetrisGame.emptyBoard(), piece: .o, advance: 930)
    soft.setSoftDropHeld(true)
    soft.step(dt: TetrisGame.maxStep)
    #expect(soft.score > 0 && soft.score == soft.active!.row - TetrisGame.spawnRow,
            "소프트드롭 점수 \(soft.score) 가 내려간 칸수 \(soft.active!.row - TetrisGame.spawnRow) 와 다르다")
}

@Test("엔진이 점수를 maxScore 에서 스스로 자른다(업로드 게이트가 초과분을 조용히 버린다)")
func theEngineClampsItsOwnScoreAtMaxScore() {
    var g = verticalIAtLastColumn(rows: 4, advance: 930, score: TetrisGame.maxScore - 100)
    g.action()
    #expect(g.score == TetrisGame.maxScore, "점수가 \(g.score) 로 상한을 넘거나 못 미친다")
    #expect(TetrisGame.maxScore == 100_000_000)
}

// MARK: - (6) 7-bag

@Test("7-bag — 한 봉지에 7종이 정확히 한 번씩 들어간다")
func everyBagContainsAllSevenPiecesExactlyOnce() {
    var rng = MiniGameRandom(seed: 20260923)
    var sawShuffle = false
    let ordered = Piece.allCases
    for _ in 0..<200 {
        let bag = TetrisGame.shuffledBag(&rng)
        #expect(bag.count == 7)
        #expect(Set(bag).count == 7, "한 봉지에 중복이 있다: \(bag)")
        if bag != ordered { sawShuffle = true }
    }
    #expect(sawShuffle, "200봉지가 전부 제자리다 — 섞이지 않았다")
}

@Test("7-bag — 판이 내놓는 조각도 7개마다 한 바퀴고, 같은 시드는 같은 순서다")
func theQueueDealsCompleteBagsAndIsDeterministicPerSeed() {
    func deal(seed: UInt64) -> [Piece] {
        var g = TetrisGame(seed: seed)
        g.action()
        var pieces = [g.active!.piece] + g.next          // 6개
        for _ in 0..<8 {
            g.action()                                    // 하드드롭 → 고정
            advanceToNextPiece(&g)
            guard case .running = g.phase else { break }
            pieces.append(g.next[TetrisGame.nextCount - 1])
        }
        return pieces
    }
    let first = deal(seed: 314)
    #expect(first.count == 14, "조각을 \(first.count)개만 받았다 — 시나리오가 중간에 끝났다")
    #expect(Set(first.prefix(7)).count == 7, "첫 7개에 중복이 있다: \(first.prefix(7))")
    #expect(Set(first.dropFirst(7)).count == 7, "다음 7개에 중복이 있다: \(first.dropFirst(7))")
    #expect(deal(seed: 314) == first, "같은 시드가 다른 순서를 냈다")
    #expect(deal(seed: 315) != first, "다른 시드가 같은 순서를 냈다 — 시드가 안 먹는다")
    #expect(TetrisGame.nextCount == 5)
}

// MARK: - (7) 홀드

@Test("홀드 — 조각당 1회, 굳기 전 재홀드 금지, 굳으면 다시 쓸 수 있다")
func holdIsOncePerPieceAndComesBackAfterTheLock() {
    var g = TetrisGame(seed: 88)
    g.action()
    let firstPiece = g.active!.piece
    let queued = g.next[0]
    #expect(g.heldPiece == nil && !g.holdUsed)

    g.holdCurrentPiece()
    #expect(g.heldPiece == firstPiece, "홀드 상자에 \(String(describing: g.heldPiece))")
    #expect(g.active?.piece == queued, "넥스트에서 조각을 안 꺼냈다")
    #expect(g.active?.row == TetrisGame.spawnRow && g.active?.column == TetrisGame.spawnColumn,
            "갈아탄 조각이 스폰 자리로 안 돌아갔다 — 리셋 바닥 2 의 종료 보장이 여기 기댄다")
    #expect(g.holdUsed)

    let before = g
    g.holdCurrentPiece()
    #expect(g == before, "굳기 전에 다시 홀드가 됐다")

    g.action()                       // 하드드롭 → 고정
    #expect(!g.holdUsed, "고정 뒤에도 홀드가 잠겨 있다")
    advanceToNextPiece(&g)
    let third = g.active!.piece
    g.holdCurrentPiece()
    #expect(g.heldPiece == third, "두 번째 홀드에서 상자가 안 바뀌었다")
    #expect(g.active?.piece == firstPiece, "상자에 있던 조각이 안 나왔다")
}

// MARK: - (8) 탑아웃(블록아웃)

@Test("탑아웃 — 스폰 4칸 중 하나라도 막혀 있으면 그 자리에서 끝난다")
func aBlockedSpawnEndsTheRoundImmediately() {
    // 스폰 상자가 지나는 4~7열을 버퍼행까지 채워 둔다.
    var board = TetrisGame.emptyBoard()
    for row in TetrisGame.spawnRow..<TetrisGame.totalRows {
        for column in 3...6 { board[row][column] = .i }
    }
    // 굳을 조각은 막힌 열 밖(2·3열)에 둔다 — 줄은 안 지워진다.
    var g = game(board: board, piece: .o, column: 1, row: 30)
    g.action()                                  // 하드드롭 → 고정
    #expect(!g.isGameOver, "고정하자마자 끝났다 — 텀이 없다")
    advanceToNextPiece(&g)
    #expect(g.isGameOver, "스폰이 막혔는데 판이 안 끝났다")
    // 유예가 지나면 결과 카드.
    for _ in 0..<40 { g.step(dt: TetrisGame.maxStep) }
    #expect(g.phase == .result)
    #expect(!g.isPlaying)
}

@Test("판은 탑아웃으로만 끝난다 — 끝나는 순간 스폰 자리가 막혀 있다(시간 상한이 없다)")
func theOnlyEndingIsBlockOutSoThereIsNoTimeLimit() {
    // 아무 키도 안 누르고 중력만 기다린다. 조각이 스폰 열에 쌓여 언젠가 블록아웃이 나는데,
    // **끝나는 이유가 언제나 '스폰 자리가 막혔다' 하나**여야 한다.
    var g = TetrisGame(seed: 4)
    g.action()
    var steps = 0
    while !g.isGameOver && steps < 20_000 {
        g.step(dt: TetrisGame.maxStep)
        steps += 1
    }
    #expect(g.isGameOver, "20000프레임(약 11분) 동안 아무 일도 안 났다 — 시나리오가 헛돈다")
    #expect(g.active != nil, "끝난 자리의 조각이 없다 — 어디서 막혔는지 화면이 못 보여 준다")
    if let blocked = g.active {
        #expect(!g.fits(blocked), "판이 끝났는데 스폰 자리가 비어 있다 — 블록아웃이 아닌 이유로 끝났다")
    }
    // 시계로 끝난 게 아니라는 확인: 판은 50초 넘게 살아 있었고, 그 사이 조각이 여러 개 굳었다.
    #expect(g.elapsed > 40, "판 시계가 \(g.elapsed)초에서 끝났다")
    #expect(g.advance > 8, "굳은 조각이 \(g.advance)개뿐이다 — 스폰 열에 쌓여 막힌 것이 맞는지 의심하라")
}

// MARK: - 판 · 스폰 기하

@Test("판은 10×40 이고 스폰은 보이는 판 바로 위 두 줄이다")
func theBoardAndSpawnGeometryMatchTheStandard() {
    #expect(TetrisGame.columns == 10 && TetrisGame.totalRows == 40 && TetrisGame.visibleRows == 20)
    #expect(TetrisGame.firstVisibleRow == 20)
    for piece in Piece.allCases {
        let rows = Set(TetrisGame.shape(piece, .spawn).map { TetrisGame.spawnRow + $0.dy })
        #expect(rows.allSatisfy { $0 < TetrisGame.firstVisibleRow },
                "\(piece) 스폰이 보이는 판 안이다(\(rows.sorted()))")
        #expect(rows.allSatisfy { $0 >= TetrisGame.firstVisibleRow - 2 },
                "\(piece) 스폰이 버퍼 두 줄보다 위다(\(rows.sorted()))")
    }
}

@Test("고스트는 지금 하드드롭하면 앉을 자리다")
func theGhostIsWhereAHardDropWouldLand() {
    var g = verticalIAtLastColumn(rows: 4)
    let ghost = g.ghost
    g.action()
    #expect(ghost != nil)
    if let ghost {
        // 고스트가 앉은 자리에 실제로 칸이 굳었다(그 줄들은 지워졌으므로 바닥 4줄이 사라졌는지로 확인).
        #expect(ghost.row == TetrisGame.totalRows - 4, "고스트 행 \(ghost.row)")
    }
    #expect(g.lastClear?.lines == 4)
}

// MARK: - (9) 폰 걸음 — 손가락 한 칸(v0.3.38 폰 단계)

// 폰은 키가 없다. 손가락이 셀 한 칸만큼 움직일 때마다 **걸음 하나**를 엔진에 넣는다:
//   · 가로 한 칸 = `setLeftHeld(true)` + `setLeftHeld(false)` 를 **같은 호출 안에서 연달아**(엔진 무수정).
//   · 세로 한 칸 = `softDropOneCell()`(v0.3.38 에 더한 유일한 엔진 API).
// 아래 여섯 테스트가 그 두 걸음의 계약이다. 깨지면 폰 조작이 통째로 죽는데, 키보드 경로만 재는 기존 규칙
// 테스트는 전부 초록이다 — 그래서 따로 못 박는다.

/// 빈 판 · 레벨 1 · 스폰 자리의 O. 폰 걸음 측정의 공통 기준판이다(양옆 4칸 · 아래 20칸 넘게 비어 있다).
private func phoneStepFixture(advance: Int = 0) -> TetrisGame {
    game(board: TetrisGame.emptyBoard(), piece: .o,
         column: TetrisGame.spawnColumn, row: TetrisGame.spawnRow, advance: advance)
}

@Test("소프트드롭 한 칸 — 정확히 한 칸 · 1점 · 판 시계는 안 흐른다(레벨 배수도 없다)")
func softDropOneCellMovesExactlyOneCellForOnePoint() throws {
    var g = phoneStepFixture()
    let before = try #require(g.active)
    let moved = g.softDropOneCell()
    #expect(moved, "한 칸도 못 내려갔다")
    let after = try #require(g.active)
    #expect(after.row == before.row + 1, "\(before.row) → \(after.row) 로 갔다(한 칸이 아니다)")
    #expect(after.column == before.column && after.rotation == before.rotation, "옆으로 새거나 돌았다")
    #expect(g.score == 1, "한 칸에 \(g.score)점을 줬다 — 칸당 1점이다")
    #expect(g.elapsed == 0, "손가락 한 칸이 판 시계를 흘렸다 — 시간은 step(dt:) 만 흘린다")

    // 세 칸이면 세 칸 · 3점. 레벨이 높아도 칸당 1점이다(하드드롭 2점/칸과 달리 배수가 없다).
    var high = phoneStepFixture(advance: 930)
    #expect(high.level == 28, "전제(레벨 28)가 깨졌다")
    let start = try #require(high.active).row
    for _ in 0..<3 { high.softDropOneCell() }
    #expect(high.active?.row == start + 3, "세 번 불렀는데 세 칸이 아니다")
    #expect(high.score == 3, "레벨 28에서 \(high.score)점 — 칸당 1점이 아니다")
}

@Test("소프트드롭 한 칸 — 못 내려가면 **아무것도 안 한다**(굳히지 않는다. 굳히는 것은 락딜레이의 일이다)")
func softDropOneCellDoesNothingWhenItCannotMove() {
    // 접지한 조각: 손가락을 아래로 더 끌어도 판이 하나도 안 바뀌어야 한다. `==` 는 내부 시계까지 전부 본다.
    var grounded = game(board: TetrisGame.boardFixture(bottomRows: flatFloor), piece: .t, column: 3, row: 36)
    #expect(grounded.isGrounded, "픽스처가 접지 상태가 아니다 — 이 테스트의 전제가 깨졌다")
    let groundedBefore = grounded
    let moved = grounded.softDropOneCell()
    #expect(!moved)
    #expect(grounded == groundedBefore, "못 내려가는 자리에서 뭔가 바뀌었다(점수·시계·접지 회계 중 하나)")
    #expect(grounded.active != nil, "못 내려간 조각을 굳혔다 — 굳히는 것은 락딜레이의 일이다")

    // running 이 아니면(시작 전·텀·결과) 아무 일도 없다.
    var ready = TetrisGame(seed: 3)
    let readyBefore = ready
    // ⚠️ `#expect` 는 값을 불변으로 캡처한다 — mutating 호출은 **지역 변수에 먼저 받는다**(이 저장소의 함정 3번).
    let readyMoved = ready.softDropOneCell()
    #expect(!readyMoved, "시작도 안 한 판이 내려갔다")
    #expect(ready == readyBefore)

    // ★ 기준선이 다르다: 한 칸 위였다면 같은 호출이 실제로 내려간다(위 '무변화'가 공허하지 않다).
    var free = game(board: TetrisGame.boardFixture(bottomRows: flatFloor), piece: .t, column: 3, row: 35)
    let freeMoved = free.softDropOneCell()
    #expect(freeMoved, "한 칸 위에서도 안 내려간다 — 이 비교의 기준선이 헛돈다")
}

@Test("소프트드롭 한 칸 — 낙하 시계를 되감는다(손가락 한 칸 뒤에 중력 한 칸이 공짜로 따라오지 않는다)")
func softDropOneCellRewindsTheFallClock() {
    let dt = TetrisGame.maxStep                          // 0.05 — step(dt:) 첫 줄이 여기서 자른다
    let gravity = TetrisGame.gravitySeconds(forLevel: 1) // ≈ 0.3552초/칸
    #expect(gravity > 7 * dt && gravity < 8 * dt, "L1 중력 \(gravity)초 — 이 검산의 전제(7~8프레임)가 깨졌다")

    // ① 기준선: 손을 안 대면 여덟 번째 프레임에 중력이 한 칸을 준다.
    var plain = phoneStepFixture()
    for _ in 0..<7 { plain.step(dt: dt) }
    #expect(plain.active?.row == TetrisGame.spawnRow, "일곱 프레임 만에 떨어졌다 — 전제가 깨졌다")
    plain.step(dt: dt)
    #expect(plain.active?.row == TetrisGame.spawnRow + 1, "여덟 번째 프레임에 중력이 안 왔다")

    // ② 같은 자리에서 손가락으로 한 칸 내리면, 바로 다음 프레임에 중력 한 칸이 **따라오지 않는다**.
    var dropped = phoneStepFixture()
    for _ in 0..<7 { dropped.step(dt: dt) }
    let droppedMoved = dropped.softDropOneCell()
    #expect(droppedMoved, "손가락 한 칸이 안 먹었다")
    #expect(dropped.active?.row == TetrisGame.spawnRow + 1)
    dropped.step(dt: dt)
    #expect(dropped.active?.row == TetrisGame.spawnRow + 1,
            "되감기를 안 해서 손가락 한 칸 뒤에 중력 한 칸이 공짜로 붙었다(내린 만큼의 두 배가 간다)")

    // ③ 그렇다고 중력을 멈추지도 않는다: 되감긴 만큼(중력 한 칸)이 지나면 다음 칸이 온다.
    for _ in 0..<6 { dropped.step(dt: dt) }   // 되감긴 뒤 합계 0.35 < 0.3552
    #expect(dropped.active?.row == TetrisGame.spawnRow + 1, "되감기가 중력을 통째로 멈췄다")
    dropped.step(dt: dt)                      // 0.40 > 0.3552
    #expect(dropped.active?.row == TetrisGame.spawnRow + 2, "되감긴 시계가 만기돼도 안 떨어진다")
    #expect(dropped.score == 1, "중력 칸에 점수가 붙었다(소프트드롭 한 칸 1점만이어야 한다)")
}

@Test("소프트드롭 한 칸 — 접지 리셋 예산을 **안 쓴다**(중력이 그렇듯이)")
func softDropOneCellNeverSpendsTheLockResetBudget() {
    // L28: 리셋 한도 2 · 재충전 없음. 예산을 다 쓰면 **바닥에 닿는 순간 곧바로** 굳는다(락딜레이 0.205초를 못 쓴다).
    // 그래서 "닿은 직후 한 프레임 뒤에도 조각이 살아 있는가"가 곧 "예산이 남았는가"다.
    func fixture() -> TetrisGame {
        game(board: TetrisGame.boardFixture(bottomRows: level28Stack), piece: .o, advance: 930)
    }
    #expect(TetrisGame.lockResetLimit(forLevel: fixture().level) == 2, "리셋 한도 전제가 깨졌다")
    #expect(!TetrisGame.lockResetRefreshes(forLevel: fixture().level), "재충전이 켜져 있으면 이 측정이 헛돈다")

    // ① 손가락으로만 내려 접지시킨다 — 예산을 한 번도 안 썼으므로 락딜레이를 그대로 받는다.
    var soft = fixture()
    var cells = 0
    while soft.softDropOneCell() { cells += 1 }
    #expect(cells >= 3, "\(cells)칸밖에 안 내려갔다 — 픽스처가 이미 바닥 근처다")
    #expect(soft.isGrounded)
    soft.step(dt: 1.0 / 120.0)
    #expect(soft.active != nil, "소프트드롭 \(cells)칸이 리셋 예산을 썼다 — 닿자마자 굳었다")

    // ② ★ 기준선이 다르다: 가로 이동 두 번은 예산을 **정말** 쓴다. 같은 자리에서 닿는 순간 굳는다.
    var shifted = fixture()
    shifted.setLeftHeld(true); shifted.setLeftHeld(false)
    shifted.setRightHeld(true); shifted.setRightHeld(false)
    while shifted.softDropOneCell() {}
    #expect(shifted.isGrounded)
    shifted.step(dt: 1.0 / 120.0)
    #expect(shifted.active == nil, "예산 2를 다 썼는데 안 굳었다 — 이 비교의 기준선이 헛돈다")
}

@Test("폰 가로 한 칸 — 누름+뗌을 **연달아** 부르면 정확히 한 칸이고 자동 반복이 남지 않는다")
func aPressReleasePairMovesExactlyOneCellAndArmsNoRepeat() throws {
    // ⚠️ 이 쌍은 **엔진 내부 구현에 기대는 배선**이다(누름이 즉시 한 칸을 주고, 뗌은 이동을 안 주며, 쌍 사이에
    //    시간이 안 흐르므로 DAS 0.167초가 만기될 수 없다). 그래서 여기서 못 박는다 — 깨지면 폰 가로 이동이
    //    통째로 죽는데 키보드 경로만 재는 규칙 테스트는 전부 초록이다.
    let start = try #require(phoneStepFixture().active).column

    // ① 한 쌍 = 정확히 한 칸(양쪽 다). 판 시계는 안 흐른다.
    var left = phoneStepFixture()
    left.setLeftHeld(true); left.setLeftHeld(false)
    #expect(left.active?.column == start - 1, "왼쪽 한 쌍이 \(left.active?.column ?? -99) 로 갔다(기대 \(start - 1))")
    #expect(left.elapsed == 0, "쌍 사이에 시간이 흘렀다 — step(dt:) 을 끼우면 DAS 가 만기된다")

    var right = phoneStepFixture()
    right.setRightHeld(true); right.setRightHeld(false)
    #expect(right.active?.column == start + 1, "오른쪽 한 쌍이 \(right.active?.column ?? -99) 로 갔다")

    // ② 세 쌍 = 정확히 세 칸(쌓이지도, 한 칸으로 접히지도 않는다).
    var three = phoneStepFixture()
    for _ in 0..<3 { three.setLeftHeld(true); three.setLeftHeld(false) }
    #expect(three.active?.column == start - 3, "세 쌍이 \(three.active?.column ?? -99) 로 갔다(기대 \(start - 3))")

    // ③ 쌍이 끝나면 자동 반복이 **안 남는다**: DAS 두 배를 흘려도 더 안 간다.
    var idle = phoneStepFixture()
    idle.setLeftHeld(true); idle.setLeftHeld(false)
    let afterPair = try #require(idle.active).column
    let window = TetrisGame.dasSeconds * 2
    var elapsed = 0.0
    while elapsed < window {
        idle.step(dt: TetrisGame.maxStep)
        elapsed += TetrisGame.maxStep
    }
    #expect(idle.active?.column == afterPair,
            "쌍이 끝났는데 DAS 가 살아남아 \(idle.active?.column ?? -99) 까지 흘렀다")

    // ★ 기준선이 다르다: **떼지 않으면** 같은 시간에 DAS/ARR 가 여러 칸을 준다.
    var held = phoneStepFixture()
    held.setLeftHeld(true)
    elapsed = 0
    while elapsed < window {
        held.step(dt: TetrisGame.maxStep)
        elapsed += TetrisGame.maxStep
    }
    #expect((held.active?.column ?? 99) < afterPair,
            "누른 채 둬도 한 칸뿐이다(\(held.active?.column ?? 99)) — 이 비교의 기준선이 헛돈다")
}

@Test("폰 두 걸음을 섞어도 판은 결정적이다 — 가로 쌍과 소프트드롭이 서로의 시계를 안 건드린다")
func phoneStepsDoNotDisturbEachOther() throws {
    // 손가락은 대각선으로 움직인다 — 한 프레임에 가로 쌍과 세로 걸음이 같이 온다. 그때도 결과가 한 칸씩이어야 한다.
    var g = phoneStepFixture()
    let start = try #require(g.active)
    g.setLeftHeld(true); g.setLeftHeld(false)
    g.softDropOneCell()
    g.setRightHeld(true); g.setRightHeld(false)
    g.softDropOneCell()
    let after = try #require(g.active)
    #expect(after.column == start.column, "가로 쌍 둘(왼·오)이 제자리로 안 돌아왔다")
    #expect(after.row == start.row + 2, "세로 두 걸음이 \(after.row - start.row)칸이 됐다")
    #expect(g.score == 2, "점수 \(g.score) — 소프트드롭 두 칸이면 2점이다")
    #expect(g.elapsed == 0, "걸음이 판 시계를 흘렸다")
}
