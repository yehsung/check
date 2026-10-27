// 원본: Tests/checkTests/GoldenExport/games-tetris-minigame/GoldenExportCrossy.swift(crossy/rules · crossy/lanes · crossy/scripted 생성기) @ 1b8260d
package com.yehsung.aingcheck.core.rules.minigame.crossy

import com.yehsung.aingcheck.core.rules.minigame.DualFold
import com.yehsung.aingcheck.core.rules.minigame.GoldenFailures
import com.yehsung.aingcheck.core.rules.minigame.GoldenOps
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.ReplayTrace
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.hex64
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import com.yehsung.aingcheck.testkit.golden.stringValue
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * 길건너 아잉이(v0.3.67, G §8-16) — Kotlin 엔진이 Swift 와 비트로 같다: 규칙표 · 시드 줄 생성(첫 판·둘째 판) · 대본 다섯
 * (차·강·떠내려감·기차·놓침 죽음 · 막힌 칸 통통 · 한 칸 줄 세우기와 버림 · 점수 단조 · 끊기 · 다시 하기).
 */
class CrossyGoldenTest {

    private fun propText(p: CrossyGame.Prop?): String = when (p) {
        null -> "."
        CrossyGame.Prop.Rock -> "r"
        is CrossyGame.Prop.Tree -> p.height.toString()
    }

    private fun moverText(m: CrossyGame.Mover): String =
        "${Golden.bitsText(m.x)}:${Golden.bitsText(m.length)}:${m.variant}:${if (m.isTruck) 1 else 0}"

    /** Swift `GoldenExportCrossy.laneText` 와 같은 글자. */
    fun laneText(l: CrossyGame.Lane): String = listOf(
        l.row.toString(), l.kind.rawValue, l.props.joinToString("") { propText(it) }, l.direction.toString(), Golden.bitsText(l.speed),
        l.movers.joinToString(";") { moverText(it) },
        l.train?.let { "${Golden.bitsText(it.x)}:${Golden.bitsText(it.length)}" } ?: "-",
        Golden.bitsText(l.trainCountdown), Golden.hex64Text(l.trainRandom.state),
    ).joinToString("|")

    private fun compareLanes(f: GoldenFailures, id: String, label: String, got: List<CrossyGame.Lane>, want: String) {
        val wantLines = want.split('\n')
        val gotLines = got.map { laneText(it) }
        val first = (0 until maxOf(wantLines.size, gotLines.size)).firstOrNull { wantLines.getOrNull(it) != gotLines.getOrNull(it) }
        f.check(id, first == null) {
            "$label 줄 ${first?.let { wantLines.getOrNull(it)?.substringBefore('|') ?: gotLines.getOrNull(it)?.substringBefore('|') }} 부터 갈린다 " +
                "(Swift ${wantLines.size}줄 · Kotlin ${gotLines.size}줄)\n  Swift  ${first?.let { wantLines.getOrNull(it) }}\n  Kotlin ${first?.let { gotLines.getOrNull(it) }}"
        }
    }

    @Test
    fun rulesMatchSwift() {
        val golden = Golden.load("crossy/rules")
        val f = GoldenFailures(golden)
        fun same(a: Double, bits: String) = a.toRawBits() == Golden.bits(bits).toRawBits()
        val c = golden.case("constants")
        val ints = mapOf(
            "columns" to CrossyGame.columns, "startColumn" to CrossyGame.startColumn, "maxScore" to CrossyGame.maxScore,
            "kindMaxScore" to MiniGameKind.crossy.maxScore, "startGrassRows" to CrossyGame.startGrassRows, "wallRow" to CrossyGame.wallRow,
            "railStartRow" to CrossyGame.railStartRow, "riverStartRow" to CrossyGame.riverStartRow, "lanesBehind" to CrossyGame.lanesBehind,
            "lanesAhead" to CrossyGame.lanesAhead,
        )
        for ((k, v) in ints) f.check("constants", c.int(k) == v) { "$k Kotlin $v" }
        val doubles = mapOf(
            "hopSecondsBits" to CrossyGame.hopSeconds, "serverTimeMarginFactorBits" to CrossyGame.serverTimeMarginFactor,
            "maxStepBits" to CrossyGame.maxStep, "deathHoldBits" to CrossyGame.deathHold, "playerHalfWidthBits" to CrossyGame.playerHalfWidth,
            "logGraceBits" to CrossyGame.logGrace, "carLengthBits" to CrossyGame.carLength, "truckLengthBits" to CrossyGame.truckLength,
            "trackMarginBits" to CrossyGame.trackMargin, "warnSecondsBits" to CrossyGame.warnSeconds, "trainLengthBits" to CrossyGame.trainLength,
            "trainSpeedBits" to CrossyGame.trainSpeed, "behindRowsBits" to CrossyGame.behindRows, "idleLimitBits" to CrossyGame.idleLimit,
            "followRateBits" to CrossyGame.followRate, "difficultyRowsBits" to CrossyGame.difficultyRows,
        )
        for ((k, v) in doubles) f.check("constants", same(v, c.string(k))) { "$k Kotlin ${Golden.bitsText(v)}" }
        val track = GoldenOps.bits(c.string("trackBits"))
        f.check("constants", listOf(CrossyGame.trackLeft, CrossyGame.trackRight, CrossyGame.trackLength) == track) { "track" }
        f.check("constants", listOf(CrossyGame.playMinX, CrossyGame.playMaxX) == GoldenOps.bits(c.string("playBits"))) { "play" }

        val d = golden.case("difficulty")
        val from = d.int("from")
        val diff = GoldenOps.bits(d.string("difficultyBits"))
        val creep = GoldenOps.bits(d.string("creepSpeedBits"))
        diff.indices.forEach { i ->
            f.check("difficulty", CrossyGame.difficulty(from + i).toRawBits() == diff[i].toRawBits()) { "difficulty(${from + i})" }
            f.check("difficulty", CrossyGame.creepSpeed(from + i).toRawBits() == creep[i].toRawBits()) { "creepSpeed(${from + i})" }
        }

        val e = golden.case("enums")
        f.check("enums", CrossyGame.Direction.entries.joinToString(" ") { "${it.rawValue}:${it.rowDelta}:${it.columnDelta}" } == e.string("directions")) { "방향" }
        f.check("enums", CrossyGame.LaneKind.entries.joinToString(" ") { it.rawValue } == e.string("laneKinds")) { "줄 종류" }
        f.check("enums", CrossyGame.DeathCause.entries.map { "${it.rawValue}=${it.caption}" } == e.array("deathCauses").map { it.stringValue() }) { "죽음 사유" }

        val o = golden.case("overlaps")
        val movers = o.string("movers").split(';').map { text ->
            val (x, len, variant, truck) = text.split(':')
            CrossyGame.Mover(Golden.bits(x), Golden.bits(len), variant.toInt(), truck == "1")
        }
        val widths = o.array("widthsBits").map { GoldenOps.bits(it.stringValue()) }
        val centers = GoldenOps.bits(o.string("centersBits"))
        val gotOverlaps = ArrayList<Boolean>()
        for (m in movers) for ((hw, g) in widths) for (cx in centers) gotOverlaps += m.overlaps(cx, hw, g)
        f.check("overlaps", gotOverlaps == GoldenOps.bools(o.string("values"))) { "overlaps 표" }
        f.check("overlaps", movers.joinToString(";") { moverText(it) } == o.string("movers")) { "물체 글자" }

        val l = golden.case("lanes")
        val grass = CrossyGame.Lane(7, CrossyGame.LaneKind.grass, listOf(CrossyGame.Prop.Tree(0), null, CrossyGame.Prop.Rock, null, null, CrossyGame.Prop.Tree(2), null, null, CrossyGame.Prop.Rock))
        val road = CrossyGame.Lane(8, CrossyGame.LaneKind.road, direction = -1, speed = 2.1, movers = listOf(CrossyGame.Mover(1.0, 1.4)))
        val river = CrossyGame.Lane(9, CrossyGame.LaneKind.river, direction = 1, speed = 1.1,
            movers = listOf(CrossyGame.Mover(-4.5, 3.0), CrossyGame.Mover(1.2, 2.0), CrossyGame.Mover(5.6, 4.0)))
        val rails = listOf(
            CrossyGame.Lane(20, CrossyGame.LaneKind.rail, direction = 1, speed = 24.0, trainCountdown = 1.0000001, trainSeed = 9uL),
            CrossyGame.Lane(21, CrossyGame.LaneKind.rail, direction = -1, speed = 24.0, trainCountdown = 1.0, trainSeed = 9uL),
            CrossyGame.Lane(22, CrossyGame.LaneKind.rail, direction = 1, speed = 24.0, train = CrossyGame.Mover(-3.0, 14.0), trainCountdown = 0.0),
            CrossyGame.Lane(23, CrossyGame.LaneKind.rail, direction = 1, speed = 24.0, trainCountdown = -0.5),
        )
        f.check("lanes", laneText(grass) == l.string("grass") && laneText(road) == l.string("road") && laneText(river) == l.string("river")) {
            "줄 글자 Kotlin ${laneText(grass)} / ${laneText(road)} / ${laneText(river)}"
        }
        val cols = (l.int("columnsFrom")..10).toList()
        f.check("lanes", cols.map { grass.isBlocked(it) } == GoldenOps.bools(l.string("grassBlocked"))) { "풀밭 막힘" }
        f.check("lanes", cols.map { road.isBlocked(it) } == GoldenOps.bools(l.string("roadBlocked"))) { "찻길 막힘" }
        f.check("lanes", listOf(grass.velocity, road.velocity, river.velocity) == GoldenOps.bits(l.string("velocityBits"))) { "흐름 속도" }
        val xs = GoldenOps.bits(l.string("logXsBits"))
        f.check("lanes", xs.map { x -> river.log(x)?.let { river.movers.indexOf(it) } ?: -1 } == GoldenOps.ints(l.string("logIndex"))) { "통나무 고르기" }
        f.check("lanes", xs.map { x -> if (road.log(x) == null) -1 else 0 } == GoldenOps.ints(l.string("roadLog"))) { "찻길 통나무 없음" }
        f.check("lanes", rails.joinToString(" ") { laneText(it) } == l.string("rails")) { "기찻길 글자 Kotlin ${rails.joinToString(" ") { laneText(it) }}" }
        f.check("lanes", (rails.map { it.isTrainWarning } + listOf(grass.isTrainWarning, river.isTrainWarning)) == GoldenOps.bools(l.string("trainWarning"))) { "경고등" }

        val hp = golden.case("hopProgress")
        val es = GoldenOps.bits(hp.string("elapsedBits"))
        val want = GoldenOps.bits(hp.string("valuesBits"))
        es.forEachIndexed { i, el ->
            val got = CrossyGame.Hop(0, 4.0, 1, 4.0, false, el, CrossyGame.Direction.forward, bumped = false, fromRiding = false).progress
            f.check("hopProgress", got.toRawBits() == want[i].toRawBits()) { "elapsed $el: Kotlin $got" }
        }
        f.assertNone()
        assertEquals(listOf("constants", "difficulty", "enums", "overlaps", "lanes", "hopProgress"), golden.cases.map { it.string("id") },
            "crossy/rules case 목록이 바뀌었다 — 빠진 표는 Kotlin 이 모른다")
    }

    @Test
    fun seededLanesMatchSwift() {
        val golden = Golden.load("crossy/lanes")
        val f = GoldenFailures(golden)
        val kinds = HashSet<CrossyGame.LaneKind>()
        for (case in golden.cases) {
            val id = case.string("id")
            val seed = case.hex64("seed")
            val game = CrossyGame(seed)
            f.check(id, game.roundSeed == case.hex64("roundSeed")) { "roundSeed Kotlin ${Golden.hex64Text(game.roundSeed)}" }
            f.check(id, game.lanes.first().row == case.int("heldFirstRow") && game.lanes.last().row == case.int("heldLastRow")) {
                "들고 있는 줄 ${game.lanes.first().row}…${game.lanes.last().row}"
            }
            val heldBefore = game.lanes.size
            val preview = game.previewLanes(320)
            f.check(id, game.lanes.size == heldBefore) { "미리보기가 판을 바꿨다" }
            preview.forEach { kinds += it.kind }
            compareLanes(f, id, "첫 판", preview, case.string("lanes"))
            val second = CrossyGame(seed)
            second.startForTesting()
            second.interrupt()
            second.action()
            f.check(id, second.roundSeed == case.hex64("secondRoundSeed")) { "둘째 판 roundSeed Kotlin ${Golden.hex64Text(second.roundSeed)}" }
            compareLanes(f, id, "둘째 판", second.previewLanes(60), case.string("secondLanes"))
        }
        f.assertNone()
        assertEquals(CrossyGame.LaneKind.entries.toSet(), kinds, "시드 줄이 네 종류를 다 내지 않았다")
        assertEquals(listOf("zero", "one", "answer", "deadbeef", "int63-max", "uint64-max", "pattern", "server"), golden.cases.map { it.string("id") },
            "crossy/lanes case 목록이 바뀌었다")
    }

    private fun fold(g: CrossyGame, h: DualFold) {
        when (val p = g.phase) {
            CrossyGame.Phase.Ready -> h.add(0)
            CrossyGame.Phase.Running -> h.add(1)
            is CrossyGame.Phase.Over -> { h.add(2); h.add(p.hold) }
            CrossyGame.Phase.Result -> h.add(3)
        }
        h.add(g.player.row); h.add(g.player.x); h.add(g.player.riding); h.add(g.player.facing.ordinal)
        val hop = g.hop
        if (hop != null) {
            h.add(1); h.add(hop.fromRow); h.add(hop.fromX); h.add(hop.toRow); h.add(hop.toX); h.add(hop.toFloats)
            h.add(hop.elapsed); h.add(hop.direction.ordinal); h.add(hop.bumped); h.add(hop.fromRiding)
        } else {
            h.add(0)
        }
        h.add(g.queued?.ordinal ?: -1)
        h.add(g.score); h.add(g.cameraRow); h.add(g.sinceProgress)
        val d = g.death
        if (d != null) {
            h.add(1); h.add(d.cause.ordinal); h.add(d.row); h.add(d.x); h.add(d.at); h.add(d.pushDirection)
        } else {
            h.add(0)
        }
        h.add(g.elapsed); h.add(g.hopCount); h.add(g.roundSeed)
        h.add(g.lanes.size)
        for (l in g.lanes) {
            h.add(l.row); h.add(l.kind.ordinal); h.add(l.direction); h.add(l.speed)
            h.add(l.movers.size)
            for (m in l.movers) { h.add(m.x); h.add(m.length); h.add(m.variant); h.add(m.isTruck) }
            val t = l.train
            if (t != null) { h.add(1); h.add(t.x); h.add(t.length) } else h.add(0)
            h.add(l.trainCountdown); h.add(l.trainRandom.state)
            for (p in l.props) h.add(
                when (p) {
                    null -> -1
                    CrossyGame.Prop.Rock -> -2
                    is CrossyGame.Prop.Tree -> p.height
                },
            )
        }
        // 화면·일시정지가 읽는 파생 값(Swift 접기와 같은 순서).
        h.add(g.isPlaying); h.add(g.isGameOver)
        val spot = g.occupancy
        h.add(spot.row); h.add(spot.x)
        val visual = g.playerVisual
        h.add(visual.row); h.add(visual.x); h.add(visual.lift)
    }

    @Test
    fun scriptedReplaysMatchSwift() {
        val golden = Golden.load("crossy/scripted")
        val f = GoldenFailures(golden)
        val causes = HashSet<CrossyGame.DeathCause>()
        for (case in golden.cases) {
            val id = case.string("id")
            val g = CrossyGame(case.hex64("seed"))
            val dts = GoldenOps.bits(case.string("dtCycleBits"))
            val h = DualFold()
            fold(g, h)
            val trace = ReplayTrace(case.int("checkpointEvery"))
            val deaths = ArrayList<String>()
            for (ops in GoldenOps.decode(case.string("ops"))) {
                val dt = dts[trace.frames % dts.size]
                h.beginFrame()
                val hadDeath = g.death != null
                for (op in ops) when (op) {
                    "F" -> g.input(CrossyGame.Direction.forward)
                    "B" -> g.input(CrossyGame.Direction.back)
                    "L" -> g.input(CrossyGame.Direction.left)
                    "R" -> g.input(CrossyGame.Direction.right)
                    "ACT" -> g.action()
                    "INT" -> g.interrupt()
                    else -> error("모르는 길건너 연산 '$op'")
                }
                g.step(dt)
                fold(g, h)
                trace.endFrame(h)
                val death = g.death
                if (!hadDeath && death != null) {
                    deaths += "${trace.frames}:${death.cause.rawValue}"
                    causes += death.cause
                }
            }
            val final = case.obj("final")
            val mismatch = trace.firstMismatch(
                case.string("frameBytes"), GoldenOps.hexes(case.string("checkpoints")), final.int("frames"),
                final.hex64("hash"), h.total.value,
            )
            f.check(id, mismatch == null) { mismatch!! }
            f.check(id, deaths.joinToString(" ") == case.string("deaths")) { "죽음 Kotlin ${deaths.take(6)}" }
            f.check(id, g.score == final.int("score") && g.hopCount == final.int("hopCount")) { "점수·뛰기 수" }
            f.check(id, g.roundSeed == final.hex64("roundSeed")) { "roundSeed" }
            val player = "${g.player.row}|${Golden.bitsText(g.player.x)}|${if (g.player.riding) 1 else 0}|${g.player.facing.rawValue}"
            f.check(id, player == final.string("player")) { "아잉이 Kotlin $player" }
            compareLanes(f, id, "끝 판", g.lanes, final.string("lanes"))
        }
        f.assertNone()
        assertEquals(CrossyGame.DeathCause.entries.toSet(), causes, "대본이 죽음 다섯 갈래를 다 거치지 않았다")
        assertEquals(listOf("A", "B", "C", "D", "E"), golden.cases.map { it.string("id") }, "crossy/scripted case 목록이 바뀌었다")
    }
}
