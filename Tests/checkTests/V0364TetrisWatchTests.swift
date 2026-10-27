import Foundation
import Testing
@testable import CheckCore

// v0.3.64 — 테트리스 **관전**(`tetris_watch` / `tetris_watch_live`)과 **관전자 수**(`watchers`) 계약.
// **모양이 아니라 결과를 잰다** — 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가" 다(관례).
//
// 서버는 스텁이다(`GomokuStubProtocol` — 테스트마다 고유 호스트라 병렬 스위트가 서로의 기록을 덮지 않는다).
// 창 폴링 루프는 3,600초로 재우고 `pollTick(at:)` 을 직접 밟는다(결정적).

// MARK: - 하네스

private let twMe = "00000000-0000-0000-0000-0000000000c3"
private let twAlice = "00000000-0000-0000-0000-0000000000a1"
private let twBob = "00000000-0000-0000-0000-0000000000b2"
private let twMatchA = "7e7e0000-0000-4000-8000-0000000000aa"
private let twMatchB = "7e7e0000-0000-4000-8000-0000000000bb"
private let twWall0 = Date(timeIntervalSince1970: 1_800_000_000)
private var twNowMs: Double { twWall0.timeIntervalSince1970 * 1000 }

/// 올바른 판 글자(200글자 · `.IJLOSTZG`).
private let twEmptyBoard = String(repeating: ".", count: 200)
private let twFilledBoard = String(repeating: ".", count: 196) + "IIII"
/// 길이가 하나 모자라다.
private let twShortBoard = String(repeating: ".", count: 199)
/// 길이는 200인데 글자 집합 밖(`X`)이 섞였다.
private let twAlienBoard = String(repeating: ".", count: 199) + "X"

private struct TWError: Error {}

private func twOpt(_ value: Any?) -> Any { value ?? NSNull() }

@MainActor
private final class TWHost: GomokuStoreHost {
    var session: SupabaseSession?
    var sessionGeneration = 0
    let service: SupabaseWorkService
    var realtimeState: RealtimeState = .idle(.disabled)
    var rubyBalance: Int?

    init(service: SupabaseWorkService, userID: String) {
        self.service = service
        session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
    }

    func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        guard let session else { throw TWError() }
        return try await operation(session)
    }

    func classifyAuthError(_ error: Error) -> AuthErrorDisposition { .transient }
}

@MainActor
private enum TWRetention {
    /// 스토어는 호스트를 **약참조**로 든다 — 테스트가 버리면 요청이 한 건도 안 나간다.
    static var hosts: [TWHost] = []
}

private final class TWClock: @unchecked Sendable {
    var wall: Date = twWall0
    var uptime: TimeInterval = 1_000
}

/// rpc 이름별 응답 스크립트: 줄 세운 응답이 먼저, 그다음 고정 응답.
private final class TWScript: @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [String: [GomokuStubProtocol.Reply]] = [:]
    private var standing: [String: GomokuStubProtocol.Reply] = [:]

    func enqueue(_ rpc: String, _ body: String, status: Int = 200, delay: TimeInterval = 0) {
        lock.lock()
        queued[rpc, default: []].append(GomokuStubProtocol.Reply(status: status, body: body, delay: delay))
        lock.unlock()
    }

    func stand(_ rpc: String, _ body: String, status: Int = 200, delay: TimeInterval = 0) {
        lock.lock()
        standing[rpc] = GomokuStubProtocol.Reply(status: status, body: body, delay: delay)
        lock.unlock()
    }

    var handler: GomokuStubProtocol.Handler {
        { [self] rpc, _, _ in self.reply(rpc) }
    }

    private func reply(_ rpc: String) -> GomokuStubProtocol.Reply? {
        lock.lock()
        defer { lock.unlock() }
        if var line = queued[rpc], !line.isEmpty {
            let next = line.removeFirst()
            queued[rpc] = line
            return next
        }
        return standing[rpc]
    }
}

private func twJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func twCount(_ host: String, _ rpc: String) -> Int { GomokuStubProtocol.count(host: host, rpc: rpc) }

/// PGRST202 본문(`serviceError` 가 "schema cache" 를 보고 `.databaseSchemaMissing` 으로 접는다).
private func twPGRST202(_ function: String) -> String {
    #"{"code":"PGRST202","details":"Searched for the function public."# + function
        + #" with parameters, but no matches were found in the schema cache.","hint":null,"#
        + #""message":"Could not find the function public."# + function + #" in the schema cache"}"#
}

/// 관전 봉투의 한 자리(명세 §1.6 의 `a`·`b`).
private func twSide(_ userID: String, name: String, board: String? = twEmptyBoard, lines: Int = 0,
                    pending: Int = 0, sent: Int = 0, topped: Bool = false) -> [String: Any] {
    ["user": ["id": userID, "display_name": name, "avatar_url": NSNull(), "character": "jelly",
              "center": NSNull()],
     "board": twOpt(board), "lines": lines, "pending": pending, "garbage_sent": sent,
     "topped_out": topped, "last_seen_ms": twNowMs - 500]
}

/// `tetris_watch` / `tetris_watch_live` 응답(명세 §1.6 의 키 그대로).
private func twWatch(status: String = "ok", id: String = twMatchA, matchStatus: String = "active",
                     stake: Int = 5, startedMs: Double? = twNowMs - 10_000,
                     result: String? = nil, reason: String? = nil, finishedMs: Double? = nil,
                     winner: String? = nil, omitsWinner: Bool = false,
                     a: [String: Any]? = nil, b: [String: Any]? = nil,
                     watchers: Int? = nil) -> String {
    guard status == "ok" else { return twJSON(["status": status, "server_now_ms": twNowMs]) }
    // `omitsWinner` 는 **칸 자체가 없는 옛 서버**를 재현한다(null 을 실은 무승부와는 다른 상태다).
    var match: [String: Any] = ["id": id, "stake": stake, "started_ms": twOpt(startedMs), "status": matchStatus,
                                "result": twOpt(result), "reason": twOpt(reason), "finished_ms": twOpt(finishedMs)]
    if !omitsWinner { match["winner"] = twOpt(winner) }
    var envelope: [String: Any] = [
        "status": "ok", "server_now_ms": twNowMs,
        "match": match,
        "a": a ?? twSide(twAlice, name: "앨리스"),
        "b": b ?? twSide(twBob, name: "밥"),
    ]
    if let watchers { envelope["watchers"] = watchers }
    return twJSON(envelope)
}

/// 로비 응답(관전 씨앗이 되는 "지금 대결 중" 한 줄 포함).
private func twLobby(matchID: String = twMatchA, watchers: Int? = nil) -> String {
    var row: [String: Any] = [
        "id": matchID,
        "a": ["id": twAlice, "display_name": "앨리스"],
        "b": ["id": twBob, "display_name": "밥"],
        "stake": 5, "started_at_ms": twNowMs - 10_000,
    ]
    if let watchers { row["watchers"] = watchers }
    return twJSON([
        "status": "ok", "server_now_ms": twNowMs, "stakes": [3, 5, 10],
        "me": ["ruby_balance": 100, "wins": 0, "losses": 0, "draws": 0,
               "active_match_id": NSNull(), "incoming": [] as [Any], "outgoing": NSNull()],
        "users": [] as [Any],
        "matches": [row],
    ])
}

/// 대국자 상태 봉투(§1.8 — `watchers` 한 칸이 더 실린다).
private func twState(id: String = twMatchB, status: String = "active", watchers: Int? = nil) -> [String: Any] {
    var payload: [String: Any] = [
        "match_id": id, "status": status, "stake": 3, "seed": 4_242,
        "server_now_ms": twNowMs, "accepted_at_ms": twNowMs - 2_000,
        "start_at_ms": twNowMs - 1_000, "ready_deadline_ms": twNowMs + 28_000,
        "max_end_ms": twNowMs + 479_000, "finished_at_ms": NSNull(),
        "me": ["id": twMe, "display_name": "나", "ready": true, "seq": 3, "board": twEmptyBoard,
               "lines": 0, "garbage_sent": 0, "garbage_applied": 0, "pending": 0,
               "last_seen_ms": twNowMs, "topped_out": false],
        "opponent": ["id": twAlice, "display_name": "앨리스", "ready": true, "seq": 3, "board": twEmptyBoard,
                     "lines": 0, "garbage_sent": 0, "garbage_applied": 0, "pending": 0,
                     "last_seen_ms": twNowMs, "topped_out": false],
        "result": NSNull(), "winner": NSNull(), "end_reason": NSNull(), "ruby_balance": 50,
    ]
    if let watchers { payload["watchers"] = watchers }
    return payload
}

private func twDecodeState(_ object: [String: Any]) throws -> TetrisStatePayload {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(TetrisStatePayload.self, from: Data(twJSON(object).utf8))
}

private func twDecodeWatch(_ text: String) throws -> TetrisWatchResponse {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(TetrisWatchResponse.self, from: Data(text.utf8))
}

/// 관전을 켠 스토어 한 벌(주 스위치 on · 창 보임 · 폴링 루프 재움).
@MainActor
private func twMake(_ label: String, script: TWScript,
                    spectatorOn: Bool = true) -> (TetrisDuelStore, TWClock, String) {
    let host = "v0364-tw-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: script.handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let owner = TWHost(service: service, userID: twMe)
    TWRetention.hosts.append(owner)
    let store = TetrisDuelStore(host: owner)
    let clock = TWClock()
    store.clock = { clock.wall }
    store.uptime = { clock.uptime }
    store.pollStepSeconds = 3_600
    store.gameLoopStepSeconds = 3_600
    store.spectatorFeaturesEnabled = spectatorOn
    store.isWindowVisible = true
    return (store, clock, host)
}

/// 나가 있는 요청이 스텁에 닿을 때까지(상한 2초).
private func twAwaitCall(_ host: String, _ rpc: String, atLeast: Int) async -> Bool {
    for _ in 0..<400 {
        if twCount(host, rpc) >= atLeast { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

// MARK: - 주 스위치

@MainActor
@Test("v0364 관전 주 스위치가 꺼져 있으면 요청이 한 건도 안 나간다")
func v0364TetrisWatchMasterSwitchOffSendsNoRequests() async throws {
    // 없으면: 배선을 안 한 기기(폰 구버전)가 2초마다 `tetris_watch_live` 를 당긴다 — 꺼짐이 기본값인 뜻이 사라진다.
    let script = TWScript()
    script.stand("tetris_watch_live", twWatch(watchers: 3))
    script.stand("tetris_watch", twWatch())
    script.stand("tetris_lobby", twLobby())
    let (off, clock, host) = twMake("switch-off", script: script, spectatorOn: false)

    off.startWatching(matchID: twMatchA)
    #expect(off.spectating == nil, "주 스위치가 꺼졌는데 관전에 들어갔다")
    await off.refreshWatch()
    clock.wall = twWall0.addingTimeInterval(120)
    await off.pollTick(at: clock.wall)

    #expect(twCount(host, "tetris_watch_live") == 0)
    #expect(twCount(host, "tetris_watch") == 0)
    #expect(off.spectatorCount == 0)

    // ★ 기준선이 달라야 한다 — 켜면 같은 걸음이 실제로 요청을 낸다.
    let (on, onClock, onHost) = twMake("switch-on", script: script)
    on.startWatching(matchID: twMatchA)
    #expect(on.spectating?.id == twMatchA)
    _ = await twAwaitCall(onHost, "tetris_watch_live", atLeast: 1)
    onClock.wall = twWall0.addingTimeInterval(120)
    await on.refreshWatch()
    #expect(twCount(onHost, "tetris_watch_live") >= 1, "켠 스토어도 요청을 안 냈다 — 위 0건은 뜻이 없다")
}

// MARK: - 세대 · 판 id 두 자물쇠

@MainActor
@Test("v0364 세대가 다른 늦은 관전 응답은 새 관전을 덮지 않는다")
func v0364TetrisWatchStaleGenerationResponseIsDropped() async throws {
    // 없으면: A 판을 나가 다시 들어간(또는 B 로 바꾼) 사이 먼저 띄운 응답이 늦게 닿아 화면을 한 틱 되돌린다.
    // 두 응답의 match id 를 **같게** 두어 세대 자물쇠만으로 걸러지는지 잰다(id 자물쇠가 가리지 못하게).
    let script = TWScript()
    script.enqueue("tetris_watch_live",
                   twWatch(a: twSide(twAlice, name: "앨리스", lines: 5), watchers: 1), delay: 0.25)
    script.enqueue("tetris_watch_live",
                   twWatch(a: twSide(twAlice, name: "앨리스", board: twFilledBoard, lines: 9), watchers: 2))
    let (store, _, host) = twMake("generation", script: script)
    store.isWindowVisible = false            // 진입이 스스로 조회를 띄우지 않게(직접 밟는다)
    store.startWatching(matchID: twMatchA)
    #expect(store.spectating?.id == twMatchA)

    let late = Task { @MainActor in await store.refreshWatch() }
    #expect(await twAwaitCall(host, "tetris_watch_live", atLeast: 1), "첫 조회가 안 나갔다")

    store.stopWatching()                     // 세대 +1
    store.startWatching(matchID: twMatchA)   // 세대 +1
    await store.refreshWatch()
    #expect(store.spectating?.a.lines == 9, "둘째 응답이 안 들어왔다")

    await late.value
    #expect(store.spectating?.a.lines == 9, "늦은 응답(lines=5)이 새 관전을 덮었다 — 세대 자물쇠가 죽었다")
    #expect(store.spectating?.a.board == twFilledBoard)
    #expect(store.spectatorCount == 2, "늦은 응답의 관전자 수(1)가 새 값을 덮었다")
}

@MainActor
@Test("v0364 match id 가 다른 관전 응답은 버려진다")
func v0364TetrisWatchForeignMatchIDResponseIsDropped() async throws {
    // 없으면: 로비에서 판을 바꾼 직후 앞 판 응답이 새 판 화면에 남의 판을 그린다.
    let script = TWScript()
    let (store, _, _) = twMake("foreign-id", script: script)
    store.isWindowVisible = false
    store.startWatching(matchID: twMatchA)

    let mine = try twDecodeWatch(twWatch(id: twMatchA, a: twSide(twAlice, name: "앨리스", lines: 4), watchers: 2))
    store.applyWatch(mine)
    #expect(store.spectating?.a.lines == 4)
    #expect(store.spectatorCount == 2)

    let foreign = try twDecodeWatch(twWatch(id: twMatchB, a: twSide(twAlice, name: "앨리스", lines: 77),
                                            watchers: 99))
    store.applyWatch(foreign)
    #expect(store.spectating?.a.lines == 4, "다른 판 응답이 들어왔다")
    #expect(store.spectatorCount == 2, "다른 판의 관전자 수가 들어왔다")
    #expect(store.notice == nil, "다른 판 응답은 조용히 버린다(안내를 남기지 않는다)")
}

// MARK: - 꼬리 밖 · 결과 날조 금지

@MainActor
@Test("v0364 not_found 면 관전을 내리고 안내 한 줄을 남긴다")
func v0364TetrisWatchNotFoundDropsWatch() async throws {
    // 없으면: 끝난 지 3분이 넘은 판에서 빈 화면이 2초 폴링을 영영 돈다.
    let script = TWScript()
    script.stand("tetris_watch_live", twWatch(status: "not_found"))
    let (store, _, _) = twMake("not-found", script: script)
    store.isWindowVisible = false
    store.startWatching(matchID: twMatchA)
    await store.refreshWatch()

    #expect(store.spectating == nil, "꼬리 밖인데 관전이 남았다")
    #expect(store.notice == TetrisDuelNoticeText.watchGone)
    #expect(store.spectatorCount == 0, "관전이 내려갔는데 관전자 수가 남았다")
    #expect(!store.watchUnavailable, "not_found 는 함수가 없다는 뜻이 아니다 — 입구를 잠그면 안 된다")
    #expect(store.availability == .available, "관전 한 번 실패로 1:1 테트리스 전체가 잠겼다")
}

@MainActor
@Test("v0364 시간이 다 돼 보여도 관전이 결과를 지어내지 않는다")
func v0364TetrisWatchDoesNotInventResultWhenTimeIsUp() async throws {
    // 없으면: 상한(480초)을 넘긴 active 판에서 관전 화면이 혼자 승패를 그려 관전자에게 거짓말한다.
    let script = TWScript()
    // 시작 600초 전 = 상한을 120초 넘겼는데 서버는 여전히 active 이고 결과 칸이 비어 있다.
    script.stand("tetris_watch_live",
                 twWatch(matchStatus: "active", startedMs: twNowMs - 600_000,
                         a: twSide(twAlice, name: "앨리스", lines: 12, topped: false),
                         b: twSide(twBob, name: "밥", lines: 3), watchers: 2))
    let (store, clock, _) = twMake("no-invented-result", script: script)
    store.isWindowVisible = false
    store.startWatching(matchID: twMatchA)
    await store.refreshWatch()

    let watch = try #require(store.spectating)
    #expect(!watch.isFinished, "서버가 안 닫은 판을 끝난 것으로 만들었다")
    #expect(watch.result == nil, "결과를 지어냈다")
    #expect(watch.endReason == nil, "사유를 지어냈다")
    #expect(watch.finishedAt == nil)
    #expect(store.notice == nil)
    store.isWindowVisible = true
    #expect(store.shouldPollWatch, "안 끝난 판인데 폴링이 멈췄다 — 서버가 닫는 순간을 못 본다")

    // ★ 기준선: 서버가 **실제로** 닫으면 그때는 결과가 선다.
    let closed = try twDecodeWatch(twWatch(matchStatus: "finished", startedMs: twNowMs - 600_000,
                                           result: "draw", reason: "time_cap", finishedMs: twNowMs,
                                           watchers: 2))
    store.applyWatch(closed)
    #expect(store.spectating?.isFinished == true)
    #expect(store.spectating?.result == "draw")
    #expect(store.spectating?.endReason == .timeCap)
    #expect(store.spectating?.finishedAt != nil)
    #expect(!store.shouldPollWatch, "끝난 판을 계속 폴링한다")
}

@MainActor
@Test("v0364 승자는 match.winner 로만 가른다 — result 로 역산하지 않는다")
func v0364TetrisWatchNamesTheWinnerOnlyFromTheWinnerColumn() async throws {
    // 없으면: 관전 화면이 'challenger_win' 을 보고 a·b 중 **아무나** 승자로 그린다. 관전 봉투에는 누가
    // challenger 인지가 없으므로 그 추측은 **절반이 틀린다** — 관전자에게 대놓고 거짓말하는 자리다.
    // 그래서 승자를 아는 길은 서버가 직접 싣는 uuid 한 칸뿐이고, 모르면 아무 말도 하지 않는 게 맞다.
    let script = TWScript()
    // ★ 같은 result('challenger_win')에 승자 uuid 만 반대로 준다. 역산 코드가 있으면 둘 중 하나는 반드시 틀린다.
    script.stand("tetris_watch_live",
                 twWatch(matchStatus: "finished", startedMs: twNowMs - 300_000,
                         result: "challenger_win", reason: "topout", finishedMs: twNowMs,
                         winner: twBob, watchers: 1))
    let (store, _, _) = twMake("winner-from-column", script: script)
    store.isWindowVisible = false
    store.startWatching(matchID: twMatchA)
    await store.refreshWatch()

    let won = try #require(store.spectating)
    #expect(won.winnerUserID == twBob)
    #expect(won.bWon, "서버가 밥을 승자로 실었는데 b 자리가 이긴 것으로 안 선다")
    #expect(!won.aWon, "result 가 'challenger_win' 이라고 a 자리를 승자로 지어냈다")

    // 같은 result, 승자만 앨리스 — 자리 판정이 뒤집혀야 한다.
    let flipped = try twDecodeWatch(twWatch(matchStatus: "finished", startedMs: twNowMs - 300_000,
                                            result: "challenger_win", reason: "topout", finishedMs: twNowMs,
                                            winner: twAlice, watchers: 1))
    store.applyWatch(flipped)
    #expect(store.spectating?.aWon == true, "승자 uuid 를 바꿨는데 자리 판정이 그대로다 — result 를 보고 있다")
    #expect(store.spectating?.bWon == false)

    // 무승부: 서버가 null 을 싣는다 — 둘 다 거짓이어야 한다.
    let drawn = try twDecodeWatch(twWatch(matchStatus: "finished", startedMs: twNowMs - 300_000,
                                          result: "draw", reason: "time_cap", finishedMs: twNowMs))
    store.applyWatch(drawn)
    #expect(store.spectating?.winnerUserID == nil)
    #expect(store.spectating?.aWon == false && store.spectating?.bWon == false, "무승부에 승자를 세웠다")

    // 칸 자체가 없는 **옛 서버**: 모르는 것이지 무승부가 아니다 — 그래도 둘 다 거짓이고 앱은 살아야 한다.
    let old = try twDecodeWatch(twWatch(matchStatus: "finished", startedMs: twNowMs - 300_000,
                                        result: "opponent_win", reason: "resign", finishedMs: twNowMs,
                                        omitsWinner: true))
    store.applyWatch(old)
    #expect(store.spectating?.winnerUserID == nil, "없는 칸에서 승자를 지어냈다")
    #expect(store.spectating?.aWon == false && store.spectating?.bWon == false)
    #expect(store.spectating?.isFinished == true, "승자를 몰라도 끝난 것은 끝난 것이다")

    // 진행 중이면 승자 칸이 와도 비운다(서버가 닫기 전까지 승패는 없다).
    let live = try twDecodeWatch(twWatch(matchStatus: "active", startedMs: twNowMs - 30_000, winner: twAlice))
    store.applyWatch(live)
    #expect(store.spectating?.winnerUserID == nil, "안 끝난 판에 승자를 세웠다")
}

// MARK: - 판 글자

@MainActor
@Test("v0364 망가진 판 글자는 그 자리만 접고 나머지는 산다")
func v0364TetrisWatchBrokenBoardFoldsOnlyThatSide() async throws {
    // 없으면: 길이·글자 집합이 어긋난 판 하나가 관전 화면을 통째로 비우거나(또는 그리다 터지거나) 한다.
    let script = TWScript()
    let (store, _, _) = twMake("broken-board", script: script)
    store.isWindowVisible = false
    store.startWatching(matchID: twMatchA)

    // 먼저 멀쩡한 두 판을 받아 둔다(접힘이 "원래 없었다" 가 아님을 가른다).
    store.applyWatch(try twDecodeWatch(twWatch(
        a: twSide(twAlice, name: "앨리스", board: twFilledBoard, lines: 7),
        b: twSide(twBob, name: "밥", board: twFilledBoard, lines: 2), watchers: 1)))
    #expect(store.spectating?.a.board == twFilledBoard)

    // 길이가 모자란 판.
    store.applyWatch(try twDecodeWatch(twWatch(
        a: twSide(twAlice, name: "앨리스", board: twShortBoard, lines: 8, pending: 4),
        b: twSide(twBob, name: "밥", board: twFilledBoard, lines: 3), watchers: 1)))
    var watch = try #require(store.spectating)
    #expect(watch.a.board == nil, "199글자 판을 그대로 들었다")
    #expect(watch.a.cells == nil)
    #expect(watch.a.lines == 8, "판이 깨졌다고 그 자리의 숫자까지 버렸다")
    #expect(watch.a.pending == 4)
    #expect(watch.b.board == twFilledBoard, "반대쪽 판까지 접었다")
    #expect(watch.b.cells?.count == 20)
    #expect(watch.b.cells?.first?.count == 10)

    // 길이는 맞는데 글자 집합 밖.
    store.applyWatch(try twDecodeWatch(twWatch(
        a: twSide(twAlice, name: "앨리스", board: twAlienBoard, lines: 9),
        b: twSide(twBob, name: "밥", board: twEmptyBoard, lines: 4), watchers: 1)))
    watch = try #require(store.spectating)
    #expect(watch.a.board == nil, "`X` 가 섞인 200글자를 그대로 들었다")
    #expect(watch.a.cells == nil)
    #expect(watch.b.board == twEmptyBoard)

    // 멀쩡한 판이 다시 오면 되돌아온다(접힘이 영구 상태가 아니다).
    store.applyWatch(try twDecodeWatch(twWatch(
        a: twSide(twAlice, name: "앨리스", board: twFilledBoard, lines: 10), watchers: 1)))
    #expect(store.spectating?.a.board == twFilledBoard)
    #expect(store.spectating?.a.cells?.count == 20)
}

@MainActor
@Test("v0364 아직 보고가 없는 자리는 판이 nil 이고 그래도 관전은 산다")
func v0364TetrisWatchNullBoardKeepsWatchAlive() async throws {
    // 없으면: 준비 전(보고 0건) 판에 들어가면 null 판이 디코드를 통째로 깨뜨린다.
    let script = TWScript()
    let (store, _, _) = twMake("null-board", script: script)
    store.isWindowVisible = false
    store.startWatching(matchID: twMatchA)
    store.applyWatch(try twDecodeWatch(twWatch(a: twSide(twAlice, name: "앨리스", board: nil), watchers: 1)))

    let watch = try #require(store.spectating)
    #expect(watch.a.board == nil)
    #expect(watch.a.cells == nil)
    #expect(watch.b.board == twEmptyBoard)
    #expect(watch.hasServerState)
    #expect(watch.a.user?.displayName == "앨리스")
    #expect(watch.b.user?.displayName == "밥")
    #expect(watch.stake == 5)
}

// MARK: - 관전자 수

@MainActor
@Test("v0364 관전 응답의 watchers 는 없으면 0 · 있으면 값이다")
func v0364TetrisWatchersDefaultZeroAndCarryValue() async throws {
    // 없으면: 옛 서버 응답에서 디코드가 throw 하거나(비옵셔널), 있는 수를 못 읽는다.
    let script = TWScript()
    let (store, _, _) = twMake("watchers-value", script: script)
    store.isWindowVisible = false
    store.startWatching(matchID: twMatchA)

    store.applyWatch(try twDecodeWatch(twWatch(watchers: 7)))
    #expect(store.spectatorCount == 7)

    store.applyWatch(try twDecodeWatch(twWatch()))        // `watchers` 키가 아예 없다(옛 서버)
    #expect(store.spectatorCount == 0, "없는 수를 앞 값으로 들고 있었다")

    store.applyWatch(try twDecodeWatch(twWatch(watchers: 4)))
    #expect(store.spectatorCount == 4)
    store.stopWatching()
    #expect(store.spectatorCount == 0, "관전이 내려갔는데 수가 남았다")
}

@MainActor
@Test("v0364 로비 '지금 대결 중' 줄의 watchers 는 없으면 0 · 있으면 값이다")
func v0364TetrisLobbyWatchersDecode() async throws {
    // 없으면: 로비 카드가 관전자 수를 못 받아 [관전] 칩 옆이 영영 비거나, 옛 서버에서 터진다.
    let script = TWScript()
    let (store, _, _) = twMake("lobby-watchers", script: script)

    script.stand("tetris_lobby", twLobby(watchers: 4))
    await store.refreshLobby()
    #expect(store.liveMatches.first?.watchers == 4)

    script.stand("tetris_lobby", twLobby())               // 키 없음(옛 서버)
    await store.refreshLobby()
    #expect(store.liveMatches.first?.watchers == 0, "없는 수를 0 으로 안 읽었다")
}

@MainActor
@Test("v0364 내 판 상태의 watchers 는 같은 spectatorCount 로 들어오고 판이 내려가면 0 이다")
func v0364TetrisStateWatchersFeedSpectatorCount() async throws {
    // 없으면: 대국자 본인 화면이 "N명이 보고 있어요" 를 영영 못 본다(한 칸으로 합친다는 계약이 죽는다).
    let script = TWScript()
    script.stand("tetris_lobby", twLobby())
    let (store, _, _) = twMake("state-watchers", script: script)

    store.applyState(try twDecodeState(twState(watchers: 5)))
    #expect(store.match?.id == twMatchB)
    #expect(store.spectatorCount == 5)

    store.applyState(try twDecodeState(twState()))        // 키 없음
    #expect(store.spectatorCount == 0)

    store.applyState(try twDecodeState(twState(watchers: 2)))
    #expect(store.spectatorCount == 2)
    store.clearMatch()
    #expect(store.spectatorCount == 0, "대국이 내려갔는데 수가 남았다")

    store.applyState(try twDecodeState(twState(watchers: 3)))
    #expect(store.spectatorCount == 3)
    store.reset()
    #expect(store.spectatorCount == 0, "로그아웃했는데 앞 사람 판의 관전자 수가 남았다")
    #expect(store.spectating == nil)
    #expect(store.spectatorFeaturesEnabled, "reset 이 배선 값을 껐다 — 재로그인하면 관전이 영영 안 열린다")
}

// MARK: - 두 깃발은 겸업하지 않는다

@MainActor
@Test("v0364 tetris_watch_live 가 없으면 수만 접고 관전 입구는 안 잠긴다")
func v0364TetrisWatchLiveMissingFoldsCountOnly() async throws {
    // 없으면: 관전자 수 한 칸이 없다는 이유로 [관전] 칩이 통째로 잠긴다(체스가 데인 겸업 사고).
    let script = TWScript()
    script.stand("tetris_watch_live", twPGRST202("tetris_watch_live"), status: 404)
    script.stand("tetris_watch", twWatch(a: twSide(twAlice, name: "앨리스", board: twFilledBoard, lines: 6)))
    script.stand("tetris_lobby", twLobby())
    let (store, _, host) = twMake("live-missing", script: script)
    store.isWindowVisible = false
    store.startWatching(matchID: twMatchA)
    await store.refreshWatch()

    #expect(store.spectatorCountUnavailable, "접힘 깃발이 안 섰다")
    #expect(!store.watchUnavailable, "수 한 칸 때문에 관전 입구를 잠갔다")
    #expect(store.availability == .available, "1:1 테트리스 전체가 잠겼다")
    #expect(store.notice == nil, "접힘은 사용자에게 할 말이 아니다")
    // 같은 한 번의 조회 안에서 옛 길로 접어 **판을 실제로 받았다**.
    #expect(twCount(host, "tetris_watch") == 1, "옛 길로 안 접었다")
    #expect(store.spectating?.a.lines == 6, "접힌 길에서 판을 못 받았다")
    #expect(store.spectatorCount == 0, "관전자 수를 모르는데 숫자를 지어냈다")

    // 그 뒤로는 계속 옛 길이다(없는 함수를 매번 두드리지 않는다).
    await store.refreshWatch()
    #expect(twCount(host, "tetris_watch_live") == 1, "없는 `*_live` 를 또 불렀다")
    #expect(twCount(host, "tetris_watch") == 2)
    #expect(store.spectating != nil, "관전이 내려갔다")

    // 입구도 그대로 열려 있다 — 다른 판으로 바로 들어간다.
    store.stopWatching()
    store.startWatching(matchID: twMatchB)
    #expect(store.spectating?.id == twMatchB, "관전 입구가 잠겼다 — 접힘 깃발이 입구 깃발을 겸업했다")
}

@MainActor
@Test("v0364 tetris_watch 자체가 없으면 관전 입구를 잠그고 테트리스 전체는 안 잠근다")
func v0364TetrisWatchMissingLocksEntryOnly() async throws {
    // 없으면: 관전 칩이 활성인 채 남아 누를 때마다 404 를 반복하거나(잠금 없음),
    // 반대로 `noteServerMissing()` 을 불러 1:1 테트리스 전체가 "곧 열려요" 로 잠긴다.
    let script = TWScript()
    script.stand("tetris_watch_live", twPGRST202("tetris_watch_live"), status: 404)
    script.stand("tetris_watch", twPGRST202("tetris_watch"), status: 404)
    script.stand("tetris_lobby", twLobby())
    let (store, clock, host) = twMake("watch-missing", script: script)
    store.isWindowVisible = false
    store.startWatching(matchID: twMatchA)
    await store.refreshWatch()

    #expect(store.spectating == nil, "함수가 없는데 관전이 남았다")
    #expect(store.watchUnavailable, "관전 입구가 안 잠겼다")
    #expect(store.notice == TetrisDuelNoticeText.unavailable)
    #expect(store.availability == .available, "관전 함수 하나 때문에 1:1 테트리스 전체가 잠겼다")

    // 잠긴 동안은 문 앞에서 막는다 — 요청이 더 안 나간다.
    let before = twCount(host, "tetris_watch")
    store.startWatching(matchID: twMatchA)
    #expect(store.spectating == nil)
    #expect(twCount(host, "tetris_watch") == before, "잠긴 채로 또 두드렸다")

    // 로비 주기(30초)에 한 번 풀어 준다 — 안 풀면 서버가 올라와도 로그아웃까지 잠긴 채 남는다.
    store.isWindowVisible = true
    clock.wall = twWall0.addingTimeInterval(TetrisDuelStore.lobbyPollSeconds + 1)
    await store.pollTick(at: clock.wall)
    #expect(!store.watchUnavailable, "잠금이 스스로 안 풀린다")
}

// MARK: - 내 판이 서면 관전은 내려간다

@MainActor
@Test("v0364 내 판이 서면 관전이 내려가고 관전자 수는 내 판의 것으로 갈린다")
func v0364TetrisWatchStandsDownWhenMyMatchStarts() async throws {
    // 없으면: 남의 판을 보던 화면 위로 내 판이 겹쳐 서고, 남의 판 관전자 수가 내 판 수로 둔갑한다.
    let script = TWScript()
    script.stand("tetris_lobby", twLobby())
    let (store, _, _) = twMake("stand-down", script: script)
    store.isWindowVisible = false
    store.startWatching(matchID: twMatchA)
    store.applyWatch(try twDecodeWatch(twWatch(watchers: 9)))
    #expect(store.spectating != nil)
    #expect(store.spectatorCount == 9)
    let generation = store.watchRuntime.watchGeneration

    store.applyState(try twDecodeState(twState(id: twMatchB, watchers: 1)))
    #expect(store.spectating == nil, "내 판이 섰는데 관전이 남았다")
    #expect(store.watchRuntime.watchGeneration > generation, "세대를 안 올렸다 — 나가 있던 관전 응답이 되살아난다")
    #expect(store.spectatorCount == 1, "남의 판 관전자 수가 내 판 수로 남았다")

    // 내 판이 진행 중이면 관전에 들어가지도 않는다.
    store.startWatching(matchID: twMatchA)
    #expect(store.spectating == nil)
}

// MARK: - 폴링 · 창

@MainActor
@Test("v0364 관전 폴링은 창이 보일 때만 2초마다 돈다")
func v0364TetrisWatchPollsOnlyWhenWindowVisible() async throws {
    // 없으면: 숨은 창이 2초마다 남의 판을 당기거나(무료 플랜), 보이는 창이 아예 안 당겨 판이 멎는다.
    let script = TWScript()
    script.stand("tetris_watch_live", twWatch(watchers: 1))
    script.stand("tetris_lobby", twLobby())
    let (store, clock, host) = twMake("poll", script: script)
    store.isWindowVisible = false
    store.startWatching(matchID: twMatchA)
    await store.refreshWatch()
    let first = twCount(host, "tetris_watch_live")
    #expect(first == 1)

    // 창이 안 보이면 폴링이 한 걸음도 안 간다.
    clock.wall = twWall0.addingTimeInterval(30)
    await store.pollTick(at: clock.wall)
    #expect(twCount(host, "tetris_watch_live") == first, "숨은 창이 관전을 당겼다")

    // 보이면 2초 주기로 돈다.
    store.isWindowVisible = true
    await store.pollTick(at: clock.wall)
    #expect(twCount(host, "tetris_watch_live") == first + 1)
    await store.pollTick(at: clock.wall)
    #expect(twCount(host, "tetris_watch_live") == first + 1, "2초를 안 기다리고 또 당겼다")
    clock.wall = twWall0.addingTimeInterval(30 + TetrisDuelStore.watchPollSeconds)
    await store.pollTick(at: clock.wall)
    #expect(twCount(host, "tetris_watch_live") == first + 2)
}

@MainActor
@Test("v0364 창을 정말 닫으면 관전이 내려간다")
func v0364TetrisWatchWindowCloseStopsWatching() async throws {
    // 없으면: 한 시간 뒤 창을 열어도 로비 대신 낡은 남의 판이 선다.
    let script = TWScript()
    let (store, _, _) = twMake("window-close", script: script)
    store.isWindowVisible = false
    store.startWatching(matchID: twMatchA)
    store.applyWatch(try twDecodeWatch(twWatch(watchers: 2)))
    #expect(store.spectating != nil)

    store.windowDidClose()
    #expect(store.spectating == nil)
    #expect(store.spectatorCount == 0)
}

// MARK: - 연속 실패

@MainActor
@Test("v0364 관전 조회가 연달아 실패하면 관전을 내리고 안내 한 줄을 남긴다")
func v0364TetrisWatchFailureStreakStopsWatching() async throws {
    // 없으면: 끊긴 망에서 빈 "관전 중" 화면이 2초 폴링을 영영 돈다.
    let script = TWScript()
    script.stand("tetris_watch_live", #"{"message":"boom"}"#, status: 500)
    let (store, _, _) = twMake("streak", script: script)
    store.isWindowVisible = false
    store.startWatching(matchID: twMatchA)

    for _ in 0..<(TetrisDuelStore.watchFailureLimit - 1) {
        await store.refreshWatch()
        #expect(store.spectating != nil, "문턱 전에 관전을 내렸다")
    }
    await store.refreshWatch()
    #expect(store.spectating == nil, "문턱을 넘었는데 관전이 남았다")
    #expect(store.notice == TetrisDuelNoticeText.checkConnection)
    #expect(!store.watchUnavailable, "5xx 는 함수가 없다는 뜻이 아니다")
    #expect(!store.spectatorCountUnavailable, "5xx 로 관전자 수를 접었다")
}
