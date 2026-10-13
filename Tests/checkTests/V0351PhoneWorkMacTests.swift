import Foundation
import Testing
@testable import check
@testable import CheckCore

// 0.3.51 — **폰도 근무를 시작·종료한다**(사장님 결정 2026-10-14, 서버 20261014130000_phone_work.sql). 맥이 지킬 것:
//
//   · 폰이 연 근무는 맥이 **미러링**(흡수)만 한다 — 빼앗지 않고, 잠자기·자리비움·7분 폴백으로 닫지 않는다.
//     서버 cron 이 폰 근무가 살아 있는 동안 last_seen_at 을 매분 민다(대리 하트비트) → 맥의 7분 자동 마감·10분 스캐빈저·
//     흡수 세션 되찾기가 전부 '신선한 신호'를 보고 손대지 않는다. 그 의존을 여기서 대조군과 함께 잰다.
//   · 다른 기기(폰)에서 근무를 끝내면 맥은 **로컬을 내리고 짧게 알린다**("다른 기기에서 근무를 끝냈어요"),
//     **되살리지 않고**(30분 재개 대상 아님), **곧바로 새 근무를 자동으로 열지 않는다**(수동 종료와 같은 억제).
//   · 맥 [근무 시작]이 열린 폰 근무에 23505 로 막혀도 그 폰 근무를 죽이지 않는다(흡수로 끝난다).
//   · 늦게 도착한 맥 종료(0행 PATCH)가 열린 폰 근무의 상태를 off_work 로 덮지 않는다.

private let phoneUserID = "00000000-0000-0000-0000-000000000002"
private let phoneSessionID = "90000000-0000-0000-0000-0000000000f1"
/// KST 2026-08-16 11:13 — 자정 경계에서 멀다(클리핑 개입 없음). 벽시계를 읽지 않는다.
private let t0 = Date(timeIntervalSince1970: 1_787_000_000)

@MainActor
private func makePhoneStore(host: String) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let suiteName = CheckTestScratch.uniqueSuitePath()
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: phoneUserID)
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

/// 폰이 연 근무를 서버가 대리 하트비트로 살려 두는 모양(내 행 working · 신호 `seen`).
private func phoneWorkingMember(startedAt: Date, seen: Date) -> TeamMemberStatus {
    TeamMemberStatus(
        id: phoneUserID,
        name: "영식",
        status: .working,
        updatedAt: seen,
        currentSessionStartedAt: startedAt,
        weeklyDurationSeconds: 0,
        todayDurationSeconds: 0,
        avatarURL: nil,
        lastSeenAt: seen,
        activeSessionID: phoneSessionID,
        openSession: OpenSessionFact(id: phoneSessionID, startedAt: startedAt)
    )
}

private func offWorkMember(seen: Date?, todaySeconds: Int = 3_600) -> TeamMemberStatus {
    TeamMemberStatus(
        id: phoneUserID,
        name: "영식",
        status: .offWork,
        updatedAt: seen,
        currentSessionStartedAt: nil,
        weeklyDurationSeconds: todaySeconds,
        todayDurationSeconds: todaySeconds,
        avatarURL: nil,
        lastSeenAt: seen,
        activeSessionID: nil
    )
}

private func workSessionPatches(host: String) -> [URLRequest] {
    URLProtocolStub.requests(forHost: host).filter { $0.httpMethod == "PATCH" && $0.url?.path == "/rest/v1/work_sessions" }
}

@MainActor
@Suite struct V0351PhoneWorkMacTests {
    // MARK: - 폰에서 끝낸 근무

    @Test func phoneStopOfMirroredSessionStopsLocallyWithNoticeSuppressionAndNoResume() async {
        let host = "v0351-phone-stop-mirrored"
        let store = makePhoneStore(host: host)
        defer { cancelTasks(store) }
        let now = t0.addingTimeInterval(5_400)
        store.clock = { now }
        // 폰이 연 근무를 미러링 중(applyRemoteOwnStatus 가 세우는 흡수 모양).
        store.teamMembers = [phoneWorkingMember(startedAt: t0, seen: now.addingTimeInterval(-40))]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
        #expect(store.adoptedRemoteSession, "폰 근무를 흡수(미러링)하지 않았다")
        #expect(store.startedAt == t0 && store.currentSessionID == phoneSessionID)
        #expect(!store.autoStartSuppressed)

        // 폰 [근무 종료] — 서버는 last_seen_at 을 지금으로 찍는다(결정 ④). 폴링이 그 결과를 가져온다.
        let generation = store.sessionGeneration
        await store.applyFetchedTeamStatuses(
            [offWorkMember(seen: now.addingTimeInterval(-5))],
            generation: generation,
            writeGeneration: store.workStateWriteGeneration
        )

        #expect(store.startedAt == nil && store.currentSessionID == nil && !store.adoptedRemoteSession)
        #expect(!store.snapshot.isWorking)
        // 같은 패스의 "동기화됨" 정규화가 덮지 않았다(통보가 존재한 적이 없게 되지 않는다).
        #expect(store.syncMessage == WorkTimerStore.remoteEndedElsewhereNotice)
        #expect(store.autoStartSuppressed, "폰에서 끝냈는데 맥이 곧바로 새 근무를 자동으로 열 수 있다")
        #expect(store.lastAutoClosedSessionID == nil, "사용자가 끈 근무를 재개 대상으로 올렸다")
        #expect(!store.canResumeRecentlyClosedSession(now: now))
        #expect(store.pendingItems.isEmpty, "맥이 종료를 또 적으려 했다")
        #expect(workSessionPatches(host: host).isEmpty)
    }

    @Test func staleDropOfMirroredSessionStaysSilent() {
        // 대조군: 흡수 세션이 **끊긴 신호**로 내려가면(남의 맥이 죽어 스캐빈저가 닫았다) 그 주인의 일이다 — 침묵, 억제 없음.
        let store = makePhoneStore(host: "v0351-phone-stale-drop")
        defer { cancelTasks(store) }
        let now = t0.addingTimeInterval(5_400)
        store.clock = { now }
        store.teamMembers = [phoneWorkingMember(startedAt: t0, seen: now.addingTimeInterval(-40))]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
        let messageBefore = store.syncMessage
        store.teamMembers = [offWorkMember(seen: now.addingTimeInterval(-900))]
        store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
        #expect(store.startedAt == nil)
        #expect(store.syncMessage == messageBefore)
        #expect(!store.autoStartSuppressed)
    }

    // MARK: - 폰 근무를 죽이지 않는다

    @Test func freshPhoneSessionIsAdoptedNotAutoClosedOnLaunch() async {
        // 로컬이 비근무인 맥(방금 켰다 · 깼다)이 폰 근무를 본다. 대리 하트비트로 신호가 40초 전 → 7분 폴백이 닫지 않고 흡수한다.
        let host = "v0351-phone-fresh-adopt"
        let store = makePhoneStore(host: host)
        defer { cancelTasks(store) }
        let now = t0.addingTimeInterval(3 * 3_600)
        store.clock = { now }
        await store.applyFetchedTeamStatuses(
            [phoneWorkingMember(startedAt: t0, seen: now.addingTimeInterval(-40))],
            generation: store.sessionGeneration,
            writeGeneration: store.workStateWriteGeneration
        )
        #expect(store.adoptedRemoteSession && store.startedAt == t0)
        #expect(workSessionPatches(host: host).isEmpty, "살아 있는 폰 근무를 맥이 닫았다")
        // 흡수 세션은 하트비트를 보내지 않는다(그 근무의 생존은 폰 + 서버 cron 이 낸다).
        await store.sendHeartbeatIfWorking()
        #expect(!URLProtocolStub.requests(forHost: host).contains { $0.url?.path == "/rest/v1/work_statuses" && $0.httpMethod != "GET" })
    }

    @Test func staleSignalControlStillClosesSoTheProxyHeartbeatIsWhatProtectsPhoneWork() async {
        // 대조군(기준선이 달라야 한다): 같은 폰 근무인데 신호가 8분 멈췄다(서버 cron 이 죽었다) → 기존 7분 폴백이 닫는다.
        // 즉 폰 근무를 지키는 것은 맥 코드가 아니라 서버의 매분 대리 하트비트다 — 그것이 멈추면 실패하면 닫히는 쪽으로 간다.
        let host = "v0351-phone-stale-control"
        let store = makePhoneStore(host: host)
        defer { cancelTasks(store) }
        let now = t0.addingTimeInterval(3 * 3_600)
        store.clock = { now }
        await store.applyFetchedTeamStatuses(
            [phoneWorkingMember(startedAt: t0, seen: now.addingTimeInterval(-8 * 60))],
            generation: store.sessionGeneration,
            writeGeneration: store.workStateWriteGeneration
        )
        #expect(!workSessionPatches(host: host).isEmpty, "대조군이 닫지 않았다 — 위 단언이 아무것도 재지 않는다")
    }

    @Test func macStartBlockedByLivePhoneSessionDoesNotKillIt() async {
        // 폰 근무가 열린 채 맥에서 [근무 시작] → 부분 유니크 23505. 복구 경로가 그 폰 근무를 닫지 않아야 한다
        // (close_abandoned 는 신선한 신호를 안 닫고, 끝 시각을 지어내지 않으며, 막은 행을 PATCH 하지 않는다).
        let host = "start-conflict-v0351-phone-blocker"
        URLProtocolStub.resetStartConflictFixture(forHost: host)
        let store = makePhoneStore(host: host)
        defer { cancelTasks(store) }
        store.start()
        await store.syncTask?.value

        let rows = URLProtocolStub.startConflictRows(forHost: host)
        #expect(rows.first { $0.id == URLProtocolStub.startConflictBlockerSessionID }?.isOpen == true,
                "맥 시작의 23505 복구가 열린 폰 근무를 닫았다")
        #expect(rows.filter(\.isOpen).count == 1, "열린 세션이 둘이 됐다")
        #expect(workSessionPatches(host: host).isEmpty, "막은 세션을 PATCH 했다")
        #expect(!URLProtocolStub.bodyText(forHost: host).contains("\"off_work\""), "폰 근무의 상태를 off_work 로 덮었다")
    }

    // MARK: - 0행 종료 꼬리

    @Test func zeroRowStopDoesNotOverwriteAnotherOpenSessionWithOffWork() async throws {
        // 맥이 닫으려던 세션은 이미 닫혔고(0행) 그 사이 폰이 새 근무를 열었다 — 꼬리의 off_work 가 그 근무를
        // '아무도 못 닫는 세션'으로 만들면 안 된다.
        let host = "start-conflict-v0351-zero-row-open"
        URLProtocolStub.resetStartConflictFixture(forHost: host)
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: URLSession(configuration: .stubbed)
        )
        try await service.stopWork(
            accessToken: "access-token", teamID: URLProtocolStub.stubTeamID, userID: URLProtocolStub.startConflictUserID,
            startedAt: t0, endedAt: t0.addingTimeInterval(3_600), durationSeconds: 3_600,
            fallbackSessionID: URLProtocolStub.startConflictClosedSessionID
        )
        let statusWrites = URLProtocolStub.requests(forHost: host).filter { $0.url?.path == "/rest/v1/work_statuses" }
        #expect(statusWrites.isEmpty, "열린 다른 근무가 있는데 off_work 꼬리를 썼다")
        #expect(URLProtocolStub.startConflictRows(forHost: host).first { $0.id == URLProtocolStub.startConflictBlockerSessionID }?.isOpen == true)
    }

    @Test func zeroRowStopStillWritesOffWorkWhenNothingIsOpen() async throws {
        // 대조군: 열린 근무가 없으면 꼬리는 그대로다(기존 바이트·동작 — 잠자기 정정 갈래가 이 길이다).
        let host = "start-conflict-v0351-zero-row-none"
        URLProtocolStub.resetStartConflictFixture(forHost: host, rows: [
            URLProtocolStub.StartConflictRow(id: URLProtocolStub.startConflictClosedSessionID, startedAt: "2026-10-08T01:00:00Z",
                                             endedAt: "2026-10-08T03:00:00Z", durationSeconds: 7_200)
        ])
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: URLSession(configuration: .stubbed)
        )
        try await service.stopWork(
            accessToken: "access-token", teamID: URLProtocolStub.stubTeamID, userID: URLProtocolStub.startConflictUserID,
            startedAt: t0, endedAt: t0.addingTimeInterval(3_600), durationSeconds: 3_600,
            fallbackSessionID: URLProtocolStub.startConflictClosedSessionID
        )
        let statusWrites = URLProtocolStub.requests(forHost: host).filter { $0.url?.path == "/rest/v1/work_statuses" }
        #expect(statusWrites.count == 1, "열린 근무가 없는데 off_work 꼬리를 빠뜨렸다")
        #expect(URLProtocolStub.bodyText(forHost: host).contains("\"off_work\""))
    }
}
