import Foundation
import Testing
@testable import check

// MARK: - 넛지 스케줄러 (활성 5분 누적 발동 / idle 유지 / 쿨다운 / 깨어남·자격 리셋)

/// clock/idle/eligible/onNudge 를 주입해 스케줄러를 결정적으로 구동하는 헬퍼(실제 시스템·타이머 없음).
@MainActor
private final class NudgeHarness {
    var now = Date(timeIntervalSince1970: 100_000)
    var idle: TimeInterval = 10          // 기본은 "실제 사용 중"(임계 120 미만).
    var eligible = true
    private(set) var nudgeCount = 0

    lazy var scheduler = NudgeScheduler(
        idleSeconds: { [weak self] in self?.idle ?? 999 },
        clock: { [weak self] in self?.now ?? .distantPast },
        isEligible: { [weak self] in self?.eligible ?? false },
        onNudge: { [weak self] in self?.nudgeCount += 1 },
        workspaceNotifications: nil // 실제 wake 옵저버 미설치(테스트 격리).
    )

    /// n 회 tick 하며 매 tick 전에 clock 을 checkInterval 만큼 진행시킨다(실사용 60초 주기 모사).
    func run(_ count: Int) {
        for _ in 0..<count {
            now = now.addingTimeInterval(NudgeScheduler.checkInterval)
            scheduler.tick()
        }
    }
}

@MainActor
@Test
func nudgeFiresAfterFiveActiveMinutes() {
    let h = NudgeHarness()

    // 4분 활성만으로는 발동하지 않는다.
    h.run(4)
    #expect(h.nudgeCount == 0)
    #expect(h.scheduler.activeMinutes == 4)

    // 5분째 활성에서 발동하고, 활성 누적은 0 으로 리셋되며 쿨다운이 걸린다.
    h.run(1)
    #expect(h.nudgeCount == 1)
    #expect(h.scheduler.activeMinutes == 0)
    #expect(h.scheduler.cooldownUntil > h.now)
}

@MainActor
@Test
func nudgeIdleTicksDoNotCountButKeepAccumulation() {
    let h = NudgeHarness()

    // 3분 활성 적립.
    h.idle = 5
    h.run(3)
    #expect(h.scheduler.activeMinutes == 3)

    // 자리 비움(임계 초과) 2분은 카운트되지 않고, 누적도 감소하지 않는다(봐준다).
    h.idle = NudgeScheduler.activeIdleThreshold + 60
    h.run(2)
    #expect(h.scheduler.activeMinutes == 3)
    #expect(h.nudgeCount == 0)

    // 다시 활성 2분 → 총 5분 → 발동.
    h.idle = 5
    h.run(2)
    #expect(h.scheduler.activeMinutes == 0)
    #expect(h.nudgeCount == 1)
}

@MainActor
@Test
func nudgeCooldownBlocksForOneHour() {
    let h = NudgeHarness()

    // 첫 발동.
    h.run(5)
    #expect(h.nudgeCount == 1)
    let cooldownUntil = h.scheduler.cooldownUntil
    #expect(cooldownUntil == h.now.addingTimeInterval(NudgeScheduler.cooldownSeconds))

    // 쿨다운 동안엔 활성이어도 카운트하지 않고 재발동하지 않는다(60분 = 60틱 이내).
    h.run(50)
    #expect(h.nudgeCount == 1)
    #expect(h.scheduler.activeMinutes == 0)
    #expect(h.now < cooldownUntil)

    // 쿨다운을 넘기면 다시 카운트가 시작되어 5분 뒤 재발동한다.
    h.now = cooldownUntil.addingTimeInterval(1)
    h.run(5)
    #expect(h.nudgeCount == 2)
}

@MainActor
@Test
func nudgeCooldownSurvivesWorkStopStart() {
    // A3: 넛지 자동 시작 직후 근무를 끝내면(컨트롤러가 stop→start 로 스케줄러를 재무장) 쿨다운이 남아 재발동하지
    // 않아야 한다. stop() 은 활성 누적만 리셋하고 cooldownUntil 은 보존하며, start() 는 이를 건드리지 않는다.
    let h = NudgeHarness()
    h.run(5)
    #expect(h.nudgeCount == 1)
    let cooldownUntil = h.scheduler.cooldownUntil

    // 근무 시작→종료 모사: 근무 중엔 정지(stop), 종료 후 재가동(start). 쿨다운은 그대로 유지된다.
    h.scheduler.stop()
    h.scheduler.start()
    #expect(h.scheduler.cooldownUntil == cooldownUntil)

    // 쿨다운 내에는 활성이어도 재발동하지 않는다.
    h.run(5)
    #expect(h.nudgeCount == 1)
    #expect(h.now < cooldownUntil)
}

@MainActor
@Test
func nudgeWakeResetsActiveMinutes() {
    let h = NudgeHarness()
    h.run(3)
    #expect(h.scheduler.activeMinutes == 3)

    // 시스템이 깨어나면 "켜진 지 5분" 의미 보존을 위해 활성 누적을 리셋한다.
    h.scheduler.handleWake()
    #expect(h.scheduler.activeMinutes == 0)
    #expect(h.nudgeCount == 0)
}

@MainActor
@Test
func nudgeIneligibleResetsAndNeverFires() {
    let h = NudgeHarness()
    h.run(3)
    #expect(h.scheduler.activeMinutes == 3)

    // 자격 상실(근무 시작/로그아웃/오버레이 꺼짐 등) → tick 이 즉시 활성 누적을 0 으로 리셋하고 통과.
    h.eligible = false
    h.run(10)
    #expect(h.scheduler.activeMinutes == 0)
    #expect(h.nudgeCount == 0)
}

// MARK: - 로그인 자동 실행 등록 결정 (SMAppService 미호출 — 주입 클로저로 검증)

@Test
func loginItemRegistersOnceThenNoOps() {
    let suiteName = "check-login-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    var registerCalls = 0
    // 첫 호출: 플래그 없음 + 미등록 → register 1회 + 플래그 기록.
    let first = LoginItemRegistrar.registerIfNeeded(
        defaults: defaults,
        isNotRegistered: { true },
        register: { registerCalls += 1 }
    )
    #expect(first == true)
    #expect(registerCalls == 1)
    #expect(defaults.object(forKey: LoginItemRegistrar.registeredKey) != nil)

    // 두 번째 호출: 플래그가 있으므로 아무것도 하지 않는다(재등록 강제 금지 — 수동 제거 존중).
    let second = LoginItemRegistrar.registerIfNeeded(
        defaults: defaults,
        isNotRegistered: { true },
        register: { registerCalls += 1 }
    )
    #expect(second == false)
    #expect(registerCalls == 1)
}

@Test
func loginItemSkipsRegisterWhenAlreadyRegisteredButStillFlags() {
    let suiteName = "check-login-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    var registerCalls = 0
    // 이미 시스템에 등록된 상태(.notRegistered 아님) → register 는 부르지 않되 플래그는 남겨 다음에 끼어들지 않는다.
    let result = LoginItemRegistrar.registerIfNeeded(
        defaults: defaults,
        isNotRegistered: { false },
        register: { registerCalls += 1 }
    )
    #expect(result == true)
    #expect(registerCalls == 0)
    #expect(defaults.object(forKey: LoginItemRegistrar.registeredKey) != nil)
}
