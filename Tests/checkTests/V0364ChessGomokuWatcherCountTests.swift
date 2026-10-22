import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.64 — 체스·오목 **관전자 수** 전선 계약(코어).
//
// 서버가 더하는 것은 키 하나(`watchers`)와 함수 하나(`<game>_watch_live` — 읽기 전용 관전 RPC 를 그대로 싣고
// 그 한 칸을 더하는 껍데기)다. 코어가 지켜야 하는 것은 넷이고, 이 파일은 **값으로** 그 넷을 잰다.
//  ① 로비 카드·관전 응답·대국 상태 봉투의 `watchers` → `watchers`/`spectatorCount`. **없으면 0.**
//  ② 관전 폴링이 부르는 이름이 `<game>_watch_live` 다(요청 본문은 옛것과 같은 세 키).
//  ③ 그 함수가 아직 없는 서버(PGRST202)면 옛 `<game>_watch` 로 접고 — ★ **관전 입구는 잠그지 않는다.**
//     `watchUnavailable`(입구 잠금)과 접힘 깃발(`spectatorCountUnavailable`)은 **다른 깃발**이어야 한다.
//     한 깃발로 겸업시키면 "관전자 수 함수가 없다"는 이유로 관전이 통째로 막힌다(이 저장소가 데인 모양).
//  ④ 관전·대국이 내려가면(나가기·리셋·로그아웃) 숫자는 0 으로 돌아간다.
//
// 응답 본문은 **실서버 픽스처 원문**에 `watchers` 한 칸만 더한 것이다(V0343·V0341 과 같은 규약) —
// 손으로 지어낸 모양을 먹이면 "스토어는 초록인데 운영에서 안 되는" 자리가 그대로 남는다.
//
// 기준선이 갈리는지 확인했다(두 분기가 같은 답을 내면 그 단언은 영원히 초록이다):
//  · 키 있음(3·7·2…) 과 키 없음(0) 이 **다른 값**을 낸다 — 세 자리(로비·관전·대국) 모두.
//  · 접힘 전(live 1·old 0) 과 접힘 뒤(live 1·old 2) 가 다른 호출 자취를 낸다.

// MARK: - 하네스

private let wcChessDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/chess-rpc", isDirectory: true)
private let wcGomokuDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/gomoku-rpc", isDirectory: true)

private struct WCError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func wcObject(_ directory: URL, _ name: String) throws -> [String: Any] {
    let data = try Data(contentsOf: directory.appendingPathComponent("\(name).json"))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw WCError("\(name) 는 JSON 객체가 아니다")
    }
    return object
}

private func wcChess(_ name: String) throws -> [String: Any] { try wcObject(wcChessDirectory, name) }
private func wcGomoku(_ name: String) throws -> [String: Any] { try wcObject(wcGomokuDirectory, name) }

/// 픽스처 원문에 **한 칸만** 더한다(없애는 것은 `nil`). 서버가 더하는 변화를 그대로 흉내 낸다.
private func wcWith(_ object: [String: Any], watchers: Int?) -> [String: Any] {
    var copy = object
    if let watchers { copy["watchers"] = watchers } else { copy.removeValue(forKey: "watchers") }
    return copy
}

private func wcText(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

/// 서버에 그 함수가 아직 없을 때 PostgREST 가 내는 **실제 404 본문 모양**.
/// "schema cache" 라는 글자가 있어야 공용 매핑이 `.databaseSchemaMissing` 으로 접는다 — 줄여 쓰면
/// 그냥 `invalidResponse(404)` 가 되어 접힘 갈래를 **한 번도 안 지난다**(그러면 이 파일이 아무것도 안 잰다).
private func wcPGRST202(_ function: String) -> String {
    #"{"code":"PGRST202","details":"Searched for the function public."# + function
        + #" with parameters, but no matches were found in the schema cache.","hint":null,"#
        + #""message":"Could not find the function public."# + function
        + #" in the schema cache"}"#
}

/// rpc 이름 → 응답 본문 목록(n 번째 호출이 n 번째 본문, 모자라면 마지막 것이 반복). 표에 없는 rpc 는 PGRST202.
private func wcHandler(_ map: [String: [String]]) -> GomokuStubProtocol.Handler {
    { rpc, _, index in
        guard let bodies = map[rpc], !bodies.isEmpty else {
            return GomokuStubProtocol.Reply(status: 404, body: wcPGRST202(rpc))
        }
        return GomokuStubProtocol.Reply(body: bodies[min(index, bodies.count - 1)])
    }
}

private func wcDecode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(type, from: Data(wcText(object).utf8))
}

@MainActor
private enum WCRetention {
    /// 두 스토어 모두 `WorkTimerStore` 를 **약참조**로 들린다 — 버리면 host 가 nil 이 되어 요청이 한 건도 안 나간다.
    static var stores: [WorkTimerStore] = []
}

@MainActor
private func wcOwner(_ label: String, me: String, handler: @escaping GomokuStubProtocol.Handler)
    -> (WorkTimerStore, String) {
    let host = "v0364-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
        session: GomokuStubProtocol.session())
    let owner = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0364-watchers"), workspaceNotifications: nil)
    owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    WCRetention.stores.append(owner)
    return (owner, host)
}

@MainActor
private func makeWCChess(_ label: String, me: String, handler: @escaping GomokuStubProtocol.Handler)
    -> (ChessStore, String) {
    let (owner, host) = wcOwner("c-\(label)", me: me, handler: handler)
    let chess = ChessStore(host: owner)
    chess.pollStepSeconds = 3_600          // 실루프는 재우고 걸음은 테스트가 직접 밟는다
    chess.spectatorFeaturesEnabled = true  // 맥 배선 한 줄(기본은 꺼짐)
    chess.isWindowVisible = true
    return (chess, host)
}

@MainActor
private func makeWCGomoku(_ label: String, me: String, handler: @escaping GomokuStubProtocol.Handler)
    -> (GomokuStore, String) {
    let (owner, host) = wcOwner("g-\(label)", me: me, handler: handler)
    let gomoku = owner.gomoku
    gomoku.pollStepSeconds = 3_600
    gomoku.spectatorFeaturesEnabled = true
    gomoku.isWindowVisible = true
    return (gomoku, host)
}

/// 상한은 벽시계가 아니라 **재개 횟수**다(전체 스위트에서 렌더 테스트가 메인 액터를 수십 초씩 쥔다).
@MainActor
private func wcWait(_ resumes: Int = 4_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func wcCount(_ host: String, _ rpc: String) -> Int { GomokuStubProtocol.count(host: host, rpc: rpc) }

private let wcChessWatchID = "9a7156f6-f055-4590-ba98-f537ead0a600"
private let wcChessWatcher = "cc000000-0000-4000-8000-0000000000c3"   // 제3자 C(관전 픽스처를 부른 사람)
private let wcChessPlayer = "aa000000-0000-4000-8000-0000000000a1"    // 백 A(대국 픽스처를 부른 사람)
private let wcGomokuWatchID = "0a7c0000-0000-4000-8000-00000000a7c1"
private let wcGomokuWatcher = "544e3837-f01c-4560-b82f-4d44c269f044"  // 제3자 C
private let wcGomokuPlayer = "3e240c02-8972-478e-a674-014f498a641b"   // 흑 B
private let wcGomokuLobbyWatcher = "785b5732-75fe-4a71-931a-2e3f06e63505"

// MARK: - ① 로비 카드 (watchers 없으면 0 · 있으면 그 값)

@Test(.gomokuDefaultsCleanup)
@MainActor
func v0364ChessLobbyCardCarriesWatchersAndDefaultsToZero() async throws {
    // 없으면: 서버가 보낸 관전자 수를 로비 카드가 통째로 버려도(또는 nil 을 1 로 지어내도) 초록이다.
    let fixture = try wcChess("chess_lobby__ok_watch_entry")
    let (store, _) = makeWCChess("lobby", me: wcChessWatcher, handler: wcHandler([:]))

    // 안 싣는 서버(옛 로비) — 카드는 0 이고 화면은 아무것도 그리지 않는다.
    await store.applyLobby(try wcDecode(ChessLobbyResponse.self, wcWith(fixture, watchers: nil)))
    #expect(store.liveMatches.count == 1, "픽스처: 관전 입구 한 줄")
    #expect(store.liveMatches.first?.watchers == 0)

    // 같은 응답에 한 칸만 더하면 그 값이 그대로 선다(기준선이 갈린다).
    var withCount = fixture
    var rows = try #require(fixture["matches"] as? [[String: Any]])
    rows[0]["watchers"] = 7
    withCount["matches"] = rows
    await store.applyLobby(try wcDecode(ChessLobbyResponse.self, withCount))
    #expect(store.liveMatches.first?.watchers == 7)
}

@Test(.gomokuDefaultsCleanup)
@MainActor
func v0364GomokuLobbyCardCarriesWatchersAndDefaultsToZero() async throws {
    // 없으면: 두 카드가 같은 숫자를 보여 주거나(한 판의 값을 전부에 쓰거나) 값을 통째로 버려도 초록이다.
    let fixture = try wcGomoku("gomoku_lobby__ok_matches")
    var rows = try #require(fixture["matches"] as? [[String: Any]])
    #expect(rows.count == 2, "픽스처: 진행 중 두 판")
    rows[0]["watchers"] = 4                      // 첫 판만 사람이 보고 있다
    var object = fixture
    object["matches"] = rows
    let (store, _) = makeWCGomoku("lobby", me: wcGomokuLobbyWatcher, handler: wcHandler([:]))

    store.applyLobby(try wcDecode(GomokuLobbyResponse.self, object))
    #expect(store.liveMatches.count == 2)
    #expect(store.liveMatches.first?.watchers == 4)
    #expect(store.liveMatches.last?.watchers == 0, "키가 없는 판은 0 — 옆 카드의 숫자를 빌리지 않는다")
}

// MARK: - ② 관전 폴링이 부르는 이름 · 관전 응답의 watchers

@Test(.gomokuDefaultsCleanup)
@MainActor
func v0364ChessWatchPollCallsWatchLiveAndShowsTheCount() async throws {
    // 없으면: 옛 `chess_watch` 를 계속 불러 관전자 수가 영영 0 이어도(서버에 새 함수가 있어도) 초록이다.
    let fixture = try wcChess("chess_watch__ok_active")
    let (store, host) = makeWCChess("watch", me: wcChessWatcher, handler: wcHandler([
        // 첫 응답은 3명, 둘째 응답은 **키 없음**(안 싣는 서버·아무도 안 보는 판) → 0 으로 내려가야 한다.
        "chess_watch_live": [wcText(wcWith(fixture, watchers: 3)), wcText(wcWith(fixture, watchers: nil))]
    ]))

    store.startWatching(matchID: wcChessWatchID)
    await wcWait { store.spectating?.hasServerState == true && !store.watchRuntime.watchInFlight }

    #expect(wcCount(host, "chess_watch_live") == 1, "관전 폴링이 부른 이름이 chess_watch_live 가 아니다")
    #expect(wcCount(host, "chess_watch") == 0, "새 함수가 있는데 옛 길을 또 불렀다")
    let body = try #require(GomokuStubProtocol.calls(host: host, rpc: "chess_watch_live").first).json
    #expect(Set(body.keys) == ["p_protocol", "p_match_id", "p_since_seq"], "요청 본문은 옛것과 같은 세 키다")
    #expect(body["p_match_id"] as? String == wcChessWatchID)
    #expect(store.spectatorCount == 3)
    #expect(store.watchUnavailable == false)
    #expect(store.spectatorCountUnavailable == false)

    await store.refreshWatch()
    #expect(wcCount(host, "chess_watch_live") == 2)
    #expect(store.spectatorCount == 0, "키가 없는 응답은 0 — 앞 응답의 숫자가 굳으면 안 된다")
    #expect(store.spectating?.hasServerState == true, "숫자가 0 이어도 관전은 그대로 돈다")
}

@Test(.gomokuDefaultsCleanup)
@MainActor
func v0364GomokuWatchPollCallsWatchLiveAndShowsTheCount() async throws {
    // 없으면: 옛 `gomoku_watch` 를 계속 불러 관전자 수가 영영 0 이어도 초록이다.
    let fixture = try wcGomoku("gomoku_watch__ok_since0")
    let (store, host) = makeWCGomoku("watch", me: wcGomokuWatcher, handler: wcHandler([
        "gomoku_watch_live": [wcText(wcWith(fixture, watchers: 5)), wcText(wcWith(fixture, watchers: nil))]
    ]))

    store.startWatching(matchID: wcGomokuWatchID)
    await wcWait { store.spectating?.hasServerState == true && !store.watchRuntime.watchInFlight }

    #expect(wcCount(host, "gomoku_watch_live") == 1, "관전 폴링이 부른 이름이 gomoku_watch_live 가 아니다")
    #expect(wcCount(host, "gomoku_watch") == 0, "새 함수가 있는데 옛 길을 또 불렀다")
    let body = try #require(GomokuStubProtocol.calls(host: host, rpc: "gomoku_watch_live").first).json
    #expect(Set(body.keys) == ["p_protocol", "p_match_id", "p_since_seq"])
    #expect(body["p_match_id"] as? String == wcGomokuWatchID)
    #expect(store.spectatorCount == 5)
    #expect(store.watchUnavailable == false)
    #expect(store.spectatorCountUnavailable == false)

    await store.refreshWatch()
    #expect(wcCount(host, "gomoku_watch_live") == 2)
    #expect(store.spectatorCount == 0, "키가 없는 응답은 0 — 앞 응답의 숫자가 굳으면 안 된다")
    #expect(store.spectating?.hasServerState == true)
}

// MARK: - ③ PGRST202 접힘 — 관전은 돌고 입구는 안 잠긴다 (핵심)

@Test(.gomokuDefaultsCleanup)
@MainActor
func v0364ChessFoldsToOldWatchWithoutLockingTheWatchDoor() async throws {
    // 없으면: 접힘 깃발을 `watchUnavailable` 과 겸업시킨 구현이 통과한다 — 그 순간 [관전] 칩이 통째로 잠겨
    //         "관전자 수 함수가 없다"는 이유로 **관전 기능 전체**가 죽는다(db push 전 창 = 모든 사용자).
    let watch = try wcChess("chess_watch__ok_active")
    let (store, host) = makeWCChess("fold", me: wcChessWatcher, handler: wcHandler([
        "chess_watch": [wcText(watch)]        // 옛 함수만 있는 서버 — chess_watch_live 는 PGRST202
    ]))

    store.startWatching(matchID: wcChessWatchID)
    await wcWait { store.spectating?.hasServerState == true && !store.watchRuntime.watchInFlight }

    #expect(wcCount(host, "chess_watch_live") == 1, "새 이름을 한 번은 시도한다")
    #expect(wcCount(host, "chess_watch") == 1, "같은 바퀴에서 옛 길로 접어 다시 불러야 한다")
    #expect(store.spectating?.hasServerState == true, "접혔는데 관전이 죽었다")
    #expect(store.spectatorCount == 0, "접힌 세션의 숫자는 0 이다(화면은 아무것도 그리지 않는다)")
    // ★ 이 파일의 핵심 단언 — 관전 입구는 잠기지 않는다.
    #expect(store.watchUnavailable == false, "관전자 수 함수가 없다는 이유로 관전 입구가 잠겼다")
    #expect(store.spectatorCountUnavailable == true, "접힘은 따로 기억해야 매 폴링이 404 를 한 번씩 더 쏜다")
    #expect(store.notice != ChessNoticeText.unavailable, "관전이 도는데 '곧 열려요' 안내가 떴다")

    // 그 뒤로는 옛 길만 쓴다(404 를 폴링마다 반복하지 않는다).
    await store.refreshWatch()
    #expect(wcCount(host, "chess_watch_live") == 1)
    #expect(wcCount(host, "chess_watch") == 2)

    // 입구가 열려 있다 — 나갔다 다시 들어갈 수 있다(잠겼다면 여기서 spectating 이 nil 이다).
    store.leaveWatch()
    #expect(store.spectating == nil)
    #expect(store.spectatorCount == 0)
    store.startWatching(matchID: wcChessWatchID)
    #expect(store.spectating != nil, "접힘이 관전 입구를 잠갔다")
}

@Test(.gomokuDefaultsCleanup)
@MainActor
func v0364GomokuFoldsToOldWatchWithoutLockingTheWatchDoor() async throws {
    // 없으면: 오목이 2026-10-01 에 데인 그 사고(깃발 겸업 → [관전] 칩이 조용히 죽음)가 그대로 되돌아온다.
    let watch = try wcGomoku("gomoku_watch__ok_since0")
    let (store, host) = makeWCGomoku("fold", me: wcGomokuWatcher, handler: wcHandler([
        "gomoku_watch": [wcText(watch)]
    ]))

    store.startWatching(matchID: wcGomokuWatchID)
    await wcWait { store.spectating?.hasServerState == true && !store.watchRuntime.watchInFlight }

    #expect(wcCount(host, "gomoku_watch_live") == 1)
    #expect(wcCount(host, "gomoku_watch") == 1)
    #expect(store.spectating?.hasServerState == true, "접혔는데 관전이 죽었다")
    #expect(store.spectatorCount == 0)
    #expect(store.watchUnavailable == false, "관전자 수 함수가 없다는 이유로 관전 입구가 잠겼다")
    #expect(store.spectatorCountUnavailable == true)
    #expect(store.notice != GomokuNoticeText.watchUnavailable, "관전이 도는데 '곧 열려요' 안내가 떴다")

    await store.refreshWatch()
    #expect(wcCount(host, "gomoku_watch_live") == 1)
    #expect(wcCount(host, "gomoku_watch") == 2)

    store.leaveWatch()
    #expect(store.spectating == nil)
    #expect(store.spectatorCount == 0)
    store.startWatching(matchID: wcGomokuWatchID)
    #expect(store.spectating != nil, "접힘이 관전 입구를 잠갔다")
}

// MARK: - ④ 대국자 본인 봉투도 같은 한 칸으로

@Test(.gomokuDefaultsCleanup)
@MainActor
func v0364ChessPlayerStateEnvelopeFeedsTheSameCount() async throws {
    // 없으면: 관전 화면에만 숫자가 뜨고 **내 판을 보고 있는 사람 수**는 영영 안 뜬다(명세의 세 자리 중 하나가 빈다).
    let fixture = try wcChess("chess_state__ok_initial_my_turn")
    let (store, _) = makeWCChess("state", me: wcChessPlayer, handler: wcHandler([:]))

    store.applyState(try wcDecode(ChessStatePayload.self, wcWith(fixture, watchers: 2)))
    #expect(store.match != nil, "픽스처: 내 판이 선다")
    #expect(store.spectatorCount == 2)

    // 안 싣는 서버의 같은 응답 → 0(기준선이 갈린다).
    store.applyState(try wcDecode(ChessStatePayload.self, wcWith(fixture, watchers: nil)))
    #expect(store.spectatorCount == 0)
}

@Test(.gomokuDefaultsCleanup)
@MainActor
func v0364GomokuPlayerStateEnvelopeFeedsTheSameCount() async throws {
    // 없으면: 내 판의 관전자 수가 영영 0 이다(서버가 `gomoku__state` 에 실어 보내도).
    let fixture = try wcGomoku("gomoku_state__ok_since0")
    let (store, _) = makeWCGomoku("state", me: wcGomokuPlayer, handler: wcHandler([:]))

    store.applyState(try wcDecode(GomokuStatePayload.self, wcWith(fixture, watchers: 6)))
    #expect(store.match != nil, "픽스처: 내 판이 선다")
    #expect(store.spectatorCount == 6)

    store.applyState(try wcDecode(GomokuStatePayload.self, wcWith(fixture, watchers: nil)))
    #expect(store.spectatorCount == 0)
}

// MARK: - ⑤ 내려갈 때는 0 으로

@Test(.gomokuDefaultsCleanup)
@MainActor
func v0364ChessCountReturnsToZeroWhenTheBoardGoesDown() async throws {
    // 없으면: 남의 판에서 본 숫자가 로비·다음 판·다음 계정 화면에 그대로 남는다(로그아웃해도 안 지워진다).
    let fixture = try wcChess("chess_state__ok_initial_my_turn")
    let (store, _) = makeWCChess("zero", me: wcChessPlayer, handler: wcHandler([:]))

    store.applyState(try wcDecode(ChessStatePayload.self, wcWith(fixture, watchers: 4)))
    #expect(store.spectatorCount == 4)
    store.clearMatch()                       // 판이 내려갔다(로비로)
    #expect(store.spectatorCount == 0)

    store.applyState(try wcDecode(ChessStatePayload.self, wcWith(fixture, watchers: 4)))
    #expect(store.spectatorCount == 4)
    store.spectatorCountUnavailable = true        // 접힘도 로그아웃까지만 기억한다
    store.reset()                            // 로그아웃
    #expect(store.spectatorCount == 0)
    #expect(store.spectatorCountUnavailable == false)
}

@Test(.gomokuDefaultsCleanup)
@MainActor
func v0364GomokuCountReturnsToZeroWhenTheBoardGoesDown() async throws {
    // 없으면: 같은 새는 자리가 오목에 남는다 — 관전을 나가도 눈 아이콘이 로비 화면에 붙어 있다.
    let watch = try wcGomoku("gomoku_watch__ok_since0")
    let (store, _) = makeWCGomoku("zero", me: wcGomokuWatcher, handler: wcHandler([
        "gomoku_watch_live": [wcText(wcWith(watch, watchers: 3))]
    ]))

    store.startWatching(matchID: wcGomokuWatchID)
    await wcWait { store.spectating?.hasServerState == true && !store.watchRuntime.watchInFlight }
    #expect(store.spectatorCount == 3)

    store.stopWatching()                     // 관전 나가기
    #expect(store.spectatorCount == 0)

    let state = try wcGomoku("gomoku_state__ok_since0")
    let (player, _) = makeWCGomoku("zero-reset", me: wcGomokuPlayer, handler: wcHandler([:]))
    player.applyState(try wcDecode(GomokuStatePayload.self, wcWith(state, watchers: 9)))
    #expect(player.spectatorCount == 9)
    player.spectatorCountUnavailable = true
    player.reset()                           // 로그아웃
    #expect(player.spectatorCount == 0)
    #expect(player.spectatorCountUnavailable == false)
}
