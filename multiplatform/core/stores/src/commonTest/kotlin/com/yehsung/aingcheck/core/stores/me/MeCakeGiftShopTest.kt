// 원본: Tests/CheckMobileKitTests/MeCakeGiftTests.swift · MeCakeGiftRepairTests.swift · MeShopProtocolTests.swift · MeRainbowProtocolTests.swift(번들 ⟺ 번호 · 선물 고르기) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.character.gift.CakeGiftText
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MeCakeGiftShopTest {
    private val pending = MeFixtures.fixture("rpc.character_gift_pending@demo-gift.json")
    private val claimed = MeFixtures.fixture("rpc.claim_character_gift.json")
    private val giftID = "d0000000-0000-4000-8000-0000000c4e01"

    private fun shop(owned: Set<String> = emptySet()): String {
        val rows = listOf("fox", "aing_cake_strawberry", "aing_cake_choco").joinToString(",") { id ->
            """{"id":"$id","price":${if (id.startsWith("aing_cake")) 2000 else 60},"owned":${id in owned},"gift_only":${id.startsWith("aing_cake")}}"""
        }
        return """{"ruby_balance":120,"characters":[$rows]}"""
    }

    private fun protocolOf(body: String): Long? = Json.parseToJsonElement(body).jsonObject["p_protocol"]?.jsonPrimitive?.content?.toLong()

    // K9 — 번들에 실린 초상 → 상점 번호(숫자를 적는 자리가 아니다)

    @Test
    fun shopProtocolIsDerivedFromTheDrawableSetAndPurchaseSendsTheSameNumber() = runTest {
        val all = MeFixtures.allPortraits
        val cases = listOf(
            all to 4L,
            all - "aing_cake_choco" to 3L,
            all - "aing_rainbow" to 2L,
            all - "aing_gold" to 1L,
            all - "robot" to null, // 0 이면 키째 뺀다(옛 서명 `{}`)
        )
        for ((drawable, expected) in cases) {
            val h = MeHarness(this, drawable = drawable) { r ->
                when (r.rpcName) {
                    "shop_state" -> MeReply.Json(shop())
                    "buy_character" -> MeReply.Json("""{"status":"ok","character":"fox","ruby_balance":60}""")
                    "character_gift_pending" -> MeReply.Json("""{"status":"ok","gift":null}""")
                    else -> null
                }
            }
            h.signIn()
            h.store.launch { h.store.loadShop() }
            advanceUntilIdle()
            h.store.selectShopItem("fox")
            h.store.confirmPurchase()
            advanceUntilIdle()
            val label = "그림 ${drawable.size}장 빠짐 ${all - drawable}"
            assertEquals(expected, protocolOf(h.server.bodies("shop_state").first()), "$label: shop_state")
            assertEquals(expected, protocolOf(h.server.bodies("buy_character").single()), "$label: 목록과 구매가 같은 번호")
            h.store.loadCakeGift()
            advanceUntilIdle()
            assertEquals(if (expected == 4L) 1 else 0, h.server.count("character_gift_pending"), "$label: 케이크를 다 못 그리면 선물을 묻지 않는다")
            h.assertClean()
        }
    }

    // 케이크 선물 고르기

    @Test
    fun openGiftPresentsItselfOncePerRunAndWaitsWhileAMatchScreenIsUp() = runTest {
        val h = MeHarness(this) { r -> if (r.rpcName == "character_gift_pending") MeReply.Json(pending) else if (r.rpcName == "shop_state") MeReply.Json(shop()) else null }
        h.signIn()
        h.links.matchScreenVisible = true
        h.store.refreshCakeGiftIfStale()
        advanceUntilIdle()
        assertNotNull(h.store.cakeGift)
        assertNull(h.store.cakeGiftSheet, "대국·관전 화면 위에는 스스로 띄우지 않는다")
        assertTrue(h.store.showsCakeGiftReopen, "그동안은 '다시 열기' 줄")
        h.store.refreshCakeGiftIfStale() // 10분 안 — 묻지 않는다
        advanceUntilIdle()
        assertEquals(1, h.server.count("character_gift_pending"))

        h.links.matchScreenVisible = false
        h.store.presentCakeGiftIfDue() // 탭을 옮길 때 · 앞에 올 때
        val sheet = assertNotNull(h.store.cakeGiftSheet)
        assertEquals(listOf("aing_cake_strawberry", "aing_cake_choco"), sheet.gift.options, "내장 순서")
        h.store.cakeGiftSheetDidAppear()
        h.store.dismissCakeGiftSheet()
        assertTrue(h.store.showsCakeGiftReopen)

        advanceTimeBy(601_000)
        // 앞에 올 때(appDidBecomeActive)의 선물 몫 두 줄.
        h.store.presentCakeGiftIfDue()
        h.store.refreshCakeGiftIfStale()
        advanceUntilIdle()
        assertEquals(2, h.server.count("character_gift_pending"), "10분이 지나면 다시 묻는다")
        assertNull(h.store.cakeGiftSheet, "이 실행에서 이미 화면에 선 선물은 스스로 다시 뜨지 않는다")
    }

    @Test
    fun choosingAndClaimingAddsOwnershipAndRereadsTheShop() = runTest {
        var owned = emptySet<String>()
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "character_gift_pending" -> MeReply.Json(pending)
                "claim_character_gift" -> MeReply.Json(claimed).also { owned = setOf("aing_cake_strawberry") }
                "shop_state" -> MeReply.Json(shop(owned))
                "set_character" -> MeReply.Json("""{"status":"ok","character":"aing_cake_strawberry"}""")
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadCakeGift() }
        advanceUntilIdle()
        h.store.confirmCakeGift() // 고르기 전에는 확인 단추가 꺼져 있다
        advanceUntilIdle()
        assertEquals(0, h.server.count("claim_character_gift"))
        h.store.selectCakeGiftOption("fox") // 선택지에 없는 것은 고를 수 없다
        assertNull(h.store.cakeGiftSheet!!.selection)
        h.store.selectCakeGiftOption("aing_cake_strawberry")
        h.store.confirmCakeGift()
        assertEquals(MeCakeGiftSheet.Phase.Claiming, h.store.cakeGiftSheet!!.phase)
        h.store.dismissCakeGiftSheet() // 받는 중에는 닫지 않는다
        assertNotNull(h.store.cakeGiftSheet)
        advanceUntilIdle()

        val body = Json.parseToJsonElement(h.server.bodies("claim_character_gift").single()).jsonObject
        assertEquals(giftID, body.getValue("p_gift").jsonPrimitive.content)
        assertEquals("aing_cake_strawberry", body.getValue("p_character").jsonPrimitive.content)
        assertEquals("4", body.getValue("p_protocol").jsonPrimitive.content)
        assertEquals(MeCakeGiftSheet.Phase.Received("aing_cake_strawberry"), h.store.cakeGiftSheet!!.phase)
        assertTrue(h.store.isOwned("aing_cake_strawberry"))
        assertNull(h.store.cakeGift, "선물이 끝났다 — '다시 열기' 줄이 걷힌다")
        assertEquals(1, h.server.count("shop_state"), "받은 뒤 서버 보유를 다시 읽는다")
        h.store.wearReceivedCakeGift()
        advanceUntilIdle()
        assertNull(h.store.cakeGiftSheet)
        assertEquals("aing_cake_strawberry", h.store.equippedServerID, "[지금 입기]는 기존 착용 경로를 탄다")
        assertEquals(listOf<String?>("aing_cake_strawberry"), h.links.equipped)
        h.assertClean()
    }

    @Test
    fun unknownClaimResultReturnsToChoosingWithAOneLineNotice() = runTest {
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "character_gift_pending" -> MeReply.Json(pending)
                "claim_character_gift" -> MeReply.Offline
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadCakeGift() }
        advanceUntilIdle()
        h.store.selectCakeGiftOption("aing_cake_choco")
        h.store.confirmCakeGift()
        advanceUntilIdle()
        val sheet = h.store.cakeGiftSheet!!
        assertEquals(MeCakeGiftSheet.Phase.Choosing, sheet.phase)
        assertEquals(CakeGiftText.claimFailed, sheet.notice)
        assertEquals("aing_cake_choco", sheet.selection, "같은 선택으로 다시 누르면 된다(replayed)")
        assertNotNull(h.store.cakeGift, "선물은 그대로 열려 있다")
        h.assertClean()
    }

    @Test
    fun ownershipFromTheShopFiltersTheOfferAndAsksTheServerAgain() = runTest {
        var owned = emptySet<String>()
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "character_gift_pending" -> MeReply.Json(pending)
                "shop_state" -> MeReply.Json(shop(owned))
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadCakeGift() }
        advanceUntilIdle()
        h.store.selectCakeGiftOption("aing_cake_strawberry")
        owned = setOf("aing_cake_strawberry") // 다른 기기에서 받았다
        h.store.launch { h.store.loadShop() }
        advanceUntilIdle()
        assertEquals(listOf("aing_cake_choco"), h.store.cakeGift!!.options, "이미 가진 케이크를 고르는 길이 없다")
        val sheet = h.store.cakeGiftSheet!!
        assertEquals(listOf("aing_cake_choco"), sheet.gift.options)
        assertNull(sheet.selection, "고른 것이 가진 것이면 고름을 푼다")
        assertEquals(2, h.server.count("character_gift_pending"), "보유가 움직였으면 스로틀 없이 서버에 다시 묻는다")
        assertTrue("aing_cake_strawberry" in h.store.pickerIDs, "가진 케이크는 고르기 목록에 선다")
        assertTrue("aing_cake_choco" !in h.store.pickerIDs, "안 가진 선물 전용은 고르기 목록에 서지 않는다")
        h.assertClean()
    }
}
