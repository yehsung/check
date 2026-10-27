// 원본: Tests/checkTests/GoldenExport/games-tetris-minigame/GoldenExportMiniGames.swift(framerate/fps · framerate/engine 생성기) @ 1b8260d
package com.yehsung.aingcheck.core.rules.minigame

import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.string
import com.yehsung.aingcheck.testkit.golden.stringValue
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** MiniGameEngine 공용 값: 프레임률(0~500Hz 전수 — C§5.1 E6) · 게임 종류 표 · 캔버스 변환 · 뛰기 입력 꼬리 · 무대 고르기. */
class MiniGameEngineGoldenTest {

    @Test
    fun frameRateMatchesSwiftForEveryRefreshRate() {
        val golden = Golden.load("framerate/fps")
        val f = GoldenFailures(golden)
        val hz = golden.case("hz")
        val from = hz.int("from")
        val fps = GoldenOps.ints(hz.string("targetFPS"))
        val intervals = GoldenOps.bits(hz.string("minimumIntervalBits"))
        fps.forEachIndexed { i, w ->
            val rate = from + i
            val got = MiniGameFrameRate.targetFPS(rate)
            f.check("hz", got == w) { "$rate Hz: 기대 $w · Kotlin $got" }
            val interval = MiniGameFrameRate.minimumInterval(rate)
            f.check("hz", interval.toRawBits() == intervals[i].toRawBits()) { "$rate Hz 간격: 기대 ${intervals[i]} · Kotlin $interval" }
        }
        val c = golden.case("constants")
        f.check("constants", MiniGameFrameRate.baselineFPS == c.int("baselineFPS") && MiniGameFrameRate.maxFPS == c.int("maxFPS") &&
            MiniGameFrameRate.minFPS == c.int("minFPS") && MiniGameFrameRate.minPlausibleHz == c.int("minPlausibleHz") &&
            MiniGameFrameRate.vsyncHeadroom.toRawBits() == Golden.bits(c.string("vsyncHeadroomBits")).toRawBits()) { "상수" }
        f.assertNone()
        assertEquals(506, fps.size, "−5…500Hz 전수가 아니다")
    }

    private fun boolOf(e: JsonElement?): Boolean = (e as JsonPrimitive).boolean

    @Test
    fun kindTableMatchesSwift() {
        val golden = Golden.load("framerate/engine")
        val f = GoldenFailures(golden)
        val kinds = golden.case("kinds")
        f.check("kinds", MiniGameKind.entries.joinToString(" ") { it.rawValue } == kinds.string("allCases")) { "allCases 순서" }
        f.check("kinds", MiniGameKind.macCases.joinToString(" ") { it.rawValue } == kinds.string("macCases")) { "macCases" }
        f.check("kinds", MiniGameKind.phoneCases.joinToString(" ") { it.rawValue } == kinds.string("phoneCases")) { "phoneCases" }
        f.check("kinds", MiniGameKind.controlHint == kinds.string("sharedControlHint")) { "공용 조작 안내" }
        val table = kinds.array("table").map { it as JsonObject }
        f.check("kinds", table.size == MiniGameKind.entries.size) { "종류 수" }
        for ((row, kind) in table.zip(MiniGameKind.entries)) {
            fun check(name: String, ok: Boolean) = f.check("kinds", ok) { "${kind.rawValue}.$name" }
            check("rawValue", kind.rawValue == row.string("rawValue"))
            check("id", kind.id == row.string("id"))
            check("title", kind.title == row.string("title"))
            check("icon", kind.icon == row.string("icon"))
            check("maxScore", kind.maxScore == row.int("maxScore"))
            check("roundTokenReuseSeconds", kind.roundTokenReuseSeconds.toRawBits() == Golden.bits(row.string("roundTokenReuseSecondsBits")).toRawBits())
            val mid = row["roundTokenMidRunRefreshSecondsBits"]
            check("roundTokenMidRunRefreshSeconds",
                if (mid == null || mid is JsonNull) kind.roundTokenMidRunRefreshSeconds == null
                else kind.roundTokenMidRunRefreshSeconds?.toRawBits() == Golden.bits(mid.stringValue()).toRawBits())
            check("howToPlay", kind.howToPlay == row.string("howToPlay"))
            check("controlHint", kind.controlHint == row.string("controlHint"))
            check("isPhoneSupported", kind.isPhoneSupported == boolOf(row["isPhoneSupported"]))
            check("fromRawValue", MiniGameKind.fromRawValue(kind.rawValue) == kind)
        }
        // INV-MiniGameEngine-6af97b9b: 테트리스 종류 상한 = 엔진 상한(글자 하나까지). 골든이 둘을 Swift 값으로 묶고 여기서 Kotlin 둘을 묶는다.
        f.check("kinds", MiniGameKind.tetris.maxScore == TetrisGame.maxScore) { "MiniGameKind.tetris.maxScore ≠ TetrisGame.maxScore" }
        f.check("kinds", MiniGameKind.crossy.maxScore == CrossyGame.maxScore && MiniGameKind.flappy.maxScore == FlappyGame.maxScore) { "종류 상한 ≠ 엔진 상한" }
        f.check("kinds", MiniGameKind.fromRawValue("chess") == null) { "모르는 종류를 접었다" }

        val canvas = golden.case("canvas")
        val (lw, lh) = GoldenOps.bits(canvas.string("logicalBits"))
        f.check("canvas", MiniGameCanvas.logicalWidth == lw && MiniGameCanvas.logicalHeight == lh) { "논리 크기" }
        for (e in canvas.array("transforms")) {
            val t = e as JsonObject
            val (w, h) = GoldenOps.bits(t.string("sizeBits"))
            val want = GoldenOps.bits(t.string("resultBits"))
            val (scale, origin) = MiniGameCanvas.transform(MiniGameSize(w, h), MiniGameCanvas.logicalSize)
            val got = listOf(scale, origin.x, origin.y)
            f.check("canvas", got.map { it.toRawBits() } == want.map { it.toRawBits() }) { "$w×$h: 기대 $want · Kotlin $got" }
        }

        val hops = golden.case("hops")
        f.check("hops", MiniGameInput.recentHopLimit == hops.int("recentHopLimit")) { "recentHopLimit" }
        var input = MiniGameInput()
        for (step in hops.string("steps").split(' ')) {
            if (step.startsWith("R")) {
                input = input.recordHop(CrossyGame.Direction.entries.first { it.rawValue == step.removePrefix("R") })
            } else {
                val (since, result) = step.removePrefix("Q").split('=')
                val got = input.hops(since.toInt()).joinToString("+") { it.rawValue }
                f.check("hops", got == result) { "$step: Kotlin $got" }
            }
        }
        f.check("hops", input.hopCount == hops.int("finalHopCount")) { "hopCount" }
        f.check("hops", input.recentHops.joinToString(" ") { it.rawValue } == hops.string("finalRecent")) { "recentHops" }

        val stages = golden.case("stages")
        val table2 = stages.array("table").map { it as JsonObject }
        for ((row, stage) in table2.zip(MiniGameStage.all)) {
            f.check("stages", stage.id == row.int("id") && stage.stageName == row.string("name") &&
                stage.starCount == row.int("starCount") && stage.hasAuroraBands == boolOf(row["hasAuroraBands"])) { "무대 ${stage.name}" }
        }
        f.check("stages", MiniGameStage.flappyThresholds == GoldenOps.ints(stages.string("flappyThresholds"))) { "flappyThresholds" }
        f.check("stages", MiniGameStage.tetrisThresholds == GoldenOps.ints(stages.string("tetrisThresholds"))) { "tetrisThresholds" }
        for ((key, fn) in listOf<Pair<String, (Int) -> MiniGameStage>>(
            "flappy" to { MiniGameStage.forFlappyScore(it) },
            "timing" to { MiniGameStage.forTimingRound(it) },
            "tetris" to { MiniGameStage.forTetrisAdvance(it) },
        )) {
            val from = stages.int("${key}From")
            GoldenOps.ints(stages.string(key)).forEachIndexed { i, w ->
                val got = fn(from + i).id
                f.check("stages", got == w) { "$key ${from + i}: 기대 $w · Kotlin $got" }
            }
        }
        f.assertNone()
        assertTrue(f.compared > 900)
    }
}
