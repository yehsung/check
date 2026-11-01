@testable import CheckCore
import CheckMobileShared
import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 미니게임 일시정지(맥 v0.2.48 → 폰 1.0.16). 맥 쪽 짝은 `Tests/checkTests/V0362MiniGamePauseOnResignTests.swift`.
//
// 사용자 답(2026-11-01): '폰 미니게임에 일시정지를 넣을까요?' → "넣기" · '폰 플래피를 접었을 때 그 점수를 기록할까요?' → "지금처럼 버림".
//
// ⚠️ 하네스 시계는 안 흐른다. 시간은 `clock.advance` 로만 흐르고, 3-2-1 · 감시 Task 는 `pauseSleep` 을 문 앞에 세워 멈춘 뒤
//    `advanceResumeCountdown` · `pauseWatchTick` 을 직접 부른다(실제 1초를 기다리지 않는다).

@Suite("폰 미니게임 일시정지")
@MainActor
struct GamesMiniGamePauseTests {
    private static let ok = #"{"status":"ok","best_score":55,"plays":4,"improved":true}"#
    private static let start = MobileClock.demoInstant
    private static let limit = TimeInterval(MiniGamePauseState.pauseLimitSeconds)

    private func configure(_ harness: GamesHarness, isPublic: Bool = true) {
        harness.server.setDefault("minigame_board", json: "[]")
        harness.server.setDefault("minigame_yesterday_winner", json: "[]")
        harness.server.setDefault("/rest/v1/profiles", json: #"[{"minigame_public":\#(isPublic)}]"#)
        harness.server.setDefault("minigame_submit_score", json: Self.ok)
    }

    private func submits(_ harness: GamesHarness) -> [String] {
        harness.server.requests("minigame_submit_score").map(\.bodyText)
    }

    private func draftData(_ harness: GamesHarness) -> Data? {
        harness.storage.defaults.data(forKey: GamesMiniGameHub.pauseDraftKey(userID: GamesHarness.userID))
    }

    private func draft(_ harness: GamesHarness) throws -> MiniGamePendingSubmit? {
        guard let data = draftData(harness) else { return nil }
        return try JSONDecoder().decode(MiniGamePendingSubmit.self, from: data)
    }

    /// 3-2-1 · 감시 Task 를 문 앞에 세운다(돌아오지 않는다 — 시험이 직접 민다).
    @discardableResult
    private func parkPause(_ harness: GamesHarness) -> BaseGate {
        let gate = BaseGate()
        harness.hub.pauseSleep = { _ in await gate.wait() }
        return gate
    }

    /// 로그인 → 화면 열기 → 토큰 → 판 시작. 테트리스·길건너는 점수가 있는 판으로 만든다.
    private func startRound(_ harness: GamesHarness, _ kind: MiniGameKind, tokenPrefix: String = "tok",
                            isPublic: Bool = true) async throws -> GamesPlayController {
        configure(harness, isPublic: isPublic)
        gamesServeRoundTokens(harness, prefix: tokenPrefix)
        parkPause(harness)
        await harness.signIn()
        harness.hub.openScreen(kind)
        if isPublic {
            #expect(await baseWaitUntil { harness.hub.roundToken == "\(tokenPrefix)-1" })
        } else {
            #expect(await baseWaitUntil { !harness.hub.isPublic })
        }
        let controller = try #require(harness.hub.controller)
        controller.tap()
        switch kind {
        case .tetris:
            for _ in 0..<7 { controller.softDropOneCell() }
        case .crossy:
            gamesDrive(controller, from: harness.clock.now, frames: 30)
            #expect(controller.score >= 1, "전제: 점수가 올라 있다")
        case .flappy, .timingBar:
            gamesDrive(controller, from: harness.clock.now, frames: 6)
        }
        #expect(controller.isPlaying, "전제: 판이 돈다")
        return controller
    }

    // MARK: - 코어 전이

    @Test("전이 표: 수동 · 자동 · 3-2-1 — 자동 정지는 절대 풀지 않는다")
    func theTransitionTable() {
        typealias Pause = MiniGamePauseState
        #expect(Pause.countdownStart == 3)
        #expect(Pause.pauseLimitSeconds == 5 * 60)
        // 수동: 도는 판 → 카드 → 3 → (취소) 카드. 판이 안 돌면 얼지 않는다.
        #expect(Pause.none.toggled(isPlaying: true) == .paused)
        #expect(Pause.none.toggled(isPlaying: false) == .none)
        #expect(Pause.paused.toggled(isPlaying: true) == .resuming(3))
        #expect(Pause.resuming(2).toggled(isPlaying: true) == .paused)
        // 자동: 언제나 '언다'. 이미 카드면 아무 일도 없다(그래야 시계가 안 되돌아간다), 3-2-1 이면 취소.
        #expect(Pause.none.resigningKey(isPlaying: true) == .paused)
        #expect(Pause.paused.resigningKey(isPlaying: true) == nil)
        #expect(Pause.resuming(1).resigningKey(isPlaying: true) == .paused)
        #expect(Pause.none.resigningKey(isPlaying: false) == nil)
        // 3 → 2 → 1 → 풀림.
        #expect(Pause.resuming(3).steppedDown() == .resuming(2))
        #expect(Pause.resuming(1).steppedDown() == .none)
        #expect(Pause.paused.steppedDown() == .paused)
        // 화면이 분기하는 값.
        #expect(Pause.paused.showsCard && Pause.paused.isFrozen && Pause.paused.countdown == nil)
        #expect(!Pause.resuming(2).showsCard && Pause.resuming(2).isFrozen && Pause.resuming(2).countdown == 2)
        #expect(!Pause.none.showsCard && !Pause.none.isFrozen && Pause.none.countdown == nil)
    }

    // MARK: - 구동기: 얼어 있는 판

    @Test("얼어 있으면 모든 입력이 판에 안 닿는다(게임 넷 · 탭 · 끌기 · 버튼)", arguments: MiniGameKind.phoneCases)
    func everyInputIsDeadWhileFrozen(kind: MiniGameKind) {
        let controller = GamesPlayController(kind: kind, seed: 21)
        controller.tap()
        gamesDrive(controller, from: Self.start, frames: 6)
        controller.setPauseState(.paused)
        let timing = controller.timing, flappy = controller.flappy, tetris = controller.tetris, crossy = controller.crossy
        let serial = controller.tapSerial

        controller.tap()
        controller.rotate(clockwise: true)
        controller.hold()
        controller.hardDrop()
        controller.moveLeftOneCell()
        controller.moveRightOneCell()
        controller.softDropOneCell()
        controller.hopCrossy(.forward)
        controller.canvasDragChanged(startLocation: .zero, translation: CGSize(width: 200, height: 0), at: Self.start)
        #expect(controller.canvasDragEnded(translation: .zero, at: Self.start) == false)

        #expect(controller.timing == timing && controller.flappy == flappy, "\(kind): 얼어 있는 판이 입력을 받았다")
        #expect(controller.tetris == tetris && controller.crossy == crossy, "\(kind): 얼어 있는 판이 입력을 받았다")
        #expect(controller.tapSerial == serial, "\(kind): 정지 중 햅틱이 울린다")
    }

    @Test("얼어 있는 동안 프레임이 와도 판이 안 움직이고, 풀린 첫 프레임은 **기준만 잡는다**", arguments: MiniGameKind.phoneCases)
    func theFirstFrameAfterThawingOnlySetsTheBase(kind: MiniGameKind) {
        let controller = GamesPlayController(kind: kind, seed: 22)
        controller.tap()
        var now = gamesDrive(controller, from: Self.start, frames: 6)
        controller.setPauseState(.paused)
        let frozen = (controller.timing, controller.flappy, controller.tetris, controller.crossy)
        now = now.addingTimeInterval(120)
        controller.tick(at: now)
        controller.setPauseState(.resuming(1))
        now = now.addingTimeInterval(1)
        controller.tick(at: now)
        controller.setPauseState(.none)

        now = now.addingTimeInterval(120)
        controller.tick(at: now)   // 풀린 첫 프레임: 그 사이 120초는 dt 가 아니다.
        #expect(controller.timing == frozen.0 && controller.flappy == frozen.1, "\(kind): 멈춘 시간을 물려받았다")
        #expect(controller.tetris == frozen.2 && controller.crossy == frozen.3, "\(kind): 멈춘 시간을 물려받았다")

        controller.tick(at: now.addingTimeInterval(1.0 / 60.0))
        let moved = controller.timing != frozen.0 || controller.flappy != frozen.1
            || controller.tetris != frozen.2 || controller.crossy != frozen.3
        #expect(moved, "\(kind): 풀렸는데 판이 안 돈다")
    }

    @Test("길건너 idleLimit 은 정지 시간을 안 센다 — 8초 서 있다 1분 멈춰도 안 죽는다")
    func crossyIdleLimitIgnoresThePause() {
        let controller = GamesPlayController(kind: .crossy, seed: 23)
        controller.tap()
        // 뛰기가 끝난 뒤부터 8초를 가만히 서 있는다(9초면 끝이다).
        var now = gamesDrive(controller, from: Self.start, frames: 8 * 60)
        #expect(controller.crossy.phase == .running, "전제: 아직 산다")
        controller.setPauseState(.paused)
        now = now.addingTimeInterval(60)
        controller.tick(at: now)
        controller.setPauseState(.none)
        controller.tick(at: now)
        #expect(controller.crossy.phase == .running, "정지 시간이 idleLimit 에 들어갔다")
        gamesDrive(controller, from: now, frames: 3 * 60)
        #expect(controller.crossy.phase != .running, "대조: 정지를 빼고 9초를 넘기면 끝나야 한다 — 이 시험이 아무것도 못 잰다")
    }

    @Test("테트리스 15분 상한은 **정지도 함께 센다** — 토큰 예산이지 게임 시간이 아니다(12 + 15 + 1 = 28 < 30)")
    func theTetrisRoundLimitKeepsCountingThroughAPause() {
        let controller = GamesPlayController(kind: .tetris, seed: 24)
        var finished: [Int] = []
        controller.onFinished = { finished.append($0) }
        controller.roundLimitSeconds = GamesMiniGameHub.tetrisRoundLimitSeconds
        controller.tap()
        let first = Self.start
        controller.tick(at: first)
        controller.setPauseState(.paused)
        controller.tick(at: first.addingTimeInterval(5 * 60))
        controller.setPauseState(.none)
        controller.tick(at: first.addingTimeInterval(14 * 60))
        #expect(controller.isPlaying, "상한 전인데 끝났다")
        controller.tick(at: first.addingTimeInterval(15 * 60))
        #expect(!controller.isPlaying, "정지를 빼 줬다 — 고의로 늘인 판 + 정지 5분이 33분이 되어 통째로 거절된다")
        #expect(finished.count == 1)
    }

    @Test("얼리는 순간 눌린 키와 끌기를 놓는다 — 풀린 뒤 첫 조각이 튀지 않는다")
    func freezingReleasesGestureAndKeys() {
        let controller = GamesPlayController(kind: .tetris, seed: 25)
        controller.updateCellWidth(20)
        controller.tap()
        let column = controller.tetris.active?.column
        // 접촉이 소비량을 쌓은 채로 언다.
        controller.canvasDragChanged(startLocation: .zero, translation: CGSize(width: 40, height: 0), at: Self.start)
        let moved = controller.tetris.active?.column
        #expect(moved != column, "전제: 끌기가 먹었다")
        controller.setPauseState(.paused)
        controller.setPauseState(.none)
        // 같은 시작점의 다음 프레임: 트래커가 비었으므로 새 접촉처럼 0 부터 잰다 — 작은 이동은 안 움직인다.
        controller.canvasDragChanged(startLocation: CGPoint(x: 1, y: 1), translation: CGSize(width: 1, height: 0), at: Self.start)
        #expect(controller.tetris.active?.column == moved, "앞 끌기의 소비량이 풀린 뒤로 샜다")
    }

    // MARK: - 게임별 표 ([그만두기] · 뒤로 · 상한)

    @Test("표: 정책이 엔진과 맞는다 — 플래피·타이밍 바는 버림, 테트리스·길건너는 확정", arguments: MiniGameKind.phoneCases)
    func thePolicyMatchesWhatEndRoundActuallyDoes(kind: MiniGameKind) {
        let controller = GamesPlayController(kind: kind, seed: 26)
        var finished: [Int] = []
        controller.onFinished = { finished.append($0) }
        controller.tap()
        gamesDrive(controller, from: Self.start, frames: 6)
        let score = controller.score
        let outcome = controller.endRound()
        if GamesMiniGamePausePolicy.quittingKeepsTheScore(kind) {
            #expect(outcome == .confirmed(score), "\(kind)")
            #expect(finished == [score], "\(kind)")
        } else {
            #expect(outcome == .abandoned, "\(kind)")
            #expect(finished.isEmpty, "\(kind): 버리는 게임이 알렸다")
        }
        #expect(GamesMiniGamePausePolicy.capApplies(kind) == GamesMiniGamePausePolicy.quittingKeepsTheScore(kind),
                "\(kind): 상한은 접어도 남는 게임에만 건다")
        #expect(controller.pauseState == .none)
    }

    @Test("표: 게임별 값을 글자로 못 박는다 — 플래피가 맥과 다른 유일한 칸이다")
    func theTableIsSpelledOut() {
        #expect(GamesMiniGamePausePolicy.capApplies(.tetris))
        #expect(GamesMiniGamePausePolicy.capApplies(.crossy))
        #expect(!GamesMiniGamePausePolicy.capApplies(.flappy), "사용자 답 '지금처럼 버림' — 안 남는 게임에 상한을 걸면 판을 없앤다")
        #expect(!GamesMiniGamePausePolicy.capApplies(.timingBar))
    }

    @Test("[그만두기]: 테트리스·길건너는 그 점수로 **한 번** 제출, 화면은 그대로 · 플래피·타이밍 바는 제출 없음 · 토큰 유지", arguments: MiniGameKind.phoneCases)
    func quittingFollowsTheTable(kind: MiniGameKind) async throws {
        let harness = GamesHarness(label: "pause-quit-\(kind.rawValue)")
        let controller = try await startRound(harness, kind)
        let score = controller.score
        harness.hub.togglePause()
        #expect(controller.pauseState == .paused)

        harness.hub.quitPausedRound()
        #expect(!controller.isPlaying)
        #expect(controller.pauseState == .none)
        #expect(harness.hub.activeKind == kind, "[그만두기] 가 화면을 닫았다")
        if GamesMiniGamePausePolicy.quittingKeepsTheScore(kind) {
            #expect(await baseWaitUntil { submits(harness).count == 1 })
            #expect(submits(harness)[0].contains(#""p_score":\#(score)"#))
        } else {
            await harness.barrier()
            #expect(submits(harness).isEmpty, "\(kind): 버리는 게임이 제출했다")
            #expect(harness.hub.roundToken == "tok-1", "\(kind): 쓰지 않은 토큰은 다음 판에 쓴다")
        }
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()
    }

    @Test("정지 중 뒤로 가기는 [그만두기]와 같다", arguments: MiniGameKind.phoneCases)
    func goingBackWhilePausedEqualsQuitting(kind: MiniGameKind) async throws {
        let harness = GamesHarness(label: "pause-back-\(kind.rawValue)")
        let controller = try await startRound(harness, kind)
        let score = controller.score
        harness.model.sceneDidEnterBackground()
        harness.model.sceneDidBecomeActive()
        harness.hub.closeScreen(kind)
        #expect(harness.hub.controller == nil)
        #expect(try draft(harness) == nil, "임시 항목이 남았다 — 다음 실행에 같은 판이 또 올라간다")
        if GamesMiniGamePausePolicy.quittingKeepsTheScore(kind) {
            #expect(await baseWaitUntil { submits(harness).count == 1 })
            #expect(submits(harness)[0].contains(#""p_score":\#(score)"#))
        } else {
            await harness.barrier()
            #expect(submits(harness).isEmpty, "\(kind): 버리는 게임이 제출했다")
        }
        await harness.tearDown()
    }

    @Test("정지 중 다른 게임 화면이 열려도(딥링크 · 판 전환) [그만두기]와 같다 — 옛 화면의 퇴장이 나중에 와도 판이 안 사라진다", arguments: MiniGameKind.phoneCases)
    func openingAnotherGameWhilePausedEqualsQuitting(kind: MiniGameKind) async throws {
        let harness = GamesHarness(label: "pause-switch-\(kind.rawValue)")
        let controller = try await startRound(harness, kind)
        let score = controller.score
        harness.hub.togglePause()
        let other: MiniGameKind = kind == .tetris ? .flappy : .tetris
        harness.hub.openScreen(other)
        harness.hub.closeScreen(kind)   // 옛 화면의 onDisappear 가 뒤늦게 온다 — 아무 일도 없어야 한다.
        #expect(harness.hub.activeKind == other)
        #expect(try draft(harness) == nil)
        if GamesMiniGamePausePolicy.quittingKeepsTheScore(kind) {
            #expect(await baseWaitUntil { submits(harness).count == 1 }, "\(kind): 사람이 쌓은 판이 경합 정리에 사라졌다")
            #expect(submits(harness)[0].contains(#""p_score":\#(score)"#))
            #expect(submits(harness)[0].contains(#""p_game":"\#(kind.rawValue)""#))
        } else {
            await harness.barrier()
            #expect(submits(harness).isEmpty, "\(kind): 버리는 게임이 제출했다")
        }
        await harness.tearDown()
    }

    @Test("로그아웃은 abandon 그대로 — 제출도 임시 항목도 안 남는다")
    func signingOutAbandonsAndClearsTheDraft() async throws {
        let harness = GamesHarness(label: "pause-logout")
        let controller = try await startRound(harness, .tetris)
        harness.model.sceneDidEnterBackground()
        #expect(draftData(harness) != nil)
        await harness.model.session.signOut()
        #expect(!controller.isPlaying)
        #expect(controller.pauseState == .none)
        #expect(draftData(harness) == nil, "로그아웃했는데 임시 항목이 남았다 — 같은 계정이 돌아오면 버린 판이 올라간다")
        await harness.barrier()
        #expect(submits(harness).isEmpty, "남의 계정으로 넘어가는 자리에서 제출했다")
        await harness.tearDown()
    }

    @Test("계정 삭제 정리에 임시 항목이 든다")
    func forgettingAnAccountRemovesTheDraft() {
        let defaults = BaseStub.makeStorage().defaults
        let key = GamesMiniGameHub.pauseDraftKey(userID: "u-gone")
        defaults.set(Data([1]), forKey: key)
        GamesMiniGameHub.forgetPendingSubmits(userID: "U-GONE", in: defaults)
        #expect(defaults.data(forKey: key) == nil)
    }

    // MARK: - 벽시계 상한

    @Test("상한은 벽시계다: 백그라운드 4분 → 복귀 → 카드 2분이면 끝 · 넘기 전에는 안 끝난다")
    func theCapCountsBackgroundTime() async throws {
        let harness = GamesHarness(label: "pause-wall")
        let controller = try await startRound(harness, .tetris)
        let score = controller.score
        harness.model.sceneDidEnterBackground()
        harness.clock.advance(4 * 60)
        harness.model.sceneDidBecomeActive()
        #expect(controller.pauseState == .paused, "복귀가 판을 저절로 풀었다")
        #expect(harness.hub.pausedSecondsUsed == 4 * 60)

        harness.clock.advance(59)
        harness.hub.pauseWatchTick()
        #expect(controller.isPlaying, "5분 전에 끝났다")

        harness.clock.advance(61)
        harness.hub.pauseWatchTick()
        #expect(!controller.isPlaying, "상한을 넘겼는데 안 끝난다")
        #expect(controller.pauseState == .none)
        #expect(harness.hub.submitNotice == GamesMiniGameText.pauseCapEnded)
        #expect(await baseWaitUntil { submits(harness).count == 1 })
        #expect(submits(harness)[0].contains(#""p_score":\#(score)"#))
        await harness.tearDown()
    }

    @Test("상한: 나가 있는 동안 넘겼으면 **돌아오는 그 순간** 끝난다(복귀 판정)", arguments: [MiniGameKind.tetris, .crossy])
    func theCapIsCheckedOnTheWayBack(kind: MiniGameKind) async throws {
        let harness = GamesHarness(label: "pause-return-\(kind.rawValue)")
        let controller = try await startRound(harness, kind)
        harness.model.sceneDidEnterBackground()
        harness.clock.advance(Self.limit + 1)
        harness.hub.pauseWatchTick()
        #expect(controller.isPlaying, "background 에서 도는 감시가 판을 끝냈다 — 복귀가 판정해야 한다")
        harness.model.sceneDidBecomeActive()
        #expect(!controller.isPlaying)
        #expect(harness.hub.submitNotice == GamesMiniGameText.pauseCapEnded)
        #expect(await baseWaitUntil { submits(harness).count == 1 })
        #expect(try draft(harness) == nil, "진짜 인편이 섰는데 임시 항목이 남았다")
        await harness.tearDown()
    }

    @Test("상한: inactive 에서 돌아와도 잰다(background 를 안 거친 복귀)")
    func theCapIsCheckedComingBackFromInactive() async throws {
        let harness = GamesHarness(label: "pause-inactive-cap")
        let controller = try await startRound(harness, .tetris)
        harness.model.sceneWillResignActive()
        #expect(controller.pauseState == .paused)
        harness.clock.advance(Self.limit)
        harness.model.sceneDidBecomeActive()
        #expect(!controller.isPlaying)
        await harness.tearDown()
    }

    @Test("상한: 재정지를 되풀이해도 시계가 안 되돌아간다 — 판 단위 누적이고 3-2-1 도 든다")
    func repeatedPausesNeverRewindTheClock() async throws {
        let harness = GamesHarness(label: "pause-repeat")
        let controller = try await startRound(harness, .crossy)
        for round in 1...2 {
            harness.hub.togglePause()
            #expect(controller.pauseState == .paused)
            harness.clock.advance(2 * 60)
            harness.hub.pauseWatchTick()
            harness.hub.togglePause()   // [이어하기]
            #expect(harness.hub.advanceResumeCountdown())
            #expect(harness.hub.advanceResumeCountdown())
            #expect(!harness.hub.advanceResumeCountdown())
            #expect(controller.pauseState == .none, "\(round)")
        }
        #expect(harness.hub.pausedSecondsUsed == 4 * 60)

        // 카드 ↔ 3-2-1 만 오가도 찬다: 맥처럼 3-2-1 을 안 세면 이 왕복으로 영영 안 찬다.
        harness.hub.togglePause()
        for _ in 0..<20 {
            harness.hub.togglePause()   // 3-2-1
            harness.clock.advance(3)
            guard controller.isPlaying else { break }
            harness.hub.togglePause()   // 취소
        }
        #expect(!controller.isPlaying, "왕복으로 상한을 피했다: \(harness.hub.pausedSecondsUsed)초")
        await harness.tearDown()
    }

    @Test("상한: 이미 넘긴 판은 [이어하기] 가 안 풀어 준다 · 정지 버튼을 또 눌러도 그 자리에서 끝난다")
    func anOverdueRoundDoesNotThaw() async throws {
        let harness = GamesHarness(label: "pause-overdue")
        let controller = try await startRound(harness, .tetris)
        harness.hub.togglePause()
        harness.clock.advance(Self.limit + 1)
        harness.hub.togglePause()
        #expect(!controller.isPlaying, "상한을 넘긴 판이 풀렸다")
        await harness.tearDown()
    }

    @Test("상한 없음: 플래피·타이밍 바는 10분을 멈춰도 그대로다 — 돌아와 이어 할 수 있다", arguments: [MiniGameKind.flappy, .timingBar])
    func noCapForTheGamesThatDiscard(kind: MiniGameKind) async throws {
        let harness = GamesHarness(label: "pause-nocap-\(kind.rawValue)")
        let controller = try await startRound(harness, kind)
        harness.model.sceneDidEnterBackground()
        harness.clock.advance(10 * 60)
        harness.model.sceneDidBecomeActive()
        harness.hub.pauseWatchTick()
        #expect(controller.isPlaying, "\(kind): 상한이 판을 없앴다")
        #expect(controller.pauseState == .paused)
        harness.hub.togglePause()
        #expect(harness.hub.advanceResumeCountdown())
        #expect(harness.hub.advanceResumeCountdown())
        #expect(!harness.hub.advanceResumeCountdown())
        #expect(controller.pauseState == .none)
        #expect(controller.isPlaying)
        await harness.barrier()
        #expect(submits(harness).isEmpty)
        await harness.tearDown()
    }

    @Test("새 판은 시계가 0 이다")
    func aNewRoundStartsWithAFreshClock() async throws {
        let harness = GamesHarness(label: "pause-fresh")
        let controller = try await startRound(harness, .tetris)
        harness.hub.togglePause()
        harness.clock.advance(4 * 60)
        harness.hub.quitPausedRound()
        #expect(controller.tetris.phase == .result)
        #expect(harness.hub.pausedSecondsUsed == 0, "끝난 판의 시계가 남았다")
        controller.tap()   // 결과 → 새 판
        #expect(controller.isPlaying)
        harness.hub.togglePause()
        harness.clock.advance(4 * 60)
        harness.hub.pauseWatchTick()
        #expect(controller.isPlaying, "앞 판의 정지가 새 판 상한에 들어갔다")
        await harness.tearDown()
    }

    @Test("상한 문구는 토큰을 든 판에만 — 오래 나가 있어 토큰이 죽은 판은 '못 올렸어요'이고 제출도 없다")
    func anExpiredTokenIsToldTheTruthOnTheCap() async throws {
        let harness = GamesHarness(label: "pause-dead-cap")
        let controller = try await startRound(harness, .tetris)
        harness.model.sceneDidEnterBackground()
        harness.clock.advance(MiniGameSubmitRules.pendingTTL + 1)
        harness.model.sceneDidBecomeActive()
        #expect(!controller.isPlaying)
        #expect(harness.hub.submitNotice == GamesMiniGameText.submitTokenDead, "안 올라간 점수를 기록했다고 말했다")
        await harness.barrier()
        #expect(submits(harness).isEmpty, "죽은 토큰을 보냈다")
        #expect(harness.hub.localBest[.tetris] == 7, "로컬 최고는 올라야 한다")
        await harness.tearDown()
    }

    @Test("상한 없는 플래피가 30분 넘게 얼었다 끝나면 '이번 판은 순위에 못 올렸어요'로 끝난다")
    func aFlappyRoundFrozenPastTheTokenTTLIsToldTheTruth() async throws {
        let harness = GamesHarness(label: "pause-dead-flappy")
        let controller = try await startRound(harness, .flappy)
        harness.hub.togglePause()
        harness.clock.advance(MiniGameSubmitRules.pendingTTL + 1)
        harness.hub.togglePause()
        _ = harness.hub.advanceResumeCountdown()
        _ = harness.hub.advanceResumeCountdown()
        _ = harness.hub.advanceResumeCountdown()
        #expect(controller.pauseState == .none)
        gamesDrive(controller, from: harness.clock.now, frames: 60 * 20) { $0.flappy.phase == .result }
        #expect(controller.flappy.phase == .result, "전제: 판이 끝났다")
        #expect(harness.hub.submitNotice == GamesMiniGameText.submitTokenDead)
        await harness.barrier()
        #expect(submits(harness).isEmpty)
        await harness.tearDown()
    }

    @Test("토큰을 기다리는 판에 상한이 오면 '올리는 중'을 '기록했어요'로 덮지 않는다")
    func aTokenlessRoundKeepsTheRetryingNotice() async throws {
        let harness = GamesHarness(label: "pause-tokenless")
        configure(harness)
        parkPause(harness)
        harness.server.setDefault("minigame_start_round") { _ in .networkFailure() }
        let gate = BaseGate()
        harness.hub.sleep = { _ in await gate.wait() }
        await harness.signIn()
        harness.hub.openScreen(.tetris)
        await harness.barrier()
        #expect(await baseWaitUntil { harness.hub.roundTokenInFlightKind == nil })
        let controller = try #require(harness.hub.controller)
        controller.tap()
        controller.softDropOneCell()
        #expect(await baseWaitUntil { harness.hub.roundTokenInFlightKind == nil })
        harness.hub.togglePause()
        harness.clock.advance(Self.limit)
        harness.hub.pauseWatchTick()
        #expect(!controller.isPlaying)
        #expect(harness.hub.submitNotice == GamesMiniGameText.submitRetrying)
        #expect(harness.hub.pendingSubmit?.token == nil)
        gate.open()
        await harness.tearDown()
    }

    // MARK: - 자동 정지

    @Test("앱 내림: inactive 에서 이미 언다 · 이미 정지면 그대로 · 3-2-1 이면 취소 · 돌아와도 안 풀린다", arguments: MiniGameKind.phoneCases)
    func resigningFreezesAndNeverThaws(kind: MiniGameKind) async throws {
        let harness = GamesHarness(label: "pause-resign-\(kind.rawValue)")
        let controller = try await startRound(harness, kind)
        harness.model.sceneWillResignActive()
        #expect(controller.pauseState == .paused, "\(kind): 앱 전환기 스냅숏에 판이 찍힌다")
        harness.model.sceneDidBecomeActive()
        #expect(controller.pauseState == .paused, "\(kind): 복귀가 판을 저절로 풀었다")

        harness.clock.advance(30)
        harness.model.sceneWillResignActive()
        harness.model.sceneDidEnterBackground()
        harness.model.sceneDidBecomeActive()
        #expect(harness.hub.pausedSecondsUsed == 30, "\(kind): 이미 정지인데 시계가 되돌아갔다")

        harness.hub.togglePause()
        #expect(controller.pauseState == .resuming(3))
        harness.model.sceneDidEnterBackground()
        #expect(controller.pauseState == .paused, "\(kind): 안 보이는 화면에서 3-2-1 이 흐른다")
        harness.model.sceneDidBecomeActive()
        #expect(controller.pauseState == .paused)
        await harness.tearDown()
    }

    @Test("[일시정지]: 판이 안 돌면 안 언다 · 3-2-1 중 누르면 취소 · 다 내려가면 풀린다")
    func theManualButton() async throws {
        let harness = GamesHarness(label: "pause-manual")
        configure(harness)
        gamesServeRoundTokens(harness, prefix: "tok")
        parkPause(harness)
        await harness.signIn()
        harness.hub.openScreen(.flappy)
        let controller = try #require(harness.hub.controller)
        harness.hub.togglePause()
        #expect(controller.pauseState == .none, "시작 전 화면을 얼렸다 — 탭이 안 먹는 화면이 된다")
        controller.tap()
        harness.hub.togglePause()
        #expect(controller.pauseState == .paused)
        harness.hub.togglePause()
        #expect(controller.pauseState == .resuming(3))
        harness.hub.togglePause()
        #expect(controller.pauseState == .paused, "3-2-1 중 정지가 취소가 아니다")
        harness.hub.togglePause()
        #expect(harness.hub.advanceResumeCountdown())
        #expect(controller.pauseState == .resuming(2))
        #expect(controller.isFrozen, "3-2-1 동안 판이 풀렸다")
        #expect(harness.hub.advanceResumeCountdown())
        #expect(!harness.hub.advanceResumeCountdown())
        #expect(controller.pauseState == .none)
        await harness.tearDown()
    }

    @Test("3-2-1 Task 가 실제로 판을 푼다(직접 안 밀어도) — 1초 간격을 그대로 넘긴다")
    func theCountdownTaskThawsTheRound() async throws {
        let harness = GamesHarness(label: "pause-countdown-task")
        let controller = try await startRound(harness, .flappy)
        let waits = BaseLockedBox<[TimeInterval]>([])
        harness.hub.pauseSleep = { seconds in waits.mutate { $0.append(seconds) } }
        harness.hub.togglePause()
        harness.hub.togglePause()
        #expect(await baseWaitUntil { controller.pauseState == .none }, "3-2-1 이 안 끝난다")
        #expect(waits.get() == [1, 1, 1], "\(waits.get())")
        await harness.tearDown()
    }

    @Test("감시 Task 가 실제로 상한을 집행한다(테트리스) · 플래피에는 감시를 걸지도 않는다")
    func theWatchTaskEnforcesTheCap() async throws {
        let harness = GamesHarness(label: "pause-watch-task")
        let controller = try await startRound(harness, .tetris)
        let gate = BaseGate()
        harness.hub.pauseSleep = { _ in await gate.wait() }
        harness.hub.togglePause()
        harness.clock.advance(Self.limit)
        #expect(controller.isPlaying, "전제: 아직 감시가 안 돌았다")
        gate.open()
        #expect(await baseWaitUntil { !controller.isPlaying }, "감시가 상한을 집행하지 않는다")
        await harness.tearDown()

        let flappyHarness = GamesHarness(label: "pause-watch-flappy")
        _ = try await startRound(flappyHarness, .flappy)
        let calls = BaseLockedBox(0)
        flappyHarness.hub.pauseSleep = { _ in calls.mutate { $0 += 1 } }
        flappyHarness.hub.togglePause()
        await baseYield(turns: 40)
        #expect(calls.get() == 0, "할 일이 없는 게임에 1초 감시를 걸었다")
        await flappyHarness.tearDown()
    }

    @Test("화면 꺼짐 방지: 정지 중 해제 · 풀리면 다시")
    func theIdleTimerIsReleasedWhileFrozen() async throws {
        let harness = GamesHarness(label: "pause-idle")
        let controller = try await startRound(harness, .tetris)
        #expect(harness.games.wantsIdleTimerDisabled)
        harness.hub.togglePause()
        #expect(!harness.games.wantsIdleTimerDisabled, "정지 카드를 띄운 채 화면이 안 꺼진다")
        harness.hub.togglePause()
        #expect(!harness.games.wantsIdleTimerDisabled)
        while harness.hub.advanceResumeCountdown() {}
        #expect(controller.pauseState == .none)
        #expect(harness.games.wantsIdleTimerDisabled)
        await harness.tearDown()
    }

    // MARK: - 길건너 토큰

    @Test("길건너 토큰 갈아 끼우기는 정지 중에도 돈다 · background 면 복귀 때 갈아 끼운다")
    func crossyTokenStaysFreshWhileFrozen() async throws {
        let harness = GamesHarness(label: "pause-crossy-token")
        configure(harness)
        let tokens = gamesServeRoundTokens(harness, prefix: "tok")
        parkPause(harness)
        await harness.signIn()
        harness.hub.openScreen(.crossy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-1" })
        let controller = try #require(harness.hub.controller)
        controller.tap()

        // 19분 놀다 언다 → 1분 뒤(토큰 20분) 감시가 갈아 끼운다.
        harness.clock.advance(19 * 60)
        harness.hub.togglePause()
        harness.hub.pauseWatchTick()
        await harness.barrier()
        #expect(tokens.get() == ["tok-1"], "아직 젊은 토큰을 갈아 끼웠다")
        harness.clock.advance(60)
        harness.hub.pauseWatchTick()
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-2" }, "정지 중 토큰이 그대로 늙는다")

        // 풀고 18분 더 논다 → background → 2분 뒤(토큰 20분) 복귀가 갈아 끼운다. background 동안 감시는 안 돈다.
        harness.hub.togglePause()
        while harness.hub.advanceResumeCountdown() {}
        #expect(controller.pauseState == .none)
        harness.clock.advance(18 * 60)
        harness.model.sceneDidEnterBackground()
        harness.clock.advance(60)
        harness.hub.pauseWatchTick()
        await harness.barrier()
        #expect(tokens.get().count == 2, "background 에서 감시가 돌았다")
        harness.clock.advance(60)
        harness.model.sceneDidBecomeActive()
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-3" }, "복귀가 토큰을 안 갈아 끼웠다: \(tokens.get())")
        #expect(controller.isPlaying)
        await harness.tearDown()
    }

    @Test("토큰 불변식: 정지 중이어도 그 게임의 인편이 살아 있으면 새 토큰을 안 받는다")
    func frozenKeepAliveHonoursThePendingInvariant() async throws {
        let harness = GamesHarness(label: "pause-crossy-invariant")
        configure(harness)
        let tokens = gamesServeRoundTokens(harness, prefix: "tok")
        parkPause(harness)
        let gate = BaseGate()
        harness.hub.sleep = { _ in await gate.wait() }
        harness.server.setDefault("minigame_submit_score") { _ in .networkFailure() }
        await harness.signIn()
        harness.hub.openScreen(.crossy)
        #expect(await baseWaitUntil { harness.hub.roundToken == "tok-1" })
        harness.hub.recordScore(kind: .crossy, score: 3)
        #expect(await baseWaitUntil { submits(harness).count == 1 })
        await harness.barrier()
        let controller = try #require(harness.hub.controller)
        controller.tap()
        harness.hub.togglePause()
        harness.clock.advance(4 * 60)
        harness.hub.pauseWatchTick()
        await harness.barrier()
        #expect(tokens.get() == ["tok-1"], "인편의 토큰을 자기 손으로 죽였다: \(tokens.get())")
        gate.open()
        await harness.tearDown()
    }

    // MARK: - 임시 항목(iOS 가 앱을 죽여도)

    @Test("임시 항목: 내려갈 때 테트리스·길건너만 지금 점수·토큰을 적고 제출은 안 한다", arguments: MiniGameKind.phoneCases)
    func theDraftIsWrittenOnlyForGamesThatKeepTheScore(kind: MiniGameKind) async throws {
        let harness = GamesHarness(label: "pause-draft-\(kind.rawValue)")
        let controller = try await startRound(harness, kind)
        let score = controller.score
        harness.model.sceneDidEnterBackground()
        await harness.barrier()
        #expect(submits(harness).isEmpty, "\(kind): 언 판의 토큰이 나갔다")
        if GamesMiniGamePausePolicy.quittingKeepsTheScore(kind) {
            let written = try #require(try draft(harness), "\(kind): 임시 항목이 없다 — iOS 가 앱을 죽이면 점수가 사라진다")
            #expect(written.kind == kind)
            #expect(written.score == score)
            #expect(written.token == "tok-1")
            #expect(harness.hub.pendingSubmit == nil, "\(kind): 인편에 넣었다 — 밀기가 도는 판의 토큰을 보내 버린다")
        } else {
            #expect(draftData(harness) == nil, "\(kind): 접으면 버리는 게임이 적었다")
        }
        await harness.tearDown()
    }

    @Test("임시 항목: inactive 에서도 적는다(앱 전환기에서 바로 쓸어 올려 죽이는 길)")
    func theDraftIsWrittenOnInactive() async throws {
        let harness = GamesHarness(label: "pause-draft-inactive")
        _ = try await startRound(harness, .tetris)
        harness.model.sceneWillResignActive()
        #expect(draftData(harness) != nil)
        await harness.tearDown()
    }

    @Test("임시 항목: 다시 내려가면 그때의 점수·토큰으로 갈아 적는다")
    func theDraftTracksTheLatestState() async throws {
        let harness = GamesHarness(label: "pause-draft-rewrite")
        let controller = try await startRound(harness, .tetris)
        harness.model.sceneDidEnterBackground()
        #expect(try draft(harness)?.score == 7)
        harness.model.sceneDidBecomeActive()
        harness.hub.togglePause()
        while harness.hub.advanceResumeCountdown() {}
        for _ in 0..<3 { controller.softDropOneCell() }
        harness.model.sceneDidEnterBackground()
        #expect(try draft(harness)?.score == 10)
        await harness.tearDown()
    }

    @Test("임시 항목: 복귀해서 이어 하면 지운다")
    func resumingClearsTheDraft() async throws {
        let harness = GamesHarness(label: "pause-draft-resume")
        _ = try await startRound(harness, .crossy)
        harness.model.sceneDidEnterBackground()
        harness.model.sceneDidBecomeActive()
        #expect(draftData(harness) != nil, "돌아와 카드만 보는 동안은 남는다(그 사이 앱이 또 내려갈 수 있다)")
        harness.hub.togglePause()
        #expect(draftData(harness) == nil, "이어 하는데 임시 항목이 남았다 — 다음 실행에 옛 점수가 올라간다")
        await harness.barrier()
        #expect(submits(harness).isEmpty)
        await harness.tearDown()
    }

    @Test("임시 항목: 프로세스가 죽어 다음 실행에 살아 있으면 **같은 토큰으로** 그 점수를 올린다")
    func anOrphanedDraftIsSubmittedOnTheNextLaunch() async throws {
        let first = GamesHarness(label: "pause-orphan-1")
        let controller = try await startRound(first, .tetris)
        let score = controller.score
        first.model.sceneDidEnterBackground()
        let saved = try #require(draftData(first))
        await first.tearDown()

        let second = GamesHarness(label: "pause-orphan-2")
        configure(second)
        gamesServeRoundTokens(second, prefix: "tok-second")
        second.storage.defaults.set(saved, forKey: GamesMiniGameHub.pauseDraftKey(userID: GamesHarness.userID))
        await second.signIn()
        #expect(await baseWaitUntil { submits(second).count == 1 }, "죽은 앱의 점수가 안 올라갔다")
        #expect(submits(second)[0].contains(#""p_token":"tok-1""#), "다른 토큰으로 나갔다")
        #expect(submits(second)[0].contains(#""p_score":\#(score)"#))
        #expect(submits(second)[0].contains(#""p_game":"tetris""#))
        #expect(draftData(second) == nil, "임시 항목이 남았다 — 다음 실행에 또 올라간다")
        #expect(await baseWaitUntil { second.hub.pendingSubmit == nil })
        #expect(second.hub.best(for: .tetris) >= score)
        #expect(second.violations.isEmpty, "\(second.violations)")
        await second.tearDown()
    }

    @Test("임시 항목: 토큰이 없던 판은 기존 인편 규칙대로 토큰을 받아 올린다")
    func anOrphanedDraftWithoutATokenWaitsForOne() async throws {
        let draft = MiniGamePendingSubmit(id: UUID(), kind: .crossy, score: 4, token: nil, tokenIssuedAt: nil,
                                          recordedAt: MobileClock.demoInstant, attempts: 0)
        let harness = GamesHarness(label: "pause-orphan-tokenless")
        configure(harness)
        gamesServeRoundTokens(harness, prefix: "tok-new")
        harness.storage.defaults.set(try JSONEncoder().encode(draft), forKey: GamesMiniGameHub.pauseDraftKey(userID: GamesHarness.userID))
        await harness.signIn()
        #expect(await baseWaitUntil { submits(harness).count == 1 }, "토큰을 기다리는 인편이 안 올라갔다")
        #expect(submits(harness)[0].contains("tok-new-1"))
        #expect(submits(harness)[0].contains(#""p_score":4"#))
        await harness.tearDown()
    }

    @Test("임시 항목: 토큰 수명을 넘긴 채 되살아나면 보내지 않고 다음에 화면을 열 때 말한다")
    func anExpiredOrphanedDraftIsDroppedAndTold() async throws {
        let harness = GamesHarness(label: "pause-orphan-expired")
        configure(harness)
        gamesServeRoundTokens(harness, prefix: "tok-new")
        let old = harness.clock.now.addingTimeInterval(-(MiniGameSubmitRules.pendingTTL + 60))
        let draft = MiniGamePendingSubmit(id: UUID(), kind: .tetris, score: 9, token: "tok-old", tokenIssuedAt: old, recordedAt: old, attempts: 0)
        harness.storage.defaults.set(try JSONEncoder().encode(draft), forKey: GamesMiniGameHub.pauseDraftKey(userID: GamesHarness.userID))
        await harness.signIn()
        await harness.barrier()
        #expect(submits(harness).isEmpty, "죽은 토큰을 보냈다")
        #expect(draftData(harness) == nil)
        harness.hub.openScreen(.tetris)
        #expect(harness.hub.submitNotice == GamesMiniGameText.submitFailedConnection, "그 판이 사라진 것을 아무도 말하지 않는다")
        #expect(harness.hub.localBest[.tetris] == 9, "로컬 최고까지 잃었다")
        await harness.tearDown()
    }

    @Test("이중 제출 0: 얼렸다 풀고 정상으로 끝나면 제출은 한 번 · 다음 실행에도 안 올라간다")
    func noDoubleSubmitAfterANormalEnd() async throws {
        let harness = GamesHarness(label: "pause-once")
        let controller = try await startRound(harness, .crossy)
        harness.model.sceneDidEnterBackground()
        harness.model.sceneDidBecomeActive()
        harness.hub.togglePause()
        while harness.hub.advanceResumeCountdown() {}
        // 정상 종료: 가만히 두면 길건너는 9초에 끝난다.
        gamesDrive(controller, from: harness.clock.now, frames: 60 * 20) { $0.crossy.phase == .result }
        #expect(controller.crossy.phase == .result)
        #expect(await baseWaitUntil { submits(harness).count == 1 })
        await harness.barrier()
        #expect(submits(harness).count == 1)
        #expect(draftData(harness) == nil, "임시 항목이 남았다")

        // 같은 저장소로 다시 켠다.
        let storageDraft = draftData(harness)
        await harness.tearDown()
        let second = GamesHarness(label: "pause-once-2")
        configure(second)
        gamesServeRoundTokens(second, prefix: "tok-second")
        if let storageDraft {
            second.storage.defaults.set(storageDraft, forKey: GamesMiniGameHub.pauseDraftKey(userID: GamesHarness.userID))
        }
        await second.signIn()
        await second.barrier()
        #expect(submits(second).isEmpty, "끝난 판이 다음 실행에 또 올라갔다")
        await second.tearDown()
    }

    @Test("이중 제출 0: 임시 항목이 있는 채 상한·[그만두기]로 끝나도 제출은 한 번이고 임시 항목은 없다", arguments: [false, true])
    func noDoubleSubmitWhenEndingWithADraft(byCap: Bool) async throws {
        let harness = GamesHarness(label: "pause-once-draft-\(byCap)")
        let controller = try await startRound(harness, .tetris)
        harness.model.sceneDidEnterBackground()
        #expect(draftData(harness) != nil)
        if byCap {
            harness.clock.advance(Self.limit)
            harness.model.sceneDidBecomeActive()
        } else {
            harness.model.sceneDidBecomeActive()
            harness.hub.quitPausedRound()
        }
        #expect(!controller.isPlaying)
        #expect(draftData(harness) == nil, "진짜 인편과 임시 항목이 둘 다 있다 — 다음 실행에 같은 판이 또 올라간다")
        #expect(await baseWaitUntil { submits(harness).count == 1 })
        await harness.barrier()
        #expect(submits(harness).count == 1)
        await harness.tearDown()
    }

    @Test("이 실행에서 적은 임시 항목은 인편으로 올리지 않는다 — 살아 있는 판의 것이다")
    func aLiveDraftIsNotAdopted() async throws {
        let harness = GamesHarness(label: "pause-live-draft")
        _ = try await startRound(harness, .tetris)
        harness.model.sceneDidEnterBackground()
        harness.model.sceneDidBecomeActive()
        harness.hub.retryPendingSubmitIfAny()
        await harness.barrier()
        #expect(harness.hub.pendingSubmit == nil)
        #expect(draftData(harness) != nil)
        #expect(submits(harness).isEmpty)
        await harness.tearDown()
    }

    @Test("공개를 끈 사람: 임시 항목도 제출도 없고 로컬 최고만 남는다")
    func aPrivateRoundWritesNoDraft() async throws {
        let harness = GamesHarness(label: "pause-private")
        let controller = try await startRound(harness, .tetris, isPublic: false)
        let score = controller.score
        harness.model.sceneDidEnterBackground()
        #expect(draftData(harness) == nil, "공개를 껐는데 다음 실행에 올라갈 점수를 적었다")
        #expect(harness.hub.localBest[.tetris] == score)
        await harness.barrier()
        #expect(submits(harness).isEmpty)
        await harness.tearDown()
    }

    // MARK: - 문구 · 화면 계약

    @Test("문구: 게임마다 접는 결과대로 말한다 · 맥과 같은 낱말 · 서버 진단이 안 샌다")
    func theTextsMatchTheTable() {
        #expect(GamesMiniGameText.pauseTitle == "일시정지")
        #expect(GamesMiniGameText.resumeAction == "이어하기")
        #expect(GamesMiniGameText.quitAction == "그만두기")
        #expect(GamesMiniGameText.pauseCapEnded == "5분 넘게 멈춰서 여기까지 기록했어요")
        for kind in MiniGameKind.phoneCases {
            let line = GamesMiniGameText.pauseSubtitle(kind)
            if GamesMiniGamePausePolicy.quittingKeepsTheScore(kind) {
                #expect(line.contains("기록돼요"), "\(kind): 남는 판을 안 남는다고 말한다")
            } else {
                #expect(line.contains("기록되지 않아요"), "\(kind): 버리는 판을 남는다고 말한다")
            }
            #expect(!line.contains("token") && !line.contains("서버"))
        }
    }

    @Test("지운 문구가 안 돌아왔다 — 앱을 내려도 판이 안 끝난다")
    func theOldBackgroundCopyIsGone() throws {
        let text = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesText.swift")
        #expect(!text.contains("endedInBackground"))
        #expect(!text.contains("앱을 나가서"))
    }

    @Test("화면 계약: 스크림은 제스처 밖 · 언 판은 프레임이 멈춘다 · 버튼은 허브로 · 데모 장면은 DEBUG 안")
    func theScreenWiring() throws {
        let screen = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift")
        #expect(screen.contains("paused: !controller.isPlaying || framesFrozen || controller.isFrozen"), "언 판의 프레임 루프가 돈다")
        let gesture = try #require(screen.range(of: ".gesture(canvasDrag(controller))"))
        let overlay = try #require(screen.range(of: "GamesMiniGamePauseOverlay("))
        #expect(gesture.upperBound < overlay.lowerBound, "스크림이 제스처 안이다 — 카드 위 탭이 판으로 샌다")
        #expect(screen.contains("onResume: { hub.togglePause() }, onQuit: { hub.quitPausedRound() }"))
        #expect(screen.contains("Button { hub.togglePause() }"), "[일시정지] 가 허브를 안 지난다")
        #expect(screen.contains("!controller.pauseState.showsCard"), "카드가 떠 있는데 [일시정지] 가 남는다")
        #expect(screen.contains(".accessibilityHidden(controller.isFrozen)"), "정지 중 보이스오버가 판을 읽는다")
        // 합성 입력 없이 찍을 장면(Release 에 안 실린다).
        let seed = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CheckMobileKit/Games/GamesDemoSeed.swift"), encoding: .utf8)
        #expect(seed.hasPrefix("#if DEBUG"))
        #expect(seed.contains("paused, countdown"))
        // 스크림은 불투명이다 — 맥 실측: 0.93 만 얹었더니 판이 비쳤다.
        let pause = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesMiniGamePause.swift")
        let body = try #require(pause.components(separatedBy: "ZStack {").dropFirst().first)
        #expect(String(body.prefix(40)).contains("CheckTheme.panel\n"), "스크림 바닥이 불투명이 아니다")
        #expect(pause.contains(".environment(\\.colorScheme, .dark)"), "라이트 모드에서 어두운 판 위에 라이트 토큰을 그린다 — [그만두기] 가 안 읽힌다")
    }
}
