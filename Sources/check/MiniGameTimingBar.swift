import SwiftUI

// MARK: - 타이밍 바 (v0.2.46 미니게임)
//
// 왕복하는 마커를 목표 구간 안에서 멈추는 10라운드 게임. 규칙(`TimingBarGame`)은 뷰를 전혀 모르는 값 타입이고,
// 시간은 `step(dt:)` 로만 흐르며 난수는 시드로 주입한 `MiniGameRandom` 만 쓴다 — 같은 시드·같은 입력이면 같은 판이라
// 테스트가 "목표 중심에 마커가 오는 시각"을 역산해 100점을 재현한다. 뷰(`TimingBarGameView`)는 상태를 `@State` 로 들고
// `TimelineView(.animation)` 으로 전진시킬 뿐, 입력은 허브가 `MiniGameInput.actionCount` 로 넘긴다(제스처 없음).

// MARK: 규칙

struct TimingBarGame: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// 시작 전. 루프는 멈춰 있다.
        case ready
        /// 라운드 진행 중. `t` 는 라운드 시작부터 흐른 초.
        case running(round: Int, t: TimeInterval)
        /// 정지 직후 결과 표시. `hold` 가 0 이 되면 다음 라운드(또는 finished)로 스스로 넘어간다.
        case roundResult(round: Int, score: Int, hold: TimeInterval)
        /// 10라운드 끝. 클릭하면 바로 새 판.
        case finished(total: Int)
    }

    static let roundCount = 10
    /// 라운드 결과("+N")를 보여 주는 시간.
    static let resultHold: TimeInterval = 0.6
    /// 한 걸음의 상한. 앱 정지·팝오버 재표시 뒤 첫 프레임이 몇 초를 한꺼번에 흘리지 않게.
    static let maxStep: TimeInterval = 1.0 / 30.0

    private(set) var phase: Phase = .ready
    private(set) var roundScores: [Int] = []
    private var targetCenter: Double = 0.5
    private var targetWidthValue: Double = 0.30
    /// 정지한 자리(결과 표시 동안 마커를 얼려 둔다).
    private var stoppedPosition: Double?
    /// 마지막 정지가 목표 안이었는지(마커 색). 시작 전·무효 뒤엔 nil.
    private(set) var lastHit: Bool?
    private var rng: MiniGameRandom

    init(seed: UInt64) {
        rng = MiniGameRandom(seed: seed)
    }

    // 난수 상태는 비교하지 않는다 — "같은 화면"인지가 관심사이고, MiniGameRandom 은 Equatable 이 아니다.
    static func == (lhs: TimingBarGame, rhs: TimingBarGame) -> Bool {
        lhs.phase == rhs.phase && lhs.roundScores == rhs.roundScores
            && lhs.targetCenter == rhs.targetCenter && lhs.targetWidthValue == rhs.targetWidthValue
            && lhs.stoppedPosition == rhs.stoppedPosition && lhs.lastHit == rhs.lastHit
    }

    // MARK: 읽기

    /// 현재(또는 마지막) 라운드 번호. 시작 전 0.
    var round: Int {
        switch phase {
        case .ready: 0
        case .running(let round, _), .roundResult(let round, _, _): round
        case .finished: Self.roundCount
        }
    }

    var total: Int { roundScores.reduce(0, +) }

    /// 루프가 돌아야 하는 상태(진행 중 또는 결과 표시 중).
    var isPlaying: Bool {
        switch phase {
        case .running, .roundResult: true
        case .ready, .finished: false
        }
    }

    /// 트랙 위 마커 위치 0…1. 결과 표시 중엔 정지한 자리에 얼어 있다.
    var markerPosition: Double {
        switch phase {
        case .running(let round, let t): Self.markerPosition(t: t, period: Self.period(round: round))
        case .roundResult: stoppedPosition ?? 0
        case .ready, .finished: 0
        }
    }

    var target: (center: Double, width: Double) { (targetCenter, targetWidthValue) }

    // MARK: 순수 함수(스펙 상수)

    /// 라운드 주기(초). 갈수록 빨라지되 0.55 밑으로는 안 내려간다.
    static func period(round: Int) -> Double {
        max(0.55, 1.40 - 0.09 * Double(round - 1))
    }

    /// 목표 구간 폭(트랙 길이 = 1). 갈수록 좁아지되 0.10 밑으로는 안 내려간다.
    static func targetWidth(round: Int) -> Double {
        max(0.10, 0.30 - 0.022 * Double(round - 1))
    }

    /// 삼각파 0→1→0. t=0 에서 0, t=T/2 에서 1, t=T 에서 다시 0.
    static func markerPosition(t: Double, period: Double) -> Double {
        let x = t / period
        return 2 * abs(x - (x + 0.5).rounded(.down))
    }

    /// 목표 중심에서의 거리 d(= |p − c| / (w/2)) 를 점수로. 안(≤1)은 60~100, 두 배 폭 안은 0~30, 그 밖은 0.
    static func roundScore(distance d: Double) -> Int {
        if d <= 1 { return 100 - Int((40 * d).rounded()) }
        if d <= 2 { return max(0, 30 - Int((30 * (d - 1)).rounded())) }
        return 0
    }

    // MARK: 전이

    mutating func step(dt: TimeInterval) {
        let dt = min(max(dt, 0), Self.maxStep)
        switch phase {
        case .running(let round, let t):
            phase = .running(round: round, t: t + dt)
        case .roundResult(let round, let score, let hold):
            let remaining = hold - dt
            if remaining > 0 {
                phase = .roundResult(round: round, score: score, hold: remaining)
            } else if round >= Self.roundCount {
                phase = .finished(total: total)
            } else {
                startRound(round + 1)
            }
        case .ready, .finished:
            break
        }
    }

    /// 클릭. 시작 전/끝난 뒤엔 새 판, 진행 중엔 정지. 결과 표시 중엔 무시(두 번 눌러 다음 라운드를 잃지 않게).
    mutating func tap() {
        switch phase {
        case .ready, .finished:
            roundScores = []
            lastHit = nil
            stoppedPosition = nil
            startRound(1)
        case .running(let round, let t):
            let p = Self.markerPosition(t: t, period: Self.period(round: round))
            let d = abs(p - targetCenter) / (targetWidthValue / 2)
            let score = Self.roundScore(distance: d)
            roundScores.append(score)
            lastHit = d <= 1
            stoppedPosition = p
            phase = .roundResult(round: round, score: score, hold: Self.resultHold)
        case .roundResult:
            break
        }
    }

    /// 판 무효(팝오버 닫힘·패널 전환). 점수는 버리고 시작 전으로.
    mutating func invalidate() {
        phase = .ready
        roundScores = []
        lastHit = nil
        stoppedPosition = nil
    }

    private mutating func startRound(_ round: Int) {
        let width = Self.targetWidth(round: round)
        targetWidthValue = width
        targetCenter = rng.uniform(width / 2 + 0.05, 1 - width / 2 - 0.05)
        stoppedPosition = nil
        phase = .running(round: round, t: 0)
    }
}

// MARK: - 잎 뷰

/// 타이밍 바 게임 화면. 상태는 이 뷰의 `@State` 에만 살고, 프레임은 진행 중일 때만 `TimelineView(.animation)` 이 돌린다.
/// 허브가 주는 것: `host`(최고기록·동작 줄이기·중단 토큰·콜백) 와 `input`(클릭/스페이스 카운터). 그 밖의 앱 상태는 모른다.
struct TimingBarGameView: View {
    let host: MiniGameHost
    let input: MiniGameInput

    @State private var game: TimingBarGame
    @State private var lastAction: Int
    @State private var lastTick: Date?
    /// `.finished` 진입을 허브에 **한 번만** 알리기 위한 표시.
    @State private var reportedFinish = false

    init(host: MiniGameHost, input: MiniGameInput, initialGame: TimingBarGame? = nil) {
        self.host = host
        self.input = input
        // 실제 플레이의 시드는 시각(밀리초)이면 충분하다 — 테스트는 initialGame 으로 시드를 고정한다.
        _game = State(initialValue: initialGame ?? TimingBarGame(seed: UInt64(Date().timeIntervalSince1970 * 1000)))
        _lastAction = State(initialValue: input.actionCount)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !game.isPlaying)) { context in
            TimingBarFrame(game: game, bestScore: host.bestScore, reduceMotion: host.reduceMotion)
                // 상태 변경은 본문 평가 중이 아니라 프레임 시각이 **바뀐 뒤**(onChange)에 한다.
                .onChange(of: context.date) { _, now in tick(now) }
        }
        .onChange(of: input.actionCount) { _, count in handleAction(count) }
        .onChange(of: host.interruptToken) { _, _ in interrupt() }
    }

    // MARK: 전이

    private func tick(_ now: Date) {
        guard game.isPlaying else { lastTick = nil; return }
        MiniGameFrameProbe.note()
        defer { lastTick = now }
        guard let last = lastTick else { return }          // 시작 뒤 첫 프레임은 기준만 잡는다.
        game.step(dt: min(now.timeIntervalSince(last), TimingBarGame.maxStep))
        if case .finished(let total) = game.phase, !reportedFinish {
            reportedFinish = true
            host.onFinished(total)
            host.onPlayingChanged(false)
        }
    }

    private func handleAction(_ count: Int) {
        guard count != lastAction else { return }
        lastAction = count
        let wasPlaying = game.isPlaying
        game.tap()
        if game.isPlaying, !wasPlaying {
            reportedFinish = false
            lastTick = nil
            host.onPlayingChanged(true)
        }
    }

    private func interrupt() {
        let wasPlaying = game.isPlaying
        game.invalidate()
        lastTick = nil
        if wasPlaying { host.onPlayingChanged(false) }
    }
}

// MARK: - 그림

/// 한 프레임의 그림. 논리 좌표(292×200)를 부모가 준 크기에 비율 유지로 맞춘다 — 캔버스가 140 까지 낮아져도 규칙은 그대로다.
private struct TimingBarFrame: View {
    let game: TimingBarGame
    let bestScore: Int
    let reduceMotion: Bool

    @State private var container = CGSize(width: MiniGameCanvas.logicalWidth, height: MiniGameCanvas.logicalHeight)

    // 논리 좌표 상수
    private static let trackLeft: CGFloat = 24
    private static let trackWidth: CGFloat = 244
    private static let trackY: CGFloat = 100
    private static let trackHeight: CGFloat = 14
    private static let markerWidth: CGFloat = 4
    private static let markerHeight: CGFloat = 26
    private static let dotsY: CGFloat = 130

    var body: some View {
        ZStack {
            Canvas { context, size in
                let (scale, origin) = MiniGameCanvas.transform(in: size)
                func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }
                func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                    CGRect(origin: pt(x, y), size: CGSize(width: w * scale, height: h * scale))
                }

                // 바닥: 실제 크기 전체를 채운다(여백까지 같은 색이어야 축소된 캔버스가 액자처럼 보이지 않는다).
                let floor = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10)
                context.fill(floor, with: .color(CheckTheme.fieldFill))
                context.stroke(floor, with: .color(CheckTheme.border), lineWidth: 1)

                // 트랙 — 시작 전(.ready)엔 그리지 않는다: 안내 카드가 가운데를 덮어 양끝만 괄호처럼 삐져나온다(통합 렌더에서 확인).
                if case .ready = game.phase {} else {
                    let trackRect = rect(Self.trackLeft, Self.trackY - Self.trackHeight / 2, Self.trackWidth, Self.trackHeight)
                    let track = Path(roundedRect: trackRect, cornerRadius: Self.trackHeight / 2 * scale)
                    context.fill(track, with: .color(CheckTheme.trackFill))
                    context.stroke(track, with: .color(CheckTheme.border), lineWidth: 1)
                }

                // 목표 구간 · 마커 — 진행 중/결과 표시 중에만.
                if game.isPlaying {
                    let (center, width) = game.target
                    let targetRect = rect(Self.trackLeft + CGFloat(center - width / 2) * Self.trackWidth,
                                          Self.trackY - Self.trackHeight / 2,
                                          CGFloat(width) * Self.trackWidth, Self.trackHeight)
                    let target = Path(roundedRect: targetRect, cornerRadius: 4 * scale)
                    context.fill(target, with: .color(CheckTheme.accent.opacity(0.35)))
                    context.stroke(target, with: .color(CheckTheme.accent), lineWidth: 1)

                    let markerX = Self.trackLeft + CGFloat(game.markerPosition) * Self.trackWidth
                    let markerRect = rect(markerX - Self.markerWidth / 2, Self.trackY - Self.markerHeight / 2,
                                          Self.markerWidth, Self.markerHeight)
                    let markerColor: Color = {
                        if case .roundResult = game.phase, game.lastHit == false { return CheckTheme.danger }
                        return CheckTheme.working
                    }()
                    context.fill(Path(roundedRect: markerRect, cornerRadius: 2 * scale), with: .color(markerColor))
                }

                // 라운드 점 10개: 미진행 border · 60+ working · 1~59 accent · 0 danger.
                let pitch = Self.trackWidth / CGFloat(TimingBarGame.roundCount)
                for index in 0..<TimingBarGame.roundCount {
                    let x = Self.trackLeft + (CGFloat(index) + 0.5) * pitch
                    let dot = Path(ellipseIn: rect(x - 3, Self.dotsY - 3, 6, 6))
                    let color: Color = {
                        guard index < game.roundScores.count else { return CheckTheme.border }
                        let score = game.roundScores[index]
                        if score >= 60 { return CheckTheme.working }
                        if score >= 1 { return CheckTheme.accent }
                        return CheckTheme.danger
                    }()
                    context.fill(dot, with: .color(color))
                }
            }

            // 글자·카드는 SwiftUI 뷰로 얹는다(위치만 논리 좌표를 따른다 — 글꼴 크기는 가독성을 위해 그대로).
            TimingBarOverlay(game: game, bestScore: bestScore, reduceMotion: reduceMotion, container: container)
        }
        // 실제 크기는 여기서 한 번 읽어 둔다(GeometryReader 없이). 첫 렌더 전엔 논리 크기로 가정한다.
        .onGeometryChange(for: CGSize.self) { proxy in proxy.size } action: { container = $0 }
    }
}

/// 캔버스 위 글자와 오버레이 카드. 부모 프레임을 그대로 채우고 안에서 정렬한다.
private struct TimingBarOverlay: View {
    let game: TimingBarGame
    let bestScore: Int
    let reduceMotion: Bool
    let container: CGSize

    var body: some View {
        ZStack {
            // 상단 좌: 라운드 · 상단 우: 총점
            VStack {
                HStack(alignment: .firstTextBaseline) {
                    Text("라운드 \(max(1, game.round))/\(TimingBarGame.roundCount)")
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                    Spacer()
                    Text("\(game.total)")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(CheckTheme.primaryText)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                Spacer()
            }

            // 결과 "+N": 마커 위. 위치는 논리 좌표를 실제 크기로 옮겨 잡는다.
            if case .roundResult(let round, let score, _) = game.phase {
                TimingBarRoundPop(score: score, hit: game.lastHit ?? false, reduceMotion: reduceMotion,
                                  markerPosition: game.markerPosition, container: container)
                    .id(round)
            }

            switch game.phase {
            case .ready:
                TimingBarCard {
                    Text(MiniGameKind.timingBar.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(CheckTheme.primaryText)
                    Text(MiniGameKind.timingBar.howToPlay)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .multilineTextAlignment(.center)
                    Text("클릭해서 시작")
                        .font(.caption)
                        .foregroundStyle(CheckTheme.accent)
                }
            case .finished(let total):
                TimingBarCard {
                    Text("총점 \(total)")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(CheckTheme.primaryText)
                    if total > bestScore {
                        Text("신기록!")
                            .font(.caption.bold())
                            .foregroundStyle(CheckTheme.working)
                    } else {
                        Text("최고 \(bestScore)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(CheckTheme.secondaryText)
                    }
                    Text("클릭해서 다시")
                        .font(.caption)
                        .foregroundStyle(CheckTheme.accent)
                }
            case .running, .roundResult:
                EmptyView()
            }
        }
    }
}

/// 마커 위에 뜨는 "+N". 동작 줄이기가 아니면 작은 스프링 팝. 위치는 논리 좌표(마커 x, y 72)를 실제 크기로 옮긴다.
private struct TimingBarRoundPop: View {
    let score: Int
    let hit: Bool
    let reduceMotion: Bool
    let markerPosition: Double
    let container: CGSize

    @State private var scale: CGFloat = 0.6

    var body: some View {
        let (unit, origin) = MiniGameCanvas.transform(in: container)
        let x = origin.x + (24 + CGFloat(markerPosition) * 244) * unit
        let y = origin.y + 72 * unit
        Text("+\(score)")
            .font(.subheadline.bold())
            .monospacedDigit()
            .foregroundStyle(hit ? CheckTheme.working : CheckTheme.danger)
            .scaleEffect(reduceMotion ? 1 : scale)
            .position(x: x, y: y)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(duration: 0.28, bounce: 0.35)) { scale = 1 }
            }
    }
}

/// 캔버스 위 오버레이 카드(시작 안내 · 결과). 말풍선과 같은 panelElevated 바탕 + border.
private struct TimingBarCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 4) { content() }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 236)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CheckTheme.panelElevated)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
            )
    }
}
