// 원본: Sources/check/MiniGameCrossy.swift @ 1b8260d (CrossyGameView :43-110 — act · tick · onChange(phase) 확정) · MiniGameCrossyScene.swift :496-512(카메라)
//
// 공용 패치 15(core/stores GamesPlayController crossy 구동)를 **구동기를 실제로 지나며** 잰다(시험 자리는 W4-g 소유 ui crossy/ — core/stores
// 시험 폴더는 이 갈래 소유 밖이라 같은 단언을 coordinator 패치로도 낸다). 화면 없이 탭 · 뛰기 · 틱 · 끝 · 정지(틱 없음) · 출구를 몬다.
package com.yehsung.aingcheck.ui.games.minigame.crossy

import com.yehsung.aingcheck.core.rules.minigame.MiniGameFrameRate
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.games.GamesPlayController
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class CrossyPlayControllerTest {
    private fun at(t: Double): SwiftDate = SwiftDate.fromReferenceDate(t)

    private fun controller(seed: ULong = 5uL): Triple<GamesPlayController, MutableList<Int>, IntArray> {
        val c = GamesPlayController(MiniGameKind.crossy, seed)
        val finished = mutableListOf<Int>()
        val started = intArrayOf(0)
        c.onFinished = { finished += it }
        c.onStarted = { started[0] += 1 }
        return Triple(c, finished, started)
    }

    /** 탭 = action(): 시작 전이면 새 판 + 앞으로 한 칸 · onStarted 한 번. 음성 짝: 다른 게임의 구동기는 hop 을 무시한다. */
    @Test
    fun tapStartsTheRoundAndHopsForward() {
        val (c, _, started) = controller()
        assertFalse(c.isPlaying)
        c.tap()
        assertTrue(c.isPlaying, "탭이 판을 켜지 않았다")
        assertEquals(1, started[0], "onStarted 는 판마다 한 번")
        assertEquals(CrossyGame.Direction.forward, c.crossy.hop?.direction, "탭은 앞으로 한 칸이다")
        assertEquals(1, c.tapSerial)
        val flappy = GamesPlayController(MiniGameKind.flappy, 5uL)
        val before = flappy.flappy.copy()
        flappy.hop(CrossyGame.Direction.left)
        assertEquals(before, flappy.flappy, "길건너가 아닌 판을 뛰기가 건드렸다")
        assertEquals(0, flappy.tapSerial)
    }

    /** 방향 뛰기: 시작 전이면 그 방향으로 판을 연다 · 뛰는 중 둘째는 한 칸 줄 서고 셋째는 엔진이 버린다(serial 도 조용). */
    @Test
    fun hopsQueueOneAndDropTheRest() {
        val (c, _, started) = controller()
        c.hop(CrossyGame.Direction.right)
        assertTrue(c.isPlaying)
        assertEquals(1, started[0])
        assertEquals(CrossyGame.Direction.right, c.crossy.hop?.direction)
        c.hop(CrossyGame.Direction.forward)
        assertEquals(CrossyGame.Direction.forward, c.crossy.queued, "뛰는 중 입력이 줄 서지 않았다")
        val serial = c.tapSerial
        c.hop(CrossyGame.Direction.left)
        assertEquals(CrossyGame.Direction.forward, c.crossy.queued, "셋째 입력이 줄을 덮었다")
        assertEquals(serial, c.tapSerial, "버린 입력이 serial 을 올렸다")
    }

    /** 틱 = step(dt): 첫 틱은 기준만, 다음 틱부터 판 시간이 흐른다. 앞으로 간 줄이 점수다. */
    @Test
    fun ticksAdvanceTheEngineAndScoreOnLanding() {
        val (c, _, _) = controller()
        c.tap()
        c.tick(at(10.0))
        assertEquals(0.0, c.crossy.elapsed, "첫 틱이 정지해 있던 시간을 물려받았다")
        var t = 10.0
        repeat(16) { t += 1.0 / 64; c.tick(at(t)) }
        assertEquals(16.0 / 64, c.crossy.elapsed, 1e-12)
        assertEquals(1, c.score, "착지한 줄이 점수가 아니다")
        assertEquals(c.crossy.score, c.score)
    }

    /**
     * 끝: 손을 놓으면 '놓쳤어요' → 죽음 연출(Over) → 결과(Result). 결과 전이에서 **한 번** 알리고, 죽은 순간 gameOverSerial 이 오른다.
     * 결과 뒤 방향키는 엔진이 버리고(판이 안 켜진다), 탭은 새 판이다.
     */
    @Test
    fun deathReportsTheScoreOnceAndArrowsDoNotRestart() {
        val (c, finished, started) = controller()
        c.tap()
        var t = 0.0
        c.tick(at(t))
        var sawOver = false
        repeat(64 * 20) {
            t += 1.0 / 64
            c.tick(at(t))
            if (c.crossy.phase is CrossyGame.Phase.Over) sawOver = true
        }
        assertTrue(sawOver, "죽음 연출을 거치지 않았다")
        assertEquals(CrossyGame.Phase.Result, c.crossy.phase)
        assertEquals(CrossyGame.DeathCause.leftBehind, c.crossy.death?.cause)
        assertEquals(listOf(c.crossy.score), finished, "결과는 판마다 한 번 알린다")
        assertEquals(1, c.gameOverSerial)
        c.hop(CrossyGame.Direction.forward)
        assertFalse(c.isPlaying, "결과 화면의 방향키가 판을 켰다(맥: 다시는 클릭·스페이스뿐)")
        repeat(10) { t += 1.0 / 64; c.tick(at(t)) }
        assertEquals(1, finished.size, "결과 뒤 틱이 다시 알렸다")
        c.tap()
        assertTrue(c.isPlaying, "결과 뒤 탭이 새 판을 열지 않았다")
        assertEquals(2, started[0])
        assertEquals(0, c.score, "새 판 점수가 앞 판을 물려받았다")
    }

    /**
     * 정지(MiniGamePauseState — 화면은 얼어 있는 동안 프레임 루프를 세운다 = 틱 없음): 5초를 쉬고 돌아온 첫 틱도 판은 엔진 maxStep(1/30) 이상
     * 흐르지 않는다. 음성 짝: 엔진 상한을 거치지 않는 dt 였다면 5초가 흘렀을 것이다(같은 dt 를 엔진에 바로 주면 상한에서 잘린다는 것을 함께 잰다).
     */
    @Test
    fun aPauseCostsAtMostOneEngineStep() {
        val (c, _, _) = controller()
        c.tap()
        c.tick(at(0.0))
        c.tick(at(1.0 / 64))
        val before = c.crossy.elapsed
        c.tick(at(5.0))
        val spent = c.crossy.elapsed - before
        assertTrue(spent <= CrossyGame.maxStep + 1e-12, "정지 뒤 첫 틱이 ${spent}초를 흘렸다")
        assertTrue(spent > 0.0, "돌아온 틱이 판을 안 움직였다")
        assertTrue(c.isPlaying, "정지가 판을 끝냈다")
    }

    /** 출구: abandon = 기록 없이 새 판(시작 전) · endRound = 플래피처럼 버림(닫기 = 기록은 데스크톱 창 quittingKeepsTheScore). */
    @Test
    fun exitsAbandonWithoutReporting() {
        val (c, finished, _) = controller()
        c.tap()
        val oldSeed = c.crossy.roundSeed
        assertTrue(c.abandon())
        assertEquals(CrossyGame.Phase.Ready, c.crossy.phase)
        assertNotEquals(oldSeed, c.crossy.roundSeed, "버린 판과 같은 길이 다시 섰다")
        assertTrue(finished.isEmpty())
        c.tap()
        assertEquals(GamesPlayController.EndOutcome.Abandoned, c.endRound())
        assertTrue(finished.isEmpty(), "버림이 점수를 알렸다")
        assertEquals(GamesPlayController.EndOutcome.None, c.endRound(), "진행 중이 아니면 끝낼 판이 없다")
    }

    /** replaceForTesting(crossy:) 는 임의 판에서 시작한다(결과 판이면 이미 알린 것으로 본다). 문구: 결과 줄은 맥 resultSubtitle 그대로. */
    @Test
    fun replaceForTestingAndResultCopy() {
        val (c, finished, _) = controller()
        c.replaceForTesting(crossy = CrossyScenes.end())
        assertEquals(CrossyGame.Phase.Result, c.crossy.phase)
        c.tick(at(1.0))
        assertTrue(finished.isEmpty())
        assertEquals("놓쳤어요 · 최고 9", GamesMiniGameText.crossyResultSubtitle(3, 9, CrossyGame.DeathCause.leftBehind))
        assertEquals("신기록! · 차에 치였어요", GamesMiniGameText.crossyResultSubtitle(12, 9, CrossyGame.DeathCause.car))
        assertEquals("최고 9", GamesMiniGameText.crossyResultSubtitle(9, 9, null))
    }

    /**
     * 주사율이 달라도 같은 판 시각이면 같은 그림 — 가로 카메라는 틱 수가 아니라 판 시간으로 섞는다. 60·75·144Hz 틱 주기(core 표가 고른 목표 fps)로
     * 같은 판(오른쪽 한 칸)을 몰아 0.4초 뒤 카메라가 거의 같다(차 < 0.01칸 — 모형 계산: 판 시간 섞기 0.003 · 틱마다 같은 비율로 섞기 0.107).
     * 같은 판 시각을 다시 그려도(재구성) 카메라가 움직이지 않는다.
     */
    @Test
    fun cameraFollowIsRefreshRateIndependent() {
        fun run(hz: Int): Double {
            val dt = 1.0 / MiniGameFrameRate.targetFPS(hz)
            val g = CrossyGame(5uL)
            val cam = CrossyCameraFollower()
            cam.follow(g)
            g.input(CrossyGame.Direction.right)
            var x = cam.follow(g)
            var t = 0.0
            while (t < 0.4 - 1e-9) {
                g.step(dt)
                t += dt
                x = cam.follow(g)
            }
            assertEquals(x, cam.follow(g), "같은 판 시각을 다시 그렸더니 카메라가 움직였다")
            return x
        }
        val x60 = run(60)
        val x75 = run(75)
        val x144 = run(144)
        assertTrue(x60 > 0.5 && x60 < 0.99, "카메라가 따라가는 중이 아니다($x60) — 아래 단언이 헛돈다")
        assertTrue(abs(x60 - x144) < 0.01 && abs(x60 - x75) < 0.01, "주사율마다 카메라가 갈렸다: 60=$x60 75=$x75 144=$x144")
    }
}
