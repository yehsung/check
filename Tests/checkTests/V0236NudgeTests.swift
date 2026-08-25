import Foundation
import Testing
@testable import check

// MARK: - v0.2.36 [F5]: 서버/자동 마감 뒤 넛지 쿨다운 이월 결함
//
// 확정 근본 원인(2차 사냥 W3 — 주입 테스트로 44분 재현): 서버가 하트비트 10분 끊김으로 세션을
// abandoned 마감한 뒤, 재시작의 유일한 자동 수단은 넛지(최소 5분)인데 **닫힌 세션이 직전 넛지로
// 시작된 것이면 쿨다운(1시간)이 stop/start 를 넘어 생존**해 재시작이 강하 후 최대 44분까지 밀렸다.
// 고침: updateWorking 의 근무 → 비근무 실전이에서 nudgeScheduler.resetCooldown().
// 이 파일은 그 배선(전이에서만·재통지 제외·표시 아닌 근무 기준)과 리셋의 단독 의미,
// 그리고 수동 종료 억제 계약의 불변을 고정한다.

/// clock/idle 을 주입해 스케줄러 단독을 결정적으로 구동하는 헬퍼(CheckNudgeTests 의 NudgeHarness 규약).
@MainActor
private final class V0236SchedulerHarness {
    var now = Date(timeIntervalSince1970: 500_000)
    var idle: TimeInterval = 10          // 기본은 "실제 사용 중"(임계 120 미만).
    var eligible = true
    /// 반드시 주입한다 — 기본값은 실제 시스템 잠금을 읽어, 잠긴 원격/CI 맥에서 전 tick 이 무적립 통과한다.
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

/// 테스트별 고정 이름의 격리 defaults. UUID 스위트는 실행마다 빈 plist 를 영구히 쌓는다(CheckNudgeTests
/// 의 ScratchDefaults 가 실측으로 못 박은 함정) — 이름을 테스트로 고정해 파일 집합을 묶는다.
private final class V0236Scratch {
    let suiteName: String
    let defaults: UserDefaults

    init(_ test: String) {
        suiteName = "check-v0236-nudge.\(test.replacingOccurrences(of: "()", with: ""))"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeSuite(named: suiteName)
    }
}

/// 실제 스토어 + 실제 컨트롤러를 관통하는 배선 검증 하네스. 넛지의 시간·입력·세션 판정만 주입해
/// (컨트롤러 init 의 nudge* 주입 지점) 발화 → 자동 시작 → 마감 수용 → 재발화를 결정적으로 돌린다.
/// 네트워크는 전부 URLProtocolStub — 프로덕션 호출 없음.
@MainActor
private final class V0236ControllerHarness {
    // 스토어의 실제 시간 경로(start 의 기본 now 등)와 섞이므로 기준을 벽시계 근처에 둔다 —
    // 판정은 전부 델타(60초 tick·쿨다운 상수)라 결정성은 주입 클록이 보증한다.
    var now = Date()
    var idle: TimeInterval = 10
    let scratch: V0236Scratch
    let store: WorkTimerStore

    lazy var controller = CheckOverlayController(
        store: store,
        notificationCenter: NotificationCenter(), // 전역 노티 오염 방지.
        defaults: scratch.defaults,
        workspaceNotifications: nil,
        nudgeIdleSeconds: { [weak self] in self?.idle ?? 999 },
        nudgeClock: { [weak self] in self?.now ?? .distantPast },
        nudgeSessionUsable: { true } // 실제 잠금 판정 금지(잠긴 원격 맥에서 전 tick 무적립).
    )

    init(_ test: String = #function) {
        scratch = V0236Scratch(test)
        store = WorkTimerStore(
            service: SupabaseWorkService(
                projectURL: URL(string: "http://v0236-nudge-tests")!,
                anonKey: "anon-test-key",
                session: URLSession(configuration: .stubbed)
            ),
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: scratch.defaults,
            workspaceNotifications: nil
        )
        // 넛지 자격: 로그인 + 팀 + 비근무.
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        store.currentTeamID = "10000000-0000-0000-0000-0000000000f5"
        store.clock = { [weak self] in self?.now ?? Date() }
        store.inputSessionUsable = { true }
        store.meaningfulIdleSeconds = { 0 }
    }

    /// n 회 tick 하며 매 tick 전에 주입 클록을 60초 진행시킨다(컨트롤러 내부 스케줄러를 직접 구동).
    func run(_ count: Int) {
        for _ in 0..<count {
            now = now.addingTimeInterval(NudgeScheduler.checkInterval)
            controller.nudgeScheduler.tick()
        }
    }

    /// 서버 자동 마감(abandoned) 수용을 헤드리스로 모사: **억제 없이** 근무만 끝난 상태를 만든다.
    /// store.stop() 을 쓰지 않는 것이 전제다 — stop() 은 사용자의 명시적 의사 전용이라
    /// suppressAutoStart 를 세우고, 서버/자동 마감 수용 경로는 그 억제를 세우지 않는다.
    func acceptServerAutoClose() {
        store.startedAt = nil
        store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
    }

    /// 자격 제거 후 동기화 경로를 태워 루프를 끄고, 스토어가 띄운 태스크를 회수한다(잔여 프로세스 금지).
    func cleanup() {
        store.session = nil
        controller.updateWorking(false)
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
        store.pokePollTask?.cancel()
        store.drainInFlight?.cancel()
    }
}

@MainActor
struct V0236NudgeTests {
    // MARK: (1) 자동 마감 뒤 재발화 — 44분이 아니라 5분

    @Test
    func autoCloseAfterNudgeStartRefiresWithinFiveTicks() {
        let h = V0236ControllerHarness()
        defer { h.cleanup() }

        // 실행 시 가동(비근무·로그인) 상태에서 실제 사용 5분 → 넛지 발화 → 자동 근무 시작.
        #expect(h.controller.nudgeSchedulerRunning)
        h.run(5)
        #expect(h.store.startedAt != nil)
        #expect(h.store.snapshot.isWorking)
        #expect(
            h.controller.nudgeScheduler.cooldownUntil
                == h.now.addingTimeInterval(NudgeScheduler.cooldownSeconds)
        )

        // SwiftUI 관찰 경로를 헤드리스로 모사: 근무 관측 → 20분 뒤 서버 abandoned 마감 수용 → 비근무 관측.
        h.controller.updateWorking(true)
        h.now = h.now.addingTimeInterval(20 * 60)
        h.acceptServerAutoClose()
        h.controller.updateWorking(false)

        // [F5] 전이 배선: 쿨다운 즉시 만료 + 억제 없음(서버 마감은 사용자의 무시가 아니다).
        #expect(h.controller.nudgeScheduler.cooldownUntil == .distantPast)
        #expect(!h.store.autoStartSuppressed)

        // 강하 수용 후 실제 사용 5분(5 tick)이면 재발화해 근무가 다시 시작된다. 이 시점은 첫 발화의
        // 25분 뒤라, resetCooldown 호출이 지워지면 쿨다운(발화+1시간)이 정확히 여기를 막는다 —
        // 아래 두 단언이 그 뮤테이션의 상시 검증이다(44분 결함의 재현 형태).
        h.run(5)
        #expect(h.store.startedAt != nil)
        #expect(h.store.snapshot.isWorking)
    }

    // MARK: (2) 수동 종료 계약 불변 — 리셋돼도 억제가 자동 시작을 막는다

    @Test
    func manualStopStillSuppressesAutoStartAfterReset() {
        let h = V0236ControllerHarness()
        defer { h.cleanup() }

        // 넛지 발화 → 자동 근무 시작 → 근무 관측.
        h.run(5)
        #expect(h.store.snapshot.isWorking)
        h.controller.updateWorking(true)

        // 사용자가 직접 [근무 종료] — 억제가 선다("원치 않으면 근무 종료를 누르면 된다" 계약).
        h.store.stop(now: h.now)
        #expect(h.store.autoStartSuppressed)
        h.controller.updateWorking(false)

        // 전이이므로 쿨다운은 리셋된다 — 그래도 계약이 안 깨지는 근거가 억제다([F5] 근거 주석의 전제).
        #expect(h.controller.nudgeScheduler.cooldownUntil == .distantPast)

        // 종료 후 30분을 계속 실제 사용해도(부재 1시간 없음 = 재무장 안 됨) 자동 재출근하지 않는다.
        h.run(30)
        #expect(h.store.startedAt == nil)
        #expect(!h.store.snapshot.isWorking)
        #expect(h.store.autoStartSuppressed)
    }

    // MARK: (3) 대조군 — 리셋이 없으면 재발화는 쿨다운에 막힌다(뮤테이션 검증의 상시화)

    @Test
    func cooldownWithoutResetBlocksRefireAfterStopStart() {
        let h = V0236SchedulerHarness()
        h.run(5)
        #expect(h.nudgeCount == 1)

        // 넛지 근무(스케줄러 정지) → 10분 뒤 자동 마감 → 재가동. resetCooldown 없이는 실제 사용
        // 5분에도 재발화가 쿨다운에 막힌다 — 컨트롤러의 리셋 호출이 지워진 세계의 형태가 정확히 이것이고,
        // (1)의 재발화 단언과 짝을 이뤄 "리셋이 재발화의 유일한 통로"임을 고정한다.
        h.scheduler.stop()
        h.now = h.now.addingTimeInterval(10 * 60)
        h.scheduler.start()
        h.run(5)
        #expect(h.nudgeCount == 1)
        // 쿨다운 중엔 적립조차 하지 않는다(기존 계약 — nudgeCooldownBlocksForOneHour 와 동일 형태).
        #expect(h.scheduler.activeMinutes == 0)
    }

    // MARK: (4) 재통지(전이 아님)에서는 리셋이 나가지 않는다

    @Test
    func renotificationWithoutTransitionKeepsCooldown() {
        let h = V0236ControllerHarness()
        defer { h.cleanup() }

        // 발화로 쿨다운을 세우되 updateWorking(true) 는 흘리지 않는다 — 컨트롤러가 근무를 관측하기 전에
        // 관찰 경로에는 false 재통지만 흐른 순서를 모사한다(onChange of isSignedIn 등의 재통지 형태).
        h.run(5)
        let cooldown = h.controller.nudgeScheduler.cooldownUntil
        #expect(cooldown > .distantPast)
        h.acceptServerAutoClose()

        // false → false 는 전이가 아니다. 여기서 리셋이 나가면 무시당한 제안의 1시간 쿨다운이
        // 재통지 한 번마다 지워진다 — 쿨다운의 존재 이유가 통째로 사라지는 뮤테이션을 여기서 잡는다.
        h.controller.updateWorking(false)
        #expect(h.controller.nudgeScheduler.cooldownUntil == cooldown)
        h.controller.updateWorking(false)
        #expect(h.controller.nudgeScheduler.cooldownUntil == cooldown)
    }

    // MARK: (4b) 전이 판정은 표시가 아니라 근무 기준이다

    @Test
    func resetKeysOnWorkTransitionNotVisibility() {
        let h = V0236ControllerHarness()
        defer { h.cleanup() }

        // 캐릭터를 꺼 둔 사용자 — 자동 시작은 그대로 일어나되(자격에서 오버레이 제외) 표시 전이는 영영 없다.
        h.store.isOverlayEnabled = false
        h.run(5)
        #expect(h.store.snapshot.isWorking)
        h.controller.updateWorking(true)
        #expect(h.controller.shouldBeVisible == false)

        h.now = h.now.addingTimeInterval(15 * 60)
        h.acceptServerAutoClose()
        h.controller.updateWorking(false)

        // 표시(shouldBeVisible)는 한 번도 안 바뀌었지만 근무는 true→false 전이했다. 전이 기억을
        // wasVisible 로 만들면 이 사용자에게 44분 결함이 그대로 남는다 — 근무 기준을 여기서 못 박는다.
        #expect(h.controller.nudgeScheduler.cooldownUntil == .distantPast)
    }

    // MARK: (5) resetCooldown 단독 의미 — 즉시 만료, 적립은 0부터

    @Test
    func resetCooldownExpiresImmediatelyAndAccrualRestartsFromZero() {
        let h = V0236SchedulerHarness()
        h.run(5)
        #expect(h.nudgeCount == 1)
        #expect(h.scheduler.cooldownUntil == h.now.addingTimeInterval(NudgeScheduler.cooldownSeconds))

        // 단독 의미: 즉시 만료. 적립은 만들지 않는다(발화가 이미 비웠다 — 리셋이 곧 발화가 아니다).
        h.scheduler.resetCooldown()
        #expect(h.scheduler.cooldownUntil == .distantPast)
        #expect(h.scheduler.activeMinutes == 0)

        // 리셋 뒤에도 "최근 10분 안에 실제 사용 5분"은 0 부터 — 4분으로는 발화하지 않고 5분째에 발화한다.
        h.run(4)
        #expect(h.nudgeCount == 1)
        #expect(h.scheduler.activeMinutes == 4)
        h.run(1)
        #expect(h.nudgeCount == 2)
        #expect(h.scheduler.activeMinutes == 0)
    }
}
