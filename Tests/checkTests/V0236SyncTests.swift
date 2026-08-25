import Foundation
import Testing
@testable import check

// v0.2.36 Sync(B) 계약 고정 — W2/W3 근본 원인에 대한 폴링 수용 지점의 정정·통보.
//
//  [F3-수용] 서버 스캐빈저가 abandoned(복원 불가)로 먼저 닫아 둔 내 소유 세션을 폴링이 발견하면,
//       잠자기 마커(PendingSleepClose)를 소비해 reason=sleep 정정 stop 을 큐에 싣는다.
//       경쟁의 양방향(폴링 먼저 / didWake 먼저)과 재실행(잠자는 사이 앱 사망)을 모두 고정한다.
//  [F4-통보] 마커 없이(잠자기가 아닌데) 신호 공백 10분+ 로 닫힌 강하는 침묵하지 않는다 —
//       사용자 문구 + 10분 되돌리기 배너. 흡수 세션 강하는 기존 그대로 침묵한다.

private func isolatedSuite() -> (suiteName: String, defaults: UserDefaults) {
    let suiteName = "check-v0236-sync-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (suiteName, defaults)
}

private let stubUserID = "00000000-0000-0000-0000-000000000002"

/// 시나리오 기준 시각(KST 2026-08-16 11:13 — 자정 경계에서 충분히 멀어 클리핑이 개입하지 않는다).
/// 벽시계를 읽지 않는 고정 절대 시각 — 이 스위트의 모든 시각은 여기서 파생한다(시각 의존 플레이키 금지).
private let t0 = Date(timeIntervalSince1970: 1_787_000_000)

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

/// 서버가 내 세션을 닫아 둔 뒤의 폴링 스냅샷(내 행이 off_work). seen 이 강하 통보의 신선도 판정 재료다.
private func offWorkMember(
    todaySeconds: Int,
    lastSeenAt: Date?,
    updatedAt: Date? = nil
) -> TeamMemberStatus {
    TeamMemberStatus(
        id: stubUserID,
        name: "영식",
        status: .offWork,
        updatedAt: updatedAt,
        currentSessionStartedAt: nil,
        weeklyDurationSeconds: todaySeconds,
        todayDurationSeconds: todaySeconds,
        avatarURL: nil,
        lastSeenAt: lastSeenAt,
        activeSessionID: nil
    )
}

@MainActor
@Suite struct V0236SyncTests {
    // MARK: - [F3-수용] (1) 경쟁 재현 — 폴링 수용이 didWake 보다 먼저

    @Test func pollAcceptanceBeforeWakeCorrectsAbandonedCloseToSleep() {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-sync-race-poll-first", defaults: defaults)
        defer { cancelTasks(store) }
        store.clock = { t0.addingTimeInterval(4_200) }
        store.start(now: t0)
        let sessionID = store.currentSessionID!
        // start 큐는 드레인된 상태로 둔다(수용 지점의 pendingItems 가드 통과).
        store.pendingItems = []
        // 오늘 앞선 마감 몫 — 이중 가산 검출의 기준값. 서버 today(9_999)와 확실히 다른 수로 둔다.
        store.accumulatedSeconds = 1_000
        store.accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: t0)
        store.lastMeaningfulInputAt = t0.addingTimeInterval(1_800)
        store.handleSleep(at: t0.addingTimeInterval(3_600))
        #expect(store.pendingSleepCloseMarker() != nil)

        // 뚜껑 닫고 10분+: 서버 스캐빈저가 abandoned 로 먼저 마감했고, 깨어난 순간 폴링이 didWake 보다
        // 먼저 완주해 이 스냅샷을 본다(서버 today 는 그 마감 몫을 이미 포함한다).
        store.teamMembers = [offWorkMember(todaySeconds: 9_999, lastSeenAt: t0.addingTimeInterval(3_630))]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

        // 큐: reason=sleep stop 정확히 1개, endedAt = max(시작, min(덮개, 마지막 입력)) = t0+1800.
        #expect(store.pendingItems.count == 1)
        let item = store.pendingItems.first
        #expect(item?.autoCloseReason == .sleep)
        #expect(item?.sessionID == sessionID)
        #expect(item?.sessionStartedAt == t0)
        #expect(item?.endedAt == t0.addingTimeInterval(1_800))
        #expect(item?.operation == .stop(durationSeconds: 1_800))
        // 마커 소거 + 로컬 마감 완료(autoStop 관문 경유).
        #expect(store.pendingSleepCloseMarker() == nil)
        #expect(store.startedAt == nil)
        #expect(store.currentSessionID == nil)
        #expect(!store.snapshot.isWorking)
        // 회계 정확히 1회: 정정 전 로컬 누적(1_000) + 정정 몫(1_800) = 2_800.
        // 서버 today(9_999, abandoned 마감 몫 포함)로 덮은 뒤 또 더하면 11_799 — 그 이중 가산 금지.
        #expect(store.accumulatedSeconds == 2_800)
        #expect(store.syncMessage == "잠자기로 자동 근무종료됨")

        // 뒤늦게 도착한 didWake 는 무해하다(startedAt/sleepBeganAt 이 이미 내려가 조기 반환).
        store.handleWake(at: t0.addingTimeInterval(4_200))
        #expect(store.pendingItems.count == 1)
        #expect(store.startedAt == nil)
        #expect(store.accumulatedSeconds == 2_800)
        #expect(store.pendingSleepCloseMarker() == nil)
    }

    // MARK: - [F3-수용] (2) 역순 — handleWake 가 먼저 이기면 수용 가지는 건너뛴다

    @Test func wakeBeforePollSkipsAcceptanceCorrection() async {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-sync-race-wake-first", defaults: defaults)
        defer { cancelTasks(store) }
        store.clock = { t0.addingTimeInterval(4_200) }
        store.start(now: t0)
        store.pendingItems = []
        store.lastMeaningfulInputAt = t0.addingTimeInterval(1_800)
        store.handleSleep(at: t0.addingTimeInterval(3_600))

        // didWake 가 먼저 완주(유예 5분 밖) — 기존 잠자기 정정이 발화해 큐 1건 + 마커 소거.
        store.handleWake(at: t0.addingTimeInterval(4_200))
        #expect(store.pendingItems.count == 1)
        #expect(store.pendingItems.first?.autoCloseReason == .sleep)
        #expect(store.pendingSleepCloseMarker() == nil)
        let accumulatedAfterWake = store.accumulatedSeconds

        // 이어서 도착한 폴링: pendingItems 가드(큐 비어있음 요구)가 수용 가지를 통째로 건너뛴다.
        store.teamMembers = [offWorkMember(todaySeconds: 9_999, lastSeenAt: t0.addingTimeInterval(3_630))]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
        #expect(store.pendingItems.count == 1)
        #expect(store.accumulatedSeconds == accumulatedAfterWake)
        #expect(store.syncMessage == "잠자기로 자동 근무종료됨")

        // 드레인 뒤의 다음 폴링도 재정정하지 않는다(마커가 이미 소거됐다) — 정정은 전 구간에서 1회다.
        await store.retryPendingSync()
        store.teamMembers = [offWorkMember(todaySeconds: 1_800, lastSeenAt: t0.addingTimeInterval(3_630))]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
        #expect(store.pendingItems.isEmpty)
    }

    // MARK: - [F3-수용] (3) 재실행 — 잠자는 사이 앱 사망, 다음 실행의 첫 수용에서 정정 1회

    @Test func relaunchConsumesPersistedMarkerExactlyOnce() async {
        let (_, defaults) = isolatedSuite()
        let first = makeStore(host: "v0236-sync-relaunch-a", defaults: defaults)
        first.clock = { t0.addingTimeInterval(3_600) }
        first.start(now: t0)
        let sessionID = first.currentSessionID!
        // start 큐를 드레인해 둔다 — 재실행이 복원하는 큐가 비어 있어야 수용 가드를 지난다.
        await first.retryPendingSync()
        first.lastMeaningfulInputAt = t0.addingTimeInterval(1_800)
        first.handleSleep(at: t0.addingTimeInterval(3_600))
        #expect(first.pendingSleepCloseMarker() != nil)
        cancelTasks(first)

        // 앱 사망 → 재실행: 메모리 상태는 없고 defaults(마커 + 소유 ID)만 남았다.
        let store = makeStore(host: "v0236-sync-relaunch-b", defaults: defaults)
        defer { cancelTasks(store) }
        store.clock = { t0.addingTimeInterval(5_000) }
        #expect(store.startedAt == nil)
        #expect(store.pendingItems.isEmpty)
        #expect(store.ownedWorkSessionID == sessionID)

        // 첫 폴링: 서버는 이미 abandoned 로 닫아 뒀다(today 는 그 마감 몫 포함).
        store.teamMembers = [offWorkMember(todaySeconds: 1_830, lastSeenAt: t0.addingTimeInterval(3_630))]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

        #expect(store.pendingItems.count == 1)
        let item = store.pendingItems.first
        #expect(item?.autoCloseReason == .sleep)
        #expect(item?.sessionID == sessionID)
        #expect(item?.sessionStartedAt == t0)
        #expect(item?.endedAt == t0.addingTimeInterval(1_800))
        #expect(item?.operation == .stop(durationSeconds: 1_800))
        #expect(store.pendingSleepCloseMarker() == nil)
        // 죽은 세션의 소유 표식 해제 + 로컬 근무를 되살리지 않는다 + 회계는 서버 몫 그대로(추가 가산 없음).
        #expect(store.ownedWorkSessionID == nil)
        #expect(store.startedAt == nil)
        #expect(store.accumulatedSeconds == 1_830)

        // 드레인 후 재수용: 마커가 소거됐으므로 두 번째 수용은 아무것도 싣지 않는다(정정 정확히 1회).
        await store.retryPendingSync()
        store.teamMembers = [offWorkMember(todaySeconds: 1_800, lastSeenAt: t0.addingTimeInterval(3_630))]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
        #expect(store.pendingItems.isEmpty)
    }

    // MARK: - [F4-통보] (4) 마커 없는 abandoned 강하 — 침묵 제거

    @Test func markerlessAbandonedDropNotifiesAndArmsUndo() {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-sync-f4-notify", defaults: defaults)
        defer { cancelTasks(store) }
        let now = t0.addingTimeInterval(7_200)
        store.clock = { now }
        store.start(now: t0)
        let sessionID = store.currentSessionID!
        store.pendingItems = []
        #expect(store.pendingSleepCloseMarker() == nil) // 잠자기가 아니었다(네트워크 단절 강하)

        // 신호 공백 15분 > 스캐빈저 임계 10분 — abandoned 마감의 모양.
        let seen = now.addingTimeInterval(-900)
        store.teamMembers = [offWorkMember(todaySeconds: 6_300, lastSeenAt: seen)]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

        // 침묵 제거: 사용자 문구 + 10분 되돌리기 배너(abandoned 는 복원 대상이 아니라 이것이 유일한 구제).
        #expect(store.syncMessage == WorkTimerStore.remoteAbandonedCloseNotice)
        #expect(store.canUndoAutoClose(now: now))
        #expect(store.lastAutoClosedSessionID == sessionID)
        #expect(store.lastAutoClosedStartedAt == t0)
        #expect(store.lastAutoClosedAt == now)
        // 되돌리기가 누적에서 도로 뺄 몫 = seen − max(시작, KST 자정) = 7_200 − 900 = 6_300.
        #expect(store.lastAutoClosedSeconds == 6_300)
        // sleep 정정은 없다(마커 없음) — 큐 0건, 강하 자체는 기존 그대로.
        #expect(store.pendingItems.isEmpty)
        #expect(store.startedAt == nil)
        #expect(store.accumulatedSeconds == 6_300)
    }

    @Test func freshSeenDropStaysSilent() {
        // 대조군: 신선한 신호의 강하(다른 맥에서 방금 누른 정상 종료가 대표)는 기존대로 조용히 내린다 —
        // 여기에 통보를 붙이면 정당한 종료마다 "연결이 끊겨…" 헛경보가 뜬다.
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-sync-f4-fresh", defaults: defaults)
        defer { cancelTasks(store) }
        let now = t0.addingTimeInterval(7_200)
        store.clock = { now }
        store.start(now: t0)
        store.pendingItems = []
        let messageBefore = store.syncMessage

        store.teamMembers = [offWorkMember(todaySeconds: 7_170, lastSeenAt: now.addingTimeInterval(-30))]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

        #expect(store.startedAt == nil)
        #expect(store.syncMessage == messageBefore)
        #expect(store.lastAutoClosedSessionID == nil)
        #expect(!store.canUndoAutoClose(now: now))
        #expect(store.pendingItems.isEmpty)
    }

    @Test func mismatchedMarkerFallsBackToNotify() {
        // 마커는 있으나 다른 세션의 낡은 관측 — 그 마커로 정정하면 무관한 세션의 마감이 위조된다.
        // 정정은 건너뛰고(마커도 소비하지 않고) F4 통보로 떨어져야 한다.
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-sync-f4-mismatch", defaults: defaults)
        defer { cancelTasks(store) }
        let now = t0.addingTimeInterval(7_200)
        store.clock = { now }
        store.start(now: t0)
        store.pendingItems = []
        let strayMarker = PendingSleepClose(
            sessionID: "dddddddd-0000-0000-0000-000000000004",
            sessionStartedAt: t0.addingTimeInterval(-86_400),
            sleepBeganAt: t0.addingTimeInterval(-82_800),
            lastInputAt: nil
        )
        store.persistPendingSleepClose(strayMarker)

        store.teamMembers = [offWorkMember(todaySeconds: 6_300, lastSeenAt: now.addingTimeInterval(-900))]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

        #expect(store.pendingItems.isEmpty)                       // 낡은 마커로 정정하지 않는다
        #expect(store.syncMessage == WorkTimerStore.remoteAbandonedCloseNotice)
        #expect(store.canUndoAutoClose(now: now))
        #expect(store.pendingSleepCloseMarker() == strayMarker)   // 남의/옛 관측을 지우지도 않는다
    }

    // MARK: - (5) 흡수 세션 강하 — 기존 동작 불변(정정·통보 없음)

    @Test func adoptedSessionDropStaysSilentAndUncorrected() {
        let (_, defaults) = isolatedSuite()
        let store = makeStore(host: "v0236-sync-adopted-drop", defaults: defaults)
        defer { cancelTasks(store) }
        let now = t0.addingTimeInterval(7_200)
        store.clock = { now }
        // 다른 맥이 연 세션을 미러링 중(흡수 상태 — applyRemoteOwnStatus 가 세우는 그 모양).
        store.startedAt = t0
        store.currentSessionID = "bbbbbbbb-0000-0000-0000-000000000002"
        store.adoptedRemoteSession = true
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        // 무관한 옛 마커가 남아 있어도 흡수 강하의 정정 재료가 되면 안 된다.
        let strayMarker = PendingSleepClose(
            sessionID: "cccccccc-0000-0000-0000-000000000003",
            sessionStartedAt: t0,
            sleepBeganAt: t0.addingTimeInterval(600),
            lastInputAt: nil
        )
        store.persistPendingSleepClose(strayMarker)
        let messageBefore = store.syncMessage

        // 흡수가 아니었다면 F4 가 발화했을 낡은 신호 — 흡수 강하는 그래도 침묵해야 한다
        // (그 세션의 주인에게는 자기 맥의 통보/복원 경로가 따로 있다).
        store.teamMembers = [offWorkMember(todaySeconds: 3_600, lastSeenAt: now.addingTimeInterval(-900))]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)

        // 기존 강하 동작 그대로.
        #expect(store.startedAt == nil)
        #expect(store.currentSessionID == nil)
        #expect(!store.adoptedRemoteSession)
        #expect(store.accumulatedSeconds == 3_600)
        #expect(!store.snapshot.isWorking)
        // 정정도 통보도 없다.
        #expect(store.pendingItems.isEmpty)
        #expect(store.syncMessage == messageBefore)
        #expect(store.lastAutoClosedSessionID == nil)
        #expect(!store.canUndoAutoClose(now: now))
        #expect(store.pendingSleepCloseMarker() == strayMarker)
    }
}
