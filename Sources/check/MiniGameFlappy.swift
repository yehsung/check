import AppKit
import SwiftUI

// MARK: - 플래피 아잉 (v0.2.46)
//
// 미니게임 2종 중 하나. 규칙은 `FlappyGame`(순수 값 타입 — 뷰·스토어·시계 의존 0)에, 그림과 프레임 루프는
// `FlappyGameView`(잎 뷰 하나)에 있다. 허브(미니게임 창)는 `MiniGameHost` 와 `MiniGameInput` 만 건네고
// 게임은 그 둘 말고는 아무것도 읽지 않는다(MiniGame.swift 의 계약).
//
// ── 논리 좌표 292×302 (y 는 아래로 +) ─────────────────────────────────────────────────────
// 창 캔버스(344×356)와 **같은 비율**이다(292 × 356/344 = 302.19 → 302). 그래서 판이 캔버스를 꽉 채우고
// 기둥이 천장·바닥에 닿는다. 2026-09-08 실기 전까지는 292×200 이라 344×356 안에서 위아래 60pt 씩
// 레터박스가 생겼고, 사용자가 "천장에 구분이 없어 비어 보인다 · 바닥 표시가 어정쩡하다"고 지적했다.
// 뷰는 `MiniGameCanvas.transform(in:logicalSize:)` 로 비율을 유지해 그린다(남는 여백 ±0.5pt).
//
// ── 물리 상수 ────────────────────────────────────────────────────────────────────────────
// 판이 세로로 1.51배(302/200) 길어졌으므로 세로 물리량도 같은 배로 키워 **체감 난이도를 보존**한다:
// 중력 900→1360 · 점프 −210→−317(점프 높이 36.9pt ≈ 높이의 12.2%, 종전 24.5/200 = 12.25%) ·
// 낙하 상한 380→574. 히트박스 22→24 · 스프라이트 30→34(세로로 길어진 판에서 캐릭터가 묻히지 않게).
// 가로(폭 292 · 기둥 폭 44 · 첫 기둥까지 폭+80)는 그대로다.
// 바닥 띠는 없앴다 — 바닥은 캔버스의 아랫변 자체이고, 기둥은 위아래 끝까지 그린다.
//
// ── 난이도 곡선 ──────────────────────────────────────────────────────────────────────────
// "갈수록 어려워지게" (사용자, 2026-09-08). 네 값이 함께 조인다:
//   속도 130 → 3/점 → 230 상한(34점)   ·   틈 132 → −3/점 → 96 하한(12점)   ·   간격 150 → −2/점 → 115 하한(18점)
//   그리고 5점부터 **틈이 위아래로 움직이는 기둥**이 확률로 섞인다(아래).
//
// ── 갑자기 튀는 틈(surprise jump) ────────────────────────────────────────────────────────
// 2026-09-08 실기 뒤 사용자 요청: "기둥 빈 위치가 갑자기 서프라이즈로 옮겨지게 · 차라리 속도 빨라지는 정도는 낮추고."
// 그래서 속도 상승률을 절반(6→3/점, 상한 300→230)으로 낮추고, 그 자리에 **틈이 한 번 확 튀는 기둥**을 넣었다.
//   · 언제부터: 점수 15 이상에서 **생성되는** 기둥부터(0~14 는 전부 고정 — 조작을 익힐 시간을 준다).
//   · 어느 기둥이: 점수와 무관하게 **20%**. 전부가 아니라 섞이기 때문에 "갑자기"가 성립한다.
//   · 어떻게: 기둥이 화면 오른쪽 끝에 들어온 뒤 `shiftDelay`(0.45~1.10초, 기둥마다 난수)가 지나면 틈 중심이
//     **한 번만** 위나 아래로 `shiftJump`(58pt) 튄다. 왕복하지 않는다 — 서프라이즈는 한 방이어야 무섭다.
//     0.12초 easeOut 보간이라 눈에는 순간이동처럼 보이지만 프레임 사이가 이어져 충돌이 어긋나지 않는다.
//   · 클램프: 튄 뒤 중심이 여백(`centerMargin` 36) 밖이면 반대 방향으로 튀고, 양쪽 다 불가능하면 고정 기둥이 된다.
//   · **색 신호는 없다**(사용자: "움직이는 기둥 뭔지 알려 주지 말자"). 고정 기둥과 픽셀 단위로 같게 그린다.
//   · 틈 폭 보정도 없다 — 고정 기둥과 같은 `gap(forScore:)` 을 쓴다.


/// 플래피 아잉 규칙. 시드만 주면 결정론적으로 같은 판이 나온다(테스트가 시드를 고정한다).
struct FlappyGame: Equatable, Sendable {
    // 논리 좌표·물리 상수. 클라·테스트가 같은 값을 본다.
    static let width: CGFloat = MiniGameCanvas.logicalWidth
    /// 창 캔버스(344×356)와 같은 비율의 세로 길이 — 이 게임만의 판 크기다(공용 200 이 아니다).
    static let height: CGFloat = 302
    /// 뷰가 `MiniGameCanvas.transform(in:logicalSize:)` 에 넘기는 판 크기.
    static var logicalSize: CGSize { CGSize(width: width, height: height) }
    static let birdX: CGFloat = 0.28 * width
    /// 충돌 판정 상자(정사각). 스프라이트(34)보다 작게 둬 "닿은 것 같은데 죽었다"를 줄인다.
    static let hitboxSize: CGFloat = 24
    static let spriteSize: CGFloat = 34
    static let gravity: CGFloat = 1360
    /// 점프 높이 = 317² / (2·1360) = 36.9pt(판 높이의 12.2%).
    static let flapVelocity: CGFloat = -317
    static let maxFallSpeed: CGFloat = 574
    static let pipeWidth: CGFloat = 44
    /// 첫 기둥은 화면 밖 80pt 에서 시작 — 시작 직후 자세를 잡을 시간(≈0.6초)을 준다.
    static let firstPipeX: CGFloat = width + 80
    /// 항상 화면 안팎에 유지하는 기둥 수. 간격이 최소(115)여도 세 개가 폭 292 를 덮고 하나가 오른쪽 밖에 대기한다.
    static let pipeCount = 3
    static let maxScore = MiniGameKind.flappy.maxScore
    /// 틈 중심을 뽑을 때 위·아래로 남기는 여백(세로 1.51배에 맞춰 24 → 36).
    static let centerMargin: CGFloat = 36
    /// 게임오버 뒤 결과 카드가 뜨기까지의 유예(그 사이 클릭은 무시 — 죽자마자 실수로 새 판을 열지 않게).
    static let overHold: TimeInterval = 0.4
    /// 게임오버 순간 빨간 플래시 길이.
    static let flashDuration: TimeInterval = 0.15
    /// dt 상한. 앱 정지·창 재표시 뒤 첫 프레임이 몇 초를 한 번에 밀지 않게.
    static let maxStep: TimeInterval = 1.0 / 30.0

    struct Pipe: Equatable, Sendable {
        var x: CGFloat
        /// 틈 중심의 **기준선**. 고정 기둥이면 이 값이 곧 중심이고, 움직이는 기둥이면 이 값을 중심으로 왕복한다.
        var centerY: CGFloat
        var gap: CGFloat
        var passed: Bool = false
        /// 화면에 들어온 뒤 튀기까지의 지연(초). **nil 이면 고정 기둥**이다.
        var shiftDelay: TimeInterval?
        /// 튀는 폭과 방향(+ 아래 · − 위). `shiftDelay` 가 nil 이면 0.
        var shiftOffset: CGFloat = 0
        /// 튀기 시작하는 **판 시각**(초). 기둥이 화면 오른쪽 끝에 들어올 때 `elapsed + shiftDelay` 로 한 번 채워진다.
        /// 채워지기 전(nil)에는 기준선 그대로다 — 화면 밖에서 미리 튀어 버리면 서프라이즈가 아니라 사고다.
        var shiftAt: TimeInterval?

        /// 이 기둥이 언젠가 튀는가(테스트·조준 판정용). 그림은 이 값을 보지 않는다 — 색 신호가 없기 때문이다.
        var isShifting: Bool { shiftDelay != nil }

        /// 그 시각의 틈 중심. **충돌·그리기가 같은 이 함수를 쓴다** — 갈라지면 "안 닿았는데 죽었다"가 된다.
        ///
        /// 튀기 전에는 기준선, `shiftAt` 부터 `shiftDuration`(0.12초) 동안 easeOut 으로 `shiftOffset` 만큼 옮겨 간 뒤
        /// 그 자리에 머문다(왕복 없음). 마지막 클램프는 손으로 만든 픽스처 대비다 — 실제 생성은 아래 `makePipe` 가
        /// 여백 안에서만 방향을 고르므로 걸리지 않는다.
        func center(at time: TimeInterval) -> CGFloat {
            guard let shiftAt else { return centerY }
            let progress = min(max((time - shiftAt) / FlappyGame.shiftDuration, 0), 1)
            let eased = 1 - pow(1 - progress, 3)          // easeOut — 시작이 가장 빠르다
            let moved = centerY + shiftOffset * CGFloat(eased)
            return min(max(moved, gap / 2), FlappyGame.height - gap / 2)
        }

        /// 위 기둥 [0, center − gap/2] — 천장에 붙는다.
        func topRect(at time: TimeInterval) -> CGRect {
            CGRect(x: x, y: 0, width: FlappyGame.pipeWidth, height: max(0, center(at: time) - gap / 2))
        }
        /// 아래 기둥 [center + gap/2, height] — 바닥에 붙는다.
        func bottomRect(at time: TimeInterval, height: CGFloat) -> CGRect {
            let top = center(at: time) + gap / 2
            return CGRect(x: x, y: top, width: FlappyGame.pipeWidth, height: max(0, height - top))
        }
    }

    struct Bird: Equatable, Sendable {
        var x: CGFloat
        var y: CGFloat
        var vy: CGFloat
    }

    enum Phase: Equatable, Sendable {
        /// 시작 전(루프 정지). 액션 = 새 판 + 첫 점프.
        case ready
        case running
        /// 충돌 직후. `hold` 초가 남았고 다 지나면 `.result`.
        case over(hold: TimeInterval)
        /// 결과 카드(루프 정지). 액션 = 새 판 + 첫 점프.
        case result
    }

    private(set) var bird: Bird
    private(set) var pipes: [Pipe]
    private(set) var score: Int
    private(set) var phase: Phase
    /// 게임오버 플래시 잔여 시간(0 이면 없음).
    private(set) var flashRemaining: TimeInterval
    /// 이번 판이 시작된 뒤 흐른 시간(초). 움직이는 기둥의 틈 위치가 이 시계를 본다 —
    /// 벽시계가 아니라 `step(dt:)` 이 흘린 시간이라 판이 결정적으로 재현된다.
    private(set) var elapsed: TimeInterval
    private var rng: MiniGameRandom

    /// 프레임 루프가 돌아야 하는 상태(running · over 유예). ready/result 는 정지.
    var isPlaying: Bool {
        switch phase {
        case .running, .over: true
        case .ready, .result: false
        }
    }

    /// 게임오버 이후(over·result) — 스프라이트 표정을 시무룩으로.
    var isGameOver: Bool {
        switch phase {
        case .over, .result: true
        case .ready, .running: false
        }
    }

    var hitbox: CGRect {
        CGRect(x: bird.x - Self.hitboxSize / 2, y: bird.y - Self.hitboxSize / 2,
               width: Self.hitboxSize, height: Self.hitboxSize)
    }

    init(seed: UInt64) {
        rng = MiniGameRandom(seed: seed)
        bird = Bird(x: Self.birdX, y: Self.height / 2, vy: 0)
        pipes = []
        score = 0
        phase = .ready
        flashRemaining = 0
        elapsed = 0
    }

    /// 테스트 픽스처 — 임의 상태에서 시작한다(난수는 seed).
    init(seed: UInt64, bird: Bird, pipes: [Pipe], score: Int, phase: Phase, elapsed: TimeInterval = 0) {
        rng = MiniGameRandom(seed: seed)
        self.bird = bird
        self.pipes = pipes
        self.score = score
        self.phase = phase
        flashRemaining = 0
        self.elapsed = elapsed
    }

    static func == (lhs: FlappyGame, rhs: FlappyGame) -> Bool {
        lhs.bird == rhs.bird && lhs.pipes == rhs.pipes && lhs.score == rhs.score
            && lhs.phase == rhs.phase && lhs.flashRemaining == rhs.flashRemaining && lhs.elapsed == rhs.elapsed
    }

    // MARK: 순수 규칙 — 난이도 곡선

    /// 틈 높이: 132 에서 점수당 3 줄고 96 에서 멈춘다(12점부터). 판 높이 대비 43.7% → 31.8%.
    static func gap(forScore score: Int) -> CGFloat {
        max(96, 132 - CGFloat(3 * max(0, score)))
    }

    /// 스크롤 속도(pt/s): 130 에서 점수당 3 빨라지고 230 에서 멈춘다(34점부터).
    /// 상승률을 절반으로 낮춘 자리에 아래 '움직이는 틈'이 들어왔다(사용자 요청 2026-09-08).
    static func speed(forScore score: Int) -> CGFloat {
        min(230, 130 + CGFloat(3 * max(0, score)))
    }

    /// 기둥 사이 수평 간격: 150 에서 점수당 2 좁아지고 115 에서 멈춘다(18점부터) — 기둥이 더 자주 온다.
    static func spacing(forScore score: Int) -> CGFloat {
        max(115, 150 - CGFloat(2 * max(0, score)))
    }

    /// 튀는 기둥이 나오기 시작하는 점수. 그 전에는 전부 고정이다(조작을 익힐 시간).
    static let shiftMinScore = 15
    /// 새 기둥이 '튀는 기둥'일 확률. 점수와 무관한 상수 — 30%(2026-09-08 실기 뒤 20% → 30%).
    static let shiftChance = 0.30
    /// 한 번에 튀는 폭(pt). 논리 302 판에서 틈 하나 남짓 — 눈에 확 띄되 반응할 수 있는 크기다.
    static let shiftJump: CGFloat = 58
    /// 화면에 들어온 뒤 튀기까지의 지연 범위(초). 기둥마다 난수라 언제 튈지 외울 수 없다.
    static let shiftDelayRange: ClosedRange<TimeInterval> = 0.45...1.10
    /// 튀는 데 걸리는 시간(초). 순간이동처럼 보이되 프레임 사이가 이어진다.
    static let shiftDuration: TimeInterval = 0.12

    // MARK: 순수 규칙 — 물리·충돌

    /// 중력 적분 뒤 속도(최대 낙하 574 클램프).
    static func nextVelocity(_ vy: CGFloat, dt: TimeInterval) -> CGFloat {
        min(vy + gravity * CGFloat(dt), maxFallSpeed)
    }

    /// AABB — 히트박스가 그 시각의 위 기둥 또는 아래 기둥과 겹치면 충돌.
    /// `time` 은 움직이는 기둥의 틈 위치를 정한다(그림과 같은 함수를 쓴다).
    static func collides(bird: CGRect, pipe: Pipe, height: CGFloat, time: TimeInterval) -> Bool {
        bird.intersects(pipe.topRect(at: time)) || bird.intersects(pipe.bottomRect(at: time, height: height))
    }

    /// 새 기둥. 틈 중심은 위·아래 여백 `centerMargin` 을 두고 뽑는다(바닥 띠가 없으므로 아래도 같은 값).
    ///
    /// 점수 15 이상이면 20% 로 '튀는 기둥'이 된다. 난수 소비 순서(기준선 → 판정 → 지연 → 방향)는 결정론의 일부다 —
    /// 15점 미만에서는 `&&` 단락 평가로 판정 난수를 아예 쓰지 않아 초반 판이 종전과 같은 모양으로 남는다.
    /// 방향은 여백 안에 들어가는 쪽으로만 고르고, 양쪽 다 안 되면 고정 기둥으로 강등한다(틈이 화면 밖으로 새지 않게).
    static func makePipe(x: CGFloat, score: Int, rng: inout MiniGameRandom) -> Pipe {
        let gap = gap(forScore: score)
        let lo = Double(gap / 2 + centerMargin)
        let hi = Double(height - gap / 2 - centerMargin)
        let center = CGFloat(rng.uniform(lo, hi))
        guard score >= shiftMinScore, rng.unit() < shiftChance else {
            return Pipe(x: x, centerY: center, gap: gap)
        }
        let delay = rng.uniform(shiftDelayRange.lowerBound, shiftDelayRange.upperBound)
        let wantsDown = rng.unit() < 0.5
        let canDown = Double(center + shiftJump) <= hi
        let canUp = Double(center - shiftJump) >= lo
        let offset: CGFloat
        switch (wantsDown, canDown, canUp) {
        case (true, true, _), (false, true, false): offset = shiftJump
        case (false, _, true), (true, false, true): offset = -shiftJump
        default: return Pipe(x: x, centerY: center, gap: gap)   // 양쪽 다 여백 밖 — 고정으로 강등
        }
        return Pipe(x: x, centerY: center, gap: gap, shiftDelay: delay, shiftOffset: offset)
    }

    // MARK: 전이

    /// 액션(클릭·스페이스). ready/result 면 새 판 + 첫 점프, running 이면 점프, over 유예 중엔 무시.
    mutating func flap() {
        switch phase {
        case .ready, .result:
            startRound()
            bird.vy = Self.flapVelocity
        case .running:
            bird.vy = Self.flapVelocity
        case .over:
            break
        }
    }

    /// 허브가 판을 끊을 때(창 닫힘·포커스 상실·게임 전환). 진행 중이면 그 점수로 결과 확정 — 점수는 유효하다.
    mutating func interrupt() {
        switch phase {
        case .running, .over:
            phase = .result
            flashRemaining = 0
        case .ready, .result:
            break
        }
    }

    mutating func step(dt rawDt: TimeInterval) {
        let dt = min(max(0, rawDt), Self.maxStep)
        switch phase {
        case .ready, .result:
            return
        case .over(let hold):
            flashRemaining = max(0, flashRemaining - dt)
            let left = hold - dt
            phase = left <= 0 ? .result : .over(hold: left)
            return
        case .running:
            break
        }

        // 0) 판 시계. 움직이는 기둥의 틈은 이 값만 본다(벽시계 아님 — 재현 가능하다).
        elapsed += dt

        // 1) 캐릭터: 중력 → 위치. 천장은 히트박스 윗변을 0 에 붙이고 속도만 죽인다(충돌 아님).
        bird.vy = Self.nextVelocity(bird.vy, dt: dt)
        bird.y += bird.vy * CGFloat(dt)
        if bird.y - Self.hitboxSize / 2 < 0 {
            bird.y = Self.hitboxSize / 2
            bird.vy = 0
        }

        // 2) 기둥 스크롤 + 통과 점수. 점수는 "이번 프레임에 오른쪽 끝을 넘었다"로 기둥당 한 번.
        let speed = Self.speed(forScore: score)
        for i in pipes.indices {
            pipes[i].x -= speed * CGFloat(dt)
            // 화면 오른쪽 끝에 들어온 순간 '튈 시각'을 확정한다(화면 밖에서 미리 튀면 서프라이즈가 아니다).
            if let delay = pipes[i].shiftDelay, pipes[i].shiftAt == nil, pipes[i].x <= Self.width {
                pipes[i].shiftAt = elapsed + delay
            }
            if !pipes[i].passed, bird.x > pipes[i].x + Self.pipeWidth {
                pipes[i].passed = true
                score += 1
            }
        }
        if score >= Self.maxScore {
            score = Self.maxScore
            phase = .result
            return
        }

        // 3) 화면 밖으로 완전히 나간 기둥은 버리고, 마지막 기둥 뒤 `spacing(현재 점수)` 에 새 기둥
        //    (틈도 현재 점수 기준 — 점수가 오를수록 좁고 자주 온다).
        while let first = pipes.first, first.x + Self.pipeWidth < 0 {
            pipes.removeFirst()
            let gapToNext = Self.spacing(forScore: score)
            let lastX = pipes.last?.x ?? (Self.firstPipeX - gapToNext)
            pipes.append(Self.makePipe(x: lastX + gapToNext, score: score, rng: &rng))
        }

        // 4) 충돌: 바닥(캔버스 아랫변) 또는 기둥.
        let box = hitbox
        if box.maxY >= Self.height
            || pipes.contains(where: { Self.collides(bird: box, pipe: $0, height: Self.height, time: elapsed) }) {
            phase = .over(hold: Self.overHold)
            flashRemaining = Self.flashDuration
        }
    }

    private mutating func startRound() {
        bird = Bird(x: Self.birdX, y: Self.height / 2, vy: 0)
        score = 0
        flashRemaining = 0
        elapsed = 0
        let gapToNext = Self.spacing(forScore: 0)
        pipes = (0..<Self.pipeCount).map { i in
            Self.makePipe(x: Self.firstPipeX + CGFloat(i) * gapToNext, score: 0, rng: &rng)
        }
        phase = .running
    }
}

// MARK: - 잎 뷰

/// 플래피 아잉 캔버스. 부모가 준 프레임을 채우고, 규칙은 `FlappyGame` 에 맡긴다.
///
/// 프레임 루프는 `TimelineView(.animation(paused:))` 하나뿐이다 — 진행 중(running·over 유예)일 때만 돌고, ready/result
/// 와 허브의 interrupt 뒤엔 멈춘다(유휴 0%). 틱은 TimelineView 의 날짜가 바뀔 때(`onChange`)만 일어나므로 body 평가
/// 도중 상태를 바꾸지 않는다.
struct FlappyGameView: View {
    let host: MiniGameHost
    let input: MiniGameInput

    @State private var game: FlappyGame
    @State private var lastTick: Date?

    init(host: MiniGameHost, input: MiniGameInput, initialGame: FlappyGame? = nil) {
        self.host = host
        self.input = input
        // 시드는 시각에서 — 판마다 다른 기둥. 테스트는 initialGame 으로 고정한다.
        let seed = UInt64(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000))
        _game = State(initialValue: initialGame ?? FlappyGame(seed: seed))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !game.isPlaying)) { context in
            canvas
                .onChange(of: context.date) { _, now in tick(now) }
        }
        .onChange(of: input.actionCount) { _, _ in act() }
        .onChange(of: host.interruptToken) { _, _ in
            game.interrupt()
        }
        .onChange(of: game.isPlaying) { _, playing in
            host.onPlayingChanged(playing)
        }
        .onChange(of: game.phase) { old, new in
            // 결과 확정은 판마다 한 번 — running/over → result 전이가 그 순간이다(interrupt 포함).
            if new == .result, old != .result { host.onFinished(game.score) }
        }
    }

    private func act() {
        let wasPlaying = game.isPlaying
        game.flap()
        // 새 판 첫 프레임은 정지해 있던 동안의 시간을 물려받지 않는다.
        if !wasPlaying, game.isPlaying { lastTick = nil }
    }

    private func tick(_ now: Date) {
        guard game.isPlaying else { return }
        MiniGameFrameProbe.note()
        defer { lastTick = now }
        guard let last = lastTick else { return }
        game.step(dt: now.timeIntervalSince(last))
    }

    // MARK: 그림

    private var canvas: some View {
        ZStack {
            Canvas(rendersAsynchronously: false) { context, size in
                draw(&context, size: size)
            }
            spriteAndScore
            if !host.reduceMotion, game.flashRemaining > 0 {
                CheckTheme.danger
                    .opacity(0.25 * game.flashRemaining / FlappyGame.flashDuration)
                    .allowsHitTesting(false)
            }
            overlayCard
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CheckTheme.fieldFill))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let t = MiniGameCanvas.transform(in: size, logicalSize: FlappyGame.logicalSize)
        func rect(_ r: CGRect) -> CGRect {
            CGRect(x: t.origin.x + r.minX * t.scale, y: t.origin.y + r.minY * t.scale,
                   width: r.width * t.scale, height: r.height * t.scale)
        }
        // 기둥: 위는 천장까지, 아래는 바닥까지. 사각으로 그려 끝이 캔버스 가장자리에 딱 붙는다
        // (모서리를 둥글리면 천장·바닥에 틈이 생겨 "떠 있는 막대"로 보인다 — 그 지적이 이 판의 이유다).
        // 튀는 기둥도 고정 기둥과 **똑같이** 그린다 — 색으로 미리 알려 주지 않는 것이 이 규칙의 핵심이다
        // (사용자, 2026-09-08). 구분이 필요하면 규칙(center(at:))이 아니라 눈으로 겪어야 한다.
        for pipe in game.pipes {
            let halves = [pipe.topRect(at: game.elapsed),
                          pipe.bottomRect(at: game.elapsed, height: FlappyGame.height)]
            for r in halves where r.height > 0 {
                let path = Path(rect(r))
                context.fill(path, with: .color(CheckTheme.accent.opacity(0.55)))
                context.stroke(path, with: .color(CheckTheme.accent), lineWidth: 1)
            }
        }
    }

    /// 스프라이트(아잉 PNG)와 상단 점수. 위치는 논리 좌표를 실제 크기로 옮겨 놓는다.
    private var spriteAndScore: some View {
        GeometryReader { geo in
            let t = MiniGameCanvas.transform(in: geo.size, logicalSize: FlappyGame.logicalSize)
            let side = FlappyGame.spriteSize * t.scale
            sprite
                .frame(width: side, height: side)
                .rotationEffect(.degrees(spriteAngle))
                .position(x: t.origin.x + game.bird.x * t.scale, y: t.origin.y + game.bird.y * t.scale)
            if showsTopScore {
                Text("\(game.score)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.primaryText)
                    .position(x: t.origin.x + FlappyGame.width / 2 * t.scale, y: t.origin.y + 26 * t.scale)
            }
        }
        .allowsHitTesting(false)
    }

    private var showsTopScore: Bool {
        switch game.phase {
        case .running, .over: true
        case .ready, .result: false
        }
    }

    /// 낙하 속도에 비례해 기운다(위로 −20°, 아래로 +25°). 동작 줄이기면 0.
    private var spriteAngle: Double {
        guard !host.reduceMotion else { return 0 }
        let raw = Double(game.bird.vy / FlappyGame.maxFallSpeed) * 25
        return min(25, max(-20, raw))
    }

    @ViewBuilder
    private var sprite: some View {
        // 공유 캐시 원본이다 — size 를 바꾸거나 lockFocus 로 그리면 메뉴바·헤더까지 오염된다. SwiftUI 축소만.
        if let image = CheckMascotAssets.image(for: game.isGameOver ? .negative : .neutral) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Circle().fill(CheckTheme.working)
        }
    }

    /// 시작·결과 카드는 두 게임이 **같은** `MiniGameOverlayCard` 를 쓴다(색·글씨 통일 — 2026-09-08 지적).
    @ViewBuilder
    private var overlayCard: some View {
        switch game.phase {
        case .ready:
            MiniGameOverlayCard(
                title: MiniGameKind.flappy.title,
                subtitle: MiniGameKind.flappy.howToPlay,
                action: "클릭해서 시작"
            )
        case .result:
            MiniGameOverlayCard(
                title: "\(game.score)점",
                titleIsScore: true,
                subtitle: game.score > host.bestScore ? "신기록!" : "최고 \(host.bestScore)",
                subtitleIsHighlighted: game.score > host.bestScore,
                action: "클릭해서 다시"
            )
        case .running, .over:
            EmptyView()
        }
    }
}
