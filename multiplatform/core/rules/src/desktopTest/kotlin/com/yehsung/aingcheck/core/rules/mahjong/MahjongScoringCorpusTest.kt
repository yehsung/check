// 원본: Tests/checkTests/MahjongScoringCorpusTests.swift @ e4995a3a — Android 판 8
// 아잉 마작 손 계산(역 · 부 · 점수) · 점수표를 판정 코퍼스(cases.json)와 맞춘다. 사례는 id 로 집는다.
package com.yehsung.aingcheck.core.rules.mahjong

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class MahjongScoringCorpusTest {
    // 없으면: 시험이 읽는 코퍼스가 원본과 갈라져도, 별칭이 빠져 천화 사례가 조용히 빠져도 초록이다.
    @Test
    fun corpusShape() {
        assertEquals("faf35270fb9c8453cceeb5808311a6ab", MahjongCorpus.md5("cases.json"))
        assertEquals("a805df6deb75bb8776ef720693ac00ec", MahjongCorpus.md5("corpus_alias.json"))
        assertEquals("mahjong-cases/1", MahjongCorpus.document.str("schema"))
        assertEquals(235, MahjongCorpus.cases.size)
        val byType = MahjongCorpus.cases.groupingBy { it.type }.eachCount()
        assertEquals(
            mapOf("hand" to 93, "score_table" to 33, "advance" to 22, "shape" to 11, "claim" to 11, "abortive" to 10, "settle_win" to 9,
                "exhaustive" to 9, "furiten" to 8, "kuikae" to 8, "dora" to 8, "riichi" to 7, "riichi_ankan" to 3, "rank" to 3),
            byType,
        )
        assertEquals(235, MahjongCorpus.cases.map { it.id }.toSet().size)
        assertEquals(setOf("heavenly", "earthly"), MahjongCorpus.alias.values.toSet())
        assertNotNull(MahjongCorpus.byID("YM-HEAVENLY"))
        assertNotNull(MahjongCorpus.byID("YM-EARTHLY"))
    }

    // 없으면: 역 · 부 · 점수 · 해석 고르기(X-01 · X-02) · 형식 오류 가운데 하나가 reference 와 갈려도 서버와 맞춰 볼 정답이 없다.
    @Test
    fun handCases() {
        val cases = MahjongCorpus.cases("hand")
        assertEquals(93, cases.size)
        val failures = mutableListOf<String>()
        var errors = 0
        for (c in cases) {
            val r = MahjongCorpus.evaluate(c.input)
            if (r == null) { failures += "${c.id}: 입력을 패 id 로 못 바꿈"; continue }
            if (c.expected.asObject()?.containsKey("error") == true) errors += 1
            val d = MahjongCorpus.diffs(c.expected, MahjongCorpus.view(r.second, r.first.tsumo))
            if (d.isNotEmpty()) failures += "${c.id}: " + d.joinToString(" | ")
        }
        assertEquals(2, errors)
        assertTrue(failures.isEmpty(), "${failures.size}건:\n" + failures.take(12).joinToString("\n"))
    }

    // 없으면: 천화(MJ-36 — 14장 중 가장 높은 화료패)를 화료패 하나로만 재면 천화+순정 구련보등이 천화 하나로 떨어진다.
    @Test
    fun heavenlyPicksBest() {
        val c = assertNotNull(MahjongCorpus.byID("YM-HEAVENLY-CHUUREN"))
        val ctx = assertNotNull(MahjongCorpus.context(c.input))
        val score = (MahjongScoring.evaluate(ctx) as MahjongEvaluation.Success).score
        assertEquals(listOf(MahjongYaku.heavenly, MahjongYaku.junseiChuuren), score.yaku.map { it.yaku })
        assertEquals(3, score.yakuman)
        val plain = (MahjongScoring.evaluate(ctx.copy(heavenly = false)) as MahjongEvaluation.Success).score
        assertEquals(listOf(MahjongYaku.chuuren), plain.yaku.map { it.yaku }, "기준선: 원래 화료패로는 순정이 아니다")
    }

    // 없으면: 상한 경계나 친/자 · 쯔모/론 지불 반올림이 갈려도 모른다.
    @Test
    fun scoreTable() {
        val cases = MahjongCorpus.cases("score_table")
        assertEquals(33, cases.size)
        val failures = mutableListOf<String>()
        for (c in cases) {
            val i = c.input
            val han = i.int("han"); val fu = i.int("fu"); val dealer = i.bool("dealer"); val tsumo = i.bool("tsumo")
            if (han == null || fu == null || dealer == null || tsumo == null) { failures += "${c.id}: 입력"; continue }
            val r = MahjongScoring.scoreOf(han, fu, dealer, tsumo, i.int("yakuman") ?: 0)
            val view = kotlinx.serialization.json.JsonObject(mapOf(
                "base" to MahjongCorpus.n(r.base), "limit" to kotlinx.serialization.json.JsonPrimitive(r.limit),
                "points" to MahjongCorpus.points(r.points), "total" to MahjongCorpus.n(r.total),
            ))
            val d = MahjongCorpus.diffs(c.expected, view)
            if (d.isNotEmpty()) failures += "${c.id}: " + d.joinToString(" | ")
        }
        assertTrue(failures.isEmpty(), failures.joinToString("\n"))
    }

    // 없으면: 해석이 여럿일 때 고르는 순서(X-01 역만 먼저 · X-02 역 순번)가 서버와 갈려 같은 손의 역 표시가 기기마다 다르다.
    @Test
    fun interpretationOrder() {
        val c = assertNotNull(MahjongCorpus.byID("X-01-SUUANKOU-OVER-KAZOE"))
        val ctx = assertNotNull(MahjongCorpus.context(c.input))
        val score = (MahjongScoring.evaluate(ctx) as MahjongEvaluation.Success).score
        assertEquals(listOf(MahjongYaku.suuankou), score.yaku.map { it.yaku })
        assertEquals(1, score.yakuman)
        assertEquals("yakuman", score.limit)
        val kazoe = (MahjongScoring.evaluate(ctx.copy(tsumo = false)) as MahjongEvaluation.Success).score
        assertEquals(0, kazoe.yakuman)
        assertTrue(kazoe.han >= 13 && kazoe.limit == "yakuman", "${kazoe.yaku} ${kazoe.han}")
    }
}
