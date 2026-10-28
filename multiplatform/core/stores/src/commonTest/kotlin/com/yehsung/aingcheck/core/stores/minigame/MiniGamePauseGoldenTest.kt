// 원본: Tests/checkTests/GoldenExport/duel/GoldenExportPause.swift(생성기) · Sources/check/MiniGamePanel.swift(PauseState) @ 1b8260d
// G §8-2: 미니게임 자동 일시정지 `PauseState` 전이 표 — Swift 와 같은 전이를 Kotlin [MiniGamePauseState] 가 낸다.
package com.yehsung.aingcheck.core.stores.minigame

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import com.yehsung.aingcheck.testkit.golden.stringValue
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals

class MiniGamePauseGoldenTest {
    private val golden = Golden.load("pause/transitions")

    private fun state(name: String): MiniGamePauseState = when {
        name == "none" -> MiniGamePauseState.None
        name == "paused" -> MiniGamePauseState.Paused
        name.startsWith("resuming-") -> MiniGamePauseState.Resuming(name.removePrefix("resuming-").toInt())
        else -> error("모르는 상태 $name")
    }

    private fun name(state: MiniGamePauseState?): JsonElement = when (state) {
        null -> JsonNull
        MiniGamePauseState.None -> JsonPrimitive("none")
        MiniGamePauseState.Paused -> JsonPrimitive("paused")
        is MiniGamePauseState.Resuming -> JsonPrimitive("resuming-${state.remaining}")
    }

    @Test
    fun transitionTableMatchesSwift() {
        val rows = golden.cases.filter { it.containsKey("state") }
        assertEquals(10, rows.size, "상태 5 × 진행 2")
        for (row in rows) {
            val id = row.string("id")
            val s = state(row.string("state"))
            val playing = row["isPlaying"]!!.jsonPrimitive.boolean
            assertEquals(row["toggled"], name(s.toggled(playing)), golden.failure(id, "toggled"))
            assertEquals(row["resigningKey"], name(s.resigningKey(playing)), golden.failure(id, "resigningKey"))
            assertEquals(row["steppedDown"], name(s.steppedDown()), golden.failure(id, "steppedDown"))
            val reads = row.obj("reads")
            assertEquals(reads["isFrozen"], JsonPrimitive(s.isFrozen), golden.failure(id, "isFrozen"))
            assertEquals(reads["showsCard"], JsonPrimitive(s.showsCard), golden.failure(id, "showsCard"))
            assertEquals(reads["countdown"], s.countdown?.let(::JsonPrimitive) ?: JsonNull, golden.failure(id, "countdown"))
        }
    }

    @Test
    fun quittingKeepsTheScoreAndConstantsMatchSwift() {
        val kinds = golden.case("quitting-keeps-the-score").array("kinds").map { it as JsonObject }
        assertEquals(MiniGameKind.entries.map { it.rawValue }, kinds.map { it.string("kind") }, "게임 목록·순서")
        for (k in kinds) {
            val kind = MiniGameKind.fromRawValue(k.string("kind"))!!
            assertEquals(k["keeps"]!!.jsonPrimitive.boolean, MiniGamePauseState.quittingKeepsTheScore(kind), k.string("kind"))
        }
        val constants = golden.case("constants")
        assertEquals(constants.int("countdownStart"), MiniGamePauseState.COUNTDOWN_START)
        assertEquals(constants.int("pauseLimitSeconds"), MiniGamePauseState.PAUSE_LIMIT_SECONDS)
    }

    @Test
    fun eventWalksMatchSwift() {
        val walks = golden.cases.filter { it.string("id").startsWith("walk-") }
        assertEquals(listOf("walk-a", "walk-b"), walks.map { it.string("id") })
        for (walk in walks) {
            var s: MiniGamePauseState = MiniGamePauseState.None
            var playing = false
            val trail = mutableListOf<JsonElement>()
            for (event in walk.array("events").map { it.stringValue() }) {
                when (event) {
                    "toggle" -> s = s.toggled(playing)
                    "resign" -> s = s.resigningKey(playing) ?: s
                    "step" -> s = s.steppedDown()
                    "play" -> playing = true
                    "stop" -> playing = false
                    else -> error(event)
                }
                trail += name(s)
            }
            assertEquals(walk.array("trail").toList(), trail, golden.failure(walk.string("id"), "trail"))
        }
    }
}
