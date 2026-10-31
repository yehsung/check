@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 제출 인편(맥 v0.3.39 → 폰 1.0.17). 맥 쪽 짝은 `Tests/checkTests/V0339MiniGamePendingSubmitTests.swift`.
//
// ⚠️ 스텁은 호출마다 다른 토큰을 줘야 한다(`gamesServeRoundTokens`) — 같은 문자열이면 갈아 끼워져도 바뀐 것이 없어 영원히 초록이다.
// ⚠️ 하네스 시계는 안 흐른다. 시간이 필요한 단언은 `clock.advance` 와 `hub.sleep` 으로만 한다.

@Suite("폰 제출 인편")
@MainActor
struct GamesMiniGamePendingSubmitTests {
    private static let ok = #"{"status":"ok","best_score":55,"plays":4,"improved":true}"#

    private func configure(_ harness: GamesHarness, submit: String = Self.ok, isPublic: Bool = true) {
        harness.server.setDefault("minigame_board", json: "[]")
        harness.server.setDefault("minigame_yesterday_winner", json: "[]")
        harness.server.setDefault("/rest/v1/profiles", json: #"[{"minigame_public":\#(isPublic)}]"#)
        harness.server.setDefault("minigame_submit_score", json: submit)
    }

    /// 앱을 끄기 전에 남은 인편을 디스크에 적어 둔다.
    private func seed(_ harness: GamesHarness, _ entries: [MiniGamePendingSubmit], userID: String = GamesHarness.userID) throws {
        harness.storage.defaults.set(try JSONEncoder().encode(entries), forKey: GamesMiniGameHub.pendingKey(userID: userID))
    }

    private func entry(_ kind: MiniGameKind = .flappy, score: Int = 7, token: String? = "tok-disk", at date: Date,
                       recovered: Bool = false) -> MiniGamePendingSubmit {
        MiniGamePendingSubmit(id: UUID(), kind: kind, score: score, token: token, tokenIssuedAt: token == nil ? nil : date,
                              recordedAt: date, attempts: 0, recoveredFromDeadTokenOnce: recovered)
    }

    private func submits(_ harness: GamesHarness) -> [String] {
        harness.server.requests("minigame_submit_score").map(\.bodyText)
    }

    /// 타이머를 문 앞에 세워 둔다(실제로 기다리지 않고, 돌아오지도 않는다). 끝나면 `gate.open()`.
    private func parkTimers(_ harness: GamesHarness) -> BaseGate {
        let gate = BaseGate()
        harness.hub.sleep = { _ in await gate.wait() }
        return gate
    }

    // MARK: - 재시작

    @Test("재시작: 적어 둔 인편이 로그인 직후 **같은 토큰으로** 나가고 디스크에서 지워진다")
    func aRestartResendsWithTheSameToken() async throws {
        let first = GamesHarness(label: "pending-restart-1")
        configure(first)
        first.server.setDefault("minigame_submit_score") { _ in .networkFailure() }
        _ = gamesServeRoundTokens(first, prefix: "tok-first")
        let gate = parkTimers(first)
        await first.signIn()
        first.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { first.hub.roundToken == "tok-first-1" })
        first.hub.recordScore(kind: .flappy, score: 13)
        #expect(first.storage.defaults.data(forKey: GamesMiniGameHub.pendingKey(userID: GamesHarness.userID)) != nil,
                "제출 **전에** 적지 않았다 — 왕복 중에 앱이 죽으면 점수가 사라진다")
        #expect(await baseWaitUntil { submits(first).count == 1 })
        await first.barrier()
        let saved = try #require(first.storage.defaults.data(forKey: GamesMiniGameHub.pendingKey(userID: GamesHarness.userID)))
        gate.open()
        await first.tearDown()

        // 앱을 다시 켰다(스토어가 새로 선다).
        let second = GamesHarness(label: "pending-restart-2")
        configure(second)
        second.storage.defaults.set(saved, forKey: GamesMiniGameHub.pendingKey(userID: GamesHarness.userID))
        _ = gamesServeRoundTokens(second, prefix: "tok-second")
        await second.signIn()
        #expect(await baseWaitUntil { submits(second).count == 1 }, "로그인했는데 되살린 인편을 안 보냈다")
        #expect(submits(second)[0].contains(#""p_token":"tok-first-1""#), "다른 토큰으로 나갔다")
        #expect(submits(second)[0].contains(#""p_score":13"#))
        #expect(await baseWaitUntil { second.hub.pendingSubmit == nil })
        #expect(second.storage.defaults.data(forKey: GamesMiniGameHub.pendingKey(userID: GamesHarness.userID)) == nil,
                "성공 뒤 디스크의 인편이 안 지워졌다")
        #expect(second.violations.isEmpty, "\(second.violations)")
        await second.tearDown()
    }

    @Test("재시작: 그 사이 공개를 껐으면 되살린 인편을 **보내지 않는다** — 공개 여부를 먼저 묻는다")
    func aRestartAsksAboutPublicFirst() async throws {
        let harness = GamesHarness(label: "pending-restart-private")
        configure(harness, isPublic: false)
        try seed(harness, [entry(at: harness.clock.now)])
        await harness.signIn()
        #expect(await baseWaitUntil { harness.hub.isPublic == false }, "공개 여부를 안 물었다")
        await harness.barrier()
        #expect(submits(harness).isEmpty, "공개를 끈 사람의 점수가 나갔다(`모름 = 공개` 기본값을 믿었다)")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("TTL 을 넘긴 인편은 읽을 때 버려지고 다음에 화면을 열 때 **한 번** 말한다 · 산 인편만 나간다")
    func expiredPendingIsDroppedAndToldOnce() async throws {
        let harness = GamesHarness(label: "pending-ttl")
        configure(harness)
        _ = gamesServeRoundTokens(harness, prefix: "tok-ttl")
        let stale = harness.clock.now.addingTimeInterval(-(MiniGameSubmitRules.pendingTTL + 60))
        try seed(harness, [entry(score: 5, token: "tok-old", at: stale), entry(score: 6, token: nil, at: stale),
                           entry(score: 7, token: "tok-new", at: harness.clock.now)])
        await harness.signIn()
        #expect(await baseWaitUntil { submits(harness).count == 1 })
        #expect(submits(harness)[0].contains("tok-new"), "죽은 인편이 나갔다: \(submits(harness))")
        #expect(await baseWaitUntil { harness.hub.pendingSubmit == nil })

        harness.hub.openScreen(.flappy)
        #expect(harness.hub.submitNotice == GamesMiniGameText.submitFailedConnection, "화면을 닫아 둔 사이 죽은 점수를 안 말했다")
        harness.hub.closeScreen(.flappy)
        harness.hub.openScreen(.flappy)
        #expect(harness.hub.submitNotice == nil, "같은 일을 두 번 말했다")
        await harness.tearDown()
    }

    @Test("로그아웃은 디스크의 인편을 안 지운다 — 같은 계정에만 다시 보이고 남의 이름으로 안 나간다")
    func signOutKeepsThePendingForTheSameAccountOnly() async throws {
        let harness = GamesHarness(label: "pending-account")
        configure(harness)
        harness.server.setDefault("minigame_submit_score") { _ in .networkFailure() }
        _ = gamesServeRoundTokens(harness, prefix: "tok-acc")
        let gate = parkTimers(harness)
        await harness.signIn()
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-acc-1" })
        harness.hub.recordScore(kind: .flappy, score: 9)
        #expect(await baseWaitUntil { submits(harness).count == 1 })
        await harness.barrier()

        await harness.model.session.signOut()
        #expect(harness.hub.pendingSubmit == nil)
        #expect(harness.storage.defaults.data(forKey: GamesMiniGameHub.pendingKey(userID: GamesHarness.userID)) != nil,
                "로그아웃이 영속 인편을 지웠다 — 돌아온 사람의 점수가 사라진다")

        let other = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(24 * 3600), subject: "u-other")
        harness.server.setDefault("/auth/v1/token") { _ in BaseStub.authResponse(access: other, refresh: "r-other", userID: "u-other") }
        await harness.model.session.signIn(email: "other@aing.invalid", password: "pw")
        #expect(harness.hub.pendingSubmit == nil, "다른 계정에 앞 사람의 인편이 보인다")
        await harness.barrier()
        #expect(submits(harness).count == 1, "앞 사람의 점수를 다른 계정으로 보냈다")
        await harness.model.session.signOut()

        let back = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(24 * 3600), subject: GamesHarness.userID)
        harness.server.setDefault("/auth/v1/token") { _ in BaseStub.authResponse(access: back, refresh: "r-back", userID: GamesHarness.userID) }
        await harness.model.session.signIn(email: "games@aing.invalid", password: "pw")
        #expect(harness.hub.pendingSubmit?.score == 9, "같은 계정으로 돌아왔는데 인편이 안 보인다")
        gate.open()
        await harness.tearDown()
    }

    // MARK: - 토큰 대기

    @Test("토큰이 왕복 중에 끝난 판은 그 응답을 받아 올라간다 — 또 요청하지 않는다")
    func aRoundThatEndsDuringTheRoundTripTakesTheResponse() async throws {
        let harness = GamesHarness(label: "pending-wait")
        configure(harness)
        let tokens = gamesServeRoundTokens(harness, prefix: "tok-wait")
        await harness.signIn()
        let hold = BaseHold.rpc("minigame_start_round", host: harness.server.host)
        harness.hub.openScreen(.flappy)
        #expect(await hold.waitHeld())
        harness.hub.recordScore(kind: .flappy, score: 4)
        #expect(harness.hub.pendingSubmit?.token == nil)
        #expect(harness.hub.submitNotice == GamesMiniGameText.submitRetrying)
        #expect(await hold.releaseAndWaitDelivered())
        #expect(await baseWaitUntil { submits(harness).count == 1 })
        #expect(submits(harness)[0].contains("tok-wait-1"))
        #expect(await baseWaitUntil { harness.hub.pendingSubmit == nil })
        // 인편이 비워지는 순간 다음 판의 토큰을 받는다.
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-wait-2" }, "\(tokens.get())")
        #expect(harness.hub.submitNotice == nil)
        await harness.tearDown()
    }

    @Test("토큰을 기다리는 인편 둘은 **순서대로** 토큰을 받아 나간다")
    func waitingScoresTakeTokensInOrder() async throws {
        let harness = GamesHarness(label: "pending-order")
        configure(harness)
        _ = gamesServeRoundTokens(harness, prefix: "tok-ord")
        await harness.signIn()
        let hold = BaseHold.rpc("minigame_start_round", host: harness.server.host)
        harness.hub.openScreen(.flappy)
        #expect(await hold.waitHeld())
        harness.hub.recordScore(kind: .flappy, score: 1)
        harness.hub.recordScore(kind: .flappy, score: 2)
        #expect(harness.hub.pendingSubmits.map(\.score) == [1, 2])
        #expect(await hold.releaseAndWaitDelivered())
        #expect(await baseWaitUntil { submits(harness).count == 2 && harness.hub.pendingSubmit == nil }, "\(submits(harness))")
        #expect(submits(harness)[0].contains(#""p_score":1"#) && submits(harness)[0].contains("tok-ord-1"), "\(submits(harness))")
        #expect(submits(harness)[1].contains(#""p_score":2"#) && submits(harness)[1].contains("tok-ord-2"), "\(submits(harness))")
        await harness.tearDown()
    }

    // MARK: - 불변식

    @Test("★ 토큰을 실은 인편이 살아 있으면 어떤 방아쇠에서도 그 게임의 `start_round` 가 나가지 않는다")
    func noStartRoundWhileAPendingCarriesAToken() async throws {
        let harness = GamesHarness(label: "pending-invariant")
        configure(harness)
        harness.server.setDefault("minigame_submit_score") { _ in .networkFailure() }
        let tokens = gamesServeRoundTokens(harness, prefix: "tok-inv")
        let gate = parkTimers(harness)
        await harness.signIn()
        harness.hub.openScreen(.crossy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-inv-1" })
        harness.hub.recordScore(kind: .crossy, score: 3)
        #expect(await baseWaitUntil { submits(harness).count == 1 })
        await harness.barrier()

        // 방아쇠 전부: 선발급 · 판 시작 · 판 도중 감시 · 복귀. 토큰이 아주 늙어도 마찬가지다.
        harness.clock.advance(25 * 60)
        harness.hub.prefetchRoundToken(kind: .crossy)
        harness.hub.beginRound(kind: .crossy)
        harness.hub.keepRoundTokenFresh(kind: .crossy)
        harness.model.sceneDidEnterBackground()
        harness.model.sceneDidBecomeActive()
        await harness.barrier()
        #expect(tokens.get() == ["tok-inv-1"], "인편의 토큰을 자기 손으로 죽였다: \(tokens.get())")
        #expect(harness.hub.pendingSubmit?.token == "tok-inv-1")
        gate.open()
        await harness.tearDown()
    }

    // MARK: - 응답 분류

    @Test("`no_token` 은 **한 번** 되살린다 — 새 토큰으로 그 점수가 올라간다(다른 기기가 토큰을 갈아 끼운 판)")
    func noTokenIsRecoveredOnce() async throws {
        let harness = GamesHarness(label: "pending-recover")
        configure(harness)
        harness.server.enqueue("minigame_submit_score") { _ in .json(#"{"status":"no_token"}"#) }
        _ = gamesServeRoundTokens(harness, prefix: "tok-rec")
        await harness.signIn()
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-rec-1" })
        harness.hub.recordScore(kind: .flappy, score: 13)
        #expect(await baseWaitUntil { submits(harness).count == 2 })
        #expect(submits(harness)[1].contains("tok-rec-2"), "죽은 토큰을 또 보냈다: \(submits(harness))")
        #expect(submits(harness)[1].contains(#""p_score":13"#), "되살린 점수가 다르다")
        #expect(await baseWaitUntil { harness.hub.pendingSubmit == nil })
        #expect(harness.hub.submitNotice == nil)
        await harness.tearDown()
    }

    @Test("`no_token` 이 또 오면 두 번은 안 준다 · 되살림 표식은 재시작을 넘어간다")
    func noTokenTwiceGivesUpAcrossARestart() async throws {
        let harness = GamesHarness(label: "pending-recover-twice")
        configure(harness, submit: #"{"status":"no_token"}"#)
        let tokens = gamesServeRoundTokens(harness, prefix: "tok-two")
        await harness.signIn()
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-two-1" })
        harness.hub.recordScore(kind: .flappy, score: 13)
        #expect(await baseWaitUntil { submits(harness).count == 2 && harness.hub.pendingSubmit == nil })
        #expect(harness.hub.submitNotice == GamesMiniGameText.submitTokenDead)
        await harness.barrier()
        #expect(submits(harness).count == 2, "무한 왕복이다")
        #expect(tokens.get().count <= 3, "\(tokens.get())")
        await harness.tearDown()

        // 한 번 되살린 인편이 재시작한 뒤에 `no_token` 을 받으면 곧장 포기한다.
        let restarted = GamesHarness(label: "pending-recover-restart")
        configure(restarted, submit: #"{"status":"no_token"}"#)
        try seed(restarted, [entry(at: restarted.clock.now, recovered: true)])
        await restarted.signIn()
        #expect(await baseWaitUntil { submits(restarted).count == 1 && restarted.hub.pendingSubmit == nil })
        await restarted.barrier()
        #expect(submits(restarted).count == 1, "재시작이 되살림 기회를 새로 줬다")
        await restarted.tearDown()
    }

    @Test("모르는 status 는 인편을 남기되 타이머로 두드리지 않고, 방아쇠에서만 다시 나간다")
    func anUnknownStatusIsHeldUntilATrigger() async throws {
        let harness = GamesHarness(label: "pending-unknown")
        configure(harness, submit: #"{"status":"brand_new_status"}"#)
        let tokens = gamesServeRoundTokens(harness, prefix: "tok-unk")
        let delays = BaseLockedBox<[TimeInterval]>([])
        harness.hub.sleep = { seconds in delays.mutate { $0.append(seconds) } }
        await harness.signIn()
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-unk-1" })
        harness.hub.recordScore(kind: .flappy, score: 3)
        #expect(await baseWaitUntil { submits(harness).count == 1 })
        await harness.barrier()
        #expect(submits(harness).count == 1, "이해 못 한 거절을 두드렸다")
        #expect(delays.get().isEmpty, "타이머를 걸었다")
        #expect(harness.hub.pendingSubmit?.score == 3, "점수를 버렸다")
        #expect(tokens.get() == ["tok-unk-1"], "토큰이 살아 있을 수 있는데 새 토큰을 받았다")

        harness.model.sceneDidEnterBackground()
        harness.model.sceneDidBecomeActive()
        #expect(await baseWaitUntil { submits(harness).count == 2 }, "방아쇠에서 다시 안 나갔다")
        await harness.tearDown()
    }

    @Test("백오프 타이머가 돌아오면 같은 토큰으로 다시 나간다 — 시계를 주입한 빌드도 굳지 않는다")
    func theBackoffTimerResendsWithoutAMovingClock() async throws {
        let harness = GamesHarness(label: "pending-timer")
        configure(harness)
        harness.server.enqueue("minigame_submit_score") { _ in .networkFailure() }
        _ = gamesServeRoundTokens(harness, prefix: "tok-tim")
        harness.hub.sleep = { _ in }
        await harness.signIn()
        harness.hub.openScreen(.flappy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-tim-1" })
        harness.hub.recordScore(kind: .flappy, score: 3)
        #expect(await baseWaitUntil { submits(harness).count == 2 && harness.hub.pendingSubmit == nil }, "타이머가 다시 안 보냈다")
        #expect(submits(harness).allSatisfy { $0.contains("tok-tim-1") })
        await harness.tearDown()
    }

    // MARK: - 게임이 다른 인편

    @Test("다른 게임 인편이 비워질 때 받는 토큰은 **지금 화면의 게임** 것이다 — 들고 있는 토큰을 치우지 않는다")
    func anotherGamesPendingDoesNotStealTheTokenSlot() async throws {
        let harness = GamesHarness(label: "pending-slot")
        configure(harness)
        let tokens = gamesServeRoundTokens(harness, prefix: "tok-slot")
        await harness.signIn()
        harness.hub.openScreen(.tetris)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-slot-1" })
        await harness.barrier()
        // 플래피 제출 한 번의 꼬리만 잰다 — 들고 있는 토큰은 테트리스 것이다.
        let flappy = entry(score: 8, token: "tok-flappy", at: harness.clock.now)
        await harness.hub.performSubmit(entry: flappy)
        await harness.barrier()
        #expect(harness.hub.roundToken == "tok-slot-1", "다른 게임 제출 꼬리가 테트리스 토큰을 치웠다: \(tokens.get())")
        #expect(harness.hub.roundTokenKind == .tetris)
        #expect(tokens.get() == ["tok-slot-1"], "\(tokens.get())")
        await harness.tearDown()
    }

    @Test("다른 게임 판이 도는 중에는 토큰을 기다리는 인편에 토큰을 받아 주지 않는다 — 판이 끝나면 민다")
    func aWaitingPendingYieldsToALiveRoundOfAnotherGame() async throws {
        let harness = GamesHarness(label: "pending-live")
        configure(harness)
        _ = gamesServeRoundTokens(harness, prefix: "tok-live")
        let parked = parkTimers(harness)
        await harness.signIn()
        harness.hub.openScreen(.tetris)
        #expect(await baseWaitUntil { harness.hub.roundToken != nil && harness.hub.roundTokenKind == .tetris })
        let live = try #require(harness.hub.controller)
        live.tap()
        #expect(live.isPlaying)
        let tetrisToken = harness.hub.roundToken
        await harness.barrier()
        let before = harness.server.requests("minigame_start_round").count
        harness.hub.recordScore(kind: .flappy, score: 9)   // 플래피 토큰이 없다 → 토큰 대기 인편
        await harness.barrier()
        #expect(harness.server.requests("minigame_start_round").count == before, "돌고 있는 테트리스 판의 토큰을 치웠다")
        #expect(harness.hub.roundToken == tetrisToken)
        #expect(harness.hub.pendingSubmit?.kind == .flappy)

        // 판이 끝나면 민다.
        harness.hub.closeScreen(.tetris)
        #expect(await baseWaitUntil { harness.hub.pendingSubmits.isEmpty }, "판이 끝났는데 인편이 안 밀렸다: \(harness.hub.pendingSubmits)")
        parked.open()
        await harness.tearDown()
    }

    @Test("토큰을 기다리는 앞 게임 인편의 왕복을 다음 게임 화면이 무효로 만들지 않는다 — 그 인편이 먼저 올라가고 화면 게임의 토큰은 그 뒤에 받는다")
    func anotherScreensPrefetchDoesNotOrphanAWaitingPending() async throws {
        // 토큰 칸이 하나라 새 요청은 앞 요청의 응답을 세대 가드로 버린다. 앞 요청이 인편의 것이면 그 인편에는 왕복도 타이머도 안 남아 다음 방아쇠까지 굳는다.
        let harness = GamesHarness(label: "pending-orphan")
        configure(harness)
        let tokens = gamesServeRoundTokens(harness, prefix: "tok-orphan")
        try seed(harness, [entry(.flappy, score: 6, token: nil, at: harness.clock.now)])
        let hold = BaseHold.rpc("minigame_start_round", host: harness.server.host)
        await harness.signIn()
        #expect(await hold.waitHeld(), "되살린 인편에 토큰을 안 받아 줬다")

        harness.hub.openScreen(.tetris)
        #expect(await baseWaitUntil { harness.server.requests("minigame_board").contains { $0.bodyText.contains("tetris") } })
        await harness.barrier()
        #expect(tokens.get().isEmpty, "테트리스 선발급이 인편의 왕복을 치웠다: \(tokens.get())")

        #expect(await hold.releaseAndWaitDelivered())
        #expect(await baseWaitUntil { harness.hub.pendingSubmits.isEmpty }, "인편이 굳었다: \(harness.hub.pendingSubmits)")
        let sent = submits(harness)
        #expect(sent.count == 1, "\(sent)")
        #expect(sent.first?.contains(#""p_game":"flappy""#) == true && sent.first?.contains(#""p_score":6"#) == true, "\(sent)")
        #expect(await baseWaitUntil { harness.hub.roundTokenKind == .tetris }, "인편이 비워졌는데 화면 게임의 토큰을 안 받았다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("앞 로그인의 공개 여부 조회가 떠 있어도 다음 로그인의 되살린 인편은 자기 조회로 나간다")
    func aPublicCheckFromThePreviousLoginDoesNotHoldTheNextOne() async throws {
        let harness = GamesHarness(label: "pending-public-relogin")
        configure(harness)
        try seed(harness, [entry(score: 8, token: "tok-relogin", at: harness.clock.now)])
        let hold = BaseHold.install(host: harness.server.host) { $0.path == "/rest/v1/profiles" && $0.query.contains("minigame_public") }
        await harness.signIn()
        #expect(await hold.waitHeld(), "되살린 인편이 공개 여부를 안 물었다")
        #expect(submits(harness).isEmpty, "공개 여부를 듣기 전에 나갔다")

        await harness.model.session.signOut()
        await harness.model.session.signIn(email: "games@aing.invalid", password: "pw")
        #expect(await baseWaitUntil { submits(harness).count == 1 }, "앞 로그인의 깃발에 막혀 다음 로그인이 공개 여부를 못 물었다")
        #expect(submits(harness).first?.contains("tok-relogin") == true)
        #expect(await hold.releaseAndWaitDelivered())
        await harness.barrier()
        #expect(submits(harness).count == 1, "늦게 온 앞 조회가 한 번 더 보냈다: \(submits(harness))")
        await harness.tearDown()
    }

    // MARK: - 코어 타입

    @Test("코어 타입: 영속 형식은 맥 0.3.39 그대로다 · 백오프와 타이머 칸은 저장하지 않는다")
    func theStoredShapeStaysTheSame() throws {
        var pending = MiniGamePendingSubmit(id: UUID(), kind: .crossy, score: 1, token: "t", tokenIssuedAt: Date(timeIntervalSince1970: 100),
                                            recordedAt: Date(timeIntervalSince1970: 200), attempts: 2)
        pending.nextRetryAt = Date(timeIntervalSince1970: 300)
        pending.heldUntilTrigger = true
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(pending)) as? [String: Any])
        #expect(Set(object.keys) == ["id", "kind", "score", "token", "tokenIssuedAt", "recordedAt", "attempts", "recoveredFromDeadTokenOnce"])
        let back = try JSONDecoder().decode(MiniGamePendingSubmit.self, from: JSONEncoder().encode(pending))
        #expect(back.nextRetryAt == nil && !back.heldUntilTrigger, "재시작은 그 자체가 재시도 방아쇠다")
        #expect(back.attempts == 2, "재시작이 백오프를 0 으로 되돌렸다")
    }

    @Test("코어 타입: 다음에 할 일 — 토큰을 실은 인편이 앞 · 백오프·붙듦이면 **새 토큰도 청하지 않는다**")
    func theNextStepKeepsTheInvariant() {
        let now = Date(timeIntervalSince1970: 1000)
        let carrying = MiniGamePendingSubmit(id: UUID(), kind: .flappy, score: 1, token: "a", tokenIssuedAt: now, recordedAt: now, attempts: 0)
        let waiting = MiniGamePendingSubmit(id: UUID(), kind: .flappy, score: 2, token: nil, tokenIssuedAt: nil, recordedAt: now, attempts: 0)
        #expect([waiting, carrying].nextStep(for: .flappy, at: now) == .submit(carrying), "토큰을 실은 인편이 먼저다")
        #expect([waiting].nextStep(for: .flappy, at: now) == .requestToken)
        #expect([waiting].nextStep(for: .tetris, at: now) == .wait, "다른 게임의 인편으로 움직였다")

        var backingOff = carrying
        backingOff.noteFailure(delays: MiniGameSubmitRules.retryDelays, at: now)
        #expect(backingOff.nextRetryAt == now.addingTimeInterval(2))
        #expect([waiting, backingOff].nextStep(for: .flappy, at: now) == .wait, "살아 있는 토큰이 있는데 토큰을 청했다")
        #expect([backingOff].nextStep(for: .flappy, at: now.addingTimeInterval(2)) == .submit(backingOff))

        var held = carrying
        held.heldUntilTrigger = true
        #expect([held].nextStep(for: .flappy, at: now) == .wait)

        var repeated = carrying
        for _ in 0..<5 { repeated.noteFailure(delays: MiniGameSubmitRules.retryDelays, at: now) }
        #expect(repeated.nextRetryAt == now.addingTimeInterval(30), "끝을 넘기면 마지막 값을 반복한다")

        // 수명은 토큰 발급과 판 끝 중 **이른 쪽**에서 센다.
        var old = waiting
        old.adopt(token: "b", at: now.addingTimeInterval(100))
        #expect(old.deadline(ttl: 60) == now.addingTimeInterval(60))
        old.demoteToTokenWait()
        #expect(old.token == nil && old.recoveredFromDeadTokenOnce && old.attempts == 0)
    }

    @Test("status 분류: 되보낼 것과 영영 못 올릴 것은 서로소 · 죽은 토큰은 terminal 의 부분집합 · `token_used` 는 어느 쪽도 아니다")
    func theStatusSetsStayConsistent() {
        #expect(MiniGameSubmitRules.retryableStatuses.isDisjoint(with: MiniGameSubmitRules.terminalStatuses))
        #expect(MiniGameSubmitRules.deadTokenStatuses.isSubset(of: MiniGameSubmitRules.terminalStatuses))
        #expect(!MiniGameSubmitRules.terminalStatuses.contains("token_used"))
        #expect(MiniGameSubmitRules.retryableStatuses == ["too_fast"])
        #expect(MiniGameSubmitRules.retryDelays == [2, 8, 30])
        #expect(MiniGameSubmitRules.pendingTTL == 30 * 60, "서버 `minigame_round_ttl()` 과 같아야 한다")
    }
}

// MARK: - 길건너 긴 판

@Suite("폰 길건너 — 판 도중 토큰 갈아 끼우기")
@MainActor
struct GamesCrossyMidRunTokenTests {
    private static let ok = #"{"status":"ok","best_score":55,"plays":4,"improved":true}"#
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func configure(_ harness: GamesHarness) {
        harness.server.setDefault("minigame_board", json: "[]")
        harness.server.setDefault("minigame_yesterday_winner", json: "[]")
        harness.server.setDefault("/rest/v1/profiles", json: #"[{"minigame_public":true}]"#)
        harness.server.setDefault("minigame_submit_score", json: Self.ok)
    }

    /// 판을 시작하고 첫 틱으로 감시 기준을 잡는다. 틱 간격이 커도 엔진은 `maxStep` 으로 잘려 판이 죽지 않는다.
    private func startCrossy(_ harness: GamesHarness, prefix: String) async throws -> (GamesPlayController, BaseLockedBox<[String]>) {
        let tokens = gamesServeRoundTokens(harness, prefix: prefix)
        await harness.signIn()
        harness.hub.openScreen(.crossy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "\(prefix)-1" })
        let controller = try #require(harness.hub.controller)
        controller.tap()
        #expect(controller.isPlaying)
        controller.tick(at: start)
        return (controller, tokens)
    }

    @Test("20분 묵은 토큰을 판이 도는 중에 갈아 끼운다 — 전에는 안 받고, 끝난 판은 **새 토큰**으로 나간다")
    func aLongRoundRefreshesItsToken() async throws {
        let harness = GamesHarness(label: "crossy-midrun")
        configure(harness)
        let (controller, tokens) = try await startCrossy(harness, prefix: "tok-mid")

        // 19분: 감시가 돌아도 안 받는다(젊다).
        harness.clock.advance(19 * 60)
        controller.tick(at: start.addingTimeInterval(31))
        await harness.barrier()
        #expect(tokens.get() == ["tok-mid-1"], "아직 젊은 토큰을 갈아 끼웠다 — 서버 하한이 다시 잰다")

        // 20분: 갈아 끼운다.
        harness.clock.advance(60)
        controller.tick(at: start.addingTimeInterval(62))
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-mid-2" }, "\(tokens.get())")

        #expect(controller.endRound() == .confirmed(controller.score))
        #expect(await baseWaitUntil { harness.server.requests("minigame_submit_score").count == 1 })
        let sent = try #require(harness.server.requests("minigame_submit_score").first)
        #expect(sent.bodyText.contains("tok-mid-2"), "죽은 옛 토큰으로 제출했다: \(sent.bodyText)")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("감시는 30초에 한 번이다 — 프레임마다 묻지 않는다 · 왕복 중이면 또 안 보낸다")
    func theKeeperRunsEveryThirtySeconds() async throws {
        let harness = GamesHarness(label: "crossy-keeper")
        configure(harness)
        let (controller, tokens) = try await startCrossy(harness, prefix: "tok-tick")
        harness.clock.advance(21 * 60)
        // 30초 안의 틱은 몇 번이든 아무 일도 없다.
        for frame in 1...120 { controller.tick(at: start.addingTimeInterval(Double(frame) * 0.2)) }
        await harness.barrier()
        #expect(tokens.get() == ["tok-tick-1"], "30초가 안 됐는데 감시가 돌았다")

        let hold = BaseHold.rpc("minigame_start_round", host: harness.server.host)
        controller.tick(at: start.addingTimeInterval(30))
        #expect(await hold.waitHeld())
        controller.tick(at: start.addingTimeInterval(61))
        await harness.barrier()
        // 붙잡은 것 말고 스텁에 닿은 요청이 없어야 한다.
        #expect(tokens.get() == ["tok-tick-1"], "왕복 중인데 또 요청했다 — 앞 요청의 응답이 버려진다")
        #expect(await hold.releaseAndWaitDelivered())
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-tick-2" })
        await harness.tearDown()
    }

    @Test("★ 갈아 끼우는 왕복 중에 끝난 판도, 갈아 끼운 직후의 `too_fast` 도 **같은 새 토큰으로** 통과한다")
    func aRoundThatEndsRightAfterTheSwapStillGetsThrough() async throws {
        let harness = GamesHarness(label: "crossy-midrun-race")
        configure(harness)
        harness.server.enqueue("minigame_submit_score") { _ in .json(#"{"status":"too_fast","need_seconds":450,"elapsed_seconds":1}"#) }
        harness.server.enqueue("minigame_submit_score") { _ in .json(#"{"status":"too_fast","need_seconds":450,"elapsed_seconds":3}"#) }
        harness.server.enqueue("minigame_submit_score") { _ in .json(#"{"status":"too_fast","need_seconds":450,"elapsed_seconds":11}"#) }
        harness.server.enqueue("minigame_submit_score") { _ in .json(#"{"status":"too_fast","need_seconds":450,"elapsed_seconds":41}"#) }
        let delays = BaseLockedBox<[TimeInterval]>([])
        harness.hub.sleep = { seconds in delays.mutate { $0.append(seconds) } }
        let (controller, tokens) = try await startCrossy(harness, prefix: "tok-race")
        harness.clock.advance(21 * 60)

        let hold = BaseHold.rpc("minigame_start_round", host: harness.server.host)
        controller.tick(at: start.addingTimeInterval(31))
        #expect(await hold.waitHeld())
        // 왕복 중에 판이 끝났다 — 토큰 칸이 비어 있다. 옛 토큰은 그 요청이 닿는 순간 죽었으니 잡을 것은 새 토큰뿐이다.
        _ = controller.endRound()
        #expect(harness.hub.pendingSubmit?.token == nil)
        #expect(harness.hub.submitNotice == GamesMiniGameText.submitRetrying, "살아 있는 점수를 못 올렸다고 말했다")
        #expect(await hold.releaseAndWaitDelivered())

        #expect(await baseWaitUntil { harness.hub.pendingSubmit == nil }, "\(delays.get())")
        let sent = harness.server.requests("minigame_submit_score").map(\.bodyText)
        #expect(sent.count == 5, "폰 옛 재시도 [1.5, 4] 는 세 번에서 포기했다: \(sent.count)")
        #expect(sent.allSatisfy { $0.contains("tok-race-2") }, "\(sent)")
        #expect(delays.get().prefix(4) == [2, 8, 30, 30], "\(delays.get())")
        // 인편이 살아 있는 동안 새 토큰이 나가지 않았다(마지막 하나는 인편이 비워진 뒤의 선발급이다).
        #expect(tokens.get().count <= 3, "\(tokens.get())")
        await harness.tearDown()
    }

    @Test("길건너가 아닌 게임은 판 도중에 토큰을 안 갈아 끼운다 · 판이 끝나면 감시가 멈춘다")
    func onlyCrossyKeepsItsToken() async throws {
        let harness = GamesHarness(label: "crossy-keeper-others")
        configure(harness)
        let tokens = gamesServeRoundTokens(harness, prefix: "tok-oth")
        await harness.signIn()
        harness.hub.openScreen(.tetris)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-oth-1" })
        let controller = try #require(harness.hub.controller)
        controller.tap()
        harness.clock.advance(11 * 60)
        controller.tick(at: start)
        controller.tick(at: start.addingTimeInterval(31))
        controller.tick(at: start.addingTimeInterval(62))
        harness.hub.keepRoundTokenFresh(kind: .tetris)
        await harness.barrier()
        #expect(tokens.get() == ["tok-oth-1"], "테트리스 판 도중에 토큰을 갈아 끼웠다")
        await harness.tearDown()

        // 끝난 판에는 감시가 없다.
        let crossy = GamesPlayController(kind: .crossy, seed: 3)
        var calls = 0
        crossy.onRoundKeepAlive = { calls += 1 }
        crossy.tap()
        crossy.tick(at: start)
        crossy.tick(at: start.addingTimeInterval(30))
        #expect(calls == 1)
        _ = crossy.endRound()
        crossy.tick(at: start.addingTimeInterval(60))
        crossy.tick(at: start.addingTimeInterval(90))
        #expect(calls == 1, "끝난 판에서 감시가 돌았다")
        // 새 판은 기준을 새로 잡는다(앞 판의 시각을 물려받지 않는다).
        crossy.tap()
        crossy.tick(at: start.addingTimeInterval(1000))
        #expect(calls == 1, "새 판 첫 틱에 감시가 돌았다")
    }
}
