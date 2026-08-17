import Foundation
import ServiceManagement
import Testing
@testable import check

// MARK: - 넛지 스케줄러 (활성 5분 누적 발동 / idle 유지 / 쿨다운 / 깨어남·자격 리셋)

/// clock/idle/eligible/session/onNudge 를 주입해 스케줄러를 결정적으로 구동하는 헬퍼(실제 시스템·타이머 없음).
@MainActor
private final class NudgeHarness {
    var now = Date(timeIntervalSince1970: 100_000)
    var idle: TimeInterval = 10          // 기본은 "실제 사용 중"(임계 120 미만).
    var eligible = true
    /// 세션 사용 가능 여부. **반드시 주입해야 한다** — 기본값 `consoleSessionUsable()` 은
    /// `CGSessionCopyCurrentDictionary()` 로 실제 시스템을 읽어, 테스트를 돌리는 맥이 잠겨 있으면
    /// (원격/CI/화면보호기) 모든 tick 이 적립 없이 통과해 넛지 테스트 전체가 빨개진다.
    /// 프로덕션 결함이 아니라 하네스가 시스템에 의존했던 것이라, 기본을 true(사람이 앞에 있음)로 고정한다.
    var sessionUsable = true
    private(set) var nudgeCount = 0

    lazy var scheduler = NudgeScheduler(
        idleSeconds: { [weak self] in self?.idle ?? 999 },
        clock: { [weak self] in self?.now ?? .distantPast },
        isEligible: { [weak self] in self?.eligible ?? false },
        onNudge: { [weak self] in self?.nudgeCount += 1 },
        isSessionUsable: { [weak self] in self?.sessionUsable ?? false },
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

@MainActor
@Test
func nudgeLockedSessionNeverAccumulatesButResumesAfterUnlock() {
    // 잠금/비콘솔 가드(tick 의 `guard isSessionUsable()`)를 지키는 유일한 테스트.
    // 이게 없으면 가드를 통째로 지워도 스위트가 초록이라, 잠금 화면 비밀번호 타이핑이나
    // 빠른 사용자 전환 중 남의 입력으로 이 사람의 근무가 자동 시작되는 회귀를 아무도 못 잡는다.
    let h = NudgeHarness()

    // 잠긴 동안엔 입력이 활발해도(idle 기본 10초 = 사용 중) 단 1분도 적립하지 않는다.
    h.sessionUsable = false
    h.run(4)
    #expect(h.scheduler.activeMinutes == 0)

    // 발동 요구치를 넘길 만큼 오래 잠겨 있어도 넛지는 뜨지 않는다.
    h.run(6)
    #expect(h.scheduler.activeMinutes == 0)
    #expect(h.nudgeCount == 0)

    // 잠금 해제 뒤에는 정상 적립으로 되돌아온다 — 가드는 영구 차단이 아니라 그 tick 만 건너뛴다.
    h.sessionUsable = true
    h.run(4)
    #expect(h.scheduler.activeMinutes == 4)
    #expect(h.nudgeCount == 0)

    // 해제 후 5분째에 정상 발동(잠긴 동안의 10분은 창에 남아 있지 않다).
    h.run(1)
    #expect(h.nudgeCount == 1)
    #expect(h.scheduler.activeMinutes == 0)
}

// MARK: - 로그인 자동 실행 등록 결정 (SMAppService 미호출 — 주입 클로저로 검증)
//
// **계약이 뒤집힌 자리다.** 예전 두 테스트(`loginItemRegistersOnceThenNoOps` /
// `loginItemSkipsRegisterWhenAlreadyRegisteredButStillFlags`)는 "한 번만 등록한다"를 못 박았는데,
// 그 1회성이 바로 이번에 고친 결함이다. 이 맥에서 실측한 그림:
//   · `08-17 04:00:46` 부터 BTM 이 `record not found`(= `.notRegistered`) 를 돌려주고 있었고,
//   · `15:02` 부팅 · `15:23` 로그인 후 앱이 자동 실행되지 않아 `15:32` 에 수동 실행됐는데,
//   · `defaults read kingcheck check.loginItemRegistered` 는 `1` 이었다.
// brew upgrade 가 `.app` 번들을 갈아 끼우면 등록 레코드가 사라지는데, 1회성 플래그가 복구를 영원히
// 막았다. 그래서 **매 실행마다 판단**하고, 등록 여부는 오직 `!userTurnedOff && .notRegistered` 다.
//
// 여기 어떤 테스트도 실제 `SMAppService.register()/unregister()` 를 부르지 않는다 — 부르면 이 맥의
// 시스템 설정(로그인 항목)이 실제로 바뀐다. 상태·등록·토글 적용은 전부 주입 지점 뒤에 있다.

/// 테스트마다 격리된 UserDefaults 스위트. 실사용 도메인(kingcheck)이나 `.standard` 를 절대 건드리지 않는다.
///
/// **스위트 이름은 UUID 가 아니라 테스트 이름으로 고정한다.** 이 파일의 예전 판은
/// `check-login-\(UUID())` 로 매번 새 스위트를 팠는데, `removePersistentDomain` 을 불러도 cfprefsd 는
/// `~/Library/Preferences/` 에 42바이트짜리 빈 plist 를 남긴다(파일을 직접 지워도 다시 쓴다 — 실측했다).
/// 그래서 테스트 실행 1회마다 파일이 13개씩 영구히 쌓였고, 발견 시점에 사용자 맥에 710개가 있었다.
/// 이름을 테스트별로 고정하면 파일 집합이 그 13개로 **묶인다** — 재실행이 같은 파일을 덮어쓸 뿐이다.
/// 테스트마다 이름이 다르므로 병렬 실행에서도 서로 섞이지 않는다.
private final class ScratchDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init(_ test: String = #function) {
        suiteName = "check-login-test.\(test.replacingOccurrences(of: "()", with: ""))"
        defaults = UserDefaults(suiteName: suiteName)!
        // 지난 실행이 남긴 값이 이 테스트로 새어 들어오지 않게 시작 시점에 비운다(끝에서도 한 번 더).
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeSuite(named: suiteName)
    }
}

/// 상태 소스와 register 클로저를 한 번에 묶어 호출 횟수를 세는 스파이.
private struct RegisterSpy {
    private(set) var calls = 0
    var succeeds = true

    mutating func register() -> Bool {
        calls += 1
        return succeeds
    }
}

/// `registerIfNeeded` 가 진단 키에 남겼어야 하는 문자열.
private func expectedDiagnostic(_ outcome: LoginItemRegistrar.Outcome, _ status: SMAppService.Status) -> String {
    "\(outcome.rawValue):\(LoginItemRegistrar.label(for: status))"
}

// MARK: 상태별 판단 (1 · 2 · 3 · 3b)

@Test
func loginItemRegistersWhenRecordIsMissing() {
    // 1) 의도키 없음 + `.notRegistered`(레코드 자체가 없음 = 등록한 적 없거나 **잃어버림**) → 되살린다.
    let scratch = ScratchDefaults()
    var spy = RegisterSpy()

    let outcome = LoginItemRegistrar.registerIfNeeded(
        defaults: scratch.defaults,
        status: { .notRegistered },
        register: { spy.register() }
    )

    #expect(outcome == .registered)
    #expect(spy.calls == 1)
    #expect(
        scratch.defaults.string(forKey: LoginItemRegistrar.lastAutoRegisterKey)
            == expectedDiagnostic(.registered, .notRegistered)
    )
}

@Test
func loginItemLeavesEnabledStatusAlone() {
    // 2) 이미 `.enabled` — 손댈 이유가 없다. 재등록을 밀어 넣으면 사용자가 손댄 적 없는 정상 상태를 흔든다.
    let scratch = ScratchDefaults()
    var spy = RegisterSpy()

    let outcome = LoginItemRegistrar.registerIfNeeded(
        defaults: scratch.defaults,
        status: { .enabled },
        register: { spy.register() }
    )

    #expect(outcome == .skippedByStatus)
    #expect(spy.calls == 0)
    #expect(
        scratch.defaults.string(forKey: LoginItemRegistrar.lastAutoRegisterKey)
            == expectedDiagnostic(.skippedByStatus, .enabled)
    )
}

@Test
func loginItemNeverRevivesWhatUserDisabledInSystemSettings() {
    // 3) `.requiresApproval` = 레코드는 살아 있는데 **사용자가 시스템 설정에서 껐다**(BTM disposition `[disabled, …]`).
    //    잃어버린 것(.notRegistered)과 일부러 끈 것(.requiresApproval)을 가르는 유일한 신호가 이 상태값이다.
    //    여기서 등록을 밀어 넣으면 사용자가 끌 때마다 앱이 되살려 매 로그인 싸움이 된다.
    let scratch = ScratchDefaults()
    var spy = RegisterSpy()

    let outcome = LoginItemRegistrar.registerIfNeeded(
        defaults: scratch.defaults,
        status: { .requiresApproval },
        register: { spy.register() }
    )

    #expect(outcome == .skippedByStatus)
    #expect(spy.calls == 0)
    #expect(
        scratch.defaults.string(forKey: LoginItemRegistrar.lastAutoRegisterKey)
            == expectedDiagnostic(.skippedByStatus, .requiresApproval)
    )
}

@Test
func loginItemSkipsNotFoundStatus() {
    // 3b) `.notFound` — 서비스 정의 자체를 못 찾은 오류 상태. 등록을 시도해도 성공할 수 없다.
    let scratch = ScratchDefaults()
    var spy = RegisterSpy()

    let outcome = LoginItemRegistrar.registerIfNeeded(
        defaults: scratch.defaults,
        status: { .notFound },
        register: { spy.register() }
    )

    #expect(outcome == .skippedByStatus)
    #expect(spy.calls == 0)
}

// MARK: 사용자 의도 (4 · 4b)

@Test
func loginItemRespectsUserTurnedOffIntent() {
    // 4) 앱 토글로 끈 사용자는 레코드가 없어도(`.notRegistered`) 되살리지 않는다 — 안 그러면 매 실행 싸운다.
    let scratch = ScratchDefaults()
    scratch.defaults.set(true, forKey: LoginItemRegistrar.userTurnedOffKey)
    var spy = RegisterSpy()

    let outcome = LoginItemRegistrar.registerIfNeeded(
        defaults: scratch.defaults,
        status: { .notRegistered },
        register: { spy.register() }
    )

    #expect(outcome == .skippedUserTurnedOff)
    #expect(spy.calls == 0)
    #expect(
        scratch.defaults.string(forKey: LoginItemRegistrar.lastAutoRegisterKey)
            == expectedDiagnostic(.skippedUserTurnedOff, .notRegistered)
    )
}

@Test
func loginItemRegistersAfterUserTurnsAutoLaunchBackOn() {
    // 4b) 껐다가 다시 켠 사용자(의도키 false)는 자동 복구 대상으로 되돌아온다 — 의도키는 영구 사형선고가 아니다.
    let scratch = ScratchDefaults()
    scratch.defaults.set(false, forKey: LoginItemRegistrar.userTurnedOffKey)
    var spy = RegisterSpy()

    let outcome = LoginItemRegistrar.registerIfNeeded(
        defaults: scratch.defaults,
        status: { .notRegistered },
        register: { spy.register() }
    )

    #expect(outcome == .registered)
    #expect(spy.calls == 1)
}

// MARK: 옛 1회성 플래그 (5 · 5b)

@Test
func loginItemRecoversUsersStuckOnLegacyOneShotFlag() {
    // 5) **이 변경의 핵심.** 옛 키가 1 로 박힌 채 등록을 잃어버린 기존 사용자 전원이 다음 실행에서 복구돼야 한다.
    //    이 맥에서 실측된 상태가 정확히 이것이다: `check.loginItemRegistered = 1` + BTM `record not found`.
    //    옛 키를 게이트로 다시 읽는 순간 그 사람들은 영원히 자동 실행 없이 산다.
    let scratch = ScratchDefaults()
    scratch.defaults.set(true, forKey: LoginItemRegistrar.legacyRegisteredKey)
    var spy = RegisterSpy()

    let outcome = LoginItemRegistrar.registerIfNeeded(
        defaults: scratch.defaults,
        status: { .notRegistered },
        register: { spy.register() }
    )

    #expect(outcome == .registered)
    #expect(spy.calls == 1)
    // 죽은 키는 그 자리에서 치운다 — `defaults read` 가 다음 사람에게 거짓말하지 않도록(멱등).
    #expect(scratch.defaults.object(forKey: LoginItemRegistrar.legacyRegisteredKey) == nil)
}

@Test
func loginItemLegacyFlagDoesNotOverrideUserIntent() {
    // 5b) 옛 키는 어떤 방향으로도 권위가 없다. 의도키가 true 면 옛 키가 1 이든 말든 건드리지 않는다.
    let scratch = ScratchDefaults()
    scratch.defaults.set(true, forKey: LoginItemRegistrar.legacyRegisteredKey)
    scratch.defaults.set(true, forKey: LoginItemRegistrar.userTurnedOffKey)
    var spy = RegisterSpy()

    let outcome = LoginItemRegistrar.registerIfNeeded(
        defaults: scratch.defaults,
        status: { .notRegistered },
        register: { spy.register() }
    )

    #expect(outcome == .skippedUserTurnedOff)
    #expect(spy.calls == 0)
    #expect(scratch.defaults.object(forKey: LoginItemRegistrar.legacyRegisteredKey) == nil)
}

// MARK: 매 실행 재판단 · 실패 재시도 (6 · 7)

@Test
func loginItemRetriesEveryLaunchWhileRecordKeepsDisappearing() {
    // 6) 1회성이 아니다. 같은 defaults 로 세 번 실행하면 세 번 등록한다.
    //    실사용 그림: `brew upgrade` 가 `.app` 번들을 갈아 끼울 때마다 BTM 레코드가 사라진다(8월에만 8번).
    //    "이미 한 번 등록했으니 됐다"는 판단이 들어오는 순간 사용자는 그 뒤로 영원히 수동 실행이다.
    let scratch = ScratchDefaults()
    var spy = RegisterSpy()

    for _ in 0..<3 {
        let outcome = LoginItemRegistrar.registerIfNeeded(
            defaults: scratch.defaults,
            status: { .notRegistered },
            register: { spy.register() }
        )
        #expect(outcome == .registered)
    }

    #expect(spy.calls == 3)
}

@Test
func loginItemRecordsFailureAndRetriesOnNextLaunch() {
    // 7) 등록 실패를 삼키지 않는다. 진단 키에 `registerFailed` 를 남기고, 플래그가 없으니 다음 실행에서 재시도한다.
    let scratch = ScratchDefaults()
    var spy = RegisterSpy()
    spy.succeeds = false

    let first = LoginItemRegistrar.registerIfNeeded(
        defaults: scratch.defaults,
        status: { .notRegistered },
        register: { spy.register() }
    )
    #expect(first == .registerFailed)
    #expect(spy.calls == 1)
    #expect(
        scratch.defaults.string(forKey: LoginItemRegistrar.lastAutoRegisterKey)
            == expectedDiagnostic(.registerFailed, .notRegistered)
    )

    // 다음 실행: 실패 기록이 남아 있어도 그것 때문에 건너뛰지 않는다(진단이지 게이트가 아니다).
    spy.succeeds = true
    let second = LoginItemRegistrar.registerIfNeeded(
        defaults: scratch.defaults,
        status: { .notRegistered },
        register: { spy.register() }
    )
    #expect(second == .registered)
    #expect(spy.calls == 2)
    #expect(
        scratch.defaults.string(forKey: LoginItemRegistrar.lastAutoRegisterKey)
            == expectedDiagnostic(.registered, .notRegistered)
    )
}

// MARK: 판단부 전수 (8)

@Test
func loginItemShouldRegisterCoversEveryStatusAndIntent() {
    // 8) 순수 판단부 4상태 × 의도키 2 = 8조합 전수. 참은 오직 한 칸(`!userTurnedOff && .notRegistered`)이다.
    let statuses: [SMAppService.Status] = [.notRegistered, .enabled, .requiresApproval, .notFound]

    for status in statuses {
        for userTurnedOff in [false, true] {
            let expected = (userTurnedOff == false && status == .notRegistered)
            #expect(
                LoginItemRegistrar.shouldRegister(userTurnedOff: userTurnedOff, status: status) == expected,
                "status=\(LoginItemRegistrar.label(for: status)) userTurnedOff=\(userTurnedOff)"
            )
        }
    }
}

// MARK: 앱 토글 (applyUserToggle)
//
// 이 세 테스트는 `LoginItemRegistrar` 의 @MainActor 정적 주입점(isLaunchAtLoginEnabled /
// setLaunchAtLoginEnabled)을 갈아 끼운다. **본문에 await 가 없는 @MainActor 동기 테스트**라 다른
// 테스트가 중간에 끼어들 수 없고, defer 로 원래 클로저를 되돌린다 — 실제 SMAppService 는 부르지 않는다.

@MainActor
@Test
func launchAtLoginToggleOffRecordsIntentBeforeTouchingSystem() {
    let scratch = ScratchDefaults()
    let savedSet = LoginItemRegistrar.setLaunchAtLoginEnabled
    let savedIsEnabled = LoginItemRegistrar.isLaunchAtLoginEnabled
    defer {
        LoginItemRegistrar.setLaunchAtLoginEnabled = savedSet
        LoginItemRegistrar.isLaunchAtLoginEnabled = savedIsEnabled
    }

    // 시스템을 만지는 그 순간 의도키가 **이미** 기록돼 있어야 한다 — 순서를 뒤집으면 unregister 도중
    // 앱이 죽거나 쓰기가 실패했을 때 "껐다"는 사실만 사라지고, 다음 실행이 곧바로 되살린다.
    var intentSeenBySystemCall: Bool?
    var systemCalls: [Bool] = []
    LoginItemRegistrar.setLaunchAtLoginEnabled = { enabled in
        intentSeenBySystemCall = scratch.defaults.bool(forKey: LoginItemRegistrar.userTurnedOffKey)
        systemCalls.append(enabled)
        return true
    }
    LoginItemRegistrar.isLaunchAtLoginEnabled = { true }

    let shown = LoginItemRegistrar.applyUserToggle(false, defaults: scratch.defaults)

    #expect(systemCalls == [false])
    #expect(intentSeenBySystemCall == true)
    #expect(scratch.defaults.bool(forKey: LoginItemRegistrar.userTurnedOffKey) == true)
    #expect(shown == false)
}

@MainActor
@Test
func launchAtLoginToggleOnClearsUserTurnedOffIntent() {
    let scratch = ScratchDefaults()
    scratch.defaults.set(true, forKey: LoginItemRegistrar.userTurnedOffKey)
    let savedSet = LoginItemRegistrar.setLaunchAtLoginEnabled
    let savedIsEnabled = LoginItemRegistrar.isLaunchAtLoginEnabled
    defer {
        LoginItemRegistrar.setLaunchAtLoginEnabled = savedSet
        LoginItemRegistrar.isLaunchAtLoginEnabled = savedIsEnabled
    }

    var systemCalls: [Bool] = []
    LoginItemRegistrar.setLaunchAtLoginEnabled = { enabled in
        systemCalls.append(enabled)
        return true
    }
    LoginItemRegistrar.isLaunchAtLoginEnabled = { false }

    let shown = LoginItemRegistrar.applyUserToggle(true, defaults: scratch.defaults)

    #expect(systemCalls == [true])
    // 다시 켰으면 자동 복구 대상으로 되돌아와야 한다 — 의도키가 true 로 남으면 등록을 잃어버려도 영영 안 살아난다.
    #expect(scratch.defaults.bool(forKey: LoginItemRegistrar.userTurnedOffKey) == false)
    #expect(shown == true)
}

@MainActor
@Test
func launchAtLoginToggleKeepsIntentWhenSystemCallFails() {
    let scratch = ScratchDefaults()
    let savedSet = LoginItemRegistrar.setLaunchAtLoginEnabled
    let savedIsEnabled = LoginItemRegistrar.isLaunchAtLoginEnabled
    defer {
        LoginItemRegistrar.setLaunchAtLoginEnabled = savedSet
        LoginItemRegistrar.isLaunchAtLoginEnabled = savedIsEnabled
    }

    // unregister 가 실패했다 → 토글은 실상태(아직 켜짐)를 보여 주지만, "껐다"는 의도는 남아야 한다.
    LoginItemRegistrar.setLaunchAtLoginEnabled = { _ in false }
    LoginItemRegistrar.isLaunchAtLoginEnabled = { true }

    let shown = LoginItemRegistrar.applyUserToggle(false, defaults: scratch.defaults)

    #expect(shown == true)  // 실패했으므로 화면에는 실상태가 뜬다(거짓 성공 표시 금지).
    #expect(scratch.defaults.bool(forKey: LoginItemRegistrar.userTurnedOffKey) == true)
}
