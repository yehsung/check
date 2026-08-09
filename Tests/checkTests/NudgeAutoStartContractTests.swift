import Foundation
import Testing
@testable import check

// MARK: - 자동 시작 v0.2.17 계약: 시간창·의미 있는 입력·잠금 배제·수동 종료 억제(1시간 부재 재무장)
//
// 배경(프로브로 실증한 결함 — 이 파일이 그 재발을 막는다):
//  · 수동 [근무 종료] 후 컴퓨터를 계속 쓰면 5분 만에 근무가 저절로 재시작됐다(쿨다운은 발동 후 1시간뿐).
//  · 활성 누적에 시간창이 없어, 몇 시간 간격의 '잠깐 만짐' 5번으로 자리에 없는 사람의 근무가 시작됐다.

/// clock/idle/eligible/lock/gap 을 주입해 스케줄러를 결정적으로 구동하는 헬퍼(실제 시스템·타이머 없음).
@MainActor
private final class ContractHarness {
    var now = Date(timeIntervalSince1970: 100_000)
    var idle: TimeInterval = 10
    var eligible = true
    var sessionUsable = true
    private(set) var nudgeCount = 0
    private(set) var absenceGapCount = 0
    private(set) var lastAliveAt: Date?

    lazy var scheduler = NudgeScheduler(
        idleSeconds: { [weak self] in self?.idle ?? 999 },
        clock: { [weak self] in self?.now ?? .distantPast },
        isEligible: { [weak self] in self?.eligible ?? false },
        onNudge: { [weak self] in self?.nudgeCount += 1 },
        isSessionUsable: { [weak self] in self?.sessionUsable ?? true },
        onAbsenceGap: { [weak self] in self?.absenceGapCount += 1 },
        onAliveTick: { [weak self] in self?.lastAliveAt = $0 },
        workspaceNotifications: nil
    )

    /// n 회 tick 하며 매 tick 전에 clock 을 checkInterval 만큼 진행시킨다(실사용 60초 주기 모사).
    func run(_ count: Int) {
        for _ in 0..<count {
            now = now.addingTimeInterval(NudgeScheduler.checkInterval)
            scheduler.tick()
        }
    }
}

// MARK: 시간창 — "최근 10분 안에 5분"만 발동한다

@MainActor
@Test
func sparseTouchesAcrossHoursDoNotFire() {
    let h = ContractHarness()
    // 약 31분 간격의 '1분 접촉' 5번(총 2.5시간) — 옛 구현은 여기서 발동했다(무감쇠 누적 프로브).
    for _ in 0..<5 {
        h.idle = 10
        h.run(1)
        h.idle = NudgeScheduler.activeIdleThreshold + 600
        h.run(30)
    }
    #expect(h.nudgeCount == 0)
    // 창 안 활성은 최대 1분만 남는다(31분 전 적립은 소멸).
    #expect(h.scheduler.activeMinutes <= 1)

    // 대조군: 진짜로 5분 연속 사용하면 정상 발동한다.
    h.idle = 10
    h.run(5)
    #expect(h.nudgeCount == 1)
}

@MainActor
@Test
func shortBreaksInsideWindowStillAccumulate() {
    let h = ContractHarness()
    // 3분 사용 + 2분 자리 비움 + 2분 사용 = 창(10분) 안 5분 → 발동(짧은 틈은 여전히 봐준다).
    h.idle = 5
    h.run(3)
    h.idle = NudgeScheduler.activeIdleThreshold + 60
    h.run(2)
    #expect(h.scheduler.activeMinutes == 3)
    h.idle = 5
    h.run(2)
    #expect(h.nudgeCount == 1)
}

// MARK: 잠금/비콘솔 세션 — 이 사람의 사용이 아니다

@MainActor
@Test
func lockedSessionNeverAccumulates() {
    let h = ContractHarness()
    // 화면이 잠긴 채 입력이 신선해도(잠금화면 타이핑, 빠른 사용자 전환 중 다른 계정 사용) 적립하지 않는다.
    h.sessionUsable = false
    h.idle = 1
    h.run(30)
    #expect(h.scheduler.activeMinutes == 0)
    #expect(h.nudgeCount == 0)

    // 잠금 해제 후 실제 사용 5분이면 정상 발동.
    h.sessionUsable = true
    h.run(5)
    #expect(h.nudgeCount == 1)
}

// MARK: 부재 관측 — 수동 종료 억제의 재무장 신호

@MainActor
@Test
func sleepGapBetweenTicksReportsAbsence() {
    let h = ContractHarness()
    h.idle = 999
    h.run(1)
    #expect(h.absenceGapCount == 0)
    // 잠자기 동안 Task.sleep 이 멈추므로 다음 tick 은 한참 뒤에 온다 — 그 간격이 곧 부재다.
    h.now = h.now.addingTimeInterval(NudgeScheduler.rearmGapSeconds + 5)
    h.scheduler.tick()
    #expect(h.absenceGapCount == 1)
}

@MainActor
@Test
func longIdleWhileAwakeReportsAbsence() {
    let h = ContractHarness()
    // 깨어 있었지만 1시간+ 아무 의미 있는 입력이 없었다 — 이것도 부재다.
    h.idle = NudgeScheduler.rearmGapSeconds + 30
    h.run(1)
    #expect(h.absenceGapCount == 1)
}

@MainActor
@Test
func schedulerRestartDoesNotMistakeWorkHoursForAbsence() {
    let h = ContractHarness()
    h.idle = 999
    h.run(1)
    #expect(h.absenceGapCount == 0)

    // 아침 자동 시작 → 근무 중 9시간은 루프 정지 → 저녁 [근무 종료]로 재가동. 이 9시간은 '자리에 있었던'
    // 시간이지 부재가 아니다 — start() 가 간격 측정을 리셋하지 않으면 방금 세운 억제가 첫 tick 에 풀려
    // 퇴근 5분 뒤 자동 재출근이 그대로 재현된다(이 테스트가 그 회귀를 막는다).
    h.scheduler.stop()
    h.now = h.now.addingTimeInterval(9 * 3600)
    h.scheduler.start()
    h.scheduler.tick()
    #expect(h.absenceGapCount == 0)

    // 재가동 이후의 진짜 공백(다음 tick 까지 1시간+)은 정상 관측된다.
    h.now = h.now.addingTimeInterval(NudgeScheduler.rearmGapSeconds + 5)
    h.scheduler.tick()
    #expect(h.absenceGapCount == 1)
}

@MainActor
@Test
func aliveTickStampsEveryTick() {
    let h = ContractHarness()
    h.idle = 999
    h.run(3)
    #expect(h.lastAliveAt == h.now)
}

// MARK: 스토어 — 수동 종료 억제의 성립·해제·영속

@MainActor
private func makeSuppressionStore(suiteName: String) -> WorkTimerStore {
    let defaults = UserDefaults(suiteName: suiteName)!
    return WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://suppression-tests")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        ),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
}

@MainActor
@Test
func manualStopSuppressesAndManualStartClears() {
    let suiteName = "check-suppression-\(UUID().uuidString)"
    UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
    let store = makeSuppressionStore(suiteName: suiteName)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    #expect(!store.autoStartSuppressed)
    store.start()
    store.stop()
    // 수동 종료 = "오늘 이 자리에서는 그만" — 자동 시작 억제가 선다.
    #expect(store.autoStartSuppressed)

    // 수동 [근무 시작]은 명시적 의사 — 억제를 푼다.
    store.start()
    #expect(!store.autoStartSuppressed)
    store.stop()
    #expect(store.autoStartSuppressed)

    // 1시간+ 부재 관측(스케줄러 onAbsenceGap 배선)도 억제를 푼다.
    store.clearAutoStartSuppression()
    #expect(!store.autoStartSuppressed)
}

@MainActor
@Test
func suppressionSurvivesRelaunchWhileAppStaysAlive() {
    let suiteName = "check-suppression-\(UUID().uuidString)"
    UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
    let store = makeSuppressionStore(suiteName: suiteName)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    store.start()
    store.stop()
    #expect(store.autoStartSuppressed)
    // 방금 생존 스탬프를 찍었으므로(종료 직후) 곧바로 재실행해도 억제가 유지된다 —
    // 업데이트 재실행·앱 껐다 켬이 억제를 초기화하면 유령 재출근이 그대로 재현된다.
    let relaunched = makeSuppressionStore(suiteName: suiteName)
    defer {
        relaunched.tickerTask?.cancel()
        relaunched.refreshTask?.cancel()
        relaunched.syncTask?.cancel()
    }
    #expect(relaunched.autoStartSuppressed)
}

@MainActor
@Test
func suppressionRearmsAfterAppWasDeadForTheGap() {
    let suiteName = "check-suppression-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    // 어제 저녁 종료 → 밤새 꺼짐 → 아침 재실행: 마지막 생존 스탬프가 1시간+ 과거면 그 공백이 곧 부재다.
    defaults.set(true, forKey: WorkTimerStore.autoStartSuppressedKey)
    defaults.set(
        Date().addingTimeInterval(-(NudgeScheduler.rearmGapSeconds + 60)),
        forKey: WorkTimerStore.nudgeLastAliveAtKey
    )
    let store = makeSuppressionStore(suiteName: suiteName)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    #expect(!store.autoStartSuppressed)
    // 표식도 청소돼 있어야 한다(다음 실행이 다시 읽지 않게).
    #expect(defaults.object(forKey: WorkTimerStore.autoStartSuppressedKey) == nil)
}

@MainActor
@Test
func aliveStampPersistsOnlyWhileSuppressed() {
    let suiteName = "check-suppression-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = makeSuppressionStore(suiteName: suiteName)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    let t = Date(timeIntervalSince1970: 200_000)
    // 억제 아님 → 스탬프를 쓰지 않는다(쓸 일도 읽을 일도 없다).
    store.recordNudgeAlive(t)
    #expect(defaults.object(forKey: WorkTimerStore.nudgeLastAliveAtKey) == nil)

    store.start()
    store.stop(now: t)
    store.recordNudgeAlive(t.addingTimeInterval(60))
    #expect(defaults.object(forKey: WorkTimerStore.nudgeLastAliveAtKey) as? Date == t.addingTimeInterval(60))
}
