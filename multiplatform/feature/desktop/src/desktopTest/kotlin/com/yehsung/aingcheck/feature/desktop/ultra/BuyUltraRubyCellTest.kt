// 원본: Sources/check/WorkTimerStoreAuth.swift 805-846(buyUltra) · Sources/check/WorkTimerStore.swift 822-826(rubyBalance didSet serial) @ a90d8623
package com.yehsung.aingcheck.feature.desktop.ultra

import com.yehsung.aingcheck.core.stores.me.RubyBalanceCell
import com.yehsung.aingcheck.feature.desktop.work.InMemoryDesktopWorkState
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull

/** U5 buy_ultra 결과는 서버 값으로 — 루비 칸은 **하나**(RubyBalanceMirror)이고 쓸 때마다 serial +1. */
class BuyUltraRubyCellTest {
    private class Rig(scope: TestScope, vararg replies: Reply, ruby: Long? = 50, price: Long? = 10) {
        val clock = TestClock()
        val server = FakeServer(scope).on("POST", BUY_PATH, *replies)
        val host = FakeSessionHost(server.service(clock::now))
        val cell = RubyBalanceCell(ruby)
        val wallet = UltraWalletStore(host, InMemoryDesktopWorkState(), SwiftRuleLapJudgment(), {}, scope, clock::now,
            initial = UltraWalletState(balance = 1))
        var mutations = 0
        val purchase = UltraPurchase(host, cell, wallet, scope, { price }) { mutations += 1 }
    }

    @Test
    fun okWritesServerValuesIntoTheOneRubyCell() = runTest {
        val rig = Rig(this, Reply.Json("""{"status":"ok","ultra_balance":2,"ruby_balance":40,"unit":10,"count":1}"""))
        val before = rig.cell.rubyWriteSerial
        rig.purchase.buy(1)
        advanceUntilIdle()
        assertEquals(40L, rig.cell.rubyBalance, "서버가 준 잔액(클라가 50-10 을 계산하지 않는다)")
        assertEquals(before + 1, rig.cell.rubyWriteSerial, "루비 칸에 한 번 썼다")
        assertEquals(2L, rig.wallet.state.value.balance)
        assertEquals("울트라 1개를 샀어요!", rig.purchase.notice.value)
        assertEquals(1, rig.mutations)
        assertFalse(rig.purchase.isPurchasing.value)
        assertEquals("""{"p_count":1}""", rig.server.calls.single().body)
    }

    @Test
    fun noRubyInResponseDoesNotTouchTheCell() = runTest {
        val rig = Rig(this, Reply.Json("""{"status":"ok","ultra_balance":3}"""))
        val before = rig.cell.rubyWriteSerial
        rig.purchase.buy(1)
        advanceUntilIdle()
        assertEquals(before, rig.cell.rubyWriteSerial, "모르는 값은 쓰지 않는다(serial 그대로)")
        assertEquals(50L, rig.cell.rubyBalance)
        assertEquals(3L, rig.wallet.state.value.balance)
    }

    @Test
    fun insufficientUsesServerNeedHaveThenPriceFallback() = runTest {
        val rig = Rig(this, Reply.Json("""{"status":"insufficient","need":30,"have":12,"ruby_balance":12}"""), Reply.Json("""{"status":"insufficient"}"""))
        rig.purchase.buy(3)
        advanceUntilIdle()
        assertEquals("루비 18개 더 필요해요", rig.purchase.notice.value)
        assertEquals(12L, rig.cell.rubyBalance)
        // 서버가 need/have 를 안 주면: need = 값 × 개수, have = (방금 적은) 칸의 잔액.
        rig.purchase.buy(2)
        advanceUntilIdle()
        assertEquals("루비 8개 더 필요해요", rig.purchase.notice.value)
        assertEquals(1L, rig.wallet.state.value.balance, "울트라 잔량은 서버가 말할 때만")
    }

    @Test
    fun otherStatusAndTransportFailureSayPurchaseFailed() = runTest {
        val rig = Rig(this, Reply.Json("""{"status":"invalid","max":10}"""), Reply.Offline)
        rig.purchase.buy(11)
        advanceUntilIdle()
        assertEquals(UltraPurchase.FAILED, rig.purchase.notice.value)
        rig.purchase.clearNotice()
        rig.purchase.buy(1)
        advanceUntilIdle()
        assertEquals(UltraPurchase.FAILED, rig.purchase.notice.value)
        assertFalse(rig.purchase.isPurchasing.value)
    }

    @Test
    fun oneAtATimeAndStaleGenerationDropped() = runTest {
        val rig = Rig(this, Reply.Json("""{"status":"ok","ultra_balance":2,"ruby_balance":40}"""))
        rig.purchase.buy(1)
        assertNull(rig.purchase.buy(1), "사는 중엔 두 번째를 받지 않는다")
        rig.host.sessionGeneration += 1
        advanceUntilIdle()
        assertEquals(1, rig.server.calls.size)
        assertEquals(50L, rig.cell.rubyBalance, "떠난 세대의 응답은 버린다")
        assertNull(rig.purchase.notice.value)
        assertFalse(rig.purchase.isPurchasing.value)
    }
}
