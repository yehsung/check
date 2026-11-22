// 원본: Sources/check/WorkTimerStoreCakeGift.swift:116-160(refreshCakeGift — 조회 전 region_gift_ensure, 세대당 한 번) ·
//       Sources/CheckCore/RegionGift.swift(ensureRegionGift) · SantaGift.swift(문구) @ main 341eb4e3
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.character.gift.SantaGiftText
import com.yehsung.aingcheck.core.rules.gacha.ShopWire
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftKind
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * 판 9 — 지역 아잉이(우리 센터 선물 · 번호 10) · 산타 아잉이(크리스마스 선물 · 번호 11). 아이폰 1.0.19 와 같이 그림을 싣고(ui Gradle Sync),
 * 스토어는 선물을 묻기 **전에** 서버에 우리 센터 선물을 마련해 달라고 한다(맥 0.3.85 와 같은 순서 · 세대당 한 번).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class V9RegionSantaGiftTest {
    /** 판 9 의 Android 그림 집합(번호 11) — 상점 번호 사다리의 모든 캐릭터. */
    private val v9 = MeFixtures.allPortraits + setOf(
        "aing_isul", "aing_pepero", "aing_hwoo", "aing_ruby", "aing_dev", "aing_busan", "aing_seoul", "aing_santa",
    )

    private fun protocolOf(body: String): Long? = Json.parseToJsonElement(body).jsonObject["p_protocol"]?.jsonPrimitive?.content?.toLong()

    private val santaPending =
        """{"status":"ok","gift":{"id":"d0000000-0000-4000-8000-00000005a171","kind":"santa","options":["aing_santa"],""" +
            """"note":null,"created_at":"2026-12-21T00:00:00.000000+00:00"}}"""

    @Test
    fun ensureGoesBeforeTheLookupOncePerSignIn() = runTest {
        val h = MeHarness(this, drawable = v9) { r ->
            when (r.rpcName) {
                "region_gift_ensure" -> MeReply.Json("""{"status":"granted"}""")
                "character_gift_pending" -> MeReply.Json("""{"status":"ok","gift":null}""")
                else -> null
            }
        }
        h.signIn()
        h.store.loadCakeGift()
        advanceUntilIdle()
        val order = h.server.requests.map { it.rpcName }.filter { it == "region_gift_ensure" || it == "character_gift_pending" }
        assertEquals(listOf("region_gift_ensure", "character_gift_pending"), order, "마련을 묻기 전에 한다(맥과 같은 순서)")
        assertEquals(11L, protocolOf(h.server.bodies("region_gift_ensure").single()), "마련 본문의 번호 = 판 9 의 번호 11")
        assertEquals(11L, protocolOf(h.server.bodies("character_gift_pending").single()))

        h.store.loadCakeGift()
        advanceUntilIdle()
        assertEquals(1, h.server.count("region_gift_ensure"), "같은 로그인(세대)에서는 한 번만 말한다")
        assertEquals(2, h.server.count("character_gift_pending"))
        h.assertClean()
    }

    @Test
    fun aFailedEnsureStillAsksAndTriesAgainNextTime() = runTest {
        var ensureReply: MeReply = MeReply.serverDown
        val h = MeHarness(this, drawable = v9) { r ->
            when (r.rpcName) {
                "region_gift_ensure" -> ensureReply
                "character_gift_pending" -> MeReply.Json("""{"status":"ok","gift":null}""")
                else -> null
            }
        }
        h.signIn()
        h.store.loadCakeGift()
        advanceUntilIdle()
        assertEquals(1, h.server.count("character_gift_pending"), "마련이 실패해도 선물은 묻는다")
        ensureReply = MeReply.Json("""{"status":"pending"}""")
        h.store.loadCakeGift()
        advanceUntilIdle()
        assertEquals(2, h.server.count("region_gift_ensure"), "실패한 마련은 다음 조회 박자에 다시 말한다")
        h.store.loadCakeGift()
        advanceUntilIdle()
        assertEquals(2, h.server.count("region_gift_ensure"), "성공한 뒤로는 다시 말하지 않는다")
    }

    @Test
    fun withoutRegionArtTheBuildNeverAsksToEnsure() = runTest {
        val h = MeHarness(this, drawable = v9 - "aing_seoul") { r ->
            if (r.rpcName == "character_gift_pending") MeReply.Json("""{"status":"ok","gift":null}""") else null
        }
        h.signIn()
        h.store.loadCakeGift()
        advanceUntilIdle()
        assertEquals(0, h.server.count("region_gift_ensure"), "서울 그림이 없는 빌드(번호 9)는 마련을 말하지 않는다")
        assertEquals(ShopWire.devProtocol.toLong(), protocolOf(h.server.bodies("character_gift_pending").single()))
        h.assertClean()
    }

    @Test
    fun aSantaGiftOpensWithTheDecidedCopyOnlyWhenSantaIsDrawable() = runTest {
        val h = MeHarness(this, drawable = v9) { r ->
            when (r.rpcName) {
                "region_gift_ensure" -> MeReply.Json("""{"status":"owned"}""")
                "character_gift_pending" -> MeReply.Json(santaPending)
                else -> null
            }
        }
        h.signIn()
        h.store.loadCakeGift()
        advanceUntilIdle()
        val gift = assertNotNull(h.store.cakeGift, "번호 11 빌드에 산타 선물이 선다")
        assertEquals(CharacterGiftKind.santa, gift.kind)
        assertEquals(listOf("aing_santa"), gift.options)
        val sheet = MeCakeGiftSheet.open(gift)
        assertEquals("aing_santa", sheet.selection, "고를 것 없는 선물 — 미리 골라 둔다([선물 열기]가 곧바로 켜진다)")
        assertEquals(SantaGiftText.title, sheet.texts.title)
        assertEquals("띵동! 산타 왔어요 🎁", sheet.texts.title, "대표 #d_4wR1Qzn9OKmt 원문")
        assertEquals("선물 열기", sheet.texts.confirmButton)
        assertEquals("띵동! 산타 선물이 기다려요 🎁", sheet.texts.reopenTitle)

        // 산타 그림이 없는 빌드(번호 10)는 섞여 온 산타 선물을 버린다(수령이 needs_update — 받을 수 없는 창을 띄우지 않는다).
        val h10 = MeHarness(this, drawable = v9 - "aing_santa") { r ->
            when (r.rpcName) {
                "region_gift_ensure" -> MeReply.Json("""{"status":"owned"}""")
                "character_gift_pending" -> MeReply.Json(santaPending)
                else -> null
            }
        }
        h10.signIn()
        h10.store.loadCakeGift()
        advanceUntilIdle()
        assertEquals(10L, protocolOf(h10.server.bodies("character_gift_pending").single()))
        assertNull(h10.store.cakeGift, "번호 10 빌드에 산타 선물이 섰다")
    }
}
