import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.41 — 1:1 오목 **관전** 스토어(GomokuStoreWatch.swift) 계약.
//
// 관례는 V0327GomokuStoreTests 그대로다: 호스트별 스텁(테스트마다 고유 호스트라 병렬 스위트가 서로의 기록·응답을 안 덮는다) ·
// 대기 상한은 벽시계가 아니라 **재개 횟수** · `WorkTimerStore` 를 `_` 로 버리지 않는다(오목 스토어가 약참조라 해제되면 요청이 한 건도
// 안 나간다) · UserDefaults 는 `GomokuTestDefaults.make`(격리 스위트, 절대경로) — 맨 `.standard` 는 Preferences 에 plist 를 흘린다(C21).
//
// 각 테스트 첫 줄은 "없으면 어떤 결함이 초록으로 통과하는가"다. 스텁이 못 잡는 것(서버 정규화·실제 시간 경과·같은 판을 보는 두 계정)은
// 통합자의 두 계정 e2e 몫이다 — 여기서 지키는 것은 스토어가 **언제 요청을 내고**, **어느 응답을 버리고**, **응답을 어떻게 옮기는가**다.

// MARK: - 픽스처

private let me = "00000000-0000-0000-0000-0000000000a1"
private let rival = "00000000-0000-0000-0000-0000000000b2"
private let third = "00000000-0000-0000-0000-0000000000c3"
private let watchedID = "aaaaaaaa-0000-0000-0000-00000000aaaa"
private let otherID = "bbbbbbbb-0000-0000-0000-00000000bbbb"
private let myFinishedID = "cccccccc-0000-0000-0000-00000000cccc"
private let myActiveID = "dddddddd-0000-0000-0000-00000000dddd"

private struct WMove: Sendable {
    let seq: Int
    let color: String
    let x: Int?
    let y: Int?
    var auto: Bool = false
}

private let twoMoves = [WMove(seq: 1, color: "black", x: 7, y: 7), WMove(seq: 2, color: "white", x: 8, y: 7)]
private let fourMoves = twoMoves + [WMove(seq: 3, color: "black", x: 7, y: 8), WMove(seq: 4, color: "white", x: 8, y: 8)]

private func jsonText(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

private func bodyValue(_ body: String, _ key: String) -> Any? {
    ((try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any])?[key]
}

private func userObject(_ id: String, _ name: String) -> [String: Any] {
    ["user_id": id, "display_name": name, "avatar_url": NSNull(), "character": "aing", "center": "seoul"]
}

private func moveRow(_ move: WMove) -> [String: Any] {
    [
        "seq": move.seq, "color": move.color,
        "x": move.x.map { $0 as Any } ?? NSNull(), "y": move.y.map { $0 as Any } ?? NSNull(),
        "kind": move.x == nil ? "pass" : "stone", "auto": move.auto
    ]
}

/// 서버 board 문자열(225자, '.'·'b'·'w'). y*15 + x.
private func boardString(_ moves: [WMove]) -> String {
    var cells = Array(repeating: Character("."), count: GomokuBoard.cellCount)
    for move in moves {
        guard let x = move.x, let y = move.y else { continue }
        cells[y * GomokuBoard.size + x] = move.color == "black" ? "b" : "w"
    }
    return String(cells)
}

/// gomoku_watch 의 ok 묶음. `moves` 는 p_since_seq 이후분, `allMoves` 는 판 문자열용(기본은 moves 와 같다). **채팅 키는 없다.**
private func watchPayload(
    id: String = watchedID,
    status: String = "active",
    black: String = third,
    white: String = rival,
    moves: [WMove] = twoMoves,
    allMoves: [WMove]? = nil,
    moveCount: Int? = nil,
    turn: String? = "black",
    deadlineMs: Double? = nil,
    serverNowMs: Double? = nil,
    result: String? = nil,
    endReason: String? = nil,
    stake: Int = 5,
    startedMs: Double? = nil,
    blackAutoStreak: Int = 0,
    whiteAutoStreak: Int = 0,
    autoAbandonStreak: Int = 3,
    blackUser: [String: Any]? = userObject(third, "셋째"),
    whiteUser: [String: Any]? = userObject(rival, "라이벌")
) -> [String: Any] {
    let finished = status == "finished"
    let board = allMoves ?? moves
    let null = NSNull()
    let turnValue: Any = finished ? null : (turn.map { $0 as Any } ?? null)
    let deadlineValue: Any = finished ? null : (deadlineMs.map { $0 as Any } ?? null)
    let resultValue: Any = result.map { $0 as Any } ?? (finished ? "black_win" as Any : null)
    let endReasonValue: Any = endReason.map { $0 as Any } ?? (finished ? "five" as Any : null)
    let winnerValue: Any = finished ? black as Any : null
    let finishedValue: Any = finished ? nowMs() as Any : null
    let match: [String: Any] = [
        "id": id,
        "status": status,
        "stake": stake,
        "black": black,
        "white": white,
        "challenger": black,
        "opponent": white,
        "move_count": moveCount ?? board.count,
        "turn": turnValue,
        "deadline_ms": deadlineValue,
        "turn_started_ms": null,
        "started_ms": startedMs.map { $0 as Any } ?? null,
        "result": resultValue,
        "end_reason": endReasonValue,
        "winner": winnerValue,
        "finished_ms": finishedValue,
        "board": boardString(board)
    ]
    return [
        "status": "ok",
        "server_now_ms": serverNowMs ?? nowMs(),
        "match": match,
        "moves": moves.map(moveRow),
        "black_user": blackUser.map { $0 as Any } ?? null,
        "white_user": whiteUser.map { $0 as Any } ?? null,
        "black_auto_streak": blackAutoStreak,
        "white_auto_streak": whiteAutoStreak,
        "auto_abandon_streak": autoAbandonStreak
    ]
}

/// 로비 "지금 대결 중" 한 줄. a/b 는 uuid 순서다 — 색이 아니다(rival < third 라 a = rival).
private func liveMatchRow(id: String = watchedID, a: String = rival, b: String = third, stake: Int = 5) -> [String: Any] {
    ["match_id": id, "a": userObject(a, a == rival ? "라이벌" : "셋째"), "b": userObject(b, b == rival ? "라이벌" : "셋째"),
     "stake": stake, "started_ms": nowMs() - 60_000]
}

private func lobbyPayload(matches: [[String: Any]] = [liveMatchRow()]) -> [String: Any] {
    [
        "status": "ok", "server_now_ms": nowMs(), "turn_seconds": 30,
        "me": ["ruby_balance": 30, "wins": 2, "losses": 1, "draws": 0, "active_match_id": NSNull(), "outgoing_match_id": NSNull()],
        "users": [userObject(rival, "라이벌"), userObject(third, "셋째")],
        "matches": matches
    ]
}

private func inboxPayload(lastFinished: String? = nil) -> [String: Any] {
    var payload: [String: Any] = ["status": "ok", "server_now_ms": nowMs(), "incoming": [], "outgoing": NSNull(), "active_match_id": NSNull()]
    if let lastFinished {
        payload["last_finished"] = ["match_id": lastFinished, "result": "black_win", "end_reason": "resign",
                                    "winner": rival, "stake": 5, "finished_ms": nowMs() - 30_000] as [String: Any]
    }
    return payload
}

/// 내 1:1 판의 gomoku_state ok 묶음(내가 백). 진행 중이거나 끝났다.
private func myStatePayload(id: String = myActiveID, finished: Bool = false) -> [String: Any] {
    let null = NSNull()
    let turnValue: Any = finished ? null : "white" as Any
    let resultValue: Any = finished ? "black_win" as Any : null
    let endReasonValue: Any = finished ? "resign" as Any : null
    let winnerValue: Any = finished ? rival as Any : null
    return [
        "status": "ok",
        "match": [
            "id": id, "status": finished ? "finished" : "active", "stake": 5,
            "black": rival, "white": me, "challenger": rival, "opponent": me,
            "move_count": 1, "turn": turnValue, "deadline_ms": null,
            "result": resultValue, "end_reason": endReasonValue,
            "winner": winnerValue, "invite_expires_ms": null
        ],
        "moves": [moveRow(WMove(seq: 1, color: "black", x: 7, y: 7))],
        "my_color": "white",
        "opponent": userObject(rival, "라이벌"),
        "ruby_balance": NSNull(),
        "server_now_ms": nowMs()
    ]
}

/// 순위 **두 줄**짜리 gomoku_ranking ok 묶음. `baseReply` 의 순위는 0행이라 "행을 손에 들었다"를 말할 수 없다.
private func rankedRankingPayload() -> [String: Any] {
    func row(_ id: String, _ name: String, rank: Int, wins: Int, losses: Int) -> [String: Any] {
        ["rank": rank, "user_id": id, "display_name": name, "avatar_url": NSNull(), "character": "aing",
         "center": "seoul", "wins": wins, "losses": losses, "draws": 0, "points": wins - losses]
    }
    return [
        "status": "ok", "server_now_ms": nowMs(), "record_since_ms": NSNull(),
        "me": ["rank": 2, "wins": 2, "losses": 1, "draws": 0, "points": 1],
        "rows": [row(rival, "라이벌", rank: 1, wins: 5, losses: 1), row(me, "나", rank: 2, wins: 2, losses: 1)]
    ]
}

private func reply(_ object: [String: Any], delay: TimeInterval = 0) -> GomokuStubProtocol.Reply {
    GomokuStubProtocol.Reply(body: jsonText(object), delay: delay)
}

/// 관전 외 RPC 의 기본 응답 — windowDidShow·leaveWatch 가 내는 로비·받은함·순위가 디코드 실패로 빨개지지 않게.
private func baseReply(_ rpc: String) -> GomokuStubProtocol.Reply? {
    switch rpc {
    case "gomoku_lobby": return reply(lobbyPayload())
    case "gomoku_inbox": return reply(inboxPayload())
    case "gomoku_ranking": return reply(["status": "ok", "server_now_ms": nowMs(), "record_since_ms": NSNull(), "me": NSNull(), "rows": []])
    default: return nil
    }
}

/// 실제 PGRST202 본문 모양(404). "schema cache" 가 공용 매핑에서 `.databaseSchemaMissing` 이 된다.
private let pgrst202 = GomokuStubProtocol.Reply(
    status: 404,
    body: #"{"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.gomoku_watch(p_match_id, p_protocol, p_since_seq) in the schema cache"}"#
)

private func snakeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}

private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) -> T {
    try! snakeDecoder().decode(type, from: Data(jsonText(object).utf8))
}

@MainActor
private func makeWatchStore(
    _ label: String,
    enabled: Bool = true,
    handler: @escaping GomokuStubProtocol.Handler = { rpc, _, _ in baseReply(rpc) }
) -> (WorkTimerStore, GomokuStore, String) {
    let host = "v0341-w-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: GomokuStubProtocol.session()
    )
    let defaults = GomokuTestDefaults.make("v0341-watch")
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    WatchTestRetention.stores.append(store)
    let gomoku = store.gomoku
    // 맥 배선(CheckApp.wireGomoku)의 한 줄을 흉내 낸다 — 이 값이 기본 false 인 것은 첫 테스트가 따로 되묻는다.
    gomoku.spectatorFeaturesEnabled = enabled
    // 창 표시가 시작하는 실제 폴링 루프는 이 테스트에서 재우고(첫 걸음이 한 시간 뒤), 걸음은 `pollTick(at:)` 을 직접 밟아 결정적으로 잰다.
    gomoku.pollStepSeconds = 3_600
    return (store, gomoku, host)
}

/// 오목 스토어는 WorkTimerStore 를 **약참조**한다 — 튜플에서 버리면 곧바로 해제되어 요청이 한 건도 안 나간다.
@MainActor
private enum WatchTestRetention {
    static var stores: [WorkTimerStore] = []
}

/// 상한은 벽시계가 아니라 **재개 횟수**다(5ms 한 번 = 한 차례) — 전체 스위트에서는 렌더 테스트가 메인 액터를 수십 초씩 쥔다.
@MainActor
private func watchWait(_ timeout: TimeInterval = 60, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<Int(timeout * 200) {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 나가 있는 관전 조회가 끝날 때까지(응답이 반영될 때까지).
@MainActor
private func settle(_ gomoku: GomokuStore) async {
    await watchWait { !gomoku.watchRuntime.watchInFlight }
}

private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

private func count(_ host: String, _ rpc: String) -> Int { GomokuStubProtocol.count(host: host, rpc: rpc) }

private func point(_ x: Int, _ y: Int) -> GomokuPoint { GomokuPoint(x: x, y: y)! }

// MARK: - 1. 주 스위치 (C11)

@MainActor
@Test(.gomokuDefaultsCleanup)
func 관전_주_스위치가_꺼져_있으면_요청이_한_건도_안_나간다() async {
    // 없으면: 같은 스토어를 쓰는 폰이 오목 화면을 열 때마다 + 1분마다 gomoku_ranking 을 당기고 [관전] 없는 화면에서 gomoku_watch 가 나가도 초록이다.
    let (_, gomoku, host) = makeWatchStore("switch-off", enabled: false)
    let clock = Clock()
    let t0 = clock.now
    gomoku.clock = { clock.now }
    #expect(gomoku.spectatorFeaturesEnabled == false, "기본값은 꺼짐 — 켜는 곳은 맥 배선 한 줄뿐이다")

    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))
    #expect(gomoku.liveMatches.count == 1, "픽스처: 관전할 카드가 있다")
    gomoku.windowDidShow()
    gomoku.startWatching(matchID: watchedID)
    #expect(gomoku.spectating == nil, "꺼진 스위치에서는 관전 상태조차 서지 않는다")
    await gomoku.refreshWatch()
    await gomoku.loadRanking()
    for offset in [0.0, 2.5, 61, 125, 3_600] {
        clock.now = t0.addingTimeInterval(offset)
        await gomoku.pollTick(at: clock.now)
    }
    gomoku.noteOwnMatchFinishedForRanking()
    try? await Task.sleep(for: .milliseconds(200))
    #expect(count(host, "gomoku_watch") == 0)
    #expect(count(host, "gomoku_ranking") == 0)
    #expect(count(host, "gomoku_state") == 0)

    // 기준선이 달라야 이 테스트가 산다: 같은 손짓이 켠 뒤에는 요청을 낸다.
    gomoku.spectatorFeaturesEnabled = true
    gomoku.startWatching(matchID: watchedID)
    await watchWait { count(host, "gomoku_watch") == 1 }
    #expect(count(host, "gomoku_watch") == 1)
    #expect(gomoku.spectating != nil)
}

// MARK: - 2. 진입 · 흑백은 서버만 (C15)

@MainActor
@Test(.gomokuDefaultsCleanup)
func 관전_진입은_로비_카드를_씨앗으로_얼굴만_들고_색은_서버_응답으로만_선다() async throws {
    // 없으면: 로비 a/b(uuid 순)를 흑/백으로 세우는 구현이 초록으로 통과해 절반의 판에서 응답 뒤 두 카드가 뒤집힌다.
    let (_, gomoku, host) = makeWatchStore("seed") { rpc, _, _ in
        rpc == "gomoku_watch" ? reply(watchPayload(black: third, white: rival), delay: 0.3) : baseReply(rpc)
    }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))

    gomoku.startWatching(matchID: watchedID.uppercased())
    let seed = try #require(gomoku.spectating)
    #expect(seed.id == watchedID, "id 는 소문자로 정규화한다")
    #expect(seed.faces.map(\.id) == [rival, third], "씨앗은 카드의 두 얼굴(a·b 순)이다")
    #expect(seed.black == nil && seed.white == nil, "첫 응답 전에는 색을 모른다")
    #expect(!seed.hasServerState)
    #expect(seed.stake == 5)
    #expect(seed.board == GomokuBoard())
    #expect(gomoku.phase == .lobby && gomoku.match == nil, "관전은 로비 자리에 선다 — phase 는 안 바뀐다")
    #expect(gomoku.isSpectating)

    // 응답이 오기 전에도(지연 0.3초) 색은 nil 이다.
    await watchWait { count(host, "gomoku_watch") == 1 }
    #expect(gomoku.spectating?.black == nil)

    await watchWait { gomoku.spectating?.hasServerState == true }
    let live = try #require(gomoku.spectating)
    #expect(live.black?.id == third, "흑은 서버가 말한 사람이다 — 카드의 a(라이벌)가 아니다")
    #expect(live.white?.id == rival)
    #expect(live.black?.displayName == "셋째")
    #expect(live.black?.center == "서울", "센터는 CenterLabel 경계를 한 번 지난 화면 글자다")
    #expect(live.board[point(7, 7)] == .black && live.board[point(8, 7)] == .white)
    #expect(live.moveCount == 2 && live.appliedSeq == 2)
    #expect(live.lastMove == point(8, 7))
    #expect(live.turn == .black)
    #expect(live.isFinished == false && live.winner == nil)
    #expect(count(host, "gomoku_state") == 0, "관전은 gomoku_state 를 부르지 않는다")
    // 같은 판을 다시 눌러도 씨앗으로 되돌리지 않는다.
    gomoku.startWatching(matchID: watchedID)
    #expect(gomoku.spectating?.hasServerState == true)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 씨앗이_없는_판도_같은_로딩_상태로_들어가고_응답이_채운다() async throws {
    // 없으면: 로비 30초 사이 목록에서 빠진 판을 누르면 아무 일도 안 일어나거나(진입 불가) 빈 씨앗으로 죽어도 초록이다.
    let (_, gomoku, host) = makeWatchStore("no-seed") { rpc, _, _ in
        rpc == "gomoku_watch" ? reply(watchPayload(id: otherID, black: rival, white: third,
                                                    blackUser: userObject(rival, "라이벌"), whiteUser: userObject(third, "셋째")))
                              : baseReply(rpc)
    }
    gomoku.isWindowVisible = true
    #expect(gomoku.liveMatches.isEmpty, "픽스처: 목록이 비어 있다")

    gomoku.startWatching(matchID: otherID)
    let seed = try #require(gomoku.spectating)
    #expect(seed.faces.isEmpty && seed.stake == nil && !seed.hasServerState)

    await watchWait { gomoku.spectating?.hasServerState == true }
    let live = try #require(gomoku.spectating)
    #expect(live.black?.id == rival && live.white?.id == third)
    #expect(live.stake == 5, "판돈은 응답이 채운다")
    #expect(count(host, "gomoku_watch") == 1)
    #expect(count(host, "gomoku_state") == 0)
}

// MARK: - 3. 세대 가드 (C13)

@MainActor
@Test(.gomokuDefaultsCleanup)
func 늦게_온_관전_응답은_나가기_뒤에도_판_전환_뒤에도_버려진다() async throws {
    // 없으면: 창을 닫고(또는 나가고) 뒤늦게 온 응답이 관전을 되살리고, A 판을 나가 B 판을 보는 사이 A 의 응답이 B 판을 한 틱 덮어도 초록이다.
    let (_, gomoku, host) = makeWatchStore("late") { rpc, body, _ in
        guard rpc == "gomoku_watch" else { return baseReply(rpc) }
        let id = bodyValue(body, "p_match_id") as? String
        if id == watchedID {
            return reply(watchPayload(id: watchedID, black: third, white: rival), delay: 0.4)
        }
        return reply(watchPayload(id: otherID, black: rival, white: third,
                                  blackUser: userObject(rival, "라이벌"), whiteUser: userObject(third, "셋째")))
    }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload(matches: [liveMatchRow(id: watchedID), liveMatchRow(id: otherID)])))

    // ① 나가기 뒤 늦은 응답.
    let generation0 = gomoku.watchRuntime.watchGeneration
    gomoku.startWatching(matchID: watchedID)
    #expect(gomoku.watchRuntime.watchGeneration == generation0 + 1, "진입이 세대를 올린다")
    await watchWait { count(host, "gomoku_watch") == 1 }
    gomoku.stopWatching()
    #expect(gomoku.spectating == nil)
    #expect(gomoku.watchRuntime.watchGeneration == generation0 + 2, "나가기가 세대를 올린다")
    try? await Task.sleep(for: .milliseconds(700))
    #expect(gomoku.spectating == nil, "0.4초 뒤 도착한 응답이 관전을 되살렸다")
    #expect(gomoku.watchRuntime.watchInFlight == false)
    #expect(count(host, "gomoku_watch") == 1)

    // ② A → B 전환 뒤 A 의 늦은 응답.
    gomoku.startWatching(matchID: watchedID)
    await watchWait { count(host, "gomoku_watch") == 2 }
    gomoku.startWatching(matchID: otherID)
    await watchWait { gomoku.spectating?.hasServerState == true }
    #expect(gomoku.spectating?.id == otherID)
    #expect(gomoku.spectating?.black?.id == rival, "B 판의 흑")
    try? await Task.sleep(for: .milliseconds(600))
    let after = try #require(gomoku.spectating)
    #expect(after.id == otherID && after.black?.id == rival, "A 판의 늦은 응답이 B 판을 덮었다")

    // ③ 세대가 같아도 다른 판 id 의 응답은 버린다(둘째 자물쇠 — applyWatch 를 직접 부른다).
    let stray = decode(GomokuWatchResponse.self, watchPayload(id: watchedID, black: third, white: rival, moves: fourMoves))
    gomoku.applyWatch(stray, requestedSince: 0)
    #expect(gomoku.spectating == after, "다른 판 응답이 지금 판에 섞였다")
    #expect(count(host, "gomoku_state") == 0)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 같은_판을_나갔다가_곧바로_다시_보면_앞_요청의_늦은_응답은_세대만이_막는다() async throws {
    // 없으면: 위 ①②는 판 id 자물쇠(applyWatch 의 `row.id == current.id`)만으로도 초록이다 — 세대 가드(C13)가 **유일한** 방어선인 갈래는 같은 판 재진입뿐이라
    //        (A 관전 → [나가기] → 곧바로 같은 A [관전]) 앞 요청의 늦은 응답이 id 자물쇠를 지나 새 요청의 응답을 덮어도 초록이다(2026-09-30 반증).
    let (_, gomoku, host) = makeWatchStore("reenter") { rpc, _, index in
        guard rpc == "gomoku_watch" else { return baseReply(rpc) }
        // 첫 요청만 늦고 수가 많다(4수) — 늦은 응답이 적용되면 moveCount 가 2 → 4 로 튄다.
        return index == 0 ? reply(watchPayload(moves: fourMoves), delay: 0.4) : reply(watchPayload(moves: twoMoves))
    }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))

    gomoku.startWatching(matchID: watchedID)
    await watchWait { count(host, "gomoku_watch") == 1 }
    gomoku.stopWatching()
    gomoku.startWatching(matchID: watchedID)
    await watchWait { gomoku.spectating?.hasServerState == true }
    #expect(count(host, "gomoku_watch") == 2)
    #expect(gomoku.spectating?.moveCount == 2, "두 번째 요청의 응답(2수)이 먼저 선다")
    try? await Task.sleep(for: .milliseconds(700))
    #expect(gomoku.spectating?.id == watchedID)
    #expect(gomoku.spectating?.moveCount == 2 && gomoku.spectating?.appliedSeq == 2,
            "앞 요청의 늦은 응답(4수)이 같은 판이라는 이유로 새 요청의 응답을 덮었다 — 세대 가드가 없다(C13)")
    #expect(gomoku.watchRuntime.watchInFlight == false)
    #expect(count(host, "gomoku_watch") == 2, "늦은 응답이 재요청을 일으켰다")
    #expect(count(host, "gomoku_state") == 0)
}

// MARK: - 4. 창이 안 보이면 요청이 없다 (C14) · 2초 주기 · 끝난 판은 멈춘다

@MainActor
@Test(.gomokuDefaultsCleanup)
func 창이_안_보이면_관전_요청이_없고_상태는_남으며_다시_보이면_즉시_한_번이다() async throws {
    // 없으면: 창을 닫거나 최소화해도 2초 폴링이 계속 돌거나(무료 플랜 예산), 반대로 닫는 순간 관전이 사라져 최소화만 해도 로비로 떨어져도 초록이다.
    let (_, gomoku, host) = makeWatchStore("visibility") { rpc, _, index in
        guard rpc == "gomoku_watch" else { return baseReply(rpc) }
        // 5번째 응답부터 끝난 판.
        return index < 4 ? reply(watchPayload()) : reply(watchPayload(status: "finished", moves: fourMoves, result: "black_win", endReason: "five"))
    }
    let clock = Clock()
    let t0 = clock.now
    gomoku.clock = { clock.now }
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))
    func tick(_ offset: TimeInterval) async {
        clock.now = t0.addingTimeInterval(offset)
        await gomoku.pollTick(at: clock.now)
        await settle(gomoku)
    }
    func watches() -> Int { count(host, "gomoku_watch") }

    // 안 보이는 창에서 들어가면 상태는 서고 요청은 없다.
    #expect(gomoku.isWindowVisible == false)
    gomoku.startWatching(matchID: watchedID)
    #expect(gomoku.spectating != nil)
    try? await Task.sleep(for: .milliseconds(100))
    await tick(0)
    #expect(watches() == 0, "창이 안 보이는데 관전 요청이 나갔다")

    // 보이는 순간 즉시 한 번(창 표시 훅).
    gomoku.windowDidShow()
    await watchWait { watches() == 1 }
    await settle(gomoku)
    #expect(gomoku.spectating?.hasServerState == true)

    // 2초 주기.
    await tick(1.9)
    #expect(watches() == 1)
    await tick(2.1)
    #expect(watches() == 2)
    await tick(4.2)
    #expect(watches() == 3)

    // 숨기면(최소화 포함) 상태는 남고 요청만 멈춘다.
    gomoku.windowDidHide()
    #expect(gomoku.spectating != nil, "창을 닫아도 관전은 남는다(C14)")
    #expect(gomoku.spectating?.hasServerState == true)
    await tick(10)
    await tick(20)
    await tick(29)
    #expect(watches() == 3, "숨긴 창에서 관전 요청이 나갔다")

    // 다시 보이면 즉시 한 번.
    clock.now = t0.addingTimeInterval(30)
    gomoku.windowDidShow()
    await watchWait { watches() == 4 }
    await settle(gomoku)
    #expect(watches() == 4)

    // 가림(다른 창 뒤·다른 Space)도 같다.
    gomoku.windowOcclusionDidChange(visible: false)
    await tick(40)
    #expect(watches() == 4, "가려진 창에서 관전 요청이 나갔다")
    gomoku.windowOcclusionDidChange(visible: true)
    await tick(50)
    #expect(watches() == 5)

    // 5번째 응답이 끝난 판 — 폴링은 즉시 멈추고 결과는 남는다.
    let ended = try #require(gomoku.spectating)
    #expect(ended.isFinished && ended.winner == .black && ended.endReason == .five)
    #expect(ended.turn == nil && ended.deadline == nil)
    #expect(ended.moveCount == 4)
    await tick(100)
    await tick(200)
    clock.now = t0.addingTimeInterval(300)
    gomoku.windowDidShow()
    try? await Task.sleep(for: .milliseconds(150))
    #expect(watches() == 5, "끝난 판을 계속 물었다")
    #expect(gomoku.spectating != nil, "결과는 [나가기] 전까지 남는다")

    // [나가기] → 로비 자리 + 목록·받은함·순위 재조회.
    let rankingsBefore = count(host, "gomoku_ranking")
    gomoku.leaveWatch()
    #expect(gomoku.spectating == nil && gomoku.phase == .lobby)
    await watchWait { count(host, "gomoku_ranking") > rankingsBefore }
    #expect(count(host, "gomoku_ranking") > rankingsBefore, "나가면 순위를 새로 읽는다")
    #expect(count(host, "gomoku_state") == 0)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 끝난_판을_관전한_채_창을_닫으면_관전이_내려가고_진행_중이면_남는다() async throws {
    // 없으면: 끝난 판(isFinished — 재조회가 없다)을 본 채 빨간 점으로 닫으면 그 화면이 무기한 남아, 한 시간 뒤 창을 열어도 로비가 아니라 남의 끝난 판이 서고
    //        [나가기]를 눌러야만 로비다(2026-09-30 반증). 내 판 결과는 같은 자리(windowDidHide → leaveMatch)에서 닫기 = 나가기인데 관전만 비대칭이었다.
    let (_, gomoku, host) = makeWatchStore("hide-finished") { rpc, _, index in
        guard rpc == "gomoku_watch" else { return baseReply(rpc) }
        return index == 0 ? reply(watchPayload()) : reply(watchPayload(status: "finished", moves: fourMoves, result: "black_win", endReason: "five"))
    }
    let clock = Clock()
    let t0 = clock.now
    gomoku.clock = { clock.now }
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))
    gomoku.startWatching(matchID: watchedID)
    gomoku.windowDidShow()
    await watchWait { gomoku.spectating?.hasServerState == true }

    // 진행 중: 닫아도 남는다(C14).
    gomoku.windowDidHide()
    #expect(gomoku.spectating != nil && gomoku.spectating?.isFinished == false, "진행 중인 관전이 창 닫기에 지워졌다(C14)")
    clock.now = t0.addingTimeInterval(5)
    gomoku.windowDidShow()
    await watchWait { gomoku.spectating?.isFinished == true }
    let requests = count(host, "gomoku_watch")
    #expect(requests == 2)

    // 끝남: 닫으면 내려간다 — 요청 없이(조용한 stopWatching).
    gomoku.windowDidHide()
    #expect(gomoku.spectating == nil, "끝난 판을 관전한 채 창을 닫았는데 관전이 남았다 — 다음에 창을 열면 낡은 남의 판이 선다")
    clock.now = t0.addingTimeInterval(3_700)
    gomoku.windowDidShow()
    try? await Task.sleep(for: .milliseconds(150))
    #expect(gomoku.spectating == nil && gomoku.phase == .lobby, "한 시간 뒤 연 창이 로비가 아니다")
    #expect(count(host, "gomoku_watch") == requests, "창 닫기가 관전 요청을 냈다")
    #expect(count(host, "gomoku_state") == 0)
}

// MARK: - 5. 예외 실패 경로 (C17)

@MainActor
@Test(.gomokuDefaultsCleanup)
func 서버_미배포_404_는_관전을_내리고_준비_중_안내를_남기며_다시_돌지_않는다() async {
    // 없으면: brew 가 db push 보다 먼저 나간 창에서 [관전] 이 빈 판 "관전 중"을 세운 채 2초마다 404 를 영영 낸다(ATTACKS client P2).
    let (_, gomoku, host) = makeWatchStore("pgrst202") { rpc, _, _ in
        rpc == "gomoku_watch" ? pgrst202 : baseReply(rpc)
    }
    let clock = Clock()
    let t0 = clock.now
    gomoku.clock = { clock.now }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))

    gomoku.startWatching(matchID: watchedID)
    await watchWait { gomoku.spectating == nil }
    #expect(gomoku.spectating == nil, "미배포 서버에서 빈 판이 남았다")
    #expect(gomoku.notice == GomokuNoticeText.watchUnavailable)
    #expect(gomoku.rankingUnavailable, "같은 마이그레이션의 순위표도 준비 중으로 접는다")
    #expect(gomoku.hasLoadedRanking)
    #expect(count(host, "gomoku_watch") == 1)
    for offset in [2.1, 4.2, 10, 100] {
        clock.now = t0.addingTimeInterval(offset)
        await gomoku.pollTick(at: clock.now)
    }
    #expect(count(host, "gomoku_watch") == 1, "내려간 관전이 계속 폴링했다")
    #expect(count(host, "gomoku_state") == 0)

    // 다음 관전에 들어가면 앞의 준비 중 안내는 걷힌다(다른 안내는 건드리지 않는다 — 아래 신청 만료 안내가 남는다).
    gomoku.setNotice(GomokuNoticeText.inviteTimedOut)
    gomoku.startWatching(matchID: otherID)
    #expect(gomoku.notice == GomokuNoticeText.inviteTimedOut, "관전 진입이 신청 안내를 지웠다(C12)")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 순위를_이미_받았으면_관전_404_가_순위표를_버리지_않는다() async throws {
    // 없으면: 관전 404 한 번으로 **멀쩡한 순위표가 "곧 열려요"로 접힌다**("같은 마이그레이션이라 순위표도 없다"는 추론은
    // 순위가 한 번도 성공하지 않았을 때만 맞다). 60초 폴링이 도는 운영에서는 applyRanking 이 회복시키지만,
    // 폰 데모처럼 시계가 고정된 화면에서는 영구히 접힌 채 남는다.
    let (_, gomoku, host) = makeWatchStore("ranking-kept") { rpc, _, _ in
        switch rpc {
        case "gomoku_watch": return pgrst202
        case "gomoku_ranking": return reply(rankedRankingPayload())
        default: return baseReply(rpc)
        }
    }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))
    await gomoku.loadRanking()
    let loaded = try #require(gomoku.ranking)
    #expect(loaded.entries.count == 2, "픽스처: 순위 두 줄을 손에 들었다 = 서버에 gomoku_ranking 이 있다는 증거")
    #expect(gomoku.rankingUnavailable == false && gomoku.hasLoadedRanking)

    gomoku.startWatching(matchID: watchedID)
    await watchWait { gomoku.spectating == nil }
    // 관전은 두 갈래 다 내려가고 안내도 남는다 — 바뀌는 것은 순위 깃발뿐이다.
    #expect(gomoku.spectating == nil, "미배포 관전에서 빈 판이 남았다")
    #expect(gomoku.notice == GomokuNoticeText.watchUnavailable)
    #expect(count(host, "gomoku_watch") == 1)
    // ★ 관전 깃발은 **조건 없이** 선다 — 이 한 줄이 없으면 [관전] 칩 게이트가 볼 신호가 없어 죽은 버튼이 활성으로 광고된다.
    //   순위 깃발을 "행이 없을 때만"으로 좁힌 그 수리가 정확히 이 신호를 지웠다(2026-10-01).
    #expect(gomoku.watchUnavailable, "행을 들고 있으면 관전 404 가 관전 입구를 안 잠근다 — 칩 게이트가 신호를 잃었다")
    #expect(gomoku.rankingUnavailable == false, "행을 들고 있는데 관전 404 가 순위표를 '곧 열려요'로 접었다")
    #expect(gomoku.ranking == loaded, "관전 404 가 받아 둔 순위 행을 버렸다")
    #expect(gomoku.hasLoadedRanking)

    // 기준선이 달라야 이 테스트가 산다: 순위를 한 번도 못 받은 창(ranking nil)에서는 **같은 404 가 깃발을 세운다**
    // (안 세우면 순위 열이 "불러오는 중"으로 영영 서 있다). 문 앞 가드(`watchUnavailable`)는 60초 순위 폴이 푸는 것이라
    // 여기서는 손으로 풀어 같은 404 를 한 번 더 받는다 — 그 가드 자체는 아래 `관전_404_뒤...` 가 본다.
    gomoku.ranking = nil
    gomoku.hasLoadedRanking = false
    gomoku.watchUnavailable = false
    gomoku.startWatching(matchID: otherID)
    await watchWait { gomoku.spectating == nil }
    #expect(count(host, "gomoku_watch") == 2)
    #expect(gomoku.rankingUnavailable, "차가운 창에서는 관전 404 가 순위표를 접어야 한다")
    #expect(gomoku.hasLoadedRanking, "차가운 창에서 '받은 것'으로 세지 않으면 화면이 로딩 문구를 영영 든다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 관전_404_뒤에는_같은_판을_다시_눌러도_요청이_안_나간다() async {
    // 없으면: **죽은 버튼이 404 를 무한히 반복한다.** 404 뒤 `stopWatching()` 이 `spectating` 을 비우므로 재진입 가드가
    // 다시 통과하고, 화면의 칩만 잠그면 스토어를 직접 부르는 길(딥링크·다른 호출부)은 그대로 열려 있다.
    // 반증 에이전트가 5회 연타로 404 왕복을 실측한 그 자리다(2026-10-01).
    let (_, gomoku, host) = makeWatchStore("door-guard") { rpc, _, _ in
        rpc == "gomoku_watch" ? pgrst202 : baseReply(rpc)
    }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))

    gomoku.startWatching(matchID: watchedID)
    await watchWait { gomoku.spectating == nil }
    #expect(count(host, "gomoku_watch") == 1)
    #expect(gomoku.watchUnavailable, "404 가 관전 입구를 잠그는 신호를 안 세웠다")

    // 같은 판을 5번 더 누른다 — **문 앞**에서 막히므로 요청은 그대로 1건이고 빈 판도 서지 않는다.
    for _ in 0..<5 {
        gomoku.startWatching(matchID: watchedID)
        await settle(gomoku)
    }
    try? await Task.sleep(for: .milliseconds(200))
    #expect(count(host, "gomoku_watch") == 1, "잠긴 관전을 5번 더 눌렀더니 요청이 \(count(host, "gomoku_watch"))건 나갔다")
    #expect(gomoku.spectating == nil, "잠긴 채로 빈 판이 섰다")
    #expect(gomoku.notice == GomokuNoticeText.watchUnavailable, "막으면서 아무 말도 안 한다 — 눌러도 반응 없는 칩이 된다")
    #expect(count(host, "gomoku_state") == 0)

    // 기준선이 달라야 이 테스트가 산다: 잠금이 풀리면(60초 순위 폴이 하는 일) **같은 손짓이** 요청을 낸다.
    gomoku.watchUnavailable = false
    gomoku.startWatching(matchID: watchedID)
    await watchWait { count(host, "gomoku_watch") == 2 }
    #expect(count(host, "gomoku_watch") == 2, "잠금을 풀었는데도 [관전] 이 요청을 못 낸다 — 가드가 문을 아예 닫아 버렸다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 관전_잠금은_60초_순위_폴이_한_번_풀어_준다() async {
    // 없으면: **서버가 올라와도 로그아웃까지 관전이 잠긴 채 남는다.** 잠금을 내리는 곳은 성공한 관전(`applyWatch`)인데
    // 문 앞 가드가 그 관전을 시작조차 못 하게 막아 자기가 자기를 열 수 없다 — 60초 순위 폴이 유일한 열쇠다.
    let (_, gomoku, host) = makeWatchStore("unlock") { rpc, _, _ in
        switch rpc {
        case "gomoku_watch": return pgrst202
        case "gomoku_ranking": return reply(rankedRankingPayload())
        default: return baseReply(rpc)
        }
    }
    let clock = Clock()
    let t0 = clock.now
    gomoku.clock = { clock.now }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))
    // 60초 창의 기준점을 t0 으로 잡는다 — 기본값(`distantPast`)이면 첫 폴이 무조건 풀어 버려 ①이 아무것도 증명하지 못한다.
    await gomoku.loadRanking()
    #expect(count(host, "gomoku_ranking") == 1)

    gomoku.startWatching(matchID: watchedID)
    await watchWait { gomoku.spectating == nil }
    #expect(gomoku.watchUnavailable && count(host, "gomoku_watch") == 1)

    // ① 60초가 안 지난 폴은 잠금을 안 푼다(감지기 기준선 — 여기서 풀리면 ②가 영원히 초록이다).
    clock.now = t0.addingTimeInterval(30)
    await gomoku.pollSpectatorFeatures(at: clock.now)
    #expect(gomoku.watchUnavailable, "30초 폴이 관전 잠금을 풀었다")
    #expect(count(host, "gomoku_ranking") == 1, "30초 폴이 순위를 다시 읽었다 — 주기 상수를 안 본다")

    // ② 60초가 지난 폴이 잠금을 푼다.
    clock.now = t0.addingTimeInterval(61)
    await gomoku.pollSpectatorFeatures(at: clock.now)
    #expect(count(host, "gomoku_ranking") == 2, "60초 폴이 순위를 안 읽었다 — 이 갈래를 아예 안 지났다")
    #expect(gomoku.watchUnavailable == false, "60초가 지나도 관전 잠금이 그대로다 — 서버가 올라와도 로그아웃까지 잠긴다")

    // ③ 풀린 문으로 [관전] 이 실제로 요청을 낸다 — 깃발만 내리고 문이 안 열리면 뜻이 없다.
    gomoku.startWatching(matchID: watchedID)
    await watchWait { count(host, "gomoku_watch") == 2 }
    #expect(count(host, "gomoku_watch") == 2, "잠금이 풀렸는데 [관전] 이 요청을 못 낸다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 순위가_0행이어도_관전_404_는_순위_깃발을_안_세운다() async throws {
    // 없으면: `if ranking == nil` 가드를 `ranking?.entries.isEmpty != false` 로 넓혀 **0행 순위표까지 "곧 열려요"로
    // 접어도 초록이다.** 0행 응답도 서버에 `gomoku_ranking` 이 있다는 증거이고(전적을 컷으로 초기화한 직후가 실제로 0행이다),
    // 접으면 사용자는 제 전적이 사라진 줄 안다.
    let (_, gomoku, host) = makeWatchStore("zero-row") { rpc, _, _ in
        rpc == "gomoku_watch" ? pgrst202 : baseReply(rpc)        // baseReply 의 순위는 0행 ok 다
    }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))
    await gomoku.loadRanking()
    let board = try #require(gomoku.ranking, "0행 응답도 표를 세운다 — nil 이면 이 테스트가 '한 번도 못 받은 창'과 안 갈린다")
    #expect(board.entries.isEmpty, "픽스처: 비었지만 nil 은 아닌 표")
    #expect(gomoku.rankingUnavailable == false && gomoku.hasLoadedRanking)

    gomoku.startWatching(matchID: watchedID)
    await watchWait { gomoku.spectating == nil }
    #expect(gomoku.watchUnavailable, "0행 창에서도 관전 404 는 관전 입구를 잠근다")
    #expect(gomoku.notice == GomokuNoticeText.watchUnavailable)
    #expect(gomoku.rankingUnavailable == false,
            "0행 순위표를 들고 있는데 관전 404 가 '곧 열려요'로 접었다 — 0행도 서버에 gomoku_ranking 이 있다는 증거다")
    #expect(gomoku.ranking == board, "관전 404 가 0행 표를 버렸다")
    #expect(count(host, "gomoku_watch") == 1)

    // 기준선이 달라야 이 테스트가 산다: **표가 아예 없는**(nil) 차가운 창에서는 같은 404 가 깃발을 세운다.
    // 문 앞 가드는 60초 폴이 푸는 것이라 여기서는 손으로 풀어 같은 404 를 한 번 더 받는다(가드 자체는 위 테스트가 본다).
    gomoku.ranking = nil
    gomoku.hasLoadedRanking = false
    gomoku.watchUnavailable = false
    gomoku.startWatching(matchID: otherID)
    await watchWait { gomoku.rankingUnavailable }
    #expect(count(host, "gomoku_watch") == 2)
    #expect(gomoku.rankingUnavailable, "표가 없는 차가운 창에서는 관전 404 가 순위표를 접어야 한다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 관전_5xx_가_연속되면_관전을_내리고_연결_안내를_남기며_성공은_연속을_끊는다() async {
    // 없으면: 일시 장애·오프라인에서 빈 판 "관전 중"이 2초 폴링을 영영 돌거나, 반대로 한 번의 흔들림에 판이 사라져도 초록이다.
    let (_, gomoku, host) = makeWatchStore("5xx") { rpc, _, index in
        guard rpc == "gomoku_watch" else { return baseReply(rpc) }
        // 실패·실패·성공·실패·실패·실패 — 세 번째 연속 실패에서만 내린다.
        return index == 2 ? reply(watchPayload()) : GomokuStubProtocol.Reply(status: 500, body: "{}")
    }
    let clock = Clock()
    let t0 = clock.now
    gomoku.clock = { clock.now }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))
    func tick(_ offset: TimeInterval) async {
        clock.now = t0.addingTimeInterval(offset)
        await gomoku.pollTick(at: clock.now)
        await settle(gomoku)
    }

    gomoku.startWatching(matchID: watchedID)
    await watchWait { count(host, "gomoku_watch") == 1 }
    await settle(gomoku)
    #expect(gomoku.spectating != nil && gomoku.notice == nil, "첫 실패에 판을 내렸다")
    #expect(gomoku.watchRuntime.watchFailureStreak == 1)
    await tick(2.1)
    #expect(count(host, "gomoku_watch") == 2)
    #expect(gomoku.spectating != nil, "두 번째 실패에 판을 내렸다")
    await tick(4.2)
    #expect(count(host, "gomoku_watch") == 3)
    #expect(gomoku.spectating?.hasServerState == true, "성공 응답이 반영되지 않았다")
    #expect(gomoku.watchRuntime.watchFailureStreak == 0, "성공이 연속 실패를 끊지 않았다")
    await tick(6.3)
    await tick(8.4)
    #expect(count(host, "gomoku_watch") == 5)
    #expect(gomoku.spectating != nil, "성공 뒤 두 번의 실패에 판을 내렸다")
    await tick(10.5)
    #expect(count(host, "gomoku_watch") == 6)
    #expect(gomoku.spectating == nil, "\(GomokuStore.watchFailureLimit)번 연속 실패인데 빈 판이 남았다")
    #expect(gomoku.notice == GomokuNoticeText.checkConnection)
    await tick(20)
    await tick(100)
    #expect(count(host, "gomoku_watch") == 6, "내려간 관전이 계속 폴링했다")
    #expect(gomoku.rankingUnavailable == false, "5xx 는 미배포가 아니다")
    #expect(count(host, "gomoku_state") == 0)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func not_found_와_unsupported_client_는_관전을_내리고_안내한다() async {
    // 없으면: 끝난 지 오래된 판·숨김 격리 판에서 not_found 를 받고도 빈 판이 2초마다 같은 답을 영영 묻는다.
    final class Mode: @unchecked Sendable { var status = "not_found" }
    let mode = Mode()
    let (_, gomoku, host) = makeWatchStore("refused") { rpc, _, _ in
        rpc == "gomoku_watch" ? reply(["status": mode.status, "server_now_ms": nowMs()]) : baseReply(rpc)
    }
    let clock = Clock()
    let t0 = clock.now
    gomoku.clock = { clock.now }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))

    gomoku.startWatching(matchID: watchedID)
    await watchWait { gomoku.spectating == nil }
    #expect(gomoku.notice == GomokuNoticeText.watchGone)
    for offset in [2.1, 4.2, 60] {
        clock.now = t0.addingTimeInterval(offset)
        await gomoku.pollTick(at: clock.now)
    }
    #expect(count(host, "gomoku_watch") == 1)

    mode.status = "unsupported_client"
    clock.now = t0.addingTimeInterval(100)
    gomoku.startWatching(matchID: otherID)
    await watchWait { gomoku.spectating == nil }
    #expect(gomoku.notice == GomokuNoticeText.updateMine)
    #expect(count(host, "gomoku_watch") == 2)
    #expect(count(host, "gomoku_state") == 0)
}

// MARK: - 6. 관전 중 last_finished (C20)

@MainActor
@Test(.gomokuDefaultsCleanup)
func 관전_중에는_받은함의_last_finished_가_결과_화면으로_넘기지_못한다() async {
    // 없으면: 관전 중 받은함이 최근 끝난 내 판을 세워 결과 카드가 관전 위로 튀어나오고(또는 W0 의 didSet 이 관전을 내려 보던 판이 사라지고),
    //        그 id 를 본 것으로 적어 [나가기] 뒤엔 그 결과를 영영 못 봐도 초록이다.
    let (_, gomoku, host) = makeWatchStore("last-finished") { rpc, _, _ in
        switch rpc {
        case "gomoku_watch": return reply(watchPayload())
        case "gomoku_inbox": return reply(inboxPayload(lastFinished: myFinishedID))
        case "gomoku_state": return reply(myStatePayload(id: myFinishedID, finished: true))
        default: return baseReply(rpc)
        }
    }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))
    gomoku.startWatching(matchID: watchedID)
    await watchWait { gomoku.spectating?.hasServerState == true }

    await gomoku.loadInbox()
    #expect(gomoku.phase == .lobby, "관전 중에 결과 화면으로 넘어갔다")
    #expect(gomoku.match == nil)
    #expect(gomoku.spectating?.id == watchedID, "관전이 내려갔다")
    #expect(count(host, "gomoku_state") == 0, "관전 중엔 last_finished 로 판을 읽지 않는다")
    #expect(!gomoku.shownResultIDs.contains(myFinishedID), "본 것으로 적으면 나간 뒤 영영 안 보인다")

    // 나가면 그 결과가 뒤늦게 선다.
    gomoku.leaveWatch()
    await watchWait { gomoku.match?.id == myFinishedID }
    #expect(gomoku.match?.id == myFinishedID && gomoku.phase == .result)
    #expect(gomoku.spectating == nil)
    #expect(count(host, "gomoku_state") == 1)
}

// MARK: - 7. 수순 증분 · 구멍 · 마감 보정

@MainActor
@Test(.gomokuDefaultsCleanup)
func p_since_seq_는_반영한_수_번호이고_구멍이_나면_처음부터_다시_받는다() async throws {
    // 없으면: 매번 since 0 으로 전부 받거나(예산), 구멍 난 기록을 그대로 쌓아 마지막 수·자동 착수 점이 틀려도 초록이다.
    // 스텁은 호출 순서(index)로 가른다: ①since0 → 2수 ②since2 → 4번 수만(3번이 빠진 구멍) ③since0 → 4수 전부 ④since4 → 없음.
    let (_, gomoku, host) = makeWatchStore("since") { rpc, _, index in
        guard rpc == "gomoku_watch" else { return baseReply(rpc) }
        switch index {
        case 0: return reply(watchPayload(moves: twoMoves))
        case 1: return reply(watchPayload(moves: [fourMoves[3]], allMoves: fourMoves, turn: "black"))
        case 2: return reply(watchPayload(moves: fourMoves, turn: "black"))
        default: return reply(watchPayload(moves: [], allMoves: fourMoves, turn: "black"))
        }
    }
    let clock = Clock()
    let t0 = clock.now
    gomoku.clock = { clock.now }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))
    func tick(_ offset: TimeInterval) async {
        clock.now = t0.addingTimeInterval(offset)
        await gomoku.pollTick(at: clock.now)
        await settle(gomoku)
    }
    func sinces() -> [Int?] { GomokuStubProtocol.calls(host: host, rpc: "gomoku_watch").map { $0.json["p_since_seq"] as? Int } }

    gomoku.startWatching(matchID: watchedID)
    await watchWait { gomoku.spectating?.hasServerState == true }
    await settle(gomoku)
    #expect(sinces() == [0])
    #expect(gomoku.spectating?.appliedSeq == 2)

    // 구멍 응답 → 같은 회차 안에서 곧바로 since 0 재요청.
    await tick(2.1)
    #expect(sinces() == [0, 2, 0], "구멍이 났는데 처음부터 다시 받지 않았다")
    let live = try #require(gomoku.spectating)
    #expect(live.appliedSeq == 4 && live.moveCount == 4)
    #expect(live.lastMove == point(8, 8))
    #expect(live.board[point(7, 8)] == .black && live.board[point(8, 8)] == .white)
    #expect(gomoku.watchRuntime.watchWantsFull == false, "전체를 실어 온 응답이 표시를 내린다")

    await tick(4.2)
    #expect(sinces() == [0, 2, 0, 4])
    #expect(gomoku.spectating?.appliedSeq == 4)
    // 요청 본문 모양 — 키 집합이 함수를 고른다.
    let body = try #require(GomokuStubProtocol.calls(host: host, rpc: "gomoku_watch").last).json
    #expect(Set(body.keys) == ["p_protocol", "p_match_id", "p_since_seq"])
    #expect(body["p_match_id"] as? String == watchedID)
    #expect(count(host, "gomoku_state") == 0)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 관전_마감은_서버_시계로_보정되고_같은_차례의_흔들림은_무시한다() async throws {
    // 없으면: 기기 시계가 5초 빠른 맥의 관전자가 "25초 남음"을 보고, 조회마다 몇 ms 다른 마감으로 창 루트가 2초마다 다시 그려져도 초록이다.
    let clock = Clock()
    let t0 = clock.now
    let serverNow = t0.timeIntervalSince1970 * 1000 + 5_000          // 서버가 5초 앞서 있다
    let (_, gomoku, host) = makeWatchStore("deadline") { rpc, _, index in
        guard rpc == "gomoku_watch" else { return baseReply(rpc) }
        // 같은 차례를 다시 읽었는데 마감이 0.3초 다르다(보정 오차) — 두 번째 응답. 서버 시계도 기기 시계처럼 2.1초 간다
        // (안 보내면 오프셋이 5→2.9초로 다시 잡혀 마감이 2.4초 움직인다 — 첫 실행에서 그렇게 빨갰다).
        let elapsedMs: Double = index == 0 ? 0 : 2_100
        let jitter: Double = index == 0 ? 0 : 300
        return reply(watchPayload(moves: [], allMoves: twoMoves,
                                  deadlineMs: serverNow + 30_000 + jitter, serverNowMs: serverNow + elapsedMs))
    }
    gomoku.clock = { clock.now }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))

    gomoku.startWatching(matchID: watchedID)
    await watchWait { gomoku.spectating?.hasServerState == true }
    await settle(gomoku)
    let first = try #require(gomoku.spectating?.deadline)
    #expect(abs(first.timeIntervalSince(t0.addingTimeInterval(30))) <= 0.25, "마감이 서버 시계 어긋남(5초)만큼 보정되지 않았다")

    clock.now = t0.addingTimeInterval(2.1)
    await gomoku.pollTick(at: clock.now)
    await settle(gomoku)
    #expect(count(host, "gomoku_watch") == 2)
    #expect(gomoku.spectating?.deadline == first, "같은 차례의 0.3초 흔들림에 마감을 갈았다")
}

// MARK: - 8. 내 판이 서면 관전이 내려간다 · 내 판 중엔 진입 불가

@MainActor
@Test(.gomokuDefaultsCleanup)
func 내_판이_서면_관전이_내려가고_내_판_중에는_관전에_들어가지_않는다() async {
    // 없으면: 수락된 내 판 뒤에서 관전 폴링이 겹쳐 돌거나, 대국·AI 판 중에 [관전] 이 판을 갈아 치워도 초록이다.
    let (_, gomoku, host) = makeWatchStore("own-match") { rpc, _, _ in
        rpc == "gomoku_watch" ? reply(watchPayload()) : baseReply(rpc)
    }
    let clock = Clock()
    let t0 = clock.now
    gomoku.clock = { clock.now }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))
    func tick(_ offset: TimeInterval) async {
        clock.now = t0.addingTimeInterval(offset)
        await gomoku.pollTick(at: clock.now)
        await settle(gomoku)
    }

    gomoku.startWatching(matchID: watchedID)
    await watchWait { gomoku.spectating?.hasServerState == true }
    let generation = gomoku.watchRuntime.watchGeneration

    // 진행 중 1:1 판이 들어온다(수락·신호·받은함 어느 경로든 match 대입).
    gomoku.applyState(decode(GomokuStatePayload.self, myStatePayload(id: myActiveID)))
    #expect(gomoku.match?.id == myActiveID && gomoku.phase == .playing)
    #expect(gomoku.spectating == nil, "내 판이 섰는데 관전이 남았다")
    #expect(gomoku.watchRuntime.watchGeneration > generation, "내 판이 서도 세대가 안 올라 늦은 관전 응답이 살아 있다")
    let before = count(host, "gomoku_watch")
    await tick(2.1)
    await tick(4.2)
    #expect(count(host, "gomoku_watch") == before, "내 판 뒤에서 관전 폴링이 돌았다")

    // 진행 중인 내 판 중에는 들어가지 않는다.
    gomoku.startWatching(matchID: watchedID)
    #expect(gomoku.spectating == nil)
    #expect(count(host, "gomoku_watch") == before)

    // 끝난 판의 결과 화면(.result)에서도 들어가지 않는다 — 관전 화면은 로비 자리다.
    gomoku.applyState(decode(GomokuStatePayload.self, myStatePayload(id: myActiveID, finished: true)))
    #expect(gomoku.phase == .result)
    gomoku.startWatching(matchID: watchedID)
    #expect(gomoku.spectating == nil)

    // AI 판 중에도.
    gomoku.backToLobby()
    gomoku.aiMoveChooser = { _, _ in nil }
    gomoku.startAIMatch(humanColor: .black)
    #expect(gomoku.isAIMatch)
    gomoku.startWatching(matchID: watchedID)
    #expect(gomoku.spectating == nil)
    #expect(count(host, "gomoku_watch") == before)
    gomoku.discardAIGame()
}

// MARK: - 9. 리셋

@MainActor
@Test(.gomokuDefaultsCleanup)
func 로그아웃_리셋은_관전·순위를_비우고_늦은_응답을_버린다() async {
    // 없으면: 로그아웃 뒤 앞 계정이 보던 남의 판·순위표가 다음 사람 화면에 남거나, 늦게 온 응답이 그것을 되살려도 초록이다.
    let (_, gomoku, host) = makeWatchStore("reset") { rpc, _, _ in
        switch rpc {
        case "gomoku_watch": return reply(watchPayload(), delay: 0.4)
        case "gomoku_ranking":
            return reply(["status": "ok", "server_now_ms": nowMs(), "record_since_ms": NSNull(),
                          "me": ["rank": 1, "wins": 3, "losses": 0, "draws": 0, "points": 3],
                          "rows": [["rank": 1, "user_id": me, "display_name": "나", "avatar_url": NSNull(), "character": "aing",
                                    "center": NSNull(), "wins": 3, "losses": 0, "draws": 0, "points": 3]]])
        default: return baseReply(rpc)
        }
    }
    gomoku.isWindowVisible = true
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload()))
    await gomoku.loadRanking()
    #expect(gomoku.ranking?.entries.count == 1 && gomoku.hasLoadedRanking)
    gomoku.startWatching(matchID: watchedID)
    await watchWait { count(host, "gomoku_watch") == 1 }

    gomoku.reset()
    #expect(gomoku.spectating == nil && gomoku.ranking == nil)
    #expect(!gomoku.hasLoadedRanking && !gomoku.rankingLoadFailed && !gomoku.rankingUnavailable)
    #expect(gomoku.spectatorFeaturesEnabled, "주 스위치는 배선 값이라 리셋이 건드리지 않는다")
    try? await Task.sleep(for: .milliseconds(700))
    #expect(gomoku.spectating == nil, "로그아웃 뒤 도착한 앞 계정의 관전 응답이 살아났다")
    #expect(count(host, "gomoku_watch") == 1)
    #expect(count(host, "gomoku_state") == 0)
}

// MARK: - 10. 순수 매퍼

@Test
func 관전_매퍼는_다른_판·모르는_status_를_거르고_끝난_판을_무승부까지_읽는다() throws {
    // 없으면: 매퍼가 pending 응답을 판으로 그리거나 무승부를 승패로 읽어도 스토어 테스트는 스텁 픽스처 모양만 지나 초록이다.
    let previous = GomokuSpectateState(id: watchedID)
    let blackUser = GomokuUser(id: third, displayName: "셋째", avatarURL: nil, characterID: nil, isWorking: true, isCapable: true, inMatch: true)
    let whiteUser = GomokuUser(id: rival, displayName: "라이벌", avatarURL: nil, characterID: nil, isWorking: true, isCapable: true, inMatch: true)

    let other = decode(GomokuWatchResponse.self, watchPayload(id: otherID))
    #expect(GomokuStore.spectateState(applying: other, to: previous, requestedSince: 0,
                                      black: blackUser, white: whiteUser, deadline: nil, startedAt: nil) == nil)
    let pending = decode(GomokuWatchResponse.self, watchPayload(status: "pending", moves: []))
    #expect(GomokuStore.spectateState(applying: pending, to: previous, requestedSince: 0,
                                      black: blackUser, white: whiteUser, deadline: nil, startedAt: nil) == nil)

    let draw = decode(GomokuWatchResponse.self, watchPayload(status: "finished", moves: fourMoves, result: "draw", endReason: "board_full"))
    let mapped = try #require(GomokuStore.spectateState(applying: draw, to: previous, requestedSince: 0,
                                                        black: blackUser, white: whiteUser, deadline: Date(), startedAt: nil))
    #expect(mapped.needsFull == false)
    #expect(mapped.state.isFinished && mapped.state.winner == nil && mapped.state.endReason == .boardFull)
    #expect(mapped.state.deadline == nil, "끝난 판에 마감이 남았다")
    #expect(mapped.state.black == blackUser && mapped.state.white == whiteUser)
    #expect(mapped.state.appliedSeq == 4 && mapped.state.lastMove == point(8, 8))

    // 자동 착수 점은 기록에서 온다 — 회색 점 자리와 마지막 수 표시.
    var autoMoves = fourMoves
    autoMoves[3].auto = true
    let auto = decode(GomokuWatchResponse.self, watchPayload(moves: autoMoves, blackAutoStreak: 0, whiteAutoStreak: 1))
    let withAuto = try #require(GomokuStore.spectateState(applying: auto, to: previous, requestedSince: 0,
                                                          black: blackUser, white: whiteUser, deadline: nil, startedAt: nil))
    #expect(withAuto.state.autoPoints == [point(8, 8)] && withAuto.state.lastMoveWasAuto)
    #expect(withAuto.state.whiteAutoStreak == 1)

    // 구멍(since > 0, 첫 seq ≠ applied + 1)은 이전 값 그대로 + needsFull.
    let gap = decode(GomokuWatchResponse.self, watchPayload(moves: [fourMoves[3]], allMoves: fourMoves))
    var twoApplied = previous
    twoApplied.appliedSeq = 2
    twoApplied.moveCount = 2
    let gapFromTwo = try #require(GomokuStore.spectateState(applying: gap, to: twoApplied, requestedSince: 2,
                                                            black: blackUser, white: whiteUser, deadline: nil, startedAt: nil))
    #expect(gapFromTwo.needsFull && gapFromTwo.state == twoApplied)
}

// MARK: - 11. 소스 계약 (주석을 걷어낸 뒤)

@Test
func 관전_소스_계약_훅은_스토어_본문에_있고_관전_파일은_대국_경로를_쓰지_않는다() throws {
    // 없으면: 누가 pollTick 의 관전 분기를 지우거나, 관전 파일이 편의로 gomoku_state/applyState 를 재사용해 참가자 게이트에 걸리고 채팅이 실려 와도
    //        스텁 테스트의 픽스처 모양만 지나 초록이다(주석을 안 걷으면 설명을 지워야만 초록이 되는 테스트가 된다 — C22).
    let code = gomokuCollapsed(V0317ShopTests.stripped(try CheckCoreSourceLayout.joinedSplitSource("GomokuStore.swift")))
    let reset = try #require(gomokuBody(of: "func reset()", in: code))
    #expect(reset.contains("dismissWindow?()"), "첫 등장 매칭이 스토어의 reset 이 아닌 다른 몸통을 읽었다")
    #expect(reset.contains("spectating = nil") && reset.contains("watchRuntime.clear()"), "로그아웃이 관전·순위 장부를 안 비운다")
    let poll = try #require(gomokuBody(of: "func pollTick(at now: Date)", in: code))
    #expect(poll.contains("pollSpectatorFeatures(at: now)"), "폴링 걸음에 관전·순위 분기가 없다")
    let show = try #require(gomokuBody(of: "func windowDidShow()", in: code))
    #expect(show.contains("spectatorWindowDidShow(at: now)"), "창이 다시 보일 때 즉시 한 번이 없다(C14)")
    let hide = try #require(gomokuBody(of: "func windowDidHide()", in: code))
    // 끝난 판 갈래 **하나만** 허용한다 — 진행 중인 관전까지 지우면 최소화만 해도 로비로 떨어진다(C14); 끝난 판을 남기면 다음에 창을 열 때 낡은 남의 판이 선다.
    #expect(hide.contains("if spectating?.isFinished == true { stopWatching() }"),
            "끝난 판을 관전한 채 창을 닫아도 관전이 남는다 — 다음에 창을 열면 로비 대신 낡은 남의 판이 선다")
    #expect(hide.components(separatedBy: "spectating").count - 1 == 1 && hide.components(separatedBy: "stopWatching").count - 1 == 1,
            "창 닫기가 진행 중인 관전까지 지운다 — 최소화만 해도 로비로 떨어진다(C14)")
    let inbox = try #require(gomokuBody(of: "func applyInbox(", in: code))
    #expect(inbox.contains("spectating == nil,"), "관전 중 last_finished 가 결과 화면으로 넘어간다(C20)")
    let matchDecl = try #require(code.range(of: "var match: GomokuMatchState? {"))
    #expect(code[matchDecl.upperBound...].prefix(700).contains("spectating = nil"), "내 판이 서도 관전이 안 내려간다")
    let state = try #require(gomokuBody(of: "func applyState(", in: code))
    #expect(state.contains("noteOwnMatchFinishedForRanking()"), "내 판이 끝나도 순위를 다시 안 읽는다(C16)")

    let watchFile = CheckCoreSourceLayout.coreDirectory.appendingPathComponent("GomokuStoreWatch.swift")
    let watch = V0317ShopTests.stripped(try String(contentsOf: watchFile, encoding: .utf8))
    #expect(!watch.contains("gomokuState("), "관전이 gomoku_state 를 재사용한다 — 참가자 게이트에 걸리고 대국자 채팅이 실려 온다")
    #expect(!watch.contains("applyState("), "관전 응답을 대국 적용 경로에 넣는다 — my_color 부재로 .ignored 거나 대국 화면이 선다")
    #expect(!watch.contains("gomokuChat"), "관전 파일에 채팅 호출이 있다(U4)")
    #expect(watch.contains("watchGeneration") && watch.contains("bumpWatchGeneration()"), "세대 가드가 없다(C13)")
    #expect(watch.contains("canPollSpectatorFeatures"), "창·주 스위치 술어를 안 본다(C11·C14)")
    #expect(watch.contains("databaseSchemaMissing"), "PGRST202 경로가 없다(C17)")
    #expect(!watch.contains("UserDefaults"), "관전 상태를 디스크에 남긴다")
}
