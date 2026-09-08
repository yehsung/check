import Foundation
import Testing
@testable import check

// MARK: - AF: 자리 비움 자동 마감 — 사람 시나리오 고정 (v0.2.35 / docs/away-close.md)
//
// 이 스위트는 **구현 단위가 아니라 사람의 하루**를 고정한다. 공격 문서(attack-1..4)가 찾아낸 억울함은
// 전부 "판정이 틀렸다"가 아니라 "누구의 어떤 하루가 끊기는가"의 모양으로 왔고, 그 하루가 바뀌지 않는지는
// 구현 단위 테스트로는 드러나지 않는다(가드 하나하나는 초록인데 조합이 사람을 끊는다).
//
// 규약 셋:
//  1. **모든 시나리오에 대조군이 있다.** "안 끊긴다"만 단언하면 evaluateAwaySession 을 통째로 지워도 초록이다.
//     그래서 안전한 케이스마다 같은 조건에서 시각만 넘긴 짝을 두고 **그쪽은 실제로 끊기는지**를 함께 본다.
//  2. **시계는 주입하고 실네트워크로 새지 않는다.** 시각은 전부 KST 벽시계로 쓴다 — 심야 근무가 판정에
//     영향을 주지 않는다는 계약(시간대 미사용)은 벽시계로 써야만 실제로 검사된다.
//  3. **임계는 서버가 준 값으로만 판정한다.** 이 파일이 9000 을 쓰는 것은 서버 응답 픽스처
//     안에서뿐이고(docs/away-close.md 2절의 그 숫자), 클라 소스에 그 숫자가 없다는 것은 맨 아래
//     소스 계약 테스트가 지킨다.
//  4. **이어붙이기(복원)는 v0.2.46 에서 클라이언트에서 제거됐다.** 서버 응답(`restorable`)과 RPC 는
//     그대로 살아 있으므로 픽스처는 문서 모양을 유지하고, "실려 와도 아무 일도 일어나지 않는다"를
//     맨 아래 회귀 테스트 두 개가 지킨다.

// MARK: - 픽스처

private let afkUserID = "00000000-0000-0000-0000-000000000002"
private let afkSessionID = "50000000-0000-0000-0000-0000000000a1"

private func afkDefaults() -> UserDefaults {
    let suiteName = "check-afk-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// KST 벽시계 → Date. 시나리오를 "새벽 2시", "점심", "밤 11시"로 쓰기 위한 것이다 —
/// 이 기능은 시간대를 한 줄도 보지 않기로 했고, 그 계약은 벽시계로 써야 검사된다.
private func kst(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    )!
}

/// 스텁 네트워크에 물린 로그인 상태 스토어. 시계는 박스로 주입해 시나리오가 시간을 앞으로 민다.
@MainActor
private final class AFKClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
private func afkStore(host: String, clock: AFKClock) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: afkDefaults()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: afkUserID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.clock = { clock.now }
    store.inputSessionUsable = { true }
    // **관측 없음**(무한대)이 이 스위트의 기본값이다. 시나리오는 lastMeaningfulInputAt 을 직접 세우고
    // (afkBeginWork), evaluateAwaySession 은 판정 직전 advanceMeaningfulInput 을 부른다 — 그 관측이
    // idle=0 이면 모든 시나리오에서 "방금 입력했다"가 되어 마감이 통째로 죽는다. 무한대는
    // advanceMeaningfulInput 의 `idle.isFinite` 가드에 걸려 관측을 건드리지 않는다(= 시나리오 값 보존).
    // 관측을 실제로 쓰는 시나리오(S5 잠금, 입력 신선도)는 각자 이 클로저를 덮어쓴다.
    store.meaningfulIdleSeconds = { .infinity }
    return store
}

/// 근무 중 상태를 세운다(start() 는 네트워크 큐를 흔들므로 시나리오는 상태를 직접 세운다 —
/// 판정 함수의 입력은 startedAt / currentSessionID / lastMeaningfulInputAt / 서버 응답 넷뿐이다).
@MainActor
private func afkBeginWork(_ store: WorkTimerStore, startedAt: Date, lastInput: Date? = nil) {
    store.startedAt = startedAt
    store.currentSessionID = WorkTimerStore.canonicalSessionID(afkSessionID)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    store.longSessionAnchor = startedAt
    store.lastMeaningfulInputAt = lastInput ?? startedAt
    store.accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: startedAt)
    store.accumulatedSeconds = 0
}

/// docs/away-close.md 2절의 away_sync() 응답을 **문서에 적힌 모양 그대로** 만들어 실제 디코드 경로로 통과시킨다.
/// 임계·복원 창이 이 파일의 상수가 아니라 **서버 응답에서** 온다는 사실이 여기서 지켜진다.
private func afkAwaySyncJSON(
    startedAt: Date?,
    lastInputAt: Date?,
    closeEligible: Bool,
    sessionID: String = afkSessionID,
    restorable: (sessionID: String, startedAt: Date, endedAt: Date, reason: String, now: Date)? = nil,
    closeThresholdSeconds: Int? = 9000,
    restoreWindowSeconds: Int = 21600
) -> String {
    let formatter = ISO8601DateFormatter()
    func stamp(_ date: Date) -> String { formatter.string(from: date) }
    var fields: [String] = [#""status":"ok""#]
    if let closeThresholdSeconds {
        fields.append("\"closeThresholdSeconds\":\(closeThresholdSeconds)")
        fields.append("\"backstopSeconds\":\(closeThresholdSeconds + 1800)")
    }
    fields.append("\"freezeSeconds\":1800")
    fields.append("\"restoreWindowSeconds\":\(restoreWindowSeconds)")
    fields.append("\"dailyRestoreLimit\":2")
    fields.append(#""restorableReasons":["away","sleep"]"#)
    fields.append("\"restoresUsedToday\":0")
    fields.append("\"restoresLeftToday\":2")
    if let startedAt {
        var open: [String] = ["\"id\":\"\(sessionID)\"", "\"teamId\":\"\(URLProtocolStub.stubTeamID)\""]
        open.append("\"startedAt\":\"\(stamp(startedAt))\"")
        if let lastInputAt { open.append("\"lastInputAt\":\"\(stamp(lastInputAt))\"") }
        open.append("\"closeEligible\":\(closeEligible)")
        fields.append("\"openSession\":{\(open.joined(separator: ","))}")
    }
    if let restorable {
        // 창 판정은 **서버가** 한다: expiresAt = endedAt + restoreWindow, remainingSeconds 는 그 잔여다.
        let expiresAt = restorable.endedAt.addingTimeInterval(TimeInterval(restoreWindowSeconds))
        let remaining = max(0, Int(expiresAt.timeIntervalSince(restorable.now)))
        let payload = [
            "\"sessionId\":\"\(restorable.sessionID)\"",
            "\"teamId\":\"\(URLProtocolStub.stubTeamID)\"",
            "\"startedAt\":\"\(stamp(restorable.startedAt))\"",
            "\"endedAt\":\"\(stamp(restorable.endedAt))\"",
            "\"durationSeconds\":\(max(0, Int(restorable.endedAt.timeIntervalSince(restorable.startedAt))))",
            "\"autoClosedAt\":\"\(stamp(restorable.endedAt))\"",
            "\"autoClosedReason\":\"\(restorable.reason)\"",
            "\"expiresAt\":\"\(stamp(expiresAt))\"",
            "\"remainingSeconds\":\(remaining)"
        ]
        fields.append("\"restorable\":{\(payload.joined(separator: ","))}")
    }
    return "{\(fields.joined(separator: ","))}"
}

/// 서버 응답 문자열 → 스토어 상태. **실제 디코더와 실제 도메인 변환**을 지난다(정책이 이 경로로만 선다).
@MainActor
private func afkApplyAwaySync(_ store: WorkTimerStore, json: String) async {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let response = try! decoder.decode(AwaySyncResponse.self, from: Data(json.utf8))
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://afk-decode")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let sync = await service.awaySync(from: response)
    store.applyAwaySync(sync)
}

/// 조건이 참이 될 때까지(또는 상한까지) 기다린다. 자동 재개는 RPC 왕복 뒤에 로컬 상태를 세우므로
/// 고정 sleep 으로는 부하 상황에서 흔들린다 — 조건 폴링이 그 축을 없앤다.
@MainActor
private func afkWait(untilTimeout seconds: Double, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(), Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private func afkIsWorking(_ store: WorkTimerStore) -> Bool { store.startedAt != nil }

// MARK: - S1. 운동 90분 / 멘토링 2시간 — 끊기지 않는다

/// 사장님이 안전해야 한다고 못 박은 두 사례. 임계(2시간 30분)는 **서버가 준 값**이고, 이 테스트는
/// 그 값보다 짧은 부재가 하나도 끊기지 않는지를 본다. 대조군(2시간 31분)이 없으면 마감을 통째로
/// 지워도 초록이므로 반드시 함께 본다.
@MainActor
@Test
func gymNinetyMinutesAndMentoringTwoHoursSurvive() async throws {
    let start = kst(2026, 8, 19, 9, 0)
    let lastInput = kst(2026, 8, 19, 10, 0)

    // ① 운동 90분: 10:00 마지막 입력 → 11:30 복귀.
    let gymClock = AFKClock(kst(2026, 8, 19, 11, 30))
    let gym = afkStore(host: "afk-gym", clock: gymClock)
    afkBeginWork(gym, startedAt: start, lastInput: lastInput)
    await afkApplyAwaySync(gym, json: afkAwaySyncJSON(startedAt: start, lastInputAt: lastInput, closeEligible: true))
    gym.evaluateAwaySession(now: gymClock.now)
    #expect(afkIsWorking(gym))

    // ② 멘토링 2시간: 12:00 까지 자리에 없다.
    let mentoringClock = AFKClock(kst(2026, 8, 19, 12, 0))
    let mentoring = afkStore(host: "afk-mentoring", clock: mentoringClock)
    afkBeginWork(mentoring, startedAt: start, lastInput: lastInput)
    await afkApplyAwaySync(
        mentoring,
        json: afkAwaySyncJSON(startedAt: start, lastInputAt: lastInput, closeEligible: true)
    )
    mentoring.evaluateAwaySession(now: mentoringClock.now)
    #expect(afkIsWorking(mentoring))

    // ③ 경계는 **배타적**이다: 정확히 2시간 30분은 아직 근무다(서버 부등호와 같은 눈금).
    //    여기가 >= 로 뒤집히면 서버 백스톱과 클라가 서로 다른 순간에 마감해 ended_at 이 갈린다.
    let boundaryClock = AFKClock(lastInput)
    let boundary = afkStore(host: "afk-boundary", clock: boundaryClock)
    afkBeginWork(boundary, startedAt: start, lastInput: lastInput)
    await afkApplyAwaySync(
        boundary,
        json: afkAwaySyncJSON(startedAt: start, lastInputAt: lastInput, closeEligible: true)
    )
    // 임계는 **서버가 준 값**이다 — 이 테스트도 그 값을 서버 응답에서 읽어 경계를 만든다.
    let threshold = try #require(boundary.awayPolicy?.closeThresholdSeconds)
    let boundaryNow = lastInput.addingTimeInterval(threshold)
    boundaryClock.now = boundaryNow
    boundary.evaluateAwaySession(now: boundaryNow)
    #expect(afkIsWorking(boundary))

    // ④ 대조군: 2시간 31분이면 실제로 끊긴다(위 셋이 '기능이 죽어서' 살아남은 게 아님을 증명한다).
    let overClock = AFKClock(kst(2026, 8, 19, 12, 31))
    let over = afkStore(host: "afk-over-threshold", clock: overClock)
    afkBeginWork(over, startedAt: start, lastInput: lastInput)
    await afkApplyAwaySync(over, json: afkAwaySyncJSON(startedAt: start, lastInputAt: lastInput, closeEligible: true))
    over.evaluateAwaySession(now: overClock.now)
    #expect(!afkIsWorking(over))
    #expect(over.pendingItems.last?.endedAt == lastInput)
    #expect(over.pendingItems.last?.autoCloseReason == .away)
}

// MARK: - S2. 점심 + 회의 3시간 — 마지막 입력 시각으로 소급 마감된다

/// 임계를 2시간 30분으로 낮춘 결과 **의도적으로** 끊기는 사례다(사장님 확정). 급소는 마감이
/// **소급**이라는 점이다 — 자리를 비운 2시간 31분이 근무로 남으면 임계를 낮춘 의미가 없다.
@MainActor
@Test
func lunchAndMeetingThreeHoursClosesBackAtTheLastInput() async throws {
    let start = kst(2026, 8, 19, 9, 0)
    let lastInput = kst(2026, 8, 19, 12, 0)
    let closedAt = kst(2026, 8, 19, 14, 31)     // 마지막 입력 + 2시간 31분(임계 초과 첫 틱)

    let clock = AFKClock(closedAt)
    let store = afkStore(host: "afk-lunch-meeting", clock: clock)
    afkBeginWork(store, startedAt: start, lastInput: lastInput)
    await afkApplyAwaySync(store, json: afkAwaySyncJSON(startedAt: start, lastInputAt: lastInput, closeEligible: true))

    store.evaluateAwaySession(now: closedAt)

    // 마감은 **소급**이다: 자리를 비운 2시간 31분은 근무로 남지 않는다.
    #expect(!afkIsWorking(store))
    #expect(store.pendingItems.last?.endedAt == lastInput)
    #expect(store.pendingItems.last?.autoCloseReason == .away)
    store.displayNow = closedAt
    #expect(store.todayDuration == 3 * 3_600)   // 09:00~12:00 만 남는다
}

// MARK: - S3. 새벽 2시에 30분 눈 붙였다 다시 일함 — 끊기지 않는다(시간대를 안 본다)

/// 이 앱 사용자의 11%가 자정을 넘겨 일한다. 판정에 hour-of-day 가 한 줄이라도 들어가면 그 사람들이
/// 낮보다 가혹한 규칙을 받는다. 그래서 **같은 부재 길이는 새벽이든 낮이든 같은 결과**여야 한다.
@MainActor
@Test
func napAtTwoAMSurvivesAndTimeOfDayNeverChangesTheVerdict() async throws {
    // ① 새벽 2시, 30분 눈 붙임 → 02:30 복귀. 끊기지 않는다.
    let nightStart = kst(2026, 8, 19, 22, 0)
    let nightInput = kst(2026, 8, 20, 1, 30)
    let nightNow = kst(2026, 8, 20, 2, 0)
    let napClock = AFKClock(nightNow)
    let nap = afkStore(host: "afk-night-nap", clock: napClock)
    afkBeginWork(nap, startedAt: nightStart, lastInput: nightInput)
    await afkApplyAwaySync(
        nap,
        json: afkAwaySyncJSON(startedAt: nightStart, lastInputAt: nightInput, closeEligible: true)
    )
    nap.evaluateAwaySession(now: nightNow)
    #expect(afkIsWorking(nap))

    // ② 시간대 무관 대조: **정확히 같은 상대 시각**을 새벽(03:00 마감 시점)과 낮(15:00)에 각각 돌린다.
    //    두 결과가 갈리면 판정에 시간대가 섞여 들어간 것이다.
    func verdict(host: String, start: Date, lastInput: Date, now: Date) async -> Bool {
        let clock = AFKClock(now)
        let store = afkStore(host: host, clock: clock)
        afkBeginWork(store, startedAt: start, lastInput: lastInput)
        await afkApplyAwaySync(
            store,
            json: afkAwaySyncJSON(startedAt: start, lastInputAt: lastInput, closeEligible: true)
        )
        store.evaluateAwaySession(now: now)
        return !afkIsWorking(store)
    }

    let nightClosed = await verdict(
        host: "afk-night-3h",
        start: kst(2026, 8, 19, 21, 0),
        lastInput: kst(2026, 8, 20, 0, 0),
        now: kst(2026, 8, 20, 3, 1)
    )
    let dayClosed = await verdict(
        host: "afk-day-3h",
        start: kst(2026, 8, 20, 9, 0),
        lastInput: kst(2026, 8, 20, 12, 0),
        now: kst(2026, 8, 20, 15, 1)
    )
    #expect(nightClosed == dayClosed)
    #expect(nightClosed)   // 3시간 부재는 새벽에도 낮과 **똑같이** 끊긴다(관대함도 시간대를 안 본다)
}

// MARK: - S4. 8시간 취침 — 뚜껑 닫은 순간으로 소급 마감된다

/// 밤 8시간이 근무로 남으면 안 된다. 마감 시각은 min(뚜껑 닫은 시각, 마지막 입력)이고, 사유는 sleep 이다
/// (사유가 abandoned 로 남으면 마감 시각·원인이 사실과 어긋난 채 서버에 쌓인다).
@MainActor
@Test
func eightHourSleepClosesBackAtTheMomentTheMacWentToSleep() async throws {
    let start = kst(2026, 8, 19, 20, 0)
    let lastInput = kst(2026, 8, 19, 22, 50)
    let lidClosed = kst(2026, 8, 19, 23, 0)
    let wake = kst(2026, 8, 20, 7, 0)

    let clock = AFKClock(lidClosed)
    let store = afkStore(host: "afk-overnight", clock: clock)
    afkBeginWork(store, startedAt: start, lastInput: lastInput)
    store.handleSleep(at: lidClosed)
    clock.now = wake
    store.handleWake(at: wake)

    // 잠자기 마감은 min(뚜껑, 마지막 입력)으로 소급된다 — 밤 8시간은 근무가 아니다.
    #expect(!afkIsWorking(store))
    #expect(store.pendingItems.last?.endedAt == lastInput)
    #expect(store.pendingItems.last?.autoCloseReason == .sleep)

    // 아침에 폴링이 한 번 더 돌아도 깎아 낸 밤은 되돌아오지 않는다.
    await afkApplyAwaySync(
        store,
        json: afkAwaySyncJSON(startedAt: nil, lastInputAt: nil, closeEligible: false)
    )
    #expect(!afkIsWorking(store))
    store.displayNow = wake
    #expect(store.todayDuration == 0)   // 마감분은 전날(8/19) 몫이라 8/20 오늘에는 한 초도 없다
}

// MARK: - S5. 잠그고 자러 감 — 잠근 시각부터 센다

/// 화면을 잠그면 그 뒤의 입력은 내 근무의 증거가 아니다(잠금 화면에서 남이 비밀번호를 두드릴 수도 있다).
/// 그래서 마감 시각은 **잠근 시각**이어야 하고, 잠금 중에는 관측이 한 번도 전진하면 안 된다.
@MainActor
@Test
func lockingTheScreenFreezesTheClockAtLockTime() async throws {
    let start = kst(2026, 8, 19, 13, 0)
    let lockedAt = kst(2026, 8, 19, 18, 0)
    let clock = AFKClock(lockedAt)
    let store = afkStore(host: "afk-locked", clock: clock)
    afkBeginWork(store, startedAt: start, lastInput: lockedAt)

    // 잠근 뒤: 잠금 화면에서 키가 눌려도(idle 5초) 관측은 잠근 시각에 멈춘다.
    store.inputSessionUsable = { false }
    store.meaningfulIdleSeconds = { 5 }
    for minutes in stride(from: 30, through: 210, by: 30) {
        clock.now = lockedAt.addingTimeInterval(TimeInterval(minutes) * 60)
        store.advanceMeaningfulInput(now: clock.now)
        #expect(store.lastMeaningfulInputAt == lockedAt)
    }

    let now = lockedAt.addingTimeInterval(2 * 3_600 + 31 * 60)
    clock.now = now
    await afkApplyAwaySync(
        store,
        json: afkAwaySyncJSON(startedAt: start, lastInputAt: lockedAt, closeEligible: true)
    )
    store.evaluateAwaySession(now: now)

    #expect(!afkIsWorking(store))
    // 마감 시각이 잠근 시각이다 — 잠금 화면의 입력으로 근무가 연장되면 여기가 늦어진다.
    #expect(store.pendingItems.last?.endedAt == lockedAt)

    // 대조군: 잠금이 풀리면(사람이 돌아왔다) 관측이 다시 전진한다 — 얼어붙는 것은 잠금뿐이다.
    let unlocked = afkStore(host: "afk-unlocked", clock: clock)
    afkBeginWork(unlocked, startedAt: start, lastInput: lockedAt)
    unlocked.meaningfulIdleSeconds = { 5 }
    unlocked.advanceMeaningfulInput(now: now)
    #expect(unlocked.lastMeaningfulInputAt == now.addingTimeInterval(-5))

    // 그리고 뒤로는 절대 가지 않는다. 유휴 관측이 갑자기 길어져도(이벤트 소스 리셋·시계 되돌림)
    // 이미 관측한 입력이 무효가 되면, 방금 타이핑한 사람이 과거 시각으로 마감된다.
    unlocked.meaningfulIdleSeconds = { 3 * 3_600 }
    unlocked.advanceMeaningfulInput(now: now)
    #expect(unlocked.lastMeaningfulInputAt == now.addingTimeInterval(-5))
}

// MARK: - S6. 맥 2대 — 아이맥 켜둔 채 노트북에서 작업

/// attack-4 의 결함 ③ 그 자체다. 아이맥의 로컬 관측은 09:10 에 멈추지만 사람은 노트북에서 계속
/// 타이핑하고 있다. 클라가 **로컬 단독**으로 판정하면 이 사람은 매일 결정론적으로 오마감된다
/// (서버 백스톱의 완화는 클라보다 30분 늦어 도달조차 못 한다).
@MainActor
@Test
func iMacLeftOnDoesNotCloseWhileTheLaptopKeepsTyping() async throws {
    let start = kst(2026, 8, 19, 9, 0)
    let iMacLastInput = kst(2026, 8, 19, 9, 10)
    let clock = AFKClock(iMacLastInput)
    let store = afkStore(host: "afk-two-macs", clock: clock)
    afkBeginWork(store, startedAt: start, lastInput: iMacLastInput)
    // 아이맥 앞에는 아무도 없다 — 이 맥의 관측은 영원히 09:10 이다.
    store.inputSessionUsable = { false }

    // 09:40 ~ 13:10, 30분마다 폴링. 서버는 매번 '노트북이 1분 전에 입력했다'를 들고 온다.
    for minutes in stride(from: 30, through: 240, by: 30) {
        let now = iMacLastInput.addingTimeInterval(TimeInterval(minutes) * 60)
        clock.now = now
        store.advanceMeaningfulInput(now: now)
        await afkApplyAwaySync(
            store,
            json: afkAwaySyncJSON(
                startedAt: start,
                lastInputAt: now.addingTimeInterval(-60),
                closeEligible: true
            )
        )
        store.evaluateAwaySession(now: now)
        #expect(afkIsWorking(store), "4시간 동안 한 틱이라도 마감되면 이 사람은 매일 오전을 잃는다")
    }

    // 혼합 함대(맥북이 구버전이라 last_input_at 을 안 싣는다): 서버가 closeEligible=false 로 답한다.
    // 클라는 서버 백스톱보다 30분 **먼저** 발화하므로, 이 게이트를 클라가 무시하면 서버에만 있는
    // 면제는 도달조차 못 하고 그 사람의 살아 있는 근무가 매일 지워진다(attack-4 결함 ②).
    let mixed = afkStore(host: "afk-mixed-fleet", clock: clock)
    afkBeginWork(mixed, startedAt: start, lastInput: iMacLastInput)
    let mixedNow = iMacLastInput.addingTimeInterval(6 * 3_600)
    clock.now = mixedNow
    await afkApplyAwaySync(
        mixed,
        json: afkAwaySyncJSON(startedAt: start, lastInputAt: iMacLastInput, closeEligible: false)
    )
    mixed.evaluateAwaySession(now: mixedNow)
    #expect(afkIsWorking(mixed), "구버전 맥이 섞인 사용자는 구버전이 사라질 때까지 통째로 면제다")

    // 대조군: 노트북도 조용해지면(서버가 든 max 가 09:10 에 멈춘다) 그때는 실제로 끊긴다.
    let silent = afkStore(host: "afk-two-macs-silent", clock: clock)
    afkBeginWork(silent, startedAt: start, lastInput: iMacLastInput)
    let now = iMacLastInput.addingTimeInterval(2 * 3_600 + 31 * 60)
    clock.now = now
    await afkApplyAwaySync(
        silent,
        json: afkAwaySyncJSON(startedAt: start, lastInputAt: iMacLastInput, closeEligible: true)
    )
    silent.evaluateAwaySession(now: now)
    #expect(!afkIsWorking(silent))
    #expect(silent.pendingItems.last?.endedAt == iMacLastInput)
}

// MARK: - S7. 흡수 세션 — 이 맥은 남의 근무를 마감하지 않는다

/// 다른 맥이 연 세션을 미러링 중인 맥에서는 '내 무입력'이 남의 근무의 증거가 아니다.
/// 대조군이 반드시 필요하다: 표식만 내리면 같은 조건에서 **실제로 마감돼야** 한다
/// (안 그러면 '남을 지켜 주는 가드'가 '아무도 못 닫는 세션'으로 뒤집힌 것을 이 스위트가 못 잡는다).
@MainActor
@Test
func adoptedSessionIsNeverClosedByThisMacsIdleness() async throws {
    let start = kst(2026, 8, 19, 9, 0)
    let lastInput = kst(2026, 8, 19, 9, 30)
    let now = kst(2026, 8, 19, 14, 0)
    let clock = AFKClock(now)

    let adopted = afkStore(host: "afk-adopted", clock: clock)
    afkBeginWork(adopted, startedAt: start, lastInput: lastInput)
    adopted.adoptedRemoteSession = true
    await afkApplyAwaySync(
        adopted,
        json: afkAwaySyncJSON(startedAt: start, lastInputAt: lastInput, closeEligible: true)
    )
    adopted.evaluateAwaySession(now: now)
    #expect(afkIsWorking(adopted))
    #expect(adopted.pendingItems.isEmpty)

    let owner = afkStore(host: "afk-adopted-control", clock: clock)
    afkBeginWork(owner, startedAt: start, lastInput: lastInput)
    await afkApplyAwaySync(
        owner,
        json: afkAwaySyncJSON(startedAt: start, lastInputAt: lastInput, closeEligible: true)
    )
    owner.evaluateAwaySession(now: now)
    #expect(!afkIsWorking(owner))
}

// MARK: - S9. 서버가 임계를 안 주면 마감하지 않는다

/// 사장님 확정 사항의 코드 쪽 반쪽. 구버전 서버·오프라인·RPC 실패는 전부 "모른다"이고,
/// 모를 때의 안전한 기본값은 **안 끊는다**다. 정책이 도착하면 같은 상태에서 즉시 끊긴다(대조군).
@MainActor
@Test
func withoutServerPolicyNothingIsEverClosed() async throws {
    let start = kst(2026, 8, 19, 9, 0)
    let lastInput = kst(2026, 8, 19, 10, 0)
    let now = kst(2026, 8, 19, 18, 0)          // 8시간 무입력 — 임계의 3배가 넘는다
    let clock = AFKClock(now)
    let store = afkStore(host: "afk-no-policy", clock: clock)
    afkBeginWork(store, startedAt: start, lastInput: lastInput)

    // 임계 키가 없는 응답(= 정책 없음). openSession 은 있고 자격도 참이지만 임계를 모른다.
    await afkApplyAwaySync(
        store,
        json: afkAwaySyncJSON(
            startedAt: start,
            lastInputAt: lastInput,
            closeEligible: true,
            closeThresholdSeconds: nil
        )
    )
    #expect(store.awayPolicy == nil)
    store.evaluateAwaySession(now: now)
    #expect(afkIsWorking(store))
    #expect(store.pendingItems.isEmpty)

    // 대조군: 다음 폴링에 임계가 도착하면 같은 무입력이 그 자리에서 마감된다.
    await afkApplyAwaySync(
        store,
        json: afkAwaySyncJSON(startedAt: start, lastInputAt: lastInput, closeEligible: true)
    )
    store.evaluateAwaySession(now: now)
    #expect(!afkIsWorking(store))
}

// MARK: - S12. 자동 재개(30분 창) — 이어붙이기 자리에 들어온 것 (v0.2.47)
//
// 규칙(사장님 확정): 자동 마감된 **내** 세션의 `ended_at` 이 지금으로부터 **30분 이내**이고 사유가
// `long_session` 이 아니면, 복귀가 감지되는 순간 배너 없이 그 세션을 되살린다(새 세션을 만들지 않는다).
//
// 이 스위트가 지키는 것은 하나다: **되살아나는 시간의 상한이 30분이다.** 되살아나는 양은 정확히
// `지금 − ended_at` 이고, v0.2.46 에서 지운 이어붙이기에는 이 상한이 없어 289분(4.8시간)짜리 수면을
// 근무로 되살렸다. 아래 케이스마다 대조군이 붙는다 — 상한만 검사하면 기능을 통째로 꺼도 초록이다.

/// 낮잠 20분은 되살아나고, **같은 경로의 4.8시간 수면은 되살아나지 않는다**(이어붙이기가 냈던 그 사고).
@MainActor
@Test
func shortSleepIsResumedWhileTheOldFourHourSleepBugIsNot() async throws {
    let start = kst(2026, 8, 19, 20, 0)
    let lastInput = kst(2026, 8, 19, 23, 0)
    let lidClosed = kst(2026, 8, 19, 23, 0)

    // ① 20분 낮잠 → 5분 뒤 복귀 감지. 갭 = 25분 ≤ 30분 → 재개 대상이다.
    let napClock = AFKClock(lidClosed)
    let nap = afkStore(host: "afk-resume-nap", clock: napClock)
    afkBeginWork(nap, startedAt: start, lastInput: lastInput)
    nap.handleSleep(at: lidClosed)
    let napWake = kst(2026, 8, 19, 23, 20)
    napClock.now = napWake
    nap.handleWake(at: napWake)
    #expect(!afkIsWorking(nap))
    #expect(nap.lastAutoClosedReason == .sleep)
    #expect(nap.lastAutoClosedEndedAt == lastInput)     // 앵커는 min(뚜껑, 마지막 입력)이다
    let napReturn = kst(2026, 8, 19, 23, 25)
    napClock.now = napReturn
    #expect(nap.canResumeRecentlyClosedSession(now: napReturn))

    // ② **대조군 — 제거된 이어붙이기가 냈던 바로 그 사고.** 같은 코드 경로로 4.8시간(289분)을 잔다.
    //    갭이 294분이라 창 밖이다 → 되살리지 않는다. 이 단언이 상한 그 자체다.
    let sleepClock = AFKClock(lidClosed)
    let deep = afkStore(host: "afk-resume-deep-sleep", clock: sleepClock)
    afkBeginWork(deep, startedAt: start, lastInput: lastInput)
    deep.handleSleep(at: lidClosed)
    let deepWake = lidClosed.addingTimeInterval(289 * 60)
    sleepClock.now = deepWake
    deep.handleWake(at: deepWake)
    #expect(!afkIsWorking(deep))
    #expect(deep.lastAutoClosedReason == .sleep)
    let deepReturn = deepWake.addingTimeInterval(5 * 60)
    sleepClock.now = deepReturn
    #expect(
        !deep.canResumeRecentlyClosedSession(now: deepReturn),
        "289분 수면이 근무로 되살아난다 — 30분 상한이 사라졌다(이어붙이기 제거 사유 그 자체)"
    )

    // ③ 경계를 양쪽에서: 같은 마감을 두고 '지금'만 움직인다.
    let inside = lastInput.addingTimeInterval(29 * 60)
    let outside = lastInput.addingTimeInterval(31 * 60)
    #expect(nap.canResumeRecentlyClosedSession(now: inside))
    #expect(!nap.canResumeRecentlyClosedSession(now: outside))
}

/// **away 마감은 사유 필터 없이도 창에 못 들어온다.** ended_at = 마지막 입력이고 마감은 그로부터
/// 임계(서버가 준 2시간 30분) 뒤에 발화하므로 갭이 언제나 30분을 넘는다. 이 산술이 계약이고,
/// 서버 임계를 30분 밑으로 내리면 깨진다(서버 함수 코멘트에 같은 경고가 있다).
@MainActor
@Test
func awayCloseCanNeverFallInsideTheResumeWindow() async throws {
    let start = kst(2026, 8, 19, 9, 0)
    let lastInput = kst(2026, 8, 19, 12, 0)
    let closedAt = kst(2026, 8, 19, 14, 31)     // 마지막 입력 + 2시간 31분(임계 초과 첫 틱)

    let clock = AFKClock(closedAt)
    let store = afkStore(host: "afk-resume-away", clock: clock)
    afkBeginWork(store, startedAt: start, lastInput: lastInput)
    await afkApplyAwaySync(store, json: afkAwaySyncJSON(startedAt: start, lastInputAt: lastInput, closeEligible: true))

    store.evaluateAwaySession(now: closedAt)
    #expect(!afkIsWorking(store))
    #expect(store.lastAutoClosedReason == .away)
    #expect(store.lastAutoClosedEndedAt == lastInput)

    // 마감 직후에도, 그 뒤 어느 시점에도 재개 대상이 아니다.
    #expect(!store.canResumeRecentlyClosedSession(now: closedAt))
    #expect(!store.canResumeRecentlyClosedSession(now: closedAt.addingTimeInterval(5 * 60)))

    // 산술 자체를 못 박는다: 임계(서버가 준 값) > 재개 창. 이 부등식이 위 두 단언의 **이유**다.
    let threshold = try #require(store.awayPolicy?.closeThresholdSeconds)
    #expect(
        threshold > WorkTimerStore.recentAutoCloseResumeWindowSeconds,
        "서버 임계가 재개 창 밑으로 내려왔다 — away 마감이 자동으로 되살아난다"
    )

    // **대조군**: 같은 세션·같은 시각인데 마감 사유만 sleep 이면(= 갭이 짧은 마감이면) 재개 대상이다.
    // 이 짝이 없으면 "재개가 통째로 죽어서" 위 단언이 초록인 경우를 못 가른다.
    let sleepClock = AFKClock(closedAt)
    let sleeper = afkStore(host: "afk-resume-away-control", clock: sleepClock)
    afkBeginWork(sleeper, startedAt: start, lastInput: closedAt.addingTimeInterval(-10 * 60))
    sleeper.handleSleep(at: closedAt.addingTimeInterval(-10 * 60))
    sleeper.handleWake(at: closedAt)
    #expect(sleeper.lastAutoClosedReason == .sleep)
    #expect(sleeper.canResumeRecentlyClosedSession(now: closedAt))
}

/// 흡수 세션(다른 맥이 연 세션)은 **재개 대상으로 등록조차 되지 않는다.** 남의 근무를 내 복귀로
/// 되살리면 그 사람의 세션이 내 소유로 넘어간다. 대조군으로 같은 조건의 내 세션은 등록된다.
@MainActor
@Test
func adoptedSessionIsNeverRegisteredAsAResumeTarget() async throws {
    let start = kst(2026, 8, 19, 9, 0)
    let lastInput = kst(2026, 8, 19, 13, 0)
    let lidClosed = kst(2026, 8, 19, 13, 0)
    let wake = kst(2026, 8, 19, 13, 20)

    let clock = AFKClock(lidClosed)
    let adopted = afkStore(host: "afk-resume-adopted", clock: clock)
    afkBeginWork(adopted, startedAt: start, lastInput: lastInput)
    adopted.adoptedRemoteSession = true
    adopted.handleSleep(at: lidClosed)
    clock.now = wake
    adopted.handleWake(at: wake)

    // 흡수 세션은 마감 자체를 하지 않는다(autoStop 의 첫 가드) — 그래서 재개 대상도 없다.
    #expect(afkIsWorking(adopted))
    #expect(adopted.lastAutoClosedSessionID == nil)
    #expect(adopted.lastAutoClosedEndedAt == nil)
    #expect(!adopted.canResumeRecentlyClosedSession(now: wake))

    // 대조군: 표식만 내리면 같은 조건에서 마감되고 재개 대상이 선다.
    let ownClock = AFKClock(lidClosed)
    let own = afkStore(host: "afk-resume-adopted-control", clock: ownClock)
    afkBeginWork(own, startedAt: start, lastInput: lastInput)
    own.handleSleep(at: lidClosed)
    ownClock.now = wake
    own.handleWake(at: wake)
    #expect(!afkIsWorking(own))
    #expect(own.canResumeRecentlyClosedSession(now: wake))
}

/// **복귀 감지 지점의 순서 계약.** 넛지 자동 시작은 새 세션을 만들기 **전에** 재개 대상을 본다.
/// 순서가 뒤바뀌면 세션이 두 개가 되거나 재개가 조용히 죽는다(이어붙이기 결함의 원인이 그 순서였다).
///
/// 비동기 왕복을 고정 sleep 으로 기다리지 않는다 — 전체 스위트가 메인 액터를 물면 그 대기가 무작위로
/// 터진다(실측). 대신 두 조각을 각각 **결정적으로** 본다:
///  (A) 컨트롤러 호출 **직후**(동기): 새 세션이 하나도 안 만들어졌다.
///      `Task { @MainActor … }` 는 지금 이 액터 실행이 끝나야 돌기 시작하므로 이 관측은 결정적이다.
///  (B) 같은 진입점이 돌려주는 Task 를 await: 그 왕복이 끝나면 **옛 세션 그대로** 살아난다.
@MainActor
@Test
func nudgeAutoStartResumesTheRecentSessionInsteadOfOpeningASecondOne() async throws {
    let now = kst(2026, 8, 19, 14, 0)
    let closedStart = kst(2026, 8, 19, 9, 0)
    let closedEnd = kst(2026, 8, 19, 13, 45)     // 15분 전에 끝났다 = 창 안
    let sessionID = WorkTimerStore.canonicalSessionID(afkSessionID)!

    @MainActor
    func armResumeTarget(_ store: WorkTimerStore, endedAt: Date) {
        store.lastAutoClosedSessionID = sessionID
        store.lastAutoClosedStartedAt = closedStart
        store.lastAutoClosedEndedAt = endedAt
        store.lastAutoClosedReason = .abandoned
        store.lastAutoClosedAt = now
    }

    // (A) 순서: 재개 대상이 있으면 넛지는 store.start() 로 가지 않는다.
    let orderClock = AFKClock(now)
    let ordered = afkStore(host: "afk-nudge-resume-order", clock: orderClock)
    armResumeTarget(ordered, endedAt: closedEnd)
    let controller = CheckOverlayController(
        store: ordered,
        notificationCenter: NotificationCenter(),
        defaults: afkDefaults(),
        workspaceNotifications: nil
    )
    defer {
        ordered.tickerTask?.cancel()
        ordered.refreshTask?.cancel()
        ordered.syncTask?.cancel()
    }
    controller.nudgeAutoStart()
    #expect(ordered.startedAt == nil, "재개 대상이 있는데 넛지가 새 세션을 먼저 만들었다 — 세션이 두 개가 된다")
    #expect(ordered.currentSessionID == nil)
    #expect(ordered.lastAutoClosedSessionID == sessionID, "재개 경로로 갔다면 대상은 왕복이 끝날 때까지 살아 있다")

    // (B) 결과: 같은 진입점의 왕복이 끝나면 **옛 세션 그대로** 살아난다(새 ID 가 아니다).
    let resumeClock = AFKClock(now)
    let store = afkStore(host: "afk-nudge-resume", clock: resumeClock)
    armResumeTarget(store, endedAt: closedEnd)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    let resume = try #require(store.resumeRecentlyClosedSession(), "재개 대상이 있는데 진입점이 nil 을 돌려줬다")
    await resume.value
    #expect(store.startedAt == closedStart)
    #expect(store.currentSessionID == sessionID)
    #expect(store.snapshot.isWorking)
    #expect(store.lastAutoClosedSessionID == nil)     // 성공하면 대상은 정리된다

    // (C) **대조군**: 창 밖(31분 전 종료)이면 같은 넛지가 그 자리에서 **새 세션**을 연다.
    let staleClock = AFKClock(now)
    let stale = afkStore(host: "afk-nudge-new-session", clock: staleClock)
    armResumeTarget(stale, endedAt: now.addingTimeInterval(-31 * 60))
    let staleController = CheckOverlayController(
        store: stale,
        notificationCenter: NotificationCenter(),
        defaults: afkDefaults(),
        workspaceNotifications: nil
    )
    defer {
        stale.tickerTask?.cancel()
        stale.refreshTask?.cancel()
        stale.syncTask?.cancel()
    }
    #expect(stale.resumeRecentlyClosedSession() == nil)
    armResumeTarget(stale, endedAt: now.addingTimeInterval(-31 * 60))
    staleController.nudgeAutoStart()
    #expect(stale.startedAt != nil)                       // 즉시(동기) 새 세션이 선다
    #expect(stale.currentSessionID != sessionID)          // 옛 세션이 아니다
    #expect(stale.lastAutoClosedSessionID == nil)         // 그리고 옛 대상은 끊긴다
}

/// **입력 신선도(20260820050000 이 "켜기 전에 함께 고칠 것"으로 못 박은 항목).**
/// 판정 직전에 관측을 전진시키지 않으면, 하트비트 주기(30초)만큼 낡은 관측으로 임계를 넘겨
/// **임계 직전에 돌아와 타이핑한 사람**이 끊긴다(마감은 소급이라 그 근무가 사라진다).
@MainActor
@Test
func staleLocalInputIsRefreshedRightBeforeTheAwayVerdict() async throws {
    let start = kst(2026, 8, 19, 9, 0)
    let now = kst(2026, 8, 19, 15, 0)
    // 마지막으로 **서버에 보고된** 입력은 임계를 1초 넘겼다 — 갱신이 없으면 이 틱에서 끊긴다.
    let reportedInput = now.addingTimeInterval(-9_001)

    // ① 사람은 5초 전에 돌아와 타이핑했다(다음 하트비트는 아직 안 나갔다) → 끊기면 안 된다.
    let backClock = AFKClock(now)
    let back = afkStore(host: "afk-fresh-input", clock: backClock)
    afkBeginWork(back, startedAt: start, lastInput: reportedInput)
    await afkApplyAwaySync(
        back,
        json: afkAwaySyncJSON(startedAt: start, lastInputAt: reportedInput, closeEligible: true)
    )
    back.meaningfulIdleSeconds = { 5 }
    back.evaluateAwaySession(now: now)
    #expect(afkIsWorking(back), "임계 직전에 돌아와 타이핑한 사람이 낡은 관측으로 끊겼다")
    #expect(back.lastMeaningfulInputAt == now.addingTimeInterval(-5))

    // ② **대조군** — 실제로 자리에 없으면(관측도 임계 밖) 같은 자리에서 그대로 끊긴다.
    //    이 짝이 없으면 "관측을 무조건 지금으로 밀어" 마감을 통째로 죽여도 초록이 된다.
    let goneClock = AFKClock(now)
    let gone = afkStore(host: "afk-stale-input", clock: goneClock)
    afkBeginWork(gone, startedAt: start, lastInput: reportedInput)
    await afkApplyAwaySync(
        gone,
        json: afkAwaySyncJSON(startedAt: start, lastInputAt: reportedInput, closeEligible: true)
    )
    gone.meaningfulIdleSeconds = { 9_100 }      // 2시간 31분째 무입력 = 관측도 임계 밖
    gone.evaluateAwaySession(now: now)
    #expect(!afkIsWorking(gone))
    #expect(gone.pendingItems.last?.endedAt == reportedInput)
    #expect(gone.pendingItems.last?.autoCloseReason == .away)

    // ③ 잠금 화면은 여전히 얼어 있다 — 신선도 갱신이 그 계약을 무르게 하지 않는다.
    let lockedClock = AFKClock(now)
    let locked = afkStore(host: "afk-fresh-input-locked", clock: lockedClock)
    afkBeginWork(locked, startedAt: start, lastInput: reportedInput)
    await afkApplyAwaySync(
        locked,
        json: afkAwaySyncJSON(startedAt: start, lastInputAt: reportedInput, closeEligible: true)
    )
    locked.meaningfulIdleSeconds = { 5 }
    locked.inputSessionUsable = { false }        // 잠긴 화면에서 남이 비밀번호를 두드린 것뿐이다
    locked.evaluateAwaySession(now: now)
    #expect(!afkIsWorking(locked))
    #expect(locked.lastMeaningfulInputAt == reportedInput)
}

// MARK: - S10. 이어붙이기 제거 회귀 그물 (v0.2.46)

/// 서버는 `away_sync()` 에서 `restorable` 을 **계속 실어 보낸다**(RPC 도 그대로 휴면 중이다 —
/// docs/away-close.md 5절). 클라가 그 조각을 다시 읽기 시작하면 21일치 실측이 확인한 두 결함이
/// 그대로 돌아온다: 승인 직후 재마감 churn 21%, 그리고 수면 갭의 근무 재계상.
///
/// 그래서 **문서 2절 모양 그대로(restorable 포함)** 의 응답을 실제 디코드 경로
/// (`awaySync(from:)` → `applyAwaySync`)로 통과시키고, 그 뒤 스토어에 복원 상태가 한 칸도 서지
/// 않는지를 본다. 정책·열린 세션이 함께 반영되는지도 같이 보는 이유는 대조군이다 —
/// 응답을 통째로 버려도 초록이 되는 테스트는 아무것도 지키지 못한다.
@MainActor
@Test
func serverResumeHintLeavesNoTraceInTheStore() async throws {
    let start = kst(2026, 8, 19, 20, 0)
    let lastInput = kst(2026, 8, 19, 22, 50)
    let lidClosed = kst(2026, 8, 19, 23, 0)
    let wake = kst(2026, 8, 20, 2, 0)          // 3시간 뒤 복귀 = 서버 창(6시간)이 활짝 열려 있는 시점

    let clock = AFKClock(lidClosed)
    let store = afkStore(host: "afk-restorable-ignored", clock: clock)
    afkBeginWork(store, startedAt: start, lastInput: lastInput)
    store.handleSleep(at: lidClosed)
    clock.now = wake
    store.handleWake(at: wake)
    #expect(!afkIsWorking(store))

    await afkApplyAwaySync(
        store,
        json: afkAwaySyncJSON(
            startedAt: nil,
            lastInputAt: nil,
            closeEligible: false,
            restorable: (sessionID: afkSessionID, startedAt: start, endedAt: lastInput, reason: "sleep", now: wake)
        )
    )

    // 대조군: 같은 응답의 정책 조각은 확실히 반영됐다(= 응답을 버려서 초록이 된 것이 아니다).
    #expect(store.awayServerSupported)
    #expect(store.awayPolicy?.closeThresholdSeconds == 9_000)

    // 본론: 마감은 그대로 서 있고, 스토어 어디에도 복원 상태가 없다.
    #expect(!afkIsWorking(store))
    #expect(store.snapshot.status == .offWork)
    let labels = Mirror(reflecting: store).children.compactMap(\.label).map { $0.lowercased() }
    // 픽스처 보정: 거울이 저장 프로퍼티를 실제로 보고 있는가(0개면 아래 단언이 공짜로 초록이 된다).
    #expect(labels.contains { $0.contains("awaypolicy") }, "거울이 스토어의 저장 프로퍼티를 못 본다 — 아래 단언이 무의미해진다")
    let restoreProperties = labels.filter { $0.contains("restorable") || $0.contains("restoringaway") }
    #expect(restoreProperties.isEmpty, "스토어에 복원 상태가 되살아났다: \(restoreProperties)")
}
// 같은 응답으로 **팝오버가** 배너를 그리지 않는지는 픽셀로 봐야 한다 —
// CheckMenuRenderTests 의 popoverDrawsNoBannerWhenTheServerStillOffersToResume 가 그쪽 반쪽이다.

/// 소스 계약(하우스 규칙 — `awayThresholdsAreNeverHardcodedInClientSource` 와 같은 방식).
/// 클라 소스 어디에도 이어붙이기 심볼이 없어야 한다. **주석을 걷어낸 뒤** 검사한다 —
/// 안 그러면 "왜 제거했는가"를 적은 설명 주석을 지워야만 초록이 되는 테스트가 된다.
///
/// ★ 아래 조각은 **첫 글자를 뗀 어간**이다(예: `…wayRestor` 는 a/A 를 뗀 형태라 대소문자 두 철자를
///   한 번에 덮는다). 심볼을 통짜로 적어 두면 "저장소에 이 심볼이 하나도 없다"를 확인하는 검수
///   grep 이 이 테스트 자신을 잡아 영원히 비지 않는다 — 그 grep 은 릴리스 절차의 일부다.
@Test
func sessionResumeSymbolsAreGoneFromClientSource() throws {
    let sources = try afkClientSources()
    #expect(!sources.isEmpty)

    let forbiddenStems = [
        "wayRestor",                // 배너 문구·넛지 문구·스토어 상태·모델 타입 일가
        "estorable",                // 복원 대상 세션 타입과 그 파생 판단들
        "estoreAwaySession",        // 복원 액션(그리고 그 async 짝)
        "estoredAwaySession",       // 복원 성공을 로컬에 미러링하던 함수
        "estoreAutoClosedSession",  // 서버 RPC 호출부
        "estoringAwaySession",      // 복원 왕복 중 연타 가드
        "wayStateOwnerUserID"       // 복원 배너의 계정 잠금
    ]
    for (name, code) in sources {
        let stripped = afkStrippingSwiftComments(code)
        for stem in forbiddenStems {
            #expect(!stripped.contains(stem), "\(name) 에 이어붙이기 심볼이 되살아났다: …\(stem)")
        }
    }
}

// MARK: - S11. 소스 계약 — 임계값은 클라 소스에 없다

/// 사장님 확정 사항: **임계는 서버 함수가 소유한다.** 이 숫자는 실측 없이 정한 값이라 계측 후 SQL
/// 한 줄로 바뀌는데, 클라에 박혀 있으면 브루 지연으로 절반이 옛 값을 쓴다.
/// 주석은 걷어낸 뒤 검사한다 — 안 그러면 "왜 서버가 소유하는가"를 적은 설명을 지워야만 초록이 된다.
@Test
func awayThresholdsAreNeverHardcodedInClientSource() throws {
    let sources = try afkClientSources()
    #expect(!sources.isEmpty)

    // 서버 소유 상수 4종의 값(9000 / 21600 / 10800)과 흔한 산술 표기. 1800(freeze)은 제외한다 —
    // longSessionResponseWindowSeconds 가 같은 값을 정당하게 쓰고 있어 검사하면 거짓 양성이 된다.
    let forbidden = [
        "(?<![0-9_.])9_?000(?![0-9_])",
        "(?<![0-9_.])21_?600(?![0-9_])",
        "(?<![0-9_.])10_?800(?![0-9_])",
        "2\\.5\\s*\\*\\s*3_?600",
        "150\\s*\\*\\s*60"
    ]
    for (name, code) in sources {
        let stripped = afkStrippingSwiftComments(code)
        for pattern in forbidden {
            let regex = try NSRegularExpression(pattern: pattern)
            let hits = regex.numberOfMatches(
                in: stripped,
                range: NSRange(stripped.startIndex..., in: stripped)
            )
            #expect(hits == 0, "\(name) 에 자리 비움 정책 상수가 리터럴로 박혀 있다(\(pattern))")
        }
        // 상수를 클라가 **선언**하는 것도 같은 결함이다(값이 무엇이든 출처가 둘이 된다).
        let declaration = try NSRegularExpression(
            pattern: "(let|var)\\s+away[A-Za-z]*(Threshold|Window|Backstop)[A-Za-z]*Seconds\\s*[:=]"
        )
        let declarationHits = declaration.numberOfMatches(
            in: stripped,
            range: NSRange(stripped.startIndex..., in: stripped)
        )
        #expect(declarationHits == 0, "\(name) 이 자리 비움 임계를 클라 상수로 선언한다")
    }

    // 그리고 판정이 실제로 **서버가 준 값**을 읽는지 확인한다(위 두 검사는 '아무 임계도 안 쓴다'로도 통과한다).
    let store = try #require(sources["WorkTimerStore.swift"])
    let strippedStore = afkStrippingSwiftComments(store)
    #expect(strippedStore.contains("policy.closeThresholdSeconds"))
}

// MARK: - 소스 읽기 도구

private func afkRepoFile(_ relativePath: String) -> URL {
    URL(fileURLWithPath: #filePath)      // Tests/checkTests/AwayCloseTests.swift
        .deletingLastPathComponent()      // Tests/checkTests
        .deletingLastPathComponent()      // Tests
        .deletingLastPathComponent()      // (repo root)
        .appendingPathComponent(relativePath)
}

private func afkClientSources() throws -> [String: String] {
    let directory = afkRepoFile("Sources/check")
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    var sources: [String: String] = [:]
    for name in names where name.hasSuffix(".swift") {
        sources[name] = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
    return sources
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다(하우스 규칙). 문자열 리터럴 안의 `//` 는 남긴다 —
/// URL 문자열이 주석으로 오인되면 그 뒤 코드가 통째로 검사에서 사라진다.
private func afkStrippingSwiftComments(_ source: String) -> String {
    var result = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var previous: Character = " "
    let characters = Array(source)
    var index = 0
    while index < characters.count {
        let character = characters[index]
        let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
        if inLineComment {
            if character == "\n" {
                inLineComment = false
                result.append(character)
            }
        } else if inBlockComment {
            if character == "*", next == "/" {
                inBlockComment = false
                index += 1
            }
        } else if inString {
            if character == "\"", previous != "\\" { inString = false }
            result.append(character)
        } else if character == "/", next == "/" {
            inLineComment = true
            index += 1
        } else if character == "/", next == "*" {
            inBlockComment = true
            index += 1
        } else if character == "\"" {
            inString = true
            result.append(character)
        } else {
            result.append(character)
        }
        previous = character
        index += 1
    }
    return result
}
