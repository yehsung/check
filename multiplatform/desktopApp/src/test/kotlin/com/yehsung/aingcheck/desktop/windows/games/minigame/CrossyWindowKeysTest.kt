// 원본: Sources/check/MiniGamePanel.swift:197-205(hopDirection) · :279-296(뛰기 가지 — 테트리스 가지보다 앞) · :999(wantsHops = 길건너 ∧ ¬얼음)
//       contract/golden/crossy/scripted(W1-a — GoldenExportCrossy.swift 의 대본 다섯: 차·강·떠내려감·기차·놓침)
//
// 길건너를 **창 키**로 논다: 대본 연산(F·B·L·R·ACT)을 가상 키(↑·↓·←·→·스페이스)로 바꿔 창 키 라우터(miniGameKeys)에 넣고 판 시계를 민다 →
// 구동기(공용 패치 15)의 끝 판이 같은 연산을 엔진에 바로 준 판과 **난수까지** 같다(엔진 자체가 Swift 골든과 비트로 같다는 것은 CrossyGoldenTest).
// dt 는 1/64(2의 거듭제곱)라 n·dt 의 날짜 차가 비트 그대로다 — 골든 dt(1/60)는 날짜 차로 비트를 못 지킨다(MiniGameKeyReplayTest 와 같은 이유).
package com.yehsung.aingcheck.desktop.windows.games.minigame

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesPlayController
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.minigame.MiniGameExposure
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.windows.kit.GameKeyMap
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.hex64
import com.yehsung.aingcheck.testkit.golden.string
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import kotlinx.coroutines.test.TestScope
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CrossyWindowKeysTest {
    private val dt = 1.0 / 64

    private fun state(kinds: List<MiniGameKind> = DesktopMiniGameExposure.visible): MiniGameWindowState {
        val store = GamesStore(UiGamesHarness(TestScope(), AppConfig()) { null }.context)
        return MiniGameWindowState(store.miniGames, visibleKinds = kinds)
    }

    /** golden RLE("n:연산 연산,…") → 프레임별 연산(core/rules 시험 GoldenOps.decode 와 같은 규칙 — n 프레임마다 같은 연산). */
    private fun frames(text: String): List<List<String>> = text.split(',').flatMap { entry ->
        val n = entry.substringBefore(':').toInt()
        require(n > 0) { "RLE 개수가 0 이하: $entry" }
        val ops = entry.substringAfter(':').split(' ').filter { it.isNotEmpty() }
        List(n) { ops }
    }

    private fun vk(op: String): Int = when (op) {
        "F" -> GameKeyMap.VK_UP
        "B" -> GameKeyMap.VK_DOWN
        "L" -> GameKeyMap.VK_LEFT
        "R" -> GameKeyMap.VK_RIGHT
        "ACT" -> GameKeyMap.VK_SPACE
        else -> error("창 키가 없는 연산 '$op'")
    }

    /** 대본 다섯을 창 키로 재생 = 엔진 직접 재생(구동기의 '첫 틱은 기준' 규칙까지 같은 한 벌). 끊기(INT)는 창 키가 아니라 거기서 멈춘다. */
    @Test
    fun scriptedHopsThroughTheWindowEqualTheEngine() {
        val golden = Golden.load("crossy/scripted")
        var routedTotal = 0
        for (case in golden.cases) {
            val id = case.string("id")
            val seed = case.hex64("seed")
            val s = state()
            s.show(MiniGameKind.crossy)
            assertEquals(MiniGameWindowRoute.Game(MiniGameKind.crossy), s.route, "$id: 데스크톱 창이 길건너를 열지 않았다")
            val c = GamesPlayController(MiniGameKind.crossy, seed)
            val reported = mutableListOf<Int>()
            c.onFinished = { reported += it }
            val router = ComposeGamesWindows.miniGameKeys({ c }, s)
            val ref = CrossyGame(seed)
            var primed = false
            val refReported = mutableListOf<Int>()
            var n = 0
            loop@ for (ops in frames(case.string("ops"))) {
                if ("INT" in ops) break@loop
                val refWasPlaying = ref.isPlaying
                for (op in ops) {
                    if (router.route(vk(op), true, hasModifiers = false, isRepeat = false, ownsKeys = true)) routedTotal += 1
                    router.route(vk(op), false, hasModifiers = false, isRepeat = false, ownsKeys = true)
                    when (op) {
                        "F" -> ref.input(CrossyGame.Direction.forward)
                        "B" -> ref.input(CrossyGame.Direction.back)
                        "L" -> ref.input(CrossyGame.Direction.left)
                        "R" -> ref.input(CrossyGame.Direction.right)
                        "ACT" -> ref.action()
                    }
                }
                if (!refWasPlaying && ref.isPlaying) primed = false
                n += 1
                c.tick(SwiftDate.fromReferenceDate(n * dt))
                val wasResult = ref.phase == CrossyGame.Phase.Result
                if (!ref.isPlaying) primed = false else if (!primed) primed = true else ref.step(dt)
                if (!wasResult && ref.phase == CrossyGame.Phase.Result) refReported += ref.score
            }
            assertEquals(ref, c.crossy, "$id: 창 키 재생 판이 엔진 직접 재생과 갈렸다(점수 ${c.crossy.score} vs ${ref.score})")
            assertEquals(refReported, reported, "$id: 끝 알림이 엔진 결과 전이와 다르다")
            assertTrue(n > 100, "$id: 대본이 너무 짧다 — 위 단언이 헛돈다")
        }
        assertTrue(routedTotal > 50, "라우터가 키를 거의 안 받았다($routedTotal) — 게이트가 닫혀 헛돈다")
    }

    /**
     * 게이트(맥 :285-295): 뗌은 삼키기만 · 조합키는 흘림 · OS 반복은 삼키기만(한 칸 아님) · 남의 창 키는 흘림 · 얼어 있으면(정지 카드 · 3-2-1)
     * 뛰기 가지를 타지 않는다(wantsHops 거짓) · 기본 창 목록(폰 노출)이면 길건너 판 화면이 없어 게이트가 닫힌다.
     */
    @Test
    fun hopGateFollowsTheMacRules() {
        val s = state()
        s.show(MiniGameKind.crossy)
        val c = GamesPlayController(MiniGameKind.crossy, 3uL)
        val router = ComposeGamesWindows.miniGameKeys({ c }, s)
        assertTrue(router.route(GameKeyMap.VK_D, true, false, false, true), "D(오른쪽) 누름을 삼키지 않았다")
        assertEquals(CrossyGame.Direction.right, c.crossy.hop?.direction, "D 가 오른쪽 뛰기가 아니다")
        val afterFirst = c.crossy.copy()
        assertTrue(router.route(GameKeyMap.VK_D, false, false, false, true), "뗌을 삼키지 않았다(짝 잃은 뗌)")
        assertTrue(router.route(GameKeyMap.VK_W, true, false, true, true), "반복은 삼켜야 한다")
        assertEquals(afterFirst, c.crossy, "OS 키 반복이 뛰기가 됐다")
        assertFalse(router.route(GameKeyMap.VK_W, true, true, false, true), "조합키(Ctrl+W 등)를 삼켰다")
        assertFalse(router.route(GameKeyMap.VK_W, true, false, false, false), "남의 창 키를 삼켰다")
        assertEquals(afterFirst, c.crossy, "게이트 밖 키가 판을 움직였다")
        // 양성 짝: 같은 W 를 게이트 안에서 누르면 줄 선다.
        assertTrue(router.route(GameKeyMap.VK_W, true, false, false, true))
        assertEquals(CrossyGame.Direction.forward, c.crossy.queued, "게이트 안 W 가 줄 서지 않았다 — 위 음성 단언이 헛돈다")
        // ESC = 정지 토글(판 중) → 얼면 뛰기 가지를 타지 않는다.
        assertTrue(router.route(GameKeyMap.VK_ESCAPE, true, false, false, true), "판 중 ESC 를 삼키지 않았다")
        assertEquals(1, s.pauseToggleSerial)
        s.frozen = true
        val frozen = c.crossy.copy()
        assertFalse(router.route(GameKeyMap.VK_LEFT, true, false, false, true), "얼어 있는데 뛰기 키를 삼켰다")
        assertEquals(frozen, c.crossy, "얼어 있는데 판이 뛰었다")
        // 기본(폰 노출) 창 목록: 길건너를 열면 허브에 남고 게이트가 닫힌다(조립이 desktop 목록을 건네기 전 — 빈 판 방지).
        val phone = state(MiniGameExposure.visible)
        phone.show(MiniGameKind.crossy)
        assertEquals(MiniGameWindowRoute.Hub, phone.route)
        assertFalse(ComposeGamesWindows.miniGameKeys({ c }, phone).route(GameKeyMap.VK_UP, true, false, false, true))
    }

    /** 데스크톱 목록 = 폰 노출 + 길건너(증거 골든이 있을 때만) · 순서는 MiniGameKind 순. 음성 짝: 폰 노출에는 길건너가 없다. */
    @Test
    fun desktopExposureAddsOnlyCrossy() {
        assertEquals(MiniGameExposure.visible + MiniGameKind.crossy, DesktopMiniGameExposure.visible)
        assertFalse(MiniGameKind.crossy in MiniGameExposure.visible, "폰 노출에 길건너가 들어왔다(Android 동작 변화)")
    }
}
