import AppKit
import Foundation
import Observation
import SceneKit

/// 아잉 캐릭터의 "생명력" 리액션 종류. 원본 모델에 리깅/클립이 없으므로 전부 프로그래매틱
/// (SCNAction squash & stretch 계열)으로 표현한다. 한 번에 하나만 재생하며, 재생 중 낮은 우선순위
/// 요청은 무시한다(우선순위: hit·출퇴근·화들짝 > 마일스톤 > 인사 > 졸기).
///
/// `drowsy` 는 일회성 재생이 아니라 지속 상태(sleeping)로의 진입 요청이다(엔진이 State.sleeping 으로 전이).
/// 잠에서 깨는 `wake` 는 자는 중 클릭으로만 발화한다.
enum ReactionKind: Equatable {
    /// 패널을 때렸을 때(전역 클릭이 패널 프레임 안).
    case hit
    /// 근무 시작(패널 표시 직후) — 폴짝 점프 + y축 360° 스핀.
    case commuteStart
    /// 근무 종료 — 앞으로 꾸벅 인사 후 패널을 숨긴다.
    case commuteEnd
    /// 오늘 누적 1시간/4시간 돌파, 팀 주간 목표 100% 돌파 — 폴짝폴짝 + 색종이 버스트.
    case milestone
    /// 팀원이 offWork→working 으로 전이했을 때 — 까딱 인사 + 말풍선.
    case greeting(name: String)
    /// 밤샘 졸기(KST 23:00~05:00) 진입 요청 — 앞으로 기울며 가라앉은 뒤 그 자세를 유지(sleeping 상태).
    case drowsy
    /// 자는 중 클릭으로 깨어남 — 화들짝(스냅 복원 + 살짝 튀어오름) + "깜빡 졸았다!" 말풍선.
    case wake

    /// 우선순위(높을수록 우선). hit/출퇴근/화들짝 > 마일스톤 > 인사 > 졸기.
    /// (wake/drowsy 는 sleeping 상태 분기에서 직접 처리되어 우선순위 비교를 거의 타지 않는다.)
    var priority: Int {
        switch self {
        case .hit, .commuteStart, .commuteEnd, .wake:
            return 3
        case .milestone:
            return 2
        case .greeting:
            return 1
        case .drowsy:
            return 0
        }
    }

    /// 재생 길이(초). 엔진은 이 길이 동안 재생 상태를 유지하고, 지나면 idle 로 복귀한다.
    /// (drowsy 는 만료 없는 sleeping 상태라 이 값을 쓰지 않는다.)
    var duration: TimeInterval {
        switch self {
        case .hit:
            return 0.6
        case .commuteStart:
            return 0.6
        case .commuteEnd:
            return 0.4
        case .milestone:
            return 1.6
        case .greeting:
            return 1.0
        case .wake:
            // 화들짝 모션(스냅 0.15 + 튀어오름 0.16)에 여유를 둔 길이. 이후 idle 복귀.
            return 0.4
        case .drowsy:
            // 지속 상태(sleeping)라 만료 판정에 쓰지 않는다. 참고용으로 진입 모션 길이를 둔다.
            return 2.0
        }
    }
}

/// 졸기 스케줄 파라미터(순수 함수). 시간대 제한 없이, 한동안 아무 리액션이 없으면 존다.
enum DrowsyWindow {
    static let timeZone = TimeZone(identifier: "Asia/Seoul")!

    /// 졸기 진입 간격 하한/상한(초). 10±4분 — 마지막 리액션 이후 이만큼 조용하면 꾸벅 잠든다.
    static let minInterval: TimeInterval = 6 * 60
    static let maxInterval: TimeInterval = 14 * 60

    /// 주어진 시각(기본 KST)이 밤샘 시간창(23:00~05:00) 안이면 true. 23,0,1,2,3,4시가 해당된다.
    static func contains(_ date: Date, timeZone: TimeZone = DrowsyWindow.timeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        return hour >= 23 || hour < 5
    }

    /// 90±30초 범위의 다음 졸기 간격을 뽑는다(난수 주입 가능).
    static func nextInterval(using rng: inout some RandomNumberGenerator) -> TimeInterval {
        TimeInterval.random(in: minInterval...maxInterval, using: &rng)
    }
}

/// 마일스톤 1일 1회 기록기. UserDefaults 에 "check.milestone.<키>.<yyyyMMdd(KST)>" 로 기록해
/// 같은 날 같은 키의 축하가 두 번 터지지 않게 한다. 세션 내 중복 조회를 줄이려 인메모리 캐시도 둔다.
struct MilestoneTracker {
    static let hourOneKey = "hour1"
    static let hourFourKey = "hour4"
    static let teamGoalKey = "teamGoal"

    let defaults: UserDefaults
    private var firedThisSession: Set<String> = []

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func dayKey(_ date: Date, timeZone: TimeZone = DrowsyWindow.timeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func defaultsKey(_ key: String, day: String) -> String {
        "check.milestone.\(key).\(day)"
    }

    /// 오늘(KST) 아직 안 터진 키면 기록하고 true, 이미 터졌으면 false. 하루가 지나면 다시 true 가 된다.
    mutating func fireIfNeeded(_ key: String, now: Date) -> Bool {
        let dkey = Self.defaultsKey(key, day: Self.dayKey(now))
        if firedThisSession.contains(dkey) {
            return false
        }
        if defaults.bool(forKey: dkey) {
            firedThisSession.insert(dkey)
            return false
        }
        defaults.set(true, forKey: dkey)
        firedThisSession.insert(dkey)
        return true
    }
}

/// 팀원 출근 인사 전이 감지기(순수 상태 기계). refreshTeamStatus 가 팀 목록을 반영할 때마다 호출되어
/// 남(自 제외) 멤버가 offWork→working 으로 바뀐 전이를 찾아 인사할 이름을 돌려준다.
/// - 첫 로드(앱 시작 직후 최초 팀 목록)는 전이로 치지 않는다(기존 근무자에게 인사 폭탄 금지).
/// - 멤버당 10분 쿨다운(연속 출퇴근 반복에도 인사가 도배되지 않게).
struct TeammateGreetingDetector {
    static let cooldown: TimeInterval = 10 * 60

    private var lastStatuses: [String: WorkStatus] = [:]
    private var lastGreetedAt: [String: Date] = [:]
    private var hasSeededInitial = false

    /// 세션 종료(로그아웃) 시 상태를 비운다.
    mutating func reset() {
        lastStatuses = [:]
        lastGreetedAt = [:]
        hasSeededInitial = false
    }

    /// 새 팀 목록을 반영하고, 인사할 팀원 이름 목록을 돌려준다(전이·쿨다운·첫 로드 규칙 적용).
    mutating func detect(members: [TeamMemberStatus], selfID: String?, now: Date = Date()) -> [String] {
        defer {
            for member in members {
                lastStatuses[member.id] = member.status
            }
        }

        // 첫 로드: 현재 상태만 시드하고 아무도 인사하지 않는다.
        guard hasSeededInitial else {
            hasSeededInitial = true
            return []
        }

        var greetings: [String] = []
        for member in members where member.id != selfID {
            // offWork→working 전이만 인사한다(nil→working 신규 등장은 이미 근무 중이므로 제외).
            guard lastStatuses[member.id] == .offWork, member.status == .working else {
                continue
            }
            if let last = lastGreetedAt[member.id], now.timeIntervalSince(last) < Self.cooldown {
                continue
            }
            greetings.append(member.name)
            lastGreetedAt[member.id] = now
        }
        return greetings
    }
}

/// 리액션 재생 조율기. 캐릭터 wrapper 노드에 SCNAction 시퀀스를 걸고, 재생 상태를 enum 으로 노출해
/// 우선순위/쿨다운 로직을 헤드리스로 검증할 수 있게 한다(노드가 없어도 상태 전이는 그대로 동작).
///
/// - idle(부유/회전)은 wrapper 안쪽 캐릭터 노드에 걸려 있어 리액션(wrapper)과 간섭하지 않는다.
/// - 시간은 clock 주입으로 결정적으로 만든다(재생 만료 판정에 사용). SCNAction 완료 콜백은 렌더 루프가
///   돌 때만 발화하므로, 만료 판정은 clock 기반으로 이중화한다.
@MainActor
@Observable
final class ReactionEngine {
    enum State: Equatable {
        case idle
        case playing(ReactionKind)
        /// 졸기 지속 상태. 자동으로 깨지 않으며(만료 없음), 클릭(wake)·마일스톤·근무종료로만 벗어난다.
        case sleeping
    }

    static let hitCooldown: TimeInterval = 0.6

    /// 말풍선 지속시간(초) 사양. perform 과 테스트가 공유해 지속시간을 결정적으로 검증한다.
    static let hitBubbleSeconds: Double = 1.2
    static let commuteStartBubbleSeconds: Double = 5
    static let commuteEndBubbleSeconds: Double = 2
    static let greetingBubbleSeconds: Double = 3
    static let wakeBubbleSeconds: Double = 2.5

    /// 말풍선 텍스트(SwiftUI 관찰용). nil 이면 숨김. 각 리액션이 자기 텍스트/지속시간으로 교체한다.
    /// (팀원 인사·시작 화이팅·때리기 아얏·종료 수고·깨우기 등 모두 이 한 채널을 자체 타이머로 공유.)
    var greetingText: String?
    /// SCNView 렌더 루프 활성 여부(SwiftUI 관찰용). 패널 표시~근무종료 인사까지 true 로 유지해
    /// 근무종료 꾸벅 인사가 렌더되게 하고, 숨김 시 false 로 내려 렌더를 멈춘다(전력 배려).
    var renderActive = false

    @ObservationIgnored private(set) var activeKind: ReactionKind?
    @ObservationIgnored private var activeUntil: Date = .distantPast
    @ObservationIgnored private var lastHitAt: Date?
    /// 졸기 지속 상태 플래그. true 인 동안 state 는 .sleeping 이며 activeKind 는 nil 이다.
    @ObservationIgnored private var isSleeping = false
    @ObservationIgnored private let clock: () -> Date

    @ObservationIgnored private weak var reactionNode: SCNNode?
    @ObservationIgnored private weak var sceneRoot: SCNNode?
    @ObservationIgnored private var modelExtent: CGFloat = 1
    @ObservationIgnored private var greetingClearTask: Task<Void, Never>?
    /// 자는 동안 💤 를 주기적으로 방출하는 반복 태스크(3.5초 주기). 깨거나 인터럽트되면 취소된다.
    @ObservationIgnored private var zzzTask: Task<Void, Never>?

    private static let reactionActionKey = "check.reaction"
    private static let confettiNodeName = "check.reaction.confetti"
    private static let zzzNodeName = "check.reaction.zzz"

    init(clock: @escaping () -> Date = { Date() }) {
        self.clock = clock
    }

    /// wrapper 노드와 씬 루트를 연결한다(makeNSView 에서 호출). modelExtent 로 동작 크기를 모델 규모에 맞춘다.
    func attach(node: SCNNode, sceneRoot: SCNNode) {
        self.reactionNode = node
        self.sceneRoot = sceneRoot
        let (minB, maxB) = node.boundingBox
        let extent = CGFloat(max(maxB.x - minB.x, max(maxB.y - minB.y, maxB.z - minB.z)))
        modelExtent = extent > 0 ? extent : 1
    }

    var hasAttachedNode: Bool {
        reactionNode != nil
    }

    /// 현재 재생 상태. clock 으로 만료를 확인해 지난 리액션은 idle 로 본다.
    /// sleeping 은 만료가 없어 클릭(wake)·마일스톤·근무종료 인터럽트 전까지 유지된다.
    var state: State {
        expireIfNeeded()
        if isSleeping {
            return .sleeping
        }
        if let activeKind {
            return .playing(activeKind)
        }
        return .idle
    }

    private func expireIfNeeded() {
        if activeKind != nil, clock() >= activeUntil {
            activeKind = nil
        }
    }

    /// 리액션 요청. 우선순위/쿨다운을 판정해 수용되면 true. 수용 시 SCNAction 을 wrapper 에 건다.
    /// 완료는 clock 기반 만료(상태)와 호출측 워치독(예: 근무종료 숨김)에 맡긴다.
    ///
    /// 자는 중(sleeping)에는 별도 라우팅을 탄다: 클릭(wake/hit)은 화들짝으로 깨우고, 마일스톤/근무종료/
    /// 근무시작은 잠을 인터럽트하며, 재-졸기·인사는 무시된다("자는데 인사 안 함").
    @discardableResult
    func request(_ kind: ReactionKind) -> Bool {
        let now = clock()
        expireIfNeeded()

        if isSleeping {
            switch kind {
            case .drowsy, .greeting:
                // 재-졸기 요청·팀원 인사는 자는 동안 무시(자는데 깨우지도, 인사하지도 않는다).
                return false
            case .wake, .hit:
                // 자는 중 클릭 → 화들짝 + "깜빡 졸았다!" 로 깨운다(hit 쿨다운과 무관하게 즉시).
                beginWake(now: now)
                return true
            case .commuteStart, .commuteEnd, .milestone:
                // 잠을 인터럽트하고 정상 재생으로 넘어간다(아래 일반 경로).
                endSleep()
            }
        }

        // wake 는 자는 중에만 유효(위 분기에서 처리). 깨어 있을 때 들어오면 재생할 것이 없다.
        if case .wake = kind {
            return false
        }

        if case .hit = kind, let last = lastHitAt, now.timeIntervalSince(last) < Self.hitCooldown {
            return false
        }

        if let active = activeKind, kind.priority <= active.priority {
            return false
        }

        if activeKind != nil {
            interruptCurrent()
        }

        // drowsy 는 일회성 재생이 아니라 지속 상태(sleeping)로의 진입이다.
        if case .drowsy = kind {
            beginSleep()
            return true
        }

        if case .hit = kind {
            lastHitAt = now
        }
        activeKind = kind
        activeUntil = now.addingTimeInterval(kind.duration)

        perform(kind)
        return true
    }

    private func interruptCurrent() {
        reactionNode?.removeAction(forKey: Self.reactionActionKey)
        resetPose()
        removeTransientNodes()
        // 말풍선은 자체 타이머를 소유하므로 여기서 강제로 지우지 않는다.
        // (새 리액션이 자기 showBubble 로 교체하거나, 말풍선 없는 리액션이면 이전 타이머대로 소멸.)
    }

    private func resetPose() {
        guard let node = reactionNode else { return }
        node.scale = SCNVector3(1, 1, 1)
        node.eulerAngles = SCNVector3(0, 0, 0)
        node.position = SCNVector3(0, 0, 0)
    }

    private func removeTransientNodes() {
        guard let root = sceneRoot else { return }
        for name in [Self.confettiNodeName, Self.zzzNodeName] {
            root.childNodes.filter { $0.name == name }.forEach { $0.removeFromParentNode() }
        }
    }

    // MARK: - 개별 리액션 동작 구성

    private func perform(_ kind: ReactionKind) {
        switch kind {
        case .hit:
            runReaction(ReactionActions.hit())
            showBubble("아얏!", seconds: Self.hitBubbleSeconds)
        case .commuteStart:
            runReaction(ReactionActions.commuteStart(hop: modelExtent * 0.32))
            showBubble("오늘도 화이팅!", seconds: Self.commuteStartBubbleSeconds)
        case .commuteEnd:
            runReaction(ReactionActions.commuteEnd())
            showBubble("수고했어!", seconds: Self.commuteEndBubbleSeconds)
        case .milestone:
            runReaction(ReactionActions.milestone(hop: modelExtent * 0.28))
            emitConfetti()
        case .greeting(let name):
            showBubble("\(name)님 출근!", seconds: Self.greetingBubbleSeconds)
            runReaction(ReactionActions.greetingNod())
        case .drowsy, .wake:
            // drowsy/wake 는 request 에서 beginSleep/beginWake 로 직접 처리되어 이 경로로 오지 않는다.
            break
        }
    }

    // MARK: - 졸기 지속 상태(sleeping) / 깨우기(wake)

    /// 졸기 진입: 앞으로 천천히 숙이며 가라앉은 자세로 전이하고, 그 자세를 유지한다(자동으로 깨지 않음).
    /// 자는 동안 💤 를 주기적으로 방출한다(zzzTask).
    private func beginSleep() {
        isSleeping = true
        activeKind = nil
        if let node = reactionNode {
            resetPose()
            node.runAction(ReactionActions.drowsySink(tilt: modelExtent * 0.18), forKey: Self.reactionActionKey)
        }
        startZzzLoop()
    }

    /// 졸기 종료(잠 상태만 해제 — 포즈는 호출측이 처리). zzzTask 취소 + 💤 노드 정리.
    /// 마일스톤/근무종료 인터럽트는 이후 runReaction(resetPose 포함)이 포즈를 복원한다.
    private func endSleep() {
        isSleeping = false
        zzzTask?.cancel()
        zzzTask = nil
        removeTransientNodes()
    }

    /// 자는 중 클릭으로 깨우기: 화들짝(현재 숙인 자세에서 스냅 복원 + 살짝 튀어오름) + "깜빡 졸았다!".
    /// resetPose 를 거치지 않고 현재(숙인) 트랜스폼에서 애니메이션해 자연스럽게 튀어오르게 한다.
    private func beginWake(now: Date) {
        endSleep()
        activeKind = .wake
        activeUntil = now.addingTimeInterval(ReactionKind.wake.duration)
        if let node = reactionNode {
            node.removeAction(forKey: Self.reactionActionKey)
            node.runAction(ReactionActions.wake(tilt: modelExtent * 0.18), forKey: Self.reactionActionKey)
        }
        showBubble("깜빡 졸았다!", seconds: Self.wakeBubbleSeconds)
    }

    /// 외부(패널 숨김 등)에서 졸기 상태를 강제 종료한다. 포즈까지 identity 로 복원(잔상 방지).
    func stopSleeping() {
        guard isSleeping else { return }
        endSleep()
        resetPose()
    }

    private func startZzzLoop() {
        zzzTask?.cancel()
        zzzTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isSleeping else { return }
                self.spawnZzzBurst()
                try? await Task.sleep(for: .seconds(3.5))
            }
        }
    }

    /// wrapper 에 리액션 시퀀스를 건다. 시퀀스는 identity 에서 시작해 identity 로 끝나므로 잔상이 남지 않는다.
    /// 상태 만료(idle 복귀)는 clock(expireIfNeeded)이 담당한다(렌더 루프 유무와 무관하게 결정적).
    private func runReaction(_ action: SCNAction) {
        guard let node = reactionNode else { return }
        resetPose()
        node.runAction(action, forKey: Self.reactionActionKey)
    }

    // MARK: - 말풍선(공통)

    /// 말풍선을 `text` 로 띄우고 `seconds` 뒤 자체 페이드로 소멸시킨다. 중복 호출 시 이전 타이머를 리셋한다
    /// (새 리액션이 자기 텍스트/지속시간으로 즉시 교체). 텍스트 변화는 SwiftUI 가 관찰해 페이드한다.
    func showBubble(_ text: String, seconds: Double) {
        greetingClearTask?.cancel()
        greetingText = text
        greetingClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.greetingText = nil
        }
    }

    // MARK: - 색종이 버스트(마일스톤)

    private func emitConfetti() {
        guard let root = sceneRoot else { return }
        removeTransientNodes()
        let emitter = SCNNode()
        emitter.name = Self.confettiNodeName
        emitter.position = SCNVector3(0, modelExtent * 0.5, 0)
        emitter.addParticleSystem(ReactionActions.confettiSystem())
        root.addChildNode(emitter)
        // 버스트 후 제거(전력 배려 — 파티클을 남기지 않는다).
        emitter.runAction(.sequence([.wait(duration: 1.5), .removeFromParentNode()]))
    }

    // MARK: - 💤 Z 노드(졸기)

    /// 💤 한 묶음(3개)을 머리 위 빈 코너에서 위로 떠오르게 방출한다. 각 묶음 컨테이너는 수명 후 자가 제거되며,
    /// 자는 동안 zzzTask 가 주기적으로 다시 호출한다. 깨거나 인터럽트되면 removeTransientNodes 로 일괄 정리.
    private func spawnZzzBurst() {
        guard let root = sceneRoot else { return }
        let container = SCNNode()
        container.name = Self.zzzNodeName
        // 머리 위 오른쪽 빈 코너에서 시작해 위로 떠오른다(캐릭터가 프레임을 꽉 채우므로 빈 코너를 쓴다).
        container.position = SCNVector3(modelExtent * 0.3, modelExtent * 0.25, modelExtent * 0.1)
        root.addChildNode(container)
        for index in 0..<3 {
            let z = ReactionActions.makeZNode(extent: modelExtent)
            z.opacity = 0
            z.position = SCNVector3(modelExtent * 0.04 * CGFloat(index), 0, 0)
            container.addChildNode(z)
            let rise = modelExtent * 0.32
            let delay = Double(index) * 0.5
            let float = SCNAction.sequence([
                .wait(duration: delay),
                .group([
                    .fadeIn(duration: 0.3),
                    .moveBy(x: modelExtent * 0.06, y: rise, z: 0, duration: 1.6)
                ]),
                .fadeOut(duration: 0.4),
                .removeFromParentNode()
            ])
            z.runAction(float)
        }
        container.runAction(.sequence([.wait(duration: 3.0), .removeFromParentNode()]))
    }
}

/// 리액션 SCNAction/파티클/포즈를 만드는 순수 팩토리. 시각 스냅샷 테스트가 정지 포즈로도 재사용한다.
enum ReactionActions {
    static func radians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }

    /// 때리면 아파하기: 순간 찌부 → 스프링 복원(오버슈트 2회 감쇠) + 좌우 부르르(±8°, 3회).
    static func hit() -> SCNAction {
        let identity = SCNVector3(1, 1, 1)
        let squashed = SCNVector3(1.28, 0.62, 1.28)
        let over1 = SCNVector3(0.90, 1.14, 0.90)
        let over2 = SCNVector3(1.08, 0.94, 1.08)
        let over3 = SCNVector3(0.97, 1.04, 0.97)
        let squashPose = SCNAction.scaleKeyframe(from: identity, to: squashed, duration: 0.08, timing: .easeOut)
        let up1 = SCNAction.scaleKeyframe(from: squashed, to: over1, duration: 0.12, timing: .easeInEaseOut)
        let down1 = SCNAction.scaleKeyframe(from: over1, to: over2, duration: 0.12, timing: .easeInEaseOut)
        let up2 = SCNAction.scaleKeyframe(from: over2, to: over3, duration: 0.10, timing: .easeInEaseOut)
        let settle = SCNAction.scaleKeyframe(from: over3, to: identity, duration: 0.10, timing: .easeInEaseOut)
        let scaleSeq = SCNAction.sequence([squashPose, up1, down1, up2, settle])

        // 좌우 부르르: z축 ±8° 3회 감쇠 후 0 복귀. 총 길이를 scale 시퀀스(0.52)에 맞춘다.
        let a = radians(8)
        let shudder = SCNAction.sequence([
            .rotateTo(x: 0, y: 0, z: a, duration: 0.06),
            .rotateTo(x: 0, y: 0, z: -a, duration: 0.10),
            .rotateTo(x: 0, y: 0, z: a * 0.6, duration: 0.10),
            .rotateTo(x: 0, y: 0, z: -a * 0.4, duration: 0.10),
            .rotateTo(x: 0, y: 0, z: 0, duration: 0.10)
        ])
        return .group([scaleSeq, shudder])
    }

    /// 근무 시작: 폴짝 점프(+hop) + y축 360° 스핀.
    static func commuteStart(hop: CGFloat) -> SCNAction {
        let jumpUp = SCNAction.moveBy(x: 0, y: hop, z: 0, duration: 0.3)
        jumpUp.timingMode = .easeOut
        let jumpDown = SCNAction.moveBy(x: 0, y: -hop, z: 0, duration: 0.3)
        jumpDown.timingMode = .easeIn
        let hopSeq = SCNAction.sequence([jumpUp, jumpDown])
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.6)
        return .group([hopSeq, spin])
    }

    /// 근무 종료: 앞으로 꾸벅 인사(x축 -20°) 후 복원.
    static func commuteEnd() -> SCNAction {
        let bow = SCNAction.rotateTo(x: radians(20), y: 0, z: 0, duration: 0.18)
        bow.timingMode = .easeOut
        let hold = SCNAction.wait(duration: 0.06)
        let up = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.16)
        up.timingMode = .easeInEaseOut
        return .sequence([bow, hold, up])
    }

    /// 마일스톤: 폴짝폴짝 2회.
    static func milestone(hop: CGFloat) -> SCNAction {
        let up = SCNAction.moveBy(x: 0, y: hop, z: 0, duration: 0.22)
        up.timingMode = .easeOut
        let down = SCNAction.moveBy(x: 0, y: -hop, z: 0, duration: 0.22)
        down.timingMode = .easeIn
        let oneHop = SCNAction.sequence([up, down])
        return .sequence([oneHop, oneHop])
    }

    /// 팀원 인사: z축 ±10° 두 번 까딱.
    static func greetingNod() -> SCNAction {
        let a = radians(10)
        return .sequence([
            .rotateTo(x: 0, y: 0, z: a, duration: 0.14),
            .rotateTo(x: 0, y: 0, z: -a, duration: 0.20),
            .rotateTo(x: 0, y: 0, z: a, duration: 0.20),
            .rotateTo(x: 0, y: 0, z: 0, duration: 0.16)
        ])
    }

    /// 졸기 진입(가라앉기): 앞으로 천천히 숙이며 가라앉는다(2s). 끝난 뒤 그 자세(x +14°, y -tilt*0.33)를 유지한다.
    /// 지속 상태(sleeping)의 정지 포즈이므로 복원 동작을 붙이지 않는다(깨우기는 wake 가 담당).
    static func drowsySink(tilt: CGFloat) -> SCNAction {
        let sink = SCNAction.group([
            SCNAction.rotateTo(x: radians(14), y: 0, z: 0, duration: 2.0),
            SCNAction.moveBy(x: 0, y: -tilt * 0.33, z: 0, duration: 2.0)
        ])
        sink.timingMode = .easeInEaseOut
        return sink
    }

    /// 화들짝 깨우기: 숙인 자세에서 identity 로 스냅 복원(0.15s) + 살짝 튀어오름. 현재 트랜스폼과 무관하게
    /// 절대 위치(0)로 복원하므로 진입 모션 도중 깨워도 잔상이 남지 않는다.
    static func wake(tilt: CGFloat) -> SCNAction {
        let snap = SCNAction.group([
            SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.15),
            SCNAction.move(to: SCNVector3(0, 0, 0), duration: 0.15)
        ])
        snap.timingMode = .easeOut
        // 살짝 튀어오름.
        let bounceUp = SCNAction.moveBy(x: 0, y: tilt * 0.12, z: 0, duration: 0.08)
        let bounceDown = SCNAction.moveBy(x: 0, y: -tilt * 0.12, z: 0, duration: 0.08)
        return .sequence([snap, bounceUp, bounceDown])
    }

    /// 색종이 파티클(코드 생성). 작은 사각 다색, 짧은 버스트.
    static func confettiSystem() -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.particleImage = nil // 기본 사각 파티클(작은 사각 조각).
        system.emissionDuration = 0.1
        system.loops = false
        system.particleLifeSpan = 1.2
        system.particleLifeSpanVariation = 0.4
        system.particleSize = 0.03
        system.particleSizeVariation = 0.02
        system.particleVelocity = 1.2
        system.particleVelocityVariation = 0.8
        system.spreadingAngle = 180
        system.emitterShape = SCNSphere(radius: 0.02)
        system.birthDirection = .random
        system.acceleration = SCNVector3(0, -1.5, 0)
        system.particleColor = NSColor.systemPink
        system.particleColorVariation = SCNVector4(0.9, 0.9, 0.9, 0)
        system.particleAngle = 0
        system.particleAngleVariation = 180
        system.particleAngularVelocity = 3
        system.particleAngularVelocityVariation = 5
        system.blendMode = .alpha
        system.isLightingEnabled = false
        // 버스트: 짧은 시간에 다량 방출.
        system.birthRate = 800
        return system
    }

    /// 💤 표현용 "Z" 텍스트 노드(흰색 반투명, unlit).
    static func makeZNode(extent: CGFloat) -> SCNNode {
        let text = SCNText(string: "Z", extrusionDepth: 0)
        text.font = NSFont.systemFont(ofSize: 1, weight: .bold)
        text.flatness = 0.1
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = NSColor.white.withAlphaComponent(0.85)
        material.isDoubleSided = true
        text.materials = [material]
        let node = SCNNode(geometry: text)
        let scale = extent * 0.12
        node.scale = SCNVector3(scale, scale, scale)
        return node
    }
}

/// SCNAction.scale(to:) 는 균일 스케일만 지원하므로, 축별(비균일) 스케일 키프레임을 만드는 헬퍼.
/// 리액션 키프레임은 identity 에서 시작해 순차로 연결되므로 시작 스케일(from)을 명시로 받아 KVC 없이 보간한다.
extension SCNAction {
    enum ScaleTiming {
        case linear
        case easeOut
        case easeInEaseOut
    }

    static func scaleKeyframe(from: SCNVector3, to: SCNVector3, duration: TimeInterval, timing: ScaleTiming) -> SCNAction {
        SCNAction.customAction(duration: duration) { node, elapsed in
            let t = duration > 0 ? min(1, Double(elapsed) / duration) : 1
            let eased = CGFloat(Self.ease(t, timing: timing))
            node.scale = SCNVector3(
                from.x + (to.x - from.x) * eased,
                from.y + (to.y - from.y) * eased,
                from.z + (to.z - from.z) * eased
            )
        }
    }

    private static func ease(_ t: Double, timing: ScaleTiming) -> Double {
        switch timing {
        case .linear:
            return t
        case .easeOut:
            return 1 - pow(1 - t, 2)
        case .easeInEaseOut:
            return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        }
    }
}
