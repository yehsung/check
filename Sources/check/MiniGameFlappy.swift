import AppKit
import SwiftUI

// MARK: - 플래피 아잉 (v0.2.46 규칙 · v0.2.51 그림)
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
// ── v0.2.51 그림 되돌리기 ─ **여기가 이 파일에서 가장 중요한 주석이다** ───────────────────
// 사용자 지시 2026-09-11(원문): "여전히 뭔가 화면 끊기는 느낌이 들어. 그냥 잔상 없애줘. 맨처음 게임 만들었을때
// 기준으로 캐릭터 옆으로 돌린거랑 점프할때 밑에 거품같은거 생기는거. 그리고 각 기둥 지나갈때 +1 되는거.
// 그리고 뒤 배경. 이거 4개만 유지하고 나머지 다 초기로 돌려줘."
//
// 즉 v0.2.48~50 에서 얹은 그림은 **네 가지와 기둥만 남기고 전부 v0.2.46(커밋 06d8566) 상태로** 돌아갔다.
//   남긴 넷: ① 오른쪽을 보는 옆모습(`FlappyMascot(facing:)` → `MiniGameMascot.sideProfile`)
//            ② 점프할 때 발밑 흰 파편(`MiniGameEffects.sparks` 호출 하나)
//            ③ 기둥을 지날 때 뜨는 "+1"(`MiniGameScorePop` · `lastScoreAt` · `lastScorePipeCenter`)
//            ④ 뒤 배경(`MiniGameBackdrop` + 점수에 따른 `MiniGameStage` 진행 — 경계 0·6·13·22·34 불변)
//   + 기둥:  ⑤ v0.2.50 의 기둥 그리기 그대로(세로 그라디언트 · 입구 립 · 립 경계선 · 1.5pt 외곽선). 같은 날
//            사용자 추가 지시로 붙었다(원문: "4번 관련해서 기둥도 변경한거 그대로 유지해도 될듯. 까먹고 말하는거에
//            포함 못시킨거야. 기둥은 버벅임에 영향 없어"). **"초기로"에 기둥을 넣지 마라** — 이 판 초안이 단색 +
//            1pt 로 단순화했다가 되돌렸다(근거는 draw 의 기둥 주석).
//   지운 것: 잔상 8겹(규칙의 `trail` 이력까지) · 스쿼시&스트레치 · 점프 흰 플래시 · 바닥 그림자 타원 ·
//            무대 전환 플레어 · 득점 링 · 죽음 파편/회전/낙하 · ready 부유 · 점수 펀치 · 무대 점 5개 ·
//            무대 이름 배너 · 기본 기울기 −6° · 캐릭터 림/명암.
//
// **다시 넣지 마라.** 이 목록은 "아직 안 만든 것"이 아니라 **사용자가 보고 물린 것**이다. 부족해 보이면
// 새 도형을 더하지 말고 남은 것의 **값만** 조여라 — 여기서 도형을 더한 시도는 v0.2.48·49·50 세 번 전부
// 다음 릴리스에서 거부당했다.
//
// **왜 성능 이야기가 여기 붙어 있나.** 사용자가 말한 "끊기는 느낌"이 이 작업의 시작이다. v0.2.50 에서 프레임
// 상한을 주사율의 약수로 맞춰 드롭률이 25%→2.6% 로 떨어졌는데도 체감이 남았고, 남은 유력 원인이 잔상이었다:
// 매 프레임 `FlappyMascot` SwiftUI 뷰를 **최대 8장 더** 만들고 각각에 scale·rotation·opacity·mask 를 걸었다.
// 헤드리스 실측(2026-09-11, 30프레임을 날고 3프레임 전에 친 — 잔상이 차 있고 파편이 한창인 — 같은 프레임을
// ImageRenderer 로 120회 렌더한 p50): 되돌리기 전 1.84~1.97ms · 되돌린 뒤 1.45~1.52ms.
//   같은 코드인데도 기계 부하로 절대 p50 이 실행마다 1.9~6.0ms 까지 흔들렸으므로, **손대지 않은 타이밍 바
//   렌더를 같은 루프에서 번갈아 재서** 그 비로 비교했다: flappy/타이밍바 = 0.775~0.785(4회) → 0.602~0.621(3회).
//   프레임당 그리기 비용 약 21% 감소.
// (이 수치는 CPU 쪽 레이아웃·래스터 비용이다. 화면 합성기의 겹 합성은 헤드리스로 못 잰다 —
//  실기기 60초 드롭률 측정은 병합 뒤에 한다.)
// 기둥을 v0.2.50 그대로 되살린 뒤 다시 쟀다(2026-09-11, 같은 기계에서 연달아 · ImageRenderer.cgImage 120회 p50 을
// 타이밍 바 렌더와 번갈아 5회전): 41d266a 1.02~1.04ms(타이밍바 대비 2.46~2.55) → 기둥 복원판 0.24~0.28ms(0.60~0.69,
// 두 번 실행) · 기둥을 단순화했던 초안 0.26~0.27ms(0.63~0.67). 기둥 복원판과 단순화 초안의 차이는 잡음 안이고,
// 같은 판에서 기둥이 화면에 있는 프레임(90프레임째)과 없는 프레임(30프레임째)도 차이가 잡음 안이다 —
// **기둥 모양은 프레임 비용을 바꾸지 않는다**(사용자 판단 "기둥은 버벅임에 영향 없어"와 같은 결론).
// 이 벤치는 위 21% 와 재는 코드·프레임이 달라 절대값·비를 서로 견주면 안 된다 — 한 벤치 안의 전/후끼리만 비교해라.


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
    private(set) var scrolled: CGFloat
    /// 마지막 점프의 판 시각. 뷰가 `elapsed - lastFlapAt` 으로 발밑 파편의 진행도를 만든다.
    private(set) var lastFlapAt: TimeInterval?
    /// 점프 횟수. 파편의 시드다 — 같은 점프면 같은 파편이 나온다(프레임마다 새로 뽑으면 파편이 끓는다).
    private(set) var flapCount: Int
    /// 마지막 득점의 판 시각.
    private(set) var lastScoreAt: TimeInterval?
    /// 그때 지나온 기둥의 틈 중심 y — "+1" 이 뜨는 자리(화면 한가운데면 무엇 때문에 점수가 났는지 안 보인다).
    private(set) var lastScorePipeCenter: CGFloat?

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
    }

    /// 테스트 픽스처 — 임의 상태에서 시작한다(난수는 seed).
    /// 그림 전용 인자는 전부 기본값이 있다: 예전 픽스처가 그대로 컴파일돼야 규칙 테스트가 흔들리지 않는다.
    init(seed: UInt64, bird: Bird, pipes: [Pipe], score: Int, phase: Phase, elapsed: TimeInterval = 0,
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

    static func == (lhs: FlappyGame, rhs: FlappyGame) -> Bool {
        lhs.bird == rhs.bird && lhs.pipes == rhs.pipes && lhs.score == rhs.score
            && lhs.phase == rhs.phase && lhs.flashRemaining == rhs.flashRemaining && lhs.elapsed == rhs.elapsed
            && lhs.scrolled == rhs.scrolled && lhs.lastFlapAt == rhs.lastFlapAt && lhs.flapCount == rhs.flapCount
            && lhs.lastScoreAt == rhs.lastScoreAt && lhs.lastScorePipeCenter == rhs.lastScorePipeCenter
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
            return      // 유예 중 클릭은 아무 일도 아니다 — 여기서 빠져나가지 않으면 죽은 뒤에 발밑 파편이 튄다
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

// MARK: - 그림 전용 상수

/// 남은 그림 장치의 길이·크기. **난이도와 무관**하다 — 여기 값을 아무리 흔들어도 속도·틈·충돌은 그대로다.
/// 규칙 상수(`FlappyGame.*`)와 한 덩어리로 두지 않는 이유가 그것이다: 그림을 튜닝하다 난이도를 건드리는 사고를 막는다.
///
/// v0.2.51 에서 이 열거형은 **절반 아래로 줄었다**(스쿼시·플래시·링·펀치·배너·플레어·잔상·그림자·죽음 연출·
/// 부유·기본 기울기·림/명암 상수가 전부 나갔다). 기둥 입구 립(`lip`)만은 남는다 — 기둥은 v0.2.50 그대로 두라는
/// 추가 지시(2026-09-11)라 "지운 것"이 아니다. 죽은 상수를 "원래 있던 것"으로 남겨 두면 다음 사람이
/// 되살리므로 값까지 통째로 지운 것이다 — 되살리려면 사용자에게 다시 물어야 한다(2026-09-11 지시).
private enum FlappyFX {
    // ── 시간(초) ───────────────────────────────────────────────────────────────────────
    /// 점프 파편이 사는 시간. 점프의 증거는 이제 **이것 하나뿐**이라 짧으면 점프가 안 보인다.
    static let flapSpark: TimeInterval = 0.35
    /// "+1" 이 화면에 머무는 시간.
    static let scorePopHold: TimeInterval = 0.60

    // ── 각도(°) ────────────────────────────────────────────────────────────────────────
    /// 낙하 속도에 비례한 기울기 범위. **0 이 기준**이다 — v0.2.48~50 의 기본 기울기(−6°)는 걷어냈다.
    /// 원형에 가까운 34pt 실루엣에서 −6° 는 눈으로 판별되지 않았고(2026-09-10 실측), 방향은 이미
    /// 돌아선 얼굴(`MiniGameMascot.sideProfile`)이 말한다.
    static let tiltRange: ClosedRange<Double> = -20...25

    // ── 크기(논리 pt · 비율) ───────────────────────────────────────────────────────────
    /// 기둥 입구 립의 두께. **반드시 기둥 사각형 안쪽으로만** 그린다 —
    /// 밖으로 1pt 라도 나가면 그리는 사각형 ≠ 충돌 사각형이 되어 "안 닿았는데 죽었다"가 된다.
    static let lip: CGFloat = 10
    /// 상단 점수의 세로 중심(논리 pt). 가운데 큰 숫자 하나 — v0.2.46 의 자리 그대로다.
    static let scoreY: CGFloat = 26
    /// "+1" 이 뜨는 x 오프셋(캐릭터 뒤로 이만큼). 득점 순간 방금 지난 기둥의 **뒷면**이 캐릭터에 닿아 있다.
    /// 한 기둥 폭(44)을 통째로 물리면 표시가 왼쪽 허공에 뜨고(2026-09-10 지적), 0 이면 글씨가 얼굴을 덮는다.
    static let scorePopBack: CGFloat = FlappyGame.pipeWidth * 0.75
    /// 점프 파편이 퍼지는 반경과 점 하나의 반지름.
    ///
    /// 30 · 3.5 였다(v0.2.48~49). 색을 흰색으로 올린 순간 그 조합이 **한 덩어리**로 드러났다: 친 지 세
    /// 프레임(0.05초)에 퍼짐 반경은 4.4~8.0pt 인데 점 반지름이 3.0pt 라 열 점이 서로 붙어, 몸 아래로
    /// 늘어지는 **흰 다리 하나**로 읽혔다(flapfx-jump-zoom.png 첫 판, 2026-09-10). 갈색일 때는 옅어서
    /// 안 보이던 결함이다 — 색만 바꾸고 끝냈으면 "이번엔 다리가 생겼다"가 세 번째 거부가 됐다.
    /// 그래서 **점은 작게(2.0) 퍼짐은 넓게(44)** 로 비를 뒤집었다: 같은 프레임에서 퍼짐 8.4~15.1pt 대
    /// 점 지름 3.2pt 라 열 개가 각각 갈린다("밑에 거품처럼 뜨는 거" — 사용자 자신의 표현).
    /// 44 는 위로도 새지 않는다: 위쪽 최대 도달이 발밑(+17.7)에서 −28 = 몸 중심 위 10pt 라 기둥 틈까지
    /// 올라가지 않는다(테스트가 캐릭터 위 45pt 밖을 0 으로 못 박는다).
    /// **두 값은 두 번 고쳐서 여기까지 왔다 — v0.2.51 로 옮길 때 값을 그대로 옮겼다.**
    static let flapSparkRadius: CGFloat = 44
    static let flapSparkDot: CGFloat = 2.0
    /// 점프 파편이 뿌려지는 각도 범위(0 = 앞 · π/2 = 아래 · π = 뒤). **아래·뒤로만** 밀어낸다 —
    /// 온 사방으로 뿌리면 "밟고 올라갔다"가 아니라 "터졌다"로 읽힌다.
    static let flapSparkAngles: ClosedRange<Double> = (0.28 * .pi)...(1.22 * .pi)
    /// 점프 파편의 색과 세기. **무대와 무관한 흰색**이다.
    ///
    /// 왜 무대색이 아닌가: 예전엔 `stage.glow` 였다. 새벽(255,196,138)·노을(255,209,122) 의 glow 를 어두운
    /// 하늘 위에 반투명으로 얹으면 발밑 점 열 개가 **갈색**으로 읽힌다("지금 갈색 안 어울려", 2026-09-10).
    /// 게다가 무대마다 색이 갈려서 같은 동작이 다섯 가지 뜻으로 보였다 — 점프는 배경이 무엇이든 같은 사건이다.
    /// 흰색은 하늘 다섯이 전부 어두운 쪽(휘도 50~98/255)이라 어디서든 뜨고, 캐릭터 몸통(연보라 169/255)보다도
    /// 밝아 만에 하나 겹쳐도 파편 쪽이 위로 뜬다.
    ///
    /// 세기 0.82 인 이유(실측 2026-09-10): 열 점은 친 직후 두세 프레임 동안 아직 발밑 한자리에 겹쳐 있다.
    /// 1.0 이면 그때 점 하나만으로도 핵이 236/255 라 **불투명한 흰 덩어리**가 몸 아래에 붙어 다리처럼 읽힌다
    /// (사용자가 두 번 거부한 것이 정확히 "점프에 붙은 도형"이다). 0.82 면 한 점의 핵이 202 라 뒤 하늘이
    /// 비쳐 공기 방울로 읽히고, 겹친 자리만 238 까지 올라 무리의 중심이 생긴다.
    /// 더 내리면 한낮 하늘(휘도 98)에서 대비가 2:1 아래로 떨어져 가장자리 점이 묻힌다(무대 5종 실측:
    /// 배경 대비 1.9~3.2:1 · 점 핵 250~252 대 몸통 169). 몸통은 v0.2.50 에 186 으로 적혀 있었는데, 몸에 얹던
    /// 흰 플래시를 뺀 뒤(v0.2.51) 같은 자리를 재니 169 였다 — 차이 17 은 그 자리의 플래시 상승분(+19)과 맞는다.
    ///
    /// 파편은 `Canvas`(draw) 에, 몸은 그 **위** 겹(`spriteAndScore`)에 있어 몸 안쪽으로 들어간 점은 아예
    /// 가려진다. 그래서 화면에 남는 흰 것은 언제나 "몸 **밖** 발밑의 점"뿐이다 — 레이어 순서를 뒤집으면
    /// 점이 얼굴 위로 올라온다.
    static let flapSparkColor = Color.white.opacity(0.82)
}

// MARK: - 잎 뷰

/// 플래피 아잉 캔버스. 부모가 준 프레임을 채우고, 규칙은 `FlappyGame` 에 맡긴다.
///
/// 프레임 루프는 `TimelineView(.animation(paused:))` 하나뿐이다 — 진행 중(running·over 유예)일 때만 돌고, ready/result
/// 와 허브의 interrupt·일시정지 뒤엔 멈춘다(유휴 0%). 틱은 TimelineView 의 날짜가 바뀔 때(`onChange`)만 일어나므로
/// body 평가 도중 상태를 바꾸지 않는다.
///
/// ⚠️ **여기에 SwiftUI 반복 애니메이션(`repeatForever`)을 넣지 마라.** v0.2.48 의 시작 화면 부유가 그것이었고,
/// `repeatForever` 는 값만 내려서는 안 멈춰 창을 닫아도 최소화해도 컴포지터가 코어의 3~5% 를 계속 태웠다
/// (2026-09-10 실측). v0.2.51 에서 그 부유를 지우면서 이 뷰에는 프레임 루프 하나만 남았다 —
/// 정지 상태(ready/result)에서 스스로 도는 것은 이제 아무것도 없다.
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
        // 일시정지(v0.2.48): 허브가 얼리면 프레임이 아예 돌지 않는다. 정지 화면(스크림·카드)은 허브가 그린다 —
        // 여기서 또 그리면 두 벌이 되어 언젠가 갈린다.
        // 프레임 상한은 **화면 주사율에서 온다**(v0.2.50). 여기 숫자를 적지 마라 — 1/60 을 박아 두면
        // 75Hz·144Hz 처럼 60 으로 나눠떨어지지 않는 화면에서 네 프레임에 한 장이 두 배로 늘어진다
        // (근거·표는 `MiniGameFrameRate`). 값이 바뀌면 이 뷰가 다시 만들어지며 스케줄도 다시 잡힌다.
        TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval(forRefreshRate: host.refreshHz),
                                paused: !game.isPlaying || host.isPaused)) { context in
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

    /// 겹은 다섯뿐이다: 캔버스(배경 → 기둥 → 발밑 파편) · 스프라이트와 점수 · "+1" · 게임오버 붉은 플래시 · 카드.
    /// **여기에 겹을 더하지 마라** — v0.2.48~50 이 얹은 잔상·그림자·링·플레어·배너를 사용자가 물렸다(2026-09-11).
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

        // 1) 배경(남긴 넷 중 ④) — 논리 사각형이 아니라 **캔버스 전체**를 덮는다. 레터박스 여백(±0.5pt)까지
        //    하늘이어야 판이 액자 속 그림처럼 보이지 않는다.
        MiniGameBackdrop.draw(into: &context, rect: full, stage: stage, scroll: game.scrolled,
                              terrain: true, reduceMotion: host.reduceMotion)

        // 2) 기둥 — **v0.2.50 의 그리기 그대로다. 한 줄도 바꾸지 마라.** 사각으로 그려 끝이 캔버스 가장자리에
        //    딱 붙는다(모서리를 둥글리면 천장·바닥에 틈이 생겨 "떠 있는 막대"로 보인다 — 그 지적이 이 판의 이유다).
        //
        //    ★ 기둥은 "맨처음 기준으로" 목록에 **없다**. 사용자 추가 지시(2026-09-11) 원문: "4번 관련해서 기둥도
        //      변경한거 그대로 유지해도 될듯. 까먹고 말하는거에 포함 못시킨거야. 기둥은 버벅임에 영향 없어".
        //      v0.2.51 초안이 이 자리를 단색 채움 + 1pt 외곽선으로 단순화했다가 그 지시로 되돌렸다.
        //      **다시 단순화하지 마라** — 사용자가 유지하라고 한 모양이고, 기둥은 프레임당 도형 몇 개라 60Hz 예산에서
        //      비용이 사실상 0이다(끊김의 원인이 아니다). 외곽선을 1pt 로 줄이면 밤·오로라에서 어두운 본체가 하늘에
        //      묻힌다(아래 외곽선 주석 — v0.2.50 에 그래서 1.5pt 가 됐다).
        //    ★ 채움 그라디언트는 **캔버스 세로 전체**를 기준으로 잡는다. 기둥 사각형마다 따로 잡으면 같은 y 라도
        //      기둥 길이에 따라 색이 달라져, 틈이 튄 기둥과 고정 기둥이 다르게 보인다 — 색으로 미리 알려 주지
        //      않기로 한 결정(사용자, 2026-09-08)이 그 자리에서 깨진다.
        //    ★ 튀는 기둥 분기는 여기 없다. 그림이 `isShifting`·`shiftAt` 을 읽는 순간 같은 결정이 깨진다.
        //    ★ 본체는 **어두운 대역**(structureDeep → structureDeepLit)이다. 예전엔 structure → structureEdge
        //      라 한낮 기둥과 캐릭터의 휘도비가 1.01:1 이었고, 겹치는 순간 플레이어가 통째로 사라졌다
        //      (2026-09-10 5개 무대 실측). 캐릭터 림을 뺀 v0.2.51 에서도 무대 5종 전부에서 캐릭터가 기둥보다
        //      4.18:1 이상 밝다(2026-09-11 실측 — 무대별 수치는 `theCharacterStaysReadableOnEveryStageWithNoRim`).
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

        // 3) 점프 임팩트(남긴 넷 중 ②) — **발밑에서 아래·뒤로 밀리는 흰 파편 하나뿐**이다.
        //
        //    ★ 여기에 도형을 더하지 마라. 세 번 거부당한 자리다:
        //      v0.2.48 `MiniGameEffects.arch` — 발밑에서 아래로 퍼지는 넓은 U("밑에 넓은 U 같은 거 안 어울려").
        //      v0.2.49 `wingBeat` — 어깨 밖에서 머리 위로 훑는 ∩ 한 쌍("양옆으로 U자 거꾸로 2개 별로야").
        //      v0.2.49~50 의 스쿼시&스트레치와 몸 아래쪽 흰 플래시도 2026-09-11 "맨처음 기준"에서 함께 빠졌다.
        //      링·속도선·먼지 퍼프·날개도 실제로 그려 보고 같은 이유로 버렸다 — **새 도형이 아니라 값이 답이다.**
        //
        //    파편만 남은 이유: 아래·뒤로 밀려나는 점들은 "밟고 올라갔다"라 몸이 솟는 방향과 어긋나지 않고,
        //    점 열 개는 34pt 캐릭터 옆에서 어떤 글자로도 읽히지 않는다(사용자 표현: "밑에 거품같은거").
        if !host.reduceMotion, game.phase == .running, let at = game.lastFlapAt {
            let foot = t.point(game.bird.x + FlappyGame.spriteSize * 0.08,
                               game.bird.y + FlappyGame.spriteSize * 0.52)
            MiniGameEffects.sparks(into: &context, center: foot,
                                   progress: (game.elapsed - at) / FlappyFX.flapSpark,
                                   count: 10, maxRadius: FlappyFX.flapSparkRadius * t.scale,
                                   color: FlappyFX.flapSparkColor, seed: UInt64(game.flapCount),
                                   dotRadius: FlappyFX.flapSparkDot,
                                   angles: FlappyFX.flapSparkAngles)
        }
    }

    /// "+1" 이 뜨는 논리 x. 득점 순간 방금 지나온 기둥의 **뒷면**이 캐릭터에 닿아 있으므로,
    /// 캐릭터 바로 뒤(기둥 폭의 3/4)에 두면 "저 기둥을 통과해서 받았다"가 보인다.
    private static let scorePopX = FlappyGame.birdX - FlappyFX.scorePopBack

    /// 스프라이트(아잉)와 상단 점수. 위치는 논리 좌표를 실제 크기로 옮겨 놓는다.
    /// v0.2.46 의 골격 그대로다 — 스프라이트 **한 장**과 가운데 큰 숫자 **하나**.
    private var spriteAndScore: some View {
        GeometryReader { geo in
            let t = MiniGameCanvas.transform(in: geo.size, logicalSize: FlappyGame.logicalSize)
            let side = FlappyGame.spriteSize * t.scale
            // 방향(남긴 넷 중 ①)은 **동작 줄이기와 무관하다** — 얼굴이 어느 쪽을 보는지는 애니메이션이 아니라
            // 정체다. 여기를 `!host.reduceMotion` 으로 바꾸지 마라(v0.2.49 가 그렇게 써서 동작 줄이기에서만
            // 얹는 명암이 갈렸다). 게임오버 표정은 3D 에 없어 자동으로 정면 PNG 로 내려간다.
            FlappyMascot(mood: game.isGameOver ? .negative : .neutral, facing: true)
                .frame(width: side, height: side)
                .rotationEffect(.degrees(spriteAngle))
                .position(x: t.origin.x + game.bird.x * t.scale, y: t.origin.y + game.bird.y * t.scale)
            if showsTopScore {
                Text("\(game.score)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.primaryText)
                    // 그림자 두 겹은 **장식이 아니라 가독성**이라 남긴다(v0.2.46 은 검은 판이라 필요 없었다).
                    // 좁은 그림자는 획을 또렷하게, 넓은 그림자는 밝은 하늘·능선 위에서 글자를 띄운다.
                    .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                    .shadow(color: .black.opacity(0.40), radius: 7)
                    .position(x: t.origin.x + FlappyGame.width / 2 * t.scale,
                              y: t.origin.y + FlappyFX.scoreY * t.scale)
            }
        }
        .allowsHitTesting(false)
    }

    /// 득점 순간 그 자리에 떠오르는 "+1"(남긴 넷 중 ③). 점수를 id 로 물려 매 득점마다 처음부터 다시 등장한다.
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

    /// 낙하 속도에 비례해 기운다(위로 −20°, 아래로 +25°). 동작 줄이기면 0.
    private var spriteAngle: Double {
        guard !host.reduceMotion else { return 0 }
        let raw = Double(game.bird.vy / FlappyGame.maxFallSpeed) * FlappyFX.tiltRange.upperBound
        return min(FlappyFX.tiltRange.upperBound, max(FlappyFX.tiltRange.lowerBound, raw))
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

/// 진행 방향(오른쪽)을 **얼굴로** 말하는 캐릭터 한 장(남긴 넷 중 ①).
///
/// **왜 이렇게 됐는가.** 아잉 PNG 는 눈·입·볼터치가 몸통 중심에 대해 완전히 대칭인 **정면 얼굴**이라
/// 좌우 반전도 회전도 방향을 만들지 못한다. v0.2.48 은 그래서 얹는 장치 넷(어두운 림 · 뒤통수 그늘 ·
/// 앞쪽 반사광 · 뒤로 흐르는 목도리)으로 방향'감'을 지어냈다. 사용자 판정은 그걸로 부족했다
/// (2026-09-10: "캐릭터가 오른쪽을 바라보고 있게끔. 드래그로 이동시키면 오른쪽 바라보는 거 되어 있잖아").
/// v0.2.49 는 **얼굴을 진짜로 돌린다** — 오버레이가 쓰는 그 3D 모델을 오버레이가 쓰는 그 각도로 돌려 구운
/// 스프라이트(`MiniGameMascot.sideProfile()`)를 PNG 자리에 끼운다. 사용자가 2026-09-11 에
/// "캐릭터 옆으로 돌린거"로 남기라고 지목한 것이 이 경로다.
///
/// **얹는 장치는 전부 뺐다**(v0.2.51). 어두운 림 · 뒤통수 그늘 · 앞쪽 반사광 · 점프 흰 플래시 · 잔상 실루엣이
/// 여기 있었다. 그냥 뺀 것이 아니라, 빼고 나서 5개 무대 × (하늘 위 · 기둥 위) 열 조합에서 캐릭터와 배경의
/// 휘도비(WCAG)를 실측했다(2026-09-11) — 하늘 위 3.55~7.24:1 · 기둥 위 4.18~7.38:1(기둥은 v0.2.50 그라디언트·립 그대로), **최솟값 3.55:1**(한낮 하늘 위)이라
/// 문턱 2.0:1 을 넉넉히 넘는다. 즉 림 없이도 실루엣이 배경에서 떨어진다.
/// 되살리려면 그 열 조합을 다시 재서 2.0:1 을 깨는 자리를 보여라(자·숫자는 플래피 테스트의 무대 대비 검사에).
/// 목도리는 v0.2.49 에 이미 뺐다: 좌표가 정면 PNG 알파에 맞춰 잰 값이라 돌아선 몸통에서는 띠가 몸을
/// 가로지르는 **붉은 칼자국**으로 읽혔다.
///
/// **판정 기준**은 그대로다: 스냅샷을 좌우 반전했을 때 다르게 보여야 한다.
private struct FlappyMascot: View {
    let mood: CheckMascotAssets.Mood
    /// 돌아선 옆모습(구운 3D 한 장)을 쓸지. false 면 정면 PNG 로 내려간다.
    /// `.negative`(게임오버 시무룩)는 3D 에 표정이 없어 어차피 정면 PNG 로 내려간다.
    var facing: Bool = true

    var body: some View {
        // 옆모습 조회는 **한 번만** 한다(캐시된 NSImage 조회지만, 그림을 가르는 값이라 한 곳에서 읽는다).
        let source = (facing ? MiniGameMascot.sideProfile(mood: mood) : nil)
            ?? CheckMascotAssets.image(for: mood)
        // 공유 캐시 원본이다 — size 를 바꾸거나 lockFocus 로 그리면 메뉴바·헤더까지 오염된다. SwiftUI 축소만.
        // 3D 옆모습이든 PNG 든 **같은 192px 정사각**이라 축소 규약이 하나로 유지된다.
        if let source {
            Image(nsImage: source)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Circle().fill(CheckTheme.working)
        }
    }
}
