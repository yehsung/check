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

    /// KST(Asia/Seoul) 그레고리력. 매 호출마다 Calendar 를 새로 만들지 않도록 1회 생성해 공유한다.
    static let kstCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DrowsyWindow.timeZone
        return calendar
    }()

    let defaults: UserDefaults
    private var firedThisSession: Set<String> = []
    /// 오늘 하루(KST)의 [시작, 다음날 시작) 구간과 그 dayKey. now 가 이 구간 안이면 재계산을 건너뛴다.
    private var cachedDay: (start: Date, next: Date, key: String)?

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func dayKey(_ date: Date, timeZone: TimeZone = DrowsyWindow.timeZone) -> String {
        let calendar: Calendar
        if timeZone == DrowsyWindow.timeZone {
            calendar = kstCalendar
        } else {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = timeZone
            calendar = c
        }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func defaultsKey(_ key: String, day: String) -> String {
        "check.milestone.\(key).\(day)"
    }

    /// 자정 롤오버 전까지 dayKey 를 메모해, 근무 1h 후 매초 호출에서도 Calendar 계산을 반복하지 않는다.
    /// now 가 캐시 구간을 벗어나면(하루가 지나면) 재계산해 자정 귀속 정확성을 유지한다.
    private mutating func cachedDayKey(for now: Date) -> String {
        if let cached = cachedDay, now >= cached.start, now < cached.next {
            return cached.key
        }
        let calendar = Self.kstCalendar
        let start = calendar.startOfDay(for: now)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let key = Self.dayKey(now)
        cachedDay = (start, next, key)
        return key
    }

    /// 오늘(KST) 아직 안 터진 키면 기록하고 true, 이미 터졌으면 false. 하루가 지나면 다시 true 가 된다.
    mutating func fireIfNeeded(_ key: String, now: Date) -> Bool {
        let dkey = Self.defaultsKey(key, day: cachedDayKey(for: now))
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

    /// 렌더 FPS 정책: 유휴/졸기는 느린 모션이라 8fps 로 충분하고, 리액션 재생 중에만 30fps 로 올린다.
    static let idleFPS = 8
    static let activeFPS = 30

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
    /// 렌더 FPS 를 조절하기 위한 SCNView 참조(attach 에서 makeNSView 가 전달). 뷰 수명은 SwiftUI 소유라 weak.
    @ObservationIgnored private weak var attachedView: SCNView?
    @ObservationIgnored private var modelExtent: CGFloat = 1
    @ObservationIgnored private var greetingClearTask: Task<Void, Never>?
    /// 리액션 재생이 끝나면 FPS 를 유휴(8)로 되돌리는 태스크. 새 리액션이 들어오면 다시 스케줄된다.
    @ObservationIgnored private var fpsResetTask: Task<Void, Never>?
    /// 자는 동안 💤 를 주기적으로 방출하는 반복 태스크(3.5초 주기). 깨거나 인터럽트되면 취소된다.
    @ObservationIgnored private var zzzTask: Task<Void, Never>?

    /// A3: 넛지 자동 근무 시작 시 다음 commuteStart 말풍선을 1회 덮어쓰는 오버라이드. perform(.commuteStart)이
    /// 소비하며 nil 로 비워, 뒤이은 수동 시작은 평소 "오늘도 화이팅!"으로 돌아간다. 관찰 대상 아님(설정→소비만).
    struct CommuteStartOverride: Equatable {
        let text: String
        let seconds: Double
    }
    @ObservationIgnored var commuteStartBubbleOverride: CommuteStartOverride?

    // MARK: - A2 잘 때 감은 눈(재질 텍스처 교체)
    /// 캐릭터 diffuse 재질 참조(attach 시 확보). 재질은 지오메트리(→노드→씬)가 소유하므로 weak.
    @ObservationIgnored private weak var eyeMaterial: SCNMaterial?
    /// 평상시(눈 뜬) diffuse 콘텐츠 원본. setEyesClosed(false) 에서 이 값으로 원복한다.
    @ObservationIgnored private var eyeOpenContents: Any?
    /// 눈 감은 텍스처 생성의 입력이 되는 원본 CGImage(다운스케일된 512²). 첫 sleeping 진입 시 1회 변형에 쓴다.
    @ObservationIgnored private var eyeSourceImage: CGImage?
    /// 1회 생성·캐시한 "감은 눈" 변형 텍스처. sleeping 동안 재질에 얹고, 깨면 eyeOpenContents 로 원복한다.
    @ObservationIgnored private var closedEyesImage: CGImage?

    // MARK: - A1 히트 영역(캐릭터 몸체 투영 rect 캐시)
    /// 캐릭터 노드 bbox 8코너를 뷰로 투영해 만든 몸체 화면영역(뷰 로컬, 12pt 인플레이트). attach 시 무효화하고
    /// 첫 조회 때 지연 계산한다. 뷰 로컬 투영은 패널 위치와 무관하게 안정적이라(카메라·모델 고정) 재배치/드래그로는
    /// 바뀌지 않는다 — 그래서 프레임당 재계산 없이 캐시 1개면 충분하다(관찰 무효화 최소화 규약).
    @ObservationIgnored private var cachedBodyViewRect: NSRect?

    private static let reactionActionKey = "check.reaction"
    private static let confettiNodeName = "check.reaction.confetti"
    private static let zzzNodeName = "check.reaction.zzz"

    init(clock: @escaping () -> Date = { Date() }) {
        self.clock = clock
    }

    /// wrapper 노드와 씬 루트를 연결한다(makeNSView 에서 호출). modelExtent 로 동작 크기를 모델 규모에 맞춘다.
    ///
    /// 지연 생성(래치) 때문에 attach 는 updateWorking(true) 의 `request(.commuteStart)` 보다 늦게 실행된다.
    /// 그 사이 걸린 리액션의 SCNAction 을 여기서 재생해 첫 출근 폴짝이 소실되지 않게 하고(말풍선/색종이는
    /// 이미 관찰 상태·자체 타이머로 살아 있어 재발화하지 않는다), sleeping 이면 가라앉은 포즈를 복원한다.
    func attach(node: SCNNode, sceneRoot: SCNNode, view: SCNView?) {
        self.reactionNode = node
        self.sceneRoot = sceneRoot
        self.attachedView = view
        let (minB, maxB) = node.boundingBox
        let extent = CGFloat(max(maxB.x - minB.x, max(maxB.y - minB.y, maxB.z - minB.z)))
        modelExtent = extent > 0 ? extent : 1
        captureEyeMaterial(in: node) // A2: 눈 감은 텍스처 교체를 위해 diffuse 재질 참조 확보.
        cachedBodyViewRect = nil     // A1: 새 뷰/노드 → 몸체 투영 캐시 무효화(다음 조회에 지연 계산).

        switch state {
        case .playing(let kind):
            if let action = reactionAction(for: kind) {
                runReaction(action)
            }
            setRenderFPS(Self.activeFPS)
        case .sleeping:
            resetPose()
            node.runAction(ReactionActions.drowsySink(tilt: modelExtent * 0.18), forKey: Self.reactionActionKey)
            setEyesClosed(true) // 복원된 sleeping 이면 감은 눈 상태를 유지한다.
            setRenderFPS(Self.idleFPS)
        case .idle:
            setRenderFPS(Self.idleFPS)
        }
    }

    /// kind 별 이동/변형 SCNAction 을 만든다(말풍선·색종이 제외 — 순수 동작만). attach 재생·perform 이 공유한다.
    private func reactionAction(for kind: ReactionKind) -> SCNAction? {
        switch kind {
        case .hit:
            return ReactionActions.hit()
        case .commuteStart:
            return ReactionActions.commuteStart(hop: modelExtent * 0.32)
        case .commuteEnd:
            return ReactionActions.commuteEnd()
        case .milestone:
            return ReactionActions.milestone(hop: modelExtent * 0.28)
        case .greeting:
            return ReactionActions.greetingNod()
        case .wake:
            return ReactionActions.wake(tilt: modelExtent * 0.18)
        case .drowsy:
            return nil
        }
    }

    /// 렌더 FPS 를 설정한다(뷰가 아직 attach 되지 않았으면 no-op — attach 시점에 상태에 맞춰 다시 잡힌다).
    private func setRenderFPS(_ fps: Int) {
        attachedView?.preferredFramesPerSecond = fps
    }

    /// `seconds` 뒤 상태가 여전히 idle/sleeping 이면 FPS 를 유휴(8)로 되돌린다. 리액션이 이어지면 새로 스케줄된다.
    private func scheduleFPSReset(after seconds: TimeInterval) {
        fpsResetTask?.cancel()
        fpsResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            switch self.state {
            case .idle, .sleeping:
                self.setRenderFPS(Self.idleFPS)
            case .playing:
                break
            }
        }
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
            // A6: 근무종료 인사(commuteEnd) 재생 중 즉시 재시작하면 동순위(3)라 등장 폴짝이 거부되고
            //     "수고했어!" 말풍선이 잔류한다 — 이 방향만 우선순위 검사를 우회해 인터럽트 후 수용한다.
            guard active == .commuteEnd, kind == .commuteStart else {
                return false
            }
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

        setRenderFPS(Self.activeFPS)
        scheduleFPSReset(after: kind.duration + 0.1)
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
            if let override = commuteStartBubbleOverride {
                // A3: 넛지 자동 시작이면 안내 문구/시간으로 1회 교체하고 오버라이드를 소비한다.
                showBubble(override.text, seconds: override.seconds)
                commuteStartBubbleOverride = nil
            } else {
                showBubble("오늘도 화이팅!", seconds: Self.commuteStartBubbleSeconds)
            }
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
        fpsResetTask?.cancel()
        setRenderFPS(Self.idleFPS)
        if let node = reactionNode {
            resetPose()
            node.runAction(ReactionActions.drowsySink(tilt: modelExtent * 0.18), forKey: Self.reactionActionKey)
        }
        setEyesClosed(true) // A2: 잠들면 눈을 감는다(첫 진입 시 변형 텍스처를 1회 지연 생성·캐시).
        startZzzLoop()
    }

    /// 졸기 종료(잠 상태만 해제 — 포즈는 호출측이 처리). zzzTask 취소 + 💤 노드 정리 + 감은 눈 원복.
    /// 마일스톤/근무종료 인터럽트는 이후 runReaction(resetPose 포함)이 포즈를 복원한다.
    private func endSleep() {
        isSleeping = false
        zzzTask?.cancel()
        zzzTask = nil
        removeTransientNodes()
        setEyesClosed(false) // A2: 깨거나 인터럽트되면 눈을 다시 뜬다(모든 sleep 이탈 경로 공통).
    }

    /// 자는 중 클릭으로 깨우기: 화들짝(현재 숙인 자세에서 스냅 복원 + 살짝 튀어오름) + "깜빡 졸았다!".
    /// resetPose 를 거치지 않고 현재(숙인) 트랜스폼에서 애니메이션해 자연스럽게 튀어오르게 한다.
    private func beginWake(now: Date) {
        endSleep()
        activeKind = .wake
        activeUntil = now.addingTimeInterval(ReactionKind.wake.duration)
        setRenderFPS(Self.activeFPS)
        scheduleFPSReset(after: 0.5)
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

    // MARK: - A2 잘 때 감은 눈(재질 텍스처 교체)

    /// attach 시 캐릭터 지오메트리에서 diffuse 텍스처를 가진 첫 재질을 찾아 참조/원본을 확보한다.
    /// (단일 메시·단일 재질 모델이지만 방어적으로 순회한다.) 텍스처가 없으면 조용히 넘어간다(감은 눈 비활성).
    private func captureEyeMaterial(in node: SCNNode) {
        guard eyeMaterial == nil else { return } // 첫 attach 에서만 확보(재-attach 시 원복 상태 보존).
        var found: SCNMaterial?
        node.enumerateHierarchy { child, stop in
            for material in child.geometry?.materials ?? [] {
                if Self.cgImage(from: material.diffuse.contents) != nil {
                    found = material
                    stop.pointee = true
                    return
                }
            }
        }
        guard let material = found else { return }
        eyeMaterial = material
        eyeOpenContents = material.diffuse.contents
        eyeSourceImage = Self.cgImage(from: material.diffuse.contents)
    }

    /// 잠들 때/깰 때 diffuse 텍스처를 감은 눈 변형본↔원본으로 교체한다. 재질 미확보(헤드리스)면 no-op.
    /// 변형본은 첫 호출 시 1회 생성해 캐시한다(512²라 수십 ms — 메인 스레드 허용).
    func setEyesClosed(_ closed: Bool) {
        guard let material = eyeMaterial else { return }
        if closed {
            if closedEyesImage == nil, let source = eyeSourceImage {
                closedEyesImage = SleepEyeTexture.makeClosedEyes(from: source)
            }
            if let closedEyesImage {
                material.diffuse.contents = closedEyesImage
            }
        } else if let eyeOpenContents {
            material.diffuse.contents = eyeOpenContents
        }
    }

    /// 재질 콘텐츠(CGImage/NSImage/파일·아카이브 URL/경로)를 CGImage 로 정규화한다. 알 수 없으면 nil.
    /// 아카이브 URL 디코딩·다운스케일은 CheckCharacter3DScene 이 이미 처리하므로 여기선 CGImage/NSImage 위주다.
    static func cgImage(from contents: Any?) -> CGImage? {
        guard let contents else { return nil }
        if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
            return (contents as! CGImage)
        }
        if let image = contents as? NSImage {
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        // URL/경로 등은 씬 로드 시 이미 CGImage 로 다운스케일되므로 일반 경로에선 도달하지 않는다.
        return CheckCharacter3DScene.downscaledTexture(contents, maxDimension: 512)
    }

    // MARK: - A1 캐릭터 몸체 히트 판정(투영 프리체크 + 지오메트리 hitTest)

    /// 몸체 히트 판정을 할 수 있는 상태인지: 뷰가 attach 되고 창에 올라와 있어야 한다(지연 마운트 전엔 false → 통과).
    var hasAttachedView: Bool {
        attachedView?.window != nil
    }

    /// 화면 좌표 `screenPoint` 가 캐릭터 "몸체"(실제 지오메트리) 위인지. 2단 판정:
    /// (1) 캐시된 투영 bbox(뷰 로컬, 12pt 인플레이트) 프리체크 — 화면 어디를 움직여도 값싼 rect 검사로 걸러
    ///     대부분의 이동에서 hitTest 를 피한다. (2) 통과한 점만 SCNView.hitTest 로 지오메트리 정밀 확정.
    /// 뷰가 없거나(지연 마운트) 창이 없으면 항상 false(완전 통과).
    func isBodyAtScreenPoint(_ screenPoint: NSPoint) -> Bool {
        guard let view = attachedView, let window = view.window else { return false }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let local = view.convert(windowPoint, from: nil)
        if let rect = projectedBodyViewRect(in: view), rect.contains(local) == false {
            return false // 프리체크 탈락(투영 rect 계산 실패 시엔 통과시켜 hitTest 로 확정).
        }
        let hits = view.hitTest(local, options: [
            .rootNode: reactionNode as Any,      // 캐릭터 서브트리만(색종이·💤 노드 제외).
            .boundingBoxOnly: false,             // 지오메트리 정밀.
            .ignoreHiddenNodes: true
        ])
        return hits.isEmpty == false
    }

    /// 캐릭터 노드 bbox 8코너를 뷰로 투영해 만든 몸체 영역(뷰 로컬, bob/sway 대비 12pt 인플레이트). 1회 계산 후 캐시.
    /// 투영은 카메라·모델이 고정이라 패널 위치와 무관하게 안정적이므로 재배치/드래그로 무효화할 필요가 없다.
    private func projectedBodyViewRect(in view: SCNView) -> NSRect? {
        if let cachedBodyViewRect { return cachedBodyViewRect }
        guard let node = reactionNode, view.bounds.width > 1, view.bounds.height > 1 else { return nil }
        let (minB, maxB) = node.boundingBox
        let corners = [
            SCNVector3(minB.x, minB.y, minB.z), SCNVector3(maxB.x, minB.y, minB.z),
            SCNVector3(minB.x, maxB.y, minB.z), SCNVector3(maxB.x, maxB.y, minB.z),
            SCNVector3(minB.x, minB.y, maxB.z), SCNVector3(maxB.x, minB.y, maxB.z),
            SCNVector3(minB.x, maxB.y, maxB.z), SCNVector3(maxB.x, maxB.y, maxB.z)
        ]
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for corner in corners {
            let world = node.convertPosition(corner, to: nil)
            let projected = view.projectPoint(world)
            minX = min(minX, CGFloat(projected.x)); maxX = max(maxX, CGFloat(projected.x))
            minY = min(minY, CGFloat(projected.y)); maxY = max(maxY, CGFloat(projected.y))
        }
        guard maxX > minX, maxY > minY else { return nil }
        let rect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -12, dy: -12)
        cachedBodyViewRect = rect
        return rect
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

    /// 💤 표현용 "Z" 텍스트 지오메트리(흰색 반투명, unlit). SCNGeometry 는 참조 타입이라 노드 간 공유해도
    /// 안전하다(노드별 scale/opacity 는 노드 속성). 매 방출마다 SCNText 를 재테셀레이션하지 않도록 1회만 만든다.
    /// 생성 후 읽기만 하며 모든 접근이 메인 스레드(ReactionEngine·테스트 모두 @MainActor)라 unsafe 공유가 안전하다.
    nonisolated(unsafe) private static let sharedZText: SCNText = {
        let text = SCNText(string: "Z", extrusionDepth: 0)
        text.font = NSFont.systemFont(ofSize: 1, weight: .bold)
        text.flatness = 0.1
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = NSColor.white.withAlphaComponent(0.85)
        material.isDoubleSided = true
        text.materials = [material]
        return text
    }()

    /// 💤 표현용 "Z" 노드(흰색 반투명, unlit). 공유 지오메트리를 얹고 스케일만 노드별로 지정한다.
    static func makeZNode(extent: CGFloat) -> SCNNode {
        let node = SCNNode(geometry: sharedZText)
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

/// A2: 캐릭터 diffuse 텍스처(512²)로부터 "감은 눈" 변형 텍스처를 만드는 순수 이미지 처리기.
///
/// USDZ 파일은 절대 건드리지 않고, 로드된 텍스처(CGImage)만 오프스크린으로 변형한다. 눈 조각은 UV 차트에서
/// 2~4개로 흩어져 있어(실측: 큰 눈 + 우하단·우상단 파편) 좌표를 하드코딩하지 않고 "어두운·비적색 픽셀" 시드로
/// connected-components 탐지한다. 각 눈 클러스터를 주변 피부색으로 인페인트한 뒤, 클러스터 픽셀 분포의
/// PCA 주축을 따라 직선 "감은 선"을 그린다(호가 아닌 직선인 이유: UV 차트 회전 부호가 모호해 호 방향을
/// 정할 수 없고, 140pt 패널 표시 크기에선 직선이 감은 눈으로 충분히 읽힌다).
enum SleepEyeTexture {
    /// 눈 시드 판정 파라미터. 이 캐릭터의 눈은 "브라운 홍채 + 검은 동공/외곽"이라, 순수 어두움(max<90)만
    /// 보면 홍채를 놓쳐(적갈로 걸러져) 감은 눈이 거의 읽히지 않았다(오프스크린 렌더로 확인). 그래서
    /// "어두운 편(max<brightMax)이며 (따뜻한 브라운: r>b+warmMargin  또는  아주 어두운 검정: max<blackMax)"으로
    /// 눈을 잡되, 라벤더 피부(b가 우세)·밝은 분홍 볼(max 큼)은 배제한다.
    private static let brightMax = 150     // max(r,g,b) < 150 이면 어두운 편(밝은 볼·피부 배제).
    private static let warmMargin = 8      // r > b + 8 이면 따뜻한 브라운(홍채) — 라벤더(b 우세) 배제.
    private static let blackMax = 70       // max(r,g,b) < 70 이면 검은 픽셀(동공/외곽) — 색과 무관하게 포함.
    private static let alphaMin = 40       // 투명 영역 제외.
    private static let dilateRadius = 3    // 클러스터 bbox 확장(내부 흰 하이라이트 포함 + 인페인트 여유).

    /// 원본 diffuse CGImage 로부터 감은 눈 변형본을 만든다. 눈을 못 찾거나 실패하면 nil(재질 원복 유지).
    static func makeClosedEyes(from source: CGImage) -> CGImage? {
        let width = source.width, height = source.height
        guard width >= 32, height >= 32 else { return nil }
        let count = width * height * 4
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        defer { ptr.deallocate() }
        ptr.initialize(repeating: 0, count: count)
        guard let ctx = CGContext(
            data: ptr, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        let buffer = UnsafeMutableBufferPointer(start: ptr, count: count)
        // 눈은 UV 아틀라스에서 여러 조각으로 흩어져 있다. 검출된 모든 눈 조각(라벤더 얼굴에 박힌 어두운·브라운)을 모아
        // 팽창(dilate)한 마스크를 피부색으로 덮어 눈을 통째로 지운다(작은 조각·외곽선까지 확실히 — 기울인 포즈에서
        // "뜬 눈" 잔여가 안 남게). 그 뒤 큰 그룹(=실제 눈)마다 PCA 감은 선을 한 번씩 그린다.
        let allClusters = detectClusters(buffer, width: width, height: height)
        guard allClusters.isEmpty == false else { return nil }
        // 전역 라벤더 피부색: 눈이 아틀라스 모서리에 있으면 지역 링이 텍스처 밖(투명)이라 못 구한다 → 전체 중앙값으로 덮는다.
        let globalSkin = globalSkinColor(buffer, width: width, height: height) ?? (r: 200, g: 190, b: 230, a: 255)
        // 감은 선 색(눈의 어두운 중앙값)은 지우기 전에 미리 읽는다.
        let groups = eyeGroups(allClusters, gap: max(8, max(width, height) / 24), imagePixelCount: width * height)
        let lineColors = groups.map { medianColor(of: $0.pixels, buffer: buffer, width: width) }
        // 1) 지우기: 모든 눈 조각의 합집합을 팽창해 피부색으로 덮는다.
        fillEyeMask(buffer, width: width, height: height, clusters: allClusters,
                    skin: globalSkin, radius: max(4, max(width, height) / 64))
        // 2) 감은 선: 주요 눈 그룹마다 PCA 주축을 따라 직선.
        for (group, dark) in zip(groups, lineColors) {
            drawClosedLine(buffer, width: width, height: height, cluster: group,
                           color: dark ?? (r: 60, g: 50, b: 70, a: 255))
        }
        return ctx.makeImage()
    }

    // MARK: - 클러스터 탐지 (테스트도 사용)

    struct Cluster {
        var pixels: [(x: Int, y: Int)]
        var minX: Int, minY: Int, maxX: Int, maxY: Int
        var centroid: (x: Double, y: Double)
    }

    /// 어두운·비적색 시드를 connected-components(8-이웃)로 묶어 노이즈(면적 하한 미만)를 걸러 돌려준다.
    static func detectClusters(in image: CGImage) -> [Cluster] {
        let width = image.width, height = image.height
        guard width >= 32, height >= 32 else { return [] }
        let count = width * height * 4
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        defer { ptr.deallocate() }
        ptr.initialize(repeating: 0, count: count)
        guard let ctx = CGContext(
            data: ptr, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return detectClusters(UnsafeMutableBufferPointer(start: ptr, count: count), width: width, height: height)
    }

    private static func detectClusters(_ buffer: UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int) -> [Cluster] {
        let pixelCount = width * height
        var seed = [Bool](repeating: false, count: pixelCount)
        for i in 0..<pixelCount {
            let r = Int(buffer[i * 4]), g = Int(buffer[i * 4 + 1]), b = Int(buffer[i * 4 + 2]), a = Int(buffer[i * 4 + 3])
            guard a > alphaMin else { continue }
            let maxc = max(r, max(g, b))
            // 어두운 편 && (아주 어두운 검정  ||  따뜻한 브라운 홍채). 브라운은 r>b 이면서 g가 b 밑으로
            // 크게 내려가지 않는다(g+4>=b) — 이 조건이 라벤더 피부(b 우세)와 채도 높은 빨강 파편(g<b)을 함께 배제한다.
            if maxc < brightMax, maxc < blackMax || (r > b + warmMargin && g + 4 >= b) {
                seed[i] = true
            }
        }
        // 면적 하한: 이미지 크기에 비례(512² 기준 ~21px). 눈 조각을 넉넉히 잡아 꽉 덮되 점 노이즈는 거른다.
        let minArea = max(8, pixelCount / 12_000)
        var visited = [Bool](repeating: false, count: pixelCount)
        var clusters: [Cluster] = []
        var stack: [Int] = []
        for start in 0..<pixelCount where seed[start] && !visited[start] {
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true
            var pixels: [(x: Int, y: Int)] = []
            var minX = width, minY = height, maxX = 0, maxY = 0
            while let idx = stack.popLast() {
                let x = idx % width, y = idx / width
                pixels.append((x, y))
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let nIdx = ny * width + nx
                        if seed[nIdx], !visited[nIdx] {
                            visited[nIdx] = true
                            stack.append(nIdx)
                        }
                    }
                }
            }
            guard pixels.count >= minArea else { continue }
            // 눈만 남긴다: 클러스터를 둘러싼 링이 라벤더 피부(파랑 우세)일 때만 채택한다. 눈은 얼굴(라벤더)에
            // 박혀 있지만, UV 아틀라스 위쪽의 빨강·흰 파편(머리 위·등)은 라벤더에 둘러싸이지 않는다 —
            // 좌표를 하드코딩하지 않고 "얼굴 위 눈"만 고르는 판별식이다.
            let ex0 = max(0, minX - dilateRadius), ey0 = max(0, minY - dilateRadius)
            let ex1 = min(width - 1, maxX + dilateRadius), ey1 = min(height - 1, maxY + dilateRadius)
            guard let ring = medianRingColor(buffer, width: width, height: height, x0: ex0, y0: ey0, x1: ex1, y1: ey1, ring: 4),
                  ring.b > ring.r + 4, ring.b > ring.g + 4 else { continue }
            let sx = pixels.reduce(0.0) { $0 + Double($1.x) }
            let sy = pixels.reduce(0.0) { $0 + Double($1.y) }
            let n = Double(pixels.count)
            clusters.append(Cluster(
                pixels: pixels, minX: minX, minY: minY, maxX: maxX, maxY: maxY,
                centroid: (sx / n, sy / n)
            ))
        }
        return clusters
    }

    /// 눈 조각을 그룹으로 합친 뒤(mergedGroups), "눈 최소 면적"(512² 기준 ~105px) 미만인 고립 스펙만 버린다.
    /// 상대(최대 대비) 기준은 아틀라스에 비정상적으로 큰 눈 조각이 하나 있으면 임계를 밀어 올려 다른 눈 조각까지
    /// 버리므로, 절대 하한을 쓴다(눈은 이 크기 이상, 점 노이즈·눈썹 파편은 미만). 낮은 검출 하한(꽉 덮기)과
    /// 적은 변경 덩어리 수를 동시에 만족시키는 지점이다.
    static func eyeGroups(_ clusters: [Cluster], gap: Int, imagePixelCount: Int) -> [Cluster] {
        let groups = mergedGroups(clusters, gap: gap)
        let threshold = max(24, imagePixelCount / 2_500)
        return groups.filter { $0.pixels.count >= threshold }
    }

    /// 서로 bbox 가 `gap` 이내로 가까운 눈 조각을 한 눈으로 합친다(union-find). 흩어진 UV 조각을 하나의
    /// 감은 눈으로 렌더해 변경 덩어리가 과하게 늘지 않게 한다.
    static func mergedGroups(_ clusters: [Cluster], gap: Int) -> [Cluster] {
        guard clusters.isEmpty == false else { return [] }
        var parent = Array(0..<clusters.count)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }
            return r
        }
        for i in 0..<clusters.count {
            for j in (i + 1)..<clusters.count where bboxGap(clusters[i], clusters[j]) <= gap {
                parent[find(i)] = find(j)
            }
        }
        var byRoot: [Int: [Int]] = [:]
        for i in 0..<clusters.count { byRoot[find(i), default: []].append(i) }
        return byRoot.values.map { indices in
            var pixels: [(x: Int, y: Int)] = []
            var minX = Int.max, minY = Int.max, maxX = 0, maxY = 0
            for k in indices {
                let c = clusters[k]
                pixels.append(contentsOf: c.pixels)
                minX = min(minX, c.minX); minY = min(minY, c.minY)
                maxX = max(maxX, c.maxX); maxY = max(maxY, c.maxY)
            }
            let n = Double(max(1, pixels.count))
            let sx = pixels.reduce(0.0) { $0 + Double($1.x) }
            let sy = pixels.reduce(0.0) { $0 + Double($1.y) }
            return Cluster(pixels: pixels, minX: minX, minY: minY, maxX: maxX, maxY: maxY, centroid: (sx / n, sy / n))
        }
    }

    /// 두 클러스터 bbox 사이의 최소 간격(겹치면 0). x·y 간격 중 큰 값을 쓴다(대각으로만 가까운 것은 안 합침).
    private static func bboxGap(_ a: Cluster, _ b: Cluster) -> Int {
        let dx = max(0, max(a.minX - b.maxX, b.minX - a.maxX))
        let dy = max(0, max(a.minY - b.maxY, b.minY - a.maxY))
        return max(dx, dy)
    }

    // MARK: - 지우기(인페인트) + 감은 선 그리기

    /// 검출된 모든 눈 조각의 bbox 를 `pad` 만큼 넓혀 피부색으로 덮는다(조각 내부의 성긴 틈까지 통째로 — 흩어진
    /// seed 를 픽셀 단위로만 지우면 사이에 남는 홍채·중간톤이 기울인 포즈에서 "뜬 눈"으로 드러나기 때문). 작은
    /// 조각까지 모두 포함하고 얼굴이 균일한 라벤더라, 사각 채움이라도 경계가 티 나지 않는다.
    private static func fillEyeMask(_ buffer: UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int, clusters: [Cluster], skin globalSkin: RGBA, radius pad: Int) {
        for cluster in clusters {
            let x0 = max(0, cluster.minX - pad), y0 = max(0, cluster.minY - pad)
            let x1 = min(width - 1, cluster.maxX + pad), y1 = min(height - 1, cluster.maxY + pad)
            // 지역 라벤더 피부색(bbox 바깥 링에서 라벤더만 골라 중앙값)으로 채워 주변 음영과 맞춘다 → 사각 패치가
            // 덜 튄다. 라벤더 이웃이 없으면(아틀라스 모서리) 전역 라벤더로 폴백한다.
            let skin = localLavenderSkin(buffer, width: width, height: height, x0: x0, y0: y0, x1: x1, y1: y1) ?? globalSkin
            for y in y0...y1 {
                for x in x0...x1 {
                    setPixel(buffer, index: y * width + x, color: skin)
                }
            }
        }
    }

    /// bbox 바깥 링(폭 6)에서 "라벤더 피부"(파랑 우세·중간 밝기) 픽셀만 골라 중앙값 색을 구한다. 없으면 nil.
    private static func localLavenderSkin(_ buffer: UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int, x0: Int, y0: Int, x1: Int, y1: Int) -> RGBA? {
        var rs = [Int](), gs = [Int](), bs = [Int]()
        let ring = 6
        let rx0 = max(0, x0 - ring), ry0 = max(0, y0 - ring)
        let rx1 = min(width - 1, x1 + ring), ry1 = min(height - 1, y1 + ring)
        for y in ry0...ry1 {
            for x in rx0...rx1 where (x < x0 || x > x1 || y < y0 || y > y1) {
                let i = (y * width + x) * 4
                let r = Int(buffer[i]), g = Int(buffer[i + 1]), b = Int(buffer[i + 2]), a = Int(buffer[i + 3])
                let maxc = max(r, max(g, b))
                if a > alphaMin, b > r + 2, b > g - 4, maxc > 110 { // 라벤더만.
                    rs.append(r); gs.append(g); bs.append(b)
                }
            }
        }
        guard rs.count >= 8 else { return nil }
        rs.sort(); gs.sort(); bs.sort()
        let m = rs.count / 2
        return (rs[m], gs[m], bs[m], 255)
    }

    /// 클러스터 픽셀 분포의 PCA 주축을 따라 중심에 직선 "감은 선"(둥근 캡)을 그린다. 호가 아닌 직선인 이유:
    /// UV 차트 회전 부호가 모호해 호 방향을 정할 수 없고, 140pt 패널 크기에선 직선이 감은 눈으로 충분히 읽힌다.
    private static func drawClosedLine(_ buffer: UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int, cluster: Cluster, color: RGBA) {
        let pca = principalAxis(of: cluster.pixels, centroid: cluster.centroid)
        // 선 길이·두께 상한: 아틀라스에서 비정상적으로 큰 눈 조각(작은 화면 눈에 매핑)은 PCA span 이 커서 두꺼운
        // 막대가 되어 "뜬 눈"처럼 보인다. 텍스처 대비 작은 절대 상한(길이 ≤ maxSpan, 두께 ≤ maxThick)으로 캡해
        // 어느 조각이든 화면에서 가느다란 감은 선으로 읽히게 한다.
        let maxSpan = Double(max(width, height)) / 13      // 512 기준 ~39px.
        let span = min(pca.principalSpan, maxSpan)
        let half = span / 2
        let ax = cluster.centroid.x - pca.dir.0 * half, ay = cluster.centroid.y - pca.dir.1 * half
        let bx = cluster.centroid.x + pca.dir.0 * half, by = cluster.centroid.y + pca.dir.1 * half
        let halfT = min(3.5, max(2.0, pca.minorSpan * 0.30) / 2)
        let margin = Int(halfT.rounded(.up)) + 1
        let lx0 = max(0, cluster.minX - margin), ly0 = max(0, cluster.minY - margin)
        let lx1 = min(width - 1, cluster.maxX + margin), ly1 = min(height - 1, cluster.maxY + margin)
        for y in ly0...ly1 {
            for x in lx0...lx1 where distanceToSegment(px: Double(x), py: Double(y), ax: ax, ay: ay, bx: bx, by: by) <= halfT {
                setPixel(buffer, index: y * width + x, color: color)
            }
        }
    }

    private typealias RGBA = (r: Int, g: Int, b: Int, a: Int)

    private static func setPixel(_ buffer: UnsafeMutableBufferPointer<UInt8>, index: Int, color: RGBA) {
        buffer[index * 4] = UInt8(clamping: color.r)
        buffer[index * 4 + 1] = UInt8(clamping: color.g)
        buffer[index * 4 + 2] = UInt8(clamping: color.b)
        buffer[index * 4 + 3] = UInt8(clamping: color.a)
    }

    private static func medianColor(of pixels: [(x: Int, y: Int)], buffer: UnsafeMutableBufferPointer<UInt8>, width: Int) -> RGBA? {
        guard pixels.isEmpty == false else { return nil }
        var rs = [Int](), gs = [Int](), bs = [Int]()
        rs.reserveCapacity(pixels.count); gs.reserveCapacity(pixels.count); bs.reserveCapacity(pixels.count)
        for p in pixels {
            let i = (p.y * width + p.x) * 4
            rs.append(Int(buffer[i])); gs.append(Int(buffer[i + 1])); bs.append(Int(buffer[i + 2]))
        }
        rs.sort(); gs.sort(); bs.sort()
        let m = rs.count / 2
        return (rs[m], gs[m], bs[m], 255)
    }

    /// 텍스처 전체에서 라벤더 피부(파랑 우세·중간 밝기) 픽셀의 중앙값 색을 구한다(모서리 눈 인페인트 폴백).
    private static func globalSkinColor(_ buffer: UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int) -> RGBA? {
        var rs = [Int](), gs = [Int](), bs = [Int]()
        let pixelCount = width * height
        for i in stride(from: 0, to: pixelCount, by: 4) { // 4픽셀 간격 샘플(충분·빠름).
            let r = Int(buffer[i * 4]), g = Int(buffer[i * 4 + 1]), b = Int(buffer[i * 4 + 2]), a = Int(buffer[i * 4 + 3])
            guard a > alphaMin else { continue }
            let maxc = max(r, max(g, b))
            if b > r + 4, b > g + 4, maxc > 120, maxc < 245 {
                rs.append(r); gs.append(g); bs.append(b)
            }
        }
        guard rs.isEmpty == false else { return nil }
        rs.sort(); gs.sort(); bs.sort()
        let m = rs.count / 2
        return (rs[m], gs[m], bs[m], 255)
    }

    /// 확장 bbox 바깥 한 겹(ring 폭)에서 불투명 픽셀의 중앙값 색(피부 라벤더)을 구한다.
    private static func medianRingColor(_ buffer: UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int, x0: Int, y0: Int, x1: Int, y1: Int, ring: Int) -> RGBA? {
        var rs = [Int](), gs = [Int](), bs = [Int]()
        let rx0 = max(0, x0 - ring), ry0 = max(0, y0 - ring)
        let rx1 = min(width - 1, x1 + ring), ry1 = min(height - 1, y1 + ring)
        for y in ry0...ry1 {
            for x in rx0...rx1 where (x < x0 || x > x1 || y < y0 || y > y1) {
                let i = (y * width + x) * 4
                guard Int(buffer[i + 3]) > alphaMin else { continue }
                rs.append(Int(buffer[i])); gs.append(Int(buffer[i + 1])); bs.append(Int(buffer[i + 2]))
            }
        }
        guard rs.isEmpty == false else { return nil }
        rs.sort(); gs.sort(); bs.sort()
        let m = rs.count / 2
        return (rs[m], gs[m], bs[m], 255)
    }

    /// 클러스터 픽셀 분포의 PCA 주축 방향과 주축/부축 span.
    private static func principalAxis(of pixels: [(x: Int, y: Int)], centroid: (x: Double, y: Double)) -> (dir: (Double, Double), principalSpan: Double, minorSpan: Double) {
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in pixels {
            let dx = Double(p.x) - centroid.x, dy = Double(p.y) - centroid.y
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        let n = Double(max(1, pixels.count))
        sxx /= n; syy /= n; sxy /= n
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        let dir = (cos(theta), sin(theta))
        let perp = (-sin(theta), cos(theta))
        var minP = Double.greatestFiniteMagnitude, maxP = -Double.greatestFiniteMagnitude
        var minQ = Double.greatestFiniteMagnitude, maxQ = -Double.greatestFiniteMagnitude
        for p in pixels {
            let dx = Double(p.x) - centroid.x, dy = Double(p.y) - centroid.y
            let projP = dx * dir.0 + dy * dir.1
            let projQ = dx * perp.0 + dy * perp.1
            minP = min(minP, projP); maxP = max(maxP, projP)
            minQ = min(minQ, projQ); maxQ = max(maxQ, projQ)
        }
        return (dir, max(2, maxP - minP), max(1, maxQ - minQ))
    }

    private static func distanceToSegment(px: Double, py: Double, ax: Double, ay: Double, bx: Double, by: Double) -> Double {
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        guard len2 > 1e-9 else { return hypot(px - ax, py - ay) }
        var t = ((px - ax) * dx + (py - ay) * dy) / len2
        t = max(0, min(1, t))
        return hypot(px - (ax + t * dx), py - (ay + t * dy))
    }

    // MARK: - 변경 통계 (결정적 검증)

    /// 원본과 변형본의 픽셀 차이를 마스크로 만들고, connected-components(변경 덩어리 수)와 변경 픽셀 비율을 돌려준다.
    /// 감은 눈 변형이 과소/과대가 아닌지(클러스터 2~5개, 변경 면적 0.2~6%)를 결정적으로 검증하는 데 쓴다.
    static func changeStats(original: CGImage, modified: CGImage) -> (clusterCount: Int, changedFraction: Double)? {
        let width = original.width, height = original.height
        guard modified.width == width, modified.height == height, width * height > 0 else { return nil }
        guard let a = rgbaBuffer(original), let b = rgbaBuffer(modified) else { return nil }
        defer { a.deallocate(); b.deallocate() }
        let pixelCount = width * height
        var changed = [Bool](repeating: false, count: pixelCount)
        var changedCount = 0
        for i in 0..<pixelCount {
            let dr = abs(Int(a[i * 4]) - Int(b[i * 4]))
            let dg = abs(Int(a[i * 4 + 1]) - Int(b[i * 4 + 1]))
            let db = abs(Int(a[i * 4 + 2]) - Int(b[i * 4 + 2]))
            if max(dr, max(dg, db)) > 10 {
                changed[i] = true
                changedCount += 1
            }
        }
        // 변경 마스크 8-이웃 CC.
        var visited = [Bool](repeating: false, count: pixelCount)
        var clusterCount = 0
        var stack: [Int] = []
        for start in 0..<pixelCount where changed[start] && !visited[start] {
            clusterCount += 1
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true
            while let idx = stack.popLast() {
                let x = idx % width, y = idx / width
                for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let nIdx = ny * width + nx
                        if changed[nIdx], !visited[nIdx] {
                            visited[nIdx] = true
                            stack.append(nIdx)
                        }
                    }
                }
            }
        }
        return (clusterCount, Double(changedCount) / Double(pixelCount))
    }

    private static func rgbaBuffer(_ image: CGImage) -> UnsafeMutableBufferPointer<UInt8>? {
        let width = image.width, height = image.height
        let count = width * height * 4
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        ptr.initialize(repeating: 0, count: count)
        guard let ctx = CGContext(
            data: ptr, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            ptr.deallocate()
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return UnsafeMutableBufferPointer(start: ptr, count: count)
    }
}
