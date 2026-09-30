import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.41 — 1:1 오목 **승점 순위표** 스토어(GomokuStoreRanking.swift) 계약.
//
// 관례는 V0327GomokuStoreTests 그대로(호스트별 스텁 · 재개 횟수 대기 · WorkTimerStore 붙잡기 · 격리 UserDefaults — C21).
// 각 테스트 첫 줄은 "없으면 어떤 결함이 초록으로 통과하는가"다. 서버 정렬·동률 깨기·컷의 실제 값은 실서버 픽스처 계약(V0327GomokuContractTests)과
// 로컬 Postgres 하네스 몫이다 — 여기서 지키는 것은 스토어가 **언제 요청을 내고**, **응답을 어떻게(재정렬 없이) 옮기고**, **실패를 어디에 적는가**다.

// MARK: - 픽스처

private let me = "00000000-0000-0000-0000-0000000000a1"
private let rival = "00000000-0000-0000-0000-0000000000b2"
private let third = "00000000-0000-0000-0000-0000000000c3"
private let fourth = "00000000-0000-0000-0000-0000000000d4"
private let fifth = "00000000-0000-0000-0000-0000000000e5"
private let watchedID = "aaaaaaaa-0000-0000-0000-00000000aaaa"

private func jsonText(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

private func rankRow(
    _ id: String, _ name: String, rank: Int, wins: Int, losses: Int, draws: Int, points: Int? = nil, center: String? = "seoul"
) -> [String: Any] {
    [
        "rank": rank, "user_id": id, "display_name": name, "avatar_url": NSNull(), "character": "aing",
        "center": center.map { $0 as Any } ?? NSNull(), "wins": wins, "losses": losses, "draws": draws, "points": points ?? (wins - losses)
    ]
}

/// 서버 순서대로(정렬 규칙: 승점 desc → 승 desc → 무 desc → user_id asc, rank() 는 앞 세 축). 동률 쌍(fourth·fifth)이 같은 3위, 다음은 5위.
private func sortedRows() -> [[String: Any]] {
    [
        rankRow(rival, "라이벌", rank: 1, wins: 5, losses: 1, draws: 0),      // +4
        rankRow(me, "나", rank: 2, wins: 3, losses: 1, draws: 2),            // +2
        rankRow(fourth, "넷째", rank: 3, wins: 1, losses: 1, draws: 1),      // 0 · 1승 1무
        rankRow(fifth, "다섯째", rank: 3, wins: 1, losses: 1, draws: 1),     // 0 · 동률(user_id 뒤)
        rankRow(third, "셋째", rank: 5, wins: 1, losses: 1, draws: 0)        // 0 · 1승 0무 — "같은 승점·승수면 더 많이 둔 쪽이 위"
    ]
}

private func rankingPayload(
    rows: [[String: Any]] = sortedRows(),
    me meRow: [String: Any]? = ["rank": 2, "wins": 3, "losses": 1, "draws": 2, "points": 2],
    recordSinceMs: Double? = nil,
    serverNowMs: Double? = nil,
    status: String = "ok"
) -> [String: Any] {
    [
        "status": status, "server_now_ms": serverNowMs ?? nowMs(),
        "record_since_ms": recordSinceMs.map { $0 as Any } ?? NSNull(),
        "me": meRow.map { $0 as Any } ?? NSNull(), "rows": rows
    ]
}

private func lobbyPayload(wins: Int = 3, losses: Int = 1, draws: Int = 2) -> [String: Any] {
    [
        "status": "ok", "server_now_ms": nowMs(), "turn_seconds": 30,
        "me": ["ruby_balance": 30, "wins": wins, "losses": losses, "draws": draws, "active_match_id": NSNull(), "outgoing_match_id": NSNull()],
        "users": [], "matches": []
    ]
}

/// 내 1:1 판의 gomoku_state ok 묶음(내가 백).
private func myStatePayload(finished: Bool) -> [String: Any] {
    let null = NSNull()
    let turnValue: Any = finished ? null : "white" as Any
    let resultValue: Any = finished ? "black_win" as Any : null
    let endReasonValue: Any = finished ? "resign" as Any : null
    let winnerValue: Any = finished ? rival as Any : null
    return [
        "status": "ok",
        "match": [
            "id": "dddddddd-0000-0000-0000-00000000dddd", "status": finished ? "finished" : "active", "stake": 5,
            "black": rival, "white": me, "challenger": rival, "opponent": me,
            "move_count": 1, "turn": turnValue, "deadline_ms": null,
            "result": resultValue, "end_reason": endReasonValue,
            "winner": winnerValue, "invite_expires_ms": null
        ],
        "moves": [["seq": 1, "color": "black", "x": 7, "y": 7, "kind": "stone"]],
        "my_color": "white",
        "opponent": ["user_id": rival, "display_name": "라이벌", "avatar_url": NSNull(), "character": "aing"],
        "ruby_balance": NSNull(),
        "server_now_ms": nowMs()
    ]
}

private func reply(_ object: [String: Any], delay: TimeInterval = 0) -> GomokuStubProtocol.Reply {
    GomokuStubProtocol.Reply(body: jsonText(object), delay: delay)
}

private func baseReply(_ rpc: String) -> GomokuStubProtocol.Reply? {
    switch rpc {
    case "gomoku_lobby": return reply(lobbyPayload())
    case "gomoku_inbox": return reply(["status": "ok", "server_now_ms": nowMs(), "incoming": [], "outgoing": NSNull(), "active_match_id": NSNull()])
    case "gomoku_ranking": return reply(rankingPayload())
    default: return nil
    }
}

/// 실제 PGRST202 본문 모양(404).
private let pgrst202 = GomokuStubProtocol.Reply(
    status: 404,
    body: #"{"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.gomoku_ranking(p_protocol) in the schema cache"}"#
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
private func makeRankingStore(
    _ label: String,
    enabled: Bool = true,
    handler: @escaping GomokuStubProtocol.Handler = { rpc, _, _ in baseReply(rpc) }
) -> (WorkTimerStore, GomokuStore, String) {
    let host = "v0341-r-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: GomokuStubProtocol.session()
    )
    let defaults = GomokuTestDefaults.make("v0341-ranking")
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    RankingTestRetention.stores.append(store)
    let gomoku = store.gomoku
    gomoku.spectatorFeaturesEnabled = enabled       // 맥 배선의 한 줄
    gomoku.pollStepSeconds = 3_600                   // 실제 루프는 재우고 걸음은 pollTick(at:) 으로 잰다
    return (store, gomoku, host)
}

/// 오목 스토어는 WorkTimerStore 를 **약참조**한다 — 튜플에서 버리면 곧바로 해제되어 요청이 한 건도 안 나간다.
@MainActor
private enum RankingTestRetention {
    static var stores: [WorkTimerStore] = []
}

@MainActor
private func rankingWait(_ timeout: TimeInterval = 60, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<Int(timeout * 200) {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

private func count(_ host: String, _ rpc: String) -> Int { GomokuStubProtocol.count(host: host, rpc: rpc) }

// MARK: - 1. 주 스위치 (C11)

@MainActor
@Test(.gomokuDefaultsCleanup)
func 순위_주_스위치가_꺼져_있으면_요청이_없다() async {
    // 없으면: 폰(같은 스토어)이 오목 화면을 열 때마다 + 1분마다 + 내 판이 끝날 때마다 그리지도 않는 gomoku_ranking 을 당겨도 초록이다.
    let (_, gomoku, host) = makeRankingStore("switch-off", enabled: false)
    let clock = Clock()
    let t0 = clock.now
    gomoku.clock = { clock.now }
    gomoku.windowDidShow()
    await gomoku.loadRanking()
    for offset in [0.0, 61, 125, 3_600] {
        clock.now = t0.addingTimeInterval(offset)
        await gomoku.pollTick(at: clock.now)
    }
    gomoku.applyState(decode(GomokuStatePayload.self, myStatePayload(finished: false)))
    gomoku.applyState(decode(GomokuStatePayload.self, myStatePayload(finished: true)))
    try? await Task.sleep(for: .milliseconds(200))
    #expect(count(host, "gomoku_ranking") == 0)
    #expect(gomoku.ranking == nil && !gomoku.hasLoadedRanking)
    // 기준선: 켜면 같은 손짓이 요청을 낸다.
    gomoku.spectatorFeaturesEnabled = true
    await gomoku.loadRanking()
    #expect(count(host, "gomoku_ranking") == 1)
}

// MARK: - 2. 응답 옮기기 — 서버 순서 그대로

@MainActor
@Test(.gomokuDefaultsCleanup)
func 순위_응답은_서버_순서_그대로_옮기고_me_와_기준_시각을_읽는다() throws {
    // 없으면: 클라 재정렬이 슬쩍 들어와 서버·앱 두 규칙이 갈리거나(같은 목록이 화면마다 다른 순서), me.rank null(0판)을 0위로 지어내도 초록이다.
    let (_, gomoku, _) = makeRankingStore("apply")
    // 일부러 뒤섞은 순서 — 스토어는 이 순서를 **그대로** 낸다(정렬은 서버 몫).
    let sorted = sortedRows()
    let shuffled = [sorted[3], sorted[0], sorted[4], sorted[1], sorted[2]]
    gomoku.applyRanking(decode(GomokuRankingResponse.self, rankingPayload(rows: shuffled, recordSinceMs: 1_759_708_800_000)))
    let board = try #require(gomoku.ranking)
    #expect(board.entries.map(\.id) == [fifth, rival, third, me, fourth], "입력 순서를 바꿨다")
    #expect(board.entries.map(\.rank) == [3, 1, 5, 2, 3], "순위는 서버가 매긴 숫자 그대로다")
    #expect(GomokuRankingOrder.isSorted(board.entries) == false, "뒤섞인 입력이 정렬돼 있을 리 없다 — 재정렬했다")
    let mine = try #require(board.entries.first { $0.id == me })
    #expect(mine.wins == 3 && mine.losses == 1 && mine.draws == 2 && mine.points == 2, "행에 승·패·무와 승점이 같이 실린다(U2)")
    #expect(mine.user.displayName == "나" && mine.user.center == "서울", "센터는 user(from:) 경계에서 화면 글자가 된다")
    #expect(board.me == GomokuMyRank(rank: 2, wins: 3, losses: 1, draws: 2, points: 2))
    #expect(board.recordSince == Date(timeIntervalSince1970: 1_759_708_800), "컷은 ms → Date")
    #expect(gomoku.hasLoadedRanking && !gomoku.rankingLoadFailed && !gomoku.rankingUnavailable)
    #expect(gomoku.notice == nil)

    // 컷 없음(null) → nil · me.rank null(0판) → nil · points 없는 옛 행은 승 − 패로 채운다 · user_id 없는 행은 싣지 않는다.
    var noPoints = rankRow(rival, "라이벌", rank: 1, wins: 5, losses: 1, draws: 0)
    noPoints["points"] = NSNull()
    var noID = rankRow(third, "셋째", rank: 2, wins: 1, losses: 1, draws: 0)
    noID["user_id"] = NSNull()
    gomoku.applyRanking(decode(GomokuRankingResponse.self, rankingPayload(
        rows: [noPoints, noID], me: ["rank": NSNull(), "wins": 0, "losses": 0, "draws": 0, "points": 0])))
    let again = try #require(gomoku.ranking)
    #expect(again.entries.map(\.id) == [rival] && again.entries.first?.points == 4)
    #expect(again.me?.rank == nil && again.me?.wins == 0, "0판이면 순위 밖(nil)이고 전적은 있다")
    #expect(again.recordSince == nil)
}

// MARK: - 3. 실패 경로 (C17) — 안내줄로 새지 않는다

@MainActor
@Test(.gomokuDefaultsCleanup)
func 순위_5xx_는_깃발만_세우고_목록과_안내줄을_건드리지_않는다() async throws {
    // 없으면: 순위 실패가 notice 로 새어 대국 상태줄을 가리거나, 들고 있던 목록을 지워 "아직 전적이 없어요"를 사실처럼 그려도 초록이다.
    let (_, gomoku, host) = makeRankingStore("5xx") { rpc, _, index in
        guard rpc == "gomoku_ranking" else { return baseReply(rpc) }
        return index == 0 ? reply(rankingPayload()) : GomokuStubProtocol.Reply(status: 500, body: "{}")
    }
    await gomoku.loadRanking()
    let kept = try #require(gomoku.ranking)
    #expect(kept.entries.count == 5)

    await gomoku.loadRanking()
    #expect(count(host, "gomoku_ranking") == 2)
    #expect(gomoku.rankingLoadFailed, "실패 깃발이 안 섰다")
    #expect(gomoku.ranking == kept, "실패가 들고 있던 목록을 지웠다")
    #expect(gomoku.hasLoadedRanking && !gomoku.rankingUnavailable)
    #expect(gomoku.notice == nil, "순위 실패가 안내줄로 샜다")

    // 다음 성공이 깃발을 내린다.
    GomokuStubProtocol.register(host: host) { rpc, _, _ in baseReply(rpc) }
    await gomoku.loadRanking()
    #expect(!gomoku.rankingLoadFailed)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 순위_404_스키마_없음은_실패가_아니라_준비_중이다() async {
    // 없으면: brew 가 db push 보다 먼저 나간 창에서 순위 열이 "다시 불러오기" 실패 화면이나 영원한 로딩으로 서 있어도 초록이다.
    let (_, gomoku, host) = makeRankingStore("pgrst202") { rpc, _, _ in
        rpc == "gomoku_ranking" ? pgrst202 : baseReply(rpc)
    }
    await gomoku.loadRanking()
    #expect(count(host, "gomoku_ranking") == 1)
    #expect(gomoku.rankingUnavailable, "미배포가 준비 중으로 안 접혔다")
    #expect(gomoku.hasLoadedRanking, "준비 중도 '받은 것'이다 — 아니면 로딩 문구가 영영 선다")
    #expect(!gomoku.rankingLoadFailed, "미배포는 실패가 아니다")
    #expect(gomoku.ranking == nil)
    #expect(gomoku.notice == nil, "순위는 안내줄을 만들지 않는다")

    // 서버가 올라오면(다음 조회가 ok) 저절로 회복한다 — 앱 재시작 없이.
    GomokuStubProtocol.register(host: host) { rpc, _, _ in baseReply(rpc) }
    await gomoku.loadRanking()
    #expect(!gomoku.rankingUnavailable && gomoku.ranking?.entries.count == 5)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 순위_거절_status_는_실패로_적고_안내하지_않는다() {
    // 없으면: unsupported_client 를 순위가 한 번 더 안내해 로비 안내와 겹치거나, 거절 응답을 빈 목록(0행)으로 그려도 초록이다.
    let (_, gomoku, _) = makeRankingStore("refused")
    gomoku.applyRanking(decode(GomokuRankingResponse.self, rankingPayload()))
    let kept = gomoku.ranking
    gomoku.applyRanking(decode(GomokuRankingResponse.self, rankingPayload(rows: [], me: nil, status: "unsupported_client")))
    #expect(gomoku.rankingLoadFailed && gomoku.ranking == kept)
    #expect(gomoku.notice == nil)
    gomoku.applyRanking(decode(GomokuRankingResponse.self, rankingPayload(rows: [], me: nil, status: "unauthorized")))
    #expect(gomoku.rankingLoadFailed && gomoku.ranking == kept && gomoku.notice == nil)
}

// MARK: - 4. 언제 요청을 내는가

@MainActor
@Test(.gomokuDefaultsCleanup)
func 순위_동시_호출은_한_건이다() async {
    // 없으면: 창 열기와 폴링이 겹치는 순간 같은 목록을 두 번 당겨도 초록이다(무료 플랜 예산).
    let (_, gomoku, host) = makeRankingStore("inflight") { rpc, _, _ in
        rpc == "gomoku_ranking" ? reply(rankingPayload(), delay: 0.2) : baseReply(rpc)
    }
    Task { await gomoku.loadRanking() }
    Task { await gomoku.loadRanking() }
    await rankingWait { gomoku.ranking != nil }
    try? await Task.sleep(for: .milliseconds(300))
    #expect(count(host, "gomoku_ranking") == 1)
    #expect(!gomoku.watchRuntime.rankingInFlight)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 순위_폴링은_로비·창_보임·안_가려짐·60초에서만_돌고_관전_중엔_안_돈다() async {
    // 없으면: 창이 안 보이거나 대국 중·관전 중에도 60초 폴링이 돌거나, 주기가 30초로 줄어도 초록이다.
    let (_, gomoku, host) = makeRankingStore("cadence") { rpc, _, _ in
        rpc == "gomoku_watch" ? reply(["status": "not_found"]) : baseReply(rpc)
    }
    let clock = Clock()
    let t0 = clock.now
    gomoku.clock = { clock.now }
    func tick(_ offset: TimeInterval) async {
        clock.now = t0.addingTimeInterval(offset)
        await gomoku.pollTick(at: clock.now)
    }
    func rankings() -> Int { count(host, "gomoku_ranking") }

    // 창이 안 보이면 없다.
    await tick(0)
    #expect(rankings() == 0)

    gomoku.isWindowVisible = true
    await tick(1)
    #expect(rankings() == 1, "로비·창 보임에서 첫 걸음에 읽는다")
    await tick(30)
    await tick(60.5)
    #expect(rankings() == 1)
    await tick(61.1)
    #expect(rankings() == 2)

    // 관전 중엔 순위를 돌리지 않는다(돌아올 때 leaveWatch 가 한 번 읽는다).
    gomoku.spectating = GomokuSpectateState(id: watchedID)
    await tick(200)
    #expect(rankings() == 2, "관전 중에 순위 폴링이 돌았다")
    gomoku.spectating = nil

    // 대국·결과 화면에서는 없다.
    gomoku.phase = .playing
    await tick(300)
    gomoku.phase = .result
    await tick(400)
    #expect(rankings() == 2)
    gomoku.phase = .lobby

    // 가려진 창에서는 없다.
    gomoku.windowOcclusionDidChange(visible: false)
    await tick(500)
    #expect(rankings() == 2, "가려진 창에서 순위 폴링이 돌았다")
    gomoku.windowOcclusionDidChange(visible: true)
    await tick(600)
    #expect(rankings() == 3)

    // 숨긴 창에서는 없다.
    gomoku.windowDidHide()
    await tick(1_000)
    await tick(2_000)
    #expect(rankings() == 3)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 창_표시는_순위를_1초_dedupe_로_한_번_읽는다() async {
    // 없으면: 창을 열 때 오는 두 번의 표시 통지가 순위를 두 번 당기거나, 창을 열어도 순위가 60초 뒤에야 오는 구현이 초록이다.
    let (_, gomoku, host) = makeRankingStore("show")
    let clock = Clock()
    let t0 = clock.now
    gomoku.clock = { clock.now }
    func rankings() -> Int { count(host, "gomoku_ranking") }

    gomoku.windowDidShow()
    await rankingWait { rankings() == 1 }
    #expect(rankings() == 1)
    clock.now = t0.addingTimeInterval(0.5)
    gomoku.windowDidShow()
    try? await Task.sleep(for: .milliseconds(100))
    #expect(rankings() == 1, "1초 안의 두 번째 표시가 또 읽었다")
    clock.now = t0.addingTimeInterval(1.5)
    gomoku.windowDidShow()
    await rankingWait { rankings() == 2 }
    #expect(rankings() == 2)

    // 결과 화면에서 보인 창은 순위를 읽지 않는다(로비 자리가 아니다).
    gomoku.phase = .result
    clock.now = t0.addingTimeInterval(10)
    gomoku.windowDidShow()
    try? await Task.sleep(for: .milliseconds(100))
    #expect(rankings() == 2)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 내_판이_끝나면_순위를_다시_읽는다() async {
    // 없으면: 내 판이 끝나 전적은 새로 왔는데 순위·승점은 60초 동안 옛것이라 머리글이 "9승 · 승점 +7(옛)" 을 붙여도 초록이다(C16).
    let (_, gomoku, host) = makeRankingStore("finished")
    gomoku.applyState(decode(GomokuStatePayload.self, myStatePayload(finished: false)))
    try? await Task.sleep(for: .milliseconds(100))
    #expect(count(host, "gomoku_ranking") == 0, "진행 중 판은 순위를 안 읽는다")
    gomoku.applyState(decode(GomokuStatePayload.self, myStatePayload(finished: true)))
    await rankingWait { count(host, "gomoku_ranking") == 1 }
    #expect(count(host, "gomoku_ranking") == 1)
    #expect(count(host, "gomoku_lobby") == 1, "전적(로비)도 같은 순간 새로 읽는다 — 기존 동작")
    #expect(gomoku.ranking != nil)
}

// MARK: - 5. 리셋

@MainActor
@Test(.gomokuDefaultsCleanup)
func 순위_리셋은_목록과_깃발을_비우고_늦은_응답을_버린다() async {
    // 없으면: 로그아웃 뒤 앞 계정의 순위표가 다음 사람 화면에 남거나 늦은 응답이 그것을 되살려도 초록이다.
    let (_, gomoku, host) = makeRankingStore("reset") { rpc, _, index in
        guard rpc == "gomoku_ranking" else { return baseReply(rpc) }
        return reply(rankingPayload(), delay: index == 0 ? 0 : 0.3)
    }
    await gomoku.loadRanking()
    #expect(gomoku.ranking != nil)
    Task { await gomoku.loadRanking() }
    await rankingWait { count(host, "gomoku_ranking") == 2 }
    gomoku.reset()
    #expect(gomoku.ranking == nil && !gomoku.hasLoadedRanking && !gomoku.rankingLoadFailed && !gomoku.rankingUnavailable)
    #expect(gomoku.watchRuntime.lastRankingRequestAt == .distantPast && !gomoku.watchRuntime.rankingInFlight)
    try? await Task.sleep(for: .milliseconds(500))
    #expect(gomoku.ranking == nil, "로그아웃 뒤 도착한 앞 계정의 순위가 살아났다")
}

// MARK: - 6. 내 순위는 한 출처 (C16)

@MainActor
@Test(.gomokuDefaultsCleanup)
func 내_순위는_로비_전적과_같을_때만_붙는다() {
    // 없으면: 로비(9승)와 순위(8승·12위)가 다른 순간에 와 머리글이 "9승 3패 · 12위 · 승점 +5" 같은 자기모순 문장을 만들어도 초록이다.
    let (_, gomoku, _) = makeRankingStore("consistent")
    #expect(gomoku.myRankConsistentWithRecord == nil, "순위 응답 전엔 없다")
    gomoku.applyRanking(decode(GomokuRankingResponse.self, rankingPayload()))       // me: 3승 1패 2무 · 2위
    #expect(gomoku.myRankConsistentWithRecord?.rank == 2, "로비를 아직 못 받았으면 순위 응답이 유일한 출처다")
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload(wins: 3, losses: 1, draws: 2)))
    #expect(gomoku.myRankConsistentWithRecord == GomokuMyRank(rank: 2, wins: 3, losses: 1, draws: 2, points: 2))
    gomoku.applyLobby(decode(GomokuLobbyResponse.self, lobbyPayload(wins: 4, losses: 1, draws: 2)))     // 판이 하나 더 끝났다
    #expect(gomoku.myRankConsistentWithRecord == nil, "전적이 다른데 옛 순위를 붙였다")
    gomoku.applyRanking(decode(GomokuRankingResponse.self, rankingPayload(me: ["rank": 1, "wins": 4, "losses": 1, "draws": 2, "points": 3])))
    #expect(gomoku.myRankConsistentWithRecord?.rank == 1)
}

// MARK: - 7. 정렬 판정 (순수 함수)

@Test
func 순위_정렬_판정은_서버_order_by_를_옮긴_것이다() throws {
    // 없으면: 서버 order by 를 바꾼 사람이 픽스처를 다시 떠도 앱 쪽 명세와의 어긋남을 아무도 못 본다(계약 테스트가 이 판정을 실서버 픽스처에 건다).
    let rows = decode(GomokuRankingResponse.self, rankingPayload()).rows ?? []
    #expect(rows.count == 5)
    #expect(GomokuRankingOrder.isSorted(rows), "픽스처가 서버 규칙대로 서 있지 않다")
    let entries = GomokuStore.rankingBoard(from: decode(GomokuRankingResponse.self, rankingPayload())).entries
    #expect(GomokuRankingOrder.isSorted(entries))
    #expect(GomokuRankingOrder.ranksMatchServerRule(entries), "rank() 모양(3,3,5)이 아니다")

    // 한 쌍을 바꾸면 거짓 — 축마다 하나씩.
    func swapped(_ i: Int, _ j: Int) -> [GomokuRankRow] {
        var copy = rows
        copy.swapAt(i, j)
        return copy
    }
    #expect(!GomokuRankingOrder.isSorted(swapped(0, 1)), "승점 축을 안 본다")
    #expect(!GomokuRankingOrder.isSorted(swapped(2, 4)), "무승부 축(같은 승점·승수면 더 많이 둔 쪽이 위)을 안 본다")
    #expect(!GomokuRankingOrder.isSorted(swapped(2, 3)), "완전 동률은 user_id 오름차순이다")
    var moreWins = rows
    moreWins[4].wins = 2
    moreWins[4].losses = 2                                         // 0점 유지 · 2승 → 넷째(1승) 앞이어야 한다
    #expect(!GomokuRankingOrder.isSorted(moreWins), "승수 축을 안 본다")
    var noID = rows
    noID[1].userId = nil
    #expect(!GomokuRankingOrder.isSorted(noID), "user_id 없는 행은 순서를 말할 수 없다")
    var wrongRank = entries
    wrongRank[3] = GomokuRankEntry(id: fifth, rank: 4, user: entries[3].user, wins: 1, losses: 1, draws: 1, points: 0)
    #expect(!GomokuRankingOrder.ranksMatchServerRule(wrongRank), "동률에 다른 순위를 줬는데 통과했다")

    // 실서버 픽스처가 있으면(W5 뒤) 그것도 같은 판정을 지난다.
    let fixture = CheckCoreSourceLayout.repoRoot
        .appendingPathComponent("Tests/checkTests/Fixtures/gomoku-rpc/gomoku_ranking__ok.json")
    if let data = try? Data(contentsOf: fixture),
       let response = try? snakeDecoder().decode(GomokuRankingResponse.self, from: data) {
        #expect(GomokuRankingOrder.isSorted(response.rows ?? []), "실서버 픽스처의 rows 가 앱 쪽 정렬 명세와 어긋난다")
        let fixtureEntries = GomokuStore.rankingBoard(from: response).entries
        #expect(GomokuRankingOrder.ranksMatchServerRule(fixtureEntries))
    }
}

// MARK: - 8. 소스 계약 (주석을 걷어낸 뒤)

@Test
func 순위_소스_계약_재정렬과_안내줄이_없다() throws {
    // 없으면: 누가 applyRanking 에 sorted 한 줄을 넣거나 실패 갈래에 setNotice 를 넣어도(둘 다 "친절"로 보인다) 스텁 테스트 몇 개가 초록인 채 지나간다.
    let file = CheckCoreSourceLayout.coreDirectory.appendingPathComponent("GomokuStoreRanking.swift")
    let code = V0317ShopTests.stripped(try String(contentsOf: file, encoding: .utf8))
    let load = try #require(gomokuBody(of: "func loadRanking()", in: code))
    #expect(!load.contains("setNotice("), "순위 실패가 안내줄로 샌다")
    let apply = try #require(gomokuBody(of: "func applyRanking(", in: code))
    #expect(!apply.contains("setNotice(") && !apply.contains(".sorted") && !apply.contains(".sort("), "순위 응답을 재정렬하거나 안내한다")
    let board = try #require(gomokuBody(of: "static func rankingBoard(", in: code))
    #expect(!board.contains(".sorted") && !board.contains(".sort("), "매퍼가 재정렬한다 — 서버·앱 두 규칙이 갈린다")
    #expect(board.contains("user(from:"), "CenterLabel 변환점을 늘렸다")
    #expect(code.contains("spectatorFeaturesEnabled"), "주 스위치를 안 본다(C11)")
    #expect(code.contains("databaseSchemaMissing"), "PGRST202 갈래가 없다(C17)")
}
