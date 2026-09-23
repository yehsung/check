@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 게임 탭 스토어 시나리오(스텁 서버 · 조작 시계). 시나리오마다 끝에서 **폰 금지 호출 0건**을 단언한다.
@MainActor
@Suite(.serialized) struct GamesStoreScenarioTests {
    private static let boardJSON = #"[{"user_id":"u-games","display_name":"나","avatar_url":null,"best_score":40,"best_at":"2026-09-17T04:00:00Z","plays":3,"center":"seoul"},{"user_id":"p-1","display_name":"구름빵","avatar_url":null,"best_score":80,"best_at":"2026-09-17T03:00:00Z","plays":5,"center":null}]"#

    private nonisolated static func tokenJSON(_ token: String) -> String {
        #"{"status":"ok","token":"\#(token)","expires_at":"2026-09-17T05:35:00Z","server_now":"2026-09-17T05:05:00Z"}"#
    }

    private func configureMiniGame(_ harness: GamesHarness, isPublic: Bool = true) {
        harness.server.setDefault("minigame_board", json: Self.boardJSON)
        harness.server.setDefault("minigame_yesterday_winner", json: "[]")
        harness.server.setDefault("/rest/v1/profiles", json: #"[{"minigame_public":\#(isPublic)}]"#)
        harness.server.setDefault("minigame_submit_score", json: #"{"status":"ok","best_score":55,"plays":4,"improved":true}"#)
    }

    /// 플래피 한 판을 끝까지(안 누르고 떨어져 0점) 민다.
    private func playFlappyToResult(_ controller: GamesPlayController, from start: Date) {
        controller.tap()
        controller.tick(at: start)
        gamesDrive(controller, from: start, frames: 600) { $0.flappy.phase == .result }
    }

    // MARK: - 미니게임

    @Test("화면을 열면 공개 여부 → 토큰 선발급 → 순위·어제 1등 · 판이 끝나면 그 토큰으로 한 번 제출 → 순위 재조회 → 다음 토큰 · 금지 호출 0")
    func miniGameHappyPath() async throws {
        let harness = GamesHarness(label: "games-happy")
        configureMiniGame(harness)
        harness.server.enqueue("minigame_start_round") { _ in .json(Self.tokenJSON("tok-1")) }
        harness.server.enqueue("minigame_start_round") { _ in .json(Self.tokenJSON("tok-2")) }
        await harness.signIn()
        #expect(harness.model.session.isSignedIn)

        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-1" })
        #expect(await baseWaitUntil { harness.hub.boards[.flappy]?.loaded == true })
        #expect(harness.hub.myRank(.flappy) == 2)
        #expect(harness.hub.best(for: .flappy) == 40, "순위표의 내 행이 로컬 최고를 올린다")
        // ⚠️ `loaded` 는 어제 1등 왕복보다 **먼저** 선다(`loadBoard` 가 순위를 넣고 `loaded = true` 를 세운 **뒤에**
        //    어제 1등을 await 한다). 그래서 위 대기가 깨는 순간 이 요청은 아직 안 나갔을 수 있다 —
        //    바로 `== 1` 을 재면 포화에서 드물게 빨개진다(실측 1회). 나간 것을 기다린 뒤에 **개수**를 잰다.
        #expect(await baseWaitUntil { harness.server.requests("minigame_yesterday_winner").count >= 1 },
                "어제 1등 조회가 안 나갔다")
        #expect(harness.server.requests("minigame_yesterday_winner").count == 1, "어제 1등을 두 번 읽었다")

        let controller = try #require(harness.hub.controller)
        playFlappyToResult(controller, from: harness.clock.now)
        #expect(controller.flappy.phase == .result)
        #expect(await baseWaitUntil { harness.server.requests("minigame_submit_score").count == 1 })
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-2" }, "제출 뒤 다음 토큰을 미리 받는다")
        #expect(await baseWaitUntil { harness.server.requests("minigame_board").count >= 2 }, "제출 성공 뒤 순위를 다시 읽는다")

        let submit = try #require(harness.server.requests("minigame_submit_score").first, "제출이 없다 — 인덱스 읽기 전에 멈춘다")
        #expect(submit.bodyText.contains(#""p_token":"tok-1""#))
        #expect(submit.bodyText.contains(#""p_score":0"#))
        #expect(submit.bodyText.contains(#""p_game":"flappy""#))
        let keys = harness.server.requests.map(GamesStubServer.key)
        let publicIndex = keys.firstIndex(of: "/rest/v1/profiles") ?? .max
        let startIndex = keys.firstIndex(of: "minigame_start_round") ?? .max
        let submitIndex = keys.firstIndex(of: "minigame_submit_score") ?? .max
        #expect(publicIndex < startIndex && startIndex < submitIndex, "순서: 공개 여부 → 토큰 → 제출 · \(keys)")
        #expect(harness.hub.best(for: .flappy) == 55, "서버가 확정한 최고를 로컬에 올린다")
        #expect(harness.hub.submitNotice == nil)
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("순위 공개를 끈 사람: 토큰을 받지 않고 제출도 없다 — 로컬 최고만 오른다")
    func privatePlayerNeverUploads() async throws {
        let harness = GamesHarness(label: "games-private")
        configureMiniGame(harness, isPublic: false)
        harness.server.setDefault("minigame_start_round", json: Self.tokenJSON("tok-x"))
        await harness.signIn()
        harness.hub.openScreen(.timingBar)
        #expect(await baseWaitUntil { !harness.hub.isPublic })
        #expect(await baseWaitUntil { harness.hub.boards[.timingBar]?.loaded == true })
        let controller = try #require(harness.hub.controller)
        controller.replaceForTesting(timing: TimingBarGame(seed: 5))
        // 한 판을 완주(매 라운드 뜨자마자 탭).
        controller.tap()
        var now = harness.clock.now
        controller.tick(at: now)
        for _ in 0..<(60 * 20) {
            now = now.addingTimeInterval(1.0 / 60.0)
            controller.tick(at: now)
            if case .running = controller.timing.phase { controller.tap() }
            if case .finished = controller.timing.phase { break }
        }
        guard case .finished(let total) = controller.timing.phase else {
            Issue.record("판이 안 끝났다")
            await harness.tearDown()
            return
        }
        await harness.barrier()
        #expect(harness.server.requests("minigame_start_round").isEmpty, "공개를 끈 사람에게 토큰을 받았다")
        #expect(harness.server.requests("minigame_submit_score").isEmpty, "공개를 끈 사람의 점수를 올렸다")
        #expect(harness.hub.best(for: .timingBar) == max(40, total))
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    @Test("판 도중 앱이 background 로 가면 판은 끝나고 제출하지 않는다 — 안내 한 줄")
    func backgroundEndsRoundWithoutSubmitting() async throws {
        let harness = GamesHarness(label: "games-background")
        configureMiniGame(harness)
        harness.server.setDefault("minigame_start_round", json: Self.tokenJSON("tok-bg"))
        await harness.signIn()
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-bg" })
        let controller = try #require(harness.hub.controller)
        controller.tap()
        controller.tick(at: harness.clock.now)
        gamesDrive(controller, from: harness.clock.now, frames: 12)
        #expect(controller.isPlaying)

        harness.model.sceneDidEnterBackground()
        #expect(!controller.isPlaying)
        #expect(harness.hub.submitNotice == GamesMiniGameText.endedInBackground(.flappy))
        gamesDrive(controller, from: harness.clock.now.addingTimeInterval(2), frames: 300)
        await harness.barrier()
        #expect(harness.server.requests("minigame_submit_score").isEmpty, "background 로 끝난 판을 제출했다")
        #expect(harness.hub.roundToken == "tok-bg", "쓰지 않은 토큰은 다음 판에 쓴다")
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    @Test("토큰을 못 받았으면(오프라인) 제출하지 않고 말한다 · 판이 끝난 자리에서 다시 받고, 연결이 돌아오면 다음 판은 올라간다")
    func missingTokenSaysSoAndRefetches() async throws {
        let harness = GamesHarness(label: "games-offline")
        configureMiniGame(harness)
        let online = BaseLockedBox(false)
        harness.server.setDefault("minigame_start_round") { _ in
            online.get() ? .json(Self.tokenJSON("tok-later")) : .networkFailure()
        }
        await harness.signIn()
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.server.requests("minigame_start_round").count == 1 && harness.hub.roundTokenInFlightKind == nil })
        #expect(harness.hub.roundToken == nil)

        // 판 시작(쓸 토큰이 없어 한 번 더 받는다 — 역시 실패) → 판 끝(토큰 없음: 제출하지 않고 말하고, 다시 받는다 — 실패).
        let controller = try #require(harness.hub.controller)
        playFlappyToResult(controller, from: harness.clock.now)
        #expect(harness.hub.submitNotice == GamesMiniGameText.submitFailedConnection)
        #expect(await baseWaitUntil { harness.server.requests("minigame_start_round").count >= 3 && harness.hub.roundTokenInFlightKind == nil },
                "판이 끝난 자리에서 토큰을 다시 받지 않았다")
        #expect(harness.server.requests("minigame_submit_score").isEmpty, "토큰 없이 제출했다")

        // 연결이 돌아왔다: 다음 판은 시작할 때 토큰을 받고, 끝나면 그 토큰으로 올라간다.
        online.mutate { $0 = true }
        playFlappyToResult(controller, from: harness.clock.now.addingTimeInterval(30))
        #expect(await baseWaitUntil { harness.server.requests("minigame_submit_score").count == 1 || harness.hub.roundToken == "tok-later" })
        if harness.server.requests("minigame_submit_score").isEmpty {
            // 시작 요청이 판(동기 구동)보다 늦게 끝났다 — 다음 판에서 쓴다.
            playFlappyToResult(controller, from: harness.clock.now.addingTimeInterval(60))
            #expect(await baseWaitUntil { harness.server.requests("minigame_submit_score").count == 1 })
        }
        #expect(harness.server.requests("minigame_submit_score").first?.bodyText.contains("tok-later") == true)
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    @Test("늦게 온 옛 토큰 응답은 새 토큰을 덮지 않는다(세대 가드) · 왕복 중 판이 시작돼도 또 요청하지 않는다")
    func lateTokenResponseIsDropped() async {
        let harness = GamesHarness(label: "games-late")
        configureMiniGame(harness)
        harness.server.setDefault("minigame_start_round") { request in
            request.bodyText.contains("timing_bar") ? .json(Self.tokenJSON("tok-old")) : .json(Self.tokenJSON("tok-new"))
        }
        await harness.signIn()
        let timingToken = BaseHold.install(host: harness.server.host) { $0.rpcName == "minigame_start_round" && $0.bodyText.contains("timing_bar") }
        harness.hub.openScreen(.timingBar)
        #expect(await baseWaitUntil { harness.hub.roundTokenInFlightKind == .timingBar })
        #expect(await timingToken.waitHeld())
        // 왕복 중에 판이 시작됐다 — 같은 게임 토큰을 또 요청하지 않는다(붙잡힌 것 말고 스텁에 닿은 요청이 없어야 한다).
        harness.hub.controller?.tap()
        await harness.barrier()
        #expect(harness.server.requests("minigame_start_round").isEmpty, "선발급이 도는 중에 또 요청했다")

        // 다른 게임으로 옮겨 새 요청이 나간다 → 옛(타이밍 바) 응답은 그 뒤에 놓는다.
        harness.hub.closeScreen(.timingBar)
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-new" })
        #expect(await timingToken.releaseAndWaitDelivered())
        await harness.barrier()
        #expect(harness.hub.roundToken == "tok-new", "늦게 온 옛 토큰이 새 토큰을 덮었다")
        #expect(harness.hub.roundTokenKind == .flappy)
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    @Test("쓸 만한 토큰은 다시 받지 않는다(서버 started_at 을 되돌리지 않게) · 20분이 지나면 새로 받는다")
    func usableTokenIsReusedUntilStale() async {
        let harness = GamesHarness(label: "games-reuse")
        configureMiniGame(harness)
        harness.server.enqueue("minigame_start_round") { _ in .json(Self.tokenJSON("tok-a")) }
        harness.server.enqueue("minigame_start_round") { _ in .json(Self.tokenJSON("tok-b")) }
        await harness.signIn()
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-a" })
        harness.hub.closeScreen(.flappy)
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.server.requests("/rest/v1/profiles").count == 2 })
        await harness.barrier()
        #expect(harness.server.requests("minigame_start_round").count == 1, "쓸 만한 토큰이 있는데 또 받았다")

        harness.clock.advance(GamesMiniGameHub.tokenRefreshSeconds + 60)
        harness.hub.closeScreen(.flappy)
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-b" }, "20분 지난 토큰을 새로 받지 않았다")
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    @Test("첫 화면 카드: 폰에 보이는 게임 전부의 오늘 순위를 읽고 60초 안에는 다시 안 읽는다 · 로그아웃하면 전부 비운다")
    func hubSummariesThrottleAndReset() async {
        // 조회 건수를 **숫자로 박지 않는다** — `MiniGameKind.phoneCases` 에서 끌어온다. 예전엔 2·4 를 박아 뒀는데,
        // 게임이 셋이 된 2026-09-23 노출 플립에서 그대로 빨개졌다. 박아 두면 새 게임마다 이 테스트가 '틀린 게
        // 아니라 낡아서' 빨개지고, 그때 사람이 숫자만 올리며 **무엇을 재던 테스트인지 잊는다.**
        let games = MiniGameKind.phoneCases.count
        let harness = GamesHarness(label: "games-hub")
        configureMiniGame(harness)
        await harness.signIn()
        harness.games.hubDidAppear()
        #expect(await baseWaitUntil {
            MiniGameKind.phoneCases.allSatisfy { harness.hub.boards[$0]?.loaded == true }
        }, "폰에 보이는 게임 중 오늘 순위를 안 읽은 것이 있다")
        #expect(harness.hub.myRank(.timingBar) == 2 && harness.hub.myTodayBest(.flappy) == 40)
        harness.games.hubDidAppear()
        await harness.barrier()
        #expect(harness.server.requests("minigame_board").count == games, "60초 안인데 다시 읽었다")
        harness.clock.advance(61)
        harness.games.hubDidAppear()
        #expect(await baseWaitUntil { harness.server.requests("minigame_board").count == games * 2 })

        await harness.model.session.signOut()
        #expect(harness.hub.boards.isEmpty)
        #expect(harness.hub.controller == nil)
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    // MARK: - 오목

    @Test("오목 수명: active → 인박스(탭 배지) · 화면 표시 → 로비·인박스·폴링 · background → 폴링 멈춤 · active → 다시 보이고 따라잡기 · 금지 호출 0")
    func gomokuLifecycle() async {
        let harness = GamesHarness(label: "games-gomoku")
        let nowMs = harness.serverNowMs
        harness.server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs, incoming: [("i-1", "구름빵", 5), ("i-2", "초코칩", 3)]))
        harness.server.setDefault("gomoku_lobby", json: GamesGomokuJSON.lobby(nowMs: nowMs))
        await harness.signIn()

        #expect(await baseWaitUntil { harness.games.badgeCount == 2 }, "active 가 되면 받은 신청으로 탭 배지를 채운다")
        #expect(harness.model.badges.games == 2)
        #expect(harness.model.badges.badge(for: .games) == 2)

        harness.games.gomokuScreenDidAppear()
        #expect(harness.gomoku.isWindowVisible)
        #expect(harness.gomoku.pollTask != nil, "오목 화면이 보이면 안전망 폴링이 돈다")
        #expect(await baseWaitUntil { harness.gomoku.hasLoadedLobby && harness.gomoku.users.count == 2 })

        harness.model.sceneDidEnterBackground()
        #expect(harness.gomoku.pollTask == nil, "background 인데 폴링이 돈다")
        #expect(harness.gomoku.isWindowOccluded, "background 는 가림이다(창을 닫은 것이 아니다)")
        #expect(harness.games.isGomokuScreenVisible, "화면은 그대로 떠 있다(돌아오면 다시 보인다)")
        // 폴링은 제품 벽시계 잠(pollStepSeconds)으로 돈다 — 한 걸음(0.5초)보다 넉넉한 재개 횟수 창을 준다(부하만큼 창도 늘어난다).
        await baseYield(turns: 220)
        await harness.barrier()
        #expect(harness.gomoku.pollTask == nil, "background 에서 폴링이 되살아났다")

        let inboxBefore = harness.server.requests("gomoku_inbox").count
        harness.model.sceneDidBecomeActive()
        #expect(harness.gomoku.isWindowVisible && !harness.gomoku.isWindowOccluded)
        #expect(harness.gomoku.pollTask != nil)
        #expect(await baseWaitUntil { harness.server.requests("gomoku_inbox").count > inboxBefore }, "돌아오면 따라잡기(인박스)")

        harness.games.gomokuScreenDidDisappear()
        #expect(!harness.gomoku.isWindowVisible)
        #expect(harness.gomoku.pollTask == nil)
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("미니게임 판이 도는 동안 화면 꺼짐 방지 · 판이 끝나거나 background 면 푼다(오목이 없어도)")
    func miniGameRoundHoldsIdleTimer() async throws {
        let harness = GamesHarness(label: "games-idle-mini")
        await harness.signIn()
        #expect(!harness.games.wantsIdleTimerDisabled, "판도 대국도 없는데 화면을 붙잡고 있다")

        // 플래피로 잰다(타이밍 바는 스스로 안 끝나 일부러 제외했다 — 아래 테스트가 그걸 지킨다).\n        // 화면만 열어서는 안 켠다 — 아직 판이 안 돌았다(ready).
        harness.games.miniGames.openScreen(.flappy)
        #expect(harness.games.miniGames.controller?.isPlaying == false)
        #expect(!harness.games.wantsIdleTimerDisabled, "판이 시작되기 전인데 화면을 붙잡았다")

        // 탭 한 번 = 판 시작. 오목은 하나도 없다 — 미니게임 가지만으로 켜져야 한다.
        harness.games.miniGames.controller?.tap()
        #expect(harness.games.miniGames.controller?.isPlaying == true)
        #expect(harness.gomoku.match == nil, "이 단언이 오목 가지로 통과하면 안 된다")
        #expect(harness.games.wantsIdleTimerDisabled, "미니게임 판이 도는데 자동잠금을 안 막는다 — 폰은 background 가 곧 판 폐기다")

        // background: 판을 폐기하므로 붙잡을 이유가 사라진다(두 경로 모두 false 여야 한다).
        harness.model.sceneDidEnterBackground()
        #expect(!harness.games.wantsIdleTimerDisabled, "background 에서 화면 꺼짐 방지를 쥐고 있다")
        harness.model.sceneDidBecomeActive()
        #expect(harness.games.miniGames.controller?.isPlaying != true, "background 가 판을 폐기하지 않았다")
        #expect(!harness.games.wantsIdleTimerDisabled, "폐기된 판으로 화면을 붙잡고 있다")

        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("타이밍 바는 화면 꺼짐 방지에서 뺀다 — 그 판은 스스로 끝나지 않아 자동잠금이 유일한 상한이다")
    func timingBarIsExcludedFromIdleTimerHold() async throws {
        let harness = GamesHarness(label: "games-idle-timing")
        await harness.signIn()
        harness.games.miniGames.openScreen(.timingBar)
        harness.games.miniGames.controller?.tap()
        #expect(harness.games.miniGames.controller?.isPlaying == true, "타이밍 바 판이 안 시작됐다")
        #expect(!harness.games.wantsIdleTimerDisabled,
                "타이밍 바가 화면을 붙잡았다 — 탭을 안 하면 판이 안 끝나므로 켜 둔 채 자리를 뜨면 화면이 영원히 켜진다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("판이 막 시작되면(오목 화면 밖) 게임 탭 오목 대국으로 연다 · 대국 중에만 화면 꺼짐 방지 · 끝나면·background 면 푼다")
    func matchStartOpensScreenAndHoldsIdleTimer() async throws {
        let harness = GamesHarness(label: "games-match")
        let nowMs = harness.serverNowMs
        let matchID = "m-live-1"
        harness.server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs))
        harness.server.setDefault("gomoku_lobby", json: GamesGomokuJSON.lobby(nowMs: nowMs))
        harness.server.setDefault("gomoku_leave", json: #"{"status":"ok","both_left":false}"#)
        await harness.signIn()
        harness.model.router.selectedTab = .messages
        #expect(!harness.games.wantsIdleTimerDisabled)

        let active = try JSONDecoder.gamesSnake.decode(GomokuStateResponse.self, from: Data(
            GamesGomokuJSON.state(nowMs: nowMs, matchID: matchID, moves: [("black", "H8"), ("white", "I9")]).utf8))
        harness.gomoku.applyState(active.state)
        #expect(harness.gomoku.phase == .playing)
        #expect(harness.model.router.selectedTab == .games, "판이 시작됐는데 오목 화면을 열지 않았다")
        #expect(harness.model.router.lastOpenedRoute == .gomokuMatch(matchID: nil))
        #expect(harness.games.wantsIdleTimerDisabled)

        harness.model.sceneDidEnterBackground()
        #expect(!harness.games.wantsIdleTimerDisabled, "background 에서 화면 꺼짐 방지를 쥐고 있다")
        harness.model.sceneDidBecomeActive()
        #expect(harness.games.wantsIdleTimerDisabled)

        // 화면이 이미 보이면 다시 열지 않는다(경로를 비우지 않는다) — 코어 openWindow 가 끝에서 presentWindow 를 부르는 경로 포함.
        let serial = harness.model.router.routeSerial
        harness.games.gomokuScreenDidAppear()
        #expect(harness.model.router.routeSerial == serial, "보이는 오목 화면을 또 열어 경로를 비웠다")
        let finished = try JSONDecoder.gamesSnake.decode(GomokuStateResponse.self, from: Data(
            GamesGomokuJSON.state(nowMs: nowMs, matchID: matchID, finished: true, moves: [("black", "H8"), ("white", "I9")]).utf8))
        harness.gomoku.applyState(finished.state)
        #expect(harness.gomoku.phase == .result)
        #expect(!harness.games.wantsIdleTimerDisabled, "끝난 판인데 화면 꺼짐 방지를 쥐고 있다")
        #expect(harness.model.router.routeSerial == serial)

        // 결과 화면인 채로 잠깐 앱을 나갔다 — 판에서 '나간' 것이 아니다(gomoku_leave 없음). 화면을 떠나면 그때 나간다.
        harness.model.sceneDidEnterBackground()
        await harness.barrier()
        #expect(harness.server.requests("gomoku_leave").isEmpty, "background 로 결과 화면의 판에서 나갔다")
        harness.model.sceneDidBecomeActive()
        harness.games.gomokuScreenDidDisappear()
        #expect(await baseWaitUntil { harness.server.requests("gomoku_leave").count == 1 }, "결과 화면을 떠났는데 판에서 나가지 않았다")

        await harness.model.session.signOut()
        #expect(harness.games.badgeCount == 0)
        #expect(!harness.games.isGomokuScreenVisible)
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    // MARK: - 데모 모드

    @Test("데모 픽스처(게임 탭): 대국 장면은 흑 차례 · H8 3-3 금수 · 채팅 · 결과 장면은 이긴 판 · 미니게임 장면은 순위·토큰 · 금지 호출 0")
    func demoFixturesDriveTheScreens() async {
        let index = MobileDemoFixtures.load()
        let routes = ["games/gomoku/match", "games/gomoku/match/demo-result", "games/flappy", "games", "games/gomoku/lobby"]
        for route in routes {
            let host = BaseStub.makeHost("games-demo")
            let scenario = route.replacingOccurrences(of: "/", with: "-").lowercased()
            MobileStubURLProtocol.register(host: host) { request in index.response(for: request, scenario: scenario) }
            let storage = BaseStub.makeStorage()
            let vault = InMemoryTokenVault()
            vault.write(MobileDemo.accessToken, key: AingKeychain.accessTokenKey)
            vault.write("demo-refresh-token", key: AingKeychain.refreshTokenKey)
            storage.defaults.set(MobileDemo.userID, forKey: AingSharedKeys.userID)
            let model = MobileAppModel(environment: MobileEnvironment(
                service: BaseStub.makeService(host: host), vault: vault, storage: storage, appInfo: BaseStub.appInfo,
                clock: .fixed(MobileClock.demoInstant), installationID: MobileDemo.installationID,
                realtimeTransport: nil, runsTimers: false, reloadWidgetTimelines: {}, demoRoute: route))
            model.session.clientReleaseTimeoutSeconds = 0
            model.start()
            #expect(await baseWaitUntil { model.session.isSignedIn }, "\(route)")
            model.sceneDidBecomeActive()
            switch route {
            case "games/gomoku/match":
                model.games.gomokuScreenDidAppear()
                #expect(await baseWaitUntil { model.gomoku.phase == .playing }, "\(route): 대국이 안 열렸다")
                let match = model.gomoku.match
                #expect(match?.myColor == .black && match?.turn == .black)
                if let board = match?.board {
                    #expect(GomokuRules.forbiddenPoints(board: board)[GomokuPoint(notation: "H8")!] == .doubleThree)
                }
                #expect(await baseWaitUntil { model.gomoku.chat.count >= 3 })
                #expect(model.gomoku.remainingSeconds(now: MobileClock.demoInstant).map { $0 > 15 && $0 <= 30 } == true)
            case let r where r.hasPrefix("games/gomoku/match/"):
                model.games.pendingGomokuFocusID = "demo-result"
                model.games.gomokuScreenDidAppear()
                #expect(await baseWaitUntil { model.gomoku.phase == .result }, "\(route): 결과가 안 열렸다")
                #expect(model.gomoku.match?.outcome == .won)
            case "games/flappy":
                model.games.miniGames.openScreen(.flappy)
                #expect(await baseWaitUntil { model.games.miniGames.boards[.flappy]?.entries.count ?? 0 >= 5 })
                #expect(await baseWaitUntil { model.games.miniGames.roundToken != nil })
                #expect(await baseWaitUntil { model.games.miniGames.boards[.flappy]?.yesterdayWinner != nil })
            case "games":
                model.games.hubDidAppear()
                // 게임 목록에서 끌어온다 — 게임이 늘 때마다 여기에 이름을 하나씩 더하는 대신,
                // 픽스처가 빠진 게임이 **그 자리에서** 드러나게 한다(아래 `missing` 검사와 짝이다).
                #expect(await baseWaitUntil {
                    MiniGameKind.phoneCases.allSatisfy { model.games.miniGames.myRank($0) != nil }
                }, "데모 첫 화면에서 순위가 안 뜬 게임이 있다 — 픽스처가 빠졌다")
                #expect(await baseWaitUntil { model.games.badgeCount >= 1 }, "데모 첫 화면에 받은 신청이 없다")
            default:
                model.games.gomokuScreenDidAppear()
                #expect(await baseWaitUntil { model.gomoku.users.count >= 5 && !model.gomoku.incoming.isEmpty })
                #expect(model.gomoku.liveMatches.count >= 1)
            }
            await baseBarrier(model.context.service)
            let requests = baseRequests(host: host)
            #expect(MobileForbiddenCalls.violations(in: requests).isEmpty, "\(route)")
            let missing = requests.filter { request in
                let key = MobileDemoFixtures.key(for: request)
                return (key.hasPrefix("rpc.gomoku_") || key.hasPrefix("rpc.minigame_")) && index.entry(for: request, scenario: scenario) == nil
            }.map(MobileDemoFixtures.key)
            #expect(missing.isEmpty, "\(route): 게임 탭 픽스처 없는 요청 \(missing)")
            model.gomoku.reset()
            model.sceneDidEnterBackground()
            BaseStub.tearDown(host: host, storage: storage)
        }
    }
}

extension JSONDecoder {
    /// 서비스와 같은 snake_case 디코더.
    static var gamesSnake: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
