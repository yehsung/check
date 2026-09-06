import Foundation
import SwiftUI
import Testing
@testable import check

// v0.2.43 배터리 3번 — 시:분 시계와 분 경계 틱 계약.
//
// 사용자 결정(2026-09-06): 메뉴바 제목과 캐릭터 라벨은 **항상 시:분**이다. 그러면 초를 보여 주는 화면은 열린 팝오버
// 하나뿐이고(오늘 시계 MM:SS·콕찌르기 쿨타임 카운트다운), 팝오버가 닫혀 있으면 근무 첫 1분부터 티커를 분 경계 60초로
// 늦출 수 있다. 종전 규칙("팝오버 닫힘 && 오버레이 시계 안 보임 1시간 && 메뉴바 라벨이 분 단위")은 캐릭터를 켠 사람과
// 근무 첫 1시간에는 영영 감속하지 않았다 — 그 두 경우가 곧 대부분의 근무 시간이었다.
//
// 감속이 늦춰도 되는 것은 **판정 시점**뿐이고, 보이는 값과 사건은 제시각에 일어나야 한다:
//  · 분 경계: HH:MM 이 실제 분 넘김보다 늦게 바뀌지 않는다(정렬).
//  · 마감 정밀 깨움: 마일스톤(1h/4h/랩)·부재 마감·장기근무 확인/마감·유예형 배너 만료가 분 경계보다 앞서면 그 시각에 깨운다.
//    깨움 계산은 evaluate* 가 쓰는 **같은 상수·같은 가드**에서 나온다(어긋나면 실패하는 테스트가 아래에 있다).

private let minuteStubUserID = "00000000-0000-0000-0000-000000000042"

/// 고정 픽스처 시각: 어느 날의 KST 정오(자정 클리핑에서 멀다).
private let t0 = TeamWeeklyGoal.koreanDayStart(for: Date(timeIntervalSince1970: 1_800_000_000))
    .addingTimeInterval(12 * 3600)

private func fixedDefaults(_ suiteName: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private func inertTokenStore(suiteName: String) -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    return TokenUsageStore(
        defaults: fixedDefaults(suiteName + ".token"),
        homeDirectory: tmp.appendingPathComponent("check-v0243-tick-home-\(suiteName)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-v0243-tick-cache-\(suiteName).json", isDirectory: false)
    )
}

private final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
private func makeStore(host: String, suiteName: String, clock: TestClock) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: fixedDefaults(suiteName),
        workspaceNotifications: nil,
        tokenUsage: inertTokenStore(suiteName: suiteName)
    )
    store.clock = { clock.now }
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: minuteStubUserID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.membershipConfirmed = true
    return store
}

@MainActor
private func cancelTasks(_ store: WorkTimerStore) {
    store.tickerTask?.cancel()
    store.refreshTask?.cancel()
    store.syncTask?.cancel()
    store.pokePollTask?.cancel()
    store.wakeGateTask?.cancel()
}

private let fixtureSessionID = WorkTimerStore.canonicalSessionID("aaaaaaaa-0000-0000-0000-0000000000c3")!

/// 근무 중 픽스처. start() 를 타지 않는다(큐/링 부수효과 없이 티커 계약만 본다).
@MainActor
private func beginWork(_ store: WorkTimerStore, startedAt: Date) {
    store.startedAt = startedAt
    store.currentSessionID = fixtureSessionID
    store.accumulatedSeconds = 0
    store.accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: startedAt)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
}

/// 팝오버 닫힘 + 오버레이 켬 상태로 근무를 시작하고, 감속 유예(60초)를 채운 뒤 지금 시각을 돌려준다.
/// `todayAtNow` 는 유예가 끝난 시각의 오늘 누적(초)이다.
@MainActor
private func beginSlowedWork(_ store: WorkTimerStore, clock: TestClock, todayAtNow: Int) -> Date {
    let now = t0.addingTimeInterval(WorkTimerStore.tickerSlowdownAfterSeconds)
    beginWork(store, startedAt: now.addingTimeInterval(-TimeInterval(todayAtNow)))
    store.setOverlayEnabled(true)
    #expect(!store.isMenuPresented)
    clock.now = t0
    store.tick()                       // 초 표시 화면이 없어진 시각(t0)을 장부에 적는다
    clock.now = now
    store.tick()                       // 유예가 찼다
    return now
}

private final class FireFlag: @unchecked Sendable {
    var fired = false
}

@MainActor
@Suite struct V0243MinuteTickTests {

    // MARK: 1. 두 시계 모두 시:분

    @Test func overlayLabelAndMenuBarTitleAreAlwaysHoursMinutes() {
        // 캐릭터 라벨: 종전엔 1시간 전 MM:SS, 뒤 HH:MM:SS 였다.
        #expect(CheckOverlayTimeFormatter.text(0) == "00:00")
        #expect(CheckOverlayTimeFormatter.text(299) == "00:04")
        #expect(CheckOverlayTimeFormatter.text(300) == "00:05")
        #expect(CheckOverlayTimeFormatter.text(3_599) == "00:59")
        #expect(CheckOverlayTimeFormatter.text(3_600) == "01:00")
        #expect(CheckOverlayTimeFormatter.text(4_980) == "01:23")
        #expect(CheckOverlayTimeFormatter.text(12 * 3_600 + 34 * 60 + 56) == "12:34")
        #expect(CheckOverlayTimeFormatter.text(-10) == "00:00")

        // 메뉴바 제목: 종전엔 1시간 전 MM:SS("01:24")였다.
        #expect(MenuBarStatusFormatter.title(for: WorkStatusSnapshot(status: .working, elapsedSeconds: 84)) == "00:01")
        #expect(MenuBarStatusFormatter.title(for: WorkStatusSnapshot(status: .working, elapsedSeconds: 3_661)) == "01:01")
        #expect(MenuBarStatusFormatter.title(for: WorkStatusSnapshot(status: .working, elapsedSeconds: 86_340)) == "23:59")
        #expect(
            MenuBarStatusFormatter.title(for: WorkStatusSnapshot(status: .working, elapsedSeconds: 84).markingAwayRestorable(true))
                == "00:01•"
        )
        // 비근무·대기 제목은 한 글자도 안 바뀐다.
        #expect(MenuBarStatusFormatter.title(for: WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)) == "오프")
        #expect(MenuBarStatusFormatter.title(for: WorkStatusSnapshot(status: .working, elapsedSeconds: 84, pendingSync: true)) == "대기")
        // 팝오버 오늘 시계가 쓰는 duration(_:) 은 그대로 MM:SS 다(팝오버 안 표시는 변경 대상이 아니다).
        #expect(MenuBarStatusFormatter.duration(84) == "01:24")
        #expect(MenuBarStatusFormatter.duration(3_661) == "01:01")
    }

    // MARK: 2·3. 팝오버가 닫히면 근무 첫 1분부터 분 경계 틱, 열려 있으면 1초

    @Test func tickerSlowsToTheMinuteBoundaryOnceThePopoverHasBeenClosedForAMinute() {
        let clock = TestClock(t0)
        let store = makeStore(host: "v0243-tick-slow", suiteName: "check-v0243-tick-slow", clock: clock)
        defer { cancelTasks(store) }
        // 근무 10분째 + 캐릭터 켬 — 종전 규칙에선 두 조건 각각이 감속을 영원히 막았다(라벨 MM:SS · 오버레이 시계 표시).
        beginWork(store, startedAt: t0.addingTimeInterval(-600))
        store.setOverlayEnabled(true)
        #expect(store.overlayClockIsShowing)
        #expect(!store.isMenuPresented)

        store.tick()
        #expect(store.nextTickDelay(now: clock.now) == 1)
        clock.now = t0.addingTimeInterval(59)
        store.tick()
        #expect(store.nextTickDelay(now: clock.now) == 1, "유예(60초)가 차기 전에 감속했다.")

        clock.now = t0.addingTimeInterval(60)
        store.tick()
        #expect(store.todayDuration(at: clock.now) == 660)
        #expect(store.nextTickDelay(now: clock.now) == 60, "종전 규칙에선 1 이었다 — 시:분 시계에선 60 이어야 한다.")
        // 분 경계 정렬: 분에서 23초 지난 시각이면 다음 분 넘김까지 37초.
        #expect(store.nextTickDelay(now: t0.addingTimeInterval(60 + 23)) == 37)

        // 감속 틱 10회 — 누적과 두 라벨은 주기와 무관하게 정확하고, 분 경계마다 시:분이 넘어간다.
        for minute in 1...10 {
            clock.now = t0.addingTimeInterval(60 + 60 * Double(minute))
            store.tick()
            let expected = 660 + 60 * minute
            #expect(store.todayDuration(at: clock.now) == expected)
            #expect(store.menuBarTitle == String(format: "%02d:%02d", expected / 3_600, (expected % 3_600) / 60))
            #expect(CheckOverlayTimeFormatter.text(store.overlayTodayDuration) == store.menuBarTitle)
            #expect(store.nextTickDelay(now: clock.now) == 60)
        }

        // 실제 티커 루프도 60 을 고른다.
        store.startTimer()
        #expect(store.armNextTickDelay() == 60)
        #expect(store.currentTickDelay == 60)

        // 팝오버가 열리면 즉시 1초(옛 루프 취소 + 새 루프).
        let slowLoop = store.tickerTask
        store.setMenuPresented(true)
        #expect(store.currentTickDelay == 1)
        #expect(slowLoop?.isCancelled == true)
        #expect(store.tickerTask != nil)
        #expect(store.nextTickDelay(now: clock.now) == 1)
        // 닫으면 다시 60초 유예부터 센다(디바운스) — 여닫기 흔들림에 루프를 재생성하지 않는다.
        store.setMenuPresented(false)
        store.tick()
        #expect(store.nextTickDelay(now: clock.now) == 1)
        clock.now = clock.now.addingTimeInterval(60)
        store.tick()
        #expect(store.nextTickDelay(now: clock.now) == 60)
    }

    @Test func popoverOpenKeepsOneSecondTicksNoMatterHowLong() {
        let clock = TestClock(t0)
        let store = makeStore(host: "v0243-tick-open", suiteName: "check-v0243-tick-open", clock: clock)
        defer { cancelTasks(store) }
        beginWork(store, startedAt: t0.addingTimeInterval(-3_600))
        store.setOverlayEnabled(false)
        store.isMenuPresented = true
        for hour in 0...2 {
            clock.now = t0.addingTimeInterval(3_600 * Double(hour))
            store.tick()
            #expect(store.nextTickDelay(now: clock.now) == 1)
            #expect(store.displayIdleSince == nil)
        }
    }

    // MARK: 4. 마일스톤 정밀 깨움

    @Test func slowTickWakesExactlyAtTheNextMilestone() {
        // 1시간 마일스톤 5초 전 → 5 (분 경계와 같은 값이지만 규칙이 둘 다 성립한다).
        do {
            let clock = TestClock(t0)
            let store = makeStore(host: "v0243-tick-m1", suiteName: "check-v0243-tick-m1", clock: clock)
            defer { cancelTasks(store) }
            let now = beginSlowedWork(store, clock: clock, todayAtNow: 3_600 - 5)
            #expect(store.nextTickDelay(now: now) == 5)
        }
        // 4시간 마일스톤 1초 전 → 1.
        do {
            let clock = TestClock(t0)
            let store = makeStore(host: "v0243-tick-m4", suiteName: "check-v0243-tick-m4", clock: clock)
            defer { cancelTasks(store) }
            let now = beginSlowedWork(store, clock: clock, todayAtNow: 4 * 3_600 - 1)
            #expect(store.nextTickDelay(now: now) == 1)
        }
        // ★ 분 경계와 갈리는 경우: 서버가 준 미션 목표가 60의 배수가 아니면(10,000초) 랩 경계는 분 경계 사이에 온다.
        //   today = 9,980 → 분 경계까지 40초, 랩 경계까지 20초 → 20 이어야 한다(분 경계만 보면 40 — 20초 늦게 발화).
        do {
            let clock = TestClock(t0)
            let store = makeStore(host: "v0243-tick-lap", suiteName: "check-v0243-tick-lap", clock: clock)
            defer { cancelTasks(store) }
            store.ultraMissionTargetSeconds = 10_000
            let now = beginSlowedWork(store, clock: clock, todayAtNow: 10_000 - 20)
            #expect(store.nextTickDelay(now: now) == 20)
            // 두 번째 랩 경계도 같은 식이다(20,000): today = 19,970 → 분 경계 10초 vs 랩 30초 → 10.
            clock.now = now.addingTimeInterval(9_990)
            store.tick()
            #expect(store.todayDuration(at: clock.now) == 19_970)
            #expect(store.nextTickDelay(now: clock.now) == 10)
        }
        // 기본 목표(3시간)는 60의 배수라 분 경계와 겹친다: 3시간 20초 전 → 20.
        do {
            let clock = TestClock(t0)
            let store = makeStore(host: "v0243-tick-m3", suiteName: "check-v0243-tick-m3", clock: clock)
            defer { cancelTasks(store) }
            let now = beginSlowedWork(store, clock: clock, todayAtNow: 3 * 3_600 - 20)
            #expect(store.nextTickDelay(now: now) == 20)
        }
    }

    // MARK: 5. 부재·장기근무 마감 정밀 깨움

    @Test func slowTickWakesExactlyAtTheAwayDeadline() {
        let clock = TestClock(t0)
        let store = makeStore(host: "v0243-tick-away", suiteName: "check-v0243-tick-away", clock: clock)
        defer { cancelTasks(store) }
        // today 가 60의 배수(10,800 = 3시간)라 분 경계까지는 60 — 부재 마감 35초가 이긴다. 마지막 입력(8,965초 전)이
        // 세션 시작(10,800초 전) **뒤**여야 evaluateAwaySession 의 "시작 ≤ 마지막 입력" 가드를 통과한다.
        let now = beginSlowedWork(store, clock: clock, todayAtNow: 10_800)
        store.awayPolicy = AwayPolicy(
            closeThresholdSeconds: 9_000, restoreWindowSeconds: nil, dailyRestoreLimit: nil, restoresLeftToday: nil, serverNow: nil
        )
        store.awayOpenSession = AwayOpenSession(
            sessionID: fixtureSessionID, startedAt: store.startedAt, lastInputAt: nil, closeEligible: true
        )
        store.lastMeaningfulInputAt = now.addingTimeInterval(-(9_000 - 35))
        #expect(store.nextTickDelay(now: now) == 35)

        // 마감이 이미 지났으면(≤ now) 1 — 다음 틱이 곧바로 판정한다.
        store.lastMeaningfulInputAt = now.addingTimeInterval(-9_000)
        #expect(store.nextTickDelay(now: now) == 1)

        // 가드 하나라도 빠지면 부재 마감은 후보에서 빠진다(evaluateAwaySession 과 같은 가드).
        store.lastMeaningfulInputAt = now.addingTimeInterval(-(9_000 - 35))
        store.awayOpenSession = AwayOpenSession(
            sessionID: fixtureSessionID, startedAt: store.startedAt, lastInputAt: nil, closeEligible: false
        )
        #expect(store.nextTickDelay(now: now) == 60)
    }

    @Test func slowTickWakesExactlyAtTheLongSessionDeadlines() {
        let clock = TestClock(t0)
        let store = makeStore(host: "v0243-tick-long", suiteName: "check-v0243-tick-long", clock: clock)
        defer { cancelTasks(store) }
        let now = beginSlowedWork(store, clock: clock, todayAtNow: 7_260)
        // 12시간 카운트다운: 앵커 + 12h 가 25초 뒤 → 25.
        store.longSessionAnchor = now.addingTimeInterval(-(WorkTimerStore.longSessionThresholdSeconds - 25))
        #expect(store.nextTickDelay(now: now) == 25)
        // 확인 배너가 떠 있으면 30분 응답 창 만료가 마감이다: 12초 뒤 → 12.
        store.isLongSessionPromptActive = true
        store.promptShownAt = now.addingTimeInterval(-(WorkTimerStore.longSessionResponseWindowSeconds - 12))
        #expect(store.nextTickDelay(now: now) == 12)
        // 배너가 떠 있는데 표시 시각이 없으면(방어) 후보에서 빠진다 — evaluateLongSession 도 같은 경우 아무것도 안 한다.
        store.promptShownAt = nil
        #expect(store.nextTickDelay(now: now) == 60)
    }

    // MARK: 6. 60초 틱에서도 캐릭터 라벨은 분 경계에서 바뀐다

    @Test func overlayLabelAdvancesAtMinuteBoundariesUnderSlowTicks() {
        let clock = TestClock(t0)
        let store = makeStore(host: "v0243-tick-label", suiteName: "check-v0243-tick-label", clock: clock)
        defer { cancelTasks(store) }
        let now = beginSlowedWork(store, clock: clock, todayAtNow: 11 * 60)   // 00:11
        #expect(store.overlayClockIsShowing)
        #expect(CheckOverlayTimeFormatter.text(store.overlayTodayDuration) == "00:11")

        // 감속 틱 5회: 매 틱 overlayNow 가 대입되고(라벨 갱신), 라벨은 그 분의 값이다.
        var assigned = 0
        for minute in 1...5 {
            let flag = FireFlag()
            withObservationTracking { _ = store.overlayNow } onChange: { flag.fired = true }
            clock.now = now.addingTimeInterval(60 * Double(minute))
            store.tick()
            if flag.fired { assigned += 1 }
            #expect(store.overlayNow == clock.now)
            #expect(CheckOverlayTimeFormatter.text(store.overlayTodayDuration) == String(format: "00:%02d", 11 + minute))
        }
        #expect(assigned == 5)
        // 팝오버 시계는 그동안 얼어 있다(두 시계 분리 M1 유지).
        #expect(store.displayNow != store.overlayNow)
    }

    // MARK: 7. 자정 롤오버에서도 분 경계 정렬은 유지된다(시:분 시계엔 초 단위 구간이 없다)

    @Test func midnightRolloverKeepsTheMinuteAlignment() {
        let dayStart = TeamWeeklyGoal.koreanDayStart(for: t0)
        let lateNight = dayStart.addingTimeInterval(-1_800)   // 어제 23:30
        let clock = TestClock(lateNight)
        let store = makeStore(host: "v0243-tick-midnight", suiteName: "check-v0243-tick-midnight", clock: clock)
        defer { cancelTasks(store) }
        beginWork(store, startedAt: lateNight)
        store.setOverlayEnabled(true)
        store.tick()
        clock.now = lateNight.addingTimeInterval(60)
        store.tick()
        #expect(store.nextTickDelay(now: clock.now) == 60)

        clock.now = dayStart.addingTimeInterval(1_800 + 17)   // 00:30:17 — 오늘 누적 30분 17초
        store.tick()
        #expect(store.todayDuration(at: clock.now) == 1_817)
        #expect(store.menuBarTitle == "00:30")
        #expect(store.nextTickDelay(now: clock.now) == 43, "자정 뒤에도 분 경계 정렬(60 − 17)이어야 한다 — 종전 MM:SS 구간의 1초 복귀는 사라졌다.")
    }

    // MARK: 8. 마감 헬퍼는 evaluate* 와 같은 시각에 같은 판정을 낸다(같은 가드·같은 상수에서 나온다는 증거)

    @Test func deadlineHelpersAgreeWithTheEvaluators() throws {
        // 부재: 깨움 시각 D 에서는 마감하지 않고(부등호 `>`), D+1 에서 마감한다 — 감속 틱이 D 에 깨어 판정을 놓치지 않는다.
        do {
            let clock = TestClock(t0)
            let store = makeStore(host: "v0243-tick-agree-away", suiteName: "check-v0243-tick-agree-away", clock: clock)
            defer { cancelTasks(store) }
            let now = beginSlowedWork(store, clock: clock, todayAtNow: 10_800)   // 마지막 입력이 세션 시작 뒤가 되도록
            store.awayPolicy = AwayPolicy(
                closeThresholdSeconds: 9_000, restoreWindowSeconds: nil, dailyRestoreLimit: nil, restoresLeftToday: nil, serverNow: nil
            )
            store.awayOpenSession = AwayOpenSession(
                sessionID: fixtureSessionID, startedAt: store.startedAt, lastInputAt: nil, closeEligible: true
            )
            store.lastMeaningfulInputAt = now.addingTimeInterval(-(9_000 - 35))
            let deadline = try #require(store.awayCloseDeadline())
            #expect(deadline == now.addingTimeInterval(35))
            clock.now = deadline
            store.tick()
            #expect(store.startedAt != nil, "마감 정각에 끊었다 — evaluateAwaySession 의 부등호는 `>` 다.")
            #expect(store.nextTickDelay(now: clock.now) == 1, "정각에 깨어난 다음 틱은 1초 뒤여야 판정이 바로 따라온다.")
            clock.now = deadline.addingTimeInterval(1)
            store.tick()
            #expect(store.startedAt == nil, "마감 1초 뒤에도 안 끊었다 — 헬퍼와 판정의 가드가 어긋났다.")
        }
        // 장기근무: 12시간 정각엔 배너가 없고 1초 뒤에 뜬다; 배너가 뜨면 마감 후보가 응답 창 만료로 바뀐다.
        do {
            let clock = TestClock(t0)
            let store = makeStore(host: "v0243-tick-agree-long", suiteName: "check-v0243-tick-agree-long", clock: clock)
            defer { cancelTasks(store) }
            let now = beginSlowedWork(store, clock: clock, todayAtNow: 7_260)
            store.longSessionAnchor = now.addingTimeInterval(-(WorkTimerStore.longSessionThresholdSeconds - 25))
            let deadline = try #require(store.longSessionDeadline())
            #expect(deadline == now.addingTimeInterval(25))
            #expect(store.longSessionPhase() == .countingDown(anchor: store.longSessionAnchor!))
            clock.now = deadline
            store.tick()
            #expect(!store.isLongSessionPromptActive)
            clock.now = deadline.addingTimeInterval(1)
            store.tick()
            #expect(store.isLongSessionPromptActive)
            #expect(store.promptShownAt == clock.now)
            #expect(store.longSessionPhase() == .promptOpen(shownAt: clock.now))
            #expect(store.longSessionDeadline() == clock.now.addingTimeInterval(WorkTimerStore.longSessionResponseWindowSeconds))
        }
        // 마일스톤: 1시간 5초 전 → 깨움 5초 뒤, 그 틱에서 1시간 축하가 발화한다(임계 상수를 공유한다).
        do {
            let clock = TestClock(t0)
            let store = makeStore(host: "v0243-tick-agree-ms", suiteName: "check-v0243-tick-agree-ms", clock: clock)
            defer { cancelTasks(store) }
            let now = beginSlowedWork(store, clock: clock, todayAtNow: 3_600 - 5)
            let fired = FireFlag()
            store.onReactionTrigger = { kind in if kind == .milestone { fired.fired = true } }
            let deadline = try #require(store.nextMilestoneDeadline(now: now))
            #expect(deadline == now.addingTimeInterval(5))
            #expect(!fired.fired)
            clock.now = deadline
            store.tick()
            #expect(fired.fired, "깨움 시각(1시간 정각)의 틱에서 마일스톤이 발화하지 않았다.")
            // 다음 후보는 4시간(기본 미션 목표 3시간은 60의 배수라 그 사이 랩 경계 10,800 이 먼저다).
            #expect(store.nextMilestoneDeadline(now: clock.now) == clock.now.addingTimeInterval(TimeInterval(3 * 3_600 - 3_600)))
        }
    }

    // MARK: 9. 소스 계약 — 감속 게이트에서 오버레이·라벨 조건이 사라졌고, 제목은 titleDuration, 팝오버 시계는 duration 그대로

    @Test func sourceContractsForTheMinuteClock() throws {
        let store = strippingSwiftComments(try String(contentsOf: sourceURL("WorkTimerStore.swift"), encoding: .utf8))
        let gateStart = try #require(store.range(of: "func nextTickDelay(now: Date) -> TimeInterval {"))
        let gateEnd = try #require(store.range(of: "func slowTickDelay(now: Date)", range: gateStart.upperBound..<store.endIndex))
        let gate = String(store[gateStart.upperBound..<gateEnd.lowerBound])
        #expect(gate.contains("secondsSurfaceVisible"))
        #expect(!gate.contains("overlayClockIsShowing"), "감속 게이트가 다시 오버레이를 본다 — 캐릭터를 켠 사람은 영영 감속하지 않는다.")
        #expect(!gate.contains("menuBarLabelIsMinuteGranular"))
        #expect(!store.contains("func menuBarLabelIsMinuteGranular"), "지운 판정이 되살아났다 — 제목이 항상 시:분이라 언제나 참이다.")
        // 임계 상수는 두 소비자가 공유한다 — 발화 지점에 숫자 리터럴이 되돌아오면 깨움과 갈린다.
        let msStart = try #require(store.range(of: "func evaluateTimeMilestones(now: Date) {"))
        let msEnd = try #require(store.range(of: "let lap = ", range: msStart.upperBound..<store.endIndex))
        let milestones = String(store[msStart.upperBound..<msEnd.lowerBound])
        #expect(milestones.contains("Self.milestoneHourFourSeconds") && milestones.contains("Self.milestoneHourOneSeconds"))
        #expect(!milestones.contains("4 * 3_600") && !milestones.contains(">= 3_600"))

        let formatter = strippingSwiftComments(try String(contentsOf: sourceURL("MenuBarStatusFormatter.swift"), encoding: .utf8))
        let titleStart = try #require(formatter.range(of: "static func title(for snapshot: WorkStatusSnapshot) -> String {"))
        let titleEnd = try #require(formatter.range(of: "static func symbolName", range: titleStart.upperBound..<formatter.endIndex))
        let title = String(formatter[titleStart.upperBound..<titleEnd.lowerBound])
        #expect(title.contains("titleDuration("))
        #expect(!title.contains(" duration("), "메뉴바 제목이 다시 MM:SS(duration) 를 쓴다.")

        let menu = strippingSwiftComments(try String(contentsOf: sourceURL("CheckMenuView.swift"), encoding: .utf8))
        #expect(menu.contains("MenuBarStatusFormatter.duration(store.todayDuration)"), "팝오버 오늘 시계는 변경 대상이 아니다 — MM:SS(duration) 그대로여야 한다.")

        let overlay = strippingSwiftComments(try String(contentsOf: sourceURL("CheckCharacter3DView.swift"), encoding: .utf8))
        let fmtStart = try #require(overlay.range(of: "enum CheckOverlayTimeFormatter {"))
        let fmt = String(overlay[fmtStart.upperBound...].prefix(400))
        #expect(fmt.contains("titleDuration("))
        #expect(!fmt.contains("%02d:%02d:%02d"), "캐릭터 라벨에 초가 되돌아왔다.")
    }
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다(하우스 규칙 — 안 그러면 설명을 지워야 초록이 된다). 문자열 리터럴 안은 남긴다.
private func strippingSwiftComments(_ source: String) -> String {
    var result = ""
    var inString = false, inLineComment = false, inBlockComment = false
    var previous: Character = " "
    let characters = Array(source)
    var index = 0
    while index < characters.count {
        let c = characters[index]
        let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
        if inLineComment {
            if c == "\n" { inLineComment = false; result.append(c) }
        } else if inBlockComment {
            if c == "*", next == "/" { inBlockComment = false; index += 1 }
        } else if inString {
            if c == "\"", previous != "\\" { inString = false }
            result.append(c)
        } else if c == "/", next == "/" {
            inLineComment = true
            index += 1
        } else if c == "/", next == "*" {
            inBlockComment = true
            index += 1
        } else {
            if c == "\"" { inString = true }
            result.append(c)
        }
        previous = c
        index += 1
    }
    return result
}

private func sourceURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Tests/checkTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("Sources/check/\(name)")
}
