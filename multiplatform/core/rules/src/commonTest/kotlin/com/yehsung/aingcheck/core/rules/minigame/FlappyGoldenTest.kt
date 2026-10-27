// 원본: Tests/checkTests/GoldenExport/games-tetris-minigame/GoldenExportMiniGames.swift(flappy/rules · flappy/scripted 생성기) @ 1b8260d
package com.yehsung.aingcheck.core.rules.minigame

import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.hex64
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import com.yehsung.aingcheck.testkit.golden.stringValue
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 플래피 — 동일성 등급 **이산**(G §8-14). 틈 중심(pow 에서 나온 값)만 허용 오차 1e-9 로, 나머지(정수·열거와 새·기둥·시계 실수)는 비트로
 * 대조한다. 1e-9 안에서 **비트가 갈린 자리 목록**은 잠근다([KNOWN_POW_BIT_DIVERGENCE_RULES] · [KNOWN_POW_BIT_DIVERGENCE_SCRIPTED],
 * W1-c NFC 의 knownDivergence 와 같은 꼴) — 세제곱 식이 바뀌어 1e-9 안에서만 흔들려도 목록이 늘거나 줄어 빨강이 된다.
 * Kotlin 은 (q·q)·q 곱셈뿐이라(IEEE 곱은 JVM·ART 어디서나 같은 비트) 이 목록은 플랫폼마다 같다. 기준은 Swift Darwin pow 의 비트(골든).
 */
class FlappyGoldenTest {
    companion object {
        /** flappy/rules center: Kotlin 곱셈과 Darwin pow 가 비트로 갈린 표본("pipe-k@시각 순번"). 실측 164점 중 이 자리뿐. */
        val KNOWN_POW_BIT_DIVERGENCE_RULES: Set<String> = setOf("pipe-0@7")

        /** flappy/scripted 득점 틈 중심: 비트로 갈린 득점("case@프레임"). 실측 496점 중 없음. */
        val KNOWN_POW_BIT_DIVERGENCE_SCRIPTED: Set<String> = emptySet()
    }

    private fun bitsOf(e: JsonElement?): Double? = if (e == null || e is JsonNull) null else Golden.bits(e.stringValue())
    private fun same(a: Double?, b: Double?): Boolean = if (a == null || b == null) a == b else a.toRawBits() == b.toRawBits()
    private fun near(a: Double?, b: Double?, tolerance: Double): Boolean = if (a == null || b == null) a == b else abs(a - b) <= tolerance

    private fun pipeOf(o: JsonObject): FlappyGame.Pipe = FlappyGame.Pipe(
        x = Golden.bits(o.string("xBits")), centerY = Golden.bits(o.string("centerYBits")), gap = Golden.bits(o.string("gapBits")),
        passed = (o["passed"] as JsonPrimitive).boolean, shiftDelay = bitsOf(o["shiftDelayBits"]),
        shiftOffset = Golden.bits(o.string("shiftOffsetBits")), shiftAt = bitsOf(o["shiftAtBits"]),
    )

    @Test
    fun rulesMatchSwift() {
        val golden = Golden.load("flappy/rules")
        val f = GoldenFailures(golden)
        var powExact = 0
        var powTotal = 0
        val powDiverged = LinkedHashSet<String>()
        for (case in golden.cases) {
            val id = case.string("id")
            when {
                id == "constants" -> {
                    val doubles = mapOf(
                        "widthBits" to FlappyGame.width, "heightBits" to FlappyGame.height, "birdXBits" to FlappyGame.birdX,
                        "hitboxSizeBits" to FlappyGame.hitboxSize, "spriteSizeBits" to FlappyGame.spriteSize,
                        "gravityBits" to FlappyGame.gravity, "flapVelocityBits" to FlappyGame.flapVelocity,
                        "maxFallSpeedBits" to FlappyGame.maxFallSpeed, "pipeWidthBits" to FlappyGame.pipeWidth,
                        "firstPipeXBits" to FlappyGame.firstPipeX, "centerMarginBits" to FlappyGame.centerMargin,
                        "overHoldBits" to FlappyGame.overHold, "flashDurationBits" to FlappyGame.flashDuration,
                        "maxStepBits" to FlappyGame.maxStep, "shiftChanceBits" to FlappyGame.shiftChance,
                        "shiftJumpBits" to FlappyGame.shiftJump, "shiftDelayMinBits" to FlappyGame.shiftDelayMin,
                        "shiftDelayMaxBits" to FlappyGame.shiftDelayMax, "shiftDurationBits" to FlappyGame.shiftDuration,
                    )
                    for ((key, value) in doubles) f.check(id, same(value, Golden.bits(case.string(key)))) { "$key Kotlin ${Golden.bitsText(value)}" }
                    f.check(id, FlappyGame.pipeCount == case.int("pipeCount")) { "pipeCount" }
                    f.check(id, FlappyGame.maxScore == case.int("maxScore")) { "maxScore" }
                    f.check(id, FlappyGame.shiftMinScore == case.int("shiftMinScore")) { "shiftMinScore" }
                }
                id == "curves" -> {
                    val from = case.int("from")
                    for ((key, fn) in listOf<Pair<String, (Int) -> Double>>(
                        "gapBits" to { s -> FlappyGame.gap(forScore = s) },
                        "speedBits" to { s -> FlappyGame.speed(forScore = s) },
                        "spacingBits" to { s -> FlappyGame.spacing(forScore = s) },
                    )) {
                        GoldenOps.bits(case.string(key)).forEachIndexed { i, w ->
                            val got = fn(from + i)
                            f.check(id, same(got, w)) { "$key 점수 ${from + i}: 기대 $w · Kotlin $got" }
                        }
                    }
                }
                id == "nextVelocity" -> {
                    val vys = GoldenOps.bits(case.string("vyBits"))
                    val dts = GoldenOps.bits(case.string("dtBits"))
                    val want = GoldenOps.bits(case.string("valuesBits"))
                    var k = 0
                    for (vy in vys) for (dt in dts) {
                        val got = FlappyGame.nextVelocity(vy, dt)
                        f.check(id, same(got, want[k])) { "vy=$vy dt=$dt: 기대 ${want[k]} · Kotlin $got" }
                        k += 1
                    }
                }
                id.startsWith("makePipe-") -> {
                    val rng = MiniGameRandom(case.hex64("seed"))
                    case.array("pipes").forEachIndexed { i, e ->
                        val w = e as JsonObject
                        val got = FlappyGame.makePipe(300.0 + i * 117, w.int("score"), rng)
                        val want = pipeOf(w)
                        f.check(id, got == want) { "기둥 $i(점수 ${w.int("score")}): 기대 $want · Kotlin $got" }
                    }
                    f.check(id, rng.next() == case.hex64("nextAfter")) { "난수 소비 수가 다르다(nextAfter)" }
                }
                id == "center" -> {
                    val tolerance = case.string("tolerance").toDouble()
                    for (e in case.array("pipes")) {
                        val p = e as JsonObject
                        val pipe = pipeOf(p.obj("pipe"))
                        val times = GoldenOps.bits(p.string("timesBits"))
                        val want = GoldenOps.bits(p.string("centersBits"))
                        times.forEachIndexed { i, t ->
                            val got = pipe.center(t)
                            powTotal += 1
                            if (same(got, want[i])) powExact += 1 else powDiverged += "${p.string("id")}@$i"
                            f.check(id, near(got, want[i], tolerance)) { "${p.string("id")} t=$t: 기대 ${want[i]} · Kotlin $got" }
                        }
                    }
                }
                id == "rectIntersects" -> {
                    case.array("rects").forEachIndexed { i, e ->
                        val r = e as JsonObject
                        val (ax, ay, aw, ah) = GoldenOps.bits(r.string("a"))
                        val (bx, by, bw, bh) = GoldenOps.bits(r.string("b"))
                        val a = MiniGameRect(ax, ay, aw, ah)
                        val b = MiniGameRect(bx, by, bw, bh)
                        val ab = (r["ab"] as JsonPrimitive).boolean
                        val ba = (r["ba"] as JsonPrimitive).boolean
                        f.check(id, a.intersects(b) == ab && b.intersects(a) == ba) {
                            "사각형 쌍 $i $a · $b: 기대 $ab/$ba · Kotlin ${a.intersects(b)}/${b.intersects(a)}"
                        }
                    }
                }
                else -> f.fail(id, "Kotlin 시험이 모르는 case")
            }
        }
        f.assertNone()
        println("AINGCHECK-FLAPPY-POW rules center 비트 일치 $powExact/$powTotal (이산 등급 — 1e-9 안이면 통과) · 갈린 자리 $powDiverged")
        assertTrue(powTotal >= 100, "틈 중심 표본을 덜 읽었다")
        assertEquals(KNOWN_POW_BIT_DIVERGENCE_RULES, powDiverged, "pow 유도값이 Swift 와 비트로 갈린 자리 목록이 바뀌었다(1e-9 안이어도) — 세제곱 식을 건드렸나")
        assertEquals(
            listOf("constants", "curves", "nextVelocity", "makePipe-0", "makePipe-1", "makePipe-2", "makePipe-3", "center", "rectIntersects"),
            golden.cases.map { it.string("id") }, "flappy/rules case 목록이 바뀌었다 — 빠진 표는 Kotlin 이 모른다",
        )
    }

    private fun fold(g: FlappyGame, h: DualFold) {
        when (val p = g.phase) {
            FlappyGame.Phase.Ready -> h.add(0)
            FlappyGame.Phase.Running -> h.add(1)
            is FlappyGame.Phase.Over -> { h.add(2); h.add(p.hold) }
            FlappyGame.Phase.Result -> h.add(3)
        }
        h.add(g.score)
        h.add(g.bird.x); h.add(g.bird.y); h.add(g.bird.vy)
        h.add(g.flashRemaining); h.add(g.elapsed); h.add(g.scrolled); h.add(g.flapCount)
        h.addOptional(g.lastFlapAt); h.addOptional(g.lastScoreAt); h.add(g.lastScorePipeCenter != null)
        val pipes = g.pipes
        h.add(pipes.size)
        for (p in pipes) {
            h.add(p.x); h.add(p.centerY); h.add(p.gap); h.add(p.passed)
            h.addOptional(p.shiftDelay); h.add(p.shiftOffset); h.addOptional(p.shiftAt)
        }
        // 화면이 읽는 파생 값(Swift 접기와 같은 순서).
        h.add(g.isPlaying); h.add(g.isGameOver); h.add(g.stage.id)
        val box = g.hitbox
        h.add(box.x); h.add(box.y); h.add(box.width); h.add(box.height)
    }

    @Test
    fun scriptedReplaysMatchSwiftDiscretely() {
        val golden = Golden.load("flappy/scripted")
        val f = GoldenFailures(golden)
        var powExact = 0
        var powTotal = 0
        val powDiverged = LinkedHashSet<String>()
        var shiftedPassed = 0
        for (case in golden.cases) {
            val id = case.string("id")
            val seed = case.hex64("seed")
            val dt = Golden.bits(case.string("dtBits"))
            val start = case.obj("start")
            val g = when (start.string("kind")) {
                "new" -> FlappyGame(seed)
                "fixture" -> {
                    val (bx, by, bvy) = GoldenOps.bits(start.string("bird"))
                    val (px, pc, pg) = GoldenOps.bits(start.string("pipe"))
                    FlappyGame(seed, FlappyGame.Bird(bx, by, bvy), listOf(FlappyGame.Pipe(px, pc, pg)), start.int("score"), FlappyGame.Phase.Running)
                }
                else -> error("모르는 시작")
            }
            val h = DualFold()
            fold(g, h)
            val trace = ReplayTrace(case.int("checkpointEvery"))
            val wantCenters = case.string("centers").split(' ').filter { it.isNotEmpty() }.associate {
                val (frame, bits) = it.split(':')
                frame.toInt() to Golden.bits(bits)
            }
            val gotCenters = HashMap<Int, Double>()
            for (ops in GoldenOps.decode(case.string("ops"))) {
                h.beginFrame()
                val scoreAt = g.lastScoreAt
                for (op in ops) when (op) {
                    "F" -> g.flap()
                    "I" -> g.interrupt()
                    else -> error("모르는 플래피 연산 '$op'")
                }
                g.step(dt)
                fold(g, h)
                trace.endFrame(h)
                val center = g.lastScorePipeCenter
                if (g.lastScoreAt != scoreAt && center != null) gotCenters[trace.frames] = center
                shiftedPassed += g.pipes.count { it.isShifting && it.passed }
            }
            val final = case.obj("final")
            val mismatch = trace.firstMismatch(
                case.string("frameBytes"), GoldenOps.hexes(case.string("checkpoints")), final.int("frames"),
                final.hex64("hash"), h.total.value,
            )
            f.check(id, mismatch == null) { mismatch!! }
            f.check(id, gotCenters.keys == wantCenters.keys) { "득점 프레임 Kotlin ${gotCenters.keys.sorted().take(10)} · Swift ${wantCenters.keys.sorted().take(10)}" }
            for ((frame, want) in wantCenters) {
                val got = gotCenters[frame]
                powTotal += 1
                if (same(got, want)) powExact += 1 else powDiverged += "$id@$frame"
                f.check(id, near(got, want, 1e-9)) { "프레임 $frame 득점 틈 중심: 기대 $want · Kotlin $got" }
            }
            f.check(id, g.score == final.int("score")) { "점수 Kotlin ${g.score}" }
            f.check(id, g.flapCount == final.int("flapCount")) { "flapCount" }
            val pipes = final.array("pipes").map { pipeOf(it as JsonObject) }
            f.check(id, g.pipes == pipes) { "끝 기둥 Kotlin ${g.pipes}" }
            f.check(id, near(g.lastScorePipeCenter, bitsOf(final["lastScorePipeCenterBits"]), 1e-9)) { "끝 lastScorePipeCenter" }
        }
        f.assertNone()
        println("AINGCHECK-FLAPPY-POW scripted 득점 틈 중심 비트 일치 $powExact/$powTotal · 갈린 자리 $powDiverged")
        assertTrue(powTotal > 50 && shiftedPassed > 0, "대본이 득점·움직이는 기둥을 충분히 거치지 않았다($powTotal, $shiftedPassed)")
        assertEquals(KNOWN_POW_BIT_DIVERGENCE_SCRIPTED, powDiverged, "득점 틈 중심이 Swift 와 비트로 갈린 자리 목록이 바뀌었다(1e-9 안이어도)")
        assertEquals(listOf("A", "B", "C", "D", "E"), golden.cases.map { it.string("id") }, "flappy/scripted case 목록이 바뀌었다")
    }
}
