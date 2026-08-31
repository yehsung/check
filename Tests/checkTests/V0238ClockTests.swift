import Foundation
import SwiftUI
import Testing
@testable import check

// v0.2.38 "가벼워지기" 트랙 ε — 시계 분리(M1)와 깨움 결합(M7) 계약 고정.
//
// 계측으로 확정된 사실: 1초 티커가 `displayNow` 를 매초 대입해, 팝오버가 닫혀 있어도 상주하는 CheckMenuView 트리를
// 매초 재평가·재레이아웃시켰다(유휴 main 1.06%). 깨움 직후에는 모든 루프의 Task.sleep 이 동시에 만료돼 Wi-Fi 결합 전
// 요청이 폭주하고 소켓이 즉시 재연결을 시도했다. 여기서는 그 두 결함의 수리를 주입 시계·주입 경로 상태로 못 박는다.
//
//  (a) 팝오버 닫힘 60틱 → displayNow 대입 0회, 열림 → 매초. 재오픈 순간 setMenuPresented(true) 가 정확히 1회 되맞춘다.
//  (b) 오버레이 시계(overlayNow)는 패널이 보일 때(오버레이 켜짐 && 근무 중)만 매초, 숨김·비근무에선 0회.
//  (c) 메뉴바 라벨은 닫힘 상태에서도 매초 갱신되고 snapshot 재대입은 0회.
//  (d) 마일스톤 발화 시각은 displayNow 와 무관하게 clock() 기준.
//  (e) 오버레이 꺼짐 + 팝오버 닫힘 1시간 → 티커 60초(분 경계 정렬), 근무 시간 계산 오차 0. 표시가 생기면 즉시 1초.
//  (f) 깨움: 경로 미충족 동안 요청 0건, 충족 순간 폴링 본문 1회 → 조인 1회 순서. 상한 초과 시 강제 진행.
//      잠자기 정정은 게이트에 늦춰질 뿐 잃지 않는다.
//
// 테스트 plist 는 **고정 이름**이다(UUID 접미어 없음) — 시작할 때 영속 도메인을 지워 이전 실행의 장부가 새지 않게 한다.
// 병렬 실행을 위해 테스트마다 서로 다른 고정 이름을 쓴다.

private let stubUserID = "00000000-0000-0000-0000-000000000002"
/// 팀 픽스처의 근무중 행(0002)이 '내 행'이 되지 않게 하는 별도 계정 — 깨움 테스트는 요청 **순서와 수**를 세는데,
/// 팀 상태 반영이 내 세션을 흡수해 링을 내리면(reconcile → .workEnded) 조인 자체가 사라져 계측이 흔들린다.
private let teammateUserID = "00000000-0000-0000-0000-000000000003"

/// 고정 픽스처 시각: 어느 날의 KST 정오. 자정 클리핑에서 멀리 떨어져 있어 하루 중 언제 돌려도 같은 결과다.
private let t0 = TeamWeeklyGoal.koreanDayStart(for: Date(timeIntervalSince1970: 1_800_000_000))
    .addingTimeInterval(12 * 3600)

private func fixedDefaults(_ suiteName: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// 스캔이 절대 일어나지 않는 토큰 스토어(빈 임시 홈) — setMenuPresented(true) 가 실홈 스캔을 켜지 않게 한다.
@MainActor
private func inertTokenStore(suiteName: String) -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    return TokenUsageStore(
        defaults: fixedDefaults(suiteName + ".token"),
        homeDirectory: tmp.appendingPathComponent("check-v0238-clock-home-\(suiteName)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-v0238-clock-cache-\(suiteName).json", isDirectory: false)
    )
}

/// 주입 시계. 클로저가 값 캡처가 아니라 이 상자를 읽으므로 테스트 도중 자유롭게 전진시킨다.
private final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

/// 스텁 네트워크에 물린 로그인·소속 확정 상태의 스토어(로그인 흐름은 건너뛴다 — 기존 스위트 규약).
@MainActor
private func makeStore(
    host: String,
    suiteName: String,
    clock: TestClock,
    userID: String = stubUserID,
    transport: RealtimeTransport? = nil
) -> WorkTimerStore {
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
        tokenUsage: inertTokenStore(suiteName: suiteName),
        realtimeTransport: transport
    )
    store.clock = { clock.now }
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
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

/// 근무 중 픽스처(시작 시각 지정). start() 를 타지 않는 이유는 큐/링 부수효과 없이 티커 계약만 보기 위해서다.
@MainActor
private func beginWork(_ store: WorkTimerStore, startedAt: Date) {
    store.startedAt = startedAt
    store.currentSessionID = WorkTimerStore.canonicalSessionID("aaaaaaaa-0000-0000-0000-0000000000e1")
    store.accumulatedSeconds = 0
    store.accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: startedAt)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
}

/// withObservationTracking 의 @Sendable onChange 가 발화 여부를 기록하는 참조 상자.
/// 관찰 알림은 MainActor 의 willSet 에서 동기 발화하므로 실제 경합은 없다.
private final class FireFlag: @unchecked Sendable {
    var fired = false
}

/// `read` 가 읽는 관찰 대상에 **대입이 일어난** 틱의 수를 센다(같은 값 대입도 센다 — @Observable 규약 그대로).
/// 틱마다 추적을 새로 걸어 "60틱 중 몇 틱이 그 프로퍼티를 건드렸나"를 정확히 셈한다.
@MainActor
private func assignmentTicks(
    of read: @escaping @MainActor () -> Void,
    ticks: Int,
    each: @MainActor () -> Void
) -> Int {
    var touched = 0
    for _ in 0..<ticks {
        let flag = FireFlag()
        withObservationTracking { read() } onChange: { flag.fired = true }
        each()
        if flag.fired { touched += 1 }
    }
    return touched
}

// MARK: - 깨움 테스트 도구

/// 스크립트 네트워크 경로. 테스트가 `satisfy()` 를 부르기 전까지 미충족이고, 취소되면 즉시 돌아온다(상한이 이겼을 때).
private final class ScriptedNetworkPath: NetworkPathObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var satisfied: Bool
    private var waitCount = 0

    init(satisfied: Bool) { self.satisfied = satisfied }

    var isSatisfied: Bool {
        lock.lock()
        defer { lock.unlock() }
        return satisfied
    }

    /// waitUntilSatisfied 가 불린 횟수 — 게이트가 관측자를 실제로 물었는지의 증거.
    var waits: Int {
        lock.lock()
        defer { lock.unlock() }
        return waitCount
    }

    func satisfy() {
        lock.lock()
        satisfied = true
        lock.unlock()
    }

    private func noteWait() {
        lock.lock()
        waitCount += 1
        lock.unlock()
    }

    func waitUntilSatisfied() async {
        noteWait()
        while !isSatisfied {
            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// 조인 시점에 **그때까지의 요청 수**를 함께 적는 전송자 — "본문이 조인보다 먼저"를 순서로 증명하기 위해서다
/// (요청 목록과 명령 목록은 따로 쌓여 사후에 순서를 되짚을 수 없다).
@MainActor
private final class WakeProbeTransport: RealtimeTransport {
    var onEvent: ((RealtimeTransportEvent) -> Void)?
    private(set) var commands: [String] = []
    private(set) var requestCountsAtConnect: [Int] = []
    let host: String

    init(host: String) { self.host = host }

    var connectCount: Int { commands.filter { $0 == "connect" }.count }

    func connect(url: URL, apiKey: String, accessToken: String, channel: String, isPrivate: Bool) {
        commands.append("connect")
        requestCountsAtConnect.append(URLProtocolStub.requests(forHost: host).count)
    }
    func pushAccessToken(_ token: String) { commands.append("push") }
    func sendHeartbeat() {
        commands.append("heartbeat")
        onEvent?(.heartbeatAck)
    }
    func disconnect() { commands.append("disconnect") }
    func emit(_ event: RealtimeTransportEvent) { onEvent?(event) }
}

private func requestCount(host: String, path: String? = nil, method: String? = nil) -> Int {
    URLProtocolStub.requests(forHost: host).filter {
        (path == nil || $0.url?.path == path) && (method == nil || $0.httpMethod == method)
    }.count
}

private let workStatusesPath = "/rest/v1/work_statuses"
private let workSessionsPath = "/rest/v1/work_sessions"

/// 조건이 참이 될 때까지 기다린다. **메인 액터에서, 벽시계가 아니라 재개 횟수로** 상한을 둔다 — 전체 스위트가 병렬로
/// 돌 때 다른 테스트가 메인 스레드를 수십 초씩 잡는데, 관찰 대상이 전부 메인 액터라 굶주린 만큼 함께 늦춰져야 한다.
@MainActor
private func waitUntil(maxResumes: Int = 3_000, _ condition: () -> Bool) async {
    for _ in 0..<maxResumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

/// 잠깐 실제로 기다린다 — **부정형 단언**("그동안 요청이 0건이다") 전용. 만료된 루프 잠(슬라이스 0.02초)이 열 번 넘게
/// 지나갈 시간이라, 게이트가 루프를 내리지 않았다면 이 안에 본문이 반드시 여러 번 돈다.
@MainActor
private func holdBriefly() async {
    try? await Task.sleep(for: .milliseconds(300))
}

/// 깨움 픽스처: 근무 중 + 링 구독 → 뚜껑 닫음(suspended). 구독 직후의 따라잡기(take_pokes 1회)는 여기서 끝까지
/// 기다린다 — 깨움과 무관한 in-flight 요청이 "결합 전 요청 0건" 단언에 섞이지 않게. refresh 루프는 0.02초 슬라이스로
/// 세우고 handleSleep 뒤에 슬라이스보다 짧게 한 번 양보하므로, 첫 본문이 도는 것은 handleWake 가 루프를 내린 뒤가 아니라
/// **아예 돌지 않은** 상태다(본문 요청 0건을 baseline 이 확인한다).
@MainActor
private func makeSuspendedWakeStore(
    host: String,
    suiteName: String,
    clock: TestClock,
    startedAt: Date
) async -> (WorkTimerStore, WakeProbeTransport) {
    let transport = WakeProbeTransport(host: host)
    let store = makeStore(host: host, suiteName: suiteName, clock: clock, userID: teammateUserID, transport: transport)
    beginWork(store, startedAt: startedAt)
    store.refreshLoopSliceSeconds = 30
    store.startStatusRefreshLoop()
    transport.emit(.joined)
    #expect(store.realtimeState.isSubscribed)
    #expect(transport.connectCount == 1)
    await waitUntil { store.realtime.catchUpTask == nil && requestCount(host: host, path: "/rest/v1/rpc/take_pokes") >= 1 }
    store.handleSleep(at: clock.now)
    #expect(store.realtimeState == .idle(.suspended))
    #expect(requestCount(host: host, path: workStatusesPath) == 0, "픽스처 단계에서 폴링 본문이 돌았다.")
    // 이제부터 만료된 잠이 곧바로 본문으로 이어지는 모양을 만든다: 30초 루프를 0.02초 루프로 갈아 세운다.
    store.refreshTask?.cancel()
    store.refreshTask = nil
    store.refreshLoopSliceSeconds = 0.02
    store.startRefreshLoopTask(runBodyFirst: false)
    return (store, transport)
}

// MARK: - 오버레이 라벨 도구

/// 뷰 값 트리(ModifiedContent 사슬)에서 캐릭터 뷰를 찾아 라벨 초를 꺼낸다. 렌더 없이 body 를 평가한 결과만 뒤진다.
private func overlayLabelSeconds(in value: Any, depth: Int = 0) -> Int? {
    if let view = value as? CheckOverlayCharacterView { return view.elapsedSeconds }
    guard depth < 8 else { return nil }
    for child in Mirror(reflecting: value).children {
        if let found = overlayLabelSeconds(in: child.value, depth: depth + 1) { return found }
    }
    return nil
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

// MARK: - 테스트

@MainActor
@Suite struct V0238ClockTests {
    // MARK: (a) 팝오버 시계는 열려 있을 때만 흐른다

    @Test func closedPopoverTicksNeverAssignDisplayNowAndOpenOnesAssignEverySecond() {
        let clock = TestClock(t0)
        let store = makeStore(host: "v0238-clock-a", suiteName: "check-v0238-clock-a", clock: clock)
        defer { cancelTasks(store) }
        beginWork(store, startedAt: t0.addingTimeInterval(-600))
        store.displayNow = t0.addingTimeInterval(-600)
        let frozen = store.displayNow
        #expect(!store.isMenuPresented)

        // 닫힘: 60틱 동안 팝오버 시계를 **한 번도 건드리지 않는다**(같은 값 대입조차 없다 — 그것도 무효화다).
        let closedTouches = assignmentTicks(of: { _ = store.displayNow }, ticks: 60) {
            clock.now = clock.now.addingTimeInterval(1)
            store.tick()
        }
        #expect(closedTouches == 0, "닫힌 팝오버의 시계가 \(closedTouches)틱에서 대입됐다 — 상주 뷰 트리가 매초 돈다.")
        #expect(store.displayNow == frozen)
        // 그 사이 정책 시계는 계속 흘렀다(clock 기준).
        #expect(store.todayDuration(at: clock.now) == 660)

        // 열림: 매 틱 대입되고 값은 주입 시계와 같다.
        store.isMenuPresented = true
        let openTouches = assignmentTicks(of: { _ = store.displayNow }, ticks: 60) {
            clock.now = clock.now.addingTimeInterval(1)
            store.tick()
        }
        #expect(openTouches == 60)
        #expect(store.displayNow == clock.now)
    }

    @Test func reopeningThePopoverRefreshesDisplayNowExactlyOnce() {
        // α 트랙(CheckMenuView.menuClockNow)의 재오픈 복구는 이 1회 갱신에 맞물린다 — 닫힌 동안 얼어 있던 시계가
        // 여는 순간 지금으로 되맞춰져야 첫 프레임이 낡은 초를 그리지 않는다.
        let clock = TestClock(t0)
        let store = makeStore(host: "v0238-clock-a2", suiteName: "check-v0238-clock-a2", clock: clock)
        defer { cancelTasks(store) }
        beginWork(store, startedAt: t0.addingTimeInterval(-600))
        store.displayNow = t0.addingTimeInterval(-600)
        for _ in 0..<30 {
            clock.now = clock.now.addingTimeInterval(1)
            store.tick()
        }
        #expect(store.displayNow == t0.addingTimeInterval(-600))

        let reopen = assignmentTicks(of: { _ = store.displayNow }, ticks: 1) {
            store.setMenuPresented(true)
        }
        #expect(reopen == 1)
        #expect(store.displayNow == clock.now)

        // 중복 신호는 무해하다(!= 가드) — 렌더 테스트들이 이 no-op 에 기대어 고정 시계를 보존한다.
        let duplicate = assignmentTicks(of: { _ = store.displayNow }, ticks: 1) {
            store.setMenuPresented(true)
        }
        #expect(duplicate == 0)
    }

    // MARK: (b) 오버레이 시계는 패널이 보일 때만 흐른다

    @Test func overlayNowTicksOnlyWhileTheOverlayClockShows() {
        let clock = TestClock(t0)
        let store = makeStore(host: "v0238-clock-b", suiteName: "check-v0238-clock-b", clock: clock)
        defer { cancelTasks(store) }
        beginWork(store, startedAt: t0.addingTimeInterval(-600))
        store.setOverlayEnabled(true)
        #expect(store.overlayClockIsShowing)

        let showing = assignmentTicks(of: { _ = store.overlayNow }, ticks: 60) {
            clock.now = clock.now.addingTimeInterval(1)
            store.tick()
        }
        #expect(showing == 60)
        #expect(store.overlayNow == clock.now)
        #expect(store.overlayTodayDuration == 660)
        // 팝오버 시계는 그동안 건드리지 않았다(두 시계가 분리돼 있다는 증거).
        #expect(store.displayNow != store.overlayNow)

        // 오버레이 꺼짐: 0회.
        store.setOverlayEnabled(false)
        let hidden = assignmentTicks(of: { _ = store.overlayNow }, ticks: 60) {
            clock.now = clock.now.addingTimeInterval(1)
            store.tick()
        }
        #expect(hidden == 0)

        // 오버레이는 켜졌지만 비근무: 0회(패널이 없다).
        store.startedAt = nil
        store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        store.setOverlayEnabled(true)
        #expect(!store.overlayClockIsShowing)
        let idle = assignmentTicks(of: { _ = store.overlayNow }, ticks: 60) {
            clock.now = clock.now.addingTimeInterval(1)
            store.tick()
        }
        #expect(idle == 0)
    }

    // MARK: (c) 메뉴바 라벨은 닫혀 있어도 매초 살아 있고 snapshot 은 건드리지 않는다

    @Test func menuBarTitleAdvancesEverySecondWhileClosedWithoutSnapshotReassignment() {
        let clock = TestClock(t0)
        let store = makeStore(host: "v0238-clock-c", suiteName: "check-v0238-clock-c", clock: clock)
        defer { cancelTasks(store) }
        beginWork(store, startedAt: t0.addingTimeInterval(-10)) // 1시간 미만 → MM:SS 라벨(초가 보인다)
        store.displayNow = .distantPast // 팝오버 시계를 일부러 망가뜨려 둔다 — 라벨은 이것을 읽으면 안 된다
        #expect(!store.isMenuPresented)

        var titleTicks = 0
        var snapshotTicks = 0
        var displayNowTicks = 0
        for _ in 0..<60 {
            let title = FireFlag(), snap = FireFlag(), display = FireFlag()
            withObservationTracking { _ = store.menuBarTitle } onChange: { title.fired = true }
            withObservationTracking { _ = store.snapshot } onChange: { snap.fired = true }
            withObservationTracking { _ = store.displayNow } onChange: { display.fired = true }
            clock.now = clock.now.addingTimeInterval(1)
            store.tick()
            if title.fired { titleTicks += 1 }
            if snap.fired { snapshotTicks += 1 }
            if display.fired { displayNowTicks += 1 }
            #expect(store.menuBarTitle == MenuBarStatusFormatter.duration(store.todayDuration(at: clock.now)))
        }
        #expect(titleTicks == 60, "닫힌 팝오버에서 메뉴바 라벨이 \(titleTicks)/60 틱만 갱신됐다.")
        #expect(snapshotTicks == 0, "티커가 snapshot 을 \(snapshotTicks)번 재대입했다 — 라벨/오버레이/헤더 전체 무효화.")
        #expect(displayNowTicks == 0)
        #expect(store.menuBarTitle == "01:10")
    }

    // MARK: (d) 마일스톤은 주입 시계 기준이다

    @Test func milestonesFireOnTheInjectedClockNotThePopoverClock() {
        let clock = TestClock(t0)
        let store = makeStore(host: "v0238-clock-d", suiteName: "check-v0238-clock-d", clock: clock)
        defer { cancelTasks(store) }
        var events: [ReactionKind] = []
        store.onReactionTrigger = { events.append($0) }
        beginWork(store, startedAt: t0.addingTimeInterval(-3_599))
        // 팝오버 시계는 근무 시작 시각에 얼어 있다(닫힌 팝오버의 실제 모양) — 그 기준으로는 오늘 누적이 0이다.
        store.displayNow = t0.addingTimeInterval(-3_599)
        #expect(store.todayDuration == 0)

        clock.now = t0 // 3599초 — 아직 아니다
        store.tick()
        #expect(events.isEmpty)

        clock.now = t0.addingTimeInterval(1) // 3600초 — 1시간 마일스톤
        store.tick()
        #expect(events == [.milestone], "1시간 마일스톤이 clock() 기준 제시각에 발화하지 않았다: \(events)")
        // 팝오버 시계 기준은 여전히 0 — 발화가 그 시계와 무관하다는 증거.
        #expect(store.todayDuration == 0)

        // 같은 날 두 번 발화하지 않는다(기존 1일 1회 계약 유지).
        clock.now = t0.addingTimeInterval(2)
        store.tick()
        #expect(events == [.milestone])
    }

    @Test func todayDurationAtIsIndependentOfDisplayNow() {
        let clock = TestClock(t0)
        let store = makeStore(host: "v0238-clock-td", suiteName: "check-v0238-clock-td", clock: clock)
        defer { cancelTasks(store) }
        beginWork(store, startedAt: t0.addingTimeInterval(-600))
        store.displayNow = t0.addingTimeInterval(-600)
        #expect(store.todayDuration == 0)
        #expect(store.todayDuration(at: t0) == 600)
        #expect(store.todayDuration(at: t0.addingTimeInterval(3_000)) == 3_600)
        // 자정 클리핑·음수 클램프는 시각 인자형에도 그대로다.
        let dayStart = TeamWeeklyGoal.koreanDayStart(for: t0)
        store.startedAt = dayStart.addingTimeInterval(-7_200)
        #expect(store.todayDuration(at: dayStart.addingTimeInterval(1_800)) == 1_800)
        store.startedAt = t0.addingTimeInterval(600)
        #expect(store.todayDuration(at: t0) == 0)
    }

    // MARK: (e) 표시 없는 근무 1시간 → 60초 티커, 기록은 정확

    @Test func tickerSlowsToAMinuteAfterAnIdleHourAndKeepsTheRecordExact() {
        let clock = TestClock(t0)
        let store = makeStore(host: "v0238-clock-e", suiteName: "check-v0238-clock-e", clock: clock)
        defer { cancelTasks(store) }
        beginWork(store, startedAt: t0.addingTimeInterval(-3_600)) // 이미 1시간 → 라벨은 HH:MM
        store.setOverlayEnabled(false)
        #expect(!store.isMenuPresented)

        store.tick() // 표시 없는 상태의 시작(t0)을 장부에 적는다
        #expect(store.nextTickDelay(now: clock.now) == 1)
        clock.now = t0.addingTimeInterval(3_599)
        store.tick()
        #expect(store.nextTickDelay(now: clock.now) == 1, "1시간이 차기 전에 감속했다.")

        clock.now = t0.addingTimeInterval(3_600)
        store.tick()
        #expect(store.nextTickDelay(now: clock.now) == 60)
        // 분 경계 정렬: 분에서 23초 지난 시각이면 다음 분 넘김까지 37초.
        #expect(store.nextTickDelay(now: t0.addingTimeInterval(3_600 + 23)) == 37)

        // 감속 틱 10회. 근무 시간 계산은 주기와 무관하게 정확하고, 라벨도 그 값이다.
        for minute in 1...10 {
            clock.now = t0.addingTimeInterval(3_600 + 60 * Double(minute))
            store.tick()
            let expected = 7_200 + 60 * minute
            #expect(store.todayDuration(at: clock.now) == expected)
            #expect(store.menuBarTitle == MenuBarStatusFormatter.duration(expected))
            #expect(store.nextTickDelay(now: clock.now) == 60)
        }

        // 실제 티커에도 반영된다: 루프가 다음 잠을 정할 때 60을 고른다.
        store.startTimer()
        #expect(store.armNextTickDelay() == 60)
        #expect(store.currentTickDelay == 60)

        // 팝오버가 열리면 즉시 1초 주기로 돌아온다(옛 루프는 취소되고 새 루프가 선다).
        let slowLoop = store.tickerTask
        store.setMenuPresented(true)
        #expect(store.currentTickDelay == 1)
        #expect(slowLoop?.isCancelled == true, "감속 중이던 티커 루프가 그대로 남아 최대 60초 동안 초침이 멈춘다.")
        #expect(store.tickerTask != nil)
        #expect(store.nextTickDelay(now: clock.now) == 1)
    }

    @Test func slowdownNeverEngagesWhileAnyClockShowsOrTheLabelShowsSeconds() {
        // 오버레이 시계가 보이면 2시간이 지나도 1초.
        do {
            let clock = TestClock(t0)
            let store = makeStore(host: "v0238-clock-e2", suiteName: "check-v0238-clock-e2", clock: clock)
            defer { cancelTasks(store) }
            beginWork(store, startedAt: t0.addingTimeInterval(-3_600))
            store.setOverlayEnabled(true)
            for hour in 0...2 {
                clock.now = t0.addingTimeInterval(3_600 * Double(hour))
                store.tick()
            }
            #expect(store.nextTickDelay(now: clock.now) == 1)
            #expect(store.displayIdleSince == nil)
        }
        // 팝오버가 열려 있으면 1초.
        do {
            let clock = TestClock(t0)
            let store = makeStore(host: "v0238-clock-e3", suiteName: "check-v0238-clock-e3", clock: clock)
            defer { cancelTasks(store) }
            beginWork(store, startedAt: t0.addingTimeInterval(-3_600))
            store.setOverlayEnabled(false)
            store.isMenuPresented = true
            for hour in 0...2 {
                clock.now = t0.addingTimeInterval(3_600 * Double(hour))
                store.tick()
            }
            #expect(store.nextTickDelay(now: clock.now) == 1)
        }
        // 라벨이 초를 보이는 동안(자정 통과로 오늘 누적이 1시간 미만)은 표시가 없어도 1초 — 초침이 60초씩 건너뛰면 안 된다.
        do {
            let dayStart = TeamWeeklyGoal.koreanDayStart(for: t0)
            let lateNight = dayStart.addingTimeInterval(-1_800) // 어제 23:30
            let clock = TestClock(lateNight)
            let store = makeStore(host: "v0238-clock-e4", suiteName: "check-v0238-clock-e4", clock: clock)
            defer { cancelTasks(store) }
            beginWork(store, startedAt: lateNight)
            store.setOverlayEnabled(false)
            store.tick()
            clock.now = dayStart.addingTimeInterval(1_800) // 00:30 — 표시 없는 1시간은 찼지만 오늘 누적은 30분
            store.tick()
            #expect(store.todayDuration(at: clock.now) == 1_800)
            #expect(store.nextTickDelay(now: clock.now) == 1)
            // 01:00 을 넘겨 라벨이 분 단위가 되면 그때 감속한다.
            clock.now = dayStart.addingTimeInterval(3_600)
            store.tick()
            #expect(store.nextTickDelay(now: clock.now) == 60)
        }
    }

    // MARK: (f) 깨움 결합 게이트

    @Test func wakeGateHoldsEveryRequestUntilThePathIsSatisfiedThenPollsOnceBeforeRejoining() async {
        let host = "v0238-clock-wake-gate"
        let clock = TestClock(t0)
        let (store, transport) = await makeSuspendedWakeStore(
            host: host, suiteName: "check-v0238-clock-wake-gate", clock: clock, startedAt: t0.addingTimeInterval(-1_800)
        )
        defer { cancelTasks(store) }
        let path = ScriptedNetworkPath(satisfied: false)
        store.networkPath = path
        let baseline = requestCount(host: host)

        // 유예(5분) 안의 짧은 잠자기 — 로컬 마감 없이 되돌아 나가는 가지. 깨움은 게이트를 세우고 루프를 내린다.
        clock.now = t0.addingTimeInterval(60)
        store.handleWake(at: clock.now)
        #expect(store.wakeGateTask != nil)
        #expect(store.refreshTask == nil, "게이트가 refresh 루프를 내리지 않았다 — 만료된 잠이 곧바로 본문을 쏜다.")
        #expect(store.pokePollTask == nil)
        #expect(store.realtimeState == .idle(.suspended), "결합 전에 재연결이 시작됐다.")

        // 경로 미충족 동안: 요청 0건, 조인 0건.
        await holdBriefly()
        #expect(path.waits == 1)
        #expect(requestCount(host: host) == baseline, "결합 전 요청 \(requestCount(host: host) - baseline)건 — 깨움 폭주 그대로다.")
        #expect(transport.connectCount == 1)
        #expect(store.realtimeState == .idle(.suspended))

        // 충족 순간: 폴링 본문 1회 → 조인 1회, 이 순서로.
        store.refreshLoopSliceSeconds = 30 // 되살아난 루프의 두 번째 본문이 검증 창에 끼어들지 않게
        path.satisfy()
        await waitUntil { transport.connectCount == 2 }
        #expect(transport.connectCount == 2, "게이트가 열렸는데 재연결이 없다.")
        #expect(store.wakeGateTask == nil)
        if case .connecting = store.realtimeState {} else {
            Issue.record("게이트 뒤 재연결이 시작되지 않았다: \(store.realtimeState)")
        }
        let statusGETs = requestCount(host: host, path: workStatusesPath, method: "GET")
        #expect(statusGETs == 1, "게이트 뒤 폴링 본문이 \(statusGETs)회 돌았다 — 단일 tick 이어야 한다.")
        let requestsBeforeJoin = transport.requestCountsAtConnect.last.map { $0 - baseline } ?? -1
        #expect(requestsBeforeJoin >= 1, "조인이 폴링 본문보다 먼저 나갔다(조인 시점까지의 요청 \(requestsBeforeJoin)건).")
        #expect(requestsBeforeJoin == requestCount(host: host) - baseline, "조인 뒤에 본문 요청이 더 나갔다 — 본문이 끝나기 전에 조인했다.")
        // 루프는 되살아나 있다(다음 주기는 평소대로).
        #expect(store.refreshTask != nil)
        #expect(store.pokePollTask != nil)
    }

    @Test func wakeGateForcesProgressWhenTheBoundExpires() async {
        let host = "v0238-clock-wake-timeout"
        let clock = TestClock(t0)
        let (store, transport) = await makeSuspendedWakeStore(
            host: host, suiteName: "check-v0238-clock-wake-timeout", clock: clock, startedAt: t0.addingTimeInterval(-1_800)
        )
        defer { cancelTasks(store) }
        let path = ScriptedNetworkPath(satisfied: false) // 영영 붙지 않는 네트워크
        store.networkPath = path
        store.wakeGateTimeoutSeconds = 0.15
        store.refreshLoopSliceSeconds = 30
        let baseline = requestCount(host: host)

        clock.now = t0.addingTimeInterval(60)
        store.handleWake(at: clock.now)
        #expect(store.wakeGateTask != nil)

        // 상한이 지나면 결합 여부와 무관하게 진행한다 — 절대 영구 대기하지 않는다.
        await waitUntil { transport.connectCount == 2 }
        #expect(transport.connectCount == 2, "상한이 지났는데 게이트가 열리지 않았다.")
        #expect(store.wakeGateTask == nil)
        #expect(!path.isSatisfied)
        #expect(requestCount(host: host, path: workStatusesPath, method: "GET") == 1)
        #expect((transport.requestCountsAtConnect.last ?? 0) - baseline >= 1, "강제 진행에서도 본문 → 조인 순서다.")
    }

    @Test func alreadySatisfiedPathReleasesTheGateWithoutWaiting() async {
        let host = "v0238-clock-wake-ready"
        let clock = TestClock(t0)
        let (store, transport) = await makeSuspendedWakeStore(
            host: host, suiteName: "check-v0238-clock-wake-ready", clock: clock, startedAt: t0.addingTimeInterval(-1_800)
        )
        defer { cancelTasks(store) }
        let path = ScriptedNetworkPath(satisfied: true)
        store.networkPath = path
        store.wakeGateTimeoutSeconds = 30 // 상한이 아니라 즉시 충족으로 열려야 한다
        store.refreshLoopSliceSeconds = 30

        clock.now = t0.addingTimeInterval(60)
        store.handleWake(at: clock.now)
        await waitUntil { transport.connectCount == 2 }
        #expect(transport.connectCount == 2)
        #expect(path.waits == 1)
        #expect(requestCount(host: host, path: workStatusesPath, method: "GET") == 1)
    }

    @Test func wakeWithoutAnObserverRejoinsImmediatelyAsBefore() async {
        // 관측자 nil(테스트 기본값) = 게이트 없음. 기존 스위트(RealtimeLinkTests `깨어나면_맨_먼저_다시_붙는다`)가
        // 기대는 동기 재연결이 그대로다 — 이 규약이 깨지면 그쪽이 먼저 빨개진다.
        let host = "v0238-clock-wake-legacy"
        let clock = TestClock(t0)
        let (store, transport) = await makeSuspendedWakeStore(
            host: host, suiteName: "check-v0238-clock-wake-legacy", clock: clock, startedAt: t0.addingTimeInterval(-1_800)
        )
        defer { cancelTasks(store) }
        #expect(store.networkPath == nil)

        store.handleWake(at: t0.addingTimeInterval(60))
        if case .connecting = store.realtimeState {} else {
            Issue.record("관측자가 없는데 즉시 재연결되지 않았다: \(store.realtimeState)")
        }
        #expect(transport.connectCount == 2)
        #expect(store.refreshTask != nil, "게이트가 없는데 루프를 내렸다.")
    }

    @Test func wakeGateDelaysTheSleepCorrectionButNeverLosesIt() async {
        // 유예 밖 잠자기(v0.2.36 정정 계약): 로컬 판정은 깨우는 즉시 — 마커 소거·큐 1건·근무 내림 — 이고, 그 정정 PATCH 만
        // 게이트 뒤에서 나간다. 결합 대기는 정정을 늦출 뿐 잃지 않는다.
        let host = "v0238-clock-wake-sleep"
        let clock = TestClock(t0)
        let (store, _) = await makeSuspendedWakeStore(
            host: host, suiteName: "check-v0238-clock-wake-sleep", clock: clock, startedAt: t0.addingTimeInterval(-3_600)
        )
        defer { cancelTasks(store) }
        store.lastMeaningfulInputAt = t0.addingTimeInterval(-600)
        #expect(store.pendingSleepCloseMarker() != nil)
        let path = ScriptedNetworkPath(satisfied: false)
        store.networkPath = path
        store.refreshLoopSliceSeconds = 30
        let patchesBefore = requestCount(host: host, path: workSessionsPath, method: "PATCH")

        clock.now = t0.addingTimeInterval(1_200) // 20분 — 유예 밖
        store.handleWake(at: clock.now)

        // 로컬 판정은 게이트를 기다리지 않는다.
        #expect(store.startedAt == nil)
        #expect(store.pendingSleepCloseMarker() == nil, "마커가 소비되지 않았다.")
        #expect(store.pendingItems.count == 1)
        #expect(store.pendingItems.first?.autoCloseReason == .sleep)
        #expect(store.pendingItems.first?.endedAt == t0.addingTimeInterval(-600))

        // 결합 전: 정정 PATCH 가 나가지 않는다(나가면 실패 → "대기" → 재시도 헛왕복).
        await holdBriefly()
        #expect(requestCount(host: host, path: workSessionsPath, method: "PATCH") == patchesBefore)
        #expect(store.pendingItems.count == 1, "결합 전에 큐가 비었다 — 정정이 게이트를 우회해 나갔다.")

        // 결합 뒤: 정정이 나가고(마감 PATCH 한 벌 — 0행 갈래의 사유 정정까지 여러 PATCH 일 수 있다) 큐가 빈다.
        path.satisfy()
        await waitUntil { store.pendingItems.isEmpty }
        #expect(store.pendingItems.isEmpty, "게이트가 열렸는데 정정이 드레인되지 않았다.")
        await waitUntil { requestCount(host: host, path: workSessionsPath, method: "PATCH") > patchesBefore }
        #expect(requestCount(host: host, path: workSessionsPath, method: "PATCH") > patchesBefore)
        #expect(URLProtocolStub.bodyText(forHost: host).contains("\"auto_closed_reason\":\"sleep\""), "정정 사유(sleep)가 서버로 가지 않았다.")
        #expect(store.wakeGateTask == nil)
    }

    // MARK: 오버레이 라벨은 오버레이 시계를 따른다 (팝오버 닫힘 + 오버레이 표시 중)

    @Test func overlayLabelAdvancesEverySecondWhileThePopoverIsClosed() throws {
        let clock = TestClock(t0)
        let store = makeStore(host: "v0238-clock-label", suiteName: "check-v0238-clock-label", clock: clock)
        defer { cancelTasks(store) }
        beginWork(store, startedAt: t0.addingTimeInterval(-600))
        store.setOverlayEnabled(true)
        // 팝오버 시계는 근무 시작 시각에 얼어 있다(닫힌 팝오버의 실제 모양). 라벨이 이것을 읽으면 600초에서 멈춘다.
        store.displayNow = t0.addingTimeInterval(-600)
        #expect(!store.isMenuPresented)
        let root = CheckOverlayRootView(store: store, engine: nil, onWorkingChange: { _ in })

        let before = try #require(overlayLabelSeconds(in: root.body))
        #expect(before == 600)

        // 60틱: 라벨 초가 60 전진하고, 팝오버 시계는 한 번도 대입되지 않는다.
        var displayNowTicks = 0
        var bodyInvalidations = 0
        for _ in 0..<60 {
            let display = FireFlag(), body = FireFlag()
            withObservationTracking { _ = store.displayNow } onChange: { display.fired = true }
            withObservationTracking { _ = root.body } onChange: { body.fired = true }
            clock.now = clock.now.addingTimeInterval(1)
            store.tick()
            if display.fired { displayNowTicks += 1 }
            if body.fired { bodyInvalidations += 1 }
        }
        let after = try #require(overlayLabelSeconds(in: root.body))
        #expect(after - before == 60, "닫힌 팝오버에서 오버레이 라벨이 \(after - before)초만 전진했다 — 라벨이 팝오버 시계를 읽고 있다.")
        #expect(displayNowTicks == 0)
        #expect(bodyInvalidations == 60, "오버레이 body 가 오버레이 시계에 \(bodyInvalidations)/60 틱만 반응했다.")
        #expect(store.todayDuration == 0, "대조: 팝오버 시계 기준 누적은 여전히 0 — 라벨 전진이 그 시계와 무관하다는 증거.")

        // 반대 방향: 팝오버 시계만 밀어도 오버레이 body 는 무효화되지 않는다(두 표면의 분리).
        let stray = FireFlag()
        withObservationTracking { _ = root.body } onChange: { stray.fired = true }
        store.displayNow = clock.now
        #expect(!stray.fired, "팝오버 시계 대입이 오버레이 body 를 깨웠다 — 라벨이 displayNow 를 관찰한다.")
    }

    @Test func overlayRootReadsTheOverlayClockInSource() throws {
        // 위 테스트가 값으로 증명하지만, 라벨 식이 다른 파생값(예: myLiveWeeklySeconds)으로 갈아타 우연히 초록이 되는
        // 길을 막기 위해 소스로도 못 박는다. 주석을 걷어낸 뒤 CheckOverlayRootView 본문만 본다(하우스 규칙).
        let code = strippingSwiftComments(
            try String(contentsOf: sourceURL("CheckCharacter3DView.swift"), encoding: .utf8)
        )
        let start = try #require(code.range(of: "struct CheckOverlayRootView"))
        let end = try #require(code.range(of: "enum CheckOverlayTimeFormatter", range: start.upperBound..<code.endIndex))
        let body = String(code[start.upperBound..<end.lowerBound])
        #expect(body.contains("store.overlayTodayDuration"))
        #expect(!body.contains("store.todayDuration"), "오버레이 라벨이 팝오버 시계 파생값을 읽는다.")
        #expect(!body.contains("displayNow"))
    }

    // MARK: 측면 표 이관 — lastTeamStatusAt 은 스토어의 저장 프로퍼티다

    @Test func lastTeamStatusAtLivesOnEachStore() {
        let clock = TestClock(t0)
        let a = makeStore(host: "v0238-clock-stamp-a", suiteName: "check-v0238-clock-stamp-a", clock: clock)
        let b = makeStore(host: "v0238-clock-stamp-b", suiteName: "check-v0238-clock-stamp-b", clock: clock)
        defer {
            cancelTasks(a)
            cancelTasks(b)
        }
        #expect(a.lastTeamStatusAt == .distantPast)
        a.lastTeamStatusAt = t0
        #expect(a.lastTeamStatusAt == t0)
        #expect(b.lastTeamStatusAt == .distantPast)
        #expect(a.teamStatusIsFresh(now: t0.addingTimeInterval(14)))
        #expect(!a.teamStatusIsFresh(now: t0.addingTimeInterval(15)))
    }
}
