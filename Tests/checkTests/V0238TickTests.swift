import Foundation
import Testing
@testable import check

// v0.2.38 S3-클라이언트 — 근무 틱 통합 RPC `work_tick` 계약 고정(docs/work-tick.md).
//
// 원칙: **전송만 합치고 의미는 바꾸지 않는다.** 30초 폴링의 `sendHeartbeatIfWorking → refreshTeamStatus →
// refreshAwayStateIfNeeded`(+팝오버 열림 시 60초 팀 메타)를 `POST rpc/work_tick` 1건으로 대체하되, 응답 조각은
// 그 세 함수가 소비하던 경로(applyFetchedTeamStatuses / applyAwaySync / 팀 메타 != 가드)로 흘린다.
//  (a) 근무 중 틱 1주기 = work_tick 정확히 1건, 기존 개별 요청 0건, 본문 키 9개·p_heartbeat=true·p_session_id 존재
//  (b) 비근무 틱 = 1건, p_heartbeat=false
//  (c) 의미 동등: 같은 픽스처를 RPC 로 준 스토어와 개별 GET 으로 준 스토어의 최종 상태가 같다(+ 조립 함수 단위 동등)
//  (d) 404/PGRST202 → 같은 틱에서 폴백 다중 호출 즉시, 이후 틱은 폴백 유지
//  (e) v=2 → 폴백
//  (f) 5xx 3회 → 1시간 폴백 → 시계 전진 후 RPC 재시도(성공하면 복귀)
//  (g) 잠자기 마커 경쟁(V0236SyncTests 시나리오 1)을 RPC 경로에서 같은 결과로
//  (h) 팝오버 즉시 새로고침 = p_heartbeat=false 1건(15초 신선도 스로틀 뒤), 폴백은 4 GET 그대로
//  (i) 비근무 away 120초 반영 스로틀 유지 / 근무 중 매 틱 반영, (j) 팀 메타 조각(60초 스로틀·스탬프)
//  (k) 소스 계약: 요청 키 9개 == 마이그레이션 인자 이름, 루프 배선, fast path 배선, 조립 함수 단일화
//
// 요청은 이 파일 전용 스크립트 프로토콜(TickScriptedURLProtocol)로 전수 기록한다 — 공용 URLProtocolStub 은 work_tick
// 을 모르고(빈 200 → 디코드 실패 → 폴백), 기존 테스트 파일은 수정 대상이 아니다.
// 테스트 plist 는 **고정 이름**이다(UUID 접미어 없음 — 실행마다 ~/Library/Preferences 에 빈 plist 를 쌓지 않는다).

private let stubUserID = "00000000-0000-0000-0000-000000000002"
private let teammateUserID = "00000000-0000-0000-0000-000000000003"
private let teamID = URLProtocolStub.stubTeamID
private let deviceIDA = "MAC-A-DEVICE"
private let otherDeviceID = "MAC-B-DEVICE"

/// 시나리오 기준 시각(2026-08-18 05:53 KST 화요일 — V0236SyncTests 와 같은 값, KST 자정에서 6시간 떨어져 클리핑이 개입하지 않는다). 벽시계를 읽지 않는다.
private let t0 = Date(timeIntervalSince1970: 1_787_000_000)

private let workTickPath = "/rest/v1/rpc/work_tick"
private let workStatusesPath = "/rest/v1/work_statuses"
private let workSessionsPath = "/rest/v1/work_sessions"
private let workStatusDevicesPath = "/rest/v1/work_status_devices"
private let awaySyncPath = "/rest/v1/rpc/away_sync"
private let membershipsPath = "/rest/v1/memberships"
private let inviteCodePath = "/rest/v1/rpc/my_team_invite_code"

/// 기존 다중 호출 경로가 내던 요청 전부(하트비트 2 + 팀 상태 GET 4 + away_sync + 팀 메타 2).
private struct LegacyCounts: Equatable, CustomStringConvertible {
    var heartbeat = 0        // POST work_statuses
    var deviceUpsert = 0     // POST work_status_devices
    var statusesGET = 0
    var sessionsGET = 0      // 활성 + 주간(2건/틱)
    var devicesGET = 0
    var awaySync = 0
    var memberships = 0
    var inviteCode = 0
    var total: Int { heartbeat + deviceUpsert + statusesGET + sessionsGET + devicesGET + awaySync + memberships + inviteCode }
    var description: String {
        "hb=\(heartbeat) dev=\(deviceUpsert) st=\(statusesGET) se=\(sessionsGET) dv=\(devicesGET) away=\(awaySync) mem=\(memberships) inv=\(inviteCode)"
    }
}

private func legacyCounts(host: String) -> LegacyCounts {
    var c = LegacyCounts()
    for r in TickScriptedURLProtocol.requests(host: host) {
        switch (r.request.url?.path, r.request.httpMethod) {
        case (workStatusesPath, "POST"): c.heartbeat += 1
        case (workStatusDevicesPath, "POST"): c.deviceUpsert += 1
        case (workStatusesPath, "GET"): c.statusesGET += 1
        case (workSessionsPath, "GET"): c.sessionsGET += 1
        case (workStatusDevicesPath, "GET"): c.devicesGET += 1
        case (awaySyncPath, _): c.awaySync += 1
        case (membershipsPath, "GET"): c.memberships += 1
        case (inviteCodePath, _): c.inviteCode += 1
        default: break
        }
    }
    return c
}

private func tickCount(host: String) -> Int {
    TickScriptedURLProtocol.requests(host: host).filter { $0.request.url?.path == workTickPath && $0.request.httpMethod == "POST" }.count
}

private func tickBodies(host: String) -> [[String: Any]] {
    TickScriptedURLProtocol.requests(host: host)
        .filter { $0.request.url?.path == workTickPath }
        .compactMap { try? JSONSerialization.jsonObject(with: Data($0.body.utf8)) as? [String: Any] }
}

/// 계약 2.1 의 인자 이름 — 이 목록이 곧 "보낸 키 집합" 이다(순서는 마이그레이션 시그니처 순).
private let contractKeys = [
    "p_team_id", "p_heartbeat", "p_session_id", "p_device_id", "p_opened_session",
    "p_last_input_at", "p_seen_at", "p_since", "p_include_meta"
]

// MARK: - 픽스처

private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

/// 근무중 행의 생존신호는 **벽시계 now** 다 — 과거로 두면 스캐빈저(신호 공백 10분+)가 발화해 close RPC + 4 GET 이
/// 비동기로 끼어들어 "기존 요청 0건" 단언이 흔들린다(URLProtocolStub 의 isoNow 와 같은 이유).
private func statusRow(userID: String, status: String, sessionID: String?, lastSeenAt: String, name: String) -> String {
    let session = sessionID.map { "\"\($0)\"" } ?? "null"
    return """
    {"user_id":"\(userID)","status":"\(status)","updated_at":"\(iso(t0))","last_seen_at":"\(lastSeenAt)",
     "active_session_id":\(session),"profiles":{"display_name":"\(name)","avatar_url":null}}
    """
}

private func openSessionRow(id: String, userID: String, startedAt: Date) -> String {
    """
    {"id":"\(id)","user_id":"\(userID)","started_at":"\(iso(startedAt))","ended_at":null,"duration_seconds":null}
    """
}

private func weeklySessionRow(userID: String, startedAt: Date, endedAt: Date) -> String {
    """
    {"user_id":"\(userID)","started_at":"\(iso(startedAt))","ended_at":"\(iso(endedAt))"}
    """
}

private func deviceRow(userID: String, deviceID: String, sessionID: String, lastSeenAt: String, opened: Bool) -> String {
    """
    {"user_id":"\(userID)","device_id":"\(deviceID)","session_id":"\(sessionID)","last_seen_at":"\(lastSeenAt)","opened_session":\(opened)}
    """
}

private func awayJSON(threshold: Int, openSessionID: String? = nil, openStartedAt: Date? = nil) -> String {
    let open: String
    if let openSessionID, let openStartedAt {
        open = """
        {"id":"\(openSessionID)","team_id":"\(teamID)","started_at":"\(iso(openStartedAt))","last_input_at":"\(iso(openStartedAt))","close_eligible":true,"close_due_at":null}
        """
    } else {
        open = "null"
    }
    return """
    {"status":"ok","server_now":"\(iso(t0))","close_threshold_seconds":\(threshold),"backstop_seconds":1800,"freeze_seconds":120,
     "restore_window_seconds":21600,"daily_restore_limit":3,"restorable_reasons":["away","sleep"],
     "restores_used_today":0,"restores_left_today":3,"open_session":\(open),"restorable":null}
    """
}

/// work_tick 응답 조립(계약 2.2 모양). 조각은 기존 GET 이 주던 행과 같은 JSON 이다.
private func tickJSON(
    v: Int = 1,
    statuses: [String],
    active: [String] = [],
    weekly: [String] = [],
    devices: [String] = [],
    away: String = awayJSON(threshold: 600),
    meta: String? = nil,
    heartbeat: String = "null"
) -> String {
    """
    {"v":\(v),"server_now":"\(iso(t0))","team_id":"\(teamID)","heartbeat":\(heartbeat),
     "statuses":[\(statuses.joined(separator: ","))],
     "sessions_active":[\(active.joined(separator: ","))],
     "sessions_weekly":[\(weekly.joined(separator: ","))],
     "sessions_since":"\(iso(TeamWeeklyGoal.koreanWeekStart(for: t0)))",
     "devices":[\(devices.joined(separator: ","))],
     "away":\(away),
     "meta":\(meta ?? "null")}
    """
}

private let pgrst202Body = #"{"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.work_tick(p_team_id, …) in the schema cache"}"#

/// 기존 개별 GET/RPC 경로용 스크립트(폴백 검증·의미 동등 대조군). 활성/주간은 쿼리로 가른다.
private func scriptLegacy(
    host: String,
    statuses: [String],
    active: [String] = [],
    weekly: [String] = [],
    devices: [String] = [],
    away: String = awayJSON(threshold: 600)
) {
    TickScriptedURLProtocol.script(host: host, path: workStatusesPath, method: "GET", body: "[\(statuses.joined(separator: ","))]")
    TickScriptedURLProtocol.script(host: host, path: workSessionsPath, method: "GET", queryContains: "ended_at=is.null", body: "[\(active.joined(separator: ","))]")
    TickScriptedURLProtocol.script(host: host, path: workSessionsPath, method: "GET", queryContains: "ended_at=not.is.null", body: "[\(weekly.joined(separator: ","))]")
    TickScriptedURLProtocol.script(host: host, path: workStatusDevicesPath, method: "GET", body: "[\(devices.joined(separator: ","))]")
    TickScriptedURLProtocol.script(host: host, path: awaySyncPath, method: "POST", body: away)
}

// MARK: - 스토어

/// 주입 시계 상자(V0238ClockTests 의 TestClock 과 같은 모양 — store.clock 클로저가 비격리라 MainActor 클래스로 둘 수 없다).
private final class TickClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

private func fixedDefaults(_ suiteName: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// 스캔이 절대 일어나지 않는 토큰 스토어(빈 임시 홈) — 팝오버 열림 상태를 흉내낼 때 실홈 스캔을 켜지 않게 한다.
@MainActor
private func inertTokenStore(suiteName: String) -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    return TokenUsageStore(
        defaults: fixedDefaults(suiteName + ".token"),
        homeDirectory: tmp.appendingPathComponent("check-v0238-tick-home-\(suiteName)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-v0238-tick-cache-\(suiteName).json", isDirectory: false)
    )
}

/// 스텁 네트워크에 물린 로그인·소속 확정 상태의 스토어(로그인 흐름은 건너뛴다 — 기존 스위트 규약).
@MainActor
private func makeStore(host: String, suite: String, clock: TickClock) -> (WorkTimerStore, SupabaseWorkService) {
    let suiteName = "check-v0238-tick-\(suite)"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: TickScriptedURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: fixedDefaults(suiteName),
        workspaceNotifications: nil,
        tokenUsage: inertTokenStore(suiteName: suiteName)
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: stubUserID)
    store.currentTeamID = teamID
    store.membershipConfirmed = true
    store.deviceID = deviceIDA
    store.clock = { clock.now }
    return (store, service)
}

@MainActor
private func cancelTasks(_ store: WorkTimerStore) {
    store.tickerTask?.cancel()
    store.refreshTask?.cancel()
    store.syncTask?.cancel()
    store.pokePollTask?.cancel()
}

/// 근무 시작(소유 맥). start() 가 큐에 넣는 start 항목은 비운다 — 드레인이 startWork POST 와 refreshTeamStatus 4 GET 을
/// 내면 이 파일이 세는 "기존 요청" 과 섞인다(V0236SyncTests 와 같은 규약).
@MainActor
private func beginOwnedWork(_ store: WorkTimerStore, at: Date) -> String {
    store.start(now: at)
    store.pendingItems = []
    store.syncTask?.cancel()
    return store.currentSessionID!
}

/// 30초 폴링 본문의 통합 구간을 루프 배선 그대로 재현한다(workTickIfPossible → 되맞춤 → finishWorkTick).
/// 루프 자체의 배선은 아래 `refreshLoopWiresTheTickInThatOrder`(소스) + `realLoopSendsWorkTickAndNoLegacyRequests`(실물)가 본다.
@MainActor
private func runTick(_ store: WorkTimerStore) async {
    let tick = await store.workTickIfPossible()
    store.reconcileRealtimeWithWorkState()
    await store.finishWorkTick(tick)
}

@MainActor
private func waitUntil(maxResumes: Int = 3_000, _ condition: () -> Bool) async {
    for _ in 0..<maxResumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

/// 의미 동등 비교 대상(요청서 (c) 항목 + awayServerSupported/누적/스로틀 스탬프).
private struct StoreSnapshot: Equatable, CustomStringConvertible {
    let snapshot: WorkStatusSnapshot
    let teamMembers: [TeamMemberStatus]
    let awayPolicy: AwayPolicy?
    let awayOpenSession: AwayOpenSession?
    let awayRestorable: AwayRestorableSession?
    let awayServerSupported: Bool
    let lastTeamStatusAt: Date
    let lastAwaySyncAt: Date
    let currentSessionID: String?
    let adoptedRemoteSession: Bool
    let startedAt: Date?
    let accumulatedSeconds: Int
    let syncMessage: String

    @MainActor
    init(_ store: WorkTimerStore) {
        snapshot = store.snapshot
        teamMembers = store.teamMembers
        awayPolicy = store.awayPolicy
        awayOpenSession = store.awayOpenSession
        awayRestorable = store.awayRestorable
        awayServerSupported = store.awayServerSupported
        lastTeamStatusAt = store.lastTeamStatusAt
        lastAwaySyncAt = store.lastAwaySyncAt
        currentSessionID = store.currentSessionID
        adoptedRemoteSession = store.adoptedRemoteSession
        startedAt = store.startedAt
        accumulatedSeconds = store.accumulatedSeconds
        syncMessage = store.syncMessage
    }

    var description: String {
        "snapshot=\(snapshot) members=\(teamMembers.count) policy=\(String(describing: awayPolicy)) open=\(String(describing: awayOpenSession)) "
            + "teamAt=\(lastTeamStatusAt) awayAt=\(lastAwaySyncAt) session=\(String(describing: currentSessionID)) adopted=\(adoptedRemoteSession) "
            + "startedAt=\(String(describing: startedAt)) acc=\(accumulatedSeconds) msg=\(syncMessage)"
    }
}

// MARK: - (a)(b) 요청 수·본문

@MainActor
@Suite struct V0238TickTests {
    @Test func workingTickSendsExactlyOneWorkTickAndNoLegacyRequests() async throws {
        let host = "v0238-tick-working"
        let fresh = iso(Date())
        TickScriptedURLProtocol.script(host: host, path: workTickPath, body: tickJSON(
            statuses: [statusRow(userID: teammateUserID, status: "working", sessionID: "30000000-0000-0000-0000-000000000009", lastSeenAt: fresh, name: "영식")],
            active: [openSessionRow(id: "30000000-0000-0000-0000-000000000009", userID: teammateUserID, startedAt: t0.addingTimeInterval(-600))]
        ))
        let clock = TickClock(t0.addingTimeInterval(1_800))
        let (store, _) = makeStore(host: host, suite: "working", clock: clock)
        defer { cancelTasks(store) }
        let sessionID = beginOwnedWork(store, at: t0)

        await runTick(store)

        #expect(tickCount(host: host) == 1, "근무 중 1주기에 work_tick 이 정확히 1건이어야 한다")
        let legacy = legacyCounts(host: host)
        #expect(legacy.total == 0, "통합 뒤에도 기존 개별 요청이 나갔다: \(legacy)")

        let body = try #require(tickBodies(host: host).first)
        #expect(Set(body.keys) == Set(contractKeys), "본문 키 집합이 계약과 다르다: \(body.keys.sorted())")
        #expect(body["p_team_id"] as? String == teamID)
        #expect(body["p_heartbeat"] as? Bool == true)
        #expect(body["p_session_id"] as? String == sessionID, "소유 맥은 p_session_id 를 반드시 싣는다(없으면 흡수 모드가 되어 하트비트가 사라진다)")
        #expect(body["p_device_id"] as? String == deviceIDA)
        #expect(body["p_opened_session"] as? Bool == true, "start() 가 세운 강한 소유는 opened_session=true 로 나간다")
        #expect(body["p_last_input_at"] is String, "start() 가 입력을 세웠으므로 관측이 실려야 한다")
        #expect(body["p_seen_at"] is String)
        #expect(body["p_since"] is String)
        #expect(body["p_include_meta"] as? Bool == false, "팝오버가 닫혀 있으면 메타를 싣지 않는다")
        // 팀 상태는 기존 경로와 같은 함수로 반영됐다(스탬프 + 팀원 목록).
        #expect(store.lastTeamStatusAt == clock.now)
        #expect(store.teamMembers.map(\.id) == [teammateUserID])
        #expect(store.teamMembers.first?.status == .working)
        #expect(store.teamMembers.first?.currentSessionStartedAt == t0.addingTimeInterval(-600))
        // 근무 중이라 away 조각은 매 틱 반영된다.
        #expect(store.awayPolicy?.closeThresholdSeconds == 600)
        #expect(store.awayServerSupported)
        #expect(store.workTickDiagnosticsLine.hasPrefix("work_tick 사용"), "\(store.workTickDiagnosticsLine)")
    }

    @Test func idleTickSendsOneWorkTickWithHeartbeatFalse() async throws {
        let host = "v0238-tick-idle"
        TickScriptedURLProtocol.script(host: host, path: workTickPath, body: tickJSON(statuses: []))
        let clock = TickClock(t0)
        let (store, _) = makeStore(host: host, suite: "idle", clock: clock)
        defer { cancelTasks(store) }
        #expect(store.startedAt == nil)

        await runTick(store)

        #expect(tickCount(host: host) == 1)
        #expect(legacyCounts(host: host).total == 0, "\(legacyCounts(host: host))")
        let body = try #require(tickBodies(host: host).first)
        #expect(Set(body.keys) == Set(contractKeys))
        #expect(body["p_heartbeat"] as? Bool == false, "비근무는 조회만(서버 쓰기 0건)")
        #expect(body["p_session_id"] is NSNull, "nil 도 키를 명시한다(null)")
        #expect(body["p_device_id"] is NSNull)
        #expect(body["p_opened_session"] as? Bool == false)
        #expect(body["p_last_input_at"] is NSNull)
        #expect(store.lastTeamStatusAt == t0)
        #expect(store.syncMessage == "동기화됨")
    }

    /// 흡수 맥(다른 맥이 연 세션을 미러링 중)은 p_session_id 없이 기기·입력만 싣는다 — 서버가 ②′(입력만) 모드로 받는다.
    @Test func adoptedMacTickOmitsSessionIDSoTheServerTakesInputOnlyMode() async throws {
        let host = "v0238-tick-adopted"
        TickScriptedURLProtocol.script(host: host, path: workTickPath, body: tickJSON(statuses: []))
        let clock = TickClock(t0)
        let (store, _) = makeStore(host: host, suite: "adopted", clock: clock)
        defer { cancelTasks(store) }
        store.startedAt = t0.addingTimeInterval(-600)
        store.currentSessionID = "bbbbbbbb-0000-0000-0000-000000000002"
        store.adoptedRemoteSession = true
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 600)
        store.lastMeaningfulInputAt = t0.addingTimeInterval(-30)

        await runTick(store)

        let body = try #require(tickBodies(host: host).first)
        #expect(body["p_heartbeat"] as? Bool == true)
        #expect(body["p_session_id"] is NSNull, "흡수 맥이 세션 ID 를 실으면 그 세션의 생존신호를 대신 보내는 것이 된다(아무도 못 닫는 세션)")
        #expect(body["p_device_id"] as? String == deviceIDA)
        #expect(body["p_opened_session"] as? Bool == false)
        #expect(body["p_last_input_at"] is String)
        #expect(legacyCounts(host: host).total == 0)
    }

    // MARK: - (c) 의미 동등

    @Test func rpcAndLegacyPathsReachTheSameStoreState() async {
        let fresh = iso(Date())
        let serverSession = "50000000-0000-0000-0000-000000000005"
        let statuses = [
            statusRow(userID: stubUserID, status: "working", sessionID: serverSession, lastSeenAt: fresh, name: "나"),
            statusRow(userID: teammateUserID, status: "off_work", sessionID: nil, lastSeenAt: iso(t0.addingTimeInterval(-7_200)), name: "영식")
        ]
        let active = [openSessionRow(id: serverSession, userID: stubUserID, startedAt: t0.addingTimeInterval(-3_600))]
        let weekly = [weeklySessionRow(userID: teammateUserID, startedAt: t0.addingTimeInterval(-90_000), endedAt: t0.addingTimeInterval(-86_400))]
        // 다른 맥이 이 세션을 강하게 주장하는 행 — 흡수 판정·반납 장부가 두 경로에서 같은 입력을 봐야 한다.
        let devices = [deviceRow(userID: stubUserID, deviceID: otherDeviceID, sessionID: serverSession, lastSeenAt: fresh, opened: true)]
        let away = awayJSON(threshold: 900, openSessionID: serverSession, openStartedAt: t0.addingTimeInterval(-3_600))

        let rpcHost = "v0238-tick-equiv-rpc"
        TickScriptedURLProtocol.script(host: rpcHost, path: workTickPath, body: tickJSON(
            statuses: statuses, active: active, weekly: weekly, devices: devices, away: away
        ))
        let legacyHost = "v0238-tick-equiv-legacy"
        TickScriptedURLProtocol.script(host: legacyHost, path: workTickPath, status: 404, body: pgrst202Body)
        scriptLegacy(host: legacyHost, statuses: statuses, active: active, weekly: weekly, devices: devices, away: away)

        let clock = TickClock(t0)
        let (rpcStore, _) = makeStore(host: rpcHost, suite: "equiv-rpc", clock: clock)
        let (legacyStore, _) = makeStore(host: legacyHost, suite: "equiv-legacy", clock: clock)
        defer { cancelTasks(rpcStore); cancelTasks(legacyStore) }

        await runTick(rpcStore)
        await runTick(legacyStore)

        // 전제: 한쪽은 RPC 만, 다른 쪽은 기존 요청만 썼다(같은 결과가 같은 요청에서 나온 것이 아니어야 비교가 의미 있다).
        #expect(tickCount(host: rpcHost) == 1)
        #expect(legacyCounts(host: rpcHost).total == 0)
        #expect(legacyCounts(host: legacyHost).statusesGET == 1)
        #expect(legacyCounts(host: legacyHost).sessionsGET == 2)
        #expect(legacyCounts(host: legacyHost).devicesGET == 1)
        #expect(legacyCounts(host: legacyHost).awaySync == 1)

        let rpc = StoreSnapshot(rpcStore)
        let legacy = StoreSnapshot(legacyStore)
        #expect(rpc == legacy, "RPC:\n\(rpc)\nGET:\n\(legacy)")
        // 시나리오가 실제로 의미 있는 상태에 도달했는지(빈 상태끼리의 동등은 증명이 아니다).
        #expect(rpc.startedAt == t0.addingTimeInterval(-3_600), "서버의 내 열린 세션을 흡수해야 한다")
        #expect(rpc.currentSessionID == serverSession)
        #expect(rpc.adoptedRemoteSession, "소유 ID 가 없는 실행이라 흡수(남의 맥 세션)로 판정돼야 한다")
        #expect(rpc.snapshot.isWorking)
        #expect(rpc.awayPolicy?.closeThresholdSeconds == 900)
        #expect(rpc.awayOpenSession?.sessionID == serverSession)
        #expect(rpc.teamMembers.count == 2)
        #expect(rpc.teamMembers.first { $0.id == stubUserID }?.deviceClaims.first?.deviceID == otherDeviceID)
        #expect(rpc.teamMembers.first { $0.id == stubUserID }?.deviceClaims.first?.openedSession == true)
    }

    /// 조각 단위 동등: 같은 행을 4 GET(fetchTeamStatuses)으로 읽어 조립한 것과 RPC 조각을 assembleTeamStatuses 로
    /// 조립한 것이 주간/오늘 누적까지 같다(같은 now 주입). 조립 함수가 한 벌이라는 사실의 실증.
    @Test func assembleTeamStatusesMatchesFetchTeamStatusesForTheSameRows() async throws {
        // t0(2026-08-18 화요일 05:53 KST)의 주 = 8/17 월요일 00:00 KST 부터. 월요일 10:00~12:00 KST 완료 세션 → 주간 7200, 오늘 0.
        let weekStart = TeamWeeklyGoal.koreanWeekStart(for: t0)
        let statuses = [
            statusRow(userID: teammateUserID, status: "working", sessionID: "30000000-0000-0000-0000-000000000009", lastSeenAt: iso(t0), name: "영식"),
            statusRow(userID: stubUserID, status: "off_work", sessionID: nil, lastSeenAt: iso(t0.addingTimeInterval(-100)), name: "나")
        ]
        let active = [openSessionRow(id: "30000000-0000-0000-0000-000000000009", userID: teammateUserID, startedAt: t0.addingTimeInterval(-1_800))]
        let weekly = [
            weeklySessionRow(userID: teammateUserID, startedAt: weekStart.addingTimeInterval(10 * 3_600), endedAt: weekStart.addingTimeInterval(12 * 3_600)),
            weeklySessionRow(userID: stubUserID, startedAt: t0.addingTimeInterval(-7_200), endedAt: t0.addingTimeInterval(-3_600))
        ]
        let devices = [deviceRow(userID: teammateUserID, deviceID: otherDeviceID, sessionID: "30000000-0000-0000-0000-000000000009", lastSeenAt: iso(t0), opened: true)]

        let host = "v0238-tick-assemble-equiv"
        scriptLegacy(host: host, statuses: statuses, active: active, weekly: weekly, devices: devices)
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: TickScriptedURLProtocol.session())
        let viaGET = try await service.fetchTeamStatuses(accessToken: "access-token", teamID: teamID, now: t0)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(WorkTickResponse.self, from: Data(tickJSON(statuses: statuses, active: active, weekly: weekly, devices: devices).utf8))
        let viaRPC = await service.assembleTeamStatuses(
            rows: response.statuses ?? [], active: response.sessionsActive ?? [], weekly: response.sessionsWeekly ?? [],
            devices: response.devices ?? [], now: t0
        )
        #expect(viaRPC == viaGET)
        #expect(viaRPC.first { $0.id == teammateUserID }?.weeklyDurationSeconds == 7_200)
        #expect(viaRPC.first { $0.id == stubUserID }?.todayDurationSeconds == 3_600)
        #expect(viaRPC.first { $0.id == teammateUserID }?.deviceClaims.count == 1)
    }

    // MARK: - (d)(e) 폴백

    @Test func functionMissingFallsBackWithinTheSameTickAndStaysOnFallback() async {
        let host = "v0238-tick-404"
        let fresh = iso(Date())
        let rows = [statusRow(userID: teammateUserID, status: "working", sessionID: "30000000-0000-0000-0000-000000000009", lastSeenAt: fresh, name: "영식")]
        TickScriptedURLProtocol.script(host: host, path: workTickPath, status: 404, body: pgrst202Body)
        scriptLegacy(host: host, statuses: rows, active: [openSessionRow(id: "30000000-0000-0000-0000-000000000009", userID: teammateUserID, startedAt: t0)])
        let clock = TickClock(t0.addingTimeInterval(600))
        let (store, service) = makeStore(host: host, suite: "404", clock: clock)
        defer { cancelTasks(store) }
        _ = beginOwnedWork(store, at: t0)

        await runTick(store)

        // 같은 틱: RPC 1건 + 기존 7건(하트비트 2 + GET 4 + away 1) — 하트비트 유실 창이 없다.
        #expect(tickCount(host: host) == 1)
        let first = legacyCounts(host: host)
        #expect(first == LegacyCounts(heartbeat: 1, deviceUpsert: 1, statusesGET: 1, sessionsGET: 2, devicesGET: 1, awaySync: 1), "\(first)")
        #expect(store.teamMembers.map(\.id) == [teammateUserID], "폴백 경로가 팀 상태를 실제로 반영했다")
        #expect(store.lastTeamStatusAt == clock.now)
        #expect(store.awayPolicy?.closeThresholdSeconds == 600)
        #expect(service.workTickGate.snapshot.disabledReason?.contains("404") == true)
        #expect(store.workTickDiagnosticsLine.hasPrefix("폴백 고정(404"), "\(store.workTickDiagnosticsLine)")
        // 폴백 사유는 syncMessage 가 아니라 진단에만 — 사용자 문구는 정상 경로 그대로.
        #expect(store.syncMessage == "동기화됨")

        // 다음 틱: RPC 를 다시 시도하지 않고 기존 7건.
        await runTick(store)
        #expect(tickCount(host: host) == 1, "이 실행 동안은 폴백이 유지돼야 한다")
        #expect(legacyCounts(host: host) == LegacyCounts(heartbeat: 2, deviceUpsert: 2, statusesGET: 2, sessionsGET: 4, devicesGET: 2, awaySync: 2), "\(legacyCounts(host: host))")
    }

    @Test func forbiddenDisablesForTheRun() async {
        let host = "v0238-tick-403"
        TickScriptedURLProtocol.script(host: host, path: workTickPath, status: 403, body: #"{"code":"42501","message":"permission denied for function work_tick"}"#)
        scriptLegacy(host: host, statuses: [])
        let clock = TickClock(t0)
        let (store, service) = makeStore(host: host, suite: "403", clock: clock)
        defer { cancelTasks(store) }

        await runTick(store)
        await runTick(store)

        #expect(tickCount(host: host) == 1)
        #expect(legacyCounts(host: host).statusesGET == 2)
        #expect(service.workTickGate.snapshot.disabledReason?.contains("403") == true)
    }

    @Test func contractVersionMismatchFallsBack() async {
        let host = "v0238-tick-v2"
        TickScriptedURLProtocol.script(host: host, path: workTickPath, body: tickJSON(v: 2, statuses: []))
        scriptLegacy(host: host, statuses: [])
        let clock = TickClock(t0)
        let (store, service) = makeStore(host: host, suite: "v2", clock: clock)
        defer { cancelTasks(store) }

        await runTick(store)
        #expect(tickCount(host: host) == 1)
        #expect(legacyCounts(host: host) == LegacyCounts(statusesGET: 1, sessionsGET: 2, devicesGET: 1, awaySync: 1), "\(legacyCounts(host: host))")
        #expect(service.workTickGate.snapshot.disabledReason?.contains("v=2") == true)

        await runTick(store)
        #expect(tickCount(host: host) == 1, "v≠1 은 이 실행 동안 폴백")
    }

    @Test func undecodableBodyFallsBack() async {
        let host = "v0238-tick-garbage"
        TickScriptedURLProtocol.script(host: host, path: workTickPath, body: "[]")
        scriptLegacy(host: host, statuses: [])
        let clock = TickClock(t0)
        let (store, service) = makeStore(host: host, suite: "garbage", clock: clock)
        defer { cancelTasks(store) }

        await runTick(store)
        #expect(tickCount(host: host) == 1)
        #expect(legacyCounts(host: host).statusesGET == 1)
        #expect(service.workTickGate.snapshot.disabledReason == "응답 해석 실패")
    }

    // MARK: - (f) 5xx 연속 3회 → 1시간 폴백 → 재시도

    @Test func threeServerErrorsSuspendForAnHourThenRetry() async {
        let host = "v0238-tick-5xx"
        // 500 ×3 → (정지) → 재시도 때 200. 4번째 응답은 정지 동안 소비되지 않아야 한다.
        TickScriptedURLProtocol.script(host: host, path: workTickPath, responses: [
            (503, #"{"message":"paused"}"#), (503, #"{"message":"paused"}"#), (500, ""),
            (200, tickJSON(statuses: []))
        ])
        scriptLegacy(host: host, statuses: [])
        let clock = TickClock(t0)
        let (store, service) = makeStore(host: host, suite: "5xx", clock: clock)
        defer { cancelTasks(store) }
        #expect(WorkTickGate.transientFailureLimit == 3)
        #expect(WorkTickGate.suspensionSeconds == 3_600)

        for expected in 1...3 {
            await runTick(store)
            #expect(tickCount(host: host) == expected)
            #expect(legacyCounts(host: host).statusesGET == expected, "실패한 틱은 즉시 폴백으로 수행된다")
        }
        let suspended = service.workTickGate.snapshot
        #expect(suspended.consecutiveTransientFailures == 3)
        #expect(suspended.suspendedUntil == t0.addingTimeInterval(3_600))
        #expect(store.workTickDiagnosticsLine.hasPrefix("1시간 폴백(HTTP 500)"), "\(store.workTickDiagnosticsLine)")

        // 정지 중: RPC 시도 0, 폴백만.
        clock.now = t0.addingTimeInterval(1_800)
        await runTick(store)
        #expect(tickCount(host: host) == 3, "1시간 정지 중에는 work_tick 을 두드리지 않는다")
        #expect(legacyCounts(host: host).statusesGET == 4)

        // 1시간 뒤: 다시 시도하고, 성공하면 장부가 초기화된다(폴백 0건).
        clock.now = t0.addingTimeInterval(3_601)
        await runTick(store)
        #expect(tickCount(host: host) == 4, "정지가 풀리면 RPC 를 다시 시도한다")
        #expect(legacyCounts(host: host).statusesGET == 4, "성공한 틱은 폴백을 돌지 않는다")
        let recovered = service.workTickGate.snapshot
        #expect(recovered.suspendedUntil == nil)
        #expect(recovered.consecutiveTransientFailures == 0)
        #expect(recovered.successCount == 1)
        #expect(recovered.fallbackCount == 4)
    }

    /// 네트워크 오류(URLError)도 일시 실패로 세지만 **취소**는 세지 않는다(팝오버 빨리 닫기·루프 취소가 정지를 앞당기면 안 된다).
    @Test func cancellationIsNotCountedAsAFailure() async {
        let host = "v0238-tick-cancel"
        TickScriptedURLProtocol.script(host: host, path: workTickPath, body: tickJSON(statuses: []), delaySeconds: 0.3)
        let clock = TickClock(t0)
        let (store, service) = makeStore(host: host, suite: "cancel", clock: clock)
        defer { cancelTasks(store) }

        let task = Task { @MainActor in await runTick(store) }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value

        #expect(service.workTickGate.snapshot.consecutiveTransientFailures == 0)
        #expect(service.workTickGate.snapshot.disabledReason == nil)
        #expect(service.workTickGate.isAvailable(now: t0))
    }

    // MARK: - (g) 잠자기 마커 경쟁(V0236SyncTests 시나리오 1)을 RPC 경로에서

    @Test func pollAcceptanceBeforeWakeCorrectsAbandonedCloseToSleepViaRPC() async {
        let host = "v0238-tick-sleep-race"
        let clock = TickClock(t0.addingTimeInterval(4_200))
        let (store, _) = makeStore(host: host, suite: "sleep-race", clock: clock)
        defer { cancelTasks(store) }
        store.start(now: t0)
        let sessionID = store.currentSessionID!
        // start 큐는 드레인된 상태로 둔다(수용 지점의 pendingItems 가드 통과).
        store.pendingItems = []
        store.syncTask?.cancel()
        // 오늘 앞선 마감 몫 — 이중 가산 검출의 기준값.
        store.accumulatedSeconds = 1_000
        store.accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: t0)
        store.lastMeaningfulInputAt = t0.addingTimeInterval(1_800)
        store.handleSleep(at: t0.addingTimeInterval(3_600))
        #expect(store.pendingSleepCloseMarker() != nil)

        // 뚜껑 닫고 10분+: 서버 스캐빈저가 abandoned 로 먼저 마감했고, 깨어난 순간 폴링이 didWake 보다 먼저 완주한다.
        // 이번엔 그 스냅샷이 work_tick 응답으로 온다(내 행 off_work, 열린 세션 없음).
        TickScriptedURLProtocol.script(host: host, path: workTickPath, body: tickJSON(
            statuses: [statusRow(userID: stubUserID, status: "off_work", sessionID: nil, lastSeenAt: iso(t0.addingTimeInterval(3_630)), name: "나")]
        ))
        // 정정 stop 의 드레인(PATCH)은 느리게 응답시켜, 아래 단언이 큐가 비워지기 **전** 상태를 보게 한다(V0236 은 await 없이 봤다).
        TickScriptedURLProtocol.script(host: host, path: workSessionsPath, method: "PATCH", body: "[]", delaySeconds: 3)
        await runTick(store)

        #expect(tickCount(host: host) == 1)
        #expect(legacyCounts(host: host).total == 0)
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
        // 회계 정확히 1회: 정정 전 로컬 누적(1_000) + 정정 몫(1_800) = 2_800(서버 today 로 덮은 뒤 또 더하면 안 된다).
        #expect(store.accumulatedSeconds == 2_800)
        // 통보 문구는 같은 패스의 "동기화됨" 정규화에 덮이지 않는다.
        #expect(store.syncMessage == "잠자기로 자동 근무종료됨")

        // 뒤늦게 도착한 didWake 는 무해하다.
        store.handleWake(at: t0.addingTimeInterval(4_200))
        #expect(store.pendingItems.count == 1)
        #expect(store.startedAt == nil)
        #expect(store.accumulatedSeconds == 2_800)
        #expect(store.pendingSleepCloseMarker() == nil)
    }

    // MARK: - (h) 팝오버 즉시 새로고침

    @Test func popoverFastPathSendsOneReadOnlyWorkTick() async throws {
        let host = "v0238-tick-popover"
        TickScriptedURLProtocol.script(host: host, path: workTickPath, body: tickJSON(statuses: []))
        let clock = TickClock(t0)
        let (store, _) = makeStore(host: host, suite: "popover", clock: clock)
        defer { cancelTasks(store) }
        store.hasActivatedStoredSession = true      // 실행 킥이 끝난 스토어(fast path 전제)
        #expect(store.lastTeamStatusAt == .distantPast)

        await store.activateStoredSession()

        #expect(tickCount(host: host) == 1)
        #expect(legacyCounts(host: host).total == 0, "\(legacyCounts(host: host))")
        let body = try #require(tickBodies(host: host).first)
        #expect(body["p_heartbeat"] as? Bool == false, "팝오버 새로고침은 하트비트를 틱 밖에서 추가로 쓰지 않는다")
        #expect(body["p_include_meta"] as? Bool == false)
        #expect(Set(body.keys) == Set(contractKeys))
        #expect(store.lastTeamStatusAt == t0, "성공 수신이 재오픈 스로틀의 근거를 찍는다(Q10)")
        // away 조각은 반영하지 않는다(기존 fast path 도 팀 상태만 받았다).
        #expect(store.awayPolicy == nil)
        #expect(store.lastAwaySyncAt == .distantPast)

        // 15초 안 재오픈 → 요청 0(캐시로 그린다). 16초 뒤 → 1건 더.
        clock.now = t0.addingTimeInterval(14)
        await store.activateStoredSession()
        #expect(tickCount(host: host) == 1)
        clock.now = t0.addingTimeInterval(16)
        await store.activateStoredSession()
        #expect(tickCount(host: host) == 2)
        #expect(legacyCounts(host: host).total == 0)
    }

    @Test func popoverFastPathFallsBackToTheFourGETsWhenTheRPCIsUnavailable() async {
        let host = "v0238-tick-popover-fallback"
        TickScriptedURLProtocol.script(host: host, path: workTickPath, status: 404, body: pgrst202Body)
        scriptLegacy(host: host, statuses: [])
        let clock = TickClock(t0)
        let (store, _) = makeStore(host: host, suite: "popover-fallback", clock: clock)
        defer { cancelTasks(store) }
        store.hasActivatedStoredSession = true

        await store.activateStoredSession()
        #expect(tickCount(host: host) == 1)
        #expect(legacyCounts(host: host) == LegacyCounts(statusesGET: 1, sessionsGET: 2, devicesGET: 1), "\(legacyCounts(host: host))")
        #expect(store.lastTeamStatusAt == t0)

        clock.now = t0.addingTimeInterval(16)
        await store.activateStoredSession()
        #expect(tickCount(host: host) == 1)
        #expect(legacyCounts(host: host).statusesGET == 2)
    }

    // MARK: - (i) away 반영 스로틀 의미 유지

    @Test func idleTicksApplyTheAwayPieceOnlyEveryTwoMinutesWhileWorkingTicksApplyEveryTick() async {
        let host = "v0238-tick-away-throttle"
        TickScriptedURLProtocol.script(host: host, path: workTickPath, responses: [
            (200, tickJSON(statuses: [], away: awayJSON(threshold: 600))),
            (200, tickJSON(statuses: [], away: awayJSON(threshold: 900))),
            (200, tickJSON(statuses: [], away: awayJSON(threshold: 1_200))),
            (200, tickJSON(statuses: [], away: awayJSON(threshold: 1_500)))
        ])
        let clock = TickClock(t0)
        let (store, _) = makeStore(host: host, suite: "away-throttle", clock: clock)
        defer { cancelTasks(store) }
        #expect(WorkTimerStore.awaySyncIdleThrottleSeconds == 120)

        await runTick(store)
        #expect(store.awayPolicy?.closeThresholdSeconds == 600)
        #expect(store.lastAwaySyncAt == t0)

        // 60초 뒤 비근무 틱: 요청은 나가지만(팀 상태 때문에) away 조각은 반영하지 않는다 — 기존엔 away_sync 요청 자체가 없었다.
        clock.now = t0.addingTimeInterval(60)
        await runTick(store)
        #expect(tickCount(host: host) == 2)
        #expect(store.awayPolicy?.closeThresholdSeconds == 600, "비근무 120초 스로틀 안에서는 away 조각을 무시한다")
        #expect(store.lastAwaySyncAt == t0)

        clock.now = t0.addingTimeInterval(120)
        await runTick(store)
        #expect(store.awayPolicy?.closeThresholdSeconds == 1_200)
        #expect(store.lastAwaySyncAt == t0.addingTimeInterval(120))

        // 근무 중이면 매 틱 반영(마감 판정의 두 재료가 그 응답에만 있다).
        clock.now = t0.addingTimeInterval(150)
        _ = beginOwnedWork(store, at: clock.now)
        await runTick(store)
        #expect(store.awayPolicy?.closeThresholdSeconds == 1_500)
        #expect(store.lastAwaySyncAt == t0.addingTimeInterval(150))
    }

    // MARK: - (j) 팀 메타 조각

    @Test func openPopoverRequestsMetaOncePerMinuteAndAppliesIt() async throws {
        let host = "v0238-tick-meta"
        let meta = """
        {"memberships":[{"team_id":"\(teamID)","role":"owner","teams":{"name":"새이름","weekly_goal_hours":45}}],
         "invite_code":[{"invite_code":"ZZZ12345"}]}
        """
        TickScriptedURLProtocol.script(host: host, path: workTickPath, body: tickJSON(statuses: [], meta: meta))
        let clock = TickClock(t0)
        let (store, _) = makeStore(host: host, suite: "meta", clock: clock)
        defer { cancelTasks(store) }
        #expect(WorkTimerStore.teamMetaRefreshThrottleSeconds == 60)

        // 닫힘: 메타 없음.
        await runTick(store)
        #expect(tickBodies(host: host).last?["p_include_meta"] as? Bool == false)

        // 열림 + 스탬프 오래됨: 메타 요청 + 반영 + 스탬프.
        store.isMenuPresented = true
        store.lastTeamMetaRefreshAt = .distantPast
        await runTick(store)
        #expect(tickBodies(host: host).last?["p_include_meta"] as? Bool == true)
        #expect(store.teamName == "새이름")
        #expect(store.teamGoalSeconds == 45 * 3_600)
        #expect(store.teamRole == "owner")
        #expect(store.myTeamInviteCode == "ZZZ12345")
        #expect(store.lastTeamMetaRefreshAt == t0, "setMenuPresented 의 refreshTeamMetaIfStale 과 같은 스탬프를 본다(이중 발사 없음)")
        #expect(legacyCounts(host: host).memberships == 0)
        #expect(legacyCounts(host: host).inviteCode == 0)

        // 60초 안: 메타 없음.
        clock.now = t0.addingTimeInterval(30)
        await runTick(store)
        #expect(tickBodies(host: host).last?["p_include_meta"] as? Bool == false)
        // 60초: 다시.
        clock.now = t0.addingTimeInterval(60)
        await runTick(store)
        #expect(tickBodies(host: host).last?["p_include_meta"] as? Bool == true)
        #expect(store.lastTeamMetaRefreshAt == t0.addingTimeInterval(60))
    }

    /// 목표 write 가 발사 후 일어났으면(세대 변화) 메타의 목표는 낡은 값이라 대입하지 않는다 — refreshTeamMeta 와 같은 스냅백 방지.
    @Test func metaGoalDoesNotSnapBackOverANewerLocalWrite() {
        let host = "v0238-tick-meta-snapback"
        let clock = TickClock(t0)
        let (store, _) = makeStore(host: host, suite: "meta-snapback", clock: clock)
        defer { cancelTasks(store) }
        store.teamGoalSeconds = 50 * 3_600
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let meta = try! decoder.decode(WorkTickResponse.Meta.self, from: Data("""
        {"memberships":[{"team_id":"\(teamID)","role":"member","teams":{"name":"아잉팀","weekly_goal_hours":40}}],"invite_code":[]}
        """.utf8))
        let capturedGeneration = store.teamGoalWriteGeneration
        store.teamGoalWriteGeneration += 1   // 발사 후 사용자가 목표를 바꿨다
        store.applyTeamMeta(meta, goalWriteGeneration: capturedGeneration)
        #expect(store.teamGoalSeconds == 50 * 3_600, "낡은 메타가 방금 쓴 목표를 되돌렸다")
        #expect(store.teamName == "아잉팀")
        #expect(store.teamRole == "member")
        #expect(store.myTeamInviteCode == nil, "invite_code 0행은 nil 확정")
    }

    // MARK: - 실물 루프 배선

    @Test func realLoopSendsWorkTickAndNoLegacyRequests() async {
        let host = "v0238-tick-real-loop"
        let fresh = iso(Date())
        TickScriptedURLProtocol.script(host: host, path: workTickPath, body: tickJSON(
            statuses: [statusRow(userID: teammateUserID, status: "working", sessionID: "30000000-0000-0000-0000-000000000009", lastSeenAt: fresh, name: "영식")]
        ))
        let clock = TickClock(t0)
        let (store, _) = makeStore(host: host, suite: "real-loop", clock: clock)
        defer { cancelTasks(store) }
        _ = beginOwnedWork(store, at: t0)
        store.refreshLoopSliceSeconds = 0.05

        store.startStatusRefreshLoop()
        // 요청이 나간 것만이 아니라 **응답이 반영된 뒤**(신선도 스탬프)까지 기다린 뒤 루프를 내린다 — 전체 스위트에서
        // 메인 액터가 수십 초 굶주리면 고정 대기는 응답 전에 루프를 취소해 in-flight 요청째 날린다(실측 1회).
        await waitUntil { tickCount(host: host) >= 1 && store.lastTeamStatusAt != .distantPast }
        store.refreshTask?.cancel()

        #expect(tickCount(host: host) >= 1, "루프 본문이 work_tick 을 보내지 않았다(배선 붕괴)")
        #expect(legacyCounts(host: host).total == 0, "루프가 기존 개별 요청을 냈다: \(legacyCounts(host: host))")
        #expect(store.teamMembers.map(\.id) == [teammateUserID])
    }

    // MARK: - (k) 소스 계약

    /// 보낸 JSON 의 키 집합 == 계약 2.1 == 마이그레이션 시그니처의 인자 이름. 키 오타는 실서버에서 매 틱 404 → 조용한
    /// 폴백이라(스텁은 초록) 여기서 문자 그대로 못 박는다. nil 도 키를 남긴다(null).
    @Test func requestEncodesExactlyTheNineContractKeys() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let allNil = WorkTickRequest(
            pTeamId: nil, pHeartbeat: false, pSessionId: nil, pDeviceId: nil, pOpenedSession: false,
            pLastInputAt: nil, pSeenAt: "2026-08-31T00:00:00Z", pSince: "2026-08-30T15:00:00Z", pIncludeMeta: false
        )
        let object = try #require(try JSONSerialization.jsonObject(with: encoder.encode(allNil)) as? [String: Any])
        #expect(Set(object.keys) == Set(contractKeys), "인코딩된 키: \(object.keys.sorted())")
        #expect(object["p_team_id"] is NSNull, "p_team_id 는 nil 이어도 키가 있어야 한다(없으면 PGRST202)")
        #expect(object["p_session_id"] is NSNull)
        #expect(object["p_device_id"] is NSNull)
        #expect(object["p_last_input_at"] is NSNull)

        // 서버 정의(supabase/migrations/20260831120000_work_tick_rpc.sql)의 인자 이름과 순서까지 같다.
        let sql = try String(contentsOf: repoURL("supabase/migrations/20260831120000_work_tick_rpc.sql"), encoding: .utf8)
        let signatureStart = try #require(sql.range(of: "create or replace function public.work_tick("))
        let signatureEnd = try #require(sql[signatureStart.upperBound...].range(of: ")"))
        let parameters = sql[signatureStart.upperBound..<signatureEnd.lowerBound]
            .split(separator: "\n")
            .compactMap { $0.split(whereSeparator: \.isWhitespace).first.map(String.init) }
            .filter { $0.hasPrefix("p_") }
        #expect(parameters == contractKeys, "마이그레이션 인자: \(parameters)")
        // CodingKeys 의 camelCase 이름이 snake_case 로 정확히 그 9개가 되는지(구조체 쪽 오타 방지).
        let codingKeys = WorkTickRequest.CodingKeys.allCasesForContract.map(\.stringValue)
        #expect(codingKeys.count == 9)
    }

    /// 폴링 루프 배선: 세 함수 자리에 `workTickIfPossible → 되맞춤 → finishWorkTick` 이 그 순서로 있고, 옛 세 호출은 없다.
    @Test func refreshLoopWiresTheTickInThatOrder() throws {
        let code = strippingComments(try String(contentsOf: sourceURL("WorkTimerStore.swift"), encoding: .utf8))
        let collapsed = code.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(collapsed.contains(
            "await self?.retryPendingSync() let tick = await self?.workTickIfPossible() self?.reconcileRealtimeWithWorkState() if let tick { await self?.finishWorkTick(tick) } await self?.refreshLeaderboardIfVisible()"
        ), "루프 본문 배선이 계약과 다르다")
        #expect(!collapsed.contains("await self?.sendHeartbeatIfWorking()"), "루프가 옛 하트비트를 따로 보낸다(요청 중복)")
        #expect(!collapsed.contains("await self?.refreshTeamStatus()"))
        #expect(!collapsed.contains("await self?.refreshAwayStateIfNeeded()"))
    }

    /// 팝오버 fast path: 15초 신선도 가드 뒤가 refreshTeamStatusOnDemand 다(다른 refreshTeamStatus 호출은 그대로).
    @Test func popoverFastPathCallsTheOnDemandRefresh() throws {
        let code = strippingComments(try String(contentsOf: sourceURL("WorkTimerStoreAuth.swift"), encoding: .utf8))
        let collapsed = code.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(collapsed.contains("guard !teamStatusIsFresh(now: clock()) else { return } await refreshTeamStatusOnDemand() return"))
        #expect(code.components(separatedBy: "refreshTeamStatusOnDemand()").count - 1 == 1)
    }

    /// 조립 함수는 한 벌이다: 서비스에 정의 1 + fetchTeamStatuses 호출 1, 스토어(Sync)의 RPC 경로 호출 1.
    /// 팀 상태 반영도 한 벌이다: applyFetchedTeamStatuses 를 refreshTeamStatus / workTickIfPossible / refreshTeamStatusOnDemand 가 부른다.
    @Test func assemblyAndApplyFunctionsAreSingleSourced() throws {
        let service = strippingComments(try String(contentsOf: sourceURL("SupabaseWorkService.swift"), encoding: .utf8))
        #expect(service.components(separatedBy: "assembleTeamStatuses(").count - 1 == 2)
        #expect(service.components(separatedBy: "return rows.map { row in").count - 1 == 1, "행 → TeamMemberStatus 매핑이 두 벌이다")
        let sync = strippingComments(try String(contentsOf: sourceURL("WorkTimerStoreSync.swift"), encoding: .utf8))
        #expect(sync.components(separatedBy: "service.assembleTeamStatuses(").count - 1 == 1)
        #expect(sync.components(separatedBy: "await applyFetchedTeamStatuses(").count - 1 == 3)
        #expect(sync.contains("static let workTickEnabled = true"), "컴파일 킬스위치가 켜져 있어야 한다")
        #expect(WorkTimerStore.workTickEnabled)
    }
}

// MARK: - 헬퍼 (소스 계약)

private func repoURL(_ relative: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/checkTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent(relative)
}

private func sourceURL(_ name: String) -> URL {
    repoURL("Sources/check/\(name)")
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).
private func strippingComments(_ source: String) -> String {
    var result = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var previous: Character = " "
    let iterator = Array(source)
    var index = 0
    while index < iterator.count {
        let c = iterator[index]
        let next: Character? = index + 1 < iterator.count ? iterator[index + 1] : nil
        if inLineComment {
            if c == "\n" { inLineComment = false; result.append(c) }
        } else if inBlockComment {
            if c == "*", next == "/" { inBlockComment = false; index += 1 }
        } else if inString {
            if c == "\"", previous != "\\" { inString = false }
            result.append(c)
        } else if c == "/", next == "/" {
            inLineComment = true; index += 1
        } else if c == "/", next == "*" {
            inBlockComment = true; index += 1
        } else if c == "\"" {
            inString = true; result.append(c)
        } else {
            result.append(c)
        }
        previous = c
        index += 1
    }
    return result
}

extension WorkTickRequest.CodingKeys {
    /// 계약 순서의 전 케이스(CaseIterable 을 프로덕션 타입에 붙이지 않으려고 테스트 쪽에 둔다).
    static var allCasesForContract: [WorkTickRequest.CodingKeys] {
        [.pTeamId, .pHeartbeat, .pSessionId, .pDeviceId, .pOpenedSession, .pLastInputAt, .pSeenAt, .pSince, .pIncludeMeta]
    }
}

// MARK: - 스크립트 프로토콜 (이 파일 전용 — 호스트별 경로 스크립트 + 요청·본문 전수 기록)

private final class TickScriptedURLProtocol: URLProtocol {
    struct Recorded: @unchecked Sendable {
        let request: URLRequest
        let body: String
    }

    private struct Rule {
        let path: String
        let method: String?
        let queryContains: String?
        var responses: [(status: Int, body: String)]
        let delaySeconds: TimeInterval
        var served = 0
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var rules: [String: [Rule]] = [:]        // host → 규칙(먼저 맞는 것)
    private nonisolated(unsafe) static var recorded: [String: [Recorded]] = [:] // host → 요청

    static func script(host: String, path: String, method: String? = nil, queryContains: String? = nil, status: Int = 200, body: String, delaySeconds: TimeInterval = 0) {
        script(host: host, path: path, method: method, queryContains: queryContains, responses: [(status, body)], delaySeconds: delaySeconds)
    }

    /// 응답 시퀀스: 순서대로 소비하고 마지막 것을 반복한다(5xx ×3 → 200 같은 경로 재현용).
    static func script(host: String, path: String, method: String? = nil, queryContains: String? = nil, responses: [(Int, String)], delaySeconds: TimeInterval = 0) {
        lock.lock(); defer { lock.unlock() }
        let rule = Rule(path: path, method: method, queryContains: queryContains, responses: responses.map { (status: $0.0, body: $0.1) }, delaySeconds: delaySeconds)
        var list = rules[host, default: []]
        // 같은 매처가 이미 있으면 갈아 끼운다(테스트 중 응답을 바꾸는 경우).
        if let index = list.firstIndex(where: { $0.path == path && $0.method == method && $0.queryContains == queryContains }) {
            list[index] = rule
        } else {
            list.append(rule)
        }
        rules[host] = list
    }

    static func requests(host: String) -> [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return recorded[host, default: []]
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TickScriptedURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var isStopped = false

    override func startLoading() {
        let host = request.url?.host ?? ""
        let body = Self.bodyText(from: request)
        var status = 200
        var payload = "[]"
        var delay: TimeInterval = 0
        Self.lock.lock()
        Self.recorded[host, default: []].append(Recorded(request: request, body: body))
        if var list = Self.rules[host],
           let index = list.firstIndex(where: { rule in
               rule.path == request.url?.path
                   && (rule.method == nil || rule.method == request.httpMethod)
                   && (rule.queryContains == nil || request.url?.query?.contains(rule.queryContains!) == true)
           }) {
            let rule = list[index]
            let pick = min(rule.served, rule.responses.count - 1)
            status = rule.responses[pick].status
            payload = rule.responses[pick].body
            delay = rule.delaySeconds
            list[index].served += 1
            Self.rules[host] = list
        }
        Self.lock.unlock()

        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        let data = Data(payload.utf8)
        let deliver = { [weak self] in
            guard let self, !self.isStopped else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() { isStopped = true }

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody { return String(data: body, encoding: .utf8) ?? "" }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
