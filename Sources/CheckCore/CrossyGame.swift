import Foundation

// MARK: - 길건너 아잉이 (v0.3.67) — 규칙
//
// 미니게임 넷째. 크로시 로드식 — 한 번 누를 때마다 한 칸씩 뛰어 앞으로 간다(사용자 결정 2026-10-27, 설계서 §0).
// 규칙은 이 값 타입(뷰·스토어·시계·SceneKit 의존 0)에, 그림은 맥 `MiniGameCrossy.swift`(SceneKit)에 있다.
// **렌더러는 이 값만 읽는다** — 줄 목록 · 물체 위치 · 아잉이 칸/위치 · 뛰기 진행 · 죽음 사유. 폰이 다음 판에 이 파일을
// 그대로 쓴다(그래서 CheckCore 다).
//
// ── 판 ────────────────────────────────────────────────────────────────────────────────────
// 가로 9칸(놀이 칸 0…8, 가운데 4)이고 줄은 앞으로 끝없이 생긴다. 줄 번호는 시작 줄이 0, 앞이 +.
// 칸 c 의 중심이 x = c 다(칸은 c−0.5…c+0.5). 놀이 칸 밖(x < −0.5 · x > 8.5)은 그림이 어둡게 칠하는 경계다.
// 줄 종류는 넷이다:
//   · 풀밭 — 나무·바위가 칸을 막는다(못 들어간다 → 제자리 통통). 시작 몇 줄은 풀밭이다.
//   · 찻길 — 줄마다 방향·속도. 승용차 1.4칸 · 트럭 2.4칸. 차에 닿으면 끝(납작).
//   · 강   — 통나무(2~4칸)가 흐른다. 통나무 위면 같이 떠내려간다. 물에 빠지면 끝, 실려서 놀이 칸 밖으로 나가면 끝.
//   · 기찻길 — 가끔 기차(놀이 칸보다 긴 14칸, 초당 24칸). 오기 **1초 전**부터 경고등이 깜빡인다. 닿으면 끝.
//
// ── 시간 하한(서버 계약 — 설계서 §1) ──────────────────────────────────────────────────────
// 앞으로 한 칸 = 뛰기 한 번 = `hopSeconds`(0.12초). 뛰는 중 입력은 **한 칸만** 줄 서고, 줄 선 입력은 앞 뛰기가
// **끝난 순간** 시작한다(남은 dt 를 이어 받는다 — 판 시계로 정확히 이어 붙는다). 점수는 **착지**에서 오른다.
// 그래서 점수 s 에 닿는 판 시계는 언제나 s × hopSeconds 이상이고, 판 시계는 벽시계를 넘지 못한다(dt 는 실 dt 를
// `maxStep` 에서 자른 값이다). 서버 `minigame_min_seconds('crossy', s)` = s × 0.09 = s × hopSeconds × 0.75
// (입력 연타 여유 25%). **이 상수를 바꾸면 서버 식도 같이 바꿔야 한다** — 계약 시험(V0367CrossyTests)이 묶는다.
//
// ── 멈춤 벌칙 ────────────────────────────────────────────────────────────────────────────
// 카메라(`cameraRow`)가 아잉이를 따라붙고, 안 움직여도 천천히 앞으로 간다(`creepSpeed`). 아잉이가 카메라보다
// `behindRows` 줄 넘게 뒤처지면 화면 아래로 밀려난 것이다 → 끝("놓쳤어요"). 가장 앞 줄을 `idleLimit` 초 동안 못
// 넘겨도 같은 결말이다. 둘 다 사유는 `.leftBehind` 하나다(설계서 §3.1 "같은 결말").
//
// ── 결정성 ───────────────────────────────────────────────────────────────────────────────
// 줄은 시드 고정 난수 하나(`generator`)로 **순서대로만** 만든다 — 같은 시드면 판을 어떻게 하든 같은 줄 번호에
// 같은 줄이 선다(기차 간격은 줄마다 따로 든 난수가 굴린다 — 놀이 방식이 줄 모양을 흔들지 않게).

package struct CrossyGame: Equatable, Sendable {
    // MARK: 상수

    /// 놀이 칸 수(가로). 칸 번호 0…8.
    package static let columns = 9
    /// 시작 칸(가운데).
    package static let startColumn = 4
    /// **뛰기 한 번의 시간(초).** 서버 시간 하한의 재료다(머리 주석) — 바꾸면 `minigame_min_seconds('crossy')` 도 같이.
    package static let hopSeconds: TimeInterval = 0.12
    /// 서버 시간 하한이 이 상수에 거는 배수(입력 연타 여유 25%). 서버 식 `s × 0.09` 의 0.09 = hopSeconds × 이 값.
    package static let serverTimeMarginFactor = 0.75
    /// 한 판 최대 점수(= `MiniGameKind.crossy.maxScore` = 서버 `minigame_score_cap('crossy')`).
    package static let maxScore = MiniGameKind.crossy.maxScore
    /// 한 번에 흘리는 최대 시간 — 창이 잠깐 멈췄다 돌아와도 차가 순간이동해 아잉이를 건너뛰지 않게.
    package static let maxStep: TimeInterval = 1.0 / 30.0
    /// 죽은 뒤 결과 카드가 뜨기까지(죽음 연출 시간). 이 동안 클릭은 무시된다(죽자마자 새 판이 되지 않게).
    package static let deathHold: TimeInterval = 1.1
    /// 아잉이 충돌 반폭(칸). 몸 그림(약 0.8칸)보다 좁다 — 스친 것까지 죽이면 "안 닿았는데"가 된다.
    package static let playerHalfWidth = 0.3
    /// 통나무 끝 너그러움(칸). 통나무 끝에서 이만큼 벗어나 착지해도 탄다.
    package static let logGrace = 0.2
    /// 승용차 · 트럭 길이(칸). 시안 B 의 상자 차 비율 그대로 — 그리는 길이 = 충돌 길이다.
    package static let carLength = 1.4
    package static let truckLength = 2.4
    /// 물체가 놀이 칸 밖으로 나가 이만큼 더 간 뒤 반대편에서 다시 들어온다(가장 긴 통나무 4칸보다 길어야 한다 —
    /// 짧으면 나가는 꼬리와 들어오는 머리가 겹쳐 보인다).
    package static let trackMargin = 5.0
    /// 경고등 시간(초) — 기차가 놀이 칸 끝에 닿기 전이 아니라 **나타나기** 1초 전부터다.
    package static let warnSeconds: TimeInterval = 1.0
    /// 기차 길이(칸) · 속도(칸/초). 놀이 칸(9)보다 길고, 9칸을 0.4초에 지나간다.
    package static let trainLength = 14.0
    package static let trainSpeed = 24.0
    /// 카메라보다 이만큼 뒤처지면 화면 아래로 밀려난 것이다.
    package static let behindRows = 2.5
    /// 가장 앞 줄을 이만큼 못 넘기면 놓친다(초).
    package static let idleLimit: TimeInterval = 9
    /// 카메라가 아잉이를 따라붙는 빠르기(1/초, 지수 접근).
    package static let followRate = 3.0
    /// 시작 풀밭(0…3 줄)과 뒤 숲 벽(−3 줄 이하 — 전부 막힘).
    package static let startGrassRows = 3
    package static let wallRow = -3
    /// 기찻길이 처음 나올 수 있는 줄 · 강이 처음 나올 수 있는 줄.
    package static let railStartRow = 14
    package static let riverStartRow = 6
    /// 난이도가 끝까지 오르는 줄 수(4 줄부터 254 줄까지 0 → 1).
    package static let difficultyRows = 250.0
    /// 들고 있는 줄 범위(카메라 뒤 · 가장 앞 줄 앞).
    package static let lanesBehind = 8
    package static let lanesAhead = 24

    package static var trackLeft: Double { -0.5 - trackMargin }
    package static var trackRight: Double { Double(columns) - 0.5 + trackMargin }
    package static var trackLength: Double { trackRight - trackLeft }
    /// 놀이 칸의 x 범위(칸 중심 기준 바깥 경계).
    package static let playMinX = -0.5
    package static var playMaxX: Double { Double(columns) - 0.5 }

    // MARK: 값 타입

    package enum Direction: String, Equatable, Sendable, CaseIterable {
        case forward, back, left, right

        /// 줄 변화(앞 +1).
        package var rowDelta: Int {
            switch self {
            case .forward: 1
            case .back: -1
            case .left, .right: 0
            }
        }

        /// 칸 변화(오른쪽 +1).
        package var columnDelta: Int {
            switch self {
            case .left: -1
            case .right: 1
            case .forward, .back: 0
            }
        }
    }

    package enum LaneKind: String, Equatable, Sendable, CaseIterable {
        case grass, road, river, rail
    }

    /// 풀밭의 막는 물건. 나무 높이(0…2)는 그림의 것이다 — 규칙은 "막힘" 하나만 본다.
    package enum Prop: Equatable, Sendable {
        case tree(height: Int)
        case rock
    }

    /// 움직이는 물체(차 · 트럭 · 통나무 · 기차). `x` 는 **왼쪽 끝**(칸 단위).
    package struct Mover: Equatable, Sendable {
        package var x: Double
        package var length: Double
        /// 그림용 갈래(차 색 · 트럭 여부 · 통나무 결). 규칙은 안 본다.
        package var variant: Int
        package var isTruck: Bool

        package init(x: Double, length: Double, variant: Int = 0, isTruck: Bool = false) {
            self.x = x
            self.length = length
            self.variant = variant
            self.isTruck = isTruck
        }

        package var maxX: Double { x + length }

        /// 가운데 `center`, 반폭 `halfWidth` 인 구간과 겹치는가(끝 너그러움 `grace` 만큼 안으로 좁혀 잰다).
        package func overlaps(center: Double, halfWidth: Double, grace: Double = 0) -> Bool {
            center + halfWidth > x + grace && center - halfWidth < maxX - grace
        }
    }

    /// 한 줄. 풀밭은 `props`, 찻길·강은 `movers`, 기찻길은 `train` · `trainCountdown` 을 쓴다.
    package struct Lane: Equatable, Sendable {
        package let row: Int
        package let kind: LaneKind
        /// 칸별 막는 물건(풀밭만, 길이 = columns). 다른 줄은 전부 nil.
        package var props: [Prop?]
        /// 흐름 방향(+1 오른쪽 · −1 왼쪽)과 빠르기(칸/초, 양수).
        package var direction: Int
        package var speed: Double
        package var movers: [Mover]
        /// 기찻길: 지금 지나가는 기차(없으면 nil) · 다음 기차까지 남은 초 · 기차 간격을 굴리는 난수.
        package var train: Mover?
        package var trainCountdown: TimeInterval
        package var trainRandom: CrossyRandom

        package init(row: Int, kind: LaneKind, props: [Prop?]? = nil, direction: Int = 1, speed: Double = 0,
                     movers: [Mover] = [], train: Mover? = nil, trainCountdown: TimeInterval = 0,
                     trainSeed: UInt64 = 0) {
            self.row = row
            self.kind = kind
            self.props = props ?? Array(repeating: nil, count: CrossyGame.columns)
            self.direction = direction
            self.speed = speed
            self.movers = movers
            self.train = train
            self.trainCountdown = trainCountdown
            self.trainRandom = CrossyRandom(seed: trainSeed)
        }

        /// 흐름 속도(칸/초, 방향 포함).
        package var velocity: Double { Double(direction) * speed }

        /// 그 칸이 막혔는가(풀밭의 나무·바위). 놀이 칸 밖도 막힘이다.
        package func isBlocked(column: Int) -> Bool {
            guard column >= 0, column < CrossyGame.columns else { return true }
            return kind == .grass && props[column] != nil
        }

        /// 경고등이 켜졌는가(기차가 나타나기 `warnSeconds` 전부터 지나갈 때까지).
        package var isTrainWarning: Bool {
            kind == .rail && (train != nil || trainCountdown <= CrossyGame.warnSeconds)
        }

        /// x 에 서 있는 아잉이를 태울 통나무(강만).
        package func log(under x: Double) -> Mover? {
            guard kind == .river else { return nil }
            return movers.first { x >= $0.x - CrossyGame.logGrace && x <= $0.maxX + CrossyGame.logGrace }
        }
    }

    /// 뛰기 한 번. `from`·`to` 는 (줄, x). 통나무에서 뛰면 출발 줄의 흐름이 두 끝을 같이 민다.
    package struct Hop: Equatable, Sendable {
        package var fromRow: Int
        package var fromX: Double
        package var toRow: Int
        package var toX: Double
        /// 착지 x 가 흐름을 따라 움직이는가(강으로 뛰는 경우 — 칸에 붙지 않는다).
        package var toFloats: Bool
        package var elapsed: TimeInterval
        package var direction: Direction
        /// 막힌 칸이라 제자리에서 통통 뛰었다(from == to).
        package var bumped: Bool
        /// 출발이 통나무 위였다(뛰는 동안 그 흐름을 탄다).
        package var fromRiding: Bool

        /// 0…1 진행.
        package var progress: Double { min(1, max(0, elapsed / CrossyGame.hopSeconds)) }
    }

    package struct Player: Equatable, Sendable {
        /// 지금 선(또는 마지막으로 착지한) 줄 · x(칸 단위, 통나무 위면 소수).
        package var row: Int
        package var x: Double
        /// 통나무를 타고 있다(강 줄에 서 있는 동안).
        package var riding: Bool
        /// 마지막으로 뛴 방향(그림이 몸을 그쪽으로 튼다).
        package var facing: Direction
    }

    package enum DeathCause: String, Equatable, Sendable, CaseIterable {
        /// 차·트럭에 치임(납작).
        case car
        /// 물에 빠짐(첨벙 가라앉음).
        case water
        /// 통나무에 실려 놀이 칸 밖으로 나감.
        case carriedOff
        /// 기차에 치임(튕겨 날아감).
        case train
        /// 화면 아래로 밀려남 · 너무 오래 앞으로 못 감("놓쳤어요").
        case leftBehind

        /// 결과 카드 한 줄.
        package var caption: String {
            switch self {
            case .car: "차에 치였어요"
            case .water: "물에 빠졌어요"
            case .carriedOff: "통나무와 떠내려갔어요"
            case .train: "기차에 치였어요"
            case .leftBehind: "놓쳤어요"
            }
        }
    }

    package struct Death: Equatable, Sendable {
        package var cause: DeathCause
        package var row: Int
        package var x: Double
        /// 판 시계(`elapsed`)로 잰 죽은 순간 — 그림이 연출 진행을 여기서 잰다.
        package var at: TimeInterval
        /// 친 것의 흐름 방향(+1/−1, 차·기차만 — 튕겨 나갈 쪽). 나머지는 0.
        package var pushDirection: Int
    }

    package enum Phase: Equatable, Sendable {
        /// 시작 전. 시작 풀밭에 아잉이가 서 있다(그림은 그려지고 루프는 멈춰 있다).
        case ready
        case running
        /// 죽음 연출. 0 이 되면 결과.
        case over(hold: TimeInterval)
        /// 결과 카드. 클릭이면 새 판.
        case result
    }

    // MARK: 상태(전부 읽기 전용)

    package private(set) var phase: Phase
    package private(set) var lanes: [Lane]
    package private(set) var player: Player
    package private(set) var hop: Hop?
    /// 뛰는 중 들어온 입력 하나(그 뒤 입력은 버린다 — "한 칸만 줄 세운다").
    package private(set) var queued: Direction?
    /// 점수 = 이 판에서 착지한 가장 앞 줄(시작 0). 뒤로 가도 줄지 않는다.
    package private(set) var score: Int
    /// 카메라가 보는 줄(연속값). 멈춤 벌칙의 기준이다.
    package private(set) var cameraRow: Double
    /// 가장 앞 줄을 마지막으로 넘긴 뒤 흐른 초.
    package private(set) var sinceProgress: TimeInterval
    package private(set) var death: Death?
    /// 판 시계(초). 정지·창 숨김 동안 안 흐른다.
    package private(set) var elapsed: TimeInterval
    /// 뛴 횟수(제자리 통통 포함) — 그림이 착지 먼지를 고를 때 쓴다.
    package private(set) var hopCount: Int
    /// 이 판의 시드(새 판마다 바뀐다).
    package private(set) var roundSeed: UInt64

    private var seedSource: CrossyRandom
    private var generator: CrossyRandom
    /// 이 판 값이 연 판 수. 첫 판은 시작 카드 뒤에 보이던 그 길 그대로 시작한다(눌렀는데 길이 바뀌면 튄다).
    private var roundsStarted = 0
    private var segmentKind: LaneKind
    private var segmentLeft: Int
    private var segmentIndex: Int
    private var pathColumn: Int

    // MARK: 만들기

    /// 시드에서 시작 판(준비 상태)을 만든다. 테스트는 시드를 고정하고, 화면은 시각에서 뽑는다.
    package init(seed: UInt64) {
        var source = CrossyRandom(seed: seed)
        let first = source.next()
        seedSource = source
        roundSeed = first
        generator = CrossyRandom(seed: first)
        phase = .ready
        lanes = []
        player = Player(row: 0, x: Double(Self.startColumn), riding: false, facing: .forward)
        hop = nil
        queued = nil
        score = 0
        cameraRow = 0
        sinceProgress = 0
        death = nil
        elapsed = 0
        hopCount = 0
        segmentKind = .grass
        segmentLeft = 0
        segmentIndex = 0
        pathColumn = Self.startColumn
        fillLanes()
    }

    // MARK: 파생(순수)

    package var isPlaying: Bool {
        switch phase {
        case .running, .over: true
        case .ready, .result: false
        }
    }

    package var isGameOver: Bool {
        switch phase {
        case .over, .result: true
        case .ready, .running: false
        }
    }

    /// 난이도 0…1 — 줄 번호로 오른다(속도 · 밀도 · 기찻길 빈도).
    package static func difficulty(row: Int) -> Double {
        min(1, max(0, Double(row - 4) / difficultyRows))
    }

    /// 카메라가 혼자 앞으로 가는 빠르기(줄/초). 가장 앞 줄의 난이도로 오른다.
    package static func creepSpeed(row: Int) -> Double {
        0.18 + 0.27 * difficulty(row: row)
    }

    /// 그 줄(들고 있는 범위 밖이면 nil).
    package func lane(at row: Int) -> Lane? {
        guard let first = lanes.first, row >= first.row, row - first.row < lanes.count else { return nil }
        return lanes[row - first.row]
    }

    /// 지금 충돌을 따지는 자리(줄, x). 뛰는 중이면 절반을 넘긴 순간 도착 줄로 넘어간다.
    package var occupancy: (row: Int, x: Double) {
        guard let hop else { return (player.row, player.x) }
        let p = hop.progress
        let row = p < 0.5 ? hop.fromRow : hop.toRow
        return (row, hop.fromX + (hop.toX - hop.fromX) * p)
    }

    /// 그림의 자리 — 줄(연속) · x · 뜬 높이(0…1, 포물선). 렌더러는 이것을 월드 좌표로 옮기기만 한다.
    package var playerVisual: (row: Double, x: Double, lift: Double) {
        guard let hop else { return (Double(player.row), player.x, 0) }
        let p = hop.progress
        let row = Double(hop.fromRow) + Double(hop.toRow - hop.fromRow) * p
        let x = hop.fromX + (hop.toX - hop.fromX) * p
        return (row, x, 4 * p * (1 - p))
    }

    // MARK: 입력

    /// 클릭·스페이스. 시작 전·결과면 새 판 + 앞으로 한 칸, 진행 중이면 앞으로 한 칸, 죽음 연출 중엔 무시.
    package mutating func action() {
        switch phase {
        case .ready, .result:
            startRound()
            input(.forward)
        case .running:
            input(.forward)
        case .over:
            return
        }
    }

    /// 방향 입력(↑↓←→ · WASD). 시작 전이면 새 판을 열고 그 방향으로 뛴다. 결과 화면의 방향키는 **무시한다** —
    /// 죽는 순간 누르고 있던 손가락이 다음 판을 열면 안 된다(다시 하기는 클릭·스페이스다).
    package mutating func input(_ direction: Direction) {
        switch phase {
        case .ready:
            startRound()
        case .running:
            break
        case .over, .result:
            return
        }
        if hop != nil {
            // 한 칸만 줄 세운다 — 이미 하나 서 있으면 버린다(연타가 쌓여 멈출 수 없게 되지 않게).
            if queued == nil { queued = direction }
            return
        }
        beginHop(direction, carry: 0)
    }

    /// 허브가 판을 끊을 때(창 닫힘 · 게임 전환 · [그만두기] · 정지 상한). 진행 중이면 그 점수로 결과 확정(유효).
    /// 플래피·테트리스와 같은 의미론이다 — 그래서 정지 상한(`quittingKeepsTheScore`)이 이 게임에도 걸린다.
    package mutating func interrupt() {
        switch phase {
        case .running, .over:
            phase = .result
            queued = nil
        case .ready, .result:
            break
        }
    }

    // MARK: 시간

    package mutating func step(dt rawDt: TimeInterval) {
        let dt = min(max(0, rawDt), Self.maxStep)
        switch phase {
        case .ready, .result:
            return
        case .over(let hold):
            // 연출 동안 차·통나무·기차는 계속 흐른다(친 차가 그 자리에 서 버리면 화면이 얼어 보인다). 규칙은 끝났다.
            elapsed += dt
            moveLanes(dt: dt)
            let left = hold - dt
            phase = left <= 0 ? .result : .over(hold: left)
            return
        case .running:
            break
        }

        elapsed += dt
        moveLanes(dt: dt)
        movePlayer(dt: dt)
        if case .over = phase { return }
        if score >= Self.maxScore {
            score = Self.maxScore
            phase = .result
            hop = nil
            queued = nil
            return
        }
        moveCamera(dt: dt)
        sinceProgress += dt
        checkDeaths()
        fillLanes()
    }

    // MARK: 내부 — 한 판

    private mutating func startRound() {
        // 첫 판은 시작 카드 뒤에 서 있던 길 그대로다(준비 상태는 시간이 안 흘러 줄이 그대로다). 그다음 판부터는
        // 새 길이다(같은 창에서 다시 하면 다른 길). 시드 줄기는 처음 시드에서 결정적으로 나온다.
        if roundsStarted > 0 {
            roundSeed = seedSource.next()
            generator = CrossyRandom(seed: roundSeed)
            lanes = []
            segmentKind = .grass
            segmentLeft = 0
            segmentIndex = 0
            pathColumn = Self.startColumn
        }
        roundsStarted += 1
        player = Player(row: 0, x: Double(Self.startColumn), riding: false, facing: .forward)
        hop = nil
        queued = nil
        score = 0
        cameraRow = 0
        sinceProgress = 0
        death = nil
        elapsed = 0
        hopCount = 0
        fillLanes()
        phase = .running
    }

    private mutating func beginHop(_ direction: Direction, carry: TimeInterval) {
        player.facing = direction
        hopCount += 1
        let fromRow = player.row
        let fromX = player.x
        let toRow = fromRow + direction.rowDelta
        let target = lane(at: toRow)
        var toX = fromX + Double(direction.columnDelta)
        var floats = false
        var bumped = false
        if target?.kind == .river {
            // 강으로 — 칸에 붙지 않는다(통나무 위 자리 그대로 · 착지에서 통나무를 찾는다).
            floats = true
            if !player.riding { toX = toX.rounded() }
            // 놀이 칸 밖으로 뛰는 것은 막힘이다 — 땅에서 같은 입력이 제자리 통통인 것과 같다(검토 지적 2026-10-27:
            // 통나무 위에서만 끝 칸 옆 뛰기가 그 자리에서 '떠내려감' 죽음이 됐다). 흘러 나가는 것은 여전히 죽음이다(checkDeaths).
            if toX < Self.playMinX || toX > Self.playMaxX { bumped = true }
        } else {
            // 땅으로 — 칸에 붙는다. 통나무에서 내릴 때는 가장 가까운 칸.
            // 놀이 칸 밖 · 나무 · 바위 · 아직 없는 줄은 전부 막힘이다(`isBlocked` 가 칸 범위까지 본다).
            let column = Int(toX.rounded())
            if target.map({ $0.isBlocked(column: column) }) ?? true {
                bumped = true
            } else {
                toX = Double(column)
            }
        }
        if bumped {
            hop = Hop(fromRow: fromRow, fromX: fromX, toRow: fromRow, toX: fromX, toFloats: player.riding,
                      elapsed: carry, direction: direction, bumped: true, fromRiding: player.riding)
        } else {
            hop = Hop(fromRow: fromRow, fromX: fromX, toRow: toRow, toX: toX, toFloats: floats,
                      elapsed: carry, direction: direction, bumped: false, fromRiding: player.riding)
        }
    }

    private mutating func movePlayer(dt: TimeInterval) {
        guard var current = hop else {
            // 서 있다 — 통나무 위면 같이 흐른다.
            if player.riding, let lane = lane(at: player.row) { player.x += lane.velocity * dt }
            return
        }
        // 뛰는 중 — 통나무에서 출발했으면 출발 줄의 흐름이 두 끝을 같이 민다(강으로 가는 착지점만 — 땅 칸은 고정).
        if current.fromRiding, let lane = lane(at: current.fromRow) {
            let shift = lane.velocity * dt
            current.fromX += shift
            if current.toFloats { current.toX += shift }
        }
        current.elapsed += dt
        // 1e-9 는 부동소수 덧셈 찌꺼기 몫이다 — 0.01 열두 번이 0.12 에 머리카락만큼 모자라 한 프레임 늦게 착지하면
        // 줄 선 뛰기가 그만큼 밀려 "착지 순간에 이어 붙는다"가 깨진다.
        guard current.elapsed >= Self.hopSeconds - 1e-9 else {
            hop = current
            return
        }
        let carry = max(0, current.elapsed - Self.hopSeconds)
        hop = nil
        land(current)
        if case .over = phase { return }
        if let next = queued {
            queued = nil
            beginHop(next, carry: carry)
        }
    }

    private mutating func land(_ landed: Hop) {
        player.row = landed.toRow
        player.x = landed.toX
        guard let lane = lane(at: landed.toRow) else { return }
        if lane.kind == .river {
            if lane.log(under: player.x) != nil {
                player.riding = true
            } else {
                player.riding = false
                die(.water, push: 0)
                return
            }
        } else {
            player.riding = false
            player.x = player.x.rounded()
        }
        if landed.toRow > score {
            score = landed.toRow
            sinceProgress = 0
        }
    }

    private mutating func moveCamera(dt: TimeInterval) {
        // 따라붙기(앞으로만) + 혼자 가기. 뒤로는 안 간다 — 뒤로 뛴 아잉이를 마중 나가면 벌칙이 아니다.
        let target = playerVisual.row
        if target > cameraRow {
            cameraRow += (target - cameraRow) * min(1, Self.followRate * dt)
        }
        cameraRow += Self.creepSpeed(row: score) * dt
    }

    private mutating func checkDeaths() {
        // 통나무에 실려 놀이 칸 밖으로.
        if player.riding, hop == nil, player.x < Self.playMinX || player.x > Self.playMaxX {
            die(.carriedOff, push: 0)
            return
        }
        if let current = hop, current.fromRiding, current.progress < 0.5,
           current.fromX < Self.playMinX || current.fromX > Self.playMaxX {
            die(.carriedOff, push: 0)
            return
        }
        let spot = occupancy
        if let lane = lane(at: spot.row) {
            switch lane.kind {
            case .road:
                if lane.movers.contains(where: { $0.overlaps(center: spot.x, halfWidth: Self.playerHalfWidth, grace: 0.06) }) {
                    die(.car, push: lane.direction)
                    return
                }
            case .rail:
                if let train = lane.train, train.overlaps(center: spot.x, halfWidth: Self.playerHalfWidth) {
                    die(.train, push: lane.direction)
                    return
                }
            case .grass, .river:
                break
            }
        }
        // 화면 아래로 밀려남 · 너무 오래 앞으로 못 감.
        if Double(spot.row) < cameraRow - Self.behindRows || sinceProgress >= Self.idleLimit {
            die(.leftBehind, push: 0)
        }
    }

    private mutating func die(_ cause: DeathCause, push: Int) {
        let spot = occupancy
        death = Death(cause: cause, row: spot.row, x: spot.x, at: elapsed, pushDirection: push)
        player.row = spot.row
        player.x = spot.x
        player.riding = false
        hop = nil
        queued = nil
        phase = .over(hold: Self.deathHold)
    }

    // MARK: 내부 — 줄

    private mutating func moveLanes(dt: TimeInterval) {
        for index in lanes.indices {
            switch lanes[index].kind {
            case .road, .river:
                let v = lanes[index].velocity * dt
                for m in lanes[index].movers.indices {
                    var mover = lanes[index].movers[m]
                    mover.x += v
                    if v > 0, mover.x > Self.trackRight { mover.x -= Self.trackLength }
                    if v < 0, mover.maxX < Self.trackLeft { mover.x += Self.trackLength }
                    lanes[index].movers[m] = mover
                }
            case .rail:
                Self.stepRail(&lanes[index], dt: dt)
            case .grass:
                break
            }
        }
    }

    private static func stepRail(_ lane: inout Lane, dt: TimeInterval) {
        if var train = lane.train {
            train.x += Double(lane.direction) * trainSpeed * dt
            let gone = lane.direction > 0 ? train.x > trackRight : train.maxX < trackLeft
            if gone {
                lane.train = nil
                let d = difficulty(row: lane.row)
                lane.trainCountdown = lane.trainRandom.uniform(4.0, 7.0) * (1 - 0.35 * d)
            } else {
                lane.train = train
            }
            return
        }
        lane.trainCountdown -= dt
        if lane.trainCountdown <= 0 {
            let start = lane.direction > 0 ? trackLeft - trainLength : trackRight
            lane.train = Mover(x: start, length: trainLength)
            lane.trainCountdown = 0
        }
    }

    /// 들고 있는 줄을 카메라 뒤 `lanesBehind` ~ 가장 앞 줄 앞 `lanesAhead` 로 맞춘다. 앞은 **순서대로만** 만든다(결정성).
    private mutating func fillLanes() {
        let lowest = min(player.row, Int(cameraRow.rounded(.down))) - Self.lanesBehind
        let highest = max(player.row, score) + Self.lanesAhead
        if lanes.isEmpty {
            // 첫 줄은 벽 아래부터 — 뒤 숲(−3)이 화면에 서야 "뒤는 막혔다"가 보인다.
            var row = min(lowest, Self.wallRow - 2)
            while row <= highest {
                lanes.append(makeLane(row: row))
                row += 1
            }
            return
        }
        while let last = lanes.last, last.row < highest {
            lanes.append(makeLane(row: last.row + 1))
        }
        if let first = lanes.first, first.row < lowest {
            lanes.removeFirst(min(lowest - first.row, lanes.count - 1))
        }
    }

    private mutating func makeLane(row r: Int) -> Lane {
        if r <= Self.wallRow {
            // 뒤 숲 — 전부 막힌 나무 벽.
            let props: [Prop?] = (0..<Self.columns).map { c in .tree(height: (c + r) & 1 == 0 ? 2 : 1) }
            return Lane(row: r, kind: .grass, props: props)
        }
        if r <= Self.startGrassRows {
            return startGrass(row: r)
        }
        if segmentLeft <= 0 { beginSegment(row: r) }
        segmentLeft -= 1
        segmentIndex += 1
        switch segmentKind {
        case .grass: return grass(row: r)
        case .road: return road(row: r)
        case .river: return river(row: r)
        case .rail: return rail(row: r)
        }
    }

    /// 시작 풀밭(−2…3). 가운데 줄기(3·4·5 칸)는 비운다 — 첫 걸음이 막히면 판이 시작부터 어색하다.
    private mutating func startGrass(row r: Int) -> Lane {
        var props = Array<Prop?>(repeating: nil, count: Self.columns)
        let edgeColumns = r < 0 ? [0, 1, 7, 8] : [0, 8]
        for c in edgeColumns where generator.unit() < (r < 0 ? 0.7 : 0.45) {
            props[c] = generator.unit() < 0.75 ? .tree(height: Int(generator.next() % 3)) : .rock
        }
        if r > 0 {
            for c in [1, 2, 6, 7] where generator.unit() < 0.2 {
                props[c] = generator.unit() < 0.7 ? .tree(height: Int(generator.next() % 3)) : .rock
            }
        }
        pathColumn = Self.startColumn
        return Lane(row: r, kind: .grass, props: props)
    }

    private mutating func beginSegment(row r: Int) {
        let d = Self.difficulty(row: r)
        var weights: [(LaneKind, Double)] = [
            (.grass, 0.30 - 0.10 * d),
            (.road, 0.36),
            (.river, r >= Self.riverStartRow ? 0.22 + 0.04 * d : 0),
            (.rail, r >= Self.railStartRow ? 0.08 + 0.10 * d : 0),
        ]
        // 같은 종류의 덩어리가 연달아 오지 않는다(붙으면 그냥 긴 덩어리다 — 길이는 아래에서 따로 고른다).
        weights = weights.map { $0.0 == segmentKind ? ($0.0, 0) : $0 }
        let total = weights.reduce(0) { $0 + $1.1 }
        var pick = generator.unit() * total
        var kind = LaneKind.road
        for (candidate, weight) in weights where weight > 0 {
            if pick < weight { kind = candidate; break }
            pick -= weight
            kind = candidate
        }
        let maxLength: Int
        switch kind {
        case .grass: maxLength = 2
        case .road: maxLength = 2 + Int(2 * d)
        case .river: maxLength = 2 + Int(d + 0.2)
        case .rail: maxLength = 1 + Int(d + 0.4)
        }
        segmentKind = kind
        segmentLeft = 1 + Int(generator.next() % UInt64(maxLength))
        segmentIndex = 0
        if kind == .grass {
            // 앞 덩어리가 풀밭이 아니면 길(막히지 않는 칸)을 새로 고른다. 풀밭끼리 붙은 줄은 같은 칸을 비워 둔다.
            pathColumn = 1 + Int(generator.next() % UInt64(Self.columns - 2))
        }
    }

    private mutating func grass(row r: Int) -> Lane {
        let d = Self.difficulty(row: r)
        var props = Array<Prop?>(repeating: nil, count: Self.columns)
        for c in 0..<Self.columns where c != pathColumn {
            guard generator.unit() < 0.18 + 0.12 * d else { continue }
            props[c] = generator.unit() < 0.7 ? .tree(height: Int(generator.next() % 3)) : .rock
        }
        return Lane(row: r, kind: .grass, props: props)
    }

    private mutating func road(row r: Int) -> Lane {
        let d = Self.difficulty(row: r)
        let direction = generator.unit() < 0.5 ? 1 : -1
        let truck = generator.unit() < 0.22 + 0.15 * d
        let length = truck ? Self.truckLength : Self.carLength
        var count = 1
        if generator.unit() < 0.5 + 0.3 * d { count += 1 }
        if d > 0.4, generator.unit() < 0.3 + 0.3 * d { count += 1 }
        let speed = generator.uniform(1.5, 2.3) * (1 + 0.9 * d) * (truck ? 0.85 : 1)
        let colorBase = Int(generator.next() % 5)
        let xs = place(count: count, length: { _ in length }, minGap: 3.0)
        let movers = xs.enumerated().map { i, x in
            Mover(x: x, length: length, variant: (colorBase + i) % 5, isTruck: truck)
        }
        return Lane(row: r, kind: .road, direction: direction, speed: speed, movers: movers)
    }

    private mutating func river(row r: Int) -> Lane {
        let d = Self.difficulty(row: r)
        // 한 강 안에서는 흐름이 번갈아 간다(첫 줄만 무작위) — 같은 방향이면 건너는 길이 한 줄로 몰린다.
        // 난수는 언제나 하나 뽑는다(뽑는 수가 갈래마다 다르면 뒤 줄들이 앞 줄 모양에 끌려 흔들린다).
        let coin = generator.unit() < 0.5 ? 1 : -1
        let direction: Int
        if segmentIndex > 1, let previous = lanes.last, previous.kind == .river {
            direction = -previous.direction
        } else {
            direction = coin
        }
        let speed = generator.uniform(0.9, 1.3) * (1 + 0.6 * d)
        let count = d < 0.5 ? 3 : 2
        let shortest = d < 0.4 ? 3 : 2
        var lengths: [Double] = []
        for _ in 0..<count { lengths.append(Double(shortest + Int(generator.next() % 2))) }
        let xs = place(count: count, length: { lengths[$0] }, minGap: 1.2)
        var movers: [Mover] = []
        for (i, x) in xs.enumerated() {
            movers.append(Mover(x: x, length: lengths[i], variant: Int(generator.next() % 3)))
        }
        return Lane(row: r, kind: .river, direction: direction, speed: speed, movers: movers)
    }

    private mutating func rail(row r: Int) -> Lane {
        let direction = generator.unit() < 0.5 ? 1 : -1
        let countdown = generator.uniform(1.5, 6.0)
        return Lane(row: r, kind: .rail, direction: direction, speed: Self.trainSpeed,
                    trainCountdown: countdown, trainSeed: generator.next())
    }

    /// 트랙 위에 `count` 개를 고르게 + 흔들어 놓는다(왼쪽 끝 x 들). 사이는 언제나 `minGap` 이상이다.
    private mutating func place(count: Int, length: (Int) -> Double, minGap: Double) -> [Double] {
        let slot = Self.trackLength / Double(count)
        let offset = generator.uniform(0, slot)
        return (0..<count).map { i in
            let room = max(0, slot - length(i) - minGap)
            let jitter = generator.uniform(0, room)
            var x = Self.trackLeft + offset + Double(i) * slot + jitter
            if x > Self.trackRight { x -= Self.trackLength }
            return x
        }
    }

    // MARK: 시험 · 미리보기 전용

    /// 지금 판에서 `row` 줄까지 **이어서 만들면** 나올 줄들(들고 있는 줄 + 그 앞). 판은 안 바뀐다(사본에서 만든다).
    /// 줄은 순서대로만 만들므로 같은 시드면 판을 어떻게 하든 같은 줄 번호에 같은 줄이 선다 — 시험이 그것을 잰다.
    package func previewLanes(through row: Int) -> [Lane] {
        var copy = self
        while let last = copy.lanes.last, last.row < row {
            copy.lanes.append(copy.makeLane(row: last.row + 1))
        }
        return copy.lanes
    }

    /// 그 줄을 통째로 갈아 끼운다(시험이 차·통나무·기차를 원하는 자리에 세운다). 들고 있지 않은 줄이면 아무 일도 없다.
    package mutating func replaceLane(_ lane: Lane) {
        guard let first = lanes.first, lane.row >= first.row, lane.row - first.row < lanes.count else { return }
        lanes[lane.row - first.row] = lane
    }

    /// 판을 바로 진행 중으로 연다(뛰지 않고). 시험이 "서 있는 판"에서 시작할 때 쓴다.
    package mutating func startForTesting() {
        startRound()
    }

    /// 아잉이를 그 자리에 세운다(시험 전용 — 착지 규칙을 거치지 않는다).
    package mutating func placePlayerForTesting(row: Int, x: Double, riding: Bool = false) {
        player.row = row
        player.x = x
        player.riding = riding
        hop = nil
        queued = nil
    }
}

/// 이 게임의 결정적 난수(SplitMix64 — `MiniGameRandom` 과 같은 식). **상태가 값으로 드러나** `Equatable` 이다 —
/// 판 전체를 비교하는 결정성 시험이 난수 상태까지 같은지 본다.
package struct CrossyRandom: Equatable, Sendable {
    package private(set) var state: UInt64

    package init(seed: UInt64) { state = seed }

    package mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// [0, 1) 균등.
    package mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// [lo, hi] 균등.
    package mutating func uniform(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * unit()
    }
}
