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

/// 응답 대본(차례대로 쓰고, 끝나면 200 `{}`).
final class WireScript: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [MobileStubResponse]
    init(_ responses: [MobileStubResponse]) { queue = responses }
    func next() -> MobileStubResponse {
        lock.lock(); defer { lock.unlock() }
        return queue.isEmpty ? .json("{}") : queue.removeFirst()
    }
}

struct WireCall {
    let id: String
    var responses: [MobileStubResponse] = []
    /// 동시에 떠나는 요청(팀 상태 네 GET) — 순서 없는 모음으로 비교한다.
    var unordered = false
    let run: (SupabaseWorkService, String) async throws -> Void
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
        let script = WireScript(call.responses)
        MobileStubURLProtocol.register(host: host) { _ in script.next() }
        defer { MobileStubURLProtocol.unregister(host: host) }
        let service = SupabaseWorkService(
            projectURL: URL(string: "https://\(host)")!,
            anonKey: WireGoldenValues.anonKey,
            session: MobileStubURLProtocol.makeSession(),
            clock: { WireGoldenValues.now }
        )
        do { try await call.run(service, WireGoldenValues.accessToken) } catch {}
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
        let notice = MobileStubResponse.json(#"[{"weekly_goal_hours": 40}]"#)
        return [
            // ---- 인증 ----
            WireCall(id: "signIn") { s, _ in _ = try await s.signIn(email: "a@b.invalid", password: "pw-123456") },
            WireCall(id: "signUp") { s, _ in _ = try await s.signUp(email: "a@b.invalid", password: "pw-123456", displayName: "아잉") },
            WireCall(id: "signUp(center)") { s, _ in _ = try await s.signUp(email: "a@b.invalid", password: "pw", displayName: "아잉", center: "busan") },
            WireCall(id: "refreshSession") { s, _ in _ = try await s.refreshSession(refreshToken: "refresh-1") },
            WireCall(id: "signOut") { s, t in await s.signOut(accessToken: t) },
            WireCall(id: "logoutLocalScope") { s, t in try await s.logoutLocalScope(accessToken: t) },
            WireCall(id: "deleteMyAccount") { s, t in try await s.deleteMyAccount(accessToken: t) },
            WireCall(id: "sendPasswordResetCode") { s, _ in try await s.sendPasswordResetCode(email: "a@b.invalid") },
            WireCall(id: "verifyPasswordResetCode") { s, _ in _ = try await s.verifyPasswordResetCode(email: "a@b.invalid", code: "123456") },
            WireCall(id: "updatePassword") { s, t in try await s.updatePassword(accessToken: t, newPassword: "new-pw-1") },
            WireCall(id: "verifySignUpCode") { s, _ in _ = try await s.verifySignUpCode(email: "a@b.invalid", code: "654321") },
            WireCall(id: "resendSignUpCode") { s, _ in try await s.resendSignUpCode(email: "a@b.invalid") },
            // ---- 팀 ----
            WireCall(id: "lookupTeamByCode") { s, _ in _ = try await s.lookupTeamByCode(code: " ab-c 12 ") },
            WireCall(id: "fetchMyInviteCode") { s, t in _ = try await s.fetchMyInviteCode(accessToken: t) },
            WireCall(id: "setTeamWeeklyGoal", responses: [notice]) { s, t in _ = try await s.setTeamWeeklyGoal(accessToken: t, goalHours: 40) },
            WireCall(id: "joinTeam") { s, t in _ = try await s.joinTeam(accessToken: t, code: "xyz-789") },
            WireCall(id: "createTeam") { s, t in _ = try await s.createTeam(accessToken: t, name: "새 팀", goalHours: 60) },
            WireCall(id: "fetchTeamLeaderboard") { s, t in _ = try await s.fetchTeamLeaderboard(accessToken: t) },
            WireCall(id: "fetchTeamLeaderboard(weekOffset)") { s, t in _ = try await s.fetchTeamLeaderboard(accessToken: t, weekOffset: 3) },
            WireCall(id: "fetchTeamLeaderboard(weekOffset)#clamp") { s, t in _ = try await s.fetchTeamLeaderboard(accessToken: t, weekOffset: 99) },
            WireCall(id: "fetchTeamLeaderboard(weekOffset)#fallback", responses: [WireRequestRecorder.pgrst202, .json("[]")]) { s, t in
                _ = try await s.fetchTeamLeaderboard(accessToken: t, weekOffset: 2)
            },
            WireCall(id: "fetchOwnMembership") { s, t in _ = try await s.fetchOwnMembership(accessToken: t, userID: u) },
            WireCall(id: "fetchTeamStatuses", unordered: true) { s, t in _ = try await s.fetchTeamStatuses(accessToken: t, teamID: "team-1", now: now) },
            // ---- 기록 · 토큰 · 프로필 ----
            WireCall(id: "fetchMySessions") { s, t in _ = try await s.fetchMySessions(accessToken: t, userID: u, since: now.addingTimeInterval(-86_400 * 30)) },
            WireCall(id: "fetchMyTokenDaily") { s, t in _ = try await s.fetchMyTokenDaily(accessToken: t, userID: u, since: "2026-08-01") },
            WireCall(id: "fetchTokenBoard") { s, t in _ = try await s.fetchTokenBoard(accessToken: t, month: "2026-09") },
            WireCall(id: "fetchMiniGamePublic") { s, t in _ = try await s.fetchMiniGamePublic(accessToken: t, userID: u) },
            WireCall(id: "updateMiniGamePublic") { s, t in try await s.updateMiniGamePublic(accessToken: t, userID: u, isPublic: false) },
            WireCall(id: "fetchMyCenter") { s, t in _ = try await s.fetchMyCenter(accessToken: t, userID: u) },
            WireCall(id: "fetchMyStatusMessage") { s, t in _ = try await s.fetchMyStatusMessage(accessToken: t, userID: u) },
            WireCall(id: "setStatusMessage") { s, t in _ = try await s.setStatusMessage(accessToken: t, text: "집중 중") },
            WireCall(id: "setStatusMessage(nil)") { s, t in _ = try await s.setStatusMessage(accessToken: t, text: nil) },
            WireCall(id: "fetchTokenUsageSettings") { s, t in _ = try await s.fetchTokenUsageSettings(accessToken: t, userID: u) },
            WireCall(id: "updateTokenUsagePublic") { s, t in try await s.updateTokenUsagePublic(accessToken: t, userID: u, isPublic: true) },
            WireCall(id: "setDisplayName") { s, t in _ = try await s.setDisplayName(accessToken: t, name: "새이름") },
            WireCall(id: "fetchDisplayNameChangedAt") { s, t in _ = try await s.fetchDisplayNameChangedAt(accessToken: t, userID: u) },
            WireCall(id: "setCharacter") { s, t in _ = try await s.setCharacter(accessToken: t, id: "aing_cake_choco") },
            WireCall(id: "setCharacter(nil)") { s, t in _ = try await s.setCharacter(accessToken: t, id: nil) },
            WireCall(id: "fetchEquippedCharacter") { s, t in _ = try await s.fetchEquippedCharacter(accessToken: t, userID: u) },
            WireCall(id: "fetchMyProfileCard") { s, t in _ = try await s.fetchMyProfileCard(accessToken: t, userID: u) },
            WireCall(id: "fetchMyAILimits") { s, t in _ = try await s.fetchMyAILimits(accessToken: t, userID: u) },
            // ---- 사진 ----
            WireCall(id: "uploadAvatar") { s, t in _ = try await s.uploadAvatar(accessToken: t, userID: u, imageData: Data("JPEG-BYTES".utf8)) },
            WireCall(id: "removeAvatar") { s, t in _ = try await s.removeAvatar(accessToken: t, userID: u) },
            WireCall(id: "deleteAvatarFile") { s, t in _ = await s.deleteAvatarFile(accessToken: t, userID: u) },
            WireCall(id: "deleteAvatarIfAny") { s, t in await s.deleteAvatarIfAny(accessToken: t, userID: u) },
            // ---- 미니게임 ----
            WireCall(id: "startMiniGameRound") { s, t in _ = try await s.startMiniGameRound(accessToken: t, kind: .flappy) },
            WireCall(id: "submitMiniGameScore") { s, t in _ = try await s.submitMiniGameScore(accessToken: t, kind: .tetris, score: 3_000_000_000, token: "tok") },
            WireCall(id: "fetchMiniGameBoard") { s, t in _ = try await s.fetchMiniGameBoard(accessToken: t, kind: .timingBar) },
            WireCall(id: "fetchMiniGameBoard(day)") { s, t in _ = try await s.fetchMiniGameBoard(accessToken: t, kind: .crossy, day: "2026-09-16") },
            WireCall(id: "fetchMiniGameYesterdayWinner") { s, t in _ = try await s.fetchMiniGameYesterdayWinner(accessToken: t, kind: .flappy) },
            WireCall(id: "fetchMiniGameAllTimeBoard") { s, t in _ = try await s.fetchMiniGameAllTimeBoard(accessToken: t, kind: .crossy) },
            // ---- 상점(C§4 #9) ----
            WireCall(id: "fetchShopState") { s, t in _ = try await s.fetchShopState(accessToken: t) },
            WireCall(id: "fetchShopState(protocol)") { s, t in _ = try await s.fetchShopState(accessToken: t, protocolVersion: 4) },
            WireCall(id: "fetchShopState(protocol)#fallback", responses: [WireRequestRecorder.pgrst202, .json("{}"), .json("{}")]) { s, t in
                _ = try await s.fetchShopState(accessToken: t, protocolVersion: 4)
                _ = try await s.fetchShopState(accessToken: t, protocolVersion: 4) // 깃발 5분 — 바로 옛 모양
            },
            WireCall(id: "fetchShopState(protocol)#plain404", responses: [.json(#"{"message":"nope"}"#, status: 404), .json("{}"), .json("{}")]) { s, t in
                _ = try await s.fetchShopState(accessToken: t, protocolVersion: 4)
                _ = try await s.fetchShopState(accessToken: t, protocolVersion: 4) // 맨 404 는 깃발을 안 세운다 — 다시 새 모양
            },
            WireCall(id: "buyCharacter") { s, t in _ = try await s.buyCharacter(accessToken: t, id: "robot") },
            WireCall(id: "buyCharacter(protocol)") { s, t in _ = try await s.buyCharacter(accessToken: t, id: "robot", protocolVersion: 3) },
            WireCall(id: "buyCharacter(protocol)#fallback", responses: [WireRequestRecorder.pgrst202, .json(#"{"status":"ok"}"#)]) { s, t in
                _ = try await s.buyCharacter(accessToken: t, id: "fox", protocolVersion: 3)
            },
            // ---- 메시지 ----
            WireCall(id: "sendMessage") { s, t in _ = try await s.sendMessage(accessToken: t, to: p, body: "  안녕하세요\n") },
            WireCall(id: "sendMessage#empty") { s, t in _ = try await s.sendMessage(accessToken: t, to: p, body: " \n ") },
            WireCall(id: "sendMessage#tooLong") { s, t in _ = try await s.sendMessage(accessToken: t, to: p, body: String(repeating: "가", count: 201)) },
            WireCall(id: "fetchMessageHistory") { s, t in _ = try await s.fetchMessageHistory(accessToken: t) },
            WireCall(id: "fetchMessageHistory#clamp") { s, t in _ = try await s.fetchMessageHistory(accessToken: t, hours: 99, limit: 0) },
            WireCall(id: "fetchPokeDirectory") { s, t in _ = try await s.fetchPokeDirectory(accessToken: t) },
            WireCall(id: "fetchMessageHistoryWithReads") { s, t in _ = try await s.fetchMessageHistoryWithReads(accessToken: t, hours: 24, limit: 600) },
            WireCall(id: "fetchMessageUnreadSummary") { s, t in _ = try await s.fetchMessageUnreadSummary(accessToken: t) },
            WireCall(id: "markMessagesRead") { s, t in _ = try await s.markMessagesRead(accessToken: t, peerUserID: p, throughMessageID: "msg-9") },
            WireCall(id: "markMessagesRead(nil)") { s, t in _ = try await s.markMessagesRead(accessToken: t, peerUserID: p, throughMessageID: nil) },
            WireCall(id: "fetchMessageHistoryWithPokes") { s, t in _ = try await s.fetchMessageHistoryWithPokes(accessToken: t, hours: 0, limit: 50) },
            WireCall(id: "markConversationRead") { s, t in _ = try await s.markConversationRead(accessToken: t, peerUserID: p, throughMessageID: "msg-9", throughPokeID: "poke-3") },
            WireCall(id: "markConversationRead(nil)") { s, t in _ = try await s.markConversationRead(accessToken: t, peerUserID: p, throughMessageID: nil, throughPokeID: nil) },
            // ---- 릴리스 · 공지 ----
            WireCall(id: "fetchLatestRelease") { s, _ in _ = try await s.fetchLatestRelease() },
            WireCall(id: "appCurrentNotice") { s, _ in _ = try await s.appCurrentNotice() },
            // ---- 제보 ----
            WireCall(id: "submitFeedback") { s, t in _ = try await s.submitFeedback(accessToken: t, kind: .bug, body: "버튼이 안 눌려요", appVersion: "1.0.14", osVersion: "17.6") },
            WireCall(id: "fetchFeedbackList") { s, t in _ = try await s.fetchFeedbackList(accessToken: t, status: nil, limit: 50) },
            WireCall(id: "fetchFeedbackList(status)") { s, t in _ = try await s.fetchFeedbackList(accessToken: t, status: .inProgress, limit: 20) },
            WireCall(id: "setFeedbackStatus") { s, t in try await s.setFeedbackStatus(accessToken: t, id: "fb-1", status: .held, note: nil) },
            WireCall(id: "setFeedbackStatus(note)") { s, t in try await s.setFeedbackStatus(accessToken: t, id: "fb-1", status: .done, note: "고쳤어요") },
            WireCall(id: "replyFeedback") { s, t in _ = try await s.replyFeedback(accessToken: t, id: "fb-1", note: "답장") },
            WireCall(id: "fetchFeedbackReplyLatest") { s, t in _ = try await s.fetchFeedbackReplyLatest(accessToken: t) },
            WireCall(id: "fetchFeedbackOpenCount") { s, t in _ = try await s.fetchFeedbackOpenCount(accessToken: t) },
            // ---- 차단 · 신고 ----
            WireCall(id: "blockUser") { s, t in try await s.blockUser(accessToken: t, userID: p) },
            WireCall(id: "unblockUser") { s, t in try await s.unblockUser(accessToken: t, userID: p) },
            WireCall(id: "fetchBlocks") { s, t in _ = try await s.fetchBlocks(accessToken: t) },
            WireCall(id: "reportContent") { s, t in try await s.reportContent(accessToken: t, targetUserID: p, reason: .harassment, detail: "욕설", messageID: "msg-1", alsoBlock: true) },
            WireCall(id: "reportContent#empty") { s, t in try await s.reportContent(accessToken: t, targetUserID: p, reason: .spam, detail: "", messageID: nil, alsoBlock: false) },
            // ---- 캐릭터 · 선물 · 뽑기 ----
            WireCall(id: "fetchAppUserCharacters") { s, t in _ = try await s.fetchAppUserCharacters(accessToken: t) },
            WireCall(id: "fetchCharacterGiftPending") { s, t in _ = try await s.fetchCharacterGiftPending(accessToken: t, protocolVersion: 4) },
            WireCall(id: "claimCharacterGift") { s, t in _ = try await s.claimCharacterGift(accessToken: t, giftID: "gift-1", characterID: "aing_cake_strawberry", protocolVersion: 4) },
            WireCall(id: "gachaPull") { s, t in _ = try await s.gachaPull(accessToken: t, protocolVersion: 4, requestID: rid) },
            WireCall(id: "gachaExchange") { s, t in _ = try await s.gachaExchange(accessToken: t, characterID: "aing_rainbow", protocolVersion: 4, requestID: rid) },
            // ---- 할 일(p_since_ms 는 null 이어도 싣는다 — C§4 #10) ----
            WireCall(id: "todoSync") { s, t in
                _ = try await s.todoSync(accessToken: t, request: TodoSyncRequest(changes: [], sinceMs: nil))
            },
            WireCall(id: "todoSync(changes)") { s, t in
                let item = TodoSyncWireItem(id: "0000000a-0000-4000-8000-00000000000a", title: "할 일", createdAtMs: 1_726_500_000_000,
                                            updatedAtMs: 1_726_500_005_000, completedAtMs: nil, deletedAtMs: nil, originDayKey: "20240917")
                _ = try await s.todoSync(accessToken: t, request: TodoSyncRequest(changes: [item], sinceMs: 1_726_400_000_000))
            },
            // ---- W1-c 응답 타입(요청 모양은 W1-d) ----
            WireCall(id: "achievementsStatus") { s, t in _ = try await s.achievementsStatus(accessToken: t) },
            WireCall(id: "achievementClaim") { s, t in _ = try await s.achievementClaim(accessToken: t, key: "poke10") },
            WireCall(id: "achievementClaim(nil)") { s, t in _ = try await s.achievementClaim(accessToken: t, key: nil) },
            WireCall(id: "dailyMissionClaim") { s, t in _ = try await s.dailyMissionClaim(accessToken: t, key: "daily_gomoku") },
            WireCall(id: "dailyMissionClaim(nil)") { s, t in _ = try await s.dailyMissionClaim(accessToken: t, key: nil) },
            WireCall(id: "weeklyWorkStatus") { s, t in _ = try await s.weeklyWorkStatus(accessToken: t) },
            WireCall(id: "weeklyWorkClaim") { s, t in _ = try await s.weeklyWorkClaim(accessToken: t) },
            WireCall(id: "weeklyWorkClaim(args)") { s, t in _ = try await s.weeklyWorkClaim(accessToken: t, weekStart: "2026-09-14", hours: 40) },
            WireCall(id: "sendMegaphone") { s, t in _ = try await s.sendMegaphone(accessToken: t, body: "다들 화이팅", requestID: "dd000000-0000-4000-8000-0000000000d4") },
            WireCall(id: "megaphoneInfo") { s, t in _ = try await s.megaphoneInfo(accessToken: t) },
            // ---- 기기 · 폰 근무 ----
            WireCall(id: "fetchClientRelease") { s, _ in _ = try await s.fetchClientRelease() },
            WireCall(id: "registerDevice") { s, t in
                _ = try await s.registerDevice(accessToken: t, installationID: "11111111-2222-4333-8444-555555555555", appBuild: 2_147_483_648,
                                               appVersion: "1.0.14", apnsToken: "tok", apnsEnvironment: "production")
            },
            WireCall(id: "registerDevice#tokenOnly") { s, t in
                _ = try await s.registerDevice(accessToken: t, installationID: "i", appBuild: 7, appVersion: nil, apnsToken: "tok", apnsEnvironment: nil)
            },
            WireCall(id: "unregisterDevice") { s, t in _ = try await s.unregisterDevice(accessToken: t, installationID: "i") },
            WireCall(id: "setPushPrefs") { s, t in _ = try await s.setPushPrefs(accessToken: t, installationID: "i", prefs: PushPrefs(message: false)) },
            WireCall(id: "startPhoneWork") { s, t in _ = try await s.startPhoneWork(accessToken: t) },
            WireCall(id: "stopPhoneWork") { s, t in _ = try await s.stopPhoneWork(accessToken: t, sessionID: "ABCDEF00-0000-4000-8000-000000000001") },
            WireCall(id: "stopPhoneWork(nil)") { s, t in _ = try await s.stopPhoneWork(accessToken: t, sessionID: nil) },
            WireCall(id: "touchPhoneWork") { s, t in _ = try await s.touchPhoneWork(accessToken: t) },
            // ---- 오목 ----
            WireCall(id: "gomokuLobby") { s, t in _ = try await s.gomokuLobby(accessToken: t) },
            WireCall(id: "gomokuChallenge") { s, t in _ = try await s.gomokuChallenge(accessToken: t, opponentID: p, stake: 10) },
            WireCall(id: "gomokuCancel") { s, t in _ = try await s.gomokuCancel(accessToken: t, matchID: m) },
            WireCall(id: "gomokuRespond") { s, t in _ = try await s.gomokuRespond(accessToken: t, matchID: m, accept: true) },
            WireCall(id: "gomokuMove") { s, t in _ = try await s.gomokuMove(accessToken: t, matchID: m, expectedSeq: 4, x: 7, y: 8) },
            WireCall(id: "gomokuMove#deadlock", responses: [WireRequestRecorder.deadlock, WireRequestRecorder.deadlock]) { s, t in
                _ = try await s.gomokuMove(accessToken: t, matchID: m, expectedSeq: 4, x: 7, y: 8)
            },
            WireCall(id: "gomokuResign") { s, t in _ = try await s.gomokuResign(accessToken: t, matchID: m) },
            WireCall(id: "gomokuState") { s, t in _ = try await s.gomokuState(accessToken: t, matchID: m, sinceSeq: 3, sinceChatSeq: 1) },
            WireCall(id: "gomokuState#deadlock", responses: [WireRequestRecorder.deadlock]) { s, t in
                _ = try await s.gomokuState(accessToken: t, matchID: m, sinceSeq: 0, sinceChatSeq: 0)
            },
            WireCall(id: "gomokuInbox") { s, t in _ = try await s.gomokuInbox(accessToken: t) },
            WireCall(id: "gomokuChatSend") { s, t in _ = try await s.gomokuChatSend(accessToken: t, matchID: m, kind: .quick, body: "잘 부탁해요") },
            WireCall(id: "gomokuLeave") { s, t in _ = try await s.gomokuLeave(accessToken: t, matchID: m) },
            WireCall(id: "gomokuChatMute") { s, t in _ = try await s.gomokuChatMute(accessToken: t, matchID: m, muted: true) },
            WireCall(id: "gomokuRanking") { s, t in _ = try await s.gomokuRanking(accessToken: t) },
            WireCall(id: "gomokuWatch") { s, t in _ = try await s.gomokuWatch(accessToken: t, matchID: m, sinceSeq: 12) },
            WireCall(id: "gomokuWatchLive") { s, t in _ = try await s.gomokuWatchLive(accessToken: t, matchID: m, sinceSeq: 12) },
            // ---- 체스 ----
            WireCall(id: "chessLobby") { s, t in _ = try await s.chessLobby(accessToken: t) },
            WireCall(id: "chessChallenge") { s, t in _ = try await s.chessChallenge(accessToken: t, opponentID: p, stake: 5) },
            WireCall(id: "chessCancel") { s, t in _ = try await s.chessCancel(accessToken: t, matchID: m) },
            WireCall(id: "chessRespond") { s, t in _ = try await s.chessRespond(accessToken: t, matchID: m, accept: false) },
            WireCall(id: "chessMove") { s, t in _ = try await s.chessMove(accessToken: t, matchID: m, expectedPly: 2, uci: "e7e8q") },
            WireCall(id: "chessMove#deadlock", responses: [WireRequestRecorder.deadlock]) { s, t in
                _ = try await s.chessMove(accessToken: t, matchID: m, expectedPly: 2, uci: "e2e4")
            },
            WireCall(id: "chessResign") { s, t in _ = try await s.chessResign(accessToken: t, matchID: m) },
            WireCall(id: "chessOfferDraw") { s, t in _ = try await s.chessOfferDraw(accessToken: t, matchID: m) },
            WireCall(id: "chessRespondDraw") { s, t in _ = try await s.chessRespondDraw(accessToken: t, matchID: m, accept: true) },
            WireCall(id: "chessState") { s, t in _ = try await s.chessState(accessToken: t, matchID: m, sinceSeq: 9) },
            WireCall(id: "chessRanking") { s, t in _ = try await s.chessRanking(accessToken: t) },
            WireCall(id: "chessWatch") { s, t in _ = try await s.chessWatch(accessToken: t, matchID: m, sinceSeq: 0) },
            WireCall(id: "chessWatchLive") { s, t in _ = try await s.chessWatchLive(accessToken: t, matchID: m, sinceSeq: 0) },
            // ---- 테트리스 ----
            WireCall(id: "tetrisLobby") { s, t in _ = try await s.tetrisLobby(accessToken: t) },
            WireCall(id: "tetrisChallenge") { s, t in _ = try await s.tetrisChallenge(accessToken: t, opponentID: p, stake: 3) },
            WireCall(id: "tetrisCancel") { s, t in _ = try await s.tetrisCancel(accessToken: t, matchID: m) },
            WireCall(id: "tetrisRespond") { s, t in _ = try await s.tetrisRespond(accessToken: t, matchID: m, accept: true) },
            WireCall(id: "tetrisReport") { s, t in
                let report = TetrisDuelReport(seq: 12, board: String(repeating: ".", count: 200), lines: 4, garbageSent: 2,
                                              garbageApplied: 1, pending: 3, toppedOut: false)
                _ = try await s.tetrisReport(accessToken: t, matchID: m, report: report)
            },
            WireCall(id: "tetrisState") { s, t in _ = try await s.tetrisState(accessToken: t, matchID: m) },
            WireCall(id: "tetrisResign") { s, t in _ = try await s.tetrisResign(accessToken: t, matchID: m) },
            WireCall(id: "tetrisRanking") { s, t in _ = try await s.tetrisRanking(accessToken: t) },
            WireCall(id: "tetrisWatchLive") { s, t in _ = try await s.tetrisWatchLive(accessToken: t, matchID: m) },
            WireCall(id: "tetrisWatch") { s, t in _ = try await s.tetrisWatch(accessToken: t, matchID: m) },
        ]
    }

    /// 갈래 밖 태그(이 골든의 case 가 아니다): H = 맥 전용 쓰기(데스크톱 근무·찌르기·울트라·토큰 업로드 — Windows 보류 §8-16),
    /// I = AI 리밋 쓰기(데스크톱 토큰·리밋), admin = 운영자 신고·제보 관리(C§9-7 기본 제외).
    static let excludedFiles: [String: String] = [
        "Sources/CheckCore/SupabaseWorkServiceMacOnly.swift": "H",
        "Sources/CheckCore/SupabaseWorkServiceAILimits.swift": "I",
        "Sources/CheckCore/SupabaseWorkServiceReportAdmin.swift": "admin",
    ]

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
        for (name, file) in try Self.allServiceMethods() {
            if let tag = Self.excludedFiles[file] {
                excluded[name] = .string(tag)
            } else if !baseNames.contains(name) && !Self.helpers.contains(name) {
                missing.append("\(name) (\(file))")
            }
        }
        #expect(missing.isEmpty, "요청 골든에 없는 서비스 메서드: \(missing)")
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
                "Sources/CheckMobileKit/Me/MeAILimitsService.swift",
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
            ],
            cases: cases
        ))
    }
}
