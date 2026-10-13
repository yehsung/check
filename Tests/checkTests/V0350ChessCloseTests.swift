import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.50 — **결과 화면인 채로 체스 창을 닫으면 그 판에서 나간 것이다**(2026-10-13 신고).
//
// 예전: 끝난 판을 들고 있는 채로 빨간 점을 누르면 끝난 판이 그대로 남아, 다음에 창을 열면 로비가 아니라 그 결과가
// 다시 서고 [로비로] 를 눌러야만 빠져나왔다. 지금: `windowDidClose()` 가 끝난 판을 내린다.
//
// 여기서 지키는 것은 넷이다:
//  ① 닫기는 끝난 판을 내린다(로비) — **최소화(`windowDidHide`)는 결과 화면을 남긴다**(두 문은 다른 뜻이다).
//  ② 닫기는 조용하다: 로비·순위·상태 요청을 **한 건도 더 내지 않는다**(다음에 창을 여는 `openWindow` 가 읽는다).
//     기준선이 달라야 하므로 같은 판에서 [로비로] 가 `chess_lobby` 를 **내는 것**을 같이 잰다.
//  ③ 진행 중인 판은 닫아도 남는다 — 닫기는 기권이 아니다(시계는 서버에서 흐른다).
//  ④ 로봇 판도 같은 규칙이다: 끝났으면 내리고(AI 판까지 버린다), 진행 중이면 남긴다.
//
// 하네스는 V0343ChessStoreTests 의 관용구 그대로다(호스트별 `GomokuStubProtocol` · 소유자 보관 · 실루프 재우기 ·
// 픽스처 **원문** · 매니페스트 caller). 그 파일의 것이 private 라 접두사 `cc` 로 다시 적었다.
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).

// MARK: - 하네스

private let ccFixtureDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/chess-rpc", isDirectory: true)

private struct CCError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// 픽스처 **원문**(서버가 낸 글자 그대로 — 다시 직렬화하지 않는다).
private func ccText(_ name: String) throws -> String {
    try String(contentsOf: ccFixtureDirectory.appendingPathComponent("\(name).json"), encoding: .utf8)
}

/// 그 픽스처를 **누가 불렀는가**(매니페스트). 세션의 user id 가 이 사람이어야 `my_color` 가 맞는다.
private func ccCaller(_ name: String) throws -> String {
    let data = try Data(contentsOf: ccFixtureDirectory.appendingPathComponent("_manifest.json"))
    guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let fixtures = manifest["fixtures"] as? [String: Any],
          let entry = fixtures[name] as? [String: Any],
          let caller = entry["caller"] as? String else {
        throw CCError("\(name): 매니페스트에 caller 가 없다")
    }
    return caller
}

/// rpc 이름 → 응답 본문 목록(모자라면 마지막 것이 반복된다). 표에 없는 rpc 는 PGRST202(그 함수를 모르는 서버).
private func ccHandler(_ map: [String: [String]]) -> GomokuStubProtocol.Handler {
    { rpc, _, index in
        guard let bodies = map[rpc], !bodies.isEmpty else {
            return GomokuStubProtocol.Reply(
                status: 404,
                body: #"{"code":"PGRST202","details":"Searched for the function public."# + rpc
                    + #" with parameters, but no matches were found in the schema cache.","hint":null,"#
                    + #""message":"Could not find the function public."# + rpc + #" in the schema cache"}"#)
        }
        return GomokuStubProtocol.Reply(body: bodies[min(index, bodies.count - 1)])
    }
}

@MainActor
private enum CCRetention {
    /// `WorkTimerStore` 는 체스 스토어를 **약참조**로 들린다 — 테스트가 버리면 요청이 한 건도 안 나간다.
    static var stores: [WorkTimerStore] = []
}

@MainActor
private func ccStore(
    _ label: String, me: String, handler: @escaping GomokuStubProtocol.Handler
) -> (ChessStore, String) {
    let host = "v0350-cc-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
        session: GomokuStubProtocol.session())
    let owner = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0350-chess-close"), workspaceNotifications: nil)
    owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    CCRetention.stores.append(owner)
    let chess = ChessStore(host: owner)
    // 실루프를 재운다 — 여기서는 폴링이 낸 요청이 '닫기가 낸 요청'으로 세어지면 안 된다.
    chess.pollStepSeconds = 3_600
    return (chess, host)
}

/// 상한은 벽시계가 아니라 **재개 횟수**다(전체 스위트에서는 렌더 테스트가 메인 액터를 수십 초씩 쥔다).
@MainActor
private func ccWait(_ resumes: Int = 4_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 떠 있던 Task 가 요청을 낼 틈을 준다(요청이 **안 나갔다**를 재기 전의 가라앉힘).
@MainActor
private func ccSettle() async {
    try? await Task.sleep(for: .milliseconds(150))
    for _ in 0..<20 { await Task.yield() }
}

private let ccEnded = "chess_state__end_timeout"
private let ccEndedID = "c0de0000-0000-4000-8000-000000000a04"
private let ccRunning = "chess_state__ok_initial_my_turn"
private let ccRunningID = "9a7156f6-f055-4590-ba98-f537ead0a600"

/// 끝난 1:1 판을 결과 화면으로 세운 스토어. 로비는 답하고(빈 로비) 순위는 서버가 모른다(PGRST202).
@MainActor
private func ccFinishedStore(_ label: String) async throws -> (ChessStore, String) {
    let (store, host) = ccStore(
        label, me: try ccCaller(ccEnded),
        handler: ccHandler(["chess_state": [try ccText(ccEnded)],
                            "chess_lobby": [try ccText("chess_lobby__ok_empty")]]))
    store.isWindowVisible = true
    await store.refreshMatch(id: ccEndedID)
    return (store, host)
}

// MARK: - 시험

@Suite("0.3.50 — 결과 화면인 채로 체스 창 닫기")
struct V0350ChessCloseTests {

    // MARK: ① 닫기는 끝난 판을 내리고, 최소화는 남긴다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func closingOnTheResultScreenFoldsTheFinishedMatchWhileMinimizingKeepsIt() async throws {
        // 없으면: 결과 화면인 채로 창을 닫아도 끝난 판이 남아, 다음에 창을 열면 로비가 아니라 그 결과가 다시 서고
        //        [로비로] 를 눌러야만 빠져나온다(신고 그대로). 반대로 그 일을 최소화 문에 달면 결과를 보다
        //        잠깐 치웠을 뿐인데 로비로 떨어진다.
        let (store, _) = try await ccFinishedStore("fold")
        let ended = try #require(store.match)
        #expect(ended.id == ccEndedID)
        #expect(ended.isFinished)
        #expect(store.phase == .result)

        // 최소화(가려짐·프로그램 숨기기도 이 문이다): 결과 화면이 그대로다.
        store.windowDidHide()
        #expect(store.match?.id == ccEndedID, "최소화가 끝난 판을 내렸다 — 되살리면 결과 화면 대신 로비다")
        #expect(store.match?.isFinished == true)
        #expect(store.phase == .result, "최소화가 결과 화면을 로비로 바꿨다")
        #expect(!store.dismissedMatchIDs.contains(ccEndedID), "최소화가 그 판을 '접은 판'으로 적었다")

        // 닫기: 그 판에서 나간 것이다.
        store.windowDidClose()
        #expect(store.match == nil, "창을 닫았는데 끝난 판이 남았다 — 다음에 열면 로비가 아니라 그 결과가 선다")
        #expect(store.phase == .lobby, "창을 닫았는데 화면이 결과에 머문다")
        #expect(store.dismissedMatchIDs.contains(ccEndedID),
                "접은 판으로 안 적혔다 — 늦게 온 그 판의 상태가 사용자를 결과 화면으로 다시 끌고 간다")
        #expect(store.notice == nil)

        // 한 번 더 불러도 같다(로그아웃 경로는 닫기를 두 번 부를 수 있다).
        store.windowDidClose()
        #expect(store.match == nil && store.phase == .lobby)
    }

    // MARK: ② 닫기는 조용하다 — [로비로] 는 로비를 다시 읽는다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func closingSendsNoRequestsWhileBackToLobbyRefetchesTheLobby() async throws {
        // 없으면: 닫을 때마다 안 보이는 창을 위해 로비·순위 왕복이 나간다(무료 플랜 요청 예산 — 창을 여는 쪽이
        //        어차피 다시 읽는다). 그리고 "닫기는 요청을 안 낸다" 만 재면 스텁이 죽어 있어도 초록이라,
        //        같은 판에서 [로비로] 가 `chess_lobby` 를 **내는 것**을 기준선으로 같이 잰다.
        let (closed, closedHost) = try await ccFinishedStore("quiet-close")
        #expect(closed.phase == .result)
        await ccSettle()
        let before = (
            total: GomokuStubProtocol.calls(host: closedHost).count,
            lobby: GomokuStubProtocol.count(host: closedHost, rpc: "chess_lobby"),
            ranking: GomokuStubProtocol.count(host: closedHost, rpc: "chess_ranking"),
            state: GomokuStubProtocol.count(host: closedHost, rpc: "chess_state")
        )
        #expect(before.state == 1, "끝난 판을 세운 조회 한 번이 기준이다")

        closed.windowDidClose()
        #expect(closed.match == nil && closed.phase == .lobby)
        await ccSettle()
        #expect(GomokuStubProtocol.count(host: closedHost, rpc: "chess_lobby") == before.lobby,
                "창 닫기가 로비를 다시 읽었다")
        #expect(GomokuStubProtocol.count(host: closedHost, rpc: "chess_ranking") == before.ranking,
                "창 닫기가 순위를 다시 읽었다")
        #expect(GomokuStubProtocol.count(host: closedHost, rpc: "chess_state") == before.state,
                "창 닫기가 판 상태를 다시 읽었다")
        #expect(GomokuStubProtocol.calls(host: closedHost).count == before.total,
                "창 닫기가 요청을 냈다: \(GomokuStubProtocol.calls(host: closedHost).map(\.rpc))")

        // 기준선: 같은 끝난 판에서 [로비로] 는 로비를 다시 읽는다 — 화면은 같은 곳에 닿는다.
        let (pressed, pressedHost) = try await ccFinishedStore("loud-lobby")
        await ccSettle()
        let lobbyBefore = GomokuStubProtocol.count(host: pressedHost, rpc: "chess_lobby")
        pressed.backToLobby()
        #expect(pressed.match == nil && pressed.phase == .lobby)
        await ccWait { GomokuStubProtocol.count(host: pressedHost, rpc: "chess_lobby") > lobbyBefore }
        #expect(GomokuStubProtocol.count(host: pressedHost, rpc: "chess_lobby") == lobbyBefore + 1,
                "[로비로] 가 로비를 다시 안 읽는다 — 그러면 위의 '닫기는 조용하다' 가 아무것도 재지 않는다")
        // 두 길이 남기는 화면 상태는 같다.
        #expect(closed.dismissedMatchIDs == pressed.dismissedMatchIDs)

        // 닫은 뒤 그 판의 끝난 상태가 **늦게 다시 와도** 결과 화면으로 끌려가지 않는다.
        await closed.refreshMatch(id: ccEndedID)
        #expect(GomokuStubProtocol.count(host: closedHost, rpc: "chess_state") == before.state + 1,
                "늦은 응답을 흉내 낸 조회가 안 나갔다 — 아래 단언이 아무것도 재지 않는다")
        #expect(closed.match == nil, "닫아서 접은 판이 늦은 응답에 되살아났다")
        #expect(closed.phase == .lobby, "닫아서 접은 판의 늦은 응답이 결과 화면을 다시 세웠다")
    }

    // MARK: ③ 진행 중인 판은 닫아도 남는다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func closingDuringAnActiveMatchKeepsTheMatch() async throws {
        // 없으면: 닫기가 판을 가리지 않고 내려, 두던 판의 창을 닫았다 열면 로비가 서고 판은 서버에서 시계만 흐른다
        //        (닫기는 기권이 아니다 — 다시 열면 그 판이 그대로 있어야 한다).
        let (store, host) = ccStore(
            "active", me: try ccCaller(ccRunning),
            handler: ccHandler(["chess_state": [try ccText(ccRunning)],
                                "chess_lobby": [try ccText("chess_lobby__ok_empty")]]))
        store.isWindowVisible = true
        await store.refreshMatch(id: ccRunningID)
        let running = try #require(store.match)
        #expect(running.isFinished == false)
        #expect(store.phase == .playing)
        await ccSettle()
        let total = GomokuStubProtocol.calls(host: host).count

        store.windowDidHide()
        store.windowDidClose()
        #expect(store.match == running, "진행 중인 판이 창 닫기에 바뀌었다")
        #expect(store.phase == .playing, "진행 중인 판의 창을 닫았더니 로비로 갔다 — 닫기는 기권이 아니다")
        #expect(!store.dismissedMatchIDs.contains(ccRunningID),
                "진행 중인 판이 '접은 판'으로 적혔다 — 그 판이 끝났을 때 결과 화면이 안 선다")
        await ccSettle()
        #expect(GomokuStubProtocol.calls(host: host).count == total, "진행 중인 판의 창 닫기가 요청을 냈다")

        // ★ 기준선 갈림: 같은 `windowDidClose()` 가 끝난 판에서는 판을 내린다(①) — 두 입력이 다른 답을 낸다.
        let (over, _) = try await ccFinishedStore("active-contrast")
        over.windowDidClose()
        #expect(over.match == nil && over.phase == .lobby)
        #expect(Set([store.phase, over.phase]).count == 2)
    }

    // MARK: ④ 로봇 판 — 끝났으면 내리고, 진행 중이면 남긴다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func closingFoldsAFinishedRobotMatchButKeepsARunningOne() async throws {
        // 없으면: 로봇에게 지고 창을 닫으면 끝난 로봇 판이 남아, 다음에 열 때 결과 화면이 다시 서고 그동안
        //        `canStartAIMatch` 가 거짓이라 새 판도 못 연다. 반대로 진행 중인 로봇 판까지 내리면 두던 판이 사라진다.
        let (store, host) = ccStore("robot", me: "aa350000-0000-4000-8000-0000000000a1", handler: ccHandler([:]))
        store.aiRuntime.minimumThinkSeconds = 0
        store.aiMoveChooser = { position, _ in ChessRules.legalMoves(in: position).first }
        store.isWindowVisible = true
        #expect(store.canStartAIMatch)

        store.startAIMatch(humanColor: .white)      // 사람이 백 — 로봇은 내 수를 기다린다
        let opened = try #require(store.match)
        #expect(store.isAIMatch && store.phase == .playing)

        // 진행 중: 닫아도 남는다(다시 열면 그 판이 이어진다).
        store.windowDidHide()
        store.windowDidClose()
        #expect(store.match?.id == opened.id, "진행 중인 로봇 판이 창 닫기에 사라졌다")
        #expect(store.isAIMatch && store.phase == .playing)
        #expect(store.aiGame != nil)

        // 기권으로 끝낸다 → 결과 화면.
        store.resignAIMatch()
        #expect(store.match?.isFinished == true)
        #expect(store.phase == .result)
        #expect(store.canStartAIMatch == false, "끝난 로봇 판을 든 채로는 새 판을 못 연다(이 시험의 전제)")

        // 최소화는 결과를 남기고, 닫기는 내린다.
        store.windowDidHide()
        #expect(store.match?.isFinished == true && store.phase == .result, "최소화가 끝난 로봇 판을 내렸다")
        store.windowDidClose()
        #expect(store.match == nil, "창을 닫았는데 끝난 로봇 판이 남았다")
        #expect(store.phase == .lobby)
        #expect(store.aiGame == nil, "판은 내렸는데 AI 판이 남았다 — 엔진 Task 가 버려진 판에 수를 낸다")
        #expect(!store.isAIMatch)
        #expect(store.canStartAIMatch, "닫고 나서도 새 로봇 판을 못 연다")

        // 로봇 판은 어느 길로도 서버에 안 나간다.
        await ccSettle()
        #expect(GomokuStubProtocol.calls(host: host).isEmpty,
                "로봇 판의 창 닫기가 요청을 냈다: \(GomokuStubProtocol.calls(host: host).map(\.rpc))")
    }
}
