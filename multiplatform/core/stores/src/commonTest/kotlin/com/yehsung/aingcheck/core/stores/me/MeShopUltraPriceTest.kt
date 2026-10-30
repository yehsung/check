// 원본: Sources/check/WorkTimerStoreAuth.swift 620-625(applyShopState — `if let price = state.ultraPrice { ultraPrice = price }`) @ 35649bee
// W3-c3 수정 공용 패치: 데스크톱 울트라 구매 화면이 읽는 값. 픽스처는 합성.
package com.yehsung.aingcheck.core.stores.me

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

@OptIn(ExperimentalCoroutinesApi::class)
class MeShopUltraPriceTest {
    @Test
    fun shopStateCarriesUltraPriceEvenWithoutCharacterRowsAndNullKeepsTheLastValue() = runTest {
        val replies = ArrayDeque(listOf("""{"ruby_balance":120,"ultra_price":30}""", """{"ruby_balance":120}"""))
        val h = MeHarness(this) { r -> if (r.rpcName == "shop_state") MeReply.Json(replies.removeFirstOrNull() ?: "{}") else null }
        h.signIn()
        assertNull(h.store.ultraPrice, "읽기 전에 값을 지어냈다")
        h.store.launch { h.store.loadShop() }
        advanceUntilIdle()
        assertEquals(30L, h.store.ultraPrice, "characters 없는 응답의 ultra_price 를 버렸다")
        h.store.launch { h.store.loadShop() }
        advanceUntilIdle()
        assertEquals(30L, h.store.ultraPrice, "ultra_price 가 빠진 응답이 아는 값을 지웠다")
    }
}
