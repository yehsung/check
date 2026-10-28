// 원본: Tests/CheckMobileKitTests/MeGachaStoreTests.swift · MeGachaMachineTests.swift(request_id 쥔 채 재시도 · 확률 합 ≠ 100% 면 숨김) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.gacha.GachaText
import com.yehsung.aingcheck.core.wire.models.GachaPullResponse
import com.yehsung.aingcheck.core.wire.models.GachaPullStatus
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

@OptIn(ExperimentalCoroutinesApi::class)
class MeGachaStoreTest {
    private val odds100 = """[{"character_id":"aing_gold","percent":3},{"character_id":"aing_rainbow","percent":2},
        {"character_id":"fox","percent":24},{"character_id":"squirrel","percent":24},{"character_id":"shiba","percent":14},
        {"character_id":"ghost","percent":14},{"character_id":"jellyfish","percent":11},{"character_id":"robot","percent":8}]"""

    private fun shop(ruby: Long? = 120, odds: String = odds100, price: String = "50", robotOwned: Boolean = false): String =
        """{${ruby?.let { "\"ruby_balance\":$it," } ?: ""}"characters":[{"id":"fox","price":60,"owned":true},{"id":"robot","price":100,"owned":$robotOwned}],
           "gacha":{"price":$price,"shards":3,"odds":$odds,"shard_costs":{"aing_gold":20,"fox":2,"robot":8}}}"""

    private fun requestID(body: String): String = Json.parseToJsonElement(body).jsonObject.getValue("p_request_id").jsonPrimitive.content

    /** 상점을 한 번 읽어 뽑기 문을 연다. */
    private fun MeHarness.openShop() {
        signIn()
        store.launch { store.loadShop() }
    }

    // ① 결과를 모르는 실패면 request_id 를 쥔 채 재시도한다

    @Test
    fun offlinePullKeepsRequestIDAndTheRetrySendsTheSameID() = runTest {
        val ok = MeReply.Json("""{"status":"ok","character_id":"robot","duplicate":false,"shards_gained":0,"shards":3,"ruby_balance":70,"replayed":true}""")
        val replies = ArrayDeque<MeReply>(listOf(MeReply.Offline, MeReply.serverDown, ok, ok))
        var serverRuby = 120L
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "shop_state" -> MeReply.Json(shop(ruby = serverRuby, robotOwned = serverRuby == 70L))
                "gacha_pull" -> replies.removeFirst().also { if (it === ok) serverRuby = 70 }
                else -> null
            }
        }
        h.openShop()
        advanceUntilIdle()
        assertTrue(h.store.showsGacha && h.store.canPullGacha, "상점이 뽑기를 열었다")

        h.store.pullGacha()
        advanceUntilIdle()
        assertFalse(h.store.isPulling)
        assertEquals(GachaText.connection, h.store.gachaNotice, "오프라인 = 결과 모름 → 연결 안내")
        val held = h.store.gachaRequestIDs.pull
        assertEquals(requestID(h.server.bodies("gacha_pull")[0]), held, "결과를 모르면 id 를 **쥔 채** 둔다")

        h.store.pullGacha() // 5xx — 여전히 결과 모름
        advanceUntilIdle()
        h.store.pullGacha() // 서버가 처음 결과를 replayed 로 돌려준다
        advanceUntilIdle()

        val ids = h.server.bodies("gacha_pull").map(::requestID)
        assertEquals(3, ids.size)
        assertEquals(1, ids.distinct().size, "같은 동작의 재시도는 같은 id: $ids")
        assertEquals(ids[0].lowercase(), ids[0], "서버에는 소문자 uuid")
        assertNull(h.store.gachaRequestIDs.pull, "서버가 답했다 — id 의 일은 끝났다")
        assertEquals(70L, h.ruby.rubyBalance, "잔량은 응답 값으로만")
        assertTrue("robot" in h.store.ownedCharacterIDs)
        assertEquals("robot", h.store.lastGachaResult?.characterID)

        // 다음 누름은 새 동작이다 — 새 id.
        h.store.pullGacha()
        advanceUntilIdle()
        val next = h.server.bodies("gacha_pull").map(::requestID)
        assertEquals(4, next.size)
        assertNotEquals(ids[0], next[3], "답을 받은 뒤의 누름은 새 id")
        h.assertClean()
    }

    @Test
    fun answeredRefusalSettlesTheIDButMissingFunctionAlsoSettles() = runTest {
        val replies = ArrayDeque<MeReply>(listOf(
            MeReply.Json("""{"status":"insufficient","need":50,"have":10}"""),
            MeReply.missingFunction,
            MeReply.Json("""{"status":"invalid"}"""),
        ))
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "shop_state" -> MeReply.Json(shop())
                "gacha_pull" -> replies.removeFirst()
                else -> null
            }
        }
        h.openShop()
        advanceUntilIdle()
        h.store.pullGacha()
        advanceUntilIdle()
        // insufficient 는 서버의 답이다 — 잔량을 안 실었으면 '가진 양'이 지금 잔량이고 id 는 버린다.
        assertEquals(10L, h.ruby.rubyBalance)
        assertNull(h.store.gachaRequestIDs.pull)
        assertTrue(h.store.isGachaNoticeError)
        // 잔량 10 으로는 뽑을 수 없다 — 버튼 판정이 막는다(요청 0건).
        val before = h.server.count("gacha_pull")
        h.store.pullGacha()
        advanceUntilIdle()
        assertEquals(before, h.server.count("gacha_pull"), "모자라면 요청을 보내지 않는다")
        h.ruby.rubyBalance = 500
        h.store.pullGacha() // 404 PGRST202 → 함수 없음 = 서버에서 아무것도 안 돌았다 → id 를 버린다
        advanceUntilIdle()
        assertNull(h.store.gachaRequestIDs.pull)
        assertEquals(GachaText.unavailable, h.store.gachaNotice)
        h.store.pullGacha()
        advanceUntilIdle()
        val ids = h.server.bodies("gacha_pull").map(::requestID)
        assertEquals(3, ids.distinct().size, "답을 받은(또는 안 돈) 요청마다 새 id: $ids")
        h.assertClean()
    }

    @Test
    fun machinePullThrowsConnectionAndHoldsTheIDWhenTheResultIsUnknown() = runTest {
        val replies = ArrayDeque<MeReply>(listOf(
            MeReply.Offline,
            MeReply.Json("""{"status":"ok","character_id":"fox","duplicate":true,"shards_gained":1,"ruby_balance":20}"""),
        ))
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "shop_state" -> MeReply.Json(shop())
                "gacha_pull" -> replies.removeFirst()
                else -> null
            }
        }
        h.openShop()
        advanceUntilIdle()
        val first = async { runCatching { h.store.pullGachaForMachine() } }
        advanceUntilIdle()
        val failure = first.await().exceptionOrNull()
        assertIs<MeGachaRevealFailure>(failure)
        assertEquals(GachaText.connection, failure.message)
        val held = h.store.gachaRequestIDs.pull ?: fail("결과를 모르면 id 를 쥔다")
        val second = async { h.store.pullGachaForMachine() }
        advanceUntilIdle()
        val reveal = second.await()
        assertEquals("fox", reveal.characterID)
        // 서버가 뒤 조각 수를 안 실었으면 앞(3) + 얻은 조각(1).
        assertEquals(4L, reveal.shardCount)
        assertEquals(3L, reveal.shardCountBefore)
        assertEquals(listOf(held, held), h.server.bodies("gacha_pull").map(::requestID))
        h.assertClean()
    }

    // ② 확률 합이 100% 가 아니면 카드를 숨긴다

    @Test
    fun gachaCardIsHiddenUnlessTheOddsSumToOneHundred() = runTest {
        data class Case(val label: String, val odds: String, val price: String, val shows: Boolean)
        val cases = listOf(
            Case("합 100", odds100, "50", true),
            Case("합 99.5", """[{"character_id":"fox","percent":60},{"character_id":"robot","percent":39.5}]""", "50", false),
            Case("합 100.005(오차 안)", """[{"character_id":"fox","percent":60.005},{"character_id":"robot","percent":40}]""", "50", true),
            Case("합 100.02(오차 밖)", """[{"character_id":"fox","percent":60.02},{"character_id":"robot","percent":40}]""", "50", false),
            Case("깨진 행이 버려져 합이 모자람", """[{"character_id":"fox","percent":60},{"character_id":"robot","percent":"40"}]""", "50", false),
            Case("빈 표", "[]", "50", false),
            Case("값 없음", odds100, "null", false),
        )
        for (case in cases) {
            val h = MeHarness(this) { r -> if (r.rpcName == "shop_state") MeReply.Json(shop(odds = case.odds, price = case.price)) else null }
            h.openShop()
            advanceUntilIdle()
            assertEquals(case.shows, h.store.showsGacha, "${case.label}: 카드")
            if (!case.shows) {
                h.store.pullGacha()
                advanceUntilIdle()
                assertEquals(0, h.server.count("gacha_pull"), "${case.label}: 숨긴 카드로는 뽑지 않는다")
            }
            h.assertClean()
        }
    }

    @Test
    fun serverWithoutGachaKeyClosesTheCardEvenIfItWasOpen() = runTest {
        var withGacha = true
        val h = MeHarness(this) { r ->
            if (r.rpcName == "shop_state") MeReply.Json(if (withGacha) shop() else """{"ruby_balance":120,"characters":[]}""") else null
        }
        h.openShop()
        advanceUntilIdle()
        assertTrue(h.store.showsGacha)
        withGacha = false
        h.store.launch { h.store.loadShop() }
        advanceUntilIdle()
        assertFalse(h.store.showsGacha, "없음도 사실이다 — 서버가 닫은 뽑기를 지난 값으로 열어 두지 않는다")
        assertNull(h.store.gachaInfo)
    }

    @Test
    fun lateResponseFromThePreviousGenerationChangesNothing() = runTest {
        val h = MeHarness(this) { r -> if (r.rpcName == "shop_state") MeReply.Json(shop()) else null }
        h.openShop()
        advanceUntilIdle()
        val ruby = h.ruby.rubyBalance
        val serial = h.ruby.rubyWriteSerial
        val stale = h.context.generation - 1
        val outcome = h.store.applyGachaPullResponse(
            GachaPullResponse(GachaPullStatus.Ok, characterID = "robot", duplicate = false, rubyBalance = 1), "x", stale,
        )
        assertNull(outcome)
        assertEquals(ruby, h.ruby.rubyBalance)
        assertEquals(serial, h.ruby.rubyWriteSerial, "미러에 쓰지 않았다")
        assertFalse("robot" in h.store.ownedCharacterIDs)
    }
}
