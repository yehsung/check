import AppKit
import Foundation
import Metal
import SceneKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.67 — 미니게임 넷째 "길건너 아잉이"(`crossy`) 맥 갈래. 설계서 `v0367-crossy/SPEC.md` §1(공통 계약) · §3(맥).
//
// 이 파일이 지키는 것(층마다 한 묶음):
//   A 엔진(CheckCore 순수 값) — 결정적 줄 생성 · 시작 풀밭 · 줄 섞임 · 난이도 · 뛰기 시간 · 입력 줄 세우기 · 막힌 칸 ·
//     죽음 사유 다섯(차 · 물 · 통나무 실림 · 기차 · 놓침) · 통나무 타기 · 점수 단조 · 끊기 · 시간 하한(서버 계약의 엔진 쪽)
//   B 종류 · 키 · 패널 배선(소스 계약은 주석을 걷어내고 잰다)
//   C 스토어 — 라운드 토큰 · 제출 · 오늘/역대 순위 · 어제 1등이 crossy 로 돈다(호스트별 대본 URLProtocol — 실네트워크 없음)
//   D 그림 — 오프스크린 SCNRenderer(시작 · 중간 · 죽음 다섯) PNG · 아잉이 화면 크기 · 노드 풀 재활용 · 그림자 맵 상한.
//     SwiftUI `ImageRenderer` 는 SCNView 를 못 찍는다 — 3D 는 SCNRenderer 로, 글자 겹(`CrossyHUD`)만 ImageRenderer 로 찍어 겹친다.
//     PNG 는 `CHECK_SNAPSHOT_DIR`/crossy 에 남는다(없으면 임시 폴더).
//   E 서버 계약(CHECK_MIGRATIONS_DIR) — 20261027130000_minigame_crossy.sql 의 상한 5000 · 시간 하한 0.09 · daily_crossy.
// 창은 띄우지 않는다.

// MARK: - 픽스처(엔진)

private typealias CG = CrossyGame

private func cgGrass(_ row: Int, blocked: [Int] = [], rock: [Int] = []) -> CG.Lane {
    var props = [CG.Prop?](repeating: nil, count: CG.columns)
    for c in blocked { props[c] = .tree(height: 1) }
    for c in rock { props[c] = .rock }
    return CG.Lane(row: row, kind: .grass, props: props)
}

private func cgRoad(_ row: Int, direction: Int = 1, speed: Double = 2, cars: [Double], truck: Bool = false) -> CG.Lane {
    let length = truck ? CG.truckLength : CG.carLength
    return CG.Lane(row: row, kind: .road, direction: direction, speed: speed,
                   movers: cars.map { CG.Mover(x: $0, length: length, isTruck: truck) })
}

private func cgRiver(_ row: Int, direction: Int = 1, speed: Double = 1, logs: [(x: Double, length: Double)]) -> CG.Lane {
    CG.Lane(row: row, kind: .river, direction: direction, speed: speed,
            movers: logs.map { CG.Mover(x: $0.x, length: $0.length) })
}

private func cgRail(_ row: Int, direction: Int = 1, countdown: Double) -> CG.Lane {
    CG.Lane(row: row, kind: .rail, direction: direction, speed: CG.trainSpeed, trainCountdown: countdown)
}

/// 진행 중 판 — 줄 −2…14 를 물건 없는 풀밭으로 덮고 `lanes` 를 얹는다(시험이 원하는 판만 남긴다).
private func cgGame(seed: UInt64 = 7, lanes: [CG.Lane] = []) -> CG {
    var game = CG(seed: seed)
    game.startForTesting()
    for row in -2...14 { game.replaceLane(cgGrass(row)) }
    for lane in lanes { game.replaceLane(lane) }
    return game
}

/// `seconds` 만큼 작은 걸음으로 흘린다(멈출 조건이 서면 그 자리에서).
@discardableResult
private func cgRun(_ game: inout CG, seconds: Double, dt: Double = 1.0 / 240,
                   until stop: (CG) -> Bool = { _ in false }) -> Bool {
    var t = 0.0
    while t < seconds - 1e-12 {
        let step = min(dt, seconds - t)
        game.step(dt: step)
        t += step
        if stop(game) { return true }
    }
    return false
}

/// 줄의 **놓인 모양**(시간이 지나도 안 바뀌는 것) — 결정성 비교용. 물체 x · 기차 시계는 뺀다.
private func cgShape(_ lane: CG.Lane) -> String {
    let props = lane.props.map { prop -> String in
        switch prop {
        case .none: "."
        case .tree(let h)?: "t\(h)"
        case .rock?: "r"
        }
    }.joined()
    return "\(lane.row):\(lane.kind.rawValue):\(props):\(lane.direction):\(lane.speed):\(lane.movers.map(\.length))"
}

/// 살아남으려는 봇 — 뛰기 전에 사본으로 0.5초를 미리 돌려 보고 산 쪽을 고른다. 규칙이 결정적이라 미리 본 것이
/// 그대로 일어난다. 그림 증거(중간 장면) · 노드 풀 · 실제 줄 위의 시간 하한 시험이 쓴다.
///   ① 앞이 열려 있고 살면 앞. ② 앞이 **막혔으면**(나무 · 바위) 다음 줄의 열린 칸 쪽으로 옆 걸음.
///   ③ 앞이 위험하면 그대로 기다린다(서 있어도 살 때). ④ 서 있어도 죽으면 옆 · 뒤 중 사는 쪽.
private func cgBotStep(_ game: inout CG, dt: Double = 1.0 / 60) {
    func survives(_ probe: CG) -> Bool {
        var copy = probe
        for _ in 0..<30 {
            copy.step(dt: 1.0 / 60)
            if copy.death != nil { return false }
        }
        return true
    }
    func tryHop(_ direction: CG.Direction) -> Bool {
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
            // 다음 줄에서 가장 가까운 열린 칸 쪽으로.
            let here = Int(game.player.x.rounded())
            let next = game.lane(at: game.player.row + 1)
            let open = (0..<CG.columns).filter { !(next?.isBlocked(column: $0) ?? true) }
            let target = open.min { abs($0 - here) < abs($1 - here) } ?? here
            let side: [CG.Direction] = target < here ? [.left, .right] : [.right, .left]
            if !survives(game) || !side.contains(where: { tryHop($0) }) { _ = tryHop(.back) }
        } else if !survives(game) {
            _ = [CG.Direction.left, .right, .back].first { tryHop($0) }
        }
    }
    game.step(dt: dt)
}

// MARK: - A 엔진

@Suite("v0.3.67 길건너 아잉이 — 엔진(CheckCore)")
struct V0367CrossyEngineTests {
    @Test("결정성: 같은 시드면 같은 줄 · 다른 시드면 다른 줄 · 판을 어떻게 해도 같은 줄 번호에 같은 줄이 선다")
    func laneGenerationIsDeterministic() {
        let a = CG(seed: 2026).previewLanes(through: 300)
        let b = CG(seed: 2026).previewLanes(through: 300)
        #expect(a == b, "같은 시드인데 줄이 다르다")
        let c = CG(seed: 2027).previewLanes(through: 300)
        #expect(a.map(cgShape) != c.map(cgShape), "다른 시드인데 줄이 같다")

        // 봇이 20초를 실제로 놀아 본 판(시간 · 뛰기 · 죽음까지) — 그 판이 들고 있는 줄의 모양이 미리 본 줄과 같다.
        var played = CG(seed: 2026)
        played.action()
        for _ in 0..<(20 * 60) where played.phase == .running { cgBotStep(&played) }
        let preview = Dictionary(uniqueKeysWithValues: a.map { ($0.row, cgShape($0)) })
        var compared = 0
        for lane in played.lanes where lane.row >= -2 {
            guard let expected = preview[lane.row] else { continue }
            #expect(cgShape(lane) == expected, "\(lane.row) 줄이 놀이에 따라 바뀌었다")
            compared += 1
        }
        print("[길건너] 결정성: 놀아 본 판 \(played.score)줄 · 비교한 줄 \(compared)개")
        #expect(compared >= 20, "비교한 줄이 너무 적다(\(compared)) — 검사가 헛돈다")
    }

    @Test("시작 풀밭: 0…3 줄은 풀밭이고 가운데 칸이 열려 있다 · −3 줄 아래는 막힌 숲 · 강은 6줄 · 기찻길은 14줄 전엔 없다")
    func startAreaAndEarlyRows() {
        for seed in UInt64(1)...40 {
            let lanes = CG(seed: seed).previewLanes(through: 60)
            for lane in lanes {
                if lane.row <= CG.wallRow {
                    #expect(lane.kind == .grass && (0..<CG.columns).allSatisfy { lane.isBlocked(column: $0) },
                            "시드 \(seed): \(lane.row) 줄 숲 벽에 구멍이 있다")
                } else if lane.row <= CG.startGrassRows {
                    #expect(lane.kind == .grass, "시드 \(seed): 시작 \(lane.row) 줄이 풀밭이 아니다")
                    #expect(!lane.isBlocked(column: CG.startColumn), "시드 \(seed): 시작 \(lane.row) 줄 가운데가 막혔다")
                }
                if lane.row < CG.riverStartRow { #expect(lane.kind != .river, "시드 \(seed): \(lane.row) 줄에 강") }
                if lane.row < CG.railStartRow { #expect(lane.kind != .rail, "시드 \(seed): \(lane.row) 줄에 기찻길") }
            }
        }
        // 첫 판은 시작 카드 뒤의 그 길이다 — 눌렀는데 길이 바뀌면 튄다.
        let ready = CG(seed: 99)
        var started = ready
        started.action()
        #expect(started.lanes.prefix(20).map(cgShape) == ready.lanes.prefix(20).map(cgShape), "시작하자 길이 바뀌었다")
    }

    @Test("줄 섞임: 네 종류가 다 나오고 · 풀밭마다 열린 칸 · 붙은 풀밭끼리 같은 칸이 열림 · 차 1~3대 사이 3칸↑ · 통나무 2~4칸")
    func laneMixIsPlayable() {
        var counts: [CG.LaneKind: Int] = [:]
        for seed in UInt64(1)...30 {
            let lanes = CG(seed: seed).previewLanes(through: 400).filter { $0.row > CG.startGrassRows }
            for (index, lane) in lanes.enumerated() {
                counts[lane.kind, default: 0] += 1
                switch lane.kind {
                case .grass:
                    let open = Set((0..<CG.columns).filter { !lane.isBlocked(column: $0) })
                    #expect(!open.isEmpty, "시드 \(seed): \(lane.row) 줄 풀밭이 통째로 막혔다")
                    if index > 0, lanes[index - 1].kind == .grass {
                        let previous = Set((0..<CG.columns).filter { !lanes[index - 1].isBlocked(column: $0) })
                        #expect(!open.isDisjoint(with: previous), "시드 \(seed): \(lane.row) 줄과 앞 풀밭이 이어지지 않는다")
                    }
                case .road:
                    #expect((1...3).contains(lane.movers.count), "시드 \(seed): \(lane.row) 줄 차 \(lane.movers.count)대")
                    let sorted = lane.movers.sorted { $0.x < $1.x }
                    for (left, right) in zip(sorted, sorted.dropFirst()) {
                        #expect(right.x - left.maxX >= 3.0 - 1e-9, "시드 \(seed): \(lane.row) 줄 차 사이가 3칸보다 좁다")
                    }
                    if let first = sorted.first, let last = sorted.last, sorted.count > 1 {
                        #expect(first.x + CG.trackLength - last.maxX >= 3.0 - 1e-9, "시드 \(seed): 감아 도는 틈이 좁다")
                    }
                case .river:
                    #expect(lane.movers.allSatisfy { (2...4).contains(Int($0.length)) }, "시드 \(seed): 통나무 길이")
                    #expect(lane.movers.count >= 2)
                case .rail:
                    #expect(lane.trainCountdown > 0 && lane.train == nil)
                }
            }
        }
        print("[길건너] 줄 섞임(30 시드 × 396줄): \(counts.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue) \($0.value)" })")
        for kind in CG.LaneKind.allCases { #expect((counts[kind] ?? 0) > 100, "\(kind) 가 거의 안 나온다") }
    }

    @Test("난이도: 줄이 갈수록 차가 빨라지고 · 통나무가 줄고 · 기찻길이 잦아지고 · 카메라가 빨리 따라온다")
    func difficultyRisesWithRow() {
        #expect(CG.difficulty(row: 0) == 0 && CG.difficulty(row: 4) == 0)
        #expect(CG.difficulty(row: 254) == 1 && CG.difficulty(row: 5000) == 1)
        #expect(CG.creepSpeed(row: 0) < CG.creepSpeed(row: 300))
        var early: (speed: [Double], logs: [Int], rail: Int, all: Int) = ([], [], 0, 0)
        var late: (speed: [Double], logs: [Int], rail: Int, all: Int) = ([], [], 0, 0)
        for seed in UInt64(1)...30 {
            for lane in CG(seed: seed).previewLanes(through: 420) {
                let isEarly = (14...90).contains(lane.row)
                guard isEarly || (260...420).contains(lane.row) else { continue }
                switch lane.kind {
                case .road:
                    if isEarly { early.speed.append(lane.speed) } else { late.speed.append(lane.speed) }
                case .river:
                    if isEarly { early.logs.append(lane.movers.count) } else { late.logs.append(lane.movers.count) }
                case .rail:
                    if isEarly { early.rail += 1 } else { late.rail += 1 }
                case .grass:
                    break
                }
                if isEarly { early.all += 1 } else { late.all += 1 }
            }
        }
        func mean(_ v: [Double]) -> Double { v.reduce(0, +) / Double(max(1, v.count)) }
        let speedRatio = mean(late.speed) / mean(early.speed)
        let logs = (mean(early.logs.map(Double.init)), mean(late.logs.map(Double.init)))
        let rail = (Double(early.rail) / Double(early.all), Double(late.rail) / Double(late.all))
        print("[길건너] 난이도: 차 속도 ×\(String(format: "%.2f", speedRatio)) · 통나무 \(String(format: "%.2f", logs.0))→\(String(format: "%.2f", logs.1))개"
              + " · 기찻길 비율 \(String(format: "%.3f", rail.0))→\(String(format: "%.3f", rail.1))")
        #expect(speedRatio > 1.5, "뒤 줄 차가 별로 안 빠르다(×\(speedRatio))")
        #expect(logs.1 < logs.0, "뒤 강의 통나무가 안 줄었다")
        #expect(rail.1 > rail.0, "뒤로 갈수록 기찻길이 안 잦아졌다")
    }

    @Test("뛰기 한 번 = hopSeconds(0.12초) · 점수는 착지에서 오른다 · 뛰는 동안 몸이 뜬다")
    func oneHopTakesHopSeconds() {
        #expect(CG.hopSeconds == 0.12)
        var game = cgGame()
        game.input(.forward)
        #expect(game.hop?.toRow == 1 && game.score == 0)
        cgRun(&game, seconds: 0.06)
        #expect(game.playerVisual.lift > 0.9, "가운데에서 몸이 안 떴다(\(game.playerVisual.lift))")
        cgRun(&game, seconds: 0.05)
        #expect(game.score == 0 && game.hop != nil, "0.11초에 벌써 착지했다")
        cgRun(&game, seconds: 0.02)
        #expect(game.score == 1 && game.hop == nil && game.player.row == 1)
        #expect(game.playerVisual.lift == 0)
    }

    @Test("입력 줄 세우기: 뛰는 중 입력은 **하나만** 서고 그 뒤는 버린다 · 줄 선 뛰기는 착지 순간 이어 붙는다(판 시계 정확히)")
    func inputQueueHoldsExactlyOne() {
        var game = cgGame()
        game.input(.forward)
        game.input(.forward)
        game.input(.forward)          // 버려진다
        #expect(game.queued == .forward)
        var reachedTwoAt: Double?
        cgRun(&game, seconds: 0.6, dt: 0.01) { g in
            if g.score == 2, reachedTwoAt == nil { reachedTwoAt = g.elapsed }
            return false
        }
        #expect(game.player.row == 2, "셋째 입력이 버려지지 않았다(줄 \(game.player.row))")
        #expect(game.queued == nil)
        #expect(reachedTwoAt.map { $0 >= 0.24 - 1e-9 && $0 < 0.25 } ?? false,
                "두 번째 착지가 \(reachedTwoAt ?? -1)초 — 착지 순간에 이어 붙지 않았다")
        // 줄 선 입력의 방향이 지켜진다(앞 → 오른쪽) · 그 뒤 입력(왼쪽)은 **버려진다**(갈아 끼우지 않는다).
        var turn = cgGame()
        turn.input(.forward)
        turn.input(.right)
        turn.input(.left)
        #expect(turn.queued == .right, "뒤에 온 입력이 줄 선 입력을 갈아 끼웠다")
        cgRun(&turn, seconds: 0.3)
        #expect(turn.player.row == 1 && turn.player.x == 5 && turn.player.facing == .right)
        // 큰 걸음에서도 남은 시간을 이어 받는다. 걸음 0.0299초(엔진 상한 1/30 아래)면 첫 착지가 5걸음(0.1495초, 0.0295초 남음)이고
        // 둘째는 남은 시간을 이어 받아 4걸음 뒤(9걸음 = 0.2691초)에 착지한다. 남은 시간을 버리면 10걸음(0.299초)이다 —
        // 연타가 프레임 박자에 끌려 느려진다(서버 하한과는 무관하지만 손맛이 프레임마다 달라진다).
        var coarse = cgGame()
        coarse.input(.forward)
        coarse.input(.forward)
        var coarseTwoAt: Double?
        cgRun(&coarse, seconds: 0.5, dt: 0.0299) { g in
            if g.score == 2, coarseTwoAt == nil { coarseTwoAt = g.elapsed }
            return false
        }
        #expect(coarseTwoAt.map { abs($0 - 9 * 0.0299) < 1e-9 } ?? false, "큰 걸음에서 둘째 착지가 \(coarseTwoAt ?? -1)초(기대 0.2691)")
    }

    @Test("막힌 칸: 나무 · 바위면 제자리 통통(줄 · 점수 그대로 · 같은 시간) · 놀이 칸 끝도 막힘 · 뒤 숲 벽도 막힘")
    func blockedTilesBump() {
        for lane in [cgGrass(1, blocked: [4]), cgGrass(1, rock: [4])] {
            var game = cgGame(lanes: [lane])
            game.input(.forward)
            #expect(game.hop?.bumped == true && game.hop?.toRow == 0, "막힌 칸으로 뛰었다")
            cgRun(&game, seconds: CG.hopSeconds + 0.01)
            #expect(game.player.row == 0 && game.score == 0 && game.hopCount == 1)
        }
        var edge = cgGame()
        edge.placePlayerForTesting(row: 0, x: 0)
        edge.input(.left)
        #expect(edge.hop?.bumped == true, "놀이 칸 왼쪽 끝 밖으로 뛰었다")
        edge.placePlayerForTesting(row: 0, x: 8)
        edge.input(.right)
        #expect(edge.hop?.bumped == true, "놀이 칸 오른쪽 끝 밖으로 뛰었다")
        // 뒤 숲(−3 줄)은 통째로 막혔다.
        var back = CG(seed: 5)
        back.startForTesting()
        back.placePlayerForTesting(row: -2, x: 4)
        back.input(.back)
        #expect(back.hop?.bumped == true, "뒤 숲 벽을 뚫었다")
    }

    @Test("차: 서 있는 아잉이에게 차가 오면 납작(car) · 친 차의 방향 · 맞닿기 직전엔 살아 있다")
    func carHitsStandingPlayer() {
        var game = cgGame(lanes: [cgRoad(1, direction: 1, speed: 2, cars: [1.0])])
        game.placePlayerForTesting(row: 1, x: 4)
        // 앞 범퍼 2.4 → 아잉이 왼쪽 몸 3.7(+너그러움 0.06) — 약 0.68초.
        cgRun(&game, seconds: 0.6)
        #expect(game.death == nil, "닿기 전에 죽었다")
        cgRun(&game, seconds: 0.2) { $0.death != nil }
        #expect(game.death?.cause == .car && game.death?.pushDirection == 1)
        #expect(game.isGameOver)
        // 반대 방향 트럭.
        var truck = cgGame(lanes: [cgRoad(1, direction: -1, speed: 3, cars: [7.0], truck: true)])
        truck.placePlayerForTesting(row: 1, x: 4)
        cgRun(&truck, seconds: 2) { $0.death != nil }
        #expect(truck.death?.cause == .car && truck.death?.pushDirection == -1)
    }

    @Test("차: 뛰어 들어갈 때는 절반을 넘긴 순간부터 그 줄의 차에 닿는다")
    func hopIntoCarCountsFromHalfway() {
        var game = cgGame(lanes: [cgRoad(1, speed: 0.0001, cars: [3.3])])
        game.input(.forward)
        cgRun(&game, seconds: 0.05)
        #expect(game.death == nil, "출발 줄에 있는데 앞 줄 차에 죽었다")
        cgRun(&game, seconds: 0.03) { $0.death != nil }
        #expect(game.death?.cause == .car && game.death?.row == 1)
    }

    @Test("강: 통나무 없이 착지하면 물(water) · 통나무 위면 타고 같이 흐른다 · 통나무 끝 0.2칸까지 너그럽다")
    func riverWaterAndRiding() {
        var wet = cgGame(lanes: [cgRiver(1, speed: 0.5, logs: [(x: -5, length: 2)])])
        wet.input(.forward)
        cgRun(&wet, seconds: 0.2) { $0.death != nil }
        #expect(wet.death?.cause == .water)
        #expect(wet.score == 0, "물에 빠진 줄을 점수로 셌다")

        var ride = cgGame(lanes: [cgRiver(1, direction: 1, speed: 1, logs: [(x: 3.0, length: 3)])])
        ride.input(.forward)
        cgRun(&ride, seconds: CG.hopSeconds + 0.001)
        #expect(ride.player.riding && ride.score == 1, "통나무에 안 탔다")
        let x0 = ride.player.x
        cgRun(&ride, seconds: 0.5)
        #expect(abs(ride.player.x - (x0 + 0.5)) < 1e-6, "통나무와 같이 안 흘렀다(\(x0) → \(ride.player.x))")
        #expect(ride.death == nil)

        // 끝 너그러움: 통나무 오른쪽 끝(3.85)에서 0.15칸 밖(4.0)에 착지해도 탄다.
        var edge = cgGame(lanes: [cgRiver(1, speed: 0.0001, logs: [(x: 0.85, length: 3)])])
        edge.input(.forward)
        cgRun(&edge, seconds: CG.hopSeconds + 0.001)
        #expect(edge.player.riding && edge.death == nil, "통나무 끝 너그러움이 없다")
    }

    @Test("통나무에 실려 놀이 칸 밖으로 나가면 끝(carriedOff) · 놀이 칸 안에서는 안 죽는다")
    func carriedOffTheEdge() {
        var game = cgGame(lanes: [cgRiver(1, direction: 1, speed: 3, logs: [(x: 5.5, length: 4)])])
        game.placePlayerForTesting(row: 1, x: 7.5, riding: true)
        cgRun(&game, seconds: 0.3)
        #expect(game.death == nil && game.player.x > 8.3, "놀이 칸 안인데 죽었다")
        cgRun(&game, seconds: 0.2) { $0.death != nil }
        #expect(game.death?.cause == .carriedOff)
        #expect((game.death?.x ?? 0) > CG.playMaxX)
    }

    @Test("통나무 위에서 옆으로 뛰면 통나무 흐름을 같이 탄다 · 통나무 밖으로 뛰면 물")
    func lateralHopOnLog() {
        var onLog = cgGame(lanes: [cgRiver(1, direction: -1, speed: 1, logs: [(x: 2.0, length: 4)])])
        onLog.placePlayerForTesting(row: 1, x: 3.0, riding: true)
        onLog.input(.right)
        cgRun(&onLog, seconds: CG.hopSeconds + 0.001)
        #expect(onLog.death == nil && onLog.player.riding)
        #expect(abs(onLog.player.x - (3.0 + 1 - 0.121)) < 0.01, "옆 뛰기가 흐름을 안 탔다(\(onLog.player.x))")

        var off = cgGame(lanes: [cgRiver(1, direction: 1, speed: 0.0001, logs: [(x: 2.0, length: 2)])])
        off.placePlayerForTesting(row: 1, x: 3.5, riding: true)
        off.input(.right)
        cgRun(&off, seconds: 0.2) { $0.death != nil }
        #expect(off.death?.cause == .water, "통나무 밖으로 뛰었는데 안 빠졌다")
    }

    @Test("통나무 위 끝 칸에서 놀이 칸 밖으로 옆 뛰기 = 제자리 통통(땅과 같다) · 흘러 나가는 것만 죽음이다")
    func lateralHopOffTheEdgeOnALogBumps() {
        for (x, direction) in [(8.0, CG.Direction.right), (0.0, CG.Direction.left), (7.7, CG.Direction.right), (0.3, CG.Direction.left)] {
            var game = cgGame(lanes: [cgRiver(1, direction: 1, speed: 0.0001, logs: [(x: -1.0, length: 4), (x: 5.5, length: 4)])])
            game.placePlayerForTesting(row: 1, x: x, riding: true)
            game.input(direction)
            #expect(game.hop?.bumped == true, "x \(x) 에서 \(direction) 이 놀이 칸 밖으로 뛰었다")
            cgRun(&game, seconds: CG.hopSeconds + 0.05)
            #expect(game.death == nil && game.player.riding, "x \(x) 끝 칸 옆 뛰기가 죽음이 됐다(\(game.death?.cause.rawValue ?? "-"))")
            #expect(abs(game.player.x - x) < 0.01, "제자리가 아니다(\(x) → \(game.player.x))")
        }
        // 안쪽으로는 그대로 뛴다.
        var inward = cgGame(lanes: [cgRiver(1, direction: 1, speed: 0.0001, logs: [(x: 5.5, length: 4)])])
        inward.placePlayerForTesting(row: 1, x: 8.0, riding: true)
        inward.input(.left)
        #expect(inward.hop?.bumped == false)
    }

    @Test("기찻길: 나타나기 1초 전부터 경고등 · 지나가는 동안 켜짐 · 닿으면 기차(train) · 지나가면 꺼지고 다음 기차를 센다")
    func railWarnsThenKills() throws {
        var game = cgGame(lanes: [cgRail(2, direction: 1, countdown: 3.0)])
        cgRun(&game, seconds: 1.5)
        #expect(game.lane(at: 2)?.isTrainWarning == false, "1.5초 남았는데 벌써 경고")
        cgRun(&game, seconds: 0.6)
        #expect(game.lane(at: 2)?.isTrainWarning == true, "0.9초 남았는데 경고가 없다")
        #expect(game.lane(at: 2)?.train == nil)
        cgRun(&game, seconds: 0.95)
        let train = try #require(game.lane(at: 2)?.train, "3초가 지났는데 기차가 안 나왔다")
        #expect(train.length == CG.trainLength && train.length > Double(CG.columns))
        // 지나가고 나면 꺼지고 다음 기차를 센다.
        cgRun(&game, seconds: 1.5)
        #expect(game.lane(at: 2)?.train == nil && game.lane(at: 2)?.isTrainWarning == false)
        #expect((game.lane(at: 2)?.trainCountdown ?? 0) > 1)

        var hit = cgGame(lanes: [cgRail(1, direction: -1, countdown: 0.5)])
        hit.placePlayerForTesting(row: 1, x: 4)
        cgRun(&hit, seconds: 2) { $0.death != nil }
        #expect(hit.death?.cause == .train && hit.death?.pushDirection == -1)
        #expect(hit.elapsed > 0.5 && hit.elapsed < 1.0, "기차가 \(hit.elapsed)초에 쳤다")
    }

    @Test("놓침: 카메라보다 2.5줄 넘게 뒤처지면(뒤로 뛰기) leftBehind · 앞 줄을 9초 못 넘겨도 leftBehind")
    func leftBehindByCameraAndIdle() {
        var back = cgGame()
        for _ in 0..<6 {
            back.input(.forward)
            cgRun(&back, seconds: CG.hopSeconds + 0.001)
        }
        cgRun(&back, seconds: 1.5)
        #expect(back.cameraRow > 5.5, "카메라가 안 따라왔다(\(back.cameraRow))")
        var backs = 0
        while back.death == nil, backs < 5 {
            back.input(.back)
            cgRun(&back, seconds: CG.hopSeconds + 0.001) { $0.death != nil }
            backs += 1
        }
        #expect(back.death?.cause == .leftBehind, "뒤처졌는데 안 놓쳤다")
        #expect(backs >= 3, "\(backs)번 만에 놓쳤다 — 카메라 여유가 너무 좁다")

        var idle = cgGame()
        idle.input(.forward)
        cgRun(&idle, seconds: CG.hopSeconds + 0.001)
        cgRun(&idle, seconds: CG.idleLimit - 0.2)
        #expect(idle.death == nil, "9초가 안 됐는데 놓쳤다")
        cgRun(&idle, seconds: 0.5) { $0.death != nil }
        #expect(idle.death?.cause == .leftBehind)
        // 카메라는 안 움직여도 앞으로 간다(혼자 가기).
        #expect(idle.cameraRow > 1.0 + CG.creepSpeed(row: 1) * 8)
    }

    @Test("점수는 가장 앞 줄 — 뒤로 가도 안 줄고, 같은 줄을 다시 밟아도 안 오른다")
    func scoreIsMonotonicFurthestRow() {
        var game = cgGame()
        var history: [Int] = []
        for direction in [CG.Direction.forward, .forward, .forward, .back, .back, .forward, .forward, .forward] {
            game.input(direction)
            cgRun(&game, seconds: CG.hopSeconds + 0.001)
            history.append(game.score)
        }
        #expect(history == [1, 2, 3, 3, 3, 3, 3, 4], "점수 기록 \(history)")
        #expect(zip(history, history.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test("죽음 연출 동안 입력은 무시 · deathHold 뒤 결과 · 결과에서 방향키는 무시 · 클릭은 새 판(새 길 · 점수 0)")
    func overResultAndRestart() {
        var game = cgGame(lanes: [cgRiver(1, speed: 0.5, logs: [(x: -5, length: 2)])])
        let firstSeed = game.roundSeed
        game.input(.forward)
        cgRun(&game, seconds: 0.2) { $0.death != nil }
        #expect(game.isGameOver && game.isPlaying)
        game.input(.left)
        game.action()
        #expect(game.hop == nil && game.queued == nil, "죽음 연출 중 입력이 먹혔다")
        cgRun(&game, seconds: CG.deathHold + 0.05)
        #expect(game.phase == .result && !game.isPlaying)
        game.input(.forward)
        #expect(game.phase == .result, "결과 화면에서 방향키가 새 판을 열었다")
        game.action()
        #expect(game.phase == .running && game.score == 0 && game.death == nil)
        #expect(game.roundSeed != firstSeed, "새 판인데 같은 길이다")
        #expect(game.hop?.direction == .forward, "다시 하기 클릭이 첫 걸음을 안 뗐다")
    }

    @Test("끊기(interrupt): 진행 중이면 그 점수로 결과 확정 · 시작 전 · 결과면 아무 일도 없다 → 정지 상한 범위 안")
    func interruptKeepsTheScore() {
        var game = cgGame()
        for _ in 0..<3 {
            game.input(.forward)
            cgRun(&game, seconds: CG.hopSeconds + 0.001)
        }
        game.interrupt()
        #expect(game.phase == .result && game.score == 3, "끊었는데 점수가 안 남았다")
        var ready = CG(seed: 1)
        ready.interrupt()
        #expect(ready.phase == .ready)
        #expect(CheckMiniGameWindowView.PauseState.quittingKeepsTheScore(.crossy),
                "길건너가 정지 상한 밖이다 — 무기한 정지로 토큰이 TTL 을 넘긴다")
    }

    @Test("시간 하한(엔진 쪽): 연타 봇도 점수 s 를 판 시계 s × hopSeconds 전에 못 낸다 → 서버 s × 0.09 를 언제나 넘는다")
    func minimumTimeContract() {
        #expect(abs(CG.hopSeconds * CG.serverTimeMarginFactor - 0.09) < 1e-12, "서버 식 0.09 와 엔진 상수가 갈렸다")
        // ① 막힘 없는 풀밭에서 매 프레임 앞으로(줄 서기를 꽉 채운다).
        var game = cgGame()
        var firstAt: [Int: Double] = [:]
        for _ in 0..<(8 * 120) {
            let ahead = game.player.row
            for row in (ahead + 1)...(ahead + 3) { game.replaceLane(cgGrass(row)) }
            game.input(.forward)
            game.step(dt: 1.0 / 120)
            if firstAt[game.score] == nil { firstAt[game.score] = game.elapsed }
        }
        let best = game.score
        #expect(best >= 60, "봇이 \(best)줄밖에 못 갔다 — 시험이 헛돈다")
        for (score, at) in firstAt where score > 0 {
            #expect(at >= Double(score) * CG.hopSeconds - 1e-9, "점수 \(score) 를 \(at)초에 냈다(하한 \(Double(score) * CG.hopSeconds))")
            #expect(at >= Double(score) * 0.09, "서버 하한 아래")
        }
        // ② 실제 줄 위의 생존 봇(차 · 강 · 기차 그대로).
        var real = CG(seed: 314)
        real.action()
        var realFirst: [Int: Double] = [:]
        for _ in 0..<(40 * 60) where real.phase == .running {
            cgBotStep(&real)
            if realFirst[real.score] == nil { realFirst[real.score] = real.elapsed }
        }
        print("[길건너] 시간 하한: 연타 \(best)줄/8초 · 생존 봇 \(real.score)줄/\(String(format: "%.1f", real.elapsed))초(사유 \(real.death?.cause.rawValue ?? "없음"))")
        #expect(real.score >= 15, "생존 봇이 \(real.score)줄 — 판이 지나치게 어렵거나 봇이 헛돈다")
        for (score, at) in realFirst where score > 0 {
            #expect(at >= Double(score) * CG.hopSeconds - 1e-9)
        }
    }

    @Test("dt 는 1/30초로 잘린다 · 상한 5000 = MiniGameKind.crossy.maxScore")
    func stepClampAndCap() {
        var game = cgGame(lanes: [cgRoad(1, speed: 2, cars: [0])])
        game.step(dt: 5)
        #expect(abs(game.elapsed - CG.maxStep) < 1e-12)
        #expect(abs((game.lane(at: 1)?.movers.first?.x ?? 0) - 2 * CG.maxStep) < 1e-9)
        #expect(CG.maxScore == 5000 && MiniGameKind.crossy.maxScore == 5000)
    }
}

// MARK: - B 종류 · 키 · 패널

private func cgStrip(_ source: String) -> String {
    source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "//") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func cgSource(_ name: String) throws -> String {
    let url = CheckCoreSourceLayout.repoRoot.appendingPathComponent("Sources/check/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
}

/// `anchor` 다음 첫 `{` 부터 짝 맞는 `}` 까지.
private func cgBlock(after anchor: String, in source: String) -> String? {
    guard let a = source.range(of: anchor), let open = source[a.upperBound...].firstIndex(of: "{") else { return nil }
    var depth = 0
    var index = open
    while index < source.endIndex {
        if source[index] == "{" { depth += 1 }
        if source[index] == "}" {
            depth -= 1
            if depth == 0 { return String(source[open...index]) }
        }
        index = source.index(after: index)
    }
    return nil
}

@Suite("v0.3.67 길건너 아잉이 — 종류 · 키 · 패널")
struct V0367CrossyWiringTests {
    @MainActor
    @Test("MiniGameKind.crossy: 맨 뒤 · rawValue 'crossy' · '길건너 아잉이' · 실재하는 아이콘 · 상한 5000 · 토큰 재사용 = 플래피 · 폰에는 없다")
    func kindContract() {
        #expect(MiniGameKind.allCases.last == .crossy, "맨 뒤가 아니다 — 헤더 칩 · 폰 타일 자리가 밀린다")
        #expect(MiniGameKind.allCases.map(\.rawValue) == ["timing_bar", "flappy", "tetris", "crossy"])
        #expect(MiniGameKind(rawValue: "crossy") == .crossy)
        #expect(MiniGameKind.crossy.title == "길건너 아잉이")
        #expect(MiniGameKind.crossy.icon == "figure.walk")
        #expect(NSImage(systemSymbolName: MiniGameKind.crossy.icon, accessibilityDescription: nil) != nil, "없는 SF Symbol")
        #expect(Set(MiniGameKind.allCases.map(\.icon)).count == MiniGameKind.allCases.count, "아이콘이 겹친다")
        #expect(MiniGameKind.crossy.icon != MiniGameGomokuEntryButton.icon)
        #expect(MiniGameKind.crossy.maxScore == 5000)
        // 토큰: 판 시작에 거의 새것(2분) · 판 도중 20분마다 갈아 끼움 — 끝이 정해지지 않은 판이 TTL 30분에 잘리지 않게.
        #expect(MiniGameKind.crossy.roundTokenReuseSeconds == 2 * 60)
        #expect(MiniGameKind.crossy.roundTokenMidRunRefreshSeconds == 20.0 * 60)
        #expect(MiniGameKind.crossy.roundTokenMidRunRefreshSeconds! + MiniGameKind.crossy.roundTokenReuseSeconds
                + CheckMiniGameWindowView.tokenKeeperInterval < WorkTimerStore.miniGamePendingSubmitTTL,
                "판 시작 토큰 나이 + 갈아 끼우는 나이 + 감시 간격이 TTL 을 넘는다")
        for kind in [MiniGameKind.timingBar, .flappy, .tetris] {
            #expect(kind.roundTokenMidRunRefreshSeconds == nil, "\(kind) 의 판 도중 토큰 동작이 바뀌었다")
        }
        #expect(MiniGameKind.flappy.roundTokenReuseSeconds == 20 * 60 && MiniGameKind.tetris.roundTokenReuseSeconds == 12 * 60)
        #expect(MiniGameKind.macCases.contains(.crossy))
        #expect(!MiniGameKind.phoneCases.contains(.crossy) && !MiniGameKind.crossy.isPhoneSupported, "폰에 길건너가 보인다")
        #expect(MiniGameKind.tetris.isPhoneSupported && MiniGameKind.flappy.isPhoneSupported)
        for key in ["↑", "↓", "←", "→", "WASD", "스페이스"] {
            #expect(MiniGameKind.crossy.controlHint.contains(key), "조작 안내에 \(key) 가 없다")
        }
        #expect(MiniGameKind.crossy.controlHint != MiniGameKind.controlHint)
        // 일일 미션 줄 아이콘 = 종류 칩 아이콘(같은 기호를 다른 화면에서도).
        #expect(DailyMissionCopy.icon(game: "crossy") == "figure.walk")
    }

    @Test("뛰기 키 표: ↑↓←→ · WASD 를 자리로 · 그 밖은 nil · 테트리스 표는 그대로(W·A·S·D 는 저 표에서 nil)")
    func hopKeyTable() {
        let expected: [UInt16: CG.Direction] = [126: .forward, 13: .forward, 125: .back, 1: .back,
                                                123: .left, 0: .left, 124: .right, 2: .right]
        for (code, direction) in expected {
            #expect(MiniGameSpaceKey.hopDirection(forKeyCode: code) == direction, "keyCode \(code)")
        }
        for code: UInt16 in [3, 4, 5, 6, 7, 8, 9, 12, 14, 36, 48, 49, 51, 53] {
            #expect(MiniGameSpaceKey.hopDirection(forKeyCode: code) == nil, "keyCode \(code) 를 뛰기로 받는다")
        }
        for code: UInt16 in [13, 0, 1, 2] {
            #expect(MiniGameSpaceKey.Stroke.key(forKeyCode: code) == nil, "테트리스 표가 W·A·S·D(\(code)) 를 받기 시작했다")
        }
        #expect(MiniGameSpaceKey.Stroke.key(forKeyCode: 126) == .rotateCW, "테트리스 ↑ 가 바뀌었다")
    }

    @Test("뛰기 입력: 누른 순서 그대로 적고 · 한 갱신에 여럿이어도 접지 않으며 · 꼬리는 8개까지")
    func hopInputKeepsPressOrder() {
        var input = MiniGameInput()
        let before = input.hopCount
        input.recordHop(.forward)
        input.recordHop(.right)
        input.recordHop(.forward)
        #expect(input.hops(since: before) == [.forward, .right, .forward], "누른 순서가 아니다: \(input.hops(since: before))")
        let mid = input.hopCount
        input.recordHop(.left)
        #expect(input.hops(since: mid) == [.left])
        #expect(input.hops(since: input.hopCount).isEmpty)
        var flood = MiniGameInput()
        for i in 0..<12 { flood.recordHop(i.isMultiple(of: 2) ? .back : .right) }
        #expect(flood.recentHops.count == MiniGameInput.recentHopLimit)
        #expect(flood.hops(since: 0).count == MiniGameInput.recentHopLimit && flood.hops(since: 0).last == .right)
        #expect(MiniGameInput() != input, "새 칸이 Equatable 밖이다 — 화면이 뛰기를 못 본다")
        // 엔진에 순서대로 넣으면 ↑ 다음 → 는 앞 칸 다음 오른쪽 칸이다(→ 다음 ↑ 와 다르다).
        var game = cgGame()
        for direction in input.hops(since: before).prefix(2) { game.input(direction) }
        cgRun(&game, seconds: 0.3)
        #expect(game.player.row == 1 && game.player.x == 5)
    }

    @MainActor
    @Test("install 이 뛰기 처리기를 쥐고 · remove 가 놓는다(합성 이벤트 없이 발화로)")
    func installArmsTheHopHandler() {
        final class Box { var hops: [CG.Direction] = [] }
        let box = Box()
        defer { MiniGameSpaceKey.remove() }
        MiniGameSpaceKey.install(shouldConsume: { false }, action: {}, wantsHops: { true }, onHop: { box.hops.append($0) })
        MiniGameSpaceKey.fireHopForTesting(.left)
        MiniGameSpaceKey.fireHopForTesting(.forward)
        #expect(box.hops == [.left, .forward])
        MiniGameSpaceKey.remove()
        MiniGameSpaceKey.fireHopForTesting(.right)
        #expect(box.hops == [.left, .forward], "remove 뒤에도 뛰기 처리기가 살아 있다")
    }

    @Test("패널 소스 계약: 뛰기 가지는 테트리스 가지보다 앞 · 엄격한 게이트 · 스페이스 게이트 없음 · wantsHops = crossy && !얼림 · 캔버스 · 정지 문구")
    func panelWiring() throws {
        let panel = cgStrip(try cgSource("MiniGamePanel.swift"))
        let installStart = try #require(panel.range(of: "static func install(shouldConsume:"))
        let installEnd = try #require(panel.range(of: "static func remove()", range: installStart.upperBound..<panel.endIndex))
        let install = String(panel[installStart.lowerBound..<installEnd.lowerBound])
        let hopBranch = try #require(install.range(of: "if let hop, wantsHops() {"), "뛰기 가지가 없다")
        let strokeBranch = try #require(install.range(of: "if let key = stroke {"))
        #expect(hopBranch.lowerBound < strokeBranch.lowerBound, "뛰기 가지가 테트리스 가지 뒤다 — 길건너에서 ↑ 가 회전 표로 샌다")
        let branch = try #require(cgBlock(after: "if let hop, wantsHops()", in: install))
        #expect(branch.contains("strokeBelongsToGame"), "뛰기 가지가 엄격한 게이트를 안 쓴다 — 남의 창의 WASD 를 삼킨다")
        #expect(branch.contains("guard belongs else { return false }"), "게이트를 재고도 안 쓴다 — 남의 창의 WASD 를 삼킨다")
        #expect(!branch.contains("shouldConsume") && !branch.contains("yieldsToOtherWindow"), "뛰기 가지가 스페이스 게이트를 쓴다")
        #expect(branch.contains("guard !isRepeat else { return true }"), "키 반복이 뛰기가 된다")
        #expect(branch.contains("guard !hasModifier else { return false }"), "⌘W 같은 단축키를 뛰기로 삼킨다")
        let remove = try #require(cgBlock(after: "static func remove()", in: panel))
        #expect(remove.contains("armedHop = nil"))

        let installCall = try #require(cgBlock(after: "private func installSpaceKey()", in: panel))
        #expect(installCall.contains("wantsHops: { store.miniGameKind == .crossy && !pauseState.isFrozen }"))
        #expect(installCall.contains("wantsStrokes: { store.miniGameKind == .tetris && isPlaying && !pauseState.isFrozen }"),
                "테트리스 게이트가 바뀌었다")
        let handle = try #require(cgBlock(after: "private func handleHop(", in: panel))
        #expect(handle.contains("guard !pauseState.isFrozen else { return }"), "얼어 있는데 뛴다")
        #expect(handle.contains("input.recordHop(direction)"), "뛰기를 누른 순서대로 안 적는다")

        let canvas = try #require(cgBlock(after: "private func canvasStack(size: CGSize)", in: panel))
        #expect(canvas.contains("case .crossy:") && canvas.contains("CrossyGameView(host: host, input: input)"))
        let subtitle = try #require(cgBlock(after: "private var pauseSubtitle: String", in: panel))
        #expect(subtitle.contains("case .crossy:") && subtitle.contains("기록돼요"), "정지 카드가 길건너 점수가 남는다고 말하지 않는다")

        // 잎 뷰: 정적 조작 안내(타이밍 바 · 플래피 전용)를 쓰지 않는다 · 프레임 상한은 주사율에서.
        let leaf = cgStrip(try cgSource("MiniGameCrossy.swift"))
        #expect(!leaf.contains("MiniGameKind.controlHint"), "정적 조작 안내를 쓴다 — 길건너에 '클릭 또는 스페이스'가 나간다")
        #expect(leaf.contains("MiniGameFrameRate.minimumInterval(forRefreshRate: host.refreshHz)"))
        #expect(!leaf.contains("1.0 / 60.0") && !leaf.contains("1/60"))
        #expect(leaf.contains("paused: !game.isPlaying || host.isPaused"), "정지 · 결과에서도 프레임 루프가 돈다")
        #expect(leaf.contains("if new == .result, old != .result { host.onFinished(game.score) }"))
        #expect(leaf.contains("host.onPlayingChanged(playing)"), "판 시작이 허브에 안 알려진다 — 라운드 토큰을 못 받는다")
        // 3D 판은 처음 한 번만 만든다 — `@State` 면 허브가 잎 뷰를 다시 지을 때마다(정지 · 판 시작) 아잉이 모델을 다시 읽는다.
        #expect(leaf.contains("@StateObject private var scene = CrossyScene()"), "3D 판을 @StateObject 로 안 쥔다")
        // 뛰기는 한 갱신에 여럿이어도 누른 순서대로 다 넣는다(방향별 카운터 + onChange 한 번 = 접힘).
        #expect(leaf.contains("for direction in input.hops(since: old) { act { $0.input(direction) } }"),
                "뛰기 입력을 순서대로 다 안 꺼낸다(마지막 하나만 · 방향별 하나만 쓰면 접힌다)")
        #expect(!leaf.contains("hopForwardCount") && !leaf.contains("hopRightCount"), "방향별 카운터가 남았다")
        #expect(!leaf.contains("repeatForever"))
    }

    @MainActor
    @Test("헤더 실측: 칩 넷 + [일시정지] · 입구 묶음이 344pt 안에 든다 — 길건너를 골랐을 때(이름이 제일 길다)도")
    func headerFitsWithFourChips() throws {
        let budget = MiniGameWindowLayout.canvasSize.width
        for selected in MiniGameKind.macCases {
            for (playing, frozen) in [(true, false), (false, false), (true, true)] {
                let header = MiniGameGameHeader(selected: selected, isPlaying: playing, isFrozen: frozen,
                                                onSelect: { _ in }, onPause: {}, onGomoku: {}, onChess: {}, onTetrisDuel: {})
                let renderer = ImageRenderer(content: header.fixedSize())
                renderer.scale = 2
                let image = try #require(renderer.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                let width = Double(image.pixelsWide) / 2
                if selected == .crossy { print("[길건너] 헤더(\(playing ? "진행" : "시작 전")\(frozen ? "·정지" : "")): \(String(format: "%.1f", width))pt / \(budget)pt") }
                #expect(width <= budget, "\(selected) 선택 · 진행 \(playing) · 정지 \(frozen) 에서 헤더가 \(width)pt")
            }
        }
    }

    @MainActor
    @Test("결과 카드 글자: 사유 · 최고/신기록 · 다시 하기는 클릭·스페이스(방향키 아님)")
    func resultCopy() {
        #expect(CrossyHUD.resultSubtitle(score: 12, best: 30, cause: .water) == "물에 빠졌어요 · 최고 30")
        #expect(CrossyHUD.resultSubtitle(score: 31, best: 30, cause: .train) == "신기록! · 기차에 치였어요")
        #expect(CrossyHUD.resultSubtitle(score: 3, best: 9, cause: nil) == "최고 9")
        #expect(CG.DeathCause.leftBehind.caption == "놓쳤어요")
        #expect(Set(CG.DeathCause.allCases.map(\.caption)).count == CG.DeathCause.allCases.count)
        #expect(!CrossyHUD.retryAction.contains("방향키"))
        #expect(CrossyHUD.startAction.contains("방향키"))
    }
}

// MARK: - C 스토어(대본 네트워크)

@MainActor
private func cgStore(host: String, defaults: UserDefaults? = nil, function: String = #function) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: V0367AllTimeURLProtocol.session()
    )
    let home = CheckTestScratch.directory("token-" + host, function: function)
    let tokens = TokenUsageStore(
        defaults: CheckTestScratch.defaults("token-" + host, function: function),
        homeDirectory: home.appendingPathComponent("home", isDirectory: true),
        cacheURL: home.appendingPathComponent("cache.json", isDirectory: false)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults ?? CheckTestScratch.defaults(host, function: function),
        tokenUsage: tokens
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID
    return store
}

@MainActor
@discardableResult
private func cgWait(_ timeout: Double = 3, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

@MainActor
@Suite("v0.3.67 길건너 아잉이 — 스토어 배선", .serialized)
struct V0367CrossyStoreTests {
    @Test("라운드 토큰: 판 시작이 minigame_start_round(p_game crossy) · 끝난 판이 그 토큰으로 minigame_submit_score(crossy, 점수)")
    func roundTokenAndSubmit() async throws {
        let host = "crossy-token.test"
        V0367AllTimeURLProtocol.script(host, path: "/rest/v1/rpc/minigame_start_round", game: "crossy",
                                       [.init(status: 200, body: #"{"status":"ok","token":"tok-crossy-1"}"#)])
        V0367AllTimeURLProtocol.script(host, path: "/rest/v1/rpc/minigame_submit_score", game: "crossy",
                                       [.init(status: 200, body: #"{"status":"ok","best_score":42,"plays":1,"improved":true}"#)])
        let store = cgStore(host: host)
        store.selectMiniGame(.crossy)
        #expect(store.miniGameKind == .crossy)
        store.beginMiniGameRound(kind: .crossy)
        await cgWait { store.hasUsableMiniGameToken(for: .crossy) }
        #expect(store.hasUsableMiniGameToken(for: .crossy), "crossy 토큰을 못 받았다")
        let starts = V0367AllTimeURLProtocol.calls(host, path: "/rest/v1/rpc/minigame_start_round")
        #expect(starts.contains { $0.game == "crossy" }, "판 시작 요청이 crossy 가 아니다: \(starts.map(\.game))")

        store.recordMiniGameScore(kind: .crossy, score: 42)
        await cgWait { !V0367AllTimeURLProtocol.calls(host, path: "/rest/v1/rpc/minigame_submit_score").isEmpty && !store.hasMiniGamePendingSubmit(for: .crossy) }
        let submits = V0367AllTimeURLProtocol.calls(host, path: "/rest/v1/rpc/minigame_submit_score")
        let submit = try #require(submits.first)
        let body = try #require(try JSONSerialization.jsonObject(with: Data(submit.body.utf8)) as? [String: Any])
        #expect(body["p_game"] as? String == "crossy" && body["p_score"] as? Int == 42 && body["p_token"] as? String == "tok-crossy-1",
                "제출 본문: \(submit.body)")
        #expect(store.miniGameBest(.crossy) == 42)
        #expect(store.miniGameBest(.flappy) == 0, "길건너 최고가 다른 게임 칸에 섞였다")
        // 상한(5000) 초과는 업로드하지 않는다(클램프가 아니라 버린다 — 다른 게임과 같은 게이트).
        store.recordMiniGameScore(kind: .crossy, score: 5001)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(V0367AllTimeURLProtocol.calls(host, path: "/rest/v1/rpc/minigame_submit_score").count == 1)
        #expect(store.miniGameBest(.crossy) == 42)
    }

    @Test("순위: crossy 를 고르면 오늘 순위 · 어제 1등을 p_game crossy 로 받고 · [역대] 도 crossy 로 받는다")
    func boardsFollowCrossy() async throws {
        let host = "crossy-boards.test"
        V0367AllTimeURLProtocol.script(host, path: "/rest/v1/rpc/minigame_board", game: "crossy", [.init(status: 200, body: """
        [{"user_id":"cccccccc-0000-0000-0000-000000000001","display_name":"길왕","avatar_url":null,"best_score":88,"best_at":"2026-10-27T01:00:00Z","plays":3,"center":null}]
        """)])
        V0367AllTimeURLProtocol.script(host, path: "/rest/v1/rpc/minigame_yesterday_winner", game: "crossy", [.init(status: 200, body: """
        [{"day":"2026-10-26","user_id":"cccccccc-0000-0000-0000-000000000009","display_name":"어제왕","avatar_url":null,"score":120,"awarded":true,"center":null}]
        """)])
        V0367AllTimeURLProtocol.script(host, path: "/rest/v1/rpc/minigame_alltime_board", game: "crossy", [.init(status: 200, body: """
        [{"user_id":"cccccccc-0000-0000-0000-000000000003","display_name":"역대왕","avatar_url":null,"best_score":456,"best_at":"2026-10-20T05:00:00Z","day":"2026-10-20","center":null}]
        """)])
        let store = cgStore(host: host)
        store.selectMiniGame(.crossy)
        await store.performLoadMiniGameBoard()
        #expect(store.miniGameBoard.first?.name == "길왕" && store.miniGameBoard.first?.bestScore == 88)
        #expect(store.miniGameYesterdayWinner?.name == "어제왕" && store.miniGameYesterdayWinner?.score == 120)
        store.selectMiniGameBoardScope(.allTime)
        await cgWait { store.miniGameAllTimeLoaded || store.miniGameAllTimeFailed }
        #expect(store.miniGameAllTimeBoard.first?.name == "역대왕" && store.miniGameAllTimeBoard.first?.bestScore == 456)
        let calls = V0367AllTimeURLProtocol.allCalls(host).filter { $0.path.contains("minigame_") }
        #expect(calls.allSatisfy { $0.game == "crossy" }, "다른 게임 순위를 물었다: \(calls.map { "\($0.path) \($0.game ?? "-")" })")
        for path in ["minigame_board", "minigame_yesterday_winner", "minigame_alltime_board"] {
            #expect(calls.contains { $0.path.hasSuffix(path) }, "\(path) 를 안 불렀다")
        }
    }

    @Test("저장된 선택 복원: 'crossy' 를 저장해 두면 다음 실행에 길건너로 열린다(모르는 값으로 접지 않는다)")
    func storedKindRestores() {
        let host = "crossy-restore.test"
        let defaults = CheckTestScratch.defaults(host)
        let first = cgStore(host: host, defaults: defaults)
        first.selectMiniGame(.crossy)
        let second = cgStore(host: host, defaults: defaults)
        #expect(second.miniGameKind == .crossy, "저장된 crossy 가 타이밍 바로 접혔다")
    }

    // MARK: 토큰 수명(검토 지적 1)

    @Test("판 시작 토큰: 길건너는 2분 넘은 토큰을 안 쓴다(새로 받는다) · 1분이면 쓴다 · 플래피는 15분도 쓴다")
    func runStartTokenIsFresh() async {
        let host = "crossy-token-age.test"
        let store = cgStore(host: host)
        store.miniGameRoundToken = "tok-old"
        store.miniGameRoundTokenKind = .crossy
        store.miniGameRoundTokenAt = Date().addingTimeInterval(-3 * 60)
        #expect(!store.hasUsableMiniGameToken(for: .crossy), "3분 묵은 길건너 토큰을 판 시작에 그대로 쓴다")
        store.beginMiniGameRound(kind: .crossy)
        await cgWait { store.miniGameRoundToken == "tok-next" }
        #expect(store.miniGameRoundToken == "tok-next", "판 시작에 새 토큰을 안 받았다")
        store.miniGameRoundTokenAt = Date().addingTimeInterval(-60)
        #expect(store.hasUsableMiniGameToken(for: .crossy))
        store.miniGameRoundToken = "tok-flappy"
        store.miniGameRoundTokenKind = .flappy
        store.miniGameRoundTokenAt = Date().addingTimeInterval(-15 * 60)
        #expect(store.hasUsableMiniGameToken(for: .flappy), "플래피의 토큰 재사용이 바뀌었다")
    }

    @Test("판 도중 토큰 갈아 끼우기: 길건너 토큰이 20분 넘으면 새로 받아 그 토큰으로 제출 · 젊으면 · 다른 게임이면 · 인편이 있으면 안 받는다")
    func midRunRefreshKeepsLongRunsAlive() async throws {
        let host = "crossy-midrun.test"
        V0367AllTimeURLProtocol.script(host, path: "/rest/v1/rpc/minigame_start_round", game: "crossy",
                                       [.init(status: 200, body: #"{"status":"ok","token":"tok-fresh"}"#)])
        let store = cgStore(host: host)
        store.miniGameKind = .crossy
        func starts() -> Int { V0367AllTimeURLProtocol.calls(host, path: "/rest/v1/rpc/minigame_start_round").count }

        // 젊은 토큰(5분) — 안 받는다.
        store.miniGameRoundToken = "tok-start"
        store.miniGameRoundTokenKind = .crossy
        store.miniGameRoundTokenAt = Date().addingTimeInterval(-5 * 60)
        store.keepMiniGameRoundTokenFresh(kind: .crossy)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(starts() == 0, "젊은 토큰을 갈아 끼웠다")
        // 다른 게임(플래피 25분) — 판 도중 갈아 끼우지 않는 게임이다.
        store.keepMiniGameRoundTokenFresh(kind: .flappy)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(starts() == 0, "플래피 판 도중에 토큰을 갈아 끼웠다")

        // 21분 — 갈아 끼운다. 29분째에 끝난 판은 새 토큰으로 올라간다(옛 토큰이면 token_expired).
        store.miniGameRoundTokenAt = Date().addingTimeInterval(-21 * 60)
        store.keepMiniGameRoundTokenFresh(kind: .crossy)
        await cgWait { store.miniGameRoundToken == "tok-fresh" }
        #expect(starts() == 1 && store.miniGameRoundToken == "tok-fresh", "늙은 토큰을 안 갈아 끼웠다")
        #expect(store.miniGameRoundTokenAt.map { Date().timeIntervalSince($0) < 5 } ?? false)
        store.recordMiniGameScore(kind: .crossy, score: 812)
        await cgWait { !V0367AllTimeURLProtocol.calls(host, path: "/rest/v1/rpc/minigame_submit_score").isEmpty }
        let submit = try #require(V0367AllTimeURLProtocol.calls(host, path: "/rest/v1/rpc/minigame_submit_score").first)
        #expect(submit.body.contains("tok-fresh") && submit.body.contains("812"), "갈아 끼운 토큰으로 안 올렸다: \(submit.body)")

        // 인편이 살아 있으면 갈아 끼우지 않는다(새 토큰이 인편의 옛 토큰을 죽인다 — 불변식).
        let held = cgStore(host: "crossy-midrun-pending.test")
        held.miniGameKind = .crossy
        held.miniGamePendingSubmits = [MiniGamePendingSubmit(id: UUID(), kind: .crossy, score: 3, token: "tok-pending",
                                                             tokenIssuedAt: Date(), recordedAt: Date(), attempts: 0)]
        held.miniGamePendingSubmitsOwner = held.session?.userID
        held.miniGameRoundToken = nil
        held.keepMiniGameRoundTokenFresh(kind: .crossy)
        await cgWait { !V0367AllTimeURLProtocol.allCalls("crossy-midrun-pending.test").isEmpty }
        try? await Task.sleep(for: .milliseconds(80))
        // 인편을 **먼저** 민다 — start_round 는 (나간다면) 그 인편 제출이 끝난 뒤의 꼬리 선발급뿐이다.
        let order = V0367AllTimeURLProtocol.allCalls("crossy-midrun-pending.test")
            .map(\.path).filter { $0.hasSuffix("minigame_submit_score") || $0.hasSuffix("minigame_start_round") }
        #expect(order.first?.hasSuffix("minigame_submit_score") == true,
                "인편이 있는데 start_round 가 먼저 나갔다 — 인편의 토큰이 죽는다: \(order)")
    }

    @Test("토큰 감시(허브 소스 계약): 판 시작에 걸고 · 끝 · 접기 · 사라짐에 거두며 · 30초마다 스토어에 묻는다")
    func tokenKeeperIsWired() throws {
        let panel = cgStrip(try cgSource("MiniGamePanel.swift"))
        let arm = try #require(cgBlock(after: "private func armTokenKeeper(kind: MiniGameKind)", in: panel))
        #expect(arm.contains("guard kind.roundTokenMidRunRefreshSeconds != nil else { return }"))
        #expect(arm.contains("store.keepMiniGameRoundTokenFresh(kind: kind)") && arm.contains("Self.tokenKeeperInterval"))
        let host = try #require(cgBlock(after: "private var host: MiniGameHost", in: panel))
        let playingBranch = try #require(cgBlock(after: "if playing", in: host))
        #expect(playingBranch.contains("armTokenKeeper(kind: kind)"), "판 시작에 토큰 감시를 안 건다")
        let endingBranch = try #require(cgBlock(after: "if !playing", in: host))
        #expect(endingBranch.contains("cancelTokenKeeper()"), "판이 끝나도 토큰 감시가 돈다")
        let interrupt = try #require(cgBlock(after: ".onChange(of: store.miniGameInterruptToken)", in: panel))
        #expect(interrupt.contains("cancelTokenKeeper()"))
        let disappear = try #require(cgBlock(after: ".onDisappear", in: panel))
        #expect(disappear.contains("cancelTokenKeeper()"))
    }

    // MARK: 접힌 판의 점수(검토 지적 7)

    @Test("장부: 멈춰 둔 플래피 판에서 다른 칩을 누르면 그 점수가 바로 올라가고, 늦게 온 onFinished 는 두 번 안 올린다")
    func switchingGamesKeepsTheScore() async {
        let host = "crossy-ledger-switch.test"
        let store = cgStore(host: host)
        store.selectMiniGame(.flappy)
        await cgWait { store.hasUsableMiniGameToken(for: .flappy) }   // 판을 하던 중이면 토큰은 이미 와 있다
        store.beginMiniGameLiveRound(kind: .flappy)
        for score in 1...13 { store.noteMiniGameLiveScore(kind: .flappy, score: score) }
        store.selectMiniGame(.crossy)              // 잎 뷰는 이 갱신에서 사라진다 — interrupt 를 못 본다
        await cgWait { V0367AllTimeURLProtocol.calls(host, path: "/rest/v1/rpc/minigame_submit_score").count >= 1 }
        store.finishMiniGameLiveRound(kind: .flappy, score: 13)   // (살아 있었다면) 늦게 온 잎 뷰의 끝
        try? await Task.sleep(for: .milliseconds(100))
        let submits = V0367AllTimeURLProtocol.calls(host, path: "/rest/v1/rpc/minigame_submit_score")
        #expect(submits.count == 1, "칩 전환 판이 \(submits.count)번 올라갔다")
        #expect(submits.first.map { $0.game == "flappy" && $0.body.contains("\"p_score\":13") } ?? false,
                "칩 전환에서 플래피 13점이 안 올라갔다: \(submits.map(\.body))")
    }

    @Test("장부: 타이밍 바는 접으면 무효(안 올림) · 길건너 창 닫기 · [그만두기] · 로그아웃은 올림 · 자연 종료 뒤 접기는 두 번 안 올림")
    func settlingFollowsQuittingKeepsTheScore() async {
        func submits(_ host: String) -> [V0367AllTimeURLProtocol.Call] {
            V0367AllTimeURLProtocol.calls(host, path: "/rest/v1/rpc/minigame_submit_score")
        }
        let timing = "crossy-ledger-timing.test"
        let t = cgStore(host: timing)
        t.prefetchMiniGameRoundToken(kind: .timingBar)
        await cgWait { t.hasUsableMiniGameToken(for: .timingBar) }
        t.beginMiniGameLiveRound(kind: .timingBar)
        t.noteMiniGameLiveScore(kind: .timingBar, score: 500)
        t.selectMiniGame(.crossy)
        #expect(!t.hasMiniGamePendingSubmit(for: .timingBar), "타이밍 바를 접었는데 점수를 인편에 적었다 — 정지 카드는 '기록되지 않아요' 라고 했다")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(submits(timing).isEmpty, "타이밍 바를 접었는데 점수가 올라갔다")

        let close = "crossy-ledger-close.test"
        let c = cgStore(host: close)
        c.selectMiniGame(.crossy)
        await cgWait { c.hasUsableMiniGameToken(for: .crossy) }
        c.isMiniGamePanelVisible = true
        c.beginMiniGameLiveRound(kind: .crossy)
        c.noteMiniGameLiveScore(kind: .crossy, score: 7)
        c.closeMiniGamePanel()
        await cgWait { !submits(close).isEmpty }
        #expect(submits(close).first.map { $0.game == "crossy" && $0.body.contains("\"p_score\":7") } ?? false, "창 닫기에서 길건너 7점이 안 올라갔다")

        let quit = "crossy-ledger-quit.test"
        let q = cgStore(host: quit)
        q.selectMiniGame(.tetris)
        await cgWait { q.hasUsableMiniGameToken(for: .tetris) }
        q.beginMiniGameLiveRound(kind: .tetris)
        q.noteMiniGameLiveScore(kind: .tetris, score: 4200)
        q.abortMiniGameRound()
        q.finishMiniGameLiveRound(kind: .tetris, score: 4200)
        await cgWait { !submits(quit).isEmpty }
        try? await Task.sleep(for: .milliseconds(80))
        #expect(submits(quit).count == 1 && submits(quit).first?.game == "tetris", "[그만두기] 판: \(submits(quit).map(\.body))")

        let natural = "crossy-ledger-natural.test"
        let n = cgStore(host: natural)
        n.selectMiniGame(.crossy)
        await cgWait { n.hasUsableMiniGameToken(for: .crossy) }
        n.beginMiniGameLiveRound(kind: .crossy)
        n.noteMiniGameLiveScore(kind: .crossy, score: 30)
        n.finishMiniGameLiveRound(kind: .crossy, score: 30)
        n.selectMiniGame(.flappy)
        await cgWait { !submits(natural).isEmpty }
        try? await Task.sleep(for: .milliseconds(80))
        #expect(submits(natural).count == 1, "자연 종료 뒤 칩 전환이 한 번 더 올렸다")

        let out = "crossy-ledger-signout.test"
        let o = cgStore(host: out)
        o.selectMiniGame(.crossy)
        o.beginMiniGameLiveRound(kind: .crossy)
        o.noteMiniGameLiveScore(kind: .crossy, score: 11)
        let owner = o.session?.userID
        o.clearPersistedSession()
        #expect(o.miniGameLiveRound?.settled == true)
        let saved = owner.flatMap { o.defaults.data(forKey: WorkTimerStore.miniGamePendingKey(userID: $0)) } ?? Data()
        #expect(String(decoding: saved, as: UTF8.self).contains("\"score\":11"), "로그아웃 직전 판이 그 계정 인편으로 안 남았다")
    }

    @Test("장부 배선(소스 계약): 허브의 끝은 장부로 · 판 시작이 장부를 연다 · 접는 문 다섯이 토큰보다 먼저 접는다 · 잎 셋이 점수를 알린다")
    func ledgerIsWired() throws {
        let panel = cgStrip(try cgSource("MiniGamePanel.swift"))
        #expect(panel.contains("onFinished: { score in store.finishMiniGameLiveRound(kind: kind, score: score) }"))
        #expect(!panel.contains("onFinished: { score in store.recordMiniGameScore"), "허브가 장부를 건너뛰고 올린다 — 두 번 올라간다")
        #expect(panel.contains("onScoreChanged: { score in store.noteMiniGameLiveScore(kind: kind, score: score) }"))
        let host = try #require(cgBlock(after: "private var host: MiniGameHost", in: panel))
        let playingBranch = try #require(cgBlock(after: "if playing", in: host))
        #expect(playingBranch.contains("store.beginMiniGameLiveRound(kind: kind)"))
        let store = cgStrip(try cgSource("WorkTimerStoreMiniGame.swift"))
        for anchor in ["func selectMiniGame(_ kind: MiniGameKind)", "func closeMiniGamePanel()", "func abortMiniGameRound()"] {
            let body = try #require(cgBlock(after: anchor, in: store))
            let settle = try #require(body.range(of: "settleMiniGameLiveRound()"), "\(anchor) 가 판을 안 접는다")
            if let token = body.range(of: "miniGameInterruptToken += 1") {
                #expect(settle.lowerBound < token.lowerBound, "\(anchor) 가 토큰을 올린 뒤에 접는다")
            }
            if let kindChange = body.range(of: "miniGameKind = kind") {
                #expect(settle.lowerBound < kindChange.lowerBound, "\(anchor) 가 종류를 바꾼 뒤에 접는다 — 남의 게임으로 올라간다")
            }
        }
        let window = cgStrip(try cgSource("CheckMiniGameWindow.swift"))
        let endRound = try #require(cgBlock(after: "private func endRound(closing: Bool)", in: window))
        let settleAt = try #require(endRound.range(of: "store.settleMiniGameLiveRound()"), "창 닫기가 판을 안 접는다")
        let tokenAt = try #require(endRound.range(of: "store.miniGameInterruptToken += 1"))
        #expect(settleAt.lowerBound < tokenAt.lowerBound)
        let main = cgStrip(try cgSource("WorkTimerStore.swift"))
        let clear = try #require(cgBlock(after: "func clearPersistedSession()", in: main))
        let clearSettle = try #require(clear.range(of: "settleMiniGameLiveRound()"), "로그아웃이 판을 안 접는다")
        let sessionNil = try #require(clear.range(of: "session = nil"))
        #expect(clearSettle.lowerBound < sessionNil.lowerBound, "세션을 지운 뒤에 접는다 — 인편을 못 적는다")
        // 플래피·테트리스는 쪼갠 파일이다 — 조각을 이어 읽는다(반쪽 읽기 금지, CheckCoreSourceLayoutTests).
        let games: [(String, String)] = [
            ("플래피", try CheckCoreSourceLayout.joinedSplitSource("MiniGameFlappy.swift")),
            ("테트리스", try CheckCoreSourceLayout.joinedSplitSource("MiniGameTetris.swift")),
            ("길건너", try CheckCoreSourceLayout.joinedSplitSource("MiniGameCrossy.swift")),
        ]
        for (game, source) in games {
            #expect(cgStrip(source).contains("host.onScoreChanged(score)"), "\(game) 화면이 진행 중 점수를 안 알린다")
        }
    }

    // MARK: 역대 표 최신 표시 경합(검토 지적 6)

    @Test("역대 표: 제출 전에 떠난 받기가 제출 뒤에 닿으면 '최신'으로 표시하지 않는다 → [역대] 로 다시 넘어가면 또 받는다")
    func allTimeFetchStartedBeforeASubmitIsNotFresh() async {
        let host = "crossy-alltime-race.test"
        V0367AllTimeURLProtocol.script(host, path: "/rest/v1/rpc/minigame_alltime_board", game: "crossy", [
            .init(status: 200, body: "[]", delay: 0.4),
            .init(status: 200, body: "[]"),
        ])
        let store = cgStore(host: host)
        store.selectMiniGame(.crossy)
        await cgWait { store.hasUsableMiniGameToken(for: .crossy) }
        func fetches() -> Int { V0367AllTimeURLProtocol.calls(host, path: "/rest/v1/rpc/minigame_alltime_board").count }
        store.selectMiniGameBoardScope(.allTime)      // 받기 A 떠남(0.4초 뒤 닿는다)
        await cgWait { fetches() == 1 }
        store.selectMiniGameBoardScope(.today)        // [오늘] 로 돌아온 사이
        store.recordMiniGameScore(kind: .crossy, score: 99)   // 판이 기록됐다 — 역대는 낡았다(보는 중이 아니라 다시 받지 않는다)
        await cgWait { !V0367AllTimeURLProtocol.calls(host, path: "/rest/v1/rpc/minigame_submit_score").isEmpty && !store.hasMiniGamePendingSubmit(for: .crossy) }
        await cgWait(2) { store.miniGameAllTimeLoaded }          // A 가 늦게 닿는다
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.miniGameAllTimeFreshKind == nil, "제출 전에 떠난 받기가 '최신'으로 표시됐다 — 새 개인 최고가 빠진 표를 다시 안 받는다")
        store.selectMiniGameBoardScope(.allTime)
        await cgWait { fetches() == 2 }
        #expect(fetches() == 2, "[역대] 로 다시 넘어갔는데 안 받았다(\(fetches())번)")
    }

    @Test("역대 표: 늦게 닿은 옛 받기가 새 받기의 표를 덮지 않는다")
    func olderAllTimeFetchDoesNotOverwriteNewer() async {
        let host = "crossy-alltime-order.test"
        V0367AllTimeURLProtocol.script(host, path: "/rest/v1/rpc/minigame_alltime_board", game: "crossy", [
            .init(status: 200, body: #"[{"user_id":"cccccccc-0000-0000-0000-00000000000a","display_name":"옛표","avatar_url":null,"best_score":10,"best_at":"2026-10-01T00:00:00Z","day":"2026-10-01","center":null}]"#, delay: 0.4),
            .init(status: 200, body: #"[{"user_id":"cccccccc-0000-0000-0000-00000000000b","display_name":"새표","avatar_url":null,"best_score":20,"best_at":"2026-10-02T00:00:00Z","day":"2026-10-02","center":null}]"#),
        ])
        let store = cgStore(host: host)
        store.selectMiniGame(.crossy)
        store.selectMiniGameBoardScope(.allTime)       // 옛 받기(느림)
        await cgWait { V0367AllTimeURLProtocol.calls(host, path: "/rest/v1/rpc/minigame_alltime_board").count == 1 }
        await store.performLoadMiniGameAllTimeBoard()  // 새 받기(빠름) — 먼저 닿는다
        #expect(store.miniGameAllTimeBoard.first?.name == "새표")
        try? await Task.sleep(for: .milliseconds(600))  // 옛 받기가 닿는다
        #expect(store.miniGameAllTimeBoard.first?.name == "새표", "늦게 닿은 옛 받기가 새 표를 덮었다")
    }
}

// MARK: - D 그림(오프스크린 SCNRenderer)

/// 증거 PNG 크기(344×356pt @2x — 시안과 같다).
private let cgPixelSize = CGSize(width: 688, height: 712)

@MainActor
private func cgSnapshot(_ scene: CrossyScene, _ game: CrossyGame, reduceMotion: Bool = false) throws -> CGImage {
    scene.apply(game, reduceMotion: reduceMotion)
    let device = try #require(MTLCreateSystemDefaultDevice(), "Metal 이 없다")
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = scene.scene
    renderer.pointOfView = scene.cameraNode
    renderer.autoenablesDefaultLighting = false
    let image = renderer.snapshot(atTime: 0, with: cgPixelSize, antialiasingMode: .multisampling4X)
    let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    // 오프스크린 스냅숏은 크기를 픽셀로 받기도, 포인트로 받기도 한다(맥 배율) — 증거는 언제나 688×712 로 맞춘다.
    if cg.width == Int(cgPixelSize.width), cg.height == Int(cgPixelSize.height) { return cg }
    let ctx = try #require(CGContext(data: nil, width: Int(cgPixelSize.width), height: Int(cgPixelSize.height), bitsPerComponent: 8,
                                     bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(origin: .zero, size: cgPixelSize))
    return try #require(ctx.makeImage())
}

/// 3D 위에 글자 겹(`CrossyHUD` — ImageRenderer 로 찍히는 쪽)을 얹은 한 장.
@MainActor
private func cgComposite(_ scene: CGImage, game: CrossyGame, best: Int) throws -> NSBitmapImageRep {
    let hud = CrossyHUD(game: game, bestScore: best)
        .frame(width: MiniGameWindowLayout.canvasSize.width, height: MiniGameWindowLayout.canvasSize.height)
        .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: hud)
    renderer.scale = 2
    let overlay = try #require(renderer.cgImage)
    let w = Int(cgPixelSize.width), h = Int(cgPixelSize.height)
    let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    let rect = CGRect(x: 0, y: 0, width: w, height: h)
    cg.addPath(CGPath(roundedRect: rect, cornerWidth: 20, cornerHeight: 20, transform: nil))
    cg.clip()
    cg.draw(scene, in: rect)
    cg.draw(overlay, in: rect)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

private func cgSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    MiniGameSnapshots.save(bitmap, name: name + ".png", sub: "crossy")
}

private func cgBitmap(_ image: CGImage) -> NSBitmapImageRep { NSBitmapImageRep(cgImage: image) }

/// 두 장이 다른 픽셀의 경계 상자(px). 같으면 nil.
private func cgDiffBounds(_ a: CGImage, _ b: CGImage, tolerance: Int = 10) -> CGRect? {
    let ra = cgBitmap(a), rb = cgBitmap(b)
    guard ra.pixelsWide == rb.pixelsWide, ra.pixelsHigh == rb.pixelsHigh, let pa = ra.bitmapData, let pb = rb.bitmapData else { return nil }
    let bpr = ra.bytesPerRow, spp = ra.samplesPerPixel
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<ra.pixelsHigh {
        for x in 0..<ra.pixelsWide {
            let o = y * bpr + x * spp
            if (0..<3).contains(where: { abs(Int(pa[o + $0]) - Int(pb[o + $0])) > tolerance }) {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

/// 서로 다른 색 수(대략 — 6비트로 접어 센다). 빈 판(한 색)인지 가른다.
private func cgColorCount(_ image: CGImage) -> Int {
    let rep = cgBitmap(image)
    guard let p = rep.bitmapData else { return 0 }
    var seen = Set<Int>()
    let bpr = rep.bytesPerRow, spp = rep.samplesPerPixel
    for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            let o = y * bpr + x * spp
            seen.insert((Int(p[o]) >> 2) << 12 | (Int(p[o + 1]) >> 2) << 6 | (Int(p[o + 2]) >> 2))
        }
    }
    return seen.count
}

/// 죽음 장면 하나 — 시작 근처 줄에 판을 세우고 사유가 날 때까지 흘린 뒤 연출 `after` 초를 더 흘린다.
private func cgDeathScene(_ cause: CG.DeathCause, after: Double = 0.30) -> CG {
    var game: CG
    switch cause {
    case .car:
        game = cgGame(lanes: [cgRoad(1, direction: 1, speed: 2.5, cars: [0.4]), cgRoad(2, direction: -1, speed: 2, cars: [7, 1.5])])
        game.placePlayerForTesting(row: 1, x: 4)
    case .water:
        game = cgGame(lanes: [cgRiver(1, direction: 1, speed: 0.6, logs: [(x: -3, length: 3), (x: 6.5, length: 3)]),
                              cgRiver(2, direction: -1, speed: 0.8, logs: [(x: 1, length: 4)])])
        game.input(.forward)
    case .carriedOff:
        game = cgGame(lanes: [cgRiver(1, direction: 1, speed: 2.5, logs: [(x: 6.0, length: 4)]),
                              cgRiver(2, direction: -1, speed: 0.8, logs: [(x: 1, length: 4)])])
        game.placePlayerForTesting(row: 1, x: 7.6, riding: true)
    case .train:
        game = cgGame(lanes: [cgRail(1, direction: 1, countdown: 0.2), cgGrass(2, blocked: [1, 7])])
        game.placePlayerForTesting(row: 1, x: 4)
    case .leftBehind:
        game = cgGame(lanes: [cgRoad(1, direction: 1, speed: 2, cars: [6]), cgGrass(3, blocked: [2, 6])])
        game.placePlayerForTesting(row: 0, x: 4)
    }
    cgRun(&game, seconds: 12, dt: 1.0 / 120) { $0.death != nil }
    cgRun(&game, seconds: after, dt: 1.0 / 120)
    return game
}

@MainActor
@Suite("v0.3.67 길건너 아잉이 — 그림(SceneKit)", .serialized)
struct V0367CrossyRenderTests {
    @Test("증거: 시작 · 중간 · 뛰는 중 · 죽음 다섯을 오프스크린으로 찍는다 — 판마다 그림이 다르고 비어 있지 않다")
    func evidenceFrames() throws {
        let scene = CrossyScene()
        #expect(scene.loadedModel, "aing.scn 을 못 읽었다 — 보라 공으로 그렸다")
        var shots: [(String, CGImage)] = []

        // 시작(준비) — 시작 카드가 얹힌다.
        let ready = CG(seed: 20261027)
        let start = try cgSnapshot(scene, ready)
        cgSave(try cgComposite(start, game: ready, best: 0), "crossy-start")
        shots.append(("start", start))

        // 중간 — 생존 봇이 실제 줄을 6초 논 판.
        var mid = CG(seed: 20261027)
        mid.action()
        for _ in 0..<(6 * 60) where mid.phase == .running { cgBotStep(&mid) }
        // 다음 착지 전 가운데(뛰는 모습)를 피하려고 서 있는 순간까지 조금 더.
        for _ in 0..<30 where mid.hop != nil && mid.phase == .running { mid.step(dt: 1.0 / 120) }
        #expect(mid.phase == .running && mid.score >= 5, "중간 장면 봇이 \(mid.score)줄에서 \(mid.death?.cause.rawValue ?? "?")")
        let midScene = CrossyScene()
        _ = try cgSnapshot(midScene, mid)                 // 카메라 가로 따라가기가 자리 잡게 한 번 먼저
        let midShot = try cgSnapshot(midScene, mid)
        cgSave(try cgComposite(midShot, game: mid, best: 30), "crossy-mid")
        shots.append(("mid", midShot))

        // 뛰는 중(늘이기 · 들어 올림 · 작아진 그림자).
        var hop = cgGame(lanes: [cgRoad(2, direction: 1, speed: 2, cars: [1]), cgRiver(4, logs: [(x: 2, length: 3)])])
        hop.input(.forward)
        cgRun(&hop, seconds: CG.hopSeconds / 2)
        let hopShot = try cgSnapshot(CrossyScene(), hop)
        cgSave(try cgComposite(hopShot, game: hop, best: 0), "crossy-hop")
        shots.append(("hop", hopShot))

        for cause in CG.DeathCause.allCases {
            let game = cgDeathScene(cause)
            #expect(game.death?.cause == cause, "\(cause) 장면이 \(game.death?.cause.rawValue ?? "죽지 않음") 으로 끝났다")
            let shot = try cgSnapshot(CrossyScene(), game)
            cgSave(try cgComposite(shot, game: game, best: 9), "crossy-death-\(cause.rawValue)")
            shots.append((cause.rawValue, shot))
            // 결과 카드까지(연출이 끝난 뒤).
            var result = game
            cgRun(&result, seconds: CG.deathHold, dt: 1.0 / 60)
            if cause == .train || cause == .car {
                let card = try cgSnapshot(CrossyScene(), result)
                cgSave(try cgComposite(card, game: result, best: 9), "crossy-result-\(cause.rawValue)")
            }
        }
        print("[길건너] 증거 PNG → \(MiniGameSnapshots.directory("crossy").path)")
        for (name, image) in shots {
            let colors = cgColorCount(image)
            #expect(colors > 60, "\(name) 장면이 거의 한 색이다(\(colors)색) — 빈 판")
        }
        for i in shots.indices {
            for j in shots.indices where j > i {
                #expect(cgDiffBounds(shots[i].1, shots[j].1) != nil, "\(shots[i].0) 와 \(shots[j].0) 가 같은 그림이다")
            }
        }
    }

    @Test("기찻길 경고: 경고 중에는 레일이 붉게 깜빡인다(기둥이 화면 밖이어도 보이게) · 꺼진 박자 · 먼 기차는 안 붉다")
    func railWarningFlashesTheTrack() throws {
        func redPixels(_ image: CGImage) -> Int {
            // 스냅숏의 바이트 순서는 렌더러가 정한다(알파가 앞일 수 있다) — RGBA 문맥에 다시 그려 순서를 못 박고 센다.
            let w = image.width, h = image.height
            var px = [UInt8](repeating: 0, count: w * h * 4)
            let drawn: Bool = px.withUnsafeMutableBytes { buffer in
                guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return 0 }
            var count = 0
            for i in stride(from: 0, to: px.count, by: 4) where px[i] > 200 && px[i + 1] < 110 && px[i + 2] < 110 { count += 1 }
            return count
        }
        func scene(countdown: Double, run: Double) throws -> CGImage {
            var game = cgGame(lanes: [cgRail(1, direction: 1, countdown: countdown), cgGrass(2, blocked: [2])])
            cgRun(&game, seconds: run)
            return try cgSnapshot(CrossyScene(), game)
        }
        let warnOn = try scene(countdown: 0.8, run: 0.05)      // 경고 · 켜진 박자(0~0.15초)
        let warnOff = try scene(countdown: 0.8, run: 0.20)     // 경고 · 꺼진 박자(0.15~0.30초)
        let calm = try scene(countdown: 5.0, run: 0.05)        // 경고 전
        cgSave(cgBitmap(warnOn), "crossy-rail-warning")
        let on = redPixels(warnOn), off = redPixels(warnOff), none = redPixels(calm)
        print("[길건너] 경고 레일 붉은 픽셀: 켜짐 \(on) · 꺼진 박자 \(off) · 경고 전 \(none)")
        #expect(on > 2000, "경고 중인데 레일이 안 붉다(\(on)px)")
        #expect(off * 4 < on && none * 4 < on, "깜빡이지 않는다 — 꺼진 박자 · 경고 전에도 붉다")
    }

    @Test("아잉이 화면 크기: 시안(약 35pt)보다 크게 — 52~60pt 언저리 · 가로 가운데 · 화면 아래쪽")
    func aingIsBiggerThanTheDraft() throws {
        let game = CG(seed: 77)
        let scene = CrossyScene()
        // 몸만 잰다 — 발밑 그림자는 두 장 다 숨긴다(그림자까지 재면 아래로 늘어난 상자가 된다).
        scene.setShadowHiddenForTesting(true)
        let with = try cgSnapshot(scene, game)
        scene.setAingHiddenForTesting(true, includingShadow: false)
        let without = try cgSnapshot(scene, game)
        scene.setAingHiddenForTesting(false)
        let body = try #require(cgDiffBounds(with, without, tolerance: 6), "아잉이가 안 그려졌다")
        let heightPt = body.height / 2, widthPt = body.width / 2
        print("[길건너] 아잉이 화면 크기: 몸 \(String(format: "%.1f", widthPt))×\(String(format: "%.1f", heightPt))pt(가로×세로)"
              + " · 중심 (\(String(format: "%.0f", body.midX / 2)), \(String(format: "%.0f", body.midY / 2)))pt / 344×356 · 시안 B 는 약 40×35pt")
        #expect(max(widthPt, heightPt) >= 50 && max(widthPt, heightPt) <= 64, "아잉이 크기가 \(widthPt)×\(heightPt)pt — 설계서 52~60pt 에서 멀다")
        #expect(heightPt >= 40, "아잉이 키가 \(heightPt)pt — 시안(35pt)과 다를 바 없다")
        #expect(abs(body.midX / 2 - 172) < 30, "아잉이가 가로 가운데가 아니다(\(body.midX / 2)pt)")
        #expect(body.midY / 2 > 356 * 0.5 && body.midY / 2 < 356 * 0.85, "아잉이가 화면 아래쪽이 아니다(\(body.midY / 2)pt)")
    }

    @Test("노드 풀: 생존 봇이 오래 가도 줄 노드는 화면 줄 수만큼만 만들고 그 뒤는 재활용한다 · 차 · 통나무 · 나무도")
    func nodePoolsRecycle() throws {
        let scene = CrossyScene()
        var game = CG(seed: 4242)
        game.action()
        var frames = 0
        var maxActive = 0
        for _ in 0..<(60 * 60) where game.phase == .running {
            cgBotStep(&game)
            scene.apply(game, reduceMotion: false)
            frames += 1
            maxActive = max(maxActive, scene.poolCountsForTesting.activeRows)
        }
        let window = CrossyScene.rowsBehind + CrossyScene.rowsAhead + 1
        print("[길건너] 노드 풀: \(frames)프레임 · \(game.score)줄 · 만든 줄 \(scene.madeRows) · 물건 \(scene.madeProps) · 차/통나무 \(scene.madeMovers) · 동시 줄 최대 \(maxActive)")
        #expect(game.score >= 30, "봇이 \(game.score)줄 — 재활용을 볼 만큼 못 갔다")
        #expect(maxActive <= window, "한 번에 \(maxActive)줄을 들고 있다(창 \(window))")
        #expect(scene.madeRows <= window + 2, "줄 노드를 \(scene.madeRows)개 만들었다 — 재활용이 안 된다")
        #expect(scene.madeMovers < game.score * 2, "차·통나무 노드를 \(scene.madeMovers)개 만들었다(\(game.score)줄)")
        #expect(scene.poolCountsForTesting.pooledRows + scene.poolCountsForTesting.activeRows == scene.madeRows)
    }

    @Test("모양 굳히기: 경계 숲은 양옆 세 칸씩 퍼져 있다(가운데 한 자리로 겹치지 않는다) · 차 길이 = 규칙 길이")
    func flattenedGeometryKeepsOffsets() {
        let palette = CrossyPalette.shared
        for variant in 0...1 {
            let (minB, maxB) = palette.borderForest(variant: variant).boundingBox
            #expect(minB.x < -6.5 && maxB.x > 6.5, "경계 숲 \(variant) 이 x \(minB.x)…\(maxB.x) 에 몰렸다 — 나무가 한가운데 겹친다")
        }
        let car = palette.vehicle(palette.vehicleKey(CG.Mover(x: 0, length: CG.carLength)))
        let (carMin, carMax) = car.boundingBox
        #expect(abs(Double(carMax.x - carMin.x) - CG.carLength) < 0.1, "그린 차 길이 \(carMax.x - carMin.x) ≠ 규칙 \(CG.carLength)")
        let truck = palette.vehicle(palette.vehicleKey(CG.Mover(x: 0, length: CG.truckLength, isTruck: true)))
        let (truckMin, truckMax) = truck.boundingBox
        #expect(abs(Double(truckMax.x - truckMin.x) - CG.truckLength) < 0.1, "그린 트럭 길이 ≠ 규칙")
        let (logMin, logMax) = palette.log(palette.logKey(CG.Mover(x: 0, length: 3))).boundingBox
        #expect(abs(Double(logMax.x - logMin.x) - 3) < 0.1, "그린 통나무 길이 ≠ 규칙")
    }

    @Test("그림자 맵 ≤ 2048 · 각진 그림자(표본 1) · 아잉이는 판 그림자를 드리우지 않는다 · 카메라는 정사영")
    func shadowAndCameraBudget() throws {
        let scene = CrossyScene()
        let sun = try #require(scene.sunForTesting)
        #expect(sun.castsShadow && sun.shadowMapSize.width <= 2048 && sun.shadowMapSize.height <= 2048)
        #expect(sun.shadowSampleCount == 1)
        #expect(scene.cameraNode.camera?.usesOrthographicProjection == true)
        #expect((scene.cameraNode.camera?.orthographicScale ?? 99) < 4.4, "카메라를 시안(4.4)보다 안 당겼다")
        // 새 씬에는 아잉이 · 발밑 그림자 · 물결 고리뿐이다 — 셋 다 빛을 안 받고(unlit) 판 그림자를 드리우지 않는다.
        var unlit = 0, casts = 0
        scene.scene.rootNode.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry, geometry.materials.allSatisfy({ $0.lightingModel == .constant }) else { return }
            unlit += 1
            if node.castsShadow { casts += 1 }
        }
        #expect(unlit >= 3, "unlit 노드를 \(unlit)개밖에 못 찾았다 — 검사가 헛돈다")
        #expect(casts == 0, "빛을 안 받는(unlit) 노드 \(casts)개가 그림자를 드리운다 — 아잉이 그림자가 비스듬히 떨어진다")
    }

    @Test("프레임 비용: 판 한 걸음 + 노드 옮기기 평균이 프레임 예산(16.7ms)의 작은 몫이다")
    func frameCostIsSmall() throws {
        let scene = CrossyScene()
        var game = CG(seed: 99)
        game.action()
        for _ in 0..<120 where game.phase == .running { cgBotStep(&game); scene.apply(game, reduceMotion: false) }
        let started = CFAbsoluteTimeGetCurrent()
        var n = 0
        for _ in 0..<600 where game.phase == .running {
            game.step(dt: 1.0 / 60)
            scene.apply(game, reduceMotion: false)
            n += 1
        }
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000 / Double(max(1, n))
        print("[길건너] 프레임 비용(규칙 + 노드 옮기기, 그리기 제외): 평균 \(String(format: "%.3f", ms))ms × \(n)프레임")
        #expect(n > 100)
        #expect(ms < 4, "한 프레임에 \(ms)ms — 60Hz 예산을 먹는다")
    }

    @Test("미리 만들기: 씬이 설 때 판이 쓸 모양을 전부 만든다 — 긴 판을 돌려도 모양이 하나도 새로 안 생긴다")
    func prewarmCoversEveryShape() throws {
        let palette = CrossyPalette.shared
        palette.resetForTesting()
        let scene = CrossyScene()
        let prepared = palette.shapeCount
        // 줄 4종 × 홀짝 × 안/밖(16) + 무늬 6 + 물건 4 + 차/트럭 10 + 통나무 3 + 기차 · 기둥 · 등 둘 · 그림자 · 고리(6)
        #expect(prepared >= 45, "미리 만든 모양이 \(prepared)개뿐이다")
        var game = CG(seed: 777)
        game.action()
        for _ in 0..<(60 * 60) where game.phase == .running {
            cgBotStep(&game)
            scene.apply(game, reduceMotion: false)
        }
        // 기차 · 경고 레일까지 나오게 기찻길에서 한 번 더(경고 켜짐 + 기차 지나감).
        var rail = cgGame(lanes: [cgRail(1, countdown: 0.05), cgRoad(2, cars: [1], truck: true), cgRiver(3, logs: [(x: 1, length: 4)])])
        for _ in 0..<60 { rail.step(dt: 1.0 / 60); scene.apply(rail, reduceMotion: false) }
        #expect(palette.shapeCount == prepared, "판 도중에 모양을 \(palette.shapeCount - prepared)개 새로 만들었다(메인 스레드에서 굳히기)")
        #expect(scene.prewarmShapes.count == prepared)
    }

    @Test("창 닫기: 허브는 창이 닫혀 있으면 3D 판을 안 세운다 · SCNView 가 내려갈 때 씬을 놓는다(그림자 맵 · MSAA 버퍼가 남지 않게)")
    func sceneIsDroppedWhenTheWindowCloses() throws {
        let panel = cgStrip(try cgSource("MiniGamePanel.swift"))
        let canvas = try #require(cgBlock(after: "private func canvasStack(size: CGSize)", in: panel))
        let gate = try #require(canvas.range(of: "if store.isMiniGamePanelVisible {"), "닫힌 창에서도 3D 판이 산다")
        let view = try #require(canvas.range(of: "CrossyGameView(host: host, input: input)"))
        #expect(gate.lowerBound < view.lowerBound)
        weak var released: CrossyScene?
        let scnView = CrossySCNView(frame: NSRect(x: 0, y: 0, width: 344, height: 356))
        do {
            let scene = CrossyScene()
            released = scene
            scnView.scene = scene.scene
            scnView.crossyScene = scene
            scnView.pending = (CG(seed: 1), false)
            CrossySceneView.dismantleNSView(scnView, coordinator: ())
        }
        #expect(scnView.scene == nil && scnView.crossyScene == nil && scnView.pending == nil, "내려간 SCNView 가 씬을 쥐고 있다")
        #expect(released == nil, "씬이 해제되지 않았다 — 누군가 붙들고 있다")
    }

    @Test("SCNView: 마우스를 안 받는다(클릭은 허브 제스처로) · 창에 안 붙으면 화면 밖 · 그리기는 바뀔 때만")
    func sceneViewContract() throws {
        let view = CrossySCNView(frame: NSRect(x: 0, y: 0, width: 344, height: 356))
        #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil)
        #expect(!view.isOnScreen, "창에 안 붙었는데 보인다고 한다 — 가려진 창에서도 노드를 옮긴다")
        let leaf = cgStrip(try cgSource("MiniGameCrossy.swift"))
        let update = try #require(cgBlock(after: "func updateNSView(", in: leaf))
        let guardAt = try #require(update.range(of: "guard view.isOnScreen else { return }"))
        let applyAt = try #require(update.range(of: "scene.apply(game, reduceMotion: reduceMotion)"))
        #expect(guardAt.lowerBound < applyAt.lowerBound, "가려진 창에서도 노드를 옮긴다")
        let make = try #require(cgBlock(after: "func makeNSView(", in: leaf))
        #expect(make.contains("view.rendersContinuously = false"), "판이 멈춰도 계속 그린다")
    }
}

// MARK: - E 서버 계약(20261027130000_minigame_crossy.sql)

private let cgCrossyMigration = "20261027130000_minigame_crossy.sql"

private func cgMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        directory = directory.deletingLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}

/// `--` 주석을 걷어낸 SQL(설명을 지워야만 초록이 되는 시험이 되지 않게 — 하우스 규칙).
private func cgMigrationSQL() throws -> String {
    let url = try cgMigrationsDirectory().appendingPathComponent(cgCrossyMigration)
    let raw = try String(contentsOf: url, encoding: .utf8)
    return raw.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func cgMatches(_ pattern: String, in text: String) throws -> [[String]] {
    let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
        (0..<match.numberOfRanges).map { i in
            Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

/// 함수 본문(달러 인용 사이) — `create or replace function public.<name>(` 부터 그 달러 태그가 닫힐 때까지.
private func cgFunctionBody(_ name: String, in sql: String) throws -> String? {
    let matches = try cgMatches(#"create\s+or\s+replace\s+function\s+public\.\#(name)\s*\(.*?as\s+(\$[a-z_]*\$)(.*?)\1"#, in: sql)
    return matches.last?[2]
}

@Suite("v0.3.67 길건너 아잉이 — 서버 계약(CHECK_MIGRATIONS_DIR)")
struct V0367CrossyServerContractTests {
    @Test("상한: minigame_score_cap('crossy') = 5000 = MiniGameKind.crossy.maxScore")
    func scoreCap() throws {
        let sql = try cgMigrationSQL()
        let body = try #require(try cgFunctionBody("minigame_score_cap", in: sql), "minigame_score_cap 을 넓히지 않았다")
        let cap = try cgMatches(#"when\s+'crossy'\s+then\s+([0-9_]+)"#, in: body).first?[1]
        #expect(cap.flatMap { Int($0) } == MiniGameKind.crossy.maxScore, "서버 상한 \(cap ?? "없음") ≠ 앱 \(MiniGameKind.crossy.maxScore)")
    }

    @Test("시간 하한: minigame_min_seconds 의 crossy 갈래 = s × 0.09 = s × hopSeconds × 0.75")
    func minimumSeconds() throws {
        let sql = try cgMigrationSQL()
        let body = try #require(try cgFunctionBody("minigame_min_seconds", in: sql), "minigame_min_seconds 를 넓히지 않았다")
        let branch = try #require(body.range(of: "'crossy'"), "crossy 갈래가 없다 — `else return 0` 로 떨어져 하한이 통째로 없다")
        let tail = String(body[branch.upperBound...].prefix(400))
        let factors = try cgMatches(#"(0\.[0-9]+)"#, in: tail).map { $0[1] }
        let factor = try #require(factors.first.flatMap(Double.init), "crossy 갈래에 배수가 없다: \(tail)")
        #expect(abs(factor - CrossyGame.hopSeconds * CrossyGame.serverTimeMarginFactor) < 1e-12,
                "서버 배수 \(factor) ≠ hopSeconds × 0.75 = \(CrossyGame.hopSeconds * CrossyGame.serverTimeMarginFactor)")
    }

    @Test("일일 미션: daily_crossy · game crossy · '길건너 아잉이 한 판 하기' · 보상 5 · 목표 1 · 미니게임 셋 바로 뒤(1:1 셋 앞)")
    @MainActor
    func dailyMissionDefinition() throws {
        let sql = try cgMigrationSQL()
        let body = try #require(try cgFunctionBody("daily_mission_defs", in: sql), "daily_mission_defs 를 넓히지 않았다")
        let rows = try cgMatches(#"\(\s*'(daily_[a-z_]+)'\s*,\s*'([a-z_]+)'\s*,\s*'([^']+)'\s*,\s*'([^']*)'\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*\)"#, in: body)
            .map { Array($0.dropFirst()) }
        let crossy = try #require(rows.first { $0[0] == "daily_crossy" }, "daily_crossy 줄이 없다: \(rows.map { $0[0] })")
        #expect(crossy[1] == "crossy" && crossy[2] == "길건너 아잉이 한 판 하기" && crossy[4] == "5" && crossy[5] == "1",
                "정의 줄이 설계서 §1 과 다르다: \(crossy)")
        #expect(crossy[2].hasPrefix(MiniGameKind.crossy.title + " "), "서버 제목이 앱 이름으로 시작하지 않는다")
        let sort = Int(crossy[6]) ?? -1
        let sortOf = Dictionary(uniqueKeysWithValues: rows.map { ($0[1], Int($0[6]) ?? -1) })
        for solo in ["timing_bar", "flappy", "tetris"] { #expect(sort > (sortOf[solo] ?? .max), "\(solo) 보다 앞이다") }
        for duel in ["gomoku", "chess", "tetris_duel"] { #expect(sort < (sortOf[duel] ?? .min), "\(duel) 보다 뒤다") }
        #expect(rows.count == 7, "정의표가 \(rows.count)줄(기대 7)")
        #expect(DailyMissionCopy.icon(game: crossy[1]) == MiniGameKind.crossy.icon)
    }

    @Test("게임 목록: 점수 표 · 라운드 표 CHECK 와 판 시작 함수가 crossy 를 안다 · 상금 함수가 crossy 를 돈다")
    func gameListsWidened() throws {
        let sql = try cgMigrationSQL()
        let lists = try cgMatches(#"\(\s*'timing_bar'\s*,\s*'flappy'\s*,\s*'tetris'\s*,\s*'crossy'\s*\)"#, in: sql)
        #expect(lists.count >= 2, "('timing_bar','flappy','tetris','crossy') 목록이 \(lists.count)곳뿐이다 — CHECK 와 판 시작을 같이 넓혀라")
        let prizeLoops = try cgMatches(#"array\s*\[\s*'timing_bar'\s*,\s*'flappy'\s*,\s*'tetris'\s*,\s*'crossy'\s*\]"#, in: sql)
        #expect(!prizeLoops.isEmpty, "자정 상금 함수가 crossy 를 안 돈다")
    }
}

// MARK: - 0.3.67 체인지로그 (내용만)
//
// 버전 고정과 "맨 위 섹션" 단언은 0.3.69 에서 `V0369RummyReleaseTests` 로 넘겼다(관행 — 그 릴리스의 시험 파일이 든다).
// 여기는 0.3.67 섹션의 **내용**만 남는다.
@Test("CHANGELOG 0.3.67(길건너 아잉이 · 역대 순위 · 접힌 판 점수 · 4줄 이하 · 배너 폭 안)")
func v0367VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.67\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((2...4).contains(items.count), "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0367] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "서버", "테스트", "CheckCore", "RPC", "마이그레이션", "💎", "crossy"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("길건너 아잉이") }, "새 미니게임 줄이 없다")
    #expect(items.contains { $0.contains("역대") }, "역대 순위 줄이 없다")
    #expect(items.contains { $0.contains("점수가 남아요") }, "접힌 판 점수 줄이 없다")
}
