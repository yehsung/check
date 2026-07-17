import AppKit
import CoreGraphics
import Foundation

/// 비근무 상태에서 사용자가 "실제로" 컴퓨터를 쓰는 시간이 5분 누적되면 근무 시작을 제안(넛지)하는 스케줄러.
///
/// 프라이버시: 입력 내용은 절대 추적하지 않는다. 유일하게 보는 것은 `CGEventSource`의 "마지막 입력 후 경과 초"
/// 숫자 하나(권한 불요)이며, 그마저도 주입 가능한 `idleSeconds` 클로저 뒤에 있어 테스트는 실제 시스템을 건드리지 않는다.
///
/// 유휴 최적화: 감지 루프는 비근무·로그인 상태일 때만(컨트롤러가 start/stop 배선) 60초 주기로 1회 tick 한다
/// (Task.sleep tolerance 10s 로 타이머 coalescing 허용). 근무중/로그아웃이면 루프가 아예 돌지 않고, 쿨다운/자격
/// 미충족이면 tick 이 즉시 통과한다. 시간·자격·발동은 전부 주입으로 결정적이라 헤드리스로 검증할 수 있다.
@MainActor
final class NudgeScheduler {
    /// 감지 주기(초). 이 간격마다 활성 여부를 1회 확인한다.
    static let checkInterval: TimeInterval = 60
    /// "실제 사용 중"으로 볼 마지막 입력 후 경과 상한(초). 이보다 오래 조용하면 그 분은 적립하지 않는다.
    static let activeIdleThreshold: TimeInterval = 120
    /// 넛지 발동에 필요한 활성 누적 분.
    static let requiredActiveMinutes = 5
    /// 넛지 후 재제안까지의 쿨다운(초).
    static let cooldownSeconds: TimeInterval = 3600

    /// 마지막 입력 후 경과 초(주입). 기본은 실제 시스템 값.
    private let idleSeconds: () -> TimeInterval
    /// 현재 시각(주입). 쿨다운 판정에 쓴다.
    private let clock: () -> Date
    /// 넛지 자격(주입). 로그인됨·팀 있음·비근무·오버레이 켜짐·표시중 아님 등을 컨트롤러가 store 로 구성한다.
    private let isEligible: () -> Bool
    /// 발동 콜백(주입). 컨트롤러가 넛지 표시로 잇는다.
    private let onNudge: () -> Void

    /// 지금까지 적립한 활성 분(발동/자격상실/깨어남 시 0). 헤드리스 검증 지점.
    private(set) var activeMinutes = 0
    /// 이 시각 전까지는 카운트하지 않는다(발동 직후 now+쿨다운). 헤드리스 검증 지점.
    private(set) var cooldownUntil: Date = .distantPast

    private var loopTask: Task<Void, Never>?
    // 시스템 깨어남 옵저버 토큰(보관). 클로저는 [weak self] 라 스토어 수명으로 자동 무력화된다.
    private var wakeObserver: NSObjectProtocol?

    /// 기본 idle 소스: 마지막 입력 후 경과 초. `kCGAnyInputEventType`(=~0)로 모든 입력을 합산하며 권한이 필요 없다.
    nonisolated static func systemIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    init(
        idleSeconds: @escaping () -> TimeInterval = NudgeScheduler.systemIdleSeconds,
        clock: @escaping () -> Date = { Date() },
        isEligible: @escaping () -> Bool,
        onNudge: @escaping () -> Void,
        workspaceNotifications: NotificationCenter? = NSWorkspace.shared.notificationCenter
    ) {
        self.idleSeconds = idleSeconds
        self.clock = clock
        self.isEligible = isEligible
        self.onNudge = onNudge
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
        activeMinutes = 0
    }

    /// 한 주기의 판정(주입된 clock/idle 로 결정적). 루프가 매 60초 호출하며, 테스트는 직접 호출한다.
    ///
    /// - 자격 미충족(로그아웃/근무중/오버레이 꺼짐/이미 표시중): 활성 누적을 0 으로 리셋하고 통과.
    /// - 쿨다운 중: 아무것도 하지 않고 통과(카운트 안 함).
    /// - 실제 사용 중(idle < 임계): +1분. 아니면 유지(감소 없음 — 잠깐 자리 비움은 봐준다).
    /// - 5분 도달: 발동 + 활성 0 + 쿨다운(now+1시간) 세팅.
    func tick() {
        let now = clock()
        guard isEligible() else {
            activeMinutes = 0
            return
        }
        guard now >= cooldownUntil else { return }
        if idleSeconds() < Self.activeIdleThreshold {
            activeMinutes += 1
        }
        if activeMinutes >= Self.requiredActiveMinutes {
            activeMinutes = 0
            cooldownUntil = now.addingTimeInterval(Self.cooldownSeconds)
            onNudge()
        }
    }

    /// 시스템이 잠에서 깨어남 — 활성 누적을 0 으로 되돌린다(테스트는 직접 호출).
    func handleWake() {
        activeMinutes = 0
    }
}
