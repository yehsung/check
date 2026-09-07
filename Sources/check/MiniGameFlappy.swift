import AppKit
import SwiftUI

// MARK: - 플래피 아잉 (v0.2.46)
//
// 팝오버 미니게임 2종 중 하나. 규칙은 `FlappyGame`(순수 값 타입 — 뷰·스토어·시계 의존 0)에, 그림과 프레임 루프는
// `FlappyGameView`(잎 뷰 하나)에 있다. 허브(MiniGamePanel)는 `MiniGameHost` 와 `MiniGameInput` 만 건네고
// 게임은 그 둘 말고는 아무것도 읽지 않는다(MiniGame.swift 의 계약).
//
// 좌표계는 논리 292×200(y 는 아래로 +). 뷰는 `MiniGameCanvas.transform(in:)` 으로 실제 캔버스에 비율 유지로
// 맞추므로 팝오버 높이 예산 때문에 캔버스가 140~200 사이에서 바뀌어도 규칙·난이도는 그대로다.

/// 플래피 아잉 규칙. 시드만 주면 결정론적으로 같은 판이 나온다(테스트가 시드를 고정한다).
struct FlappyGame: Equatable, Sendable {
    // 논리 좌표·물리 상수. 클라·테스트가 같은 값을 본다.
    static let width: CGFloat = MiniGameCanvas.logicalWidth
    static let height: CGFloat = MiniGameCanvas.logicalHeight
    static let birdX: CGFloat = 0.28 * width
    /// 충돌 판정 상자(정사각). 스프라이트(30)보다 작게 둬 "닿은 것 같은데 죽었다"를 줄인다.
    static let hitboxSize: CGFloat = 22
    static let spriteSize: CGFloat = 30
    static let gravity: CGFloat = 1500
    static let flapVelocity: CGFloat = -430
    static let maxFallSpeed: CGFloat = 620
    /// 캔버스 아래 바닥띠. 히트박스 아래가 여기 닿으면 충돌.
    static let floorBand: CGFloat = 8
    static let pipeWidth: CGFloat = 44
    static let pipeSpacing: CGFloat = 150
    static let firstPipeX: CGFloat = width + 40
    /// 항상 화면 안팎에 유지하는 기둥 수(간격 150 × 3 = 450 > 폭 292 + 40 이라 빈 구간이 안 생긴다).
    static let pipeCount = 3
    static let maxScore = MiniGameKind.flappy.maxScore
    /// 게임오버 뒤 결과 카드가 뜨기까지의 유예(그 사이 클릭은 무시 — 죽자마자 실수로 새 판을 열지 않게).
    static let overHold: TimeInterval = 0.4
    /// 게임오버 순간 빨간 플래시 길이.
    static let flashDuration: TimeInterval = 0.15
    /// dt 상한. 앱 정지·팝오버 재표시 뒤 첫 프레임이 몇 초를 한 번에 밀지 않게.
    static let maxStep: TimeInterval = 1.0 / 30.0

    struct Pipe: Equatable, Sendable {
        var x: CGFloat
        var centerY: CGFloat
        var gap: CGFloat
        var passed: Bool = false

        /// 위 기둥 [0, centerY − gap/2].
        var topRect: CGRect {
            CGRect(x: x, y: 0, width: FlappyGame.pipeWidth, height: max(0, centerY - gap / 2))
        }
        /// 아래 기둥 [centerY + gap/2, H].
        func bottomRect(height: CGFloat) -> CGRect {
            let top = centerY + gap / 2
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
    }

    /// 테스트 픽스처 — 임의 상태에서 시작한다(난수는 seed).
    init(seed: UInt64, bird: Bird, pipes: [Pipe], score: Int, phase: Phase) {
        rng = MiniGameRandom(seed: seed)
        self.bird = bird
        self.pipes = pipes
        self.score = score
        self.phase = phase
        flashRemaining = 0
    }

    static func == (lhs: FlappyGame, rhs: FlappyGame) -> Bool {
        lhs.bird == rhs.bird && lhs.pipes == rhs.pipes && lhs.score == rhs.score
            && lhs.phase == rhs.phase && lhs.flashRemaining == rhs.flashRemaining
    }

    // MARK: 순수 규칙

    /// 틈 높이: 5점마다 2 줄고 62 에서 멈춘다.
    static func gap(forScore score: Int) -> CGFloat {
        max(62, 74 - CGFloat(2 * (max(0, score) / 5)))
    }

    /// 스크롤 속도(pt/s): 점수당 3 빨라지고 190 에서 멈춘다.
    static func speed(forScore score: Int) -> CGFloat {
        min(190, 120 + CGFloat(3 * max(0, score)))
    }

    /// 중력 적분 뒤 속도(최대 낙하 620 클램프).
    static func nextVelocity(_ vy: CGFloat, dt: TimeInterval) -> CGFloat {
        min(vy + gravity * CGFloat(dt), maxFallSpeed)
    }

    /// AABB — 히트박스가 위 기둥 또는 아래 기둥과 겹치면 충돌.
    static func collides(bird: CGRect, pipe: Pipe, height: CGFloat) -> Bool {
        bird.intersects(pipe.topRect) || bird.intersects(pipe.bottomRect(height: height))
    }

    /// 새 기둥. 틈 중심은 위·아래 여백 24(아래는 바닥띠 8 만큼 더) 를 두고 뽑는다.
    static func makePipe(x: CGFloat, score: Int, rng: inout MiniGameRandom) -> Pipe {
        let gap = gap(forScore: score)
        let lo = Double(gap / 2 + 24)
        let hi = Double(height - gap / 2 - 24 - floorBand)
        return Pipe(x: x, centerY: CGFloat(rng.uniform(lo, hi)), gap: gap)
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

    /// 허브가 판을 끊을 때(팝오버 닫힘·패널/게임 전환). 진행 중이면 그 점수로 결과 확정 — 점수는 유효하다.
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

        // 3) 화면 밖으로 완전히 나간 기둥은 버리고, 마지막 기둥 뒤 150 에 새 기둥(현재 점수의 틈).
        while let first = pipes.first, first.x + Self.pipeWidth < 0 {
            pipes.removeFirst()
            let lastX = pipes.last?.x ?? (Self.firstPipeX - Self.pipeSpacing)
            pipes.append(Self.makePipe(x: lastX + Self.pipeSpacing, score: score, rng: &rng))
        }

        // 4) 충돌: 바닥띠 또는 기둥.
        let box = hitbox
        if box.maxY >= Self.height - Self.floorBand
            || pipes.contains(where: { Self.collides(bird: box, pipe: $0, height: Self.height) }) {
            phase = .over(hold: Self.overHold)
            flashRemaining = Self.flashDuration
        }
    }

    private mutating func startRound() {
        bird = Bird(x: Self.birdX, y: Self.height / 2, vy: 0)
        score = 0
        flashRemaining = 0
        pipes = (0..<Self.pipeCount).map { i in
            Self.makePipe(x: Self.firstPipeX + CGFloat(i) * Self.pipeSpacing, score: 0, rng: &rng)
        }
        phase = .running
    }
}

// MARK: - 잎 뷰

/// 플래피 아잉 캔버스. 부모가 준 프레임(292×h)을 채우고, 규칙은 `FlappyGame` 에 맡긴다.
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
        let t = MiniGameCanvas.transform(in: size)
        func rect(_ r: CGRect) -> CGRect {
            CGRect(x: t.origin.x + r.minX * t.scale, y: t.origin.y + r.minY * t.scale,
                   width: r.width * t.scale, height: r.height * t.scale)
        }
        // 바닥띠.
        let floor = CGRect(x: 0, y: FlappyGame.height - FlappyGame.floorBand,
                           width: FlappyGame.width, height: FlappyGame.floorBand)
        context.fill(Path(rect(floor)), with: .color(CheckTheme.trackFill))
        // 기둥: 위·아래(아래는 바닥띠 위까지).
        for pipe in game.pipes {
            let top = pipe.topRect
            let bottom = pipe.bottomRect(height: FlappyGame.height - FlappyGame.floorBand)
            for r in [top, bottom] where r.height > 0 {
                let path = Path(roundedRect: rect(r), cornerRadius: 4 * t.scale, style: .continuous)
                context.fill(path, with: .color(CheckTheme.accent.opacity(0.55)))
                context.stroke(path, with: .color(CheckTheme.accent), lineWidth: 1)
            }
        }
    }

    /// 스프라이트(아잉 PNG)와 상단 점수. 위치는 논리 좌표를 실제 크기로 옮겨 놓는다.
    private var spriteAndScore: some View {
        GeometryReader { geo in
            let t = MiniGameCanvas.transform(in: geo.size)
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
                    .position(x: t.origin.x + FlappyGame.width / 2 * t.scale, y: t.origin.y + 22 * t.scale)
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

    @ViewBuilder
    private var overlayCard: some View {
        switch game.phase {
        case .ready:
            FlappyOverlayCard {
                Text(MiniGameKind.flappy.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckTheme.primaryText)
                Text(MiniGameKind.flappy.howToPlay)
                    .font(.system(size: 11))
                    .foregroundStyle(CheckTheme.primaryText)
                Text("클릭해서 시작")
                    .font(.system(size: 11))
                    .foregroundStyle(CheckTheme.secondaryText)
            }
        case .result:
            let isRecord = game.score > host.bestScore
            FlappyOverlayCard {
                Text("\(game.score)점")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.primaryText)
                if isRecord {
                    Text("신기록!")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CheckTheme.working)
                } else {
                    Text("최고 \(host.bestScore)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(CheckTheme.secondaryText)
                }
                Text("클릭해서 다시")
                    .font(.system(size: 11))
                    .foregroundStyle(CheckTheme.secondaryText)
            }
        case .running, .over:
            EmptyView()
        }
    }
}

/// 캔버스 위 안내/결과 카드(잔디 말풍선과 같은 바탕 — panelElevated + border, 모서리 10).
private struct FlappyOverlayCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 4) { content }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CheckTheme.panelElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(CheckTheme.border, lineWidth: 1)
            )
            .allowsHitTesting(false)
    }
}
