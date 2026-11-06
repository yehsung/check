import Foundation
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

private func ceGolden(seed: UInt64) -> CEGoldenSeed {
    let game = CE(seed: seed)
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
            let text = try ceLineJSON(head: head, listKey: "seeds", items: ceGoldenSeeds.map(ceGolden))
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
