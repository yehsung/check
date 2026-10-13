import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.50 — 1:1 오목: **끝난 판에서 나가기** · **끝인사(끝난 뒤 채팅)** 계약.
//
// 신고(2026-10-13) 둘을 지킨다.
//  ① "게임이 끝나고 [로비로] 를 안 누르면 계속 그 방에 머문다" — 결과 화면인 채로 창을 닫아도 끝난 판이 남아,
//     다음에 창을 열면 로비가 아니라 그 결과가 다시 섰다. 닫기(`windowDidClose`)는 끝난 판을 내린다.
//     최소화(`windowDidHide`)는 남긴다. 진행 중인 판은 어느 쪽도 건드리지 않는다(닫기는 기권이 아니다).
//  ② "게임이 종료되면 채팅을 보내도 전달이 안 된다" — 서버는 끝난 뒤 120초 동안 말을 받고 상대를 두드리는데,
//     받는 쪽이 끝난 판에서는 초인종에 받은함만 읽었다. 결과 화면에 서 있는 동안은 그 판도 읽는다(초인종 · 따라잡기 ·
//     끝난 뒤 130초 동안의 안전망 폴링).
//
// 관례는 V0328GomokuChatStoreTests 그대로다(호스트별 스텁 · 재개 횟수 대기 · WorkTimerStore 보관 · `.gomokuDefaultsCleanup`).
// 스텁이 못 재는 것(실제 초인종 배달 · 서버의 120초 판정)은 두 계정 e2e 몫이다.

// MARK: - 픽스처

private let geMe = "00000000-0000-0000-0000-0000000000a1"
private let geRival = "00000000-0000-0000-0000-0000000000b2"
private let geMatchID = "eeeeeeee-0350-4000-8000-00000000e001"
private let geOtherMatchID = "eeeeeeee-0350-4000-8000-00000000e002"

private func geText(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func geReply(_ object: [String: Any]) -> GomokuStubProtocol.Reply {
    GomokuStubProtocol.Reply(body: geText(object))
}

/// 서버 `chat[]` 한 줄(상대가 보낸 것).
private func geChat(_ seq: Int, _ body: String, mine: Bool = false) -> [String: Any] {
    ["seq": seq, "kind": "text", "body": body, "mine": mine, "created_ms": 1_800_000_000_000.0]
}

/// gomoku_state 의 ok 묶음. 수는 한 건도 없는 판이다(끝난 사유는 기권) — 여기서 재는 것은 판이 아니라 나가기와 대화다.
private func geState(
    id: String = geMatchID, finished: Bool, chat: [[String: Any]]? = nil, chatSeq: Int? = nil,
    finishedMs: Double? = nil, serverNowMs: Double? = nil
) -> [String: Any] {
    var payload: [String: Any] = [
        "status": "ok",
        "match": [
            "id": id,
            "status": finished ? "finished" : "active",
            "stake": 5,
            "black": geMe,
            "white": geRival,
            "challenger": geRival,
            "opponent": geMe,
            "move_count": 0,
            "turn": finished ? NSNull() : "black" as Any,
            "deadline_ms": NSNull(),
            "result": finished ? "white_win" as Any : NSNull(),
            "end_reason": finished ? "resign" as Any : NSNull(),
            "winner": NSNull(),
            "invite_expires_ms": NSNull(),
            "finished_ms": finishedMs.map { $0 as Any } ?? NSNull()
        ],
        "moves": [],
        "my_color": "black",
        "opponent": ["user_id": geRival, "display_name": "라이벌", "avatar_url": NSNull(), "character": "aing"],
        "ruby_balance": NSNull(),
        "server_now_ms": serverNowMs.map { $0 as Any } ?? NSNull()
    ]
    if let chat { payload["chat"] = chat }
    if let chatSeq { payload["chat_seq"] = chatSeq }
    return payload
}

private func geDecode(_ object: [String: Any]) -> GomokuStatePayload {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(GomokuStatePayload.self, from: Data(geText(object).utf8))
}

private func geInbox() -> [String: Any] { ["status": "ok", "incoming": [], "outgoing": NSNull()] }
private func geLobby() -> [String: Any] { ["status": "ok", "users": []] }

/// 오목 스토어는 WorkTimerStore 를 **약참조**한다 — 버리면 곧바로 해제되어 요청이 한 건도 안 나간다.
@MainActor
private enum GERetention {
    static var stores: [WorkTimerStore] = []
}

@MainActor
private func geStore(
    _ label: String, handler: @escaping GomokuStubProtocol.Handler = { _, _, _ in nil }
) -> (WorkTimerStore, GomokuStore, String) {
    let host = "v0350-ge-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let store = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0350-gomoku-exit"), workspaceNotifications: nil)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: geMe)
    GERetention.stores.append(store)
    let gomoku = store.gomoku
    // 실루프를 재우고 `pollTick(at:)` 을 직접 밟는다.
    gomoku.pollStepSeconds = 3_600
    return (store, gomoku, host)
}

/// 상한은 벽시계가 아니라 **재개 횟수**다(전체 스위트에서는 렌더 테스트가 메인 액터를 수십 초씩 쥔다).
@MainActor
private func geWait(_ resumes: Int = 4_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private final class GEClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

private func geCount(_ host: String, _ rpc: String) -> Int { GomokuStubProtocol.count(host: host, rpc: rpc) }

/// 끝인사가 오가는 서버: 첫 조회엔 상대의 첫 줄, 그 뒤로는 둘째 줄만(받은 번호 뒤).
private let geFarewellHandler: GomokuStubProtocol.Handler = { rpc, _, index in
    switch rpc {
    case "gomoku_state":
        return index == 0
            ? geReply(geState(finished: true, chat: [geChat(1, "수고하셨어요")], chatSeq: 1))
            : geReply(geState(finished: true, chat: [geChat(2, "한 판 더 해요")], chatSeq: 2))
    case "gomoku_inbox": return geReply(geInbox())
    case "gomoku_lobby": return geReply(geLobby())
    case "gomoku_leave": return geReply(["status": "ok", "both_left": false, "chat_deleted": 0])
    default: return nil
    }
}

@Suite("0.3.50 오목 — 끝난 판 나가기 · 끝인사")
struct V0350GomokuExitChatTests {

    // MARK: - ② 끝인사: 초인종

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aDoorbellOnTheResultScreenFetchesTheOpponentsFarewell() async throws {
        // 없으면: 끝난 판에서 온 초인종은 받은함만 읽어, 상대가 끝난 뒤 보낸 말이 받는 쪽 화면에 영영 안 뜬다
        //        (보낸 사람은 제 줄을 보므로 "보냈는데 전달이 안 된다"가 된다 — 신고 그대로).
        let (_, gomoku, host) = geStore("farewell", handler: geFarewellHandler)
        gomoku.applyState(geDecode(geState(finished: true, chat: [], chatSeq: 0)))
        #expect(gomoku.phase == .result)
        #expect(gomoku.chat.isEmpty)
        #expect(geCount(host, "gomoku_state") == 0, "결과 화면을 세우는 것만으로 판을 다시 읽었다")

        gomoku.handleSignal()
        await geWait { gomoku.chat.count == 1 && gomoku.syncTask == nil }

        #expect(gomoku.chat.map(\.body) == ["수고하셨어요"], "끝난 판의 초인종이 상대의 끝인사를 안 읽어 왔다")
        #expect(gomoku.chat.first?.isMine == false)
        #expect(geCount(host, "gomoku_state") == 1, "초인종 한 번에 판 조회는 한 번이다")
        #expect(geCount(host, "gomoku_inbox") == 1, "끝난 판이어도 초인종은 새 신청일 수 있다 — 받은함도 읽는다")
        let first = try #require(GomokuStubProtocol.calls(host: host, rpc: "gomoku_state").first?.json)
        #expect(first["p_match_id"] as? String == geMatchID)
        #expect(first["p_since_chat_seq"] as? Int == 0)
        // 결과 화면은 그대로다 — 같은 끝난 판을 다시 읽는다고 화면이 바뀌면 안 된다.
        #expect(gomoku.phase == .result && gomoku.match?.isFinished == true && gomoku.match?.id == geMatchID)

        // 둘째 초인종: **받은 번호 뒤만** 묻고, 온 줄이 뒤에 붙는다.
        gomoku.handleSignal()
        await geWait { gomoku.chat.count == 2 && gomoku.syncTask == nil }
        #expect(gomoku.chat.map(\.body) == ["수고하셨어요", "한 판 더 해요"])
        let second = try #require(GomokuStubProtocol.calls(host: host, rpc: "gomoku_state").last?.json)
        #expect(second["p_since_chat_seq"] as? Int == 1, "끝난 판의 대화를 매번 처음부터 다시 받는다")
        #expect(geCount(host, "gomoku_state") == 2)
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func catchingUpAfterAReconnectAlsoReadsTheFinishedMatch() async {
        // 없으면: 소켓이 끊겨 있던 동안 온 끝인사는 초인종이 없어 다시 붙은 뒤에도 안 보인다.
        let (_, gomoku, host) = geStore("catch-up", handler: geFarewellHandler)
        gomoku.applyState(geDecode(geState(finished: true, chat: [], chatSeq: 0)))

        await gomoku.catchUp()

        #expect(gomoku.chat.map(\.body) == ["수고하셨어요"])
        #expect(geCount(host, "gomoku_state") == 1)
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func afterLeavingForTheLobbyADoorbellNoLongerReadsThatMatch() async {
        // 없으면: [로비로] 로 나간 판을 초인종마다 계속 읽는다(무료 플랜 예산) — 그리고 그 대화는 이미 끝났다.
        let (_, gomoku, host) = geStore("left", handler: geFarewellHandler)
        gomoku.applyState(geDecode(geState(finished: true, chat: [], chatSeq: 0)))
        gomoku.backToLobby()
        #expect(gomoku.phase == .lobby && gomoku.match == nil)
        await geWait { geCount(host, "gomoku_inbox") >= 1 }
        let inboxBefore = geCount(host, "gomoku_inbox")

        gomoku.handleSignal()
        await geWait { geCount(host, "gomoku_inbox") > inboxBefore && gomoku.syncTask == nil }

        #expect(geCount(host, "gomoku_inbox") > inboxBefore, "로비의 초인종이 받은함을 안 읽었다")
        #expect(geCount(host, "gomoku_state") == 0, "나간 판을 초인종에 다시 읽었다")
        #expect(gomoku.chat.isEmpty)
    }

    // MARK: - ② 끝인사: 안전망 폴링

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func theFarewellSafetyNetPollsOnlyWhileVisibleAndOnlyForTheGraceWindow() async {
        // 없으면: 초인종을 놓치면(미구독 · 재연결 중) 결과 화면의 대화가 멈춰 선다. 반대로 상한이 없으면
        //        결과 화면을 켜 둔 창이 끝난 판을 끝없이 읽는다.
        let (store, gomoku, host) = geStore("poll", handler: geFarewellHandler)
        let clock = GEClock()
        let t0 = clock.now
        gomoku.clock = { clock.now }
        func tick(_ offset: TimeInterval) async {
            clock.now = t0.addingTimeInterval(offset)
            await gomoku.pollTick(at: clock.now)
        }
        func states() -> Int { geCount(host, "gomoku_state") }

        gomoku.applyState(geDecode(geState(finished: true, chat: [], chatSeq: 0)))
        #expect(gomoku.finishedChatWatch?.id == geMatchID)
        #expect(gomoku.finishedChatWatch?.until == t0.addingTimeInterval(GomokuStore.finishedChatWindowSeconds))
        gomoku.lastStateRequestAt = t0

        // 창이 안 보이면 안 돈다.
        await tick(50)
        #expect(states() == 0)
        clock.now = t0
        gomoku.isWindowVisible = true

        // 미구독: 3초.
        await tick(2.0)
        #expect(states() == 0)
        await tick(3.1)
        #expect(states() == 1)
        #expect(gomoku.chat.map(\.body) == ["수고하셨어요"], "안전망이 읽어 온 끝인사가 화면에 안 붙었다")
        await tick(5.0)
        #expect(states() == 1)
        await tick(6.2)
        #expect(states() == 2)

        // 구독 중: 10초(주 경로는 초인종이다).
        store.realtimeState = .subscribed(since: t0, lastHeardAt: t0)
        await tick(15.0)
        #expect(states() == 2)
        await tick(16.3)
        #expect(states() == 3)

        // 같은 끝난 판을 다시 읽어도 끝이 뒤로 밀리지 않는다 — 밀리면 영영 안 닫힌다.
        #expect(gomoku.finishedChatWatch?.until == t0.addingTimeInterval(GomokuStore.finishedChatWindowSeconds))

        // 창 안의 마지막 한 번, 그리고 그 뒤로는 침묵.
        await tick(129)
        #expect(states() == 4)
        await tick(141)
        #expect(states() == 4, "서버가 더는 말을 안 받는 시간에도 끝난 판을 읽는다")
        await tick(3_600)
        #expect(states() == 4)
        // 결과 화면에서는 로비 목록도 돌지 않는다.
        #expect(geCount(host, "gomoku_lobby") == 0)
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func theSafetyNetCountsFromTheServersFinishTimeAndStopsOnceTheMatchIsFolded() async {
        let clock = GEClock()
        let t0 = clock.now
        let t0Ms = t0.timeIntervalSince1970 * 1000

        // 서버가 끝난 시각을 말해 주면 **거기서** 센다: 200초 전에 끝난 판을 뒤늦게 세우면 안전망은 이미 닫혀 있다.
        let (_, late, lateHost) = geStore("poll-late", handler: geFarewellHandler)
        late.clock = { clock.now }
        late.applyState(geDecode(geState(finished: true, chat: [], chatSeq: 0,
                                         finishedMs: t0Ms - 200_000, serverNowMs: t0Ms)))
        #expect(late.finishedChatWatch?.until == t0.addingTimeInterval(-200 + GomokuStore.finishedChatWindowSeconds))
        late.isWindowVisible = true
        late.lastStateRequestAt = t0
        clock.now = t0.addingTimeInterval(30)
        await late.pollTick(at: clock.now)
        #expect(geCount(lateHost, "gomoku_state") == 0, "오래전에 끝난 판에 안전망이 돈다")

        // 기준선: 방금 끝난 판은 같은 순간에 돈다(위 0 이 '아무것도 안 도는 스토어'라서가 아니다).
        clock.now = t0
        let (_, fresh, freshHost) = geStore("poll-fresh", handler: geFarewellHandler)
        fresh.clock = { clock.now }
        fresh.applyState(geDecode(geState(finished: true, chat: [], chatSeq: 0,
                                          finishedMs: t0Ms, serverNowMs: t0Ms)))
        fresh.isWindowVisible = true
        fresh.lastStateRequestAt = t0
        clock.now = t0.addingTimeInterval(30)
        await fresh.pollTick(at: clock.now)
        #expect(geCount(freshHost, "gomoku_state") == 1)

        // 판을 내리면(로비로) 창이 남아 있어도 더 읽지 않는다.
        fresh.backToLobby()
        fresh.lastStateRequestAt = t0
        clock.now = t0.addingTimeInterval(60)
        await fresh.pollTick(at: clock.now)
        #expect(geCount(freshHost, "gomoku_state") == 1, "나간 판을 안전망이 계속 읽는다")
    }

    // MARK: - ① 끝난 판에서 나가기

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func closingTheWindowOnTheResultScreenLeavesForTheLobbyButMinimizingKeepsIt() async {
        // 없으면: 결과 화면인 채로 창을 닫아도 끝난 판이 남아, 다음에 창을 열면 로비가 아니라 그 결과가 다시 서고
        //        [로비로] 를 눌러야만 빠져나온다(신고 그대로).
        let (_, gomoku, host) = geStore("close", handler: geFarewellHandler)
        gomoku.applyState(geDecode(geState(finished: true, chat: [geChat(1, "수고하셨어요")], chatSeq: 1)))
        gomoku.chatDraft = "잘 뒀어요"
        #expect(gomoku.phase == .result && gomoku.chat.count == 1)

        // 최소화: 결과 화면도 대화도 쓰던 글도 남는다.
        gomoku.windowDidHide()
        #expect(gomoku.match?.isFinished == true && gomoku.phase == .result)
        #expect(gomoku.chat.count == 1 && gomoku.chatDraft == "잘 뒀어요")

        // 닫기: 로비로.
        gomoku.windowDidClose()
        #expect(gomoku.match == nil, "창을 닫았는데 끝난 판이 남았다 — 다음에 열면 결과 화면이 다시 선다")
        #expect(gomoku.phase == .lobby)
        #expect(gomoku.chat.isEmpty && gomoku.chatDraft == "", "나간 판의 대화·초안이 다음 판으로 넘어간다")
        #expect(gomoku.dismissedMatchIDs.contains(geMatchID))

        await geWait { geCount(host, "gomoku_leave") == 1 }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(geCount(host, "gomoku_leave") == 1, "같은 판에 나가기를 두 번 불렀다(최소화가 이미 말했다)")
        // 닫힌 창을 위해 목록을 다시 읽지 않는다 — 다음에 여는 `openWindow` 가 읽는다.
        #expect(geCount(host, "gomoku_lobby") == 0 && geCount(host, "gomoku_inbox") == 0)

        // 늦게 온 그 판의 응답이 사용자를 결과 화면으로 끌고 가지 않는다.
        #expect(gomoku.applyState(geDecode(geState(finished: true))) == .ignored)
        #expect(gomoku.phase == .lobby && gomoku.match == nil)

        // 멱등(로그아웃 경로가 한 번 더 불러도 안전하다).
        gomoku.windowDidClose()
        #expect(gomoku.phase == .lobby && geCount(host, "gomoku_leave") == 1)
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func closingAloneAlsoTellsTheServerAndBackToLobbyStillRefreshes() async {
        // 닫기 통지만 와도(프로그램 닫기) 서버에 나갔다고 말한다.
        let (_, closed, closedHost) = geStore("close-only", handler: geFarewellHandler)
        closed.applyState(geDecode(geState(finished: true)))
        closed.windowDidClose()
        await geWait { geCount(closedHost, "gomoku_leave") == 1 }
        #expect(geCount(closedHost, "gomoku_leave") == 1)
        #expect(closed.phase == .lobby && closed.match == nil)

        // 기준선: [로비로] 는 여전히 목록을 다시 읽는다(닫기의 '0건' 이 스텁이 죽어서가 아니다).
        let (_, viaButton, buttonHost) = geStore("button", handler: geFarewellHandler)
        viaButton.applyState(geDecode(geState(finished: true)))
        viaButton.backToLobby()
        await geWait { geCount(buttonHost, "gomoku_lobby") == 1 && geCount(buttonHost, "gomoku_inbox") == 1 }
        #expect(geCount(buttonHost, "gomoku_lobby") == 1 && geCount(buttonHost, "gomoku_inbox") == 1)
        #expect(viaButton.phase == .lobby && viaButton.match == nil)
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func closingTheWindowNeverLeavesAMatchInProgress() async {
        // 없으면: 창을 닫는 것이 기권이 된다 — 대국은 서버에서 계속되는데 화면만 로비로 떨어진다.
        let (_, gomoku, host) = geStore("close-active", handler: geFarewellHandler)
        gomoku.applyState(geDecode(geState(id: geOtherMatchID, finished: false)))
        #expect(gomoku.phase == .playing)

        gomoku.windowDidHide()
        gomoku.windowDidClose()
        try? await Task.sleep(for: .milliseconds(150))

        #expect(gomoku.phase == .playing && gomoku.match?.id == geOtherMatchID)
        #expect(gomoku.match?.isFinished == false)
        #expect(geCount(host, "gomoku_leave") == 0, "진행 중인 판에서 나가기를 불렀다")
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func closingTheWindowFoldsAFinishedRobotMatchButKeepsOneInProgress() async {
        let (_, gomoku, host) = geStore("close-ai")
        gomoku.aiRuntime.minimumThinkSeconds = 0
        gomoku.isWindowVisible = true
        gomoku.startAIMatch(humanColor: .black)      // 사람이 흑 — 로봇은 기다린다
        #expect(gomoku.isAIMatch && gomoku.phase == .playing)

        // 진행 중인 로봇 판은 닫아도 남는다(1:1 과 같은 결).
        gomoku.windowDidHide()
        gomoku.windowDidClose()
        #expect(gomoku.isAIMatch && gomoku.phase == .playing && gomoku.match?.isFinished == false)

        gomoku.resignAIMatch()
        #expect(gomoku.match?.isFinished == true && gomoku.phase == .result)

        gomoku.windowDidHide()
        #expect(gomoku.phase == .result, "최소화가 끝난 로봇 판의 결과를 지웠다")
        gomoku.windowDidClose()
        #expect(gomoku.match == nil && gomoku.aiGame == nil && gomoku.phase == .lobby,
                "창을 닫았는데 끝난 로봇 판이 남았다")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(geCount(host, "gomoku_leave") == 0 && geCount(host, "gomoku_state") == 0,
                "로봇 판은 서버에 없다")
    }
}
