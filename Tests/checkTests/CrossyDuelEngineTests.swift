import Foundation
import SceneKit
import Testing
@testable import CheckCore

// 길건너 아잉이 1:1 — 엔진(갈래 E). 설계서 crossy-duel/SPEC.md §2 · §7 · §10.2 E 줄.
//
// 픽스처 두 장(Tests/checkTests/Fixtures/crossy-duel/)은 **갈래 시작 커밋(3d5f1f19)의 엔진으로** 떴다(SPEC §2 v1.1):
//   · lanes-golden.json  — 씨앗 셋의 줄 −8…124 모양·물체 비트열. 머리 `laneGeneratorVersion` 이 엔진 상수와 같아야 한다.
//     **줄 생성(CrossyGame.swift `makeLane` 아래)·난이도를 바꾸는 커밋은 `CrossyGame.laneGeneratorVersion` 을 올리고,
//     같은 출시에 서버 `crossy_duel_min_build()` 를 그 build 로 올리는 한 줄 파일을 짝으로 낸다**(옛 앱에 신청이 안 가게).
//     버전을 올렸으면 픽스처를 다시 뜬다: `CROSSY_DUEL_RECORD_FIXTURES=lanes swift test --filter CrossyDuelEngine`.
//   · solo-baseline.json — 혼자 하기(`.solo`) 판의 투영 해시열(봇 판 셋 + 대본 판). 1:1 을 덧붙여도 혼자 하기가 한 비트도
//     안 바뀌었음을 결과로 잰다(SPEC §7.3, CC-9). 혼자 하기를 **일부러** 바꿀 때만 `=solo` 로 다시 뜬다.
// 창은 띄우지 않는다.

private typealias CE = CrossyGame

// MARK: - 투영(비트 단위 — 고정 dt 라 결정적)

private func ceBits(_ value: Double) -> String { String(value.bitPattern, radix: 16) }

private func cePhase(_ phase: CE.Phase) -> String {
    switch phase {
    case .ready: "ready"
    case .running: "running"
    case .over(let hold): "over(\(ceBits(hold)))"
    case .result: "result"
    }
}

private func ceProps(_ lane: CE.Lane) -> [String] {
    lane.props.map { prop -> String in
        switch prop {
        case .none: "."
        case .tree(let h)?: "t\(h)"
        case .rock?: "r"
        }
    }
}

private func ceMover(_ m: CE.Mover) -> String {
    "\(ceBits(m.x))/\(ceBits(m.length))/\(m.variant)/\(m.isTruck ? 1 : 0)"
}

/// 줄 하나의 **지금** 모양(물체 x · 기차 · 기차 시계 · 기차 난수 상태까지).
private func ceLaneProjection(_ lane: CE.Lane) -> String {
    let movers = lane.movers.map(ceMover).joined(separator: ",")
    let train = lane.train.map(ceMover) ?? "-"
    return "\(lane.row):\(lane.kind.rawValue):\(ceProps(lane).joined()):\(lane.direction):\(ceBits(lane.speed))"
        + ":[\(movers)]:\(train):\(ceBits(lane.trainCountdown)):\(String(lane.trainRandom.state, radix: 16))"
}

/// 판 전체 투영 — 혼자 하기 무변경 비교의 단위. **갈래 시작 커밋의 엔진에 있던 칸만** 쓴다(새 칸은 기준선에 없다).
private func ceProjection(_ g: CE) -> String {
    var parts: [String] = []
    parts.append("phase=\(cePhase(g.phase))")
    parts.append("score=\(g.score) elapsed=\(ceBits(g.elapsed)) hops=\(g.hopCount) seed=\(String(g.roundSeed, radix: 16))")
    parts.append("player=\(g.player.row),\(ceBits(g.player.x)),\(g.player.riding ? 1 : 0),\(g.player.facing.rawValue)")
    if let hop = g.hop {
        parts.append("hop=\(hop.fromRow),\(ceBits(hop.fromX))>\(hop.toRow),\(ceBits(hop.toX)),\(hop.toFloats ? 1 : 0),"
                     + "\(ceBits(hop.elapsed)),\(hop.direction.rawValue),\(hop.bumped ? 1 : 0),\(hop.fromRiding ? 1 : 0)")
    } else {
        parts.append("hop=-")
    }
    parts.append("queued=\(g.queued?.rawValue ?? "-")")
    parts.append("camera=\(ceBits(g.cameraRow)) since=\(ceBits(g.sinceProgress))")
    if let d = g.death {
        parts.append("death=\(d.cause.rawValue),\(d.row),\(ceBits(d.x)),\(ceBits(d.at)),\(d.pushDirection)")
    } else {
        parts.append("death=-")
    }
    parts.append("lanes=" + g.lanes.map(ceLaneProjection).joined(separator: ";"))
    return parts.joined(separator: " ")
}

/// FNV-1a 64.
private func ceHash(_ text: String) -> String {
    var h: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in text.utf8 {
        h ^= UInt64(byte)
        h = h &* 0x0000_0100_0000_01B3
    }
    return String(h, radix: 16)
}

private func ceSummary(_ g: CE) -> String {
    String(format: "%@ s%d r%d x%.3f cam%.3f t%.3f", cePhase(g.phase), g.score, g.player.row, g.player.x, g.cameraRow, g.elapsed)
}

// MARK: - 줄 픽스처(엔진 시험 문만 쓴다)

private func ceGrass(_ row: Int, blocked: [Int] = []) -> CE.Lane {
    var props = [CE.Prop?](repeating: nil, count: CE.columns)
    for c in blocked { props[c] = .tree(height: 1) }
    return CE.Lane(row: row, kind: .grass, props: props)
}

private func ceRoad(_ row: Int, direction: Int = 1, speed: Double = 2, cars: [Double], truck: Bool = false) -> CE.Lane {
    let length = truck ? CE.truckLength : CE.carLength
    return CE.Lane(row: row, kind: .road, direction: direction, speed: speed,
                   movers: cars.map { CE.Mover(x: $0, length: length, isTruck: truck) })
}

private func ceRiver(_ row: Int, direction: Int = 1, speed: Double = 1, logs: [(x: Double, length: Double)]) -> CE.Lane {
    CE.Lane(row: row, kind: .river, direction: direction, speed: speed,
            movers: logs.map { CE.Mover(x: $0.x, length: $0.length) })
}

private func ceRail(_ row: Int, direction: Int = 1, countdown: Double) -> CE.Lane {
    CE.Lane(row: row, kind: .rail, direction: direction, speed: CE.trainSpeed, trainCountdown: countdown)
}

/// 진행 중 판 — 줄 −2…14 를 빈 풀밭으로 덮고 `lanes` 를 얹는다.
private func ceBoard(_ base: CE, lanes: [CE.Lane] = []) -> CE {
    var game = base
    game.startForTesting()
    for row in -2...14 { game.replaceLane(ceGrass(row)) }
    for lane in lanes { game.replaceLane(lane) }
    return game
}

/// 살아남으려는 봇(V0367 `cgBotStep` 과 같은 규칙) — 뛰기 전에 사본으로 0.5초를 미리 돌려 보고 산 쪽을 고른다.
private func ceBotStep(_ game: inout CE, dt: Double = 1.0 / 60) {
    func survives(_ probe: CE) -> Bool {
        var copy = probe
        for _ in 0..<30 {
            copy.step(dt: 1.0 / 60)
            if copy.death != nil { return false }
        }
        return true
    }
    func tryHop(_ direction: CE.Direction) -> Bool {
        var probe = game
        probe.input(direction)
        guard probe.hop?.bumped != true, survives(probe) else { return false }
        game.input(direction)
        return true
    }
    if game.phase == .running, game.hop == nil, game.queued == nil {
        var forward = game
        forward.input(.forward)
        let blocked = forward.hop?.bumped == true
        if !blocked, survives(forward) {
            game.input(.forward)
        } else if blocked {
            let here = Int(game.player.x.rounded())
            let next = game.lane(at: game.player.row + 1)
            let open = (0..<CE.columns).filter { !(next?.isBlocked(column: $0) ?? true) }
            let target = open.min { abs($0 - here) < abs($1 - here) } ?? here
            let side: [CE.Direction] = target < here ? [.left, .right] : [.right, .left]
            if !survives(game) || !side.contains(where: { tryHop($0) }) { _ = tryHop(.back) }
        } else if !survives(game) {
            _ = [CE.Direction.left, .right, .back].first { tryHop($0) }
        }
    }
    game.step(dt: dt)
}

// MARK: - 혼자 하기 기준선 대본

private enum CEScript {
    case action
    case input(CE.Direction)
}

/// 기준선 판 하나 — 처음 판(`make`) · 걸음 수(1/60초) · 몇 걸음마다 투영을 적는가 · 걸음마다 무엇을 하는가.
private struct CEScenario {
    let name: String
    let make: (_ factory: (UInt64) -> CE) -> CE
    let steps: Int
    let sampleEvery: Int
    /// 그 걸음 **앞**에 넣을 입력(대본). nil 이면 봇이 민다.
    let script: [Int: [CEScript]]?
    /// 대본 판에서 봇으로 넘어가는 걸음(그 걸음부터 봇).
    let botFrom: Int?
}

private let ceDt = 1.0 / 60

private func ceScenarios() -> [CEScenario] {
    var list: [CEScenario] = []
    // 봇 판 셋(SPEC §7.3 — 씨앗 2026 · 2027 · 314). 실제 줄 위에서 20초.
    for seed in [UInt64(2026), 2027, 314] {
        list.append(CEScenario(name: "bot-\(seed)", make: { factory in
            var g = factory(seed)
            g.action()
            return g
        }, steps: 20 * 60, sampleEvery: 15, script: nil, botFrom: 0))
    }
    // 대본 판: 일부러 차에 죽음 → 1.1초 뒤 결과 → action() 으로 둘째 판(씨앗 줄기 둘째 값) → 봇 5초(CC-9).
    list.append(CEScenario(name: "script-car-then-second-round", make: { factory in
        var g = ceBoard(factory(2026), lanes: [ceRoad(1, direction: 1, speed: 2.5, cars: [0.4]),
                                               ceRoad(2, direction: -1, speed: 2, cars: [7, 1.5])])
        g.placePlayerForTesting(row: 1, x: 4)
        return g
    }, steps: 8 * 60, sampleEvery: 6, script: [150: [.input(.forward)], 151: [.action]], botFrom: 152))
    // 대본 판: 아무것도 안 함 → 카메라 혼자 가기 + 9초 정체 → 놓침(creep · leftBehind 경로).
    list.append(CEScenario(name: "script-idle-left-behind", make: { factory in
        var g = factory(314)
        g.action()
        return g
    }, steps: 12 * 60, sampleEvery: 15, script: [:], botFrom: nil))
    // 대본 판: 앞으로 여섯 칸 → 뒤로 → 카메라 −2.5줄 넘게 처져 놓침.
    var backScript: [Int: [CEScript]] = [:]
    for i in 0..<6 { backScript[1 + i * 10] = [.input(.forward)] }
    for i in 0..<6 { backScript[150 + i * 10] = [.input(.back)] }
    list.append(CEScenario(name: "script-back-left-behind", make: { factory in ceBoard(factory(77)) },
                           steps: 5 * 60, sampleEvery: 5, script: backScript, botFrom: nil))
    // 대본 판: 물 · 기차 · 실려 나감 죽음(죽음 연출 `.over` 가지 → 결과).
    list.append(CEScenario(name: "script-water", make: { factory in
        var g = ceBoard(factory(7), lanes: [ceRiver(1, direction: 1, speed: 0.6, logs: [(x: -3, length: 3), (x: 6.5, length: 3)]),
                                            ceRiver(2, direction: -1, speed: 0.8, logs: [(x: 1, length: 4)])])
        g.input(.forward)
        return g
    }, steps: 2 * 60, sampleEvery: 3, script: [:], botFrom: nil))
    list.append(CEScenario(name: "script-train", make: { factory in
        var g = ceBoard(factory(7), lanes: [ceRail(1, direction: 1, countdown: 0.2), ceGrass(2, blocked: [1, 7])])
        g.placePlayerForTesting(row: 1, x: 4)
        return g
    }, steps: 2 * 60, sampleEvery: 3, script: [:], botFrom: nil))
    list.append(CEScenario(name: "script-carried-off", make: { factory in
        var g = ceBoard(factory(7), lanes: [ceRiver(1, direction: 1, speed: 2.5, logs: [(x: 6.0, length: 4)]),
                                            ceRiver(2, direction: -1, speed: 0.8, logs: [(x: 1, length: 4)])])
        g.placePlayerForTesting(row: 1, x: 7.6, riding: true)
        return g
    }, steps: 2 * 60, sampleEvery: 3, script: [:], botFrom: nil))
    return list
}

private struct CESample: Codable, Equatable {
    var step: Int
    var summary: String
    var hash: String
}

private struct CEScenarioRecord: Codable, Equatable {
    var name: String
    var samples: [CESample]
    var final: String
}

private func ceRun(_ scenario: CEScenario, factory: (UInt64) -> CE) -> CEScenarioRecord {
    var game = scenario.make(factory)
    var samples: [CESample] = [CESample(step: 0, summary: ceSummary(game), hash: ceHash(ceProjection(game)))]
    for index in 0..<scenario.steps {
        if let botFrom = scenario.botFrom, index >= botFrom {
            ceBotStep(&game, dt: ceDt)
        } else {
            for command in scenario.script?[index] ?? [] {
                switch command {
                case .action: game.action()
                case .input(let d): game.input(d)
                }
            }
            game.step(dt: ceDt)
        }
        if (index + 1) % scenario.sampleEvery == 0 {
            samples.append(CESample(step: index + 1, summary: ceSummary(game), hash: ceHash(ceProjection(game))))
        }
    }
    return CEScenarioRecord(name: scenario.name, samples: samples, final: ceProjection(game))
}

private struct CESoloBaselineFile: Codable {
    var source: String
    var note: String
    var dt: String
    var scenarios: [CEScenarioRecord]
}

// MARK: - 금빛 줄 픽스처

private struct CEGoldenMover: Codable, Equatable {
    var x: Double
    var xBits: String
    var length: Double
    var lengthBits: String
    var variant: Int
    var isTruck: Bool
}

private struct CEGoldenLane: Codable, Equatable {
    var row: Int
    var kind: String
    var props: [String]
    var direction: Int
    var speed: Double
    var speedBits: String
    var movers: [CEGoldenMover]
    var trainCountdown: Double
    var trainCountdownBits: String
    var trainSeed: String
}

private struct CEGoldenSeed: Codable, Equatable {
    var seed: UInt64
    var roundSeed: String
    var lanes: [CEGoldenLane]
}

private struct CEGoldenFile: Codable {
    var laneGeneratorVersion: Int
    var source: String
    var note: String
    var rows: [Int]
    var seeds: [CEGoldenSeed]
}

/// 금빛 픽스처의 씨앗 — 0 · 보통 값 · 서버 씨앗 최댓값(2³¹−1, SPEC §2).
private let ceGoldenSeeds: [UInt64] = [0, 2026, 2_147_483_647]
private let ceGoldenThrough = 124

private func ceGolden(seed: UInt64, rules: CE.Rules = .solo) -> CEGoldenSeed {
    let game = CE(seed: seed, rules: rules)
    let lanes = game.previewLanes(through: ceGoldenThrough).filter { $0.row >= -8 && $0.row <= ceGoldenThrough }
    return CEGoldenSeed(seed: seed, roundSeed: String(game.roundSeed, radix: 16), lanes: lanes.map { lane in
        CEGoldenLane(row: lane.row, kind: lane.kind.rawValue, props: ceProps(lane), direction: lane.direction,
                     speed: lane.speed, speedBits: ceBits(lane.speed),
                     movers: lane.movers.map {
                         CEGoldenMover(x: $0.x, xBits: ceBits($0.x), length: $0.length, lengthBits: ceBits($0.length),
                                       variant: $0.variant, isTruck: $0.isTruck)
                     },
                     trainCountdown: lane.trainCountdown, trainCountdownBits: ceBits(lane.trainCountdown),
                     trainSeed: String(lane.trainRandom.state, radix: 16))
    })
}

// MARK: - 픽스처 읽기 · 쓰기

private let ceFixtureDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/crossy-duel", isDirectory: true)

private func ceRecordMode() -> Set<String> {
    let raw = ProcessInfo.processInfo.environment["CROSSY_DUEL_RECORD_FIXTURES"] ?? ""
    let names = Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    return names.contains("all") ? ["lanes", "solo"] : names
}

private func ceFixtureSource() -> String {
    let commit = ProcessInfo.processInfo.environment["CROSSY_DUEL_FIXTURE_COMMIT"] ?? "unknown"
    return "Sources/CheckCore/CrossyGame.swift @ \(commit)"
}

/// 한 줄에 한 항목인 JSON(차이를 읽기 쉽게) — 항목은 키 정렬 JSONEncoder.
private func ceLineJSON<Head: Encodable, Item: Encodable>(head: Head, listKey: String, items: [Item]) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var headText = String(decoding: try encoder.encode(head), as: UTF8.self)
    // 머리 객체의 닫는 괄호 앞에 목록을 끼운다.
    precondition(headText.hasSuffix("}"))
    headText.removeLast()
    let body = try items.map { String(decoding: try encoder.encode($0), as: UTF8.self) }.joined(separator: ",\n")
    return headText + ",\"\(listKey)\":[\n" + body + "\n]}\n"
}

private struct CEGoldenHead: Encodable {
    var laneGeneratorVersion: Int
    var source: String
    var note: String
    var rows: [Int]
}

private struct CESoloHead: Encodable {
    var source: String
    var note: String
    var dt: String
}

// MARK: - 시험

@Suite("길건너 1:1 엔진 — 픽스처(갈래 시작 커밋의 엔진으로 뜬 기준선)")
struct CrossyDuelEngineFixtureTests {
    @Test("픽스처 뜨기(CROSSY_DUEL_RECORD_FIXTURES=lanes|solo|all 일 때만 쓴다 — 평소엔 아무것도 안 한다)")
    func recordFixturesWhenAsked() throws {
        let mode = ceRecordMode()
        guard !mode.isEmpty else { return }
        try FileManager.default.createDirectory(at: ceFixtureDir, withIntermediateDirectories: true)
        if mode.contains("lanes") {
            let head = CEGoldenHead(
                laneGeneratorVersion: 1,
                source: ceFixtureSource(),
                note: "CrossyGame(seed:).previewLanes(through: 124) 의 줄 −8…124. 실수는 IEEE 754 비트(16진)와 같은 값의 십진. "
                    + "trainSeed = 줄이 태어날 때 기차 난수 상태. 이식판(안드로이드·윈도우)은 비트 단위로 같아야 한다.",
                rows: [-8, ceGoldenThrough])
            let text = try ceLineJSON(head: head, listKey: "seeds", items: ceGoldenSeeds.map { ceGolden(seed: $0) })
            try text.write(to: ceFixtureDir.appendingPathComponent("lanes-golden.json"), atomically: true, encoding: .utf8)
        }
        if mode.contains("solo") {
            let head = CESoloHead(
                source: ceFixtureSource(),
                note: "혼자 하기(.solo) 판의 투영 해시열 — 투영 = phase · score · elapsed · player · hop · queued · cameraRow · "
                    + "sinceProgress · death · 줄 전부(물체 x · 기차 · trainCountdown · 기차 난수). 걸음 1/60초 고정.",
                dt: "1/60")
            let records = ceScenarios().map { ceRun($0, factory: { CE(seed: $0) }) }
            let text = try ceLineJSON(head: head, listKey: "scenarios", items: records)
            try text.write(to: ceFixtureDir.appendingPathComponent("solo-baseline.json"), atomically: true, encoding: .utf8)
        }
        print("[길건너 1:1] 픽스처를 다시 떴다: \(mode.sorted()) → \(ceFixtureDir.path)")
    }
}

// MARK: - 1:1 시험 도구

/// `seconds` 만큼 작은 걸음으로 흘린다(멈출 조건이 서면 그 자리에서).
@discardableResult
private func ceRunFor(_ game: inout CE, seconds: Double, dt: Double = 1.0 / 240,
                      until stop: (CE) -> Bool = { _ in false }) -> Bool {
    var t = 0.0
    while t < seconds - 1e-12 {
        let step = min(dt, seconds - t)
        game.step(dt: step)
        t += step
        if stop(game) { return true }
    }
    return false
}

private func ceShape(_ lane: CE.Lane) -> String {
    "\(lane.row):\(lane.kind.rawValue):\(ceProps(lane).joined()):\(lane.direction):\(ceBits(lane.speed)):\(lane.movers.map(\.length))"
}

private func ceIsOver(_ game: CE) -> Bool {
    if case .over = game.phase { return true }
    return false
}

private func ceHold(_ game: CE) -> Double? {
    if case .over(let hold) = game.phase { return hold }
    return nil
}

/// 칸마다 1초 안에 차가 지나가는 빠른 찻길(트랙 20칸에 차 셋 · 초당 12칸) — 1초 안전한 칸이 없다.
private func ceFastRoad(_ row: Int) -> CE.Lane {
    ceRoad(row, direction: 1, speed: 12, cars: [-5.5, 1.17, 7.83])
}

/// 1:1 판 — 줄 −2…14 를 빈 풀밭으로 덮고 `lanes` 를 얹는다.
private func ceDuelBoard(_ lanes: [CE.Lane] = [], seed: UInt64 = 7) -> CE {
    ceBoard(CE(seed: seed, rules: .duel), lanes: lanes)
}

/// 서 있는 그대로 `seconds` 안에 죽는가 — 죽은 시각(초, 지금부터) 또는 nil. 판은 안 바뀐다(사본).
private func ceDiesWithin(_ game: CE, seconds: Double) -> Double? {
    var copy = game
    var t = 0.0
    while t < seconds - 1e-9 {
        copy.step(dt: 1.0 / 120)
        t += 1.0 / 120
        if copy.death != nil { return t }
    }
    return nil
}

/// 빠른 찻길(1줄)에서 죽고 3초 뒤 다시 선 판 — 칸 고르기가 실패해 죽은 칸 + 보호 1초다.
private func ceShieldedOnFastRoad(extra: [CE.Lane] = []) -> CE {
    var game = ceDuelBoard([ceFastRoad(1)] + extra)
    game.placePlayerForTesting(row: 1, x: 4)
    ceRunFor(&game, seconds: 2) { $0.death != nil }
    ceRunFor(&game, seconds: 3.2) { $0.phase == .running }
    return game
}

// MARK: - 시험: 픽스처 대조

extension CrossyDuelEngineFixtureTests {
    @Test("금빛 줄 픽스처: 머리 laneGeneratorVersion = 엔진 상수 · 씨앗 셋 × 줄 −8…124 가 비트 단위로 같다 · 1:1 규칙도 같은 줄")
    func goldenLanesMatchBitForBit() throws {
        let data = try Data(contentsOf: ceFixtureDir.appendingPathComponent("lanes-golden.json"))
        let file = try JSONDecoder().decode(CEGoldenFile.self, from: data)
        #expect(file.laneGeneratorVersion == CE.laneGeneratorVersion,
                "줄 생성 버전(\(CE.laneGeneratorVersion))이 픽스처(\(file.laneGeneratorVersion))와 다르다 — 버전을 올렸으면 픽스처를 다시 뜨고, 같은 출시에 crossy_duel_min_build() 를 올려라")
        #expect(CE.laneGeneratorVersion == 1)
        #expect(file.rows == [-8, ceGoldenThrough])
        #expect(file.seeds.map(\.seed) == ceGoldenSeeds)
        var compared = 0
        for expected in file.seeds {
            for rules in [CE.Rules.solo, .duel] {
                let actual = ceGolden(seed: expected.seed, rules: rules)
                #expect(actual.roundSeed == expected.roundSeed, "씨앗 \(expected.seed): 줄 난수 씨앗이 다르다")
                #expect(actual.lanes.count == expected.lanes.count && actual.lanes.count == 133)
                if let bad = zip(actual.lanes, expected.lanes).first(where: { $0.0 != $0.1 }) {
                    Issue.record("씨앗 \(expected.seed)(\(rules == .duel ? "1:1" : "혼자")) \(bad.1.row) 줄이 픽스처와 다르다: \(bad.0) ≠ \(bad.1)")
                }
                compared += min(actual.lanes.count, expected.lanes.count)
            }
        }
        #expect(compared == 3 * 2 * 133)
        // 기준선: 다른 씨앗은 갈린다(비교가 헛돌지 않는다).
        #expect(ceGolden(seed: 1).lanes != file.seeds[0].lanes)
        let kinds = Set(file.seeds.flatMap { $0.lanes.map(\.kind) })
        #expect(kinds == ["grass", "road", "river", "rail"], "픽스처가 네 종류를 다 안 담았다(\(kinds))")
    }

    @Test("혼자 하기 무변경: .solo 봇 판 셋 + 대본 판 여섯의 투영 해시열이 갈래 시작 커밋 기준선과 같다 · 1:1 규칙이면 갈린다")
    func soloBaselineUnchanged() throws {
        let data = try Data(contentsOf: ceFixtureDir.appendingPathComponent("solo-baseline.json"))
        let file = try JSONDecoder().decode(CESoloBaselineFile.self, from: data)
        #expect(file.source.contains("3d5f1f19"), "기준선이 갈래 시작 커밋에서 뜬 것이 아니다(\(file.source))")
        let scenarios = ceScenarios()
        #expect(file.scenarios.map(\.name) == scenarios.map(\.name))
        var samples = 0
        let factories: [(String, (UInt64) -> CE)] = [("기본", { CE(seed: $0) }), (".solo", { CE(seed: $0, rules: .solo) })]
        for (scenario, expected) in zip(scenarios, file.scenarios) {
            for (label, factory) in factories {
                let actual = ceRun(scenario, factory: factory)
                #expect(actual.samples.count == expected.samples.count)
                if let bad = zip(actual.samples, expected.samples).first(where: { $0.0 != $0.1 }) {
                    Issue.record("\(scenario.name)(\(label)) 걸음 \(bad.1.step) 에서 갈렸다: \(bad.0.summary) ≠ 기준선 \(bad.1.summary)")
                }
                #expect(actual.final == expected.final, "\(scenario.name)(\(label)) 마지막 투영이 다르다")
                samples += actual.samples.count
            }
        }
        print("[길건너 1:1] 혼자 하기 기준선: 판 \(scenarios.count)개 · 투영 \(samples)개 비교")
        #expect(samples > 900)
        // 대본 판이 실제로 그 길을 지났다(죽음 다섯 사유 중 넷 · 둘째 판).
        let finals = Dictionary(uniqueKeysWithValues: file.scenarios.map { ($0.name, $0.final) })
        #expect(finals["script-water"]?.contains("death=water") == true)
        #expect(finals["script-train"]?.contains("death=train") == true)
        #expect(finals["script-carried-off"]?.contains("death=carriedOff") == true)
        #expect(finals["script-idle-left-behind"]?.contains("death=leftBehind") == true)
        #expect(finals["script-back-left-behind"]?.contains("death=leftBehind") == true)
        // 기준선: 같은 대본을 1:1 규칙으로 돌리면 갈린다(카메라 혼자 가기 · 놓침이 없다) — 비교가 규칙 차이를 본다.
        for name in ["script-idle-left-behind", "script-car-then-second-round"] {
            let scenario = try #require(scenarios.first { $0.name == name })
            let expected = try #require(file.scenarios.first { $0.name == name })
            let duel = ceRun(scenario, factory: { CE(seed: $0, rules: .duel) })
            #expect(duel.samples.map(\.hash) != expected.samples.map(\.hash), "\(name): 1:1 규칙인데 혼자 하기와 같다 — 투영이 헛돈다")
            #expect(!duel.final.contains("phase=result"), "\(name): 1:1 판이 결과로 끝났다")
        }
    }
}

// MARK: - 시험: 규칙

@Suite("길건너 1:1 엔진 — 규칙(목표 · 카메라 · 놓침 · 다시 하기)")
struct CrossyDuelEngineRulesTests {
    @Test("규칙 값 · 상수: .solo = nil·nil·켬·켬·켬 · .duel = 100·3초·끔·끔·끔 · 기본 init 은 .solo")
    func rulesAndConstants() {
        #expect(CE.Rules.solo == CE.Rules(goalScore: nil, respawnDelay: nil, cameraCreeps: true, leftBehindKills: true, allowsRestart: true))
        #expect(CE.Rules.duel == CE.Rules(goalScore: 100, respawnDelay: 3.0, cameraCreeps: false, leftBehindKills: false, allowsRestart: false))
        #expect(CE.respawnDelaySeconds == 3.0 && CE.respawnRoadSafeSeconds == 1.0 && CE.respawnShieldMaxSeconds == 2.5)
        #expect(CE.laneGeneratorVersion == 1)
        #expect(CE(seed: 7).rules == .solo)
        #expect(CE(seed: 7) == CE(seed: 7, rules: .solo), "기본 init 이 .solo 와 다른 판을 만든다")
        #expect(CE(seed: 7, rules: .duel).rules == .duel)
        let fresh = CE(seed: 7, rules: .duel)
        #expect(fresh.deaths == 0 && fresh.respawnShield == nil && fresh.phase == .ready)
    }

    @Test("begin(): .ready 에서만 첫 판을 연다(같은 씨앗 · 뛰지 않음 · 점수 0) — 진행 중 · 죽음 연출 · 결과에선 아무것도 안 한다")
    func beginOpensOnlyFromReady() {
        let ready = CE(seed: 2026, rules: .duel)
        var game = ready
        game.begin()
        #expect(game.phase == .running && game.score == 0 && game.hop == nil && game.player.row == 0)
        #expect(game.roundSeed == ready.roundSeed, "begin() 이 새 씨앗을 열었다")
        #expect(game.lanes.map(ceShape) == ready.lanes.map(ceShape), "begin() 이 길을 바꿨다")
        let running = game
        game.begin()
        #expect(game == running, "진행 중 begin() 이 판을 건드렸다")
        // 죽음 연출 중
        var over = ceDuelBoard([ceFastRoad(1)])
        over.placePlayerForTesting(row: 1, x: 4)
        ceRunFor(&over, seconds: 1) { $0.death != nil }
        #expect(ceIsOver(over))
        let overSnapshot = over
        over.begin()
        #expect(over == overSnapshot)
        // 기준선: 혼자 하기의 action() 은 .ready 에서 판을 열고 **뛴다** — begin 은 안 뛴다.
        var solo = CE(seed: 2026)
        solo.action()
        #expect(solo.hop != nil)
    }

    @Test("1:1 은 놓침이 없고 카메라가 혼자 안 간다 — 20초 서 있어도 산다(기준선: 혼자 하기는 9초 안팎에 놓침)")
    func noLeftBehindAndNoCreep() {
        var duel = ceDuelBoard()
        duel.input(.forward)
        ceRunFor(&duel, seconds: 20)
        #expect(duel.death == nil && duel.phase == .running && duel.deaths == 0, "1:1 에서 서 있다 죽었다(\(duel.death?.cause.rawValue ?? "-"))")
        #expect(duel.cameraRow <= 1.0 + 1e-9, "카메라가 혼자 갔다(\(duel.cameraRow))")
        #expect(duel.cameraRow > 0.99, "카메라가 아잉이를 안 따라왔다(\(duel.cameraRow))")

        var solo = ceBoard(CE(seed: 7))
        solo.input(.forward)
        ceRunFor(&solo, seconds: 20) { $0.death != nil }
        #expect(solo.death?.cause == .leftBehind, "기준선: 혼자 하기가 안 놓쳤다")
    }

    @Test("1:1 은 카메라보다 2.5줄 넘게 뒤로는 못 간다(제자리 통통 · 안 죽음) — 기준선: 혼자 하기는 놓침")
    func backHopsStopAtCameraMargin() {
        func climb(_ game: inout CE) {
            for _ in 0..<6 {
                game.input(.forward)
                ceRunFor(&game, seconds: CE.hopSeconds + 0.001)
            }
            ceRunFor(&game, seconds: 1.5)
        }
        var duel = ceDuelBoard()
        climb(&duel)
        #expect(duel.cameraRow > 5.5)
        var rows: [Int] = []
        var bumped = false
        for _ in 0..<6 {
            duel.input(.back)
            if duel.hop?.bumped == true { bumped = true }
            ceRunFor(&duel, seconds: CE.hopSeconds + 0.001)
            rows.append(duel.player.row)
        }
        #expect(bumped, "뒤로 막힘이 없다(\(rows))")
        #expect(duel.death == nil, "1:1 에서 뒤로 가다 죽었다")
        #expect(rows.allSatisfy { Double($0) >= duel.cameraRow - CE.behindRows }, "카메라 2.5줄 밖으로 나갔다(\(rows), 카메라 \(duel.cameraRow))")
        #expect(rows.first == 5 && rows.min() == 4, "뒤로 간 줄 \(rows)")

        var solo = ceBoard(CE(seed: 7))
        climb(&solo)
        for _ in 0..<6 where solo.death == nil {
            solo.input(.back)
            ceRunFor(&solo, seconds: CE.hopSeconds + 0.001) { $0.death != nil }
        }
        #expect(solo.death?.cause == .leftBehind, "기준선: 혼자 하기가 안 놓쳤다")
    }

    @Test("목표 100: 닿으면 .result · 그 뒤 클릭 · 방향키 · 걸음 무시(판이 한 비트도 안 바뀐다) — 기준선: 혼자 하기는 계속 간다")
    func goalEndsAndFreezes() {
        func atNinetyNine(_ rules: CE.Rules) -> CE {
            var game = CE(seed: 2026, rules: rules)
            game.restore(row: 99, score: 99, deaths: 2)
            game.replaceLane(ceGrass(99))
            game.replaceLane(ceGrass(100))
            game.placePlayerForTesting(row: 99, x: 4)
            return game
        }
        var duel = atNinetyNine(.duel)
        duel.input(.forward)
        ceRunFor(&duel, seconds: CE.hopSeconds + 0.01)
        #expect(duel.phase == .result && duel.score == 100 && duel.death == nil)
        #expect(duel.deaths == 2)
        let frozen = duel
        duel.action()
        duel.input(.forward)
        duel.input(.left)
        duel.step(dt: 1.0 / 30)
        duel.begin()
        #expect(duel == frozen, "끝난 1:1 판이 입력에 움직였다")

        var solo = atNinetyNine(.solo)
        solo.input(.forward)
        ceRunFor(&solo, seconds: CE.hopSeconds + 0.01)
        #expect(solo.phase == .running && solo.score == 100, "기준선: 혼자 하기가 100에서 멈췄다")
        solo.input(.forward)
        #expect(solo.hop != nil)
    }

    @Test("목표 100 은 같은 걸음의 충돌보다 앞 — 착지 순간 차가 겹쳐도 100 인정(기준선: 혼자 하기는 그 걸음에 치인다)")
    func goalBeatsLandingCollision() {
        func landing(_ rules: CE.Rules) -> CE {
            var game = CE(seed: 2026, rules: rules)
            game.restore(row: 99, score: 99, deaths: 0)
            game.replaceLane(ceGrass(99))
            // 앞 범퍼가 아잉이 몸(3.76)에 착지 걸음(8번째 1/60초)에 처음 닿는 차.
            game.replaceLane(ceRoad(100, direction: 1, speed: 2, cars: [2.11]))
            game.placePlayerForTesting(row: 99, x: 4)
            game.input(.forward)
            for _ in 0..<7 { game.step(dt: 1.0 / 60) }
            return game
        }
        var duel = landing(.duel)
        #expect(duel.death == nil && duel.hop != nil, "착지 전에 끝났다")
        duel.step(dt: 1.0 / 60)
        #expect(duel.phase == .result && duel.score == 100 && duel.death == nil, "착지 순간 겹친 차가 100 을 지웠다")

        var solo = landing(.solo)
        solo.step(dt: 1.0 / 60)
        #expect(solo.death?.cause == .car && solo.death?.row == 100, "기준선: 혼자 하기가 착지 걸음에 안 치였다 — 대본이 헛돈다")
    }

    @Test("둘째 판 씨앗: 혼자 하기는 죽음 → 1.1초 뒤 결과 → 클릭이 씨앗 줄기 둘째 값으로 새 판 · 1:1 은 결과로 안 가고 같은 씨앗으로 다시 선다")
    func secondRoundSeedOnlyInSolo() {
        var stream = CrossyRandom(seed: 2026)
        let first = stream.next()
        let second = stream.next()
        func dieOnRoad(_ rules: CE.Rules) -> CE {
            var game = ceBoard(CE(seed: 2026, rules: rules), lanes: [ceRoad(1, direction: 1, speed: 2.5, cars: [0.4])])
            game.placePlayerForTesting(row: 1, x: 4)
            ceRunFor(&game, seconds: 3) { $0.death != nil }
            return game
        }
        var solo = dieOnRoad(.solo)
        #expect(solo.roundSeed == first)
        ceRunFor(&solo, seconds: CE.deathHold + 0.02)
        #expect(solo.phase == .result)
        solo.action()
        #expect(solo.roundSeed == second && solo.score == 0 && solo.phase == .running, "둘째 판 씨앗이 줄기 둘째 값이 아니다")

        var duel = dieOnRoad(.duel)
        ceRunFor(&duel, seconds: CE.deathHold + 0.02)
        #expect(ceIsOver(duel), "1:1 이 1.1초에 결과로 갔다")
        ceRunFor(&duel, seconds: 2.0) { $0.phase == .running }
        #expect(duel.phase == .running && duel.roundSeed == first)
    }
}

// MARK: - 시험: 부활(안 R1)

@Suite("길건너 1:1 엔진 — 부활(3초 뒤 그 줄 · 칸 고르기 · 보호 · 강)")
struct CrossyDuelEngineRespawnTests {
    @Test("부활: 죽고 3.0초 뒤(2.99초엔 아직 .over) 죽은 줄에서 다시 · 점수 · 판 시계 · 씨앗 · 난수 그대로 · deaths +1 — 기준선: 혼자 하기는 1.1초에 결과")
    func respawnAfterThreeSecondsOnTheSameRow() throws {
        var game = ceDuelBoard([ceRoad(3, direction: 1, speed: 2.5, cars: [0.4])])
        for _ in 0..<2 {
            game.input(.forward)
            ceRunFor(&game, seconds: CE.hopSeconds + 0.001)
        }
        #expect(game.score == 2)
        game.placePlayerForTesting(row: 3, x: 4)
        let seed = game.roundSeed
        ceRunFor(&game, seconds: 2) { $0.death != nil }
        let death = try #require(game.death)
        #expect(death.cause == .car && death.row == 3 && game.deaths == 1)
        #expect(ceHold(game) == CE.respawnDelaySeconds, "죽음 연출 길이가 3초가 아니다(\(String(describing: ceHold(game))))")
        game.input(.forward)
        game.action()
        #expect(game.hop == nil, "죽음 연출 중 입력이 먹혔다")
        ceRunFor(&game, seconds: 2.99)
        #expect(ceIsOver(game) && game.death != nil, "2.99초에 벌써 다시 섰다")
        ceRunFor(&game, seconds: 0.05) { $0.phase == .running }
        #expect(game.phase == .running && game.death == nil)
        #expect(abs(game.elapsed - death.at - 3.0) <= 1.0 / 240 + 1e-9, "다시 선 시각이 죽고 \(game.elapsed - death.at)초")
        #expect(game.player.row == 3 && game.score == 2 && game.roundSeed == seed && game.deaths == 1)
        #expect(game.player.facing == .forward && !game.player.riding)
        // 난수 그대로 — 앞으로 만들 줄(15 줄부터 — 그 앞은 시험이 덮었다)이 새 판에서 미리 본 줄과 같다.
        let fresh = CE(seed: 7).previewLanes(through: 80).filter { $0.row >= 15 }.map(ceShape)
        let after = game.previewLanes(through: 80).filter { $0.row >= 15 }.map(ceShape)
        #expect(after == fresh && fresh.count == 66, "부활이 줄 난수를 건드렸다")

        var solo = ceBoard(CE(seed: 7), lanes: [ceRoad(3, direction: 1, speed: 2.5, cars: [0.4])])
        solo.placePlayerForTesting(row: 3, x: 4)
        ceRunFor(&solo, seconds: 2) { $0.death != nil }
        ceRunFor(&solo, seconds: CE.deathHold + 0.01)
        #expect(solo.phase == .result, "기준선: 혼자 하기가 결과로 안 갔다")
    }

    @Test("찻길: 1초 안전한 칸이 없으면 죽은 칸 + 보호 1초 — 보호 동안 차가 지나가도 살고, 끝나면 치인다")
    func roadWithoutSafeColumnShieldsOneSecond() throws {
        var game = ceShieldedOnFastRoad()
        let shield = try #require(game.respawnShield, "빠른 찻길인데 보호가 없다")
        #expect(shield.row == 1 && abs(shield.until - game.elapsed - CE.respawnRoadSafeSeconds) < 1e-9)
        #expect(game.player.row == 1 && game.player.x == 4, "칸을 고를 수 없으면 죽은 칸이어야 한다(\(game.player.x))")
        var passedThrough = 0
        ceRunFor(&game, seconds: 0.99) { g in
            if g.lane(at: 1)?.movers.contains(where: { $0.overlaps(center: 4, halfWidth: CE.playerHalfWidth, grace: 0.06) }) == true {
                passedThrough += 1
            }
            return g.death != nil
        }
        #expect(game.death == nil, "보호 중에 치였다")
        #expect(passedThrough > 0, "보호 동안 차가 안 지나갔다 — 시험이 헛돈다")
        ceRunFor(&game, seconds: 0.7) { $0.death != nil }
        #expect(game.respawnShield == nil)
        #expect(game.death?.cause == .car && game.deaths == 2, "보호가 끝났는데 안 치였다")
    }

    @Test("보호는 그 줄 한정: 옆 뛰기(같은 줄)는 유지 · 다른 줄 착지에서 끝 · 돌아와도 다시 무적이 아니다")
    func shieldEndsOnOtherRowLanding() throws {
        var game = ceShieldedOnFastRoad()
        let shield = try #require(game.respawnShield)
        game.input(.right)
        ceRunFor(&game, seconds: CE.hopSeconds + 0.005)
        #expect(game.death == nil && game.player.row == 1 && game.player.x == 5)
        #expect(game.respawnShield == shield, "옆 뛰기에 보호가 바뀌었다")
        game.input(.forward)
        ceRunFor(&game, seconds: CE.hopSeconds + 0.005)
        #expect(game.death == nil && game.player.row == 2)
        #expect(game.respawnShield == nil, "다른 줄에 착지했는데 보호가 남았다")
        game.input(.back)
        ceRunFor(&game, seconds: 1) { $0.death != nil }
        let death = try #require(game.death, "보호 줄로 돌아왔는데 안 치였다 — 다시 무적이 됐다")
        #expect(death.cause == .car && death.row == 1)
        #expect(death.at < shield.until, "옛 보호가 끝난 뒤에 치였다 — 돌아온 뒤 보호가 살았는지 가를 수 없다")
    }

    @Test("보호 판정은 충돌 자리 줄 — 보호 줄에서 앞으로 뛰는 둘째 절반(충돌 자리는 다음 줄)엔 다음 줄 차에 치인다(CC-13)")
    func shieldFollowsOccupancyRow() throws {
        // 2줄: 아잉이 칸(4)을 덮고 거의 서 있는 차.
        var game = ceShieldedOnFastRoad(extra: [ceRoad(2, speed: 0.0001, cars: [3.3])])
        let shield = try #require(game.respawnShield)
        let hopStart = game.elapsed
        game.input(.forward)
        // 첫 절반: 충돌 자리는 1줄(보호) — 빠른 차가 지나가도 산다.
        ceRunFor(&game, seconds: CE.hopSeconds * 0.45)
        #expect(game.death == nil && game.occupancy.row == 1)
        ceRunFor(&game, seconds: CE.hopSeconds) { $0.death != nil }
        let death = try #require(game.death, "보호 줄을 떠나는 둘째 절반에 다음 줄 차를 뚫었다")
        #expect(death.cause == .car && death.row == 2)
        // 뛰는 중(착지 전)에 치였다 — 그 순간 `player.row`(착지 전 = 1)는 보호 줄이었고 보호 시각도 남아 있었다.
        // player.row 로 재는 변이는 둘째 절반을 살아 넘기고 착지한 **뒤에야** 치인다(실측: 이 단언이 가른다).
        #expect(death.at - hopStart < CE.hopSeconds - 1e-9, "착지한 뒤에 치였다(\(death.at - hopStart)초) — 둘째 절반에 보호가 살아 있었다")
        #expect(death.at < shield.until && shield.row == 1)
    }

    @Test("둘째 절반 죽음: 아직 착지 못 한 앞 줄에서 다시 서도 점수 +1 없음 · 칸은 같은 거리면 왼쪽 먼저")
    func secondHalfDeathGivesNoPoint() throws {
        var game = ceDuelBoard([ceRoad(1, speed: 0.0001, cars: [3.3])])
        game.input(.forward)
        ceRunFor(&game, seconds: 0.2) { $0.death != nil }
        let death = try #require(game.death)
        #expect(death.row == 1 && game.score == 0)
        ceRunFor(&game, seconds: 3.1) { $0.phase == .running }
        #expect(game.phase == .running && game.player.row == 1 && game.score == 0, "착지 안 한 줄을 점수로 셌다(\(game.score))")
        #expect(game.player.x == 3, "죽은 칸(4)은 차 · 3 과 5 는 같은 거리 — 왼쪽(3)이어야 한다(\(game.player.x))")
        #expect(game.respawnShield == nil)
        game.input(.forward)
        ceRunFor(&game, seconds: CE.hopSeconds + 0.005)
        #expect(game.player.row == 2 && game.score == 2)
    }

    @Test("기찻길: 1.5초 안에 기차가 오면 마지막 겹침 + 0.1초까지 보호 — 기차가 지나가도 산다 · 안 오면 보호 없음(기준선: 보호 없이 서면 치임)")
    func railShieldLastsUntilTrainPasses() throws {
        func respawnOnRail(nextTrainIn countdown: Double) -> CE {
            var game = ceDuelBoard([ceRail(1, direction: 1, countdown: 0.2)])
            game.placePlayerForTesting(row: 1, x: 4)
            ceRunFor(&game, seconds: 2) { $0.death != nil }
            ceRunFor(&game, seconds: 2.9)
            // 다시 서기 직전에 기찻길을 새로 깐다(0.1초 뒤 부활 — 그때 기차까지 countdown − 0.1).
            game.replaceLane(ceRail(1, direction: 1, countdown: countdown))
            ceRunFor(&game, seconds: 0.2) { $0.phase == .running }
            return game
        }
        var game = respawnOnRail(nextTrainIn: 0.5)
        #expect(game.phase == .running && game.player.row == 1 && game.player.x == 4)
        let shield = try #require(game.respawnShield, "기차가 오는데 보호가 없다")
        let length = shield.until - game.elapsed
        #expect(shield.row == 1 && length > 1.3 && length < 1.7, "보호 길이 \(length)초(기차가 지나는 끝 + 0.1 ≈ 1.49)")
        #expect(length <= CE.respawnShieldMaxSeconds)
        var trainOverMe = 0
        ceRunFor(&game, seconds: 2.0) { g in
            if g.lane(at: 1)?.train?.overlaps(center: 4, halfWidth: CE.playerHalfWidth) == true { trainOverMe += 1 }
            return g.death != nil
        }
        #expect(game.death == nil, "보호 중 기차에 치였다")
        #expect(trainOverMe > 0, "기차가 안 지나갔다 — 시험이 헛돈다")
        #expect(game.respawnShield == nil && game.lane(at: 1)?.train == nil)

        let calm = respawnOnRail(nextTrainIn: 5.0)
        #expect(calm.phase == .running && calm.respawnShield == nil, "기차가 안 오는데 보호가 섰다")

        var solo = ceBoard(CE(seed: 7), lanes: [ceRail(1, direction: 1, countdown: 0.4)])
        solo.placePlayerForTesting(row: 1, x: 4)
        ceRunFor(&solo, seconds: 1.5) { $0.death != nil }
        #expect(solo.death?.cause == .train, "기준선: 보호 없이 섰는데 기차가 안 쳤다")
    }

    @Test("강: 놀이 칸 안 통나무 중 실려 나가기까지 가장 긴 자리(흐름 반대쪽 끝에서 반 칸 안)에 riding 으로 선다")
    func riverRespawnRidesTheLongestLog() throws {
        var game = ceDuelBoard([ceRiver(1, direction: 1, speed: 0.6, logs: [(x: -3, length: 3), (x: 6.5, length: 3)])])
        game.input(.forward)
        ceRunFor(&game, seconds: 0.3) { $0.death != nil }
        #expect(game.death?.cause == .water)
        ceRunFor(&game, seconds: 2.9)
        game.replaceLane(ceRiver(1, direction: -1, speed: 1, logs: [(x: 1, length: 3), (x: 5, length: 3)]))
        ceRunFor(&game, seconds: 0.2) { $0.phase == .running }
        #expect(game.phase == .running && game.player.row == 1 && game.player.riding)
        let lane = try #require(game.lane(at: 1))
        let far = try #require(lane.movers.max { $0.x < $1.x })
        #expect(abs(game.player.x - (far.maxX - 0.5)) < 1e-9, "가장 오래 버티는 자리가 아니다(\(game.player.x), 통나무 \(far.x)…\(far.maxX))")
        #expect(lane.log(under: game.player.x) != nil)
        ceRunFor(&game, seconds: 2) { $0.death != nil }
        #expect(game.death == nil && game.player.riding, "통나무 위에 섰는데 2초 안에 죽었다")
    }

    @Test("빈 강(CC-14): 통나무가 없으면 0.25초씩 최대 3초 더 기다리고, 그래도 없으면 뒤쪽 땅 줄 빈칸에 보호 2초 — 프로세스는 안 죽는다")
    func emptyRiverFallsBackToLandBehind() throws {
        var game = ceDuelBoard([ceGrass(1, blocked: [4]), ceRiver(2, logs: [])])
        game.placePlayerForTesting(row: 1, x: 3)
        game.input(.forward)
        ceRunFor(&game, seconds: 0.3) { $0.death != nil }
        let death = try #require(game.death)
        #expect(death.cause == .water && death.row == 2)
        ceRunFor(&game, seconds: 5.9 - (game.elapsed - death.at))
        #expect(ceIsOver(game) && game.death != nil, "통나무가 없는데 5.9초에 섰다")
        ceRunFor(&game, seconds: 0.2) { $0.phase == .running }
        #expect(game.phase == .running && game.death == nil)
        #expect(abs(game.elapsed - death.at - 6.0) <= 1.0 / 240 + 1e-9, "대체 경로가 죽고 \(game.elapsed - death.at)초")
        #expect(game.player.row == 1 && game.player.x == 3 && !game.player.riding, "뒤쪽 땅 줄 빈칸이 아니다(\(game.player.row), \(game.player.x))")
        let shield = try #require(game.respawnShield)
        #expect(shield.row == 1 && abs(shield.until - game.elapsed - 2.0) < 1e-9)
        #expect(game.score == 0 && game.deaths == 1)
        ceRunFor(&game, seconds: 2.1)
        #expect(game.respawnShield == nil && game.death == nil)

        // 기준선: 기다리는 동안 통나무가 놀이 칸에 들어오면(5.5초) 그 위에 선다 — 대체 경로로 안 간다.
        var waiting = ceDuelBoard([ceRiver(2, direction: 1, speed: 1, logs: [(x: -8, length: 3)])])
        waiting.placePlayerForTesting(row: 1, x: 4)
        waiting.input(.forward)
        ceRunFor(&waiting, seconds: 0.3) { $0.death != nil }
        let wet = try #require(waiting.death)
        ceRunFor(&waiting, seconds: 6.5) { $0.phase == .running }
        #expect(waiting.phase == .running && waiting.player.row == 2 && waiting.player.riding)
        let waited = waiting.elapsed - wet.at
        #expect(abs(waited - 5.5) <= 1.0 / 240 + 1e-9, "통나무를 기다린 시각 \(waited)초(기대 5.5)")
        #expect(abs(waiting.player.x - 0) < 1e-9, "놀이 칸에 막 들어온 통나무의 흐름 반대쪽 끝에서 반 칸 안이어야 한다(\(waiting.player.x))")
        #expect(waiting.respawnShield == nil)
    }
}

// MARK: - 시험: 실제 줄 위 실측(안 R1)

private struct CERespawnSample {
    var kind: CE.LaneKind
    var shielded: Bool
    var riding: Bool
    var diesIn1: Bool
    var diesIn15: Bool
    var baselineDiesIn1: Bool?
    var baselineDiesIn15: Bool?
    var trainWouldHit: Bool
}

/// 무모한 봇 — 0.25초마다 앞으로만 뛴다(1:1 규칙). 죽고 다시 설 때마다 그 자리를 잰다.
private func ceRecklessDuel(seed: UInt64, seconds: Double,
                            onRespawn: (CE, CE.Death) -> Void,
                            onScore: (Int, Double) -> Void) -> CE {
    var game = CE(seed: seed, rules: .duel)
    game.begin()
    var lastInput = -1.0
    var steps = 0
    while steps < Int(seconds * 60), game.phase != .result {
        if game.phase == .running, game.hop == nil, game.queued == nil, game.elapsed - lastInput >= 0.25 {
            game.input(.forward)
            lastInput = game.elapsed
        }
        let wasOver = ceIsOver(game)
        let death = game.death
        let score = game.score
        game.step(dt: 1.0 / 60)
        steps += 1
        if wasOver, game.phase == .running, let death { onRespawn(game, death) }
        if game.score != score { onScore(game.score, game.elapsed) }
    }
    return game
}

@Suite("길건너 1:1 엔진 — 실제 줄 실측(R1 · 시간 하한 · 결정성)")
struct CrossyDuelEngineMeasureTests {
    @Test("R1 실측: 다시 선 직후 서 있어도 찻길 1초 · 기찻길 1.5초 · 강 1초 안 죽음 0 — 기준선: 죽은 칸 그대로면 찻길이 치인다")
    func respawnSpotsSurviveOnRealLanes() {
        var samples: [CERespawnSample] = []
        var floorViolations: [String] = []
        var finals: [Int] = []
        for seed in UInt64(1)...60 {
            let end = ceRecklessDuel(seed: seed, seconds: 150, onRespawn: { game, death in
                let kind = game.lane(at: death.row)?.kind ?? .grass
                var sample = CERespawnSample(kind: kind, shielded: game.respawnShield != nil, riding: game.player.riding,
                                             diesIn1: ceDiesWithin(game, seconds: 1.0) != nil,
                                             diesIn15: ceDiesWithin(game, seconds: 1.5) != nil,
                                             baselineDiesIn1: nil, baselineDiesIn15: nil, trainWouldHit: false)
                if kind == .road, game.respawnShield == nil {
                    // 기준선: 칸 고르기를 끈 판 — 죽은 칸 그대로.
                    var raw = game
                    raw.placePlayerForTesting(row: death.row, x: Double(min(CE.columns - 1, max(0, Int(death.x.rounded())))))
                    sample.baselineDiesIn1 = ceDiesWithin(raw, seconds: 1.0) != nil
                    sample.baselineDiesIn15 = ceDiesWithin(raw, seconds: 1.5) != nil
                }
                if kind == .rail {
                    var copy = game
                    for _ in 0..<180 {
                        copy.step(dt: 1.0 / 120)
                        if copy.lane(at: death.row)?.train?.overlaps(center: game.player.x, halfWidth: CE.playerHalfWidth) == true {
                            sample.trainWouldHit = true
                        }
                    }
                }
                samples.append(sample)
            }, onScore: { score, at in
                if at < Double(score) * CE.hopSeconds - 1e-9 { floorViolations.append("씨앗 \(seed) 점수 \(score) @ \(at)") }
            })
            finals.append(end.score)
        }
        func rate(_ part: Int, _ whole: Int) -> String { whole == 0 ? "-" : String(format: "%.1f%%", 100 * Double(part) / Double(whole)) }
        for kind in CE.LaneKind.allCases {
            let group = samples.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            let alive15 = group.filter { !$0.diesIn15 }.count
            let alive1 = group.filter { !$0.diesIn1 }.count
            var line = "[길건너 1:1] R1 \(kind.rawValue): \(group.count)번 다시 섬 · 1초 안 안 죽음 \(rate(alive1, group.count))"
                + " · 1.5초 안 안 죽음 \(rate(alive15, group.count)) · 보호 \(group.filter(\.shielded).count)"
            if kind == .road {
                let base = group.compactMap(\.baselineDiesIn1)
                let base15 = group.compactMap(\.baselineDiesIn15)
                line += " · 기준선(죽은 칸 그대로) 1초 안 치임 \(rate(base.filter { $0 }.count, base.count)) · 1.5초 \(rate(base15.filter { $0 }.count, base15.count))"
            }
            if kind == .rail { line += " · 보호 없었으면 1.5초 안 기차 \(rate(group.filter(\.trainWouldHit).count, group.count))" }
            if kind == .river { line += " · 통나무 위 \(rate(group.filter(\.riding).count, group.count))" }
            print(line)
        }
        print("[길건너 1:1] 무모한 봇 60판(150초) 점수: 평균 \(finals.reduce(0, +) / max(1, finals.count)) · 최대 \(finals.max() ?? 0) · 다시 섬 \(samples.count)번")
        let roads = samples.filter { $0.kind == .road }
        let rails = samples.filter { $0.kind == .rail }
        let rivers = samples.filter { $0.kind == .river }
        #expect(roads.count >= 100 && rails.count >= 20 && rivers.count >= 100, "표본이 적다(찻길 \(roads.count) · 기찻길 \(rails.count) · 강 \(rivers.count))")
        #expect(roads.filter(\.diesIn1).isEmpty, "찻길에 다시 서고 1초 안에 치였다(\(roads.filter(\.diesIn1).count)번)")
        #expect(rails.filter(\.diesIn15).isEmpty, "기찻길에 다시 서고 1.5초 안에 치였다(\(rails.filter(\.diesIn15).count)번)")
        let dryRivers = rivers.filter { !$0.riding }.count
        #expect(dryRivers == 0, "강에 통나무 없이 섰다(\(dryRivers)번)")
        #expect(rivers.filter(\.diesIn1).isEmpty, "강에 다시 서고 1초 안에 죽었다")
        #expect(samples.filter { $0.kind == .grass }.isEmpty, "1:1 인데 풀밭에서 죽었다(놓침이 살아 있다)")
        // 기준선이 갈린다: 칸 고르기를 끄면 찻길이 1초 안에 치인다.
        let baseline = roads.compactMap(\.baselineDiesIn1)
        let baselineHits = baseline.filter { $0 }.count
        #expect(baselineHits * 33 >= baseline.count, "기준선(죽은 칸 그대로)이 거의 안 치인다(\(baselineHits)/\(baseline.count)) — 칸 고르기를 가르지 못한다")
        // 기찻길: 기차에 죽은 줄은 3초 뒤 다음 기차가 1.5초 안에 거의 안 온다(간격 ≥ 3.5초) — 보호는 드문 안전망이고,
        // 보호가 서는 길 · 기차가 지나가도 사는 것은 대본 판(railShieldLastsUntilTrainPasses)이 잰다.
        let railUnprotectedHits = rails.filter { $0.trainWouldHit && !$0.shielded }.count
        #expect(railUnprotectedHits == 0, "기찻길에 1.5초 안에 기차가 오는데 보호가 없었다(\(railUnprotectedHits)번)")
        // 시간 하한: 부활이 섞인 판도 점수 s 의 판 시각 ≥ s × hopSeconds.
        #expect(floorViolations.isEmpty, "시간 하한 위반 \(floorViolations.prefix(3))")
    }

    @Test("결정성: 같은 씨앗 두 1:1 판을 다르게 놀려도(죽음 · 부활 포함) 같은 줄 번호에 같은 줄 — 새 판에서 미리 본 줄 · 금빛 픽스처와 같다")
    func sameSeedSameLanesWithDeaths() throws {
        let preview = Dictionary(uniqueKeysWithValues: CE(seed: 2026).previewLanes(through: 300).map { ($0.row, ceShape($0)) })
        var deaths = 0
        let reckless = ceRecklessDuel(seed: 2026, seconds: 120, onRespawn: { _, _ in deaths += 1 }, onScore: { _, _ in })
        var careful = CE(seed: 2026, rules: .duel)
        careful.begin()
        for _ in 0..<(40 * 60) where careful.phase == .running || ceIsOver(careful) { ceBotStep(&careful) }
        #expect(deaths >= 5, "무모한 봇이 \(deaths)번밖에 안 죽었다 — 부활 경로를 안 지났다")
        var compared = 0
        for game in [reckless, careful] {
            for lane in game.lanes where lane.row >= -2 {
                guard let expected = preview[lane.row] else { continue }
                #expect(ceShape(lane) == expected, "\(lane.row) 줄이 놀이에 따라 바뀌었다")
                compared += 1
            }
        }
        print("[길건너 1:1] 결정성: 무모한 판 \(reckless.score)줄(죽음 \(deaths)) · 조심 판 \(careful.score)줄 · 비교 \(compared)줄")
        #expect(compared >= 40)
        #expect(reckless.score != careful.score || reckless.deaths != careful.deaths, "두 판이 같은 길을 놀았다 — 비교가 헛돈다")
    }
}

// MARK: - 시험: restore(앱 재실행 이어 하기)

@Suite("길건너 1:1 엔진 — restore(이어 하기)")
struct CrossyDuelEngineRestoreTests {
    @Test("restore 불변식: .running · cameraRow = row · score · deaths = 인자 · 뒤이은 begin()·걸음이 점수 · 줄을 안 지운다(기준선: .ready 의 begin 은 0)")
    func restoreInvariants() {
        var game = ceDuelBoard()
        game.restore(row: 10, score: 10, deaths: 3)
        #expect(game.phase == .running && game.cameraRow == 10 && game.score == 10 && game.deaths == 3)
        #expect(game.player.row == 10 && game.player.x == 4 && game.death == nil && game.hop == nil)
        let restored = game
        game.begin()
        #expect(game == restored, "restore 뒤 begin() 이 판을 다시 열었다")
        ceRunFor(&game, seconds: 1, dt: 1.0 / 30)
        #expect(game.score == 10 && game.player.row == 10)
        game.input(.forward)
        ceRunFor(&game, seconds: CE.hopSeconds + 0.01)
        #expect(game.score == 11 && game.player.row == 11, "이어 하기 첫 걸음 점수 \(game.score)")

        // 새 판(.ready)에서 바로 restore — 첫 판이 열리고 begin() 은 아무것도 안 한다.
        var fresh = CE(seed: 2026, rules: .duel)
        fresh.restore(row: 37, score: 37, deaths: 0)
        #expect(fresh.phase == .running && fresh.cameraRow == 37 && fresh.score == 37)
        let before = fresh
        fresh.begin()
        #expect(fresh == before)
        // 기준선: restore 가 .ready 를 남겼다면 begin() 이 점수 · 줄을 0 으로 돌렸을 것이다.
        var ready = CE(seed: 2026, rules: .duel)
        ready.begin()
        #expect(ready.score == 0 && ready.cameraRow == 0)
    }

    @Test("restore: 같은 씨앗 줄(새 판에서 미리 본 줄과 같음) · 찻길은 1초 안전 칸 · 강은 통나무 위 · 기찻길 · 서 있어도 1초 산다")
    func restoreOnRealLanes() throws {
        var checked: [CE.LaneKind: Int] = [:]
        for seed in [UInt64(0), 2026, 314] {
            let preview = CE(seed: seed).previewLanes(through: 200)
            let shapes = Dictionary(uniqueKeysWithValues: preview.map { ($0.row, ceShape($0)) })
            var picks: [CE.LaneKind: [Int]] = [:]
            for lane in preview where (1...100).contains(lane.row) && (picks[lane.kind]?.count ?? 0) < 3 {
                picks[lane.kind, default: []].append(lane.row)
            }
            for row in picks.values.flatMap({ $0 }).sorted() {
                var game = CE(seed: seed, rules: .duel)
                game.restore(row: row, score: row, deaths: 1)
                let kind = try #require(game.lane(at: row)?.kind)
                #expect(game.phase == .running && game.cameraRow == Double(row) && game.score == row && game.deaths == 1)
                for lane in game.lanes { #expect(ceShape(lane) == shapes[lane.row], "씨앗 \(seed) restore(\(row)): \(lane.row) 줄이 다르다") }
                switch kind {
                case .river:
                    #expect(game.player.row == row && game.player.riding && game.lane(at: row)?.log(under: game.player.x) != nil,
                            "씨앗 \(seed) 강 \(row) 줄: 통나무 위가 아니다")
                case .road:
                    #expect(game.player.row == row && !game.player.riding)
                    #expect(game.respawnShield != nil || ceDiesWithin(game, seconds: 1.0) == nil, "씨앗 \(seed) 찻길 \(row) 줄: 1초 안에 치였다")
                case .rail, .grass:
                    #expect(game.player.row == row)
                }
                #expect(ceDiesWithin(game, seconds: 1.0) == nil, "씨앗 \(seed) \(kind.rawValue) \(row) 줄: restore 뒤 1초 안에 죽었다")
                checked[kind, default: 0] += 1
            }
        }
        print("[길건너 1:1] restore 실제 줄: \(checked.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue) \($0.value)" })")
        #expect(CE.LaneKind.allCases.allSatisfy { (checked[$0] ?? 0) >= 3 })
    }

    @Test("restore 판 도중(CC-22): 판 시계 · 씨앗은 그대로 그 줄로 다시 선다 · 들고 있는 줄보다 뒤로 가면 같은 줄을 다시 만든다")
    func restoreMidGame() throws {
        var game = ceDuelBoard()
        for _ in 0..<5 {
            game.input(.forward)
            ceRunFor(&game, seconds: CE.hopSeconds + 0.001)
        }
        let elapsed = game.elapsed
        let seed = game.roundSeed
        game.restore(row: 8, score: 8, deaths: 2)
        #expect(game.score == 8 && game.player.row == 8 && game.cameraRow == 8 && game.deaths == 2)
        #expect(game.elapsed == elapsed && game.roundSeed == seed, "restore 가 판 시계 · 씨앗을 건드렸다")

        let shapes = Dictionary(uniqueKeysWithValues: CE(seed: 2026).previewLanes(through: 200).map { ($0.row, ceShape($0)) })
        var far = CE(seed: 2026, rules: .duel)
        far.restore(row: 90, score: 90, deaths: 0)
        #expect(far.lane(at: 10) == nil, "앞서 간 판이 10 줄을 아직 들고 있다 — 다시 만들기 길을 안 지난다")
        far.restore(row: 10, score: 10, deaths: 0)
        #expect(far.lane(at: 10) != nil && far.player.row <= 10 && far.cameraRow == 10)
        far.step(dt: 1.0 / 30)
        for lane in far.lanes { #expect(ceShape(lane) == shapes[lane.row], "다시 만든 \(lane.row) 줄이 다르다") }
    }
}

// MARK: - 시험: 그림(보호 깜빡임)

@MainActor
@Suite("길건너 1:1 엔진 — 그림(보호 깜빡임)", .serialized)
struct CrossyDuelEngineSceneTests {
    @Test("보호 동안 아잉이가 깜빡인다(초당 6회 0.4↔1.0 · 동작 줄이기 0.6 고정) · 보호가 끝나면 1.0 · 보호 없는 판은 늘 1.0")
    func shieldBlinks() {
        let scene = CrossyScene(aingLoader: { nil })
        var game = ceShieldedOnFastRoad()
        #expect(game.respawnShield != nil)
        var on = 0
        var off = 0
        while let shield = game.respawnShield, game.elapsed < shield.until, game.death == nil {
            let expected: CGFloat = Int(game.elapsed * 12) % 2 == 0 ? 1.0 : 0.4
            scene.apply(game, reduceMotion: false)
            #expect(abs(scene.aingTransformForTesting.opacity - expected) < 1e-3)
            if expected == 1 { on += 1 } else { off += 1 }
            scene.apply(game, reduceMotion: true)
            #expect(abs(scene.aingTransformForTesting.opacity - 0.6) < 1e-3)
            game.step(dt: 1.0 / 120)
        }
        #expect(on > 20 && off > 20, "깜빡임 박자가 안 보인다(켬 \(on) · 끔 \(off))")
        if game.death == nil {
            scene.apply(game, reduceMotion: false)
            #expect(abs(scene.aingTransformForTesting.opacity - 1.0) < 1e-3, "보호가 끝났는데 반투명이다")
        }
        // 기준선: 보호 없는 판은 같은 박자에도 1.0.
        var plain = ceDuelBoard()
        for _ in 0..<24 {
            scene.apply(plain, reduceMotion: false)
            #expect(abs(scene.aingTransformForTesting.opacity - 1.0) < 1e-3)
            plain.step(dt: 1.0 / 120)
        }
    }
}
