import Foundation
import Testing
@testable import CheckCore

// v0.3.60 테트리스 1:1 — 엔진 대결 확장(공격 표 · 상쇄 · 삽입 · 탑아웃 · 구멍 난수 분리 · 레벨 바닥)과 200글자 판.
//
// 기준선 원칙: 상쇄·삽입·바닥을 재는 테스트마다 **그것이 없는 판**을 같은 입력으로 함께 돌려 차이가 그 장치에서만
// 난다는 것을 보인다(같은 판끼리 비교하면 영원히 초록이다).

private typealias DPiece = TetrisGame.Piece
private typealias DActive = TetrisGame.ActivePiece

/// 오른쪽 끝 열만 빈 줄 `rows` 개 위에 세로 I 를 둔 판(하드드롭 하면 그 줄들을 지운다).
private func wellGame(rows: Int, seed: UInt64 = 11, pending: [Int] = [], attackSent: Int = 0) -> TetrisGame {
    let filler = Array(repeating: "IIIIIIIII.", count: rows)
    // 세로 I(rotation .right)는 상자의 dx = 2 열을 쓴다 → column 7 이면 9열.
    return TetrisGame(seed: seed, board: TetrisGame.boardFixture(bottomRows: filler),
                      active: DActive(piece: .i, rotation: .right, column: 7, row: TetrisGame.spawnRow),
                      pendingGarbage: pending, attackSentTotal: attackSent)
}

/// 바닥에 그대로 앉아 아무 줄도 못 지우는 O(3~4열).
private func flatGame(board: [[DPiece?]] = TetrisGame.emptyBoard(), mask: [UInt16] = [],
                      seed: UInt64 = 11, pending: [Int] = []) -> TetrisGame {
    TetrisGame(seed: seed, board: board,
               active: DActive(piece: .o, rotation: .spawn, column: 2, row: TetrisGame.spawnRow),
               pendingGarbage: pending, garbageMask: mask)
}

/// 텀을 지나 다음 조각이 뜰 때까지.
private func toNextPiece(_ g: inout TetrisGame) {
    var guardCount = 0
    while guardCount < 400 {
        switch g.phase {
        case .are, .lineClear: g.step(dt: TetrisGame.maxStep)
        default: return
        }
        guardCount += 1
    }
}

private func holeColumn(_ row: [DPiece?]) -> Int? {
    let empty = row.indices.filter { row[$0] == nil }
    return empty.count == 1 ? empty[0] : nil
}

@Suite("v0.3.60 테트리스 대결 — 엔진 확장")
struct V0360TetrisDuelEngineTests {

    // MARK: 기본값 = 꺼짐

    @Test("새 판의 대결 칸은 전부 꺼져 있다(대기 0 · 누계 0 · 표시 0 · 바닥 1 · 난이도 = level)")
    func duelStateDefaultsAreOff() {
        let g = TetrisGame(seed: 5)
        #expect(g.pendingGarbage.isEmpty && g.pendingGarbageLines == 0)
        #expect(g.attackSentTotal == 0)
        #expect(g.garbageMask == Array(repeating: 0, count: TetrisGame.totalRows))
        #expect(g.levelFloor == 1)
        #expect(g.difficultyLevel == g.level)
        var started = g
        started.action()
        #expect(started.levelFloor == 1 && started.pendingGarbage.isEmpty && started.attackSentTotal == 0)
    }

    // MARK: 공격 표

    @Test("공격 표 — 1줄 0 · 2줄 1 · 3줄 2 · 4줄 4 (가산 없음)")
    func attackTableMatchesTheUserDecision() {
        #expect((0...4).map { TetrisGame.attackLines(lines: $0) } == [0, 0, 1, 2, 4])
        #expect(TetrisGame.attackLines(lines: -1) == 0)
    }

    @Test("실제 굳힘이 표대로 공격 누계를 올리고 lastClear.attack 에 싣는다 — 1~4줄")
    func lockingAppliesTheAttackTable() {
        for (rows, expected) in [(1, 0), (2, 1), (3, 2), (4, 4)] {
            var g = wellGame(rows: rows)
            g.action()
            #expect(g.lastClear?.lines == rows, "\(rows)줄 픽스처가 \(g.lastClear?.lines ?? -1)줄을 지웠다")
            #expect(g.lastClear?.attack == expected)
            #expect(g.attackSentTotal == expected, "\(rows)줄 → 누계 \(g.attackSentTotal) ≠ \(expected)")
        }
    }

    @Test("T-스핀·B2B·콤보·퍼펙트는 공격을 더하지 않는다 — 4줄 퍼펙트 + B2B 사슬도 4")
    func noBonusesOnAttack() {
        // 4줄을 지우면 판이 비는 픽스처(퍼펙트) + B2B 사슬이 이미 있는 상태 + 콤보 진행 중.
        var g = TetrisGame(seed: 3, board: TetrisGame.boardFixture(bottomRows: Array(repeating: "IIIIIIIII.", count: 4)),
                           active: DActive(piece: .i, rotation: .right, column: 7, row: TetrisGame.spawnRow),
                           combo: 3, backToBack: 2)
        g.action()
        #expect(g.lastClear?.perfectClear == true && g.lastClear?.backToBack == true, "전제가 깨졌다")
        #expect(g.attackSentTotal == 4)
    }

    // MARK: 상쇄

    @Test("상쇄 — 4줄 공격이 대기 3줄을 먼저 깎고 1만 보낸다 · 상쇄 없는 판은 4를 보낸다")
    func attackCancelsPendingFirst() {
        var baseline = wellGame(rows: 4)
        baseline.action()
        var g = wellGame(rows: 4)
        let accepted = g.receiveGarbage(lines: 3)
        #expect(accepted)
        g.action()
        #expect(baseline.attackSentTotal == 4)
        #expect(g.attackSentTotal == 1, "상쇄 뒤 보낸 공격 \(g.attackSentTotal) ≠ 1")
        #expect(g.pendingGarbage.isEmpty)
        #expect(g.lastClear?.attack == 4, "lastClear.attack 은 상쇄 전 값이다")
        // 줄을 지운 굳힘이라 판에는 아무것도 안 들어왔다 — 두 판이 같다(대기·누계만 다르다).
        #expect(g.board == baseline.board)
    }

    @Test("상쇄는 앞 묶음부터 깎는다 — [1,2,3] 에 3줄 공격(2)이면 [1,3] 이 남고 보낸 것은 0")
    func cancellationTrimsFromTheFront() {
        var g = wellGame(rows: 3, pending: [1, 2, 3])
        g.action()
        #expect(g.pendingGarbage == [1, 3], "남은 대기 \(g.pendingGarbage)")
        #expect(g.attackSentTotal == 0)
        // 대기보다 큰 공격: 남은 것만 보낸다.
        var h = wellGame(rows: 4, pending: [1, 1])
        h.action()
        #expect(h.pendingGarbage.isEmpty && h.attackSentTotal == 2)
    }

    @Test("공격 누계는 단조 증가 — 연속 굳힘에서 줄지 않는다")
    func attackTotalIsMonotonic() {
        var g = wellGame(rows: 4, attackSent: 7)
        g.action()
        #expect(g.attackSentTotal == 11)
        toNextPiece(&g)
        let before = g.attackSentTotal
        g.action()   // 빈 판에 아무 조각이나 하드드롭 — 줄 없음
        #expect(g.attackSentTotal == before)
    }

    // MARK: 삽입

    @Test("삽입은 줄을 안 지운 굳힘에서만 — 1줄 소거에서는 대기가 그대로, 다음 소거 없는 굳힘에서 바닥에 들어온다")
    func garbageEntersOnlyOnANonClearingLock() {
        var g = wellGame(rows: 1, pending: [2])
        g.action()
        #expect(g.lastClear?.lines == 1)
        #expect(g.pendingGarbage == [2], "줄을 지운 굳힘에서 방해 줄이 들어왔다")
        #expect(g.garbageMask.allSatisfy { $0 == 0 })
        toNextPiece(&g)
        // 기준선: 같은 판·같은 조각에서 대기만 없는 것(픽스처로 다시 만든다).
        var baseline = TetrisGame(seed: 11, board: g.board, active: g.active, phase: .running, next: g.next)
        var withGarbage = TetrisGame(seed: 11, board: g.board, active: g.active, phase: .running, next: g.next,
                                     pendingGarbage: [2])
        baseline.action()
        withGarbage.action()
        #expect(baseline.lastClear?.lines == 0 && withGarbage.lastClear?.lines == 0)
        #expect(withGarbage.pendingGarbage.isEmpty)
        // 바닥 두 행이 방해 줄(구멍 하나 · 같은 구멍)이고, 그 위는 기준선 판을 두 행 올린 것과 같다.
        let rows = TetrisGame.totalRows
        let holeA = holeColumn(withGarbage.board[rows - 1])
        let holeB = holeColumn(withGarbage.board[rows - 2])
        #expect(holeA != nil && holeA == holeB, "같은 묶음 두 줄의 구멍이 다르다(\(String(describing: holeA)) · \(String(describing: holeB)))")
        #expect(Array(withGarbage.board.prefix(rows - 2)) == Array(baseline.board.dropFirst(2)),
                "방해 줄 위의 판이 기준선을 두 행 올린 것과 다르다")
        let full = UInt16((1 << TetrisGame.columns) - 1)
        #expect(withGarbage.garbageMask[rows - 1] == full & ~(UInt16(1) << holeA!))
        #expect(withGarbage.garbageMask[rows - 2] == full & ~(UInt16(1) << holeA!))
        #expect(withGarbage.garbageMask.prefix(rows - 2).allSatisfy { $0 == 0 })
        #expect(withGarbage.isGarbage(row: rows - 1, column: (holeA! + 1) % TetrisGame.columns))
        #expect(!withGarbage.isGarbage(row: rows - 1, column: holeA!))
        guard case .are = withGarbage.phase else {
            Issue.record("삽입 뒤 텀으로 안 갔다: \(withGarbage.phase)")
            return
        }
    }

    @Test("한 번에 최대 8줄 — [5,6] 이면 8줄이 들어오고 3줄은 남아 다음 굳힘에서 **같은 구멍**으로 들어온다 · 먼저 온 묶음이 위")
    func insertionIsCappedAtEightAndKeepsTheHoleOfASplitBatch() {
        var g = flatGame(pending: [5, 6])
        g.action()
        #expect(g.pendingGarbage == [3], "남은 대기 \(g.pendingGarbage)")
        let rows = TetrisGame.totalRows
        let garbageRows = (0..<rows).filter { g.garbageMask[$0] != 0 }
        #expect(garbageRows == Array((rows - 8)..<rows), "방해 줄 행이 바닥 8행이 아니다: \(garbageRows)")
        let firstBatchHole = holeColumn(g.board[rows - 8])
        let secondBatchHole = holeColumn(g.board[rows - 1])
        for r in (rows - 8)..<(rows - 3) { #expect(holeColumn(g.board[r]) == firstBatchHole, "먼저 온 묶음(위 5행)의 구멍이 갈렸다") }
        for r in (rows - 3)..<rows { #expect(holeColumn(g.board[r]) == secondBatchHole, "둘째 묶음(아래 3행)의 구멍이 갈렸다") }
        toNextPiece(&g)
        g.action()   // 다음 조각도 줄 없이 굳는다(구멍이 3열 근처가 아닌 한) — 남은 3줄이 들어온다.
        if g.lastClear?.lines == 0 {
            #expect(g.pendingGarbage.isEmpty)
            for r in (rows - 3)..<rows {
                #expect(holeColumn(g.board[r]) == secondBatchHole, "잘린 묶음의 나머지가 다른 구멍으로 들어왔다")
            }
        }
    }

    @Test("방해 줄 탑아웃 — 맨 위 n행에 칸이 있으면 밀지 않고 끝난다 · 한 행 덜 차 있으면 들어온다(기준선)")
    func garbageThatWouldPushBlocksOffTheTopEndsTheGame() {
        var board = TetrisGame.emptyBoard()
        for r in 2..<TetrisGame.totalRows { board[r][0] = .i }      // 0열 탑이 2행까지(맨 위 두 행은 비었다)
        var dies = flatGame(board: board, pending: [3])
        var lives = flatGame(board: board, pending: [2])
        dies.action()
        lives.action()
        guard case .over = dies.phase else {
            Issue.record("맨 위 3행에 칸이 있는데 방해 줄 3줄이 들어갔다: \(dies.phase)")
            return
        }
        #expect(dies.board[2][0] == .i, "탑아웃인데 판을 밀었다(칸이 사라졌다)")
        #expect(dies.isGameOver)
        guard case .are = lives.phase else {
            Issue.record("맨 위 2행은 비었는데 탑아웃했다: \(lives.phase)")
            return
        }
        #expect(lives.board[0][0] == .i, "2줄이 들어와 탑이 맨 위까지 올라가야 한다")
        // 판이 끝나면 더 받지 않는다.
        let afterEnd = dies.receiveGarbage(lines: 1)
        #expect(!afterEnd)
    }

    @Test("줄 지우기는 방해 줄 표시를 판과 같은 술어로 거른다 — 지운 행 위의 방해 줄 행이 표시와 함께 내려온다")
    func clearingRowsKeepsTheGarbageMaskAligned() {
        // 38행: 방해 줄(4·9열 빈칸) · 39행: 9열만 빈 보통 줄. 세로 I 를 9열에 꽂으면 39행만 지워진다.
        let lines = ["GGGG.GGGG.", "IIIIIIIII."]
        var g = TetrisGame(seed: 2, board: TetrisGame.boardFixture(bottomRows: lines),
                           active: DActive(piece: .i, rotation: .right, column: 7, row: TetrisGame.spawnRow),
                           garbageMask: TetrisGame.garbageMaskFixture(bottomRows: lines))
        #expect(g.garbageMask[38] != 0 && g.garbageMask[39] == 0, "픽스처 전제가 깨졌다")
        g.action()
        #expect(g.lastClear?.lines == 1)
        let expected = TetrisGame.garbageMaskFixture(bottomRows: ["GGGG.GGGG."])[39]
        #expect(g.garbageMask[39] == expected, "방해 줄 행이 내려왔는데 표시가 안 따라왔다")
        #expect(g.garbageMask[38] == 0)
        #expect(g.board[39][9] == .i && !g.isGarbage(row: 39, column: 9), "I 가 채운 칸을 방해 줄로 칠한다")
    }

    // MARK: 결정성

    /// 하드드롭만 하는 판에서 조각이 뜰 때마다 적는다. `arrivals[k]` = k 번째 조각이 뜰 때 받을 방해 줄.
    private static func pieceOrder(seed: UInt64, arrivals: [Int: Int], pieces: Int) -> (order: [DPiece], garbageRows: [UInt16]) {
        var g = TetrisGame(seed: seed)
        g.action()
        var order: [DPiece] = []
        var column = 0
        while order.count < pieces {
            guard case .running = g.phase, let a = g.active else {
                if g.isGameOver { break }
                g.step(dt: TetrisGame.maxStep)
                continue
            }
            order.append(a.piece)
            if let n = arrivals[order.count] { g.receiveGarbage(lines: n) }
            // 열을 돌려 가며 놓아 판이 고르게 쌓이게(줄도 가끔 지운다).
            g.rotate(clockwise: true)
            for _ in 0..<5 { g.setLeftHeld(true); g.setLeftHeld(false) }
            for _ in 0..<column { g.setRightHeld(true); g.setRightHeld(false) }
            column = (column + 3) % 8
            g.action()
        }
        return (order, g.garbageMask.filter { $0 != 0 })
    }

    @Test("같은 시드면 공격이 언제 얼마나 오든 조각 순서가 같다 — 구멍 난수가 조각 난수와 따로 돈다")
    func pieceOrderDoesNotDependOnGarbageArrival() {
        let calm = Self.pieceOrder(seed: 99, arrivals: [:], pieces: 40)
        let early = Self.pieceOrder(seed: 99, arrivals: [2: 3, 5: 1, 9: 4], pieces: 40)
        let late = Self.pieceOrder(seed: 99, arrivals: [7: 2, 8: 2, 20: 4], pieces: 40)
        let n = min(calm.order.count, early.order.count, late.order.count)
        #expect(n >= 14, "판이 너무 일찍 끝나 비교할 조각이 \(n)장뿐이다")
        #expect(Array(early.order.prefix(n)) == Array(calm.order.prefix(n)), "공격이 조각 순서를 바꿨다")
        #expect(Array(late.order.prefix(n)) == Array(calm.order.prefix(n)), "공격 시점이 조각 순서를 바꿨다")
        // 기준선: 다른 시드는 다른 순서다(위 비교가 공허하지 않다).
        let other = Self.pieceOrder(seed: 100, arrivals: [:], pieces: 14)
        #expect(Array(other.order.prefix(14)) != Array(calm.order.prefix(14)))
    }

    @Test("같은 시드·같은 묶음 순서면 도착 시점이 달라도 구멍 열이 같다")
    func holeSequenceDependsOnlyOnBatchOrder() {
        let a = Self.pieceOrder(seed: 7, arrivals: [2: 2, 3: 3, 4: 1], pieces: 9)
        let b = Self.pieceOrder(seed: 7, arrivals: [2: 2, 6: 3, 8: 1], pieces: 9)
        #expect(!a.garbageRows.isEmpty)
        // 줄 소거가 방해 줄을 지우지 않는 짧은 판에서만 비교한다(지워졌으면 개수가 다르다).
        if a.garbageRows.count == 6, b.garbageRows.count == 6 {
            #expect(a.garbageRows == b.garbageRows, "같은 묶음 순서인데 구멍이 갈렸다")
        } else {
            Issue.record("픽스처 판이 방해 줄을 지웠다(\(a.garbageRows.count) · \(b.garbageRows.count)) — 시나리오를 고쳐라")
        }
    }

    // MARK: 받기 게이트

    @Test("receiveGarbage — 판이 진행 중일 때만 받는다(시작 전 · 결과 화면은 거절) · 0 이하는 무시")
    func receiveIsGatedOnPlay() {
        var ready = TetrisGame(seed: 1)
        let beforeStart = ready.receiveGarbage(lines: 2)
        #expect(!beforeStart)
        #expect(ready.pendingGarbage.isEmpty)
        ready.action()
        let zero = ready.receiveGarbage(lines: 0)
        let negative = ready.receiveGarbage(lines: -3)
        #expect(!zero && !negative)
        let two = ready.receiveGarbage(lines: 2)
        let one = ready.receiveGarbage(lines: 1)
        #expect(two && one)
        #expect(ready.pendingGarbage == [2, 1] && ready.pendingGarbageLines == 3)
        var over = TetrisGame(seed: 1, board: TetrisGame.emptyBoard(), active: nil, phase: .result)
        let onResult = over.receiveGarbage(lines: 1)
        #expect(!onResult)
    }

    @Test("== 는 대결 칸까지 본다")
    func equalityIncludesDuelState() {
        var a = TetrisGame(seed: 4)
        a.action()
        var b = a
        #expect(a == b)
        b.receiveGarbage(lines: 1)
        #expect(a != b)
        var c = a
        c.setLevelFloor(5)
        #expect(a != c)
    }

    // MARK: 레벨 바닥

    @Test("레벨 바닥은 난이도만 바꾼다 — 바닥 15 면 한 걸음에 바닥까지(20G) · 공개 level·scoreLevel 은 그대로 · 기준선은 한 칸")
    func levelFloorDrivesGravityButNotTheDisplayedLevel() {
        let base = TetrisGame(seed: 8, board: TetrisGame.emptyBoard(),
                              active: DActive(piece: .t, column: 3, row: TetrisGame.spawnRow))
        var floored = base
        floored.setLevelFloor(15)
        var plain = base
        floored.step(dt: TetrisGame.maxStep)
        plain.step(dt: TetrisGame.maxStep)
        #expect(floored.isGrounded, "바닥 15 인데 20G 로 안 떨어졌다(행 \(floored.active?.row ?? -1))")
        #expect((plain.active?.row ?? 0) <= TetrisGame.spawnRow + 1, "기준선이 이미 떨어졌다 — 비교가 공허하다")
        #expect(floored.level == 1 && floored.scoreLevel == 1 && floored.difficultyLevel == 15)
    }

    @Test("레벨 바닥 28 — 리셋 한도 2 라 벽까지 못 간다 · 기준선(바닥 1)은 벽에 닿는다")
    func floorTwentyEightLimitsResets() {
        var board = TetrisGame.emptyBoard()
        for c in 3...6 { board[39][c] = .i }   // 스폰 바로 아래가 아니라 바닥에 받침
        let base = TetrisGame(seed: 8, board: board,
                              active: DActive(piece: .o, column: TetrisGame.spawnColumn, row: TetrisGame.spawnRow))
        var floored = base
        floored.setLevelFloor(28)
        floored.step(dt: TetrisGame.maxStep)     // 20G: 곧바로 받침 위에 접지
        #expect(floored.isGrounded, "전제가 깨졌다 — 바닥 28 인데 접지가 아니다")
        var plain = base
        // 사람처럼 한 번 누르고 한 걸음 흘린다(누름 사이에 걸음이 있어야 리셋 한도가 굳힘으로 이어진다).
        for _ in 0..<6 {
            if floored.advance == 0 {
                floored.setLeftHeld(true); floored.setLeftHeld(false)
                floored.step(dt: TetrisGame.maxStep)
            }
            plain.setLeftHeld(true); plain.setLeftHeld(false)
            plain.step(dt: TetrisGame.maxStep)
        }
        #expect(floored.advance == 1, "바닥 28 에서 두 번 움직인 O 가 안 굳었다")
        var oColumns: [Int] = []
        for row in floored.board { for (c, cell) in row.enumerated() where cell == .o { oColumns.append(c) } }
        #expect(oColumns.min() == 2, "리셋 한도 2 면 정확히 두 칸(4→2열)만 간다 — 지금 \(oColumns.min() ?? -1)")
        #expect(plain.active?.cells.map(\.column).min() == 0, "기준선(바닥 1)이 벽에 못 갔다 — 비교가 공허하다")
    }

    @Test("레벨 바닥은 1…30 으로 자르고, 새 판에서 1 로 돌아간다")
    func levelFloorIsClampedAndResetByANewRound() {
        var g = TetrisGame(seed: 1)
        g.setLevelFloor(0)
        #expect(g.levelFloor == 1)
        g.setLevelFloor(1_000)
        #expect(g.levelFloor == TetrisGame.maxLevelFloor)
        g.action()
        #expect(g.levelFloor == 1)
    }
}

// MARK: - 200글자 판

@Suite("v0.3.60 테트리스 대결 — 200글자 판 인코딩")
struct V0360TetrisDuelBoardTests {

    @Test("빈 판은 점 200개 · 길이·글자 집합이 서버 CHECK 와 같다")
    func emptyBoardEncodesToDots() {
        let text = TetrisDuelBoard.encode(TetrisGame(seed: 1))
        #expect(text == String(repeating: ".", count: 200))
        #expect(text == TetrisDuelBoard.emptyText)
        #expect(TetrisDuelBoard.cellCount == 200)
        #expect(TetrisDuelBoard.alphabet == ".IJLOSTZG")
        #expect(TetrisDuelBoard.isValid(text))
    }

    @Test("위에서 아래로 행 우선 — 맨 아래 행은 끝 10글자, 보이는 판 맨 위 행은 첫 10글자 · 버퍼 행은 안 싣는다")
    func orientationIsTopDownRowMajor() {
        var board = TetrisGame.emptyBoard()
        board[39][0] = .t                         // 맨 아래 왼쪽
        board[TetrisGame.firstVisibleRow][9] = .z  // 보이는 판 맨 위 오른쪽
        board[TetrisGame.firstVisibleRow - 1][4] = .i  // 버퍼(안 보인다)
        let text = Array(TetrisDuelBoard.encode(board: board, garbageMask: []))
        #expect(text[190] == "T")
        #expect(text[9] == "Z")
        #expect(text.filter { $0 != "." }.count == 2, "버퍼 행이 실렸다")
    }

    @Test("왕복 — 실제 판(조각 일곱 + 방해 줄)을 인코딩했다가 풀면 칸마다 같다")
    func roundTripPreservesEveryCell() throws {
        // 대결 판을 실제로 굴려 방해 줄과 여러 조각이 섞인 판을 만든다.
        var g = TetrisGame(seed: 31)
        g.action()
        var placed = 0
        while placed < 30, !g.isGameOver {
            guard case .running = g.phase else { g.step(dt: TetrisGame.maxStep); continue }
            if placed % 5 == 0 { g.receiveGarbage(lines: 1 + placed % 3) }
            for _ in 0..<(placed % 4) { g.setRightHeld(true); g.setRightHeld(false) }
            for _ in 0..<(placed % 3) { g.setLeftHeld(true); g.setLeftHeld(false) }
            g.action()
            placed += 1
        }
        let text = TetrisDuelBoard.encode(g)
        #expect(TetrisDuelBoard.isValid(text))
        #expect(text.contains("G"), "방해 줄이 한 칸도 없다 — 왕복이 G 를 안 잰다")
        #expect(Set(text).subtracting(["." as Character, "G"]).count >= 4, "조각 글자가 너무 적다")
        let grid = try #require(TetrisDuelBoard.decode(text))
        #expect(grid.count == 20 && grid.allSatisfy { $0.count == 10 })
        for r in 0..<20 {
            for c in 0..<10 {
                let row = TetrisGame.firstVisibleRow + r
                let expected: TetrisDuelCell
                if let p = g.board[row][c] {
                    expected = g.isGarbage(row: row, column: c) ? .garbage : .piece(p)
                } else {
                    expected = .empty
                }
                #expect(grid[r][c] == expected, "(\(r),\(c)) \(grid[r][c]) ≠ \(expected)")
            }
        }
        // 풀었다 다시 싸도 같은 글자판.
        let letters = grid.flatMap { $0 }.map { cell -> Character in
            switch cell {
            case .empty: return "."
            case .garbage: return "G"
            case .piece(let p): return TetrisDuelBoard.letter(for: p)
            }
        }
        #expect(String(letters) == text)
    }

    @Test("깨진 글자판은 거절 — 199·201글자 · 소문자 · 모르는 글자 · 비ASCII")
    func malformedTextIsRejected() {
        let ok = String(repeating: ".", count: 200)
        #expect(TetrisDuelBoard.decode(ok) != nil)
        for bad in [String(repeating: ".", count: 199), String(repeating: ".", count: 201),
                    "i" + String(repeating: ".", count: 199), "X" + String(repeating: ".", count: 199),
                    "가" + String(repeating: ".", count: 199), ""] {
            #expect(TetrisDuelBoard.decode(bad) == nil, "깨진 판을 받았다: \(bad.prefix(3))…(\(bad.count))")
            #expect(!TetrisDuelBoard.isValid(bad))
        }
        for letter in TetrisDuelBoard.alphabet {
            #expect(TetrisDuelBoard.isValid(String(repeating: letter, count: 200)), "\(letter) 를 거절했다")
        }
    }
}
