// 원본: 없음 — W1-a 길건너 아잉이 골든 생성 시험(G §8-16: 시드 줄 생성 · 차/강/통나무/기차/놓침 충돌 · 점수 단조 · 입력 줄 세우기 ·
// 막힌 칸). 원본 엔진: Sources/CheckCore/CrossyGame.swift · MiniGameEngine.swift @ 1b8260d.
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

@Suite("GoldenExport games-tetris-minigame — 길건너 아잉이(규칙표 · 시드 줄 · 대본)")
struct GoldenExportCrossy {
    static let engine = "Sources/CheckCore/CrossyGame.swift"
    static let kinds = "Sources/CheckCore/MiniGameEngine.swift"
    static let checkpointEvery = 64

    // MARK: - 줄 글자(G2 · G3 공용)

    static func propText(_ p: CrossyGame.Prop?) -> String {
        switch p {
        case nil: return "."
        case .rock?: return "r"
        case .tree(let h)?: return String(h)
        }
    }

    static func moverText(_ m: CrossyGame.Mover) -> String {
        "\(GoldenBits.bits(m.x)):\(GoldenBits.bits(m.length)):\(m.variant):\(m.isTruck ? 1 : 0)"
    }

    /// 줄 한 개의 정규 글자: row|kind|props|direction|speed|movers|train|trainCountdown|trainRandom.state
    static func laneText(_ l: CrossyGame.Lane) -> String {
        [
            String(l.row), l.kind.rawValue, l.props.map(propText).joined(), String(l.direction), GoldenBits.bits(l.speed),
            l.movers.map(moverText).joined(separator: ";"),
            l.train.map { "\(GoldenBits.bits($0.x)):\(GoldenBits.bits($0.length))" } ?? "-",
            GoldenBits.bits(l.trainCountdown), GoldenBits.hex64(l.trainRandom.state),
        ].joined(separator: "|")
    }

    // MARK: - crossy/rules (G1)

    @Test("crossy/rules — 상수 · 난이도 · 카메라 빠르기 · 방향 · 사유 · 겹침 · 막힌 칸 · 통나무 · 경고등 · 뛰기 진행")
    func rules() {
        var cases: [GoldenJSON] = []
        cases.append([
            "id": "constants",
            "columns": .int(CrossyGame.columns), "startColumn": .int(CrossyGame.startColumn),
            "hopSecondsBits": .bits(CrossyGame.hopSeconds), "serverTimeMarginFactorBits": .bits(CrossyGame.serverTimeMarginFactor),
            "maxScore": .int(CrossyGame.maxScore), "kindMaxScore": .int(MiniGameKind.crossy.maxScore),
            "maxStepBits": .bits(CrossyGame.maxStep), "deathHoldBits": .bits(CrossyGame.deathHold),
            "playerHalfWidthBits": .bits(CrossyGame.playerHalfWidth), "logGraceBits": .bits(CrossyGame.logGrace),
            "carLengthBits": .bits(CrossyGame.carLength), "truckLengthBits": .bits(CrossyGame.truckLength),
            "trackMarginBits": .bits(CrossyGame.trackMargin), "warnSecondsBits": .bits(CrossyGame.warnSeconds),
            "trainLengthBits": .bits(CrossyGame.trainLength), "trainSpeedBits": .bits(CrossyGame.trainSpeed),
            "behindRowsBits": .bits(CrossyGame.behindRows), "idleLimitBits": .bits(CrossyGame.idleLimit),
            "followRateBits": .bits(CrossyGame.followRate), "startGrassRows": .int(CrossyGame.startGrassRows),
            "wallRow": .int(CrossyGame.wallRow), "railStartRow": .int(CrossyGame.railStartRow),
            "riverStartRow": .int(CrossyGame.riverStartRow), "difficultyRowsBits": .bits(CrossyGame.difficultyRows),
            "lanesBehind": .int(CrossyGame.lanesBehind), "lanesAhead": .int(CrossyGame.lanesAhead),
            "trackBits": GoldenCompact.bits([CrossyGame.trackLeft, CrossyGame.trackRight, CrossyGame.trackLength]),
            "playBits": GoldenCompact.bits([CrossyGame.playMinX, CrossyGame.playMaxX]),
        ])
        let rows = Array(-10...300)
        cases.append(["id": "difficulty", "from": -10,
                      "difficultyBits": GoldenCompact.bits(rows.map { CrossyGame.difficulty(row: $0) }),
                      "creepSpeedBits": GoldenCompact.bits(rows.map { CrossyGame.creepSpeed(row: $0) })])
        cases.append(["id": "enums",
                      "directions": .string(CrossyGame.Direction.allCases.map { "\($0.rawValue):\($0.rowDelta):\($0.columnDelta)" }.joined(separator: " ")),
                      "laneKinds": .string(CrossyGame.LaneKind.allCases.map(\.rawValue).joined(separator: " ")),
                      "deathCauses": .array(CrossyGame.DeathCause.allCases.map { .string("\($0.rawValue)=\($0.caption)") })])
        // 겹침: 물체 셋 × 중심 격자 × (반폭, 너그러움) 넷.
        let movers = [CrossyGame.Mover(x: 2, length: 1.4), CrossyGame.Mover(x: -1.25, length: 2.4, variant: 3, isTruck: true),
                      CrossyGame.Mover(x: 7.5, length: 14)]
        let widths: [(Double, Double)] = [(0.3, 0), (0.3, 0.06), (0, 0), (0.5, 0.2)]
        let centers = (0...48).map { -2.0 + Double($0) * 0.25 }
        var overlaps: [Bool] = []
        for m in movers { for (hw, g) in widths { for c in centers { overlaps.append(m.overlaps(center: c, halfWidth: hw, grace: g)) } } }
        cases.append(["id": "overlaps", "spec": "물체 × (반폭, 너그러움) × 중심 행 우선",
                      "movers": .string(movers.map(Self.moverText).joined(separator: ";")),
                      "widthsBits": .array(widths.map { GoldenCompact.bits([$0.0, $0.1]) }),
                      "centersBits": GoldenCompact.bits(centers), "values": GoldenCompact.bools(overlaps)])
        // 막힌 칸 · 통나무 · 경고등.
        let grass = CrossyGame.Lane(row: 7, kind: .grass, props: [.tree(height: 0), nil, .rock, nil, nil, .tree(height: 2), nil, nil, .rock])
        let road = CrossyGame.Lane(row: 8, kind: .road, direction: -1, speed: 2.1, movers: [CrossyGame.Mover(x: 1, length: 1.4)])
        let river = CrossyGame.Lane(row: 9, kind: .river, direction: 1, speed: 1.1,
                                    movers: [CrossyGame.Mover(x: -4.5, length: 3), CrossyGame.Mover(x: 1.2, length: 2),
                                             CrossyGame.Mover(x: 5.6, length: 4)])
        let rails = [
            CrossyGame.Lane(row: 20, kind: .rail, direction: 1, speed: 24, trainCountdown: 1.0000001, trainSeed: 9),
            CrossyGame.Lane(row: 21, kind: .rail, direction: -1, speed: 24, trainCountdown: 1.0, trainSeed: 9),
            CrossyGame.Lane(row: 22, kind: .rail, direction: 1, speed: 24, train: CrossyGame.Mover(x: -3, length: 14), trainCountdown: 0),
            CrossyGame.Lane(row: 23, kind: .rail, direction: 1, speed: 24, trainCountdown: -0.5),
        ]
        let columns = Array(-2...10)
        let logXs = (0...44).map { -6.0 + Double($0) * 0.4 }
        cases.append([
            "id": "lanes",
            "grass": .string(Self.laneText(grass)), "road": .string(Self.laneText(road)), "river": .string(Self.laneText(river)),
            "columnsFrom": -2,
            "grassBlocked": GoldenCompact.bools(columns.map { grass.isBlocked(column: $0) }),
            "roadBlocked": GoldenCompact.bools(columns.map { road.isBlocked(column: $0) }),
            "velocityBits": GoldenCompact.bits([grass.velocity, road.velocity, river.velocity]),
            "logXsBits": GoldenCompact.bits(logXs),
            "logIndex": GoldenCompact.ints(logXs.map { x in river.log(under: x).flatMap { found in river.movers.firstIndex(of: found) } ?? -1 }),
            "roadLog": GoldenCompact.ints(logXs.map { x in road.log(under: x) == nil ? -1 : 0 }),
            "rails": .string(rails.map(Self.laneText).joined(separator: " ")),
            "trainWarning": GoldenCompact.bools(rails.map(\.isTrainWarning) + [grass.isTrainWarning, river.isTrainWarning]),
        ])
        let hops = (0...20).map { k -> Double in Double(k) * 0.0071 - 0.01 }
        cases.append(["id": "hopProgress", "elapsedBits": GoldenCompact.bits(hops),
                      "valuesBits": GoldenCompact.bits(hops.map { e in
                          CrossyGame.Hop(fromRow: 0, fromX: 4, toRow: 1, toX: 4, toFloats: false, elapsed: e, direction: .forward,
                                         bumped: false, fromRiding: false).progress
                      })])
        goldenEmit(GoldenFile(
            golden: "crossy/rules",
            equivalence: .bit,
            swiftSources: [Self.engine, Self.kinds],
            spec: [
                "lane text": "row|kind|props(칸마다 . 없음 · r 바위 · 0~2 나무 높이)|direction|speed 비트|movers(x비트:길이비트:variant:트럭 1/0 을 ; 로)|train(- 또는 x비트:길이비트)|trainCountdown 비트|trainRandom 상태 0x",
                "overlaps": "Mover.overlaps(center:halfWidth:grace:) — 물체 × 폭 × 중심 행 우선, 불은 0/1",
                "lanes": "isBlocked(column: −2…10) · velocity · log(under:) 가 고른 통나무 순번(없으면 −1) · isTrainWarning",
                "hopProgress": "Hop.progress = min(1, max(0, elapsed / hopSeconds))",
            ],
            cases: cases
        ))
    }

    // MARK: - crossy/lanes (G2)

    static let laneSeeds: [(String, UInt64)] = [
        ("zero", 0), ("one", 1), ("answer", 42), ("deadbeef", 0xDEAD_BEEF), ("int63-max", 0x7FFF_FFFF_FFFF_FFFF),
        ("uint64-max", .max), ("pattern", 0x0123_4567_89AB_CDEF), ("server", 2_147_483_647),
    ]

    @Test("crossy/lanes — 시드 여덟 × 새 판에서 이어 만든 줄 −5…320 · 둘째 판 시드 줄")
    func lanes() {
        var cases: [GoldenJSON] = []
        var kindsSeen = Set<String>()
        for (id, seed) in Self.laneSeeds {
            let game = CrossyGame(seed: seed)
            let preview = game.previewLanes(through: 320)
            #expect(game.lanes.count < preview.count, "\(id): 미리보기가 판을 바꿨거나 더 만들지 않았다")
            preview.forEach { kindsSeen.insert($0.kind.rawValue) }
            // 둘째 판: 시작 → 끊기 → 다시(새 시드 줄기) — 첫 판과 다른 길이어야 한다.
            var second = CrossyGame(seed: seed)
            second.startForTesting()
            second.interrupt()
            second.action()
            let secondPreview = second.previewLanes(through: 60)
            cases.append([
                "id": .string(id), "seed": .hex64(seed), "roundSeed": .hex64(game.roundSeed),
                "heldFirstRow": .int(game.lanes.first?.row ?? 0), "heldLastRow": .int(game.lanes.last?.row ?? 0),
                "lanes": .string(preview.map(Self.laneText).joined(separator: "\n")),
                "secondRoundSeed": .hex64(second.roundSeed),
                "secondLanes": .string(secondPreview.map(Self.laneText).joined(separator: "\n")),
            ])
        }
        #expect(kindsSeen == ["grass", "road", "river", "rail"], "시드 줄이 네 종류를 다 내지 않았다: \(kindsSeen.sorted())")
        goldenEmit(GoldenFile(
            golden: "crossy/lanes",
            equivalence: .bit,
            swiftSources: [Self.engine, Self.kinds],
            spec: [
                "lanes": "CrossyGame(seed).previewLanes(through: 320) 의 줄 글자(crossy/rules 의 lane text)를 줄바꿈으로 — 들고 있는 줄(−5…24) + 이어 만든 줄",
                "second": "같은 시드로 startForTesting() → interrupt() → action()(결과 화면에서 새 판 = seedSource.next() 로 새 길 + 앞으로 한 칸) 뒤 previewLanes(through: 60)",
                "held": "새 판이 처음 들고 있는 줄 범위(첫 줄 · 끝 줄)",
            ],
            cases: cases
        ))
    }

    // MARK: - crossy/scripted (G3)

    static func ordinal(_ d: CrossyGame.Direction) -> Int { CrossyGame.Direction.allCases.firstIndex(of: d)! }

    static func fold(_ g: CrossyGame, into h: inout GoldenDualFold) {
        switch g.phase {
        case .ready: h.add(0)
        case .running: h.add(1)
        case .over(let hold): h.add(2); h.add(hold)
        case .result: h.add(3)
        }
        h.add(g.player.row); h.add(g.player.x); h.add(g.player.riding); h.add(ordinal(g.player.facing))
        if let hop = g.hop {
            h.add(1); h.add(hop.fromRow); h.add(hop.fromX); h.add(hop.toRow); h.add(hop.toX); h.add(hop.toFloats)
            h.add(hop.elapsed); h.add(ordinal(hop.direction)); h.add(hop.bumped); h.add(hop.fromRiding)
        } else {
            h.add(0)
        }
        h.add(g.queued.map(ordinal) ?? -1)
        h.add(g.score); h.add(g.cameraRow); h.add(g.sinceProgress)
        if let d = g.death {
            h.add(1); h.add(CrossyGame.DeathCause.allCases.firstIndex(of: d.cause)!); h.add(d.row); h.add(d.x); h.add(d.at)
            h.add(d.pushDirection)
        } else {
            h.add(0)
        }
        h.add(g.elapsed); h.add(g.hopCount); h.add(g.roundSeed)
        h.add(g.lanes.count)
        for l in g.lanes {
            h.add(l.row); h.add(CrossyGame.LaneKind.allCases.firstIndex(of: l.kind)!); h.add(l.direction); h.add(l.speed)
            h.add(l.movers.count)
            for m in l.movers { h.add(m.x); h.add(m.length); h.add(m.variant); h.add(m.isTruck) }
            if let t = l.train { h.add(1); h.add(t.x); h.add(t.length) } else { h.add(0) }
            h.add(l.trainCountdown); h.add(l.trainRandom.state)
            for p in l.props {
                switch p {
                case nil: h.add(-1)
                case .rock?: h.add(-2)
                case .tree(let height)?: h.add(height)
                }
            }
        }
    }

    static func apply(_ op: String, to g: inout CrossyGame) {
        switch op {
        case "F": g.input(.forward)
        case "B": g.input(.back)
        case "L": g.input(.left)
        case "R": g.input(.right)
        case "ACT": g.action()
        case "INT": g.interrupt()
        default: Issue.record("모르는 길건너 연산 \(op)")
        }
    }

    struct Script {
        var id: String
        var seed: UInt64
        var dts: [Double]
        var frames: Int
        var modeOffset: Int
    }

    static let scripts: [Script] = [
        Script(id: "A", seed: 1, dts: [1.0 / 60.0], frames: 60 * 150, modeOffset: 0),
        Script(id: "B", seed: 0xDEAD_BEEF, dts: [1.0 / 30.0], frames: 30 * 150, modeOffset: 1),
        Script(id: "C", seed: 42, dts: [0.016, 0.05, 0.008], frames: 9_000, modeOffset: 2),
        Script(id: "D", seed: 0, dts: [1.0 / 144.0], frames: 144 * 50, modeOffset: 3),
        Script(id: "E", seed: .max, dts: [1.0 / 60.0], frames: 60 * 120, modeOffset: 4),
    ]

    /// 조종사(Swift 몫만 — Kotlin 은 연산만 재생한다). 판마다 버릇을 바꾼다:
    /// 0 똑똑이(앞을 보고 안전할 때만) · 1 막무가내 앞으로(차·강·기차) · 2 통나무에 타고 멈춤(떠내려감) · 3 가만히(놓침) ·
    /// 4 벽·나무 들이받기(막힌 칸 통통 · 뒤 숲) 뒤 똑똑이.
    static func pilot(_ s: Script) -> [[String]] {
        var g = CrossyGame(seed: s.seed)
        var frames: [[String]] = []
        var round = 0
        var picker = MiniGameRandom(seed: s.seed ^ 0xC205_5000)
        var bumpPlan = ["L", "L", "L", "L", "L", "L", "B", "B", "B", "B", "R", "F", "F"]
        var idleSince = 0
        for frame in 1...s.frames {
            let dt = s.dts[(frame - 1) % s.dts.count]
            var ops: [String] = []
            let mode = (round + s.modeOffset) % 5
            switch g.phase {
            case .ready:
                ops.append(mode == 4 ? "L" : "ACT")
            case .result:
                if frame % 20 == 0 {
                    round += 1
                    bumpPlan = ["L", "L", "L", "L", "L", "L", "B", "B", "B", "B", "R", "F", "F"]
                    ops.append("ACT")
                } else if frame % 7 == 0 {
                    ops.append("F")              // 결과 화면의 방향키는 무시돼야 한다
                }
            case .over:
                if frame % 5 == 0 { ops.append("F") }   // 죽음 연출 중 입력도 무시
            case .running:
                if frame == s.frames / 2 { ops.append("INT"); break }
                switch mode {
                case 1:
                    // 기찻길 앞까지는 똑똑이, 앞 줄이 기찻길이면 기차에 맞는 순간을 골라 뛴다(기차 죽음). 그 전엔 가끔 연타(줄 서기·버림).
                    if g.hop == nil, let ahead = g.lane(at: g.player.row + 1), ahead.kind == .rail {
                        if Self.leadsTo(g, op: "F", cause: .train, dt: dt) { ops.append("F") }
                    } else if g.hop == nil, let choice = smartChoice(g, picker: &picker, dt: dt, aggressive: false) {
                        ops.append(choice)
                    }
                    if frame % 11 == 0, g.hop != nil { ops.append("F"); ops.append("L") }      // 줄 선 입력 하나 + 버려지는 하나
                case 2:
                    if let lane = g.lane(at: g.player.row), lane.kind == .river, g.player.riding {
                        idleSince += 1                  // 타고 멈춘다
                    } else if g.hop == nil {
                        ops.append(smartChoice(g, picker: &picker, dt: dt, aggressive: true) ?? "F")
                    }
                case 3:
                    if g.score < 3, g.hop == nil { ops.append("F") }
                case 4:
                    if !bumpPlan.isEmpty, g.hop == nil {
                        ops.append(bumpPlan.removeFirst())
                    } else if g.hop == nil, let choice = smartChoice(g, picker: &picker, dt: dt, aggressive: false) {
                        ops.append(choice)
                    }
                default:
                    if g.hop == nil, let choice = smartChoice(g, picker: &picker, dt: dt, aggressive: false) {
                        ops.append(choice)
                        if picker.next() % 9 == 0 { ops.append(choice) }      // 뛰는 중 줄 서기(같은 프레임)
                    }
                }
            }
            for op in ops { apply(op, to: &g) }
            g.step(dt: dt)
            frames.append(ops)
        }
        _ = idleSince
        return frames
    }

    /// 그 입력 뒤 0.8초 안에 그 사유로 죽는가(기차 죽음 고르기).
    static func leadsTo(_ g: CrossyGame, op: String, cause: CrossyGame.DeathCause, dt: Double) -> Bool {
        var probe = g
        apply(op, to: &probe)
        var t = 0.0
        while t < 0.8 {
            probe.step(dt: dt)
            t += dt
            if let d = probe.death { return d.cause == cause }
        }
        return false
    }

    /// 한 수 앞보기: 그 입력 뒤 잠깐(뛰기 + 여유) 서 있어도 사는가. 앞 → 가만히 → 옆 → 뒤 순서.
    static func smartChoice(_ g: CrossyGame, picker: inout MiniGameRandom, dt: Double, aggressive: Bool) -> String? {
        func survives(_ op: String?, _ horizon: Double) -> Bool {
            var probe = g
            if let op { apply(op, to: &probe) }
            var t = 0.0
            while t < horizon {
                probe.step(dt: dt)
                t += min(dt, CrossyGame.maxStep)
                if case .over = probe.phase { return false }
            }
            return true
        }
        if survives("F", CrossyGame.hopSeconds + 0.35) { return "F" }
        if !aggressive, g.sinceProgress < 6, survives(nil, 0.3) { return nil }
        let sides = picker.next() % 2 == 0 ? ["L", "R"] : ["R", "L"]
        for op in sides where survives(op, CrossyGame.hopSeconds + 0.3) { return op }
        if survives("B", CrossyGame.hopSeconds + 0.3) { return "B" }
        return aggressive ? "F" : nil
    }

    @Test("crossy/scripted — 대본 다섯(죽음 다섯 갈래 · 막힌 칸 · 줄 세우기 · 점수 단조 · 끊기 · 다시 하기)")
    func scripted() {
        var cases: [GoldenJSON] = []
        var causes = Set<String>()
        var bumps = 0
        var droppedInputs = 0
        var backHopsAfterProgress = 0
        for s in Self.scripts {
            let rle = GoldenOpsRLE.encode(Self.pilot(s))
            var g = CrossyGame(seed: s.seed)
            var h = GoldenDualFold()
            Self.fold(g, into: &h)
            var checkpoints: [UInt64] = []
            var bytes = GoldenFrameBytes()
            var deaths: [String] = []
            var frame = 0
            var lastScore = 0
            for ops in GoldenOpsRLE.decode(rle) {
                frame += 1
                let dt = s.dts[(frame - 1) % s.dts.count]
                h.beginFrame()
                let hadDeath = g.death != nil
                let seedBefore = g.roundSeed
                for op in ops {
                    let queuedBefore = g.queued
                    let hopping = g.hop != nil
                    Self.apply(op, to: &g)
                    if hopping, queuedBefore != nil, ["F", "B", "L", "R"].contains(op), case .running = g.phase { droppedInputs += 1 }
                    if let hop = g.hop, hop.bumped, hop.elapsed == 0 { bumps += 1 }
                    if op == "B", g.score > 0 { backHopsAfterProgress += 1 }
                }
                g.step(dt: dt)
                if case .running = g.phase, seedBefore == g.roundSeed {
                    #expect(g.score >= lastScore, "\(s.id) 프레임 \(frame): 점수가 줄었다")
                }
                lastScore = g.score
                if !hadDeath, let d = g.death {
                    causes.insert(d.cause.rawValue)
                    deaths.append("\(frame):\(d.cause.rawValue)")
                }
                Self.fold(g, into: &h)
                bytes.append(h.frame.value)
                if frame % Self.checkpointEvery == 0 { checkpoints.append(h.total.value) }
            }
            cases.append([
                "id": .string(s.id), "seed": .hex64(s.seed), "dtCycleBits": GoldenCompact.bits(s.dts), "ops": .string(rle),
                "checkpointEvery": .int(Self.checkpointEvery),
                "checkpoints": .string(checkpoints.map(GoldenBits.hex64).joined(separator: " ")),
                "frameBytes": .string(bytes.text),
                "deaths": .string(deaths.joined(separator: " ")),
                "final": [
                    "hash": .hex64(h.total.value), "frames": .int(frame), "score": .int(g.score), "hopCount": .int(g.hopCount),
                    "roundSeed": .hex64(g.roundSeed), "elapsedBits": .bits(g.elapsed), "cameraRowBits": .bits(g.cameraRow),
                    "player": .string("\(g.player.row)|\(GoldenBits.bits(g.player.x))|\(g.player.riding ? 1 : 0)|\(g.player.facing.rawValue)"),
                    "lanes": .string(g.lanes.map(Self.laneText).joined(separator: "\n")),
                ],
            ])
        }
        #expect(causes == Set(CrossyGame.DeathCause.allCases.map(\.rawValue)), "대본이 죽음 다섯 갈래를 다 거치지 않았다: \(causes.sorted())")
        #expect(bumps > 0, "막힌 칸 통통이 한 번도 없었다")
        #expect(droppedInputs > 0, "줄 선 뒤 버려진 입력이 한 번도 없었다")
        #expect(backHopsAfterProgress > 0, "앞으로 간 뒤 뒤로 뛴 적이 없다(점수 단조를 못 잰다)")
        goldenEmit(GoldenFile(
            golden: "crossy/scripted",
            equivalence: .bit,
            swiftSources: [Self.engine, Self.kinds],
            spec: [
                "frame": "CrossyGame(seed) → 처음 접기 → 프레임 f(1부터): dt = dtCycle[(f−1) % 길이], 연산을 적힌 순서대로(F B L R = input(forward·back·left·right) · ACT = action() · INT = interrupt()) → step(dt) → 접기",
                "fold": "phase(ready 0 · running 1 · over 2+유예 · result 3) · player row·x·riding·facing 순번(forward 0 back 1 left 2 right 3) · hop(없으면 0, 있으면 1 · fromRow · fromX · toRow · toX · toFloats · elapsed · direction 순번 · bumped · fromRiding) · queued(없으면 −1) · score · cameraRow · sinceProgress · death(없으면 0, 있으면 1 · cause 순번(car water carriedOff train leftBehind) · row · x · at · pushDirection) · elapsed · hopCount · roundSeed · 줄 수 · 줄마다 row · kind 순번(grass road river rail) · direction · speed · 물체 수 · 물체마다 x·length·variant·isTruck · train(0 또는 1·x·length) · trainCountdown · trainRandom 상태 · 칸마다 prop(없음 −1 · 바위 −2 · 나무 높이)",
                "deaths": "\"프레임:사유\" — 죽음이 생긴 프레임",
                "final.lanes": "끝 판이 들고 있는 줄 글자(crossy/rules 의 lane text)",
            ],
            cases: cases
        ))
    }
}
