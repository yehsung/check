import Foundation
import Testing
@testable import check
@testable import CheckCore

// stab-l6(2026-10-30) — `token_usage_board` 맥 호출 합치기.
//
// 왜: 2026-10-29 18:53 KST 장애의 첫 SQL 시간 초과가 이 RPC 안이었고, 느린 동안 요청 하나가 PostgREST 연결 하나를 쥔다.
// 맥은 순위판 30초 루프 · 팝오버 재오픈 킥 · 열기 토글 · [다시 시도] · 팝오버 내 행 조회가 서로를 모른 채 같은 달을 쏴서,
// 서버가 느릴수록 같은 질의가 겹쳐 쌓였다. 수리는 `fetchTokenBoardCoalesced` 한 자리 — 같은 달·같은 세대 조회가 떠 있으면 붙는다.
//
// 여기서는 **요청 수**를 값으로 잰다(스텁이 응답만 늦추고 요청은 바로 기록한다 — `MyTokenRowURLProtocol.boardDelay`).
// 기준선이 다른 회차를 같이 둔다: 순차 호출·다른 달·force 는 **합치지 않아야** 한다(합치기만 재면 "늘 1건"인 고장도 초록이다).

private let stabBoardPath = "/rest/v1/rpc/token_usage_board"
private let stabUserID = "5a0c7e0e-1d1f-4c55-9a51-6b8b7e0c0a11"

private func stabBoardJSON() -> String {
    """
    [{"user_id":"\(stabUserID)","display_name":"합치기","avatar_url":null,
      "claude_input":1,"claude_output":2,"claude_cache_read":3,"claude_cache_creation":4,
      "codex_input":5,"codex_output":6,"total":21,
      "today_total":0,"today_date":"2026-10-30","codex_cache_read":0,
      "codex_account_month":null,"codex_effective":11,"center":null}]
    """
}

@MainActor
private func stabStore(host: String) -> WorkTimerStore {
    let path = CheckTestScratch.suitePath(named: "check-stab-l6-\(host)")
    let defaults = UserDefaults(suiteName: path)!
    defaults.removePersistentDomain(forName: path)
    let tokenPath = CheckTestScratch.suitePath(named: "check-stab-l6-\(host).token")
    let tokenDefaults = UserDefaults(suiteName: tokenPath)!
    tokenDefaults.removePersistentDomain(forName: tokenPath)
    let tmp = FileManager.default.temporaryDirectory
    let tokenUsage = TokenUsageStore(
        defaults: tokenDefaults,
        homeDirectory: tmp.appendingPathComponent("check-stab-l6-home-\(host)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-stab-l6-cache-\(host).json", isDirectory: false)
    )
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: MyTokenRowURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil,
        tokenUsage: tokenUsage
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: stabUserID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.membershipConfirmed = true
    return store
}

@MainActor
private func stabCancelTasks(_ store: WorkTimerStore) {
    store.tickerTask?.cancel()
    store.refreshTask?.cancel()
    store.syncTask?.cancel()
    store.pokePollTask?.cancel()
}

/// 조건이 참이 될 때까지 **메인 액터에서** 기다린다(V0336 · V0238 과 같은 규약). `Task.yield()` 한 번에 기대면
/// 앞 Task 가 자리를 세우기 전에 다음 호출이 먼저 돌 수 있어, 순서를 이 대기로 못 박는다.
@MainActor
private func stabWaitUntil(_ condition: () -> Bool) async {
    for _ in 0..<250 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

private func stabBoardRequests(_ host: String) -> Int {
    MyTokenRowURLProtocol.requests(host: host, path: stabBoardPath).count
}

/// 뮤테이션: `fetchTokenBoardCoalesced` 의 합류 갈래를 지우면(언제나 새로 쏘면) 3건이 되어 빨갛다.
@MainActor
@Test
func stabL6OverlappingBoardLoadsShareOneRequest() async throws {
    let host = "stab-l6-overlap"
    MyTokenRowURLProtocol.configure(host: host, boardJSON: stabBoardJSON(), boardDelay: 0.4)
    let store = stabStore(host: host)
    defer { stabCancelTasks(store) }

    // 30초 루프 · 재오픈 킥 · 열기 토글 · [다시 시도] 가 응답 8초 사이에 겹친 모양 — 같은 달 넷. 루프 갈래는 진짜 가드를 지나게 세운다
    // (setMenuPresented·toggleTokenBoard 는 다른 패널 조회까지 킥해서 이 파일의 주장과 무관한 요청을 섞는다).
    store.isMenuPresented = true
    store.isTokenBoardVisible = true
    let a = Task { @MainActor in await store.performLoadTokenBoard() }
    store.loadTokenBoard()  // 재오픈 킥(setMenuPresented 가 부르는 그것) — Task 를 따로 띄운다
    let b = Task { @MainActor in await store.performLoadTokenBoard() }
    let c = Task { @MainActor in await store.refreshTokenBoardIfVisible() }
    _ = await (a.value, b.value, c.value)

    // loadTokenBoard() 는 Task 를 따로 띄운다 — 그 조회까지 끝나길 기다린다(자리가 비면 끝난 것이다).
    await stabWaitUntil { store.tokenBoardFetchInFlight == nil }
    #expect(stabBoardRequests(host) == 1, "같은 달 조회가 겹쳤는데 \(stabBoardRequests(host))건 나갔다 — 합치기가 안 붙었다")
    #expect(store.tokenBoard.map(\.userID) == [stabUserID], "합류한 쪽도 같은 응답으로 표를 채운다")
    #expect(store.tokenBoardLoaded && !store.tokenBoardFailed && !store.tokenBoardLoading)
    #expect(store.tokenBoardFetchInFlight == nil, "끝난 조회의 자리가 남으면 다음 주기가 끝난 응답을 재사용한다(캐시가 된다)")
}

/// 팝오버 내 행 조회(non-force)도 떠 있는 순위판 조회에 붙는다 — 같은 RPC · 같은 달이다.
@MainActor
@Test
func stabL6MyRowJoinsTheBoardFetchInFlight() async throws {
    let host = "stab-l6-myrow"
    MyTokenRowURLProtocol.configure(host: host, boardJSON: stabBoardJSON(), boardDelay: 0.4)
    let store = stabStore(host: host)
    defer { stabCancelTasks(store) }
    #expect(!store.isTokenBoardVisible, "전제: 순위판이 닫혀 있어야 내 행 경로가 스스로 쏜다")

    let board = Task { @MainActor in await store.performLoadTokenBoard() }
    await stabWaitUntil { store.tokenBoardFetchInFlight != nil }
    let mine = Task { @MainActor in await store.loadMyTokenRowIfDue() }
    _ = await (board.value, mine.value)

    #expect(stabBoardRequests(host) == 1, "내 행 조회가 떠 있는 보드 조회에 붙지 않았다(\(stabBoardRequests(host))건)")
    #expect(store.myTokenRow?.total == 21, "합류한 내 행 경로도 응답에서 내 행을 채집한다")
}

/// 기준선 ①: 업로드 직후 force 는 **붙지 않는다**(떠 있던 조회엔 방금 올린 값이 없다). 그리고 뒤에 오는 호출은 그 새 조회에 붙는다.
@MainActor
@Test
func stabL6ForcedMyRowFetchDoesNotJoinAnOlderFlight() async throws {
    let host = "stab-l6-force"
    MyTokenRowURLProtocol.configure(host: host, boardJSON: stabBoardJSON(), boardDelay: 0.4)
    let store = stabStore(host: host)
    defer { stabCancelTasks(store) }

    let board = Task { @MainActor in await store.performLoadTokenBoard() }
    await stabWaitUntil { store.tokenBoardFetchInFlight != nil }
    let first = store.tokenBoardFetchInFlight?.id
    let forced = Task { @MainActor in await store.loadMyTokenRowIfDue(force: true) }
    await stabWaitUntil { store.tokenBoardFetchInFlight?.id != first }
    #expect(store.tokenBoardFetchInFlight != nil, "force 조회가 자리를 넘겨받아야 한다")
    let later = Task { @MainActor in await store.performLoadTokenBoard() }
    _ = await (board.value, forced.value, later.value)

    #expect(stabBoardRequests(host) == 2, "force 는 새로 1건, 뒤의 보드 조회는 그 새 조회에 붙어야 한다(실제 \(stabBoardRequests(host))건)")
    #expect(store.tokenBoardFetchInFlight == nil)
}

/// 기준선 ②: 합치기는 **겹칠 때만**이다 — 끝난 뒤의 다음 주기는 다시 쏜다(캐시가 아니다). 다른 달도 따로 나간다.
@MainActor
@Test
func stabL6SequentialOrOtherMonthLoadsStillFetch() async throws {
    let host = "stab-l6-seq"
    MyTokenRowURLProtocol.configure(host: host, boardJSON: stabBoardJSON())
    let store = stabStore(host: host)
    defer { stabCancelTasks(store) }

    await store.performLoadTokenBoard()
    await store.performLoadTokenBoard()
    #expect(stabBoardRequests(host) == 2, "순차 호출이 합쳐졌다 — 끝난 응답을 재사용하면 30초 루프가 새 값을 못 받는다")

    MyTokenRowURLProtocol.configure(host: host, boardJSON: stabBoardJSON(), boardDelay: 0.3)
    let current = Task { @MainActor in await store.performLoadTokenBoard() }
    await stabWaitUntil { store.tokenBoardFetchInFlight != nil }
    let previousMonth = TokenBoardMonthNavigator.step(store.tokenBoardMonth, by: -1)
    let other = Task { @MainActor in _ = try? await store.fetchTokenBoardCoalesced(month: previousMonth) }
    _ = await (current.value, other.value)
    let bodies = MyTokenRowURLProtocol.requests(host: host, path: stabBoardPath).map(\.body)
    #expect(bodies.count == 2, "다른 달은 합치면 안 된다(실제 \(bodies.count)건)")
    #expect(bodies.contains { $0.contains(previousMonth) }, "지난달 조회가 자기 달 인자로 나가야 한다")
}

/// 세대가 바뀌면(계정 전환) 옛 세션의 조회에 붙지 않는다.
@MainActor
@Test
func stabL6NewSessionGenerationDoesNotJoinOldFlight() async throws {
    let host = "stab-l6-gen"
    MyTokenRowURLProtocol.configure(host: host, boardJSON: stabBoardJSON(), boardDelay: 0.4)
    let store = stabStore(host: host)
    defer { stabCancelTasks(store) }

    let month = store.tokenBoardMonth
    let old = Task { @MainActor in _ = try? await store.fetchTokenBoardCoalesced(month: month) }
    await stabWaitUntil { store.tokenBoardFetchInFlight != nil }
    store.sessionGeneration += 1
    let fresh = Task { @MainActor in _ = try? await store.fetchTokenBoardCoalesced(month: month) }
    _ = await (old.value, fresh.value)
    #expect(stabBoardRequests(host) == 2, "세대가 바뀌었는데 옛 조회에 붙었다(실제 \(stabBoardRequests(host))건)")
}

/// 기준선 ③: force 가 자리를 넘겨받은 뒤 **옛 조회가 먼저 끝나도** 새 자리를 지우지 않는다(`id` 표식).
/// 지우면 force 조회가 아직 떠 있는데 뒤에 오는 루프·재오픈이 다시 겹쳐 쏜다 — 합치기가 force 한 번에 풀린다.
/// 뮤테이션: `fetchTokenBoardCoalesced` 의 defer 에서 `id` 비교를 빼면(늘 비우면) 뒤 조회가 1건 더 나가 빨갛다.
@MainActor
@Test
func stabL6OlderFlightFinishingFirstKeepsTheForcedSlot() async throws {
    let host = "stab-l6-slot-id"
    MyTokenRowURLProtocol.configure(host: host, boardJSON: stabBoardJSON(), boardDelay: 0.3)
    let store = stabStore(host: host)
    defer { stabCancelTasks(store) }

    let board = Task { @MainActor in await store.performLoadTokenBoard() }
    await stabWaitUntil { stabBoardRequests(host) == 1 }
    let first = store.tokenBoardFetchInFlight?.id
    #expect(first != nil, "전제: 옛 조회가 자리를 세웠다")
    // force 조회는 응답을 오래 늦춘다 — 옛 조회(0.3s)가 **먼저** 끝나는 모양을 확정한다. configure 가 기록을 비우므로 아래 건수는 그 뒤의 것이다.
    MyTokenRowURLProtocol.configure(host: host, boardJSON: stabBoardJSON(), boardDelay: 1.5)
    let forced = Task { @MainActor in await store.loadMyTokenRowIfDue(force: true) }
    await stabWaitUntil { store.tokenBoardFetchInFlight.map { $0.id != first } ?? false }
    let forcedID = store.tokenBoardFetchInFlight?.id
    await stabWaitUntil { stabBoardRequests(host) == 1 }
    await board.value
    #expect(store.tokenBoardFetchInFlight?.id == forcedID, "옛 조회가 끝나며 force 조회의 자리를 지웠다")
    let later = Task { @MainActor in await store.performLoadTokenBoard() }
    _ = await (forced.value, later.value)
    #expect(stabBoardRequests(host) == 1, "뒤의 보드 조회는 떠 있는 force 조회에 붙어야 한다(실제 \(stabBoardRequests(host))건)")
    #expect(store.tokenBoardFetchInFlight == nil)
}

/// 기다리던 쪽이 취소되면 응답이 와도 반영하지 않고 조용히 빠진다(옛 '취소 → 조용히' 갈래). 공유 조회는 끊지 않는다 —
/// 같이 기다린 내 행 경로는 그 응답을 그대로 받는다.
/// 뮤테이션: 합류 갈래의 `Task.checkCancellation()` 을 빼면 취소된 순위판 조회가 표를 채워 빨갛다.
@MainActor
@Test
func stabL6CancelledJoinerStaysQuietWhileTheSharedFetchCompletes() async throws {
    let host = "stab-l6-cancel"
    MyTokenRowURLProtocol.configure(host: host, boardJSON: stabBoardJSON(), boardDelay: 0.4)
    let store = stabStore(host: host)
    defer { stabCancelTasks(store) }
    #expect(!store.isTokenBoardVisible, "전제: 순위판이 닫혀 있어야 내 행 경로가 스스로 쏜다")

    let mine = Task { @MainActor in await store.loadMyTokenRowIfDue() }
    await stabWaitUntil { store.tokenBoardFetchInFlight != nil }
    let joiner = Task { @MainActor in await store.performLoadTokenBoard() }
    await stabWaitUntil { store.tokenBoardLoading }
    joiner.cancel()
    _ = await (mine.value, joiner.value)

    #expect(stabBoardRequests(host) == 1)
    #expect(store.tokenBoard.isEmpty && !store.tokenBoardLoaded, "취소된 합류자가 응답을 표에 반영했다")
    #expect(!store.tokenBoardFailed, "취소는 실패 표시가 아니다")
    #expect(store.myTokenRow?.total == 21, "공유 조회는 끊기지 않고 내 행 경로가 응답을 받는다")
}
