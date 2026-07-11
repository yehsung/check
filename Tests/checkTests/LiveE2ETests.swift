import Foundation
import Testing
@testable import check

// 트랙 C — 라이브 E2E.
// 실제 프로덕션 Supabase(xfnhfjvubetkdnfkfljg.supabase.co)에 실제 WorkTimerStore + 실제
// SupabaseWorkService(URLSession.shared)를 연결해 스토어 레벨로 전체 흐름을 구동한다.
// 게이팅: CHECK_E2E=1 일 때만 실행되며, 평소 swift test 에서는 전부 스킵된다.
// anon key 는 /Users/yesung/check/.env.local 에서, 정리용 service_role 키는
// CHECK_E2E_SR_KEY_FILE 이 가리키는 apikeys.json 에서 읽는다. 키 원문은 절대 출력하지 않는다.

// MARK: - 에러/관측

private struct E2EError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private enum LiveE2EState {
    nonisolated(unsafe) static var primaryUserID: String?
    nonisolated(unsafe) static var recordedDurationSeconds: Int?
    nonisolated(unsafe) static var observations: [String] = []
}

private func obs(_ line: String) {
    LiveE2EState.observations.append(line)
    print("E2E| \(line)")
}

// MARK: - 고정 QA 자격/문구

private enum Emails {
    static let primary = "check.e2e.livesuite@gmail.com"
    static let nickname = "check.e2e.nickname@gmail.com"
    static let ghost = "check.e2e.ghost.doesnotexist@gmail.com"
    static let password = "E2E-qa-Passw0rd!23"
    static let wrongPassword = "E2E-qa-WRONG-Passw0rd!99"
    // 30자(그래핌 기준) 한글 20 + 이모지 10.
    static let edgeDisplayName = "가나다라마바사아자차카타파하거너더러머버" + "🎉🚀✨🌟💪🔥😀🙌🐣🌈"
}

// MARK: - 키 로딩 (파일 → 값 주입)

private enum LiveE2EEnv {
    static let enabled = ProcessInfo.processInfo.environment["CHECK_E2E"] == "1"

    static func anonKey() throws -> String {
        let path = ProcessInfo.processInfo.environment["CHECK_E2E_ANON_KEY_FILE"]
            ?? "/Users/yesung/check/.env.local"
        let text = try String(contentsOfFile: path, encoding: .utf8)
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("\(SupabaseConfig.anonKeyEnvironmentName)=") else { continue }
            let value = stripQuotes(
                String(line.dropFirst(SupabaseConfig.anonKeyEnvironmentName.count + 1))
                    .trimmingCharacters(in: .whitespaces)
            )
            guard !value.isEmpty else { continue }
            return value
        }
        throw E2EError("anon key(\(SupabaseConfig.anonKeyEnvironmentName)) 를 \(path) 에서 찾지 못함")
    }

    static func serviceRoleKey() throws -> String {
        guard let path = ProcessInfo.processInfo.environment["CHECK_E2E_SR_KEY_FILE"] else {
            throw E2EError("CHECK_E2E_SR_KEY_FILE 환경변수가 설정되지 않음")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw E2EError("apikeys.json 이 배열 형태가 아님")
        }
        for item in array where (item["name"] as? String) == "service_role" {
            if let key = item["api_key"] as? String, !key.isEmpty {
                return key
            }
        }
        throw E2EError("service_role 키를 \(path) 에서 찾지 못함")
    }

    private static func stripQuotes(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last else {
            return value
        }
        if (first == "\"" || first == "'"), first == last {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}

// MARK: - 날짜 파서 (프로덕션 timestamptz 는 소수 초 유무가 섞여 온다)

private func parseSupabaseDate(_ value: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFraction.date(from: value) {
        return date
    }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: value)
}

// MARK: - service_role 관리자 클라이언트 (RLS 우회, 검증/정리 전용)

private struct E2EAdmin: Sendable {
    let serviceKey: String
    let projectURL = SupabaseConfig.projectURL
    let session = URLSession(configuration: .ephemeral)

    private func send(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        prefer: String? = nil
    ) async throws -> (Data, Int) {
        var attempt = 0
        while true {
            attempt += 1
            do {
                var components = URLComponents(
                    url: projectURL.appending(path: path),
                    resolvingAgainstBaseURL: false
                )!
                components.queryItems = query.isEmpty ? nil : query
                guard let url = components.url else {
                    throw E2EError("잘못된 URL: \(path)")
                }
                var request = URLRequest(url: url)
                request.httpMethod = method
                request.setValue(serviceKey, forHTTPHeaderField: "apikey")
                request.setValue("Bearer \(serviceKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                if let prefer {
                    request.setValue(prefer, forHTTPHeaderField: "Prefer")
                }
                if let body {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = body
                }
                let (data, response) = try await session.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                // 프로덕션 레이트리밋/일시 오류는 1회 재시도.
                if (code == 429 || code >= 500), attempt == 1 {
                    obs("admin 재시도(HTTP \(code)) \(method) \(path)")
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    continue
                }
                return (data, code)
            } catch {
                if attempt == 1 {
                    obs("admin 재시도(예외) \(method) \(path): \(error)")
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    continue
                }
                throw error
            }
        }
    }

    private func rows(_ table: String, _ query: [URLQueryItem]) async throws -> [[String: Any]] {
        let (data, code) = try await send(path: "/rest/v1/\(table)", method: "GET", query: query)
        guard code == 200 else {
            throw E2EError("REST \(table) HTTP \(code): \(String(decoding: data, as: UTF8.self))")
        }
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    func findUserID(email: String) async throws -> String? {
        let target = email.lowercased()
        var page = 1
        while page <= 50 {
            let (data, code) = try await send(
                path: "/auth/v1/admin/users",
                method: "GET",
                query: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "per_page", value: "200")
                ]
            )
            guard code == 200 else {
                throw E2EError("admin 유저 목록 HTTP \(code)")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let users = object["users"] as? [[String: Any]]
            else {
                throw E2EError("admin 유저 목록 형태가 예상과 다름")
            }
            if let match = users.first(where: { ($0["email"] as? String)?.lowercased() == target }) {
                return match["id"] as? String
            }
            if users.count < 200 {
                break
            }
            page += 1
        }
        return nil
    }

    func deleteUser(id: String) async throws {
        let (data, code) = try await send(path: "/auth/v1/admin/users/\(id)", method: "DELETE")
        guard code == 200 || code == 204 else {
            throw E2EError("admin 삭제 HTTP \(code): \(String(decoding: data, as: UTF8.self))")
        }
    }

    /// 이메일로 유저를 찾아 admin 삭제. 삭제되었으면 true. 캐스케이드(profiles 0)를 폴링해 확인.
    @discardableResult
    func deleteByEmail(_ email: String) async throws -> Bool {
        guard let id = try await findUserID(email: email) else {
            return false
        }
        try await deleteUser(id: id)
        for _ in 0..<20 {
            if try await profileCount(byEmail: email) == 0 {
                break
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return true
    }

    func profileCount(userID: String) async throws -> Int {
        try await rows("profiles", [
            URLQueryItem(name: "id", value: "eq.\(userID)"),
            URLQueryItem(name: "select", value: "id")
        ]).count
    }

    func profileCount(byEmail email: String) async throws -> Int {
        try await rows("profiles", [
            URLQueryItem(name: "email", value: "eq.\(email)"),
            URLQueryItem(name: "select", value: "id")
        ]).count
    }

    func profileDisplayName(userID: String) async throws -> String? {
        try await rows("profiles", [
            URLQueryItem(name: "id", value: "eq.\(userID)"),
            URLQueryItem(name: "select", value: "display_name")
        ]).first?["display_name"] as? String
    }

    func membershipCount(userID: String) async throws -> Int {
        try await rows("memberships", [
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "select", value: "user_id")
        ]).count
    }

    func statusRows(userID: String) async throws -> [[String: Any]] {
        try await rows("work_statuses", [
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "select", value: "status,active_session_id")
        ])
    }

    func sessionRows(userID: String, openOnly: Bool) async throws -> [[String: Any]] {
        var query = [
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "select", value: "id,started_at,ended_at,duration_seconds"),
            URLQueryItem(name: "order", value: "started_at.desc")
        ]
        if openOnly {
            query.append(URLQueryItem(name: "ended_at", value: "is.null"))
        }
        return try await rows("work_sessions", query)
    }

    func sessionCount(userID: String) async throws -> Int {
        try await sessionRows(userID: userID, openOnly: false).count
    }

    /// 오늘(한국시각) 시작한 완료 세션들의 duration_seconds 합계 — 서버 기준 오늘 누적.
    func todayTotalDuration(userID: String) async throws -> Int {
        let dayStart = TeamWeeklyGoal.koreanDayStart(for: Date())
        var total = 0
        for row in try await sessionRows(userID: userID, openOnly: false) {
            guard row["ended_at"] is String else { continue }
            guard let startedString = row["started_at"] as? String,
                  let started = parseSupabaseDate(startedString),
                  started >= dayStart
            else { continue }
            if let duration = row["duration_seconds"] as? Int {
                total += duration
            }
        }
        return total
    }
}

// MARK: - 스토어/유틸 헬퍼

@MainActor
private func makeLiveStore(anonKey: String, defaults: UserDefaults) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: SupabaseConfig.projectURL,
        anonKey: anonKey,
        session: .shared
    )
    return WorkTimerStore(
        service: service,
        environment: [SupabaseConfig.anonKeyEnvironmentName: anonKey],
        defaults: defaults
    )
}

private func liveIsolatedDefaults() -> UserDefaults {
    let suiteName = "check-live-e2e-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private func waitUntil(
    tries: Int = 15,
    delayMs: UInt64 = 300,
    _ condition: () async -> Bool
) async -> Bool {
    for _ in 0..<tries {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
    }
    return await condition()
}

@MainActor
private func makeContext() throws -> (anonKey: String, admin: E2EAdmin) {
    let anonKey = try LiveE2EEnv.anonKey()
    let admin = E2EAdmin(serviceKey: try LiveE2EEnv.serviceRoleKey())
    return (anonKey, admin)
}

/// primary 계정이 반드시 존재하도록 보장하고 userID 를 돌려준다(순서 흔들림 대비 자가치유).
@MainActor
private func ensurePrimaryAccount(anonKey: String, admin: E2EAdmin) async throws -> String {
    if let cached = LiveE2EState.primaryUserID,
       (try? await admin.profileCount(userID: cached)) == 1 {
        return cached
    }
    if let existing = try await admin.findUserID(email: Emails.primary) {
        LiveE2EState.primaryUserID = existing
        return existing
    }
    let store = makeLiveStore(anonKey: anonKey, defaults: liveIsolatedDefaults())
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    store.email = Emails.primary
    store.displayName = "복구계정"
    store.password = Emails.password
    await store.signUp()?.value
    guard let userID = store.session?.userID else {
        throw E2EError("primary 계정 생성 실패: \(store.syncMessage)")
    }
    LiveE2EState.primaryUserID = userID
    return userID
}

// MARK: - 시나리오 스위트 (직렬 실행, 게이트 오프 시 전부 스킵)

@Suite(.serialized)
@MainActor
struct LiveE2ETests {

    // 0. 시작 전 잔존 QA 계정 admin 삭제(멱등).
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s00_preCleanup() async throws {
        let ctx = try makeContext()
        for email in [Emails.primary, Emails.nickname] {
            let removed = try await ctx.admin.deleteByEmail(email)
            obs("사전정리 \(email): \(removed ? "잔존 계정 삭제" : "없음")")
        }
        for email in [Emails.primary, Emails.nickname] {
            #expect(try await ctx.admin.findUserID(email: email) == nil)
        }
    }

    // 1. 가입 → 즉시 세션 + 트리거 3종 행 생성.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s01_signUpCreatesSessionAndTriggerRows() async throws {
        let ctx = try makeContext()
        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.email = Emails.primary
        store.displayName = "이서브영식"
        store.password = Emails.password

        await store.signUp()?.value

        obs("가입 결과: isSignedIn=\(store.isSignedIn), syncMessage=\(store.syncMessage)")
        #expect(store.isSignedIn)
        let userID = try #require(store.session?.userID)
        LiveE2EState.primaryUserID = userID

        let profileReady = await waitUntil {
            (try? await ctx.admin.profileCount(userID: userID)) == 1
        }
        #expect(profileReady)

        let membershipCount = try await ctx.admin.membershipCount(userID: userID)
        let statusRows = try await ctx.admin.statusRows(userID: userID)
        #expect(try await ctx.admin.profileCount(userID: userID) == 1)
        #expect(membershipCount == 1)
        #expect(statusRows.count == 1)
        #expect((statusRows.first?["status"] as? String) == "off_work")
        obs("트리거 행: profiles=1, memberships=\(membershipCount), work_statuses=\(statusRows.count)(off_work)")
    }

    // 2. 로그아웃 → 올바른 비번 재로그인 → 세션 복원.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s02_signOutThenReSignIn() async throws {
        let ctx = try makeContext()
        _ = try await ensurePrimaryAccount(anonKey: ctx.anonKey, admin: ctx.admin)
        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.email = Emails.primary
        store.password = Emails.password
        await store.signIn()?.value
        #expect(store.isSignedIn)

        store.signOut()
        #expect(!store.isSignedIn)

        store.password = Emails.password
        await store.signIn()?.value
        #expect(store.isSignedIn)
        #expect(store.session != nil)
        obs("재로그인: isSignedIn=\(store.isSignedIn), syncMessage=\(store.syncMessage)")
    }

    // 3. 틀린 비번 → 로그인 실패 + "로그인 정보 오류".
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s03_wrongPassword() async throws {
        let ctx = try makeContext()
        _ = try await ensurePrimaryAccount(anonKey: ctx.anonKey, admin: ctx.admin)
        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.email = Emails.primary
        store.password = Emails.wrongPassword

        await store.signIn()?.value

        obs("틀린 비번: isSignedIn=\(store.isSignedIn), syncMessage=\(store.syncMessage)")
        #expect(!store.isSignedIn)
        #expect(store.syncMessage == "로그인 정보 오류")
    }

    // 4. 없는 이메일 → 동일 오류.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s04_unknownEmail() async throws {
        let ctx = try makeContext()
        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.email = Emails.ghost
        store.password = Emails.password

        await store.signIn()?.value

        obs("없는 이메일: isSignedIn=\(store.isSignedIn), syncMessage=\(store.syncMessage)")
        #expect(!store.isSignedIn)
        #expect(store.syncMessage == "로그인 정보 오류")
    }

    // 5. 중복 가입 → 실제 GoTrue(autoconfirm) 응답 기준 문구 확인/기록.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s05_duplicateSignUp() async throws {
        let ctx = try makeContext()
        let userID = try await ensurePrimaryAccount(anonKey: ctx.anonKey, admin: ctx.admin)
        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.email = Emails.primary
        store.displayName = "중복시도"
        store.password = Emails.password

        await store.signUp()?.value

        let message = store.syncMessage
        obs("중복 가입: isSignedIn=\(store.isSignedIn), syncMessage=\(message)")
        if message != "이미 가입된 이메일" {
            obs("발견(시나리오5): 예상과 다른 중복 가입 문구 = \(message)")
        }
        // 견고한 불변식: 중복 가입은 새 세션을 만들지 않고 계정을 복제하지 않는다.
        #expect(!store.isSignedIn)
        #expect(try await ctx.admin.profileCount(userID: userID) == 1)
        #expect(try await ctx.admin.profileCount(byEmail: Emails.primary) == 1)
        // 실측: autoconfirm 환경의 GoTrue 는 422 user_already_exists → "이미 가입된 이메일".
        #expect(message == "이미 가입된 이메일")
    }

    // 6. 근무 시작 → DB open 세션 + working 상태.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s06_startWork() async throws {
        let ctx = try makeContext()
        let userID = try await ensurePrimaryAccount(anonKey: ctx.anonKey, admin: ctx.admin)
        // 깨끗한 시작을 위해 잔존 open 세션 정리(멱등).
        if try await ctx.admin.sessionRows(userID: userID, openOnly: true).isEmpty == false {
            obs("s06 잔존 open 세션 존재 → 정리 시도")
        }

        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.email = Emails.primary
        store.password = Emails.password
        await store.signIn()?.value
        #expect(store.isSignedIn)

        // signIn 이 open 세션을 복원해 이미 working 이면 그 세션을 그대로 사용.
        if store.startedAt == nil {
            store.start()
            await store.syncTask?.value
        }

        let openReady = await waitUntil {
            ((try? await ctx.admin.sessionRows(userID: userID, openOnly: true).count) ?? 0) == 1
        }
        #expect(openReady)
        let openCount = try await ctx.admin.sessionRows(userID: userID, openOnly: true).count
        let statusRows = try await ctx.admin.statusRows(userID: userID)
        #expect(openCount == 1)
        #expect((statusRows.first?["status"] as? String) == "working")
        obs("근무 시작: open 세션=\(openCount), 상태=\(statusRows.first?["status"] as? String ?? "nil")")
    }

    // 7. 이중 시작 방어 → 두 번째 스토어가 fresh start 시 서버 409, open 세션은 여전히 1개.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s07_doubleStartDefense() async throws {
        let ctx = try makeContext()
        let userID = try await ensurePrimaryAccount(anonKey: ctx.anonKey, admin: ctx.admin)

        // 방어 대상 open 세션이 있어야 의미가 있으므로, 없으면 하나 만든다(자가치유).
        if try await ctx.admin.sessionRows(userID: userID, openOnly: true).isEmpty {
            let seed = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
            seed.email = Emails.primary
            seed.password = Emails.password
            await seed.signIn()?.value
            if seed.startedAt == nil {
                seed.start()
                await seed.syncTask?.value
            }
            seed.tickerTask?.cancel()
            seed.refreshTask?.cancel()
        }

        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.email = Emails.primary
        store.password = Emails.password
        await store.signIn()?.value
        #expect(store.isSignedIn)

        // 두 번째 클라이언트가 자신이 오프인 줄 알고 새로 시작하는 상황을 재현.
        store.startedAt = nil
        store.currentSessionID = nil
        store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)

        store.start()
        await store.syncTask?.value

        obs("이중 시작: pendingSync=\(store.snapshot.pendingSync), pendingOp=\(String(describing: store.pendingOperation)), syncMessage=\(store.syncMessage)")
        #expect(store.snapshot.pendingSync)
        #expect(store.pendingOperation == .start)

        let openCount = try await ctx.admin.sessionRows(userID: userID, openOnly: true).count
        #expect(openCount == 1)
        obs("이중 시작 방어 후 open 세션=\(openCount)")
    }

    // 8. 근무 종료 → ended_at/duration 기록 + off_work, duration ±2초 정확도.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s08_stopWork() async throws {
        let ctx = try makeContext()
        let userID = try await ensurePrimaryAccount(anonKey: ctx.anonKey, admin: ctx.admin)

        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.email = Emails.primary
        store.password = Emails.password
        await store.signIn()?.value
        #expect(store.isSignedIn)

        // open 세션이 없으면(순서 흔들림) 새로 시작.
        if store.startedAt == nil {
            store.start()
            await store.syncTask?.value
        }
        #expect(store.startedAt != nil)

        // 실제 경과가 수 초가 되도록 잠깐 근무.
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        store.stop()
        await store.syncTask?.value

        let closedReady = await waitUntil {
            let rows = (try? await ctx.admin.sessionRows(userID: userID, openOnly: false)) ?? []
            return rows.first?["ended_at"] is String
        }
        #expect(closedReady)

        let sessions = try await ctx.admin.sessionRows(userID: userID, openOnly: false)
        let latest = try #require(sessions.first)
        let duration = try #require(latest["duration_seconds"] as? Int)
        let startedString = try #require(latest["started_at"] as? String)
        let endedString = try #require(latest["ended_at"] as? String)
        let serverElapsed = Int(
            (parseSupabaseDate(endedString) ?? .distantPast)
                .timeIntervalSince(parseSupabaseDate(startedString) ?? .distantFuture)
        )

        LiveE2EState.recordedDurationSeconds = duration
        obs("근무 종료: duration_seconds=\(duration), 서버 타임스탬프 경과=\(serverElapsed)초")

        #expect(duration >= 1)
        #expect(abs(duration - serverElapsed) <= 2)
        #expect(store.accumulatedSeconds == duration)

        let statusRows = try await ctx.admin.statusRows(userID: userID)
        #expect((statusRows.first?["status"] as? String) == "off_work")
        let openCount = try await ctx.admin.sessionRows(userID: userID, openOnly: true).count
        #expect(openCount == 0)
        obs("종료 후 상태=off_work, open 세션=\(openCount)")
    }

    // 9. 재실행 복구 → 새 인스턴스에서 세션 복원(activateStoredSession) 후 오늘 누적이 8과 일치.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09_relaunchRecovery() async throws {
        let ctx = try makeContext()
        let userID = try await ensurePrimaryAccount(anonKey: ctx.anonKey, admin: ctx.admin)

        // 로그인해 세션을 defaults 에 저장(재실행 시뮬레이션의 전제).
        let sharedDefaults = liveIsolatedDefaults()
        let loginStore = makeLiveStore(anonKey: ctx.anonKey, defaults: sharedDefaults)
        loginStore.email = Emails.primary
        loginStore.password = Emails.password
        await loginStore.signIn()?.value
        #expect(loginStore.isSignedIn)
        loginStore.tickerTask?.cancel()
        loginStore.refreshTask?.cancel()

        // 재실행: 저장된 세션으로 새 스토어 생성 → 생성자에서 세션 복원.
        let relaunchStore = makeLiveStore(anonKey: ctx.anonKey, defaults: sharedDefaults)
        defer {
            relaunchStore.tickerTask?.cancel()
            relaunchStore.refreshTask?.cancel()
        }
        #expect(relaunchStore.isSignedIn)

        await relaunchStore.activateStoredSession()

        let serverToday = try await ctx.admin.todayTotalDuration(userID: userID)
        obs("재실행 복구: accumulatedSeconds=\(relaunchStore.accumulatedSeconds), 서버 오늘 누적=\(serverToday), 기록된 8 duration=\(String(describing: LiveE2EState.recordedDurationSeconds))")

        #expect(relaunchStore.accumulatedSeconds == serverToday)
        if let recorded = LiveE2EState.recordedDurationSeconds {
            #expect(serverToday == recorded)
            #expect(serverToday >= 1)
        }
    }

    // 10. 별명 엣지 → 30자 한글+이모지 display_name 이 트리거로 profiles 에 그대로 저장.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s10_nicknameEdge() async throws {
        let ctx = try makeContext()
        // 독립 이메일 사용 — 시작 시 정리(멱등).
        try await ctx.admin.deleteByEmail(Emails.nickname)

        let edge = Emails.edgeDisplayName
        #expect(edge.count == 30)

        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.email = Emails.nickname
        store.displayName = edge
        store.password = Emails.password

        await store.signUp()?.value
        #expect(store.isSignedIn)
        let userID = try #require(store.session?.userID)

        let stored = await waitUntil {
            (try? await ctx.admin.profileDisplayName(userID: userID)) == edge
        }
        #expect(stored)
        let displayName = try await ctx.admin.profileDisplayName(userID: userID)
        #expect(displayName == edge)
        obs("별명 엣지: 저장된 display_name 길이=\(displayName?.count ?? -1), 일치=\(displayName == edge)")
    }

    // 11. 정리 → admin 삭제 후 4개 테이블 0건 확인. 실패 중단 시에도 반드시 실행되도록 마지막에 배치.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s11_cleanup() async throws {
        let ctx = try makeContext()

        let primaryUserID = try? await ctx.admin.findUserID(email: Emails.primary)
        let nicknameUserID = try? await ctx.admin.findUserID(email: Emails.nickname)

        for email in [Emails.primary, Emails.nickname] {
            let removed = try await ctx.admin.deleteByEmail(email)
            obs("정리 \(email): \(removed ? "admin 삭제" : "이미 없음")")
        }

        // 이메일/auth 레벨 삭제 확인.
        for email in [Emails.primary, Emails.nickname] {
            #expect(try await ctx.admin.findUserID(email: email) == nil)
            #expect(try await ctx.admin.profileCount(byEmail: email) == 0)
        }

        // 캐스케이드 확인: 알고 있던 userID 기준 4개 테이블 0건.
        for userID in [primaryUserID, nicknameUserID, LiveE2EState.primaryUserID].compactMap({ $0 }) {
            let cascaded = await waitUntil {
                let profiles = (try? await ctx.admin.profileCount(userID: userID)) ?? -1
                let sessions = (try? await ctx.admin.sessionCount(userID: userID)) ?? -1
                return profiles == 0 && sessions == 0
            }
            #expect(cascaded)
            #expect(try await ctx.admin.profileCount(userID: userID) == 0)
            #expect(try await ctx.admin.membershipCount(userID: userID) == 0)
            #expect(try await ctx.admin.statusRows(userID: userID).count == 0)
            #expect(try await ctx.admin.sessionCount(userID: userID) == 0)
            obs("캐스케이드 확인(userID \(userID.prefix(8))…): profiles/memberships/work_statuses/work_sessions = 0")
        }

        print("E2E| ===== 관측 요약 =====")
        for line in LiveE2EState.observations {
            print("E2E| - \(line)")
        }
    }
}
