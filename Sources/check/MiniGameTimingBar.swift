import SwiftUI

// MARK: - 타이밍 바 (v0.2.46 규칙 · v0.2.48 시각 개편)
//
// 왕복하는 마커를 목표 구간 안에서 멈추는 10라운드 게임. 규칙(`TimingBarGame`)은 뷰를 전혀 모르는 값 타입이고,
// 시간은 `step(dt:)` 로만 흐르며 난수는 시드로 주입한 `MiniGameRandom` 만 쓴다 — 같은 시드·같은 입력이면 같은 판이라
// 테스트가 "목표 중심에 마커가 오는 시각"을 역산해 100점을 재현한다. 뷰(`TimingBarGameView`)는 상태를 `@State` 로 들고
// `TimelineView(.animation)` 으로 전진시킬 뿐, 입력은 허브가 `MiniGameInput.actionCount` 로 넘긴다(제스처 없음).
//
// ── 논리 좌표 292×302 (2026-09-10) ────────────────────────────────────────────────────────
// 창 캔버스(344×356)와 **같은 비율**이다(292 × 356/344 = 302.19 → 302). 종전 292×200 은 344×356 안에서
// 위아래 60pt 씩 죽은 여백을 만들었다 — 플래피가 먼저 겪고 고친 함정이고, 여기서도 판이 그만큼 비어 보였다.
//
// ⚠️ **판을 키워도 난이도는 1도 안 변한다.** 이 게임의 규칙은 전부 정규화 좌표(0…1)로 계산한다:
// 목표 중심 `targetCenter` · 폭 `targetWidthValue` · 마커 위치 `markerPosition` · 거리 `d = |p−c|/(w/2)` 가
// 모두 "트랙 길이 = 1" 기준이라 트랙을 몇 pt 로 그리든 `roundScore(distance:)` 의 입력이 같다.
// 중력·점프 높이를 가진 플래피와 달리 여기엔 판 크기에 맞춰 다시 맞출 물리 상수가 없다.
// 반대로 `period(round:)` · `targetWidth(round:)` · `roundScore(distance:)` · `roundCount` 는 순위표가 걸린
// 난이도 그 자체다 — 그림 작업에서 저 넷을 만지면 그 순간 기존 기록의 의미가 깨진다.
//
// ── 이 개편이 화면에 더한 것 (사용자 지적 2026-09-10: "게임하는 맛이 없다") ──────────────────
//   · 무대: 2라운드마다 `MiniGameStage` 한 단계(새벽 → 한낮 → 노을 → 밤 → 오로라). **능선은 끈다**
//     (`terrain: false`) — 가로 스크롤이 없는 정적인 게임이라 지형이 깔리면 화면이 더 멎어 보인다.
//     대신 트랙 뒤에 무대 glow 후광을 깔아 "여기가 무대다"를 만든다.
//   · 목표 구간을 3중으로 그린다. 바깥/안쪽/정중앙이 각각 70~89 · 90+ · 100 점 구간이다 —
//     배점 함수를 그림으로 옮긴 것이지 새 규칙이 아니다(그래서 배점을 고치면 이 그림도 같이 틀린다).
//   · 판정 순간: 등급(`TimingBarGame.Verdict`) → 링 2개 · 파편 · 점수 팝 · 화면 흔들림. "몇 점인지"가
//     숫자로만 오던 것이 이 개편의 발단이다.
//   · 이펙트 시계는 **상태를 늘리지 않는다** — `roundResult(hold:)` 를 뒤집어 "정지 뒤 흐른 시간"을 얻고,
//     무대 전환 섬광은 `running(t:)` 를 그대로 쓴다. @State 시계를 따로 두면 규칙과 그림이 갈라져
//     같은 판을 다시 그릴 수 없게 된다(테스트가 initialGame 하나로 프레임을 재현하는 근거가 사라진다).

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

    /// 정지 순간의 판정 등급. **점수에서만 나오는 순수 함수**다 — 그림이 자기 기준으로 등급을 다시 세면
    /// 배점이 바뀔 때 표시와 점수가 조용히 갈린다. 색과 함께 라벨을 들고 다니는 이유는 접근성이다:
    /// 색만으로 결과를 알리지 않는다(색각 이상에서도 "완벽!"이 글자로 온다).
    enum Verdict: Equatable, Sendable {
        case perfect, great, good, close, miss

        var label: String {
            switch self {
            case .perfect: "완벽!"
            case .great: "훌륭!"
            case .good: "좋아"
            case .close: "아슬"
            case .miss: "빗나감"
            }
        }

        /// 등급 색. **무대를 타지 않는다** — 무대는 2라운드마다 바뀌는데 판정 색까지 따라 바뀌면
        /// "이 색이 몇 점인지"를 라운드마다 새로 배워야 한다. 100점만 테마에 없는 금색을 쓴다
        /// (working 초록을 90점대와 나눠 쓰면 완벽과 훌륭이 한눈에 구별되지 않는다).
        var tint: Color {
            switch self {
            case .perfect: Self.perfectGold
            case .great: CheckTheme.working
            case .good: CheckTheme.accent
            case .close: CheckTheme.pending
            case .miss: CheckTheme.danger
            }
        }

        /// 등급 글리프(라운드 스트립 칸 안). **색만으로는 말하지 않는다** — 칸이 22pt 라 숫자는 못 넣지만
        /// 채운 정도(꽉 참 → 테두리만 → ×)는 색을 못 보는 눈에도 순서로 읽힌다(2026-09-10 지적).
        var glyph: TimingBarSegmentGlyph {
            switch self {
            case .perfect: .star
            case .great: .disc
            case .good: .diamond
            case .close: .ring
            case .miss: .cross
            }
        }

        /// 무대 glow 5종의 공통분모에 가까운 금색(새벽·노을 glow 계열).
        private static let perfectGold = Color(red: 1.00, green: 0.84, blue: 0.52)
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

    /// 연속으로 목표 구간에 넣은 횟수. 배점상 구간 안이면 70~100, 밖이면 0 뿐이라 "70점 이상"이 곧 "명중"이다.
    /// **표시 전용이다.** 총점(`total`)에 절대 더하지 마라 — 서버 상한 1000점(= 100 × 10라운드)을 넘겨
    /// 업로드가 거부되고, 콤보 보너스가 붙은 기록과 안 붙은 기록이 한 순위표에 섞여 의미가 깨진다.
    var combo: Int {
        var streak = 0
        for score in roundScores.reversed() {
            guard score >= 70 else { break }
            streak += 1
        }
        return streak
    }

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

    /// 라운드 주기(초). 갈수록 빨라지되 0.42 밑으로는 안 내려간다.
    /// r1 1.10 · r5 0.80 · r10 0.425. 2026-09-08 실기에서 "너무 쉽다"는 지적을 받아 1.40/0.09 에서 올렸다.
    static func period(round: Int) -> Double {
        max(0.42, 1.10 - 0.075 * Double(round - 1))
    }

    /// 목표 구간 폭(트랙 길이 = 1). 갈수록 좁아지되 0.07 밑으로는 안 내려간다.
    /// r1 0.24 · r5 0.164 · r10 0.07(하한). 종전 0.30/0.022 보다 처음부터 좁고 끝은 더 좁다.
    static func targetWidth(round: Int) -> Double {
        max(0.07, 0.24 - 0.019 * Double(round - 1))
    }

    /// 삼각파 0→1→0. t=0 에서 0, t=T/2 에서 1, t=T 에서 다시 0.
    /// 해석식이라 **과거·미래 시각도 그냥 계산된다** — 마커 잔상(t − k/60)이 이 성질에 기대고 있다.
    static func markerPosition(t: Double, period: Double) -> Double {
        let x = t / period
        return 2 * abs(x - (x + 0.5).rounded(.down))
    }

    /// 목표 중심에서의 거리 d(= |p − c| / (w/2)) 를 점수로.
    /// 라운드 점수(사용자 결정 2026-09-08): 목표 구간 **안**이면 정중앙 100 → 가장자리 70 (정확도 비례), **밖이면 0**.
    /// 구간 밖 부분 점수는 없다 — "들어왔느냐"가 먼저고, 그 다음이 정확도다.
    static func roundScore(distance d: Double) -> Int {
        guard d <= 1 else { return 0 }
        return 100 - Int((30 * d).rounded())
    }

    /// 점수 → 판정 등급. 경계는 100 / 90 / 80 / 70 이고 그 밑은 전부 빗나감(배점상 0 뿐이다).
    static func verdict(score: Int) -> Verdict {
        if score >= 100 { return .perfect }
        if score >= 90 { return .great }
        if score >= 80 { return .good }
        if score >= 70 { return .close }
        return .miss
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
/// 허브가 주는 것: `host`(최고기록·동작 줄이기·중단 토큰·**일시정지**·콜백) 와 `input`(클릭/스페이스 카운터).
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
        // 일시정지 계약(v0.2.48): 정지 중엔 프레임이 아예 돌지 않는다. 정지 화면(스크림·카운트다운)은 허브가 그린다 —
        // 게임 쪽에도 그리면 두 벌이 되어 언젠가 갈린다.
        // 프레임 상한은 **화면 주사율에서 온다**(v0.2.50). 여기 숫자를 적지 마라 — 1/60 을 박아 두면
        // 75Hz·144Hz 처럼 60 으로 나눠떨어지지 않는 화면에서 네 프레임에 한 장이 두 배로 늘어진다
        // (근거·표는 `MiniGameFrameRate`). 값이 바뀌면 이 뷰가 다시 만들어지며 스케줄도 다시 잡힌다.
        TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval(forRefreshRate: host.refreshHz),
                                paused: !game.isPlaying || host.isPaused)) { context in
            TimingBarFrame(game: game, bestScore: host.bestScore, reduceMotion: host.reduceMotion)
                // 상태 변경은 본문 평가 중이 아니라 프레임 시각이 **바뀐 뒤**(onChange)에 한다.
                .onChange(of: context.date) { _, now in tick(now) }
        }
        .onChange(of: input.actionCount) { _, count in handleAction(count) }
        .onChange(of: host.interruptToken) { _, _ in interrupt() }
    }

    // MARK: 전이

    private func tick(_ now: Date) {
        // 정지 중엔 시간을 흘리지 않는다. lastTick 도 비워 재개 첫 프레임이 정지 구간을 한꺼번에 물려받지 않게 한다.
        // 프로브는 가드 **앞**이다 — 재는 것이 "틱이 일을 했는가"가 아니라 "프레임 루프가 돌았는가"이기
        // 때문이다. 뒤에 두면 TimelineView 를 안 멈춰도 프레임 수가 0 으로 나와 유휴 0% 가 거짓말이 된다.
        MiniGameFrameProbe.note()
        guard game.isPlaying, !host.isPaused else { lastTick = nil; return }
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
        // 정지 중 스페이스·클릭은 판을 건드리지 않는다 — 재개는 허브가 쥐고 있다(정지 화면 뒤에서 라운드가 끝나면 안 된다).
        guard !host.isPaused else { return }
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

// MARK: - 그림 상수(논리 좌표 292×302)

/// 배치는 전부 여기 한곳에서 정한다. 값 자체는 그림의 것이고 규칙과 공유하지 않는다 —
/// 규칙이 이 숫자를 읽기 시작하면 "판을 키웠더니 난이도가 변했다"가 다시 가능해진다.
private enum TimingBarLayout {
    static let width = MiniGameCanvas.logicalWidth
    /// 창 캔버스(344×356)와 같은 비율. 유도식은 `MiniGameCanvas.logicalHeight` 한 곳에만 둔다
    /// (플래피도 같은 값을 쓴다 — 두 벌로 적으면 언젠가 갈린다).
    static let height: CGFloat = MiniGameCanvas.logicalHeight
    static var logicalSize: CGSize { CGSize(width: width, height: height) }

    static let headerY: CGFloat = 22
    static let comboY: CGFloat = 56
    static let trackLeft: CGFloat = 24
    static let trackWidth: CGFloat = 244
    static let trackY: CGFloat = 150
    static let trackHeight: CGFloat = 18
    static let markerWidth: CGFloat = 4
    static let markerHeight: CGFloat = 30
    /// 블레이드 위아래로 삐져나온 삼각 촉의 높이.
    static let markerTip: CGFloat = 6
    static let segmentsY: CGFloat = 250
    static let segmentHeight: CGFloat = 10
    /// 점수 팝이 뜨는 높이(마커 촉 위).
    static let popY: CGFloat = 106

    /// 목표 구간 **안쪽 띠**의 폭 비율(90점 이상 구간). 스펙 초안은 40% 였지만 90점 경계는 배점상 정확히
    /// d < 0.35 다(100 − round(30d) ≥ 90 ⇔ 30d < 10.5 ⇔ d < 0.35). 그림이 배점보다 넓으면
    /// "안쪽 띠에 넣었는데 89점"이 생겨 이 3중 띠의 존재 이유가 사라진다.
    static let innerTargetRatio: CGFloat = 0.35
    /// 정중앙 100점 선의 폭. 실제 100점 구간(d < 1/60)은 r1 에서 ≈1.0pt 라, 눈에 보이는 최소한을 잡는다.
    /// 1.5 는 1:1 배율에서 밝은 안쪽 블록 위에 얹히면 사라져 2 로 올렸다(2026-09-10 지적).
    static let perfectLineWidth: CGFloat = 2
    /// 정중앙 선이 트랙 위아래로 삐져나오는 길이. 마커가 선을 덮어도 이 두 촉이 남는다.
    static let perfectOverhang: CGFloat = 4
    /// 목표 구간 두 층의 불투명도. **대비로 정한 값이다**(2026-09-10 실측):
    /// 바깥 띠는 어두운 트랙 대비 3:1 이상, 안쪽 블록은 바깥 띠 대비 3:1 이상.
    /// 조준해야 하는 UI 요소가 3:1 미만이면 "3중 구조"는 이름만 남는다.
    /// 새벽이 가장 좁다: 트랙 → structureEdge 의 전체 대비가 8.9:1 이라 3:1 두 단이 딱 들어간다.
    /// 그래서 바깥 띠는 두 끝의 **기하평균** 자리에 둔다(양쪽 2.9~3.4:1).
    static let outerTargetOpacity: Double = 0.78
    static let innerTargetOpacity: Double = 1.0

    static let ringDuration: Double = 0.4
    static let flashDuration: Double = 0.15
    static let shakeDuration: Double = 0.12
    /// 무대가 바뀐 직후 번지는 섬광.
    static let stageFlareDuration: Double = 0.6
}

/// 이 게임의 투영. 좌표 변환은 공용 `MiniGameProjection` 이 하고, 여기서는 트랙 전용 편의만 얹는다.
private extension MiniGameProjection {
    /// 트랙 위 정규화 위치(0…1) → 실제 x.
    func trackX(_ position: Double) -> CGFloat {
        x(TimingBarLayout.trackLeft + CGFloat(position) * TimingBarLayout.trackWidth)
    }
}

// MARK: - 그림

/// 한 프레임의 그림. 배경·트랙·마커·이펙트는 Canvas 한 장에, 글자와 카드는 그 위 SwiftUI 층에 그린다.
private struct TimingBarFrame: View {
    let game: TimingBarGame
    let bestScore: Int
    let reduceMotion: Bool

    @State private var container = TimingBarLayout.logicalSize

    var body: some View {
        let stage = MiniGameStage.forTimingRound(game.round)
        ZStack {
            Canvas(rendersAsynchronously: false) { context, size in
                draw(&context, size: size, stage: stage)
            }
            TimingBarOverlay(game: game, stage: stage, bestScore: bestScore,
                             reduceMotion: reduceMotion, container: container)
        }
        // 화면 흔들림은 **캔버스 통째로** 민다. 배경을 8pt 부풀려 그리므로 밀어도 가장자리가 비지 않는다.
        .offset(shakeOffset)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CheckTheme.fieldFill))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        // 테두리는 흔들리는 층 **밖**에 둔다(같이 흔들리면 액자가 떨린다).
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
        // 실제 크기는 여기서 한 번 읽어 둔다(GeometryReader 없이). 첫 렌더 전엔 논리 크기로 가정한다.
        .onGeometryChange(for: CGSize.self) { proxy in proxy.size } action: { container = $0 }
    }

    // MARK: 이펙트 시계 — 전부 phase 에서 파생한다(새 상태 없음)

    /// 정지(tap) 뒤 흐른 초. `roundResult(hold:)` 가 resultHold 에서 줄어드는 것을 뒤집었다.
    private var sinceTap: Double? {
        guard case .roundResult(_, _, let hold) = game.phase else { return nil }
        return TimingBarGame.resultHold - hold
    }

    /// 무대가 막 바뀐 직후인가. 무대는 2라운드마다(3·5·7·9 라운드 시작) 갈리므로 홀수 라운드의 t 만 보면 된다.
    private var stageFlareProgress: Double? {
        guard case .running(let round, let t) = game.phase,
              round >= 3, round % 2 == 1, t < TimingBarLayout.stageFlareDuration else { return nil }
        return t / TimingBarLayout.stageFlareDuration
    }

    /// 세그먼트 맥동 위상(0…1). 진행 중일 때만 흔들린다.
    private var pulse: Double {
        guard !reduceMotion, case .running(_, let t) = game.phase else { return 1 }
        return 0.5 + 0.5 * sin(t * 5.5)
    }

    /// 판정 순간의 화면 흔들림. 명중 2pt · 빗나감 4pt, 0.12초 감쇠. 동작 줄이기면 없다.
    private var shakeOffset: CGSize {
        guard !reduceMotion, let elapsed = sinceTap, elapsed < TimingBarLayout.shakeDuration,
              let hit = game.lastHit else { return .zero }
        let decay = 1 - elapsed / TimingBarLayout.shakeDuration
        let amplitude = (hit ? 2.0 : 4.0) * decay
        return CGSize(width: amplitude * sin(elapsed * 160), height: amplitude * 0.6 * cos(elapsed * 130))
    }

    /// 이번 라운드의 판정(결과 표시 중에만).
    private var verdict: TimingBarGame.Verdict? {
        guard case .roundResult(_, let score, _) = game.phase else { return nil }
        return TimingBarGame.verdict(score: score)
    }

    /// 세그먼트 바는 카드가 떠 있는 동안 숨긴다 — 트랙 폭(244)이 카드 폭(240)보다 넓어 양 끝 칸만 삐져나온다.
    private var showsSegments: Bool { game.isPlaying }

    // MARK: Canvas

    private func draw(_ context: inout GraphicsContext, size: CGSize, stage: MiniGameStage) {
        let projection = MiniGameProjection(container: size, logicalSize: TimingBarLayout.logicalSize)
        let full = CGRect(origin: .zero, size: size)

        // 1) 배경: 하늘·별·지평선 광원만(`terrain: false`). 8pt 부풀려 흔들림에도 가장자리가 안 뚫린다.
        //    scroll 0 — 가로로 흐르는 것이 없는 게임이라 별도 정지해 있다(프레임마다 난수를 뽑지 않는다).
        MiniGameBackdrop.draw(into: &context, rect: full.insetBy(dx: -8, dy: -8), stage: stage,
                              scroll: 0, terrain: false, reduceMotion: reduceMotion)

        // 2) 무대 전환 섬광.
        if let progress = stageFlareProgress {
            MiniGameEffects.flare(into: &context, rect: full, progress: progress, color: stage.glow)
        }

        drawTrackGlow(&context, projection: projection, stage: stage)
        drawTrack(&context, projection: projection, stage: stage)
        if game.isPlaying {
            drawTarget(&context, projection: projection, stage: stage)
            drawMarker(&context, projection: projection)
            drawHitEffects(&context, projection: projection, full: full, stage: stage)
        }
        if showsSegments {
            drawSegments(&context, projection: projection, stage: stage)
        }

        // 빗나감 붉은 플래시(0.15초) — 마지막에 덮어야 판 전체가 물든다.
        if let elapsed = sinceTap, verdict == .miss, elapsed < TimingBarLayout.flashDuration {
            let strength = 1 - elapsed / TimingBarLayout.flashDuration
            context.fill(Path(full), with: .color(CheckTheme.danger.opacity(0.24 * strength)))
        }
    }

    /// 트랙 뒤 무대 후광. 가로로 긴 타원에 radialGradient 를 채운다(blur 금지 — 60Hz 예산).
    private func drawTrackGlow(_ context: inout GraphicsContext, projection: MiniGameProjection, stage: MiniGameStage) {
        let glow = projection.rect(TimingBarLayout.trackLeft - 46, TimingBarLayout.trackY - 52,
                                   TimingBarLayout.trackWidth + 92, 104)
        MiniGameEffects.glow(into: &context, in: glow, color: stage.glow, opacity: 0.22)
    }

    /// 트랙 본체(안쪽 그림자 느낌의 어두운 캡슐) + 양 끝 눈금 3개씩.
    private func drawTrack(_ context: inout GraphicsContext, projection: MiniGameProjection, stage: MiniGameStage) {
        let body = projection.rect(TimingBarLayout.trackLeft, TimingBarLayout.trackY - TimingBarLayout.trackHeight / 2,
                                   TimingBarLayout.trackWidth, TimingBarLayout.trackHeight)
        let capsule = Path(roundedRect: body, cornerRadius: body.height / 2)
        // 트랙 바닥은 **깊게** 판다. 노을처럼 하늘이 밝은 무대에서 0.58/0.26 은 트랙 자체가 떠 버려
        // 목표 구간 바깥 띠와의 대비가 1.60:1 밖에 안 나왔다(2026-09-10 실측). 조준해야 하는 UI 다.
        context.fill(capsule, with: .linearGradient(
            Gradient(colors: [.black.opacity(0.86), .black.opacity(0.66)]),
            startPoint: CGPoint(x: body.midX, y: body.minY),
            endPoint: CGPoint(x: body.midX, y: body.maxY)
        ))
        context.stroke(capsule, with: .color(stage.structureEdge.opacity(0.35)), lineWidth: 1)

        // 눈금: 트랙 밖으로 3개씩. 자를 옆에 세워 둔 것처럼 바깥으로 갈수록 짧고 흐리다.
        for step in 0..<3 {
            let inset = 6 + CGFloat(step) * 5
            let tickHeight = 8 - CGFloat(step) * 2
            let opacity = 0.5 - Double(step) * 0.14
            for side in [-1.0, 1.0] as [CGFloat] {
                let center = side < 0
                    ? TimingBarLayout.trackLeft - inset
                    : TimingBarLayout.trackLeft + TimingBarLayout.trackWidth + inset
                let tick = projection.rect(center - 0.75, TimingBarLayout.trackY - tickHeight / 2, 1.5, tickHeight)
                context.fill(Path(tick), with: .color(stage.structureEdge.opacity(opacity)))
            }
        }
    }

    /// 목표 구간 3중. 바깥(70~89) · 안쪽(90+) · 정중앙 선(100) — `roundScore(distance:)` 의 100 − round(30d) 를
    /// 그림으로 옮긴 것이다. 배점을 고치면 여기 비율도 같이 틀린다(고칠 때 이 주석을 보라).
    private func drawTarget(_ context: inout GraphicsContext, projection: MiniGameProjection, stage: MiniGameStage) {
        let (center, width) = game.target
        let height = TimingBarLayout.trackHeight
        let top = TimingBarLayout.trackY - height / 2

        let outerWidth = CGFloat(width) * TimingBarLayout.trackWidth
        let outerLeft = TimingBarLayout.trackLeft + CGFloat(center - width / 2) * TimingBarLayout.trackWidth
        // 바깥 띠(70~89점) — 트랙 대비 3:1 이상. 0.30 은 1.60:1 이라 트랙과 구분되지 않았다.
        let outer = projection.rect(outerLeft, top, outerWidth, height)
        context.fill(Path(roundedRect: outer, cornerRadius: 3 * projection.scale),
                     with: .color(stage.structure.opacity(TimingBarLayout.outerTargetOpacity)))

        // 안쪽 블록(90점+) — 바깥 띠 대비 3:1 이상. 같은 색의 불투명도만 올려서는 그 차이가 안 난다
        // (0.30 → 0.55 가 1.46:1 이었다). **밝은 쪽 색**(structureEdge)으로 갈아 대역을 통째로 옮긴다.
        let innerWidth = outerWidth * TimingBarLayout.innerTargetRatio
        let inner = projection.rect(outerLeft + (outerWidth - innerWidth) / 2, top + 2, innerWidth, height - 4)
        let innerPath = Path(roundedRect: inner, cornerRadius: 2 * projection.scale)
        context.fill(innerPath, with: .color(stage.structureEdge.opacity(TimingBarLayout.innerTargetOpacity)))
        // 두 층 사이의 **어두운 경계선**. 무대 팔레트가 좁은 곳(노을 2.4:1)에서는 밝기만으로 층이 갈리지
        // 않는다 — 형태(선)를 한 겹 더 두면 팔레트와 무관하게 3중 구조가 눈으로 읽힌다.
        context.stroke(innerPath, with: .color(.black.opacity(0.50)), lineWidth: 1)

        // 100점 선은 트랙 위아래로 튀어나온다 — 마커가 겹쳐도 "정중앙이 여기"가 남아야 한다.
        // 안쪽 블록이 밝아졌으므로 선 밑에 **어두운 홈**을 먼저 파 둔다: 그래야 밝은 띠 위에서도 선이 남는다.
        let lineX = TimingBarLayout.trackLeft + CGFloat(center) * TimingBarLayout.trackWidth
        let slotWidth = TimingBarLayout.perfectLineWidth + 2
        let slot = projection.rect(lineX - slotWidth / 2, top - TimingBarLayout.perfectOverhang,
                                   slotWidth, height + TimingBarLayout.perfectOverhang * 2)
        context.fill(Path(slot), with: .color(.black.opacity(0.55)))
        let line = projection.rect(lineX - TimingBarLayout.perfectLineWidth / 2,
                                   top - TimingBarLayout.perfectOverhang,
                                   TimingBarLayout.perfectLineWidth, height + TimingBarLayout.perfectOverhang * 2)
        context.fill(Path(line), with: .color(stage.glow))
    }

    /// 마커: 잔상 → 광원 → 블레이드 → 삼각 촉 순.
    private func drawMarker(_ context: inout GraphicsContext, projection: MiniGameProjection) {
        // 진행 중엔 흰 블레이드(무대 5종 어디서도 목표 띠 색과 안 겹친다), 판정 뒤엔 등급 색.
        let color = verdict?.tint ?? CheckTheme.primaryText

        // 잔상: 삼각파가 해석식이라 과거 위치를 그냥 계산할 수 있다(t − 나이). 지난 프레임을 보관할 필요가 없다.
        // 나이는 **시간**이다(33·67·100ms) — 프레임 수로 세면 꼬리 길이가 화면 주사율마다 달라진다
        // (75Hz 의 2프레임은 27ms, 60Hz 는 33ms). v0.2.50 에 프레임 간격이 화면을 따라가면서 갈린 자리라
        // 여기서 시간으로 못 박는다: 어느 화면에서도 꼬리가 같은 길이로 보인다(픽셀은 60Hz 때와 같다).
        if !reduceMotion, case .running(let round, let t) = game.phase {
            let period = TimingBarGame.period(round: round)
            for (age, opacity) in [(2.0 / 60.0, 0.28), (4.0 / 60.0, 0.16), (6.0 / 60.0, 0.08)] {
                let past = TimingBarGame.markerPosition(t: t - age, period: period)
                // 촉 없이, 블레이드보다 짧게 — 잔상이 본체와 같은 모양이면 마커가 여러 개로 보인다.
                let ghost = bladeRect(at: past, projection: projection).insetBy(dx: 0, dy: 4 * projection.scale)
                context.fill(Path(roundedRect: ghost, cornerRadius: 1.5 * projection.scale),
                             with: .color(color.opacity(opacity)))
            }
        }

        let markerX = projection.trackX(game.markerPosition)
        let centerY = projection.y(TimingBarLayout.trackY)

        // 광원 — 마커가 트랙 위에서 스스로 빛나 보이게(그라디언트로만, blur 금지).
        let halo = 26 * projection.scale
        MiniGameEffects.glow(
            into: &context,
            in: CGRect(x: markerX - halo, y: centerY - halo, width: halo * 2, height: halo * 2),
            color: color, opacity: 0.38
        )

        let blade = bladeRect(at: game.markerPosition, projection: projection)
        context.fill(Path(roundedRect: blade, cornerRadius: 1.5 * projection.scale), with: .color(color))

        // 위아래 삼각 촉 — 블레이드 **쪽으로** 뾰족하다(밖으로 향하면 위아래 화살표 ↕ 가 되어 창 크기 조절
        // 손잡이처럼 읽힌다 — 첫 스냅샷에서 실제로 그렇게 보였다, 2026-09-10).
        // 색만으로 알리지 않는 장치이기도 하다: 두 촉이 가리키는 한 점이 곧 정지할 자리다.
        let half = 5 * projection.scale
        let tip = TimingBarLayout.markerTip * projection.scale
        var top = Path()
        top.move(to: CGPoint(x: markerX, y: blade.minY + 1))
        top.addLine(to: CGPoint(x: markerX - half, y: blade.minY - tip))
        top.addLine(to: CGPoint(x: markerX + half, y: blade.minY - tip))
        top.closeSubpath()
        var bottom = Path()
        bottom.move(to: CGPoint(x: markerX, y: blade.maxY - 1))
        bottom.addLine(to: CGPoint(x: markerX - half, y: blade.maxY + tip))
        bottom.addLine(to: CGPoint(x: markerX + half, y: blade.maxY + tip))
        bottom.closeSubpath()
        context.fill(top, with: .color(color))
        context.fill(bottom, with: .color(color))
    }

    private func bladeRect(at position: Double, projection: MiniGameProjection) -> CGRect {
        CGRect(
            x: projection.trackX(position) - TimingBarLayout.markerWidth / 2 * projection.scale,
            y: projection.y(TimingBarLayout.trackY - TimingBarLayout.markerHeight / 2),
            width: TimingBarLayout.markerWidth * projection.scale,
            height: TimingBarLayout.markerHeight * projection.scale
        )
    }

    /// 명중 순간의 링 2개 · 파편 · (완벽일 때만) 섬광.
    private func drawHitEffects(_ context: inout GraphicsContext, projection: MiniGameProjection,
                                full: CGRect, stage: MiniGameStage) {
        guard let elapsed = sinceTap, let verdict, verdict != .miss else { return }
        let progress = elapsed / TimingBarLayout.ringDuration
        guard progress < 1 else { return }
        let center = CGPoint(x: projection.trackX(game.markerPosition), y: projection.y(TimingBarLayout.trackY))
        MiniGameEffects.ring(into: &context, center: center, progress: progress,
                             maxRadius: 42 * projection.scale, color: verdict.tint, lineWidth: 2)
        MiniGameEffects.ring(into: &context, center: center, progress: min(1, progress * 1.5),
                             maxRadius: 24 * projection.scale, color: verdict.tint.opacity(0.85), lineWidth: 1.5)
        // 파편 방향은 라운드로 시드를 고정한다 — 같은 판을 다시 그리면 같은 그림이 나와야 한다.
        MiniGameEffects.sparks(into: &context, center: center, progress: progress, count: 8,
                               maxRadius: 34 * projection.scale, color: verdict.tint,
                               seed: UInt64(max(1, game.round)), dotRadius: 2.2 * projection.scale)
        if verdict == .perfect {
            MiniGameEffects.flare(into: &context, rect: full,
                                  progress: elapsed / TimingBarLayout.stageFlareDuration, color: stage.glow)
        }
    }

    /// 라운드 진행 세그먼트 10칸. 칸 색이 그 라운드의 등급이고, **그 안의 글리프가 같은 사실을 형태로**
    /// 한 번 더 말한다(색 단독 금지). 진행 중인 칸만 테두리가 강조되며 맥동한다.
    /// 칸 위에 숫자는 쓰지 않는다 — 10칸이 트랙 폭을 나눠 쓰므로(칸당 ≈22pt) 두 자리가 읽히지 않는다.
    private func drawSegments(_ context: inout GraphicsContext, projection: MiniGameProjection, stage: MiniGameStage) {
        let count = TimingBarGame.roundCount
        let gap: CGFloat = 3
        let cellWidth = (TimingBarLayout.trackWidth - gap * CGFloat(count - 1)) / CGFloat(count)
        let currentIndex: Int? = {
            if case .running(let round, _) = game.phase { return round - 1 }
            return nil
        }()
        for index in 0..<count {
            let left = TimingBarLayout.trackLeft + CGFloat(index) * (cellWidth + gap)
            let cell = projection.rect(left, TimingBarLayout.segmentsY - TimingBarLayout.segmentHeight / 2,
                                       cellWidth, TimingBarLayout.segmentHeight)
            let path = Path(roundedRect: cell, cornerRadius: 3 * projection.scale)
            if index < game.roundScores.count {
                let verdict = TimingBarGame.verdict(score: game.roundScores[index])
                context.fill(path, with: .color(verdict.tint.opacity(0.85)))
                context.stroke(path, with: .color(verdict.tint), lineWidth: 1)
                drawGlyph(&context, verdict.glyph, in: cell)
            } else if index == currentIndex {
                context.fill(path, with: .color(stage.glow.opacity(0.14 + 0.16 * pulse)))
                context.stroke(path, with: .color(stage.glow.opacity(0.55 + 0.45 * pulse)), lineWidth: 1.6)
            } else {
                context.stroke(path, with: .color(stage.structureEdge.opacity(0.28)), lineWidth: 1)
            }
        }
    }

    /// 칸 한가운데의 등급 글리프. 칸 색이 밝으므로(등급 tint 0.85) 글리프는 **검정**이다 —
    /// 금·초록 위 흰 글리프는 대비가 무너진다(순위 배지와 같은 규약).
    private func drawGlyph(_ context: inout GraphicsContext, _ glyph: TimingBarSegmentGlyph, in cell: CGRect) {
        let ink = GraphicsContext.Shading.color(.black.opacity(0.72))
        let r = min(cell.height, cell.width) * 0.28
        let c = CGPoint(x: cell.midX, y: cell.midY)
        let box = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        switch glyph {
        case .star, .disc:
            context.fill(Path(ellipseIn: box), with: ink)
            if glyph == .star {
                // 완벽만 한 겹 더 — 가운데를 뚫어 '고리 안의 점'으로 만든다(디스크와 형태가 갈린다).
                context.fill(Path(ellipseIn: box.insetBy(dx: r * 0.5, dy: r * 0.5)),
                             with: .color(.white.opacity(0.85)))
            }
        case .diamond:
            var path = Path()
            path.move(to: CGPoint(x: c.x, y: c.y - r))
            path.addLine(to: CGPoint(x: c.x + r, y: c.y))
            path.addLine(to: CGPoint(x: c.x, y: c.y + r))
            path.addLine(to: CGPoint(x: c.x - r, y: c.y))
            path.closeSubpath()
            context.fill(path, with: ink)
        case .ring:
            context.stroke(Path(ellipseIn: box), with: ink, lineWidth: max(1, r * 0.55))
        case .cross:
            var path = Path()
            path.move(to: CGPoint(x: c.x - r, y: c.y - r))
            path.addLine(to: CGPoint(x: c.x + r, y: c.y + r))
            path.move(to: CGPoint(x: c.x + r, y: c.y - r))
            path.addLine(to: CGPoint(x: c.x - r, y: c.y + r))
            context.stroke(path, with: ink, lineWidth: max(1, r * 0.55))
        }
    }
}

/// 라운드 스트립 칸 안에 그리는 등급 형태. 색을 못 보는 눈에도 등급이 남게 하는 두 번째 채널이다.
enum TimingBarSegmentGlyph {
    case star, disc, diamond, ring, cross
}

// MARK: - 캔버스 위 글자층

/// 헤더·콤보 칩·점수 팝·오버레이 카드. 위치만 논리 좌표를 따르고 글꼴 크기는 그대로 둔다(가독성).
private struct TimingBarOverlay: View {
    let game: TimingBarGame
    let stage: MiniGameStage
    let bestScore: Int
    let reduceMotion: Bool
    let container: CGSize

    var body: some View {
        let projection = MiniGameProjection(container: container, logicalSize: TimingBarLayout.logicalSize)
        ZStack {
            header(projection)
            if game.isPlaying, game.combo >= 2 { comboChip(projection) }
            if case .roundResult(let round, let score, _) = game.phase {
                scorePop(projection, round: round, score: score)
            }
            card
        }
        .allowsHitTesting(false)
    }

    /// 왼쪽 위: 라운드 + 무대 이름 칩 · 오른쪽 위: 총점.
    private func header(_ projection: MiniGameProjection) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text("라운드 \(max(1, game.round))/\(TimingBarGame.roundCount)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CheckTheme.primaryText.opacity(0.86))
            MiniGameStageChip(stage: stage)
            Spacer(minLength: 4)
            TimingBarTotal(total: game.total, reduceMotion: reduceMotion)
        }
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        .frame(width: (TimingBarLayout.width - 28) * projection.scale)
        .position(x: projection.x(TimingBarLayout.width / 2), y: projection.y(TimingBarLayout.headerY))
    }

    /// 콤보 칩 — 연속 명중 2 이상에서만. **표시 전용**이라 총점과는 아무 관계가 없다(TimingBarGame.combo 주석 참고).
    private func comboChip(_ projection: MiniGameProjection) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill").font(.system(size: 9, weight: .bold))
            Text("콤보 x\(game.combo)").font(.system(size: 11, weight: .heavy))
        }
        .foregroundStyle(stage.glow)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(stage.glow.opacity(0.18)))
        .overlay(Capsule().stroke(stage.glow.opacity(0.50), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        // 3 이상부터 살짝 커진다 — 숫자만 늘면 눈에 안 걸린다.
        .scaleEffect(game.combo >= 3 ? 1.14 : 1)
        .position(x: projection.x(TimingBarLayout.width / 2), y: projection.y(TimingBarLayout.comboY))
    }

    /// "+N · 등급" 팝. 마커 위에 뜨되 양 끝에서는 판 밖으로 나가지 않게 x 를 가둔다.
    private func scorePop(_ projection: MiniGameProjection, round: Int, score: Int) -> some View {
        let verdict = TimingBarGame.verdict(score: score)
        let clamped = min(max(game.markerPosition, 0.10), 0.90)
        return MiniGameScorePop(text: "+\(score)", caption: verdict.label,
                                tint: verdict.tint, reduceMotion: reduceMotion)
            .id(round)
            .position(x: projection.trackX(clamped), y: projection.y(TimingBarLayout.popY))
    }

    /// 시작·결과 카드. **아래쪽에 붙인다** — 카드가 ≈150pt 라 판(302) 한가운데 두면 트랙(y 150)을 덮는다.
    /// 종전에는 그래서 시작 화면에 트랙을 아예 안 그렸고, 양 끝만 괄호처럼 삐져나왔다.
    /// 트랙은 이 게임의 얼굴이라 시작 화면에서도 보여야 한다(2026-09-10 지적으로 우회 제거).
    @ViewBuilder
    private var card: some View {
        switch game.phase {
        case .ready:
            bottomAligned(
                MiniGameOverlayCard(
                    title: MiniGameKind.timingBar.title,
                    subtitle: MiniGameKind.timingBar.howToPlay,
                    action: "\(MiniGameKind.controlHint)로 시작",
                    icon: MiniGameKind.timingBar.icon,
                    tint: stage.glow
                )
            )
        case .finished(let total):
            bottomAligned(
                MiniGameOverlayCard(
                    title: "총점 \(total)",
                    titleIsScore: true,
                    subtitle: total > bestScore ? "신기록!" : "최고 \(bestScore)",
                    subtitleIsHighlighted: total > bestScore,
                    action: "\(MiniGameKind.controlHint)로 다시",
                    icon: MiniGameKind.timingBar.icon,
                    tint: stage.glow
                )
            )
        case .running, .roundResult:
            EmptyView()
        }
    }

    private func bottomAligned(_ content: some View) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content
        }
        .padding(.bottom, 10)
    }
}

/// 오른쪽 위 총점. 점수가 오르는 순간 한 번 튄다(동작 줄이기면 그대로).
private struct TimingBarTotal: View {
    let total: Int
    let reduceMotion: Bool

    @State private var scale: CGFloat = 1

    var body: some View {
        // String(total) — `Text("\(total)")` 는 로캘 자리수 구분을 붙여 만점에서 "1,000" 이 되고,
        // 결과 카드("총점 1000")·순위표와 표기가 갈린다.
        Text(String(total))
            .font(.system(size: 25, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(CheckTheme.primaryText)
            .scaleEffect(reduceMotion ? 1 : scale)
            .onChange(of: total) { _, _ in
                guard !reduceMotion else { return }
                scale = 1.3
                withAnimation(.spring(duration: 0.34, bounce: 0.45)) { scale = 1 }
            }
    }
}
