import AppKit
import CoreGraphics
import Foundation

/// 비근무 상태에서 사용자가 "실제로" 컴퓨터를 쓰는 시간이 최근 10분 창 안에 5분 누적되면 근무 시작을
/// 제안(넛지)하는 스케줄러.
///
/// 프라이버시: 입력 내용은 절대 추적하지 않는다. 보는 것은 `CGEventSource`의 "마지막 입력 후 경과 초"
/// 숫자(권한 불요)와 세션 잠금 여부뿐이며, 그마저도 주입 가능한 클로저 뒤에 있어 테스트는 실제 시스템을
/// 건드리지 않는다.
///
/// 활성 판정은 세 겹이다(v0.2.17 — "안 쓰는데 저절로 근무 시작" 사고 후 강화):
///  1. **의미 있는 입력만 센다** — 키 입력·클릭·스크롤. 마우스 이동 단독은 제외한다. any-input 기준이던
///     시절엔 광마우스 표면 반사 지터·책상 진동 같은 이동 이벤트만으로 '사용 중'이 성립했다.
///  2. **잠금/비콘솔 세션은 세지 않는다** — 잠금 화면 비밀번호 타이핑, 다른 계정 사용(빠른 사용자 전환)은
///     이 사람의 근무가 아니다.
///  3. **10분 창** — 활성 분은 10분이 지나면 소멸한다. 무기한 누적이던 시절엔 몇 시간 간격의 '잠깐 만짐'
///     5번(청소하다 건드림, 알림 확인)이 합산돼 자리에 없는 사람의 근무가 시작됐다(프로브로 실증).
///
/// 유휴 최적화: 감지 루프는 비근무·로그인 상태일 때만(컨트롤러가 start/stop 배선) 60초 주기로 1회 tick 한다
/// (Task.sleep tolerance 10s 로 타이머 coalescing 허용). 시간·자격·발동은 전부 주입으로 결정적이다.
@MainActor
final class NudgeScheduler {
    /// 감지 주기(초). 이 간격마다 활성 여부를 1회 확인한다.
    static let checkInterval: TimeInterval = 60
    /// "실제 사용 중"으로 볼 마지막 의미 있는 입력 후 경과 상한(초). 이보다 오래 조용하면 그 분은 적립하지 않는다.
    static let activeIdleThreshold: TimeInterval = 120
    /// 넛지 발동에 필요한 활성 누적 분.
    static let requiredActiveMinutes = 5
    /// 활성 분의 유효 시간창(초). 이 창을 벗어난 적립은 소멸한다 — "최근 10분 안에 5분을 실제로 썼다"가 계약이다.
    /// 창(10분) > 필요 분(5분) × 주기(1분) 이므로 짧은 자리 비움(누적 5분 미만의 틈)은 여전히 봐준다.
    static let activeWindowSeconds: TimeInterval = 10 * 60
    /// 넛지 후 재제안까지의 쿨다운(초).
    static let cooldownSeconds: TimeInterval = 3600
    /// 부재 재무장 공백(초). 수동 [근무 종료]의 자동 시작 억제는 이만큼의 완전한 공백(잠자기·방치·앱 꺼짐)
    /// 뒤에만 풀린다 — "퇴근 후 계속 쓰는 동안은 다시 출근시키지 않고, 한참 자리를 비웠다 돌아오면
    /// 다음 근무로 본다"는 계약. WorkTimerStore 의 억제 영속 판정도 같은 상수를 쓴다.
    static let rearmGapSeconds: TimeInterval = 60 * 60

    /// 마지막 의미 있는 입력 후 경과 초(주입). 기본은 키/클릭/스크롤 중 가장 최근 값.
    private let idleSeconds: () -> TimeInterval
    /// 현재 시각(주입). 쿨다운·시간창·공백 판정에 쓴다.
    private let clock: () -> Date
    /// 넛지 자격(주입). 로그인됨·팀 있음·비근무·억제 아님 등을 컨트롤러가 store 로 구성한다.
    private let isEligible: () -> Bool
    /// 발동 콜백(주입). 컨트롤러가 자동 근무 시작으로 잇는다.
    private let onNudge: () -> Void
    /// 이 세션이 지금 사람 앞에 있는가(주입). 기본은 화면 잠금 아님 + 콘솔 세션.
    private let isSessionUsable: () -> Bool
    /// 1시간+ 공백 관측 콜백(주입). 컨트롤러가 수동 종료 억제 해제로 잇는다.
    private let onAbsenceGap: () -> Void
    /// 생존 스탬프 콜백(주입). 억제 상태의 영속 재무장 판정(앱이 죽어 있던 시간 측정)에 쓴다.
    private let onAliveTick: (Date) -> Void

    /// 최근 활성 분의 시각들(시간창 내만 유지). 헤드리스 검증 지점.
    private(set) var activeTickTimes: [Date] = []
    /// 시간창 내 활성 누적 분. 헤드리스 검증 지점(기존 테스트 호환 이름).
    var activeMinutes: Int { activeTickTimes.count }
    /// 이 시각 전까지는 카운트하지 않는다(발동 직후 now+쿨다운). 헤드리스 검증 지점.
    private(set) var cooldownUntil: Date = .distantPast
    /// 직전 tick 시각. 루프가 살아 있는 동안의 벽시계 간격으로 잠자기 공백을 잰다.
    /// start() 가 nil 로 되돌린다 — 루프가 꺼져 있던 구간(근무 중)은 공백의 증거가 아니다.
    private var lastTickAt: Date?

    private var loopTask: Task<Void, Never>?
    // 시스템 깨어남 옵저버 토큰(보관). 클로저는 [weak self] 라 스토어 수명으로 자동 무력화된다.
    private var wakeObserver: NSObjectProtocol?

    /// 기본 idle 소스: 마지막 **의미 있는** 입력 후 경과 초. 키 입력·클릭·스크롤만 본다 —
    /// `.mouseMoved` 는 일부러 뺀다(광마우스 지터·책상 진동·이벤트 합성 앱이 이동 이벤트를 만든다).
    nonisolated static func meaningfulIdleSeconds() -> TimeInterval {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }

    /// 기본 세션 판정: 화면이 잠겨 있지 않고 이 세션이 콘솔(실제 화면 앞)에 있다.
    /// 사전 판독이 실패하면 막지 않는다(fail-open) — 판정 불가로 넛지 전체가 죽는 것이 더 나쁘다.
    nonisolated static func consoleSessionUsable() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        // 잠금 키는 잠겼을 때만 나타난다(비잠금 = 키 부재, 실측). NSNumber → Bool 브리징.
        if (session["CGSSessionScreenIsLocked"] as? Bool) == true { return false }
        if let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool, !onConsole { return false }
        return true
    }

    init(
        idleSeconds: @escaping () -> TimeInterval = NudgeScheduler.meaningfulIdleSeconds,
        clock: @escaping () -> Date = { Date() },
        isEligible: @escaping () -> Bool,
        onNudge: @escaping () -> Void,
        isSessionUsable: @escaping () -> Bool = NudgeScheduler.consoleSessionUsable,
        onAbsenceGap: @escaping () -> Void = {},
        onAliveTick: @escaping (Date) -> Void = { _ in },
        workspaceNotifications: NotificationCenter? = NSWorkspace.shared.notificationCenter
    ) {
        self.idleSeconds = idleSeconds
        self.clock = clock
        self.isEligible = isEligible
        self.onNudge = onNudge
        self.isSessionUsable = isSessionUsable
        self.onAbsenceGap = onAbsenceGap
        self.onAliveTick = onAliveTick
        observeWake(workspaceNotifications)
    }

    /// 깨어남 노티를 구독한다("켜진 지 5분"의 의미 보존 — 잠들었다 깨면 활성 누적을 0 으로 리셋).
    private func observeWake(_ center: NotificationCenter?) {
        guard let center else { return }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }
    }

    /// 감지 루프를 켠다(멱등). 비근무·로그인일 때 컨트롤러가 호출한다.
    func start() {
        guard loopTask == nil else { return }
        // 루프가 꺼져 있던 구간(근무 중)을 공백으로 오인하지 않게 간격 측정을 처음부터 시작한다.
        // 이 리셋이 없으면 "아침 출근 → 저녁 [근무 종료]" 의 9시간 근무가 첫 tick 에 '9시간 부재'로 읽혀
        // 방금 세운 수동 종료 억제가 그 자리에서 풀린다(= 퇴근 5분 뒤 자동 재출근, 억제가 무용지물).
        lastTickAt = nil
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // 60초 주기(느슨한 tolerance 로 전력 절감). 첫 tick 도 한 주기 뒤라 켠 직후 즉발하지 않는다.
                try? await Task.sleep(for: .seconds(Self.checkInterval), tolerance: .seconds(10))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    /// 감지 루프를 끄고 활성 누적을 리셋한다(근무 시작 등 자격 상실 시 컨트롤러가 호출).
    func stop() {
        loopTask?.cancel()
        loopTask = nil
        activeTickTimes = []
    }

    /// 한 주기의 판정(주입된 clock/idle 로 결정적). 루프가 매 60초 호출하며, 테스트는 직접 호출한다.
    ///
    /// - 공백 관측: 직전 tick 과의 벽시계 간격(잠자기 동안 Task.sleep 이 멈추므로 간격 = 잠든 시간),
    ///   또는 의미 있는 입력의 idle 자체가 1시간을 넘으면 onAbsenceGap(수동 종료 억제 해제 신호).
    /// - 자격 미충족(로그아웃/근무중/억제/이미 표시중): 활성 누적을 비우고 통과.
    /// - 쿨다운 중: 아무것도 하지 않고 통과(카운트 안 함).
    /// - 잠금/비콘솔: 적립하지 않고 통과(창 밖으로 밀린 옛 적립은 다음 활성 tick 에 정리된다).
    /// - 실제 사용 중(의미 있는 idle < 임계): 지금 시각을 적립. 창(10분) 밖 적립은 소멸.
    /// - 창 안 5분 도달: 발동 + 적립 비움 + 쿨다운(now+1시간) 세팅.
    func tick() {
        let now = clock()
        if let last = lastTickAt, now.timeIntervalSince(last) >= Self.rearmGapSeconds {
            onAbsenceGap()
        }
        if idleSeconds() >= Self.rearmGapSeconds {
            onAbsenceGap()
        }
        lastTickAt = now
        onAliveTick(now)
        guard isEligible() else {
            if !activeTickTimes.isEmpty { activeTickTimes = [] }
            return
        }
        guard now >= cooldownUntil else { return }
        guard isSessionUsable() else { return }
        if idleSeconds() < Self.activeIdleThreshold {
            activeTickTimes.append(now)
        }
        activeTickTimes.removeAll { now.timeIntervalSince($0) > Self.activeWindowSeconds }
        if activeTickTimes.count >= Self.requiredActiveMinutes {
            activeTickTimes = []
            cooldownUntil = now.addingTimeInterval(Self.cooldownSeconds)
            onNudge()
        }
    }

    /// 시스템이 잠에서 깨어남 — 활성 누적을 0 으로 되돌린다(테스트는 직접 호출).
    func handleWake() {
        activeTickTimes = []
    }
}
