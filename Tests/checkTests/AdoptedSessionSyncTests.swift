import Foundation
import Observation
import Testing
@testable import check

// MARK: - D2: 흡수 세션 소유권 표식 (adoptedRemoteSession)
//
// 이 스위트가 고정하는 계약: "진행 중 세션을 **이 앱 인스턴스가 열지 않았다**"는 사실을 표식으로 남기고,
// 그 동안 이 맥의 하트비트가 서버에 아무 쓰기도 하지 않는다. 하트비트는 '내가 이 세션의 소유 맥이다'라는
// 선언이라, 흡수 세션에서 계속 보내면 work_statuses.last_seen_at 이 영원히 신선해져 서버/클라 스캐빈저의
// 10분 무신호 판정이 발화하지 못한다 — 자동 마감 경로까지 막힌 상태에서 그건 '아무도 못 닫는 세션'이다.

@MainActor
@Test
func adoptedSessionSendsNoHeartbeat() async {
    // 흡수 상태에서 하트비트가 한 건도 나가지 않아야 스캐빈저의 신호 공백 시계가 실제로 흐른다.
    let testHost = "adopted-heartbeat-test"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeAdoptedSyncStubStore(host: testHost, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    // 다른 맥이 2시간 전에 연 세션이 서버 스냅샷으로 도착한 상황(로컬은 비근무).
    let remoteStart = Date().addingTimeInterval(-7_200)
    let remoteSessionID = "90000000-0000-0000-0000-000000000001"
    store.teamMembers = [remoteWorkingMember(userID: userID, startedAt: remoteStart, sessionID: remoteSessionID)]

    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

    // (.working, nil) → 정식 흡수: 서버의 시작시각/세션ID를 그대로 미러링하고 표식을 세운다.
    #expect(store.adoptedRemoteSession)
    #expect(store.startedAt == remoteStart)
    #expect(store.currentSessionID == remoteSessionID)
    #expect(store.longSessionAnchor == remoteStart)
    #expect(store.snapshot.isWorking)

    await store.sendHeartbeatIfWorking()

    // 요청 0건 — 이 맥은 남의 세션에 대해 서버에 아무 말도 하지 않는다.
    #expect(URLProtocolStub.requests(forHost: testHost).isEmpty)
}

@MainActor
@Test
func ownSessionStillHeartbeats() async {
    // 대조군. 표식이 하트비트를 **통째로** 죽여 버리면 정상 근무의 생존신호가 끊겨 내 세션이 10분 뒤
    // 스캐빈저에 마감된다(그 뒤 근무 전량 유실). start() 가 연 세션은 표식이 서지 않고 신호가 나가야 한다.
    let testHost = "own-heartbeat-control-test"
    let store = makeAdoptedSyncStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    store.start()
    await store.syncTask?.value

    #expect(!store.adoptedRemoteSession)
    #expect(store.startedAt != nil)
    #expect(store.currentSessionID != nil)

    // start() 자체도 상태 upsert 를 한 번 보내므로, 하트비트 몫만 증분으로 센다.
    let before = statusUpsertCount(host: testHost)
    await store.sendHeartbeatIfWorking()
    #expect(statusUpsertCount(host: testHost) - before == 1)
}

@MainActor
@Test
func remoteSessionCloseClearsAdoptionMarks() async {
    // 서버가 그 세션을 닫았으면(스캐빈저/다른 맥의 종료) 로컬도 **완전히** 내려놓아야 한다.
    // 예전엔 startedAt 만 지우고 currentSessionID 를 남겨, 이미 닫힌 id 가 다음 재흡수(찢어진 읽기로
    // activeSessionID 가 비어 오면 ?? currentSessionID 로 되살아난다)와 자동 마감 폴백 POST 에
    // 그대로 실려 나갔다. 표식까지 남으면 다음 세션이 이 맥 것인데도 하트비트가 죽는다.
    let testHost = "adopted-remote-close-test"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeAdoptedSyncStubStore(host: testHost, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    let remoteStart = Date().addingTimeInterval(-7_200)
    let remoteSessionID = "90000000-0000-0000-0000-000000000002"
    store.teamMembers = [remoteWorkingMember(userID: userID, startedAt: remoteStart, sessionID: remoteSessionID)]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    #expect(store.adoptedRemoteSession)

    // 다음 폴링: 서버는 이제 off_work. 오늘 몫 2시간은 완료 세션으로 집계돼 내려온다.
    store.teamMembers = [
        TeamMemberStatus(
            id: userID,
            name: "영식",
            status: .offWork,
            updatedAt: Date(),
            currentSessionStartedAt: nil,
            weeklyDurationSeconds: 7_200,
            todayDurationSeconds: 7_200,
            avatarURL: nil,
            lastSeenAt: Date(),
            activeSessionID: nil
        )
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

    #expect(store.startedAt == nil)
    #expect(store.currentSessionID == nil)
    #expect(!store.adoptedRemoteSession)
    #expect(store.longSessionAnchor == nil)
    #expect(!store.snapshot.isWorking)
    #expect(store.snapshot.elapsedSeconds == 7_200)

    // 세션ID 까지 끊겼으므로 하트비트는 이제 부활시킬 대상 자체가 없다(요청 0건).
    await store.sendHeartbeatIfWorking()
    #expect(URLProtocolStub.requests(forHost: testHost).isEmpty)
}

@MainActor
@Test
func replacedRemoteSessionIsReadopted() {
    // 흡수 맥이 어제 시작시각을 든 채 **오늘의 다른 세션**을 미러링하면 타이머가 20시간이 된다.
    // 부분 유니크 인덱스(work_sessions_one_open_per_user)상 사용자당 열린 세션은 하나뿐이므로,
    // 서버가 다른 id 를 들고 있다는 것은 내가 든 id 가 이미 닫혔다는 뜻이다 — 서버 쪽이 진실이다.
    let testHost = "readopt-replaced-session-test"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeAdoptedSyncStubStore(host: testHost, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    let yesterdayStart = Date().addingTimeInterval(-20 * 3_600)
    store.startedAt = yesterdayStart
    store.currentSessionID = "90000000-0000-0000-0000-000000000003"
    store.longSessionAnchor = yesterdayStart
    store.adoptedRemoteSession = true
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)

    let todayStart = Date().addingTimeInterval(-2 * 3_600)
    let todaySessionID = "90000000-0000-0000-0000-000000000004"
    store.teamMembers = [remoteWorkingMember(userID: userID, startedAt: todayStart, sessionID: todaySessionID)]

    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

    #expect(store.startedAt == todayStart)
    #expect(store.currentSessionID == todaySessionID)
    #expect(store.longSessionAnchor == todayStart)
    #expect(store.adoptedRemoteSession)
}

@MainActor
@Test
func tornStatusReadDoesNotReadoptWithoutOpenSessionRow() {
    // work_statuses 와 work_sessions 는 병렬 GET 이라(SupabaseWorkService) 상태표만 먼저 도착할 수 있다.
    // 그때 currentSessionStartedAt 은 nil 이고, 그대로 흡수하면 시작시각이 now 로 리셋돼 진행 중이던
    // 근무 시간이 통째로 증발한다. 열린 세션 행이 함께 온 경우에만 재흡수해야 한다.
    let testHost = "readopt-torn-read-test"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeAdoptedSyncStubStore(host: testHost, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    let localStart = Date().addingTimeInterval(-3 * 3_600)
    let localSessionID = "90000000-0000-0000-0000-000000000005"
    store.startedAt = localStart
    store.currentSessionID = localSessionID
    store.longSessionAnchor = localStart
    store.adoptedRemoteSession = true
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)

    // 상태표는 '근무중 + 다른 세션 id'인데 열린 세션 행(currentSessionStartedAt)이 비어 온 찢어진 읽기.
    store.teamMembers = [
        TeamMemberStatus(
            id: userID,
            name: "영식",
            status: .working,
            updatedAt: Date(),
            currentSessionStartedAt: nil,
            weeklyDurationSeconds: 0,
            todayDurationSeconds: 0,
            avatarURL: nil,
            lastSeenAt: Date(),
            activeSessionID: "90000000-0000-0000-0000-000000000006"
        )
    ]

    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

    // 아무것도 갈아치우지 않는다 — 다음 폴링에서 온전한 스냅샷이 오면 그때 재흡수한다.
    #expect(store.startedAt == localStart)
    #expect(store.currentSessionID == localSessionID)
    #expect(store.adoptedRemoteSession)
}

@MainActor
@Test
func readoptionSkipsRedundantStartedAtAssignment() {
    // 30초 폴링이 도는 경로라 == 가드가 없으면 값이 그대로여도 관찰자가 매번 발화해 팝오버 서브트리가
    // 통째로 무효화된다(@Observable 은 동일 값 대입도 발화시킨다).
    let testHost = "readopt-equality-guard-test"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeAdoptedSyncStubStore(host: testHost, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    let remoteStart = Date().addingTimeInterval(-7_200)
    store.teamMembers = [
        remoteWorkingMember(userID: userID, startedAt: remoteStart, sessionID: "90000000-0000-0000-0000-000000000007")
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    #expect(store.startedAt == remoteStart)

    // 세션 id 만 바뀌어 재흡수가 일어나는 경우에도, 시작시각이 같으면 startedAt 은 재대입되지 않아야 한다.
    store.teamMembers = [
        remoteWorkingMember(userID: userID, startedAt: remoteStart, sessionID: "90000000-0000-0000-0000-000000000008")
    ]
    let fired = AdoptionObservationFlag()
    withObservationTracking { _ = store.startedAt } onChange: { fired.value = true }
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

    #expect(!fired.value)
    #expect(store.startedAt == remoteStart)
    #expect(store.currentSessionID == "90000000-0000-0000-0000-000000000008")
}

// MARK: - 헬퍼

/// withObservationTracking 의 @Sendable onChange 에서 발화 여부를 받아 두는 상자.
/// 관찰 알림은 MainActor 의 willSet 에서 동기 발화하므로 실제 경합은 없다.
private final class AdoptionObservationFlag: @unchecked Sendable {
    var value = false
}

/// 이 스위트가 세는 '하트비트성 쓰기'. startWork 도 같은 upsert 를 한 번 보내므로 증분으로만 판정한다.
@MainActor
private func statusUpsertCount(host: String) -> Int {
    URLProtocolStub.requests(forHost: host)
        .filter { $0.url?.path == "/rest/v1/work_statuses" && $0.httpMethod == "POST" }
        .count
}

/// 서버 스냅샷의 '내 행'(근무중 + 열린 세션)을 만든다. 신호는 신선하게 둬 stale 판정/자동 마감 경로가
/// 끼어들지 않게 한다 — 이 스위트가 보려는 것은 흡수와 하트비트뿐이다.
@MainActor
private func remoteWorkingMember(userID: String, startedAt: Date, sessionID: String) -> TeamMemberStatus {
    TeamMemberStatus(
        id: userID,
        name: "영식",
        status: .working,
        updatedAt: Date(),
        currentSessionStartedAt: startedAt,
        weeklyDurationSeconds: 0,
        todayDurationSeconds: 0,
        avatarURL: nil,
        lastSeenAt: Date(),
        activeSessionID: sessionID
    )
}

@MainActor
private func makeAdoptedSyncStubStore(
    host: String,
    userID: String = "00000000-0000-0000-0000-000000000002"
) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let suiteName = "check-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
    // 세션을 직접 주입하는 테스트는 로그인 흐름(confirmMembership)을 건너뛰므로 팀도 직접 확정한다.
    store.currentTeamID = URLProtocolStub.stubTeamID
    return store
}
