// 원본: Tests/CheckMobileKitTests/MeGachaStoreTests.swift · MeGachaMachineTests.swift(request_id 쥔 채 재시도 — 뽑기·조각 교환 · 확률 합 ≠ 100% 면 숨김 · 세대 가드) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.gacha.GachaExchangeAvailability
import com.yehsung.aingcheck.core.rules.gacha.GachaText
import com.yehsung.aingcheck.core.wire.models.GachaExchangeResponse
import com.yehsung.aingcheck.core.wire.models.GachaExchangeStatus
import com.yehsung.aingcheck.core.wire.models.GachaPullResponse
import com.yehsung.aingcheck.core.wire.models.GachaPullStatus
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
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

    /**
     * Swift `MeGachaStoreTests.shopV2` — 서버 `shop_state` 의 금까지 7줄 응답(AMENDMENT 1 교환값 — 금 20 · 2/2/4/4/5/8). 교환 시험이 쓴다.
     * 기대값은 손으로 적은 글자다(코어 함수로 기대값을 다시 만들지 않는다).
     */
    private fun shopV2(ruby: Long = 120, shards: Long = 0, owned: Set<String> = setOf("fox")): String {
        fun row(id: String, price: Int, gachaOnly: Boolean = false) =
            """{"id":"$id","price":$price,"owned":${id in owned},"gacha_only":$gachaOnly}"""
        val rows = listOf(
            row("fox", 60), row("squirrel", 60), row("ghost", 100), row("shiba", 100), row("jellyfish", 140),
            row("robot", 200), row("aing_gold", 1000, gachaOnly = true),
        ).joinToString(",")
        return """{"ruby_balance":$ruby,"characters":[$rows],
            "gacha":{"price":50,"shards":$shards,
                     "odds":[{"character_id":"aing_gold","percent":5},{"character_id":"fox","percent":24},
                             {"character_id":"squirrel","percent":24},{"character_id":"shiba","percent":14},
                             {"character_id":"ghost","percent":14},{"character_id":"jellyfish","percent":11},
                             {"character_id":"robot","percent":8}],
                     "shard_costs":{"aing_gold":20,"fox":2,"squirrel":2,"shiba":4,"ghost":4,"jellyfish":5,"robot":8}}}"""
    }

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

    // ① 조각 교환도 같은 규약이다(교환은 캐릭터마다 칸이 따로 — GachaRequestIDs.exchangeID)

    @Test
    fun exchangeSendsThreeKeysTakesTheServerShardsAndOneTapIsOneRequest() = runTest {
        // Swift MeGachaStoreTests.exchangeFlow — 본문 키 셋 · 서버 조각 수 · 보유 · 안내 · 모자라면 요청 없음 · 서버 insufficient_shards · 연타 = 요청 하나.
        var shopBody = shopV2(shards = 5)
        val exchangeGate = CompletableDeferred<Unit>()
        val replies = ArrayDeque<MeReply>(listOf(
            MeReply.Gate(exchangeGate, MeReply.Json(
                """{"status":"ok","character_id":"squirrel","shards":3,"cost":2,"request_id":"00000000-0000-4000-8000-0000000000e1","replayed":false}""",
            )),
            MeReply.Json("""{"status":"insufficient_shards","need":4,"have":1}"""),
        ))
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "shop_state" -> MeReply.Json(shopBody)
                "gacha_exchange" -> replies.removeFirst()
                else -> null
            }
        }
        h.openShop()
        runCurrent()
        assertEquals(5L, h.store.gachaShards)

        shopBody = shopV2(shards = 3, owned = setOf("fox", "squirrel")) // 교환 뒤 다시 읽기가 받을 서버 값
        h.store.exchangeShards("squirrel")
        h.store.exchangeShards("squirrel") // 연타
        h.store.exchangeShards("shiba") // 떠 있는 교환이 있으면 다른 캐릭터도 기다린다
        assertEquals("squirrel", h.store.exchangingID)
        runCurrent() // 문에서 멈춘다(가상 시계를 돌리지 않는다 — HttpTimeout 이 문을 먼저 끊지 않게)
        assertEquals(1, h.server.count("gacha_exchange"), "교환 중에 또 눌러 요청이 더 나갔다")
        exchangeGate.complete(Unit)
        runCurrent()

        val body = Json.parseToJsonElement(h.server.bodies("gacha_exchange").single()).jsonObject
        assertEquals(setOf("p_character_id", "p_protocol", "p_request_id"), body.keys, "본문 $body")
        assertEquals("squirrel", body.getValue("p_character_id").jsonPrimitive.content)
        assertEquals(4, body.getValue("p_protocol").jsonPrimitive.int, "번호 4(초상이 다 실린 번들) — 2 면 무지개 교환이 needs_update 로 거절된다")
        assertTrue(h.store.isOwned("squirrel"))
        assertEquals(3L, h.store.gachaShards, "조각은 서버 값")
        assertEquals("교환했어요: 다람쥐", h.store.exchangeNotice)
        assertFalse(h.store.isExchangeNoticeError)
        assertEquals(120L, h.ruby.rubyBalance, "교환이 루비를 움직였다")
        assertNull(h.store.exchangingID)
        assertNull(h.store.gachaRequestIDs.exchange["squirrel"], "서버가 답했다 — 그 id 의 일은 끝났다")

        // 조각 3 으로 해파리(5)는 못 바꾼다 — 요청 없이 이유.
        h.store.exchangeShards("jellyfish")
        runCurrent()
        assertEquals(1, h.server.count("gacha_exchange"))
        assertEquals("조각 2개 더 필요해요", h.store.exchangeNotice)
        // 가진 것은 "이미 갖고 있어요".
        h.store.exchangeShards("fox")
        assertEquals(GachaText.alreadyOwned, h.store.exchangeNotice)

        // 클라는 조각 5 로 알지만(강아지 4 를 바꿀 수 있다) 서버는 그새 1 이라고 말한다(다른 기기에서 썼다).
        shopBody = shopV2(shards = 5, owned = setOf("fox", "squirrel"))
        h.store.launch { h.store.loadShop() }
        runCurrent()
        assertEquals(GachaExchangeAvailability.available(4), h.store.gachaExchangeAvailability("shiba"))
        h.store.exchangeShards("shiba")
        runCurrent()
        assertEquals("조각 3개 더 필요해요", h.store.exchangeNotice)
        assertTrue(h.store.isExchangeNoticeError)
        assertEquals(1L, h.store.gachaShards, "서버가 말한 조각 수로 맞춘다")
        assertFalse(h.store.isOwned("shiba"))
        assertEquals(2, h.server.count("gacha_exchange"))
        h.assertClean()
    }

    @Test
    fun exchangeWithAnUnknownResultHoldsItsRequestIDUntilTheServerAnswers() = runTest {
        // 오프라인 · 5xx 는 결과를 모른다 — 같은 캐릭터를 다시 누르면 **같은 id** 로 묻는다(서버가 이미 처리했으면 replayed). 답(needs_update)을
        // 받은 뒤의 누름은 새 동작이라 새 id 다.
        val exchanged = MeReply.Json("""{"status":"ok","character_id":"squirrel","shards":3,"cost":2,"replayed":false}""")
        val replies = ArrayDeque<MeReply>(listOf(
            MeReply.Offline,
            MeReply.serverDown,
            MeReply.Json("""{"status":"needs_update"}"""),
            exchanged,
        ))
        var squirrelOwned = false
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "shop_state" -> MeReply.Json(if (squirrelOwned) shopV2(shards = 3, owned = setOf("fox", "squirrel")) else shopV2(shards = 5))
                "gacha_exchange" -> replies.removeFirst().also { if (it === exchanged) squirrelOwned = true }
                else -> null
            }
        }
        h.openShop()
        advanceUntilIdle()

        h.store.exchangeShards("squirrel")
        advanceUntilIdle()
        assertEquals(GachaText.connection, h.store.exchangeNotice, "오프라인 = 결과 모름 → 연결 안내")
        assertTrue(h.store.isExchangeNoticeError)
        val held = requestID(h.server.bodies("gacha_exchange")[0])
        assertEquals(held, h.store.gachaRequestIDs.exchange["squirrel"], "결과를 모르면 id 를 **쥔 채** 둔다")
        assertFalse(h.store.isOwned("squirrel"))

        h.store.exchangeShards("squirrel") // 5xx — 여전히 결과 모름
        advanceUntilIdle()
        assertEquals(held, h.store.gachaRequestIDs.exchange["squirrel"])
        h.store.exchangeShards("squirrel") // needs_update — 서버의 답이다
        advanceUntilIdle()
        assertEquals("앱을 업데이트하면 교환할 수 있어요", h.store.exchangeNotice)
        assertNull(h.store.gachaRequestIDs.exchange["squirrel"], "답을 받은 id 는 버린다")
        h.store.exchangeShards("squirrel") // 새 동작
        advanceUntilIdle()

        val ids = h.server.bodies("gacha_exchange").map(::requestID)
        assertEquals(4, ids.size)
        assertEquals(listOf(held, held, held), ids.take(3), "결과를 모르는 재시도는 같은 id: $ids")
        assertEquals(held.lowercase(), held, "서버에는 소문자 uuid")
        assertNotEquals(held, ids[3], "답을 받은 뒤의 누름은 새 id")
        assertTrue(h.store.isOwned("squirrel"))
        h.assertClean()
    }

    @Test
    fun leavingTheShopWithAnUnknownResultKeepsBothRequestIDsForTheReturn() = runTest {
        // 상점을 떠나면 안내·연출은 걷지만 결과를 모르는 request_id 는 **남긴다** — 돌아와 다시 누르면 같은 id 로 물어 두 번 깎이지 않는다.
        val pullReplies = ArrayDeque<MeReply>(listOf(
            MeReply.Offline,
            MeReply.Json("""{"status":"ok","character_id":"ghost","duplicate":false,"shards_gained":0,"shards":5,"ruby_balance":70,"replayed":true}"""),
        ))
        val exchangeReplies = ArrayDeque<MeReply>(listOf(
            MeReply.Offline,
            MeReply.Json("""{"status":"ok","character_id":"squirrel","shards":3,"cost":2,"replayed":true}"""),
        ))
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "shop_state" -> MeReply.Json(shopV2(shards = if (exchangeReplies.isEmpty()) 3 else 5))
                "gacha_pull" -> pullReplies.removeFirst()
                "gacha_exchange" -> exchangeReplies.removeFirst()
                else -> null
            }
        }
        h.openShop()
        advanceUntilIdle()
        h.store.pullGacha()
        h.store.exchangeShards("squirrel")
        advanceUntilIdle()
        val pullID = assertNotNull(h.store.gachaRequestIDs.pull, "결과 모름 — 뽑기 id 를 쥔다")
        val exchangeID = assertNotNull(h.store.gachaRequestIDs.exchange["squirrel"], "결과 모름 — 교환 id 를 쥔다")

        h.store.shopDidDisappear()
        assertNull(h.store.gachaNotice, "떠나면 안내는 걷는다")
        assertNull(h.store.exchangeNotice)
        assertEquals(pullID, h.store.gachaRequestIDs.pull, "떠나도 결과를 모르는 뽑기 id 는 남는다")
        assertEquals(exchangeID, h.store.gachaRequestIDs.exchange["squirrel"], "떠나도 결과를 모르는 교환 id 는 남는다")

        h.store.pullGacha()
        h.store.exchangeShards("squirrel")
        advanceUntilIdle()
        assertEquals(listOf(pullID, pullID), h.server.bodies("gacha_pull").map(::requestID), "돌아와 누른 뽑기가 새 id 로 또 깎는다")
        assertEquals(listOf(exchangeID, exchangeID), h.server.bodies("gacha_exchange").map(::requestID), "돌아와 누른 교환이 새 id 로 또 깎는다")
        assertNull(h.store.gachaRequestIDs.pull)
        assertNull(h.store.gachaRequestIDs.exchange["squirrel"])
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
        var robotOwnedOnServer = false
        val h = MeHarness(this) { r -> if (r.rpcName == "shop_state") MeReply.Json(shop(robotOwned = robotOwnedOnServer)) else null }
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

        // 교환도 같다(Swift generationGuardAndReset 의 lateExchange) — 옛 세대 응답은 보유·조각·안내를 건드리지 않는다.
        val shards = h.store.gachaShards
        h.store.applyGachaExchangeResponse(
            GachaExchangeResponse(GachaExchangeStatus.Ok, characterID = "robot", shards = 1, cost = 8), "robot", "x", stale,
        )
        assertFalse("robot" in h.store.ownedCharacterIDs, "옛 세대 교환 응답이 보유를 더했다")
        assertEquals(shards, h.store.gachaShards, "옛 세대 교환 응답이 조각 수를 바꿨다")
        assertNull(h.store.exchangeNotice)
        // 기준선: 같은 세대면 옮긴다(가드가 모든 응답을 버리지 않는다). 옮긴 뒤 다시 읽는 상점은 서버의 새 보유를 말한다.
        robotOwnedOnServer = true
        h.store.applyGachaExchangeResponse(
            GachaExchangeResponse(GachaExchangeStatus.Ok, characterID = "robot", shards = 1, cost = 8), "robot", "x", h.context.generation,
        )
        assertTrue("robot" in h.store.ownedCharacterIDs)
        assertEquals("교환했어요: 로봇", h.store.exchangeNotice)
    }
}
