// 원본: 없음 — W1-a 미니게임(플래피 · 타이밍 바 · 프레임률 · 엔진 공용 값) 골든 생성 시험(C§5.1 E4~E6 · C§5.2 G1·G3).
// 원본 엔진: Sources/CheckCore/FlappyGame.swift · TimingBarGame.swift · MiniGameEngine.swift @ 1b8260d.
import CheckGoldenSupport
import CoreGraphics
import Foundation
import Testing
@testable import CheckCore

@Suite("GoldenExport games-tetris-minigame — 플래피 · 타이밍 바 · 프레임률 · 엔진 공용 값")
struct GoldenExportMiniGames {
    static let engine = "Sources/CheckCore/MiniGameEngine.swift"
    static let flappy = "Sources/CheckCore/FlappyGame.swift"
    static let timingBar = "Sources/CheckCore/TimingBarGame.swift"
    static let checkpointEvery = 64

    // MARK: - flappy/rules (G1 · 이산)

    @Test("flappy/rules — 상수 · 난이도 곡선 · 속도 적분 · 새 기둥(난수 순서) · 틈 중심(pow) · CGRect.intersects 의미 · 충돌")
    func flappyRules() {
        var cases: [GoldenJSON] = []
        cases.append([
            "id": "constants",
            "widthBits": .bits(Double(FlappyGame.width)), "heightBits": .bits(Double(FlappyGame.height)),
            "birdXBits": .bits(Double(FlappyGame.birdX)), "hitboxSizeBits": .bits(Double(FlappyGame.hitboxSize)),
            "spriteSizeBits": .bits(Double(FlappyGame.spriteSize)), "gravityBits": .bits(Double(FlappyGame.gravity)),
            "flapVelocityBits": .bits(Double(FlappyGame.flapVelocity)), "maxFallSpeedBits": .bits(Double(FlappyGame.maxFallSpeed)),
            "pipeWidthBits": .bits(Double(FlappyGame.pipeWidth)), "firstPipeXBits": .bits(Double(FlappyGame.firstPipeX)),
            "pipeCount": .int(FlappyGame.pipeCount), "maxScore": .int(FlappyGame.maxScore),
            "centerMarginBits": .bits(Double(FlappyGame.centerMargin)), "overHoldBits": .bits(FlappyGame.overHold),
            "flashDurationBits": .bits(FlappyGame.flashDuration), "maxStepBits": .bits(FlappyGame.maxStep),
            "shiftMinScore": .int(FlappyGame.shiftMinScore), "shiftChanceBits": .bits(FlappyGame.shiftChance),
            "shiftJumpBits": .bits(Double(FlappyGame.shiftJump)),
            "shiftDelayMinBits": .bits(FlappyGame.shiftDelayRange.lowerBound),
            "shiftDelayMaxBits": .bits(FlappyGame.shiftDelayRange.upperBound),
            "shiftDurationBits": .bits(FlappyGame.shiftDuration),
        ])
        let scores = Array(-3...60)
        cases.append(["id": "curves", "from": -3,
                      "gapBits": GoldenCompact.bits(scores.map { Double(FlappyGame.gap(forScore: $0)) }),
                      "speedBits": GoldenCompact.bits(scores.map { Double(FlappyGame.speed(forScore: $0)) }),
                      "spacingBits": GoldenCompact.bits(scores.map { Double(FlappyGame.spacing(forScore: $0)) })])
        let vys: [Double] = [-317, -100, 0, 0.5, 300, 573.9, 574, 800]
        let dts: [Double] = [0, 1.0 / 144.0, 1.0 / 60.0, 1.0 / 30.0, 0.05]
        var velocities: [Double] = []
        for vy in vys { for dt in dts { velocities.append(Double(FlappyGame.nextVelocity(CGFloat(vy), dt: dt))) } }
        cases.append(["id": "nextVelocity", "vyBits": GoldenCompact.bits(vys), "dtBits": GoldenCompact.bits(dts),
                      "spec": "vy 행 × dt 열 행 우선", "valuesBits": GoldenCompact.bits(velocities)])
        // 새 기둥: 시드마다 점수 여럿 · 난수 소비 순서를 rng 다음 값으로 묶는다.
        for (index, seed) in [UInt64(1), 42, 0xFEED_BEEF, 0xFFFF_FFFF_FFFF_FFFF].enumerated() {
            var rng = MiniGameRandom(seed: seed)
            var pipes: [GoldenJSON] = []
            for round in 0..<24 {
                let score = [0, 14, 15, 16, 22, 30, 60, 999][round % 8]
                let pipe = FlappyGame.makePipe(x: CGFloat(300 + round * 117), score: score, rng: &rng)
                pipes.append(Self.pipeJSON(pipe, score: score))
            }
            var after = rng
            cases.append(["id": .string("makePipe-\(index)"), "seed": .hex64(seed), "pipes": .array(pipes),
                          "nextAfter": .hex64(after.next())])
        }
        // 틈 중심(pow — 이산): 튀는 기둥 · 시각 격자.
        let pipes: [FlappyGame.Pipe] = [
            FlappyGame.Pipe(x: 100, centerY: 120, gap: 96, shiftDelay: 0.5, shiftOffset: 58, shiftAt: 2.0),
            FlappyGame.Pipe(x: 100, centerY: 200, gap: 110, shiftDelay: 0.9, shiftOffset: -58, shiftAt: 3.25),
            FlappyGame.Pipe(x: 100, centerY: 60, gap: 132, shiftDelay: 0.45, shiftOffset: -58, shiftAt: 1.0),
            FlappyGame.Pipe(x: 100, centerY: 151, gap: 96),
        ]
        var centers: [GoldenJSON] = []
        for (index, pipe) in pipes.enumerated() {
            let start = pipe.shiftAt ?? 0
            let times = (0...40).map { start - 0.01 + Double($0) * 0.0035 }
            centers.append(["pipe": Self.pipeJSON(pipe, score: 0), "id": .string("pipe-\(index)"),
                            "timesBits": GoldenCompact.bits(times),
                            "centersBits": GoldenCompact.bits(times.map { Double(pipe.center(at: $0)) })])
        }
        cases.append(["id": "center", "tolerance": "1e-9", "pipes": .array(centers)])
        // CGRect.intersects(맥 CoreGraphics 실측 의미).
        let rects: [(CGRect, CGRect)] = [
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 10, y: 0, width: 10, height: 10)),
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 0, y: 10, width: 10, height: 10)),
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 5, y: 5, width: 0, height: 0)),
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 2, y: 5, width: 4, height: 0)),
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 2, y: 0, width: 4, height: 0)),
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 2, y: 10, width: 4, height: 0)),
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 9.999, y: 0, width: 10, height: 10)),
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 15, y: 0, width: -6, height: 10)),
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 10, y: 10, width: 5, height: 5)),
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 0, y: 2, width: 0, height: 4)),
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 10, y: 2, width: 0, height: 4)),
            (CGRect(x: 1, y: 1, width: 0, height: 0), CGRect(x: 2, y: 2, width: 0, height: 0)),
            (CGRect(x: 1, y: 1, width: 0, height: 5), CGRect(x: 1, y: 3, width: 0, height: 5)),
            (CGRect(x: 1, y: 1, width: 0, height: 2), CGRect(x: 1, y: 3, width: 0, height: 5)),
            (CGRect(x: 0, y: 5, width: 10, height: 0), CGRect(x: 5, y: 0, width: 0, height: 10)),
            (CGRect(x: 0, y: 5, width: 10, height: 0), CGRect(x: 10, y: 0, width: 0, height: 10)),
            (CGRect(x: 0, y: 5, width: 10, height: 0), CGRect(x: 0, y: 0, width: 0, height: 10)),
            (CGRect(x: 0, y: 5, width: 10, height: 0), CGRect(x: 5, y: 0, width: 0, height: 5)),
            (CGRect(x: 0, y: 5, width: 10, height: 0), CGRect(x: 5, y: 5, width: 0, height: 5)),
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 2, y: 12, width: 4, height: -2)),
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 2, y: 11, width: 4, height: -2)),
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 10, y: 10, width: 0, height: 0)),
            (CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 0, y: 0, width: 0, height: 0)),
            (CGRect(x: 69.76, y: 0, width: 24, height: 24), CGRect(x: 30, y: 0, width: 44, height: 0)),
            (CGRect(x: 69.76, y: 0, width: 24, height: 24), CGRect(x: 93.76, y: 0, width: 44, height: 100)),
            (CGRect(x: 69.76, y: 278, width: 24, height: 24), CGRect(x: 50, y: 302, width: 44, height: 0)),
        ]
        cases.append(["id": "rectIntersects",
                      "spec": "a·b = [x, y, w, h] 비트. ab = a.intersects(b), ba = b.intersects(a)",
                      "rects": .array(rects.map { a, b -> GoldenJSON in
                          ["a": Self.rectBits(a), "b": Self.rectBits(b), "ab": .bool(a.intersects(b)), "ba": .bool(b.intersects(a))]
                      })])
        goldenEmit(GoldenFile(
            golden: "flappy/rules",
            equivalence: .discrete,
            swiftSources: [Self.flappy, Self.engine],
            spec: [
                "equivalence": "이산(G §8-14): center 의 centersBits 만 허용 오차 tolerance(절대값) — easeOut 의 1 − pow(1−p, 3) 를 Kotlin 은 곱셈으로 낸다. 그 밖의 칸(곡선 · 속도 · 새 기둥 · 사각형)은 비트 그대로 대조한다",
                "makePipe": "MiniGameRandom(seed) 하나로 makePipe(x: 300 + 117·i, score: [0,14,15,16,22,30,60,999][i % 8]) 를 24번 — 기둥마다 x·centerY·gap·shiftDelay(없으면 null)·shiftOffset 비트. nextAfter = 그 뒤 rng.next()",
                "rectIntersects": "맥 CoreGraphics CGRect.intersects 의 실측 의미(변만 맞닿으면 거짓 · 크기 0 은 점 · 반열린 [min, max))",
            ],
            cases: cases
        ))
    }

    static func rectBits(_ r: CGRect) -> GoldenJSON {
        GoldenCompact.bits([Double(r.origin.x), Double(r.origin.y), Double(r.size.width), Double(r.size.height)])
    }

    static func phaseName(_ p: FlappyGame.Phase) -> GoldenJSON {
        switch p {
        case .ready: return ["kind": "ready"]
        case .running: return ["kind": "running"]
        case .over(let hold): return ["kind": "over", "holdBits": .bits(hold)]
        case .result: return ["kind": "result"]
        }
    }

    static func pipeJSON(_ pipe: FlappyGame.Pipe, score: Int) -> GoldenJSON {
        [
            "score": .int(score), "xBits": .bits(Double(pipe.x)), "centerYBits": .bits(Double(pipe.centerY)),
            "gapBits": .bits(Double(pipe.gap)), "passed": .bool(pipe.passed),
            "shiftDelayBits": pipe.shiftDelay.map(GoldenJSON.bits) ?? .null,
            "shiftOffsetBits": .bits(Double(pipe.shiftOffset)),
            "shiftAtBits": pipe.shiftAt.map(GoldenJSON.bits) ?? .null,
        ]
    }

    // MARK: - flappy/scripted (G3 · 이산)

    static func flappyFold(_ g: FlappyGame, into h: inout GoldenDualFold) {
        switch g.phase {
        case .ready: h.add(0)
        case .running: h.add(1)
        case .over(let hold): h.add(2); h.add(hold)
        case .result: h.add(3)
        }
        h.add(g.score)
        h.add(Double(g.bird.x)); h.add(Double(g.bird.y)); h.add(Double(g.bird.vy))
        h.add(g.flashRemaining); h.add(g.elapsed); h.add(Double(g.scrolled)); h.add(g.flapCount)
        h.add(g.lastFlapAt); h.add(g.lastScoreAt); h.add(g.lastScorePipeCenter != nil)
        h.add(g.pipes.count)
        for p in g.pipes {
            h.add(Double(p.x)); h.add(Double(p.centerY)); h.add(Double(p.gap)); h.add(p.passed)
            h.add(p.shiftDelay); h.add(Double(p.shiftOffset)); h.add(p.shiftAt)
        }
        // 화면이 읽는 파생 값(검증 지적: 옮긴 공개 파생값도 골든에 싣는다).
        h.add(g.isPlaying); h.add(g.isGameOver); h.add(g.stage.id)
        let box = g.hitbox
        h.add(Double(box.origin.x)); h.add(Double(box.origin.y)); h.add(Double(box.size.width)); h.add(Double(box.size.height))
    }

    struct FlappyCase {
        var id: String
        var seed: UInt64
        var dt: Double
        var frames: Int
        var fixture: Bool
        var interruptAt: Int?
    }

    static let flappyCases: [FlappyCase] = [
        FlappyCase(id: "A", seed: 1, dt: 1.0 / 60.0, frames: 60 * 150, fixture: false, interruptAt: nil),
        FlappyCase(id: "B", seed: 0xFEED, dt: 1.0 / 30.0, frames: 30 * 150, fixture: false, interruptAt: nil),
        FlappyCase(id: "C", seed: 99, dt: 0.05, frames: 20 * 120, fixture: false, interruptAt: nil),
        FlappyCase(id: "D", seed: 7, dt: 1.0 / 144.0, frames: 144 * 60, fixture: false, interruptAt: 144 * 20),
        FlappyCase(id: "E", seed: 5, dt: 1.0 / 60.0, frames: 120, fixture: true, interruptAt: nil),
    ]

    /// 조종사(Swift 몫만): 다음 기둥의 틈 중심을 노린다. 연산 F = flap(), I = interrupt().
    static func flappyPilot(_ c: FlappyCase) -> (start: FlappyGame, frames: [[String]]) {
        let start: FlappyGame
        if c.fixture {
            start = FlappyGame(seed: c.seed, bird: .init(x: FlappyGame.birdX, y: 151, vy: 0),
                               pipes: [.init(x: 60, centerY: 151, gap: 96)], score: 998, phase: .running)
        } else {
            start = FlappyGame(seed: c.seed)
        }
        var g = start
        var frames: [[String]] = []
        var deadSince: Int?
        for frame in 1...c.frames {
            var ops: [String] = []
            if let at = c.interruptAt, frame == at { ops.append("I") }
            switch g.phase {
            case .ready, .result:
                if frame % 9 == 0 { ops.append("F") }
            case .over:
                if deadSince == nil { deadSince = frame }
                ops.append("F")                     // 유예 중 클릭은 무시돼야 한다
            case .running:
                deadSince = nil
                if Self.flappyShouldFlap(g, dt: c.dt) { ops.append("F") }
            }
            for op in ops { Self.flappyApply(op, to: &g) }
            g.step(dt: c.dt)
            frames.append(ops)
        }
        return (start, frames)
    }

    /// 다음 기둥의 틈 중심(지금 판 시각 기준).
    static func flappyTarget(_ g: FlappyGame) -> Double {
        let box = g.hitbox
        let next = g.pipes.first { $0.x + FlappyGame.pipeWidth >= box.minX - 1 }
        return next.map { Double($0.center(at: g.elapsed)) } ?? Double(FlappyGame.height / 2)
    }

    /// 앞보기: 지금 뛸 때와 안 뛸 때를 각각 (기본 버릇으로) 0.6초 흘려 오래 사는 쪽, 같으면 틈 중심에 가까운 쪽.
    static func flappyShouldFlap(_ g: FlappyGame, dt: Double) -> Bool {
        let horizon = max(8, Int((0.6 / min(dt, FlappyGame.maxStep)).rounded(.down)))
        func run(flapFirst: Bool) -> (Int, Double) {
            var probe = g
            if flapFirst { probe.flap() }
            for k in 0..<horizon {
                if k > 0, Double(probe.bird.y) > Self.flappyTarget(probe) + 6, probe.bird.vy > 0 { probe.flap() }
                probe.step(dt: dt)
                guard case .running = probe.phase else { return (k, .infinity) }
            }
            return (horizon, abs(Double(probe.bird.y) - Self.flappyTarget(probe)))
        }
        let a = run(flapFirst: true)
        let b = run(flapFirst: false)
        if a.0 != b.0 { return a.0 > b.0 }
        return a.1 + 4 < b.1
    }

    static func flappyApply(_ op: String, to g: inout FlappyGame) {
        switch op {
        case "F": g.flap()
        case "I": g.interrupt()
        default: Issue.record("모르는 플래피 연산 \(op)")
        }
    }

    @Test("flappy/scripted — 대본 다섯(조종사 → 연산 RLE · 체크포인트 · 프레임 바이트 · 득점 때 틈 중심 · 끝 상태)")
    func flappyScripted() {
        var cases: [GoldenJSON] = []
        var shiftedPasses = 0
        for c in Self.flappyCases {
            let pilot = Self.flappyPilot(c)
            let rle = GoldenOpsRLE.encode(pilot.frames)
            var g = pilot.start
            var h = GoldenDualFold()
            Self.flappyFold(g, into: &h)
            var checkpoints: [UInt64] = []
            var bytes = GoldenFrameBytes()
            var centers: [String] = []
            var maxScore = 0
            var frame = 0
            for ops in GoldenOpsRLE.decode(rle) {
                frame += 1
                h.beginFrame()
                let scoreAt = g.lastScoreAt
                for op in ops { Self.flappyApply(op, to: &g) }
                g.step(dt: c.dt)
                Self.flappyFold(g, into: &h)
                bytes.append(h.frame.value)
                if frame % Self.checkpointEvery == 0 { checkpoints.append(h.total.value) }
                if g.lastScoreAt != scoreAt, let center = g.lastScorePipeCenter {
                    centers.append("\(frame):\(GoldenBits.bits(Double(center)))")
                }
                maxScore = max(maxScore, g.score)
                if g.score >= FlappyGame.shiftMinScore { shiftedPasses += g.pipes.filter { $0.isShifting && $0.passed }.count }
            }
            #expect(c.fixture || maxScore >= 20, "\(c.id): 조종사가 움직이는 기둥(15점~)까지 못 갔다(최고 \(maxScore))")
            let start: GoldenJSON
            if c.fixture {
                start = ["kind": "fixture", "bird": GoldenCompact.bits([Double(FlappyGame.birdX), 151, 0]),
                         "pipe": GoldenCompact.bits([60, 151, 96]), "score": 998]
            } else {
                start = ["kind": "new"]
            }
            cases.append([
                "id": .string(c.id), "seed": .hex64(c.seed), "dtBits": .bits(c.dt),
                "start": start,
                "ops": .string(rle), "checkpointEvery": .int(Self.checkpointEvery),
                "checkpoints": .string(checkpoints.map(GoldenBits.hex64).joined(separator: " ")),
                "frameBytes": .string(bytes.text),
                "centers": .string(centers.joined(separator: " ")),
                "maxScore": .int(maxScore),
                "final": [
                    "hash": .hex64(h.total.value), "frames": .int(frame), "score": .int(g.score),
                    "phase": Self.phaseName(g.phase), "elapsedBits": .bits(g.elapsed),
                    "birdBits": GoldenCompact.bits([Double(g.bird.x), Double(g.bird.y), Double(g.bird.vy)]),
                    "flapCount": .int(g.flapCount), "pipes": .array(g.pipes.map { Self.pipeJSON($0, score: g.score) }),
                    "lastScorePipeCenterBits": g.lastScorePipeCenter.map { GoldenJSON.bits(Double($0)) } ?? .null,
                ],
            ])
        }
        #expect(shiftedPasses > 0, "대본이 움직이는 기둥을 하나도 통과하지 않았다 — pow 경로를 안 잰다")
        goldenEmit(GoldenFile(
            golden: "flappy/scripted",
            equivalence: .discrete,
            swiftSources: [Self.flappy, Self.engine],
            spec: [
                "start": "new = FlappyGame(seed). fixture = FlappyGame(seed, bird(x, y, vy), pipes: [Pipe(x, centerY, gap)], score, phase: running)",
                "frame": "연산을 적힌 순서대로(F = flap(), I = interrupt()) → step(dt) → 접기. 처음 접기 = 시작 판",
                "fold": "phase(ready 0 · running 1 · over 2+유예 · result 3) · score · bird x·y·vy · flashRemaining · elapsed · scrolled · flapCount · lastFlapAt(없으면 0, 있으면 1+비트) · lastScoreAt(같은 꼴) · lastScorePipeCenter 가 있는가 · 기둥 수 · 기둥마다 x·centerY·gap·passed·shiftDelay(꼴 같음)·shiftOffset·shiftAt(꼴 같음) · isPlaying · isGameOver · stage.id · hitbox x·y·w·h",
                "discrete": "pow 에서 나온 값(lastScorePipeCenter)은 해시에 넣지 않고 centers(\"프레임:비트\")로 따로 싣는다 — Kotlin 은 1e-9 안에서 대조한다. 충돌 판정(단계)은 정수 출력이라 해시로 잰다",
            ],
            cases: cases
        ))
    }

    // MARK: - timing-bar/rules (G1)

    @Test("timing-bar/rules — 주기 · 목표 폭 · 삼각파 · 라운드 점수(반올림 경계) · 판정 등급 · 상수")
    func timingBarRules() {
        var cases: [GoldenJSON] = []
        let rounds = Array(-1...14)
        cases.append(["id": "period", "from": -1, "valuesBits": GoldenCompact.bits(rounds.map { TimingBarGame.period(round: $0) })])
        cases.append(["id": "targetWidth", "from": -1, "valuesBits": GoldenCompact.bits(rounds.map { TimingBarGame.targetWidth(round: $0) })])
        let periods: [Double] = [1.10, 0.8, 0.425, 0.42, 1.0 / 3.0]
        var times: [Double] = []
        for k in 0...60 { times.append(Double(k) * 0.0371) }
        times += [-0.3, -1e-12, 1e-12, 0.2125, 0.55, 2.2, 1000.0001]
        var markers: [Double] = []
        for p in periods { for t in times { markers.append(TimingBarGame.markerPosition(t: t, period: p)) } }
        cases.append(["id": "markerPosition", "periodsBits": GoldenCompact.bits(periods), "timesBits": GoldenCompact.bits(times),
                      "spec": "period 행 × t 열", "valuesBits": GoldenCompact.bits(markers)])
        var distances: [Double] = [0, 1e-9, 0.5, 1, 1.0000001, 2, .nan, -0.1]
        for k in 0...30 { distances.append((Double(k) + 0.5) / 30.0) }
        for k in 0...30 { distances.append(Double(k) / 30.0) }
        cases.append(["id": "roundScore", "distancesBits": GoldenCompact.bits(distances),
                      "values": GoldenCompact.ints(distances.map { TimingBarGame.roundScore(distance: $0) })])
        cases.append(["id": "verdict", "from": -1,
                      "values": .string((-1...101).map { "\(TimingBarGame.verdict(score: $0))" }.joined(separator: " ")),
                      "labels": .array([TimingBarGame.Verdict.perfect, .great, .good, .close, .miss].map { .string("\($0)=\($0.label)") }),
                      "glyphs": .array([TimingBarGame.Verdict.perfect, .great, .good, .close, .miss].map { .string("\($0)=\($0.glyph)") })])
        cases.append(["id": "constants", "roundCount": .int(TimingBarGame.roundCount), "resultHoldBits": .bits(TimingBarGame.resultHold),
                      "maxStepBits": .bits(TimingBarGame.maxStep)])
        goldenEmit(GoldenFile(
            golden: "timing-bar/rules",
            equivalence: .bit,
            swiftSources: [Self.timingBar, Self.engine],
            spec: [
                "markerPosition": "2·|x − floor(x + 0.5)|, x = t / period(Swift (x + 0.5).rounded(.down))",
                "roundScore": "d ≤ 1 이면 100 − Int((30·d).rounded()) — .rounded() 는 0.5 를 0 에서 먼 쪽으로(경계 (k+0.5)/30 을 싣는다), 아니면(NaN 포함) 0",
                "verdict": "점수 −1…101 → 등급 이름(공백으로 이음). labels = 등급=라벨, glyphs = 등급=라운드 스트립 글리프(TimingBarSegmentGlyph — 색을 못 보는 눈의 두 번째 채널)",
            ],
            cases: cases
        ))
    }

    // MARK: - timing-bar/scripted (G3)

    static func timingFold(_ g: TimingBarGame, into h: inout GoldenDualFold) {
        switch g.phase {
        case .ready: h.add(0)
        case .running(let round, let t): h.add(1); h.add(round); h.add(t)
        case .roundResult(let round, let score, let hold): h.add(2); h.add(round); h.add(score); h.add(hold)
        case .finished(let total): h.add(3); h.add(total)
        }
        h.add(g.roundScores.count)
        for s in g.roundScores { h.add(s) }
        h.add(g.target.center); h.add(g.target.width)
        h.add(g.markerPosition)
        if let hit = g.lastHit { h.add(true); h.add(hit) } else { h.add(false) }
        h.add(g.combo); h.add(g.total); h.add(g.round); h.add(g.isPlaying)
    }

    struct TimingCase {
        var id: String
        var seed: UInt64
        var dt: Double
        var frames: Int
        var invalidateAt: Int?
    }

    static let timingCases: [TimingCase] = [
        TimingCase(id: "A", seed: 3, dt: 1.0 / 60.0, frames: 60 * 40, invalidateAt: nil),
        TimingCase(id: "B", seed: 0xABCD_EF01_2345_6789, dt: 1.0 / 30.0, frames: 30 * 40, invalidateAt: nil),
        TimingCase(id: "C", seed: 77, dt: 0.07, frames: 30 * 45, invalidateAt: 400),
        TimingCase(id: "D", seed: 2_147_483_647, dt: 1.0 / 119.0, frames: 119 * 35, invalidateAt: nil),
    ]

    /// 조종사: 라운드마다 정확도를 바꿔(시드 난수) 목표 근처에서 누른다 — 판정 다섯이 다 나오게. 결과 표시 중에도 가끔 누른다(무시).
    static func timingPilot(_ c: TimingCase) -> [[String]] {
        var g = TimingBarGame(seed: c.seed)
        var plan = MiniGameRandom(seed: c.seed ^ 0x5151)
        var frames: [[String]] = []
        var lastRound = -1
        var tapIn: Int?
        let step = min(max(c.dt, 0), TimingBarGame.maxStep)
        for frame in 1...c.frames {
            var ops: [String] = []
            if let at = c.invalidateAt, frame == at { ops.append("V") }
            switch g.phase {
            case .ready, .finished:
                lastRound = -1
                if frame % 11 == 0 { ops.append("T") }
            case .roundResult:
                if frame % 13 == 0 { ops.append("T") }
            case .running(let round, let t):
                if round != lastRound {
                    // 이 라운드에 노릴 거리(반폭의 배수) — 판정 다섯이 다 나오게. 한 주기 안에서 그 거리에 가장 가까운 프레임을 고른다.
                    lastRound = round
                    let want = [0.0, 0.1, 0.4, 0.75, 0.95, 1.3][Int(plan.next() % 6)] * g.target.width / 2
                    let period = TimingBarGame.period(round: round)
                    var best = 0
                    var bestError = Double.infinity
                    for k in 0...Int((period / step).rounded(.down)) {
                        let p = TimingBarGame.markerPosition(t: t + Double(k) * step, period: period)
                        let error = abs(abs(p - g.target.center) - want)
                        if error < bestError { bestError = error; best = k }
                    }
                    tapIn = best
                }
                if let k = tapIn {
                    if k == 0 { ops.append("T"); tapIn = nil } else { tapIn = k - 1 }
                }
            }
            for op in ops { Self.timingApply(op, to: &g) }
            g.step(dt: c.dt)
            frames.append(ops)
        }
        return frames
    }

    static func timingPhase(_ p: TimingBarGame.Phase) -> GoldenJSON {
        switch p {
        case .ready: return ["kind": "ready"]
        case .running(let round, let t): return ["kind": "running", "round": .int(round), "tBits": .bits(t)]
        case .roundResult(let round, let score, let hold):
            return ["kind": "roundResult", "round": .int(round), "score": .int(score), "holdBits": .bits(hold)]
        case .finished(let total): return ["kind": "finished", "total": .int(total)]
        }
    }

    static func timingApply(_ op: String, to g: inout TimingBarGame) {
        switch op {
        case "T": g.tap()
        case "V": g.invalidate()
        default: Issue.record("모르는 타이밍 바 연산 \(op)")
        }
    }

    @Test("timing-bar/scripted — 대본 넷(누름 · 무효 · 10라운드 끝 · 다시)")
    func timingBarScripted() {
        var cases: [GoldenJSON] = []
        var verdicts = Set<String>()
        for c in Self.timingCases {
            let rle = GoldenOpsRLE.encode(Self.timingPilot(c))
            var g = TimingBarGame(seed: c.seed)
            var h = GoldenDualFold()
            Self.timingFold(g, into: &h)
            var checkpoints: [UInt64] = []
            var bytes = GoldenFrameBytes()
            var frame = 0
            for ops in GoldenOpsRLE.decode(rle) {
                frame += 1
                h.beginFrame()
                var wasRunning = false
                if case .running = g.phase { wasRunning = true }
                for op in ops { Self.timingApply(op, to: &g) }
                if wasRunning, case .roundResult(_, let score, _) = g.phase {
                    verdicts.insert("\(TimingBarGame.verdict(score: score))")
                }
                g.step(dt: c.dt)
                Self.timingFold(g, into: &h)
                bytes.append(h.frame.value)
                if frame % Self.checkpointEvery == 0 { checkpoints.append(h.total.value) }
            }
            cases.append([
                "id": .string(c.id), "seed": .hex64(c.seed), "dtBits": .bits(c.dt), "ops": .string(rle),
                "checkpointEvery": .int(Self.checkpointEvery),
                "checkpoints": .string(checkpoints.map(GoldenBits.hex64).joined(separator: " ")),
                "frameBytes": .string(bytes.text),
                "final": ["hash": .hex64(h.total.value), "frames": .int(frame), "phase": Self.timingPhase(g.phase),
                          "roundScores": GoldenCompact.ints(g.roundScores), "total": .int(g.total),
                          "targetBits": GoldenCompact.bits([g.target.center, g.target.width]),
                          "markerPositionBits": .bits(g.markerPosition)],
            ])
        }
        #expect(verdicts.count == 5, "대본이 판정 다섯을 다 거치지 않았다: \(verdicts.sorted())")
        goldenEmit(GoldenFile(
            golden: "timing-bar/scripted",
            equivalence: .bit,
            swiftSources: [Self.timingBar, Self.engine],
            spec: [
                "frame": "TimingBarGame(seed) → 처음 접기 → 프레임마다 연산(T = tap(), V = invalidate()) → step(dt) → 접기",
                "fold": "phase(ready 0 · running 1+round+t · roundResult 2+round+score+hold · finished 3+total) · roundScores 개수·값 · target center·width · markerPosition · lastHit(없으면 0, 있으면 1+값) · combo · total · round · isPlaying",
            ],
            cases: cases
        ))
    }

    // MARK: - framerate/fps (G1, 0~500Hz 전수)

    @Test("framerate/fps — 주사율 −5…500Hz → 목표 fps · 요구 간격 비트")
    func framerateFps() {
        let hzs = Array(-5...500)
        goldenEmit(GoldenFile(
            golden: "framerate/fps",
            equivalence: .bit,
            swiftSources: [Self.engine],
            spec: ["rules": "MiniGameFrameRate.targetFPS(forRefreshRate:) · minimumInterval(forRefreshRate:) — 규칙 ①~④ 는 원본 머리 주석"],
            cases: [
                ["id": "hz", "from": -5,
                 "targetFPS": GoldenCompact.ints(hzs.map { MiniGameFrameRate.targetFPS(forRefreshRate: $0) }),
                 "minimumIntervalBits": GoldenCompact.bits(hzs.map { MiniGameFrameRate.minimumInterval(forRefreshRate: $0) })],
                ["id": "constants", "baselineFPS": .int(MiniGameFrameRate.baselineFPS), "maxFPS": .int(MiniGameFrameRate.maxFPS),
                 "minFPS": .int(MiniGameFrameRate.minFPS), "minPlausibleHz": .int(MiniGameFrameRate.minPlausibleHz),
                 "vsyncHeadroomBits": .bits(MiniGameFrameRate.vsyncHeadroom)],
            ]
        ))
    }

    // MARK: - framerate/engine (G1 — MiniGameEngine 공용 값)

    @Test("framerate/engine — 게임 종류 표 · 캔버스 변환 · 뛰기 입력 꼬리 · 무대 고르기")
    func engineValues() {
        var cases: [GoldenJSON] = []
        cases.append(["id": "kinds",
                      "allCases": .string(MiniGameKind.allCases.map(\.rawValue).joined(separator: " ")),
                      "macCases": .string(MiniGameKind.macCases.map(\.rawValue).joined(separator: " ")),
                      "phoneCases": .string(MiniGameKind.phoneCases.map(\.rawValue).joined(separator: " ")),
                      "sharedControlHint": .string(MiniGameKind.controlHint),
                      "table": .array(MiniGameKind.allCases.map { kind -> GoldenJSON in
                          ["rawValue": .string(kind.rawValue), "id": .string(kind.id), "title": .string(kind.title),
                           "icon": .string(kind.icon), "maxScore": .int(kind.maxScore),
                           "roundTokenReuseSecondsBits": .bits(kind.roundTokenReuseSeconds),
                           "roundTokenMidRunRefreshSecondsBits": kind.roundTokenMidRunRefreshSeconds.map(GoldenJSON.bits) ?? .null,
                           "howToPlay": .string(kind.howToPlay), "controlHint": .string(kind.controlHint),
                           "isPhoneSupported": .bool(kind.isPhoneSupported)]
                      })])
        let sizes: [(Double, Double)] = [(344, 356), (292, 302), (1000, 100), (100, 1000), (0, 0), (375.5, 600.25), (-10, 50)]
        cases.append(["id": "canvas",
                      "logicalBits": GoldenCompact.bits([Double(MiniGameCanvas.logicalWidth), Double(MiniGameCanvas.logicalHeight)]),
                      "transforms": .array(sizes.map { (w, h) -> GoldenJSON in
                          let t = MiniGameCanvas.transform(in: CGSize(width: w, height: h), logicalSize: MiniGameCanvas.logicalSize)
                          return ["sizeBits": GoldenCompact.bits([w, h]),
                                  "resultBits": GoldenCompact.bits([Double(t.scale), Double(t.origin.x), Double(t.origin.y)])]
                      })])
        // 뛰기 입력 꼬리: 적기·묻기를 섞은 대본.
        var input = MiniGameInput()
        let directions = CrossyGame.Direction.allCases
        var steps: [String] = []
        var picker = MiniGameRandom(seed: 0x4801)
        for step in 0..<60 {
            if step % 4 == 3 {
                let since = input.hopCount - Int(picker.next() % 12)
                let hops = input.hops(since: since)
                steps.append("Q\(since)=\(hops.map(\.rawValue).joined(separator: "+"))")
            } else {
                let d = directions[Int(picker.next() % 4)]
                input.recordHop(d)
                steps.append("R\(d.rawValue)")
            }
        }
        cases.append(["id": "hops", "recentHopLimit": .int(MiniGameInput.recentHopLimit), "steps": .string(steps.joined(separator: " ")),
                      "finalHopCount": .int(input.hopCount),
                      "finalRecent": .string(input.recentHops.map(\.rawValue).joined(separator: " "))])
        cases.append(["id": "stages",
                      "table": .array(MiniGameStage.all.map { s -> GoldenJSON in
                          ["id": .int(s.id), "name": .string(s.name), "starCount": .int(s.starCount),
                           "hasAuroraBands": .bool(s.hasAuroraBands)]
                      }),
                      "flappyThresholds": GoldenCompact.ints(MiniGameStage.flappyThresholds),
                      "tetrisThresholds": GoldenCompact.ints(MiniGameStage.tetrisThresholds),
                      "flappyFrom": -3, "flappy": GoldenCompact.ints((-3...60).map { MiniGameStage.forFlappyScore($0).id }),
                      "timingFrom": -2, "timing": GoldenCompact.ints((-2...14).map { MiniGameStage.forTimingRound($0).id }),
                      "tetrisFrom": -5, "tetris": GoldenCompact.ints((-5...800).map { MiniGameStage.forTetrisAdvance($0).id })])
        goldenEmit(GoldenFile(
            golden: "framerate/engine",
            equivalence: .bit,
            swiftSources: [Self.engine],
            spec: [
                "kinds": "MiniGameKind 표(순서 = allCases = 화면 순서). 글자 칸은 화면 문구 그대로",
                "canvas": "MiniGameCanvas.transform(in: size, logicalSize: 292×302) → [scale, origin.x, origin.y] 비트",
                "hops": "MiniGameInput() 에 R<방향> = recordHop, Q<since>=<결과> = hops(since:) 를 + 로 이은 것(빈 결과는 빈 글자)",
                "stages": "무대 id · 이름 · 별 수와 고르기(플래피 점수 · 타이밍 라운드 · 테트리스 advance) — 색은 그림의 것이라 싣지 않는다",
            ],
            cases: cases
        ))
    }
}
