// 원본: 없음
@testable import CheckCore
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckMobileKit

// W1-d G5 요청 골든(C§5.2 · G §2-3 W1-d ①): 서비스 메서드 + 표준 인자 → 나간 요청(메서드 · 경로 · 쿼리 쌍 · 헤더 여섯 ·
// 본문 정규 JSON). Kotlin 은 같은 이름의 호출을 MockEngine 으로 녹음해 대조한다 — **레지스트리에 없는 이름은 "미이식"으로 빨강**.
//
// 빠짐 금지: `allServiceMethods()` 가 Swift 소스에서 SupabaseWorkService 의 메서드 이름을 긁어, 모든 이름이 case(접두가 같은 id)
// · 갈래 밖 태그(H 맥 전용 · I AI 리밋 쓰기 · admin 운영자 — G §2-3 "H·I 몫은 태그로 뺀다") · 내부 도우미 중 하나임을 단언한다.
// 새 RPC 가 생기면 이 시험이 먼저 빨갛다.

/// 응답 대본(차례대로 쓰고, 끝나면 200 `{}`). 길(route)이 있으면 차례 대신 요청 모양으로 고른다(동시에 떠나는 요청).
final class WireScript: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [MobileStubResponse]
    private let routes: [WireRoute]
    init(_ responses: [MobileStubResponse], routes: [WireRoute] = []) {
        queue = responses
        self.routes = routes
    }
    func next(for request: MobileStubRequest) -> MobileStubResponse {
        lock.lock(); defer { lock.unlock() }
        if !routes.isEmpty { return routes.first { $0.matches(request) }?.response ?? .json("{}") }
        return queue.isEmpty ? .json("{}") : queue.removeFirst()
    }
}

struct WireCall {
    let id: String
    var responses: [MobileStubResponse] = []
    /// 동시에 떠나는 요청(팀 상태 네 GET) — 순서 없는 모음으로 비교한다.
    var unordered = false
    var routes: [WireRoute] = []
    var clock: WireClock? = nil
    let run: (SupabaseWorkService, String) async throws -> Any?
}

enum WireRequestRecorder {
    static let pgrst202 = MobileStubResponse.missingFunction("x")
    static let deadlock = MobileStubResponse.json(#"{"code":"40P01","message":"deadlock detected"}"#, status: 400)
    static let headerWhitelist = ["apikey", "authorization", "accept", "content-type", "prefer", "x-upsert"]

    /// 아바타 캐시 무력화 꼬리(시각·uuid) → 자리표시.
    static func scrub(_ text: String, host: String) -> String {
        var t = text.replacingOccurrences(of: WireGoldenValues.accessToken, with: "<ACCESS>")
            .replacingOccurrences(of: WireGoldenValues.anonKey, with: "<ANON>")
            .replacingOccurrences(of: host, with: "golden.invalid")
        t = t.replacingOccurrences(of: #"\?v=[0-9]+-[0-9A-F]{8}"#, with: "?v=<CACHE_BUSTER>", options: .regularExpression)
        return t
    }

    static func record(_ call: WireCall, index: Int) async throws -> GoldenJSON {
        let host = "w1d-g5-\(index)-\(UUID().uuidString.prefix(8).lowercased()).invalid"
        let script = WireScript(call.responses, routes: call.routes)
        MobileStubURLProtocol.register(host: host) { request in script.next(for: request) }
        defer { MobileStubURLProtocol.unregister(host: host) }
        let clock = call.clock
        let service = SupabaseWorkService(
            projectURL: URL(string: "https://\(host)")!,
            anonKey: WireGoldenValues.anonKey,
            session: MobileStubURLProtocol.makeSession(),
            clock: { clock?.now ?? WireGoldenValues.now }
        )
        let result: GoldenJSON
        do {
            result = try WireResult.ok(try await call.run(service, WireGoldenValues.accessToken), host: host)
        } catch {
            result = WireResult.thrown(error)
        }
        var requests: [GoldenJSON] = []
        for r in MobileStubURLProtocol.requests(host: host) {
            var headers: [String: GoldenJSON] = [:]
            for (k, v) in r.headers where headerWhitelist.contains(k.lowercased()) {
                headers[k.lowercased()] = .string(scrub(v, host: host))
            }
            let items = URLComponents(string: "https://x/?\(r.query)")?.queryItems ?? []
            let query: [GoldenJSON] = r.query.isEmpty ? [] : items.map { .array([.string($0.name), .string(scrub($0.value ?? "", host: host))]) }
            let body: GoldenJSON
            if r.bodyText.isEmpty {
                body = .null
            } else if let tree = try? WireJSON.parse(r.bodyText) {
                body = try GoldenJSON.parse(Data(scrub(try tree.golden.canonicalText(), host: host).utf8))
            } else {
                body = .object(["$bytes": .string(Data(r.bodyText.utf8).base64EncodedString())])
            }
            requests.append(.object([
                "method": .string(r.method), "path": .string(r.path), "query": .array(query),
                "headers": .object(headers), "body": body,
            ]))
        }
        if call.unordered {
            requests = try requests.map { ($0, try $0.canonicalText()) }.sorted { GoldenJSON.keyPrecedes($0.1, $1.1) }.map(\.0)
        }
        let responses: [GoldenJSON] = call.responses.map {
            .object(["status": .int($0.status), "body": .string(String(decoding: $0.body, as: UTF8.self))])
        }
        return .object([
            "id": .string(call.id), "requests": .array(requests), "responses": .array(responses), "unordered": .bool(call.unordered),
            "routes": .array(call.routes.map(\.golden)), "result": result,
        ])
    }
}

@Suite("GoldenExport W1-d 와이어 — G5 요청 골든")
struct GoldenExportWireRequests {
    static let u = WireGoldenValues.userID
    static let p = WireGoldenValues.peerID
    static let m = WireGoldenValues.matchID
    static let now = WireGoldenValues.now
    static let rid = WireGoldenValues.requestID

    static var calls: [WireCall] {
        let u = u, p = p, m = m, now = now, rid = rid
        let shopClock = WireClock(now)
        let notice = MobileStubResponse.json(#"[{"weekly_goal_hours": 40}]"#)
        return [
            // ---- 인증 ----
            WireCall(id: "signIn") { s, _ in try await s.signIn(email: "a@b.invalid", password: "pw-123456") },
            WireCall(id: "signUp") { s, _ in try await s.signUp(email: "a@b.invalid", password: "pw-123456", displayName: "아잉") },
            WireCall(id: "signUp(center)") { s, _ in try await s.signUp(email: "a@b.invalid", password: "pw", displayName: "아잉", center: "busan") },
            WireCall(id: "refreshSession") { s, _ in try await s.refreshSession(refreshToken: "refresh-1") },
            WireCall(id: "signOut") { s, t in await s.signOut(accessToken: t) },
            WireCall(id: "logoutLocalScope") { s, t in try await s.logoutLocalScope(accessToken: t) },
            WireCall(id: "deleteMyAccount") { s, t in try await s.deleteMyAccount(accessToken: t) },
            WireCall(id: "sendPasswordResetCode") { s, _ in try await s.sendPasswordResetCode(email: "a@b.invalid") },
            WireCall(id: "verifyPasswordResetCode") { s, _ in try await s.verifyPasswordResetCode(email: "a@b.invalid", code: "123456") },
            WireCall(id: "updatePassword") { s, t in try await s.updatePassword(accessToken: t, newPassword: "new-pw-1") },
            WireCall(id: "verifySignUpCode") { s, _ in try await s.verifySignUpCode(email: "a@b.invalid", code: "654321") },
            WireCall(id: "resendSignUpCode") { s, _ in try await s.resendSignUpCode(email: "a@b.invalid") },
            // ---- 팀 ----
            WireCall(id: "lookupTeamByCode") { s, _ in try await s.lookupTeamByCode(code: " ab-c 12 ") },
            WireCall(id: "fetchMyInviteCode") { s, t in try await s.fetchMyInviteCode(accessToken: t) },
            WireCall(id: "setTeamWeeklyGoal", responses: [notice]) { s, t in try await s.setTeamWeeklyGoal(accessToken: t, goalHours: 40) },
            WireCall(id: "joinTeam") { s, t in try await s.joinTeam(accessToken: t, code: "xyz-789") },
            WireCall(id: "createTeam") { s, t in try await s.createTeam(accessToken: t, name: "새 팀", goalHours: 60) },
            WireCall(id: "fetchTeamLeaderboard") { s, t in try await s.fetchTeamLeaderboard(accessToken: t) },
            WireCall(id: "fetchTeamLeaderboard(weekOffset)") { s, t in try await s.fetchTeamLeaderboard(accessToken: t, weekOffset: 3) },
            WireCall(id: "fetchTeamLeaderboard(weekOffset)#clamp") { s, t in try await s.fetchTeamLeaderboard(accessToken: t, weekOffset: 99) },
            WireCall(id: "fetchTeamLeaderboard(weekOffset)#fallback", responses: [WireRequestRecorder.pgrst202, .json("[]")]) { s, t in
                return try await s.fetchTeamLeaderboard(accessToken: t, weekOffset: 2)
            },
            WireCall(id: "fetchOwnMembership") { s, t in try await s.fetchOwnMembership(accessToken: t, userID: u) },
            // 네 GET 이 동시에 떠난다. 하나라도 디코드에 실패하면 Swift 는 나머지 `async let` 을 취소해 **아직 안 떠난 요청이 빠진다**
            // (부하에 따라 요청 수가 3·4 로 갈렸다 — 골든 비결정). 그래서 빈 배열을 길로 준다(결과 대조는 #data).
            WireCall(id: "fetchTeamStatuses", unordered: true, routes: [
                WireRoute(path: "/rest/v1/work_statuses", response: .json("[]")), WireRoute(path: "/rest/v1/work_sessions", response: .json("[]")),
                WireRoute(path: "/rest/v1/work_status_devices", response: .json("[]")),
            ]) { s, t in try await s.fetchTeamStatuses(accessToken: t, teamID: "team-1", now: now) },
            // ---- 기록 · 토큰 · 프로필 ----
            WireCall(id: "fetchMySessions") { s, t in try await s.fetchMySessions(accessToken: t, userID: u, since: now.addingTimeInterval(-86_400 * 30)) },
            WireCall(id: "fetchMyTokenDaily") { s, t in try await s.fetchMyTokenDaily(accessToken: t, userID: u, since: "2026-08-01") },
            WireCall(id: "fetchTokenBoard") { s, t in try await s.fetchTokenBoard(accessToken: t, month: "2026-09") },
            WireCall(id: "fetchMiniGamePublic") { s, t in try await s.fetchMiniGamePublic(accessToken: t, userID: u) },
            WireCall(id: "updateMiniGamePublic") { s, t in try await s.updateMiniGamePublic(accessToken: t, userID: u, isPublic: false) },
            WireCall(id: "fetchMyCenter") { s, t in try await s.fetchMyCenter(accessToken: t, userID: u) },
            WireCall(id: "fetchMyStatusMessage") { s, t in try await s.fetchMyStatusMessage(accessToken: t, userID: u) },
            WireCall(id: "setStatusMessage") { s, t in try await s.setStatusMessage(accessToken: t, text: "집중 중") },
            WireCall(id: "setStatusMessage(nil)") { s, t in try await s.setStatusMessage(accessToken: t, text: nil) },
            WireCall(id: "fetchTokenUsageSettings") { s, t in try await s.fetchTokenUsageSettings(accessToken: t, userID: u) },
            WireCall(id: "updateTokenUsagePublic") { s, t in try await s.updateTokenUsagePublic(accessToken: t, userID: u, isPublic: true) },
            WireCall(id: "setDisplayName") { s, t in try await s.setDisplayName(accessToken: t, name: "새이름") },
            WireCall(id: "fetchDisplayNameChangedAt") { s, t in try await s.fetchDisplayNameChangedAt(accessToken: t, userID: u) },
            WireCall(id: "setCharacter") { s, t in try await s.setCharacter(accessToken: t, id: "aing_cake_choco") },
            WireCall(id: "setCharacter(nil)") { s, t in try await s.setCharacter(accessToken: t, id: nil) },
            WireCall(id: "fetchEquippedCharacter") { s, t in try await s.fetchEquippedCharacter(accessToken: t, userID: u) },
            WireCall(id: "fetchMyProfileCard") { s, t in try await s.fetchMyProfileCard(accessToken: t, userID: u) },
            WireCall(id: "fetchMyAILimits") { s, t in try await s.fetchMyAILimits(accessToken: t, userID: u) },
            // ---- 사진 ----
            WireCall(id: "uploadAvatar") { s, t in try await s.uploadAvatar(accessToken: t, userID: u, imageData: Data("JPEG-BYTES".utf8)) },
            WireCall(id: "removeAvatar") { s, t in try await s.removeAvatar(accessToken: t, userID: u) },
            WireCall(id: "deleteAvatarFile") { s, t in await s.deleteAvatarFile(accessToken: t, userID: u) },
            WireCall(id: "deleteAvatarIfAny") { s, t in await s.deleteAvatarIfAny(accessToken: t, userID: u) },
            // ---- 미니게임 ----
            WireCall(id: "startMiniGameRound") { s, t in try await s.startMiniGameRound(accessToken: t, kind: .flappy) },
            WireCall(id: "submitMiniGameScore") { s, t in try await s.submitMiniGameScore(accessToken: t, kind: .tetris, score: 3_000_000_000, token: "tok") },
            WireCall(id: "fetchMiniGameBoard") { s, t in try await s.fetchMiniGameBoard(accessToken: t, kind: .timingBar) },
            WireCall(id: "fetchMiniGameBoard(day)") { s, t in try await s.fetchMiniGameBoard(accessToken: t, kind: .crossy, day: "2026-09-16") },
            WireCall(id: "fetchMiniGameYesterdayWinner") { s, t in try await s.fetchMiniGameYesterdayWinner(accessToken: t, kind: .flappy) },
            WireCall(id: "fetchMiniGameAllTimeBoard") { s, t in try await s.fetchMiniGameAllTimeBoard(accessToken: t, kind: .crossy) },
            // ---- 상점(C§4 #9) ----
            WireCall(id: "fetchShopState") { s, t in try await s.fetchShopState(accessToken: t) },
            WireCall(id: "fetchShopState(protocol)") { s, t in try await s.fetchShopState(accessToken: t, protocolVersion: 4) },
            WireCall(id: "fetchShopState(protocol)#fallback", responses: [WireRequestRecorder.pgrst202, .json("{}"), .json("{}")]) { s, t in
                let first = try await s.fetchShopState(accessToken: t, protocolVersion: 4)
                let second = try await s.fetchShopState(accessToken: t, protocolVersion: 4) // 깃발 5분 — 바로 옛 모양
                return [first, second]
            },
            // 본문이 오류 문장인 404 는 authMessage 라 되묻지도 않는다(isMissingFunction 아님) — 첫 호출이 던지고 둘째는 다시 새 모양.
            WireCall(id: "fetchShopState(protocol)#plain404", responses: [.json(#"{"message":"nope"}"#, status: 404), .json("{}"), .json("{}")]) { s, t in
                _ = try? await s.fetchShopState(accessToken: t, protocolVersion: 4) // authMessage("nope") 로 던진다 — 되묻기 없음
                return try await s.fetchShopState(accessToken: t, protocolVersion: 4)
            },
            WireCall(id: "buyCharacter") { s, t in try await s.buyCharacter(accessToken: t, id: "robot") },
            WireCall(id: "buyCharacter(protocol)") { s, t in try await s.buyCharacter(accessToken: t, id: "robot", protocolVersion: 3) },
            WireCall(id: "buyCharacter(protocol)#fallback", responses: [WireRequestRecorder.pgrst202, .json(#"{"status":"ok"}"#)]) { s, t in
                return try await s.buyCharacter(accessToken: t, id: "fox", protocolVersion: 3)
            },
            // ---- 메시지 ----
            WireCall(id: "sendMessage") { s, t in try await s.sendMessage(accessToken: t, to: p, body: "  안녕하세요\n") },
            WireCall(id: "sendMessage#empty") { s, t in try await s.sendMessage(accessToken: t, to: p, body: " \n ") },
            WireCall(id: "sendMessage#tooLong") { s, t in try await s.sendMessage(accessToken: t, to: p, body: String(repeating: "가", count: 201)) },
            WireCall(id: "fetchMessageHistory") { s, t in try await s.fetchMessageHistory(accessToken: t) },
            WireCall(id: "fetchMessageHistory#clamp") { s, t in try await s.fetchMessageHistory(accessToken: t, hours: 99, limit: 0) },
            WireCall(id: "fetchPokeDirectory") { s, t in try await s.fetchPokeDirectory(accessToken: t) },
            WireCall(id: "fetchMessageHistoryWithReads") { s, t in try await s.fetchMessageHistoryWithReads(accessToken: t, hours: 24, limit: 600) },
            WireCall(id: "fetchMessageUnreadSummary") { s, t in try await s.fetchMessageUnreadSummary(accessToken: t) },
            WireCall(id: "markMessagesRead") { s, t in try await s.markMessagesRead(accessToken: t, peerUserID: p, throughMessageID: "msg-9") },
            WireCall(id: "markMessagesRead(nil)") { s, t in try await s.markMessagesRead(accessToken: t, peerUserID: p, throughMessageID: nil) },
            WireCall(id: "fetchMessageHistoryWithPokes") { s, t in try await s.fetchMessageHistoryWithPokes(accessToken: t, hours: 0, limit: 50) },
            WireCall(id: "markConversationRead") { s, t in try await s.markConversationRead(accessToken: t, peerUserID: p, throughMessageID: "msg-9", throughPokeID: "poke-3") },
            WireCall(id: "markConversationRead(nil)") { s, t in try await s.markConversationRead(accessToken: t, peerUserID: p, throughMessageID: nil, throughPokeID: nil) },
            // ---- 릴리스 · 공지 ----
            WireCall(id: "fetchLatestRelease") { s, _ in try await s.fetchLatestRelease() },
            WireCall(id: "appCurrentNotice") { s, _ in try await s.appCurrentNotice() },
            // ---- 제보 ----
            WireCall(id: "submitFeedback") { s, t in try await s.submitFeedback(accessToken: t, kind: .bug, body: "버튼이 안 눌려요", appVersion: "1.0.14", osVersion: "17.6") },
            WireCall(id: "fetchFeedbackList") { s, t in try await s.fetchFeedbackList(accessToken: t, status: nil, limit: 50) },
            WireCall(id: "fetchFeedbackList(status)") { s, t in try await s.fetchFeedbackList(accessToken: t, status: .inProgress, limit: 20) },
            WireCall(id: "setFeedbackStatus") { s, t in try await s.setFeedbackStatus(accessToken: t, id: "fb-1", status: .held, note: nil) },
            WireCall(id: "setFeedbackStatus(note)") { s, t in try await s.setFeedbackStatus(accessToken: t, id: "fb-1", status: .done, note: "고쳤어요") },
            // 응답 시각을 못 읽으면 Swift 는 벽시계 `Date()`, Kotlin 은 주입 시계(앱 조립 = 시스템 시계)다 — 둘 다 "$now" 로 적는다.
            WireCall(id: "replyFeedback") { s, t in Self.nowMarked(try await s.replyFeedback(accessToken: t, id: "fb-1", note: "답장")) },
            WireCall(id: "fetchFeedbackReplyLatest") { s, t in try await s.fetchFeedbackReplyLatest(accessToken: t) },
            WireCall(id: "fetchFeedbackOpenCount") { s, t in try await s.fetchFeedbackOpenCount(accessToken: t) },
            // ---- 차단 · 신고 ----
            WireCall(id: "blockUser") { s, t in try await s.blockUser(accessToken: t, userID: p) },
            WireCall(id: "unblockUser") { s, t in try await s.unblockUser(accessToken: t, userID: p) },
            WireCall(id: "fetchBlocks") { s, t in try await s.fetchBlocks(accessToken: t) },
            WireCall(id: "reportContent") { s, t in try await s.reportContent(accessToken: t, targetUserID: p, reason: .harassment, detail: "욕설", messageID: "msg-1", alsoBlock: true) },
            WireCall(id: "reportContent#empty") { s, t in try await s.reportContent(accessToken: t, targetUserID: p, reason: .spam, detail: "", messageID: nil, alsoBlock: false) },
            // ---- 캐릭터 · 선물 · 뽑기 ----
            WireCall(id: "fetchAppUserCharacters") { s, t in try await s.fetchAppUserCharacters(accessToken: t) },
            WireCall(id: "fetchCharacterGiftPending") { s, t in try await s.fetchCharacterGiftPending(accessToken: t, protocolVersion: 4) },
            WireCall(id: "claimCharacterGift") { s, t in try await s.claimCharacterGift(accessToken: t, giftID: "gift-1", characterID: "aing_cake_strawberry", protocolVersion: 4) },
            WireCall(id: "gachaPull") { s, t in try await s.gachaPull(accessToken: t, protocolVersion: 4, requestID: rid) },
            WireCall(id: "gachaExchange") { s, t in try await s.gachaExchange(accessToken: t, characterID: "aing_rainbow", protocolVersion: 4, requestID: rid) },
            // ---- 할 일(p_since_ms 는 null 이어도 싣는다 — C§4 #10) ----
            WireCall(id: "todoSync") { s, t in
                return try await s.todoSync(accessToken: t, request: TodoSyncRequest(changes: [], sinceMs: nil))
            },
            WireCall(id: "todoSync(changes)") { s, t in
                let item = TodoSyncWireItem(id: "0000000a-0000-4000-8000-00000000000a", title: "할 일", createdAtMs: 1_726_500_000_000,
                                            updatedAtMs: 1_726_500_005_000, completedAtMs: nil, deletedAtMs: nil, originDayKey: "20240917")
                return try await s.todoSync(accessToken: t, request: TodoSyncRequest(changes: [item], sinceMs: 1_726_400_000_000))
            },
            // ---- W1-c 응답 타입(요청 모양은 W1-d) ----
            WireCall(id: "achievementsStatus") { s, t in try await s.achievementsStatus(accessToken: t) },
            WireCall(id: "achievementClaim") { s, t in try await s.achievementClaim(accessToken: t, key: "poke10") },
            WireCall(id: "achievementClaim(nil)") { s, t in try await s.achievementClaim(accessToken: t, key: nil) },
            WireCall(id: "dailyMissionClaim") { s, t in try await s.dailyMissionClaim(accessToken: t, key: "daily_gomoku") },
            WireCall(id: "dailyMissionClaim(nil)") { s, t in try await s.dailyMissionClaim(accessToken: t, key: nil) },
            WireCall(id: "weeklyWorkStatus") { s, t in try await s.weeklyWorkStatus(accessToken: t) },
            WireCall(id: "weeklyWorkClaim") { s, t in try await s.weeklyWorkClaim(accessToken: t) },
            WireCall(id: "weeklyWorkClaim(args)") { s, t in try await s.weeklyWorkClaim(accessToken: t, weekStart: "2026-09-14", hours: 40) },
            WireCall(id: "sendMegaphone") { s, t in try await s.sendMegaphone(accessToken: t, body: "다들 화이팅", requestID: "dd000000-0000-4000-8000-0000000000d4") },
            WireCall(id: "megaphoneInfo") { s, t in try await s.megaphoneInfo(accessToken: t) },
            // ---- 기기 · 폰 근무 ----
            WireCall(id: "fetchClientRelease") { s, _ in try await s.fetchClientRelease() },
            WireCall(id: "registerDevice") { s, t in
                return try await s.registerDevice(accessToken: t, installationID: "11111111-2222-4333-8444-555555555555", appBuild: 2_147_483_648,
                                               appVersion: "1.0.14", apnsToken: "tok", apnsEnvironment: "production")
            },
            WireCall(id: "registerDevice#tokenOnly") { s, t in
                return try await s.registerDevice(accessToken: t, installationID: "i", appBuild: 7, appVersion: nil, apnsToken: "tok", apnsEnvironment: nil)
            },
            WireCall(id: "unregisterDevice") { s, t in try await s.unregisterDevice(accessToken: t, installationID: "i") },
            WireCall(id: "setPushPrefs") { s, t in try await s.setPushPrefs(accessToken: t, installationID: "i", prefs: PushPrefs(message: false)) },
            WireCall(id: "startPhoneWork") { s, t in try await s.startPhoneWork(accessToken: t) },
            WireCall(id: "stopPhoneWork") { s, t in try await s.stopPhoneWork(accessToken: t, sessionID: "ABCDEF00-0000-4000-8000-000000000001") },
            WireCall(id: "stopPhoneWork(nil)") { s, t in try await s.stopPhoneWork(accessToken: t, sessionID: nil) },
            WireCall(id: "touchPhoneWork") { s, t in try await s.touchPhoneWork(accessToken: t) },
            // ---- 오목 ----
            WireCall(id: "gomokuLobby") { s, t in try await s.gomokuLobby(accessToken: t) },
            WireCall(id: "gomokuChallenge") { s, t in try await s.gomokuChallenge(accessToken: t, opponentID: p, stake: 10) },
            WireCall(id: "gomokuCancel") { s, t in try await s.gomokuCancel(accessToken: t, matchID: m) },
            WireCall(id: "gomokuRespond") { s, t in try await s.gomokuRespond(accessToken: t, matchID: m, accept: true) },
            WireCall(id: "gomokuMove") { s, t in try await s.gomokuMove(accessToken: t, matchID: m, expectedSeq: 4, x: 7, y: 8) },
            WireCall(id: "gomokuMove#deadlock", responses: [WireRequestRecorder.deadlock, WireRequestRecorder.deadlock]) { s, t in
                return try await s.gomokuMove(accessToken: t, matchID: m, expectedSeq: 4, x: 7, y: 8)
            },
            WireCall(id: "gomokuResign") { s, t in try await s.gomokuResign(accessToken: t, matchID: m) },
            WireCall(id: "gomokuState") { s, t in try await s.gomokuState(accessToken: t, matchID: m, sinceSeq: 3, sinceChatSeq: 1) },
            WireCall(id: "gomokuState#deadlock", responses: [WireRequestRecorder.deadlock]) { s, t in
                return try await s.gomokuState(accessToken: t, matchID: m, sinceSeq: 0, sinceChatSeq: 0)
            },
            WireCall(id: "gomokuInbox") { s, t in try await s.gomokuInbox(accessToken: t) },
            WireCall(id: "gomokuChatSend") { s, t in try await s.gomokuChatSend(accessToken: t, matchID: m, kind: .quick, body: "잘 부탁해요") },
            WireCall(id: "gomokuLeave") { s, t in try await s.gomokuLeave(accessToken: t, matchID: m) },
            WireCall(id: "gomokuChatMute") { s, t in try await s.gomokuChatMute(accessToken: t, matchID: m, muted: true) },
            WireCall(id: "gomokuRanking") { s, t in try await s.gomokuRanking(accessToken: t) },
            WireCall(id: "gomokuWatch") { s, t in try await s.gomokuWatch(accessToken: t, matchID: m, sinceSeq: 12) },
            WireCall(id: "gomokuWatchLive") { s, t in try await s.gomokuWatchLive(accessToken: t, matchID: m, sinceSeq: 12) },
            // ---- 체스 ----
            WireCall(id: "chessLobby") { s, t in try await s.chessLobby(accessToken: t) },
            WireCall(id: "chessChallenge") { s, t in try await s.chessChallenge(accessToken: t, opponentID: p, stake: 5) },
            WireCall(id: "chessCancel") { s, t in try await s.chessCancel(accessToken: t, matchID: m) },
            WireCall(id: "chessRespond") { s, t in try await s.chessRespond(accessToken: t, matchID: m, accept: false) },
            WireCall(id: "chessMove") { s, t in try await s.chessMove(accessToken: t, matchID: m, expectedPly: 2, uci: "e7e8q") },
            WireCall(id: "chessMove#deadlock", responses: [WireRequestRecorder.deadlock]) { s, t in
                return try await s.chessMove(accessToken: t, matchID: m, expectedPly: 2, uci: "e2e4")
            },
            WireCall(id: "chessResign") { s, t in try await s.chessResign(accessToken: t, matchID: m) },
            WireCall(id: "chessOfferDraw") { s, t in try await s.chessOfferDraw(accessToken: t, matchID: m) },
            WireCall(id: "chessRespondDraw") { s, t in try await s.chessRespondDraw(accessToken: t, matchID: m, accept: true) },
            WireCall(id: "chessState") { s, t in try await s.chessState(accessToken: t, matchID: m, sinceSeq: 9) },
            WireCall(id: "chessRanking") { s, t in try await s.chessRanking(accessToken: t) },
            WireCall(id: "chessWatch") { s, t in try await s.chessWatch(accessToken: t, matchID: m, sinceSeq: 0) },
            WireCall(id: "chessWatchLive") { s, t in try await s.chessWatchLive(accessToken: t, matchID: m, sinceSeq: 0) },
            // ---- 테트리스 ----
            WireCall(id: "tetrisLobby") { s, t in try await s.tetrisLobby(accessToken: t) },
            WireCall(id: "tetrisChallenge") { s, t in try await s.tetrisChallenge(accessToken: t, opponentID: p, stake: 3) },
            WireCall(id: "tetrisCancel") { s, t in try await s.tetrisCancel(accessToken: t, matchID: m) },
            WireCall(id: "tetrisRespond") { s, t in try await s.tetrisRespond(accessToken: t, matchID: m, accept: true) },
            WireCall(id: "tetrisReport") { s, t in
                let report = TetrisDuelReport(seq: 12, board: String(repeating: ".", count: 200), lines: 4, garbageSent: 2,
                                              garbageApplied: 1, pending: 3, toppedOut: false)
                return try await s.tetrisReport(accessToken: t, matchID: m, report: report)
            },
            WireCall(id: "tetrisState") { s, t in try await s.tetrisState(accessToken: t, matchID: m) },
            WireCall(id: "tetrisResign") { s, t in try await s.tetrisResign(accessToken: t, matchID: m) },
            WireCall(id: "tetrisRanking") { s, t in try await s.tetrisRanking(accessToken: t) },
            WireCall(id: "tetrisWatchLive") { s, t in try await s.tetrisWatchLive(accessToken: t, matchID: m) },
            WireCall(id: "tetrisWatch") { s, t in try await s.tetrisWatch(accessToken: t, matchID: m) },
            // ---- 결과 대조(서비스 후처리 — 검증 지적: G5 가 요청만 보고 결과를 버렸다). 대본에 실제 모양의 응답을 싣는다 ----
            WireCall(id: "signIn#data", responses: [.json(#"{"access_token":"acc-1","refresh_token":"ref-1","user":{"id":"U-1"}}"#)]) { s, _ in
                try await s.signIn(email: "a@b.invalid", password: "pw-123456")
            },
            WireCall(id: "signUp#session", responses: [.json(#"{"access_token":"acc-2","refresh_token":null,"user":{"id":"U-2","identities":[{"id":"i"}]}}"#)]) { s, _ in
                try await s.signUp(email: "a@b.invalid", password: "pw-123456", displayName: "아잉")
            },
            WireCall(id: "signUp#confirm", responses: [.json(#"{"user":{"id":"U-3","identities":[{"id":"i"}]}}"#)]) { s, _ in
                try await s.signUp(email: "a@b.invalid", password: "pw-123456", displayName: "아잉")
            },
            WireCall(id: "signUp#exists", responses: [.json(#"{"user":{"id":"U-4","identities":[]}}"#)]) { s, _ in
                try await s.signUp(email: "a@b.invalid", password: "pw-123456", displayName: "아잉")
            },
            WireCall(id: "signUp#noIdentitiesKey", responses: [.json(#"{"user":{"id":"U-5"}}"#)]) { s, _ in
                try await s.signUp(email: "a@b.invalid", password: "pw-123456", displayName: "아잉")
            },
            WireCall(id: "verifySignUpCode#expired", responses: [.json(#"{"code":403,"error_code":"otp_expired","msg":"Token has expired or is invalid"}"#, status: 403)]) { s, _ in
                try await s.verifySignUpCode(email: "a@b.invalid", code: "654321")
            },
            WireCall(id: "sendPasswordResetCode#rateLimited", responses: [.json(#"{"msg":"For security purposes, you can only request this after 30 seconds."}"#, status: 429)]) { s, _ in
                try await s.sendPasswordResetCode(email: "a@b.invalid")
            },
            WireCall(id: "updatePassword#same", responses: [.json(#"{"code":422,"error_code":"same_password","msg":"New password should be different from the old password."}"#, status: 422)]) { s, t in
                try await s.updatePassword(accessToken: t, newPassword: "new-pw-1")
            },
            WireCall(id: "lookupTeamByCode#data", responses: [.json(#"[{"team_id":"T-1","name":"아잉팀","weekly_goal_hours":40,"member_count":3},{"team_id":"T-2","name":"둘","weekly_goal_hours":1,"member_count":1}]"#)]) { s, _ in
                try await s.lookupTeamByCode(code: "abc-123")
            },
            WireCall(id: "lookupTeamByCode#none", responses: [.json("[]")]) { s, _ in try await s.lookupTeamByCode(code: "abc-123") },
            WireCall(id: "fetchMyInviteCode#data", responses: [.json(#"[{"invite_code":"ABC123"}]"#)]) { s, t in try await s.fetchMyInviteCode(accessToken: t) },
            WireCall(id: "joinTeam#data", responses: [.json(#"[{"team_id":"T-1","name":"아잉팀","weekly_goal_hours":30}]"#)]) { s, t in
                try await s.joinTeam(accessToken: t, code: "xyz-789")
            },
            WireCall(id: "joinTeam#none", responses: [.json("[]")]) { s, t in try await s.joinTeam(accessToken: t, code: "xyz-789") },
            WireCall(id: "createTeam#data", responses: [.json(#"[{"team_id":"T-9","name":"새 팀","invite_code":"XYZ789","weekly_goal_hours":60}]"#)]) { s, t in
                try await s.createTeam(accessToken: t, name: "새 팀", goalHours: 60)
            },
            WireCall(id: "fetchTeamLeaderboard#data", responses: [.json(#"[{"team_id":"T-1","team_name":"아잉팀","weekly_goal_hours":40,"total_seconds":7200,"working_count":2,"member_count":null,"center":"busan","week_start":"2026-09-14","participant_count":3},{"team_id":"T-2","team_name":"둘","weekly_goal_hours":10,"total_seconds":0,"working_count":0,"member_count":4,"center":"nowhere"}]"#)]) { s, t in
                try await s.fetchTeamLeaderboard(accessToken: t)
            },
            WireCall(id: "fetchOwnMembership#data", responses: [.json(#"[{"team_id":"T-1","role":"owner","teams":{"name":"아잉팀","weekly_goal_hours":45}}]"#)]) { s, t in
                try await s.fetchOwnMembership(accessToken: t, userID: u)
            },
            WireCall(id: "fetchOwnMembership#defaults", responses: [.json(#"[{"team_id":"T-1","role":null,"teams":null}]"#)]) { s, t in
                try await s.fetchOwnMembership(accessToken: t, userID: u)
            },
            WireCall(id: "fetchOwnMembership#none", responses: [.json("[]")]) { s, t in try await s.fetchOwnMembership(accessToken: t, userID: u) },
            WireCall(id: "fetchTeamStatuses#data", unordered: true, routes: Self.teamRoutes(devices: Self.teamDevicesOK)) { s, t in
                try await s.fetchTeamStatuses(accessToken: t, teamID: "team-1", now: now)
            },
            WireCall(id: "fetchTeamStatuses#devicesFail", unordered: true, routes: Self.teamRoutes(devices: .json(#"{"message":"boom"}"#, status: 500))) { s, t in
                try await s.fetchTeamStatuses(accessToken: t, teamID: "team-1", now: now)
            },
            WireCall(id: "fetchMySessions#data", responses: [.json(#"[{"id":"S-1","user_id":"U","started_at":"2026-09-16T00:00:00Z","ended_at":"2026-09-16T01:00:00Z","duration_seconds":3600}]"#)]) { s, t in
                try await s.fetchMySessions(accessToken: t, userID: u, since: now.addingTimeInterval(-86_400))
            },
            WireCall(id: "fetchMiniGamePublic#data", responses: [.json(#"[{"minigame_public":false}]"#)]) { s, t in try await s.fetchMiniGamePublic(accessToken: t, userID: u) },
            WireCall(id: "fetchMyCenter#data", responses: [.json(#"[{"center":"busan"}]"#)]) { s, t in try await s.fetchMyCenter(accessToken: t, userID: u) },
            WireCall(id: "fetchMyStatusMessage#data", responses: [.json(#"[{"status_message":"집중"}]"#)]) { s, t in try await s.fetchMyStatusMessage(accessToken: t, userID: u) },
            WireCall(id: "fetchTokenUsageSettings#data", responses: [.json(#"[{"token_usage_public":false,"token_usage_collect":null,"focus_mode":true}]"#)]) { s, t in
                try await s.fetchTokenUsageSettings(accessToken: t, userID: u)
            },
            WireCall(id: "fetchTokenUsageSettings#none", responses: [.json("[]")]) { s, t in try await s.fetchTokenUsageSettings(accessToken: t, userID: u) },
            WireCall(id: "setDisplayName#data", responses: [.json(#"{"status":"ok","display_name":"새이름"}"#)]) { s, t in try await s.setDisplayName(accessToken: t, name: "새이름") },
            WireCall(id: "fetchDisplayNameChangedAt#data", responses: [.json(#"[{"display_name_changed_at":"2026-09-01T00:00:00.5Z"}]"#)]) { s, t in
                try await s.fetchDisplayNameChangedAt(accessToken: t, userID: u)
            },
            WireCall(id: "fetchEquippedCharacter#data", responses: [.json(#"[{"character":"robot"}]"#)]) { s, t in try await s.fetchEquippedCharacter(accessToken: t, userID: u) },
            WireCall(id: "fetchEquippedCharacter#noRow", responses: [.json("[]")]) { s, t in try await s.fetchEquippedCharacter(accessToken: t, userID: u) },
            WireCall(id: "fetchMyAILimits#data", responses: [.json(#"[{"device_id":" mac-1 ","device_label":"  ","provider":"claude","five_hour_percent":12.5,"five_hour_resets_at":"2026-09-17T06:00:00Z","weekly_percent":null,"weekly_resets_at":null,"plan_label":"Max","observed_at":"2026-09-17T05:00:00Z"},{"device_id":"","provider":"codex","observed_at":"2026-09-17T05:00:00Z"},{"device_id":"mac-2","provider":"codex","observed_at":"bad"}]"#)]) { s, t in
                try await s.fetchMyAILimits(accessToken: t, userID: u)
            },
            // 폰이 부르는 읽기(MeAILimitsStore) — I(AI 리밋 쓰기) 태그가 파일 단위라 빠져 있던 자리.
            WireCall(id: "fetchAILimitMainDeviceID", responses: [.json(#"[{"main_device_id":"  mac-1 \n"}]"#)]) { s, t in
                try await s.fetchAILimitMainDeviceID(accessToken: t, userID: u)
            },
            WireCall(id: "fetchAILimitMainDeviceID#blank", responses: [.json(#"[{"main_device_id":"   "}]"#)]) { s, t in
                try await s.fetchAILimitMainDeviceID(accessToken: t, userID: u)
            },
            WireCall(id: "fetchAILimitMainDeviceID#none", responses: [.json("[]")]) { s, t in try await s.fetchAILimitMainDeviceID(accessToken: t, userID: u) },
            WireCall(id: "fetchAILimitMainDeviceID#null", responses: [.json(#"[{"main_device_id":null}]"#)]) { s, t in
                try await s.fetchAILimitMainDeviceID(accessToken: t, userID: u)
            },
            WireCall(id: "removeAvatar#gone404", responses: [.json("", status: 404), .json("")]) { s, t in try await s.removeAvatar(accessToken: t, userID: u) },
            WireCall(id: "removeAvatar#left", responses: [.json(#"{"message":"denied"}"#, status: 403), .json("")]) { s, t in try await s.removeAvatar(accessToken: t, userID: u) },
            WireCall(id: "deleteAvatarFile#notFoundBody", responses: [.json(#"{"statusCode":"404","error":"not_found","message":"Object not found"}"#, status: 400)]) { s, t in
                await s.deleteAvatarFile(accessToken: t, userID: u)
            },
            WireCall(id: "fetchMiniGameBoard#data", responses: [.json(#"[{"user_id":"U-1","display_name":null,"avatar_url":"","best_score":120,"best_at":"2026-09-17T01:00:00.123Z","plays":null,"center":"busan"},{"user_id":"U-2","display_name":"둘","avatar_url":"https://golden.invalid/a b.png","best_score":3000000000,"best_at":"bad","plays":7,"center":"mars"}]"#)]) { s, t in
                try await s.fetchMiniGameBoard(accessToken: t, kind: .flappy)
            },
            WireCall(id: "fetchMiniGameYesterdayWinner#data", responses: [.json(#"[{"day":null,"user_id":"U-1","display_name":null,"avatar_url":"%zz","score":42,"awarded":null,"center":"seoul"}]"#)]) { s, t in
                try await s.fetchMiniGameYesterdayWinner(accessToken: t, kind: .crossy)
            },
            WireCall(id: "fetchMiniGameYesterdayWinner#none", responses: [.json("[]")]) { s, t in try await s.fetchMiniGameYesterdayWinner(accessToken: t, kind: .crossy) },
            WireCall(id: "fetchMiniGameAllTimeBoard#data", responses: [.json(#"[{"user_id":"U-1","display_name":null,"avatar_url":"","best_score":120,"best_at":"2026-09-01T00:00:00Z","day":"2026-09-01","center":"busan"},{"user_id":null,"best_score":5},{"user_id":"U-2","display_name":"둘","best_score":null},{"user_id":"U-3","display_name":"셋","avatar_url":"https://golden.invalid/x y.png","best_score":7,"best_at":"bad","center":"weird"}]"#)]) { s, t in
                try await s.fetchMiniGameAllTimeBoard(accessToken: t, kind: .crossy)
            },
            WireCall(id: "sendMessage#data", responses: [.json(#"{"status":"cooldown","retry_after_seconds":5}"#)]) { s, t in
                try await s.sendMessage(accessToken: t, to: p, body: "안녕")
            },
            WireCall(id: "fetchMessageHistory#data", responses: [.json(Self.historyRows)]) { s, t in try await s.fetchMessageHistory(accessToken: t) },
            WireCall(id: "fetchMessageHistoryWithReads#data", responses: [.json(Self.historyRows)]) { s, t in
                try await s.fetchMessageHistoryWithReads(accessToken: t, hours: 24, limit: 600)
            },
            WireCall(id: "fetchMessageHistoryWithPokes#data", responses: [.json(Self.pokeLogRows)]) { s, t in
                try await s.fetchMessageHistoryWithPokes(accessToken: t, hours: 24, limit: 500)
            },
            WireCall(id: "appCurrentNotice#error", responses: [.json("", status: 500)]) { s, _ in try await s.appCurrentNotice() },
            WireCall(id: "submitFeedback#data", responses: [.json(#""fb-9""#)]) { s, t in
                try await s.submitFeedback(accessToken: t, kind: .request, body: "기능 요청", appVersion: "1.0.14", osVersion: "17.6")
            },
            WireCall(id: "fetchFeedbackList#data", responses: [.json(#"[{"id":"fb-1","user_id":"U-1","kind":"bug","body":"버그","status":"doing","admin_note":"보는 중","admin_note_at":"2026-09-17T01:00:00Z","app_version":"1.0.14","os_version":"17.6","created_at":"2026-09-16T01:00:00.5Z","updated_at":null,"display_name":null,"avatar_url":""},{"id":"fb-2","kind":"zz","body":"?","status":"weird"},{"id":"fb-3","kind":"request","body":"!","status":null}]"#)]) { s, t in
                try await s.fetchFeedbackList(accessToken: t, status: nil, limit: 50)
            },
            WireCall(id: "replyFeedback#data", responses: [.json(#""2026-09-17T05:00:00.25Z""#)]) { s, t in
                Self.nowMarked(try await s.replyFeedback(accessToken: t, id: "fb-1", note: "답장"))
            },
            WireCall(id: "replyFeedback#garbage", responses: [.json("42")]) { s, t in Self.nowMarked(try await s.replyFeedback(accessToken: t, id: "fb-1", note: "답장")) },
            // 로그아웃은 실패를 삼킨다(`try?` — 비2xx·전송 실패 모두).
            WireCall(id: "signOut#serverError", responses: [.json(#"{"msg":"boom"}"#, status: 500)]) { s, t in await s.signOut(accessToken: t) },
            WireCall(id: "fetchFeedbackReplyLatest#data", responses: [.json(#""2026-09-16T00:00:00Z""#)]) { s, t in try await s.fetchFeedbackReplyLatest(accessToken: t) },
            WireCall(id: "fetchFeedbackOpenCount#data", responses: [.json("3")]) { s, t in try await s.fetchFeedbackOpenCount(accessToken: t) },
            WireCall(id: "fetchBlocks#data", responses: [.json(#"[{"user_id":"B-1","display_name":"","avatar_url":"https://golden.invalid/b 1.jpg","created_at":"2026-09-10T00:00:00Z","created_epoch":1789000000},{"user_id":"","display_name":"없음"},{"blocked":"B-2","blocked_at":"2026-09-11T00:00:00.5Z"},{"id":"B-3","display_name":"셋","blocked_epoch":1789100000}]"#)]) { s, t in
                try await s.fetchBlocks(accessToken: t)
            },
            WireCall(id: "fetchAppUserCharacters#data", responses: [.json(#"[{"user_id":" AA-1 ","character":"robot"},{"user_id":null,"character":"fox"},{"user_id":"bb-2","character":null},"x"]"#)]) { s, t in
                try await s.fetchAppUserCharacters(accessToken: t)
            },
            WireCall(id: "fetchAppUserCharacters#missing", responses: [WireRequestRecorder.pgrst202]) { s, t in try await s.fetchAppUserCharacters(accessToken: t) },
            WireCall(id: "fetchAppUserCharacters#plain404", responses: [.json("", status: 404)]) { s, t in try await s.fetchAppUserCharacters(accessToken: t) },
            WireCall(id: "fetchAppUserCharacters#serverError", responses: [.json("", status: 503)]) { s, t in try await s.fetchAppUserCharacters(accessToken: t) },
            WireCall(id: "fetchCharacterGiftPending#missing", responses: [WireRequestRecorder.pgrst202]) { s, t in
                try await s.fetchCharacterGiftPending(accessToken: t, protocolVersion: 4)
            },
            WireCall(id: "startPhoneWork#data", responses: [.json(#"{"status":"ok","session":{"id":"S-1","started_at":"2026-09-17T05:00:00Z","origin":"phone"},"server_now":"2026-09-17T05:05:00Z","check_after_seconds":"x","wallet":{"ruby_balance":12}}"#)]) { s, t in
                try await s.startPhoneWork(accessToken: t)
            },
            // ---- 상점 번호 깃발(C§4 #9 · INV-SupabaseWorkService-50250b14) — 맨 404(본문이 오류 문장 아님)는 되묻되 깃발을 안 세운다 ----
            WireCall(id: "fetchShopState(protocol)#html404", responses: [.json("<html>404 Not Found</html>", status: 404), .json("{}"), .json("{}")]) { s, t in
                let first = try await s.fetchShopState(accessToken: t, protocolVersion: 4)
                let second = try await s.fetchShopState(accessToken: t, protocolVersion: 4) // 깃발이 없으니 다시 새 모양
                return [first, second]
            },
            // 시계 주입: PGRST202 로 깃발(t0) → 299.999초 뒤 옛 모양 → 300초 뒤 새 모양을 다시 묻는다(5분 만료).
            WireCall(id: "fetchShopState(protocol)#recheck", responses: [WireRequestRecorder.pgrst202, .json("{}"), .json("{}"), .json("{}")], clock: shopClock) { s, t in
                let first = try await s.fetchShopState(accessToken: t, protocolVersion: 4)
                shopClock.set(secondsAfterStart: 299.999)
                let second = try await s.fetchShopState(accessToken: t, protocolVersion: 4)
                shopClock.set(secondsAfterStart: 300)
                let third = try await s.fetchShopState(accessToken: t, protocolVersion: 4)
                return [first, second, third]
            },
        ]
    }

    // ---- 결과 대조용 대본 ----

    /** 벽시계(`Date()`)로 떨어진 결과 표식 — 지금에서 60초 안이면 "$now"(골든이 실행마다 바뀌지 않게). */
    static func nowMarked(_ date: Date) -> Any { abs(date.timeIntervalSinceNow) < 60 ? "$now" : date }

    /// 팀 상태 네 GET(동시에 떠난다 — 길로 고른다). now = 2026-09-17 05:05Z(목, KST 14:05) · 주 시작 = 09-13 15:00Z · 오늘 시작 = 09-16 15:00Z.
    static func teamRoutes(devices: MobileStubResponse) -> [WireRoute] {
        [
            WireRoute(path: "/rest/v1/work_statuses", response: .json(#"[{"user_id":"u-work","status":"working","updated_at":"2026-09-17T05:00:00.123Z","last_seen_at":"2026-09-17T05:04:30Z","active_session_id":"S-OPEN","profiles":{"display_name":"일꾼","avatar_url":"https://golden.invalid/a b.jpg"}},{"user_id":"u-off","status":"off_work","updated_at":"2026-09-17T01:00:00Z","last_seen_at":null,"active_session_id":null,"profiles":{"display_name":"쉬는이","avatar_url":""}},{"user_id":"u-odd","status":"paused","updated_at":"bad-date","profiles":null}]"#)),
            WireRoute(path: "/rest/v1/work_sessions", query: ("ended_at", "is.null"), response: .json(#"[{"id":"ABCDEF00-0000-4000-8000-0000000000A1","user_id":"u-work","started_at":"2026-09-17T03:00:00Z","ended_at":null,"duration_seconds":null},{"id":"abcdef00-0000-4000-8000-0000000000a0","user_id":"u-work","started_at":"2026-09-17T02:30:00.5Z"},{"id":null,"user_id":"u-work","started_at":"2026-09-17T01:00:00Z"},{"id":"x","user_id":"u-off","started_at":"garbage"}]"#)),
            WireRoute(path: "/rest/v1/work_sessions", query: ("ended_at", "not.is.null"), response: .json(#"[{"user_id":"u-work","started_at":"2026-09-13T14:00:00Z","ended_at":"2026-09-13T16:00:00Z"},{"user_id":"u-work","started_at":"2026-09-16T14:30:00Z","ended_at":"2026-09-16T15:30:00Z"},{"user_id":"u-off","started_at":"2026-09-17T04:00:00Z","ended_at":"2026-09-17T06:00:00Z"},{"user_id":"u-off","started_at":"2026-09-10T00:00:00Z","ended_at":"2026-09-11T00:00:00Z"},{"user_id":"u-off","started_at":"bad","ended_at":"2026-09-17T00:00:00Z"},{"user_id":"u-odd","started_at":"2026-09-17T05:00:00Z","ended_at":null}]"#)),
            WireRoute(path: "/rest/v1/work_status_devices", response: devices),
        ]
    }

    static let teamDevicesOK = MobileStubResponse.json(#"[{"user_id":"u-work","device_id":"mac-1","session_id":"S-OPEN","last_seen_at":"2026-09-17T05:04:00Z","opened_session":true},{"user_id":"u-work","device_id":"phone-1","session_id":null,"last_seen_at":null}]"#)

    /// 이력 행(message_history · _with_reads 같은 대본): 본문 다듬기 · 보이는 글자 없음 버림 · 상대 없음 버림 · epoch 우선 · 이름 폴백 · 읽음 칸 갈래.
    static let historyRows = #"[{"id":"m1","body":"  안녕 ","created_at":"2026-09-17T05:00:00Z","created_epoch":1789621200,"is_mine":true,"peer_user_id":"p1","peer_display_name":"","peer_avatar_url":"","read_by_peer":true,"unread":true},{"id":"m2","body":"둘째","created_at":"2026-09-17T04:59:59.5Z","is_mine":false,"peer_user_id":"p2","peer_display_name":"친구","peer_avatar_url":"https://golden.invalid/p 2.jpg","read_by_peer":true,"unread":false},{"id":"m3","body":" \n ","created_epoch":1789621000,"peer_user_id":"p1"},{"id":"m4","body":"상대 없음","created_epoch":1789621000,"peer_user_id":""},{"id":"m5","body":"시각 없음","peer_user_id":"p1"},{"id":"m6","body":"옛 행","created_at":"2026-09-17T04:00:00Z","peer_user_id":"p3"}]"#

    /// 찌르기를 끼운 행: 같은 초의 메시지·찌르기 순서(마이크로초) · epoch 만 있는 행 · 모르는 kind · 깨진 원소 · 중복 id.
    static let pokeLogRows = #"[{"id":"m1","kind":"message","body":"  안녕 ","created_at":"2026-09-17T05:00:00.000002+00:00","created_epoch":1789621200,"is_mine":true,"peer_user_id":"p1","peer_display_name":"","peer_avatar_url":"","read_by_peer":true,"unread":true},{"id":"k1","kind":"poke","created_at":"2026-09-17T05:00:00.000001+00:00","created_epoch":1789621200,"is_mine":false,"peer_user_id":"p1","peer_display_name":"친구","peer_avatar_url":"https://golden.invalid/p 1.jpg","unread":true},{"id":"k2","kind":" ultra ","created_epoch":1789621100,"is_mine":true,"peer_user_id":"p1","unread":true},{"id":"m2","body":"둘째","created_at":"2026-09-17T04:59:59Z","is_mine":false,"peer_user_id":"p2","unread":false},{"id":"x1","kind":"sticker","body":"?","created_epoch":1789621000,"peer_user_id":"p1"},{"id":"m3","kind":"message","body":" \n ","created_epoch":1789621000,"peer_user_id":"p1"},{"id":"k3","kind":"normal","created_at":"2026-09-17T05:00:00.000001+00:00","peer_user_id":"p2","is_mine":false},"broken",{"id":"m1","kind":"message","body":"중복","created_epoch":1789621300,"peer_user_id":"p1"},{"id":"k4","kind":"poke","peer_user_id":"p1"}]"#

    /// 결과를 대조하지 않는 case(반환 타입이 다른 갈래의 규칙이다 — Kotlin 은 요청만 대조하고 결과는 그 갈래가 같은 골든 결과로 잰다).
    static let resultOtherLanes: [String: String] = [
        "setStatusMessage": "W1-c(StatusMessageSaveOutcome — rules/text)",
        "setStatusMessage(nil)": "W1-c(StatusMessageSaveOutcome — rules/text)",
        "achievementsStatus": "W1-c(AchievementStatus)", "achievementClaim": "W1-c(AchievementStatus)",
        "achievementClaim(nil)": "W1-c(AchievementStatus)", "dailyMissionClaim": "W1-c(AchievementStatus)",
        "dailyMissionClaim(nil)": "W1-c(AchievementStatus)", "weeklyWorkStatus": "W1-c(WeeklyWorkStatus)",
        "weeklyWorkClaim": "W1-c(WeeklyWorkClaim)", "weeklyWorkClaim(args)": "W1-c(WeeklyWorkClaim)",
        "sendMegaphone": "W1-c(MegaphoneSendOutcome)", "megaphoneInfo": "W1-c(MegaphoneInfo)",
        "fetchMyAILimits": "W2-c(MeAILimitsService — 라벨 정규화 AILimitDeviceLabelContract=W1-c · AILimitPlanLabelContract=I)",
        "fetchMyAILimits#data": "W2-c(MeAILimitsService — 라벨 정규화 AILimitDeviceLabelContract=W1-c · AILimitPlanLabelContract=I)",
    ]

    /// 갈래 밖 태그(**메서드 단위** — 이 골든의 case 가 아니다): H = 맥 전용 쓰기(데스크톱 근무·찌르기·울트라·토큰 업로드 — Windows
    /// 보류 §8-16), I = AI 리밋 쓰기·맥 고르개(데스크톱 토큰·리밋), admin = 운영자 신고 관리(C§9-7 기본 제외).
    /// 파일 단위로 빼면 그 파일의 **폰이 부르는 읽기**까지 빠진다(fetchAILimitMainDeviceID 가 그랬다) — 그래서 이름마다 적고,
    /// 폰 소스(CheckMobileKit · CheckMobileShared)가 부르는 이름은 태그할 수 없다(아래 단언).
    static let excludedMethods: [String: String] = [
        "startWork": "H", "stopWork": "H", "heartbeat": "H", "upsertStatusDevice": "H", "reportDeviceInput": "H",
        "closeAbandonedSessions": "H", "awaySync": "H", "makeWorkTickRequest": "H", "workTick": "H", "reopenSession": "H",
        "fetchMyOverlappingSessions": "H", "insertClosedSession": "H", "upsertTokenUsage": "H", "sendTokenScanHeartbeat": "H",
        "upsertTokenUsageDaily": "H", "fetchLegacyTokenUsageTotal": "H", "upsertLegacyTokenUsage": "H", "sendPoke": "H",
        "sendUltraPoke": "H", "buyUltra": "H", "takePokes": "H", "syncUltraWallet": "H", "updateFocusMode": "H", "updateAppVersion": "H",
        "aiLimitPercent": "I", "aiLimitRow": "I", "aiLimitClearingRow": "I", "upsertAILimits": "I", "fetchAILimitDevices": "I",
        "upsertAILimitMainDeviceID": "I",
        "fetchReportAdminList": "admin", "updateReportAdmin": "admin", "fetchReportOpenCount": "admin", "item": "admin",
    ]

    /// 폰 소스(주석을 걷은 글자)에서 `.이름(` 으로 부르는 서비스 메서드 이름.
    static func phoneCalledNames(_ names: Set<String>) throws -> Set<String> {
        var found: Set<String> = []
        for dir in ["Sources/CheckMobileKit", "Sources/CheckMobileShared"] {
            let base = WireRepo.url(dir)
            for f in try FileManager.default.subpathsOfDirectory(atPath: base.path) where f.hasSuffix(".swift") {
                let text = try String(contentsOf: base.appendingPathComponent(f), encoding: .utf8)
                let code = text.components(separatedBy: "\n").map { line -> String in
                    guard let r = line.range(of: "//") else { return line }
                    return String(line[..<r.lowerBound])
                }.joined(separator: "\n")
                for name in names where code.contains(".\(name)(") { found.insert(name) }
            }
        }
        return found
    }

    /// 요청을 보내지 않는 도우미(순수 함수 · 바탕).
    static let helpers: Set<String> = [
        "assembleTeamStatuses", "weekStart", "parseDate", "postgrestErrorCode", "normalizeInviteCode", "membership",
        "passwordRecoveryError", "retryAfterSeconds", "send", "sendNoBody", "sendData", "serviceError", "url", "duelRPC",
        "messageHistoryEntry", "messageHistoryWithPokes", "isMissingFunction",
    ]

    /// Swift 소스의 SupabaseWorkService 메서드 이름(액터 몸통 + `extension SupabaseWorkService {` 블록). (이름, 파일).
    static func allServiceMethods() throws -> [(String, String)] {
        let files = try FileManager.default.subpathsOfDirectory(atPath: WireRepo.url("Sources").path)
            .filter { $0.hasSuffix(".swift") && !$0.hasPrefix("check/") }
            .sorted()
        var out: [(String, String)] = []
        let funcRE = try NSRegularExpression(pattern: #"package (?:nonisolated )?(?:static )?func ([A-Za-z0-9_]+)\s*[<(]"#)
        for f in files {
            let rel = "Sources/" + f
            let text = try String(contentsOf: WireRepo.url(rel), encoding: .utf8)
            var blocks: [Substring] = []
            for opener in ["package actor SupabaseWorkService {", "extension SupabaseWorkService {"] {
                var search = text.startIndex
                while let r = text.range(of: opener, range: search..<text.endIndex) {
                    let end = text.range(of: "\n}", range: r.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
                    blocks.append(text[r.upperBound..<end])
                    search = end
                }
            }
            for b in blocks {
                let s = String(b)
                for match in funcRE.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                    out.append((String(s[Range(match.range(at: 1), in: s)!]), rel))
                }
            }
        }
        return out
    }

    @Test func requests() async throws {
        var cases: [GoldenJSON] = []
        for (i, call) in Self.calls.enumerated() {
            cases.append(try await WireRequestRecorder.record(call, index: i))
        }
        let ids = Set(Self.calls.map(\.id))
        #expect(ids.count == Self.calls.count, "case id 가 겹친다")

        // 빠짐 금지 — Swift 의 모든 서비스 메서드가 case · 태그 · 도우미 중 하나다.
        var excluded: [String: GoldenJSON] = [:]
        var missing: [String] = []
        let baseNames = Set(Self.calls.map { $0.id.components(separatedBy: CharacterSet(charactersIn: "(#")).first! })
        let methods = try Self.allServiceMethods()
        for (name, file) in methods {
            if let tag = Self.excludedMethods[name] {
                #expect(!baseNames.contains(name), "태그한 이름이 case 이기도 하다: \(name)")
                excluded[name] = .string(tag)
            } else if !baseNames.contains(name) && !Self.helpers.contains(name) {
                missing.append("\(name) (\(file))")
            }
        }
        #expect(missing.isEmpty, "요청 골든에 없는 서비스 메서드: \(missing)")
        let unknownTags = Set(Self.excludedMethods.keys).subtracting(methods.map(\.0))
        #expect(unknownTags.isEmpty, "서비스에 없는 태그 이름(오타·삭제): \(unknownTags.sorted())")
        // 폰이 부르는 메서드는 태그로 뺄 수 없다 — 태그는 '폰·Android 가 안 쓰는 몫'이라는 주장이다.
        let phoneTagged = try Self.phoneCalledNames(Set(Self.excludedMethods.keys))
        #expect(phoneTagged.isEmpty, "폰 소스가 부르는데 갈래 밖으로 태그한 메서드: \(phoneTagged.sorted())")
        let caseIDs = Set(Self.calls.map(\.id))
        #expect(Set(Self.resultOtherLanes.keys).subtracting(caseIDs).isEmpty, "resultOtherLanes 에 없는 case id")
        goldenEmit(GoldenFile(
            golden: "wire/requests",
            equivalence: .bit,
            swiftSources: [
                "Sources/CheckCore/SupabaseWorkService.swift", "Sources/CheckCore/SupabaseWorkHTTP.swift", "Sources/CheckCore/DuelRPC.swift",
                "Sources/CheckCore/SupabaseWorkModels.swift", "Sources/CheckCore/ChessWire.swift", "Sources/CheckCore/TetrisWire.swift",
                "Sources/CheckCore/SupabaseWorkServiceBlocks.swift", "Sources/CheckCore/SupabaseWorkServiceCharacter.swift",
                "Sources/CheckCore/SupabaseWorkServiceMessageReads.swift", "Sources/CheckCore/SupabaseWorkServiceSignUp.swift",
                "Sources/CheckCore/SupabaseWorkServiceSignUpOTP.swift", "Sources/CheckCore/SupabaseWorkServiceTodoSync.swift",
                "Sources/CheckCore/AppUserCharacters.swift", "Sources/CheckCore/CharacterGift.swift", "Sources/CheckCore/MessagePokeLog.swift",
                "Sources/CheckCore/DailyMissions.swift", "Sources/CheckCore/Achievements.swift", "Sources/CheckCore/Gacha.swift",
                "Sources/CheckCore/WeeklyWorkReward.swift", "Sources/CheckCore/Megaphone.swift", "Sources/CheckCore/TodoSync.swift",
                "Sources/CheckCore/StatusMessage.swift",
                "Sources/CheckMobileKit/Session/MobileDeviceService.swift", "Sources/CheckMobileKit/Session/MobilePhoneWorkService.swift",
                "Sources/CheckMobileKit/Session/MobileSignOutCleanup.swift", "Sources/CheckMobileKit/Me/MeProfileService.swift",
                "Sources/CheckMobileKit/Me/MeAILimitsService.swift", "Sources/CheckCore/SupabaseWorkServiceAILimits.swift",
            ],
            spec: [
                "values": .object([
                    "anonKey": .string("<ANON>"), "accessToken": .string("<ACCESS>"), "host": .string("golden.invalid"),
                    "userID": .string(WireGoldenValues.userID), "peerID": .string(WireGoldenValues.peerID),
                    "matchID": .string(WireGoldenValues.matchID), "requestID": .string(WireGoldenValues.requestID.uuidString.lowercased()),
                    "nowSince1970": .int(Int(WireGoldenValues.now.timeIntervalSince1970)),
                    "avatarCacheBuster": .string("?v=<ms>-<uuid 앞 8자> → ?v=<CACHE_BUSTER>"),
                ]),
                "request": .string("method · path · query(디코드한 [이름, 값] 쌍, 순서 그대로) · headers(apikey·authorization·accept·content-type·prefer·x-upsert 만, 소문자) · body(JSON 이면 정규 값 — 정수 글자 → 숫자, 그 밖 숫자 → {\"$num\": 글자}; 아니면 {\"$bytes\": base64}; 없으면 null)"),
                "responses": .string("이 case 의 응답 대본(차례대로, 끝나면 200 {}). unordered = 동시에 떠나는 요청이라 정규 글자 순으로 정렬해 비교"),
                "excluded": .object(excluded),
                "result": .string("서비스 반환값: {\"ok\": GoldenMirror 덤프(Void = \"$void\", nil = null, 글자 잎은 요청과 같은 자리표시)} 또는 {\"throws\": SupabaseWorkServiceError 덤프 | \"$decoding\" | {\"$type\", \"$dump\"}}"),
                "resultOtherLanes": .object(Self.resultOtherLanes.mapValues { .string($0) }),
                "routes": .string("routes 가 있으면 대본 대신 요청 모양(경로 + 디코드한 쿼리 쌍 하나)으로 응답을 고른다(처음 맞는 것, 없으면 200 {})"),
                "clock": .string("서비스 시계 = values.nowSince1970. #recheck 는 둘째 호출 전 +299.999초, 셋째 호출 전 +300초로 옮긴다"),
            ],
            cases: cases
        ))
    }
}
