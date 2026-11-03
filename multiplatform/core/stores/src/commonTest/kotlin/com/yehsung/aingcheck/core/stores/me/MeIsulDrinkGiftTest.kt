// 원본: Sources/check/WorkTimerStoreCakeGift.swift @ 12624739 (맥 0.3.74 — 종류를 아는 선물 박자 · ⑤ 다음 선물 · 보유 거름의 종류 옮김)
//       Tests/CheckMobileKitTests/MeIsulProtocolPinTests.swift(번호 핀) · supabase/migrations/20261108122000_isul_aing_drink_gift.sql(프로토콜 절)
//
// 이슬 아잉이 — '술 한잔' 선물(Android 판 7). 서버 실출력 모양(20261108122000 의 character_gift_pending · claim_character_gift 갈래)을 스텁으로 주고
// 스토어의 진짜 경로(조회 → 시트 → 받기 → 상점 다시 읽기 → 다음 선물)를 돈다. 두 그림 집합으로 잰다:
//   · Android = 초상 열둘(이슬 포함) → 번호 5 · 술 선물을 받는다 · 결론마다 다음 선물을 한 번 묻는다.
//   · 데스크톱(Windows v1) = 초상 열하나(이슬 빼냄 — ui CharacterArt.takesDrinkGift 거짓) → 번호 4 · 0.3.73 흐름 그대로(되묻기 0).
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.character.gift.CakeGiftText
import com.yehsung.aingcheck.core.rules.character.gift.CharacterGiftCopy
import com.yehsung.aingcheck.core.rules.character.gift.DrinkGiftText
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftKind
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MeIsulDrinkGiftTest {
    private val android = MeFixtures.allPortraits + ISUL
    private val desktop = MeFixtures.allPortraits

    /** 서버 p ≥ 5 응답 — gift 에 kind 를 싣는다(20261108122000 character_gift_pending). */
    private fun drinkPending(id: String = DRINK_GIFT, note: String? = null) =
        """{"status":"ok","gift":{"id":"$id","kind":"drink","options":["$ISUL"],"note":${note?.let { "\"$it\"" } ?: "null"},"created_at":"2026-11-03T09:00:00.123456+00:00"}}"""

    private fun birthdayPending(id: String = CAKE_GIFT) =
        """{"status":"ok","gift":{"id":"$id","kind":"birthday","options":["aing_cake_strawberry","aing_cake_choco"],"note":null,"created_at":"2026-11-01T09:00:00+00:00"}}"""

    private val none = """{"status":"ok"}"""

    /**
     * p ≥ 5 shop_state — 이슬 행(장식값 2002 · gacha_only · gift_only, 미보유면 잠긴 칸). [isulRow] 거짓 = p < 5 응답(서버 §5-2: 이슬 행은
     * 가진 사람에게도 싣지 않는다 — 데스크톱 Windows v1 이 받는 모양).
     */
    private fun shop(owned: Set<String> = emptySet(), isulRow: Boolean = true): String {
        val ids = listOf("fox" to 60, "aing_cake_strawberry" to 2000, "aing_cake_choco" to 2001) + (if (isulRow) listOf(ISUL to 2002) else emptyList())
        val rows = ids.joinToString(",") { (id, price) ->
            val gift = id.startsWith("aing_")
            """{"id":"$id","price":$price,"owned":${id in owned},"gacha_only":$gift,"gift_only":$gift}"""
        }
        return """{"ruby_balance":120,"characters":[$rows]}"""
    }

    private fun protocolOf(body: String): String? = Json.parseToJsonElement(body).jsonObject["p_protocol"]?.jsonPrimitive?.content

    @Test
    fun androidSaysFiveAndDesktopStaysFourOnEveryShopAndGiftCall() = runTest {
        for ((drawable, expected) in listOf(android to "5", desktop to "4")) {
            val h = MeHarness(this, drawable = drawable) { r ->
                when (r.rpcName) {
                    "shop_state" -> MeReply.Json(shop())
                    "character_gift_pending" -> MeReply.Json(none)
                    else -> null
                }
            }
            h.signIn()
            h.store.launch { h.store.loadShop() }
            h.store.launch { h.store.loadCakeGift() }
            advanceUntilIdle()
            assertEquals(expected, protocolOf(h.server.bodies("shop_state").single()), "shop_state")
            assertEquals(expected, protocolOf(h.server.bodies("character_gift_pending").single()), "character_gift_pending")
            h.assertClean()
        }
    }

    @Test
    fun drinkGiftOpensAnInvitationWithItsOnlyOptionPreselectedAndClaimsAtFive() = runTest {
        var owned = emptySet<String>()
        val h = MeHarness(this, drawable = android) { r ->
            when (r.rpcName) {
                "character_gift_pending" -> MeReply.Json(if (ISUL in owned) none else drinkPending(note = "오늘 한잔 어때?"))
                "claim_character_gift" -> MeReply.Json("""{"status":"ok","character_id":"$ISUL","replayed":false}""").also { owned = setOf(ISUL) }
                "shop_state" -> MeReply.Json(shop(owned))
                "set_character" -> MeReply.Json("""{"status":"ok","character":"$ISUL"}""")
                else -> null
            }
        }
        h.signIn()
        h.store.refreshCakeGiftIfStale()
        advanceUntilIdle()
        val gift = assertNotNull(h.store.cakeGift)
        assertEquals(CharacterGiftKind.drink, gift.kind)
        assertEquals(listOf(ISUL), gift.options)
        assertEquals("오늘 한잔 어때?", gift.note)
        val sheet = assertNotNull(h.store.cakeGiftSheet, "열린 술 선물은 스스로 선다(실행당 한 번)")
        assertFalse(sheet.choosesOption, "고를 것이 없다")
        assertEquals(ISUL, sheet.selection, "이슬 하나를 미리 골라 둔다")
        assertTrue(sheet.canConfirm, "[짠 받기]가 곧바로 켜진다")
        assertEquals(CharacterGiftCopy.drink, sheet.texts)
        assertEquals("짠! 🥂", sheet.texts.title)
        assertEquals("짠 받기", sheet.texts.confirmButton)
        h.store.cakeGiftSheetDidAppear()

        h.store.confirmCakeGift()
        advanceUntilIdle()
        val body = Json.parseToJsonElement(h.server.bodies("claim_character_gift").single()).jsonObject
        assertEquals(DRINK_GIFT, body.getValue("p_gift").jsonPrimitive.content)
        assertEquals(ISUL, body.getValue("p_character").jsonPrimitive.content)
        assertEquals("5", body.getValue("p_protocol").jsonPrimitive.content)
        assertEquals(MeCakeGiftSheet.Phase.Received(ISUL), h.store.cakeGiftSheet!!.phase)
        assertEquals("이슬 아잉이를 받았어요!", h.store.cakeGiftSheet!!.texts.received(MeCharacterName.display(ISUL)))
        assertTrue(h.store.isOwned(ISUL))
        assertNull(h.store.cakeGift)
        assertEquals(1, h.server.count("shop_state"), "받은 뒤 서버 보유를 다시 읽는다")
        assertEquals(1, h.server.count("character_gift_pending"), "받은 뒤 화면이 떠 있는 동안은 다음 선물을 묻지 않는다(겹치지 않게)")

        h.store.wearReceivedCakeGift()
        advanceUntilIdle()
        assertNull(h.store.cakeGiftSheet)
        assertEquals(ISUL, h.store.equippedServerID, "[지금 입기]는 기존 착용 경로를 탄다")
        assertEquals(2, h.server.count("character_gift_pending"), "결론 난 시트를 닫으면 다음 선물을 한 번 묻는다(맥 ⑤)")
        assertEquals(1, h.store.cakeGiftFollowUps)
        assertTrue(ISUL in h.store.pickerIDs, "가진 이슬은 고르기 목록에 선다")
        h.assertClean()
    }

    @Test
    fun birthdayFirstThenTheDrinkGiftComesOnlyAfterTheFirstIsReceived() = runTest {
        // 서버는 두 종류 중 **먼저 지급된** 열린 선물 하나만 준다(생일이 먼저). 받아야 다음 것이 나온다.
        var claimedBirthday = false
        val h = MeHarness(this, drawable = android) { r ->
            when (r.rpcName) {
                "character_gift_pending" -> MeReply.Json(if (claimedBirthday) drinkPending() else birthdayPending())
                "claim_character_gift" -> MeReply.Json("""{"status":"ok","character_id":"aing_cake_choco","replayed":false}""").also { claimedBirthday = true }
                "shop_state" -> MeReply.Json(shop(if (claimedBirthday) setOf("aing_cake_choco") else emptySet()))
                else -> null
            }
        }
        h.signIn()
        h.store.refreshCakeGiftIfStale()
        advanceUntilIdle()
        val first = assertNotNull(h.store.cakeGiftSheet)
        assertEquals(CharacterGiftKind.birthday, first.kind)
        assertTrue(first.choosesOption)
        assertNull(first.selection, "생일은 고르지 않은 채로 선다")
        assertEquals(CharacterGiftCopy.birthday, first.texts)
        h.store.cakeGiftSheetDidAppear()
        // 고르지 않고 닫으면 같은 선물이 '다시 열기' 줄로 남는다(다음 선물을 묻지 않는다 — 결론이 안 났다).
        h.store.dismissCakeGiftSheet()
        advanceUntilIdle()
        assertTrue(h.store.showsCakeGiftReopen)
        assertEquals(CAKE_GIFT, h.store.cakeGift!!.id)
        assertEquals(1, h.server.count("character_gift_pending"))
        assertEquals(0, h.store.cakeGiftFollowUps)

        h.store.reopenCakeGift()
        advanceUntilIdle()
        assertEquals(CAKE_GIFT, h.store.cakeGiftSheet!!.id, "[고르기]는 같은 선물을 다시 연다")
        h.store.selectCakeGiftOption("aing_cake_choco")
        h.store.confirmCakeGift()
        advanceUntilIdle()
        assertEquals(MeCakeGiftSheet.Phase.Received("aing_cake_choco"), h.store.cakeGiftSheet!!.phase)
        h.store.dismissCakeGiftSheet()
        advanceUntilIdle()
        val next = assertNotNull(h.store.cakeGiftSheet, "생일을 받고 닫으면 술 선물이 이어서 선다")
        assertEquals(DRINK_GIFT, next.id)
        assertEquals(CharacterGiftKind.drink, next.kind)
        assertEquals(ISUL, next.selection)
        assertEquals(1, h.store.cakeGiftFollowUps)
        h.assertClean()
    }

    @Test
    fun needsUpdateKeepsTheGiftOpenWithTheUpdateLineAndAsksNothingMore() = runTest {
        val h = MeHarness(this, drawable = android) { r ->
            when (r.rpcName) {
                "character_gift_pending" -> MeReply.Json(drinkPending())
                "claim_character_gift" -> MeReply.Json("""{"status":"needs_update","min_protocol":5}""")
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadCakeGift() }
        advanceUntilIdle()
        h.store.confirmCakeGift()
        advanceUntilIdle()
        val sheet = h.store.cakeGiftSheet!!
        assertEquals(MeCakeGiftSheet.Phase.Choosing, sheet.phase, "업데이트 필요 — 선물은 그대로 열려 있다")
        assertEquals(CakeGiftText.needsUpdate, sheet.notice)
        assertEquals(DrinkGiftText.notice(com.yehsung.aingcheck.core.rules.character.gift.CharacterGiftClaimOutcome.needsUpdate) { it }, sheet.notice)
        assertNotNull(h.store.cakeGift)
        h.store.dismissCakeGiftSheet()
        advanceUntilIdle()
        assertTrue(h.store.showsCakeGiftReopen, "닫으면 같은 선물이 다시 열기 줄로 남는다")
        assertEquals(1, h.server.count("character_gift_pending"), "결론이 안 났으니 다음 선물을 묻지 않는다")
        assertEquals(0, h.store.cakeGiftFollowUps)
        h.assertClean()
    }

    @Test
    fun claimFailureShowsTheDrinkCopyLineAndRetriesWithTheSameChoice() = runTest {
        var offline = true
        val h = MeHarness(this, drawable = android) { r ->
            when (r.rpcName) {
                "character_gift_pending" -> MeReply.Json(drinkPending())
                "claim_character_gift" -> if (offline) MeReply.Offline else MeReply.Json("""{"status":"ok","character_id":"$ISUL","replayed":true}""")
                "shop_state" -> MeReply.Json(shop(setOf(ISUL)))
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadCakeGift() }
        advanceUntilIdle()
        h.store.confirmCakeGift()
        advanceUntilIdle()
        assertEquals(DrinkGiftText.claimFailed, h.store.cakeGiftSheet!!.notice)
        assertEquals(ISUL, h.store.cakeGiftSheet!!.selection, "같은 선택으로 다시 누르면 된다(replayed)")
        offline = false
        h.store.confirmCakeGift()
        advanceUntilIdle()
        assertEquals(MeCakeGiftSheet.Phase.Received(ISUL), h.store.cakeGiftSheet!!.phase)
        h.assertClean()
    }

    @Test
    fun unknownKindOrADrinkGiftAtFourIsNoGift() = runTest {
        // 모르는 종류(서버 CHECK 밖) → 이 빌드가 열 수 없는 선물 = 없음. 번호 4(데스크톱)에 술 선물이 섞여 와도 = 없음(받을 수 없는 창을 안 띄운다).
        for ((drawable, json) in listOf(
            android to """{"status":"ok","gift":{"id":"g9","kind":"beer","options":["$ISUL"]}}""",
            desktop to drinkPending(),
        )) {
            val h = MeHarness(this, drawable = drawable) { r -> if (r.rpcName == "character_gift_pending") MeReply.Json(json) else null }
            h.signIn()
            h.store.launch { h.store.loadCakeGift() }
            advanceUntilIdle()
            assertEquals(1, h.server.count("character_gift_pending"))
            assertNull(h.store.cakeGift, json)
            assertNull(h.store.cakeGiftSheet)
            h.assertClean()
        }
    }

    @Test
    fun keylessGiftIsABirthdayAndABirthdayOfferNeverCarriesIsul() = runTest {
        // kind 키가 없는 옛 응답(p = 4 모양) → 생일. 생일 선물에 이슬이 섞여 와도 버린다(설계서 §2 — 생일 창에 이슬이 서지 않는다).
        val json = """{"status":"ok","gift":{"id":"g3","options":["$ISUL","aing_cake_strawberry"]}}"""
        val h = MeHarness(this, drawable = android) { r -> if (r.rpcName == "character_gift_pending") MeReply.Json(json) else null }
        h.signIn()
        h.store.launch { h.store.loadCakeGift() }
        advanceUntilIdle()
        val gift = assertNotNull(h.store.cakeGift)
        assertEquals(CharacterGiftKind.birthday, gift.kind)
        assertEquals(listOf("aing_cake_strawberry"), gift.options)
        h.assertClean()
    }

    @Test
    fun desktopBirthdayFlowAsksNoFollowUp() = runTest {
        // 번호 4 인 빌드엔 '다음 선물'이 없다 — 0.3.73 과 요청 수가 같다(조회 1 · 받기 1 · 상점 1).
        val h = MeHarness(this, drawable = desktop) { r ->
            when (r.rpcName) {
                "character_gift_pending" -> MeReply.Json(MeFixtures.fixture("rpc.character_gift_pending@demo-gift.json"))
                "claim_character_gift" -> MeReply.Json(MeFixtures.fixture("rpc.claim_character_gift.json"))
                "shop_state" -> MeReply.Json(shop(setOf("aing_cake_strawberry")))
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadCakeGift() }
        advanceUntilIdle()
        h.store.selectCakeGiftOption("aing_cake_strawberry")
        h.store.confirmCakeGift()
        advanceUntilIdle()
        h.store.dismissCakeGiftSheet()
        advanceUntilIdle()
        assertEquals(1, h.server.count("character_gift_pending"))
        assertEquals(0, h.store.cakeGiftFollowUps)
        assertEquals("4", protocolOf(h.server.bodies("claim_character_gift").single()))
        h.assertClean()
    }

    @Test
    fun anotherAccountsOwnershipNeverFiltersTheNextAccountsDrinkGift() = runTest {
        // 계정 경계(맥 검토 수리와 같은 함정): 앞 계정이 가진 이슬로 새 계정의 술 선물(선택지 하나)을 거르면 선물이 통째로 사라진다.
        var user = "user-1"
        val h = MeHarness(this, drawable = android) { r ->
            when (r.rpcName) {
                "shop_state" -> MeReply.Json(shop(if (user == "user-1") setOf(ISUL) else emptySet()))
                "character_gift_pending" -> MeReply.Json(if (user == "user-1") none else drinkPending())
                else -> null
            }
        }
        h.signIn("user-1")
        h.store.launch { h.store.loadShop() }
        advanceUntilIdle()
        assertTrue(h.store.isOwned(ISUL))
        h.sessionStore.signOut()
        h.store.reset()
        advanceUntilIdle()
        user = "user-2"
        h.signIn("user-2")
        h.store.launch { h.store.loadCakeGift() }
        advanceUntilIdle()
        assertFalse(h.store.isOwned(ISUL), "보유는 계정에 묶여 비워졌다")
        assertEquals(listOf(ISUL), h.store.cakeGift?.options, "새 계정의 술 선물이 산다")
        assertEquals(ISUL, h.store.cakeGiftSheet?.selection)
        h.assertClean()
    }

    @Test
    fun ownershipFilteringKeepsTheGiftKind() = runTest {
        // 보유로 거른 새 선물이 종류를 잃으면(생일로 읽히면) 이슬 선택지가 0 이 된다 — 맥이 고친 잠재 결함(검토 ISUL-3).
        // 지금 술 선물의 선택지는 언제나 이슬 하나라 스토어의 거름(unownedCakeGift · 시트 맞추기)은 '그대로' 아니면 '없음'으로 끝나고, 새 선물을
        // 만드는 갈래를 술 선물로는 타지 않는다(잠재 결함 방지). 그래서 그 갈래가 지나는 한 곳(CharacterGiftOffer.narrowed)을 술 선물로 직접 잰다 —
        // 종류를 빼면 이 단언이 빨강이다(수리 전 뮤턴트: 스토어 두 자리에서 kind 를 빼도 이 시험 · MeCakeGiftShopTest 가 초록이었다).
        val drink = com.yehsung.aingcheck.core.wire.gift.CharacterGiftOffer("g1", listOf(ISUL), note = "한잔", kind = CharacterGiftKind.drink)
        val narrowed = drink.narrowed(listOf(ISUL))
        assertEquals(CharacterGiftKind.drink, narrowed.kind, "줄인 새 선물도 술 선물이다")
        assertEquals(listOf(ISUL), narrowed.options, "종류를 잃으면 생일로 다시 걸러 이슬 선택지가 사라진다")
        assertEquals(drink, narrowed, "id · 한 줄 · 시각도 그대로")
        val h = MeHarness(this, drawable = android) { r -> if (r.rpcName == "shop_state") MeReply.Json(shop(setOf("aing_cake_strawberry"))) else null }
        h.signIn()
        h.store.launch { h.store.loadShop() }
        advanceUntilIdle()
        assertTrue(drink === h.store.unownedCakeGift(drink), "가진 것이 선택지에 없으면 같은 값 그대로(새로 만들지 않는다)")
        val mixed = com.yehsung.aingcheck.core.wire.gift.CharacterGiftOffer("g2", listOf("aing_cake_strawberry", "aing_cake_choco"))
        val kept = assertNotNull(h.store.unownedCakeGift(mixed))
        assertEquals(CharacterGiftKind.birthday, kept.kind)
        assertEquals(listOf("aing_cake_choco"), kept.options, "생일은 줄인 새 선물(narrowed 갈래)")
        h.assertClean()
    }

    // 상점 · 고르기

    @Test
    fun isulIsALockedDrinkCellForEveryoneWithNoBuyGachaOrExchangePath() = runTest {
        val h = MeHarness(this, drawable = android) { r -> if (r.rpcName == "shop_state") MeReply.Json(shop()) else null }
        h.signIn()
        h.store.launch { h.store.loadShop() }
        advanceUntilIdle()
        assertTrue(ISUL in h.store.shopRows.map { it.id }, "잠긴 칸은 모두에게(안 가진 사람에게도) 선다 — 케이크와 같게")
        assertTrue(h.store.isGiftOnly(ISUL))
        assertFalse(h.store.isGachaOnly(ISUL), "뽑기 전용이 아니다(뽑기 · 조각 교환 길이 없다)")
        assertNull(h.store.price(ISUL), "살 수 있는 줄이 아니다(장식값 2002 를 사는 값으로 쓰지 않는다)")
        assertEquals(CharacterGiftKind.drink, h.store.giftKind(ISUL))
        assertEquals(CharacterGiftKind.birthday, h.store.giftKind("aing_cake_choco"))
        assertEquals(
            MeCharacterTileStatus.Content.Locked("술 한잔 선물 전용"),
            MeCharacterTileStatus.GiftOnly(h.store.giftKind(ISUL)).content,
        )
        assertEquals(MeCharacterTileStatus.Content.Locked("생일 선물 전용"), MeCharacterTileStatus.GiftOnly(h.store.giftKind("aing_cake_choco")).content)
        h.store.selectShopItem(ISUL)
        assertNull(h.store.shopSelection, "사기 단추가 서지 않는다")
        assertEquals(DrinkGiftText.lockedHint, h.store.shopNotice)
        assertEquals(ISUL, h.store.shopGiftHintID)
        assertFalse(h.store.canConfirmPurchase)
        assertNull(h.store.shopGachaHintID)
        assertFalse(ISUL in h.store.pickerIDs, "안 가진 선물 전용은 고르기 목록에 서지 않는다")
        h.store.chooseCharacter(ISUL)
        assertEquals(DrinkGiftText.lockedHint, h.store.characterNotice, "고르기 안전망도 종류 글자")
        assertEquals(0, h.server.count("set_character"))
        assertEquals(0, h.server.count("buy_character"))
        h.assertClean()
    }

    @Test
    fun desktopFoldsAWornIsulToAingLike0373AndroidKeepsIt() = runTest {
        // 검토 ISUL-1: 서버는 번호 5 미만에게 이슬 행을 **가진 사람에게도** 싣지 않는다(20261108122000 §5-2). 그 설계 전제가 '옛 클라는 모르는
        // 착용 id 를 아잉으로 접는다'이다. 공용 카드 표에 이슬이 들어간 뒤에도 데스크톱(Windows v1 · 번호 4)의 나 탭은 0.3.73 처럼 아잉으로 접어야
        // 한다 — 안 접으면 '착용 중'인 잠긴 이슬 칸이 서고, 누르면 "술 한잔 선물로만…" 안내가 뜨며, 다른 캐릭터로 바꾸면 다시 고를 길이 없다.
        for ((drawable, isDesktop) in listOf(desktop to true, android to false)) {
            val h = MeHarness(this, drawable = drawable) { r ->
                when {
                    r.rpcName == "shop_state" -> MeReply.Json(shop(setOf(ISUL), isulRow = !isDesktop))
                    r.method == "GET" && r.path == "/rest/v1/profiles" -> MeReply.Json("""[{"character":"$ISUL"}]""")
                    else -> null
                }
            }
            h.signIn()
            h.store.launch { h.store.loadShop() }
            h.store.launch { h.store.loadEquippedCharacter() }
            advanceUntilIdle()
            val label = if (isDesktop) "데스크톱" else "Android"
            assertEquals(ISUL, h.store.equippedServerID, "$label: 서버 착용값은 원문 그대로 쥔다(건드리지 않는다)")
            assertTrue(h.store.equippedLoaded)
            if (isDesktop) {
                assertEquals("aing", h.store.equippedCharacterID, "데스크톱: 이슬 착용값 = 아잉(0.3.73 과 같다)")
                assertTrue(h.store.isWearing("aing"), "데스크톱: 아잉 칸이 '착용 중'")
                assertFalse(h.store.isWearing(ISUL))
                assertFalse(ISUL in h.store.pickerIDs, "데스크톱: 고르기 목록에 이슬 칸이 서지 않는다(잠긴 '착용 중' 칸 없음)")
                assertFalse(ISUL in h.store.shopRows.map { it.id }, "데스크톱: 상점에도 이슬 칸이 없다(서버가 안 싣는다)")
            } else {
                assertEquals(ISUL, h.store.equippedCharacterID, "Android: 이슬을 입은 그대로 선다")
                assertTrue(h.store.isWearing(ISUL))
                assertTrue(ISUL in h.store.pickerIDs, "Android: 가진 이슬은 고르기 목록에 선다")
            }
            h.assertClean()
        }
    }

    @Test
    fun placeholderRowsShowIsulOnlyWhereThePlatformDrawsIt() = runTest {
        // 상점을 아직 못 읽었을 때의 자리표시: Android(번호 5)는 이슬 잠긴 칸을 세우고, 데스크톱(번호 4 — 서버가 이슬 행을 안 보낸다)은 세우지 않는다.
        for ((drawable, shows) in listOf(android to true, desktop to false)) {
            val h = MeHarness(this, drawable = drawable) { r -> if (r.rpcName == "shop_state") MeReply.Offline else null }
            h.signIn()
            h.store.launch { h.store.loadShop() }
            advanceUntilIdle()
            assertTrue(h.store.shopState.hasFailed)
            assertEquals(shows, ISUL in h.store.shopRows.map { it.id }, "drawable ${drawable.size}")
            assertTrue("aing_cake_choco" in h.store.shopRows.map { it.id }, "케이크 자리표시는 그대로")
            h.assertClean()
        }
    }

    private companion object {
        const val ISUL = "aing_isul"
        const val DRINK_GIFT = "d0000000-0000-4000-8000-00000015a001"
        const val CAKE_GIFT = "d0000000-0000-4000-8000-0000000c4e02"
    }
}
