import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

@MainActor
@Suite("순위 탭 스토어(rankme)")
struct RankingsStoreTests {
    // MARK: 응답 모양

    nonisolated static let league = #"""
    [
      {"team_id":"t-low","team_name":"낮은팀","weekly_goal_hours":40,"total_seconds":36000,"working_count":0,"member_count":2,"center":null},
      {"team_id":"team-rankme-1","team_name":"테스트팀","weekly_goal_hours":40,"total_seconds":0,"working_count":0,"member_count":3,"center":"seoul"},
      {"team_id":"t-high","team_name":"높은팀","weekly_goal_hours":40,"total_seconds":288000,"working_count":2,"member_count":4,"center":"busan"},
      {"team_id":"t-zero","team_name":"쉬는팀","weekly_goal_hours":40,"total_seconds":0,"working_count":0,"member_count":3,"center":null}
    ]
    """#

    nonisolated static func tokenRow(_ user: String, name: String, total: Int, today: Int = 0, todayDate: String = "2026-09-17") -> String {
        #"{"user_id":"\#(user)","display_name":"\#(name)","avatar_url":null,"claude_input":\#(total),"claude_output":0,"claude_cache_read":0,"claude_cache_creation":0,"codex_input":0,"codex_output":0,"total":\#(total),"today_total":\#(today),"today_date":"\#(todayDate)","codex_effective":0,"center":null}"#
    }

    nonisolated static func boardRow(_ user: String, name: String, score: Int, at: String) -> String {
        #"{"user_id":"\#(user)","display_name":"\#(name)","avatar_url":null,"best_score":\#(score),"best_at":"\#(at)","plays":3,"center":"seoul"}"#
    }

    // MARK: 시나리오

    @Test("시나리오: 탭 표시 → 리그(평균순·0시간 팀 숨김·내 팀은 유지) → 토큰(달 넘기기·비공개 칩) → 미니게임(종류 전환·어제 1등) · 쓰기 0건")
    func fullScenario() async throws {
        let harness = await RankMeHarness(label: "rank-scenario") { request in
            switch request.rpcName {
            case "team_weekly_leaderboard": return .json(Self.league)
            case "token_usage_board":
                if request.bodyText.contains("2026-08") {
                    return .json("[\(Self.tokenRow("u-aug", name: "팔월", total: 900))]")
                }
                return .json("[\(Self.tokenRow("u-small", name: "작은", total: 10)),\(Self.tokenRow(RankMeFixture.userID, name: "나", total: 5000, today: 70)),\(Self.tokenRow("u-old", name: "옛날", total: 300, today: 99, todayDate: "2026-09-10"))]")
            case "minigame_board":
                if request.bodyText.contains("flappy") {
                    return .json("[\(Self.boardRow("u-f", name: "플래피", score: 12, at: "2026-09-17T01:00:00Z"))]")
                }
                return .json("[\(Self.boardRow("u-b", name: "늦게", score: 900, at: "2026-09-17T03:00:00Z")),\(Self.boardRow(RankMeFixture.userID, name: "나", score: 950, at: "2026-09-17T02:00:00Z")),\(Self.boardRow("u-a", name: "먼저", score: 900, at: "2026-09-17T01:00:00Z"))]")
            case "minigame_yesterday_winner":
                if request.bodyText.contains("flappy") { return .json("[]") }
                return .json(#"[{"day":"2026-09-16","user_id":"u-a","display_name":"먼저","avatar_url":null,"score":990,"awarded":true,"center":"busan"}]"#)
            default: break
            }
            if request.path == "/rest/v1/profiles", request.method == "GET", request.query.contains("token_usage_collect") {
                return .json(#"[{"token_usage_public":false,"token_usage_collect":true,"focus_mode":true}]"#)
            }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.rankings

        // 보이지 않는 탭은 서버를 두드리지 않는다(장벽 뒤에 잰다 — 띄웠다면 장벽보다 먼저 기록된다).
        store.appDidBecomeActive()
        await harness.barrier()
        #expect(harness.requests(rpc: "team_weekly_leaderboard").isEmpty)
        #expect(!store.leagueState.isLoading)

        store.tabDidAppear()
        #expect(await baseWaitUntil { store.leagueState.hasLoaded })
        #expect(store.leagueDisplay.map(\.id) == ["t-high", "t-low", "team-rankme-1"], "평균 내림차순 + 0시간 팀 숨김 + 내 팀 유지")
        #expect(store.league.count == 4)
        #expect(store.myTeamID == RankMeFixture.teamID)
        try #require(store.leagueDisplay.count == 3, "리그가 안 섰다 — 인덱스 읽기 전에 멈춘다")
        #expect(RankingsText.leagueCaption(store.leagueDisplay[0]) == "각자 목표 40시간 · 총 80시간 00분 · 4명 · 2명 근무중")
        #expect(RankingsText.leagueAverage(store.leagueDisplay[0]) == "평균 20시간 00분")
        #expect(RankingsText.leaguePercent(store.leagueDisplay[0]) == 50)

        // 신선한 판은 다시 부르지 않는다.
        store.tabDidAppear()
        await harness.barrier()
        #expect(harness.requests(rpc: "team_weekly_leaderboard").count == 1)
        harness.clock.advance(RankingsStore.staleSeconds + 1)
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { harness.requests(rpc: "team_weekly_leaderboard").count == 2 })

        // AI 토큰
        store.select(board: .tokens)
        #expect(await baseWaitUntil { store.tokenState.hasLoaded })
        #expect(store.tokenMonth == "2026-09")
        #expect(store.tokenBoard.map(\.userID) == [RankMeFixture.userID, "u-old", "u-small"])
        #expect(store.myTokenUsagePublic == false, "내 행 비공개 칩")
        #expect(store.isCurrentTokenMonth)
        #expect(store.tokenTitle == "9월 AI 토큰 소모량")
        try #require(store.tokenBoard.count == 3, "토큰 판이 안 섰다 — 인덱스 읽기 전에 멈춘다")
        #expect(RankingsText.tokenToday(store.tokenBoard[0], todayKey: store.todayKey) == "오늘 +70 토큰")
        #expect(RankingsText.tokenToday(store.tokenBoard[1], todayKey: store.todayKey) == "오늘 +0 토큰", "어제 이후 스테일 행은 0")
        #expect(harness.requests(rpc: "token_usage_board").first?.jsonBody["p_month"] as? String == "2026-09")

        store.stepTokenMonth(by: 1)
        await harness.barrier()
        #expect(store.tokenMonth == "2026-09", "미래 달로는 못 간다")
        #expect(harness.requests(rpc: "token_usage_board").count == 1, "값이 그대로면 요청도 없다")

        store.stepTokenMonth(by: -1)
        #expect(store.tokenBoard.isEmpty, "옮기는 순간 이전 달 행을 비운다")
        #expect(await baseWaitUntil { store.tokenState.hasLoaded && store.tokenMonth == "2026-08" })
        #expect(store.tokenBoard.map(\.userID) == ["u-aug"])
        #expect(!store.isCurrentTokenMonth)
        #expect(harness.requests(rpc: "token_usage_board").last?.jsonBody["p_month"] as? String == "2026-08")

        // 미니게임
        store.select(board: .minigame)
        #expect(await baseWaitUntil { store.miniGameState.hasLoaded && store.miniGameWinner != nil })
        #expect(store.miniGameBoard.map(\.userID) == [RankMeFixture.userID, "u-a", "u-b"], "점수 → 먼저 낸 사람")
        #expect(store.myMiniGameRank == 1)
        #expect(store.miniGameWinner?.awarded == true)
        #expect(harness.requests(rpc: "minigame_board").first?.jsonBody["p_game"] as? String == "timing_bar")

        store.select(miniGame: .flappy)
        #expect(store.miniGameBoard.isEmpty && store.miniGameWinner == nil)
        #expect(await baseWaitUntil { store.miniGameState.hasLoaded && store.miniGameKind == .flappy && !store.miniGameBoard.isEmpty })
        await harness.barrier()
        #expect(store.miniGameBoard.map(\.userID) == ["u-f"])
        #expect(store.miniGameWinner == nil)
        #expect(store.myMiniGameRank == nil)

        // 읽기만 한다: RPC 는 전부 조회, 표는 GET 만.
        let writes = harness.requests.filter { $0.rpcName == nil && $0.method.uppercased() != "GET" }
        #expect(writes.isEmpty, "순위 탭이 쓰기를 냈다: \(writes.map { "\($0.method) \($0.path)" })")
        harness.expectNoForbiddenCalls()
    }

    @Test("딥링크: rankings/<board> 가 세그먼트를 고른다")
    func deepLinkSelectsBoard() async {
        let harness = await RankMeHarness(label: "rank-link") { _ in nil }
        defer { harness.tearDown() }
        harness.rankings.open(.rankings(.minigame))
        #expect(harness.rankings.board == .minigame)
        harness.rankings.open(.me)
        #expect(harness.rankings.board == .minigame, "다른 탭 라우트는 무시")
    }

    @Test("늦은 응답: 달을 옮긴 뒤 도착한 이전 달 응답은 버린다 · 게임 종류를 바꾼 뒤 도착한 응답도")
    func staleMonthAndKindResponsesAreDropped() async throws {
        let harness = await RankMeHarness(label: "rank-stale") { request in
            switch request.rpcName {
            case "token_usage_board":
                if request.bodyText.contains("2026-09") {
                    return .json("[\(Self.tokenRow("u-sept", name: "구월", total: 1))]")
                }
                return .json("[\(Self.tokenRow("u-aug", name: "팔월", total: 2))]")
            case "minigame_board":
                if request.bodyText.contains("timing_bar") {
                    return .json("[\(Self.boardRow("u-timing", name: "타이밍", score: 5, at: "2026-09-17T01:00:00Z"))]")
                }
                return .json("[\(Self.boardRow("u-flappy", name: "플래피", score: 7, at: "2026-09-17T01:00:00Z"))]")
            default:
                return nil
            }
        }
        defer { harness.tearDown() }
        let store = harness.rankings
        let september = BaseHold.rpc("token_usage_board", host: harness.host)
        store.select(board: .tokens)
        store.tabDidAppear()
        #expect(await september.waitHeld())
        store.stepTokenMonth(by: -1)
        #expect(await baseWaitUntil { store.tokenState.hasLoaded && store.tokenMonth == "2026-08" })
        #expect(await september.releaseAndWaitDelivered())
        await harness.barrier()
        #expect(store.tokenMonth == "2026-08")
        #expect(store.tokenBoard.map(\.userID) == ["u-aug"], "늦게 온 9월 응답이 8월 화면을 덮었다")

        let timing = BaseHold.rpc("minigame_board", host: harness.host)
        store.select(board: .minigame)
        #expect(await timing.waitHeld())
        store.select(miniGame: .flappy)
        #expect(await baseWaitUntil { store.miniGameState.hasLoaded && store.miniGameKind == .flappy })
        #expect(await timing.releaseAndWaitDelivered())
        await harness.barrier()
        #expect(store.miniGameBoard.map(\.userID) == ["u-flappy"], "늦게 온 타이밍 바 응답이 플래피 화면을 덮었다")
        harness.expectNoForbiddenCalls()
    }

    @Test("로그아웃 세대: 떠 있던 리그 응답은 로그아웃 뒤 버리고, reset 이 모든 판을 비운다")
    func generationGuardAndReset() async throws {
        let harness = await RankMeHarness(label: "rank-gen") { request in
            if request.rpcName == "team_weekly_leaderboard" {
                return .json(Self.league)
            }
            if request.path == "/auth/v1/logout" { return .json("{}") }
            if request.rpcName == "unregister_device" { return .json(#"{"status":"ok","removed":true}"#) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.rankings
        // 당겨서 새로고침(refreshable)처럼 스토어 inflight 밖에서 부른 조회 — reset 의 취소가 닿지 않으므로 세대·순번 가드만이 막는다.
        let hold = BaseHold.rpc("team_weekly_leaderboard", host: harness.host)
        let pull = Task { await store.loadLeague() }
        #expect(await baseWaitUntil { store.leagueState.isLoading })
        #expect(await hold.waitHeld())
        await harness.model.session.signOut()
        #expect(await hold.releaseAndWaitDelivered())
        await pull.value
        #expect(store.league.isEmpty, "로그아웃 뒤 늦게 온 리그가 화면에 섰다")
        let leagueCalls = harness.requests(rpc: "team_weekly_leaderboard").count
        store.tabDidAppear()
        await harness.barrier()
        #expect(!store.leagueState.isLoading && harness.requests(rpc: "team_weekly_leaderboard").count == leagueCalls, "로그아웃 상태에서 조회를 시작했다")
        #expect(!store.leagueState.hasLoaded)
        #expect(store.board == .league && store.tokenMonth == "2026-09" && store.myTokenUsagePublic == nil)
        harness.expectNoForbiddenCalls()
    }

    @Test("실패 상태: 리그 500 은 실패+다시 시도, 미니게임 함수 없음(PGRST202)은 실패가 아니라 '아직 없음'")
    func failureStates() async {
        let harness = await RankMeHarness(label: "rank-fail") { request in
            switch request.rpcName {
            case "team_weekly_leaderboard": return .json(#"{"message":"boom"}"#, status: 500)
            case "minigame_board": return .missingFunction("minigame_board")
            default: return nil
            }
        }
        defer { harness.tearDown() }
        let store = harness.rankings
        await store.loadLeague()
        #expect(store.leagueState.hasFailed && !store.leagueState.hasLoaded)
        #expect(RankingsText.leagueEmpty(hasLoaded: false, isLoading: false, hasFailed: true, unfilteredCount: 0) == RankingsText.leagueFailed)
        await store.loadMiniGame()
        #expect(store.miniGameState.hasLoaded && !store.miniGameState.hasFailed)
        #expect(RankingsText.miniGameEmptyText(hasLoaded: true, hasFailed: false) == RankingsText.miniGameEmpty)
        #expect(harness.model.session.isSignedIn, "5xx 로 로그아웃되면 안 된다")
    }

    // MARK: 신선도 · 달 넘김 · 칩 (rankme-fix)

    @Test("MU5 실패한 판은 30초 신선도 창 안이라도 탭 표시·active 에서 다시 읽는다(성공한 판은 안 읽는다)")
    func failedBoardRetriesInsideFreshWindow() async throws {
        let harness = await RankMeHarness(label: "rank-fix-mu5") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.rankings
        harness.enqueue("team_weekly_leaderboard", .json(Self.league))
        harness.enqueue("team_weekly_leaderboard", .json(#"{"message":"boom"}"#, status: 500))
        harness.enqueue("team_weekly_leaderboard", .json(Self.league))
        store.tabDidAppear()
        #expect(await baseWaitUntil { store.leagueState.hasLoaded && !store.leagueState.isLoading })
        // 당겨서 새로고침이 실패했다 — 마지막 성공 시각(loadedAt)은 방금이다.
        harness.clock.advance(1)
        await store.refresh()
        #expect(store.leagueState.hasFailed && store.leagueState.loadedAt != nil)
        store.tabDidDisappear()
        harness.clock.advance(1)
        store.tabDidAppear()
        #expect(await baseWaitUntil { harness.requests(rpc: "team_weekly_leaderboard").count == 3 }, "실패한 판을 신선하다고 보고 다시 읽지 않았다")
        #expect(await baseWaitUntil { !store.leagueState.hasFailed && !store.leagueState.isLoading })
        store.appDidBecomeActive()
        await harness.barrier()
        #expect(harness.requests(rpc: "team_weekly_leaderboard").count == 3, "성공한 신선한 판을 다시 읽었다")
    }

    @Test("MU6 앱을 켜 둔 채 달이 바뀌면 이번 달을 따라간다 · 사용자가 과거 달로 옮겼으면 그 달에 머문다")
    func tokenMonthFollowsMonthRollover() async throws {
        // 2026-09-30 23:59 KST.
        let lastMinute = ISO8601DateFormatter().date(from: "2026-09-30T14:59:00Z")!
        let harness = await RankMeHarness(label: "rank-fix-mu6", clockStart: lastMinute) { request in
            if request.rpcName == "token_usage_board" {
                return .json("[\(Self.tokenRow("u-\(request.bodyText.contains("2026-10") ? "oct" : "sep")", name: "달", total: 1))]")
            }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.rankings
        store.select(board: .tokens)
        store.tabDidAppear()
        #expect(await baseWaitUntil { store.tokenState.hasLoaded && !store.tokenState.isLoading })
        #expect(store.tokenMonth == "2026-09")
        store.tabDidDisappear()

        harness.clock.advance(120) // 10/1 00:01 KST
        store.tabDidAppear()
        #expect(store.tokenMonth == "2026-10", "달이 바뀌었는데 9월에 머문다")
        #expect(await baseWaitUntil { store.tokenState.hasLoaded && store.tokenBoard.map(\.userID) == ["u-oct"] })
        #expect(harness.requests(rpc: "token_usage_board").last?.jsonBody["p_month"] as? String == "2026-10")
        #expect(store.isCurrentTokenMonth)

        // 사용자가 9월로 옮긴 뒤 11월이 되면 9월에 머문다.
        store.stepTokenMonth(by: -1)
        #expect(await baseWaitUntil { store.tokenState.hasLoaded && store.tokenMonth == "2026-09" })
        harness.clock.advance(31 * 86_400)
        store.appDidBecomeActive()
        #expect(store.tokenMonth == "2026-09", "사용자가 고른 과거 달을 멋대로 옮겼다")
    }

    @Test("칩: 토큰 판 조회가 떠 있는 동안 나 탭에서 공개 설정을 바꾸면, 늦게 온 조회의 옛 공개 여부가 칩을 되돌리지 않는다")
    func lateTokenPrivacyDoesNotRevertChip() async throws {
        let harness = await RankMeHarness(label: "rank-fix-chip") { request in
            if request.rpcName == "token_usage_board" { return .json("[\(Self.tokenRow(RankMeFixture.userID, name: "나", total: 5))]") }
            if request.path == "/rest/v1/profiles", request.method == "GET", request.query.contains("token_usage_collect") {
                return .json(#"[{"token_usage_public":true,"token_usage_collect":true,"focus_mode":false}]"#)
            }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.rankings
        let privacyHold = BaseHold.install(host: harness.host) { $0.query.contains("token_usage_collect") }
        let load = Task { await store.loadTokens() }
        #expect(await privacyHold.waitHeld())
        store.noteTokenUsagePublic(false)
        #expect(await privacyHold.releaseAndWaitDelivered())
        await load.value
        #expect(store.tokenState.hasLoaded)
        #expect(store.myTokenUsagePublic == false, "저장 성공 뒤 늦게 온 옛 공개 여부가 '비공개' 칩을 지웠다")
        // 아무도 안 바꿨으면 서버값을 따른다.
        await store.loadTokens()
        #expect(store.myTokenUsagePublic == true)
    }

    // MARK: 순수 문구

    @Test("문구: 빈 목록 갈림 · 정족수 · 점수 · 토큰 제목 · 나 탭 공개 설정 반영")
    func texts() async {
        #expect(RankingsText.tokenEmpty(hasLoaded: false, isLoading: true, hasFailed: false, isCurrentMonth: true) == "불러오는 중…")
        #expect(RankingsText.tokenEmpty(hasLoaded: false, isLoading: false, hasFailed: true, isCurrentMonth: true) == "순위를 불러오지 못했어요")
        #expect(RankingsText.tokenEmpty(hasLoaded: true, isLoading: false, hasFailed: false, isCurrentMonth: true) == "아직 이번 달 소모량을 올린 사용자가 없어요")
        #expect(RankingsText.tokenEmpty(hasLoaded: true, isLoading: false, hasFailed: false, isCurrentMonth: false) == "이 달에는 기록이 없어요")
        #expect(RankingsText.leagueEmpty(hasLoaded: true, isLoading: false, hasFailed: false, unfilteredCount: 3) == "아직 이번 주 근무한 팀이 없어요")
        #expect(RankingsText.quorumCaption(players: 0) == "오늘은 아직 아무도 안 했어요 · 5명부터 지급")
        #expect(RankingsText.quorumCaption(players: 3) == "오늘 3명 참여 · 5명부터 지급")
        #expect(RankingsText.quorumCaption(players: 5) == "오늘 5명 참여 · 지급 조건 충족")
        #expect(RankingsText.score(1000) == "1000점")
        #expect(RankingsText.prizeCaption == "자정에 1·2·3등에게 루비 20·10·5")
        #expect(RankingsText.tokenTitle(month: "2025-12", now: RankMeFixture.now) == "2025년 12월 AI 토큰 소모량")

        let harness = await RankMeHarness(label: "rank-note") { _ in nil }
        defer { harness.tearDown() }
        harness.rankings.noteTokenUsagePublic(true)
        #expect(harness.rankings.myTokenUsagePublic == true)
    }
}
