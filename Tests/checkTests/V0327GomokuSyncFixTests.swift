import Foundation
import Observation
import Testing
@testable import check

// v0.3.27 오목 스토어 — 2차 검증(클라 적대 검토 set #1 · 계약 검토 set #4 · 서버 set #2 교착)에서 나온 결함의 정식 회귀.
//
// 리뷰 재현(zrev_R1~R5)을 옮긴 것이 앞의 다섯이다. 기대값은 전부 "올바른 동작"이고, 고치기 전 코드에서 각각 빨갛다
// (재현 로그: review-client/build1.log). 스텁이 못 잡는 것(실제 배달·두 기기 순서)은 통합자의 두 계정 e2e 몫이다.

private let sfMe = "00000000-0000-0000-0000-0000000000a1"
private let sfRival = "00000000-0000-0000-0000-0000000000b2"
private let sfMatchA = "aaaaaaaa-2222-3333-4444-555555555555"
private let sfMatchB = "bbbbbbbb-2222-3333-4444-555555555555"

private func sfJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func sfNowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

private func sfBoard(_ stones: [(Int, Int, Character)]) -> String {
    var cells = Array(repeating: Character("."), count: 225)
    for (x, y, c) in stones { cells[y * 15 + x] = c }
    return String(cells)
}

/// 실서버 gomoku__state 모양(board 포함).
private func sfState(
    id: String = sfMatchA, moveCount: Int, stones: [(Int, Int, Character)] = [], moves: [[String: Any]] = [],
    turn: String?, status: String = "active", myColor: String = "black",
    deadlineMs: Double? = nil, serverNowMs: Double? = nil, result: String? = nil, endReason: String? = nil,
    ruby: Int? = 20
) -> [String: Any] {
    let now = sfNowMs()
    return [
        "status": "ok",
        "match": [
            "id": id, "status": status, "stake": 5,
            "black": myColor == "black" ? sfMe : sfRival, "white": myColor == "black" ? sfRival : sfMe,
            "challenger": sfMe, "opponent": sfRival, "move_count": moveCount,
            "turn": turn ?? NSNull(), "deadline_ms": deadlineMs ?? (now + 30_000),
            "result": result ?? NSNull(), "end_reason": endReason ?? NSNull(), "winner": NSNull(),
            "invite_expires_ms": now, "board": sfBoard(stones)
        ] as [String: Any],
        "moves": moves,
        "my_color": myColor,
        "opponent": ["user_id": sfRival, "display_name": "라이벌", "avatar_url": NSNull(), "character": "aing"],
        "ruby_balance": ruby.map { $0 as Any } ?? NSNull(),
        "server_now_ms": serverNowMs ?? now
    ]
}

private func sfDecode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(T.self, from: Data(sfJSON(object).utf8))
}

private let sfPeer = GomokuUser(id: sfRival, displayName: "라이벌", avatarURL: nil, characterID: nil,
                                isWorking: true, isCapable: true, inMatch: false)

private let sfDeadlockBody = #"{"code":"40P01","details":null,"hint":null,"message":"deadlock detected"}"#

@MainActor
private enum SFRetention { static var stores: [WorkTimerStore] = [] }

@MainActor
private final class SFTally {
    var presents = 0
    var attentionRequests = 0
    var attentions: [GomokuAttention] = []
    var fired = false
}

@MainActor
private func sfMakeStore(_ label: String, handler: @escaping GomokuStubProtocol.Handler) -> (WorkTimerStore, GomokuStore, String) {
    let host = "v0327-sf-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: GomokuTestDefaults.make("v0327-sf"), workspaceNotifications: nil)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: sfMe)
    SFRetention.stores.append(store)
    return (store, store.gomoku, host)
}

@MainActor
private func sfWait(_ timeout: TimeInterval = 20, _ condition: @MainActor () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
private func sfWire(_ gomoku: GomokuStore) -> SFTally {
    let tally = SFTally()
    gomoku.presentWindow = { tally.presents += 1 }
    gomoku.requestAttention = { tally.attentionRequests += 1 }
    gomoku.onAttention = { tally.attentions.append($0) }
    return tally
}

// MARK: - C1 판 시작 · 내 차례 알림 (zrev_R1)

@MainActor
@Test(.gomokuDefaultsCleanup)
func 신청자는_창이_안_보여도_상대가_수락해_판이_시작되면_창과_주의와_말풍선을_받는다() async {
    let (_, gomoku, host) = sfMakeStore("start") { rpc, _, _ in
        switch rpc {
        case "gomoku_inbox":
            return .init(body: sfJSON(["status": "ok", "incoming": [], "outgoing": NSNull(),
                                       "active_match_id": sfMatchA, "server_now_ms": sfNowMs()]))
        case "gomoku_state":
            return .init(body: sfJSON(sfState(moveCount: 0, turn: "black")))
        case "gomoku_lobby":
            return .init(body: sfJSON(["status": "ok", "users": []]))
        default: return nil
        }
    }
    let tally = sfWire(gomoku)
    gomoku.outgoing = GomokuInvite(id: sfMatchA, peer: sfPeer, stake: 5, expiresAt: Date().addingTimeInterval(50))
    #expect(gomoku.isWindowVisible == false)

    gomoku.handleSignal()   // 서버 gomoku_respond 가 신청자에게 보내는 ring
    await sfWait { gomoku.phase == .playing && gomoku.syncTask == nil }

    #expect(gomoku.phase == .playing)
    #expect(gomoku.match?.turn == gomoku.match?.myColor, "내가 흑 — 30초 안에 둬야 한다")
    #expect(gomoku.outgoing == nil)
    #expect(tally.presents == 1, "판이 시작됐는데 창을 띄우지 않았다(presentWindow \(tally.presents)회)")
    #expect(tally.attentionRequests == 1, "앱이 뒤에 있으면 주의를 끌어야 한다")
    #expect(tally.attentions == [GomokuAttention(kind: .matchStarted, matchID: sfMatchA, opponentName: "라이벌", moveCount: 0)])
    #expect(gomoku.notice == nil, "수락으로 사라진 보낸 신청을 거절로 안내했다")

    // 같은 판을 다시 읽어도 다시 띄우거나 다시 말하지 않는다.
    gomoku.handleSignal()
    await sfWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_state") >= 2 && gomoku.syncTask == nil }
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 2)
    #expect(tally.presents == 1 && tally.attentionRequests == 1 && tally.attentions.count == 1)
}

@MainActor
@Test
func 창이_안_보일_때_상대가_두면_내_차례_말풍선을_같은_기록_수에_한_번만_연다() {
    let gomoku = GomokuStore()
    let tally = sfWire(gomoku)
    let b1: [(Int, Int, Character)] = [(7, 7, "b")]
    gomoku.applyState(sfDecode(GomokuStatePayload.self, sfState(moveCount: 1, stones: b1, turn: "white")))
    #expect(tally.presents == 1, "진행 중 판을 처음 받았다 — 창을 띄운다")
    #expect(tally.attentions.isEmpty, "상대 차례에 내 차례라고 말했다")

    let b2 = b1 + [(8, 7, "w")]
    let mine = sfDecode(GomokuStatePayload.self, sfState(moveCount: 2, stones: b2, turn: "black"))
    gomoku.applyState(mine)
    #expect(tally.attentions == [GomokuAttention(kind: .myTurn, matchID: sfMatchA, opponentName: "라이벌", moveCount: 2)])
    gomoku.applyState(mine)
    #expect(tally.attentions.count == 1, "같은 차례를 다시 읽고 또 말했다")
    #expect(tally.presents == 1, "진행 중인 판에서 창을 또 띄웠다")

    // 창이 보이는 동안 온 차례는 말하지 않고, 창을 닫은 뒤 같은 차례를 다시 읽어도 뒤늦게 말하지 않는다.
    gomoku.isWindowVisible = true
    let b4 = b2 + [(6, 6, "b"), (9, 9, "w")]
    let visibleTurn = sfDecode(GomokuStatePayload.self, sfState(moveCount: 4, stones: b4, turn: "black"))
    gomoku.applyState(visibleTurn)
    gomoku.isWindowVisible = false
    gomoku.applyState(visibleTurn)
    #expect(tally.attentions.count == 1)

    // 판이 끝나면 말하지 않는다.
    gomoku.applyState(sfDecode(GomokuStatePayload.self, sfState(
        moveCount: 5, stones: b4 + [(5, 5, "b")], turn: nil, status: "finished", result: "white_win", endReason: "resign")))
    #expect(tally.attentions.count == 1 && tally.presents == 1)
}

// MARK: - C2 늦게 온 옛 상태 (zrev_R2)

@MainActor
@Test(.gomokuDefaultsCleanup)
func 착수보다_먼저_읽힌_옛_상태가_늦게_와도_방금_둔_수를_지우지_않는다() async throws {
    let twoStones: [(Int, Int, Character)] = [(7, 7, "b"), (8, 7, "w")]
    let threeStones: [(Int, Int, Character)] = twoStones + [(6, 6, "b")]
    let (_, gomoku, host) = sfMakeStore("late-state") { rpc, _, _ in
        switch rpc {
        case "gomoku_state":
            // 착수보다 먼저 서버가 읽은 스냅숏(move_count 2, 흑 차례) — 응답만 늦다.
            return .init(body: sfJSON(sfState(moveCount: 2, stones: twoStones, turn: "black")), delay: 0.6)
        case "gomoku_move":
            let state = sfState(moveCount: 3, stones: threeStones,
                                moves: [["seq": 3, "color": "black", "kind": "stone", "x": 6, "y": 6]], turn: "white")
            var body = state
            body["black_passed"] = false
            body["state"] = state
            return .init(body: sfJSON(body))
        default: return nil
        }
    }
    let seed = sfState(moveCount: 2, stones: twoStones,
                       moves: [["seq": 1, "color": "black", "kind": "stone", "x": 7, "y": 7],
                               ["seq": 2, "color": "white", "kind": "stone", "x": 8, "y": 7]], turn: "black")
    gomoku.applyState(sfDecode(GomokuStatePayload.self, seed))
    #expect(gomoku.match?.moveCount == 2)

    let pending = Task { await gomoku.refreshMatch() }
    await sfWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 1 }
    await gomoku.place(GomokuPoint(x: 6, y: 6)!)
    #expect(gomoku.match?.moveCount == 3, "착수 응답 직후")
    await pending.value

    #expect(gomoku.match?.moveCount == 3, "늦은 상태 응답이 move_count 를 \(gomoku.match?.moveCount ?? -1) 로 되돌렸다")
    #expect(gomoku.match?.board[GomokuPoint(x: 6, y: 6)!] == .black, "방금 둔 돌이 판에서 사라졌다")
    #expect(gomoku.match?.turn == .white, "상대 차례가 내 차례로 되돌아갔다")

    // 끝남은 순서와 무관하게 받는다.
    let finished = sfDecode(GomokuStatePayload.self, sfState(
        moveCount: 2, stones: twoStones, turn: nil, status: "finished", result: "black_win", endReason: "timeout"))
    #expect(gomoku.applyState(finished) == .applied)
    #expect(gomoku.match?.isFinished == true)
}

// MARK: - C4 다른 판 조회 (zrev_R3)

@MainActor
@Test(.gomokuDefaultsCleanup)
func 한_판을_읽는_중에_들어온_다른_판_조회는_삼키지_않고_뒤이어_읽는다() async throws {
    let (_, gomoku, host) = sfMakeStore("other-match") { rpc, body, _ in
        guard rpc == "gomoku_state" else { return nil }
        if body.contains(sfMatchA) {
            return .init(body: sfJSON(sfState(id: sfMatchA, moveCount: 0, turn: "white", status: "finished",
                                              result: "white_win", endReason: "resign")), delay: 0.6)
        }
        return .init(body: sfJSON(sfState(id: sfMatchB, moveCount: 0, turn: "black")))
    }
    let first = Task { await gomoku.refreshMatch(id: sfMatchA) }
    await sfWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 1 }
    await gomoku.refreshMatch(id: sfMatchB)
    await first.value

    let calls = GomokuStubProtocol.calls(host: host, rpc: "gomoku_state")
    #expect(calls.filter { $0.body.contains(sfMatchB) }.count == 1, "판 B 조회가 한 번도 나가지 않았다(A 조회만 되풀이)")
    #expect(calls.filter { $0.body.contains(sfMatchA) }.count == 1, "같은 판이 아닌데 A 를 한 번 더 읽었다")
    #expect(gomoku.match?.id == sfMatchB)
    #expect(gomoku.stateInFlightID == nil)
}

// MARK: - C5 같은 값 재조회 (zrev_R4)

@MainActor
@Test
func 같은_신청을_다시_읽어도_bannerInvite_관찰이_깨지지_않는다() async {
    let gomoku = GomokuStore()
    let local = Date(timeIntervalSince1970: 1_800_000_000)
    gomoku.clock = { local }
    let base = local.timeIntervalSince1970 * 1000
    func inbox(serverNow: Double) -> GomokuInboxResponse {
        sfDecode(GomokuInboxResponse.self, [
            "status": "ok",
            "incoming": [["match_id": sfMatchA, "stake": 5, "invite_expires_ms": base + 50_000,
                          "challenger": ["user_id": sfRival, "display_name": "라이벌"]]],
            "outgoing": NSNull(), "active_match_id": NSNull(), "server_now_ms": serverNow
        ])
    }
    await gomoku.applyInbox(inbox(serverNow: base))
    #expect(gomoku.bannerInvite?.id == sfMatchA)
    let tally = SFTally()
    withObservationTracking { _ = gomoku.bannerInvite } onChange: { MainActor.assumeIsolated { tally.fired = true } }
    // 두 번째 응답: 같은 행, 왕복 지연만 7ms 다르다.
    await gomoku.applyInbox(inbox(serverNow: base + 7))
    #expect(gomoku.bannerInvite?.id == sfMatchA)
    #expect(tally.fired == false, "내용이 같은 신청인데 bannerInvite 관찰이 깨졌다(팝오버 루트 재평가)")

    // 오프셋이 문턱(250ms)을 넘게 달라져도 만료가 1초 안쪽이면 같은 신청 값을 그대로 쓴다.
    await gomoku.applyInbox(inbox(serverNow: base + 400))
    #expect(tally.fired == false, "만료가 0.4초 달라졌다고 신청을 갈았다")
    // 만료가 정말로 바뀌면(1초 이상) 새 값이다.
    await gomoku.applyInbox(inbox(serverNow: base - 5_000))
    #expect(tally.fired == true)
}

@MainActor
@Test
func 서버_시계_오프셋은_문턱을_넘을_때만_다시_잰다() {
    let gomoku = GomokuStore()
    let local = Date(timeIntervalSince1970: 1_800_000_000)
    gomoku.clock = { local }
    let ms = local.timeIntervalSince1970 * 1000
    gomoku.noteServerNow(ms + 10_000)
    #expect(abs(gomoku.serverClockOffset - 10) < 0.0001, "처음 잰 값은 그대로 받는다")
    gomoku.noteServerNow(ms + 10_200)
    #expect(abs(gomoku.serverClockOffset - 10) < 0.0001, "200ms 흔들림에 오프셋을 갈았다")
    gomoku.noteServerNow(ms + 10_300)
    #expect(abs(gomoku.serverClockOffset - 10.3) < 0.0001, "300ms 어긋남은 반영해야 한다")
    gomoku.reset()
    gomoku.noteServerNow(ms + 10)
    #expect(abs(gomoku.serverClockOffset - 0.01) < 0.0001, "리셋 뒤 첫 값은 문턱과 무관하게 받는다")
}

@MainActor
@Test
func 같은_차례를_다시_읽으면_마감을_바꾸지_않아_창_루트가_다시_그려지지_않는다() {
    let gomoku = GomokuStore()
    let local = Date(timeIntervalSince1970: 1_800_000_000)
    gomoku.clock = { local }
    let serverNow = local.timeIntervalSince1970 * 1000
    let stones: [(Int, Int, Character)] = [(7, 7, "b")]
    gomoku.applyState(sfDecode(GomokuStatePayload.self, sfState(
        moveCount: 1, stones: stones, turn: "white", deadlineMs: serverNow + 30_000, serverNowMs: serverNow)))
    let deadline = gomoku.match?.deadline
    let tally = SFTally()
    withObservationTracking { _ = gomoku.match } onChange: { MainActor.assumeIsolated { tally.fired = true } }

    // 오프셋이 0.4초 달라진 응답(문턱 넘음) — 같은 차례라 마감은 0.4초만 달라지고, 그 값은 버린다.
    gomoku.applyState(sfDecode(GomokuStatePayload.self, sfState(
        moveCount: 1, stones: stones, turn: "white", deadlineMs: serverNow + 30_000, serverNowMs: serverNow + 400)))
    #expect(gomoku.match?.deadline == deadline)
    #expect(tally.fired == false, "같은 차례를 다시 읽었는데 대국 상태가 바뀌었다")

    // 다음 차례의 마감은 새 값이다(문턱 안쪽 차이여도).
    gomoku.applyState(sfDecode(GomokuStatePayload.self, sfState(
        moveCount: 2, stones: stones + [(8, 8, "w")], turn: "black",
        deadlineMs: serverNow + 30_300, serverNowMs: serverNow + 400)))
    #expect(tally.fired == true)
    #expect(gomoku.match?.deadline != deadline)
}

// MARK: - C6 보낸 신청이 사라짐 (zrev_R5)

@MainActor
@Test
func 보낸_신청이_거절되면_받지_않았다고_말하고_만료면_응답이_없었다고_말한다() async {
    let gomoku = GomokuStore()
    let empty = sfDecode(GomokuInboxResponse.self, [
        "status": "ok", "incoming": [], "outgoing": NSNull(), "active_match_id": NSNull(), "server_now_ms": sfNowMs()
    ])
    gomoku.outgoing = GomokuInvite(id: sfMatchA, peer: sfPeer, stake: 5, expiresAt: Date().addingTimeInterval(50))
    await gomoku.applyInbox(empty)   // 거절 ring → loadInbox
    #expect(gomoku.outgoing == nil)
    #expect(gomoku.notice == GomokuNoticeText.inviteDeclined, "신청 카드가 사라졌는데 이유 안내가 없다")
    #expect(gomoku.notice == "상대가 신청을 받지 않았어요")

    gomoku.notice = nil
    gomoku.outgoing = GomokuInvite(id: sfMatchB, peer: sfPeer, stake: 5, expiresAt: Date().addingTimeInterval(-1))
    await gomoku.applyInbox(empty)
    #expect(gomoku.notice == GomokuNoticeText.inviteTimedOut, "만료된 신청을 거절로 안내했다")

    // 수락으로 판이 된 신청은 거절이 아니다.
    gomoku.notice = nil
    gomoku.outgoing = GomokuInvite(id: sfMatchA, peer: sfPeer, stake: 5, expiresAt: Date().addingTimeInterval(50))
    await gomoku.applyInbox(sfDecode(GomokuInboxResponse.self, [
        "status": "ok", "incoming": [], "outgoing": NSNull(), "active_match_id": sfMatchA, "server_now_ms": sfNowMs()
    ]))
    #expect(gomoku.notice == nil)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 신청을_보내기_전에_나간_받은함이_늦게_와도_방금_보낸_신청을_지우지_않는다() async {
    let (_, gomoku, host) = sfMakeStore("inbox-before-challenge") { rpc, _, _ in
        switch rpc {
        case "gomoku_inbox":
            return .init(body: sfJSON(["status": "ok", "incoming": [], "outgoing": NSNull(),
                                       "server_now_ms": sfNowMs()]), delay: 0.5)
        case "gomoku_challenge":
            let now = sfNowMs()
            return .init(body: sfJSON(["status": "ok", "match_id": sfMatchA, "invite_expires_ms": now + 60_000,
                                       "server_now_ms": now]))
        default:
            return nil
        }
    }
    let pending = Task { await gomoku.loadInbox() }
    await sfWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") == 1 }
    await gomoku.challenge(userID: sfRival)
    #expect(gomoku.outgoing?.id == sfMatchA)
    await pending.value
    #expect(gomoku.outgoing?.id == sfMatchA, "신청보다 먼저 나간 받은함 응답이 방금 보낸 신청을 지웠다")
    #expect(gomoku.notice == "신청을 보냈어요", "보낸 신청을 거절로 안내했다: \(gomoku.notice ?? "nil")")
}

// MARK: - F1 · F2 (계약 검토 set #4)

@Test
func 기권_응답이_시간_초과면_시간이_지나_끝났다고_말한다() {
    #expect(GomokuNoticeText.resign(.timeout) == "시간이 지나 대국이 끝났어요")
    #expect(GomokuNoticeText.resign(.timeout) == GomokuNoticeText.move(.timeout))
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 받은함의_최근_끝난_판은_결과_화면으로_한_번만_세운다() async {
    let (_, gomoku, host) = sfMakeStore("last-finished") { rpc, _, _ in
        switch rpc {
        case "gomoku_inbox":
            return .init(body: sfJSON([
                "status": "ok", "incoming": [], "outgoing": NSNull(), "active_match_id": NSNull(),
                "last_finished": ["match_id": sfMatchA.uppercased(), "result": "white_win", "end_reason": "resign",
                                  "winner": sfRival, "stake": 5, "finished_ms": sfNowMs() - 60_000],
                "server_now_ms": sfNowMs()
            ]))
        case "gomoku_state":
            return .init(body: sfJSON(sfState(moveCount: 1, stones: [(7, 7, "b")], turn: nil, status: "finished",
                                              result: "white_win", endReason: "resign", ruby: 15)))
        case "gomoku_lobby":
            return .init(body: sfJSON(["status": "ok", "users": []]))
        default:
            return nil
        }
    }
    let tally = sfWire(gomoku)
    await gomoku.loadInbox()
    #expect(gomoku.phase == .result, "앱을 다시 켠 사이 끝난 판의 결과가 안 보인다")
    #expect(gomoku.match?.id == sfMatchA && gomoku.match?.outcome == .lost && gomoku.match?.endReason == .resign)
    #expect(tally.presents == 0, "끝난 판 때문에 창을 띄웠다 — 결과는 다음에 창을 열 때 보이면 된다")

    // 이미 보여 준 결과는 다시 세우지 않는다(결과 화면에 머물러 있든, [로비로] 로 접었든).
    await gomoku.loadInbox()
    gomoku.backToLobby()
    await sfWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") >= 3 }
    await gomoku.loadInbox()
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 1)
    #expect(gomoku.phase == .lobby && gomoku.match == nil)
}

// MARK: - DL 서버 교착(set #2) — 쓰기만 한 번 더

@MainActor
@Test(.gomokuDefaultsCleanup)
func 교착으로_되돌려진_쓰기는_한_번_더_보내고_읽기는_다시_보내지_않는다() async {
    let (_, gomoku, host) = sfMakeStore("deadlock") { rpc, _, index in
        switch rpc {
        case "gomoku_move":
            if index == 0 { return .init(status: 500, body: sfDeadlockBody) }
            let state = sfState(moveCount: 3, stones: [(7, 7, "b"), (8, 7, "w"), (6, 6, "b")], turn: "white")
            var body = state
            body["state"] = state
            return .init(body: sfJSON(body))
        case "gomoku_resign":
            return .init(status: 500, body: sfDeadlockBody)
        case "gomoku_cancel":
            return .init(status: 500, body: #"{"code":"XX000","message":"internal"}"#)
        case "gomoku_state":
            return .init(status: 500, body: sfDeadlockBody)
        default:
            return nil
        }
    }
    gomoku.applyState(sfDecode(GomokuStatePayload.self, sfState(moveCount: 2, stones: [(7, 7, "b"), (8, 7, "w")], turn: "black")))

    await gomoku.place(GomokuPoint(x: 6, y: 6)!)
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_move") == 2, "교착으로 죽은 착수를 다시 보내지 않았다")
    #expect(gomoku.match?.moveCount == 3)
    #expect(gomoku.notice == nil)
    let bodies = GomokuStubProtocol.calls(host: host, rpc: "gomoku_move").map { $0.json["p_expected_seq"] as? Int }
    #expect(bodies == [2, 2], "재시도는 같은 요청이어야 한다(expected_seq 가 멱등을 지킨다)")

    // 두 번 연속 교착이면 더 보내지 않고 실패로 알린다.
    await gomoku.resign()
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_resign") == 2)
    #expect(gomoku.notice == GomokuNoticeText.checkConnection)

    // 교착이 아닌 서버 실패는 다시 보내지 않는다.
    gomoku.outgoing = GomokuInvite(id: sfMatchB, peer: sfPeer, stake: 5, expiresAt: Date().addingTimeInterval(50))
    await gomoku.cancelChallenge()
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_cancel") == 1)

    // 읽기는 재시도하지 않는다(다음 계기가 다시 읽는다).
    let statesBefore = GomokuStubProtocol.count(host: host, rpc: "gomoku_state")
    await gomoku.refreshMatch(id: sfMatchA)
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == statesBefore + 1)
}

// MARK: - C8 로비 실패 · C3 가림

@MainActor
@Test(.gomokuDefaultsCleanup)
func 상대_목록_조회가_실패하면_실패를_기억하고_성공하면_지운다() async {
    let (_, gomoku, _) = sfMakeStore("lobby-fail") { rpc, _, index in
        guard rpc == "gomoku_lobby" else { return nil }
        if index == 0 { return .init(status: 404, body: #"{"code":"PGRST202","message":"Could not find the function"}"#) }
        return .init(body: sfJSON(["status": "ok", "users": [["user_id": sfRival, "display_name": "라이벌",
                                                               "is_working": true, "capable": true, "in_match": false]]]))
    }
    #expect(gomoku.lobbyLoadFailed == false && gomoku.hasLoadedLobby == false)
    await gomoku.refreshLobby()
    #expect(gomoku.lobbyLoadFailed, "목록 조회 실패를 기억하지 않았다 — 화면이 '상대가 없다'고 말한다")
    #expect(gomoku.hasLoadedLobby == false)
    #expect(gomoku.users.isEmpty)
    await gomoku.refreshLobby()
    #expect(gomoku.lobbyLoadFailed == false)
    #expect(gomoku.hasLoadedLobby)
    #expect(gomoku.users.count == 1)
    gomoku.reset()
    #expect(gomoku.lobbyLoadFailed == false && gomoku.hasLoadedLobby == false)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 가려진_창은_폴링만_멈추고_보이는_상태와_실시간_조회는_그대로다() async {
    let (_, gomoku, host) = sfMakeStore("occluded") { rpc, _, _ in
        switch rpc {
        case "gomoku_state":
            return .init(body: sfJSON(sfState(moveCount: 1, stones: [(7, 7, "b")], turn: "white")))
        case "gomoku_lobby":
            return .init(body: sfJSON(["status": "ok", "users": []]))
        case "gomoku_inbox":
            // 진행 중 판을 그대로 말한다 — 창을 열 때의 받은함이 판을 다시 읽지 않게(이 테스트는 신호·폴링만 센다).
            return .init(body: sfJSON(["status": "ok", "incoming": [], "active_match_id": sfMatchA]))
        default:
            return nil
        }
    }
    gomoku.applyState(sfDecode(GomokuStatePayload.self, sfState(moveCount: 1, stones: [(7, 7, "b")], turn: "white")))
    gomoku.pollStepSeconds = 60
    gomoku.windowDidShow()
    #expect(gomoku.pollTask != nil)
    // 창을 열 때 나가는 로비·받은함 조회가 끝난 뒤를 기준으로 잰다.
    await sfWait {
        GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") >= 1 && GomokuStubProtocol.count(host: host, rpc: "gomoku_lobby") >= 1
            && gomoku.stateInFlightID == nil
    }
    try? await Task.sleep(for: .milliseconds(100))

    gomoku.windowOcclusionDidChange(visible: false)
    #expect(gomoku.pollTask == nil, "가려진 창에서 폴링이 계속 돈다")
    #expect(gomoku.isWindowVisible, "가림이 '안 보임'으로 번졌다 — 시계 잎 뷰가 멈춘다")
    let t = Date().addingTimeInterval(1_000)
    let before = GomokuStubProtocol.count(host: host, rpc: "gomoku_state")
    await gomoku.pollTick(at: t)
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == before, "가려진 창의 폴링 한 걸음이 요청을 냈다")

    // 실시간 신호는 가림과 무관하게 판을 다시 읽는다.
    gomoku.handleSignal()
    await sfWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == before + 1 && gomoku.syncTask == nil }
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == before + 1)

    gomoku.windowOcclusionDidChange(visible: true)
    #expect(gomoku.pollTask != nil, "다시 보이는데 폴링이 안 돈다")
    await gomoku.pollTick(at: t.addingTimeInterval(10))
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == before + 2)

    // 가려진 채로 창을 닫았다 다시 열면 가림 기록이 폴링을 막지 않는다.
    gomoku.windowOcclusionDidChange(visible: false)
    gomoku.windowDidHide()
    gomoku.windowDidShow()
    #expect(gomoku.pollTask != nil)
    gomoku.windowDidHide()
}
