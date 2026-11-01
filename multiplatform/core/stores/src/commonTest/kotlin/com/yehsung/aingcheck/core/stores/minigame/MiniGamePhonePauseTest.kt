// 원본: Tests/CheckMobileKitTests/GamesMiniGamePauseTests.swift @ 45ceda2d (폰 미니게임 일시정지 — 사용자 답 "넣기" · 플래피 "지금처럼 버림")
//
// iOS 시험의 뜻을 옮겼다. 다른 것: 시계가 가상 시간이라 `clock.advance` 대신 `advance` 를 쓰고, 정지 중 토큰 챙기기는 iOS 허브 감시 대신 기존 `runRoundTokenKeeper` 를 잰다.
// iOS 는 시험이 3-2-1 · 감시를 직접 민다. 여기도 같은 까닭으로 `pauseSleep` 을 세워 두고 직접 민다(`advanceUntilIdle` 이 1초 고리에서 안 끝난다). 진짜 고리는 두 시험이 가상 시간으로 잰다.
package com.yehsung.aingcheck.core.stores.minigame

import com.yehsung.aingcheck.core.rules.minigame.FlappyGame
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.MiniGamePoint
import com.yehsung.aingcheck.core.rules.minigame.MiniGameSize
import com.yehsung.aingcheck.core.rules.minigame.TimingBarGame
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.games.GamesPlayController
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.games.MemoryPrefs
import com.yehsung.aingcheck.core.stores.games.Reply
import com.yehsung.aingcheck.core.stores.games.StoreFixtures
import com.yehsung.aingcheck.core.stores.games.StoreHarness
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MiniGamePhonePauseTest {
    private class Stub {
        var tokens = 0
        val submits = ArrayDeque<Reply>()
        val starts = ArrayDeque<Reply>()
        var public = true
        fun route(r: RecordedRequest): Reply? = when {
            r.rpcName == "minigame_start_round" -> {
                tokens += 1
                starts.removeFirstOrNull() ?: Reply.Json("""{"status":"ok","token":"t$tokens"}""")
            }
            r.rpcName == "minigame_submit_score" -> submits.removeFirstOrNull() ?: ok
            r.rpcName == "minigame_board" || r.rpcName == "minigame_yesterday_winner" -> Reply.Json("[]")
            r.path == "/rest/v1/profiles" && r.method == "GET" -> Reply.Json("""[{"minigame_public":$public}]""")
            else -> null
        }

        companion object {
            val ok = Reply.Json("""{"status":"ok","best_score":55,"plays":4,"improved":true}""")
            fun status(s: String) = Reply.Json("""{"status":"$s"}""")
        }
    }

    private class Rig(val h: StoreHarness, val hub: GamesMiniGameHub, val stub: Stub, val prefs: MemoryPrefs)

    /** 안드로이드 조립과 같은 허브(폰 규칙 켬) · 3-2-1 · 감시는 문 앞에 세운다(시험이 직접 민다). */
    private suspend fun TestScope.rig(stub: Stub = Stub(), prefs: MemoryPrefs = MemoryPrefs(), parked: Boolean = true): Rig {
        val h = StoreHarness(this, prefs = prefs, route = stub::route)
        h.signIn()
        val hub = GamesMiniGameHub(h.context)
        hub.phonePauseRules = true
        if (parked) hub.pauseSleep = { awaitCancellation() }
        return Rig(h, hub, stub, prefs)
    }

    /** 로그인 → 화면 열기 → 토큰 → 판 시작. 테트리스·길건너는 점수가 있는 판으로 만든다. */
    private suspend fun TestScope.started(kind: MiniGameKind, stub: Stub = Stub(), prefs: MemoryPrefs = MemoryPrefs()): Pair<Rig, GamesPlayController> {
        val r = rig(stub, prefs)
        r.hub.openScreen(kind)
        advanceUntilIdle()
        if (stub.public) assertEquals("t${stub.tokens}", r.hub.roundToken, "전제: 토큰을 쥐었다") else assertFalse(r.hub.isPublic)
        val c = assertNotNull(r.hub.controller)
        c.tap()
        when (kind) {
            MiniGameKind.tetris -> repeat(7) { c.softDropOneCell() }
            MiniGameKind.crossy -> {
                drive(c, 0.0, 30)
                assertTrue(c.score >= 1, "전제: 점수가 올라 있다")
            }
            MiniGameKind.flappy, MiniGameKind.timingBar -> drive(c, 0.0, 6)
        }
        assertTrue(c.isPlaying, "전제: 판이 돈다")
        return r to c
    }

    private val t0 = SwiftDate(1_789_621_500.0)
    private fun at(seconds: Double) = t0.addingTimeInterval(seconds)

    private fun drive(c: GamesPlayController, from: Double, frames: Int, stop: ((GamesPlayController) -> Boolean)? = null): Double {
        var t = from
        repeat(frames) {
            t += 1.0 / 60
            c.tick(at(t))
            if (stop?.invoke(c) == true) return t
        }
        return t
    }

    private fun TestScope.advance(seconds: Double) {
        advanceTimeBy((seconds * 1000).toLong())
        runCurrent()
    }

    private val limit = MiniGamePauseState.PAUSE_LIMIT_SECONDS.toDouble()
    private val owner = StoreFixtures.USER.lowercase()

    private fun Rig.submits(): List<String> = h.server.bodies("minigame_submit_score")
    private fun Rig.draftText(): String? = prefs.getString(GamesMiniGameHub.pauseDraftKey(owner))
    private fun Rig.draft(): JsonObject? = draftText()?.let { Json.parseToJsonElement(it).jsonObject }
    private fun JsonObject.intOf(key: String) = getValue(key).jsonPrimitive.int
    private fun JsonObject.textOf(key: String) = get(key)?.jsonPrimitive?.takeIf { it.isString }?.content
    private fun Rig.tokensAsked(): Int = h.server.count("minigame_start_round")
    private fun String.hasScore(score: Int) = "\"p_score\":$score" in this
    private fun String.hasToken(token: String) = "\"p_token\":\"$token\"" in this

    /** 3-2-1 을 끝까지 민다. */
    private fun GamesMiniGameHub.finishCountdown() {
        while (advanceResumeCountdown()) Unit
    }

    // MARK: 코어 전이

    @Test
    fun theTransitionTable() {
        val none = MiniGamePauseState.None
        val paused = MiniGamePauseState.Paused
        assertEquals(3, MiniGamePauseState.COUNTDOWN_START)
        assertEquals(5 * 60, MiniGamePauseState.PAUSE_LIMIT_SECONDS)
        // 수동: 도는 판 → 카드 → 3 → (취소) 카드. 판이 안 돌면 얼지 않는다.
        assertEquals(paused, none.toggled(true))
        assertEquals(none, none.toggled(false))
        assertEquals(MiniGamePauseState.Resuming(3), paused.toggled(true))
        assertEquals(paused, MiniGamePauseState.Resuming(2).toggled(true))
        // 자동: 언제나 '언다'. 이미 카드면 아무 일도 없다(그래야 시계가 안 되돌아간다), 3-2-1 이면 취소.
        assertEquals(paused, none.resigningKey(true))
        assertNull(paused.resigningKey(true))
        assertEquals(paused, MiniGamePauseState.Resuming(1).resigningKey(true))
        assertNull(none.resigningKey(false))
        assertEquals(MiniGamePauseState.Resuming(2), MiniGamePauseState.Resuming(3).steppedDown())
        assertEquals(none, MiniGamePauseState.Resuming(1).steppedDown())
    }

    // MARK: 구동기 — 얼어 있는 판

    /** 얼어 있으면 모든 입력이 판에 안 닿는다(게임 넷 · 탭 · 끌기 · 버튼 · 키). */
    @Test
    fun everyInputIsDeadWhileFrozen() {
        for (kind in MiniGameKind.entries) {
            val c = GamesPlayController(kind, 21u)
            c.tap()
            drive(c, 0.0, 6)
            c.applyPauseState(MiniGamePauseState.Paused)
            val timing = c.timing
            val flappy = c.flappy
            val tetris = c.tetris
            val crossy = c.crossy
            val serial = c.tapSerial
            c.tap()
            c.rotate(clockwise = true)
            c.hold()
            c.hardDrop()
            c.moveLeftOneCell()
            c.moveRightOneCell()
            c.softDropOneCell()
            c.hop(CrossyGame.Direction.forward)
            c.setLeftHeld(true)
            c.setSoftDropHeld(true)
            c.canvasDragChanged(MiniGamePoint(0.0, 0.0), MiniGameSize(200.0, 0.0), at(1.0))
            assertFalse(c.canvasDragEnded(MiniGameSize(0.0, 0.0), at(1.0)), "$kind: 정지 중 끌기가 탭으로 먹었다")
            assertEquals(timing, c.timing, "$kind")
            assertEquals(flappy, c.flappy, "$kind")
            assertEquals(tetris, c.tetris, "$kind")
            assertEquals(crossy, c.crossy, "$kind")
            assertEquals(serial, c.tapSerial, "$kind: 정지 중 햅틱이 울린다")
        }
    }

    /** 얼어 있는 동안 프레임이 와도 판이 안 움직이고, 풀린 첫 프레임은 **기준만 잡는다**. */
    @Test
    fun theFirstFrameAfterThawingOnlySetsTheBase() {
        for (kind in MiniGameKind.entries) {
            val c = GamesPlayController(kind, 22u)
            c.tap()
            var t = drive(c, 0.0, 6)
            c.applyPauseState(MiniGamePauseState.Paused)
            val frozen = listOf(c.timing, c.flappy, c.tetris, c.crossy)
            // 언 뒤 프레임이 **둘 이상** 온다 — 하나면 기준만 잡고 끝나서 가드가 없어도 판이 안 움직인다(iOS 뮤테이션 실측 45ceda2d).
            t = drive(c, t + 120, 30)
            c.applyPauseState(MiniGamePauseState.Resuming(1))
            t = drive(c, t + 1, 30)
            assertEquals(frozen, listOf(c.timing, c.flappy, c.tetris, c.crossy), "$kind: 얼어 있는 판이 움직였다")
            c.applyPauseState(MiniGamePauseState.None)
            t += 120
            c.tick(at(t)) // 풀린 첫 프레임: 그 사이 120초는 dt 가 아니다.
            assertEquals(frozen, listOf(c.timing, c.flappy, c.tetris, c.crossy), "$kind: 멈춘 시간을 물려받았다")
            c.tick(at(t + 1.0 / 60))
            assertNotEquals(frozen, listOf(c.timing, c.flappy, c.tetris, c.crossy), "$kind: 풀렸는데 판이 안 돈다")
        }
    }

    /** 길건너 idleLimit 은 정지 시간을 안 센다 — 8초 서 있다 1분 멈춰도 안 죽는다. */
    @Test
    fun crossyIdleLimitIgnoresThePause() {
        val c = GamesPlayController(MiniGameKind.crossy, 23u)
        c.tap()
        var t = drive(c, 0.0, 8 * 60)
        assertEquals(CrossyGame.Phase.Running, c.crossy.phase, "전제: 아직 산다")
        c.applyPauseState(MiniGamePauseState.Paused)
        t += 60
        c.tick(at(t))
        c.applyPauseState(MiniGamePauseState.None)
        c.tick(at(t))
        assertEquals(CrossyGame.Phase.Running, c.crossy.phase, "정지 시간이 idleLimit 에 들어갔다")
        drive(c, t, 3 * 60)
        assertNotEquals(CrossyGame.Phase.Running, c.crossy.phase, "대조: 정지를 빼고 9초를 넘기면 끝나야 한다 — 이 시험이 아무것도 못 잰다")
    }

    /** 테트리스 15분 상한은 **정지도 함께 센다** — 토큰 예산이지 게임 시간이 아니다(12 + 15 + 1 = 28 < 30). */
    @Test
    fun theTetrisRoundLimitKeepsCountingThroughAPause() {
        val c = GamesPlayController(MiniGameKind.tetris, 24u)
        val finished = mutableListOf<Int>()
        c.onFinished = { finished += it }
        c.roundLimitSeconds = GamesMiniGameHub.tetrisRoundLimitSeconds
        c.tap()
        c.tick(at(0.0))
        c.applyPauseState(MiniGamePauseState.Paused)
        c.tick(at(5.0 * 60))
        c.applyPauseState(MiniGamePauseState.None)
        c.tick(at(14.0 * 60))
        assertTrue(c.isPlaying, "상한 전인데 끝났다")
        c.tick(at(15.0 * 60))
        assertFalse(c.isPlaying, "정지를 빼 줬다 — 고의로 늘인 판 + 정지 5분이 33분이 되어 통째로 거절된다")
        assertEquals(1, finished.size)
    }

    /** 얼리는 순간 눌린 키와 끌기를 놓는다 — 풀린 뒤 첫 조각이 튀지 않는다. */
    @Test
    fun freezingReleasesGestureAndKeys() {
        val c = GamesPlayController(MiniGameKind.tetris, 25u)
        c.updateCellWidth(20.0)
        c.tap()
        val column = c.tetris.active?.column
        c.canvasDragChanged(MiniGamePoint(0.0, 0.0), MiniGameSize(40.0, 0.0), at(0.0))
        assertNotEquals(column, c.tetris.active?.column, "전제: 끌기가 먹었다")
        c.setLeftHeld(true) // 누름이 한 칸을 바로 움직인다. 여기서 안 놓으면 DAS 가 풀린 판을 벽까지 민다.
        val moved = c.tetris.active?.column
        c.applyPauseState(MiniGamePauseState.Paused)
        c.applyPauseState(MiniGamePauseState.None)
        // 같은 시작점의 다음 프레임: 트래커가 비었으므로 새 접촉처럼 0 부터 잰다 — 작은 이동은 안 움직인다.
        c.canvasDragChanged(MiniGamePoint(1.0, 1.0), MiniGameSize(1.0, 0.0), at(0.1))
        assertEquals(moved, c.tetris.active?.column, "앞 끌기의 소비량이 풀린 뒤로 샜다")
        drive(c, 1.0, 60)
        assertEquals(moved, c.tetris.active?.column, "← 를 눌린 채로 안다 — 풀린 판이 왼쪽으로 붙는다")
    }

    // MARK: 게임별 표

    /** 표: 정책이 엔진과 맞는다 — 플래피·타이밍 바는 버림, 테트리스·길건너는 확정. */
    @Test
    fun thePolicyMatchesWhatEndRoundActuallyDoes() {
        for (kind in MiniGameKind.entries) {
            val c = GamesPlayController(kind, 26u)
            val finished = mutableListOf<Int>()
            c.onFinished = { finished += it }
            c.tap()
            drive(c, 0.0, 6)
            val score = c.score
            val outcome = c.endRound()
            if (GamesMiniGamePausePolicy.quittingKeepsTheScore(kind)) {
                assertEquals(GamesPlayController.EndOutcome.Confirmed(score), outcome, "$kind")
                assertEquals(listOf(score), finished, "$kind")
            } else {
                assertEquals(GamesPlayController.EndOutcome.Abandoned, outcome, "$kind")
                assertEquals(emptyList(), finished, "$kind: 버리는 게임이 알렸다")
            }
            assertEquals(GamesMiniGamePausePolicy.quittingKeepsTheScore(kind), GamesMiniGamePausePolicy.capApplies(kind), "$kind: 상한은 접어도 남는 게임에만 건다")
            assertEquals(MiniGamePauseState.None, c.pauseState)
        }
    }

    /** 표: 게임별 값을 글자로 못 박는다 — 플래피가 맥과 다른 유일한 칸이다. */
    @Test
    fun theTableIsSpelledOut() {
        assertTrue(GamesMiniGamePausePolicy.capApplies(MiniGameKind.tetris))
        assertTrue(GamesMiniGamePausePolicy.capApplies(MiniGameKind.crossy))
        assertFalse(GamesMiniGamePausePolicy.capApplies(MiniGameKind.flappy), "사용자 답 '지금처럼 버림' — 안 남는 게임에 상한을 걸면 판을 없앤다")
        assertFalse(GamesMiniGamePausePolicy.capApplies(MiniGameKind.timingBar))
        val differs = MiniGameKind.entries.filter { MiniGamePauseState.quittingKeepsTheScore(it) != GamesMiniGamePausePolicy.quittingKeepsTheScore(it) }
        assertEquals(listOf(MiniGameKind.flappy), differs, "맥 표와 폰 표가 갈리는 칸은 플래피 하나다")
    }

    /** [그만두기]: 테트리스·길건너는 그 점수로 **한 번** 제출, 화면은 그대로 · 플래피·타이밍 바는 제출 없음 · 토큰 유지. */
    @Test
    fun quittingFollowsTheTable() = runTest {
        for (kind in MiniGameKind.entries) {
            val (r, c) = started(kind)
            val score = c.score
            r.hub.togglePause()
            assertEquals(MiniGamePauseState.Paused, c.pauseState)
            r.hub.quitPausedRound()
            assertFalse(c.isPlaying, "$kind")
            assertEquals(MiniGamePauseState.None, c.pauseState)
            assertEquals(kind, r.hub.activeKind, "[그만두기] 가 화면을 닫았다")
            advanceUntilIdle()
            if (GamesMiniGamePausePolicy.quittingKeepsTheScore(kind)) {
                assertEquals(1, r.submits().size, "$kind")
                assertTrue(r.submits()[0].hasScore(score), r.submits()[0])
            } else {
                assertEquals(emptyList(), r.submits(), "$kind: 버리는 게임이 제출했다")
                assertEquals("t1", r.hub.roundToken, "$kind: 쓰지 않은 토큰은 다음 판에 쓴다")
            }
            r.h.assertClean()
        }
    }

    /** 정지 중 뒤로 가기는 [그만두기]와 같다. */
    @Test
    fun goingBackWhilePausedEqualsQuitting() = runTest {
        for (kind in MiniGameKind.entries) {
            val (r, c) = started(kind)
            val score = c.score
            r.hub.appDidEnterBackground()
            r.hub.sceneDidComeForward()
            r.hub.closeScreen(kind)
            assertNull(r.hub.controller)
            assertNull(r.draftText(), "임시 항목이 남았다 — 다음 실행에 같은 판이 또 올라간다")
            advanceUntilIdle()
            if (GamesMiniGamePausePolicy.quittingKeepsTheScore(kind)) {
                assertEquals(1, r.submits().size, "$kind")
                assertTrue(r.submits()[0].hasScore(score))
            } else {
                assertEquals(emptyList(), r.submits(), "$kind: 버리는 게임이 제출했다")
            }
        }
    }

    /** 정지 중 다른 게임 화면이 열려도(딥링크 · 판 전환) [그만두기]와 같다 — 옛 화면의 퇴장이 나중에 와도 판이 안 사라진다. */
    @Test
    fun openingAnotherGameWhilePausedEqualsQuitting() = runTest {
        for (kind in MiniGameKind.entries) {
            val (r, c) = started(kind)
            val score = c.score
            r.hub.togglePause()
            val other = if (kind == MiniGameKind.tetris) MiniGameKind.flappy else MiniGameKind.tetris
            r.hub.openScreen(other)
            r.hub.closeScreen(kind) // 옛 화면의 onDispose 가 뒤늦게 온다 — 아무 일도 없어야 한다.
            assertEquals(other, r.hub.activeKind)
            assertNull(r.draftText())
            advanceUntilIdle()
            if (GamesMiniGamePausePolicy.quittingKeepsTheScore(kind)) {
                assertEquals(1, r.submits().size, "$kind: 사람이 쌓은 판이 경합 정리에 사라졌다")
                assertTrue(r.submits()[0].hasScore(score))
                assertTrue("\"p_game\":\"${kind.rawValue}\"" in r.submits()[0])
            } else {
                assertEquals(emptyList(), r.submits(), "$kind: 버리는 게임이 제출했다")
            }
        }
    }

    /** 로그아웃은 abandon 그대로 — 제출도 임시 항목도 안 남는다. */
    @Test
    fun resetAbandonsAndClearsTheDraft() = runTest {
        val (r, c) = started(MiniGameKind.tetris)
        r.hub.appDidEnterBackground()
        assertNotNull(r.draftText())
        r.hub.reset()
        assertFalse(c.isPlaying)
        assertEquals(MiniGamePauseState.None, c.pauseState)
        assertNull(r.draftText(), "로그아웃했는데 임시 항목이 남았다 — 같은 계정이 돌아오면 버린 판이 올라간다")
        advanceUntilIdle()
        assertEquals(emptyList(), r.submits(), "남의 계정으로 넘어가는 자리에서 제출했다")
    }

    /** 계정 삭제 정리에 인편·임시 항목·표식이 든다(대소문자 무관 — 키는 소문자다). */
    @Test
    fun forgettingAnAccountRemovesEverything() {
        val prefs = MemoryPrefs()
        val keys = listOf(GamesMiniGameHub.pauseDraftKey("u-gone"), GamesMiniGameHub.pendingKey("u-gone"), GamesMiniGameHub.lostNoticeKey("u-gone"))
        for (key in keys) prefs.putString(key, "x")
        GamesMiniGameHub.forgetPendingSubmits("U-GONE", prefs)
        for (key in keys) assertNull(prefs.getString(key), key)
    }

    // MARK: 벽시계 상한

    /** 상한은 벽시계다: 백그라운드 4분 → 복귀 → 카드 2분이면 끝 · 넘기 전에는 안 끝난다. */
    @Test
    fun theCapCountsBackgroundTime() = runTest {
        val (r, c) = started(MiniGameKind.tetris)
        val score = c.score
        r.hub.appDidEnterBackground()
        advance(4.0 * 60)
        r.hub.sceneDidComeForward()
        assertEquals(MiniGamePauseState.Paused, c.pauseState, "복귀가 판을 저절로 풀었다")
        assertEquals(4.0 * 60, r.hub.pausedSecondsUsed)
        advance(59.0)
        r.hub.pauseWatchTick()
        assertTrue(c.isPlaying, "5분 전에 끝났다")
        advance(61.0)
        r.hub.pauseWatchTick()
        assertFalse(c.isPlaying, "상한을 넘겼는데 안 끝난다")
        assertEquals(MiniGamePauseState.None, c.pauseState)
        assertEquals(GamesMiniGameText.pauseCapEnded, r.hub.submitNotice)
        advanceUntilIdle()
        assertEquals(1, r.submits().size)
        assertTrue(r.submits()[0].hasScore(score))
        assertEquals(GamesMiniGameText.pauseCapEnded, r.hub.submitNotice, "제출 성공이 상한 안내를 지웠다 — 판이 조용히 사라진 것처럼 보인다")
    }

    /** 상한: 나가 있는 동안 넘겼으면 **돌아오는 그 순간** 끝난다(복귀 판정). background 의 감시는 판을 안 끝낸다. */
    @Test
    fun theCapIsCheckedOnTheWayBack() = runTest {
        for (kind in listOf(MiniGameKind.tetris, MiniGameKind.crossy)) {
            val (r, c) = started(kind)
            r.hub.appDidEnterBackground()
            advance(limit + 1)
            r.hub.pauseWatchTick()
            assertTrue(c.isPlaying, "$kind: background 에서 도는 감시가 판을 끝냈다 — 복귀가 판정해야 한다")
            r.hub.sceneDidComeForward()
            assertFalse(c.isPlaying, "$kind")
            assertEquals(GamesMiniGameText.pauseCapEnded, r.hub.submitNotice)
            advanceUntilIdle()
            assertEquals(1, r.submits().size)
            assertNull(r.draftText(), "진짜 인편이 섰는데 임시 항목이 남았다")
        }
    }

    /** 상한: ON_PAUSE 에서 돌아와도 잰다(background 를 안 거친 복귀). */
    @Test
    fun theCapIsCheckedComingBackFromOnPause() = runTest {
        val (r, c) = started(MiniGameKind.tetris)
        r.hub.appWillResignActive()
        assertEquals(MiniGamePauseState.Paused, c.pauseState)
        advance(limit)
        r.hub.sceneDidComeForward()
        assertFalse(c.isPlaying)
    }

    /** 상한: 재정지를 되풀이해도 시계가 안 되돌아간다 — 판 단위 누적이고 3-2-1 도 든다. */
    @Test
    fun repeatedPausesNeverRewindTheClock() = runTest {
        val (r, c) = started(MiniGameKind.crossy)
        repeat(2) {
            r.hub.togglePause()
            assertEquals(MiniGamePauseState.Paused, c.pauseState)
            advance(2.0 * 60)
            r.hub.pauseWatchTick()
            r.hub.togglePause() // [이어하기]
            assertTrue(r.hub.advanceResumeCountdown())
            assertTrue(r.hub.advanceResumeCountdown())
            assertFalse(r.hub.advanceResumeCountdown())
            assertEquals(MiniGamePauseState.None, c.pauseState)
        }
        assertEquals(4.0 * 60, r.hub.pausedSecondsUsed)
        // 카드 ↔ 3-2-1 만 오가도 찬다: 맥처럼 3-2-1 을 안 세면 이 왕복으로 영영 안 찬다.
        r.hub.togglePause()
        for (i in 0 until 40) {
            r.hub.togglePause() // 3-2-1
            advance(3.0)
            if (!c.isPlaying) break
            r.hub.togglePause() // 취소
        }
        assertFalse(c.isPlaying, "왕복으로 상한을 피했다: ${r.hub.pausedSecondsUsed}초")
    }

    /** 상한: 이미 넘긴 판은 [이어하기] 가 안 풀어 준다. */
    @Test
    fun anOverdueRoundDoesNotThaw() = runTest {
        val (r, c) = started(MiniGameKind.tetris)
        r.hub.togglePause()
        advance(limit + 1)
        r.hub.togglePause()
        assertFalse(c.isPlaying, "상한을 넘긴 판이 풀렸다")
    }

    /** 상한 없음: 플래피·타이밍 바는 10분을 멈춰도 그대로다 — 돌아와 이어 할 수 있다. */
    @Test
    fun noCapForTheGamesThatDiscard() = runTest {
        for (kind in listOf(MiniGameKind.flappy, MiniGameKind.timingBar)) {
            val (r, c) = started(kind)
            r.hub.appDidEnterBackground()
            advance(10.0 * 60)
            r.hub.sceneDidComeForward()
            r.hub.pauseWatchTick()
            assertTrue(c.isPlaying, "$kind: 상한이 판을 없앴다")
            assertEquals(MiniGamePauseState.Paused, c.pauseState)
            r.hub.togglePause()
            assertTrue(r.hub.advanceResumeCountdown())
            assertTrue(r.hub.advanceResumeCountdown())
            assertFalse(r.hub.advanceResumeCountdown())
            assertEquals(MiniGamePauseState.None, c.pauseState)
            assertTrue(c.isPlaying)
            advanceUntilIdle()
            assertEquals(emptyList(), r.submits())
        }
    }

    /** 새 판은 시계가 0 이다. */
    @Test
    fun aNewRoundStartsWithAFreshClock() = runTest {
        val (r, c) = started(MiniGameKind.tetris)
        r.hub.togglePause()
        advance(4.0 * 60)
        r.hub.quitPausedRound()
        assertEquals(TetrisGame.Phase.Result, c.tetris.phase)
        assertEquals(0.0, r.hub.pausedSecondsUsed, "끝난 판의 시계가 남았다")
        advanceUntilIdle()
        c.tap() // 결과 → 새 판
        assertTrue(c.isPlaying)
        r.hub.togglePause()
        advance(4.0 * 60)
        r.hub.pauseWatchTick()
        assertTrue(c.isPlaying, "앞 판의 정지가 새 판 상한에 들어갔다")
    }

    /** 상한 문구는 토큰을 든 판에만 — 오래 나가 있어 토큰이 죽은 판은 '못 올렸어요'이고 제출도 없다. */
    @Test
    fun anExpiredTokenIsToldTheTruthOnTheCap() = runTest {
        val (r, c) = started(MiniGameKind.tetris)
        r.hub.appDidEnterBackground()
        advance(GamesMiniGameHub.pendingSubmitTtlSeconds + 1)
        r.hub.sceneDidComeForward()
        assertFalse(c.isPlaying)
        assertEquals(GamesMiniGameText.submitTokenDead, r.hub.submitNotice, "안 올라간 점수를 기록했다고 말했다")
        advanceUntilIdle()
        assertEquals(emptyList(), r.submits(), "죽은 토큰을 보냈다")
        assertEquals(7L, r.hub.localBest[MiniGameKind.tetris], "로컬 최고는 올라야 한다")
        assertEquals(GamesMiniGameText.submitTokenDead, r.hub.submitNotice, "다음 토큰 선발급이 그 말을 지웠다")
    }

    /** 상한 없는 플래피가 30분 넘게 얼었다 끝나면 '이번 판은 순위에 못 올렸어요'로 끝난다. */
    @Test
    fun aFlappyRoundFrozenPastTheTokenTTLIsToldTheTruth() = runTest {
        val (r, c) = started(MiniGameKind.flappy)
        r.hub.togglePause()
        advance(GamesMiniGameHub.pendingSubmitTtlSeconds + 1)
        r.hub.togglePause()
        r.hub.finishCountdown()
        assertEquals(MiniGamePauseState.None, c.pauseState)
        drive(c, 100.0, 60 * 20) { it.flappy.phase == FlappyGame.Phase.Result }
        assertEquals(FlappyGame.Phase.Result, c.flappy.phase, "전제: 판이 끝났다")
        assertEquals(GamesMiniGameText.submitTokenDead, r.hub.submitNotice)
        advanceUntilIdle()
        assertEquals(emptyList(), r.submits())
    }

    /** 토큰을 기다리는 판에 상한이 오면 '올리는 중'을 '기록했어요'로 덮지 않는다. */
    @Test
    fun aTokenlessRoundKeepsTheRetryingNotice() = runTest {
        val stub = Stub()
        stub.starts += Reply.Offline
        stub.starts += Reply.Offline
        val r = rig(stub)
        r.hub.sleep = { awaitCancellation() }
        r.hub.openScreen(MiniGameKind.tetris)
        advanceUntilIdle()
        assertNull(r.hub.roundToken, "전제: 토큰이 없다")
        val c = assertNotNull(r.hub.controller)
        c.tap()
        c.softDropOneCell()
        advanceUntilIdle()
        assertNull(r.hub.roundTokenInFlightKind)
        r.hub.togglePause()
        advance(limit)
        r.hub.pauseWatchTick()
        assertFalse(c.isPlaying)
        assertEquals(GamesMiniGameText.submitRetrying, r.hub.submitNotice)
        assertNull(r.hub.pendingSubmit?.token)
        assertNotNull(r.hub.pendingSubmit, "점수를 잃었다")
    }

    // MARK: 자동 정지

    /** 앱 내림: ON_PAUSE 에서 이미 언다 · 이미 정지면 그대로 · 3-2-1 이면 취소 · 돌아와도 안 풀린다. */
    @Test
    fun resigningFreezesAndNeverThaws() = runTest {
        for (kind in MiniGameKind.entries) {
            val (r, c) = started(kind)
            r.hub.appWillResignActive()
            assertEquals(MiniGamePauseState.Paused, c.pauseState, "$kind: 앱 전환 화면에 판이 찍힌다")
            r.hub.sceneDidComeForward()
            assertEquals(MiniGamePauseState.Paused, c.pauseState, "$kind: 복귀가 판을 저절로 풀었다")
            advance(30.0)
            r.hub.appWillResignActive()
            r.hub.appDidEnterBackground()
            r.hub.sceneDidComeForward()
            assertEquals(30.0, r.hub.pausedSecondsUsed, "$kind: 이미 정지인데 시계가 되돌아갔다")
            r.hub.togglePause()
            assertEquals(MiniGamePauseState.Resuming(3), c.pauseState)
            r.hub.appDidEnterBackground()
            assertEquals(MiniGamePauseState.Paused, c.pauseState, "$kind: 안 보이는 화면에서 3-2-1 이 흐른다")
            r.hub.sceneDidComeForward()
            assertEquals(MiniGamePauseState.Paused, c.pauseState)
        }
    }

    /** [일시정지]: 판이 안 돌면 안 언다 · 3-2-1 중 누르면 취소 · 다 내려가면 풀린다. */
    @Test
    fun theManualButton() = runTest {
        val r = rig()
        r.hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        val c = assertNotNull(r.hub.controller)
        r.hub.togglePause()
        assertEquals(MiniGamePauseState.None, c.pauseState, "시작 전 화면을 얼렸다 — 탭이 안 먹는 화면이 된다")
        c.tap()
        r.hub.togglePause()
        assertEquals(MiniGamePauseState.Paused, c.pauseState)
        r.hub.togglePause()
        assertEquals(MiniGamePauseState.Resuming(3), c.pauseState)
        r.hub.togglePause()
        assertEquals(MiniGamePauseState.Paused, c.pauseState, "3-2-1 중 정지가 취소가 아니다")
        r.hub.togglePause()
        assertTrue(r.hub.advanceResumeCountdown())
        assertEquals(MiniGamePauseState.Resuming(2), c.pauseState)
        assertTrue(c.isFrozen, "3-2-1 동안 판이 풀렸다")
        assertTrue(r.hub.advanceResumeCountdown())
        assertFalse(r.hub.advanceResumeCountdown())
        assertEquals(MiniGamePauseState.None, c.pauseState)
    }

    /** 3-2-1 코루틴이 실제로 판을 푼다(직접 안 밀어도) — 1초 간격을 그대로 넘긴다. */
    @Test
    fun theCountdownLoopThawsTheRound() = runTest {
        val (r, c) = started(MiniGameKind.flappy)
        val waits = mutableListOf<Double>()
        r.hub.pauseSleep = { waits += it; delay((it * 1000).toLong()) }
        r.hub.togglePause()
        r.hub.togglePause()
        advance(2.5)
        assertEquals(MiniGamePauseState.Resuming(1), c.pauseState, "2.5초면 3 → 2 → 1 까지다")
        assertTrue(c.isFrozen)
        advance(1.0)
        assertEquals(MiniGamePauseState.None, c.pauseState, "3-2-1 이 안 끝난다")
        assertEquals(listOf(1.0, 1.0, 1.0), waits)
    }

    /** 감시 코루틴이 실제로 상한을 집행한다(테트리스) · 플래피에는 감시를 걸지도 않는다. */
    @Test
    fun theWatchLoopEnforcesTheCap() = runTest {
        val (r, c) = started(MiniGameKind.tetris)
        r.hub.pauseSleep = { delay((it * 1000).toLong()) }
        r.hub.togglePause()
        advance(limit - 2)
        assertTrue(c.isPlaying, "상한 전에 끝났다")
        advance(3.0)
        assertFalse(c.isPlaying, "감시가 상한을 집행하지 않는다")
        advanceUntilIdle() // 감시 고리가 거둬졌다 — 안 거뒀으면 여기서 안 끝난다

        val (f, _) = started(MiniGameKind.flappy)
        var calls = 0
        f.hub.pauseSleep = { calls += 1; awaitCancellation() }
        f.hub.togglePause()
        advanceUntilIdle()
        assertEquals(0, calls, "할 일이 없는 게임에 1초 감시를 걸었다")
    }

    /** 화면 꺼짐 방지: 정지 중 해제 · 풀리면 다시. */
    @Test
    fun theIdleTimerIsReleasedWhileFrozen() = runTest {
        val stub = Stub()
        val h = StoreHarness(this, route = stub::route)
        h.signIn()
        val games = GamesStore(h.context)
        games.miniGames.phonePauseRules = true
        games.miniGames.pauseSleep = { awaitCancellation() }
        games.appDidBecomeActive()
        games.miniGames.openScreen(MiniGameKind.tetris)
        advanceUntilIdle()
        val c = assertNotNull(games.miniGames.controller)
        c.tap()
        assertTrue(games.wantsIdleTimerDisabled)
        games.miniGames.togglePause()
        assertFalse(games.wantsIdleTimerDisabled, "정지 카드를 띄운 채 화면이 안 꺼진다")
        games.miniGames.togglePause()
        assertFalse(games.wantsIdleTimerDisabled)
        games.miniGames.finishCountdown()
        assertEquals(MiniGamePauseState.None, c.pauseState)
        assertTrue(games.wantsIdleTimerDisabled)
    }

    /** 스토어의 두 문이 허브에 닿는다 — 앱이 내려가도 판이 안 끝나고, 스토어 자리 API 가 그대로 얼린다. */
    @Test
    fun theStoreEntryPointsReachTheHub() = runTest {
        val stub = Stub()
        val h = StoreHarness(this, route = stub::route)
        h.signIn()
        val games = GamesStore(h.context)
        games.miniGames.phonePauseRules = true
        games.miniGames.pauseSleep = { awaitCancellation() }
        games.appDidBecomeActive()
        games.miniGames.openScreen(MiniGameKind.tetris)
        advanceUntilIdle()
        val c = assertNotNull(games.miniGames.controller)
        c.tap()
        c.softDropOneCell()
        games.sceneWillResignActive()
        assertEquals(MiniGamePauseState.Paused, c.pauseState)
        games.appDidEnterBackground()
        advanceUntilIdle()
        assertTrue(c.isPlaying, "앱을 내렸는데 판이 끝났다")
        assertEquals(0, h.server.count("minigame_submit_score"), "언 판의 토큰이 나갔다")
        assertNull(games.miniGames.submitNotice, "'앱을 나가서…' 는 이제 거짓말이다")
        advanceTimeBy((limit * 1000).toLong())
        games.sceneDidComeForward()
        assertFalse(c.isPlaying, "복귀가 상한을 안 잰다")
    }

    // MARK: 토큰 · 인편 · too_fast (맥 규칙)

    /** 길건너 토큰 갈아 끼우기(`runRoundTokenKeeper`)는 정지 중에도 돈다 · background 면 쉬고 복귀 때 갈아 끼운다. */
    @Test
    fun crossyTokenStaysFreshWhileFrozen() = runTest {
        val stub = Stub()
        val r = rig(stub)
        r.hub.openScreen(MiniGameKind.crossy)
        advanceUntilIdle()
        assertEquals("t1", r.hub.roundToken)
        val c = assertNotNull(r.hub.controller)
        c.tap()
        val keeper = backgroundScope.launch { r.hub.runRoundTokenKeeper(c) }

        // 19분 놀다 언다 → 1분 뒤(토큰 20분) 감시가 갈아 끼운다.
        advance(19.0 * 60)
        r.hub.togglePause()
        advance(1.0)
        assertEquals(1, r.tokensAsked(), "아직 젊은 토큰을 갈아 끼웠다")
        advance(60.0)
        assertEquals("t2", r.hub.roundToken, "정지 중 토큰이 그대로 늙는다")

        // 풀고 18분 반 더 논다 → background 2분(토큰 20분을 넘긴다) → 감시는 쉰다 → 복귀가 갈아 끼운다. 정지 합은 3분이라 상한은 멀다.
        r.hub.togglePause()
        r.hub.finishCountdown()
        assertEquals(MiniGamePauseState.None, c.pauseState)
        advance(18.5 * 60)
        r.hub.appDidEnterBackground()
        advance(2.0 * 60)
        assertEquals(2, r.tokensAsked(), "background 에서 감시가 망을 썼다")
        r.hub.sceneDidComeForward()
        advanceTimeBy(100)
        runCurrent()
        assertEquals("t3", r.hub.roundToken, "복귀가 토큰을 안 갈아 끼웠다")
        assertTrue(c.isPlaying)
        keeper.cancel()
    }

    /** 토큰 불변식: 정지 중이어도 그 게임의 인편이 살아 있으면 새 토큰을 안 받는다. */
    @Test
    fun frozenKeepAliveHonoursThePendingInvariant() = runTest {
        val stub = Stub()
        repeat(20) { stub.submits += Reply.Offline } // 방아쇠마다 되보낸다 — 이 시험 동안 내내 망이 없다
        val r = rig(stub)
        r.hub.sleep = { awaitCancellation() }
        r.hub.openScreen(MiniGameKind.crossy)
        advanceUntilIdle()
        assertEquals("t1", r.hub.roundToken)
        r.hub.recordScore(MiniGameKind.crossy, 3)
        advanceUntilIdle()
        assertTrue(r.submits().isNotEmpty(), "전제: 제출이 실패했다")
        assertNotNull(r.hub.pendingSubmit)
        val c = assertNotNull(r.hub.controller)
        c.tap()
        r.hub.togglePause()
        advance(21.0 * 60)
        r.hub.keepRoundTokenFresh(MiniGameKind.crossy)
        r.hub.sceneDidComeForward()
        advanceUntilIdle()
        assertEquals(1, r.tokensAsked(), "인편의 토큰을 자기 손으로 죽였다")
        assertNotNull(r.hub.pendingSubmit, "전제: 인편이 끝까지 살아 있었다")
    }

    /**
     * too_fast(맥 규칙 — 횟수가 아니라 TTL 이 끝을 낸다): 정지 중 토큰을 갈아 끼운 직후 [그만두기] → 서버는 새 토큰 기준으로 `too_fast` → 인편을 남기고 **같은 토큰으로** 되보내 통과한다.
     * 그동안 새 토큰은 안 받는다(불변식) · 제출이 통과하면 다음 판 토큰을 받는다.
     */
    @Test
    fun tooFastAfterAFrozenRefreshIsRetriedWithTheSameToken() = runTest {
        val stub = Stub()
        stub.submits += Stub.status("too_fast")
        stub.submits += Stub.status("too_fast")
        val r = rig(stub)
        r.hub.openScreen(MiniGameKind.crossy)
        advanceUntilIdle()
        val c = assertNotNull(r.hub.controller)
        c.tap()
        drive(c, 0.0, 30)
        val score = c.score
        r.hub.togglePause()
        advance(20.0 * 60)
        r.hub.keepRoundTokenFresh(MiniGameKind.crossy)
        advanceTimeBy(100)
        runCurrent()
        assertEquals("t2", r.hub.roundToken, "전제: 정지 중 갈아 끼웠다")
        r.hub.quitPausedRound()
        runCurrent()
        assertEquals(1, r.submits().size)
        assertEquals(GamesMiniGameText.submitRetrying, r.hub.submitNotice, "곧 올라갈 점수를 못 올렸다고 말했다")
        assertNotNull(r.hub.pendingSubmit, "too_fast 에 점수를 버렸다")
        advanceUntilIdle()
        assertEquals(3, r.submits().size, "2초 · 8초 뒤 되보낸다")
        assertTrue(r.submits().all { it.hasToken("t2") && it.hasScore(score) }, "${r.submits()}")
        assertNull(r.hub.pendingSubmit)
        assertEquals(3, r.tokensAsked(), "인편이 사는 동안은 0건, 통과한 뒤에 다음 판 토큰 하나")
    }

    /** 맥 규칙: 앞 판의 인편이 사는 동안 얼린 판의 임시 항목은 인편에 안 섞인다 · 각 판이 자기 토큰으로 한 번씩 올라간다. */
    @Test
    fun aPendingSubmitAndAFrozenDraftStaySeparate() = runTest {
        val stub = Stub()
        val gate = CompletableDeferred<Unit>()
        stub.submits += Reply.Gate(gate, Stub.ok)
        val r = rig(stub)
        r.hub.openScreen(MiniGameKind.tetris)
        advanceUntilIdle()
        r.hub.recordScore(MiniGameKind.tetris, 3) // 앞 판 — t1 로 제출이 왕복 중
        runCurrent()
        assertEquals(1, r.submits().size)
        val c = assertNotNull(r.hub.controller)
        c.tap() // 새 판 — 인편이 살아 있어 토큰을 안 받는다
        repeat(4) { c.softDropOneCell() }
        r.hub.appDidEnterBackground()
        runCurrent()
        assertEquals(1, r.tokensAsked(), "인편의 토큰을 죽였다")
        assertEquals(listOf(3), r.hub.pendingSubmits.map { it.score }, "임시 항목이 인편에 섞였다")
        assertNull(r.draft()?.textOf("token"), "이 판은 토큰이 없다 — 앞 판의 토큰을 적으면 그 점수로 두 번 나간다")
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(1, r.submits().size, "앞 판 제출은 한 번이고 언 판은 안 나간다")
        assertTrue(c.isPlaying)
    }

    // MARK: 임시 항목

    /** 내려갈 때 테트리스·길건너만 지금 점수·토큰을 적고 제출은 안 한다. */
    @Test
    fun theDraftIsWrittenOnlyForGamesThatKeepTheScore() = runTest {
        for (kind in MiniGameKind.entries) {
            val (r, c) = started(kind)
            val score = c.score
            r.hub.appDidEnterBackground()
            advanceUntilIdle()
            assertEquals(emptyList(), r.submits(), "$kind: 언 판의 토큰이 나갔다")
            if (GamesMiniGamePausePolicy.quittingKeepsTheScore(kind)) {
                val written = assertNotNull(r.draft(), "$kind: 임시 항목이 없다 — OS 가 앱을 죽이면 점수가 사라진다")
                assertEquals(kind.rawValue, written.textOf("kind"))
                assertEquals(score, written.intOf("score"))
                assertEquals("t1", written.textOf("token"))
                assertNull(r.hub.pendingSubmit, "$kind: 인편에 넣었다 — 밀기가 도는 판의 토큰을 보내 버린다")
            } else {
                assertNull(r.draftText(), "$kind: 접으면 버리는 게임이 적었다")
            }
        }
    }

    /** ON_PAUSE 에서도 적는다(최근 앱 화면에서 바로 쓸어 올려 죽이는 길 — 프로세스 ON_STOP 은 700ms 늦다). */
    @Test
    fun theDraftIsWrittenOnPause() = runTest {
        val (r, _) = started(MiniGameKind.tetris)
        r.hub.appWillResignActive()
        assertNotNull(r.draftText())
    }

    /** 다시 내려가면 그때의 점수·토큰으로 갈아 적는다. */
    @Test
    fun theDraftTracksTheLatestState() = runTest {
        val (r, c) = started(MiniGameKind.tetris)
        r.hub.appDidEnterBackground()
        assertEquals(7, r.draft()?.intOf("score"))
        r.hub.sceneDidComeForward()
        r.hub.togglePause()
        r.hub.finishCountdown()
        repeat(3) { c.softDropOneCell() }
        r.hub.appDidEnterBackground()
        assertEquals(10, r.draft()?.intOf("score"))
    }

    /** 복귀해서 이어 하면 지운다 · 3-2-1 중 다시 내려가면 다시 적는다. */
    @Test
    fun resumingClearsTheDraftAndGoingDownAgainRewritesIt() = runTest {
        val (r, _) = started(MiniGameKind.crossy)
        r.hub.appDidEnterBackground()
        r.hub.sceneDidComeForward()
        assertNotNull(r.draftText(), "돌아와 카드만 보는 동안은 남는다(그 사이 앱이 또 내려갈 수 있다)")
        r.hub.togglePause()
        assertNull(r.draftText(), "이어 하는데 임시 항목이 남았다 — 다음 실행에 옛 점수가 올라간다")
        r.hub.appWillResignActive()
        assertNotNull(r.draftText(), "3-2-1 중에 내려간 판이 다음 실행에 사라진다")
        advanceUntilIdle()
        assertEquals(emptyList(), r.submits())
    }

    /** 프로세스가 죽어 다음 실행에 살아 있으면 **같은 토큰으로** 그 점수를 올린다(부르는 자리: 스토어 appDidBecomeActive). */
    @Test
    fun anOrphanedDraftIsSubmittedOnTheNextLaunch() = runTest {
        val prefs = MemoryPrefs()
        val (first, c) = started(MiniGameKind.tetris, prefs = prefs)
        val score = c.score
        first.hub.appDidEnterBackground()
        assertNotNull(first.draftText())
        first.h.storeScope.cancel() // 프로세스가 죽었다

        val second = StoreHarness(this, prefs = prefs, route = Stub()::route)
        second.signIn()
        val games = GamesStore(second.context)
        games.appDidBecomeActive()
        advanceUntilIdle()
        val bodies = second.server.bodies("minigame_submit_score")
        assertEquals(1, bodies.size, "죽은 앱의 점수가 안 올라갔다")
        assertTrue(bodies[0].hasToken("t1"), "다른 토큰으로 나갔다: ${bodies[0]}")
        assertTrue(bodies[0].hasScore(score))
        assertTrue("\"p_game\":\"tetris\"" in bodies[0])
        assertNull(prefs.getString(GamesMiniGameHub.pauseDraftKey(owner)), "임시 항목이 남았다 — 다음 실행에 또 올라간다")
        assertNull(games.miniGames.pendingSubmit)
        assertTrue(games.miniGames.best(MiniGameKind.tetris) >= score.toLong())
    }

    /** 토큰이 없던 판은 기존 인편 규칙대로 토큰을 받아 올린다. */
    @Test
    fun anOrphanedDraftWithoutATokenWaitsForOne() = runTest {
        val prefs = MemoryPrefs()
        val now = StoreFixtures.clock(this).now().timeIntervalSince1970
        prefs.putString(GamesMiniGameHub.pauseDraftKey(owner), """{"id":0,"kind":"crossy","score":4,"recordedAt":$now}""")
        val stub = Stub()
        val r = rig(stub, prefs)
        r.hub.retryPendingSubmitIfAny()
        advanceUntilIdle()
        assertEquals(1, r.submits().size, "토큰을 기다리는 인편이 안 올라갔다")
        assertTrue(r.submits()[0].hasToken("t1") && r.submits()[0].hasScore(4), r.submits()[0])
        assertNull(r.draftText())
    }

    /** 토큰 수명을 넘긴 채 되살아나면 보내지 않고 다음에 화면을 열 때 말한다 · 로컬 최고는 남는다. */
    @Test
    fun anExpiredOrphanedDraftIsDroppedAndTold() = runTest {
        val prefs = MemoryPrefs()
        val old = StoreFixtures.clock(this).now().timeIntervalSince1970 - (GamesMiniGameHub.pendingSubmitTtlSeconds + 60)
        prefs.putString(GamesMiniGameHub.pauseDraftKey(owner), """{"id":0,"kind":"tetris","score":9,"token":"t-old","tokenIssuedAt":$old,"recordedAt":$old}""")
        val r = rig(Stub(), prefs)
        r.hub.retryPendingSubmitIfAny()
        advanceUntilIdle()
        assertEquals(emptyList(), r.submits(), "죽은 토큰을 보냈다")
        assertNull(r.draftText())
        r.hub.openScreen(MiniGameKind.tetris)
        assertEquals(GamesMiniGameText.submitExpired, r.hub.submitNotice, "그 판이 사라진 것을 아무도 말하지 않는다")
        assertEquals(9L, r.hub.localBest[MiniGameKind.tetris], "로컬 최고까지 잃었다")
    }

    /** 깨진 값은 없는 것으로 친다(앱이 죽거나 제출이 나가지 않는다). */
    @Test
    fun aBrokenDraftIsIgnored() = runTest {
        val prefs = MemoryPrefs()
        prefs.putString(GamesMiniGameHub.pauseDraftKey(owner), "{broken")
        val r = rig(Stub(), prefs)
        r.hub.retryPendingSubmitIfAny()
        advanceUntilIdle()
        assertEquals(emptyList(), r.submits())
        assertNull(r.draftText())
    }

    /** 인편에 적은 뒤 임시 항목을 지우기 전에 또 죽은 자리 — 같은 판을 두 번 줄 세우지 않는다. */
    @Test
    fun anAlreadyAdoptedDraftIsNotQueuedTwice() = runTest {
        val prefs = MemoryPrefs()
        val now = StoreFixtures.clock(this).now().timeIntervalSince1970
        prefs.putString(GamesMiniGameHub.pendingKey(owner), """[{"id":5,"kind":"tetris","score":9,"token":"t-a","tokenIssuedAt":$now,"recordedAt":$now}]""")
        prefs.putString(GamesMiniGameHub.pauseDraftKey(owner), """{"id":0,"kind":"tetris","score":9,"token":"t-a","tokenIssuedAt":$now,"recordedAt":$now}""")
        val r = rig(Stub(), prefs)
        r.hub.retryPendingSubmitIfAny()
        advanceUntilIdle()
        assertEquals(1, r.submits().size, "같은 판이 두 번 나갔다")
        assertNull(r.draftText())
    }

    /** 이중 제출 0: 얼렸다 풀고 정상으로 끝나면 제출은 한 번 · 다음 실행에도 안 올라간다. */
    @Test
    fun noDoubleSubmitAfterANormalEnd() = runTest {
        val prefs = MemoryPrefs()
        val (r, c) = started(MiniGameKind.crossy, prefs = prefs)
        r.hub.appDidEnterBackground()
        r.hub.sceneDidComeForward()
        r.hub.togglePause()
        r.hub.finishCountdown()
        // 정상 종료: 가만히 두면 길건너는 9초에 끝난다.
        drive(c, 100.0, 60 * 20) { it.crossy.phase == CrossyGame.Phase.Result }
        assertEquals(CrossyGame.Phase.Result, c.crossy.phase)
        advanceUntilIdle()
        assertEquals(1, r.submits().size)
        assertNull(r.draftText(), "임시 항목이 남았다")

        val second = StoreHarness(this, prefs = prefs, route = Stub()::route)
        second.signIn()
        GamesStore(second.context).appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(0, second.server.count("minigame_submit_score"), "끝난 판이 다음 실행에 또 올라갔다")
    }

    /** 이중 제출 0: 임시 항목이 있는 채 상한·[그만두기]로 끝나도 제출은 한 번이고 임시 항목은 없다. */
    @Test
    fun noDoubleSubmitWhenEndingWithADraft() = runTest {
        for (byCap in listOf(false, true)) {
            val (r, c) = started(MiniGameKind.tetris)
            r.hub.appDidEnterBackground()
            assertNotNull(r.draftText())
            if (byCap) {
                advance(limit)
                r.hub.sceneDidComeForward()
            } else {
                r.hub.sceneDidComeForward()
                r.hub.quitPausedRound()
            }
            assertFalse(c.isPlaying)
            assertNull(r.draftText(), "진짜 인편과 임시 항목이 둘 다 있다 — 다음 실행에 같은 판이 또 올라간다")
            advanceUntilIdle()
            assertEquals(1, r.submits().size)
        }
    }

    /**
     * 이중 제출 0(제출 · 이어 하기 겹침): [그만두기] 제출이 왕복 중인데 프로세스가 죽었다 → 다음 실행은 **인편에서 같은 토큰으로** 한 번 더 보내고, 서버의 `token_used` 는 성공이다.
     * 임시 항목은 이미 지워져 그 길로는 안 나간다. 서버가 받는 점수는 한 번이다.
     */
    @Test
    fun aSubmitInFlightAtDeathIsResentOnlyFromThePendingQueue() = runTest {
        val prefs = MemoryPrefs()
        val stub = Stub()
        stub.submits += Reply.Hang
        val (r, c) = started(MiniGameKind.tetris, stub, prefs)
        val score = c.score
        r.hub.appDidEnterBackground()
        r.hub.sceneDidComeForward()
        r.hub.quitPausedRound()
        runCurrent()
        assertEquals(1, r.submits().size, "전제: 제출이 왕복 중이다")
        assertNull(r.draftText())
        r.h.storeScope.cancel() // 프로세스가 죽었다

        val nextStub = Stub()
        nextStub.submits += Stub.status("token_used")
        val second = StoreHarness(this, prefs = prefs, route = nextStub::route)
        second.signIn()
        val games = GamesStore(second.context)
        games.appDidBecomeActive()
        advanceUntilIdle()
        val bodies = second.server.bodies("minigame_submit_score")
        assertEquals(1, bodies.size, "$bodies")
        assertTrue(bodies[0].hasToken("t1") && bodies[0].hasScore(score), bodies[0])
        assertNull(games.miniGames.pendingSubmit, "token_used 는 성공이다")
    }

    /** 이 실행에서 적은 임시 항목은 인편으로 올리지 않는다 — 살아 있는 판의 것이다. */
    @Test
    fun aLiveDraftIsNotAdopted() = runTest {
        val (r, _) = started(MiniGameKind.tetris)
        r.hub.appDidEnterBackground()
        r.hub.sceneDidComeForward()
        r.hub.retryPendingSubmitIfAny()
        advanceUntilIdle()
        assertNull(r.hub.pendingSubmit)
        assertNotNull(r.draftText())
        assertEquals(emptyList(), r.submits())
    }

    /** 공개를 끈 사람: 임시 항목도 제출도 없고 로컬 최고만 남는다. */
    @Test
    fun aPrivateRoundWritesNoDraft() = runTest {
        val stub = Stub()
        stub.public = false
        val (r, c) = started(MiniGameKind.tetris, stub)
        val score = c.score
        r.hub.appDidEnterBackground()
        assertNull(r.draftText(), "공개를 껐는데 다음 실행에 올라갈 점수를 적었다")
        assertEquals(score.toLong(), r.hub.localBest[MiniGameKind.tetris])
        advanceUntilIdle()
        assertEquals(emptyList(), r.submits())
    }

    // MARK: 플래피 잠금 · 기본 경로

    /**
     * 사용자 답 "지금처럼 버림"의 잠금 — iOS 가 56962b12 로 넣었다 f4874d5c 로 되돌린 변경이 안드로이드에 안 들어왔다.
     * 플래피를 접는 모든 길(그만두기 · 뒤로 · 판 전환 · 앱 내림 뒤 그만두기)에서 제출 0 · 인편 0 · 임시 항목 0 · 로컬 최고도 안 오른다.
     * 정상으로 끝난 판(게임오버)은 그대로 올라간다(대조 — 위가 공허하지 않다).
     */
    @Test
    fun foldingFlappyNeverRecords() = runTest {
        val exits: List<Pair<String, (Rig) -> Unit>> = listOf(
            "그만두기" to { r -> r.hub.togglePause(); r.hub.quitPausedRound() },
            "뒤로" to { r -> r.hub.closeScreen(MiniGameKind.flappy) },
            "정지 중 뒤로" to { r -> r.hub.togglePause(); r.hub.closeScreen(MiniGameKind.flappy) },
            "판 전환" to { r -> r.hub.togglePause(); r.hub.openScreen(MiniGameKind.timingBar) },
            "앱 내림 뒤 그만두기" to { r -> r.hub.appDidEnterBackground(); r.hub.sceneDidComeForward(); r.hub.quitPausedRound() },
        )
        for ((name, exit) in exits) {
            val (r, c) = started(MiniGameKind.flappy)
            c.replaceForTesting(flappy = FlappyGame(11u, FlappyGame.Bird(60.0, 150.0, 0.0), emptyList(), 5, FlappyGame.Phase.Running))
            assertEquals(5, c.score, "전제: 점수가 있는 판이다")
            exit(r)
            advanceUntilIdle()
            assertEquals(emptyList(), r.submits(), "$name: 플래피를 접었는데 기록했다")
            assertEquals(emptyList(), r.hub.pendingSubmits, name)
            assertNull(r.draftText(), name)
            assertEquals(0L, r.hub.localBest[MiniGameKind.flappy] ?: 0L, "$name: 버린 판이 최고 점수가 됐다")
            assertFalse(c.isPlaying, name)
        }
        // 대조: 언 적이 있어도 정상으로 끝난 판은 올라간다.
        val (r, c) = started(MiniGameKind.flappy)
        r.hub.togglePause()
        r.hub.togglePause()
        r.hub.finishCountdown()
        drive(c, 100.0, 60 * 20) { it.flappy.phase == FlappyGame.Phase.Result }
        assertEquals(FlappyGame.Phase.Result, c.flappy.phase)
        advanceUntilIdle()
        assertEquals(1, r.submits().size, "정상으로 끝난 플래피가 안 올라갔다")
    }

    /** 스위치가 꺼져 있으면(Windows 창의 기본값) 지금까지와 같다 — 구동기는 안 얼고, 앱 내림 문은 판을 끝내고, 문구도 그대로다. */
    @Test
    fun theDefaultHubKeepsTheWindowsBehaviour() = runTest {
        val h = StoreHarness(this, route = Stub()::route)
        h.signIn()
        val hub = GamesMiniGameHub(h.context)
        assertFalse(hub.phonePauseRules, "기본값이 켜지면 Windows 창의 상한 출구가 판을 안 끝낸다")
        hub.openScreen(MiniGameKind.tetris)
        advanceUntilIdle()
        val c = assertNotNull(hub.controller)
        c.tap()
        c.softDropOneCell()
        hub.appDidEnterBackground()
        assertFalse(c.isPlaying, "상한 출구가 판을 안 끝냈다")
        assertEquals(MiniGamePauseState.None, c.pauseState)
        assertEquals(GamesMiniGameText.endedInBackground(MiniGameKind.tetris), hub.submitNotice)
        assertNull(h.prefs.getString(GamesMiniGameHub.pauseDraftKey(owner)))
        advanceUntilIdle()
        assertEquals(1, h.server.count("minigame_submit_score"))

        // 30분 묵은 토큰의 문구도 그대로다(폰만 '못 올렸어요').
        hub.prefetchRoundToken(MiniGameKind.tetris)
        advanceUntilIdle()
        assertNotNull(hub.roundToken)
        advanceTimeBy(((GamesMiniGameHub.pendingSubmitTtlSeconds + 1) * 1000).toLong())
        hub.recordScore(MiniGameKind.tetris, 3)
        assertEquals(GamesMiniGameText.submitExpired, hub.submitNotice)
    }

    // MARK: 문구

    /** 문구: 게임마다 접는 결과대로 말한다 · 맥과 같은 낱말 · 서버 진단이 안 샌다. */
    @Test
    fun theTextsMatchTheTable() {
        assertEquals("일시정지", GamesMiniGameText.pauseTitle)
        assertEquals("이어하기", GamesMiniGameText.resumeAction)
        assertEquals("그만두기", GamesMiniGameText.quitAction)
        assertEquals("5분 넘게 멈춰서 여기까지 기록했어요", GamesMiniGameText.pauseCapEnded)
        for (kind in MiniGameKind.entries) {
            val line = GamesMiniGameText.pauseSubtitle(kind)
            if (GamesMiniGamePausePolicy.quittingKeepsTheScore(kind)) assertTrue("기록돼요" in line, "$kind: 남는 판을 안 남는다고 말한다")
            else assertTrue("기록되지 않아요" in line, "$kind: 버리는 판을 남는다고 말한다")
            assertFalse("token" in line || "서버" in line)
        }
    }
}
