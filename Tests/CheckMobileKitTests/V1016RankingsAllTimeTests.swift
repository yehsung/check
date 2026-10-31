@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// [순위] 탭 미니게임 판의 [오늘 | 역대] 전환. 서버·전선·정렬·날짜 글자는 코어 `MiniGameAllTimeEntry` 한 벌이고,
// 이 스위트가 재는 것은 **`RankingsStore` 의 판정**이다:
//  · 언제 받고 언제 안 받는가(요청 수로)
//  · 늦은 응답을 무엇으로 버리는가(게임 · 뒤에 떠난 요청 · 계정)
//  · 실패 세 갈래와 그려 둔 줄
//  · [오늘] 의 요청이 그대로인가
//
// 뷰(`#if os(iOS)`)는 macOS 스위트가 한 줄도 컴파일하지 않는다 — 자리·재사용은 소스 계약으로 재고, 컴파일은 `ios/scripts/build-sim.sh` 가 잰다.
@MainActor
@Suite(.serialized) struct V1016RankingsAllTimeTests {
    /// 역대 응답 두 줄 — **일부러 거꾸로** 준다(점수 오름차순). 클라가 다시 세우지 않으면 1등 자리에 작은 점수가 선다.
    private nonisolated static func allTimeJSON(top: Int) -> String {
        #"[{"user_id":"u-other","display_name":"구름빵","avatar_url":null,"best_score":10,"best_at":"2026-09-13T04:00:00Z","day":"2026-09-13","center":null},"#
            + #"{"user_id":"\#(RankMeFixture.userID)","display_name":"나","avatar_url":null,"best_score":\#(top),"best_at":"2026-09-02T01:00:00Z","day":"2026-09-02","center":"seoul"}]"#
    }

    private nonisolated static func todayJSON(_ user: String = "u-today") -> String {
        "[\(RankingsStoreTests.boardRow(user, name: "오늘", score: 7, at: "2026-09-17T01:00:00Z"))]"
    }

    /// 오늘 순위 · 어제 1등 · 역대가 모두 답하는 서버.
    private func makeHarness(_ label: String) async -> RankMeHarness {
        await RankMeHarness(label: label) { request in
            switch request.rpcName {
            case "minigame_board": return .json(Self.todayJSON())
            case "minigame_yesterday_winner": return .json("[]")
            case "minigame_alltime_board":
                return .json(Self.allTimeJSON(top: request.bodyText.contains(#""p_game":"flappy""#) ? 300 : 500))
            default: return nil
            }
        }
    }

    /// 미니게임 판을 [역대] 로 연다. 오늘 표는 안 받는 길이다(값을 먼저 고른 뒤 판을 연다).
    private func openAllTime(_ harness: RankMeHarness) async {
        harness.rankings.select(miniGameScope: .allTime)
        harness.rankings.select(board: .minigame)
        #expect(await baseWaitUntil { harness.rankings.miniGameAllTimeState.hasLoaded && !harness.rankings.miniGameAllTimeState.isLoading })
    }

    private func gameInBody(_ request: MobileStubRequest) -> String? {
        request.jsonBody["p_game"] as? String
    }

    // MARK: - 받는 때 · 안 받는 때

    @Test("[오늘] 은 역대를 부르지 않는다: 탭 표시 · 판 고르기 · 게임 바꾸기 · 새로고침 · 재진입 전부 0건이고 오늘 요청 수는 그대로다")
    func todayNeverFetchesAllTime() async {
        let harness = await makeHarness("v1016-today")
        defer { harness.tearDown() }
        let store = harness.rankings
        #expect(store.miniGameScope == .today, "전환의 기본은 [오늘] 이다")

        store.select(board: .minigame)
        #expect(await baseWaitUntil { store.miniGameState.hasLoaded && harness.requests(rpc: "minigame_yesterday_winner").count == 1 })
        #expect(await baseWaitUntil { !store.miniGameState.isLoading })
        #expect(harness.requests(rpc: "minigame_board").count == 1)

        // 신선한 표에 탭 표시는 요청을 더 내지 않는다(같은 틱에 부르는 경우는 아래 `sameTickOpenKeepsTodayRequests`).
        store.tabDidAppear()
        await harness.barrier()
        #expect(harness.requests(rpc: "minigame_board").count == 1)

        store.select(miniGame: .flappy)
        #expect(await baseWaitUntil { harness.requests(rpc: "minigame_yesterday_winner").count == 2 })
        #expect(await baseWaitUntil { !store.miniGameState.isLoading })
        #expect(harness.requests(rpc: "minigame_board").map(gameInBody) == ["timing_bar", "flappy"])

        await store.refresh()
        #expect(harness.requests(rpc: "minigame_board").count == 3)
        #expect(harness.requests(rpc: "minigame_yesterday_winner").count == 3)

        store.tabDidDisappear()
        harness.clock.advance(RankingsStore.staleSeconds + 1)
        store.tabDidAppear()
        #expect(await baseWaitUntil { harness.requests(rpc: "minigame_yesterday_winner").count == 4 })
        await harness.barrier()

        #expect(harness.requests(rpc: "minigame_alltime_board").isEmpty, "[오늘] 을 보는 사람에게 역대 호출이 나갔다")
        #expect(harness.requests(rpc: "minigame_board").count == 4)
        harness.expectNoForbiddenCalls()
    }

    @Test("같은 틱의 판 고르기 + 탭 표시는 [오늘] 요청 2건 그대로다 — 오늘 경로는 먼저 깃발을 세우지 않는다(이번 변경이 바꾸지 않는 값)")
    func sameTickOpenKeepsTodayRequests() async {
        let harness = await makeHarness("v1016-open-tick")
        defer { harness.tearDown() }
        let store = harness.rankings
        store.select(board: .minigame)
        store.tabDidAppear()
        #expect(await baseWaitUntil { harness.requests(rpc: "minigame_board").count == 2 && !store.miniGameState.isLoading })
        await harness.barrier()
        #expect(harness.requests(rpc: "minigame_board").count == 2)
        #expect(harness.requests(rpc: "minigame_alltime_board").isEmpty)
    }

    @Test("띄운 조회는 떠날 때의 보기를 지킨다: 같은 틱에 [오늘]→[역대] 를 눌러도 오늘 조회가 역대 조회로 바뀌지 않는다")
    func launchedFetchKeepsItsScope() async {
        let harness = await makeHarness("v1016-capture-scope")
        defer { harness.tearDown() }
        let store = harness.rankings
        await openAllTime(harness)
        #expect(harness.requests(rpc: "minigame_alltime_board").count == 1)
        #expect(harness.requests(rpc: "minigame_board").isEmpty)

        store.select(miniGameScope: .today)
        store.select(miniGameScope: .allTime)
        #expect(await baseWaitUntil { harness.requests(rpc: "minigame_yesterday_winner").count == 1 && !store.miniGameState.isLoading }, "오늘 조회가 사라졌다")
        await harness.barrier()
        #expect(harness.requests(rpc: "minigame_board").count == 1)
        #expect(harness.requests(rpc: "minigame_alltime_board").count == 1, "신선한 역대 표를 오늘 조회 자리에서 다시 받았다")
        #expect(store.miniGameState.hasLoaded)
    }

    @Test("띄운 조회는 떠날 때의 판을 지킨다: 같은 틱에 AI 토큰→미니게임을 골라도 토큰 조회가 미니게임 조회로 바뀌지 않는다")
    func launchedFetchKeepsItsBoard() async {
        let harness = await makeHarness("v1016-capture-board")
        defer { harness.tearDown() }
        let store = harness.rankings
        store.select(board: .tokens)
        store.select(board: .minigame)
        #expect(await baseWaitUntil { harness.requests(rpc: "minigame_yesterday_winner").count >= 1 && !store.miniGameState.isLoading && !store.tokenState.isLoading })
        await harness.barrier()
        #expect(harness.requests(rpc: "token_usage_board").count == 1, "토큰 조회가 사라졌다")
        #expect(harness.requests(rpc: "minigame_board").count == 1, "한 번 고른 판을 두 번 받았다")
    }

    @Test("[역대] 를 고를 때 한 번 · 정렬은 클라가 다시 세운다 · 같은 쪽 다시 누름과 30초 안의 왕복은 안 부른다")
    func selectingFetchesOnce() async throws {
        let harness = await makeHarness("v1016-select")
        defer { harness.tearDown() }
        let store = harness.rankings
        store.select(board: .minigame)
        #expect(await baseWaitUntil { store.miniGameState.hasLoaded })
        #expect(await baseWaitUntil { harness.requests(rpc: "minigame_yesterday_winner").count == 1 && !store.miniGameState.isLoading })
        #expect(harness.requests(rpc: "minigame_alltime_board").isEmpty)

        store.select(miniGameScope: .allTime)
        #expect(store.miniGameAllTimeState.isLoading, "고른 순간 '불러오는 중'이 서야 빈 표 문구가 깜빡이지 않는다")
        #expect(await baseWaitUntil { store.miniGameAllTimeState.hasLoaded })
        #expect(harness.requests(rpc: "minigame_alltime_board").map(gameInBody) == ["timing_bar"])
        #expect(store.miniGameAllTime.map(\.bestScore) == [500, 10], "서버 정렬을 믿었다")
        #expect(store.miniGameAllTime.first?.dayCaption == "9/2")
        #expect(store.miniGameAllTime.first?.userID == store.myUserID, "내 줄 판정 재료가 어긋났다")

        store.select(miniGameScope: .allTime)
        store.select(miniGameScope: .today)
        store.select(miniGameScope: .allTime)
        await harness.barrier()
        #expect(harness.requests(rpc: "minigame_alltime_board").count == 1, "오가며 누를 때마다 요청이 나갔다")
        #expect(harness.requests(rpc: "minigame_board").count == 1, "신선한 오늘 표를 다시 받았다")
        harness.expectNoForbiddenCalls()
    }

    @Test("[역대] 인 채 게임 바꾸기 · 당겨서 새로고침 · 낡은 탭 재진입에서 받는다 · 신선한 재진입은 안 받는다 · 오늘 표는 그 사이 안 받는다")
    func allTimeTriggers() async {
        let harness = await makeHarness("v1016-triggers")
        defer { harness.tearDown() }
        let store = harness.rankings
        await openAllTime(harness)
        #expect(harness.requests(rpc: "minigame_alltime_board").count == 1)

        store.tabDidDisappear()
        store.tabDidAppear()
        await harness.barrier()
        #expect(harness.requests(rpc: "minigame_alltime_board").count == 1, "신선한 표를 재진입마다 다시 받았다")

        store.tabDidDisappear()
        harness.clock.advance(RankingsStore.staleSeconds + 1)
        store.tabDidAppear()
        #expect(await baseWaitUntil { harness.requests(rpc: "minigame_alltime_board").count == 2 }, "낡은 표를 재진입에서 안 받았다")
        #expect(await baseWaitUntil { !store.miniGameAllTimeState.isLoading })

        await store.refresh()
        #expect(harness.requests(rpc: "minigame_alltime_board").count == 3, "당겨서 새로고침이 역대를 안 받았다")

        store.select(miniGame: .flappy)
        #expect(store.miniGameAllTime.isEmpty, "옮기는 순간 옛 게임 줄을 비운다")
        #expect(await baseWaitUntil { store.miniGameAllTime.first?.bestScore == 300 })
        #expect(harness.requests(rpc: "minigame_alltime_board").last.flatMap(gameInBody) == "flappy")
        #expect(harness.requests(rpc: "minigame_alltime_board").count == 4)

        await harness.barrier()
        #expect(harness.requests(rpc: "minigame_board").isEmpty, "[역대] 를 보는데 오늘 표를 받았다")
        #expect(harness.requests(rpc: "minigame_yesterday_winner").isEmpty)
        harness.expectNoForbiddenCalls()
    }

    @Test("[역대] 에서 게임을 바꾼 뒤 [오늘] 로 오면 새 게임 오늘 표를 받는다 — 오늘 쪽 깃발이 굳어 있지 않다")
    func returningToTodayLoadsTheNewGame() async {
        let harness = await makeHarness("v1016-return")
        defer { harness.tearDown() }
        let store = harness.rankings
        await openAllTime(harness)
        store.select(miniGame: .flappy)
        #expect(await baseWaitUntil { store.miniGameAllTime.first?.bestScore == 300 })
        #expect(!store.miniGameState.isLoading, "안 받는 오늘 표에 '불러오는 중'이 섰다")

        store.select(miniGameScope: .today)
        #expect(await baseWaitUntil { store.miniGameState.hasLoaded })
        #expect(harness.requests(rpc: "minigame_board").map(gameInBody) == ["flappy"])
        #expect(store.miniGameBoard.map(\.userID) == ["u-today"])
    }

    @Test("[오늘] 에서 게임을 바꾸면 역대 줄을 비우고 요청은 없다 · 다음 [역대] 가 그 게임을 받는다")
    func changingGameOnTodayClearsAllTimeWithoutFetching() async {
        let harness = await makeHarness("v1016-clear")
        defer { harness.tearDown() }
        let store = harness.rankings
        await openAllTime(harness)
        #expect(store.miniGameAllTime.first?.bestScore == 500)
        store.select(miniGameScope: .today)
        #expect(await baseWaitUntil { store.miniGameState.hasLoaded && !store.miniGameState.isLoading })

        store.select(miniGame: .flappy)
        #expect(store.miniGameAllTime.isEmpty && !store.miniGameAllTimeState.hasLoaded)
        await harness.barrier()
        #expect(harness.requests(rpc: "minigame_alltime_board").count == 1)

        store.select(miniGameScope: .allTime)
        #expect(await baseWaitUntil { store.miniGameAllTime.first?.bestScore == 300 })
        #expect(harness.requests(rpc: "minigame_alltime_board").last.flatMap(gameInBody) == "flappy")
    }

    @Test("다른 판을 보는 동안 고른 값은 기억만 한다 · 그 판을 열 때 받는다")
    func scopeOnAnotherBoardOnlyRemembers() async {
        let harness = await RankMeHarness(label: "v1016-otherboard") { request in
            switch request.rpcName {
            case "team_weekly_leaderboard": return .json(RankingsStoreTests.league)
            case "minigame_alltime_board": return .json(Self.allTimeJSON(top: 500))
            default: return nil
            }
        }
        defer { harness.tearDown() }
        let store = harness.rankings
        #expect(store.board == .league)
        store.select(miniGameScope: .allTime)
        await harness.barrier()
        #expect(store.miniGameScope == .allTime)
        #expect(harness.requests(rpc: "minigame_alltime_board").isEmpty)
        #expect(harness.requests(rpc: "team_weekly_leaderboard").isEmpty, "전환이 보고 있는 다른 판을 건드렸다")
        store.select(board: .minigame)
        #expect(await baseWaitUntil { store.miniGameAllTimeState.hasLoaded })
        #expect(harness.requests(rpc: "minigame_alltime_board").count == 1)
    }

    @Test("한 틱에 [역대]→[오늘]→[역대] 를 눌러도 요청은 하나 · [역대]→[오늘] 로 끝나도 '불러오는 중'이 굳지 않는다")
    func sameTickTogglesDoNotDoubleFetchOrStick() async {
        let harness = await makeHarness("v1016-tick")
        defer { harness.tearDown() }
        let store = harness.rankings
        store.select(board: .minigame)
        #expect(await baseWaitUntil { harness.requests(rpc: "minigame_yesterday_winner").count == 1 && !store.miniGameState.isLoading })

        store.select(miniGameScope: .allTime)
        store.select(miniGameScope: .today)
        store.select(miniGameScope: .allTime)
        #expect(await baseWaitUntil { store.miniGameAllTimeState.hasLoaded && !store.miniGameAllTimeState.isLoading })
        await harness.barrier()
        #expect(harness.requests(rpc: "minigame_alltime_board").count == 1)

        store.select(miniGameScope: .today)
        harness.clock.advance(RankingsStore.staleSeconds + 1)
        store.select(miniGameScope: .allTime)
        store.select(miniGameScope: .today)
        #expect(await baseWaitUntil { !store.miniGameAllTimeState.isLoading }, "다른 보기로 넘어갔다고 '불러오는 중'이 안 내려왔다")
    }

    // MARK: - 늦은 응답

    @Test("게임을 바꾼 뒤 닿은 옛 게임 역대는 버린다 — [역대] 인 채 · [오늘] 로 내려와 바꾼 경우 둘 다")
    func lateResponseAfterGameChangeIsDropped() async {
        let harness = await makeHarness("v1016-late-game")
        defer { harness.tearDown() }
        let store = harness.rankings
        store.select(miniGameScope: .allTime)
        let hold = BaseHold.rpc("minigame_alltime_board", host: harness.host)
        store.select(board: .minigame)
        #expect(await hold.waitHeld())
        store.select(miniGame: .flappy)
        #expect(await baseWaitUntil { store.miniGameAllTime.first?.bestScore == 300 })
        #expect(await hold.releaseAndWaitDelivered())
        await harness.barrier()
        #expect(store.miniGameAllTime.first?.bestScore == 300, "늦게 온 타이밍 바 역대가 플래피 화면을 덮었다")
        #expect(!store.miniGameAllTimeState.isLoading)

        let other = await makeHarness("v1016-late-game-today")
        defer { other.tearDown() }
        let otherStore = other.rankings
        otherStore.select(miniGameScope: .allTime)
        let otherHold = BaseHold.rpc("minigame_alltime_board", host: other.host)
        otherStore.select(board: .minigame)
        #expect(await otherHold.waitHeld())
        otherStore.select(miniGameScope: .today)
        otherStore.select(miniGame: .flappy)
        #expect(await otherHold.releaseAndWaitDelivered())
        await other.barrier()
        #expect(otherStore.miniGameAllTime.isEmpty, "[오늘] 에서 게임을 바꿨는데 옛 게임 역대가 꽂혔다")
        #expect(!otherStore.miniGameAllTimeState.hasLoaded && !otherStore.miniGameAllTimeState.isLoading)
    }

    @Test("뒤에 떠난 요청이 있으면 먼저 떠난 응답은 버린다")
    func olderRequestIsDropped() async {
        let harness = await RankMeHarness(label: "v1016-late-serial") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.rankings
        // 붙잡힌 요청은 놓아준 뒤에야 스텁에 닿으므로 첫 응답을 먹는 쪽이 **뒤에 떠난** 요청이다.
        harness.enqueue("minigame_alltime_board", .json(Self.allTimeJSON(top: 500)))
        harness.enqueue("minigame_alltime_board", .json(Self.allTimeJSON(top: 100)))
        store.select(miniGameScope: .allTime)
        let hold = BaseHold.rpc("minigame_alltime_board", host: harness.host)
        store.select(board: .minigame)
        #expect(await hold.waitHeld())
        await store.refresh()
        #expect(store.miniGameAllTime.first?.bestScore == 500)
        #expect(await hold.releaseAndWaitDelivered())
        await harness.barrier()
        #expect(store.miniGameAllTime.first?.bestScore == 500, "먼저 떠난 응답이 새 표를 덮었다")
        #expect(!store.miniGameAllTimeState.isLoading)
    }

    @Test("[오늘] 로 돌아간 사이 닿은 응답은 쓴다 — 게임도 계정도 그대로라 버릴 까닭이 없고, 다음 [역대] 가 다시 안 묻는다")
    func responseArrivingWhileOnTodayIsKept() async {
        let harness = await makeHarness("v1016-keep")
        defer { harness.tearDown() }
        let store = harness.rankings
        store.select(miniGameScope: .allTime)
        let hold = BaseHold.rpc("minigame_alltime_board", host: harness.host)
        store.select(board: .minigame)
        #expect(await hold.waitHeld())
        store.select(miniGameScope: .today)
        #expect(await hold.releaseAndWaitDelivered())
        #expect(await baseWaitUntil { store.miniGameAllTimeState.hasLoaded })
        store.select(miniGameScope: .allTime)
        await harness.barrier()
        #expect(harness.requests(rpc: "minigame_alltime_board").count == 1)
    }

    @Test("로그아웃 뒤 닿은 응답은 버리고 역대 줄·상태를 비운다 · 보기 선택은 남는다 · 다음 계정이 판을 열면 새로 받는다")
    func signOutDropsLateResponseAndClears() async {
        let harness = await RankMeHarness(label: "v1016-signout") { request in
            if request.rpcName == "minigame_alltime_board" { return .json(Self.allTimeJSON(top: 500)) }
            if request.path == "/auth/v1/logout" { return .json("{}") }
            if request.rpcName == "unregister_device" { return .json(#"{"status":"ok","removed":true}"#) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.rankings
        await openAllTime(harness)
        #expect(!store.miniGameAllTime.isEmpty)

        // 당겨서 새로고침처럼 스토어 inflight 밖에서 부른 조회 — reset 의 취소가 닿지 않으므로 세대·순번 가드만이 막는다.
        let hold = BaseHold.rpc("minigame_alltime_board", host: harness.host)
        let pull = Task { await store.loadMiniGameAllTime() }
        #expect(await hold.waitHeld())
        await harness.model.session.signOut()
        #expect(store.miniGameAllTime.isEmpty, "로그아웃이 남의 역대 줄을 안 비웠다")
        #expect(store.miniGameAllTimeState == RankingsLoadState())
        #expect(store.miniGameScope == .allTime, "로그아웃이 보기 선택을 되돌렸다(계정이 아니라 이 실행의 값이다)")
        #expect(await hold.releaseAndWaitDelivered())
        await pull.value
        await harness.barrier()
        #expect(store.miniGameAllTime.isEmpty, "로그아웃 뒤 늦게 온 역대가 화면에 섰다")
        #expect(store.miniGameAllTimeState == RankingsLoadState())
    }

    @Test("reset 은 '준비 중' 표식도 비운다 · 같은 실행의 다음 계정은 [역대] 로 판을 열 때 다시 묻는다")
    func resetClearsUnavailableAndNextOpenRefetches() async {
        let harness = await RankMeHarness(label: "v1016-reset") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.rankings
        await openAllTime(harness)
        #expect(store.miniGameAllTimeUnavailable)

        store.reset()
        #expect(!store.miniGameAllTimeUnavailable, "접힌 표식을 다음 계정에 물려줬다")
        #expect(store.board == .league && store.miniGameKind == .timingBar && store.miniGameScope == .allTime)

        harness.enqueue("minigame_alltime_board", .json(Self.allTimeJSON(top: 500)))
        store.select(board: .minigame)
        #expect(await baseWaitUntil { store.miniGameAllTime.first?.bestScore == 500 })
        #expect(harness.requests(rpc: "minigame_alltime_board").count == 2)
    }

    // MARK: - 실패 세 갈래

    @Test("함수 없는 서버는 준비 중이다: 실패 아님 · [다시 시도] 없음 · 30초 안에 오가도 404 를 다시 안 두드린다 · 올라오면 표가 선다")
    func missingFunctionIsComingSoon() async {
        let harness = await RankMeHarness(label: "v1016-missing") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.rankings
        await openAllTime(harness)
        #expect(store.miniGameAllTimeUnavailable)
        #expect(!store.miniGameAllTimeState.hasFailed && store.miniGameAllTimeState.hasLoaded)
        #expect(store.miniGameAllTimeEmptyText == GamesMiniGameText.allTimeUnavailableCaption)
        #expect(!store.miniGameAllTimeShowsRetry, "'준비 중' 옆에 [다시 시도] 가 붙으면 같은 404 를 영원히 두드린다")

        store.select(miniGameScope: .today)
        store.select(miniGameScope: .allTime)
        await harness.barrier()
        #expect(harness.requests(rpc: "minigame_alltime_board").count == 1)

        harness.enqueue("minigame_alltime_board", .json(Self.allTimeJSON(top: 500)))
        await store.refresh()
        #expect(!store.miniGameAllTimeUnavailable, "함수가 올라온 뒤에도 '준비 중'이 남았다")
        #expect(store.miniGameAllTime.first?.bestScore == 500)
    }

    @Test("그 밖의 실패: [다시 시도] 가 붙고 준비 중으로 안 접힌다 · 다시 보러 오면 다시 묻는다 · 재시도가 성공하면 표가 선다")
    func otherFailureOffersRetry() async {
        let harness = await RankMeHarness(label: "v1016-fail") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.rankings
        harness.enqueue("minigame_alltime_board", .networkFailure())
        harness.enqueue("minigame_alltime_board", .json(#"{"message":"boom"}"#, status: 500))
        harness.enqueue("minigame_alltime_board", .json(Self.allTimeJSON(top: 500)))

        store.select(miniGameScope: .allTime)
        store.select(board: .minigame)
        #expect(await baseWaitUntil { store.miniGameAllTimeState.hasFailed })
        #expect(!store.miniGameAllTimeUnavailable, "네트워크 실패를 '준비 중'으로 접었다")
        #expect(store.miniGameAllTimeShowsRetry)
        #expect(store.miniGameAllTimeEmptyText == GamesMiniGameText.allTimeFailedCaption)
        #expect(await baseWaitUntil { !store.miniGameAllTimeState.isLoading })

        // 다시 보러 온 것이 곧 재시도 의사다(30초 안이어도).
        store.select(miniGameScope: .today)
        store.select(miniGameScope: .allTime)
        #expect(await baseWaitUntil { harness.requests(rpc: "minigame_alltime_board").count == 2 })
        #expect(await baseWaitUntil { store.miniGameAllTimeState.hasFailed && !store.miniGameAllTimeState.isLoading }, "5xx 도 실패다")
        #expect(harness.model.session.isSignedIn, "5xx 로 로그아웃되면 안 된다")

        await store.loadMiniGameAllTime()
        #expect(!store.miniGameAllTimeState.hasFailed && store.miniGameAllTime.first?.bestScore == 500)
        #expect(!store.miniGameAllTimeShowsRetry)
    }

    @Test("취소는 아무것도 안 바꾼다 — 첫 조회 · 줄이 있을 때 · [다시 시도] 가 취소돼도 실패 카드가 남는다")
    func cancellationChangesNothing() async {
        let harness = await RankMeHarness(label: "v1016-cancel") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.rankings
        store.select(miniGameScope: .allTime)

        harness.enqueue("minigame_alltime_board", .networkFailure(.cancelled))
        await store.loadMiniGameAllTime()
        #expect(!store.miniGameAllTimeState.hasFailed && !store.miniGameAllTimeState.hasLoaded && !store.miniGameAllTimeUnavailable)
        #expect(!store.miniGameAllTimeState.isLoading)

        harness.enqueue("minigame_alltime_board", .networkFailure())
        await store.loadMiniGameAllTime()
        #expect(store.miniGameAllTimeShowsRetry)
        harness.enqueue("minigame_alltime_board", .networkFailure(.cancelled))
        await store.loadMiniGameAllTime()
        #expect(store.miniGameAllTimeShowsRetry, "[다시 시도] 가 취소되자 버튼 없는 '불러오는 중' 카드로 굳었다")
        #expect(store.miniGameAllTimeEmptyText == GamesMiniGameText.allTimeFailedCaption)

        harness.enqueue("minigame_alltime_board", .json(Self.allTimeJSON(top: 500)))
        await store.loadMiniGameAllTime()
        let loaded = store.miniGameAllTimeState
        harness.enqueue("minigame_alltime_board", .networkFailure(.cancelled))
        harness.clock.advance(5)
        await store.loadMiniGameAllTime()
        #expect(store.miniGameAllTime.first?.bestScore == 500, "취소가 그려 둔 줄을 지웠다")
        #expect(store.miniGameAllTimeState == loaded, "취소가 상태를 바꿨다")
    }

    @Test("이미 줄이 있으면 실패해도 줄을 그대로 둔다 · [다시 시도] 를 안 띄운다 · 다음 재진입이 다시 묻는다")
    func rowsSurviveFailure() async {
        let harness = await RankMeHarness(label: "v1016-rows") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.rankings
        harness.enqueue("minigame_alltime_board", .json(Self.allTimeJSON(top: 500)))
        await openAllTime(harness)
        #expect(store.miniGameAllTime.first?.bestScore == 500)

        harness.enqueue("minigame_alltime_board", .networkFailure())
        await store.refresh()
        #expect(store.miniGameAllTimeState.hasFailed)
        #expect(store.miniGameAllTime.map(\.bestScore) == [500, 10], "실패가 그려 둔 줄을 지웠다")
        #expect(!store.miniGameAllTimeShowsRetry, "그려 둔 표 위에 실패 카드가 섰다")

        harness.enqueue("minigame_alltime_board", .json(Self.allTimeJSON(top: 600)))
        store.tabDidDisappear()
        store.tabDidAppear()
        #expect(await baseWaitUntil { store.miniGameAllTime.first?.bestScore == 600 }, "실패한 표를 신선하다고 보고 다시 안 물었다")
    }

    // MARK: - 글자

    @Test("보이스오버: [역대] 줄은 날짜까지 읽는다 · [오늘] 줄 글자는 그대로다")
    func rowAccessibility() {
        let entry = MiniGameBoardEntry(userID: "u", name: "구름빵", avatarURL: nil, bestScore: 40, bestAt: nil, plays: 0, center: "서울")
        let today = RankingsText.miniGameRowAccessibility(rank: 1, entry: entry, isMe: true)
        #expect(today == "1위, 구름빵, 서울센터, \(RankingsText.score(40)), \(RankingsText.meChip)")
        let allTime = RankingsText.miniGameRowAccessibility(rank: 1, entry: entry, isMe: true, dayCaption: "9/13")
        #expect(allTime == "1위, 구름빵, 서울센터, \(RankingsText.score(40)), 9/13 기록, \(RankingsText.meChip)")
    }

    @Test("부제는 보는 표를 따른다: [역대] 는 '오늘 · 자정에 마감해요'라 말하지 않는다 · [오늘] 과 다른 판 글자는 그대로다 · 화면이 이 값을 그린다")
    func subtitleFollowsScope() async throws {
        let harness = await makeHarness("v1016-subtitle")
        defer { harness.tearDown() }
        let store = harness.rankings
        #expect(store.boardSubtitle == "이번 주 · 월요일 0시에 새로 시작해요")

        store.select(miniGameScope: .allTime)
        #expect(store.boardSubtitle == "이번 주 · 월요일 0시에 새로 시작해요", "미니게임 보기가 다른 판 부제를 바꿨다")
        store.select(board: .tokens)
        #expect(store.boardSubtitle == "이번 달 · 1일에 새로 시작해요")

        store.select(board: .minigame)
        #expect(store.boardSubtitle == "역대 · 마감 없이 이어져요")
        #expect(!store.boardSubtitle.contains("오늘") && !store.boardSubtitle.contains("자정"), "역대 표는 오늘 판이 아니고 자정에 마감하지도 않는다")

        store.select(miniGameScope: .today)
        #expect(store.boardSubtitle == "오늘 · 자정에 마감해요")
        await harness.barrier()

        // 뷰는 macOS 스위트가 컴파일하지 않는다 — 스토어 값이 맞아도 화면이 판만 넘기면 말짱 도루묵이다.
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Rankings/RankingsTab.swift")
        #expect(tab.contains("RankingsBoardSubtitle(text: store.boardSubtitle)"), "부제가 스토어 값을 안 쓴다")
        #expect(!tab.contains("RankingsText.boardSubtitle("), "화면이 판만 보고 부제를 고른다")
    }

    @Test("빈 칸 문구는 [게임] 탭과 한 벌이다 — 불러오는 중 · 아직 없음")
    func emptyTextSharesTheGamesTable() async {
        let harness = await RankMeHarness(label: "v1016-empty") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.rankings
        #expect(store.miniGameAllTimeEmptyText == GamesMiniGameText.loadingCaption)
        harness.enqueue("minigame_alltime_board", .json("[]"))
        await store.loadMiniGameAllTime()
        #expect(store.miniGameAllTimeEmptyText == GamesMiniGameText.emptyBoard)
        #expect(!store.miniGameAllTimeShowsRetry)
    }

    // MARK: - 소스 계약(폰 뷰는 macOS 에서 컴파일되지 않는다)

    @Test("화면: 전환은 머리 줄 아래 · 제목은 scope.boardTitle · 행 뷰 한 벌 · 어제 1등·상금·정족수는 [오늘] 에만 · 글자는 [게임] 탭과 한 벌")
    func viewContract() throws {
        let code = try IntegrationContractTests.code("Sources/CheckMobileKit/Rankings/RankingsBoardSections.swift")
        let sectionStart = try #require(code.range(of: "struct RankingsMiniGameSection: View"))
        let sectionEnd = try #require(code.range(of: "struct RankingsPrizeLine: View"))
        let section = String(code[sectionStart.lowerBound..<sectionEnd.lowerBound])

        // 전환은 머리 trailing 안이 아니라 그 다음 줄이다(제목 + 알약 둘은 좁은 폰에서 꺾인다).
        let header = try #require(section.range(of: "RankingsSectionHeader(title: scope.boardTitle) {"))
        let menu = try #require(section.range(of: "RankingsGameMenu(selected:"))
        let picker = try #require(section.range(of: "GamesBoardScopePicker(selected: scope)"))
        #expect(header.upperBound < menu.lowerBound && menu.upperBound < picker.lowerBound)
        let afterMenu = section[menu.upperBound..<picker.lowerBound]
        #expect(afterMenu.contains("}\n            }\n            "), "전환이 머리 trailing 안으로 들어갔다")
        #expect(section.contains("store.select(miniGameScope: $0)"))

        let todayStart = try #require(section.range(of: "private var today: some View"))
        let allTimeStart = try #require(section.range(of: "private var allTime: some View"))
        // [역대] 본문은 상금 줄 **정의** 앞에서 끊는다 — 정의까지 넣으면 "[역대] 가 상금 줄을 부른다"가 늘 참이 된다.
        let prizeFooterDefinition = try #require(section.range(of: "private func prizeFooter(players:"))
        #expect(todayStart.lowerBound < allTimeStart.lowerBound && allTimeStart.lowerBound < prizeFooterDefinition.lowerBound)
        let todayBody = section[todayStart.lowerBound..<allTimeStart.lowerBound]
        let allTimeBody = section[allTimeStart.lowerBound..<prizeFooterDefinition.lowerBound]
        for onlyToday in ["RankingsChampionRow(", "prizeFooter(players:", "knowsMiniGamePlayerCount"] {
            #expect(todayBody.contains(onlyToday), "[오늘] 에서 \(onlyToday) 가 사라졌다")
            #expect(!allTimeBody.contains(onlyToday), "[역대] 에 오늘 판의 것(\(onlyToday))이 섞였다")
        }
        #expect(todayBody.contains("RankingsText.miniGameEmptyText("), "[오늘] 빈 칸 문구가 바뀌었다")

        // 역대 줄은 같은 행 뷰 + 코어가 만든 날짜 글자, 내 줄 강조 유지.
        #expect(allTimeBody.contains("entry: entry.rankRowEntry") && allTimeBody.contains("dateCaption: entry.dayCaption"))
        #expect(allTimeBody.contains("entry.userID == store.myUserID"), "역대 줄에 내 줄 강조가 없다")
        #expect(code.components(separatedBy: "struct RankingsMiniGameRow").count - 1 == 1)
        #expect(section.components(separatedBy: "RankingsMiniGameRow(").count - 1 == 2)
        #expect(!section.contains("struct RankingsAllTime"), "역대 행 뷰가 두 벌이 됐다")
        // 빈 칸·규칙 글자는 게임 탭과 한 벌이다.
        #expect(allTimeBody.contains("store.miniGameAllTimeEmptyText") && allTimeBody.contains("store.miniGameAllTimeShowsRetry"))
        #expect(allTimeBody.contains("GamesMiniGameText.allTimeRuleCaption") && allTimeBody.contains("GamesMiniGameText.allTimeDayCaption"))
        // 보이스오버: 행이 자식을 숨기므로 날짜를 라벨에 넘겨야 한다.
        #expect(code.contains("isMe: isMe, dayCaption: dateCaption)"), "역대 줄 날짜가 보이스오버에 안 들린다")

        // 전환을 세우는 자리는 두 화면뿐이고 값은 각자 든다.
        let pickers = try IntegrationContractTests.files(containing: ["GamesBoardScopePicker("], under: "Sources/CheckMobileKit")
        #expect(pickers == ["Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift", "Sources/CheckMobileKit/Rankings/RankingsBoardSections.swift"],
                "전환이 흩어졌다: \(pickers)")
        // 스토어가 역대 줄을 빼서 쓰는 응답 가드(게임·순번·세대) 셋이 함께 있다.
        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/Rankings/RankingsStore.swift")
        #expect(store.contains("guard generation == context.generation, serial == miniGameAllTimeSerial, kind == miniGameKind else { return }"))
    }

    // MARK: - 데모 픽스처

    @Test("데모: [순위] 미니게임 · [게임] 장면마다 역대 픽스처가 닿고, 실제 스토어를 지나 줄이 선다 · 사람마다 오늘 최고 이상 · 날짜는 데모 시각 전")
    func demoFixtures() async throws {
        let fixtures = MobileDemoFixtures.load()
        func entry(_ key: String, scene: String, needle: String?) -> MobileDemoFixtures.Entry? {
            fixtures.entries.first { $0.key == key && $0.scenario == scene && $0.needle == needle }
        }
        let scenes: [(scene: String, needles: [String?])] = [
            ("rankings-minigame", [nil, "flappy"]),
            ("games", MiniGameKind.phoneCases.map(\.rawValue)),
            ("games-flappy", ["flappy"]),
            ("games-timing", ["timing_bar"]),
        ]
        for (scene, needles) in scenes {
            for needle in needles {
                let allTime = try #require(entry("rpc.minigame_alltime_board", scene: scene, needle: needle), "\(scene)@\(needle ?? "-") 역대 픽스처가 없다")
                let today = try #require(entry("rpc.minigame_board", scene: scene, needle: needle), "\(scene)@\(needle ?? "-") 오늘 픽스처가 없다")
                func rows(_ data: Data) throws -> [[String: Any]] {
                    try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
                }
                let todayBest = Dictionary(uniqueKeysWithValues: try rows(today.data).compactMap { row -> (String, Int)? in
                    guard let user = row["user_id"] as? String, let score = row["best_score"] as? Int else { return nil }
                    return (user, score)
                })
                for row in try rows(allTime.data) {
                    let user = try #require(row["user_id"] as? String)
                    let score = try #require(row["best_score"] as? Int)
                    let day = try #require(row["day"] as? String)
                    #expect(score >= (todayBest[user] ?? 0), "\(allTime.relativePath): 역대 최고가 오늘 최고보다 작다(\(user))")
                    #expect(MiniGameAllTimeEntry.dayCaption(day) != nil, "\(allTime.relativePath): 날짜 모양")
                    #expect(day <= "2026-09-17", "\(allTime.relativePath): 데모 시각보다 뒤의 기록")
                    #expect((row["best_at"] as? String)?.hasPrefix(day) == true, "\(allTime.relativePath): best_at 과 day 가 다른 날이다")
                }
            }
        }

        // 파일 모양이 실제 디코더·정렬을 지나 내 줄과 날짜까지 서는가.
        let file = try #require(entry("rpc.minigame_alltime_board", scene: "rankings-minigame", needle: nil))
        let body = String(decoding: file.data, as: UTF8.self)
        let harness = await RankMeHarness(label: "v1016-demo") { request in
            request.rpcName == "minigame_alltime_board" ? .json(body) : nil
        }
        defer { harness.tearDown() }
        await openAllTime(harness)
        let store = harness.rankings
        #expect(store.miniGameAllTime.count == 6)
        #expect(store.miniGameAllTime.allSatisfy { $0.dayCaption != nil })
        #expect(store.miniGameAllTime.map(\.bestScore) == store.miniGameAllTime.map(\.bestScore).sorted(by: >))
        #expect(store.miniGameAllTime.contains { $0.userID == MobileDemo.userID }, "데모 사용자 줄이 없어 내 줄 강조를 못 본다")
    }
}
