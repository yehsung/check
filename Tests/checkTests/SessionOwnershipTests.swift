import Foundation
import Testing
@testable import check

// MARK: - v0.2.15: 재시작한 내 세션의 소유권 (check.session.ownedWorkSessionID)
//
// D2(흡수 세션 표식)가 만든 회귀를 고정하는 스위트다. startedAt 은 영속되지 않으므로 **근무 중 앱이
// 재시작되면 반드시** (.working, nil) 분기를 타고, 예전엔 그 자리에서 무조건 흡수로 판정했다. 표식을
// 내리는 곳은 전부 사용자 조작이거나 그 세션의 사망이라, 유일한 소유 맥이 자기 세션을 되찾을 길이 없었다:
//   재시작 → 흡수 판정 → 하트비트 영구 정지 → 90초 뒤 팀원 화면 '연결 끊김'
//   → 10분 뒤 **내 앱 자신의** 스캐빈저가 close_abandoned_work_sessions 로 내 살아 있는 세션을 마감.
// 해당 상황: 자동 업데이트 후 재실행 · 크래시 · 사용자가 껐다 켬 · 재부팅(D1 킥이 즉시 폴링한다).
//
// 수리는 2단이고 이 스위트는 두 단과 **대조군**을 함께 고정한다.
//  1차: start() 가 만든 세션 ID 를 영속해, 서버의 activeSessionID 와 같으면 '재시작한 나'로 판정한다.
//  2차: 소유 ID 가 없는 실행(= v0.2.14 → v0.2.15 업그레이드 재시작. 근무 중인 사용자 전원이 여기 해당)은
//       흡수 상태에서 서버의 last_seen_at 이 **전진하지 않고** stale(90초)이 되면 소유권을 되찾는다.
//  대조군: 다른 맥이 살아 있어 last_seen_at 이 폴링마다 전진하면 끝까지 흡수 상태다(D2 성질 보존).

// MARK: - 픽스처

@MainActor
private func makeOwnershipStubStore(
    host: String,
    userID: String = "00000000-0000-0000-0000-000000000002"
) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let suiteName = "check-ownership-tests-\(UUID().uuidString)"
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

/// 서버 스냅샷의 '내 행'(근무중 + 열린 세션). lastSeenAt 을 명시로 받아 '전진/정지'를 테스트가 직접 조종한다.
/// deviceClaims 는 기본 빈 배열 = "아무 맥도 주장하지 않음"이 아니라 **판정 불가**(구버전 맥/표 없는 서버).
private func workingMember(
    userID: String,
    startedAt: Date,
    sessionID: String,
    lastSeenAt: Date,
    deviceClaims: [StatusDeviceClaim] = []
) -> TeamMemberStatus {
    TeamMemberStatus(
        id: userID,
        name: "영식",
        status: .working,
        updatedAt: lastSeenAt,
        currentSessionStartedAt: startedAt,
        weeklyDurationSeconds: 0,
        todayDurationSeconds: 0,
        avatarURL: nil,
        lastSeenAt: lastSeenAt,
        activeSessionID: sessionID,
        deviceClaims: deviceClaims
    )
}

/// 이 스위트가 세는 '하트비트성 쓰기'(work_statuses upsert). 흡수 상태에서는 0건이어야 한다.
@MainActor
private func statusUpsertCount(host: String) -> Int {
    URLProtocolStub.requests(forHost: host)
        .filter { $0.url?.path == "/rest/v1/work_statuses" && $0.httpMethod == "POST" }
        .count
}

/// 이 맥이 남긴 기기별 소유 주장(work_status_devices upsert) 건수. 흡수 상태에서는 0건이어야 한다 —
/// 그 행 자체가 '살아 있는 소유 주장'이라, 남기면 진짜 소유 맥이 그것을 보고 자기 세션을 반납한다.
@MainActor
private func deviceClaimCount(host: String) -> Int {
    URLProtocolStub.requests(forHost: host)
        .filter { $0.url?.path == "/rest/v1/work_status_devices" && $0.httpMethod == "POST" }
        .count
}

// MARK: - 1차: 결정적 판정(영속된 소유 세션 ID)

@MainActor
@Test
func startPersistsOwnedSessionIDAndStopClearsIt() {
    // 영속이 실제로 일어나야 재시작 판정이 성립한다. 그리고 종료 시 반드시 지워야, 이미 닫힌 세션을
    // 다음 실행이 '내 것'이라 우기며 죽은 세션에 하트비트를 쏘지 않는다.
    let host = "owned-id-persist"
    let store = makeOwnershipStubStore(host: host)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    #expect(store.ownedWorkSessionID == nil)

    store.start()
    #expect(store.ownedWorkSessionID != nil)
    #expect(store.ownedWorkSessionID == store.currentSessionID)

    store.stop()
    #expect(store.ownedWorkSessionID == nil)
}

@MainActor
@Test
func restartWithPersistedOwnSessionKeepsOwnershipAndHeartbeats() async {
    // **재시작 자살 소멸.** 근무 중 앱이 다시 뜬 상황을 그대로 재현한다: startedAt/currentSessionID 는
    // 사라졌고(영속 대상이 아님) UserDefaults 의 소유 ID 만 남았다. 서버는 같은 세션을 여전히 들고 있다.
    let host = "restart-owned-session"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let ownedSessionID = "a0000000-0000-0000-0000-000000000001"
    let sessionStart = Date().addingTimeInterval(-3 * 3_600)
    // 이전 실행의 start() 가 남긴 흔적. 이 값 하나가 '재시작한 나'와 '남의 맥'을 가른다.
    store.setOwnedWorkSessionID(ownedSessionID)
    #expect(store.startedAt == nil)

    store.teamMembers = [
        workingMember(
            userID: userID,
            startedAt: sessionStart,
            sessionID: ownedSessionID,
            // 방금 재시작이라 마지막 하트비트가 아직 신선하다(자리 비움 자동 마감 경로가 끼어들지 않는 구간).
            lastSeenAt: Date().addingTimeInterval(-20)
        )
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

    // 세션은 그대로 되살아나되 **소유권은 내 것**이다 — 표식이 서면 아래 하트비트가 통째로 죽는다.
    #expect(store.startedAt == sessionStart)
    #expect(store.currentSessionID == ownedSessionID)
    #expect(!store.adoptedRemoteSession)

    await store.sendHeartbeatIfWorking()
    #expect(statusUpsertCount(host: host) == 1)
    let bodies = zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
        .filter { $0.0.url?.path == "/rest/v1/work_statuses" && $0.0.httpMethod == "POST" }
        .map { $0.1 }
    #expect(bodies.first?.contains(#""active_session_id":"\#(ownedSessionID)""#) == true)
}

@MainActor
@Test
func restartWithForeignSessionIDStaysAdopted() {
    // 소유 ID 가 **다른 값**이면 그건 남의 맥이 연 세션이다. 1차 판정이 '아무 세션이나 내 것'으로
    // 퍼지면 D2 가 통째로 무력화되므로, 불일치는 반드시 흡수여야 한다.
    let host = "restart-foreign-session"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    store.setOwnedWorkSessionID("a0000000-0000-0000-0000-000000000002")
    let remoteStart = Date().addingTimeInterval(-2 * 3_600)
    store.teamMembers = [
        workingMember(
            userID: userID,
            startedAt: remoteStart,
            sessionID: "b0000000-0000-0000-0000-000000000003",
            lastSeenAt: Date().addingTimeInterval(-10)
        )
    ]

    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

    #expect(store.adoptedRemoteSession)
    #expect(store.startedAt == remoteStart)
    #expect(store.currentSessionID == "b0000000-0000-0000-0000-000000000003")
    // 남의 세션이므로 이 맥은 서버에 아무 말도 하지 않는다.
    #expect(URLProtocolStub.requests(forHost: host).isEmpty)
}

@MainActor
@Test
func remoteSessionCloseClearsPersistedOwnedSessionID() {
    // 서버가 내 세션을 닫았으면 소유 ID 도 함께 끊어야 한다. 남기면 다음 실행이 이미 닫힌 ID 를
    // '내 세션'으로 되찾으려 들어, 존재하지 않는 세션에 생존신호를 쏘는 상태로 굳는다.
    let host = "owned-id-cleared-on-close"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let ownedSessionID = "a0000000-0000-0000-0000-000000000004"
    store.setOwnedWorkSessionID(ownedSessionID)
    store.teamMembers = [
        workingMember(
            userID: userID,
            startedAt: Date().addingTimeInterval(-3_600),
            sessionID: ownedSessionID,
            lastSeenAt: Date().addingTimeInterval(-10)
        )
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    #expect(!store.adoptedRemoteSession)

    // 다음 폴링: 서버는 off_work(사용자가 다른 맥에서 종료했거나 스캐빈저가 마감).
    store.teamMembers = [
        TeamMemberStatus(
            id: userID,
            name: "영식",
            status: .offWork,
            updatedAt: Date(),
            currentSessionStartedAt: nil,
            weeklyDurationSeconds: 3_600,
            todayDurationSeconds: 3_600,
            avatarURL: nil,
            lastSeenAt: Date(),
            activeSessionID: nil
        )
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

    #expect(store.startedAt == nil)
    #expect(store.ownedWorkSessionID == nil)
    #expect(!store.adoptedRemoteSession)
}

// MARK: - 2차: 생존성 백스톱 (업그레이드 재시작 경로)

@MainActor
@Test
func upgradeRestartReclaimsOwnershipWhenLastSeenStops() async {
    // **업그레이드 경로.** v0.2.14 에서 올라온 사용자는 소유 ID 가 없어 1차 판정이 못 구한다(근무 중인
    // 사용자 전원이 이 경로다). 흡수한 뒤에도 서버의 last_seen_at 이 전진하지 않으면 그 세션을 돌보는
    // 인스턴스가 아무 데도 없다는 뜻이므로 소유권을 되찾고 하트비트를 재개해야 한다.
    let host = "upgrade-restart-reclaim"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    #expect(store.ownedWorkSessionID == nil)

    let sessionID = "c0000000-0000-0000-0000-000000000001"
    let sessionStart = Date().addingTimeInterval(-4 * 3_600)
    // 폴링 1: 재시작 직후. 마지막 하트비트는 20초 전이라 아직 신선하다 → 흡수로 시작한다.
    let frozenSeen = Date().addingTimeInterval(-20)
    store.teamMembers = [
        workingMember(userID: userID, startedAt: sessionStart, sessionID: sessionID, lastSeenAt: frozenSeen)
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    #expect(store.adoptedRemoteSession)

    // 폴링 2(+30초): 신호가 그대로다. 하지만 아직 임계 전이라 주장하지 않는다 — 신선도만 보고
    // 뺏으면 네트워크가 잠깐 밀린 살아 있는 맥의 근무를 가로챈다.
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    #expect(store.adoptedRemoteSession)
    await store.sendHeartbeatIfWorking()
    #expect(statusUpsertCount(host: host) == 0)

    // 폴링 3~: 신호가 여전히 굳은 채 30초 주기로 계속 관측한다. 임계는 이제 90초가 아니라
    // adoptedReclaimStaleSeconds(7분)다 — 90초는 이 앱 자신의 잠자기 유예(5분) 계약 한가운데를 잘라
    // 살아 있는 맥의 3분 낮잠만으로 소유권을 뺏던 값이라 계약을 바꿨다(아래 napping/vanished 테스트가 양쪽을 고정한다).
    let t0 = Date()
    for step in 1...30 where store.adoptedRemoteSession {
        store.updateAdoptedPresenceTracking(
            store.teamMembers[0],
            now: t0.addingTimeInterval(Double(step) * 30)
        )
    }

    #expect(!store.adoptedRemoteSession)
    // 되찾은 세션은 이제 이 맥의 것이다 — 다음 재시작이 다시 흡수로 떨어지지 않게 소유 ID 도 남는다.
    #expect(store.ownedWorkSessionID == sessionID)
    #expect(store.startedAt == sessionStart)

    await store.sendHeartbeatIfWorking()
    #expect(statusUpsertCount(host: host) == 1)
}

// MARK: - 대조군: 원래 D2 성질 보존 (이게 제일 중요)

@MainActor
@Test
func advancingLastSeenKeepsAdoptionSoOtherMacKeepsWorking() async {
    // **대조군.** 맥 A 가 실제로 근무 중이면 30초마다 하트비트로 last_seen_at 이 전진한다. 그 동안
    // 흡수한 맥 B 는 끝까지 물러나 있어야 한다 — 여기서 소유권을 주장하면 두 맥이 같은 세션에 생존신호를
    // 쏘아 '아무도 못 닫는 세션'이 되고, B 의 잠자기가 A 의 근무를 과거 시각으로 잘라 버린다.
    let host = "adoption-survives-advancing-seen"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let sessionID = "d0000000-0000-0000-0000-000000000001"
    let t0 = Date()
    let sessionStart = t0.addingTimeInterval(-5 * 3_600)
    store.teamMembers = [
        workingMember(
            userID: userID,
            startedAt: sessionStart,
            sessionID: sessionID,
            lastSeenAt: t0.addingTimeInterval(-150)
        )
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    #expect(store.adoptedRemoteSession)

    // 맥 A 는 살아 있지만 네트워크가 밀려 신호가 늘 120초 늦게 도착한다 — **나이는 계속 stale 임계를
    // 넘는데 값은 폴링마다 전진하는** 상황이다. 신선도만 보는 판정이 조금이라도 섞여 있으면 여기서
    // 곧바로 남의 근무를 가로챈다. 10번(=5분) 돌려도 흡수 상태가 유지돼야 한다.
    for index in 1...10 {
        let now = t0.addingTimeInterval(Double(index) * 30)
        let seen = now.addingTimeInterval(-120)
        store.updateAdoptedPresenceTracking(
            workingMember(userID: userID, startedAt: sessionStart, sessionID: sessionID, lastSeenAt: seen),
            now: now
        )
    }

    #expect(store.adoptedRemoteSession)
    // 소유 ID 도 세우지 않는다 — 세우면 이 맥이 다음 재시작에서 남의 세션을 자기 것이라 우긴다.
    #expect(store.ownedWorkSessionID == nil)

    // 하트비트 0건: 이 맥은 남의 세션에 대해 서버에 아무 말도 하지 않는다.
    await store.sendHeartbeatIfWorking()
    #expect(statusUpsertCount(host: host) == 0)

    // 잠자기 자동 마감도 여전히 막힌다(D2 의 본래 계약). 큐가 곧 서버 쓰기다.
    let sleepAt = Date()
    store.handleSleep(at: sleepAt)
    store.handleWake(at: sleepAt.addingTimeInterval(10 * 60))
    #expect(store.pendingItems.isEmpty)
    #expect(store.startedAt == sessionStart)
    #expect(store.snapshot.isWorking)
    #expect(URLProtocolStub.requests(forHost: host).isEmpty)
}

@MainActor
@Test
func adoptedSessionSwapResetsPresenceTracking() {
    // 세션이 바뀌면 관측을 처음부터 다시 해야 한다. 직전 세션의 신호를 새 세션의 '전진 없음' 근거로
    // 재활용하면, 방금 다른 맥이 연 멀쩡한 세션을 첫 폴링에 곧바로 가로챈다.
    let host = "adoption-tracking-reset-on-swap"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let oldSeen = Date().addingTimeInterval(-30 * 60)
    let firstSession = "e0000000-0000-0000-0000-000000000001"
    store.teamMembers = [
        workingMember(
            userID: userID,
            startedAt: Date().addingTimeInterval(-6 * 3_600),
            sessionID: firstSession,
            lastSeenAt: oldSeen
        )
    ]
    // 두 번 관측해 '전진 없는 아주 낡은 신호'를 장부에 남긴다.
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    store.adoptedLastSeenSessionID = firstSession
    store.adoptedLastSeenAt = oldSeen

    // 다른 맥이 방금 새 세션을 열었다(신호는 신선). 재흡수 직후 첫 관측이므로 주장하지 않아야 한다.
    let newSession = "e0000000-0000-0000-0000-000000000002"
    let freshStart = Date().addingTimeInterval(-60)
    store.teamMembers = [
        workingMember(userID: userID, startedAt: freshStart, sessionID: newSession, lastSeenAt: Date())
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

    #expect(store.currentSessionID == newSession)
    #expect(store.adoptedRemoteSession)
    #expect(store.adoptedLastSeenSessionID == newSession)
}

// MARK: - 되돌리기 재개도 소유권 주장이다

@MainActor
@Test
func undoAutoCloseClaimsOwnedSessionID() async {
    // 자리 비움 되돌리기는 사용자가 직접 reopen 을 보낸 것이라 명백한 소유권 주장이다. 소유 ID 를
    // 남기지 않으면 재개 직후 앱이 재시작될 때 그 세션이 다시 '남의 것'으로 판정돼 하트비트가 끊긴다.
    let host = "undo-claims-owned-id"
    let store = makeOwnershipStubStore(host: host)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let closedSessionID = "f0000000-0000-0000-0000-000000000001"
    let closedStart = Date().addingTimeInterval(-2 * 3_600)
    store.lastAutoClosedSessionID = closedSessionID
    store.lastAutoClosedStartedAt = closedStart
    store.lastAutoClosedAt = Date()
    store.lastAutoClosedSeconds = 0

    await store.performUndoAutoClose()

    #expect(store.startedAt == closedStart)
    #expect(!store.adoptedRemoteSession)
    #expect(store.ownedWorkSessionID == closedSessionID)
}

// MARK: - v0.2.16 차단 1: UUID 대소문자 왕복 (Swift 대문자 ↔ Postgres uuid 소문자)
//
// 위 스위트가 이 축을 통째로 놓쳤던 이유는 픽스처가 소유 ID 와 activeSessionID 에 **같은 리터럴 소문자
// 문자열**을 썼기 때문이다. 실제 프로덕션은 앱이 UUID().uuidString(대문자)을 만들어 보내고, Postgres 의
// uuid 네이티브 컬럼이 **소문자**로 돌려준다. 아래 테스트들은 반드시 진짜 UUID 를 만들고 서버 쪽 값만
// .lowercased() 해 그 왕복을 모사한다 — 리터럴을 다시 쓰면 검증이 통째로 공허해진다.

@MainActor
@Test
func swiftUUIDIsUppercaseAndCanonicalizationClosesTheGap() {
    // 전제 확인: 이 축이 실재한다는 것을 코드로 못 박는다. Swift 의 UUID().uuidString 은 대문자다.
    let clientID = UUID().uuidString
    #expect(clientID == clientID.uppercased())
    #expect(clientID != clientID.lowercased())
    // 정규화는 한 곳(canonicalSessionID)에만 있고, 왕복한 두 표현을 같은 값으로 만든다.
    #expect(WorkTimerStore.canonicalSessionID(clientID) == WorkTimerStore.canonicalSessionID(clientID.lowercased()))
    #expect(WorkTimerStore.canonicalSessionID(nil) == nil)
}

@MainActor
@Test
func startGeneratesAlreadyCanonicalSessionID() {
    // 생성 지점에서 정규화한다 — 그래야 서버에 저장되는 값과 로컬 값의 표현이 처음부터 같다.
    let host = "canonical-start-id"
    let store = makeOwnershipStubStore(host: host)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    store.start()
    let sessionID = store.currentSessionID
    #expect(sessionID == sessionID?.lowercased())
    #expect(store.ownedWorkSessionID == sessionID)
    // 큐에 실려 서버로 나가는 값도 같은 표현이어야 한다(서버가 그대로 돌려줄 값이므로).
    #expect(store.pendingItems.first?.sessionID == sessionID)
}

@MainActor
@Test
func restartWithUppercasePersistedIDKeepsOwnershipAcrossPostgresRoundTrip() async {
    // **차단 1 / 재시작 경로.** 이전 실행이 대문자로 영속해 둔 소유 ID(v0.2.15 이하가 남긴 그 값) +
    // 소문자로 돌아온 서버 응답. 정규화가 없으면 1차 판정이 실패해 재시작한 내 세션이 흡수로 떨어지고
    // 하트비트가 영구 정지한다(10분 뒤 내 앱 자신의 스캐빈저가 내 살아 있는 세션을 마감).
    let host = "restart-uppercase-roundtrip"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let clientID = UUID().uuidString              // 이전 실행의 start() 가 만든 그 값(대문자)
    let serverID = clientID.lowercased()          // work_statuses.active_session_id 가 돌려주는 값
    #expect(clientID != serverID)
    store.setOwnedWorkSessionID(clientID)

    let sessionStart = Date().addingTimeInterval(-3 * 3_600)
    store.teamMembers = [
        workingMember(
            userID: userID,
            startedAt: sessionStart,
            sessionID: serverID,
            lastSeenAt: Date().addingTimeInterval(-20)
        )
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

    #expect(!store.adoptedRemoteSession)
    #expect(store.startedAt == sessionStart)
    #expect(store.currentSessionID == serverID)

    await store.sendHeartbeatIfWorking()
    #expect(statusUpsertCount(host: host) == 1)
    let bodies = zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
        .filter { $0.0.url?.path == "/rest/v1/work_statuses" && $0.0.httpMethod == "POST" }
        .map { $0.1 }
    #expect(bodies.first?.contains(#""active_session_id":"\#(serverID)""#) == true)
}

@MainActor
@Test
func firstPollAfterStartKeepsOwnSessionOwned() async {
    // **차단 1 의 진짜 피해 경로.** 재시작이 아니라 그냥 근무 중이다. 30초 뒤 첫 폴링에서 서버가 내 세션을
    // 소문자로 돌려주면, 원시 비교 시절엔 재흡수 분기의 'serverSessionID != currentSessionID' 가
    // **항상 참**이라 내 세션이 내 앱에서 남의 것으로 뒤집혔다 → 하트비트 정지 → 그 창에서 뚜껑을 5분 넘게
    // 닫거나 앱을 끄면 마감이 못 나가고 스캐빈저가 시작 시각으로 마감(= 그 근무가 0초로 기록).
    let host = "first-poll-after-start"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let t0 = Date().addingTimeInterval(-60)
    store.start(now: t0)
    let clientID = store.currentSessionID!
    // 시작 큐를 드레인해야 applyRemoteOwnStatus 가 (pendingItems 가드를 지나) 실제로 판정을 수행한다.
    await store.syncTask?.value

    let before = statusUpsertCount(host: host)
    store.teamMembers = [
        workingMember(userID: userID, startedAt: t0, sessionID: clientID.lowercased(), lastSeenAt: Date())
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

    #expect(!store.adoptedRemoteSession)
    #expect(store.startedAt == t0)
    #expect(store.ownedWorkSessionID == clientID.lowercased())

    await store.sendHeartbeatIfWorking()
    #expect(statusUpsertCount(host: host) - before == 1)
}

// MARK: - v0.2.16 차단 2: 백스톱 임계는 이 앱 자신의 계약(잠자기 5분 유예) 위에 있어야 한다

@MainActor
@Test
func reclaimThresholdIsDerivedFromSleepGraceAndStaysAheadOfScavenger() {
    // 임계를 상수에서 파생시킨 이유를 고정한다. 한쪽만 바뀌면 (1) 살아 있는 맥의 정상 잠자기를 방치로
    // 오판하거나 (2) 스캐빈저(10분)보다 늦어 되찾기 자체가 무의미해진다.
    // 하한: 잠자기 유예 5분 + 하트비트 앞뒤 2주기 = 정상 복귀 시 최대 신호 공백 ~6분
    // (20260712120000_auto_close_stale_sessions.sql 의 임계 10분 근거와 같은 계산).
    let normalMaxGap = WorkTimerStore.sleepGraceSeconds + 2 * WorkTimerStore.heartbeatIntervalSeconds
    #expect(WorkTimerStore.adoptedReclaimStaleSeconds > normalMaxGap)
    // 상한: 최악 노출(임계 + 관측 1주기)이 클라 스캐빈저/서버 cron 의 10분보다 앞서야 한다.
    #expect(
        WorkTimerStore.adoptedReclaimStaleSeconds + WorkTimerStore.heartbeatIntervalSeconds
            < WorkTimerStore.abandonedSessionThresholdSeconds
    )
    // 옛 임계(표시용 stale 90초)를 그대로 쓰면 위 하한을 못 넘는다 — 회귀 방지로 못 박는다.
    #expect(WorkTimerStore.adoptedReclaimStaleSeconds > TeamMemberStatus.stalePresenceSeconds)
}

@MainActor
@Test
func ownerMacTakingThreeMinuteNapKeepsItsSession() {
    // **차단 2.** 맥 A 는 살아 있다 — 뚜껑을 3분 닫은 것뿐이고, 이 앱의 계약상 5분 이하 잠자기는 근무
    // 연속으로 인정된다(sleepGraceSeconds). 그동안 하트비트만 멈춘다. 옛 임계(90초)에선 맥 B 가 +100초에
    // 소유권을 뺏었고, 그 뒤 B 의 잠자기 자동 마감이 A 의 **살아 있는** 세션을 B 의 덮은 시각으로 잘랐다.
    let host = "owner-three-minute-nap"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let t0 = Date()
    let sessionStart = t0.addingTimeInterval(-4 * 3_600)
    let sessionID = UUID().uuidString.lowercased()

    // 폴링 1~2: A 가 정상 하트비트 중이라 신호가 전진한다 → 흡수 상태로 자리 잡는다.
    for index in 0..<2 {
        let now = t0.addingTimeInterval(Double(index) * 30)
        store.teamMembers = [
            workingMember(userID: userID, startedAt: sessionStart, sessionID: sessionID, lastSeenAt: now.addingTimeInterval(-10))
        ]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    }
    #expect(store.adoptedRemoteSession)

    // A 가 뚜껑을 3분(=180초) 닫는다. 그 사이 신호는 완전히 동결된다.
    let frozen = t0.addingTimeInterval(20)
    let napBegan = t0.addingTimeInterval(60)
    for step in 1...6 {
        let now = napBegan.addingTimeInterval(Double(step) * 30)
        store.updateAdoptedPresenceTracking(
            workingMember(userID: userID, startedAt: sessionStart, sessionID: sessionID, lastSeenAt: frozen),
            now: now
        )
        #expect(store.adoptedRemoteSession, "낮잠 \(Int(now.timeIntervalSince(frozen)))초 만에 A 의 세션을 가로챘다")
    }

    // 소유 ID 도 세우지 않는다 — 세우면 이 맥이 다음 재시작에서 남의 세션을 자기 것이라 우긴다.
    #expect(store.ownedWorkSessionID == nil)

    // A 가 깨어나 하트비트를 재개하면 장부는 완전히 되돌아가야 한다(정체를 누적으로 세면 '가끔 밀리는'
    // 정상 맥도 결국 임계에 닿는다).
    let wokeAt = napBegan.addingTimeInterval(190)
    store.updateAdoptedPresenceTracking(
        workingMember(userID: userID, startedAt: sessionStart, sessionID: sessionID, lastSeenAt: wokeAt),
        now: wokeAt
    )
    #expect(store.adoptedStallObservations == 0)
    #expect(store.adoptedStallBeganAt == nil)
    #expect(store.adoptedRemoteSession)
}

@MainActor
@Test
func vanishedOwnerMacIsReclaimedBeforeScavengerDeadline() async throws {
    // 반대편 성질: 소유 맥이 **정말로** 사라지면(전원 차단·크래시) 그 세션은 아무도 못 닫는 채 방치된다.
    // 되찾기는 반드시 일어나되, (1) 잠자기 유예 계약보다는 늦고 (2) 10분 스캐빈저보다는 앞서야 한다.
    let host = "vanished-owner-reclaim"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let t0 = Date()
    let sessionStart = t0.addingTimeInterval(-4 * 3_600)
    let sessionID = UUID().uuidString.lowercased()
    let lastSignal = t0.addingTimeInterval(-10)   // A 의 마지막 하트비트
    store.teamMembers = [
        workingMember(userID: userID, startedAt: sessionStart, sessionID: sessionID, lastSeenAt: lastSignal)
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    #expect(store.adoptedRemoteSession)

    // 30초 주기로 계속 폴링한다. 신호는 영영 전진하지 않는다.
    var reclaimedAfter: TimeInterval?
    for step in 1...30 {
        let now = t0.addingTimeInterval(Double(step) * 30)
        store.updateAdoptedPresenceTracking(store.teamMembers[0], now: now)
        if !store.adoptedRemoteSession {
            reclaimedAfter = now.timeIntervalSince(lastSignal)
            break
        }
    }

    let elapsed = try #require(reclaimedAfter)
    // (1) 정상 근무로 인정되는 신호 공백(잠자기 5분 유예 + 하트비트 앞뒤 1주기씩)보다는 뒤여야 한다.
    #expect(elapsed > WorkTimerStore.sleepGraceSeconds + 2 * WorkTimerStore.heartbeatIntervalSeconds)
    // (2) 10분 스캐빈저보다는 앞서야 한다 — 늦으면 되찾기 전에 서버가 내 세션을 마감해 버린다.
    #expect(elapsed < WorkTimerStore.abandonedSessionThresholdSeconds)
    #expect(store.ownedWorkSessionID == sessionID)
    #expect(store.startedAt == sessionStart)

    // 되찾았으면 하트비트가 즉시 재개돼야 한다(안 그러면 되찾은 의미가 없다).
    await store.sendHeartbeatIfWorking()
    #expect(statusUpsertCount(host: host) == 1)
}

@MainActor
@Test
func clockSkewWithOneMissedAdvanceDoesNotClaim() {
    // last_seen_at 은 **상대가 자기 시계로** 쓴다(SupabaseWorkService.upsertStatus — DB 기본값/트리거가
    // 덮어 주지 않는다). 그런데 나이는 내 시계로 잰다. 두 맥의 시계가 2분 어긋나 있으면 나이는 처음부터
    // 임계를 넘긴 것처럼 보이므로, 하트비트가 딱 한 번 밀리는 순간 곧바로 주장이 성립해선 안 된다.
    let host = "clock-skew-one-miss"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let t0 = Date()
    let sessionStart = t0.addingTimeInterval(-4 * 3_600)
    let sessionID = UUID().uuidString.lowercased()
    let skew: TimeInterval = 8 * 60   // A 의 시계가 8분 느리다 → 나이는 늘 임계(7분)를 넘는다

    var seen = t0.addingTimeInterval(-skew)
    store.teamMembers = [
        workingMember(userID: userID, startedAt: sessionStart, sessionID: sessionID, lastSeenAt: seen)
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    #expect(store.adoptedRemoteSession)

    // A 는 살아 있어 값이 매 폴링 전진한다 — 딱 한 번(index 3)만 재시도 실패로 밀린다.
    for index in 1...20 {
        let now = t0.addingTimeInterval(Double(index) * 30)
        if index != 3 { seen = now.addingTimeInterval(-skew) }
        store.updateAdoptedPresenceTracking(
            workingMember(userID: userID, startedAt: sessionStart, sessionID: sessionID, lastSeenAt: seen),
            now: now
        )
        #expect(store.adoptedRemoteSession, "폴링 \(index)(시계 어긋남 \(Int(skew))초)에서 소유권을 가로챘다")
    }
    #expect(store.ownedWorkSessionID == nil)
}

// MARK: - v0.2.17: 오판 자가정정(릴리스 규칙)을 시각 비교에서 **기기 신원**으로 옮긴다
//
// 옛 규칙("서버의 last_seen_at 이 내 마지막 하트비트보다 60초 앞서면 남이 쓰는 것")은 구조적으로 죽어 있었다:
// 폴링 루프가 하트비트 → 상태 읽기 순서라 내가 읽는 값은 언제나 1초 전 내가 쓴 내 값이고(실측
// seen−mine = [-0.89, -0.89, -0.90]), 발화하려면 상대 시계가 내 앞에 있어야 했다 — 시계가 맞을수록 죽는
// 규칙이라 방향이 거꾸로였다. 더 근본적으로, 내가 매 폴링 직전에 덮어쓰므로 **공유 셀의 시각만으로는
// 다른 인스턴스의 존재를 원리적으로 관측할 수 없다.** 그래서 기기마다 자기 행을 쓰게 하고(work_status_devices),
// "신선하게 전진하는 남의 주장"만을 반납의 증거로 삼는다. 그 **부재는 아무것도 증명하지 않는다**.

/// 남의 맥이 남긴 소유 주장 한 줄.
private func foreignClaim(deviceID: String, sessionID: String?, lastSeenAt: Date) -> StatusDeviceClaim {
    StatusDeviceClaim(deviceID: deviceID, sessionID: sessionID, lastSeenAt: lastSeenAt)
}

@MainActor
@Test
func ownershipIsReleasedWhenAnotherDeviceClaimsSameSession() async throws {
    // 백스톱은 소유권을 **세우는** 방향뿐이라 한 번 틀리면 되돌릴 길이 없었다(남의 세션 ID 가 내 소유 ID 로
    // 영속돼 재시작해도 그대로 굳는다). 대칭 규칙: 같은 세션에 **다른 기기**의 주장이 폴링 사이에 전진하면
    // 그 맥이 지금 살아서 쓰고 있다는 사실이므로 소유권을 내려놓는다.
    let host = "release-on-foreign-device"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    // 타이브레이크에서 **내가 지는** 배치(상대 기기 ID 가 사전식으로 작다). 반대 배치는 아래 대조군이 고정한다.
    store.deviceID = "MAC-B-ZZZZ"
    let otherDevice = "MAC-A-AAAA"

    // 재시작 복구로 소유권을 확정한 상태(대문자 영속 + 소문자 서버 응답 — 실제 왕복 그대로).
    let clientID = UUID().uuidString
    let serverID = clientID.lowercased()
    let sessionStart = Date().addingTimeInterval(-2 * 3_600)
    store.setOwnedWorkSessionID(clientID)
    let t0 = Date()
    store.teamMembers = [
        workingMember(
            userID: userID,
            startedAt: sessionStart,
            sessionID: serverID,
            lastSeenAt: t0.addingTimeInterval(-15),
            deviceClaims: [foreignClaim(deviceID: otherDevice, sessionID: serverID, lastSeenAt: t0.addingTimeInterval(-15))]
        )
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    // 첫 관측은 증거가 아니다(그 행은 몇 시간 전 죽은 맥의 화석일 수 있다) — 아직 소유를 유지한다.
    #expect(!store.adoptedRemoteSession)

    await store.sendHeartbeatIfWorking()
    let upsertsAfterHeartbeat = statusUpsertCount(host: host)
    #expect(upsertsAfterHeartbeat == 1)

    // 다음 폴링: 그 기기의 주장이 **전진했다** = 지금 살아서 같은 세션을 쓰고 있다.
    store.teamMembers = [
        workingMember(
            userID: userID,
            startedAt: sessionStart,
            sessionID: serverID,
            lastSeenAt: t0.addingTimeInterval(15),
            deviceClaims: [foreignClaim(deviceID: otherDevice, sessionID: serverID, lastSeenAt: t0.addingTimeInterval(15))]
        )
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

    // 소유권을 내려놓고 흡수 상태로 되돌아간다 — 소유자 2 상태를 두면 서로의 신호를 갱신해 스캐빈저가
    // 영영 발화하지 못하고, 한쪽의 잠자기가 다른 쪽의 살아 있는 근무를 과거 시각으로 마감한다.
    #expect(store.adoptedRemoteSession)
    #expect(store.ownedWorkSessionID == nil)
    #expect(store.startedAt == sessionStart)     // 근무 자체는 계속 흐른다(화면이 꺼지지 않는다)

    // 반납했으므로 이 맥은 더 이상 그 세션에 아무 말도 하지 않는다(상태 upsert 도, 기기 주장도).
    await store.sendHeartbeatIfWorking()
    #expect(statusUpsertCount(host: host) == upsertsAfterHeartbeat)
    #expect(deviceClaimCount(host: host) == 1)
}

@MainActor
@Test
func ownershipSurvivesMyOwnDeviceEcho() async throws {
    // **릴리스 규칙의 대조군이자 가장 위험한 오발화 지점.** 서버가 돌려주는 행은 평소 **내가 방금 쓴 것**이다.
    // 내 기기 행의 전진을 '남의 주장'으로 오인하면 모든 정상 근무가 매 폴링 소유권을 반납해 하트비트가 죽는다
    // (= 결함을 고치려다 전원에게 더 큰 사고를 내는 경로). 시각을 넣든 기기를 넣든 셀 하나를 나눠 쓰면
    // 관측자는 늘 자기 값을 되읽는다는 사실이 바로 이 테스트가 못 박는 것이다.
    let host = "release-ignores-own-device-echo"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    store.start()
    await store.syncTask?.value
    let sessionID = try #require(store.currentSessionID)
    let sessionStart = try #require(store.startedAt)
    let t0 = Date()

    for index in 0..<10 {
        await store.sendHeartbeatIfWorking()
        // 서버는 내 기기 행을 그대로(내가 방금 쓴 값 그대로) 돌려준다 — 폴링마다 전진한다.
        let echo = t0.addingTimeInterval(Double(index) * 30)
        store.teamMembers = [
            workingMember(
                userID: userID,
                startedAt: sessionStart,
                sessionID: sessionID,
                lastSeenAt: echo,
                deviceClaims: [foreignClaim(deviceID: store.deviceID, sessionID: sessionID, lastSeenAt: echo)]
            )
        ]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
        #expect(!store.adoptedRemoteSession, "폴링 \(index) 에서 내 기기 행의 메아리를 남의 주장으로 오인했다")
    }
    #expect(store.ownedWorkSessionID == sessionID)
}

@MainActor
@Test
func releaseRuleIsInertWhenNobodyClaimsTheSession() {
    // **혼합 함대 안전판.** 이 표를 모르는 맥(v0.2.10~v0.2.16)은 행을 만들지 않는다 — 그 침묵을 '다른 맥 없음'
    // 으로 승격시키면 안 된다. 기기 행이 하나도 없으면 판정은 '불가'이고 소유권은 기존 백스톱(7분)에 맡긴다.
    // 서버의 last_seen_at 이 아무리 앞서 보여도(시계 어긋남) 그것만으로는 절대 반납하지 않는다.
    let host = "release-inert-without-claims"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let clientID = UUID().uuidString
    let sessionStart = Date().addingTimeInterval(-3_600)
    store.setOwnedWorkSessionID(clientID)
    for index in 0..<5 {
        store.teamMembers = [
            workingMember(
                userID: userID,
                startedAt: sessionStart,
                sessionID: clientID.lowercased(),
                // 상대 시계가 10분 앞선 것처럼 보이는 값. 옛 규칙이라면 이 하나로 반납했다.
                lastSeenAt: Date().addingTimeInterval(600 + Double(index) * 30)
            )
        ]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
        #expect(!store.adoptedRemoteSession, "폴링 \(index): 기기 주장이 없는데 소유권을 내려놨다")
    }
    #expect(store.ownedWorkSessionID == clientID.lowercased())
}

@MainActor
@Test
func firstObservationOfForeignDeviceIsNotEvidence() {
    // 첫 관측은 증거가 아니다 — 그 행은 어제 죽은 맥이 남긴 화석일 수 있다. '전진'을 봐야 지금 살아 있다는
    // 사실이 성립한다. 값이 굳어 있는 동안에는 몇 번을 관측해도 반납하지 않는다.
    let host = "release-needs-advance"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    store.deviceID = "MAC-B-ZZZZ"

    let clientID = UUID().uuidString
    let sessionStart = Date().addingTimeInterval(-3_600)
    // 몇 시간 전에 멈춘 화석 주장(사전식으로는 내가 지는 배치라 '전진만 하면' 반납할 조건이다).
    let fossil = Date().addingTimeInterval(-4 * 3_600)
    store.setOwnedWorkSessionID(clientID)
    for index in 0..<5 {
        store.teamMembers = [
            workingMember(
                userID: userID,
                startedAt: sessionStart,
                sessionID: clientID.lowercased(),
                lastSeenAt: Date(),
                deviceClaims: [
                    foreignClaim(deviceID: "MAC-A-AAAA", sessionID: clientID.lowercased(), lastSeenAt: fossil)
                ]
            )
        ]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
        #expect(!store.adoptedRemoteSession, "폴링 \(index): 전진하지 않는 화석 주장에 소유권을 내려놨다")
    }
    #expect(store.ownedWorkSessionID == clientID.lowercased())
}

@MainActor
@Test
func foreignDeviceClaimingAnotherSessionDoesNotRelease() {
    // 맥 간 정상 인수인계: A 가 근무를 끝내고 B 가 **새 세션**을 열었다. A 의 기기 행에는 옛 세션 ID 가
    // 남아 있고 A 가 잠깐 더 갱신할 수도 있다. 세션 ID 를 보지 않으면 B 가 방금 연 자기 세션을 남의 것으로
    // 오인해 즉시 반납한다 — 그러면 아무도 하트비트를 보내지 않아 새 근무가 10분 뒤 스캐빈저에 마감된다.
    let host = "release-scoped-to-my-session"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    store.deviceID = "MAC-B-ZZZZ"

    let mySession = UUID().uuidString.lowercased()
    let otherSession = UUID().uuidString.lowercased()
    let sessionStart = Date().addingTimeInterval(-600)
    store.setOwnedWorkSessionID(mySession)
    let t0 = Date()
    for index in 0..<4 {
        // A 의 주장은 매 폴링 전진하지만, 그것은 **다른 세션**에 대한 것이다.
        let advancing = t0.addingTimeInterval(Double(index) * 30)
        store.teamMembers = [
            workingMember(
                userID: userID,
                startedAt: sessionStart,
                sessionID: mySession,
                lastSeenAt: advancing,
                deviceClaims: [foreignClaim(deviceID: "MAC-A-AAAA", sessionID: otherSession, lastSeenAt: advancing)]
            )
        ]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
        #expect(!store.adoptedRemoteSession, "폴링 \(index): 남의 **다른** 세션 주장에 내 세션을 반납했다")
    }
    #expect(store.ownedWorkSessionID == mySession)
}

@MainActor
@Test
func lexicographicTiebreakLetsExactlyOneSideBackDown() {
    // 타이브레이크가 없으면 양쪽이 서로를 보고 **동시에** 반납한다 → 아무도 하트비트를 안 보내고, 7분 뒤
    // 양쪽이 동시에 재주장하는 7.5분 주기 발진이 생긴다(그 사이 진짜 소유 맥도 흡수라 자기 잠자기 마감조차
    // 못 건다). 사전식 비교는 자의적이지만 결정적·대칭이라 정확히 한쪽만 물러난다.
    // 여기서는 **내가 이기는** 배치다(내 기기 ID 가 더 작다) → 상대의 전진을 봐도 내가 소유를 유지한다.
    let host = "release-tiebreak-winner"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    store.deviceID = "MAC-A-AAAA"

    let sessionID = UUID().uuidString.lowercased()
    let sessionStart = Date().addingTimeInterval(-3_600)
    store.setOwnedWorkSessionID(sessionID)
    let t0 = Date()
    for index in 0..<5 {
        let advancing = t0.addingTimeInterval(Double(index) * 30)
        store.teamMembers = [
            workingMember(
                userID: userID,
                startedAt: sessionStart,
                sessionID: sessionID,
                lastSeenAt: advancing,
                deviceClaims: [foreignClaim(deviceID: "MAC-B-ZZZZ", sessionID: sessionID, lastSeenAt: advancing)]
            )
        ]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
        #expect(!store.adoptedRemoteSession, "폴링 \(index): 양쪽이 동시에 물러나면 아무도 세션을 돌보지 않는다")
    }
    #expect(store.ownedWorkSessionID == sessionID)
}

// MARK: - v0.2.18: 반납의 결정자를 사전식 동전 던지기에서 **주장 강도**로 옮긴다
//
// 직전 라운드의 반납 규칙은 마지막 한 줄이 `claim.deviceID < deviceID` 였다. 그 비교는 "누가 진짜 세션을
// 열었는가"를 전혀 보지 않는데, deviceID 는 랜덤 UUID 라 두 배치가 정확히 50:50 이다:
//   정방향(진짜 소유자 ID 가 작음) → 오판한 맥이 물러난다 ✅
//   역방향(진짜 소유자 ID 가 큼)   → **진짜 소유자가 물러난다** → 그 뒤 오판한 맥이 뚜껑을 6분 닫으면
//      살아 있는 세션이 마감되고, 진짜 소유자의 수동 [근무 종료]는 ended_at=is.null 필터가 0행이라
//      PATCH 도 못 하고 폴백 POST 는 ignore-duplicates 로 버려져 **마감 기록이 0건**이 된다(v0.2.16 사고 재현).
// 소유는 두 출처로만 생긴다: start()/되돌리기 재개가 세운 **강한 소유**(사실)와 백스톱이 세운 **약한 소유**
// (추측). work_sessions_one_open_per_user 부분 유니크상 강한 소유자는 최대 한 명이므로 "약한 쪽이 강한 쪽에게
// 물러난다"가 항상 진짜 소유자를 남긴다. 아래 네 배치가 **배치와 무관함**을 못 박는다.

/// 같은 세션을 두 맥이 주장하는 대치 상황을 한 번 굴린다(첫 폴링 = 관측 seed, 둘째 폴링 = 상대 주장 전진).
/// 강/약과 기기 ID 사전식 순서만 인자로 바꾼다 — 기대 결과가 배치에 흔들리지 않는지를 보기 위함이다.
@MainActor
private func runOwnershipStandoff(
    host: String,
    myDeviceID: String,
    foreignDeviceID: String,
    mineIsStrong: Bool,
    theirsIsStrong: Bool
) -> WorkTimerStore {
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    store.deviceID = myDeviceID

    // 재시작 복구로 소유를 확정한 상태(대문자 영속 + 소문자 서버 응답 — 실제 왕복 그대로).
    let clientID = UUID().uuidString
    let serverID = clientID.lowercased()
    let sessionStart = Date().addingTimeInterval(-2 * 3_600)
    store.setOwnedWorkSessionID(clientID, strength: mineIsStrong ? .strong : .weak)

    let t0 = Date()
    func poll(_ claimSeen: Date) {
        store.teamMembers = [
            workingMember(
                userID: userID,
                startedAt: sessionStart,
                sessionID: serverID,
                lastSeenAt: claimSeen,
                deviceClaims: [
                    StatusDeviceClaim(
                        deviceID: foreignDeviceID,
                        sessionID: serverID,
                        lastSeenAt: claimSeen,
                        openedSession: theirsIsStrong
                    )
                ]
            )
        ]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    }
    // 첫 관측은 증거가 아니다(화석일 수 있다) → 값만 적힌다. 둘째 폴링에서 전진 = 상대가 지금 살아 있다.
    poll(t0.addingTimeInterval(-15))
    poll(t0.addingTimeInterval(15))
    return store
}

@MainActor
@Test
func weakClaimYieldsToTheStrongOwnerInTheReverseArrangement() async {
    // **이번 라운드의 핵심 단언.** 진짜 소유자(강함)의 기기 ID 가 사전식으로 **큰** 쪽이다 —
    // 옛 규칙이라면 진짜 소유자가 물러나고 오판한 이 맥이 세션을 차지했다. 이제는 오판한 쪽(나)이 물러난다.
    let store = runOwnershipStandoff(
        host: "standoff-weak-lex-winner",
        myDeviceID: "MAC-A-AAAA",        // 사전식으로 내가 이기는 배치
        foreignDeviceID: "MAC-B-ZZZZ",   // 그런데 세션을 실제로 연 것은 저쪽이다
        mineIsStrong: false,
        theirsIsStrong: true
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    #expect(store.adoptedRemoteSession, "추측으로 세운 소유가 진짜 소유자를 밀어냈다(= v0.2.16 사고 재현)")
    #expect(store.ownedWorkSessionID == nil)
    #expect(store.startedAt != nil)   // 근무 표시 자체는 미러링으로 계속 흐른다
}

@MainActor
@Test
func weakClaimYieldsToTheStrongOwnerInTheForwardArrangementToo() async {
    // 정방향(진짜 소유자 ID 가 작다). 옛 규칙에서도 우연히 맞던 배치 — 결과가 **배치와 무관**함을 못 박는다.
    let store = runOwnershipStandoff(
        host: "standoff-weak-lex-loser",
        myDeviceID: "MAC-B-ZZZZ",
        foreignDeviceID: "MAC-A-AAAA",
        mineIsStrong: false,
        theirsIsStrong: true
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    #expect(store.adoptedRemoteSession)
    #expect(store.ownedWorkSessionID == nil)
}

@MainActor
@Test
func strongOwnerHoldsAgainstAWeakClaimEvenWhenLexicographicallyLosing() async {
    // 같은 사고를 **진짜 소유자 쪽에서** 본다. 내 기기 ID 가 사전식으로 커서 옛 규칙이라면 내가 물러났고,
    // 그 뒤 내 근무는 통째로 유실됐다. 이제는 내가 세션을 열었다는 사실이 이긴다.
    let store = runOwnershipStandoff(
        host: "standoff-strong-lex-loser",
        myDeviceID: "MAC-B-ZZZZ",
        foreignDeviceID: "MAC-A-AAAA",
        mineIsStrong: true,
        theirsIsStrong: false
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    #expect(!store.adoptedRemoteSession, "진짜 소유자가 추측 앞에서 물러났다 — 그 뒤 근무가 전부 유실된다")
    #expect(store.ownedWorkSessionID != nil)
    #expect(store.ownsCurrentSessionStrongly)
}

@MainActor
@Test
func strongOwnerHoldsAgainstAWeakClaimInTheForwardArrangementToo() async {
    let store = runOwnershipStandoff(
        host: "standoff-strong-lex-winner",
        myDeviceID: "MAC-A-AAAA",
        foreignDeviceID: "MAC-B-ZZZZ",
        mineIsStrong: true,
        theirsIsStrong: false
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    #expect(!store.adoptedRemoteSession)
    #expect(store.ownsCurrentSessionStrongly)
}

@MainActor
@Test
func twoWeakClaimsStillFallBackToTheLexicographicTiebreak() async {
    // 강/약이 같으면(둘 다 추측 — 예: 두 맥이 모두 백스톱으로 되찾은 경우) 판별할 사실이 없다. 그때만
    // 사전식으로 대칭을 깬다. 이 폴백이 없으면 양쪽이 동시에 반납해 아무도 세션을 돌보지 않고,
    // 7분 뒤 양쪽이 동시에 재주장하는 7.5분 주기 발진이 생긴다.
    let loser = runOwnershipStandoff(
        host: "standoff-both-weak-loser",
        myDeviceID: "MAC-B-ZZZZ",
        foreignDeviceID: "MAC-A-AAAA",
        mineIsStrong: false,
        theirsIsStrong: false
    )
    let winner = runOwnershipStandoff(
        host: "standoff-both-weak-winner",
        myDeviceID: "MAC-A-AAAA",
        foreignDeviceID: "MAC-B-ZZZZ",
        mineIsStrong: false,
        theirsIsStrong: false
    )
    defer {
        for store in [loser, winner] {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
            store.syncTask?.cancel()
        }
    }

    // 정확히 한쪽만 물러난다(양쪽 반납도, 양쪽 유지도 아니다).
    #expect(loser.adoptedRemoteSession)
    #expect(!winner.adoptedRemoteSession)
}

@MainActor
@Test
func startClaimsStronglyAndBackstopClaimsWeakly() async throws {
    // 강/약의 **출처**를 못 박는다. start() 는 이 맥이 서버에 세션을 만든 것이라 사실(강함)이고,
    // 백스톱의 되찾기는 '아무도 안 돌보는 것 같다'는 추측(약함)이다. 이 구분이 무너지면 반납 규칙 전체가
    // 다시 동전 던지기로 돌아간다.
    let host = "claim-strength-origin"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    store.start()
    await store.syncTask?.value
    #expect(store.ownedSessionClaimStrength == .strong)
    #expect(store.ownsCurrentSessionStrongly)

    // 하트비트가 그 사실을 실어 보내야 상대 맥이 판정할 수 있다.
    await store.sendHeartbeatIfWorking()
    // GET(팀 폴링)이 아니라 **쓰기**만 본다 — GET 은 본문이 비어 있어 필터를 빠뜨리면 늘 빈 문자열을 잡는다.
    let strongBody = try #require(
        zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
            .first { $0.0.url?.path == "/rest/v1/work_status_devices" && $0.0.httpMethod == "POST" }?.1
    )
    #expect(strongBody.contains(#""opened_session":true"#))

    // 이제 백스톱 경로. 다른 맥이 연 세션을 흡수한 뒤 신호가 굳어 7분이 지나 되찾는다.
    store.stop()
    await store.syncTask?.value
    let t0 = Date()
    let foreignSession = UUID().uuidString.lowercased()
    let frozen = t0.addingTimeInterval(-10)
    store.teamMembers = [
        workingMember(userID: userID, startedAt: t0.addingTimeInterval(-3_600), sessionID: foreignSession, lastSeenAt: frozen)
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    #expect(store.adoptedRemoteSession)
    for step in 1...6 {
        store.updateAdoptedPresenceTracking(
            store.teamMembers[0],
            now: t0.addingTimeInterval(Double(step) * 120)
        )
    }
    #expect(!store.adoptedRemoteSession, "백스톱이 되찾지 못했다면 아래 강도 단언이 공허해진다")
    #expect(store.ownedSessionClaimStrength == .weak)
    #expect(!store.ownsCurrentSessionStrongly)

    let before = URLProtocolStub.requests(forHost: host).count
    await store.sendHeartbeatIfWorking()
    let weakBody = try #require(
        zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
            .dropFirst(before)
            .first { $0.0.url?.path == "/rest/v1/work_status_devices" && $0.0.httpMethod == "POST" }?.1
    )
    #expect(weakBody.contains(#""opened_session":false"#))
}

@MainActor
@Test
func restartDoesNotLaunderAWeakClaimIntoAStrongOne() async {
    // **세탁 경로 차단.** 백스톱이 추측으로 세운 소유 ID 는 재시작을 넘어 살아남는다(그래야 되찾은 세션의
    // 하트비트가 재시작 후에도 이어진다). 그런데 재시작 복구의 1차 판정이 그것을 무조건 '내가 연 세션'으로
    // 승격시키면, 추측이 재시작 한 번으로 사실이 되어 진짜 소유자가 이 맥 앞에서 물러난다 —
    // 고치려던 사고가 그대로 되살아난다. 강도는 반드시 **영속된 값 그대로** 물려받아야 한다.
    let host = "restart-keeps-weak"
    let userID = "00000000-0000-0000-0000-000000000002"
    let suiteName = "check-ownership-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    func makeStore() -> WorkTimerStore {
        let store = WorkTimerStore(
            service: service,
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: defaults
        )
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
        store.currentTeamID = URLProtocolStub.stubTeamID
        store.deviceID = "MAC-A-AAAA"   // 사전식으로 내가 이기는 배치(옛 규칙이라면 내가 버틴다)
        return store
    }

    let sessionID = UUID().uuidString.lowercased()
    let sessionStart = Date().addingTimeInterval(-3 * 3_600)

    // 1) 이전 실행: 백스톱이 약하게 되찾아 소유 ID 를 영속했다.
    let before = makeStore()
    before.claimSessionOwnership(sessionID, strength: .weak)
    before.tickerTask?.cancel()
    before.refreshTask?.cancel()
    #expect(before.ownedSessionClaimStrength == .weak)

    // 2) 재시작: 같은 UserDefaults 를 든 새 인스턴스가 그 세션을 1차 판정으로 되찾는다.
    let after = makeStore()
    defer {
        after.tickerTask?.cancel()
        after.refreshTask?.cancel()
        after.syncTask?.cancel()
    }
    let t0 = Date()
    func poll(_ seen: Date) {
        after.teamMembers = [
            workingMember(
                userID: userID,
                startedAt: sessionStart,
                sessionID: sessionID,
                lastSeenAt: seen,
                deviceClaims: [
                    StatusDeviceClaim(deviceID: "MAC-B-ZZZZ", sessionID: sessionID, lastSeenAt: seen, openedSession: true)
                ]
            )
        ]
        after.applyRemoteOwnStatus(writeGeneration: after.workStateWriteGeneration)
    }
    poll(t0.addingTimeInterval(-15))
    #expect(!after.adoptedRemoteSession)                 // 1차 판정으로 소유를 유지한다(재시작 계약 보존)
    #expect(after.ownedSessionClaimStrength == .weak)    // 그러나 강도는 승격되지 않는다
    #expect(!after.ownsCurrentSessionStrongly)

    // 3) 진짜 소유자(강함)의 주장이 전진하면, 사전식으로 내가 이기는 배치인데도 내가 물러난다.
    poll(t0.addingTimeInterval(15))
    #expect(after.adoptedRemoteSession, "재시작이 추측을 사실로 세탁해 진짜 소유자를 밀어냈다")
    #expect(after.ownedWorkSessionID == nil)
}

@MainActor
@Test
func undoOfSomeoneElsesAutoClosedSessionDoesNotMintASecondStrongOwner() async {
    // **'강한 소유자는 최대 한 명'이라는 전제를 되돌리기 경로에서 지킨다.**
    // 맥 A 가 연 세션 S 가 7분 침묵으로 **이 맥(B)** 에게 자동 마감되고, B 사용자가 [되돌리기]를 눌렀다.
    // 되돌리기를 무조건 strong 으로 치면 S 의 강한 소유자가 A·B 둘이 되어, 두 strong 이 만나는 순간
    // 규칙이 다시 사전식 동전 던지기(= 이번 라운드가 없앤 그 결함)로 떨어진다.
    // S 를 실제로 연 것은 A 이므로 B 의 되돌리기 주장은 **약함**이어야 하고, A 가 돌아오면 B 가 물러난다.
    let host = "ownership-abandoned-session-release"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    store.deviceID = "MAC-B-AAAA"   // 사전식으로 내가 이기는 배치(옛 규칙이라면 내가 버틴다)

    // 이 맥은 S 를 연 적이 없다(소유 ID 를 영속한 적도 없다). 폴링이 방치된 S 를 주워 마감한다.
    #expect(store.ownedWorkSessionID == nil)
    await store.refreshTeamStatus()
    #expect(store.syncMessage == "자리 비움으로 자동 근무종료됨")

    await store.performUndoAutoClose()
    #expect(store.startedAt != nil)
    #expect(store.ownedWorkSessionID != nil)          // 되돌리기 자체는 그대로 동작한다(하트비트 재개)
    #expect(store.ownedSessionClaimStrength == .weak) // 그러나 '내가 열었다'고 주장하지는 않는다
    #expect(!store.ownsCurrentSessionStrongly)

    // 진짜 소유자 A 가 돌아와 신호를 전진시키면, 사전식으로 내가 이기는 배치인데도 내가 물러난다.
    let sessionID = store.currentSessionID!
    let sessionStart = store.startedAt!
    let t0 = Date()
    for step in 0..<2 {
        let seen = t0.addingTimeInterval(Double(step) * 30)
        store.teamMembers = [
            workingMember(
                userID: userID,
                startedAt: sessionStart,
                sessionID: sessionID,
                lastSeenAt: seen,
                deviceClaims: [
                    StatusDeviceClaim(deviceID: "MAC-A-ZZZZ", sessionID: sessionID, lastSeenAt: seen, openedSession: true)
                ]
            )
        ]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    }
    #expect(store.adoptedRemoteSession, "주워서 되돌린 세션을 진짜 소유자 앞에서도 놓지 않았다")
    #expect(store.ownedWorkSessionID == nil)
}

@MainActor
@Test
func undoOfMyOwnAutoClosedSessionKeepsStrongOwnership() async {
    // 대칭 대조군. 내가 연 세션이 (재시작 등으로) 내 앱에 자동 마감됐다가 되돌려진 경우엔 강도가
    // 그대로 strong 이어야 한다 — 이걸 잃으면 진짜 소유자가 남의 추측 앞에서도 사전식 동전 던지기로 떨어진다.
    let host = "ownership-abandoned-session-release-mine"
    let store = makeOwnershipStubStore(host: host)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    // 이전 실행의 start() 가 남긴 소유 ID + 강도(= 마감되는 그 세션).
    store.setOwnedWorkSessionID("50000000-0000-0000-0000-000000000001", strength: .strong)

    await store.refreshTeamStatus()
    #expect(store.syncMessage == "자리 비움으로 자동 근무종료됨")
    #expect(store.ownedWorkSessionID == nil)   // 마감하면 소유 증거는 일단 내려놓는다

    await store.performUndoAutoClose()
    #expect(store.startedAt != nil)
    #expect(store.ownedSessionClaimStrength == .strong)
    #expect(store.ownsCurrentSessionStrongly)
}

@MainActor
@Test
func heartbeatWritesThisMacsDeviceClaim() async throws {
    // 쓰기 쪽 계약. 반납 규칙이 성립하려면 **소유를 믿는 맥이 자기 행을 남겨야** 한다. 이 쓰기가 없으면
    // 상대 맥은 나를 영원히 '판정 불가'로 보고, 이중 소유가 백스톱만으로 방치된다.
    let host = "device-row-write"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    store.deviceID = "THIS-MAC-DEVICE-ID"

    store.start()
    await store.syncTask?.value
    let sessionID = try #require(store.currentSessionID)

    await store.sendHeartbeatIfWorking()

    #expect(deviceClaimCount(host: host) == 1)
    let claimBodies = zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
        .filter { $0.0.url?.path == "/rest/v1/work_status_devices" && $0.0.httpMethod == "POST" }
        .map { $0.1 }
    let body = try #require(claimBodies.first)
    #expect(body.contains(#""device_id":"THIS-MAC-DEVICE-ID""#))
    // 세션 ID 는 **반드시** 실려야 한다. 빠지면 PostgREST merge-duplicates 가 그 컬럼을 건드리지 않아
    // 옛 세션 ID 가 그대로 남고, 상대 맥은 "이 맥이 지금 그 세션을 쓴다"는 거짓 주장을 읽는다.
    #expect(body.contains(#""session_id":"\#(sessionID)""#))
    // 충돌 키가 (team_id,user_id,device_id) 여야 맥 2대가 서로의 행을 덮어쓰지 않는다.
    let claimRequest = try #require(URLProtocolStub.requests(forHost: host).first {
        $0.url?.path == "/rest/v1/work_status_devices" && $0.httpMethod == "POST"
    })
    #expect(claimRequest.url?.query?.contains("on_conflict=team_id,user_id,device_id") == true)
}

@MainActor
@Test
func adoptedMacWritesNoDeviceClaim() async {
    // 흡수 상태(다른 맥이 연 세션을 미러링)에서 기기 행을 쓰면, 그 행 자체가 '살아 있는 소유 주장'이라
    // 진짜 소유 맥이 그것을 보고 자기 세션을 반납한다 — 소유자가 0 이 되어 아무도 하트비트를 보내지 않는다.
    let host = "adopted-device-row-silence"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    store.teamMembers = [
        workingMember(
            userID: userID,
            startedAt: Date().addingTimeInterval(-3_600),
            sessionID: "b0000000-0000-0000-0000-000000000009",
            lastSeenAt: Date().addingTimeInterval(-10)
        )
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    #expect(store.adoptedRemoteSession)

    await store.sendHeartbeatIfWorking()
    #expect(URLProtocolStub.requests(forHost: host).isEmpty)
}

// MARK: - v0.2.16: 마감한 세션의 소유 ID 정리

@MainActor
@Test
func autoClosedAbandonedOwnSessionReleasesOwnedSessionID() async {
    // 자리 비움 자동 마감은 세션을 **실제로 닫는다**(stopWork PATCH). 그런데 소유 ID 를 지우지 않아
    // 닫힌 세션 ID 가 UserDefaults 에 남았고, 다음 실행의 1차 판정이 그 죽은 ID 를 '내 세션'이라 우기며
    // 존재하지 않는 세션에 하트비트를 쏘는 상태로 굳었다. 마감했으면 소유권도 함께 놓는 것이 대칭이다.
    let host = "ownership-abandoned-session-release"
    let store = makeOwnershipStubStore(host: host)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let abandonedSessionID = "50000000-0000-0000-0000-000000000001"
    store.setOwnedWorkSessionID(abandonedSessionID)
    #expect(store.startedAt == nil)

    await store.refreshTeamStatus()

    #expect(store.syncMessage == "자리 비움으로 자동 근무종료됨")
    #expect(store.lastAutoClosedSessionID == abandonedSessionID)
    #expect(store.ownedWorkSessionID == nil)
    #expect(!store.adoptedRemoteSession)

    // 되돌리기는 여전히 소유권 주장으로 동작해야 한다(마감 정리가 되돌리기를 망가뜨리지 않는다).
    await store.performUndoAutoClose()
    #expect(store.startedAt != nil)
    #expect(store.ownedWorkSessionID == abandonedSessionID)
}

@MainActor
@Test
func legacyUppercaseOwnedIDInDefaultsIsRescuedOnUpgradeRestart() {
    // **업그레이드 경로.** v0.2.15 이하는 소유 ID 를 대문자 그대로 UserDefaults 에 넣었다(정규화가 없었다).
    // 그 맥이 근무 중 이번 버전으로 올라오면, 쓰기 쪽 정규화는 그 값을 손대지 못한다 — 읽기 쪽 정규화만이
    // 그 세션을 구제한다. 없으면 업그레이드한 사람 전원이 '재시작 = 내 세션 흡수'로 떨어져 하트비트가 죽는다.
    let host = "legacy-uppercase-owned-id"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let clientID = UUID().uuidString
    // 옛 버전이 남긴 그대로(정규화 경유 없이) 디스크에 심는다.
    store.defaults.set(clientID, forKey: WorkTimerStore.ownedWorkSessionIDKey)

    let sessionStart = Date().addingTimeInterval(-90 * 60)
    store.teamMembers = [
        workingMember(
            userID: userID,
            startedAt: sessionStart,
            sessionID: clientID.lowercased(),
            lastSeenAt: Date().addingTimeInterval(-15)
        )
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

    #expect(!store.adoptedRemoteSession)
    #expect(store.startedAt == sessionStart)
    // 되찾으면서 저장 형태도 소문자로 통일된다(다음 실행부터는 읽기 정규화에 기대지 않는다).
    #expect(store.defaults.string(forKey: WorkTimerStore.ownedWorkSessionIDKey) == clientID.lowercased())
}

@MainActor
@Test
func wakingFromLongSleepDoesNotClaimOnTheFirstPoll() {
    // 시간 조건만으로 판정하면, **내가** 15분 잠들었다 깨어난 첫 폴링에서 곧바로 주장이 성립한다:
    // 정체 스탬프는 잠들기 전에 찍혔으니 경과가 이미 임계를 넘어 있기 때문이다. 그런데 그 순간 맥 A 도
    // 막 깨어나 다음 하트비트를 보내기 직전일 수 있다(A 의 잠자기 유예는 5분이라 A 자신은 근무 연속이다).
    // 그래서 '전진 없음'을 여러 폴링에 걸쳐 확인한다 — 관측 횟수와 경과 시간을 **함께** 요구하는 이유다.
    let host = "wake-from-long-sleep"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let t0 = Date()
    let sessionStart = t0.addingTimeInterval(-3 * 3_600)
    let sessionID = UUID().uuidString.lowercased()
    let frozen = t0.addingTimeInterval(-10)
    store.teamMembers = [
        workingMember(userID: userID, startedAt: sessionStart, sessionID: sessionID, lastSeenAt: frozen)
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    store.updateAdoptedPresenceTracking(store.teamMembers[0], now: t0.addingTimeInterval(30))
    #expect(store.adoptedRemoteSession)

    // 뚜껑을 15분 닫았다 연다. 깨어난 직후 첫 폴링: 경과는 이미 임계를 한참 넘었지만 관측은 이제 2회다.
    store.updateAdoptedPresenceTracking(store.teamMembers[0], now: t0.addingTimeInterval(900))
    #expect(store.adoptedRemoteSession, "잠자기에서 깬 첫 폴링에 곧바로 A 의 세션을 가로챘다")

    // A 도 깨어나 하트비트를 재개했다 → 장부가 리셋되어 이후로도 영영 주장하지 않는다.
    for step in 1...20 {
        let now = t0.addingTimeInterval(900 + Double(step) * 30)
        store.updateAdoptedPresenceTracking(
            workingMember(
                userID: userID,
                startedAt: sessionStart,
                sessionID: sessionID,
                lastSeenAt: now.addingTimeInterval(-10)
            ),
            now: now
        )
    }
    #expect(store.adoptedRemoteSession)
    #expect(store.ownedWorkSessionID == nil)
}

// MARK: - 백스톱 회수 차단(v0.2.17): 남의 기기가 주장한 세션은 되찾지 않는다

@MainActor
@Test
func foreignDeviceClaimBlocksBackstopReclaim() async {
    // 맥 A 가 연 세션을 미러링하던 맥 B. A 가 뚜껑을 닫고 사라져 신호가 굳어도, A 의 기기 행이
    // "이 세션은 A 의 것"이라 말하는 한 B 는 되찾지 않는다 — 되찾아 하트비트를 재개하면 last_seen 이
    // 계속 신선해져 10분 스캐빈저가 영영 발화하지 못하고, 퇴근한 사람의 타이머가 밤새 흐른다.
    // 옳은 결말은 스캐빈저가 마지막 신호 시각으로 마감하는 것이다.
    let host = "reclaim-blocked-by-foreign-claim"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let sessionID = "e0000000-0000-0000-0000-000000000001"
    let sessionStart = Date().addingTimeInterval(-4 * 3_600)
    let frozenSeen = Date().addingTimeInterval(-20)
    let ownerClaim = StatusDeviceClaim(
        deviceID: "owner-mac-device-id",
        sessionID: sessionID,
        lastSeenAt: frozenSeen,
        openedSession: true
    )
    store.teamMembers = [
        workingMember(
            userID: userID, startedAt: sessionStart, sessionID: sessionID,
            lastSeenAt: frozenSeen, deviceClaims: [ownerClaim]
        )
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    #expect(store.adoptedRemoteSession)

    // 신호가 굳은 채 20분(40폴링) — 7분 임계를 한참 넘겨도 주장하지 않는다.
    let t0 = Date()
    for step in 1...40 {
        store.updateAdoptedPresenceTracking(
            store.teamMembers[0],
            now: t0.addingTimeInterval(Double(step) * 30)
        )
    }
    #expect(store.adoptedRemoteSession)
    #expect(store.ownedWorkSessionID == nil)

    // 하트비트도 0건 — 이 맥은 그 세션을 되살리지 않는다(스캐빈저가 마감하도록 길을 비켜 준다).
    await store.sendHeartbeatIfWorking()
    #expect(statusUpsertCount(host: host) == 0)
    #expect(deviceClaimCount(host: host) == 0)
}

@MainActor
@Test
func ownDeviceClaimDoesNotBlockBackstopReclaim() async {
    // 대조군: 그 기기 행이 **내가** 남긴 것이면(이전 실행의 잔재 — defaults 는 남고 프로세스만 재시작)
    // 차단 근거가 아니다. 소유 ID 를 잃은 재시작의 자기 구조(백스톱 회수)는 그대로 살아 있어야 한다.
    let host = "reclaim-allowed-own-claim"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeOwnershipStubStore(host: host, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let sessionID = "e0000000-0000-0000-0000-000000000002"
    let sessionStart = Date().addingTimeInterval(-4 * 3_600)
    let frozenSeen = Date().addingTimeInterval(-20)
    let myOldClaim = StatusDeviceClaim(
        deviceID: store.deviceID,
        sessionID: sessionID,
        lastSeenAt: frozenSeen,
        openedSession: true
    )
    store.teamMembers = [
        workingMember(
            userID: userID, startedAt: sessionStart, sessionID: sessionID,
            lastSeenAt: frozenSeen, deviceClaims: [myOldClaim]
        )
    ]
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    #expect(store.adoptedRemoteSession)

    let t0 = Date()
    for step in 1...30 where store.adoptedRemoteSession {
        store.updateAdoptedPresenceTracking(
            store.teamMembers[0],
            now: t0.addingTimeInterval(Double(step) * 30)
        )
    }
    #expect(!store.adoptedRemoteSession)
    #expect(store.ownedWorkSessionID == sessionID)

    await store.sendHeartbeatIfWorking()
    #expect(statusUpsertCount(host: host) == 1)
}
