// 원본: Tests/CheckMobileKitTests/GamesTetrisDuelWiringTests.swift:587-606(체스 가지가 꼬리를 끊지 않는다) · GamesTetrisWatchTests.swift:308-335 ·
//       GamesMiniGameHub.swift:94-101(need_seconds 로 지연을 계산하지 않는다) @ 1b8260d — 주석을 걷은 소스 계약(기억 source-contract-tests-need-comment-stripping)
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.testkit.structure.StructureRules
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GamesSourceContractTest {
    private val mpRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")) { "aingcheck.mpRoot 가 없다" })
    private val pkg = "core/stores/src/commonMain/kotlin/com/yehsung/aingcheck/core/stores"

    private fun code(rel: String): String = StructureRules.stripComments(File(mpRoot, "$pkg/$rel").readText())

    /** 함수 몸통(첫 `{` 부터 짝 `}` 까지). */
    private fun body(source: String, signature: String): String {
        val start = source.indexOf(signature)
        check(start >= 0) { "서명 '$signature' 이 없다" }
        val open = source.indexOf('{', start)
        var depth = 0
        for (i in open until source.length) {
            when (source[i]) {
                '{' -> depth += 1
                '}' -> { depth -= 1; if (depth == 0) return source.substring(open, i + 1) }
            }
        }
        error("몸통이 닫히지 않는다: $signature")
    }

    /** 허브는 서버의 `need_seconds`·`elapsed_seconds` 를 **읽지도 않는다**(위조 보조 도구 — 재시도 지연은 눈먼 고정 간격). */
    @Test
    fun theHubNeverReadsTheServersTimingHints() {
        val hub = code("minigame/GamesMiniGameHub.kt")
        assertFalse("needSeconds" in hub, "need_seconds 로 지연을 계산하지 않는다")
        assertFalse("elapsedSeconds" in hub, "elapsed_seconds 를 읽지 않는다")
        assertTrue("tooFastRetryDelaysSeconds" in hub, "대조: 눈먼 지연 표는 있다(정규식이 비지 않았다)")
    }

    /** 관전 갈래는 `tetris_state` 를 **절대 부르지 않는다**(참가자 게이트 — 관전자는 not_found 만 받는다)·관전 응답을 applyState 로 넣지 않는다. */
    @Test
    fun theWatchBranchNeverCallsTheParticipantState() {
        val watch = code("tetris/TetrisDuelStoreWatch.kt")
        assertFalse("tetrisState(" in watch)
        assertFalse("applyState(" in watch)
        assertTrue("tetrisWatchLive(" in watch && "tetrisWatch(" in watch, "대조: 관전 RPC 둘은 부른다")
    }

    /**
     * active 복귀 함수는 체스·오목 가지에서 **꼬리를 끊지 않는다**(early return 0) — 끊으면 꼬리의 테트리스 따라잡기가 화면이 안 보일 때(= 거의 늘)
     * 한 번도 안 돈다. 테트리스 가지가 **마지막**이고 else(`systemDidWake`)를 가진다.
     */
    @Test
    fun becomingActiveNeverCutsTheTail() {
        val active = body(code("games/GamesStore.kt"), "fun appDidBecomeActive()")
        assertEquals(0, Regex("""\breturn\b""").findAll(active).count(), "꼬리를 끊는 return 이 없다")
        val tetris = active.indexOf("val tetris = context.tetris")
        assertTrue(tetris > active.indexOf("val chess = context.chess"), "테트리스 가지가 체스 가지 뒤(꼬리)다")
        assertTrue("tetris.systemDidWake()" in active.substring(tetris), "화면이 안 보이면 systemDidWake")
    }
}
