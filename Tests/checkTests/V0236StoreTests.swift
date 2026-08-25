import Foundation
import Testing
@testable import check

// v0.2.36 스토어 수정 계약 고정.
//
//  [F1] 종료 시퀀스(finishWorkBeforeQuit)의 stop() 은 수동 종료용 자동 시작 억제를 심지 않는다 —
//       ⌘Q·재부팅·brew 업그레이드로 근무 중 앱이 끝난 사용자는 [근무 종료]를 누른 적이 없는데,
//       억제가 심기면 1시간 안의 재실행이 init 재무장 판정으로 그것을 유지해 자동 출근이 무기한 죽는다.
//  [F3] 근무 중 잠자기의 관측(PendingSleepClose)을 defaults 에 심고, 세션이 정상 경로로 닫히는
//       모든 지점에서 지운다. 폴링이 didWake 보다 먼저 로컬을 내린 경합(W2)에서는 **남긴다** —
//       그 마커가 살아 있어야 Sync 소유자가 abandoned 마감을 sleep 으로 정정할 수 있다.
//  [F7] 미반영 근무 큐(pendingItems)를 didSet 으로 defaults 에 영속하고 init 이 복원한다 —
//       오프라인 중 앱 종료/크래시가 미반영 근무를 영구 소실시키지 않게.

private func isolatedSuite() -> (suiteName: String, defaults: UserDefaults) {
    let suiteName = "check-v0236-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (suiteName, defaults)
}

private let stubUserID = "00000000-0000-0000-0000-000000000002"

/// 스텁 네트워크에 물린 로그인 상태 스토어(로그인 흐름은 건너뛰고 세션/팀을 직접 확정 — 기존 스위트 규약).
@MainActor
private func makeStore(host: String, defaults: UserDefaults) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: stubUserID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    return store
}

@MainActor
private func cancelTasks(_ store: WorkTimerStore) {
    store.tickerTask?.cancel()
    store.refreshTask?.cancel()
    store.syncTask?.cancel()
    store.pokePollTask?.cancel()
}

/// 큐 픽스처. 시각은 **정초 값**만 쓴다 — JSON 왕복(Double)에서 소수부 정밀도가 흔들려
/// 동등성 단언이 시각 의존 플레이키가 되는 것을 막는다.
private func makeItem(
    operation: PendingWorkOperation,
    owner: String? = stubUserID,
    reason: AutoCloseReason? = nil
) -> PendingWorkItem {
    PendingWorkItem(
        id: UUID(),
        operation: operation,
        sessionID: "aaaaaaaa-0000-0000-0000-000000000001",
        sessionStartedAt: Date(timeIntervalSince1970: 1_787_000_000),
        endedAt: Date(timeIntervalSince1970: 1_787_003_600),
        ownerUserID: owner,
        autoCloseReason: reason
    )
}

@MainActor
@Suite struct V0236StoreTests {
    // MARK: - [F1] 종료 시퀀스의 stop() 은 억제를 심지 않는다

    @Test func quitSequenceStopDoesNotSuppressAutoStart() async {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-quit-no-suppress", defaults: defaults)
        defer { cancelTasks(store) }
        store.start()
        #expect(!store.autoStartSuppressed)

        await store.finishWorkBeforeQuit(timeout: 0.5)

        // 근무는 마감됐지만(종료 동기화) 사용자가 [근무 종료]를 누른 적은 없다 — 억제 금지.
        #expect(store.startedAt == nil)
        #expect(!store.autoStartSuppressed)
        #expect(defaults.object(forKey: WorkTimerStore.autoStartSuppressedKey) == nil)
    }

    @Test func manualStopStillSuppressesAutoStart() {
        // 대조군. 게이트가 수동 stop 까지 삼키면 "퇴근 후 유령 재출근"(v0.2.17 계약)이 되살아난다.
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-manual-suppress", defaults: defaults)
        defer { cancelTasks(store) }
        store.start()
        store.stop()

        #expect(store.autoStartSuppressed)
        #expect(defaults.bool(forKey: WorkTimerStore.autoStartSuppressedKey))
    }

    // MARK: - [F3] 잠자기 마감 정정 마커 — 심김

    @Test func sleepWhileWorkingPersistsCloseMarker() {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-sleep-marker", defaults: defaults)
        defer { cancelTasks(store) }
        let t0 = Date(timeIntervalSince1970: 1_787_000_000)
        store.start(now: t0)
        let input = t0.addingTimeInterval(1_800)
        store.lastMeaningfulInputAt = input
        let sleepAt = t0.addingTimeInterval(3_600)

        store.handleSleep(at: sleepAt)

        #expect(store.pendingSleepCloseMarker() == PendingSleepClose(
            sessionID: store.currentSessionID!,
            sessionStartedAt: t0,
            sleepBeganAt: sleepAt,
            lastInputAt: input
        ))

        // defaults 왕복: 같은 defaults 로 다시 만든 스토어(앱 재실행)에서도 마커가 그대로 읽힌다 —
        // 잠자는 사이 앱이 죽는 경우(업그레이드)의 정정은 다음 실행이 이 값으로만 할 수 있다.
        let relaunched = makeStore(host: "v0236-sleep-marker-relaunch", defaults: defaults)
        defer { cancelTasks(relaunched) }
        #expect(relaunched.pendingSleepCloseMarker()?.sleepBeganAt == sleepAt)
    }

    @Test func sleepWithoutWorkingDoesNotPersistMarker() {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-sleep-idle", defaults: defaults)
        defer { cancelTasks(store) }

        store.handleSleep(at: Date(timeIntervalSince1970: 1_787_000_000))

        #expect(store.pendingSleepCloseMarker() == nil)
    }

    @Test func sleepOnAdoptedSessionDoesNotPersistMarker() {
        // 흡수 세션(다른 맥이 연 세션)에서 내 덮개 시각은 마감 근거가 될 수 없다(autoStop 과 같은 계약).
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-sleep-adopted", defaults: defaults)
        defer { cancelTasks(store) }
        let t0 = Date(timeIntervalSince1970: 1_787_000_000)
        store.startedAt = t0
        store.currentSessionID = "bbbbbbbb-0000-0000-0000-000000000001"
        store.adoptedRemoteSession = true
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)

        store.handleSleep(at: t0.addingTimeInterval(600))

        #expect(store.pendingSleepCloseMarker() == nil)
    }

    // MARK: - [F3] 마커 해제 지점 전수

    @Test func wakeWithinGraceClearsMarker() {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-wake-grace", defaults: defaults)
        defer { cancelTasks(store) }
        let t0 = Date(timeIntervalSince1970: 1_787_000_000)
        store.start(now: t0)
        let sleepAt = t0.addingTimeInterval(3_600)
        store.handleSleep(at: sleepAt)
        #expect(store.pendingSleepCloseMarker() != nil)

        store.handleWake(at: sleepAt.addingTimeInterval(120)) // 유예(5분) 안 — 세션 계속

        #expect(store.startedAt != nil)
        #expect(store.pendingSleepCloseMarker() == nil)
    }

    @Test func wakeAutoStopClearsMarker() {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-wake-autostop", defaults: defaults)
        defer { cancelTasks(store) }
        let t0 = Date(timeIntervalSince1970: 1_787_000_000)
        store.start(now: t0)
        let sleepAt = t0.addingTimeInterval(3_600)
        store.lastMeaningfulInputAt = sleepAt
        store.handleSleep(at: sleepAt)
        #expect(store.pendingSleepCloseMarker() != nil)

        store.handleWake(at: sleepAt.addingTimeInterval(600)) // 유예 밖 — sleep 자동 마감 발화

        // 마감이 실제로 발화했고(사유가 큐에 실렸다), 정정할 마감을 직접 내보냈으므로 마커도 내려간다.
        #expect(store.startedAt == nil)
        #expect(store.pendingItems.last?.autoCloseReason == .sleep)
        #expect(store.pendingSleepCloseMarker() == nil)
    }

    @Test func manualStopClearsMarker() {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-stop-clears", defaults: defaults)
        defer { cancelTasks(store) }
        let t0 = Date(timeIntervalSince1970: 1_787_000_000)
        store.start(now: t0)
        store.handleSleep(at: t0.addingTimeInterval(3_600))
        #expect(store.pendingSleepCloseMarker() != nil)

        store.stop(now: t0.addingTimeInterval(4_000))

        #expect(store.pendingSleepCloseMarker() == nil)
    }

    @Test func autoStopAnyReasonClearsMarker() {
        // 자동 마감의 모든 사유가 지나는 관문(closeOwnedSessionLocally → autoStop)에서 마커가 내려간다.
        // 이 관문은 Sync 의 서버 정정 수용 지점이 쓰는 그 문이라, "소비 후 마감이 마커를 지운다"까지가 계약이다.
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-autostop-clears", defaults: defaults)
        defer { cancelTasks(store) }
        let t0 = Date(timeIntervalSince1970: 1_787_000_000)
        store.start(now: t0)
        store.handleSleep(at: t0.addingTimeInterval(3_600))
        #expect(store.pendingSleepCloseMarker() != nil)

        store.closeOwnedSessionLocally(
            endedAt: t0.addingTimeInterval(3_600),
            message: "잠자기로 자동 근무종료됨",
            reason: .sleep
        )

        #expect(store.startedAt == nil)
        #expect(store.pendingSleepCloseMarker() == nil)
    }

    @Test func startClearsStaleMarker() {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-start-clears", defaults: defaults)
        defer { cancelTasks(store) }
        store.persistPendingSleepClose(PendingSleepClose(
            sessionID: "cccccccc-0000-0000-0000-000000000001",
            sessionStartedAt: Date(timeIntervalSince1970: 1_786_900_000),
            sleepBeganAt: Date(timeIntervalSince1970: 1_786_903_600),
            lastInputAt: nil
        ))

        store.start(now: Date(timeIntervalSince1970: 1_787_000_000))

        // 새 세션이 섰다 — 이전 세션의 관측은 낡은 마커라 여기서 끊긴다.
        #expect(store.pendingSleepCloseMarker() == nil)
    }

    @Test func accountSwitchClearsMarkerButSameAccountKeepsIt() {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-owner-marker", defaults: defaults)
        defer { cancelTasks(store) }
        let marker = PendingSleepClose(
            sessionID: "dddddddd-0000-0000-0000-000000000001",
            sessionStartedAt: Date(timeIntervalSince1970: 1_787_000_000),
            sleepBeganAt: Date(timeIntervalSince1970: 1_787_003_600),
            lastInputAt: nil
        )
        store.persistPendingSleepClose(marker)

        // 같은 계정 확정(첫 로그인/재로그인)은 관측을 이어받는다.
        store.adoptWorkStateOwner(stubUserID)
        #expect(store.pendingSleepCloseMarker() == marker)

        // 계정이 바뀌면 앞 계정의 관측을 끊는다.
        store.adoptWorkStateOwner("99999999-0000-0000-0000-000000000009")
        #expect(store.pendingSleepCloseMarker() == nil)
    }

    // MARK: - [F3] 경합 생존 — 지우면 안 되는 자리

    @Test func wakeAfterRemoteCloseKeepsMarkerForSyncConsumer() {
        // W2 그 자체: 폴링이 didWake 보다 먼저 완주해 로컬을 내리면 handleWake 는 startedAt 가드에서
        // 조기 반환한다. 그 가지가 마커를 지우면 sleep 정정이 영영 못 나가 abandoned 가 굳는다 — 남겨야 한다.
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-race-survives", defaults: defaults)
        defer { cancelTasks(store) }
        let t0 = Date(timeIntervalSince1970: 1_787_000_000)
        store.start(now: t0)
        let sleepAt = t0.addingTimeInterval(3_600)
        store.handleSleep(at: sleepAt)

        // 폴링의 원격 마감 흡수가 로컬을 먼저 내린 모양.
        store.startedAt = nil
        store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)

        store.handleWake(at: sleepAt.addingTimeInterval(1_200))

        #expect(store.pendingSleepCloseMarker()?.sleepBeganAt == sleepAt)
    }

    @Test func forcedLogoutKeepsMarkerAndQueue() {
        // 강제 로그아웃(토큰 만료)은 미반영 근무를 보존한다(:2004 주석의 계약). 마커도 같은 성격의
        // 미결 관측이라 함께 산다 — 재로그인(같은 계정) 후 정정이 재생돼야 하고, 계정이 바뀌면
        // adoptWorkStateOwner 가 그때 끊는다.
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-forced-logout", defaults: defaults)
        defer { cancelTasks(store) }
        let item = makeItem(operation: .stop(durationSeconds: 100), reason: .sleep)
        store.pendingItems = [item]
        let marker = PendingSleepClose(
            sessionID: "eeeeeeee-0000-0000-0000-000000000001",
            sessionStartedAt: Date(timeIntervalSince1970: 1_787_000_000),
            sleepBeganAt: Date(timeIntervalSince1970: 1_787_003_600),
            lastInputAt: nil
        )
        store.persistPendingSleepClose(marker)

        store.clearPersistedSession()

        #expect(store.pendingItems == [item])
        #expect(WorkTimerStore.restoredPendingWorkQueue(from: defaults) == [item])
        #expect(store.pendingSleepCloseMarker() == marker)
    }

    @Test func corruptMarkerReadsAsNil() {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-corrupt-marker", defaults: defaults)
        defer { cancelTasks(store) }
        defaults.set(Data("{깨진 json".utf8), forKey: WorkTimerStore.pendingSleepCloseKey)

        #expect(store.pendingSleepCloseMarker() == nil)
    }

    // MARK: - [F7] 미반영 근무 큐 영속

    @Test func queueMutationsPersistToDefaults() {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-queue-mutations", defaults: defaults)
        defer { cancelTasks(store) }
        let a = makeItem(operation: .start)
        let b = makeItem(operation: .stop(durationSeconds: 123), reason: .sleep)

        // @Observable 매크로 아래에서도 didSet 이 in-place 변이(append/removeFirst/removeAll)를
        // 전부 잡는지 — 이 스위트가 그 상호작용의 실증이다.
        store.pendingItems.append(a)
        #expect(WorkTimerStore.restoredPendingWorkQueue(from: defaults) == [a])

        store.pendingItems.append(b)
        #expect(WorkTimerStore.restoredPendingWorkQueue(from: defaults) == [a, b])

        store.pendingItems.removeFirst()
        #expect(WorkTimerStore.restoredPendingWorkQueue(from: defaults) == [b])

        store.pendingItems.removeAll()
        #expect(WorkTimerStore.restoredPendingWorkQueue(from: defaults).isEmpty)
        // 빈 큐는 키 자체가 지워진다 — 낡은 JSON 이 다음 실행에 유령 항목으로 남지 않게.
        #expect(defaults.data(forKey: WorkTimerStore.pendingWorkQueueKey) == nil)
    }

    @Test func queueSurvivesRelaunch() {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-queue-relaunch", defaults: defaults)
        defer { cancelTasks(store) }
        let a = makeItem(operation: .start)
        let b = makeItem(operation: .stop(durationSeconds: 7_200), reason: .away)
        store.pendingItems = [a, b]

        // 앱 재실행(같은 defaults 로 재초기화) — 연관값·사유·시각·소유자까지 그대로 복원돼야
        // 드레인이 정확히 재생된다(재생 자체의 멱등은 서버 몫: start ignore-duplicates / stop id 필터).
        let relaunched = makeStore(host: "v0236-queue-relaunch-2", defaults: defaults)
        defer { cancelTasks(relaunched) }
        #expect(relaunched.pendingItems == [a, b])
    }

    @Test func ownerFilterDropsForeignItemsAndPersists() {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-queue-owner", defaults: defaults)
        defer { cancelTasks(store) }
        let mine = makeItem(operation: .start)
        let foreign = makeItem(operation: .start, owner: "99999999-0000-0000-0000-000000000009")
        store.pendingItems = [foreign, mine]

        store.adoptWorkStateOwner(stubUserID)

        // 기존 소유자 필터 계약 그대로 + 필터 결과가 디스크에도 반영된다(removeAll(where:) 도 didSet 경유).
        #expect(store.pendingItems == [mine])
        #expect(WorkTimerStore.restoredPendingWorkQueue(from: defaults) == [mine])
    }

    @Test func corruptQueueRestoresEmptyWithoutCrash() {
        let (_, defaults) = isolatedSuite()
        defaults.set(Data("깨진 데이터".utf8), forKey: WorkTimerStore.pendingWorkQueueKey)

        let store = makeStore(host: "v0236-queue-corrupt", defaults: defaults)
        defer { cancelTasks(store) }

        #expect(store.pendingItems.isEmpty)
    }

    @Test func unknownOperationKindRestoresEmptyWithoutCrash() {
        // 미래 버전이 남긴 모르는 kind — 케이스 접힘/오배달 대신 빈 큐로 접는다(크래시 금지).
        let (_, defaults) = isolatedSuite()
        let json = #"[{"id":"AAAAAAAA-0000-0000-0000-000000000001","operation":{"kind":"pause"},"sessionID":"s"}]"#
        defaults.set(Data(json.utf8), forKey: WorkTimerStore.pendingWorkQueueKey)

        let store = makeStore(host: "v0236-queue-unknown-kind", defaults: defaults)
        defer { cancelTasks(store) }

        #expect(store.pendingItems.isEmpty)
    }

    @Test func drainedQueueAlsoClearsDefaults() async {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-queue-drain", defaults: defaults)
        defer { cancelTasks(store) }
        store.start()
        #expect(!store.pendingItems.isEmpty)
        #expect(defaults.data(forKey: WorkTimerStore.pendingWorkQueueKey) != nil)

        await store.retryPendingSync()

        // 드레인 성공 = 서버 반영 완료. 메모리 큐와 디스크 장부가 함께 비어야 다음 실행이 이중 재생을 안 한다.
        #expect(store.pendingItems.isEmpty)
        #expect(defaults.data(forKey: WorkTimerStore.pendingWorkQueueKey) == nil)
    }
}
