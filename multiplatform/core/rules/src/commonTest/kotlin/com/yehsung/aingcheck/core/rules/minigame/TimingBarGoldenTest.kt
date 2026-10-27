// 원본: Tests/checkTests/GoldenExport/games-tetris-minigame/GoldenExportMiniGames.swift(timing-bar/rules · timing-bar/scripted 생성기) @ 1b8260d
package com.yehsung.aingcheck.core.rules.minigame

import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.hex64
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import com.yehsung.aingcheck.testkit.golden.stringValue
import kotlin.test.Test
import kotlin.test.assertEquals

/** 타이밍 바 — 비트(C§5.1 E5). 반올림 경계((k+0.5)/30)·floor 삼각파·NaN 점수까지 Swift 와 같다. */
class TimingBarGoldenTest {

    @Test
    fun rulesMatchSwift() {
        val golden = Golden.load("timing-bar/rules")
        val f = GoldenFailures(golden)
        for (case in golden.cases) {
            val id = case.string("id")
            when (id) {
                "period", "targetWidth" -> {
                    val from = case.int("from")
                    GoldenOps.bits(case.string("valuesBits")).forEachIndexed { i, w ->
                        val got = if (id == "period") TimingBarGame.period(from + i) else TimingBarGame.targetWidth(from + i)
                        f.check(id, got.toRawBits() == w.toRawBits()) { "라운드 ${from + i}: 기대 $w · Kotlin $got" }
                    }
                }
                "markerPosition" -> {
                    val periods = GoldenOps.bits(case.string("periodsBits"))
                    val times = GoldenOps.bits(case.string("timesBits"))
                    val want = GoldenOps.bits(case.string("valuesBits"))
                    var k = 0
                    for (p in periods) for (t in times) {
                        val got = TimingBarGame.markerPosition(t, p)
                        f.check(id, got.toRawBits() == want[k].toRawBits()) { "t=$t period=$p: 기대 ${want[k]} · Kotlin $got" }
                        k += 1
                    }
                }
                "roundScore" -> {
                    val ds = GoldenOps.bits(case.string("distancesBits"))
                    val want = GoldenOps.ints(case.string("values"))
                    ds.forEachIndexed { i, d ->
                        val got = TimingBarGame.roundScore(d)
                        f.check(id, got == want[i]) { "d=$d: 기대 ${want[i]} · Kotlin $got" }
                    }
                }
                "verdict" -> {
                    val from = case.int("from")
                    case.string("values").split(' ').forEachIndexed { i, w ->
                        val got = TimingBarGame.verdict(from + i).name
                        f.check(id, got == w) { "점수 ${from + i}: 기대 $w · Kotlin $got" }
                    }
                    val labels = case.array("labels").map { it.stringValue() }
                    val got = TimingBarGame.Verdict.entries.map { "${it.name}=${it.label}" }
                    f.check(id, got == labels) { "라벨 Kotlin $got" }
                }
                "constants" -> {
                    f.check(id, TimingBarGame.roundCount == case.int("roundCount")) { "roundCount" }
                    f.check(id, TimingBarGame.resultHold.toRawBits() == Golden.bits(case.string("resultHoldBits")).toRawBits()) { "resultHold" }
                    f.check(id, TimingBarGame.maxStep.toRawBits() == Golden.bits(case.string("maxStepBits")).toRawBits()) { "maxStep" }
                }
                else -> f.fail(id, "Kotlin 시험이 모르는 case")
            }
        }
        f.assertNone()
    }

    private fun fold(g: TimingBarGame, h: DualFold) {
        when (val p = g.phase) {
            TimingBarGame.Phase.Ready -> h.add(0)
            is TimingBarGame.Phase.Running -> { h.add(1); h.add(p.round); h.add(p.t) }
            is TimingBarGame.Phase.RoundResult -> { h.add(2); h.add(p.round); h.add(p.score); h.add(p.hold) }
            is TimingBarGame.Phase.Finished -> { h.add(3); h.add(p.total) }
        }
        val scores = g.roundScores
        h.add(scores.size)
        for (s in scores) h.add(s)
        h.add(g.target.first); h.add(g.target.second)
        h.add(g.markerPosition)
        val hit = g.lastHit
        if (hit != null) { h.add(true); h.add(hit) } else h.add(false)
        h.add(g.combo); h.add(g.total); h.add(g.round); h.add(g.isPlaying)
    }

    @Test
    fun scriptedReplaysMatchSwift() {
        val golden = Golden.load("timing-bar/scripted")
        val f = GoldenFailures(golden)
        for (case in golden.cases) {
            val id = case.string("id")
            val g = TimingBarGame(case.hex64("seed"))
            val dt = Golden.bits(case.string("dtBits"))
            val h = DualFold()
            fold(g, h)
            val trace = ReplayTrace(case.int("checkpointEvery"))
            for (ops in GoldenOps.decode(case.string("ops"))) {
                h.beginFrame()
                for (op in ops) when (op) {
                    "T" -> g.tap()
                    "V" -> g.invalidate()
                    else -> error("모르는 타이밍 바 연산 '$op'")
                }
                g.step(dt)
                fold(g, h)
                trace.endFrame(h)
            }
            val final = case.obj("final")
            val mismatch = trace.firstMismatch(
                case.string("frameBytes"), GoldenOps.hexes(case.string("checkpoints")), final.int("frames"),
                final.hex64("hash"), h.total.value,
            )
            f.check(id, mismatch == null) { mismatch!! }
            f.check(id, g.roundScores == GoldenOps.ints(final.string("roundScores"))) { "점수 Kotlin ${g.roundScores}" }
            f.check(id, g.total == final.int("total")) { "총점" }
        }
        f.assertNone()
        assertEquals(4, golden.cases.size)
    }
}
