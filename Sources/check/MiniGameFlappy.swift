import AppKit
import SwiftUI

// MARK: - 플래피 아잉 (v0.2.46 규칙 · v0.2.48 그림)
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
//   그리고 15점부터 **틈이 한 번 확 튀는 기둥**이 확률로 섞인다(아래).
//
// ── 갑자기 튀는 틈(surprise jump) ────────────────────────────────────────────────────────
// 2026-09-08 실기 뒤 사용자 요청: "기둥 빈 위치가 갑자기 서프라이즈로 옮겨지게 · 차라리 속도 빨라지는 정도는 낮추고."
// 그래서 속도 상승률을 절반(6→3/점, 상한 300→230)으로 낮추고, 그 자리에 **틈이 한 번 확 튀는 기둥**을 넣었다.
//   · 언제부터: 점수 15 이상에서 **생성되는** 기둥부터(0~14 는 전부 고정 — 조작을 익힐 시간을 준다).
//   · 어느 기둥이: 점수와 무관하게 **30%**. 전부가 아니라 섞이기 때문에 "갑자기"가 성립한다.
//   · 어떻게: 기둥이 화면 오른쪽 끝에 들어온 뒤 `shiftDelay`(0.45~1.10초, 기둥마다 난수)가 지나면 틈 중심이
//     **한 번만** 위나 아래로 `shiftJump`(58pt) 튄다. 왕복하지 않는다 — 서프라이즈는 한 방이어야 무섭다.
//     0.12초 easeOut 보간이라 눈에는 순간이동처럼 보이지만 프레임 사이가 이어져 충돌이 어긋나지 않는다.
//   · 클램프: 튄 뒤 중심이 여백(`centerMargin` 36) 밖이면 반대 방향으로 튀고, 양쪽 다 불가능하면 고정 기둥이 된다.
//   · **색 신호는 없다**(사용자: "움직이는 기둥 뭔지 알려 주지 말자"). 고정 기둥과 픽셀 단위로 같게 그린다.
//   · 틈 폭 보정도 없다 — 고정 기둥과 같은 `gap(forScore:)` 을 쓴다.
//
// ── v0.2.48 그림 개편 ────────────────────────────────────────────────────────────────────
// 사용자 지적 2026-09-10: "캐릭터가 달려가는 쪽으로 좀 바라보고, 점프할 때는 점프하는 듯한 임팩트가 들어가고,
// 뒤에 배경도 단순히 검은색이 아니라 게임할 맛 나게 이것저것 배경들이 있고, 점수가 올라감에 따라 디자인도 바뀌고."
// 배경은 공용 `MiniGameBackdrop`(하늘·별·능선 2층 패럴랙스), 팔레트는 공용 `MiniGameStage` 5단계로 갈았다.
// **난이도 값은 한 글자도 건드리지 않았다** — 순위표가 걸린 게임이라 그림이 규칙을 흔들면 남은 기록의 의미가 깨진다.
// 무대 경계(0·6·13·22·34)가 튀는 기둥이 시작되는 15와 겹치지 않는 것도 같은 이유다(배경이 예고가 되면 안 된다).
// 그림에 필요한 시계·좌표는 전부 규칙 값 타입 안의 **그림 전용 필드**로 넣었다(아래) — 벽시계를 쓰면 같은 시드가
// 같은 그림을 내놓지 못해 스냅샷으로 검증할 수 없다.


/// 플래피 아잉 규칙. 시드만 주면 결정론적으로 같은 판이 나온다(테스트가 시드를 고정한다).
struct FlappyGame: Equatable, Sendable {
    // 논리 좌표·물리 상수. 클라·테스트가 같은 값을 본다.
    static let width: CGFloat = MiniGameCanvas.logicalWidth
    /// 창 캔버스(344×356)와 같은 비율의 세로 길이. 유도식은 `MiniGameCanvas.logicalHeight` 한 곳에만 있다 —
    /// 타이밍 바도 같은 값을 쓰므로 두 벌로 적으면 언젠가 갈린다.
    static let height: CGFloat = MiniGameCanvas.logicalHeight
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
        /// 틈 중심의 **기준선**. 고정 기둥이면 이 값이 곧 중심이고, 움직이는 기둥이면 이 값에서 한 번 튄다.
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

    // ── 그림 전용 상태(v0.2.48) ──────────────────────────────────────────────────────────
    // 아래 여섯 값은 **오직 뷰가 읽는다**. 규칙(속도·틈·간격·충돌·점수)은 한 번도 이 값을 보지 않는다 —
    // 보는 순간 "디자인을 손대면 난이도가 바뀐다"가 되어 순위표에 남은 기록의 의미가 깨진다.
    // 전부 판 시계(elapsed)·판 거리(scrolled) 기준이고 벽시계를 쓰지 않는다: 같은 시드가 같은 그림을 내놔야
    // 스냅샷으로 디자인을 검증할 수 있기 때문이다.

    /// 이번 판이 흘려보낸 가로 거리(pt). 배경 패럴랙스의 **유일한** 시계다.
    private(set) var scrolled: CGFloat
    /// 마지막 점프의 판 시각. 뷰가 `elapsed - lastFlapAt` 으로 스쿼시·날개·파편의 진행도를 만든다.
    private(set) var lastFlapAt: TimeInterval?
    /// 점프 횟수. 파편의 시드다 — 같은 점프면 같은 파편이 나온다(프레임마다 새로 뽑으면 파편이 끓는다).
    private(set) var flapCount: Int
    /// 마지막 득점의 판 시각.
    private(set) var lastScoreAt: TimeInterval?
    /// 그때 지나온 기둥의 틈 중심 y — "+1" 팝과 링이 뜨는 자리(화면 한가운데면 무엇 때문에 점수가 났는지 안 보인다).
    private(set) var lastScorePipeCenter: CGFloat?
    /// 무대가 바뀐 판 시각(점수가 `MiniGameStage.flappyThresholds` 를 넘은 순간). 전환 플레어·이름 배너에 쓴다.
    private(set) var stageChangedAt: TimeInterval?

    private var rng: MiniGameRandom

    /// 지금 점수의 무대. 규칙이 아니라 **팔레트**다 — 색이 바뀌어도 속도·틈은 그대로다.
    var stage: MiniGameStage { MiniGameStage.forFlappyScore(score) }

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
        scrolled = 0
        lastFlapAt = nil
        flapCount = 0
        lastScoreAt = nil
        lastScorePipeCenter = nil
        stageChangedAt = nil
    }

    /// 테스트 픽스처 — 임의 상태에서 시작한다(난수는 seed).
    /// 그림 전용 인자는 전부 기본값이 있다: 예전 픽스처가 그대로 컴파일돼야 규칙 테스트가 흔들리지 않는다.
    init(seed: UInt64, bird: Bird, pipes: [Pipe], score: Int, phase: Phase, elapsed: TimeInterval = 0,
         scrolled: CGFloat = 0, lastFlapAt: TimeInterval? = nil, flapCount: Int = 0,
         lastScoreAt: TimeInterval? = nil, lastScorePipeCenter: CGFloat? = nil,
         stageChangedAt: TimeInterval? = nil) {
        rng = MiniGameRandom(seed: seed)
        self.bird = bird
        self.pipes = pipes
        self.score = score
        self.phase = phase
        flashRemaining = 0
        self.elapsed = elapsed
        self.scrolled = scrolled
        self.lastFlapAt = lastFlapAt
        self.flapCount = flapCount
        self.lastScoreAt = lastScoreAt
        self.lastScorePipeCenter = lastScorePipeCenter
        self.stageChangedAt = stageChangedAt
    }

    static func == (lhs: FlappyGame, rhs: FlappyGame) -> Bool {
        lhs.bird == rhs.bird && lhs.pipes == rhs.pipes && lhs.score == rhs.score
            && lhs.phase == rhs.phase && lhs.flashRemaining == rhs.flashRemaining && lhs.elapsed == rhs.elapsed
            && lhs.scrolled == rhs.scrolled && lhs.lastFlapAt == rhs.lastFlapAt && lhs.flapCount == rhs.flapCount
            && lhs.lastScoreAt == rhs.lastScoreAt && lhs.lastScorePipeCenter == rhs.lastScorePipeCenter
            && lhs.stageChangedAt == rhs.stageChangedAt
    }

    // MARK: 순수 규칙 — 난이도 곡선

    /// 틈 높이: 132 에서 점수당 3 줄고 96 에서 멈춘다(12점부터). 판 높이 대비 43.7% → 31.8%.
    static func gap(forScore score: Int) -> CGFloat {
        max(96, 132 - CGFloat(3 * max(0, score)))
    }

    /// 스크롤 속도(pt/s): 130 에서 점수당 3 빨라지고 230 에서 멈춘다(34점부터).
    /// 상승률을 절반으로 낮춘 자리에 아래 '갑자기 튀는 틈'이 들어왔다(사용자 요청 2026-09-08).
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
    /// 점수 15 이상이면 30% 로 '튀는 기둥'이 된다. 난수 소비 순서(기준선 → 판정 → 지연 → 방향)는 결정론의 일부다 —
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
            return      // 유예 중 클릭은 아무 일도 아니다 — 여기서 빠져나가지 않으면 죽은 뒤에 날개가 퍼덕인다
        }
        // 그림용 기록. 점프가 **실제로** 일어난 경우에만 갱신한다.
        lastFlapAt = elapsed
        flapCount += 1
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
        // 배경이 흘러간 거리 — 기둥과 **같은 속도**로 누적한다(층별 배속은 배경이 스스로 나눈다).
        scrolled += speed * CGFloat(dt)
        let stageBefore = stage.id
        for i in pipes.indices {
            pipes[i].x -= speed * CGFloat(dt)
            // 화면 오른쪽 끝에 들어온 순간 '튈 시각'을 확정한다(화면 밖에서 미리 튀면 서프라이즈가 아니다).
            if let delay = pipes[i].shiftDelay, pipes[i].shiftAt == nil, pipes[i].x <= Self.width {
                pipes[i].shiftAt = elapsed + delay
            }
            if !pipes[i].passed, bird.x > pipes[i].x + Self.pipeWidth {
                pipes[i].passed = true
                score += 1
                // 그림용: "+1" 과 링이 **지나온 그 기둥의 틈**에서 뜬다.
                lastScoreAt = elapsed
                lastScorePipeCenter = pipes[i].center(at: elapsed)
            }
        }
        // 그림용: 무대가 넘어간 프레임을 한 번 기록(배너·플레어). 점수가 오르는 곳은 위 한 군데뿐이다.
        if stage.id != stageBefore { stageChangedAt = elapsed }
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
        scrolled = 0
        lastFlapAt = nil
        flapCount = 0
        lastScoreAt = nil
        lastScorePipeCenter = nil
        stageChangedAt = nil
        let gapToNext = Self.spacing(forScore: 0)
        pipes = (0..<Self.pipeCount).map { i in
            Self.makePipe(x: Self.firstPipeX + CGFloat(i) * gapToNext, score: 0, rng: &rng)
        }
        phase = .running
    }
}

// MARK: - 그림 전용 상수

/// 이펙트 길이·크기. **난이도와 무관**하다 — 여기 값을 아무리 흔들어도 속도·틈·충돌은 그대로다.
/// 규칙 상수(`FlappyGame.*`)와 한 덩어리로 두지 않는 이유가 그것이다: 그림을 튜닝하다 난이도를 건드리는 사고를 막는다.
private enum FlappyFX {
    // ── 시간(초) ───────────────────────────────────────────────────────────────────────
    /// 점프 스쿼시&스트레치. 0.18 보다 길면 연타할 때 몸이 계속 눌린 채로 남는다.
    static let squash: TimeInterval = 0.18
    /// 점프 순간 발밑에서 퍼지는 공기 아치.
    static let flapArch: TimeInterval = 0.26
    /// 점프 파편.
    static let flapSpark: TimeInterval = 0.35
    /// 점프 순간 스프라이트 전체가 하얗게 뜨는 시간. **정지 프레임에서 "쳤다"를 말하는 유일한 단서다** —
    /// 스쿼시(0.86→1)와 파편만으로는 스냅샷에서 점프가 판별되지 않았다(2026-09-10 지적).
    static let flapFlash: TimeInterval = 0.12
    /// 득점 링과 "+1" 이 화면에 머무는 시간.
    static let scoreRing: TimeInterval = 0.45
    static let scorePopHold: TimeInterval = 0.60
    /// 상단 큰 숫자의 팝.
    static let scorePunch: TimeInterval = 0.30
    /// 무대 배너와 전환 플레어.
    static let stageBanner: TimeInterval = 0.90
    static let stageFlare: TimeInterval = 0.60

    // ── 각도(°) ────────────────────────────────────────────────────────────────────────
    /// 진행 방향(오른쪽)으로 기운 기본 자세. **이것만으로는 방향이 안 보인다** — 원형에 가까운 실루엣에서
    /// −6° 는 눈으로 판별되지 않았다(2026-09-10 실측). 방향의 본체는 `FlappyMascot` 의 세 겹이다.
    static let baseTilt: Double = -6
    /// 낙하 속도에 비례한 기울기 범위.
    static let tiltRange: ClosedRange<Double> = -20...25
    /// 죽은 뒤 회전.
    static let deathSpin: Double = 90

    // ── 크기(논리 pt · 비율) ───────────────────────────────────────────────────────────
    /// 기둥 입구 립의 두께. **반드시 기둥 사각형 안쪽으로만** 그린다 —
    /// 밖으로 1pt 라도 나가면 그리는 사각형 ≠ 충돌 사각형이 되어 "안 닿았는데 죽었다"가 된다.
    static let lip: CGFloat = 10
    /// HUD 한 줄의 세로 중심(논리 pt)과 좌우 여백(논리 pt). 타이밍 바 헤더(headerY 22 · 여백 14)와 같은 규약이다.
    static let scoreY: CGFloat = 26
    static let hudInset: CGFloat = 14
    /// 득점 링 최대 반경. 30 은 판 폭(292)의 1/5 이라 "허공에 뜬 조준환"으로 읽혔다(2026-09-10) —
    /// 16 은 스프라이트 반지름(17)과 같아 '캐릭터가 지나온 자리'로 읽힌다.
    static let scoreRingRadius: CGFloat = 16
    /// "+1"·링이 뜨는 x 오프셋(캐릭터 뒤로 이만큼). 득점 순간 방금 지난 기둥의 **뒷면**이 캐릭터에 닿아 있다.
    static let scorePopBack: CGFloat = FlappyGame.pipeWidth * 0.75
    /// 점프 공기 아치의 반폭·깊이(스프라이트 기준 비율).
    static let flapArchHalfWidth: CGFloat = 0.60
    static let flapArchDepth: CGFloat = 0.34
    /// 점프 파편이 퍼지는 반경 · 죽음 파편 반경.
    static let flapSparkRadius: CGFloat = 30
    static let deathSparkRadius: CGFloat = 46
    /// 점프 파편이 뿌려지는 각도 범위(0 = 앞 · π/2 = 아래 · π = 뒤). **아래·뒤로만** 밀어낸다 —
    /// 온 사방으로 뿌리면 "밟고 올라갔다"가 아니라 "터졌다"로 읽힌다.
    static let flapSparkAngles: ClosedRange<Double> = (0.28 * .pi)...(1.22 * .pi)
    /// 잔상 간격과 불투명도(뒤로 갈수록 옅다).
    static let ghostStep: CGFloat = 9
    static let ghostOpacities: [Double] = [0.20, 0.12, 0.06]
    /// 점프 스쿼시 시작값 → (1, 1).
    static let squashFrom: (x: CGFloat, y: CGFloat) = (0.86, 1.18)
    /// 바닥 그림자: 폭 = spriteSize × (base + gain × 고도) · 납작함 · 불투명도 = base + gain × 고도.
    static let shadowWidth: (base: CGFloat, gain: CGFloat) = (0.42, 0.58)
    static let shadowFlatness: CGFloat = 0.26
    static let shadowOpacity: (base: Double, gain: Double) = (0.10, 0.32)
    /// 죽은 뒤 유예 동안 뷰에서만 떨어지는 거리. 규칙(game.bird)은 절대 건드리지 않는다.
    static let deathDrop: CGFloat = 46
    /// 시작 전 부유 진폭.
    static let idleFloat: CGFloat = 3
    /// 시작 전 캐릭터가 앉아 있는 자리(논리 y). 규칙의 시작 위치(높이/2 = 151)를 쓰면 시작 카드가 그 자리를
    /// 덮어 캐릭터가 카드 뒤에 유령처럼 비친다(2026-09-10 스냅샷에서 확인). **뷰에서만** 카드 위로 올린다 —
    /// 규칙의 bird 는 그대로라 판은 여전히 151 에서 시작한다.
    static let readyPerch: CGFloat = 74

    // ── 스프라이트 위에 얹는 방향·대비 장치 ─────────────────────────────────────────────
    /// 어두운 림(스프라이트 배율과 불투명도). 기둥 본체를 어둡게 내린 것과 **짝**이다 —
    /// 둘 중 하나만으로는 겹치는 순간 실루엣이 사라진다.
    static let rimScale: CGFloat = 1.11
    static let rimOpacity: Double = 0.62
    /// 뒤통수 그늘(왼쪽 끝)과 앞쪽 반사광(오른쪽 끝)의 진하기. 한 장의 그라디언트로 함께 만든다 —
    /// 정면 대칭 얼굴을 3/4 측면처럼 읽히게 하는 것이 이 한 겹의 일이다.
    static let backShade: Double = 0.52
    static let frontLight: Double = 0.42
    /// 뒤로 흐르는 목도리 색. **무대 색이 아니다** — 기둥(structureEdge)·득점(glow)과 같은 색을 쓰면
    /// 캐릭터가 "닿으면 죽는 것"과 같은 신호를 입게 된다.
    static let scarf = Color(red: 0.96, green: 0.42, blue: 0.55)
    static let scarfShade = Color(red: 0.74, green: 0.22, blue: 0.38)
}

// MARK: - 잎 뷰

/// 플래피 아잉 캔버스. 부모가 준 프레임을 채우고, 규칙은 `FlappyGame` 에 맡긴다.
///
/// 프레임 루프는 `TimelineView(.animation(paused:))` 하나뿐이다 — 진행 중(running·over 유예)일 때만 돌고, ready/result
/// 와 허브의 interrupt·일시정지 뒤엔 멈춘다(유휴 0%). 틱은 TimelineView 의 날짜가 바뀔 때(`onChange`)만 일어나므로
/// body 평가 도중 상태를 바꾸지 않는다.
struct FlappyGameView: View {
    let host: MiniGameHost
    let input: MiniGameInput

    @State private var game: FlappyGame
    @State private var lastTick: Date?
    /// 시작 전 부유. **프레임 루프가 아니라** SwiftUI 애니메이션으로 흔든다 — ready 에서는 TimelineView 가
    /// 멈춰 있어야 유휴 0% 가 지켜지기 때문이다.
    @State private var idleBob = false
    /// 부유 애니메이션을 **구조적으로** 살려 둘지. `repeatForever` 는 값만 바꿔서는 안 멈춘다 —
    /// 창을 닫아도 최소화해도 컴포지터가 계속 돌아 코어의 3~5% 를 태웠다(2026-09-10 실측).
    /// 그래서 허브가 판을 끊는 순간(창 닫힘 · 포커스 상실 · 게임 전환 · [그만두기]) 여기를 내려
    /// 애니메이션이 붙어 있던 **뷰 정체성 자체**를 버린다.
    @State private var bobEnabled = true

    init(host: MiniGameHost, input: MiniGameInput, initialGame: FlappyGame? = nil) {
        self.host = host
        self.input = input
        // 시드는 시각에서 — 판마다 다른 기둥. 테스트는 initialGame 으로 고정한다.
        let seed = UInt64(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000))
        _game = State(initialValue: initialGame ?? FlappyGame(seed: seed))
    }

    var body: some View {
        // 일시정지(v0.2.48): 허브가 얼리면 프레임이 아예 돌지 않는다. 정지 화면(스크림·카드)은 허브가 그린다 —
        // 여기서 또 그리면 두 벌이 되어 언젠가 갈린다.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !game.isPlaying || host.isPaused)) { context in
            canvas
                .onChange(of: context.date) { _, now in tick(now) }
        }
        .onChange(of: input.actionCount) { _, _ in act() }
        .onChange(of: host.interruptToken) { _, _ in
            game.interrupt()
            // ready 에서 interrupt() 는 무전이라(전이 없음) 여기서 장식을 직접 끈다 —
            // 창을 닫고도 부유가 계속 도는 자리가 정확히 이 경로였다.
            bobEnabled = false
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
        // 정지 중엔 시간을 흘리지 않는다(lastTick 도 비워야 재개 첫 프레임이 정지 구간을 한꺼번에 밀지 않는다).
        // 프로브는 가드 **앞**이다 — 재는 것이 "틱이 일을 했는가"가 아니라 "프레임 루프가 돌았는가"이기
        // 때문이다. 뒤에 두면 TimelineView 를 안 멈춰도 프레임 수가 0 으로 나와 유휴 0% 가 거짓말이 된다.
        MiniGameFrameProbe.note()
        guard game.isPlaying, !host.isPaused else { lastTick = nil; return }
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
            scorePop
            if !host.reduceMotion, game.flashRemaining > 0 {
                CheckTheme.danger
                    .opacity(0.25 * game.flashRemaining / FlappyGame.flashDuration)
                    .allowsHitTesting(false)
            }
            overlayCard
        }
        // 바탕은 캔버스가 하늘로 꽉 채운다(예전 fieldFill 은 배경 아래로 사라졌다 — 검은 판이 "게임할 맛이 없다"는
        // 지적의 절반이었다, 2026-09-10). 모서리만 창 모양대로 잘라 낸다.
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        // 투영은 공용 `MiniGameProjection` 하나다 — 예전엔 여기 지역 클로저 두 개를 따로 만들어
        // 타이밍 바와 같은 일을 다른 코드로 하고 있었다.
        let t = MiniGameProjection(container: size, logicalSize: FlappyGame.logicalSize)
        let full = CGRect(origin: .zero, size: size)
        let stage = game.stage
        let motion = !host.reduceMotion

        // 1) 배경 — 논리 사각형이 아니라 **캔버스 전체**를 덮는다. 레터박스 여백(±0.5pt)까지 하늘이어야
        //    판이 액자 속 그림처럼 보이지 않는다.
        MiniGameBackdrop.draw(into: &context, rect: full, stage: stage, scroll: game.scrolled,
                              terrain: true, reduceMotion: host.reduceMotion)

        // 2) 바닥 그림자 — 높이 뜰수록 작고 옅다(깊이감). 기둥보다 아래 레이어라 기둥에 가려진다.
        let altitude = min(max(displayBirdY / FlappyGame.height, 0), 1)
        let shadowWidth = FlappyGame.spriteSize
            * (FlappyFX.shadowWidth.base + FlappyFX.shadowWidth.gain * altitude) * t.scale
        let shadowHeight = shadowWidth * FlappyFX.shadowFlatness
        context.fill(
            Path(ellipseIn: CGRect(x: t.point(game.bird.x, 0).x - shadowWidth / 2,
                                   y: t.point(0, FlappyGame.height).y - shadowHeight * 0.95,
                                   width: shadowWidth, height: shadowHeight)),
            with: .color(.black.opacity(FlappyFX.shadowOpacity.base
                                        + FlappyFX.shadowOpacity.gain * Double(altitude)))
        )

        // 3) 기둥. 사각으로 그려 끝이 캔버스 가장자리에 딱 붙는다(모서리를 둥글리면 천장·바닥에 틈이 생겨
        //    "떠 있는 막대"로 보인다 — 그 지적이 이 판의 이유다).
        //    ★ 채움 그라디언트는 **캔버스 세로 전체**를 기준으로 잡는다. 기둥 사각형마다 따로 잡으면 같은 y 라도
        //      기둥 길이에 따라 색이 달라져, 틈이 튄 기둥과 고정 기둥이 다르게 보인다 — 색으로 미리 알려 주지
        //      않기로 한 결정(사용자, 2026-09-08)이 그 자리에서 깨진다.
        //    ★ 튀는 기둥 분기는 여기 없다. 그림이 `isShifting`·`shiftAt` 을 읽는 순간 같은 결정이 깨진다.
        //    ★ 본체는 **어두운 대역**(structureDeep → structureDeepLit)이다. 예전엔 structure → structureEdge
        //      라 한낮 기둥과 캐릭터의 휘도비가 1.01:1 이었고, 겹치는 순간 플레이어가 통째로 사라졌다
        //      (2026-09-10 5개 무대 실측). 지금은 무대 5종 전부에서 캐릭터가 기둥보다 3.1:1 이상 밝다.
        //      밝은 색은 립·경계선·외곽선에만 남는다 — 그래서 기둥은 "어두운 기둥 + 빛나는 윤곽"으로 읽힌다.
        let pipeShading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [stage.structureDeep, stage.structureDeepLit]),
            startPoint: CGPoint(x: full.midX, y: full.minY),
            endPoint: CGPoint(x: full.midX, y: full.maxY)
        )
        for pipe in game.pipes {
            let halves: [(rect: CGRect, isTop: Bool)] = [
                (pipe.topRect(at: game.elapsed), true),
                (pipe.bottomRect(at: game.elapsed, height: FlappyGame.height), false)
            ]
            for half in halves where half.rect.height > 0 {
                let path = Path(t.rect(half.rect))
                context.fill(path, with: pipeShading)
                // 입구 립 — 틈 쪽 끝에서 **안쪽으로** lip(10pt). 사각형 밖으로는 한 점도 나가지 않는다.
                let lipHeight = min(FlappyFX.lip, half.rect.height)
                let lipY = half.isTop ? half.rect.maxY - lipHeight : half.rect.minY
                context.fill(
                    Path(t.rect(CGRect(x: half.rect.minX, y: lipY, width: half.rect.width, height: lipHeight))),
                    with: .color(stage.structureEdge.opacity(0.55))
                )
                if half.rect.height > FlappyFX.lip {
                    // 립과 몸통의 경계선(1pt). 역시 사각형 안쪽이다.
                    let edgeY = half.isTop ? lipY : lipY + lipHeight - 1
                    context.fill(
                        Path(t.rect(CGRect(x: half.rect.minX, y: edgeY, width: half.rect.width, height: 1))),
                        with: .color(stage.structureEdge.opacity(0.95))
                    )
                }
                // 외곽선은 어두워진 본체를 하늘에서 세워 주는 유일한 선이다 — 1pt 로는 밤·오로라에서 묻힌다.
                context.stroke(path, with: .color(stage.structureEdge.opacity(0.92)), lineWidth: 1.5)
            }
        }

        // 4) 무대 전환 플레어 — 아래에서 위로 한 번 번진다(배너와 같은 순간).
        if motion, let changed = game.stageChangedAt {
            MiniGameEffects.flare(into: &context, rect: full,
                                  progress: (game.elapsed - changed) / FlappyFX.stageFlare, color: stage.glow)
        }

        // 5) 득점 링 — 지나온 기둥의 틈 자리에서.
        if motion, let at = game.lastScoreAt, let center = game.lastScorePipeCenter {
            MiniGameEffects.ring(into: &context, center: t.point(Self.scorePopX, center),
                                 progress: (game.elapsed - at) / FlappyFX.scoreRing,
                                 maxRadius: FlappyFX.scoreRingRadius * t.scale,
                                 color: stage.glow, lineWidth: 1.5)
        }

        // 6) 점프 임팩트 — **발밑에서 아래로 퍼지는 공기 아치 + 아래·뒤로 밀리는 파편**.
        //    예전엔 몸통 왼쪽(= 뒤)에 날개 타원을 그렸는데, 캔버스가 스프라이트보다 아래 레이어라 잔상 3장에
        //    가려 40%만 삐져나왔고 색이 `structureEdge`(기둥 립)라 '점프' 신호가 '닿으면 죽는 것' 신호와
        //    겹쳤다(2026-09-10 지적). 지금은 자리도 색도 캐릭터 것이다: 앞·아래 · stage.glow.
        if motion, game.phase == .running, let at = game.lastFlapAt {
            let sinceFlap = game.elapsed - at
            let foot = t.point(game.bird.x + FlappyGame.spriteSize * 0.08,
                             displayBirdY + FlappyGame.spriteSize * 0.52)
            MiniGameEffects.arch(into: &context, center: foot,
                                 progress: sinceFlap / FlappyFX.flapArch,
                                 halfWidth: FlappyGame.spriteSize * FlappyFX.flapArchHalfWidth * t.scale,
                                 depth: FlappyGame.spriteSize * FlappyFX.flapArchDepth * t.scale,
                                 color: stage.glow, lineWidth: 2.2)
            MiniGameEffects.sparks(into: &context, center: foot,
                                   progress: sinceFlap / FlappyFX.flapSpark,
                                   count: 10, maxRadius: FlappyFX.flapSparkRadius * t.scale,
                                   color: stage.glow, seed: UInt64(game.flapCount), dotRadius: 3.5,
                                   angles: FlappyFX.flapSparkAngles)
        }

        // 7) 죽는 순간의 큰 파편(붉은 플래시와 짝). 진행도는 남은 유예(overHold)에서 뽑는다 —
        //    over 중엔 판 시계(elapsed)가 멈춰 있어 elapsed 로는 아무것도 움직이지 않는다.
        //    자리는 **부딪힌 그 지점**이다(떨어지는 몸을 따라다니면 충돌 위치가 흐려진다).
        if motion, let progress = deathProgress, progress < 1 {
            MiniGameEffects.sparks(into: &context, center: t.point(game.bird.x, game.bird.y),
                                   progress: progress, count: 14,
                                   maxRadius: FlappyFX.deathSparkRadius * t.scale,
                                   color: CheckTheme.danger, seed: UInt64(game.flapCount) &+ 91, dotRadius: 2.5)
        }
    }

    /// "+1" 과 득점 링이 뜨는 논리 x. 득점 순간 방금 지나온 기둥의 **뒷면**이 캐릭터에 닿아 있으므로,
    /// 캐릭터 바로 뒤(기둥 폭의 3/4)에 두면 "저 기둥을 통과해서 받았다"가 보인다. 한 기둥 폭(44)을
    /// 통째로 물리면 표시가 왼쪽 허공에 뜨고(2026-09-10 지적), 0 이면 글씨가 얼굴을 덮는다.
    private static let scorePopX = FlappyGame.birdX - FlappyFX.scorePopBack

    /// 스프라이트(아잉 PNG)와 상단 HUD. 위치는 논리 좌표를 실제 크기로 옮겨 놓는다.
    private var spriteAndScore: some View {
        GeometryReader { geo in
            let t = MiniGameCanvas.transform(in: geo.size, logicalSize: FlappyGame.logicalSize)
            let side = FlappyGame.spriteSize * t.scale
            let cx = t.origin.x + game.bird.x * t.scale
            let cy = t.origin.y + displayBirdY * t.scale
            // 잔상 — 진행 중에만, 뒤로 갈수록 옅게. 속도감을 만드는 값싼 수단이다(블러는 60Hz 예산에서 못 쓴다).
            // 잔상에는 방향 장치도 림도 없다: 필요한 것은 실루엣뿐이고, 60Hz 에서 네 벌을 다 그릴 이유가 없다.
            if !host.reduceMotion, game.phase == .running {
                ForEach(0..<FlappyFX.ghostOpacities.count, id: \.self) { index in
                    FlappyMascot(mood: mood, facing: false, rim: false)
                        .frame(width: side, height: side)
                        .rotationEffect(.degrees(spriteAngle))
                        .opacity(FlappyFX.ghostOpacities[index])
                        .position(x: cx - FlappyFX.ghostStep * CGFloat(index + 1) * t.scale, y: cy)
                }
            }
            // 부유는 **구조 분기**로 켜고 끈다. 플래그만 내리거나 애니메이션을 nil 로 바꾸는 것으로는
            // 이미 시작된 repeatForever 가 안 멈춘다(2026-09-10 실측: 창을 닫아도 최소화해도 코어의 3~5%가
            // 계속 탔다 — 뷰가 살아 있고 컴포지터가 디스플레이 링크를 붙들고 있기 때문이다).
            // 분기가 갈리면 애니메이션이 붙어 있던 뷰 정체성 자체가 버려진다(같은 실측에서 0.03%).
            if bobEnabled, game.phase == .ready, !host.reduceMotion {
                mascot(side: side)
                    .position(x: cx, y: cy)
                    .offset(y: (idleBob ? -FlappyFX.idleFloat : FlappyFX.idleFloat) * t.scale)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: idleBob)
            } else {
                mascot(side: side)
                    .position(x: cx, y: cy)
            }
            if showsTopScore { scoreHUD(t) }
        }
        .allowsHitTesting(false)
        .onAppear {
            // ready 에서만 부유한다. 시작하면 위 분기가 갈리며 반복 애니메이션이 통째로 버려진다.
            if game.phase == .ready, !host.reduceMotion { idleBob = true }
        }
    }

    /// 지금 자세의 캐릭터 한 장(림 · 방향 장치 · 점프 플래시 포함).
    private func mascot(side: CGFloat) -> some View {
        FlappyMascot(mood: mood, flash: flapFlash, facing: !host.reduceMotion)
            .frame(width: side, height: side)
            .scaleEffect(x: squash.x, y: squash.y)
            .rotationEffect(.degrees(spriteAngle))
    }

    private var mood: CheckMascotAssets.Mood { game.isGameOver ? .negative : .neutral }

    /// 상단 HUD — **두 게임이 같은 규약을 쓴다**(2026-09-10 지적: 같은 창의 같은 자리에서 탭만 바꿨는데
    /// 점수가 화면 반대편으로 간다). 왼쪽 위 = 진행 표시(플래피 무대 점 5개 · 타이밍 바 "라운드 N/10")와
    /// 무대 이름, 오른쪽 위 = 큰 점수. 한 줄을 나눠 쓰므로 HUD 가 판 안쪽으로 자라지 않는다.
    ///
    /// 무대 이름을 **상시**가 아니라 바뀌는 0.9초에만 띄우는 것만 타이밍 바와 다르다: 플래피는 판이 흐르는
    /// 게임이라 상시 글씨가 기둥과 겹쳐 흐른다. 대신 자리·모양은 같은 캡슐이다.
    private func scoreHUD(_ t: (scale: CGFloat, origin: CGPoint)) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Group {
                if showsStageBanner {
                    MiniGameStageChip(stage: game.stage)
                } else {
                    stageDots
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 2)
            Spacer(minLength: 4)
            Text("\(game.score)")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.primaryText)
                // 배경이 하늘로 밝아졌으니 숫자는 그림자 두 겹으로 대비를 챙긴다 — 좁은 그림자는 획을 또렷하게,
                // 넓은 그림자는 밝은 립(한낮 초록·노을 주황) 위에 겹쳤을 때 글자를 띄운다(2026-09-10 스냅샷).
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                .shadow(color: .black.opacity(0.40), radius: 7)
                .scaleEffect(scorePunch)
        }
        .frame(width: (FlappyGame.width - FlappyFX.hudInset * 2) * t.scale)
        .position(x: t.origin.x + FlappyGame.width / 2 * t.scale,
                  y: t.origin.y + FlappyFX.scoreY * t.scale)
    }

    /// 무대 진행 점 5개 — 지금 무대만 채우고 나머지는 테두리만(채움과 크기 두 가지로 표시한다: 색만으로 알리지 않는다).
    private var stageDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<MiniGameStage.all.count, id: \.self) { index in
                let current = index == game.stage.id
                Circle()
                    .fill(current ? game.stage.glow : Color.clear)
                    .overlay(Circle().stroke(game.stage.glow.opacity(current ? 0 : 0.6), lineWidth: 1))
                    .frame(width: current ? 6 : 5, height: current ? 6 : 5)
            }
        }
    }

    /// 득점 순간 그 자리에 떠오르는 "+1". 점수를 id 로 물려 매 득점마다 처음부터 다시 등장한다.
    @ViewBuilder
    private var scorePop: some View {
        if let at = game.lastScoreAt, let center = game.lastScorePipeCenter,
           game.elapsed - at < FlappyFX.scorePopHold, showsTopScore {
            GeometryReader { geo in
                let t = MiniGameCanvas.transform(in: geo.size, logicalSize: FlappyGame.logicalSize)
                MiniGameScorePop(text: "+1", tint: game.stage.glow, reduceMotion: host.reduceMotion)
                    .id(game.score)
                    .position(x: t.origin.x + Self.scorePopX * t.scale,
                              y: t.origin.y + center * t.scale)
            }
            .allowsHitTesting(false)
        }
    }

    private var showsTopScore: Bool {
        switch game.phase {
        case .running, .over: true
        case .ready, .result: false
        }
    }

    private var showsStageBanner: Bool {
        guard let changed = game.stageChangedAt else { return false }
        return game.elapsed - changed < FlappyFX.stageBanner
    }

    /// 낙하 속도에 비례해 기운다(위로 −20°, 아래로 +25°) + 진행 방향으로 기운 기본 자세(−6°) + 죽은 뒤 회전(+90°).
    /// 기본 자세는 **동작이 아니라 방향 표시**라 동작 줄이기에서도 남긴다(속도 기울기와 회전만 뺀다).
    private var spriteAngle: Double {
        guard !host.reduceMotion else { return FlappyFX.baseTilt }
        let raw = Double(game.bird.vy / FlappyGame.maxFallSpeed) * FlappyFX.tiltRange.upperBound
        let tilt = min(FlappyFX.tiltRange.upperBound, max(FlappyFX.tiltRange.lowerBound, raw))
        return FlappyFX.baseTilt + tilt + FlappyFX.deathSpin * (deathProgress ?? 0)
    }

    /// 점프 직후 0.18초 동안 (0.86, 1.18) → (1, 1) easeOut. 점프에 "임팩트"를 주는 가장 값싼 수단이다.
    private var squash: (x: CGFloat, y: CGFloat) {
        guard !host.reduceMotion, game.phase == .running, let at = game.lastFlapAt else { return (1, 1) }
        let progress = (game.elapsed - at) / FlappyFX.squash
        guard progress >= 0, progress < 1 else { return (1, 1) }
        let eased = CGFloat(1 - pow(1 - progress, 3))
        return (FlappyFX.squashFrom.x + (1 - FlappyFX.squashFrom.x) * eased,
                FlappyFX.squashFrom.y - (FlappyFX.squashFrom.y - 1) * eased)
    }

    /// 죽은 뒤 유예(0.4초)의 진행도. `.result` 는 이미 다 떨어진 상태(1).
    /// over 중에는 판 시계가 멈춰 있으므로 elapsed 가 아니라 남은 유예로 계산한다.
    private var deathProgress: Double? {
        switch game.phase {
        case .over(let hold): min(1, max(0, 1 - hold / FlappyGame.overHold))
        case .result: 1
        case .ready, .running: nil
        }
    }

    /// 뷰가 캐릭터를 그리는 y(논리). 규칙의 `bird.y` 와 갈라지는 경우는 둘뿐이고 **둘 다 그림일 뿐이다**:
    /// 시작 전(카드에 가리지 않게 위로) · 죽은 뒤(유예 동안 떨어뜨리는 연출).
    private var displayBirdY: CGFloat {
        game.phase == .ready ? FlappyFX.readyPerch : game.bird.y + deathDrop
    }

    /// 죽은 뒤 아래로 떨어지는 거리(논리 pt). **뷰 전용** — 규칙의 bird 는 건드리지 않는다
    /// (건드리면 죽은 뒤에 충돌 판정과 점수가 또 바뀐다).
    private var deathDrop: CGFloat {
        guard !host.reduceMotion, let progress = deathProgress else { return 0 }
        return FlappyFX.deathDrop * CGFloat(progress * progress)
    }

    /// 상단 큰 숫자의 팝(1.28 → 1).
    private var scorePunch: CGFloat {
        guard !host.reduceMotion, let at = game.lastScoreAt else { return 1 }
        let progress = (game.elapsed - at) / FlappyFX.scorePunch
        guard progress >= 0, progress < 1 else { return 1 }
        return 1 + 0.28 * CGFloat(1 - (1 - pow(1 - progress, 3)))
    }

    /// 점프 직후 스프라이트를 하얗게 띄우는 진행도(1 → 0).
    private var flapFlash: Double {
        guard !host.reduceMotion, game.phase == .running, let at = game.lastFlapAt else { return 0 }
        let progress = (game.elapsed - at) / FlappyFX.flapFlash
        guard progress >= 0, progress < 1 else { return 0 }
        return 1 - progress
    }

    /// 시작·결과 카드는 두 게임이 **같은** `MiniGameOverlayCard` 를 쓴다(색·글씨 통일 — 2026-09-08 지적).
    /// 아이콘·강조색은 지금 무대에서 가져온다 — 카드가 배경 위에 얹힌 남의 물건처럼 보이지 않게(2026-09-10).
    @ViewBuilder
    private var overlayCard: some View {
        switch game.phase {
        case .ready:
            MiniGameOverlayCard(
                title: MiniGameKind.flappy.title,
                subtitle: MiniGameKind.flappy.howToPlay,
                action: "\(MiniGameKind.controlHint)로 시작",
                icon: MiniGameKind.flappy.icon,
                tint: game.stage.glow
            )
        case .result:
            MiniGameOverlayCard(
                title: "\(game.score)점",
                titleIsScore: true,
                subtitle: game.score > host.bestScore ? "신기록!" : "최고 \(host.bestScore)",
                subtitleIsHighlighted: game.score > host.bestScore,
                action: "\(MiniGameKind.controlHint)로 다시",
                icon: MiniGameKind.flappy.icon,
                tint: game.stage.glow
            )
        case .running, .over:
            EmptyView()
        }
    }
}

// MARK: - 방향을 가진 마스코트

/// 진행 방향(오른쪽)을 말하는 캐릭터 한 장.
///
/// **왜 필요한가.** 아잉 PNG 는 눈·입·볼터치가 몸통 중심에 대해 완전히 대칭인 **정면 얼굴**이라 얼굴을 돌릴
/// 수 없다. v0.2.48 초안은 −6° 기울기 하나로 방향을 만들려 했는데, 원형에 가까운 실루엣에서 −6° 는 다섯 무대
/// 스냅샷 어디에서도 눈으로 판별되지 않았다(2026-09-10 지적: "달려가는 쪽으로 좀 바라보고"가 구현되지 않았다).
/// PNG 를 못 고치므로 **얹어서** 만든다. 넷을 함께 쓴다:
///   ① 어두운 림 — 실루엣을 하늘·기둥·언덕에서 떼어 놓는다. 기둥 본체를 어둡게 내린 것과 짝이다.
///   ② 뒤통수 그늘 — 왼쪽(뒤) 절반에 검은 그라디언트. 빛이 앞에서 온다 = 앞이 오른쪽이다.
///   ③ 앞쪽 반사광 — 오른쪽 가장자리의 흰 띠. ②와 함께 정면 얼굴을 3/4 측면처럼 읽히게 한다.
///   ④ 뒤로 흐르는 목도리 — 몸통 뒤로 뻗는 두 갈래. 좌우를 뒤집으면 곧바로 어긋나는, 가장 강한 신호다.
/// **판정 기준**: 스냅샷을 좌우 반전했을 때 다르게 보여야 통과다.
private struct FlappyMascot: View {
    let mood: CheckMascotAssets.Mood
    /// 점프 순간의 흰 플래시(1 → 0). 정지 프레임에서 "쳤다"를 말한다.
    var flash: Double = 0
    /// 방향 장치(그늘 · 반사광 · 목도리)를 그릴지. 잔상은 실루엣만 필요해 false 다.
    var facing: Bool = true
    /// 어두운 림을 두를지.
    var rim: Bool = true

    var body: some View {
        ZStack {
            if rim {
                image
                    .colorMultiply(.black)
                    .opacity(FlappyFX.rimOpacity)
                    .scaleEffect(FlappyFX.rimScale)
            }
            if facing { FlappyScarfTails().fill(scarfShading) }
            image
            if facing {
                // 뒤통수 그늘 + 앞쪽 반사광을 **한 장**으로. 실루엣 안쪽에만 얹는다(마스크가 PNG 알파다).
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(FlappyFX.backShade), location: 0),
                        .init(color: .clear, location: 0.48),
                        .init(color: .white.opacity(FlappyFX.frontLight), location: 1)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .mask(image)
                // 목도리 매듭은 몸통 **위**다(뒤로만 그리면 뒤에 붙은 깃발로 보인다). 실루엣으로 자른다.
                FlappyScarfKnot().fill(scarfShading).mask(image)
            }
            if flash > 0 {
                Color.white.opacity(0.9 * flash).mask(image)
            }
        }
        .compositingGroup()
    }

    private var scarfShading: LinearGradient {
        LinearGradient(colors: [FlappyFX.scarfShade, FlappyFX.scarf],
                       startPoint: .leading, endPoint: .trailing)
    }

    @ViewBuilder
    private var image: some View {
        // 공유 캐시 원본이다 — size 를 바꾸거나 lockFocus 로 그리면 메뉴바·헤더까지 오염된다. SwiftUI 축소만.
        if let nsImage = CheckMascotAssets.image(for: mood) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Circle().fill(CheckTheme.working)
        }
    }
}

/// 좌표는 모두 스프라이트 사각형(0…1) 기준이다. 아잉 실루엣은 y 0.72…0.82 에서 몸통만 남으므로
/// (귀는 0.65…0.72 · 아래 꼬리는 0.85 에서 끝난다 — PNG 알파 실측) 매듭을 그 띠에 얹는다.
private enum FlappyScarfShape {
    static func point(_ rect: CGRect, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }
}

/// 몸통을 두른 매듭 띠. 실루엣 마스크로 잘리므로 좌우로 넉넉히 넘겨 그린다.
private struct FlappyScarfKnot: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { FlappyScarfShape.point(rect, x, y) }
        var path = Path()
        path.move(to: p(-0.05, 0.715))
        path.addQuadCurve(to: p(1.05, 0.715), control: p(0.50, 0.790))
        path.addLine(to: p(1.05, 0.820))
        path.addQuadCurve(to: p(-0.05, 0.820), control: p(0.50, 0.895))
        path.closeSubpath()
        return path
    }
}

/// 몸통 뒤로 흐르는 두 갈래. 시작점은 몸통 **안쪽**(매듭에서 나온다), 끝은 사각형 **밖**(x < 0)에서
/// 한 점으로 모인다 — 끝을 직선으로 자르면 리본이 아니라 붙여 놓은 깃발로 보인다(2026-09-10 1차 시안).
private struct FlappyScarfTails: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { FlappyScarfShape.point(rect, x, y) }
        var path = Path()
        // 위 갈래 — 길고, 뒤로 가며 올라간다.
        path.move(to: p(0.38, 0.70))
        path.addQuadCurve(to: p(-0.16, 0.56), control: p(0.06, 0.60))
        path.addQuadCurve(to: p(0.40, 0.81), control: p(0.10, 0.76))
        path.closeSubpath()
        // 아래 갈래 — 짧고 아래로 처진다(둘이 갈려야 '흐른다'로 읽힌다).
        path.move(to: p(0.36, 0.79))
        path.addQuadCurve(to: p(-0.03, 0.97), control: p(0.08, 0.85))
        path.addQuadCurve(to: p(0.40, 0.85), control: p(0.18, 0.92))
        path.closeSubpath()
        return path
    }
}
