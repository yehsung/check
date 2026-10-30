// 원본: Sources/check/MiniGamePanel.swift:176-205(키 표) · ★433(뗌 먼저) · contract/golden/tetris/scripted(W1-a — GoldenExportTetris.swift)
// 대본 키열(누름/뗌)을 **창 키 라우터**로 넣고 판 시계를 golden dt 로 민다 → 컨트롤러의 끝 상태·제출 점수가 Swift 엔진 골든과 같아야 한다.
// 키 표(GameKeyMap) · 게이트(miniGameKeys) · 솔로 어댑터(SoloTetrisKeys) · 컨트롤러(공용 패치 4)를 한 줄로 지난다.
package com.yehsung.aingcheck.desktop.windows.games.minigame

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesPlayController
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import com.yehsung.aingcheck.desktop.windows.kit.GameKeyMap
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.coroutines.test.TestScope
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class MiniGameKeyReplayTest {
    /** 대본 연산 → (가상 키, 누름?) 열. 회전·홀드·스페이스는 누른 뒤 바로 뗀다(뗌은 뜻이 없어야 한다 — 그것도 지나간다). */
    private fun strokes(op: String): List<Pair<Int, Boolean>> = when (op) {
        "L+" -> listOf(GameKeyMap.VK_LEFT to true)
        "L-" -> listOf(GameKeyMap.VK_LEFT to false)
        "R+" -> listOf(GameKeyMap.VK_RIGHT to true)
        "R-" -> listOf(GameKeyMap.VK_RIGHT to false)
        "SD+" -> listOf(GameKeyMap.VK_DOWN to true)
        "SD-" -> listOf(GameKeyMap.VK_DOWN to false)
        "CW" -> listOf(GameKeyMap.VK_UP to true, GameKeyMap.VK_UP to false)
        "CCW" -> listOf(GameKeyMap.VK_Z to true, GameKeyMap.VK_Z to false)
        "HOLD" -> listOf(GameKeyMap.VK_C to true, GameKeyMap.VK_C to false)
        "ACT" -> listOf(GameKeyMap.VK_SPACE to true, GameKeyMap.VK_SPACE to false)
        else -> error("모르는 테트리스 연산 '$op'")
    }

    /** golden RLE("n:연산 연산,…") → 프레임별 연산(GoldenOps.decode 와 같은 규칙 — 연산이 있는 항목은 n=1). */
    private fun frames(text: String): List<List<String>> = text.split(',').flatMap { entry ->
        val n = entry.substringBefore(':').toInt()
        val ops = entry.substringAfter(':').split(' ').filter { it.isNotEmpty() }
        require(ops.isEmpty() || n == 1) { "연산 있는 항목이 여러 프레임: $entry" }
        List(n) { ops }
    }

    private class Run(val controller: GamesPlayController, val submitted: List<Int>, val frames: Int, val routed: Int)

    private fun replay(case: JsonObject): Run {
        val store = GamesStore(UiGamesHarness(TestScope(), AppConfig()) { null }.context)
        val state = MiniGameWindowState(store.miniGames)
        state.show(MiniGameKind.tetris) // 창이 판 화면에 있고 초점이 있다 — 게이트가 키를 받는 자리
        val c = GamesPlayController(MiniGameKind.tetris, case.string("seed").removePrefix("0x").toULong(16))
        val submitted = mutableListOf<Int>()
        c.onFinished = { submitted += it }
        val router = ComposeGamesWindows.miniGameKeys({ c }, state)
        val start = case["start"]!!.jsonObject
        require(start.string("kind") == "new" && start.string("preOps") == "ACT") { "새 판 대본만 창으로 잴 수 있다" }
        var routed = 0
        fun press(op: String) = strokes(op).forEach { (vk, down) ->
            if (router.route(vk, down, hasModifiers = false, isRepeat = false, ownsKeys = true)) routed += 1
        }
        press("ACT") // preOps: 시작(스페이스 = 시작 — 판 전이면 탭)
        val dt = Double.fromBits(case.string("dtBits").toULong(16).toLong())
        c.tick(SwiftDate.fromReferenceDate(0.0)) // 기준 프레임(첫 tick 은 기준만 잡는다)
        var n = 0
        for (ops in frames(case.string("ops"))) {
            ops.forEach(::press)
            n += 1
            c.tick(SwiftDate.fromReferenceDate(n * dt)) // dt 가 2의 거듭제곱이라 n·dt 와 차이가 비트 그대로다
            if (c.tetris.phase == TetrisGame.Phase.Result) break
        }
        return Run(c, submitted, n, routed)
    }

    /** A·B — dt 가 2의 거듭제곱(1/64·1/32)인 새 판 대본. E·F 는 dt 가 정확하지 않아 날짜 차로 비트를 못 지키고, C·D·G 는 advance 시작이라 창에서 못 만든다. */
    @Test
    fun scriptedKeyStreamThroughTheWindowMatchesTheSwiftGolden() {
        val golden = Golden.load("tetris/scripted")
        for (id in listOf("A", "B")) {
            val case = golden.case(id)
            val final = case["final"]!!.jsonObject
            val run = replay(case)
            val g = run.controller.tetris
            val held = g.heldPiece?.name?.lowercase()?.first()?.toString() ?: "-"
            val got = mapOf(
                "frames" to run.frames, "score" to g.score, "lines" to g.lines, "advance" to g.advance, "level" to g.level,
                "attackSentTotal" to g.attackSentTotal, "held" to held, "elapsedBits" to Golden.bitsText(g.elapsed),
            )
            val want = mapOf(
                "frames" to final.int("frames"), "score" to final.int("score"), "lines" to final.int("lines"), "advance" to final.int("advance"),
                "level" to final.int("level"), "attackSentTotal" to final.int("attackSentTotal"), "held" to final.string("held"),
                "elapsedBits" to final.string("elapsedBits"),
            )
            assertEquals(want, got, "$id: 창 키열 재생의 끝 상태가 Swift 골든과 갈렸다")
            assertEquals(TetrisGame.Phase.Result, g.phase, "$id: 결과 단계에 들지 않았다")
            // 제출 본문의 점수 = 컨트롤러가 한 번 알린 점수(허브 recordScore → minigame_submit_score). 판 끝은 한 번만.
            assertEquals(listOf(final.int("score")), run.submitted, "$id: 제출 점수가 골든과 다르거나 두 번 알렸다")
            assertTrue(run.routed > 0, "$id: 라우터가 키를 하나도 받지 않았다 — 게이트가 닫혀 헛돈다")
        }
    }

    /** ④ 키 상실 = 정지 + 눌린 키를 놓는다(★433). 놓지 않으면 돌아와서 조각이 저절로 미끄러진다. */
    @Test
    fun focusLostReleasesHeldKeys() {
        val store = GamesStore(UiGamesHarness(TestScope(), AppConfig()) { null }.context)
        val state = MiniGameWindowState(store.miniGames)
        state.show(MiniGameKind.tetris)
        store.miniGames.openScreen(MiniGameKind.tetris)
        val c = requireNotNull(store.miniGames.controller)
        val router = ComposeGamesWindows.miniGameKeys(store, state)
        router.route(GameKeyMap.VK_SPACE, true, false, false, true)
        assertTrue(c.isPlaying, "판이 시작되지 않았다")
        val beforePress = c.tetris.copy()
        router.route(GameKeyMap.VK_LEFT, true, false, false, true)
        val held = c.tetris.copy()
        assertNotEquals(beforePress, held, "누름이 엔진에 닿지 않았다 — 아래 단언이 헛돈다")
        val released = held.copy().also { it.releaseAllKeys() }
        assertNotEquals(held, released, "엔진 등식이 눌림을 안 본다 — 아래 단언이 헛돈다")
        state.apply(listOf(StoreNotice.PauseIfPlaying))
        assertEquals(released, c.tetris, "키 상실인데 ← 가 눌린 채 남았다")
        assertTrue(c.isPlaying, "키 상실이 판을 끝냈다")
    }
}
