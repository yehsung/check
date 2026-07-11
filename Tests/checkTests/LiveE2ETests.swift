import Foundation
import Testing
@testable import check

// 트랙 A — 라이브 E2E(초대코드 흐름).
// 실제 프로덕션 Supabase(xfnhfjvubetkdnfkfljg.supabase.co)에 실제 WorkTimerStore + 실제
// SupabaseWorkService(URLSession.shared)를 연결해 스토어 레벨로 전체 흐름을 구동한다.
// 게이팅: CHECK_E2E=1 일 때만 실행되며, 평소 swift test 에서는 전부 스킵된다.
// 이 초대코드 마이그레이션은 아직 원격에 미적용이므로 라이브 실행은 하지 않는다(컴파일 + 게이트오프 스킵만).
// anon key 는 /Users/yesung/check/.env.local 에서, 정리용 service_role 키는
// CHECK_E2E_SR_KEY_FILE 이 가리키는 apikeys.json 에서 읽는다. 키 원문은 절대 출력하지 않는다.
//
// 안전 규칙: 이 스위트는 오직 E2E 전용 계정과 "E2E-" 로 시작하는 이름의 팀만 만들고 지운다.
// 실팀(sudo 박수=SUDOPARK, 낭만러너 김유정=RUNNER01)과 그 소속 데이터는 절대 건드리지 않는다.

// MARK: - 에러/관측

private struct E2EError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private enum LiveE2EState {
    nonisolated(unsafe) static var ownerUserID: String?
    nonisolated(unsafe) static var joinerUserID: String?
    nonisolated(unsafe) static var e2eTeamID: String?
    nonisolated(unsafe) static var e2eTeamCode: String?
    nonisolated(unsafe) static var recordedDurationSeconds: Int?
    nonisolated(unsafe) static var observations: [String] = []
}

private func obs(_ line: String) {
    LiveE2EState.observations.append(line)
    print("E2E| \(line)")
}

// MARK: - 고정 QA 자격/문구

private enum Emails {
    // owner: E2E 전용 팀을 만드는 계정. joiner: 그 팀 코드로 합류하는 두 번째 계정.
    static let owner = "check.e2e.owner@gmail.com"
    static let joiner = "check.e2e.joiner@gmail.com"
    static let nickname = "check.e2e.nickname@gmail.com"
    static let ghost = "check.e2e.ghost.doesnotexist@gmail.com"
    static let password = "E2E-qa-Passw0rd!23"
    static let wrongPassword = "E2E-qa-WRONG-Passw0rd!99"
    // 30자(그래핌 기준) 한글 20 + 이모지 10.
    static let edgeDisplayName = "가나다라마바사아자차카타파하거너더러머버" + "🎉🚀✨🌟💪🔥😀🙌🐣🌈"
}

private enum E2ETeam {
    // 실팀과 절대 겹치지 않는 접두사. 생성/정리는 이 접두사로만 스코프한다.
    static let namePrefix = "E2E-리그-테스트"
    static let goalHours = 42
    static func uniqueName() -> String {
        "\(namePrefix)-\(UUID().uuidString.prefix(8))"
    }
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

    func membershipRows(userID: String) async throws -> [[String: Any]] {
        try await rows("memberships", [
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "select", value: "team_id,role")
        ])
    }

    func membershipCount(userID: String) async throws -> Int {
        try await membershipRows(userID: userID).count
    }

    func statusRows(userID: String) async throws -> [[String: Any]] {
        try await rows("work_statuses", [
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "select", value: "status,active_session_id,team_id")
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

    // MARK: 팀 헬퍼 (E2E 전용 팀만 스코프)

    /// 이름이 접두사로 시작하는 팀들. 실팀은 이 접두사를 절대 쓰지 않으므로 안전하다.
    func teams(namePrefix prefix: String) async throws -> [[String: Any]] {
        try await rows("teams", [
            URLQueryItem(name: "name", value: "like.\(prefix)*"),
            URLQueryItem(name: "select", value: "id,name,invite_code")
        ])
    }

    func teamName(id: String) async throws -> String? {
        try await rows("teams", [
            URLQueryItem(name: "id", value: "eq.\(id)"),
            URLQueryItem(name: "select", value: "name")
        ]).first?["name"] as? String
    }

    func teamExists(inviteCode: String) async throws -> Bool {
        try await rows("teams", [
            URLQueryItem(name: "invite_code", value: "eq.\(inviteCode)"),
            URLQueryItem(name: "select", value: "id")
        ]).isEmpty == false
    }

    func teamMemberCount(teamID: String) async throws -> Int {
        try await rows("memberships", [
            URLQueryItem(name: "team_id", value: "eq.\(teamID)"),
            URLQueryItem(name: "select", value: "user_id")
        ]).count
    }

    /// 안전 삭제: 반드시 이름 접두사가 E2E 접두사여야 지운다(실팀 보호 이중 가드).
    @discardableResult
    func deleteTeamIfE2E(id: String) async throws -> Bool {
        guard let name = try await teamName(id: id), name.hasPrefix(E2ETeam.namePrefix) else {
            return false
        }
        let (data, code) = try await send(
            path: "/rest/v1/teams",
            method: "DELETE",
            query: [URLQueryItem(name: "id", value: "eq.\(id)")]
        )
        guard code == 200 || code == 204 else {
            throw E2EError("팀 삭제 HTTP \(code): \(String(decoding: data, as: UTF8.self))")
        }
        return true
    }

    /// E2E 접두사 팀 전체 삭제(멱등 정리). 삭제한 개수를 돌려준다.
    @discardableResult
    func deleteAllE2ETeams() async throws -> Int {
        var deleted = 0
        for team in try await teams(namePrefix: E2ETeam.namePrefix) {
            if let id = team["id"] as? String, try await deleteTeamIfE2E(id: id) {
                deleted += 1
            }
        }
        return deleted
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

/// 만들기 모드로 가입하며 E2E 전용 팀을 새로 만든다(계정 + owner 멤버십 + 참여코드).
@MainActor
private func signUpCreatingE2ETeam(
    store: WorkTimerStore,
    email: String,
    displayName: String,
    teamName: String
) async {
    store.email = email
    store.displayName = displayName
    store.password = Emails.password
    store.isCreateTeamMode = true
    store.createTeamName = teamName
    store.createTeamGoalHours = E2ETeam.goalHours
    await store.signUp()?.value
}

/// 코드 모드로 가입하며 기존 팀에 합류한다(미리보기 확정 후 가입 → 자동 join_team).
@MainActor
private func signUpJoiningByCode(
    store: WorkTimerStore,
    email: String,
    displayName: String,
    code: String
) async {
    store.email = email
    store.displayName = displayName
    store.password = Emails.password
    store.isCreateTeamMode = false
    store.signupTeamCode = code
    await store.performPreviewTeamCode()
    await store.signUp()?.value
}

/// owner 계정과 E2E 팀이 반드시 존재하도록 보장하고 (userID, 팀코드) 를 돌려준다(순서 흔들림 대비 자가치유).
@MainActor
private func ensureOwnerAndTeam(anonKey: String, admin: E2EAdmin) async throws -> (userID: String, code: String) {
    if let userID = LiveE2EState.ownerUserID,
       let code = LiveE2EState.e2eTeamCode,
       (try? await admin.profileCount(userID: userID)) == 1,
       (try? await admin.teamExists(inviteCode: code)) == true {
        return (userID, code)
    }

    let store = makeLiveStore(anonKey: anonKey, defaults: liveIsolatedDefaults())
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    // 이미 계정이 있으면 로그인해 소유 팀 코드를 회수, 없으면 새로 만든다.
    if try await admin.findUserID(email: Emails.owner) != nil {
        store.email = Emails.owner
        store.password = Emails.password
        await store.signIn()?.value
        if let code = store.myTeamInviteCode, let teamID = store.currentTeamID {
            LiveE2EState.ownerUserID = store.session?.userID
            LiveE2EState.e2eTeamID = teamID
            LiveE2EState.e2eTeamCode = code
            if let userID = store.session?.userID {
                return (userID, code)
            }
        }
    }

    await signUpCreatingE2ETeam(
        store: store,
        email: Emails.owner,
        displayName: "E2E오너",
        teamName: E2ETeam.uniqueName()
    )
    guard let userID = store.session?.userID, let code = store.createdTeamCode else {
        throw E2EError("owner/E2E 팀 생성 실패: \(store.syncMessage)")
    }
    LiveE2EState.ownerUserID = userID
    LiveE2EState.e2eTeamID = store.currentTeamID
    LiveE2EState.e2eTeamCode = code
    return (userID, code)
}

// MARK: - 시나리오 스위트 (직렬 실행, 게이트 오프 시 전부 스킵)

@Suite(.serialized)
@MainActor
struct LiveE2ETests {

    // 0. 시작 전 잔존 QA 계정 + E2E 팀 admin 정리(멱등).
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s00_preCleanup() async throws {
        let ctx = try makeContext()
        for email in [Emails.owner, Emails.joiner, Emails.nickname] {
            let removed = try await ctx.admin.deleteByEmail(email)
            obs("사전정리 \(email): \(removed ? "잔존 계정 삭제" : "없음")")
        }
        let deletedTeams = try await ctx.admin.deleteAllE2ETeams()
        obs("사전정리 E2E 팀: \(deletedTeams)개 삭제")
        for email in [Emails.owner, Emails.joiner, Emails.nickname] {
            #expect(try await ctx.admin.findUserID(email: email) == nil)
        }
        #expect(try await ctx.admin.teams(namePrefix: E2ETeam.namePrefix).isEmpty)
    }

    // 1. 가입(무소속) → create_team 으로 E2E 전용 팀 생성 + owner 행 3종 + 참여코드 수신.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s01_signUpCreatesE2ETeamAsOwner() async throws {
        let ctx = try makeContext()
        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }

        await signUpCreatingE2ETeam(
            store: store,
            email: Emails.owner,
            displayName: "E2E오너",
            teamName: E2ETeam.uniqueName()
        )

        obs("팀 생성 가입: isSignedIn=\(store.isSignedIn), owner=\(store.isTeamOwner), syncMessage=\(store.syncMessage)")
        #expect(store.isSignedIn)
        let userID = try #require(store.session?.userID)
        let code = try #require(store.createdTeamCode)
        LiveE2EState.ownerUserID = userID
        LiveE2EState.e2eTeamID = store.currentTeamID
        LiveE2EState.e2eTeamCode = code

        // 참여코드는 8자, 헷갈리는 문자 제외 문자셋 사용.
        #expect(code.count == 8)
        #expect(store.myTeamInviteCode == code)
        #expect(store.isTeamOwner)

        let profileReady = await waitUntil {
            (try? await ctx.admin.profileCount(userID: userID)) == 1
        }
        #expect(profileReady)

        let memberships = try await ctx.admin.membershipRows(userID: userID)
        let statusRows = try await ctx.admin.statusRows(userID: userID)
        #expect(memberships.count == 1)
        #expect((memberships.first?["role"] as? String) == "owner")
        #expect(statusRows.count == 1)
        #expect((statusRows.first?["status"] as? String) == "off_work")
        #expect(try await ctx.admin.teamExists(inviteCode: code))
        obs("owner 행: memberships=1(owner), work_statuses=1(off_work), 팀코드 존재=true")
    }

    // 2. 두 번째 계정이 s01 코드로 join_team → 같은 팀 member 로 합류.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s02_secondAccountJoinsByCode() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        // 깨끗한 재실행을 위해 joiner 를 정리(멱등).
        try await ctx.admin.deleteByEmail(Emails.joiner)

        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }

        await signUpJoiningByCode(
            store: store,
            email: Emails.joiner,
            displayName: "E2E합류자",
            code: owner.code
        )

        obs("코드 합류 가입: isSignedIn=\(store.isSignedIn), teamID=\(store.currentTeamID ?? "nil"), owner=\(store.isTeamOwner)")
        #expect(store.isSignedIn)
        let joinerID = try #require(store.session?.userID)
        LiveE2EState.joinerUserID = joinerID

        // 미리보기가 owner 팀을 정확히 가리켰어야 한다.
        #expect(store.currentTeamID == LiveE2EState.e2eTeamID)
        #expect(!store.isTeamOwner)

        let memberships = try await ctx.admin.membershipRows(userID: joinerID)
        #expect(memberships.count == 1)
        #expect((memberships.first?["role"] as? String) == "member")
        #expect((memberships.first?["team_id"] as? String) == LiveE2EState.e2eTeamID)

        // 두 계정이 같은 팀에 있으므로 팀 인원은 2명.
        let teamID = try #require(LiveE2EState.e2eTeamID)
        let memberCount = try await ctx.admin.teamMemberCount(teamID: teamID)
        #expect(memberCount == 2)
        obs("합류 후 팀 인원=\(memberCount)(owner \(owner.userID.prefix(6))… + joiner \(joinerID.prefix(6))…)")
    }

    // 3. 틀린 비번 → 로그인 실패 + "로그인 정보 오류".
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s03_wrongPassword() async throws {
        let ctx = try makeContext()
        _ = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.email = Emails.owner
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

    // 5. 중복 가입 → 실제 GoTrue(autoconfirm) 응답 기준 문구 확인. 계정/팀을 복제하지 않는다.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s05_duplicateSignUp() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        let teamsBefore = try await ctx.admin.teams(namePrefix: E2ETeam.namePrefix).count
        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }

        // 이미 존재하는 owner 이메일로 팀 만들기 재시도 → 계정 생성 단계에서 막혀야 한다.
        await signUpCreatingE2ETeam(
            store: store,
            email: Emails.owner,
            displayName: "중복시도",
            teamName: E2ETeam.uniqueName()
        )

        let message = store.syncMessage
        obs("중복 가입: isSignedIn=\(store.isSignedIn), syncMessage=\(message)")
        #expect(!store.isSignedIn)
        #expect(message == "이미 가입된 이메일")
        // 계정도 팀도 새로 만들어지지 않았다(중복 가입은 create_team 까지 도달하지 않는다).
        #expect(try await ctx.admin.profileCount(byEmail: Emails.owner) == 1)
        #expect(try await ctx.admin.teams(namePrefix: E2ETeam.namePrefix).count == teamsBefore)
        _ = owner
    }

    // 6. 리더보드 가드 → 팀 소속 계정은 리그 행을 보고, 그 안에 우리 E2E 팀이 있다.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s06_leaderboardGuardForMember() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.email = Emails.owner
        store.password = Emails.password
        await store.signIn()?.value
        #expect(store.isSignedIn)

        await store.performLoadLeaderboard()

        // 소속이 있으므로 가드를 통과해 리그 행이 내려오고, 우리 팀이 포함된다.
        obs("리더보드 가드(member): 행수=\(store.leaderboard.count)")
        #expect(!store.leaderboard.isEmpty)
        #expect(store.leaderboard.contains { $0.id == LiveE2EState.e2eTeamID })
        _ = owner
    }

    // 7. 근무 시작/종료 → open→close 세션 + duration ±2초, off_work.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s07_startAndStopWork() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)

        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.email = Emails.owner
        store.password = Emails.password
        await store.signIn()?.value
        #expect(store.isSignedIn)

        if store.startedAt == nil {
            store.start()
            await store.syncTask?.value
        }
        #expect(store.startedAt != nil)

        try? await Task.sleep(nanoseconds: 3_000_000_000)

        store.stop()
        await store.syncTask?.value

        let closedReady = await waitUntil {
            let rows = (try? await ctx.admin.sessionRows(userID: owner.userID, openOnly: false)) ?? []
            return rows.first?["ended_at"] is String
        }
        #expect(closedReady)

        let sessions = try await ctx.admin.sessionRows(userID: owner.userID, openOnly: false)
        let latest = try #require(sessions.first)
        let duration = try #require(latest["duration_seconds"] as? Int)
        let startedString = try #require(latest["started_at"] as? String)
        let endedString = try #require(latest["ended_at"] as? String)
        let serverElapsed = Int(
            (parseSupabaseDate(endedString) ?? .distantPast)
                .timeIntervalSince(parseSupabaseDate(startedString) ?? .distantFuture)
        )

        LiveE2EState.recordedDurationSeconds = duration
        obs("근무 종료: duration_seconds=\(duration), 서버 경과=\(serverElapsed)초")

        #expect(duration >= 1)
        #expect(abs(duration - serverElapsed) <= 2)
        #expect(store.accumulatedSeconds == duration)

        let statusRows = try await ctx.admin.statusRows(userID: owner.userID)
        #expect((statusRows.first?["status"] as? String) == "off_work")
        #expect(try await ctx.admin.sessionRows(userID: owner.userID, openOnly: true).count == 0)
    }

    // 8. 재실행 복구 → 새 인스턴스에서 세션 복원 후 오늘 누적이 서버와 일치.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s08_relaunchRecovery() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)

        let sharedDefaults = liveIsolatedDefaults()
        let loginStore = makeLiveStore(anonKey: ctx.anonKey, defaults: sharedDefaults)
        loginStore.email = Emails.owner
        loginStore.password = Emails.password
        await loginStore.signIn()?.value
        #expect(loginStore.isSignedIn)
        loginStore.tickerTask?.cancel()
        loginStore.refreshTask?.cancel()

        let relaunchStore = makeLiveStore(anonKey: ctx.anonKey, defaults: sharedDefaults)
        defer {
            relaunchStore.tickerTask?.cancel()
            relaunchStore.refreshTask?.cancel()
        }
        #expect(relaunchStore.isSignedIn)

        await relaunchStore.activateStoredSession()

        let serverToday = try await ctx.admin.todayTotalDuration(userID: owner.userID)
        obs("재실행 복구: accumulatedSeconds=\(relaunchStore.accumulatedSeconds), 서버 오늘 누적=\(serverToday)")
        #expect(relaunchStore.accumulatedSeconds == serverToday)
    }

    // 9. 별명 엣지 → 30자 한글+이모지 display_name 이 트리거로 profiles 에 그대로 저장(코드 합류 흐름).
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09_nicknameEdge() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        try await ctx.admin.deleteByEmail(Emails.nickname)

        let edge = Emails.edgeDisplayName
        #expect(edge.count == 30)

        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }

        await signUpJoiningByCode(
            store: store,
            email: Emails.nickname,
            displayName: edge,
            code: owner.code
        )
        #expect(store.isSignedIn)
        let userID = try #require(store.session?.userID)

        let stored = await waitUntil {
            (try? await ctx.admin.profileDisplayName(userID: userID)) == edge
        }
        #expect(stored)
        #expect(try await ctx.admin.profileDisplayName(userID: userID) == edge)
        obs("별명 엣지: 저장 일치=\(try await ctx.admin.profileDisplayName(userID: userID) == edge)")
    }

    // 10. 정리 → E2E 계정 + E2E 팀 삭제 후 잔존 0 확인. 실팀(SUDOPARK/RUNNER01)은 그대로 살아 있어야 한다.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s10_cleanup() async throws {
        let ctx = try makeContext()

        let ownerUserID = try? await ctx.admin.findUserID(email: Emails.owner)
        let joinerUserID = try? await ctx.admin.findUserID(email: Emails.joiner)
        let nicknameUserID = try? await ctx.admin.findUserID(email: Emails.nickname)

        for email in [Emails.owner, Emails.joiner, Emails.nickname] {
            let removed = try await ctx.admin.deleteByEmail(email)
            obs("정리 \(email): \(removed ? "admin 삭제" : "이미 없음")")
        }

        // 계정 캐스케이드로 멤버십/상태/세션은 사라지지만, teams 행은 팀 삭제로 별도 정리한다(E2E 접두사만).
        let deletedTeams = try await ctx.admin.deleteAllE2ETeams()
        obs("정리 E2E 팀: \(deletedTeams)개 삭제")

        for email in [Emails.owner, Emails.joiner, Emails.nickname] {
            #expect(try await ctx.admin.findUserID(email: email) == nil)
            #expect(try await ctx.admin.profileCount(byEmail: email) == 0)
        }

        for userID in [ownerUserID, joinerUserID, nicknameUserID,
                       LiveE2EState.ownerUserID, LiveE2EState.joinerUserID].compactMap({ $0 }) {
            let cascaded = await waitUntil {
                let profiles = (try? await ctx.admin.profileCount(userID: userID)) ?? -1
                let sessions = (try? await ctx.admin.sessionCount(userID: userID)) ?? -1
                return profiles == 0 && sessions == 0
            }
            #expect(cascaded)
            #expect(try await ctx.admin.membershipCount(userID: userID) == 0)
            #expect(try await ctx.admin.statusRows(userID: userID).count == 0)
        }

        // E2E 팀은 모두 사라졌고, 실팀 코드는 여전히 살아 있다(정규화 조회 기준 존재).
        #expect(try await ctx.admin.teams(namePrefix: E2ETeam.namePrefix).isEmpty)
        #expect(try await ctx.admin.teamExists(inviteCode: "SUDOPARK"))

        print("E2E| ===== 관측 요약 =====")
        for line in LiveE2EState.observations {
            print("E2E| - \(line)")
        }
    }
}
