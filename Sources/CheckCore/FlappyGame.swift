import Foundation
import SwiftUI

// B3: `MiniGameFlappy.swift` 에서 화면(AppKit·뷰)과 무관한 규칙·값 타입만 코어로 옮겼다.
// 설명 주석의 큰 줄기(왜 이 값인가)는 원래 파일 머리에 남아 있다.

/// 플래피 아잉 규칙. 시드만 주면 결정론적으로 같은 판이 나온다(테스트가 시드를 고정한다).
package struct FlappyGame: Equatable, Sendable {
    // 논리 좌표·물리 상수. 클라·테스트가 같은 값을 본다.
    package static let width: CGFloat = MiniGameCanvas.logicalWidth
    /// 창 캔버스(344×356)와 같은 비율의 세로 길이. 유도식은 `MiniGameCanvas.logicalHeight` 한 곳에만 있다 —
    /// 타이밍 바도 같은 값을 쓰므로 두 벌로 적으면 언젠가 갈린다.
    package static let height: CGFloat = MiniGameCanvas.logicalHeight
    /// 뷰가 `MiniGameCanvas.transform(in:logicalSize:)` 에 넘기는 판 크기.
    package static var logicalSize: CGSize { CGSize(width: width, height: height) }
    package static let birdX: CGFloat = 0.28 * width
    /// 충돌 판정 상자(정사각). 스프라이트(34)보다 작게 둬 "닿은 것 같은데 죽었다"를 줄인다.
    package static let hitboxSize: CGFloat = 24
    package static let spriteSize: CGFloat = 34
    package static let gravity: CGFloat = 1360
    /// 점프 높이 = 317² / (2·1360) = 36.9pt(판 높이의 12.2%).
    package static let flapVelocity: CGFloat = -317
    package static let maxFallSpeed: CGFloat = 574
    package static let pipeWidth: CGFloat = 44
    /// 첫 기둥은 화면 밖 80pt 에서 시작 — 시작 직후 자세를 잡을 시간(≈0.6초)을 준다.
    package static let firstPipeX: CGFloat = width + 80
    /// 항상 화면 안팎에 유지하는 기둥 수. 간격이 최소(115)여도 세 개가 폭 292 를 덮고 하나가 오른쪽 밖에 대기한다.
    package static let pipeCount = 3
    package static let maxScore = MiniGameKind.flappy.maxScore
    /// 틈 중심을 뽑을 때 위·아래로 남기는 여백(세로 1.51배에 맞춰 24 → 36).
    package static let centerMargin: CGFloat = 36
    /// 게임오버 뒤 결과 카드가 뜨기까지의 유예(그 사이 클릭은 무시 — 죽자마자 실수로 새 판을 열지 않게).
    package static let overHold: TimeInterval = 0.4
    /// 게임오버 순간 빨간 플래시 길이.
    package static let flashDuration: TimeInterval = 0.15
    /// dt 상한. 앱 정지·창 재표시 뒤 첫 프레임이 몇 초를 한 번에 밀지 않게.
    package static let maxStep: TimeInterval = 1.0 / 30.0

    package struct Pipe: Equatable, Sendable {
        package var x: CGFloat
        /// 틈 중심의 **기준선**. 고정 기둥이면 이 값이 곧 중심이고, 움직이는 기둥이면 이 값에서 한 번 튄다.
        package var centerY: CGFloat
        package var gap: CGFloat
        package var passed: Bool = false
        /// 화면에 들어온 뒤 튀기까지의 지연(초). **nil 이면 고정 기둥**이다.
        package var shiftDelay: TimeInterval?
        /// 튀는 폭과 방향(+ 아래 · − 위). `shiftDelay` 가 nil 이면 0.
        package var shiftOffset: CGFloat = 0
        /// 튀기 시작하는 **판 시각**(초). 기둥이 화면 오른쪽 끝에 들어올 때 `elapsed + shiftDelay` 로 한 번 채워진다.
        /// 채워지기 전(nil)에는 기준선 그대로다 — 화면 밖에서 미리 튀어 버리면 서프라이즈가 아니라 사고다.
        package var shiftAt: TimeInterval?

        /// 이 기둥이 언젠가 튀는가(테스트·조준 판정용). 그림은 이 값을 보지 않는다 — 색 신호가 없기 때문이다.
        package var isShifting: Bool { shiftDelay != nil }

        /// 그 시각의 틈 중심. **충돌·그리기가 같은 이 함수를 쓴다** — 갈라지면 "안 닿았는데 죽었다"가 된다.
        ///
        /// 튀기 전에는 기준선, `shiftAt` 부터 `shiftDuration`(0.12초) 동안 easeOut 으로 `shiftOffset` 만큼 옮겨 간 뒤
        /// 그 자리에 머문다(왕복 없음). 마지막 클램프는 손으로 만든 픽스처 대비다 — 실제 생성은 아래 `makePipe` 가
        /// 여백 안에서만 방향을 고르므로 걸리지 않는다.
        package func center(at time: TimeInterval) -> CGFloat {
            guard let shiftAt else { return centerY }
            let progress = min(max((time - shiftAt) / FlappyGame.shiftDuration, 0), 1)
            let eased = 1 - pow(1 - progress, 3)          // easeOut — 시작이 가장 빠르다
            let moved = centerY + shiftOffset * CGFloat(eased)
            return min(max(moved, gap / 2), FlappyGame.height - gap / 2)
        }

        /// 위 기둥 [0, center − gap/2] — 천장에 붙는다.
        package func topRect(at time: TimeInterval) -> CGRect {
            CGRect(x: x, y: 0, width: FlappyGame.pipeWidth, height: max(0, center(at: time) - gap / 2))
        }
        /// 아래 기둥 [center + gap/2, height] — 바닥에 붙는다.
        package func bottomRect(at time: TimeInterval, height: CGFloat) -> CGRect {
            let top = center(at: time) + gap / 2
            return CGRect(x: x, y: top, width: FlappyGame.pipeWidth, height: max(0, height - top))
        }
    }

    package struct Bird: Equatable, Sendable {
        package var x: CGFloat
        package var y: CGFloat
        package var vy: CGFloat
    }

    package enum Phase: Equatable, Sendable {
        /// 시작 전(루프 정지). 액션 = 새 판 + 첫 점프.
        case ready
        case running
        /// 충돌 직후. `hold` 초가 남았고 다 지나면 `.result`.
        case over(hold: TimeInterval)
        /// 결과 카드(루프 정지). 액션 = 새 판 + 첫 점프.
        case result
    }

    package private(set) var bird: Bird
    package private(set) var pipes: [Pipe]
    package private(set) var score: Int
    package private(set) var phase: Phase
    /// 게임오버 플래시 잔여 시간(0 이면 없음).
    package private(set) var flashRemaining: TimeInterval
    /// 이번 판이 시작된 뒤 흐른 시간(초). 움직이는 기둥의 틈 위치가 이 시계를 본다 —
    /// 벽시계가 아니라 `step(dt:)` 이 흘린 시간이라 판이 결정적으로 재현된다.
    package private(set) var elapsed: TimeInterval

    // ── 그림 전용 상태 ───────────────────────────────────────────────────────────────────
    // 아래 넷은 **오직 뷰가 읽는다**. 규칙(속도·틈·간격·충돌·점수)은 한 번도 이 값을 보지 않는다 —
    // 보는 순간 "디자인을 손대면 난이도가 바뀐다"가 되어 순위표에 남은 기록의 의미가 깨진다.
    // 전부 판 시계(elapsed)·판 거리(scrolled) 기준이고 벽시계를 쓰지 않는다: 같은 시드가 같은 그림을 내놔야
    // 스냅샷으로 디자인을 검증할 수 있기 때문이다.
    //
    // ⚠️ v0.2.51 에서 여기 있던 **`trail`(잔상 이력)과 `stageChangedAt`(무대 전환 시각)을 지웠다.**
    //    잔상은 사용자가 없애 달라고 한 그것이고, 무대 전환 시각은 그것만 보던 플레어·이름 배너가 함께 지워져
    //    아무도 읽지 않는 값이 됐다. **그리지 않는 값을 매 프레임 갱신하면 지운 의미가 없다** — 특히 잔상은
    //    배열 밀기·버리기·붙이기가 프레임마다 돌던 자리다. 되살리려면 뷰가 아니라 여기부터 손대게 되고,
    //    그것이 곧 "사용자에게 다시 물어야 한다"는 뜻이다.

    /// 이번 판이 흘려보낸 가로 거리(pt). 배경 패럴랙스의 **유일한** 시계다.
    package private(set) var scrolled: CGFloat
    /// 마지막 점프의 판 시각. 뷰가 `elapsed - lastFlapAt` 으로 발밑 파편의 진행도를 만든다.
    package private(set) var lastFlapAt: TimeInterval?
    /// 점프 횟수. 파편의 시드다 — 같은 점프면 같은 파편이 나온다(프레임마다 새로 뽑으면 파편이 끓는다).
    package private(set) var flapCount: Int
    /// 마지막 득점의 판 시각.
    package private(set) var lastScoreAt: TimeInterval?
    /// 그때 지나온 기둥의 틈 중심 y — "+1" 이 뜨는 자리(화면 한가운데면 무엇 때문에 점수가 났는지 안 보인다).
    package private(set) var lastScorePipeCenter: CGFloat?

    private var rng: MiniGameRandom

    /// 지금 점수의 무대. 규칙이 아니라 **팔레트**다 — 색이 바뀌어도 속도·틈은 그대로다.
    package var stage: MiniGameStage { MiniGameStage.forFlappyScore(score) }

    /// 프레임 루프가 돌아야 하는 상태(running · over 유예). ready/result 는 정지.
    package var isPlaying: Bool {
        switch phase {
        case .running, .over: true
        case .ready, .result: false
        }
    }

    /// 게임오버 이후(over·result) — 스프라이트 표정을 시무룩으로.
    package var isGameOver: Bool {
        switch phase {
        case .over, .result: true
        case .ready, .running: false
        }
    }

    package var hitbox: CGRect {
        CGRect(x: bird.x - Self.hitboxSize / 2, y: bird.y - Self.hitboxSize / 2,
               width: Self.hitboxSize, height: Self.hitboxSize)
    }

    package init(seed: UInt64) {
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
    }

    /// 테스트 픽스처 — 임의 상태에서 시작한다(난수는 seed).
    /// 그림 전용 인자는 전부 기본값이 있다: 예전 픽스처가 그대로 컴파일돼야 규칙 테스트가 흔들리지 않는다.
    package init(seed: UInt64, bird: Bird, pipes: [Pipe], score: Int, phase: Phase, elapsed: TimeInterval = 0,
         scrolled: CGFloat = 0, lastFlapAt: TimeInterval? = nil, flapCount: Int = 0,
         lastScoreAt: TimeInterval? = nil, lastScorePipeCenter: CGFloat? = nil) {
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
    }

    package static func == (lhs: FlappyGame, rhs: FlappyGame) -> Bool {
        lhs.bird == rhs.bird && lhs.pipes == rhs.pipes && lhs.score == rhs.score
            && lhs.phase == rhs.phase && lhs.flashRemaining == rhs.flashRemaining && lhs.elapsed == rhs.elapsed
            && lhs.scrolled == rhs.scrolled && lhs.lastFlapAt == rhs.lastFlapAt && lhs.flapCount == rhs.flapCount
            && lhs.lastScoreAt == rhs.lastScoreAt && lhs.lastScorePipeCenter == rhs.lastScorePipeCenter
    }

    // MARK: 순수 규칙 — 난이도 곡선

    /// 틈 높이: 132 에서 점수당 3 줄고 96 에서 멈춘다(12점부터). 판 높이 대비 43.7% → 31.8%.
    package static func gap(forScore score: Int) -> CGFloat {
        max(96, 132 - CGFloat(3 * max(0, score)))
    }

    /// 스크롤 속도(pt/s): 130 에서 점수당 3 빨라지고 230 에서 멈춘다(34점부터).
    /// 상승률을 절반으로 낮춘 자리에 아래 '갑자기 튀는 틈'이 들어왔다(사용자 요청 2026-09-08).
    package static func speed(forScore score: Int) -> CGFloat {
        min(230, 130 + CGFloat(3 * max(0, score)))
    }

    /// 기둥 사이 수평 간격: 150 에서 점수당 2 좁아지고 115 에서 멈춘다(18점부터) — 기둥이 더 자주 온다.
    package static func spacing(forScore score: Int) -> CGFloat {
        max(115, 150 - CGFloat(2 * max(0, score)))
    }

    /// 튀는 기둥이 나오기 시작하는 점수. 그 전에는 전부 고정이다(조작을 익힐 시간).
    package static let shiftMinScore = 15
    /// 새 기둥이 '튀는 기둥'일 확률. 점수와 무관한 상수 — 30%(2026-09-08 실기 뒤 20% → 30%).
    package static let shiftChance = 0.30
    /// 한 번에 튀는 폭(pt). 논리 302 판에서 틈 하나 남짓 — 눈에 확 띄되 반응할 수 있는 크기다.
    package static let shiftJump: CGFloat = 58
    /// 화면에 들어온 뒤 튀기까지의 지연 범위(초). 기둥마다 난수라 언제 튈지 외울 수 없다.
    package static let shiftDelayRange: ClosedRange<TimeInterval> = 0.45...1.10
    /// 튀는 데 걸리는 시간(초). 순간이동처럼 보이되 프레임 사이가 이어진다.
    package static let shiftDuration: TimeInterval = 0.12

    // MARK: 순수 규칙 — 물리·충돌

    /// 중력 적분 뒤 속도(최대 낙하 574 클램프).
    package static func nextVelocity(_ vy: CGFloat, dt: TimeInterval) -> CGFloat {
        min(vy + gravity * CGFloat(dt), maxFallSpeed)
    }

    /// AABB — 히트박스가 그 시각의 위 기둥 또는 아래 기둥과 겹치면 충돌.
    /// `time` 은 움직이는 기둥의 틈 위치를 정한다(그림과 같은 함수를 쓴다).
    package static func collides(bird: CGRect, pipe: Pipe, height: CGFloat, time: TimeInterval) -> Bool {
        bird.intersects(pipe.topRect(at: time)) || bird.intersects(pipe.bottomRect(at: time, height: height))
    }

    /// 새 기둥. 틈 중심은 위·아래 여백 `centerMargin` 을 두고 뽑는다(바닥 띠가 없으므로 아래도 같은 값).
    ///
    /// 점수 15 이상이면 30% 로 '튀는 기둥'이 된다. 난수 소비 순서(기준선 → 판정 → 지연 → 방향)는 결정론의 일부다 —
    /// 15점 미만에서는 `&&` 단락 평가로 판정 난수를 아예 쓰지 않아 초반 판이 종전과 같은 모양으로 남는다.
    /// 방향은 여백 안에 들어가는 쪽으로만 고르고, 양쪽 다 안 되면 고정 기둥으로 강등한다(틈이 화면 밖으로 새지 않게).
    package static func makePipe(x: CGFloat, score: Int, rng: inout MiniGameRandom) -> Pipe {
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
    package mutating func flap() {
        switch phase {
        case .ready, .result:
            startRound()
            bird.vy = Self.flapVelocity
        case .running:
            bird.vy = Self.flapVelocity
        case .over:
            return      // 유예 중 클릭은 아무 일도 아니다 — 여기서 빠져나가지 않으면 죽은 뒤에 발밑 파편이 튄다
        }
        // 그림용 기록. 점프가 **실제로** 일어난 경우에만 갱신한다.
        lastFlapAt = elapsed
        flapCount += 1
    }

    /// 허브가 판을 끊을 때(창 닫힘·포커스 상실·게임 전환). 진행 중이면 그 점수로 결과 확정 — 점수는 유효하다.
    package mutating func interrupt() {
        switch phase {
        case .running, .over:
            phase = .result
            flashRemaining = 0
        case .ready, .result:
            break
        }
    }

    package mutating func step(dt rawDt: TimeInterval) {
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
        for i in pipes.indices {
            pipes[i].x -= speed * CGFloat(dt)
            // 화면 오른쪽 끝에 들어온 순간 '튈 시각'을 확정한다(화면 밖에서 미리 튀면 서프라이즈가 아니다).
            if let delay = pipes[i].shiftDelay, pipes[i].shiftAt == nil, pipes[i].x <= Self.width {
                pipes[i].shiftAt = elapsed + delay
            }
            if !pipes[i].passed, bird.x > pipes[i].x + Self.pipeWidth {
                pipes[i].passed = true
                score += 1
                // 그림용: "+1" 이 **지나온 그 기둥의 틈**에서 뜬다.
                lastScoreAt = elapsed
                lastScorePipeCenter = pipes[i].center(at: elapsed)
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
        scrolled = 0
        lastFlapAt = nil
        flapCount = 0
        lastScoreAt = nil
        lastScorePipeCenter = nil
        let gapToNext = Self.spacing(forScore: 0)
        pipes = (0..<Self.pipeCount).map { i in
            Self.makePipe(x: Self.firstPipeX + CGFloat(i) * gapToNext, score: 0, rng: &rng)
        }
        phase = .running
    }
}
