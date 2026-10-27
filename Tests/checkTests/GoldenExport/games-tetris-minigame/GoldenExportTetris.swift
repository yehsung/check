// 원본: 없음 — W1-a 테트리스 골든 생성 시험(C§5.1 E2·E3 · C§5.2 G1~G3). 원본 엔진은 Sources/CheckCore/TetrisGame.swift ·
// TetrisDuelSession.swift · TetrisDuelBoard.swift @ 1b8260d. Kotlin 대조: multiplatform/core/rules/src/commonTest/…/tetris/.
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

@Suite("GoldenExport games-tetris-minigame — 테트리스(규칙표 · 7-bag · 방해 줄 구멍 · 대본 A~G · 대결 세션)")
struct GoldenExportTetris {
    static let engine = "Sources/CheckCore/TetrisGame.swift"
    static let rngSource = "Sources/CheckCore/MiniGameEngine.swift"
    static let session = "Sources/CheckCore/TetrisDuelSession.swift"
    static let duelBoard = "Sources/CheckCore/TetrisDuelBoard.swift"

    // MARK: - tetris/rules (G1)

    @Test("tetris/rules — 레벨 · 중력 비트 · 락딜레이 · 리셋 한도 · 점수표 · 모양 · 킥표 · 상수")
    func rules() {
        let levels = Array(-2...40)
        let spins: [(String, TetrisGame.Spin)] = [("none", .none), ("mini", .mini), ("full", .full)]
        var cases: [GoldenJSON] = []
        cases.append(["id": "level", "from": -5, "values": GoldenCompact.ints((-5...2000).map { TetrisGame.level(forAdvance: $0) })])
        cases.append(["id": "scoreLevel", "from": -2, "values": GoldenCompact.ints(levels.map { TetrisGame.scoreLevel(forLevel: $0) })])
        cases.append(["id": "gravityStage", "from": -2, "values": GoldenCompact.ints(levels.map { TetrisGame.gravityStage(forLevel: $0) })])
        cases.append(["id": "gravitySecondsForStage", "from": -3,
                      "valuesBits": GoldenCompact.bits((-3...25).map { TetrisGame.gravitySeconds(forStage: $0) })])
        cases.append(["id": "gravitySecondsForLevel", "from": -2,
                      "valuesBits": GoldenCompact.bits(levels.map { TetrisGame.gravitySeconds(forLevel: $0) })])
        cases.append(["id": "softDropSeconds", "from": -2,
                      "valuesBits": GoldenCompact.bits(levels.map { TetrisGame.softDropSeconds(forLevel: $0) })])
        cases.append(["id": "lockDelaySeconds", "from": -2,
                      "valuesBits": GoldenCompact.bits(levels.map { TetrisGame.lockDelaySeconds(forLevel: $0) })])
        cases.append(["id": "lockResetLimit", "from": -2, "values": GoldenCompact.ints(levels.map { TetrisGame.lockResetLimit(forLevel: $0) })])
        cases.append(["id": "lockResetRefreshes", "from": -2, "values": GoldenCompact.bools(levels.map { TetrisGame.lockResetRefreshes(forLevel: $0) })])
        cases.append(["id": "attackLines", "from": -1, "values": GoldenCompact.ints((-1...6).map { TetrisGame.attackLines(lines: $0) })])
        for (name, spin) in spins {
            cases.append(["id": "actionPoints-\(name)", "from": -1,
                          "values": GoldenCompact.ints((-1...5).map { TetrisGame.actionPoints(lines: $0, spin: spin) })])
            cases.append(["id": "isDifficult-\(name)", "from": -1,
                          "values": GoldenCompact.bools((-1...5).map { TetrisGame.isDifficult(lines: $0, spin: spin) })])
        }
        cases.append(["id": "perfectClearPoints", "from": -1,
                      "plain": GoldenCompact.ints((-1...5).map { TetrisGame.perfectClearPoints(lines: $0, backToBackTetris: false) }),
                      "b2bTetris": GoldenCompact.ints((-1...5).map { TetrisGame.perfectClearPoints(lines: $0, backToBackTetris: true) })])
        var combo: [Int] = []
        for c in -2...6 { for s in [1, 2, 3, 30] { combo.append(TetrisGame.comboPoints(combo: c, scoreLevel: s)) } }
        cases.append(["id": "comboPoints", "spec": "combo -2…6 × scoreLevel [1,2,3,30] 행 우선", "values": GoldenCompact.ints(combo)])
        var placement: [Int] = []
        for lines in 0...4 {
            for (_, spin) in spins {
                for level in [1, 7, 30] {
                    for b2b in [false, true] {
                        for c in [-1, 0, 3] {
                            for perfect in [false, true] {
                                placement.append(TetrisGame.placementPoints(lines: lines, spin: spin, scoreLevel: level,
                                                                            backToBack: b2b, combo: c, perfectClear: perfect))
                            }
                        }
                    }
                }
            }
        }
        cases.append(["id": "placementPoints",
                      "spec": "lines 0…4 × spin[none,mini,full] × scoreLevel[1,7,30] × backToBack[f,t] × combo[-1,0,3] × perfect[f,t] 행 우선",
                      "values": GoldenCompact.ints(placement)])
        var shapes: [String: GoldenJSON] = [:]
        var kicks: [String: GoldenJSON] = [:]
        for piece in TetrisGame.Piece.allCases {
            let letter = String(GoldenTetrisText.letters[piece.rawValue])
            for rotation in TetrisGame.Rotation.allCases {
                shapes["\(letter)\(rotation.rawValue)"] = .string(TetrisGame.shape(piece, rotation).map { "\($0.dx),\($0.dy)" }.joined(separator: " "))
                for to in TetrisGame.Rotation.allCases {
                    kicks["\(letter)\(rotation.rawValue)\(to.rawValue)"] =
                        .string(TetrisGame.kicks(piece: piece, from: rotation, to: to).map { "\($0.dx),\($0.dy)" }.joined(separator: " "))
                }
            }
        }
        cases.append(["id": "shapes", "spec": "키 = 조각 글자 + 회전 rawValue, 값 = \"dx,dy\" 넷(상자 왼쪽 위 기준)", "table": .object(shapes)])
        cases.append(["id": "kicks", "spec": "키 = 조각 글자 + from + to(rawValue), 값 = \"dx,dy\"(y 양수 = 위)", "table": .object(kicks)])
        var nextLevel: [Int] = []
        for a in 0...700 {
            let g = TetrisGame(seed: 0, board: TetrisGame.emptyBoard(), active: nil, advance: a)
            nextLevel.append(g.advanceToNextLevel)
        }
        cases.append(["id": "advanceToNextLevel", "from": 0, "values": GoldenCompact.ints(nextLevel)])
        cases.append([
            "id": "constants",
            "columns": .int(TetrisGame.columns), "totalRows": .int(TetrisGame.totalRows), "visibleRows": .int(TetrisGame.visibleRows),
            "firstVisibleRow": .int(TetrisGame.firstVisibleRow), "spawnRow": .int(TetrisGame.spawnRow),
            "spawnColumn": .int(TetrisGame.spawnColumn), "nextCount": .int(TetrisGame.nextCount),
            "maxStepBits": .bits(TetrisGame.maxStep), "dasSecondsBits": .bits(TetrisGame.dasSeconds),
            "arrSecondsBits": .bits(TetrisGame.arrSeconds), "areSecondsBits": .bits(TetrisGame.areSeconds),
            "lineClearSecondsBits": .bits(TetrisGame.lineClearSeconds), "overHoldBits": .bits(TetrisGame.overHold),
            "maxGroundedSecondsBits": .bits(TetrisGame.maxGroundedSeconds), "advanceAtGravityCap": .int(TetrisGame.advanceAtGravityCap),
            "scoreLevelCap": .int(TetrisGame.scoreLevelCap), "maxScore": .int(TetrisGame.maxScore),
            "kindMaxScore": .int(MiniGameKind.tetris.maxScore),
            "maxGarbageInsertPerLock": .int(TetrisGame.maxGarbageInsertPerLock), "maxLevelFloor": .int(TetrisGame.maxLevelFloor),
            "pieceOrder": .string(GoldenTetrisText.pieces(TetrisGame.Piece.allCases)),
        ])
        // 배치·색 상수(TetrisLayout · TetrisPalette — Kotlin 은 상수만 옮긴다, C§3.2 A-1).
        let layout: [Double] = [
            TetrisLayout.logicalSize.width, TetrisLayout.logicalSize.height, TetrisLayout.cell, TetrisLayout.outerMargin,
            TetrisLayout.columnWidth, TetrisLayout.gutter, TetrisLayout.boardX, TetrisLayout.boardWidth, TetrisLayout.rightColumnX,
            TetrisLayout.bufferY, TetrisLayout.boardTopY, TetrisLayout.boardBottomY, TetrisLayout.bandY, TetrisLayout.bandHeight,
            TetrisLayout.textMinX, TetrisLayout.textMaxX, TetrisLayout.labelY, TetrisLayout.labelHeight, TetrisLayout.boxY,
            TetrisLayout.boxHeight, TetrisLayout.stageChipY, TetrisLayout.stageChipHeight, TetrisLayout.levelCaptionY,
            TetrisLayout.levelValueY, TetrisLayout.linesCaptionY, TetrisLayout.linesValueY, TetrisLayout.captionHeight,
            TetrisLayout.valueHeight, TetrisLayout.slotGap, TetrisLayout.miniCell,
        ].map { Double($0) }
        let rects = [TetrisLayout.cellRect(row: 20, column: 0), TetrisLayout.cellRect(row: 39, column: 9),
                     TetrisLayout.cellRect(row: 19, column: 4), TetrisLayout.wellRect]
        var palette: [Double] = [TetrisPalette.wellInk.r, TetrisPalette.wellInk.g, TetrisPalette.wellInk.b, TetrisPalette.wellOpacity,
                                 TetrisPalette.ghostOpacity, TetrisPalette.spentOpacity]
        for piece in TetrisGame.Piece.allCases {
            let c = TetrisPalette.rgb[piece]!
            palette += [c.r, c.g, c.b]
        }
        cases.append([
            "id": "layout",
            "spec": "TetrisLayout 상수 30개(logicalSize w·h · cell · outerMargin · columnWidth · gutter · boardX · boardWidth · rightColumnX · bufferY · boardTopY · boardBottomY · bandY · bandHeight · textMinX · textMaxX · labelY · labelHeight · boxY · boxHeight · stageChipY · stageChipHeight · levelCaptionY · levelValueY · linesCaptionY · linesValueY · captionHeight · valueHeight · slotGap · miniCell) · slotY(0…4) · cellRect(20,0)(39,9)(19,4) · wellRect([x,y,w,h]) · 팔레트(wellInk rgb · wellOpacity · ghostOpacity · spentOpacity · 조각 ijlostz 의 rgb)",
            "constantsBits": GoldenCompact.bits(layout),
            "slotYBits": GoldenCompact.bits((0..<5).map { Double(TetrisLayout.slotY($0)) }),
            "rectsBits": GoldenCompact.bits(rects.flatMap { [Double($0.origin.x), Double($0.origin.y), Double($0.width), Double($0.height)] }),
            "paletteBits": GoldenCompact.bits(palette),
        ])
        goldenEmit(GoldenFile(
            golden: "tetris/rules",
            equivalence: .bit,
            swiftSources: [Self.engine, Self.rngSource, "Sources/CheckCore/TetrisLayout.swift"],
            spec: [
                "tables": "정수·불 표는 공백으로 이은 글자(불은 0/1 한 글자씩), 실수는 IEEE-754 비트 16진을 공백으로 이은 글자. from = 첫 입력값(1씩 오른다)",
                "gravity": "gravitySecondsForStage 는 Darwin pow 의 비트다 — Kotlin 은 pow 를 부르지 않고 이 비트를 상수 표로 든다(G §8-14). 1 미만·20 초과 단계는 클램프",
                "rounding": "lockResetLimit 은 Swift .rounded()(0.5 는 0 에서 먼 쪽)",
            ],
            cases: cases
        ))
    }

    // MARK: - tetris/bags (G2)

    static func bagSeeds() -> [(String, UInt64)] {
        var seeds: [(String, UInt64)] = [
            ("zero", 0), ("one", 1), ("server-max", 2_147_483_647), ("int63-max", 0x7FFF_FFFF_FFFF_FFFF),
            ("int63-min", 0x8000_0000_0000_0000), ("uint64-max", .max), ("tetris-a", 20_261_020), ("tetris-b", 7_777),
            ("tetris-c", 330), ("tetris-d", 930),
        ]
        var stream = MiniGameRandom(seed: 0xC0FF_EE00_1234_5678)
        for index in 0..<190 {
            let raw = stream.next()
            // 반은 서버 시드 범위(0…2147483647), 반은 64비트 전체.
            seeds.append(("s\(index)", index % 2 == 0 ? raw % 2_147_483_648 : raw))
        }
        return seeds
    }

    @Test("tetris/bags — 시드 200 × 7-bag 10봉지(조각 70)")
    func bags() {
        let cases: [GoldenJSON] = Self.bagSeeds().map { id, seed in
            var rng = MiniGameRandom(seed: seed)
            var pieces: [TetrisGame.Piece] = []
            for _ in 0..<10 { pieces += TetrisGame.shuffledBag(&rng) }
            // 엔진 넥스트 큐(새 판 시작 직후)도 같은 열의 앞부분이어야 한다 — 큐가 봉지를 쓰는 순서까지 묶는다.
            var game = TetrisGame(seed: seed)
            game.action()
            return [
                "id": .string(id), "seed": .hex64(seed), "pieces": .string(GoldenTetrisText.pieces(pieces)),
                "firstActive": .string(game.active.map { String(GoldenTetrisText.letters[$0.piece.rawValue]) } ?? "-"),
                "firstNext": .string(GoldenTetrisText.pieces(game.next)),
            ]
        }
        goldenEmit(GoldenFile(
            golden: "tetris/bags",
            equivalence: .bit,
            swiftSources: [Self.engine, Self.rngSource],
            spec: [
                "pieces": "MiniGameRandom(seed) 하나로 shuffledBag 를 10번(Fisher-Yates, 부호 없는 rng.next() % (i+1)) — 글자 ijlostz = Piece rawValue 0…6",
                "engine": "firstActive · firstNext = TetrisGame(seed).action() 직후 떨어지는 조각과 넥스트 5",
            ],
            cases: cases
        ))
    }

    // MARK: - tetris/garbage-holes (G2, 엔진 경유)

    @Test("tetris/garbage-holes — 시드 64 × 엔진이 넣은 방해 줄 구멍(굳힘 넷 × 8줄)")
    func garbageHoles() {
        let seeds = Array(Self.bagSeeds().prefix(64))
        let cases: [GoldenJSON] = seeds.map { id, seed in
            let run = Self.garbageHoleRun(seed: seed)
            return ["id": .string(id), "seed": .hex64(seed), "holes": GoldenCompact.ints(run.holes),
                    "locks": .int(run.locks), "phase": GoldenTetrisText.phase(run.game.phase),
                    "board": .string(GoldenTetrisText.board(run.game))]
        }
        goldenEmit(GoldenFile(
            golden: "tetris/garbage-holes",
            equivalence: .bit,
            swiftSources: [Self.engine, Self.rngSource],
            spec: [
                "procedure": "game = TetrisGame(seed, board: 빈 판, active: O(spawn, 열 3, 행 18), phase: running, pendingGarbage: [1]×8). 굳힘 k = 1…4: (k>1 이면 step(0.05) 두 번 · receiveGarbage(1) 여덟 번) → action()(하드드롭 → 굳힘 → 8줄 삽입). 굳힘마다 단계가 over 면 멈춘다. 삽입 뒤 행 32…39 의 garbageMask 에서 비트가 빈 열이 그 줄의 구멍(넣은 순서)",
                "holes": "구멍 열(0…9)을 넣은 순서대로 — 묶음 하나 = garbageRng(seed ^ 0x6a09e667f3bcc909).next() % 10 한 번",
            ],
            cases: cases
        ))
    }

    static func garbageHoleRun(seed: UInt64) -> (holes: [Int], locks: Int, game: TetrisGame) {
        var game = TetrisGame(seed: seed, board: TetrisGame.emptyBoard(),
                              active: TetrisGame.ActivePiece(piece: .o, column: TetrisGame.spawnColumn, row: TetrisGame.spawnRow),
                              pendingGarbage: Array(repeating: 1, count: 8))
        var holes: [Int] = []
        var locks = 0
        for k in 1...4 {
            if k > 1 {
                game.step(dt: 0.05)
                game.step(dt: 0.05)
                for _ in 0..<8 { _ = game.receiveGarbage(lines: 1) }
            }
            game.action()
            locks += 1
            if case .over = game.phase { break }
            for row in 32..<40 {
                let mask = game.garbageMask[row]
                guard let hole = (0..<TetrisGame.columns).first(where: { mask & (UInt16(1) << $0) == 0 }) else { continue }
                holes.append(hole)
            }
        }
        return (holes, locks, game)
    }

    // MARK: - tetris/scripted (G3)

    struct ScriptedCase {
        var id: String
        var seed: UInt64
        var advance: Int?
        var dt: Double
        var maxFrames: Int
        var actEvery: Int
    }

    /// A~D 는 V0360(C-X2) 대본 그대로, E~G 는 주사율이 다른 dt(1/24 · 1/119 · 0.07 → 클램프 1/20).
    static let scriptedCases: [ScriptedCase] = [
        ScriptedCase(id: "A", seed: 20_261_020, advance: nil, dt: 1.0 / 64.0, maxFrames: 64 * 900, actEvery: 4),
        ScriptedCase(id: "B", seed: 7_777, advance: nil, dt: 1.0 / 32.0, maxFrames: 32 * 3_600, actEvery: 2),
        ScriptedCase(id: "C", seed: 330, advance: 330, dt: 1.0 / 64.0, maxFrames: 64 * 900, actEvery: 4),
        ScriptedCase(id: "D", seed: 930, advance: 930, dt: 1.0 / 128.0, maxFrames: 128 * 600, actEvery: 8),
        ScriptedCase(id: "E", seed: 24, advance: nil, dt: 1.0 / 24.0, maxFrames: 24 * 240, actEvery: 2),
        ScriptedCase(id: "F", seed: 119, advance: nil, dt: 1.0 / 119.0, maxFrames: 119 * 60, actEvery: 7),
        ScriptedCase(id: "G", seed: 2_147_483_647, advance: 300, dt: 0.07, maxFrames: 20 * 120, actEvery: 1),
    ]
    static let checkpointEvery = 64

    /// 조종사 없이 연산만으로 다시 돈다 — 누적 해시(= C-X2 정의) · 체크포인트 · 프레임 바이트.
    static func replay(start: TetrisGame, preOps: [GoldenTetrisOp], frames: [[GoldenTetrisOp]], dt: Double)
        -> (hash: UInt64, checkpoints: [UInt64], bytes: String, frames: Int, game: TetrisGame) {
        var g = start
        for op in preOps { op.apply(to: &g) }
        var total = GoldenFNV1a64()
        GoldenTetrisFold.board(g, into: &total)
        var checkpoints: [UInt64] = []
        var bytes = GoldenFrameBytes()
        var frame = 0
        for ops in frames {
            frame += 1
            let before = g.advance
            for op in ops { op.apply(to: &g) }
            g.step(dt: dt)
            var local = GoldenFNV1a64()
            GoldenTetrisFold.light(g, into: &total)
            GoldenTetrisFold.light(g, into: &local)
            if g.advance != before {
                GoldenTetrisFold.board(g, into: &total)
                GoldenTetrisFold.board(g, into: &local)
            }
            bytes.append(local.value)
            if frame % checkpointEvery == 0 { checkpoints.append(total.value) }
            if case .result = g.phase { break }
        }
        return (total.value, checkpoints, bytes.text, frame, g)
    }

    @Test("tetris/scripted — 대본 A~G: 연산 RLE → 64프레임 체크포인트 · 프레임 바이트 · 끝 상태(A~D 해시 = V0360)")
    func scripted() throws {
        let v0360: [String: UInt64] = ["A": 0x64cd_f7c7_36fc_a8b9, "B": 0xb8cf_1911_16c8_9774,
                                       "C": 0xd30f_b21e_622f_28c6, "D": 0x6519_e5cd_f43b_db8c]
        var cases: [GoldenJSON] = []
        for script in Self.scriptedCases {
            let pilot: GoldenTetrisPilot.Result
            if let advance = script.advance {
                pilot = GoldenTetrisPilot.fromAdvance(advance, seed: script.seed, dt: script.dt, maxFrames: script.maxFrames,
                                                      actEvery: script.actEvery, checkpointEvery: Self.checkpointEvery)
            } else {
                pilot = GoldenTetrisPilot.fromNewGame(seed: script.seed, dt: script.dt, maxFrames: script.maxFrames,
                                                      actEvery: script.actEvery, checkpointEvery: Self.checkpointEvery)
            }
            let rle = GoldenTetrisRLE.encode(pilot.frames)
            let decoded = try GoldenTetrisRLE.decode(rle)
            let run = Self.replay(start: pilot.start, preOps: pilot.preOps, frames: decoded, dt: script.dt)
            #expect(run.hash == pilot.trace.hash, "\(script.id): 연산 재생 해시가 조종사와 다르다")
            #expect(run.checkpoints == pilot.trace.checkpoints, "\(script.id): 체크포인트가 조종사와 다르다")
            if let pinned = v0360[script.id] {
                #expect(run.hash == pinned, "\(script.id): V0360 박힌 해시와 다르다")
            }
            let start: GoldenJSON
            if let advance = script.advance {
                start = ["kind": "advance", "advance": .int(advance)]
            } else {
                start = ["kind": "new", "preOps": .string(pilot.preOps.map(\.rawValue).joined(separator: " "))]
            }
            cases.append([
                "id": .string(script.id),
                "seed": .hex64(script.seed),
                "dtBits": .bits(script.dt),
                "start": start,
                "ops": .string(rle),
                "checkpointEvery": .int(Self.checkpointEvery),
                "checkpoints": .string(run.checkpoints.map(GoldenBits.hex64).joined(separator: " ")),
                "frameBytes": .string(run.bytes),
                "final": GoldenTetrisText.final(run.game, hash: run.hash, frames: run.frames),
            ])
        }
        goldenEmit(GoldenFile(
            golden: "tetris/scripted",
            equivalence: .bit,
            swiftSources: [Self.engine, Self.rngSource],
            spec: [
                "replay": "contract/README.md §2-4 그대로: 시작 판(new = TetrisGame(seed) 에 preOps, advance = TetrisGame(seed, 빈 판, active nil, phase are(0.1), advance)) → 판 전체 접기 → 프레임마다 [연산 → step(dt) → goldFoldLight, advance 가 바뀐 프레임엔 goldFoldBoard] · 결과 단계에 들면 멈춘다",
                "fold": "FNV-1a 64(64비트 값을 작은 끝부터 8바이트). light = active(piece·rotation·column·row 또는 −1) · next 개수·조각 · held(또는 −1) · holdUsed · score · advance · lines · combo · backToBack · phase(ready 0 · running 1 · lineClear 2+남은 · are 3+남은 · over 4+유예 · result 5) · elapsed · lastClear(lines · spin 0/1/2 · backToBack · perfectClear · points · at, 없으면 −2) · level · scoreLevel · isGrounded. board = 40×10 칸 rawValue(빈 칸 −1). Int 는 Int64 비트, Double 은 비트, Bool 은 1/0",
                "checkpoints": "누적 해시를 checkpointEvery 프레임마다(공백으로 이은 0x 글자)",
                "frameBytes": "프레임마다 그 프레임 몫(light + 바뀐 판)만 새 FNV 로 접은 값의 아래 1바이트 16진 — 첫 불일치 프레임 번호를 짚는다",
                "final.board": "40행을 / 로 이은 글자(. 빈 칸, ijlostz)",
                "v0360": "A~D 의 final.hash = V0360TetrisSoloGoldenTests 박힌 해시(C-X2)",
            ],
            cases: cases
        ))
    }

    // MARK: - tetris/duel-rules (G1)

    @Test("tetris/duel-rules — 가속 바닥 · 시작 시각 옮기기 · 판 글자(검사·풀기·싸기) · 다시 열기")
    func duelRules() {
        var cases: [GoldenJSON] = []
        let times: [Double] = [-1, 0, 119.999, 120, 120.5, 129.999, 130, 135.7, 179.9, 180, 300, 299.99, 999_999.9, 1_000_000,
                               .infinity, -.infinity, .nan, 1e300, 0.0000001]
        cases.append(["id": "rampLevelFloor", "timesBits": GoldenCompact.bits(times),
                      "values": GoldenCompact.ints(times.map { TetrisDuelSession.rampLevelFloor(elapsedSeconds: $0) })])
        let starts: [(Double, Double, Double)] = [(1_000_003_000, 1_000_000_000, 0.5), (0, 50_400, 12.25),
                                                   (1_761_600_000_123, 1_761_600_002_000, 1234.5678), (5, 5, -3)]
        cases.append(["id": "localStart",
                      "inputsBits": .array(starts.map { GoldenCompact.bits([$0.0, $0.1, $0.2]) }),
                      "valuesBits": GoldenCompact.bits(starts.map { TetrisDuelSession.localStart(startAtMs: $0.0, serverNowMs: $0.1, localNow: $0.2) })])
        // 판 글자: 검사·풀기(다시 싸서 같은 글자인가).
        let empty = TetrisDuelBoard.emptyText
        let sample = String(repeating: ".", count: 150) + "..IJLOSTZ." + "G.GGGGGGGG" + "ZZ.TTTOO.I" + "GGGG.GGGGG" + "LJLJ.SSZZI"
        let texts: [(String, String)] = [
            ("empty", empty), ("sample", sample), ("short", String(sample.dropLast())), ("long", sample + "."),
            ("lower", sample.replacingOccurrences(of: "I", with: "i")), ("hangul", String(sample.dropLast()) + "가"),
            ("blank", ""), ("allG", String(repeating: "G", count: 200)),
        ]
        for (id, text) in texts {
            let decoded = TetrisDuelBoard.decode(text)
            let reencoded: GoldenJSON = decoded.map { rows -> GoldenJSON in
                .string(rows.map { row in String(row.map { cell -> Character in
                    switch cell {
                    case .empty: return "."
                    case .piece(let p): return TetrisDuelBoard.letter(for: p)
                    case .garbage: return "G"
                    }
                }) }.joined())
            } ?? .null
            cases.append(["id": .string("board-\(id)"), "cps": .string(text.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " ")),
                          "valid": .bool(TetrisDuelBoard.isValid(text)), "decoded": reencoded])
        }
        // 싸기: 픽스처 판 + 방해 줄 표시.
        let rows = ["..........", "TT.......G", "IJLOSTZ...", "GGGGG.GGGG", "Gzzzz.GGGG"]
        let encodeGame = TetrisGame(seed: 3, board: TetrisGame.boardFixture(bottomRows: rows), active: nil,
                                    garbageMask: TetrisGame.garbageMaskFixture(bottomRows: rows))
        cases.append(["id": "encode-fixture", "rows": .array(rows.map { GoldenJSON.string($0) }),
                      "text": .string(TetrisDuelBoard.encode(encodeGame)),
                      "fixtureBoard": .string(GoldenTetrisText.board(encodeGame)),
                      "fixtureMask": .array(encodeGame.garbageMask.map { GoldenJSON.int(Int($0)) })])
        // 다시 열기.
        let points: [(String, Int, TetrisDuelResumePoint)] = [
            ("resume-sample", 1_234_567, TetrisDuelResumePoint(seq: 12, board: sample, lines: 9, garbageSent: 7, garbageApplied: 4,
                                                                pending: 3, elapsedSeconds: 50.25)),
            ("resume-negative", -5, TetrisDuelResumePoint(seq: -3, board: empty, lines: -2, garbageSent: -1, garbageApplied: -9,
                                                          pending: 0, elapsedSeconds: -.infinity)),
            ("resume-nan", 7, TetrisDuelResumePoint(seq: 1, board: sample, lines: 0, garbageSent: 0, garbageApplied: 0,
                                                    pending: 2, elapsedSeconds: .nan)),
            ("resume-broken", 7, TetrisDuelResumePoint(seq: 1, board: String(sample.dropLast()), lines: 0, garbageSent: 0,
                                                       garbageApplied: 0, pending: 0, elapsedSeconds: 1)),
        ]
        for (id, seed, point) in points {
            var item: [String: GoldenJSON] = [
                "id": .string(id), "seed": .int(seed), "seq": .int(point.seq), "board": .string(point.board),
                "lines": .int(point.lines), "garbageSent": .int(point.garbageSent), "garbageApplied": .int(point.garbageApplied),
                "pending": .int(point.pending), "elapsedSecondsBits": .bits(point.elapsedSeconds),
            ]
            if let s = TetrisDuelSession(seed: seed, resumingFrom: point) {
                item["result"] = Self.sessionJSON(s)
            } else {
                item["result"] = .null
            }
            cases.append(.object(item))
        }
        // 새 세션(음수 시드 · 이어 보고).
        for (id, seed, seq, applied) in [("new-negative", -5, -1, -7), ("new-resumed-seq", 99, 41, 13)] {
            cases.append(["id": .string(id), "seed": .int(seed), "startingSeq": .int(seq), "garbageAppliedIn": .int(applied),
                          "result": Self.sessionJSON(TetrisDuelSession(seed: seed, startingSeq: seq, garbageApplied: applied))])
        }
        goldenEmit(GoldenFile(
            golden: "tetris/duel-rules",
            equivalence: .bit,
            swiftSources: [Self.session, Self.duelBoard, Self.engine],
            spec: [
                "rampLevelFloor": "판 경과초(비트) → 레벨 바닥(D7)",
                "localStart": "(startAtMs, serverNowMs, localNow) 비트 → 로컬 단조 시계의 판 시작 비트",
                "board-*": "cps = 입력 글자의 유니코드 스칼라(16진). valid = isValid, decoded = decode 를 다시 글자로(.IJLOSTZG) 또는 null",
                "encode-fixture": "boardFixture · garbageMaskFixture(같은 줄) → encode",
                "resume-*": "TetrisDuelSession(seed:resumingFrom:) — 못 풀면 null. result 는 세션 칸 + 엔진 판(40행 글자) · 표시 · 대기 · 단계",
                "new-*": "TetrisDuelSession(seed:startingSeq:garbageApplied:) — 시드 Int 는 UInt64(clamping:) 로 엔진에",
            ],
            cases: cases
        ))
    }

    static func sessionJSON(_ s: TetrisDuelSession) -> GoldenJSON {
        [
            "seed": .int(s.seed), "started": .bool(s.started), "finished": .bool(s.finished), "seq": .int(s.seq),
            "garbageApplied": .int(s.garbageApplied), "simulatedBits": .bits(s.simulated),
            "startAtBits": s.startAt.map(GoldenJSON.bits) ?? .null, "reportedAttackSent": .int(s.reportedAttackSent),
            "isLive": .bool(s.isLive), "toppedOut": .bool(s.toppedOut),
            "game": GoldenTetrisText.final(s.game, hash: 0, frames: 0),
            "firstNext": .string(GoldenTetrisText.pieces(s.game.next)),
        ]
    }

    // MARK: - tetris/duel (G3 — 대결 세션 대본)

    struct DuelCase {
        var id: String
        var seed: Int
        var dt: Double
        var seconds: Double
        var resume: TetrisDuelResumePoint?
        var preOps: [String]
        var gaps: [(at: Double, seconds: Double)]
        var finishAt: Double
        var style: Int
        /// 상대 공격을 보내는 로컬 시각 상한(초).
        var attackUntil: Double
    }

    static let duelSample = String(repeating: ".", count: 150) + "..IJLOSTZ." + "G.GGGGGGGG" + "ZZ.TTTOO.I" + "GGGG.GGGGG" + "LJLJ.SSZZI"

    static let duelCases: [DuelCase] = [
        DuelCase(id: "phone-60", seed: 1_234_567, dt: 1.0 / 60.0, seconds: 200, resume: nil,
                 preOps: ["SY1000003000/1000000000"], gaps: [(40, 2), (90, 35)], finishAt: 196, style: 0, attackUntil: 100),
        DuelCase(id: "keys-30", seed: 2_147_483_647, dt: 1.0 / 30.0, seconds: 170, resume: nil,
                 preOps: ["SY1000002500/1000000000"], gaps: [(70, 0.7)], finishAt: 168, style: 1, attackUntil: 100),
        // 가속(120초~)을 재려고 판 시계 115.25초에서 다시 연다 — 20G(바닥 15, 170초~)까지 간다.
        DuelCase(id: "resume-90", seed: 77, dt: 1.0 / 90.0, seconds: 80,
                 resume: TetrisDuelResumePoint(seq: 12, board: duelSample, lines: 9, garbageSent: 7, garbageApplied: 4,
                                               pending: 3, elapsedSeconds: 115.25),
                 preOps: ["SY0/115400"], gaps: [(30, 2)], finishAt: 79, style: 2, attackUntil: 12),
        DuelCase(id: "negative-seed-24", seed: -5, dt: 1.0 / 24.0, seconds: 60, resume: nil,
                 preOps: ["SY3000/0"], gaps: [], finishAt: 59, style: 1, attackUntil: 100),
    ]

    @Test("tetris/duel — 대결 세션 대본 넷(시작 맞추기 · 한 칸 이동 · 방해 줄 · 가속 · 따라잡기 · 보고 · 다시 열기 · 끝)")
    func duel() throws {
        var cases: [GoldenJSON] = []
        var reasonsSeen = Set<Int>()
        var maxFloor = 1
        for script in Self.duelCases {
            let recorded = GoldenDuelPilot.record(script)
            let rle = GoldenOpsRLE.encode(recorded.frames)
            let run = GoldenDuelReplay.run(seed: script.seed, resume: script.resume, preOps: script.preOps,
                                           frames: GoldenOpsRLE.decode(rle), dt: script.dt, checkpointEvery: Self.checkpointEvery)
            #expect(run.hash == recorded.hash, "\(script.id): 연산 재생이 조종사 판과 다르다")
            reasonsSeen.formUnion(run.reasons)
            maxFloor = max(maxFloor, run.maxLevelFloor)
            var item: [String: GoldenJSON] = [
                "id": .string(script.id), "seed": .int(script.seed), "dtBits": .bits(script.dt),
                "preOps": .string(script.preOps.joined(separator: " ")),
                "ops": .string(rle), "checkpointEvery": .int(Self.checkpointEvery),
                "checkpoints": .string(run.checkpoints.map(GoldenBits.hex64).joined(separator: " ")),
                "frameBytes": .string(run.bytes),
                "reports": .int(run.reportCount),
                "maxLevelFloor": .int(run.maxLevelFloor),
                "final": .object([
                    "hash": .hex64(run.hash), "frames": .int(run.frames), "session": Self.sessionJSON(run.session),
                    "droppedSecondsBits": .bits(run.session.droppedSeconds),
                    "lastReportAtBits": run.session.lastReportAt.map(GoldenJSON.bits) ?? .null,
                    "lastReport": run.lastReport.map { r -> GoldenJSON in
                        ["seq": .int(r.seq), "board": .string(r.board), "lines": .int(r.lines), "garbageSent": .int(r.garbageSent),
                         "garbageApplied": .int(r.garbageApplied), "pending": .int(r.pending), "toppedOut": .bool(r.toppedOut)]
                    } ?? .null,
                ]),
            ]
            if let point = script.resume {
                item["resume"] = ["seq": .int(point.seq), "board": .string(point.board), "lines": .int(point.lines),
                                  "garbageSent": .int(point.garbageSent), "garbageApplied": .int(point.garbageApplied),
                                  "pending": .int(point.pending), "elapsedSecondsBits": .bits(point.elapsedSeconds)]
            }
            cases.append(.object(item))
        }
        #expect(maxFloor >= 12, "대본이 가속 바닥 12 까지 가지 않았다(최대 \(maxFloor))")
        #expect(reasonsSeen == [0, 1, 2, 3], "대본 넷이 보고 까닭 넷(준비 · 탑아웃 · 공격 · 하트비트)을 다 거치지 않았다: \(reasonsSeen.sorted())")
        goldenEmit(GoldenFile(
            golden: "tetris/duel",
            equivalence: .bit,
            swiftSources: [Self.session, Self.engine, Self.duelBoard, Self.rngSource],
            spec: [
                "start": "resume 칸이 있으면 TetrisDuelSession(seed:resumingFrom:), 없으면 TetrisDuelSession(seed:). now = 0 에서 preOps → 판 전체 접기(아래 board)",
                "frame": "프레임 f(1부터): now = f × dt. 연산을 적힌 순서대로 → (N 이 없으면) advance(to: now) → reportReason(at: now) 이 있으면 makeReport(at: now) → 접기",
                "ops": "L+ L- R+ R- SD+ SD- = set*Held · CW CCW = rotate · HOLD = hold() · HD = hardDrop() · ML MR = moveLeft/RightOneCell() · SD1 = softDropOneCell() · REL = releaseAllKeys() · FIN = finish() · A<n> = absorbOpponentAttack(total: n) · Q<n> = adoptServerSeq(n) · SY<a>/<b> = syncStart(startAtMs: a, serverNowMs: b, localNow: now) · N = 이 프레임은 advance 를 부르지 않는다(멎은 화면 — 다음 advance 가 따라잡는다)",
                "fold": "누적 FNV(프레임 바이트는 그 프레임 몫만): tetris/scripted 의 light(game) → levelFloor · pendingGarbage 개수·묶음 · attackSentTotal → 세션 startAt(없으면 0, 있으면 1+비트) · simulated · started · finished · droppedSeconds · garbageApplied · seq · lastReportAt(같은 꼴) · reportedAttackSent · reportedToppedOut · isLive · toppedOut → 보고(없으면 0, 있으면 까닭 순번+1(ready 1 · toppedOut 2 · attack 3 · heartbeat 4) · seq · board 바이트마다 · lines · garbageSent · garbageApplied · pending · toppedOut) → advance 가 바뀐 프레임엔 board(40×10 rawValue, 빈 칸 −1) + garbageMask 40행",
                "reports": "만든 보고 수",
                "maxLevelFloor": "대본 동안 엔진이 받은 가속 바닥의 최댓값(재생 확인용)",
            ],
            cases: cases
        ))
    }
}

// MARK: - 대결 대본 재생(연산 → 세션)

enum GoldenDuelReplay {
    struct Run {
        var hash: UInt64
        var checkpoints: [UInt64]
        var bytes: String
        var frames: Int
        var session: TetrisDuelSession
        var reportCount: Int
        var lastReport: TetrisDuelReport?
        var reasons: Set<Int>
        var maxLevelFloor: Int
    }

    static func makeSession(seed: Int, resume: TetrisDuelResumePoint?) -> TetrisDuelSession {
        if let resume { return TetrisDuelSession(seed: seed, resumingFrom: resume)! }
        return TetrisDuelSession(seed: seed)
    }

    static func apply(_ op: String, to s: inout TetrisDuelSession, now: Double) {
        switch op {
        case "L+": s.setLeftHeld(true)
        case "L-": s.setLeftHeld(false)
        case "R+": s.setRightHeld(true)
        case "R-": s.setRightHeld(false)
        case "SD+": s.setSoftDropHeld(true)
        case "SD-": s.setSoftDropHeld(false)
        case "CW": s.rotate(clockwise: true)
        case "CCW": s.rotate(clockwise: false)
        case "HOLD": s.hold()
        case "HD": s.hardDrop()
        case "ML": s.moveLeftOneCell()
        case "MR": s.moveRightOneCell()
        case "SD1": _ = s.softDropOneCell()
        case "REL": s.releaseAllKeys()
        case "FIN": s.finish()
        case "N": break
        default:
            if op.hasPrefix("A") { _ = s.absorbOpponentAttack(total: Int(op.dropFirst())!) }
            else if op.hasPrefix("Q") { s.adoptServerSeq(Int(op.dropFirst())!) }
            else if op.hasPrefix("SY") {
                let parts = op.dropFirst(2).split(separator: "/")
                s.syncStart(startAtMs: Double(Int(parts[0])!), serverNowMs: Double(Int(parts[1])!), localNow: now)
            } else {
                Issue.record("모르는 대결 연산 \(op)")
            }
        }
    }

    static func board(_ s: TetrisDuelSession, into h: inout GoldenDualFold) {
        for row in s.game.board { for cell in row { h.add(cell?.rawValue ?? -1) } }
        for mask in s.game.garbageMask { h.add(Int(mask)) }
    }

    static func fold(_ s: TetrisDuelSession, reason: TetrisDuelReportReason?, report: TetrisDuelReport?, into h: inout GoldenDualFold) {
        var light = GoldenFNV1a64()
        // light 접기는 _base 의 정의를 그대로 쓰되 두 해시에 같이 싣기 위해 값을 다시 접는다.
        let g = s.game
        func lightValues() -> [UInt64] {
            var out: [UInt64] = []
            func a(_ x: Int) { out.append(UInt64(bitPattern: Int64(x))) }
            func d(_ x: Double) { out.append(x.bitPattern) }
            func b(_ x: Bool) { out.append(x ? 1 : 0) }
            if let p = g.active { a(p.piece.rawValue); a(p.rotation.rawValue); a(p.column); a(p.row) } else { a(-1) }
            a(g.next.count)
            for p in g.next { a(p.rawValue) }
            a(g.heldPiece?.rawValue ?? -1)
            b(g.holdUsed)
            a(g.score); a(g.advance); a(g.lines); a(g.combo); a(g.backToBack)
            switch g.phase {
            case .ready: a(0)
            case .running: a(1)
            case .lineClear(let left): a(2); d(left)
            case .are(let left): a(3); d(left)
            case .over(let hold): a(4); d(hold)
            case .result: a(5)
            }
            d(g.elapsed)
            if let c = g.lastClear {
                a(c.lines)
                switch c.spin { case .none: a(0); case .mini: a(1); case .full: a(2) }
                b(c.backToBack); b(c.perfectClear); a(c.points); d(c.at)
            } else {
                a(-2)
            }
            a(g.level); a(g.scoreLevel); b(g.isGrounded)
            return out
        }
        let values = lightValues()
        // 자기 확인: 위 값들이 _base 의 goldFoldLight 와 같은 열이다.
        var check = GoldenFNV1a64()
        GoldenTetrisFold.light(g, into: &check)
        for v in values { light.add(v) }
        precondition(light.value == check.value, "대결 접기의 light 몫이 _base GoldenTetrisFold.light 와 갈렸다")
        for v in values { h.add(v) }
        h.add(g.levelFloor)
        h.add(g.pendingGarbage.count)
        for n in g.pendingGarbage { h.add(n) }
        h.add(g.attackSentTotal)
        h.add(s.startAt)
        h.add(s.simulated)
        h.add(s.started)
        h.add(s.finished)
        h.add(s.droppedSeconds)
        h.add(s.garbageApplied)
        h.add(s.seq)
        h.add(s.lastReportAt)
        h.add(s.reportedAttackSent)
        h.add(s.reportedToppedOut)
        h.add(s.isLive)
        h.add(s.toppedOut)
        if let reason, let report {
            h.add(Self.ordinal(reason) + 1)
            h.add(report.seq)
            for byte in report.board.utf8 { h.add(Int(byte)) }
            h.add(report.lines)
            h.add(report.garbageSent)
            h.add(report.garbageApplied)
            h.add(report.pending)
            h.add(report.toppedOut)
        } else {
            h.add(0)
        }
    }

    static func ordinal(_ reason: TetrisDuelReportReason) -> Int {
        switch reason {
        case .ready: 0
        case .toppedOut: 1
        case .attack: 2
        case .heartbeat: 3
        }
    }

    static func run(seed: Int, resume: TetrisDuelResumePoint?, preOps: [String], frames: [[String]], dt: Double,
                    checkpointEvery: Int) -> Run {
        var s = makeSession(seed: seed, resume: resume)
        for op in preOps { apply(op, to: &s, now: 0) }
        var h = GoldenDualFold()
        board(s, into: &h)
        var checkpoints: [UInt64] = []
        var bytes = GoldenFrameBytes()
        var reports = 0
        var lastReport: TetrisDuelReport?
        var reasons = Set<Int>()
        var maxFloor = s.game.levelFloor
        var frame = 0
        for ops in frames {
            frame += 1
            let now = Double(frame) * dt
            h.beginFrame()
            let before = s.game.advance
            for op in ops { apply(op, to: &s, now: now) }
            if !ops.contains("N") { s.advance(to: now) }
            let reason = s.reportReason(at: now)
            let report = reason.map { _ in s.makeReport(at: now) }
            if let reason { reports += 1; reasons.insert(ordinal(reason)); lastReport = report }
            fold(s, reason: reason, report: report, into: &h)
            if s.game.advance != before { board(s, into: &h) }
            bytes.append(h.frame.value)
            if frame % checkpointEvery == 0 { checkpoints.append(h.total.value) }
            maxFloor = max(maxFloor, s.game.levelFloor)
        }
        return Run(hash: h.total.value, checkpoints: checkpoints, bytes: bytes.text, frames: frame, session: s,
                   reportCount: reports, lastReport: lastReport, reasons: reasons, maxLevelFloor: maxFloor)
    }
}

// MARK: - 대결 조종사(Swift 몫만 — Kotlin 은 연산만 재생한다)

enum GoldenDuelPilot {
    struct Recorded {
        var frames: [[String]]
        var hash: UInt64
    }

    static func boardCost(_ board: [[TetrisGame.Piece?]]) -> Double {
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
        return Double(heights.reduce(0, +)) * 0.51 + Double(holes) * 3.6 + Double(bumpiness) * 0.18 + Double(heights.max() ?? 0) * 0.5
    }

    /// (회전 수, 목표 왼쪽 열). 한 칸 이동(누름+뗌 쌍)으로 옮겨 하드드롭해 본 판의 비용이 가장 낮은 자리.
    static func bestPlacement(_ game: TetrisGame) -> (turns: Int, column: Int)? {
        guard game.active != nil else { return nil }
        var best: (turns: Int, column: Int)?
        var bestCost = Double.infinity
        for turns in 0..<4 {
            for column in 0..<TetrisGame.columns {
                var probe = game
                for _ in 0..<turns { probe.rotate(clockwise: true) }
                guard let piece = probe.active else { continue }
                let leftmost = piece.cells.map(\.column).min() ?? 0
                for _ in 0..<abs(column - leftmost) {
                    if column < leftmost { probe.setLeftHeld(true); probe.setLeftHeld(false) }
                    else { probe.setRightHeld(true); probe.setRightHeld(false) }
                }
                guard probe.active?.cells.map(\.column).min() == column else { continue }
                let before = probe.lines
                probe.action()
                let cost = boardCost(probe.board) - 14 * Double(probe.lines - before)
                if cost < bestCost { bestCost = cost; best = (turns, column) }
            }
        }
        return best
    }

    static func record(_ script: GoldenExportTetris.DuelCase) -> Recorded {
        var s = GoldenDuelReplay.makeSession(seed: script.seed, resume: script.resume)
        for op in script.preOps { GoldenDuelReplay.apply(op, to: &s, now: 0) }
        var h = GoldenDualFold()
        GoldenDuelReplay.board(s, into: &h)
        var frames: [[String]] = []
        let total = Int((script.seconds / script.dt).rounded(.down))
        var attackTotal = script.resume?.garbageApplied ?? 0
        var plan: (turns: Int, column: Int)?
        var planKey = -1
        var pieces = 0
        var softFrames = 0
        var heldLeft = false
        var finished = false
        var askedSeq = false
        for frame in 1...total {
            let now = Double(frame) * script.dt
            var ops: [String] = []
            let inGap = script.gaps.contains { now >= $0.at && now < $0.at + $0.seconds }
            if inGap { ops.append("N") }
            // 카운트다운 중 입력(무시돼야 한다)과 늦게 온 시작 추정(무시돼야 한다).
            if frame == 5 { ops.append("L+"); heldLeft = true }
            if frame == 7 { ops.append("HD") }
            if frame == 9 { ops.append("L-"); heldLeft = false }
            if frame == 30, let first = script.preOps.first { ops.append(first) }
            // 상대 공격: 판 앞쪽 100초 동안 10초마다 누계를 1~2 올린다(가끔 줄어든 값 — 멱등). 그 뒤로는 멈춰 가속(120초~)까지 버티게 한다.
            if frame % Int((10 / script.dt).rounded(.down)) == 0, now > 4, now < script.attackUntil {
                attackTotal += 1 + (frame / 7) % 2
                ops.append("A\(attackTotal)")
                if frame % 3 == 0 { ops.append("A\(attackTotal - 2)") }
            }
            if !askedSeq, s.seq >= 20 { ops.append("Q\(s.seq + 5)"); askedSeq = true }
            if !finished, now >= script.finishAt { ops.append("FIN"); finished = true }
            // 판 조작(살아 있고 조각이 있을 때만 — 그 밖의 입력은 엔진·세션이 무시하는지도 대본이 잰다).
            if !inGap, !finished, s.isLive, case .running = s.game.phase, let active = s.game.active {
                let key = s.game.advance * 2 + (s.game.holdUsed ? 1 : 0)
                if key != planKey {
                    planKey = key
                    pieces += 1
                    plan = bestPlacement(s.game)
                    softFrames = 0
                    if heldLeft { ops.append("L-"); heldLeft = false }
                }
                let leftmost = active.cells.map(\.column).min() ?? 0
                // 가속(바닥 10~)에서는 매 프레임 움직이고 바로 떨어뜨린다 — 조각이 순식간에 쌓인 더미에 닿는다.
                let fast = s.game.levelFloor >= 10
                let mode = fast ? 0 : (pieces + script.style) % 5
                let actNow = fast || frame % (script.style == 1 ? 2 : 3) == 0
                if mode == 4, !s.game.holdUsed, actNow, pieces % 3 == 0 {
                    ops.append("HOLD")
                } else if let p = plan, p.turns > 0, actNow {
                    ops.append(p.turns == 3 ? "CCW" : "CW")
                    var probe = s
                    probe.rotate(clockwise: p.turns != 3)
                    // 회전이 막히면(조각이 이미 내려앉았다) 남은 회전을 버린다 — 조종사 _base 와 같은 처리.
                    plan = probe.game.active?.rotation == active.rotation ? (0, p.column) : (p.turns == 3 ? 0 : p.turns - 1, p.column)
                } else if let p = plan, p.turns == 0, leftmost != p.column, actNow {
                    if script.style == 1, abs(leftmost - p.column) >= 3, !heldLeft, leftmost > p.column {
                        ops.append("L+"); heldLeft = true          // 키보드식 DAS 미끄러짐
                    } else if heldLeft {
                        if leftmost <= p.column { ops.append("L-"); heldLeft = false }
                    } else {
                        ops.append(leftmost > p.column ? "ML" : "MR")
                    }
                } else if actNow {
                    if heldLeft { ops.append("L-"); heldLeft = false }
                    switch mode {
                    case 1 where softFrames < 6:
                        ops.append("SD1"); softFrames += 1
                    case 2 where softFrames == 0:
                        ops.append("SD+"); softFrames = 1
                    case 2 where softFrames < 16:
                        softFrames += 1
                    case 2:
                        ops.append("SD-"); ops.append("HD")
                    default:
                        ops.append("HD")
                    }
                }
            }
            if frame == total - 3 { ops.append("REL") }
            let before = s.game.advance
            h.beginFrame()
            for op in ops { GoldenDuelReplay.apply(op, to: &s, now: now) }
            if !ops.contains("N") { s.advance(to: now) }
            let reason = s.reportReason(at: now)
            let report = reason.map { _ in s.makeReport(at: now) }
            GoldenDuelReplay.fold(s, reason: reason, report: report, into: &h)
            if s.game.advance != before { GoldenDuelReplay.board(s, into: &h) }
            frames.append(ops)
        }
        return Recorded(frames: frames, hash: h.total.value)
    }
}
