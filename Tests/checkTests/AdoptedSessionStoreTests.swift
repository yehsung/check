import Foundation
import Testing
@testable import check

// D2 흡수 세션 소유권 표식(adoptedRemoteSession)의 스토어 쪽 계약 고정.
//
// 이 스위트의 핵심은 **대조군**이다. 표식이 자동 마감을 전부 막아 버리면 '남의 세션을 지켜 주는 수정'이
// '내 세션을 아무도 못 닫게 만드는 결함'으로 뒤집힌다(맥 A 종료 후 맥 B 가 밤새 근무중으로 고착).
// 그래서 모든 차단 케이스마다 같은 조건에서 표식만 false 인 짝을 두고, 그쪽은 **여전히 마감하는지**를 함께 본다.
//
// 자동 마감 경로는 전부 autoStop 한 곳으로 모이므로(handleWake / evaluateLongSession) 차단도 거기서 한다.
// 여기서는 그 초크 포인트가 실제로 두 진입점을 모두 덮는지를 진입점 쪽에서 실증한다.

// MARK: - 픽스처

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "check-adopted-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// 스텁 네트워크에 물린 로그인 상태 스토어. 로그인 흐름(confirmMembership)을 건너뛰므로 팀도 직접 확정한다.
@MainActor
private func makeAdoptionStubStore(
    host: String,
    userID: String = "00000000-0000-0000-0000-000000000002"
) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    return store
}

/// 다른 맥이 연 세션을 서버 스냅샷에서 흡수한 직후의 로컬 상태를 만든다(applyRemoteOwnStatus 가 세우는 그 모양).
@MainActor
private func adoptRemote(_ store: WorkTimerStore, startedAt: Date, sessionID: String = "remote-session") {
    store.startedAt = startedAt
    store.currentSessionID = sessionID
    store.longSessionAnchor = startedAt
    store.snapshot = WorkStatusSnapshot(
        status: .working,
        elapsedSeconds: max(0, Int(Date().timeIntervalSince(startedAt)))
    )
    store.adoptedRemoteSession = true
}

// MARK: - 잠자기 자동 마감

@MainActor
@Test
func adoptedRemoteSessionIsNotClosedByWake() {
    // 맥 A 가 근무를 시작하고 맥 B 가 그것을 흡수한 상태에서, 맥 B 의 덮개를 10분 닫았다 연다.
    // 예전엔 맥 B 가 '덮은 시각'으로 맥 A 의 세션을 마감해 그 뒤 맥 A 의 근무가 통째로 사라졌다.
    let host = "adopted-wake-skip"
    let store = makeAdoptionStubStore(host: host)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    let sleepAt = Date()
    let sessionStart = sleepAt.addingTimeInterval(-3_600)
    adoptRemote(store, startedAt: sessionStart)
    let messageBefore = store.syncMessage

    store.handleSleep(at: sleepAt)
    store.handleWake(at: sleepAt.addingTimeInterval(10 * 60)) // 10분 > 5분 유예

    // 서버에 아무 쓰기도 하지 않는다(큐가 곧 쓰기다 — 항목이 생기면 다음 드레인에 PATCH 가 나간다).
    #expect(store.pendingItems.isEmpty)
    // 로컬 표시도 내리지 않는다: 내려 봐야 다음 폴링(≤30초)이 즉시 재흡수해 되돌려 놓기 때문이다.
    #expect(store.startedAt == sessionStart)
    #expect(store.snapshot.isWorking)
    #expect(store.adoptedRemoteSession)
    // 마감 사유 문구도 뜨지 않는다(사용자에게 일어나지 않은 일을 알리지 않는다).
    #expect(store.syncMessage == messageBefore)
    // 잠자기 기록만 소비한다 — 남겨 두면 다음 깨어남이 아주 오래된 sleepBeganAt 으로 다시 판정한다.
    #expect(store.sleepBeganAt == nil)
    #expect(URLProtocolStub.requests(forHost: host).isEmpty)
}

@MainActor
@Test
func ownSessionStillAutoStopsOnWake() {
    // 대조군. 표식이 전부를 막으면 '내가 연 세션'까지 방치돼 잠자기 자동 마감이 통째로 죽는다.
    let host = "own-wake-stop"
    let store = makeAdoptionStubStore(host: host)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    let sleepAt = Date()
    store.start(now: sleepAt.addingTimeInterval(-3_600))
    // start() 는 소유권을 확정하는 지점이라 표식이 반드시 내려가 있어야 한다.
    #expect(!store.adoptedRemoteSession)
    // v0.2.35: 잠자기 마감 시각이 min(뚜껑 닫은 시각, 마지막 의미 있는 입력)으로 정밀해졌다.
    // 이 테스트가 고정하는 것은 **표식이 마감을 막지 않는다**이지 마감 시각 정책이 아니므로,
    // "뚜껑을 닫기 직전까지 타이핑하고 있었다"를 명시해 원래 의도만 남긴다(헤드리스라 하트비트가 돌지 않는다).
    store.lastMeaningfulInputAt = sleepAt

    store.handleSleep(at: sleepAt)
    store.handleWake(at: sleepAt.addingTimeInterval(10 * 60))

    #expect(store.startedAt == nil)
    #expect(store.sleepBeganAt == nil)
    #expect(store.syncMessage == "잠자기로 자동 근무종료됨")
    // 시작과 마감이 순서대로 큐에 남는다(= 서버에 마감이 나간다). 덮은 시각으로 마감한다.
    #expect(store.pendingItems.map(\.operation) == [.start, .stop(durationSeconds: 3_600)])
    #expect(store.pendingItems.last?.endedAt == sleepAt)
}

// MARK: - 12시간 자동 마감

@MainActor
@Test
func adoptedRemoteSessionIsNotClosedByTwelveHourRule() {
    // 흡수 세션의 '12시간'은 남의 맥이 잰 시간이다. 마감도, 그 앞의 확인 배너도 이 맥에서는 뜨지 않는다.
    let host = "adopted-long-session-skip"
    let store = makeAdoptionStubStore(host: host)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    let t0 = Date()
    adoptRemote(store, startedAt: t0)

    store.evaluateLongSession(now: t0.addingTimeInterval(12 * 3_600 + 1))
    // 배너까지 막는 이유: 마감만 막으면 [네, 근무 중이에요] 를 눌러도 남의 세션이라 30분마다 되풀이된다.
    #expect(!store.isLongSessionPromptActive)
    #expect(store.promptShownAt == nil)

    store.evaluateLongSession(now: t0.addingTimeInterval(12 * 3_600 + 30 * 60 + 2))

    #expect(store.startedAt == t0)
    #expect(store.snapshot.isWorking)
    #expect(store.pendingItems.isEmpty)
    #expect(URLProtocolStub.requests(forHost: host).isEmpty)
}

@MainActor
@Test
func ownSessionStillAutoStopsAfterTwelveHours() {
    // 대조군. 내가 연 세션은 종전대로 12시간 확인 → 30분 무응답 → 12시간 시점 마감을 그대로 탄다.
    let host = "own-long-session-stop"
    let store = makeAdoptionStubStore(host: host)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    let t0 = Date()
    store.startedAt = t0
    store.longSessionAnchor = t0
    store.currentSessionID = "own-session"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    #expect(!store.adoptedRemoteSession)

    store.evaluateLongSession(now: t0.addingTimeInterval(12 * 3_600 + 1))
    #expect(store.isLongSessionPromptActive)

    store.evaluateLongSession(now: t0.addingTimeInterval(12 * 3_600 + 30 * 60 + 2))

    #expect(store.startedAt == nil)
    #expect(store.syncMessage == "장시간 미확인으로 자동 근무종료됨")
    #expect(store.pendingItems.first?.endedAt == t0.addingTimeInterval(12 * 3_600))
}

// MARK: - 사용자가 직접 누른 종료 / 시작

@MainActor
@Test
func userStopClosesAdoptedSessionOnServer() async {
    // 사용자가 직접 누른 종료는 흡수 세션이어도 그대로 서버에 쓴다 — 같은 사람의 명시적 의사이기 때문이다.
    // (자동 경로만 막는 것이 D2 의 계약이고, 이 테스트가 그 경계를 고정한다.)
    let host = "adopted-user-stop"
    let store = makeAdoptionStubStore(host: host)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    let now = Date()
    adoptRemote(store, startedAt: now.addingTimeInterval(-3_600))

    store.stop(now: now)

    #expect(store.startedAt == nil)
    // 세션이 끝났으므로 표식도 함께 내려간다 — 남기면 다음에 이 맥에서 시작할 근무가 남의 것으로 오인된다.
    #expect(!store.adoptedRemoteSession)
    #expect(store.pendingItems.map(\.operation) == [.stop(durationSeconds: 3_600)])

    await store.syncTask?.value

    let stopPatches = URLProtocolStub.requests(forHost: host).filter {
        $0.url?.path == "/rest/v1/work_sessions" && $0.httpMethod == "PATCH"
    }
    #expect(stopPatches.count == 1)
    #expect(store.pendingItems.isEmpty)
}

@MainActor
@Test
func startClearsAdoptionMarkSoOwnSessionStaysClosable() {
    // 표식이 남은 채 새 근무를 시작하면 그 세션은 이 맥의 자동 마감·하트비트에서 영구 제외돼
    // '아무도 못 닫는 세션'이 된다. start() 가 소유권을 확정하는 유일한 지점이라 여기서 반드시 내린다.
    let host = "start-clears-adoption"
    let store = makeAdoptionStubStore(host: host)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    // 흡수 세션이 끝나며 표식 리셋이 한 군데라도 빠진 최악의 상태를 만든다.
    store.adoptedRemoteSession = true
    store.startedAt = nil

    let t0 = Date()
    store.start(now: t0)
    #expect(!store.adoptedRemoteSession)

    // 표식이 남아 있었다면 아래 잠자기 마감이 통째로 막힌다.
    // v0.2.35 의 잠자기 시각 정밀화(min(뚜껑, 마지막 입력))는 이 테스트의 관심사가 아니므로
    // "뚜껑 직전까지 입력이 있었다"를 명시한다(헤드리스라 하트비트가 그 값을 전진시키지 못한다).
    store.lastMeaningfulInputAt = t0.addingTimeInterval(60)
    store.handleSleep(at: t0.addingTimeInterval(60))
    store.handleWake(at: t0.addingTimeInterval(60 + 10 * 60))
    #expect(store.startedAt == nil)
    #expect(store.pendingItems.map(\.operation) == [.start, .stop(durationSeconds: 60)])
}

// MARK: - 앱 종료 동기화

@MainActor
@Test
func adoptedRemoteSessionSkipsQuitSync() async {
    // 이 맥을 끄는 것이 저쪽 근무를 끝내지는 않는다. 종료 동기화가 흡수 세션을 내 종료 시각으로 마감하면
    // 상대는 화면상 퇴근 처리되고 그 뒤 근무가 통째로 소실된다.
    let host = "adopted-quit-skip"
    let store = makeAdoptionStubStore(host: host)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    let sessionStart = Date().addingTimeInterval(-3_600)
    adoptRemote(store, startedAt: sessionStart)

    await store.finishWorkBeforeQuit(timeout: 0.05)

    #expect(store.startedAt == sessionStart)
    #expect(store.adoptedRemoteSession)
    #expect(store.pendingItems.isEmpty)
    #expect(URLProtocolStub.requests(forHost: host).isEmpty)
}

@MainActor
@Test
func ownSessionStillSyncsOnQuit() async {
    // 대조군. 내가 연 세션은 종료 직전에 종전대로 마감이 서버로 나간다(가드가 전부를 막지 않음).
    let host = "own-quit-sync"
    let store = makeAdoptionStubStore(host: host)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    store.startedAt = Date().addingTimeInterval(-3_600)
    store.currentSessionID = "own-session"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)

    await store.finishWorkBeforeQuit(timeout: 3)

    #expect(store.startedAt == nil)
    let stopPatches = URLProtocolStub.requests(forHost: host).filter {
        $0.url?.path == "/rest/v1/work_sessions" && $0.httpMethod == "PATCH"
    }
    #expect(stopPatches.count == 1)
    // 종료 경로의 stop() 은 찔림 꼬리를 회수하지 않는다 — take_pokes 는 서버 원자 소비라
    // 응답 전에 프로세스가 죽으면 그 찔림이 영구 소실되고, 종료 시점엔 볼 사람도 없다.
    let takePokes = URLProtocolStub.requests(forHost: host).filter {
        $0.url?.path == "/rest/v1/rpc/take_pokes"
    }
    #expect(takePokes.isEmpty)
}
