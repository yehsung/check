import Foundation

// 기기 안 체스 AI. 공개 입구는 `ChessAI.bestMove`(측정·보고용 `ChessAI.decide`) 하나다.
//
// ── 오목 AI 와 같은 모양으로 둔 까닭 ──
// 이 저장소는 이미 기기 안 AI 를 한 벌 돌린다(docs/plan/gomoku-ai.md §2 · GomokuAIEngine.swift). 쓰는 쪽(스토어·화면)이
// 둘을 같은 방식으로 다루게 **그 계약을 그대로** 따른다: 단일 난이도(항상 최선) · 시간 상한 1.5초 · 취소 문(클로저) ·
// 순수 동기 함수(부르는 쪽이 `Task.detached` 로 돌린다 — 엔진이 스레드를 만들지 않으므로 메인 스레드를 막는 자리가 없다) ·
// 점수가 **완전히 같은** 수끼리는 씨앗 무작위(앱은 매판 다른 기보, 테스트는 씨앗을 박아 결정적).
//
// ── 판 표현은 새로 만들지 않는다 ──
// 탐색은 `ChessEngine`(ChessRules.swift) 의 제자리 make/unmake·generate·isAttacked·pinnedMask 를 그대로 쓴다.
// 두 벌을 두면 규칙이 두 군데가 되고, 그 어긋남은 수 세기(perft)가 아니라 **대국 중 불법 수**로 드러난다 —
// 가장 늦게, 가장 나쁘게 드러나는 자리다. 그래서 AI 는 규칙을 한 줄도 다시 적지 않는다.
//
// ── 탐색 ──
// 반복 심화 네가맥스 알파베타(PVS) + 치환표(Zobrist) + 수 정렬(치환표 수 → 잡기 MVV-LVA → 킬러 → 이력) +
// 널 무브 + 늦은 수 줄이기(LMR) + **정지 탐색**. 정지 탐색이 없으면 잎에서 잡기 한가운데를 끊어 기물을 그냥 준다
// (잡는 수가 아직 안 끝난 국면을 '조용한 국면'으로 평가하는 자리다 — 과제의 합격선 ⑤ 가 바로 이것을 잰다).
//
// ── 메이트 점수 ──
// 메이트는 거리로 점수화한다: `mate - ply`. 그래서 같은 승리끼리는 **빠른 쪽**이 높고, 당하는 메이트는 늦은 쪽이 높다.
// 스테일메이트는 0(무승부)이다 — '수가 없다'를 이김으로 보면 자기 왕을 가두는 수를 승리로 고르는 사고가 난다.
//
// ── 시간 ──
// 마감은 예산보다 조금 앞에 둔다(틱 사이 간격 + 루트 마무리). 그렇게 하지 않으면 **측정한 벽시계가** 상한을 넘는다.
// 반복 심화는 예산의 절반을 넘겨 쓴 뒤에는 다음 깊이를 **시작하지 않는다**(시작한 깊이는 보통 앞 깊이의 몇 배다 —
// 끊긴 깊이의 결과는 버리므로 시작만 하고 버리는 건 순손실이다).
//
// 프라이버시·동시성: 이 엔진은 판 숫자만 본다. 한 번의 호출 안에서만 살고 스레드를 넘나들지 않는다.

/// 한 수를 고를 때의 한도. 오목(`GomokuAISearchLimits`)과 같은 모양이다.
package nonisolated struct ChessAISearchLimits: Sendable {
    /// 생각 시간 상한. 반복 심화가 이 시간에 끊긴다.
    package var timeBudget: Duration
    /// 탐색 깊이 상한. 앱은 넉넉히 두고 시간이 먼저 끊게 한다 — 테스트는 이 값으로 결정적으로 돌린다.
    package var maxDepth: Int
    /// 점수가 완전히 같은 최선의 수끼리 고를 때 쓰는 씨앗. nil 이면 시스템 무작위(앱), 테스트는 고정한다.
    package var tieBreakSeed: UInt64?

    package init(timeBudget: Duration = .milliseconds(1500), maxDepth: Int = 64, tieBreakSeed: UInt64? = nil) {
        self.timeBudget = timeBudget
        self.maxDepth = maxDepth
        self.tieBreakSeed = tieBreakSeed
    }
}

/// 한 번의 탐색 결과. 수만 쓰는 자리는 `bestMove` 를 부르고, **상한·깊이를 재는 자리**(테스트·보고)가 이것을 본다.
package nonisolated struct ChessAIDecision: Sendable {
    package let move: ChessMove
    /// 센티폰(폰 한 개 = 100). **두는 쪽 시점**이다.
    package let score: Int
    /// 끝까지 마친 가장 깊은 반복 심화 깊이. 끊긴 깊이는 결과를 버리므로 세지 않는다.
    package let depth: Int
    package let nodes: Int
    package let elapsed: Duration

    /// 메이트 점수면 **몇 반수 뒤** 메이트인가(+ = 내가 이긴다, − = 내가 당한다). 아니면 nil.
    /// 점수 자체로 판정하면 부르는 쪽마다 문턱을 다시 적게 된다 — 한 군데서만 적는다.
    package var mateInPlies: Int? {
        if score >= ChessAIScore.mateThreshold { return ChessAIScore.mate - score }
        if score <= -ChessAIScore.mateThreshold { return -(ChessAIScore.mate + score) }
        return nil
    }
}

package nonisolated enum ChessAI {
    /// `position` 에서 차례인 쪽이 둘 최선의 수. 합법 수가 없거나(메이트·스테일메이트) 체스판으로
    /// 성립하지 않는 국면이면 nil.
    ///
    /// `repetitionCounts` 는 `ChessRules.outcome` 에 넘기는 것과 같은 표(`repetitionKey` → 횟수)다.
    /// 넘기면 **세 번째 반복이 되는 수를 무승부(0)로** 셈한다 — 이기고 있는 판을 반복으로 흘려보내지 않고,
    /// 지고 있는 판에서는 그 수를 고른다. 안 넘기면 반복은 탐색 경로 안에서만 본다.
    ///
    /// `isCancelled` 가 true 가 되면 지금까지 찾은 최선(아직 없으면 첫 합법 수)을 곧바로 돌려준다.
    package static func bestMove(
        position: ChessPosition,
        repetitionCounts: [String: Int] = [:],
        limits: ChessAISearchLimits = .init(),
        isCancelled: @Sendable () -> Bool = { false }
    ) -> ChessMove? {
        decide(position: position, repetitionCounts: repetitionCounts, limits: limits, isCancelled: isCancelled)?.move
    }

    /// `bestMove` 와 같은 탐색이지만 점수·깊이·노드·걸린 시간까지 낸다.
    package static func decide(
        position: ChessPosition,
        repetitionCounts: [String: Int] = [:],
        limits: ChessAISearchLimits = .init(),
        isCancelled: @Sendable () -> Bool = { false }
    ) -> ChessAIDecision? {
        guard let engine = ChessEngine(position: position) else { return nil }
        // 엔진은 이 호출 안에서만 산다 — 취소 문을 들고 있어도 호출 밖으로 새지 않는다(블록 안에서 해제된다).
        return withoutActuallyEscaping(isCancelled) { cancelled in
            let search = ChessAISearch(engine: engine, budget: limits.timeBudget, isCancelled: cancelled)
            let depth = max(1, limits.maxDepth)
            if let seed = limits.tieBreakSeed {
                var rng = GomokuAISplitMix64(seed: seed)
                return search.decide(maxDepth: depth, repetitionCounts: repetitionCounts, rng: &rng)
            }
            var rng = SystemRandomNumberGenerator()
            return search.decide(maxDepth: depth, repetitionCounts: repetitionCounts, rng: &rng)
        }
    }
}

// MARK: - 점수 눈금

enum ChessAIScore {
    /// 0 반수 메이트(= 지금 메이트당한 국면)의 절댓값. `mate - ply` 로 거리를 담는다.
    static let mate = 32_000
    /// 이 값을 넘으면 메이트 점수다. 가장 깊은 탐색(maxPly)보다 큰 여유를 두고 가른다.
    static let mateThreshold = mate - 1_000
    static let infinity = 1 << 20
    /// 센티폰 기물 가치(ChessCode 순서: 빈칸 · 폰 · 나이트 · 비숍 · 룩 · 퀸 · 왕).
    /// 왕에 큰 값을 주지 않는 까닭: 왕은 잡히지 않는다(생성기가 왕 잡기를 내지 않는다). 정렬에서만 쓰이는 값이다.
    static let piece: [Int] = [0, 100, 320, 330, 500, 900, 20_000]
}

// MARK: - 표(칸 가치 · Zobrist)

/// 칸 가치표와 Zobrist 키. 표는 **보이는 대로**(8줄 = 8랭크, 위가 8랭크) 적고 한 번만 뒤집어 칸 번호(a1 = 0)로 옮긴다 —
/// 코드에 적힌 숫자와 판이 눈으로 맞아야 "폰이 왜 거기로 가지" 를 표에서 읽을 수 있다.
enum ChessAITables {
    /// 중반 표(폰·나이트·비숍·룩·퀸·왕). 색인은 `ChessCode` 의 말 종류 - 1.
    static let midgame: [[Int32]] = [
        flip([
              0,  0,  0,  0,  0,  0,  0,  0,
             50, 50, 50, 50, 50, 50, 50, 50,
             10, 10, 20, 30, 30, 20, 10, 10,
              5,  5, 10, 25, 25, 10,  5,  5,
              0,  0,  0, 20, 20,  0,  0,  0,
              5, -5,-10,  0,  0,-10, -5,  5,
              5, 10, 10,-20,-20, 10, 10,  5,
              0,  0,  0,  0,  0,  0,  0,  0
        ]),
        flip([
            -50,-40,-30,-30,-30,-30,-40,-50,
            -40,-20,  0,  0,  0,  0,-20,-40,
            -30,  0, 10, 15, 15, 10,  0,-30,
            -30,  5, 15, 20, 20, 15,  5,-30,
            -30,  0, 15, 20, 20, 15,  0,-30,
            -30,  5, 10, 15, 15, 10,  5,-30,
            -40,-20,  0,  5,  5,  0,-20,-40,
            -50,-40,-30,-30,-30,-30,-40,-50
        ]),
        flip([
            -20,-10,-10,-10,-10,-10,-10,-20,
            -10,  0,  0,  0,  0,  0,  0,-10,
            -10,  0,  5, 10, 10,  5,  0,-10,
            -10,  5,  5, 10, 10,  5,  5,-10,
            -10,  0, 10, 10, 10, 10,  0,-10,
            -10, 10, 10, 10, 10, 10, 10,-10,
            -10,  5,  0,  0,  0,  0,  5,-10,
            -20,-10,-10,-10,-10,-10,-10,-20
        ]),
        flip([
              0,  0,  0,  0,  0,  0,  0,  0,
              5, 10, 10, 10, 10, 10, 10,  5,
             -5,  0,  0,  0,  0,  0,  0, -5,
             -5,  0,  0,  0,  0,  0,  0, -5,
             -5,  0,  0,  0,  0,  0,  0, -5,
             -5,  0,  0,  0,  0,  0,  0, -5,
             -5,  0,  0,  0,  0,  0,  0, -5,
              0,  0,  5,  5,  5,  5,  0,  0
        ]),
        flip([
            -20,-10,-10, -5, -5,-10,-10,-20,
            -10,  0,  0,  0,  0,  0,  0,-10,
            -10,  0,  5,  5,  5,  5,  0,-10,
             -5,  0,  5,  5,  5,  5,  0, -5,
              0,  0,  5,  5,  5,  5,  0, -5,
            -10,  5,  5,  5,  5,  5,  0,-10,
            -10,  0,  5,  0,  0,  0,  0,-10,
            -20,-10,-10, -5, -5,-10,-10,-20
        ]),
        flip([
            -30,-40,-40,-50,-50,-40,-40,-30,
            -30,-40,-40,-50,-50,-40,-40,-30,
            -30,-40,-40,-50,-50,-40,-40,-30,
            -30,-40,-40,-50,-50,-40,-40,-30,
            -20,-30,-30,-40,-40,-30,-30,-20,
            -10,-20,-20,-20,-20,-20,-20,-10,
             20, 20,  0,  0,  0,  0, 20, 20,
             20, 30, 10,  0,  0, 10, 30, 20
        ])
    ]

    /// 끝내기 표. 폰과 왕만 중반과 다르다 — 폰은 **밀어야** 하고, 왕은 숨는 대신 **중앙으로 걸어 나와야** 한다
    /// (왕이 구석에 앉은 끝내기는 상대 왕을 몰 수 없어 50수로 흘러간다).
    static let endgame: [[Int32]] = [
        flip([
              0,  0,  0,  0,  0,  0,  0,  0,
             90, 90, 90, 90, 90, 90, 90, 90,
             55, 55, 55, 55, 55, 55, 55, 55,
             30, 30, 30, 30, 30, 30, 30, 30,
             15, 15, 15, 15, 15, 15, 15, 15,
              5,  5,  5,  5,  5,  5,  5,  5,
              0,  0,  0,  0,  0,  0,  0,  0,
              0,  0,  0,  0,  0,  0,  0,  0
        ]),
        midgame[1],
        midgame[2],
        midgame[3],
        midgame[4],
        flip([
            -50,-40,-30,-20,-20,-30,-40,-50,
            -30,-20,-10,  0,  0,-10,-20,-30,
            -30,-10, 20, 30, 30, 20,-10,-30,
            -30,-10, 30, 40, 40, 30,-10,-30,
            -30,-10, 30, 40, 40, 30,-10,-30,
            -30,-10, 20, 30, 30, 20,-10,-30,
            -30,-30,  0,  0,  0,  0,-30,-30,
            -50,-30,-30,-30,-30,-30,-30,-50
        ])
    ]

    /// 보이는 순서(8랭크 먼저)를 칸 번호(a1 = 0)로 옮긴다.
    private static func flip(_ visual: [Int32]) -> [Int32] {
        var table = [Int32](repeating: 0, count: 64)
        for square in 0..<64 {
            let file = square & 7
            let rank = square >> 3
            table[square] = visual[(7 - rank) * 8 + file]
        }
        return table
    }

    /// 말·칸 키 16×64(말 코드를 그대로 색인한다 — 빈 칸 자리는 쓰지 않는다) + 캐슬링 권리 16 + 앙파상 파일 8 + 차례 1.
    /// 씨앗을 박아 **둘 때마다 같은 표**가 나온다: 치환표 충돌이 판마다 달라지면 같은 국면에서 다른 수가 나오고,
    /// 그러면 테스트가 못 박을 것이 없다.
    static let zobrist: (pieces: [UInt64], castling: [UInt64], enPassant: [UInt64], side: UInt64) = {
        var rng = GomokuAISplitMix64(seed: 0x6368_6573_7341_4921)   // "chessAI!"
        var pieces = [UInt64](repeating: 0, count: 16 * 64)
        for index in pieces.indices { pieces[index] = rng.next() }
        var castling = [UInt64](repeating: 0, count: 16)
        for index in castling.indices { castling[index] = rng.next() }
        var enPassant = [UInt64](repeating: 0, count: 8)
        for index in enPassant.indices { enPassant[index] = rng.next() }
        return (pieces, castling, enPassant, rng.next())
    }()
}

// MARK: - 탐색

nonisolated final class ChessAISearch {
    static let maxPly = 96
    /// 한 노드가 낼 수 있는 유사 합법 수의 넉넉한 상한(실제 최대는 218 쯤이다).
    static let maxMoves = 256
    static let ttBits = 18

    private(set) var engine: ChessEngine

    // 시간·취소
    private let started: ContinuousClock.Instant
    private let deadline: ContinuousClock.Instant
    private let budget: Duration
    private let isCancelled: @Sendable () -> Bool
    private(set) var aborted = false
    private(set) var nodes = 0

    // 수 버퍼: ply 마다 창 하나(모양은 `ChessEngine.perft` 와 같다 — 노드마다 배열을 새로 만들지 않는다).
    private var moveStack: [ChessRawMove] = []
    private let scores: UnsafeMutablePointer<Int32>
    private let killers: UnsafeMutablePointer<ChessRawMove>
    private let history: UnsafeMutablePointer<Int32>
    private let tt: UnsafeMutablePointer<TTEntry>
    private let ttMask: Int
    /// 평가 전용 긁적임(색*8 + 파일 / 색*6 + 종류−1). **잎마다 배열을 새로 만들지 않으려고** 미리 잡아 둔다 —
    /// 작은 Swift 배열도 힙을 쓰므로 그 할당이 평가 자체보다 비싸다.
    private let pawnFiles: UnsafeMutablePointer<Int32>
    private let pieceCounts: UnsafeMutablePointer<Int32>
    /// 칸 가치표·기물 가치를 **평평한 한 벌로 복사해** 들고 있는다((종류−1)*64 + 칸).
    /// 중첩 배열(`[[Int32]]`)을 잎마다 두 번 색인하면 전역 접근자 + 안쪽 배열 유지/해제가 붙는다. 평가는
    /// 그래도 잎 비용의 절반이다 — 평가를 아예 끄고 재면 디버그 빌드에서 초당 노드가 38k → 85k 로 뛴다.
    private let midgameTable: UnsafeMutablePointer<Int32>
    private let endgameTable: UnsafeMutablePointer<Int32>
    private let pieceValue: UnsafeMutablePointer<Int32>

    /// 뿌리에서 지금까지 거쳐 온 국면 해시(경로 반복 판정). 두기 전에 쌓고 되돌릴 때 버린다.
    private var hashPath: [UInt64] = []
    private(set) var hash: UInt64 = 0

    struct TTEntry {
        var key: UInt64 = 0
        var score: Int32 = 0
        var depth: Int16 = -1
        /// 1 정확 · 2 아래 경계(베타 끊기) · 3 위 경계(알파에 못 미침).
        var flag: UInt8 = 0
        var from: Int8 = -1
        var to: Int8 = -1
        var promotion: UInt8 = 0
    }

    init(engine: ChessEngine, budget: Duration, isCancelled: @escaping @Sendable () -> Bool) {
        self.engine = engine
        self.budget = budget
        self.isCancelled = isCancelled
        scores = .allocate(capacity: Self.maxPly * Self.maxMoves)
        killers = .allocate(capacity: Self.maxPly * 2)
        history = .allocate(capacity: 16 * 64)
        tt = .allocate(capacity: 1 << Self.ttBits)
        ttMask = (1 << Self.ttBits) - 1
        pawnFiles = .allocate(capacity: 16)
        pieceCounts = .allocate(capacity: 12)
        midgameTable = .allocate(capacity: 6 * 64)
        endgameTable = .allocate(capacity: 6 * 64)
        pieceValue = .allocate(capacity: 7)
        scores.initialize(repeating: 0, count: Self.maxPly * Self.maxMoves)
        killers.initialize(repeating: ChessAISearch.noMove, count: Self.maxPly * 2)
        history.initialize(repeating: 0, count: 16 * 64)
        tt.initialize(repeating: TTEntry(), count: 1 << Self.ttBits)
        pawnFiles.initialize(repeating: 0, count: 16)
        pieceCounts.initialize(repeating: 0, count: 12)
        midgameTable.initialize(repeating: 0, count: 6 * 64)
        endgameTable.initialize(repeating: 0, count: 6 * 64)
        for kind in 0..<6 {
            for square in 0..<64 {
                midgameTable[kind * 64 + square] = ChessAITables.midgame[kind][square]
                endgameTable[kind * 64 + square] = ChessAITables.endgame[kind][square]
            }
        }
        pieceValue.initialize(repeating: 0, count: 7)
        for kind in 0..<7 { pieceValue[kind] = Int32(ChessAIScore.piece[kind]) }
        moveStack.reserveCapacity(Self.maxPly * 128)
        hashPath.reserveCapacity(Self.maxPly)
        started = ContinuousClock.now
        // 마감을 예산보다 조금 앞에 두는 까닭: 틱은 512 노드마다 보고(그 사이가 수십 μs), 루트는 돌아와서 할 일이 남아
        // 있다. 예산에 딱 맞추면 **재 보면 상한을 넘는다** — 상한은 "재서 지키는" 값이다.
        let margin = min(budget / 50, .milliseconds(20))
        deadline = started.advanced(by: budget - margin)
        hash = Self.fullHash(engine)
    }

    deinit {
        scores.deallocate()
        killers.deallocate()
        history.deallocate()
        tt.deallocate()
        pawnFiles.deallocate()
        pieceCounts.deallocate()
        midgameTable.deallocate()
        endgameTable.deallocate()
        pieceValue.deallocate()
    }

    static let noMove = ChessRawMove(from: 0, to: 0, promotion: 0, flags: 0)

    // MARK: 해시

    static func fullHash(_ engine: ChessEngine) -> UInt64 {
        var value: UInt64 = 0
        for square in 0..<64 {
            let cell = engine.cells[square]
            guard cell != ChessCode.empty else { continue }
            value ^= ChessAITables.zobrist.pieces[Int(cell) * 64 + square]
        }
        value ^= ChessAITables.zobrist.castling[Int(engine.castling) & 15]
        if engine.enPassant >= 0 { value ^= ChessAITables.zobrist.enPassant[engine.enPassant & 7] }
        if engine.side == 1 { value ^= ChessAITables.zobrist.side }
        return value
    }

    /// 두고 나서 해시를 증분 갱신한다. `piece` 는 **두기 전**의 말 코드, `undo` 는 `make` 가 낸 것이다.
    ///
    /// 앙파상 칸을 '잡을 수 있을 때만' 넣지 않고 늘 넣는 까닭: 치환표는 과하게 갈라도 손해가 적고(적중이 조금 줄 뿐),
    /// 덜 갈라지면 **다른 국면을 같다고** 본다. 경로 반복 판정도 이 쪽으로 틀리면 안 나온 무승부를 만든다.
    @inline(__always)
    private func updateHash(piece: UInt8, undo: ChessUndo) {
        let move = undo.move
        let keys = ChessAITables.zobrist
        hash ^= keys.pieces[Int(piece) * 64 + move.from]
        let placed = move.promotion == 0 ? piece : (move.promotion | (piece & ChessCode.blackBit))
        hash ^= keys.pieces[Int(placed) * 64 + move.to]
        if undo.captured != ChessCode.empty {
            hash ^= keys.pieces[Int(undo.captured) * 64 + undo.capturedSquare]
        }
        if undo.rookFrom >= 0 {
            let rook = engine.cells[undo.rookTo]
            hash ^= keys.pieces[Int(rook) * 64 + undo.rookFrom]
            hash ^= keys.pieces[Int(rook) * 64 + undo.rookTo]
        }
        hash ^= keys.castling[Int(undo.castling) & 15]
        hash ^= keys.castling[Int(engine.castling) & 15]
        if undo.enPassant >= 0 { hash ^= keys.enPassant[undo.enPassant & 7] }
        if engine.enPassant >= 0 { hash ^= keys.enPassant[engine.enPassant & 7] }
        hash ^= keys.side
    }

    /// 두고 해시·경로를 함께 민다. 되돌리기는 `undoMove`.
    /// private 이 아닌 까닭: 증분 해시가 맞는지는 **전체 재계산과 나란히 재야** 알 수 있고(틀리면 치환표가
    /// 다른 국면을 같다고 보는데, 그건 수가 조금 나빠지는 모습으로만 드러난다), 그 대조를 테스트가 여기서 한다.
    @inline(__always)
    func makeMove(_ move: ChessRawMove) -> (undo: ChessUndo, hash: UInt64) {
        let piece = engine.cells[move.from]
        let before = hash
        hashPath.append(before)
        let undo = engine.make(move)
        updateHash(piece: piece, undo: undo)
        return (undo, before)
    }

    @inline(__always)
    func undoMove(_ state: (undo: ChessUndo, hash: UInt64)) {
        engine.unmake(state.undo)
        hashPath.removeLast()
        hash = state.hash
    }

    // MARK: 시간

    @inline(__always)
    private func tick() {
        nodes += 1
        if nodes & 511 == 0, !aborted {
            if ContinuousClock.now >= deadline || isCancelled() { aborted = true }
        }
    }

    private func checkAbortNow() -> Bool {
        if !aborted, ContinuousClock.now >= deadline || isCancelled() { aborted = true }
        return aborted
    }

    private var elapsed: Duration { ContinuousClock.now - started }

    private var elapsedFraction: Double {
        let total = Self.seconds(budget)
        return total > 0 ? Self.seconds(elapsed) / total : 1
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    // MARK: 평가

    /// 두는 쪽 시점의 센티폰 점수.
    ///
    /// 항: 기물 가치 + 칸 가치표(중반↔끝내기 사이 선형 보간) + 폰 구조(이중·고립) + 왕 안전(폰 방패, 중반만) +
    /// 비숍 한 쌍. 끝내기 왕 중앙화는 **따로 더하지 않는다** — 끝내기 왕 표가 그 일을 한다(항이 둘이면 서로 싸운다).
    func evaluate() -> Int {
        var midgame = 0
        var endgame = 0
        var phase = 0
        for index in 0..<16 { pawnFiles[index] = 0 }
        for index in 0..<12 { pieceCounts[index] = 0 }

        engine.cells.withUnsafeBufferPointer { cells in
            for square in 0..<64 {
                let cell = cells[square]
                guard cell != ChessCode.empty else { continue }
                let kind = Int(cell & ChessCode.kindMask)
                let isBlack = (cell & ChessCode.blackBit) != 0
                let colorIndex = isBlack ? 1 : 0
                pieceCounts[colorIndex * 6 + kind - 1] += 1
                // 흑은 같은 표를 위아래로 뒤집어 읽는다(칸 번호 ^ 56 = 랭크 반사).
                let view = isBlack ? square ^ 56 : square
                let material = Int(pieceValue[kind])
                let mid = material + Int(midgameTable[(kind - 1) * 64 + view])
                let end = material + Int(endgameTable[(kind - 1) * 64 + view])
                if isBlack {
                    midgame -= mid
                    endgame -= end
                } else {
                    midgame += mid
                    endgame += end
                }
                if kind == Int(ChessCode.pawn) { pawnFiles[colorIndex * 8 + (square & 7)] += 1 }
                switch UInt8(kind) {
                case ChessCode.knight, ChessCode.bishop: phase += 1
                case ChessCode.rook: phase += 2
                case ChessCode.queen: phase += 4
                default: break
                }
            }
        }

        // 사국 중에서도 가장 흔한 둘(맨 왕 · 작은 말 하나)은 탐색 안에서 바로 0 으로 접는다. 전체 규칙은
        // `ChessRules.hasInsufficientMaterial` 이 쥐고 있고, 그걸 잎마다 부르면 국면을 복사해야 한다.
        let pawns = pieceCounts[0] + pieceCounts[6]
        let heavy = pieceCounts[3] + pieceCounts[4] + pieceCounts[9] + pieceCounts[10]
        let minors = pieceCounts[1] + pieceCounts[2] + pieceCounts[7] + pieceCounts[8]
        if pawns == 0, heavy == 0, minors <= 1 { return 0 }

        for colorIndex in 0..<2 {
            var structure = 0
            for file in 0..<8 {
                let count = Int(pawnFiles[colorIndex * 8 + file])
                guard count > 0 else { continue }
                // 이중 폰: 같은 파일의 둘째부터 벌점. 앞뒤로 서로를 막아 한 개 몫을 못 한다.
                if count > 1 { structure -= (count - 1) * 18 }
                let left = file > 0 ? pawnFiles[colorIndex * 8 + file - 1] : 0
                let right = file < 7 ? pawnFiles[colorIndex * 8 + file + 1] : 0
                // 고립 폰: 옆 파일에 같은 색 폰이 없으면 폰으로는 영원히 지킬 수 없다.
                if left == 0, right == 0 { structure -= 14 * count }
            }
            if pieceCounts[colorIndex * 6 + Int(ChessCode.bishop) - 1] >= 2 { structure += 30 }
            if colorIndex == 0 {
                midgame += structure
                endgame += structure
            } else {
                midgame -= structure
                endgame -= structure
            }
        }

        // 왕 안전(중반만): 왕 앞 세 파일에 폰 방패가 있는가. 끝내기에서는 왕이 걸어 나가야 하므로 세지 않는다.
        for colorIndex in 0..<2 {
            let shield = pawnShield(colorIndex: colorIndex)
            midgame += colorIndex == 0 ? shield : -shield
        }

        // 몰기: 한쪽이 **왕만** 남았으면 상대 왕을 변·구석으로 밀고 내 왕을 붙인다.
        // 이 항이 없으면 퀸이 남아도 50수 무승부로 흘러간다 — 기물 가치와 칸 가치표만으로는 왕을 모는 수와
        // 가만히 있는 수가 동점이고, 동점이면 무작위로 고르기 때문이다(무작위 상대 20전에서 실제로 새던 자리다).
        let whiteForce = pieceCounts[0] + pieceCounts[1] + pieceCounts[2] + pieceCounts[3] + pieceCounts[4]
        let blackForce = pieceCounts[6] + pieceCounts[7] + pieceCounts[8] + pieceCounts[9] + pieceCounts[10]
        if whiteForce > 0, blackForce == 0 {
            let mop = mopUp(strong: 0, weak: 1)
            midgame += mop
            endgame += mop
        } else if blackForce > 0, whiteForce == 0 {
            let mop = mopUp(strong: 1, weak: 0)
            midgame -= mop
            endgame -= mop
        }

        let clamped = min(phase, 24)
        var score = (midgame * clamped + endgame * (24 - clamped)) / 24
        if engine.side == 1 { score = -score }
        return score
    }

    /// 몰기 점수(이긴 쪽 시점, 늘 0 이상). 변까지의 거리 + 두 왕 사이 거리 — 둘 다 **줄이는** 쪽이 높다.
    private func mopUp(strong: Int, weak: Int) -> Int {
        let weakSquare = engine.kings[weak]
        let strongSquare = engine.kings[strong]
        let weakFile = weakSquare & 7
        let weakRank = weakSquare >> 3
        // 0(중앙) … 6(구석). 변으로 밀면 커진다.
        let edge = (3 - min(weakFile, 7 - weakFile)) + (3 - min(weakRank, 7 - weakRank))
        let distance = abs(weakFile - (strongSquare & 7)) + abs(weakRank - (strongSquare >> 3))
        return 12 * edge + 6 * (14 - distance)
    }

    private func pawnShield(colorIndex: Int) -> Int {
        let kingSquare = engine.kings[colorIndex]
        let kingFile = kingSquare & 7
        let kingRank = kingSquare >> 3
        let wanted = ChessCode.pawn | (colorIndex == 1 ? ChessCode.blackBit : 0)
        var shield = 0
        for file in max(0, kingFile - 1)...min(7, kingFile + 1) {
            var found = false
            for step in 1...2 {
                let rank = colorIndex == 0 ? kingRank + step : kingRank - step
                guard rank >= 0, rank < 8 else { break }
                if engine.cells[rank * 8 + file] == wanted {
                    shield += step == 1 ? 10 : 5
                    found = true
                    break
                }
            }
            // 폰이 하나도 없는 파일은 상대 룩·퀸이 바로 들어오는 길이다.
            if !found { shield -= 12 }
        }
        return shield
    }

    // MARK: 수 생성 · 정렬

    /// 이 ply 의 합법 수를 버퍼 창에 담는다. 반환은 (시작 색인, 개수, 체크인가).
    /// `capturesOnly` 면 잡기·퀸 승격만 담는다(정지 탐색). **체크일 때는 부르는 쪽이 false 로 부른다** —
    /// 체크를 잡기로만 벗어난다고 보면 피하는 수를 못 보고 거짓 메이트를 만든다.
    private func generateLegal(ply: Int, capturesOnly: Bool) -> (start: Int, count: Int, inCheck: Bool) {
        let start = moveStack.count
        engine.generate(into: &moveStack)
        let end = moveStack.count
        let moverIndex = Int(engine.side)
        let kingSquare = engine.kings[moverIndex]
        let byBlack = moverIndex == 0
        let inCheck = engine.isAttacked(kingSquare, byBlack: byBlack)
        let pins = engine.pinnedMask(kingSquare: kingSquare, moverIsBlack: moverIndex == 1)
        var write = start
        var index = start
        while index < end {
            let move = moveStack[index]
            index += 1
            if capturesOnly {
                let isCapture = engine.cells[move.to] != ChessCode.empty
                    || move.flags & ChessRawMove.enPassant != 0
                guard isCapture || move.promotion == ChessCode.queen else { continue }
            }
            if engine.needsKingSafetyCheck(move, kingSquare: kingSquare, pins: pins, inCheck: inCheck) {
                let undo = engine.make(move)
                let safe = !engine.isAttacked(engine.kings[moverIndex], byBlack: byBlack)
                engine.unmake(undo)
                guard safe else { continue }
            }
            moveStack[write] = move
            write += 1
        }
        moveStack.removeLast(end - write)
        return (start, write - start, inCheck)
    }

    /// 창에 담긴 수에 정렬 점수를 매긴다.
    ///
    /// 순서: 치환표 수 → 잡기·승격(MVV-LVA: 비싼 것을 싼 말로) → 킬러 두 개 → 이력. 정렬이 탐색의 세기다 —
    /// 좋은 수를 먼저 보면 알파베타가 같은 시간에 두 배 넘게 깊이 들어간다.
    private func scoreMoves(start: Int, count: Int, ply: Int, ttMove: ChessRawMove) {
        let base = ply * Self.maxMoves
        for offset in 0..<count {
            let move = moveStack[start + offset]
            var score: Int32
            if move.from == ttMove.from, move.to == ttMove.to, move.promotion == ttMove.promotion {
                score = 1 << 30
            } else {
                let victim = engine.cells[move.to]
                let isEnPassant = move.flags & ChessRawMove.enPassant != 0
                if victim != ChessCode.empty || isEnPassant || move.promotion != 0 {
                    let victimKind = isEnPassant ? Int(ChessCode.pawn) : Int(victim & ChessCode.kindMask)
                    let attackerKind = Int(engine.cells[move.from] & ChessCode.kindMask)
                    let promotionBonus = move.promotion == 0 ? 0 : Int(pieceValue[Int(move.promotion)]) - 100
                    score = Int32(1_000_000 + 100 * Int(pieceValue[victimKind])
                                  - Int(pieceValue[attackerKind]) + promotionBonus)
                } else if move == killers[ply * 2] {
                    score = 900_000
                } else if move == killers[ply * 2 + 1] {
                    score = 890_000
                } else {
                    let piece = Int(engine.cells[move.from])
                    score = min(history[piece * 64 + move.to], 880_000)
                }
            }
            scores[base + offset] = score
        }
    }

    /// 남은 수 중 점수가 가장 큰 것을 `index` 자리로 끌어온다(선택 정렬 한 걸음).
    /// 통째로 정렬하지 않는 까닭: 베타 끊기는 보통 첫 몇 수에서 난다 — 나머지를 정렬한 비용은 그대로 버려진다.
    @inline(__always)
    private func pickBest(start: Int, count: Int, index: Int, ply: Int) {
        let base = ply * Self.maxMoves
        var bestOffset = index
        var bestScore = scores[base + index]
        var offset = index + 1
        while offset < count {
            if scores[base + offset] > bestScore {
                bestScore = scores[base + offset]
                bestOffset = offset
            }
            offset += 1
        }
        guard bestOffset != index else { return }
        moveStack.swapAt(start + index, start + bestOffset)
        scores[base + bestOffset] = scores[base + index]
        scores[base + index] = bestScore
    }

    // MARK: 무승부 규칙

    /// 지금 국면이 규칙으로 무승부인가(탐색 안쪽 전용 — 뿌리에서는 부르지 않는다).
    /// 경로 반복은 **한 번만 되돌아와도** 무승부로 본다: 되풀이할 수 있는 길을 승리로 세면 반복으로 흘러가는 수를 고른다.
    private func isDrawByRule() -> Bool {
        if engine.halfmove >= 100 { return true }
        guard engine.halfmove >= 4, hashPath.count >= 2 else { return false }
        // 되돌릴 수 없는 수(폰 이동·잡기) 이전은 볼 필요가 없다 — 그 앞 국면은 다시 나올 수 없다.
        let limit = min(engine.halfmove, hashPath.count)
        var index = hashPath.count - 2
        var steps = 2
        while index >= 0, steps <= limit {
            if hashPath[index] == hash { return true }
            index -= 2
            steps += 2
        }
        return false
    }

    /// 두는 쪽에 폰·왕 말고 다른 말이 있는가(널 무브를 걸러내는 조건 — 쩐의 위기(zugzwang)는 말이 폰뿐일 때 난다).
    private func hasNonPawnMaterial() -> Bool {
        let me: UInt8 = engine.side == 0 ? 0 : ChessCode.blackBit
        for square in 0..<64 {
            let cell = engine.cells[square]
            guard cell != ChessCode.empty, (cell & ChessCode.blackBit) == me else { continue }
            let kind = cell & ChessCode.kindMask
            if kind != ChessCode.pawn, kind != ChessCode.king { return true }
        }
        return false
    }

    // MARK: 정지 탐색

    /// 잡기(와 퀸 승격)가 끝날 때까지만 더 보는 탐색. 체크면 그 자리에서 벗어나는 수를 전부 본다(깊이 한도 안에서).
    ///
    /// 이게 없으면 잎에서 "내가 상대 퀸을 잡았다"만 세고 그 다음 수의 되잡기를 못 본다 — 기물을 그냥 주는 수가
    /// 가장 좋은 수로 올라온다. 과제의 합격선 ⑤(자기 퀸을 공짜로 주지 않는다)는 정확히 이 함수가 지킨다.
    private func quiesce(_ alphaIn: Int, _ betaIn: Int, ply: Int, checkDepth: Int) -> Int {
        tick()
        if aborted { return 0 }
        if ply >= Self.maxPly - 2 { return evaluate() }

        let moverIndex = Int(engine.side)
        let inCheck = engine.isAttacked(engine.kings[moverIndex], byBlack: moverIndex == 0)
        // 체크를 '잡기만'으로 보는 깊이에 들어가면 수가 없어도 메이트라고 말할 수 없다 — 전부 본 때만 메이트다.
        let full = inCheck && checkDepth > 0
        var alpha = alphaIn
        var best = -ChessAIScore.infinity
        var standPat = 0
        if !full {
            standPat = evaluate()
            best = standPat
            if best >= betaIn { return best }
            if best > alpha { alpha = best }
        }

        let generated = generateLegal(ply: ply, capturesOnly: !full)
        defer { moveStack.removeLast(generated.count) }
        if generated.count == 0 {
            // 전부 보고도 수가 없으면 판정이다: 체크면 메이트, 아니면 스테일메이트(무승부).
            if full { return -(ChessAIScore.mate - ply) }
            return best
        }
        scoreMoves(start: generated.start, count: generated.count, ply: ply, ttMove: Self.noMove)

        for index in 0..<generated.count {
            pickBest(start: generated.start, count: generated.count, index: index, ply: ply)
            let move = moveStack[generated.start + index]
            if !full {
                // 델타 가지치기: 잡아 봐야 알파에 한참 못 미치는 잡기는 보지 않는다.
                let victim = move.flags & ChessRawMove.enPassant != 0
                    ? Int(ChessCode.pawn)
                    : Int(engine.cells[move.to] & ChessCode.kindMask)
                let gain = Int(pieceValue[victim]) + (move.promotion == 0 ? 0 : 800)
                if standPat + gain + 200 < alpha { continue }
            }
            let state = makeMove(move)
            let score = -quiesce(-betaIn, -alpha, ply: ply + 1, checkDepth: full ? checkDepth - 1 : checkDepth)
            undoMove(state)
            if aborted { return 0 }
            if score > best {
                best = score
                if score > alpha {
                    alpha = score
                    if alpha >= betaIn { break }
                }
            }
        }
        return best
    }

    // MARK: 알파베타

    func search(depth depthIn: Int, alpha alphaIn: Int, beta betaIn: Int, ply: Int, allowNull: Bool) -> Int {
        tick()
        if aborted { return 0 }
        if ply > 0, isDrawByRule() { return 0 }
        if ply >= Self.maxPly - 2 { return evaluate() }

        let moverIndex = Int(engine.side)
        let inCheck = engine.isAttacked(engine.kings[moverIndex], byBlack: moverIndex == 0)
        var depth = depthIn
        // 체크 중이면 한 수 더 본다: 체크를 피하는 수는 선택지가 아니라 강제다(깊이를 소모할 이유가 없다).
        if inCheck, ply < 48 { depth += 1 }
        if depth <= 0 { return quiesce(alphaIn, betaIn, ply: ply, checkDepth: 4) }

        var alpha = alphaIn
        var beta = betaIn
        let slot = Int(truncatingIfNeeded: hash) & ttMask
        var ttMove = Self.noMove
        if tt[slot].key == hash {
            ttMove = ChessRawMove(from: Int(tt[slot].from), to: Int(tt[slot].to),
                                  promotion: tt[slot].promotion, flags: 0)
            if Int(tt[slot].depth) >= depth, ply > 0 {
                let score = fromTT(Int(tt[slot].score), ply)
                switch tt[slot].flag {
                case 1: return score
                case 2: alpha = max(alpha, score)
                case 3: beta = min(beta, score)
                default: break
                }
                if alpha >= beta { return score }
            }
        }

        // 널 무브: 한 수를 **거르고도** 베타를 넘으면 이 가지는 볼 필요가 없다. 체크·끝내기(폰만 남은 판)에서는
        // 거르는 쪽이 이득인 자리가 있어(쩐의 위기) 쓰지 않는다.
        if allowNull, !inCheck, ply > 0, depth >= 3, beta < ChessAIScore.mateThreshold, hasNonPawnMaterial() {
            // 50수 카운터는 **건드리지 않는다**: 널 무브는 실제로 둔 수가 아니다. 더하면 카운터 99 의 이긴 판이
            // 널 무브 한 번으로 100(무승부)이 되어 이기는 수가 0 점으로 접힌다.
            let savedEnPassant = engine.enPassant
            let savedHash = hash
            hashPath.append(hash)
            engine.side ^= 1
            engine.enPassant = -1
            hash ^= ChessAITables.zobrist.side
            if savedEnPassant >= 0 { hash ^= ChessAITables.zobrist.enPassant[savedEnPassant & 7] }
            let reduction = 2 + depth / 6
            let score = -search(depth: depth - 1 - reduction, alpha: -beta, beta: -beta + 1,
                                ply: ply + 1, allowNull: false)
            engine.side ^= 1
            engine.enPassant = savedEnPassant
            hash = savedHash
            hashPath.removeLast()
            if aborted { return 0 }
            if score >= beta { return beta }
        }

        let generated = generateLegal(ply: ply, capturesOnly: false)
        defer { moveStack.removeLast(generated.count) }
        if generated.count == 0 {
            // 수가 없다 → 체크면 메이트(거리로 점수화), 아니면 스테일메이트는 **무승부**다.
            return inCheck ? -(ChessAIScore.mate - ply) : 0
        }
        scoreMoves(start: generated.start, count: generated.count, ply: ply, ttMove: ttMove)

        var best = -ChessAIScore.infinity
        var bestMove = Self.noMove
        for index in 0..<generated.count {
            pickBest(start: generated.start, count: generated.count, index: index, ply: ply)
            let move = moveStack[generated.start + index]
            let isCapture = engine.cells[move.to] != ChessCode.empty
                || move.flags & ChessRawMove.enPassant != 0
            let state = makeMove(move)
            var score: Int
            if index == 0 {
                score = -search(depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1, allowNull: true)
            } else {
                // 늦은 수 줄이기: 정렬이 뒤로 보낸 조용한 수는 한 칸 얕게 본다. 알파를 넘으면 제 깊이로 다시 본다
                // (줄인 깊이에서 나온 '좋다'를 그대로 믿으면 정렬 실수가 그대로 수가 된다).
                var reduction = 0
                if depth >= 3, index >= 3, !isCapture, !inCheck, move.promotion == 0 {
                    // 체크를 거는 수는 줄이지 않는다(강제수다). 이 판정을 **줄일 후보에만** 하는 까닭: 수마다
                    // 부르면 노드마다 `isAttacked` 가 수 개수만큼(중반이면 35번) 붙는다 — 쓰는 데는 여기뿐이다.
                    let opponentIndex = Int(engine.side)
                    if !engine.isAttacked(engine.kings[opponentIndex], byBlack: opponentIndex == 0) {
                        reduction = index >= 6 ? 2 : 1
                    }
                }
                score = -search(depth: depth - 1 - reduction, alpha: -(alpha + 1), beta: -alpha,
                                ply: ply + 1, allowNull: true)
                if !aborted, score > alpha, reduction > 0 {
                    score = -search(depth: depth - 1, alpha: -(alpha + 1), beta: -alpha,
                                    ply: ply + 1, allowNull: true)
                }
                if !aborted, score > alpha, score < beta {
                    score = -search(depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1, allowNull: true)
                }
            }
            undoMove(state)
            if aborted { return 0 }
            if score > best {
                best = score
                bestMove = move
                if score > alpha {
                    alpha = score
                    if alpha >= beta {
                        if !isCapture {
                            // 킬러·이력: 같은 깊이의 **다른 가지**에서도 같은 수가 끊는 일이 잦다.
                            if killers[ply * 2] != move {
                                killers[ply * 2 + 1] = killers[ply * 2]
                                killers[ply * 2] = move
                            }
                            let piece = Int(engine.cells[move.from])
                            let bonus = Int32(depth * depth)
                            let slotIndex = piece * 64 + move.to
                            history[slotIndex] = min(history[slotIndex] + bonus, 800_000)
                        }
                        break
                    }
                }
            }
        }

        let flag: UInt8 = best >= betaIn ? 2 : (best <= alphaIn ? 3 : 1)
        if tt[slot].key != hash || Int(tt[slot].depth) <= depth {
            tt[slot] = TTEntry(key: hash, score: Int32(toTT(best, ply)), depth: Int16(depth), flag: flag,
                               from: Int8(bestMove.from), to: Int8(bestMove.to), promotion: bestMove.promotion)
        }
        return best
    }

    /// 메이트 점수는 치환표에 **그 국면에서의 거리**로 넣는다. ply 를 함께 넣지 않으면 깊이가 다른 자리에서
    /// 꺼낸 메이트 거리가 몇 수씩 어긋나 "두 수 뒤 메이트"를 영원히 미루는 수가 나온다.
    @inline(__always) private func toTT(_ score: Int, _ ply: Int) -> Int {
        if score >= ChessAIScore.mateThreshold { return score + ply }
        if score <= -ChessAIScore.mateThreshold { return score - ply }
        return score
    }

    @inline(__always) private func fromTT(_ score: Int, _ ply: Int) -> Int {
        if score >= ChessAIScore.mateThreshold { return score - ply }
        if score <= -ChessAIScore.mateThreshold { return score + ply }
        return score
    }

    // MARK: 뿌리

    func decide(maxDepth: Int, repetitionCounts: [String: Int],
                rng: inout some RandomNumberGenerator) -> ChessAIDecision? {
        let rootStart = moveStack.count
        let generated = generateLegal(ply: 0, capturesOnly: false)
        defer { moveStack.removeLast(moveStack.count - rootStart) }
        guard generated.count > 0 else { return nil }

        var rootMoves = (0..<generated.count).map { moveStack[generated.start + $0] }
        // 둘 수 있는 수가 하나면 탐색할 것이 없다(고를 여지가 없는 자리라 점수·깊이는 0 으로 둔다).
        if rootMoves.count == 1 {
            return ChessAIDecision(move: rootMoves[0].move, score: 0, depth: 0, nodes: nodes, elapsed: elapsed)
        }

        // 세 번째 반복이 되는 수는 **무승부**다. 탐색에 맡기면 뿌리 앞의 이력을 모르니 이기는 수로 센다.
        var forcedDraw = Set<ChessRawMove>()
        if !repetitionCounts.isEmpty {
            for move in rootMoves {
                let state = makeMove(move)
                let key = engine.position.repetitionKey
                undoMove(state)
                if (repetitionCounts[key] ?? 0) + 1 >= 3 { forcedDraw.insert(move) }
            }
        }

        var bestMoves = [rootMoves[0]]
        var bestScore = 0
        var completedDepth = 0
        var previous = [Int](repeating: 0, count: rootMoves.count)
        var depth = 1
        while depth <= maxDepth {
            var iterationBest = -ChessAIScore.infinity
            var iterationMoves: [ChessRawMove] = []
            var iterationScores = [Int](repeating: -ChessAIScore.infinity, count: rootMoves.count)
            for (index, move) in rootMoves.enumerated() {
                if forcedDraw.contains(move) {
                    // 무승부는 탐색하지 않는다 — 값이 0 으로 정해져 있다.
                    iterationScores[index] = 0
                    if 0 > iterationBest {
                        iterationBest = 0
                        iterationMoves = [move]
                    } else if iterationBest == 0 {
                        iterationMoves.append(move)
                    }
                    continue
                }
                let state = makeMove(move)
                var score: Int
                var exact = true
                if iterationMoves.isEmpty {
                    score = -search(depth: depth - 1, alpha: -ChessAIScore.infinity, beta: ChessAIScore.infinity,
                                    ply: 1, allowNull: true)
                } else {
                    score = -search(depth: depth - 1, alpha: -(iterationBest + 1), beta: -iterationBest,
                                    ply: 1, allowNull: true)
                    if !aborted, score > iterationBest {
                        // 좁은 창으로 "더 좋다"가 나오면 **전 창으로 다시** 본다. 좁은 창의 값은 경계일 뿐이라
                        // 그대로 동점 판정에 쓰면 더 나쁜 수가 최선과 동점으로 올라온다.
                        score = -search(depth: depth - 1, alpha: -ChessAIScore.infinity,
                                        beta: ChessAIScore.infinity, ply: 1, allowNull: true)
                    } else {
                        exact = false
                    }
                }
                undoMove(state)
                if aborted { break }
                iterationScores[index] = score
                if exact, score > iterationBest {
                    iterationBest = score
                    iterationMoves = [move]
                } else if exact, score == iterationBest {
                    iterationMoves.append(move)
                }
            }
            if aborted || iterationMoves.isEmpty { break }
            completedDepth = depth
            bestScore = iterationBest
            bestMoves = iterationMoves
            previous = iterationScores
            // 다음 깊이는 좋은 수부터(정렬이 탐색의 세기다).
            let order = rootMoves.indices.sorted { previous[$0] > previous[$1] }
            rootMoves = order.map { rootMoves[$0] }
            previous = order.map { previous[$0] }
            // 메이트가 확정되면 더 깊이 볼 것이 없다.
            if abs(bestScore) >= ChessAIScore.mateThreshold { break }
            if checkAbortNow() { break }
            if elapsedFraction > 0.5 { break }
            depth += 1
        }

        let chosen = bestMoves.randomElement(using: &rng) ?? rootMoves[0]
        return ChessAIDecision(move: chosen.move, score: bestScore, depth: completedDepth,
                               nodes: nodes, elapsed: elapsed)
    }
}
