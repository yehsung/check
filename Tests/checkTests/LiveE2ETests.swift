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
// E2E 접두사가 아닌 데이터(실사용 계정/팀)는 절대 건드리지 않는다.

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
    // s09y 전용 일회성 계정 — 표시명 충돌 시 가입이 성공하는지만 본다. owner/joiner/nickname 셋 중
    // 아무거나 재사용하면 그 계정의 표시명이 '-2' 로 바뀌어 뒤따르는 별명 시나리오의 기대값이 흔들린다.
    static let dupName = "check.e2e.dupname@gmail.com"
    static let ghost = "check.e2e.ghost.doesnotexist@gmail.com"
    static let password = "E2E-qa-Passw0rd!23"
    static let wrongPassword = "E2E-qa-WRONG-Passw0rd!99"
    // 30자(그래핌 기준) 한글 20 + 이모지 10.
    // 이 값을 ZWJ(U+200D) 포함 이모지로 바꿔도 서버는 U+200D 를 지우지 않는다(normalize_display_name 이
    // 보존한다 — 지우면 "👨‍👩‍👧" 같은 결합 이름이 조각난다). 대신 유일성 키(display_name_key)에서는 무시된다.
    // **무시 대상은 ZWJ 하나가 아니다** — 키는 U+115F/U+1160/U+180E/U+200D/U+2800/U+3164/U+FE0F 를 전부
    // 지운다(20260804010000 의 2번 주석에 각각이 왜 필요한지 적혀 있다). 그래서 '이름+보이지 않는 한 글자'는
    // 새 계정으로도 통과하지 못하고(taken), 그런 글자만으로 만든 이름은 invalid_empty 다.
    static let edgeDisplayName = "가나다라마바사아자차카타파하거너더러머버" + "🎉🚀✨🌟💪🔥😀🙌🐣🌈"
    /// 이 스위트가 만들고 지우는 계정 전부. **새 E2E 계정을 더하면 반드시 여기에도 넣어라** —
    /// 빠뜨리면 s00/s10 이 그 계정을 지우지 않아 다음 실행이 지난 실행의 표시명·쿨타임을 물려받는다.
    static let managed: [String] = [owner, joiner, nickname, dupName]
}

/// v0.2.16 별명/울트라 시나리오가 공유하는 고정 문자열. 실사용자 26명의 이름과 절대 겹치지 않게 'E2E' 로 시작한다.
private enum E2ENames {
    static let ownerBase = "E2E오너"
    static let joinerBase = "E2E합류자"
    // 아래 넷은 전부 서버 max_len(12) 이하다 — 넘으면 invalid_long 이 나서 시나리오가 무의미해진다.
    static let first = "E2E별명하나"      // 7자
    static let second = "E2E별명둘"       // 6자
    static let raceA = "E2E동시A"         // 6자
    static let raceB = "E2E동시B"         // 6자
    static let duplicate = "E2E중복이름"   // 7자
    /// `first` 와 **유일성 키가 같은** 변형: 대문자→소문자 + 공백 삽입/앞뒤 공백.
    /// display_name_key 는 lower + 모든 공백 제거이므로 둘 다 'e2e별명하나' 로 접힌다.
    static let firstVariant = "  e2e  별명 하나  "
    /// 13자 — 서버 max_len(12)를 정확히 1 넘긴다.
    static let tooLong = "일이삼사오육칠팔구십일이삼"
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

    func teamWeeklyGoalHours(id: String) async throws -> Int? {
        try await rows("teams", [
            URLQueryItem(name: "id", value: "eq.\(id)"),
            URLQueryItem(name: "select", value: "weekly_goal_hours")
        ]).first?["weekly_goal_hours"] as? Int
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

    // MARK: 방치 세션 자동 마감 셋업/검증 (E2E owner 계정만 조작)

    /// owner 의 열린(ended_at null) 세션을 모두 닫는다(방치 세션 셋업 전 유니크 제약 충돌 방지, 멱등).
    func closeOpenSessions(userID: String) async throws {
        let iso = ISO8601DateFormatter()
        let body = try JSONSerialization.data(withJSONObject: [
            "ended_at": iso.string(from: Date()),
            "duration_seconds": 0
        ])
        let (data, code) = try await send(
            path: "/rest/v1/work_sessions",
            method: "PATCH",
            query: [
                URLQueryItem(name: "user_id", value: "eq.\(userID)"),
                URLQueryItem(name: "ended_at", value: "is.null")
            ],
            body: body,
            prefer: "return=minimal"
        )
        guard code == 200 || code == 204 else {
            throw E2EError("열린 세션 정리 HTTP \(code): \(String(decoding: data, as: UTF8.self))")
        }
    }

    /// admin 으로 열린 세션을 삽입하고 id 를 돌려준다(자동 마감 함수 검증용 셋업).
    func insertOpenSession(teamID: String, userID: String, startedAt: Date) async throws -> String {
        let iso = ISO8601DateFormatter()
        let body = try JSONSerialization.data(withJSONObject: [
            "team_id": teamID,
            "user_id": userID,
            "started_at": iso.string(from: startedAt)
        ])
        let (data, code) = try await send(
            path: "/rest/v1/work_sessions",
            method: "POST",
            body: body,
            prefer: "return=representation"
        )
        guard code == 201 || code == 200 else {
            throw E2EError("세션 삽입 HTTP \(code): \(String(decoding: data, as: UTF8.self))")
        }
        let rows = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        guard let id = rows.first?["id"] as? String else {
            throw E2EError("세션 삽입 응답에 id 없음")
        }
        return id
    }

    /// admin 으로 work_status 를 upsert 한다(마지막 신호 시각을 과거로 조작해 방치 상태를 만든다).
    func upsertWorkStatus(teamID: String, userID: String, status: String, activeSessionID: String?, lastSeenAt: Date) async throws {
        let iso = ISO8601DateFormatter()
        let sessionValue: Any = activeSessionID ?? NSNull()
        let body = try JSONSerialization.data(withJSONObject: [
            "team_id": teamID,
            "user_id": userID,
            "status": status,
            "active_session_id": sessionValue,
            "last_seen_at": iso.string(from: lastSeenAt),
            "updated_at": iso.string(from: lastSeenAt)
        ])
        let (data, code) = try await send(
            path: "/rest/v1/work_statuses",
            method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: "team_id,user_id")],
            body: body,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
        guard code == 200 || code == 201 || code == 204 else {
            throw E2EError("work_status upsert HTTP \(code): \(String(decoding: data, as: UTF8.self))")
        }
    }

    /// service_role 로 close_abandoned_work_sessions() RPC 를 호출하고 마감 건수를 돌려준다.
    func callCloseAbandonedSessions() async throws -> Int {
        let (data, code) = try await send(
            path: "/rest/v1/rpc/close_abandoned_work_sessions",
            method: "POST",
            body: Data("{}".utf8)
        )
        guard code == 200 else {
            throw E2EError("close_abandoned RPC HTTP \(code): \(String(decoding: data, as: UTF8.self))")
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(text) ?? 0
    }

    /// E2E 계정의 특정 월 토큰 원장 행을 전부 지운다(멱등 정리). 기기별 표와 옛 표(v0.2.10 폴백용) 양쪽을 비운다 —
    /// 이전 실행이 남긴 다른 device_id 행이나 옛 표 행이 보드 합산/폴백에 섞여 기대값을 흔들 수 있기 때문이다.
    /// E2E 전용 계정 user_id 로만 스코프한다 — 실사용 계정 데이터는 절대 건드리지 않는다.
    func deleteTokenUsageRows(userID: String, month: String) async throws {
        for table in ["token_usage_device_monthly", "token_usage_monthly"] {
            let (data, code) = try await send(
                path: "/rest/v1/\(table)",
                method: "DELETE",
                query: [
                    URLQueryItem(name: "user_id", value: "eq.\(userID)"),
                    URLQueryItem(name: "month", value: "eq.\(month)")
                ],
                prefer: "return=minimal"
            )
            guard code == 200 || code == 204 else {
                throw E2EError("토큰 원장 정리(\(table)) HTTP \(code): \(String(decoding: data, as: UTF8.self))")
            }
        }
    }

    /// admin 으로 **옛 표**(token_usage_monthly)에 한 줄을 upsert 한다 — 아직 v0.2.10 인 맥이 올린 상태의 재현.
    /// (v0.2.11 클라도 이 표에 쓰지만 '행을 깎지 않을 때만' 쓰므로, 더 큰 타 기기 값은 service_role 로 심는다.)
    func upsertLegacyTokenUsage(userID: String, month: String, total: Int, todayTotal: Int, todayDate: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "user_id": userID,
            "month": month,
            "claude_input": total,
            "total": total,
            "today_total": todayTotal,
            "today_date": todayDate
        ])
        let (data, code) = try await send(
            path: "/rest/v1/token_usage_monthly",
            method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: "user_id,month")],
            body: body,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
        guard code == 200 || code == 201 || code == 204 else {
            throw E2EError("옛 토큰 원장 upsert HTTP \(code): \(String(decoding: data, as: UTF8.self))")
        }
    }

    /// 옛 표(token_usage_monthly)의 그 달 총량(행이 없으면 nil). v0.2.11 클라가 남의 더 큰 값을 깎지 않는지 실증용.
    func legacyTokenUsageTotal(userID: String, month: String) async throws -> Int? {
        try await rows("token_usage_monthly", [
            URLQueryItem(name: "select", value: "total"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "month", value: "eq.\(month)")
        ]).first?["total"] as? Int
    }

    /// admin 으로 **옛 표** 행의 updated_at 을 과거로 민다 — '기기 행보다 먼저 쓰이고 그 뒤로 갱신이 끊긴 행'
    /// (= 화석) 을 재현하는 유일한 수단이다. 마이그레이션의 touch 트리거는 **명시적으로 과거 시각을 실은 쓰기**만
    /// 그 값을 보존하고 그 밖의 모든 쓰기는 now() 로 덮으므로, 앱(이 컬럼을 절대 보내지 않는다)의 동작은 그대로다.
    /// 이 픽스처가 없으면 옛 행을 심는 순간 updated_at 이 now() 가 되어 화석 판정이 영원히 성립하지 않는다.
    /// 달로 좁히지 않는다 — 보드의 '살아 있는 구버전 맥' 판정(legacy_live)이 달 무관이라, 다른 달에 남은 행이
    /// 하나라도 최근 시각이면 재현이 흔들린다. E2E 전용 계정 user_id 로만 스코프한다.
    func backdateLegacyTokenUsage(userID: String, updatedAt: Date) async throws {
        let iso = ISO8601DateFormatter()
        let body = try JSONSerialization.data(withJSONObject: ["updated_at": iso.string(from: updatedAt)])
        let (data, code) = try await send(
            path: "/rest/v1/token_usage_monthly",
            method: "PATCH",
            query: [URLQueryItem(name: "user_id", value: "eq.\(userID)")],
            body: body,
            prefer: "return=minimal"
        )
        guard code == 200 || code == 204 else {
            throw E2EError("옛 토큰 원장 updated_at 백데이트 HTTP \(code): \(String(decoding: data, as: UTF8.self))")
        }
    }

    /// admin 으로 기기별 원장 행의 created_at 을 과거로 민다 — 보드의 7일 유예(now() - first_at <= 7 days)를
    /// 넘긴 상태(업그레이드한 지 오래된 계정)를 재현한다. 이 표에는 touch 트리거가 없어 값이 그대로 남는다.
    /// 기준 시각 first_at 은 **달 무관 최솟값**이므로 그 계정의 기기 행 전체를 민다(달로 좁히면 다른 달의 행이
    /// 최솟값을 '방금'으로 되돌려 유예가 계속 살아 있다).
    func backdateDeviceTokenUsage(userID: String, createdAt: Date) async throws {
        let iso = ISO8601DateFormatter()
        let body = try JSONSerialization.data(withJSONObject: ["created_at": iso.string(from: createdAt)])
        let (data, code) = try await send(
            path: "/rest/v1/token_usage_device_monthly",
            method: "PATCH",
            query: [URLQueryItem(name: "user_id", value: "eq.\(userID)")],
            body: body,
            prefer: "return=minimal"
        )
        guard code == 200 || code == 204 else {
            throw E2EError("기기 원장 created_at 백데이트 HTTP \(code): \(String(decoding: data, as: UTF8.self))")
        }
    }

    /// 옛 표 행의 updated_at 이 기준 시각보다 과거로 **남아 있는지**(트리거가 now() 로 덮지 않았는지) 확인한다.
    /// 백데이트 픽스처가 실제로 먹혔다는 전제를 단언으로 못 박는 데 쓴다.
    func legacyTokenUsageOlder(userID: String, month: String, than: Date) async throws -> Bool {
        let iso = ISO8601DateFormatter()
        return try await rows("token_usage_monthly", [
            URLQueryItem(name: "select", value: "user_id"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "month", value: "eq.\(month)"),
            URLQueryItem(name: "updated_at", value: "lt.\(iso.string(from: than))")
        ]).isEmpty == false
    }

    /// 특정 계정의 그 달 기기별 원장 행 수(기기별로 쪼개졌는지 실증하는 관측용).
    func tokenUsageRowCount(userID: String, month: String) async throws -> Int {
        try await rows("token_usage_device_monthly", [
            URLQueryItem(name: "select", value: "device_id"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "month", value: "eq.\(month)")
        ]).count
    }

    // MARK: 별명(표시명) 픽스처 — 20260804010000/20260804020000 검증용, E2E 계정 user_id 로만 스코프

    /// admin 으로 profiles 한 행을 PATCH 한다. **service_role 이 필요한 이유가 이 설계의 전부다** —
    /// 20260804020000 이 authenticated 의 표 단위 UPDATE 를 회수했으므로 사용자 토큰으로는
    /// display_name 을 되돌릴 수 없다(그게 그 마이그레이션의 목적이다). 픽스처는 admin 만 만들 수 있다.
    private func patchProfile(userID: String, body: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: body)
        let (payload, code) = try await send(
            path: "/rest/v1/profiles",
            method: "PATCH",
            query: [URLQueryItem(name: "id", value: "eq.\(userID)")],
            body: data,
            prefer: "return=minimal"
        )
        guard code == 200 || code == 204 else {
            throw E2EError("profiles PATCH HTTP \(code): \(String(decoding: payload, as: UTF8.self))")
        }
    }

    /// display_name_changed_at 을 null 로 지운다. **이 헬퍼가 s10 에만 있으면 안 되는 이유**:
    /// release.md 의 확인 명령은 --filter 로 s09w/s09x/s09y 만 돌려 s10_cleanup 을 실행하지 않는다.
    /// 그러면 같은 주에 두 번째 릴리스를 낼 때 s09w 가 cooldown 으로 빨개져 배포가 멈춘다
    /// (그리고 원인이 '기능 고장'처럼 보인다).
    func clearDisplayNameCooldown(userID: String) async throws {
        try await patchProfile(userID: userID, body: ["display_name_changed_at": NSNull()])
    }

    /// 표시명을 admin 권한으로 되돌린다(RPC 쿨타임을 태우지 않는다 — set_display_name 을 거치지 않으므로).
    func setDisplayName(userID: String, to name: String) async throws {
        try await patchProfile(userID: userID, body: ["display_name": name])
    }

    /// display_name_changed_at 을 임의 시각으로 민다(쿨타임 만료 시뮬레이션). nil 이면 지운다.
    func setDisplayNameChangedAt(userID: String, to date: Date?) async throws {
        var body: [String: Any] = ["display_name_changed_at": NSNull()]
        if let date {
            body["display_name_changed_at"] = ISO8601DateFormatter().string(from: date)
        }
        try await patchProfile(userID: userID, body: body)
    }

    /// 현재 display_name_changed_at(없으면 nil). '실패한 시도가 쿨타임을 소모하지 않는다'를 단언하려면
    /// 시도 전후를 비교해야 하는데, 이 값은 사용자 토큰으로 못 고치므로 admin 이 진실의 유일한 창구다.
    func displayNameChangedAt(userID: String) async throws -> Date? {
        let raw = try await rows("profiles", [
            URLQueryItem(name: "id", value: "eq.\(userID)"),
            URLQueryItem(name: "select", value: "display_name_changed_at")
        ]).first?["display_name_changed_at"] as? String
        return raw.flatMap(parseSupabaseDate)
    }

    /// 아바타 URL(없으면 nil). 원복 픽스처는 **원래 값을 알아야** 되돌릴 수 있다.
    func profileAvatarURL(userID: String) async throws -> String? {
        try await rows("profiles", [
            URLQueryItem(name: "id", value: "eq.\(userID)"),
            URLQueryItem(name: "select", value: "avatar_url")
        ]).first?["avatar_url"] as? String
    }

    /// 토큰 공개 여부(행이 없으면 nil).
    func profileTokenUsagePublic(userID: String) async throws -> Bool? {
        try await rows("profiles", [
            URLQueryItem(name: "id", value: "eq.\(userID)"),
            URLQueryItem(name: "select", value: "token_usage_public")
        ]).first?["token_usage_public"] as? Bool
    }

    /// 아바타 URL 원복(nil 이면 지운다). s09x 가 대조군으로 심은 가짜 URL 을 남기면 이후 관측이 흐려진다
    /// (깨진 이미지가 뜨는 계정이 하나 생긴다).
    func setAvatarURL(userID: String, to url: String?) async throws {
        var body: [String: Any] = ["avatar_url": NSNull()]
        if let url { body["avatar_url"] = url }
        try await patchProfile(userID: userID, body: body)
    }

    /// 토큰 공개 설정 원복. s09x 가 대조군으로 false 를 심으므로 원래 값으로 되돌린다
    /// (안 되돌리면 s09e/s09g 의 보드 기대값이 흔들린다).
    func setTokenUsagePublic(userID: String, to isPublic: Bool) async throws {
        try await patchProfile(userID: userID, body: ["token_usage_public": isPublic])
    }

    // MARK: 울트라 찌르기 픽스처 — 하루 한도 장부가 pokes 행 자체라 정리가 곧 리셋이다

    private func deletePokes(fromUser userID: String, extraQuery: [URLQueryItem]) async throws {
        let (data, code) = try await send(
            path: "/rest/v1/pokes",
            method: "DELETE",
            query: [URLQueryItem(name: "from_user", value: "eq.\(userID)")] + extraQuery,
            prefer: "return=minimal"
        )
        guard code == 200 || code == 204 else {
            throw E2EError("pokes 정리 HTTP \(code): \(String(decoding: data, as: UTF8.self))")
        }
    }

    /// 해당 계정이 **보낸** kind='ultra' 행만 지운다. from_user = <E2E 계정 uid> 로만 스코프한다 —
    /// 실사용자 26명의 pokes 행은 절대 만지지 않는다(to_user 로는 절대 스코프하지 않는다).
    func deleteUltraPokes(fromUser userID: String) async throws {
        try await deletePokes(fromUser: userID, extraQuery: [URLQueryItem(name: "kind", value: "eq.ultra")])
    }

    /// 해당 계정이 보낸 찔림을 종류 무관 전부 지운다. 울트라 시나리오의 진입 정리에 필요하다 —
    /// 하루 한도(울트라 행)뿐 아니라 **60초 쿨타임(일반 행 포함 max(created_at))** 까지 리셋해야
    /// s09f 직후에 실행돼도 첫 울트라가 cooldown 이 아니라 ok 로 나온다.
    func deleteAllPokes(fromUser userID: String) async throws {
        try await deletePokes(fromUser: userID, extraQuery: [])
    }

    /// 해당 계정이 보낸 찔림의 created_at 을 과거로 민다 — **60초 쿨타임만 만료시키고 하루 한도는 그대로 두는**
    /// 유일한 수단이다(행을 지우면 한도 장부까지 리셋된다). 대상 계정을 하나밖에 못 세운 환경에서
    /// 울트라를 연속 두 번 보내려면 이게 필요하다. E2E 계정 from_user 로만 스코프한다.
    func backdatePokes(fromUser userID: String, createdAt: Date) async throws {
        let iso = ISO8601DateFormatter()
        let body = try JSONSerialization.data(withJSONObject: ["created_at": iso.string(from: createdAt)])
        let (data, code) = try await send(
            path: "/rest/v1/pokes",
            method: "PATCH",
            query: [URLQueryItem(name: "from_user", value: "eq.\(userID)")],
            body: body,
            prefer: "return=minimal"
        )
        guard code == 200 || code == 204 else {
            throw E2EError("pokes created_at 백데이트 HTTP \(code): \(String(decoding: data, as: UTF8.self))")
        }
    }

    /// 해당 계정이 보낸 울트라 행 수. 하루 한도 장부가 별도 표가 아니라 pokes 행 자체라는 계약의 관측 창구다
    /// (진입에서 전부 지우므로 시나리오 안에서는 곧 '오늘 쓴 횟수'다).
    func ultraPokeCount(fromUser userID: String) async throws -> Int {
        try await rows("pokes", [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "from_user", value: "eq.\(userID)"),
            URLQueryItem(name: "kind", value: "eq.ultra")
        ]).count
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

/// 사용자 **본인 JWT** 로 PostgREST 를 직접 호출한다(SupabaseWorkService 를 통째로 우회).
/// 이 헬퍼가 필요한 이유는 하나뿐이다: 앱에는 display_name 을 PATCH 하는 함수가 **아예 없어서**,
/// "우회 PATCH 가 서버 권한만으로 막히는가"를 우리 코드로는 원리적으로 실증할 수 없다.
/// 악의적 클라(또는 curl)를 그대로 흉내 내야 (a) 컬럼 단위 UPDATE 잠금이 진짜로 작동하는지 알 수 있다.
private func userRest(
    anonKey: String,
    accessToken: String,
    path: String,
    method: String,
    query: [URLQueryItem] = [],
    json: [String: Any]? = nil,
    prefer: String? = "return=minimal"
) async throws -> (status: Int, body: String) {
    var components = URLComponents(
        url: SupabaseConfig.projectURL.appending(path: path),
        resolvingAgainstBaseURL: false
    )!
    components.queryItems = query.isEmpty ? nil : query
    guard let url = components.url else { throw E2EError("잘못된 URL: \(path)") }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue(anonKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
    if let json {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
    }
    let session = URLSession(configuration: .ephemeral)
    let (data, response) = try await session.data(for: request)
    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
    return (code, String(decoding: data, as: UTF8.self))
}

@MainActor
private func makeContext() throws -> (anonKey: String, admin: E2EAdmin) {
    let anonKey = try LiveE2EEnv.anonKey()
    let admin = E2EAdmin(serviceKey: try LiveE2EEnv.serviceRoleKey())
    return (anonKey, admin)
}

/// **로그인 없이**(anon 키만, 사용자 JWT 없음) PostgREST 를 호출한다. 공개 cask 에서 anon 키를 꺼낸
/// 익명 공격자를 그대로 흉내 낸다 — RPC 실행권이 anon 에서 회수됐는지는 이 경로로만 실증된다.
private func anonRest(
    anonKey: String,
    path: String,
    method: String = "POST",
    json: [String: Any]? = nil
) async throws -> (status: Int, body: String) {
    let url = SupabaseConfig.projectURL.appending(path: path)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue(anonKey, forHTTPHeaderField: "apikey")
    // Authorization 을 일부러 붙이지 않는다 → PostgREST 가 anon 역할로 실행한다.
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let json {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
    }
    let session = URLSession(configuration: .ephemeral)
    let (data, response) = try await session.data(for: request)
    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
    return (code, String(decoding: data, as: UTF8.self))
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
        for email in Emails.managed {
            let removed = try await ctx.admin.deleteByEmail(email)
            obs("사전정리 \(email): \(removed ? "잔존 계정 삭제" : "없음")")
        }
        let deletedTeams = try await ctx.admin.deleteAllE2ETeams()
        obs("사전정리 E2E 팀: \(deletedTeams)개 삭제")
        for email in Emails.managed {
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
        // member_count 컬럼(20260712010000 마이그레이션)이 아직 라이브에 없어도 디코드는 호환된다
        // (TeamLeaderboardRow.memberCount 는 optional → 누락 시 0, 평균은 0명 가드). 여기선 행 존재만 본다.
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
        // 로컬 시계 경과와 서버 타임스탬프(초 단위 절삭) 계산은 ±1초 위상차가 생길 수 있다.
        // 다음 새로고침에서 서버값으로 수렴하므로 ±2초 허용.
        #expect(abs(store.accumulatedSeconds - duration) <= 2)

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
        // 재실행 복구값은 서버 기준으로 세팅되지만, s07 직후 로컬-서버 초 절삭 위상차가 남을 수 있어 ±2초 허용.
        #expect(abs(relaunchStore.accumulatedSeconds - serverToday) <= 2)
    }

    // 8b. anon 노출 회귀 방어 — 20260809120000 마이그레이션이 데이터 RPC 를 anon 에서 회수했는지 실서버로 확인.
    // 회귀 지점: 공개 cask 의 anon 키만으로 로그인 없이 token_usage_board 를 호출하면 전 사용자 이름·아바타·
    // 토큰이 그대로 반환됐다(2026-08-09 실증). 반대로 lookup_team_by_code(가입 전 팀코드 미리보기)는 anon 이
    // 계속 실행할 수 있어야 한다 — 이 두 계약을 한 테스트로 고정한다.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s08b_anonRpcExposureIsLocked() async throws {
        let ctx = try makeContext()

        // 유출됐던 데이터 RPC 들은 로그인 없이는 401/403 이어야 한다(실행권 없음 = permission denied).
        let leaky: [(path: String, body: [String: Any])] = [
            ("/rest/v1/rpc/token_usage_board", ["p_month": "2026-08"]),
            ("/rest/v1/rpc/team_weekly_leaderboard", [:]),
            ("/rest/v1/rpc/app_user_directory", [:]),
        ]
        for rpc in leaky {
            let res = try await anonRest(anonKey: ctx.anonKey, path: rpc.path, json: rpc.body)
            obs("anon \(rpc.path) → HTTP \(res.status)")
            #expect(res.status == 401 || res.status == 403, "anon 이 \(rpc.path) 를 실행할 수 있으면 안 된다 (HTTP \(res.status))")
        }

        // 가입 전 팀코드 미리보기는 반대로 anon 이 실행 가능해야 한다(없는 코드라 0행이지만 200/2xx).
        let lookup = try await anonRest(
            anonKey: ctx.anonKey,
            path: "/rest/v1/rpc/lookup_team_by_code",
            json: ["code": "ZZZZZZZZ"]
        )
        obs("anon lookup_team_by_code → HTTP \(lookup.status)")
        #expect(lookup.status == 200, "가입 전 팀코드 미리보기는 anon 이 실행할 수 있어야 한다 (HTTP \(lookup.status))")
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

    // 9b. 방치 세션 서버 자동 마감(RPC 직접 검증, cron 대기 없이 함수 자체를 검증).
    // admin 으로 owner 의 열린 세션 + last_seen_at 을 11분 전으로 조작 → service_role 로 RPC 직접 호출 →
    // 세션이 마지막 신호 시각으로 마감되고(off_work) 열린 세션이 사라졌는지 검증. E2E 접두사 스코프 밖 접근 금지.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09b_autoCloseAbandonedSessionViaRPC() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        let teamID = try #require(LiveE2EState.e2eTeamID)

        // 방치 상황 셋업: 2시간 전 시작한 열린 세션 + 마지막 신호 11분 전(>10분) working 상태.
        // 기존 열린 세션이 있으면 유니크 제약(one_open_per_user)에 걸리므로 먼저 정리한다(멱등).
        try await ctx.admin.closeOpenSessions(userID: owner.userID)
        let startedAt = Date().addingTimeInterval(-2 * 3600)
        let staleSignal = Date().addingTimeInterval(-11 * 60)
        let sessionID = try await ctx.admin.insertOpenSession(teamID: teamID, userID: owner.userID, startedAt: startedAt)
        try await ctx.admin.upsertWorkStatus(
            teamID: teamID, userID: owner.userID, status: "working",
            activeSessionID: sessionID, lastSeenAt: staleSignal
        )

        // service_role 로 RPC 직접 호출 — cron 을 기다리지 않고 함수 자체를 검증한다.
        let closed = try await ctx.admin.callCloseAbandonedSessions()
        obs("방치 자동마감 RPC: 마감 건수=\(closed)")
        #expect(closed >= 1)

        // 세션이 마지막 신호 시각으로 마감됐다: ended_at ≈ staleSignal, duration ≈ (마지막신호 - 시작).
        let sessions = try await ctx.admin.sessionRows(userID: owner.userID, openOnly: false)
        let closedSession = try #require(sessions.first { ($0["id"] as? String) == sessionID })
        let endedString = try #require(closedSession["ended_at"] as? String)
        let endedDate = try #require(parseSupabaseDate(endedString))
        #expect(abs(endedDate.timeIntervalSince(staleSignal)) <= 2)
        let duration = try #require(closedSession["duration_seconds"] as? Int)
        let expectedDuration = Int(staleSignal.timeIntervalSince(startedAt))
        #expect(abs(duration - expectedDuration) <= 2)

        // 상태가 off_work 로 바뀌고 열린 세션이 없다.
        let statusRows = try await ctx.admin.statusRows(userID: owner.userID)
        #expect((statusRows.first?["status"] as? String) == "off_work")
        #expect(try await ctx.admin.sessionRows(userID: owner.userID, openOnly: true).count == 0)
        obs("방치 자동마감 검증: ended_at≈마지막신호, duration≈\(expectedDuration)초, status=off_work")
    }

    // 9c. 좀비 '근무중' 부활 차단(하트비트 부활 → before-trigger 강등, 20260717040000 마이그레이션 검증).
    // E2E owner 로 근무 시작(열린 세션 생성) → admin 으로 그 세션을 강제 마감(ended_at 세팅) →
    // 같은 계정 토큰으로 service.heartbeat(status='working') 부활 시도 → 열린 세션이 없으므로
    // work_statuses 가 트리거로 off_work 로 강등되고 active_session_id 가 비워졌는지 단언.
    // E2E 접두사 스코프 밖 접근 금지, 키 원문 출력 금지.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09c_blockZombieWorkingRevivalViaTrigger() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        let teamID = try #require(LiveE2EState.e2eTeamID)

        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.email = Emails.owner
        store.password = Emails.password
        await store.signIn()?.value
        #expect(store.isSignedIn)
        let accessToken = try #require(store.session?.accessToken)

        // 결정적 셋업: 앞 시나리오가 남긴 잔존 열린 세션과 refresh 복원 개입을 제거한다.
        // (1) 복원 루프를 start() 전에 멈추고, (2) admin 으로 열린 세션을 선제 정리해
        // startWork 의 one_open_per_user 유니크 충돌(409 sessionAlreadyOpen)을 막는다.
        store.refreshTask?.cancel()
        try await ctx.admin.closeOpenSessions(userID: owner.userID)

        // 복원으로 이미 근무중(startedAt != nil)이면 먼저 종료한다 — stop 이 서버 work_statuses 를 off_work 로
        // 내려 좀비 상태를 지우므로, 이후 항상 새 세션으로 깨끗이 시작한다.
        if store.startedAt != nil {
            store.stop()
            await store.syncTask?.value
        }

        // 근무 시작 → 새 열린 세션 생성 + status=working(이 시점엔 세션이 열려 있어 트리거 통과).
        store.start()
        await store.syncTask?.value
        // 시작 동기화가 실제 성공했는지 확인 — startWork 가 409 등으로 실패하면 항목이 pendingItems 에 잔류한다.
        #expect(store.pendingItems.isEmpty)

        // 배경 하트비트 루프(startedAt != nil 이면 계속 working 송신)를 멈춰, 부활 시도를 딱 한 번으로 격리한다.
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()

        let sessionID = try #require(store.currentSessionID)
        let openReady = await waitUntil {
            let rows = (try? await ctx.admin.sessionRows(userID: owner.userID, openOnly: true)) ?? []
            // Postgres uuid 는 소문자로 정규화되고 앱의 UUID().uuidString 은 대문자다 — 대소문자 무시 비교.
            return rows.contains { ($0["id"] as? String)?.lowercased() == sessionID.lowercased() }
        }
        if !openReady {
            // 실패 진단(개인정보/키 미출력: id 접두 8자 + 마감 여부만 남긴다).
            obs("s09c openReady 실패 — currentSessionID=\(String(sessionID.prefix(8)))…, pendingItems=\(store.pendingItems.count)")
            let recent = (try? await ctx.admin.sessionRows(userID: owner.userID, openOnly: false)) ?? []
            for row in recent.prefix(2) {
                let idHead = (row["id"] as? String).map { String($0.prefix(8)) } ?? "nil"
                let ended = row["ended_at"] is String ? "closed" : "open"
                obs("s09c 세션 디버그: id=\(idHead)… \(ended)")
            }
        }
        #expect(openReady)

        // admin 으로 그 세션을 강제 마감(ended_at 세팅) — 자동마감이 방치 세션을 닫은 상황을 재현한다.
        try await ctx.admin.closeOpenSessions(userID: owner.userID)
        #expect(try await ctx.admin.sessionRows(userID: owner.userID, openOnly: true).count == 0)

        // 좀비 부활 시도: 같은 계정 토큰으로 하트비트(status='working', active_session_id=닫힌 세션).
        // 열린 세션이 없으므로 before-trigger 가 off_work 로 강등해야 한다(하트비트 부활 좀비 차단).
        try await store.service.heartbeat(
            accessToken: accessToken, teamID: teamID, userID: owner.userID, sessionID: sessionID
        )

        // 트리거 검증: status 는 off_work 로 강등, active_session_id 는 null.
        let statusRows = try await ctx.admin.statusRows(userID: owner.userID)
        let statusRow = try #require(statusRows.first)
        #expect((statusRow["status"] as? String) == "off_work")
        #expect(statusRow["active_session_id"] is NSNull)
        // 부활은 세션을 되살리지 않는다 — 열린 세션은 여전히 없다.
        #expect(try await ctx.admin.sessionRows(userID: owner.userID, openOnly: true).count == 0)
        obs("좀비 부활 차단: 하트비트(working) → 트리거 강등 status=off_work, active_session_id=null")
    }

    // 9d. 팀원 목표 수정 + 참여코드 팀원 공개(20260722090000 마이그레이션 검증).
    // B(joiner, member)가 my_team_invite_code 로 참여코드를 조회(성공) → set_team_weekly_goal(37) 로 팀 목표를
    // 바꾼다 → SR 키 REST 로 teams.weekly_goal_hours==37 을 확인한다. member 역할도 코드 조회·목표 수정이 가능하다.
    // 이 시나리오는 마이그레이션 push 전이라 서버에 RPC 가 없다 — 작성만 하고 실행은 오케스트레이터가 push 후 담당한다.
    // E2E 접두사 스코프 밖 접근 금지, 키 원문 출력 금지.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09d_memberReadsInviteCodeAndUpdatesGoal() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        let teamID = try #require(LiveE2EState.e2eTeamID)

        // B(joiner) 가 팀 member 로 존재하도록 보장한다(있으면 로그인, 없으면 코드로 합류 가입 — 자가치유).
        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        if try await ctx.admin.findUserID(email: Emails.joiner) != nil {
            store.email = Emails.joiner
            store.password = Emails.password
            await store.signIn()?.value
        }
        if !store.isSignedIn || store.currentTeamID == nil {
            await signUpJoiningByCode(
                store: store,
                email: Emails.joiner,
                displayName: "E2E합류자",
                code: owner.code
            )
        }
        #expect(store.isSignedIn)
        #expect(store.currentTeamID == teamID)
        // B 는 member 다(owner 아님) — 그래도 아래에서 코드 조회·목표 수정이 가능해야 한다.
        #expect(!store.isTeamOwner)

        // B2: member 도 참여코드를 조회·노출한다(owner 전용 아님).
        #expect(store.myTeamInviteCode == owner.code)
        obs("팀원 참여코드 공개: member 코드 조회=\(store.myTeamInviteCode == owner.code)")

        // B3: member 가 주간 목표를 37시간으로 바꾼다.
        let changed = await store.updateTeamGoal(hours: 37)
        obs("팀원 목표 수정: updateTeamGoal(37)=\(changed), syncMessage=\(store.syncMessage)")
        #expect(changed)
        #expect(store.teamGoalSeconds == 37 * 3600)
        #expect(store.syncMessage == "주간 목표 변경됨")

        // SR 키 REST 로 서버 반영(teams.weekly_goal_hours==37)을 확인한다.
        let serverApplied = await waitUntil {
            (try? await ctx.admin.teamWeeklyGoalHours(id: teamID)) == 37
        }
        #expect(serverApplied)
        #expect(try await ctx.admin.teamWeeklyGoalHours(id: teamID) == 37)
        obs("서버 반영 확인: teams.weekly_goal_hours=37")

        // 정리: 다음 실행 결정성을 위해 목표를 E2E 기본값(42)으로 되돌린다(팀/계정 최종 삭제는 s10 담당).
        _ = await store.updateTeamGoal(hours: E2ETeam.goalHours)
    }

    // s09e. 이번 달 AI 토큰 보드 전체 공개(token_usage_board RPC): 각 계정이 token_usage_monthly 를 upsert 하면
    // 팀과 무관하게 모두 이번 달 순위를 조회할 수 있어야 한다 — 같은 팀 A/B 뿐 아니라 타팀 C 도 A/B 를 본다(전체 공개).
    // 자기 upsert 가 자기 조회에 반영되는지, 이름이 행에 담겨 오는지(이메일 비노출)도 확인한다.
    // 테이블 직접 select 는 RLS 로 잠겨 있고 조회는 RPC(security definer)로만 이뤄진다.
    // 이 시나리오는 마이그레이션(20260722130000_token_usage_monthly) push 전이라 서버에 RPC/테이블이 없다 —
    // 작성만 하고 실행(push 후)은 오케스트레이터가 담당한다. E2E 접두사 스코프 밖 접근 금지, 키 원문 출력 금지.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09e_tokenBoardGlobalPublic() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        let teamID = try #require(LiveE2EState.e2eTeamID)
        let month = TokenUsageMonthKey.current()

        // A(owner) 로그인.
        let storeA = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { storeA.tickerTask?.cancel(); storeA.refreshTask?.cancel() }
        storeA.email = Emails.owner
        storeA.password = Emails.password
        await storeA.signIn()?.value
        let sessionA = try #require(storeA.session)
        #expect(sessionA.userID == owner.userID)

        // B(joiner) 가 같은 팀 member 로 존재하도록 보장(있으면 로그인, 없으면 코드로 합류 — 자가치유).
        let storeB = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { storeB.tickerTask?.cancel(); storeB.refreshTask?.cancel() }
        if try await ctx.admin.findUserID(email: Emails.joiner) != nil {
            storeB.email = Emails.joiner
            storeB.password = Emails.password
            await storeB.signIn()?.value
        }
        if !storeB.isSignedIn || storeB.currentTeamID != teamID {
            await signUpJoiningByCode(store: storeB, email: Emails.joiner, displayName: "E2E합류자", code: owner.code)
        }
        let sessionB = try #require(storeB.session)
        #expect(storeB.currentTeamID == teamID)

        // C(nickname) 를 자기 소유의 다른 E2E 팀에 둔다(있으면 로그인, 없으면 새 팀 생성 — 자가치유). 타팀 조회 검증용.
        let storeC = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { storeC.tickerTask?.cancel(); storeC.refreshTask?.cancel() }
        if try await ctx.admin.findUserID(email: Emails.nickname) != nil {
            storeC.email = Emails.nickname
            storeC.password = Emails.password
            await storeC.signIn()?.value
        }
        if !storeC.isSignedIn || storeC.currentTeamID == nil {
            await signUpCreatingE2ETeam(store: storeC, email: Emails.nickname, displayName: "E2E타팀", teamName: E2ETeam.uniqueName())
        }
        let sessionC = try #require(storeC.session)

        // A, B, C 가 각자 이번 달 사용량을 upsert 한다(값은 서로 다르게 둬 조회로 구분한다).
        // 오늘분(todayTotal/todayDate)도 함께 올려 순위판 "오늘 +N" 왕복을 검증한다(마이그레이션 20260723060000 push 후).
        // 원장이 (user_id, month, device_id) 로 쪼개졌으므로(20260726010000) 기기별 잔여 행이 합산에 섞이지 않도록
        // 먼저 그 달 행을 비우고 각자 기기 하나로만 올린다 — 아래 총합 등호 비교를 결정적으로 만든다.
        let today = TokenUsageDayKey.current()
        let deviceE2E = "e2e-device-single"
        for userID in [sessionA.userID, sessionB.userID, sessionC.userID] {
            try await ctx.admin.deleteTokenUsageRows(userID: userID, month: month)
        }
        let usageA = TokenUsageMonthly(month: month, claudeInput: 1_111, claudeOutput: 2_222, todayTotal: 1_100, todayDate: today)
        let usageB = TokenUsageMonthly(month: month, claudeInput: 3_333, codexOutput: 4_444, todayTotal: 2_200, todayDate: today)
        let usageC = TokenUsageMonthly(month: month, claudeInput: 5_555, codexInput: 6_666, todayTotal: 3_300, todayDate: today)
        try await storeA.service.upsertTokenUsage(accessToken: sessionA.accessToken, userID: sessionA.userID, usage: usageA, deviceID: deviceE2E)
        try await storeB.service.upsertTokenUsage(accessToken: sessionB.accessToken, userID: sessionB.userID, usage: usageB, deviceID: deviceE2E)
        try await storeC.service.upsertTokenUsage(accessToken: sessionC.accessToken, userID: sessionC.userID, usage: usageC, deviceID: deviceE2E)

        // A 가 전체 보드를 조회하면 자기(반영)·같은 팀 B·타팀 C 가 모두 보여야 한다(전체 공개 RPC).
        let boardFromA = try await storeA.service.fetchTokenBoard(accessToken: sessionA.accessToken, month: month)
        #expect(boardFromA.contains { $0.userId == sessionA.userID && $0.total == usageA.total })  // 자기 upsert 반영
        #expect(boardFromA.contains { $0.userId == sessionB.userID && $0.total == usageB.total })  // 같은 팀
        // 오늘분 왕복: 업로드한 today_total/today_date 가 RPC 반환 행에 그대로 담겨 온다("오늘 +N" 원천).
        #expect(boardFromA.contains { $0.userId == sessionA.userID && $0.todayTotal == usageA.todayTotal && $0.todayDate == today })
        #expect(boardFromA.contains { $0.userId == sessionB.userID && $0.todayTotal == usageB.todayTotal })
        // 이름이 행에 담겨 오고(이메일이 아니라 표시 이름), 이메일이 새지 않는다.
        let selfRow = boardFromA.first { $0.userId == sessionA.userID }
        #expect(selfRow?.displayName.isEmpty == false)
        #expect(selfRow?.displayName.contains("@") == false)
        obs("토큰 보드 전체 공개: A 가 본 행 수=\(boardFromA.count)")

        // 타팀이어야 의미 있는 교차 조회 검증이다 — C 가 어쩌다 T1 에 있으면(방어) 그 부분은 건너뛴다.
        if storeC.currentTeamID != teamID {
            #expect(boardFromA.contains { $0.userId == sessionC.userID && $0.total == usageC.total })  // 타팀도 보인다

            // C(타팀) 도 A/B 를 조회할 수 있어야 한다(예전 RLS 팀 차단과 정반대 — 전체 공개).
            let boardFromC = try await storeC.service.fetchTokenBoard(accessToken: sessionC.accessToken, month: month)
            #expect(boardFromC.contains { $0.userId == sessionA.userID })
            #expect(boardFromC.contains { $0.userId == sessionB.userID })
            #expect(boardFromC.contains { $0.userId == sessionC.userID && $0.total == usageC.total })  // 자기 upsert 반영
            obs("토큰 보드 타팀 조회 허용: C 가 본 행 수=\(boardFromC.count)(A·B·C 포함이어야 함)")
        } else {
            obs("s09e: C 가 우연히 같은 팀 — 타팀 교차 조회 검증 건너뜀")
        }
    }

    // s09f. 콕찌르기 왕복 + 대상 게이트: 나도 대상도 근무중이어야 찌를 수 있다.
    //  (a) owner·joiner 모두 근무중 → owner→joiner ok, 즉시 재찌르기 = 쿨타임(cooldown+retry_after),
    //      joiner 가 take_pokes 로 원자 수신+소비(표시명 포함), 재호출 시 빈 배열.
    //  (b) joiner 근무종료 후 owner→joiner = target_not_working(쿨타임 60초가 안 지났어도 대상 체크가 먼저라 결정적).
    //  (c) owner 근무종료 후 owner→joiner = not_working(보낸이 체크가 대상 체크보다 먼저).
    // 마이그레이션(20260724030000_poke_target_working) push 후 오케스트레이터가 실행한다. 열린 세션 잔존 금지.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09f_pokeRoundTrip() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        let teamID = try #require(LiveE2EState.e2eTeamID)

        // A(owner) 로그인.
        let storeA = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { storeA.tickerTask?.cancel(); storeA.refreshTask?.cancel() }
        storeA.email = Emails.owner
        storeA.password = Emails.password
        await storeA.signIn()?.value
        let sessionA = try #require(storeA.session)
        #expect(sessionA.userID == owner.userID)

        // B(joiner) 가 같은 팀 member 로 존재하도록 보장(있으면 로그인, 없으면 코드로 합류 — 자가치유).
        let storeB = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { storeB.tickerTask?.cancel(); storeB.refreshTask?.cancel() }
        if try await ctx.admin.findUserID(email: Emails.joiner) != nil {
            storeB.email = Emails.joiner
            storeB.password = Emails.password
            await storeB.signIn()?.value
        }
        if !storeB.isSignedIn || storeB.currentTeamID != teamID {
            await signUpJoiningByCode(store: storeB, email: Emails.joiner, displayName: "E2E합류자", code: owner.code)
        }
        let sessionB = try #require(storeB.session)
        #expect(storeB.currentTeamID == teamID)

        // owner·joiner 모두 근무중으로(열린 세션) — 새 정책상 양쪽 모두 게이트 통과 조건.
        if storeA.startedAt == nil {
            storeA.start()
            await storeA.syncTask?.value
        }
        #expect(storeA.startedAt != nil)
        if storeB.startedAt == nil {
            storeB.start()
            await storeB.syncTask?.value
        }
        #expect(storeB.startedAt != nil)

        // 남은 미소비 찔림이 다음 검증을 흔들지 않게 B 의 수신함을 먼저 비운다(멱등).
        _ = try await storeB.service.takePokes(accessToken: sessionB.accessToken)

        // (a-1) owner → joiner 찌르기 = ok(둘 다 근무중).
        let first = try await storeA.service.sendPoke(accessToken: sessionA.accessToken, to: sessionB.userID)
        #expect(first.status == "ok")
        obs("콕찌르기: owner→joiner 첫 시도 status=\(first.status)")

        // (a-2) 즉시 재찌르기 = 서버 쿨타임(cooldown + retry_after 1...60).
        let second = try await storeA.service.sendPoke(accessToken: sessionA.accessToken, to: sessionB.userID)
        #expect(second.status == "cooldown")
        let retry = try #require(second.retryAfterSeconds)
        #expect(retry >= 1 && retry <= 60)
        obs("콕찌르기: 즉시 재시도 status=\(second.status), retry_after=\(retry)")

        // (a-3) joiner 가 take_pokes 로 owner 찔림을 원자 수신+소비한다(보낸이 표시명 포함).
        let taken = try await storeB.service.takePokes(accessToken: sessionB.accessToken)
        #expect(taken.contains { $0.fromUser == sessionA.userID })
        let ownerPoke = taken.first { $0.fromUser == sessionA.userID }
        #expect(ownerPoke?.fromDisplayName.isEmpty == false)
        #expect(ownerPoke?.fromDisplayName.contains("@") == false)  // 이메일 비노출.
        obs("콕찌르기 수신: joiner 가 받은 행 수=\(taken.count)")

        // (a-4) 재호출 시 빈 배열(이미 소비됨).
        let takenAgain = try await storeB.service.takePokes(accessToken: sessionB.accessToken)
        #expect(takenAgain.contains { $0.fromUser == sessionA.userID } == false)

        // (b) joiner 근무종료 → owner→joiner = target_not_working. owner 는 여전히 근무중이고
        //     (a) 로 60초 쿨타임이 남아 있지만, 서버가 대상 체크를 쿨타임보다 먼저 하므로 결정적으로 target_not_working 이다.
        storeB.stop()
        await storeB.syncTask?.value
        let joinerClosed = await waitUntil {
            (try? await ctx.admin.sessionRows(userID: sessionB.userID, openOnly: true))?.isEmpty == true
        }
        #expect(joinerClosed)
        let afterTargetStop = try await storeA.service.sendPoke(accessToken: sessionA.accessToken, to: sessionB.userID)
        #expect(afterTargetStop.status == "target_not_working")
        obs("콕찌르기: 대상(joiner) 근무종료 후 status=\(afterTargetStop.status)")

        // (c) owner 근무종료 → 보낸이 체크가 대상 체크보다 먼저라 not_working(대상도 자리비움이지만 보낸이 게이트가 우선).
        storeA.stop()
        await storeA.syncTask?.value
        let ownerClosed = await waitUntil {
            (try? await ctx.admin.sessionRows(userID: owner.userID, openOnly: true))?.isEmpty == true
        }
        #expect(ownerClosed)
        let afterSenderStop = try await storeA.service.sendPoke(accessToken: sessionA.accessToken, to: sessionB.userID)
        #expect(afterSenderStop.status == "not_working")
        obs("콕찌르기: 보낸이(owner) 근무종료 후 status=\(afterSenderStop.status)")

        // 세션 정리 철저 — 열린 세션 잔존 금지(다음 시나리오/재실행 오염 방지, 멱등).
        try await ctx.admin.closeOpenSessions(userID: owner.userID)
        try await ctx.admin.closeOpenSessions(userID: sessionB.userID)
    }


    // s09g. 토큰 사용량 공개/비공개: joiner 가 비공개로 두면 owner 보드에서 사라지되(타인 숨김) 자기 보드에는 남고,
    // 다시 공개로 되돌리면 owner 보드에 재등장한다. 마이그레이션(20260724010000_token_usage_privacy) push 후 실행한다.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09g_tokenPrivacyBoard() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        let teamID = try #require(LiveE2EState.e2eTeamID)
        let month = TokenUsageMonthKey.current()

        // A(owner) 로그인.
        let storeA = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { storeA.tickerTask?.cancel(); storeA.refreshTask?.cancel() }
        storeA.email = Emails.owner
        storeA.password = Emails.password
        await storeA.signIn()?.value
        let sessionA = try #require(storeA.session)
        #expect(sessionA.userID == owner.userID)

        // B(joiner) 가 같은 팀 member 로 존재하도록 보장.
        let storeB = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { storeB.tickerTask?.cancel(); storeB.refreshTask?.cancel() }
        if try await ctx.admin.findUserID(email: Emails.joiner) != nil {
            storeB.email = Emails.joiner
            storeB.password = Emails.password
            await storeB.signIn()?.value
        }
        if !storeB.isSignedIn || storeB.currentTeamID != teamID {
            await signUpJoiningByCode(store: storeB, email: Emails.joiner, displayName: "E2E합류자", code: owner.code)
        }
        let sessionB = try #require(storeB.session)

        // joiner 가 이번 달 사용량을 올려 보드에 뜰 조건을 만든다(원장 기기 분리 후이므로 그 달 행을 비우고 기기 하나로).
        try await ctx.admin.deleteTokenUsageRows(userID: sessionB.userID, month: month)
        let usageB = TokenUsageMonthly(month: month, claudeInput: 7_777, codexOutput: 8_888)
        try await storeB.service.upsertTokenUsage(accessToken: sessionB.accessToken, userID: sessionB.userID, usage: usageB, deviceID: "e2e-device-single")

        // 기본 공개 상태를 보장(이전 실행 잔류 대비) — 시작점을 true 로 맞춘다.
        try await storeB.service.updateTokenUsagePublic(accessToken: sessionB.accessToken, userID: sessionB.userID, isPublic: true)
        let boardPublic = try await storeA.service.fetchTokenBoard(accessToken: sessionA.accessToken, month: month)
        #expect(boardPublic.contains { $0.userId == sessionB.userID })  // 공개면 owner 보드에 보인다.

        // 비공개로 전환 → owner 보드에서 사라진다(타인 숨김). joiner 자기 보드에는 남는다(auth.uid() 유지).
        try await storeB.service.updateTokenUsagePublic(accessToken: sessionB.accessToken, userID: sessionB.userID, isPublic: false)
        let boardHidden = try await storeA.service.fetchTokenBoard(accessToken: sessionA.accessToken, month: month)
        #expect(boardHidden.contains { $0.userId == sessionB.userID } == false)  // owner 에겐 숨김.
        let selfBoard = try await storeB.service.fetchTokenBoard(accessToken: sessionB.accessToken, month: month)
        #expect(selfBoard.contains { $0.userId == sessionB.userID })  // 본인에겐 보인다.
        obs("토큰 비공개: owner 보드 숨김=\(boardHidden.contains { $0.userId == sessionB.userID } == false), 본인 보드 유지=\(selfBoard.contains { $0.userId == sessionB.userID })")

        // 다시 공개로 되돌리면 owner 보드에 재등장.
        try await storeB.service.updateTokenUsagePublic(accessToken: sessionB.accessToken, userID: sessionB.userID, isPublic: true)
        let boardRestored = try await storeA.service.fetchTokenBoard(accessToken: sessionA.accessToken, month: month)
        #expect(boardRestored.contains { $0.userId == sessionB.userID })  // 공개 복원 → 다시 보인다.
    }

    // s09h. 맥 2대 합산(결함1 회귀 방지): 같은 계정이 device_id 만 다른 두 행을 올리면 원장에 행이 둘로 남고,
    // token_usage_board 는 user_id 로 묶어 **합산값** 한 행을 돌려줘야 한다.
    // 예전 (user_id, month) 키에서는 두 번째 upsert 가 첫 번째를 통째로 덮어써 총량이 "마지막 기기 값"이었다 —
    // 이 시나리오가 실패하면 그 회귀가 돌아온 것이다. today 도 서버가 KST 오늘을 계산해 그 날짜인 행만 합산한다:
    // 기기1은 오늘분, 기기2는 어제 날짜로 올려 "오늘 것만" 더해지는지 함께 못 박는다.
    // 마이그레이션(20260726010000_token_usage_device) push 후 오케스트레이터가 실행한다.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09h_tokenBoardSumsDevices() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        let month = TokenUsageMonthKey.current()
        let today = TokenUsageDayKey.current()

        // A(owner) 로그인.
        let storeA = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { storeA.tickerTask?.cancel(); storeA.refreshTask?.cancel() }
        storeA.email = Emails.owner
        storeA.password = Emails.password
        await storeA.signIn()?.value
        let sessionA = try #require(storeA.session)
        #expect(sessionA.userID == owner.userID)

        // 이전 실행 잔여 행(다른 device_id·'legacy')이 합산에 섞이지 않게 그 달 원장을 비운다.
        try await ctx.admin.deleteTokenUsageRows(userID: sessionA.userID, month: month)

        // 같은 계정 · 같은 달 · 다른 기기 두 행. 오늘분은 기기1만 오늘 날짜로, 기기2는 어제 날짜로 둔다.
        let yesterday = TokenUsageDayKey.current(Date().addingTimeInterval(-24 * 3600))
        let usageMac1 = TokenUsageMonthly(month: month, claudeInput: 1_000, claudeOutput: 2_000, todayTotal: 300, todayDate: today)
        let usageMac2 = TokenUsageMonthly(month: month, claudeInput: 4_000, codexOutput: 8_000, todayTotal: 999, todayDate: yesterday)
        try await storeA.service.upsertTokenUsage(accessToken: sessionA.accessToken, userID: sessionA.userID, usage: usageMac1, deviceID: "e2e-mac-1")
        try await storeA.service.upsertTokenUsage(accessToken: sessionA.accessToken, userID: sessionA.userID, usage: usageMac2, deviceID: "e2e-mac-2")

        // 원장은 기기별로 두 행(덮어쓰기 아님).
        #expect(try await ctx.admin.tokenUsageRowCount(userID: sessionA.userID, month: month) == 2)

        // 보드는 user_id 로 묶여 한 행 + 합산값.
        let board = try await storeA.service.fetchTokenBoard(accessToken: sessionA.accessToken, month: month)
        let myRows = board.filter { $0.userId == sessionA.userID }
        #expect(myRows.count == 1)
        let row = try #require(myRows.first)
        #expect(row.total == usageMac1.total + usageMac2.total)          // 15,000 — 마지막 기기 값(12,000)이 아니다.
        #expect(row.claudeInput == 5_000)                                 // 1,000 + 4,000
        #expect(row.claudeOutput == 2_000)
        #expect(row.codexOutput == 8_000)
        // 오늘분은 서버가 계산한 KST 오늘 날짜인 행만 합산한다(어제 날짜 기기2의 999 는 제외).
        #expect(row.todayTotal == 300)
        #expect(row.todayDate == today)
        obs("토큰 기기 합산: 원장 2행 → 보드 1행 total=\(row.total)(기대 \(usageMac1.total + usageMac2.total)), todayTotal=\(row.todayTotal)")

        // 과도기(맥 A=v0.2.10 옛 표에만, 맥 B=v0.2.11 새 표에만): 옛 표 값이 훨씬 크면 그 값이 보드에 남아야 한다.
        // 회귀 지점: "기기 행이 하나라도 있으면 옛 표를 통째로 버린다"는 초안이면, 보조 맥이 한 번 올리는 순간
        // 주력 맥(아직 v0.2.10)의 사용량이 순위에서 영구 누락돼 total 이 15,000 에 고정된다.
        let legacyTotal = 900_000
        try await ctx.admin.upsertLegacyTokenUsage(
            userID: sessionA.userID, month: month, total: legacyTotal, todayTotal: 4_321, todayDate: today
        )
        let mixedBoard = try await storeA.service.fetchTokenBoard(accessToken: sessionA.accessToken, month: month)
        let mixedRows = mixedBoard.filter { $0.userId == sessionA.userID }
        #expect(mixedRows.count == 1)                      // 두 출처를 더해 행이 둘로 늘어나지 않는다.
        let mixedRow = try #require(mixedRows.first)
        #expect(mixedRow.total == legacyTotal)             // 15,000 이 아니라 옛 표의 900,000(큰 쪽).
        #expect(mixedRow.todayTotal == 4_321)              // today 도 채택된 쪽 값으로 일관되게 온다.
        obs("토큰 과도기(옛 표 우세): total=\(mixedRow.total)(기대 \(legacyTotal), 기기합=\(row.total))")

        // 결함1 의 핵심 재현 경로: v0.2.11 맥에서 팝오버를 열면 도는 **클라 업로드 전체 경로**를 실제로 태운다.
        // 예전엔 이 경로가 옛 표를 무조건 자기 값으로 덮어써(merge-duplicates), 주력 맥(아직 v0.2.10)의 900,000 이
        // 사라지고 보드가 이 맥의 값으로 떨어졌다 — 팝오버를 마지막에 연 맥의 값으로 널뛰던 그 증상이다.
        let popoverUsage = TokenUsageMonthly(month: month, claudeInput: 2_000, todayTotal: 11, todayDate: today)
        await storeA.uploadTokenUsageIfNeeded(usage: popoverUsage, now: Date())
        #expect(try await ctx.admin.legacyTokenUsageTotal(userID: sessionA.userID, month: month) == legacyTotal)
        let afterUploadBoard = try await storeA.service.fetchTokenBoard(accessToken: sessionA.accessToken, month: month)
        let afterUploadRow = try #require(afterUploadBoard.first { $0.userId == sessionA.userID })
        #expect(afterUploadRow.total == legacyTotal)       // 여전히 900,000 — 보조 맥 업로드가 주력 맥을 지우지 않는다.
        obs("토큰 과도기(v0.2.11 업로드 후): 옛 표=\(String(describing: try await ctx.admin.legacyTokenUsageTotal(userID: sessionA.userID, month: month))), 보드 total=\(afterUploadRow.total)")

        // 두 맥 모두 v0.2.11 이 되면 옛 행은 얼어붙고 기기 합산이 계속 자라 자동으로 합산이 이긴다(이중 계상 없음).
        let usageMac1Grown = TokenUsageMonthly(month: month, claudeInput: 1_000_000, claudeOutput: 2_000, todayTotal: 300, todayDate: today)
        try await storeA.service.upsertTokenUsage(accessToken: sessionA.accessToken, userID: sessionA.userID, usage: usageMac1Grown, deviceID: "e2e-mac-1")
        let grownBoard = try await storeA.service.fetchTokenBoard(accessToken: sessionA.accessToken, month: month)
        let grownRow = try #require(grownBoard.first { $0.userId == sessionA.userID })
        // 기기 합산 = mac1(성장) + mac2 + 위 업로드가 만든 이 맥의 행. 옛 900,000 을 더하지 않는다.
        #expect(grownRow.total == usageMac1Grown.total + usageMac2.total + popoverUsage.total)
        obs("토큰 과도기 졸업(기기 합산 우세): total=\(grownRow.total)(기대 \(usageMac1Grown.total + usageMac2.total + popoverUsage.total))")

        // 화석 무시(v0.2.9 이하 과다계상 정정 경로): 옛 행이 **기기 행보다 먼저** 만들어져 그 뒤로 갱신되지 않으면
        // 아무도 쓰지 않는 잔재이므로 보드가 무시한다. 클라는 그 행을 덮어쓰지 않으니(위 게이트) 서버가 갈라 준다.
        // 단 판정에는 **7일 유예**가 걸려 있다(업그레이드 직후에는 아직 v0.2.10 인 주력 맥의 옛 행도 똑같이
        // '갱신 끊김'으로 보이기 때문 — 유예가 없으면 그 맥의 200M 이 보조 맥 첫 업로드에 폭락한다).
        // 그래서 같은 픽스처를 두 국면으로 나눠 못 박는다: (a) 유예 중에는 옛 행이 살아 있고,
        // (b) 유예가 지나면 화석이 무시된다. 두 단언 사이의 유일한 차이는 **시각**뿐이다.
        //
        // 회귀 지점: 예전 이 블록은 (a) 의 상태(첫 기기 행이 '방금')에서 곧바로 (b) 의 값을 기대했다.
        // E2E 계정은 s10 정리로 매 실행 새로 만들어져 first_at 이 언제나 '방금'이라 유예가 항상 살아 있고,
        // 단언은 구조적으로 통과 불가능했다(PostgreSQL 15 실측: 기대 7,000, 실제 5,000,000) —
        // 마이그레이션 push 직후 이 릴리스 게이트가 100% 실패했다.
        try await ctx.admin.deleteTokenUsageRows(userID: sessionA.userID, month: month)
        let fossilTotal = 5_000_000
        try await ctx.admin.upsertLegacyTokenUsage(
            userID: sessionA.userID, month: month, total: fossilTotal, todayTotal: 0, todayDate: today
        )
        let correctedUsage = TokenUsageMonthly(month: month, claudeInput: 7_000, todayTotal: 3, todayDate: today)
        storeA.lastUploadedUsage = nil
        storeA.lastTokenUploadAt = .distantPast
        await storeA.uploadTokenUsageIfNeeded(usage: correctedUsage, now: Date())

        // (a) 유예(첫 기기 행 이후 7일) 안: 옛 행을 살려 둔다 — 아직 v0.2.10 인 주력 맥의 값일 수 있기 때문이다.
        let graceBoard = try await storeA.service.fetchTokenBoard(accessToken: sessionA.accessToken, month: month)
        let graceRow = try #require(graceBoard.first { $0.userId == sessionA.userID })
        #expect(graceRow.total == fossilTotal)             // 유예 중에는 큰 쪽(옛 행)이 그대로 남는다.
        obs("토큰 화석 유예 중: total=\(graceRow.total)(기대 \(fossilTotal), 기기 \(correctedUsage.total))")

        // (b) 유예 만료: 시계를 감을 수 없으니 픽스처의 시각을 뒤로 민다.
        //     첫 기기 행 8일 전 + 옛 행 마지막 쓰기 9일 전 = "업그레이드 뒤 아무도 옛 행을 갱신하지 않았다".
        //     (옛 표 touch 트리거는 명시적 과거 시각만 보존한다 — 앱은 이 컬럼을 보내지 않아 실사용과 무관하다.
        //      이 예외가 없으면 옛 행을 심는 순간 updated_at 이 now() 가 되어 화석을 재현할 방법이 아예 없다.)
        let now = Date()
        try await ctx.admin.backdateDeviceTokenUsage(
            userID: sessionA.userID, createdAt: now.addingTimeInterval(-8 * 24 * 3600)
        )
        try await ctx.admin.backdateLegacyTokenUsage(
            userID: sessionA.userID, updatedAt: now.addingTimeInterval(-9 * 24 * 3600)
        )
        // 백데이트가 트리거에 덮이지 않고 남았는지 먼저 확인한다(아래 단언의 전제).
        #expect(try await ctx.admin.legacyTokenUsageOlder(
            userID: sessionA.userID, month: month, than: now.addingTimeInterval(-8.5 * 24 * 3600)
        ))
        let fossilBoard = try await storeA.service.fetchTokenBoard(accessToken: sessionA.accessToken, month: month)
        let fossilRow = try #require(fossilBoard.first { $0.userId == sessionA.userID })
        #expect(fossilRow.total == correctedUsage.total)   // 5,000,000 이 아니라 정정된 기기 값.
        #expect(fossilRow.todayTotal == correctedUsage.todayTotal)
        obs("토큰 화석 무시(유예 만료): total=\(fossilRow.total)(기대 \(correctedUsage.total), 화석 \(fossilTotal))")

        // (c) 아직 v0.2.10 인 맥이 다시 올리면(= 옛 행 갱신) 화석 판정이 풀려 그 값이 즉시 되살아난다.
        //     트리거가 실사용 쓰기를 여전히 now() 로 스탬프한다는 것 — 위 예외가 판정을 무력화하지 않았다는 증거다.
        try await ctx.admin.upsertLegacyTokenUsage(
            userID: sessionA.userID, month: month, total: fossilTotal, todayTotal: 0, todayDate: today
        )
        let revivedBoard = try await storeA.service.fetchTokenBoard(accessToken: sessionA.accessToken, month: month)
        let revivedRow = try #require(revivedBoard.first { $0.userId == sessionA.userID })
        #expect(revivedRow.total == fossilTotal)
        obs("토큰 화석 판정 복구(구버전 맥 재업로드): total=\(revivedRow.total)(기대 \(fossilTotal))")

        // 정리: 다음 시나리오/재실행이 이 합산 픽스처에 오염되지 않게 그 달 행을 비운다(멱등).
        try await ctx.admin.deleteTokenUsageRows(userID: sessionA.userID, month: month)
    }

    // 9i. 앱이 쓰는 **모든 PostgREST 임베드 조회**가 실서버에서 실제로 해석되는지.
    //
    // 이 테스트가 없어서 v0.2.15 배포 당일 팀 기능이 전원 다운됐다(2026-08-02).
    // 마이그레이션 20260801010000 이 work_status_devices 에 work_statuses·profiles 양쪽 FK 를 달았고,
    // PostgREST 가 그 표를 **다대다 연결 표로 자동 해석**해 work_statuses→profiles 임베드에 경로가 둘이 됐다.
    // 결과는 PGRST201 로 **팀 현황 GET 전체가 400** — 서버만의 변경이라 구버전 앱 사용자까지 함께 죽었다.
    //
    // 왜 기존 테스트가 전부 초록이었나(이 테스트의 존재 이유):
    //   1) URLProtocolStub 은 보낸 select 를 해석하지 않고 준비된 JSON 을 돌려준다 —
    //      PostgREST 의 관계 해석은 **실서버에서만** 일어나므로 단위 테스트로는 원리적으로 못 잡는다.
    //   2) 스토어 경로(refreshTeamStatus)는 실패를 syncMessage 로 삼킨다 —
    //      스토어를 구동하는 e2e 가 있어도 조용히 지나간다.
    //   그래서 **service 를 직접 불러 throw 여부로** 판정한다. 삼키는 층을 건너뛰는 것이 핵심이다.
    //
    // 교훈: 표를 **더하기만 해도** 기존 조회가 깨질 수 있다. "순수 추가라 안전"은 PostgREST 에서 거짓이다.
    // 마이그레이션을 push 한 뒤에는 앱을 배포하기 전에 반드시 이 시나리오를 돌린다(docs/release.md).
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09i_postgrestEmbedsStayUnambiguous() async throws {
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
        let session = try #require(store.session)
        let teamID = try #require(store.currentTeamID)

        // (1) work_statuses?select=…,profiles(…) — 이번에 깨졌던 바로 그 조회.
        //     throw 하지 않는 것 자체가 단언이다(PGRST201 이면 여기서 실패한다).
        let members = try await store.service.fetchTeamStatuses(
            accessToken: session.accessToken,
            teamID: teamID
        )
        // 임베드가 실제로 **해석돼 값이 실려 왔는지**까지 본다. 400 이 아니어도 관계가 끊기면
        // 이름이 통째로 폴백('팀원')이 되어 화면이 조용히 망가진다.
        let me = try #require(members.first { $0.id == session.userID })
        #expect(me.name != "팀원")
        #expect(!me.name.isEmpty)
        obs("임베드 해석 확인: work_statuses→profiles, 팀원 \(members.count)명, 내 표시명='\(me.name)'")

        // (2) memberships?select=team_id,role,teams(…) — 팀 이름/목표를 가져오는 다른 임베드.
        //     confirmMembership 이 이 조회를 쓰며, 실패하면 소속팀이 사라진 것처럼 보인다.
        let membership = try await store.service.fetchOwnMembership(
            accessToken: session.accessToken,
            userID: session.userID
        )
        let confirmed = try #require(membership)
        #expect(confirmed.teamID == teamID)
        // 임베드가 끊기면 teams(...) 가 비어 teamName 이 폴백('팀')으로 조용히 내려앉는다 — 값까지 본다.
        #expect(confirmed.teamName != "팀")
        #expect(confirmed.goalHours > 0)
        obs("임베드 해석 확인: memberships→teams, 팀='\(confirmed.teamName)' 목표=\(confirmed.goalHours)h")

        // (3) 새 표의 조회가 기존 조회를 죽이지 않는지 — 별도 GET 이라 임베드는 아니지만,
        //     이 표의 존재 자체가 (1)을 깨뜨린 전력이 있으므로 같은 시나리오에서 함께 확인한다.
        _ = owner
        #expect(members.allSatisfy { $0.weeklyDurationSeconds >= 0 })
    }

    // s09k. 울트라 찌르기 왕복 + 하루 한도(보낸이 기준, 대상 무관) + 게이트 순서.
    // 서버가 지키는 계약 넷을 실서버에서 한 번에 못 박는다:
    //  (a) 울트라가 kind='ultra' 로 저장되고 take_pokes 가 그 종류를 실어 온다(구버전은 이 키를 무시한다).
    //  (b) 하루 한도는 **보낸 사람 기준**이다 — 대상을 바꿔도 같은 몫을 깎고, 다 쓰면 어느 대상에게도 못 보낸다.
    //  (c) 남은 횟수(ultra_remaining)가 한도→…→0 으로 정확히 줄고, **실패는 몫을 태우지 않는다**(pokes 행 수 불변).
    //  (d) 게이트 순서가 invalid → 보낸이근무 → 대상근무 → 하루한도 → 쿨타임 이다.
    //      대상 근무종료 뒤 결과가 ultra_used_today 가 **아니라** target_not_working 이라는 사실이
    //      '대상근무 > 하루한도' 를 결정적으로 증명한다(A 는 이미 오늘 몫을 다 썼는데도).
    // 마이그레이션 20260804030000 push 후 실행한다. 열린 세션 잔존 금지.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09k_ultraPokeRoundTrip() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        let teamID = try #require(LiveE2EState.e2eTeamID)

        // A(owner) 로그인.
        let storeA = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { storeA.tickerTask?.cancel(); storeA.refreshTask?.cancel() }
        storeA.email = Emails.owner
        storeA.password = Emails.password
        await storeA.signIn()?.value
        let sessionA = try #require(storeA.session)
        #expect(sessionA.userID == owner.userID)

        // B(joiner) 가 같은 팀 member 로 존재하도록 보장(있으면 로그인, 없으면 코드로 합류 — 자가치유).
        let storeB = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { storeB.tickerTask?.cancel(); storeB.refreshTask?.cancel() }
        if try await ctx.admin.findUserID(email: Emails.joiner) != nil {
            storeB.email = Emails.joiner
            storeB.password = Emails.password
            await storeB.signIn()?.value
        }
        if !storeB.isSignedIn || storeB.currentTeamID != teamID {
            await signUpJoiningByCode(store: storeB, email: Emails.joiner, displayName: E2ENames.joinerBase, code: owner.code)
        }
        let sessionB = try #require(storeB.session)
        #expect(storeB.currentTeamID == teamID)

        // C(nickname) — **두 번째 울트라를 다른 대상에게** 보내기 위한 계정. s09e 가 쓰는 계정을 그대로
        // 재사용한다(있으면 로그인, 없으면 자기 팀 만들며 가입 — 자가치유). 팀이 달라도 울트라는 나간다.
        let storeC = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { storeC.tickerTask?.cancel(); storeC.refreshTask?.cancel() }
        if try await ctx.admin.findUserID(email: Emails.nickname) != nil {
            storeC.email = Emails.nickname
            storeC.password = Emails.password
            await storeC.signIn()?.value
        }
        if !storeC.isSignedIn || storeC.currentTeamID == nil {
            await signUpCreatingE2ETeam(store: storeC, email: Emails.nickname, displayName: "E2E타팀", teamName: E2ETeam.uniqueName())
        }

        // 진입 정리 — **이 두 줄이 없으면 스위트가 두 번째 실행부터 영구히 빨개진다.**
        // 하루 한도 장부가 pokes 행 자체라 지난 실행의 울트라가 그대로 오늘 몫으로 남고,
        // 60초 쿨타임도 직전 s09f 의 일반 찌르기가 그대로 물고 있다. 종류 무관 전부 지워 둘 다 리셋한다.
        try await ctx.admin.deleteAllPokes(fromUser: sessionA.userID)
        #expect(try await ctx.admin.ultraPokeCount(fromUser: sessionA.userID) == 0)

        // A·B 근무중(양쪽 게이트 통과 조건).
        if storeA.startedAt == nil { storeA.start(); await storeA.syncTask?.value }
        #expect(storeA.startedAt != nil)
        if storeB.startedAt == nil { storeB.start(); await storeB.syncTask?.value }
        #expect(storeB.startedAt != nil)

        // C 도 근무중으로 세워 둔다. 못 세우면(계정/팀 문제) 교차 대상 실증만 건너뛴다.
        var thirdTargetID: String?
        if let sessionC = storeC.session, storeC.currentTeamID != nil {
            if storeC.startedAt == nil { storeC.start(); await storeC.syncTask?.value }
            if storeC.startedAt != nil { thirdTargetID = sessionC.userID }
        }

        // B 의 수신함을 먼저 비운다(앞 시나리오가 남긴 미소비 찔림이 kind 단언을 흔들지 않게, 멱등).
        _ = try await storeB.service.takePokes(accessToken: sessionB.accessToken)

        // v0.2.34: 클라의 하루 한도 상수는 사라졌다(재화 경제로 전환 — 잔량은 서버가 정한다).
        // 이 프로브가 도는 계정의 app_build 가 43 미만이면 서버 밑바닥은 2 다(구버전 유예,
        // docs/ultra-economy.md §1). 실서버 프로브라 그 값을 클라 상수에서 파생시킬 수는 없다.
        let limit = 2

        // (a-1) A→B 울트라 = ok. 남은 횟수가 한도-1 이라는 사실이 **서버가 2회 한도로 돌고 있다**의 증거다.
        let first = try await storeA.service.sendUltraPoke(accessToken: sessionA.accessToken, to: sessionB.userID)
        #expect(first.status == "ok")
        #expect(first.ultraRemaining == limit - 1)
        obs("울트라 1발: status=\(first.status), 남은=\(first.ultraRemaining.map(String.init) ?? "nil")")

        // (a-2) B 가 take_pokes 로 원자 수신+소비 — **kind 가 실려 온다**(6열로 늘어난 RETURNS TABLE 실증).
        let taken = try await storeB.service.takePokes(accessToken: sessionB.accessToken)
        let ultraRow = try #require(taken.first { $0.fromUser == sessionA.userID })
        #expect(ultraRow.kind == "ultra")
        #expect(ultraRow.fromDisplayName.isEmpty == false)
        #expect(ultraRow.fromDisplayName.contains("@") == false)  // 이메일 비노출.
        obs("울트라 수신: kind=\(ultraRow.kind ?? "nil"), 보낸이='\(ultraRow.fromDisplayName)'")

        // (a-3) 재호출 시 빈 배열(원자 소비 불변 — kind 가 늘어도 소비 규약은 그대로다).
        let takenAgain = try await storeB.service.takePokes(accessToken: sessionB.accessToken)
        #expect(takenAgain.contains { $0.fromUser == sessionA.userID } == false)

        // 두 번째 울트라의 대상. 원칙은 **다른 대상(C)** 이다 — 대상이 달라도 같은 몫이 깎인다는
        // '보낸이 기준' 계약을 실증하는 유일한 지점이기 때문이다.
        let secondTarget: String
        if let thirdTargetID {
            secondTarget = thirdTargetID
        } else {
            obs("s09k: 세 번째 계정(C)을 근무중으로 못 세워 '대상 무관' 교차 실증을 건너뜀 — 한도 자체만 검증한다")
            // 같은 대상이면 60초 쿨타임이 먼저 걸린다. 행을 지우면 하루 한도까지 리셋되므로,
            // created_at 만 61초 전으로 밀어 쿨타임만 만료시킨다(오늘 몫 1회 소모 상태는 유지).
            try await ctx.admin.backdatePokes(fromUser: sessionA.userID, createdAt: Date().addingTimeInterval(-61))
            secondTarget = sessionB.userID
        }

        // (b-1) 두 번째 울트라 = ok, 남은 0. 여기까지가 "하루 2회"다.
        let second = try await storeA.service.sendUltraPoke(accessToken: sessionA.accessToken, to: secondTarget)
        #expect(second.status == "ok")
        #expect(second.ultraRemaining == 0)
        #expect(try await ctx.admin.ultraPokeCount(fromUser: sessionA.userID) == limit)
        obs("울트라 2발: status=\(second.status), 남은=\(second.ultraRemaining.map(String.init) ?? "nil"), 장부=\(limit)행")

        // (b-2) 세 번째 시도 = ultra_used_today. 같은 대상이라 60초 쿨타임도 걸려 있지만
        //       **하루한도가 쿨타임보다 앞**이라 cooldown 이 아니라 ultra_used_today 가 나온다(순서 실증).
        let third = try await storeA.service.sendUltraPoke(accessToken: sessionA.accessToken, to: secondTarget)
        #expect(third.status == "ultra_used_today")
        #expect(third.ultraRemaining == 0)
        let reset = try #require(third.resetAfterSeconds)
        #expect(reset >= 1 && reset <= 86_400)
        obs("울트라 소진: status=\(third.status), reset_after=\(reset)초")

        // (b-3) 대상을 B 로 바꿔도 여전히 ultra_used_today — 한도는 대상별이 아니라 보낸이 하나로 센다.
        //       그리고 실패한 두 번의 시도가 장부를 늘리지 않았다(실패는 몫을 태우지 않는다).
        let fourth = try await storeA.service.sendUltraPoke(accessToken: sessionA.accessToken, to: sessionB.userID)
        #expect(fourth.status == "ultra_used_today")
        #expect(fourth.ultraRemaining == 0)
        #expect(try await ctx.admin.ultraPokeCount(fromUser: sessionA.userID) == limit)

        // (c-1) 울트라 소진이 **일반** 찌르기를 막지 않는다(쿨타임이면 cooldown, 아니면 ok — 둘 다 정상).
        let normal = try await storeA.service.sendPoke(accessToken: sessionA.accessToken, to: sessionB.userID)
        #expect(normal.status != "ultra_used_today")
        obs("울트라 소진 후 일반 찌르기: status=\(normal.status)")

        // (c-2) B 근무종료 → target_not_working. A 는 이미 오늘 몫을 다 썼는데도 ultra_used_today 가
        //       아니라는 점이 **대상근무 게이트가 하루한도보다 앞**임을 결정적으로 증명한다.
        storeB.stop()
        await storeB.syncTask?.value
        let joinerClosed = await waitUntil {
            (try? await ctx.admin.sessionRows(userID: sessionB.userID, openOnly: true))?.isEmpty == true
        }
        #expect(joinerClosed)
        let afterTargetStop = try await storeA.service.sendUltraPoke(accessToken: sessionA.accessToken, to: sessionB.userID)
        #expect(afterTargetStop.status == "target_not_working")
        obs("울트라 게이트 순서: 대상 근무종료 후 status=\(afterTargetStop.status)(하루한도보다 앞)")

        // (c-3) A 근무종료 → not_working(보낸이 게이트가 대상 게이트보다 앞).
        storeA.stop()
        await storeA.syncTask?.value
        let ownerClosed = await waitUntil {
            (try? await ctx.admin.sessionRows(userID: owner.userID, openOnly: true))?.isEmpty == true
        }
        #expect(ownerClosed)
        let afterSenderStop = try await storeA.service.sendUltraPoke(accessToken: sessionA.accessToken, to: sessionB.userID)
        #expect(afterSenderStop.status == "not_working")
        obs("울트라 게이트 순서: 보낸이 근무종료 후 status=\(afterSenderStop.status)(대상 게이트보다 앞)")

        // 후정리 — 한도 장부(=pokes 행)와 열린 세션을 남기지 않는다. 남기면 다음 실행의 첫 울트라가
        // 곧바로 ultra_used_today 를 받아 스위트가 영구히 빨개진다.
        try await ctx.admin.deleteAllPokes(fromUser: sessionA.userID)
        try await ctx.admin.closeOpenSessions(userID: owner.userID)
        try await ctx.admin.closeOpenSessions(userID: sessionB.userID)
        if let thirdTargetID {
            try await ctx.admin.closeOpenSessions(userID: thirdTargetID)
        }
    }

    // s09w. 별명 변경 RPC: 성공 → 1주일 쿨타임 → 동시 요청 원자성 → 중복 거절.
    // 마이그레이션 20260804010000/20260804020000 push 후 실행한다.
    // **진입에서 쿨타임을 스스로 리셋한다** — ensureOwnerAndTeam 이 계정을 재사용하므로(:663-670)
    // 지난 실행이 태운 1주일 쿨타임이 그대로 남아 있고, 리셋을 s10_cleanup 에만 두면 release.md 의
    // --filter 확인 명령(s10 을 안 돌린다)에서 이 시나리오가 cooldown 으로 빨개져 배포가 멈춘다.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09w_displayNameChangeCooldownAndUniqueness() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        let teamID = try #require(LiveE2EState.e2eTeamID)
        // 진입 정규화: 이름과 쿨타임을 **둘 다** 기준선으로 되돌린다. 이름을 안 되돌리면 앞 실행이
        // 중간에 끊겨 owner 가 이미 E2E별명하나 인 상태에서 (1)이 ok 대신 unchanged 를 받아 빨개진다.
        try await ctx.admin.setDisplayName(userID: owner.userID, to: E2ENames.ownerBase)
        try await ctx.admin.clearDisplayNameCooldown(userID: owner.userID)

        // owner 는 여러 시나리오가 공유하는 장기 계정이다. 이름을 남겨 두면 다음 실행의 중복 시나리오가
        // 어떤 이름을 점유 중인지 예측 불가능해지고 '-2' 접미어가 누적된다.
        // 정상 경로에서는 본문 끝에서 **await 로** 원복하고(그래야 다음 시나리오가 확정된 값을 본다),
        // 아래 defer 는 throw 로 빠져나갈 때만 도는 최후 그물이다 — 정상 경로에서도 돌면 그 늦은 쓰기가
        // 다음 시나리오 한복판에 착지해 s09y/s09z 의 기대값을 흔든다.
        var restored = false
        defer {
            if !restored {
                let admin = ctx.admin
                let ownerID = owner.userID
                Task {
                    try? await admin.setDisplayName(userID: ownerID, to: E2ENames.ownerBase)
                    try? await admin.clearDisplayNameCooldown(userID: ownerID)
                }
            }
        }

        let storeA = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { storeA.tickerTask?.cancel(); storeA.refreshTask?.cancel() }
        storeA.email = Emails.owner
        storeA.password = Emails.password
        await storeA.signIn()?.value
        let sessionA = try #require(storeA.session)

        // (1) 첫 변경은 즉시 허용된다(display_name_changed_at 이 null 이므로).
        let okResult = try await storeA.service.setDisplayName(accessToken: sessionA.accessToken, name: E2ENames.first)
        #expect(okResult.status == "ok")
        #expect(okResult.displayName == E2ENames.first)
        #expect(try await ctx.admin.profileDisplayName(userID: owner.userID) == E2ENames.first)
        #expect(try await ctx.admin.displayNameChangedAt(userID: owner.userID) != nil)
        obs("별명 변경: status=\(okResult.status), 저장='\(okResult.displayName ?? "nil")'")

        // (2) 즉시 재변경 = 쿨타임. 남은 초는 6일 초과 7일 이하여야 한다(방금 태웠으므로).
        let cooled = try await storeA.service.setDisplayName(accessToken: sessionA.accessToken, name: E2ENames.second)
        #expect(cooled.status == "cooldown")
        let retry = try #require(cooled.retryAfterSeconds)
        #expect(retry > 518_400 && retry <= 604_800)
        #expect(try await ctx.admin.profileDisplayName(userID: owner.userID) == E2ENames.first)
        obs("별명 쿨타임: status=\(cooled.status), retry_after=\(retry)초")

        // (3) 같은 사용자의 **맥 두 대**가 같은 순간에 서로 다른 이름을 저장한다. 서버가 쿨타임 판정을
        //     UPDATE 안에 넣지 않았다면(밖에서 select 로 먼저 봤다면) 둘 다 통과해 한 창에서 두 번 바뀐다.
        //     서비스는 actor 라 한 인스턴스로는 요청이 줄을 서므로, 기기 두 대를 흉내 내려면 인스턴스도 둘이어야 한다.
        try await ctx.admin.clearDisplayNameCooldown(userID: owner.userID)
        let deviceOne = SupabaseWorkService(projectURL: SupabaseConfig.projectURL, anonKey: ctx.anonKey, session: .shared)
        let deviceTwo = SupabaseWorkService(projectURL: SupabaseConfig.projectURL, anonKey: ctx.anonKey, session: .shared)
        let token = sessionA.accessToken
        async let raceOne = deviceOne.setDisplayName(accessToken: token, name: E2ENames.raceA)
        async let raceTwo = deviceTwo.setDisplayName(accessToken: token, name: E2ENames.raceB)
        let (resultOne, resultTwo) = try await (raceOne, raceTwo)
        let raceResults = [resultOne, resultTwo]
        let okCount = raceResults.filter { $0.status == "ok" }.count
        #expect(okCount == 1)
        let loser = try #require(raceResults.first { $0.status != "ok" })
        #expect(loser.status == "cooldown" || loser.status == "taken")
        let winnerName = try #require(raceResults.first { $0.status == "ok" }?.displayName)
        #expect(try await ctx.admin.profileDisplayName(userID: owner.userID) == winnerName)
        obs("별명 동시 저장: ok=\(okCount)건, 진 쪽=\(loser.status), 최종='\(winnerName)'")

        // (4) 중복 거절 + **실패는 쿨타임을 소모하지 않는다.**
        //     owner 이름을 결정적 값으로 admin 이 세팅하고(RPC 를 안 거치므로 쿨타임을 안 태운다),
        //     joiner 는 쿨타임이 만료된 상태에서 '대소문자·공백만 다른' 같은 이름을 시도한다.
        try await ctx.admin.setDisplayName(userID: owner.userID, to: E2ENames.first)
        let storeB = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { storeB.tickerTask?.cancel(); storeB.refreshTask?.cancel() }
        if try await ctx.admin.findUserID(email: Emails.joiner) != nil {
            storeB.email = Emails.joiner
            storeB.password = Emails.password
            await storeB.signIn()?.value
        }
        if !storeB.isSignedIn || storeB.currentTeamID != teamID {
            await signUpJoiningByCode(store: storeB, email: Emails.joiner, displayName: E2ENames.joinerBase, code: owner.code)
        }
        let sessionB = try #require(storeB.session)

        let expired = Date().addingTimeInterval(-8 * 24 * 3600)
        try await ctx.admin.setDisplayNameChangedAt(userID: sessionB.userID, to: expired)
        let joinerNameBefore = try #require(try await ctx.admin.profileDisplayName(userID: sessionB.userID))
        let takenResult = try await storeB.service.setDisplayName(accessToken: sessionB.accessToken, name: E2ENames.firstVariant)
        #expect(takenResult.status == "taken")
        #expect(try await ctx.admin.profileDisplayName(userID: sessionB.userID) == joinerNameBefore)
        // 실패가 몫을 태웠다면 changed_at 이 now() 로 튄다 — 8일 전 그대로여야 한다.
        let joinerChangedAfter = try #require(try await ctx.admin.displayNameChangedAt(userID: sessionB.userID))
        #expect(abs(joinerChangedAfter.timeIntervalSince(expired)) <= 2)
        obs("별명 중복 거절: status=\(takenResult.status)(공백·대소문자 변형도 같은 이름으로 본다), 쿨타임 미소모")

        // 원복(정상 경로) — 다음 시나리오가 확정된 상태를 보도록 여기서 await 로 끝낸다.
        try await ctx.admin.setDisplayName(userID: owner.userID, to: E2ENames.ownerBase)
        try await ctx.admin.clearDisplayNameCooldown(userID: owner.userID)
        try await ctx.admin.clearDisplayNameCooldown(userID: sessionB.userID)
        restored = true
    }

    // s09x. 이 웨이브의 핵심 회귀 — 별명 RPC 를 통째로 건너뛰는 직접 PATCH 가 서버 권한만으로 막히는가.
    // 앱에는 display_name 을 PATCH 하는 함수가 없으므로 악의적 클라(=curl)를 그대로 흉내 내야 실증된다.
    // **대조군이 절반이다**: 같은 토큰의 avatar_url·token_usage_public PATCH 는 여전히 2xx 여야 한다.
    // 대조군이 없으면 '막긴 했는데 아바타 변경과 토큰 공개 토글을 같이 죽였다'를 프로덕션 전에 못 잡는다.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09x_directDisplayNamePatchIsRejected() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)

        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
        store.email = Emails.owner
        store.password = Emails.password
        await store.signIn()?.value
        let session = try #require(store.session)
        #expect(session.userID == owner.userID)

        let nameBefore = try #require(try await ctx.admin.profileDisplayName(userID: owner.userID))
        let avatarBefore = try await ctx.admin.profileAvatarURL(userID: owner.userID)
        let publicBefore = try await ctx.admin.profileTokenUsagePublic(userID: owner.userID) ?? true
        let selfFilter = [URLQueryItem(name: "id", value: "eq.\(owner.userID)")]

        // (1) 우회 시도 → 42501(권한 없음)이 403 으로 나와야 한다. 200 이면 즉시 배포 중단감이다:
        //     길이·중복·쿨타임 판정 전부를 한 요청으로 건너뛸 수 있다는 뜻이다.
        let bypass = try await userRest(
            anonKey: ctx.anonKey, accessToken: session.accessToken,
            path: "/rest/v1/profiles", method: "PATCH",
            query: selfFilter, json: ["display_name": "우회"]
        )
        #expect((400..<500).contains(bypass.status))
        #expect(bypass.status == 403)
        #expect(try await ctx.admin.profileDisplayName(userID: owner.userID) == nameBefore)
        obs("별명 직접 PATCH 차단: HTTP \(bypass.status), 이름 불변=\(try await ctx.admin.profileDisplayName(userID: owner.userID) == nameBefore)")

        // (2) 대조군 A — 아바타 URL PATCH 는 계속 살아 있어야 한다(uploadAvatar 의 두 번째 단계).
        let avatarPatch = try await userRest(
            anonKey: ctx.anonKey, accessToken: session.accessToken,
            path: "/rest/v1/profiles", method: "PATCH",
            query: selfFilter, json: ["avatar_url": "https://example.com/e2e-avatar.jpg"]
        )
        #expect((200..<300).contains(avatarPatch.status))
        let avatarAfter = try await ctx.admin.profileAvatarURL(userID: owner.userID)
        #expect(avatarAfter == "https://example.com/e2e-avatar.jpg")

        // (3) 대조군 B — 토큰 공개 토글 PATCH 도 계속 살아 있어야 한다(updateTokenUsagePublic).
        let privacyPatch = try await userRest(
            anonKey: ctx.anonKey, accessToken: session.accessToken,
            path: "/rest/v1/profiles", method: "PATCH",
            query: selfFilter, json: ["token_usage_public": !publicBefore]
        )
        #expect((200..<300).contains(privacyPatch.status))
        let publicAfter = try await ctx.admin.profileTokenUsagePublic(userID: owner.userID)
        #expect(publicAfter == !publicBefore)
        obs("대조군: avatar_url HTTP \(avatarPatch.status), token_usage_public HTTP \(privacyPatch.status)(둘 다 2xx 여야 한다)")

        // 원복 — 깨진 이미지 URL 과 뒤집힌 공개설정을 남기면 이후 시나리오의 보드 기대값이 흔들린다.
        try await ctx.admin.setAvatarURL(userID: owner.userID, to: avatarBefore)
        try await ctx.admin.setTokenUsagePublic(userID: owner.userID, to: publicBefore)
    }

    // s09y. 표시명이 이미 쓰이고 있어도 **가입은 성공한다**(충돌 시 접미어를 붙인다).
    // 유일 인덱스만 넣고 가입 트리거를 안 고치면 두 번째 동명 가입의 profiles INSERT 가 죽고,
    // 그 롤백이 auth.users INSERT 까지 되돌려 새 사람이 앱에 아예 못 들어온다 — 이 시나리오가 그 방어선이다.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09y_signUpFallsBackWhenDisplayNameTaken() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)
        try await ctx.admin.deleteByEmail(Emails.dupName)   // 깨끗한 재실행(멱등)
        // 충돌 대상을 결정적으로 만든다. admin PATCH 라 owner 의 쿨타임을 태우지 않는다.
        try await ctx.admin.setDisplayName(userID: owner.userID, to: E2ENames.duplicate)

        var restored = false
        defer {
            if !restored {
                let admin = ctx.admin
                let ownerID = owner.userID
                Task { try? await admin.setDisplayName(userID: ownerID, to: E2ENames.ownerBase) }
            }
        }

        // 앱의 가입 HTTP 요청을 서비스로 직접 만든다. 스토어의 signUp() 은 코드 모드에서 joinPreview 를
        // 요구하고 만들기 모드는 팀을 만들어 버려 **무소속 가입**을 만들 수 없는데, 아래 S1 회귀 단언
        // (memberships 0행)은 무소속이어야 성립한다. 보내는 본문은 스토어 경로와 완전히 같다.
        let service = SupabaseWorkService(projectURL: SupabaseConfig.projectURL, anonKey: ctx.anonKey, session: .shared)
        let created = try await service.signUp(
            email: Emails.dupName, password: Emails.password, displayName: E2ENames.duplicate
        )
        let newSession = try #require(created)   // 중복이어도 **성공**이다(실패로 바뀌지 않는 것이 핵심).
        let newUserID = newSession.userID

        let profileReady = await waitUntil {
            (try? await ctx.admin.profileCount(userID: newUserID)) == 1
        }
        #expect(profileReady)
        #expect(try await ctx.admin.profileDisplayName(userID: newUserID) == "\(E2ENames.duplicate)-2")
        obs("동명 가입: 성공, 표시명='\(try await ctx.admin.profileDisplayName(userID: newUserID) ?? "nil")'")

        // S1 이 가입 트리거를 20260701000000 본문으로 되돌리면 여기서 memberships 가 1행(레거시 팀)이 된다.
        // 이 두 줄이 '신규 가입자 전원이 참여한 적 없는 팀에 자동 소속'을 프로덕션 전에 잡는 유일한 자동 검사다.
        #expect(try await ctx.admin.membershipRows(userID: newUserID).isEmpty)
        #expect(try await ctx.admin.statusRows(userID: newUserID).isEmpty)

        // 만든 계정으로 실제 로그인까지 되는지 — '가입 성공'의 최종 의미는 그 사람이 앱을 쓸 수 있다는 것이다.
        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
        store.email = Emails.dupName
        store.password = Emails.password
        await store.signIn()?.value
        #expect(store.isSignedIn)

        try await ctx.admin.setDisplayName(userID: owner.userID, to: E2ENames.ownerBase)
        restored = true
    }

    // s09z. 입력 거절 3종. 셋 다 **쿨타임을 소모하지 않는다** — 실패한 시도가 몫을 태우면
    // 오타 한 번에 일주일 잠긴다.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s09z_setDisplayNameRejectsBlankAndTooLong() async throws {
        let ctx = try makeContext()
        let owner = try await ensureOwnerAndTeam(anonKey: ctx.anonKey, admin: ctx.admin)

        let store = makeLiveStore(anonKey: ctx.anonKey, defaults: liveIsolatedDefaults())
        defer { store.tickerTask?.cancel(); store.refreshTask?.cancel() }
        store.email = Emails.owner
        store.password = Emails.password
        await store.signIn()?.value
        let session = try #require(store.session)

        let nameBefore = try #require(try await ctx.admin.profileDisplayName(userID: owner.userID))
        let changedBefore = try await ctx.admin.displayNameChangedAt(userID: owner.userID)

        // 공백만 있는 이름 → 정규화 후 빈 문자열.
        let blank = try await store.service.setDisplayName(accessToken: session.accessToken, name: "   ")
        #expect(blank.status == "invalid_empty")

        // 13자 → 서버 max_len(12)을 정확히 1 넘긴다. 서버가 돌려주는 max_length 가 클라 상수와 같아야
        // "12자까지 쓸 수 있어요" 안내와 서버 판정이 어긋나지 않는다.
        #expect(E2ENames.tooLong.unicodeScalars.count == WorkTimerStore.displayNameMaxLength + 1)
        let tooLong = try await store.service.setDisplayName(accessToken: session.accessToken, name: E2ENames.tooLong)
        #expect(tooLong.status == "invalid_long")
        #expect(tooLong.maxLength == WorkTimerStore.displayNameMaxLength)

        // 현재 이름 그대로 저장 → unchanged. 이 분기가 없으면 아무것도 안 바꾸고 저장만 눌러도
        // 쿨타임 1주일이 헛되이 소모된다.
        let unchanged = try await store.service.setDisplayName(accessToken: session.accessToken, name: nameBefore)
        #expect(unchanged.status == "unchanged")
        #expect(unchanged.displayName == nameBefore)

        #expect(try await ctx.admin.profileDisplayName(userID: owner.userID) == nameBefore)
        let changedAfter = try await ctx.admin.displayNameChangedAt(userID: owner.userID)
        #expect(changedBefore == changedAfter)
        obs("별명 입력 거절: 공백=\(blank.status), 13자=\(tooLong.status)(max=\(tooLong.maxLength.map(String.init) ?? "nil")), 동일=\(unchanged.status), 쿨타임 미소모")
    }

    // 10. 정리 → E2E 계정 + E2E 팀 삭제 후 잔존 0 확인. E2E 접두사 밖(실사용) 팀 수는 변하지 않아야 한다.
    @Test(.enabled(if: LiveE2EEnv.enabled))
    func s10_cleanup() async throws {
        let ctx = try makeContext()

        let ownerUserID = try? await ctx.admin.findUserID(email: Emails.owner)
        let joinerUserID = try? await ctx.admin.findUserID(email: Emails.joiner)
        let nicknameUserID = try? await ctx.admin.findUserID(email: Emails.nickname)
        let dupNameUserID = try? await ctx.admin.findUserID(email: Emails.dupName)

        // 별명 쿨타임·울트라 장부 일괄 리셋(보조 방어선). 각 시나리오가 진입에서 스스로 리셋하므로 평소엔
        // 잉여지만, 앞 단계가 throw 로 끊겨 계정이 남은 실행에서 다음 회차를 구해 준다.
        // 계정 삭제가 성공하면 캐스케이드로 어차피 사라진다 — 실패했을 때를 위한 그물이다.
        for userID in [ownerUserID, joinerUserID, nicknameUserID, dupNameUserID].compactMap({ $0 }) {
            try? await ctx.admin.clearDisplayNameCooldown(userID: userID)
            try? await ctx.admin.deleteUltraPokes(fromUser: userID)
        }

        for email in Emails.managed {
            let removed = try await ctx.admin.deleteByEmail(email)
            obs("정리 \(email): \(removed ? "admin 삭제" : "이미 없음")")
        }

        // 계정 캐스케이드로 멤버십/상태/세션은 사라지지만, teams 행은 팀 삭제로 별도 정리한다(E2E 접두사만).
        let deletedTeams = try await ctx.admin.deleteAllE2ETeams()
        obs("정리 E2E 팀: \(deletedTeams)개 삭제")

        for email in Emails.managed {
            #expect(try await ctx.admin.findUserID(email: email) == nil)
            #expect(try await ctx.admin.profileCount(byEmail: email) == 0)
        }

        for userID in [ownerUserID, joinerUserID, nicknameUserID, dupNameUserID,
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

        // E2E 팀은 모두 사라졌다(실사용 팀은 접두사 스코프 밖이라 애초에 건드리지 않는다).
        #expect(try await ctx.admin.teams(namePrefix: E2ETeam.namePrefix).isEmpty)

        print("E2E| ===== 관측 요약 =====")
        for line in LiveE2EState.observations {
            print("E2E| - \(line)")
        }
    }
}
