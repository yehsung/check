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
//  3. **임계·복원 창은 서버가 준 값으로만 판정한다.** 이 파일이 9000 을 쓰는 것은 서버 응답 픽스처
//     안에서뿐이고(docs/away-close.md 2절의 그 숫자), 클라 소스에 그 숫자가 없다는 것은 맨 아래
//     소스 계약 테스트가 지킨다.

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
    store.meaningfulIdleSeconds = { 0 }
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
    store.applyAwaySync(sync, ownerUserID: afkUserID)
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

// MARK: - S2. 점심 + 회의 3시간 — 끊기고, 복원하면 공백 전체가 근무로 돌아온다

/// 임계를 2시간 30분으로 낮춘 결과 **의도적으로** 끊기는 사례다(사장님 확정). 그래서 이 시나리오의
/// 급소는 "끊긴다"가 아니라 **"복원 버튼 한 번에 공백 전체가 돌아오는가"** 다. 돌아오지 않으면
/// 이 릴리스는 매일 3시간을 빼앗는 기능이 된다.
@MainActor
@Test
func lunchAndMeetingThreeHoursClosesAndRestoreReturnsTheWholeGap() async throws {
    let start = kst(2026, 8, 19, 9, 0)
    let lastInput = kst(2026, 8, 19, 12, 0)
    let closedAt = kst(2026, 8, 19, 14, 31)     // 마지막 입력 + 2시간 31분(임계 초과 첫 틱)
    let backAt = kst(2026, 8, 19, 15, 5)        // 회의 끝나고 복귀

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

    // 복귀. 서버가 복원 대상을 들고 온다(창은 서버가 계산한다).
    clock.now = backAt
    await afkApplyAwaySync(
        store,
        json: afkAwaySyncJSON(
            startedAt: nil,
            lastInputAt: nil,
            closeEligible: false,
            restorable: (sessionID: afkSessionID, startedAt: start, endedAt: lastInput, reason: "away", now: backAt)
        )
    )
    #expect(store.offerAwayRestoreOnAutoStart(now: backAt))
    let restorable = try #require(store.restorableAwaySession)
    #expect(restorable.reason == .away)

    // 복원 성공(서버가 S1 을 재개하고 S2 를 지운 뒤 응답한 것을 로컬에 미러링).
    store.applyRestoredAwaySession(sessionID: afkSessionID, startedAt: start, closedEndedAt: lastInput)

    #expect(store.startedAt == start)
    store.displayNow = backAt
    // ★ 공백(12:00~15:05)까지 **전부** 근무로 돌아온다. 마감이 더해 둔 오늘 몫을 되빼지 않으면
    //   같은 구간을 두 번 세어 9시간이 되고, 안 되빼는 대신 시작 시각을 복귀 시각으로 세우면 3시간을 잃는다.
    #expect(store.todayDuration == Int(backAt.timeIntervalSince(start)))
    #expect(store.awayRestorable == nil)
    #expect(!store.awayRestorePromptPending)
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

// MARK: - S4. 8시간 취침 — 끊기고, 복원 창은 이미 닫혀 있다

/// 복원 창(6시간)이 통상 수면(7~8시간)보다 **짧아야** 하는 이유가 이 시나리오다. 아침에 일어난 사람이
/// 밤을 복원 버튼 한 번으로 근무로 만들 수 있으면 이 기능 전체가 무의미해진다.
/// 동시에 **3시간 낮잠은 창이 살아 있어야** 한다(같은 문이라 닫으면 워크숍 다녀온 사람도 함께 죽는다).
@MainActor
@Test
func eightHourSleepClosesAndItsRestoreWindowIsAlreadyClosed() async throws {
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

    // 아침. 서버가 같은 세션을 복원 대상으로 실어 보내도 **창이 닫혀 있다**(잔여 0).
    await afkApplyAwaySync(
        store,
        json: afkAwaySyncJSON(
            startedAt: nil,
            lastInputAt: nil,
            closeEligible: false,
            restorable: (sessionID: afkSessionID, startedAt: start, endedAt: lastInput, reason: "sleep", now: wake)
        )
    )
    let expired = try #require(store.restorableAwaySession)
    #expect(expired.remainingSeconds == 0)
    #expect(!store.offerAwayRestoreOnAutoStart(now: wake))
    #expect(!store.awayRestorePromptPending)

    // 대조군: 같은 마감이라도 3시간 뒤 복귀면 창이 살아 있다(워크숍 다녀온 사람을 살리는 그 문).
    let napWake = kst(2026, 8, 20, 2, 0)
    let napClock = AFKClock(napWake)
    let nap = afkStore(host: "afk-overnight-control", clock: napClock)
    await afkApplyAwaySync(
        nap,
        json: afkAwaySyncJSON(
            startedAt: nil,
            lastInputAt: nil,
            closeEligible: false,
            restorable: (sessionID: afkSessionID, startedAt: start, endedAt: lastInput, reason: "sleep", now: napWake)
        )
    )
    #expect((nap.restorableAwaySession?.remainingSeconds ?? 0) > 0)
    #expect(nap.offerAwayRestoreOnAutoStart(now: napWake))
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

/// 복원 창의 만료 판정은 **서버가 준 두 값 중 하나라도 닫혔다고 하면 닫힌 것**이다.
/// 두 값은 같은 트랜잭션에서 나오지만 클라가 한쪽만 보면, 그 한쪽이 비거나(구버전 응답·키 누락)
/// 어긋나는 순간 이미 죽은 창이 되살아나 사용자가 [이어 붙이기]를 눌렀다가 not_restorable 을 받는다.
@MainActor
@Test
func restoreOfferHonoursEitherExpirySignal() {
    let now = kst(2026, 8, 20, 7, 0)
    let clock = AFKClock(now)

    func offer(host: String, expiresAt: Date?, remainingSeconds: Int) -> Bool {
        let store = afkStore(host: host, clock: clock)
        store.awayStateOwnerUserID = afkUserID
        store.awayRestorable = AwayRestorableSession(
            sessionID: afkSessionID,
            startedAt: now.addingTimeInterval(-11 * 3_600),
            endedAt: now.addingTimeInterval(-8 * 3_600),
            autoClosedAt: now.addingTimeInterval(-8 * 3_600),
            reason: .sleep,
            expiresAt: expiresAt,
            remainingSeconds: remainingSeconds
        )
        return store.offerAwayRestoreOnAutoStart(now: now)
    }

    // 창 시각은 지났는데 잔여 초만 남아 있는 응답 — 묻지 않는다.
    #expect(!offer(host: "afk-expiry-a", expiresAt: now.addingTimeInterval(-3_600), remainingSeconds: 3_600))
    // 창 시각은 미래인데 잔여가 0인 응답 — 역시 묻지 않는다.
    #expect(!offer(host: "afk-expiry-b", expiresAt: now.addingTimeInterval(3_600), remainingSeconds: 0))
    // 둘 다 열려 있을 때만 묻는다(대조군).
    #expect(offer(host: "afk-expiry-c", expiresAt: now.addingTimeInterval(3_600), remainingSeconds: 3_600))
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

// MARK: - S8. 복원 직후 10분 스캐빈저가 다시 닫지 않는다

/// attack-4 의 결함 ⑥. 복원 트랜잭션이 last_seen_at 을 밀지 않으면 되살린 세션이 몇 초 뒤 다시 닫힌다.
/// 클라 쪽 반쪽은 둘이다: ① 복원 직후 로컬 판정이 옛 입력 시각으로 그 세션을 다시 마감하지 않는다,
/// ② 복원 즉시 하트비트가 다시 나가 서버의 신호 공백이 이어지지 않는다.
@MainActor
@Test
func restoredSessionSurvivesTheNextTenMinutes() async throws {
    let host = "afk-restore-survives"
    let start = kst(2026, 8, 19, 9, 0)
    let staleInput = kst(2026, 8, 19, 10, 0)
    let restoredAt = kst(2026, 8, 19, 15, 0)
    let clock = AFKClock(restoredAt)
    let store = afkStore(host: host, clock: clock)
    store.awayStateOwnerUserID = afkUserID

    store.applyRestoredAwaySession(sessionID: afkSessionID, startedAt: start, closedEndedAt: staleInput)
    #expect(store.startedAt == start)
    // 버튼을 누른 것 자체가 "사람이 자리에 있다"는 증거다 — 옛 입력 시각이 남으면 다음 틱이 즉시 다시 마감한다.
    #expect(store.lastMeaningfulInputAt == restoredAt)

    // ① 10분 뒤 틱: 서버가 아직 옛 last_input(10:00)을 들고 있어도 max 규칙이 방금 누른 시각을 채택한다.
    let tenMinutesLater = restoredAt.addingTimeInterval(600)
    clock.now = tenMinutesLater
    store.inputSessionUsable = { false }   // 복원 직후 사람이 잠깐 손을 뗐다 — 그래도 방금 눌렀다.
    await afkApplyAwaySync(
        store,
        json: afkAwaySyncJSON(startedAt: start, lastInputAt: staleInput, closeEligible: true)
    )
    store.evaluateAwaySession(now: tenMinutesLater)
    #expect(afkIsWorking(store), "복원 직후 10분 안에 다시 닫히면 사용자는 버튼이 고장 났다고 본다")

    // ② 하트비트가 다시 나간다(= 서버의 신호 공백이 끊긴다 → 10분 스캐빈저 조건이 성립하지 않는다).
    await store.sendHeartbeatIfWorking()
    let statusPosts = zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
        .filter { $0.0.url?.path == "/rest/v1/work_statuses" }
        .map(\.1)
    #expect(statusPosts.contains { $0.contains("last_seen_at") && $0.contains("\"status\":\"working\"") })
}

/// 서버 쪽 반쪽(복원 트랜잭션이 last_seen_at·last_input_at 을 now 로 민다)은 클라가 검사할 수 없다 —
/// 마이그레이션은 이 저장소에 없다(supabase/ 는 .gitignore). 그래서 **계약 문서**를 고정한다:
/// 이 문장이 문서에서 사라지면 다음 사람이 복원 RPC 를 재작성할 때 그 한 줄을 잃고,
/// 되살린 세션이 10분 뒤 다시 닫힌다(공격이 실제로 잡아낸 결함이다).
@Test
func restoreContractDocumentsTheHeartbeatRefresh() throws {
    let doc = try String(contentsOf: afkRepoFile("docs/away-close.md"), encoding: .utf8)
    let section = try #require(doc.range(of: "restore_auto_closed_session"))
    let tail = String(doc[section.lowerBound...])
    #expect(tail.contains("last_seen_at=now()") || tail.contains("`last_seen_at=now()`"))
    #expect(tail.contains("10분 스캐빈저"))
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

// MARK: - S10. 복원 후 12시간 앵커는 세션 시작 시각이다

/// 복원 시각으로 앵커를 세우면 09:00 시작 → 14:30 마감 → 15:00 복원인 사람의 12시간 확인이
/// 다음 날 03:00 으로 밀려 총 18시간 세션이 된다 = 12시간 안전장치가 복원 경로에서 무력화된다.
@MainActor
@Test
func restoreAnchorsTheTwelveHourCheckToTheOriginalStart() throws {
    let start = kst(2026, 8, 19, 9, 0)
    let closedEndedAt = kst(2026, 8, 19, 12, 0)
    let restoredAt = kst(2026, 8, 19, 15, 0)
    let clock = AFKClock(restoredAt)
    let store = afkStore(host: "afk-anchor", clock: clock)

    store.applyRestoredAwaySession(sessionID: afkSessionID, startedAt: start, closedEndedAt: closedEndedAt)
    #expect(store.longSessionAnchor == start)

    // 시작 + 11시간 59분: 아직 묻지 않는다.
    store.evaluateLongSession(now: start.addingTimeInterval(12 * 3_600 - 60))
    #expect(!store.isLongSessionPromptActive)

    // 시작 + 12시간 1분(= 21:01 KST): 여기서 물어야 한다. 앵커가 복원 시각이면 이 시점엔 조용하고,
    // 확인은 다음 날 03:00 으로 밀린다.
    store.evaluateLongSession(now: start.addingTimeInterval(12 * 3_600 + 60))
    #expect(store.isLongSessionPromptActive)
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
