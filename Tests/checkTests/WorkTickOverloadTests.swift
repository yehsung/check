import Foundation
import Testing
@testable import check
@testable import CheckCore

// 2026-10-30 서버 안정화 l1 — work_tick 과부하 대응(docs/work-tick.md 2.5·4.1·4.5).
//
// 2026-10-29 18:54 KST 장애(PGRST003·504·57014)에서 work_tick 이 실패한 틱마다 기존 경로(하트비트 2 + 팀 GET 4 + away 1)로
// 즉시 재수행해 과부하인 서버에 사용자당 요청을 늘렸고, 3회 뒤엔 1시간 동안 그 경로에 묶였다. 실패를 셋으로 가른다:
//  (a) 계약 실패(404·403·v≠1·디코드) → 이 실행 동안 끔(변경 없음)
//  (b) 과부하·도달 불가(502·503·504 · 520~524 · 408·429 · 500+57014/PGRST000~003/53xxx/08xxx/57P0x · 도달 불가 URLError)
//      → 펼치지 않는다 · 백오프 30·60·120·120초 × 지터 · 근무 중이고 마지막 성공 하트비트와 마지막 시도가 둘 다 120초보다
//        오래됐을 때만 레거시 하트비트 1번(검증 단계 K1·K2 — 실패한 시도도 시도로 센다)
//      · away 는 "모른다" 로 접는다 · (c) 의 정지 카운터에 세지 않는다
//  (c) 그 밖의 일시 실패 → 지금처럼 그 틱을 기존 경로로 재수행, 연속 3회면 15분(옛 60분) 정지
// 단언은 **요청 수**로 한다(경로·메서드별 전수 기록). 이 파일 전용 스크립트 프로토콜은 음수 상태를 URLError 로 실패시킨다.
// 테스트 plist 는 고정 이름이다(V0238TickTests 와 같은 규약 — 실행마다 ~/Library/Preferences 에 쌓지 않는다).

private let ovUserID = "00000000-0000-0000-0000-000000000002"
private let ovTeammateID = "00000000-0000-0000-0000-000000000003"
private let ovTeammateSession = "30000000-0000-0000-0000-000000000009"
private let ovTeamID = URLProtocolStub.stubTeamID
private let ovDeviceID = "MAC-A-DEVICE"
/// 기준 시각(V0238TickTests 의 t0 와 같은 값 — KST 자정에서 떨어져 클리핑이 개입하지 않는다).
private let ovT0 = Date(timeIntervalSince1970: 1_787_000_000)

private let ovWorkTickPath = "/rest/v1/rpc/work_tick"
private let ovWorkStatusesPath = "/rest/v1/work_statuses"
private let ovWorkSessionsPath = "/rest/v1/work_sessions"
private let ovDevicesPath = "/rest/v1/work_status_devices"
private let ovAwaySyncPath = "/rest/v1/rpc/away_sync"
private let ovMembershipsPath = "/rest/v1/memberships"

/// 이 파일이 세는 요청 분류. `other` 는 예상 밖의 모든 요청이다(0 이어야 "그 틱의 요청은 이것뿐" 이 성립한다).
private struct OvCounts: Equatable, CustomStringConvertible {
    var tick = 0          // POST rpc/work_tick
    var heartbeat = 0     // POST work_statuses(레거시 하트비트)
    var deviceWrite = 0   // POST/PATCH work_status_devices(기기 주장·입력 보고)
    var teamGET = 0       // GET work_statuses / work_sessions / work_status_devices / memberships
    var awaySync = 0      // rpc/away_sync
    var other: [String] = []
    var description: String {
        "tick=\(tick) hb=\(heartbeat) dev=\(deviceWrite) team=\(teamGET) away=\(awaySync) other=\(other)"
    }
}

private func ovCounts(host: String, since start: Int = 0) -> OvCounts {
    var c = OvCounts()
    for r in OvScriptedURLProtocol.requests(host: host).dropFirst(start) {
        let path = r.url?.path ?? ""
        let method = r.httpMethod ?? ""
        switch (path, method) {
        case (ovWorkTickPath, "POST"): c.tick += 1
        case (ovWorkStatusesPath, "POST"): c.heartbeat += 1
        case (ovDevicesPath, "POST"), (ovDevicesPath, "PATCH"): c.deviceWrite += 1
        case (ovWorkStatusesPath, "GET"), (ovWorkSessionsPath, "GET"), (ovDevicesPath, "GET"), (ovMembershipsPath, "GET"): c.teamGET += 1
        case (ovAwaySyncPath, _): c.awaySync += 1
        case _ where ovIndependentLoopPaths.contains(path): break
        default: c.other.append("\(method) \(path)")
        }
    }
    return c
}

/// 근무 틱과 무관한 독립 루프(콕 폴링 — start() 가 깨운다)의 요청. 틱의 요청 수에 넣지 않는다(ovBeginOwnedWork 가 그 태스크도 끊는다).
private let ovIndependentLoopPaths: Set<String> = ["/rest/v1/rpc/take_pokes", "/rest/v1/rpc/gomoku_inbox"]

private func ovMark(_ host: String) -> Int { OvScriptedURLProtocol.requests(host: host).count }

// MARK: - 픽스처

private func ovISO(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

private func ovAwayJSON(threshold: Int) -> String {
    """
    {"status":"ok","server_now":"\(ovISO(ovT0))","close_threshold_seconds":\(threshold),"backstop_seconds":1800,"freeze_seconds":120,
     "restore_window_seconds":21600,"daily_restore_limit":3,"restorable_reasons":["away","sleep"],
     "restores_used_today":0,"restores_left_today":3,"open_session":null,"restorable":null}
    """
}

/// 성공 응답. 팀원 행의 생존신호는 **벽시계 now** 다(과거면 스캐빈저가 close RPC + 4 GET 을 끼워 요청 수가 흔들린다).
private func ovTickJSON(threshold: Int = 600) -> String {
    let fresh = ovISO(Date())
    return """
    {"v":1,"server_now":"\(ovISO(ovT0))","team_id":"\(ovTeamID)","heartbeat":null,
     "statuses":[{"user_id":"\(ovTeammateID)","status":"working","updated_at":"\(ovISO(ovT0))","last_seen_at":"\(fresh)",
                  "active_session_id":"\(ovTeammateSession)","profiles":{"display_name":"영식","avatar_url":null}}],
     "sessions_active":[{"id":"\(ovTeammateSession)","user_id":"\(ovTeammateID)","started_at":"\(ovISO(ovT0.addingTimeInterval(-600)))","ended_at":null,"duration_seconds":null}],
     "sessions_weekly":[],
     "sessions_since":"\(ovISO(TeamWeeklyGoal.koreanWeekStart(for: ovT0)))",
     "devices":[],
     "away":\(ovAwayJSON(threshold: threshold)),
     "meta":null}
    """
}

private let ov504 = (504, #"{"message":"upstream request timeout"}"#)
/// URLError(.timedOut) 로 실패시키는 표식(음수 상태 = URLError 코드).
private let ovTimedOut = (URLError.Code.timedOut.rawValue, "")

// MARK: - 스토어

private final class OvClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

private func ovDefaults(_ suiteName: String) -> UserDefaults {
    let path = CheckTestScratch.suitePath(named: suiteName)
    let defaults = UserDefaults(suiteName: path)!
    defaults.removePersistentDomain(forName: path)
    return defaults
}

@MainActor
private func ovInertTokenStore(suiteName: String) -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    return TokenUsageStore(
        defaults: ovDefaults(suiteName + ".token"),
        homeDirectory: tmp.appendingPathComponent("check-worktick-overload-home-\(suiteName)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-worktick-overload-cache-\(suiteName).json", isDirectory: false)
    )
}

/// 로그인·소속 확정 상태의 스토어(V0238TickTests.makeStore 와 같은 모양) + 지터 1.0 고정.
@MainActor
private func ovMakeStore(host: String, suite: String, clock: OvClock) -> (WorkTimerStore, SupabaseWorkService) {
    let suiteName = "check-worktick-overload-\(suite)"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: OvScriptedURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: ovDefaults(suiteName),
        workspaceNotifications: nil,
        tokenUsage: ovInertTokenStore(suiteName: suiteName)
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: ovUserID)
    store.currentTeamID = ovTeamID
    store.membershipConfirmed = true
    store.deviceID = ovDeviceID
    store.clock = { clock.now }
    service.workTickGate.jitter = { 1.0 }
    return (store, service)
}

@MainActor
private func ovCancelTasks(_ store: WorkTimerStore) {
    store.tickerTask?.cancel()
    store.refreshTask?.cancel()
    store.syncTask?.cancel()
    store.pokePollTask?.cancel()
}

/// 근무 시작(소유 맥, 서버 확인 도장까지 — V0238TickTests.beginOwnedWork 와 같은 규약).
@MainActor
private func ovBeginOwnedWork(_ store: WorkTimerStore, at: Date) {
    store.start(now: at)
    store.pendingItems = []
    store.syncTask?.cancel()
    store.pokePollTask?.cancel()
    store.confirmedServerSessionID = WorkTimerStore.canonicalSessionID(store.currentSessionID)
}

/// 폴링 본문의 통합 구간(workTickIfPossible → 되맞춤 → finishWorkTick) — V0238TickTests.runTick 과 같다.
@MainActor
private func ovRunTick(_ store: WorkTimerStore) async {
    let tick = await store.workTickIfPossible()
    store.reconcileRealtimeWithWorkState()
    await store.finishWorkTick(tick)
}

@MainActor
@Suite struct WorkTickOverloadTests {
    // MARK: ① 504 한 번 → work_tick 1건뿐(팀 GET·away 0), 하트비트가 신선하면 레거시 하트비트도 0

    @Test func overload504TickSendsOnlyTheWorkTickWhenTheHeartbeatIsFresh() async {
        let host = "worktick-overload-504"
        OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, responses: [(200, ovTickJSON()), ov504])
        let clock = OvClock(ovT0.addingTimeInterval(600))
        let (store, service) = ovMakeStore(host: host, suite: "504", clock: clock)
        defer { ovCancelTasks(store) }
        ovBeginOwnedWork(store, at: ovT0)

        await ovRunTick(store)
        #expect(ovCounts(host: host) == OvCounts(tick: 1), "\(ovCounts(host: host))")
        #expect(store.lastHeartbeatSucceededAt == clock.now, "p_heartbeat=true 인 work_tick 성공이 하트비트 성공 시각을 찍는다")
        #expect(store.awayPolicy?.closeThresholdSeconds == 600)
        #expect(store.syncMessage == "동기화됨")

        clock.now = clock.now.addingTimeInterval(30)
        let mark = ovMark(host)
        await ovRunTick(store)

        let delta = ovCounts(host: host, since: mark)
        #expect(delta == OvCounts(tick: 1), "504 틱은 work_tick 1건뿐이어야 한다(펼침 금지): \(delta)")
        let gate = service.workTickGate.snapshot
        #expect(gate.consecutiveOverloadFailures == 1)
        #expect(gate.backoffUntil == clock.now.addingTimeInterval(30))
        #expect(gate.lastOverloadReason == "HTTP 504")
        #expect(gate.consecutiveTransientFailures == 0, "(b) 는 15분 정지 카운터에 세지 않는다")
        #expect(gate.suspendedUntil == nil)
        #expect(gate.fallbackCount == 0, "(b) 틱은 폴백이 아니다")
        #expect(gate.disabledReason == nil)
        // away 는 "모른다" 로 접혔다(근무 중이라 스로틀 없음) — 마감이 멈춘다.
        #expect(store.awayPolicy == nil)
        #expect(store.awayOpenSession == nil)
        // 사용자 문구는 건드리지 않는다. 진단 줄에만 과부하 대기가 실린다.
        #expect(store.syncMessage == "동기화됨")
        let until = CheckCoreShared.realtimeDiagnosticsTime.string(from: clock.now.addingTimeInterval(30))
        #expect(store.workTickDiagnosticsLine.hasPrefix("work_tick 사용 · 과부하 대기(HTTP 504) \(until) 까지"), "\(store.workTickDiagnosticsLine)")
    }

    // MARK: ② 마지막 하트비트가 120초보다 오래된 근무 중 504 → 레거시 하트비트 정확히 1건, 팀 GET 0

    @Test func overloadSendsExactlyOneLegacyHeartbeatOnlyWhenTheLastSuccessIsOlderThan120Seconds() async {
        let host = "worktick-overload-heartbeat"
        OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, responses: [(200, ovTickJSON()), ov504])
        let start = ovT0.addingTimeInterval(600)
        let clock = OvClock(start)
        let (store, service) = ovMakeStore(host: host, suite: "heartbeat", clock: clock)
        defer { ovCancelTasks(store) }
        ovBeginOwnedWork(store, at: ovT0)

        await ovRunTick(store)                 // 성공 — 하트비트 시각 = start
        #expect(store.lastHeartbeatSucceededAt == start)

        // 정확히 120초: "120초보다 오래됐을 때만" 이므로 아직 보내지 않는다.
        clock.now = start.addingTimeInterval(120)
        var mark = ovMark(host)
        await ovRunTick(store)
        #expect(ovCounts(host: host, since: mark) == OvCounts(tick: 1), "\(ovCounts(host: host, since: mark))")
        #expect(service.workTickGate.snapshot.backoffUntil == start.addingTimeInterval(150))

        // 150초: 백오프가 끝난 첫 틱 — 회복 확인 work_tick 1건이 또 504, 하트비트는 150초 묵었다 → 레거시 하트비트 한 번(상태 + 기기 주장).
        clock.now = start.addingTimeInterval(150)
        mark = ovMark(host)
        await ovRunTick(store)
        let stale = ovCounts(host: host, since: mark)
        #expect(stale == OvCounts(tick: 1, heartbeat: 1, deviceWrite: 1), "팀 GET·away 없이 하트비트 1건만: \(stale)")
        #expect(store.lastHeartbeatSucceededAt == clock.now, "레거시 하트비트 성공도 성공 시각을 찍는다")
        #expect(service.workTickGate.snapshot.consecutiveOverloadFailures == 2)
        #expect(service.workTickGate.snapshot.backoffUntil == start.addingTimeInterval(210))

        // 180초: 백오프 중 + 하트비트 30초 전 → 요청 0건.
        clock.now = start.addingTimeInterval(180)
        mark = ovMark(host)
        await ovRunTick(store)
        #expect(ovCounts(host: host, since: mark) == OvCounts(), "백오프 중 신선한 하트비트면 아무것도 내지 않는다: \(ovCounts(host: host, since: mark))")
        #expect(service.workTickGate.snapshot.fallbackCount == 0)
    }

    /// K1 — 구조 하트비트는 **시도**로도 묶인다: 실패한 시도도 시도로 세어, 장애가 이어지는 동안 120초에 한 번만 나간다.
    /// (성공만 보던 판은 120초 뒤부터 매 틱 상태 + 기기 주장 2건을 내 평시 work_tick 보다 요청이 늘었다.)
    @Test func aFailedOverloadHeartbeatIsRetriedOnlyAfter120SecondsFromTheLastAttempt() async {
        let host = "worktick-overload-heartbeat-fails"
        OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, responses: [ov504])
        OvScriptedURLProtocol.script(host: host, path: ovWorkStatusesPath, method: "POST", responses: [ov504])
        let start = ovT0.addingTimeInterval(600)
        let clock = OvClock(start)
        let (store, service) = ovMakeStore(host: host, suite: "heartbeat-fails", clock: clock)
        defer { ovCancelTasks(store) }
        ovBeginOwnedWork(store, at: ovT0)
        #expect(store.lastHeartbeatSucceededAt == .distantPast)

        await ovRunTick(store)
        #expect(ovCounts(host: host) == OvCounts(tick: 1, heartbeat: 1, deviceWrite: 1), "\(ovCounts(host: host))")
        #expect(store.lastHeartbeatSucceededAt == .distantPast, "실패한 하트비트는 성공 시각을 찍지 않는다")
        #expect(store.lastHeartbeatAttemptAt == start, "실패해도 시도 시각은 찍는다")

        // (시각, 그 틱의 기대 요청) — 백오프 30·60·120 과 시도 120초 규칙이 겹친다. 성공은 한 번도 없다.
        let steps: [(at: TimeInterval, expected: OvCounts)] = [
            (15, OvCounts()),                                        // 백오프 안 · 시도 15초 전 → 0
            (30, OvCounts(tick: 1)),                                 // 백오프 끝 → 회복 확인 1건, 시도 30초 전 → 하트비트 없음
            (60, OvCounts()),                                        // 백오프(60초) 안
            (90, OvCounts(tick: 1)),                                 // 회복 확인 1건 · 시도 90초 전
            (120, OvCounts()),                                       // 시도 정확히 120초 전 → "보다 오래" 가 아니다
            (150, OvCounts(heartbeat: 1, deviceWrite: 1)),           // 시도 150초 전 → 한 번 더(팀 조회 없이)
            (180, OvCounts()),
            (210, OvCounts(tick: 1)),                                // 백오프(120초) 끝 · 시도 60초 전
            (240, OvCounts()), (270, OvCounts()),                    // 시도 90·120초 전
            (300, OvCounts(heartbeat: 1, deviceWrite: 1)),
        ]
        for step in steps {
            clock.now = start.addingTimeInterval(step.at)
            let mark = ovMark(host)
            await ovRunTick(store)
            #expect(ovCounts(host: host, since: mark) == step.expected, "t+\(step.at): \(ovCounts(host: host, since: mark))")
        }
        // 5분 동안 레거시 하트비트 시도 3번(0·150·300초) — 30초 틱마다였다면 9번이다.
        #expect(ovCounts(host: host).heartbeat == 3, "\(ovCounts(host: host))")
        #expect(service.workTickGate.snapshot.fallbackCount == 0)
        #expect(service.workTickGate.snapshot.consecutiveTransientFailures == 0)
    }

    /// 반박 초점 — 구조 하트비트는 `sendHeartbeatIfWorking` 의 게이트를 그대로 탄다: 흡수 맥·확인 전 세션은 공유 행
    /// (work_statuses POST = 세션 생존신호)을 **한 건도** 쓰지 않고 자기 기기 행의 입력 보고만 한다(유령 하트비트 금지).
    @Test func overloadRescueNeverSendsAGhostHeartbeatFromAdoptedOrUnconfirmedMacs() async {
        for adopted in [true, false] {
            let host = "worktick-overload-ghost-\(adopted ? "adopted" : "unconfirmed")"
            OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, responses: [ov504])
            let clock = OvClock(ovT0.addingTimeInterval(600))
            let (store, service) = ovMakeStore(host: host, suite: "ghost-\(adopted)", clock: clock)
            defer { ovCancelTasks(store) }
            store.start(now: ovT0)
            store.pendingItems = []
            store.syncTask?.cancel()
            store.pokePollTask?.cancel()
            if adopted { store.adoptedRemoteSession = true }
            #expect(store.confirmedSessionID == nil || adopted, "확인 도장 없이 시작 — 확인 전 세션")
            store.awayServerSupported = true
            store.inputSessionUsable = { true }
            store.meaningfulIdleSeconds = { 5 }
            let mark = ovMark(host)

            await ovRunTick(store)
            let first = ovCounts(host: host, since: mark)
            #expect(first == OvCounts(tick: 1, deviceWrite: 1), "\(adopted ? "흡수" : "확인 전") 맥: 입력 보고만, 상태 하트비트 0: \(first)")
            #expect(service.workTickGate.snapshot.consecutiveOverloadFailures == 1)

            // 백오프 중 다음 틱: 입력 보고가 방금 성공했으니(성공 = 시도) 아무것도 내지 않는다.
            clock.now = clock.now.addingTimeInterval(15)
            let mark2 = ovMark(host)
            await ovRunTick(store)
            #expect(ovCounts(host: host, since: mark2) == OvCounts(), "\(ovCounts(host: host, since: mark2))")
        }
    }

    // MARK: ③ 연속 504 → 30·60·120·120초 백오프, 백오프 중 work_tick 0, 회복하면 카운터 0

    @Test func consecutiveOverloadBacksOffThirtySixtyThenCapsAtOneTwentyAndRecovers() async {
        let host = "worktick-overload-backoff"
        OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, responses: [ov504, ov504, ov504, ov504, (200, ovTickJSON())])
        let clock = OvClock(ovT0)
        let (store, service) = ovMakeStore(host: host, suite: "backoff", clock: clock)
        defer { ovCancelTasks(store) }

        // (시도 시각, 기대 백오프 길이, 백오프 중 한 번 더 도는 틱의 시각)
        let steps: [(attempt: TimeInterval, backoff: TimeInterval, inside: TimeInterval)] = [
            (0, 30, 15), (30, 60, 60), (90, 120, 150), (210, 120, 300)
        ]
        for (index, step) in steps.enumerated() {
            clock.now = ovT0.addingTimeInterval(step.attempt)
            await ovRunTick(store)
            #expect(ovCounts(host: host).tick == index + 1)
            let gate = service.workTickGate.snapshot
            #expect(gate.consecutiveOverloadFailures == index + 1)
            #expect(gate.backoffUntil == clock.now.addingTimeInterval(step.backoff), "k=\(index + 1) 의 백오프는 \(step.backoff)초여야 한다")

            clock.now = ovT0.addingTimeInterval(step.inside)
            await ovRunTick(store)
            #expect(ovCounts(host: host).tick == index + 1, "백오프 중 틱은 work_tick 을 시도하지 않는다(t+\(step.inside))")
        }
        #expect(ovCounts(host: host) == OvCounts(tick: 4), "비근무 과부하 동안 팀 GET·away·하트비트 0: \(ovCounts(host: host))")

        // 330초: 백오프가 끝난 첫 틱의 work_tick 1건이 회복을 확인한다 → 장부가 비고 다음 틱부터 평소대로.
        clock.now = ovT0.addingTimeInterval(330)
        await ovRunTick(store)
        let recovered = service.workTickGate.snapshot
        #expect(recovered.consecutiveOverloadFailures == 0)
        #expect(recovered.backoffUntil == nil)
        #expect(recovered.lastOverloadReason == nil)
        #expect(recovered.consecutiveTransientFailures == 0)
        #expect(recovered.successCount == 1)
        #expect(recovered.fallbackCount == 0)
        #expect(store.teamMembers.map(\.id) == [ovTeammateID], "회복 틱의 팀 조각이 반영됐다")
        #expect(store.workTickDiagnosticsLine.hasPrefix("work_tick 사용 · 성공 1회"), "\(store.workTickDiagnosticsLine)")

        clock.now = ovT0.addingTimeInterval(360)
        await ovRunTick(store)
        #expect(ovCounts(host: host) == OvCounts(tick: 6), "\(ovCounts(host: host))")
    }

    /// 지터는 주입이고 범위 밖 값은 0.8~1.2 로 눌린다(주입 실수로 백오프가 0·무한이 되지 않게).
    @Test func backoffJitterIsInjectableAndClamped() {
        let gate = WorkTickGate()
        gate.jitter = { 1.2 }
        gate.recordOverloadFailure(reason: "HTTP 504", at: ovT0)
        #expect(gate.snapshot.backoffUntil == ovT0.addingTimeInterval(36))
        #expect(gate.availability(now: ovT0.addingTimeInterval(35)) == .backingOff(until: ovT0.addingTimeInterval(36)))
        #expect(!gate.isAvailable(now: ovT0.addingTimeInterval(35)))
        #expect(gate.isAvailable(now: ovT0.addingTimeInterval(36)))

        gate.jitter = { 0.1 }
        gate.recordOverloadFailure(reason: "HTTP 504", at: ovT0)
        #expect(gate.snapshot.backoffUntil == ovT0.addingTimeInterval(60 * 0.8), "k=2, 지터 0.1 → 0.8 로 눌림")
        gate.jitter = { 9 }
        for _ in 0..<10 { gate.recordOverloadFailure(reason: "HTTP 504", at: ovT0) }
        #expect(gate.snapshot.backoffUntil == ovT0.addingTimeInterval(120 * 1.2), "상한 120초 × 1.2")
        #expect(gate.snapshot.consecutiveTransientFailures == 0)
        #expect(gate.snapshot.suspendedUntil == nil)
    }

    // MARK: ④ URLError 시간 초과도 ①과 같다 · 500 은 코드로 갈린다

    @Test func urlErrorTimedOutIsOverloadLikeA504() async {
        let host = "worktick-overload-timeout"
        OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, responses: [(200, ovTickJSON()), ovTimedOut])
        let clock = OvClock(ovT0.addingTimeInterval(600))
        let (store, service) = ovMakeStore(host: host, suite: "timeout", clock: clock)
        defer { ovCancelTasks(store) }
        ovBeginOwnedWork(store, at: ovT0)

        await ovRunTick(store)
        clock.now = clock.now.addingTimeInterval(30)
        let mark = ovMark(host)
        await ovRunTick(store)

        #expect(ovCounts(host: host, since: mark) == OvCounts(tick: 1), "\(ovCounts(host: host, since: mark))")
        let gate = service.workTickGate.snapshot
        #expect(gate.consecutiveOverloadFailures == 1)
        #expect(gate.lastOverloadReason == "URLError \(URLError.Code.timedOut.rawValue)")
        #expect(gate.consecutiveTransientFailures == 0)
        #expect(gate.fallbackCount == 0)
        #expect(store.awayPolicy == nil)
    }

    @Test func server500WithStatementTimeoutIsOverload() async {
        let host = "worktick-overload-57014"
        OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, status: 500, body: #"{"code":"57014","message":"canceling statement due to statement timeout"}"#)
        let clock = OvClock(ovT0)
        let (store, service) = ovMakeStore(host: host, suite: "57014", clock: clock)
        defer { ovCancelTasks(store) }

        await ovRunTick(store)
        #expect(ovCounts(host: host) == OvCounts(tick: 1), "\(ovCounts(host: host))")
        #expect(service.workTickGate.snapshot.consecutiveOverloadFailures == 1)
        #expect(service.workTickGate.snapshot.lastOverloadReason == "HTTP 500 57014")
        #expect(service.workTickGate.snapshot.consecutiveTransientFailures == 0)
    }

    /// K2 — 429(속도 제한)·408 은 서비스 층이 `.rejected` 로, 522(Cloudflare 원점 연결 시간 초과)는 `.serverError` 로 던진다.
    /// 어느 쪽이든 그 틱은 work_tick 1건뿐이고(펼침 금지) 백오프가 선다.
    @Test func rateLimitAndCloudflareOriginTimeoutAreOverloadOnTheStorePath() async {
        for (status, body) in [(429, #"{"message":"Too Many Requests"}"#), (408, ""), (522, "<html>origin timeout</html>")] {
            let host = "worktick-overload-k2-\(status)"
            OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, status: status, body: body)
            let clock = OvClock(ovT0.addingTimeInterval(600))
            let (store, service) = ovMakeStore(host: host, suite: "k2-\(status)", clock: clock)
            defer { ovCancelTasks(store) }
            ovBeginOwnedWork(store, at: ovT0)
            store.lastHeartbeatSucceededAt = clock.now.addingTimeInterval(-10)   // 신선한 하트비트 — 구조 하트비트 없음

            await ovRunTick(store)
            #expect(ovCounts(host: host) == OvCounts(tick: 1), "HTTP \(status): \(ovCounts(host: host))")
            let gate = service.workTickGate.snapshot
            #expect(gate.consecutiveOverloadFailures == 1, "HTTP \(status)")
            #expect(gate.lastOverloadReason?.hasPrefix("HTTP \(status)") == true, "\(gate.lastOverloadReason ?? "nil")")
            #expect(gate.consecutiveTransientFailures == 0, "HTTP \(status) 는 (c) 카운터에 세지 않는다")
            #expect(gate.fallbackCount == 0)
        }
    }

    /// 과부하 코드가 아닌 500 은 (c) — 지금 규칙 그대로 그 틱을 기존 경로로 재수행한다(하트비트 유실 창 금지).
    @Test func server500WithAnotherCodeIsTransientAndFallsBackWithinTheTick() async {
        let host = "worktick-overload-500-other"
        OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, status: 500, body: #"{"code":"XX000","message":"internal"}"#)
        let clock = OvClock(ovT0.addingTimeInterval(600))
        let (store, service) = ovMakeStore(host: host, suite: "500-other", clock: clock)
        defer { ovCancelTasks(store) }
        ovBeginOwnedWork(store, at: ovT0)

        await ovRunTick(store)
        let counts = ovCounts(host: host)
        #expect(counts == OvCounts(tick: 1, heartbeat: 1, deviceWrite: 1, teamGET: 4, awaySync: 1), "\(counts)")
        let gate = service.workTickGate.snapshot
        #expect(gate.consecutiveTransientFailures == 1)
        #expect(gate.lastTransientReason == "HTTP 500 XX000")
        #expect(gate.consecutiveOverloadFailures == 0)
        #expect(gate.backoffUntil == nil)
        #expect(gate.fallbackCount == 1)
    }

    /// 분류표 전수(상태·코드·URLError) — 스토어 경로가 쓰는 바로 그 함수.
    @Test func overloadClassificationTable() {
        for status in [502, 503, 504] {
            #expect(WorkTickGate.isOverload(.serverError(status: status, code: nil)), "\(status)")
            #expect(WorkTickGate.isOverload(.serverError(status: status, code: "XX000")), "\(status) 은 코드와 무관")
        }
        for code in ["57014", "PGRST000", "PGRST001", "PGRST002", "PGRST003", "53300", "53100", "08006", "08001", "57P01", "57P03"] {
            #expect(WorkTickGate.isOverload(.serverError(status: 500, code: code)), "500 \(code)")
        }
        for code in [nil, "XX000", "P0001", "PGRST004", "PGRST116", "42883", "57P", "5300", "57014x"] as [String?] {
            #expect(!WorkTickGate.isOverload(.serverError(status: 500, code: code)), "500 \(code ?? "nil")")
        }
        #expect(!WorkTickGate.isOverload(.serverError(status: 501, code: "57014")))
        // K2 — Cloudflare 원점 오류·시간 초과(520~524)와 408·429 도 (b). 그 바깥 이웃은 (c).
        for status in 520...524 {
            #expect(WorkTickGate.isOverload(.serverError(status: status, code: nil)), "\(status)")
        }
        for status in [505, 519, 525, 530] {
            #expect(!WorkTickGate.isOverload(.serverError(status: status, code: nil)), "\(status)")
        }
        #expect(WorkTickGate.isOverload(.rejected(status: 429, code: nil)))
        #expect(WorkTickGate.isOverload(.rejected(status: 408, code: nil)))
        #expect(WorkTickGate.isOverload(.rejected(status: 429, code: "XX000")), "429 는 코드와 무관")
        #expect(!WorkTickGate.isOverload(.rejected(status: 400, code: "57014")))
        #expect(!WorkTickGate.isOverload(.rejected(status: 409, code: nil)))
        #expect(!WorkTickGate.isOverload(.rejected(status: 400, code: "22023")))
        #expect(!WorkTickGate.isOverload(.rejected(status: -1, code: nil)))
        #expect(!WorkTickGate.isOverload(.functionMissing(code: "PGRST202")))
        #expect(!WorkTickGate.isOverload(.forbidden(code: "42501")))
        #expect(!WorkTickGate.isOverload(.undecodable))
        #expect(!WorkTickGate.isOverload(.contractMismatch(version: 2)))
        let reachability: [URLError.Code] = [.timedOut, .cannotConnectToHost, .networkConnectionLost, .cannotFindHost,
                                             .dnsLookupFailed, .notConnectedToInternet, .secureConnectionFailed]
        for code in reachability { #expect(WorkTickGate.isOverload(URLError(code)), "\(code.rawValue)") }
        for code in [URLError.Code.badServerResponse, .cancelled, .badURL, .userAuthenticationRequired] {
            #expect(!WorkTickGate.isOverload(URLError(code)), "\(code.rawValue)")
        }
    }

    // MARK: ⑤ (c) 3회 → 15분 정지 + 기존 경로 재수행, 15분 뒤 다시 work_tick · (b) 는 그 카운터에 세지도 지우지도 않는다

    @Test func transientFailuresSuspendForFifteenMinutesAndOverloadNeitherCountsNorResets() async {
        let host = "worktick-overload-mixed"
        let transient = (500, #"{"code":"XX000","message":"internal"}"#)
        OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, responses: [transient, transient, ov504, transient, (200, ovTickJSON())])
        let clock = OvClock(ovT0)
        let (store, service) = ovMakeStore(host: host, suite: "mixed", clock: clock)
        defer { ovCancelTasks(store) }
        #expect(WorkTickGate.suspensionSeconds == 15 * 60)

        await ovRunTick(store)                                   // (c) 1 — 폴백 재수행
        clock.now = ovT0.addingTimeInterval(30)
        await ovRunTick(store)                                   // (c) 2 — 폴백 재수행
        #expect(ovCounts(host: host).teamGET == 8, "(c) 틱은 지금처럼 즉시 기존 경로로 재수행한다")
        clock.now = ovT0.addingTimeInterval(60)
        var mark = ovMark(host)
        await ovRunTick(store)                                   // (b) — 펼치지 않음
        #expect(ovCounts(host: host, since: mark) == OvCounts(tick: 1), "\(ovCounts(host: host, since: mark))")
        #expect(service.workTickGate.snapshot.consecutiveTransientFailures == 2, "(b) 는 (c) 카운터를 지우지 않는다")
        #expect(service.workTickGate.snapshot.suspendedUntil == nil, "(b) 는 (c) 카운터에 세지 않는다")

        clock.now = ovT0.addingTimeInterval(90)                  // 백오프(60+30=90) 끝
        await ovRunTick(store)                                   // (c) 3 → 15분 정지
        let suspended = service.workTickGate.snapshot
        #expect(suspended.consecutiveTransientFailures == 3)
        #expect(suspended.suspendedUntil == clock.now.addingTimeInterval(900))
        #expect(store.workTickDiagnosticsLine.hasPrefix("15분 폴백(HTTP 500 XX000)"), "\(store.workTickDiagnosticsLine)")

        // 정지 중: work_tick 0, 기존 경로(팀 GET 4 + away 1)로 수행 — 지금과 같다.
        clock.now = ovT0.addingTimeInterval(90 + 600)
        mark = ovMark(host)
        await ovRunTick(store)
        #expect(ovCounts(host: host, since: mark) == OvCounts(teamGET: 4, awaySync: 1), "\(ovCounts(host: host, since: mark))")

        // 15분 뒤: 다시 work_tick, 성공하면 장부가 빈다.
        clock.now = ovT0.addingTimeInterval(90 + 901)
        mark = ovMark(host)
        await ovRunTick(store)
        #expect(ovCounts(host: host, since: mark) == OvCounts(tick: 1), "\(ovCounts(host: host, since: mark))")
        let recovered = service.workTickGate.snapshot
        #expect(recovered.suspendedUntil == nil)
        #expect(recovered.consecutiveTransientFailures == 0)
        #expect(recovered.consecutiveOverloadFailures == 0)
        #expect(recovered.successCount == 1)
    }

    // MARK: ⑥ 404 → 이 실행 동안 끔(회귀 없음)

    @Test func functionMissingStillDisablesForTheRunWithoutBackoff() async {
        let host = "worktick-overload-404"
        OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, status: 404,
                                     body: #"{"code":"PGRST202","message":"Could not find the function public.work_tick"}"#)
        let clock = OvClock(ovT0)
        let (store, service) = ovMakeStore(host: host, suite: "404", clock: clock)
        defer { ovCancelTasks(store) }

        await ovRunTick(store)
        #expect(ovCounts(host: host) == OvCounts(tick: 1, teamGET: 4, awaySync: 1), "같은 틱에 기존 경로로 재수행: \(ovCounts(host: host))")
        clock.now = ovT0.addingTimeInterval(30)
        await ovRunTick(store)
        #expect(ovCounts(host: host).tick == 1, "이 실행 동안 work_tick 을 다시 시도하지 않는다")
        let gate = service.workTickGate.snapshot
        #expect(gate.disabledReason?.contains("404") == true)
        #expect(gate.consecutiveOverloadFailures == 0)
        #expect(gate.backoffUntil == nil)
        #expect(service.workTickGate.availability(now: clock.now) == .disabled)
    }

    // MARK: ⑦ (b) 뒤 away 는 nil 로 접힌다 — 비근무 120초 스로틀 안이면 건드리지 않는다

    @Test func overloadFoldsAwayToUnknownButRespectsTheIdleThrottle() async {
        let host = "worktick-overload-away-idle"
        OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, responses: [(200, ovTickJSON(threshold: 1_500)), ov504])
        let clock = OvClock(ovT0)
        let (store, _) = ovMakeStore(host: host, suite: "away-idle", clock: clock)
        defer { ovCancelTasks(store) }

        await ovRunTick(store)
        #expect(store.awayPolicy?.closeThresholdSeconds == 1_500)
        #expect(store.lastAwaySyncAt == ovT0)

        // 30초 뒤 504: 비근무 스로틀(120초) 안 — 정책·스탬프 그대로.
        clock.now = ovT0.addingTimeInterval(30)
        await ovRunTick(store)
        #expect(store.awayPolicy?.closeThresholdSeconds == 1_500, "스로틀 안이면 접기도 하지 않는다")
        #expect(store.lastAwaySyncAt == ovT0)

        // 150초 뒤(백오프 끝 · 스로틀 밖) 504 다시: "모른다" 로 접고 스탬프를 찍는다.
        clock.now = ovT0.addingTimeInterval(150)
        await ovRunTick(store)
        #expect(store.awayPolicy == nil)
        #expect(store.awayOpenSession == nil)
        #expect(store.lastAwaySyncAt == clock.now)
        #expect(ovCounts(host: host) == OvCounts(tick: 3), "away_sync 요청은 한 건도 없다: \(ovCounts(host: host))")
    }

    /// 백오프 중 틱(요청 0)도 같은 접기를 하고, 세션이 없으면 통째로 비운다(기존 가드 그대로).
    @Test func backoffTicksFoldAwayWhileWorking() async {
        let host = "worktick-overload-away-working"
        OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, responses: [(200, ovTickJSON()), ov504])
        let clock = OvClock(ovT0.addingTimeInterval(600))
        let (store, service) = ovMakeStore(host: host, suite: "away-working", clock: clock)
        defer { ovCancelTasks(store) }
        ovBeginOwnedWork(store, at: ovT0)

        await ovRunTick(store)
        clock.now = clock.now.addingTimeInterval(30)
        await ovRunTick(store)                                   // 504 → 백오프
        #expect(store.awayPolicy == nil)
        // 백오프 중에 무언가가 정책을 채워도(예: 다른 경로) 다음 틱이 다시 "모른다" 로 접는다 — 근무 중엔 매 틱.
        store.awayPolicy = AwayPolicy(closeThresholdSeconds: 600, serverNow: nil)
        clock.now = clock.now.addingTimeInterval(10)
        let mark = ovMark(host)
        await ovRunTick(store)
        #expect(ovCounts(host: host, since: mark) == OvCounts(), "\(ovCounts(host: host, since: mark))")
        #expect(store.awayPolicy == nil)
        #expect(service.workTickGate.snapshot.consecutiveOverloadFailures == 1)
    }

    /// 반박 초점 — `.overloaded` 핸드오프는 `.fromTick` 과 같은 가드를 지난다: 다른 계정·옛 세대의 핸드오프는 정책을 건드리지
    /// 않고, 세션이 없으면 통째로 비운다.
    @Test func overloadedHandoffKeepsTheAccountAndGenerationGuards() async {
        let host = "worktick-overload-handoff-guards"
        let clock = OvClock(ovT0.addingTimeInterval(600))
        let (store, _) = ovMakeStore(host: host, suite: "handoff-guards", clock: clock)
        defer { ovCancelTasks(store) }
        ovBeginOwnedWork(store, at: ovT0)
        let policy = AwayPolicy(closeThresholdSeconds: 600, serverNow: nil)

        store.awayPolicy = policy
        await store.finishWorkTick(.overloaded(ownerUserID: "someone-else", generation: store.sessionGeneration))
        #expect(store.awayPolicy == policy, "다른 계정의 핸드오프는 접지 않는다")

        await store.finishWorkTick(.overloaded(ownerUserID: ovUserID, generation: store.sessionGeneration - 1))
        #expect(store.awayPolicy == policy, "옛 세대의 핸드오프는 접지 않는다")

        await store.finishWorkTick(.overloaded(ownerUserID: ovUserID, generation: store.sessionGeneration))
        #expect(store.awayPolicy == nil, "같은 계정·세대면 \"모른다\" 로 접는다")
        #expect(ovCounts(host: host) == OvCounts(), "핸드오프는 요청을 내지 않는다: \(ovCounts(host: host))")
    }

    /// 반박 초점 — 백오프 중 로그아웃: 하트비트 성공·시도 시각(계정에 묶인 값)은 지워지고, 그 사이 늦게 끝난 틱은 핸드오프를 버린다.
    @Test func signOutDuringBackoffClearsTheHeartbeatStamps() async {
        let host = "worktick-overload-signout"
        OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, responses: [(200, ovTickJSON()), ov504])
        let clock = OvClock(ovT0.addingTimeInterval(600))
        let (store, service) = ovMakeStore(host: host, suite: "signout", clock: clock)
        defer { ovCancelTasks(store) }
        ovBeginOwnedWork(store, at: ovT0)
        await ovRunTick(store)
        clock.now = clock.now.addingTimeInterval(30)
        await ovRunTick(store)
        #expect(service.workTickGate.snapshot.consecutiveOverloadFailures == 1)
        #expect(store.lastHeartbeatSucceededAt != .distantPast)

        store.signOut(notifyServer: false)
        #expect(store.lastHeartbeatSucceededAt == .distantPast)
        #expect(store.lastHeartbeatAttemptAt == .distantPast)
        let mark = ovMark(host)
        let handoff = await store.workTickIfPossible()
        if case .fallback = handoff {} else { Issue.record("세션이 없으면 기존 경로(통합 대상 아님) — \(handoff)") }
        #expect(ovCounts(host: host, since: mark).heartbeat == 0, "로그아웃 뒤엔 하트비트가 없다")
    }

    // MARK: 팝오버 즉시 새로고침도 같은 게이트

    @Test func popoverOnDemandRefreshHonoursTheOverloadGate() async {
        let host = "worktick-overload-ondemand"
        OvScriptedURLProtocol.script(host: host, path: ovWorkTickPath, responses: [ov504, (200, ovTickJSON())])
        let clock = OvClock(ovT0)
        let (store, service) = ovMakeStore(host: host, suite: "ondemand", clock: clock)
        defer { ovCancelTasks(store) }

        await store.refreshTeamStatusOnDemand()
        #expect(ovCounts(host: host) == OvCounts(tick: 1), "(b) 실패를 refreshTeamStatus 로 펼치지 않는다: \(ovCounts(host: host))")
        #expect(service.workTickGate.snapshot.consecutiveOverloadFailures == 1)
        #expect(service.workTickGate.snapshot.fallbackCount == 0)

        clock.now = ovT0.addingTimeInterval(10)
        await store.refreshTeamStatusOnDemand()
        #expect(ovCounts(host: host) == OvCounts(tick: 1), "백오프 중이면 네트워크를 내지 않는다: \(ovCounts(host: host))")

        clock.now = ovT0.addingTimeInterval(31)
        await store.refreshTeamStatusOnDemand()
        #expect(ovCounts(host: host) == OvCounts(tick: 2), "\(ovCounts(host: host))")
        #expect(store.teamMembers.map(\.id) == [ovTeammateID])
        #expect(service.workTickGate.snapshot.consecutiveOverloadFailures == 0)
        #expect(store.lastHeartbeatSucceededAt == .distantPast, "p_heartbeat=false 틱의 성공은 하트비트 성공이 아니다")
    }
}

// MARK: - 스크립트 프로토콜 (이 파일 전용 — 음수 상태 = URLError 로 실패)

private final class OvScriptedURLProtocol: URLProtocol {
    private struct Rule {
        let path: String
        let method: String?
        var responses: [(status: Int, body: String)]
        var served = 0
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var rules: [String: [Rule]] = [:]
    private nonisolated(unsafe) static var recorded: [String: [URLRequest]] = [:]

    static func script(host: String, path: String, method: String? = nil, status: Int = 200, body: String) {
        script(host: host, path: path, method: method, responses: [(status, body)])
    }

    /// 응답 시퀀스: 순서대로 소비하고 마지막 것을 반복한다.
    static func script(host: String, path: String, method: String? = nil, responses: [(Int, String)]) {
        lock.lock(); defer { lock.unlock() }
        var list = rules[host, default: []]
        let rule = Rule(path: path, method: method, responses: responses.map { (status: $0.0, body: $0.1) })
        if let index = list.firstIndex(where: { $0.path == path && $0.method == method }) {
            list[index] = rule
        } else {
            list.append(rule)
        }
        rules[host] = list
    }

    static func requests(host: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded[host, default: []]
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OvScriptedURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        var status = 200
        var payload = "[]"
        Self.lock.lock()
        Self.recorded[host, default: []].append(request)
        if var list = Self.rules[host],
           let index = list.firstIndex(where: { $0.path == request.url?.path && ($0.method == nil || $0.method == request.httpMethod) }) {
            let rule = list[index]
            let pick = min(rule.served, rule.responses.count - 1)
            status = rule.responses[pick].status
            payload = rule.responses[pick].body
            list[index].served += 1
            Self.rules[host] = list
        }
        Self.lock.unlock()

        if status < 0 {
            client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue: status)))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
