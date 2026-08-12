import Foundation
import Testing
@testable import check

// MARK: - 살아 있는 눈(깜빡임) · 첫 출근 인사

@MainActor
private func isolatedDefaults() -> UserDefaults {
    let name = "check-blink-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
private func makeStore(_ defaults: UserDefaults) -> WorkTimerStore {
    WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
}

private func member(
    id: String,
    status: WorkStatus,
    todaySeconds: Int
) -> TeamMemberStatus {
    TeamMemberStatus(
        id: id,
        name: "팀원\(id)",
        status: status,
        updatedAt: nil,
        currentSessionStartedAt: status == .working ? Date() : nil,
        weeklyDurationSeconds: 0,
        todayDurationSeconds: todaySeconds,
        avatarURL: nil,
        lastSeenAt: nil,
        activeSessionID: nil
    )
}

// MARK: 깜빡임

@MainActor
@Test
func blinkOnlyRunsWhenIdleAndRendering() async {
    // 깜빡임은 자는 눈 자산을 아주 짧게 켰다 끄는 것이라, 자는 중(이미 감김)·리액션 중(그 연출이 표정을 씀)에는
    // 스스로 물러나야 한다. 렌더가 꺼져 있을 때도 마찬가지 — 보이지도 않는데 FPS 를 올릴 이유가 없다.
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 900_000) })

    // 렌더 꺼짐 → 아무 일도 없다(자산 미준비 상태라도 크래시 없이 통과해야 한다).
    engine.renderActive = false
    engine.blink()
    #expect(engine.state == .idle)

    // 렌더 켜도 자산(sleepDiffuse)이 없는 헤드리스에서는 조용히 no-op — 이 계약이 없으면
    // SceneKit 뷰가 붙지 않는 테스트/미리보기에서 깜빡임이 크래시한다.
    engine.renderActive = true
    engine.blink()
    #expect(engine.state == .idle)
}

@MainActor
@Test
func blinkIntervalRangeStaysAmbient() {
    // 간격이 사람 깜빡임(≈3~5초)보다 너무 촘촘하면 메뉴바 옆 작은 캐릭터에서는 '떨림'으로 읽힌다.
    // 상한도 묶어 둔다 — 너무 성기면 '살아 있음'이 전달되지 않는다.
    #expect(CheckOverlayController.blinkIntervalRange.lowerBound >= 2.5)
    #expect(CheckOverlayController.blinkIntervalRange.upperBound <= 10)
    // 깜빡임 자체는 0.1~0.15초여야 한다. 더 길면 조는 것으로 보인다.
    #expect(ReactionEngine.blinkSeconds >= 0.08)
    #expect(ReactionEngine.blinkSeconds <= 0.2)
}

// MARK: 첫 출근 인사

@MainActor
@Test
func firstArrivalRequiresEveryoneElseToBeIdleToday() {
    let store = makeStore(isolatedDefaults())
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    let me = "00000000-0000-0000-0000-0000000000AA"
    store.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: me)

    // 팀 목록이 아직 없으면 판정 불가 → false(모를 때 축하하지 않는다).
    #expect(store.isFirstArrivalToday == false)

    // 나뿐인 팀도 false — 매일 "1등"이 뜨면 축하가 아니라 소음이다.
    store.teamMembers = [member(id: me, status: .offWork, todaySeconds: 0)]
    #expect(store.isFirstArrivalToday == false)

    // 아무도 오늘 일한 적 없고 근무 중도 아니다 → 내가 1등.
    store.teamMembers = [
        member(id: me, status: .offWork, todaySeconds: 0),
        member(id: "B", status: .offWork, todaySeconds: 0),
        member(id: "C", status: .offWork, todaySeconds: 0)
    ]
    #expect(store.isFirstArrivalToday)

    // 누군가 이미 오늘 근무 기록이 있으면 1등이 아니다.
    store.teamMembers = [
        member(id: me, status: .offWork, todaySeconds: 0),
        member(id: "B", status: .offWork, todaySeconds: 1),
        member(id: "C", status: .offWork, todaySeconds: 0)
    ]
    #expect(store.isFirstArrivalToday == false)

    // 기록은 0이어도 지금 근무 중인 사람이 있으면 1등이 아니다(방금 시작한 사람).
    store.teamMembers = [
        member(id: me, status: .offWork, todaySeconds: 0),
        member(id: "B", status: .working, todaySeconds: 0)
    ]
    #expect(store.isFirstArrivalToday == false)
}

// MARK: 밤샘 — 자정을 넘겨 이어서 일하는 경우

@MainActor
@Test
func overnightWorkerIsNotGreetedAsFirstArrival() {
    // 전날 22시에 시작해 새벽까지 일한 사람. 새벽 3시에 끊고 3시 반에 다시 켜면 남들은 다 자고 있어
    // '팀에서 오늘 처음'이 성립해 버린다 — 하지만 그 사람은 도착한 적이 없고 밤새 앉아 있었다.
    let store = makeStore(isolatedDefaults())
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    let me = "00000000-0000-0000-0000-0000000000AA"
    store.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: me)
    store.teamMembers = [
        member(id: me, status: .offWork, todaySeconds: 0),
        member(id: "B", status: .offWork, todaySeconds: 0)
    ]

    // 새벽 3:30(KST). 자정~3시를 이미 일해 누적에 오늘 몫이 들어 있다.
    let earlyMorning = Date(timeIntervalSince1970: 1_800_000)
    let dayStart = TeamWeeklyGoal.koreanDayStart(for: earlyMorning)
    store.clock = { earlyMorning }
    store.accumulatedSeconds = 3 * 3600
    store.accumulatedDayStart = dayStart
    #expect(store.isFirstArrivalToday == false)

    // 대조군: 같은 시각이라도 오늘 마친 근무가 없으면(진짜 새벽 출근) 1등이 맞다.
    store.accumulatedSeconds = 0
    #expect(store.isFirstArrivalToday)
}

@MainActor
@Test
func sessionCarriedOverFromYesterdayIsNotAnArrival() {
    // 밤샘 중 앱이 재시작돼 서버의 열린 세션을 이어받는 경로. 진행 중 세션은 아직 누적에 들어가지 않아
    // '오늘 마친 근무'는 0으로 보이지만, 세션 시작이 어제라면 그건 출근이 아니라 이어서 일하는 중이다.
    let store = makeStore(isolatedDefaults())
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    let me = "00000000-0000-0000-0000-0000000000AA"
    store.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: me)
    store.teamMembers = [
        member(id: me, status: .offWork, todaySeconds: 0),
        member(id: "B", status: .offWork, todaySeconds: 0)
    ]

    let earlyMorning = Date(timeIntervalSince1970: 1_800_000)
    store.clock = { earlyMorning }
    // 어제 22시에 시작해 아직 안 끝난 세션.
    store.startedAt = TeamWeeklyGoal.koreanDayStart(for: earlyMorning).addingTimeInterval(-2 * 3600)
    #expect(store.isFirstArrivalToday == false)

    // 대조군: 오늘 시작한 세션이면 1등이 맞다.
    store.startedAt = TeamWeeklyGoal.koreanDayStart(for: earlyMorning).addingTimeInterval(60)
    #expect(store.isFirstArrivalToday)
}

@MainActor
@Test
func teammateWorkingOvernightBlocksTheGreeting() {
    // 남이 밤샘 중이면(아직 근무중) 내가 아침에 켜도 1등이 아니다. 그 사람이 새벽에 끊었어도
    // 자정~종료 몫이 todayDurationSeconds 에 잡혀 마찬가지로 걸린다.
    let store = makeStore(isolatedDefaults())
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    let me = "00000000-0000-0000-0000-0000000000AA"
    store.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: me)

    // 아직 근무 중인 밤샘 팀원.
    store.teamMembers = [
        member(id: me, status: .offWork, todaySeconds: 0),
        member(id: "B", status: .working, todaySeconds: 0)
    ]
    #expect(store.isFirstArrivalToday == false)

    // 새벽에 끊은 밤샘 팀원(자정 이후 몫이 남아 있다).
    store.teamMembers = [
        member(id: me, status: .offWork, todaySeconds: 0),
        member(id: "B", status: .offWork, todaySeconds: 3 * 3600)
    ]
    #expect(store.isFirstArrivalToday == false)
}

@MainActor
@Test
func firstArrivalGreetingFiresOncePerDay() {
    let defaults = isolatedDefaults()
    let store = makeStore(defaults)
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    let me = "00000000-0000-0000-0000-0000000000AA"
    store.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: me)
    store.teamMembers = [
        member(id: me, status: .offWork, todaySeconds: 0),
        member(id: "B", status: .offWork, todaySeconds: 0)
    ]

    let morning = Date(timeIntervalSince1970: 1_800_000)
    #expect(store.consumeFirstArrivalGreeting(now: morning))
    // 같은 날 두 번째 출근(점심 뒤 재시작)에는 다시 뜨지 않는다.
    #expect(store.consumeFirstArrivalGreeting(now: morning.addingTimeInterval(3 * 3600)) == false)

    // 앱을 껐다 켜도(같은 defaults) 여전히 소비된 상태여야 한다 — 기록이 영속이라야 하루 1회가 성립한다.
    let relaunched = makeStore(defaults)
    defer { relaunched.tickerTask?.cancel(); relaunched.refreshTask?.cancel() }
    relaunched.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: me)
    relaunched.teamMembers = store.teamMembers
    #expect(relaunched.consumeFirstArrivalGreeting(now: morning.addingTimeInterval(4 * 3600)) == false)

    // 다음 날에는 다시 뜬다.
    #expect(relaunched.consumeFirstArrivalGreeting(now: morning.addingTimeInterval(26 * 3600)))
}

@MainActor
@Test
func firstArrivalDoesNotStealTheNudgeExplanation() {
    // 넛지 자동 시작은 "왜 저절로 시작됐는지"를 설명하는 더 급한 문구다. 1등 출근과 겹치면 그쪽이 이긴다.
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 910_000) })
    let store = makeStore(isolatedDefaults())
    defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
    let me = "00000000-0000-0000-0000-0000000000AA"
    store.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: me)
    store.currentTeamID = "10000000-0000-0000-0000-000000000001"
    store.teamMembers = [
        member(id: me, status: .offWork, todaySeconds: 0),
        member(id: "B", status: .offWork, todaySeconds: 0)
    ]
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: isolatedDefaults(), workspaceNotifications: nil
    )

    // 넛지가 오버라이드를 먼저 세운 상태로 표시 전이가 오면, 1등 문구가 덮어쓰지 않는다.
    controller.nudgeAutoStart()
    #expect(engine.commuteStartBubbleOverride?.text == CheckOverlayController.nudgeAutoStartText)
    store.stop()
    store.clearAutoStartSuppression()
}
