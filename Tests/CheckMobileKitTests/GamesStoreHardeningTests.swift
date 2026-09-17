@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 게임 탭 수리(games-fix) 회귀 시나리오 — 검증(games-verify)이 찾은 결함과, 지워도 스위트가 초록이던 가드
/// (늦은 제출·순위 응답의 세대 가드 · 404 접기 · reset 의 대상 id 비우기 · 점수 상한)를 각각 붙잡는다.
@MainActor
@Suite(.serialized) struct GamesStoreHardeningTests {
    private nonisolated static let boardJSON = #"[{"user_id":"u-games","display_name":"나","avatar_url":null,"best_score":40,"best_at":"2026-09-17T04:00:00Z","plays":3,"center":"seoul"},{"user_id":"p-1","display_name":"구름빵","avatar_url":null,"best_score":80,"best_at":"2026-09-17T03:00:00Z","plays":5,"center":null}]"#
    private nonisolated static let tokenJSON = #"{"status":"ok","token":"tok-hard","expires_at":"2026-09-17T05:35:00Z","server_now":"2026-09-17T05:05:00Z"}"#

    /// 플래피 한 판을 끝까지(안 누르고 떨어져 0점) 민다.
    private func playFlappyToResult(_ controller: GamesPlayController, from start: Date) {
        controller.tap()
        controller.tick(at: start)
        gamesDrive(controller, from: start, frames: 600) { $0.flappy.phase == .result }
    }

    // MARK: - 순위 공개 여부

    @Test("순위 공개를 끈 사람: 공개 여부 조회가 한 번 실패해도 아는 값(비공개)을 지킨다 — 토큰도 제출도 없다")
    func privateFlagSurvivesTransientLookupFailure() async throws {
        let harness = GamesHarness(label: "games-private-flip")
        let failProfiles = BaseLockedBox(false)
        harness.server.setDefault("minigame_board", json: Self.boardJSON)
        harness.server.setDefault("minigame_yesterday_winner", json: "[]")
        harness.server.setDefault("/rest/v1/profiles") { _ in
            failProfiles.get() ? .networkFailure() : .json(#"[{"minigame_public":false}]"#)
        }
        harness.server.setDefault("minigame_start_round", json: Self.tokenJSON)
        harness.server.setDefault("minigame_submit_score", json: #"{"status":"ok","best_score":0,"plays":1,"improved":true}"#)
        await harness.signIn()

        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { !harness.hub.isPublic && harness.hub.boards[.flappy]?.loaded == true })
        harness.hub.closeScreen(.flappy)

        // 같은 로그인에서 다시 연다 — 이번엔 공개 여부 조회만 실패(오프라인 순간), 나머지는 정상.
        failProfiles.mutate { $0 = true }
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.server.requests("/rest/v1/profiles").count >= 2 })
        #expect(await baseWaitUntil { harness.server.requests("minigame_board").count >= 2 }, "조회 실패 뒤 화면 흐름이 멈췄다")
        #expect(!harness.hub.isPublic, "조회 한 번 실패로 비공개를 공개로 덮었다")

        let controller = try #require(harness.hub.controller)
        playFlappyToResult(controller, from: harness.clock.now)
        #expect(controller.flappy.phase == .result)
        await harness.barrier()
        #expect(harness.server.requests("minigame_start_round").isEmpty, "공개를 끈 사람에게 토큰을 받았다")
        #expect(harness.server.requests("minigame_submit_score").isEmpty, "순위 공개를 끈 사람의 점수가 올라갔다(조회 일시 실패 뒤)")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("공개 여부: 서버가 값을 안 주면(행·컬럼 없음) · 표가 없는 서버면 공개로 접는다 — 실패만 아는 값을 지킨다")
    func publicFlagFoldsOnlyUnknownServerValues() async {
        let harness = GamesHarness(label: "games-public-fold")
        // 0 비공개 · 1 빈 배열(행 없음) · 2 값 null · 3 표 없음(PGRST205) · 4 5xx
        let mode = BaseLockedBox(0)
        harness.server.setDefault("/rest/v1/profiles") { _ in
            switch mode.get() {
            case 0: return .json(#"[{"minigame_public":false}]"#)
            case 1: return .json("[]")
            case 2: return .json(#"[{"minigame_public":null}]"#)
            case 3: return .json(#"{"code":"PGRST205","message":"Could not find the table 'public.profiles' in the schema cache"}"#, status: 404)
            default: return .json(#"{"message":"unavailable"}"#, status: 503)
            }
        }
        await harness.signIn()

        for (step, expected) in [(0, false), (1, true), (0, false), (2, true), (0, false), (3, true), (0, false), (4, false)] {
            mode.mutate { $0 = step }
            await harness.hub.refreshPublic()
            #expect(harness.hub.isPublic == expected, "mode \(step): isPublic=\(harness.hub.isPublic)")
        }
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    // MARK: - 딥링크

    @Test("오목 화면이 이미 보이는 중에 온 gomoku/match/<id> 딥링크: 대상 판을 바로 연다 · 대상 id 를 남기지 않는다 · 로그아웃은 남은 id 를 비운다")
    func deepLinkWhileGomokuScreenVisibleAppliesFocus() async throws {
        let harness = GamesHarness(label: "games-focus")
        let nowMs = harness.serverNowMs
        harness.server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs))
        harness.server.setDefault("gomoku_lobby", json: GamesGomokuJSON.lobby(nowMs: nowMs))
        harness.server.setDefault("gomoku_state") { request in
            request.bodyText.contains("m-focus-2")
                ? .json(GamesGomokuJSON.state(nowMs: nowMs, matchID: "m-focus-2", moves: [("black", "H8")]))
                : .missingFunction("gomoku_state")
        }
        await harness.signIn()
        let router = harness.model.router

        // 로비를 보는 중(오목 화면 표시).
        router.selectedTab = .games
        harness.games.gomokuScreenDidAppear()
        #expect(await baseWaitUntil { harness.gomoku.hasLoadedLobby })
        #expect(harness.gomoku.phase == .lobby)

        // 푸시 탭 = 라우터가 경로를 비우고 링크를 남긴다 → 게임 탭이 꺼내 스토어에 묻는다.
        router.open(.gomokuMatch(matchID: "m-focus-2"))
        let route = try #require(router.consumePendingRoute(for: .games))
        #expect(harness.games.routeStep(for: route) == .push(.gomoku), "비워진 경로를 되돌려야 화면이 닫히지 않는다")
        #expect(harness.games.pendingGomokuFocusID == nil, "보이는 화면에 대상 id 를 남겼다 — 나중의 무관한 진입에 쓰인다")
        #expect(await baseWaitUntil { harness.gomoku.match?.id == "m-focus-2" }, "보이는 오목 화면에 온 대상 판이 적용되지 않았다")
        #expect(harness.server.requests("gomoku_state").contains { $0.bodyText.contains("m-focus-2") })

        // 화면을 떠난 뒤 온 대상 링크는 다음 표시가 꺼내 쓴다.
        harness.games.gomokuScreenDidDisappear()
        router.open(.gomokuInvite(matchID: "i-9"))
        let invite = try #require(router.consumePendingRoute(for: .games))
        #expect(harness.games.routeStep(for: invite) == .push(.gomoku))
        #expect(harness.games.pendingGomokuFocusID == "i-9")

        // 게임 탭의 다른 라우트.
        #expect(harness.games.routeStep(for: .games) == .popToRoot)
        #expect(harness.games.routeStep(for: .miniGame(.timing)) == .push(.miniGame(.timingBar)))
        #expect(harness.games.routeStep(for: .miniGame(.flappy)) == .push(.miniGame(.flappy)))
        #expect(harness.games.routeStep(for: .now) == nil)

        // 로그아웃(세대 교체) — 남아 있던 대상 id 는 다음 계정의 진입에 쓰이지 않는다.
        await harness.model.session.signOut()
        #expect(harness.games.pendingGomokuFocusID == nil, "로그아웃 뒤에도 옛 계정의 대상 id 가 남았다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    // MARK: - 화면 꺼짐 방지

    @Test("대국 중 화면 꺼짐 방지는 스토어 하나가 쥔다 — 오목 화면을 떠나도(뒤로) 판이 도는 동안 유지 · background·끝·로그아웃이면 푼다")
    func idleTimerFollowsMatchNotScreen() async throws {
        let harness = GamesHarness(label: "games-idle")
        let nowMs = harness.serverNowMs
        harness.server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs))
        harness.server.setDefault("gomoku_lobby", json: GamesGomokuJSON.lobby(nowMs: nowMs))
        harness.server.setDefault("gomoku_leave", json: #"{"status":"ok","both_left":false}"#)
        // 서버 판 상태(화면이 나타나며 다시 읽는 판이 테스트가 넣은 상태와 같게).
        let serverFinished = BaseLockedBox(false)
        let serverMatchID = BaseLockedBox("m-idle")
        harness.server.setDefault("gomoku_state") { _ in
            .json(GamesGomokuJSON.state(nowMs: nowMs, matchID: serverMatchID.get(), finished: serverFinished.get(),
                                        moves: [("black", "H8"), ("white", "I9")]))
        }
        let applied = BaseLockedBox<[Bool]>([])
        harness.games.installIdleTimerSink { value in applied.mutate { $0.append(value) } }
        harness.games.installIdleTimerSink { _ in Issue.record("두 번째 싱크가 걸렸다(관찰이 겹친다)") }
        #expect(applied.get() == [false])
        await harness.signIn()

        let active = try JSONDecoder.gamesSnake.decode(GomokuStateResponse.self, from: Data(
            GamesGomokuJSON.state(nowMs: nowMs, matchID: "m-idle", moves: [("black", "H8"), ("white", "I9")]).utf8))
        harness.gomoku.applyState(active.state)
        #expect(await baseWaitUntil { applied.get().last == true }, "판이 시작됐는데 화면 꺼짐 방지를 켜지 않았다")

        // 오목 화면에 들어갔다가 [뒤로] — 판은 서버에서 계속 돈다.
        harness.games.gomokuScreenDidAppear()
        harness.games.gomokuScreenDidDisappear()
        harness.model.router.popToRoot(.games)
        await baseYield()
        await harness.barrier()
        #expect(applied.get().last == true, "대국 중 오목 화면을 떠났더니 화면 꺼짐 방지가 풀렸다")
        #expect(harness.games.appliedIdleTimerDisabled == true)

        harness.model.sceneDidEnterBackground()
        #expect(await baseWaitUntil { applied.get().last == false }, "background 에서 화면 꺼짐 방지를 쥐고 있다")
        harness.model.sceneDidBecomeActive()
        #expect(await baseWaitUntil { applied.get().last == true })

        let finished = try JSONDecoder.gamesSnake.decode(GomokuStateResponse.self, from: Data(
            GamesGomokuJSON.state(nowMs: nowMs, matchID: "m-idle", finished: true, moves: [("black", "H8"), ("white", "I9")]).utf8))
        serverFinished.mutate { $0 = true }
        harness.gomoku.applyState(finished.state)
        #expect(await baseWaitUntil { applied.get().last == false }, "끝난 판인데 화면 꺼짐 방지를 쥐고 있다")

        // 끝난 판은 다시 열리지 않는다(같은 판의 늦은 진행 중 스냅숏은 버린다) — 다시 켜지는 길은 **새 판**이다.
        harness.gomoku.applyState(active.state)
        await baseYield()
        await harness.barrier()
        #expect(applied.get().last == false, "끝난 판에 늦게 온 진행 중 스냅숏이 화면 꺼짐 방지를 다시 켰다")
        let next = try JSONDecoder.gamesSnake.decode(GomokuStateResponse.self, from: Data(
            GamesGomokuJSON.state(nowMs: nowMs, matchID: "m-idle-2", moves: [("black", "H8"), ("white", "I9")]).utf8))
        serverMatchID.mutate { $0 = "m-idle-2" }
        serverFinished.mutate { $0 = false }
        harness.gomoku.applyState(next.state)
        #expect(await baseWaitUntil { applied.get().last == true })
        await harness.model.session.signOut()
        #expect(await baseWaitUntil { applied.get().last == false }, "로그아웃했는데 화면 꺼짐 방지를 쥐고 있다")

        let values = applied.get()
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 != $1 }, "같은 값을 거듭 넘겼다: \(values)")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    // MARK: - 늦은 응답 · 세대

    @Test("로그아웃 → 다른 계정 로그인 사이에 늦게 온 옛 계정의 순위·제출 응답은 새 계정의 화면·로컬 최고에 쓰지 않는다")
    func lateResponsesAfterReloginAreDropped() async throws {
        let harness = GamesHarness(label: "games-relogin")
        harness.server.setDefault("/rest/v1/profiles", json: #"[{"minigame_public":true}]"#)
        harness.server.setDefault("minigame_yesterday_winner", json: "[]")
        harness.server.setDefault("minigame_start_round", json: Self.tokenJSON)
        harness.server.setDefault("minigame_board", json: Self.boardJSON)
        harness.server.setDefault("minigame_submit_score", json: #"{"status":"ok","best_score":999,"plays":9,"improved":true}"#)
        await harness.signIn()
        // 옛 계정의 순위·제출 응답을 붙잡아 두었다가 다른 계정 로그인 뒤에 놓는다.
        let boardHold = BaseHold.rpc("minigame_board", host: harness.server.host)
        let submitHold = BaseHold.rpc("minigame_submit_score", host: harness.server.host)

        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-hard" && boardHold.held == 1 })
        let controller = try #require(harness.hub.controller)
        playFlappyToResult(controller, from: harness.clock.now)
        #expect(await submitHold.waitHeld())

        // 두 응답이 도는 동안 로그아웃하고 다른 계정으로 들어간다.
        await harness.model.session.signOut()
        let other = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(24 * 3600), subject: "u-other")
        harness.server.setDefault("/auth/v1/token") { _ in BaseStub.authResponse(access: other, refresh: "r-other", userID: "u-other") }
        await harness.model.session.signIn(email: "other@aing.invalid", password: "pw")
        #expect(harness.model.session.session?.userID.lowercased() == "u-other")

        #expect(await boardHold.releaseAndWaitDelivered())
        #expect(await submitHold.releaseAndWaitDelivered())
        await harness.barrier()
        #expect(harness.hub.boards[.flappy] == nil, "옛 계정의 늦은 순위 응답이 새 계정 화면에 들어왔다")
        #expect((harness.hub.localBest[.flappy] ?? 0) == 0, "옛 계정의 늦은 제출 응답이 새 계정의 최고로 보인다")
        #expect(harness.storage.defaults.integer(forKey: GamesMiniGameHub.bestKey(userID: "u-other", kind: .flappy)) == 0,
                "옛 계정의 늦은 제출 응답이 새 계정의 로컬 최고 키에 써졌다")
        #expect(harness.hub.submitNotice == nil)
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    // MARK: - 순위 조회 접기

    @Test("순위 조회: 함수가 없는 서버(404 PGRST202)는 실패가 아니라 빈 기록 · 5xx 는 실패 — 실패면 사람 수를 모른다")
    func boardMissingFunctionFoldsAndFailureHidesQuorum() async throws {
        let harness = GamesHarness(label: "games-board-fold")
        let mode = BaseLockedBox(0)
        harness.server.setDefault("minigame_board") { _ in
            switch mode.get() {
            case 0: return .missingFunction("minigame_board")
            case 1: return .json(#"{"message":"unavailable"}"#, status: 503)
            default: return .json(Self.boardJSON)
            }
        }
        await harness.signIn()

        await harness.hub.loadBoard(.timingBar, withWinner: false)
        var state = try #require(harness.hub.boards[.timingBar])
        #expect(state.loaded && !state.failed && state.entries.isEmpty, "404 를 실패로 봤다: \(state)")
        #expect(state.knowsPlayerCount, "함수 없는 서버는 '아직 아무도 안 했다'가 맞다")

        await harness.hub.loadBoard(.flappy, withWinner: false)
        mode.mutate { $0 = 1 }
        await harness.hub.loadBoard(.flappy, withWinner: false)
        state = try #require(harness.hub.boards[.flappy])
        #expect(state.failed && state.entries.isEmpty)
        #expect(!state.knowsPlayerCount, "불러오지 못한 순위를 '아무도 안 했어요'로 말한다")

        mode.mutate { $0 = 2 }
        await harness.hub.loadBoard(.flappy, withWinner: false)
        mode.mutate { $0 = 1 }
        await harness.hub.loadBoard(.flappy, withWinner: false)
        state = try #require(harness.hub.boards[.flappy])
        #expect(state.failed && state.entries.count == 2 && state.knowsPlayerCount, "줄이 있으면 적어도 그만큼은 했다")

        #expect(!GamesMiniGameBoard().knowsPlayerCount, "불러오는 중(아직 모름)")
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    // MARK: - 점수 상한

    @Test("범위 밖 점수(음수 · 게임 상한 초과)는 로컬 최고도 제출도 없다 — 토큰은 그대로 · 범위 안 점수는 올라간다")
    func outOfRangeScoresAreDropped() async {
        let harness = GamesHarness(label: "games-score-range")
        harness.server.setDefault("/rest/v1/profiles", json: #"[{"minigame_public":true}]"#)
        harness.server.setDefault("minigame_board", json: "[]")
        harness.server.setDefault("minigame_yesterday_winner", json: "[]")
        harness.server.setDefault("minigame_start_round", json: Self.tokenJSON)
        harness.server.setDefault("minigame_submit_score", json: #"{"status":"ok","best_score":3,"plays":1,"improved":true}"#)
        await harness.signIn()
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-hard" })

        harness.hub.recordScore(kind: .flappy, score: MiniGameKind.flappy.maxScore + 1)
        harness.hub.recordScore(kind: .flappy, score: -1)
        await harness.barrier()
        #expect(harness.server.requests("minigame_submit_score").isEmpty, "상한을 넘는 점수를 올렸다")
        #expect((harness.hub.localBest[.flappy] ?? 0) == 0, "범위 밖 점수로 로컬 최고를 올렸다")
        #expect(harness.hub.roundToken == "tok-hard", "범위 밖 점수가 토큰을 써 버렸다")

        harness.hub.recordScore(kind: .flappy, score: 3)
        #expect(await baseWaitUntil { harness.server.requests("minigame_submit_score").count == 1 }, "범위 안 점수가 안 올라갔다(대조군)")
        #expect(harness.hub.best(for: .flappy) == 3)
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }
}
