// 원본: Tests/CheckMobileKitTests/V1015CrossyPhoneTests.swift:29-37·57-90·110-246·277-297 @ 1a5eeca6 (폰 노출 · 구동기 출구 · 쓸기 판정 · 문구)
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.MiniGamePoint
import com.yehsung.aingcheck.core.rules.minigame.MiniGameSize
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import com.yehsung.aingcheck.core.stores.minigame.MiniGameExposure
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GamesCrossyGestureTest {
    private fun at(t: Double): SwiftDate = SwiftDate.fromReferenceDate(t)

    /** 뛰기가 끝날 때까지 돌린다 — 뛰는 중 입력은 엔진이 **줄 세우기**로 받으므로 문턱을 재려면 먼저 땅에 서 있어야 한다. 돌아온 값은 다음 시각. */
    private fun settle(c: GamesPlayController, from: Double): Double {
        var t = from
        c.tick(at(t))
        var frames = 0
        while (c.crossy.hop != null && frames < 60) {
            t += 1.0 / 64
            c.tick(at(t))
            frames += 1
        }
        return t
    }

    private fun drive(c: GamesPlayController, from: Double, frames: Int): Double {
        var t = from
        c.tick(at(t))
        repeat(frames) {
            t += 1.0 / 64
            c.tick(at(t))
        }
        return t
    }

    private fun started(seed: ULong): GamesPlayController = GamesPlayController(MiniGameKind.crossy, seed).also { it.tap() }

    @Test
    fun crossyIsVisibleOnThePhone() {
        assertEquals(listOf(MiniGameKind.timingBar, MiniGameKind.flappy, MiniGameKind.tetris, MiniGameKind.crossy), MiniGameKind.phoneCases, "폰 목록 순서는 entries 그대로다")
        assertTrue(MiniGameKind.crossy.isPhoneSupported)
        assertTrue(MiniGameKind.crossy in MiniGameExposure.visible, "증거 골든이 있는데 폰 노출에서 빠졌다")
        assertEquals(MiniGameExposure.visible, MiniGameExposure.desktopVisible, "폰에 열린 뒤로 두 목록은 같다")
    }

    @Test
    fun theTrackerGateLivesInOnePlace() {
        assertTrue(MiniGameKind.tetris.usesCanvasDragTracker && MiniGameKind.crossy.usesCanvasDragTracker)
        assertFalse(MiniGameKind.timingBar.usesCanvasDragTracker || MiniGameKind.flappy.usesCanvasDragTracker)
        // 트래커를 안 쓰는 게임에 끌기를 넘겨도 아무 일이 없다(래치가 그 둘의 조작 전부다).
        val flappy = GamesPlayController(MiniGameKind.flappy, 25uL)
        flappy.canvasDragChanged(MiniGamePoint(0.0, 0.0), MiniGameSize(0.0, -60.0), at(0.0))
        assertFalse(flappy.isPlaying)
        assertFalse(flappy.canvasDragEnded(MiniGameSize(0.0, 0.0), at(0.0)))
    }

    /** background·뒤로가기 = 그 점수로 확정 — `interrupt()` 뒤에는 tick 이 다시 오지 않으므로 여기서 알려야 한다. 두 번 부르면 아무것도 안 한다. */
    @Test
    fun endRoundConfirmsTheScore() {
        val c = GamesPlayController(MiniGameKind.crossy, 12uL)
        val finished = mutableListOf<Int>()
        c.onFinished = { finished += it }
        assertEquals(GamesPlayController.EndOutcome.None, c.endRound(), "시작 전인데 끝냈다고 한다")
        c.tap()
        drive(c, 1.0, 20)
        val score = c.score
        assertTrue(score >= 1, "전제: 점수가 올라 있다(확정이 0점이면 무엇도 못 잰다)")
        assertEquals(GamesPlayController.EndOutcome.Confirmed(score), c.endRound(), "길건너 판이 버려졌다 — 움직이는 게임을 무한 일시정지할 수 있다")
        assertEquals(listOf(score), finished, "확정했다면서 알리지 않았다")
        assertEquals(CrossyGame.Phase.Result, c.crossy.phase)
        assertFalse(c.isPlaying)
        assertEquals(GamesPlayController.EndOutcome.None, c.endRound())
        assertEquals(listOf(score), finished, "판마다 한 번")
    }

    /** abandon = 기록 없이 버린다(로그아웃·화면 경합). `interrupt()` 는 확정이라 버릴 때 쓰면 안 된다 — Ready 가 갈아 끼웠다는 증거다. */
    @Test
    fun abandonDoesNotReport() {
        val c = GamesPlayController(MiniGameKind.crossy, 13uL)
        val finished = mutableListOf<Int>()
        c.onFinished = { finished += it }
        assertFalse(c.abandon(), "시작 전인데 버렸다고 한다")
        c.tap()
        drive(c, 1.0, 20)
        assertTrue(c.abandon())
        assertEquals(CrossyGame.Phase.Ready, c.crossy.phase)
        assertEquals(0, c.crossy.score)
        drive(c, 2.0, 120)
        assertTrue(finished.isEmpty(), "버린 판을 끝났다고 알렸다 → 제출된다")
    }

    @Test
    fun theSwipeThresholdIsTwentyPoints() {
        val c = started(21uL)
        val t = settle(c, 1.0)
        val before = c.crossy.hopCount
        val finger = MiniGamePoint(100.0, 200.0)
        c.canvasDragChanged(finger, MiniGameSize(0.0, -19.0), at(t))
        assertEquals(before, c.crossy.hopCount, "문턱(20) 아래인데 뛰었다")
        assertNull(c.crossy.queued)
        c.canvasDragChanged(finger, MiniGameSize(0.0, -20.0), at(t))
        assertEquals(before + 1, c.crossy.hopCount, "문턱을 넘었는데 안 뛰었다 — 떼기를 기다리면 늦다")
        assertEquals(CrossyGame.Direction.forward, c.crossy.player.facing, "화면 위로 쓸었는데 앞으로 안 간다")
    }

    @Test
    fun oneContactMakesExactlyOneCell() {
        val c = started(22uL)
        val t = settle(c, 1.0)
        val finger = MiniGamePoint(50.0, 50.0)
        c.canvasDragChanged(finger, MiniGameSize(0.0, -24.0), at(t))
        val after = c.crossy.hopCount
        for (distance in listOf(-40.0, -120.0, -400.0)) c.canvasDragChanged(finger, MiniGameSize(0.0, distance), at(t))
        assertEquals(after, c.crossy.hopCount, "한 번의 쓸기가 여러 칸을 냈다")
        assertNull(c.crossy.queued, "두 번째 칸이 줄에 섰다")
        assertFalse(c.canvasDragEnded(MiniGameSize(0.0, -400.0), at(t)), "한 칸을 낸 접촉은 탭이 아니다 — 한 번 쓸기가 두 칸이 된다")
        // 손을 떼면 새 접촉은 다시 받는다.
        val next = settle(c, t)
        c.canvasDragChanged(MiniGamePoint(51.0, 50.0), MiniGameSize(0.0, -30.0), at(next))
        assertEquals(after + 1, c.crossy.hopCount, "새 접촉인데 안 받았다 — 소진 표시가 굳었다")
    }

    /** 끌기 끝이 안 온 접촉(시스템 제스처 취소) 뒤에도 다음 접촉은 산다 — 시작점이 달라 새 접촉이다. */
    @Test
    fun aCancelledContactDoesNotKillTheNextSwipe() {
        val t = CrossyGestureTracker()
        assertEquals(CrossyGame.Direction.left, t.drag(MiniGamePoint(10.0, 10.0), MiniGameSize(-30.0, 0.0)))
        assertTrue(t.isSpent)
        assertEquals(CrossyGame.Direction.right, t.drag(MiniGamePoint(11.0, 10.0), MiniGameSize(30.0, 0.0)), "끝이 안 온 접촉의 소진 표시가 새 접촉을 죽였다")
    }

    @Test
    fun aDiagonalDragPicksOneAxis() {
        fun facing(dx: Double, dy: Double, seed: ULong): CrossyGame.Direction {
            val c = started(seed)
            val t = settle(c, 1.0)
            val before = c.crossy.hopCount
            c.canvasDragChanged(MiniGamePoint(10.0, 10.0), MiniGameSize(dx, dy), at(t))
            assertEquals(before + 1, c.crossy.hopCount, "대각 끌기가 한 칸도 안 냈다($dx, $dy)")
            assertNull(c.crossy.queued, "두 방향이 같이 나갔다")
            return c.crossy.player.facing
        }
        assertEquals(CrossyGame.Direction.forward, facing(30.0, -40.0, 31uL), "세로가 큰데 옆으로 갔다")
        assertEquals(CrossyGame.Direction.left, facing(-40.0, 30.0, 32uL), "가로가 큰데 세로로 갔다")
        assertEquals(CrossyGame.Direction.right, facing(40.0, 30.0, 33uL))
        assertEquals(CrossyGame.Direction.forward, facing(30.0, -30.0, 34uL), "45° 쓸기가 옆으로 갔다")
        assertEquals(CrossyGame.Direction.back, facing(30.0, 30.0, 35uL))
    }

    @Test
    fun aTapGoesForwardAndRestarts() {
        val c = started(23uL)
        val t = settle(c, 1.0)
        val before = c.crossy.hopCount
        val finger = MiniGamePoint(70.0, 70.0)
        c.canvasDragChanged(finger, MiniGameSize(2.0, 3.0), at(t))
        assertEquals(before, c.crossy.hopCount, "8 도 안 움직였는데 쓸기로 봤다")
        assertTrue(c.canvasDragEnded(MiniGameSize(2.0, 3.0), at(t + 0.1)))
        assertEquals(before + 1, c.crossy.hopCount, "탭이 앞으로 한 칸을 안 냈다")
        assertEquals(CrossyGame.Direction.forward, c.crossy.player.facing)
        // 죽은 구간(8 이상 20 미만)은 의도한 것이다.
        val again = settle(c, t)
        val count = c.crossy.hopCount
        val slow = MiniGamePoint(90.0, 90.0)
        c.canvasDragChanged(slow, MiniGameSize(0.0, -12.0), at(again))
        assertFalse(c.canvasDragEnded(MiniGameSize(0.0, -12.0), at(again)))
        assertEquals(count, c.crossy.hopCount, "죽은 구간이 동작을 냈다")
        // 느린 탭(0.25초 넘김)도 아무 일이 없다.
        c.canvasDragChanged(MiniGamePoint(91.0, 90.0), MiniGameSize(1.0, 1.0), at(again))
        assertFalse(c.canvasDragEnded(MiniGameSize(1.0, 1.0), at(again + 0.3)))
        assertEquals(count, c.crossy.hopCount, "느린 탭이 뛰었다")
        // 결과 카드: 탭 한 번이 새 판이다(화면의 시작 래치가 tap() 을 부른다).
        c.endRound()
        assertEquals(CrossyGame.Phase.Result, c.crossy.phase)
        c.tap()
        assertTrue(c.isPlaying, "결과 카드의 탭이 새 판을 안 열었다")
    }

    /** 쓸기가 판을 켜면 라운드 토큰 뒷정리를 못 지나 점수가 조용히 사라진다. 결과 화면의 쓸기도 같다. */
    @Test
    fun aSwipeNeverStartsARound() {
        val c = GamesPlayController(MiniGameKind.crossy, 24uL)
        var startedCount = 0
        c.onStarted = { startedCount += 1 }
        c.canvasDragChanged(MiniGamePoint(5.0, 5.0), MiniGameSize(0.0, -60.0), at(0.0))
        assertFalse(c.isPlaying, "쓸기가 판을 켰다")
        assertEquals(0, startedCount)
        assertEquals(CrossyGame.Phase.Ready, c.crossy.phase)
        // 기준선: 데스크톱 방향키 문(hop)은 시작 전이면 판을 연다 — 두 문의 뜻이 갈린다.
        c.hop(CrossyGame.Direction.forward)
        assertTrue(c.isPlaying)
        assertEquals(1, startedCount)
    }

    /** 새 판의 첫 칸은 앞 접촉의 소진 표시를 물려받지 않는다(resetGesture 가 두 트래커를 다 비운다). */
    @Test
    fun aNewRoundForgetsThePreviousContact() {
        val c = started(26uL)
        val t = settle(c, 1.0)
        val finger = MiniGamePoint(40.0, 40.0)
        c.canvasDragChanged(finger, MiniGameSize(0.0, -30.0), at(t))
        c.endRound()
        c.tap() // 새 판
        val next = settle(c, t + 1)
        val before = c.crossy.hopCount
        c.canvasDragChanged(finger, MiniGameSize(0.0, -30.0), at(next))
        assertEquals(before + 1, c.crossy.hopCount, "앞 판 접촉의 소진 표시가 새 판 쓸기를 먹었다")
    }

    @Test
    fun thePhoneCopyTellsTheTruth() {
        assertEquals(GamesMiniGameText.endedInBackground(MiniGameKind.tetris), GamesMiniGameText.endedInBackground(MiniGameKind.crossy), "길건너는 확정 쪽이다")
        assertTrue("기록했어요" in GamesMiniGameText.endedInBackground(MiniGameKind.crossy))
        assertTrue("기록하지 않았어요" in GamesMiniGameText.endedInBackground(MiniGameKind.flappy), "버리는 두 게임은 그대로다")
        val howTo = GamesMiniGameText.howToPlay(MiniGameKind.crossy)
        assertEquals(MiniGameKind.crossy.howToPlay + "\n쓸어서 그 방향으로 한 칸 · 탭하면 앞으로 한 칸", howTo)
        assertFalse("방향키" in howTo || "클릭" in howTo, "맥 키보드 안내가 폰에 나갔다")
        assertEquals("길건너 아잉이 게임 화면 — 탭해서 앞으로 · 쓸어서 그 방향으로", GamesMiniGameText.canvasAccessibility(MiniGameKind.crossy))
        // Windows 글자는 그대로다(키보드가 있다).
        assertEquals("길건너 아잉이 게임 화면 — 방향키로 뛰기", GamesMiniGameText.crossyDesktopCanvasAccessibility())
        assertEquals("클릭 · 스페이스 · 방향키로 시작", GamesMiniGameText.crossyStartAction)
    }
}
