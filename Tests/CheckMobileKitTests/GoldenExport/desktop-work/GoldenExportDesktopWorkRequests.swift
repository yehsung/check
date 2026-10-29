// 원본: Sources/CheckCore/SupabaseWorkServiceMacOnly.swift(근무 21-620 · upsertStatus 953-1016) · SupabaseWorkModels.swift(1253-1400 · 2811-2990) @ a90d8623
@testable import CheckCore
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckMobileKit

// W2-g1 데스크톱 근무 요청 골든(xplat-w1/briefs/work.md §5 wq): 맥 전용 근무 쓰기(G5 의 H 태그 몫)를 W1-d G5 녹음기
// (`WireRequestRecorder` — GoldenWireSupport · MobileStubURLProtocol)로 그대로 녹음한다. Kotlin `DesktopWorkRequestsGoldenTest` 가
// feature/desktop 의 확장 함수(core/net 에 H 이름을 넣지 않는다 — WireRequestsGoldenTest 가 빨개진다)를 MockEngine 으로 녹음해 대조한다.
//
// 벽시계: 맥 원본은 `last_seen_at`·`updated_at`·`auto_closed_at` 을 `Date()` 로 찍는다(서비스 시계가 아니다) — 골든이 실행마다 바뀌지
// 않게 이 세 키의 본문 값은 "<WALL>" 로 바꾼다(spec.wallClockKeys). Kotlin 은 주입 시계로 찍고 같은 자리에서 같은 표식으로 바꾼다.

@Suite("GoldenExport W2-g1 데스크톱 근무 — 요청 골든")
struct GoldenExportDesktopWorkRequests {
    static let u = WireGoldenValues.userID
    static let now = WireGoldenValues.now
    static let team = "ee000000-0000-4000-8000-0000000000e5"
    static let sid = "ab000000-0000-4000-8000-0000000000f6"
    static let device = "win:0f000000-0000-4000-8000-0000000000a7"
    /// 04:05:00Z · 05:04:00Z · 05:04:30Z
    static let startedAt = now.addingTimeInterval(-3600)
    static let endedAt = now.addingTimeInterval(-60)
    static let lastInput = now.addingTimeInterval(-30)

    /// G5 의 H 태그 중 근무 몫(+ 내부 `openSessionIDs`) — 이름마다 case 가 있어야 한다(Kotlin 도 같은 목록을 단언한다).
    static let names = [
        "startWork", "stopWork", "heartbeat", "upsertStatusDevice", "reportDeviceInput", "closeAbandonedSessions", "awaySync",
        "makeWorkTickRequest", "workTick", "reopenSession", "openSessionIDs", "fetchMyOverlappingSessions", "insertClosedSession",
    ]
    static let wallClockKeys: Set<String> = ["last_seen_at", "updated_at", "auto_closed_at"]

    static let rowOpenUpper = #"[{"id":"AB000000-0000-4000-8000-0000000000F6","user_id":"\#(WireGoldenValues.userID)","started_at":"2026-09-17T04:05:00Z","ended_at":null}]"#
    static let rowClosed = #"[{"id":"ab000000-0000-4000-8000-0000000000f6","user_id":"\#(WireGoldenValues.userID)","started_at":"2026-09-17T04:05:00Z","ended_at":"2026-09-17T05:04:00Z","duration_seconds":3540}]"#
    static let rowOther = #"[{"id":"CD000000-0000-4000-8000-0000000000C7","user_id":"\#(WireGoldenValues.userID)","started_at":"2026-09-17T05:00:00Z","ended_at":null}]"#
    static let empty = MobileStubResponse.json("[]")
    static let ok = MobileStubResponse.json("{}")
    static let conflict = MobileStubResponse.json(#"{"code":"23505","details":null,"hint":null,"message":"duplicate key value violates unique constraint \"work_sessions_one_open_per_user\""}"#, status: 409)
    static let schemaMissing = MobileStubResponse.json(#"{"code":"PGRST204","message":"Could not find the 'auto_closed_reason' column of 'work_sessions' in the schema cache"}"#, status: 400)
    static let bad400 = MobileStubResponse.json("{}", status: 400)

    static func tick(_ s: SupabaseWorkService) async -> WorkTickRequest {
        await s.makeWorkTickRequest(teamID: team, heartbeat: true, sessionID: nil, deviceID: device, openedSession: false,
                              lastInputAt: nil, includeMeta: false, now: now)
    }

    static var calls: [WireCall] {
        let u = u, team = team, sid = sid, device = device, startedAt = startedAt, endedAt = endedAt, lastInput = lastInput, now = now
        let rowOpenUpper = MobileStubResponse.json(rowOpenUpper), rowClosed = MobileStubResponse.json(rowClosed), rowOther = MobileStubResponse.json(rowOther)
        let empty = empty, ok = ok, conflict = conflict, schemaMissing = schemaMissing, bad400 = bad400
        return [
            // ---- 시작(★ 0행 = 이미 있다 · 23505 = sessionAlreadyOpen · 디코드 실패 nil — C#20·#36) ----
            WireCall(id: "startWork#rows", responses: [rowOpenUpper, ok]) { s, t in
                try await s.startWork(accessToken: t, teamID: team, userID: u, sessionID: sid, startedAt: startedAt) },
            WireCall(id: "startWork#zeroRows", responses: [empty, ok]) { s, t in
                try await s.startWork(accessToken: t, teamID: team, userID: u, sessionID: sid, startedAt: startedAt) },
            WireCall(id: "startWork#undecodable", responses: [.json("not json"), ok]) { s, t in
                try await s.startWork(accessToken: t, teamID: team, userID: u, sessionID: sid, startedAt: startedAt) },
            WireCall(id: "startWork#23505", responses: [conflict]) { s, t in
                try await s.startWork(accessToken: t, teamID: team, userID: u, sessionID: sid, startedAt: startedAt) },
            // ---- 종료(★ id 필터 · 0행 폴백 POST · abandoned 만 정정 · 다른 열린 행이 보이면 꼬리 생략 — C#21) ----
            WireCall(id: "stopWork#manual", responses: [rowClosed, ok]) { s, t in
                try await s.stopWork(accessToken: t, teamID: team, userID: u, startedAt: startedAt, endedAt: endedAt,
                                     durationSeconds: 3540, fallbackSessionID: sid) },
            WireCall(id: "stopWork#autoReason", responses: [rowClosed, ok]) { s, t in
                try await s.stopWork(accessToken: t, teamID: team, userID: u, startedAt: startedAt, endedAt: endedAt,
                                     durationSeconds: 3540, fallbackSessionID: sid, autoClosedReason: .away) },
            WireCall(id: "stopWork#reasonColumnMissing", responses: [schemaMissing, rowClosed, ok]) { s, t in
                try await s.stopWork(accessToken: t, teamID: team, userID: u, startedAt: startedAt, endedAt: endedAt,
                                     durationSeconds: 3540, fallbackSessionID: sid, autoClosedReason: .longSession) },
            WireCall(id: "stopWork#zeroRowsFallback", responses: [empty, ok, empty, ok]) { s, t in
                try await s.stopWork(accessToken: t, teamID: team, userID: u, startedAt: startedAt, endedAt: endedAt,
                                     durationSeconds: -5, fallbackSessionID: sid) },
            WireCall(id: "stopWork#zeroRowsSleepCorrect", responses: [empty, ok, empty, ok, empty, ok]) { s, t in
                try await s.stopWork(accessToken: t, teamID: team, userID: u, startedAt: startedAt, endedAt: endedAt,
                                     durationSeconds: 3540, fallbackSessionID: sid, autoClosedReason: .sleep) },
            WireCall(id: "stopWork#zeroRowsOtherOpen", responses: [empty, ok, rowOther]) { s, t in
                try await s.stopWork(accessToken: t, teamID: team, userID: u, startedAt: startedAt, endedAt: endedAt,
                                     durationSeconds: 3540, fallbackSessionID: sid) },
            WireCall(id: "stopWork#zeroRowsOpenLookupFails", responses: [empty, ok, .json(#"{"message":"boom"}"#, status: 500), ok]) { s, t in
                try await s.stopWork(accessToken: t, teamID: team, userID: u, startedAt: startedAt, endedAt: endedAt,
                                     durationSeconds: 3540, fallbackSessionID: sid) },
            WireCall(id: "stopWork#noSharedStatus", responses: [empty, ok]) { s, t in
                try await s.stopWork(accessToken: t, teamID: team, userID: u, startedAt: startedAt, endedAt: endedAt,
                                     durationSeconds: 3540, fallbackSessionID: sid, updateSharedStatus: false) },
            // ---- 하트비트 · 기기 행 ----
            WireCall(id: "heartbeat#input") { s, t in
                try await s.heartbeat(accessToken: t, teamID: team, userID: u, sessionID: sid, lastInputAt: lastInput) },
            WireCall(id: "heartbeat#noInput") { s, t in
                try await s.heartbeat(accessToken: t, teamID: team, userID: u, sessionID: sid) },
            WireCall(id: "heartbeat#inputColumnMissing", responses: [schemaMissing, ok]) { s, t in
                try await s.heartbeat(accessToken: t, teamID: team, userID: u, sessionID: sid, lastInputAt: lastInput) },
            WireCall(id: "upsertStatusDevice#opened") { s, t in
                try await s.upsertStatusDevice(accessToken: t, teamID: team, userID: u, deviceID: device, sessionID: sid,
                                               openedSession: true, lastInputAt: lastInput) },
            WireCall(id: "upsertStatusDevice#weak") { s, t in
                try await s.upsertStatusDevice(accessToken: t, teamID: team, userID: u, deviceID: device, sessionID: sid,
                                               openedSession: false) },
            WireCall(id: "upsertStatusDevice#inputColumnMissing", responses: [bad400, ok]) { s, t in
                try await s.upsertStatusDevice(accessToken: t, teamID: team, userID: u, deviceID: device, sessionID: sid,
                                               openedSession: true, lastInputAt: lastInput) },
            WireCall(id: "reportDeviceInput") { s, t in
                try await s.reportDeviceInput(accessToken: t, teamID: team, userID: u, deviceID: device, lastInputAt: lastInput) },
            // ---- 스캐빈저 · 자리 비움 ----
            WireCall(id: "closeAbandonedSessions#int", responses: [.json(" 3\n")]) { s, t in try await s.closeAbandonedSessions(accessToken: t) },
            WireCall(id: "closeAbandonedSessions#empty", responses: [.json("")]) { s, t in try await s.closeAbandonedSessions(accessToken: t) },
            WireCall(id: "awaySync#ok", responses: [.json(#"{"status":"ok","server_now":"2026-09-17T05:05:00.250Z","close_threshold_seconds":1800,"backstop_seconds":3600,"freeze_seconds":600,"open_session":{"id":"AB000000-0000-4000-8000-0000000000F6","team_id":"ee000000-0000-4000-8000-0000000000e5","started_at":"2026-09-17T04:05:00Z","last_input_at":"2026-09-17T04:30:00Z","close_eligible":true,"close_due_at":"2026-09-17T05:00:00Z"}}"#)]) { s, t in
                try await s.awaySync(accessToken: t) },
            WireCall(id: "awaySync#thresholdZero", responses: [.json(#"{"status":"ok","server_now":"2026-09-17T05:05:00Z","close_threshold_seconds":0,"open_session":{"id":"x-1","close_eligible":true}}"#)]) { s, t in
                try await s.awaySync(accessToken: t) },
            WireCall(id: "awaySync#eligibleMissing", responses: [.json(#"{"status":"paused","close_threshold_seconds":900,"open_session":{"id":"x-2","started_at":"bad"}}"#)]) { s, t in
                try await s.awaySync(accessToken: t) },
            WireCall(id: "awaySync#unavailable", responses: [WireRequestRecorder.pgrst202]) { s, t in try await s.awaySync(accessToken: t) },
            WireCall(id: "awaySync#garbage", responses: [.json("[1]")]) { s, t in try await s.awaySync(accessToken: t) },
            // ---- work_tick(요청 조립은 순수 · 실패 갈래 — C§4 ⑨) ----
            WireCall(id: "makeWorkTickRequest#owner") { s, _ in
                await s.makeWorkTickRequest(teamID: team, heartbeat: true, sessionID: sid, deviceID: device, openedSession: true,
                                      lastInputAt: lastInput, includeMeta: false, now: now) },
            WireCall(id: "makeWorkTickRequest#adopted") { s, _ in
                await s.makeWorkTickRequest(teamID: team, heartbeat: false, sessionID: nil, deviceID: device, openedSession: false,
                                      lastInputAt: lastInput, includeMeta: false, now: now) },
            WireCall(id: "makeWorkTickRequest#unconfirmed") { s, _ in
                await s.makeWorkTickRequest(teamID: team, heartbeat: false, sessionID: nil, deviceID: nil, openedSession: false,
                                      lastInputAt: lastInput, includeMeta: true, now: now) },
            WireCall(id: "makeWorkTickRequest#none") { s, _ in
                await s.makeWorkTickRequest(teamID: nil, heartbeat: false, sessionID: nil, deviceID: nil, openedSession: false,
                                      lastInputAt: nil, includeMeta: false, now: now) },
            WireCall(id: "workTick#ok", responses: [.json(#"{"v":1,"server_now":"2026-09-17T05:05:01Z","team_id":"ee000000-0000-4000-8000-0000000000e5","heartbeat":{"mode":"owner","status":"working","active_session_id":"ab000000-0000-4000-8000-0000000000f6","last_seen_at":"2026-09-17T05:05:00Z","device":true},"statuses":[{"user_id":"u-1","status":"working","active_session_id":"S-1"}],"sessions_active":[{"id":"S-1","user_id":"u-1","started_at":"2026-09-17T04:00:00Z"}],"sessions_weekly":[],"sessions_since":"2026-09-13T15:00:00Z","devices":[{"user_id":"u-1","device_id":"win:x","session_id":"S-1","opened_session":true}],"away":{"status":"ok","close_threshold_seconds":1800},"meta":{"memberships":[],"invite_code":[{"invite_code":"ABC123"}]}}"#)]) { s, t in
                try await s.workTick(accessToken: t, request: await tick(s)) },
            WireCall(id: "workTick#401", responses: [.json("{}", status: 401)]) { s, t in try await s.workTick(accessToken: t, request: await tick(s)) },
            WireCall(id: "workTick#404", responses: [.json(#"{"code":"PGRST202","message":"Could not find the function"}"#, status: 404)]) { s, t in
                try await s.workTick(accessToken: t, request: await tick(s)) },
            WireCall(id: "workTick#PGRST202", responses: [.json(#"{"code":"PGRST202"}"#, status: 400)]) { s, t in try await s.workTick(accessToken: t, request: await tick(s)) },
            WireCall(id: "workTick#403", responses: [.json(#"{"code":"42501"}"#, status: 403)]) { s, t in try await s.workTick(accessToken: t, request: await tick(s)) },
            WireCall(id: "workTick#42501", responses: [.json(#"{"code":"42501"}"#, status: 400)]) { s, t in try await s.workTick(accessToken: t, request: await tick(s)) },
            WireCall(id: "workTick#503", responses: [.json("upstream", status: 503)]) { s, t in try await s.workTick(accessToken: t, request: await tick(s)) },
            WireCall(id: "workTick#409", responses: [.json(#"{"code":"P0001"}"#, status: 409)]) { s, t in try await s.workTick(accessToken: t, request: await tick(s)) },
            WireCall(id: "workTick#v2", responses: [.json(#"{"v":2}"#)]) { s, t in try await s.workTick(accessToken: t, request: await tick(s)) },
            WireCall(id: "workTick#garbage", responses: [.json("<html>")]) { s, t in try await s.workTick(accessToken: t, request: await tick(s)) },
            // ---- 되돌리기 · 갇힌 근무 복구 ----
            WireCall(id: "reopenSession#rows", responses: [rowOpenUpper, ok]) { s, t in
                try await s.reopenSession(accessToken: t, teamID: team, userID: u, sessionID: sid) },
            WireCall(id: "reopenSession#zero", responses: [empty, ok]) { s, t in
                try await s.reopenSession(accessToken: t, teamID: team, userID: u, sessionID: sid) },
            WireCall(id: "reopenSession#reasonColumnMissing", responses: [schemaMissing, rowOpenUpper, ok]) { s, t in
                try await s.reopenSession(accessToken: t, teamID: team, userID: u, sessionID: sid) },
            WireCall(id: "openSessionIDs", responses: [.json(#"[{"id":"AB000000-0000-4000-8000-0000000000F6","user_id":"u","started_at":"x"},{"id":null,"user_id":"u","started_at":"y"}]"#)]) { s, t in
                try await s.openSessionIDs(accessToken: t, userID: u) },
            WireCall(id: "fetchMyOverlappingSessions", responses: [.json(#"[{"id":"CD000000-0000-4000-8000-0000000000C7","user_id":"u","started_at":"2026-09-17T05:00:00Z","ended_at":null},{"id":"x","user_id":"u","started_at":"2026-09-17T03:00:00Z","ended_at":"2026-09-17T04:30:00Z","duration_seconds":5400}]"#)]) { s, t in
                try await s.fetchMyOverlappingSessions(accessToken: t, userID: u, since: startedAt) },
            WireCall(id: "insertClosedSession") { s, t in
                try await s.insertClosedSession(accessToken: t, teamID: team, userID: u, sessionID: sid, startedAt: startedAt, endedAt: endedAt) },
        ]
    }

    /// 본문 객체의 벽시계 키 값 → "<WALL>"(값이 null 이면 그대로 — 키가 실렸는지는 그대로 대조된다).
    static func maskWall(_ v: GoldenJSON) -> GoldenJSON {
        switch v {
        case .object(let o):
            var out: [String: GoldenJSON] = [:]
            for (k, x) in o {
                if wallClockKeys.contains(k), case .string = x { out[k] = .string("<WALL>") } else { out[k] = maskWall(x) }
            }
            return .object(out)
        case .array(let a): return .array(a.map(maskWall))
        default: return v
        }
    }

    @Test("데스크톱 근무 요청 골든")
    func desktopWorkRequests() async throws {
        var cases: [GoldenJSON] = []
        for (i, call) in Self.calls.enumerated() {
            let recorded = try await WireRequestRecorder.record(call, index: 9000 + i)
            guard case .object(var o) = recorded, case .array(let reqs)? = o["requests"] else { Issue.record("녹음 모양"); continue }
            o["requests"] = .array(reqs.map { r in
                guard case .object(var ro) = r, let body = ro["body"] else { return r }
                ro["body"] = Self.maskWall(body)
                return .object(ro)
            })
            cases.append(.object(o))
        }
        let ids = Self.calls.map(\.id)
        let missing = Self.names.filter { n in !ids.contains { $0 == n || $0.hasPrefix(n + "#") } }
        #expect(missing.isEmpty, "case 가 없는 근무 이름: \(missing)")
        #expect(Set(ids).count == ids.count, "case id 중복")
        goldenEmit(GoldenFile(
            golden: "desktop-work/requests",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkServiceMacOnly.swift", "Sources/CheckCore/SupabaseWorkModels.swift",
                           "Sources/CheckCore/SupabaseWorkHTTP.swift"],
            spec: [
                "values": .object([
                    "anonKey": .string("<ANON>"), "accessToken": .string("<ACCESS>"), "host": .string("golden.invalid"),
                    "userID": .string(Self.u), "teamID": .string(Self.team), "sessionID": .string(Self.sid), "deviceID": .string(Self.device),
                    "nowSince1970": .int(Int(Self.now.timeIntervalSince1970)),
                    "startedAtSince1970": .int(Int(Self.startedAt.timeIntervalSince1970)),
                    "endedAtSince1970": .int(Int(Self.endedAt.timeIntervalSince1970)),
                    "lastInputAtSince1970": .int(Int(Self.lastInput.timeIntervalSince1970)),
                ]),
                "names": .array(Self.names.map { .string($0) }),
                "wallClockKeys": .array(Self.wallClockKeys.sorted().map { .string($0) }),
                "request": .string("W1-d G5 와 같다(wire/requests spec.request) — 단 본문의 wallClockKeys 값(글자)은 \"<WALL>\""),
                "result": .string("W1-d G5 와 같다(wire/requests spec.result). WorkTickFailure·AwaySyncUnavailable 은 {\"$type\", \"$dump\"}"),
            ],
            cases: cases
        ))
    }
}
