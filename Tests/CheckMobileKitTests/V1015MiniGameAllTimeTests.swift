@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

#if canImport(AppKit)
import AppKit
#endif

// 폰 1.0.15 — 미니게임 순위 **[오늘 | 역대] 전환**(맥 0.3.67 을 폰에 붙인다 · 설계서 ②)과 일일 미션 `rummy` 아이콘(③).
//
// 서버·코어는 그대로다(`minigame_alltime_board` 는 2026-10-27 06:48 KST 운영에 올라가 있고, 전선·디코드·정렬·날짜 글자는
// 코어 `MiniGameAllTimeEntry` 한 벌이다). 이 스위트가 재는 것은 **폰 허브의 판정**이다:
//  · 언제 받는가(안 보는 사람에게 호출이 가지 않는가)
//  · 겹친 받기에서 **누가 이기는가**(맥 검토 2026-10-27 · `bc9a64c` 6번이 고친 두 경합을 폰에서 다시 잰다)
//  · 빈 칸 네 상태가 **서로 다른 말**을 하는가(불러오는 중 ≠ 실패 ≠ 준비 중 ≠ 아직 없음)
//  · 글자가 맥과 같은가(소스 계약)
//
// 전환이 서는 자리는 **[게임] 탭 미니게임 화면 하나**다(사용자 결정 2026-10-30). [순위] 탭은 store·RPC·빈 칸 문구가
// 따로라 이번 판에서 안 넓혔고, 아래 소스 계약이 그 사실을 못 박는다.
//
// 뷰(`#if os(iOS)`)는 macOS 스위트가 한 줄도 컴파일하지 않는다 — `ios/scripts/build-sim.sh` 가 유일한 그물이다.
@MainActor
@Suite(.serialized) struct V1015MiniGameAllTimeTests {
    private static let boardJSON = #"[{"user_id":"u-games","display_name":"나","avatar_url":null,"best_score":40,"best_at":"2026-10-30T04:00:00Z","plays":3,"center":"seoul"}]"#

    /// 역대 응답 두 줄 — **일부러 거꾸로** 준다(점수 오름차순). 클라가 다시 세우지 않으면 1등 자리에 100점이 선다.
    /// `nonisolated` 인 이유: 스텁 응답기(`@Sendable`)는 메인 액터 밖에서 돈다(`GamesStoreScenarioTests.tokenJSON` 과 같은 자리).
    private nonisolated static func allTimeJSON(top: Int) -> String {
        #"[{"user_id":"p-1","display_name":"구름빵","avatar_url":null,"best_score":100,"best_at":"2026-09-13T04:00:00Z","day":"2026-09-13","center":null},"#
            + #"{"user_id":"u-games","display_name":"나","avatar_url":null,"best_score":\#(top),"best_at":"2026-10-02T01:00:00Z","day":"2026-10-02","center":"seoul"}]"#
    }

    /// 오늘 순위 · 어제 1등 · 공개 여부 · 토큰 · 제출을 세운다(`GamesStoreScenarioTests.configureMiniGame` 과 같은 한 벌).
    /// **역대는 일부러 안 세운다** — 세우는 시험이 자기 몫만 세운다(안 세우면 스텁 기본값이 404 = 준비 중이다).
    private func configure(_ harness: GamesHarness) {
        harness.server.setDefault("minigame_board", json: Self.boardJSON)
        harness.server.setDefault("minigame_yesterday_winner", json: "[]")
        harness.server.setDefault("/rest/v1/profiles", json: #"[{"minigame_public":true}]"#)
        harness.server.setDefault("minigame_submit_score", json: #"{"status":"ok","best_score":55,"plays":4,"improved":true}"#)
        gamesServeRoundTokens(harness, prefix: "tok")
    }

    /// 플래피 한 판을 끝까지(안 누르고 떨어져 0점) 민다.
    private func playFlappy(_ controller: GamesPlayController, from start: Date) {
        controller.tap()
        controller.tick(at: start)
        gamesDrive(controller, from: start, frames: 600) { $0.flappy.phase == .result }
    }

    /// 화면을 열고 **열기 꼬리까지** 끝난 뒤 돌려준다.
    ///
    /// ⚠️ `loaded` 만 기다리면 이르다. `openScreen` 의 Task 는 순위를 넣어 `loaded` 를 세운 **뒤에** 어제 1등을 await 하고,
    /// 그 다음에야 역대 갈래를 본다 — 거기서 바로 전환을 누르면 그 꼬리가 '나도 역대를 받자'로 깨어나 받기가 둘이 된다.
    /// 이 시험들은 **요청 수**를 세므로 그 한 건이 곧 빨강이다(실측: 일련번호가 3 까지 갔다). 어제 1등 요청이 나간 것을
    /// 보고 장벽을 한 번 지난 뒤 돌려준다(허브에도 짝 가드를 뒀다 — `openScreen` 의 `allTimeLoading` 주석).
    private func openFlappy(_ harness: GamesHarness) async {
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.hub.boards[.flappy]?.loaded == true }, "오늘 순위가 안 닿았다")
        #expect(await baseWaitUntil { harness.server.requests("minigame_yesterday_winner").count >= 1 },
                "어제 1등 조회가 안 나갔다(열기 꼬리가 아직 안 돌았다)")
        await harness.barrier()
    }

    // MARK: - 언제 받는가

    @Test("화면을 열 땐 역대를 안 받는다 · [역대] 를 고를 때 한 번 · 오가며 눌러도 그 한 번뿐 · 60초 요약도 안 받는다")
    func allTimeIsFetchedOnlyWhenChosen() async {
        let harness = GamesHarness(label: "v1015-when")
        configure(harness)
        harness.server.setDefault("minigame_alltime_board", json: Self.allTimeJSON(top: 500))
        await harness.signIn()
        await openFlappy(harness)
        await harness.barrier()
        #expect(harness.hub.boardScope == .today, "전환의 기본은 [오늘] 이다")
        #expect(harness.server.requests("minigame_alltime_board").isEmpty,
                "안 보는 사람에게 역대 호출이 나갔다(역대는 고를 때 처음 받는다)")

        harness.hub.selectBoardScope(.allTime)
        #expect(await baseWaitUntil { harness.hub.boards[.flappy]?.allTimeLoaded == true })
        #expect(harness.server.requests("minigame_alltime_board").count == 1)
        #expect(harness.hub.boards[.flappy]?.allTime.map(\.bestScore) == [500, 100],
                "서버 정렬을 믿었다 — 점수 내림차순으로 다시 세워야 한다")
        #expect(harness.hub.boards[.flappy]?.allTime.first?.dayCaption == "10/2", "행의 작은 날짜가 없다")
        #expect(harness.hub.best(for: .flappy) == 500, "내 역대 행이 로컬 최고를 올리지 않았다(다른 기기 · 재설치 복구)")

        // 같은 쪽을 다시 · [오늘] 로 갔다 와도 **최신 표를 들고 있으면 다시 받지 않는다.**
        harness.hub.selectBoardScope(.allTime)
        harness.hub.selectBoardScope(.today)
        harness.hub.selectBoardScope(.allTime)
        await harness.barrier()
        #expect(harness.server.requests("minigame_alltime_board").count == 1, "오가며 누를 때마다 요청이 나갔다")

        // 첫 화면 요약 루프(60초)는 역대에 손대지 않는다 — 안 보는 게임 셋까지 역대를 받으면 안 된다.
        harness.hub.refreshSummariesIfStale()
        await harness.barrier()
        #expect(harness.server.requests("minigame_alltime_board").count == 1, "요약 루프가 역대를 받았다")
        #expect(harness.violations.isEmpty, "폰 금지 호출: \(harness.violations)")
        await harness.tearDown()
    }

    @Test("표는 **게임마다** 따로 산다 — [역대] 를 보는 채로 다른 게임을 열면 그 게임 역대를 새로 받고 앞 게임 줄은 남는다")
    func eachGameKeepsItsOwnTable() async {
        let harness = GamesHarness(label: "v1015-perGame")
        configure(harness)
        harness.server.setDefault("minigame_alltime_board") { request in
            // 요청 본문의 `p_game` 하나로 가른다(서버 인자는 그것뿐이고 DEFAULT 가 없다 — 빼면 PGRST202).
            // 두 값 모두 응답의 다른 줄(100)보다 커야 1등 자리에 선다 — 작으면 이 시험이 정렬을 재는 것이 된다.
            .json(Self.allTimeJSON(top: request.bodyText.contains(#""p_game":"flappy""#) ? 500 : 300))
        }
        await harness.signIn()
        await openFlappy(harness)
        harness.hub.selectBoardScope(.allTime)
        #expect(await baseWaitUntil { harness.hub.boards[.flappy]?.allTime.first?.bestScore == 500 })

        harness.hub.closeScreen(.flappy)
        harness.hub.openScreen(.timingBar)
        #expect(await baseWaitUntil { harness.hub.boards[.timingBar]?.allTime.first?.bestScore == 300 },
                "[역대] 를 보던 채로 다른 게임을 열었는데 그 게임 역대를 안 받았다")
        #expect(harness.hub.boards[.flappy]?.allTime.first?.bestScore == 500, "앞 게임의 역대 줄이 사라졌다")
        let games = harness.server.requests("minigame_alltime_board").map(\.bodyText)
        #expect(games.count == 2 && games[0].contains(#""p_game":"flappy""#) && games[1].contains(#""p_game":"timing_bar""#),
                "역대 요청의 게임 키: \(games)")
        #expect(harness.violations.isEmpty, "폰 금지 호출: \(harness.violations)")
        await harness.tearDown()
    }

    @Test("판이 끝나면 **[역대] 를 보는 중일 때만** 다시 받는다")
    func theRoundTailRefetchesOnlyWhileViewingAllTime() async throws {
        let harness = GamesHarness(label: "v1015-tail")
        configure(harness)
        harness.server.setDefault("minigame_alltime_board", json: Self.allTimeJSON(top: 500))
        await harness.signIn()
        await openFlappy(harness)
        let controller = try #require(harness.hub.controller)
        #expect(await baseWaitUntil { harness.hub.roundToken != nil }, "선발급 토큰이 안 왔다")
        playFlappy(controller, from: harness.clock.now)
        #expect(await baseWaitUntil { harness.server.requests("minigame_submit_score").count == 1 })
        await harness.barrier()
        #expect(harness.server.requests("minigame_alltime_board").isEmpty, "[오늘] 을 보는데 판마다 역대를 받았다")

        harness.hub.selectBoardScope(.allTime)
        #expect(await baseWaitUntil { harness.server.requests("minigame_alltime_board").count == 1 })
        #expect(await baseWaitUntil { harness.hub.roundToken != nil }, "다음 판 토큰이 안 왔다")
        playFlappy(controller, from: harness.clock.now)
        #expect(await baseWaitUntil { harness.server.requests("minigame_submit_score").count == 2 })
        #expect(await baseWaitUntil { harness.server.requests("minigame_alltime_board").count == 2 },
                "[역대] 를 보는 중인데 판이 끝나도 표를 다시 받지 않았다")
        #expect(harness.violations.isEmpty, "폰 금지 호출: \(harness.violations)")
        await harness.tearDown()
    }

    // MARK: - 겹친 받기(맥 `bc9a64c` 6번을 폰에서 다시 잰다)

    @Test("늦게 온 옛 받기가 새 표를 덮지 않는다 — 전환 받기와 판 끝 재조회가 겹칠 때")
    func lateFetchDoesNotOverwriteTheNewerTable() async {
        let harness = GamesHarness(label: "v1015-race")
        configure(harness)
        // 스텁에 **먼저 닿는** 요청이 첫 응답을 먹는다. 붙잡힌 요청은 놓아준 뒤에야 닿으므로,
        // 첫 응답이 '새 표'(500 — 판이 끝나 다시 받은 것)이고 둘째가 '옛 표'(100 — 전환이 먼저 띄운 것)다.
        harness.server.enqueue("minigame_alltime_board") { _ in .json(Self.allTimeJSON(top: 500)) }
        harness.server.enqueue("minigame_alltime_board") { _ in .json(#"[]"#) }
        await harness.signIn()

        // ① 사람이 [역대] 를 보는 채로 화면을 연다 — 열기 꼬리가 역대 받기 **한 건**을 띄우고, 그걸 붙잡아 둔다.
        //    전환을 **화면 열기 전에** 세우는 것이 이 시험의 뼈대다: 화면이 없으면 전환 자체는 아무것도 안 받으므로
        //    (`selectBoardScope` 의 `activeKind` 가드) 떠 있는 받기가 정확히 하나라고 말할 수 있다.
        //    화면을 먼저 열고 누르면 전환과 열기 꼬리가 각자 띄워 셋이 겹친다(그 꼴은 아래 ② 가 못 잰다).
        let hold = BaseHold.rpc("minigame_alltime_board", host: harness.server.host)
        harness.hub.selectBoardScope(.allTime)
        #expect(harness.hub.boardScope == .allTime)
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.hub.boards[.flappy]?.loaded == true }, "오늘 순위가 안 닿았다")
        #expect(await hold.waitHeld(), "[역대] 를 보는데 화면을 여는 길에 역대를 안 받았다")

        // ② 그 사이 판이 끝나 역대를 다시 받았다(새 개인 최고가 든 표). 붙잡기는 한 건만 쥐므로 이 받기는 그냥 통과한다.
        await harness.hub.performLoadAllTimeBoard(.flappy)
        #expect(harness.hub.boards[.flappy]?.allTime.map(\.bestScore) == [500, 100], "뒤에 떠난 받기가 반영되지 않았다")

        // ③ 붙잡아 둔 옛 받기가 이제 닿는다 — **새 표를 덮으면 안 된다.**
        #expect(await hold.releaseAndWaitDelivered())
        await harness.barrier()
        #expect(harness.hub.boards[.flappy]?.allTime.map(\.bestScore) == [500, 100],
                "늦게 온 옛 받기가 새 표를 덮었다(일련번호 가드가 없다)")
        #expect(harness.hub.allTimeAppliedSerial == 2, "반영 번호: \(harness.hub.allTimeAppliedSerial)")
        #expect(harness.violations.isEmpty, "폰 금지 호출: \(harness.violations)")
        await harness.tearDown()
    }

    @Test("[오늘] 로 되돌아간 사이 판이 기록되면, 떠 있던 받기를 '최신'으로 표시하지 않는다 — 다음 전환이 다시 받는다")
    func aFetchCrossingASubmitIsNotMarkedFresh() async throws {
        let harness = GamesHarness(label: "v1015-stale")
        configure(harness)
        harness.server.setDefault("minigame_alltime_board", json: Self.allTimeJSON(top: 500))
        await harness.signIn()
        await openFlappy(harness)
        let controller = try #require(harness.hub.controller)
        #expect(await baseWaitUntil { harness.hub.roundToken != nil }, "선발급 토큰이 안 왔다")

        // ① [역대] 를 눌러 받기를 띄우고 붙잡는다.
        let hold = BaseHold.rpc("minigame_alltime_board", host: harness.server.host)
        harness.hub.selectBoardScope(.allTime)
        #expect(await hold.waitHeld())
        // ② 사람이 [오늘] 로 되돌아갔다 — 이제 판이 끝나도 역대 재조회가 안 나간다.
        harness.hub.selectBoardScope(.today)
        // ③ 판 하나가 서버에 남았다 — 그 게임의 역대 표는 이 순간 낡았다.
        playFlappy(controller, from: harness.clock.now)
        #expect(await baseWaitUntil { harness.server.requests("minigame_submit_score").count == 1 })
        await harness.barrier()
        // ⚠️ 붙잡힌 받기는 **아직 스텁에 닿지 않았다** — 붙잡기가 스텁 **앞**에 서기 때문이다(`BaseHoldURLProtocol`).
        //    그래서 스텁 기록은 0 이고, 그 0 이 곧 "판 끝 재조회가 **더** 나가지 않았다"다: 붙잡기는 한 건만 쥐므로
        //    둘째 받기가 떠났다면 그건 통과해 기록에 남는다(실측으로 이 자리를 1 로 적어 뒀다가 틀렸다).
        #expect(hold.held == 1, "전환이 띄운 받기가 붙잡히지 않았다 — 아래 순서가 뜻을 잃는다")
        #expect(harness.server.requests("minigame_alltime_board").isEmpty, "[오늘] 인데 판 끝 재조회가 나갔다")

        // ④ 붙잡힌 받기가 **제출 뒤에** 닿는다. 표는 반영해도 좋지만 '최신'으로 표시하면 안 된다 —
        //    그 표에는 방금 기록한 점수가 빠져 있다.
        #expect(await hold.releaseAndWaitDelivered())
        await harness.barrier()
        #expect(harness.hub.boards[.flappy]?.allTimeLoaded == true, "반영 자체는 해야 한다(빈 표로 두면 '불러오는 중'에 굳는다)")
        #expect(harness.hub.allTimeFreshKind == nil, "제출 전에 떠난 받기가 '최신'을 다시 세웠다")

        harness.hub.selectBoardScope(.allTime)
        #expect(await baseWaitUntil { harness.server.requests("minigame_alltime_board").count == 2 },
                "새 개인 최고가 빠진 표를 최신으로 믿고 다시 받지 않았다")
        #expect(harness.violations.isEmpty, "폰 금지 호출: \(harness.violations)")
        await harness.tearDown()
    }

    @Test("로그아웃은 역대 표·신선도를 비운다 — 다음 계정이 앞사람 표를 물려받지 않는다(보기 선택은 남는다)")
    func signOutClearsTheTableButKeepsTheViewChoice() async {
        let harness = GamesHarness(label: "v1015-reset")
        configure(harness)
        harness.server.setDefault("minigame_alltime_board", json: Self.allTimeJSON(top: 500))
        await harness.signIn()
        await openFlappy(harness)
        harness.hub.selectBoardScope(.allTime)
        #expect(await baseWaitUntil { harness.hub.allTimeFreshKind == .flappy })

        harness.hub.reset()
        #expect(harness.hub.boards.isEmpty, "남의 역대 행이 남았다")
        #expect(harness.hub.allTimeFreshKind == nil, "신선도 표식이 계정 전환을 넘어 살았다")
        // 보기 선택은 **계정이 아니라 이 앱 실행의 것**이다(맥과 같은 선택).
        #expect(harness.hub.boardScope == .allTime, "로그아웃이 보기 선택을 되돌렸다")
        await harness.tearDown()
    }

    // MARK: - 빈 칸 네 상태

    @Test("빈 칸 문구 넷이 서로 다르다: 불러오는 중 ≠ 실패(+[다시 시도]) ≠ 준비 중(버튼 없음) ≠ 아직 없음")
    func theFourEmptyStatesSpeakDifferently() {
        let loading = GamesMiniGameBoard()
        #expect(loading.allTimeEmptyText == GamesMiniGameText.loadingCaption && !loading.allTimeShowsRetry)

        var failed = GamesMiniGameBoard()
        failed.allTimeFailed = true
        #expect(failed.allTimeEmptyText == GamesMiniGameText.allTimeFailedCaption)
        #expect(failed.allTimeShowsRetry, "한 번도 못 받은 실패에 [다시 시도] 가 없다")

        var unavailable = GamesMiniGameBoard()
        unavailable.allTimeLoaded = true
        unavailable.allTimeUnavailable = true
        #expect(unavailable.allTimeEmptyText == GamesMiniGameText.allTimeUnavailableCaption)
        #expect(!unavailable.allTimeShowsRetry, "'준비 중' 옆에 [다시 시도] 가 붙으면 같은 404 를 영원히 두드린다")

        var empty = GamesMiniGameBoard()
        empty.allTimeLoaded = true
        #expect(empty.allTimeEmptyText == GamesMiniGameText.emptyBoard && !empty.allTimeShowsRetry)

        // 줄을 들고 있으면 실패를 **조용히** 둔다(지난 표를 지우지 않는다 — 공용 규칙 `MobileLoadKnowledge` 와 같은 결).
        var hasRows = GamesMiniGameBoard()
        hasRows.allTime = [MiniGameAllTimeEntry(userID: "p-1", name: "구름빵", avatarURL: nil, bestScore: 100,
                                                bestAt: nil, day: "2026-09-13")]
        hasRows.allTimeLoaded = true
        hasRows.allTimeFailed = true
        #expect(!hasRows.allTimeShowsRetry, "이미 그린 표 위에 실패 행이 섰다")

        // 넷이 **같은 말을 하지 않는다** — 같은 문장이면 사용자가 상황을 못 가른다.
        let texts = [loading.allTimeEmptyText, failed.allTimeEmptyText, unavailable.allTimeEmptyText, empty.allTimeEmptyText]
        #expect(Set(texts).count == 4, "빈 칸 문구: \(texts)")
        // 로드 전에 실패가 섰으면 그건 실패다(준비 중이 먼저 걸리면 네트워크 실패까지 "곧 열려요"로 덮인다).
        #expect(GamesMiniGameText.allTimeEmpty(failed: true, loaded: false, unavailable: true)
                == GamesMiniGameText.allTimeFailedCaption)
    }

    @Test("함수가 없는 서버는 **준비 중**이다(실패가 아니다) · 네트워크 실패는 실패다 · 404 를 오가며 다시 두드리지 않는다")
    func missingFunctionFoldsToComingSoon() async {
        let harness = GamesHarness(label: "v1015-missing")
        configure(harness)
        // 역대 기본값을 안 세웠다 — 스텁이 404 + PGRST202 로 답한다(마이그레이션 전 창과 같은 모양).
        await harness.signIn()
        await openFlappy(harness)
        harness.hub.selectBoardScope(.allTime)
        #expect(await baseWaitUntil { harness.hub.boards[.flappy]?.allTimeUnavailable == true })
        let board = harness.hub.boards[.flappy]
        #expect(board?.allTimeFailed == false, "준비 중을 실패로 그렸다")
        #expect(board?.allTimeLoaded == true && board?.allTime.isEmpty == true)
        #expect(board?.allTimeEmptyText == GamesMiniGameText.allTimeUnavailableCaption)

        harness.hub.selectBoardScope(.today)
        harness.hub.selectBoardScope(.allTime)
        await harness.barrier()
        #expect(harness.server.requests("minigame_alltime_board").count == 1, "오가며 누를 때마다 404 를 다시 두드렸다")

        // 네트워크 실패는 **실패**다(사용자가 고칠 수 있는 일이라 [다시 시도] 가 붙는다).
        let other = GamesHarness(label: "v1015-netfail")
        configure(other)
        other.server.setDefault("minigame_alltime_board") { _ in .networkFailure() }
        await other.signIn()
        await openFlappy(other)
        other.hub.selectBoardScope(.allTime)
        #expect(await baseWaitUntil { other.hub.boards[.flappy]?.allTimeFailed == true })
        #expect(other.hub.boards[.flappy]?.allTimeUnavailable == false, "네트워크 실패를 '준비 중'으로 접었다")
        #expect(other.hub.boards[.flappy]?.allTimeShowsRetry == true)
        // 실패한 채였으면 [역대] 로 다시 넘어올 때 한 번 더 받는다 — 다시 보러 온 것이 곧 재시도 의사다.
        other.hub.selectBoardScope(.today)
        other.hub.selectBoardScope(.allTime)
        #expect(await baseWaitUntil { other.server.requests("minigame_alltime_board").count == 2 },
                "실패한 표를 다시 보러 왔는데 재시도가 안 나갔다")
        await other.tearDown()
        await harness.tearDown()
    }

    // MARK: - 글자(맥과 한 벌) · 자리

    @Test("문구는 맥 네 줄 그대로 · 제목은 코어 한 벌 · 전환은 [게임] 탭 미니게임 화면 하나에만 선다")
    func copyAndPlacementMatchTheMac() throws {
        let mac = try MeTextParityTests.macCode()
        for sentence in [GamesMiniGameText.allTimeRuleCaption, GamesMiniGameText.allTimeDayCaption,
                         GamesMiniGameText.allTimeFailedCaption, GamesMiniGameText.allTimeUnavailableCaption] {
            #expect(mac.contains(sentence), "맥 코드에 없는 문장(한쪽만 바뀌었다): \(sentence)")
        }
        // 머리 제목은 코어 열거값 한 벌이다 — 폰이 "역대 순위"를 따로 적으면 맥과 갈린다.
        #expect(GamesMiniGameText.allTimeRankTitle == MiniGameBoardScope.allTime.boardTitle)
        #expect(MiniGameBoardScope.allTime.boardTitle == "역대 순위" && MiniGameBoardScope.allTime.label == "역대")

        // [순위] 탭(다른 store · 다른 화면)은 이번 판에서 **안 넓혔다**(사용자 결정 2026-10-30).
        #expect(RankingsText.miniGameRankTitle == MiniGameBoardScope.today.boardTitle)
        let rankingsSection = try IntegrationContractTests.code("Sources/CheckMobileKit/Rankings/RankingsBoardSections.swift")
        #expect(!rankingsSection.contains("MiniGameBoardScope"), "[순위] 탭에 전환이 섞여 들어갔다")

        // 전환 부품을 세우는 자리는 한 곳이다(둘이 되면 두 화면이 서로 다른 판을 보여 준다).
        let pickers = try IntegrationContractTests.files(containing: ["GamesBoardScopePicker("], under: "Sources/CheckMobileKit")
        #expect(pickers == ["Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift"], "전환이 흩어졌다: \(pickers)")
        // 화면은 빈 칸 판정을 **허브에서** 읽는다(뷰 안 삼항은 macOS 스위트가 못 잰다).
        let screen = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift")
        #expect(screen.contains("state.allTimeEmptyText") && screen.contains("state.allTimeShowsRetry"))
        // 역대 줄도 **같은 행 뷰**를 쓴다(코어가 만든 `rankRowEntry` — 행 뷰가 두 벌이면 열 규격이 갈린다).
        #expect(screen.contains("entry.rankRowEntry") && screen.contains("dateCaption: entry.dayCaption"))
        // 게이트(폰 목록)는 이 판에서 안 건드린다 — 길건너를 넣는 것은 다른 레인이다.
        #expect(MiniGameKind.phoneCases.allSatisfy { $0.isPhoneSupported })
    }

    // MARK: - ③ 일일 미션 `rummy` 아이콘

    @Test("일일 미션 rummy 아이콘: 별이 아니고 · 겹치지 말아야 할 일곱과 다르고 · 실재하는 이름이다")
    func rummyMissionIcon() {
        let rummy = MeText.dailyMissionIcon(game: "rummy")
        // 맥 `DailyMissionCopy.icon(game: "rummy")` 과 **같은 기호**다(게임 이름이 아잉 큐브 — 두 기기가 한 그림).
        #expect(rummy == "cube.fill")
        #expect(rummy != MeText.missionFallbackIcon, "기본 별로 떨어졌다")
        // 겹치지 말아야 할 일곱: `MiniGameKind(rawValue:)` 가 먼저 걸러 코어 아이콘으로 가는 미니게임 넷 + 1:1 셋.
        let others = MiniGameKind.allCases.map(\.icon) + ["gomoku", "chess", "tetris_duel"].map { MeText.dailyMissionIcon(game: $0) }
        #expect(others.count == 7 && Set(others).count == 7, "전제가 깨졌다(일곱이 서로 달라야 한다): \(others)")
        #expect(!others.contains(rummy), "일곱 중 하나와 같은 실루엣이다: \(others)")
        // 내부 식별자는 `rummy` **하나**다 — '아잉 큐브'는 화면 이름이고 `aing_cube` 는 코드에 없다.
        #expect(MeText.dailyMissionIcon(game: "aing_cube") == MeText.missionFallbackIcon)
        #expect(MeText.dailyMissionIcon(game: "rummy1") == MeText.missionFallbackIcon, "표는 1:1 완전 일치다")
        #if canImport(AppKit)
        // 없는 이름은 런타임에 **경고 없이 빈 칸**이 된다(두부도 안 뜬다). 여덟 줄 전부를 되묻는다.
        for symbol in Set(others + [rummy, MeText.missionFallbackIcon]) {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "없는 SF Symbol: \(symbol)")
        }
        #endif
    }
}
